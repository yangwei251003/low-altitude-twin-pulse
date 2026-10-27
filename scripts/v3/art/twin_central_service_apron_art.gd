extends RefCounted
## Exact complementary visual replacement after the installed I2 yard.
## World keeps the same Ground body, shape, pit/ramp and facility colliders.
const Reader = preload("res://scripts/v3/art/twin_i2_east_revetment_art.gd")
const Split = preload("res://scripts/v3/art/twin_i2_revetment_partition.gd")
const MODEL_PATH := "res://assets/v3/environment/central_service_apron/central_service_apron.glb"
const PLAN_PATH := "res://assets/v3/environment/central_service_apron/central_service_partition.json"
const ORIGIN := Vector3(-2.425,0,.25)

static func install(world: Node3D) -> Dictionary:
	if not world.is_inside_tree() or not world.yard_connector_art.get("ok",false): return _fail("installed_live_yard_required")
	if world.has_meta("central_service_apron"): return _fail("apron_install_once")
	var plan: Variant = JSON.parse_string(FileAccess.get_file_as_string(PLAN_PATH))
	if not plan is Dictionary or plan.get("version",0)!=1: return _fail("apron_partition_missing")
	var dry: MeshInstance3D = world.waterfront_install.meshes.dry_surface
	if not dry.visible or not dry.global_transform.is_equal_approx(Transform3D.IDENTITY): return _fail("dry_world_identity_required")
	var read: Dictionary = Reader._read_mesh(dry.mesh)
	if not read.ok or Reader._attributes_sha(read.geometry)!=plan.source_attributes_sha256: return _fail("approved_dry_input_changed")
	var collider: CollisionShape3D = world.waterfront_install.shape_node
	var collision := collider.shape as ConcavePolygonShape3D
	if collision==null or Split._sha(collision.get_faces().to_byte_array())!=plan.ground_collision_sha256: return _fail("original_ground_required")
	var packed := load(MODEL_PATH) as PackedScene
	if packed==null: return _fail("apron_model_missing")
	var model := packed.instantiate() as Node3D
	if model==null: return _fail("apron_model_root")
	var checked: Dictionary = _validate(model,plan)
	if not checked.ok:
		model.free()
		return checked
	var geometry := {"faces":PackedVector3Array(),"normals":PackedVector3Array(),"uv":PackedVector2Array(),"tangents":PackedFloat32Array()}
	for key: String in ["faces","normals"]:
		for p: Array in plan.geometry[key]: geometry[key].append(Vector3(float(p[0]),float(p[1]),float(p[2])))
	for p: Array in plan.geometry.uv: geometry.uv.append(Vector2(float(p[0]),float(p[1])))
	for p: Array in plan.geometry.tangents:
		for v: float in p: geometry.tangents.append(v)
	if not Split._validate(geometry).ok or geometry.tangents.size()!=geometry.faces.size()*4 or absf(Split._area(geometry)-float(plan.retained_area_m2))>.0005:
		model.free()
		return _fail("apron_complementary_surface_invalid")
	var remaining: ArrayMesh = Reader._make_mesh(geometry,"central apron retained ground")
	remaining.surface_set_material(0,dry.mesh.surface_get_material(0))
	# All validation precedes these two visual writes. No body or shape is edited.
	model.name = "CentralServiceApron"
	model.position = ORIGIN
	dry.get_parent().add_child(model)
	dry.mesh = remaining
	world.set_meta("central_service_apron",true)
	return {"ok":true,"code":"central_service_apron_installed","model":model,"meshes":checked.meshes,"triangles":1148,
		"materials":3,"removed_area_m2":plan.replacement_area_m2,"collision_unchanged":true,"remaining_visual":geometry,
		"original_collision_sha256":plan.ground_collision_sha256,"source":MODEL_PATH}

static func _validate(model: Node3D,plan: Dictionary) -> Dictionary:
	for kind: String in ["CollisionObject3D","Camera3D","Light3D","AnimationPlayer"]:
		if not model.find_children("*",kind,true,false).is_empty(): return _fail("apron_visual_only_required")
	var meshes := model.find_children("*","MeshInstance3D",true,false)
	if meshes.size()!=3: return _fail("apron_three_groups")
	var names: Dictionary = {}
	for mesh: MeshInstance3D in meshes:
		var label := str(mesh.name)
		if not plan.mesh_triangles.has(label) or names.has(label) or mesh.mesh==null or mesh.mesh.get_surface_count()!=1: return _fail("apron_group_contract")
		names[label] = true
		var cursor: Node = mesh
		while cursor!=null:
			if cursor is Node3D and not cursor.transform.is_equal_approx(Transform3D.IDENTITY): return _fail("apron_identity_required")
			cursor = cursor.get_parent()
		var arrays: Array = mesh.mesh.surface_get_arrays(0)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		if int((indices.size() if not indices.is_empty() else vertices.size())/3)!=int(plan.mesh_triangles[label]): return _fail("apron_triangle_count")
		for point: Vector3 in vertices:
			if not point.is_finite() or point.y!=0: return _fail("apron_flat_original_plane")
		var mat := mesh.get_active_material(0) as BaseMaterial3D
		if mat==null or mat.transparency!=BaseMaterial3D.TRANSPARENCY_DISABLED: return _fail("apron_opaque_material")
		if label!="ApronJoint":
			if mat.albedo_texture==null or mat.normal_texture==null or mat.roughness_texture==null or mat.metallic_texture==null: return _fail("apron_shared_pbr_maps")
	return {"ok":true,"meshes":meshes}

static func _fail(code: String) -> Dictionary:
	return {"ok":false,"code":code}
