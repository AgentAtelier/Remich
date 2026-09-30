#!/usr/bin/env bash
# Phase 1, Step 3 acceptance check — "anvil's needs and actions, taken"
# (docs/PLAN.md §4, step 3).
#
# One command, from anywhere:
#
#     bash tools/check_phase1_step3.sh
#
# It fails if the Step 3 import loses its provenance, its engine-free firewall,
# its donor tests or its recorded adaptations. It runs the Step 2 acceptance
# first (which runs Step 1), so the repository-shape and bridge baselines
# cannot regress underneath a green Step 3.
#
# Checks:
#
#   1. the Step 2 acceptance is still green;
#   2. docs/PLAN.md §3 carries the corrected donor paragraph;
#   3. the central provenance record is tracked and states the donor identity;
#   4. the machine-readable inventory block is well-formed;
#   5. the inventory is complete — every tracked file under the taken dirs;
#   6. canonical provenance per entry, donor paths exist, the vault untouched;
#   7. byte verification of every copied file (unchanged/adapted/excerpt/data);
#   8. the kimi_npc_mod.rs defect: not taken → not present, and documented;
#   9. the engine-free firewall (source grep + cargo tree), godot only in
#      remich_gdext;
#  10. the donor tests run green and the executed test count equals the source
#      `#[test]` count;
#  11. the workspace builds without warnings and tests;
#  12. the Step 2 bridge artifacts are still committed at their committed
#      value;
#  13. no generated state, staging or bundle metadata committed; worktree
#      clean;
#  14. no timing probe left behind, and the timings are recorded.

set -uo pipefail

REPO_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)" || exit 1
cd "$REPO_ROOT" || exit 1

PROVENANCE_DOC="docs/anvil-import-phase1-step3.md"
PLAN_DOC="docs/PLAN.md"
VAULT="/home/mrg/Documents/Project/buggy-vault"
VAULT_COMMIT="24181142c693be37f90a6a667a6dc493425cd832"
ANVIL_MAIN="97c8fdbd7ff85779f33456fd7c444657f8d90b36"
PROVENANCE_FORM="buggy-vault@24181142 repos/anvil/source/<path>"
DATA_SHA="166104ba90e30446adfb8d15ec6e242a52567c979bccb274a7011296b163dba5"
SENTINEL="remich-timing-probe"
# Every `#[test]` in the two donor crates: 181 unit (anvil_sim 131 +
# anvil_core 50) + 2 carried integration tests. Frozen for this step so that
# deleting tests from the source cannot pass by matching a lowered count.
EXPECTED_SOURCE_TESTS=183
BRIDGE_PROBE_SOURCE="crates/remich_gdext/src/lib.rs"
COMMITTED_BRIDGE_VALUE="remich-bridge-v1"
TAKEN_DIRS=(crates/anvil_sim crates/anvil_core assets)

LOG_DIR="$(mktemp -d "${TMPDIR:-/tmp}/remich-p1s3.XXXXXX")" || exit 1
trap 'rm -rf "$LOG_DIR"' EXIT

failures=0
pass() { printf 'ok    %s\n' "$1"; }
fail() { printf 'FAIL  %s\n' "$1"; failures=$((failures + 1)); }
note() { printf '      %s\n' "$1"; }
header() { printf '\n== %s ==\n' "$1"; }

# --------------------------------------------------- 1. Step 2 still green
header "1. The Step 2 acceptance is still green"

if bash tools/check_phase1_step2.sh >"$LOG_DIR/step2.log" 2>&1; then
    pass "bash tools/check_phase1_step2.sh exits 0"
    tail -n 3 "$LOG_DIR/step2.log" | sed 's/^/      | /'
else
    fail "bash tools/check_phase1_step2.sh failed:"
    grep '^FAIL' "$LOG_DIR/step2.log" | sed 's/^/      | /'
    tail -n 60 "$LOG_DIR/step2.log" | sed 's/^/      | /'
fi

# --------------------------------------------- 2. PLAN.md §3 donor paragraph
header "2. docs/PLAN.md §3 carries the corrected donor paragraph"

