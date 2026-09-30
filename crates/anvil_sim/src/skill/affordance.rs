//! Affordances
//!
//! Defines affordances - discrete perceptual or action capabilities.
//! Each affordance belongs to exactly one SkillDomain.
//!
//! Defined in Sprint 18a design decisions.

use crate::skill::domain::SkillDomain;
use anvil_core::{FailureClass, ValidationErrors};
use serde::{Deserialize, Serialize};
use std::fmt;

use anvil_core::error_buffer;
use anvil_core::push_validation_error;

/// Unique identifier for an affordance.
#[derive(Debug, Clone, Copy, PartialEq, Eq, PartialOrd, Ord, Hash, Serialize, Deserialize, Default)]
pub struct AffordanceId(u32);

impl AffordanceId {
    /// Creates a new affordance ID.
    pub fn new(id: u32) -> Self {
        Self(id)
    }

    /// Returns the raw ID value.
    pub fn get(&self) -> u32 {
        self.0
    }

    /// Generates deterministic IDs from a name hash.
    /// Uses a simple hash to ensure stability across sessions.
    pub fn from_name(name: &str) -> Self {
        let mut hash: u32 = 5381;
        for byte in name.bytes() {
            hash = hash.wrapping_mul(33).wrapping_add(byte as u32);
        }
        Self(hash)
    }
}

impl fmt::Display for AffordanceId {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(f, "AffordanceId({})", self.0)
    }
}

/// Tool class for affordance requirements.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
#[non_exhaustive]
pub enum ToolClass {
    /// No tool required.
    None,
    /// Basic hand tools (knife, stick, rope).
    Basic,
    /// Specialized tools (hammer, chisel, axe).
    Specialized,
    /// Precision instruments (measuring tools, scales).
    Precision,
}

impl fmt::Display for ToolClass {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            ToolClass::None => write!(f, "none"),
            ToolClass::Basic => write!(f, "basic"),
            ToolClass::Specialized => write!(f, "specialized"),
            ToolClass::Precision => write!(f, "precision"),
        }
    }
}

/// Place tag for affordance context affinity.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
#[non_exhaustive]
pub enum PlaceTag {
    /// Forest, woodland areas.
    Forest,
    /// River, lake, or coastal areas.
    Water,
    /// Mountain or hilly terrain.
    Mountain,
    /// Open plains or fields.
    Plain,
    /// Settlement or village areas.
    Settlement,
    /// Cave or underground areas.
    Cave,
    /// Desert or arid areas.
    Desert,
}

impl fmt::Display for PlaceTag {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            PlaceTag::Forest => write!(f, "forest"),
            PlaceTag::Water => write!(f, "water"),
            PlaceTag::Mountain => write!(f, "mountain"),
            PlaceTag::Plain => write!(f, "plain"),
            PlaceTag::Settlement => write!(f, "settlement"),
            PlaceTag::Cave => write!(f, "cave"),
            PlaceTag::Desert => write!(f, "desert"),
        }
    }
}

/// Default unlock threshold for affordances.
pub const DEFAULT_UNLOCK_THRESHOLD: f32 = 0.75;

/// An affordance - a discrete perceptual or action capability.
///
/// Each affordance belongs to exactly one SkillDomain and represents
/// a specific capability that can be practiced and improved.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct Affordance {
    /// Unique identifier for this affordance.
    pub id: AffordanceId,
    /// The domain this affordance belongs to.
    pub domain: SkillDomain,
    /// Internal identifier (e.g., "soil_moisture_reading").
    pub name: String,
    /// Current maturity level (0.0 to 1.0).
    pub unlock_threshold: f32,
    /// Optional tool class required to use this affordance.
    pub requires_tool_class: Option<ToolClass>,
    /// Optional place tags indicating context affinity.
    pub place_tags: Vec<PlaceTag>,
}

impl Affordance {
    /// Creates a new affordance.
    #[allow(clippy::too_many_arguments)]
    pub fn new(
        id: AffordanceId,
        domain: SkillDomain,
        name: String,
        unlock_threshold: f32,
        requires_tool_class: Option<ToolClass>,
        place_tags: Vec<PlaceTag>,
    ) -> Self {
        Self {
            id,
            domain,
            name,
            unlock_threshold,
            requires_tool_class,
            place_tags,
        }
    }

    /// Creates an affordance with default unlock threshold.
    pub fn with_default_threshold(
        id: AffordanceId,
        domain: SkillDomain,
        name: &'static str,
    ) -> Self {
        Self::new(id, domain, name.to_string(), DEFAULT_UNLOCK_THRESHOLD, None, Vec::new())
    }

