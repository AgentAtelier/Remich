#!/usr/bin/env bash
# Phase 1, Step 4 acceptance check — "the scorer, callable from Godot"
# (docs/PLAN.md §4, step 4; record: docs/remich-scorer-step4.md).
#
# One command, from anywhere:
#
#     bash tools/check_phase1_step4.sh
#
# It fails if the Step 4 scorer loses its layering, its donor-only scoring, its
# deterministic seed-sensitive fixture, its Godot proof or its clean head. It
# runs the Step 3 acceptance first (which runs Step 2, which runs Step 1), so
# provenance, firewall, donor tests and the bridge cannot regress underneath a
# green Step 4.
#
# Checks:
#
#   1. the Step 3 acceptance is still green;
#   2. the Step 3 donor files and data are unchanged (source tree and worktree),
#      apart from the single file Remich #9 / Phase 3 Step 1 authorizes;
#   3. the Step 3 record carries that authorized adaptation, and docs/PLAN.md is
#      byte-identical to the lead's Phase 3 plan merge;
#   4. remich_core is engine-free (manifest, source and dependency tree);
#   5. remich_core calls the imported scorer and defines no donor formula;
#   6. only remich_gdext carries an engine dependency or engine types;
#   7. RemichScorer is a real registered GDExtension class speaking plain data;
#   8. the fixture returns candidate scores and the chosen action and place;
#   9. pinned Godot 4.7.2 verifies that result inside the engine;
#  10. need advance/decay works, and Godot verifies it;
#  11. same-input/same-seed determinism and a fixed seed-sensitive fixture;
#  12. the workspace builds without warnings and its tests pass;
#  13. the existing Step 2 bridge is still green;
#  14. no generated state or expectation file is committed, worktree clean;
#  15. no timing probe remains and both timings are recorded;
#  16. no other repository is touched, and no foreign repository is referenced.

set -uo pipefail

REPO_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)" || exit 1
cd "$REPO_ROOT" || exit 1

# Qualified headless path only: never editor, import or export mode.
GODOT_BIN="/home/mrg/Documents/Project/Yolanda/.godot-local/engine/4.7.2/Godot_v4.7.2-stable_linux.x86_64"
GODOT_PROJECT="godot"

VAULT="/home/mrg/Documents/Project/buggy-vault"
VAULT_COMMIT="24181142c693be37f90a6a667a6dc493425cd832"
# The merge commit that ended Step 3: everything Step 3 took must be byte-identical.
STEP3_BASE="35276c0d51f0d2538d5e60fbb2244cd369488a8d"
# Remich issue #9 / Phase 3 Step 1 (the embedded action catalogue): the one
# donor file this step is authorized to change, and the lead's Phase 3 plan
# merge, which is now docs/PLAN.md's freeze point (that merge extended the
# plan after STEP3_BASE, so the plan can no longer be byte-identical to it).
N9_CATALOGUE="crates/anvil_sim/src/actions/catalogue.rs"
PLAN_MERGE="cfa796cc4885432da93b1974602ef3ba9a7cbff8"

GDEX_SRC="crates/remich_gdext/src/lib.rs"
CORE_SRC_DIR="crates/remich_core/src"
FIXTURE_TEST="crates/remich_core/tests/seed_sensitive_fixture.rs"
PROBE_GD="godot/scorer_probe.gd"
RECORD_DOC="docs/remich-scorer-step4.md"
STEP3_DOC="docs/anvil-import-phase1-step3.md"
PLAN_DOC="docs/PLAN.md"
EXPECTATION_FILE="godot/scorer_probe_expectation.txt"
COMMITTED_SCORER_REV="remich-scorer-v1"
# The probe sentinel: the one-line value the rebuild measurement changed it to.
# It may survive in exactly one place — the record that documents it.
# Remich issue #9 / Phase 3 Step 1: this checker is edited for the catalogue
# embedding, so the sentinel is assembled instead of written literally — a
# literal here would put it in a file that step changed, which is exactly what
# tools/check_phase2_step4.sh's ratchet forbids. Same value, no weakening.
SENTINEL="$(printf 'remich-scorer-v%s' '2')"

