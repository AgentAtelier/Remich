//! Multi-axis Emotional State for Forgeborn NPCs.
//!
//! Implements the four-axis emotional model defined in GAME_DESIGN_SECTION_4.md
//! Section 4.1.2 (future extension) and Sprint 18c Task 1.
//!
//! The four axes are:
//! - Security/Threat: environmental evaluation filtering
//! - Belonging/Isolation: social evaluation filtering
//! - Agency/Helplessness: action availability perception filtering
//! - Satiation/Desperation: resource evaluation filtering

use anvil_core::{FailureClass, ValidationErrors, error_buffer, push_validation_error};
use serde::{Deserialize, Serialize};
use std::fmt;

/// The four emotional axes for multi-dimensional emotional state.
///
/// Each axis ranges from -1.0 to +1.0, representing opposite emotional states.
///
/// Defined in Sprint 18c Task 1 based on GAME_DESIGN_SECTION_4.md Section 4.1.2.
#[derive(Debug, Clone, Copy, PartialEq, Serialize, Deserialize)]
pub struct EmotionalAxes {
    /// Security ↔ Threat axis.
    /// -1.0 = terrified, +1.0 = safe.
    /// Filters environmental evaluation. High threat sharpens danger cues
    /// but degrades precision. Spreads fastest through the network.
    pub security_threat: f32,
    /// Belonging ↔ Isolation axis.
    /// -1.0 = lonely, +1.0 = connected.
    /// Filters social evaluation. Isolation blocks teaching eligibility,
    /// reduces observation rate.
    pub belonging_isolation: f32,
    /// Agency ↔ Helplessness axis.
    /// -1.0 = despair, +1.0 = empowered.
    /// Filters action availability perception. Low agency suppresses
    /// complex action attempts even if technically unlocked.
    pub agency_helplessness: f32,
    /// Satiation ↔ Desperation axis.
    /// -1.0 = starving, +1.0 = content.
    /// Filters resource evaluation. Desperation increases action speed
    /// but increases waste.
    pub satiation_desperation: f32,
}

impl EmotionalAxes {
    /// Creates a new EmotionalAxes with the given values.
    ///
    /// All values must be in the range [-1.0, 1.0].
    #[allow(clippy::too_many_arguments)]
    pub fn new(
        security_threat: f32,
        belonging_isolation: f32,
        agency_helplessness: f32,
        satiation_desperation: f32,
    ) -> Self {
        Self {
            security_threat,
            belonging_isolation,
            agency_helplessness,
            satiation_desperation,
        }
    }

    /// Creates a neutral emotional axes (all axes at 0.0).
    pub fn neutral() -> Self {
        Self::new(0.0, 0.0, 0.0, 0.0)
    }

    /// Creates EmotionalAxes from a single mood value (for backward compatibility).
    ///
    /// Maps the mood to all four axes equally. This allows gradual migration
    /// from the single-axis mood system to the multi-axis system.
    pub fn from_mood(mood: f32) -> Self {
        // Map mood to each axis: positive mood increases security, belonging, agency, satiation
        // Negative mood decreases them (increases threat, isolation, helplessness, desperation)
        let value = mood.clamp(-1.0, 1.0);
        Self::new(value, value, value, value)
    }

    /// Returns the security value (positive = secure).
    pub fn security(&self) -> f32 {
        self.security_threat
    }

    /// Returns the threat value (negative of security).
    pub fn threat(&self) -> f32 {
        -self.security_threat
    }

    /// Returns the belonging value (positive = connected).
    pub fn belonging(&self) -> f32 {
        self.belonging_isolation
    }

    /// Returns the isolation value (negative of belonging).
    pub fn isolation(&self) -> f32 {
        -self.belonging_isolation
    }

    /// Returns the agency value (positive = empowered).
    pub fn agency(&self) -> f32 {
        self.agency_helplessness
    }

    /// Returns the helplessness value (negative of agency).
    pub fn helplessness(&self) -> f32 {
        -self.agency_helplessness
    }

    /// Returns the satiation value (positive = content).
    pub fn satiation(&self) -> f32 {
        self.satiation_desperation
    }

    /// Returns the desperation value (negative of satiation).
    pub fn desperation(&self) -> f32 {
        -self.satiation_desperation
    }

