//! World domain types: regions, entities, settlements, vegetation,
//! damage, and history.

mod damage;
mod entity;
mod history;
mod region;
mod settlement;
mod vegetation;

pub use damage::{DamageType, damage_type_label};
pub use entity::EntityKind;
pub use history::{HistoryEvent, validate_event_ordering};
pub use region::RegionId;
pub use settlement::{
    SettlementOccupancyState, SettlementReconstructionState, settlement_occupancy_state_label,
    settlement_reconstruction_state_label,
};
pub use vegetation::{VegetationState, vegetation_state_label};
