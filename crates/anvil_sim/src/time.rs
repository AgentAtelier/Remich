//! Time Module
//!
//! Implements sigmoid time curves for smooth time-of-day modifiers (Sprint 18c Task 3).
//! Replaces static TimeBlock with continuous functions.
//!
//! The day is divided into time periods with smooth transitions:
//! - Pre-Dawn (0.0-0.08): All learning ×0.3 (night continues)
//! - Dawn (0.1-0.25): Perception skills +20%
//! - Midday (0.25-0.5): Physical skills +10%
//! - Evening (0.5-0.7): Social skills +30%
//! - Night (0.7-1.0): All learning ×0.3

use crate::skill::domain::SkillDomain;

/// Transition width for smooth transitions between time periods.
const TRANSITION_WIDTH: f32 = 0.05;

/// Returns the time learning modifier for a given time of day and skill domain.
///
/// This implements Sprint 18c Task 3 sigmoid time curves:
/// - Dawn (0.1-0.25): Perception skills (WeatherSense, Foraging) +20%
/// - Midday (0.25-0.5): Physical skills (Woodcraft, Stonework, Husbandry, Pathfinding) +10%
/// - Evening (0.5-0.7): Social skills (SocialWeaving) +30%
/// - Night (0.7-1.0) and Pre-Dawn (0.0-0.08): All learning ×0.3
///
/// # Arguments
/// * `time_of_day` - Time of day as a fraction of the day cycle [0.0, 1.0]
///   where 0.0 = midnight, 0.25 = dawn, 0.5 = noon, 0.75 = dusk, 1.0 = midnight
/// * `domain` - The skill domain to get the modifier for
///
/// # Returns
/// A multiplier to apply to learning rates for this domain at this time.
/// 1.0 = no effect, >1.0 = enhanced learning, <1.0 = reduced learning.
pub fn time_learning_modifier(time_of_day: f32, domain: SkillDomain) -> f32 {
    let tod = time_of_day.clamp(0.0, 1.0);

    // Classify the skill domain
    let is_perception = matches!(domain, SkillDomain::WeatherSense | SkillDomain::Foraging);
    let is_physical = matches!(
        domain,
        SkillDomain::Woodcraft | SkillDomain::Stonework | SkillDomain::Husbandry | SkillDomain::Pathfinding
    );
    let is_social = matches!(domain, SkillDomain::SocialWeaving);

    // Dawn period weight (0.1-0.25): perception bonus
    let dawn_weight = smooth_pulse(tod, 0.1, 0.25, TRANSITION_WIDTH);

    // Midday period weight (0.25-0.5): physical bonus
    let midday_weight = smooth_pulse(tod, 0.25, 0.5, TRANSITION_WIDTH);

    // Evening period weight (0.5-0.7): social bonus
    let evening_weight = smooth_pulse(tod, 0.5, 0.7, TRANSITION_WIDTH);

    // Night period weight (0.7-1.0 and 0.0-0.08): all learning penalty
    // Using 0.08 instead of 0.1 to leave room for dawn to start at 0.1
    let night_weight = smooth_pulse_wrapped(tod, 0.7, 1.0, 0.0, 0.08, TRANSITION_WIDTH);

    // Apply domain-specific bonus
    let domain_bonus = if is_perception {
        1.0 + 0.2 * dawn_weight
    } else if is_physical {
        1.0 + 0.1 * midday_weight
    } else if is_social {
        1.0 + 0.3 * evening_weight
    } else {
        1.0
    };

    // Night penalty: all learning ×0.3 when night_weight is 1.0
    let night_penalty = 0.3 + 0.7 * (1.0 - night_weight);

    domain_bonus * night_penalty
}

/// Creates a smooth pulse that is 1.0 between start and end, with smooth transitions.
///
/// The pulse starts transitioning at (start - width) and finishes at (end + width).
/// Within [start, end], the value is exactly 1.0.
fn smooth_pulse(x: f32, start: f32, end: f32, transition_width: f32) -> f32 {
    if x < start - transition_width {
        return 0.0;
    }
    if x > end + transition_width {
        return 0.0;
    }
    if x >= start && x <= end {
        return 1.0;
    }
    // Left transition zone: rising from 0 to 1
    if x < start {
        return smooth_step(start - transition_width, start, x);
    }
    // Right transition zone: falling from 1 to 0
    1.0 - smooth_step(end, end + transition_width, x)
}