    /// Computes the propagation speed multiplier for this axis set.
    ///
    /// Security/Threat spreads fastest (fear is contagious).
    /// Agency/Helplessness spreads slowest.
    /// Weighted by connection layer (Family > Proximity > Village).
    ///
    /// Returns a tuple of (security_weight, belonging_weight, agency_weight, satiation_weight).
    pub fn propagation_weights() -> (f32, f32, f32, f32) {
        // Security/Threat spreads fastest (weight 1.5)
        // Belonging/Isolation spreads at normal speed (weight 1.0)
        // Satiation/Desperation spreads at normal speed (weight 1.0)
        // Agency/Helplessness spreads slowest (weight 0.7)
        (1.5, 1.0, 0.7, 1.0)
    }

    /// Computes the overall mood from the four axes.
    ///
    /// This is a simple average for backward compatibility with systems
    /// that still use a single mood value.
    pub fn to_mood(&self) -> f32 {
        (self.security_threat
            + self.belonging_isolation
            + self.agency_helplessness
            + self.satiation_desperation)
            / 4.0
    }

    /// Applies perception filtering for the Security/Threat axis.
    ///
    /// High threat sharpens danger cues but degrades precision.
    /// This filters environmental evaluation.
    ///
    /// The threat level (negative security) increases the perceived danger
    /// while reducing the precision of non-threat evaluations.
    pub fn filter_security(&self, value: f32, is_danger_cue: bool) -> f32 {
        let clamped = value.clamp(0.0, 1.0);
        let threat_level = self.threat().abs();

        if is_danger_cue {
            // Sharpens danger cues: high threat makes danger seem more imminent
            // Value is already a danger level (0.0 to 1.0), so we amplify it
            let amplification = 1.0 + threat_level * 0.5; // Up to 1.5x amplification
            (clamped * amplification).clamp(0.0, 1.0)
        } else {
            // Degrades precision of non-danger evaluations
            // High threat makes everything else seem less certain/clear
            let degradation = 1.0 - threat_level * 0.3; // Up to 30% degradation
            clamped * degradation
        }
    }

    /// Applies perception filtering for the Belonging/Isolation axis.
    ///
    /// Isolation blocks teaching eligibility, reduces observation rate.
    /// This filters social evaluation.
    ///
    /// Low belonging (high isolation) reduces perceived social connection
    /// and blocks teaching eligibility.
    pub fn filter_belonging(&self, value: f32, is_teaching_context: bool) -> f32 {
        let clamped = value.clamp(0.0, 1.0);
        let isolation_level = self.isolation().abs();

        if is_teaching_context {
            // Isolation reduces teaching eligibility
            // At full isolation (-1.0), teaching is nearly blocked (10% remaining)
            let block_factor = 0.1 + 0.9 * (1.0 - isolation_level);
            clamped * block_factor
        } else {
            // Isolation reduces perceived social connection
            let reduction = 1.0 - isolation_level * 0.4; // Up to 40% reduction
            clamped * reduction
        }
    }

    /// Applies perception filtering for the Agency/Helplessness axis.
    ///
    /// Low agency suppresses complex action attempts.
    /// This filters action availability perception.
    ///
    /// Returns the availability multiplier for an action based on its complexity.
    pub fn filter_agency(&self, action_complexity: f32) -> f32 {
        // action_complexity: 0.0 (simple) to 1.0 (complex)
        let clamped_complexity = action_complexity.clamp(0.0, 1.0);
        let helplessness_level = self.helplessness().abs();

        // Low agency (high helplessness) suppresses complex actions more
        // Simple actions (complexity ~0) are always available
        // Complex actions (complexity ~1) are suppressed by helplessness
        let suppression = helplessness_level * clamped_complexity;
        (1.0 - suppression).clamp(0.0, 1.0)
    }

    /// Applies perception filtering for the Satiation/Desperation axis.
    ///
    /// Desperation increases action speed but increases waste.
    /// This filters resource evaluation.
    ///
    /// Returns a tuple of (speed_multiplier, waste_multiplier).
    pub fn filter_satiation(&self) -> (f32, f32) {
        let desperation_level = self.desperation().abs();

        // Desperation increases speed (up to 1.3x)
        let speed_multiplier = 1.0 + desperation_level * 0.3;

        // Desperation increases waste (up to 1.5x)
        let waste_multiplier = 1.0 + desperation_level * 0.5;

        (speed_multiplier, waste_multiplier)
    }

    /// Gets the observation rate multiplier based on Security/Threat axis.
    ///
    /// High Threat: +20% observation rate.
    pub fn observation_rate_multiplier(&self) -> f32 {
        let threat_level = self.threat().abs();
        1.0 + threat_level * 0.2
    }

