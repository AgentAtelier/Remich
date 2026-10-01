#!/usr/bin/env bash
# Phase 3, Step 2 acceptance check — "soul primitives across the bridge"
# (docs/PLAN.md §4b, step 2; record: docs/remich-soul-primitives-phase3-step2.md).
#
# One command, from anywhere:
#
#     bash tools/check_phase3_step2.sh
#
# This step crosses no new behaviour into Remich. The pinned donor already
# computes a propagated influence for a given edge strength; what did not
# exist was any way to reach that from the engine. So the work is: take the
# donor's own edge-strength layer (settlement/connection.rs and the ids it is
# parameterised by), expose the donor's soul primitives through an
# engine-free facade and one binding class, and prove inside pinned Godot that
# the result is deterministic, equivalent to the donor, and never writes an
# influence into a soul.
#
# Requirements, as checks (46 in total):
#
#    1. the Phase 3 Step 1 acceptance (which transitively runs the whole
#       live chain) is green;
#    2. that run reports the Phase 2 Step 4 acceptance green;
#    3. the Phase 1 Step 3 donor/import acceptance is green, run directly;
#    4. docs/PLAN.md is byte-identical to the re-scope freeze;
#    5. the donor vault is clean at the pinned commit;
#   6-9. soul.rs, soul/axes.rs, settlement/connection.rs and
#       settlement/ids.rs are each byte-identical to the donor;
#   10. settlement/mod.rs keeps the donor's own doc comment and carries
#       exactly the three documented declaration lines, once each;
#   11. settlement/mod.rs keeps Phase 1's pruning and its skill module;
#   12. the provenance record carries a dated Phase 3 Step 2 section;
#   13. the record states all four test counts: 184, +0, +3, 187;
#   14. the inventory carries both new files with canonical provenance and
#       status `unchanged`;
#   15. the record states that system/npc stays untaken and that propagated
#       influence is not a receiver state update;
#   16. the engine-free core names no engine (cargo tree and sources);
#   17. the facade's own tests are green (7);
#   18. the name -> layer lookup carries no number;
#   19. propagation is the donor's weight() into the donor's propagate(),
#       with no application, blending or ordering of our own;
#   20. SOUL_BRIDGE_REV holds exactly the committed marker line;
#   21. exactly one binding class exists and its state is a plain soul only;
#   22. the six required methods exist on it;
#   23. the binding's bridge-revision test exists;
#   24. the gdext crate's tests are green;
#   25. the probe is a standalone SceneTree script and not an autoload;
#   26. the probe's three seeds equal the facade's fixture seeds;
#   27. the probe's three layers equal the donor's ConnectionLayer names;
#   28. the probe calls only the six methods of that class;
#   29. the probe reads no clock, pid or random source;
#   30. the probe asserts the soul is unchanged across the call and refuses
#       an unknown layer;
#   31. the staging script derives the expectation from the Rust source;
#   32. the runner uses the pinned engine, headless, via --script;
#   33. the derived expectation file and the traces are ignored;
#   34. a fresh normal run exits 0 with the class marker and no failure;
#   35. that run reports the propagation marker;
#   36. a second fresh normal run exits 0 with the class marker and no
#       failure;
#   37. the two normal traces are byte-identical;
#   38. the normal trace SHA-256 equals the committed one;
#   39. a fresh bypass run exits 0 with the class marker, no failure and no
#       propagation marker;
#   40. the bypass trace SHA-256 equals the committed one;
#   41. the normal and bypass SHA-256 values differ;
#   42. the two traces differ only in their propagated_influence lines;
#   43. every bypass influence component is zero;
#   44. the normal trace has at least one non-zero influence component;
#   45. both traces carry three records, the donor's three layer weights, the
#       influence-kind line, the bridge revision, and no mode label;
#   46. the boundary holds: no mutation construct anywhere in this step's
#       files, system/npc untouched, no sibling repository modified, and a
#       clean worktree.
#
# Anything outside this list is out of scope by construction: no event -> axis
# mutation, no target += influence, no blending, no receiver clamping, no
# neighbour aggregation, no update ordering, no contextual contagion, no
# EmotionalEvent, no persistent social graph, and no Remich-owned weight
# table or propagation formula.
set -uo pipefail

REPO_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)" || exit 1
cd "$REPO_ROOT" || exit 1

VAULT="/home/mrg/Documents/Project/buggy-vault"
VAULT_COMMIT="24181142c693be37f90a6a667a6dc493425cd832"
GODOT_BIN="/home/mrg/Documents/Project/Yolanda/.godot-local/engine/4.7.2/Godot_v4.7.2-stable_linux.x86_64"

# The re-scope freeze: docs/PLAN.md may not be rewritten by this step.
PLAN_FREEZE="02eff4214c97d31743e7486a9d905fa5c22541a6"
PROVENANCE_DOC="docs/anvil-import-phase1-step3.md"

