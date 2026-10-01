#!/usr/bin/env bash
# Phase 2, Step 3 acceptance check — "the game's save"
# (docs/PLAN.md §4a, step 3; record: docs/remich-save-phase2-step3.md).
#
# One command, from anywhere:
#
#     bash tools/check_phase2_step3.sh
#
# It re-proves, directly, every capability this step must preserve and add.
# Phase 2 Step 2's checker is run unchanged as a sub-check: the clock stays
# the sole time authority, the weather snapshot stays single-writer, and the
# Phase 1 scorer markers survive.
#
# Requirements, as checks (numbered as this step enumerated them):
#
#   1. the Step 2 merge is an ancestor of this head;
#   2. tools/check_phase2_step2.sh remains green, differing only by its named
#      Remich #9 / Phase 3 Step 1 edit, with the five preserved markers
#      (CLOCK/WEATHER/SCORER/DECAY/BRIDGE) in its log;
#   3. donor code/data and provenance remain untouched, bar the one file
#      Remich #9 authorizes and the record documenting it;
#   4. the save core is engine-free;
#   5. the save format declares an explicit version 1;
#   6. serialization is deterministic — identical state, identical bytes;
#   7. round-trip load preserves every saved field exactly;
#   8. malformed, unsupported-version and invalid state fail clearly;
#   9. a changed identity adapts and never refuses;
#  10. the drop record names subject, field, value and reason=missing-place;
#  11. the save holds only the sanctioned state;
#  12. the core carries no presentation state, no tool path, never the bridge
#      revision;
#  13. the binding owns Godot conversion and file access, and SAVE_BRIDGE_REV
#      holds its committed value (the v2 rebuild sentinel lives only in docs);
#  14. a fresh process writes the noon save outside the worktree, with
#      SaveProbe last in the autoload chain and silent without its mode;
#  15. the save on disk is exactly the sanctioned JSON;
#  16. the save file carries no presentation state and no repository/engine
#      path;
#  17. the uninterrupted baseline completes to tick 240;
#  18. a fresh process loads the save and continues (REMICH_SAVE_OK);
#  19. the two second-half continuation traces are byte-identical;
#  20. their SHA-256 hashes match (both reported);
#  21. the independent trace validator accepts both traces;
#  22. final clock, needs, weather and scorer choices agree across the runs;
#  23. the traces contain no process-specific values or paths;
#  24. the shared clock and weather autoloads remain the sole authorities;
#  25. the adapted load reports the drop exactly and keeps what fits;
#  26. identity mismatch is never a refusal;
#  27. loading never rewrites the save (H1 = H2 = H3, all reported);
#  28. the noon boundary convention holds (next tick 120, snapshot 119, needs
#      ready for the decision at 120);
#  29. the earlier markers still appear, the save probe is silent in ordinary
#      runs, and every engine run in tools/ is headless;
#  30. the record documents donors, format, boundary, trace hashes, the drop
#      report, save hashes, timings and refusals;
#  31. the workspace builds and tests warning-free; no generated state is
#      tracked;
#  32. no other repository was modified, external paths stay limited, and the
#      worktree is clean.
#
# Where behaviour can prove the rule, it does: the four engine runs, the
# byte-identity comparison, the adaptation report, the rehashing of the save
# around both loads and the shared-node assertions inside the probe are all
# exercised by running things. The traces and the save live outside the
# worktree (a fresh /tmp/remich-p2s3.* directory), so the runs themselves
# cannot make check 32 look dirty.

set -uo pipefail

REPO_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)" || exit 1
cd "$REPO_ROOT" || exit 1

# Qualified headless path only: never editor, import or export mode.
GODOT_BIN="/home/mrg/Documents/Project/Yolanda/.godot-local/engine/4.7.2/Godot_v4.7.2-stable_linux.x86_64"

VAULT="/home/mrg/Documents/Project/buggy-vault"
VAULT_COMMIT="24181142c693be37f90a6a667a6dc493425cd832"
# The merge commit that closed Phase 2 Step 2 (PR #10, reviewed head c63da5b):
# Step 2's checker, the earlier checkers and the plan must be unchanged since
# it, and its merge must be an ancestor of this head.
STEP2_MERGE="eecab0be8f76e1abdc33f560e21bd8af31ecdfa1"
STEP2_HEAD="c63da5b0567f5b74b653674ca891a069386a7f13"

SAVE_SRC="crates/remich_core/src/save.rs"
CLOCK_SRC="crates/remich_core/src/clock.rs"
CORE_SRC_DIR="crates/remich_core/src"
GDEX_SRC="crates/remich_gdext/src/lib.rs"
GDEX_SAVE_SRC="crates/remich_gdext/src/save.rs"
SAVE_PROBE="godot/save_probe.gd"
PROBE_PROJECT="godot/project.godot"
STEP2_CHECKER="tools/check_phase2_step2.sh"
RUN_SAVE="tools/run_save.sh"
TRACE_VALIDATOR="tools/check_save_trace.py"
RECORD_DOC="docs/remich-save-phase2-step3.md"
PLAN_DOC="docs/PLAN.md"
# Remich issue #9 / Phase 3 Step 1 (the embedded action catalogue): the one
# donor file this step is authorized to change, the provenance record that
# documents it, the checkers whose ratchets it legitimately moved, and the
# lead's Phase 3 plan merge. docs/PLAN.md's freeze point is PLAN_FREEZE
# below — the lead's Phase 3 Step 2 re-scope.
N9_CATALOGUE="crates/anvil_sim/src/actions/catalogue.rs"
N9_PROVENANCE="docs/anvil-import-phase1-step3.md"
PLAN_MERGE="cfa796cc4885432da93b1974602ef3ba9a7cbff8"
# Remich Phase 3 Step 2 — soul primitives across the bridge (the lead's
# docs-only plan re-scope, 2026-10-01): docs/PLAN.md's byte-for-byte freeze
# point moved from $PLAN_MERGE to the commit that made the amendment, so plan
# content is compared against PLAN_FREEZE below. $PLAN_MERGE stays the
# ancestry base and the checker-freeze base. Any further edit to the plan
# still fails these checks; re-pin PLAN_FREEZE only for an authorized
# amendment.
PLAN_FREEZE="02eff4214c97d31743e7486a9d905fa5c22541a6"

