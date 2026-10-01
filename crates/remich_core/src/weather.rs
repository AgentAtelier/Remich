//! The weather snapshot — Phase 2, Step 2 "one weather snapshot"
//! (docs/PLAN.md §4a, step 2).
//!
//! One Rust-held snapshot of plain weather data, written by **exactly one**
//! driver and read by everything else. The channel below makes that ownership
//! structural rather than conventional: a writer must claim the channel before
//! it may publish, a second, distinct claim is refused with an error that
//! names the conflict, and readers only ever read.
//!
//! ## What this module is not
//!
//! * It is **not** Eisleck's weather model. What the weather *does* belongs to
//!   Eisleck (docs/PLAN.md §1.1); this is the game-side channel it will later
//!   drive, plus a deliberately small stand-in driver — see
//!   [`StandInWeather`] — that exists only to make the channel demonstrably
//!   live and is documented as replaceable fixture behaviour.
//! * It holds **no time authority of its own**. The only time input is an
//!   integer simulation tick handed in by the caller (the one shared world
//!   clock of Phase 2, Step 1); this module never advances a tick, never
//!   accumulates seconds and never reads a frame delta. The stand-in driver's
//!   state is `u64` seed and `u64` cycle length, nothing else.
//! * It knows nothing about rendering: no shader global, no engine type. The
//!   mapping from a snapshot to any renderer-facing value lives one layer up,
//!   in the binding.
//!
//! ## The snapshot (plain data)
//!
//! [`WeatherSnapshot`] carries, at minimum: wind direction X, wind direction
//! Z, wind strength, rain, temperature, light, and the integer simulation tick
//! for which the snapshot applies. Every numeric weather field must be finite;
//! wind strength must be non-negative. Those are the only numeric rules this
//! step invents, and they are **Remich test-fixture semantics**, not final
//! Eisleck units or policy (docs/remich-weather-phase2-step2.md).
//!
//! ## The one writer
//!
//! [`WeatherChannel`] starts with **no writer**. The first
//! [`WeatherChannel::claim_writer`] succeeds and owns the channel; every
//! publish must come from that owner; a distinct second writer is refused with
//! [`WeatherError::WriterConflict`], which names both writers. A refused
//! publish changes nothing: the last valid snapshot survives untouched.

use std::fmt;

use serde::{Deserialize, Serialize};

/// The one stand-in driver's writer identity (docs/PLAN.md §4a, step 2: the
/// driver now is a stand-in schedule, to be replaced by Eisleck).
pub const STAND_IN_DRIVER_ID: &str = "stand-in-weather-schedule";

// --- the stand-in schedule's fixture values ---------------------------------
// Remich test-fixture semantics (replaceable, not Eisleck policy):
//
//   * the fixture cycle is the test project's explicit 240-tick day, supplied
//     by the caller — this module never fixes a cycle length of its own;
//   * a tick whose phase is in the first half of the cycle is *morning*
//     (calm), a tick in the second half is *afternoon* (windy);
//   * wind strength is a fixture scalar in Grengewald's gentle 0..1 metre
//     displacement range, so the binding can adapt it at the edge without a
//     unit conversion;
//   * rain, temperature and light are present and observable, held at one
//     documented value per half-cycle. They are placeholders for Eisleck, not
//     a weather simulation.

/// Fixture wind strength of the calm morning half-cycle.
pub const STAND_IN_MORNING_STRENGTH: f64 = 0.0;
/// Fixture wind strength of the windy afternoon half-cycle.
pub const STAND_IN_AFTERNOON_STRENGTH: f64 = 0.7;
/// Fixture rain of the calm morning half-cycle.
pub const STAND_IN_MORNING_RAIN: f64 = 0.0;
/// Fixture rain of the windy afternoon half-cycle.
pub const STAND_IN_AFTERNOON_RAIN: f64 = 0.1;
/// Fixture temperature of the calm morning half-cycle.
pub const STAND_IN_MORNING_TEMPERATURE: f64 = 12.0;
/// Fixture temperature of the windy afternoon half-cycle.
pub const STAND_IN_AFTERNOON_TEMPERATURE: f64 = 19.0;
/// Fixture light of the calm morning half-cycle.
pub const STAND_IN_MORNING_LIGHT: f64 = 0.35;
/// Fixture light of the windy afternoon half-cycle.
pub const STAND_IN_AFTERNOON_LIGHT: f64 = 0.85;

