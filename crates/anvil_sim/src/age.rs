//! Continuous Age Curves for Forgeborn NPCs.
//!
//! Implements Sprint 18c Task 2: Continuous age curves replacing the discrete
//! AgeCategory system.
//!
//! Age is stored as `age_days: f32` and all capability modifiers are computed
//! from smooth curves rather than discrete categories.

use anvil_core::{FailureClass, ValidationErrors, error_buffer, push_validation_error};
use serde::{Deserialize, Serialize};

/// Age in days for an NPC.
///
/// Stored as f32 to allow for fractional days and smooth interpolation
/// between breakpoints in the capability curves.
#[derive(Debug, Clone, Copy, PartialEq, Serialize, Deserialize)]
pub struct Age {
    /// Age in days.
    pub days: f32,
}

impl Age {
    /// Creates a new Age with the given number of days.
    pub fn new(days: f32) -> Self {
        Self { days }
    }

    /// Creates an Age from years (convenience constructor).
    pub fn from_years(years: f32) -> Self {
        // Assuming 365 days per year for simplicity
        Self::new(years * 365.0)
    }

    /// Returns the age in years.
    pub fn years(&self) -> f32 {
        self.days / 365.0
    }

    /// Computes the learning rate multiplier based on age.
    ///
    /// Breakpoints (in years):
    /// - 0-5: 0.0 -> 0.5
    /// - 5-8: 0.5 -> 1.5
    /// - 8-12: 1.5 -> 2.0
    /// - 12-16: 2.0
    /// - 16-25: 2.0 -> 1.5
    /// - 25-40: 1.5 -> 1.0
    /// - 40-55: 1.0 -> 0.9
    /// - 55-70: 0.9 -> 0.75
    /// - 70-85: 0.75 -> 0.6
    /// - 85+: 0.6 -> 0.4
    ///
    /// Defined in Sprint 18c Task 2.
    pub fn learning_rate_multiplier(&self) -> f32 {
        let years = self.years();

        if years <= 0.0 {
            0.0
        } else if years <= 5.0 {
            // 0-5: linear from 0.0 to 0.5
            0.0 + (years / 5.0) * 0.5
        } else if years <= 8.0 {
            // 5-8: linear from 0.5 to 1.5
            0.5 + ((years - 5.0) / 3.0) * 1.0
        } else if years <= 12.0 {
            // 8-12: linear from 1.5 to 2.0
            1.5 + ((years - 8.0) / 4.0) * 0.5
        } else if years <= 16.0 {
            // 12-16: constant 2.0
            2.0
        } else if years <= 25.0 {
            // 16-25: linear from 2.0 to 1.5
            2.0 - ((years - 16.0) / 9.0) * 0.5
        } else if years <= 40.0 {
            // 25-40: linear from 1.5 to 1.0
            1.5 - ((years - 25.0) / 15.0) * 0.5
        } else if years <= 55.0 {
            // 40-55: linear from 1.0 to 0.9
            1.0 - ((years - 40.0) / 15.0) * 0.1
        } else if years <= 70.0 {
            // 55-70: linear from 0.9 to 0.75
            0.9 - ((years - 55.0) / 15.0) * 0.15
        } else if years <= 85.0 {
            // 70-85: linear from 0.75 to 0.6
            0.75 - ((years - 70.0) / 15.0) * 0.15
        } else {
            // 85+: linear from 0.6 to 0.4
            0.6 - ((years - 85.0) / 100.0) * 0.2
        }
    }

    /// Computes the physical capability modifier based on age.
    ///
    /// Breakpoints (in years):
    /// - 0-5: 0.0
    /// - 5-8: 0.15
    /// - 8-12: 0.4
    /// - 12-16: 0.7
    /// - 16-20: 0.9
    /// - 20-35: 1.0
    /// - 35-50: 0.95
    /// - 50-60: 0.85
    /// - 60-70: 0.7
    /// - 70-80: 0.5
    /// - 80+: 0.3
    ///
    /// Defined in Sprint 18c Task 2.
    pub fn physical_capability(&self) -> f32 {
        let years = self.years();

        if years < 5.0 {
            0.0
        } else if years < 8.0 {
            0.15
        } else if years < 12.0 {
            0.4
        } else if years < 16.0 {
            0.7
        } else if years < 20.0 {
            0.9
        } else if years <= 35.0 {
            1.0
        } else if years <= 50.0 {
            // 35-50: linear from 1.0 to 0.95
            1.0 - ((years - 35.0) / 15.0) * 0.05
        } else if years <= 60.0 {
            // 50-60: linear from 0.95 to 0.85
            0.95 - ((years - 50.0) / 10.0) * 0.1
        } else if years <= 70.0 {
            // 60-70: linear from 0.85 to 0.7
            0.85 - ((years - 60.0) / 10.0) * 0.15
        } else if years <= 80.0 {
            // 70-80: linear from 0.7 to 0.5
            0.7 - ((years - 70.0) / 10.0) * 0.2
        } else {
            // 80+: linear from 0.5 to 0.3 over 35 years
            0.5 - ((years - 80.0) / 35.0) * 0.2
        }
    }

