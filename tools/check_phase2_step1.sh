#!/usr/bin/env bash
# Phase 2, Step 1 acceptance check — "one clock" (docs/PLAN.md §4a, step 1;
# record: docs/remich-clock-phase2-step1.md).
#
# One command, from anywhere:
#
#     bash tools/check_phase2_step1.sh
#
# It re-proves, directly, every capability this step must preserve and add.
# The Phase 1 checkers stay untouched historical qualification records: their
# freeze assertions (plan/Rust byte-identical to their own merge bases) cannot
# survive intentional Phase 2 work, so this script does not relax them — it
# re-establishes their substance instead. Where a Phase 1 checker is still
# expected to be green as-is (Step 3: donor byte-identity, provenance,
# firewall, bridge, build/tests, clean head), it is run as a sub-check.
#
# Requirements, as checks (numbered as the step prompt numbered them):
#
#   1. the Phase 2 plan merge is an ancestor of this head;
#   2. Step 3 donor code/data and provenance remain unchanged
#      (Step 3 acceptance green + explicit diff against the reviewed merge);
#   3. the clock core is engine-free;
#   4. authoritative clock fields/advancement use integer representations,
#      not accumulated floats (behaviour tests + compiled self-checks);
#   5. the fixed tick duration exists and is exact;
#   6. pause/resume tests pass;
#   7. speed-1 progression is consecutive;
#   8. speed-4 progression is consecutive and skips no simulation tick;
#   9. speed 1 and speed 4 produce the same ordered simulation ticks;
#  10. exactly one real shared Godot clock node exists;
#  11. the day/scorer temporal inputs come from that shared clock, not from
#      a second GDScript tick authority;
#  12. pinned Godot 4.7.2 loads and calls the clock through the real
#      GDExtension;
#  13. REMICH_CLOCK_OK is observed;
#  14. REMICH_SCORER_OK, REMICH_DECAY_OK and REMICH_BRIDGE_OK still appear;
#  15. a complete speed-1 day succeeds;
#  16. a complete speed-4 day succeeds;
#  17. their simulation traces are byte-identical;
#  18. their SHA-256 hashes match (both are reported);
#  19. the workspace builds and tests warning-free;
#  20. no generated trace/build/staging state is tracked;
#  21. no float-clock sabotage remains;
#  22. the worktree is clean;
#  23. no other repository was modified.
#
# The traces this script compares live outside the worktree, so the runs
# themselves cannot make check 22 look dirty.

set -uo pipefail

REPO_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)" || exit 1
cd "$REPO_ROOT" || exit 1

# Qualified headless path only: never editor, import or export mode.
GODOT_BIN="/home/mrg/Documents/Project/Yolanda/.godot-local/engine/4.7.2/Godot_v4.7.2-stable_linux.x86_64"
GODOT_PROJECT="godot"

VAULT="/home/mrg/Documents/Project/buggy-vault"
VAULT_COMMIT="24181142c693be37f90a6a667a6dc493425cd832"
# The merge commit that opened phase 2 (PR #7, reviewed plan head 1c9d638):
# donor code/data, provenance and the plan must be unchanged since it.
PHASE2_PLAN_MERGE="4bcb40dcbfbc1a5eccc6ac46d088f251678f4940"
# The merge commit that closed phase 1 (PR #6): also an ancestor of this head.
PHASE1_FINAL_MERGE="be11fa1cbaf7ab6f7bf5766806c47e1111a2fbc2"

