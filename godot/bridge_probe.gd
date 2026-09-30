extends Node

## Phase 1, step 2 bridge probe (docs/PLAN.md).
##
## The engine loads Remich's Rust GDExtension at startup. This autoload proves
## the three things an exit code alone cannot:
##
##   1. the extension was loaded   -- the Rust class is registered in ClassDB;
##   2. the Rust callable was reached -- it exists and is invoked from GDScript;
##   3. the expected value crossed the boundary -- the returned value is exactly
##      what the Rust source currently declares, read from the expectation file
##      that tools/stage_bridge.sh derives from crates/remich_gdext/src/lib.rs.
##
## It prints one machine-checkable line and quits with a matching exit code.
## Nothing here is simulation: it is a probe of the bridge and nothing else.

const BRIDGE_CLASS := "RemichBridge"
const BRIDGE_CALLABLE := "bridge_probe"
const EXPECTATION_FILE := "res://bridge_probe_expectation.txt"
const VALUE_PREFIX := "remich-bridge-"
const OK_MARKER := "REMICH_BRIDGE_OK"
const FAIL_MARKER := "REMICH_BRIDGE_FAIL"


func _ready() -> void:
	var expected := _read_expectation()
	if expected.is_empty():
		_fail("expectation-missing", "could not read " + EXPECTATION_FILE)
		return

	# 1. the extension was loaded
	if not ClassDB.class_exists(BRIDGE_CLASS):
		_fail("extension-not-loaded", BRIDGE_CLASS + " is not registered in ClassDB")
		return

	# 2. the Rust callable was reached
	if not ClassDB.class_has_method(BRIDGE_CLASS, BRIDGE_CALLABLE):
		_fail("callable-missing", BRIDGE_CLASS + "." + BRIDGE_CALLABLE + " does not exist")
		return

	var bridge: Object = ClassDB.instantiate(BRIDGE_CLASS)
	if bridge == null:
		_fail("instantiate-failed", "ClassDB could not instantiate " + BRIDGE_CLASS)
		return

	var returned: Variant = bridge.call(BRIDGE_CALLABLE)
	bridge.free()

	# 3. the expected value crossed the boundary and was observed by Godot
	if typeof(returned) != TYPE_STRING:
		_fail("wrong-type", "expected String, got " + type_string(typeof(returned)))
		return
	if not (returned as String).begins_with(VALUE_PREFIX):
		_fail("unexpected-value", str(returned) + " is not a bridge probe value")
		return
	if returned != expected:
		_fail("value-mismatch", "Godot observed " + str(returned)
				+ " but the Rust source expects " + expected)
		return

	print(OK_MARKER + " value=" + returned)
	get_tree().quit(0)


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
