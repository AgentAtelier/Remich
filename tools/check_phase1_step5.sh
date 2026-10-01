#!/usr/bin/env bash
# Phase 1, Step 5 acceptance check — "a day in the test project"
# (docs/PLAN.md §4, step 5; record: docs/remich-day-step5.md).
#
# One command, from anywhere:
#
#     bash tools/check_phase1_step5.sh
#
# It fails if the stand-in day loses its fixed fixture, its real-GDExtension
# path, its trace, its determinism or its clean head. It runs the Step 4
# acceptance first (which runs Step 3, which runs Step 2, which runs Step 1), so
# the scorer, the donor import, the firewall and the bridge cannot regress
# underneath a green Step 5.
#
# Requirements, as checks:
#
#   1. `bash tools/check_phase1_step4.sh` remains green;
#   2. Step 3 donor code and data are unchanged (and so are the Step 3 record
#      and docs/PLAN.md);
#   3. Step 4 scorer/decay behaviour is unchanged — no Rust changed at all;
#   4. the day harness exists in Remich's own Godot project;
#   5. it is inactive during ordinary earlier-step runs unless activated;
#   6. pinned Godot 4.7.2 runs the day through the real `RemichScorer`;
#   7. the runtime writes a non-empty trace file;
#   8. trace validation passes (tools/check_day_trace.py);
#   9. exactly 24 decision checkpoints, 0..23, ticks 0,10,...,230;
#  10. every checkpoint carries time, needs, choice and all six scores;
#      the final tick is 240 and sequential advancement matches a direct
#      0 -> 240 advancement;
#  11. two independent runs of the fixed day are byte-identical;
#  12. `REMICH_DAY_OK` appears, and no FAIL, script or parse error does;
#  13. Step 4's `REMICH_SCORER_OK` and Step 2's `REMICH_BRIDGE_OK` remain;
#  14. the workspace builds warning-free and its tests pass;
#  15. generated trace files are not tracked, and no timing probe remains;
#  16. the clean-build and rebuild-through-day timings are recorded;
#  17. the worktree is clean;
#  18. no other repository was modified.

set -uo pipefail

REPO_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)" || exit 1
cd "$REPO_ROOT" || exit 1

# Qualified headless path only: never editor, import or export mode.
GODOT_BIN="/home/mrg/Documents/Project/Yolanda/.godot-local/engine/4.7.2/Godot_v4.7.2-stable_linux.x86_64"
GODOT_PROJECT="godot"

VAULT="/home/mrg/Documents/Project/buggy-vault"
VAULT_COMMIT="24181142c693be37f90a6a667a6dc493425cd832"
# The merge commit that ended Step 4: everything Step 3 and Step 4 took must be
# byte-identical to it.
STEP4_BASE="a599a55cefa9ba3417773f2dbe102c1997ace645"

DAY_PROBE="godot/day_probe.gd"
PROBE_PROJECT="godot/project.godot"
SCORER_PROBE="godot/scorer_probe.gd"
BRIDGE_PROBE="godot/bridge_probe.gd"
VALIDATOR="tools/check_day_trace.py"
RUN_DAY="tools/run_day.sh"
GDEX_SRC="crates/remich_gdext/src/lib.rs"
RECORD_DOC="docs/remich-day-step5.md"
STEP4_DOC="docs/remich-scorer-step4.md"
STEP3_DOC="docs/anvil-import-phase1-step3.md"
PLAN_DOC="docs/PLAN.md"
TRACE_ENV="REMICH_DAY_TRACE_PATH"
COMMITTED_SCORER_REV="remich-scorer-v1"

LOG_DIR="$(mktemp -d "${TMPDIR:-/tmp}/remich-p1s5.XXXXXX")" || exit 1
trap 'rm -rf "$LOG_DIR"' EXIT

# The two traces the acceptance generates live outside the worktree, so they
# can never make check 17 look dirty.
TRACE_ONE="$LOG_DIR/day-run-1.jsonl"
TRACE_TWO="$LOG_DIR/day-run-2.jsonl"
LOG_ONE="$LOG_DIR/day-run-1.log"
LOG_TWO="$LOG_DIR/day-run-2.log"
LOG_PLAIN="$LOG_DIR/ordinary-run.log"

failures=0
pass() { printf 'ok    %s\n' "$1"; }
fail() { printf 'FAIL  %s\n' "$1"; failures=$((failures + 1)); }
note() { printf '      %s\n' "$1"; }
header() { printf '\n== %s ==\n' "$1"; }

