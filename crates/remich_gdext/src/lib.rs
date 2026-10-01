//! The thin binding layer of Remich.
//!
//! This crate is the boundary and nothing else (docs/PLAN.md §1.2). It sits on
//! top of `remich_core`, and it is the one place engine types are allowed to
//! appear. The engine-free core stays free of them.
//!
//! Step 2 turned the Step 1 skeleton into a real, loadable GDExtension: the
//! smallest genuine bridge that proves the engine can load this library, call
//! into Rust, and observe a value come back. Step 4 adds the second, real
//! path — `RemichScorer`, which is conversion and exposure only. The scoring
//! itself lives in `remich_core`, which calls the Step 3 donor scorer; nothing
//! here computes a score, re-implements a donor formula, or decides anything.
//! The simulated day itself is Step 5 (docs/PLAN.md).

use godot::classes::RenderingServer;
use godot::prelude::*;

use remich_core::clock::WorldClock;
use remich_core::decay::advance_needs;
use remich_core::scorer::{self, ScorerInput, ScorerOutcome};
use remich_core::soul::{
    connection_layer_from_name, connection_layer_name, AxesSnapshot, SoulFacade,
    SubstrateSnapshot,
};
use remich_core::weather::{
    StandInWeather, WeatherChannel, WeatherError, WeatherSnapshot, STAND_IN_DRIVER_ID,
};

// The game's save surface (Phase 2, Step 3): file access and plain-value
// conversion live there; the engine-free document itself lives in
// `remich_core::save`.
mod save;
pub use save::RemichGameSave;

/// The single value Remich's bridge probe hands to Godot.
///
/// This is a probe, not game behaviour: it exists only so the engine has
/// something observable to receive across the boundary. Its string form is
/// what the step's rebuild measurement changes, and
/// `godot/bridge_probe.gd` verifies it against this declaration (see
/// `tools/stage_bridge.sh`, which derives the expectation from this line).
pub const BRIDGE_PROBE_VALUE: &str = "remich-bridge-v1";

/// The revision marker carried on every `RemichScorer` result.
///
/// Pure metadata: it says which revision of the Remich-owned scorer bridge
/// produced a result, and it deliberately says nothing about donor behaviour.
/// `godot/scorer_probe.gd` checks the returned marker against
/// `godot/scorer_probe_expectation.txt`, which `tools/stage_scorer.sh` derives
/// from this line — so a stale library cannot masquerade as a fresh build.
/// Step 4's rebuild measurement changes exactly this line to `v2` and then
/// restores it; `tools/check_phase1_step4.sh` fails if it is left changed.
pub const SCORER_BRIDGE_REV: &str = "remich-scorer-v1";

/// The revision marker carried by the shared world clock node.
///
/// The same stale-library guard as the two markers above, for the clock:
/// `godot/clock_probe.gd` checks the value Godot observes against
/// `godot/clock_probe_expectation.txt`, which `tools/stage_clock.sh` derives
/// from this line. Phase 2 Step 1's rebuild measurement changes exactly this
/// line to `v2`, times the rebuild-through-engine path, and restores it;
/// `tools/check_phase2_step1.sh` fails if any value other than the committed
/// one survives outside documentation.
pub const CLOCK_BRIDGE_REV: &str = "remich-clock-v1";

/// The revision marker carried by the shared weather node.
///
/// The same stale-library guard as the three markers above, for the weather
/// channel: `godot/weather_probe.gd` checks the value Godot observes against
/// `godot/weather_probe_expectation.txt`, which `tools/stage_weather.sh`
/// derives from this line. Phase 2 Step 2's rebuild measurement changes
/// exactly this line to `v2`, times the rebuild-through-engine path, and
/// restores it; `tools/check_phase2_step2.sh` fails if any value other than
/// the committed one survives outside documentation.
pub const WEATHER_BRIDGE_REV: &str = "remich-weather-v1";

/// The revision marker carried by the game's save surface.
///
/// The same stale-library guard as the four markers above, for the save
/// (Phase 2, Step 3): `godot/save_probe.gd` checks the value Godot observes
/// against `godot/save_probe_expectation.txt`, which `tools/stage_save.sh`
/// derives from this line — so a stale library cannot pass. The step's
/// rebuild measurement changes exactly this line to `v2`, times the
/// rebuild-through-engine path, and restores it;
/// `tools/check_phase2_step3.sh` fails if any value other than the committed
/// one survives outside documentation. It is implementation evidence only:
/// the save document carries its own `format_version`, and this marker is
/// never serialized into game state.
pub const SAVE_BRIDGE_REV: &str = "remich-save-v1";

/// The revision marker carried by the soul surface (Phase 3, Step 2).
///
/// The same stale-library guard as the five markers above: `godot/soul_probe.gd`
/// checks the value Godot observes against `godot/soul_probe_expectation.txt`,
/// which `tools/stage_soul.sh` derives from this line — so a stale library
/// cannot pass. Phase 3 Step 2's rebuild measurement changes exactly this
/// line to `v2`, times the rebuild-through-engine path, and restores it;
/// `tools/check_phase3_step2.sh` fails if any value other than the committed
/// one survives outside documentation. It says nothing about donor behaviour:
/// the propagated influence it labels is the donor's, unchanged.
pub const SOUL_BRIDGE_REV: &str = "remich-soul-v1";

/// The one shader global this binding writes.
///
/// The name, type and default come from Grengewald's pinned contract
/// (`AgentAtelier/Grengewald@95fa08e45c919e93d62d3940f2dea032f1b724e3`,
/// `docs/GODOT.md`, standing ruling 1 — recorded in
/// `docs/remich-weather-phase2-step2.md`): a `vec4` named `grengewald_wind`
/// whose X/Y are world X/Z direction, Z is gentle displacement in metres, and
/// W is the game-supplied motion phase. The declaration itself lives in
/// `godot/project.godot`; the live write goes through Godot's real runtime
/// setter, exactly as Grengewald documents for its own use.
pub const WIND_GLOBAL_NAME: &str = "grengewald_wind";

/// The layer's own name, mirrored from the engine-free side of the boundary.
pub const LAYER_NAME: &str = "remich_gdext";

/// What this layer passes across the boundary to the core: the core's identity,
/// forwarded unchanged.
pub fn forward_core_name() -> &'static str {
    remich_core::CORE_NAME
}

/// The Godot-facing class behind the probe.
///
/// Deliberately a bare `Node` with one trivial method — no nodes of our own
/// design, no behaviour, no simulation. It exists so `ClassDB` has something
/// Godot can instantiate and call.
#[derive(GodotClass)]
#[class(base = Node)]
pub struct RemichBridge {
    base: Base<Node>,
}

#[godot_api]
impl INode for RemichBridge {
    fn init(base: Base<Node>) -> Self {
        Self { base }
    }
}

#[godot_api]
impl RemichBridge {
    /// One deliberately trivial callable. It crosses the Rust/Godot boundary in
    /// both directions: Godot calls it, Rust returns one observable value.
    #[func]
    fn bridge_probe(&self) -> GString {
        BRIDGE_PROBE_VALUE.into()
    }
}

/// The Godot-facing scorer (docs/PLAN.md, phase 1, step 4).
///
/// A node only so `ClassDB` can instantiate it and a scene can hold it. Every
/// argument and every result is a plain value, an `Array` or a `Dictionary` —
/// no Munshausen object, no Larochette node, no resource handle, no type from
/// any other repository.
#[derive(GodotClass)]
#[class(base = Node)]
pub struct RemichScorer {
    base: Base<Node>,
}

#[godot_api]
impl INode for RemichScorer {
    fn init(base: Base<Node>) -> Self {
        Self { base }
    }
}

