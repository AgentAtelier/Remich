#!/usr/bin/env bash
# Phase 1, Step 1 acceptance check — "The repository's shape" (docs/PLAN.md).
#
# One command, from anywhere:
#
#     bash tools/check_phase1_step1.sh
#
# It verifies that the Step 1 shape still exists and fails loudly if any part
# of it is removed. Checks:
#
#   1. the Cargo workspace is valid and holds separate core and binding crates;
#   2. the Rust toolchain is pinned to an exact version (no `stable` alias);
#   3. the engine-free core has no engine dependency and no engine API use;
#   4. the workspace builds and tests successfully;
#   5. the Godot test project exists;
#   6. the pinned Godot 4.7.2 opens that project successfully, headless;
#   7. the README still states Remich's ownership boundary;
#   8. generated build state (Cargo target/, Godot .godot/) is not committed.

set -uo pipefail

REPO_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)" || exit 1
cd "$REPO_ROOT" || exit 1

GODOT_BIN="/home/mrg/Documents/Project/Yolanda/.godot-local/engine/4.7.2/Godot_v4.7.2-stable_linux.x86_64"
GODOT_PROJECT="godot"
TOOLCHAIN_FILE="rust-toolchain.toml"
CORE_DIR="crates/remich_core"
BINDING_DIR="crates/remich_gdext"

LOG_DIR="$(mktemp -d "${TMPDIR:-/tmp}/remich-p1s1.XXXXXX")" || exit 1
trap 'rm -rf "$LOG_DIR"' EXIT

failures=0
pass() { printf 'ok    %s\n' "$1"; }
fail() { printf 'FAIL  %s\n' "$1"; failures=$((failures + 1)); }
note() { printf '      %s\n' "$1"; }
header() { printf '\n== %s ==\n' "$1"; }

# ---------------------------------------------------------------- 1. workspace
header "1. Cargo workspace is valid with separate core and binding crates"

meta=""
if meta="$(cargo metadata --format-version 1 --no-deps 2>/dev/null)"; then
    pass "cargo metadata --format-version 1 --no-deps reads the workspace"
else
    fail "cargo metadata cannot read the workspace"
fi

if [ -n "$meta" ]; then
    core_manifest="$(jq -r '.packages[] | select(.name=="remich_core") | .manifest_path' <<<"$meta")"
    bind_manifest="$(jq -r '.packages[] | select(.name=="remich_gdext") | .manifest_path' <<<"$meta")"

    if [ -n "$core_manifest" ]; then
        pass "workspace contains the core crate remich_core"
    else
        fail "workspace has no crate named remich_core"
    fi

    if [ -n "$bind_manifest" ]; then
        pass "workspace contains the binding crate remich_gdext"
    else
        fail "workspace has no crate named remich_gdext"
    fi

    if [ -n "$core_manifest" ] && [ -n "$bind_manifest" ]; then
        if [ "$core_manifest" != "$bind_manifest" ]; then
            pass "core and binding are separate crates with separate manifests"
        else
            fail "core and binding share a manifest"
        fi
        case "$core_manifest" in
            */crates/remich_core/*) pass "core lives apart at $CORE_DIR" ;;
            *) fail "core manifest is not at $CORE_DIR: $core_manifest" ;;
        esac
        case "$bind_manifest" in
            */crates/remich_gdext/*) pass "binding lives apart at $BINDING_DIR" ;;
            *) fail "binding manifest is not at $BINDING_DIR: $bind_manifest" ;;
        esac
    fi
fi

# -------------------------------------------------------------- 2. toolchain
header "2. The Rust toolchain is pinned exactly"

channel=""
if [ -f "$TOOLCHAIN_FILE" ]; then
    pass "$TOOLCHAIN_FILE exists"
    channel="$(sed -n 's/^[[:space:]]*channel[[:space:]]*=[[:space:]]*"\([^"]*\)".*/\1/p' "$TOOLCHAIN_FILE" | head -n 1)"
    if [ -z "$channel" ]; then
        fail "$TOOLCHAIN_FILE declares no channel="
    elif printf '%s' "$channel" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+$'; then
        pass "channel pins an exact version: $channel"
    else
        fail "channel '$channel' is not an exact version (unpinned stable/beta/nightly aliases are not allowed)"
    fi
else
    fail "$TOOLCHAIN_FILE is missing — the toolchain is not pinned"
fi

rustc_vv="$(rustc -Vv 2>/dev/null)"
rustc_release="$(printf '%s\n' "$rustc_vv" | sed -n 's/^release: //p')"
note "rustc -Vv in use:"
printf '%s\n' "$rustc_vv" | sed 's/^/      | /'

if [ -n "$channel" ] && [ "$rustc_release" = "$channel" ]; then
    pass "rustc -Vv release ($rustc_release) matches the pinned channel"
else
    fail "rustc -Vv release '$rustc_release' does not match pinned channel '$channel'"
fi

if [ -n "$rustc_release" ] && grep -qF "rustc $rustc_release" README.md 2>/dev/null; then
    pass "README records the exact rustc -Vv used (rustc $rustc_release)"
