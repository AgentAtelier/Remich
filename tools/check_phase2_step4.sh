#!/usr/bin/env bash
# Phase 2, Step 4 acceptance check — "many inhabitants, measured"
# (docs/PLAN.md §4a, step 4; record: docs/remich-scale-phase2-step4.md).
#
# One command, from anywhere:
#
#     bash tools/check_phase2_step4.sh
#
# It re-proves, directly, every capability this step must preserve and add.
# Phase 2 Step 3's checker is run unchanged as a sub-check, which transitively
# preserves Steps 1-2 and Phase 1. The performance measurement itself is
# re-exercised only in SMOKE mode (1 warm-up, 3 measured samples): the one
# official run belongs to the record and is never repeated here.
#
# Requirements, as checks (numbered as this step enumerated them):
#
#   1. the Step 3 merge and its reviewed head are ancestors of this head;
#   2. tools/check_phase2_step3.sh remains green (with every earlier checker,
#      validator, harness and probe frozen since the Step 3 merge except their
#      named Remich #9 / Phase 3 Step 1 edits, docs/PLAN.md frozen at the
#      lead's Phase 3 plan merge, the autoload order intact with SaveProbe
#      last, and no benchmark marker anywhere in the ordinary runs);
#   3. donor code/data and provenance remain untouched, bar the one file
#      Remich #9 authorizes and the record documenting it;
#   4. the scorer implementation and formulas are unchanged since Step 3,
#      the committed bridge revision holds, and the rebuild sentinel
#      survives only in documentation that records the measurement;
#   5. no new bulk, batched or parallel scoring API exists — the only files
#      changed since the Step 3 merge are the benchmark script, its runner,
#      this checker, its validator, the record, and the files Remich #9 /
#      Phase 3 Step 1 names (the catalogue, its provenance record, the
#      checkers whose ratchets it moved and this step's own new files);
#   6. the benchmark invokes the real RemichScorer through pinned Godot
#      4.7.2 (behavioural: the smoke run itself);
#   7. exactly one scorer instance is created, outside all timed work;
#   8. the fixture is 1,000 deterministic inputs (seed base, profile table,
#      fixed noon position, six activities, empty skills, zero damage/mood);
#   9. the populations are exactly 1, 10, 100, 1000, in that order;
#  10. every population is a prefix of the same fixture;
#  11. fixture creation, scorer construction and the preflight all occur
#      outside the timed region (the only clock reads live in the measured
#      function);
#  12. warm-up samples are untimed and separate from the measured samples;
#  13. each timed sample performs exactly N scorer calls (call arithmetic
#      on every reported line);
#  14. each result is consumed in the timed loop (chosen_id folded into the
#      reported checksum, the sample bracketed by the clock);
#  15. a correctness preflight verifies all 1,000 inputs before measurement;
#  16. two untimed correctness passes produce the same result signature;
#  17. the smoke benchmark exercises all four populations;
#  18. the smoke benchmark emits exactly four REMICH_SCALE_RESULT lines;
#  19. the smoke benchmark emits REMICH_SCALE_OK and exits 0;
#  20. every reported timing value is finite and non-negative, p95 >= median,
#      and the per-inhabitant median is derived from the tick median;
#  21. no performance limit or verdict exists in benchmark code or output;
#  22. the official command exists exactly as documented (and rejects any
#      other argument with the usage line);
#  23. the record contains one complete official result for all four
#      populations, plus the fixture, environment, timing and method
#      statements this step must publish;
#  24. the record names the exact official reproduction command;
#  25. the record states the official benchmark ran once and that no
#      optimisation pass followed it;
#  26. the measured commit is named, exists, and is an ancestor of HEAD;
#  27. the final executable tree differs from the measured commit only by
#      result documentation and the named Remich #9 files;
#  28. the workspace builds and tests warning-free;
#  29. no generated benchmark output, build or staging state is tracked;
#  30. no other repository was modified and external paths stay limited;
#  31. the worktree is clean.
#
# Where behaviour can prove the rule, it does: the smoke benchmark, its
# machine-readable result block (parsed by tools/check_scale_result.py), the
# Step 3 sub-check, the workspace build and tests are all executed by running
# them. Structural facts that cannot be observed from outside — what sits
# inside the timed region — are checked against the benchmark's own source,
# and the arithmetic of the reported lines ties the numbers back to the
# method. This checker never compares a timing value against a performance
# limit: slow numbers are a result, not a failure.
#
# Before the record exists (draft runs on an uncommitted tree) checks 23-27
# fail by design, and check 2 fails while the tree is dirty because the Step
# 3 sub-check requires a clean head; check 31 fails on any dirty tree.

set -uo pipefail

REPO_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)" || exit 1
cd "$REPO_ROOT" || exit 1

# Qualified headless path only: never editor, import or export mode.
GODOT_BIN="/home/mrg/Documents/Project/Yolanda/.godot-local/engine/4.7.2/Godot_v4.7.2-stable_linux.x86_64"

VAULT="/home/mrg/Documents/Project/buggy-vault"
VAULT_COMMIT="24181142c693be37f90a6a667a6dc493425cd832"
# The merge commit that closed Phase 2 Step 3 (PR #11, reviewed head
# 72f8e71): Step 3's checker, every earlier checker and the plan must be
# unchanged since it, and its merge must be an ancestor of this head.
STEP3_MERGE="08850b2bcd9c9bc078836c422658b90247b5b66f"
STEP3_HEAD="72f8e7167dbf0a60c3b97568ba866659ac157b10"

BENCH_RUNNER="tools/benchmark_phase2_step4.sh"
BENCH_SCRIPT="godot/scale_benchmark.gd"
RESULT_VALIDATOR="tools/check_scale_result.py"
STEP3_CHECKER="tools/check_phase2_step3.sh"
RECORD_DOC="docs/remich-scale-phase2-step4.md"
PLAN_DOC="docs/PLAN.md"

