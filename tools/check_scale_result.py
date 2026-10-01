#!/usr/bin/env python3
"""Validate the machine-readable result block of the Phase 2 step 4 benchmark.

Usage:

    python3 tools/check_scale_result.py <file> <smoke|official> <expected-rev> [--only NAME]

<file> is a captured benchmark run (tools/benchmark_phase2_step4.sh output)
or the record document quoting one (docs/remich-scale-phase2-step4.md). It
checks the REMICH_SCALE_* block:

    env        the one REMICH_SCALE_ENV line: mode, populations, population
               order, warm-up and sample counts, timer, fixture parameters,
               the preflight fields, and the recorded environment (engine,
               toolchain, profile, library, machine);
    ok         exactly one REMICH_SCALE_OK line, no REMICH_SCALE_FAIL line,
               and its mode/counts/revision fields match the run;
    presence   one REMICH_SCALE_RESULT line per population, exactly four,
               covering 1, 10, 100 and 1000;
    order      the four lines appear in exactly 1, 10, 100, 1000 order;
    calls      the method on every line (warm-up and sample counts for the
               mode) and the call arithmetic: total_calls is exactly
               samples * inhabitants, warmup_calls exactly warmup * N — so
               a measured sample provably performs exactly N scorer calls;
    values     every timing value parses as a finite, non-negative number,
               every integer field is a plain non-negative integer, p95 is
               at least the median (they are order statistics of the same
               samples), the per-inhabitant median is derived from the tick
               median, and every line carries the expected scorer revision.

No timing value is ever compared against a performance limit: a slower
measurement is a result, not a failure, and this validator only decides
whether a measurement is well-formed.
"""

import math
import re
import sys

POPULATIONS = [1, 10, 100, 1000]
METHOD = {"smoke": (1, 3), "official": (10, 100)}
REQUIRED_ENV = {
    "populations": "1,10,100,1000",
    "order": "1,10,100,1000",
    "timer": "Time.get_ticks_usec",
    "fixture": "1000",
    "seed_base": "60628",
    "profiles": "8",
    "time_of_day": "0.5",
    "activities": "6",
    "skills": "0",
    "damage": "0.0",
    "mood": "0.0",
    "scorer_instances": "1",
    "preflight": "ok",
    "preflight_inputs": "1000",
    "preflight_passes": "2",
    "profile": "debug",
    "lib": "target/debug/libremich_gdext.so",
    "os": "Linux",
}
RESULT_KEYS = [
    "inhabitants",
    "warmup",
    "samples",
    "total_calls",
    "warmup_calls",
    "median_us",
    "p95_us",
    "mean_us",
    "median_us_per_inhabitant",
    "checksum",
    "rev",
]
INTEGER_FIELDS = [
    "inhabitants",
    "warmup",
    "samples",
    "total_calls",
    "warmup_calls",
    "checksum",
]
TIMING_FIELDS = ["median_us", "p95_us", "mean_us", "median_us_per_inhabitant"]
PLAIN_INTEGER = re.compile(r"^[0-9]+$")

problems = []


def problem(message):
    problems.append(message)


def parse_fields(line, marker):
    fields = {}
    for token in line.split()[1:]:
        if "=" not in token:
            problem("%s line has a token without '=': %r" % (marker, token))
            continue
        key, value = token.split("=", 1)
        fields[key] = value
    return fields


def finite_number(text, where):
    try:
        value = float(text)
    except ValueError:
        problem("%s is not a number: %r" % (where, text))
        return None
    if not math.isfinite(value):
        problem("%s is not finite: %r" % (where, text))
        return None
    if value < 0.0:
        problem("%s is negative: %r" % (where, text))
        return None
    return value