#[godot_api]
impl RemichScorer {
    /// Scores the activities available now and returns the choice.
    ///
    /// Input dictionary (plain values only):
    ///
    /// * `seed` — integer; the only thing that makes a run *this* run. It is
    ///   handed to the donor's own seeded actor state and never to a
    ///   tie-break.
    /// * `needs` — an array of exactly 7 numbers in donor order
    ///   (`food, water, shelter, safety, sleep, companionship, joy`), each in
    ///   `[0.0, 1.0]`.
    /// * `time_of_day` — number in `[0.0, 1.0]`.
    /// * `activities` — an array of dictionaries, each `{ "id": int, "place":
    ///   String }`. `id` must exist in the donor action catalogue; `place` is
    ///   Remich's own metadata and can never affect a score.
    /// * `skills` — optional array of donor skill names (`farmer`, `builder`,
    ///   `musician`, `storyteller`, `healer`). Default: none.
    /// * `settlement_damage` — optional number in `[0.0, 1.0]`. Default `0.0`.
    /// * `settlement_aggregate_mood` — optional number in `[-1.0, 1.0]`.
    ///   Default `0.0`.
    ///
    /// The three optional inputs are documented neutral defaults: inside those
    /// values the donor's own modifiers return the same constant for every
    /// candidate, so none of them can tilt the ranking. They are placeholders
    /// for explicit caller input, not final Munshausen behaviour.
    ///
    /// Output dictionary: `ok`, `bridge_rev`, `seed`, `time_of_day`,
    /// `chosen_id`, `chosen_name`, `chosen_place`, `chosen_score`, and
    /// `candidates` — an array of `{ "id", "name", "place", "score" }` in
    /// input order, including the choice. On failure `ok` is `false` and
    /// `error` says why; nothing is substituted for a rejected request.
    #[func]
    fn score_activity(&self, input: VarDictionary) -> VarDictionary {
        match parse_score_input(&input) {
            Ok(request) => match scorer::score(&request) {
                Ok(outcome) => score_result(&outcome, request.seed, request.time_of_day),
                Err(error) => failure("scorer-error", &error.to_string()),
            },
            Err(message) => failure("bad-input", &message),
        }
    }

    /// Advances the actor's needs across ticks, applying donor decay.
    ///
    /// Arguments: the seven need values (array), `from_tick`, `to_tick`.
    /// Returns `ok`, `bridge_rev`, the decayed `needs`, how many `decay_steps`
    /// were applied, and the tick range echoed back.
    ///
    /// Semantics are the donor's own — one step per tick divisible by 10,
    /// `Need::decay_rate()` subtracted, clamped at `0.0`, Safety never moving —
    /// documented in `remich_core::decay` with its donor reference.
    #[func]
    fn advance_time(&self, needs: VarArray, from_tick: i64, to_tick: i64) -> VarDictionary {
        if from_tick < 0 || to_tick < 0 {
            return failure("bad-input", "ticks must not be negative");
        }

        let plain = match plain_needs(&needs) {
            Ok(plain) => plain,
            Err(message) => return failure("bad-input", &message),
        };

        match advance_needs(&plain, from_tick as u64, to_tick as u64) {
            Ok(advanced) => {
                let mut result = VarDictionary::new();
                result.set("ok", true);
                result.set("bridge_rev", SCORER_BRIDGE_REV);
                result.set("decay_steps", advanced.decay_steps as i64);
                result.set("from_tick", from_tick);
                result.set("to_tick", to_tick);
                result.set("needs", &need_array(&advanced.needs));
                result
            }
            Err(error) => failure("scorer-error", &error.to_string()),
        }
    }

    /// The revision marker this library was built with, on its own.
    #[func]
    fn scorer_bridge_rev(&self) -> GString {
        SCORER_BRIDGE_REV.into()
    }
}

/// The Godot-facing world clock (docs/PLAN.md, phase 2, step 1).
///
/// The authoritative state lives in the engine-free `remich_core::clock`
/// [`WorldClock`] held by this class; this layer only exposes it and drives
/// it. Exactly one instance of this class is meant to exist in the test
/// project — `godot/world_clock.gd` instantiates the single shared node and
/// every other script reaches the clock through that node, never with a
/// second copy of the tick.
///
/// Everything observable is integer: `tick` (`i64`), `tick_length_ns`
/// (`i64`), `speed` (`i64`), `is_paused` (bool). Advancement happens only in
/// [`RemichWorldClock::pulse`], which takes **no** arguments — there is no
/// float `delta` parameter and no API that advances by seconds.
#[derive(GodotClass)]
#[class(base = Node)]
pub struct RemichWorldClock {
    base: Base<Node>,
    /// The one authoritative clock. Created once by [`Self::initialize`].
    clock: Option<WorldClock>,
}

#[godot_api]
impl INode for RemichWorldClock {
    fn init(base: Base<Node>) -> Self {
        Self { base, clock: None }
    }
}

#[godot_api]
impl RemichWorldClock {
    /// Creates the authoritative clock with the fixed tick length, in whole
    /// nanoseconds, supplied by the test project. The value is integer state
    /// and stays immutable for the life of the clock. A zero (or negative)
    /// length is refused; so is a second initialization, because the tick
    /// length must never change under a running clock.
    #[func]
    fn initialize(&mut self, tick_length_ns: i64) -> VarDictionary {
        if self.clock.is_some() {
            return clock_failure(
                "already-initialized",
                "the tick length is fixed at construction",
            );
        }
        if tick_length_ns <= 0 {
            return clock_failure(
                "bad-input",
                "tick length must be a positive number of nanoseconds",
            );
        }
        match WorldClock::new(tick_length_ns as u64) {
            Ok(clock) => {
                self.clock = Some(clock);
                let mut result = VarDictionary::new();
                result.set("ok", true);
                result.set("bridge_rev", CLOCK_BRIDGE_REV);
                result.set("tick_length_ns", tick_length_ns);
                result
            }
            Err(error) => clock_failure("init-failed", &error.to_string()),
        }
    }

    /// Whether [`Self::initialize`] has succeeded yet.
    #[func]
    fn is_initialized(&self) -> bool {
        self.clock.is_some()
    }

    /// The authoritative integer tick. `-1` before initialization.
    #[func]
    fn tick(&self) -> i64 {
        match &self.clock {
            Some(clock) => clock.tick() as i64,
            None => -1,
        }
    }

    /// The fixed tick length in whole nanoseconds. `-1` before
    /// initialization.
    #[func]
    fn tick_length_ns(&self) -> i64 {
        match &self.clock {
            Some(clock) => clock.tick_length_ns() as i64,
            None => -1,
        }
    }

    /// The integer speed multiplier. `0` before initialization.
    #[func]
    fn speed(&self) -> i64 {
        match &self.clock {
            Some(clock) => i64::from(clock.speed()),
            None => 0,
        }
    }

    /// Whether the clock is paused (uninitialized counts as not running:
    /// it emits nothing either way).
    #[func]
    fn is_paused(&self) -> bool {
        match &self.clock {
            Some(clock) => clock.is_paused(),
            None => true,
        }
    }

    /// Sets the integer speed multiplier (≥ 1). `0` is refused — pause is
    /// how a clock stops, not a speed of zero.
    #[func]
    fn set_speed(&mut self, speed: i64) -> VarDictionary {
        let Some(clock) = self.clock.as_mut() else {
            return clock_failure("not-initialized", "call initialize first");
        };
        if speed < 1 || speed > i64::from(u32::MAX) {
            return clock_failure("bad-input", "speed must be an integer of at least 1");
        }
        match clock.set_speed(speed as u32) {
            Ok(()) => {
                let mut result = VarDictionary::new();
                result.set("ok", true);
                result.set("bridge_rev", CLOCK_BRIDGE_REV);
                result.set("speed", speed);
                result
            }
            Err(error) => clock_failure("bad-input", &error.to_string()),
        }
    }

    /// Pauses the clock: pulses emit nothing until [`Self::resume`].
    #[func]
    fn pause(&mut self) -> VarDictionary {
        let Some(clock) = self.clock.as_mut() else {
            return clock_failure("not-initialized", "call initialize first");
        };
        clock.pause();
        let mut result = VarDictionary::new();
        result.set("ok", true);
        result.set("bridge_rev", CLOCK_BRIDGE_REV);
        result.set("paused", true);
        result
    }

