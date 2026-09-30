//! Semantic authored‑world types: [`RegionSpec`], [`LandmarkKind`],
//! and [`TerrainType`].

use crate::artifact::{SemanticArtifact, Versioned};
use crate::error::{FailureClass, ValidationErrors, error_buffer};
use crate::{AnvilCoreError, push_validation_error};
use serde::{Deserialize, Serialize};
use std::fmt;

// ---------------------------------------------------------------------------
// TerrainType
// ---------------------------------------------------------------------------

/// The five biome types: Highlands, Forest, Desert, Marsh, and Coast.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize, Default)]
#[serde(rename_all = "snake_case")]
#[non_exhaustive]
pub enum TerrainType {
    /// Rolling hills and valleys, sparsely vegetated.
    #[default]
    Highlands,
    /// Dense woodland with tall trees.
    Forest,
    /// Arid sandy environment with scattered vegetation.
    Desert,
    /// Wet, low-lying area with standing water.
    Marsh,
    /// Coastal area where land meets sea.
    Coast,
}

impl TerrainType {
    /// Default vegetation density for this biome.
    pub fn default_density(&self) -> &'static str {
        match self {
            TerrainType::Highlands | TerrainType::Desert | TerrainType::Coast => "sparse",
            TerrainType::Forest => "dense",
            TerrainType::Marsh => "medium",
        }
    }

    /// Default atmosphere description for this biome.
    pub fn default_atmosphere(&self) -> &'static str {
        match self {
            TerrainType::Highlands => "clear and windy",
            TerrainType::Forest => "cool and shaded",
            TerrainType::Desert => "dry and exposed",
            TerrainType::Marsh => "foggy and damp",
            TerrainType::Coast => "windy and salty",
        }
    }

    /// Typical palette colours for this biome.
    pub fn typical_palette(&self) -> &'static [&'static str] {
        match self {
            TerrainType::Highlands => &["charcoal grey", "weathered slate", "ochre", "pale green"],
            TerrainType::Forest => &["deep green", "bark brown", "stone grey", "moss"],
            TerrainType::Desert => &["sand", "bone white", "pale umber", "cracked earth"],
            TerrainType::Marsh => &["deep olive", "wet slate", "mud brown", "dull blue"],
            TerrainType::Coast => &["pale grey", "chalk white", "deep sea blue", "seafoam green"],
        }
    }
}

impl fmt::Display for TerrainType {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            TerrainType::Highlands => write!(f, "highlands"),
            TerrainType::Forest => write!(f, "forest"),
            TerrainType::Desert => write!(f, "desert"),
            TerrainType::Marsh => write!(f, "marsh"),
            TerrainType::Coast => write!(f, "coast"),
        }
    }
}

// ---------------------------------------------------------------------------
// LandmarkKind
// ---------------------------------------------------------------------------

/// The categorical classification of a landmark within a region.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
#[non_exhaustive]
pub enum LandmarkKind {
    /// Remains of a once-great structure.
    Ruin,
    /// Commemorative structure or statue.
    Monument,
    /// Inhabited settlement.
    Settlement,
    /// Tall defensive or watch structure.
    Tower,
    /// Upright stone marker.
    StandingStone,
    /// Sacred or memorial site.
    Shrine,
    /// Natural underground cavity.
    Cave,
    /// Structure spanning a gap.
    Bridge,
}

impl LandmarkKind {
    /// True if the landmark is a built structure.
    pub fn is_structure(&self) -> bool {
        matches!(
            self,
            LandmarkKind::Tower
                | LandmarkKind::Settlement
                | LandmarkKind::Bridge
                | LandmarkKind::Ruin
        )
    }

    /// True if the landmark serves as a navigation or cultural marker.
    pub fn is_marker(&self) -> bool {
        matches!(
            self,
            LandmarkKind::StandingStone | LandmarkKind::Shrine | LandmarkKind::Monument
        )
    }

    /// True if the landmark is a natural feature.
    pub fn is_natural(&self) -> bool {
        matches!(self, LandmarkKind::Cave)
    }
}

impl fmt::Display for LandmarkKind {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            LandmarkKind::Ruin => write!(f, "ruin"),
            LandmarkKind::Monument => write!(f, "monument"),
            LandmarkKind::Settlement => write!(f, "settlement"),
            LandmarkKind::Tower => write!(f, "tower"),
            LandmarkKind::StandingStone => write!(f, "standing_stone"),
            LandmarkKind::Shrine => write!(f, "shrine"),
            LandmarkKind::Cave => write!(f, "cave"),
            LandmarkKind::Bridge => write!(f, "bridge"),
        }
    }
}

// ---------------------------------------------------------------------------
// LandmarkSpec
// ---------------------------------------------------------------------------

/// Specification for a landmark within a region.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct LandmarkSpec {
    /// Human-readable name for this landmark.
    pub name: String,
    /// Categorical classification of this landmark.
    pub kind: LandmarkKind,
    /// Descriptive text explaining what this landmark is.
    pub description: String,
}

