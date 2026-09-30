//! The thin binding layer of Remich.
//!
//! This crate is the boundary and nothing else (docs/PLAN.md §1.2). It sits on
//! top of `remich_core`, and it is the one place engine types are allowed to
//! appear. The engine-free core stays free of them.
//!
//! Phase 1, step 2 turns the Step 1 skeleton into a real, loadable GDExtension:
//! the smallest genuine bridge that proves the engine can load this library,
//! call into Rust, and observe a value come back. Nothing more. Scoring, needs,
//! actions, utilities and the simulated day are Steps 3–5 (docs/PLAN.md).

use godot::prelude::*;

/// The single value Remich's bridge probe hands to Godot.
///
/// This is a probe, not game behaviour: it exists only so the engine has
/// something observable to receive across the boundary. Its string form is
/// what the step's rebuild measurement changes, and
/// `godot/bridge_probe.gd` verifies it against this declaration (see
/// `tools/stage_bridge.sh`, which derives the expectation from this line).
pub const BRIDGE_PROBE_VALUE: &str = "remich-bridge-v1";

/// The layer's own name, mirrored from the engine-free side of the boundary.
pub const LAYER_NAME: &str = "remich_gdext";

/// What this layer passes across the boundary to the core: the core's identity,
/// forwarded unchanged.
pub fn forward_core_name() -> &'static str {
    remich_core::CORE_NAME
}

/// The Godot-facing class behind the probe.
///
/// Deliberately a bare `Node` with one trivial method — no nodes of our own
/// design, no behaviour, no simulation. It exists so `ClassDB` has something
/// Godot can instantiate and call.
#[derive(GodotClass)]
#[class(base = Node)]
pub struct RemichBridge {
    base: Base<Node>,
}

#[godot_api]
impl INode for RemichBridge {
    fn init(base: Base<Node>) -> Self {
        Self { base }
    }
}

#[godot_api]
impl RemichBridge {
    /// One deliberately trivial callable. It crosses the Rust/Godot boundary in
    /// both directions: Godot calls it, Rust returns one observable value.
    #[func]
    fn bridge_probe(&self) -> GString {
        BRIDGE_PROBE_VALUE.into()
    }
}

/// The library's entry point type tag; `#[gdextension]` emits the
/// `gdext_rust_init` symbol that `godot/remich.gdextension` names.
struct RemichExtension;

#[gdextension]
unsafe impl ExtensionLibrary for RemichExtension {}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn layer_identifies_itself() {
        assert_eq!(LAYER_NAME, "remich_gdext");
    }

    #[test]
    fn boundary_forwards_to_the_core() {
        assert_eq!(forward_core_name(), "remich_core");
    }

    /// The bridge probe must stay recognisably a bridge probe: this is the
    /// prefix `godot/bridge_probe.gd` checks before it accepts a returned
    /// value as coming from this call and not from somewhere else.
    #[test]
    fn bridge_probe_value_is_a_probe() {
        assert!(BRIDGE_PROBE_VALUE.starts_with("remich-bridge-"));
        assert!(!BRIDGE_PROBE_VALUE.is_empty());
    }
}
