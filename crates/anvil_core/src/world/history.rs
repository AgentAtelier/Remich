use crate::error::{FailureClass, ValidationErrors, error_buffer};
use crate::push_validation_error;
use crate::world::DamageType;
use serde::{Deserialize, Serialize};

/// A disaster event that affects the world.
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct HistoryEvent {
    /// The type of damage caused by this event.
    pub damage_type: DamageType,
    /// The severity of the event, in the range [0.0, 1.0].
    pub magnitude: f32,
    /// The world-space position where the event originated, as [x, y, z].
    pub epicenter: [f32; 3],
    /// The radius of the event's effect area.
    pub radius: f32,
    /// The simulation tick at which this event occurred.
    pub tick: u64,
}

impl HistoryEvent {
    /// Validate a single event, returning all problems found.
    pub fn validate(&self) -> ValidationErrors {
        let mut errors = error_buffer();

        if !self.magnitude.is_finite() || self.magnitude < 0.0 || self.magnitude > 1.0 {
            push_validation_error!(
                errors,
                FailureClass::Semantic,
                "E030",
                "HistoryEvent",
                "magnitude",
                format!("{}", self.magnitude),
                "magnitude must be in [0.0, 1.0]"
            );
        }

        if !self.radius.is_finite() || self.radius <= 0.0 {
            push_validation_error!(
                errors,
                FailureClass::Semantic,
                "E031",
                "HistoryEvent",
                "radius",
                format!("{}", self.radius),
                "radius must be positive"
            );
        }

        if !self.epicenter.iter().all(|v| v.is_finite()) {
            push_validation_error!(
                errors,
                FailureClass::Semantic,
                "E032",
                "HistoryEvent",
                "epicenter",
                format!("{:?}", self.epicenter),
                "epicenter contains non‑finite values"
            );
        }

        errors
    }
}

/// Validate a collection of history events, including tick ordering.
pub fn validate_event_ordering(events: &[HistoryEvent]) -> ValidationErrors {
    let mut errors = error_buffer();

    for event in events {
        errors.extend(event.validate());
    }

    // Check strictly ascending ticks.
    for i in 1..events.len() {
        if events[i].tick <= events[i - 1].tick {
            push_validation_error!(
                errors,
                FailureClass::Semantic,
                "E033",
                "HistoryEvent",
                format!("events[{}].tick", i),
                format!("{}", events[i].tick),
                "ticks must be strictly ascending"
            );
        }
    }

    errors
}
