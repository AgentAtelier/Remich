extends Node

## The one shared world-clock node (docs/PLAN.md, phase 2, step 1: "one clock").
##
## This autoload owns exactly ONE instance of the native `RemichWorldClock`
## GDExtension class: created here once, in `_ready()`, added to the scene
## tree. Every other script — the day harness, the clock proof, later cores —
## reaches the clock through this node. Nothing else instantiates the class.
##
## This script holds no tick, no counter and no time of its own: it only
## delegates each call to the single Rust clock. Authoritative state lives in
## `remich_core::clock::WorldClock` behind the extension; a float never
## decides which integer tick exists, and no method here takes a delta.
##
## ## The test project's fixed tick length — test configuration, not authority
##
## `TEST_TICK_LENGTH_NS` (100 ms, in whole nanoseconds) is supplied to the
## Rust clock at construction and is immutable afterwards. It is the explicit
## fixture configuration of THIS test project, declared in one place so the
## proof and the record can both quote it. It is not a decision about any
## game's simulation rate, and no engine-free core reads it: a shipped game
## would supply its own value at construction.

const CLOCK_CLASS := "RemichWorldClock"

## The fixed tick length of this test project's fixture, in whole nanoseconds.
const TEST_TICK_LENGTH_NS := 100000000

## The authoritative instance. Never replaced after `_ready()`.
var _clock: Object = null


func _ready() -> void:
	if not ClassDB.class_exists(CLOCK_CLASS):
		# This run has no extension loaded (an ordinary earlier-step run
		# without staging). Stay silent; the probes that need the clock say
		# so themselves.
		return
	var created: Node = ClassDB.instantiate(CLOCK_CLASS) as Node
	if created == null:
		return
	var result: Variant = created.call("initialize", TEST_TICK_LENGTH_NS)
	if typeof(result) != TYPE_DICTIONARY or not bool(result.get("ok", false)):
		created.free()
		return
	_clock = created
	add_child(created)


## Whether the single native clock exists and is initialized.
func is_ready() -> bool:
	return _clock != null


## The authoritative integer tick. -1 when the clock is unavailable.
func tick() -> int:
	return int(_clock.call("tick")) if _clock != null else -1


## The fixed tick length in whole nanoseconds. -1 when unavailable.
func tick_length_ns() -> int:
	return int(_clock.call("tick_length_ns")) if _clock != null else -1


## The integer speed multiplier. 0 when unavailable.
func speed() -> int:
	return int(_clock.call("speed")) if _clock != null else 0


## Whether the clock is paused (unavailable counts as not running).
func is_paused() -> bool:
	return bool(_clock.call("is_paused")) if _clock != null else true


## Sets the integer speed multiplier (>= 1). Delegates; returns Rust's verdict.
func set_speed(new_speed: int) -> Dictionary:
	return _delegate("set_speed", [new_speed])


## Pauses the clock. Delegates; returns Rust's verdict.
func pause() -> Dictionary:
	return _delegate("pause", [])


## Resumes the clock at exactly the next integer tick. Delegates.
func resume() -> Dictionary:
	return _delegate("resume", [])


## Re-positions the clock at an explicit integer tick (fixture setup).
func reset(new_tick: int) -> Dictionary:
	return _delegate("reset", [new_tick])


## The clock's whole state as plain values — tick, fixed tick length, speed,
## paused — for the game's save (phase 2, step 3). A read, like every other
## method here: this script holds no copy of it.
func capture_state() -> Dictionary:
	return _delegate("capture_state", [])


## Replaces the ONE native clock's whole state from a validated save (phase
## 2, step 3). The native object mutates in place — this autoload's instance
## id never changes, no second clock appears, and Rust refuses a state that
## construction would have refused. The save path's only clock entry point.
func restore_state(state: Dictionary) -> Dictionary:
	return _delegate("restore_state", [state])


## One driver pulse: every tick made available by this pulse, in order.
## Empty while paused. Never a float input.
func pulse() -> Array:
	if _clock == null:
		return []
	var ticks: Variant = _clock.call("pulse")
	if typeof(ticks) != TYPE_ARRAY:
		return []
	return ticks


## Presents an integer tick as a position inside a caller-supplied cycle
## (e.g. time of day for a cycle of `cycle_length` ticks). The float conversion
## happens in Rust, at the edge; the integer tick remains the authority.
## Returns -1.0 when the clock is unavailable or the inputs are invalid.
func cycle_position(tick: int, cycle_length: int) -> float:
	if _clock == null or tick < 0 or cycle_length <= 0:
		return -1.0
	return float(_clock.call("cycle_position", tick, cycle_length))


## The clock revision this library was built with (stale-library guard).
func bridge_rev() -> String:
	return str(_clock.call("clock_bridge_rev")) if _clock != null else ""


## The instance id of the single native clock — for proofs that there is
## exactly one object behind every read.
func clock_instance_id() -> int:
	return _clock.get_instance_id() if _clock != null else -1


func _delegate(method: String, args: Array) -> Dictionary:
	if _clock == null:
		return {
			"ok": false,
			"error": "the shared clock is not available in this run",
		}
	var result: Variant = _clock.callv(method, args)
	if typeof(result) != TYPE_DICTIONARY:
		return {
			"ok": false,
			"error": "%s returned %s" % [method, type_string(typeof(result))],
		}
	return result