# Show the last lines of a run log under an `ok`/`FAIL` message.
tail_log() { tail -n 25 "$1" | sed 's/^/      | /'; }

# ------------------------------------------------- 1. Step 4 still green
header "1. The Step 4 acceptance is still green"

if bash tools/check_phase1_step4.sh >"$LOG_DIR/step4.log" 2>&1; then
    pass "bash tools/check_phase1_step4.sh exits 0"
    tail -n 3 "$LOG_DIR/step4.log" | sed 's/^/      | /'
else
    fail "bash tools/check_phase1_step4.sh failed:"
    grep '^FAIL' "$LOG_DIR/step4.log" | sed 's/^/      | /'
    tail -n 60 "$LOG_DIR/step4.log" | sed 's/^/      | /'
fi

# ------------------------------------ 2. Step 3 donor code and data unchanged
header "2. Step 3 donor code, data and record are unchanged"

# `git diff <commit>` compares that commit against the working tree, so it
# catches a rewritten file and an uncommitted edit alike.
donor_delta="$(git diff --name-only "$STEP4_BASE" -- \
    crates/anvil_sim crates/anvil_core assets "$STEP3_DOC" "$PLAN_DOC" 2>/dev/null)"
if [ -z "$donor_delta" ]; then
    pass "crates/anvil_sim, crates/anvil_core, assets, the Step 3 record and the plan are unchanged"
else
    fail "a Step 3 file, the Step 3 record or the plan changed since the Step 4 base:"
    printf '%s\n' "$donor_delta" | sed 's/^/      | /'
fi

if grep -qF "buggy-vault@${VAULT_COMMIT:0:8}" "$STEP3_DOC" 2>/dev/null; then
    pass "the Step 3 provenance record still names the pinned donor"
else
    fail "the Step 3 provenance record no longer names the pinned donor"
fi

# ------------------------------------- 3. Step 4 scorer/decay behaviour intact
header "3. Step 4's scorer and decay behaviour are unchanged (no Rust changed)"

core_delta="$(git diff --name-only "$STEP4_BASE" -- crates Cargo.toml Cargo.lock rust-toolchain.toml 2>/dev/null)"
if [ -z "$core_delta" ]; then
    pass "every Rust source, manifest and lockfile is byte-identical to the Step 4 base"
else
    fail "a Rust file changed since the Step 4 base — Step 5 needs no Rust change:"
    printf '%s\n' "$core_delta" | sed 's/^/      | /'
fi

if [ -f "$RECORD_DOC" ] && [ -f "$SCORER_PROBE" ] && [ -f "$BRIDGE_PROBE" ]; then
    pass "the Step 4 record and both Godot probes are still present"
else
    fail "a Step 4 artefact is missing"
fi

# ---------------------------------------------- 4. the day harness exists
header "4. The stand-in day harness exists in Remich's Godot project"

if [ -f "$DAY_PROBE" ] && [ -s "$DAY_PROBE" ]; then
    pass "$DAY_PROBE exists and is not empty"
else
    fail "$DAY_PROBE is missing or empty"
fi

if git ls-files --error-unmatch "$DAY_PROBE" >/dev/null 2>&1; then
    pass "$DAY_PROBE is a tracked file of this repository"
else
    fail "$DAY_PROBE is not tracked by this repository"
fi

for needle in \
    "func _run_day(" \
    "score_activity" \
    "advance_time" \
    "scorer_bridge_rev" \
    "ClassDB.instantiate(SCORER_CLASS)" \
    "REMICH_DAY_OK" \
    "REMICH_DAY_FAIL" \
    "$TRACE_ENV" \
    "CHECKPOINTS := 24" \
    "TICKS_PER_CHECKPOINT := 10" \
    "FINAL_TICK := 240"
do
    if grep -qF "$needle" "$DAY_PROBE"; then
        pass "the harness declares $needle"
    else
        fail "the harness does not declare $needle"
    fi
done

if grep -qE '^DayProbe="\*res://day_probe\.gd"$' "$PROBE_PROJECT"; then
    pass "day_probe.gd is an autoload"
else
    fail "day_probe.gd is not registered as an autoload"
fi

