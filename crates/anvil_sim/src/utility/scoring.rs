//! Utility scoring implementation for NPC action selection.
//!
//! Implements the scoring formula from GAME_DESIGN_SECTION_4.md Section 4.4.3:
//!
//! ```text
//! score = base_urgency(need)
//!       × time_block_multiplier(action, current_time)
//!       × skill_modifier(npc, action)
//!       × perception_filter(npc.mood, need)
//!       × substrate_weight(npc.substrate, action)
//!       × coping_modifier(settlement.damage, action.coping_type)
//!       × cooperation_modifier(settlement.aggregate_mood, action.communal_benefit)
//! ```

use crate::actions::{Action, CopingType};
use crate::needs::Need;
use crate::soul::{EmotionalState, Substrate};
use anvil_core::ValidationErrors;

/// A computed utility score for an action.
#[derive(Debug, Clone, Copy, PartialEq)]
pub struct UtilityScore {
    /// The raw computed score value.
    pub value: f32,
    /// The action ID this score is for.
    pub action_id: u64,
}

impl UtilityScore {
    /// Creates a new utility score.
    pub fn new(action_id: u64, value: f32) -> Self {
        Self { action_id, value }
    }
}

/// Computes the base urgency for a need.
///
/// urgency = 1.0 - need_satisfaction, scaled by decay rate.
///
/// A need that is completely unsatisfied (0.0) has maximum urgency (1.0).
/// A need that is fully satisfied (1.0) has minimum urgency (0.0).
///
/// The decay rate determines how quickly the need becomes urgent when unsatisfied.
///
/// Defined in GAME_DESIGN_SECTION_4.md Section 4.4.3.
pub fn base_urgency(need: Need, need_satisfaction: f32) -> f32 {
    // Clamp satisfaction to [0.0, 1.0]
    let clamped = need_satisfaction.clamp(0.0, 1.0);
    // Urgency is 1.0 - satisfaction
    let urgency = 1.0 - clamped;
    // Scale by decay rate (faster-decaying needs are more urgent)
    urgency * need.decay_rate() * 1000.0 // Scale to make values meaningful
}

/// Computes the time block multiplier for an action at a given time of day.
///
/// Uses the action's time_preference and the current time to determine
/// whether this is a good time for the action.
///
/// Defined in GAME_DESIGN_SECTION_4.md Section 4.3.1.
pub fn time_block_multiplier(action: &Action, time_of_day: f32) -> f32 {
    action.time_preference.multiplier(time_of_day)
}

/// Computes the skill modifier based on NPC skills and action requirements.
///
/// For Sprint 17, this is a simple multiplier based on whether the NPC
/// has skills relevant to the action's primary need.
///
/// Future: This will be expanded to use skill levels and action-specific
/// skill requirements.
pub fn skill_modifier(npc_skills: &[crate::settlement::skill::Skill], action: &Action) -> f32 {
    // For now, check if the NPC has any skill that matches the action's primary need
    // This is a simplified implementation

    // Map needs to relevant skills
    let relevant_skills: Vec<crate::settlement::skill::Skill> = match action.primary_need {
        Need::Food => vec![crate::settlement::skill::Skill::Farmer],
        Need::Water => vec![], // No specific skill for water yet
        Need::Shelter => vec![crate::settlement::skill::Skill::Builder],
        Need::Safety => vec![], // No specific skill for safety yet
        Need::Sleep => vec![], // No specific skill for sleep yet
        Need::Companionship => vec![
            crate::settlement::skill::Skill::Musician,
            crate::settlement::skill::Skill::Storyteller,
        ],
        Need::Joy => vec![], // Joy cannot be directly satisfied
    };

    // Count matching skills
    let matching_count = npc_skills
        .iter()
        .filter(|skill| relevant_skills.contains(skill))
        .count();

    // Base multiplier + bonus per matching skill
    1.0 + (matching_count as f32 * 0.2)
}

