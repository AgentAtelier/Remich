//! Layered Soul Model for Forgeborn NPCs.
//!
//! Implements the three-layer architecture defined in GAME_DESIGN_SECTION_4.md Section 4.1:
//! - Layer 1: Substrate (stable traits)
//! - Layer 2: Emotional State (multi-axis emotional state with perception filter)
//! - Layer 3: Action Surface (utility scoring - implemented in npc.rs)
//!
//! Sprint 18c: Multi-axis emotional state replaces the single mood value.
//! The four axes (security/threat, belonging/isolation, agency/helplessness,
//! satiation/desperation) each filter different categories of perception.

use anvil_core::{FailureClass, ValidationErrors, error_buffer, push_validation_error};
use serde::{Deserialize, Serialize};
use std::fmt;

pub mod axes;

pub use axes::EmotionalAxes;

/// Layer 1: The Substrate - stable traits that define who the NPC is.
///
/// Three axes, each a continuous value from -1.0 to +1.0.
/// Changes only under extraordinary circumstances (trauma, years-long relationships).
/// For practical purposes in normal gameplay, the substrate is fixed.
///
/// Defined in GAME_DESIGN_SECTION_4.md Section 4.1.1.
#[derive(Debug, Clone, Copy, PartialEq, Serialize, Deserialize)]
pub struct Substrate {
    /// Courage ↔ Fear axis.
    /// -1.0 = fearful, +1.0 = courageous.
    /// A courageous NPC stays when others flee, volunteers for dangerous tasks.
    pub courage_fear: f32,
    /// Generosity ↔ Selfishness axis.
    /// -1.0 = selfish, +1.0 = generous.
    /// A generous NPC shares food when stores are low, helps neighbours first.
    pub generosity_selfishness: f32,
    /// Stability ↔ Anxiety axis.
    /// -1.0 = anxious, +1.0 = stable.
    /// A stable NPC absorbs shocks, recovers faster, anchors others.
    /// An anxious NPC amplifies shocks, is more susceptible to negative contagion.
    pub stability_anxiety: f32,
}

impl Substrate {
    /// Creates a new substrate with the given axis values.
    ///
    /// All values must be in the range [-1.0, 1.0].
    pub fn new(
        courage_fear: f32,
        generosity_selfishness: f32,
        stability_anxiety: f32,
    ) -> Self {
        Self {
            courage_fear,
            generosity_selfishness,
            stability_anxiety,
        }
    }

    /// Creates a neutral substrate (all axes at 0.0).
    pub fn neutral() -> Self {
        Self::new(0.0, 0.0, 0.0)
    }

    /// Creates a substrate from a seeded random generator.
    ///
    /// Uses the deterministic RNG to generate consistent substrate values.
    pub fn from_seed(seed: u64) -> Self {
        let mut rng = crate::DeterministicRng::new(seed);
        // Use different seeds for each axis to ensure variation
        let courage_fear = rng.next_f32_range(-1.0, 1.0);
        let generosity_selfishness = rng.next_f32_range(-1.0, 1.0);
        let stability_anxiety = rng.next_f32_range(-1.0, 1.0);
        Self::new(courage_fear, generosity_selfishness, stability_anxiety)
    }

    /// Returns the courage value (positive = courageous).
    pub fn courage(&self) -> f32 {
        self.courage_fear
    }

    /// Returns the fear value (negative of courage).
    pub fn fear(&self) -> f32 {
        -self.courage_fear
    }

    /// Returns the generosity value (positive = generous).
    pub fn generosity(&self) -> f32 {
        self.generosity_selfishness
    }

    /// Returns the selfishness value (negative of generosity).
    pub fn selfishness(&self) -> f32 {
        -self.generosity_selfishness
    }

    /// Returns the stability value (positive = stable).
    pub fn stability(&self) -> f32 {
        self.stability_anxiety
    }

    /// Returns the anxiety value (negative of stability).
    pub fn anxiety(&self) -> f32 {
        -self.stability_anxiety
    }

    /// Validates this substrate.
    pub fn validate(&self) -> ValidationErrors {
        let mut errors = error_buffer();

        for (field, value) in [
            ("courage_fear", self.courage_fear),
            ("generosity_selfishness", self.generosity_selfishness),
            ("stability_anxiety", self.stability_anxiety),
        ] {
            if !value.is_finite() || !(-1.0..=1.0).contains(&value) {
                push_validation_error!(
                    errors,
                    FailureClass::Semantic,
                    "E174",
                    "Substrate",
                    field,
                    format!("{}", value),
                    "axis value must be in [-1.0, 1.0]"
                );
            }
        }

        errors
    }
}

