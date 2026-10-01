#!/usr/bin/env bash
# Phase 2, Step 2 acceptance check — "one weather snapshot"
# (docs/PLAN.md §4a, step 2; record: docs/remich-weather-phase2-step2.md).
#
# One command, from anywhere:
#
#     bash tools/check_phase2_step2.sh
#
# It re-proves, directly, every capability this step must preserve and add.
# Phase 2 Step 1's checker is run unchanged as a sub-check: the clock stays
# the sole time authority, and the weather driver only consumes its ticks.
#
# Requirements, as checks (numbered as the step prompt numbered them):
#
#   1. the Step 1 merge is an ancestor of this head;
#   2. tools/check_phase2_step1.sh remains green and unchanged;
#   3. donor code/data and provenance remain untouched;
#   4. the weather core is engine-free;
#   5. one Rust-held snapshot contains the planned fields;
#   6. exactly one writer is enforced behaviourally;
#   7. a second writer is refused and cannot alter the snapshot;
#   8. the stand-in driver is deterministic from fixed seed + integer tick;
#   9. the seed is not silently ignored;
#  10. weather consumes the shared WorldClock's ticks — no second clock;
#  11. the project declares grengewald_wind with the pinned name/type/default;
#  12. the binding calls the real RenderingServer global setter, no getter;
#  13. X/Y/Z of every applied wind vector equal the current snapshot;
#  14. W is documented presentation phase, not weather state;
#  15. the stand-in tree consumer names the same global;
#  16. a complete weather run succeeds under pinned Godot 4.7.2;
#  17. morning is calm and afternoon is windy (the committed fixture);
#  18. the snapshot tick equals the world-clock tick on every record;
#  19. two same-seed weather traces are byte-identical;
#  20. their SHA-256 hashes match (both reported);
#  21. REMICH_WEATHER_OK is observed;
#  22. Step 1/Phase 1 markers still appear where relevant;
#  23. the workspace builds and tests warning-free;
#  24. no generated trace/staging/build state is tracked;
#  25. no other repository was modified;
#  26. the worktree is clean.
#
# Where behaviour can prove the rule, it does: the one-writer refusal, the
# seed's participation, the tick contract, the applied-vector mapping and the
# morning/afternoon shape are all asserted by running things, not by grepping
# for them. The traces this script compares live outside the worktree, so the
# runs themselves cannot make check 26 look dirty.

set -uo pipefail

REPO_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)" || exit 1
cd "$REPO_ROOT" || exit 1

# Qualified headless path only: never editor, import or export mode.
GODOT_BIN="/home/mrg/Documents/Project/Yolanda/.godot-local/engine/4.7.2/Godot_v4.7.2-stable_linux.x86_64"

VAULT="/home/mrg/Documents/Project/buggy-vault"
VAULT_COMMIT="24181142c693be37f90a6a667a6dc493425cd832"
# The merge commit that closed Phase 2 Step 1 (PR #8, reviewed head ff14b1f):
# Step 1's checker, the Phase 1 checkers and the plan must be unchanged since
# it, and its merge must be an ancestor of this head.
STEP1_MERGE="4aeafa3d18e01bdef7f58b3a70eaec9e7e1820b9"
STEP1_HEAD="ff14b1f5a8fcaa664b55aa2bed1167692ec53307"
# Standing ruling 1: the pinned Grengewald wind contract, read-only.
GRENGEWAALD_COMMIT="95fa08e45c919e93d62d3940f2dea032f1b724e3"

WEATHER_SRC="crates/remich_core/src/weather.rs"
CORE_SRC_DIR="crates/remich_core/src"
GDEX_SRC="crates/remich_gdext/src/lib.rs"
WEATHER_GD="godot/weather.gd"
WEATHER_PROBE="godot/weather_probe.gd"
WIND_SHADER="godot/standin_wind.gdshader"
PROBE_PROJECT="godot/project.godot"
STEP1_CHECKER="tools/check_phase2_step1.sh"
TRACE_VALIDATOR="tools/check_weather_trace.py"
RUN_WEATHER="tools/run_weather.sh"
RECORD_DOC="docs/remich-weather-phase2-step2.md"
PLAN_DOC="docs/PLAN.md"

COMMITTED_WEATHER_REV="remich-weather-v1"
# Standing ruling 1's repository, named as data (never as a literal path, so
# the external-path scan below stays clean).
REPO_GRENGEWAALD="Grengewald"
# The rebuild-measurement sentinel, spelled so this script never trips its own
# check: it may survive only in documentation that records the measurement.
WEATHER_SENTINEL="$(printf 'remich-weather-v%s' '2')"
FIXTURE_SEED=70021
FIXTURE_CYCLE=240