if [ -f "$PLAN_DOC" ]; then
    for needle in \
        "$VAULT_COMMIT" \
        "$ANVIL_MAIN" \
        "$PROVENANCE_FORM" \
        "$PROVENANCE_DOC" \
        "no upstream fetch" \
        "Step 3 did not take" \
        "no repair was performed" \
        "anvil's needs and actions, taken"
    do
        if grep -qF "$needle" "$PLAN_DOC"; then
            pass "PLAN records: $needle"
        else
            fail "PLAN does not record: $needle"
        fi
    done

    # The defect being corrected: `97c8fdbd` was presented as a commit of the
    # vault repository ("(main `97c8fdbd`)" next to the vault path), and the
    # old short provenance form `anvil@97c8fdbd` was used.
    if grep -qF '(main `97c8fdbd`)' "$PLAN_DOC"; then
        fail "PLAN still describes 97c8fdbd as the vault checkout's main"
    else
        pass "PLAN no longer describes 97c8fdbd as the vault checkout's main"
    fi

    if grep -qF 'anvil@97c8fdbd' "$PLAN_DOC"; then
        fail "PLAN still uses the old provenance form anvil@97c8fdbd"
    else
        pass "PLAN no longer uses the old provenance form anvil@97c8fdbd"
    fi

    # A line that pairs the vault path with the preserved anvil commit must
    # also carry the vault commit — otherwise the two commits are conflated.
    conflation="$(awk -v main="$ANVIL_MAIN" -v vault="$VAULT_COMMIT" '
        /buggy-vault/ && index($0, main) && !index($0, vault) { print NR": "$0 }
    ' "$PLAN_DOC")"
    if [ -n "$conflation" ]; then
        fail "PLAN pairs buggy-vault with the preserved anvil commit without the vault commit:"
        printf '%s\n' "$conflation" | sed 's/^/      | /'
    else
        pass "PLAN never pairs the vault path with the preserved anvil commit alone"
    fi
else
    fail "$PLAN_DOC is missing"
fi

# --------------------------------------- 3. provenance record + donor identity
header "3. The central provenance record exists and states the donor identity"

if [ -f "$PROVENANCE_DOC" ]; then
    pass "$PROVENANCE_DOC exists"
else
    fail "$PROVENANCE_DOC is missing"
fi

if git ls-files --error-unmatch "$PROVENANCE_DOC" >/dev/null 2>&1; then
    pass "$PROVENANCE_DOC is tracked by git"
else
    fail "$PROVENANCE_DOC is not tracked by git"
fi

if [ -f "$PROVENANCE_DOC" ]; then
    for needle in \
        "buggy-vault/repos/anvil/source" \
        "$VAULT_COMMIT" \
        "$ANVIL_MAIN" \
        "$PROVENANCE_FORM" \
        "PRESERVATION-RECORD.md" \
        "read-only" \
        "No fetch, clone or ls-remote" \
        "were not modified" \
        "kimi_npc_mod.rs" \
        "provenance exception"
    do
        if grep -qF "$needle" "$PROVENANCE_DOC"; then
            pass "record states: $needle"
        else
            fail "record does not state: $needle"
        fi
    done
fi

# ------------------------------------------- 4. inventory block well-formed
header "4. The machine-readable inventory block is well-formed"