impl fmt::Display for Substrate {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(
            f,
            "Substrate {{ courage: {:+.2}, generosity: {:+.2}, stability: {:+.2} }}",
            self.courage_fear, self.generosity_selfishness, self.stability_anxiety
        )
    }
}

/// Layer 2: Emotional State with multi-axis emotional model.
///
/// Sprint 18c replaces the single mood value with four axes:
/// - Security/Threat: environmental evaluation filtering
/// - Belonging/Isolation: social evaluation filtering
/// - Agency/Helplessness: action availability perception filtering
/// - Satiation/Desperation: resource evaluation filtering
///
/// Each axis ranges from -1.0 to +1.0.
///
/// The mood value is maintained for backward compatibility and is computed
/// as the average of all four axes.
///
/// Defined in GAME_DESIGN_SECTION_4.md Section 4.1.2 and Sprint 18c Task 1.
#[derive(Debug, Clone, Copy, PartialEq, Serialize, Deserialize)]
pub struct EmotionalState {
    /// The four emotional axes.
    pub axes: EmotionalAxes,
}

impl EmotionalState {
    /// Creates a new emotional state with the given axes.
    pub fn new(axes: EmotionalAxes) -> Self {
        Self { axes }
    }

    /// Creates a new emotional state from individual axis values.
    #[allow(clippy::too_many_arguments)]
    pub fn with_axes(
        security_threat: f32,
        belonging_isolation: f32,
        agency_helplessness: f32,
        satiation_desperation: f32,
    ) -> Self {
        Self::new(EmotionalAxes::new(
            security_threat,
            belonging_isolation,
            agency_helplessness,
            satiation_desperation,
        ))
    }

    /// Creates a neutral emotional state (all axes at 0.0).
    pub fn neutral() -> Self {
        Self::new(EmotionalAxes::neutral())
    }

    /// Creates an emotional state from a single mood value.
    ///
    /// Maps the mood to all four axes equally for backward compatibility.
    /// This allows gradual migration from the single-axis mood system.
    pub fn from_mood(mood: f32) -> Self {
        Self::new(EmotionalAxes::from_mood(mood))
    }

    /// Returns the overall mood (average of all four axes).
    ///
    /// This is maintained for backward compatibility with systems
    /// that still use a single mood value.
    pub fn mood(&self) -> f32 {
        self.axes.to_mood()
    }

    /// Returns the security/threat axis value.
    pub fn security(&self) -> f32 {
        self.axes.security()
    }

    /// Returns the belonging/isolation axis value.
    pub fn belonging(&self) -> f32 {
        self.axes.belonging()
    }

    /// Returns the agency/helplessness axis value.
    pub fn agency(&self) -> f32 {
        self.axes.agency()
    }

    /// Returns the satiation/desperation axis value.
    pub fn satiation(&self) -> f32 {
        self.axes.satiation()
    }

    /// Applies the perception filter to a value based on mood and substrate stability.
    ///
    /// This is the original perception filter from Sprint 17.
    /// For the multi-axis system, use the axis-specific filters directly.
    ///
    /// An NPC in a negative emotional state perceives resource scarcity as more severe
    /// than it objectively is. The substrate's stability axis controls the strength of
    /// the distortion.
    ///
    /// For a need value (0.0 to 1.0 where 1.0 = fully satisfied):
    /// - Negative mood biases the perceived value downward (scarcity seems worse)
    /// - Positive mood biases the perceived value upward (things seem better)
    ///
    /// Defined in GAME_DESIGN_SECTION_4.md Section 4.1.2.
    pub fn perceive(&self, value: f32, substrate_stability: f32) -> f32 {
        // Clamp value to [0.0, 1.0] range
        let clamped_value = value.clamp(0.0, 1.0);

        // Calculate distortion factor based on mood and stability
        // Stability ranges from -1.0 (anxious) to +1.0 (stable)
        // We want anxiety to increase distortion, stability to decrease it
        // So we use (1.0 - stability) to get the distortion magnitude
        let distortion_magnitude = (1.0 - substrate_stability).abs();

        // Mood bias: negative mood = downward bias, positive mood = upward bias
        // The bias is scaled by distortion magnitude
        let bias = self.mood() * distortion_magnitude * 0.5; // 0.5 scaling factor for subtlety

        // Apply bias to the value
        (clamped_value + bias).clamp(0.0, 1.0)
    }

    /// Validates this emotional state.
    pub fn validate(&self) -> ValidationErrors {
        self.axes.validate()
    }
}

impl fmt::Display for EmotionalState {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(f, "EmotionalState {{ axes: {} }}", self.axes)
    }
}

impl Default for EmotionalState {
    fn default() -> Self {
        Self::neutral()
    }
}

