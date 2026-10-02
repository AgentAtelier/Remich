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
##   6. `apply_wind()` **refuses** in this mode with `no-presentation-phase`
##      instead of silently writing a frozen `W = 0.0`. W is the game-supplied
##      motion phase in radians, not weather, and no external weather snapshot
##      carries one — so this seam refuses to fabricate it, while the decided
##      weather itself stays valid, present and readable;
##   7. invalid values are refused through the existing validation and the last
##      valid snapshot survives untouched;
##   8. a **second writer is refused from the engine side**, naming both
##      writers, leaving owner and snapshot unchanged;
##   9. a production publish **cannot overwrite a writer that already holds the
##      channel** — against a stand-in-mode node it is refused with
##      `writer-conflict` naming both identities, and that node's snapshot
##      stands. (A second node is used for this because it is a different
##      *mode*; it is freed again, so exactly one live object remains.);
##  10. the stand-in path is unchanged: on a stand-in-mode node the same
##      `apply_wind()` still succeeds and still derives an animated W from the
##      integer tick.
##
## Failure prints `REMICH_EXTERNAL_WEATHER_FAIL reason=... detail=...` and
## exits non-zero. Success prints `REMICH_EXTERNAL_WEATHER_OK` and exits 0.

const WEATHER_CLASS := "RemichWeather"
const EXPECTATION_FILE := "res://external_weather_probe_expectation.txt"
const OK_MARKER := "REMICH_EXTERNAL_WEATHER_OK"
const FAIL_MARKER := "REMICH_EXTERNAL_WEATHER_FAIL"

## The refusal code an externally driven node gives when asked for the wind
## global's presentation phase. W is game-supplied motion in radians, not
## weather: the seam must refuse to invent one rather than write a frozen 0.0.
const NO_PHASE_CODE := "no-presentation-phase"

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

