#!/usr/bin/env bash
# Stage Remich's Godot project and run the Phase 2 Step 2 weather proof
# through the real GDExtension in pinned Godot 4.7.2.
#
# Usage:
#   bash tools/run_weather.sh <trace-path>
#
# The trace path is where `godot/weather_probe.gd` writes its JSON Lines
# weather trace. Any pre-existing file at that path is removed first, so a
# run that never reaches the writer cannot be mistaken for a fresh one.
# Without REMICH_WEATHER_TRACE_PATH (see below) the weather probe stays
# silent, so ordinary runs — and Step 1's day runs — are unaffected.
#
# The stand-in seed is the test project's fixture constant
# (godot/weather.gd, TEST_SEED): two runs of this script with the same trace
# inputs must produce byte-identical traces.
#
# Staging (tools/stage_weather.sh) also stages the shared clock, scorer and
# bridge expectations, so the same process carries the Step 1 and Phase 1
# markers alongside the weather proof.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

TRACE_PATH="${1:-}"
if [ -z "$TRACE_PATH" ]; then
    echo "usage: bash tools/run_weather.sh <trace-path>" >&2
    exit 2
fi

GODOT_BIN="/home/mrg/Documents/Project/Yolanda/.godot-local/engine/4.7.2/Godot_v4.7.2-stable_linux.x86_64"
if [ ! -x "$GODOT_BIN" ]; then
    echo "run_weather: pinned engine missing at $GODOT_BIN" >&2
    exit 1
fi

rm -f "$TRACE_PATH"

# Registering the GDExtension and every probe expectation (bridge, scorer,
# clock, weather) is part of staging a run that has to load it.
bash tools/stage_weather.sh

REMICH_WEATHER_TRACE_PATH="$TRACE_PATH" "$GODOT_BIN" --headless --path godot --quit-after 10
