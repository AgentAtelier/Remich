extends SceneTree

## Phase 2, step 4 — "many inhabitants, measured" (docs/PLAN.md §4a, step 4).
##
## A baseline measurement of the CURRENT scorer path: how long one measured
## tick takes when the real Godot -> GDExtension -> Rust `RemichScorer`
## `score_activity` call scores 1, 10, 100 or 1,000 stand-in inhabitants.
## This is groundwork for Forgeborn's Social LOD — it does not implement
## Social LOD, decide any Social LOD policy, or invent population state —
## and, as the plan requires, there is no optimisation back and forth: this
## step adds no performance feature of any kind, changes no formula, seed or
## need, and reports whatever the existing path honestly costs. A slower
## number is a result, not a failure.
##
## This file is a standalone script, never an autoload: ordinary Step 1-3
## runs never execute it and the project's autoload order (SaveProbe last)
## is untouched. It is run only through the runner, which supplies the
## environment and stages the extension:
##
##     bash tools/benchmark_phase2_step4.sh [--smoke]
##
## which executes exactly (pinned Godot 4.7.2, headless, never editor,
## import or export mode):
##
##     "$GODOT_BIN" --headless --path godot --script res://scale_benchmark.gd
##
## A bare invocation without the REMICH_SCALE_* environment fails clearly
## (REMICH_SCALE_FAIL reason=missing-environment) and exits non-zero.
##
## Fixture — built ONCE, before any timing, with no randomness anywhere:
##
##     for i in 0..999, input[i] = {
##       seed: 60628 + i                        (donor-seeded state per i)
##       needs: NEEDS_PROFILES[i % 8]           (the committed table below)
##       time_of_day: 0.5                       (the test fixture's noon)
##       activities: the six qualified ones, in input order:
##           2/north-hills, 1/east-field, 16/market-square,
##           14/cottage-loft, 12/ridge, 5/kitchen
##       skills: []
##       settlement_damage: 0.0
##       settlement_aggregate_mood: 0.0 }
##
## Population N is input[0..N): every case is a prefix of the same 1,000
## inputs, so all four cases measure one workload family.
##
## One measured tick = `_sample`: exactly N `score_activity` calls over the
## fixed world/time state, each returned `chosen_id` folded into a running
## checksum — results are consumed, never silently discarded. Deliberately
## OUTSIDE the timed region: fixture construction, scorer construction, the
## untimed correctness preflight, warm-up, statistics, logging, JSON and
## everything else (they are different costs).
##
## Method, per population, official order 1 -> 10 -> 100 -> 1000 (never
## reordered): one real scorer instance created before timing and reused for
## the whole benchmark; 10 untimed warm-up samples (1 in smoke); 100 measured
## samples (3 in smoke); each sample's elapsed microseconds read from the
## engine's monotonic `Time.get_ticks_usec()` around the N calls, with no
## logging inside the measured interval. Reported per population: warm-up
## samples, measured samples, total scorer calls, median / p95 (nearest-rank:
## the ceil(0.95 * samples)-th smallest) / arithmetic mean microseconds per
## tick, median microseconds per inhabitant (tick median / N), the sample-0
## checksum (deterministic across runs of the same configuration), and the
## scorer bridge revision. No performance limit is enforced and no judgement
## about the numbers is printed.
##
## Before any timing, two untimed passes score all 1,000 inputs and require,
## for every result: ok, the expected six candidate ids, a chosen id among
## them, a finite chosen score, six finite candidate scores, and the expected
## bridge revision — and require the two passes' signatures to match. Only
## valid scorer work is ever measured.
##
## Output, one machine-readable block per run:
##
##     REMICH_SCALE_ENV      every parameter and the environment of the run
##     REMICH_SCALE_RESULT   one line per population
##     REMICH_SCALE_OK       or REMICH_SCALE_FAIL reason=... (exit code 1)

const SCORER_CLASS := "RemichScorer"
const SCORER_CALLABLE := "score_activity"

