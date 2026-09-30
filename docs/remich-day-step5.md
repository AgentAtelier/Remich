# A day in the test project — Phase 1 Step 5 (record)

A stand-in inhabitant in Remich's own Godot project lives one test day through
the Step 4 scorer. Every checkpoint is one call into the real GDExtension; the
result — time, needs, choice, and all candidate scores — is written to a JSON
Lines file. The rebuild time is measured again with the scorer in place.

This is a harness, not a simulation. There is no action execution, no
completion effect, no need refill, no movement, no pathfinding, no schedule, no
activity duration, no NPC memory, no Munshausen behaviour and no Larochette
integration anywhere in it. A chosen activity in this day means only:

> at this point in the test day these were the caller-declared available
> activities, and the existing Step 4 scorer chose this one.

## 1. The fixed stand-in fixture

One committed fixture, declared once in `godot/day_probe.gd` and echoed into
the trace's `fixture` record:

| field | value |
|---|---|
| seed | `60628` (the Step 4 fixture's first seed) |
| initial needs | `[0.40, 0.35, 0.60, 0.50, 0.45, 0.42, 0.55]` |
| need order | `food, water, shelter, safety, sleep, companionship, joy` |
| skills | `[]` |
| settlement damage | `0.0` |
| settlement aggregate mood | `0.0` |
| checkpoints | `24`, numbered `0..23` |

The six activities, declared available at **every** checkpoint — there is no
availability schedule, because this harness does not invent one:

| order | id | name | place |
|---:|---:|---|---|
| 0 | 2 | Hunt | `north-hills` |
| 1 | 1 | Farm/Tend | `east-field` |
| 2 | 16 | Gather Socially | `market-square` |
| 3 | 14 | Sleep | `cottage-loft` |
| 4 | 12 | Lookout/Observe | `ridge` |
| 5 | 5 | Cook/Prepare | `kitchen` |

The seed, the needs and the activity set are exactly the ones Step 4 already
qualified, so the day starts from a result the engine has already verified.

## 2. The test-harness clock — 240 ticks/day is not a time authority

| quantity | value |
|---|---|
| decision checkpoints | `24`, numbered `0..23` |
| normalized time of day | `checkpoint / 24.0` |
| checkpoint ticks | `0, 10, 20, … 230` |
| advancement | one `RemichScorer.advance_time(needs, tick, tick + 10)` after every checkpoint |
| final tick after the complete day | `240` |

**`240` ticks per day is a convention of this test harness and of nothing
else.** It exists to make one compact, inspectable day: 24 familiar,
hour-like checkpoints with exactly one already-qualified donor decay boundary
between each pair. It is not a Remich, anvil, Munshausen, Eisleck or
Larochette time authority, it is not exposed on the engine-free scorer API as a
global truth, and no other module may read it as one. It appears only in
`godot/day_probe.gd` (as `CHECKPOINTS`, `TICKS_PER_CHECKPOINT`, `FINAL_TICK`)
and nowhere in `crates/`.

Because each advance crosses exactly one boundary, every decision record
carries `next_decay_steps: 1` — the count Rust returned, not a number GDScript
worked out. Twenty-four single steps make the final tick of `240`.

## 3. What runs, and in what order

`godot/day_probe.gd` is an autoload in `godot/project.godot`, registered
**after** Step 4's scorer probe and **before** Step 2's bridge probe:

```
Marker → ScorerProbe → DayProbe → BridgeProbe
```

`DayProbe` reads `REMICH_DAY_TRACE_PATH` in `_ready()`. When it is empty —
which is every Step 1-4 run — the script returns before doing anything and
prints nothing at all. When it holds a file path, the day is scheduled with
`call_deferred` rather than run inline.

The deferral is deliberate. Godot runs autoload `_ready` callbacks in list order
during startup and honours the **last** `quit()` it sees: a probe that calls
`quit(1)` and is followed by another that calls `quit(0)` ends the process with
exit code `0`. Running the day inline would therefore let a successful
`BridgeProbe` overwrite a failed day's failure. Running it deferred means
`BridgeProbe` has already taken the success path, so:

* success — the day prints `REMICH_DAY_OK` and does not touch the exit code,
  leaving `BridgeProbe`'s `quit(0)` in force;
* failure — the day prints `REMICH_DAY_FAIL` and calls `quit(1)`, which lands
  **after** `BridgeProbe` and therefore wins.

Both directions were measured against the pinned engine before being relied on
(the deferred call runs in the first message-queue flush, after every autoload
has had its turn, and its exit code is the one the process exits with).

At each checkpoint the loop does exactly what §4 of the brief requires:

1. use the current needs (the array the previous `advance_time` returned);
2. compute `time_of_day = checkpoint / 24.0`;
3. call `RemichScorer.score_activity`;
4. require `ok` — any refusal is a `REMICH_DAY_FAIL`;
5. record the returned chosen id/name/place/score, **all** six candidate scores
   in input order, and the `bridge_rev`;
6. call `RemichScorer.advance_time` to the next 10-tick boundary, and use
   *its* returned array for the next checkpoint.

GDScript never computes a score, a decay rate, a soul or a tie here; the only
arithmetic it does is `checkpoint / 24.0` and `tick + 10`, both clock
conventions this harness declares for itself.

After the last checkpoint the harness also asks Rust for one direct
`advance_time(INITIAL_NEEDS, 0, 240)` and compares it with the 24 sequential
advances. They must be identical or the day fails with `reason=state-drift`.
That is the day-loop drift check: it is done by Rust on both sides, and both
arrays are written into the trace.

## 4. The trace: activation, path and schema

| | |
|---|---|
| activation | environment variable `REMICH_DAY_TRACE_PATH`, read once in `_ready()` |
| inactive when | unset or empty — ordinary runs write nothing and print nothing |
| path | whatever the variable holds; the acceptance uses a fresh path under `/tmp` inside its own `mktemp -d` directory |
| format | JSON Lines: one JSON object per line, `LF`-terminated, keys emitted in sorted order |
| committed? | never — `day_trace*.jsonl` is in `.gitignore` and `tools/check_phase1_step5.sh` fails if one is tracked |

Records, in file order:

| record | count | fields |
|---|---:|---|
| `fixture` | 1 | `trace_format, seed, initial_needs, need_order, skills, settlement_damage, settlement_aggregate_mood, activities, available_at_every_checkpoint, checkpoints, ticks_per_checkpoint, time_of_day_formula, final_tick, clock_note` |
| `decision` | 24 | `checkpoint, tick, time_of_day, seed, needs[7], bridge_rev, chosen{ id, name, place, score }, candidates[6] { id, name, place, score }, next_decay_steps` |
| `summary` | 1 | `trace_format, bridge_rev, seed, checkpoints, final_tick, final_needs[7], direct_0_240_needs[7], sequential_equals_direct, first_chosen, last_chosen, distinct_chosen_ids, distinct_count, need_order, clock_note` |

Every decision record carries the seven needs *it scored with* and the six
scores it was given, so a reader can see why the choice did or did not move
between two checkpoints without re-running the engine: the needs, the clock,
and every candidate's score are all on the line. `next_decay_steps` says how
much decay the following advance applied, as Rust counted it.

`trace_format` is `remich-day-trace-v1` — this is a narrow internal test
artifact of this Remich harness, not a published cross-module format.

## 5. The observed day

Twenty-four checkpoints, four distinct activities, one real day-shaped
pattern. Nothing here was tuned to create variety; the donor scorer produced
it:

| cp | tick | time_of_day | chosen | score | margin over runner-up |
|---:|---:|---|---|---|---:|
| 0 | 0 | 0.0000 | `14 Sleep` @ `cottage-loft` | `0.0210661012679338` | 77.4 % |
| 1 | 10 | 0.0417 | `14 Sleep` @ `cottage-loft` | `0.0210685543715954` | 77.4 % |
| 2 | 20 | 0.0833 | `14 Sleep` @ `cottage-loft` | `0.0210710000246763` | 77.4 % |
| 3 | 30 | 0.1250 | `14 Sleep` @ `cottage-loft` | `0.0210734512656927` | 77.4 % |
| 4 | 40 | 0.1667 | `14 Sleep` @ `cottage-loft` | `0.0210759025067091` | 77.4 % |
| 5 | 50 | 0.2083 | `1 Farm/Tend` @ `east-field` | `0.0238259714096785` | 51.0 % |
| 6 | 60 | 0.2500 | `1 Farm/Tend` @ `east-field` | `0.023829622194171` | 51.0 % |
| 7 | 70 | 0.2917 | `1 Farm/Tend` @ `east-field` | `0.0238332767039537` | 51.0 % |
| 8 | 80 | 0.3333 | `1 Farm/Tend` @ `east-field` | `0.0238369293510914` | 51.0 % |
| 9 | 90 | 0.3750 | `5 Cook/Prepare` @ `kitchen` | `0.0238405801355839` | 80.0 % |
| 10 | 100 | 0.4167 | `5 Cook/Prepare` @ `kitchen` | `0.0238442309200764` | 80.0 % |
| 11 | 110 | 0.4583 | `5 Cook/Prepare` @ `kitchen` | `0.0238478798419237` | 80.0 % |
| 12 | 120 | 0.5000 | `5 Cook/Prepare` @ `kitchen` | `0.0238515343517065` | 80.0 % |
| 13 | 130 | 0.5417 | `5 Cook/Prepare` @ `kitchen` | `0.0238551832735538` | 80.0 % |
| 14 | 140 | 0.5833 | `5 Cook/Prepare` @ `kitchen` | `0.0238588359206915` | 80.0 % |
| 15 | 150 | 0.6250 | `5 Cook/Prepare` @ `kitchen` | `0.023862486705184` | 80.0 % |
| 16 | 160 | 0.6667 | `5 Cook/Prepare` @ `kitchen` | `0.0238661393523216` | 80.0 % |
| 17 | 170 | 0.7083 | `16 Gather Socially` @ `market-square` | `0.0138687212020159` | 65.6 % |
| 18 | 180 | 0.7500 | `16 Gather Socially` @ `market-square` | `0.0138700371608138` | 65.6 % |
| 19 | 190 | 0.7917 | `16 Gather Socially` @ `market-square` | `0.0138713512569666` | 65.6 % |
| 20 | 200 | 0.8333 | `16 Gather Socially` @ `market-square` | `0.0138726672157645` | 65.6 % |
| 21 | 210 | 0.8750 | `14 Sleep` @ `cottage-loft` | `0.0211175587028265` | 77.4 % |
| 22 | 220 | 0.9167 | `14 Sleep` @ `cottage-loft` | `0.0211200062185526` | 77.4 % |
| 23 | 230 | 0.9583 | `14 Sleep` @ `cottage-loft` | `0.021122457459569` | 77.4 % |

Summary, exactly as observed:

* **first choice**: `14 Sleep` @ `cottage-loft`, score `0.0210661012679338`
* **last choice**: `14 Sleep` @ `cottage-loft`, score `0.021122457459569`
* **distinct chosen ids**: `[1, 5, 14, 16]` — **4** of the 6 declared
  (counts: `14` × 8, `5` × 8, `1` × 4, `16` × 4; ids `2 Hunt` and `12
  Lookout/Observe` were never the top candidate). No particular number of
  distinct actions was required, and the fixture was not tuned to produce
  variety — this is simply what the donor scorer returned.
* **final needs** (tick `240`):
  `[0.397600322961807, 0.346400111913681, 0.598799824714661, 0.5, 0.448319852352142, 0.418560177087784, 0.54951936006546]`
* `sequential_equals_direct`: `true` — 24 single-boundary advances landed
  exactly where one direct `0 → 240` advance landed.
* `safety` is `0.5` at every checkpoint and at the end (its donor rate is
  `0.0`); no other need ever rose; the largest total drop over the whole day
  is `food`, `0.40 → 0.3976003`.

**Why the day changed.** The transitions happen at checkpoints 5, 9, 17 and
21. Over those same 24 checkpoints the needs move by at most 0.24 percentage
points, so the changes are not the needs talking — they are the donor's
time-of-day term crossing between adjacent checkpoints while the needs drift
downward monotonically underneath. That is the whole of the observation, and
it is deliberately **not** read as a design verdict on anvil's formulas: this
is evidence that the scorer can be called repeatedly, inside Godot, for a
complete deterministic test day.

## 6. Determinism of the day

The exact fixture was run twice under pinned Godot 4.7.2, to two separate
temporary paths:

```sh
bash tools/run_day.sh /tmp/run-1.jsonl
bash tools/run_day.sh /tmp/run-2.jsonl
```

Result: **byte-identical**. `cmp` reports no difference and both carry

```
6a5c78729a519163a16d2e754ed74d63ff0a3b9d0a957ef19b8543a89fe4ce2b
```

Same fixed fixture, same seed, same scorer, same trace bytes. This is not a
new sabotage test; it is the observable consequence of the determinism Step 4
already qualified, now visible across 24 consecutive calls and 24 consecutive
decays. `tools/check_day_trace.py` independently validates the file, and
`tools/check_phase1_step5.sh` performs the two-run comparison itself rather
than trusting this paragraph.

## 7. Godot proof and markers

All of it runs in the pinned engine
`/home/mrg/Documents/Project/Yolanda/.godot-local/engine/4.7.2/Godot_v4.7.2-stable_linux.x86_64`,
headless only — never editor, import or export mode.

| marker | meaning |
|---|---|
| `REMICH_DAY_OK checkpoints=24 final_tick=240 rev=… trace=… distinct=… first_id=… first_name=… last_id=… last_name=…` | a complete day was scored, written and verified |
| `REMICH_DAY_FAIL reason=… detail=…` | the day did not complete; the process then exits non-zero |

Observed on an ordinary run of the fixture:

```text
REMICH_DAY_OK checkpoints=24 final_tick=240 rev=remich-scorer-v1 trace=… distinct=4 first_id=14 first_name=Sleep last_id=14 last_name=Sleep
```

Failure paths were exercised too (an unwritable trace target produces
`REMICH_DAY_FAIL reason=trace-dir` and exit code `1`, despite `BridgeProbe`
having already asked for `0`), and the marker is checked in addition to — not
instead of — the exit code. No run is accepted on exit code alone.

Earlier probes still answer in the same process:

| marker | step |
|---|---|
| `REMICH_SCORER_OK …` and `REMICH_DECAY_OK …` | Step 4, scorer and decay |
| `REMICH_BRIDGE_OK value=remich-bridge-v1` | Step 2, the bridge |

## 8. Revision marker and the two timings

`SCORER_BRIDGE_REV = "remich-scorer-v1"` at line 38 of
`crates/remich_gdext/src/lib.rs` is Remich-owned metadata carried on every
result and on every trace record; `tools/stage_scorer.sh` parses it out of that
line into the (ignored) expectation file, so a stale library cannot agree with
itself.

Measured on this worktree, 2026-10-01, pinned toolchain, no build-config change:

| measurement | command | wall clock |
|---|---|---|
| Clean build | `cargo clean` then `cargo build --workspace` | **38.77 s** |
| One-line probe, rebuild through the complete day | `cargo build --workspace && bash tools/run_day.sh <trace-path>` | **0.73 s** |

Evidence for the clean build: 31 `Compiling` lines, including every dependency
(`godot-codegen`, `anvil_core`, `anvil_sim`, `remich_core`, `remich_gdext`), 0
warnings.

Evidence for the one-line probe: the timed command is the **whole** iteration
path, not merely Cargo — extension rebuild (1 crate recompiled,
`remich_gdext`), staging, pinned Godot 4.7.2 start, Step 4's
`REMICH_SCORER_OK` verification, the full 24-checkpoint day, the runtime
writing the trace, and `REMICH_DAY_OK` printed. The trace was then inspected:
it carried the incremented revision in `bridge_rev` on all 25 records that
carry one.

The change touched exactly one line — line 38, the `SCORER_BRIDGE_REV`
constant — incrementing its revision suffix by one (`-v1` → `-v2`). The
**verbatim diff and both marker lines are carried in the pull request body**,
not here: `tools/check_phase1_step4.sh` §15 asserts that the probed value
survives in exactly one tracked file (Step 4's own record), and this step does
not relax a merged step's guard in order to accommodate itself. Section 12
below records the trade-off.

Old revision observed in a day trace before the change:

```text
REMICH_DAY_OK checkpoints=24 final_tick=240 rev=remich-scorer-v1 … distinct=4 …
"bridge_rev":"remich-scorer-v1"
```

New revision observed in the timed day trace: the same marker and all 25
`bridge_rev` records carrying the incremented suffix. The probe trace's
`sha256` is
`6acabc78b52b8454a2135639f1888cb82d31a8853378bfaa4017e68b8ba281c1`
against `6a5c78729a519163a16d2e754ed74d63ff0a3b9d0a957ef19b8543a89fe4ce2b`
for the ordinary run — and masking that one string makes the two files
byte-identical, so the revision marker is the *only* thing the probe changed.

Then the source was restored **byte-for-byte** — `sha256`
`c6fa5fff7d78c0f82eed2bc981a16c362bc0f7568a590d5fe429ffa7d79622ff` before and
after, `cmp` clean — rebuilt, re-staged, and a further ordinary day reported
`rev=remich-scorer-v1` again with a trace byte-identical to the pre-probe one.
The probed value now appears in exactly one tracked file in this worktree:
`docs/remich-scorer-step4.md`, which was already there on `origin/main` and is
untouched by this step.

## 9. Trace validation

`tools/check_day_trace.py` validates a generated trace with an implementation
that shares no code with the Godot script that wrote it — the file is the only
thing the two have in common. It checks:

* the record kinds and their order, and that every line is valid JSON;
* exactly 24 decision records, checkpoints `0..23`, ticks `0,10,…,230`;
* `time_of_day` equals `checkpoint / 24.0`, increases strictly, and spans
  `0.0 → 23/24`;
* seven finite needs per decision, all in `[0.0, 1.0]`;
* `safety` never changes, and no non-safety need ever rises;
* six candidates per decision, ids in the declared input order
  `[2, 1, 16, 14, 12, 5]`, every score finite;
* the chosen id exists among that record's candidates and its name, place and
  score agree with that candidate;
* `next_decay_steps` is `1` at every checkpoint;
* every record reports the revision currently declared by
  `crates/remich_gdext/src/lib.rs`;
* the fixture record matches the committed stand-in, and checkpoint 0 starts
  from its initial needs;
* a final summary with `final_tick` `240`, `checkpoints` `24`, `sequential_equals_direct`
  `true`, both needs arrays present and equal, first/last chosen matching the
  trace, and `distinct_chosen_ids`/`distinct_count` matching what the trace
  actually shows.

It deliberately contains **no hand-written expected choice schedule** — the
Step 4 fixture already qualifies exact scoring; this qualifies the repeated
day loop and the trace. It reimplements no donor arithmetic either: the
sequential-versus-direct verdict is Rust's, recorded in the trace, and the
validator checks that verdict and that both arrays are present and agree.

The validator is also exercised against nine deliberately broken traces
(removed checkpoint, chosen id not among candidates, a risen need, a moved
safety, a wrong tick, a wrong final tick, reordered candidates, a non-finite
score, a truncated file). Each one is rejected with a specific `FAIL` line, so
the validator is not merely vacuous.

## 10. Reproducing

One command, from anywhere:

```sh
bash tools/check_phase1_step5.sh
```

It runs the Step 4 acceptance (which runs Step 3, Step 2 and Step 1) and then
the eighteen Step-5 sections listed in its header, including two independent
day runs, the trace validator, and the byte-identity comparison.

## 11. Firewall and scope

| file | changed by this step? |
|---|---|
| `crates/anvil_sim/**`, `crates/anvil_core/**`, `assets/**` | **no** — byte-identical to the Step 4 base |
| `crates/remich_core/**`, `crates/remich_gdext/**`, `Cargo.lock` | **no** — this step needed no Rust change at all |
| `godot/scorer_probe.gd`, `godot/bridge_probe.gd` | **no** |
| `docs/anvil-import-phase1-step3.md`, `docs/PLAN.md` | **no** |
| `godot/day_probe.gd`, `godot/project.godot`, `.gitignore`, `tools/run_day.sh`, `tools/check_day_trace.py`, `tools/check_phase1_step5.sh`, this record | **yes** |

The layering is unchanged: `Godot → remich_gdext → remich_core → anvil_sim →
anvil_core`, with `remich_core` engine-free and only `remich_gdext` holding
engine types. `godot/day_probe.gd` is GDScript that *calls* the extension; it
defines no scoring, decay, soul or seed logic of its own, and
`tools/check_phase1_step5.sh` fails if it ever starts to.

The donor vault remains clean at
`24181142c693be37f90a6a667a6dc493425cd832`. Munshausen, Larochette and
Eisleck are untouched. The Y-R connection remains the lead's work. The only
external path this repository names anywhere is the pinned engine binary above
and the read-only `buggy-vault` checkout used by Step 3's own checker.

No stop was needed: the Step 4 scorer already carried every input this trace
requires (seed, seven needs, time of day, activities with places, and the
neutral skill/damage/mood defaults), so nothing forced a donor, firewall or
format change.

## 12. Disclosure: why this record does not quote the probe value

The rebuild measurement of §8 increments `SCORER_BRIDGE_REV`'s suffix by one
and restores it. `tools/check_phase1_step4.sh` §15 asserts that the probed
value appears in **exactly one** tracked file — Step 4's record, which is
already on `origin/main`. Writing that value into this record (or into
`tools/check_phase1_step5.sh`) would turn Step 4's acceptance red.

Two ways out existed: relax a merged step's guard, or keep the verbatim string
out of this step's files. This step did the second, so the record describes the
change by suffix and the pull request body carries the exact `diff -u` and both
marker lines. In exchange, `tools/check_phase1_step5.sh` checks the stronger,
general rule: **no revision other than the committed one may appear anywhere
outside documentation or the acceptance scripts themselves** — and it derives
that rule without ever spelling the probed value out, so it holds for whatever
revision this lane measures next. `SCORER_BRIDGE_REV` must equal the committed
value, byte-for-byte, or the check fails.

Nothing is hidden: the probe value is one digit different from the committed
one, this section says which, and `git diff` on
`crates/remich_gdext/src/lib.rs` at the acceptance head is empty.