/// Computes the perception filter modifier.
///
/// This applies the Layer 2 emotional state's distortion to the perceived
/// urgency of a need. An NPC in a negative mood will perceive needs as
/// more urgent (scarcity seems worse), while a positive mood will perceive
/// them as less urgent (things seem better).
///
/// The substrate's stability axis determines how strongly mood affects perception.
///
/// Defined in GAME_DESIGN_SECTION_4.md Sections 4.1.2 and 4.4.3.
pub fn perception_filter(
    npc_emotional_state: &EmotionalState,
    need_satisfaction: f32,
    substrate_stability: f32,
) -> f32 {
    // Use the emotional state's perceive method
    // For need satisfaction, we want:
    // - Negative mood: perceives lower satisfaction (more urgent)
    // - Positive mood: perceives higher satisfaction (less urgent)
    
    // The perceived satisfaction is biased by mood
    let perceived_satisfaction = npc_emotional_state.perceive(need_satisfaction, substrate_stability);
    
    // Convert back to urgency: lower perceived satisfaction = higher urgency
    // But we need to be careful: perception_filter in the formula is a multiplier
    // that affects the base urgency. If the need seems more unsatisfied, the multiplier should be > 1.
    
    // If perceived satisfaction is lower than actual, the need seems more urgent
    // multiplier = actual_urgency / perceived_urgency
    // But since perceived_satisfaction might be different from actual:
    
    let actual_urgency = 1.0 - need_satisfaction.clamp(0.0, 1.0);
    let perceived_urgency = 1.0 - perceived_satisfaction.clamp(0.0, 1.0);
    
    // If perceived urgency > actual urgency, we want multiplier > 1
    // This happens when perceived_satisfaction < actual satisfaction
    if actual_urgency > 0.0 {
        (perceived_urgency / actual_urgency).clamp(0.5, 2.0)
    } else {
        1.0
    }
}

/// Computes the substrate weight modifier.
///
/// The substrate (Layer 1) modifies action weights based on the NPC's traits:
/// - Generous NPCs get bonus utility on Share Food and communally beneficial actions
/// - Courageous NPCs get bonus on Hunt (distant), Lookout
/// - Stable NPCs' perception filter is dampened (already handled in perception_filter)
///
/// Defined in GAME_DESIGN_SECTION_4.md Section 4.4.3.
pub fn substrate_weight(substrate: &Substrate, action: &Action) -> f32 {
    let mut weight = 1.0;

    // Generosity bonus for communal actions
    if action.communal_benefit {
        // More generous = more likely to do communal actions
        weight += substrate.generosity_selfishness * 0.3;
    }

    // Courage bonus for dangerous/remote actions
    match action.primary_need {
        Need::Food if action.name == "Hunt" => {
            // Hunting requires courage
            weight += substrate.courage_fear * 0.4;
        }
        Need::Safety if action.name == "Lookout/Observe" || action.name == "Warn Others" => {
            // Lookout and warning require courage
            weight += substrate.courage_fear * 0.3;
        }
        _ => {}
    }

    weight.clamp(0.1, 3.0)
}

/// Computes the coping modifier based on settlement damage and action coping type.
///
/// Material coping actions are boosted when settlement damage is high.
/// Emotional coping actions are suppressed by the material satisfaction gate.
///
/// Defined in GAME_DESIGN_SECTION_4.md Section 4.4.3 and
/// GAME_DESIGN_SECTION_3.md Section 3.3.2.
pub fn coping_modifier(settlement_damage: f32, action_coping_type: CopingType) -> f32 {
    // When there's no damage, coping actions still have neutral value
    if settlement_damage == 0.0 {
        return 0.5;
    }

    match action_coping_type {
        CopingType::Material => {
            // Material coping is more valuable when damage is high
            // Boost proportional to damage level
            1.0 + settlement_damage * 2.0
        }
        CopingType::Emotional => {
            // Emotional coping is suppressed when material needs are unsatisfied
            // This is the "material satisfaction gate" from Section 3.3.2
            // For now, we use a simple threshold: if damage is very high, emotional coping is less effective
            if settlement_damage > 0.7 {
                0.5 // Suppressed
            } else {
                1.0 - settlement_damage * 0.5
            }
        }
        CopingType::None => 1.0,
    }
}

/// Computes the cooperation modifier based on settlement mood and action communal benefit.
///
/// When aggregate mood is high (> +0.3), communal actions are boosted.
/// When aggregate mood is low (< -0.3), communal actions are penalized.
/// Family-layer interactions are exempt (NPCs always cooperate with family).
///
/// Defined in GAME_DESIGN_SECTION_4.md Section 4.5.1.
pub fn cooperation_modifier(
    settlement_aggregate_mood: f32,
    action_communal_benefit: bool,
) -> f32 {
    if !action_communal_benefit {
        // Non-communal actions are not affected by cooperation modifier
        return 1.0;
    }

    // Communal actions are affected by aggregate mood
    if settlement_aggregate_mood > 0.3 {
        // High mood: boost communal actions
        1.0 + (settlement_aggregate_mood - 0.3) * 2.0
    } else if settlement_aggregate_mood < -0.3 {
        // Low mood: penalize communal actions
        1.0 - (0.3 - settlement_aggregate_mood) * 2.0
    } else {
        // Neutral mood: no effect
        1.0
    }
}

