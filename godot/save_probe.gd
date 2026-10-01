extends Node

## Phase 2, step 3 save proof (docs/PLAN.md, phase 2, step 3: "the game's
## save").
##
## Runs last in the autoload chain, so a save failure cannot be masked by an
## earlier probe's successful `quit(0)` — Godot honours the **last** `quit()`
## it sees, and this probe defers behind every other one. Inside pinned
## Godot it proves the whole Step 3 path, end to end, in **four separate
## processes** (one `REMICH_SAVE_MODE` per invocation, each a fresh engine
## process started by `tools/run_save.sh`):
##
##   * `baseline` — initialize the fixture, run the day through the noon
##     boundary, continue uninterrupted to tick 240, and write only the
##     second-half continuation trace;
##   * `save` — initialize the identical fixture, run to noon, write the
##     actual game save file at the documented boundary, exit;
##   * `load` — fresh process: read that save, same identity and place set,
##     verify zero drops, restore the ONE shared clock and weather node,
##     resume the scorer, continue to 240, write the same-shaped
##     continuation trace — byte-identical to the baseline's, and with the
##     save file's bytes untouched (re-read and compared in-process);
##   * `adapt` — fresh process: load the same save against another identity
##     whose valid-place set omits `market-square`; the load succeeds,
##     keeps every fitting state element, drops exactly the dangling place
##     reference, prints it by name, and never rewrites the save.
##
## The noon boundary (documented in `docs/remich-save-phase2-step3.md`):
## the simulation processes through tick **119**, so the shared clock then
## points at the next tick **120**, the latest weather snapshot is tick
## **119**, and the inhabitant's needs are exactly the state ready for the
## decision at tick 120. The save is written there.
##
## What this probe never does: it holds no tick counter, no second clock, no
## weather copy and no engine delta; it never instantiates the native clock
## or weather class (the autoloads own those, once each); it writes only the
## trace path and — in `save` mode only — the save path it was given.
##
## Failure prints `REMICH_SAVE_FAIL reason=...` and exits non-zero.

const SAVE_CLASS := "RemichGameSave"
const SCORER_CLASS := "RemichScorer"
const CLOCK_CLASS := "RemichWorldClock"
const WEATHER_CLASS := "RemichWeather"
const EXPECTATION_FILE := "res://save_probe_expectation.txt"

const MODE_ENV := "REMICH_SAVE_MODE"
const FILE_ENV := "REMICH_SAVE_FILE"
const TRACE_ENV := "REMICH_SAVE_TRACE"

const OK_MARKER := "REMICH_SAVE_OK"
const ADAPT_MARKER := "REMICH_SAVE_ADAPT_OK"
const ADAPT_KEEP_MARKER := "REMICH_SAVE_ADAPT_KEEP"
const WRITTEN_MARKER := "REMICH_SAVE_WRITTEN"
const BASELINE_MARKER := "REMICH_SAVE_BASELINE_OK"
const FAIL_MARKER := "REMICH_SAVE_FAIL"

const REQUIRED_SAVE_CALLABLES: Array[String] = [
	"save_bridge_rev", "write_save", "load_save",
]
const SCORER_CALLABLES := ["score_activity", "advance_time", "scorer_bridge_rev"]

## The one stand-in driver's writer identity (`remich_core::weather`).
const STAND_IN_WRITER := "stand-in-weather-schedule"

const TRACE_FORMAT := "remich-save-continuation-v1"

# --- the fixed committed fixture (the same day as the Step 5 harness) --------
const SEED := 60628
const INITIAL_NEEDS := [0.40, 0.35, 0.60, 0.50, 0.45, 0.42, 0.55]
const SKILLS := []
const SETTLEMENT_DAMAGE := 0.0
const SETTLEMENT_AGGREGATE_MOOD := 0.0
const ACTIVITIES := [
	{"id": 2, "place": "north-hills"},
	{"id": 1, "place": "east-field"},
	{"id": 16, "place": "market-square"},
	{"id": 14, "place": "cottage-loft"},
	{"id": 12, "place": "ridge"},
	{"id": 5, "place": "kitchen"},
]
const NEED_ORDER_NAMES := [
	"food", "water", "shelter", "safety", "sleep", "companionship", "joy",
]
const TICKS_PER_CHECKPOINT := 10
const FINAL_TICK := 240
const TEST_CYCLE_LENGTH := 240

## The noon boundary: the save is written once the simulation has processed
## through tick 119 (clock next tick 120, latest snapshot 119, needs ready
## for the decision at 120).
const NOON_TICK := 120

## The fixture's tool identities: the save is written against A and the
## changed-world load supplies B. Plain strings; nothing resolves them.
const SAVED_IDENTITY := "world-revision-A"
const CHANGED_IDENTITY := "world-revision-B"