    /// Resumes the clock at exactly the next integer tick, at the retained
    /// speed.
    #[func]
    fn resume(&mut self) -> VarDictionary {
        let Some(clock) = self.clock.as_mut() else {
            return clock_failure("not-initialized", "call initialize first");
        };
        clock.resume();
        let mut result = VarDictionary::new();
        result.set("ok", true);
        result.set("bridge_rev", CLOCK_BRIDGE_REV);
        result.set("paused", false);
        result
    }

    /// Re-positions the clock at an explicit integer tick (fixture setup).
    #[func]
    fn reset(&mut self, tick: i64) -> VarDictionary {
        let Some(clock) = self.clock.as_mut() else {
            return clock_failure("not-initialized", "call initialize first");
        };
        if tick < 0 {
            return clock_failure("bad-input", "tick must not be negative");
        }
        clock.reset(tick as u64);
        let mut result = VarDictionary::new();
        result.set("ok", true);
        result.set("bridge_rev", CLOCK_BRIDGE_REV);
        result.set("tick", tick);
        result
    }

    /// One driver pulse: returns every tick made available by this pulse, in
    /// order — `speed` consecutive integers at speed 1/4, none while paused.
    /// Takes no arguments: there is no delta, no seconds, no float input of
    /// any kind. Consumers iterate the returned ticks and process each one.
    #[func]
    fn pulse(&mut self) -> VarArray {
        let mut ticks = VarArray::new();
        let Some(clock) = self.clock.as_mut() else {
            godot_error!("RemichWorldClock: pulse before initialize");
            return ticks;
        };
        for tick in clock.pulse().ticks() {
            ticks.push(tick as i64);
        }
        ticks
    }

    /// Presents an integer tick as a position inside a caller-supplied
    /// cycle — the one float conversion, at the edge, for values like
    /// normalized time of day. The caller must state the cycle length; the
    /// clock never decides one. Returns `-1.0` (and logs) for a bad input.
    #[func]
    fn cycle_position(&self, tick: i64, cycle_length: i64) -> f64 {
        if tick < 0 || cycle_length <= 0 {
            godot_error!("RemichWorldClock: cycle_position needs tick >= 0 and cycle_length >= 1");
            return -1.0;
        }
        match WorldClock::cycle_position(tick as u64, cycle_length as u64) {
            Ok(position) => position,
            Err(error) => {
                godot_error!("RemichWorldClock: {error}");
                -1.0
            }
        }
    }

    /// The clock's whole state, read for the game's save (Phase 2, Step 3):
    /// tick, fixed tick length, speed and pause as plain values. No
    /// wall-clock reading happens here — this clock has none to read.
    #[func]
    fn capture_state(&self) -> VarDictionary {
        let Some(clock) = self.clock.as_ref() else {
            return clock_failure("not-initialized", "call initialize first");
        };
        let state = clock.capture_state();
        let mut result = VarDictionary::new();
        result.set("ok", true);
        result.set("bridge_rev", CLOCK_BRIDGE_REV);
        result.set("tick", state.tick as i64);
        result.set("tick_length_ns", state.tick_length_ns as i64);
        result.set("speed", i64::from(state.speed));
        result.set("paused", state.paused);
        result
    }

    /// Replaces this clock's whole state from a validated save (Phase 2,
    /// Step 3). This is the one sanctioned full-state replacement: it mutates
    /// **the same native clock** the autoload holds — no second clock is ever
    /// created — and it validates the state the same way construction does
    /// (a zero tick length or a zero speed is refused and nothing changes).
    #[func]
    fn restore_state(&mut self, state: VarDictionary) -> VarDictionary {
        let Some(clock) = self.clock.as_mut() else {
            return clock_failure("not-initialized", "call initialize first");
        };
        let parsed = (|| -> Result<remich_core::clock::ClockState, String> {
            let tick = plain_integer(&field(&state, "tick")?, "clock state tick")?;
            let tick_length_ns =
                plain_integer(&field(&state, "tick_length_ns")?, "clock state tick_length_ns")?;
            let speed = plain_integer(&field(&state, "speed")?, "clock state speed")?;
            let paused = field(&state, "paused")?
                .try_to::<bool>()
                .map_err(|_| "clock state paused must be a bool".to_string())?;
            if speed > u64::from(u32::MAX) {
                return Err("clock state speed exceeds u32".to_string());
            }
            Ok(remich_core::clock::ClockState {
                tick,
                tick_length_ns,
                speed: speed as u32,
                paused,
            })
        })();
        let parsed = match parsed {
            Ok(parsed) => parsed,
            Err(message) => return clock_failure("bad-input", &message),
        };
        match clock.restore_state(parsed) {
            Ok(()) => {
                let mut result = VarDictionary::new();
                result.set("ok", true);
                result.set("bridge_rev", CLOCK_BRIDGE_REV);
                result.set("tick", parsed.tick as i64);
                result.set("tick_length_ns", parsed.tick_length_ns as i64);
                result.set("speed", i64::from(parsed.speed));
                result.set("paused", parsed.paused);
                result
            }
            Err(error) => clock_failure("bad-input", &error.to_string()),
        }
    }

    /// The revision marker this library was built with, on its own.
    #[func]
    fn clock_bridge_rev(&self) -> GString {
        CLOCK_BRIDGE_REV.into()
    }
}

/// A refused clock request: says why, substitutes nothing.
fn clock_failure(code: &str, message: &str) -> VarDictionary {
    godot_error!("RemichWorldClock: {code}: {message}");
    let mut result = VarDictionary::new();
    result.set("ok", false);
    result.set("bridge_rev", CLOCK_BRIDGE_REV);
    result.set("code", code);
    result.set("error", message);
    result
}

// ---------------------------------------------------------------------------
// The one weather snapshot, exposed as one shared node (Phase 2, Step 2).
//
// The native object owns the Rust-held channel: one writer, everyone else
// reads. Godot keeps no second copy of tick, wind, rain, temperature or
// light — every read here goes straight to `remich_core::weather`, and every
// publish goes through the stand-in driver that owns the channel. There is
// no setter for arbitrary weather values: `drive` takes the integer world
// tick and publishes what the fixture schedule says for that tick, nothing
// else.
// ---------------------------------------------------------------------------

/// The presentation phase passed to the wind global's W component, in
/// radians: a **pure function of the integer tick and the caller's explicit
/// cycle length** — `2π * (tick mod cycle) / cycle`.
///
/// This is presentation/test-fixture behaviour (docs/remich-weather-
/// phase2-step2.md), not weather and not saved state: the motion phase is
/// Grengewald's renderer-facing input, and it deliberately does not live in
/// the weather snapshot. No time is accumulated to produce it.
fn presentation_phase(tick: u64, cycle_length: u64) -> f64 {
    if cycle_length == 0 {
        return 0.0;
    }
    let phase = tick % cycle_length;
    phase as f64 / cycle_length as f64 * std::f64::consts::TAU
}

/// The exact vector the wind global is written with, derived from the
/// snapshot: X ← direction X, Y ← direction Z, Z ← wind strength adapted to
/// Grengewald's gentle 0..1 metre displacement input (the fixture strength
/// already lives in that range, so the adaptation is a clamp at the edge),
/// W ← the presentation phase of the snapshot's integer tick.
fn wind_vector(snapshot: &WeatherSnapshot, cycle_length: u64) -> [f64; 4] {
    [
        snapshot.wind_dir_x,
        snapshot.wind_dir_z,
        snapshot.wind_strength.clamp(0.0, 1.0),
        presentation_phase(snapshot.tick, cycle_length),
    ]
}

