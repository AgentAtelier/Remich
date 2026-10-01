extends Node

## Phase 2, step 2 weather proof (docs/PLAN.md, phase 2, step 2: "one weather
## snapshot").
##
## Runs last in the autoload chain, so a weather failure cannot be masked by
## an earlier probe's successful `quit(0)` — Godot honours the **last**
## `quit()` it sees, and this probe defers behind every other one. Inside
## pinned Godot it proves the whole Step 2 path, end to end:
##
##   1. `RemichWeather` is a real registered GDExtension class with the
##      real callables, and it exposes **no** setter for weather values;
##   2. the one shared node (`Weather` autoload) is initialized, holds
##      exactly ONE native weather object in the scene tree, and reports the
##      staged revision — a stale library cannot pass;
##   3. the channel starts owned by the stand-in driver, with no snapshot
##      yet, and the project declares `grengewald_wind` as `vec4` with the
##      pinned Grengewald default;
##   4. the shared `WorldClock` is the only clock: this probe resets it,
##      pulses it, and drives weather from **those** integer ticks;
##   5. on every driven tick: drive the stand-in -> read the snapshot back ->
##      snapshot tick == the world-clock tick that drove it -> apply the
##      wind global -> read the applied vector back and compare it against
##      the snapshot (X/Y/Z), with W in the documented presentation range;
##   6. a **second writer is refused from the engine side**, against the live
##      snapshot: the claim comes back `writer-conflict`, naming both
##      writers, and neither the owner nor the last valid snapshot changes;
##   7. morning is the fixture's calm state and afternoon its windy state;
##   8. every record is written as JSON Lines, byte-for-byte reproducible for
##      a fixed seed (`tools/check_weather_trace.py` re-derives it).
##
## Failure prints `REMICH_WEATHER_FAIL reason=...` and exits non-zero.
##
## ## The wind global and the runtime getter
##
## Grengewald's pinned contract documents that runtime global getters are
## editor-only in the compatibility backend, so this probe never reads the
## global back through a getter. The write path is established the four ways
## the step asks for: the declared name/type/default (checked against
## ProjectSettings), the binding's real `RenderingServer` setter (checked in
## Rust source), the exact vector the binding recorded passing, and this
## probe's per-tick comparison of that recorded vector against the snapshot.

const WEATHER_CLASS := "RemichWeather"
const EXPECTATION_FILE := "res://weather_probe_expectation.txt"
const TRACE_ENV := "REMICH_WEATHER_TRACE_PATH"
const OK_MARKER := "REMICH_WEATHER_OK"
const FAIL_MARKER := "REMICH_WEATHER_FAIL"

## The pinned Grengewald contract (docs/GODOT.md at the pinned commit):
## one game-owned shader global of this name, type and default.
const WIND_GLOBAL := "grengewald_wind"
const WIND_GLOBAL_TYPE := "vec4"
const WIND_GLOBAL_DEFAULT := Vector4(1, 0, 0, 0)

## The one stand-in driver's writer identity (`remich_core::weather`).
const STAND_IN_WRITER := "stand-in-weather-schedule"

## Callables the native class must actually have.
const REQUIRED_CALLABLES: Array[String] = [
	"initialize", "is_initialized", "drive", "snapshot", "writer_id",
	"writer_status", "try_claim_writer", "apply_wind", "last_applied_wind",
	"weather_bridge_rev", "seed", "cycle_length",
]

## Methods that must NOT exist: there is no weather mutation that bypasses
## the one-writer rule.
const FORBIDDEN_CALLABLES: Array[String] = [
	"set_wind", "set_wind_direction", "set_wind_strength", "set_rain",
	"set_temperature", "set_light", "set_snapshot", "set_tick", "publish",
]

## The fixture's broad stand-in shape, as ranges (not a float table):
## calm morning (<= 0.1), windy afternoon (>= 0.5).
const CALM_MAX := 0.1
const WINDY_MIN := 0.5

## Tolerance for comparing a snapshot value against the vector actually
## handed to the setter: Godot's `vec4` is 32-bit, the snapshot's f64 is
## converted once at that edge.
const VECTOR_TOLERANCE := 0.000001
## Tolerance for re-deriving the presentation phase (f32 rounding on top of
## the same double-precision formula).
const PHASE_TOLERANCE := 0.0001

var _trace_path := ""


