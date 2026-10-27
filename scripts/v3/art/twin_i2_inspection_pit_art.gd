extends RefCounted
## Baked editable pit, mounted over the independently excavated physical pit.
## The original Ground owns all collision; small drain/groove detail is visual.
const SOURCE_MODEL := "res://assets/v3/environment/inspection_pit/inspection_pit.glb"
const MODEL := "res://assets/v3/environment/i2_visual_lod/20261021_021300_adedde/inspection_pit_lod.glb"
const EXPECTED_TRIANGLES := {"FloorAndRamp":1860,"Hardware":3054,"WallConcrete":2460}
const ANCHOR := Vector3(-17.625,0,5.75)
const BOUNDS := AABB(Vector3(-4.375,-2.485,-4.75),Vector3(8.75,2.486,9.5))

static func install(pit: Dictionary) -> Dictionary:
	if not pit.get("ok",false): return {"ok":false,"code":"physical_pit_required"}
	var wrapper: Node3D=pit.get("wrapper")
	if not is_instance_valid(wrapper): return {"ok":false,"code":"pit_required"}
	if wrapper.has_node("AuthoredInspectionPit"): return {"ok":false,"code":"already_installed"}
	var old: Dictionary=pit.get("visuals",{})
	for part: String in ["floor","walls","coping","ramp"]:
		if not is_instance_valid(old.get(part)) or not old[part] is MeshInstance3D or not old[part].visible:
			return {"ok":false,"code":"original_pit_visual_required"}
	var packed:=load(MODEL) as PackedScene
	if packed==null: return {"ok":false,"code":"model_missing"}
	var model:=packed.instantiate() as Node3D
	if model==null: return {"ok":false,"code":"model_root"}
	for kind: String in ["CollisionObject3D","Camera3D","Light3D","AnimationPlayer"]:
		if not model.find_children("*",kind,true,false).is_empty(): return _reject(model,"visual_only_required")
	var meshes:=model.find_children("*","MeshInstance3D",true,false)
	if meshes.size()!=3: return _reject(model,"three_baked_groups_required")
	var bounds:=AABB()
	var first:=true
	var triangles:=0
	var materials: Dictionary={}
	for view: MeshInstance3D in meshes:
		if view.mesh==null: return _reject(model,"mesh_missing")
		if str(view.name) not in EXPECTED_TRIANGLES or view.mesh.get_faces().size()!=int(EXPECTED_TRIANGLES[str(view.name)])*3:
			return _reject(model,"mesh_triangle_contract")
		var authored:=Transform3D.IDENTITY
		var node: Node=view
		while node!=null:
			if node is Node3D: authored=node.transform*authored
			node=node.get_parent()
		if not authored.is_equal_approx(Transform3D.IDENTITY): return _reject(model,"identity_export_required")
		bounds=view.get_aabb() if first else bounds.merge(view.get_aabb())
		first=false
		for surface in view.mesh.get_surface_count():
			var arrays: Array=view.mesh.surface_get_arrays(surface)
			var vertices: PackedVector3Array=arrays[Mesh.ARRAY_VERTEX]
			var indices: PackedInt32Array=arrays[Mesh.ARRAY_INDEX]
			triangles+=int((indices.size() if not indices.is_empty() else vertices.size())/3)
			for point: Vector3 in vertices:
				if not point.is_finite() or not BOUNDS.grow(.00002).has_point(point): return _reject(model,"pit_bounds")
			var material:=view.get_active_material(surface) as BaseMaterial3D
			if material==null or material.transparency!=BaseMaterial3D.TRANSPARENCY_DISABLED or material.albedo_texture==null or material.normal_texture==null or material.roughness_texture==null or material.metallic_texture==null:
				return _reject(model,"baked_opaque_pbr_required")
			materials[material.get_instance_id()]=true
	if triangles!=7374 or materials.size()!=3: return _reject(model,"delivery_changed")
	if bounds.position.distance_to(BOUNDS.position)>.00003 or bounds.size.distance_to(BOUNDS.size)>.00003:
		return _reject(model,"pit_extent_changed")
	model.name="AuthoredInspectionPit"
	model.position=ANCHOR
	wrapper.add_child(model)
	for view: MeshInstance3D in old.values(): view.hide()
	wrapper.set_meta("stage","authored_inspection_pit_not_final_area_art")
	return {"ok":true,"code":"pit_art_installed","model":model,"meshes":meshes,"triangles":triangles,"materials":materials.size(),"source":MODEL}

static func _reject(model: Node,code: String) -> Dictionary:
	model.free()
	return {"ok":false,"code":code}