impl Versioned for LandmarkSpec {
    fn version(&self) -> u32 {
        1
    }
    fn artifact_type_name(&self) -> &'static str {
        "LandmarkSpec"
    }
}

impl SemanticArtifact for LandmarkSpec {
    fn validate(&self) -> ValidationErrors {
        let mut errors = error_buffer();

        if self.name.trim().is_empty() {
            push_validation_error!(
                errors,
                FailureClass::Semantic,
                "E007",
                self.artifact_type_name(),
                "name",
                self.name.clone(),
                "landmark name cannot be empty"
            );
        }

        if self.description.trim().is_empty() {
            push_validation_error!(
                errors,
                FailureClass::Semantic,
                "E008",
                self.artifact_type_name(),
                "description",
                self.description.clone(),
                "landmark description cannot be empty"
            );
        }

        errors
    }
}

// ---------------------------------------------------------------------------
// StyleHints
// ---------------------------------------------------------------------------

/// Visual style guidance for a region.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct StyleHints {
    /// Color palette for this region's assets.
    #[serde(default)]
    pub palette: Vec<String>,

    /// Density of vegetation/foliage placement.
    pub density: String,
    /// Atmospheric conditions description.
    pub atmosphere: String,
}

/// Valid density values.
pub const VALID_DENSITIES: &[&str] = &["sparse", "medium", "dense"];

// ---------------------------------------------------------------------------
// RegionSpec
// ---------------------------------------------------------------------------

/// Authored region specification with landmark constraints.
///
/// A region must have between 3 and 5 landmarks, each with unique archetype tags.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct RegionSpec {
    /// Human-readable name for this region.
    pub name: String,
    /// Biome classification for this region.
    pub terrain_type: TerrainType,
    /// Atmospheric mood description.
    pub mood: String,
    /// List of landmarks in this region.
    pub landmarks: Vec<LandmarkSpec>,
    /// Visual styling guidance.
    pub style_hints: StyleHints,
}

impl RegionSpec {
    /// Minimum number of landmarks required per region.
    pub const MIN_LANDMARKS: usize = 3;
    /// Maximum number of landmarks allowed per region.
    pub const MAX_LANDMARKS: usize = 5;
}

impl Versioned for RegionSpec {
    fn version(&self) -> u32 {
        1
    }
    fn artifact_type_name(&self) -> &'static str {
        "RegionSpec"
    }
}

