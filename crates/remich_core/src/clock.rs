//! The world clock — Phase 2, Step 1 "one clock" (docs/PLAN.md §4a).
//!
//! One authoritative clock for the whole simulation: an integer tick counter,
//! a fixed tick length held as an exact integer duration, pause/running state,
//! an integer speed multiplier, and deterministic advancement. Every core
//! reads this one clock; nothing keeps a second copy of the tick.
//!
//! ## Why integer ticks (the scouts' warning)
//!
//! The donor generation accumulated `f32` seconds and derived a tick by
//! flooring total seconds — so subsecond steps could share a tick, and a
//! long run drifted with the accumulator. This module refuses that shape
//! outright: the authoritative state below is integer-only (`u64`/`u32`/
//! `bool`), advancement is an integer add, and the *only* floating-point
//! expression in this file is [`WorldClock::cycle_position`], an edge
//! conversion used to present a derived value (a position inside a caller
//! supplied cycle). A float never decides which integer tick exists.
//!
//! ## The model
//!
//! * `tick` — the authoritative integer position. It advances only in
//!   [`WorldClock::pulse`], by integer addition.
//! * `tick_length_ns` — the fixed tick duration in whole nanoseconds,
//!   supplied once at construction and never mutated afterwards. This
//!   clock does not convert it to seconds and does not accumulate them.
//! * `paused` — a paused clock emits nothing: [`WorldClock::pulse`] returns
//!   an empty batch and the tick does not move. Resuming continues at
//!   exactly the next integer tick.
//! * `speed` — an integer multiplier ≥ 1. Speed means *more consecutive
//!   ticks per driver pulse*, never skipped simulation: one pulse at
//!   speed 4 makes the four ticks `t, t+1, t+2, t+3` available, all of
//!   which consumers are expected to process in order. The tick sequence
//!   of a run therefore does not depend on its speed — only the number of
//!   pulses does.
//!
//! ## Cycles are the caller's business
//!
//! This clock does not decree the length of a game day. A caller that needs
//! a cyclic interpretation (time of day) supplies the cycle length explicitly
//! and gets a derived float back; the integer tick remains the authority.
//! Remich's test project uses `240` as *its test fixture's* cycle length —
//! a test-project configuration, not a decision about any game's simulation
//! rate.
//!
//! ## Save state (Phase 2, Step 3)
//!
//! The whole clock is four integer/bool fields, so the game's save holds all
//! of them: [`WorldClock::capture_state`] reads them and
//! [`WorldClock::restore_state`] replaces them wholesale from a validated
//! save. Restore is the one sanctioned full-state replacement of a live
//! clock (construction fixes the tick length for ordinary life; a loaded save
//! is not ordinary life), and it validates exactly what construction
//! validates — a zero tick length or a zero speed is refused. The clock
//! still exists as one object: restore mutates the existing clock, it never
//! creates a second one.

use std::fmt;

use serde::{Deserialize, Serialize};

/// The error type of this module.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ClockError {
    /// A tick length of zero nanoseconds was requested: there is no such tick.
    ZeroTickLength,
    /// A speed of zero was requested: that is what pause is for.
    ZeroSpeed,
    /// A cycle length of zero was requested: division has no meaning here.
    ZeroCycleLength,
}

impl fmt::Display for ClockError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            ClockError::ZeroTickLength => {
                write!(f, "tick length must be a positive number of nanoseconds")
            }
            ClockError::ZeroSpeed => {
                write!(f, "speed must be at least 1 (use pause to stop the clock)")
            }
            ClockError::ZeroCycleLength => write!(f, "cycle length must be at least 1"),
        }
    }
}

impl std::error::Error for ClockError {}

/// One driver pulse's worth of simulation ticks: the *consecutive* ticks
/// `[first, first + count)`, in order, none skipped, none repeated.
///
/// This is the unit consumers work with. A pulse at speed 1 yields one tick;
/// a pulse at speed 4 yields four; a paused pulse yields none. Consumers are
/// expected to iterate every tick in the batch — speed 4 must never let a
/// consumer see `8` jump to `12` while `9, 10, 11, 12` disappear.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Default)]
pub struct TickBatch {
    /// The first tick made available by the pulse.
    first: u64,
    /// How many consecutive ticks the pulse made available.
    count: u32,
}

