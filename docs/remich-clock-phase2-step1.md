# Remich — Phase 2, Step 1: one clock

*Record of the step described in `docs/PLAN.md` §4a, step 1. Acceptance:
`bash tools/check_phase2_step1.sh` — 23 checks, one command, run from any
directory. This document is the step's evidence: what the clock is, what was
measured on the committed head, what the sabotage did, and what this step
deliberately did not do.*

## 1. The clock model

One authoritative clock, in the engine-free core (`crates/remich_core/src/clock.rs`):

| state | type | meaning |
|---|---|---|
| `tick` | `u64` | the authoritative position: the next tick a pulse makes available |
| `tick_length_ns` | `u64` | the fixed tick duration, in whole nanoseconds; immutable after construction |
| `speed` | `u32` | integer multiplier ≥ 1: consecutive ticks per driver pulse |
| `paused` | `bool` | a paused clock emits nothing |

* **Advancement is an integer add.** `pulse()` is the only thing that moves the
  tick, and it does `tick += speed` (checked). There is no accumulated
  quantity anywhere in the authority.
* **The only floating-point expression in the module** is the edge
  `WorldClock::cycle_position(tick, cycle_length)`, which *presents* an
  already-existing integer tick as a position inside a caller-supplied cycle.
  It never decides which tick exists. Everything else — construction,
  pause/resume, speed changes, reset, the batch API — is integer.
* **No engine anywhere in the core.** `crates/remich_core` names no `godot`
  or `gdext` in its manifest, its source, or its resolved dependency tree
  (checks 3 of the acceptance script), and `pulse()` takes no `delta`
  argument: there is no Godot frame time to feed it.
* **The core does not decree a day.** Cycle length is always the caller's
  argument. `240` is *this test project's fixture* cycle length (a 24-hour day
  of 240 ticks in the test harness), not a claim about any game's simulation
  rate.

**Test-project tick length (configuration, not core law):** `100_000_000` ns
(100 ms), declared as `TEST_TICK_LENGTH_NS` in `godot/world_clock.gd` and
passed to the core at initialization. The core only requires `> 0`.

## 2. Pause and speed semantics

* `pause()` → subsequent pulses return an **empty batch**; the tick does not
  move. `resume()` continues at **exactly** the next integer tick; speed is
  retained across a pause and changes only on explicit request.
* `set_speed(0)` is **refused** (`ClockError::ZeroSpeed`): stopping is what
  pause is for, so a zero speed can never silently mean "paused but claiming
  speed 0".
* Speed means *more consecutive ticks per pulse*, never skipped simulation:
  * speed 1, one pulse → `[t, t+1)` — one tick;
  * speed 4, one pulse → `[t, t+1, t+2, t+3)` — four ticks, in order;
  * paused, one pulse → `[]`.
* Every tick in a batch is meant to be processed in order. The tests prove a
  speed-4 pulse cannot turn `8` into `12` while `9, 10, 11, 12` disappear
  (`a_speed_four_pulse_cannot_turn_8_into_12`), that a long run never skips or
  repeats a tick, and that the tick sequence at speed 1 and speed 4 is the
  *same ordered sequence* — only the number of pulses differs
  (`speed_one_and_speed_four_emit_the_same_ordered_ticks`).

## 3. One shared node in Godot

* `godot/world_clock.gd` is the single shared clock script: it creates
  **exactly one** native `RemichWorldClock` instance (one
  `ClassDB.instantiate(CLOCK_CLASS)` in the whole project, asserted by the
  acceptance script) and delegates every call to it. It holds no tick of its
  own — there is no parallel GDScript tick counter anywhere.
* It is registered once as the `WorldClock` autoload in
  `godot/project.godot`. Every other script reaches the clock through that
  node (`WorldClock.pulse()`, `WorldClock.cycle_position(...)`,
  `WorldClock.is_ready()`), never with a second instance.
* The native class (`RemichWorldClock` in `crates/remich_gdext`) exposes only
  integer observables — `tick`, `tick_length_ns`, `speed`, `is_paused` — and
  `pulse()` takes **zero** arguments (no float `delta` parameter, no
  advance-by-seconds API). `godot/clock_probe.gd` asserts that at runtime:
  `pulse_args=0`.

## 4. The scorer and the day now run on this clock

`godot/day_probe.gd` (the Phase 1 day harness) was rewired: it no longer
synthesizes ticks from a checkpoint counter. It now

* drives the whole day by looping `batch = WorldClock.pulse()` and iterating
  every tick of every batch until the shared clock reaches the fixture's
  final tick (240);
* derives `time_of_day` through `WorldClock.cycle_position(tick,
  TEST_CYCLE_LENGTH)` — the shared clock, not a GDScript float division;
