use serde::{Deserialize, Serialize};
use std::fmt;

/// The categorical classification of an entity within the world.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
#[non_exhaustive]
pub enum EntityKind {
    /// Named point of interest in a region.
    Landmark,
    /// Decorative or functional object.
    Prop,
    /// Location where entities can be spawned.
    SpawnPoint,
    /// Interactive zone that triggers events.
    Trigger,
    /// Navigation point along a path.
    Waypoint,
    /// Connection between regions.
    Connection,
}

impl fmt::Display for EntityKind {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            EntityKind::Landmark => write!(f, "landmark"),
            EntityKind::Prop => write!(f, "prop"),
            EntityKind::SpawnPoint => write!(f, "spawn_point"),
            EntityKind::Trigger => write!(f, "trigger"),
            EntityKind::Waypoint => write!(f, "waypoint"),
            EntityKind::Connection => write!(f, "connection"),
        }
    }
}