if [ -f "$PROVENANCE_DOC" ]; then
    begin_count="$(grep -c '^<!-- step3-inventory:begin -->$' "$PROVENANCE_DOC" || true)"
    end_count="$(grep -c '^<!-- step3-inventory:end -->$' "$PROVENANCE_DOC" || true)"
    if [ "$begin_count" = "1" ] && [ "$end_count" = "1" ]; then
        pass "exactly one step3-inventory begin/end marker pair"
    else
        fail "inventory markers: begin=$begin_count end=$end_count (expected 1 each)"
    fi

    sed -n '/^<!-- step3-inventory:begin -->$/,/^<!-- step3-inventory:end -->$/p' \
        "$PROVENANCE_DOC" | sed '1d;$d' | grep -v '^$' >"$LOG_DIR/inventory.raw"
    awk -F ' :: ' 'NF >= 4 { print $1 "\t" $2 "\t" $3 }' \
        "$LOG_DIR/inventory.raw" >"$LOG_DIR/inventory.tsv"

    raw_lines="$(wc -l <"$LOG_DIR/inventory.raw")"
    tsv_lines="$(wc -l <"$LOG_DIR/inventory.tsv")"
    if [ "$raw_lines" -gt 0 ] && [ "$raw_lines" = "$tsv_lines" ]; then
        pass "$raw_lines inventory entries, all shaped 'path :: provenance :: status :: why'"
    else
        fail "malformed inventory lines: raw=$raw_lines parsed=$tsv_lines"
        grep -vxFf <(cut -f1 "$LOG_DIR/inventory.tsv" 2>/dev/null) \
            "$LOG_DIR/inventory.raw" 2>/dev/null | sed 's/^/      | /' || true
    fi

    bad_status="$(cut -f3 "$LOG_DIR/inventory.tsv" \
        | grep -vx 'unchanged\|adapted\|new\|excerpt\|data' || true)"
    if [ -z "$bad_status" ]; then
        pass "every status is one of unchanged/adapted/new/excerpt/data"
    else
        fail "unknown inventory status(es):"
        printf '%s\n' "$bad_status" | sed 's/^/      | /'
    fi

    dups="$(cut -f1 "$LOG_DIR/inventory.tsv" | sort | uniq -d)"
    if [ -z "$dups" ]; then
        pass "no destination path is listed twice"
    else
        fail "destination path(s) listed more than once:"
        printf '%s\n' "$dups" | sed 's/^/      | /'
    fi
else
    fail "cannot check the inventory: $PROVENANCE_DOC is missing"
fi

# --------------------------------------------- 5. inventory completeness
header "5. The inventory covers every tracked file in the taken directories"

if [ -s "$LOG_DIR/inventory.tsv" ]; then
    missing_from_inventory=0
    for dir in "${TAKEN_DIRS[@]}"; do
        if [ ! -d "$dir" ]; then
            fail "expected taken directory $dir does not exist"
            continue
        fi
        while IFS= read -r f; do
            if ! grep -qxF "$f" <(cut -f1 "$LOG_DIR/inventory.tsv"); then
                fail "tracked file is not in the inventory: $f"
                missing_from_inventory=$((missing_from_inventory + 1))
            fi
        done < <(git ls-files -- "$dir")
    done
    if [ "$missing_from_inventory" -eq 0 ]; then
        pass "every tracked file under ${TAKEN_DIRS[*]} is inventoried"
    fi

    bad_dest=0
    while IFS=$'\t' read -r p _prov _st; do
        if [ ! -f "$p" ]; then
            fail "inventoried file does not exist: $p"
            bad_dest=$((bad_dest + 1))
        elif ! git ls-files --error-unmatch "$p" >/dev/null 2>&1; then
            fail "inventoried file is not tracked by git: $p"
            bad_dest=$((bad_dest + 1))
        fi
    done <"$LOG_DIR/inventory.tsv"
    if [ "$bad_dest" -eq 0 ]; then
        pass "every inventoried destination exists and is tracked"
    fi

    # Frozen inventory shape for this step: 34 entries = 27 unchanged + 4
    # adapted + 1 new + 1 excerpt + 1 data (docs/anvil-import §4 "Counts").
    counts="$(cut -f3 "$LOG_DIR/inventory.tsv" | sort | uniq -c \
        | awk '{ printf "%s=%s ", $2, $1 }')"
    expected_counts="adapted=4 data=1 excerpt=1 new=1 unchanged=27 "
    if [ "$counts" = "$expected_counts" ]; then
        pass "inventory status counts match the recorded 34 entries: $counts"
    else
        fail "inventory status counts are '$counts', expected '$expected_counts'"
    fi
else
    fail "no parsed inventory to check"
