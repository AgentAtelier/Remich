//! The thin binding layer of Remich.
//!
//! This crate is the boundary and nothing else (docs/PLAN.md §1.2). It sits on
//! top of `remich_core`, and it is the one place engine types are allowed to
//! appear. The engine-free core stays free of them.
//!
//! Step 1 stops at the skeleton: no engine binding is chosen or added, no
//! engine-facing calls, no nodes. Step 2 picks the binding version that
//! supports the pinned engine, and only then does this crate grow engine types.

/// The layer's own name, mirrored from the engine-free side of the boundary.
pub const LAYER_NAME: &str = "remich_gdext";

/// What this layer passes across the boundary in Step 1: the core's identity,
/// forwarded unchanged. A stand-in for real calls until Step 2 adds them.
pub fn forward_core_name() -> &'static str {
    remich_core::CORE_NAME
}

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
}
