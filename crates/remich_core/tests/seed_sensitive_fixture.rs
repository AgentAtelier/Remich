//! Phase 1, Step 4 — the fixed seed-sensitive fixture (docs/PLAN.md §4).
//!
//! The step requires determinism to be *proved*, and requires the proof to
//! fail if the seed were quietly ignored. This file is that proof. It commits
//! the inputs and the two seeds outright — it never searches for a case that
//! happens to pass.
//!
//! The fixture:
//!
//! * seed **60628** chooses `1 Farm/Tend` at `east-field`;
//! * seed **87004** chooses `2 Hunt` at `north-hills`;
//! * everything else in the request — seven needs, time of day, the six
//!   available activities and their places, the neutral settlement inputs — is
//!   identical between the two runs.
//!
//! So the difference can only come from the seed, and the seed only ever enters
//! as donor-defined state: `anvil_sim::soul::LayeredSoul::from_seed`, whose
//! substrate and emotional state the donor's `compute_utility_score` reads.
//! There is no tie here to break either — `Farm/Tend` beats `Hunt` by 51% for
//! the first seed and `Hunt` beats `Farm/Tend` by 35% for the second — so no
//! random tie-break, no seed noise and no tuned formula could be hiding.
//!
//! `godot/scorer_probe.gd` runs exactly this fixture across the real
//! GDExtension and checks the same recorded results there.

use remich_core::scorer::{score, AvailableActivity, ScorerInput, ScoredCandidate};

/// The seed that chooses `Farm/Tend`.
const SEED_A: u64 = 60_628;
/// The seed that chooses `Hunt`.
const SEED_B: u64 = 87_004;

/// The actor's seven need-satisfaction values, donor order
/// (`food, water, shelter, safety, sleep, companionship, joy`).
const NEEDS: [f32; 7] = [0.40, 0.35, 0.60, 0.50, 0.45, 0.42, 0.55];

/// Dawn — the window in which `Farm/Tend`, `Hunt` and `Lookout/Observe` are in
/// their preferred time block.
const TIME_OF_DAY: f32 = 0.27;

/// The activities available now, each with the place it happens at.
///
/// The place is bridge metadata: swapping it never changes a score (see
/// `remich_core::scorer`'s own tests).
fn activities() -> Vec<AvailableActivity> {
    vec![
        AvailableActivity::new(2, "north-hills"),
        AvailableActivity::new(1, "east-field"),
        AvailableActivity::new(16, "market-square"),
        AvailableActivity::new(14, "cottage-loft"),
        AvailableActivity::new(12, "ridge"),
        AvailableActivity::new(5, "kitchen"),
    ]
}

/// The committed fixture for one seed.
fn fixture(seed: u64) -> ScorerInput {
    ScorerInput::new(seed, NEEDS, TIME_OF_DAY, activities())
}

/// The recorded result for seed 60628: (chosen id, chosen place, candidate
/// (id, score) pairs in input order).
fn recorded_a() -> (u64, &'static str, [(u64, f32); 6]) {
    (
        1,
        "east-field",
        [
            (2, 0.011_674_161),
            (1, 0.023_807_716),
            (16, 0.002_769_275_3),
            (14, 0.004_213_220_4),
            (12, 0.0),
            (5, 0.004_761_543),
        ],
    )
}

/// The recorded result for seed 87004, in the same shape.
fn recorded_b() -> (u64, &'static str, [(u64, f32); 6]) {
    (
        2,
        "north-hills",
        [
            (2, 0.056_183_21),
            (1, 0.036_763_236),
            (16, 0.004_321_844),
            (14, 0.006_532_007),
            (12, 0.0),
            (5, 0.007_352_647_4),
        ],
    )
}

