//! The game's save — Phase 2, Step 3 "the game's save" (docs/PLAN.md §4a).
//!
//! A narrow, explicitly versioned container for exactly the authoritative
//! state the test game needs to continue deterministically: the **tool
//! identity** (a plain string, copied in by the caller and given no deeper
//! meaning here), the one clock's complete state, the one weather snapshot
//! plus the stand-in driver's fixture configuration, and the one stand-in
//! inhabitant's state. Serialization is deterministic: the document is plain
//! structs serialized in declaration order, so identical state produces
//! identical bytes.
//!
//! ## The shape borrowed — and the code that was not
//!
//! The useful shape is the preserved anvil save's (read-only design
//! reference: `buggy-vault@24181142`,
//! `repos/anvil/source/crates/anvil_runtime/src/snapshot/format.rs` and
//! `repos/anvil/source/crates/anvil_runtime/src/lib.rs`; preserved original
//! anvil main `97c8fdbd7ff85779f33456fd7c444657f8d90b36`): a versioned
//! serialized document, an authored-world identity copied in as data, time
//! state, weather state, named simulation state, deterministic continuation.
//! Nothing is copied — no donor source, and the donor runtime crate is not a
//! dependency of this crate. Two donor behaviours are deliberately **not**
//! reproduced, because the Phase 2 plan supersedes them:
//!
//! * an exact authored-world hash mismatch **refused** restore there; here a
//!   changed tool identity is not an error at all — [`adapt_to_world`] keeps
//!   what still fits, drops references that no longer resolve in the world
//!   the caller says is current, and reports every drop explicitly;
//! * some donor restore failures were merely logged while restore still
//!   returned success (and event queues were dropped); here malformed bytes,
//!   an unsupported format version and structurally invalid state each fail
//!   clearly, and nothing is dropped without appearing in the load report.
//!
//! ## What may fail, and what adapts
//!
//! [`from_bytes`] fails clearly for data that cannot be trusted at all:
//! malformed bytes, an unsupported `format_version`, structurally invalid
//! state (a zero tick length, a zero speed, an empty identity, needs outside
//! `0..=1`, non-finite weather). A **changed tool identity** never fails: it
//! is adaptation input. A saved place that no longer exists never fails
//! either: only that one reference is removed, named in the report, and the
//! rest of the state — including everything else about the inhabitant — is
//! kept.
//!
//! ## Loading never rewrites the save
//!
//! This module never opens a file. It converts bytes to state
//! ([`from_bytes`]) and state to bytes ([`to_bytes`]); reading, writing and
//! the decision of which path is the layer above's business. Loading is a
//! pure function of the save's bytes plus the caller's current-world
//! description, so it cannot rewrite anything, and no source path of any
//! tool or authored world belongs in this file.

use std::fmt;

use serde::{Deserialize, Serialize};

use crate::clock::ClockState;
use crate::scorer::{self, NEED_COUNT};
use crate::weather::{WeatherError, WeatherSnapshot};

/// The save's explicit internal format version (this build's documents are
/// written as `format_version = 1`).
///
/// This is the *only* compatibility switch in this step: a document whose
/// `format_version` is not exactly this value is refused with
/// [`SaveError::UnsupportedVersion`] rather than guessed at. There is no
/// migration framework here on purpose (docs/PLAN.md, phase 2 step 3) —
/// when the format changes, this number changes and older documents fail
/// clearly.
pub const SAVE_FORMAT_VERSION: u32 = 1;

/// The load report's reason code for a saved place that the caller's current
/// world no longer lists.
pub const REASON_MISSING_PLACE: &str = "missing-place";

/// The one field of the inhabitant state that can be dropped: the optional
/// reference to a current place.
pub const CURRENT_PLACE_FIELD: &str = "current_place";