CLOCK_SRC="crates/remich_core/src/clock.rs"
CORE_SRC_DIR="crates/remich_core/src"
GDEX_SRC="crates/remich_gdext/src/lib.rs"
WORLD_CLOCK_GD="godot/world_clock.gd"
DAY_PROBE="godot/day_probe.gd"
CLOCK_PROBE="godot/clock_probe.gd"
PROBE_PROJECT="godot/project.godot"
TRACE_VALIDATOR="tools/check_day_trace.py"
RUN_DAY="tools/run_day.sh"
RECORD_DOC="docs/remich-clock-phase2-step1.md"
STEP3_DOC="docs/anvil-import-phase1-step3.md"
PLAN_DOC="docs/PLAN.md"
# Remich issue #9 / Phase 3 Step 1 (the embedded action catalogue): the one
# donor file this step is authorized to change, and the lead's Phase 3 plan
# merge (that merge extended the plan after PHASE2_PLAN_MERGE, so the plan
# can no longer match it byte for byte). docs/PLAN.md's freeze point is
# PLAN_FREEZE below — the lead's Phase 3 Step 2 re-scope.
N9_CATALOGUE="crates/anvil_sim/src/actions/catalogue.rs"
PLAN_MERGE="cfa796cc4885432da93b1974602ef3ba9a7cbff8"
# Remich Phase 3 Step 2 — soul primitives across the bridge (the lead's
# docs-only plan re-scope, 2026-10-01): docs/PLAN.md's byte-for-byte freeze
# point moved from $PLAN_MERGE to the commit that made the amendment, so plan
# content is compared against PLAN_FREEZE below. $PLAN_MERGE stays the
# ancestry base and the checker-freeze base. Any further edit to the plan
# still fails these checks; re-pin PLAN_FREEZE only for an authorized
# amendment.
PLAN_FREEZE="02eff4214c97d31743e7486a9d905fa5c22541a6"

COMMITTED_CLOCK_REV="remich-clock-v1"
# The rebuild-measurement sentinel, spelled so this script never trips its own
# check: it may survive only in documentation that records the measurement.
CLOCK_SENTINEL="$(printf 'remich-clock-v%s' '2')"

TRACE_ENV="REMICH_DAY_TRACE_PATH"
SPEED_ENV="REMICH_CLOCK_SPEED"

LOG_DIR="$(mktemp -d "${TMPDIR:-/tmp}/remich-p2s1.XXXXXX")" || exit 1
trap 'rm -rf "$LOG_DIR"' EXIT

# Three runs of the SAME fixed day: two at speed 1 (determinism) and one at
# speed 4. All three traces must be byte-identical.
TRACE_S1A="$LOG_DIR/day-speed1-run1.jsonl"
TRACE_S1B="$LOG_DIR/day-speed1-run2.jsonl"
TRACE_S4="$LOG_DIR/day-speed4.jsonl"
LOG_S1A="$LOG_DIR/day-speed1-run1.log"
LOG_S1B="$LOG_DIR/day-speed1-run2.log"
LOG_S4="$LOG_DIR/day-speed4.log"

failures=0
pass() { printf 'ok    %s\n' "$1"; }
fail() { printf 'FAIL  %s\n' "$1"; failures=$((failures + 1)); }
note() { printf '      %s\n' "$1"; }
header() { printf '\n== %s ==\n' "$1"; }
tail_log() { tail -n 25 "$1" | sed 's/^/      | /'; }

# ------------------------------------------- 1. the plan merge is an ancestor
header "1. The Phase 2 plan merge is an ancestor of this head"

if git merge-base --is-ancestor "$PHASE2_PLAN_MERGE" HEAD 2>/dev/null; then
    pass "the Phase 2 plan merge $PHASE2_PLAN_MERGE is an ancestor of HEAD"
else
    fail "the Phase 2 plan merge $PHASE2_PLAN_MERGE is NOT an ancestor of HEAD"
fi

if git merge-base --is-ancestor "$PHASE1_FINAL_MERGE" HEAD 2>/dev/null; then
    pass "the Phase 1 final merge $PHASE1_FINAL_MERGE is an ancestor of HEAD"
else
    fail "the Phase 1 final merge $PHASE1_FINAL_MERGE is NOT an ancestor of HEAD"
fi

note "HEAD is $(git rev-parse HEAD)"

# ------------------------- 2. Step 3 donor code/data and provenance unchanged
header "2. Step 3 donor code/data and provenance remain unchanged"

