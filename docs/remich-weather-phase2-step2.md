# Remich — Phase 2, Step 2: one weather snapshot

Record of the second Phase 2 step (docs/PLAN.md §4a, step 2): a Rust-held
weather snapshot written by exactly one driver and read by everything else,
driven by Phase 2 Step 1's single clock, exposed through one shared Godot
node, and written to the wind shader global Grengewald's trees already read.

Reproduce everything with one command:

```bash
bash tools/check_phase2_step2.sh
```

## 1. The pinned external authority (standing ruling 1)

This step's only external module fact is read-only:

- repository: `AgentAtelier/Grengewald`
- commit: `AgentAtelier/Grengewald@95fa08e45c919e93d62d3940f2dea032f1b724e3`
- file: `docs/GODOT.md`

Verified with read-only `git show` against the local checkout; Grengewald was
never checked out, branched, edited or run, and its worktree stayed clean.
No Grengewald code was copied. The contract taken from that document:

- shader global name: `grengewald_wind`
- type: `vec4`, default `Vector4(1,0,0,0)`
- X/Y = world X/Z wind direction; Z = gentle displacement strength in
  metres; W = game-supplied motion phase in radians
- the runtime setter Grengewald itself uses:
  `RenderingServer.global_shader_parameter_set`
- runtime global getters are editor-only in the compatibility backend, so
  the binding never calls one (see §7)
- Grengewald itself has no independent clock or weather driver

Nothing about that contract had to change for this step, and no stop was
needed.

## 2. The snapshot contract (test-fixture semantics, not Eisleck policy)

`crates/remich_core/src/weather.rs` holds `WeatherSnapshot` — plain data, no
Godot types, no behaviour beyond validation:

| field | type | fixture convention |
|---|---|---|
| `tick` | `u64` | the integer simulation tick this snapshot applies to |
| `wind_dir_x`, `wind_dir_z` | `f64` | a finite unit vector's X/Z components |
| `wind_strength` | `f64` | finite, non-negative; fixture range 0..1 (Grengewald's gentle displacement-metres range) |
| `rain` | `f64` | finite scalar; fixture range 0..1 |
| `temperature` | `f64` | finite scalar (fixture degrees, meaning reserved) |
| `light` | `f64` | finite scalar in 0..1 |

Every numeric field must be finite and strength non-negative; the rules are
enforced by `WeatherSnapshot::validate`, called again by the channel on
publish, so a struct literal cannot smuggle invalid data in.

**This is not Eisleck's final weather model, units or policy.** The numbers
above are Remich test-fixture conventions chosen so the channel is
demonstrably live; Eisleck owns what actual weather means (docs/PLAN.md
§1.1). No clouds, pressure, fog, wetness, seasons or catastrophes exist —
wind, rain, temperature, light and a tick, nothing else.

## 3. One writer: the ownership model

`WeatherChannel` starts with **no writer**. The API is the rule, not a
comment:

- `claim_writer(id)` — the first claim wins. Re-claiming as the *same* id is
  an idempotent no-op (never a replacement). A **second distinct identity is
  refused** with `WeatherError::WriterConflict`, whose `Display` names both
  `held_by` and `attempted`.
- `publish(id, snapshot)` — refused (nothing changed) when there is no
  writer yet, when `id` is not the owner (`WriterConflict` again), or when
  the snapshot is invalid.
- `read()` — anybody may read the latest snapshot; reading never claims and
  never writes.
- There is no global mutable static and no unrestricted setter: the channel
  itself is the gate.

Refusal is tested directly (an allowed anti-silent-mistake check), both in
Rust and from the engine:

- Rust (`weather::tests`): `a_second_distinct_writer_claim_is_refused_with_the_conflict_named`
  and `a_second_writer_publish_is_refused_and_the_snapshot_is_unchanged` — a
  second writer attempts claim *and* publish against a live snapshot; both
  are refused, the first writer stays authoritative, and the last valid
  snapshot compares equal byte-for-byte afterwards.
- Engine (`godot/weather_probe.gd`): after driving the cycle, the probe
  attempts `try_claim_writer("intruder-weather-driver")` through the binding
  — the same channel API, so it cannot bypass the rule — and requires
  `code=writer-conflict` naming both writers, an unchanged owner, and an
  unchanged snapshot/status. The engine log carries the refusal verbatim:
  `RemichWeather: writer-conflict: the weather channel is owned by
  'stand-in-weather-schedule'; writer 'intruder-weather-driver' was refused
  (one writer only, the first claim stands)`.

The binding exposes no weather mutation at all (`set_wind`, `set_rain`,
`publish`, … are asserted absent); the only publish path is
`drive(tick)`, which computes `seed + tick` in Rust.

## 4. The stand-in driver (replaceable fixture, not Eisleck)

`StandInWeather` is deliberately small:

- **state:** `u64 seed`, `u64 cycle_length` — two integers, proved by
  `type_name_of_val` and `size_of`, with the struct source checked for any
  hidden field. No accumulator, no counter, no RNG, no wall clock.
- **schedule:** within the caller's explicit cycle (the test fixture's
  `240`-tick day), the first half is a **calm morning**
  (strength `0.0`, rain `0.0`, temperature `12.0`, light `0.35`) and the
  second half a **windy afternoon** (strength `0.7`, rain `0.1`,
  temperature `19.0`, light `0.85`). Wind is the value that visibly changes;
  the rest are simple observable placeholders. Half-cycle arithmetic is
  integer (`phase >= cycle - cycle/2`).
