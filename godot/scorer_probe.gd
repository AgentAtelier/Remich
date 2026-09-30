extends Node

## Phase 1, step 4 scorer probe (docs/PLAN.md, phase 1, step 4).
##
## The engine loads Remich's Rust GDExtension at startup; this autoload proves
## the real scorer path across it, with plain data only:
##
##   1. the extension was loaded   -- RemichScorer is registered in ClassDB;
##   2. the Rust scorer was reached -- it is instantiated and called;
##   3. the deterministic fixture came back -- the chosen activity, its place
##      and every candidate score are checked against the values recorded in
##      `crates/remich_core/tests/seed_sensitive_fixture.rs`, and the two fixed
##      seeds choose differently right here in the engine;
##   4. need decay follows the donor semantics -- checked the same way.
##
## It prints two machine-checkable lines (`REMICH_SCORER_OK`, `REMICH_DECAY_OK`)
## and fails with a matching exit code otherwise. Nothing here is simulation:
## it is a probe of the bridge and the recorded fixture.
##
## The probe only runs when `godot/scorer_probe_expectation.txt` exists, which
## `tools/stage_scorer.sh` writes for Step 4's runs. Steps 1-3 do not stage it
## and this script stays silent for them, leaving `bridge_probe.gd` to quit the
## run exactly as before.

const SCORER_CLASS := "RemichScorer"
const EXPECTATION_FILE := "res://scorer_probe_expectation.txt"
const VALUE_PREFIX := "remich-scorer-"
const OK_MARKER := "REMICH_SCORER_OK"
const FAIL_MARKER := "REMICH_SCORER_FAIL"
const DECAY_MARKER := "REMICH_DECAY_OK"
const DECAY_FAIL_MARKER := "REMICH_DECAY_FAIL"

# --- the committed fixture, identical to tests/seed_sensitive_fixture.rs ----
const SEED_A := 60628
const SEED_B := 87004
const NEEDS := [0.40, 0.35, 0.60, 0.50, 0.45, 0.42, 0.55]
const TIME_OF_DAY := 0.27
const ACTIVITIES := [
	{"id": 2, "place": "north-hills"},
	{"id": 1, "place": "east-field"},
	{"id": 16, "place": "market-square"},
	{"id": 14, "place": "cottage-loft"},
	{"id": 12, "place": "ridge"},
	{"id": 5, "place": "kitchen"},
]

const EXPECTED_IDS := [2, 1, 16, 14, 12, 5]
const EXPECTED_NAMES := ["Hunt", "Farm/Tend", "Gather Socially", "Sleep", "Lookout/Observe", "Cook/Prepare"]
const EXPECTED_PLACES := ["north-hills", "east-field", "market-square", "cottage-loft", "ridge", "kitchen"]

# Recorded candidate scores, seed 60628 then seed 87004, in input order.
const SCORES_A := [
	0.011674161069095135, 0.023807715624570847, 0.0027692753355950117,
	0.004213220439851284, 0.0, 0.004761543124914169,
]
const SCORES_B := [
	0.056183211505413055, 0.03676323592662811, 0.0043218438513576984,
	0.006532006897032261, 0.0, 0.0073526473715901375,
]

# The donor's seven decay rates, taken from the imported donor source
# crates/anvil_sim/src/needs.rs (`Need::decay_rate`), in NEED_ORDER. They are
# used here only as expected values to check the Rust result against.
const DECAY_RATES := [0.0001, 0.00015, 0.00005, 0.0, 0.00007, 0.00006, 0.00002]

const NEED_ORDER_NAMES := ["food", "water", "shelter", "safety", "sleep", "companionship", "joy"]


func _ready() -> void:
	var expected := _read_expectation()
	if expected.is_empty():
		# Not staged: Steps 1-3 are running. This probe does not exist for them.
		return
	if not expected.begins_with(VALUE_PREFIX):
		_fail("unexpected-rev", expected + " is not a scorer bridge revision")
		return
	_run(expected)