# The deep re-proof: the Step 3 acceptance hashes every donor file against the
# pinned vault, checks provenance, firewall, donor tests and the bridge. It is
# expected to be green on a Phase 2 head; if it fails, its FAIL lines say why.
if bash tools/check_phase1_step3.sh >"$LOG_DIR/step3.log" 2>&1; then
    pass "bash tools/check_phase1_step3.sh exits 0 (donor byte-identity, provenance, firewall, bridge)"
    tail -n 3 "$LOG_DIR/step3.log" | sed 's/^/      | /'
else
    fail "bash tools/check_phase1_step3.sh failed:"
    grep '^FAIL' "$LOG_DIR/step3.log" | sed 's/^/      | /'
    tail -n 40 "$LOG_DIR/step3.log" | sed 's/^/      | /'
fi

# Remich issue #9 / Phase 3 Step 1: two named exceptions — the authorized
# catalogue embedding and the provenance record that documents it (its
# content is guarded by the Step 3 sub-check above). docs/PLAN.md was
# extended by the lead's Phase 3 plan merge after this base, then amended by
# the lead's Phase 3 Step 2 re-scope, so it is frozen byte-for-byte at
# $PLAN_FREEZE instead, which still forbids rewriting it here.
donor_delta="$(git diff --name-only "$PHASE2_PLAN_MERGE" -- \
    crates/anvil_sim crates/anvil_core assets "$STEP3_DOC" 2>/dev/null \
    | grep -vxF "$N9_CATALOGUE" | grep -vxF "$STEP3_DOC" || true)"
plan_delta=""
if ! git diff --quiet "$PLAN_FREEZE" -- "$PLAN_DOC" 2>/dev/null; then
    plan_delta="$PLAN_DOC"
fi
combined="$(printf '%s\n%s\n' "$donor_delta" "$plan_delta" | sed '/^$/d')"
if [ -z "$combined" ]; then
    pass "donor crates and data are unchanged but for the authorized $N9_CATALOGUE, the provenance record documents it, and docs/PLAN.md matches the plan re-scope freeze"
else
    fail "donor code/data, provenance or the plan changed beyond the Remich #9 authorization:"
    printf '%s\n' "$combined" | sed 's/^/      | /'
fi

if grep -qF "buggy-vault@${VAULT_COMMIT:0:8}" "$STEP3_DOC" 2>/dev/null; then
    pass "the provenance record still names the pinned donor"
else
    fail "the provenance record no longer names the pinned donor"
fi

# ---------------------------------------------- 3. the clock core is engine-free
header "3. The clock core is engine-free"

if grep -qiE 'godot|gdext' crates/remich_core/Cargo.toml; then
    fail "remich_core's manifest names an engine:"
    grep -niE 'godot|gdext' crates/remich_core/Cargo.toml | sed 's/^/      | /'
else
    pass "remich_core's manifest names no engine"
fi

if grep -rqiE 'godot|gdext' "$CORE_SRC_DIR"; then
    fail "remich_core's source names an engine (the firewall is broken):"
    grep -rniE 'godot|gdext' "$CORE_SRC_DIR" | sed 's/^/      | /'
else
    pass "the engine-free core — including $CLOCK_SRC — names no engine at all"
fi

strip_paths='s/ \((path[+]file:)?\/[^)]*\)//g'
if cargo tree -p remich_core --edges normal,build 2>/dev/null | sed -E "$strip_paths" \
        | grep -qiE 'godot|gdext'; then
    fail "cargo tree -p remich_core resolves an engine crate"
else
    pass "cargo tree -p remich_core resolves no engine crate"
fi

# -------------------------------- 4. integer authority, not accumulated floats
header "4. Authoritative clock state and advancement are integer, not floats"

# The behavioural proof is the test run below; this asserts the tests exist by
# name and that the compiled self-checks are among them. Behavioural beats
# textual: the source self-test compiles the file and fails on any float type
# outside cycle_position or any seconds-accumulating idiom.
if cargo test -p remich_core clock::tests >"$LOG_DIR/clock-tests.log" 2>&1; then
    pass "cargo test -p remich_core clock::tests"
else
    fail "cargo test -p remich_core clock::tests failed:"
    tail -n 60 "$LOG_DIR/clock-tests.log" | sed 's/^/      | /'