## The six already-qualified test places; the changed world omits exactly
## the one the inhabitant referred to.
const VALID_PLACES := [
	"north-hills", "east-field", "market-square", "cottage-loft", "ridge",
	"kitchen",
]
const CHANGED_VALID_PLACES := [
	"north-hills", "east-field", "cottage-loft", "ridge", "kitchen",
]

const INHABITANT_ID := "standin-inhabitant-1"
const CURRENT_PLACE := "market-square"

## Tolerance for comparing the saved f32 needs against the document's
## f32-shortest decimal text (both sides originate from the same f32; the
## engine-free tests compare the f32 bits exactly).
const NEEDS_TOLERANCE := 0.000001
## Tolerance for the snapshot's f64 fields read back from the document's
## shortest-round-trip text.
const SNAPSHOT_TOLERANCE := 0.000000000001
## Tolerance for re-deriving the presentation phase after restore (32-bit W).
const PHASE_TOLERANCE := 0.0001

var _mode := ""
var _save_path := ""
var _trace_path := ""
var _save_surface: Object = null
## The engine-observed save revision (never a typed-in constant: a stale
## library must fail the staging check, not pass it).
var _revision := ""

# The load's (and therefore the continuation's) identity view: the fixture
# constants for baseline/save, the loaded values for load mode.
var _identity := SAVED_IDENTITY
var _inhabitant_seed := SEED
var _current_place := CURRENT_PLACE


func _ready() -> void:
	_mode = OS.get_environment(MODE_ENV)
	if _mode.is_empty():
		# Every ordinary run — day, clock, weather, bridge — never asks for
		# the save proof: this autoload does not exist for them.
		return
	_save_path = OS.get_environment(FILE_ENV)
	_trace_path = OS.get_environment(TRACE_ENV)
	call_deferred("_run")


func _run() -> void:
	# --- 1. the save surface is a real registered class ----------------------
	if not ClassDB.class_exists(SAVE_CLASS):
		_fail("extension-not-loaded", SAVE_CLASS + " is not registered in ClassDB")
		return
	for method_name in REQUIRED_SAVE_CALLABLES:
		if not ClassDB.class_has_method(SAVE_CLASS, method_name):
			_fail("callable-missing", SAVE_CLASS + "." + method_name + " does not exist")
			return

	var expected := _read_expectation()
	if expected.is_empty():
		_fail("not-staged", "could not read " + EXPECTATION_FILE + " (run tools/stage_save.sh)")
		return
	var surface: Object = ClassDB.instantiate(SAVE_CLASS)
	if surface == null:
		_fail("instantiate-failed", "ClassDB could not instantiate " + SAVE_CLASS)
		return
	_save_surface = surface
	_revision = str(surface.call("save_bridge_rev"))
	if _revision != expected:
		_fail("rev-mismatch", "the engine observed " + _revision + " but the Rust source expects " + expected)
		return

	# --- 2. the shared authorities, one instance each ------------------------
	if not WorldClock.is_ready():
		_fail("clock-missing", "the WorldClock autoload holds no initialized clock")
		return
	if not Weather.is_ready():
		_fail("shared-missing", "the Weather autoload holds no initialized weather")
		return
	if _count_native(CLOCK_CLASS) != 1:
		_fail("second-clock", "%d %s objects are in the scene tree, expected exactly 1" % [
			_count_native(CLOCK_CLASS), CLOCK_CLASS])
		return
	if _count_native(WEATHER_CLASS) != 1:
		_fail("second-weather", "%d %s objects are in the scene tree, expected exactly 1" % [
			_count_native(WEATHER_CLASS), WEATHER_CLASS])
		return

	match _mode:
		"baseline", "save":
			_run_day_mode()
		"load":
			_run_load_mode()
		"adapt":
			_run_adapt_mode()
		_:
			_fail("bad-mode", "unknown %s: %s" % [MODE_ENV, _mode])


# --- baseline / save: the first half of the day, identically -----------------