# Autoload order: Marker, ScorerProbe, DayProbe, BridgeProbe — the day runs
# between the qualified scorer probe and the existing success quit path.
autoload_order="$(grep -E '^(Marker|ScorerProbe|DayProbe|BridgeProbe)=' "$PROBE_PROJECT" \
    | sed 's/=.*//' | tr '\n' ' ')"
if [ "$autoload_order" = "Marker ScorerProbe DayProbe BridgeProbe " ]; then
    pass "autoload order is Marker, ScorerProbe, DayProbe, BridgeProbe"
else
    fail "autoload order is '$autoload_order', expected 'Marker ScorerProbe DayProbe BridgeProbe '"
fi

# GDScript is only ever a caller here: no score, no donor formula, no decay.
if grep -qE 'compute_utility_score|base_urgency|decay_rate|from_seed' "$DAY_PROBE"; then
    fail "the Godot harness computes a score, a decay rate or a soul itself:"
    grep -nE 'compute_utility_score|base_urgency|decay_rate|from_seed' "$DAY_PROBE" | sed 's/^/      | /'
else
    pass "the Godot harness defines no scoring, decay or seed logic of its own"
fi

# ----------------------------------- 5. inactive unless explicitly activated
header "5. The harness stays inactive during ordinary earlier-step runs"

if grep -A3 -q 'if trace_path.is_empty():' "$DAY_PROBE" \
        && grep -A3 'if trace_path.is_empty():' "$DAY_PROBE" | grep -q 'return'; then
    pass "$TRACE_ENV empty means the harness returns before doing any work"
else
    fail "the harness has no early return when $TRACE_ENV is unset"
fi

if grep -q "OS.get_environment(TRACE_ENV)" "$DAY_PROBE"; then
    pass "the harness is activated by the environment alone"
else
    fail "the harness does not read its activation from the environment"
fi

plain_rc=0
env -u "$TRACE_ENV" "$GODOT_BIN" --headless --path "$GODOT_PROJECT" --quit-after 10 \
    >"$LOG_PLAIN" 2>&1 || plain_rc=$?
if [ "$plain_rc" -eq 0 ]; then
    pass "an ordinary run without activation still exits 0"
else
    fail "an ordinary run without activation exited $plain_rc"
fi

if grep -qE '^REMICH_DAY_' "$LOG_PLAIN"; then
    fail "an ordinary run printed a day marker (the harness is not silent):"
    grep -E '^REMICH_DAY_' "$LOG_PLAIN" | sed 's/^/      | /'
else
    pass "an ordinary run prints no REMICH_DAY marker at all"
fi

if grep -q '^REMICH_TEST_PROJECT_OPENED$' "$LOG_PLAIN"; then
    pass "that ordinary run still opened this project and ran its scene"
else
    fail "the ordinary run never reached the project"
fi

# ------------------------------------- 6. the day runs through the real bridge
header "6. Pinned Godot 4.7.2 runs the day through the real RemichScorer"

if [ -x "$GODOT_BIN" ]; then
    pass "the pinned engine exists at the qualified path"
else
    fail "the pinned engine is missing at $GODOT_BIN"
fi

# Every engine invocation in tools/ must be headless and never enter editor,
# import or export mode. (The same rule is asserted by Step 4's checker; it is
# repeated here so this step's own scripts are covered too.)
invocations="$(grep -rnE '\$GODOT_BIN"[[:space:]]+([-"$])' tools/*.sh 2>/dev/null \
    | grep -vF -- '--version' || true)"
engine_mode_problems=""
while IFS= read -r line; do
    [ -z "$line" ] && continue
    case "$line" in
        *--headless*)
            case "$line" in
                *--editor*|*--export*|*--import*|*--project-manager*)
                    engine_mode_problems="$engine_mode_problems$line
" ;;
            esac
            ;;
        *) engine_mode_problems="$engine_mode_problems$line
" ;;
    esac
done <<<"$invocations"
if [ -z "$invocations" ]; then
    fail "no engine run found in tools/ — the qualified proof path is missing"
elif [ -z "$engine_mode_problems" ]; then
    pass "every engine run in tools/ is headless, with no editor/import/export mode"
else
    fail "an engine run is not headless, or enters a forbidden mode:"
    printf '%s\n' "$engine_mode_problems" | sed 's/^/      | /'
fi

