# Remich — Phase 2, Step 4: many inhabitants, measured

*The lane's Phase 2 capability steps, step 4 of four (docs/PLAN.md §4a):*

> **Many inhabitants, measured.** The scorer for 1, 10, 100 and 1,000 stand-in
> inhabitants per tick, time per tick reported (groundwork for Forgeborn's
> Social LOD; no optimisation back and forth). *Acceptance:* the numbers
> posted with the command that reproduces them.

This record is the numbers and the command that reproduces them. It is a
baseline measurement of the existing path so that later work has something
to compare against — it is groundwork for Social LOD, not a Social LOD
implementation: nothing here decides population behaviour, invents
relationship or schedule state, changes the save format, or adds a capacity
policy. **No performance threshold.** No tuning back and forth, and no
judgement is printed with the numbers: a slower measurement is a result,
not a failure.

## 1. What one measured tick includes

One measured tick is:

> N calls through the real `RemichScorer.score_activity` — the same Godot →
> GDExtension → Rust bridge every Step 1-3 probe uses — over the fixed
> benchmark world/time state, each returned result consumed by folding its
> `chosen_id` into a running checksum, bracketed by the engine's monotonic
> `Time.get_ticks_usec()`.

Deliberately **outside the timed region**, because they are different costs:
fixture construction, scorer construction, the correctness preflight, the
warm-up samples, statistics, logging, JSON, weather, saving, need decay,
clock advancement and file I/O. The benchmark advances no game simulation
at all — it asks exactly one question: how long does the current scorer
path take to score N stand-in inhabitants for one tick?

## 2. The fixture (exactly one, built once)

Built once, before any timed work, with no runtime randomness anywhere.
For `index` in `0..999`:

| field | value |
|---|---|
| `seed` | `60628 + index` — a distinct donor-seeded state per inhabitant |
| `needs` | `NEEDS_PROFILES[index % 8]` — the committed eight-profile table, seven values each, every value strictly inside (0, 1) |
| `time_of_day` | `0.5` — the test fixture's noon position |
| `activities` | the six qualified activities: `2`/north-hills, `1`/east-field, `16`/market-square, `14`/cottage-loft, `12`/ridge, `5`/kitchen |
| `skills` | `[]` |
| `settlement_damage` | `0.0` |
| `settlement_aggregate_mood` | `0.0` |

Population 1, 10, 100 and 1000 are the first N entries of that same single
fixture — every population is a **prefix of the same 1,000** inputs, so the
four cases measure one workload family, not four different ones. The exact
generation rule lives in `godot/scale_benchmark.gd` (`_build_fixture`) and
is stated in the table above.

## 3. Method: one instance, a fixed order, the monotonic clock

* **one scorer instance** (`ClassDB.instantiate("RemichScorer")`), created
  before any timing and reused for the whole benchmark — construction and
  destruction never appear inside a measured sample;
* populations in fixed official order: 1, 10, 100, 1000 — never reordered
  after seeing results;
* **10 warm-up samples** per population (untimed, same path, not recorded),
  then **100 measured samples** per population;
* each measured sample: `Time.get_ticks_usec()` → exactly N scorer calls,
  each result's `chosen_id` folded into the sample checksum →
  `Time.get_ticks_usec()`; no logging inside the measured interval;
* median: the middle of the sorted samples (mean of the two middle values
  for an even count); p95: **nearest-rank** — the ceil(0.95 × samples)-th
  smallest; mean: arithmetic over the 100 samples; median µs/inhabitant =
  tick median ÷ N;
* correctness before performance: two untimed passes score all 1,000
  inputs first and require, per result, `ok`, the expected six candidate
  ids, a chosen id among them, finite chosen and candidate scores and the
  expected bridge revision — and require both passes' signatures to match
  (`preflight_signature=850168875` below). Nothing broken is ever
  benchmarked;
* every reported checksum is the sample-0 fold for that population: the
  smoke run and the official run reported byte-identical checksums
  (6 / 656248685 / 181725936 / 471619192), as the fixture rule requires.