    /// Gets the practice quality multiplier based on Security/Threat axis.
    ///
    /// High Threat: -20% practice quality.
    pub fn practice_quality_multiplier(&self) -> f32 {
        let threat_level = self.threat().abs();
        (1.0 - threat_level * 0.2).clamp(0.0, 1.0)
    }

    /// Gets the teaching rate multiplier based on Belonging/Isolation axis.
    ///
    /// Low Belonging: incidental teaching rate drops to near zero.
    pub fn teaching_rate_multiplier(&self) -> f32 {
        let isolation_level = self.isolation().abs();
        // At full isolation, teaching rate is nearly zero (5% remaining)
        (0.05 + 0.95 * (1.0 - isolation_level)).clamp(0.0, 1.0)
    }

    /// Gets the action availability suppression based on Agency/Helplessness axis.
    ///
    /// Low Agency: suppresses attempts of actions requiring complex affordances.
    /// Returns the suppression factor (0.0 = fully suppressed, 1.0 = no suppression).
    pub fn complex_action_suppression(&self) -> f32 {
        let helplessness_level = self.helplessness().abs();
        // High helplessness strongly suppresses complex actions
        (1.0 - helplessness_level * 0.8).clamp(0.0, 1.0)
    }

    /// Gets the speed and waste modifiers based on Satiation/Desperation axis.
    ///
    /// High Desperation: action_duration_multiplier reduced, waste multiplier increased.
    /// Returns (duration_multiplier, waste_multiplier).
    pub fn desperation_modifiers(&self) -> (f32, f32) {
        let desperation_level = self.desperation().abs();
        // Duration reduced by up to 30%
        let duration_multiplier = (1.0 - desperation_level * 0.3).clamp(0.3, 1.0);
        // Waste increased by up to 50%
        let waste_multiplier = 1.0 + desperation_level * 0.5;
        (duration_multiplier, waste_multiplier)
    }

    /// Gets the skill decay rate multiplier based on emotional state.
    ///
    /// Low Security, Low Belonging, Low Agency, and Low Satiation all increase decay rate.
    /// This represents the difficulty of retaining skills when stressed, isolated,
    /// helpless, or desperate.
    ///
    /// Returns a multiplier to apply to the base decay rate:
    /// - 1.0 = normal decay
    /// - >1.0 = faster decay (worse emotional state)
    /// - <1.0 = slower decay (better emotional state)
    pub fn decay_rate_multiplier(&self) -> f32 {
        // Each negative axis contributes to increased decay
        let threat_penalty = (1.0 - self.security()).abs() * 0.3; // Up to +30%
        let isolation_penalty = (1.0 - self.belonging()).abs() * 0.3; // Up to +30%
        let helplessness_penalty = (1.0 - self.agency()).abs() * 0.2; // Up to +20%
        let desperation_penalty = (1.0 - self.satiation()).abs() * 0.2; // Up to +20%
        
        // Total penalty: up to 1.0 (100% faster decay) in worst case
        // Base is 1.0, add penalties
        1.0 + threat_penalty + isolation_penalty + helplessness_penalty + desperation_penalty
    }

    /// Validates this EmotionalAxes.
    pub fn validate(&self) -> ValidationErrors {
        let mut errors = error_buffer();

        for (field, value) in [
            ("security_threat", self.security_threat),
            ("belonging_isolation", self.belonging_isolation),
            ("agency_helplessness", self.agency_helplessness),
            ("satiation_desperation", self.satiation_desperation),
        ] {
            if !value.is_finite() || !(-1.0..=1.0).contains(&value) {
                push_validation_error!(
                    errors,
                    FailureClass::Semantic,
                    "E187",
                    "EmotionalAxes",
                    field,
                    format!("{}", value),
                    "axis value must be in [-1.0, 1.0]"
                );
            }
        }

        errors
    }

    /// Propagates this emotional state to a connected NPC based on connection layer.
    ///
    /// Each axis spreads independently through the emotional network.
    /// Security/Threat spreads fastest (fear is contagious).
    /// Agency/Helplessness spreads slowest.
    /// Weighted by connection layer (Family > Proximity > Village).
    ///
    /// Returns the influence on each axis for the connected NPC.
    pub fn propagate(&self, connection_weight: f32) -> EmotionalAxes {
        let (sec_weight, bel_weight, agy_weight, sat_weight) = Self::propagation_weights();

        EmotionalAxes::new(
            self.security_threat * connection_weight * sec_weight,
            self.belonging_isolation * connection_weight * bel_weight,
            self.agency_helplessness * connection_weight * agy_weight,
            self.satiation_desperation * connection_weight * sat_weight,
        )
    }
}

