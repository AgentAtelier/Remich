extends SceneTree

## Phase 3, step 2 soul proof (docs/PLAN.md §4b: "soul primitives across the
## bridge").
##
## This is deliberately NOT an autoload: it is a standalone script the runner
## invokes explicitly, so the project's autoload chain and order are untouched
## (tools/run_soul.sh: `godot --headless --script res://soul_probe.gd`). It
## proves the whole Step 2 path inside pinned Godot:
##
##   1. `RemichSoul` is a real registered GDExtension class with the real
##      callables, and it exposes NO way to change an axis or to apply an
##      influence to a soul;
##   2. three fixed stand-ins (committed seeds) are created through the donor's
##      own `LayeredSoul::from_seed`, and read back with their three substrate
##      traits and their four emotional axes;
##   3. each stand-in is probed through a different donor connection layer —
##      family, proximity, village — and the edge strength is the donor's
##      `ConnectionLayer::weight()`;
##   4. the returned four values are the donor's propagated INFLUENCE, labelled
##      as such in the trace; they are never written into any soul, and the
##      snapshot read before and after the call is bit-for-bit unchanged;
##   5. an unknown layer name is refused, not substituted;
##   6. every record is written as plain text, byte-for-byte reproducible for
##      the fixed seeds.
##
## Test-only bypass (`REMICH_SOUL_BYPASS=1`, set by tools/run_soul.sh): the
## probe skips the call to the donor's propagation calculation and records
## neutral (zero) influence values instead, while seed, substrate, source axes,
## layer name and donor weight stay identical. Nothing else changes, and no
## mode string is written into the trace — so a differing trace SHA proves the
## propagated-influence fields carried the difference.
##
## Failure prints `REMICH_SOUL_FAIL reason=...` and exits non-zero.

const SOUL_CLASS := "RemichSoul"
const EXPECTATION_FILE := "res://soul_probe_expectation.txt"
const TRACE_ENV := "REMICH_SOUL_TRACE_PATH"
const BYPASS_ENV := "REMICH_SOUL_BYPASS"
const OK_MARKER := "REMICH_SOUL_OK"
const PROPAGATION_MARKER := "REMICH_SOUL_PROPAGATION_OK"
const FAIL_MARKER := "REMICH_SOUL_FAIL"

## The three committed fixed stand-ins: seed, actor name, and the one donor
## connection layer each is probed through (fixed order). The seeds are
## duplicated in crates/remich_core/src/soul.rs's fixture tests;
## tools/check_phase3_step2.sh compares the two lists.
const SEEDS: Array[int] = [1000003, 2000003, 3000003]
const ACTOR_NAMES: Array[String] = ["standin-0", "standin-1", "standin-2"]
const LAYERS: Array[String] = ["family", "proximity", "village"]

## The donor's layer names, exercised once each.
const EXPECTED_LAYERS := "family,proximity,village"

## A layer name the donor does not have: must be refused, never substituted.
const UNKNOWN_LAYER := "stranger"

## Callables the native class must actually have.
const REQUIRED_CALLABLES: Array[String] = [
	"initialize", "is_initialized", "soul_snapshot", "connection_weight",
	"propagate", "soul_bridge_rev",
]

## Methods that must NOT exist: no event may change an axis, and no influence
## may ever be applied to, blended into or clamped onto a soul. The donor has
## no such operation either — this is the step's core negative claim.
const FORBIDDEN_CALLABLES: Array[String] = [
	"apply_influence", "apply_propagation", "apply_to", "add_influence",
	"blend_influence", "set_axes", "set_axis", "set_security", "set_belonging",
	"set_agency", "set_satiation", "set_mood", "on_need_met", "on_need_unmet",
	"need_met", "need_unmet", "on_catastrophe_felt", "catastrophe_felt",
	"feel_catastrophe", "update_receiver", "set_substrate",
]

var _trace_path := ""
var _bypass := false


func _initialize() -> void:
	quit(_run())


