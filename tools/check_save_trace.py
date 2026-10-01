#!/usr/bin/env python3
"""Validate the Phase 2 Step 3 continuation traces (docs/remich-save-phase2-step3.md).

This reads the two traces written by `godot/save_probe.gd` — the uninterrupted
baseline and the fresh-process loaded run — and checks them with an
implementation that shares no code with the Godot script that produced them:
the files are the only thing the two have in common.

What it asserts, per trace:

* shape — a fixture record, exactly 12 continuation decision records
  (checkpoints 12..23, the decisions at and after the noon save point), and
  a summary record; JSON Lines, exact key sets;
* the noon continuation contract — every decision sits on its checkpoint's
  tick (`checkpoint * 10`), carries the fixture's seven needs in
  `[0, 1]`, the engine's scorer revision, all six candidate scores plus the
  chosen one (which must match one candidate exactly), the record's own
  weather snapshot (`snapshot.tick == tick`, all seven fields finite), and
  the inhabitant's current place;
* the summary — `final_tick == 240`, the final seven needs, the final
  weather snapshot (the last driven tick, 239), the final clock state, the
  12 chosen ids, and a distinct count consistent with them;
* no process-specific values — no absolute path appears in any string of
  either trace.

And, across the two traces:

* the fixture records are identical;
* all 12 continuation decision records are byte-for-byte the same values
  (tick, needs, choice, every candidate score, weather snapshot, place);
* the final clock, needs, weather and scorer choices agree.

Usage:
    python3 tools/check_save_trace.py BASELINE LOADED
                                      [--seed N] [--cycle N] [--identity S]

Exits 0 when both traces are valid and continuations of each other,
1 otherwise.
"""

import argparse
import json
import math
import sys

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
    return (
        isinstance(value, (int, float))
        and not isinstance(value, bool)
        and math.isfinite(value)
    )


FIXTURE_KEYS = {
    "type",
    "trace_format",
    "identity",
    "inhabitant",
    "seed",
    "current_place",
    "cycle_length",
    "noon_tick",
    "final_tick",
    "ticks_per_checkpoint",
    "need_order",
    "activities",
}
DECISION_KEYS = {
    "type",
    "checkpoint",
    "tick",
    "time_of_day",
    "seed",
    "needs",
    "bridge_rev",
    "chosen",
    "candidates",
    "next_decay_steps",
    "current_place",
    "weather",
}
CHOSEN_KEYS = {"id", "name", "place", "score"}
CANDIDATE_KEYS = {"id", "name", "place", "score"}
WEATHER_KEYS = {
    "tick",
    "wind_dir_x",
    "wind_dir_z",
    "wind_strength",
    "rain",
    "temperature",
    "light",
}
SUMMARY_KEYS = {
    "type",
    "trace_format",
    "identity",
    "inhabitant",
    "checkpoints",
    "final_tick",
    "final_needs",
    "final_weather",
    "final_clock",
    "chosen_ids",
    "distinct_count",
    "need_order",
}
NEED_ORDER = [
    "food",
    "water",
    "shelter",
    "safety",
    "sleep",
    "companionship",
    "joy",
]
PLACES = {"north-hills", "east-field", "market-square", "cottage-loft", "ridge", "kitchen"}
TRACE_FORMAT = "remich-save-continuation-v1"
NOON_TICK = 120
FINAL_TICK = 240
DECISIONS = 12


def load_trace(path: str):
    """Reads a trace into records, failing on unparseable lines."""
    try:
        with open(path, encoding="utf-8") as handle:
            raw_lines = handle.read().splitlines()
    except OSError as error:
        fail(f"{path}: cannot be read: {error}")
        return None
    records = []
    for index, line in enumerate(raw_lines):
        if not line.strip():
            fail(f"{path}: line {index + 1} is blank")
            continue
        try:
            records.append(json.loads(line))
        except json.JSONDecodeError as error:
            fail(f"{path}: line {index + 1} is not JSON: {error}")
    return records


def string_values(value):
    """Every string anywhere inside a structure (for the path scan)."""
    if isinstance(value, str):
        yield value
    elif isinstance(value, dict):
        for key, item in value.items():
            yield str(key)
            yield from string_values(item)
    elif isinstance(value, list):
        for item in value:
            yield from string_values(item)