    /// Computes the fluency expression modifier for physical skill domains.
    ///
    /// This modifier is applied to action_duration_multiplier for physical
    /// skill domains only.
    ///
    /// Breakpoints (in years):
    /// - 0-35: 1.0
    /// - 35-55: 0.98
    /// - 55-65: 0.9
    /// - 65-75: 0.75
    /// - 75-85: 0.6
    /// - 85+: 0.4
    ///
    /// Defined in Sprint 18c Task 2.
    pub fn fluency_expression_modifier(&self) -> f32 {
        let years = self.years();

        if years <= 35.0 {
            1.0
        } else if years <= 55.0 {
            // 35-55: linear from 1.0 to 0.98
            1.0 - ((years - 35.0) / 20.0) * 0.02
        } else if years <= 65.0 {
            // 55-65: linear from 0.98 to 0.9
            0.98 - ((years - 55.0) / 10.0) * 0.08
        } else if years <= 75.0 {
            // 65-75: linear from 0.9 to 0.75
            0.9 - ((years - 65.0) / 10.0) * 0.15
        } else if years <= 85.0 {
            // 75-85: linear from 0.75 to 0.6
            0.75 - ((years - 75.0) / 10.0) * 0.15
        } else {
            // 85+: linear from 0.6 to 0.4
            0.6 - ((years - 85.0) / 100.0) * 0.2
        }
    }

    /// Returns true if this age can perform actions requiring a minimum physical capability.
    ///
    /// Defined in Sprint 18c Task 2.
    pub fn can_perform_with_capability(&self, min_capability: f32) -> bool {
        self.physical_capability() >= min_capability
    }

    /// Returns the age category for backward compatibility.
    ///
    /// This is a legacy method for systems that still use discrete categories.
    pub fn to_age_category(&self) -> AgeCategory {
        let years = self.years();
        if years < 15.0 {
            AgeCategory::Child
        } else if years >= 60.0 {
            AgeCategory::Elder
        } else {
            AgeCategory::Adult
        }
    }

    /// Validates this age.
    pub fn validate(&self) -> ValidationErrors {
        let mut errors = error_buffer();

        if !self.days.is_finite() || self.days < 0.0 {
            push_validation_error!(
                errors,
                FailureClass::Semantic,
                "E185",
                "Age",
                "days",
                format!("{}", self.days),
                "age must be non-negative and finite"
            );
        }

        // Check for unreasonably high ages (cap at ~150 years for now)
        if self.days > 150.0 * 365.0 {
            push_validation_error!(
                errors,
                FailureClass::Semantic,
                "E186",
                "Age",
                "days",
                format!("{}", self.days),
                "age exceeds maximum reasonable value"
            );
        }

        errors
    }
}

impl Default for Age {
    fn default() -> Self {
        // Default to a young adult (20 years old)
        Self::from_years(20.0)
    }
}

use std::fmt;

impl fmt::Display for Age {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(f, "Age({:.1} days, {:.1} years)", self.days, self.years())
    }
}

/// Legacy AgeCategory for backward compatibility.
///
/// Sprint 18c introduces continuous age, but this enum is kept for
/// backward compatibility with existing systems.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize, Hash)]
#[serde(rename_all = "snake_case")]
#[non_exhaustive]
pub enum AgeCategory {
    /// Child - age < 15 in game terms.
    /// Cannot perform heavy physical work.
    Child,
    /// Adult - age 15-60 in game terms.
    /// Can perform all actions.
    Adult,
    /// Elder - age > 60 in game terms.
    /// Reduced physical capability but enhanced social influence.
    Elder,
    /// All ages can perform this action.
    All,
}