/// Combined Layered Soul data for an NPC.
///
/// Contains both the substrate (Layer 1) and emotional state (Layer 2).
/// Layer 3 (Action Surface) is implemented in the utility scoring system.
///
/// Defined in GAME_DESIGN_SECTION_4.md Section 4.1.
#[derive(Debug, Clone, Copy, PartialEq, Serialize, Deserialize)]
pub struct LayeredSoul {
    /// The substrate (Layer 1) - stable traits.
    pub substrate: Substrate,
    /// The emotional state (Layer 2) - current emotional axes with perception filter.
    pub emotional_state: EmotionalState,
}

impl LayeredSoul {
    /// Creates a new layered soul with the given substrate and emotional state.
    pub fn new(substrate: Substrate, emotional_state: EmotionalState) -> Self {
        Self {
            substrate,
            emotional_state,
        }
    }

    /// Creates a neutral layered soul (all values at 0.0).
    pub fn neutral() -> Self {
        Self::new(Substrate::neutral(), EmotionalState::neutral())
    }

    /// Creates a layered soul from a seeded random generator.
    pub fn from_seed(seed: u64) -> Self {
        let substrate = Substrate::from_seed(seed);
        // Use a different seed for emotional state to ensure variation
        let mood_seed = seed.wrapping_add(12345);
        let mut rng = crate::DeterministicRng::new(mood_seed);
        let mood = rng.next_f32_range(-0.5, 0.5); // Start with mild mood variation
        let emotional_state = EmotionalState::from_mood(mood);
        Self::new(substrate, emotional_state)
    }

    /// Applies the perception filter to a value.
    ///
    /// Convenience method that delegates to the emotional state's perceive method.
    pub fn perceive(&self, value: f32) -> f32 {
        self.emotional_state
            .perceive(value, self.substrate.stability_anxiety)
    }

    /// Validates this layered soul.
    pub fn validate(&self) -> ValidationErrors {
        let mut errors = error_buffer();
        errors.extend(self.substrate.validate());
        errors.extend(self.emotional_state.validate());
        errors
    }
}

impl fmt::Display for LayeredSoul {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(
            f,
            "LayeredSoul {{ substrate: {}, emotional_state: {} }}",
            self.substrate, self.emotional_state
        )
    }
}

impl Default for LayeredSoul {
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
    fn test_substrate_neutral() {
        let substrate = Substrate::neutral();
        assert_eq!(substrate.courage_fear, 0.0);
        assert_eq!(substrate.generosity_selfishness, 0.0);
        assert_eq!(substrate.stability_anxiety, 0.0);
    }

    #[test]
    fn test_substrate_accessors() {
        let substrate = Substrate::new(0.5, -0.3, 0.8);
        assert_eq!(substrate.courage(), 0.5);
        assert_eq!(substrate.fear(), -0.5);
        assert_eq!(substrate.generosity(), -0.3);
        assert_eq!(substrate.selfishness(), 0.3);
        assert_eq!(substrate.stability(), 0.8);
        assert_eq!(substrate.anxiety(), -0.8);
    }

    #[test]
    fn test_substrate_validation() {
        let substrate = Substrate::new(0.5, -0.3, 0.8);
        assert!(substrate.validate().is_empty());
    }

    #[test]
    fn test_substrate_validation_invalid() {
        let substrate = Substrate::new(1.5, -0.3, 0.8); // Invalid courage
        let errors = substrate.validate();
        assert_eq!(errors.len(), 1);
        assert_eq!(errors[0].code().as_str(), "E174");
    }

    #[test]
    fn test_emotional_state_neutral() {
        let state = EmotionalState::neutral();
        assert_eq!(state.mood(), 0.0);
    }

    #[test]
    fn test_emotional_state_from_mood() {
        let state = EmotionalState::from_mood(0.5);
        assert!((state.mood() - 0.5).abs() < 0.001);
    }

    #[test]
    fn test_emotional_state_validation() {
        let state = EmotionalState::from_mood(0.5);
        assert!(state.validate().is_empty());
    }

    #[test]
    fn test_emotional_state_validation_invalid() {
        let axes = EmotionalAxes::new(1.5, 0.0, 0.0, 0.0);
        let state = EmotionalState::new(axes);
        let errors = state.validate();
        assert_eq!(errors.len(), 1);
        assert_eq!(errors[0].code().as_str(), "E187");
    }

    #[test]
    fn test_emotional_state_with_axes() {
        let state = EmotionalState::with_axes(0.5, -0.3, 0.8, -0.2);
        assert!((state.security() - 0.5).abs() < 0.001);
        assert!((state.belonging() - (-0.3)).abs() < 0.001);
        assert!((state.agency() - 0.8).abs() < 0.001);
        assert!((state.satiation() - (-0.2)).abs() < 0.001);
    }

