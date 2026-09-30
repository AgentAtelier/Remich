//! Skill System Module
//!
//! Implements the skill infrastructure for Forgeborn as specified in Sprint 18a.
//! Contains skill domains, affordances, profiles, and practice/decay mechanics.
//!
//! Defined in GAME_DESIGN_SECTION_4.md Section 4.8 (Design Constraints).

pub mod affordance;
pub mod domain;

pub use affordance::{Affordance, AffordanceId, MaturityState, ToolClass, PlaceTag, DEFAULT_UNLOCK_THRESHOLD};
pub use domain::SkillDomain;
