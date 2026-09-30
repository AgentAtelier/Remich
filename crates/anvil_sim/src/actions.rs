//! NPC Action catalogue for Forgeborn.
//!
//! Defines the ~21 actions that NPCs can perform to satisfy their needs.
//! Each action has metadata that drives the utility scoring system.
//!
//! Defined in GAME_DESIGN_SECTION_4.md Section 4.4.2.

use crate::age::AgeCategory;
use crate::needs::Need;
use crate::skill::AffordanceId;
use anvil_core::{FailureClass, ValidationErrors};
use serde::{Deserialize, Serialize};
use std::fmt;

use anvil_core::error_buffer;
use anvil_core::push_validation_error;

/// Time blocks for action scheduling.
///
/// Static blocks per Section 4.3.1. Sigmoid curves deferred to Sprint 18.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize, Hash)]
#[serde(rename_all = "snake_case")]
#[non_exhaustive]
pub enum TimeBlock {
    /// Dawn - pre-dawn to mid-morning (0.2-0.35 in day cycle).
    /// Highest energy, physical work begins.
    Dawn,
    /// Day - mid-morning to late afternoon (0.35-0.7 in day cycle).
    /// Peak productivity, social interaction, trade.
    Day,
    /// Dusk - late afternoon to nightfall (0.7-0.85 in day cycle).
    /// Work winds down, communal meals, gathering.
    Dusk,
    /// Night - nightfall to pre-dawn (0.85-0.2 in day cycle).
    /// Rest, sleep, stories by fire, reduced activity.
    Night,
    /// Anytime - no time preference.
    Anytime,
}

impl fmt::Display for TimeBlock {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            TimeBlock::Dawn => write!(f, "dawn"),
            TimeBlock::Day => write!(f, "day"),
            TimeBlock::Dusk => write!(f, "dusk"),
            TimeBlock::Night => write!(f, "night"),
            TimeBlock::Anytime => write!(f, "anytime"),
        }
    }
}

impl TimeBlock {
    /// Returns the time range for this block as (start, end) in [0.0, 1.0] day cycle.
    pub fn time_range(&self) -> (f32, f32) {
        match self {
            TimeBlock::Dawn => (0.2, 0.35),
            TimeBlock::Day => (0.35, 0.7),
            TimeBlock::Dusk => (0.7, 0.85),
            TimeBlock::Night => (0.85, 1.0),
            TimeBlock::Anytime => (0.0, 1.0),
        }
    }

    /// Returns the utility multiplier for this block at a given time of day.
    ///
    /// time_of_day is a value from 0.0 (midnight) to 1.0 (next midnight).
    pub fn multiplier(&self, time_of_day: f32) -> f32 {
        // Handle wrap-around for Night block
        if *self == TimeBlock::Night {
            if !(0.2..0.85).contains(&time_of_day) {
                return 1.0;
            }
            return 0.2;
        }

        let (start, end) = self.time_range();
        if time_of_day >= start && time_of_day < end {
            1.0
        } else {
            0.2
        }
    }
}

/// Coping types for actions that help the settlement cope with catastrophes.
///
/// Defined in GAME_DESIGN_SECTION_3.md Section 3.3.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize, Hash)]
#[serde(rename_all = "snake_case")]
#[non_exhaustive]
pub enum CopingType {
    /// Material coping - directly addresses physical threats.
    Material,
    /// Emotional coping - addresses psychological well-being.
    Emotional,
    /// No coping function.
    None,
}

impl fmt::Display for CopingType {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            CopingType::Material => write!(f, "material"),
            CopingType::Emotional => write!(f, "emotional"),
            CopingType::None => write!(f, "none"),
        }
    }
}

/// Resource pools that actions can affect.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize, Hash)]
#[serde(rename_all = "snake_case")]
#[non_exhaustive]
pub enum ResourcePool {
    /// Food store pool.
    Food,
    /// Water pool.
    Water,
    /// Materials pool (aggregated timber/stone/cloth/tools).
    Materials,
    /// Structural integrity pool.
    StructuralIntegrity,
}

impl fmt::Display for ResourcePool {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            ResourcePool::Food => write!(f, "food"),
            ResourcePool::Water => write!(f, "water"),
            ResourcePool::Materials => write!(f, "materials"),
            ResourcePool::StructuralIntegrity => write!(f, "structural_integrity"),
        }
    }
}

/// The effect an action has on resource pools.
#[derive(Debug, Clone, Copy, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum ResourceEffect {
    /// Produces the specified resource at the given base rate per tick.
    Produce {
        /// The resource pool to produce into.
        pool: ResourcePool,
        /// The base production rate per tick (0.0 to 1.0).
        rate: f32,
    },
    /// Consumes the specified resource at the given base rate per tick.
    Consume {
        /// The resource pool to consume from.
        pool: ResourcePool,
        /// The base consumption rate per tick (0.0 to 1.0).
        rate: f32,
    },
}