fi

# --------------------------- 6. canonical provenance + donor/vault integrity
header "6. Canonical provenance, donor paths exist, the vault is untouched"

if git -C "$VAULT" rev-parse HEAD 2>/dev/null | grep -q "^$VAULT_COMMIT"; then
    pass "vault HEAD is still $VAULT_COMMIT"
else
    fail "vault HEAD is no longer $VAULT_COMMIT (the donor moved)"
fi

vault_status="$(git -C "$VAULT" status --porcelain 2>/dev/null)"
if [ -z "$vault_status" ]; then
    pass "vault working tree is clean (0 entries) — the donor was not mutated"
else
    fail "vault working tree is dirty — the donor was mutated:"
    printf '%s\n' "$vault_status" | sed 's/^/      | /'
fi

if git -C "$VAULT" show "$VAULT_COMMIT:repos/anvil/PRESERVATION-RECORD.md" 2>/dev/null \
        | grep -qF "$ANVIL_MAIN"; then
    pass "the vault's preservation record states the preserved anvil main $ANVIL_MAIN"
else
    fail "the vault's preservation record does not state anvil main $ANVIL_MAIN"
fi

if [ -s "$LOG_DIR/inventory.tsv" ]; then
    bad_prov=0
    while IFS=$'\t' read -r p prov st; do
        case "$st" in
            unchanged|adapted)
                prefix="buggy-vault@24181142 repos/anvil/source/"
                if [[ "$prov" != "$prefix"* ]]; then
                    fail "non-canonical provenance for $st entry: $p → $prov"
                    bad_prov=$((bad_prov + 1))
                    continue
                fi
                # The donor path must mirror the destination inside the
                # source tree; the vault path used with `git show` below is
                # that relative path prefixed with repos/anvil/source/.
                rel="${prov#"$prefix"}"
                if [ "$rel" != "$p" ]; then
                    fail "donor path does not mirror destination for $p → $rel"
                    bad_prov=$((bad_prov + 1))
                    continue
                fi
                donor_path="repos/anvil/source/$rel"
                ;;
            excerpt|new)
                if [[ "$prov" == *"buggy-vault@24181142 repos/anvil/source/"* ]]; then
                    donor_path="$(sed -n 's|.*buggy-vault@[0-9a-f]* \(repos/anvil/source/[^ ]*\).*|\1|p' <<<"$prov")"
                    if [ -z "$donor_path" ]; then
                        fail "cannot parse the donor path from the $st entry: $p"
                        bad_prov=$((bad_prov + 1))
                        continue
                    fi
                elif [[ "$prov" == *"buggy-vault@"* ]]; then
                    fail "provenance names buggy-vault but not at the canonical form: $p"
                    bad_prov=$((bad_prov + 1))
                    continue
                else
                    continue # genuinely new file, no donor path
                fi
                ;;
            data)
                if [[ "$prov" != "anvil-bundle@97c8fdbd "* ]]; then
                    fail "data entry lacks the documented bundle provenance: $p → $prov"
                    bad_prov=$((bad_prov + 1))
                fi
                donor_path=""
                ;;
            *)
                continue
                ;;
        esac
        if [ -n "${donor_path:-}" ]; then
            if git -C "$VAULT" cat-file -e "$VAULT_COMMIT:$donor_path" 2>/dev/null; then
                :
            else
                fail "donor path does not exist at $VAULT_COMMIT: $donor_path (for $p)"
                bad_prov=$((bad_prov + 1))
            fi
        fi
    done <"$LOG_DIR/inventory.tsv"
    if [ "$bad_prov" -eq 0 ]; then
        pass "every entry's provenance is canonical, mirrors the donor tree and resolves in the vault"
    fi
fi

# ------------------------------------------------- 7. byte verification
header "7. Byte verification: unchanged / adapted / excerpt / data"