/// The shared weather node: the one place Godot reaches the Rust-held
/// snapshot.
///
/// One instance exists in the test project (`godot/weather.gd`, the `Weather`
/// autoload). `initialize` is the only way in, and it claims the channel for
/// the stand-in driver — a second initialization is refused rather than
/// replacing the first. `drive` publishes for a supplied integer world tick
/// (the ticks come from the shared world clock; this class never advances
/// time itself), `snapshot`/`writer_status` are plain reads, and
/// `apply_wind` performs the one live write of the Grengewald wind global
/// from the current snapshot through the engine's real setter.
#[derive(GodotClass)]
#[class(base = Node)]
pub struct RemichWeather {
    base: Base<Node>,
    /// The one authoritative weather channel. Created once by
    /// [`Self::initialize`]; nobody outside it ever mutates weather.
    channel: Option<WeatherChannel>,
    /// The fixture driver that owns the channel (seed + cycle length only).
    stand_in: Option<StandInWeather>,
    /// Instrumentation: the exact `vec4` handed to the shader-global setter
    /// on the most recent [`Self::apply_wind`], in the setter's own
    /// 32-bit-rounded components. Read back by the probe as the applied
    /// vector; empty before the first apply.
    last_applied: Option<[f64; 4]>,
}

#[godot_api]
impl INode for RemichWeather {
    fn init(base: Base<Node>) -> Self {
        Self {
            base,
            channel: None,
            stand_in: None,
            last_applied: None,
        }
    }
}

#[godot_api]
impl RemichWeather {
    /// Creates the one weather channel and claims it for the stand-in
    /// driver. A second initialization is refused — the stand-in's seed and
    /// cycle are fixture constants of a run, never swapped under a live
    /// channel.
    #[func]
    fn initialize(&mut self, seed: i64, cycle_length: i64) -> VarDictionary {
        if self.channel.is_some() {
            return weather_failure(
                "already-initialized",
                "the weather channel is created once, like the clock",
            );
        }
        if seed < 0 {
            return weather_failure("bad-input", "seed must not be negative");
        }
        if cycle_length <= 0 {
            return weather_failure("bad-input", "cycle length must be at least 1 tick");
        }
        let stand_in = match StandInWeather::new(seed as u64, cycle_length as u64) {
            Ok(stand_in) => stand_in,
            Err(error) => return weather_refusal(&error),
        };
        let mut channel = WeatherChannel::new();
        if let Err(error) = stand_in.attach(&mut channel) {
            return weather_refusal(&error);
        }
        self.channel = Some(channel);
        self.stand_in = Some(stand_in);
        self.last_applied = None;

        let mut result = VarDictionary::new();
        result.set("ok", true);
        result.set("bridge_rev", WEATHER_BRIDGE_REV);
        result.set("writer", STAND_IN_DRIVER_ID);
        result.set("seed", seed);
        result.set("cycle_length", cycle_length);
        result
    }

    /// Whether [`Self::initialize`] has succeeded yet.
    #[func]
    fn is_initialized(&self) -> bool {
        self.channel.is_some()
    }

    /// The stand-in driver's seed. `-1` before initialization.
    #[func]
    fn seed(&self) -> i64 {
        match self.stand_in {
            Some(stand_in) => stand_in.seed() as i64,
            None => -1,
        }
    }

    /// The explicit cycle length in integer ticks. `-1` before
    /// initialization.
    #[func]
    fn cycle_length(&self) -> i64 {
        match self.stand_in {
            Some(stand_in) => stand_in.cycle_length() as i64,
            None => -1,
        }
    }

    /// Publishes the stand-in snapshot for the supplied **integer world
    /// tick** and returns it. The tick comes from the shared world clock;
    /// this call never advances time, never reads a delta and never generates
    /// a value of its own — it is `seed + tick` and nothing else. Refused
    /// (with the conflict named) if the channel is not owned by the stand-in
    /// driver.
    #[func]
    fn drive(&mut self, tick: i64) -> VarDictionary {
        if tick < 0 {
            return weather_failure("bad-input", "tick must not be negative");
        }
        let (Some(channel), Some(stand_in)) = (self.channel.as_mut(), self.stand_in.as_ref())
        else {
            return weather_failure("not-initialized", "call initialize first");
        };
        match stand_in.drive(channel, tick as u64) {
            Ok(snapshot) => snapshot_dictionary(&snapshot, stand_in.seed()),
            Err(error) => weather_refusal(&error),
        }
    }

    /// The latest published snapshot, read straight from the Rust channel.
    /// `ok=false` with code `no-snapshot` before the first publish. Reading
    /// never claims the channel and never writes.
    #[func]
    fn snapshot(&self) -> VarDictionary {
        let Some(channel) = self.channel.as_ref() else {
            return weather_failure("not-initialized", "call initialize first");
        };
        match channel.read() {
            Some(snapshot) => snapshot_dictionary(&snapshot, self.seed().max(0) as u64),
            None => weather_failure("no-snapshot", "no snapshot has been published yet"),
        }
    }

    /// The channel's writer identity — `""` before initialization.
    #[func]
    fn writer_id(&self) -> GString {
        match &self.channel {
            Some(channel) => channel.writer_id().unwrap_or_default().into(),
            None => GString::new(),
        }
    }

    /// The full ownership status a reader may inspect: who owns the channel,
    /// whether a snapshot exists, and the tick that snapshot applies to
    /// (`-1` when there is none).
    #[func]
    fn writer_status(&self) -> VarDictionary {
        let mut result = VarDictionary::new();
        result.set("ok", true);
        result.set("bridge_rev", WEATHER_BRIDGE_REV);
        match &self.channel {
            None => {
                result.set("owned", false);
                result.set("writer", "");
                result.set("has_snapshot", false);
                result.set("snapshot_tick", -1);
            }
            Some(channel) => {
                result.set("owned", channel.is_owned());
                result.set("writer", channel.writer_id().unwrap_or_default());
                let latest = channel.read();
                result.set("has_snapshot", latest.is_some());
                result.set(
                    "snapshot_tick",
                    latest.map(|s| s.tick as i64).unwrap_or(-1),
                );
            }
        }
        result
    }

    /// A writer-ownership probe: lets the test project *attempt* a claim as a
    /// distinct identity. The attempt goes through the same channel API as
    /// everything else, so it cannot bypass the one-writer rule — it exists
    /// so acceptance can watch a second writer be refused from the engine
    /// side, with the conflict named on both sides.
    #[func]
    fn try_claim_writer(&mut self, writer: GString) -> VarDictionary {
        let Some(channel) = self.channel.as_mut() else {
            return weather_failure("not-initialized", "call initialize first");
        };
        match channel.claim_writer(&writer.to_string()) {
            Ok(()) => {
                let mut result = VarDictionary::new();
                result.set("ok", true);
                result.set("bridge_rev", WEATHER_BRIDGE_REV);
                result.set("writer", channel.writer_id().unwrap_or_default());
                result
            }
            Err(error) => weather_refusal(&error),
        }
    }

    /// Writes the Grengewald wind global from the **current snapshot**
    /// through the engine's real runtime setter
    /// (`RenderingServer.global_shader_parameter_set`), and returns the exact
    /// vector that was applied — also kept as instrumentation for
    /// [`Self::last_applied_wind`]. Refused when no snapshot exists. This is
    /// the binding's one live render write; the snapshot itself never
    /// becomes renderer-specific.
    #[func]
    fn apply_wind(&mut self) -> VarDictionary {
        let (Some(channel), Some(stand_in)) = (&self.channel, self.stand_in) else {
            return weather_failure("not-initialized", "call initialize first");
        };
        let Some(snapshot) = channel.read() else {
            return weather_failure("no-snapshot", "no snapshot has been published yet");
        };

        let [x, y, z, w] = wind_vector(&snapshot, stand_in.cycle_length());
        // Godot's `vec4` (and Grengewald's shader) is 32-bit: convert once,
        // at this edge, and record the rounded components — the setter's
        // argument exactly — rather than the unrounded inputs.
        let vector = Vector4::new(x as f32, y as f32, z as f32, w as f32);
        let applied = [
            f64::from(vector.x),
            f64::from(vector.y),
            f64::from(vector.z),
            f64::from(vector.w),
        ];
        let variant = vector.to_variant();
        let mut rendering = RenderingServer::singleton();
        rendering.global_shader_parameter_set(WIND_GLOBAL_NAME, &variant);
        self.last_applied = Some(applied);

        let mut result = VarDictionary::new();
        result.set("ok", true);
        result.set("bridge_rev", WEATHER_BRIDGE_REV);
        result.set("tick", snapshot.tick as i64);
        let mut applied_array = VarArray::new();
        for value in applied {
            applied_array.push(value);
        }
        result.set("applied", &applied_array);
        result
    }