No batching, no bulk API, no parallelism, no cached or precomputed scores,
no changed formula, seed or need: the scorer core and every Rust source are
byte-identical to the Step 3 merge (proven by the acceptance, checks 4-5).

## 4. The official environment

| item | value |
|---|---|
| Godot | pinned **Godot 4.7.2** (`Godot_v4.7.2-stable_linux.x86_64`, headless, `--script`, never editor/import/export) |
| Rust | repository pin `rust-toolchain.toml` channel **1.98.1** (`rustc 1.98.1 (48a229cea 2026-09-01)`) |
| build profile / library | development **debug** build — `cargo build --workspace`, loaded from `target/debug/libremich_gdext.so` (stated explicitly: the normal Cargo development/debug library, not a release build) |
| CPU | **AMD Ryzen 5 5600X** 6-Core Processor |
| OS / kernel | Linux, `7.2.8-1-cachyos`, x86_64 |
| machine state | ordinary development machine, untouched — no governor, GPU, core-pinning, service, priority, package or kernel changes of any kind |

## 5. The official result

The single official run, in full (the run's own wall time was 8.367 s
including engine start-up, fixture, preflight and all 111,110 scored
samples):

```text
REMICH_SCALE_ENV mode=official godot=4.7.2.stable.official.ed1daf0bf rust=1.98.1 profile=debug lib=target/debug/libremich_gdext.so os=Linux kernel=7.2.8-1-cachyos arch=x86_64 cpu=AMD_Ryzen_5_5600X_6-Core_Processor populations=1,10,100,1000 order=1,10,100,1000 warmup=10 samples=100 timer=Time.get_ticks_usec fixture=1000 seed_base=60628 profiles=8 time_of_day=0.5 activities=6 skills=0 damage=0.0 mood=0.0 scorer_instances=1 preflight=ok preflight_inputs=1000 preflight_passes=2 preflight_signature=850168875 rev=remich-scorer-v1
REMICH_SCALE_RESULT inhabitants=1 warmup=10 samples=100 total_calls=100 warmup_calls=10 median_us=65.0 p95_us=69.0 mean_us=65.04 median_us_per_inhabitant=65.0 checksum=6 rev=remich-scorer-v1
REMICH_SCALE_RESULT inhabitants=10 warmup=10 samples=100 total_calls=1000 warmup_calls=100 median_us=651.0 p95_us=653.0 mean_us=649.42 median_us_per_inhabitant=65.1 checksum=656248685 rev=remich-scorer-v1
REMICH_SCALE_RESULT inhabitants=100 warmup=10 samples=100 total_calls=10000 warmup_calls=1000 median_us=6430.0 p95_us=6459.0 mean_us=6434.5 median_us_per_inhabitant=64.3 checksum=181725936 rev=remich-scorer-v1
REMICH_SCALE_RESULT inhabitants=1000 warmup=10 samples=100 total_calls=100000 warmup_calls=10000 median_us=64462.5 p95_us=64805.0 mean_us=64518.79 median_us_per_inhabitant=64.4625 checksum=471619192 rev=remich-scorer-v1
REMICH_SCALE_OK populations=1,10,100,1000 mode=official warmup=10 samples=100 timer=Time.get_ticks_usec rev=remich-scorer-v1
```

Compact table:

| inhabitants | median µs/tick | p95 µs/tick | mean µs/tick | median µs/inhabitant |
|---:|---:|---:|---:|---:|
| 1 | 65.0 | 69.0 | 65.04 | 65.0 |
| 10 | 651.0 | 653.0 | 649.42 | 65.1 |
| 100 | 6430.0 | 6459.0 | 6434.5 | 64.3 |
| 1000 | 64462.5 | 64805.0 | 64518.79 | 64.4625 |

### Reproducing it

```bash
bash tools/benchmark_phase2_step4.sh
```

