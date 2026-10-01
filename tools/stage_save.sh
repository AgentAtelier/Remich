#!/usr/bin/env bash
# Staging for the Phase 2 Step 3 save proof (docs/PLAN.md §4a, step 3).
#
# The save probe must verify the revision that is actually in the library on
# disk, not one anybody typed, so the expectation is parsed straight out of
# the Rust source — exactly as tools/stage_clock.sh, stage_scorer.sh and
# stage_bridge.sh do for the earlier probes. Change SAVE_BRIDGE_REV on one
# line and Godot is expected to see the new value; if the library is stale,
# the save proof fails instead of agreeing with itself (and the Step 3
# rebuild measurement times exactly that line changing v1 -> v2 and back).
#
# Registering the GDExtension and staging the scorer/bridge expectations is
# part of staging a run that loads it (via tools/stage_scorer.sh, which
# chains tools/stage_bridge.sh), so the same process carries the Phase 1 and
# bridge markers alongside the save proof. The clock and weather probes are
# deliberately NOT staged: they stay silent in save runs, and the shared
# clock/weather autoloads remain active for the proof to restore into.
#
# Derived state, never committed: it is written beside the project and ignored.
#
# Usage:  bash tools/stage_save.sh
set -euo pipefail

REPO_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)" || exit 1
cd "$REPO_ROOT" || exit 1

PROBE_SOURCE="crates/remich_gdext/src/lib.rs"
PROBE_CONST="SAVE_BRIDGE_REV"
EXPECTATION_FILE="godot/save_probe_expectation.txt"

[ -f "$PROBE_SOURCE" ] || { echo "stage_save: missing $PROBE_SOURCE" >&2; exit 1; }

# Registering the extension with the project and staging the earlier probe
# expectations (scorer, bridge) are part of staging a run that loads it.
bash tools/stage_scorer.sh >/dev/null

rev="$(
    sed -n "s/^[[:space:]]*pub const ${PROBE_CONST}: &str = \"\([^\"]*\)\".*/\1/p" "$PROBE_SOURCE"
)"
rev="${rev%%$'\n'*}"
[ -n "$rev" ] || {
    echo "stage_save: could not parse ${PROBE_CONST} from $PROBE_SOURCE" >&2
    exit 1
}

printf '%s\n' "$rev" >"$EXPECTATION_FILE"

echo "staged save: rev=$rev expectation=$EXPECTATION_FILE"
