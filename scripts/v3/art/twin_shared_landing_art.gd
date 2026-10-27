class_name TwinSharedLandingArt
extends RefCounted
## Static presentation bound to six original fixed bodies. No collision or saved state changes.
const MODEL_PATH := "res://assets/v3/shared_access_landings/shared_access_landings.glb"
const ORIGIN := Vector3(15,5,0)
const PARTS := {"WestLanding":2660, "EastLanding":2660, "SouthBypass":1200,
    "WestOuterRail":2736, "EastOuterRail":2736, "SouthOuterRail":1916}

static func install(bridge: Node3D) -> Dictionary:
	if bridge.is_inside_tree() or not bridge.configured or bridge.has_meta("authored_fixed_landings"):
		return {"ok":false,"code":"landing_art_before_tree_once"}
	var layout: Dictionary = bridge.layout()
	var specs := {}
	for spec: Dictionary in layout.fixed:
		if PARTS.has(str(spec.id)): specs[str(spec.id)] = spec
	if specs.size() != PARTS.size() or not bridge.status().pose_valid:
		return {"ok":false,"code":"landing_art_authority_contract"}
	var packed := load(MODEL_PATH) as PackedScene
	if packed == null: return {"ok":false,"code":"landing_art_glb_missing"}
	var model := packed.instantiate() as Node3D
	if model == null: return {"ok":false,"code":"landing_art_root_type"}
	var meshes := model.find_children("*","MeshInstance3D",true,false)
	if meshes.size() != PARTS.size() or not model.find_children("*","CollisionObject3D",true,false).is_empty() or not model.find_children("*","Camera3D",true,false).is_empty() or not model.find_children("*","Light3D",true,false).is_empty() or not model.find_children("*","AnimationPlayer",true,false).is_empty():
		return _reject(model,"landing_art_export_contract")
	var selected := {}
	var materials := {}
	var triangles := 0
	# Complete validation before touching any authority body or its graybox.
	for mesh: MeshInstance3D in meshes:
		var id := str(mesh.name)
		if not PARTS.has(id) or not specs.has(id) or selected.has(id) or mesh.mesh == null or mesh.mesh.get_surface_count() != 2:
			return _reject(model,"landing_art_part:"+id)
		var spec: Dictionary = specs[id]
		var body: StaticBody3D = bridge.fixed_bodies.get(id)
		if body == null or body.get_node_or_null("Visual") == null:
			return _reject(model,"landing_art_body:"+id)
		var authored := Transform3D.IDENTITY
		var node: Node = mesh
		while node != null:
			if node is Node3D:
				if not node.basis.is_equal_approx(Basis.IDENTITY): return _reject(model,"landing_art_scaled_or_rotated:"+id)
				authored = node.transform * authored
			node = node.get_parent()
		var center := Vector3(spec.center[0],spec.center[1],spec.center[2])
		var size := Vector3(spec.size[0],spec.size[1],spec.size[2])
		var bounds := AABB(center-size*.5,size).grow(.0005)
		var faces := mesh.mesh.get_faces()
		var count := int(faces.size()/3)
		if count != int(PARTS[id]): return _reject(model,"landing_art_triangles:"+id)
		for vertex: Vector3 in faces:
			if not bounds.has_point(ORIGIN + authored * vertex): return _reject(model,"landing_art_outside_body:"+id)
		for surface in mesh.mesh.get_surface_count():
			var material := mesh.get_active_material(surface) as BaseMaterial3D
			if material == null or material.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED or material.albedo_texture == null or material.normal_texture == null or material.roughness_texture == null or material.metallic_texture == null:
				return _reject(model,"landing_art_pbr:"+id)
			materials[material.get_instance_id()] = true
		selected[id] = {"mesh":mesh,"body":body,
			"local":Transform3D(Basis.IDENTITY,ORIGIN-center)*authored,
			"authored":authored,"center":center}
		triangles += count
	if triangles != 13908 or materials.size() != 2: return _reject(model,"landing_art_geometry_material_count")
	var records: Array = []
	for id: String in selected:
		var item: Dictionary = selected[id]
		var mesh: MeshInstance3D = item.mesh
		mesh.owner = null
		mesh.get_parent().remove_child(mesh)
		item.body.add_child(mesh)
		mesh.transform = item.local
		# Closed details must not accumulate double-sided alpha layers below the
		# deck. Protected physical-edge cues on the old bodies remain opaque.
		mesh.set_meta("terrain_visibility_single_sided",true)
		item.body.get_node("Visual").hide()
		records.append({"id":id,"mesh":mesh,"body":item.body,"authored":item.authored,
			"author_center":item.center,"local":item.local,"triangles":PARTS[id]})
	model.free()
	bridge.set_meta("authored_fixed_landings",true)
	return {"ok":true,"code":"landing_art_installed","path":MODEL_PATH,
		"triangles":triangles,"mesh_count":meshes.size(),"material_count":materials.size(),
		"model_meshes":meshes,"parts":records,
		"collision_policy":"six existing fixed bodies unchanged; moving bridge, targets, routes and saved state preserved"}

static func _reject(model: Node, code: String) -> Dictionary:
	model.free()
	return {"ok":false,"code":code}
