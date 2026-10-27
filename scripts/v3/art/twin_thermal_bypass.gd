class_name TwinThermalBypass
extends Node3D
## Read-only presentation of the host's thermal entity. No physics or save ownership.
const MODEL_PATH := "res://assets/v3/thermal_bypass/thermal_bypass.glb"
# Artist contract: fan axle in the imported asset-root coordinates, not Blender Euler.
const FAN_AXIS_IN_ASSET := Vector3(0, 0, 1)
const HEAT_EMISSION_CAP := 0.16
const LAMP_EMISSION_CAP := 0.8

var imported := false
var import_errors: Array[String] = []
var visual: Node3D
var _fan: Node3D
var _fan_rest := Transform3D.IDENTITY
var _fan_axis := Vector3.ZERO
var _fan_phase := 0.0
var _fan_speed := 0.0
var _animation_paused := false
var _temperature := 20.0
var _powered := false
var _heat_materials: Array[Dictionary] = []
var _lamp_materials: Array[Dictionary] = []

func _ready() -> void:
	if not ResourceLoader.exists(MODEL_PATH):
		_fail("Authored thermal GLB is not imported yet: " + MODEL_PATH)
		return
	var packed := load(MODEL_PATH) as PackedScene
	if packed == null:
		_fail("Thermal GLB must resolve to a PackedScene")
		return
	visual = packed.instantiate() as Node3D
	if visual == null:
		_fail("Thermal GLB root must be Node3D")
		return
	add_child(visual)
	var nodes: Dictionary = {}
	for key in ["FanRotor", "StatusLens", "HeatPipes"]:
		var found := visual.find_children(key, "Node3D", true, false)
		if found.size() != 1:
			_fail("Expected one " + key + ", found " + str(found.size()))
		else: nodes[key] = found[0]
	if visual is CollisionObject3D or not visual.find_children("*", "CollisionObject3D", true, false).is_empty():
		_fail("Thermal GLB may not own world collisions")
	if not visual.find_children("*", "Camera3D", true, false).is_empty() or not visual.find_children("*", "Light3D", true, false).is_empty():
		_fail("Thermal GLB includes a studio camera or light")
	if not import_errors.is_empty(): return
	_fan = nodes.FanRotor
	_fan_rest = _fan.transform
	if _meshes(_fan).is_empty():
		_fail("FanRotor contains no authored rotor mesh")
	# Transform the artist's asset-root axis into the actual local pivot basis.
	var axis: Vector3 = _fan.global_basis.inverse() * visual.global_basis * FAN_AXIS_IN_ASSET
	if not axis.is_finite() or axis.length_squared() < 0.001:
		_fail("Imported FanRotor basis cannot express its declared axle")
	else: _fan_axis = axis.normalized()
	var bound_meshes: Dictionary = {}
	_heat_materials = _prepare_materials(nodes.HeatPipes, bound_meshes)
	_lamp_materials = _prepare_materials(nodes.StatusLens, bound_meshes)
	if not import_errors.is_empty(): return
	imported = true
	_apply_state()
	_pose_fan()

func set_state(state: Dictionary) -> void:
	var temperature = state.get("temperature", 20.0)
	if typeof(temperature) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(temperature)):
		return
	# Clamp the visual mapping only; never normalize or mutate the entity supplied.
	var next_temperature := clampf(float(temperature), -40.0, 200.0)
	var next_powered := bool(state.get("powered", false))
	if next_temperature == _temperature and next_powered == _powered: return
	_temperature = next_temperature
	_powered = next_powered
	if imported: _apply_state()

func set_animation_paused(value: bool) -> void:
	_animation_paused = value
	# Static temperature/power appearance is deliberately unchanged by pausing.

func _process(delta: float) -> void:
	if not imported or _animation_paused or (is_inside_tree() and get_tree().paused): return
	if not is_finite(delta) or delta <= 0.0 or _fan_speed <= 0.0: return
	_fan_phase = fposmod(_fan_phase + _fan_speed * minf(delta, 0.25), TAU)
	_pose_fan()

func _apply_state() -> void:
	var heat := clampf((_temperature - 20.0) / 50.0, 0.0, 1.0)
	for row in _heat_materials:
		var material: BaseMaterial3D = row.material
		var base: Color = row.albedo
		# Keep authored texture/normal/roughness; warm only the dedicated pipe faces.
		material.albedo_color = base.lerp(Color(0.80, 0.28, 0.09, base.a), heat * 0.22)
		material.emission_enabled = heat > 0.0
		material.emission = Color(1.0, 0.35, 0.08)
		material.emission_energy_multiplier = HEAT_EMISSION_CAP * heat
	for row in _lamp_materials:
		var material: BaseMaterial3D = row.material
		var base: Color = row.albedo
		# The narrow instrument must remain readable at the default 26m camera.
		# Only this lens receives the stronger hue/emission; no extra world light.
		var temperature_color: Color = Color("38d5e6").lerp(Color("ffc247"), heat * 2.0) if heat <= 0.5 else Color("ffc247").lerp(Color("ff5836"), (heat - 0.5) * 2.0)
		# This is a temperature window, not a powered/fault indicator. Multiply
		# the authored lens tint/texture; power loss must not erase retained heat.
		material.albedo_color = base * temperature_color
		material.emission_enabled = true
		material.emission = temperature_color
		material.emission_energy_multiplier = LAMP_EMISSION_CAP * lerpf(0.35, 0.8, heat)
	_fan_speed = lerpf(3.0, 9.0, heat) if _powered else 0.0

func _pose_fan() -> void:
	if not is_instance_valid(_fan): return
	var pose := _fan_rest
	pose.basis = _fan_rest.basis * Basis(_fan_axis, _fan_phase)
	_fan.transform = pose

func _prepare_materials(group: Node3D, bound_meshes: Dictionary) -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	var meshes := _meshes(group)
	if meshes.is_empty(): _fail(str(group.name) + " contains no authored material faces")
	for mesh in meshes:
		if bound_meshes.has(mesh.get_instance_id()):
			_fail("HeatPipes and StatusLens must be independent mesh groups")
			continue
		bound_meshes[mesh.get_instance_id()] = true
		for surface in range(mesh.mesh.get_surface_count()):
			var source := mesh.get_active_material(surface) as BaseMaterial3D
			if source == null:
				_fail(str(group.name) + " needs an imported PBR material at surface " + str(surface))
				continue
			var copy := source.duplicate() as BaseMaterial3D
			mesh.set_surface_override_material(surface, copy)
			rows.append({"material":copy, "albedo":source.albedo_color})
	return rows

func _meshes(node: Node) -> Array[MeshInstance3D]:
	var result: Array[MeshInstance3D] = []
	if node is MeshInstance3D and node.mesh != null: result.append(node)
	for child in node.get_children(): result.append_array(_meshes(child))
	return result

func _fail(message: String) -> void:
	import_errors.append(message)
	push_error("Thermal bypass import: " + message)