fi

for test_name in \
    authoritative_fields_are_integer_types \
    the_authoritative_clock_source_uses_no_float_time \
    cycle_position_matches_the_test_fixture_derivation
do
    if grep -qE "(^|[[:space:]:])${test_name} \.\.\. ok$" "$LOG_DIR/clock-tests.log" 2>/dev/null; then
        pass "integer-authority test green: $test_name"
    else
        fail "integer-authority test not green: $test_name"
    fi
done

# --------------------------------------------- 5. the fixed tick duration
header "5. The fixed tick duration exists and is exact"

for test_name in \
    zero_tick_length_is_refused \
    tick_length_is_exact_integer_state_that_does_not_drift
do
    if grep -qE "(^|[[:space:]:])${test_name} \.\.\. ok$" "$LOG_DIR/clock-tests.log" 2>/dev/null; then
        pass "tick-length test green: $test_name"
    else
        fail "tick-length test not green: $test_name"
    fi
done

# ------------------------------------------------------ 6. pause/resume tests
header "6. Pause/resume tests pass"

for test_name in \
    paused_pulses_emit_nothing_and_leave_the_tick_unchanged \
    resume_continues_from_exactly_the_next_tick \
    speed_is_retained_across_pause_and_changed_only_on_request \
    zero_speed_is_refused_rather_than_silently_pausing
do
    if grep -qE "(^|[[:space:]:])${test_name} \.\.\. ok$" "$LOG_DIR/clock-tests.log" 2>/dev/null; then
        pass "pause/resume test green: $test_name"
    else
        fail "pause/resume test not green: $test_name"
    fi
done

# ------------------------------------------ 7. speed-1 progression consecutive
header "7. Speed-1 progression is consecutive"

for test_name in \
    speed_one_pulse_emits_one_consecutive_tick \
    starts_from_the_configured_tick
do
    if grep -qE "(^|[[:space:]:])${test_name} \.\.\. ok$" "$LOG_DIR/clock-tests.log" 2>/dev/null; then
        pass "speed-1 test green: $test_name"
    else
        fail "speed-1 test not green: $test_name"
    fi
done

# ------------------------- 8. speed-4 consecutive, no simulation tick skipped
header "8. Speed-4 progression is consecutive and skips no simulation tick"

for test_name in \
    speed_four_pulse_emits_four_consecutive_ticks \
    a_speed_four_pulse_cannot_turn_8_into_12 \
    no_tick_is_skipped_or_repeated_across_a_long_run \
    long_run_reaches_the_exact_expected_tick \
    batch_iteration_covers_every_tick_exactly_once
do
    if grep -qE "(^|[[:space:]:])${test_name} \.\.\. ok$" "$LOG_DIR/clock-tests.log" 2>/dev/null; then
        pass "speed-4 test green: $test_name"
    else
        fail "speed-4 test not green: $test_name"
    fi
done

# ---------------------- 9. speed 1 and speed 4: the same ordered simulation ticks
header "9. Speed 1 and speed 4 produce the same ordered simulation ticks"

if grep -qE "(^|[[:space:]:])speed_one_and_speed_four_emit_the_same_ordered_ticks \.\.\. ok$" \
        "$LOG_DIR/clock-tests.log" 2>/dev/null; then
    pass "speed-equivalence test green: identical tick sequence, only the pulse count differs"
else
    fail "speed-equivalence test not green: speed_one_and_speed_four_emit_the_same_ordered_ticks"
fi

# --------------------------------------- 10. one real shared Godot clock node
header "10. Exactly one real shared Godot clock node exists"

if grep -q 'const CLOCK_CLASS := "RemichWorldClock"' "$WORLD_CLOCK_GD" 2>/dev/null; then
    pass "$WORLD_CLOCK_GD targets the native RemichWorldClock class"
else
    fail "$WORLD_CLOCK_GD does not name the native clock class"
fi

instantiations="$(grep -c 'ClassDB.instantiate(CLOCK_CLASS)' godot/*.gd 2>/dev/null \
    | grep -v ':0$' || true)"
