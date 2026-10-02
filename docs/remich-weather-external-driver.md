# Remich — issue #19: the one weather channel, externally driven

Record of the lead-owned At Dusk integration seam ([#19](https://github.com/AgentAtelier/Remich/issues/19)):
Remich's single shared weather channel gains a **production mode** in which an
external driver decides the weather and publishes whole snapshots into that
same channel.

Base: `79e5d73b8d83bc09800c3a6b89dc36980e45ea26` (Remich `main` at handoff).

Reproduce everything with one command:

```bash
bash tools/check_external_weather.sh
```

This is **not** a new Remich lane or phase, and it does not reopen the closed
lane. It is one bounded change to the one weather seam, and it exists only to
unblock the stopped Eisleck Step-3 end-to-end acceptance.

## 1. The ownership decision this implements

| owns | who |
|---|---|
| the one shared runtime weather channel | **Remich** |
| the authoritative integer game clock | **Remich** |
| deciding what the weather *is* | **Eisleck** |
| reading the weather | everyone, through the same `WeatherSnapshot` |

There is still exactly one `WeatherChannel`, exactly one `RemichWeather` node
per project, and exactly one `WeatherSnapshot` every consumer reads. This
change adds a **second way to become that channel's writer**, not a second
channel.

The snapshot format and meaning are **unchanged**: `tick`, `wind_dir_x`,
`wind_dir_z`, `wind_strength`, `rain`, `temperature`, `light`. No field was
added — in particular no cloud field, no presentation phase, nothing.
Remich still does not decide weather, and nothing here reads a clock.

## 2. Two modes, one channel, one writer

`RemichWeather` had one entry point, `initialize(seed, cycle_length)`, which
created the channel and immediately claimed it for
`stand-in-weather-schedule`. That made the **test fixture** the owner of the
only live channel, and left production with no way in.

There are now two explicit, mutually exclusive entry points:

| | stand-in mode (fixture) | external mode (production) |
|---|---|---|
| entry point | `initialize(seed, cycle_length)` | `initialize_external()` |
| claims the channel for | `stand-in-weather-schedule` | `eislek-weather-driver` |
| creates a `StandInWeather` | yes (seed + cycle) | **no** |
| publishes with | `drive(tick)` — computes `seed + tick` | `publish_external_snapshot(tick, …)` — publishes what it is given |
| who decides the weather | the fixture schedule | the external driver |

The first initialization on an instance wins and the second is refused
(`already-initialized`), so **the two modes can never both hold the one
channel** — not even transiently. Which mode a node is in is read off whether
it has a stand-in driver at all: no second field, no second channel, no
second authority.

The stable production writer id is a constant owned by the core,
`remich_core::weather::EXTERNAL_DRIVER_ID`:

```rust
pub const EXTERNAL_DRIVER_ID: &str = "eislek-weather-driver";
```

It is a `const`, never a parameter. No gameplay caller can choose a production
writer identity, and the spelling is fixed in one place, asserted in the core
tests, in the binding tests, and from the engine.

## 3. The one production publish operation

```gdscript
Weather.publish_external_snapshot(tick, wind_dir_x, wind_dir_z,
                                  wind_strength, rain, temperature, light)
```

That is the whole production surface: *publish this one complete
externally-decided snapshot for this Remich tick.* It takes the seven
existing snapshot values and nothing else — no writer identity, no options
dictionary, no partial update. It:

1. parses the plain Godot inputs (rejecting a negative tick);
2. builds a real `WeatherSnapshot` through the existing
   `WeatherSnapshot::new`, so the existing finite/non-negative validation
   applies unchanged;
3. publishes it with `WeatherChannel::publish(EXTERNAL_DRIVER_ID, …)` — the
   same one-writer API the stand-in uses, not a way around it;
4. returns the repository's ordinary result dictionary (`ok`, `bridge_rev`,
   the seven fields; or `ok=false` with a `code` and the reason).

Deliberately **not** offered: `set_rain`, `set_wind`, `set_temperature`,
`set_light`, `set_snapshot`, `set_tick`, a bare `publish`, or any
writer-id argument. A caller cannot assemble half a weather behind the
production driver's back, and cannot become the production writer. The engine
probe asserts each of those names is absent from the class.

### Refusals

| situation | `code` |
|---|---|
| the node is not initialized | `not-initialized` |
| a second initialization, either mode | `already-initialized` |
| a stand-in-only call in external mode (`drive`, `restore_save_state`) | `no-stand-in-driver` |
| a non-finite value, or a negative strength | `invalid-snapshot` |
| a distinct second writer claiming or publishing | `writer-conflict` (names `held_by` and `attempted`) |
| a negative tick | `bad-input` |

`drive(tick)` in external mode is **structurally unavailable** rather than
silently generating stand-in weather: there is no stand-in schedule on that
node, and the refusal names the mode and points at the real operation. A
refused publish substitutes nothing — the last valid snapshot stands.

### Tick ownership is unchanged

Remich remains the tick authority. The publish stores the integer tick it was
handed, verbatim. The seam does not advance time, generate ticks, interpolate
between them, hold a counter, or decide that a transition happened. This is
asserted with a deliberately awkward tick sequence — `4096, 7, 0, 1, 999999,
240`, out of order and non-adjacent — so that a clock, an accumulator or an
interpolator could not produce it, and by a source scan of the seam for delta,
wall time, counter, RNG and second-clock idioms.

## 4. What the readers see

Unchanged, and reading the same one channel: `snapshot()`, `writer_id()`,
`writer_status()`, `apply_wind()`, `last_applied_wind()`.

`apply_wind()` — the one live write of the `grengewald_wind` shader global —
now works in both modes. It reads the one channel's latest snapshot, so a
snapshot published through the production seam is applied by the same call
with no second object in between. X/Y/Z of the applied vector are the
published snapshot's own values.

**One documented difference, in the renderer-facing W slot only.** The wind
global's W component is the *presentation phase*, `2π·(tick mod cycle)/cycle`
— explicitly not weather and not saved state. It needs a cycle, and a cycle is
*fixture* configuration (the stand-in's explicit `cycle_length`). The
production seam publishes a snapshot somebody else decided and declares no
cycle of its own, so it declares `EXTERNAL_PRESENTATION_CYCLE = 0` explicitly
rather than borrowing the fixture's, and W is a flat `0.0` there. A flat phase
is a renderer input, not a weather or clock decision, and it is asserted by
the probe rather than assumed. The stand-in's tick-derived phase is untouched.

In external mode `seed()` and `cycle_length()` report `-1` — "not available" —
because no stand-in exists, not `0`. The `seed` key in a snapshot dictionary
carries the same `-1` there. It was never a snapshot field.

## 5. Proving it

### Engine-free (Rust)

- the two identities alternate on **one** channel, and neither displaces the
  other (`the_two_identities_alternate_on_one_channel_and_never_both_hold_it`);
- an external publish stores the supplied snapshot and tick verbatim;
- invalid values are refused and the last valid snapshot survives;
- a distinct second writer is refused on the production channel, owner and
  snapshot intact;
- the production publish cannot bypass a stand-in that owns the channel;
- the stand-in still owns its channel and drives whole cycles;
- the pre-existing channel and stand-in regressions all still hold.

### Binding (Rust)

- the production seam uses the one core writer id, and never restates the
  literal;
- the publish is one whole-snapshot operation with no setter and no
  writer-id parameter;
- the seam's own source contains no clock;
- the external mode's presentation cycle is declared, and the stand-in's is
  unchanged.

### Real engine (pinned Godot 4.7.2)

`godot_external_weather/` is a second, deliberately tiny project beside the
fixture, because `godot/` initializes its shared node in **stand-in** mode and
must keep doing exactly that for its own acceptance. Nothing in `godot/` is
changed by this work.

`bash tools/run_external_weather.sh` stages the derived expectation from the
Rust source (so a stale library cannot pass) and runs the probe, which proves
through the real GDExtension: one native object on one channel; external
initialization claims it for `eislek-weather-driver` and creates no stand-in; a
second initialization is refused either way; `drive(tick)` is refused; one
complete decided snapshot publishes and reads back through `snapshot()` with
exactly the seven supplied values and the exact tick; `writer_status()` names
the production writer; `apply_wind()` derives the global from that snapshot;
invalid values are refused with the last valid one intact; a second writer is
refused with both identities named; and a production publish is refused against
a stand-in-mode node that already owns the channel, so the seam cannot take a
channel over from whoever holds it.

The probe supplies **plain test numbers** as if it were Eisleck. Remich has no
dependency on that driver and remains independently testable.

## 6. The committed stand-in acceptance is unchanged

`godot/weather.gd`, `godot/weather_probe.gd` and `godot/project.godot` are
byte-for-byte identical to the base, and `tools/check_phase2_step2.sh` is not
modified. The stand-in mode is still fixture behaviour, and its own acceptance
still proves it.

## 7. What this change does to the closed acceptance chain

`bash tools/check_phase3_step1.sh` (the top of the chain) is **already red on
`main` at the base SHA**, before this change: 3 failures from a stale
`PLAN_FREEZE` (the lane's closing record moved `docs/PLAN.md` after the chain
checkers froze it) and a dirty `Grengewald` worktree. At this head it is 4
failures. The one added failure is a **file-scope ratchet, not a behaviour
regression**:

```
FAIL  the files changed under crates/, assets/ and godot/ are:
      | crates/anvil_sim/src/actions/catalogue.rs
      | crates/remich_core/src/weather.rs
      | crates/remich_gdext/src/lib.rs
      | crates/remich_gdext/src/save.rs
```

That check asserts that *only* the Remich #9 catalogue file differs under
`crates/`, `assets/` and `godot/` since the phase-3 plan merge. It is a
per-step scope ratchet from a closed step, and this seam necessarily changes
`crates/`. Two ratchets in the Step 4 sub-check fail for the same reason
(`Rust source changed since the Step 3 merge beyond the Remich #9 catalogue
embedding`, and `files outside this step's benchmark-only scope changed`).

They are **not** amended here. Every weather-specific check in the chain still
behaves exactly as before: `tools/check_phase2_step2.sh` records the same
8 failures as the base SHA, byte for byte, and its stand-in weather run still
succeeds (`REMICH_WEATHER_OK seed=70021 ticks=240
writer=stand-in-weather-schedule calm=0.000000 windy=0.700000
rev=remich-weather-v1`). Per standing ruling 5 in the lane's closing record,
repairing a closed step's scope ratchet is its own maintenance step, tracked on
[#15](https://github.com/AgentAtelier/Remich/issues/15) — not part of a
capability change. This seam is reported to #19 with that boundary stated, not
silently accommodated.

## 8. Bite checks (sabotage, reverted)

Two deliberate weakenings were introduced, the acceptance was re-run against
each, and both were fully reverted afterwards (`git status` clean):

| sabotage | caught by |
|---|---|
| rename `EXTERNAL_DRIVER_ID` in the core | `the_production_writer_id_is_one_fixed_constant` (Rust) and the engine probe: `reason=wrong-writer … claimed 'saboteur-weather', expected 'eislek-weather-driver'`, exit 1 |
| remove the ownership check from `WeatherChannel::publish` | four core tests, two binding tests, and — after it was found missing — the engine probe: `reason=takeover-accepted`, exit 1 |

The second one is why the probe now carries the takeover case. The first
engine run of that sabotage still reported `REMICH_EXTERNAL_WEATHER_OK`: the
probe's second-writer check only exercised `claim_writer`, and a claim refusal
does not prove a *publish* refusal. The probe was extended to attempt a
production publish against a stand-in-owned node, and it now fails loudly when
the publish path stops enforcing ownership. The checker also greps the seam's
own body for a stray `claim_writer`, so a pre-claim cannot be slipped back in
as a bypass.

## 9. Not in this change

Weather generation, climate, scheduling, cloud policy, weather transitions,
random weather, player weather controls, per-field gameplay setters, a second
channel, another clock, a save-format change, a new Remich lane or phase, and
any dependency on Eisleck. Issue #19 is **not** closed by this: it is resolved
only once the merged seam has been used successfully for the stopped Eisleck
Step-3 end-to-end one-channel acceptance.

## 10. A note on the id's spelling

`eislek-weather-driver` is spelled exactly as issue #19 spells it (with `k`).
The repository and the external driver are `Eisleck` (with `c`). This seam
follows the issue's own spelling deliberately, so the issue, the source and the
acceptance all say one thing; renaming it is a one-line change in the core
plus the test assertions, if the lead prefers `eisleck`.