if [ -s "$LOG_DIR/inventory.tsv" ]; then
    unchanged_ok=0
    unchanged_bad=0
    while IFS=$'\t' read -r p prov st; do
        [ "$st" = "unchanged" ] || continue
        donor_path="${prov#buggy-vault@24181142 }"
        donor_sha="$(git -C "$VAULT" show "$VAULT_COMMIT:$donor_path" 2>/dev/null | sha256sum | cut -d' ' -f1)"
        dest_sha="$(sha256sum "$p" 2>/dev/null | cut -d' ' -f1)"
        if [ -n "$donor_sha" ] && [ "$donor_sha" = "$dest_sha" ]; then
            unchanged_ok=$((unchanged_ok + 1))
        else
            fail "byte mismatch against the vault for unchanged entry: $p"
            unchanged_bad=$((unchanged_bad + 1))
        fi
    done <"$LOG_DIR/inventory.tsv"
    if [ "$unchanged_ok" -eq 27 ] && [ "$unchanged_bad" -eq 0 ]; then
        pass "all 27 unchanged entries are byte-identical to the vault (sha256 vs git show $VAULT_COMMIT)"
    fi

    # An adapted .rs file must be the donor file minus whole lines only —
    # a pure deletion, as §5 claims. (The two adapted Cargo.toml files have
    # documented line edits and are covered by the §5 listing check below.)
    while IFS=$'\t' read -r p prov st; do
        [ "$st" = "adapted" ] || continue
        [[ "$p" == *.rs ]] || continue
        donor_path="${prov#buggy-vault@24181142 }"
        if git -C "$VAULT" show "$VAULT_COMMIT:$donor_path" 2>/dev/null | awk '
            NR == FNR { donor[FNR] = $0; dn = FNR; next }
            {
                i = last + 1
                while (i <= dn && donor[i] != $0) i++
                if (i > dn) { bad = 1; exit }
                last = i
            }
            END { if (bad) exit 1 }
        ' - "$p"; then
            pass "adapted file is a pure line-deletion of its donor: $p"
        else
            fail "adapted file is not a pure line-deletion of its donor (a byte outside the deletions changed): $p"
        fi
    done <"$LOG_DIR/inventory.tsv"

    # Excerpt entries: every claimed donor line range must appear verbatim in
    # the destination file.
    while IFS=$'\t' read -r p prov st; do
        ranges="$(grep -oE 'lines [0-9]+-[0-9]+' <<<"$prov" || true)"
        [ -n "$ranges" ] || continue
        donor_path="$(sed -n 's|.*buggy-vault@[0-9a-f]* \(repos/anvil/source/[^ ]*\).*|\1|p' <<<"$prov")"
        if [ -z "$donor_path" ]; then
            fail "claimed line ranges but no parseable donor path: $p"
            continue
        fi
        dest_content="$(<"$p")"
        while IFS= read -r range; do
            a="${range#lines }"
            a="${a%%-*}"
            b="${range##*-}"
            slice="$(git -C "$VAULT" show "$VAULT_COMMIT:$donor_path" 2>/dev/null | sed -n "${a},${b}p")"
            if [ -n "$slice" ] && [[ "$dest_content" == *"$slice"* ]]; then
                pass "excerpt $donor_path lines $a-$b is contained verbatim in $p"
            else
                fail "excerpt $donor_path lines $a-$b is NOT contained verbatim in $p"
            fi
        done <<<"$ranges"
    done <"$LOG_DIR/inventory.tsv"

    # The data entry: sha256 of the committed file must equal the hash
    # recorded in the provenance doc.
    if [ -f assets/sim/actions.json ]; then
        data_sha="$(sha256sum assets/sim/actions.json | cut -d' ' -f1)"
        if [ "$data_sha" = "$DATA_SHA" ] && grep -qF "$DATA_SHA" "$PROVENANCE_DOC"; then
            pass "assets/sim/actions.json sha256 matches the recorded $DATA_SHA"
        else
            fail "assets/sim/actions.json sha256 is '$data_sha', recorded '$DATA_SHA'"
        fi
        actions_count="$(grep -c '"id"' assets/sim/actions.json || true)"
        if [ "$actions_count" = "26" ]; then
            pass "the catalogue carries the 26 actions the donor tests assert"
        else
            fail "the catalogue carries $actions_count actions, expected 26"
        fi
    else
        fail "assets/sim/actions.json is missing"
    fi

    # Every adaptation listed in §5 must name the file it adapts.
    sed -n '/^## 5\./,/^## 6\./p' "$PROVENANCE_DOC" >"$LOG_DIR/adaptations.md"
    if [ -s "$LOG_DIR/adaptations.md" ]; then
        while IFS=$'\t' read -r p _prov st; do
            [ "$st" = "adapted" ] || continue
            if grep -qF "$p" "$LOG_DIR/adaptations.md"; then
                pass "§5 lists the adaptation of $p"
            else
                fail "§5 does not list the adaptation of $p"
            fi
        done <"$LOG_DIR/inventory.tsv"
        if grep -qF 'Cargo.toml` (workspace root' "$LOG_DIR/adaptations.md"; then
            pass "§5 lists the workspace-root Cargo.toml wiring"
        else
            fail "§5 does not list the workspace-root Cargo.toml wiring"
        fi
    else
        fail "the provenance record has no §5 adaptation list"
    fi
