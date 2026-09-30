//! The engine-free scorer adapter (Phase 1, Step 4).
//!
//! This crate sits between plain bridge data and the Step 3 donor import
//! (docs/PLAN.md §1.2). Its job is deliberately narrow:
//!
//! * take plain inputs — a seed, seven need-satisfaction values, a time of day,
//!   and the activities that are available now with the place each happens at;
//! * resolve every activity id against the donor catalogue
//!   ([`anvil_sim::actions::catalogue`]);
//! * call the donor scoring function
//!   [`anvil_sim::utility::scoring::compute_utility_score`] once per activity —
//!   never a re-implementation of it;
//! * select with the donor's own rule: the highest score, strict `>`, so equal
//!   scores are resolved by input order and never by a random tie-break.
//!
//! The seed does **not** enter the choice policy. It enters as donor-defined
//! deterministic actor state: [`anvil_sim::soul::LayeredSoul::from_seed`] builds
//! the substrate (courage, generosity, stability) and the emotional state that
//! the donor's `substrate_weight` and `perception_filter` read inside
//! `compute_utility_score`. Two seeds therefore give two different actors with
//! two different — but each fully reproducible — score vectors.
//!
//! The place a caller attaches to an activity is Remich's own bridge metadata.
//! The donor formula has no place term, so a place can never change a score; it
//! is carried through to the result untouched so the caller learns *where* the
//! chosen activity is to happen.
//!
//! Donor provenance for everything called from here is recorded in
//! `docs/anvil-import-phase1-step3.md`.

use anvil_sim::actions::catalogue;
use anvil_sim::needs::Need;
use anvil_sim::settlement::Skill;
use anvil_sim::soul::LayeredSoul;
use anvil_sim::utility::scoring::compute_utility_score;
use std::fmt;

/// How many need-satisfaction values an input carries: the donor's seven needs.
pub const NEED_COUNT: usize = 7;

/// The donor's need order, which is the order the plain input array uses.
///
/// The authority is the donor's own declaration: `Need`'s variants, in this
/// order, in `crates/anvil_sim/src/needs.rs` — a file imported at Step 3 and
/// byte-verified there. The donor's `NpcSystem` walks them in exactly this
/// order too (`buggy-vault@24181142
/// repos/anvil/source/crates/anvil_sim/src/system/npc/kimi_npc_mod.rs`,
/// `all_needs` / `need_index`), but that system file is *not* taken, so nothing
/// here is copied from it. The donor exposes no index and no iterator for
/// `Need`, which is why the order is written out once; a test pins the seven
/// `Display` names in this exact order against the imported enum.
pub const NEED_ORDER: [Need; NEED_COUNT] = [
    Need::Food,
    Need::Water,
    Need::Shelter,
    Need::Safety,
    Need::Sleep,
    Need::Companionship,
    Need::Joy,
];

/// The donor's seed-derived actor state.
///
/// This is the whole seed path: the caller's seed becomes the donor's own
/// deterministic soul, which the donor's scoring formula then reads. Nothing
/// else in the adapter is seeded, and no random choice is ever made.
pub fn actor_soul(seed: u64) -> LayeredSoul {
    LayeredSoul::from_seed(seed)
}

/// Which slot of the plain seven-value input holds this need.
///
/// Deliberately named for *this* adapter's array, not for the donor's system
/// helper of the same idea: `kimi_npc_mod.rs` was never taken, and no symbol
/// here may be mistaken for one of its functions. Returns `None` only if the
/// donor ever grows an eighth need that [`NEED_ORDER`] does not name yet — a
/// clear failure rather than a wrong slot.
fn need_slot(need: Need) -> Option<usize> {
    NEED_ORDER.iter().position(|candidate| *candidate == need)
}

/// The satisfaction value for one need inside a plain seven-value input.
pub fn satisfaction_for(needs: &[f32; NEED_COUNT], need: Need) -> Option<f32> {
    need_slot(need).map(|index| needs[index])
}