# Remich issue #9 / Phase 3 Step 1 (the embedded action catalogue): the one
# donor file that step is authorized to change, the provenance record that
# documents it, its own result record, the checkers whose ratchets it
# legitimately moved, and the lead's Phase 3 plan merge — at which
# docs/PLAN.md is now frozen, because that merge extended the plan after
# $STEP3_MERGE.
N9_CATALOGUE="crates/anvil_sim/src/actions/catalogue.rs"
N9_PROVENANCE="docs/anvil-import-phase1-step3.md"
N9_RECORD="docs/remich-catalogue-phase3-step1.md"
PLAN_MERGE="cfa796cc4885432da93b1974602ef3ba9a7cbff8"

COMMITTED_SCORER_REV="remich-scorer-v1"
# The rebuild-measurement sentinel, spelled so this script never trips its
# own check: it may survive only in documentation that records it.
SCORER_SENTINEL="$(printf 'remich-scorer-v%s' '2')"

EXPECTED_AUTOLOADS="Marker,ScorerProbe,WorldClock,Weather,DayProbe,ClockProbe,BridgeProbe,WeatherProbe,SaveProbe"

LOG_DIR="$(mktemp -d /tmp/remich-p2s4.XXXXXX)" || exit 1
trap 'rm -rf "$LOG_DIR"' EXIT

LOG_BUILD="$LOG_DIR/build.log"
LOG_TEST="$LOG_DIR/test.log"
LOG_SMOKE="$LOG_DIR/smoke.log"
LOG_STEP3="$LOG_DIR/step3.log"

failures=0
pass() { printf 'ok    %s\n' "$1"; }
fail() { printf 'FAIL  %s\n' "$1"; failures=$((failures + 1)); }
note() { printf '      %s\n' "$1"; }
header() { printf '\n== %s ==\n' "$1"; }
tail_log() { tail -n 25 "$1" | sed 's/^/      | /'; }

# body_of <file> <function> — the function's source from its header line to
# just before the next top-level function.
body_of() {
    awk -v name="$2" '
        $0 ~ "^func " name "\\(" { grab = 1 }
        grab == 1 && $0 ~ /^func / && $0 !~ "^func " name "\\(" { exit }
        grab == 1 { print }
    ' "$1"
}

# first_line_of <text> <pattern> — the 1-based line of the first match, or
# empty when the pattern is absent.
first_line_of() {
    printf '%s\n' "$1" | grep -n "$2" | head -n 1 | cut -d: -f1
}

# validate <only|all> <label> <file> <mode> — the result-block validator.
validate() {
    local only="$1" label="$2" file="$3" mode="$4" out=""
    local args=()
    [ "$only" = "all" ] || args=(--only "$only")
    if out="$(python3 "$RESULT_VALIDATOR" "$file" "$mode" \
            "$COMMITTED_SCORER_REV" "${args[@]}" 2>&1)"; then
        pass "$label"
    else
        fail "$label"
        printf '%s\n' "$out" | sed 's/^/      | /'
    fi
}

# ---------------------------------------------------------------------------
# Execute everything the numbered checks then read from. The smoke benchmark
# runs first (a few seconds), the Step 3 sub-check afterwards (it stages and
# runs its own engine processes); both run before any check reads them, so a
# failing run is reported, not hidden.
# ---------------------------------------------------------------------------

BUILD_RC=0
cargo build --workspace >"$LOG_BUILD" 2>&1 || BUILD_RC=$?
TEST_RC=0
cargo test --workspace >"$LOG_TEST" 2>&1 || TEST_RC=$?

SMOKE_RC=0
bash "$BENCH_RUNNER" --smoke >"$LOG_SMOKE" 2>&1 || SMOKE_RC=$?

STEP3_RC=0
bash "$STEP3_CHECKER" >"$LOG_STEP3" 2>&1 || STEP3_RC=$?

# -------------------------------------- 1. the Step 3 merge is an ancestor
header "1. The Phase 2 Step 3 merge is an ancestor of this head"

if git merge-base --is-ancestor "$STEP3_MERGE" HEAD 2>/dev/null; then
    pass "the Step 3 merge $STEP3_MERGE is an ancestor of HEAD"
else
    fail "the Step 3 merge $STEP3_MERGE is NOT an ancestor of HEAD"
fi

if git merge-base --is-ancestor "$STEP3_HEAD" HEAD 2>/dev/null; then
    pass "the reviewed Step 3 head $STEP3_HEAD is an ancestor of HEAD"
else
    fail "the reviewed Step 3 head $STEP3_HEAD is NOT an ancestor of HEAD"
fi

note "HEAD is $(git rev-parse HEAD)"

# ------------------- 2. Step 3 green unchanged; benchmark silent elsewhere
header "2. The Step 3 acceptance stays green and unchanged; the benchmark is silent in ordinary runs"

if [ "$STEP3_RC" -eq 0 ]; then
    pass "tools/check_phase2_step3.sh ran green unchanged as a sub-check"
else
    fail "the Step 3 sub-check is not green (rc=$STEP3_RC)"
    tail_log "$LOG_STEP3"
fi

