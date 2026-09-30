//! Need decay over advancing time (Phase 1, Step 4).
//!
//! The smallest adapter that reproduces the donor's need-decay semantics on
//! plain data — not the donor `NpcSystem`, which is not taken:
//!
//! * Donor reference for this behaviour only:
//!   `buggy-vault@24181142 repos/anvil/source/crates/anvil_sim/src/system/npc/kimi_npc_mod.rs`
//!   (`decay_needs`, `all_needs`, `need_index`).
//! * The donor applies exactly one decay step per tick whose number is
//!   divisible by 10, and skips every other tick.
//! * One step subtracts [`Need::decay_rate`]()` for that need and clamps the
//!   result to a minimum of `0.0`.
//! * The donor's Safety decay rate is `0.0`, so Safety never moves here either.
//!
//! [`advance_needs`] therefore counts the multiples of 10 crossed between two
//! ticks — the ticks *after* `from_tick` up to and including `to_tick`, since
//! `from_tick` already describes state that has been reached — and applies that
//! many donor steps, one at a time, in the donor's own need order.

use crate::scorer::{validate_needs, NEED_COUNT, NEED_ORDER};

/// The error type of this module: the scorer's, since both are the same plain
/// request-level failures.
pub use crate::scorer::ScorerError;

/// The donor's decay cadence: a step is applied on ticks divisible by this.
pub const NEED_DECAY_INTERVAL: u64 = 10;

/// The result of advancing a plain need array across ticks.
#[derive(Debug, Clone, PartialEq)]
pub struct AdvancedNeeds {
    /// The decayed need values, in [`NEED_ORDER`].
    pub needs: [f32; NEED_COUNT],
    /// How many donor decay steps were applied.
    pub decay_steps: u64,
    /// The tick the advance started at.
    pub from_tick: u64,
    /// The tick the advance ended at.
    pub to_tick: u64,
}

/// How many donor decay steps a tick range crosses.
///
/// Exactly one step per multiple of 10 in `(from_tick, to_tick]`.
pub fn decay_steps_between(from_tick: u64, to_tick: u64) -> Result<u64, ScorerError> {
    if to_tick < from_tick {
        return Err(ScorerError::TickOrder {
            from_tick,
            to_tick,
        });
    }
    Ok(to_tick / NEED_DECAY_INTERVAL - from_tick / NEED_DECAY_INTERVAL)
}

/// Applies the donor's decay semantics to a plain need array.
///
/// The input must be seven finite values in `[0.0, 1.0]`; anything else is a
/// clear error rather than a silently decayed number.
pub fn advance_needs(
    needs: &[f32; NEED_COUNT],
    from_tick: u64,
    to_tick: u64,
) -> Result<AdvancedNeeds, ScorerError> {
    validate_needs(needs)?;
    let decay_steps = decay_steps_between(from_tick, to_tick)?;

    let mut decayed = *needs;
    for (index, need) in NEED_ORDER.iter().enumerate() {
        let rate = need.decay_rate();
        // Donor Safety: rate 0.0, so the value is left exactly as it was.
        if rate == 0.0 {
            continue;
        }
        let mut value = decayed[index];
        for _ in 0..decay_steps {
            value = (value - rate).max(0.0);
            // Stays at the clamp for every later step, so stop early rather
            // than grinding through an arbitrarily long tick range.
            if value == 0.0 {
                break;
            }
        }
        decayed[index] = value;
    }

    Ok(AdvancedNeeds {
        needs: decayed,
        decay_steps,
        from_tick,
        to_tick,
    })
}

#[cfg(test)]
mod tests {
    use super::*;
    use anvil_sim::needs::Need;

    /// The donor's one-line step, spelled out for comparison.
    fn donor_step(value: f32, need: Need) -> f32 {
        (value - need.decay_rate()).max(0.0)
    }

    fn donor_steps(value: f32, need: Need, steps: u64) -> f32 {
        let mut out = value;
        for _ in 0..steps {
            out = donor_step(out, need);
        }
        out
    }

    const FIXTURE: [f32; NEED_COUNT] = [0.40, 0.35, 0.60, 0.50, 0.45, 0.42, 0.55];