else
    fail "README does not record the exact rustc -Vv used"
fi

# --------------------------------------------------- 3. engine-free core
header "3. The core is engine-free: no engine dependency, no engine API use"

if [ -f "$CORE_DIR/Cargo.toml" ] && grep -qiE 'godot|gdext' "$CORE_DIR/Cargo.toml"; then
    fail "$CORE_DIR/Cargo.toml mentions the engine"
else
    pass "$CORE_DIR/Cargo.toml declares no engine dependency"
fi

if [ -d "$CORE_DIR/src" ] && grep -rqiE 'godot|gdext' "$CORE_DIR/src"; then
    fail "engine API use found in $CORE_DIR/src:"
    grep -rniE 'godot|gdext' "$CORE_DIR/src" | sed 's/^/      | /'
else
    pass "$CORE_DIR/src contains no engine API use"
fi

core_deps="$(cargo metadata --format-version 1 2>/dev/null \
    | jq -r '.packages[] | select(.name=="remich_core") | .dependencies[].name' 2>/dev/null \
    | sort -u | tr '\n' ' ')"
core_deps="${core_deps%% }"
if printf '%s' "$core_deps" | grep -qiE 'godot|gdext'; then
    fail "remich_core resolves an engine dependency: $core_deps"
else
    pass "remich_core's resolved dependencies contain no engine crate"
fi

# `cargo tree` annotates every workspace package with its absolute checkout
# path, and a checkout path that happens to contain the words `godot`/`gdext`
# must not be mistaken for an engine crate. This check is about crate identity,
# so only the source-path annotation is stripped before grepping. A real engine
# package line (`├── godot v0.5.5`) carries no path annotation here and is
# still caught.
if cargo tree -p remich_core --edges normal,build 2>/dev/null \
        | sed -E 's/ \((path[+]file:)?\/[^)]*\)//g' >"$LOG_DIR/tree-core.txt"; then
    if grep -qiE 'godot|gdext' "$LOG_DIR/tree-core.txt"; then
        fail "cargo tree -p remich_core shows an engine crate:"
        grep -niE 'godot|gdext' "$LOG_DIR/tree-core.txt" | sed 's/^/      | /'
    else
        pass "cargo tree -p remich_core shows no engine crate"
    fi
else
    fail "cargo tree -p remich_core failed"
fi

# Step 1 had chosen no binding, so it asserted that NO engine crate appeared
# anywhere in the workspace graph ("Step 2 chooses it"). Step 2 chooses it, so
# total absence is no longer the rule — confinement is, and that is exactly what
# keeps the firewall of §1.2 intact: an engine crate may now appear in the
# graph, but only behind the binding crate. Every other workspace member must
# still have an engine-free dependency closure.
workspace_members="$(cargo metadata --format-version 1 --no-deps 2>/dev/null \
    | jq -r '.packages[].name' 2>/dev/null | sort -u)"
engine_breaches=""
for member in $workspace_members; do
    if [ "$member" = "remich_gdext" ]; then
        continue
    fi
    # Path annotation stripped, same reason as above: crate identity only.
    if cargo tree -p "$member" --edges normal,build 2>/dev/null \
            | sed -E 's/ \((path[+]file:)?\/[^)]*\)//g' \
            | grep -qiE 'godot|gdext'; then
        engine_breaches="$engine_breaches $member"
    fi
done
if [ -n "$engine_breaches" ]; then
    fail "an engine crate reaches a workspace member other than remich_gdext:$engine_breaches"
else
    pass "every workspace member except remich_gdext keeps an engine-free dependency closure"
fi

# ------------------------------------------------------ 4. build and tests
header "4. The workspace builds and tests"

if cargo build --workspace >"$LOG_DIR/build.log" 2>&1; then
    pass "cargo build --workspace"
else
    fail "cargo build --workspace failed:"
    tail -n 30 "$LOG_DIR/build.log" | sed 's/^/      | /'
fi

if cargo test --workspace >"$LOG_DIR/test.log" 2>&1; then
    pass "cargo test --workspace"
    sed 's/^/      | /' "$LOG_DIR/test.log"
else
    fail "cargo test --workspace failed:"
    tail -n 40 "$LOG_DIR/test.log" | sed 's/^/      | /'
fi

# ----------------------------------------------------- 5. Godot test project
header "5. The Remich-owned Godot test project exists"

if [ -f "$GODOT_PROJECT/project.godot" ]; then
    pass "$GODOT_PROJECT/project.godot exists"
else
    fail "$GODOT_PROJECT/project.godot is missing"
fi

if [ -f "$GODOT_PROJECT/project.godot" ] \
        && grep -qE '^config/name="[^"]*Remich' "$GODOT_PROJECT/project.godot"; then
    pass "the project is Remich-owned (config/name)"
else
    fail "the Godot project is not named as Remich's own"
fi

if [ -f "$GODOT_PROJECT/main.tscn" ]; then
    pass "$GODOT_PROJECT/main.tscn exists (the project has a main scene)"