def check_env(env_lines, mode, warmup, samples, rev):
    if len(env_lines) != 1:
        problem("expected exactly one REMICH_SCALE_ENV line, found %d"
                % len(env_lines))
        return
    fields = parse_fields(env_lines[0], "ENV")
    for key, expected in REQUIRED_ENV.items():
        if fields.get(key) != expected:
            problem("ENV %s=%r, expected %r"
                    % (key, fields.get(key), expected))
    for key, expected in (("mode", mode), ("warmup", str(warmup)),
                          ("samples", str(samples)), ("rev", rev)):
        if fields.get(key) != expected:
            problem("ENV %s=%r, expected %r"
                    % (key, fields.get(key), expected))
    if not fields.get("godot", "").startswith("4.7.2"):
        problem("ENV godot=%r is not the pinned 4.7.2 engine"
                % fields.get("godot"))
    if not re.match(r"^[0-9]+\.[0-9]+\.[0-9]+", fields.get("rust", "")):
        problem("ENV rust=%r is not an exact toolchain version"
                % fields.get("rust"))
    if not fields.get("kernel"):
        problem("ENV kernel is empty")
    if not fields.get("arch"):
        problem("ENV arch is empty")
    cpu = fields.get("cpu", "")
    if not cpu or cpu == "unknown":
        problem("ENV cpu=%r does not name the machine" % cpu)
    signature = fields.get("preflight_signature", "")
    if not PLAIN_INTEGER.match(signature or ""):
        problem("ENV preflight_signature=%r is not a non-negative integer"
                % signature)


def check_ok(ok_lines, mode, warmup, samples, rev):
    if len(ok_lines) != 1:
        problem("expected exactly one REMICH_SCALE_OK line, found %d"
                % len(ok_lines))
        return
    fields = parse_fields(ok_lines[0], "OK")
    for key, expected in (("populations", "1,10,100,1000"), ("mode", mode),
                          ("warmup", str(warmup)), ("samples", str(samples)),
                          ("timer", "Time.get_ticks_usec"), ("rev", rev)):
        if fields.get(key) != expected:
            problem("OK %s=%r, expected %r"
                    % (key, fields.get(key), expected))


def inhabitants_of(result_lines):
    found = []
    for line in result_lines:
        fields = parse_fields(line, "RESULT")
        found.append(fields.get("inhabitants"))
    return found


def check_presence(result_lines):
    if len(result_lines) != 4:
        problem("expected exactly four REMICH_SCALE_RESULT lines, found %d"
                % len(result_lines))
        return
    seen = inhabitants_of(result_lines)
    for population in POPULATIONS:
        if str(population) not in seen:
            problem("no result line for inhabitants=%d" % population)


def check_order(result_lines):
    if len(result_lines) != 4:
        problem("expected exactly four REMICH_SCALE_RESULT lines, found %d"
                % len(result_lines))
        return
    seen = inhabitants_of(result_lines)
    expected = [str(p) for p in POPULATIONS]
    if seen != expected:
        problem("result lines are for inhabitants=%s, expected %s in order"
                % (",".join(seen), ",".join(expected)))


def check_calls(result_lines, warmup, samples):
    for line in result_lines:
        fields = parse_fields(line, "RESULT")
        where = "inhabitants=%s" % fields.get("inhabitants", "?")
        if fields.get("warmup") != str(warmup):
            problem("%s: warmup=%r, expected %d"
                    % (where, fields.get("warmup"), warmup))
        if fields.get("samples") != str(samples):
            problem("%s: samples=%r, expected %d"
                    % (where, fields.get("samples"), samples))
        for key in ("inhabitants", "total_calls", "warmup_calls"):
            if not PLAIN_INTEGER.match(fields.get(key) or ""):
                problem("%s: %s=%r is not a non-negative integer"
                        % (where, key, fields.get(key)))
        inhabitants = fields.get("inhabitants")
        total = fields.get("total_calls")
        warmup_calls = fields.get("warmup_calls")
        if PLAIN_INTEGER.match(inhabitants or "") \
                and PLAIN_INTEGER.match(total or ""):
            if int(total) != samples * int(inhabitants):
                problem("%s: total_calls=%d, expected samples(%d) * "
                        "inhabitants(%d) = %d"
                        % (where, int(total), samples, int(inhabitants),
                           samples * int(inhabitants)))
        if PLAIN_INTEGER.match(inhabitants or "") \
                and PLAIN_INTEGER.match(warmup_calls or ""):
            if int(warmup_calls) != warmup * int(inhabitants):
                problem("%s: warmup_calls=%d, expected warmup(%d) * "
                        "inhabitants(%d) = %d"
                        % (where, int(warmup_calls), warmup,
                           int(inhabitants), warmup * int(inhabitants)))


