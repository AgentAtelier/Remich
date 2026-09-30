use serde::{Deserialize, Serialize};
use std::fmt;

/// The type of a disaster that damaged a landmark.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
#[non_exhaustive]
pub enum DamageType {
    /// Seismic ground shaking.
    Earthquake,
    /// Combustion event.
    Fire,
    /// Water inundation.
    Flood,
    /// Prolonged water shortage.
    Drought,
    /// Volcanic eruption.
    Volcanic,
    /// Gradual wearing away of land.
    Erosion,
}

impl DamageType {
    /// Human-readable label (kept for backward compatibility; calls Display).
    #[deprecated = "Use Display instead: format!(\"{}\", value)"]
    pub fn label(self) -> &'static str {
        // This function is no longer called internally.
        // Keep for external backward compatibility only.
        match self {
            DamageType::Earthquake => "earthquake",
            DamageType::Fire => "fire",
            DamageType::Flood => "flood",
            DamageType::Drought => "drought",
            DamageType::Volcanic => "volcanic",
            DamageType::Erosion => "erosion",
        }
    }
}

impl fmt::Display for DamageType {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        let s = match self {
            DamageType::Earthquake => "earthquake",
            DamageType::Fire => "fire",
            DamageType::Flood => "flood",
            DamageType::Drought => "drought",
            DamageType::Volcanic => "volcanic",
            DamageType::Erosion => "erosion",
        };
        write!(f, "{}", s)
    }
}

/// Convenience: label for an optional damage type.
pub fn damage_type_label(damage: Option<DamageType>) -> &'static str {
    match damage {
        Some(dt) => match dt {
            DamageType::Earthquake => "earthquake",
            DamageType::Fire => "fire",
            DamageType::Flood => "flood",
            DamageType::Drought => "drought",
            DamageType::Volcanic => "volcanic",
            DamageType::Erosion => "erosion",
        },
        None => "stable",
    }
}
