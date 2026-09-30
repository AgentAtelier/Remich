//! Connection specification between regions.

use serde::{Deserialize, Serialize};
use std::collections::BTreeSet;
use std::fmt;

use crate::artifact::{SemanticArtifact, Versioned};
use crate::error::{FailureClass, ValidationErrors, error_buffer};
use crate::push_validation_error;

// ---------------------------------------------------------------------------
// ConnectionId — type‑safe zero‑cost wrapper
// ---------------------------------------------------------------------------
/// Unique identifier for a connection between regions.
#[derive(Debug, Clone, Copy, PartialEq, Eq, PartialOrd, Ord, Hash, Serialize, Deserialize)]
#[serde(transparent)]
pub struct ConnectionId(usize);

impl ConnectionId {
    /// Create a new `ConnectionId` from a raw index.
    pub const fn new(id: usize) -> Self {
        Self(id)
    }

    /// Get the underlying index value.
    pub const fn get(self) -> usize {
        self.0
    }
}

impl fmt::Display for ConnectionId {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(f, "ConnectionId({})", self.0)
    }
}

// ---------------------------------------------------------------------------
// ConnectionKind
// ---------------------------------------------------------------------------
/// The type of connection between regions.
#[derive(Debug, Clone, Copy, PartialEq, Eq, PartialOrd, Ord, Hash, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
#[non_exhaustive]
pub enum ConnectionKind {
    /// Paved road suitable for travel.
    Road,
    /// Unpaved path or trail.
    Path,
    /// Magical or special passage.
    Portal,
    /// Gated entrance or checkpoint.
    Gate,
    /// Natural waterway.
    River,
}

impl ConnectionKind {
    /// Returns true if this connection kind can be traversed on foot.
    pub fn is_traversable_on_foot(&self) -> bool {
        matches!(self, ConnectionKind::Road | ConnectionKind::Path)
    }

    /// Returns true if this connection requires crossing water.
    pub fn requires_water_crossing(&self) -> bool {
        matches!(self, ConnectionKind::River)
    }
}

impl fmt::Display for ConnectionKind {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            ConnectionKind::Road => write!(f, "road"),
            ConnectionKind::Path => write!(f, "path"),
            ConnectionKind::Portal => write!(f, "portal"),
            ConnectionKind::Gate => write!(f, "gate"),
            ConnectionKind::River => write!(f, "river"),
        }
    }
}

// ---------------------------------------------------------------------------
// Directionality
// ---------------------------------------------------------------------------
/// The directionality of a connection.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
#[non_exhaustive]
#[derive(Default)]
pub enum Directionality {
    /// Connection can be traversed in both directions.
    #[default]
    Bidirectional,
    /// Connection can only be traversed in one direction.
    OneWay,
}

// ---------------------------------------------------------------------------
// ConnectionSpec
// ---------------------------------------------------------------------------
/// Connection specification between regions, defining from/to region semantics.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct ConnectionSpec {
    /// Human-readable name for this connection.
    #[serde(default)]
    pub name: String,

    /// The starting region name.
    pub from_region: String,
    /// The destination region name.
    pub to_region: String,
    /// The type of connection.
    pub kind: ConnectionKind,

    /// The directionality of this connection.
    #[serde(default)]
    pub directionality: Directionality,
}

impl ConnectionSpec {
    /// Returns true if this connection involves the given region (either from or to).
    pub fn involves_region(&self, region_name: &str) -> bool {
        self.from_region == region_name || self.to_region == region_name
    }

    /// Returns true if this connection links the specified regions.
    /// For bidirectional connections, either order works.
    pub fn connects(&self, from: &str, to: &str) -> bool {
        match self.directionality {
            Directionality::Bidirectional => {
                (self.from_region == from && self.to_region == to)
                    || (self.from_region == to && self.to_region == from)
            }
            Directionality::OneWay => self.from_region == from && self.to_region == to,
        }
    }

    /// Returns a display name for this connection.
    /// If a custom name is set, it is returned. Otherwise, a generated name
    /// in the format "from to to kind" is used.
    pub fn display_name(&self) -> String {
        if !self.name.trim().is_empty() {
            return self.name.clone();
        }
        format!("{} to {} {}", self.from_region, self.to_region, self.kind)
    }

    /// Validate that both from_region and to_region exist in the set of known regions.
    pub fn validate_region_names(&self, known_regions: &BTreeSet<&str>) -> ValidationErrors {
        let mut errors = error_buffer();
        if !known_regions.contains(self.from_region.as_str()) {
            use crate::push_validation_error;
            push_validation_error!(
                errors,
                FailureClass::Semantic,
                "E024",
                self.artifact_type_name(),
                "from_region",
                self.from_region.clone(),
                "from_region is not a known region"
            );
        }
        if !known_regions.contains(self.to_region.as_str()) {
            use crate::push_validation_error;
            push_validation_error!(
                errors,
                FailureClass::Semantic,
                "E025",
                self.artifact_type_name(),
                "to_region",
                self.to_region.clone(),
                "to_region is not a known region"
            );
        }
        errors
    }
}

// ---------------------------------------------------------------------------
// Trait implementations
// ---------------------------------------------------------------------------
impl Versioned for ConnectionSpec {
    fn version(&self) -> u32 {
        1
    }

    fn artifact_type_name(&self) -> &'static str {
        "ConnectionSpec"
    }
}

