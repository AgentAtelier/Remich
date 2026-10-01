extends Node

## Phase 2, step 1 clock proof (docs/PLAN.md, phase 2, step 1: "one clock").
##
## Runs after the day harness (autoload order: DayProbe defers first, this
## probe second) and proves, inside pinned Godot, that the REAL shared clock
## is there and is the day's clock:
##
##   1. `RemichWorldClock` is a real registered GDExtension class;
##   2. the one shared node (`WorldClock` autoload) is initialized and reports
##      the staged revision — a stale library cannot pass;
##   3. `pulse` takes zero arguments: no float delta can decide the tick;
##   4. when the day ran in this process, the shared clock IS at the day's
##      final tick and at the run's requested speed — the day's scorer calls
##      read this very clock, not a private copy;
##   5. pause: pulses emit nothing and the tick does not move, speed intact;
##   6. resume: continues at exactly the next integer tick;
##   7. speed 4: four consecutive ticks per pulse, with the intermediate
##      ticks present (8 -> 12 cannot hide 9, 10, 11, 12);
##   8. the fixed tick length is exactly the test project's declared value.
##
## One machine-checkable line: `REMICH_CLOCK_OK tick=... speed=... paused=...`.
## Fails with `REMICH_CLOCK_FAIL reason=...` and exit code 1.
##
## The probe only runs when `godot/clock_probe_expectation.txt` exists, which
## `tools/stage_clock.sh` writes from the Rust source. Unstaged runs stay
## exactly as quiet as they were before this step.

const CLOCK_CLASS := "RemichWorldClock"
const CLOCK_AUTOLOAD := "WorldClock"
const EXPECTATION_FILE := "res://clock_probe_expectation.txt"
const OK_MARKER := "REMICH_CLOCK_OK"
const FAIL_MARKER := "REMICH_CLOCK_FAIL"

const TRACE_ENV := "REMICH_DAY_TRACE_PATH"
const SPEED_ENV := "REMICH_CLOCK_SPEED"
const DAY_FINAL_TICK := 240

const REQUIRED_CALLABLES := [
	"initialize", "is_initialized", "tick", "tick_length_ns", "speed",
	"set_speed", "pause", "resume", "is_paused", "pulse", "reset",
	"cycle_position", "clock_bridge_rev",
]


func _ready() -> void:
	var expected := _read_expectation()
	if expected.is_empty():
		# Not staged: this probe does not exist for ordinary runs.
		return
	call_deferred("_run", expected)