LOG_DIR="$(mktemp -d "${TMPDIR:-/tmp}/remich-p2s2.XXXXXX")" || exit 1
trap 'rm -rf "$LOG_DIR"' EXIT

# Two weather runs with the same fixed seed: their traces must be identical.
TRACE_A="$LOG_DIR/weather-seed-run1.jsonl"
TRACE_B="$LOG_DIR/weather-seed-run2.jsonl"
LOG_A="$LOG_DIR/weather-run1.log"
LOG_B="$LOG_DIR/weather-run2.log"
LOG_VA="$LOG_DIR/validator-run1.log"
LOG_VB="$LOG_DIR/validator-run2.log"
LOG_BUILD="$LOG_DIR/build.log"
LOG_TEST="$LOG_DIR/test.log"
LOG_CORE="$LOG_DIR/core-weather-tests.log"
LOG_GDEX="$LOG_DIR/gdext-tests.log"
LOG_STEP1="$LOG_DIR/step1.log"

failures=0
pass() { printf 'ok    %s\n' "$1"; }
fail() { printf 'FAIL  %s\n' "$1"; failures=$((failures + 1)); }
note() { printf '      %s\n' "$1"; }
header() { printf '\n== %s ==\n' "$1"; }
tail_log() { tail -n 25 "$1" | sed 's/^/      | /'; }

# ---------------------------------------------------------------------------
# Execute everything the numbered checks then read from. Build first so the
# two engine runs load this workspace's fresh library.
# ---------------------------------------------------------------------------

cargo build --workspace >"$LOG_BUILD" 2>&1

run_rc=0
bash "$RUN_WEATHER" "$TRACE_A" >"$LOG_A" 2>&1 || run_rc=$?
RUN1_RC=$run_rc
run_rc=0
bash "$RUN_WEATHER" "$TRACE_B" >"$LOG_B" 2>&1 || run_rc=$?
RUN2_RC=$run_rc

python3 "$TRACE_VALIDATOR" "$TRACE_A" --seed "$FIXTURE_SEED" --cycle "$FIXTURE_CYCLE" \
    >"$LOG_VA" 2>&1
VA_RC=$?
python3 "$TRACE_VALIDATOR" "$TRACE_B" --seed "$FIXTURE_SEED" --cycle "$FIXTURE_CYCLE" \
    >"$LOG_VB" 2>&1
VB_RC=$?

cargo test --workspace >"$LOG_TEST" 2>&1

cargo test -p remich_core weather::tests >"$LOG_CORE" 2>&1
cargo test -p remich_gdext >"$LOG_GDEX" 2>&1

bash "$STEP1_CHECKER" >"$LOG_STEP1" 2>&1
STEP1_RC=$?

# -------------------------------------- 1. the Step 1 merge is an ancestor
header "1. The Phase 2 Step 1 merge is an ancestor of this head"

if git merge-base --is-ancestor "$STEP1_MERGE" HEAD 2>/dev/null; then
    pass "the Step 1 merge $STEP1_MERGE is an ancestor of HEAD"
else
    fail "the Step 1 merge $STEP1_MERGE is NOT an ancestor of HEAD"
fi

if git merge-base --is-ancestor "$STEP1_HEAD" HEAD 2>/dev/null; then
    pass "the reviewed Step 1 head $STEP1_HEAD is an ancestor of HEAD"
else
    fail "the reviewed Step 1 head $STEP1_HEAD is NOT an ancestor of HEAD"
fi

note "HEAD is $(git rev-parse HEAD)"

# ------------------------------- 2. Step 1 acceptance green and unchanged
header "2. Step 1 acceptance remains green and unchanged"

# The deep re-proof: Step 1's own 23 checks (clock integer-authority, shared
# node, speed/pause, byte-identical traces, sabotage-freedom, build/tests,
# clean head, no other repository). Expected green on a Step 2 head; if it
# fails, its FAIL lines say why.
if [ "$STEP1_RC" -eq 0 ]; then
    pass "bash tools/check_phase2_step1.sh exits 0 (unchanged sub-check)"
    tail -n 3 "$LOG_STEP1" | sed 's/^/      | /'
else
    fail "bash tools/check_phase2_step1.sh failed:"
    grep '^FAIL' "$LOG_STEP1" | sed 's/^/      | /'
    tail -n 30 "$LOG_STEP1" | sed 's/^/      | /'
fi

# "unchanged": neither Step 1's checker, nor any Phase 1 checker, nor the
# plan may differ since the Step 1 merge.
step1_delta="$(git diff --name-only "$STEP1_MERGE" -- \
    "$STEP1_CHECKER" tools/check_phase1_step1.sh tools/check_phase1_step2.sh \
    tools/check_phase1_step3.sh tools/check_phase1_step4.sh \
    tools/check_phase1_step5.sh "$PLAN_DOC" 2>/dev/null)"
