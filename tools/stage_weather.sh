#!/usr/bin/env bash
# Staging for the Phase 2 Step 2 weather proof (docs/PLAN.md §4a).
#
# The weather probe must verify the revision that is actually in the library
# on disk, not one anybody typed, so the expectation is parsed straight out
# of the Rust source — exactly as tools/stage_clock.sh, stage_scorer.sh and
# stage_bridge.sh do for the earlier probes. Change WEATHER_BRIDGE_REV on one
# line and Godot is expected to see the new value; if the library is stale,
# the weather proof fails instead of agreeing with itself.
#
# Staging the clock/scorer/bridge expectations is part of staging a run that
# loads the extension (the weather run also carries the Step 1 and Phase 1
# markers, so the shared clock is proven in the same process). The derived
# expectation files are never committed: they are written beside the project
# and ignored.
#
# Derived state, never committed: it is written beside the project and ignored.
#
# Usage:  bash tools/stage_weather.sh
set -euo pipefail

REPO_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)" || exit 1
cd "$REPO_ROOT" || exit 1

PROBE_SOURCE="crates/remich_gdext/src/lib.rs"
PROBE_CONST="WEATHER_BRIDGE_REV"
EXPECTATION_FILE="godot/weather_probe_expectation.txt"

[ -f "$PROBE_SOURCE" ] || { echo "stage_weather: missing $PROBE_SOURCE" >&2; exit 1; }

# Registering the extension with the project and staging the earlier probe
# expectations (bridge, scorer, shared clock) are part of staging a run that
# loads it.
bash tools/stage_clock.sh >/dev/null

rev="$(
    sed -n "s/^[[:space:]]*pub const ${PROBE_CONST}: &str = \"\([^\"]*\)\".*/\1/p" "$PROBE_SOURCE"
)"
rev="${rev%%$'\n'*}"
[ -n "$rev" ] || {
    echo "stage_weather: could not parse ${PROBE_CONST} from $PROBE_SOURCE" >&2
    exit 1
}

printf '%s\n' "$rev" >"$EXPECTATION_FILE"

echo "staged weather: rev=$rev expectation=$EXPECTATION_FILE"
