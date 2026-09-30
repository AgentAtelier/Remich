#!/usr/bin/env bash
# Staging for the Phase 1 Step 4 scorer probe (docs/PLAN.md).
#
# The scorer probe must verify the revision that is actually in the library on
# disk, not one anybody typed, so the expectation is parsed straight out of the
# Rust source — exactly as tools/stage_bridge.sh does for the Step 2 probe.
# Change the marker on one line and Godot is expected to see the new value; if
# the library is stale, the probe fails instead of agreeing with itself.
#
# Derived state, never committed: it is written beside the project and ignored.
#
# Usage:  bash tools/stage_scorer.sh
set -euo pipefail

REPO_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)" || exit 1
cd "$REPO_ROOT" || exit 1

PROBE_SOURCE="crates/remich_gdext/src/lib.rs"
PROBE_CONST="SCORER_BRIDGE_REV"
EXPECTATION_FILE="godot/scorer_probe_expectation.txt"

[ -f "$PROBE_SOURCE" ] || { echo "stage_scorer: missing $PROBE_SOURCE" >&2; exit 1; }

# Registering the extension with the project is part of staging a run that
# loads it; tools/stage_bridge.sh owns that file and writes the same content.
bash tools/stage_bridge.sh >/dev/null

rev="$(
    sed -n "s/^[[:space:]]*pub const ${PROBE_CONST}: &str = \"\([^\"]*\)\".*/\1/p" "$PROBE_SOURCE"
)"
rev="${rev%%$'\n'*}"
[ -n "$rev" ] || {
    echo "stage_scorer: could not parse ${PROBE_CONST} from $PROBE_SOURCE" >&2
    exit 1
}

printf '%s\n' "$rev" >"$EXPECTATION_FILE"

echo "staged scorer: rev=$rev expectation=$EXPECTATION_FILE"
