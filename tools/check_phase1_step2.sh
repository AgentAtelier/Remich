#!/usr/bin/env bash
# Phase 1, Step 2 acceptance check — "The bridge exists" (docs/PLAN.md).
#
# One command, from anywhere:
#
#     bash tools/check_phase1_step2.sh
#
# It fails if the Step 2 bridge capability is removed. It runs the Step 1
# acceptance first, so the repository-shape and engine-free-core baseline cannot
# regress underneath a green Step 2.
#
# Checks:
#
#   1. the Step 1 acceptance is still green;
#   2. the authoritative binding compatibility evidence is committed;
#   3. the binding dependency is pinned exactly, at the qualified API level;
#   4. the core is still engine-free (no engine dependency, no engine API use);
#   5. the workspace builds and tests;
#   6. a real extension library carrying the entry symbol is produced;
#   7. the Godot project has the GDExtension registration and the Godot-side probe;
#   8. pinned Godot 4.7.2 loads the extension headlessly, reaches the Rust
#      callable, and observes the expected value;
#   9. generated build/import/library state is not committed, and no timing
#      probe remains.

set -uo pipefail

REPO_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)" || exit 1
cd "$REPO_ROOT" || exit 1

GODOT_BIN="/home/mrg/Documents/Project/Yolanda/.godot-local/engine/4.7.2/Godot_v4.7.2-stable_linux.x86_64"
GODOT_PROJECT="godot"
CORE_DIR="crates/remich_core"
BINDING_DIR="crates/remich_gdext"
BINDING_MANIFEST="$BINDING_DIR/Cargo.toml"
PROBE_SOURCE="$BINDING_DIR/src/lib.rs"
EVIDENCE_DOC="docs/binding-compatibility.md"
EXTENSION_FILE="$GODOT_PROJECT/remich.gdextension"
PROBE_SCRIPT="$GODOT_PROJECT/bridge_probe.gd"
EXPECTATION_FILE="$GODOT_PROJECT/bridge_probe_expectation.txt"
EXTENSION_LIST="$GODOT_PROJECT/.godot/extension_list.cfg"
EXTENSION_LIB="target/debug/libremich_gdext.so"
# The value committed for Step 2. The rebuild measurement changes exactly this
# line and then reverts it; check 9 fails if the probe was left behind.
COMMITTED_PROBE_VALUE="remich-bridge-v1"

LOG_DIR="$(mktemp -d "${TMPDIR:-/tmp}/remich-p1s2.XXXXXX")" || exit 1
trap 'rm -rf "$LOG_DIR"' EXIT

failures=0
pass() { printf 'ok    %s\n' "$1"; }
fail() { printf 'FAIL  %s\n' "$1"; failures=$((failures + 1)); }
note() { printf '      %s\n' "$1"; }
header() { printf '\n== %s ==\n' "$1"; }

