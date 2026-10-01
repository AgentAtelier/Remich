#!/usr/bin/env bash
# Stage Remich's Godot project and run the Phase 3 Step 2 soul proof through
# the real GDExtension in pinned Godot 4.7.2.
#
# Usage:
#   bash tools/run_soul.sh <trace-path> [normal|bypass]
#
#   normal  (default) create three stand-in souls, read them back, and record
#           the donor's propagated influence for a named connection layer.
#   bypass  the same fixture with the propagation calculation NOT invoked:
#           neutral (zero) influence values are recorded instead, while seed,
#           substrate, source axes, layer name and donor weight stay identical.
#           This is a test-only bypass of the propagation calculation — it does
#           not "disable contagion" and does not "stop mood spreading", because
#           neither of those exists in Remich (the donor returns an influence
#           value and never applies it to a receiver).
#
# The trace path is where godot/soul_probe.gd writes its plain-text soul trace.
# Any pre-existing file at that path is removed first, so a run that never
# reaches the writer cannot be mistaken for a fresh one. Traces are written
# OUTSIDE the repository (the checker points them at a temp directory).
#
# The probe is a standalone script, not an autoload: it is invoked explicitly
# with `--script`, so the project's autoload list and order are untouched.
#
# Success is judged on the probe's own machine-readable markers, not only on
# the process exit code (an unrelated autoload may quit with 0 afterwards):
# REMICH_SOUL_OK must be present, REMICH_SOUL_FAIL must be absent, and the
# trace must exist and be non-empty.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

if [ $# -lt 1 ] || [ $# -gt 2 ]; then
    echo "usage: bash tools/run_soul.sh <trace-path> [normal|bypass]" >&2
    exit 2
fi

TRACE_PATH="$1"
MODE="${2:-normal}"
case "$MODE" in
    normal) BYPASS="" ;;
    bypass) BYPASS="1" ;;
    *) echo "usage: bash tools/run_soul.sh <trace-path> [normal|bypass]" >&2; exit 2 ;;
esac

GODOT_BIN="/home/mrg/Documents/Project/Yolanda/.godot-local/engine/4.7.2/Godot_v4.7.2-stable_linux.x86_64"
if [ ! -x "$GODOT_BIN" ]; then
    echo "run_soul: pinned Godot is missing at $GODOT_BIN" >&2
    exit 1
fi

# A fresh trace every time: a run that never reaches the writer must not be
# mistakable for a successful one.
rm -f "$TRACE_PATH"

bash tools/stage_soul.sh

LOG_PATH="${TMPDIR:-/tmp}/remich-soul-run.$$.log"
cleanup() { rm -f "$LOG_PATH"; }
trap cleanup EXIT

# Headless, read-only: no editor, no import/export workflow. The probe loads
# as the main loop via --script, so nothing else in the project runs work.
set +e
REMICH_SOUL_TRACE_PATH="$TRACE_PATH" REMICH_SOUL_BYPASS="$BYPASS" \
    "$GODOT_BIN" --headless --path godot --script res://soul_probe.gd \
    >"$LOG_PATH" 2>&1
godot_rc=$?
set -e

cat "$LOG_PATH"

status=0
if ! grep -q '^REMICH_SOUL_OK actors=3 rev=remich-soul-v' "$LOG_PATH"; then
    echo "run_soul: the success marker REMICH_SOUL_OK actors=3 was not emitted" >&2
    status=1
fi
if grep -q '^REMICH_SOUL_FAIL ' "$LOG_PATH"; then
    echo "run_soul: the probe reported a failure (REMICH_SOUL_FAIL)" >&2
    status=1
fi
if [ "$MODE" = "normal" ]; then
    if ! grep -q '^REMICH_SOUL_PROPAGATION_OK layers=family,proximity,village rev=remich-soul-v' "$LOG_PATH"; then
        echo "run_soul: REMICH_SOUL_PROPAGATION_OK was not emitted" >&2
        status=1
    fi
fi
if [ ! -s "$TRACE_PATH" ]; then
    echo "run_soul: no trace was written at $TRACE_PATH" >&2
    status=1
fi
if [ "$godot_rc" -ne 0 ]; then
    echo "run_soul: pinned Godot exited with $godot_rc" >&2
    status=1
fi

exit "$status"
