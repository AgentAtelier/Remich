extends Node

## The one shared weather node (docs/PLAN.md, phase 2, step 2: "one weather
## snapshot").
##
## This autoload owns exactly ONE instance of the native `RemichWeather`
## GDExtension class: created here once, in `_ready()`, added to the scene
## tree. Every other script — the weather proof, the day harness, later
## consumers — reaches the weather through this node. Nothing else
## instantiates the class.
##
## This script keeps **no** weather state of its own: no wind, no rain, no
## temperature, no light, no tick, no counter. It only delegates each call to
## the single Rust channel behind the extension, so Godot never holds a
## second authoritative copy of anything the snapshot owns. The one-writer
## rule is enforced in Rust (`remich_core::weather::WeatherChannel`); every
## method here is a plain read, a tick-driven publish, or a pass-through of
## the ownership probe — there is no way to set weather values from script.
##
## ## The test project's stand-in fixture — test configuration, not authority
##
## `TEST_SEED` and `TEST_CYCLE_LENGTH` are supplied to the Rust stand-in
## driver at construction and are immutable afterwards (a second
## initialization is refused by the binding). They are the explicit fixture
## configuration of THIS test project — the same 240-tick cycle Phase 2's
## day harness uses — declared in one place so the proof and the record can
## both quote them. They are not a decision about any game's weather, and no
## engine-free core reads them: Eisleck will replace the stand-in driver
## (docs/remich-weather-phase2-step2.md).

const WEATHER_CLASS := "RemichWeather"

## The stand-in fixture's seed for this test project.
const TEST_SEED := 70021

## The stand-in fixture's explicit cycle length, in integer ticks.
const TEST_CYCLE_LENGTH := 240

## The authoritative instance. Never replaced after `_ready()`.
var _weather: Object = null


func _ready() -> void:
	if not ClassDB.class_exists(WEATHER_CLASS):
		# This run has no extension loaded (an ordinary earlier-step run
		# without staging). Stay silent; the probes that need the weather
		# say so themselves.
		return
	var created: Node = ClassDB.instantiate(WEATHER_CLASS) as Node
	if created == null:
		return
	var result: Variant = created.call("initialize", TEST_SEED, TEST_CYCLE_LENGTH)
	if typeof(result) != TYPE_DICTIONARY or not bool(result.get("ok", false)):
		created.free()
		return
	_weather = created
	add_child(created)


## Whether the single native weather node exists and is initialized.
func is_ready() -> bool:
	return _weather != null


## Publishes the stand-in snapshot for the supplied integer world tick
## (obtained from the shared `WorldClock`) and returns it. Delegates; the
## tick drives the weather — weather never drives time.
func drive(tick: int) -> Dictionary:
	return _delegate("drive", [tick])


## The save-restore path (phase 2, step 3): re-publishes a loaded save's
## verified snapshot **through the stand-in driver that owns the channel**,
## with the seed and cycle checked against this run's fixture. Not a weather
## setter: it takes the save's structure, refuses anything else, and leaves
## the one-writer rule exactly as it was — a second writer still cannot
## publish. The presentation phase is not restored; it is derived again from
## the restored integer tick when the wind global is next applied.
func restore_save_state(state: Dictionary) -> Dictionary:
	return _delegate("restore_save_state", [state])


## The latest snapshot, read straight from the Rust channel. `ok=false` with
## code `no-snapshot` before the first publish.
func snapshot() -> Dictionary:
	return _delegate("snapshot", [])


## The channel's writer identity — "" when unavailable.
func writer_id() -> String:
	return str(_weather.call("writer_id")) if _weather != null else ""


## The full ownership status: who owns the channel, whether a snapshot
## exists, and the tick that snapshot applies to.
func writer_status() -> Dictionary:
	return _delegate("writer_status", [])


## Attempts a writer claim as a distinct identity — the engine-side second
## writer probe. Goes through the same channel API, so it cannot bypass the
## one-writer rule; a refusal comes back with `code` = `writer-conflict`.
func try_claim_writer(writer: String) -> Dictionary:
	return _delegate("try_claim_writer", [writer])


## Writes the Grengewald wind global from the current snapshot through the
## engine's real setter and returns the exact vector applied.
func apply_wind() -> Dictionary:
	return _delegate("apply_wind", [])


## The exact vector handed to the setter on the most recent `apply_wind()`:
## four 32-bit-rounded components [X, Y, Z, W]. Empty before the first apply.
func last_applied_wind() -> Array:
	if _weather == null:
		return []
	var applied: Variant = _weather.call("last_applied_wind")
	if typeof(applied) != TYPE_ARRAY:
		return []
	return applied


## The stand-in fixture's seed. -1 when unavailable.
func stand_in_seed() -> int:
	return int(_weather.call("seed")) if _weather != null else -1


## The stand-in fixture's explicit cycle length in integer ticks.
## -1 when unavailable.
func cycle_length() -> int:
	return int(_weather.call("cycle_length")) if _weather != null else -1


## The weather revision this library was built with (stale-library guard).
func bridge_rev() -> String:
	return str(_weather.call("weather_bridge_rev")) if _weather != null else ""


## The instance id of the single native weather node — for proofs that there
## is exactly one object behind every read.
func weather_instance_id() -> int:
	return _weather.get_instance_id() if _weather != null else -1


func _delegate(method: String, args: Array) -> Dictionary:
	if _weather == null:
		return {
			"ok": false,
			"error": "the shared weather node is not available in this run",
		}
	var result: Variant = _weather.callv(method, args)
	if typeof(result) != TYPE_DICTIONARY:
		return {
			"ok": false,
			"error": "%s returned %s" % [method, type_string(typeof(result))],
		}
	return result
