extends RefCounted
## Presentation beneath the original solid. No new doorway, collider or device.
const MODEL_PATH := "res://assets/v3/environment/west_service_room/west_service_room.glb"
const ORIGIN := Vector3(-14,0,-8)
const EXTENT := AABB(Vector3(-2,0,-2),Vector3(4,2.5,4))
const PARTS := {"PaintedShell":2376,"ConcreteBase":220,"RoofMetal":1012}

static func install(works: Node3D) -> Dictionary:
	return install_variant(works,"WestLowRoof",MODEL_PATH,ORIGIN,EXTENT,PARTS,"WestServiceRoomArt")

## Same construction contract for the approved low and offset service rooms.
## The production caller supplies constants, never save/network resource paths.
static func install_variant(works: Node3D, body_id: String, model_path: String, origin: Vector3, extent: AABB, parts: Dictionary, model_name: String) -> Dictionary:
	var marker:="authored_room_"+body_id
	if works.is_inside_tree() or works.has_meta(marker):
		return {"ok":false,"code":"service_room_install_before_tree_once"}
	var body := works.fixed_bodies.get(body_id) as StaticBody3D
	if body==null: return {"ok":false,"code":"service_room_original_body_missing"}
	var shape := body.get_node_or_null("ExactBoxCollision") as CollisionShape3D
	var old := body.get_node_or_null("Visual") as MeshInstance3D
	if old==null or shape==null or not shape.shape is BoxShape3D or not shape.transform.is_equal_approx(Transform3D.IDENTITY):
		return {"ok":false,"code":"service_room_original_box_required"}
	if not body.transform.is_equal_approx(Transform3D(Basis.IDENTITY,origin+extent.get_center())) or not shape.shape.size.is_equal_approx(extent.size):
		return {"ok":false,"code":"service_room_layout_changed"}
	var packed := load(model_path) as PackedScene
	if packed==null: return {"ok":false,"code":"service_room_glb_missing"}
	var model := packed.instantiate() as Node3D
	if model==null: return {"ok":false,"code":"service_room_root_type"}
	var checked := _validate(model,extent,parts)
	if not checked.ok:
		model.free()
		return checked
	# Preserve the original body's shape, identity, masks and local placement.
	# Keeping the entire art subtree here gives local camera fading one owner.
	model.name=model_name
	model.position=origin-body.position
	body.add_child(model)
	for mesh: MeshInstance3D in checked.meshes:
		mesh.set_meta("terrain_visibility_single_sided",true)
	old.hide()
	works.set_meta(marker,true)
	return {"ok":true,"code":"service_room_installed","path":model_path,"model":model,
		"body":body,"shape":shape,"model_meshes":checked.meshes,"triangles":checked.triangles,
		"materials":checked.materials,"bounds":checked.bounds,"occluders":[body],
		"collision_policy":"original "+body_id+" body and box unchanged"}

static func _validate(model: Node3D, extent: AABB, parts: Dictionary, expected_materials: int = 3) -> Dictionary:
	for kind: String in ["CollisionObject3D","Camera3D","Light3D","AnimationPlayer"]:
		if not model.find_children("*",kind,true,false).is_empty(): return {"ok":false,"code":"service_room_visual_only"}
	var meshes := model.find_children("*","MeshInstance3D",true,false)
	if meshes.size()!=parts.size(): return {"ok":false,"code":"service_room_mesh_count"}
	var names: Dictionary={}
	var materials: Dictionary={}
	var triangles:=0
	var bounds:=AABB()
	var first:=true
	for mesh: MeshInstance3D in meshes:
		var label:=str(mesh.name)
		if label not in parts or names.has(label) or mesh.mesh==null or mesh.mesh.get_surface_count()!=1:
			return {"ok":false,"code":"service_room_mesh_contract"}
		names[label]=true
		var parent: Node=mesh
		while parent!=null:
			if parent is Node3D and not parent.transform.is_equal_approx(Transform3D.IDENTITY): return {"ok":false,"code":"service_room_identity_export"}
			parent=parent.get_parent()
		var arrays: Array=mesh.mesh.surface_get_arrays(0)
		var vertices: PackedVector3Array=arrays[Mesh.ARRAY_VERTEX]
		var indices: PackedInt32Array=arrays[Mesh.ARRAY_INDEX]
		if vertices.is_empty(): return {"ok":false,"code":"service_room_empty_mesh"}
		var count:=int((indices.size() if not indices.is_empty() else vertices.size())/3)
		if count!=parts[label]: return {"ok":false,"code":"service_room_approved_geometry_changed"}
		triangles+=count
		for point: Vector3 in vertices:
			if not point.is_finite() or not extent.grow(.00003).has_point(point): return {"ok":false,"code":"service_room_outside_original_solid"}
		var material := mesh.get_active_material(0) as BaseMaterial3D
		if material==null or material.transparency!=BaseMaterial3D.TRANSPARENCY_DISABLED or material.albedo_texture==null or material.normal_texture==null or material.roughness_texture==null or material.metallic_texture==null:
			return {"ok":false,"code":"service_room_opaque_pbr_required"}
		materials[material.get_instance_id()]=true
		bounds=mesh.get_aabb() if first else bounds.merge(mesh.get_aabb())
		first=false
	if materials.size()!=expected_materials or not bounds.position.is_equal_approx(extent.position) or not bounds.size.is_equal_approx(extent.size):
		return {"ok":false,"code":"service_room_extent_or_budget"}
	return {"ok":true,"meshes":meshes,"triangles":triangles,"materials":materials.size(),"bounds":bounds}