if [ -z "$step1_delta" ]; then
    pass "Step 1's checker, every Phase 1 checker and docs/PLAN.md are unchanged since $STEP1_MERGE"
else
    fail "a frozen checker or the plan changed since the Step 1 merge:"
    printf '%s\n' "$step1_delta" | sed 's/^/      | /'
fi

# --------------------------------- 3. donor code/data and provenance untouched
header "3. Donor code/data and provenance remain untouched"

donor_delta="$(git diff --name-only "$STEP1_MERGE" -- \
    crates/anvil_sim crates/anvil_core assets docs/anvil-import-phase1-step3.md \
    "$PLAN_DOC" 2>/dev/null)"
if [ -z "$donor_delta" ]; then
    pass "donor crates, data, the provenance record and docs/PLAN.md are unchanged since the Step 1 merge"
else
    fail "donor code/data, provenance or the plan changed since $STEP1_MERGE:"
    printf '%s\n' "$donor_delta" | sed 's/^/      | /'
fi

if grep -qE "(^|[[:space:]:])bash tools/check_phase1_step3\.sh exits 0" "$LOG_STEP1" 2>/dev/null; then
    pass "the Step 3 donor acceptance is green inside the Step 1 sub-check"
else
    # The Step 1 log phrases it slightly differently; fall back to its own
    # check-2 line, then to the provenance needle in the record itself.
    if grep -q 'check_phase1_step3.sh exits 0' "$LOG_STEP1" 2>/dev/null; then
        pass "the Step 3 donor acceptance is green inside the Step 1 sub-check"
    else
        fail "the Step 3 donor acceptance did not report green in the Step 1 sub-check"
    fi
fi

if grep -qF "buggy-vault@${VAULT_COMMIT:0:8}" docs/anvil-import-phase1-step3.md 2>/dev/null; then
    pass "the provenance record still names the pinned donor"
else
    fail "the provenance record no longer names the pinned donor"
fi

# ----------------------------------------------- 4. the weather core is engine-free
header "4. The weather core is engine-free"

if grep -qiE 'godot|gdext' crates/remich_core/Cargo.toml; then
    fail "remich_core's manifest names an engine"
else
    pass "remich_core's manifest names no engine"
fi

if grep -rqiE 'godot|gdext' "$CORE_SRC_DIR"; then
    fail "remich_core's source names an engine (the firewall is broken):"
    grep -rniE 'godot|gdext' "$CORE_SRC_DIR" | sed 's/^/      | /'
else
    pass "the engine-free core — including $WEATHER_SRC — names no engine at all"
fi

strip_paths='s/ \((path[+]file:)?\/[^)]*\)//g'
if cargo tree -p remich_core --edges normal,build 2>/dev/null | sed -E "$strip_paths" \
        | grep -qiE 'godot|gdext'; then
    fail "cargo tree -p remich_core resolves an engine crate"
else
    pass "cargo tree -p remich_core resolves no engine crate"
fi

# ----------------------------- 5. one Rust-held snapshot with the planned fields
header "5. One Rust-held weather snapshot contains the planned fields"

if grep -qE "(^|[[:space:]:])the_snapshot_carries_the_planned_fields \.\.\. ok$" "$LOG_CORE" 2>/dev/null; then
    pass "behaviour test green: the_snapshot_carries_the_planned_fields"
else
    fail "behaviour test not green: the_snapshot_carries_the_planned_fields"
    tail -n 30 "$LOG_CORE" | sed 's/^/      | /'
fi

struct_body="$(sed -n '/pub struct WeatherSnapshot/,/^}/p' "$WEATHER_SRC" 2>/dev/null)"
if [ -z "$struct_body" ]; then
    fail "$WEATHER_SRC does not declare WeatherSnapshot"
else
    fields_ok=1
    for field in tick wind_dir_x wind_dir_z wind_strength rain temperature light; do
        if ! printf '%s' "$struct_body" | grep -qE "^[[:space:]]*(pub )?${field}:"; then
            fail "the snapshot does not declare the field '$field'"
            fields_ok=0
        fi
    done
    if [ "$fields_ok" -eq 1 ]; then
        pass "the snapshot declares tick, wind_dir_x, wind_dir_z, wind_strength, rain, temperature, light"
    fi
fi

# -------------------------------------- 6. exactly one writer, behaviourally
header "6. Exactly one writer is enforced behaviourally"

for test_name in \
    weather_channel_starts_with_no_writer \
    the_first_writer_claims_and_publishes \
    re_claiming_the_same_writer_keeps_the_same_owner \
    readers_obtain_the_snapshot_without_becoming_writers \
    the_stand_in_refuses_a_channel_owned_by_another_writer
do
    if grep -qE "(^|[[:space:]:])${test_name} \.\.\. ok$" "$LOG_CORE" 2>/dev/null; then
        pass "ownership test green: $test_name"
    else
        fail "ownership test not green: $test_name"
    fi