if [ "$instantiations" = "$WORLD_CLOCK_GD:1" ]; then
    pass "exactly one script instantiates the native clock — $WORLD_CLOCK_GD, once"
else
    fail "the native clock class is instantiated in: ${instantiations:-nowhere}"
fi

if [ "$(grep -c '^WorldClock=' "$PROBE_PROJECT" 2>/dev/null)" = "1" ]; then
    pass "project.godot declares exactly one WorldClock autoload"
else
    fail "project.godot does not declare exactly one WorldClock autoload"
fi

if grep -q 'REMICH_CLOCK_OK' "$CLOCK_PROBE" 2>/dev/null; then
    pass "the clock proof ($CLOCK_PROBE) exists"
else
    fail "the clock proof $CLOCK_PROBE is missing"
fi

# --------------------------------- 11. day/scorer temporal inputs from the clock
header "11. The day's temporal inputs come from the shared clock"

# Structural statements about this particular harness (the behaviour itself is
# proved in checks 12-18 by the engine): the day reads ticks from the shared
# clock's pulse, derives time of day through the shared clock, and holds no
# second authority of its own.
for needle in \
    "WorldClock.pulse()" \
    "WorldClock.cycle_position(tick, TEST_CYCLE_LENGTH)" \
    "WorldClock.is_ready()"
do
    if grep -qF "$needle" "$DAY_PROBE"; then
        pass "the day harness reads the clock: $needle"
    else
        fail "the day harness does not read: $needle"
    fi
done

if grep -qE 'checkpoint[[:space:]]*\*[[:space:]]*TICKS_PER_CHECKPOINT' "$DAY_PROBE"; then
    fail "the day harness still synthesizes its own ticks (checkpoint * TICKS_PER_CHECKPOINT)"
else
    pass "the day harness has no independent tick synthesis (no checkpoint * ticks counter)"
fi

if grep -qF 'WorldClock.cycle_position' "$DAY_PROBE" \
        && ! grep -qE 'float\(checkpoint\)[[:space:]]*/[[:space:]]*float\(CHECKPOINTS\)' "$DAY_PROBE"; then
    pass "time_of_day is derived by the shared clock, not by a checkpoint counter in GDScript"
else
    fail "time_of_day is still computed by a GDScript checkpoint counter"
fi

# ------------------- 12-16. pinned Godot: clock, scorer, day at speeds 1 and 4
header "12-16. Pinned Godot 4.7.2: the real GDExtension clock, scorer and day runs"

if [ -x "$GODOT_BIN" ]; then
    pass "the pinned engine exists at the qualified path"
    godot_version="$("$GODOT_BIN" --version 2>/dev/null | tail -n 1)"
    case "$godot_version" in
        4.7.2*) pass "pinned Godot --version: $godot_version" ;;
        *) fail "pinned Godot --version is '$godot_version', expected 4.7.2" ;;
    esac
else
    fail "the pinned engine is missing at $GODOT_BIN"
fi

# Every engine invocation in tools/ must be headless and never enter editor,
# import or export mode (also what keeps Yolanda byte-for-byte untouched).
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

# Three runs of the fixed day: two at speed 1, one at speed 4.
run_rc=0
bash "$RUN_DAY" "$TRACE_S1A" 1 >"$LOG_S1A" 2>&1 || run_rc=$?
if [ "$run_rc" -eq 0 ]; then
    pass "the complete speed-1 day exits 0 (run 1)"
else
    fail "the speed-1 day run 1 exited $run_rc:"
    tail_log "$LOG_S1A"
fi

run_rc=0
bash "$RUN_DAY" "$TRACE_S1B" 1 >"$LOG_S1B" 2>&1 || run_rc=$?
if [ "$run_rc" -eq 0 ]; then
    pass "the complete speed-1 day exits 0 (run 2 — determinism)"
else
    fail "the speed-1 day run 2 exited $run_rc:"
    tail_log "$LOG_S1B"
fi

run_rc=0
bash "$RUN_DAY" "$TRACE_S4" 4 >"$LOG_S4" 2>&1 || run_rc=$?
if [ "$run_rc" -eq 0 ]; then
    pass "the complete speed-4 day exits 0"
