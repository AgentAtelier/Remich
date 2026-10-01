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
//! * [`clock`] — the one world clock: integer ticks, a fixed integer tick
//!   length, pause and speed (Phase 2, Step 1).
//! * [`weather`] — the one weather snapshot: plain data, one writer, readers
//!   everywhere, plus the small stand-in driver (Phase 2, Step 2).
//! * [`save`] — the game's save: a narrow versioned document holding the
//!   tool identity as a plain string, the clock, the weather and the
//!   stand-in inhabitant, plus identity-change adaptation with an explicit
//!   drop report (Phase 2, Step 3).
//! * [`soul`] — soul primitives across the bridge: seed creation, reading the
//!   substrate and the four axes, and the donor's own propagation returning
//!   a propagated influence (Phase 3, Step 2).

/// The name this crate answers to across the boundary.
pub const CORE_NAME: &str = "remich_core";

/// Plain-data need decay as ticks advance, with the donor's decay semantics.
pub mod decay;
/// The one world clock: integer ticks, fixed tick length, pause and speed.
pub mod clock;
/// Plain-data scoring: the adapter over the donor's utility scorer.
pub mod scorer;
/// The one weather snapshot: one writer, plain-data reads, stand-in driver.
pub mod weather;
/// The game's save: versioned document, adaptation, explicit drop reports
/// (Phase 2, Step 3).
pub mod save;
/// Soul primitives: donor seed creation, reads, and the donor's propagated
/// influence (Phase 3, Step 2). Adapter only — no formula of our own.
pub mod soul;

#[cfg(test)]
mod tests {
    use super::CORE_NAME;

    #[test]
    fn core_identifies_itself() {
        assert_eq!(CORE_NAME, "remich_core");
    }
}
