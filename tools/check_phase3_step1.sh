#!/usr/bin/env bash
# Phase 3, Step 1 acceptance check — "the embedded catalogue"
# (docs/PLAN.md §4b, step 1; Remich issue #9; record:
# docs/remich-catalogue-phase3-step1.md).
#
# One command, from anywhere:
#
#     bash tools/check_phase3_step1.sh
#
# Issue #9 is the authority for this step: the shipped library used to read
# `assets/sim/actions.json` from the checkout it was built in, so a game that
# loaded Remich elsewhere panicked on the first `score_activity`. The lead
# authorized exactly one donor adaptation — embed the committed catalogue at
# compile time and parse it with `serde_json::from_str`, same data, same
# error type — plus the historical ratchets that adaptation legitimately
# moves. This checker proves that change, and only that change.
#
# Requirements, as checks (numbered as the step prompt numbered them):
#
#   1. the Phase 3 plan merge is an ancestor of this head;
#   2. the authorized catalogue file is the only file under crates/, assets/
#      or godot/ changed for this step;
#   3. assets/sim/actions.json keeps its qualified sha256;
#   4. the catalogue's inventory status is `adapted`;
#   5. its provenance still names the exact donor path and vault commit;
#   6. the post-import, issue-#9 adaptation is documented;
#   7. runtime catalogue loading uses compile-time embedded text;
#   8. runtime parsing uses serde_json::from_str;
#   9. the non-test runtime loader uses neither repo_path! nor filesystem
#      access;
#  10. the ActionCatalogueError API is unchanged, byte for byte;
#  11. the new embedded-vs-file test exists and passes;
#  12. the embedded catalogue parses to 26 actions;
#  13. the donor source-test count is exactly 184;
#  14. cargo test -p anvil_core -p anvil_sim passes;
#  15. cargo test --workspace passes warning-free;
#  16. every adjusted historical ratchet names Remich #9 / Phase 3 Step 1 and
#      carries only named exceptions — no wildcard, no directory, no other
#      checker touched;
#  17. tools/check_phase2_step4.sh is green (which transitively re-proves the
#      bridge, scorer, deterministic day, clock, weather, save and benchmark);
#  18. the normal pinned-Godot day succeeds;
#  19. the normal day trace equals the canonical qualified SHA-256;
#  20. the relocation proof builds before the move and never rebuilds after;
#  21. the old build-checkout path is genuinely absent before scoring;
#  22. the relocated pinned-Godot scorer/day succeeds;
#  23. the relocated day trace equals the same canonical SHA-256;
#  24. the donor vault is still at 24181142 and clean;
#  25. no other repository was modified, and external paths stay limited;
#  26. no generated relocation, build or trace state is tracked;
#  27. the worktree is clean.
#
# Where behaviour can prove the rule, it does: both day runs, the relocation
# proof, the workspace tests and the Step 4 sub-check are executed. Structural
# facts that cannot be observed from outside — that the loader embeds its data
# — are asserted against the source, and the relocation proof is itself the
# behavioural demonstration that the baked build path is gone.
set -uo pipefail

REPO_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)" || exit 1
cd "$REPO_ROOT" || exit 1

# The lead's Phase 3 plan merge: the base of this step — ancestry, the
# donor/asset comparison, and the freeze base of every historical checker.
PLAN_MERGE="cfa796cc4885432da93b1974602ef3ba9a7cbff8"
# Remich Phase 3 Step 2 — soul primitives across the bridge (the lead's
# docs-only plan re-scope, 2026-10-01): docs/PLAN.md's byte-for-byte freeze
# point moved from $PLAN_MERGE to the commit that made the amendment, so plan
# content is compared against PLAN_FREEZE. Any further edit to the plan still
# fails the plan check below; re-pin PLAN_FREEZE only for an authorized
# amendment.
PLAN_FREEZE="02eff4214c97d31743e7486a9d905fa5c22541a6"
VAULT="/home/mrg/Documents/Project/buggy-vault"
VAULT_COMMIT="24181142c693be37f90a6a667a6dc493425cd832"
DATA_SHA="166104ba90e30446adfb8d15ec6e242a52567c979bccb274a7011296b163dba5"
CANONICAL_DAY_SHA="6a5c78729a519163a16d2e754ed74d63ff0a3b9d0a957ef19b8543a89fe4ce2b"
# Qualified headless path only: never editor, import or export mode.
GODOT_BIN="/home/mrg/Documents/Project/Yolanda/.godot-local/engine/4.7.2/Godot_v4.7.2-stable_linux.x86_64"