def validate_trace(path: str, records, args):
    """Per-trace structural checks; returns (fixture, decisions, summary)."""
    header(f"structure of {path}")
    if records is None:
        return None, None, None
    if len(records) != DECISIONS + 2:
        fail(
            f"{path}: {len(records)} records, expected {DECISIONS + 2} "
            f"(fixture + {DECISIONS} decisions + summary)"
        )
        if len(records) < DECISIONS + 2:
            return None, None, None

    fixture, decisions, summary = records[0], records[1 : DECISIONS + 1], records[-1]

    # --- fixture ---------------------------------------------------------
    if fixture.get("type") != "fixture":
        fail(f"{path}: the first record is {fixture.get('type')!r}, expected 'fixture'")
    if set(fixture) != FIXTURE_KEYS:
        fail(f"{path}: fixture keys are {sorted(fixture)}, expected {sorted(FIXTURE_KEYS)}")
    else:
        checks = [
            (fixture["trace_format"] == TRACE_FORMAT, "trace_format"),
            (fixture["identity"] == args.identity, "identity"),
            (fixture["inhabitant"] == "standin-inhabitant-1", "inhabitant"),
            (fixture["seed"] == args.seed, "seed"),
            (fixture["current_place"] == "market-square", "current_place"),
            (fixture["cycle_length"] == args.cycle, "cycle_length"),
            (fixture["noon_tick"] == NOON_TICK, "noon_tick"),
            (fixture["final_tick"] == FINAL_TICK, "final_tick"),
            (fixture["ticks_per_checkpoint"] == 10, "ticks_per_checkpoint"),
            (fixture["need_order"] == NEED_ORDER, "need_order"),
        ]
        for passed, name in checks:
            if not passed:
                fail(f"{path}: fixture {name} is {fixture[name]!r}")
        activities = fixture["activities"]
        if not isinstance(activities, list) or len(activities) != 6:
            fail(f"{path}: fixture activities are {activities!r}, expected six")
        elif {a.get("place") for a in activities} != PLACES:
            fail(f"{path}: fixture activity places are not the six qualified places")
        if all(passed for passed, _ in checks):
            ok(
                f"{path}: fixture record — {args.identity}, seed {args.seed}, "
                f"noon {NOON_TICK}, final {FINAL_TICK}, six activities, seven needs"
            )

    # --- continuation decisions -----------------------------------------
    shape_ok = True
    for position, record in enumerate(decisions):
        checkpoint = 12 + position
        tick = checkpoint * 10
        where = f"{path}: decision at tick {tick}"
        if record.get("type") != "decision" or set(record) != DECISION_KEYS:
            fail(f"{where}: keys are {sorted(record)}, expected {sorted(DECISION_KEYS)}")
            shape_ok = False
            continue
        if record["checkpoint"] != checkpoint or record["tick"] != tick:
            fail(f"{where}: is checkpoint {record['checkpoint']} tick {record['tick']}")
            shape_ok = False
            continue
        if abs(record["time_of_day"] - tick / args.cycle) > 1e-9:
            fail(f"{where}: time_of_day {record['time_of_day']} != {tick / args.cycle}")
            shape_ok = False
        if record["seed"] != args.seed:
            fail(f"{where}: seed {record['seed']} != fixture seed {args.seed}")
            shape_ok = False
        if record["bridge_rev"] == "":
            fail(f"{where}: no scorer bridge revision")
            shape_ok = False
        needs = record["needs"]
        if (
            not isinstance(needs, list)
            or len(needs) != 7
            or not all(is_finite(n) and 0.0 <= n <= 1.0 for n in needs)
        ):
            fail(f"{where}: needs {needs!r} are not seven values in [0, 1]")
            shape_ok = False
        if record["current_place"] != "market-square":
            fail(f"{where}: current_place {record['current_place']!r}")
            shape_ok = False

        chosen = record["chosen"]
        candidates = record["candidates"]
        if not isinstance(chosen, dict) or set(chosen) != CHOSEN_KEYS:
            fail(f"{where}: chosen {chosen!r} does not carry exactly {sorted(CHOSEN_KEYS)}")
            shape_ok = False
        if not isinstance(candidates, list) or len(candidates) != 6:
            fail(f"{where}: {len(candidates) if isinstance(candidates, list) else candidates!r} "
                 "candidates, expected the six fixture activities")
            shape_ok = False
        else:
            for candidate in candidates:
                if (
                    not isinstance(candidate, dict)
                    or set(candidate) != CANDIDATE_KEYS
                    or not is_finite(candidate["score"])
                ):
                    fail(f"{where}: malformed candidate {candidate!r}")
                    shape_ok = False
                    break
            matching = [
                c for c in candidates
                if isinstance(c, dict)
                and c.get("id") == chosen.get("id")
                and c.get("score") == chosen.get("score")
            ]
            if not matching:
                fail(
                    f"{where}: chosen id {chosen.get('id')!r} score "
                    f"{chosen.get('score')!r} matches no candidate exactly"
                )
                shape_ok = False
        if record["next_decay_steps"] != 1:
            fail(f"{where}: next_decay_steps {record['next_decay_steps']}, expected 1")
            shape_ok = False

        weather = record["weather"]
        if not isinstance(weather, dict) or set(weather) != WEATHER_KEYS:
            fail(f"{where}: weather must carry exactly {sorted(WEATHER_KEYS)}")
            shape_ok = False
        else:
            if weather["tick"] != tick:
                fail(f"{where}: weather tick {weather['tick']} is not the record's tick")
                shape_ok = False
            for key in WEATHER_KEYS - {"tick"}:
                if not is_finite(weather[key]):
                    fail(f"{where}: weather {key} is not finite")
                    shape_ok = False
                    break
    if shape_ok:
        ok(
            f"{path}: {DECISIONS} continuation decisions — checkpoints 12..23, "
            "seven needs, six candidate scores + chosen, own-tick weather, place"
        )

    # --- summary ---------------------------------------------------------
    if summary.get("type") != "summary" or set(summary) != SUMMARY_KEYS:
        fail(f"{path}: summary keys are {sorted(summary)}, expected {sorted(SUMMARY_KEYS)}")
    else:
        summary_ok = True
        if summary["checkpoints"] != DECISIONS:
            fail(f"{path}: summary checkpoints {summary['checkpoints']}, expected {DECISIONS}")
            summary_ok = False
        if summary["final_tick"] != FINAL_TICK:
            fail(f"{path}: summary final_tick {summary['final_tick']}, expected {FINAL_TICK}")
            summary_ok = False
        needs = summary["final_needs"]
        if (
            not isinstance(needs, list)
            or len(needs) != 7
            or not all(is_finite(n) and 0.0 <= n <= 1.0 for n in needs)
        ):
            fail(f"{path}: summary final_needs {needs!r} are not seven values in [0, 1]")
            summary_ok = False
        weather = summary["final_weather"]
        if not isinstance(weather, dict) or set(weather) != WEATHER_KEYS:
            fail(f"{path}: summary final_weather must carry exactly {sorted(WEATHER_KEYS)}")
            summary_ok = False
        elif weather["tick"] != FINAL_TICK - 1:
            fail(f"{path}: final weather tick {weather['tick']}, expected {FINAL_TICK - 1}")
            summary_ok = False
        clock = summary["final_clock"]
        if not isinstance(clock, dict) or set(clock) != {"tick", "speed", "paused"}:
            fail(f"{path}: summary final_clock is {clock!r}")
            summary_ok = False
        else:
            if clock["tick"] != FINAL_TICK or clock["speed"] != 1 or clock["paused"] is not False:
                fail(f"{path}: final clock {clock!r}, expected tick 240, speed 1, running")
                summary_ok = False
        chosen_ids = summary["chosen_ids"]
        if (
            not isinstance(chosen_ids, list)
            or len(chosen_ids) != DECISIONS
            or not all(isinstance(i, int) for i in chosen_ids)
        ):
            fail(f"{path}: summary chosen_ids {chosen_ids!r}, expected 12 ints")
            summary_ok = False
        elif summary["distinct_count"] != len(set(chosen_ids)):
            fail(
                f"{path}: distinct_count {summary['distinct_count']} != "
                f"{len(set(chosen_ids))} distinct chosen ids"
            )
            summary_ok = False
        if summary["identity"] != fixture.get("identity"):
            fail(f"{path}: summary identity differs from the fixture record")
            summary_ok = False
        if summary["need_order"] != NEED_ORDER:
            fail(f"{path}: summary need_order differs from the seven-name order")
            summary_ok = False
        if summary_ok:
            ok(
                f"{path}: summary — final_tick 240, seven needs, weather tick 239, "
                f"clock 240/speed 1/running, 12 chosen ids, "
                f"{summary['distinct_count']} distinct"
            )

    # --- no process-specific values --------------------------------------
    strings = [text for record in records for text in string_values(record)]
    paths_found = [
        s for s in strings if "/home/" in s or "/tmp/" in s or "file://" in s
    ]
    if paths_found:
        fail(f"{path}: process-specific path values appear in the trace: {paths_found[:3]}")
    else:
        ok(f"{path}: no path or process-specific value appears anywhere in the trace")

    return fixture, decisions, summary


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("baseline")
    parser.add_argument("loaded")
    parser.add_argument("--seed", type=int, default=60628)
    parser.add_argument("--cycle", type=int, default=240)
    parser.add_argument("--identity", default="world-revision-A")
    args = parser.parse_args()

    print("== Phase 2 Step 3 continuation traces ==")
    baseline = load_trace(args.baseline)
    loaded = load_trace(args.loaded)

    base_fixture, base_decisions, base_summary = validate_trace(
        args.baseline, baseline, args
    )
    load_fixture, load_decisions, load_summary = validate_trace(
        args.loaded, loaded, args
    )

    header("the loaded continuation is the baseline continuation")
    if None in (base_fixture, base_decisions, base_summary, load_fixture,
                load_decisions, load_summary):
        fail("the traces could not be compared: at least one is malformed")
    else:
        if base_fixture == load_fixture:
            ok("the two fixture records are identical")
        else:
            fail(f"fixture records differ:\n  baseline: {base_fixture}\n  loaded:   {load_fixture}")

        first_difference = None
        for index, (left, right) in enumerate(zip(base_decisions, load_decisions)):
            if left != right:
                first_difference = (index, left, right)
                break
        if first_difference is None and len(base_decisions) == len(load_decisions):
            ok(
                f"all {DECISIONS} continuation decision records are identical "
                "(tick, needs, choice, all candidate scores, weather snapshot, place)"
            )
        elif first_difference is not None:
            index, left, right = first_difference
            fail(
                f"continuation decision {index} differs:\n"
                f"  baseline: {left}\n  loaded:   {right}"
            )
        else:
            fail(
                f"continuation record counts differ: {len(base_decisions)} vs "
                f"{len(load_decisions)}"
            )

        if (
            base_summary["final_needs"] == load_summary["final_needs"]
            and base_summary["final_weather"] == load_summary["final_weather"]
            and base_summary["final_clock"] == load_summary["final_clock"]
            and base_summary["chosen_ids"] == load_summary["chosen_ids"]
            and base_summary["distinct_count"] == load_summary["distinct_count"]
        ):
            ok(
                "final state agrees: clock, needs, weather and all 12 scorer "
                "choices are equal across the two runs"
            )
        else:
            fail("the two summaries' final state differs")
            for key in ("final_needs", "final_weather", "final_clock",
                        "chosen_ids", "distinct_count"):
                if base_summary[key] != load_summary[key]:
                    print(f"      {key}: {base_summary[key]!r} vs {load_summary[key]!r}")

    print("\n========================================")
    if failures == 0:
        print(f"PASS  continuation traces {args.baseline} and {args.loaded}")
        print("========================================")
        return 0
    print(
        f"FAIL  continuation traces {args.baseline} and {args.loaded} "
        f"— {failures} check(s) failed"
    )
    print("========================================")
    return 1


if __name__ == "__main__":
    sys.exit(main())