func _run(expected: String) -> void:
	# 1. the extension was loaded
	if not ClassDB.class_exists(SCORER_CLASS):
		_fail("extension-not-loaded", SCORER_CLASS + " is not registered in ClassDB")
		return

	# 2. the Rust callables exist
	for method_name in ["score_activity", "advance_time", "scorer_bridge_rev"]:
		if not ClassDB.class_has_method(SCORER_CLASS, method_name):
			_fail("callable-missing", SCORER_CLASS + "." + method_name + " does not exist")
			return

	var scorer: Object = ClassDB.instantiate(SCORER_CLASS)
	if scorer == null:
		_fail("instantiate-failed", "ClassDB could not instantiate " + SCORER_CLASS)
		return

	# 3. the declared revision really came back out of this library
	var rev: Variant = scorer.call("scorer_bridge_rev")
	if typeof(rev) != TYPE_STRING or rev != expected:
		_fail("rev-mismatch", "Godot observed " + str(rev) + " but the Rust source expects " + expected)
		scorer.free()
		return

	# 4. seed A: the full recorded fixture
	var error := _verify_score(
		scorer.call("score_activity", _fixture(SEED_A)),
		expected, SEED_A, 1, "east-field", SCORES_A, "seed A")
	if error != "":
		_fail("seed-a", error)
		scorer.free()
		return

	# 5. seed B: same request, different seed, different choice
	error = _verify_score(
		scorer.call("score_activity", _fixture(SEED_B)),
		expected, SEED_B, 2, "north-hills", SCORES_B, "seed B")
	if error != "":
		_fail("seed-b", error)
		scorer.free()
		return

	# 6. the seed is not ignored: the two runs really differ, here in Godot
	var chosen_a := _chosen_id(scorer, SEED_A)
	var chosen_b := _chosen_id(scorer, SEED_B)
	if chosen_a == -1 or chosen_b == -1 or chosen_a == chosen_b:
		_fail("seed-insensitive", "seed A chose %d and seed B chose %d" % [chosen_a, chosen_b])
		scorer.free()
		return

	# 7. plain skill names reach the donor's skill modifier, and help
	var with_skill: Dictionary = scorer.call("score_activity", _fixture(SEED_A, ["farmer"]))
	if not bool(with_skill.get("ok", false)):
		_fail("skills", "skills input was rejected: " + str(with_skill.get("error")))
		scorer.free()
		return
	if not _close(float(with_skill.get("chosen_score", 0.0)), 0.028569258749485016):
		_fail("skills", "the Farmer skill did not raise Farm/Tend's score as recorded")
		scorer.free()
		return

	# 8. a rejected request fails loudly instead of substituting an action
	var broken: Dictionary = scorer.call("score_activity", _fixture(SEED_A, [], 9999))
	if bool(broken.get("ok", true)):
		_fail("silent-substitution", "an unknown action id was accepted")
		scorer.free()
		return
	if str(broken.get("error", "")).is_empty():
		_fail("silent-substitution", "the rejection carried no error message")
		scorer.free()
		return

	print("%s rev=%s seed_a=%d chosen_a=1 chosen_a_place=east-field chosen_b=%d chosen_b_place=north-hills candidates=%d" % [
		OK_MARKER, expected, SEED_A, chosen_b, EXPECTED_IDS.size()])

	# 9. need decay, with the donor's semantics
	if not _verify_decay(scorer):
		scorer.free()
		return
	print(DECAY_MARKER + " steps_none=0 steps_one=1 steps_many=3 safety_unchanged=true floor=0.0")

	scorer.free()


# --- scoring checks ----------------------------------------------------------

