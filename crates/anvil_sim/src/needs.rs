//! NPC Needs system for Forgeborn.
//!
//! Defines the seven needs that drive NPC behaviour as specified in
//! GAME_DESIGN_SECTION_4.md Section 4.4.1.

use anvil_core::{ValidationErrors};
use serde::{Deserialize, Serialize};
use std::fmt;

/// The seven needs that drive all NPC behaviour.
///
/// Each need is a value from 0.0 (completely unsatisfied) to 1.0 (fully satisfied).
/// Needs decay over time at different rates.
///
/// Defined in GAME_DESIGN_SECTION_4.md Section 4.4.1.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize, Hash)]
#[serde(rename_all = "snake_case")]
#[non_exhaustive]
pub enum Need {
    /// Food need - moderate decay, depleted by time and exertion.
    /// Satisfied by eating from communal stores.
    Food,
    /// Water need - moderate-fast decay, depleted by heat and exertion.
    /// Satisfied by drinking from well, river, or stores.
    Water,
    /// Shelter need - slow decay unless exposed to weather.
    /// Satisfied by being in an intact building.
    Shelter,
    /// Safety need - context-dependent, driven by threats and precursors.
    /// Satisfied by distance from threat, being in a group, being indoors.
    Safety,
    /// Sleep need - slow decay while awake.
    /// Satisfied by sleeping in shelter.
    Sleep,
    /// Companionship need - slow decay while alone.
    /// Satisfied by being near connected NPCs, conversation, communal activity.
    Companionship,
    /// Joy need - very slow decay, natural drift toward neutral.
    /// **Cannot be directly satisfied by any action.** Only CatalystEvents produce joy.
    /// This enforces Principle 7 (Design Constraint 12).
    Joy,
}

impl fmt::Display for Need {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Need::Food => write!(f, "food"),
            Need::Water => write!(f, "water"),
            Need::Shelter => write!(f, "shelter"),
            Need::Safety => write!(f, "safety"),
            Need::Sleep => write!(f, "sleep"),
            Need::Companionship => write!(f, "companionship"),
            Need::Joy => write!(f, "joy"),
        }
    }
}

impl Need {
    /// Returns the decay rate for this need per simulation tick.
    ///
    /// These are suggested starting values from GAME_DESIGN_SECTION_4.md Section 4.4.1.
    /// Actual values may need tuning during gameplay balancing.
    pub fn decay_rate(&self) -> f32 {
        match self {
            Need::Food => 0.0001,      // Moderate decay
            Need::Water => 0.00015,    // Moderate-fast decay
            Need::Shelter => 0.00005,  // Slow decay
            Need::Safety => 0.0,        // Context-dependent, not time-based
            Need::Sleep => 0.00007,    // Slow decay
            Need::Companionship => 0.00006, // Slow decay
            Need::Joy => 0.00002,      // Very slow decay (natural drift)
        }
    }

    /// Returns whether this need can be directly satisfied by actions.
    /// Joy cannot be directly satisfied - it only comes from CatalystEvents.
    pub fn can_be_satisfied(&self) -> bool {
        !matches!(self, Need::Joy)
    }

    /// Validates this need.
    pub fn validate(&self) -> ValidationErrors {
        // Needs are enum variants, always valid
        Vec::new()
    }
}

/// Decay rates as tunable constants for the seven needs.
///
/// These can be adjusted during gameplay balancing without changing the Need enum.
#[derive(Debug, Clone)]
pub struct NeedDecayRates {
    /// Food decay rate per tick.
    pub food: f32,
    /// Water decay rate per tick.
    pub water: f32,
    /// Shelter decay rate per tick.
    pub shelter: f32,
    /// Safety decay rate per tick (typically 0, context-dependent).
    pub safety: f32,
    /// Sleep decay rate per tick.
    pub sleep: f32,
    /// Companionship decay rate per tick.
    pub companionship: f32,
    /// Joy decay rate per tick.
    pub joy: f32,
}

impl Default for NeedDecayRates {
    fn default() -> Self {
        Self {
            food: Need::Food.decay_rate(),
            water: Need::Water.decay_rate(),
            shelter: Need::Shelter.decay_rate(),
            safety: Need::Safety.decay_rate(),
            sleep: Need::Sleep.decay_rate(),
            companionship: Need::Companionship.decay_rate(),
            joy: Need::Joy.decay_rate(),
        }
    }
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_need_display() {
        assert_eq!(format!("{}", Need::Food), "food");
        assert_eq!(format!("{}", Need::Water), "water");
        assert_eq!(format!("{}", Need::Shelter), "shelter");
        assert_eq!(format!("{}", Need::Safety), "safety");
        assert_eq!(format!("{}", Need::Sleep), "sleep");
        assert_eq!(format!("{}", Need::Companionship), "companionship");
        assert_eq!(format!("{}", Need::Joy), "joy");
    }

    #[test]
    fn test_need_decay_rates() {
        // Joy should have the slowest decay
        assert!(Need::Joy.decay_rate() < Need::Food.decay_rate());
        assert!(Need::Joy.decay_rate() < Need::Water.decay_rate());

        // Water should decay faster than food
        assert!(Need::Water.decay_rate() > Need::Food.decay_rate());

        // Safety should have zero decay (context-dependent)
        assert_eq!(Need::Safety.decay_rate(), 0.0);
    }

    #[test]
    fn test_joy_cannot_be_satisfied() {
        assert!(!Need::Joy.can_be_satisfied());
        assert!(Need::Food.can_be_satisfied());
        assert!(Need::Water.can_be_satisfied());
        assert!(Need::Shelter.can_be_satisfied());
        assert!(Need::Safety.can_be_satisfied());
        assert!(Need::Sleep.can_be_satisfied());
        assert!(Need::Companionship.can_be_satisfied());
    }

    #[test]
    fn test_need_validation() {
        let errors = Need::Food.validate();
        assert!(errors.is_empty());
    }

    #[test]
    fn test_need_decay_rates_default() {
        let rates = NeedDecayRates::default();
        assert_eq!(rates.food, Need::Food.decay_rate());
        assert_eq!(rates.water, Need::Water.decay_rate());
        assert_eq!(rates.shelter, Need::Shelter.decay_rate());
    }
}
