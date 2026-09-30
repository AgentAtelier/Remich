//! The engine-free core of Remich.
//!
//! The firewall (docs/PLAN.md §1.2): everything in this crate is plain Rust.
//! It has no engine dependency and no engine types. Anything that needs engine
//! types belongs one layer above, in the thin binding crate, which is the only
//! place they are allowed to appear.
//!
//! Phase 1, Step 1 leaves this a skeleton on purpose. Scoring, needs, actions
//! and utilities arrive in later steps and are deliberately absent here. What
//! has to hold from the first commit is the shape: this crate builds, tests,
//! and knows nothing about the engine.

/// The name this crate answers to across the boundary.
///
/// Placeholder so the workspace has something to build, link and assert on
/// before the binding layer exists; Step 2 gives the boundary real work.
pub const CORE_NAME: &str = "remich_core";

#[cfg(test)]
mod tests {
    use super::CORE_NAME;

    #[test]
    fn core_identifies_itself() {
        assert_eq!(CORE_NAME, "remich_core");
    }
}
