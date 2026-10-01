//! Settlement simulation types for Forgeborn.
//!
//! This module defines the core data types for settlements, people, and families
//! as specified in GAME_DESIGN_SECTION_3.md Sections 3.1, 3.3, 3.4, and 3.6,
//! and extended in Sprint 17 with GAME_DESIGN_SECTION_4.md.
//!
//! Phase 3 Step 2 — soul primitives across the bridge: two donor modules are
//! declared here and nothing else is added. The full donor declaration list
//! (`catalyst`, `family`, `memory`, `person`, `settlement_type` and their
//! re-exports) stays pruned exactly as Phase 1 Step 3 pruned it — this step
//! needs the edge-strength layer and the newtype ids it is parameterised by,
//! and takes no person, family, settlement, memory or NPC system.
//!
//! Provenance (both byte-identical):
//!
//! * `buggy-vault@24181142 repos/anvil/source/crates/anvil_sim/src/settlement/connection.rs`
//! * `buggy-vault@24181142 repos/anvil/source/crates/anvil_sim/src/settlement/ids.rs`

pub mod connection;
pub mod ids;
pub mod skill;

pub use connection::{Connection, ConnectionLayer};
pub use skill::Skill;