/// A save document: the whole authoritative state of the test game
/// (docs/PLAN.md, phase 2 step 3 — "anvil's shape" as a design reference).
///
/// Deterministic by construction: fixed declaration order, no maps or sets,
/// no timestamps, no wall-clock readings. Two documents built from identical
/// state serialize to identical bytes.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct GameSave {
    /// The explicit internal format version; always [`SAVE_FORMAT_VERSION`]
    /// for documents this build writes.
    pub format_version: u32,
    /// The tool identity — the Yolanda world revision the game was built
    /// from, **copied in by the caller as a plain string**. This crate
    /// assigns it no meaning, never resolves it against anything, and never
    /// opens a file because of it.
    pub tool_identity: String,
    /// The one clock's complete integer state.
    pub clock: ClockState,
    /// The one weather snapshot plus the stand-in driver's fixture
    /// configuration, needed to continue the weather deterministically.
    pub weather: WeatherState,
    /// The one stand-in inhabitant's narrow state.
    pub inhabitant: InhabitantState,
}

/// Weather state as the save holds it: the latest authoritative snapshot
/// plus the stand-in driver's two fixture constants.
///
/// Deliberately absent: the presentation phase / motion phase and anything
/// renderer-facing. The shader global's vector is derived at the renderer's
/// edge from the restored integer tick and this snapshot (as Phase 2 Step 2
/// defines it); it is not saved state.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct WeatherState {
    /// The stand-in driver's seed (fixture configuration of the run).
    pub seed: u64,
    /// The stand-in driver's explicit cycle length in integer ticks
    /// (fixture configuration of the run).
    pub cycle_length: u64,
    /// The latest published weather snapshot.
    pub snapshot: WeatherSnapshot,
}

/// The one stand-in inhabitant's state: enough to resume the existing
/// scorer, and nothing more.
///
/// No memory, no relationships, no schedule, no movement, no NPC behaviour
/// (that is Munshausen's and Eisleck's business, not the save's).
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct InhabitantState {
    /// The stable stand-in inhabitant id, e.g. `standin-inhabitant-1`.
    pub id: String,
    /// The scorer seed the inhabitant's decisions are made with.
    pub seed: u64,
    /// The seven need-satisfaction values, in [`scorer::NEED_ORDER`].
    pub needs: [f32; NEED_COUNT],
    /// The inhabitant's current place — an **optional plain reference**, kept
    /// only to exercise changed-world adaptation. It is not a new behavioral
    /// input to the scorer; the scorer already receives place information
    /// through its activities.
    pub current_place: Option<String>,
}

/// A failed save read/write/parse, distinct from adaptation.
///
/// These are the cases the plan explicitly allows to fail: malformed bytes,
/// an unsupported format version, structurally invalid state, and I/O
/// trouble. A changed tool identity is **not** among them — that adapts.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum SaveError {
    /// The bytes are not a well-formed document of this format.
    Malformed(String),
    /// The document declares a `format_version` this build does not know.
    UnsupportedVersion {
        /// The version the document declared.
        found: u32,
        /// The version this build supports.
        supported: u32,
    },
    /// The document parsed but its state is structurally invalid.
    Invalid(String),
    /// The file behind the caller's path could not be read or written.
    Io(String),
}

impl fmt::Display for SaveError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            SaveError::Malformed(detail) => write!(f, "the save bytes are malformed: {detail}"),
            SaveError::UnsupportedVersion { found, supported } => write!(
                f,
                "unsupported save format version {found} (this build supports {supported})"
            ),
            SaveError::Invalid(detail) => write!(f, "the save's state is invalid: {detail}"),
            SaveError::Io(detail) => write!(f, "the save file could not be handled: {detail}"),
        }
    }
}

impl std::error::Error for SaveError {}

/// The caller's narrow plain description of the world a save is being loaded
/// **against**: the current tool identity and the currently valid place ids.
///
/// Plain strings in, plain strings out — nothing here queries a repository,
/// an engine or another module for them (docs/PLAN.md, phase 2 step 3).
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct CurrentWorld {
    /// The current tool identity, as the caller supplies it.
    pub tool_identity: String,
    /// The place ids the caller says currently exist, in the caller's order.
    pub valid_places: Vec<String>,
}

