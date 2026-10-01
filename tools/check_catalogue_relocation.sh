#!/usr/bin/env bash
# Remich issue #9 / Phase 3 Step 1 — relocation proof for the embedded
# action catalogue (docs/PLAN.md §4b step 1; record:
# docs/remich-catalogue-phase3-step1.md).
#
# One command, from anywhere:
#
#     bash tools/check_catalogue_relocation.sh
#
# The defining acceptance of Remich #9: the built library must still work
# after the checkout it was built in no longer exists at the path used during
# compilation. Before the adaptation, `crates/anvil_sim/src/actions/catalogue.rs`
# resolved `assets/sim/actions.json` through `repo_path!`, which bakes
# CARGO_MANIFEST_DIR into the library — Larochette built Remich in a
# temporary checkout, deleted it, and the first `score_activity` panicked.
#
# Proof, entirely inside a disposable directory (the real worktree is never
# moved, and no other repository is touched):
#
#   1. a fresh directory under the system temporary directory;
#   2. the current committed HEAD exported into <tmp>/build-checkout;
#   3. `cargo build --workspace` there — the one and only build of this
#      script, and always before the move;
#   4. the library exists, and the committed asset exists at the build-time
#      path with its qualified sha256;
#   5. the whole directory is renamed to <tmp>/moved-checkout;
#   6. the original build-checkout path (the path the pre-#9 implementation
#      would have baked in) is proven absent, before anything is scored;
#   7. no cargo is invoked after the move: only staging and the existing
#      Godot test project run, from inside the moved checkout;
#   8. pinned Godot 4.7.2 runs the normal Remich day through the real
#      GDExtension — which calls score_activity at every checkpoint — and it
#      must report REMICH_SCORER_OK and REMICH_DAY_OK with the canonical
#      day-trace SHA-256;
#   9. the temporary directory is removed on exit.
#
# On the pre-issue-#9 implementation this fails at step 6/8: the baked asset
# path points into the directory renamed away, the catalogue cannot load, and
# neither marker appears. Nothing here proves relocation by rebuilding after
# the move.
set -uo pipefail

REPO_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)" || exit 1
cd "$REPO_ROOT" || exit 1

CANONICAL_DAY_SHA="6a5c78729a519163a16d2e754ed74d63ff0a3b9d0a957ef19b8543a89fe4ce2b"
DATA_SHA="166104ba90e30446adfb8d15ec6e242a52567c979bccb274a7011296b163dba5"
# Qualified headless path only: never editor, import or export mode.
GODOT_BIN="/home/mrg/Documents/Project/Yolanda/.godot-local/engine/4.7.2/Godot_v4.7.2-stable_linux.x86_64"
LIBRARY="target/debug/libremich_gdext.so"

failures=0
pass() { printf 'ok    %s\n' "$1"; }
fail() { printf 'FAIL  %s\n' "$1"; failures=$((failures + 1)); }
note() { printf '      %s\n' "$1"; }

HEAD_SHA="$(git rev-parse HEAD 2>/dev/null)" || {
    echo "relocation: cannot read HEAD" >&2
    exit 1
}

ROOT="$(mktemp -d "${TMPDIR:-/tmp}/remich-relocate.XXXXXX")" || exit 1
BUILD="$ROOT/build-checkout"
MOVED="$ROOT/moved-checkout"
DAY_LOG="$ROOT/day.log"
DAY_TRACE="$ROOT/relocated-day.jsonl"
trap 'rm -rf "$ROOT"' EXIT

# ------------------------------------------------- 1. export the committed head
printf '== relocation proof (Remich #9 / Phase 3 Step 1) ==\n'
note "committed head: $HEAD_SHA"

stray="$(git status --porcelain 2>/dev/null)"
if [ -z "$stray" ]; then
    pass "the worktree is clean, so HEAD is exactly the source under test"
else
    fail "the worktree is dirty — the exported head would not be the source under test"
    printf '%s\n' "$stray" | head -n 5 | sed 's/^/      | /'
fi

mkdir -p "$BUILD" || exit 1
if git archive --format=tar "$HEAD_SHA" | tar -x -C "$BUILD"; then
    pass "exported $HEAD_SHA into $BUILD"
else
    fail "could not export HEAD into the build checkout"
    exit 1
fi

if [ -f "$BUILD/assets/sim/actions.json" ]; then
    build_asset_sha="$(sha256sum "$BUILD/assets/sim/actions.json" | cut -d' ' -f1)"
    if [ "$build_asset_sha" = "$DATA_SHA" ]; then
        pass "the committed asset exists at the build-time path with its qualified sha256"
    else
        fail "the exported asset sha256 is '$build_asset_sha', expected $DATA_SHA"
    fi
else
    fail "assets/sim/actions.json is missing from the exported checkout"
fi

# ------------------------------------------------------- 2. build before moving
# The one and only cargo invocation in this script. Everything below the
# marker "THE MOVE" must run without cargo — tools/check_phase3_step1.sh
# asserts that structurally as well as behaviourally.
if (cd "$BUILD" && cargo build --workspace >"$ROOT/build.log" 2>&1); then
    pass "cargo build --workspace succeeded in the build checkout (before the move)"