CATALOGUE="crates/anvil_sim/src/actions/catalogue.rs"
PROVENANCE_DOC="docs/anvil-import-phase1-step3.md"
RECORD_DOC="docs/remich-catalogue-phase3-step1.md"
RELOCATION_PROOF="tools/check_catalogue_relocation.sh"
STEP4_CHECKER="tools/check_phase2_step4.sh"
PLAN_DOC="docs/PLAN.md"
# The donor source `#[test]` count: 184 since this step added exactly one
# catalogue test (183 was the frozen count at the import).
EXPECTED_SOURCE_TESTS=184
# The historical ratchets issue #9 legitimately moved — all seven, no others.
ADJUSTED_CHECKERS="tools/check_phase1_step3.sh tools/check_phase1_step4.sh
tools/check_phase1_step5.sh tools/check_phase2_step1.sh
tools/check_phase2_step2.sh tools/check_phase2_step3.sh
tools/check_phase2_step4.sh"
FROZEN_CHECKERS="tools/check_phase1_step1.sh tools/check_phase1_step2.sh"

LOG_DIR="$(mktemp -d "${TMPDIR:-/tmp}/remich-p3s1.XXXXXX")" || exit 1
trap 'rm -rf "$LOG_DIR"' EXIT

failures=0
pass() { printf 'ok    %s\n' "$1"; }
fail() { printf 'FAIL  %s\n' "$1"; failures=$((failures + 1)); }
note() { printf '      %s\n' "$1"; }
header() { printf '\n== %s ==\n' "$1"; }

# ------------------------------------------------- 1. the plan merge is base
header "1. The Phase 3 plan merge is an ancestor of this head"

if git merge-base --is-ancestor "$PLAN_MERGE" HEAD 2>/dev/null; then
    pass "the Phase 3 plan merge $PLAN_MERGE is an ancestor of HEAD"
else
    fail "the Phase 3 plan merge $PLAN_MERGE is NOT an ancestor of HEAD"
fi
note "HEAD is $(git rev-parse HEAD)"

# ---------------------------------------- 2. only the authorized file changed
header "2. The authorized catalogue file is the only donor/data/engine file changed"

behaviour_delta="$(git diff --name-only "$PLAN_MERGE" -- crates/ assets/ godot/ 2>/dev/null)"
if [ "$behaviour_delta" = "$CATALOGUE" ]; then
    pass "only $CATALOGUE differs under crates/, assets/ and godot/"
else
    fail "the files changed under crates/, assets/ and godot/ are:"
    printf '%s\n' "${behaviour_delta:-<none>}" | sed 's/^/      | /'
fi

# ------------------------------------------------------------- 3. asset bytes
header "3. The committed catalogue data keeps its qualified sha256"

if [ -f assets/sim/actions.json ]; then
    data_sha="$(sha256sum assets/sim/actions.json | cut -d' ' -f1)"
    if [ "$data_sha" = "$DATA_SHA" ]; then
        pass "assets/sim/actions.json sha256 is $DATA_SHA"
    else
        fail "assets/sim/actions.json sha256 is '$data_sha', expected $DATA_SHA"
    fi
else
    fail "assets/sim/actions.json is missing"
fi

# --------------------------------------------------- 4-6. the provenance record
header "4-6. The inventory entry, its donor provenance and the post-import note"

if [ -f "$PROVENANCE_DOC" ]; then
    entry="$(grep -F "$CATALOGUE :: " "$PROVENANCE_DOC" || true)"
    if [ -n "$entry" ]; then
        prov="$(awk -F ' :: ' '{ print $2 }' <<<"$entry")"
        status="$(awk -F ' :: ' '{ print $3 }' <<<"$entry")"
        if [ "$status" = "adapted" ]; then
            pass "the inventory status of $CATALOGUE is 'adapted'"
        else
            fail "the inventory status of $CATALOGUE is '$status', expected 'adapted'"
        fi
        expected_prov="buggy-vault@${VAULT_COMMIT:0:8} repos/anvil/source/$CATALOGUE"
        if [ "$prov" = "$expected_prov" ]; then
            pass "its provenance is the canonical donor path at the pinned vault commit"
        else
            fail "its provenance is '$prov', expected '$expected_prov'"
        fi
    else
        fail "the inventory has no entry for $CATALOGUE"
    fi

    for needle in \
        "Post-import adaptation" \
        "Remich issue #9 / Phase 3 Step 1" \
        "2026-10-01" \
        "CARGO_MANIFEST_DIR" \
        "include_str!" \
        "serde_json::from_str" \
        "IoError(NotFound)" \
        "ActionCatalogueError"
    do
        if grep -qF "$needle" "$PROVENANCE_DOC"; then
            pass "the record documents: $needle"
        else
            fail "the record does not document: $needle"
        fi
    done
