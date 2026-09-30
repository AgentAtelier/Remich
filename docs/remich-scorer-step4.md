# The scorer, callable from Godot — Phase 1 Step 4 (record)

Step 4 of `docs/PLAN.md` §4: a Godot class that takes plain data — a seed, the
seven need-satisfactions, a time of day, and the activities available now with
the place each happens at — and returns the chosen activity together with every
candidate score. Needs decay when time advances. The choice is deterministic and
sensitive to the seed. Nothing is scored in GDScript and no donor formula is
re-implemented anywhere in this repository.

This record is the Step-4 counterpart of `docs/anvil-import-phase1-step3.md`.

## 1. Firewall and layering

```text
Godot  ->  remich_gdext  ->  remich_core  ->  anvil_sim  ->  anvil_core
```

| crate | role | engine dependency |
|---|---|---|
| `remich_gdext` | the only place engine types appear; converts `Dictionary`/`Array`/scalars both ways | `godot =0.5.5` (features `api-4-7`), pinned |
| `remich_core` | Remich's adapter: resolves donor action ids, calls the donor scorer, applies donor decay | none (engine-free, and dependent only on engine-free `anvil_sim`) |
| `anvil_sim` | the Step 3 donor import, unchanged by this step | none |
| `anvil_core` | the Step 3 donor import, unchanged by this step | none |

`remich_gdext` deliberately does **not** depend on `anvil_sim`. The Godot layer
speaks plain data only and resolves skill names through
`remich_core::scorer::skills_from_names`, so it never even *names* a donor type.
No other workspace member resolves an engine crate
(`cargo tree -p <member>`, path annotations stripped — see §11).

## 2. Donor APIs called (the adapter is a caller, never a copy)

| donor API | where it is called | why |
|---|---|---|
| `anvil_sim::utility::scoring::compute_utility_score` | `remich_core::scorer::score` | the score itself; the formula is *never* re-derived here |
| `anvil_sim::actions::catalogue::action_by_id` | `remich_core::scorer::validate` + `score` | resolves the caller's plain id to donor action metadata |
| `anvil_sim::soul::LayeredSoul::from_seed` | `remich_core::scorer::actor_soul` | the whole seed path |
| `anvil_sim::needs::Need::decay_rate` | `remich_core::decay::advance_needs` | one donor decay step |
| `anvil_sim::needs::Need::can_be_satisfied` | `remich_core::scorer::score` | the donor's "Joy is never chosen" rule |
| `anvil_sim::settlement::Skill` (`Display` spellings) | `remich_core::scorer::skill_from_name` | plain skill names in, donor values out |

Nothing under `crates/anvil_sim/**`, `crates/anvil_core/**` or
`assets/sim/actions.json` was edited by this step (§10).

## 3. Input contract

`RemichScorer.score_activity(input: Dictionary) -> Dictionary`

| key | type | required | meaning |
|---|---|---|---|
| `seed` | int ≥ 0 | yes | the only run-differentiating input; see §4 |
| `needs` | Array of 7 numbers, each in `[0.0, 1.0]` | yes | donor order: `food, water, shelter, safety, sleep, companionship, joy` |
| `time_of_day` | number in `[0.0, 1.0]` | yes | the donor's day cycle |
| `activities` | Array of `{ "id": int, "place": String }` | yes | available now; `id` must exist in the donor catalogue; `place` is Remich's own metadata |
| `skills` | Array of donor skill names | no (default `[]`) | `farmer`, `builder`, `musician`, `storyteller`, `healer` |
| `settlement_damage` | number in `[0.0, 1.0]` | no (default `0.0`) | neutral default, §5 |
| `settlement_aggregate_mood` | number in `[-1.0, 1.0]` | no (default `0.0`) | neutral default, §5 |

Each activity's `place` is **bridge metadata**: it is carried through to the
result and is never an argument to the donor scorer, so it cannot change a
score (there is a test that rewrites every place and asserts bit-identical
scores).

