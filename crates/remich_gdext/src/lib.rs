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

use godot::prelude::*;

use remich_core::clock::WorldClock;
use remich_core::decay::advance_needs;
use remich_core::scorer::{self, ScorerInput, ScorerOutcome};

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
// Plain-data conversion. This is the whole of this layer's work: no scoring,
// no defaults beyond the three documented above, no inference.
// ---------------------------------------------------------------------------

/// Reads a required field, naming it when it is missing.
fn field(input: &VarDictionary, key: &str) -> Result<Variant, String> {
    input
        .get(key)
        .ok_or_else(|| format!("missing required field '{key}'"))
}

/// Reads a number; an integer is accepted where a number is wanted.
fn plain_number(value: &Variant, what: &str) -> Result<f64, String> {
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
fn plain_integer(value: &Variant, what: &str) -> Result<u64, String> {
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
fn plain_text(value: &Variant, what: &str) -> Result<String, String> {
    value
        .try_to::<GString>()
        .map(|text| text.to_string())
        .map_err(|_| format!("{what} must be a string, got {:?}", value.get_type()))
}

/// Reads the seven need values out of a plain array.
fn plain_needs(values: &VarArray) -> Result<[f32; scorer::NEED_COUNT], String> {
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
fn need_array(needs: &[f32; scorer::NEED_COUNT]) -> VarArray {
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
