extends Node

## The production-seam weather proof (Remich issue #19).
##
## This is the engine-side proof that the ONE weather channel can be driven by
## an external driver instead of the stand-in schedule, and that the externally
## published snapshot is visible through the *existing* readers. It runs in its
## own tiny project (`godot_external_weather/`), deliberately beside the
## committed fixture in `godot/`, because that fixture initializes the shared
## node in stand-in mode and must keep doing exactly that for its own
## acceptance. Nothing here changes it.
##
## The weather values below are **plain test numbers** standing in for what an
## external driver (Eisleck) decides. This probe contains no weather model, no
## climate, no schedule and no dependency on that driver: Remich stays
## independently testable. What is proven is the *seam* — that a complete
## decided snapshot, published under the one fixed production writer identity,
## is validated, stored, read back and rendered through the one channel.
##
## Inside pinned Godot it proves, end to end:
##
##   1. `RemichWeather` is a real registered class carrying the real callables,
##      the external initialization and the one production publish — and still
##      exposing **no** unrestricted weather setter;
##   2. external initialization claims the one channel for the fixed
##      production writer id, creates **no** stand-in driver, and refuses a
##      second initialization (so the two modes can never both hold it);
##   3. `drive(tick)` is unavailable in this mode: there is no stand-in
##      schedule, and the refusal says so rather than failing vaguely;
##   4. one complete, valid external snapshot publishes through the production
##      writer and reads back through `snapshot()` with **exactly** the seven
##      values supplied, the exact tick preserved;
##   5. `writer_status()` names the production writer and the snapshot's tick;
##   6. the existing `apply_wind()` derives the wind global from that
##      externally published snapshot, on that same channel, and the recorded
##      vector is compared against the published values;
##   7. invalid values are refused through the existing validation and the last
##      valid snapshot survives untouched;
##   8. a **second writer is refused from the engine side**, naming both
##      writers, leaving owner and snapshot unchanged.
##
## Failure prints `REMICH_EXTERNAL_WEATHER_FAIL reason=... detail=...` and
## exits non-zero. Success prints `REMICH_EXTERNAL_WEATHER_OK` and exits 0.

const WEATHER_CLASS := "RemichWeather"
const EXPECTATION_FILE := "res://external_weather_probe_expectation.txt"
const OK_MARKER := "REMICH_EXTERNAL_WEATHER_OK"
const FAIL_MARKER := "REMICH_EXTERNAL_WEATHER_FAIL"

## The pinned Grengewald contract: one game-owned shader global.
const WIND_GLOBAL := "grengewald_wind"
const WIND_GLOBAL_TYPE := "vec4"
const WIND_GLOBAL_DEFAULT := Vector4(1, 0, 0, 0)

## The one production writer identity, spelled exactly as
## `remich_core::weather::EXTERNAL_DRIVER_ID`. Asserted against what the engine
## observes, so a library that spells it differently cannot pass.
const EXTERNAL_WRITER := "eislek-weather-driver"

## The stand-in identity: what this mode must NOT be.
const STAND_IN_WRITER := "stand-in-weather-schedule"

## The callables the native class must have, including this seam's two.
const REQUIRED_CALLABLES: Array[String] = [
	"initialize", "initialize_external", "is_initialized",
	"publish_external_snapshot", "drive", "snapshot", "writer_id",
	"writer_status", "try_claim_writer", "apply_wind", "last_applied_wind",
	"weather_bridge_rev", "seed", "cycle_length",
]

## Methods that must NOT exist: there is no weather mutation that bypasses
## the one-writer rule, and no per-field setter that would let a caller
## assemble half a weather behind the production driver's back.
const FORBIDDEN_CALLABLES: Array[String] = [
	"set_wind", "set_wind_direction", "set_wind_strength", "set_rain",
	"set_temperature", "set_light", "set_snapshot", "set_tick", "publish",
	"set_weather", "publish_with_writer",
]

## The one decided snapshot this probe publishes. Plain constants, chosen to be
## unmistakable and to exercise every field at once: a tick far from any cycle
## boundary, a direction that is not an axis, a fractional strength, and
## distinct rain/temperature/light values. No meaning is implied by them.
const TICK := 137
const WIND_DIR_X := 0.6
const WIND_DIR_Z := -0.8
const WIND_STRENGTH := 0.42
const RAIN := 0.25
const TEMPERATURE := 7.5
const LIGHT := 0.33

