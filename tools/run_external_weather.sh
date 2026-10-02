#!/usr/bin/env bash
# Run the production-seam weather proof (Remich issue #19) through the real
# GDExtension in pinned Godot 4.7.2.
#
# Usage:
#   bash tools/run_external_weather.sh
#
# This project initializes the one `RemichWeather` in EXTERNAL mode and proves
# the seam end to end: the production writer claims the one channel, one
# complete decided snapshot publishes through it, and the existing readers
# (`snapshot`, `writer_status`, `apply_wind`) see it. The probe supplies plain
# test values as if it were the external driver; there is no dependency on
# Eisleck, so Remich stays independently testable.
#
# The committed stand-in fixture in `godot/` is untouched by this run — it is a
# separate project, and its own acceptance still covers the stand-in mode.
#
# Staging (tools/stage_external_weather.sh) writes the derived expectation from
# the Rust source, so a stale library cannot pass.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

GODOT_BIN="/home/mrg/Documents/Project/Yolanda/.godot-local/engine/4.7.2/Godot_v4.7.2-stable_linux.x86_64"
if [ ! -x "$GODOT_BIN" ]; then
    echo "run_external_weather: pinned engine missing at $GODOT_BIN" >&2
    exit 1
fi

bash tools/stage_external_weather.sh

"$GODOT_BIN" --headless --path godot_external_weather --quit-after 10