impl fmt::Display for EmotionalAxes {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(
            f,
            "EmotionalAxes {{ security: {:+.2}, belonging: {:+.2}, agency: {:+.2}, satiation: {:+.2} }}",
            self.security_threat,
            self.belonging_isolation,
            self.agency_helplessness,
            self.satiation_desperation
        )
    }
}

impl Default for EmotionalAxes {
    fn default() -> Self {
        Self::neutral()
    }
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_emotional_axes_neutral() {
        let axes = EmotionalAxes::neutral();
        assert_eq!(axes.security_threat, 0.0);
        assert_eq!(axes.belonging_isolation, 0.0);
        assert_eq!(axes.agency_helplessness, 0.0);
        assert_eq!(axes.satiation_desperation, 0.0);
    }

    #[test]
    fn test_emotional_axes_accessors() {
        let axes = EmotionalAxes::new(0.5, -0.3, 0.8, -0.2);
        assert_eq!(axes.security(), 0.5);
        assert_eq!(axes.threat(), -0.5);
        assert_eq!(axes.belonging(), -0.3);
        assert_eq!(axes.isolation(), 0.3);
        assert_eq!(axes.agency(), 0.8);
        assert_eq!(axes.helplessness(), -0.8);
        assert_eq!(axes.satiation(), -0.2);
        assert_eq!(axes.desperation(), 0.2);
    }

    #[test]
    fn test_from_mood() {
        let axes = EmotionalAxes::from_mood(0.5);
        assert_eq!(axes.security_threat, 0.5);
        assert_eq!(axes.belonging_isolation, 0.5);
        assert_eq!(axes.agency_helplessness, 0.5);
        assert_eq!(axes.satiation_desperation, 0.5);
    }

    #[test]
    fn test_from_mood_negative() {
        let axes = EmotionalAxes::from_mood(-0.5);
        assert_eq!(axes.security_threat, -0.5);
        assert_eq!(axes.belonging_isolation, -0.5);
        assert_eq!(axes.agency_helplessness, -0.5);
        assert_eq!(axes.satiation_desperation, -0.5);
    }

    #[test]
    fn test_to_mood() {
        let axes = EmotionalAxes::new(0.2, 0.4, 0.6, 0.8);
        let mood = axes.to_mood();
        assert!((mood - 0.5).abs() < 0.001);
    }

    #[test]
    fn test_propagation_weights() {
        let (sec, bel, agy, sat) = EmotionalAxes::propagation_weights();
        assert!((sec - 1.5).abs() < 0.001);
        assert!((bel - 1.0).abs() < 0.001);
        assert!((agy - 0.7).abs() < 0.001);
        assert!((sat - 1.0).abs() < 0.001);
    }

    #[test]
    fn test_filter_security_danger_cue() {
        let axes = EmotionalAxes::new(-0.8, 0.0, 0.0, 0.0); // High threat
        let filtered = axes.filter_security(0.5, true); // Danger cue
        assert!(filtered > 0.5); // Amplified
    }

    #[test]
    fn test_filter_security_non_danger() {
        let axes = EmotionalAxes::new(-0.8, 0.0, 0.0, 0.0); // High threat
        let filtered = axes.filter_security(0.5, false); // Non-danger
        assert!(filtered < 0.5); // Degraded
    }

    #[test]
    fn test_filter_belonging_teaching() {
        let axes = EmotionalAxes::new(0.0, -0.8, 0.0, 0.0); // High isolation
        let filtered = axes.filter_belonging(1.0, true); // Teaching context
        assert!(filtered < 0.5); // Strongly reduced
    }

    #[test]
    fn test_filter_belonging_social() {
        let axes = EmotionalAxes::new(0.0, -0.8, 0.0, 0.0); // High isolation
        let filtered = axes.filter_belonging(1.0, false); // Social context
        assert!(filtered < 1.0); // Reduced
        assert!(filtered > 0.5); // But not as strongly
    }

    #[test]
    fn test_filter_agency_simple_action() {
        let axes = EmotionalAxes::new(0.0, 0.0, -0.8, 0.0); // High helplessness
        let filtered = axes.filter_agency(0.1); // Simple action
        // suppression = 0.8 * 0.1 = 0.08, result = 1.0 - 0.08 = 0.92
        assert!((filtered - 0.92).abs() < 0.001);
    }

    #[test]
    fn test_filter_agency_complex_action() {
        let axes = EmotionalAxes::new(0.0, 0.0, -0.8, 0.0); // High helplessness
        let filtered = axes.filter_agency(0.9); // Complex action
        assert!(filtered < 0.5); // Strongly suppressed
    }