from a freshly built workspace (`cargo build --workspace`), on this
repository at the final head. The command fixes the method itself —
populations 1, 10, 100, 1000, 10 warm-up samples, 100 measured samples —
and prints one `REMICH_SCALE_RESULT` line per population plus
`REMICH_SCALE_OK`. The shorter `--smoke` form (1 warm-up, 3 measured
samples) exists for development only; its numbers are not these numbers.

## 6. Measured commit, build and rebuild timings

**Measured commit (executable state):** `4a7578437826fe7280e7e13d7a1200d5d1e70e4b`
— `Phase 2 Step 4 — many inhabitants, measured`. All executable files
(the benchmark script, its runner, this step's checker and its result
validator) exist exactly at that commit; only this record was added
afterwards.

**Clean build:** from the clean measured commit, the procedure
`cargo clean + cargo build --workspace` took 38.829 s end to end
(`cargo clean` 0.125 s wall, then `cargo build --workspace` **38.704 s
wall**: crates compiled: 31, warnings: 0, exit 0, development/debug
profile).

**One-line rebuild observed in Godot:** with the measured commit clean and
`remich-scorer-v1` observed in a smoke run first, exactly one line was
changed — `crates/remich_gdext/src/lib.rs`, `SCORER_BRIDGE_REV` `remich-scorer-v1`
→ `remich-scorer-v2` (1 file, 1 insertion, 1 deletion) — and the timed
command `cargo build --workspace` + `bash tools/benchmark_phase2_step4.sh
--smoke` (**`SCORER_BRIDGE_REV v1 -> v2 -> v1`**) ran: rebuild **0.609 s
wall** (1 crate: `remich_gdext`), smoke **0.752 s wall** → **1.361 s
end-to-end**, during which pinned Godot loaded the rebuilt extension and
the smoke benchmark reported `REMICH_SCALE_OK ... rev=remich-scorer-v2`
with all four populations executed (rev=remich-scorer-v2, exit 0). The line
was then restored byte-for-byte (sha256 of `lib.rs` equal to the pre-probe
hash `4d659ee25f00fab2b6be5e9a64c4ef7cd1c6df1cc04355252d408301a506dc48`,
`git diff` clean), the library rebuilt (0.614 s, 1 crate), and smoke
re-proved `rev=remich-scorer-v1` (exit 0). No `remich-scorer-v2` survives
outside documentation that records this measurement.

## 7. Acceptance

* Step 3 acceptance, run unchanged as a sub-check during this step's
  development: green — `tools/check_phase2_step3.sh` reported PASS on the
  clean measured commit, which transitively re-proves Steps 1-2 and
  Phase 1 (`REMICH_SAVE_OK`, `REMICH_SAVE_ADAPT_OK`, `REMICH_WEATHER_OK`,
  `REMICH_CLOCK_OK`, `REMICH_SCORER_OK`, `REMICH_DECAY_OK`,
  `REMICH_BRIDGE_OK`);
* Step 4 acceptance: `bash tools/check_phase2_step4.sh` — 31 checks, with
  the Step 3 checker as its sub-check and the benchmark re-exercised in
  smoke mode only. It is run exactly once on the clean final committed
  head — this record's own commit — immediately after this record lands;
  its result, the final head and this run count are reported in the PR
  body;
* `official benchmark runs: 1` — the single official run in §5, captured
  verbatim; the benchmark was not rerun afterwards, and no executable file
  changed after it (the measured → final diff is this record alone);
* No optimisation or tuning pass followed the official result.

## 8. Refusals and stops

None were needed, and none were taken for the wrong reason: no stop
condition fired (the scorer was never behaviourally modified, no new
scoring API was needed, no other repository was touched, no published
format changed). What this step deliberately **refused**, per the plan's
"no optimisation back and forth": introducing `score_many`, batching,
caching, threads, SIMD, population-specific shortcuts, reduced candidate
lists, altered formulas, altered seeds or needs, or any scorer path for
large populations; tuning after seeing the official numbers; publishing a
capacity recommendation, an FPS budget or a Social LOD threshold from
these measurements. The numbers stand exactly as measured.