else
    fail "the speed-4 day run exited $run_rc:"
    tail_log "$LOG_S4"
fi

problem_pattern='REMICH_(DAY|SCORER|DECAY|BRIDGE|CLOCK)_FAIL|SCRIPT ERROR|Parse Error'
problem_lines=""
for log in "$LOG_S1A" "$LOG_S1B" "$LOG_S4"; do
    hit="$(grep -nE "$problem_pattern" "$log" 2>/dev/null || true)"
    if [ -n "$hit" ]; then
        problem_lines="$problem_lines$(basename "$log"):
$hit
"
    fi
done
if [ -z "$problem_lines" ]; then
    pass "no day/scorer/decay/bridge/clock failure marker and no script error, in any run"
else
    fail "a run reported a failure or a script/parse error:"
    printf '%s' "$problem_lines" | sed 's/^/      | /'
fi

# 12-13: the real GDExtension clock was loaded, called and observed.
if grep -qE '^REMICH_CLOCK_OK tick=[0-9]+ speed=[0-9]+ paused=(true|false) ' "$LOG_S1A" \
        && grep -qE '^REMICH_CLOCK_OK tick=[0-9]+ speed=[0-9]+ paused=(true|false) ' "$LOG_S1B" \
        && grep -qE '^REMICH_CLOCK_OK tick=[0-9]+ speed=[0-9]+ paused=(true|false) ' "$LOG_S4"; then
    pass "REMICH_CLOCK_OK observed in all three runs"
    grep -h '^REMICH_CLOCK_OK ' "$LOG_S1A" "$LOG_S4" | sed 's/^/      | /'
else
    fail "REMICH_CLOCK_OK is missing from at least one run:"
    for log in "$LOG_S1A" "$LOG_S1B" "$LOG_S4"; do
        grep -c '^REMICH_CLOCK_OK ' "$log" 2>/dev/null | sed "s|^|      $(basename "$log"): |"
    done
fi

if grep -q '^REMICH_CLOCK_OK .*tick_length_ns=100000000 ' "$LOG_S1A"; then
    pass "the clock proof observed the exact test-project tick length (100000000 ns)"
else
    fail "the clock proof did not report the declared tick length"
fi

# 11 + 12, behaviourally: the proof asserts the shared node sits at the day's
# final tick (the day drove THIS clock), pulse has no delta argument, and the
# speed-4 batches were consecutive.
for needle in \
    'day_final_tick=240' \
    'pulse_args=0' \
    'resume_batch=240,241,242,243' \
    'speed4_second=244,245,246,247' \
    'speed1_batch=248'
do
    if grep -q "^REMICH_CLOCK_OK $needle" "$LOG_S1A" || grep -q " $needle" "$LOG_S1A"; then
        pass "in-engine clock proof: $needle"
    else
        fail "in-engine clock proof is missing: $needle"
    fi
done

if grep -q '^REMICH_CLOCK_OK .*day_final_tick=240 .*speed=1 ' "$LOG_S1A" \
        || grep -qE '^REMICH_CLOCK_OK tick=240 speed=1 .*day_final_tick=240' "$LOG_S1A"; then
    pass "speed-1 run: the shared clock was at tick 240 with speed 1 after the day"
else
    fail "speed-1 run: the shared clock's post-day state does not match the run"
fi
if grep -qE '^REMICH_CLOCK_OK tick=240 speed=4 .*day_final_tick=240' "$LOG_S4"; then
    pass "speed-4 run: the shared clock was at tick 240 with speed 4 after the day"
else
    fail "speed-4 run: the shared clock's post-day state does not match the run"
fi

# 14: the earlier qualified markers remain, in the same engine process.
for log in "$LOG_S1A" "$LOG_S1B" "$LOG_S4"; do
    base="$(basename "$log")"
    for marker in REMICH_SCORER_OK REMICH_DECAY_OK REMICH_BRIDGE_OK REMICH_DAY_OK; do
        if grep -q "^$marker " "$log"; then
            pass "$base: $marker present"
        else
            fail "$base: no $marker marker"
        fi
    done