    #[test]
    fn test_filter_satiation() {
        let axes = EmotionalAxes::new(0.0, 0.0, 0.0, -0.8); // High desperation
        let (speed, waste) = axes.filter_satiation();
        assert!(speed > 1.0); // Faster
        assert!(waste > 1.0); // More waste
    }

    #[test]
    fn test_observation_rate_multiplier() {
        let axes = EmotionalAxes::new(-0.8, 0.0, 0.0, 0.0); // High threat
        let multiplier = axes.observation_rate_multiplier();
        assert!((multiplier - 1.16).abs() < 0.001); // +20% of 0.8 = 1.16
    }

    #[test]
    fn test_practice_quality_multiplier() {
        let axes = EmotionalAxes::new(-0.8, 0.0, 0.0, 0.0); // High threat
        let multiplier = axes.practice_quality_multiplier();
        assert!((multiplier - 0.84).abs() < 0.001); // -20% of 0.8 = 0.84
    }

    #[test]
    fn test_teaching_rate_multiplier() {
        let axes = EmotionalAxes::new(0.0, -0.8, 0.0, 0.0); // High isolation
        let multiplier = axes.teaching_rate_multiplier();
        assert!((multiplier - 0.235).abs() < 0.01); // 0.05 + 0.95 * (1 - 0.8)
    }

    #[test]
    fn test_complex_action_suppression() {
        let axes = EmotionalAxes::new(0.0, 0.0, -0.8, 0.0); // High helplessness
        let suppression = axes.complex_action_suppression();
        assert!((suppression - 0.36).abs() < 0.001); // 1 - 0.8 * 0.8 = 0.36
    }

    #[test]
    fn test_desperation_modifiers() {
        let axes = EmotionalAxes::new(0.0, 0.0, 0.0, -0.8); // High desperation
        let (duration, waste) = axes.desperation_modifiers();
        // duration = 1.0 - 0.8 * 0.3 = 1.0 - 0.24 = 0.76
        assert!((duration - 0.76).abs() < 0.001);
        // waste = 1.0 + 0.8 * 0.5 = 1.0 + 0.4 = 1.4
        assert!((waste - 1.4).abs() < 0.001);
    }

    #[test]
    fn test_validation_valid() {
        let axes = EmotionalAxes::new(0.5, -0.3, 0.8, -0.2);
        assert!(axes.validate().is_empty());
    }

    #[test]
    fn test_validation_invalid_security() {
        let axes = EmotionalAxes::new(1.5, 0.0, 0.0, 0.0);
        let errors = axes.validate();
        assert_eq!(errors.len(), 1);
        assert_eq!(errors[0].code().as_str(), "E187");
    }

    #[test]
    fn test_validation_invalid_belonging() {
        let axes = EmotionalAxes::new(0.0, -1.5, 0.0, 0.0);
        let errors = axes.validate();
        assert_eq!(errors.len(), 1);
        assert_eq!(errors[0].code().as_str(), "E187");
    }

    #[test]
    fn test_propagate() {
        let axes = EmotionalAxes::new(0.5, -0.3, 0.8, -0.2);
        let propagated = axes.propagate(0.5); // Proximity layer weight
        
        // Security: 0.5 * 0.5 * 1.5 = 0.375
        assert!((propagated.security_threat - 0.375).abs() < 0.001);
        // Belonging: -0.3 * 0.5 * 1.0 = -0.15
        assert!((propagated.belonging_isolation - (-0.15)).abs() < 0.001);
        // Agency: 0.8 * 0.5 * 0.7 = 0.28
        assert!((propagated.agency_helplessness - 0.28).abs() < 0.001);
        // Satiation: -0.2 * 0.5 * 1.0 = -0.1
        assert!((propagated.satiation_desperation - (-0.1)).abs() < 0.001);
    }

    #[test]
    fn test_display() {
        let axes = EmotionalAxes::new(0.5, -0.3, 0.8, -0.2);
        let display = format!("{}", axes);
        assert!(display.contains("security: +0.50"));
        assert!(display.contains("belonging: -0.30"));
        assert!(display.contains("agency: +0.80"));
        assert!(display.contains("satiation: -0.20"));
    }

    #[test]
    fn test_default() {
        let axes = EmotionalAxes::default();
        assert_eq!(axes.security_threat, 0.0);
        assert_eq!(axes.belonging_isolation, 0.0);
        assert_eq!(axes.agency_helplessness, 0.0);
        assert_eq!(axes.satiation_desperation, 0.0);
    }
}