day1_rc=0
bash "$RUN_DAY" "$TRACE_ONE" >"$LOG_ONE" 2>&1 || day1_rc=$?
if [ "$day1_rc" -eq 0 ]; then
    pass "bash tools/run_day.sh <trace> exits 0 for the day run"
    tail_log "$LOG_ONE"
else
    fail "the day run exited $day1_rc:"
    tail_log "$LOG_ONE"
fi

if grep -q '^REMICH_SCORER_OK ' "$LOG_ONE" && grep -q '^REMICH_DAY_OK ' "$LOG_ONE"; then
    pass "the same engine process reached RemichScorer (scorer probe) and then ran the day"
else
    fail "the day run did not reach RemichScorer"
fi

for needle in 'ClassDB.class_exists(SCORER_CLASS)' \
    'ClassDB.class_has_method' \
    'scorer.call(' \
    '"score_activity"' \
    '"advance_time"'
do
    if grep -qF "$needle" "$DAY_PROBE"; then
        pass "the day calls the extension: $needle"
    else
        fail "the day does not call the extension: $needle"
    fi
done

# ---------------------------------------------------- 7. the trace file
header "7. The runtime wrote a non-empty trace file"

if [ -s "$TRACE_ONE" ]; then
    pass "the trace is present and non-empty ($(wc -c <"$TRACE_ONE") bytes, $(wc -l <"$TRACE_ONE") lines)"
else
    fail "no non-empty trace at $TRACE_ONE"
fi

# ------------------------------------------------- 8. trace validation
header "8. The trace validates independently of the code that wrote it"

if [ -f "$VALIDATOR" ]; then
    pass "$VALIDATOR exists"
else
    fail "$VALIDATOR is missing"
fi

# A syntax check only — `py_compile` would drop a __pycache__ into the tree
# and make check 17 fail on state this step generated.
if python3 -c "import ast, sys; ast.parse(open(sys.argv[1], encoding='utf-8').read())" "$VALIDATOR" \
        2>/dev/null; then
    pass "the validator is syntactically valid Python"
else
    fail "the validator does not parse"
fi

if python3 "$VALIDATOR" "$TRACE_ONE" >"$LOG_DIR/validator.log" 2>&1; then
    pass "python3 tools/check_day_trace.py accepts the trace"
    grep -c '^ok    ' "$LOG_DIR/validator.log" | sed 's/^/      | checks ok: /'
else
    fail "the trace validator rejected the trace:"
    cat "$LOG_DIR/validator.log" | sed 's/^/      | /'
fi

# A validator that accepts everything would also pass the check above, so nine
# deliberately broken traces have to be rejected, each for its own reason.
mutation_total="$(python3 - "$TRACE_ONE" "$LOG_DIR" <<'PY' 2>/dev/null
import copy
import json
import os
import sys

source, out_dir = sys.argv[1], sys.argv[2]
records = [json.loads(line) for line in open(source, encoding="utf-8") if line.strip()]


def is_decision(record):
    return record.get("type") == "decision"


def at(records, checkpoint):
    return next(r for r in records if is_decision(r) and r["checkpoint"] == checkpoint)


def emit(name, subset):
    path = os.path.join(out_dir, "mut-" + name + ".jsonl")
    with open(path, "w", encoding="utf-8") as handle:
        for record in subset:
            handle.write(json.dumps(record) + "\n")


cases = []

cases.append(("missing-checkpoint",
              [r for r in records if not (is_decision(r) and r["checkpoint"] == 11)]))

scratch = copy.deepcopy(records)
at(scratch, 5)["chosen"]["id"] = 99
cases.append(("chosen-not-a-candidate", scratch))

scratch = copy.deepcopy(records)
at(scratch, 9)["needs"][0] = 0.99
cases.append(("rising-need", scratch))

scratch = copy.deepcopy(records)
at(scratch, 4)["needs"][3] = 0.75
cases.append(("moving-safety", scratch))

scratch = copy.deepcopy(records)
at(scratch, 17)["tick"] = 999
cases.append(("wrong-tick", scratch))

scratch = copy.deepcopy(records)
summary = next(r for r in scratch if r.get("type") == "summary")
summary["final_tick"] = 999
summary["sequential_equals_direct"] = False
cases.append(("wrong-final-state", scratch))

scratch = copy.deepcopy(records)
at(scratch, 2)["candidates"].reverse()
cases.append(("reordered-candidates", scratch))

scratch = copy.deepcopy(records)
at(scratch, 8)["candidates"][0]["score"] = None
cases.append(("non-finite-score", scratch))