fn assert_matches_recording(
    outcome: &remich_core::scorer::ScorerOutcome,
    expected: (u64, &'static str, [(u64, f32); 6]),
) {
    assert_eq!(outcome.chosen_id, expected.0, "chosen action id");
    assert_eq!(outcome.chosen_place, expected.1, "chosen place");
    assert_eq!(outcome.candidates.len(), expected.2.len(), "candidate count");

    for (index, (candidate, (id, score))) in outcome
        .candidates
        .iter()
        .zip(expected.2.iter())
        .enumerate()
    {
        assert_eq!(candidate.id, *id, "candidate {index} id");
        assert_eq!(
            candidate.score.to_bits(),
            score.to_bits(),
            "candidate {index} score is bit-identical to the recorded value"
        );
    }
}

fn scores(outcome: &remich_core::scorer::ScorerOutcome) -> Vec<u32> {
    outcome
        .candidates
        .iter()
        .map(|candidate: &ScoredCandidate| candidate.score.to_bits())
        .collect()
}

#[test]
fn same_input_and_same_seed_give_exactly_the_same_result() {
    let first = score(&fixture(SEED_A)).expect("the fixture is valid");
    let second = score(&fixture(SEED_A)).expect("the fixture is valid");

    assert_eq!(first.chosen_id, second.chosen_id, "same chosen action");
    assert_eq!(
        first.chosen_score.to_bits(),
        second.chosen_score.to_bits(),
        "same chosen score, bit for bit"
    );
    assert_eq!(
        scores(&first),
        scores(&second),
        "same candidate scores in the same order"
    );
    assert_eq!(
        first.candidates
            .iter()
            .map(|candidate| candidate.id)
            .collect::<Vec<_>>(),
        second
            .candidates
            .iter()
            .map(|candidate| candidate.id)
            .collect::<Vec<_>>(),
        "same candidate order"
    );
}

#[test]
fn the_fixture_produces_its_recorded_result() {
    let for_a = score(&fixture(SEED_A)).expect("the fixture is valid");
    assert_matches_recording(&for_a, recorded_a());
    assert_eq!(for_a.chosen_name, "Farm/Tend");
    assert_eq!(for_a.chosen_place, "east-field");

    let for_b = score(&fixture(SEED_B)).expect("the fixture is valid");
    assert_matches_recording(&for_b, recorded_b());
    assert_eq!(for_b.chosen_name, "Hunt");
    assert_eq!(for_b.chosen_place, "north-hills");
}

/// **The seed-sensitivity test.** The two runs differ in one thing only — the
/// seed — and they must choose differently.
///
/// This is the assertion that fails if the implementation ever ignores the
/// supplied seed and substitutes a constant: both runs would then produce the
/// identical score vector below, and `assert_ne!` would fire.
#[test]
fn seed_is_not_ignored_two_fixed_seeds_choose_differently() {
    let for_a = score(&fixture(SEED_A)).expect("the fixture is valid");
    let for_b = score(&fixture(SEED_B)).expect("the fixture is valid");

    assert_ne!(
        for_a.chosen_id, for_b.chosen_id,
        "the seed must reach the donor scorer: seed {SEED_A} chooses {} and seed \
         {SEED_B} chooses {}, so a constant seed would break this fixture",
        for_a.chosen_name, for_b.chosen_name
    );

    // Not just the choice: the whole score vector moves with the donor's
    // seed-derived soul, so no hidden constant can reproduce it either.
    assert_ne!(
        scores(&for_a),
        scores(&for_b),
        "every score must differ once only the seed differs"
    );

    // And the choice is not a coin flip: each winner is comfortably clear of
    // the runner-up, so a random tie-break could not be doing this work.
    let winner_a = for_a
        .candidates
        .iter()
        .filter(|candidate| candidate.id == for_a.chosen_id)
        .next()
        .expect("chosen candidate present");
    let runner_up_a = for_a
        .candidates
        .iter()
        .filter(|candidate| candidate.id != for_a.chosen_id)
        .map(|candidate| candidate.score)
        .fold(0.0f32, f32::max);
    assert!(
        winner_a.score > runner_up_a * 1.2,
        "seed {SEED_A} must win clearly, not by a tie: {} vs {}",
        winner_a.score,
        runner_up_a
    );
}

/// The seed is read through the donor's own seeded state, and that state is
/// what differs — the adapter adds nothing of its own on top of it.
#[test]
fn the_two_seeds_produce_different_donor_souls() {
    let soul_a = remich_core::scorer::actor_soul(SEED_A);
    let soul_b = remich_core::scorer::actor_soul(SEED_B);

    assert_ne!(
        soul_a.substrate.courage_fear.to_bits(),
        soul_b.substrate.courage_fear.to_bits(),
        "donor substrate differs between the seeds"
    );
    assert_ne!(
        soul_a.substrate.generosity_selfishness.to_bits(),
        soul_b.substrate.generosity_selfishness.to_bits(),
        "donor generosity differs between the seeds"
    );
    assert_ne!(
        soul_a.emotional_state, soul_b.emotional_state,
        "donor emotional state differs between the seeds"
    );

    // Rebuilding from the same seed rebuilds the same state, every time.
    assert_eq!(soul_a, remich_core::scorer::actor_soul(SEED_A));
}