const FIXTURE_SIZE := 1000
const SEED_BASE := 60628
const TIME_OF_DAY := 0.5
const SETTLEMENT_DAMAGE := 0.0
const SETTLEMENT_MOOD := 0.0
const POPULATIONS := [1, 10, 100, 1000]
const EXPECTED_CANDIDATES := 6

## The official methodology (docs/PLAN.md §4a, step 4). Smoke runs the same
## code path through the same four populations, short; its numbers are never
## the posted ones.
const OFFICIAL_WARMUP := 10
const OFFICIAL_SAMPLES := 100
const SMOKE_WARMUP := 1
const SMOKE_SAMPLES := 3

## The committed needs-profile table: eight nontrivial seven-value profiles
## (donor order: food, water, shelter, safety, sleep, companionship, joy),
## every value strictly inside (0, 1). Fixture input i takes profile i % 8.
const NEEDS_PROFILES := [
	[0.40, 0.35, 0.60, 0.50, 0.45, 0.42, 0.55],
	[0.62, 0.58, 0.33, 0.47, 0.71, 0.29, 0.44],
	[0.25, 0.77, 0.55, 0.68, 0.36, 0.51, 0.63],
	[0.83, 0.41, 0.49, 0.32, 0.57, 0.66, 0.38],
	[0.31, 0.64, 0.72, 0.55, 0.28, 0.47, 0.70],
	[0.56, 0.29, 0.44, 0.76, 0.63, 0.35, 0.52],
	[0.47, 0.52, 0.26, 0.58, 0.81, 0.73, 0.34],
	[0.69, 0.36, 0.61, 0.43, 0.39, 0.54, 0.77],
]

## The same six qualified activities every Step 1-3 probe uses, in input
## order: ids come from the donor action catalogue, places are Remich's own
## metadata and can never affect a score.
const ACTIVITIES := [
	{"id": 2, "place": "north-hills"},
	{"id": 1, "place": "east-field"},
	{"id": 16, "place": "market-square"},
	{"id": 14, "place": "cottage-loft"},
	{"id": 12, "place": "ridge"},
	{"id": 5, "place": "kitchen"},
]
const EXPECTED_ACTIVITY_IDS := [2, 1, 16, 14, 12, 5]

var _mode := ""
var _warmup := 0
var _samples := 0
var _expected_rev := ""
var _exit_code := 1
var _fail_line_printed := false
var _reported := false
var _lines: Array[String] = []


func _initialize() -> void:
	_run()


## The benchmark's own quit must come after every autoload probe has had its
## say: Godot honours the LAST quit() it sees, and bridge_probe quits from
## its _ready — which runs before this first process frame.
func _process(_delta: float) -> bool:
	if not _reported:
		_reported = true
		for line in _lines:
			print(line)
		if _exit_code != 0 and not _fail_line_printed:
			print("REMICH_SCALE_FAIL reason=setup-incomplete")
	quit(_exit_code)
	return false


func _fail(reason: String, detail: String = "") -> void:
	_exit_code = 1
	_fail_line_printed = true
	var line := "REMICH_SCALE_FAIL reason=%s" % reason
	if detail != "":
		line = "%s detail=%s" % [line, detail]
	_lines.append(line)