else
    fail "no parsed inventory to verify"
fi

# ------------------------------------------- 8. kimi_npc_mod.rs conditional
header "8. The kimi_npc_mod.rs defect: not taken → not present, and documented"

if grep -qF 'system/npc' "$LOG_DIR/inventory.tsv" 2>/dev/null; then
    # The conditional branch: if a later change takes system/npc, the module
    # root must be restored to mod.rs and the repair recorded.
    if [ -f crates/anvil_sim/src/system/npc/mod.rs ]; then
        pass "system/npc is taken and its module root is present as mod.rs"
    else
        fail "system/npc is taken but crates/anvil_sim/src/system/npc/mod.rs is missing"
    fi
    if [ -f crates/anvil_sim/src/system/npc/kimi_npc_mod.rs ]; then
        fail "kimi_npc_mod.rs was copied — the module-root repair was not performed"
    else
        pass "kimi_npc_mod.rs was not copied"
    fi
else
    pass "the inventory takes no system/npc path (step scope ruling §2.2)"
    if [ -d crates/anvil_sim/src/system ]; then
        fail "crates/anvil_sim/src/system exists although system was not taken"
    else
        pass "no system/ tree exists under crates/anvil_sim/src"
    fi
fi

kimi_tracked="$(git ls-files | grep -F 'kimi_npc_mod.rs' || true)"
if [ -z "$kimi_tracked" ]; then
    pass "no kimi_npc_mod.rs file is tracked in this repository"
else
    fail "kimi_npc_mod.rs is tracked in this repository:"
    printf '%s\n' "$kimi_tracked" | sed 's/^/      | /'
fi

if grep -qF 'no filename' "$PROVENANCE_DOC" && grep -qF 'restoration was performed' "$PROVENANCE_DOC" \
        && grep -qF 'Observed, unfixed' "$PROVENANCE_DOC"; then
    pass "the record states the defect was observed, unfixed, and not repaired this step"
else
    fail "the record does not document the untouched kimi_npc_mod.rs defect"
fi

# ------------------------------------------------- 9. engine-free firewall
header "9. The engine-free firewall holds and godot stays in remich_gdext"

if grep -rqiE 'godot|gdext' crates/anvil_sim crates/anvil_core; then
    fail "engine terms found in the imported crates:"
    grep -rniE 'godot|gdext' crates/anvil_sim crates/anvil_core | sed 's/^/      | /'
else
    pass "no 'godot'/'gdext' anywhere in crates/anvil_sim or crates/anvil_core"
fi

for pkg in anvil_sim anvil_core; do
    if cargo tree -p "$pkg" --edges normal,build >"$LOG_DIR/tree-$pkg.txt" 2>/dev/null; then
        if grep -qiE 'godot|gdext' "$LOG_DIR/tree-$pkg.txt"; then
            fail "cargo tree -p $pkg shows an engine crate (the firewall is broken):"
            grep -niE 'godot|gdext' "$LOG_DIR/tree-$pkg.txt" | sed 's/^/      | /'
        else
            pass "cargo tree -p $pkg shows no engine crate"
        fi
    else
        fail "cargo tree -p $pkg failed"
    fi