func _run() -> int:
	_trace_path = OS.get_environment(TRACE_ENV)
	if _trace_path.is_empty():
		return _fail("no-trace-path", TRACE_ENV + " must name the trace to write")
	_bypass = OS.get_environment(BYPASS_ENV) == "1"

	# --- 1. a real registered class with the real callables ------------------
	if not ClassDB.class_exists(SOUL_CLASS):
		return _fail("extension-not-loaded", SOUL_CLASS + " is not registered in ClassDB")
	for method_name in REQUIRED_CALLABLES:
		if not ClassDB.class_has_method(SOUL_CLASS, method_name):
			return _fail("callable-missing", SOUL_CLASS + "." + method_name + " does not exist")
	for method_name in FORBIDDEN_CALLABLES:
		if ClassDB.class_has_method(SOUL_CLASS, method_name):
			return _fail("event-or-application-api",
				SOUL_CLASS + "." + method_name + " would be an axis mutation or a receiver application")

	var expected := _read_expectation()
	if expected.is_empty():
		return _fail("not-staged", "could not read " + EXPECTATION_FILE + " (run tools/stage_soul.sh)")

	# --- 2. the revision this library was actually built with ----------------
	# Instantiated through ClassDB so a missing extension is a reported
	# failure rather than a parse error (no compile-time link to the class).
	var soul: Object = ClassDB.instantiate(SOUL_CLASS)
	if soul == null:
		return _fail("no-instance", "could not instantiate " + SOUL_CLASS)
	var revision := str(soul.call("soul_bridge_rev"))
	if revision != expected:
		soul.free()
		return _fail("rev-mismatch", "the engine observed %s but the Rust source expects %s" % [
			revision, expected])
	if bool(soul.call("is_initialized")):
		soul.free()
		return _fail("premature-soul", "a fresh " + SOUL_CLASS + " already holds a soul")

	# --- 3. an unknown layer must be refused, never substituted --------------
	# A soul must exist first: an uninitialized class refuses everything,
	# which is correct but is not the refusal under test here.
	var primed: Dictionary = soul.call("initialize", SEEDS[0])
	if not bool(primed.get("ok", false)):
		soul.free()
		return _fail("prime-refused", str(primed.get("error", "")))
	var refusal: Dictionary
	if _bypass:
		refusal = soul.call("connection_weight", UNKNOWN_LAYER)
	else:
		refusal = soul.call("propagate", UNKNOWN_LAYER)
	if bool(refusal.get("ok", true)):
		soul.free()
		return _fail("unknown-layer-accepted", "'%s' was accepted as a connection layer" % UNKNOWN_LAYER)
	if str(refusal.get("code", "")) != "unknown-layer":
		soul.free()
		return _fail("wrong-refusal", "the unknown layer failed with code '%s', expected 'unknown-layer'" % [
			str(refusal.get("code", ""))])

	# --- 4. the three stand-ins ---------------------------------------------
	var records: Array[String] = []
	var influenced_nonzero := false

	for index in SEEDS.size():
		var seed := SEEDS[index]
		var layer := LAYERS[index]

		var started: Dictionary = soul.call("initialize", seed)
		if not bool(started.get("ok", false)):
			soul.free()
			return _fail("initialize-refused", str(started.get("error", "")))
		if int(started.get("seed", -1)) != seed:
			soul.free()
			return _fail("seed-echo", "initialize echoed seed %s, expected %d" % [
				str(started.get("seed", "")), seed])
		if not bool(soul.call("is_initialized")):
			soul.free()
			return _fail("not-initialized", "initialize succeeded but the soul is not initialized")
		if str(started.get("bridge_rev", "")) != revision:
			soul.free()
			return _fail("rev-missing", "initialize did not carry bridge_rev %s" % revision)

		var before: Dictionary = soul.call("soul_snapshot")
		if not bool(before.get("ok", false)):
			soul.free()
			return _fail("snapshot-refused", str(before.get("error", "")))
		if int(before.get("seed", -1)) != seed:
			soul.free()
			return _fail("snapshot-seed", "the snapshot seed %s != %d" % [
				str(before.get("seed", "")), seed])
		var substrate: Dictionary = before.get("substrate", {})
		var source_axes: Dictionary = before.get("axes", {})
		if substrate.size() != 3 or source_axes.size() != 4:
			soul.free()
			return _fail("snapshot-shape", "substrate has %d and axes %d fields" % [
				substrate.size(), source_axes.size()])

		# The donor's edge strength, then (outside bypass) the donor's
		# propagated influence for that layer.
		var weight := 0.0
		var influence := [0.0, 0.0, 0.0, 0.0]
		if _bypass:
			# Test-only: the propagation calculation is NOT invoked; neutral
			# influence values are recorded instead. Everything else is read
			# from the same donor calls as the normal run.
			var weighted: Dictionary = soul.call("connection_weight", layer)
			if not bool(weighted.get("ok", false)):
				soul.free()
				return _fail("weight-refused", str(weighted.get("error", "")))
			weight = float(weighted.get("connection_weight", 0.0))
		else:
			var propagated: Dictionary = soul.call("propagate", layer)
			if not bool(propagated.get("ok", false)):
				soul.free()
				return _fail("propagate-refused", str(propagated.get("error", "")))
			if str(propagated.get("layer", "")) != layer:
				soul.free()
				return _fail("layer-echo", "propagate answered layer '%s', expected '%s'" % [
					str(propagated.get("layer", "")), layer])
			if str(propagated.get("value_kind", "")) != "propagated-influence":
				soul.free()
				return _fail("unlabelled-influence", "the result is not labelled as propagated influence")
			if bool(propagated.get("receiver_state_changed", true)):
				soul.free()
				return _fail("receiver-claimed", "the propagation claims it changed a receiver state")
			weight = float(propagated.get("connection_weight", 0.0))
			var values: Dictionary = propagated.get("propagated_influence", {})
			if values.size() != 4:
				soul.free()
				return _fail("influence-shape", "the influence has %d axes" % values.size())
			influence = [
				float(values.get("security_threat", 0.0)),
				float(values.get("belonging_isolation", 0.0)),
				float(values.get("agency_helplessness", 0.0)),
				float(values.get("satiation_desperation", 0.0)),
			]

		# Propagation reads and returns: the soul's own state must not move.
		var after: Dictionary = soul.call("soul_snapshot")
		if not bool(after.get("ok", false)):
			soul.free()
			return _fail("snapshot-after", str(after.get("error", "")))
		# Sorted keys: the comparison must not depend on dictionary order.
		if JSON.stringify(after, "", true) != JSON.stringify(before, "", true):
			soul.free()
			return _fail("receiver-mutated",
				"the soul snapshot changed across the propagation call — an influence was applied")

		for value in influence:
			if float(value) != 0.0:
				influenced_nonzero = true

		records.append("actor=%d name=%s seed=%d" % [index, ACTOR_NAMES[index], seed])
		records.append(_floats_line("substrate", [
			float(substrate.get("courage_fear", 0.0)),
			float(substrate.get("generosity_selfishness", 0.0)),
			float(substrate.get("stability_anxiety", 0.0)),
		], ["courage_fear", "generosity_selfishness", "stability_anxiety"]))
		records.append(_axes_line("source_axes", source_axes))
		records.append("connection layer=%s weight=%.6f" % [layer, weight])
		records.append(_floats_line("propagated_influence", influence, [
			"security_threat", "belonging_isolation", "agency_helplessness",
			"satiation_desperation",
		]))
		records.append("influence_kind=propagated-influence (not a receiver state update)")
		records.append("bridge_rev=%s" % revision)
		records.append("")

	soul.free()

	# A zero-output implementation must not be able to pass: the NORMAL run
	# must show at least one non-zero propagated component. Bypass mode
	# records zeros by design — its difference from the normal trace is the
	# whole proof — so the guard is not applied there.
	if not _bypass and not influenced_nonzero:
		return _fail("influence-neutral",
			"every propagated influence component is zero — a zero-output implementation cannot pass")

	# --- 5. the trace ---------------------------------------------------------
	if not _write_trace(records):
		return 1

	print("%s actors=%d rev=%s" % [OK_MARKER, SEEDS.size(), revision])
	if not _bypass:
		print("%s layers=%s rev=%s" % [PROPAGATION_MARKER, EXPECTED_LAYERS, revision])
	return 0