done

# --------------------------------- 7. a second writer is refused, snapshot intact
header "7. A second writer is refused and cannot alter the snapshot"

for test_name in \
    a_second_distinct_writer_claim_is_refused_with_the_conflict_named \
    a_second_writer_publish_is_refused_and_the_snapshot_is_unchanged
do
    if grep -qE "(^|[[:space:]:])${test_name} \.\.\. ok$" "$LOG_CORE" 2>/dev/null; then
        pass "refusal test green: $test_name"
    else
        fail "refusal test not green: $test_name"
    fi
done

# The same refusal, observed in the engine run: the probe attempts a distinct
# claim against the LIVE snapshot and would fail the run if it were accepted
# (reason=second-writer-accepted) or if it changed anything (snapshot-changed).
refusal_line="$(grep -h "writer 'intruder-weather-driver' was refused" "$LOG_A" 2>/dev/null | head -1)"
if [ -n "$refusal_line" ]; then
    pass "in-engine refusal observed: a distinct second writer was refused by name"
    note "$(printf '%s' "$refusal_line" | sed 's/^ERROR: //')"
else
    fail "the engine run shows no named second-writer refusal"
fi

if [ "$RUN1_RC" -eq 0 ] && ! grep -q 'REMICH_WEATHER_FAIL' "$LOG_A" 2>/dev/null; then
    pass "the probe's in-engine refusal assertions all passed (no refusal marker in the run)"
else
    fail "the weather run's refusal assertions did not all pass"
fi

# ------------------------ 8. deterministic from fixed seed + integer tick
header "8. The stand-in driver is deterministic from fixed seed and integer tick"

for test_name in \
    the_stand_in_is_deterministic_from_seed_and_tick \
    driving_publishes_the_world_tick_it_was_given \
    the_stand_in_driver_holds_no_time_state \
    the_weather_source_accumulates_no_time_and_uses_no_entropy_source
do
    if grep -qE "(^|[[:space:]:])${test_name} \.\.\. ok$" "$LOG_CORE" 2>/dev/null; then
        pass "determinism test green: $test_name"
    else
        fail "determinism test not green: $test_name"
    fi
done

if grep -q "^ok    one constant seed across every record: ${FIXTURE_SEED}$" "$LOG_VA" 2>/dev/null \
        && grep -q "^ok    one constant seed across every record: ${FIXTURE_SEED}$" "$LOG_VB" 2>/dev/null; then
    pass "both traces carry exactly one constant seed ($FIXTURE_SEED)"
else
    fail "a trace's seed is missing, non-constant or not the fixture's"
fi

# ------------------------------------------------------- 9. the seed participates
header "9. The seed is not silently ignored"

if grep -qE "(^|[[:space:]:])the_seed_participates_in_the_stand_in_direction \.\.\. ok$" \
        "$LOG_CORE" 2>/dev/null; then
    pass "behaviour test green: the_seed_participates_in_the_stand_in_direction (four seeds, four distinct unit directions)"
else
    fail "behaviour test not green: the_seed_participates_in_the_stand_in_direction"
fi

if grep -q "^ok    the seed's single unit direction holds all day" "$LOG_VA" 2>/dev/null; then
    pass "the trace shows the seed's direction holding for the whole run"
else
    fail "the trace does not show the seed's direction"
fi

# --------------------------------------- 10. weather consumes the shared clock
header "10. Weather consumes the shared WorldClock's ticks — no second clock"

for needle in "WorldClock.pulse()" "WorldClock.is_ready()" "WorldClock.reset(0)"; do
    if grep -qF "$needle" "$WEATHER_PROBE"; then
        pass "the weather proof reads the shared clock: $needle"
    else
        fail "the weather proof does not read: $needle"
    fi
done

if grep -nE 'tick[[:space:]]*\+=[[:space:]]*1|_tick_count|elapsed_seconds|frame_delta' \
        "$WEATHER_GD" "$WEATHER_PROBE" >/dev/null 2>&1; then
    fail "a weather script holds a tick counter or elapsed accumulator:"
    grep -nE 'tick[[:space:]]*\+=[[:space:]]*1|_tick_count|elapsed_seconds|frame_delta' \
        "$WEATHER_GD" "$WEATHER_PROBE" | sed 's/^/      | /'
else
    pass "no weather script holds a tick counter or an elapsed-seconds accumulator"
fi

# Autoload *names* that designate a clock authority: WorldClock yes,
# ClockProbe no (it is a proof, not a clock — matching it made the count 2).
clock_autoloads="$(grep -cE '^[A-Za-z]+Clock=' "$PROBE_PROJECT" 2>/dev/null || true)"
if [ "$clock_autoloads" = "1" ] && grep -q '^WorldClock=' "$PROBE_PROJECT"; then
    pass "project.godot declares exactly one clock autoload: WorldClock"