/// The seed's participation: one of four fixed **unit** wind directions.
///
/// A very small stable mapping — `seed % 4` selects the direction — so the
/// seed demonstrably shapes the stand-in result instead of being accepted and
/// ignored, while the result stays exactly reproducible. No randomness, no
/// search, no mutable global state.
const SEED_DIRECTIONS: [(f64, f64); 4] = [(1.0, 0.0), (0.0, 1.0), (-1.0, 0.0), (0.0, -1.0)];

/// Why a weather request was refused.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum WeatherError {
    /// An empty writer identity may not claim the channel.
    EmptyWriterId,
    /// A second, distinct writer tried to claim or publish; the channel stays
    /// with `held_by`. This is the one-writer rule speaking.
    WriterConflict {
        /// The writer that owns the channel.
        held_by: String,
        /// The writer that was refused.
        attempted: String,
    },
    /// A publish arrived before any writer claimed the channel.
    PublishWithoutWriter,
    /// A numeric weather field was not finite.
    NonFinite {
        /// The offending field's name.
        field: &'static str,
    },
    /// Wind strength must be non-negative.
    NegativeWindStrength,
    /// A cycle length of zero was requested: division has no meaning here.
    ZeroCycleLength,
}

impl fmt::Display for WeatherError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            WeatherError::EmptyWriterId => write!(f, "a writer identity must not be empty"),
            WeatherError::WriterConflict { held_by, attempted } => write!(
                f,
                "the weather channel is owned by '{held_by}'; writer '{attempted}' was refused \
                 (one writer only, the first claim stands)"
            ),
            WeatherError::PublishWithoutWriter => {
                write!(f, "no writer owns the weather channel yet; claim it first")
            }
            WeatherError::NonFinite { field } => {
                write!(f, "weather field '{field}' must be a finite number")
            }
            WeatherError::NegativeWindStrength => {
                write!(f, "wind strength must be a non-negative number")
            }
            WeatherError::ZeroCycleLength => write!(f, "cycle length must be at least 1"),
        }
    }
}

impl std::error::Error for WeatherError {}

/// One authoritative weather snapshot: plain data, no methods that decide
/// anything.
///
/// `tick` is the integer simulation tick **for which** this snapshot applies
/// (the shared world clock's tick at publish time, handed in by the driver).
/// The snapshot never advances it; it is a label, not a clock.
///
/// The serde derives (Phase 2, Step 3) exist so the game's save can hold a
/// snapshot verbatim: they serialize the fields in declaration order and add
/// no state of their own — in particular no presentation phase, which stays
/// derived from the tick at the renderer's edge.
#[derive(Debug, Clone, Copy, PartialEq, Serialize, Deserialize)]
pub struct WeatherSnapshot {
    /// The integer simulation tick this snapshot applies to.
    pub tick: u64,
    /// Wind direction, world X component (fixture: a unit vector's X).
    pub wind_dir_x: f64,
    /// Wind direction, world Z component (fixture: a unit vector's Z).
    pub wind_dir_z: f64,
    /// Wind strength (fixture: non-negative scalar, Grengewald gentle range).
    pub wind_strength: f64,
    /// Rain (fixture scalar; meaning is Eisleck's to define later).
    pub rain: f64,
    /// Temperature (fixture scalar; meaning and unit are Eisleck's to define
    /// later).
    pub temperature: f64,
    /// Light (fixture scalar in `[0.0, 1.0]` for the stand-in).
    pub light: f64,
}