Availability is the caller's: the adapter does not re-filter, does not add, and
does not replace anything the caller listed.

## 4. Output contract

`score_activity` returns:

| key | type |
|---|---|
| `ok` | bool — `false` on any refusal |
| `bridge_rev` | String — the revision marker (§9) |
| `seed`, `time_of_day` | echoed back |
| `chosen_id`, `chosen_name`, `chosen_place`, `chosen_score` | the choice |
| `candidates` | Array of `{ "id", "name", "place", "score" }` in **input order**, including the choice |

On refusal `ok` is `false` and `code` + `error` say exactly which input was
rejected (`bad-input` for malformed plain data, `scorer-error` for a request
the adapter refuses). Nothing is substituted: an unknown action id is reported
as itself rather than silently scoring something else. The Godot probe asserts
this path explicitly with a deliberately unknown id `9999`.

`advance_time(needs: Array, from_tick: int, to_tick: int)` returns `ok`,
`bridge_rev`, the decayed `needs`, how many `decay_steps` were applied, and the
tick range echoed back.

## 5. Seed flow (donor-defined, never a tie-break)

```text
caller's seed  ->  LayeredSoul::from_seed(seed)
                     |- Substrate        {courage, generosity, stability}
                     `- EmotionalState
               ->  compute_utility_score(..., &emotional_state, &substrate, ...)
                     |- perception_filter(mood, need)
                     `- substrate_weight(substrate, action)
```

The seed reaches the donor's own deterministic actor state and nothing else.
It never enters a comparison, and there is no random tie-break: selection is
the donor's established rule — strict `score > best_score`, `best_score`
starting at `f32::MIN`, candidates visited in input order, so equal scores leave
the first one in front. No seed noise, no formula tuning.

## 6. Neutral defaults (documented, not inferred)

The donor formula accepts three inputs the step's minimum listing does not
supply. They are explicit fields with explicit neutral defaults, chosen because
inside them the donor's own modifiers return a *constant* across all
candidates — so no default can tilt the ranking:

| input | default | donor behaviour at that default |
|---|---|---|
| `skills` | `[]` | `skill_modifier` returns `1.0` for every action |
| `settlement_damage` | `0.0` | `coping_modifier` returns `0.5` for every action |
| `settlement_aggregate_mood` | `0.0` | `cooperation_modifier` returns `1.0` for every action |

They are visible as fields of `ScorerInput`, as documented optional keys on the
Godot dictionary, and as assertions in `remich_core`'s tests. They are
placeholders for explicit caller input, **not** final Munshausen behaviour.

## 7. The fixed fixture and its recorded result

One fixture, used unchanged by the Rust test and by `godot/scorer_probe.gd`:

* needs `[0.40, 0.35, 0.60, 0.50, 0.45, 0.42, 0.55]`
* time of day `0.27` (dawn window)
* available now: `2/north-hills`, `1/east-field`, `16/market-square`,
  `14/cottage-loft`, `12/ridge`, `5/kitchen`
* skills `[]`, damage `0.0`, mood `0.0`
* two committed seeds: **60628** and **87004**

| seed | chosen | place | chosen score | margin over runner-up |
|---|---|---|---|---|
| 60628 | `1 Farm/Tend` | `east-field` | `0.023807715624570847` | 51.0 % |
| 87004 | `2 Hunt` | `north-hills` | `0.056183211505413055` | 34.6 % |

Candidate scores as Godot receives them (f64 forms of the f32 the donor
returned), in input order:

| # | id | name | place | seed 60628 | seed 87004 |
|---|---|---|---|---|---|
| 0 | 2 | Hunt | north-hills | `0.011674161069095135` | `0.056183211505413055` |
| 1 | 1 | Farm/Tend | east-field | `0.023807715624570847` | `0.03676323592662811` |
| 2 | 16 | Gather Socially | market-square | `0.0027692753355950117` | `0.0043218438513576984` |
| 3 | 14 | Sleep | cottage-loft | `0.004213220439851284` | `0.006532006897032261` |
| 4 | 12 | Lookout/Observe | ridge | `0.0` | `0.0` |
| 5 | 5 | Cook/Prepare | kitchen | `0.004761543124914169` | `0.0073526473715901375` |

