#!/usr/bin/env python3
"""Validate a Phase 2 Step 2 weather trace (docs/remich-weather-phase2-step2.md).

This reads a trace written by `godot/weather_probe.gd` and checks it with an
implementation that shares no code with the Godot script that produced it:
the file is the only thing the two have in common.

What it asserts:

* shape — every record carries exactly the documented keys, JSON Lines, one
  record per driven tick of the fixture cycle, in tick order;
* the tick contract (step 2 check 18) — `snapshot_tick == tick` on every
  record, and the tick sequence is `0 .. cycle-1`: the snapshot's own tick is
  the world-clock tick that drove it;
* the mapping to `grengewald_wind` (check 13) — applied X/Y/Z equal the
  snapshot's direction X / direction Z / strength (within the 32-bit vec4
  conversion tolerance), and W sits in `[0, 2*PI)` equal to the documented
  tick-derived presentation phase;
* the fixture's broad stand-in shape (check 17) — calm mornings (strength
  `<= 0.1`), windy afternoons (`>= 0.5`), as RANGES: this deliberately does
  not bake a hand-written table of expected floats;
* plain-data sanity — every numeric field finite, direction a unit vector,
  one constant direction per seed, strength inside its documented range;
* provenance — a constant seed and a constant bridge revision throughout.

Usage:
    python3 tools/check_weather_trace.py TRACE [--seed N] [--cycle N]
                                          [--rev REVISION]

Exits 0 when the trace is valid, 1 otherwise.
"""

from __future__ import annotations

import argparse
import json
import math
import sys

TOLERANCE = 1e-6      # f64 snapshot -> 32-bit vec4 at the binding edge
PHASE_TOLERANCE = 1e-4  # same formula, plus the 32-bit W conversion

REQUIRED_KEYS = (
    "tick",
    "snapshot_tick",
    "seed",
    "wind_dir_x",
    "wind_dir_z",
    "wind_strength",
    "rain",
    "temperature",
    "light",
    "wind_global",
    "weather_bridge_rev",
)

failures = 0


def ok(message: str) -> None:
    print(f"ok    {message}")


def fail(message: str) -> None:
    global failures
    failures += 1
    print(f"FAIL  {message}")


def header(message: str) -> None:
    print(f"\n== {message} ==")


