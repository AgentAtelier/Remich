#!/usr/bin/env bash
# Staging for the Phase 1 Step 2 bridge (docs/PLAN.md).
#
# Two things must exist beside the sources before pinned Godot can load
# Remich's own extension, and both are regenerated on every run because both
# are derived state, never committed:
#
#   godot/.godot/extension_list.cfg        registers Remich's .gdextension with
#                                          the project. The editor normally
#                                          writes this on first open; this
#                                          repository must never open the
#                                          editor (the pinned binary is
#                                          portable-mode and an editor run
#                                          would rewrite Yolanda's own
#                                          editor_data/), so we write it here,
#                                          exactly as the godot-rust book
#                                          documents for the manual case.
#
#   godot/bridge_probe_expectation.txt     the value Godot must observe when it
#                                          calls into Rust. It is parsed out of
#                                          crates/remich_gdext/src/lib.rs, so a
#                                          one-line change to the Rust probe
#                                          automatically changes what Godot is
#                                          expected to see — which is what
#                                          makes the check able to catch a
#                                          stale extension library.
#
# Usage:  bash tools/stage_bridge.sh
set -euo pipefail

REPO_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)" || exit 1
cd "$REPO_ROOT" || exit 1

PROBE_SOURCE="crates/remich_gdext/src/lib.rs"
PROBE_CONST="BRIDGE_PROBE_VALUE"
EXTENSION_FILE="godot/remich.gdextension"
EXPECTATION_FILE="godot/bridge_probe_expectation.txt"
EXTENSION_LIST="godot/.godot/extension_list.cfg"

[ -f "$PROBE_SOURCE" ] || { echo "stage_bridge: missing $PROBE_SOURCE" >&2; exit 1; }
[ -f "$EXTENSION_FILE" ] || { echo "stage_bridge: missing $EXTENSION_FILE" >&2; exit 1; }

# Read the probe value straight out of the Rust source. Only the first match
# counts, and the line must look exactly like a `&str` const declaration.
probe_value="$(
    sed -n "s/^[[:space:]]*pub const ${PROBE_CONST}: &str = \"\([^\"]*\)\".*/\1/p" "$PROBE_SOURCE"
)"
probe_value="${probe_value%%$'\n'*}"
[ -n "$probe_value" ] || {
    echo "stage_bridge: could not parse ${PROBE_CONST} from $PROBE_SOURCE" >&2
    exit 1
}

printf '%s\n' "$probe_value" >"$EXPECTATION_FILE"

mkdir -p "$(dirname "$EXTENSION_LIST")"
printf 'res://%s\n' "$(basename "$EXTENSION_FILE")" >"$EXTENSION_LIST"

echo "staged bridge: value=$probe_value expectation=$EXPECTATION_FILE extension_list=$EXTENSION_LIST"