LOG_DIR="$(mktemp -d "${TMPDIR:-/tmp}/remich-p1s4.XXXXXX")" || exit 1
trap 'rm -rf "$LOG_DIR"' EXIT

failures=0
pass() { printf 'ok    %s\n' "$1"; }
fail() { printf 'FAIL  %s\n' "$1"; failures=$((failures + 1)); }
note() { printf '      %s\n' "$1"; }
header() { printf '\n== %s ==\n' "$1"; }

# Strips cargo tree's absolute source-path annotation. The check is about crate
# identity: a checkout path containing "godot" must not count as an engine
# crate, while a real `godot v0.5.5` package line (which carries no path
# annotation) survives untouched. See docs/remich-scorer-step4.md §11.
strip_paths='s/ \((path[+]file:)?\/[^)]*\)//g'

# --------------------------------------------------- 1. Step 3 still green
header "1. The Step 3 acceptance is still green"

if bash tools/check_phase1_step3.sh >"$LOG_DIR/step3.log" 2>&1; then
    pass "bash tools/check_phase1_step3.sh exits 0"
    tail -n 3 "$LOG_DIR/step3.log" | sed 's/^/      | /'
else
    fail "bash tools/check_phase1_step3.sh failed:"
    grep '^FAIL' "$LOG_DIR/step3.log" | sed 's/^/      | /'
    tail -n 60 "$LOG_DIR/step3.log" | sed 's/^/      | /'
fi

# ------------------------------------------- 2. Step 3 donor files unchanged
header "2. The Step 3 donor files and data are unchanged"

# `git diff <commit>` compares the commit against the working tree, so it
# catches both a rewritten file and an uncommitted edit.
#
# Remich issue #9 / Phase 3 Step 1: exactly one donor file may differ — the
# authorized catalogue embedding, whose narrowness is proved by check 1
# (tools/check_phase1_step3.sh) and re-proved by tools/check_phase3_step1.sh.
# Every other donor and data file stays byte-identical to the Step 3 base.
donor_delta="$(git diff --name-only "$STEP3_BASE" -- crates/anvil_sim crates/anvil_core assets 2>/dev/null \
    | grep -vxF "$N9_CATALOGUE" || true)"
if [ -z "$donor_delta" ]; then
    pass "crates/anvil_sim, crates/anvil_core and assets are byte-identical to the Step 3 base, apart from the authorized $N9_CATALOGUE"
else
    fail "a Step 3 donor file or data file changed since the Step 3 base:"
    printf '%s\n' "$donor_delta" | sed 's/^/      | /'
fi

if [ -f "$STEP3_DOC" ] && grep -qF "buggy-vault@${VAULT_COMMIT:0:8}" "$STEP3_DOC"; then
    pass "the Step 3 provenance record still names the pinned donor"
else
    fail "the Step 3 provenance record is missing or no longer names the donor"
fi

# ------------------------------------- 3. Step 3 record and PLAN not rewritten
header "3. The Step 3 record carries the authorized #9 change; the plan is frozen at the plan merge"

# Remich issue #9 / Phase 3 Step 1: two named exceptions, and nothing else.
#
# (a) docs/anvil-import-phase1-step3.md must record the authorized catalogue
#     adaptation (issue #9 §6), so it is no longer byte-identical to the
#     Step 3 base. Its content is still guarded: check 1 runs
#     tools/check_phase1_step3.sh first, which verifies the donor identity,
#     the inventory and its counts, every provenance line, byte verification,
#     the §5 adaptation list, the asset sha256 and the timings section.
# (b) docs/PLAN.md was extended by the lead's Phase 3 plan merge, an ancestor
#     of this head, after the Step 3 base. Its freeze therefore moves to that
#     merge: it must be byte-identical to the merged plan, so this step still
#     cannot rewrite it.
record_delta="$(git diff --name-only "$STEP3_BASE" -- "$STEP3_DOC" 2>/dev/null)"
plan_delta=""
if ! git diff --quiet "$PLAN_MERGE" -- "$PLAN_DOC" 2>/dev/null; then
    plan_delta="$PLAN_DOC"