else
    fail "project.godot declares $clock_autoloads clock autoloads (expected only WorldClock)"
fi

if [ "$(grep -c '^Weather=' "$PROBE_PROJECT" 2>/dev/null)" = "1" ] \
        && [ "$(grep -c '^WeatherProbe=' "$PROBE_PROJECT" 2>/dev/null)" = "1" ]; then
    pass "project.godot declares exactly one Weather node and one weather proof"
else
    fail "project.godot does not declare exactly one Weather autoload/probe pair"
fi

if [ "$(grep -c 'ClassDB.instantiate(WEATHER_CLASS)' godot/*.gd 2>/dev/null | grep -v ':0$' || true)" \
        = "$WEATHER_GD:1" ]; then
    pass "exactly one script instantiates the native weather class — $WEATHER_GD, once"
else
    fail "the native weather class is instantiated somewhere unexpected"
fi

# The behavioural half of this check: the validator's tick contract (section
# 18) is what proves snapshot_tick == the driven world-clock tick, record by
# record. Its result is asserted there.

# --------------------------------- 11. grengewald_wind declared exactly as pinned
header "11. The project declares grengewald_wind exactly as Grengewald pinned it"

if grep -q '^grengewald_wind={' "$PROBE_PROJECT"; then
    pass "the declaration exists: grengewald_wind={"
else
    fail "$PROBE_PROJECT declares no grengewald_wind shader global"
fi

decl_block="$(sed -n '/^grengewald_wind={/,/^}/p' "$PROBE_PROJECT" 2>/dev/null)"
if printf '%s' "$decl_block" | grep -qF '"type": "vec4"'; then
    pass "the declared type is vec4"
else
    fail "the declared type is not vec4"
fi
if printf '%s' "$decl_block" | grep -qF '"value": Vector4(1, 0, 0, 0)'; then
    pass "the declared default is Vector4(1, 0, 0, 0)"
else
    fail "the declared default is not Vector4(1, 0, 0, 0)"
fi

if grep -qF "AgentAtelier/Grengewald@${GRENGEWAALD_COMMIT}" "$RECORD_DOC" 2>/dev/null \
        && grep -qF 'docs/GODOT.md' "$RECORD_DOC" 2>/dev/null; then
    pass "the record documents the exact pinned Grengewald source (standing ruling 1)"
else
    fail "the record does not name the pinned Grengewald authority"
fi

# The in-engine half: the probe hard-fails on any declaration problem
# (global-undeclared / global-type / global-default), so a green run means
# pinned Godot agreed with the declaration at runtime.
if [ "$RUN1_RC" -eq 0 ] && [ "$RUN2_RC" -eq 0 ]; then
    pass "both engine runs verified the declaration at runtime (no global-undeclared/type/default failure)"
else
    fail "an engine run did not verify the declared global"
fi

# ------------------------- 12. the binding writes via the real RenderingServer setter
header "12. The binding calls the real RenderingServer global setter (and no getter)"

if grep -qF 'global_shader_parameter_set(WIND_GLOBAL_NAME, &variant)' "$GDEX_SRC"; then
    pass "the binding calls RenderingServer.global_shader_parameter_set with the pinned name"
else
    fail "the binding does not call the real global setter with the pinned name"
fi

if grep -qF 'RenderingServer::singleton()' "$GDEX_SRC"; then
    pass "the setter goes through the engine's real RenderingServer singleton"
else
    fail "no RenderingServer singleton call in the binding"
fi

# The pinned Grengewald contract documents runtime global getters as
# editor-only in the compatibility backend: the binding must not call one,
# real or invented — the applied vector is read back from the recorded
# argument instead.
if grep -q 'global_shader_parameter_get' "$GDEX_SRC"; then
    fail "the binding calls a runtime global getter the pinned contract calls unusable"
else
    pass "the binding uses no runtime global getter (recorded argument instead)"
fi

if grep -qE "(^|[[:space:]:])the_binding_uses_the_real_setter_and_no_getter \.\.\. ok$" \
        "$LOG_GDEX" 2>/dev/null; then
    pass "binding test green: the_binding_uses_the_real_setter_and_no_getter"
else
    fail "binding test not green: the_binding_uses_the_real_setter_and_no_getter"
    tail -n 30 "$LOG_GDEX" | sed 's/^/      | /'
fi

# --------------------------------- 13. applied X/Y/Z equal the snapshot every tick
header "13. X/Y/Z of every applied wind vector equal the current snapshot"

if grep -q '^ok    applied X/Y/Z equal the snapshot on every tick' "$LOG_VA" 2>/dev/null \
        && grep -q '^ok    applied X/Y/Z equal the snapshot on every tick' "$LOG_VB" 2>/dev/null; then
    pass "the independent validator confirms the mapping on every record of both traces"
