//! The game's save surface (Phase 2, Step 3) — the thin binding's half of
//! `docs/PLAN.md` §4a's "the game's save".
//!
//! The engine-free layer owns everything about the *document*: its
//! structure, deterministic serialization, parsing, validation and
//! adaptation ([`remich_core::save`]). This module owns only the two things
//! that genuinely need the layer above: converting between Godot plain
//! values and those core structs, and actual file access at the caller's
//! **supplied path**.
//!
//! Two invariants are structural here:
//!
//! * **The path is the caller's.** `write_save` and `load_save` receive one
//!   path string and touch nothing else — no repository, no authored world,
//!   no engine data directory. `load_save` reads; only `write_save` writes,
//!   and only the file the caller named.
//! * **Loading never rewrites the save.** `load_save` performs a single
//!   `read` and returns the adapted state as values; it has no write path at
//!   all. Adapting a load changes the loaded game state, not the bytes on
//!   disk — the acceptance hashes the file before and after to prove it.
//!
//! Identity mismatch and a missing place are adaptation inputs handled by
//! the core; they never reach the failure paths below. Malformed bytes, an
//! unsupported format version, structurally invalid state and I/O trouble do.

use godot::prelude::*;

use remich_core::clock::ClockState;
use remich_core::save::{
    adapt_to_world, from_bytes, to_bytes, CurrentWorld, GameSave, InhabitantState, SaveError,
    WeatherState, SAVE_FORMAT_VERSION,
};

use crate::{
    field, need_array, plain_integer, plain_needs, plain_text, snapshot_dictionary,
    snapshot_from_dictionary, SAVE_BRIDGE_REV,
};

/// The Godot-facing game-save class: one node so `ClassDB` can instantiate
/// it, two real file operations, and plain dictionaries in both directions.
/// Every argument and every result is a plain value, an `Array` or a
/// `Dictionary` — no type from any other repository appears here.
#[derive(GodotClass)]
#[class(base = Node)]
pub struct RemichGameSave {
    base: Base<Node>,
}

#[godot_api]
impl INode for RemichGameSave {
    fn init(base: Base<Node>) -> Self {
        Self { base }
    }
}

#[godot_api]
impl RemichGameSave {
    /// The revision marker this library was built with, on its own
    /// (stale-library guard for `godot/save_probe.gd`).
    #[func]
    fn save_bridge_rev(&self) -> GString {
        SAVE_BRIDGE_REV.into()
    }

    /// Builds a save document from plain state, serializes it
    /// deterministically and writes it to the caller's path. The three state
    /// dictionaries come from the shared authorities: the clock's
    /// `capture_state`, the weather's seed/cycle/latest snapshot, and the
    /// stand-in inhabitant's narrow state. The tool identity is copied in
    /// verbatim as a plain string.
    ///
    /// Refuses (without writing anything) if the state is structurally
    /// invalid or the path is unwritable.
    #[func]
    fn write_save(
        &self,
        path: GString,
        tool_identity: GString,
        clock: VarDictionary,
        weather: VarDictionary,
        inhabitant: VarDictionary,
    ) -> VarDictionary {
        let save = match build_save(&tool_identity.to_string(), &clock, &weather, &inhabitant) {
            Ok(save) => save,
            Err(message) => return save_failure("bad-input", &message),
        };
        let bytes = match to_bytes(&save) {
            Ok(bytes) => bytes,
            Err(error) => return save_failure("invalid-save", &error.to_string()),
        };

        let path_string = path.to_string();
        if let Some(parent) = std::path::Path::new(&path_string).parent() {
            if !parent.as_os_str().is_empty() {
                if let Err(error) = std::fs::create_dir_all(parent) {
                    return save_failure("io", &format!("could not create {parent:?}: {error}"));
                }
            }
        }
        if let Err(error) = std::fs::write(&path_string, &bytes) {
            return save_failure("io", &format!("could not write the save: {error}"));
        }

        let mut result = VarDictionary::new();
        result.set("ok", true);
        result.set("bridge_rev", SAVE_BRIDGE_REV);
        result.set("format_version", i64::from(save.format_version));
        result.set("tool_identity", save.tool_identity.as_str());
        result.set("bytes", bytes.len() as i64);
        result
    }