def check_values(result_lines, rev):
    for line in result_lines:
        fields = parse_fields(line, "RESULT")
        where = "inhabitants=%s" % fields.get("inhabitants", "?")
        for key in RESULT_KEYS:
            if key not in fields:
                problem("%s: missing field %s" % (where, key))
        for key in INTEGER_FIELDS:
            if key in fields and not PLAIN_INTEGER.match(fields[key]):
                problem("%s: %s=%r is not a non-negative integer"
                        % (where, key, fields.get(key)))
        timings = {}
        for key in TIMING_FIELDS:
            if key in fields:
                value = finite_number(
                    fields[key], "%s: %s" % (where, key))
                if value is not None:
                    timings[key] = value
        if "median_us" in timings and "p95_us" in timings:
            if timings["p95_us"] < timings["median_us"]:
                problem("%s: p95_us=%s is below median_us=%s — the samples "
                        "cannot both describe one measurement"
                        % (where, fields["p95_us"], fields["median_us"]))
        if "median_us" in timings and "median_us_per_inhabitant" in timings:
            inhabitants = fields.get("inhabitants", "")
            if PLAIN_INTEGER.match(inhabitants) and int(inhabitants) > 0:
                derived = timings["median_us"] / int(inhabitants)
                tolerance = 5e-4 / int(inhabitants) + 1e-6
                if abs(timings["median_us_per_inhabitant"] - derived) \
                        > tolerance:
                    problem("%s: median_us_per_inhabitant=%s is not the tick "
                            "median (%s) divided by %s"
                            % (where, fields["median_us_per_inhabitant"],
                               fields["median_us"], inhabitants))
        if fields.get("rev") != rev:
            problem("%s: rev=%r, expected %r"
                    % (where, fields.get("rev"), rev))


def main(argv):
    if len(argv) < 4 or argv[1] in ("-h", "--help"):
        print(__doc__)
        return 2
    path, mode, rev = argv[1], argv[2], argv[3]
    only = None
    if "--only" in argv:
        index = argv.index("--only")
        if index + 1 >= len(argv):
            print("  | --only needs a name")
            return 2
        only = argv[index + 1]
    if mode not in METHOD:
        print("  | mode must be smoke or official, got %r" % mode)
        return 2
    warmup, samples = METHOD[mode]
    known = {"env", "ok", "presence", "order", "calls", "values"}
    if only is not None and only not in known:
        print("  | unknown check %r (known: %s)"
              % (only, ", ".join(sorted(known))))
        return 2

    try:
        with open(path, encoding="utf-8") as handle:
            lines = [line.strip() for line in handle]
    except OSError as error:
        print("  | cannot read %s: %s" % (path, error))
        return 1

    env_lines = [l for l in lines if l.startswith("REMICH_SCALE_ENV ")]
    ok_lines = [l for l in lines if l.startswith("REMICH_SCALE_OK ")]
    fail_lines = [l for l in lines if l.startswith("REMICH_SCALE_FAIL ")]
    result_lines = [l for l in lines if l.startswith("REMICH_SCALE_RESULT ")]

    if only in (None, "env"):
        check_env(env_lines, mode, warmup, samples, rev)
    if only in (None, "ok"):
        if fail_lines:
            problem("the run reported: %s" % fail_lines[0])
        check_ok(ok_lines, mode, warmup, samples, rev)
    if only in (None, "presence"):
        check_presence(result_lines)
    if only in (None, "order"):
        check_order(result_lines)
    if only in (None, "calls"):
        check_calls(result_lines, warmup, samples)
    if only in (None, "values"):
        check_values(result_lines, rev)

    if problems:
        for message in problems:
            print("  | %s" % message)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
