class_name TwinUnderdeckGateArt
extends RefCounted
## Presentation only. The passage owns collision, slide distance and state lamps.
## Two explicit GLBs prevent the stationary rail from following the moving door.
const PANEL_PATH := "res://assets/v3/underdeck_door/panel.glb"
const RAIL_PATH := "res://assets/v3/underdeck_door/fixed_rail.glb"

static func panel(rear: bool) -> Node3D:
	return _instance(PANEL_PATH, "AuthoredMovingPanel", rear)

static func rail(rear: bool) -> Node3D:
	return _instance(RAIL_PATH, "AuthoredFixedRail", rear)

static func lamp(rail_root: Node3D) -> MeshInstance3D:
	var found := rail_root.find_children("StatusLens", "MeshInstance3D", true, false)
	if found.size() != 1:
		push_error("Underdeck rail requires exactly one authored StatusLens")
		return null
	var surface := found[0] as MeshInstance3D
	# Keep the actual curved lens geometry and texture; clone just this surface's
	# material so front/rear states cannot recolor each other or the painted frame.
	var material := surface.get_active_material(0).duplicate() as StandardMaterial3D
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.emission_enabled = false
	surface.material_override = material
	# The fixed camera sees the back of the north rail. Repeat the authored lens
	# on that actual rail back, sharing this gate's state (never the other gate).
	# This is presentation only and cannot add collision or change the open gap.
	var repeater := surface.duplicate() as MeshInstance3D
	repeater.name = "StatusRepeater"
	repeater.rotation.y = PI
	repeater.material_override = material
	surface.get_parent().add_child(repeater)
	return surface

static func _instance(path: String, label: String, rear: bool) -> Node3D:
	var packed := load(path) as PackedScene
	if packed == null:
		push_error("Underdeck authored GLB unavailable: " + path)
		return null
	var root := packed.instantiate() as Node3D
	root.name = label
	# Front design +X parking becomes world -X at the north door. Physics stays
	# world aligned; both fully authored faces remain visible from inside/outside.
	root.rotation.y = PI if rear else 0.0
	return root
