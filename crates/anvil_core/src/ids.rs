//! Identity types: [`ArchetypeTag`] for assets and [`AuthoredEntityId`]
//! for authored entities.

use crate::{AnvilCoreError, ErrorCode, FailureClass};
use serde::{Deserialize, Serialize};
use std::borrow;
use std::fmt;

// ---------------------------------------------------------------------------
// AuthoredEntityId — type‑safe entity identifier
// ---------------------------------------------------------------------------

/// A unique identifier assigned to an entity during world compilation.
///
/// Wraps a `u64`; serialised transparently as a bare integer.
#[derive(Debug, Clone, Copy, PartialEq, Eq, PartialOrd, Ord, Hash, Serialize, Deserialize)]
#[serde(transparent)]
pub struct AuthoredEntityId(pub u64);

impl AuthoredEntityId {
    /// Canonical constructor.
    pub const fn new(value: u64) -> Self {
        Self(value)
    }

    /// Returns the raw `u64` value.
    pub const fn get(self) -> u64 {
        self.0
    }
}

impl fmt::Display for AuthoredEntityId {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(f, "#{}", self.0)
    }
}

// ---------------------------------------------------------------------------
// ArchetypeTag — validated asset archetype identifier
// ---------------------------------------------------------------------------

/// A validated archetype tag referencing a catalogue entry.
///
/// Tags must match the pattern `[a-z][a-z0-9_]*` — lowercase letters,
/// digits, and underscores only, starting with a letter.
///
/// Use `ArchetypeTag::missing()` as a fallback when catalogue resolution fails.
#[derive(Debug, Clone, PartialEq, Eq, PartialOrd, Ord, Hash, Serialize, Deserialize)]
#[serde(transparent)]
pub struct ArchetypeTag(String);

impl ArchetypeTag {
    /// Fallback tag used when catalogue resolution fails.
    /// Returns a tag with the string `"missing"`.
    pub fn missing() -> Self {
        Self("missing".to_string())
    }

    /// Creates a new `ArchetypeTag`, validating the tag format.
    ///
    /// Tags must be non‑empty, contain only lowercase letters, digits,
    /// and underscores, and start with a letter.
    #[allow(clippy::result_large_err)]
    pub fn new(value: impl Into<String>) -> Result<Self, AnvilCoreError> {
        let value: String = value.into();

        // --- validation ---
        if value.trim().is_empty() {
            return Err(AnvilCoreError::validation(
                FailureClass::Structural,
                ErrorCode::new("E020"),
                "ArchetypeTag",
                "value",
                value,
                "archetype tag cannot be empty",
            ));
        }

        // Pattern: start with lowercase letter, then letters/digits/underscores
        let valid = value.chars().enumerate().all(|(i, c)| {
            if i == 0 {
                c.is_ascii_lowercase()
            } else {
                c.is_ascii_lowercase() || c.is_ascii_digit() || c == '_'
            }
        });

        if !valid {
            return Err(AnvilCoreError::validation(
                FailureClass::Semantic,
                ErrorCode::new("E021"),
                "ArchetypeTag",
                "value",
                value,
                "tag must start with a lowercase letter and contain only lowercase letters, digits, and underscores",
            ));
        }

        Ok(Self(value))
    }

    /// Returns the tag as a string slice.
    pub fn as_str(&self) -> &str {
        &self.0
    }

}

impl borrow::Borrow<str> for ArchetypeTag {
    fn borrow(&self) -> &str {
        self.as_str()
    }
}

impl fmt::Display for ArchetypeTag {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(f, "{}", self.0)
    }
}

/// Compile-time-validated archetype tag literal.
///
/// `arche!("forest_settlement_small")` expands to a runtime construction
/// that is statically guaranteed to succeed: invalid format produces a
/// compile error, not a runtime panic.
///
/// # Examples
///
/// ```
/// use anvil_core::arche;
/// let tag = arche!("grass");
/// assert_eq!(tag.as_str(), "grass");
/// ```
///
/// ```compile_fail
/// use anvil_core::arche;
/// let _ = arche!("Has-Capitals");  // compile error – capitals not allowed
/// ```
#[macro_export]
macro_rules! arche {
    ($lit:literal) => {{
        const _: () = {
            let bytes = $lit.as_bytes();
            assert!(!bytes.is_empty(), "ArchetypeTag must not be empty");
            assert!(
                bytes[0].is_ascii_lowercase(),
                "ArchetypeTag must start with a lowercase letter"
            );
            let mut i = 1;
            while i < bytes.len() {
                let b = bytes[i];
                assert!(
                    b.is_ascii_lowercase() || b.is_ascii_digit() || b == b'_',
                    "ArchetypeTag must contain only lowercase letters, digits, and underscores"
                );
                i += 1;
            }
        };
        // SAFETY: the const block above proved $lit is a valid ArchetypeTag.
        #[allow(clippy::expect_used)]
        $crate::ArchetypeTag::new($lit).expect("validated by arche! macro")
    }};
}