    /// Reads the save at the caller's path, validates it, and adapts it to
    /// the caller's current world (identity + valid place ids) — returning
    /// the kept state, the identity-change flag and every drop by name.
    ///
    /// Read-only with respect to the file. A changed identity or a missing
    /// place **adapts**; malformed bytes, an unsupported format version and
    /// structurally invalid state fail clearly with a specific `code`.
    #[func]
    fn load_save(
        &self,
        path: GString,
        current_identity: GString,
        valid_places: VarArray,
    ) -> VarDictionary {
        let path_string = path.to_string();
        let bytes = match std::fs::read(&path_string) {
            Ok(bytes) => bytes,
            Err(error) => {
                return save_failure("io", &format!("could not read the save: {error}"))
            }
        };
        let parsed = match from_bytes(&bytes) {
            Ok(save) => save,
            Err(error) => return save_failure(save_error_code(&error), &error.to_string()),
        };

        let mut places = Vec::with_capacity(valid_places.len());
        for (index, entry) in valid_places.iter_shared().enumerate() {
            match plain_text(&entry, &format!("valid place at index {index}")) {
                Ok(place) => places.push(place),
                Err(message) => return save_failure("bad-input", &message),
            }
        }
        let world = CurrentWorld::new(current_identity.to_string(), places);
        let (loaded, report) = adapt_to_world(parsed, &world);

        let mut result = VarDictionary::new();
        result.set("ok", true);
        result.set("bridge_rev", SAVE_BRIDGE_REV);
        result.set("format_version", i64::from(loaded.format_version));
        result.set("saved_identity", loaded.tool_identity.as_str());
        result.set("current_identity", world.tool_identity.as_str());
        result.set("identity_changed", report.identity_changed);

        let mut drops = VarArray::new();
        for drop in &report.drops {
            let mut entry = VarDictionary::new();
            entry.set("subject", drop.subject.as_str());
            entry.set("field", drop.field.as_str());
            entry.set("value", drop.value.as_str());
            entry.set("reason", drop.reason.as_str());
            drops.push(&entry);
        }
        result.set("drops", &drops);

        let mut clock = VarDictionary::new();
        clock.set("tick", loaded.clock.tick as i64);
        clock.set("tick_length_ns", loaded.clock.tick_length_ns as i64);
        clock.set("speed", i64::from(loaded.clock.speed));
        clock.set("paused", loaded.clock.paused);
        result.set("clock", &clock);

        let mut weather = VarDictionary::new();
        weather.set("seed", loaded.weather.seed as i64);
        weather.set("cycle_length", loaded.weather.cycle_length as i64);
        weather.set(
            "snapshot",
            &snapshot_dictionary(&loaded.weather.snapshot, loaded.weather.seed as i64),
        );
        result.set("weather", &weather);

        let mut inhabitant = VarDictionary::new();
        inhabitant.set("id", loaded.inhabitant.id.as_str());
        inhabitant.set("seed", loaded.inhabitant.seed as i64);
        inhabitant.set("needs", &need_array(&loaded.inhabitant.needs));
        if let Some(place) = &loaded.inhabitant.current_place {
            // Present only when it resolved; an adapted-out reference is
            // absent, not null-but-there.
            inhabitant.set("current_place", place.as_str());
        }
        result.set("inhabitant", &inhabitant);

        result
    }
}

