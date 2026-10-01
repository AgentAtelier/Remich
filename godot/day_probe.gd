extends Node

## Phase 1, step 5 day harness, running on Phase 2's one clock
## (docs/PLAN.md, phase 1, step 5 and phase 2, step 1).
##
## A stand-in inhabitant in Remich's own Godot project lives one test day
## through the Step 4 scorer, and writes the trace (time, needs, choice, scores)
## to a file. Nothing here is simulation: there is no action execution, no
## need refill, no movement, no schedule and no memory. A chosen activity in
## this harness means only:
##
##   at this point in the test day these were the caller-declared available
##   activities, and the existing Step 4 scorer chose this one.
##
## The day runs entirely through the real GDExtension — `score_activity` for
## every decision and `advance_time` for every step. GDScript never computes a
## score, and the state the next checkpoint uses is always the array Rust
## handed back.
##
## ## One clock (phase 2, step 1)
##
## Every temporal input of this day comes from the ONE shared clock — the
## `WorldClock` autoload, which holds the single native `RemichWorldClock`
## instance. This script keeps no tick counter and no second clock:
##
##   * the day's progression is the clock's own integer tick: each driver
##     pulse returns the ticks it made available, and every one of them is
##     processed in order (`WorldClock.pulse()`);
##   * the tick used for need advancement is the clock's tick;
##   * `time_of_day` is derived FROM that integer tick by the clock, with the
##     test fixture's explicit cycle length (`TEST_CYCLE_LENGTH`), never by a
##     checkpoint counter acting as another clock;
##   * speed is the clock's integer multiplier: a speed-4 run processes the
##     SAME consecutive ticks as a speed-1 run — only the number of driver
##     pulses differs, and no pulse- or speed-metadata enters the trace.
##
## ## The test-harness cycle (NOT a time authority)
##
## 24 checkpoints `0..23`, `time_of_day = checkpoint / 24.0`, checkpoint ticks
## `0, 10, 20, ... 230`, one `advance_time` across each 10-tick span, and a
## final tick of `240` once the day is complete.
##
## **240 ticks/cycle is a convention of this test harness only** — declared
## here as `CHECKPOINTS`, `TICKS_PER_CHECKPOINT`, `FINAL_TICK` and the explicit
## test cycle length `TEST_CYCLE_LENGTH`. It exists to make a compact,
## inspectable one day: 24 familiar hour-like checkpoints and exactly one
## already-qualified donor decay boundary between them. It is not a Remich,
## anvil, Munshausen, Eisleck or Larochette time authority, it is not added to
## the engine-free clock or scorer API as a global truth, and no other module
## may read it as one.
##
## ## Activation
##
## This autoload is silent and does nothing unless `REMICH_DAY_TRACE_PATH` is
## set to a file path. Steps 1-4 never set it, so ordinary runs are unaffected
## and `bridge_probe.gd` remains their final quit path. The driver speed comes
## from `REMICH_CLOCK_SPEED` (default `1`).
##
## ## Why the day is deferred
##
## Autoload `_ready` callbacks run in list order during startup, and Godot
## honours the **last** `quit()` it sees. Running the day inline here would let
## a later probe's successful `quit(0)` overwrite this probe's `quit(1)`, so the
## day runs on the first deferred call instead: after `BridgeProbe` has taken
## the success path, a failed day still ends the process non-zero. The clock
## proof (`clock_probe.gd`) defers after this one and therefore runs on the
## clock state the day left behind.

const TRACE_ENV := "REMICH_DAY_TRACE_PATH"
const SPEED_ENV := "REMICH_CLOCK_SPEED"
const SCORER_CLASS := "RemichScorer"
const SCORER_CALLABLES := ["score_activity", "advance_time", "scorer_bridge_rev"]
const OK_MARKER := "REMICH_DAY_OK"
const FAIL_MARKER := "REMICH_DAY_FAIL"

const TRACE_FORMAT := "remich-day-trace-v1"

# --- the fixed committed fixture ---------------------------------------------
# Seed and needs are the same values the Step 4 fixture commits, so the day
# starts from a result that has already been qualified in the engine.
const SEED := 60628
const INITIAL_NEEDS := [0.40, 0.35, 0.60, 0.50, 0.45, 0.42, 0.55]
const SKILLS := []
const SETTLEMENT_DAMAGE := 0.0
const SETTLEMENT_AGGREGATE_MOOD := 0.0