cases.append(("truncated", records[:5]))

for name, subset in cases:
    emit(name, subset)
print(len(cases))
PY
)"
if [ -n "$mutation_total" ] && [ "$mutation_total" -gt 0 ] 2>/dev/null; then
    pass "the self-test generated $mutation_total deliberately broken traces"
else
    fail "the validator self-test could not generate its broken traces"
    mutation_total=0
fi

rejected=0
accepted=""
for mutated in "$LOG_DIR"/mut-*.jsonl; do
    [ -e "$mutated" ] || continue
    name="$(basename "$mutated" .jsonl)"
    if python3 "$VALIDATOR" "$mutated" >"$LOG_DIR/mut.log" 2>&1; then
        accepted="$accepted $name"
    else
        rejected=$((rejected + 1))
        first_fail="$(grep -m1 '^FAIL' "$LOG_DIR/mut.log" 2>/dev/null || true)"
        note "$name rejected: ${first_fail:-no detail}"
    fi
done
if [ -n "$accepted" ]; then
    fail "the validator accepted a broken trace:$accepted"
elif [ "$rejected" -eq "$mutation_total" ] && [ "$rejected" -gt 0 ]; then
    pass "all $rejected deliberately broken traces are rejected — the validator is not vacuous"
else
    fail "only $rejected of $mutation_total broken traces were exercised"
fi

# -------------------------------------- 9. 24 checkpoints, 0..23, ticks 0..230
header "9. Exactly 24 decision checkpoints, 0..23, at ticks 0,10,...,230"

decision_count="$(grep -c '"type":"decision"' "$TRACE_ONE" 2>/dev/null || echo 0)"
if [ "$decision_count" -eq 24 ]; then
    pass "the trace holds exactly 24 decision records"
else
    fail "the trace holds $decision_count decision records, expected 24"
fi

expected_seq="$(seq 0 23 | tr '\n' ' ')"
actual_seq="$(grep -o '"checkpoint":[0-9]*' "$TRACE_ONE" | sed 's/.*://' | tr '\n' ' ')"
if [ "$actual_seq" = "$expected_seq" ]; then
    pass "checkpoint numbers run 0..23 with no gap or repeat"
else
    fail "checkpoint numbers are '$actual_seq'"
fi

expected_ticks="$(seq 0 23 | awk '{ printf "%d ", $1 * 10 }')"
actual_ticks="$(grep -o '"tick":[0-9]*' "$TRACE_ONE" | sed 's/.*://' | tr '\n' ' ')"
if [ "$actual_ticks" = "$expected_ticks" ]; then
    pass "ticks run 0 10 20 ... 230"
else
    fail "ticks are '$actual_ticks', expected '$expected_ticks'"
fi

# ------------------------------- 10. time, needs, choice, scores, final tick
header "10. Every checkpoint carries time, needs, choice and all scores"

incomplete="$(grep '"type":"decision"' "$TRACE_ONE" \
    | awk '$0 !~ /"time_of_day":[0-9]/ || $0 !~ /"needs":\[/ || $0 !~ /"chosen":\{/ || $0 !~ /"candidates":\[/ { n++ } END { print n + 0 }')"
if [ "$incomplete" = "0" ]; then
    pass "all 24 records carry a time_of_day, a needs array, a chosen object and a candidate list"
else
    fail "$incomplete decision record(s) are missing time, needs, choice or candidates"
fi

wrong_score_count="$(grep '"type":"decision"' "$TRACE_ONE" \
    | awk '{ n = gsub(/"score":/, "&"); if (n != 7) bad++ } END { print bad + 0 }')"
if [ "$wrong_score_count" = "0" ]; then
    pass "each record scores six candidates plus the choice — 7 scores, all present"
else
    fail "$wrong_score_count decision record(s) do not carry 7 scores"
fi

if grep -q '"final_tick":240' "$TRACE_ONE"; then
    pass "the trace's final tick is 240"
else
    fail "the trace does not record a final tick of 240"
fi

if grep -q 'final_tick=240' "$LOG_ONE"; then
    pass "the engine marker reports final_tick=240"
else
    fail "the engine marker does not report final_tick=240"
fi

if grep -q '"sequential_equals_direct":true' "$TRACE_ONE" \
        && grep -q '"direct_0_240_needs":\[' "$TRACE_ONE"; then
    pass "24 sequential advances are recorded as matching one direct 0 -> 240 advance"