/// Resolves a plain skill name to the donor's `Skill`.
///
/// Plain data crosses the boundary; the donor enum lives inside it. The names
/// are the donor's own `Display` spellings (`farmer`, `builder`, `musician`,
/// `storyteller`, `healer`), so nothing is invented here either.
pub fn skill_from_name(name: &str) -> Option<Skill> {
    match name {
        "musician" => Some(Skill::Musician),
        "storyteller" => Some(Skill::Storyteller),
        "builder" => Some(Skill::Builder),
        "healer" => Some(Skill::Healer),
        "farmer" => Some(Skill::Farmer),
        _ => None,
    }
}

/// Resolves a plain list of skill names, failing clearly on the first unknown.
pub fn skills_from_names<I, S>(names: I) -> Result<Vec<Skill>, ScorerError>
where
    I: IntoIterator<Item = S>,
    S: AsRef<str>,
{
    let mut skills = Vec::new();
    for name in names {
        let name = name.as_ref();
        match skill_from_name(name) {
            Some(skill) => skills.push(skill),
            None => return Err(ScorerError::UnknownSkill(name.to_string())),
        }
    }
    Ok(skills)
}

/// One activity the caller says is available now, with where it happens.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct AvailableActivity {
    /// Donor action id; resolved against `anvil_sim::actions::catalogue`.
    pub id: u64,
    /// Bridge metadata: the place this activity happens at. Never scored.
    pub place: String,
}

impl AvailableActivity {
    /// An available activity at a place.
    pub fn new(id: u64, place: impl Into<String>) -> Self {
        Self {
            id,
            place: place.into(),
        }
    }
}

/// One scored activity, in input order.
#[derive(Debug, Clone, PartialEq)]
pub struct ScoredCandidate {
    /// Donor action id.
    pub id: u64,
    /// The donor catalogue's name for that id.
    pub name: String,
    /// The place carried through untouched from the input.
    pub place: String,
    /// The donor score, exactly as `compute_utility_score` returned it.
    pub score: f32,
}

/// Everything a caller asked for, returned as plain data.
#[derive(Debug, Clone, PartialEq)]
pub struct ScorerOutcome {
    /// The chosen activity's donor action id.
    pub chosen_id: u64,
    /// The chosen activity's catalogue name.
    pub chosen_name: String,
    /// The place the chosen activity happens at.
    pub chosen_place: String,
    /// The chosen activity's score.
    pub chosen_score: f32,
    /// Every candidate that was scored, in input order, including the choice.
    pub candidates: Vec<ScoredCandidate>,
}

/// A complete plain scoring request.
///
/// Three inputs the donor formula accepts are not in the plan's minimum
/// listing, so they are explicit fields with documented neutral defaults (see
/// [`ScorerInput::new`]): never inferred, never global, always visible in the
/// caller and in the test.
#[derive(Debug, Clone, PartialEq)]
pub struct ScorerInput {
    /// The seed; it becomes the donor's seeded actor state and nothing else.
    pub seed: u64,
    /// The actor's seven need-satisfaction values, in [`NEED_ORDER`].
    pub needs: [f32; NEED_COUNT],
    /// Time of day in the donor's `[0.0, 1.0]` day cycle.
    pub time_of_day: f32,
    /// The activities available now, each with its place.
    pub activities: Vec<AvailableActivity>,
    /// The actor's skills. Default: none.
    pub skills: Vec<Skill>,
    /// Settlement damage in `[0.0, 1.0]`. Default: `0.0`.
    pub settlement_damage: f32,
    /// Settlement aggregate mood in `[-1.0, 1.0]`. Default: `0.0`.
    pub settlement_aggregate_mood: f32,
}