func _run_day_mode() -> void:
	for step: Array in [
		["reset", WorldClock.reset(0)],
		["set_speed", WorldClock.set_speed(1)],
		["resume", WorldClock.resume()],
	]:
		if not bool(step[1].get("ok", false)):
			_fail("clock-setup", "%s: %s" % [step[0], str(step[1].get("error"))])
			return
	if WorldClock.tick() != 0:
		_fail("clock-start", "the shared clock starts at %d, expected tick 0" % WorldClock.tick())
		return

	_identity = SAVED_IDENTITY
	_inhabitant_seed = SEED
	_current_place = CURRENT_PLACE

	var scorer := _open_scorer()
	if scorer == null:
		return

	var drive := _drive_day(scorer, INITIAL_NEEDS.duplicate(), _mode == "save")
	if drive.is_empty():
		scorer.free()
		return
	var records: Array = drive["records"]
	var final_needs: Array = drive["final_needs"]
	var decisions_total := int(drive["decisions_total"])
	var last_decision := int(drive["last_decision_tick"])

	if _mode == "save":
		# --- the noon boundary, asserted exactly ---------------------------
		if WorldClock.tick() != NOON_TICK:
			_fail("noon-boundary", "the shared clock is at %d after tick %d, expected next tick %d" % [
				WorldClock.tick(), NOON_TICK - 1, NOON_TICK])
			scorer.free()
			return
		var snapshot: Dictionary = Weather.snapshot()
		if int(snapshot.get("tick", -1)) != NOON_TICK - 1:
			_fail("noon-weather", "the latest snapshot is tick %d, expected %d" % [
				int(snapshot.get("tick", -1)), NOON_TICK - 1])
			scorer.free()
			return
		if decisions_total != NOON_TICK / TICKS_PER_CHECKPOINT or last_decision != NOON_TICK - TICKS_PER_CHECKPOINT:
			_fail("noon-decisions", "the first half produced %d decisions (last at tick %d), expected %d (last at %d)" % [
				decisions_total, last_decision, NOON_TICK / TICKS_PER_CHECKPOINT,
				NOON_TICK - TICKS_PER_CHECKPOINT])
			scorer.free()
			return
		if not records.is_empty():
			_fail("noon-records", "the first half must not have written continuation records")
			scorer.free()
			return

		var write: Dictionary = _save_surface.call(
			"write_save", _save_path, _identity,
			WorldClock.capture_state(), _weather_state(),
			_inhabitant_state(final_needs))
		if not bool(write.get("ok", false)):
			_fail("write-refused", "%s: %s" % [
				str(write.get("code", "?")), str(write.get("error", ""))])
			scorer.free()
			return
		print("%s tick=%d identity=%s bytes=%d rev=%s" % [
			WRITTEN_MARKER, NOON_TICK, _identity, int(write.get("bytes", -1)),
			str(write.get("bridge_rev", ""))])
		scorer.free()
		_quit(0)
		return

	# --- baseline: the uninterrupted second half --------------------------
	if decisions_total != FINAL_TICK / TICKS_PER_CHECKPOINT or last_decision != FINAL_TICK - TICKS_PER_CHECKPOINT:
		_fail("decisions", "the day produced %d decisions (last at tick %d)" % [
			decisions_total, last_decision])
		scorer.free()
		return
	if records.size() != (FINAL_TICK - NOON_TICK) / TICKS_PER_CHECKPOINT:
		_fail("records", "%d continuation records, expected %d" % [
			records.size(), (FINAL_TICK - NOON_TICK) / TICKS_PER_CHECKPOINT])
		scorer.free()
		return
	var final_tick := WorldClock.tick()
	if final_tick != FINAL_TICK:
		_fail("final-tick", "the shared clock ended at tick %d, expected %d" % [
			final_tick, FINAL_TICK])
		scorer.free()
		return

	var lines: Array[String] = [_fixture_record_line()]
	for record in records:
		lines.append(JSON.stringify(record, "", true))
	lines.append(_summary_line(records, final_needs, final_tick))
	scorer.free()
	if not _write_trace(lines):
		return
	print("%s mode=baseline records=%d final_tick=%d identity=%s rev=%s" % [
		BASELINE_MARKER, records.size(), final_tick, _identity, _revision])
	_quit(0)


# --- load: restore the shared state and continue -----------------------------