impl WeatherSnapshot {
    /// Builds a snapshot, refusing non-finite fields or a negative strength.
    pub fn new(
        tick: u64,
        wind_dir_x: f64,
        wind_dir_z: f64,
        wind_strength: f64,
        rain: f64,
        temperature: f64,
        light: f64,
    ) -> Result<Self, WeatherError> {
        let snapshot = Self {
            tick,
            wind_dir_x,
            wind_dir_z,
            wind_strength,
            rain,
            temperature,
            light,
        };
        snapshot.validate()?;
        Ok(snapshot)
    }

    /// The numeric rules of this step: every weather field finite, wind
    /// strength non-negative. Called again by the channel on publish, so a
    /// snapshot built by bypassing [`Self::new`] still cannot enter the
    /// channel invalid.
    pub fn validate(&self) -> Result<(), WeatherError> {
        for (field, value) in [
            ("wind_dir_x", self.wind_dir_x),
            ("wind_dir_z", self.wind_dir_z),
            ("wind_strength", self.wind_strength),
            ("rain", self.rain),
            ("temperature", self.temperature),
            ("light", self.light),
        ] {
            if !value.is_finite() {
                return Err(WeatherError::NonFinite { field });
            }
        }
        if self.wind_strength < 0.0 {
            return Err(WeatherError::NegativeWindStrength);
        }
        Ok(())
    }
}

/// The one weather channel: **one writer, everyone else reads.**
///
/// The ownership rule is enforced by the API, not by convention:
///
/// * [`WeatherChannel::new`] — no writer, no snapshot;
/// * [`WeatherChannel::claim_writer`] — the first claim wins; a second,
///   distinct identity is refused with [`WeatherError::WriterConflict`]
///   (re-claiming as the *same* identity is a no-op, never a replacement);
/// * [`WeatherChannel::publish`] — only the owner may publish, and only a
///   valid snapshot enters; refusals change nothing;
/// * [`WeatherChannel::read`] — anybody may read the latest snapshot;
///   reading never claims, never writes.
///
/// There is no global mutable static and no unrestricted setter anywhere: the
/// channel itself is the gate.
#[derive(Debug, Clone, Default, PartialEq)]
pub struct WeatherChannel {
    /// The writer identity that owns this channel, once claimed.
    writer: Option<String>,
    /// The last snapshot a valid publish left behind.
    latest: Option<WeatherSnapshot>,
}

impl WeatherChannel {
    /// A channel with no writer and no snapshot.
    pub fn new() -> Self {
        Self::default()
    }

    /// Claims the channel for `writer_id`.
    ///
    /// The first claim wins. Claiming again as the same identity succeeds and
    /// changes nothing (it is not a replacement). A *distinct* identity is
    /// refused with the conflict named on both sides.
    pub fn claim_writer(&mut self, writer_id: &str) -> Result<(), WeatherError> {
        if writer_id.is_empty() {
            return Err(WeatherError::EmptyWriterId);
        }
        match &self.writer {
            None => {
                self.writer = Some(writer_id.to_string());
                Ok(())
            }
            Some(held) if held == writer_id => Ok(()),
            Some(held) => Err(WeatherError::WriterConflict {
                held_by: held.clone(),
                attempted: writer_id.to_string(),
            }),
        }
    }

    /// The owning writer's identity, if the channel has been claimed.
    pub fn writer_id(&self) -> Option<&str> {
        self.writer.as_deref()
    }

    /// Whether a writer owns the channel.
    pub fn is_owned(&self) -> bool {
        self.writer.is_some()
    }

    /// Publishes `snapshot` on behalf of `writer_id`.
    ///
    /// Refused (with nothing changed) when there is no writer yet, when
    /// `writer_id` is not the owner, or when the snapshot itself is invalid.
    pub fn publish(
        &mut self,
        writer_id: &str,
        snapshot: WeatherSnapshot,
    ) -> Result<(), WeatherError> {
        let Some(held) = self.writer.as_deref() else {
            return Err(WeatherError::PublishWithoutWriter);
        };
        if held != writer_id {
            return Err(WeatherError::WriterConflict {
                held_by: held.to_string(),
                attempted: writer_id.to_string(),
            });
        }
        snapshot.validate()?;
        self.latest = Some(snapshot);
        Ok(())
    }

