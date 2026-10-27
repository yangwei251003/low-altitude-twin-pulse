extends Node3D
const FinalBossVisuals = preload("res://scripts/v3/content/final_presentation/twin_final_boss_visuals.gd")
## Shared low-cost presentation and real hit targets for the six later bosses.
## Session owns combat/Store. Layout owns floors and cover; this owns no clocks.
var definition: Dictionary = {}
var targets: Dictionary = {}
var definitions: Dictionary = {}
var _meshes: Dictionary = {}
var _materials: Dictionary = {}
var _warning: Node3D
var _warning_key := ""
var _centre := Vector3.ZERO
var _fantasy := false

func configure(spec: Dictionary, centre: Vector3) -> Dictionary:
	if not definition.is_empty() or not spec.get("parts") is Array or not centre.is_finite(): return {"ok":false,"code":"fresh_arena_spec_required"}
	definition = spec.duplicate(true)
	_centre = centre
	_fantasy = str(spec.region_id).begins_with("F")
	name = "Arena_" + str(spec.id)
	var ids: Array = spec.parts.duplicate()
	ids.append("core")
	for index in range(ids.size()):
		var part: String = str(ids[index])
		var id := target_id(part)
		var body := StaticBody3D.new()
		body.name = part
		body.collision_layer = 8
		body.collision_mask = 0
		body.set_meta("entity_id", id)
		body.position = centre + (Vector3(0, 1, 0) if part == "core" else Vector3((index - (spec.parts.size()-1)*.5)*5.2, -1.0 + index*1.8, 1.7))
		# Keep the real charge-return hit sphere clear of the breaker's full
		# travel. The breaker retains the authored closed/open physical poses.
		if spec.region_id == "F4" and part == "charge_return": body.position.x -= 2.0
		add_child(body)
		var collision := CollisionShape3D.new()
		var shape := SphereShape3D.new()
		shape.radius = 1.55 if part == "core" else 1.25
		collision.shape = shape
		body.add_child(collision)
		var material := StandardMaterial3D.new()
		material.albedo_color = Color("697b63") if _fantasy else Color("4e6970")
		material.roughness = .88
		var mesh := MeshInstance3D.new()
		if _fantasy:
			var cone := CylinderMesh.new()
			cone.top_radius = .25 if part == "core" else 1.4
			cone.bottom_radius = 1.45 if part == "core" else .6
			cone.height = 2.5
			cone.radial_segments = 7
			mesh.mesh = cone
		else:
			var box := BoxMesh.new()
			box.size = Vector3(2.3,2.2,2.4)
			mesh.mesh = box
		mesh.material_override = material
		body.add_child(mesh)
		# Distinct silhouettes remain readable from the fixed camera.
		for fin_index in range(3):
			var fin := MeshInstance3D.new()
			var box := BoxMesh.new()
			box.size = Vector3(.28, 1.3 + fin_index*.25, 2.7)
			fin.mesh = box
			fin.position.x = (fin_index-1)*.7
			fin.rotation.z = (fin_index-1)*.3 if _fantasy else 0.0
			fin.material_override = material
			body.add_child(fin)
		targets[id] = body
		_meshes[id] = mesh
		_materials[id] = material
		definitions[id] = {"id":id,"name":str(spec.name) + " · " + _part_label(part),"position":body.position,"tags":["enemy"],"revision":0,"owner":"world"}
	return {"ok":true,"code":"arena_targets_built"}

func target_id(part: String) -> String:
	return "campaign:" + str(definition.get("region_id", "")) + ":" + part

func part_id(id: String) -> String:
	return id.trim_prefix("campaign:" + str(definition.get("region_id", "")) + ":") if targets.has(id) else ""

func centre() -> Vector3:
	return _centre

func apply_view(state: Dictionary, open_parts: Array, defeated: bool) -> void:
	for id: String in targets:
		var part := part_id(id)
		var hp: int = int(state.get("core_hp_milli", 1)) if part == "core" else int(state.get("parts", {}).get(part, 1))
		var body: StaticBody3D = targets[id]
		body.collision_layer = 0 if defeated or hp <= 0 else 8
		body.visible = not defeated
		var material: StandardMaterial3D = _materials[id]
		material.albedo_color = Color("48534e") if hp <= 0 else (Color("e2b957") if part in open_parts else (Color("697b63") if _fantasy else Color("4e6970")))
		material.emission_enabled = part in open_parts and not defeated
		material.emission = Color("e79e46")
		material.emission_energy_multiplier = .35
	show_warning(state)
	FinalBossVisuals.apply_view(self, state, open_parts, defeated)

func show_warning(state: Dictionary) -> void:
	var stage: String = str(state.get("attack_stage", ""))
	var attack: Dictionary = state.get("attack", {})
	var key: String = str(attack.get("token", "")) + ":" + stage
	if key == _warning_key: return
	_warning_key = key
	if is_instance_valid(_warning): _warning.free()
	_warning = null
	if stage not in ["warning", "active"] or attack.is_empty(): return
	_warning = Node3D.new()
	_warning.name = "LockedAttackWarning"
	add_child(_warning)
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(1,.34,.16,.24 if stage == "warning" else .48)
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	for shape: Dictionary in attack.get("shapes", []):
		var p: Array = shape.centre_mm
		var centre := Vector3(float(p[0]),0,float(p[2]))/1000.0
		var bottom := float(shape.y_min_mm)/1000.0
		var top := float(shape.y_max_mm)/1000.0
		if shape.kind == "lane":
			var box := BoxMesh.new()
			box.size = Vector3(float(shape.width_mm), (top-bottom)*1000.0, float(shape.length_mm))/1000.0
			if shape.axis == "x": box.size = Vector3(box.size.z,box.size.y,box.size.x)
			var mesh := MeshInstance3D.new()
			mesh.mesh = box
			mesh.position = centre + Vector3.UP*(bottom+top)*.5
			mesh.material_override = material
			_warning.add_child(mesh)
		else:
			var outer := float(shape.outer_mm)/1000.0
			var inner := float(shape.get("inner_mm",0))/1000.0
			for radius: float in [outer,inner]:
				if radius <= 0: continue
				for elevation: float in [bottom,top]:
					var mesh := MeshInstance3D.new()
					var ring := TorusMesh.new()
					ring.inner_radius = maxf(.01,radius-.08)
					ring.outer_radius = radius+.08
					ring.rings = 32
					ring.ring_segments = 4
					mesh.mesh = ring
					mesh.position = centre + Vector3.UP*elevation
					mesh.material_override = material
					_warning.add_child(mesh)

static func _part_label(part: String) -> String:
	return {"core":"核心","low_pump":"低位泵","high_pump":"高位泵","true_left_wing":"左真翼","true_right_wing":"右真翼",
		"radiator_west":"西散热片","radiator_east":"东散热片","west_voice":"西声簇","upper_voice":"高声簇","east_voice":"东声簇",
		"west_prism":"西棱镜","east_prism":"东棱镜","charge_return":"电荷回流","thermal_return":"热量回流","living_return":"活脉回流"}.get(part,part)