func _run_load_mode() -> void:
	if not FileAccess.file_exists(_save_path):
		_fail("save-missing", "no save at " + _save_path)
		return
	var raw_before := FileAccess.get_file_as_string(_save_path)

	var loaded: Dictionary = _save_surface.call(
		"load_save", _save_path, SAVED_IDENTITY, VALID_PLACES)
	if not bool(loaded.get("ok", false)):
		_fail("load-refused", "%s: %s" % [
			str(loaded.get("code", "?")), str(loaded.get("error", ""))])
		return
	if bool(loaded.get("identity_changed", true)):
		_fail("identity-changed", "the same identity was supplied, yet the load reports a change")
		return
	var drops: Array = loaded.get("drops", [])
	if drops.size() != 0:
		_fail("unexpected-drops", "an ordinary load dropped: %s" % [str(drops)])
		return

	_identity = str(loaded.get("saved_identity", ""))
	var inhabitant: Dictionary = loaded.get("inhabitant", {})
	if str(inhabitant.get("id", "")) != INHABITANT_ID:
		_fail("inhabitant-id", "the loaded inhabitant is '%s', expected '%s'" % [
			str(inhabitant.get("id", "")), INHABITANT_ID])
		return
	_inhabitant_seed = int(inhabitant.get("seed", -1))
	if _inhabitant_seed < 0:
		_fail("inhabitant-seed", "the loaded inhabitant has no seed")
		return
	var needs: Variant = inhabitant.get("needs")
	if typeof(needs) != TYPE_ARRAY or needs.size() != NEED_ORDER_NAMES.size():
		_fail("inhabitant-needs", "the loaded inhabitant's needs are malformed")
		return
	_current_place = str(inhabitant.get("current_place", ""))
	if _current_place != CURRENT_PLACE:
		_fail("current-place", "the loaded current place is '%s', expected '%s' in an ordinary load" % [
			_current_place, CURRENT_PLACE])
		return

	# Loading is read-only with respect to the save: the bytes are identical
	# after the read, the parse and the adaptation.
	var raw_after := FileAccess.get_file_as_string(_save_path)
	if raw_after != raw_before:
		_fail("save-rewritten", "the load changed the save file's bytes")
		return

	# --- restore the ONE shared clock and the ONE shared weather node -------
	var clock_before := WorldClock.clock_instance_id()
	var weather_before := Weather.weather_instance_id()

	var restored_clock: Dictionary = WorldClock.restore_state(loaded.get("clock", {}))
	if not bool(restored_clock.get("ok", false)):
		_fail("clock-restore", "%s: %s" % [
			str(restored_clock.get("code", "?")), str(restored_clock.get("error", ""))])
		return
	if WorldClock.tick() != NOON_TICK:
		_fail("clock-tick", "the restored clock is at %d, expected the save point %d" % [
			WorldClock.tick(), NOON_TICK])
		return
	var saved_clock: Dictionary = loaded.get("clock", {})
	if WorldClock.tick_length_ns() != int(saved_clock.get("tick_length_ns", -1)) \
			or WorldClock.speed() != int(saved_clock.get("speed", -1)) \
			or WorldClock.is_paused() != bool(saved_clock.get("paused", true)):
		_fail("clock-state", "the restored clock does not match the saved state")
		return

	var restored_weather: Dictionary = Weather.restore_save_state(loaded.get("weather", {}))
	if not bool(restored_weather.get("ok", false)):
		_fail("weather-restore", "%s: %s" % [
			str(restored_weather.get("code", "?")), str(restored_weather.get("error", ""))])
		return
	if int(Weather.snapshot().get("tick", -1)) != NOON_TICK - 1:
		_fail("weather-tick", "the restored snapshot is tick %d, expected %d" % [
			int(Weather.snapshot().get("tick", -1)), NOON_TICK - 1])
		return
	if Weather.writer_id() != STAND_IN_WRITER:
		_fail("writer", "after restore the channel belongs to '%s', expected '%s'" % [
			Weather.writer_id(), STAND_IN_WRITER])
		return

	# The presentation phase was NOT restored: W is derived again from the
	# restored integer tick and cycle, exactly as Step 2 defines.
	var applied: Dictionary = Weather.apply_wind()
	if not bool(applied.get("ok", false)) or int(applied.get("tick", -1)) != NOON_TICK - 1:
		_fail("wind-apply", "the wind write did not use the restored snapshot")
		return
	var vector: Array = Weather.last_applied_wind()
	if vector.size() != 4:
		_fail("wind-vector", "the applied wind vector has %d components" % vector.size())
		return
	var cycle := Weather.cycle_length()
	var expected_phase := float((NOON_TICK - 1) % cycle) / float(cycle) * TAU
	if absf(float(vector[3]) - expected_phase) > PHASE_TOLERANCE:
		_fail("wind-w", "W is %s, expected the phase derived from restored tick %d (%s)" % [
			str(vector[3]), NOON_TICK - 1, str(expected_phase)])
		return

	if WorldClock.clock_instance_id() != clock_before:
		_fail("clock-replaced", "restore swapped the shared clock object")
		return
	if Weather.weather_instance_id() != weather_before:
		_fail("weather-replaced", "restore swapped the shared weather object")
		return
	if _count_native(CLOCK_CLASS) != 1 or _count_native(WEATHER_CLASS) != 1:
		_fail("second-authority", "a second clock or weather object appeared during restore")
		return

	# --- continue the day from the restored noon state ---------------------
	var scorer := _open_scorer()
	if scorer == null:
		return
	var drive := _drive_day(scorer, (needs as Array).duplicate(), false)
	if drive.is_empty():
		scorer.free()
		return
	var records: Array = drive["records"]
	var final_needs: Array = drive["final_needs"]
	if records.size() != (FINAL_TICK - NOON_TICK) / TICKS_PER_CHECKPOINT \
			or int(drive["decisions_total"]) != (FINAL_TICK - NOON_TICK) / TICKS_PER_CHECKPOINT \
			or int(drive["last_decision_tick"]) != FINAL_TICK - TICKS_PER_CHECKPOINT:
		_fail("continuation", "the loaded day produced %d continuation records (last decision %d)" % [
			records.size(), int(drive["last_decision_tick"])])
		scorer.free()
		return
	if WorldClock.tick() != FINAL_TICK:
		_fail("final-tick", "the loaded day ended at tick %d, expected %d" % [
			WorldClock.tick(), FINAL_TICK])
		scorer.free()
		return

	var lines: Array[String] = [_fixture_record_line()]
	for record in records:
		lines.append(JSON.stringify(record, "", true))
	lines.append(_summary_line(records, final_needs, FINAL_TICK))
	scorer.free()
	if not _write_trace(lines):
		return
	print("%s tick=%d identity=%s drops=0 rev=%s" % [
		OK_MARKER, NOON_TICK, _identity, _revision])
	_quit(0)


