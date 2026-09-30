use serde::{Deserialize, Serialize};
use std::fmt;

/// Identifies a region within a `WorldAuthored`.
/// The inner value is an index into `WorldAuthored::regions`.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize, PartialOrd, Ord)]
#[serde(transparent)]
pub struct RegionId(usize);

impl RegionId {
    /// Create a new `RegionId` from a raw index.
    pub const fn new(id: usize) -> Self {
        Self(id)
    }

    /// Get the underlying index value.
    /// This is the position in `WorldAuthored::regions` Vec.
    pub const fn get(self) -> usize {
        self.0
    }
}

impl fmt::Display for RegionId {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(f, "Region #{}", self.0)
    }
}
