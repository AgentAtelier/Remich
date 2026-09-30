//! The engine-free core of Remich.
//!
//! The firewall (docs/PLAN.md §1.2): everything in this crate is plain Rust.
//! It has no engine dependency and no engine types. Anything that needs engine
//! types belongs one layer above, in the thin binding crate, which is the only
//! place they are allowed to appear.
//!
//! Since Phase 1, Step 4 this crate also has an engine-free dependency: the
//! Step 3 donor import `anvil_sim`. That is the point of the layer — this is
//! the Remich-owned **adapter** between plain bridge data and the donor
//! scorer (docs/PLAN.md §4, step 4). It calls the donor's own functions and
//! never re-implements their formulas.
//!
//! * [`scorer`] — resolve donor action ids, call the donor utility scorer,
//!   pick the highest score the way the donor picks it.
//! * [`decay`] — apply the donor's need-decay semantics to plain need data as
//!   ticks advance.

/// The name this crate answers to across the boundary.
pub const CORE_NAME: &str = "remich_core";

/// Plain-data need decay as ticks advance, with the donor's decay semantics.
pub mod decay;
/// Plain-data scoring: the adapter over the donor's utility scorer.
pub mod scorer;

#[cfg(test)]
mod tests {
    use super::CORE_NAME;

    #[test]
    fn core_identifies_itself() {
        assert_eq!(CORE_NAME, "remich_core");
    }
}