# --- adapt: the changed world keeps what fits and names what it dropped ------


func _run_adapt_mode() -> void:
	if not FileAccess.file_exists(_save_path):
		_fail("save-missing", "no save at " + _save_path)
		return
	var raw_before := FileAccess.get_file_as_string(_save_path)
	var parsed: Variant = JSON.parse_string(raw_before)
	if typeof(parsed) != TYPE_DICTIONARY:
		_fail("save-parse", "the save file is not a JSON object")
		return
	var raw: Dictionary = parsed
	for key in ["clock", "weather", "inhabitant"]:
		if typeof(raw.get(key)) != TYPE_DICTIONARY:
			_fail("save-parse", "the save's %s is not a JSON object" % key)
			return
	var raw_clock: Dictionary = raw.get("clock")
	var raw_weather: Dictionary = raw.get("weather")
	var raw_inhabitant: Dictionary = raw.get("inhabitant")
	if typeof(raw_weather.get("snapshot")) != TYPE_DICTIONARY:
		_fail("save-parse", "the save's weather snapshot is not a JSON object")
		return
	var raw_snapshot: Dictionary = raw_weather.get("snapshot")

	var loaded: Dictionary = _save_surface.call(
		"load_save", _save_path, CHANGED_IDENTITY, CHANGED_VALID_PLACES)
	if not bool(loaded.get("ok", false)):
		_fail("load-refused", "%s: %s" % [
			str(loaded.get("code", "?")), str(loaded.get("error", ""))])
		return
	if not bool(loaded.get("identity_changed", false)):
		_fail("expected-adaptation", "the identity differs, yet the load reports no change")
		return
	var drops: Array = loaded.get("drops", [])
	if drops.size() != 1:
		_fail("drop-count", "%d drops, expected exactly 1" % drops.size())
		return
	var drop: Dictionary = drops[0]
	var expected_drop := {
		"subject": INHABITANT_ID,
		"field": "current_place",
		"value": CURRENT_PLACE,
		"reason": "missing-place",
	}
	for key in ["subject", "field", "value", "reason"]:
		if str(drop.get(key, "")) != str(expected_drop[key]):
			_fail("drop-record", "drop %s is '%s', expected '%s'" % [
				key, str(drop.get(key, "")), str(expected_drop[key])])
			return

	# --- everything that fits is retained, verified against the save itself -
	var inhabitant: Dictionary = loaded.get("inhabitant", {})
	if str(inhabitant.get("id", "")) != str(raw_inhabitant.get("id", "")) \
			or str(inhabitant.get("id", "")) != INHABITANT_ID:
		_fail("id-changed", "the inhabitant id did not survive adaptation")
		return
	if int(inhabitant.get("seed", -1)) != int(raw_inhabitant.get("seed", -2)):
		_fail("seed-changed", "the inhabitant seed did not survive adaptation")
		return
	var needs: Variant = inhabitant.get("needs")
	var raw_needs: Variant = raw_inhabitant.get("needs")
	if typeof(needs) != TYPE_ARRAY or typeof(raw_needs) != TYPE_ARRAY \
			or needs.size() != NEED_ORDER_NAMES.size() \
			or raw_needs.size() != NEED_ORDER_NAMES.size():
		_fail("needs-shape", "the seven needs did not survive adaptation")
		return
	for index in NEED_ORDER_NAMES.size():
		if absf(float(needs[index]) - float(raw_needs[index])) > NEEDS_TOLERANCE:
			_fail("needs-changed", "need %d is %s, the save holds %s" % [
				index, str(needs[index]), str(raw_needs[index])])
			return
	if inhabitant.has("current_place"):
		_fail("place-kept", "the dangling place reference survived: %s" % [
			str(inhabitant.get("current_place"))])
		return

	var loaded_clock: Dictionary = loaded.get("clock", {})
	for key in ["tick", "tick_length_ns", "speed", "paused"]:
		if not loaded_clock.has(key) or not raw_clock.has(key):
			_fail("clock-changed", "clock %s is missing from the load or from the save" % key)
			return
		var after: Variant = loaded_clock.get(key)
		var before: Variant = raw_clock.get(key)
		if key == "paused":
			if bool(after) != bool(before):
				_fail("clock-changed", "clock %s did not survive adaptation" % key)
				return
		elif int(after) != int(before):
			_fail("clock-changed", "clock %s did not survive adaptation" % key)
			return

	var loaded_weather: Dictionary = loaded.get("weather", {})
	if not loaded_weather.has("seed") or not raw_weather.has("seed") \
			or not loaded_weather.has("cycle_length") or not raw_weather.has("cycle_length") \
			or not loaded_weather.has("snapshot"):
		_fail("weather-config", "the driver configuration is missing from the load or the save")
		return
	if int(loaded_weather.get("seed", -1)) != int(raw_weather.get("seed", -2)) \
			or int(loaded_weather.get("cycle_length", -1)) != int(raw_weather.get("cycle_length", -2)):
		_fail("weather-config", "the driver configuration did not survive adaptation")
		return
	var loaded_snapshot: Dictionary = loaded_weather.get("snapshot")
	for key in ["tick"]:
		if not loaded_snapshot.has(key) or not raw_snapshot.has(key):
			_fail("weather-changed", "snapshot %s is missing from the load or the save" % key)
			return
		if int(loaded_snapshot.get(key, -1)) != int(raw_snapshot.get(key, -2)):
			_fail("weather-changed", "snapshot %s did not survive adaptation" % key)
			return
	for key in ["wind_dir_x", "wind_dir_z", "wind_strength", "rain", "temperature", "light"]:
		if not loaded_snapshot.has(key) or not raw_snapshot.has(key):
			_fail("weather-changed", "snapshot %s is missing from the load or the save" % key)
			return
		if absf(float(loaded_snapshot.get(key)) - float(raw_snapshot.get(key))) > SNAPSHOT_TOLERANCE:
			_fail("weather-changed", "snapshot %s did not survive adaptation" % key)
			return

	# --- the fitting clock and weather are restored into the shared nodes ----
	var clock_before := WorldClock.clock_instance_id()
	var weather_before := Weather.weather_instance_id()
	var restored_clock: Dictionary = WorldClock.restore_state(loaded_clock)
	if not bool(restored_clock.get("ok", false)) or WorldClock.tick() != NOON_TICK:
		_fail("clock-restore", "the fitting clock state could not be restored: %s" % [
			str(restored_clock.get("error", ""))])
		return
	var restored_weather: Dictionary = Weather.restore_save_state(loaded_weather)
	if not bool(restored_weather.get("ok", false)) \
			or int(Weather.snapshot().get("tick", -1)) != NOON_TICK - 1:
		_fail("weather-restore", "the fitting weather state could not be restored: %s" % [
			str(restored_weather.get("error", ""))])
		return
	if Weather.writer_id() != STAND_IN_WRITER:
		_fail("writer", "after adaptation-restore the channel belongs to '%s'" % Weather.writer_id())
		return
	if WorldClock.clock_instance_id() != clock_before \
			or Weather.weather_instance_id() != weather_before \
			or _count_native(CLOCK_CLASS) != 1 \
			or _count_native(WEATHER_CLASS) != 1:
		_fail("second-authority", "adaptation-restore replaced or duplicated a shared authority")
		return

	# --- the save file's bytes are untouched by the adapted load ------------
	var raw_after := FileAccess.get_file_as_string(_save_path)
	if raw_after != raw_before:
		_fail("save-rewritten", "the adapted load changed the save file's bytes")
		return

	print("%s id=%s seed=%d needs=%d place=absent clock=tick:%d weather:snapshot:%d" % [
		ADAPT_KEEP_MARKER, str(inhabitant.get("id", "")),
		int(inhabitant.get("seed", -1)), needs.size(),
		WorldClock.tick(), int(Weather.snapshot().get("tick", -1))])
	print("%s saved_identity=%s current_identity=%s drops=1 dropped=%s.%s:%s rev=%s" % [
		ADAPT_MARKER,
		str(loaded.get("saved_identity", "")),
		str(loaded.get("current_identity", "")),
		str(drop.get("subject", "")), str(drop.get("field", "")),
		str(drop.get("value", "")), _revision])
	_quit(0)