impl fmt::Display for AgeCategory {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            AgeCategory::Child => write!(f, "child"),
            AgeCategory::Adult => write!(f, "adult"),
            AgeCategory::Elder => write!(f, "elder"),
            AgeCategory::All => write!(f, "all"),
        }
    }
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_age_new() {
        let age = Age::new(365.0);
        assert_eq!(age.days, 365.0);
        assert!((age.years() - 1.0).abs() < 0.001);
    }

    #[test]
    fn test_age_from_years() {
        let age = Age::from_years(5.0);
        assert!((age.days - 1825.0).abs() < 0.001); // 5 * 365
    }

    #[test]
    fn test_learning_rate_multiplier_child() {
        let age = Age::from_years(4.0);
        let multiplier = age.learning_rate_multiplier();
        // At 4 years: 0.0 + (4/5) * 0.5 = 0.4
        assert!((multiplier - 0.4).abs() < 0.001);
    }

    #[test]
    fn test_learning_rate_multiplier_peak() {
        let age = Age::from_years(14.0);
        let multiplier = age.learning_rate_multiplier();
        // At 14 years: 2.0 (peak)
        assert!((multiplier - 2.0).abs() < 0.001);
    }

    #[test]
    fn test_learning_rate_multiplier_elder() {
        let age = Age::from_years(75.0);
        let multiplier = age.learning_rate_multiplier();
        // At 75 years: 0.75 - ((75-70)/15) * 0.15 = 0.75 - 0.05 = 0.70
        assert!((multiplier - 0.70).abs() < 0.001);
    }

    #[test]
    fn test_physical_capability_child() {
        let age = Age::from_years(4.0);
        assert_eq!(age.physical_capability(), 0.0);
    }

    #[test]
    fn test_physical_capability_peak() {
        let age = Age::from_years(25.0);
        assert_eq!(age.physical_capability(), 1.0);
    }

    #[test]
    fn test_physical_capability_elder() {
        let age = Age::from_years(75.0);
        let capability = age.physical_capability();
        // At 75 years: 0.7 - ((75-70)/10) * 0.2 = 0.7 - 0.1 = 0.6
        assert!((capability - 0.6).abs() < 0.001);
    }

    #[test]
    fn test_fluency_expression_modifier_peak() {
        let age = Age::from_years(30.0);
        assert_eq!(age.fluency_expression_modifier(), 1.0);
    }

    #[test]
    fn test_fluency_expression_modifier_elder() {
        let age = Age::from_years(80.0);
        let modifier = age.fluency_expression_modifier();
        // At 80 years: 0.75 - ((80-75)/10) * 0.15 = 0.75 - 0.075 = 0.675
        assert!((modifier - 0.675).abs() < 0.001);
    }

    #[test]
    fn test_can_perform_with_capability() {
        let age = Age::from_years(20.0);
        assert!(age.can_perform_with_capability(0.5));
        assert!(age.can_perform_with_capability(1.0));
        assert!(!age.can_perform_with_capability(1.1));
    }

    #[test]
    fn test_to_age_category() {
        assert_eq!(Age::from_years(5.0).to_age_category(), AgeCategory::Child);
        assert_eq!(Age::from_years(15.0).to_age_category(), AgeCategory::Adult);
        assert_eq!(Age::from_years(30.0).to_age_category(), AgeCategory::Adult);
        assert_eq!(Age::from_years(60.0).to_age_category(), AgeCategory::Elder);
        assert_eq!(Age::from_years(80.0).to_age_category(), AgeCategory::Elder);
    }

    #[test]
    fn test_validation_valid() {
        let age = Age::from_years(20.0);
        assert!(age.validate().is_empty());
    }

    #[test]
    fn test_validation_negative() {
        let age = Age::new(-1.0);
        let errors = age.validate();
        assert_eq!(errors.len(), 1);
        assert_eq!(errors[0].code().as_str(), "E185");
    }

    #[test]
    fn test_validation_too_high() {
        let age = Age::from_years(200.0);
        let errors = age.validate();
        assert_eq!(errors.len(), 1);
        assert_eq!(errors[0].code().as_str(), "E186");
    }

    #[test]
    fn test_default() {
        let age = Age::default();
        assert!((age.years() - 20.0).abs() < 0.001);
    }

    #[test]
    fn test_display() {
        let age = Age::from_years(25.0);
        let display = format!("{}", age);
        assert!(display.contains("9125.0 days"));
        assert!(display.contains("25.0 years"));
    }
}