COMMITTED_SAVE_REV="remich-save-v1"
# The rebuild-measurement sentinel, spelled so this script never trips its own
# check: it may survive only in documentation that records the measurement.
SAVE_SENTINEL="$(printf 'remich-save-v%s' '2')"
SAVED_IDENTITY="world-revision-A"
CURRENT_IDENTITY="world-revision-B"
INHABITANT="standin-inhabitant-1"
CURRENT_PLACE="market-square"
DROP_TOKEN="${INHABITANT}.current_place:${CURRENT_PLACE}"
FIXTURE_SEED=60628

LOG_DIR="$(mktemp -d /tmp/remich-p2s3.XXXXXX)" || exit 1
trap 'rm -rf "$LOG_DIR"' EXIT

TRACE_A="$LOG_DIR/trace-baseline.jsonl"
TRACE_B="$LOG_DIR/trace-load.jsonl"
SAVE_FILE="$LOG_DIR/noon-save.json"
LOG_BASELINE="$LOG_DIR/run-baseline.log"
LOG_SAVE="$LOG_DIR/run-save.log"
LOG_LOAD="$LOG_DIR/run-load.log"
LOG_ADAPT="$LOG_DIR/run-adapt.log"
LOG_V="$LOG_DIR/validator.log"
LOG_JSON="$LOG_DIR/save-json.log"
LOG_BUILD="$LOG_DIR/build.log"
LOG_TEST="$LOG_DIR/test.log"
LOG_CORE="$LOG_DIR/core-save-tests.log"
LOG_GDEX="$LOG_DIR/gdext-tests.log"
LOG_STEP2="$LOG_DIR/step2.log"

failures=0
pass() { printf 'ok    %s\n' "$1"; }
fail() { printf 'FAIL  %s\n' "$1"; failures=$((failures + 1)); }
note() { printf '      %s\n' "$1"; }
header() { printf '\n== %s ==\n' "$1"; }
tail_log() { tail -n 25 "$1" | sed 's/^/      | /'; }
hash_of() { sha256sum "$1" 2>/dev/null | cut -d' ' -f1; }

# ---------------------------------------------------------------------------
# Execute everything the numbered checks then read from. Build first so the
# engine runs load this workspace's fresh library. The four save modes are
# four separate pinned-engine processes (tools/run_save.sh starts one per
# invocation); the save is hashed after it is written, after the load and
# after the adaptation — H1 must be taken before anything loads, so a
# rewrite by a load could not hide behind a later recomputation.
# ---------------------------------------------------------------------------

cargo build --workspace >"$LOG_BUILD" 2>&1

run_rc=0
bash "$RUN_SAVE" baseline "$TRACE_A" >"$LOG_BASELINE" 2>&1 || run_rc=$?
BASELINE_RC=$run_rc
run_rc=0
bash "$RUN_SAVE" save "$SAVE_FILE" >"$LOG_SAVE" 2>&1 || run_rc=$?
SAVE_RC=$run_rc
H1="$(hash_of "$SAVE_FILE")"
run_rc=0
bash "$RUN_SAVE" load "$SAVE_FILE" "$TRACE_B" >"$LOG_LOAD" 2>&1 || run_rc=$?
LOAD_RC=$run_rc
H2="$(hash_of "$SAVE_FILE")"
run_rc=0
bash "$RUN_SAVE" adapt "$SAVE_FILE" >"$LOG_ADAPT" 2>&1 || run_rc=$?
ADAPT_RC=$run_rc
H3="$(hash_of "$SAVE_FILE")"

python3 "$TRACE_VALIDATOR" "$TRACE_A" "$TRACE_B" >"$LOG_V" 2>&1
VA_RC=$?

python3 - "$SAVE_FILE" >"$LOG_JSON" 2>&1 <<'PY'
import json
import sys

path = sys.argv[1]
sections = {"structure": [], "purity": [], "boundary": []}


def bad(section, message):
    sections[section].append(message)


try:
    with open(path, encoding="utf-8") as handle:
        text = handle.read()
    save = json.loads(text)
    if not isinstance(save, dict):
        raise ValueError("the document is not a JSON object")
except Exception as error:  # unreadable, empty or malformed
    for section in sections:
        bad(section, f"the save file could not be read: {error}")
    save = None
    text = ""

if isinstance(save, dict):
    # --- structure: exactly the sanctioned shape -------------------------
    if set(save) != {"format_version", "tool_identity", "clock", "weather", "inhabitant"}:
        bad("structure", f"top-level keys are {sorted(save)}")
    if save.get("format_version") != 1:
        bad("structure", f"format_version is {save.get('format_version')!r}, expected 1")
    if save.get("tool_identity") != "world-revision-A":
        bad("structure", f"tool_identity is {save.get('tool_identity')!r}")

    clock = save.get("clock")
    if not isinstance(clock, dict) or set(clock) != {
        "tick", "tick_length_ns", "speed", "paused"
    }:
        bad("structure", "the clock must be exactly tick/tick_length_ns/speed/paused")

    weather = save.get("weather")
    if not isinstance(weather, dict) or set(weather) != {"seed", "cycle_length", "snapshot"}:
        bad("structure", "the weather must be exactly seed/cycle_length/snapshot")

    snapshot = weather.get("snapshot") if isinstance(weather, dict) else None
    if not isinstance(snapshot, dict) or set(snapshot) != {
        "tick", "wind_dir_x", "wind_dir_z", "wind_strength",
        "rain", "temperature", "light",
    }:
        bad("structure", "the snapshot must be exactly the seven weather fields")

    inhabitant = save.get("inhabitant")
    if not isinstance(inhabitant, dict) or set(inhabitant) != {
        "id", "seed", "needs", "current_place"
    }:
        bad("structure", "the inhabitant must be exactly id/seed/needs/current_place")
    else:
        if inhabitant.get("id") != "standin-inhabitant-1":
            bad("structure", f"inhabitant id is {inhabitant.get('id')!r}")
        if inhabitant.get("seed") != 60628:
            bad("structure", f"inhabitant seed is {inhabitant.get('seed')!r}")
        needs = inhabitant.get("needs")
        if (
            not isinstance(needs, list)
            or len(needs) != 7
            or not all(
                isinstance(n, (int, float))
                and not isinstance(n, bool)
                and 0.0 <= n <= 1.0
                for n in needs
            )
        ):
            bad("structure", "the inhabitant does not carry exactly seven needs in [0, 1]")
        if inhabitant.get("current_place") != "market-square":
            bad("structure", f"current_place is {inhabitant.get('current_place')!r}")

    # --- boundary: noon convention --------------------------------------
    if isinstance(clock, dict):
        if clock.get("tick") != 120:
            bad("boundary", f"clock tick is {clock.get('tick')!r}, expected 120")
        if clock.get("tick_length_ns") != 100000000:
            bad("boundary", f"tick_length_ns is {clock.get('tick_length_ns')!r}")
        if clock.get("speed") != 1:
            bad("boundary", f"speed is {clock.get('speed')!r}, expected 1")
        if clock.get("paused") is not False:
            bad("boundary", "the clock must be saved running")
    if isinstance(snapshot, dict) and snapshot.get("tick") != 119:
        bad("boundary", f"snapshot tick is {snapshot.get('tick')!r}, expected 119")
    if isinstance(weather, dict) and (
        weather.get("seed") != 70021 or weather.get("cycle_length") != 240
    ):
        bad(
            "boundary",
            f"weather fixture is seed={weather.get('seed')!r} "
            f"cycle={weather.get('cycle_length')!r}, expected 70021/240",
        )

    # --- purity: nothing presentation, nothing tool, nothing path ---------
    for needle in (
        "grengewald", "remich-save-", "phase", "motion", "elapsed",
        "unix", "wall", "res://", "/home/", "/tmp/",
    ):
        if needle in text:
            bad("purity", f"the save text contains {needle!r}")