impl TickBatch {
    /// A batch starting at `first`, covering `count` consecutive ticks.
    pub const fn new(first: u64, count: u32) -> Self {
        Self { first, count }
    }

    /// An empty batch: what a paused clock emits.
    pub const fn empty() -> Self {
        Self { first: 0, count: 0 }
    }

    /// The first tick of the batch.
    pub const fn first(&self) -> u64 {
        self.first
    }

    /// How many consecutive ticks the batch carries.
    pub const fn count(&self) -> u32 {
        self.count
    }

    /// `true` when the pulse made no tick available (paused).
    pub const fn is_empty(&self) -> bool {
        self.count == 0
    }

    /// The ticks of this batch, in order.
    pub fn ticks(&self) -> impl Iterator<Item = u64> + '_ {
        self.first..self.first + u64::from(self.count)
    }

    /// The last tick of the batch, if any.
    pub fn last(&self) -> Option<u64> {
        if self.count == 0 {
            None
        } else {
            Some(self.first + u64::from(self.count) - 1)
        }
    }
}

/// The one world clock: integer tick, exact integer tick length, pause, speed.
///
/// Construction takes the fixed tick duration in whole nanoseconds and
/// refuses zero; the value is then immutable. Advancement happens only in
/// [`WorldClock::pulse`], which is a pure integer operation.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct WorldClock {
    /// The authoritative position: the next tick a pulse will make available.
    tick: u64,
    /// The fixed tick length in whole nanoseconds. Immutable after construction.
    tick_length_ns: u64,
    /// The integer speed multiplier (≥ 1): consecutive ticks per pulse.
    speed: u32,
    /// Paused clocks emit nothing.
    paused: bool,
}

/// The clock's complete authoritative state, as the game's save holds it
/// (Phase 2, Step 3).
///
/// Four fields, all integer or bool — the save never stores wall-clock time,
/// accumulated seconds or an engine delta, because this clock has none to
/// store. `tick` is the same *next tick* position [`WorldClock::pulse`]
/// advances from; a save taken when the clock points at tick `N` continues
/// with tick `N`.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub struct ClockState {
    /// The authoritative position: the next tick a pulse will make available.
    pub tick: u64,
    /// The fixed tick length in whole nanoseconds.
    pub tick_length_ns: u64,
    /// The integer speed multiplier (≥ 1).
    pub speed: u32,
    /// Whether the clock is paused.
    pub paused: bool,
}

impl WorldClock {
    /// A clock at tick 0 with the given fixed tick length.
    pub fn new(tick_length_ns: u64) -> Result<Self, ClockError> {
        Self::starting_at(tick_length_ns, 0)
    }

    /// A clock starting at an explicit integer tick (fixture initialization).
    pub fn starting_at(tick_length_ns: u64, start_tick: u64) -> Result<Self, ClockError> {
        if tick_length_ns == 0 {
            return Err(ClockError::ZeroTickLength);
        }
        Ok(Self {
            tick: start_tick,
            tick_length_ns,
            speed: 1,
            paused: false,
        })
    }

    /// The authoritative integer tick: the next tick a pulse makes available.
    pub const fn tick(&self) -> u64 {
        self.tick
    }

    /// The fixed tick length, in whole nanoseconds. Never accumulated,
    /// never converted, never mutated — not by a pulse, not by a speed change.
    pub const fn tick_length_ns(&self) -> u64 {
        self.tick_length_ns
    }

    /// The integer speed multiplier.
    pub const fn speed(&self) -> u32 {
        self.speed
    }

    /// Whether the clock is paused.
    pub const fn is_paused(&self) -> bool {
        self.paused
    }

    /// Sets the integer speed multiplier. `0` is refused: pause, not zero, is
    /// how a clock stops.
    pub fn set_speed(&mut self, speed: u32) -> Result<(), ClockError> {
        if speed == 0 {
            return Err(ClockError::ZeroSpeed);
        }
        self.speed = speed;
        Ok(())
    }

    /// Pauses the clock: subsequent pulses emit nothing.
    pub fn pause(&mut self) {
        self.paused = true;
    }