else
    fail "$PROVENANCE_DOC is missing"
fi

# --------------------------------- 7-10. the loader, the parse and the error API
header "7-10. The runtime loader embeds, parses with serde_json::from_str, and keeps its error API"

if [ -f "$CATALOGUE" ]; then
    # The code the library actually runs: everything before the test module,
    # with // comments stripped so prose cannot satisfy a source assertion.
    sed -n '1,/^#\[cfg(test)\]/p' "$CATALOGUE" | sed 's|//.*$||' \
        >"$LOG_DIR/catalogue-runtime.rs"

    if grep -qF 'include_str!' "$LOG_DIR/catalogue-runtime.rs" \
            && grep -qF 'env!("CARGO_MANIFEST_DIR")' "$LOG_DIR/catalogue-runtime.rs" \
            && grep -qF '"/../../assets/sim/actions.json"' "$LOG_DIR/catalogue-runtime.rs"; then
        pass "the runtime loader embeds the committed catalogue at compile time"
    else
        fail "the runtime loader does not embed assets/sim/actions.json at compile time"
    fi

    if grep -qF 'serde_json::from_str' "$LOG_DIR/catalogue-runtime.rs"; then
        pass "the runtime parse is serde_json::from_str"
    else
        fail "the runtime parse is not serde_json::from_str"
    fi

    runtime_touched="$(grep -nE 'repo_path|std::fs|fs::read|File::open' \
        "$LOG_DIR/catalogue-runtime.rs" || true)"
    if [ -z "$runtime_touched" ]; then
        pass "the non-test loader uses neither repo_path! nor any filesystem access"
    else
        fail "the non-test loader still reaches the build checkout:"
        printf '%s\n' "$runtime_touched" | sed 's/^/      | /'
    fi

    # The error API must be byte-identical to the donor's, even though the
    # runtime loader no longer performs I/O: issue #9 forbade redesigning it.
    donor_enum="$(git -C "$VAULT" show \
        "$VAULT_COMMIT:repos/anvil/source/$CATALOGUE" 2>/dev/null \
        | sed -n '/^#\[derive(Debug, Error)\]$/,/^}$/p')"
    ours_enum="$(sed -n '/^#\[derive(Debug, Error)\]$/,/^}$/p' "$CATALOGUE")"
    if [ -n "$donor_enum" ] && [ "$donor_enum" = "$ours_enum" ]; then
        pass "ActionCatalogueError is byte-identical to the donor's definition"
    else
        fail "ActionCatalogueError differs from the donor's definition:"
        diff <(printf '%s\n' "$donor_enum") <(printf '%s\n' "$ours_enum") \
            | sed 's/^/      | /' || true
    fi
    for variant in 'IoError(#[from] std::io::Error)' \
                   'ParseError(#[from] serde_json::Error)' \
                   '#[non_exhaustive]' \
                   'pub enum ActionCatalogueError'; do
        if grep -qF "$variant" "$CATALOGUE"; then
            pass "the error API still declares: $variant"
        else
            fail "the error API no longer declares: $variant"
        fi
    done
else
    fail "$CATALOGUE is missing"
fi

# ---------------------------------------------------- 11-13. the new test, 26
header "11-13. The embedded-vs-file test exists, 26 actions parse, 184 source tests"

if grep -qF 'fn embedded_catalogue_is_the_committed_file' "$CATALOGUE"; then
    pass "the embedded-vs-file test exists in $CATALOGUE"
else
    fail "the embedded-vs-file test is missing from $CATALOGUE"
fi

actions_count="$(grep -c '"id"' assets/sim/actions.json 2>/dev/null)"
if [ "$actions_count" = "26" ]; then
    pass "the committed catalogue carries 26 actions"
else
    fail "the committed catalogue carries $actions_count actions, expected 26"
fi

