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
