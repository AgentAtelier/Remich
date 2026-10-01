//! Action Catalogue Module
//!
//! Contains the complete catalogue of ~21 actions that NPCs can perform.
//! Organized by primary need as specified in GAME_DESIGN_SECTION_4.md Section 4.4.2.
//!
//! Sprint 18a: Each action now carries a primary_affordance_id linking it to
//! the most relevant affordance for skill progression.

use super::{Action, Need};
use crate::skill::AffordanceId;
use std::sync::OnceLock;
use thiserror::Error;

/// The action catalogue, embedded into the library at compile time.
///
/// Remich issue #9 / Phase 3 Step 1: a shipped library must not read its
/// runtime data from the checkout it happened to be built in. The bytes below
/// are the committed `assets/sim/actions.json` (26 actions, sha256 recorded in
/// `docs/anvil-import-phase1-step3.md`), baked in when this crate is compiled,
/// so `load_actions()` needs no `repo_path!`, no file handle and no `std::fs`.
/// The data itself is unchanged: the same file, the same bytes, the same
/// parse. `embedded_catalogue_is_the_committed_file` proves the equality
/// against the on-disk asset, and only that test ever reads it.
const EMBEDDED_ACTIONS_JSON: &str = include_str!(concat!(
    env!("CARGO_MANIFEST_DIR"),
    "/../../assets/sim/actions.json"
));

/// Error type for action catalogue operations.
#[derive(Debug, Error)]
#[non_exhaustive]
pub enum ActionCatalogueError {
    /// Failed to read the catalogue file.
    #[error("failed to read actions file: {0}")]
    IoError(#[from] std::io::Error),
    /// Failed to parse the catalogue JSON.
    #[error("failed to parse actions JSON: {0}")]
    ParseError(#[from] serde_json::Error),
}

/// Loads the action catalogue embedded in this library.
///
/// Returns a `Result` so callers can decide whether to fail hard or
/// fall back to an empty catalogue.
///
/// Since Remich issue #9 the catalogue is the compile-time
/// `EMBEDDED_ACTIONS_JSON` text rather than a file reached through
/// `repo_path!`: no path is resolved, no file is opened and nothing under the
/// build checkout is read. Parsing is `serde_json::from_str` over those same
/// bytes, so the `Action` values, their order and the `ActionCatalogueError`
/// type are exactly what they were when the catalogue was loaded from disk.
pub fn load_actions() -> Result<Vec<Action>, ActionCatalogueError> {
    let actions: Vec<Action> = serde_json::from_str(EMBEDDED_ACTIONS_JSON)?;
    Ok(actions)
}

/// Cached action catalogue (lazy initialization).
static ACTIONS_CACHE: OnceLock<Vec<Action>> = OnceLock::new();

/// Returns the complete action catalogue, loading from JSON on first use.
pub fn actions() -> &'static Vec<Action> {
    ACTIONS_CACHE.get_or_init(|| {
        load_actions().expect("Failed to load actions catalogue")
    })
}


/// Returns actions for a specific primary need.
pub fn actions_for_need(need: Need) -> Vec<Action> {
    actions()
        .iter()
        .filter(|a| a.primary_need == need)
        .cloned()
        .collect()
}

/// Returns the action with the given ID.
pub fn action_by_id(id: u64) -> Option<Action> {
    actions().iter().find(|a| a.id == id).cloned()
}

/// Returns actions that exercise a specific affordance.
pub fn actions_for_affordance(affordance_id: AffordanceId) -> Vec<Action> {
    actions()
        .iter()
        .filter(|a| a.primary_affordance_id == Some(affordance_id))
        .cloned()
        .collect()
}

/// Returns the primary affordance ID for an action ID.
pub fn affordance_id_for_action(action_id: u64) -> Option<AffordanceId> {
    action_by_id(action_id).and_then(|a| a.primary_affordance_id)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_all_actions_have_affordances() {
        let actions = actions();
        // Count actions with and without affordances
        let with_affordance: Vec<&Action> = actions.iter()
            .filter(|a| a.primary_affordance_id.is_some())
            .collect();
        let without_affordance: Vec<&Action> = actions.iter()
            .filter(|a| a.primary_affordance_id.is_none())
            .collect();
        
        // Most actions should have affordances (only Sleep, Rest, Steal don't)
        // Sprint 18c: 26 total actions (21 original + 5 child), 3 without affordances
        assert_eq!(without_affordance.len(), 3);
        assert_eq!(with_affordance.len(), 23);
    }

    #[test]
    fn test_affordance_mapping_farm_tend() {
        let action = action_by_id(1).unwrap();
        assert_eq!(action.name, "Farm/Tend");
        assert_eq!(action.primary_affordance_id, Some(AffordanceId::new(20)));
    }

    #[test]
    fn test_affordance_mapping_hunt() {
        let action = action_by_id(2).unwrap();
        assert_eq!(action.name, "Hunt");
        assert_eq!(action.primary_affordance_id, Some(AffordanceId::new(31)));
    }

    #[test]
    fn test_affordance_mapping_build_repair() {
        let action = action_by_id(8).unwrap();
        assert_eq!(action.name, "Build/Repair");
        assert_eq!(action.primary_affordance_id, Some(AffordanceId::new(2))); // joint_fit_preview (Woodcraft)
    }

    #[test]
    fn test_affordance_mapping_tell_story() {
        let action = action_by_id(17).unwrap();
        assert_eq!(action.name, "Tell Story");
        assert_eq!(action.primary_affordance_id, Some(AffordanceId::new(61)));
    }

    #[test]
    fn test_actions_for_affordance() {
        let actions = actions_for_affordance(AffordanceId::new(20));
        assert_eq!(actions.len(), 1);
        assert_eq!(actions[0].name, "Farm/Tend");
    }

    #[test]
    fn test_affordance_id_for_action() {
        let affordance_id = affordance_id_for_action(1).unwrap();
        assert_eq!(affordance_id, AffordanceId::new(20));
    }

    #[test]
    fn test_affordance_id_for_action_none() {
        // Sleep has no affordance
        let affordance_id = affordance_id_for_action(14);
        assert!(affordance_id.is_none());
    }

    // ============================================================
    // Playbook 5 - CI tests for JSON loading
    // ============================================================
    #[test]
    fn actions_json_loads() {
        let actions = load_actions()
            .expect("actions.json must be loadable");
        assert!(!actions.is_empty());
    }

    // ============================================================
    // Remich issue #9 / Phase 3 Step 1 - the embedded catalogue
    // ============================================================
    /// The compile-time catalogue must be the committed
    /// `assets/sim/actions.json` byte for byte, and it must parse to the 26
    /// actions the donor tests assert.
    ///
    /// Reading the file here is test-only proof of equality; the runtime
    /// `load_actions()` above never touches the filesystem.
    #[test]
    fn embedded_catalogue_is_the_committed_file() {
        let committed = std::fs::read_to_string(concat!(
            env!("CARGO_MANIFEST_DIR"),
            "/../../assets/sim/actions.json"
        ))
        .expect("the committed assets/sim/actions.json must be readable in tests");
        assert_eq!(EMBEDDED_ACTIONS_JSON, committed.as_str());

        let parsed: Vec<Action> = serde_json::from_str(EMBEDDED_ACTIONS_JSON)
            .expect("the embedded catalogue must parse");
        assert_eq!(parsed.len(), 26);
    }
}
