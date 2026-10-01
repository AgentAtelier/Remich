#!/usr/bin/env bash
# Staging for the Phase 2 Step 1 shared-clock proof (docs/PLAN.md §4a).
#
# The clock probe must verify the revision that is actually in the library on
# disk, not one anybody typed, so the expectation is parsed straight out of
# the Rust source — exactly as tools/stage_scorer.sh and tools/stage_bridge.sh
# do for the earlier probes. Change CLOCK_BRIDGE_REV on one line and Godot is
# expected to see the new value; if the library is stale, the clock proof
# fails instead of agreeing with itself.
#
# Derived state, never committed: it is written beside the project and ignored.
#
# Usage:  bash tools/stage_clock.sh
set -euo pipefail

REPO_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)" || exit 1
cd "$REPO_ROOT" || exit 1

PROBE_SOURCE="crates/remich_gdext/src/lib.rs"
PROBE_CONST="CLOCK_BRIDGE_REV"
EXPECTATION_FILE="godot/clock_probe_expectation.txt"

[ -f "$PROBE_SOURCE" ] || { echo "stage_clock: missing $PROBE_SOURCE" >&2; exit 1; }

# Registering the extension with the project and staging the earlier probe
# expectations are part of staging a run that loads it.
bash tools/stage_scorer.sh >/dev/null

rev="$(
    sed -n "s/^[[:space:]]*pub const ${PROBE_CONST}: &str = \"\([^\"]*\)\".*/\1/p" "$PROBE_SOURCE"
)"
rev="${rev%%$'\n'*}"
[ -n "$rev" ] || {
    echo "stage_clock: could not parse ${PROBE_CONST} from $PROBE_SOURCE" >&2
    exit 1
}

printf '%s\n' "$rev" >"$EXPECTATION_FILE"

echo "staged clock: rev=$rev expectation=$EXPECTATION_FILE"
