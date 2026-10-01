#!/usr/bin/env bash
# Phase 2, step 4 benchmark runner — "many inhabitants, measured"
# (docs/PLAN.md §4a, step 4; record: docs/remich-scale-phase2-step4.md).
#
# Usage:
#
#   bash tools/benchmark_phase2_step4.sh          # the OFFICIAL measurement
#   bash tools/benchmark_phase2_step4.sh --smoke  # short development smoke
#
# Official: populations 1, 10, 100, 1000 in that fixed order, 10 warm-up
# samples and 100 measured samples per population. The official command is
# run ONCE, from the clean measured commit, after which nothing executable
# may change — only the record may. Smoke: the same code path and the same
# four populations with 1 warm-up and 3 measured samples; its numbers are
# not the official measurements and are never posted as them.
#
# What this runner does (and does not do):
#
#   * it never builds — like every Remich runner it measures the library
#     already on disk; the benchmark itself refuses a stale one by comparing
#     the library's own scorer revision against the source (tools/stage_*'s
#     rule), so an out-of-date target/debug/*.so fails instead of reporting
#     wrong numbers;
#   * it strips every probe expectation before staging, then registers only
#     the extension (tools/stage_bridge.sh): during a benchmark run no
#     ordinary Step 1-3 probe may execute, print or quit — SaveProbe and the
#     rest stay silent, and the autoload order is untouched;
#   * it runs exactly one fresh pinned-Godot process, headless, never in
#     editor/import/export mode, with a hang guard (timeout 300):
#
#       "$GODOT_BIN" --headless --path godot --script res://scale_benchmark.gd
#
#   * on any operational failure it prints `REMICH_SCALE_FAIL reason=...`
#     and exits non-zero; success is exactly one REMICH_SCALE_OK line from
#     the benchmark, exit 0.
#
# The machine the numbers come from is ordinary and untouched: no governor
# changes, no core pinning, no installed packages, no service or kernel
# tweaks of any kind.
set -euo pipefail

REPO_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

MODE="official"
case "${1:-}" in
    "") ;;
    --smoke) MODE="smoke" ;;
    *)
        echo "usage: bash tools/benchmark_phase2_step4.sh [--smoke]" >&2
        exit 2
        ;;
esac
if [ "$#" -gt 1 ]; then
    echo "usage: bash tools/benchmark_phase2_step4.sh [--smoke]" >&2
    exit 2
fi

fail() {
    echo "REMICH_SCALE_FAIL reason=$1"
    exit 1
}

# Qualified headless path only: never editor, import or export mode.
GODOT_BIN="/home/mrg/Documents/Project/Yolanda/.godot-local/engine/4.7.2/Godot_v4.7.2-stable_linux.x86_64"
[ -x "$GODOT_BIN" ] || fail "pinned-engine-missing"

LIB="target/debug/libremich_gdext.so"
[ -f "$LIB" ] || fail "library-missing-cargo-build-workspace-first"

# The scorer revision the SOURCE carries; the benchmark compares it with the
# revision the loaded library reports and refuses a stale library.
SCORER_REV="$(sed -n 's/^pub const SCORER_BRIDGE_REV: &str = "\([^"]*\)";$/\1/p' \
    crates/remich_gdext/src/lib.rs | head -n1)"
[ -n "$SCORER_REV" ] || fail "scorer-revision-unparsed"

# The environment the numbers will be attributed to, echoed by the benchmark
# in its REMICH_SCALE_ENV line exactly as supplied here.
GODOT_VERSION="$("$GODOT_BIN" --version 2>/dev/null | head -n1 | tr -d '\r')"
[ -n "$GODOT_VERSION" ] || fail "godot-version-unavailable"
RUST_VERSION="$(rustc -V 2>/dev/null | awk '{print $2}')"
[ -n "$RUST_VERSION" ] || fail "rustc-version-unavailable"
OS_NAME="$(uname -s)"
KERNEL="$(uname -r)"
ARCH="$(uname -m)"
CPU="$(grep -m1 'model name' /proc/cpuinfo 2>/dev/null | cut -d: -f2- \
    | sed 's/^ *//; s/ /_/g')"
[ -n "$CPU" ] || CPU="unknown"

export REMICH_SCALE_MODE="$MODE"
export REMICH_SCALE_REV="$SCORER_REV"
export REMICH_SCALE_GODOT="$GODOT_VERSION"
export REMICH_SCALE_RUST="$RUST_VERSION"
export REMICH_SCALE_PROFILE="debug"
export REMICH_SCALE_LIB="$LIB"
export REMICH_SCALE_OS="$OS_NAME"
export REMICH_SCALE_KERNEL="$KERNEL"
export REMICH_SCALE_ARCH="$ARCH"
export REMICH_SCALE_CPU="$CPU"

# Stage ONLY the extension registration. Every other probe expectation is
# removed first: a leftover expectation from an earlier Step 1-3 run would
# make that probe execute (and possibly quit) during a benchmark run.
rm -f godot/*_expectation.txt
bash tools/stage_bridge.sh

RUN_LOG="$(mktemp /tmp/remich-p2s4-bench.XXXXXX)"
trap 'rm -f "$RUN_LOG"' EXIT

set +e
timeout 300 "$GODOT_BIN" --headless --path godot --script res://scale_benchmark.gd \
    >"$RUN_LOG" 2>&1
rc=$?
set -e

cat "$RUN_LOG"

if [ "$rc" -eq 124 ]; then
    fail "timeout-after-300s"
fi
if [ "$rc" -ne 0 ]; then
    if ! grep -q '^REMICH_SCALE_FAIL' "$RUN_LOG"; then
        fail "engine-exit-$rc"
    fi
    exit "$rc"
fi
if grep -q '^REMICH_SCALE_FAIL' "$RUN_LOG"; then
    fail "benchmark-reported-failure"
fi
if ! grep -q '^REMICH_SCALE_OK' "$RUN_LOG"; then
    fail "missing-ok-line"
fi
exit 0
