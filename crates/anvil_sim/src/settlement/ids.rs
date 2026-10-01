//! Newtype identifiers for settlement simulation entities.

use anvil_core::ValidationErrors;
use serde::{Deserialize, Serialize};
use std::fmt;

/// A unique identifier for a settlement.
#[derive(Debug, Clone, Copy, PartialEq, Eq, PartialOrd, Ord, Hash, Serialize, Deserialize)]
#[serde(transparent)]
pub struct SettlementId(pub u64);

impl SettlementId {
    /// Creates a new settlement identifier.
    pub const fn new(value: u64) -> Self {
        Self(value)
    }

    /// Returns the raw numeric value.
    pub const fn get(self) -> u64 {
        self.0
    }
}

impl fmt::Display for SettlementId {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(f, "settlement#{}", self.0)
    }
}

/// A unique identifier for a person (NPC).
#[derive(Debug, Clone, Copy, PartialEq, Eq, PartialOrd, Ord, Hash, Serialize, Deserialize)]
#[serde(transparent)]
pub struct PersonId(pub u64);

impl PersonId {
    /// Creates a new person identifier.
    pub const fn new(value: u64) -> Self {
        Self(value)
    }

    /// Returns the raw numeric value.
    pub const fn get(self) -> u64 {
        self.0
    }
}

impl fmt::Display for PersonId {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(f, "person#{}", self.0)
    }
}

/// A unique identifier for a family.
#[derive(Debug, Clone, Copy, PartialEq, Eq, PartialOrd, Ord, Hash, Serialize, Deserialize)]
#[serde(transparent)]
pub struct FamilyId(pub u64);

impl FamilyId {
    /// Creates a new family identifier.
    pub const fn new(value: u64) -> Self {
        Self(value)
    }

    /// Returns the raw numeric value.
    pub const fn get(self) -> u64 {
        self.0
    }
}

impl fmt::Display for FamilyId {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(f, "family#{}", self.0)
    }
}

/// A unique identifier for a catalyst event.
#[derive(Debug, Clone, Copy, PartialEq, Eq, PartialOrd, Ord, Hash, Serialize, Deserialize)]
#[serde(transparent)]
pub struct CatalystEventId(pub u64);

impl CatalystEventId {
    /// Creates a new catalyst event identifier.
    pub const fn new(value: u64) -> Self {
        Self(value)
    }

    /// Returns the raw numeric value.
    pub const fn get(self) -> u64 {
        self.0
    }
}

impl fmt::Display for CatalystEventId {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(f, "catalyst#{}", self.0)
    }
}

/// Validation for all ID types - they must have non-zero values.
impl SettlementId {
    /// Validates the settlement ID.
    pub fn validate(&self) -> ValidationErrors {
        use anvil_core::{FailureClass, push_validation_error};
        let mut errors = Vec::new();
        if self.0 == 0 {
            push_validation_error!(
                errors,
                FailureClass::Structural,
                "E150",
                "SettlementId",
                "value",
                format!("{}", self.0),
                "settlement ID must be non-zero"
            );
        }
        errors
    }
}

impl PersonId {
    /// Validates the person ID.
    pub fn validate(&self) -> ValidationErrors {
        use anvil_core::{FailureClass, push_validation_error};
        let mut errors = Vec::new();
        if self.0 == 0 {
            push_validation_error!(
                errors,
                FailureClass::Structural,
                "E151",
                "PersonId",
                "value",
                format!("{}", self.0),
                "person ID must be non-zero"
            );
        }
        errors
    }
}

impl FamilyId {
    /// Validates the family ID.
    pub fn validate(&self) -> ValidationErrors {
        use anvil_core::{FailureClass, push_validation_error};
        let mut errors = Vec::new();
        if self.0 == 0 {
            push_validation_error!(
                errors,
                FailureClass::Structural,
                "E152",
                "FamilyId",
                "value",
                format!("{}", self.0),
                "family ID must be non-zero"
            );
        }
        errors
    }
}

impl CatalystEventId {
    /// Validates the catalyst event ID.
    pub fn validate(&self) -> ValidationErrors {
        use anvil_core::{FailureClass, push_validation_error};
        let mut errors = Vec::new();
        if self.0 == 0 {
            push_validation_error!(
                errors,
                FailureClass::Structural,
                "E153",
                "CatalystEventId",
                "value",
                format!("{}", self.0),
                "catalyst event ID must be non-zero"
            );
        }
        errors
    }
}