    /// The exact vector handed to the wind-global setter on the most recent
    /// [`Self::apply_wind`] (four 32-bit-rounded components: X, Y, Z, W).
    /// Empty before the first apply. Instrumentation for the probe — the
    /// engine's runtime global getter is editor-only in the compatibility
    /// backend, so this recorded argument is how the applied vector is read
    /// back.
    #[func]
    fn last_applied_wind(&self) -> VarArray {
        let mut applied_array = VarArray::new();
        if let Some(applied) = self.last_applied {
            for value in applied {
                applied_array.push(value);
            }
        }
        applied_array
    }

    /// The save-restore path (Phase 2, Step 3): re-publishes a **validated
    /// saved snapshot** through the channel's legitimate owner.
    ///
    /// This is not a weather setter: it does not accept arbitrary values
    /// from a live caller — it takes the `{seed, cycle_length, snapshot}`
    /// structure a loaded save produced, verifies the seed and cycle length
    /// against the run's already-constructed stand-in driver (those two are
    /// fixture configuration fixed at construction, saved for integrity and
    /// never swapped under a live channel), and then publishes the snapshot
    /// with `channel.publish(STAND_IN_DRIVER_ID, ..)` — the same one-writer
    /// API `drive` uses. A second writer still cannot publish: the channel
    /// stays owned by the stand-in driver, and every existing refusal
    /// (including Step 2's second-writer proof) still holds. The
    /// presentation phase is **not** restored — it is derived again from the
    /// restored integer tick when the wind global is next applied.
    #[func]
    fn restore_save_state(&mut self, state: VarDictionary) -> VarDictionary {
        let (Some(channel), Some(stand_in)) = (&mut self.channel, &self.stand_in) else {
            return weather_failure("not-initialized", "call initialize first");
        };
        let parsed = (|| -> Result<(u64, u64, WeatherSnapshot), String> {
            let seed = plain_integer(&field(&state, "seed")?, "saved weather seed")?;
            let cycle_length =
                plain_integer(&field(&state, "cycle_length")?, "saved weather cycle_length")?;
            let snapshot =
                snapshot_from_dictionary(&field(&state, "snapshot")?.try_to::<VarDictionary>()
                    .map_err(|_| "saved weather snapshot must be a dictionary".to_string())?)?;
            Ok((seed, cycle_length, snapshot))
        })();
        let (seed, cycle_length, snapshot) = match parsed {
            Ok(parsed) => parsed,
            Err(message) => return weather_failure("bad-input", &message),
        };
        if seed != stand_in.seed() {
            return weather_failure(
                "fixture-mismatch",
                &format!(
                    "the save's weather seed {seed} is not this run's stand-in seed {}",
                    stand_in.seed()
                ),
            );
        }
        if cycle_length != stand_in.cycle_length() {
            return weather_failure(
                "fixture-mismatch",
                &format!(
                    "the save's weather cycle length {cycle_length} is not this run's {}",
                    stand_in.cycle_length()
                ),
            );
        }
        match channel.publish(STAND_IN_DRIVER_ID, snapshot) {
            Ok(()) => {
                self.last_applied = None;
                let mut result = VarDictionary::new();
                result.set("ok", true);
                result.set("bridge_rev", WEATHER_BRIDGE_REV);
                result.set("writer", STAND_IN_DRIVER_ID);
                result.set("seed", seed as i64);
                result.set("cycle_length", cycle_length as i64);
                result.set("tick", snapshot.tick as i64);
                result
            }
            Err(error) => weather_refusal(&error),
        }
    }

    /// The revision marker this library was built with, on its own.
    #[func]
    fn weather_bridge_rev(&self) -> GString {
        WEATHER_BRIDGE_REV.into()
    }
}

/// The published snapshot as plain Godot data. Plain reads only: this is the
/// same Rust struct the channel holds, handed across the boundary.
pub(crate) fn snapshot_dictionary(snapshot: &WeatherSnapshot, seed: u64) -> VarDictionary {
    let mut result = VarDictionary::new();
    result.set("ok", true);
    result.set("bridge_rev", WEATHER_BRIDGE_REV);
    result.set("seed", seed as i64);
    result.set("tick", snapshot.tick as i64);
    result.set("wind_dir_x", snapshot.wind_dir_x);
    result.set("wind_dir_z", snapshot.wind_dir_z);
    result.set("wind_strength", snapshot.wind_strength);
    result.set("rain", snapshot.rain);
    result.set("temperature", snapshot.temperature);
    result.set("light", snapshot.light);
    result
}

/// Reads the seven plain snapshot fields back out of a dictionary — the
/// inverse of [`snapshot_dictionary`], used by the save paths. The extra
/// keys a live read carries (`ok`, `bridge_rev`, `seed`) are ignored; every
/// snapshot field itself is required, and the values go through
/// [`WeatherSnapshot::new`]'s validation, so a malformed structure is
/// refused rather than defaulted.
pub(crate) fn snapshot_from_dictionary(
    input: &VarDictionary,
) -> Result<WeatherSnapshot, String> {
    let tick = plain_integer(&field(input, "tick")?, "snapshot tick")?;
    let wind_dir_x = plain_number(&field(input, "wind_dir_x")?, "snapshot wind_dir_x")?;
    let wind_dir_z = plain_number(&field(input, "wind_dir_z")?, "snapshot wind_dir_z")?;
    let wind_strength =
        plain_number(&field(input, "wind_strength")?, "snapshot wind_strength")?;
    let rain = plain_number(&field(input, "rain")?, "snapshot rain")?;
    let temperature = plain_number(&field(input, "temperature")?, "snapshot temperature")?;
    let light = plain_number(&field(input, "light")?, "snapshot light")?;
    WeatherSnapshot::new(
        tick,
        wind_dir_x,
        wind_dir_z,
        wind_strength,
        rain,
        temperature,
        light,
    )
    .map_err(|error| error.to_string())
}

/// A refused weather request: says why, substitutes nothing. An ownership
/// conflict additionally carries both identities, so the refusal names the
/// conflict instead of merely reporting failure.
fn weather_refusal(error: &WeatherError) -> VarDictionary {
    let code = match error {
        WeatherError::WriterConflict { .. } => "writer-conflict",
        WeatherError::EmptyWriterId | WeatherError::PublishWithoutWriter => "writer-ownership",
        WeatherError::NonFinite { .. }
        | WeatherError::NegativeWindStrength
        | WeatherError::ZeroCycleLength => "invalid-snapshot",
    };
    godot_error!("RemichWeather: {code}: {error}");
    let mut result = VarDictionary::new();
    result.set("ok", false);
    result.set("bridge_rev", WEATHER_BRIDGE_REV);
    result.set("code", code);
    result.set("error", error.to_string());
    if let WeatherError::WriterConflict { held_by, attempted } = error {
        result.set("held_by", held_by.clone());
        result.set("attempted", attempted.clone());
    }
    result
}

/// A refused weather setup: says why, substitutes nothing.
fn weather_failure(code: &str, message: &str) -> VarDictionary {
    godot_error!("RemichWeather: {code}: {message}");
    let mut result = VarDictionary::new();
    result.set("ok", false);
    result.set("bridge_rev", WEATHER_BRIDGE_REV);
    result.set("code", code);
    result.set("error", message);
    result
}