# Declared available at every checkpoint of this test day. There is no
# availability schedule: this harness does not invent one.
const ACTIVITIES := [
	{"id": 2, "place": "north-hills"},
	{"id": 1, "place": "east-field"},
	{"id": 16, "place": "market-square"},
	{"id": 14, "place": "cottage-loft"},
	{"id": 12, "place": "ridge"},
	{"id": 5, "place": "kitchen"},
]

const NEED_ORDER_NAMES := [
	"food", "water", "shelter", "safety", "sleep", "companionship", "joy",
]

# --- the test-harness cycle ---------------------------------------------------
const CHECKPOINTS := 24
const TICKS_PER_CHECKPOINT := 10
const FINAL_TICK := 240

# The explicit test-project cycle length the shared clock uses to derive
# time_of_day from an integer tick (`WorldClock.cycle_position(tick, 240)`).
# It equals this fixture's FINAL_TICK, so the qualified Phase 1 values
# (checkpoint / 24.0) are reproduced exactly. Test-project configuration —
# not a decision about any game's simulation rate.
const TEST_CYCLE_LENGTH := 240

const CLOCK_NOTE := (
	"240 ticks/day is a test-harness convention for this probe only; "
	+ "it is not a Remich, anvil, Munshausen, Eisleck or Larochette time authority.")


func _ready() -> void:
	var trace_path := OS.get_environment(TRACE_ENV)
	if trace_path.is_empty():
		# Steps 1-4 are running: stay completely silent and do no work.
		return
	call_deferred("_run_day", trace_path)