func _run() -> void:
	# --- configuration and environment (all supplied by the runner) -------
	_mode = OS.get_environment("REMICH_SCALE_MODE")
	if _mode == "smoke":
		_warmup = SMOKE_WARMUP
		_samples = SMOKE_SAMPLES
	elif _mode == "official":
		_warmup = OFFICIAL_WARMUP
		_samples = OFFICIAL_SAMPLES
	else:
		_fail("missing-environment", "REMICH_SCALE_MODE_must_be_smoke_or_official")
		return

	var missing := ""
	for key in ["REMICH_SCALE_REV", "REMICH_SCALE_GODOT", "REMICH_SCALE_RUST",
			"REMICH_SCALE_PROFILE", "REMICH_SCALE_LIB", "REMICH_SCALE_OS",
			"REMICH_SCALE_KERNEL", "REMICH_SCALE_ARCH", "REMICH_SCALE_CPU"]:
		if OS.get_environment(key).is_empty():
			missing = key
	if missing != "":
		_fail("missing-environment", missing)
		return
	_expected_rev = OS.get_environment("REMICH_SCALE_REV")

	# --- exactly one scorer, created here, outside every timed region -----
	if not ClassDB.class_exists(SCORER_CLASS):
		_fail("extension-not-loaded", SCORER_CLASS + "_is_not_registered_in_ClassDB")
		return
	if not ClassDB.class_has_method(SCORER_CLASS, SCORER_CALLABLE):
		_fail("callable-missing", SCORER_CLASS + "." + SCORER_CALLABLE + "_missing")
		return
	var scorer: Object = ClassDB.instantiate(SCORER_CLASS)
	if scorer == null:
		_fail("instantiate-failed", SCORER_CLASS)
		return

	# The library's own revision must agree with the source the runner read:
	# a stale .so refuses to benchmark rather than agreeing with itself.
	var library_rev := str(scorer.call("scorer_bridge_rev"))
	if library_rev != _expected_rev:
		_fail("library-revision-mismatch", "source_%s_library_%s" % [
			_expected_rev.replace("-", "_"), library_rev.replace("-", "_")])
		return

	# --- fixture: built once, deterministic, before any timing -----------
	var inputs := _build_fixture()

	# --- correctness preflight: two untimed passes over all 1,000 --------
	var pass_a := _preflight(scorer, inputs, _expected_rev)
	if pass_a < 0:
		return
	var pass_b := _preflight(scorer, inputs, _expected_rev)
	if pass_b < 0:
		return
	if pass_a != pass_b:
		_fail("preflight-signature-mismatch", "%d_vs_%d" % [pass_a, pass_b])
		return

	_lines.append(_env_line(pass_a))

	# --- warm-up (untimed) then measurement, official order --------------
	for population in POPULATIONS:
		if _warm_up(scorer, inputs, population, _warmup) < 0:
			_fail("warmup-checksum-mismatch", "population=%d" % population)
			return
		var measured := _measure(scorer, inputs, population, _samples)
		if measured.has("error"):
			_fail(str(measured["error"]), "population=%d" % population)
			return
		_lines.append(_result_line(population, measured))

	scorer.free()

	_exit_code = 0
	_lines.append(_ok_line())


func _ok_line() -> String:
	return ("REMICH_SCALE_OK populations=%s mode=%s warmup=%d samples=%d "
			+ "timer=Time.get_ticks_usec rev=%s") % [
		_join_ints(POPULATIONS), _mode, _warmup, _samples, _expected_rev]


func _env_line(preflight_signature: int) -> String:
	var fields := PackedStringArray()
	fields.append("REMICH_SCALE_ENV")
	fields.append("mode=%s" % _mode)
	fields.append("godot=%s" % OS.get_environment("REMICH_SCALE_GODOT"))
	fields.append("rust=%s" % OS.get_environment("REMICH_SCALE_RUST"))
	fields.append("profile=%s" % OS.get_environment("REMICH_SCALE_PROFILE"))
	fields.append("lib=%s" % OS.get_environment("REMICH_SCALE_LIB"))
	fields.append("os=%s" % OS.get_environment("REMICH_SCALE_OS"))
	fields.append("kernel=%s" % OS.get_environment("REMICH_SCALE_KERNEL"))
	fields.append("arch=%s" % OS.get_environment("REMICH_SCALE_ARCH"))
	fields.append("cpu=%s" % OS.get_environment("REMICH_SCALE_CPU"))
	fields.append("populations=%s" % _join_ints(POPULATIONS))
	fields.append("order=%s" % _join_ints(POPULATIONS))
	fields.append("warmup=%d" % _warmup)
	fields.append("samples=%d" % _samples)
	fields.append("timer=Time.get_ticks_usec")
	fields.append("fixture=%d" % FIXTURE_SIZE)
	fields.append("seed_base=%d" % SEED_BASE)
	fields.append("profiles=%d" % NEEDS_PROFILES.size())
	fields.append("time_of_day=%s" % str(TIME_OF_DAY))
	fields.append("activities=%d" % ACTIVITIES.size())
	fields.append("skills=0")
	fields.append("damage=%s" % str(SETTLEMENT_DAMAGE))
	fields.append("mood=%s" % str(SETTLEMENT_MOOD))
	fields.append("scorer_instances=1")
	fields.append("preflight=ok")
	fields.append("preflight_inputs=%d" % FIXTURE_SIZE)
	fields.append("preflight_passes=2")
	fields.append("preflight_signature=%d" % preflight_signature)
	fields.append("rev=%s" % _expected_rev)
	return " ".join(fields)


