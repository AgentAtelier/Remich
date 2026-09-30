//! Skill Domains
//!
//! Defines the seven broad skill domains for Forgeborn.
//! Each domain groups related affordances (perceptual or action capabilities).
//!
//! Defined in Sprint 18a design decisions.

use serde::{Deserialize, Serialize};
use std::fmt;

/// Skill domains - broad categories of capabilities.
///
/// Sprint 18a defines seven domains. New domains can be added without
/// refactoring the scoring pipeline, profile storage, or event system.
#[derive(Debug, Clone, Copy, PartialEq, Eq, PartialOrd, Ord, Hash, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
#[non_exhaustive]
pub enum SkillDomain {
    /// Carpentry, carving, joinery, tool handling.
    Woodcraft,
    /// Masonry, quarrying, ore extraction, carving.
    Stonework,
    /// Farming, planting, harvesting, soil management.
    Husbandry,
    /// Navigation, tracking, route-finding, landmark recognition.
    Pathfinding,
    /// Plant identification, gathering, fishing, trapping.
    Foraging,
    /// Reading clouds, wind, precipitation, precursor signals.
    WeatherSense,
    /// Storytelling, negotiation, conflict resolution, emotional labour.
    SocialWeaving,
}

impl fmt::Display for SkillDomain {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            SkillDomain::Woodcraft => write!(f, "woodcraft"),
            SkillDomain::Stonework => write!(f, "stonework"),
            SkillDomain::Husbandry => write!(f, "husbandry"),
            SkillDomain::Pathfinding => write!(f, "pathfinding"),
            SkillDomain::Foraging => write!(f, "foraging"),
            SkillDomain::WeatherSense => write!(f, "weather_sense"),
            SkillDomain::SocialWeaving => write!(f, "social_weaving"),
        }
    }
}

impl SkillDomain {
    /// Returns all skill domains.
    pub fn all() -> &'static [SkillDomain] {
        &[
            SkillDomain::Woodcraft,
            SkillDomain::Stonework,
            SkillDomain::Husbandry,
            SkillDomain::Pathfinding,
            SkillDomain::Foraging,
            SkillDomain::WeatherSense,
            SkillDomain::SocialWeaving,
        ]
    }

    /// Returns the domain from a string representation.
    pub fn from_str_name(s: &str) -> Option<SkillDomain> {
        match s {
            "woodcraft" => Some(SkillDomain::Woodcraft),
            "stonework" => Some(SkillDomain::Stonework),
            "husbandry" => Some(SkillDomain::Husbandry),
            "pathfinding" => Some(SkillDomain::Pathfinding),
            "foraging" => Some(SkillDomain::Foraging),
            "weather_sense" => Some(SkillDomain::WeatherSense),
            "social_weaving" => Some(SkillDomain::SocialWeaving),
            _ => None,
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_skill_domain_display() {
        assert_eq!(format!("{}", SkillDomain::Woodcraft), "woodcraft");
        assert_eq!(format!("{}", SkillDomain::Stonework), "stonework");
        assert_eq!(format!("{}", SkillDomain::Husbandry), "husbandry");
        assert_eq!(format!("{}", SkillDomain::Pathfinding), "pathfinding");
        assert_eq!(format!("{}", SkillDomain::Foraging), "foraging");
        assert_eq!(format!("{}", SkillDomain::WeatherSense), "weather_sense");
        assert_eq!(format!("{}", SkillDomain::SocialWeaving), "social_weaving");
    }

    #[test]
    fn test_skill_domain_all() {
        let domains = SkillDomain::all();
        assert_eq!(domains.len(), 7);
    }

    #[test]
    fn test_skill_domain_from_str_name() {
        assert_eq!(SkillDomain::from_str_name("woodcraft"), Some(SkillDomain::Woodcraft));
        assert_eq!(SkillDomain::from_str_name("nonexistent"), None);
    }
}