/// Computes the full utility score for an action given an NPC and settlement state.
///
/// This implements the complete formula from GAME_DESIGN_SECTION_4.md Section 4.4.3.
#[allow(clippy::too_many_arguments)]
pub fn compute_utility_score(
    npc_need_satisfaction: f32,
    action: &Action,
    need: Need,
    npc_skills: &[crate::settlement::skill::Skill],
    npc_emotional_state: &EmotionalState,
    substrate: &Substrate,
    time_of_day: f32,
    settlement_damage: f32,
    settlement_aggregate_mood: f32,
) -> f32 {
    let base = base_urgency(need, npc_need_satisfaction);
    let time = time_block_multiplier(action, time_of_day);
    let skill = skill_modifier(npc_skills, action);
    let perception = perception_filter(npc_emotional_state, npc_need_satisfaction, substrate.stability_anxiety);
    let substrate = substrate_weight(substrate, action);
    let coping = coping_modifier(settlement_damage, action.coping_type);
    let cooperation = cooperation_modifier(settlement_aggregate_mood, action.communal_benefit);

    base * time * skill * perception * substrate * coping * cooperation
}

/// Validates the utility scoring module.
///
/// Currently returns empty as there's no state to validate.
/// This is a placeholder for future validation if the module gains state.
pub fn validate() -> ValidationErrors {
    Vec::new()
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

#[cfg(test)]
mod tests {
    use super::*;
    use crate::actions::catalogue;
    use crate::soul::EmotionalState;

    #[test]
    fn test_base_urgency() {
        // Fully unsatisfied need (0.0) should have maximum urgency
        let urgency = base_urgency(Need::Food, 0.0);
        assert!(urgency > 0.0);

        // Fully satisfied need (1.0) should have minimum urgency
        let urgency = base_urgency(Need::Food, 1.0);
        assert!(urgency < 0.001); // Very close to 0

        // Need with 50% satisfaction should have moderate urgency
        let urgency = base_urgency(Need::Food, 0.5);
        assert!(urgency > 0.0 && urgency < base_urgency(Need::Food, 0.0));
    }

    #[test]
    fn test_base_urgency_varies_by_need() {
        // Faster-decaying needs should be more urgent at the same satisfaction level
        let food_urgency = base_urgency(Need::Food, 0.5);
        let water_urgency = base_urgency(Need::Water, 0.5);
        let joy_urgency = base_urgency(Need::Joy, 0.5);

        // Water decays faster than food
        assert!(water_urgency > food_urgency);
        // Joy decays slowest
        assert!(joy_urgency < food_urgency);
    }

    #[test]
    fn test_time_block_multiplier() {
        let action = catalogue::action_by_id(1).unwrap(); // Farm/Tend prefers Dawn
        
        // Should have high multiplier during Dawn
        let multiplier = time_block_multiplier(&action, 0.25);
        assert_eq!(multiplier, 1.0);

        // Should have low multiplier during Night
        let multiplier = time_block_multiplier(&action, 0.9);
        assert_eq!(multiplier, 0.2);
    }

    #[test]
    fn test_skill_modifier() {
        use crate::settlement::skill::Skill;
        
        let action = catalogue::action_by_id(1).unwrap(); // Farm/Tend
        
        // NPC with no skills should have base multiplier
        let modifier = skill_modifier(&[], &action);
        assert_eq!(modifier, 1.0);

        // NPC with Farmer skill should have bonus for Farm/Tend
        let modifier = skill_modifier(&[Skill::Farmer], &action);
        assert!(modifier > 1.0);
    }

    #[test]
    fn test_perception_filter_neutral() {
        let emotional_state = EmotionalState::from_mood(0.0);
        let substrate_stability = 0.0;

        // Neutral mood should not distort perception
        let filter = perception_filter(&emotional_state, 0.5, substrate_stability);
        assert!((filter - 1.0).abs() < 0.01);
    }

    #[test]
    fn test_perception_filter_negative_mood() {
        let emotional_state = EmotionalState::from_mood(-0.8);
        let substrate_stability = 0.0;

        // Negative mood should make needs seem more urgent (higher multiplier)
        let filter = perception_filter(&emotional_state, 0.5, substrate_stability);
        assert!(filter > 1.0);
    }

    #[test]
    fn test_perception_filter_positive_mood() {
        let emotional_state = EmotionalState::from_mood(0.8);
        let substrate_stability = 0.0;

        // Positive mood should make needs seem less urgent (lower multiplier)
        let filter = perception_filter(&emotional_state, 0.5, substrate_stability);
        assert!(filter < 1.0);
    }

    #[test]
    fn test_substrate_weight_generous() {
        use crate::soul::Substrate;
        
        let substrate = Substrate::new(0.0, 0.8, 0.0); // Very generous
        let action = catalogue::action_by_id(6).unwrap(); // Share Food (communal)

        let weight = substrate_weight(&substrate, &action);
        assert!(weight > 1.0); // Generous NPC should have bonus for communal action
    }

    #[test]
    fn test_substrate_weight_selfish() {
        use crate::soul::Substrate;
        
        let substrate = Substrate::new(0.0, -0.8, 0.0); // Very selfish
        let action = catalogue::action_by_id(6).unwrap(); // Share Food (communal)

        let weight = substrate_weight(&substrate, &action);
        assert!(weight < 1.0); // Selfish NPC should have penalty for communal action
    }

    #[test]
    fn test_substrate_weight_courageous() {
        use crate::soul::Substrate;
        
        let substrate = Substrate::new(0.8, 0.0, 0.0); // Very courageous
        let action = catalogue::action_by_id(2).unwrap(); // Hunt

        let weight = substrate_weight(&substrate, &action);
        assert!(weight > 1.0); // Courageous NPC should have bonus for Hunt
    }

    #[test]
    fn test_coping_modifier_material_high_damage() {
        // Material coping should be boosted when damage is high
        let modifier = coping_modifier(0.8, CopingType::Material);
        assert!(modifier > 1.0);
    }

    #[test]
    fn test_coping_modifier_emotional_high_damage() {
        // Emotional coping should be suppressed when damage is high
        let modifier = coping_modifier(0.8, CopingType::Emotional);
        assert!(modifier < 1.0);
    }

    #[test]
    fn test_cooperation_modifier_high_mood() {
        // Communal actions should be boosted when mood is high
        let modifier = cooperation_modifier(0.5, true);
        assert!(modifier > 1.0);
    }

    #[test]
    fn test_cooperation_modifier_low_mood() {
        // Communal actions should be penalized when mood is low
        let modifier = cooperation_modifier(-0.5, true);
        assert!(modifier < 1.0);
    }

    #[test]
    fn test_cooperation_modifier_non_communal() {
        // Non-communal actions should not be affected by mood
        let modifier_high = cooperation_modifier(0.5, false);
        let modifier_low = cooperation_modifier(-0.5, false);
        assert_eq!(modifier_high, 1.0);
        assert_eq!(modifier_low, 1.0);
    }

    #[test]
    fn test_compute_utility_score() {
        use crate::soul::{EmotionalState, Substrate};
        
        let action = catalogue::action_by_id(1).unwrap(); // Farm/Tend
        let need = Need::Food;
        let npc_skills: Vec<crate::settlement::skill::Skill> = vec![];
        let npc_emotional_state = EmotionalState::neutral();
        let substrate = Substrate::neutral();
        let time_of_day = 0.25; // Dawn
        let settlement_damage = 0.0;
        let settlement_aggregate_mood = 0.0;

        // Low satisfaction should give high score
        let score_low = compute_utility_score(
            0.2, // Low satisfaction
            &action,
            need,
            &npc_skills,
            &npc_emotional_state,
            &substrate,
            time_of_day,
            settlement_damage,
            settlement_aggregate_mood,
        );

        // High satisfaction should give low score
        let score_high = compute_utility_score(
            0.8, // High satisfaction
            &action,
            need,
            &npc_skills,
            &npc_emotional_state,
            &substrate,
            time_of_day,
            settlement_damage,
            settlement_aggregate_mood,
        );

        assert!(score_low > score_high);
    }

    #[test]
    fn test_utility_score_struct() {
        let score = UtilityScore::new(1, 0.5);
        assert_eq!(score.action_id, 1);
        assert_eq!(score.value, 0.5);
    }
}
