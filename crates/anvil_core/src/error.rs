//! Error infrastructure: [`AnvilCoreError`], [`ErrorCode`],
//! [`ValidationLevel`], and the [`push_validation_error!`] macro.

use serde::{Deserialize, Serialize};
use std::fmt;

// ---------------------------------------------------------------------------
// ValidationError trait — common interface for structured validation errors
// ---------------------------------------------------------------------------

/// Common interface for all structured validation errors in the workspace.
///
/// Every validation error must provide these fields for consistent error reporting.
pub trait ValidationError: std::error::Error {
    /// The error code (e.g., "E001").
    fn error_code(&self) -> &str;
    /// The type of artifact being validated (e.g., "RegionSpec").
    fn artifact_type(&self) -> &str;
    /// The name of the field that failed validation.
    fn field_name(&self) -> &str;
    /// The invalid value that was encountered.
    fn invalid_value(&self) -> &str;
    /// A human-readable description of the validation failure.
    fn message(&self) -> &str;
}

// ---------------------------------------------------------------------------
// FailureClass — the three categories of failure
// ---------------------------------------------------------------------------

/// Every error belongs to exactly one failure class, which determines
/// how the pipeline should respond.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[non_exhaustive]
pub enum FailureClass {
    /// A bug in the code.  Fix the source and recompile.
    Structural,

    /// The LLM or authored data produced invalid output.  Re‑prompt
    /// or fix the data.
    Semantic,

    /// A file, mesh, texture, or other asset is missing or malformed.
    /// Fix the asset pipeline.
    Asset,
}

impl fmt::Display for FailureClass {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            FailureClass::Structural => write!(f, "structural"),
            FailureClass::Semantic => write!(f, "semantic"),
            FailureClass::Asset => write!(f, "asset"),
        }
    }
}

// ---------------------------------------------------------------------------
// ValidationLevel
// ---------------------------------------------------------------------------

/// Whether a validation issue is fatal or advisory.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[non_exhaustive]
pub enum ValidationLevel {
    /// The pipeline cannot proceed with this artifact.
    Error,

    /// The artifact is usable but the author should review it.
    Warning,
}

impl fmt::Display for ValidationLevel {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            ValidationLevel::Error => write!(f, "ERROR"),
            ValidationLevel::Warning => write!(f, "WARNING"),
        }
    }
}

// ---------------------------------------------------------------------------
// ErrorCode — unique searchable identifier for every validation failure
// ---------------------------------------------------------------------------

/// A short machine‑readable error code, e.g. `"E003"`.
///
/// Maintained in `crates/anvil_core/ERROR_CODES.md`.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct ErrorCode(String);

impl ErrorCode {
    /// Creates a new error code from a string slice.
    pub fn new(code: &str) -> Self {
        ErrorCode(code.to_string())
    }

    /// Returns the error code as a string slice.
    pub fn as_str(&self) -> &str {
        &self.0
    }
}

impl std::fmt::Display for ErrorCode {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> fmt::Result {
        write!(f, "{}", self.0)
    }
}

impl From<&str> for ErrorCode {
    fn from(s: &str) -> Self {
        ErrorCode::new(s)
    }
}

impl From<String> for ErrorCode {
    fn from(s: String) -> Self {
        ErrorCode(s)
    }
}

// ---------------------------------------------------------------------------
// AnvilCoreError
// ---------------------------------------------------------------------------

