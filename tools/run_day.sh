#!/usr/bin/env bash
# Stage Remich's Godot project and run one test day (Phase 1 step 5, now
# driven by Phase 2's one clock) through the real GDExtension in pinned
# Godot 4.7.2.
#
# Usage:
#   bash tools/run_day.sh <trace-path> [speed]
#
# The trace path is where `godot/day_probe.gd` writes its JSON Lines day. Any
# pre-existing file at that path is removed first, so a run that never reaches
# the writer cannot be mistaken for a fresh one. Without REMICH_DAY_TRACE_PATH
# (see below) the harness stays silent and this script would produce nothing.
#
# The optional speed (default 1) is the shared clock's integer speed
# multiplier for the run, exported as REMICH_CLOCK_SPEED. Speed 1 and speed 4
# must produce byte-identical simulation traces: the same consecutive ticks
# are processed either way, only the number of driver pulses differs.
#
# Steps 1-4 never call this script and never set REMICH_DAY_TRACE_PATH, so
# ordinary runs are unaffected.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

TRACE_PATH="${1:-}"
if [ -z "$TRACE_PATH" ]; then
    echo "usage: bash tools/run_day.sh <trace-path> [speed]" >&2
    exit 2
fi

SPEED="${2:-1}"
case "$SPEED" in
    ''|*[!0-9]*) echo "run_day: speed must be a positive integer, got '$SPEED'" >&2; exit 2 ;;
esac
if [ "$SPEED" -lt 1 ]; then
    echo "run_day: speed must be at least 1, got '$SPEED'" >&2
    exit 2
fi

GODOT_BIN="/home/mrg/Documents/Project/Yolanda/.godot-local/engine/4.7.2/Godot_v4.7.2-stable_linux.x86_64"
if [ ! -x "$GODOT_BIN" ]; then
    echo "run_day: pinned engine missing at $GODOT_BIN" >&2
    exit 1
fi

rm -f "$TRACE_PATH"

# Registering the GDExtension and every probe expectation (bridge, scorer,
# clock) is part of staging a run that has to load it.
bash tools/stage_clock.sh

REMICH_CLOCK_SPEED="$SPEED" REMICH_DAY_TRACE_PATH="$TRACE_PATH" "$GODOT_BIN" --headless --path godot --quit-after 10