    /// Resumes the clock. It continues at exactly the next integer tick; the
    /// speed is untouched (change it separately, explicitly, with
    /// [`WorldClock::set_speed`]).
    pub fn resume(&mut self) {
        self.paused = false;
    }

    /// Re-positions the clock at an explicit integer tick (fixture setup /
    /// reset). Does not touch pause state, speed or the tick length.
    pub fn reset(&mut self, tick: u64) {
        self.tick = tick;
    }

    /// The clock's whole state, read for the game's save (Phase 2, Step 3).
    /// A plain copy of the four authoritative fields — no wall-clock time is
    /// read, because none exists here to read.
    pub const fn capture_state(&self) -> ClockState {
        ClockState {
            tick: self.tick,
            tick_length_ns: self.tick_length_ns,
            speed: self.speed,
            paused: self.paused,
        }
    }

    /// Replaces this clock's whole state from a validated save (Phase 2,
    /// Step 3). The **same** clock object continues — restore mutates this
    /// clock in place and never produces a second one — and the saved state
    /// must be as sound as construction requires: a zero tick length or a
    /// zero speed is refused, and nothing else is second-guessed (a changed
    /// tool identity is adaptation's business, not the clock's).
    pub fn restore_state(&mut self, state: ClockState) -> Result<(), ClockError> {
        if state.tick_length_ns == 0 {
            return Err(ClockError::ZeroTickLength);
        }
        if state.speed == 0 {
            return Err(ClockError::ZeroSpeed);
        }
        self.tick = state.tick;
        self.tick_length_ns = state.tick_length_ns;
        self.speed = state.speed;
        self.paused = state.paused;
        Ok(())
    }

    /// One driver pulse: makes `speed` consecutive ticks available, in order,
    /// and advances the authoritative tick by exactly that integer amount.
    ///
    /// * paused → an empty batch, the tick does not move;
    /// * speed 1 → `[t, t+1)`;
    /// * speed 4 → `[t, t+4)` — four *consecutive* ticks for consumers to
    ///   process in order, never a jump that hides the intermediate ones.
    pub fn pulse(&mut self) -> TickBatch {
        if self.paused {
            return TickBatch::new(self.tick, 0);
        }
        let batch = TickBatch::new(self.tick, self.speed);
        self.tick = self
            .tick
            .checked_add(u64::from(self.speed))
            .expect("WorldClock tick overflowed u64");
        batch
    }