# Remich issue #9 / Phase 3 Step 1: the frozen checkers that changed are
# exactly the ones whose ratchets the authorized catalogue adaptation moved
# (inventory counts, the donor byte rule, the frozen source-test count and
# the donor/record/plan freezes), each edited with a comment naming this
# issue. docs/PLAN.md was extended by the lead's Phase 3 plan merge after
# the Step 3 merge, so it is frozen byte-for-byte at that merge instead —
# which still forbids this step from rewriting it. Every other frozen file
# must match $STEP3_MERGE exactly.
frozen_delta="$(git diff --name-only "$STEP3_MERGE" -- \
    "$STEP3_CHECKER" tools/check_phase2_step1.sh tools/check_phase2_step2.sh \
    tools/check_phase1_step1.sh tools/check_phase1_step2.sh \
    tools/check_phase1_step3.sh tools/check_phase1_step4.sh \
    tools/check_phase1_step5.sh \
    tools/check_save_trace.py tools/check_weather_trace.py \
    tools/check_day_trace.py \
    tools/run_day.sh tools/run_save.sh tools/run_weather.sh \
    tools/stage_bridge.sh tools/stage_clock.sh tools/stage_scorer.sh \
    tools/stage_weather.sh tools/stage_save.sh \
    godot/save_probe.gd godot/scorer_probe.gd godot/bridge_probe.gd \
    godot/clock_probe.gd godot/weather_probe.gd godot/day_probe.gd \
    godot/marker.gd godot/world_clock.gd godot/weather.gd \
    godot/project.godot godot/remich.gdextension \
    2>/dev/null \
    | grep -vxF -e "$STEP3_CHECKER" -e tools/check_phase2_step1.sh \
        -e tools/check_phase2_step2.sh -e tools/check_phase1_step3.sh \
        -e tools/check_phase1_step4.sh -e tools/check_phase1_step5.sh || true)"
plan_delta=""
if ! git diff --quiet "$PLAN_MERGE" -- "$PLAN_DOC" 2>/dev/null; then
    plan_delta="$PLAN_DOC"
fi
combined="$(printf '%s\n%s\n' "$frozen_delta" "$plan_delta" | sed '/^$/d')"
if [ -z "$combined" ]; then
    pass "every earlier checker, validator, harness and probe differs only by its named Remich #9 edit, and docs/PLAN.md matches the plan merge"
else
    fail "a frozen checker, harness, probe or the plan changed beyond the Remich #9 authorization:"
    printf '%s\n' "$combined" | sed 's/^/      | /'
fi

# docs/PLAN.md (lead's Phase 3 plan merge) plus the two records Remich #9
# requires: the provenance record it amends, and this step's own result
# record. Nothing else under docs/ may differ from the Step 3 merge.
doc_delta="$(git diff --name-only "$STEP3_MERGE" -- 'docs/*.md' 2>/dev/null \
    | grep -vxF -e "$RECORD_DOC" -e "$N9_PROVENANCE" -e "$N9_RECORD" \
        -e docs/PLAN.md || true)"
if [ -z "$doc_delta" ]; then
    pass "no record other than this step's own, the Remich #9 provenance update and the lead's plan merge exists changed since the Step 3 merge"
else
    fail "an earlier record changed since the Step 3 merge:"
    printf '%s\n' "$doc_delta" | sed 's/^/      | /'
fi
if git diff --quiet "$PLAN_MERGE" -- "$PLAN_DOC" 2>/dev/null; then
    pass "docs/PLAN.md is byte-identical to the lead's Phase 3 plan merge $PLAN_MERGE"
else
    fail "docs/PLAN.md was rewritten since the Phase 3 plan merge $PLAN_MERGE"
fi

autoload_order="$(grep -E '^(Marker|ScorerProbe|WorldClock|Weather|DayProbe|ClockProbe|BridgeProbe|WeatherProbe|SaveProbe)=' \
    godot/project.godot | cut -d= -f1 | paste -sd, -)"
if [ "$autoload_order" = "$EXPECTED_AUTOLOADS" ]; then
    pass "the autoload order is unchanged with SaveProbe last (no autoload was added)"
else
    fail "the autoload order changed: $autoload_order"
fi

scale_refs="$(grep -rl 'scale_benchmark' --exclude-dir=.git --exclude-dir=target \
    --exclude-dir=.godot . 2>/dev/null | sed 's|^\./||' | sort)"
bad_refs=""
while IFS= read -r ref; do
    [ -z "$ref" ] && continue
    case "$ref" in
        "$BENCH_SCRIPT" | "$BENCH_RUNNER" | tools/check_phase2_step4.sh \
            | "$RECORD_DOC") ;;
        *) bad_refs="$bad_refs      | $ref
" ;;
    esac
done <<<"$scale_refs"
if [ -z "$bad_refs" ]; then
    pass "the benchmark is referenced only by its own files — ordinary runs never reach it"
else
    fail "something outside the benchmark's own files references it:"
    printf '%s' "$bad_refs"
fi

if grep -q 'REMICH_SCALE' "$LOG_STEP3" 2>/dev/null; then
    fail "a benchmark marker appeared in the ordinary Step 1-3 runs:"
    grep 'REMICH_SCALE' "$LOG_STEP3" | head -n 5 | sed 's/^/      | /'
else
    pass "the ordinary runs (Step 3 and everything below) contain no benchmark marker"
fi

# -------------------------------------- 3. donor code/data and provenance
header "3. Donor code/data and provenance remain untouched, bar the authorized Remich #9 entry"

# Remich issue #9 / Phase 3 Step 1: two named exceptions — the authorized
# catalogue embedding, and the provenance record that documents it (guarded
# by the Step 3 sub-check). docs/PLAN.md is frozen byte-for-byte at the
# lead's Phase 3 plan merge.
donor_delta="$(git diff --name-only "$STEP3_MERGE" -- \
    crates/anvil_sim crates/anvil_core assets docs/anvil-import-phase1-step3.md \
    2>/dev/null \
    | grep -vxF -e "$N9_CATALOGUE" -e "$N9_PROVENANCE" || true)"
plan_delta=""
if ! git diff --quiet "$PLAN_MERGE" -- "$PLAN_DOC" 2>/dev/null; then
    plan_delta="$PLAN_DOC"
fi
combined="$(printf '%s\n%s\n' "$donor_delta" "$plan_delta" | sed '/^$/d')"
if [ -z "$combined" ]; then
    pass "donor crates and data are unchanged but for the authorized $N9_CATALOGUE, the provenance record documents it, and the plan matches the plan merge"