    #[test]
    fn test_perception_filter_neutral() {
        let state = EmotionalState::from_mood(0.0);
        let substrate_stability = 0.0;

        // Neutral mood with neutral stability should not distort perception
        assert_eq!(state.perceive(0.5, substrate_stability), 0.5);
        assert_eq!(state.perceive(0.0, substrate_stability), 0.0);
        assert_eq!(state.perceive(1.0, substrate_stability), 1.0);
    }

    #[test]
    fn test_perception_filter_negative_mood() {
        let state = EmotionalState::from_mood(-0.8); // Strong negative mood
        let substrate_stability = 0.0; // Neutral stability

        // Negative mood should bias perception downward
        // A value of 0.5 should be perceived as lower than 0.5
        let perceived = state.perceive(0.5, substrate_stability);
        assert!(perceived < 0.5);
    }

    #[test]
    fn test_perception_filter_positive_mood() {
        let state = EmotionalState::from_mood(0.8); // Strong positive mood
        let substrate_stability = 0.0; // Neutral stability

        // Positive mood should bias perception upward
        // A value of 0.5 should be perceived as higher than 0.5
        let perceived = state.perceive(0.5, substrate_stability);
        assert!(perceived > 0.5);
    }

    #[test]
    fn test_perception_filter_stability_dampens() {
        let state = EmotionalState::from_mood(-0.8); // Strong negative mood
        let low_stability = -0.8; // High anxiety
        let high_stability = 0.8; // High stability

        // With high anxiety, mood should strongly distort perception
        let perceived_anxious = state.perceive(0.5, low_stability);
        // With high stability, mood should barely distort perception
        let perceived_stable = state.perceive(0.5, high_stability);

        // Anxious NPC should perceive lower than stable NPC
        assert!(perceived_anxious < perceived_stable);
    }

    #[test]
    fn test_perception_filter_clamping() {
        let state = EmotionalState::from_mood(-1.0); // Maximum negative mood
        let substrate_stability = -1.0; // Maximum anxiety

        // Even with extreme distortion, values should stay in [0.0, 1.0]
        let perceived = state.perceive(0.5, substrate_stability);
        assert!((0.0..=1.0).contains(&perceived));
    }

    #[test]
    fn test_layered_soul_neutral() {
        let soul = LayeredSoul::neutral();
        assert_eq!(soul.substrate.courage_fear, 0.0);
        assert_eq!(soul.emotional_state.mood(), 0.0);
    }

    #[test]
    fn test_layered_soul_perceive() {
        let substrate = Substrate::new(0.0, 0.0, 0.5); // Moderate stability
        let emotional_state = EmotionalState::from_mood(-0.5); // Negative mood
        let soul = LayeredSoul::new(substrate, emotional_state);

        // Should delegate to emotional_state.perceive
        let perceived = soul.perceive(0.5);
        assert!(perceived < 0.5); // Negative mood should bias downward
    }

    #[test]
    fn test_layered_soul_validation() {
        let soul = LayeredSoul::new(Substrate::neutral(), EmotionalState::neutral());
        assert!(soul.validate().is_empty());
    }

    #[test]
    fn test_layered_soul_validation_invalid() {
        let substrate = Substrate::new(1.5, 0.0, 0.0); // Invalid
        let emotional_state = EmotionalState::neutral();
        let soul = LayeredSoul::new(substrate, emotional_state);
        let errors = soul.validate();
        assert_eq!(errors.len(), 1);
        assert_eq!(errors[0].code().as_str(), "E174");
    }

    #[test]
    fn test_substrate_display() {
        let substrate = Substrate::new(0.5, -0.3, 0.8);
        let display = format!("{}", substrate);
        assert!(display.contains("courage: +0.50"));
        assert!(display.contains("generosity: -0.30"));
        assert!(display.contains("stability: +0.80"));
    }

    #[test]
    fn test_emotional_state_display() {
        let state = EmotionalState::from_mood(0.5);
        let display = format!("{}", state);
        assert!(display.contains("axes:"));
    }

    #[test]
    fn test_layered_soul_display() {
        let substrate = Substrate::new(0.5, -0.3, 0.8);
        let emotional_state = EmotionalState::from_mood(0.5);
        let soul = LayeredSoul::new(substrate, emotional_state);
        let display = format!("{}", soul);
        assert!(display.contains("substrate:"));
        assert!(display.contains("emotional_state:"));
    }

    #[test]
    fn test_emotional_state_default() {
        let state = EmotionalState::default();
        assert_eq!(state.mood(), 0.0);
    }

    #[test]
    fn test_layered_soul_default() {
        let soul = LayeredSoul::default();
        assert_eq!(soul.substrate.courage_fear, 0.0);
        assert_eq!(soul.emotional_state.mood(), 0.0);
    }
}