Supplied with `skills: ["farmer"]`, seed 60628 still chooses `1 Farm/Tend` and
its score becomes `0.028569258749485016` — the plain skill name crossed the
boundary and reached the donor's `skill_modifier`.

`Lookout/Observe` scores `0.0` because `Safety`'s donor decay rate is `0.0`,
which makes the donor's `base_urgency` for Safety identically zero. That is the
donor's own arithmetic, left exactly as it is.

**Determinism tests** (`crates/remich_core/tests/seed_sensitive_fixture.rs`):

* same input + same seed → identical chosen id, bit-identical chosen score,
  bit-identical candidate scores in the same order;
* both seeds reproduce their recorded results above, bit for bit;
* **the two seeds choose differently** — the assertion that fails if the
  implementation ever ignores the supplied seed and substitutes a constant;
* the two seeds produce different donor souls (`Substrate`, `EmotionalState`)
  and rebuilding from one seed rebuilds it exactly.

The inputs and the two seeds are literals. The committed test performs no
search; seed discovery was done with a throw-away example that was deleted
before the commit.

## 8. Need decay

**Donor reference for this behaviour only:**
`buggy-vault@24181142 repos/anvil/source/crates/anvil_sim/src/system/npc/kimi_npc_mod.rs`
(`decay_needs`, `all_needs`, `need_index`). The donor `NpcSystem` itself was
**not** taken — `remich_core::decay` reproduces only the semantics above.

* one decay step per tick whose number is divisible by 10; other ticks skip;
* one step subtracts `Need::decay_rate()` for that need and clamps the result
  to a minimum of `0.0`;
* the donor's Safety decay rate is `0.0`, so Safety never moves;
* steps are applied in the donor's need order.

`advance_needs(needs, from_tick, to_tick)` counts the multiples of 10 crossed in
`(from_tick, to_tick]` — `to_tick/10 - from_tick/10` — because `from_tick`
already describes state that has been reached. A backwards range is an error,
never a silent no-op.

Tests cover: no boundary crossed (`5 -> 9`, nothing moves), exactly one
boundary (`5 -> 10`), several boundaries (`5 -> 35` → three steps), a long
advance (`0 -> 10000` → 1000 steps) where every value is clamped at `0.0` and
never negative, Safety never moving, and malformed need values rejected before
any decay.

## 9. Godot proof under the pinned 4.7.2

The binary is the pinned, qualified one and is only ever invoked qualified and
headless, never in editor/import/export mode:

```text
/home/mrg/Documents/Project/Yolanda/.godot-local/engine/4.7.2/Godot_v4.7.2-stable_linux.x86_64 --headless --path godot --quit-after 10
```

`godot/scorer_probe.gd` (a new autoload, after `Marker`, before `BridgeProbe`)
instantiates `RemichScorer` through real `ClassDB` and asserts, with plain
data, the whole of §7: the recorded candidate list, both seeds' choices, the
skill path, and the refusal path. It then checks decay (§8). Machine markers:

```text
REMICH_SCORER_OK rev=remich-scorer-v1 seed_a=60628 chosen_a=1 chosen_a_place=east-field chosen_b=2 chosen_b_place=north-hills candidates=6
REMICH_DECAY_OK steps_none=0 steps_one=1 steps_many=3 safety_unchanged=true floor=0.0
REMICH_BRIDGE_OK value=remich-bridge-v1
REMICH_TEST_PROJECT_OPENED
```

Exit code `0` alone is never accepted: the acceptance greps for these markers.
The deliberate unknown-id probe is expected to emit exactly one `ERROR:` line
(`action id 9999 is not in the donor action catalogue`) and no script error.