impl ResourceEffect {
    /// Validates this resource effect.
    pub fn validate(&self) -> ValidationErrors {
        let mut errors = error_buffer();

        let rate = match self {
            ResourceEffect::Produce { rate, .. } => rate,
            ResourceEffect::Consume { rate, .. } => rate,
        };

        if !rate.is_finite() || *rate < 0.0 || *rate > 1.0 {
            push_validation_error!(
                errors,
                FailureClass::Semantic,
                "E170",
                "ResourceEffect",
                "rate",
                format!("{}", rate),
                "rate must be in [0.0, 1.0]"
            );
        }

        errors
    }
}

/// Metadata for an action in the catalogue.
///
/// Defined in GAME_DESIGN_SECTION_4.md Section 4.4.2.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct Action {
    /// Unique identifier for this action.
    pub id: u64,
    /// Human-readable name of the action.
    pub name: String,
    /// The primary need this action serves.
    pub primary_need: Need,
    /// Minimum age category that can perform this action.
    pub min_age_category: AgeCategory,
    /// Whether this action provides communal benefit (triggers cooperation modifier).
    pub communal_benefit: bool,
    /// Whether this action requires spatial movement (major action) vs in-place (minor action).
    pub is_major: bool,
    /// The coping type of this action.
    pub coping_type: CopingType,
    /// The resource effect of this action, if any.
    pub resource_effect: Option<ResourceEffect>,
    /// The preferred time blocks for this action.
    pub time_preference: TimeBlock,
    /// The base duration of this action in ticks.
    pub duration_ticks: u64,
    /// The primary affordance ID this action exercises (Sprint 18a).
    /// Maps each action to the most relevant affordance for skill progression.
    pub primary_affordance_id: Option<AffordanceId>,
    /// Minimum physical capability required to perform this action (Sprint 18c).
    /// Actions with higher physical requirements (e.g., heavy lifting) require
    /// higher physical capability. Value ranges from 0.0 to 1.0.
    pub min_physical_capability: f32,
}

impl Action {
    /// Creates a new action.
    #[allow(clippy::too_many_arguments)]
    pub fn new(
        id: u64,
        name: String,
        primary_need: Need,
        min_age_category: AgeCategory,
        communal_benefit: bool,
        is_major: bool,
        coping_type: CopingType,
        resource_effect: Option<ResourceEffect>,
        time_preference: TimeBlock,
        duration_ticks: u64,
        primary_affordance_id: Option<AffordanceId>,
        min_physical_capability: f32,
    ) -> Self {
        Self {
            id,
            name,
            primary_need,
            min_age_category,
            communal_benefit,
            is_major,
            coping_type,
            resource_effect,
            time_preference,
            duration_ticks,
            primary_affordance_id,
            min_physical_capability,
        }
    }

    /// Validates this action.
    pub fn validate(&self) -> ValidationErrors {
        let mut errors = error_buffer();

        if self.id == 0 {
            push_validation_error!(
                errors,
                FailureClass::Structural,
                "E171",
                "Action",
                "id",
                format!("{}", self.id),
                "action ID must be non-zero"
            );
        }

        if self.name.trim().is_empty() {
            push_validation_error!(
                errors,
                FailureClass::Semantic,
                "E172",
                "Action",
                "name",
                self.name.clone(),
                "action name cannot be empty"
            );
        }

        if self.duration_ticks == 0 {
            push_validation_error!(
                errors,
                FailureClass::Semantic,
                "E173",
                "Action",
                "duration_ticks",
                format!("{}", self.duration_ticks),
                "duration must be positive"
            );
        }

        if let Some(effect) = &self.resource_effect {
            errors.extend(effect.validate());
        }

        if !self.min_physical_capability.is_finite() || self.min_physical_capability < 0.0 || self.min_physical_capability > 1.0 {
            push_validation_error!(
                errors,
                FailureClass::Semantic,
                "E173b",
                "Action",
                "min_physical_capability",
                format!("{}", self.min_physical_capability),
                "min_physical_capability must be in [0.0, 1.0]"
            );
        }

        errors
    }
}

impl fmt::Display for Action {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(
            f,
            "Action {{ id: {}, name: '{}', need: {}, duration: {} ticks, affordance: {:?} }}",
            self.id, self.name, self.primary_need, self.duration_ticks, self.primary_affordance_id
        )
    }
}

