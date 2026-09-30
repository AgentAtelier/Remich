extends Node
## Step 1 marker: proves the pinned engine really opened THIS project and ran
## its main scene (docs/PLAN.md, phase 1, step 1). It prints one line and does
## nothing else — no simulation, no behaviour.

func _ready() -> void:
	print("REMICH_TEST_PROJECT_OPENED")