else
    fail "$GODOT_PROJECT/main.tscn is missing"
fi

if [ -f "$GODOT_PROJECT/marker.gd" ]; then
    pass "$GODOT_PROJECT/marker.gd exists (the marker the headless check looks for)"
else
    fail "$GODOT_PROJECT/marker.gd is missing"
fi

# ------------------------------------------------ 6. pinned Godot, headless
header "6. The pinned Godot 4.7.2 opens the test project headlessly"

if [ -x "$GODOT_BIN" ]; then
    pass "pinned Godot binary present: $GODOT_BIN"
else
    fail "pinned Godot binary missing or not executable: $GODOT_BIN"
fi

godot_version=""
if [ -x "$GODOT_BIN" ]; then
    godot_version="$("$GODOT_BIN" --version 2>/dev/null | tail -n 1)"
    case "$godot_version" in
        4.7.2*) pass "pinned Godot --version: $godot_version" ;;
        *)      fail "pinned Godot --version is '$godot_version', expected 4.7.2" ;;
    esac
fi

if [ -x "$GODOT_BIN" ] && [ -d "$GODOT_PROJECT" ]; then
    # Editor mode (--editor / --import) is deliberately NOT used here. This
    # pinned binary is portable-mode: an editor run rewrites the engine's own
    # editor_data/ next to the executable, i.e. inside Yolanda's directory, and
    # the lane rule is that the binary may be used but Yolanda may not be
    # changed. Running the project headlessly leaves Yolanda byte-for-byte
    # untouched while still opening this project.
    "$GODOT_BIN" --headless --path "$GODOT_PROJECT" --quit \
        >"$LOG_DIR/godot-run.log" 2>&1
    rc=$?
    if [ "$rc" -ne 0 ]; then
        fail "headless project open exited $rc:"
        tail -n 30 "$LOG_DIR/godot-run.log" | sed 's/^/      | /'
    elif grep -q 'REMICH_TEST_PROJECT_OPENED' "$LOG_DIR/godot-run.log"; then
        pass "headless open exits 0 and loads this project: Godot --headless --path $GODOT_PROJECT --quit"
        note "the project's marker autoload ran, so the engine opened Remich's project, not an empty one"
    else
        fail "the engine exited 0 but never loaded this project (marker autoload did not run)"
        tail -n 30 "$LOG_DIR/godot-run.log" | sed 's/^/      | /'
    fi
fi

# ------------------------------------------------------- 7. README boundary
header "7. The README still states Remich's ownership boundary"

readme="README.md"
if [ ! -f "$readme" ]; then
    fail "README.md is missing"
else
    # Flatten hard line wraps first: reflowing the README must not break the check.
    readme_flat="$(tr -s '[:space:]' ' ' <"$readme")"
    for phrase in \
        "Remich owns the bridge, not the behaviour" \
        "data transfer between engine-free Rust cores and Godot" \
        "Godot types belong only in the thin binding layer" \
        "runtime simulation is game state, not Yolanda history" \
        "Determinism is a requirement, not a hope" \
        "Rebuild speed is a requirement, not a hope"
    do
        if printf '%s' "$readme_flat" | grep -qF "$phrase"; then
            pass "README: \"$phrase\""
        else
            fail "README no longer states: \"$phrase\""
        fi
    done
fi

# ------------------------------------------------- 8. generated state ignored
header "8. Generated build state is not committed"

committed_state="$(git ls-files | grep -E '(^|/)(target|\.godot)/' || true)"
if [ -n "$committed_state" ]; then
    fail "generated build state is tracked by git:"
    printf '%s\n' "$committed_state" | sed 's/^/      | /'
else
    pass "no Cargo target/ or Godot .godot/ path is tracked by git"
fi

# Match on generated *file* paths: git only treats a bare `.godot/` as a
# directory pattern once the directory exists, and the whole point is that it
# should never be tracked.
if git check-ignore -q target/debug/remich \
        && git check-ignore -q "$GODOT_PROJECT/.godot/global_script_class_cache.cfg" \
        && git check-ignore -q "$GODOT_PROJECT/.godot/editor/editor_layout.cfg"; then
    pass "Cargo target/ and Godot .godot/ are ignored"
else
    fail "Cargo target/ and Godot .godot/ are not both ignored"
fi

# And real source files must NOT be ignored, or the ignore rule has gone too far.
if git check-ignore -q Cargo.toml "$GODOT_PROJECT/project.godot" 2>/dev/null; then
    fail "the ignore rules swallow real source files"
else
    pass "the ignore rules leave real source files tracked"
fi

# ------------------------------------------------------------------ summary
printf '\n========================================\n'
if [ "$failures" -eq 0 ]; then
    printf 'PASS  Phase 1 Step 1 — the repository'\''s shape\n'
    printf '========================================\n'
    exit 0
fi
printf 'FAIL  Phase 1 Step 1 — %d check(s) failed\n' "$failures"
printf '========================================\n'
exit 1