## Godot's `vec4` is 32-bit while the snapshot is `f64`: the binding converts
## once at that edge.
const VECTOR_TOLERANCE := 0.000001

var _weather: Node = null


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	# --- 1. a real registered class with this seam's callables -----------------
	if not ClassDB.class_exists(WEATHER_CLASS):
		_fail("extension-not-loaded", WEATHER_CLASS + " is not registered in ClassDB")
		return
	for method_name in REQUIRED_CALLABLES:
		if not ClassDB.class_has_method(WEATHER_CLASS, method_name):
			_fail("callable-missing", WEATHER_CLASS + "." + method_name + " does not exist")
			return
	for method_name in FORBIDDEN_CALLABLES:
		if ClassDB.class_has_method(WEATHER_CLASS, method_name):
			_fail("unrestricted-mutation", WEATHER_CLASS + "." + method_name + " would bypass the one-writer rule")
			return

	var expected := _read_expectation()
	if expected.is_empty():
		_fail("not-staged", "could not read " + EXPECTATION_FILE + " (run tools/stage_external_weather.sh)")
		return

	# --- 2. external initialization claims the one channel --------------------
	var created: Node = ClassDB.instantiate(WEATHER_CLASS) as Node
	if created == null:
		_fail("instantiate-failed", "could not create " + WEATHER_CLASS)
		return
	add_child(created)
	_weather = created

	if bool(created.call("is_initialized")):
		_fail("premature-init", "the node reports itself initialized before initialization")
		return
	var claimed: Dictionary = created.call("initialize_external")
	if not bool(claimed.get("ok", false)):
		_fail("external-init-refused", str(claimed.get("error", "")))
		return
	if str(claimed.get("writer", "")) != EXTERNAL_WRITER:
		_fail("wrong-writer", "external initialization claimed '%s', expected '%s'" % [
			str(claimed.get("writer", "")), EXTERNAL_WRITER])
		return
	var revision := str(created.call("weather_bridge_rev"))
	if revision != expected:
		_fail("rev-mismatch", "the engine observed " + revision + " but the Rust source expects " + expected)
		return
	if _count_native() != 1:
		_fail("not-shared", "%d %s objects are in the scene tree, expected exactly 1" % [
			_count_native(), WEATHER_CLASS])
		return
	var instance_before := int(created.call("get_instance_id"))

	# No stand-in driver exists in this mode: the fixture's seed and cycle are
	# reported absent (-1), not defaulted to something plausible.
	if int(created.call("seed")) != -1:
		_fail("stand-in-seed", "external mode reports seed %d; there must be no stand-in" % [
			int(created.call("seed"))])
		return
	if int(created.call("cycle_length")) != -1:
		_fail("stand-in-cycle", "external mode reports cycle %d; there must be no stand-in" % [
			int(created.call("cycle_length"))])
		return

	# Exactly one native object, holding exactly the one channel.
	if int(created.call("writer_id")) != 0 and str(created.call("writer_id")) != EXTERNAL_WRITER:
		_fail("channel-writer", "the channel writer is '%s', expected '%s'" % [
			str(created.call("writer_id")), EXTERNAL_WRITER])
		return

	# A second initialization is refused, whichever way it is attempted: the
	# two modes are alternatives on one instance, never both.
	var again: Dictionary = created.call("initialize_external")
	if bool(again.get("ok", false)):
		_fail("second-init-accepted", "a second external initialization was allowed")
		return
	if str(again.get("code", "")) != "already-initialized":
		_fail("second-init-code", "the second initialization failed with '%s'" % str(again.get("code", "")))
		return
	var stand_in_init: Dictionary = created.call("initialize", 70021, 240)
	if bool(stand_in_init.get("ok", false)):
		_fail("mode-coexist", "stand-in initialization was allowed on an external node")
		return
	if str(created.call("writer_id")) != EXTERNAL_WRITER:
		_fail("owner-replaced", "the refused initializations changed the owner to '%s'" % [
			str(created.call("writer_id"))])
		return

	# --- 3. drive(tick) is unavailable in this mode ---------------------------
	var driven: Dictionary = created.call("drive", TICK)
	if bool(driven.get("ok", false)):
		_fail("drive-accepted", "drive(tick) silently generated stand-in weather in external mode")
		return
	if str(driven.get("code", "")) != "no-stand-in-driver":
		_fail("drive-code", "drive(tick) failed with '%s', expected 'no-stand-in-driver'" % [
			str(driven.get("code", ""))])
		return

	# --- 4. one complete decided snapshot publishes and reads back ------------
	# Nothing is published yet, so the existing readers say so rather than
	# inventing weather.
	var empty: Dictionary = created.call("snapshot")
	if bool(empty.get("ok", false)):
		_fail("premature-snapshot", "a snapshot exists before anything was published")
		return
	if str(empty.get("code", "")) != "no-snapshot":
		_fail("empty-code", "an unpublished snapshot read failed with '%s'" % str(empty.get("code", "")))
		return

	var published: Dictionary = _publish(created)
	if not bool(published.get("ok", false)):
		_fail("publish-refused", str(published.get("error", "")))
		return

	var snapshot: Dictionary = created.call("snapshot")
	if not bool(snapshot.get("ok", false)):
		_fail("readback-failed", "the publish succeeded but nothing reads back: %s" % [
			str(snapshot.get("error", ""))])
		return
	# Exactly the seven values supplied, through the existing reader.
	for entry in [
		["tick", TICK], ["wind_dir_x", WIND_DIR_X], ["wind_dir_z", WIND_DIR_Z],
		["wind_strength", WIND_STRENGTH], ["rain", RAIN],
		["temperature", TEMPERATURE], ["light", LIGHT],
	]:
		var key := str(entry[0])
		if float(snapshot.get(key, NAN)) != float(entry[1]):
			_fail("value-mismatch", "%s read back as %s, published %s" % [
				key, str(snapshot.get(key)), str(entry[1])])
			return
	if int(snapshot.get("tick", -1)) != TICK:
		_fail("tick-mismatch", "the snapshot tick is %d, expected the published %d" % [
			int(snapshot.get("tick", -1)), TICK])
		return

	# --- 5. writer_status identifies the production writer -------------------
	var status: Dictionary = created.call("writer_status")
	if not bool(status.get("owned", false)):
		_fail("unowned", "the external channel has no writer")
		return
	if str(status.get("writer", "")) != EXTERNAL_WRITER:
		_fail("status-writer", "writer_status names '%s', expected '%s'" % [
			str(status.get("writer", "")), EXTERNAL_WRITER])
		return
	if not bool(status.get("has_snapshot", false)):
		_fail("status-no-snapshot", "writer_status says there is no snapshot after a publish")
		return
	if int(status.get("snapshot_tick", -1)) != TICK:
		_fail("status-tick", "writer_status reports tick %d, expected %d" % [
			int(status.get("snapshot_tick", -1)), TICK])
		return

	# --- 6. the existing apply_wind reads that same channel -------------------
	var declared: Variant = ProjectSettings.get_setting("shader_globals/" + WIND_GLOBAL, null)
	if str((declared as Dictionary).get("type", "")) != WIND_GLOBAL_TYPE \
			or (declared as Dictionary).get("value") != WIND_GLOBAL_DEFAULT:
		_fail("global-declaration", "the project does not declare %s as the pinned %s" % [
			WIND_GLOBAL, WIND_GLOBAL_TYPE])
		return

	var applied: Dictionary = created.call("apply_wind")
	if not bool(applied.get("ok", false)):
		_fail("apply-refused", str(applied.get("error", "")))
		return
	if int(applied.get("tick", -1)) != TICK:
		_fail("apply-tick", "the wind write used tick %d, expected the published %d" % [
			int(applied.get("tick", -1)), TICK])
		return
	var vector: Array = created.call("last_applied_wind")
	if vector.size() != 4:
		_fail("applied-missing", "the recorded wind vector has %d components" % vector.size())
		return
	if not _same_numbers(applied.get("applied", []), vector):
		_fail("applied-diverged", "the returned and recorded vectors disagree")
		return
	# X/Y/Z are the externally published snapshot's own values.
	for entry in [["X", WIND_DIR_X], ["Y", WIND_DIR_Z], ["Z", WIND_STRENGTH]]:
		var index := ["X", "Y", "Z"].find(str(entry[0]))
		if absf(float(vector[index]) - float(entry[1])) > VECTOR_TOLERANCE:
			_fail("wind-component", "the applied %s is %s, the published snapshot says %s" % [
				str(entry[0]), str(vector[index]), str(entry[1])])
			return

	# --- 7. invalid values are refused, the last valid snapshot survives ------
	# Each entry is [what, wind_dir_x, wind_dir_z, strength, rain, temp, light]
	# — the same order `publish_external_snapshot` takes, so a refused value is
	# refused by the existing field's own rule, not by position.
	var before_invalid := JSON.stringify(created.call("snapshot"))
	for entry in [
		["non-finite wind_dir_x", [NAN, WIND_DIR_Z, WIND_STRENGTH, RAIN, TEMPERATURE, LIGHT], "wind_dir_x"],
		["non-finite rain", [WIND_DIR_X, WIND_DIR_Z, WIND_STRENGTH, NAN, TEMPERATURE, LIGHT], "rain"],
		["infinite temperature", [WIND_DIR_X, WIND_DIR_Z, WIND_STRENGTH, RAIN, INF, LIGHT], "temperature"],
		["negative strength", [WIND_DIR_X, WIND_DIR_Z, -0.1, RAIN, TEMPERATURE, LIGHT], ""],
	]:
		var values: Array = entry[1]
		var refused: Dictionary = created.call("publish_external_snapshot",
			TICK + 1, values[0], values[1], values[2], values[3], values[4], values[5])
		if bool(refused.get("ok", false)):
			_fail("invalid-accepted", "a snapshot with %s was accepted" % str(entry[0]))
			return
		if str(refused.get("code", "")) != "invalid-snapshot":
			_fail("invalid-code", "%s failed with '%s', expected 'invalid-snapshot'" % [
				str(entry[0]), str(refused.get("code", ""))])
			return
		# A non-finite field is refused by name, so the refusal says which one.
		var named := str(entry[2])
		if not named.is_empty() and not str(refused.get("error", "")).contains(named):
			_fail("invalid-unnamed", "the refusal for %s does not name '%s': %s" % [
				str(entry[0]), named, str(refused.get("error", ""))])
			return
		if JSON.stringify(created.call("snapshot")) != before_invalid:
			_fail("invalid-replaced", "a refused snapshot replaced the last valid one (%s)" % str(entry[0]))
			return

	# --- 8. a second writer is refused from the engine side -------------------
	var claim: Dictionary = created.call("try_claim_writer", "intruder-weather-driver")
	if bool(claim.get("ok", false)):
		_fail("second-writer-accepted", "a distinct second writer was allowed to claim the channel")
		return
	if str(claim.get("code", "")) != "writer-conflict":
		_fail("wrong-refusal", "the second claim failed with '%s', expected 'writer-conflict'" % [
			str(claim.get("code", ""))])
		return
	var conflict := "%s %s %s" % [
		str(claim.get("error", "")), str(claim.get("held_by", "")), str(claim.get("attempted", ""))]
	if not conflict.contains(EXTERNAL_WRITER) or not conflict.contains("intruder-weather-driver"):
		_fail("conflict-unnamed", "the refusal must name both writers, got: " + conflict)
		return
	if str(created.call("writer_id")) != EXTERNAL_WRITER:
		_fail("owner-replaced", "the refused claim changed the owner to '%s'" % str(created.call("writer_id")))
		return
	if JSON.stringify(created.call("snapshot")) != before_invalid:
		_fail("snapshot-changed", "the refused claim changed the published snapshot")
		return

	# Nothing along the way replaced the object or grew a second channel.
	if int(created.call("get_instance_id")) != instance_before:
		_fail("instance-replaced", "the native weather object changed during the run")
		return
	if _count_native() != 1:
		_fail("not-shared", "%d %s objects remain, expected exactly 1" % [
			_count_native(), WEATHER_CLASS])
		return

	print("%s writer=%s tick=%d strength=%.6f rev=%s" % [
		OK_MARKER, str(created.call("writer_id")), TICK, WIND_STRENGTH, revision])
	get_tree().quit(0)


# --- helpers -----------------------------------------------------------------

## The one production publish, called with the seven plain values.
func _publish(weather: Node) -> Dictionary:
	return weather.call("publish_external_snapshot",
		TICK, WIND_DIR_X, WIND_DIR_Z, WIND_STRENGTH, RAIN, TEMPERATURE, LIGHT)


## The number of native weather objects in the scene tree: the proof must own
## exactly one, on one channel.
func _count_native() -> int:
	var count := 0
	var stack: Array[Node] = [get_tree().root]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		if node.get_class() == WEATHER_CLASS:
			count += 1
		for child in node.get_children():
			if child is Node:
				stack.append(child)
	return count


func _same_numbers(left: Variant, right: Variant) -> bool:
	if typeof(left) != TYPE_ARRAY or typeof(right) != TYPE_ARRAY:
		return false
	if left.size() != right.size():
		return false
	for index in left.size():
		if float(left[index]) != float(right[index]):
			return false
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
	get_tree().quit(1)