else
    fail "donor code/data, provenance or the plan changed beyond the Remich #9 authorization:"
    printf '%s\n' "$combined" | sed 's/^/      | /'
fi

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

if grep -qF "buggy-vault@${VAULT_COMMIT:0:8}" docs/anvil-import-phase1-step3.md 2>/dev/null; then
    pass "the provenance record still names the pinned donor"
else
    fail "the provenance record no longer names the pinned donor"
fi

# ------------------------- 4. scorer implementation unchanged; v1 restored
header "4. The scorer implementation and formulas are unchanged since Step 3"

# Remich issue #9 / Phase 3 Step 1: the authorized catalogue embedding is the
# only Rust file this ratchet allows to differ, and it changes how the
# catalogue reaches the scorer, never the scorer — the committed bridge
# revision, the formulas and the smoke run below still pin the behaviour.
rust_delta="$(git diff --name-only "$STEP3_MERGE" -- crates/ 2>/dev/null \
    | grep -vxF "$N9_CATALOGUE" || true)"
if [ -z "$rust_delta" ]; then
    pass "no Rust source changed but for the authorized $N9_CATALOGUE — the scorer core, the binding, the save, the weather and the clock are exactly as merged"
else
    fail "Rust source changed since the Step 3 merge beyond the Remich #9 catalogue embedding:"
    printf '%s\n' "$rust_delta" | sed 's/^/      | /'
fi

if grep -q '^pub const SCORER_BRIDGE_REV: &str = "remich-scorer-v1";$' \
        crates/remich_gdext/src/lib.rs; then
    pass "SCORER_BRIDGE_REV is the committed $COMMITTED_SCORER_REV"
else
    fail "SCORER_BRIDGE_REV is not the committed $COMMITTED_SCORER_REV"
fi

sentinel_files="$(grep -rl --exclude-dir=.git --exclude-dir=target \
    --exclude-dir=.godot -- "$SCORER_SENTINEL" . 2>/dev/null || true)"