// Catalogue module - defined in separate file
pub mod catalogue;

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_age_category_display() {
        assert_eq!(format!("{}", AgeCategory::Child), "child");
        assert_eq!(format!("{}", AgeCategory::Adult), "adult");
        assert_eq!(format!("{}", AgeCategory::Elder), "elder");
        assert_eq!(format!("{}", AgeCategory::All), "all");
    }

    #[test]
    fn test_time_block_display() {
        assert_eq!(format!("{}", TimeBlock::Dawn), "dawn");
        assert_eq!(format!("{}", TimeBlock::Day), "day");
        assert_eq!(format!("{}", TimeBlock::Dusk), "dusk");
        assert_eq!(format!("{}", TimeBlock::Night), "night");
        assert_eq!(format!("{}", TimeBlock::Anytime), "anytime");
    }

    #[test]
    fn test_time_block_multiplier() {
        assert_eq!(TimeBlock::Dawn.multiplier(0.25), 1.0);
        assert_eq!(TimeBlock::Dawn.multiplier(0.5), 0.2);

        assert_eq!(TimeBlock::Day.multiplier(0.5), 1.0);
        assert_eq!(TimeBlock::Day.multiplier(0.2), 0.2);

        assert_eq!(TimeBlock::Night.multiplier(0.9), 1.0);
        assert_eq!(TimeBlock::Night.multiplier(0.1), 1.0);
        assert_eq!(TimeBlock::Night.multiplier(0.5), 0.2);

        assert_eq!(TimeBlock::Anytime.multiplier(0.0), 1.0);
        assert_eq!(TimeBlock::Anytime.multiplier(0.5), 1.0);
        assert_eq!(TimeBlock::Anytime.multiplier(0.9), 1.0);
    }

    #[test]
    fn test_coping_type_display() {
        assert_eq!(format!("{}", CopingType::Material), "material");
        assert_eq!(format!("{}", CopingType::Emotional), "emotional");
        assert_eq!(format!("{}", CopingType::None), "none");
    }

    #[test]
    fn test_resource_pool_display() {
        assert_eq!(format!("{}", ResourcePool::Food), "food");
        assert_eq!(format!("{}", ResourcePool::Water), "water");
        assert_eq!(format!("{}", ResourcePool::Materials), "materials");
        assert_eq!(
            format!("{}", ResourcePool::StructuralIntegrity),
            "structural_integrity"
        );
    }

    #[test]
    fn test_resource_effect_validation() {
        let effect = ResourceEffect::Produce {
            pool: ResourcePool::Food,
            rate: 0.5,
        };
        assert!(effect.validate().is_empty());

        let effect = ResourceEffect::Produce {
            pool: ResourcePool::Food,
            rate: 1.5,
        };
        let errors = effect.validate();
        assert_eq!(errors.len(), 1);
        assert_eq!(errors[0].code().as_str(), "E170");
    }

    #[test]
    fn test_action_validation() {
        let action = Action::new(
            1,
            "Test".to_string(),
            Need::Food,
            AgeCategory::Adult,
            true,
            false,
            CopingType::None,
            None,
            TimeBlock::Anytime,
            30,
            None,
            0.5, // min_physical_capability
        );
        assert!(action.validate().is_empty());
    }

    #[test]
    fn test_action_validation_zero_id() {
        let action = Action::new(
            0,
            "Test".to_string(),
            Need::Food,
            AgeCategory::Adult,
            true,
            false,
            CopingType::None,
            None,
            TimeBlock::Anytime,
            30,
            None,
            0.5, // min_physical_capability
        );
        let errors = action.validate();
        assert_eq!(errors.len(), 1);
        assert_eq!(errors[0].code().as_str(), "E171");
    }

    #[test]
    fn test_action_validation_empty_name() {
        let action = Action::new(
            1,
            "".to_string(),
            Need::Food,
            AgeCategory::Adult,
            true,
            false,
            CopingType::None,
            None,
            TimeBlock::Anytime,
            30,
            None,
            0.5, // min_physical_capability
        );
        let errors = action.validate();
        assert_eq!(errors.len(), 1);
        assert_eq!(errors[0].code().as_str(), "E172");
    }

    #[test]
    fn test_action_catalogue() {
        let actions = catalogue::actions();
        // 21 original actions + 5 child-specific actions = 26 (Sprint 18c Task 4)
        assert_eq!(actions.len(), 26);
        assert!(actions.iter().all(|a| a.primary_need != Need::Joy));
    }

    #[test]
    fn test_actions_for_need() {
        let food_actions = catalogue::actions_for_need(Need::Food);
        assert!(!food_actions.is_empty());
        assert!(food_actions.iter().all(|a| a.primary_need == Need::Food));
    }

    #[test]
    fn test_action_by_id() {
        let action = catalogue::action_by_id(1);
        assert!(action.is_some());
        assert_eq!(action.unwrap().name, "Farm/Tend");

        let action = catalogue::action_by_id(999);
        assert!(action.is_none());
    }
}