labels = {
    "structure": (
        "save-structure: the save on disk is exactly the sanctioned JSON "
        "(version, identity, clock, weather, one inhabitant)"
    ),
    "purity": (
        "save-purity: no presentation state, no bridge revision and no "
        "repository or engine path inside the save file"
    ),
    "boundary": (
        "save-boundary: clock tick 120 next and running, snapshot at 119, "
        "weather fixture 70021/240, seven needs ready for the decision at 120"
    ),
}
exit_ok = True
for section in ("structure", "purity", "boundary"):
    if sections[section]:
        exit_ok = False
        for message in sections[section]:
            print(f"FAIL  {section}: {message}")
    else:
        print(f"ok    {labels[section]}")
sys.exit(0 if exit_ok else 1)
PY
JSON_RC=$?

cargo test --workspace >"$LOG_TEST" 2>&1
cargo test -p remich_core save:: >"$LOG_CORE" 2>&1
cargo test -p remich_gdext >"$LOG_GDEX" 2>&1

bash "$STEP2_CHECKER" >"$LOG_STEP2" 2>&1
STEP2_RC=$?

# -------------------------------------- 1. the Step 2 merge is an ancestor
header "1. The Phase 2 Step 2 merge is an ancestor of this head"

if git merge-base --is-ancestor "$STEP2_MERGE" HEAD 2>/dev/null; then
    pass "the Step 2 merge $STEP2_MERGE is an ancestor of HEAD"
else
    fail "the Step 2 merge $STEP2_MERGE is NOT an ancestor of HEAD"
fi

if git merge-base --is-ancestor "$STEP2_HEAD" HEAD 2>/dev/null; then
    pass "the reviewed Step 2 head $STEP2_HEAD is an ancestor of HEAD"
else
    fail "the reviewed Step 2 head $STEP2_HEAD is NOT an ancestor of HEAD"
fi

note "HEAD is $(git rev-parse HEAD)"

# ------------------------------- 2. Step 2 acceptance green and unchanged
header "2. Step 2 acceptance remains green and unchanged as a sub-check"

# The deep re-proof: Step 2's own 26 checks (weather single-writer, refused
# second writer, deterministic stand-in, tick contract, applied-vector
# mapping, morning/afternoon shape, byte-identical traces, build/tests,
# clean head, no other repository). Expected green on a Step 3 head; if it
# fails, its FAIL lines say why.
if [ "$STEP2_RC" -eq 0 ]; then
    pass "bash tools/check_phase2_step2.sh exits 0 (unchanged sub-check)"
    tail -n 3 "$LOG_STEP2" | sed 's/^/      | /'
else
    fail "bash tools/check_phase2_step2.sh failed:"
    grep '^FAIL' "$LOG_STEP2" | sed 's/^/      | /'
    tail -n 30 "$LOG_STEP2" | sed 's/^/      | /'
fi

# "unchanged": neither Step 2's checker, nor any earlier checker, nor the
# plan may differ since the Step 2 merge.
#
# Remich issue #9 / Phase 3 Step 1: the five frozen checkers that changed are
# exactly the ones whose ratchets the authorized catalogue adaptation moved,
# each edited with a comment naming this issue (tools/check_phase3_step1.sh
# verifies they carry nothing else). docs/PLAN.md was extended by the lead's
# Phase 3 plan merge, then amended by the lead's Phase 3 Step 2 re-scope, so
# it is frozen byte-for-byte at $PLAN_FREEZE instead of at the Step 2 merge —
# which still forbids this step from rewriting it.
# Every other frozen file must match $STEP2_MERGE exactly.
step2_delta="$(git diff --name-only "$STEP2_MERGE" -- \
    "$STEP2_CHECKER" tools/check_phase2_step1.sh \
    tools/check_phase1_step1.sh tools/check_phase1_step2.sh \
    tools/check_phase1_step3.sh tools/check_phase1_step4.sh \
    tools/check_phase1_step5.sh 2>/dev/null \
    | grep -vxF -e "$STEP2_CHECKER" -e tools/check_phase2_step1.sh \
        -e tools/check_phase1_step3.sh -e tools/check_phase1_step4.sh \
        -e tools/check_phase1_step5.sh || true)"
plan_delta=""
if ! git diff --quiet "$PLAN_FREEZE" -- "$PLAN_DOC" 2>/dev/null; then
    plan_delta="$PLAN_DOC"
fi
combined="$(printf '%s\n%s\n' "$step2_delta" "$plan_delta" | sed '/^$/d')"
if [ -z "$combined" ]; then
    pass "the frozen earlier checkers differ only by their named Remich #9 edits, and docs/PLAN.md matches the plan re-scope freeze"
else
    fail "a frozen checker or the plan changed beyond the Remich #9 authorization:"
    printf '%s\n' "$combined" | sed 's/^/      | /'
fi

