#!/usr/bin/env bash
# Staging for the production-seam weather proof (Remich issue #19).
#
# The external-weather probe must verify the revision that is actually in the
# library on disk, not one anybody typed, so the expectation is parsed straight
# out of the Rust source — exactly as tools/stage_weather.sh does for the
# stand-in probe. The two projects prove the same library through different
# modes, so the same marker serves both; if the library were stale, this proof
# would fail instead of agreeing with itself.
#
# This project's own .gdextension is committed, but Godot still needs the same
# two pieces of derived state the stand-in project stages: the expectation
# (parsed out of the Rust source, so a stale library cannot pass) and
# `.godot/extension_list.cfg`, which registers the extension with the project.
# The editor would normally write the list on first open, but this repository
# must never open the editor, so it is written here exactly as
# tools/stage_bridge.sh writes the stand-in project's.
#
# Derived state, never committed: it is written beside the project and ignored.
#
# Usage:  bash tools/stage_external_weather.sh
set -euo pipefail

REPO_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)" || exit 1
cd "$REPO_ROOT" || exit 1

PROBE_SOURCE="crates/remich_gdext/src/lib.rs"
PROBE_CONST="WEATHER_BRIDGE_REV"
EXTENSION_FILE="godot_external_weather/remich.gdextension"
EXPECTATION_FILE="godot_external_weather/external_weather_probe_expectation.txt"
EXTENSION_LIST="godot_external_weather/.godot/extension_list.cfg"

[ -f "$PROBE_SOURCE" ] || { echo "stage_external_weather: missing $PROBE_SOURCE" >&2; exit 1; }
[ -f "$EXTENSION_FILE" ] || { echo "stage_external_weather: missing $EXTENSION_FILE" >&2; exit 1; }

rev="$(
    sed -n "s/^[[:space:]]*pub const ${PROBE_CONST}: &str = \"\([^\"]*\)\".*/\1/p" "$PROBE_SOURCE"
)"
rev="${rev%%$'\n'*}"
[ -n "$rev" ] || {
    echo "stage_external_weather: could not parse ${PROBE_CONST} from $PROBE_SOURCE" >&2
    exit 1
}

printf '%s\n' "$rev" >"$EXPECTATION_FILE"

mkdir -p "$(dirname "$EXTENSION_LIST")"
printf 'res://%s\n' "$(basename "$EXTENSION_FILE")" >"$EXTENSION_LIST"

echo "staged external weather: rev=$rev expectation=$EXPECTATION_FILE extension_list=$EXTENSION_LIST"
