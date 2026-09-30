use crate::world::{DamageType, VegetationState};
use serde::{Deserialize, Serialize};
use std::fmt;

// ---------------------------------------------------------------------------
// SettlementOccupancyState
// ---------------------------------------------------------------------------

/// The current occupancy state of a settlement.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
#[non_exhaustive]
pub enum SettlementOccupancyState {
    /// Settlement is fully functional with no damage.
    Intact,
    /// Settlement has sustained damage but remains inhabited.
    Damaged,
    /// Settlement has been abandoned due to damage.
    Abandoned,
    /// Settlement has been completely destroyed.
    Razed,
}

impl SettlementOccupancyState {
    /// Classify occupancy from damage type + severity.
    pub fn from_damage(damage_type: Option<DamageType>, severity: f32) -> Self {
        let dt = match damage_type {
            Some(dt) => dt,
            None => return Self::Intact,
        };

        match dt {
            DamageType::Drought | DamageType::Erosion => {
                if severity >= 0.6 {
                    Self::Abandoned
                } else if severity >= 0.3 {
                    Self::Damaged
                } else {
                    Self::Intact
                }
            }
            DamageType::Fire | DamageType::Volcanic => {
                if severity >= 0.5 {
                    Self::Razed
                } else if severity >= 0.3 {
                    Self::Damaged
                } else {
                    Self::Intact
                }
            }
            DamageType::Earthquake | DamageType::Flood => {
                if severity >= 0.7 {
                    Self::Razed
                } else if severity >= 0.3 {
                    Self::Damaged
                } else {
                    Self::Intact
                }
            }
        }
    }

    /// Human-readable label (kept for backward compatibility; calls Display).
    #[deprecated = "Use Display instead: format!(\"{}\", value)"]
    pub fn label(self) -> &'static str {
        // This function is no longer called internally.
        // Keep for external backward compatibility only.
        match self {
            SettlementOccupancyState::Intact => "intact",
            SettlementOccupancyState::Damaged => "damaged",
            SettlementOccupancyState::Abandoned => "abandoned",
            SettlementOccupancyState::Razed => "razed",
        }
    }
}

impl fmt::Display for SettlementOccupancyState {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        let s = match self {
            SettlementOccupancyState::Intact => "intact",
            SettlementOccupancyState::Damaged => "damaged",
            SettlementOccupancyState::Abandoned => "abandoned",
            SettlementOccupancyState::Razed => "razed",
        };
        write!(f, "{}", s)
    }
}

/// Convenience: label for an occupancy state.
pub fn settlement_occupancy_state_label(state: SettlementOccupancyState) -> &'static str {
    match state {
        SettlementOccupancyState::Intact => "intact",
        SettlementOccupancyState::Damaged => "damaged",
        SettlementOccupancyState::Abandoned => "abandoned",
        SettlementOccupancyState::Razed => "razed",
    }
}

// ---------------------------------------------------------------------------
// SettlementReconstructionState
// ---------------------------------------------------------------------------

/// The reconstruction state of a settlement.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
#[non_exhaustive]
pub enum SettlementReconstructionState {
    /// Settlement is stable with no reconstruction needed.
    Stable,
    /// Settlement is actively being repaired.
    Repairing,
}

impl SettlementReconstructionState {
    /// Classify from occupancy, vegetation, and severity.
    pub fn from_occupancy_and_vegetation(
        occupancy: SettlementOccupancyState,
        vegetation_state: &VegetationState,
        damage_severity: f32,
    ) -> Self {
        if *vegetation_state == VegetationState::Regrowth
            && damage_severity >= 0.2
            && matches!(
                occupancy,
                SettlementOccupancyState::Intact | SettlementOccupancyState::Damaged
            )
        {
            Self::Repairing
        } else {
            Self::Stable
        }
    }

    /// Human-readable label (kept for backward compatibility; calls Display).
    #[deprecated = "Use Display instead: format!(\"{}\", value)"]
    pub fn label(self) -> &'static str {
        // This function is no longer called internally.
        // Keep for external backward compatibility only.
        match self {
            SettlementReconstructionState::Stable => "stable",
            SettlementReconstructionState::Repairing => "repairing",
        }
    }
}

impl fmt::Display for SettlementReconstructionState {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        let s = match self {
            SettlementReconstructionState::Stable => "stable",
            SettlementReconstructionState::Repairing => "repairing",
        };
        write!(f, "{}", s)
    }
}

/// Convenience: label for a reconstruction state.
pub fn settlement_reconstruction_state_label(state: SettlementReconstructionState) -> &'static str {
    match state {
        SettlementReconstructionState::Stable => "stable",
        SettlementReconstructionState::Repairing => "repairing",
    }
}
