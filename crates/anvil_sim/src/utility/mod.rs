//! Utility scoring system for NPC action selection.
//!
//! Implements the utility-AI system as specified in GAME_DESIGN_SECTION_4.md Section 4.4.3.
//! This is the Action Surface (Layer 3) of the Layered Soul model.

pub mod scoring;

pub use scoring::{
    base_urgency, cooperation_modifier, coping_modifier, perception_filter,
    skill_modifier, substrate_weight, time_block_multiplier, UtilityScore,
};
