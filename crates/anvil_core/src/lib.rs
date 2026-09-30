#![deny(warnings)]
#![deny(missing_docs)]
#![cfg_attr(not(test), deny(clippy::unwrap_used, clippy::expect_used, clippy::panic, clippy::unreachable, clippy::todo))]
//!
//! # anvil_core
//!
//! Foundational domain types and validation infrastructure for the
//! Anvil pipeline. This crate defines the shared contracts that every
//! other crate depends on.
//!
//! ## Key types
//!
//! - **[`ArchetypeTag`]** — validated identifier for game assets (e.g. `"highlands_watchtower"`)
//! - **[`RegionSpec`]**, **[`ConnectionSpec`]** — authored world descriptions
//! - **[`DamageType`]**, **[`VegetationState`]**, **[`SettlementOccupancyState`]**,
//!   **[`SettlementReconstructionState`]**, **[`TerrainType`]** — game-state enums
//! - **[`AssetRequestSpec`]** — LLM asset generation request
//!
//! ## Error handling
//!
//! This crate uses **[`AnvilCoreError`]** for all validation failures.
//! Validation methods return `Vec<AnvilCoreError>` so callers can fix
//! all problems at once. Use **[`push_validation_error!`]** for
//! concise error construction in custom `validate()` methods.

mod artifact;
mod asset_request;
mod connections;
mod error;
mod ids;
pub mod path;
mod semantic;
pub mod world;

pub use artifact::{SemanticArtifact, Versioned};
pub use asset_request::{
    AssetRequestFamily, AssetRequestQualityHint, AssetRequestSourceHint, AssetRequestSpec,
    AssetRequestSpecBuilder, BuildError,
};
pub use connections::{ConnectionId, ConnectionKind, ConnectionSpec, Directionality};
pub use error::{AnvilCoreError, ErrorCode, FailureClass, ValidationError, ValidationErrors, error_buffer};
pub use ids::{ArchetypeTag, AuthoredEntityId};
pub use path::AssetPath;
pub use semantic::{LandmarkKind, LandmarkSpec, RegionSpec, StyleHints, TerrainType};
pub use world::{
    DamageType, EntityKind, HistoryEvent, RegionId, SettlementOccupancyState,
    SettlementReconstructionState, VegetationState, damage_type_label,
    settlement_occupancy_state_label, settlement_reconstruction_state_label,
    vegetation_state_label,
};

#[cfg(test)]
mod tests {
    use super::*;
    use crate::error::{ErrorCode, ValidationErrors, error_buffer};

    #[derive(Debug, Clone)]
    struct DummyArtifact {
        name: String,
    }

    impl Versioned for DummyArtifact {
        fn version(&self) -> u32 {
            1
        }
        fn artifact_type_name(&self) -> &'static str {
            "DummyArtifact"
        }
    }

    impl SemanticArtifact for DummyArtifact {
        fn validate(&self) -> ValidationErrors {
            let mut errors = error_buffer();
            if self.name.trim().is_empty() {
                push_validation_error!(
                    errors,
                    FailureClass::Semantic,
                    "E999",
                    "DummyArtifact",
                    "name",
                    self.name.clone(),
                    "artifact name cannot be empty"
                );
            }
            errors
        }
    }

    #[test]
    fn failure_class_json_roundtrip() {
        let original = FailureClass::Semantic;
        let json = serde_json::to_string(&original).expect("serialize failure class");
        let decoded: FailureClass = serde_json::from_str(&json).expect("deserialize failure class");

        assert_eq!(decoded, original);
    }

    #[test]
    fn authored_entity_id_json_roundtrip() {
        let original = AuthoredEntityId::new(42);
        let json = serde_json::to_string(&original).expect("serialize entity id");
        let decoded: AuthoredEntityId = serde_json::from_str(&json).expect("deserialize entity id");

        assert_eq!(decoded, original);
        assert_eq!(decoded.get(), 42);
    }

    #[test]
    fn forge_core_error_display_is_human_readable() {
        let error = AnvilCoreError::validation(
            FailureClass::Semantic,
            ErrorCode::new("E000"),
            "Dummy",
            "field",
            "value",
            "missing required field: name",
        );

        assert!(error.to_string().contains("missing required field: name"));
        assert_eq!(error.failure_class(), FailureClass::Semantic);
    }

    #[test]
    fn semantic_artifact_validation_passes_for_valid_data() {
        let artifact = DummyArtifact {
            name: "standing stones".to_string(),
        };

        assert_eq!(artifact.version(), 1);
        assert!(artifact.validate().is_empty());
    }

    #[test]
    fn semantic_artifact_validation_fails_for_empty_name() {
        let artifact = DummyArtifact {
            name: "   ".to_string(),
        };

        let errors = artifact.validate();
        assert!(!errors.is_empty());
        let error = &errors[0];
        assert_eq!(error.failure_class(), FailureClass::Semantic);
        assert!(error.to_string().contains("artifact name cannot be empty"));
    }
}