func _result_line(population: int, measured: Dictionary) -> String:
	var elapsed: Array = measured["elapsed"]
	var stats := _stats(elapsed)
	var samples := elapsed.size()
	var median: float = stats["median"]
	return ("REMICH_SCALE_RESULT inhabitants=%d warmup=%d samples=%d "
			+ "total_calls=%d warmup_calls=%d median_us=%s p95_us=%s "
			+ "mean_us=%s median_us_per_inhabitant=%s checksum=%d rev=%s") % [
		population, _warmup, samples,
		int(measured["calls"]), _warmup * population,
		String.num(median, 3),
		String.num(float(stats["p95"]), 3),
		String.num(float(stats["mean"]), 3),
		String.num(median / float(population), 6),
		int(measured["signature"]), _expected_rev]


## Deterministic fixture construction — runs once, outside every timed
## region; the populations below are prefixes of its result.
func _build_fixture() -> Array:
	var inputs: Array = []
	var index := 0
	while index < FIXTURE_SIZE:
		inputs.append({
			"seed": SEED_BASE + index,
			"needs": NEEDS_PROFILES[index % NEEDS_PROFILES.size()],
			"time_of_day": TIME_OF_DAY,
			"activities": ACTIVITIES,
			"skills": [],
			"settlement_damage": SETTLEMENT_DAMAGE,
			"settlement_aggregate_mood": SETTLEMENT_MOOD,
		})
		index += 1
	return inputs


## Untimed correctness pass over every fixture input: returns the outcome
## signature, or -1 after failing the run on the first violation.
func _preflight(scorer: Object, inputs: Array, expected_rev: String) -> int:
	var signature := 0
	var index := 0
	while index < inputs.size():
		var raw: Variant = scorer.call(SCORER_CALLABLE, inputs[index])
		if not (raw is Dictionary):
			_fail("preflight-not-a-dictionary", "input=%d" % index)
			return -1
		var result: Dictionary = raw
		var violation := _result_violation(result, expected_rev)
		if violation != "":
			_fail("preflight-invalid", "input=%d_reason=%s" % [index, violation])
			return -1
		signature = (signature * 31 + _result_fold(result)) % 1000000007
		index += 1
	return signature


func _result_violation(result: Dictionary, expected_rev: String) -> String:
	if not result.has("ok") or result.get("ok") != true:
		return "ok"
	if str(result.get("bridge_rev", "")) != expected_rev:
		return "bridge-rev"
	if not (result.get("candidates") is Array):
		return "candidates-missing"
	var candidates: Array = result.get("candidates")
	if candidates.size() != EXPECTED_CANDIDATES:
		return "candidate-count"
	var ids: Array = []
	for candidate in candidates:
		if not (candidate is Dictionary):
			return "candidate-entry"
		var entry: Dictionary = candidate
		if not entry.has("id") or not entry.has("score"):
			return "candidate-fields"
		var score: Variant = entry["score"]
		if not ((score is float) or (score is int)):
			return "candidate-score"
		if not is_finite(float(score)):
			return "candidate-score"
		ids.append(int(entry["id"]))
	for wanted in EXPECTED_ACTIVITY_IDS:
		if not ids.has(wanted):
			return "candidate-ids"
	if not result.has("chosen_id") or not (result["chosen_id"] is int):
		return "chosen-id"
	var chosen: int = result["chosen_id"]
	if not ids.has(chosen):
		return "chosen-id"
	if not result.has("chosen_score"):
		return "chosen-score"
	var chosen_score: Variant = result["chosen_score"]
	if not ((chosen_score is float) or (chosen_score is int)):
		return "chosen-score"
	if not is_finite(float(chosen_score)):
		return "chosen-score"
	return ""