// ---------------------------------------------------------------------------
// Plain-data conversion. This is the whole of this layer's work: no scoring,
// no defaults beyond the three documented above, no inference.
// ---------------------------------------------------------------------------

/// Reads a required field, naming it when it is missing.
pub(crate) fn field(input: &VarDictionary, key: &str) -> Result<Variant, String> {
    input
        .get(key)
        .ok_or_else(|| format!("missing required field '{key}'"))
}

/// Reads a number; an integer is accepted where a number is wanted.
pub(crate) fn plain_number(value: &Variant, what: &str) -> Result<f64, String> {
    if let Ok(number) = value.try_to::<f64>() {
        return Ok(number);
    }
    if let Ok(number) = value.try_to::<i64>() {
        return Ok(number as f64);
    }
    Err(format!(
        "{what} must be a number, got {:?}",
        value.get_type()
    ))
}

/// Reads a non-negative integer, allowing a whole-number float through.
pub(crate) fn plain_integer(value: &Variant, what: &str) -> Result<u64, String> {
    if let Ok(number) = value.try_to::<i64>() {
        if number < 0 {
            return Err(format!("{what} must not be negative, got {number}"));
        }
        return Ok(number as u64);
    }
    let number = plain_number(value, what)?;
    if number < 0.0 || number.fract() != 0.0 || number > u64::MAX as f64 {
        return Err(format!("{what} must be a whole non-negative number, got {number}"));
    }
    Ok(number as u64)
}

/// Reads a string.
pub(crate) fn plain_text(value: &Variant, what: &str) -> Result<String, String> {
    value
        .try_to::<GString>()
        .map(|text| text.to_string())
        .map_err(|_| format!("{what} must be a string, got {:?}", value.get_type()))
}

/// Reads the seven need values out of a plain array.
pub(crate) fn plain_needs(values: &VarArray) -> Result<[f32; scorer::NEED_COUNT], String> {
    if values.len() != scorer::NEED_COUNT {
        return Err(format!(
            "expected {} need values, got {}",
            scorer::NEED_COUNT,
            values.len()
        ));
    }

    let mut needs = [0.0f32; scorer::NEED_COUNT];
    for (index, slot) in needs.iter_mut().enumerate() {
        let value = values.at(index);
        *slot = plain_number(&value, &format!("need at index {index}"))? as f32;
    }
    Ok(needs)
}

/// Reads the available activities: `{ "id", "place" }` dictionaries.
fn plain_activities(values: &VarArray) -> Result<Vec<scorer::AvailableActivity>, String> {
    if values.is_empty() {
        return Err("at least one activity is required".to_string());
    }

    let mut activities = Vec::with_capacity(values.len());
    for (index, entry) in values.iter_shared().enumerate() {
        let dictionary = entry.try_to::<VarDictionary>().map_err(|_| {
            format!("activity at index {index} must be a dictionary, got {:?}", entry.get_type())
        })?;

        let id = plain_integer(&field(&dictionary, "id")?, &format!("activity {index}.id"))?;
        if id == 0 {
            return Err(format!("activity {index}.id must not be 0"));
        }
        let place = plain_text(&field(&dictionary, "place")?, &format!("activity {index}.place"))?;

        activities.push(scorer::AvailableActivity::new(id, place));
    }
    Ok(activities)
}

/// Reads the optional skill-name list, defaulting to none.
///
/// The donor's `Skill` enum never appears in this crate: the names are plain
/// strings here and are resolved by `remich_core` a few lines below.
fn plain_skill_names(input: &VarDictionary) -> Result<Vec<String>, String> {
    let Some(value) = input.get("skills") else {
        return Ok(Vec::new());
    };
    let values = value
        .try_to::<VarArray>()
        .map_err(|_| format!("skills must be an array of names, got {:?}", value.get_type()))?;

    let mut names = Vec::with_capacity(values.len());
    for (index, entry) in values.iter_shared().enumerate() {
        names.push(plain_text(&entry, &format!("skill at index {index}"))?);
    }
    Ok(names)
}

/// Turns the Godot dictionary into the engine-free request.
fn parse_score_input(input: &VarDictionary) -> Result<ScorerInput, String> {
    let seed = plain_integer(&field(input, "seed")?, "seed")?;
    let needs = plain_needs(
        &field(input, "needs")?
            .try_to::<VarArray>()
            .map_err(|_| "needs must be an array of 7 numbers".to_string())?,
    )?;
    let time_of_day = plain_number(&field(input, "time_of_day")?, "time_of_day")? as f32;
    let activities = plain_activities(
        &field(input, "activities")?
            .try_to::<VarArray>()
            .map_err(|_| "activities must be an array of dictionaries".to_string())?,
    )?;

    let mut request = ScorerInput::new(seed, needs, time_of_day, activities);

    // Plain names in, donor skill values out — resolved by the adapter, so
    // this crate never names a donor type.
    let skill_names = plain_skill_names(input)?;
    if !skill_names.is_empty() {
        let skills = scorer::skills_from_names(skill_names)
            .map_err(|error| error.to_string())?;
        request = request.with_skills(skills);
    }

    if let Some(value) = input.get("settlement_damage") {
        request.settlement_damage = plain_number(&value, "settlement_damage")? as f32;
    }
    if let Some(value) = input.get("settlement_aggregate_mood") {
        request.settlement_aggregate_mood =
            plain_number(&value, "settlement_aggregate_mood")? as f32;
    }

    Ok(request)
}

/// The plain seven-value need array, as Godot receives it.
pub(crate) fn need_array(needs: &[f32; scorer::NEED_COUNT]) -> VarArray {
    let mut values = VarArray::new();
    for value in needs {
        values.push(f64::from(*value));
    }
    values
}

/// A successful scoring result, as plain data.
fn score_result(outcome: &ScorerOutcome, seed: u64, time_of_day: f32) -> VarDictionary {
    let mut candidates = VarArray::new();
    for candidate in &outcome.candidates {
        let mut entry = VarDictionary::new();
        entry.set("id", candidate.id as i64);
        entry.set("name", candidate.name.as_str());
        entry.set("place", candidate.place.as_str());
        entry.set("score", f64::from(candidate.score));
        candidates.push(&entry);
    }

    let mut result = VarDictionary::new();
    result.set("ok", true);
    result.set("bridge_rev", SCORER_BRIDGE_REV);
    result.set("seed", seed as i64);
    result.set("time_of_day", f64::from(time_of_day));
    result.set("chosen_id", outcome.chosen_id as i64);
    result.set("chosen_name", outcome.chosen_name.as_str());
    result.set("chosen_place", outcome.chosen_place.as_str());
    result.set("chosen_score", f64::from(outcome.chosen_score));
    result.set("candidates", &candidates);
    result
}

/// A refused request: says why, substitutes nothing.
fn failure(code: &str, message: &str) -> VarDictionary {
    godot_error!("RemichScorer: {code}: {message}");
    let mut result = VarDictionary::new();
    result.set("ok", false);
    result.set("bridge_rev", SCORER_BRIDGE_REV);
    result.set("code", code);
    result.set("error", message);
    result
}

/// The Godot-facing soul surface (docs/PLAN.md §4b, phase 3, step 2).
///
/// One narrow class over the engine-free `remich_core::soul` facade: create a
/// soul from a seed, read the substrate and the four axes back, ask for the
/// donor's propagated influence through a named connection layer, and read
/// this library's revision. Every argument and every result is a plain value,
/// an `Array` or a `Dictionary` — no Munshausen type, no Eisleck type, no
/// Larochette node, no resource handle, and no emotion formula in GDScript:
/// the calls below only convert and forward.
///
/// Deliberately absent, and checked as absent by
/// `tools/check_phase3_step2.sh`: any event that changes an axis (need met or
/// unmet, catastrophe felt), any call that writes an influence into a soul,
/// and any weight or propagation formula of our own. The donor computes the
/// influence; what it *means* for an inhabitant belongs to the lead's
/// Munshausen wiring (docs/PLAN.md §4b, "Lead steps").
#[derive(GodotClass)]
#[class(base = Node)]
pub struct RemichSoul {
    base: Base<Node>,
    /// The authoritative state: one engine-free facade, held in Rust.
    soul: Option<SoulFacade>,
}