done

if [ -s "$LOG_DIR/tree-anvil_sim.txt" ] && grep -qE '(^|[[:space:]])anvil_core v[0-9]' "$LOG_DIR/tree-anvil_sim.txt"; then
    pass "anvil_sim resolves its narrow dependency anvil_core"
else
    fail "anvil_sim does not resolve anvil_core"
fi

godot_tomls="$(git ls-files '*.toml' | xargs -r grep -lE '^godot[[:space:]]*=' 2>/dev/null || true)"
if [ "$godot_tomls" = "crates/remich_gdext/Cargo.toml" ]; then
    pass "the godot dependency is declared only by crates/remich_gdext/Cargo.toml"
else
    fail "the godot dependency is declared by: ${godot_tomls:-<nothing>}"
fi

# ------------------------------------------------- 10. donor tests
header "10. The donor tests run green and the executed count matches the source"

if cargo test -p anvil_core -p anvil_sim >"$LOG_DIR/donor-test.log" 2>&1; then
    pass "cargo test -p anvil_core -p anvil_sim"
else
    fail "cargo test -p anvil_core -p anvil_sim failed:"
    tail -n 40 "$LOG_DIR/donor-test.log" | sed 's/^/      | /'
fi

# Non-doctest results only: every `test result:` line that follows a
# `Running …` section (unit + integration), not a `Doc-tests …` section.
# Cargo indents both section headers, so the patterns must not anchor at ^.
executed="$(awk '
    /Doc-tests / { in_doc = 1 }
    /Running /   { in_doc = 0 }
    /^test result:/ && !in_doc {
        for (i = 1; i <= NF; i++) if ($i == "passed;") { s += $(i - 1); break }
    }
    END { print s + 0 }
' "$LOG_DIR/donor-test.log")"
source_tests="$(grep -r --include='*.rs' -o '#\[test\]' crates/anvil_sim crates/anvil_core 2>/dev/null | wc -l)"

if [ "$executed" = "$EXPECTED_SOURCE_TESTS" ] && [ "$source_tests" = "$EXPECTED_SOURCE_TESTS" ]; then
    pass "executed tests ($executed) == source #[test] occurrences ($source_tests) == $EXPECTED_SOURCE_TESTS"
else
    fail "test counts drifted: executed=$executed source=$source_tests expected=$EXPECTED_SOURCE_TESTS"
fi

bad_results="$(grep '^test result:' "$LOG_DIR/donor-test.log" | grep -v 'test result: ok\.' || true)"
if [ -z "$bad_results" ]; then
    pass "every test target reports ok"
else
    fail "a test target did not report ok:"
    printf '%s\n' "$bad_results" | sed 's/^/      | /'
fi

if grep -qF 'test result: ok. 2 passed; 0 failed; 1 ignored;' "$LOG_DIR/donor-test.log"; then
    pass "anvil_core doc-tests: 2 passed, 0 failed, 1 ignored (the donor's own ignore example in error.rs)"
else
    fail "anvil_core doc-tests are not '2 passed; 1 ignored'"
fi

# -------------------------------------------- 11. workspace build and tests
header "11. The workspace builds without warnings and tests"

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

if grep -qF 'crates/anvil_core' Cargo.toml && grep -qF 'crates/anvil_sim' Cargo.toml; then
    pass "the workspace root manifest still members both donor crates"
else
    fail "the workspace root manifest does not member both donor crates"
fi

if cargo test --workspace >"$LOG_DIR/ws-test.log" 2>&1; then
    pass "cargo test --workspace"
    grep -E '^test result:' "$LOG_DIR/ws-test.log" | sed 's/^/      | /'
else
    fail "cargo test --workspace failed:"
    tail -n 40 "$LOG_DIR/ws-test.log" | sed 's/^/      | /'
