#!/usr/bin/env python3
"""Validate a Phase 1 Step 5 day trace (docs/remich-day-step5.md).

This reads a trace written by `godot/day_probe.gd` and checks it with an
implementation that shares no code with the Godot script that produced it: the
file is the only thing the two have in common.

It deliberately does NOT contain a hand-written expected choice schedule. The
Step 4 fixture already qualifies exact scoring (`tools/check_phase1_step4.sh`
and `crates/remich_core/tests/seed_sensitive_fixture.rs`); what this validator
qualifies is the repeated day loop and the trace that documents it. Everything
it asserts here is either structural (shape, ordering, consistency) or a clock
convention the harness itself declares. Decay arithmetic is not reimplemented
either — the harness records the verdict Rust gave it for the sequential-vs-
direct comparison, and this checks that verdict and that both arrays are there
and agree.

Usage:
    python3 tools/check_day_trace.py TRACE [--scorer-source PATH]

Exits 0 when the trace is valid, 1 otherwise.
"""

from __future__ import annotations

import argparse
import json
import math
import re
import sys

CHECKPOINTS = 24
TICKS_PER_CHECKPOINT = 10
FINAL_TICK = 240
NEED_COUNT = 7
SAFETY_INDEX = 3

# The caller-declared activities, in the order the fixture supplies them.
INPUT_IDS = [2, 1, 16, 14, 12, 5]

# The committed fixture's inputs (not its results).
FIXTURE_SEED = 60628
FIXTURE_INITIAL_NEEDS = [0.40, 0.35, 0.60, 0.50, 0.45, 0.42, 0.55]
TIME_OF_DAY_FORMULA = "checkpoint / 24.0"

RECORD_TYPES = ("fixture", "decision", "summary")

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
    return isinstance(value, (int, float)) and not isinstance(value, bool) \
        and math.isfinite(float(value))


def finite_needs(values, where: str) -> bool:
    if not isinstance(values, list) or len(values) != NEED_COUNT:
        fail(f"{where} has {len(values) if isinstance(values, list) else type(values).__name__}"
             f" needs, expected {NEED_COUNT}")
        return False
    good = True
    for index, value in enumerate(values):
        if not is_finite(value):
            fail(f"{where} need {index} is not a finite number: {value!r}")
            good = False
        elif not 0.0 <= float(value) <= 1.0:
            fail(f"{where} need {index} is {value}, outside [0.0, 1.0]")
            good = False
    return good


def load(path: str):
    records = []
    with open(path, "r", encoding="utf-8") as handle:
        for number, line in enumerate(handle, start=1):
            text = line.rstrip("\n")
            if not text.strip():
                fail(f"line {number} is blank")
                continue
            try:
                records.append((number, json.loads(text)))
            except json.JSONDecodeError as exc:
                fail(f"line {number} is not valid JSON: {exc}")
    return records


def scorer_revision(source_path: str) -> str:
    try:
        with open(source_path, "r", encoding="utf-8") as handle:
            text = handle.read()
    except OSError as exc:
        fail(f"could not read the scorer source {source_path}: {exc}")
        return ""
    match = re.search(r'pub const SCORER_BRIDGE_REV:\s*&str\s*=\s*"([^"]*)"', text)
    if match is None:
        fail(f"no SCORER_BRIDGE_REV in {source_path}")
        return ""
    return match.group(1)