else
    fail "the trace does not record the sequential-versus-direct comparison"
fi

if grep -q '"next_decay_steps":1' "$TRACE_ONE"; then
    pass "the trace records exactly one donor decay boundary crossed per checkpoint"
else
    fail "the trace records no per-checkpoint decay-step count"
fi

# ----------------------------------- 11. two runs, byte-identical trace
header "11. Two independent runs of the fixed day are byte-identical"

day2_rc=0
bash "$RUN_DAY" "$TRACE_TWO" >"$LOG_TWO" 2>&1 || day2_rc=$?
if [ "$day2_rc" -eq 0 ]; then
    pass "the second day run also exits 0"
else
    fail "the second day run exited $day2_rc:"
    tail_log "$LOG_TWO"
fi

if [ -s "$TRACE_TWO" ]; then
    pass "the second trace is present and non-empty"
else
    fail "no non-empty second trace at $TRACE_TWO"
fi

if cmp -s "$TRACE_ONE" "$TRACE_TWO"; then
    pass "the two traces are byte-identical"
else
    fail "the two traces differ:"
    cmp "$TRACE_ONE" "$TRACE_TWO" 2>&1 | sed 's/^/      | /'
fi

hash_one="$(sha256sum "$TRACE_ONE" 2>/dev/null | cut -d' ' -f1)"
hash_two="$(sha256sum "$TRACE_TWO" 2>/dev/null | cut -d' ' -f1)"
if [ -n "$hash_one" ] && [ "$hash_one" = "$hash_two" ]; then
    pass "sha256 of both traces: $hash_one"
else
    fail "trace hashes differ: '$hash_one' vs '$hash_two'"
fi

# ------------------------------------- 12. day markers, and no failure marker
header "12. REMICH_DAY_OK appears, and no failure or parse error does"

for log in "$LOG_ONE" "$LOG_TWO"; do
    if grep -q '^REMICH_DAY_OK ' "$log"; then
        pass "$(basename "$log"): REMICH_DAY_OK observed"
        grep '^REMICH_DAY_OK ' "$log" | sed 's/^/      | /'
    else
        fail "$(basename "$log"): no REMICH_DAY_OK marker"
    fi
done

if grep -q '^REMICH_DAY_OK checkpoints=24 final_tick=240 ' "$LOG_ONE" \
        && grep -q '^REMICH_DAY_OK checkpoints=24 final_tick=240 ' "$LOG_TWO"; then
    pass "both markers report checkpoints=24 and final_tick=240"
else
    fail "a day marker does not report checkpoints=24 final_tick=240"
fi

if grep -qE '^REMICH_DAY_OK .*distinct=[0-9]+ .*first_id=[0-9]+ .*last_id=[0-9]+ ' "$LOG_ONE"; then
    pass "the marker summarises first choice, last choice and distinct ids"
    grep '^REMICH_DAY_OK ' "$LOG_ONE" | sed 's/^/      | /'
else
    fail "the day marker carries no first/last/distinct summary"
fi

if grep -qE '^REMICH_DAY_OK .*first_name=.+ last_id=[0-9]+ last_name=.+' "$LOG_ONE"; then
    pass "the marker names the first and last chosen activities"
else
    fail "the day marker does not name the first and last chosen activities"
fi

problem_pattern='REMICH_(DAY|SCORER|DECAY|BRIDGE)_FAIL|SCRIPT ERROR|Parse Error'
problem_lines=""
for log in "$LOG_ONE" "$LOG_TWO" "$LOG_PLAIN"; do
    hit="$(grep -nE "$problem_pattern" "$log" 2>/dev/null || true)"
    if [ -n "$hit" ]; then
        problem_lines="$problem_lines$(basename "$log"):
$hit
"
    fi
done
if [ -z "$problem_lines" ]; then
    pass "no day/scorer/decay/bridge failure marker, and no script or parse error, in any run"
else
    fail "a run reported a failure or a script/parse error:"
    printf '%s' "$problem_lines" | sed 's/^/      | /'
fi

# ------------------------------------ 13. the earlier probes stay green
header "13. Step 4's scorer proof and Step 2's bridge proof remain green"