/// The unified error type for `anvil_core`.
///
/// Every validation failure produces one of these.  The error message
/// is structured so that the terminal output tells you **what went
/// wrong, where, why, and what to do about it** — without needing to
/// read source code or stack traces.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[non_exhaustive]
pub enum AnvilCoreError {
    /// A validation check on an authored artifact failed.
    ValidationFailed {
        /// Which failure class.
        class: FailureClass,

        /// Whether this is an error or a warning.
        level: ValidationLevel,

        /// Unique error code, e.g. `ErrorCode("E003")`.
        code: ErrorCode,

        /// The type of artifact that failed, e.g. `"ConnectionSpec"`.
        artifact_type: String,

        /// The specific field that failed, e.g. `"from_region"`.
        field: String,

        /// The invalid value (truncated if very long).
        value: String,

        /// What went wrong, e.g. `"must not be empty"`.
        message: String,

        /// Optional: what to do about it.
        hint: Option<String>,

        /// Optional: file and line where the error was created.
        location: Option<(String, u32)>,

        /// Optional: source location as a string (e.g., "asset_request.rs:42").
        source_location: Option<String>,
    },
}

impl std::fmt::Display for AnvilCoreError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Self::ValidationFailed {
                class,
                level: _,
                code,
                artifact_type,
                field,
                value,
                message,
                hint,
                location,
                source_location,
            } => {
                write!(
                    f,
                    "[{}] [{}] {}.{} = {:?}: {}",
                    code, class, artifact_type, field, value, message
                )?;
                if let Some(hint) = hint {
                    write!(f, "\n  Hint: {}", hint)?;
                }
                if let Some((file, line)) = location {
                    write!(f, "\n  At: {}:{}", file, line)?;
                }
                if let Some(sl) = source_location {
                    write!(f, "\n  Source: {}", sl)?;
                }
                Ok(())
            }
        }
    }
}

impl std::error::Error for AnvilCoreError {}

impl ValidationError for AnvilCoreError {
    fn error_code(&self) -> &str {
        self.code().as_str()
    }
    fn artifact_type(&self) -> &str {
        self.artifact_type()
    }
    fn field_name(&self) -> &str {
        self.field()
    }
    fn invalid_value(&self) -> &str {
        self.value()
    }
    fn message(&self) -> &str {
        self.message()
    }
}

impl AnvilCoreError {
    // ------------------------------------------------------------------
    // Constructors
    // ------------------------------------------------------------------

    /// Create a validation error with all fields populated.
    pub fn validation(
        class: FailureClass,
        code: ErrorCode,
        artifact_type: impl Into<String>,
        field: impl Into<String>,
        value: impl Into<String>,
        message: impl Into<String>,
    ) -> Self {
        Self::ValidationFailed {
            class,
            level: ValidationLevel::Error,
            code,
            artifact_type: artifact_type.into(),
            field: field.into(),
            value: value.into(),
            message: message.into(),
            hint: None,
            location: None,
            source_location: None,
        }
    }

    // ------------------------------------------------------------------
    // Builder methods (fluent API)
    // ------------------------------------------------------------------

    /// Mark this as a warning rather than a fatal error.
    pub fn into_warning(mut self) -> Self {
        match self {
            Self::ValidationFailed { ref mut level, .. } => {
                *level = ValidationLevel::Warning;
            }
        }
        self
    }

    /// Attach a fix hint that will appear in the rendered error message.
    pub fn with_hint(mut self, hint_text: impl Into<String>) -> Self {
        match self {
            Self::ValidationFailed { ref mut hint, .. } => {
                *hint = Some(hint_text.into());
            }
        }
        self
    }

    /// Attach the source location (file and line) to the error.
    /// Call with `file!()` and `line!()` from the call site.
    pub fn at_location(mut self, file: &str, line: u32) -> Self {
        match self {
            Self::ValidationFailed {
                ref mut location, ..
            } => {
                *location = Some((file.to_string(), line));
            }
        }
        self
    }

    /// Attach a source location string (e.g., "asset_request.rs:42") to the error.
    pub fn with_source_location(mut self, location: impl Into<String>) -> Self {
        match self {
            Self::ValidationFailed {
                ref mut source_location,
                ..
            } => {
                *source_location = Some(location.into());
            }
        }
        self
    }