done

if grep -q '^REMICH_DAY_OK checkpoints=24 final_tick=240 ' "$LOG_S1A" \
        && grep -q '^REMICH_DAY_OK checkpoints=24 final_tick=240 ' "$LOG_S1B" \
        && grep -q '^REMICH_DAY_OK checkpoints=24 final_tick=240 ' "$LOG_S4"; then
    pass "every complete day reports checkpoints=24 final_tick=240"
else
    fail "a day marker does not report checkpoints=24 final_tick=240"
fi

# ------------------------------------- 15-16. traces exist and validate
header "15-16. The complete day traces exist and validate independently"

for trace in "$TRACE_S1A" "$TRACE_S1B" "$TRACE_S4"; do
    if [ -s "$trace" ]; then
        pass "$(basename "$trace"): present and non-empty ($(wc -l <"$trace") lines)"
    else
        fail "$(basename "$trace"): missing or empty"
    fi
done

for trace in "$TRACE_S1A" "$TRACE_S4"; do
    if python3 "$TRACE_VALIDATOR" "$trace" >"$LOG_DIR/validator-$(basename "$trace").log" 2>&1; then
        pass "tools/check_day_trace.py accepts $(basename "$trace") (the Phase 1 fixture still holds)"
    else
        fail "the trace validator rejected $(basename "$trace"):"
        tail -n 40 "$LOG_DIR/validator-$(basename "$trace").log" | sed 's/^/      | /'
    fi
done

# ------------------------------- 17-18. byte-identical, SHA-256 reported and equal
header "17-18. The speed-1 and speed-4 traces are byte-identical with equal SHA-256"

if cmp -s "$TRACE_S1A" "$TRACE_S1B"; then
    pass "the two speed-1 runs are byte-identical (determinism under the new clock)"
else
    fail "the two speed-1 runs differ:"
    cmp "$TRACE_S1A" "$TRACE_S1B" 2>&1 | sed 's/^/      | /'
fi

if cmp -s "$TRACE_S1A" "$TRACE_S4"; then
    pass "the speed-1 and speed-4 traces are byte-identical"
else
    fail "the speed-1 and speed-4 traces differ:"
    cmp "$TRACE_S1A" "$TRACE_S4" 2>&1 | sed 's/^/      | /'
fi

hash_s1a="$(sha256sum "$TRACE_S1A" 2>/dev/null | cut -d' ' -f1)"
hash_s1b="$(sha256sum "$TRACE_S1B" 2>/dev/null | cut -d' ' -f1)"
hash_s4="$(sha256sum "$TRACE_S4" 2>/dev/null | cut -d' ' -f1)"
if [ -n "$hash_s1a" ] && [ "$hash_s1a" = "$hash_s1b" ] && [ "$hash_s1a" = "$hash_s4" ]; then
    pass "all three trace SHA-256 values match"
    note "speed-1 (run 1) sha256: $hash_s1a"
    note "speed-1 (run 2) sha256: $hash_s1b"
    note "speed-4        sha256: $hash_s4"
else
    fail "trace SHA-256 values differ: s1a=$hash_s1a s1b=$hash_s1b s4=$hash_s4"
fi

# The trace must still carry the qualified Phase 1 information.
for field in '"type":"decision"' '"tick":' '"time_of_day":' '"needs":[' \
    '"chosen":{' '"candidates":[' '"final_tick":240'; do
    if grep -qF "$field" "$TRACE_S4"; then
        pass "the trace still carries $field"
    else
        fail "the trace lost $field"
    fi
done

# ----------------------------------- 19. workspace build and tests warning-free
header "19. The workspace builds without warnings and its tests pass"

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

if grep -q '^warning' "$LOG_DIR/test.log"; then
    fail "cargo test emitted warnings:"
    grep '^warning' "$LOG_DIR/test.log" | sed 's/^/      | /'
else
    pass "cargo test is warning-free"
fi