/// Creates a smooth pulse that wraps around the [0.0, 1.0] boundary.
///
/// This handles the Night period which spans from 0.7 to 1.0 and continues at 0.0 to 0.1.
fn smooth_pulse_wrapped(
    x: f32,
    start1: f32,
    end1: f32,
    start2: f32,
    end2: f32,
    transition_width: f32,
) -> f32 {
    let pulse1 = smooth_pulse(x, start1, end1, transition_width);
    let pulse2 = smooth_pulse(x, start2, end2, transition_width);
    // Clamp to [0.0, 1.0] to avoid floating point errors
    (pulse1 + pulse2).clamp(0.0, 1.0)
}

/// Cubic smooth step function.
///
/// Returns 0.0 when x <= edge0, 1.0 when x >= edge1.
/// Uses a cubic Hermite spline (3t^2 - 2t^3) for smooth interpolation.
fn smooth_step(edge0: f32, edge1: f32, x: f32) -> f32 {
    let t = ((x - edge0) / (edge1 - edge0)).clamp(0.0, 1.0);
    t * t * (3.0 - 2.0 * t)
}

/// Returns the time period name for a given time of day.
///
/// This is useful for debugging and logging.
pub fn time_period_name(time_of_day: f32) -> &'static str {
    let tod = time_of_day.clamp(0.0, 1.0);

    if tod < 0.1 {
        "Pre-Dawn"
    } else if tod < 0.25 {
        "Dawn"
    } else if tod < 0.5 {
        "Midday"
    } else if tod < 0.7 {
        "Evening"
    } else {
        "Night"
    }
}