impl CurrentWorld {
    /// The world description as the caller supplies it: identity plus the
    /// valid place ids.
    pub fn new(
        tool_identity: impl Into<String>,
        valid_places: impl IntoIterator<Item = impl Into<String>>,
    ) -> Self {
        Self {
            tool_identity: tool_identity.into(),
            valid_places: valid_places.into_iter().map(Into::into).collect(),
        }
    }
}

/// One explicitly reported removal: a saved reference that does not resolve
/// in the caller's current world, with everything needed to name it.
///
/// The report ordering is deterministic: adaptations visit the saved state
/// in field order, and this format drops at most this one field.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct DropRecord {
    /// The subject whose state was dropped, e.g. `standin-inhabitant-1`.
    pub subject: String,
    /// The field/path that held the reference, e.g. `current_place`.
    pub field: String,
    /// The dropped reference itself, e.g. `market-square`.
    pub value: String,
    /// Why it was dropped, e.g. `missing-place`.
    pub reason: String,
}

impl DropRecord {
    /// The compact machine-checkable form: `subject.field:value`.
    pub fn describe(&self) -> String {
        format!("{}.{}:{}", self.subject, self.field, self.value)
    }
}

/// The result of loading a parsed save against a [`CurrentWorld`]: whether
/// the tool identity changed, and every drop that adaptation performed.
///
/// An identity change with no dangling references is a perfectly ordinary
/// successful load: `identity_changed = true`, `drops` empty.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct LoadReport {
    /// Whether the saved tool identity differs from the caller's current one.
    /// Never an error on its own.
    pub identity_changed: bool,
    /// Every reference that was removed, in deterministic order.
    pub drops: Vec<DropRecord>,
}

impl LoadReport {
    /// The compact `subject.field:value` forms, in report order.
    pub fn describe_drops(&self) -> Vec<String> {
        self.drops.iter().map(DropRecord::describe).collect()
    }
}

/// Serializes a save to bytes deterministically: identical state produces
/// identical bytes, and any structurally invalid state is refused before it
/// can reach disk (a non-finite float cannot be represented anyway).
pub fn to_bytes(save: &GameSave) -> Result<Vec<u8>, SaveError> {
    validate(save)?;
    serde_json::to_vec(save).map_err(|error| SaveError::Invalid(error.to_string()))
}

/// Parses bytes into a save, then refuses — clearly and specifically — an
/// unsupported `format_version` or structurally invalid state.
///
/// A changed tool identity is not checked here (there is no identity to
/// compare against yet); identity comparison happens in [`adapt_to_world`]
/// and never fails.
pub fn from_bytes(bytes: &[u8]) -> Result<GameSave, SaveError> {
    let save: GameSave =
        serde_json::from_slice(bytes).map_err(|error| SaveError::Malformed(error.to_string()))?;
    validate(&save)?;
    Ok(save)
}

/// Loads a parsed save against the caller's current world: keeps every saved
/// state element that still fits, removes only references that do not
/// resolve, reports every removal, and always completes.
///
/// The tool-identity comparison marks the load as adapted; it never fails
/// and never removes state. The only removable reference in this format is
/// the inhabitant's `current_place` when the caller's valid-place set no
/// longer lists it — the inhabitant itself (id, seed, all seven needs) is
/// kept, because the plan says keep what fits.
pub fn adapt_to_world(save: GameSave, world: &CurrentWorld) -> (GameSave, LoadReport) {
    let identity_changed = save.tool_identity != world.tool_identity;
    let mut save = save;
    let mut drops = Vec::new();

    if let Some(place) = save.inhabitant.current_place.as_deref() {
        let still_valid = world.valid_places.iter().any(|valid| valid == place);
        if !still_valid {
            drops.push(DropRecord {
                subject: save.inhabitant.id.clone(),
                field: CURRENT_PLACE_FIELD.to_string(),
                value: place.to_string(),
                reason: REASON_MISSING_PLACE.to_string(),
            });
            save.inhabitant.current_place = None;
        }
    }

    (
        save,
        LoadReport {
            identity_changed,
            drops,
        },
    )
}