impl ScorerInput {
    /// A request with the three documented neutral defaults.
    ///
    /// * `skills` empty — the donor's `skill_modifier` returns `1.0` for every
    ///   action, so skills change nothing until a caller supplies them;
    /// * `settlement_damage` `0.0` — the donor's `coping_modifier` returns
    ///   `0.5` for every action while there is no damage;
    /// * `settlement_aggregate_mood` `0.0` — the donor's
    ///   `cooperation_modifier` returns `1.0` for every action inside the
    ///   neutral band `[-0.3, 0.3]`.
    ///
    /// All three are constant across the candidates, so the defaults cannot
    /// tilt the ranking. They are placeholders for explicit caller input, not
    /// final Munshausen behaviour.
    pub fn new(
        seed: u64,
        needs: [f32; NEED_COUNT],
        time_of_day: f32,
        activities: Vec<AvailableActivity>,
    ) -> Self {
        Self {
            seed,
            needs,
            time_of_day,
            activities,
            skills: Vec::new(),
            settlement_damage: 0.0,
            settlement_aggregate_mood: 0.0,
        }
    }

    /// Replaces the skill list.
    pub fn with_skills(mut self, skills: Vec<Skill>) -> Self {
        self.skills = skills;
        self
    }

    /// Replaces the two settlement inputs.
    pub fn with_settlement(mut self, damage: f32, aggregate_mood: f32) -> Self {
        self.settlement_damage = damage;
        self.settlement_aggregate_mood = aggregate_mood;
        self
    }
}

/// Everything that can make a request refuse to run.
///
/// Refusing is the point: a malformed request or an id that is not in the
/// donor catalogue fails loudly instead of silently scoring something else.
#[derive(Debug, Clone, PartialEq)]
pub enum ScorerError {
    /// No activity was supplied, so there is nothing to choose.
    NoActivities,
    /// An activity id is not in the donor action catalogue.
    UnknownActionId(u64),
    /// The plain need array had the wrong length.
    NeedCount {
        /// How many values arrived.
        got: usize,
    },
    /// A need value was not a finite number in `[0.0, 1.0]`.
    NeedOutOfRange {
        /// Which slot.
        index: usize,
        /// What arrived.
        value: f32,
    },
    /// The time of day was not a finite number in `[0.0, 1.0]`.
    InvalidTimeOfDay(f32),
    /// Settlement damage was not a finite number in `[0.0, 1.0]`.
    InvalidSettlementDamage(f32),
    /// Settlement aggregate mood was not a finite number in `[-1.0, 1.0]`.
    InvalidSettlementMood(f32),
    /// A catalogue action serves a need this adapter does not index.
    UnindexableNeed {
        /// The action whose primary need is unknown to [`NEED_ORDER`].
        action_id: u64,
        /// The need's donor name.
        need: String,
    },
    /// A plain skill name is not a donor skill.
    UnknownSkill(String),
    /// The requested tick range runs backwards.
    TickOrder {
        /// The tick time starts at.
        from_tick: u64,
        /// The tick time was asked to go to.
        to_tick: u64,
    },
}

impl fmt::Display for ScorerError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Self::NoActivities => write!(f, "no activities were supplied to choose from"),
            Self::UnknownActionId(id) => {
                write!(f, "action id {id} is not in the donor action catalogue")
            }
            Self::NeedCount { got } => write!(
                f,
                "expected {NEED_COUNT} need-satisfaction values, got {got}"
            ),
            Self::NeedOutOfRange { index, value } => write!(
                f,
                "need value at index {index} is {value}, expected a finite value in [0.0, 1.0]"
            ),
            Self::InvalidTimeOfDay(value) => write!(
                f,
                "time of day is {value}, expected a finite value in [0.0, 1.0]"
            ),
            Self::InvalidSettlementDamage(value) => write!(
                f,
                "settlement damage is {value}, expected a finite value in [0.0, 1.0]"
            ),
            Self::InvalidSettlementMood(value) => write!(
                f,
                "settlement aggregate mood is {value}, expected a finite value in [-1.0, 1.0]"
            ),
            Self::UnindexableNeed { action_id, need } => write!(
                f,
                "action {action_id} serves the need '{need}', which NEED_ORDER does not index"
            ),
            Self::UnknownSkill(name) => {
                write!(f, "'{name}' is not a donor skill name")
            }
            Self::TickOrder { from_tick, to_tick } => write!(
                f,
                "cannot advance time backwards: from_tick {from_tick} is after to_tick {to_tick}"
            ),
        }
    }
}