func _ready() -> void:
	_trace_path = OS.get_environment(TRACE_ENV)
	if _trace_path.is_empty():
		# Ordinary runs (and the day runs of Step 1) never ask for a weather
		# trace: this probe does not exist for them.
		return
	call_deferred("_run")


func _run() -> void:
	# --- 1. a real registered class with the real callables ------------------
	if not ClassDB.class_exists(WEATHER_CLASS):
		_fail("extension-not-loaded", WEATHER_CLASS + " is not registered in ClassDB")
		return
	for method_name in REQUIRED_CALLABLES:
		if not ClassDB.class_has_method(WEATHER_CLASS, method_name):
			_fail("callable-missing", WEATHER_CLASS + "." + method_name + " does not exist")
			return
	for method_name in FORBIDDEN_CALLABLES:
		if ClassDB.class_has_method(WEATHER_CLASS, method_name):
			_fail("unrestricted-mutation", WEATHER_CLASS + "." + method_name + " would bypass the one-writer rule")
			return

	var expected := _read_expectation()
	if expected.is_empty():
		_fail("not-staged", "could not read " + EXPECTATION_FILE + " (run tools/stage_weather.sh)")
		return

	# --- 2. the one shared node ---------------------------------------------
	if not Weather.is_ready():
		_fail("shared-missing", "the Weather autoload holds no initialized " + WEATHER_CLASS)
		return
	var revision := Weather.bridge_rev()
	if revision != expected:
		_fail("rev-mismatch", "the engine observed " + revision + " but the Rust source expects " + expected)
		return
	var native_count := _count_native()
	if native_count != 1:
		_fail("not-shared", "%d %s objects are in the scene tree, expected exactly 1" % [
			native_count, WEATHER_CLASS])
		return

	# --- 3. ownership and the declared global --------------------------------
	var status := Weather.writer_status()
	if not bool(status.get("owned", false)):
		_fail("unowned", "the weather channel has no writer")
		return
	if str(status.get("writer", "")) != STAND_IN_WRITER:
		_fail("wrong-writer", "the channel is owned by '%s', expected '%s'" % [
			str(status.get("writer", "")), STAND_IN_WRITER])
		return
	if bool(status.get("has_snapshot", false)):
		_fail("premature-snapshot", "nothing has driven the weather, yet a snapshot exists (tick %d)" % [
			int(status.get("snapshot_tick", -1))])
		return
	var declared: Variant = ProjectSettings.get_setting("shader_globals/" + WIND_GLOBAL, null)
	if declared == null:
		_fail("global-undeclared", "ProjectSettings declares no shader_globals/" + WIND_GLOBAL)
		return
	if typeof(declared) != TYPE_DICTIONARY:
		_fail("global-shape", "shader_globals/" + WIND_GLOBAL + " is " + type_string(typeof(declared)) + ", expected a {type,value} dictionary")
		return
	if str(declared.get("type", "")) != WIND_GLOBAL_TYPE:
		_fail("global-type", "the declared type is '%s', expected '%s'" % [
			str(declared.get("type", "")), WIND_GLOBAL_TYPE])
		return
	if declared.get("value") != WIND_GLOBAL_DEFAULT:
		_fail("global-default", "the declared default is %s, expected %s" % [
			str(declared.get("value")), str(WIND_GLOBAL_DEFAULT)])
		return

	# --- 4. the one clock drives this weather --------------------------------
	if not WorldClock.is_ready():
		_fail("clock-missing", "the WorldClock autoload holds no initialized clock")
		return
	var cycle := Weather.cycle_length()
	if cycle <= 1:
		_fail("bad-cycle", "the stand-in cycle length is %d" % cycle)
		return
	var seed := Weather.stand_in_seed()
	if seed < 0:
		_fail("bad-seed", "the stand-in seed is %d" % seed)
		return
	WorldClock.reset(0)
	if not bool(WorldClock.set_speed(1).get("ok", false)):
		_fail("clock-speed", "the shared clock refused speed 1")
		return
	WorldClock.resume()
	if WorldClock.tick() != 0:
		_fail("clock-not-reset", "the shared clock is at %d after reset" % WorldClock.tick())
		return

	# --- 5. one full fixture cycle, tick by tick -----------------------------
	var half := cycle - cycle / 2
	var morning_max := -1.0
	var afternoon_min := 2.0
	var morning_ticks := 0
	var afternoon_ticks := 0
	var records: Array[String] = []
	var instance_before := Weather.weather_instance_id()

	while WorldClock.tick() < cycle:
		var batch: Array = WorldClock.pulse()
		if batch.is_empty():
			_fail("clock-stalled", "the shared clock is at %d and emitted nothing" % WorldClock.tick())
			return
		for tick in batch:
			var driven: Dictionary = Weather.drive(tick)
			if not bool(driven.get("ok", false)):
				_fail("drive-refused", str(driven.get("error", "")))
				return

			var snapshot: Dictionary = Weather.snapshot()
			if not bool(snapshot.get("ok", false)):
				_fail("snapshot-missing", "the drive succeeded but no snapshot reads back: %s" % [
					str(snapshot.get("error", ""))])
				return
			var snapshot_tick := int(snapshot.get("tick", -1))
			if snapshot_tick != tick:
				_fail("tick-mismatch", "snapshot tick %d != world-clock tick %d" % [snapshot_tick, tick])
				return

			var applied: Dictionary = Weather.apply_wind()
			if not bool(applied.get("ok", false)):
				_fail("apply-refused", str(applied.get("error", "")))
				return
			if int(applied.get("tick", -1)) != tick:
				_fail("apply-tick", "the wind write used tick %d, expected %d" % [
					int(applied.get("tick", -1)), tick])
				return
			var vector: Array = Weather.last_applied_wind()
			if vector.size() != 4:
				_fail("applied-missing", "the recorded wind vector has %d components" % vector.size())
				return
			if not _same_numbers(applied.get("applied", []), vector):
				_fail("applied-diverged", "the returned vector and the recorded vector disagree")
				return

			# X/Y/Z of the applied vector equal the snapshot (the engine's
			# 32-bit vec4 vs the snapshot's f64: one conversion at the edge).
			var strength := clampf(float(snapshot.get("wind_strength", -1.0)), 0.0, 1.0)
			if absf(float(vector[0]) - float(snapshot.get("wind_dir_x", NAN))) > VECTOR_TOLERANCE:
				_fail("wind-x", "applied X %s != snapshot direction X %s at tick %d" % [
					str(vector[0]), str(snapshot.get("wind_dir_x")), tick])
				return
			if absf(float(vector[1]) - float(snapshot.get("wind_dir_z", NAN))) > VECTOR_TOLERANCE:
				_fail("wind-y", "applied Y %s != snapshot direction Z %s at tick %d" % [
					str(vector[1]), str(snapshot.get("wind_dir_z")), tick])
				return
			if absf(float(vector[2]) - strength) > VECTOR_TOLERANCE:
				_fail("wind-z", "applied Z %s != snapshot strength %s at tick %d" % [
					str(vector[2]), str(snapshot.get("wind_strength")), tick])
				return

			# W: presentation phase, never weather. Derived from the integer
			# tick, inside [0, 2*PI).
			var phase := float(vector[3])
			if phase < 0.0 or phase >= TAU + PHASE_TOLERANCE:
				_fail("wind-w-range", "W is %s, outside [0, 2*PI)" % str(phase))
				return
			var expected_phase := float(tick % cycle) / float(cycle) * TAU
			if absf(phase - expected_phase) > PHASE_TOLERANCE:
				_fail("wind-w", "W is %s at tick %d, expected the tick-derived phase %s" % [
					str(phase), tick, str(expected_phase)])
				return

			# The broad stand-in shape: calm morning, windy afternoon.
			var wind_strength := float(snapshot.get("wind_strength", NAN))
			if tick < half:
				morning_max = maxf(morning_max, wind_strength)
				morning_ticks += 1
			else:
				afternoon_min = minf(afternoon_min, wind_strength)
				afternoon_ticks += 1

			records.append(JSON.stringify({
				"tick": tick,
				"snapshot_tick": snapshot_tick,
				"seed": seed,
				"wind_dir_x": float(snapshot.get("wind_dir_x")),
				"wind_dir_z": float(snapshot.get("wind_dir_z")),
				"wind_strength": wind_strength,
				"rain": float(snapshot.get("rain")),
				"temperature": float(snapshot.get("temperature")),
				"light": float(snapshot.get("light")),
				"wind_global": [float(vector[0]), float(vector[1]), float(vector[2]), phase],
				"weather_bridge_rev": revision,
			}, "", true))

	# --- 6. a second writer is refused against the live snapshot -------------
	# The channel now holds a real last-valid snapshot (tick 239): a distinct
	# second writer attempts a claim, is refused with the conflict named, and
	# neither the owner nor that snapshot may change.
	var snapshot_before := JSON.stringify(Weather.snapshot())
	var status_before := JSON.stringify(Weather.writer_status())
	var claim := Weather.try_claim_writer("intruder-weather-driver")
	if bool(claim.get("ok", true)):
		_fail("second-writer-accepted", "a distinct second writer was allowed to claim the channel")
		return
	if str(claim.get("code", "")) != "writer-conflict":
		_fail("wrong-refusal", "the second claim failed with code '%s', expected 'writer-conflict'" % [
			str(claim.get("code", ""))])
		return
	var conflict := "%s %s %s" % [
		str(claim.get("error", "")), str(claim.get("held_by", "")), str(claim.get("attempted", ""))]
	if not conflict.contains(STAND_IN_WRITER) or not conflict.contains("intruder-weather-driver"):
		_fail("conflict-unnamed", "the refusal must name both writers, got: " + conflict)
		return
	if Weather.writer_id() != STAND_IN_WRITER:
		_fail("owner-replaced", "the refused claim changed the owner to '%s'" % Weather.writer_id())
		return
	if JSON.stringify(Weather.snapshot()) != snapshot_before:
		_fail("snapshot-changed", "the refused claim changed the last valid snapshot")
		return
	if JSON.stringify(Weather.writer_status()) != status_before:
		_fail("status-changed", "the refused claim changed the channel's ownership status")
		return

	# --- 7. the cycle completed the way the fixture says ---------------------
	if WorldClock.tick() != cycle:
		_fail("clock-final", "the shared clock is at %d, expected its final tick %d" % [
			WorldClock.tick(), cycle])
		return
	if records.size() != cycle:
		_fail("record-count", "%d records for a %d-tick cycle" % [records.size(), cycle])
		return
	if morning_ticks + afternoon_ticks != cycle:
		_fail("half-count", "%d morning + %d afternoon ticks != %d" % [
			morning_ticks, afternoon_ticks, cycle])
		return
	if morning_max > CALM_MAX:
		_fail("morning-not-calm", "the morning's wind strength reached %s, expected <= %s" % [
			str(morning_max), str(CALM_MAX)])
		return
	if afternoon_min < WINDY_MIN:
		_fail("afternoon-not-windy", "the afternoon's wind strength fell to %s, expected >= %s" % [
			str(afternoon_min), str(WINDY_MIN)])
		return
	if Weather.weather_instance_id() != instance_before:
		_fail("instance-replaced", "the shared weather object changed during the run")
		return
	var final_status := Weather.writer_status()
	if str(final_status.get("writer", "")) != STAND_IN_WRITER:
		_fail("writer-lost", "the stand-in driver no longer owns the channel")
		return

	# --- the trace -------------------------------------------------------------
	if not _write_trace(records):
		return

	print("%s seed=%d ticks=%d writer=%s calm=%.6f windy=%.6f rev=%s" % [
		OK_MARKER,
		seed,
		records.size(),
		Weather.writer_id(),
		morning_max,
		afternoon_min,
		revision,
	])
	get_tree().quit(0)


# --- helpers -----------------------------------------------------------------

## The number of native weather objects in the scene tree: the shared node
## must be the only one.
func _count_native() -> int:
	var count := 0
	var stack: Array[Node] = [get_tree().root]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		if node.get_class() == WEATHER_CLASS:
			count += 1
		var children := node.get_children()
		for child in children:
			if child is Node:
				stack.append(child)
	return count


func _same_numbers(left: Variant, right: Variant) -> bool:
	if typeof(left) != TYPE_ARRAY or typeof(right) != TYPE_ARRAY:
		return false
	if left.size() != right.size():
		return false
	for index in left.size():
		if float(left[index]) != float(right[index]):
			return false
	return true


func _write_trace(records: Array) -> bool:
	var file := FileAccess.open(_trace_path, FileAccess.WRITE)
	if file == null:
		_fail("trace-unwritable", "could not open " + _trace_path)
		return false
	file.store_string("\n".join(records) + "\n")
	file.close()
	return true


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
