//! # anvil_sim — the Step 3 subset taken into Remich
//!
//! Engine-free plain-Rust subset of anvil's `anvil_sim` crate: the pieces that
//! choose an action — needs, the action catalogue, utility scoring, the
//! time-of-day curves — plus the narrow dependencies those pieces require
//! (`age`, `soul`, `settlement::skill`, `skill::{affordance, domain}`) and
//! `anvil_core`.
//!
//! The firewall holds (docs/PLAN.md §1): nothing in this crate depends on an
//! engine, an engine binding, or engine types. The binding crate is the only
//! place such names may appear.
//!
//! Provenance: every donor file in this crate comes from
//! `buggy-vault@24181142 repos/anvil/source/<path>` (vault commit
//! `24181142c693be37f90a6a667a6dc493425cd832`, which preserves original anvil
//! `main` `97c8fdbd7ff85779f33456fd7c444657f8d90b36`). The complete
//! per-file record — including this crate root — is
//! `docs/anvil-import-phase1-step3.md`.
//!
//! **This crate root is new, Remich-authored wiring** (the donor
//! `crates/anvil_sim/src/lib.rs` is *not* copied: it declares the simulation
//! systems — catastrophe, physics, joy, NPC — that Step 3 does not take).
//! The one donor item carried into this file is `DeterministicRng`, taken
//! verbatim because `soul.rs` calls `crate::DeterministicRng` in non-test
//! code, together with its two donor tests.

use serde::{Deserialize, Serialize};

/// NPC action catalogue: `TimeBlock`, `CopingType`, `ResourcePool`,
/// `ResourceEffect`, `Action`, and the JSON-backed action catalogue.
pub mod actions;
/// Aging categories (`AgeCategory`) and the `Age` type.
pub mod age;
/// The seven needs that drive NPC behaviour.
pub mod needs;
/// Settlement-side types; only `skill` (the `Skill` enum) is taken.
pub mod settlement;
/// Skill-side types; only `affordance` and `domain` are taken.
pub mod skill;
/// The layered soul: `Substrate`, `EmotionalState`, `LayeredSoul`.
pub mod soul;
/// Time-of-day curves (sigmoid learning modifiers, time-block mapping).
pub mod time;
/// Utility scoring for NPC action selection.
pub mod utility;

/// Deterministic random number generator for simulation.
/// 
/// Uses a simple deterministic hash function (xorshift64*) to produce
/// reproducible pseudo-random values from a seed.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct DeterministicRng {
    /// Internal state of the RNG.
    state: u64,
}

impl Default for DeterministicRng {
    fn default() -> Self {
        // xorshift64* requires a non-zero seed. Use a fixed non-zero constant.
        // 0 is an absorbing state for xorshift64* (0 ^ (0>>12) = 0, etc.)
        Self::new(0x4d32_19af_dead_beef)
    }
}

impl DeterministicRng {
    /// Creates a new deterministic RNG with the given seed.
    pub fn new(seed: u64) -> Self {
        Self { state: seed }
    }

    /// Generates a deterministic u64 value and advances the state.
    /// This uses a simple xorshift64* algorithm for deterministic pseudo-randomness.
    pub fn next_u64(&mut self) -> u64 {
        let mut x = self.state;
        x ^= x >> 12;
        x ^= x << 25;
        x ^= x >> 27;
        self.state = x;
        x.wrapping_mul(2685821657736338717u64)
    }

    /// Generates a deterministic f32 in range [0.0, 1.0).
    pub fn next_f32(&mut self) -> f32 {
        let bits = self.next_u64();
        // Use the upper 24 bits for the mantissa (gives good distribution in [0, 1))
        (bits >> 40) as f32 / 16_777_216.0
    }

    /// Generates a deterministic f32 in a custom range.
    pub fn next_f32_range(&mut self, min: f32, max: f32) -> f32 {
        min + (max - min) * self.next_f32()
    }

    /// Resets the RNG state to the given seed.
    pub fn reset(&mut self, seed: u64) {
        self.state = seed;
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_deterministic_rng_reproducibility() {
        let mut rng1 = DeterministicRng::new(12345);
        let mut rng2 = DeterministicRng::new(12345);

        assert_eq!(rng1.next_u64(), rng2.next_u64());
        assert_eq!(rng1.next_f32(), rng2.next_f32());

        let val1 = rng1.next_f32_range(10.0, 20.0);
        let val2 = rng2.next_f32_range(10.0, 20.0);
        assert!((val1 - val2).abs() < 0.001);
    }

    #[test]
    fn test_deterministic_rng_different_seeds() {
        let mut rng1 = DeterministicRng::new(12345);
        let mut rng2 = DeterministicRng::new(54321);

        assert_ne!(rng1.next_u64(), rng2.next_u64());
    }
}