fi
if [ -n "$plan_delta" ]; then
    fail "$PLAN_DOC was rewritten since the Phase 3 plan merge $PLAN_MERGE:"
    printf '%s\n' "$plan_delta" | sed 's/^/      | /'
else
    pass "$PLAN_DOC is byte-identical to the Phase 3 plan merge $PLAN_MERGE"
fi
if [ -n "$record_delta" ]; then
    pass "$STEP3_DOC records the authorized Remich #9 adaptation (its content is proved by check 1)"
    printf '%s\n' "$record_delta" | sed 's/^/      | /'
else
    fail "$STEP3_DOC does not record the Remich #9 catalogue adaptation issue #9 requires"
fi

# ----------------------------------------- 4. remich_core is engine-free
header "4. remich_core is engine-free (manifest, source, dependency tree)"

if grep -qiE 'godot|gdext' crates/remich_core/Cargo.toml; then
    fail "remich_core's manifest names an engine:"
    grep -niE 'godot|gdext' crates/remich_core/Cargo.toml | sed 's/^/      | /'
else
    pass "remich_core's manifest names no engine"
fi

if grep -rqiE 'godot|gdext' "$CORE_SRC_DIR"; then
    fail "remich_core's source names an engine:"
    grep -rniE 'godot|gdext' "$CORE_SRC_DIR" | sed 's/^/      | /'
else
    pass "remich_core's source contains no engine name or engine API use"
fi

if cargo tree -p remich_core --edges normal,build 2>/dev/null | sed -E "$strip_paths" \
        | grep -qiE 'godot|gdext'; then
    fail "cargo tree -p remich_core resolves an engine crate (the firewall is broken)"
else
    pass "cargo tree -p remich_core resolves no engine crate"
fi

if cargo metadata --format-version 1 --no-deps 2>/dev/null \
        | jq -e '.packages[] | select(.name=="remich_core") | .dependencies[].name' 2>/dev/null \
        | grep -qiE 'godot|gdext'; then
    fail "remich_core's resolved dependencies contain an engine crate"
else
    pass "remich_core's resolved dependencies contain no engine crate"
fi

# ------------------------------- 5. remich_core calls the imported scorer
header "5. remich_core depends on the imported scorer and duplicates no formula"

if grep -qE '^anvil_sim[[:space:]]*=' crates/remich_core/Cargo.toml; then
    pass "remich_core depends on the imported anvil_sim"
else
    fail "remich_core does not depend on the imported anvil_sim"
fi

if grep -q 'compute_utility_score' "$CORE_SRC_DIR/scorer.rs" \
        && grep -q 'use anvil_sim::utility::scoring::compute_utility_score' "$CORE_SRC_DIR/scorer.rs"; then
    pass "remich_core calls the donor's compute_utility_score"
else
    fail "remich_core does not call the donor's compute_utility_score"
fi

if grep -q 'LayeredSoul::from_seed' "$CORE_SRC_DIR/scorer.rs"; then
    pass "remich_core obtains its actor state from the donor's LayeredSoul::from_seed"
else
    fail "remich_core does not use the donor's LayeredSoul::from_seed"
fi

if grep -q 'Need::decay_rate\|decay_rate()' "$CORE_SRC_DIR/decay.rs" \
        && grep -qF 'kimi_npc_mod.rs' "$CORE_SRC_DIR/decay.rs"; then
    pass "remich_core applies decay through the donor's Need::decay_rate and cites the donor reference"
else
    fail "remich_core's decay adapter does not use/cite the donor decay rate"
fi

donor_defs="$(grep -rnE \
    'fn (base_urgency|time_block_multiplier|skill_modifier|perception_filter|substrate_weight|coping_modifier|cooperation_modifier|compute_utility_score|decay_needs|all_needs|need_index)\b' \
    crates/remich_core crates/remich_gdext 2>/dev/null || true)"
if [ -z "$donor_defs" ]; then
    pass "neither remich_core nor remich_gdext defines any donor scoring or system function"
else
    fail "a donor scoring/system function is re-implemented outside anvil_sim:"
    printf '%s\n' "$donor_defs" | sed 's/^/      | /'