for log in "$LOG_ONE" "$LOG_TWO" "$LOG_PLAIN"; do
    base="$(basename "$log")"
    if grep -q '^REMICH_SCORER_OK ' "$log"; then
        pass "$base: REMICH_SCORER_OK present (Step 4)"
    else
        fail "$base: no REMICH_SCORER_OK marker (Step 4 regressed)"
    fi
    if grep -q '^REMICH_DECAY_OK ' "$log"; then
        pass "$base: REMICH_DECAY_OK present (Step 4)"
    else
        fail "$base: no REMICH_DECAY_OK marker (Step 4 regressed)"
    fi
    if grep -q '^REMICH_BRIDGE_OK ' "$log"; then
        pass "$base: REMICH_BRIDGE_OK present (Step 2)"
    else
        fail "$base: no REMICH_BRIDGE_OK marker (Step 2 regressed)"
    fi
done

# ------------------------------------------ 14. workspace build and tests
header "14. The workspace builds without warnings and its tests pass"

if cargo build --workspace >"$LOG_DIR/build.log" 2>&1; then
    pass "cargo build --workspace"
else
    fail "cargo build --workspace failed:"
    tail -n 40 "$LOG_DIR/build.log" | sed 's/^/      | /'
fi

if grep -q '^warning' "$LOG_DIR/build.log"; then
    fail "the workspace build emitted warnings:"
    grep '^warning' "$LOG_DIR/build.log" | sed 's/^/      | /'
else
    pass "the workspace build is warning-free"
fi

if cargo test --workspace >"$LOG_DIR/test.log" 2>&1; then
    pass "cargo test --workspace"
else
    fail "cargo test --workspace failed:"
    tail -n 60 "$LOG_DIR/test.log" | sed 's/^/      | /'
fi

# --------------------------- 15. no tracked trace, no timing probe remains
header "15. Generated traces are not tracked and no timing probe remains"

# The harness only ever writes `*.jsonl`, and only where REMICH_DAY_TRACE_PATH
# points; a pathspec match keeps this check about traces rather than about the
# file named check_day_trace.py.
tracked_traces="$(git ls-files -- '*.jsonl' 2>/dev/null)"
if [ -z "$tracked_traces" ]; then
    pass "no generated trace file (*.jsonl) is tracked by git"
else
    fail "a generated trace file is tracked by git:"
    printf '%s\n' "$tracked_traces" | sed 's/^/      | /'
fi

if git check-ignore -q day_trace-example.jsonl; then
    pass "a trace dropped inside the working tree is ignored"
else
    fail "day_trace*.jsonl is not ignored by .gitignore"
fi