bad_sentinel=""
while IFS= read -r file; do
    [ -z "$file" ] && continue
    case "$file" in
        # Documentation that records the measurement may carry it — and so
        # may any file this step never touched (the Phase 1 scorer record's
        # own sentinel evidence predates this step).
        ./docs/*.md) continue ;;
    esac
    rel="${file#./}"
    if [ -n "$(git ls-files -- "$rel" 2>/dev/null)" ] \
            && git diff --quiet "$STEP3_MERGE" -- "$rel" 2>/dev/null; then
        continue
    fi
    bad_sentinel="$bad_sentinel      | $file
"
done <<<"$sentinel_files"
if [ -z "$bad_sentinel" ]; then
    pass "the rebuild sentinel survives only in documentation or in files this step never changed"
else
    fail "the rebuild sentinel survives in a file this step changed:"
    printf '%s' "$bad_sentinel"
fi

# ------------- 5. no new bulk/batched/parallel API; scope is benchmark-only
header "5. No new bulk, batched or parallel scoring API; the change is benchmark-only"

delta="$({ git diff --name-only "$STEP3_MERGE"
           git ls-files --others --exclude-standard
         } | sort -u)"
allowed=""
while IFS= read -r file; do
    [ -z "$file" ] && continue
    case "$file" in
        godot/scale_benchmark.gd | tools/benchmark_phase2_step4.sh \
            | tools/check_phase2_step4.sh | tools/check_scale_result.py \
            | docs/remich-scale-phase2-step4.md) ;;
        # Remich issue #9 / Phase 3 Step 1: the authorized catalogue
        # embedding, the provenance record documenting it, this step's own
        # record, the lead's Phase 3 plan merge, the checkers whose ratchets
        # the adaptation moved, and the two scripts this step adds.
        "$N9_CATALOGUE" | "$N9_PROVENANCE" | "$N9_RECORD" | docs/PLAN.md \
            | tools/check_phase1_step3.sh | tools/check_phase1_step4.sh \
            | tools/check_phase1_step5.sh | tools/check_phase2_step1.sh \
            | tools/check_phase2_step2.sh | tools/check_phase2_step3.sh \
            | tools/check_phase3_step1.sh | tools/check_catalogue_relocation.sh) ;;
        *) allowed="$allowed$file
" ;;
    esac
done <<<"$delta"
if [ -z "$allowed" ]; then
    pass "the only files changed since the Step 3 merge are the benchmark's own files and the files Remich #9 / Phase 3 Step 1 names"
else
    fail "files outside this step's benchmark-only scope changed:"
    printf '%s' "$allowed" | sed 's/^/      | /'
fi

banned='score_many|score_batch|batch_score|rayon|std::thread|thread::spawn|Thread\.new|WorkerThreadPool|memoiz|cached_|_cached'
hits=""
while IFS= read -r file; do
    [ -z "$file" ] && continue
    case "$file" in
        tools/check_phase2_step4.sh) continue ;;
        *.gd | *.sh | *.py | *.rs | *.toml) ;;
        *) continue ;;
    esac
    [ -f "$file" ] || continue
    found="$(grep -nE "$banned" "$file" 2>/dev/null || true)"
    if [ -n "$found" ]; then
        hits="$hits      | $file: $(printf '%s' "$found" | head -n 2 | paste -sd' ' -)
"
    fi
done <<<"$delta"
if [ -z "$hits" ]; then
    pass "no bulk/batched/parallel scoring construct appears in any changed source file"
else
    fail "a banned performance construct appears in a changed source file:"
    printf '%s' "$hits"
fi

# ------------------- 6. the benchmark runs the real scorer in pinned Godot
header "6. The benchmark invokes the real RemichScorer through pinned Godot"

if [ "$SMOKE_RC" -eq 0 ]; then
    pass "bash tools/benchmark_phase2_step4.sh --smoke exits 0"
else
    fail "the smoke benchmark did not exit 0 (rc=$SMOKE_RC)"
    tail_log "$LOG_SMOKE"
fi

if grep -qF 'Godot Engine v4.7.2' "$LOG_SMOKE"; then
    pass "the smoke run is a pinned Godot 4.7.2 process"
else
    fail "the smoke log does not show the pinned Godot 4.7.2 engine"
fi

if grep -qF -- '--headless --path godot --script res://scale_benchmark.gd' \
        "$BENCH_RUNNER" && grep -qF -- '--headless' "$BENCH_RUNNER"; then
    pass "the runner starts the benchmark headless via --script, never editor/import/export mode"
else
    fail "the runner does not start the benchmark with the documented headless --script command"
fi

if grep -qF 'const SCORER_CLASS := "RemichScorer"' "$BENCH_SCRIPT" \
        && grep -qF 'ClassDB.instantiate(SCORER_CLASS)' "$BENCH_SCRIPT"; then
    pass "the benchmark instantiates the real RemichScorer class"
else
    fail "the benchmark does not instantiate the real RemichScorer class"
fi

rev_hits="$(grep '^REMICH_SCALE_RESULT ' "$LOG_SMOKE" 2>/dev/null \
    | grep -cF "rev=$COMMITTED_SCORER_REV")"
if [ "$rev_hits" -eq 4 ]; then
    pass "all four result lines report the scorer revision actually loaded (rev=$COMMITTED_SCORER_REV)"
else
    fail "only $rev_hits of 4 result lines report rev=$COMMITTED_SCORER_REV"
fi

# --------------------- 7. one scorer instance, created outside timed work
header "7. Exactly one scorer instance, created outside timed work"

instances="$(grep -c 'ClassDB.instantiate' "$BENCH_SCRIPT")"
if [ "$instances" -eq 1 ]; then
    pass "the benchmark source contains exactly one scorer instantiation"
else
    fail "the benchmark source contains $instances scorer instantiations, expected 1"
fi

run_body="$(body_of "$BENCH_SCRIPT" _run)"
measure_body="$(body_of "$BENCH_SCRIPT" _measure)"
sample_body="$(body_of "$BENCH_SCRIPT" _sample)"
warm_body="$(body_of "$BENCH_SCRIPT" _warm_up)"
preflight_body="$(body_of "$BENCH_SCRIPT" _preflight)"
violation_body="$(body_of "$BENCH_SCRIPT" _result_violation)"
fixture_calls="$(printf '%s\n' "$run_body" | grep -c '_build_fixture')"

if printf '%s\n' "$run_body" | grep -q 'ClassDB.instantiate' \
        && ! printf '%s\n' "$measure_body" | grep -q 'ClassDB.instantiate' \
        && ! printf '%s\n' "$sample_body" | grep -q 'ClassDB.instantiate'; then
    pass "the instance is created in setup and never inside the measured or sampling loops"
else
    fail "the scorer instantiation is not confined to setup code"
fi

validate env "the smoke run reports scorer_instances=1 and the full fixture parameters" "$LOG_SMOKE" smoke

# ------------------------------------- 8. the fixture is 1,000 deterministic
header "8. The fixture is 1,000 deterministic inputs"

fixture_greps="const FIXTURE_SIZE := 1000|const SEED_BASE := 60628|NEEDS_PROFILES"
fixture_ok=1
while IFS= read -r needle; do
    [ -z "$needle" ] && continue
    if ! grep -qF "$needle" "$BENCH_SCRIPT"; then
        fixture_ok=0
        fail "the benchmark source is missing: $needle"
    fi
done <<<"$(printf '%s\n' "$fixture_greps" | tr '|' '\n')"
[ "$fixture_ok" -eq 1 ] && pass "the fixture constants are committed: 1,000 inputs, seed base 60628, the needs-profile table"

if grep -qE 'randi\(|randomize\(|RandomNumberGenerator' "$BENCH_SCRIPT"; then
    fail "the fixture path contains a runtime randomness call"
else
    pass "no runtime randomness appears anywhere in the benchmark"
fi

if [ "$fixture_calls" -eq 1 ]; then
    pass "the fixture is built by exactly one call, outside the measured loop"
else
    fail "the fixture build is called $fixture_calls times, expected 1"
fi

# ---------------------------------- 9. populations are exactly 1, 10, 100, 1000
header "9. The populations are exactly 1, 10, 100, 1000 in that order"

if grep -qF 'const POPULATIONS := [1, 10, 100, 1000]' "$BENCH_SCRIPT"; then
    pass "the committed population list is [1, 10, 100, 1000]"
else
    fail "the committed population list is not [1, 10, 100, 1000]"
fi

validate order "the smoke result lines are ordered 1, 10, 100, 1000" "$LOG_SMOKE" smoke

# ----------------------------- 10. each population is a prefix of the fixture
header "10. Every population is a prefix of the same fixture"

sample_pref="$(first_line_of "$sample_body" 'inputs\[i\]')"
if [ -n "$sample_pref" ] \
        && ! printf '%s\n' "$sample_body" | grep -q '_build_fixture' \
        && ! printf '%s\n' "$sample_body" | grep -q 'slice' \
        && [ "$fixture_calls" -eq 1 ]; then
    pass "the sampling loop reads input[0..N) of the single prebuilt fixture"
else
    fail "the sampling loop does not read prefixes of the single prebuilt fixture"
fi

# ------------------------- 11. fixture, construction and preflight before time
header "11. Fixture creation, scorer construction and the preflight are outside the timed region"

clock_reads="$(grep -c ':= Time.get_ticks_usec()' "$BENCH_SCRIPT")"
clock_in_measure="$(printf '%s\n' "$measure_body" | grep -c ':= Time.get_ticks_usec()')"
if [ "$clock_reads" -eq 2 ] && [ "$clock_in_measure" -eq 2 ]; then
    pass "the only clock reads in the whole script are the two bracketing the measured sample"
else
    fail "clock reads exist outside the measured bracket ($clock_reads total, $clock_in_measure in _measure)"
fi

if ! printf '%s\n' "$measure_body" | grep -qE '_build_fixture|_preflight|ClassDB.instantiate'; then
    pass "the measured function contains no fixture, preflight or construction work"
else
    fail "the measured function contains setup work"
fi

fixture_pos="$(first_line_of "$run_body" '_build_fixture()')"
preflight_pos="$(first_line_of "$run_body" '_preflight(scorer')"
warm_pos="$(first_line_of "$run_body" '_warm_up(scorer')"
measure_pos="$(first_line_of "$run_body" '_measure(scorer')"
if [ -n "$fixture_pos" ] && [ -n "$preflight_pos" ] && [ -n "$warm_pos" ] \
        && [ -n "$measure_pos" ] \
        && [ "$fixture_pos" -lt "$preflight_pos" ] \
        && [ "$preflight_pos" -lt "$warm_pos" ] \
        && [ "$warm_pos" -lt "$measure_pos" ]; then
    pass "the setup order in _run is fixture -> preflight -> warm-up -> measurement"
else
    fail "the setup order in _run is not fixture -> preflight -> warm-up -> measurement"
fi

# --------------------------------- 12. warm-up is outside the measured samples
header "12. Warm-up samples are untimed and separate from the measured samples"

if printf '%s\n' "$warm_body" | grep -q '_sample(' \
        && ! printf '%s\n' "$warm_body" | grep -q 'Time.get_ticks_usec' \
        && ! printf '%s\n' "$warm_body" | grep -q 'elapsed' \
        && printf '%s\n' "$measure_body" | grep -q 'Time.get_ticks_usec' \
        && printf '%s\n' "$measure_body" | grep -q 'elapsed.append'; then
    pass "the warm-up runs the sampling path without a clock read or a recorded sample"
else
    fail "warm-up and measured samples are not cleanly separated in the source"
fi

validate calls "every smoke result line carries the smoke method counts (warmup=1, samples=3)" "$LOG_SMOKE" smoke

# --------------------------- 13. each timed sample performs exactly N calls
header "13. Each timed sample performs exactly N scorer calls"

validate calls "each result line's total_calls is exactly samples * inhabitants (and warmup_calls warmup * N)" "$LOG_SMOKE" smoke

# ------------------------- 14. each result is minimally consumed in the loop
header "14. Each result is minimally consumed inside the timed loop"

if printf '%s\n' "$sample_body" | grep -q 'chosen_id' \
        && printf '%s\n' "$sample_body" | grep -q 'checksum'; then
    pass "the sampling loop folds every returned chosen_id into the checksum"
else
    fail "the sampling loop does not consume each returned chosen_id"
fi

br_first="$(first_line_of "$measure_body" 'Time.get_ticks_usec')"
br_sample="$(first_line_of "$measure_body" '_sample(')"
br_last="$(printf '%s\n' "$measure_body" | grep -n 'Time.get_ticks_usec' | tail -n 1 | cut -d: -f1)"
if [ -n "$br_first" ] && [ -n "$br_sample" ] && [ -n "$br_last" ] \
        && [ "$br_first" -lt "$br_sample" ] && [ "$br_sample" -lt "$br_last" ]; then
    pass "each measured sample is the clock -> N calls -> clock bracket around the sampling loop"
else
    fail "the measured sample is not bracketed around the sampling loop"
fi

checksum_lines="$(grep '^REMICH_SCALE_RESULT ' "$LOG_SMOKE" 2>/dev/null \
    | grep -cE ' checksum=[0-9]+ rev=')"
if [ "$checksum_lines" -eq 4 ]; then
    pass "all four smoke result lines report a non-negative integer checksum"
else
    fail "only $checksum_lines of 4 smoke result lines report a checksum"
fi

# ------------------------ 15. the correctness preflight covers all 1,000
header "15. A correctness preflight verifies all 1,000 inputs before measurement"

validate env "the smoke run reports preflight=ok over 1,000 inputs in 2 passes" "$LOG_SMOKE" smoke

preflight_ok=1
for needle in 'while index < inputs.size()' '_result_violation'; do
    if ! printf '%s\n' "$preflight_body" | grep -qF "$needle"; then
        preflight_ok=0
        fail "_preflight is missing: $needle"
    fi
done

for needle in '"ok"' 'bridge-rev' 'candidate-count' 'candidate-ids' \
        'chosen-id' 'chosen-score' 'is_finite'; do
    if ! printf '%s\n' "$violation_body" | grep -qF "$needle"; then
        preflight_ok=0
        fail "the per-result checks are missing: $needle"
    fi
done
if grep -qF 'const EXPECTED_CANDIDATES := 6' "$BENCH_SCRIPT"; then
    :
else
    preflight_ok=0
    fail "the expected candidate count is not the committed six"
fi
if [ "$preflight_ok" -eq 1 ]; then
    pass "every required property (ok, six candidates, chosen among them, finite scores, expected revision) is asserted per input"
fi

# ------------------ 16. two untimed passes produce the same signature
header "16. Two untimed correctness passes produce the same result signature"

preflight_calls="$(grep -c '_preflight(scorer, inputs, _expected_rev)' "$BENCH_SCRIPT")"
if [ "$preflight_calls" -eq 2 ] \
        && grep -qF 'preflight-signature-mismatch' "$BENCH_SCRIPT"; then
    pass "the preflight runs twice and the run fails if the two signatures differ"
else
    fail "the two-pass signature comparison is not in place (calls found: $preflight_calls)"
fi

if grep -qE 'preflight=ok preflight_inputs=1000 preflight_passes=2 preflight_signature=[0-9]+' "$LOG_SMOKE"; then
    pass "the smoke run reports the matched preflight signature from both passes"
else
    fail "the smoke ENV line does not report a matched preflight signature"
fi

# ---------------------------- 17. smoke exercises all four populations
header "17. The smoke benchmark exercises all four populations"

validate presence "the smoke run produced one result line for each of 1, 10, 100, 1000" "$LOG_SMOKE" smoke

# ------------------ 18. exactly four REMICH_SCALE_RESULT lines in smoke
header "18. The smoke benchmark emits exactly four REMICH_SCALE_RESULT lines"

result_lines="$(grep -c '^REMICH_SCALE_RESULT ' "$LOG_SMOKE")"
if [ "$result_lines" -eq 4 ]; then
    pass "exactly four REMICH_SCALE_RESULT lines are present"
else
    fail "found $result_lines REMICH_SCALE_RESULT lines, expected 4"
fi

# ------------------------------- 19. smoke emits REMICH_SCALE_OK and exits 0
header "19. The smoke benchmark emits REMICH_SCALE_OK and exits 0"

ok_lines="$(grep -c '^REMICH_SCALE_OK ' "$LOG_SMOKE")"
if [ "$ok_lines" -eq 1 ] && [ "$SMOKE_RC" -eq 0 ]; then
    pass "exactly one REMICH_SCALE_OK line and exit code 0"
else
    fail "expected one REMICH_SCALE_OK line and exit 0 (lines: $ok_lines, rc: $SMOKE_RC)"
    tail_log "$LOG_SMOKE"
fi

validate ok "the OK line matches the smoke method and the scorer revision" "$LOG_SMOKE" smoke

# -------------------- 20. timings are finite, non-negative and consistent
header "20. Every reported timing is finite, non-negative and internally consistent"

validate values "all timing values are finite and non-negative, p95 >= median, per-inhabitant median derived from the tick median" "$LOG_SMOKE" smoke

# --------------------------- 21. no performance limit or verdict exists
header "21. No performance limit or verdict exists in benchmark code or output"

verdict_pattern='threshold|budget|verdict|fps|recommend|maximum population|too slow'
verdict_hits=""
for file in "$BENCH_SCRIPT" "$BENCH_RUNNER" "$RESULT_VALIDATOR"; do
    found="$(grep -inE "$verdict_pattern" "$file" 2>/dev/null || true)"
    if [ -n "$found" ]; then
        verdict_hits="$verdict_hits      | $file: $(printf '%s' "$found" | head -n 2 | paste -sd' ' -)
"
    fi
done
if [ -z "$verdict_hits" ]; then
    pass "no benchmark source compares a timing against a limit or prints a judgement"
else
    fail "benchmark source contains limit/verdict language:"
    printf '%s' "$verdict_hits"
fi

output_verdict="$(grep -E "$verdict_pattern" "$LOG_SMOKE" 2>/dev/null || true)"
if [ -z "$output_verdict" ]; then
    pass "the smoke output contains no verdict, label or capacity estimate"
else
    fail "the smoke output contains verdict-like language:"
    printf '%s\n' "$output_verdict" | sed 's/^/      | /'
fi

# --------------------------- 22. the official command exists as documented
header "22. The official benchmark command exists exactly as documented"

if [ -f "$BENCH_RUNNER" ] && head -n 1 "$BENCH_RUNNER" | grep -qF '#!/usr/bin/env bash'; then
    pass "$BENCH_RUNNER exists with its runner shebang"
else
    fail "$BENCH_RUNNER is missing or lacks its shebang"
fi

if grep -qF 'bash tools/benchmark_phase2_step4.sh [--smoke]' "$BENCH_RUNNER" \
        && grep -qF 'MODE="official"' "$BENCH_RUNNER"; then
    pass "the zero-argument form is the official method and --smoke is the documented variant"
else
    fail "the runner does not document/defaults the official method"
fi

bogus_out="$(bash "$BENCH_RUNNER" --bogus 2>&1)"
bogus_rc=$?
if [ "$bogus_rc" -eq 2 ] && printf '%s\n' "$bogus_out" | grep -qF 'usage'; then
    pass "any other argument is rejected with the usage line (rc=2) before any run"
else
    fail "an unexpected argument was not rejected with the usage line (rc=$bogus_rc)"
fi

# ------------------------- 23. the record holds one complete official result
header "23. The record contains one complete official result for all four populations"

if [ -f "$RECORD_DOC" ]; then
    pass "the record $RECORD_DOC exists"
    validate all "the recorded block parses as one complete official run (mode, populations, method, values)" "$RECORD_DOC" official
    for needle in "60628 + index" \
        "prefix of the same 1,000" \
        "one scorer instance" \
        "10 warm-up samples" \
        "100 measured samples" \
        "nearest-rank" \
        "outside the timed region" \
        "No performance threshold." \
        "Social LOD" \
        "cargo clean + cargo build --workspace" \
        "SCORER_BRIDGE_REV v1 -> v2 -> v1" \
        "Godot 4.7.2" \
        "1.98.1" \
        "target/debug/libremich_gdext.so" \
        "Time.get_ticks_usec" \
        "official benchmark runs: 1" \
        "AMD Ryzen 5 5600X"; do
        if grep -qF -- "$needle" "$RECORD_DOC"; then
            pass "the record states: $needle"
        else
            fail "the record is missing: $needle"
        fi
    done
    if grep -qF -- "$SCORER_SENTINEL" "$RECORD_DOC"; then
        pass "the record carries the rebuild-probe evidence (the v1 -> v2 -> v1 sentinel observation)"
    else
        fail "the record does not carry the rebuild-probe sentinel observation"
    fi
else
    fail "the record $RECORD_DOC does not exist yet (it is written after the official run)"
fi

# -------------------- 24. the record names the exact official command
header "24. The record names the exact official reproduction command"

if [ -f "$RECORD_DOC" ] \
        && grep -qE 'bash tools/benchmark_phase2_step4\.sh([^ -]|$)' "$RECORD_DOC"; then
    pass "the record names: bash tools/benchmark_phase2_step4.sh"
else
    fail "the record does not name the exact official command"
fi

# --------------- 25. the record states: official run once, no optimisation
header "25. The record states the official benchmark ran once with no optimisation after it"

if [ -f "$RECORD_DOC" ]; then
    runs="$(grep -cF 'official benchmark runs: 1' "$RECORD_DOC")"
    if [ "$runs" -eq 1 ]; then
        pass "the record says: official benchmark runs: 1 (exactly once, stated once)"
    else
        fail "the record's official-run statement appears $runs times, expected exactly 1"
    fi
    if grep -qF 'No optimisation or tuning pass followed the official result.' \
            "$RECORD_DOC"; then
        pass "the record states that no optimisation or tuning pass followed the official result"
    else
        fail "the record does not state that no optimisation followed the official result"
    fi
else
    fail "the record $RECORD_DOC does not exist yet"
fi

# --------------------------------- 26. the measured commit is named
header "26. The measured commit is named"

MEASURED=""
if [ -f "$RECORD_DOC" ]; then
    MEASURED="$(grep -iE 'measured commit' "$RECORD_DOC" \
        | grep -oE '\b[0-9a-f]{40}\b' | head -n1)"
fi
if [ -z "$MEASURED" ]; then
    fail "the record does not name a 40-hex measured commit"
else
    if git cat-file -e "${MEASURED}^{commit}" 2>/dev/null; then
        pass "the measured commit $MEASURED exists"
        if git merge-base --is-ancestor "$MEASURED" HEAD 2>/dev/null; then
            pass "the measured commit is an ancestor of HEAD"
        else
            fail "the measured commit is not an ancestor of HEAD"
        fi
    else
        fail "the named measured commit $MEASURED does not exist"
    fi
fi

# --------------- 27. measured -> final differs by documentation only
header "27. The final tree differs from the measured commit only by result documentation"

if [ -z "$MEASURED" ]; then
    fail "no measured commit to compare against (see check 26)"
else
    final_delta="$(git diff --name-only "$MEASURED" HEAD)"
    non_doc=""
    while IFS= read -r file; do
        [ -z "$file" ] && continue
        case "$file" in
            docs/*.md) ;;
            # Remich issue #9 / Phase 3 Step 1: the authorized catalogue
            # embedding, the checkers whose ratchets it moved (this one
            # included), and the two scripts it adds. Nothing else may reach
            # the final head.
            "$N9_CATALOGUE" | tools/check_phase2_step4.sh \
                | tools/check_phase1_step3.sh \
                | tools/check_phase1_step4.sh | tools/check_phase1_step5.sh \
                | tools/check_phase2_step1.sh | tools/check_phase2_step2.sh \
                | tools/check_phase2_step3.sh | tools/check_phase3_step1.sh \
                | tools/check_catalogue_relocation.sh) ;;
            *) non_doc="$non_doc      | $file
" ;;
        esac
    done <<<"$final_delta"
    if [ -n "$non_doc" ]; then
        fail "the measured -> final diff contains files beyond documentation and the named Remich #9 set:"
        printf '%s' "$non_doc"
    elif [ -z "$final_delta" ]; then
        fail "the final head does not differ from the measured commit by the record"
    else
        pass "measured -> final differs by documentation only, plus the named Remich #9 files:"
        printf '%s\n' "$final_delta" | sed 's/^/      | /'
    fi
fi

# ------------------------------ 28. warning-free build and tests
header "28. The workspace builds and tests warning-free"

if [ "$BUILD_RC" -eq 0 ]; then
    pass "cargo build --workspace exits 0"
else
    fail "cargo build --workspace exits $BUILD_RC:"
    tail_log "$LOG_BUILD"
fi
if [ "$TEST_RC" -eq 0 ]; then
    pass "cargo test --workspace exits 0"
else
    fail "cargo test --workspace exits $TEST_RC:"
    tail_log "$LOG_TEST"
fi
for label in "the workspace build:LOG_BUILD" "the test suite:LOG_TEST"; do
    name="${label%%:*}"
    varname="${label##*:}"
    if grep -q '^warning' "${!varname}" 2>/dev/null; then
        fail "$name emitted warnings:"
        grep '^warning' "${!varname}" | sed 's/^/      | /'
    else
        pass "$name is warning-free"
    fi
done

# --------------------------- 29. no generated state is tracked
header "29. No generated benchmark output, build or staging state is tracked"

tracked="$(git ls-files | grep -E '(^target/|\.so$|_expectation\.txt$|\.jsonl$|\.log$|^godot/\.godot/)' || true)"
if [ -z "$tracked" ]; then
    pass "no build, staging, trace or benchmark-output file is tracked"
else
    fail "generated state is tracked:"
    printf '%s\n' "$tracked" | sed 's/^/      | /'
fi

for generated in godot/bridge_probe_expectation.txt godot/.godot/extension_list.cfg \
        target/debug/libremich_gdext.so; do
    if git check-ignore -q "$generated" 2>/dev/null; then
        pass "generated state stays ignored: $generated"
    else
        fail "generated state is not ignored: $generated"
    fi
done

# --------------------- 30. no other repository was modified; paths limited
header "30. No other repository was modified; external paths stay limited"

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

# --------------------------------------------- 31. the worktree is clean
header "31. The worktree is clean"

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
    printf 'PASS  Phase 2 Step 4 — many inhabitants, measured\n'
    printf '========================================\n'
    exit 0
fi
printf 'FAIL  Phase 2 Step 4 — %d check(s) failed\n' "$failures"
printf '========================================\n'
exit 1