func _verify_score(result: Variant, expected: String, seed: int, chosen_id: int,
		chosen_place: String, expected_scores: Array, label: String) -> String:
	if typeof(result) != TYPE_DICTIONARY:
		return "%s: score_activity returned %s, expected Dictionary" % [label, type_string(typeof(result))]
	var returned: Dictionary = result

	if not bool(returned.get("ok", false)):
		return "%s: the scorer refused the fixture: %s" % [label, str(returned.get("error"))]
	if str(returned.get("bridge_rev", "")) != expected:
		return "%s: bridge_rev is %s, expected %s" % [label, str(returned.get("bridge_rev")), expected]
	if int(returned.get("seed", -1)) != seed:
		return "%s: the seed did not cross (got %s)" % [label, str(returned.get("seed"))]

	if int(returned.get("chosen_id", -1)) != chosen_id:
		return "%s: chose id %s, expected %d" % [label, str(returned.get("chosen_id")), chosen_id]
	if str(returned.get("chosen_name", "")) != EXPECTED_NAMES[EXPECTED_IDS.find(chosen_id)]:
		return "%s: chosen name is %s" % [label, str(returned.get("chosen_name"))]
	if str(returned.get("chosen_place", "")) != chosen_place:
		return "%s: chosen place is %s, expected %s" % [label, str(returned.get("chosen_place")), chosen_place]
	if not _close(float(returned.get("chosen_score", -1.0)),
			expected_scores[EXPECTED_IDS.find(chosen_id)]):
		return "%s: chosen score is %s, expected %s" % [
			label, str(returned.get("chosen_score")),
			str(expected_scores[EXPECTED_IDS.find(chosen_id)])]

	var candidates: Variant = returned.get("candidates")
	if typeof(candidates) != TYPE_ARRAY:
		return "%s: candidates is not an Array" % label
	if candidates.size() != EXPECTED_IDS.size():
		return "%s: %d candidates, expected %d" % [label, candidates.size(), EXPECTED_IDS.size()]

	for index in EXPECTED_IDS.size():
		var entry: Variant = candidates[index]
		if typeof(entry) != TYPE_DICTIONARY:
			return "%s: candidate %d is not a Dictionary" % [label, index]
		var candidate: Dictionary = entry
		if int(candidate.get("id", -1)) != EXPECTED_IDS[index]:
			return "%s: candidate %d id is %s" % [label, index, str(candidate.get("id"))]
		if str(candidate.get("name", "")) != EXPECTED_NAMES[index]:
			return "%s: candidate %d name is %s" % [label, index, str(candidate.get("name"))]
		if str(candidate.get("place", "")) != EXPECTED_PLACES[index]:
			return "%s: candidate %d place is %s" % [label, index, str(candidate.get("place"))]
		if not _close(float(candidate.get("score", -1.0)), expected_scores[index]):
			return "%s: candidate %d score is %s, expected %s" % [
				label, index, str(candidate.get("score")), str(expected_scores[index])]

	return ""


func _chosen_id(scorer: Object, seed: int) -> int:
	var returned: Variant = scorer.call("score_activity", _fixture(seed))
	if typeof(returned) != TYPE_DICTIONARY or not bool(returned.get("ok", false)):
		return -1
	return int(returned.get("chosen_id", -1))


# --- decay checks ------------------------------------------------------------