source_tests="$(grep -r --include='*.rs' -o '#\[test\]' crates/anvil_sim crates/anvil_core 2>/dev/null | wc -l)"
if [ "$source_tests" = "$EXPECTED_SOURCE_TESTS" ]; then
    pass "the donor source #[test] count is $source_tests"
else
    fail "the donor source #[test] count is $source_tests, expected $EXPECTED_SOURCE_TESTS"
fi

# ------------------------------------------------------- 14-15. workspace tests
header "14-15. The donor tests and the workspace build and test warning-free"

if cargo test -p anvil_core -p anvil_sim >"$LOG_DIR/donor-test.log" 2>&1; then
    pass "cargo test -p anvil_core -p anvil_sim"
else
    fail "cargo test -p anvil_core -p anvil_sim failed:"
    tail -n 40 "$LOG_DIR/donor-test.log" | sed 's/^/      | /'
fi

if grep -qE '^test .*embedded_catalogue_is_the_committed_file \.\.\. ok$' "$LOG_DIR/donor-test.log"; then
    pass "the embedded-vs-file test passes (embedded text == committed file, 26 actions)"
else
    fail "the embedded-vs-file test did not pass"
fi

executed="$(awk '
    /Doc-tests / { in_doc = 1 }
    /Running /   { in_doc = 0 }
    /^test result:/ && !in_doc {
        for (i = 1; i <= NF; i++) if ($i == "passed;") { s += $(i - 1); break }
    }
    END { print s + 0 }
' "$LOG_DIR/donor-test.log")"
if [ "$executed" = "$EXPECTED_SOURCE_TESTS" ]; then
    pass "executed donor tests ($executed) == $EXPECTED_SOURCE_TESTS"
else
    fail "executed donor tests = $executed, expected $EXPECTED_SOURCE_TESTS"
fi

if cargo build --workspace >"$LOG_DIR/build.log" 2>&1; then
    pass "cargo build --workspace"
else
    fail "cargo build --workspace failed:"
    tail -n 30 "$LOG_DIR/build.log" | sed 's/^/      | /'
fi
if grep -q '^warning:' "$LOG_DIR/build.log"; then
    fail "cargo build --workspace emitted warnings:"
    grep -A2 '^warning:' "$LOG_DIR/build.log" | sed 's/^/      | /'
else
    pass "cargo build --workspace emitted no warnings"
fi

if cargo test --workspace >"$LOG_DIR/ws-test.log" 2>&1; then
    pass "cargo test --workspace"
else
    fail "cargo test --workspace failed:"
    tail -n 40 "$LOG_DIR/ws-test.log" | sed 's/^/      | /'
fi
if grep -q '^warning:' "$LOG_DIR/ws-test.log"; then
    fail "cargo test --workspace emitted warnings:"
    grep -A2 '^warning:' "$LOG_DIR/ws-test.log" | sed 's/^/      | /'
else
    pass "cargo test --workspace emitted no warnings"
fi

# ---------------------------------------------------- 16. the adjusted ratchets
header "16. Every adjusted historical ratchet names Remich #9 / Phase 3 Step 1"

adjusted_bad=""
for f in $ADJUSTED_CHECKERS; do
    if git diff --quiet "$PLAN_MERGE" -- "$f" 2>/dev/null; then
        adjusted_bad="$adjusted_bad      | not adjusted although its ratchets moved: $f
"
        continue
    fi
    if grep -qF 'Remich' "$f" && grep -qF '#9' "$f" && grep -qF 'Phase 3 Step 1' "$f"; then
        pass "$f is adjusted and names Remich #9 / Phase 3 Step 1"
    else
        adjusted_bad="$adjusted_bad      | adjusted without naming the issue: $f
"
    fi
done
if [ -z "$adjusted_bad" ]; then
    pass "all seven historical ratchets were adjusted with a comment naming the issue"
else
    fail "a historical ratchet was not adjusted, or was adjusted without naming the issue:"
    printf '%s' "$adjusted_bad"
fi

other_adjusted=""
for f in $FROZEN_CHECKERS; do
    if ! git diff --quiet "$PLAN_MERGE" -- "$f" 2>/dev/null; then
        other_adjusted="$other_adjusted      | $f
"
    fi
done
if [ -z "$other_adjusted" ]; then
    pass "no checker outside the authorized set was touched ($FROZEN_CHECKERS stay frozen)"
else
    fail "a checker outside the authorized set changed:"
    printf '%s' "$other_adjusted"
fi