* makes its decisions on the ticks the clock handed out (every 10th tick,
  24 of them), so the scorer and decay read the tick they were given, never a
  computed stand-in.

Phase 1's qualified markers still appear in the same engine run:
`REMICH_SCORER_OK`, `REMICH_DECAY_OK`, `REMICH_BRIDGE_OK`, plus
`REMICH_DAY_OK checkpoints=24 final_tick=240` and the new
`REMICH_CLOCK_OK …` proof line.

## 5. Evidence: traces, hashes, timings

All measured on the committed head of this branch (the **measured commit**
below), warning-free.

**Byte-identical traces (acceptance checks 15–18).** Three runs of the same
fixed day — speed 1 twice (determinism) and speed 4 once — produce
byte-identical 26-line traces, each still carrying the full Phase 1 record
(fixture, decisions with `tick` / `time_of_day` / `needs` / `candidates` /
`chosen`, summary with `final_tick`), and each accepted unchanged by the
Phase 1 validator `tools/check_day_trace.py`:

| run | SHA-256 |
|---|---|
| speed 1, run 1 | `6a5c78729a519163a16d2e754ed74d63ff0a3b9d0a957ef19b8543a89fe4ce2b` |
| speed 1, run 2 | `6a5c78729a519163a16d2e754ed74d63ff0a3b9d0a957ef19b8543a89fe4ce2b` |
| speed 4 | `6a5c78729a519163a16d2e754ed74d63ff0a3b9d0a957ef19b8543a89fe4ce2b` |

All three hashes are equal, and the speed-4 run's in-engine proof line shows
the shared clock at `tick=240 speed=4` afterwards, with the intermediate
batches intact (`resume_batch=240,241,242,243 speed4_second=244,245,246,247`).

**Measured commit:** `30bd88a8e89b71a0b379da9bf7554e7036db087d`
("Phase 2 Step 1 — one clock"), tree clean at measurement time. Only this
document changed afterwards.

**Timing A — clean build** (after `cargo clean`):

```
cargo clean && cargo build --workspace     → 42.12 s   (rc 0, zero warnings)
```

**Timing B — one-line rebuild through Godot.** Exactly one line changed:
`CLOCK_BRIDGE_REV` in `crates/remich_gdext/src/lib.rs` from
`remich-clock-v1` to `remich-clock-v2`. Then rebuild + one engine day run,
timed together until the engine *observed* the new revision:

```
cargo build --workspace && bash tools/run_day.sh <trace> 1
  → 0.92 s   (rc 0)
  → REMICH_CLOCK_OK … rev=remich-clock-v2 …    (Godot saw v2 in-process)
```

Restored byte-for-byte (`git checkout --`), rebuilt and re-run to prove the
committed value again:

```
cargo build --workspace && bash tools/run_day.sh <trace> 1
  → 0.92 s   (rc 0)
  → REMICH_CLOCK_OK … rev=remich-clock-v1 …
  → trace sha256 6a5c78729a519163a16d2e754ed74d63ff0a3b9d0a957ef19b8543a89fe4ce2b (matches)
  → git diff empty against the measured commit
```

(For comparison, Phase 1's one-line-through-Godot measurement was 0.73 s —
`docs/PLAN.md` §4a. The step's own numbers are the two above.)

## 6. The float-time sabotage, run and reverted

The scouts' warning (donor generation accumulated `f32` seconds and derived a
tick by flooring them) was re-introduced **temporarily and uncommitted**, and
the acceptance script was run against it.

**Command:**

```
python3 /tmp/apply_sabotage.py crates/remich_core/src/clock.rs   # uncommitted
bash tools/check_phase2_step1.sh                                  # → rc 1
git checkout -- crates/remich_core/src/clock.rs                   # byte-for-byte revert
```

**The exact diff** (9 insertions, 5 deletions, all in
`crates/remich_core/src/clock.rs`):

```diff
-#[derive(Debug, Clone, PartialEq, Eq)]
+#[derive(Debug, Clone, PartialEq)]
 pub struct WorldClock {
+    /// SABOTAGE: the donor's rejected shape — accumulated float seconds.
+    accumulated_seconds: f64,
     /// The authoritative position: the next tick a pulse will make available.
     tick: u64,
...
         Ok(Self {
+            accumulated_seconds: start_tick as f64 * (tick_length_ns as f64 / 1_000_000_000.0),
             tick: start_tick,
...
     pub fn reset(&mut self, tick: u64) {
+        self.accumulated_seconds = tick as f64 * (self.tick_length_ns as f64 / 1_000_000_000.0);
         self.tick = tick;
     }
...
         let batch = TickBatch::new(self.tick, self.speed);
-        self.tick = self
-            .tick
-            .checked_add(u64::from(self.speed))
-            .expect("WorldClock tick overflowed u64");
+        // SABOTAGE: float time decides which integer tick exists.
+        let seconds_per_tick = self.tick_length_ns as f64 / 1_000_000_000.0;
+        self.accumulated_seconds += f64::from(self.speed) * seconds_per_tick;
+        self.tick = self.accumulated_seconds.floor() as u64;
         batch
```

