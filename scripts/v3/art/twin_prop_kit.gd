class_name TwinPropKit
extends Node3D
## Reimport-safe wrapper. Editable source stays in Blender; rules stay in the world.
const PATHS = {
	"coastal_work_terrace":"res://assets/v3/industrial_kit/coastal_work_terrace.glb",
	"power_relay_cabinet":"res://assets/v3/industrial_kit/power_relay_cabinet.glb",
	"rootstone_terrace":"res://assets/v3/fantasy_kit/rootstone_terrace.glb",
	"photosensitive_roots":"res://assets/v3/fantasy_kit/photosensitive_roots.glb"
}
@export_enum("coastal_work_terrace", "power_relay_cabinet", "rootstone_terrace", "photosensitive_roots") var asset_kind = "coastal_work_terrace"
@export var create_collision = false
var imported = false
var visual: Node3D
var collision_body: StaticBody3D
var pivots: Dictionary = {}
var rest: Dictionary = {}
var lamps: Dictionary = {}
var _lamp_materials: Dictionary = {}
static var _shape_cache: Dictionary = {}

func _ready() -> void:
	var model = load(PATHS[asset_kind]) as PackedScene
	if model == null:
		push_error("Missing authored kit: " + asset_kind)
		return
	visual = model.instantiate()
	add_child(visual)
	if asset_kind == "coastal_work_terrace":
		# The shared atlas also contains a cabinet lamp; concrete stair paint emits no light.
		var paint = visual.find_child("Static_IK_SafetySignal", true, false)
		if paint is MeshInstance3D and paint.get_active_material(0) is StandardMaterial3D:
			var surface = paint.get_active_material(0).duplicate()
			surface.emission_enabled = false
			paint.material_override = surface
	if create_collision:
		collision_body = StaticBody3D.new()
		collision_body.name = "AuthoredTerrainCollision"
		collision_body.collision_layer = 1
		add_child(collision_body)
		_add_collision(visual)
	for key in ["SwitchPivot", "LeafPivot_N", "LeafPivot_E", "LeafPivot_S", "LeafPivot_W"]:
		var pivot = visual.find_child(key, true, false)
		if pivot is Node3D:
			pivots[key] = pivot
			rest[key] = pivot.transform
	for key in ["StatusLamp", "Terminal_A", "Terminal_B", "Terminal_C", "Static_Core"]:
		var node = visual.find_child(key, true, false)
		if node: lamps[key] = _meshes(node)
	imported = true

func _meshes(node: Node) -> Array:
	var result: Array = []
	if node is MeshInstance3D: result.append(node)
	for child in node.get_children(): result.append_array(_meshes(child))
	return result

func _add_collision(node: Node) -> void:
	var collidable = not str(node.name).contains("Foliage")
	if asset_kind == "coastal_work_terrace": collidable = str(node.name).contains("IvoryWeather")
	if node is MeshInstance3D and node.mesh != null and collidable:
		var key = str(PATHS[asset_kind]) + ":" + str(visual.get_path_to(node))
		if not _shape_cache.has(key): _shape_cache[key] = node.mesh.create_trimesh_shape()
		var shape = CollisionShape3D.new()
		shape.name = "Surface_" + str(node.name)
		shape.shape = _shape_cache[key]
		collision_body.add_child(shape)
		shape.transform = global_transform.affine_inverse() * node.global_transform
	for child in node.get_children(): _add_collision(child)

func set_state(state: Dictionary) -> void:
	if not imported: return
	if asset_kind == "power_relay_cabinet":
		var powered = bool(state.get("powered", false)) or float(state.get("charge", 0)) >= 30
		_glow("StatusLamp", 1.0 if powered else 0.0, Color("6bd9ba"))
		for i in range(3): _glow(["Terminal_A", "Terminal_B", "Terminal_C"][i], 0.7 if float(state.get("charge", 0)) >= (i + 1) * 30 else 0.0, Color("81cbe3"))
		if pivots.has("SwitchPivot"):
			pivots.SwitchPivot.transform = rest.SwitchPivot
			pivots.SwitchPivot.rotate_object_local(Vector3.RIGHT, deg_to_rad(28 if powered else 0))
	elif asset_kind == "photosensitive_roots":
		var growth = clampf(float(state.get("growth", 0)), 0, 1)
		for key in pivots:
			pivots[key].transform = rest[key]
			pivots[key].rotate_object_local(Vector3.RIGHT, deg_to_rad(-58) * growth)
		var lit = maxf(float(state.get("environment_light", 0)), float(state.get("light_level", 0))) >= 0.25
		_glow("Static_Core", 1.1 if lit else 0.05, Color("67d9cd"))

func _glow(key: String, energy: float, color: Color) -> void:
	for mesh in lamps.get(key, []):
		for surface_index in range(mesh.mesh.get_surface_count()):
			var id = "%s:%s" % [mesh.get_instance_id(), surface_index]
			var source = mesh.mesh.surface_get_material(surface_index)
			if not source is StandardMaterial3D: continue
			# Terminals retain their ceramic insulation; only the conductor signals charge.
			if key.begins_with("Terminal_") and not str(source.resource_name).contains("Galvanized"): continue
			if not _lamp_materials.has(id):
				var copy = source.duplicate()
				mesh.set_surface_override_material(surface_index, copy)
				_lamp_materials[id] = copy
			var material: StandardMaterial3D = _lamp_materials[id]
			material.emission_enabled = energy > 0
			material.emission = color
			material.emission_energy_multiplier = energy