impl std::error::Error for ScorerError {}

/// Checks seven need-satisfaction values: finite and inside `[0.0, 1.0]`.
pub fn validate_needs(needs: &[f32; NEED_COUNT]) -> Result<(), ScorerError> {
    for (index, value) in needs.iter().enumerate() {
        if !value.is_finite() || !(0.0..=1.0).contains(value) {
            return Err(ScorerError::NeedOutOfRange {
                index,
                value: *value,
            });
        }
    }
    Ok(())
}

/// Checks a whole request before any of it is used.
///
/// Every activity id is resolved here, up front, so an unknown id is reported
/// as itself rather than disappearing behind a later rule.
pub fn validate(input: &ScorerInput) -> Result<(), ScorerError> {
    validate_needs(&input.needs)?;

    if !input.time_of_day.is_finite() || !(0.0..=1.0).contains(&input.time_of_day) {
        return Err(ScorerError::InvalidTimeOfDay(input.time_of_day));
    }

    if !input.settlement_damage.is_finite() || !(0.0..=1.0).contains(&input.settlement_damage) {
        return Err(ScorerError::InvalidSettlementDamage(input.settlement_damage));
    }

    if !input.settlement_aggregate_mood.is_finite()
        || !(-1.0..=1.0).contains(&input.settlement_aggregate_mood)
    {
        return Err(ScorerError::InvalidSettlementMood(
            input.settlement_aggregate_mood,
        ));
    }

    if input.activities.is_empty() {
        return Err(ScorerError::NoActivities);
    }

    for activity in &input.activities {
        if catalogue::action_by_id(activity.id).is_none() {
            return Err(ScorerError::UnknownActionId(activity.id));
        }
    }

    Ok(())
}

