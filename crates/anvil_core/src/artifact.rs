//! Semantic artifact traits: [`Versioned`] and [`SemanticArtifact`].

use crate::error::ValidationErrors;

/// Every semantic artifact declares its schema version and identity.
///
/// Implementations for simple types can use the defaults; types that
/// need backward‑compatibility can override the version‑check method
/// without changing the trait API.
pub trait Versioned {
    /// The current schema version of this artifact.
    fn version(&self) -> u32;

    /// Returns the lowest schema version that this artifact can safely
    /// be processed as.  The default is the current version, meaning
    /// no backward‑compatibility is claimed.
    fn minimum_compatible_version(&self) -> u32 {
        self.version()
    }

    /// A human‑readable type name, useful for error messages and logging.
    fn artifact_type_name(&self) -> &'static str;
}

/// A validated piece of authored meaning.
///
/// Every LLM‑produced artifact must pass validation before it can enter
/// the deterministic pipeline.  Implementations must be **pure** — the
/// same input always produces the same validation result.
pub trait SemanticArtifact: Versioned {
    /// Validates this artifact, returning an empty `Vec` if it is correct
    /// and a list of `AnvilCoreError` if it is malformed.
    ///
    /// Collecting *all* errors at once lets the author fix every problem
    /// in a single pass rather than playing whack‑a‑mole with one error
    /// per run.
    fn validate(&self) -> ValidationErrors;

    /// A short, human‑readable summary of the validation state.
    fn validation_summary(&self) -> &str {
        "Valid"
    }
}