func _run_day(trace_path: String) -> void:
	# --- the one shared clock: configure it as this run's fixture ------------
	if not WorldClock.is_ready():
		_fail("clock-missing", "the WorldClock autoload holds no initialized clock")
		return
	var speed := _run_speed()
	if speed < 1:
		_fail("bad-speed", SPEED_ENV + " must be a positive integer")
		return
	for step: Array in [
		["reset", WorldClock.reset(0)],
		["set_speed", WorldClock.set_speed(speed)],
		["resume", WorldClock.resume()],
	]:
		if not bool(step[1].get("ok", false)):
			_fail("clock-setup", "%s: %s" % [step[0], str(step[1].get("error"))])
			return
	if WorldClock.tick() != 0:
		_fail("clock-start", "the shared clock starts at %d, expected tick 0" % WorldClock.tick())
		return

	var scorer := _open_scorer()
	if scorer == null:
		return

	var revision := str(scorer.call("scorer_bridge_rev"))
	if revision.is_empty():
		_fail("rev-missing", SCORER_CLASS + ".scorer_bridge_rev returned nothing")
		scorer.free()
		return

	var lines: Array[String] = []
	lines.append(JSON.stringify(_fixture_record()))

	var needs: Array = INITIAL_NEEDS.duplicate()
	var chosen_ids: Array[int] = []
	var first_chosen := {}
	var last_chosen := {}
	var decisions := 0

	# Every tick the shared clock makes available is processed, in order.
	# A decision happens exactly on the ticks divisible by 10 (the fixture's
	# checkpoints); the rest are ordinary simulation ticks the clock produced.
	# At speed 1 each pulse yields one tick, at speed 4 four consecutive ones —
	# the sequence of decisions is the same either way.
	while WorldClock.tick() < FINAL_TICK:
		var batch: Array = WorldClock.pulse()
		if batch.is_empty():
			if WorldClock.is_paused():
				_fail("clock-paused", "the shared clock is paused mid-day")
			else:
				_fail("no-progress", "a pulse of the shared clock made no tick available")
			scorer.free()
			return

		for tick_variant in batch:
			var tick := int(tick_variant)
			if tick % TICKS_PER_CHECKPOINT != 0 or tick >= FINAL_TICK:
				continue
			var checkpoint := tick / TICKS_PER_CHECKPOINT
			# Time of day, derived by the clock from the integer tick with the
			# test fixture's explicit cycle length. A negative value means the
			# clock refused the inputs; nothing is substituted.
			var time_of_day := WorldClock.cycle_position(tick, TEST_CYCLE_LENGTH)
			if time_of_day < 0.0:
				_fail("cycle-position", "the shared clock refused a cycle position at tick %d" % tick)
				scorer.free()
				return

			# 1-5: one real scorer call, recorded exactly as it came back.
			var scored: Variant = scorer.call(
				"score_activity", _score_input(needs, time_of_day))
			if typeof(scored) != TYPE_DICTIONARY:
				_fail("wrong-type", "score_activity returned "
					+ type_string(typeof(scored)) + " at checkpoint " + str(checkpoint))
				scorer.free()
				return
			var result: Dictionary = scored
			if not bool(result.get("ok", false)):
				_fail("score-refused", "checkpoint %d: %s" % [
					checkpoint, str(result.get("error"))])
				scorer.free()
				return
			if str(result.get("bridge_rev", "")) != revision:
				_fail("rev-mixed", "checkpoint %d reported %s, the day started on %s" % [
					checkpoint, str(result.get("bridge_rev")), revision])
				scorer.free()
				return
			var candidates: Variant = result.get("candidates")
			if typeof(candidates) != TYPE_ARRAY or candidates.size() != ACTIVITIES.size():
				_fail("candidates", "checkpoint %d returned %s candidates, expected %d" % [
					checkpoint, str(candidates.size()) if typeof(candidates) == TYPE_ARRAY
					else type_string(typeof(candidates)), ACTIVITIES.size()])
				scorer.free()
				return
			var chosen_id := int(result.get("chosen_id", -1))
			if chosen_id < 0:
				_fail("chosen", "checkpoint %d returned no chosen id" % checkpoint)
				scorer.free()
				return
			var chosen := {
				"id": chosen_id,
				"name": str(result.get("chosen_name", "")),
				"place": str(result.get("chosen_place", "")),
				"score": float(result.get("chosen_score", 0.0)),
			}

			# 6: advance across the next 10 clock ticks through Rust. The state
			# recorded below is the pre-advance state; the state the next
			# checkpoint sees is exactly the array that came back here.
			var advanced: Variant = scorer.call(
				"advance_time", needs, tick, tick + TICKS_PER_CHECKPOINT)
			if typeof(advanced) != TYPE_DICTIONARY or not bool(advanced.get("ok", false)):
				_fail("advance-refused", "checkpoint %d: %s" % [
					checkpoint, str(advanced.get("error")) if typeof(advanced) == TYPE_DICTIONARY
					else type_string(typeof(advanced))])
				scorer.free()
				return
			var next_needs: Variant = advanced.get("needs")
			if typeof(next_needs) != TYPE_ARRAY or next_needs.size() != NEED_ORDER_NAMES.size():
				_fail("advance-needs", "checkpoint %d returned a malformed needs array" % checkpoint)
				scorer.free()
				return

			lines.append(JSON.stringify({
				"type": "decision",
				"checkpoint": checkpoint,
				"tick": tick,
				"time_of_day": time_of_day,
				"seed": SEED,
				"needs": needs.duplicate(),
				"bridge_rev": revision,
				"chosen": chosen,
				"candidates": candidates,
				"next_decay_steps": int(advanced.get("decay_steps", -1)),
			}))

			if checkpoint == 0:
				first_chosen = chosen.duplicate()
			last_chosen = chosen.duplicate()
			chosen_ids.append(chosen_id)
			needs = next_needs.duplicate()
			decisions += 1

	# The clock, not a counter, says the day is over.
	if decisions != CHECKPOINTS:
		_fail("checkpoints", "the shared clock produced %d decision ticks, expected %d" % [
			decisions, CHECKPOINTS])
		scorer.free()
		return
	var final_tick := WorldClock.tick()
	if final_tick != FINAL_TICK:
		_fail("final-tick", "the shared clock ended at tick %d, expected %d" % [
			final_tick, FINAL_TICK])
		scorer.free()
		return

	# The day-loop drift check: 24 sequential single-boundary advances must land
	# where one direct 0 -> 240 advance lands. Both sides come from Rust; no
	# decay is recomputed here.
	var direct: Variant = scorer.call("advance_time", INITIAL_NEEDS, 0, FINAL_TICK)
	scorer.free()
	if typeof(direct) != TYPE_DICTIONARY or not bool(direct.get("ok", false)):
		_fail("direct-advance", "the 0 -> 240 advance was refused: "
			+ str(direct.get("error")))
		return
	var direct_needs: Variant = direct.get("needs")
	if typeof(direct_needs) != TYPE_ARRAY or direct_needs.size() != NEED_ORDER_NAMES.size():
		_fail("direct-advance", "the 0 -> 240 advance returned a malformed needs array")
		return
	if not _same_needs(needs, direct_needs):
		_fail("state-drift", "24 sequential advances gave %s but a direct 0 -> 240 gave %s"
			% [str(needs), str(direct_needs)])
		return

	var distinct: Array[int] = []
	for chosen_id in chosen_ids:
		if not distinct.has(chosen_id):
			distinct.append(chosen_id)
	distinct.sort()

	lines.append(JSON.stringify({
		"type": "summary",
		"trace_format": TRACE_FORMAT,
		"bridge_rev": revision,
		"seed": SEED,
		"checkpoints": decisions,
		"final_tick": final_tick,
		"final_needs": needs.duplicate(),
		"direct_0_240_needs": direct_needs.duplicate(),
		"sequential_equals_direct": true,
		"first_chosen": first_chosen,
		"last_chosen": last_chosen,
		"distinct_chosen_ids": distinct,
		"distinct_count": distinct.size(),
		"need_order": NEED_ORDER_NAMES,
		"clock_note": CLOCK_NOTE,
	}))

	if not _write_trace(trace_path, lines):
		return

	print("%s checkpoints=%d final_tick=%d rev=%s trace=%s distinct=%d first_id=%d first_name=%s last_id=%d last_name=%s speed=%d" % [
		OK_MARKER, decisions, final_tick, revision, trace_path, distinct.size(),
		int(first_chosen["id"]), str(first_chosen["name"]),
		int(last_chosen["id"]), str(last_chosen["name"]), speed])