/// Scores every available activity with the donor formula and picks one.
///
/// Selection is the donor's established rule, preserved literally: the highest
/// score wins, the comparison is strict `score > best_score`, and candidates
/// are visited in input order — so equal scores leave the first one in front
/// and no random tie-break exists. The donor's own "Joy is never directly
/// chosen to satisfy a need" rule is kept as well.
pub fn score(input: &ScorerInput) -> Result<ScorerOutcome, ScorerError> {
    validate(input)?;

    let soul = actor_soul(input.seed);

    let mut candidates: Vec<ScoredCandidate> = Vec::with_capacity(input.activities.len());

    for activity in &input.activities {
        // validate() already proved every id resolves.
        let action = catalogue::action_by_id(activity.id)
            .ok_or(ScorerError::UnknownActionId(activity.id))?;

        // Donor rule: Joy cannot be directly satisfied, so it is never chosen
        // to satisfy a need (anvil's evaluation skips that need outright).
        if !action.primary_need.can_be_satisfied() {
            continue;
        }

        let need = action.primary_need;
        let index = need_slot(need).ok_or_else(|| ScorerError::UnindexableNeed {
            action_id: action.id,
            need: need.to_string(),
        })?;

        let value = compute_utility_score(
            input.needs[index],
            &action,
            need,
            &input.skills,
            &soul.emotional_state,
            &soul.substrate,
            input.time_of_day,
            input.settlement_damage,
            input.settlement_aggregate_mood,
        );

        candidates.push(ScoredCandidate {
            id: action.id,
            name: action.name.clone(),
            place: activity.place.clone(),
            score: value,
        });
    }

    if candidates.is_empty() {
        return Err(ScorerError::NoActivities);
    }

    // The donor's selection: strict `>`, input order for equal scores.
    let mut best_index = 0usize;
    let mut best_score = f32::MIN;
    for (index, candidate) in candidates.iter().enumerate() {
        if candidate.score > best_score {
            best_score = candidate.score;
            best_index = index;
        }
    }

    let chosen = &candidates[best_index];
    Ok(ScorerOutcome {
        chosen_id: chosen.id,
        chosen_name: chosen.name.clone(),
        chosen_place: chosen.place.clone(),
        chosen_score: chosen.score,
        candidates,
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    /// A small fixed request used by the ordinary adapter tests. The
    /// seed-sensitive fixture lives in `tests/seed_sensitive_fixture.rs`.
    fn request(seed: u64) -> ScorerInput {
        ScorerInput::new(
            seed,
            [0.40, 0.35, 0.60, 0.50, 0.45, 0.42, 0.55],
            0.27,
            vec![
                AvailableActivity::new(2, "north-hills"),
                AvailableActivity::new(1, "east-field"),
                AvailableActivity::new(16, "market-square"),
            ],
        )
    }

    #[test]
    fn need_order_is_the_donor_order() {
        let names: Vec<String> = NEED_ORDER.iter().map(|need| need.to_string()).collect();
        assert_eq!(
            names,
            [
                "food",
                "water",
                "shelter",
                "safety",
                "sleep",
                "companionship",
                "joy"
            ]
        );
    }

    #[test]
    fn satisfaction_reads_the_right_slot() {
        let needs = [0.1, 0.2, 0.3, 0.4, 0.5, 0.6, 0.7];
        assert_eq!(satisfaction_for(&needs, Need::Food), Some(0.1));
        assert_eq!(satisfaction_for(&needs, Need::Water), Some(0.2));
        assert_eq!(satisfaction_for(&needs, Need::Safety), Some(0.4));
        assert_eq!(satisfaction_for(&needs, Need::Joy), Some(0.7));
    }

    #[test]
    fn the_donor_catalogue_carries_no_joy_serving_action() {
        // So the donor's Joy skip below can never silently drop a supplied
        // activity today: nothing in the catalogue serves Joy.
        let joy_ids: Vec<u64> = catalogue::actions()
            .iter()
            .filter(|action| !action.primary_need.can_be_satisfied())
            .map(|action| action.id)
            .collect();
        assert!(joy_ids.is_empty(), "unexpected Joy actions: {joy_ids:?}");
    }

    #[test]
    fn scores_every_candidate_with_a_name_and_a_place() {
        let outcome = score(&request(424242)).expect("valid request");

        assert_eq!(
            outcome
                .candidates
                .iter()
                .map(|candidate| candidate.id)
                .collect::<Vec<_>>(),
            vec![2, 1, 16],
            "candidates come back in input order"
        );
        assert_eq!(outcome.candidates[0].name, "Hunt");
        assert_eq!(outcome.candidates[0].place, "north-hills");
        assert_eq!(outcome.candidates[1].place, "east-field");
        assert_eq!(outcome.candidates[2].place, "market-square");

        assert!(
            outcome
                .candidates
                .iter()
                .any(|candidate| candidate.id == outcome.chosen_id),
            "the choice is one of the candidates"
        );
        // The choice is reported consistently with its own candidate entry.
        let chosen = outcome
            .candidates
            .iter()
            .find(|candidate| candidate.id == outcome.chosen_id)
            .expect("chosen id has a candidate entry");
        assert_eq!(outcome.chosen_name, chosen.name);
        assert_eq!(outcome.chosen_place, chosen.place);
        assert_eq!(outcome.chosen_score.to_bits(), chosen.score.to_bits());
        assert!(outcome.chosen_score.is_finite());
    }

    #[test]
    fn the_place_never_touches_the_score() {
        let placed = request(424242);
        let mut renamed = request(424242);
        for (index, activity) in renamed.activities.iter_mut().enumerate() {
            activity.place = format!("elsewhere-{index}");
        }

        let a = score(&placed).expect("valid request");
        let b = score(&renamed).expect("valid request");

        assert_eq!(a.chosen_id, b.chosen_id);
        assert_eq!(a.chosen_score.to_bits(), b.chosen_score.to_bits());
        assert_eq!(
            a.candidates
                .iter()
                .map(|candidate| candidate.score.to_bits())
                .collect::<Vec<_>>(),
            b.candidates
                .iter()
                .map(|candidate| candidate.score.to_bits())
                .collect::<Vec<_>>()
        );
        // ...while the metadata still crosses.
        assert_ne!(a.candidates[0].place, b.candidates[0].place);
    }

    #[test]
    fn equal_scores_keep_the_first_candidate_in_front() {
        // Two entries for the same action at two places: identical scores, and
        // input order decides — strictly, without a tie-break.
        let input = ScorerInput::new(
            7,
            [0.40, 0.35, 0.60, 0.50, 0.45, 0.42, 0.55],
            0.27,
            vec![
                AvailableActivity::new(9, "shed"),
                AvailableActivity::new(9, "barn"),
            ],
        );
        let outcome = score(&input).expect("valid request");
        assert_eq!(outcome.chosen_id, 9);
        assert_eq!(outcome.chosen_place, "shed");
        assert_eq!(outcome.candidates[0].score, outcome.candidates[1].score);
    }

    #[test]
    fn an_unknown_action_id_fails_and_scores_nothing() {
        let mut input = request(424242);
        input.activities.push(AvailableActivity::new(9_999, "nowhere"));
        assert_eq!(
            score(&input),
            Err(ScorerError::UnknownActionId(9_999))
        );
    }

    #[test]
    fn malformed_inputs_fail_clearly() {
        let mut empty = request(1);
        empty.activities.clear();
        assert_eq!(score(&empty), Err(ScorerError::NoActivities));

        let mut needs = request(1);
        needs.needs[3] = 1.5;
        assert_eq!(
            score(&needs),
            Err(ScorerError::NeedOutOfRange {
                index: 3,
                value: 1.5
            })
        );

        let mut nan = request(1);
        nan.needs[0] = f32::NAN;
        match score(&nan) {
            Err(ScorerError::NeedOutOfRange { index, value }) => {
                assert_eq!(index, 0);
                assert!(value.is_nan(), "the offending value is reported back");
            }
            other => panic!("expected NeedOutOfRange, got {other:?}"),
        }

        let mut tod = request(1);
        tod.time_of_day = -0.1;
        assert_eq!(score(&tod), Err(ScorerError::InvalidTimeOfDay(-0.1)));

        let mut damage = request(1);
        damage.settlement_damage = 2.0;
        assert_eq!(score(&damage), Err(ScorerError::InvalidSettlementDamage(2.0)));

        let mut mood = request(1);
        mood.settlement_aggregate_mood = -1.5;
        assert_eq!(
            score(&mood),
            Err(ScorerError::InvalidSettlementMood(-1.5))
        );
    }

    #[test]
    fn skill_names_round_trip_and_an_unknown_name_fails() {
        for name in ["musician", "storyteller", "builder", "healer", "farmer"] {
            let skill = skill_from_name(name).expect("known skill name");
            assert_eq!(skill.to_string(), name);
        }
        assert_eq!(skill_from_name("carpenter"), None);
        assert_eq!(
            skills_from_names(["farmer", "carpenter"]),
            Err(ScorerError::UnknownSkill("carpenter".to_string()))
        );
    }

    #[test]
    fn the_neutral_defaults_hold_for_every_candidate() {
        // The three inputs the plan does not supply are visible here, and each
        // is constant across candidates: no default can tilt the ranking.
        let input = request(424242);
        assert!(input.skills.is_empty());
        assert_eq!(input.settlement_damage, 0.0);
        assert_eq!(input.settlement_aggregate_mood, 0.0);

        let with_settlement = input.clone().with_settlement(0.0, 0.0);
        let base = score(&input).expect("valid request");
        let same = score(&with_settlement).expect("valid request");
        assert_eq!(base.candidates, same.candidates);
    }
}
