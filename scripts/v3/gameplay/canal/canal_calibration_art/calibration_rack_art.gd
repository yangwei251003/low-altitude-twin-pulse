extends RefCounted
## Visual wrapper only. The existing rack owns all contact, collision and work.
const MODEL := "res://assets/v3/environment/canal_calibration_rack/calibration_rack.glb"
const SIZE := Vector3(2.4,.32,2.4)
const LOCAL_BOUNDS := AABB(Vector3(-1.2,0,-1.2),SIZE)
const LOCAL_OFFSET := Vector3(0,-.16,0)

static func install(rack: StaticBody3D) -> Dictionary:
	if not is_instance_valid(rack) or not rack.is_inside_tree() or rack.name != "RepairRack":
		return {"ok":false,"code":"original_live_rack_required"}
	if rack.has_node("AuthoredCalibrationRack"):
		return {"ok":false,"code":"already_installed"}
	var old: MeshInstance3D
	var shapes := 0
	for child: Node in rack.get_children():
		if child is MeshInstance3D and child.mesh is BoxMesh and child.mesh.size.is_equal_approx(SIZE):
			if old != null: return {"ok":false,"code":"ambiguous_old_visual"}
			old = child
	for owner: int in rack.get_shape_owners():
		if rack.is_shape_owner_disabled(owner) or not rack.shape_owner_get_transform(owner).is_equal_approx(Transform3D.IDENTITY):
			return {"ok":false,"code":"original_shape_required"}
		for index in rack.shape_owner_get_shape_count(owner):
			var shape := rack.shape_owner_get_shape(owner,index)
			if not shape is BoxShape3D or not shape.size.is_equal_approx(SIZE):
				return {"ok":false,"code":"original_shape_required"}
			shapes += 1
	if old == null or not old.visible or shapes != 1:
		return {"ok":false,"code":"original_rack_required"}
	var packed := load(MODEL) as PackedScene
	if packed == null: return {"ok":false,"code":"model_missing"}
	var model := packed.instantiate() as Node3D
	if model == null: return {"ok":false,"code":"model_root"}
	for kind: String in ["CollisionObject3D","Camera3D","Light3D","AnimationPlayer"]:
		if not model.find_children("*",kind,true,false).is_empty(): return _reject(model,"visual_only_required")
	var meshes := model.find_children("*","MeshInstance3D",true,false)
	if meshes.is_empty() or meshes.size() > 3: return _reject(model,"mesh_budget")
	var bounds := AABB()
	var first := true
	var triangles := 0
	var materials: Dictionary = {}
	for view: MeshInstance3D in meshes:
		if view.mesh == null: return _reject(model,"mesh_missing")
		var authored := Transform3D.IDENTITY
		var node: Node = view
		while node != null:
			if node is Node3D: authored = node.transform * authored
			node = node.get_parent()
		if not authored.is_equal_approx(Transform3D.IDENTITY): return _reject(model,"identity_export_required")
		var faces := view.mesh.get_faces()
		triangles += int(faces.size()/3)
		for point: Vector3 in faces:
			if not point.is_finite() or not LOCAL_BOUNDS.grow(.00001).has_point(point): return _reject(model,"outside_original_rack")
		bounds = view.get_aabb() if first else bounds.merge(view.get_aabb())
		first = false
		for surface in view.mesh.get_surface_count():
			var material := view.get_active_material(surface) as BaseMaterial3D
			if material == null or material.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED or material.albedo_texture == null or material.normal_texture == null or material.roughness_texture == null or material.metallic_texture == null:
				return _reject(model,"baked_opaque_pbr_required")
			materials[material.get_instance_id()] = true
	if triangles <= 0 or triangles > 20000 or materials.size() > 3:
		return _reject(model,"delivery_budget")
	if bounds.position.distance_to(LOCAL_BOUNDS.position) > .00002 or bounds.size.distance_to(SIZE) > .00002:
		return _reject(model,"rack_size")
	# Atomic visual swap after all checks. Collider, its RID and work binding stay.
	model.name = "AuthoredCalibrationRack"
	model.position = LOCAL_OFFSET
	rack.add_child(model)
	old.hide()
	return {"ok":true,"code":"rack_art_installed","model":model,"meshes":meshes,
		"triangles":triangles,"materials":materials.size(),"source":MODEL}

static func _reject(model: Node, code: String) -> Dictionary:
	model.free()
	return {"ok":false,"code":code}
