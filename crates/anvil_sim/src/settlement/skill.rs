//! NPC skill types.
//!
//! Placeholder for future NPC skill system expansion.

use serde::{Deserialize, Serialize};
use std::fmt;

/// A placeholder for NPC skills. Will be expanded in future sprints.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, Hash)]
#[serde(rename_all = "snake_case")]
#[non_exhaustive]
pub enum Skill {
    /// Ability to play a musical instrument.
    Musician,
    /// Ability to tell stories effectively.
    Storyteller,
    /// Ability to build and repair structures.
    Builder,
    /// Ability to heal and tend to the injured.
    Healer,
    /// Ability to farm and gather food.
    Farmer,
}

impl fmt::Display for Skill {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Skill::Musician => write!(f, "musician"),
            Skill::Storyteller => write!(f, "storyteller"),
            Skill::Builder => write!(f, "builder"),
            Skill::Healer => write!(f, "healer"),
            Skill::Farmer => write!(f, "farmer"),
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
    fn test_skill_display() {
        assert_eq!(format!("{}", Skill::Musician), "musician");
        assert_eq!(format!("{}", Skill::Storyteller), "storyteller");
        assert_eq!(format!("{}", Skill::Builder), "builder");
        assert_eq!(format!("{}", Skill::Healer), "healer");
        assert_eq!(format!("{}", Skill::Farmer), "farmer");
    }
}