/// Returns the primary time block for a given time of day.
///
/// This maintains backward compatibility with the existing TimeBlock enum
/// by mapping the continuous time to the nearest block.
///
/// Original TimeBlock ranges from actions.rs:
/// - Dawn: [0.2, 0.35)
/// - Day: [0.35, 0.7)
/// - Dusk: [0.7, 0.85)
/// - Night: [0.0, 0.2) ∪ [0.85, 1.0]
/// - Anytime: all
pub fn time_block_from_tod(time_of_day: f32) -> crate::actions::TimeBlock {
    let tod = time_of_day.clamp(0.0, 1.0);

    // Night has wrap-around: [0.0, 0.2) and [0.85, 1.0]
    if !(0.2..0.85).contains(&tod) {
        crate::actions::TimeBlock::Night
    } else if tod < 0.35 {
        crate::actions::TimeBlock::Dawn
    } else if tod < 0.7 {
        crate::actions::TimeBlock::Day
    } else {
        crate::actions::TimeBlock::Dusk
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_smooth_step_boundaries() {
        assert_eq!(smooth_step(0.0, 1.0, 0.0), 0.0);
        assert_eq!(smooth_step(0.0, 1.0, 1.0), 1.0);
    }

    #[test]
    fn test_smooth_pulse_full_range() {
        // Before start - in transition zone (0.05 to 0.1)
        let val_before = smooth_pulse(0.075, 0.1, 0.25, 0.05);
        assert!(val_before > 0.0, "Should be > 0 in transition zone");
        assert!(val_before < 1.0, "Should be < 1 in transition zone");

        // At start
        assert_eq!(smooth_pulse(0.1, 0.1, 0.25, 0.05), 1.0);

        // In the middle
        assert_eq!(smooth_pulse(0.175, 0.1, 0.25, 0.05), 1.0);

        // At end
        assert_eq!(smooth_pulse(0.25, 0.1, 0.25, 0.05), 1.0);

        // After end - in transition zone (0.25 to 0.3)
        let val_after = smooth_pulse(0.275, 0.1, 0.25, 0.05);
        assert!(val_after > 0.0, "Should be > 0 in transition zone");
        assert!(val_after < 1.0, "Should be < 1 in transition zone");

        // Well after end
        assert_eq!(smooth_pulse(0.3, 0.1, 0.25, 0.05), 0.0);

        // Before start - outside transition zone
        assert_eq!(smooth_pulse(0.04, 0.1, 0.25, 0.05), 0.0);

        // Well after end - outside transition zone
        assert_eq!(smooth_pulse(0.31, 0.1, 0.25, 0.05), 0.0);
    }

    #[test]
    fn test_time_learning_modifier_perception_dawn() {
        // Perception skills should get +20% during Dawn (0.1-0.25)
        let mod_dawn_peak = time_learning_modifier(0.175, SkillDomain::WeatherSense);

        // Should be approximately 1.2 at peak (no night penalty at 0.175)
        assert!(
            (mod_dawn_peak - 1.2).abs() < 0.01,
            "Expected ~1.2, got {}",
            mod_dawn_peak
        );

        // At start of dawn (0.13 is past the pre-dawn night transition at 0.13)
        let mod_dawn_start = time_learning_modifier(0.13, SkillDomain::WeatherSense);
        assert!(
            mod_dawn_start >= 1.15,
            "Expected >= 1.15 at dawn start, got {}",
            mod_dawn_start
        );
    }

    #[test]
    fn test_time_learning_modifier_physical_midday() {
        // Physical skills should get +10% during Midday (0.25-0.5)
        let mod_midday_peak = time_learning_modifier(0.375, SkillDomain::Woodcraft);

        // Should be approximately 1.1 at peak
        assert!(
            (mod_midday_peak - 1.1).abs() < 0.01,
            "Expected ~1.1, got {}",
            mod_midday_peak
        );
    }

    #[test]
    fn test_time_learning_modifier_social_evening() {
        // Social skills should get +30% during Evening (0.5-0.7)
        let mod_evening_peak = time_learning_modifier(0.6, SkillDomain::SocialWeaving);

        // Should be approximately 1.3 at peak
        assert!(
            (mod_evening_peak - 1.3).abs() < 0.01,
            "Expected ~1.3, got {}",
            mod_evening_peak
        );
    }

    #[test]
    fn test_time_learning_modifier_night_penalty() {
        // All skills should be at ~0.3x during Night (0.7-1.0) and Pre-Dawn (0.0-0.08)
        let mod_night = time_learning_modifier(0.85, SkillDomain::Woodcraft);
        let mod_pre_dawn = time_learning_modifier(0.04, SkillDomain::Woodcraft);

        // At night peak
        assert!(
            (mod_night - 0.3).abs() < 0.01,
            "Expected ~0.3 at night, got {}",
            mod_night
        );

        // At pre-dawn
        assert!(
            (mod_pre_dawn - 0.3).abs() < 0.01,
            "Expected ~0.3 at pre-dawn, got {}",
            mod_pre_dawn
        );
    }

    #[test]
    fn test_time_learning_modifier_no_overlap() {
        // At 0.175 (dawn), Woodcraft should NOT get physical bonus
        let mod_woodcraft_dawn = time_learning_modifier(0.175, SkillDomain::Woodcraft);
        assert!(
            (mod_woodcraft_dawn - 1.0).abs() < 0.01,
            "Woodcraft should not get bonus during Dawn, got {}",
            mod_woodcraft_dawn
        );

        // At 0.375 (midday), WeatherSense should NOT get perception bonus
        let mod_perception_midday = time_learning_modifier(0.375, SkillDomain::WeatherSense);
        assert!(
            (mod_perception_midday - 1.0).abs() < 0.01,
            "WeatherSense should not get bonus during Midday, got {}",
            mod_perception_midday
        );
    }

    #[test]
    fn test_time_period_name() {
        assert_eq!(time_period_name(0.0), "Pre-Dawn");
        assert_eq!(time_period_name(0.05), "Pre-Dawn");
        assert_eq!(time_period_name(0.1), "Dawn");
        assert_eq!(time_period_name(0.175), "Dawn");
        assert_eq!(time_period_name(0.25), "Midday");
        assert_eq!(time_period_name(0.375), "Midday");
        assert_eq!(time_period_name(0.5), "Evening");
        assert_eq!(time_period_name(0.6), "Evening");
        assert_eq!(time_period_name(0.7), "Night");
        assert_eq!(time_period_name(0.9), "Night");
    }

    #[test]
    fn test_time_block_from_tod() {
        use crate::actions::TimeBlock;
        // Night: [0.0, 0.2) ∪ [0.85, 1.0]
        assert_eq!(time_block_from_tod(0.0), TimeBlock::Night);
        assert_eq!(time_block_from_tod(0.1), TimeBlock::Night); // 0.1 is in [0.0, 0.2)
        // Dawn: [0.2, 0.35)
        assert_eq!(time_block_from_tod(0.2), TimeBlock::Dawn);
        assert_eq!(time_block_from_tod(0.25), TimeBlock::Dawn);
        assert_eq!(time_block_from_tod(0.3), TimeBlock::Dawn);
        // Day: [0.35, 0.7)
        assert_eq!(time_block_from_tod(0.35), TimeBlock::Day);
        assert_eq!(time_block_from_tod(0.5), TimeBlock::Day);
        // Dusk: [0.7, 0.85)
        assert_eq!(time_block_from_tod(0.7), TimeBlock::Dusk);
        assert_eq!(time_block_from_tod(0.8), TimeBlock::Dusk);
        // Night: [0.85, 1.0]
        assert_eq!(time_block_from_tod(0.85), TimeBlock::Night);
        assert_eq!(time_block_from_tod(0.95), TimeBlock::Night);
    }
}