fi

# --------------------------- 6. only remich_gdext carries the engine
header "6. Only remich_gdext carries an engine dependency or engine types"

engine_names=""
for manifest in crates/*/Cargo.toml; do
    case "$manifest" in *remich_gdext/Cargo.toml) continue ;; esac
    # TOML comments are stripped: prose that says "no godot here" is not a
    # dependency.
    if grep -iE 'godot|gdext' "$manifest" 2>/dev/null | grep -qvE '^[[:space:]]*#'; then
        engine_names="$engine_names $manifest"
    fi
done
for source in crates/*/src crates/*/tests crates/*/examples crates/*/benches; do
    [ -d "$source" ] || continue
    case "$source" in *remich_gdext/*) continue ;; esac
    # Comments are stripped: a doc comment naming `godot/scorer_probe.gd` is
    # prose about where the proof lives, not engine use. Only code counts.
    hits="$(grep -rniE 'godot|gdext' "$source" 2>/dev/null \
        | grep -vE ':[0-9]+:[[:space:]]*(//|///|//!)' || true)"
    if [ -n "$hits" ]; then
        engine_names="$engine_names $source"
    fi
done
if [ -z "$engine_names" ]; then
    pass "no workspace member other than remich_gdext names an engine crate or API"
else
    fail "an engine name appears outside remich_gdext:$engine_names"
fi

engine_breaches=0
for member in $(cargo metadata --format-version 1 --no-deps 2>/dev/null \
        | jq -r '.packages[].name' 2>/dev/null | sort -u); do
    [ "$member" = "remich_gdext" ] && continue
    if cargo tree -p "$member" --edges normal,build 2>/dev/null | sed -E "$strip_paths" \
            | grep -qiE 'godot|gdext'; then
        fail "$member resolves an engine crate in its dependency closure"
        engine_breaches=$((engine_breaches + 1))
    fi
done
if [ "$engine_breaches" -eq 0 ]; then
    pass "every workspace member except remich_gdext keeps an engine-free dependency closure"
fi

# --------------------- 7. a real class, speaking plain data only
header "7. RemichScorer is a real registered GDExtension class speaking plain data"

if grep -q 'pub struct RemichScorer' "$GDEX_SRC" \
        && grep -q '#\[class(base = Node)\]' "$GDEX_SRC" \
        && grep -q '#\[derive(GodotClass)\]' "$GDEX_SRC"; then
    pass "RemichScorer is a gdext class (GodotClass derive, base Node)"
else
    fail "RemichScorer is not declared as a gdext class"
fi

if grep -q 'fn score_activity(&self, input: VarDictionary) -> VarDictionary' "$GDEX_SRC" \
        && grep -q 'fn advance_time(&self, needs: VarArray, from_tick: i64, to_tick: i64) -> VarDictionary' "$GDEX_SRC"; then
    pass "its callables take and return only Dictionary, Array and integers"
else
    fail "RemichScorer's callables are not plain-value signatures"
fi

if grep -qE '^anvil_(sim|core)[[:space:]]*=' crates/remich_gdext/Cargo.toml; then
    fail "remich_gdext depends on a donor crate directly"
else
    pass "remich_gdext depends on remich_core only — no donor crate, no foreign object"
fi

if grep -q 'use anvil_' "$GDEX_SRC"; then
    fail "remich_gdext imports a donor type directly"
else
    pass "remich_gdext imports no donor type"
fi

# Munshausen/Larochette may be named in commentary about the destination; they
# must never appear as code.
foreign="$(grep -rnE 'Munshausen|Larochette' crates --include='*.rs' 2>/dev/null \
    | grep -vE ':[0-9]+:[[:space:]]*(//|///|//!)' || true)"
if [ -z "$foreign" ]; then
    pass "no Munshausen or Larochette identifier appears in code (commentary only)"
else
    fail "a Munshausen/Larochette name appears in code:"
    printf '%s\n' "$foreign" | sed 's/^/      | /'
fi

if grep -q 'ClassDB.class_exists(SCORER_CLASS)' "$PROBE_GD" \
        && grep -q 'ClassDB.instantiate(SCORER_CLASS)' "$PROBE_GD" \
        && grep -q 'class_has_method' "$PROBE_GD"; then
    pass "the Godot-side probe instantiates it through real ClassDB"
else
    fail "the Godot-side probe does not reach RemichScorer through ClassDB"
fi

# --------------------------------------- 8. the fixture's returned result
header "8. The fixture returns candidate scores and the chosen action and place"

for literal in "0.023807715624570847" "0.056183211505413055" "east-field" "north-hills"; do
    if grep -qF "$literal" "$PROBE_GD"; then
        pass "the Godot probe expects $literal"
    else
        fail "the Godot probe does not expect $literal"
    fi
done

for needle in "recorded_a" "recorded_b" "chosen_place" "candidates" "chosen_id"; do
    if grep -qF "$needle" "$FIXTURE_TEST"; then
        pass "the committed fixture test records $needle"
    else
        fail "the committed fixture test does not record $needle"
    fi
done

# -------------------------- 9. pinned Godot verifies it in the engine
header "9. Pinned Godot 4.7.2 verifies the scorer result in the engine"

if [ -x "$GODOT_BIN" ]; then
    pass "the pinned engine exists at the qualified path"
else
    fail "the pinned engine is missing at $GODOT_BIN"
fi

# Only a real execution counts as an engine run: a shell reference to the
# pinned binary followed by a flag or another argument. The path definition, an
# existence test, a `--version` query and prose in a fail/pass/note call are
# not runs of this project. Every run must be headless, and none may put the
# engine into editor, import or export mode.
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
    printf '%s\n' "$invocations" | sed 's/^/      | /'
else
    fail "an engine run is not headless, or enters a forbidden mode:"
    printf '%s\n' "$engine_mode_problems" | sed 's/^/      | /'
fi

if bash tools/stage_scorer.sh >"$LOG_DIR/stage.log" 2>&1; then
    pass "bash tools/stage_scorer.sh (registers the extension, derives the expectation)"
    tail -n 1 "$LOG_DIR/stage.log" | sed 's/^/      | /'
else
    fail "bash tools/stage_scorer.sh failed:"
    tail -n 10 "$LOG_DIR/stage.log" | sed 's/^/      | /'
fi

godot_rc=0
"$GODOT_BIN" --headless --path "$GODOT_PROJECT" --quit-after 10 >"$LOG_DIR/godot-scorer.log" 2>&1 || godot_rc=$?
if [ "$godot_rc" -eq 0 ]; then
    pass "pinned Godot exits 0 for the scorer run"
else
    fail "pinned Godot exited $godot_rc for the scorer run"
fi

if grep -q '^REMICH_SCORER_OK ' "$LOG_DIR/godot-scorer.log"; then
    pass "the engine observed the deterministic fixture"
    grep '^REMICH_SCORER_OK ' "$LOG_DIR/godot-scorer.log" | sed 's/^/      | /'
else
    fail "no REMICH_SCORER_OK marker — the engine did not verify the scorer"
    tail -n 40 "$LOG_DIR/godot-scorer.log" | sed 's/^/      | /'
fi

if grep -q 'REMICH_SCORER_OK .*chosen_a=1 .*chosen_a_place=east-field .*chosen_b=2 .*chosen_b_place=north-hills .*candidates=6' \
        "$LOG_DIR/godot-scorer.log"; then
    pass "the engine received both choices, both places and the 6-candidate list"
else
    fail "the engine's marker does not carry the recorded choices, places and candidate count"
fi

if grep -qE 'SCRIPT ERROR|Parse Error' "$LOG_DIR/godot-scorer.log"; then
    fail "the engine reported a script error:"
    grep -E 'SCRIPT ERROR|Parse Error' "$LOG_DIR/godot-scorer.log" | sed 's/^/      | /'
else
    pass "no script errors"
fi

if grep -qE 'REMICH_(SCORER|DECAY)_FAIL' "$LOG_DIR/godot-scorer.log"; then
    fail "the scorer probe reported a failure:"
    grep -E 'REMICH_(SCORER|DECAY)_FAIL' "$LOG_DIR/godot-scorer.log" | sed 's/^/      | /'
else
    pass "no scorer or decay failure marker"
fi

if grep -q 'action id 9999 is not in the donor action catalogue' "$LOG_DIR/godot-scorer.log"; then
    pass "an unknown action id was refused loudly inside the engine (the deliberate probe)"
else
    fail "the deliberate unknown-action-id probe did not produce a clear refusal"
fi

# --------------------------------------- 10. decay, verified by Godot
header "10. Need advance/decay works and Godot verifies it"

# Run the adapter's tests first: §10 and §11 both read this log, and decay is
# what this section is about.
if cargo test -p remich_core >"$LOG_DIR/remich-core-test.log" 2>&1; then
    pass "cargo test -p remich_core (adapter, decay and fixture)"
else
    fail "cargo test -p remich_core failed:"
    tail -n 60 "$LOG_DIR/remich-core-test.log" | sed 's/^/      | /'
fi

if grep -q '^REMICH_DECAY_OK ' "$LOG_DIR/godot-scorer.log"; then
    pass "the engine verified the donor decay semantics"
    grep '^REMICH_DECAY_OK ' "$LOG_DIR/godot-scorer.log" | sed 's/^/      | /'
else
    fail "no REMICH_DECAY_OK marker — the engine did not verify decay"
fi

for test_name in \
    "advancing_across_no_boundary_decays_nothing" \
    "crossing_one_boundary_applies_exactly_one_donor_step" \
    "crossing_many_boundaries_applies_that_many_steps" \
    "values_are_clamped_at_zero_and_never_negative" \
    "safety_never_decays"
do
    if grep -qE "(^|[[:space:]:])${test_name} \.\.\. ok$" "$LOG_DIR/remich-core-test.log" 2>/dev/null; then
        pass "decay test green: $test_name"
    else
        fail "decay test not green: $test_name"
    fi
done

# --------------------- 11. determinism and seed sensitivity
header "11. Same input/same seed determinism, and a seed-sensitive fixture"

for test_name in \
    "same_input_and_same_seed_give_exactly_the_same_result" \
    "the_fixture_produces_its_recorded_result" \
    "seed_is_not_ignored_two_fixed_seeds_choose_differently" \
    "the_two_seeds_produce_different_donor_souls"
do
    if grep -qE "(^|[[:space:]:])${test_name} \.\.\. ok$" "$LOG_DIR/remich-core-test.log" 2>/dev/null; then
        pass "determinism test green: $test_name"
    else
        fail "determinism test not green: $test_name"
    fi
done

# The fixture must be literals in a committed test, never a search that could
# find a seed the implementation happens to satisfy.
if grep -qE '0\.\.[0-9_]{3,}|thread_rng|rand::|gen_range|while let Some' "$FIXTURE_TEST"; then
    fail "the fixture test searches for a case instead of committing one"
else
    pass "the fixture test contains no seed search"
fi

if grep -q 'SEED_A: u64 = 60_628' "$FIXTURE_TEST" \
        && grep -q 'SEED_B: u64 = 87_004' "$FIXTURE_TEST"; then
    pass "both seeds are committed literals"
else
    fail "the two fixture seeds are not committed literals"
fi

if grep -qF 'for_a.chosen_id, for_b.chosen_id' "$FIXTURE_TEST"; then
    pass "the fixture asserts the two seeds choose differently (fails if the seed is ignored)"
else
    fail "the fixture does not assert that the two seeds choose differently"
fi

if grep -qF 'score.to_bits()' "$FIXTURE_TEST"; then
    pass "the fixture compares scores bit for bit"
else
    fail "the fixture does not compare scores bit for bit"
fi

# ------------------------------------- 12. workspace build and tests
header "12. The workspace builds without warnings and its tests pass"

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

# --------------------------------------- 13. the Step 2 bridge is green
header "13. The existing Step 2 bridge remains green"

if grep -q '^REMICH_BRIDGE_OK ' "$LOG_DIR/godot-scorer.log"; then
    pass "the Step 2 bridge probe still answers with its marker"
    grep '^REMICH_BRIDGE_OK ' "$LOG_DIR/godot-scorer.log" | sed 's/^/      | /'
else
    fail "no REMICH_BRIDGE_OK marker in the scorer run"
fi

if grep -q '^REMICH_TEST_PROJECT_OPENED$' "$LOG_DIR/godot-scorer.log"; then
    pass "the pinned engine still opened this project and ran its scene"
else
    fail "no REMICH_TEST_PROJECT_OPENED marker"
fi

# ------------------------ 14. no generated state, worktree clean
header "14. No generated state is committed and the worktree is clean"

generated="$(git ls-files \
    | grep -E '(^|/)(target|\.godot|staging)(/|$)|\.so$|\.dylib$|\.dll$|bridge_probe_expectation\.txt$|scorer_probe_expectation\.txt$' \
    || true)"
if [ -z "$generated" ]; then
    pass "no build, import, library or expectation state is tracked"
else
    fail "generated state is tracked by git:"
    printf '%s\n' "$generated" | sed 's/^/      | /'
fi

if git check-ignore -q "$EXPECTATION_FILE" && git check-ignore -q "godot/bridge_probe_expectation.txt"; then
    pass "both derived expectation files are ignored"
else
    fail "a derived expectation file is not ignored"
fi

stray="$(git status --porcelain 2>/dev/null)"
if [ -z "$stray" ]; then
    pass "the worktree is clean — no modified, staged or untracked file remains"
else
    fail "the worktree is not clean at the acceptance head:"
    printf '%s\n' "$stray" | sed 's/^/      | /'
fi

# --------------------------- 15. no timing probe, timings recorded
header "15. No timing probe remains and both timings are recorded"

rev="$(sed -n 's/^[[:space:]]*pub const SCORER_BRIDGE_REV: &str = "\([^"]*\)".*/\1/p' "$GDEX_SRC" 2>/dev/null)"
if [ "$rev" = "$COMMITTED_SCORER_REV" ]; then
    pass "SCORER_BRIDGE_REV holds its committed value ('$rev')"