impl SemanticArtifact for ConnectionSpec {
    fn validate(&self) -> ValidationErrors {
        let mut errors = error_buffer();

        if self.from_region.trim().is_empty() {
            push_validation_error!(
                errors,
                FailureClass::Semantic,
                "E001",
                self.artifact_type_name(),
                "from_region",
                self.from_region.clone(),
                "must not be empty",
                hint = "Provide a non-empty region name matching one of the known regions."
            );
        }

        if self.to_region.trim().is_empty() {
            push_validation_error!(
                errors,
                FailureClass::Semantic,
                "E002",
                self.artifact_type_name(),
                "to_region",
                self.to_region.clone(),
                "must not be empty",
                hint = "Provide a non-empty region name matching one of the known regions."
            );
        }

        if self.from_region.trim() == self.to_region.trim() && !self.from_region.trim().is_empty() {
            push_validation_error!(
                errors,
                FailureClass::Semantic,
                "E003",
                self.artifact_type_name(),
                "from_region / to_region",
                self.from_region.clone(),
                "a region cannot be connected to itself",
                hint = "Specify two different region names."
            );
        }

        errors
    }
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------
#[cfg(test)]
mod tests {
    use super::*;

    // Existing tests (kept)
    #[test]
    fn connection_kind_uses_snake_case_json() {
        let json = serde_json::to_string(&ConnectionKind::Portal).expect("serialize");
        assert_eq!(json, "\"portal\"");
    }

    #[test]
    fn connection_id_roundtrip() {
        let original = ConnectionId(7);
        let json = serde_json::to_string(&original).expect("serialize");
        let decoded: ConnectionId = serde_json::from_str(&json).expect("deserialize");
        assert_eq!(decoded, original);
    }

    // New tests for improvements
    #[test]
    fn connection_id_new() {
        assert_eq!(ConnectionId::new(5), ConnectionId(5));
    }

    #[test]
    fn road_is_traversable_on_foot() {
        assert!(ConnectionKind::Road.is_traversable_on_foot());
    }

    #[test]
    fn portal_is_not_traversable_on_foot() {
        assert!(!ConnectionKind::Portal.is_traversable_on_foot());
    }

    #[test]
    fn river_requires_water_crossing() {
        assert!(ConnectionKind::River.requires_water_crossing());
    }

    #[test]
    fn display_kind() {
        assert_eq!(format!("{}", ConnectionKind::Gate), "gate");
    }

    #[test]
    fn default_directionality_is_bidirectional() {
        let spec = ConnectionSpec {
            name: String::new(),
            from_region: "A".into(),
            to_region: "B".into(),
            kind: ConnectionKind::Road,
            directionality: Directionality::default(),
        };
        assert!(spec.connects("A", "B"));
        assert!(spec.connects("B", "A"));
    }

    #[test]
    fn oneway_connects_only_from_to() {
        let spec = ConnectionSpec {
            name: String::new(),
            from_region: "A".into(),
            to_region: "B".into(),
            kind: ConnectionKind::Path,
            directionality: Directionality::OneWay,
        };
        assert!(spec.connects("A", "B"));
        assert!(!spec.connects("B", "A"));
    }

    #[test]
    fn display_name_generated() {
        let spec = ConnectionSpec {
            name: String::new(),
            from_region: "Highmark".into(),
            to_region: "Greyridge".into(),
            kind: ConnectionKind::Road,
            directionality: Directionality::default(),
        };
        assert_eq!(spec.display_name(), "Highmark to Greyridge road");
    }

    #[test]
    fn display_name_custom() {
        let spec = ConnectionSpec {
            name: "Custom Route".into(),
            from_region: "A".into(),
            to_region: "B".into(),
            kind: ConnectionKind::Path,
            directionality: Directionality::default(),
        };
        assert_eq!(spec.display_name(), "Custom Route");
    }

    #[test]
    fn validate_rejects_empty_from() {
        let spec = ConnectionSpec {
            name: String::new(),
            from_region: "  ".into(),
            to_region: "B".into(),
            kind: ConnectionKind::Road,
            directionality: Directionality::default(),
        };
        assert!(!spec.validate().is_empty());
    }

    #[test]
    fn validate_rejects_self_connection() {
        let spec = ConnectionSpec {
            name: String::new(),
            from_region: "X".into(),
            to_region: "X".into(),
            kind: ConnectionKind::Road,
            directionality: Directionality::default(),
        };
        assert!(!spec.validate().is_empty());
    }

    #[test]
    fn validate_accepts_valid_spec() {
        let spec = ConnectionSpec {
            name: String::new(),
            from_region: "A".into(),
            to_region: "B".into(),
            kind: ConnectionKind::Road,
            directionality: Directionality::default(),
        };
        assert!(spec.validate().is_empty());
    }

    #[test]
    fn validate_region_names_ok() {
        let spec = ConnectionSpec {
            name: String::new(),
            from_region: "A".into(),
            to_region: "B".into(),
            kind: ConnectionKind::Road,
            directionality: Directionality::default(),
        };
        let regions: BTreeSet<&str> = ["A", "B"].into_iter().collect();
        assert!(spec.validate_region_names(&regions).is_empty());
    }

    #[test]
    fn validate_region_names_fails_for_unknown_from() {
        let spec = ConnectionSpec {
            name: String::new(),
            from_region: "Unknown".into(),
            to_region: "B".into(),
            kind: ConnectionKind::Road,
            directionality: Directionality::default(),
        };
        let regions: BTreeSet<&str> = ["A", "B"].into_iter().collect();
        let errors = spec.validate_region_names(&regions);
        assert!(!errors.is_empty());
        assert!(errors.iter().any(|e| e.field() == "from_region"));
    }
}