# The probe value, parsed straight out of the Rust source. tools/stage_bridge.sh
# does the same parse; check 8 compares the two so a divergence fails loudly
# instead of letting Godot verify against something nobody wrote.
probe_value_from_source() {
    local v
    v="$(sed -n 's/^[[:space:]]*pub const BRIDGE_PROBE_VALUE: &str = "\([^"]*\)".*/\1/p' "$PROBE_SOURCE" 2>/dev/null)"
    printf '%s' "${v%%$'\n'*}"
}

# --------------------------------------------------- 1. Step 1 still green
header "1. The Step 1 acceptance is still green"

if bash tools/check_phase1_step1.sh >"$LOG_DIR/step1.log" 2>&1; then
    pass "bash tools/check_phase1_step1.sh exits 0"
    tail -n 3 "$LOG_DIR/step1.log" | sed 's/^/      | /'
else
    fail "bash tools/check_phase1_step1.sh failed:"
    tail -n 60 "$LOG_DIR/step1.log" | sed 's/^/      | /'
fi

# ------------------------------------------------ 2. compatibility evidence
header "2. Authoritative Godot 4.7.2 compatibility evidence is committed"

if git ls-files --error-unmatch "$EVIDENCE_DOC" >/dev/null 2>&1; then
    pass "$EVIDENCE_DOC is tracked by git"
else
    fail "$EVIDENCE_DOC is not tracked by git — the compatibility evidence is uncommitted"
fi

if [ -f "$EVIDENCE_DOC" ]; then
    for needle in \
        "godot-rust/gdext" \
        "0.5.5" \
        "api-4-7" \
        "4.7.2" \
        "runtime version" \
        "2026-09-30"
    do
        if grep -qF "$needle" "$EVIDENCE_DOC"; then
            pass "evidence records: $needle"
        else
            fail "evidence does not record: $needle"
        fi
    done

    if grep -qE 'https://(github\.com/godot-rust|godot-rust\.github\.io)' "$EVIDENCE_DOC"; then
        pass "evidence cites upstream godot-rust sources by URL"
    else
        fail "evidence cites no upstream godot-rust URL"
    fi

    if grep -qF "Changelog.md" "$EVIDENCE_DOC" && grep -qF "23 June 2026" "$EVIDENCE_DOC"; then
        pass "evidence cites gdext's own release notes with their date"
    else
        fail "evidence does not cite gdext's release notes with a date"
    fi
else
    fail "$EVIDENCE_DOC is missing"
fi

# ------------------------------------------------------- 3. dependency pinned
header "3. The binding dependency is pinned exactly, at the 4.7 API level"

binding_line="$(grep -E '^godot[[:space:]]*=' "$BINDING_MANIFEST" 2>/dev/null | head -n 1)"
pin=""
if [ -z "$binding_line" ]; then
    fail "$BINDING_MANIFEST declares no godot dependency"
else
    note "manifest: $binding_line"

    pin="$(sed -n 's/.*version[[:space:]]*=[[:space:]]*"\([^"]*\)".*/\1/p' <<<"$binding_line" | head -n 1)"
    if printf '%s' "$pin" | grep -Eq '^=[0-9]+\.[0-9]+\.[0-9]+$'; then
        pass "binding version is pinned exactly: '$pin' (a caret/loose range is not allowed)"
    else
        fail "binding version '$pin' is not an exact '=X.Y.Z' pin"
    fi

    if printf '%s' "$binding_line" | grep -q 'api-4-7'; then
        pass "the manifest selects API level api-4-7 (this is not the default in the pinned binding)"
    else
        fail "the manifest does not select api-4-7 — the bridge would target the wrong engine API"
    fi
fi

if [ -f Cargo.lock ]; then
    lock_pin="$(awk '/^name = "godot"$/{getline; sub(/^version = "/,""); sub(/"$/,""); print; exit}' Cargo.lock)"
    if [ "$lock_pin" = "${pin#=}" ] && [ -n "$lock_pin" ]; then
        pass "Cargo.lock freezes godot at $lock_pin"
    else
        fail "Cargo.lock freezes godot at '$lock_pin', expected '${pin#=}'"
    fi

    api_payload="$(awk '/^name = "gdextension-api"$/{getline; sub(/^version = "/,""); sub(/"$/,""); print; exit}' Cargo.lock)"
    if [ -n "$api_payload" ]; then
        pass "Cargo.lock freezes the shipped Godot API payload (gdextension-api $api_payload)"
    else
        fail "Cargo.lock has no gdextension-api entry"
    fi
else
    fail "Cargo.lock is missing — nothing freezes the resolved binding versions"
fi

if cargo tree -p remich_gdext --edges normal,build >"$LOG_DIR/tree-binding.txt" 2>/dev/null; then
    # Match on the crate name and version, not on cargo tree's box-drawing
    # prefix (├── ─ │), which is locale/charset dependent.
    if grep -qE '(^|[[:space:]])godot v[0-9]' "$LOG_DIR/tree-binding.txt"; then
        pass "the binding crate really resolves the godot crate:"
        grep -E '(^|[[:space:]])godot v[0-9]' "$LOG_DIR/tree-binding.txt" | head -n 2 | sed 's/^/      | /'
    else
        fail "cargo tree -p remich_gdext shows no godot crate"
    fi
else
    fail "cargo tree -p remich_gdext failed"
fi

# --------------------------------------------------- 4. engine-free core
header "4. The core is still engine-free"

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

# The source-path annotation is stripped before grepping: `cargo tree` prints
# each workspace package's absolute checkout path, and a checkout path that
# contains the words `godot`/`gdext` is not an engine crate. Only crate
# identity counts, and a real `├── godot v0.5.5` line is untouched by the
# strip.
if cargo tree -p remich_core --edges normal,build 2>/dev/null \
        | sed -E 's/ \((path[+]file:)?\/[^)]*\)//g' >"$LOG_DIR/tree-core.txt"; then
    if grep -qiE 'godot|gdext' "$LOG_DIR/tree-core.txt"; then
        fail "cargo tree -p remich_core shows an engine crate (the firewall is broken):"
        grep -niE 'godot|gdext' "$LOG_DIR/tree-core.txt" | sed 's/^/      | /'
    else
        pass "cargo tree -p remich_core shows no engine crate"
    fi
else
    fail "cargo tree -p remich_core failed"
fi

# ------------------------------------------------------ 5. build and tests
header "5. The workspace builds and tests"

if cargo build --workspace >"$LOG_DIR/build.log" 2>&1; then
    pass "cargo build --workspace"
else
    fail "cargo build --workspace failed:"
    tail -n 30 "$LOG_DIR/build.log" | sed 's/^/      | /'
fi

if cargo test --workspace >"$LOG_DIR/test.log" 2>&1; then
    pass "cargo test --workspace"
    grep -E '^test result:' "$LOG_DIR/test.log" | sed 's/^/      | /'
else
    fail "cargo test --workspace failed:"
    tail -n 40 "$LOG_DIR/test.log" | sed 's/^/      | /'
fi

# --------------------------------------------------- 6. a real library exists
header "6. A real extension library carrying the entry symbol is produced"

if [ -s "$EXTENSION_LIB" ]; then
    pass "$EXTENSION_LIB exists and is not empty"
    note "$(du -h "$EXTENSION_LIB" | cut -f1) on disk"
else
    fail "$EXTENSION_LIB was not produced at $EXTENSION_LIB"
fi

if [ -s "$EXTENSION_LIB" ] && file "$EXTENSION_LIB" | grep -q 'ELF .*shared object'; then
    pass "it is an ELF shared object, not a placeholder"
else
    fail "it is not an ELF shared object"
fi

if [ -s "$EXTENSION_LIB" ] && nm -D --defined-only "$EXTENSION_LIB" 2>/dev/null | grep -q 'gdext_rust_init'; then
    pass "it exports the gdext_rust_init entry symbol that the .gdextension file names"
else
    fail "it does not export gdext_rust_init"
fi

# ------------------------------------ 7. Godot-side registration and probe
header "7. The Godot project registers the extension and carries the probe"

for f in "$EXTENSION_FILE" "$PROBE_SCRIPT" "$GODOT_PROJECT/project.godot"; do
    if [ -f "$f" ]; then
        pass "$f exists"
    else
        fail "$f is missing"
    fi
    if git ls-files --error-unmatch "$f" >/dev/null 2>&1; then
        pass "$f is tracked by git"
    else
        fail "$f is not tracked by git"
    fi
done

if [ -f "$EXTENSION_FILE" ] && grep -qE '^entry_symbol[[:space:]]*=[[:space:]]*"gdext_rust_init"' "$EXTENSION_FILE"; then
    pass "$EXTENSION_FILE names entry_symbol = \"gdext_rust_init\""
else
    fail "$EXTENSION_FILE does not name the entry symbol gdext_rust_init"
fi

if [ -f "$EXTENSION_FILE" ] && grep -qF "$EXTENSION_LIB" "$EXTENSION_FILE" \
        && grep -qF "res://../$EXTENSION_LIB" "$EXTENSION_FILE"; then
    pass "$EXTENSION_FILE points at res://../$EXTENSION_LIB"
else
    fail "$EXTENSION_FILE does not point at res://../$EXTENSION_LIB"
fi

if [ -f "$EXTENSION_FILE" ] && grep -qE '^compatibility_minimum[[:space:]]*=[[:space:]]*4\.7' "$EXTENSION_FILE"; then
    pass "$EXTENSION_FILE declares compatibility_minimum = 4.7"
else
    fail "$EXTENSION_FILE does not declare compatibility_minimum = 4.7"
fi

if [ -f "$GODOT_PROJECT/project.godot" ] \
        && grep -qE '^BridgeProbe="\*res://bridge_probe\.gd"' "$GODOT_PROJECT/project.godot"; then
    pass "project.godot autoloads the Godot-side probe (BridgeProbe)"
else
    fail "project.godot does not autoload the Godot-side probe"
fi

if [ -f "$PROBE_SCRIPT" ] \
        && grep -q 'REMICH_BRIDGE_OK' "$PROBE_SCRIPT" \
        && grep -q 'bridge_probe' "$PROBE_SCRIPT" \
        && grep -q 'ClassDB' "$PROBE_SCRIPT"; then
    pass "the probe script reaches the Rust callable through ClassDB and prints a marker"
else
    fail "the probe script does not reach the Rust callable / print its marker"
fi

if bash tools/stage_bridge.sh >"$LOG_DIR/stage.log" 2>&1; then
    pass "bash tools/stage_bridge.sh (registers the extension, derives the expectation)"
    tail -n 1 "$LOG_DIR/stage.log" | sed 's/^/      | /'
else
    fail "bash tools/stage_bridge.sh failed:"
    tail -n 10 "$LOG_DIR/stage.log" | sed 's/^/      | /'
fi

if [ -f "$EXTENSION_LIST" ] && grep -qF "res://$(basename "$EXTENSION_FILE")" "$EXTENSION_LIST"; then
    pass "$(basename "$EXTENSION_LIST") registers res://$(basename "$EXTENSION_FILE")"
else
    fail "$(basename "$EXTENSION_LIST") does not register the extension"
fi

# ------------------------------------------ 8. load, call, observe in Godot
header "8. Pinned Godot 4.7.2 loads it headlessly, calls Rust, observes the value"

expected="$(probe_value_from_source)"
staged="$(tr -d '\n' <"$EXPECTATION_FILE" 2>/dev/null)"
if [ -n "$expected" ] && [ "$expected" = "$staged" ]; then
    pass "the expectation handed to Godot is parsed from the Rust source: '$expected'"
else
    fail "expectation/staging divergence: source='$expected' staged='$staged'"
fi

if [ -x "$GODOT_BIN" ]; then
    godot_version="$("$GODOT_BIN" --version 2>/dev/null | tail -n 1)"
    case "$godot_version" in
        4.7.2*) pass "pinned Godot --version: $godot_version" ;;
        *)      fail "pinned Godot --version is '$godot_version', expected 4.7.2" ;;
    esac
else
    fail "pinned Godot binary missing or not executable: $GODOT_BIN"
fi

if [ -x "$GODOT_BIN" ] && [ -n "$expected" ]; then
    # Runtime path only. No --editor / --import / --export: the pinned binary is
    # portable-mode and an editor run rewrites editor_data/ inside Yolanda.
    "$GODOT_BIN" --headless --path "$GODOT_PROJECT" --quit-after 10 \
        >"$LOG_DIR/godot-bridge.log" 2>&1
    rc=$?
    note "command: Godot_v4.7.2-stable_linux.x86_64 --headless --path $GODOT_PROJECT --quit-after 10"
    sed 's/^/      | /' "$LOG_DIR/godot-bridge.log"

    if [ "$rc" -eq 0 ]; then
        pass "the engine exited 0"
    else
        fail "the engine exited $rc"
    fi

    if grep -q 'REMICH_TEST_PROJECT_OPENED' "$LOG_DIR/godot-bridge.log"; then
        pass "Remich's own project loaded (the Step 1 marker ran)"
    else
        fail "the engine did not load Remich's project"
    fi

    if grep -qE 'Initialize godot-rust \(API v4\.7.*runtime v4\.7\.2' "$LOG_DIR/godot-bridge.log"; then
        pass "the extension was loaded: gdext reported API v4.7 against runtime v4.7.2"
    else
        fail "gdext did not report loading against the 4.7 API on runtime 4.7.2"
    fi

    if grep -q "REMICH_BRIDGE_OK value=$expected" "$LOG_DIR/godot-bridge.log"; then
        pass "Godot reached the Rust callable and observed the expected value: $expected"
    else
        fail "Godot did not observe the expected value '$expected'"
    fi

    if grep -q 'REMICH_BRIDGE_FAIL' "$LOG_DIR/godot-bridge.log"; then
        fail "the Godot-side probe reported a failure:"
        grep 'REMICH_BRIDGE_FAIL' "$LOG_DIR/godot-bridge.log" | sed 's/^/      | /'
    else
        pass "the Godot-side probe reported no failure"
    fi

    if grep -qE 'SCRIPT ERROR|Parse Error' "$LOG_DIR/godot-bridge.log"; then
        fail "the engine reported a script error:"
        grep -E 'SCRIPT ERROR|Parse Error' "$LOG_DIR/godot-bridge.log" | sed 's/^/      | /'
    else
        pass "no script errors"
    fi
fi

# ---------------------------------------- 9. generated state, no probe left
header "9. Generated state is not committed and no timing probe remains"

generated="$(git ls-files | grep -E '(^|/)(target|\.godot)/|\.so$|\.dylib$|\.dll$|bridge_probe_expectation\.txt$' || true)"
if [ -n "$generated" ]; then
    fail "generated build/import/library state is tracked by git:"
    printf '%s\n' "$generated" | sed 's/^/      | /'
else
    pass "no target/, .godot/, extension binary or derived expectation file is tracked"
fi

if git check-ignore -q "$EXTENSION_LIB" \
        && git check-ignore -q "$EXTENSION_LIST" \
        && git check-ignore -q "$EXPECTATION_FILE"; then
    pass "the extension library, extension_list.cfg and the expectation file are all ignored"
else
    fail "generated bridge state is not fully ignored"
fi

stray="$(git status --porcelain --untracked-files=all 2>/dev/null \
    | grep '^??' \
    | grep -E '(target/|\.godot/|\.so$|\.dylib$|\.dll$|bridge_probe_expectation)' || true)"
if [ -n "$stray" ]; then
    fail "untracked generated files are not ignored:"
    printf '%s\n' "$stray" | sed 's/^/      | /'
else
    pass "no untracked generated file escapes the ignore rules"
fi

current_probe="$(probe_value_from_source)"
if [ "$current_probe" = "$COMMITTED_PROBE_VALUE" ]; then
    pass "the bridge probe still holds its committed value ('$current_probe') — no timing probe left behind"
else
    fail "the bridge probe is '$current_probe', expected '$COMMITTED_PROBE_VALUE' — the timing probe was not reverted"
fi

# ------------------------------------------------------------------ summary
printf '\n========================================\n'
if [ "$failures" -eq 0 ]; then
    printf 'PASS  Phase 1 Step 2 — the bridge exists\n'
    printf '========================================\n'
    exit 0
fi
printf 'FAIL  Phase 1 Step 2 — %d check(s) failed\n' "$failures"
printf '========================================\n'
exit 1