else
    fail "cargo build --workspace failed in the build checkout:"
    tail -n 30 "$ROOT/build.log" | sed 's/^/      | /'
    exit 1
fi

if [ -f "$BUILD/$LIBRARY" ]; then
    pass "the extension library exists at $LIBRARY"
else
    fail "$LIBRARY was not produced"
    exit 1
fi
lib_sha_before="$(sha256sum "$BUILD/$LIBRARY" | cut -d' ' -f1)"
lib_mtime_before="$(stat -c %Y "$BUILD/$LIBRARY")"

# =============================================== THE MOVE: no cargo below this
# ============================================================== line ==========
if mv "$BUILD" "$MOVED"; then
    pass "moved the entire build checkout to the new path"
else
    fail "could not move the build checkout"
    exit 1
fi

if [ ! -e "$BUILD" ]; then
    pass "old build checkout: absent ($BUILD)"
else
    fail "the old build checkout still exists: $BUILD"
fi

# This is precisely the path the pre-#9 loader baked in at compile time
# (repo_path! -> CARGO_MANIFEST_DIR of crates/anvil_sim, two levels up, joined
# with assets/sim/actions.json). Its absence is what the old implementation
# could not survive.
if [ ! -e "$BUILD/assets/sim/actions.json" ]; then
    pass "baked runtime asset path of the pre-#9 implementation: absent"
else
    fail "the baked runtime asset path still exists: $BUILD/assets/sim/actions.json"
fi

if [ -f "$MOVED/$LIBRARY" ] && [ -f "$MOVED/assets/sim/actions.json" ]; then
    pass "new checkout: present, with its library and its committed asset"
else
    fail "the moved checkout is missing its library or its asset"
    exit 1
fi

note "cargo after move: none (see the marker above; asserted again by check_phase3_step1)"

# ------------------------------------ 3. stage and run the real Godot project
cd "$MOVED" || exit 1
if [ -x "$GODOT_BIN" ]; then
    pass "the pinned engine exists at the qualified path"
else
    fail "the pinned engine is missing at $GODOT_BIN"
fi

bash tools/run_day.sh "$DAY_TRACE" 1 >"$DAY_LOG" 2>&1
day_rc=$?
cd "$REPO_ROOT" || exit 1

if [ "$day_rc" -eq 0 ]; then
    pass "the relocated day run exits 0 (staging + pinned Godot 4.7.2, no rebuild)"
else
    fail "the relocated day run exited $day_rc:"
    tail -n 30 "$DAY_LOG" | sed 's/^/      | /'
fi

if grep -qF 'REMICH_SCORER_OK' "$DAY_LOG" 2>/dev/null; then
    pass "REMICH_SCORER_OK: present — score_activity ran from the moved checkout"
else
    fail "REMICH_SCORER_OK: absent in the relocated run"
fi

if grep -qF 'REMICH_DAY_OK' "$DAY_LOG" 2>/dev/null; then
    pass "REMICH_DAY_OK: present"
else
    fail "REMICH_DAY_OK: absent in the relocated run"
fi

# ------------------------------------------- 4. the library used was the one
# --------------------------------------------------------- built before the move
lib_sha_after="$(sha256sum "$MOVED/$LIBRARY" 2>/dev/null | cut -d' ' -f1)"
lib_mtime_after="$(stat -c %Y "$MOVED/$LIBRARY" 2>/dev/null || echo missing)"
if [ "$lib_sha_after" = "$lib_sha_before" ] && [ "$lib_mtime_after" = "$lib_mtime_before" ]; then
    pass "the library the run used is byte-identical and unrebuilt since the pre-move build"
else
    fail "the library changed across the run — something rebuilt after the move"
    note "sha before=$lib_sha_before after=$lib_sha_after mtime before=$lib_mtime_before after=$lib_mtime_after"
fi

# --------------------------------------------------- 5. the relocated day trace
if [ -s "$DAY_TRACE" ]; then
    day_sha="$(sha256sum "$DAY_TRACE" | cut -d' ' -f1)"
    pass "relocated day SHA-256: $day_sha"
    if [ "$day_sha" = "$CANONICAL_DAY_SHA" ]; then
        pass "the relocated day trace equals the canonical qualified trace"
    else
        fail "the relocated day trace sha256 is '$day_sha', expected $CANONICAL_DAY_SHA"
    fi
else
    fail "the relocated run wrote no day trace"
fi

# ------------------------------------------------------------------ summary
printf '\nrelocation-proof: old build checkout: absent\n'
printf 'relocation-proof: new checkout: present\n'
printf 'relocation-proof: cargo after move: none\n'
printf 'relocation-proof: REMICH_SCORER_OK: %s\n' \
    "$(grep -qF 'REMICH_SCORER_OK' "$DAY_LOG" 2>/dev/null && echo present || echo absent)"
printf 'relocation-proof: REMICH_DAY_OK: %s\n' \
    "$(grep -qF 'REMICH_DAY_OK' "$DAY_LOG" 2>/dev/null && echo present || echo absent)"
printf 'relocation-proof: relocated day SHA-256: %s\n' "${day_sha:-missing}"
if [ "$failures" -eq 0 ]; then
    printf 'relocation-proof: PASS\n'
    exit 0
fi
printf 'relocation-proof: FAIL (%d check(s) failed)\n' "$failures"
exit 1