rev="$(sed -n 's/^[[:space:]]*pub const SCORER_BRIDGE_REV: &str = "\([^"]*\)".*/\1/p' "$GDEX_SRC" 2>/dev/null)"
if [ "$rev" = "$COMMITTED_SCORER_REV" ]; then
    pass "SCORER_BRIDGE_REV holds its committed value ('$rev') — the probe was restored"
else
    fail "SCORER_BRIDGE_REV is '$rev', expected '$COMMITTED_SCORER_REV' — the probe was not reverted"
fi

# A probed revision may survive only in documentation that records a rebuild
# measurement, or in the acceptance scripts that name it. This deliberately
# never spells the probed value out, so it generalises over every revision the
# lane may measure instead of hard-coding today's.
revision_files="$(grep -rlE 'remich-scorer-v[0-9]+' . \
    --exclude-dir=.git --exclude-dir=target --exclude-dir=.godot \
    --include='*.rs' --include='*.toml' --include='*.gd' --include='*.gdextension' \
    --include='*.sh' --include='*.py' --include='*.md' --include='*.json' 2>/dev/null \
    | sed 's|^\./||' | sort -u)"
probe_outside=""
while IFS= read -r file; do
    [ -z "$file" ] && continue
    others="$(grep -ohE 'remich-scorer-v[0-9]+' "$file" 2>/dev/null | sort -u \
        | grep -vFx "$COMMITTED_SCORER_REV" || true)"
    [ -z "$others" ] && continue
    case "$file" in
        docs/*.md) : ;;                     # records that document a measurement
        tools/check_phase1_step*.sh) : ;;   # the checkers that name it
        *) probe_outside="$probe_outside$file: $others
" ;;
    esac
done <<<"$revision_files"
if [ -z "$probe_outside" ]; then
    pass "no revision other than '$COMMITTED_SCORER_REV' survives outside documentation"
    note "files naming a revision: $(printf '%s' "$revision_files" | tr '\n' ' ')"
else
    fail "a probed revision survives in a source, build or Godot file:"
    printf '%s' "$probe_outside" | sed 's/^/      | /'
fi

# ----------------------------------------- 16. both timings are recorded
header "16. Both rebuild timings and the restore evidence are recorded"

missing_record_bits=""
for needle in \
    'Clean build' \
    'One-line probe' \
    'cargo clean' \
    "bash tools/run_day.sh" \
    'sha256' \
    'REMICH_DAY_OK' \
    'test-harness'
do
    if ! grep -qF "$needle" "$RECORD_DOC" 2>/dev/null; then
        missing_record_bits="$missing_record_bits $needle"
    fi
done
if [ -n "$missing_record_bits" ]; then
    fail "$RECORD_DOC is missing:$missing_record_bits"
else
    pass "$RECORD_DOC records both timings, the exact commands and the restore evidence"
fi

if grep -qE '\| (Clean build|One-line probe)[^|]*\|[^|]*\| \*\*[0-9]+\.[0-9]{2} s\*\*' "$RECORD_DOC"; then
    pass "the timing table carries wall-clock seconds"
    grep -E '^\| (Clean build|One-line probe)' "$RECORD_DOC" | sed 's/^/      | /'
else
    fail "$RECORD_DOC has no timing table with wall-clock seconds"
fi

# ------------------------------------------------- 17. the worktree is clean
header "17. The worktree is clean at this head"

stray="$(git status --porcelain 2>/dev/null)"
if [ -z "$stray" ]; then
    pass "no modified, staged or untracked file remains"
else
    fail "the worktree is not clean at the acceptance head:"
    printf '%s\n' "$stray" | sed 's/^/      | /'
fi

# ------------------------------------- 18. no other repository was modified
header "18. No other repository was modified"

vault_head="$(git -C "$VAULT" rev-parse HEAD 2>/dev/null || echo missing)"
if [ "$vault_head" = "$VAULT_COMMIT" ]; then
    pass "the read-only donor vault is still at $VAULT_COMMIT"
else
    fail "the donor vault HEAD is '$vault_head', expected $VAULT_COMMIT"
fi

vault_stray="$(git -C "$VAULT" status --porcelain 2>/dev/null | head -5)"
if [ -z "$vault_stray" ]; then
    pass "the donor vault worktree is clean — nothing was written into it"
else
    fail "the donor vault worktree is dirty:"
    printf '%s\n' "$vault_stray" | sed 's/^/      | /'
fi

for repo in Munshausen Larochette Eisleck; do
    dir="/home/mrg/Documents/Project/$repo"
    if [ -d "$dir" ] && [ -e "$dir/.git" ]; then
        if [ -z "$(git -C "$dir" status --porcelain 2>/dev/null | head -5)" ]; then
            pass "$repo is untouched (clean)"
        else
            fail "$repo is dirty — this step must not modify it"
        fi
    fi
done

# The only external paths this repository may name are the pinned engine and
# the read-only donor vault used by Step 3's own checker.
refs="$(grep -rhoE '/home/mrg/Documents/Project/[A-Za-z0-9._-]+' \
    --include='*.rs' --include='*.toml' --include='*.gd' --include='*.gdextension' \
    --include='*.md' --include='*.sh' --include='*.py' --include='*.json' . 2>/dev/null | sort -u)"
unexpected=""
while IFS= read -r ref; do
    [ -z "$ref" ] && continue
    case "$ref" in
        "/home/mrg/Documents/Project/Yolanda") ;;
        "/home/mrg/Documents/Project/buggy-vault") ;;
        *) unexpected="$unexpected$ref
" ;;
    esac
done <<<"$refs"
if [ -z "$unexpected" ]; then
    pass "the only external paths named are the pinned engine and the donor vault"
    printf '%s\n' "$refs" | sed 's/^/      | /'
else
    fail "this repository references another repository:"
    printf '%s\n' "$unexpected" | sed 's/^/      | /'
fi

# ------------------------------------------------------------------ summary
printf '\n========================================\n'
if [ "$failures" -eq 0 ]; then
    printf 'PASS  Phase 1 Step 5 — a day in the test project\n'
    printf '========================================\n'
    exit 0
fi
printf 'FAIL  Phase 1 Step 5 — %d check(s) failed\n' "$failures"
printf '========================================\n'
exit 1