impl SemanticArtifact for RegionSpec {
    fn validate(&self) -> ValidationErrors {
        let mut errors = error_buffer();

        // --- name ---
        if self.name.trim().is_empty() {
            push_validation_error!(
                errors,
                FailureClass::Semantic,
                "E004",
                self.artifact_type_name(),
                "name",
                self.name.clone(),
                "region name cannot be empty",
                hint = "Provide a non-empty name for the region."
            );
        }

        // --- mood ---
        if self.mood.trim().is_empty() {
            push_validation_error!(
                errors,
                FailureClass::Semantic,
                "E005",
                self.artifact_type_name(),
                "mood",
                self.mood.clone(),
                "region mood cannot be empty"
            );
        }

        // --- landmark count ---
        if !(Self::MIN_LANDMARKS..=Self::MAX_LANDMARKS).contains(&self.landmarks.len()) {
            push_validation_error!(
                errors,
                FailureClass::Semantic,
                "E006",
                self.artifact_type_name(),
                "landmarks",
                format!("{} landmarks", self.landmarks.len()),
                format!(
                    "region must contain between {} and {} landmarks",
                    Self::MIN_LANDMARKS,
                    Self::MAX_LANDMARKS,
                )
            );
        }

        // --- individual landmarks ---
        let mut seen_names: Vec<String> = Vec::with_capacity(self.landmarks.len());
        for (i, landmark) in self.landmarks.iter().enumerate() {
            // delegate to LandmarkSpec validation - remap field names with index
            for e in landmark.validate() {
                let field_name = format!("landmarks[{}].{}", i, e.field());
                let code_str = e.code().as_str();
                // LandmarkSpec validation produces E007 (name empty) and E008 (description empty)
                match code_str {
                    "E007" => {
                        push_validation_error!(
                            errors,
                            e.failure_class(),
                            "E007",
                            self.artifact_type_name(),
                            field_name,
                            e.value().to_string(),
                            e.message().to_string()
                        );
                    }
                    "E008" => {
                        push_validation_error!(
                            errors,
                            e.failure_class(),
                            "E008",
                            self.artifact_type_name(),
                            field_name,
                            e.value().to_string(),
                            e.message().to_string()
                        );
                    }
                    _ => {
                        // Fallback: LandmarkSpec only emits E007/E008 today;
                        // if new codes are added, this paths handles them.
                        errors.push(
                            AnvilCoreError::validation(
                                e.failure_class(),
                                e.code().clone(),
                                self.artifact_type_name(),
                                field_name,
                                e.value().to_string(),
                                e.message().to_string(),
                            )
                            .at_location(file!(), line!()),
                        );
                    }
                }
            }

            // duplicate name check
            let normalized = landmark.name.trim().to_lowercase();
            if !normalized.is_empty() && seen_names.iter().any(|n| n == &normalized) {
                push_validation_error!(
                    errors,
                    FailureClass::Semantic,
                    "E015",
                    self.artifact_type_name(),
                    format!("landmarks[{}].name", i),
                    landmark.name.clone(),
                    "landmark name is not unique within this region",
                    hint = "Give each landmark a distinct name."
                );
            }
            seen_names.push(normalized);
        }

        // --- style hints ---
        if self.style_hints.palette.is_empty() {
            push_validation_error!(
                errors,
                FailureClass::Semantic,
                "E009",
                self.artifact_type_name(),
                "style_hints.palette",
                "empty palette",
                "style_hints.palette cannot be empty"
            );
        }

        if !VALID_DENSITIES.contains(&self.style_hints.density.as_str()) {
            push_validation_error!(
                errors,
                FailureClass::Semantic,
                "E010",
                self.artifact_type_name(),
                "style_hints.density",
                self.style_hints.density.clone(),
                format!("density must be one of: {}", VALID_DENSITIES.join(", "))
            );
        }

        if self.style_hints.atmosphere.trim().is_empty() {
            push_validation_error!(
                errors,
                FailureClass::Semantic,
                "E011",
                self.artifact_type_name(),
                "style_hints.atmosphere",
                self.style_hints.atmosphere.clone(),
                "style_hints.atmosphere cannot be empty"
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

    fn valid_region() -> RegionSpec {
        RegionSpec {
            name: "Misty Highlands".to_string(),
            terrain_type: TerrainType::Highlands,
            mood: "ancient and windswept".to_string(),
            landmarks: vec![
                LandmarkSpec {
                    name: "Watcher Stones".to_string(),
                    kind: LandmarkKind::StandingStone,
                    description: "weathered monoliths on a ridge".to_string(),
                },
                LandmarkSpec {
                    name: "Broken Tower".to_string(),
                    kind: LandmarkKind::Tower,
                    description: "a shattered tower overlooking the valley".to_string(),
                },
                LandmarkSpec {
                    name: "Ashen Monument".to_string(),
                    kind: LandmarkKind::Monument,
                    description: "a forgotten monument in the heather".to_string(),
                },
            ],
            style_hints: StyleHints {
                palette: vec!["grey".into(), "violet".into(), "pale green".into()],
                density: "sparse".into(),
                atmosphere: "misty".into(),
            },
        }
    }

    #[test]
    fn valid_region_passes() {
        let region = valid_region();
        assert!(region.validate().is_empty());
    }

    #[test]
    fn blank_name_fails() {
        let mut region = valid_region();
        region.name = "   ".into();
        let errors = region.validate();
        assert!(!errors.is_empty());
        assert!(
            errors[0]
                .to_string()
                .contains("region name cannot be empty")
        );
    }

    #[test]
    fn too_few_landmarks_fails() {
        let mut region = valid_region();
        region.landmarks.truncate(2);
        let errors = region.validate();
        assert!(!errors.is_empty());
        assert!(
            errors[0]
                .to_string()
                .contains("must contain between 3 and 5")
        );
    }

    #[test]
    fn duplicate_landmark_name_fails() {
        let mut region = valid_region();
        region.landmarks[1].name = "Watcher Stones".into();
        let errors = region.validate();
        assert!(errors.iter().any(|e| e.to_string().contains("not unique")));
    }

    #[test]
    fn invalid_density_fails() {
        let mut region = valid_region();
        region.style_hints.density = "thick".into();
        let errors = region.validate();
        assert!(
            errors
                .iter()
                .any(|e| e.to_string().contains("density must be one of"))
        );
    }

    #[test]
    fn palette_serializes_as_array() {
        let hints = StyleHints {
            palette: vec!["a".into(), "b".into()],
            density: "sparse".into(),
            atmosphere: "clear".into(),
        };
        let json = serde_json::to_string(&hints).unwrap();
        assert!(json.contains("[\"a\",\"b\"]"));
    }

    #[test]
    fn terrain_display() {
        assert_eq!(format!("{}", TerrainType::Marsh), "marsh");
    }

    #[test]
    fn landmark_display() {
        assert_eq!(format!("{}", LandmarkKind::StandingStone), "standing_stone");
    }

    #[test]
    fn landmark_kind_methods() {
        assert!(LandmarkKind::Tower.is_structure());
        assert!(LandmarkKind::Bridge.is_structure());
        assert!(!LandmarkKind::Cave.is_structure());
        assert!(LandmarkKind::Shrine.is_marker());
        assert!(LandmarkKind::Cave.is_natural());
    }
}