    /// Builder‑style convenience for validation errors.
    #[deprecated = "Use validation() instead"]
    pub fn validation_failed(
        class: FailureClass,
        code: ErrorCode,
        artifact_type: impl Into<String>,
        field: impl Into<String>,
        value: impl Into<String>,
        message: impl Into<String>,
    ) -> Self {
        Self::validation(class, code, artifact_type, field, value, message)
    }

    // ------------------------------------------------------------------
    // Queries / Field accessors
    // ------------------------------------------------------------------

    /// The failure class for this error.
    pub fn failure_class(&self) -> FailureClass {
        match self {
            Self::ValidationFailed { class, .. } => *class,
        }
    }

    /// `true` if this is a warning rather than a fatal error.
    pub fn is_warning(&self) -> bool {
        match self {
            Self::ValidationFailed { level, .. } => *level == ValidationLevel::Warning,
        }
    }

    /// Returns the error code.
    pub fn code(&self) -> &ErrorCode {
        match self {
            Self::ValidationFailed { code, .. } => code,
        }
    }

    /// Returns the field name.
    pub fn field(&self) -> &str {
        match self {
            Self::ValidationFailed { field, .. } => field.as_str(),
        }
    }

    /// Returns the invalid value.
    pub fn value(&self) -> &str {
        match self {
            Self::ValidationFailed { value, .. } => value.as_str(),
        }
    }

    /// Returns the message.
    pub fn message(&self) -> &str {
        match self {
            Self::ValidationFailed { message, .. } => message.as_str(),
        }
    }

    /// Returns the artifact type.
    pub fn artifact_type(&self) -> &str {
        match self {
            Self::ValidationFailed { artifact_type, .. } => artifact_type.as_str(),
        }
    }

    /// Returns the validation level.
    pub fn level(&self) -> ValidationLevel {
        match self {
            Self::ValidationFailed { level, .. } => *level,
        }
    }
}

// ---------------------------------------------------------------------------
// Helper: collect multiple errors
// ---------------------------------------------------------------------------

/// A collection of validation errors returned from a single `validate()` call.
pub type ValidationErrors = Vec<AnvilCoreError>;

/// Convenience: create a pre‑allocated error buffer.
pub fn error_buffer() -> ValidationErrors {
    Vec::with_capacity(8)
}

// ---------------------------------------------------------------------------
// Macro: push_validation_error!
// ---------------------------------------------------------------------------