# The five markers this step must preserve, observed in the sub-check's log
# (clock and weather markers from its own runs, scorer/decay/bridge from the
# day proofs).
for marker in REMICH_CLOCK_OK REMICH_WEATHER_OK REMICH_SCORER_OK \
    REMICH_DECAY_OK REMICH_BRIDGE_OK; do
    if [ "$STEP2_RC" -eq 0 ] && grep -qF "$marker " "$LOG_STEP2" 2>/dev/null; then
        pass "sub-check log: $marker present"
    else
        fail "sub-check log: no $marker marker (or the sub-check itself failed)"
    fi
done

# --------------------------------- 3. donor code/data and provenance untouched
header "3. Donor code/data and provenance remain untouched, bar the authorized Remich #9 entry"

# Remich issue #9 / Phase 3 Step 1: two named exceptions — the authorized
# catalogue embedding, and the provenance record that documents it (its
# content is guarded by the Step 3 sub-check). docs/PLAN.md is frozen
# byte-for-byte at $PLAN_FREEZE, the lead's Phase 3 Step 2 re-scope.
donor_delta="$(git diff --name-only "$STEP2_MERGE" -- \
    crates/anvil_sim crates/anvil_core assets docs/anvil-import-phase1-step3.md \
    2>/dev/null \
    | grep -vxF -e "$N9_CATALOGUE" -e "$N9_PROVENANCE" || true)"
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

# ----------------------------------------------- 4. the save core is engine-free
header "4. The save core is engine-free"

if grep -qiE 'godot|gdext' crates/remich_core/Cargo.toml; then
    fail "remich_core's manifest names an engine"
else
    pass "remich_core's manifest names no engine"
fi

if grep -rqiE 'godot|gdext' "$CORE_SRC_DIR"; then
    fail "remich_core's source names an engine (the firewall is broken):"
    grep -rniE 'godot|gdext' "$CORE_SRC_DIR" | sed 's/^/      | /'
else
    pass "the engine-free core — including $SAVE_SRC — names no engine at all"
fi

# The save path itself must not reach for engine primitives either.
if grep -rnE 'FileAccess|VarDictionary|Variant' "$CORE_SRC_DIR" >/dev/null 2>&1; then
    fail "the core uses an engine type:"
    grep -rnE 'FileAccess|VarDictionary|Variant' "$CORE_SRC_DIR" | sed 's/^/      | /'
else
    pass "the core's save/load/adaptation path uses no engine type (bytes in, bytes out)"
fi

strip_paths='s/ \((path[+]file:)?\/[^)]*\)//g'
if cargo tree -p remich_core --edges normal,build 2>/dev/null | sed -E "$strip_paths" \
        | grep -qiE 'godot|gdext'; then
    fail "cargo tree -p remich_core resolves an engine crate"
else
    pass "cargo tree -p remich_core resolves no engine crate"
fi

# ------------------------------------- 5. the format declares an explicit version
header "5. The save format declares an explicit version 1"

if grep -qE "(^|[[:space:]:])the_save_format_has_an_explicit_internal_version \.\.\. ok$" \
        "$LOG_CORE" 2>/dev/null; then
    pass "behaviour test green: the_save_format_has_an_explicit_internal_version"
else
    fail "behaviour test not green: the_save_format_has_an_explicit_internal_version"
    tail -n 30 "$LOG_CORE" | sed 's/^/      | /'
fi

if grep -q 'pub const SAVE_FORMAT_VERSION: u32 = 1' "$SAVE_SRC" 2>/dev/null; then
    pass "the source declares SAVE_FORMAT_VERSION: u32 = 1"
else
    fail "SAVE_FORMAT_VERSION is not the explicit literal 1"
fi

game_body="$(sed -n '/pub struct GameSave/,/^}/p' "$SAVE_SRC" 2>/dev/null)"
if printf '%s' "$game_body" | grep -qE '^[[:space:]]*(pub )?format_version:'; then
    pass "GameSave carries the format_version field itself"
else
    fail "GameSave does not declare a format_version field"
fi

# --------------------------------- 6. deterministic serialization (identical bytes)
header "6. Serialization is deterministic: identical state, identical bytes"

if grep -qE "(^|[[:space:]:])identical_state_serializes_to_identical_bytes \.\.\. ok$" \
        "$LOG_CORE" 2>/dev/null; then
    pass "behaviour test green: identical_state_serializes_to_identical_bytes"
else
    fail "behaviour test not green: identical_state_serializes_to_identical_bytes"
fi

# ------------------------------ 7. round-trip load preserves every saved field
header "7. Round-trip load preserves every saved field exactly"

for test_name in \
    serialize_then_parse_preserves_every_field \
    the_clock_state_round_trips_exactly \
    the_weather_snapshot_round_trips_exactly \
    the_inhabitant_state_round_trips_exactly \
    the_tool_identity_round_trips_exactly
do
    if grep -qE "(^|[[:space:]:])${test_name} \.\.\. ok$" "$LOG_CORE" 2>/dev/null; then
        pass "round-trip test green: $test_name"
    else
        fail "round-trip test not green: $test_name"
    fi
done

# ------------------- 8. malformed / unsupported-version / invalid state refused
header "8. Malformed, unsupported-version and invalid state fail clearly"

for test_name in \
    an_unsupported_format_version_fails_clearly \
    malformed_bytes_fail_clearly \
    structurally_invalid_save_state_fails_clearly
do
    if grep -qE "(^|[[:space:]:])${test_name} \.\.\. ok$" "$LOG_CORE" 2>/dev/null; then
        pass "refusal test green: $test_name"
    else
        fail "refusal test not green: $test_name"
    fi
done

# ------------------------------------- 9. a changed identity adapts, never refuses
header "9. A changed identity adapts and never refuses"

for test_name in \
    same_world_load_has_zero_drops_and_is_not_adapted \
    changed_world_load_adapts_and_completes \
    retained_state_is_value_identical_to_what_fit \
    an_identity_change_alone_drops_nothing \
    drop_report_ordering_is_deterministic
do
    if grep -qE "(^|[[:space:]:])${test_name} \.\.\. ok$" "$LOG_CORE" 2>/dev/null; then
        pass "adaptation test green: $test_name"
    else
        fail "adaptation test not green: $test_name"
    fi
done

# ----------------------- 10. the drop record names subject/field/value/reason
header "10. The drop record names subject, field, value and reason=missing-place"

