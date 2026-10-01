//! Social connection types for NPC mood contagion.
//!
//! Defines the connection layers as per GAME_DESIGN_SECTION_3.md Section 3.1.2.

use crate::settlement::ids::PersonId;
use anvil_core::ValidationErrors;
use serde::{Deserialize, Serialize};
use std::fmt;

// ---------------------------------------------------------------------------
// ConnectionLayer
// ---------------------------------------------------------------------------

/// The layers of social connection between NPCs as defined in Section 3.1.2.
///
/// These layers determine the influence strength for mood contagion.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize, Hash)]
#[serde(rename_all = "snake_case")]
#[non_exhaustive]
pub enum ConnectionLayer {
    /// Family connections (parents, children, siblings, partners).
    /// High influence strength. 2-7 members per family.
    Family,
    /// Proximity connections (co-workers, neighbours, daily routine sharing).
    /// Moderate influence strength. 3-12 connections per NPC.
    Proximity,
    /// Village connections (everyone else in the settlement).
    /// Weak but cumulative influence strength.
    Village,
}

impl fmt::Display for ConnectionLayer {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            ConnectionLayer::Family => write!(f, "family"),
            ConnectionLayer::Proximity => write!(f, "proximity"),
            ConnectionLayer::Village => write!(f, "village"),
        }
    }
}

impl ConnectionLayer {
    /// Returns the relative influence weight for this layer.
    /// Family: high (1.0), Proximity: moderate (0.5), Village: weak (0.1).
    pub fn weight(&self) -> f32 {
        match self {
            ConnectionLayer::Family => 1.0,
            ConnectionLayer::Proximity => 0.5,
            ConnectionLayer::Village => 0.1,
        }
    }
}

// ---------------------------------------------------------------------------
// Connection
// ---------------------------------------------------------------------------

/// A social connection between two NPCs with a layer classification.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct Connection {
    /// The target person in this connection.
    pub target: PersonId,
    /// The layer of this connection (Family, Proximity, Village).
    pub layer: ConnectionLayer,
}

impl Connection {
    /// Creates a new connection to a target person with a given layer.
    pub fn new(target: PersonId, layer: ConnectionLayer) -> Self {
        Self { target, layer }
    }

    /// Validates this connection.
    pub fn validate(&self) -> ValidationErrors {
        self.target.validate()
    }
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_connection_layer_weights() {
        assert_eq!(ConnectionLayer::Family.weight(), 1.0);
        assert_eq!(ConnectionLayer::Proximity.weight(), 0.5);
        assert_eq!(ConnectionLayer::Village.weight(), 0.1);
    }

    #[test]
    fn test_connection_layer_display() {
        assert_eq!(format!("{}", ConnectionLayer::Family), "family");
        assert_eq!(format!("{}", ConnectionLayer::Proximity), "proximity");
        assert_eq!(format!("{}", ConnectionLayer::Village), "village");
    }

    #[test]
    fn test_connection_validation() {
        let conn = Connection::new(PersonId::new(1), ConnectionLayer::Family);
        let errors = conn.validate();
        assert!(errors.is_empty());
    }
}