# The committed bridge revision, and the two trace fingerprints this step
# measured: the fixture is byte-stable by construction (no timestamp, pid,
# path or machine value may enter the trace), so a fresh run must reproduce
# them exactly or the behaviour moved.
SOUL_REV="remich-soul-v1"
NORMAL_SHA="410aab053bcb79891e8cf3f7ac3c538f9f3973ebde05624b88e18b0dfbb2717f"
BYPASS_SHA="0e9795e795d9a72daf90e4a9829df25cf45e46460ce2e07cebdfe87c80f7a055"

SETTLEMENT_MOD="crates/anvil_sim/src/settlement/mod.rs"
# The exact lines Phase 3 Step 2 added to the module root; all three are
# spelled identically in the donor's own settlement/mod.rs.
P3S2_ADDED_LINES=(
    'pub mod connection;'
    'pub mod ids;'
    'pub use connection::{Connection, ConnectionLayer};'
)
# The six methods the probe is allowed to call, in the order the step prompt
# named them.
REQUIRED_METHODS="connection_weight,initialize,is_initialized,propagate,soul_bridge_rev,soul_snapshot"
DONOR_LAYERS="family,proximity,village"

STEP3_CHECKER="tools/check_phase1_step3.sh"
STEP4_CHECKER="tools/check_phase2_step4.sh"
STEP1_CHECKER="tools/check_phase3_step1.sh"

SIBLINGS="Munshausen Larochette Eisleck Grengewald Marnach"

LOG_DIR="$(mktemp -d "${TMPDIR:-/tmp}/remich-p3s2.XXXXXX")" || exit 1
trap 'rm -rf "$LOG_DIR"' EXIT

failures=0
pass() { printf 'ok    %s\n' "$1"; }
fail() { printf 'FAIL  %s\n' "$1"; failures=$((failures + 1)); }
note() { printf '      %s\n' "$1"; }
header() { printf '\n== %s ==\n' "$1"; }

note "HEAD is $(git rev-parse HEAD)"

# =============================================== 1-3. the live chain is green
header "1-3. The live chain is green"

if bash "$STEP1_CHECKER" >"$LOG_DIR/p3s1.log" 2>&1; then
    pass "bash $STEP1_CHECKER exits 0 (which runs the whole chain beneath it)"
    tail -n 3 "$LOG_DIR/p3s1.log" | sed 's/^/      | /'
else
    fail "bash $STEP1_CHECKER failed:"
    grep '^FAIL' "$LOG_DIR/p3s1.log" | sed 's/^/      | /'
    tail -n 40 "$LOG_DIR/p3s1.log" | sed 's/^/      | /'
fi

if grep -qF "ok    bash $STEP4_CHECKER exits 0" "$LOG_DIR/p3s1.log"; then
    pass "that run reports bash $STEP4_CHECKER exits 0"
else
    fail "that run does not report $STEP4_CHECKER green"
fi

if bash "$STEP3_CHECKER" >"$LOG_DIR/p1s3.log" 2>&1; then
    pass "bash $STEP3_CHECKER exits 0"
    tail -n 3 "$LOG_DIR/p1s3.log" | sed 's/^/      | /'
else
    fail "bash $STEP3_CHECKER failed:"
    grep '^FAIL' "$LOG_DIR/p1s3.log" | sed 's/^/      | /'
    tail -n 30 "$LOG_DIR/p1s3.log" | sed 's/^/      | /'
fi

# =============================================================== 4. the plan
header "4. docs/PLAN.md is byte-identical to the re-scope freeze"

if git diff --quiet "$PLAN_FREEZE" -- docs/PLAN.md 2>/dev/null; then
    pass "docs/PLAN.md is byte-identical to $PLAN_FREEZE"
else
    fail "docs/PLAN.md differs from the re-scope freeze $PLAN_FREEZE"
fi

# ====================================================== 5. the donor is pinned
header "5. The donor vault is clean at the pinned commit"

vault_status="$(git -C "$VAULT" status --porcelain 2>/dev/null)"
if [ -z "$vault_status" ] \
        && [ "$(git -C "$VAULT" rev-parse HEAD 2>/dev/null)" = "$VAULT_COMMIT" ]; then
    pass "the donor vault is clean and at $VAULT_COMMIT — read-only access held"
else
    fail "the donor vault is dirty or not at $VAULT_COMMIT:"
    printf '%s\n' "${vault_status:-<not at the pinned commit>}" | sed 's/^/      | /'
fi

# ================================================ 6-9. the four donor files
header "6-9. Every donor file this step uses is byte-identical to the donor"

for donor_file in \
    crates/anvil_sim/src/soul.rs \
    crates/anvil_sim/src/soul/axes.rs \
    crates/anvil_sim/src/settlement/connection.rs \
    crates/anvil_sim/src/settlement/ids.rs