# --- inputs and records -------------------------------------------------------

func _score_input(needs: Array, time_of_day: float) -> Dictionary:
	return {
		"seed": SEED,
		"needs": needs.duplicate(),
		"time_of_day": time_of_day,
		"activities": ACTIVITIES.duplicate(true),
		"skills": SKILLS.duplicate(),
		"settlement_damage": SETTLEMENT_DAMAGE,
		"settlement_aggregate_mood": SETTLEMENT_AGGREGATE_MOOD,
	}


func _fixture_record() -> Dictionary:
	return {
		"type": "fixture",
		"trace_format": TRACE_FORMAT,
		"seed": SEED,
		"initial_needs": INITIAL_NEEDS.duplicate(),
		"need_order": NEED_ORDER_NAMES,
		"skills": SKILLS.duplicate(),
		"settlement_damage": SETTLEMENT_DAMAGE,
		"settlement_aggregate_mood": SETTLEMENT_AGGREGATE_MOOD,
		"activities": ACTIVITIES.duplicate(true),
		"available_at_every_checkpoint": true,
		"checkpoints": CHECKPOINTS,
		"ticks_per_checkpoint": TICKS_PER_CHECKPOINT,
		"time_of_day_formula": "checkpoint / 24.0",
		"final_tick": FINAL_TICK,
		"clock_note": CLOCK_NOTE,
	}


# --- plumbing -----------------------------------------------------------------

## The driver speed for this run: the shared clock's integer multiplier.
func _run_speed() -> int:
	var raw := OS.get_environment(SPEED_ENV)
	if raw.is_empty():
		return 1
	if not raw.is_valid_int():
		return -1
	return int(raw)


func _open_scorer() -> Object:
	if not ClassDB.class_exists(SCORER_CLASS):
		_fail("extension-not-loaded", SCORER_CLASS + " is not registered in ClassDB")
		return null
	for method_name in SCORER_CALLABLES:
		if not ClassDB.class_has_method(SCORER_CLASS, method_name):
			_fail("callable-missing", SCORER_CLASS + "." + method_name + " does not exist")
			return null
	var scorer: Object = ClassDB.instantiate(SCORER_CLASS)
	if scorer == null:
		_fail("instantiate-failed", "ClassDB could not instantiate " + SCORER_CLASS)
	return scorer


func _write_trace(trace_path: String, lines: Array[String]) -> bool:
	var directory := trace_path.get_base_dir()
	if not directory.is_empty() and not DirAccess.dir_exists_absolute(directory):
		var made := DirAccess.make_dir_recursive_absolute(directory)
		if made != OK:
			_fail("trace-dir", "could not create %s (%s)" % [
				directory, error_string(made)])
			return false

	var file: FileAccess = FileAccess.open(trace_path, FileAccess.WRITE)
	if file == null:
		_fail("trace-open", "could not open %s for writing (%s)" % [
			trace_path, error_string(FileAccess.get_open_error())])
		return false
	for line in lines:
		file.store_line(line)
	file.flush()
	file = null
	return true


## Both sides arrive from Rust already; this only compares them.
func _same_needs(left: Array, right: Array) -> bool:
	if left.size() != right.size():
		return false
	for index in left.size():
		if float(left[index]) != float(right[index]):
			return false
	return true


func _fail(reason: String, detail: String) -> void:
	print(FAIL_MARKER + " reason=" + reason + " detail=" + detail)
	get_tree().quit(1)