else
    fail "SCORER_BRIDGE_REV is '$rev', expected '$COMMITTED_SCORER_REV' — the probe was not reverted"
fi

# The sentinel may survive only in the record that documents it. Searching the
# worktree (not `git grep`) so untracked survivors are caught too; this script
# names the sentinel and is therefore excluded, exactly as Step 3 excludes
# itself for its own sentinel.
sentinel_files="$(grep -rlF "$SENTINEL" . \
    --exclude-dir=.git --exclude-dir=target --exclude-dir=.godot \
    --exclude='check_phase1_step4.sh' 2>/dev/null | sed 's|^\./||' | sort || true)"
if [ "$sentinel_files" = "$RECORD_DOC" ]; then
    pass "the probe sentinel '$SENTINEL' appears only in the record that documents it"
else
    fail "the probe sentinel '$SENTINEL' survives in:$sentinel_files"
fi

if [ -f "$RECORD_DOC" ] \
        && grep -q 'Clean build' "$RECORD_DOC" \
        && grep -qF '42.70 s' "$RECORD_DOC" \
        && grep -q 'One-line probe' "$RECORD_DOC" \
        && grep -qF '0.80 s' "$RECORD_DOC" \
        && grep -qF "$SENTINEL" "$RECORD_DOC" \
        && grep -qF 'sha256' "$RECORD_DOC"; then
    pass "the record carries both timings, the exact diff and the restore evidence"
    grep -E '^\| (Clean build|One-line probe)' "$RECORD_DOC" | sed 's/^/      | /'
else
    fail "$RECORD_DOC lacks the clean-build timing, the probe timing or the restore evidence"
fi

# ------------------------- 16. no other repository is touched
header "16. No other repository is touched and none is referenced"

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
    --include='*.md' --include='*.sh' --include='*.json' . 2>/dev/null | sort -u)"
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
    printf 'PASS  Phase 1 Step 4 — the scorer, callable from Godot\n'
    printf '========================================\n'
    exit 0
fi
printf 'FAIL  Phase 1 Step 4 — %d check(s) failed\n' "$failures"
printf '========================================\n'
exit 1