# --- the day loop, shared by every mode that runs it -------------------------


## Drives the ONE shared clock from wherever it points, tick by tick:
## stand-in weather for every tick, a scorer decision on every 10th tick,
## continuation records for every decision at or after noon. With
## `stop_at_noon` it returns right after processing tick 119 — the save
## point — leaving the clock pointing at 120. Returns `{}` after `_fail()`.
func _drive_day(scorer: Object, start_needs: Array, stop_at_noon: bool) -> Dictionary:
	var needs := start_needs.duplicate()
	var place := _current_place
	var revision := str(scorer.call("scorer_bridge_rev"))
	var records: Array = []
	var decisions_total := 0
	var last_decision_tick := -1

	while WorldClock.tick() < FINAL_TICK:
		var batch: Array = WorldClock.pulse()
		if batch.is_empty():
			_fail("clock-stalled", "the shared clock is at %d and emitted nothing" % WorldClock.tick())
			return {}
		for tick_variant in batch:
			var tick := int(tick_variant)

			# The weather is driven from this integer tick — the same clock,
			# the same tick the decision logic sees.
			var driven: Dictionary = Weather.drive(tick)
			if not bool(driven.get("ok", false)):
				_fail("drive-refused", str(driven.get("error", "")))
				return {}
			var snapshot: Dictionary = Weather.snapshot()
			if not bool(snapshot.get("ok", false)) or int(snapshot.get("tick", -1)) != tick:
				_fail("snapshot-tick", "the snapshot for tick %d reads back as %s" % [
					tick, str(snapshot.get("tick"))])
				return {}

			if tick % TICKS_PER_CHECKPOINT == 0 and tick < FINAL_TICK:
				var checkpoint := tick / TICKS_PER_CHECKPOINT
				var time_of_day := WorldClock.cycle_position(tick, TEST_CYCLE_LENGTH)
				if time_of_day < 0.0:
					_fail("cycle-position", "the shared clock refused a cycle position at tick %d" % tick)
					return {}

				var scored: Variant = scorer.call("score_activity", _score_input(needs, time_of_day))
				if typeof(scored) != TYPE_DICTIONARY:
					_fail("wrong-type", "score_activity returned %s at checkpoint %d" % [
						type_string(typeof(scored)), checkpoint])
					return {}
				var result: Dictionary = scored
				if not bool(result.get("ok", false)):
					_fail("score-refused", "checkpoint %d: %s" % [checkpoint, str(result.get("error"))])
					return {}
				if str(result.get("bridge_rev", "")) != revision:
					_fail("rev-mixed", "checkpoint %d reported %s, the day started on %s" % [
						checkpoint, str(result.get("bridge_rev")), revision])
					return {}
				var candidates: Variant = result.get("candidates")
				if typeof(candidates) != TYPE_ARRAY or candidates.size() != ACTIVITIES.size():
					_fail("candidates", "checkpoint %d returned no candidate list of the fixture's size" % checkpoint)
					return {}
				var chosen_id := int(result.get("chosen_id", -1))
				if chosen_id < 0:
					_fail("chosen", "checkpoint %d returned no chosen id" % checkpoint)
					return {}
				var chosen := {
					"id": chosen_id,
					"name": str(result.get("chosen_name", "")),
					"place": str(result.get("chosen_place", "")),
					"score": float(result.get("chosen_score", 0.0)),
				}

				var advanced: Variant = scorer.call(
					"advance_time", needs, tick, tick + TICKS_PER_CHECKPOINT)
				if typeof(advanced) != TYPE_DICTIONARY or not bool(advanced.get("ok", false)):
					var detail := type_string(typeof(advanced))
					if typeof(advanced) == TYPE_DICTIONARY:
						detail = str(advanced.get("error"))
					_fail("advance-refused", "checkpoint %d: %s" % [checkpoint, detail])
					return {}
				var next_needs: Variant = advanced.get("needs")
				if typeof(next_needs) != TYPE_ARRAY or next_needs.size() != NEED_ORDER_NAMES.size():
					_fail("advance-needs", "checkpoint %d returned a malformed needs array" % checkpoint)
					return {}

				decisions_total += 1
				last_decision_tick = tick
				if tick >= NOON_TICK:
					var record := {
						"type": "decision",
						"checkpoint": checkpoint,
						"tick": tick,
						"time_of_day": time_of_day,
						"seed": _inhabitant_seed,
						"needs": needs.duplicate(),
						"bridge_rev": revision,
						"chosen": chosen,
						"candidates": candidates,
						"next_decay_steps": int(advanced.get("decay_steps", -1)),
						"current_place": place,
						"weather": {
							"tick": tick,
							"wind_dir_x": float(snapshot.get("wind_dir_x")),
							"wind_dir_z": float(snapshot.get("wind_dir_z")),
							"wind_strength": float(snapshot.get("wind_strength")),
							"rain": float(snapshot.get("rain")),
							"temperature": float(snapshot.get("temperature")),
							"light": float(snapshot.get("light")),
						},
					}
					records.append(record)
				needs = (next_needs as Array).duplicate()

			if stop_at_noon and tick == NOON_TICK - 1:
				return {
					"records": records,
					"decisions_total": decisions_total,
					"last_decision_tick": last_decision_tick,
					"final_needs": needs,
					"final_place": place,
				}

	return {
		"records": records,
		"decisions_total": decisions_total,
		"last_decision_tick": last_decision_tick,
		"final_needs": needs,
		"final_place": place,
	}