    #[test]
    fn step_counts_are_multiples_of_ten_crossed() {
        assert_eq!(decay_steps_between(0, 0).unwrap(), 0);
        assert_eq!(decay_steps_between(5, 9).unwrap(), 0);
        assert_eq!(decay_steps_between(5, 10).unwrap(), 1);
        assert_eq!(decay_steps_between(10, 10).unwrap(), 0);
        assert_eq!(decay_steps_between(10, 14).unwrap(), 0);
        assert_eq!(decay_steps_between(10, 20).unwrap(), 1);
        assert_eq!(decay_steps_between(5, 35).unwrap(), 3);
        assert_eq!(decay_steps_between(0, 100).unwrap(), 10);
    }

    #[test]
    fn advancing_across_no_boundary_decays_nothing() {
        let outcome = advance_needs(&FIXTURE, 5, 9).expect("valid advance");
        assert_eq!(outcome.decay_steps, 0);
        assert_eq!(outcome.needs, FIXTURE, "not one value moved");
    }

    #[test]
    fn crossing_one_boundary_applies_exactly_one_donor_step() {
        let outcome = advance_needs(&FIXTURE, 5, 10).expect("valid advance");
        assert_eq!(outcome.decay_steps, 1);
        for (index, need) in NEED_ORDER.iter().enumerate() {
            assert_eq!(
                outcome.needs[index],
                donor_step(FIXTURE[index], *need),
                "need {need} did not receive exactly one donor step"
            );
        }
    }

    #[test]
    fn crossing_many_boundaries_applies_that_many_steps() {
        let outcome = advance_needs(&FIXTURE, 5, 35).expect("valid advance");
        assert_eq!(outcome.decay_steps, 3);
        for (index, need) in NEED_ORDER.iter().enumerate() {
            assert_eq!(
                outcome.needs[index],
                donor_steps(FIXTURE[index], *need, 3),
                "need {need} did not receive three donor steps"
            );
        }
    }

    #[test]
    fn safety_never_decays() {
        let safety_index = NEED_ORDER.iter().position(|n| *n == Need::Safety).unwrap();
        assert_eq!(Need::Safety.decay_rate(), 0.0);

        let outcome = advance_needs(&FIXTURE, 0, 10_000).expect("valid advance");
        assert_eq!(outcome.decay_steps, 1_000);
        assert_eq!(outcome.needs[safety_index], FIXTURE[safety_index]);
    }

    #[test]
    fn values_are_clamped_at_zero_and_never_negative() {
        let mut nearly_gone = [0.00004; NEED_COUNT];
        // Long enough for every non-zero donor rate to hit the clamp.
        let outcome = advance_needs(&nearly_gone, 0, 10_000).expect("valid advance");
        assert_eq!(outcome.decay_steps, 1_000);
        for (index, value) in outcome.needs.iter().enumerate() {
            assert!(*value >= 0.0, "need {index} went negative: {value}");
            if NEED_ORDER[index] != Need::Safety {
                assert_eq!(*value, 0.0, "need {index} should have bottomed out");
            }
        }

        // Starting exactly at zero stays exactly zero.
        nearly_gone = [0.0; NEED_COUNT];
        let outcome = advance_needs(&nearly_gone, 0, 100).expect("valid advance");
        assert_eq!(outcome.needs, [0.0; NEED_COUNT]);

        // A half-satisfied need decays to the exact difference after 1 step.
        let outcome = advance_needs(&[0.5; NEED_COUNT], 9, 10).expect("valid advance");
        for (index, need) in NEED_ORDER.iter().enumerate() {
            if *need == Need::Safety {
                assert_eq!(outcome.needs[index], 0.5);
            } else {
                assert_eq!(
                    outcome.needs[index],
                    (0.5 - need.decay_rate()).max(0.0)
                );
            }
        }
    }

    #[test]
    fn a_backwards_advance_is_an_error() {
        assert_eq!(
            decay_steps_between(20, 10),
            Err(ScorerError::TickOrder {
                from_tick: 20,
                to_tick: 10
            })
        );
        assert!(advance_needs(&FIXTURE, 20, 10).is_err());
    }

    #[test]
    fn malformed_need_values_are_rejected_before_any_decay() {
        let mut bad = FIXTURE;
        bad[2] = -0.1;
        assert_eq!(
            advance_needs(&bad, 0, 10),
            Err(ScorerError::NeedOutOfRange {
                index: 2,
                value: -0.1
            })
        );
    }

    #[test]
    fn advancing_with_no_distance_applies_no_steps() {
        let outcome = advance_needs(&FIXTURE, 42, 42).expect("valid advance");
        assert_eq!(outcome.decay_steps, 0);
        assert_eq!(outcome.needs, FIXTURE);
    }
}
