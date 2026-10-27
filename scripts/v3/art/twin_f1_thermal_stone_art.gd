extends Node3D
## Presentation only. The existing F1:thermal owns interaction, temperature,
## save/network state, identity and its original solid 3x2x2 collision box.
const MODEL_PATH := "res://assets/v3/environment/f1_thermal_stone/f1_thermal_stone.glb"
const EXTENT := AABB(Vector3(-1.5,0,-1),Vector3(3,2,2))
var imported := false
var import_errors: Array[String] = []
var visual: Node3D
var _temperature := 20.0
var _state_materials: Array[Dictionary] = []

func _ready() -> void:
	var packed := load(MODEL_PATH) as PackedScene
	if packed == null:
		_fail("thermal_stone_glb_missing")
		return
	visual = packed.instantiate() as Node3D
	if visual == null:
		_fail("thermal_stone_visual_root")
		return
	for kind: String in ["CollisionObject3D","Camera3D","Light3D","AnimationPlayer"]:
		if not visual.find_children("*",kind,true,false).is_empty(): _fail("visual_only_required:"+kind)
	var meshes := visual.find_children("*","MeshInstance3D",true,false)
	var triangle_count := 0
	var names: Dictionary = {}
	for mesh: MeshInstance3D in meshes:
		if mesh.mesh == null or mesh.mesh.get_surface_count()!=1:
			_fail("single_surface_required")
			continue
		names[str(mesh.name)] = true
		var cursor: Node = mesh
		while cursor != null:
			if cursor is Node3D and not cursor.transform.is_equal_approx(Transform3D.IDENTITY): _fail("identity_required")
			cursor = cursor.get_parent()
		var arrays: Array = mesh.mesh.surface_get_arrays(0)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		triangle_count += int((indices.size() if not indices.is_empty() else vertices.size())/3)
		for point: Vector3 in vertices:
			if not point.is_finite() or not EXTENT.grow(.00002).has_point(point): _fail("source_box_exceeded")
		var mat := mesh.get_active_material(0) as BaseMaterial3D
		if mat == null or mat.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED:
			_fail("opaque_material_required")
			continue
		if str(mesh.name) in ["TemperatureCore","HeatInlays"]:
			var copy := mat.duplicate() as BaseMaterial3D
			copy.vertex_color_use_as_albedo = true
			mesh.set_surface_override_material(0,copy)
			_state_materials.append({"material":copy,"neutral":mat.albedo_color,"core":str(mesh.name)=="TemperatureCore"})
		elif mat.albedo_texture==null or mat.roughness_texture==null or mat.normal_texture==null:
			_fail("static_baked_pbr_required")
	if meshes.size()!=5 or names.size()!=5 or triangle_count!=7896 or _state_materials.size()!=2: _fail("five_group_contract")
	if not import_errors.is_empty():
		visual.free()
		visual = null
		return
	add_child(visual)
	imported = true
	_apply_temperature()

func set_state(state: Dictionary) -> void:
	var raw: Variant = state.get("temperature",20.0)
	if typeof(raw) not in [TYPE_INT,TYPE_FLOAT] or not is_finite(float(raw)): return
	_temperature = clampf(float(raw),-40,200)
	if imported: _apply_temperature()

func set_animation_paused(_paused: bool) -> void:
	pass # No ambient animation or independent clock belongs to this static stone.

func _apply_temperature() -> void:
	var warmth := clampf((_temperature-20.0)/50.0,0,1)
	var tint := Color(.10,.62,.65).lerp(Color(.65,.40,.12),warmth*2) if warmth<=.5 else Color(.65,.40,.12).lerp(Color(.82,.18,.055),(warmth-.5)*2)
	for row: Dictionary in _state_materials:
		var mat: BaseMaterial3D = row.material
		mat.albedo_color = row.neutral*tint
		mat.emission_enabled = true
		mat.emission = tint
		mat.emission_energy_multiplier = lerpf(.10,.22,warmth) if row.core else lerpf(.05,.12,warmth)

func _fail(code: String) -> void:
	if code not in import_errors: import_errors.append(code)
	push_error("F1 thermal stone: "+code)