# Every exception added to the seven ratchets must name a file: a wildcard
# (crates/anvil_sim/**) or a bare directory would silence unrelated drift,
# which is exactly what issue #9 does not authorize.
added="$(git diff -U0 "$PLAN_MERGE" -- $ADJUSTED_CHECKERS 2>/dev/null \
    | grep -E '^\+' | grep -v '^+++' || true)"
if [ -z "$added" ]; then
    fail "no added lines were parsed from the ratchet diff — the comparison is broken"
else
    if printf '%s\n' "$added" | grep -qE '\*\*|[A-Za-z0-9._-]/[A-Za-z0-9._-]*\*'; then
        fail "a path wildcard (a double star, or a star after a slash) was added to a historical ratchet:"
        printf '%s\n' "$added" | grep -E '\*\*|[A-Za-z0-9._-]/[A-Za-z0-9._-]*\*' \
            | sed 's/^/      | /'
    else
        pass "no path wildcard was added to any historical ratchet"
    fi

    # Each -e argument of every added exclusion must be an exact path (or a
    # variable holding one) — never a directory such as crates/anvil_sim.
    bad_args="$(printf '%s\n' "$added" | grep -oE -- '-e [^ |&()]+' \
        | sed 's/^-e //' | tr -d '"' \
        | grep -vE '^\$' | grep -vE '\.[A-Za-z0-9]+$' || true)"
    if [ -z "$bad_args" ]; then
        pass "every exclusion added to a historical ratchet names an exact file, not a directory"
    else
        fail "an exclusion added to a historical ratchet does not name an exact file:"
        printf '%s\n' "$bad_args" | sed 's/^/      | /'
    fi
fi

if git diff --quiet "$PLAN_FREEZE" -- "$PLAN_DOC" 2>/dev/null; then
    pass "docs/PLAN.md is byte-identical to the lead's docs-only Phase 3 Step 2 re-scope"
else
    fail "docs/PLAN.md was rewritten since the lead's Phase 3 Step 2 re-scope $PLAN_FREEZE"
fi

# ------------------------------------- 17. the previous acceptance chain is green
header "17. The Phase 2 Step 4 acceptance (the previous chain) is green"

if bash "$STEP4_CHECKER" >"$LOG_DIR/step4.log" 2>&1; then
    pass "bash $STEP4_CHECKER exits 0"
    tail -n 3 "$LOG_DIR/step4.log" | sed 's/^/      | /'
else
    fail "bash $STEP4_CHECKER failed:"
    grep '^FAIL' "$LOG_DIR/step4.log" | sed 's/^/      | /'
    tail -n 40 "$LOG_DIR/step4.log" | sed 's/^/      | /'
fi

# ------------------------------------------------- 18-19. the normal real day
header "18-19. The normal pinned-Godot day succeeds with the canonical trace"

DAY_TRACE="$LOG_DIR/normal-day.jsonl"
DAY_LOG="$LOG_DIR/normal-day.log"
bash tools/run_day.sh "$DAY_TRACE" 1 >"$DAY_LOG" 2>&1
day_rc=$?
if [ "$day_rc" -eq 0 ]; then
    pass "bash tools/run_day.sh <trace> 1 exits 0"
else
    fail "the day run exited $day_rc:"
    tail -n 30 "$DAY_LOG" | sed 's/^/      | /'
fi
for marker in REMICH_SCORER_OK REMICH_DAY_OK; do
    if grep -qF "$marker" "$DAY_LOG" 2>/dev/null; then
        pass "$marker present in the normal day run"
    else
        fail "$marker absent in the normal day run"
    fi
done
if [ -s "$DAY_TRACE" ]; then
    day_sha="$(sha256sum "$DAY_TRACE" | cut -d' ' -f1)"
    if [ "$day_sha" = "$CANONICAL_DAY_SHA" ]; then
        pass "the normal day trace SHA-256 is the canonical $CANONICAL_DAY_SHA"
    else
        fail "the normal day trace SHA-256 is '$day_sha', expected $CANONICAL_DAY_SHA"
    fi
else
    fail "the normal day run wrote no trace"
fi

# -------------------------------------------- 20-23. the relocation proof runs
header "20-23. The relocation proof builds first, moves, and never rebuilds"

if [ -f "$RELOCATION_PROOF" ]; then
    pass "$RELOCATION_PROOF exists"
else
    fail "$RELOCATION_PROOF is missing"