## The signature of one preflight outcome: fold of the choice and every
## candidate id — the same inputs must give the same signature on pass two.
func _result_fold(result: Dictionary) -> int:
	var fold: int = result["chosen_id"]
	var candidates: Array = result["candidates"]
	for candidate in candidates:
		fold = (fold * 137 + int(candidate["id"])) % 1000000007
	return fold


## One untimed warm-up sample: exactly `population` scorer calls through the
## measured path, nothing recorded, no clock read. Returns the checksum, or
## -1 if the rounds disagreed (which would make the run unmeasurable).
func _warm_up(scorer: Object, inputs: Array, population: int, rounds: int) -> int:
	var checksum := -1
	var round := 0
	while round < rounds:
		var here := _sample(scorer, inputs, population)
		if checksum >= 0 and here != checksum:
			return -1
		checksum = here
		round += 1
	return checksum


## The measured region: `samples` samples, each bracketing exactly
## `population` scorer calls with the monotonic microsecond clock and nothing
## else — no logging, no statistics, no fixture or object construction.
func _measure(scorer: Object, inputs: Array, population: int, samples: int) -> Dictionary:
	var elapsed: Array = []
	var calls := 0
	var signature := -1
	var sample := 0
	while sample < samples:
		var started := Time.get_ticks_usec()
		var checksum := _sample(scorer, inputs, population)
		var finished := Time.get_ticks_usec()
		if finished < started:
			return {"error": "timer-went-backwards"}
		elapsed.append(finished - started)
		if signature < 0:
			signature = checksum
		elif checksum != signature:
			return {"error": "sample-checksum-mismatch"}
		calls += population
		sample += 1
	return {"elapsed": elapsed, "calls": calls, "signature": signature}


## Exactly `population` calls through the real bridge, each result consumed
## by folding its chosen_id into the returned checksum.
func _sample(scorer: Object, inputs: Array, population: int) -> int:
	var checksum := 0
	var i := 0
	while i < population:
		var result: Variant = scorer.call(SCORER_CALLABLE, inputs[i])
		checksum = (checksum * 31 + int(result.get("chosen_id", -1)) + 1) % 1000000007
		i += 1
	return checksum


## median: the middle of the sorted samples (mean of the two middle values
## for an even count). p95: nearest-rank — the ceil(0.95 * count)-th
## smallest. mean: arithmetic.
func _stats(elapsed: Array) -> Dictionary:
	var sorted := elapsed.duplicate()
	sorted.sort()
	var count := sorted.size()
	var total := 0
	for value in sorted:
		total += int(value)
	var mean := float(total) / float(count)
	var median: float
	if count % 2 == 1:
		median = float(sorted[count / 2])
	else:
		median = (float(sorted[count / 2 - 1]) + float(sorted[count / 2])) / 2.0
	var p95_index := ceili(0.95 * float(count)) - 1
	if p95_index < 0:
		p95_index = 0
	if p95_index > count - 1:
		p95_index = count - 1
	return {"median": median, "p95": float(sorted[p95_index]), "mean": mean}


func _join_ints(values: Array) -> String:
	var parts := PackedStringArray()
	for value in values:
		parts.append(str(int(value)))
	return ",".join(parts)