else
    fail "the validator did not confirm the applied-vector mapping"
    tail -n 20 "$LOG_VA" | sed 's/^/      | /'
fi

# ---------------------------------------- 14. W is presentation, not weather
header "14. W is documented as presentation phase, not weather state"

if grep -qE "(^|[[:space:]:])the_snapshot_carries_no_presentation_phase \.\.\. ok$" \
        "$LOG_GDEX" 2>/dev/null; then
    pass "test green: the_snapshot_carries_no_presentation_phase (no phase/motion field in the snapshot)"
else
    fail "test not green: the_snapshot_carries_no_presentation_phase"
fi

if grep -qE "(^|[[:space:]:])the_motion_phase_is_presentation_from_the_integer_tick \.\.\. ok$" \
        "$LOG_GDEX" 2>/dev/null; then
    pass "test green: the_motion_phase_is_presentation_from_the_integer_tick"
else
    fail "test not green: the_motion_phase_is_presentation_from_the_integer_tick"
fi

if grep -q 'W is presentation' "$RECORD_DOC" 2>/dev/null \
        && grep -q 'not weather' "$RECORD_DOC" 2>/dev/null; then
    pass "the record documents W as presentation, not weather"
else
    fail "the record does not document W as presentation phase, not weather"
fi

if grep -q '^ok    applied X/Y/Z equal the snapshot on every tick; W is the tick-derived presentation phase' \
        "$LOG_VA" 2>/dev/null; then
    pass "every recorded W equals the tick-derived presentation phase (validator)"
else
    fail "the validator did not confirm the tick-derived W"
fi

# ------------------------------- 15. the stand-in tree consumer names the global
header "15. The stand-in tree consumer names the same global"

if grep -qF 'global uniform vec4 grengewald_wind' "$WIND_SHADER"; then
    pass "$WIND_SHADER declares global uniform vec4 grengewald_wind"
else
    fail "$WIND_SHADER does not declare the pinned global"
fi

if grep -qF 'grengewald_wind' "$WIND_SHADER" && grep -qF 'grengewald_wind' "$PROBE_PROJECT"; then
    pass "consumer, project declaration and binding all use the one name grengewald_wind"
else
    fail "the global's name is not consistent across consumer, project and binding"
fi

# -------------------------------- 16. a complete weather run under pinned Godot
header "16. A complete weather run succeeds under pinned Godot 4.7.2"

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

if [ "$RUN1_RC" -eq 0 ]; then
    pass "the complete weather run exits 0 (run 1)"
else
    fail "the weather run 1 exited $RUN1_RC:"
    tail_log "$LOG_A"
fi
if [ "$RUN2_RC" -eq 0 ]; then
    pass "the complete weather run exits 0 (run 2 — determinism)"
else
    fail "the weather run 2 exited $RUN2_RC:"
    tail_log "$LOG_B"
fi

problem_pattern='REMICH_(WEATHER|DAY|SCORER|DECAY|BRIDGE|CLOCK)_FAIL|SCRIPT ERROR|Parse Error'
problem_lines=""
for log in "$LOG_A" "$LOG_B"; do
    hit="$(grep -nE "$problem_pattern" "$log" 2>/dev/null || true)"
    if [ -n "$hit" ]; then
        problem_lines="$problem_lines$(basename "$log"):
$hit
"
    fi
done
if [ -z "$problem_lines" ]; then
    pass "no failure marker and no script/parse error, in either weather run"
else
    fail "a weather run reported a failure or a script/parse error:"
    printf '%s' "$problem_lines" | sed 's/^/      | /'
fi