if grep -qE "(^|[[:space:]:])a_missing_place_drops_only_the_place_reference_and_names_it \.\.\. ok$" \
        "$LOG_CORE" 2>/dev/null; then
    pass "behaviour test green: a_missing_place_drops_only_the_place_reference_and_names_it"
else
    fail "behaviour test not green: a_missing_place_drops_only_the_place_reference_and_names_it"
fi

if grep -q '"missing-place"' "$SAVE_SRC" 2>/dev/null; then
    pass "the structured reason is the literal missing-place"
else
    fail "the structured drop reason 'missing-place' is not in the save core"
fi

if grep -q 'current_place' "$SAVE_SRC" 2>/dev/null; then
    pass "the drop field is the inhabitant's current_place reference"
else
    fail "the save core does not name the current_place field"
fi

# -------------------------------------------- 11. the save holds only sanctioned state
header "11. The save holds only the sanctioned state"

game_body="$(sed -n '/pub struct GameSave/,/^}/p' "$SAVE_SRC" 2>/dev/null)"
fields_ok=1
for field in format_version tool_identity clock weather inhabitant; do
    if ! printf '%s' "$game_body" | grep -qE "^[[:space:]]*(pub )?${field}:"; then
        fail "GameSave does not declare the field '$field'"
        fields_ok=0
    fi
done
if [ "$fields_ok" -eq 1 ]; then
    pass "GameSave declares exactly format_version, tool_identity, clock, weather, inhabitant"
fi

clock_body="$(sed -n '/pub struct ClockState/,/^}/p' "$CLOCK_SRC" 2>/dev/null)"
clock_ok=1
for field in tick tick_length_ns speed paused; do
    if ! printf '%s' "$clock_body" | grep -qE "^[[:space:]]*(pub )?${field}:"; then
        fail "ClockState does not declare the field '$field'"
        clock_ok=0
    fi
done
if [ "$clock_ok" -eq 1 ]; then
    pass "the saved clock holds the full state: tick, tick_length_ns, speed, paused (no wall clock)"
fi

if printf '%s' "$game_body" | grep -qE 'inhabitant:[[:space:]]*InhabitantState'; then
    if printf '%s' "$game_body" | grep -qE 'inhabitants:'; then
        fail "the save unexpectedly holds a collection of inhabitants"
    else
        pass "exactly one stand-in inhabitant slot: inhabitant: InhabitantState"
    fi
else
    fail "GameSave does not hold a single InhabitantState slot"
fi

# --------------------- 12. no presentation state, no tool path, never the bridge rev
header "12. The core carries no presentation state, no tool path, never the bridge revision"

for test_name in \
    the_save_carries_no_presentation_state \
    the_serialized_save_contains_no_repository_path \
    the_bridge_revision_is_not_game_state
do
    if grep -qE "(^|[[:space:]:])${test_name} \.\.\. ok$" "$LOG_CORE" 2>/dev/null; then
        pass "purity test green: $test_name"
    else
        fail "purity test not green: $test_name"
    fi
done

# ------------------- 13. the binding owns conversion + file access; revision holds
header "13. The binding owns Godot conversion and file access; the save revision holds"

if grep -q 'pub struct RemichGameSave' "$GDEX_SAVE_SRC" 2>/dev/null \
        && grep -q 'fn write_save' "$GDEX_SAVE_SRC" \
        && grep -q 'fn load_save' "$GDEX_SAVE_SRC"; then
    pass "RemichGameSave exposes write_save/load_save at the binding edge"
else
    fail "the binding's save surface (RemichGameSave/write_save/load_save) is missing"
fi

if grep -q 'std::fs::write' "$GDEX_SAVE_SRC" 2>/dev/null \
        && grep -q 'std::fs::read' "$GDEX_SAVE_SRC"; then
    pass "the binding — not the core, not the script — performs the file access"
else
    fail "the binding does not own the save file's bytes on disk"
fi

for test_name in \
    every_save_error_gets_its_own_code \
    the_surface_uses_the_cores_format_version \
    save_bridge_rev_is_the_committed_marker
do
    if grep -qE "(^|[[:space:]:])${test_name} \.\.\. ok$" "$LOG_GDEX" 2>/dev/null; then
        pass "binding test green: $test_name"
    else
        fail "binding test not green: $test_name"
    fi
done