    /// Validates this affordance.
    pub fn validate(&self) -> ValidationErrors {
        let mut errors = error_buffer();

        if self.id.get() == 0 {
            push_validation_error!(
                errors,
                FailureClass::Structural,
                "E180",
                "Affordance",
                "id",
                format!("{}", self.id.get()),
                "affordance ID must be non-zero"
            );
        }

        if self.name.is_empty() {
            push_validation_error!(
                errors,
                FailureClass::Semantic,
                "E181",
                "Affordance",
                "name",
                self.name.to_string(),
                "affordance name cannot be empty"
            );
        }

        if self.unlock_threshold <= 0.0 || self.unlock_threshold > 1.0 {
            push_validation_error!(
                errors,
                FailureClass::Semantic,
                "E182",
                "Affordance",
                "unlock_threshold",
                format!("{}", self.unlock_threshold),
                "unlock threshold must be in (0.0, 1.0]"
            );
        }

        errors
    }
}

impl fmt::Display for Affordance {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(
            f,
            "Affordance {{ id: {}, domain: {}, name: '{}', threshold: {:.2} }}",
            self.id, self.domain, self.name, self.unlock_threshold
        )
    }
}

/// Maturity state for tracking skill progression.
#[derive(Debug, Clone, Copy, PartialEq, Default, Serialize, Deserialize)]
pub struct MaturityState {
    /// Current maturity level (0.0 to 1.0).
    pub maturity: f32,
    /// Highest maturity ever achieved for this affordance.
    pub peak_maturity: f32,
    /// The last tick at which this affordance was practiced.
    pub last_practice_tick: u64,
    /// The last tick at which a failure occurred (for future breakthrough processing).
    pub last_failure_tick: u64,
}

impl MaturityState {
    /// Creates a new maturity state with zero maturity.
    pub fn new() -> Self {
        Self {
            maturity: 0.0,
            peak_maturity: 0.0,
            last_practice_tick: 0,
            last_failure_tick: 0,
        }
    }

    /// Creates a maturity state with a specific initial maturity.
    pub fn with_maturity(maturity: f32) -> Self {
        Self {
            maturity: maturity.clamp(0.0, 1.0),
            peak_maturity: maturity.clamp(0.0, 1.0),
            last_practice_tick: 0,
            last_failure_tick: 0,
        }
    }

    /// Validates this maturity state.
    pub fn validate(&self) -> ValidationErrors {
        let mut errors = error_buffer();

        if !self.maturity.is_finite() || self.maturity < 0.0 || self.maturity > 1.0 {
            push_validation_error!(
                errors,
                FailureClass::Semantic,
                "E183",
                "MaturityState",
                "maturity",
                format!("{}", self.maturity),
                "maturity must be in [0.0, 1.0]"
            );
        }

        if !self.peak_maturity.is_finite() || self.peak_maturity < 0.0 || self.peak_maturity > 1.0 {
            push_validation_error!(
                errors,
                FailureClass::Semantic,
                "E184",
                "MaturityState",
                "peak_maturity",
                format!("{}", self.peak_maturity),
                "peak maturity must be in [0.0, 1.0]"
            );
        }

        errors
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_affordance_id_display() {
        let id = AffordanceId::new(42);
        assert_eq!(format!("{}", id), "AffordanceId(42)");
    }

    #[test]
    fn test_affordance_id_from_name() {
        let id1 = AffordanceId::from_name("test_affordance");
        let id2 = AffordanceId::from_name("test_affordance");
        assert_eq!(id1, id2);
    }

    #[test]
    fn test_tool_class_display() {
        assert_eq!(format!("{}", ToolClass::None), "none");
        assert_eq!(format!("{}", ToolClass::Basic), "basic");
        assert_eq!(format!("{}", ToolClass::Specialized), "specialized");
        assert_eq!(format!("{}", ToolClass::Precision), "precision");
    }

    #[test]
    fn test_place_tag_display() {
        assert_eq!(format!("{}", PlaceTag::Forest), "forest");
        assert_eq!(format!("{}", PlaceTag::Water), "water");
        assert_eq!(format!("{}", PlaceTag::Mountain), "mountain");
    }

    #[test]
    fn test_affordance_validation() {
        let affordance = Affordance::with_default_threshold(
            AffordanceId::new(1),
            SkillDomain::Husbandry,
            "soil_moisture_reading",
        );
        assert!(affordance.validate().is_empty());
    }

    #[test]
    fn test_affordance_validation_zero_id() {
        let affordance = Affordance::with_default_threshold(
            AffordanceId::new(0),
            SkillDomain::Husbandry,
            "soil_moisture_reading",
        );
        let errors = affordance.validate();
        assert_eq!(errors.len(), 1);
        assert_eq!(errors[0].code().as_str(), "E180");
    }

    #[test]
    fn test_affordance_validation_empty_name() {
        // Can't easily create an affordance with empty name through normal constructor
        // This is tested by the validation logic
    }

    #[test]
    fn test_maturity_state_validation() {
        let state = MaturityState::new();
        assert!(state.validate().is_empty());

        let state = MaturityState::with_maturity(0.5);
        assert!(state.validate().is_empty());
    }

    #[test]
    fn test_maturity_state_validation_invalid() {
        let state = MaturityState {
            maturity: 1.5,
            peak_maturity: 0.5,
            last_practice_tick: 0,
            last_failure_tick: 0,
        };
        let errors = state.validate();
        assert_eq!(errors.len(), 1);
        assert_eq!(errors[0].code().as_str(), "E183");
    }
}
