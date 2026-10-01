#!/usr/bin/env bash
# Staging for the Phase 3 Step 2 soul proof (docs/PLAN.md §4b, step 2).
#
# The soul probe must verify the revision that is actually in the library on
# disk, not one anybody typed, so the expectation is parsed straight out of
# the Rust source — exactly as tools/stage_clock.sh, stage_scorer.sh,
# stage_weather.sh and stage_bridge.sh do for the earlier probes. Change
# SOUL_BRIDGE_REV on one line and Godot is expected to see the new value; if
# the library is stale, the soul proof fails instead of agreeing with itself.
#
# Staging the bridge expectation is part of staging any run that loads the
# extension: godot/bridge_probe.gd is an autoload that FAILS loudly when its
# own expectation file is missing, so a soul run stages it too (that also
# registers godot/remich.gdextension with the project). The scorer, clock,
# weather, save and day probes are deliberately NOT staged — they stay silent
# because their expectations and environment variables are absent, so this
# dedicated standalone probe is the only thing that does work.
#
# Derived state, never committed: it is written beside the project and ignored.
#
# Usage:  bash tools/stage_soul.sh
set -euo pipefail

REPO_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)" || exit 1
cd "$REPO_ROOT" || exit 1

PROBE_SOURCE="crates/remich_gdext/src/lib.rs"
PROBE_CONST="SOUL_BRIDGE_REV"
EXPECTATION_FILE="godot/soul_probe_expectation.txt"

[ -f "$PROBE_SOURCE" ] || { echo "stage_soul: missing $PROBE_SOURCE" >&2; exit 1; }

# Registering the extension with the project and staging the bridge
# expectation are part of staging a run that loads it.
bash tools/stage_bridge.sh >/dev/null

rev="$(
    sed -n "s/^[[:space:]]*pub const ${PROBE_CONST}: &str = \"\([^\"]*\)\".*/\1/p" "$PROBE_SOURCE"
)"
rev="${rev%%$'\n'*}"
[ -n "$rev" ] || {
    echo "stage_soul: could not parse ${PROBE_CONST} from $PROBE_SOURCE" >&2
    exit 1
}
case "$rev" in
    remich-soul-v*) ;;
    *)
        echo "stage_soul: ${PROBE_CONST}='$rev' does not look like a soul revision" >&2
        exit 1
        ;;
esac

printf '%s\n' "$rev" >"$EXPECTATION_FILE"

echo "staged soul: rev=$rev expectation=$EXPECTATION_FILE"
