#!/usr/bin/env bash
# Stage Remich's Godot project and run the Phase 2 Step 3 save proof through
# the real GDExtension in pinned Godot 4.7.2 — one FRESH engine process per
# invocation, exactly as the acceptance needs it:
#
# Usage:
#   bash tools/run_save.sh baseline <trace-path>
#   bash tools/run_save.sh save     <save-file>
#   bash tools/run_save.sh load     <save-file> <trace-path>
#   bash tools/run_save.sh adapt    <save-file>
#
#   baseline  initialize the fixture, run 0 -> 240 uninterrupted, write only
#             the second-half continuation trace to <trace-path>;
#   save      run to the noon save point, write the game save to
#             <save-file> and exit — the only mode that writes a save;
#   load      fresh process: restore <save-file> (same identity), continue
#             to 240, write the same-shaped continuation trace;
#   adapt     fresh process: restore <save-file> against the changed
#             identity/valid places and print the adaptation report.
#
# Pre-existing traces are removed first (a run that never reaches the writer
# cannot be mistaken for a fresh one), and in `save` mode the save file is
# removed too, so the bytes on disk come from this write alone. `load` and
# `adapt` never remove or rewrite the save — they only read it, and the
# acceptance hashes it before and after both.
#
# Without REMICH_SAVE_MODE (see godot/save_probe.gd) the save probe stays
# silent, so every ordinary run — day, clock, weather, bridge — is unaffected.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

MODE="${1:-}"
case "$MODE" in
    baseline | save | load | adapt) ;;
    *)
        echo "usage: bash tools/run_save.sh baseline|save|load|adapt [args...]" >&2
        exit 2
        ;;
esac
shift

SAVE_PATH=""
TRACE_PATH=""
case "$MODE" in
    baseline)
        [ "$#" -eq 1 ] || {
            echo "usage: bash tools/run_save.sh baseline <trace-path>" >&2
            exit 2
        }
        TRACE_PATH="$1"
        rm -f "$TRACE_PATH"
        ;;
    save)
        [ "$#" -eq 1 ] || {
            echo "usage: bash tools/run_save.sh save <save-file>" >&2
            exit 2
        }
        SAVE_PATH="$1"
        rm -f "$SAVE_PATH"
        ;;
    load)
        [ "$#" -eq 2 ] || {
            echo "usage: bash tools/run_save.sh load <save-file> <trace-path>" >&2
            exit 2
        }
        SAVE_PATH="$1"
        TRACE_PATH="$2"
        [ -f "$SAVE_PATH" ] || {
            echo "run_save: no save at $SAVE_PATH" >&2
            exit 1
        }
        rm -f "$TRACE_PATH"
        ;;
    adapt)
        [ "$#" -eq 1 ] || {
            echo "usage: bash tools/run_save.sh adapt <save-file>" >&2
            exit 2
        }
        SAVE_PATH="$1"
        [ -f "$SAVE_PATH" ] || {
            echo "run_save: no save at $SAVE_PATH" >&2
            exit 1
        }
        ;;
esac

GODOT_BIN="/home/mrg/Documents/Project/Yolanda/.godot-local/engine/4.7.2/Godot_v4.7.2-stable_linux.x86_64"
if [ ! -x "$GODOT_BIN" ]; then
    echo "run_save: pinned engine missing at $GODOT_BIN" >&2
    exit 1
fi

# Staging (tools/stage_save.sh) registers the extension and derives the save
# revision expectation from the Rust source; the probe refuses a stale one.
bash tools/stage_save.sh

REMICH_SAVE_MODE="$MODE" \
REMICH_SAVE_FILE="$SAVE_PATH" \
REMICH_SAVE_TRACE="$TRACE_PATH" \
    "$GODOT_BIN" --headless --path godot --quit-after 10