def is_finite(value) -> bool:
    return isinstance(value, (int, float)) and not isinstance(value, bool) and math.isfinite(value)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("trace")
    parser.add_argument("--seed", type=int, default=None)
    parser.add_argument("--cycle", type=int, default=240)
    parser.add_argument("--rev", default=None)
    args = parser.parse_args()

    try:
        with open(args.trace, encoding="utf-8") as handle:
            raw = handle.read()
    except OSError as error:
        fail(f"trace is unreadable: {error}")
        return finish(args.trace)

    header("shape")
    lines = raw.splitlines()
    if lines and lines[-1] == "":
        lines.pop()
    if not raw.endswith("\n"):
        fail("the trace does not end with a newline")
    if any(line == "" for line in lines):
        fail("the trace contains an empty line")
    ok(f"{len(lines)} non-empty JSON Lines records")

    records = []
    for index, line in enumerate(lines):
        try:
            record = json.loads(line)
        except json.JSONDecodeError as error:
            fail(f"line {index + 1} is not JSON: {error}")
            continue
        if not isinstance(record, dict):
            fail(f"line {index + 1} is not a JSON object")
            continue
        missing = [key for key in REQUIRED_KEYS if key not in record]
        extra = [key for key in record if key not in REQUIRED_KEYS]
        if missing:
            fail(f"line {index + 1} is missing keys {missing}")
        if extra:
            fail(f"line {index + 1} has unexpected keys {extra}")
        records.append(record)

    header("tick contract (snapshot tick == driven world-clock tick)")
    if len(records) != args.cycle:
        fail(f"{len(records)} records for a {args.cycle}-tick cycle")
    tick_ok = True
    for expected, record in enumerate(records):
        if record.get("tick") != expected:
            fail(f"record {expected} has tick {record.get('tick')}, expected {expected}")
            tick_ok = False
            break
        if record.get("snapshot_tick") != record.get("tick"):
            fail(
                f"tick {record.get('tick')}: snapshot_tick "
                f"{record.get('snapshot_tick')} != the world-clock tick that drove it"
            )
            tick_ok = False
            break
    if tick_ok and len(records) == args.cycle:
        ok(f"every record's snapshot tick equals its driven world-clock tick (0..{args.cycle - 1})")

    header("provenance")
    seeds = {record.get("seed") for record in records}
    if len(seeds) != 1 or not all(isinstance(seed, int) for seed in seeds):
        fail(f"the seed is not one constant integer across the trace: {seeds}")
    else:
        seed = seeds.pop()
        ok(f"one constant seed across every record: {seed}")
        if args.seed is not None and seed != args.seed:
            fail(f"seed {seed} != the fixture's seed {args.seed}")

    revisions = {record.get("weather_bridge_rev") for record in records}
    if len(revisions) != 1 or not all(isinstance(rev, str) for rev in revisions):
        fail(f"the bridge revision is not one constant string: {revisions}")
    else:
        revision = revisions.pop()
        if not revision.startswith("remich-weather-"):
            fail(f"revision {revision!r} does not look like a weather bridge revision")
        else:
            ok(f"one constant weather bridge revision: {revision}")
        if args.rev is not None and revision != args.rev:
            fail(f"revision {revision!r} != the staged expectation {args.rev!r}")

    header("plain data")
    numeric_fields = (
        "wind_dir_x",
        "wind_dir_z",
        "wind_strength",
        "rain",
        "temperature",
        "light",
    )
    numbers_ok = True
    directions = set()
    for record in records:
        for field in numeric_fields:
            if not is_finite(record.get(field)):
                fail(f"tick {record.get('tick')}: {field} is not a finite number")
                numbers_ok = False
        strength = record.get("wind_strength", math.nan)
        if is_finite(strength) and not 0.0 <= strength <= 1.0:
            fail(f"tick {record.get('tick')}: wind strength {strength} outside the fixture's 0..1 range")
            numbers_ok = False
        light = record.get("light", math.nan)
        if is_finite(light) and not 0.0 <= light <= 1.0:
            fail(f"tick {record.get('tick')}: light {light} outside 0..1")
            numbers_ok = False
        direction = (record.get("wind_dir_x"), record.get("wind_dir_z"))
        if all(is_finite(value) for value in direction):
            length = math.hypot(direction[0], direction[1])
            if abs(length - 1.0) > 1e-9:
                fail(f"tick {record.get('tick')}: wind direction {direction} is not a unit vector")
                numbers_ok = False
            directions.add(direction)
    if numbers_ok:
        ok("every weather field is finite; strength/light in range; direction is a unit vector")
    if len(directions) != 1:
        fail(f"the seed should select ONE direction for the whole trace, saw {len(directions)}")
    else:
        ok(f"the seed's single unit direction holds all day: {directions.pop()}")

    header("mapping to grengewald_wind (X/Y/Z from the snapshot, W presentation)")
    mapping_ok = True
    half = args.cycle - args.cycle // 2
    calm_max = -1.0
    windy_min = math.inf
    for record in records:
        tick = record.get("tick")
        vector = record.get("wind_global")
        if not isinstance(vector, list) or len(vector) != 4 or not all(
            is_finite(value) for value in vector
        ):
            fail(f"tick {tick}: wind_global {vector!r} is not four finite numbers")
            mapping_ok = False
            continue
        x, y, z, w = vector
        if abs(x - record["wind_dir_x"]) > TOLERANCE:
            fail(f"tick {tick}: applied X {x} != snapshot direction X {record['wind_dir_x']}")
            mapping_ok = False
        if abs(y - record["wind_dir_z"]) > TOLERANCE:
            fail(f"tick {tick}: applied Y {y} != snapshot direction Z {record['wind_dir_z']}")
            mapping_ok = False
        expected_z = min(max(record["wind_strength"], 0.0), 1.0)
        if abs(z - expected_z) > TOLERANCE:
            fail(f"tick {tick}: applied Z {z} != adapted strength {expected_z}")
            mapping_ok = False
        expected_w = (tick % args.cycle) / args.cycle * math.tau
        if not 0.0 <= w <= math.tau + PHASE_TOLERANCE:
            fail(f"tick {tick}: W {w} outside [0, 2*PI)")
            mapping_ok = False
        elif abs(w - expected_w) > PHASE_TOLERANCE:
            fail(f"tick {tick}: W {w} != the tick-derived presentation phase {expected_w}")
            mapping_ok = False

        strength = record["wind_strength"]
        if tick < half:
            calm_max = max(calm_max, strength)
        else:
            windy_min = min(windy_min, strength)
    if mapping_ok:
        ok("applied X/Y/Z equal the snapshot on every tick; W is the tick-derived presentation phase")

    header("stand-in shape: calm morning, windy afternoon")
    if calm_max > 0.1:
        fail(f"morning wind strength reached {calm_max}, expected <= 0.1 (calm)")
    else:
        ok(f"morning is calm: strength never above {calm_max}")
    if windy_min < 0.5:
        fail(f"afternoon wind strength fell to {windy_min}, expected >= 0.5 (windy)")
    else:
        ok(f"afternoon is windy: strength never below {windy_min}")

    return finish(args.trace)


def finish(path: str) -> int:
    print("\n========================================")
    if failures == 0:
        print(f"PASS  weather trace {path}")
        print("========================================")
        return 0
    print(f"FAIL  weather trace {path} — {failures} check(s) failed")
    print("========================================")
    return 1


if __name__ == "__main__":
    sys.exit(main())