#[godot_api]
impl INode for RemichSoul {
    fn init(base: Base<Node>) -> Self {
        Self { base, soul: None }
    }
}

#[godot_api]
impl RemichSoul {
    /// Creates the soul from a seed with the donor's `LayeredSoul::from_seed`.
    ///
    /// Returns `ok`, `bridge_rev` and the seed echoed back. A negative seed
    /// is refused outright rather than wrapped into a different one.
    #[func]
    fn initialize(&mut self, seed: i64) -> VarDictionary {
        if seed < 0 {
            return soul_failure("bad-input", "seed must not be negative");
        }
        self.soul = Some(SoulFacade::from_seed(seed as u64));
        let mut result = VarDictionary::new();
        result.set("ok", true);
        result.set("bridge_rev", SOUL_BRIDGE_REV);
        result.set("seed", seed);
        result
    }

    /// Whether this class holds an initialized soul.
    #[func]
    fn is_initialized(&self) -> bool {
        self.soul.is_some()
    }

    /// Reads the soul back: `seed`, `substrate` and the four `axes`, copied
    /// from the donor's own fields. Read-only — there is no setter here.
    #[func]
    fn soul_snapshot(&self) -> VarDictionary {
        let Some(soul) = &self.soul else {
            return soul_failure("not-initialized", "call initialize(seed) first");
        };
        let snapshot = soul.snapshot();
        let mut result = soul_ok();
        result.set("seed", snapshot.seed as i64);
        result.set("substrate", &substrate_dict(&snapshot.substrate));
        result.set("axes", &axes_dict(&snapshot.axes));
        result
    }

    /// The donor's edge strength for a named connection layer, on its own.
    ///
    /// The number comes from `ConnectionLayer::weight()`; an unknown layer
    /// name is refused rather than replaced by a default.
    #[func]
    fn connection_weight(&self, layer: GString) -> VarDictionary {
        let Some(soul) = &self.soul else {
            return soul_failure("not-initialized", "call initialize(seed) first");
        };
        let Some(connection) = connection_layer_from_name(&layer.to_string()) else {
            return soul_failure(
                "unknown-layer",
                &format!("'{layer}' is not a donor connection layer (family, proximity, village)"),
            );
        };
        let mut result = soul_ok();
        result.set("layer", connection_layer_name(connection));
        result.set("connection_weight", f64::from(soul.connection_weight(connection)));
        result
    }

    /// The donor's propagated influence through a named connection layer.
    ///
    /// Returns `ok`, `bridge_rev`, `layer`, `connection_weight`, the
    /// `source_axes` this influence was computed from, and
    /// `propagated_influence` — the four donor values. The influence is
    /// labelled as exactly that: it is **not** a new state for any soul, and
    /// this class writes nothing back. An unknown layer name is refused
    /// rather than substituted.
    #[func]
    fn propagate(&self, layer: GString) -> VarDictionary {
        let Some(soul) = &self.soul else {
            return soul_failure("not-initialized", "call initialize(seed) first");
        };
        let Some(connection) = connection_layer_from_name(&layer.to_string()) else {
            return soul_failure(
                "unknown-layer",
                &format!("'{layer}' is not a donor connection layer (family, proximity, village)"),
            );
        };

        let influence = soul.propagate(connection);
        let snapshot = soul.snapshot();
        let mut result = soul_ok();
        result.set("layer", connection_layer_name(influence.layer));
        result.set("connection_weight", f64::from(influence.connection_weight));
        result.set("source_axes", &axes_dict(&snapshot.axes));
        result.set("propagated_influence", &axes_dict(&influence.axes));
        result.set("value_kind", "propagated-influence");
        result.set("receiver_state_changed", false);
        result
    }

    /// The revision marker this library was built with, on its own.
    #[func]
    fn soul_bridge_rev(&self) -> GString {
        SOUL_BRIDGE_REV.into()
    }
}

/// A successful soul result: `ok` plus the revision every successful call
/// carries.
fn soul_ok() -> VarDictionary {
    let mut result = VarDictionary::new();
    result.set("ok", true);
    result.set("bridge_rev", SOUL_BRIDGE_REV);
    result
}

/// A refused soul request: says why, substitutes nothing.
fn soul_failure(code: &str, message: &str) -> VarDictionary {
    godot_error!("RemichSoul: {code}: {message}");
    let mut result = VarDictionary::new();
    result.set("ok", false);
    result.set("bridge_rev", SOUL_BRIDGE_REV);
    result.set("code", code);
    result.set("error", message);
    result
}

/// The four axes as a plain dictionary, in the donor's field order.
fn axes_dict(axes: &AxesSnapshot) -> VarDictionary {
    let mut result = VarDictionary::new();
    result.set("security_threat", f64::from(axes.security_threat));
    result.set("belonging_isolation", f64::from(axes.belonging_isolation));
    result.set("agency_helplessness", f64::from(axes.agency_helplessness));
    result.set("satiation_desperation", f64::from(axes.satiation_desperation));
    result
}

/// The three substrate traits as a plain dictionary, in the donor's field
/// order.
fn substrate_dict(substrate: &SubstrateSnapshot) -> VarDictionary {
    let mut result = VarDictionary::new();
    result.set("courage_fear", f64::from(substrate.courage_fear));
    result.set("generosity_selfishness", f64::from(substrate.generosity_selfishness));
    result.set("stability_anxiety", f64::from(substrate.stability_anxiety));
    result
}

/// The library's entry point type tag; `#[gdextension]` emits the
/// `gdext_rust_init` symbol that `godot/remich.gdextension` names.
struct RemichExtension;