# --- trace records (byte-identical between baseline and load) ----------------


func _fixture_record_line() -> String:
	return JSON.stringify({
		"type": "fixture",
		"trace_format": TRACE_FORMAT,
		"identity": _identity,
		"inhabitant": INHABITANT_ID,
		"seed": _inhabitant_seed,
		"current_place": _current_place,
		"cycle_length": TEST_CYCLE_LENGTH,
		"noon_tick": NOON_TICK,
		"final_tick": FINAL_TICK,
		"ticks_per_checkpoint": TICKS_PER_CHECKPOINT,
		"need_order": NEED_ORDER_NAMES,
		"activities": ACTIVITIES,
	}, "", true)


func _summary_line(records: Array, final_needs: Array, final_tick: int) -> String:
	var chosen_ids: Array = []
	for record in records:
		chosen_ids.append(int(record["chosen"]["id"]))
	var distinct: Array = []
	for chosen_id in chosen_ids:
		if not distinct.has(chosen_id):
			distinct.append(chosen_id)
	distinct.sort()
	var snapshot: Dictionary = Weather.snapshot()
	return JSON.stringify({
		"type": "summary",
		"trace_format": TRACE_FORMAT,
		"identity": _identity,
		"inhabitant": INHABITANT_ID,
		"checkpoints": records.size(),
		"final_tick": final_tick,
		"final_needs": final_needs.duplicate(),
		"final_weather": {
			"tick": int(snapshot.get("tick", -1)),
			"wind_dir_x": float(snapshot.get("wind_dir_x")),
			"wind_dir_z": float(snapshot.get("wind_dir_z")),
			"wind_strength": float(snapshot.get("wind_strength")),
			"rain": float(snapshot.get("rain")),
			"temperature": float(snapshot.get("temperature")),
			"light": float(snapshot.get("light")),
		},
		"final_clock": {
			"tick": WorldClock.tick(),
			"speed": WorldClock.speed(),
			"paused": WorldClock.is_paused(),
		},
		"chosen_ids": chosen_ids,
		"distinct_count": distinct.size(),
		"need_order": NEED_ORDER_NAMES,
	}, "", true)