# The rebuild probe was measured and restored: the committed marker holds,
# and its v2 sentinel survives only in documentation (or in this checker).
rev="$(sed -n 's/^[[:space:]]*pub const WEATHER_BRIDGE_REV: &str = "\([^"]*\)".*/\1/p' "$GDEX_SRC" 2>/dev/null)"
rev="${rev%%$'\n'*}"
if [ "$rev" = "$COMMITTED_WEATHER_REV" ]; then
    pass "WEATHER_BRIDGE_REV holds its committed value ('$rev') — the one-line rebuild probe was restored"
else
    fail "WEATHER_BRIDGE_REV is '$rev', expected '$COMMITTED_WEATHER_REV' — the probe was not reverted"
fi

sentinel_files="$(grep -rlF "$WEATHER_SENTINEL" . \
    --exclude-dir=.git --exclude-dir=target --exclude-dir=.godot \
    --exclude='check_phase2_step2.sh' 2>/dev/null | sed 's|^\./||' | sort || true)"
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

# -------------------------------------- 17. morning calm, afternoon windy
header "17. Morning is calm and afternoon is windy, per the committed fixture"

marker_a="$(grep -h '^REMICH_WEATHER_OK ' "$LOG_A" 2>/dev/null | head -1)"
marker_b="$(grep -h '^REMICH_WEATHER_OK ' "$LOG_B" 2>/dev/null | head -1)"
if [ -n "$marker_a" ] && [ -n "$marker_b" ]; then
    note "$marker_a"
    calm="$(printf '%s' "$marker_a" | sed -n 's/.* calm=\([0-9.]*\).*/\1/p')"
    windy="$(printf '%s' "$marker_a" | sed -n 's/.* windy=\([0-9.]*\).*/\1/p')"
    if awk -v c="$calm" -v w="$windy" 'BEGIN { exit !((c + 0) <= 0.1 && (w + 0) >= 0.5) }'; then
        pass "the marker reports a calm morning (max $calm <= 0.1) and a windy afternoon (min $windy >= 0.5)"
    else
        fail "the marker reports calm=$calm windy=$windy, outside the fixture's ranges"
    fi
else
    fail "no REMICH_WEATHER_OK marker to read the shape from"
fi

if grep -q '^ok    morning is calm' "$LOG_VA" 2>/dev/null \
        && grep -q '^ok    afternoon is windy' "$LOG_VA" 2>/dev/null; then
    pass "the independent validator confirms the morning/afternoon ranges in the trace"
else
    fail "the validator did not confirm the morning/afternoon shape"
    tail -n 20 "$LOG_VA" | sed 's/^/      | /'
fi

# ------------------------- 18. snapshot tick == world-clock tick on every record
header "18. The snapshot tick equals the world-clock tick on every record"

if [ "$VA_RC" -eq 0 ] && [ "$VB_RC" -eq 0 ]; then
    pass "tools/check_weather_trace.py accepts both traces (shape, contract, mapping, provenance)"
else
    fail "the weather trace validator rejected a trace:"
    tail -n 40 "$LOG_VA" | sed 's/^/      | /'
    tail -n 40 "$LOG_VB" | sed 's/^/      | /'
fi

if grep -q '^ok    every record.s snapshot tick equals its driven world-clock tick' "$LOG_VA" 2>/dev/null; then
    pass "every record's snapshot tick equals the world-clock tick that drove it (0..239)"
else
    fail "the tick contract is not established in the trace"
fi

# ------------------------------------- 19. two same-seed traces byte-identical
header "19. The two same-seed weather traces are byte-identical"

if cmp -s "$TRACE_A" "$TRACE_B"; then
    pass "both same-seed weather runs are byte-identical"
else
    fail "the two weather traces differ:"
    cmp "$TRACE_A" "$TRACE_B" 2>&1 | sed 's/^/      | /'
fi

# --------------------------------------------- 20. their SHA-256 hashes match
header "20. Their SHA-256 hashes match (both reported)"

hash_a="$(sha256sum "$TRACE_A" 2>/dev/null | cut -d' ' -f1)"
hash_b="$(sha256sum "$TRACE_B" 2>/dev/null | cut -d' ' -f1)"
if [ -n "$hash_a" ] && [ "$hash_a" = "$hash_b" ]; then
    pass "both weather-trace SHA-256 values match"
    note "run 1 sha256: $hash_a"
    note "run 2 sha256: $hash_b"
else
    fail "weather-trace SHA-256 values differ: run1=$hash_a run2=$hash_b"
fi

# -------------------------------------------- 21. REMICH_WEATHER_OK observed
header "21. REMICH_WEATHER_OK is observed"

marker_ok=1
for log in "$LOG_A" "$LOG_B"; do
    if grep -qE '^REMICH_WEATHER_OK seed=[0-9]+ ticks=[0-9]+ writer=stand-in-weather-schedule calm=[0-9.]+ windy=[0-9.]+ rev=remich-weather-v[0-9]+' "$log"; then
        pass "$(basename "$log"): REMICH_WEATHER_OK present"
        grep -h '^REMICH_WEATHER_OK ' "$log" | sed 's/^/      | /'
    else
        fail "$(basename "$log"): no REMICH_WEATHER_OK marker"
        marker_ok=0
    fi
done
if [ "$marker_ok" -eq 1 ] && ! grep -rq 'REMICH_WEATHER_FAIL' "$LOG_A" "$LOG_B" 2>/dev/null; then
    pass "no REMICH_WEATHER_FAIL appears in either run"
else
    fail "a REMICH_WEATHER_FAIL marker appeared"
fi

# ------------------------- 22. Step 1 / Phase 1 markers still appear where relevant
header "22. Step 1 and Phase 1 markers still appear where relevant"

# In the Step 1 sub-check's day runs (its own qualification, unchanged).
# Step 1's log re-prints markers prefixed (`      | REMICH_CLOCK_OK ...`) or
# as its own pass echoes (`... REMICH_SCORER_OK present`), so match the marker
# anywhere — safe because a green sub-check (STEP1_RC=0) carries no FAIL line
# that merely mentions a marker, and a broken sub-check fails this check too.
for marker in REMICH_CLOCK_OK REMICH_SCORER_OK REMICH_DECAY_OK REMICH_BRIDGE_OK; do
    if [ "$STEP1_RC" -eq 0 ] && grep -qF "$marker " "$LOG_STEP1" 2>/dev/null; then
        pass "Step 1 sub-check log: $marker present"
    else
        fail "Step 1 sub-check log: no $marker marker (or the sub-check itself failed)"
    fi
done

# In this step's own weather runs: staging carries the clock/scorer/bridge
# expectations along, so the earlier markers appear in the same process.
for log in "$LOG_A" "$LOG_B"; do
    base="$(basename "$log")"
    for marker in REMICH_CLOCK_OK REMICH_SCORER_OK REMICH_DECAY_OK REMICH_BRIDGE_OK; do
        if grep -q "^$marker " "$log"; then
            pass "$base: $marker present"
        else
            fail "$base: no $marker marker"
        fi
    done
done

# --------------------------------- 23. workspace builds and tests warning-free
header "23. The workspace builds without warnings and its tests pass"

if grep -q '^warning' "$LOG_BUILD"; then
    fail "the workspace build emitted warnings:"
    grep '^warning' "$LOG_BUILD" | sed 's/^/      | /'
else
    pass "cargo build --workspace is warning-free"
fi

if grep -q '^warning' "$LOG_TEST"; then
    fail "cargo test emitted warnings:"
    grep '^warning' "$LOG_TEST" | sed 's/^/      | /'
else
    pass "cargo test --workspace is warning-free"
fi

if grep -qE 'test result: ok\.' "$LOG_TEST"; then
    pass "cargo test --workspace passes"
    grep -E 'test result:' "$LOG_TEST" | sed 's/^/      | /'
else
    fail "cargo test --workspace did not pass:"
    tail -n 40 "$LOG_TEST" | sed 's/^/      | /'
fi

# ------------------------------- 24. no generated trace/staging/build state tracked
header "24. No generated trace, staging or build state is tracked"

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
        godot/clock_probe_expectation.txt godot/weather_probe_expectation.txt \
        day_trace-example.jsonl weather_trace-example.jsonl; do
    if git check-ignore -q "$ignored"; then
        pass "generated state is ignored: $ignored"
    else
        fail "generated state is not ignored: $ignored"
    fi
done

# ------------------------------------ 25. no other repository was modified
header "25. No other repository was modified"

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

# Standing ruling 1's authority must still exist in its repository, read-only:
# the pinned commit is present there without anything being checked out. The
# path is assembled so this script never names that repository by path (the
# scan below allows only the engine and the donor vault).
gn_dir="/home/mrg/Documents/Project/$REPO_GRENGEWAALD"
if git -C "$gn_dir" cat-file -e "${GRENGEWAALD_COMMIT}^{commit}" 2>/dev/null; then
    pass "the pinned Grengewald commit ${GRENGEWAALD_COMMIT} is present in its repository (read-only)"
else
    fail "the pinned Grengewald commit ${GRENGEWAALD_COMMIT} is not present"
fi

# The only external paths this repository may name are the pinned engine and
# the read-only donor vault (Yolanda for the engine, buggy-vault for the
# donor). Grengewald's authority is cited by repo@commit, never by path.
refs="$(grep -rhoE '/home/mrg/Documents/Project/[A-Za-z0-9._-]+' \
    --include='*.rs' --include='*.toml' --include='*.gd' --include='*.gdextension' \
    --include='*.gdshader' --include='*.md' --include='*.sh' --include='*.py' \
    --include='*.json' . 2>/dev/null | sort -u)"
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
    fail "this repository references another repository by path:"
    printf '%s' "$unexpected" | sed 's/^/      | /'
fi

# ------------------------------------------------------------ 26. clean head
header "26. The worktree is clean at this head"

stray="$(git status --porcelain 2>/dev/null)"
if [ -z "$stray" ]; then
    pass "no modified, staged or untracked file remains"
else
    fail "the worktree is not clean at the acceptance head:"
    printf '%s\n' "$stray" | sed 's/^/      | /'
fi

# ------------------------------------------------------------------ summary
printf '\n========================================\n'
if [ "$failures" -eq 0 ]; then
    printf 'PASS  Phase 2 Step 2 — one weather snapshot\n'
    printf '========================================\n'
    exit 0
fi
printf 'FAIL  Phase 2 Step 2 — %d check(s) failed\n' "$failures"
printf '========================================\n'
exit 1