/// Pushes a structured validation error with all fields populated.
///
/// This macro provides a concise way to add validation errors to a collection
/// while preserving the error code, type, field path, invalid value, message,
/// optional hint, and source location.
///
/// # Examples
///
/// ```ignore
/// push_validation_error!(
///     errors, FailureClass::Semantic, "E001",
///     "ConnectionSpec", "from_region", &self.from_region,
///     "must not be empty"
/// );
///
/// // With optional hint
/// push_validation_error!(
///     errors, FailureClass::Semantic, "E015",
///     "RegionSpec", "name", &self.name,
///     "region name cannot be empty",
///     hint = "Provide a non-empty name for the region."
/// );
/// ```
#[macro_export]
macro_rules! push_validation_error {
    ($errors:expr, $class:expr, $code:literal, $artifact:expr, $field:expr, $value:expr, $msg:expr) => {
        $errors.push(
            $crate::AnvilCoreError::validation(
                $class,
                $crate::ErrorCode::new($code),
                $artifact,
                $field,
                $value,
                $msg,
            )
            .at_location(file!(), line!()),
        );
    };
    ($errors:expr, $class:expr, $code:literal, $artifact:expr, $field:expr, $value:expr, $msg:expr, hint = $hint:expr) => {
        $errors.push(
            $crate::AnvilCoreError::validation(
                $class,
                $crate::ErrorCode::new($code),
                $artifact,
                $field,
                $value,
                $msg,
            )
            .with_hint($hint)
            .at_location(file!(), line!()),
        );
    };
    ($errors:expr, $class:expr, $code:literal, $artifact:expr, $field:expr, $value:expr, $msg:expr, warning) => {
        $errors.push(
            $crate::AnvilCoreError::validation(
                $class,
                $crate::ErrorCode::new($code),
                $artifact,
                $field,
                $value,
                $msg,
            )
            .into_warning()
            .at_location(file!(), line!()),
        );
    };
    ($errors:expr, $class:expr, $code:literal, $artifact:expr, $field:expr, $value:expr, $msg:expr, warning, hint = $hint:expr) => {
        $errors.push(
            $crate::AnvilCoreError::validation(
                $class,
                $crate::ErrorCode::new($code),
                $artifact,
                $field,
                $value,
                $msg,
            )
            .into_warning()
            .with_hint($hint)
            .at_location(file!(), line!()),
        );
    };
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

#[cfg(test)]
#[allow(clippy::vec_init_then_push)]
mod tests {
    use super::*;

    #[test]
    fn error_code_new() {
        let code = ErrorCode::new("E001");
        assert_eq!(code.0, "E001");
    }

    #[test]
    fn validation_failed_display() {
        let err = AnvilCoreError::validation(
            FailureClass::Semantic,
            ErrorCode::new("E001"),
            "ConnectionSpec",
            "from_region",
            "",
            "must not be empty",
        )
        .with_hint("Provide a non-empty region name")
        .at_location("test.rs", 42);

        let display = err.to_string();
        assert!(display.contains("E001"));
        assert!(display.contains("semantic"));
        assert!(display.contains("ConnectionSpec.from_region"));
        assert!(display.contains("must not be empty"));
        assert!(display.contains("Hint:"));
        assert!(display.contains("At:"));
    }

    #[test]
    fn field_accessors_work() {
        let err = AnvilCoreError::validation(
            FailureClass::Asset,
            ErrorCode::new("E020"),
            "ArchetypeTag",
            "value",
            "bad_tag",
            "tag format invalid",
        );

        assert_eq!(err.code().as_str(), "E020");
        assert_eq!(err.field(), "value");
        assert_eq!(err.value(), "bad_tag");
        assert_eq!(err.message(), "tag format invalid");
        assert_eq!(err.artifact_type(), "ArchetypeTag");
        assert_eq!(err.level(), ValidationLevel::Error);
        assert_eq!(err.failure_class(), FailureClass::Asset);
    }

    #[test]
    fn display_for_failure_class() {
        assert_eq!(format!("{}", FailureClass::Structural), "structural");
        assert_eq!(format!("{}", FailureClass::Semantic), "semantic");
        assert_eq!(format!("{}", FailureClass::Asset), "asset");
    }

    #[test]
    fn display_for_validation_level() {
        assert_eq!(format!("{}", ValidationLevel::Error), "ERROR");
        assert_eq!(format!("{}", ValidationLevel::Warning), "WARNING");
    }

    #[test]
    fn push_validation_error_macro_basic() {
        let mut errors: ValidationErrors = vec![];
        push_validation_error!(
            errors,
            FailureClass::Semantic,
            "E999",
            "TestType",
            "field",
            "bad_value",
            "test message"
        );

        assert_eq!(errors.len(), 1);
        assert_eq!(errors[0].code().0, "E999");
        assert_eq!(errors[0].field(), "field");
    }

    #[test]
    fn push_validation_error_macro_with_hint() {
        let mut errors: ValidationErrors = vec![];
        push_validation_error!(
            errors,
            FailureClass::Semantic,
            "E998",
            "TestType",
            "field",
            "bad_value",
            "test message",
            hint = "fix it this way"
        );

        assert_eq!(errors.len(), 1);
        assert!(errors[0].to_string().contains("fix it this way"));
    }

    #[test]
    fn into_warning() {
        let err = AnvilCoreError::validation(
            FailureClass::Semantic,
            ErrorCode::new("E001"),
            "TestType",
            "field",
            "value",
            "message",
        )
        .into_warning();

        assert!(err.is_warning());
        assert_eq!(err.level(), ValidationLevel::Warning);
    }
}