/// The structural rules every document must satisfy, applied identically on
/// write and on read: a bad save never leaves this crate, and a bad save
/// never enters the game.
fn validate(save: &GameSave) -> Result<(), SaveError> {
    if save.format_version != SAVE_FORMAT_VERSION {
        return Err(SaveError::UnsupportedVersion {
            found: save.format_version,
            supported: SAVE_FORMAT_VERSION,
        });
    }
    if save.tool_identity.trim().is_empty() {
        return Err(SaveError::Invalid(
            "the tool identity must be a non-empty plain string".to_string(),
        ));
    }
    if save.clock.tick_length_ns == 0 {
        return Err(SaveError::Invalid(
            "the clock's tick length must be at least one nanosecond".to_string(),
        ));
    }
    if save.clock.speed == 0 {
        return Err(SaveError::Invalid(
            "the clock's speed must be at least 1 (0 is pause, not speed)".to_string(),
        ));
    }
    if save.weather.cycle_length == 0 {
        return Err(SaveError::Invalid(
            "the weather cycle length must be at least one tick".to_string(),
        ));
    }
    save.weather
        .snapshot
        .validate()
        .map_err(|error: WeatherError| SaveError::Invalid(error.to_string()))?;
    if save.inhabitant.id.trim().is_empty() {
        return Err(SaveError::Invalid(
            "the inhabitant's id must be a non-empty plain string".to_string(),
        ));
    }
    scorer::validate_needs(&save.inhabitant.needs)
        .map_err(|error| SaveError::Invalid(error.to_string()))?;
    if matches!(&save.inhabitant.current_place, Some(place) if place.trim().is_empty()) {
        return Err(SaveError::Invalid(
            "the inhabitant's current place must not be an empty string".to_string(),
        ));
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    /// The Phase 2 fixture's clock state at the noon save point: the clock
    /// points at the next tick, 120.
    fn fixture_clock() -> ClockState {
        ClockState {
            tick: 120,
            tick_length_ns: 100_000_000,
            speed: 1,
            paused: false,
        }
    }

    /// The fixture's weather at the noon save point: the latest snapshot is
    /// tick 119, and the stand-in driver's two configuration values.
    fn fixture_weather() -> WeatherState {
        WeatherState {
            seed: 70021,
            cycle_length: 240,
            snapshot: WeatherSnapshot::new(119, 0.0, 1.0, 0.7, 0.1, 19.0, 0.85)
                .expect("valid fixture values"),
        }
    }

    /// The fixture's one stand-in inhabitant, ready for the decision at 120.
    fn fixture_inhabitant() -> InhabitantState {
        InhabitantState {
            id: "standin-inhabitant-1".to_string(),
            seed: 60628,
            needs: [0.40, 0.35, 0.60, 0.50, 0.45, 0.42, 0.55],
            current_place: Some("market-square".to_string()),
        }
    }

    /// A complete fixture save, as the noon save point writes it.
    fn fixture_save() -> GameSave {
        GameSave {
            format_version: SAVE_FORMAT_VERSION,
            tool_identity: "world-revision-A".to_string(),
            clock: fixture_clock(),
            weather: fixture_weather(),
            inhabitant: fixture_inhabitant(),
        }
    }

    /// The ordinary load's current world: the same identity, the same six
    /// qualified test places.
    fn current_world_same() -> CurrentWorld {
        CurrentWorld::new(
            "world-revision-A",
            [
                "north-hills",
                "east-field",
                "market-square",
                "cottage-loft",
                "ridge",
                "kitchen",
            ],
        )
    }

    /// The changed-world load's current world: another identity, and exactly
    /// the saved place removed from the valid set.
    fn current_world_changed() -> CurrentWorld {
        CurrentWorld::new(
            "world-revision-B",
            ["north-hills", "east-field", "cottage-loft", "ridge", "kitchen"],
        )
    }

    fn as_text(save: &GameSave) -> String {
        let bytes = to_bytes(save).expect("valid fixture save");
        String::from_utf8(bytes).expect("serde_json writes utf-8")
    }

    /// The save format has one explicit internal version, and documents this
    /// build writes declare exactly it.
    #[test]
    fn the_save_format_has_an_explicit_internal_version() {
        assert_eq!(SAVE_FORMAT_VERSION, 1);
        let text = as_text(&fixture_save());
        assert!(
            text.contains("\"format_version\":1"),
            "the serialized document must declare format_version 1, got: {text}"
        );
    }

    /// Serialization is deterministic: two independently built copies of the
    /// same state produce byte-identical documents, and so do a document and
    /// its own re-parse.
    #[test]
    fn identical_state_serializes_to_identical_bytes() {
        let first = to_bytes(&fixture_save()).expect("valid fixture save");
        let second = to_bytes(&fixture_save()).expect("valid fixture save");
        assert_eq!(first, second, "identical state, identical bytes");

        let parsed = from_bytes(&first).expect("valid fixture document");
        let third = to_bytes(&parsed).expect("valid fixture save");
        assert_eq!(
            first, third,
            "serialize -> parse -> serialize is byte-stable"
        );
    }

    /// The whole document round-trips: every field of the fixture survives
    /// serialization and parsing with `==` — the layout, the identity, the
    /// clock, the weather and the inhabitant.
    #[test]
    fn serialize_then_parse_preserves_every_field() {
        let save = fixture_save();
        let parsed = from_bytes(&to_bytes(&save).expect("valid")).expect("valid document");
        assert_eq!(parsed, save);
        assert_eq!(parsed.format_version, SAVE_FORMAT_VERSION);
        assert_eq!(parsed.tool_identity, save.tool_identity);
        assert_eq!(parsed.clock, save.clock);
        assert_eq!(parsed.weather, save.weather);
        assert_eq!(parsed.inhabitant, save.inhabitant);
    }

    /// The clock state round-trips exactly — every integer and bool field —
    /// including a non-trivial case (paused, speed 3, deep tick).
    #[test]
    fn the_clock_state_round_trips_exactly() {
        let save = GameSave {
            clock: ClockState {
                tick: 9_876_543_210,
                tick_length_ns: 100_000_000,
                speed: 3,
                paused: true,
            },
            ..fixture_save()
        };
        let parsed = from_bytes(&to_bytes(&save).expect("valid")).expect("valid document");
        assert_eq!(parsed.clock, save.clock);
        assert_eq!(parsed.clock.tick, 9_876_543_210);
        assert_eq!(parsed.clock.tick_length_ns, 100_000_000);
        assert_eq!(parsed.clock.speed, 3);
        assert!(parsed.clock.paused);
        // And the fixture's own clock round-trips too.
        let parsed = from_bytes(&to_bytes(&fixture_save()).expect("valid")).expect("valid");
        assert_eq!(parsed.clock, fixture_clock());
    }

    /// The weather snapshot round-trips exactly: all seven fields, with the
    /// float values compared bit-for-bit rather than approximately.
    #[test]
    fn the_weather_snapshot_round_trips_exactly() {
        let save = fixture_save();
        let parsed = from_bytes(&to_bytes(&save).expect("valid")).expect("valid document");
        let (got, want) = (parsed.weather.snapshot, save.weather.snapshot);
        assert_eq!(got.tick, want.tick);
        assert_eq!(got.wind_dir_x.to_bits(), want.wind_dir_x.to_bits());
        assert_eq!(got.wind_dir_z.to_bits(), want.wind_dir_z.to_bits());
        assert_eq!(got.wind_strength.to_bits(), want.wind_strength.to_bits());
        assert_eq!(got.rain.to_bits(), want.rain.to_bits());
        assert_eq!(got.temperature.to_bits(), want.temperature.to_bits());
        assert_eq!(got.light.to_bits(), want.light.to_bits());
        // The driver's two fixture values come back too.
        assert_eq!(parsed.weather.seed, 70021);
        assert_eq!(parsed.weather.cycle_length, 240);
    }

    /// The stand-in inhabitant's state round-trips exactly: id, seed, all
    /// seven needs (bit-for-bit), and both the present and the absent place
    /// reference.
    #[test]
    fn the_inhabitant_state_round_trips_exactly() {
        let save = fixture_save();
        let parsed = from_bytes(&to_bytes(&save).expect("valid")).expect("valid document");
        assert_eq!(parsed.inhabitant.id, "standin-inhabitant-1");
        assert_eq!(parsed.inhabitant.seed, 60628);
        for (got, want) in parsed
            .inhabitant
            .needs
            .iter()
            .zip(save.inhabitant.needs.iter())
        {
            assert_eq!(got.to_bits(), want.to_bits(), "need bits survive");
        }
        assert_eq!(
            parsed.inhabitant.current_place.as_deref(),
            Some("market-square")
        );

        let no_place = GameSave {
            inhabitant: InhabitantState {
                current_place: None,
                ..fixture_inhabitant()
            },
            ..fixture_save()
        };
        let parsed = from_bytes(&to_bytes(&no_place).expect("valid")).expect("valid document");
        assert_eq!(parsed.inhabitant.current_place, None);
    }

    /// The tool identity is copied through verbatim as a plain string — no
    /// normalization, no hashing, no deeper meaning — so whatever the caller
    /// passed in comes back out of the document byte-for-byte.
    #[test]
    fn the_tool_identity_round_trips_exactly() {
        for identity in [
            "world-revision-A",
            "world-revision-B",
            "Yolanda world revision 2026-10-01 (build 42)",
            "  spaced identity is the caller's business  ",
        ] {
            let save = GameSave {
                tool_identity: identity.to_string(),
                ..fixture_save()
            };
            let parsed = from_bytes(&to_bytes(&save).expect("valid")).expect("valid document");
            assert_eq!(parsed.tool_identity, identity);
        }
    }

    /// Loading against the same identity and the unchanged place set is an
    /// ordinary load: not adapted, zero drops, the state untouched.
    #[test]
    fn same_world_load_has_zero_drops_and_is_not_adapted() {
        let save = fixture_save();
        let (loaded, report) = adapt_to_world(save.clone(), &current_world_same());
        assert!(!report.identity_changed);
        assert!(report.drops.is_empty(), "nothing was dropped");
        assert_eq!(report.describe_drops(), Vec::<String>::new());
        assert_eq!(loaded, save, "an ordinary load changes no state");
    }

    /// Loading against another identity completes successfully and marks the
    /// load adapted — never refused, never emptied.
    #[test]
    fn changed_world_load_adapts_and_completes() {
        let save = fixture_save();
        let (loaded, report) = adapt_to_world(save.clone(), &current_world_changed());
        assert!(report.identity_changed, "the identity difference is seen");
        assert_eq!(loaded.tool_identity, "world-revision-A", "the save's own identity is kept as data");
        assert_eq!(
            loaded.inhabitant.current_place, None,
            "the dangling reference is gone"
        );
        assert_eq!(loaded.clock, save.clock, "clock state survives adaptation");
        assert_eq!(loaded.weather, save.weather, "weather state survives");
        assert_eq!(loaded.inhabitant.id, save.inhabitant.id);
        assert_eq!(loaded.inhabitant.seed, save.inhabitant.seed);
        assert_eq!(loaded.inhabitant.needs, save.inhabitant.needs);
    }

    /// The one drop is exactly the place reference, named precisely:
    /// subject, field, value and reason — and nothing else about the
    /// inhabitant is touched.
    #[test]
    fn a_missing_place_drops_only_the_place_reference_and_names_it() {
        let save = fixture_save();
        let (loaded, report) = adapt_to_world(save.clone(), &current_world_changed());
        assert_eq!(report.drops.len(), 1);
        let drop = &report.drops[0];
        assert_eq!(drop.subject, "standin-inhabitant-1");
        assert_eq!(drop.field, "current_place");
        assert_eq!(drop.value, "market-square");
        assert_eq!(drop.reason, REASON_MISSING_PLACE);
        assert_eq!(drop.describe(), "standin-inhabitant-1.current_place:market-square");
        assert_eq!(
            report.describe_drops(),
            vec!["standin-inhabitant-1.current_place:market-square".to_string()]
        );

        // Everything that fits is retained value-identically.
        assert_eq!(loaded.format_version, save.format_version);
        assert_eq!(loaded.tool_identity, save.tool_identity);
        assert_eq!(loaded.clock, save.clock);
        assert_eq!(loaded.weather, save.weather);
        assert_eq!(loaded.inhabitant.id, save.inhabitant.id);
        assert_eq!(loaded.inhabitant.seed, save.inhabitant.seed);
        assert_eq!(loaded.inhabitant.needs, save.inhabitant.needs);
        assert_eq!(loaded.inhabitant.current_place, None, "only the reference");
    }

    /// Retained state is byte-identical to what fit: serializing the adapted
    /// save and diffing it against the original shows only the identity
    /// marker difference is *not* even that — the serialized bytes differ
    /// only in the `current_place` field becoming `null`.
    #[test]
    fn retained_state_is_value_identical_to_what_fit() {
        let save = fixture_save();
        let original_text = as_text(&save);
        let (loaded, report) = adapt_to_world(save, &current_world_changed());
        assert_eq!(report.drops.len(), 1);
        let adapted_text = as_text(&loaded);

        // The one field that changes: `"current_place":"market-square"` ->
        // `"current_place":null` (the value runs to the next `}` or `,`,
        // and neither marker nor value contains either).
        let marker = "\"current_place\":";
        let field_slice = |text: &str| -> String {
            let start = text.find(marker).expect("the field is present");
            let rest = &text[start..];
            let end = rest.find(['}', ',']).expect("the field ends");
            rest[..end].to_string()
        };
        assert_eq!(field_slice(&original_text), "\"current_place\":\"market-square\"");
        assert_eq!(field_slice(&adapted_text), "\"current_place\":null");

        // Every other byte of the document is unchanged.
        let stripped_original = original_text.replace("\"current_place\":\"market-square\"", "");
        let stripped_adapted = adapted_text.replace("\"current_place\":null", "");
        assert_eq!(
            stripped_original, stripped_adapted,
            "only the dropped reference differs between the two documents"
        );
    }

    /// An unknown `format_version` fails clearly with the version named —
    /// no guessing, no partial load.
    #[test]
    fn an_unsupported_format_version_fails_clearly() {
        let text = as_text(&fixture_save()).replace(
            "\"format_version\":1",
            "\"format_version\":2",
        );
        assert!(text.contains("\"format_version\":2"));
        let error = from_bytes(text.as_bytes()).expect_err("version 2 is not this build's");
        assert_eq!(
            error,
            SaveError::UnsupportedVersion {
                found: 2,
                supported: SAVE_FORMAT_VERSION
            }
        );
        assert!(!matches!(error, SaveError::Malformed(_)));

        let future = text.replace("\"format_version\":2", "\"format_version\":999");
        let error = from_bytes(future.as_bytes()).expect_err("version 999 is unknown");
        assert_eq!(
            error,
            SaveError::UnsupportedVersion {
                found: 999,
                supported: SAVE_FORMAT_VERSION
            }
        );
    }

    /// Malformed bytes fail clearly as malformed — truncated, empty or
    /// simply not JSON of this shape.
    #[test]
    fn malformed_bytes_fail_clearly() {
        for bytes in [
            &b""[..],
            &b"{"[..],
            &b"not json at all"[..],
            &b"[]"[..],
            &br#"{"format_version":1,"tool_identity":"A"}"#[..],
        ] {
            let error = from_bytes(bytes).expect_err("these bytes are not a save");
            assert!(
                matches!(error, SaveError::Malformed(_)),
                "expected Malformed for {bytes:?}, got {error:?}"
            );
        }
    }

    /// Structurally invalid state fails clearly with the problem named: a
    /// zero speed, needs outside `0..=1`, an empty identity — none of them
    /// load, and none of them is confused with an identity change.
    #[test]
    fn structurally_invalid_save_state_fails_clearly() {
        let text = as_text(&fixture_save());

        let zero_speed = text.replace("\"speed\":1", "\"speed\":0");
        assert!(zero_speed.contains("\"speed\":0"));
        let error = from_bytes(zero_speed.as_bytes()).expect_err("speed 0 is invalid");
        assert!(
            matches!(error, SaveError::Invalid(ref message) if message.contains("speed")),
            "the refusal names the speed, got: {error:?}"
        );

        let bad_needs = text.replace("\"needs\":[0.4", "\"needs\":[2.4");
        assert!(bad_needs.contains("\"needs\":[2.4"));
        let error = from_bytes(bad_needs.as_bytes()).expect_err("needs must be in 0..=1");
        assert!(
            matches!(error, SaveError::Invalid(_)),
            "invalid needs are Invalid, got: {error:?}"
        );

        let empty_identity =
            text.replace("\"tool_identity\":\"world-revision-A\"", "\"tool_identity\":\"\"");
        let error = from_bytes(empty_identity.as_bytes()).expect_err("identity may not be empty");
        assert!(
            matches!(error, SaveError::Invalid(ref message) if message.contains("identity")),
            "the refusal names the identity, got: {error:?}"
        );
    }

    /// The save carries no renderer/presentation state: the serialized bytes
    /// name no shader global, no presentation or motion phase, no engine —
    /// those are derived again at the edge after load (Phase 2 Step 2).
    #[test]
    fn the_save_carries_no_presentation_state() {
        let text = as_text(&fixture_save()).to_lowercase();
        for forbidden in [
            "grengewald",
            "wind_global",
            "shader",
            "presentation",
            "motion_phase",
            "phase",
            "renderer",
        ] {
            assert!(
                !text.contains(forbidden),
                "the save must not carry presentation state: found '{forbidden}'"
            );
        }
    }

    /// The save's bytes contain no repository path at all: it knows the
    /// caller's path, identities and place ids — never where any tool or
    /// authored world lives.
    #[test]
    fn the_serialized_save_contains_no_repository_path() {
        let text = as_text(&fixture_save());
        for forbidden in ["/home/", "/Users/", "file://", "/tmp/", "\\\\"] {
            assert!(
                !text.contains(forbidden),
                "the save must not embed a path: found '{forbidden}' in {text}"
            );
        }
    }

    /// The bridge revision is implementation evidence, not game state: it is
    /// never serialized into the document (the format has its own version).
    #[test]
    fn the_bridge_revision_is_not_game_state() {
        let text = as_text(&fixture_save());
        assert!(!text.contains("remich-save-v"));
        assert!(!text.contains("bridge"));
    }

    /// The drop report is deterministic: adapting two identical copies
    /// against the same world produces identical reports, drops and order.
    #[test]
    fn drop_report_ordering_is_deterministic() {
        let first = adapt_to_world(fixture_save(), &current_world_changed());
        let second = adapt_to_world(fixture_save(), &current_world_changed());
        assert_eq!(first.1, second.1);
        assert_eq!(first.0, second.0);
        assert_eq!(first.1.describe_drops(), second.1.describe_drops());

        // The ordinary load's report is deterministic too (and empty).
        let first = adapt_to_world(fixture_save(), &current_world_same());
        let second = adapt_to_world(fixture_save(), &current_world_same());
        assert_eq!(first.1, second.1);
        assert!(first.1.drops.is_empty());
    }

    /// A changed identity with **no** dangling references keeps every drop
    /// empty: identity changes are adaptation markers, not removals.
    #[test]
    fn an_identity_change_alone_drops_nothing() {
        let world = CurrentWorld::new(
            "world-revision-C",
            [
                "north-hills",
                "east-field",
                "market-square",
                "cottage-loft",
                "ridge",
                "kitchen",
            ],
        );
        let (loaded, report) = adapt_to_world(fixture_save(), &world);
        assert!(report.identity_changed);
        assert!(report.drops.is_empty());
        assert_eq!(
            loaded.inhabitant.current_place.as_deref(),
            Some("market-square"),
            "the place still resolves, so it stays"
        );
    }
}