- **seed participation:** `seed % 4` selects one of four fixed **unit**
  wind directions `(1,0) (0,1) (-1,0) (0,-1)` — a small stable mapping, so
  the seed demonstrably shapes the result instead of being accepted and
  ignored. `the_seed_participates_in_the_stand_in_direction` asserts four
  seeds give four distinct directions; no random search exists anywhere.
- **determinism:** `snapshot(tick)` is a pure function of `(&self, tick)`;
  `the_stand_in_is_deterministic_from_seed_and_tick` interleaves two
  independent drivers over a full cycle and requires bit-identical results.

The 240-tick cycle is test-project configuration (as in Step 1), never
game-wide authority. The driver never advances time: the tick is always
handed in.

## 5. One shared node, driven by the one clock

- `RemichWeather` (GDExtension class) owns the Rust channel; `Weather`
  (autoload `godot/weather.gd`) holds exactly one instance and only
  delegates — no wind/rain/temperature/light/tick state of its own. The
  probe counts native weather objects in the scene tree and requires exactly
  `1`, and requires `ClassDB.instantiate(WEATHER_CLASS)` to appear in
  exactly one script.
- `project.godot` declares exactly one clock autoload (`WorldClock`) and no
  second one; `godot/weather_probe.gd` obtains its ticks exclusively from
  `WorldClock.pulse()` after `WorldClock.reset(0)`, and holds no tick
  counter or elapsed-seconds accumulator (asserted by the checker).
- The loop is exactly the step's contract: obtain the integer tick from the
  shared clock → `Weather.drive(tick)` publishes → `Weather.snapshot()`
  reads it back → snapshot `tick` must equal that clock tick →
  `Weather.apply_wind()` writes the global → the recorded applied vector is
  compared to the snapshot. The trace records both `tick` (from the clock)
  and `snapshot_tick` (read back), and they are equal on every one of the
  240 records (`tools/check_weather_trace.py`).

## 6. The mapping to `grengewald_wind`

Declared in `godot/project.godot`, exactly per the pinned document:

```ini
[shader_globals]

grengewald_wind={
"type": "vec4",
"value": Vector4(1, 0, 0, 0)
}
```

Written from the **binding** (`crates/remich_gdext/src/lib.rs`), never from
`remich_core`, through the engine's real runtime setter —
`RenderingServer::singleton().global_shader_parameter_set(WIND_GLOBAL_NAME, …)`
— the same setter Grengewald documents:

| global | source |
|---|---|
| X | snapshot `wind_dir_x` |
| Y | snapshot `wind_dir_z` (world Z) |
| Z | snapshot `wind_strength`, clamped to 0..1 = Grengewald's gentle displacement metres (identity within the fixture range; the clamp is the whole "conversion") |
| W | **presentation phase**, see below |

Godot's `vec4` is 32-bit while the snapshot is `f64`: the binding converts
once at this edge and records **the rounded components it actually passed**
(`last_applied_wind()`). The probe and the trace validator compare those
against the snapshot with a 1e-6 tolerance; equality would otherwise be a
lie about the boundary.

### W is presentation, not weather

W is the motion phase in radians: `2π · (tick mod cycle) / cycle`, a pure
function of the shared clock's integer tick and the fixture cycle
(`presentation_phase`). **W is presentation, not weather, and not saved
state**: the snapshot deliberately carries no phase field
(`the_snapshot_carries_no_presentation_phase`), and the checker requires
this sentence's substance here. It exists because Grengewald's contract has
a game-supplied phase slot; deriving it from the one clock keeps it
deterministic without pretending it is authoritative weather.

### No fake global getter

Per the pinned contract, runtime global getters are editor-only in the
compatibility backend; none is called, real or invented (the checker greps
the binding for `global_shader_parameter_get`, and a test does too). The
live write path is established instead by: (1) the declared name/type/
default in `project.godot`, verified at runtime from ProjectSettings by the
probe (it hard-fails on `global-undeclared`/`global-type`/`global-default`);
(2) the binding's call to the real `RenderingServer` setter; (3) the vector
recorded at that call; (4) the per-tick equality of that vector's weather
components with the read-back snapshot.

### The stand-in tree consumer