# --- helpers -----------------------------------------------------------------


func _axes_line(label: String, axes: Dictionary) -> String:
	return _floats_line(label, [
		float(axes.get("security_threat", 0.0)),
		float(axes.get("belonging_isolation", 0.0)),
		float(axes.get("agency_helplessness", 0.0)),
		float(axes.get("satiation_desperation", 0.0)),
	], ["security_threat", "belonging_isolation", "agency_helplessness",
		"satiation_desperation"])


func _floats_line(label: String, values: Array, keys: Array) -> String:
	var parts: Array[String] = []
	for index in keys.size():
		parts.append("%s=%.6f" % [keys[index], float(values[index])])
	return "%s %s" % [label, " ".join(parts)]


func _write_trace(records: Array) -> bool:
	var file := FileAccess.open(_trace_path, FileAccess.WRITE)
	if file == null:
		_fail("trace-unwritable", "could not open " + _trace_path)
		return false
	file.store_string("\n".join(records) + "\n")
	file.close()
	return true


func _read_expectation() -> String:
	if not FileAccess.file_exists(EXPECTATION_FILE):
		return ""
	var file := FileAccess.open(EXPECTATION_FILE, FileAccess.READ)
	if file == null:
		return ""
	return file.get_as_text().strip_edges()


func _fail(reason: String, detail: String) -> int:
	print("%s reason=%s detail=%s" % [FAIL_MARKER, reason, detail])
	return 1