The Step-2 probe is untouched and stays green; the scorer probe is added beside
it. When `godot/scorer_probe_expectation.txt` is absent (Steps 1–3), the scorer
probe returns silently and `BridgeProbe` quits the run exactly as before.

## 10. Revision marker and the two timings

`SCORER_BRIDGE_REV = "remich-scorer-v1"` in `crates/remich_gdext/src/lib.rs`
is Remich-owned metadata carried on every result;
`tools/stage_scorer.sh` parses it out of that line into the (ignored) expectation
file, so a stale library cannot agree with itself.

Measured on this worktree, 2026-09-30, pinned toolchain, no build-config change:

| measurement | command | wall clock |
|---|---|---|
| Clean build | `cargo clean` then `cargo build --workspace` | **42.70 s** |
| One-line probe, rebuild through Godot | `cargo build --workspace && bash tools/stage_scorer.sh && <pinned Godot> --headless --path godot --quit-after 10` | **0.80 s** |

Evidence for the clean build: 31 `Compiling` lines including every dependency
(`godot-codegen`, `anvil_core`, `anvil_sim`, `remich_core`, `remich_gdext`),
0 warnings.

The one-line change, exact diff (`diff -u` of the file immediately before and
after the edit; one changed line):

```diff
-pub const SCORER_BRIDGE_REV: &str = "remich-scorer-v1";
+pub const SCORER_BRIDGE_REV: &str = "remich-scorer-v2";
```

Old marker observed in Godot before the change:

```text
REMICH_SCORER_OK rev=remich-scorer-v1 ...
```

New marker observed in Godot through the same timed path (1 crate recompiled):

```text
REMICH_SCORER_OK rev=remich-scorer-v2 ...
```

Then the source was restored **byte-for-byte** — `sha256`
`c6fa5fff7d78c0f82eed2bc981a16c362bc0f7568a590d5fe429ffa7d79622ff` before and
after — rebuilt, re-staged, and Godot observed `rev=remich-scorer-v1` again.
The sentinel `remich-scorer-v2` now appears in exactly one tracked file: this
record. `tools/check_phase1_step4.sh` enforces both facts.

## 11. One disclosure: a false positive fixed in the earlier acceptance scripts

The Step 1/2/3 firewalls grep `cargo tree` output for `godot|gdext`. Cargo
annotates every workspace package with its **absolute checkout path**, and this
worktree's mandated path contains the word `godot`
(`.../worktrees/remich-p1s4-scorer-godot-20260930/crates/...`). The check
therefore reported a broken firewall while `cargo tree` in fact showed no engine
crate at all.

Fix: at the four `cargo tree` call sites that *search for engine terms*, the
source-path annotation is stripped before grepping —

```sh
sed -E 's/ \((path[+]file:)?\/[^)]*\)//g'
```

The check is about crate identity, so only ` (/home/...)`-shaped annotations are
removed; `(*)` and `(proc-macro)` survive, and a real engine package line
(`├── godot v0.5.5`) carries no path annotation and is still caught — verified
in both directions while making the change. No check's *meaning* was relaxed,
and the positive assertions (`godot v0.5.5` in `remich_gdext`,
`anvil_core v0.1.0` in `anvil_sim`) are untouched.

Files changed: `tools/check_phase1_step1.sh` (2 sites),
`tools/check_phase1_step2.sh` (1), `tools/check_phase1_step3.sh` (1).

## 12. Reproducing

One command, from anywhere:

```sh
bash tools/check_phase1_step4.sh
```

It runs the Step 3 acceptance (which runs Step 2 and Step 1) and then checks the
Step-4 requirements listed in its header.

## 13. Scope confirmation

* Donor files and data from Step 3 are unchanged; the vault is still clean at
  `24181142c693be37f90a6a667a6dc493425cd832`.
* No Munshausen or Larochette fact is required: no behaviour, path, crate or
  value from those repositories is read or written here. The only external
  paths referenced anywhere are the pinned Godot binary above and the read-only
  `buggy-vault` checkout used by Step 3's own checker.
* No other repository was modified.