func _verify_decay(scorer: Object) -> bool:
	# (a) no boundary crossed between 5 and 9: nothing moves
	var none: Dictionary = scorer.call("advance_time", NEEDS, 5, 9)
	if not bool(none.get("ok", false)):
		_decay_fail("refused the no-boundary advance: " + str(none.get("error")))
		return false
	if int(none.get("decay_steps", -1)) != 0:
		_decay_fail("0 steps expected for 5->9, got %s" % str(none.get("decay_steps")))
		return false
	var after_none: Array = none.get("needs")
	for index in NEEDS.size():
		if not _close(after_none[index], NEEDS[index]):
			_decay_fail("%s moved without a boundary" % NEED_ORDER_NAMES[index])
			return false

	# (b) exactly one boundary (10) crossed between 5 and 10
	var one: Dictionary = scorer.call("advance_time", NEEDS, 5, 10)
	if int(one.get("decay_steps", -1)) != 1:
		_decay_fail("1 step expected for 5->10, got %s" % str(one.get("decay_steps")))
		return false
	var after_one: Array = one.get("needs")
	for index in NEEDS.size():
		var expected_value: float = maxf(NEEDS[index] - DECAY_RATES[index], 0.0)
		if not _close(after_one[index], expected_value):
			_decay_fail("%s after one step is %s, expected %s" % [
				NEED_ORDER_NAMES[index], str(after_one[index]), str(expected_value)])
			return false

	# (c) three boundaries (10, 20, 30) crossed between 5 and 35
	var many: Dictionary = scorer.call("advance_time", NEEDS, 5, 35)
	if int(many.get("decay_steps", -1)) != 3:
		_decay_fail("3 steps expected for 5->35, got %s" % str(many.get("decay_steps")))
		return false
	var after_many: Array = many.get("needs")
	for index in NEEDS.size():
		var expected_value: float = maxf(NEEDS[index] - 3.0 * DECAY_RATES[index], 0.0)
		if not _close(after_many[index], expected_value):
			_decay_fail("%s after three steps is %s, expected %s" % [
				NEED_ORDER_NAMES[index], str(after_many[index]), str(expected_value)])
			return false
	# Safety's donor decay rate is 0.0, so it never moves at all.
	if not _close(after_many[3], NEEDS[3]):
		_decay_fail("safety decayed, but its donor decay rate is 0.0")
		return false

	# (d) a long advance: values are clamped, never negative
	var floor_needs := [0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0]
	var floor_run: Dictionary = scorer.call("advance_time", floor_needs, 0, 10000)
	if int(floor_run.get("decay_steps", -1)) != 1000:
		_decay_fail("1000 steps expected for 0->10000, got %s" % str(floor_run.get("decay_steps")))
		return false
	var floored: Array = floor_run.get("needs")
	for index in floored.size():
		if float(floored[index]) < 0.0:
			_decay_fail("%s went negative: %s" % [NEED_ORDER_NAMES[index], str(floored[index])])
			return false
		if not _close(floored[index], 0.0):
			_decay_fail("%s started at 0.0 and did not stay there" % NEED_ORDER_NAMES[index])
			return false

	# (e) a value just above the floor reaches it exactly
	var tiny := [0.00004, 0.00004, 0.00004, 0.5, 0.00004, 0.00004, 0.00004]
	var tiny_run: Dictionary = scorer.call("advance_time", tiny, 0, 10000)
	var tiny_needs: Array = tiny_run.get("needs")
	for index in [0, 1, 2, 4, 5, 6]:
		if not _close(tiny_needs[index], 0.0):
			_decay_fail("%s should have bottomed out at 0.0, got %s" % [
				NEED_ORDER_NAMES[index], str(tiny_needs[index])])
			return false
	if not _close(tiny_needs[3], 0.5):
		_decay_fail("safety should have stayed at 0.5, got %s" % str(tiny_needs[3]))
		return false

	return true


# --- helpers -----------------------------------------------------------------

func _fixture(seed: int, skills: Array = [], unknown_id: int = -1) -> Dictionary:
	var activities: Array = ACTIVITIES.duplicate(true)
	if unknown_id >= 0:
		activities.append({"id": unknown_id, "place": "nowhere"})
	return {
		"seed": seed,
		"needs": NEEDS.duplicate(),
		"time_of_day": TIME_OF_DAY,
		"activities": activities,
		"skills": skills,
		"settlement_damage": 0.0,
		"settlement_aggregate_mood": 0.0,
	}


## The Rust side computes in f32 and hands over the exact widened value; this
## compares against the recorded literal without pretending the two roundings
## are identical.
func _close(observed: float, expected: float) -> bool:
	return absf(observed - expected) <= 0.000001 * maxf(1.0, absf(expected))


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


func _decay_fail(detail: String) -> void:
	print(DECAY_FAIL_MARKER + " detail=" + detail)
	get_tree().quit(1)