do
    live_sha="$(sha256sum "$donor_file" 2>/dev/null | cut -d' ' -f1)"
    donor_sha="$(git -C "$VAULT" show "${VAULT_COMMIT}:repos/anvil/source/$donor_file" \
        2>/dev/null | sha256sum | cut -d' ' -f1)"
    if [ -n "$live_sha" ] && [ "$live_sha" = "$donor_sha" ]; then
        pass "$donor_file is byte-identical to the donor (${live_sha:0:16}…)"
    else
        fail "$donor_file is not byte-identical to the donor: live=${live_sha:-<missing>} donor=${donor_sha:-<unreadable>}"
    fi
done

# ============================================ 10-11. the module-root wiring
header "10-11. settlement/mod.rs declares the two modules and nothing else"

git -C "$VAULT" show "${VAULT_COMMIT}:repos/anvil/source/$SETTLEMENT_MOD" \
    >"$LOG_DIR/donor.mod.rs" 2>/dev/null

why=""
if ! diff -q <(head -n 5 "$LOG_DIR/donor.mod.rs") <(head -n 5 "$SETTLEMENT_MOD") >/dev/null 2>&1; then
    why="$why
    the donor's own five doc-comment lines are not the first five lines"
fi
for line in "${P3S2_ADDED_LINES[@]}"; do
    occurrences="$(grep -cxF -- "$line" "$SETTLEMENT_MOD" || true)"
    if [ "$occurrences" != "1" ]; then
        why="$why
    expected exactly one occurrence of '$line', found $occurrences"
    fi
    if ! tr '\n' ' ' <"$PROVENANCE_DOC" | grep -qF -- "$line"; then
        why="$why
    the provenance record does not document '$line'"
    fi
done
if [ -z "$why" ]; then
    pass "$SETTLEMENT_MOD keeps the donor's doc comment and carries exactly the three documented lines, once each"
else
    fail "$SETTLEMENT_MOD does not match the documented Phase 3 Step 2 addition:"
    printf '%s\n' "$why" | sed 's/^/      | /'
fi

why=""
for pruned in \
    'pub mod catalyst;' 'pub mod family;' 'pub mod memory;' \
    'pub mod person;' 'pub mod settlement_type;'
do
    if grep -qxF -- "$pruned" "$SETTLEMENT_MOD"; then
        why="$why
    Phase 1's pruned declaration is back: $pruned"
    fi
done
for kept in 'pub mod skill;' 'pub use skill::Skill;'; do
    if ! grep -qxF -- "$kept" "$SETTLEMENT_MOD"; then
        why="$why
    a Phase 1 keep is missing: $kept"
    fi
done
if [ -z "$why" ]; then
    pass "$SETTLEMENT_MOD keeps Phase 1's pruning and its skill module"
else
    fail "$SETTLEMENT_MOD changed its Phase 1 pruning:"
    printf '%s\n' "$why" | sed 's/^/      | /'
fi

# ================================================= 12-15. the provenance record
header "12-15. The provenance record carries the dated Phase 3 Step 2 addition"

if grep -qF '## 11. Phase 3 Step 2' "$PROVENANCE_DOC"; then
    pass "the record carries a dated Phase 3 Step 2 section"
else
    fail "the record has no dated Phase 3 Step 2 section"
fi

tr '\n' ' ' <"$PROVENANCE_DOC" | tr -s ' ' >"$LOG_DIR/doc.flat"
why=""
for needle in \
    '**184** at the Step 1 head' \
    '**+0** contributed by `settlement/ids.rs`' \
    '**+3** contributed by `settlement/connection.rs`' \
    '**= 187**'
do
    if ! grep -qF -- "$needle" "$LOG_DIR/doc.flat"; then
        why="$why
    the record does not state: $needle"
    fi
done
if [ -z "$why" ]; then
    pass "the record states all four counts: 184 -> +0 ids -> +3 connection -> 187"
else
    fail "the record does not carry the four test counts:"
    printf '%s\n' "$why" | sed 's/^/      | /'
fi

sed -n '/^<!-- step3-inventory:begin -->$/,/^<!-- step3-inventory:end -->$/p' \
    "$PROVENANCE_DOC" >"$LOG_DIR/inventory"
why=""
for new_file in \
    crates/anvil_sim/src/settlement/connection.rs \
    crates/anvil_sim/src/settlement/ids.rs
do
    entry="$(grep -F "$new_file :: " "$LOG_DIR/inventory" || true)"
    if [ -z "$entry" ]; then
        why="$why
    the inventory has no entry for $new_file"
        continue
    fi
    prov="$(awk -F ' :: ' '{ print $2 }' <<<"$entry")"
    status="$(awk -F ' :: ' '{ print $3 }' <<<"$entry")"
    if [ "$prov" != "buggy-vault@${VAULT_COMMIT:0:8} repos/anvil/source/$new_file" ]; then
        why="$why
    non-canonical provenance for $new_file: $prov"
    fi
    if [ "$status" != "unchanged" ]; then
        why="$why
    status of $new_file is '$status', expected 'unchanged'"
    fi