    /// Presents an integer tick as a position inside a caller-supplied cycle,
    /// e.g. normalized time of day for a cycle of `cycle_length` ticks.
    ///
    /// This is the one floating-point expression in this module, and it is an
    /// edge *presentation*: it derives a display value from an integer tick
    /// that already exists. It never decides which tick that is, and the
    /// caller must state the cycle length explicitly — the clock itself does
    /// not decree how long a day is.
    pub fn cycle_position(tick: u64, cycle_length: u64) -> Result<f64, ClockError> {
        if cycle_length == 0 {
            return Err(ClockError::ZeroCycleLength);
        }
        Ok((tick % cycle_length) as f64 / cycle_length as f64)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    /// 100 ms in nanoseconds — the explicit fixed tick length of Remich's
    /// test project fixture (declared there too, by the test project's
    /// shared clock script). It is test-project configuration, not a
    /// game-design decision.
    const TEST_TICK_LENGTH_NS: u64 = 100_000_000;

    fn clock_at_speed(speed: u32) -> WorldClock {
        let mut clock = WorldClock::new(TEST_TICK_LENGTH_NS).expect("valid tick length");
        clock.set_speed(speed).expect("valid speed");
        clock
    }

    /// Collects every tick `count` pulses make available, in order.
    fn emitted(clock: &mut WorldClock, pulses: usize) -> Vec<u64> {
        let mut ticks = Vec::new();
        for _ in 0..pulses {
            for tick in clock.pulse().ticks() {
                ticks.push(tick);
            }
        }
        ticks
    }

    // ------------------------------------------------- integer advancement

    #[test]
    fn starts_from_the_configured_tick() {
        let clock = WorldClock::new(TEST_TICK_LENGTH_NS).expect("valid");
        assert_eq!(clock.tick(), 0);
        assert_eq!(clock.speed(), 1);
        assert!(!clock.is_paused());

        let clock = WorldClock::starting_at(TEST_TICK_LENGTH_NS, 1_234).expect("valid");
        assert_eq!(clock.tick(), 1_234);
        let mut clock = clock;
        assert_eq!(clock.pulse().ticks().collect::<Vec<_>>(), vec![1_234]);
        assert_eq!(clock.tick(), 1_235);
    }

    #[test]
    fn speed_one_pulse_emits_one_consecutive_tick() {
        let mut clock = clock_at_speed(1);
        let mut previous: Option<u64> = None;
        for expected in 0..50 {
            let batch = clock.pulse();
            assert_eq!(batch.count(), 1);
            let tick = batch.first();
            assert_eq!(tick, expected);
            if let Some(previous) = previous {
                assert_eq!(tick, previous + 1, "speed 1 skipped or repeated a tick");
            }
            previous = Some(tick);
            assert_eq!(clock.tick(), tick + 1);
        }
    }

    #[test]
    fn speed_four_pulse_emits_four_consecutive_ticks() {
        let mut clock = clock_at_speed(4);
        for first in (0..40).step_by(4) {
            let batch = clock.pulse();
            assert_eq!(batch.count(), 4);
            assert_eq!(
                batch.ticks().collect::<Vec<_>>(),
                vec![first, first + 1, first + 2, first + 3],
                "a speed-4 pulse must carry four consecutive ticks in order"
            );
            assert_eq!(clock.tick(), first + 4);
        }
    }

    /// The named sabotage shape: a driver that only reports "now 12" after a
    /// pulse starting from 8 would hide 9, 10, 11 and 12 from consumers. The
    /// batch API makes that impossible: every intermediate tick is in there.
    #[test]
    fn a_speed_four_pulse_cannot_turn_8_into_12() {
        let mut clock = clock_at_speed(4);
        clock.reset(8);
        let first = clock.pulse();
        assert_eq!(first.ticks().collect::<Vec<_>>(), vec![8, 9, 10, 11]);
        let second = clock.pulse();
        assert_eq!(second.ticks().collect::<Vec<_>>(), vec![12, 13, 14, 15]);

        // Consumers that process every tick of both batches see 9, 10, 11 and
        // 12 — none of them can be missed.
        let seen: Vec<u64> = first.ticks().chain(second.ticks()).collect();
        for required in [9u64, 10, 11, 12] {
            assert!(seen.contains(&required), "tick {required} disappeared");
        }
    }

    #[test]
    fn no_tick_is_skipped_or_repeated_across_a_long_run() {
        for speed in [1u32, 4] {
            let mut clock = clock_at_speed(speed);
            let pulses = 1_000;
            let ticks = emitted(&mut clock, pulses);
            let expected: Vec<u64> = (0..(u64::from(speed) * pulses as u64)).collect();
            assert_eq!(ticks, expected, "speed {speed}: ticks skipped or repeated");
        }
    }

    #[test]
    fn long_run_reaches_the_exact_expected_tick() {
        let mut clock = clock_at_speed(4);
        emitted(&mut clock, 100_000);
        assert_eq!(
            clock.tick(),
            400_000,
            "the long run must land on the exact integer tick"
        );

        let mut clock = clock_at_speed(1);
        emitted(&mut clock, 240);
        assert_eq!(clock.tick(), 240);
    }

    // -------------------------------------------------------- pause / resume

    #[test]
    fn paused_pulses_emit_nothing_and_leave_the_tick_unchanged() {
        let mut clock = clock_at_speed(1);
        emitted(&mut clock, 3);
        let held = clock.tick();
        assert_eq!(held, 3);

        clock.pause();
        assert!(clock.is_paused());
        for _ in 0..10 {
            let batch = clock.pulse();
            assert!(batch.is_empty(), "a paused pulse must emit no tick");
            assert_eq!(clock.tick(), held, "the tick moved while paused");
        }
    }

    #[test]
    fn resume_continues_from_exactly_the_next_tick() {
        let mut clock = clock_at_speed(4);
        emitted(&mut clock, 2);
        assert_eq!(clock.tick(), 8);

        clock.pause();
        emitted(&mut clock, 5);
        assert_eq!(clock.tick(), 8);

        clock.resume();
        let batch = clock.pulse();
        assert_eq!(batch.ticks().collect::<Vec<_>>(), vec![8, 9, 10, 11]);
        assert_eq!(
            clock.tick(),
            12,
            "resume must continue at the next integer tick"
        );
    }

    #[test]
    fn speed_is_retained_across_pause_and_changed_only_on_request() {
        let mut clock = clock_at_speed(4);
        clock.pause();
        assert_eq!(clock.speed(), 4, "pausing must not change the speed");
        clock.resume();
        assert_eq!(clock.speed(), 4, "resuming must not change the speed");
        assert_eq!(clock.pulse().count(), 4, "the retained speed still applies");

        clock.set_speed(1).expect("valid speed");
        clock.pause();
        assert_eq!(clock.speed(), 1, "an explicit change is kept while paused");
        clock.resume();
        assert_eq!(clock.pulse().count(), 1);
    }

    #[test]
    fn zero_speed_is_refused_rather_than_silently_pausing() {
        let mut clock = clock_at_speed(1);
        assert_eq!(clock.set_speed(0), Err(ClockError::ZeroSpeed));
        assert_eq!(clock.speed(), 1);
    }

    // ----------------------------------------------------- the tick duration

    #[test]
    fn zero_tick_length_is_refused() {
        assert_eq!(WorldClock::new(0), Err(ClockError::ZeroTickLength));
        assert_eq!(
            WorldClock::starting_at(0, 42),
            Err(ClockError::ZeroTickLength)
        );
    }

    #[test]
    fn tick_length_is_exact_integer_state_that_does_not_drift() {
        let mut clock = clock_at_speed(4);
        for _ in 0..10_000 {
            clock.pulse();
            assert_eq!(
                clock.tick_length_ns(),
                TEST_TICK_LENGTH_NS,
                "the fixed tick length drifted"
            );
        }
        clock.pause();
        assert_eq!(clock.tick_length_ns(), TEST_TICK_LENGTH_NS);
        clock.resume();
        clock.set_speed(1).expect("valid speed");
        assert_eq!(
            clock.tick_length_ns(),
            TEST_TICK_LENGTH_NS,
            "changing the speed must not mutate the tick length"
        );
        clock.reset(999);
        assert_eq!(clock.tick_length_ns(), TEST_TICK_LENGTH_NS);
    }

    // ------------------------------------------------------ speed equivalence

    /// The step's acceptance in miniature: for a fixed target number of
    /// simulation ticks, speed 1 and speed 4 produce exactly the same ordered
    /// tick sequence; only the number of driver pulses differs.
    #[test]
    fn speed_one_and_speed_four_emit_the_same_ordered_ticks() {
        const TARGET_TICKS: u64 = 240;

        let mut slow = clock_at_speed(1);
        let mut pulses_slow = 0usize;
        let mut slow_ticks = Vec::new();
        while slow.tick() < TARGET_TICKS {
            for tick in slow.pulse().ticks() {
                slow_ticks.push(tick);
            }
            pulses_slow += 1;
        }

        let mut fast = clock_at_speed(4);
        let mut pulses_fast = 0usize;
        let mut fast_ticks = Vec::new();
        while fast.tick() < TARGET_TICKS {
            for tick in fast.pulse().ticks() {
                fast_ticks.push(tick);
            }
            pulses_fast += 1;
        }

        assert_eq!(
            slow_ticks, fast_ticks,
            "speed changed the simulation tick sequence"
        );
        assert_eq!(slow_ticks.len(), TARGET_TICKS as usize);
        assert_eq!(slow.tick(), TARGET_TICKS);
        assert_eq!(fast.tick(), TARGET_TICKS);
        assert_eq!(pulses_slow, TARGET_TICKS as usize);
        assert_eq!(pulses_fast, (TARGET_TICKS / 4) as usize);
        assert_ne!(pulses_slow, pulses_fast, "only the pulse count may differ");
    }

    // ------------------------------------------------------ derived cycles

    #[test]
    fn cycle_position_matches_the_test_fixture_derivation() {
        // The test project's fixture: 240 ticks per test cycle, 24
        // checkpoint-like positions — time_of_day = checkpoint / 24.
        const CYCLE: u64 = 240;
        for checkpoint in 0..24u64 {
            let tick = checkpoint * 10;
            let position = WorldClock::cycle_position(tick, CYCLE).expect("valid cycle");
            let expected = checkpoint as f64 / 24.0;
            assert_eq!(
                position.to_bits(),
                expected.to_bits(),
                "tick {tick} must derive exactly checkpoint {checkpoint} / 24"
            );
        }
        // The cycle wraps: it is a property of (tick, cycle), never of wall time.
        let wrapped = WorldClock::cycle_position(241, CYCLE).expect("valid cycle");
        assert_eq!(wrapped.to_bits(), (1.0f64 / 240.0).to_bits());
        assert_eq!(WorldClock::cycle_position(0, CYCLE).expect("valid"), 0.0);
    }

    #[test]
    fn zero_cycle_length_is_refused() {
        assert_eq!(
            WorldClock::cycle_position(10, 0),
            Err(ClockError::ZeroCycleLength)
        );
    }

    // ------------------------------------------------ integer-only authority

    /// The type-level proof: every authoritative field is an integer or a
    /// bool, checked by the compiler's own type names rather than by grep.
    #[test]
    fn authoritative_fields_are_integer_types() {
        let clock = WorldClock::new(TEST_TICK_LENGTH_NS).expect("valid");
        assert_eq!(std::any::type_name_of_val(&clock.tick), "u64");
        assert_eq!(std::any::type_name_of_val(&clock.tick_length_ns), "u64");
        assert_eq!(std::any::type_name_of_val(&clock.speed), "u32");
        assert_eq!(std::any::type_name_of_val(&clock.paused), "bool");
    }

    /// The source-level backstop for the same property, and the guard that
    /// fails loudly if a future edit reintroduces accumulated float time: the
    /// only floating-point type in this module's *code* lives inside
    /// `cycle_position` — the documented presentation edge — and no
    /// seconds-accumulating idiom appears anywhere. Comment lines are skipped
    /// (the prose legitimately names the donor's old float-time bug), and the
    /// banned idioms are assembled at runtime so this list cannot trip itself.
    #[test]
    fn the_authoritative_clock_source_uses_no_float_time() {
        let source = include_str!("clock.rs");
        let code = source
            .lines()
            .filter(|line| !line.trim_start().starts_with("//"))
            .collect::<Vec<_>>()
            .join("\n");

        let edge = code
            .find("pub fn cycle_position")
            .expect("the presentation edge exists");
        let positions: Vec<usize> = code
            .match_indices("f64")
            .chain(code.match_indices("f32"))
            .map(|(i, _)| i)
            .collect();
        assert!(!positions.is_empty(), "cycle_position itself converts");
        for position in positions {
            assert!(
                position > edge,
                "a floating-point type appears outside cycle_position (offset {position})"
            );
        }

        for banned in [
            ["from_", "secs_f"].concat(),
            ["as_", "secs_f"].concat(),
            ["elapsed", "("].concat(),
            ["floor", "("].concat(),
            ["total", "_seconds"].concat(),
            ["_seconds", " +="].concat(),
        ] {
            assert!(
                !code.contains(&banned),
                "the clock source must not contain '{banned}'"
            );
        }
    }

    /// `TickBatch` iteration covers every tick exactly once, in order — the
    /// property consumers rely on when they process a speed-4 pulse.
    #[test]
    fn batch_iteration_covers_every_tick_exactly_once() {
        let batch = TickBatch::new(8, 4);
        let ticks: Vec<u64> = batch.ticks().collect();
        assert_eq!(ticks, vec![8, 9, 10, 11]);
        assert_eq!(batch.last(), Some(11));
        assert_eq!(TickBatch::empty().last(), None);
        assert!(TickBatch::empty().ticks().next().is_none());
    }

    /// Capturing reads the four authoritative fields and nothing else: the
    /// saved clock state is exactly tick, tick length, speed and pause —
    /// integer/bool state, no wall clock, no accumulated seconds.
    #[test]
    fn clock_state_captures_every_authoritative_field() {
        let mut clock = clock_at_speed(4);
        clock.reset(119);
        clock.pause();
        let state = clock.capture_state();
        assert_eq!(state.tick, 119);
        assert_eq!(state.tick_length_ns, TEST_TICK_LENGTH_NS);
        assert_eq!(state.speed, 4);
        assert!(state.paused);
        // The other direction: a fresh running clock at speed 1.
        let fresh = WorldClock::new(TEST_TICK_LENGTH_NS).expect("valid tick length");
        let state = fresh.capture_state();
        assert_eq!(
            state,
            ClockState {
                tick: 0,
                tick_length_ns: TEST_TICK_LENGTH_NS,
                speed: 1,
                paused: false,
            }
        );
    }

    /// Restore puts a captured state back **into the same clock**, and the
    /// clock continues from exactly the saved next tick: state at 119 paused
    /// at speed 4 resumes emitting 119, 120, ... and nothing else changes.
    #[test]
    fn restore_replaces_the_states_exactly_and_continues_from_the_saved_tick() {
        let mut donor = clock_at_speed(4);
        donor.reset(119);
        donor.pause();
        let state = donor.capture_state();

        let mut clock = WorldClock::new(TEST_TICK_LENGTH_NS).expect("valid tick length");
        clock.restore_state(state).expect("valid saved state");
        assert_eq!(clock.capture_state(), state);
        assert_eq!(clock.tick(), 119, "the saved next tick is restored");
        assert!(clock.is_paused(), "pause state is restored");
        clock.resume();
        assert_eq!(
            emitted(&mut clock, 1),
            vec![119, 120, 121, 122],
            "the restored clock pulses from the saved tick at the saved speed"
        );
    }

    /// Restore is a state replacement on the existing clock: after it, every
    /// capture of the clock equals the state that went in — round-trip
    /// capture -> restore -> capture is the identity.
    #[test]
    fn capture_restore_capture_is_the_identity() {
        let mut clock = WorldClock::starting_at(TEST_TICK_LENGTH_NS, 120)
            .expect("valid tick length");
        clock.set_speed(3).expect("valid speed");
        clock.pause();
        let state = clock.capture_state();
        clock.restore_state(state).expect("valid saved state");
        assert_eq!(clock.capture_state(), state);
        // And a save taken after ordinary running round-trips too.
        clock.resume();
        for _ in 0..5 {
            let _ = clock.pulse();
        }
        let state = clock.capture_state();
        clock.restore_state(state).expect("valid saved state");
        assert_eq!(clock.capture_state(), state);
        assert_eq!(clock.tick(), 135, "120 + 5 ticks at speed 3");
    }

    /// A saved state that construction would refuse is refused here too: a
    /// zero tick length or a zero speed never enters the live clock, and the
    /// clock's previous state survives the refusal untouched.
    #[test]
    fn restore_refuses_a_zero_tick_length_and_a_zero_speed() {
        let mut clock = WorldClock::new(TEST_TICK_LENGTH_NS).expect("valid tick length");
        clock.reset(42);
        let before = clock.capture_state();

        let zero_length = ClockState {
            tick_length_ns: 0,
            ..before
        };
        assert_eq!(
            clock.restore_state(zero_length),
            Err(ClockError::ZeroTickLength)
        );

        let zero_speed = ClockState {
            speed: 0,
            ..before
        };
        assert_eq!(clock.restore_state(zero_speed), Err(ClockError::ZeroSpeed));

        assert_eq!(
            clock.capture_state(),
            before,
            "a refused restore changes nothing"
        );
    }

    /// The saved clock state carries only the four integer/bool fields —
    /// read from this file's own source, so a float or an accumulated
    /// seconds field cannot quietly join the save.
    #[test]
    fn clock_state_declares_only_integer_authoritative_fields() {
        let source = include_str!("clock.rs");
        let start = source
            .find("pub struct ClockState")
            .expect("the save's clock state exists");
        let rest = &source[start..];
        let end = rest.find("\n}").expect("the struct body ends");
        let body = &rest[..end];
        for field in ["tick:", "tick_length_ns:", "speed:", "paused:"] {
            assert!(body.contains(field), "ClockState must declare '{field}'");
        }
        // "_seconds" (accumulated-seconds state), not "seconds": the tick
        // length legitimately ends in "nanoseconds".
        for banned in ["f32", "f64", "_seconds", "elapsed", "wall"] {
            assert!(
                !body.contains(banned),
                "ClockState must not carry '{banned}' state"
            );
        }
    }
}
