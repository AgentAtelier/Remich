extends Node

## Phase 1, step 5 day harness (docs/PLAN.md, phase 1, step 5).
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
## ## The test-harness clock (NOT a time authority)
##
## 24 checkpoints `0..23`, `time_of_day = checkpoint / 24.0`, checkpoint ticks
## `0, 10, 20, ... 230`, one `advance_time` to the next 10-tick boundary after
## every checkpoint, and a final tick of `240` once the day is complete.
##
## **240 ticks/day is a convention of this test harness only.** It exists to
## make a compact, inspectable one day: 24 familiar hour-like checkpoints and
## exactly one already-qualified donor decay boundary between them. It is not a
## Remich, anvil, Munshausen, Eisleck or Larochette time authority, it is not
## added to the engine-free scorer API as a global truth, and no other module
## may read it as one.
##
## ## Activation
##
## This autoload is silent and does nothing unless `REMICH_DAY_TRACE_PATH` is
## set to a file path. Steps 1-4 never set it, so ordinary runs are unaffected
## and `bridge_probe.gd` remains their final quit path.
##
## ## Why the day is deferred
##
## Autoload `_ready` callbacks run in list order during startup, and Godot
## honours the **last** `quit()` it sees. Running the day inline here would let
## a later probe's successful `quit(0)` overwrite this probe's `quit(1)`, so the
## day runs on the first deferred call instead: after `BridgeProbe` has taken
## the success path, a failed day still ends the process non-zero.

const TRACE_ENV := "REMICH_DAY_TRACE_PATH"
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

# --- the test-harness clock ---------------------------------------------------
const CHECKPOINTS := 24
const TICKS_PER_CHECKPOINT := 10
const FINAL_TICK := 240

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

	for checkpoint in CHECKPOINTS:
		var tick := checkpoint * TICKS_PER_CHECKPOINT
		var time_of_day := float(checkpoint) / float(CHECKPOINTS)

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

		# 6: advance to the next checkpoint through Rust. The state recorded
		# below is the pre-advance state; the state the next iteration sees is
		# exactly the array that came back here.
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
		"checkpoints": CHECKPOINTS,
		"final_tick": FINAL_TICK,
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

	print("%s checkpoints=%d final_tick=%d rev=%s trace=%s distinct=%d first_id=%d first_name=%s last_id=%d last_name=%s" % [
		OK_MARKER, CHECKPOINTS, FINAL_TICK, revision, trace_path, distinct.size(),
		int(first_chosen["id"]), str(first_chosen["name"]),
		int(last_chosen["id"]), str(last_chosen["name"])])


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