`godot/standin_wind.gdshader` is a few lines declaring
`global uniform vec4 grengewald_wind` and leaning on it — the same global
name Grengewald's trees read, proving Remich writes the game-owned value,
not a private one. It is **not** Grengewald rendering: nothing renders it,
and acceptance validates it statically alongside the real setter path.

## 7. The deterministic weather trace

`tools/run_weather.sh <trace>` stages the expectations and runs the probe in
pinned Godot 4.7.2 (`--headless`, never editor/import/export). One fixed
seed (`TEST_SEED = 70021`, declared once in `godot/weather.gd`), one full
`240`-tick cycle, one JSON record per tick carrying: `tick`,
`snapshot_tick`, `seed`, `wind_dir_x/z`, `wind_strength`, `rain`,
`temperature`, `light`, `wind_global` (applied X/Y/Z/W) and
`weather_bridge_rev`.

Two runs with the same seed produce byte-identical traces:

| run | SHA-256 |
|---|---|
| run 1 | `3686ae5d1abe7843d0a503a78b92ed2465381b359b4580369457648b86cd28b6` |
| run 2 | `3686ae5d1abe7843d0a503a78b92ed2465381b359b4580369457648b86cd28b6` |

Shape assertions (ranges, no float table): morning strength `<= 0.1`,
afternoon strength `>= 0.5`, unit direction constant all day, every record's
`snapshot_tick == tick` in `0..239`.

The marker:

```
REMICH_WEATHER_OK seed=70021 ticks=240 writer=stand-in-weather-schedule calm=0.000000 windy=0.700000 rev=remich-weather-v1
```

(`calm` = the morning's maximum observed strength, `windy` = the
afternoon's minimum). Failure prints `REMICH_WEATHER_FAIL reason=… detail=…`
and exits non-zero; `WeatherProbe` is the **last** autoload, so no earlier
probe's `quit(0)` can mask it.

## 8. Measured commit, build and rebuild timings

All executable work (channel, tests, binding, nodes, shader, probes,
staging, scripts, acceptance) was committed first; only documentation
changed afterwards.

**Measured commit:** `2942719e6e35dd1027fba35b9e501d38f78884a3`

| Measurement | Command | Result |
|---|---|---|
| Clean build | `cargo clean` (removed 1.5 GiB / 2692 files) then `cargo build --workspace` from the measured commit | **54.10 s**, 31 crates compiled, **0 warnings**, exit 0 |
| One-line rebuild through Godot | change exactly `WEATHER_BRIDGE_REV` from `remich-weather-v1` to `remich-weather-v2`, then rebuild and run the weather proof | incremental rebuild **0.81 s** + engine run **0.41 s** = **1.22 s** until Godot observed v2, 0 warnings, exit 0 |

The one-line diff, for the record:

```diff
-pub const WEATHER_BRIDGE_REV: &str = "remich-weather-v1";
+pub const WEATHER_BRIDGE_REV: &str = "remich-weather-v2";
```

The engine observed `rev=remich-weather-v2` in that run (expectation staged
from the source, so a stale library would fail — a marker reading anything
else would have failed the run), then the line was restored byte-for-byte
(`git diff` empty against the measured commit, line 65 back to
`remich-weather-v1`), rebuilt, and re-proved at `remich-weather-v1` with a
weather trace whose SHA-256 is again
`3686ae5d1abe7843d0a503a78b92ed2465381b359b4580369457648b86cd28b6` — the
same bytes the deterministic runs produce. The sentinel `remich-weather-v2`
survives only in this record and in the checker that names it (the checker
constructs it at runtime so it never trips its own scan).

**Final head:** this record's own commit follows the measured commit and
contains documentation only — the exact final SHA is carried by the PR (a
file cannot contain the SHA of the commit that contains it).

## 9. Acceptance

`bash tools/check_phase2_step2.sh` — 26 checks, including Step 1's
`tools/check_phase2_step1.sh` run unchanged as a sub-check. Result:
**100 ok / 0 fail** (run at the measured commit; the final head differs only
by this record, and the same run is repeated once on the final head before
hand-back — its result is reported in the PR).

Step 1's clock remains: integer-authoritative, one shared node,
speed/pause-capable, float-sabotage-free; `REMICH_CLOCK_OK`,
`REMICH_SCORER_OK`, `REMICH_DECAY_OK` and `REMICH_BRIDGE_OK` appear in this
step's runs as well (staging carries them).

## 10. Refusals and stops

- **Stops:** none. No Grengewald change, no plan conflict, no final-Eisleck
  semantic decision, no cross-module schema change, no second clock, no
  firewall break, no other repository touched, no earlier capability
  regressed.
- **Refusals exercised:** the second writer (§3), refused both in Rust and
  from the engine, leaving the snapshot intact.
- **Deliberately refused by design:** any Godot-side weather mutation
  (asserted absent), any float time input to the driver, any use of the
  editor-only global getter, and any extra weather concept beyond wind,
  rain, temperature, light and tick.