## The stand-in fixture's own explicit configuration, used only to prove that
## path is unchanged: a cycle in integer ticks and a tick inside it.
const STAND_IN_CYCLE_LENGTH := 240
const STAND_IN_TICK := 130

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

	# Exactly one native object, holding exactly the one channel. A direct
	# string identity check: comparing the string to the expected string is the
	# whole assertion. (Converting it to a number first would let any
	# non-numeric writer id compare equal to 0 and slip through.)
	if str(created.call("writer_id")) != EXTERNAL_WRITER:
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
	var stand_in_init: Dictionary = created.call("initialize", 70021, STAND_IN_CYCLE_LENGTH)
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

	# --- 6. apply_wind refuses rather than inventing a presentation phase ----
	# The pinned global is still checked: the seam writes it, and it is not being
	# quietly removed.
	var declared: Variant = ProjectSettings.get_setting("shader_globals/" + WIND_GLOBAL, null)
	if str((declared as Dictionary).get("type", "")) != WIND_GLOBAL_TYPE \
			or (declared as Dictionary).get("value") != WIND_GLOBAL_DEFAULT:
		_fail("global-declaration", "the project does not declare %s as the pinned %s" % [
			WIND_GLOBAL, WIND_GLOBAL_TYPE])
		return

	# W is the game-supplied motion phase in radians, not weather. A cycle is
	# fixture configuration (the stand-in's explicit cycle_length), and no
	# external weather snapshot carries a phase. So this mode must REFUSE: a
	# frozen W = 0.0 would silently make the real Grengewald motion phase
	# static, and borrowing the fixture's 240-tick cycle would invent one.
	var applied: Dictionary = created.call("apply_wind")
	if bool(applied.get("ok", false)):
		_fail("apply-accepted", "apply_wind() succeeded in external mode; it must refuse rather \
			than fabricate a presentation phase (applied: %s)" % str(applied.get("applied", [])))
		return
	if str(applied.get("code", "")) != NO_PHASE_CODE:
		_fail("apply-code", "apply_wind() failed with '%s', expected '%s'" % [
			str(applied.get("code", "")), NO_PHASE_CODE])
		return
	# The refusal must say the weather is fine and only the phase is not owned
	# here, so the reason is auditable rather than vague.
	var apply_reason := str(applied.get("error", ""))
	if not apply_reason.contains("valid and present") \
			or not apply_reason.contains("presentation phase"):
		_fail("apply-reason", "the refusal does not separate the valid weather from the \
			unowned presentation phase: " + apply_reason)
		return
	# A refused apply must write nothing at all: no recorded vector, so no
	# fabricated W is left behind in the global either.
	var fabricated: Array = created.call("last_applied_wind")
	if fabricated.size() != 0:
		_fail("apply-fabricated", "a refused apply_wind() still recorded a wind vector: %s" % [
			str(fabricated)])
		return
	# The weather itself is untouched by the refusal: still valid, still present,
	# still exactly the seven published values and the exact tick.
	var after_apply: Dictionary = created.call("snapshot")
	if JSON.stringify(after_apply) != JSON.stringify(snapshot):
		_fail("apply-damaged", "the refused apply_wind() changed the published weather")
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
	# Two refusals, because the one-writer rule has two halves and both must
	# bite in the engine: a distinct identity may not CLAIM, and (proven below,
	# on a stand-in-owned node) a production publish may not overwrite a writer
	# that already holds the channel.
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

	# --- 9. a production publish cannot overwrite another writer ---------------
	# The other half of the one-writer rule, proved through the engine: a node
	# initialized in STAND-IN mode holds the channel under the stand-in id, and
	# the production publish must be refused against it — no matter how valid
	# the snapshot is. This is a separate node on purpose (it is a different
	# mode, not a second channel on the shared one), and it is freed before the
	# instance-count check below, which still requires exactly one live object.
	var stand_in_node: Node = ClassDB.instantiate(WEATHER_CLASS) as Node
	if stand_in_node == null:
		_fail("instantiate-failed", "could not create a stand-in-mode node")
		return
	add_child(stand_in_node)
	var fixture_init := stand_in_node.call("initialize", 70021, STAND_IN_CYCLE_LENGTH) as Dictionary
	if not bool(fixture_init.get("ok", false)):
		_fail("stand-in-init-refused", str(fixture_init.get("error", "")))
		return
	if str(stand_in_node.call("writer_id")) != STAND_IN_WRITER:
		_fail("stand-in-writer", "the stand-in node is owned by '%s'" % str(stand_in_node.call("writer_id")))
		return
	stand_in_node.call("drive", STAND_IN_TICK)
	var stand_in_before := JSON.stringify(stand_in_node.call("snapshot"))
	var takeover: Dictionary = stand_in_node.call("publish_external_snapshot",
		TICK, WIND_DIR_X, WIND_DIR_Z, WIND_STRENGTH, RAIN, TEMPERATURE, LIGHT)
	if bool(takeover.get("ok", false)):
		_fail("takeover-accepted", "a production publish overwrote the stand-in that owns the channel")
		return
	if str(takeover.get("code", "")) != "writer-conflict":
		_fail("takeover-code", "the production publish against the stand-in failed with '%s', expected 'writer-conflict'" % [
			str(takeover.get("code", ""))])
		return
	var takeover_conflict := "%s %s %s" % [
		str(takeover.get("error", "")), str(takeover.get("held_by", "")), str(takeover.get("attempted", ""))]
	if not takeover_conflict.contains(STAND_IN_WRITER) or not takeover_conflict.contains(EXTERNAL_WRITER):
		_fail("takeover-unnamed", "the refusal must name both writers, got: " + takeover_conflict)
		return
	if JSON.stringify(stand_in_node.call("snapshot")) != stand_in_before:
		_fail("takeover-replaced", "the refused publish changed the stand-in's snapshot")
		return

	# --- 10. the stand-in path is unchanged -----------------------------------
	# The same apply_wind() that just refused in external mode must still succeed
	# here, because the stand-in declares the explicit presentation cycle the
	# fixture supplied. If the refusal had been made unconditional, this fails too.
	var fixture_applied: Dictionary = stand_in_node.call("apply_wind")
	if not bool(fixture_applied.get("ok", false)):
		_fail("stand-in-apply-refused", "apply_wind() was refused on the stand-in node too: %s" % [
			str(fixture_applied.get("error", ""))])
		return
	if int(fixture_applied.get("tick", -1)) != STAND_IN_TICK:
		_fail("stand-in-apply-tick", "the stand-in wind write used tick %d, expected %d" % [
			int(fixture_applied.get("tick", -1)), STAND_IN_TICK])
		return
	var fixture_vector: Array = stand_in_node.call("last_applied_wind")
	if fixture_vector.size() != 4:
		_fail("stand-in-applied-missing", "the stand-in wind vector has %d components" % [
			fixture_vector.size()])
		return
	if not _same_numbers(fixture_applied.get("applied", []), fixture_vector):
		_fail("stand-in-applied-diverged", "the returned and recorded stand-in vectors disagree")
		return
	# The stand-in's W is still the animated, tick-derived presentation phase, not
	# frozen: tick 130 in a 240-tick cycle is 130/240 of a turn, so W is neither
	# zero nor the same value a different tick would produce.
	var expected_w := TAU * float(STAND_IN_TICK) / float(STAND_IN_CYCLE_LENGTH)
	if absf(float(fixture_vector[3]) - expected_w) > VECTOR_TOLERANCE:
		_fail("stand-in-w-wrong", "the stand-in's W is %s, expected the tick-derived phase %s" % [
			str(fixture_vector[3]), str(expected_w)])
		return
	# X/Y/Z still come from the stand-in's own published snapshot.
	var fixture_snapshot: Dictionary = stand_in_node.call("snapshot")
	var fixture_components := [
		float(fixture_snapshot.get("wind_dir_x", NAN)),
		float(fixture_snapshot.get("wind_dir_z", NAN)),
		float(fixture_snapshot.get("wind_strength", NAN)),
	]
	for index in 3:
		if absf(float(fixture_vector[index]) - fixture_components[index]) > VECTOR_TOLERANCE:
			_fail("stand-in-wind-component", "the stand-in's applied component %d is %s, its \
				snapshot says %s" % [index, str(fixture_vector[index]), str(fixture_components[index])])
			return
	# One tick further and the phase moves: it is derived from the integer tick,
	# never held still.
	stand_in_node.call("drive", STAND_IN_TICK + 1)
	stand_in_node.call("apply_wind")
	var moved: Array = stand_in_node.call("last_applied_wind")
	if moved.size() != 4 or absf(float(moved[3]) - float(fixture_vector[3])) < 1e-6:
		_fail("stand-in-w-static", "the stand-in's W did not change between ticks %d and %d" % [
			STAND_IN_TICK, STAND_IN_TICK + 1])
		return
	stand_in_node.queue_free()
	await get_tree().process_frame

	# Nothing along the way replaced the shared object or grew a second channel.
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
