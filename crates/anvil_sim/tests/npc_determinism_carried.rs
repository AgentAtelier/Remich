//! Carried donor tests — verbatim excerpts from
//! `buggy-vault@24181142 repos/anvil/source/crates/anvil_sim/tests/npc_determinism.rs`
//! (original lines 161-218, byte-identical).
//!
//! That donor file has four tests. The two below exercise code Step 3 takes
//! (`soul::LayeredSoul`, and `utility::scoring::compute_utility_score` with
//! `actions::catalogue`) and run as they stand. The other two —
//! `test_npc_system_deterministic_action_selection` and
//! `test_npc_system_deterministic_need_decay` — require `NpcSystem`,
//! `WorldRuntime` and `anvil_world`, which this step does not take; see
//! `docs/anvil-import-phase1-step3.md` for the exact dependency diagnosis.

use anvil_sim::soul::LayeredSoul;

#[test]
fn test_layered_soul_deterministic_generation() {
    // Create two identical souls with the same seed
    let soul1 = LayeredSoul::from_seed(42);
    let soul2 = LayeredSoul::from_seed(42);

    assert_eq!(soul1.substrate.courage_fear, soul2.substrate.courage_fear);
    assert_eq!(soul1.substrate.generosity_selfishness, soul2.substrate.generosity_selfishness);
    assert_eq!(soul1.substrate.stability_anxiety, soul2.substrate.stability_anxiety);
}

#[test]
fn test_utility_scoring_deterministic() {
    use anvil_sim::{
        actions::catalogue,
        needs::Need,
        soul::{EmotionalState, Substrate},
        utility::scoring::compute_utility_score,
    };

    // Create identical parameters
    let need_satisfaction = 0.5f32;
    let action = catalogue::action_by_id(1).unwrap(); // Farm/Tend
    let need = Need::Food;
    let skills: Vec<anvil_sim::settlement::skill::Skill> = vec![];
    let emotional_state = EmotionalState::from_mood(0.0);
    let substrate = Substrate::neutral();
    let time_of_day = 0.25f32; // Dawn
    let settlement_damage = 0.0f32;
    let settlement_aggregate_mood = 0.5f32;

    // Compute score twice with identical parameters
    let score1 = compute_utility_score(
        need_satisfaction,
        &action,
        need,
        &skills,
        &emotional_state,
        &substrate,
        time_of_day,
        settlement_damage,
        settlement_aggregate_mood,
    );

    let score2 = compute_utility_score(
        need_satisfaction,
        &action,
        need,
        &skills,
        &emotional_state,
        &substrate,
        time_of_day,
        settlement_damage,
        settlement_aggregate_mood,
    );

    assert_eq!(score1, score2, "Utility score should be deterministic");
}