# ------------------------- 20. no generated trace/build/staging state is tracked
header "20. No generated trace, build or staging state is tracked"

generated="$(git ls-files \
    | grep -E '(^|/)(target|\.godot|staging)(/|$)|\.so$|\.dylib$|\.dll$|_expectation\.txt$|\.jsonl$' \
    || true)"
if [ -z "$generated" ]; then
    pass "no build, import, library, expectation or trace file is tracked"
else
    fail "generated state is tracked by git:"
    printf '%s\n' "$generated" | sed 's/^/      | /'
fi

for ignored in godot/bridge_probe_expectation.txt godot/scorer_probe_expectation.txt \
        godot/clock_probe_expectation.txt day_trace-example.jsonl; do
    if git check-ignore -q "$ignored"; then
        pass "generated state is ignored: $ignored"
    else
        fail "generated state is not ignored: $ignored"
    fi
done

# --------------------------------- 21. no float-clock sabotage remains
header "21. No float-clock sabotage remains"

rev="$(sed -n 's/^[[:space:]]*pub const CLOCK_BRIDGE_REV: &str = "\([^"]*\)".*/\1/p' "$GDEX_SRC" 2>/dev/null)"
rev="${rev%%$'\n'*}"
if [ "$rev" = "$COMMITTED_CLOCK_REV" ]; then
    pass "CLOCK_BRIDGE_REV holds its committed value ('$rev') — the rebuild probe was restored"
else
    fail "CLOCK_BRIDGE_REV is '$rev', expected '$COMMITTED_CLOCK_REV' — the probe was not reverted"
fi

# The rebuild-measurement sentinel may survive only in documentation that
# records it and in this checker, which names it.
sentinel_files="$(grep -rlF "$CLOCK_SENTINEL" . \
    --exclude-dir=.git --exclude-dir=target --exclude-dir=.godot \
    --exclude='check_phase2_step1.sh' 2>/dev/null | sed 's|^\./||' | sort || true)"
unexpected=""
while IFS= read -r file; do
    [ -z "$file" ] && continue
    case "$file" in
        docs/*.md) : ;;   # the record that documents the measurement
        *) unexpected="$unexpected$file
" ;;
    esac
done <<<"$sentinel_files"
if [ -z "$unexpected" ]; then
    pass "the rebuild sentinel survives only in documentation"
else
    fail "the rebuild sentinel survives outside documentation:"
    printf '%s' "$unexpected" | sed 's/^/      | /'
fi

# The compiled integer-authority self-check (check 4) fails if accumulated
# float time returns to the clock; name it here so this section stands alone.
if grep -qE "(^|[[:space:]:])the_authoritative_clock_source_uses_no_float_time \.\.\. ok$" \
        "$LOG_DIR/clock-tests.log" 2>/dev/null; then
    pass "the clock source self-check is green: no float time in the authority"
else
    fail "the clock source self-check is not green"
fi

# ------------------------------------------------------------ 22. clean head
header "22. The worktree is clean at this head"

stray="$(git status --porcelain 2>/dev/null)"
if [ -z "$stray" ]; then
    pass "no modified, staged or untracked file remains"
else
    fail "the worktree is not clean at the acceptance head:"
    printf '%s\n' "$stray" | sed 's/^/      | /'
fi

# ------------------------------------- 23. no other repository was modified
header "23. No other repository was modified"

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

for repo in Munshausen Larochette Eisleck Grengewald Marnach; do
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
# the read-only donor vault (Yolanda for the engine, buggy-vault for the
# donor). Yolanda itself is never opened in editor mode — asserted by the
# headless scan in check 12 — which is what keeps it byte-for-byte untouched.
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
    printf '%s' "$unexpected" | sed 's/^/      | /'
fi

# ------------------------------------------------------------------ summary
printf '\n========================================\n'
if [ "$failures" -eq 0 ]; then
    printf 'PASS  Phase 2 Step 1 — one clock\n'
    printf '========================================\n'
    exit 0
fi
printf 'FAIL  Phase 2 Step 1 — %d check(s) failed\n' "$failures"
printf '========================================\n'
exit 1