done
if [ -z "$why" ]; then
    pass "the inventory carries both new files as byte-identical, canonically attributed entries"
else
    fail "the inventory does not carry both new files correctly:"
    printf '%s\n' "$why" | sed 's/^/      | /'
fi

why=""
for needle in \
    '`system/npc` remains untaken' \
    'no receiver application' \
    'Propagated influence'
do
    if ! grep -qF -- "$needle" "$PROVENANCE_DOC"; then
        why="$why
    the record does not state: $needle"
    fi
done
if [ -z "$why" ]; then
    pass "the record states system/npc stays untaken and that influence is not a receiver state update"
else
    fail "the record does not state the scope limits:"
    printf '%s\n' "$why" | sed 's/^/      | /'
fi

# ==================================================== 16-19. the core facade
header "16-19. The engine-free facade reaches the donor and nothing else"

why=""
if cargo tree -p remich_core 2>/dev/null | grep -qiE 'godot|gdext'; then
    why="$why
    cargo tree -p remich_core resolves an engine crate"
fi
engine_hits="$(grep -rniE 'godot|gdext' crates/remich_core/src || true)"
if [ -n "$engine_hits" ]; then
    why="$why
    engine API use in the engine-free core:
$(printf '%s\n' "$engine_hits" | sed 's/^/      /')"
fi
if [ -z "$why" ]; then
    pass "the engine-free core — including the new soul facade — names no engine at all"
else
    fail "the engine-free core is not engine-free:"
    printf '%s\n' "$why" | sed 's/^/      | /'
fi

if cargo test -p remich_core soul:: >"$LOG_DIR/core-soul.log" 2>&1 \
        && grep -qF 'test result: ok. 7 passed' "$LOG_DIR/core-soul.log"; then
    pass "the facade's own tests are green (7 equivalence and refusal tests)"
else
    fail "the facade's tests are not green:"
    grep -E 'test result|^error' "$LOG_DIR/core-soul.log" | sed 's/^/      | /'
fi

why=""
lookup="$(grep -E '^ *"(family|proximity|village)" =>' crates/remich_core/src/soul.rs || true)"
if [ "$(printf '%s\n' "$lookup" | sed '/^$/d' | wc -l)" -ne 3 ]; then
    why="$why
    expected the three-name lookup, found: ${lookup:-<none>}"
fi
if printf '%s\n' "$lookup" | grep -qE '[0-9]'; then
    why="$why
    a number is attached to a layer name:
$(printf '%s\n' "$lookup" | grep -E '[0-9]' | sed 's/^/      /')"
fi
if [ -z "$why" ]; then
    pass "the name -> ConnectionLayer lookup maps names to donor variants and carries no number"
else
    fail "the name -> layer lookup is not a pure lookup:"
    printf '%s\n' "$why" | sed 's/^/      | /'
fi

why=""
grep -qF 'pub fn propagate(&self, layer: ConnectionLayer) -> PropagatedInfluence' \
    crates/remich_core/src/soul.rs \
    || why="$why
    the facade does not expose propagate(&self, layer: ConnectionLayer)"
grep -qF 'let connection_weight = layer.weight();' crates/remich_core/src/soul.rs \
    || why="$why
    the donor's ConnectionLayer::weight() is not the edge strength used"
grep -qF '.axes.propagate(connection_weight)' crates/remich_core/src/soul.rs \
    || why="$why
    the donor's EmotionalAxes::propagate(connection_weight) is not what runs"
applied="$(grep -vE '^[[:space:]]*//' crates/remich_core/src/soul.rs \
    | grep -nE 'fn (apply|blend|update_axis|write_influence|record_event)|target[[:space:]]*\+=' || true)"
if [ -n "$applied" ]; then
    why="$why
    an application of influence exists in the facade:
$(printf '%s\n' "$applied" | sed 's/^/      /')"
fi
if [ -z "$why" ]; then
    pass "propagation is the donor's weight() into the donor's propagate(), with no application of our own"
else
    fail "the facade does more than forward to the donor:"
    printf '%s\n' "$why" | sed 's/^/      | /'
fi

# ==================================================== 20-24. the binding class
header "20-24. One binding class exposes those primitives, explicitly"

if grep -qxF 'pub const SOUL_BRIDGE_REV: &str = "'"$SOUL_REV"'";' crates/remich_gdext/src/lib.rs; then
    pass "SOUL_BRIDGE_REV holds exactly the committed marker '$SOUL_REV'"
else
    fail "SOUL_BRIDGE_REV does not hold the committed marker '$SOUL_REV'"
fi

why=""
class_count="$(grep -c 'pub struct RemichSoul' crates/remich_gdext/src/lib.rs || true)"
if [ "$class_count" != "1" ]; then
    why="$why
    expected exactly one RemichSoul class, found $class_count"
fi
block="$(sed -n '/^pub struct RemichSoul {$/,/^}$/p' crates/remich_gdext/src/lib.rs)"
if ! printf '%s\n' "$block" | grep -qF 'soul: Option<SoulFacade>'; then
    why="$why
    the class does not hold a plain soul facade"