/// Builds the engine-free document from the plain dictionaries the probe
/// assembled from the shared authorities. Every field is required; nothing
/// is defaulted, and the core validates again on the way to bytes.
fn build_save(
    tool_identity: &str,
    clock: &VarDictionary,
    weather: &VarDictionary,
    inhabitant: &VarDictionary,
) -> Result<GameSave, String> {
    let tick = plain_integer(&field(clock, "tick")?, "clock state tick")?;
    let tick_length_ns =
        plain_integer(&field(clock, "tick_length_ns")?, "clock state tick_length_ns")?;
    let speed = plain_integer(&field(clock, "speed")?, "clock state speed")?;
    if speed > u64::from(u32::MAX) {
        return Err("clock state speed exceeds u32".to_string());
    }
    let paused = field(clock, "paused")?
        .try_to::<bool>()
        .map_err(|_| "clock state paused must be a bool".to_string())?;

    let seed = plain_integer(&field(weather, "seed")?, "weather seed")?;
    let cycle_length = plain_integer(&field(weather, "cycle_length")?, "weather cycle_length")?;
    let snapshot = snapshot_from_dictionary(
        &field(weather, "snapshot")?
            .try_to::<VarDictionary>()
            .map_err(|_| "weather snapshot must be a dictionary".to_string())?,
    )?;

    let id = plain_text(&field(inhabitant, "id")?, "inhabitant id")?;
    let inhabitant_seed = plain_integer(&field(inhabitant, "seed")?, "inhabitant seed")?;
    let needs = plain_needs(
        &field(inhabitant, "needs")?
            .try_to::<VarArray>()
            .map_err(|_| "inhabitant needs must be an array of 7 numbers".to_string())?,
    )?;
    let current_place = match inhabitant.get("current_place") {
        Some(value) if !value.is_nil() => Some(plain_text(&value, "inhabitant current_place")?),
        _ => None,
    };

    Ok(GameSave {
        format_version: SAVE_FORMAT_VERSION,
        tool_identity: tool_identity.to_string(),
        clock: ClockState {
            tick,
            tick_length_ns,
            speed: speed as u32,
            paused,
        },
        weather: WeatherState {
            seed,
            cycle_length,
            snapshot,
        },
        inhabitant: InhabitantState {
            id,
            seed: inhabitant_seed,
            needs,
            current_place,
        },
    })
}

/// The specific failure code for each core save error — the probe's
/// `REMICH_SAVE_FAIL reason=...` carries exactly this.
pub(crate) fn save_error_code(error: &SaveError) -> &'static str {
    match error {
        SaveError::Malformed(_) => "malformed",
        SaveError::UnsupportedVersion { .. } => "unsupported-version",
        SaveError::Invalid(_) => "invalid-save",
        SaveError::Io(_) => "io",
    }
}

/// A refused save request: says why, substitutes nothing.
fn save_failure(code: &str, message: &str) -> VarDictionary {
    godot_error!("RemichGameSave: {code}: {message}");
    let mut result = VarDictionary::new();
    result.set("ok", false);
    result.set("bridge_rev", SAVE_BRIDGE_REV);
    result.set("code", code);
    result.set("error", message);
    result
}

#[cfg(test)]
mod tests {
    use super::*;

    /// Each core save error maps to its own specific probe-facing code —
    /// malformed data is never reported as an I/O problem, and an
    /// unsupported version is never reported as malformed.
    #[test]
    fn every_save_error_gets_its_own_code() {
        assert_eq!(
            save_error_code(&SaveError::Malformed("x".to_string())),
            "malformed"
        );
        assert_eq!(
            save_error_code(&SaveError::UnsupportedVersion {
                found: 2,
                supported: 1
            }),
            "unsupported-version"
        );
        assert_eq!(
            save_error_code(&SaveError::Invalid("x".to_string())),
            "invalid-save"
        );
        assert_eq!(save_error_code(&SaveError::Io("x".to_string())), "io");
    }

    /// The surface writes exactly the format version the engine-free core
    /// declares — one version, declared once, mirrored here.
    #[test]
    fn the_surface_uses_the_cores_format_version() {
        assert_eq!(SAVE_FORMAT_VERSION, remich_core::save::SAVE_FORMAT_VERSION);
        assert_eq!(SAVE_FORMAT_VERSION, 1);
    }
}