func _run(expected: String) -> void:
	# 1. a real registered class with the real callables
	if not ClassDB.class_exists(CLOCK_CLASS):
		_fail("extension-not-loaded", CLOCK_CLASS + " is not registered in ClassDB")
		return
	for method_name in REQUIRED_CALLABLES:
		if not ClassDB.class_has_method(CLOCK_CLASS, method_name):
			_fail("callable-missing", CLOCK_CLASS + "." + method_name + " does not exist")
			return

	# 2. the single shared node
	if not WorldClock.is_ready():
		_fail("shared-missing", "the " + CLOCK_AUTOLOAD
			+ " autoload holds no initialized " + CLOCK_CLASS)
		return
	var revision := WorldClock.bridge_rev()
	if revision != expected:
		_fail("rev-mismatch", "Godot observed " + revision
			+ " but the Rust source expects " + expected)
		return

	# 3. pulse takes no arguments: nothing like a delta can drive a tick
	var pulse_args := _method_args(CLOCK_CLASS, "pulse")
	if not pulse_args.is_empty():
		_fail("pulse-args", "%s.pulse takes %d argument(s); a tick must never be derived from a delta" % [
			CLOCK_CLASS, pulse_args.size()])
		return
	var tick_args := _method_args(CLOCK_CLASS, "tick")
	if not tick_args.is_empty():
		_fail("tick-args", "%s.tick must take no arguments" % CLOCK_CLASS)
		return

	# 4. the day drove THIS clock (only when a day ran in this process)
	var day_active := not OS.get_environment(TRACE_ENV).is_empty()
	var run_speed := _run_speed()
	if run_speed < 1:
		_fail("bad-speed-env", SPEED_ENV + " is not a positive integer")
		return
	var snapshot_tick := WorldClock.tick()
	var snapshot_speed := WorldClock.speed()
	var snapshot_paused := WorldClock.is_paused()
	if day_active:
		if snapshot_tick != DAY_FINAL_TICK:
			_fail("day-not-shared", "the shared clock is at %d after the day, expected its final tick %d — the day did not drive this clock" % [
				snapshot_tick, DAY_FINAL_TICK])
			return
		if snapshot_speed != run_speed:
			_fail("day-speed", "the shared clock runs at speed %d, the run asked for %d" % [
				snapshot_speed, run_speed])
			return
		if snapshot_paused:
			_fail("day-left-paused", "the day finished with the shared clock paused")
			return
	else:
		if snapshot_tick != 0:
			_fail("not-fresh", "no day ran, yet the shared clock is at %d, expected 0" % snapshot_tick)
			return

	# 5. pause: no tick moves, the speed is retained
	var speed_before := snapshot_speed
	var pause_result := WorldClock.pause()
	if not bool(pause_result.get("ok", false)):
		_fail("pause-refused", str(pause_result.get("error")))
		return
	var held := WorldClock.tick()
	for _i in 3:
		var paused_batch: Array = WorldClock.pulse()
		if not paused_batch.is_empty():
			_fail("paused-emitted", "a paused pulse emitted %s" % [paused_batch])
			return
		if WorldClock.tick() != held:
			_fail("paused-advanced", "the tick moved while paused: %d -> %d" % [
				held, WorldClock.tick()])
			return
	if WorldClock.speed() != speed_before:
		_fail("speed-lost", "pausing changed the speed: %d -> %d" % [
			speed_before, WorldClock.speed()])
		return

	# 6. resume at speed 4: four consecutive ticks, then four more
	if not bool(WorldClock.set_speed(4).get("ok", false)):
		_fail("set-speed", "speed 4 was refused")
		return
	if not bool(WorldClock.resume().get("ok", false)):
		_fail("resume", "resume was refused")
		return
	var first_batch: Array = WorldClock.pulse()
	if not _same_ints(first_batch, [held, held + 1, held + 2, held + 3]):
		_fail("speed4-not-consecutive", "first speed-4 pulse gave %s, expected four consecutive ticks from %d" % [
			_join(first_batch), held])
		return
	if WorldClock.tick() != held + 4:
		_fail("speed4-tick", "after one speed-4 pulse the tick is %d, expected %d" % [
			WorldClock.tick(), held + 4])
		return
	var second_batch: Array = WorldClock.pulse()
	if not _same_ints(second_batch, [held + 4, held + 5, held + 6, held + 7]):
		_fail("speed4-gap", "second speed-4 pulse gave %s, expected it to continue at %d" % [
			_join(second_batch), held + 4])
		return

	# pause again at speed 4: still nothing moves
	if not bool(WorldClock.pause().get("ok", false)):
		_fail("pause", "the second pause was refused")
		return
	var held2 := WorldClock.tick()
	var blocked: Array = WorldClock.pulse()
	if not blocked.is_empty() or WorldClock.tick() != held2:
		_fail("pause2", "the clock advanced while paused: %d -> %d" % [
			held2, WorldClock.tick()])
		return

	# resume at speed 1: exactly the next tick, one per pulse
	if not bool(WorldClock.set_speed(1).get("ok", false)):
		_fail("set-speed", "speed 1 was refused")
		return
	if not bool(WorldClock.resume().get("ok", false)):
		_fail("resume", "the second resume was refused")
		return
	var single: Array = WorldClock.pulse()
	if not _same_ints(single, [held2]):
		_fail("speed1", "a speed-1 pulse gave %s, expected exactly [%d]" % [
			_join(single), held2])
		return

	# 8. the fixed tick length is exactly the test project's declared value
	if WorldClock.tick_length_ns() != WorldClock.TEST_TICK_LENGTH_NS:
		_fail("tick-length", "the shared clock reports tick_length_ns=%d, the test project declares %d" % [
			WorldClock.tick_length_ns(), WorldClock.TEST_TICK_LENGTH_NS])
		return

	print("%s tick=%d speed=%d paused=%s tick_length_ns=%d rev=%s shared_instance=%d pulse_args=0 day_final_tick=%s pause_held=%d resume_batch=%s speed4_second=%s speed1_batch=%s" % [
		OK_MARKER,
		snapshot_tick,
		snapshot_speed,
		"true" if snapshot_paused else "false",
		WorldClock.tick_length_ns(),
		revision,
		WorldClock.clock_instance_id(),
		str(DAY_FINAL_TICK) if day_active else "none",
		held,
		_join(first_batch),
		_join(second_batch),
		_join(single),
	])


# --- helpers -----------------------------------------------------------------

func _run_speed() -> int:
	var raw := OS.get_environment(SPEED_ENV)
	if raw.is_empty():
		return 1
	if not raw.is_valid_int():
		return -1
	return int(raw)


## The declared argument list of a method, via the engine's own reflection.
func _method_args(cls: String, method: String) -> Array:
	for entry in ClassDB.class_get_method_list(cls):
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		if str(entry.get("name", "")) == method:
			var args: Variant = entry.get("args", [])
			return args if typeof(args) == TYPE_ARRAY else []
	return []


func _same_ints(observed: Array, expected: Array) -> bool:
	if observed.size() != expected.size():
		return false
	for index in observed.size():
		if int(observed[index]) != int(expected[index]):
			return false
	return true


func _join(ticks: Array) -> String:
	var parts: PackedStringArray = []
	for tick in ticks:
		parts.append(str(int(tick)))
	return ",".join(parts)


func _read_expectation() -> String:
	if not FileAccess.file_exists(EXPECTATION_FILE):
		return ""
	var file := FileAccess.open(EXPECTATION_FILE, FileAccess.READ)
	if file == null:
		return ""
	return file.get_as_text().strip_edges()


func _fail(reason: String, detail: String) -> void:
	print(FAIL_MARKER + " reason=" + reason + " detail=" + detail)
	get_tree().quit(1)