fi
if printf '%s\n' "$block" | grep -qiE 'f32|f64|weight|axes|family|proximity|village'; then
    why="$why
    the class stores state beyond a soul:
$(printf '%s\n' "$block" | grep -iE 'f32|f64|weight|axes|family|proximity|village' | sed 's/^/      /')"
fi
if [ -z "$why" ]; then
    pass "exactly one RemichSoul class exists and holds only the soul facade"
else
    fail "the binding class is not a single plain-values class:"
    printf '%s\n' "$why" | sed 's/^/      | /'
fi

why=""
for method in initialize is_initialized soul_snapshot connection_weight propagate soul_bridge_rev; do
    if ! grep -qE "^    fn $method\(" crates/remich_gdext/src/lib.rs; then
        why="$why
    missing: fn $method("
    fi
done
if [ -z "$why" ]; then
    pass "all six required methods exist on the class"
else
    fail "the class is missing required methods:"
    printf '%s\n' "$why" | sed 's/^/      | /'
fi

if grep -qE 'fn soul_bridge_rev_is_the_committed_marker' crates/remich_gdext/src/lib.rs; then
    pass "the binding's bridge-revision test exists"
else
    fail "the binding has no soul_bridge_rev_is_the_committed_marker test"
fi

if cargo test -p remich_gdext >"$LOG_DIR/gdext.log" 2>&1; then
    pass "cargo test -p remich_gdext is green"
else
    fail "cargo test -p remich_gdext failed:"
    grep -E 'test result|^error|panicked' "$LOG_DIR/gdext.log" | sed 's/^/      | /'
fi

# =========================================================== 25-30. the probe
header "25-30. The probe is a standalone script with the committed fixture"

why=""
if [ ! -f godot/soul_probe.gd ]; then
    why="$why
    godot/soul_probe.gd is missing"
elif [ "$(head -n 1 godot/soul_probe.gd)" != "extends SceneTree" ]; then
    why="$why
    the probe does not extend SceneTree"
fi
if grep -qi 'soul' godot/project.godot; then
    why="$why
    the probe is registered with the project (it must not be an autoload)"
fi
if [ -z "$why" ]; then
    pass "the probe is a standalone SceneTree script and is not an autoload"
else
    fail "the probe is not the standalone script this step requires:"
    printf '%s\n' "$why" | sed 's/^/      | /'
fi

rust_seeds="$(sed -n 's/.*FIXTURE_SEEDS: \[u64; 3\] = \[\([^]]*\)\];.*/\1/p' \
    crates/remich_core/src/soul.rs | tr -d ' _')"
probe_seeds="$(sed -n 's/.*const SEEDS: Array\[int\] = \[\([^]]*\)\].*/\1/p' \
    godot/soul_probe.gd | tr -d ' ')"
if [ -n "$rust_seeds" ] && [ "$rust_seeds" = "$probe_seeds" ]; then
    pass "the probe's three seeds equal the facade's fixture seeds ($probe_seeds)"
else
    fail "the probe seeds ($probe_seeds) do not equal the facade fixture seeds ($rust_seeds)"
fi

donor_layers="$(git -C "$VAULT" show "${VAULT_COMMIT}:repos/anvil/source/crates/anvil_sim/src/settlement/connection.rs" \
    | awk '/pub enum ConnectionLayer/,/^}/' \
    | sed -n 's/^    \([A-Za-z][A-Za-z]*\),$/\1/p' \
    | tr '[:upper:]' '[:lower:]' | paste -sd,)"
probe_layers="$(sed -n 's/.*const LAYERS: Array\[String\] = \[\(.*\)\].*/\1/p' godot/soul_probe.gd | tr -d ' \"')"
if [ -n "$donor_layers" ] && [ "$probe_layers" = "$donor_layers" ] \
        && [ "$probe_layers" = "$DONOR_LAYERS" ]; then
    pass "the probe's three layers are the donor's own names ($probe_layers)"
else
    fail "the probe layers are '$probe_layers', the donor's are '$donor_layers'"
fi

probe_calls="$(grep -o 'soul\.call("[a-z_]*"' godot/soul_probe.gd \
    | sed 's/soul\.call("//; s/"$//' | sort -u | paste -sd,)"
if [ "$probe_calls" = "$REQUIRED_METHODS" ]; then
    pass "the probe calls only the six methods of the class"
else
    fail "the probe calls '$probe_calls', expected '$REQUIRED_METHODS'"
fi

clock_hits="$(grep -nE 'Time\.|randomize|randi|randf|get_unix|DateTime|get_ticks|get_pid|get_user' \
    godot/soul_probe.gd || true)"
if [ -z "$clock_hits" ]; then
    pass "the probe reads no clock, pid or random source"
else
    fail "the probe reads a clock, pid or random source:"
    printf '%s\n' "$clock_hits" | sed 's/^/      | /'
fi

why=""
grep -qF 'JSON.stringify(after' godot/soul_probe.gd \
    || why="$why
    the probe does not compare the snapshot taken after the call with the one before"
grep -qF 'unknown-layer' godot/soul_probe.gd \
    || why="$why
    the probe does not require an unknown layer to be refused"
if [ -z "$why" ]; then
    pass "the probe asserts the soul is unchanged across the call and refuses an unknown layer"
else
    fail "the probe is missing an assertion this step requires:"
    printf '%s\n' "$why" | sed 's/^/      | /'
fi

# =================================================== 31-33. staging and runner
header "31-33. Staging derives the expectation and the runner pins the engine"

why=""
grep -qF 'SOUL_BRIDGE_REV' tools/stage_soul.sh \
    || why="$why
    the staging script does not read SOUL_BRIDGE_REV"
grep -qF 'stage_bridge.sh' tools/stage_soul.sh \
    || why="$why
    the staging script does not chain tools/stage_bridge.sh"
grep -qF 'godot/soul_probe_expectation.txt' tools/stage_soul.sh \
    || why="$why
    the staging script does not write godot/soul_probe_expectation.txt"
if [ -z "$why" ]; then
    pass "the staging script derives the expectation from the Rust source and chains the bridge staging"
else
    fail "the staging script does not derive what this step requires:"
    printf '%s\n' "$why" | sed 's/^/      | /'
fi

why=""
grep -qF 'Godot_v4.7.2-stable_linux.x86_64' tools/run_soul.sh \
    || why="$why
    the runner does not name the pinned engine binary"
grep -qF -- '--headless' tools/run_soul.sh \
    || why="$why
    the runner is not headless"
grep -qF 'res://soul_probe.gd' tools/run_soul.sh \
    || why="$why
    the runner does not invoke the probe with --script"
grep -qF 'REMICH_SOUL_BYPASS' tools/run_soul.sh \
    || why="$why
    the runner has no bypass mode"
if [ -z "$why" ]; then
    pass "the runner uses the pinned engine, headless, via --script res://soul_probe.gd"
else
    fail "the runner does not run the probe as this step requires:"
    printf '%s\n' "$why" | sed 's/^/      | /'
fi

why=""
grep -qxF '/godot/soul_probe_expectation.txt' .gitignore \
    || why="$why
    /godot/soul_probe_expectation.txt is not ignored"
grep -qxF 'soul_trace*.txt' .gitignore \
    || why="$why
    soul_trace*.txt is not ignored"
if [ -z "$why" ]; then
    pass "the derived expectation file and the soul traces are ignored"
else
    fail "derived state is not ignored:"
    printf '%s\n' "$why" | sed 's/^/      | /'
fi

# ===================================================== 34-38. the normal runs
header "34-38. Two fresh normal runs are deterministic and reproduce the SHA"

NORMAL_A="$LOG_DIR/normal-a.txt"
NORMAL_B="$LOG_DIR/normal-b.txt"
BYPASS_T="$LOG_DIR/bypass.txt"

bash tools/run_soul.sh "$NORMAL_A" normal >"$LOG_DIR/run-a.log" 2>&1
rc_a=$?
why=""
[ "$rc_a" -eq 0 ] || why="$why
    the run exited $rc_a"
grep -qxF "REMICH_SOUL_OK actors=3 rev=$SOUL_REV" "$LOG_DIR/run-a.log" \
    || why="$why
    REMICH_SOUL_OK actors=3 rev=$SOUL_REV was not reported"
if grep -q '^REMICH_SOUL_FAIL ' "$LOG_DIR/run-a.log"; then
    why="$why
$(grep '^REMICH_SOUL_FAIL ' "$LOG_DIR/run-a.log" | sed 's/^/    /')"
fi
[ -s "$NORMAL_A" ] || why="$why
    no trace was written"
if [ -z "$why" ]; then
    pass "a fresh normal run exits 0 with REMICH_SOUL_OK actors=3 and no failure marker"
else
    fail "the first normal run did not report the class marker:"
    printf '%s\n' "$why" | sed 's/^/      | /'
    tail -n 20 "$LOG_DIR/run-a.log" | sed 's/^/      | /'
fi

if grep -qxF "REMICH_SOUL_PROPAGATION_OK layers=$DONOR_LAYERS rev=$SOUL_REV" "$LOG_DIR/run-a.log"; then
    pass "that run reports the propagation marker for family, proximity and village"
else
    fail "REMICH_SOUL_PROPAGATION_OK layers=$DONOR_LAYERS rev=$SOUL_REV was not reported"
fi

bash tools/run_soul.sh "$NORMAL_B" normal >"$LOG_DIR/run-b.log" 2>&1
rc_b=$?
why=""
[ "$rc_b" -eq 0 ] || why="$why
    the run exited $rc_b"
grep -qxF "REMICH_SOUL_OK actors=3 rev=$SOUL_REV" "$LOG_DIR/run-b.log" \
    || why="$why
    REMICH_SOUL_OK actors=3 rev=$SOUL_REV was not reported"
if grep -q '^REMICH_SOUL_FAIL ' "$LOG_DIR/run-b.log"; then
    why="$why
$(grep '^REMICH_SOUL_FAIL ' "$LOG_DIR/run-b.log" | sed 's/^/    /')"
fi
[ -s "$NORMAL_B" ] || why="$why
    no trace was written"
if [ -z "$why" ]; then
    pass "a second fresh normal run exits 0 with REMICH_SOUL_OK actors=3 and no failure marker"
else
    fail "the second normal run did not report the class marker:"
    printf '%s\n' "$why" | sed 's/^/      | /'
    tail -n 20 "$LOG_DIR/run-b.log" | sed 's/^/      | /'
fi

if cmp -s "$NORMAL_A" "$NORMAL_B"; then
    pass "the two normal traces are byte-identical"
else
    fail "the two normal traces differ:"
    diff "$NORMAL_A" "$NORMAL_B" | sed 's/^/      | /'
fi

normal_sha="$(sha256sum "$NORMAL_A" 2>/dev/null | cut -d' ' -f1)"
if [ "$normal_sha" = "$NORMAL_SHA" ]; then
    pass "the normal trace SHA-256 is the committed $NORMAL_SHA"
else
    fail "the normal trace SHA-256 is '${normal_sha:-<no trace>}', expected $NORMAL_SHA"
fi

# ====================================================== 39-41. the bypass run
header "39-41. The bypass run changes only the influence values"

bash tools/run_soul.sh "$BYPASS_T" bypass >"$LOG_DIR/run-bypass.log" 2>&1
rc_x=$?
why=""
[ "$rc_x" -eq 0 ] || why="$why
    the run exited $rc_x"
grep -qxF "REMICH_SOUL_OK actors=3 rev=$SOUL_REV" "$LOG_DIR/run-bypass.log" \
    || why="$why
    REMICH_SOUL_OK actors=3 rev=$SOUL_REV was not reported"
if grep -q '^REMICH_SOUL_FAIL ' "$LOG_DIR/run-bypass.log"; then
    why="$why
$(grep '^REMICH_SOUL_FAIL ' "$LOG_DIR/run-bypass.log" | sed 's/^/    /')"
fi
if grep -q '^REMICH_SOUL_PROPAGATION_OK ' "$LOG_DIR/run-bypass.log"; then
    why="$why
    the bypass run claimed a propagation it did not perform"
fi
[ -s "$BYPASS_T" ] || why="$why
    no trace was written"
if [ -z "$why" ]; then
    pass "a fresh bypass run exits 0 with REMICH_SOUL_OK, no failure and no propagation marker"
else
    fail "the bypass run did not report what this step requires:"
    printf '%s\n' "$why" | sed 's/^/      | /'
    tail -n 20 "$LOG_DIR/run-bypass.log" | sed 's/^/      | /'
fi

bypass_sha="$(sha256sum "$BYPASS_T" 2>/dev/null | cut -d' ' -f1)"
if [ "$bypass_sha" = "$BYPASS_SHA" ]; then
    pass "the bypass trace SHA-256 is the committed $BYPASS_SHA"
else
    fail "the bypass trace SHA-256 is '${bypass_sha:-<no trace>}', expected $BYPASS_SHA"
fi

if [ -n "$normal_sha" ] && [ -n "$bypass_sha" ] && [ "$normal_sha" != "$bypass_sha" ]; then
    pass "normal_sha != bypass_sha — the bypass removed exactly what it claims to"
else
    fail "the normal and bypass traces have the same SHA-256 ($normal_sha)"
fi

# =========================================================== 42-44. what moved
header "42-44. Only the propagated influence differs, and only in the normal run"

if diff <(grep -v '^propagated_influence ' "$NORMAL_A") \
        <(grep -v '^propagated_influence ' "$BYPASS_T") >/dev/null 2>&1; then
    pass "the two traces differ only in their propagated_influence lines"
else
    fail "a field other than the propagated influence differs:"
    diff <(grep -v '^propagated_influence ' "$NORMAL_A") \
        <(grep -v '^propagated_influence ' "$BYPASS_T") | sed 's/^/      | /'
fi

bypass_nonzero="$(grep '^propagated_influence ' "$BYPASS_T" | sed 's/^propagated_influence //' \
    | awk '{ for (i = 1; i <= NF; i++) { split($i, a, "="); if (a[2] + 0 != 0) bad++ } }
           END { print bad + 0 }')"
if [ "$bypass_nonzero" = "0" ]; then
    pass "every bypass influence component is zero"
else
    fail "$bypass_nonzero bypass influence component(s) are not zero"
fi

normal_nonzero="$(grep '^propagated_influence ' "$NORMAL_A" | sed 's/^propagated_influence //' \
    | awk '{ for (i = 1; i <= NF; i++) { split($i, a, "="); if (a[2] + 0 != 0) n++ } }
           END { print n + 0 }')"
if [ "$normal_nonzero" -ge 1 ]; then
    pass "the normal trace has $normal_nonzero non-zero influence component(s) — a zero-output implementation cannot pass"
else
    fail "every normal influence component is zero — a zero-output implementation would pass"
fi

# ================================================== 45-46. shape and boundary
header "45-46. The trace carries the donor's numbers, and the boundary holds"

why=""
records="$(grep -c '^actor=' "$NORMAL_A" || true)"
[ "$records" = "3" ] || why="$why
    $records actor record(s), expected 3"
grep '^connection layer=' "$NORMAL_A" >"$LOG_DIR/layers.now"
printf 'connection layer=family weight=1.000000\nconnection layer=proximity weight=0.500000\nconnection layer=village weight=0.100000\n' \
    >"$LOG_DIR/layers.want"
if ! diff -q "$LOG_DIR/layers.want" "$LOG_DIR/layers.now" >/dev/null 2>&1; then
    why="$why
    the three connection lines are not the donor's 1.0 / 0.5 / 0.1 in order:
$(diff "$LOG_DIR/layers.want" "$LOG_DIR/layers.now" | sed 's/^/    /')"
fi
kinds="$(grep -c '^influence_kind=propagated-influence (not a receiver state update)$' "$NORMAL_A" || true)"
[ "$kinds" = "3" ] || why="$why
    $kinds influence_kind line(s), expected 3"
revs="$(grep -c "^bridge_rev=$SOUL_REV\$" "$NORMAL_A" || true)"
[ "$revs" = "3" ] || why="$why
    $revs bridge_rev line(s), expected 3"
labels="$(grep -ciE 'bypass|mode=' "$NORMAL_A" "$BYPASS_T" 2>/dev/null | grep -v ':0$' || true)"
if [ -n "$labels" ]; then
    why="$why
    a mode label appears in a trace:
$labels"
fi
if [ -z "$why" ]; then
    pass "both traces carry three records, the donor's three weights, the influence-kind line, the revision and no mode label"
else
    fail "the trace does not carry the shape this step requires:"
    printf '%s\n' "$why" | sed 's/^/      | /'
fi

why=""
forbidden="$(for f in \
        crates/remich_core/src/soul.rs \
        godot/soul_probe.gd \
        tools/stage_soul.sh \
        tools/run_soul.sh; do
        grep -vE '^[[:space:]]*(//|#)' "$f" | grep -nE \
            'target[[:space:]]*\+=|EmotionalEvent|\.clamp\(|lerp\(|update_order|contextual_contagion|asymmetr|weight_table|WEIGHT_TABLE' \
            | sed "s|^|$f:|"
    done;
    sed -n '/^pub struct RemichSoul {$/,/^}$/p' crates/remich_gdext/src/lib.rs \
        | grep -vE '^[[:space:]]*//' \
        | grep -nE 'target[[:space:]]*\+=|EmotionalEvent|\.clamp\(|lerp\(|weight_table' \
        | sed 's|^|crates/remich_gdext/src/lib.rs:|' || true)"