fi

# --------------------------------------------------- 12. the bridge intact
header "12. The Step 2 bridge artifacts are still committed at their value"

for f in godot/remich.gdextension godot/bridge_probe.gd godot/project.godot; do
    if git ls-files --error-unmatch "$f" >/dev/null 2>&1; then
        pass "$f is tracked by git"
    else
        fail "$f is not tracked by git — the bridge lost a committed artifact"
    fi
done

bridge_value="$(sed -n 's/^[[:space:]]*pub const BRIDGE_PROBE_VALUE: &str = "\([^"]*\)".*/\1/p' \
    "$BRIDGE_PROBE_SOURCE" 2>/dev/null)"
if [ "$bridge_value" = "$COMMITTED_BRIDGE_VALUE" ]; then
    pass "the bridge probe still holds its committed value ('$bridge_value')"
else
    fail "the bridge probe is '$bridge_value', expected '$COMMITTED_BRIDGE_VALUE'"
fi

# ------------------------------- 13. no generated/staging/bundle state, clean
header "13. No generated state, staging or bundle metadata is committed"

generated="$(git ls-files \
    | grep -E '(^|/)(target|\.godot|staging)(/|$)|\.so$|\.dylib$|\.dll$|\.bundle$|\.tmp$|remich-p1s3-staging' \
    || true)"
if [ -z "$generated" ]; then
    pass "no generated build/import state, staging directory or bundle file is tracked"
else
    fail "generated/staging/bundle paths are tracked by git:"
    printf '%s\n' "$generated" | sed 's/^/      | /'
fi

stray="$(git status --porcelain 2>/dev/null)"
if [ -z "$stray" ]; then
    pass "the worktree is clean — no modified, staged or untracked file remains"
else
    fail "the worktree is not clean at the acceptance head:"
    printf '%s\n' "$stray" | sed 's/^/      | /'
fi

# --------------------------------------------- 14. timing probe and timings
header "14. No timing probe remains and the timings are recorded"

# The checker names the sentinel in its own source; exclude it so the search
# means "anywhere except here", i.e. the probe itself never survives.
sentinel_files="$(git grep -lF "$SENTINEL" -- . ':(exclude)tools/check_phase1_step3.sh' 2>/dev/null || true)"
if [ -z "$sentinel_files" ]; then
    fail "the provenance record does not document the timing probe ('$SENTINEL' found nowhere)"
elif [ "$sentinel_files" = "$PROVENANCE_DOC" ]; then
    pass "the probe sentinel '$SENTINEL' appears only in the record that documents it"
else
    fail "the probe sentinel '$SENTINEL' is present in a tracked file other than $PROVENANCE_DOC:"
    printf '%s\n' "$sentinel_files" | sed 's/^/      | /'
fi

sed -n '/^## 10\. Build timings/,/^## /p' "$PROVENANCE_DOC" >"$LOG_DIR/timings.md"
if [ -s "$LOG_DIR/timings.md" ] \
        && grep -q 'Clean build' "$LOG_DIR/timings.md" \
        && grep -q 'probe' "$LOG_DIR/timings.md" \
        && grep -qF "$SENTINEL" "$LOG_DIR/timings.md" \
        && grep -qE '[0-9]+(\.[0-9]+)?[[:space:]]*s(\b|ec)' "$LOG_DIR/timings.md"; then
    pass "the record carries the clean-build and one-line-probe timings"
    grep -E '^\| ' "$LOG_DIR/timings.md" | sed 's/^/      | /'
else
    fail "the record has no complete §10 Build timings section (clean build + probe + seconds)"
fi

# ------------------------------------------------------------------ summary
printf '\n========================================\n'
if [ "$failures" -eq 0 ]; then
    printf 'PASS  Phase 1 Step 3 — anvil needs and actions taken\n'
    printf '========================================\n'
    exit 0
fi
printf 'FAIL  Phase 1 Step 3 — %d check(s) failed\n' "$failures"
printf '========================================\n'
exit 1