    /// Reads the latest snapshot. Reading never claims the channel and never
    /// changes it — this is how every non-writer consumer sees the weather.
    pub fn read(&self) -> Option<WeatherSnapshot> {
        self.latest
    }
}

/// The deliberately small stand-in weather driver (docs/PLAN.md §4a, step 2).
///
/// **Fixture behaviour, to be replaced by Eisleck.** Its only job is to make
/// the channel demonstrably live: a calm morning, a windy afternoon, and
/// determinism from `seed + integer tick`.
///
/// * `snapshot` is a **pure function** of `(&self, tick)`: same seed, same
///   cycle, same tick → bit-identical snapshot, always. It reads no clock, no
///   wall time and no entropy; the tick is supplied by the caller (the one
///   shared world clock).
/// * The driver's whole state is two `u64`s — seed and cycle length — proved
///   by [`StandInWeather`]'s own test. There is no accumulator, no counter and
///   no mutable random source whose call count could change results.
/// * The seed participates through [`SEED_DIRECTIONS`]: `seed % 4` picks one
///   of four fixed unit wind directions.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct StandInWeather {
    /// The run's seed: picks the stand-in wind direction.
    seed: u64,
    /// The caller's explicit cycle length in integer ticks (the test
    /// fixture's `240`; never fixed by this module).
    cycle_length: u64,
}

impl StandInWeather {
    /// A stand-in driver for `seed` over a cycle of `cycle_length` ticks.
    pub fn new(seed: u64, cycle_length: u64) -> Result<Self, WeatherError> {
        if cycle_length == 0 {
            return Err(WeatherError::ZeroCycleLength);
        }
        Ok(Self { seed, cycle_length })
    }

    /// The seed this stand-in was built with.
    pub const fn seed(&self) -> u64 {
        self.seed
    }

    /// The explicit cycle length this stand-in was built with.
    pub const fn cycle_length(&self) -> u64 {
        self.cycle_length
    }

    /// The stand-in snapshot for `tick` — a pure, deterministic function of
    /// seed, cycle length and the integer tick.
    ///
    /// First half of the cycle = calm morning, second half = windy afternoon
    /// (the fixture values at the top of this file). No time is read, kept or
    /// advanced here: the tick in the returned snapshot is the tick that was
    /// handed in.
    pub fn snapshot(&self, tick: u64) -> WeatherSnapshot {
        let phase = tick % self.cycle_length;
        // Second half of the cycle == afternoon. Integer arithmetic only.
        let afternoon = phase >= self.cycle_length - self.cycle_length / 2;
        let (wind_dir_x, wind_dir_z) =
            SEED_DIRECTIONS[(self.seed % SEED_DIRECTIONS.len() as u64) as usize];

        let (wind_strength, rain, temperature, light) = if afternoon {
            (
                STAND_IN_AFTERNOON_STRENGTH,
                STAND_IN_AFTERNOON_RAIN,
                STAND_IN_AFTERNOON_TEMPERATURE,
                STAND_IN_AFTERNOON_LIGHT,
            )
        } else {
            (
                STAND_IN_MORNING_STRENGTH,
                STAND_IN_MORNING_RAIN,
                STAND_IN_MORNING_TEMPERATURE,
                STAND_IN_MORNING_LIGHT,
            )
        };

        WeatherSnapshot {
            tick,
            wind_dir_x,
            wind_dir_z,
            wind_strength,
            rain,
            temperature,
            light,
        }
    }

    /// Claims the channel as the stand-in driver. Refused if another writer
    /// already owns it — the stand-in never displaces anyone.
    pub fn attach(&self, channel: &mut WeatherChannel) -> Result<(), WeatherError> {
        channel.claim_writer(STAND_IN_DRIVER_ID)
    }