#[gdextension]
unsafe impl ExtensionLibrary for RemichExtension {}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn layer_identifies_itself() {
        assert_eq!(LAYER_NAME, "remich_gdext");
    }

    #[test]
    fn boundary_forwards_to_the_core() {
        assert_eq!(forward_core_name(), "remich_core");
    }

    /// The bridge probe must stay recognisably a bridge probe: this is the
    /// prefix `godot/bridge_probe.gd` checks before it accepts a returned
    /// value as coming from this call and not from somewhere else.
    #[test]
    fn bridge_probe_value_is_a_probe() {
        assert!(BRIDGE_PROBE_VALUE.starts_with("remich-bridge-"));
        assert!(!BRIDGE_PROBE_VALUE.is_empty());
    }

    /// The scorer revision marker is the one line Step 4's rebuild measurement
    /// changes, so it must keep the shape `tools/stage_scorer.sh` parses.
    #[test]
    fn scorer_bridge_rev_is_the_committed_marker() {
        assert_eq!(SCORER_BRIDGE_REV, "remich-scorer-v1");
        assert!(SCORER_BRIDGE_REV.starts_with("remich-scorer-"));
    }

    /// The clock revision marker is the one line Step 1's rebuild measurement
    /// changes (`v1` -> `v2`, then restored), so it must keep the shape
    /// `tools/stage_clock.sh` parses and hold the committed value.
    #[test]
    fn clock_bridge_rev_is_the_committed_marker() {
        assert_eq!(CLOCK_BRIDGE_REV, "remich-clock-v1");
        assert!(CLOCK_BRIDGE_REV.starts_with("remich-clock-"));
    }

    /// The weather revision marker is the one line Step 2's rebuild
    /// measurement changes (`v1` -> `v2`, then restored), so it must keep the
    /// shape `tools/stage_weather.sh` parses and hold the committed value.
    #[test]
    fn weather_bridge_rev_is_the_committed_marker() {
        assert_eq!(WEATHER_BRIDGE_REV, "remich-weather-v1");
        assert!(WEATHER_BRIDGE_REV.starts_with("remich-weather-"));
    }

    /// The save revision marker is the one line Phase 2 Step 3's rebuild
    /// measurement changes (`v1` -> `v2`, then restored), so it must keep the
    /// shape `tools/stage_save.sh` parses and hold the committed value. It
    /// stays out of the engine-free core: the save document carries its own
    /// `format_version`, and this marker is implementation evidence only.
    #[test]
    fn save_bridge_rev_is_the_committed_marker() {
        assert_eq!(SAVE_BRIDGE_REV, "remich-save-v1");
        assert!(SAVE_BRIDGE_REV.starts_with("remich-save-"));
        let core_save = include_str!("../../remich_core/src/save.rs");
        assert!(
            !core_save.contains(SAVE_BRIDGE_REV),
            "the bridge revision must never appear in the engine-free save core"
        );
    }

    /// The soul revision marker is the one line Phase 3 Step 2's rebuild
    /// measurement changes (`v1` -> `v2`, then restored), so it must keep the
    /// shape `tools/stage_soul.sh` parses and hold the committed value. It is
    /// also the marker `godot/soul_probe.gd` reads back from the engine.
    #[test]
    fn soul_bridge_rev_is_the_committed_marker() {
        assert_eq!(SOUL_BRIDGE_REV, "remich-soul-v1");
        assert!(SOUL_BRIDGE_REV.starts_with("remich-soul-"));
    }

    /// The pinned Grengewald contract (standing ruling 1): exactly this
    /// global name, declared as `vec4` with default `Vector4(1,0,0,0)` in
    /// `godot/project.godot` and written here.
    #[test]
    fn the_wind_global_matches_the_pinned_grengewald_contract() {
        assert_eq!(WIND_GLOBAL_NAME, "grengewald_wind");
        let project = include_str!("../../../godot/project.godot");
        assert!(project.contains("[shader_globals]"));
        assert!(project.contains("grengewald_wind={"));
        assert!(project.contains("\"type\": \"vec4\""));
        assert!(project.contains("\"value\": Vector4(1, 0, 0, 0)"));
    }

    /// The mapping: the vector's weather-controlled components come from the
    /// snapshot, and W alone is the presentation phase. X ← direction X,
    /// Y ← direction Z, Z ← strength clamped into Grengewald's 0..1 metre
    /// displacement range, W ← `2π·(tick mod cycle)/cycle`.
    #[test]
    fn the_wind_vector_reads_the_snapshot_and_the_tick_only() {
        let snapshot = WeatherSnapshot::new(60, 0.0, 1.0, 0.7, 0.1, 19.0, 0.85)
            .expect("valid fixture values");
        let [x, y, z, w] = wind_vector(&snapshot, 240);
        assert_eq!(x, 0.0, "global X is the snapshot's direction X");
        assert_eq!(y, 1.0, "global Y is the snapshot's direction Z");
        assert_eq!(z, 0.7, "global Z is the snapshot's wind strength");
        assert_eq!(w, presentation_phase(60, 240), "global W is presentation");
        assert!((z - snapshot.wind_strength).abs() < f64::EPSILON);
        // The weather-controlled components depend only on the snapshot:
        // changing the cycle changes W and nothing else.
        let [_, _, z_other, w_other] = wind_vector(&snapshot, 120);
        assert_eq!(z_other, z, "strength never depends on the cycle");
        assert_ne!(w_other, w, "the phase does depend on the cycle (presentation)");
    }

    /// W is presentation, derived from the integer tick — never accumulated
    /// time, never stored as weather state. It wraps inside `[0, 2π)`,
    /// repeats every cycle, and two calls with the same inputs agree.
    #[test]
    fn the_motion_phase_is_presentation_from_the_integer_tick() {
        assert_eq!(presentation_phase(0, 240), 0.0);
        let mut seen = std::collections::BTreeSet::new();
        for tick in 0..240 {
            let phase = presentation_phase(tick, 240);
            assert!((0.0..std::f64::consts::TAU).contains(&phase));
            assert_eq!(phase, presentation_phase(tick, 240), "pure function");
            assert_eq!(phase, presentation_phase(tick + 240, 240), "wraps per cycle");
            seen.insert(phase.to_bits());
        }
        assert_eq!(seen.len(), 240, "each tick of the cycle has its own phase");
        assert_eq!(presentation_phase(5, 0), 0.0, "a zero cycle cannot divide");
    }

    /// The displacement adaptation stays inside Grengewald's gentle range:
    /// the fixture strength passes through, anything else is clamped at the
    /// edge rather than rescaled into different units.
    #[test]
    fn the_displacement_stays_in_grengewalds_metre_range() {
        let mut snapshot = WeatherSnapshot::new(0, 1.0, 0.0, 0.0, 0.0, 10.0, 0.5)
            .expect("valid fixture values");
        for strength in [0.0, 0.05, 0.7, 1.0] {
            snapshot.wind_strength = strength;
            assert_eq!(wind_vector(&snapshot, 240)[2], strength);
        }
        snapshot.wind_strength = 2.5;
        assert_eq!(wind_vector(&snapshot, 240)[2], 1.0, "clamped at 1 metre");
        snapshot.wind_strength = -1.0;
        assert_eq!(wind_vector(&snapshot, 240)[2], 0.0, "clamped at neutral");
    }

    /// The snapshot must never become renderer-specific: the weather struct
    /// declares the planned fields and carries no presentation phase.
    #[test]
    fn the_snapshot_carries_no_presentation_phase() {
        let core_source = include_str!("../../remich_core/src/weather.rs");
        let start = core_source
            .find("pub struct WeatherSnapshot")
            .expect("the snapshot struct exists");
        let rest = &core_source[start..];
        let end = rest.find("\n}").expect("the struct body ends");
        let body = &rest[..end];
        for field in [
            "tick:",
            "wind_dir_x:",
            "wind_dir_z:",
            "wind_strength:",
            "rain:",
            "temperature:",
            "light:",
        ] {
            assert!(body.contains(field), "the snapshot must declare '{field}'");
        }
        for forbidden in ["phase", "motion", "shader", "global"] {
            assert!(
                !body.contains(forbidden),
                "the snapshot must not carry presentation state '{forbidden}'"
            );
        }
    }

    /// The live write goes through the engine's real runtime setter with the
    /// pinned name, and the binding deliberately uses **no** global getter —
    /// Grengewald documents getters as editor-only in the compatibility
    /// backend, so the applied vector is read back from the recorded
    /// argument instead.
    #[test]
    fn the_binding_uses_the_real_setter_and_no_getter() {
        let source = include_str!("lib.rs");
        assert!(source.contains("global_shader_parameter_set("));
        assert!(source.contains("global_shader_parameter_set(WIND_GLOBAL_NAME"));
        let getter = ["global_shader_parameter", "_get"].join("");
        assert!(
            !source.contains(&getter),
            "the binding must not call the unusable runtime getter"
        );
        // The mapping helper is a pure function of (tick, cycle): no delta,
        // no wall clock — nothing but the integer tick inside it.
        let start = source
            .find("fn presentation_phase")
            .expect("the presentation helper exists");
        let end = source
            .find("fn wind_vector")
            .expect("the mapping helper follows it");
        let section = &source[start..end];
        assert!(!section.contains("delta"));
        assert!(!section.contains("elapsed"));
        assert!(!section.contains("Instant"));
    }

    /// The Godot layer converts and forwards: it never scores.
    #[test]
    fn the_binding_layer_contains_no_donor_formula() {
        let source = include_str!("lib.rs");
        for donor_fn in [
            "base_urgency",
            "time_block_multiplier",
            "skill_modifier",
            "perception_filter",
            "substrate_weight",
            "coping_modifier",
            "cooperation_modifier",
            "compute_utility_score",
        ] {
            // Assembled at runtime so this list does not trip its own check.
            let defined = format!("fn {donor_fn}");
            assert!(
                !source.contains(&defined),
                "the binding crate must not contain '{defined}'"
            );
        }
    }
}