fi

# Structural: after the move marker, the proof script must contain no cargo
# build/test/check/run invocation at all. The pattern anchors the marker line
# itself (`# ====… THE MOVE: …`), so prose that merely names it — the comment
# above the single pre-move build, for instance — cannot be mistaken for it.
move_line="$(grep -nE '^# =+ THE MOVE' "$RELOCATION_PROOF" 2>/dev/null | head -n 1 | cut -d: -f1)"
if [ -n "$move_line" ]; then
    after_move="$(tail -n +"$move_line" "$RELOCATION_PROOF")"
    late_cargo="$(printf '%s\n' "$after_move" \
        | grep -nE 'cargo[[:space:]]+(build|test|check|run|clean)' || true)"
    if [ -z "$late_cargo" ]; then
        pass "the proof script invokes no cargo command after the move (structural)"
    else
        fail "the proof script invokes cargo after the move:"
        printf '%s\n' "$late_cargo" | sed 's/^/      | /'
    fi
else
    fail "the proof script has no move marker to audit"
fi

PROOF_LOG="$LOG_DIR/relocation.log"
if bash "$RELOCATION_PROOF" >"$PROOF_LOG" 2>&1; then
    pass "bash $RELOCATION_PROOF exits 0"
else
    fail "bash $RELOCATION_PROOF failed:"
    tail -n 40 "$PROOF_LOG" | sed 's/^/      | /'
fi

for needle in \
    "relocation-proof: old build checkout: absent" \
    "relocation-proof: new checkout: present" \
    "relocation-proof: cargo after move: none" \
    "relocation-proof: REMICH_SCORER_OK: present" \
    "relocation-proof: REMICH_DAY_OK: present" \
    "baked runtime asset path of the pre-#9 implementation: absent"
do
    if grep -qF "$needle" "$PROOF_LOG" 2>/dev/null; then
        pass "relocation proof: ${needle#relocation-proof: }"
    else
        fail "relocation proof does not report: $needle"
    fi
done

relocated_sha="$(sed -n 's/^relocation-proof: relocated day SHA-256: //p' "$PROOF_LOG" | head -n 1)"
if [ "$relocated_sha" = "$CANONICAL_DAY_SHA" ]; then
    pass "the relocated day SHA-256 equals the canonical trace hash"
else
    fail "the relocated day SHA-256 is '$relocated_sha', expected $CANONICAL_DAY_SHA"
fi

# ------------------------------------------------- 24-27. boundaries and state
header "24-27. The vault is untouched, no other repository changed, nothing stray"

if git -C "$VAULT" rev-parse HEAD 2>/dev/null | grep -q "^$VAULT_COMMIT"; then
    pass "the donor vault HEAD is still $VAULT_COMMIT"
else
    fail "the donor vault HEAD is no longer $VAULT_COMMIT"
fi
vault_status="$(git -C "$VAULT" status --porcelain 2>/dev/null)"
if [ -z "$vault_status" ]; then
    pass "the donor vault working tree is clean — read-only access held"
else
    fail "the donor vault working tree is dirty:"
    printf '%s\n' "$vault_status" | head -n 5 | sed 's/^/      | /'
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
else
    fail "this repository references another repository by path:"
    printf '%s' "$unexpected" | sed 's/^/      | /'
fi

generated="$(git ls-files \
    | grep -E '(^|/)(target|\.godot|staging)(/|$)|\.so$|\.dylib$|\.dll$|\.bundle$|\.tmp$|\.jsonl$' \
    || true)"
if [ -z "$generated" ]; then
    pass "no generated build, relocation, import or trace state is tracked"
else
    fail "generated state is tracked by git:"
    printf '%s\n' "$generated" | sed 's/^/      | /'
fi

stray="$(git status --porcelain 2>/dev/null)"
if [ -z "$stray" ]; then
    pass "the worktree is clean — no modified, staged or untracked file remains"
else
    fail "the worktree is not clean at the acceptance head:"
    printf '%s\n' "$stray" | sed 's/^/      | /'
fi

# ------------------------------------------------------------------ summary
printf '\n========================================\n'
if [ "$failures" -eq 0 ]; then
    printf 'PASS  Phase 3 Step 1 — the embedded catalogue\n'
    printf '========================================\n'
    exit 0
fi
printf 'FAIL  Phase 3 Step 1 — %d check(s) failed\n' "$failures"
printf '========================================\n'
exit 1
