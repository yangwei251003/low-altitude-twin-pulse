class_name TwinMaintenancePavingArt
extends RefCounted
## Eight purpose-specific source variants share one atlas. The runtime keeps
## the original Y0 collision; shallow seams and lifting recesses are decoration.
const MODEL_PATH := "res://assets/v3/i2_maintenance_paving/maintenance_paving.glb"
const REGION := Rect2(14.5,-14,10,16)
const VARIANTS := {"W0":3020,"W1":3124,"W2":2820,"W3":3004,
	"E0":520,"E1":464,"E2":520,"E3":808}

static func build() -> Dictionary:
	var packed := load(MODEL_PATH) as PackedScene
	if packed == null: return {"ok":false,"code":"maintenance_glb_missing"}
	var wrapper := Node3D.new()
	wrapper.name = "MaintenanceAuthoredPaving"
	var records: Array = []
	var materials := {}
	var total := 0
	var mesh_count := 0
	for id: String in VARIANTS:
		var model := packed.instantiate() as Node3D
		if model == null: return _reject(wrapper,"maintenance_root_type")
		wrapper.add_child(model)
		var selected := model.find_child("MaintenancePaving_"+id,true,false) as Node3D
		if selected == null: return _reject(wrapper,"maintenance_variant_missing:"+id)
		for other: String in VARIANTS:
			var sibling := model.find_child("MaintenancePaving_"+other,true,false) as Node3D
			if sibling == null or sibling.get_parent() != selected.get_parent(): return _reject(wrapper,"maintenance_variant_hierarchy")
		for other: String in VARIANTS:
			if other != id: model.find_child("MaintenancePaving_"+other,true,false).free()
		if not model.find_children("*","CollisionObject3D",true,false).is_empty() or not model.find_children("*","Camera3D",true,false).is_empty() or not model.find_children("*","Light3D",true,false).is_empty():
			return _reject(wrapper,"maintenance_export_contract")
		var meshes := model.find_children("*","MeshInstance3D",true,false)
		if meshes.size() != (2 if id.begins_with("W") else 1): return _reject(wrapper,"maintenance_part_count:"+id)
		var bounds := AABB()
		var first := true
		var count := 0
		for mesh: MeshInstance3D in meshes:
			if mesh.mesh == null or mesh.mesh.get_surface_count() != 1: return _reject(wrapper,"maintenance_surface_contract")
			var ancestor: Node = mesh
			while ancestor != null:
				if ancestor is Node3D and not ancestor.transform.is_equal_approx(Transform3D.IDENTITY): return _reject(wrapper,"maintenance_nonidentity")
				ancestor = ancestor.get_parent()
			count += int(mesh.mesh.get_faces().size()/3)
			bounds = mesh.get_aabb() if first else bounds.merge(mesh.get_aabb())
			first = false
			var material := mesh.get_active_material(0) as BaseMaterial3D
			if material == null or material.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED or material.albedo_texture == null or material.normal_texture == null or material.roughness_texture == null or material.metallic_texture == null:
				return _reject(wrapper,"maintenance_pbr")
			materials[material.get_instance_id()] = true
		if count != int(VARIANTS[id]) or not bounds.position.is_equal_approx(Vector3(-2.5,-.18,-2)) or not bounds.end.is_equal_approx(Vector3(2.5,0,2)):
			return _reject(wrapper,"maintenance_geometry:"+id)
		var at := Vector3(17 if id.begins_with("W") else 22,0,-12+int(id.right(1))*4)
		model.name = "Maintenance_"+id
		model.position = at
		total += count
		mesh_count += meshes.size()
		records.append({"id":id,"model":model,"meshes":meshes,"triangles":count,
			"bounds":AABB(at+Vector3(-2.5,-.18,-2),Vector3(5,.18,4))})
	if total != 14280 or materials.size() != 1: return _reject(wrapper,"maintenance_shared_material_geometry")
	return {"ok":true,"code":"maintenance_paving_ready","path":MODEL_PATH,
		"wrapper":wrapper,"tiles":records,"mesh_count":mesh_count,"triangles":total,
		"region":REGION,"area_m2":160.0,"material_count":materials.size()}

static func _reject(wrapper: Node, code: String) -> Dictionary:
	wrapper.free()
	return {"ok":false,"code":code}