It compiles cleanly (so the failure is behavioural, not a build break) — and
acceptance still fails it: **47 checks failed, exit code 1**, including:

* **the source self-check** —
  `the_authoritative_clock_source_uses_no_float_time` panics with
  `a floating-point type appears outside cycle_position (offset 1576)`;
* **the exact-tick test** —
  `the long run must land on the exact integer tick: left: 40000, right: 400000`
  (the floored-seconds accumulator derives *seconds*, not ticks: 400 000 ticks
  of 100 ms = 40 000 s, and the floor returns 40 000 — the donor bug in one
  assertion);
* **speed-4 consecutiveness** — `a_speed_four_pulse_cannot_turn_8_into_12`,
  `no_tick_is_skipped_or_repeated_across_a_long_run` (batches repeat
  `0,1,2,3, 0,1,2,3, …` instead of advancing) and the speed-equivalence test;
* **pause/resume and speed-1 tests**;
* **the engine run itself** —
  `REMICH_CLOCK_FAIL reason=speed4-tick detail=after one speed-4 pulse the
  tick is 240, expected 244` and
  `REMICH_DAY_FAIL reason=checkpoints detail=the shared clock produced 241
  decision ticks, expected 24`, so no trace was produced;
* checks 15–18 (no valid traces, hashes differ), check 21 (the self-check is
  not green) and check 22 (the sabotaged file is an uncommitted modification).

**Reverted:** `git status --porcelain` empty and `git diff 30bd88a` empty —
the clock file is byte-identical to the measured commit. The final acceptance
run in §7 was made on the clean, final head with no sabotage present.

## 7. Final acceptance

`bash tools/check_phase2_step1.sh` on the clean, final committed head:
**exit code 0, 100 checks ok, 0 failed** (all 23 numbered sections). It
includes, as a sub-check, `bash tools/check_phase1_step3.sh` — the Phase 1
donor qualification (byte-identity to the pinned vault, provenance,
firewall, bridge, build) — which is green on this head.

The acceptance script also asserts, directly and independently of the Phase 1
scripts (which are left untouched as historical records):

* the plan merge `4bcb40d…` and the Phase 1 final merge `be11fa1c…` are
  ancestors of this head;
* donor code/data, provenance and `docs/PLAN.md` are unchanged since the plan
  merge;
* the clock core is engine-free and integer-authoritative (compiled
  self-checks, not grep alone);
* one shared node, one instantiation, one autoload, `pulse_args=0`;
* speed 1 and speed 4 walk the same ordered ticks with byte-identical traces
  and equal SHA-256s;
* the workspace builds and tests warning-free;
* no generated trace/build/staging state is tracked; the worktree is clean;
* no other repository was modified (donor vault pinned and clean;
  neighbouring repositories clean; the engine is only ever invoked headless,
  never in editor/import/export mode, which is what keeps Yolanda
  byte-for-byte untouched).

## 8. What this step deliberately did not do (refusals)

* **Did not modify any Phase 1 checker** (`tools/check_phase1_step4.sh`,
  `tools/check_phase1_step5.sh`). Their freeze assertions are historical
  qualification records and are intentionally incompatible with intentional
  Phase 2 work; this step re-proves their *substance* instead of weakening
  them. `tools/check_phase1_step3.sh` is run unmodified, as-is, as a
  sub-check.
* **Did not make 240 ticks/day a game-wide truth.** `240` appears only as the
  test fixture's cycle length (test project configuration and tests). The
  core takes the cycle length as an argument and decrees nothing.
* **Did not put float time anywhere near the authority** — no `f32`/`f64`
  state, no accumulated seconds, no `floor(seconds)`, no Godot `delta`. The
  single edge conversion is `cycle_position`, documented and tested as such.
* **Did not add a second clock**: no per-system clocks, no parallel GDScript
  tick counter, no engine-side accumulation.
* **Did not enter editor/import/export mode** on the pinned engine, and did
  not write to any other repository (Yolanda is used read-only, for its
  headless engine binary; the donor vault is read-only and remains pinned and
  clean).
* **Did not merge anything and did not start Step 2** (one weather
  snapshot). This step ends at its single pull request.

## 9. How to re-run everything

```
bash tools/check_phase2_step1.sh      # the 23 checks, one command
bash tools/run_day.sh <trace-path> 1  # a complete day at speed 1
bash tools/run_day.sh <trace-path> 4  # the same day at speed 4
cargo test -p remich_core clock::tests
```