    /// Publishes the stand-in snapshot for `tick` on an attached channel.
    ///
    /// The channel must be owned by this driver: any other owner makes the
    /// publish fail with the conflict named, and the channel stays as it was.
    pub fn drive(
        &self,
        channel: &mut WeatherChannel,
        tick: u64,
    ) -> Result<WeatherSnapshot, WeatherError> {
        let snapshot = self.snapshot(tick);
        channel.publish(STAND_IN_DRIVER_ID, snapshot)?;
        Ok(snapshot)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    /// The fixture cycle the test project uses (test-project configuration,
    /// not a game-wide authority — the same convention as Phase 2, Step 1).
    const TEST_CYCLE: u64 = 240;

    fn stand_in(seed: u64) -> StandInWeather {
        StandInWeather::new(seed, TEST_CYCLE).expect("valid cycle length")
    }

    /// A channel owned by the stand-in, holding the snapshot for `tick`.
    fn attached_at(seed: u64, tick: u64) -> (StandInWeather, WeatherChannel) {
        let stand_in = stand_in(seed);
        let mut channel = WeatherChannel::new();
        stand_in.attach(&mut channel).expect("first claim succeeds");
        stand_in.drive(&mut channel, tick).expect("owner publishes");
        (stand_in, channel)
    }

    // ------------------------------------------------------- the one writer

    #[test]
    fn weather_channel_starts_with_no_writer() {
        let mut channel = WeatherChannel::new();
        assert!(!channel.is_owned());
        assert_eq!(channel.writer_id(), None);
        assert_eq!(channel.read(), None);
        assert_eq!(
            channel.publish("first-driver", stand_in(1).snapshot(0)),
            Err(WeatherError::PublishWithoutWriter),
            "publishing before any claim must be refused"
        );
        assert_eq!(channel.read(), None, "a refused publish must change nothing");
    }

    #[test]
    fn the_first_writer_claims_and_publishes() {
        let mut channel = WeatherChannel::new();
        channel.claim_writer("driver-a").expect("first claim wins");
        assert!(channel.is_owned());
        assert_eq!(channel.writer_id(), Some("driver-a"));

        let snapshot = stand_in(7).snapshot(42);
        channel.publish("driver-a", snapshot).expect("owner publishes");
        assert_eq!(channel.read(), Some(snapshot));
    }

    #[test]
    fn re_claiming_the_same_writer_keeps_the_same_owner() {
        let mut channel = WeatherChannel::new();
        channel.claim_writer("driver-a").expect("first claim");
        channel
            .claim_writer("driver-a")
            .expect("re-claiming the same identity is not a replacement");
        assert_eq!(channel.writer_id(), Some("driver-a"));
    }

    #[test]
    fn a_second_distinct_writer_claim_is_refused_with_the_conflict_named() {
        let mut channel = WeatherChannel::new();
        channel.claim_writer("driver-a").expect("first claim");

        let refused = channel.claim_writer("driver-b");
        match refused {
            Err(WeatherError::WriterConflict { held_by, attempted }) => {
                assert_eq!(held_by, "driver-a", "the refusal must name the owner");
                assert_eq!(attempted, "driver-b", "the refusal must name the challenger");
            }
            other => panic!("a second distinct writer must be refused, got {other:?}"),
        }
        assert_eq!(
            channel.writer_id(),
            Some("driver-a"),
            "the first writer stands after the refusal"
        );
    }

    /// The step's core refusal: a second writer's *publish* is refused, the
    /// first writer stays authoritative, and the last valid snapshot is
    /// byte-for-byte unchanged by the attempt.
    #[test]
    fn a_second_writer_publish_is_refused_and_the_snapshot_is_unchanged() {
        let (stand_in, mut channel) = attached_at(60628, 130);
        let before = channel.read().expect("the owner published");
        assert_eq!(before.tick, 130);

        // A distinct second writer: both a claim and a direct publish.
        let claim = channel.claim_writer("intruder-driver");
        assert!(
            matches!(claim, Err(WeatherError::WriterConflict { .. })),
            "a distinct second claim must be refused"
        );

        let forged = WeatherSnapshot::new(999, 0.3, 0.4, 0.9, 1.0, 30.0, 1.0)
            .expect("a valid snapshot, refused purely on ownership");
        let publish = channel.publish("intruder-driver", forged);
        assert!(
            matches!(publish, Err(WeatherError::WriterConflict { .. })),
            "a second writer's publish must be refused"
        );

        assert_eq!(
            channel.read(),
            Some(before),
            "the refused attempts must leave the last valid snapshot untouched"
        );
        assert_eq!(channel.writer_id(), Some(STAND_IN_DRIVER_ID));
        assert_eq!(stand_in.seed(), 60628);
    }

    #[test]
    fn readers_obtain_the_snapshot_without_becoming_writers() {
        let (stand_in, mut channel) = attached_at(5, 24);
        // Several plain reads: no claim is possible through them.
        let first = channel.read().expect("the owner published");
        let second = channel.read().expect("still there");
        assert_eq!(first, second);
        assert_eq!(first.tick, 24);
        // Reading never made anyone an owner: a distinct identity reading the
        // snapshot and then trying to claim is refused like any second writer.
        assert!(matches!(
            channel.claim_writer("reader-script"),
            Err(WeatherError::WriterConflict { .. })
        ));
        // ...and reading changed nothing: the owner still publishes.
        channel
            .publish(STAND_IN_DRIVER_ID, stand_in.snapshot(25))
            .expect("the owner still publishes");
        assert_eq!(channel.read().expect("published").tick, 25);
        assert_eq!(channel.writer_id(), Some(STAND_IN_DRIVER_ID));
    }

    #[test]
    fn an_empty_writer_id_is_refused() {
        let mut channel = WeatherChannel::new();
        assert_eq!(channel.claim_writer(""), Err(WeatherError::EmptyWriterId));
        assert!(!channel.is_owned());
    }

    #[test]
    fn non_finite_and_negative_values_are_refused_and_leave_the_snapshot_unchanged() {
        let (stand_in, mut channel) = attached_at(3, 10);
        let before = channel.read().expect("the owner published");

        let nan_direction = WeatherSnapshot::new(11, f64::NAN, 0.0, 0.5, 0.0, 10.0, 0.5);
        assert!(matches!(
            nan_direction,
            Err(WeatherError::NonFinite { field: "wind_dir_x" })
        ));

        let infinite_rain = WeatherSnapshot::new(11, 1.0, 0.0, 0.5, f64::INFINITY, 10.0, 0.5);
        assert!(matches!(
            infinite_rain,
            Err(WeatherError::NonFinite { field: "rain" })
        ));

        let negative_strength = WeatherSnapshot::new(11, 1.0, 0.0, -0.1, 0.0, 10.0, 0.5);
        assert_eq!(
            negative_strength,
            Err(WeatherError::NegativeWindStrength)
        );

        // A struct literal bypassing `new` still cannot enter the channel.
        let bypass = WeatherSnapshot {
            tick: 12,
            wind_dir_x: 1.0,
            wind_dir_z: 0.0,
            wind_strength: -5.0,
            rain: 0.0,
            temperature: 10.0,
            light: 0.5,
        };
        assert_eq!(
            channel.publish(STAND_IN_DRIVER_ID, bypass),
            Err(WeatherError::NegativeWindStrength),
            "the channel re-validates on publish"
        );
        assert_eq!(channel.read(), Some(before), "nothing valid was lost");
        assert_eq!(stand_in.seed(), 3);
    }

    #[test]
    fn the_snapshot_carries_the_planned_fields() {
        let snapshot = WeatherSnapshot::new(240, 1.0, 0.0, 0.7, 0.1, 19.0, 0.85)
            .expect("valid fixture values");
        assert_eq!(snapshot.tick, 240);
        assert_eq!(snapshot.wind_dir_x, 1.0);
        assert_eq!(snapshot.wind_dir_z, 0.0);
        assert_eq!(snapshot.wind_strength, 0.7);
        assert_eq!(snapshot.rain, 0.1);
        assert_eq!(snapshot.temperature, 19.0);
        assert_eq!(snapshot.light, 0.85);
        // All six weather fields are finite, by construction and by rule.
        for value in [
            snapshot.wind_dir_x,
            snapshot.wind_dir_z,
            snapshot.wind_strength,
            snapshot.rain,
            snapshot.temperature,
            snapshot.light,
        ] {
            assert!(value.is_finite());
        }
    }

    #[test]
    fn a_zero_cycle_length_is_refused() {
        assert_eq!(StandInWeather::new(1, 0), Err(WeatherError::ZeroCycleLength));
    }

    // ------------------------------------------------ the stand-in schedule

    #[test]
    fn the_stand_in_is_deterministic_from_seed_and_tick() {
        // Two independent drivers, the same seed, calls interleaved: every
        // tick must come back bit-identical, in whatever order they are asked.
        let a = stand_in(60628);
        let b = stand_in(60628);
        for tick in (0..TEST_CYCLE).step_by(3) {
            assert_eq!(a.snapshot(tick), b.snapshot(tick), "tick {tick} diverged");
            assert_eq!(a.snapshot(tick), a.snapshot(tick), "tick {tick} is unstable");
        }
        // ... and driving a channel twice with the same inputs agrees too.
        let (_, channel_a) = attached_at(60628, 119);
        let (_, channel_b) = attached_at(60628, 119);
        assert_eq!(channel_a.read(), channel_b.read());
    }

    /// The seed must shape the result: if it were silently ignored, every
    /// seed would produce seed 0's direction.
    #[test]
    fn the_seed_participates_in_the_stand_in_direction() {
        let mut directions = std::collections::BTreeSet::new();
        for seed in 0..4 {
            let snapshot = stand_in(seed).snapshot(60);
            assert!(
                snapshot.wind_dir_x.is_finite() && snapshot.wind_dir_z.is_finite(),
                "direction must be finite"
            );
            let length = (snapshot.wind_dir_x * snapshot.wind_dir_x
                + snapshot.wind_dir_z * snapshot.wind_dir_z)
                .sqrt();
            assert!((length - 1.0).abs() < 1e-12, "the direction must be a unit vector");
            directions.insert((snapshot.wind_dir_x.to_bits(), snapshot.wind_dir_z.to_bits()));
        }
        assert_eq!(
            directions.len(),
            4,
            "four seeds must select four distinct directions — the seed is not ignored"
        );
        assert_ne!(
            stand_in(0).snapshot(60).wind_dir_x,
            stand_in(1).snapshot(60).wind_dir_x
        );
    }

    /// The broad stand-in shape the acceptance asserts: calm in the morning,
    /// windy in the afternoon, and only wind visibly changes between them.
    #[test]
    fn the_stand_in_is_calm_in_the_morning_and_windy_in_the_afternoon() {
        let stand_in = stand_in(60628);
        let half = TEST_CYCLE - TEST_CYCLE / 2;
        for tick in 0..TEST_CYCLE {
            let snapshot = stand_in.snapshot(tick);
            assert_eq!(snapshot.tick, tick, "the snapshot carries the driven tick");
            if tick < half {
                assert!(
                    snapshot.wind_strength <= 0.1,
                    "morning tick {tick} must be calm, strength {}",
                    snapshot.wind_strength
                );
                assert!(snapshot.wind_strength >= 0.0);
            } else {
                assert!(
                    snapshot.wind_strength >= 0.5,
                    "afternoon tick {tick} must be windy, strength {}",
                    snapshot.wind_strength
                );
            }
        }
        // Wind is the value that visibly changes across the half-cycle; the
        // rest of the fixture is present and simple by design.
        assert_ne!(
            stand_in.snapshot(0).wind_strength,
            stand_in.snapshot(half).wind_strength
        );
    }

    #[test]
    fn driving_publishes_the_world_tick_it_was_given() {
        let (stand_in, mut channel) = attached_at(60628, 0);
        // Drive a full fixture cycle through the channel, exactly the way the
        // shared clock will drive it: the snapshot's tick is every time the
        // tick that was handed in.
        for tick in 0..TEST_CYCLE {
            let published = stand_in
                .drive(&mut channel, tick)
                .expect("the owner publishes");
            assert_eq!(published.tick, tick);
            assert_eq!(channel.read().expect("published").tick, tick);
            assert_eq!(channel.writer_id(), Some(STAND_IN_DRIVER_ID));
        }
    }

    #[test]
    fn the_stand_in_refuses_a_channel_owned_by_another_writer() {
        let stand_in = stand_in(60628);
        let mut channel = WeatherChannel::new();
        channel.claim_writer("intruder-driver").expect("first claim");

        let attached = stand_in.attach(&mut channel);
        assert!(
            matches!(attached, Err(WeatherError::WriterConflict { .. })),
            "the stand-in must never displace an existing writer"
        );
        let driven = stand_in.drive(&mut channel, 5);
        assert!(
            matches!(driven, Err(WeatherError::WriterConflict { .. })),
            "the stand-in must not publish on a channel it does not own"
        );
        assert_eq!(channel.read(), None, "the channel is untouched");
        assert_eq!(channel.writer_id(), Some("intruder-driver"));
    }

    // --------------------------------------------- no time, no entropy state

    /// The stand-in driver's entire state is two `u64`s: no float
    /// accumulator, no tick counter, no random source. The compiler's own
    /// type names, not a grep.
    #[test]
    fn the_stand_in_driver_holds_no_time_state() {
        let stand_in = stand_in(60628);
        assert_eq!(std::any::type_name_of_val(&stand_in.seed), "u64");
        assert_eq!(std::any::type_name_of_val(&stand_in.cycle_length), "u64");
        assert_eq!(
            std::mem::size_of::<StandInWeather>(),
            2 * std::mem::size_of::<u64>(),
            "exactly two u64 fields — nothing hidden in the layout"
        );

        // The source itself: the struct declares only seed and cycle length.
        let source = include_str!("weather.rs");
        let start = source
            .find("pub struct StandInWeather")
            .expect("the stand-in struct exists");
        let rest = &source[start..];
        let end = rest.find("\n}").expect("the struct body ends");
        let body = &rest[..end];
        assert!(body.contains("seed: u64"));
        assert!(body.contains("cycle_length: u64"));
        let wall_clock = ["el", "apsed"].concat();
        for forbidden in ["tick:", "seconds", "rng", "accumulator", wall_clock.as_str()] {
            assert!(
                !body.contains(forbidden),
                "the stand-in struct must not hold '{forbidden}'"
            );
        }
    }

    /// The source-level backstop for the same property: no frame delta, no
    /// wall clock, no floor-of-seconds, no entropy source, and no second
    /// clock — anywhere in this module's code (comments are skipped: the
    /// prose legitimately explains what is absent). The banned idioms are
    /// assembled at runtime so this list cannot trip itself.
    #[test]
    fn the_weather_source_accumulates_no_time_and_uses_no_entropy_source() {
        let source = include_str!("weather.rs");
        let code = source
            .lines()
            .filter(|line| !line.trim_start().starts_with("//"))
            .collect::<Vec<_>>()
            .join("\n");

        for banned in [
            ["e", "lapsed"].concat(),
            ["del", "ta"].concat(),
            ["floor", "("].concat(),
            ["System", "Time"].concat(),
            ["Inst", "ant::now"].concat(),
            ["thread", "_rng"].concat(),
            ["ran", "dom"].concat(),
            ["World", "Clock"].concat(),
            ["as", "_secs"].concat(),
            ["total", "_seconds"].concat(),
        ] {
            assert!(
                !code.contains(&banned),
                "the weather source must not contain '{banned}'"
            );
        }
    }
}
