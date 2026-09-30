use serde::{Deserialize, Serialize};
use std::fmt;

/// Post‑disaster vegetation state for an entity.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize, Default)]
#[serde(rename_all = "snake_case")]
#[non_exhaustive]
pub enum VegetationState {
    /// No vegetation present.
    Bare,
    /// Vegetation is regrowing after damage.
    Regrowth,
    /// Healthy, mature vegetation.
    #[default]
    Mature,
    /// Vegetation has died.
    Dead,
    /// Vegetation has been burned.
    Burned,
}

impl VegetationState {
    /// `true` if the vegetation is alive (Mature or Regrowth).
    pub fn is_alive(self) -> bool {
        matches!(self, VegetationState::Mature | VegetationState::Regrowth)
    }

    /// `true` if the vegetation is dead or visibly damaged.
    pub fn is_damaged(self) -> bool {
        matches!(
            self,
            VegetationState::Dead | VegetationState::Burned | VegetationState::Bare
        )
    }

    /// Human-readable label (kept for backward compatibility; calls Display).
    #[deprecated = "Use Display instead: format!(\"{}\", value)"]
    pub fn label(self) -> &'static str {
        // This function is no longer called internally.
        // Keep for external backward compatibility only.
        match self {
            VegetationState::Mature => "mature",
            VegetationState::Dead => "dead",
            VegetationState::Burned => "burned",
            VegetationState::Bare => "bare",
            VegetationState::Regrowth => "regrowth",
        }
    }
}

impl fmt::Display for VegetationState {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        let s = match self {
            VegetationState::Mature => "mature",
            VegetationState::Dead => "dead",
            VegetationState::Burned => "burned",
            VegetationState::Bare => "bare",
            VegetationState::Regrowth => "regrowth",
        };
        write!(f, "{}", s)
    }
}

/// Convenience: label for a vegetation state reference.
pub fn vegetation_state_label(state: &VegetationState) -> &'static str {
    match state {
        VegetationState::Mature => "mature",
        VegetationState::Dead => "dead",
        VegetationState::Burned => "burned",
        VegetationState::Bare => "bare",
        VegetationState::Regrowth => "regrowth",
    }
}