if [ -n "$forbidden" ]; then
    why="$why
    a forbidden mutation construct exists:
$(printf '%s\n' "$forbidden" | sed 's/^/      /')"
fi
npc_delta="$(git diff --name-only "$PLAN_FREEZE" -- crates/anvil_sim/src/system/ 2>/dev/null)"
if [ -n "$npc_delta" ]; then
    why="$why
    system/ changed:
$(printf '%s\n' "$npc_delta" | sed 's/^/      /')"
fi
if git ls-files 'crates/anvil_sim/src/system/*' | grep -q .; then
    why="$why
    a file under system/ is tracked (system/npc must stay untaken)"
fi
for sibling in $SIBLINGS; do
    dirt="$(git -C "/home/mrg/Documents/Project/$sibling" status --porcelain 2>/dev/null | wc -l)"
    if [ "$dirt" -ne 0 ]; then
        why="$why
    $sibling is not clean ($dirt entries)"
    fi
done
stray="$(git status --porcelain 2>/dev/null)"
if [ -n "$stray" ]; then
    why="$why
    the worktree is not clean at the acceptance head:
$(printf '%s\n' "$stray" | sed 's/^/      /')"
fi
if [ -z "$why" ]; then
    pass "no mutation construct in this step's files, system/npc untouched, siblings clean, worktree clean"
else
    fail "the boundary of this step does not hold:"
    printf '%s\n' "$why" | sed 's/^/      | /'
fi

# ------------------------------------------------------------------ summary
printf '\n========================================\n'
if [ "$failures" -eq 0 ]; then
    printf 'PASS  Phase 3 Step 2 — soul primitives across the bridge\n'
    printf '========================================\n'
    exit 0
fi
printf 'FAIL  Phase 3 Step 2 — %d check(s) failed\n' "$failures"
printf '========================================\n'
exit 1