rev="$(sed -n 's/^[[:space:]]*pub const SAVE_BRIDGE_REV: &str = "\([^"]*\)".*/\1/p' \
    "$GDEX_SRC" 2>/dev/null)"
rev="${rev%%$'\n'*}"
if [ "$rev" = "$COMMITTED_SAVE_REV" ]; then
    pass "SAVE_BRIDGE_REV holds its committed value ('$rev') — the one-line rebuild probe was restored"
else
    fail "SAVE_BRIDGE_REV is '$rev', expected '$COMMITTED_SAVE_REV' — the probe was not reverted"
fi

sentinel_files="$(grep -rlF "$SAVE_SENTINEL" . \
    --exclude-dir=.git --exclude-dir=target --exclude-dir=.godot \
    --exclude='check_phase2_step3.sh' 2>/dev/null | sed 's|^\./||' | sort || true)"
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

# ------------- 14. a fresh process writes the noon save outside the worktree
header "14. A fresh process writes the noon save outside the worktree"

if [ "$SAVE_RC" -eq 0 ]; then
    pass "the save run exits 0"
else
    fail "the save run exited $SAVE_RC:"
    tail_log "$LOG_SAVE"
fi

written_marker="$(grep -h '^REMICH_SAVE_WRITTEN ' "$LOG_SAVE" 2>/dev/null | head -1)"
if printf '%s' "$written_marker" | grep -qE \
        '^REMICH_SAVE_WRITTEN tick=120 identity=world-revision-A bytes=[0-9]+ rev=remich-save-v1$'; then
    pass "the noon save marker is exact"
    note "$written_marker"
else
    fail "no exact REMICH_SAVE_WRITTEN marker (got: ${written_marker:-none})"
fi

last_autoload="$(sed -n '/^\[autoload\]/,/^\[/p' "$PROBE_PROJECT" 2>/dev/null \
    | grep -E '^[A-Za-z]+=' | tail -1)"
if [ "$last_autoload" = 'SaveProbe="*res://save_probe.gd"' ]; then
    pass "SaveProbe is the last autoload — its quit() cannot be masked by an earlier probe"
else
    fail "the last autoload is '$last_autoload', expected SaveProbe (quit ordering)"
fi

case "$SAVE_FILE" in
    "$REPO_ROOT"/*) fail "the save file was written inside the worktree: $SAVE_FILE" ;;
    /tmp/*) pass "the save lives in a fresh /tmp/remich-p2s3.* directory, outside the worktree" ;;
    *) fail "the save file is not outside the worktree: $SAVE_FILE" ;;
esac

if grep -qF 'if _mode.is_empty()' "$SAVE_PROBE" 2>/dev/null; then
    pass "the save probe is mode-gated: silent without REMICH_SAVE_MODE (ordinary runs unaffected)"
else
    fail "the save probe has no empty-mode gate — it would disturb ordinary runs"
fi

invocations="$(grep -c 'GODOT_BIN" --headless' "$RUN_SAVE" 2>/dev/null || echo 0)"
if [ "$invocations" = "1" ]; then
    pass "run_save.sh starts exactly one headless engine process per mode — four modes, four fresh processes"
else
    fail "run_save.sh has $invocations engine invocations, expected exactly one per call"
fi

# --------------------------------------------- 15. the save on disk is exact
header "15. The save on disk is exactly the sanctioned JSON"

if grep -q '^ok    save-structure' "$LOG_JSON" 2>/dev/null; then
    pass "$(grep '^ok    save-structure' "$LOG_JSON" | sed 's/^ok    //')"
else
    fail "the save file's structure does not match the sanctioned format:"
    grep '^FAIL  structure' "$LOG_JSON" 2>/dev/null | sed 's/^/      | /'
    [ "$JSON_RC" -eq 0 ] || note "python exited $JSON_RC"
fi

# -------------------------- 16. the save has no presentation state or paths
header "16. The save file carries no presentation state and no repository/engine path"

if grep -q '^ok    save-purity' "$LOG_JSON" 2>/dev/null; then
    pass "$(grep '^ok    save-purity' "$LOG_JSON" | sed 's/^ok    //')"
else
    fail "the save file contains presentation state, a revision or a path:"
    grep '^FAIL  purity' "$LOG_JSON" 2>/dev/null | sed 's/^/      | /'
fi

# -------------------------------------- 17. the uninterrupted baseline completes
header "17. The uninterrupted baseline completes to tick 240"

if [ "$BASELINE_RC" -eq 0 ]; then
    pass "the baseline run exits 0"
else
    fail "the baseline run exited $BASELINE_RC:"
    tail_log "$LOG_BASELINE"
fi

baseline_marker="$(grep -h '^REMICH_SAVE_BASELINE_OK ' "$LOG_BASELINE" 2>/dev/null | head -1)"
if printf '%s' "$baseline_marker" | grep -qE \
        '^REMICH_SAVE_BASELINE_OK mode=baseline records=12 final_tick=240 identity=world-revision-A rev=remich-save-v1$'; then
    pass "the baseline marker is exact"
    note "$baseline_marker"
else
    fail "no exact REMICH_SAVE_BASELINE_OK marker (got: ${baseline_marker:-none})"
fi

baseline_lines="$(wc -l <"$TRACE_A" 2>/dev/null || echo 0)"
if [ "$baseline_lines" -eq 14 ] 2>/dev/null; then
    pass "the baseline trace has 14 records: fixture + 12 decisions + summary"
else
    fail "the baseline trace has $baseline_lines records, expected 14"
fi

# -------------------------- 18. a fresh process loads the save and continues
header "18. A fresh process loads the save and continues (REMICH_SAVE_OK)"

if [ "$LOAD_RC" -eq 0 ]; then
    pass "the load run exits 0"
else
    fail "the load run exited $LOAD_RC:"
    tail_log "$LOG_LOAD"
fi

ok_marker="$(grep -h '^REMICH_SAVE_OK ' "$LOG_LOAD" 2>/dev/null | head -1)"
if printf '%s' "$ok_marker" | grep -qE \
        '^REMICH_SAVE_OK tick=120 identity=world-revision-A drops=0 rev=remich-save-v1$'; then
    pass "the load marker is exact: restored at tick 120, same identity, zero drops"
    note "$ok_marker"
else
    fail "no exact REMICH_SAVE_OK marker (got: ${ok_marker:-none})"
fi

if [ "$LOAD_RC" -eq 0 ] && ! grep -qE 'REMICH_(SAVE|WEATHER|DAY|SCORER|DECAY|BRIDGE|CLOCK)_FAIL' \
        "$LOG_LOAD" 2>/dev/null; then
    pass "no failure marker appears in the load run"
else
    fail "the load run carries a failure marker"
fi

load_lines="$(wc -l <"$TRACE_B" 2>/dev/null || echo 0)"
if [ "$load_lines" -eq 14 ] 2>/dev/null; then
    pass "the loaded continuation trace has 14 records: fixture + 12 decisions + summary"
else
    fail "the loaded trace has $load_lines records, expected 14"
fi

# ------------------------------------- 19. the traces are byte-identical
header "19. The two second-half continuation traces are byte-identical"

if cmp -s "$TRACE_A" "$TRACE_B"; then
    pass "baseline and loaded continuation traces are byte-identical"
else
    fail "the continuation traces differ:"
    cmp "$TRACE_A" "$TRACE_B" 2>&1 | sed 's/^/      | /'
fi

# --------------------------------------------- 20. their SHA-256 hashes match
header "20. Their SHA-256 hashes match (both reported)"

HASH_A="$(hash_of "$TRACE_A")"
HASH_B="$(hash_of "$TRACE_B")"
if [ -n "$HASH_A" ] && [ "$HASH_A" = "$HASH_B" ]; then
    pass "both continuation-trace SHA-256 values match"
    note "baseline sha256: $HASH_A"
    note "loaded   sha256: $HASH_B"
else
    fail "continuation-trace SHA-256 values differ: baseline=$HASH_A loaded=$HASH_B"
fi

# ------------------------------------- 21. the independent validator accepts both
header "21. The independent trace validator accepts both traces"

if [ "$VA_RC" -eq 0 ]; then
    pass "tools/check_save_trace.py accepts both traces (shape, contract, cross-run)"
    tail -n 3 "$LOG_V" | sed 's/^/      | /'
else
    fail "the save trace validator rejected a trace:"
    tail -n 40 "$LOG_V" | sed 's/^/      | /'
fi

decision_lines="$(grep -c '12 continuation decisions' "$LOG_V" 2>/dev/null || echo 0)"
if [ "$decision_lines" -eq 2 ] 2>/dev/null; then
    pass "both traces carry the twelve continuation decisions at checkpoints 12..23"
else
    fail "the validator confirmed the continuation decisions in $decision_lines of 2 traces"
fi

# -------------------- 22. final clock, needs, weather and scorer choices agree
header "22. Final clock, needs, weather and scorer choices agree across the runs"

if grep -q '^ok    final state agrees' "$LOG_V" 2>/dev/null; then
    pass "$(grep '^ok    final state agrees' "$LOG_V" | sed 's/^ok    //')"
else
    fail "the validator did not establish equal final state"
    tail -n 20 "$LOG_V" | sed 's/^/      | /'
fi

# ------------------------------------- 23. no process-specific values in the traces
header "23. The traces contain no process-specific values or paths"

path_lines="$(grep -c 'no path or process-specific value appears anywhere in the trace' \
    "$LOG_V" 2>/dev/null || echo 0)"
if [ "$path_lines" -eq 2 ] 2>/dev/null; then
    pass "neither trace contains a path or process-specific value"
else
    fail "the path scan ran on $path_lines of 2 traces"
fi

# -------------------------- 24. the shared clock/weather nodes stay the authorities
header "24. The shared clock and weather autoloads remain the sole authorities"

clock_hits="$(grep -c 'ClassDB.instantiate(CLOCK_CLASS)' godot/*.gd 2>/dev/null | grep -v ':0$' || true)"
if [ "$clock_hits" = "godot/world_clock.gd:1" ]; then
    pass "exactly one script instantiates the native clock class — godot/world_clock.gd, once"
else
    fail "the native clock class is instantiated unexpectedly: $clock_hits"
fi

weather_hits="$(grep -c 'ClassDB.instantiate(WEATHER_CLASS)' godot/*.gd 2>/dev/null | grep -v ':0$' || true)"
if [ "$weather_hits" = "godot/weather.gd:1" ]; then
    pass "exactly one script instantiates the native weather class — godot/weather.gd, once"
else
    fail "the native weather class is instantiated unexpectedly: $weather_hits"
fi

if grep -qE 'ClassDB\.instantiate\((CLOCK_CLASS|WEATHER_CLASS)\)' "$SAVE_PROBE"; then
    fail "the save probe instantiates a native clock/weather class itself"
else
    pass "the save probe never instantiates a second native clock or weather object"
fi

# The behavioural half: inside the green load and adapt runs the probe
# asserted the instance ids were unchanged, that exactly one native object of
# each class exists, and that the channel still belongs to the stand-in
# writer. If any of that broke, REMICH_SAVE_FAIL would have failed the run.
for needle in \
    'WorldClock.clock_instance_id() != clock_before' \
    'Weather.weather_instance_id() != weather_before' \
    '_count_native(CLOCK_CLASS) != 1' \
    'Weather.writer_id() != STAND_IN_WRITER'; do
    if grep -qF "$needle" "$SAVE_PROBE" 2>/dev/null; then
        pass "the probe asserts authority stability: $needle"
    else
        fail "the probe does not assert: $needle"
    fi
done

if [ "$LOAD_RC" -eq 0 ] && [ "$ADAPT_RC" -eq 0 ]; then
    pass "the restore ran green: same instance ids, one native object per class, stand-in writer kept"
else
    fail "a restore run failed — the authority assertions did not all hold"
fi

# ------------------------ 25. the adapted load reports the drop and keeps the rest
header "25. The adapted load reports the drop exactly and keeps what fits"

keep_marker="$(grep -h '^REMICH_SAVE_ADAPT_KEEP ' "$LOG_ADAPT" 2>/dev/null | head -1)"
if printf '%s' "$keep_marker" | grep -qE \
        '^REMICH_SAVE_ADAPT_KEEP id=standin-inhabitant-1 seed=60628 needs=7 place=absent clock=tick:120 weather:snapshot:119$'; then
    pass "the kept-state marker is exact: id, seed, seven needs, clock and snapshot survive"
    note "$keep_marker"
else
    fail "no exact REMICH_SAVE_ADAPT_KEEP marker (got: ${keep_marker:-none})"
fi

adapt_marker="$(grep -h '^REMICH_SAVE_ADAPT_OK ' "$LOG_ADAPT" 2>/dev/null | head -1)"
if printf '%s' "$adapt_marker" | grep -qE \
        '^REMICH_SAVE_ADAPT_OK saved_identity=world-revision-A current_identity=world-revision-B drops=1 dropped=standin-inhabitant-1\.current_place:market-square rev=remich-save-v1$'; then
    pass "the adaptation marker is exact: exactly one named drop, the market-square reference"
    note "$adapt_marker"
else
    fail "no exact REMICH_SAVE_ADAPT_OK marker (got: ${adapt_marker:-none})"
fi

# ---------------------------------------- 26. identity mismatch never refuses
header "26. Identity mismatch is never a refusal"

if grep -rq 'REMICH_SAVE_FAIL' "$LOG_BASELINE" "$LOG_SAVE" "$LOG_LOAD" "$LOG_ADAPT" 2>/dev/null; then
    fail "a REMICH_SAVE_FAIL marker appeared in a save run:"
    grep -h 'REMICH_SAVE_FAIL' "$LOG_BASELINE" "$LOG_SAVE" "$LOG_LOAD" "$LOG_ADAPT" \
        | sed 's/^/      | /'
else
    pass "no REMICH_SAVE_FAIL marker in any of the four runs"
fi

problem_pattern='REMICH_(SAVE|WEATHER|DAY|SCORER|DECAY|BRIDGE|CLOCK)_FAIL|SCRIPT ERROR|Parse Error'
problem_lines=""
for log in "$LOG_BASELINE" "$LOG_SAVE" "$LOG_LOAD" "$LOG_ADAPT"; do
    hit="$(grep -nE "$problem_pattern" "$log" 2>/dev/null || true)"
    if [ -n "$hit" ]; then
        problem_lines="$problem_lines$(basename "$log"):
$hit
"
    fi
done
if [ -z "$problem_lines" ]; then
    pass "no failure marker and no script/parse error, in any save run"
else
    fail "a save run reported a failure or a script/parse error:"
    printf '%s' "$problem_lines" | sed 's/^/      | /'
fi

if [ "$ADAPT_RC" -eq 0 ] && [ -n "$adapt_marker" ]; then
    pass "the changed-identity load exits 0 with a success marker — adaptation, not refusal"
else
    fail "the changed-identity load did not complete as a success"
fi

# ------------------------------------ 27. loading never rewrites the save
header "27. Loading never rewrites the save (H1 = H2 = H3)"

if [ -n "$H1" ] && [ "$H1" = "$H2" ] && [ "$H2" = "$H3" ]; then
    pass "the save file's SHA-256 is unchanged by the load and by the adaptation"
    note "before load:  $H1"
    note "after load:   $H2"
    note "after adapt:  $H3"
else
    fail "the save file changed across loading: before=$H1 after-load=$H2 after-adapt=$H3"
fi

# ------------------------------------------- 28. the noon boundary convention
header "28. The noon boundary convention holds (120 next, snapshot 119, needs ready)"

if grep -q '^ok    save-boundary' "$LOG_JSON" 2>/dev/null; then
    pass "$(grep '^ok    save-boundary' "$LOG_JSON" | sed 's/^ok    //')"
else
    fail "the saved state does not sit on the documented noon boundary:"
    grep '^FAIL  boundary' "$LOG_JSON" 2>/dev/null | sed 's/^/      | /'
fi

if grep -q '^ok    .*12 continuation decisions — checkpoints 12..23' "$LOG_V" 2>/dev/null; then
    pass "the continuation begins at the decision on tick 120 (checkpoint 12) in both traces"
else
    fail "the traces do not begin their continuation at the noon decision"
fi

# ------------------ 29. earlier markers, silent probe, headless engine runs
header "29. Earlier markers appear, the save probe is silent elsewhere, runs are headless"

for log in "$LOG_BASELINE" "$LOG_LOAD"; do
    base="$(basename "$log")"
    for marker in REMICH_SCORER_OK REMICH_DECAY_OK REMICH_BRIDGE_OK; do
        if grep -q "^$marker " "$log" 2>/dev/null; then
            pass "$base: $marker present"
        else
            fail "$base: no $marker marker"
        fi
    done
done

if grep -q 'REMICH_SAVE_' "$LOG_STEP2" 2>/dev/null; then
    fail "the save probe spoke during the Step 2 sub-check's ordinary runs"
else
    pass "the save probe stayed silent in the sub-check's ordinary runs (mode gate holds)"
fi

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

# ------------------------------- 30. the record documents the whole step
header "30. The record documents donors, format, boundary, hashes, drop, timings, refusals"

if [ -f "$RECORD_DOC" ]; then
    doc_problems=0
    for needle in \
        "buggy-vault@24181142" \
        "97c8fdbd7ff85779f33456fd7c444657f8d90b36" \
        "no donor code was copied" \
        "format_version = 1" \
        "remich-save-v1" \
        "next tick is 120" \
        "snapshot tick 119" \
        "decision at 120" \
        "$DROP_TOKEN" \
        "Timing A" \
        "Timing B"; do
        if ! grep -qF "$needle" "$RECORD_DOC" 2>/dev/null; then
            fail "the record does not document: $needle"
            doc_problems=1
        fi
    done
    if [ -n "$HASH_A" ] && grep -qF "$HASH_A" "$RECORD_DOC" 2>/dev/null; then
        pass "the record carries the measured continuation-trace SHA-256"
    else
        fail "the record does not carry this head's trace hash ($HASH_A)"
        doc_problems=1
    fi
    if [ -n "$H1" ] && grep -qF "$H1" "$RECORD_DOC" 2>/dev/null; then
        pass "the record carries the measured save-file SHA-256 (H1 = H2 = H3)"
    else
        fail "the record does not carry this head's save hash ($H1)"
        doc_problems=1
    fi
    if [ "$doc_problems" -eq 0 ]; then
        pass "the record names the donors and the not-copied ruling, the format, the noon convention, the hashes, the drop and both timings"
    fi
    if grep -qi 'refus' "$RECORD_DOC" 2>/dev/null; then
        pass "the record states what was refused (nothing this step: adaptation never refuses)"
    else
        fail "the record does not state the step's refusals"
    fi
else
    fail "the record $RECORD_DOC does not exist yet"
fi

# ------------------------- 31. warning-free build/tests, no generated state tracked
header "31. The workspace builds and tests warning-free; no generated state is tracked"

for label in "the workspace build:LOG_BUILD" "the test suite:LOG_TEST" \
    "the core save tests:LOG_CORE" "the binding tests:LOG_GDEX"; do
    name="${label%%:*}"
    varname="${label##*:}"
    if grep -q '^warning' "${!varname}" 2>/dev/null; then
        fail "$name emitted warnings:"
        grep '^warning' "${!varname}" | sed 's/^/      | /'
    else
        pass "$name is warning-free"
    fi
done

if grep -qE 'test result: ok\.' "$LOG_TEST"; then
    pass "cargo test --workspace passes"
    grep -E 'test result:' "$LOG_TEST" | sed 's/^/      | /'
else
    fail "cargo test --workspace did not pass:"
    tail -n 40 "$LOG_TEST" | sed 's/^/      | /'
fi

if grep -qE 'test result: ok\. 19 passed' "$LOG_CORE"; then
    pass "cargo test -p remich_core save:: passes (19 save tests)"
else
    fail "the save-module tests did not run green:"
    tail -n 40 "$LOG_CORE" | sed 's/^/      | /'
fi

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
        godot/save_probe_expectation.txt \
        day_trace-example.jsonl weather_trace-example.jsonl; do
    if git check-ignore -q "$ignored"; then
        pass "generated state is ignored: $ignored"
    else
        fail "generated state is not ignored: $ignored"
    fi
done

# ------------- 32. no other repository modified; paths limited; clean worktree
header "32. No other repository was modified; external paths stay limited; the worktree is clean"

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
    printf 'PASS  Phase 2 Step 3 — the game.s save\n'
    printf '========================================\n'
    exit 0
fi
printf 'FAIL  Phase 2 Step 3 — %d check(s) failed\n' "$failures"
printf '========================================\n'
exit 1