# --- inputs ------------------------------------------------------------------


func _score_input(needs: Array, time_of_day: float) -> Dictionary:
	return {
		"seed": _inhabitant_seed,
		"needs": needs.duplicate(),
		"time_of_day": time_of_day,
		"activities": ACTIVITIES.duplicate(true),
		"skills": SKILLS.duplicate(),
		"settlement_damage": SETTLEMENT_DAMAGE,
		"settlement_aggregate_mood": SETTLEMENT_AGGREGATE_MOOD,
	}


func _weather_state() -> Dictionary:
	return {
		"seed": Weather.stand_in_seed(),
		"cycle_length": Weather.cycle_length(),
		"snapshot": Weather.snapshot(),
	}


func _inhabitant_state(needs: Array) -> Dictionary:
	return {
		"id": INHABITANT_ID,
		"seed": _inhabitant_seed,
		"needs": needs.duplicate(),
		"current_place": _current_place,
	}


# --- plumbing -----------------------------------------------------------------


## Releases the save surface and exits: the native object is freed so a
## leak warning cannot dress up a clean run.
func _quit(code: int) -> void:
	if _save_surface != null:
		_save_surface.free()
		_save_surface = null
	get_tree().quit(code)


func _open_scorer() -> Object:
	if not ClassDB.class_exists(SCORER_CLASS):
		_fail("extension-not-loaded", SCORER_CLASS + " is not registered in ClassDB")
		return null
	for method_name in SCORER_CALLABLES:
		if not ClassDB.class_has_method(SCORER_CLASS, method_name):
			_fail("callable-missing", SCORER_CLASS + "." + method_name + " does not exist")
			return null
	var scorer: Object = ClassDB.instantiate(SCORER_CLASS)
	if scorer == null:
		_fail("instantiate-failed", "ClassDB could not instantiate " + SCORER_CLASS)
	return scorer


## The number of native objects of one class in the scene tree: each shared
## authority must be the only one.
func _count_native(native_class: String) -> int:
	var count := 0
	var stack: Array[Node] = [get_tree().root]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		if node.get_class() == native_class:
			count += 1
		var children := node.get_children()
		for child in children:
			if child is Node:
				stack.append(child)
	return count


func _write_trace(lines: Array[String]) -> bool:
	var directory := _trace_path.get_base_dir()
	if not directory.is_empty() and not DirAccess.dir_exists_absolute(directory):
		var made := DirAccess.make_dir_recursive_absolute(directory)
		if made != OK:
			_fail("trace-dir", "could not create %s (%s)" % [
				directory, error_string(made)])
			return false
	var file: FileAccess = FileAccess.open(_trace_path, FileAccess.WRITE)
	if file == null:
		_fail("trace-unwritable", "could not open %s for writing (%s)" % [
			_trace_path, error_string(FileAccess.get_open_error())])
		return false
	for line in lines:
		file.store_line(line)
	file.flush()
	file = null
	return true


func _read_expectation() -> String:
	if not FileAccess.file_exists(EXPECTATION_FILE):
		return ""
	var file := FileAccess.open(EXPECTATION_FILE, FileAccess.READ)
	if file == null:
		return ""
	return file.get_as_text().strip_edges()


func _fail(reason: String, detail: String) -> void:
	print(FAIL_MARKER + " reason=" + reason + " detail=" + detail)
	_quit(1)