def same_needs(left, right) -> bool:
    if not isinstance(left, list) or not isinstance(right, list):
        return False
    if len(left) != len(right):
        return False
    return all(float(a) == float(b) for a, b in zip(left, right))


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("trace", help="path to the JSON Lines day trace")
    parser.add_argument(
        "--scorer-source",
        default="crates/remich_gdext/src/lib.rs",
        help="Rust file that declares the committed SCORER_BRIDGE_REV",
    )
    args = parser.parse_args()

    expected_revision = scorer_revision(args.scorer_source)
    if not expected_revision:
        return finish(args.trace)

    header("1. The trace is readable and well formed")
    try:
        raw_lines = load(args.trace)
    except OSError as exc:
        fail(f"could not read the trace {args.trace}: {exc}")
        return finish(args.trace)
    if failures:
        return finish(args.trace)
    ok(f"{len(raw_lines)} lines, all valid JSON")

    records = [record for _, record in raw_lines]
    unknown = [r for r in records if r.get("type") not in RECORD_TYPES]
    if unknown:
        fail(f"{len(unknown)} line(s) carry an unknown record type")
    fixtures = [r for r in records if r.get("type") == "fixture"]
    decisions = [r for r in records if r.get("type") == "decision"]
    summaries = [r for r in records if r.get("type") == "summary"]

    header("2. The record kinds and their order")
    if len(fixtures) != 1:
        fail(f"{len(fixtures)} fixture records, expected 1")
    else:
        ok("exactly one fixture record")
    if records and records[0].get("type") != "fixture":
        fail("the fixture record is not first")
    elif fixtures:
        ok("the fixture record opens the trace")
    if len(summaries) != 1:
        fail(f"{len(summaries)} summary records, expected 1")
    else:
        ok("exactly one final summary record")
    if records and records[-1].get("type") != "summary":
        fail("the summary record is not last")
    elif summaries:
        ok("the summary record closes the trace")

    header("3. Exactly 24 decision checkpoints, 0..23, ticks 0..230")
    if len(decisions) != CHECKPOINTS:
        fail(f"{len(decisions)} decision records, expected {CHECKPOINTS}")
    else:
        ok(f"exactly {CHECKPOINTS} decision records")
    for index, decision in enumerate(decisions):
        if decision.get("checkpoint") != index:
            fail(f"decision {index} declares checkpoint {decision.get('checkpoint')!r}")
            break
    else:
        ok(f"checkpoint sequence runs 0..{CHECKPOINTS - 1} in order")
    bad_ticks = [
        d.get("checkpoint") for d in decisions
        if d.get("tick") != d.get("checkpoint", -1) * TICKS_PER_CHECKPOINT
    ]
    if bad_ticks:
        fail(f"ticks are not checkpoint x {TICKS_PER_CHECKPOINT}: {bad_ticks}")
    elif decisions:
        ok(f"ticks are 0, {TICKS_PER_CHECKPOINT}, ... "
           f"{(CHECKPOINTS - 1) * TICKS_PER_CHECKPOINT}")
    if decisions and decisions[-1].get("tick") != (CHECKPOINTS - 1) * TICKS_PER_CHECKPOINT:
        fail("the last decision is not at tick 230")
    elif decisions:
        ok("the last decision sits at tick 230, one boundary before the final 240")

    header("4. Normalized time of day covers the whole day")
    times = [d.get("time_of_day") for d in decisions]
    if not all(is_finite(t) for t in times):
        fail("a time_of_day is not a finite number")
    else:
        bad = [
            (index, t) for index, t in enumerate(times)
            if abs(float(t) - index / CHECKPOINTS) > 1e-12
        ]
        if bad:
            fail(f"time_of_day does not equal checkpoint/24 at {bad[:3]}")
        else:
            ok("every time_of_day equals checkpoint / 24.0")
        if not all(float(a) < float(b) for a, b in zip(times, times[1:])):
            fail("time_of_day does not increase strictly across the day")
        else:
            ok("time_of_day increases strictly through the day")
        if float(times[0]) != 0.0 or abs(float(times[-1]) - (CHECKPOINTS - 1) / CHECKPOINTS) > 1e-12:
            fail("the day does not start at 0.0 and end at 23/24")
        else:
            ok("the day runs from 0.0 to 23/24 across 24 checkpoints")

    header("5. Needs: seven values, finite, in range, and only ever decaying")
    needs_ok = True
    for index, decision in enumerate(decisions):
        if not finite_needs(decision.get("needs"), f"decision {index}"):
            needs_ok = False
            break
    if needs_ok:
        ok(f"every decision carries {NEED_COUNT} finite needs in [0.0, 1.0]")
    if decisions:
        safety = float(decisions[0].get("needs", [None] * NEED_COUNT)[SAFETY_INDEX]) \
            if isinstance(decisions[0].get("needs"), list) and len(decisions[0]["needs"]) > SAFETY_INDEX \
            else None
        if safety is None:
            fail("the first decision has no safety value to compare against")
        else:
            moved = [
                d.get("checkpoint") for d in decisions
                if not is_finite(d.get("needs", [None] * NEED_COUNT)[SAFETY_INDEX])
                or float(d["needs"][SAFETY_INDEX]) != safety
            ]
            if moved:
                fail(f"safety changed at checkpoint(s) {moved}, but its donor rate is 0.0")
            else:
                ok("safety is unchanged at every checkpoint")

    previous = None
    for index, decision in enumerate(decisions):
        current = decision.get("needs")
        if not isinstance(current, list) or len(current) != NEED_COUNT:
            continue
        if previous is not None:
            for need_index, (before, after) in enumerate(zip(previous, current)):
                if need_index == SAFETY_INDEX:
                    continue
                if not is_finite(before) or not is_finite(after):
                    continue
                if float(after) > float(before):
                    fail(f"need {need_index} rose from {before} to {after} "
                         f"between decisions {index - 1} and {index}")
        previous = current
    if failures == 0:
        ok("no non-safety need ever increases between consecutive checkpoints")

    header("6. Every decision scores all six candidates in the declared order")
    shape_ok = True
    for index, decision in enumerate(decisions):
        candidates = decision.get("candidates")
        if not isinstance(candidates, list) or len(candidates) != len(INPUT_IDS):
            fail(f"decision {index} has "
                 f"{len(candidates) if isinstance(candidates, list) else type(candidates).__name__}"
                 f" candidates, expected {len(INPUT_IDS)}")
            shape_ok = False
            break
        ids = [c.get("id") for c in candidates if isinstance(c, dict)]
        if ids != INPUT_IDS:
            fail(f"decision {index} candidate ids {ids} are not the declared input order {INPUT_IDS}")
            shape_ok = False
            break
        for c_index, candidate in enumerate(candidates):
            if not isinstance(candidate, dict):
                fail(f"decision {index} candidate {c_index} is not an object")
                shape_ok = False
                break
            if not is_finite(candidate.get("score")):
                fail(f"decision {index} candidate {c_index} score "
                     f"{candidate.get('score')!r} is not finite")
                shape_ok = False
                break
            if not isinstance(candidate.get("name"), str) or not isinstance(candidate.get("place"), str):
                fail(f"decision {index} candidate {c_index} has no name/place string")
                shape_ok = False
                break
        if not shape_ok:
            break
    if shape_ok:
        ok(f"every decision scores {len(INPUT_IDS)} candidates with ids {INPUT_IDS} in order")

    header("7. The chosen activity exists among that record's candidates")
    chosen_ok = True
    for index, decision in enumerate(decisions):
        chosen = decision.get("chosen")
        candidates = decision.get("candidates")
        if not isinstance(chosen, dict) or not isinstance(candidates, list):
            chosen_ok = False
            continue
        match = next(
            (c for c in candidates if isinstance(c, dict) and c.get("id") == chosen.get("id")),
            None,
        )
        if match is None:
            fail(f"decision {index}: chosen id {chosen.get('id')!r} is not among its candidates")
            chosen_ok = False
            continue
        if chosen.get("name") != match.get("name") or chosen.get("place") != match.get("place"):
            fail(f"decision {index}: chosen name/place disagrees with its candidate")
            chosen_ok = False
            continue
        if not is_finite(chosen.get("score")) or float(chosen.get("score")) != float(match.get("score")):
            fail(f"decision {index}: chosen score disagrees with its candidate")
            chosen_ok = False
    if chosen_ok:
        ok("the chosen id, name, place and score agree with that record's candidate in every decision")

    header("8. One qualified decay boundary between checkpoints")
    step_values = [d.get("next_decay_steps") for d in decisions]
    if not step_values:
        fail("no decisions to check the decay cadence on")
    elif any(value != 1 for value in step_values):
        fail(f"next_decay_steps is {step_values}, expected 1 everywhere")
    else:
        ok(f"all {CHECKPOINTS} advances crossed exactly one donor boundary")

    header("9. Every decision and the summary carry the committed revision")
    revisions = {d.get("bridge_rev") for d in decisions}
    revisions.update(s.get("bridge_rev") for s in summaries)
    if revisions != {expected_revision}:
        fail(f"the trace reports revisions {sorted(map(str, revisions))}, "
             f"the committed scorer declares {expected_revision!r}")
    else:
        ok(f"every record reports {expected_revision!r} (read from {args.scorer_source})")

    header("10. The fixture is the committed stand-in day")
    fixture = fixtures[0] if fixtures else None
    if fixture is None:
        fail("no fixture record to validate")
    else:
        checks = [
            (fixture.get("seed") == FIXTURE_SEED, f"seed is {fixture.get('seed')!r}"),
            (fixture.get("checkpoints") == CHECKPOINTS, f"checkpoints is {fixture.get('checkpoints')!r}"),
            (fixture.get("ticks_per_checkpoint") == TICKS_PER_CHECKPOINT,
             f"ticks_per_checkpoint is {fixture.get('ticks_per_checkpoint')!r}"),
            (fixture.get("final_tick") == FINAL_TICK, f"final_tick is {fixture.get('final_tick')!r}"),
            (fixture.get("time_of_day_formula") == TIME_OF_DAY_FORMULA,
             f"time_of_day_formula is {fixture.get('time_of_day_formula')!r}"),
            (fixture.get("available_at_every_checkpoint") is True,
             "activities are not declared available at every checkpoint"),
            (same_needs(fixture.get("initial_needs"), FIXTURE_INITIAL_NEEDS),
             "initial needs are not the committed fixture"),
            ([a.get("id") for a in fixture.get("activities", []) if isinstance(a, dict)] == INPUT_IDS,
             "the fixture's activities are not the declared six"),
        ]
        for passed, message in checks:
            if not passed:
                fail(f"the fixture record: {message}")
        if all(passed for passed, _ in checks):
            ok("seed 60628, the committed initial needs, and the six declared activities")
        if finite_needs(fixture.get("initial_needs"), "the fixture record"):
            ok("the fixture's initial needs are seven finite values in [0.0, 1.0]")

    if decisions:
        first_needs = decisions[0].get("needs")
        if fixture is not None and not same_needs(first_needs, fixture.get("initial_needs")):
            fail("checkpoint 0 did not start from the fixture's initial needs")
        else:
            ok("checkpoint 0 starts from the fixture's initial needs")

    header("11. The final summary")
    summary = summaries[0] if summaries else None
    if summary is None:
        fail("no summary record to validate")
        return finish(args.trace)

    if summary.get("final_tick") != FINAL_TICK:
        fail(f"final tick is {summary.get('final_tick')!r}, expected {FINAL_TICK}")
    else:
        ok(f"final tick is {FINAL_TICK}")
    if summary.get("checkpoints") != CHECKPOINTS:
        fail(f"the summary counts {summary.get('checkpoints')!r} checkpoints, "
             f"expected {CHECKPOINTS}")
    else:
        ok(f"the summary counts {CHECKPOINTS} decision checkpoints")

    final_needs = summary.get("final_needs")
    if not finite_needs(final_needs, "the summary"):
        pass
    elif not same_needs(summary.get("direct_0_240_needs"), final_needs):
        fail("final needs and the direct 0 -> 240 needs differ")
    elif summary.get("sequential_equals_direct") is not True:
        fail("the harness did not record sequential == direct")
    else:
        ok("24 sequential advances landed exactly where a direct 0 -> 240 advance landed")

    if final_needs and decisions:
        last = decisions[-1].get("needs")
        if isinstance(last, list) and len(last) == NEED_COUNT:
            if float(final_needs[SAFETY_INDEX]) != float(last[SAFETY_INDEX]):
                fail("safety moved between the last checkpoint and the final state")
            elif any(float(final_needs[i]) > float(last[i]) for i in range(NEED_COUNT)
                     if i != SAFETY_INDEX):
                fail("a non-safety need rose between the last checkpoint and the final state")
            else:
                ok("the final needs continue the decay chain from checkpoint 23")

    first, last = summary.get("first_chosen"), summary.get("last_chosen")
    if decisions:
        for label, recorded, expected in (
            ("first", first, decisions[0].get("chosen")),
            ("last", last, decisions[-1].get("chosen")),
        ):
            if not isinstance(recorded, dict) or not isinstance(expected, dict):
                fail(f"the summary's {label}_chosen is missing")
            elif (recorded.get("id"), recorded.get("name"), recorded.get("place")) != \
                    (expected.get("id"), expected.get("name"), expected.get("place")):
                fail(f"the summary's {label}_chosen does not match the trace")
        if isinstance(first, dict) and isinstance(last, dict) and decisions:
            if (first.get("id"), first.get("name"), first.get("place")) == \
                    (decisions[0].get("chosen", {}).get("id"),
                     decisions[0].get("chosen", {}).get("name"),
                     decisions[0].get("chosen", {}).get("place")) and \
                    (last.get("id"), last.get("name"), last.get("place")) == \
                    (decisions[-1].get("chosen", {}).get("id"),
                     decisions[-1].get("chosen", {}).get("name"),
                     decisions[-1].get("chosen", {}).get("place")):
                ok("first and last chosen activities match the trace")

    observed = sorted({int(d["chosen"]["id"]) for d in decisions
                       if isinstance(d.get("chosen"), dict) and is_finite(d["chosen"].get("id"))})
    declared = summary.get("distinct_chosen_ids")
    if declared != observed:
        fail(f"distinct_chosen_ids is {declared}, the trace shows {observed}")
    elif summary.get("distinct_count") != len(observed):
        fail(f"distinct_count is {summary.get('distinct_count')}, "
             f"but distinct_chosen_ids has {len(observed)}")
    else:
        ok(f"{len(observed)} distinct chosen id(s) across the day: {observed} "
           "(recorded as observed, not prescribed)")

    return finish(args.trace)


def finish(path: str) -> int:
    print("\n========================================")
    if failures == 0:
        print(f"PASS  day trace {path}")
        print("========================================")
        return 0
    print(f"FAIL  day trace {path} — {failures} check(s) failed")
    print("========================================")
    return 1


if __name__ == "__main__":
    sys.exit(main())
