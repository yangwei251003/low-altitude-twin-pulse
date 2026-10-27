extends RefCounted
## Two imported visual groups remain owned by the two original collision bodies.
const MODEL_PATH := "res://assets/v3/environment/west_landing_platform/west_landing_platform.glb"
const ORIGIN := Vector3(-6,0,-4)
const GROUPS := {
	"PlatformAssembly":{"body":"WestLanding","extent":AABB(Vector3(-4,4.6,-2),Vector3(8,.4,4)),"parts":{"PlatformSteel":672,"PlatformPaint":660}},
	"LegAssembly":{"body":"WestLandingLeg","extent":AABB(Vector3(-3.6,0,1),Vector3(.5,4.6,.5)),"parts":{"LegSteel":960,"LegPaint":836}}
}

static func install(works: Node3D) -> Dictionary:
	if works.is_inside_tree() or works.has_meta("authored_west_landing"):
		return {"ok":false,"code":"west_landing_install_before_tree_once"}
	var packed := load(MODEL_PATH) as PackedScene
	if packed==null: return {"ok":false,"code":"west_landing_glb_missing"}
	var model := packed.instantiate() as Node3D
	if model==null: return {"ok":false,"code":"west_landing_root_type"}
	var checked := _validate(works,model)
	if not checked.ok:
		model.free()
		return checked
	# Validate everything first. Never move the physical bodies or replace their
	# shapes; detached visual groups inherit the common GLB coordinate origin.
	var records: Array=[]
	for row: Dictionary in checked.groups:
		var group: Node3D=row.group
		group.owner=null
		group.get_parent().remove_child(group)
		row.body.add_child(group)
		group.position=ORIGIN-row.body.position
		for mesh: MeshInstance3D in row.meshes:
			mesh.set_meta("terrain_visibility_single_sided",true)
		row.body.get_node("Visual").hide()
		records.append(row)
	model.free()
	works.set_meta("authored_west_landing",true)
	return {"ok":true,"code":"west_landing_installed","path":MODEL_PATH,
		"source_scene":packed,"groups":records,"model_meshes":checked.meshes,
		"triangles":3128,"materials":2,"occluders":records.map(func(row: Dictionary): return row.body),
		"collision_policy":"original WestLanding and WestLandingLeg boxes unchanged; no filled bridge void"}

static func _validate(works: Node3D, model: Node3D) -> Dictionary:
	# Godot adds an identity scene root around the named glTF root.
	var authored := model.get_node_or_null("WestLandingPlatform") as Node3D
	if not model.transform.is_equal_approx(Transform3D.IDENTITY) or model.get_child_count()!=1 or authored==null or not authored.transform.is_equal_approx(Transform3D.IDENTITY) or authored.get_child_count()!=GROUPS.size():
		return {"ok":false,"code":"west_landing_root_contract"}
	for kind: String in ["CollisionObject3D","Camera3D","Light3D","AnimationPlayer"]:
		if not model.find_children("*",kind,true,false).is_empty(): return {"ok":false,"code":"west_landing_visual_only"}
	var records: Array=[]
	var all_meshes: Array=[]
	var materials: Dictionary={}
	for label: String in GROUPS:
		var spec: Dictionary=GROUPS[label]
		var extent: AABB=spec.extent
		var body := works.fixed_bodies.get(spec.body) as StaticBody3D
		if body==null: return {"ok":false,"code":"west_landing_original_body_missing:"+str(spec.body)}
		var shape := body.get_node_or_null("ExactBoxCollision") as CollisionShape3D
		var old := body.get_node_or_null("Visual") as MeshInstance3D
		if old==null or shape==null or not shape.shape is BoxShape3D or not shape.transform.is_equal_approx(Transform3D.IDENTITY):
			return {"ok":false,"code":"west_landing_original_box_required"}
		if not body.transform.is_equal_approx(Transform3D(Basis.IDENTITY,ORIGIN+extent.get_center())) or not shape.shape.size.is_equal_approx(extent.size):
			return {"ok":false,"code":"west_landing_layout_changed"}
		var group := authored.get_node_or_null(NodePath(label)) as Node3D
		if group==null or not group.transform.is_equal_approx(Transform3D.IDENTITY) or group.get_child_count()!=spec.parts.size():
			return {"ok":false,"code":"west_landing_group_contract:"+label}
		var meshes: Array=[]
		var bounds:=AABB()
		var first:=true
		for part: String in spec.parts:
			var mesh := group.get_node_or_null(NodePath(part)) as MeshInstance3D
			if mesh==null or mesh.mesh==null or mesh.mesh.get_surface_count()!=1 or mesh.get_child_count()!=0 or not mesh.transform.is_equal_approx(Transform3D.IDENTITY):
				return {"ok":false,"code":"west_landing_mesh_contract:"+part}
			var arrays: Array=mesh.mesh.surface_get_arrays(0)
			var vertices: PackedVector3Array=arrays[Mesh.ARRAY_VERTEX]
			var indices: PackedInt32Array=arrays[Mesh.ARRAY_INDEX]
			if vertices.is_empty() or int((indices.size() if not indices.is_empty() else vertices.size())/3)!=int(spec.parts[part]):
				return {"ok":false,"code":"west_landing_approved_geometry_changed:"+part}
			for point: Vector3 in vertices:
				# Each group must stay inside its own solid, not the combined AABB.
				if not point.is_finite() or not extent.grow(.00003).has_point(point):
					return {"ok":false,"code":"west_landing_outside_original_solid:"+part}
			var material := mesh.get_active_material(0) as BaseMaterial3D
			if material==null or material.transparency!=BaseMaterial3D.TRANSPARENCY_DISABLED or material.albedo_texture==null or material.normal_texture==null or material.roughness_texture==null or material.metallic_texture==null:
				return {"ok":false,"code":"west_landing_opaque_pbr_required:"+part}
			materials[material.get_instance_id()]=true
			bounds=mesh.get_aabb() if first else bounds.merge(mesh.get_aabb())
			first=false
			meshes.append(mesh)
		if not bounds.position.is_equal_approx(extent.position) or not bounds.size.is_equal_approx(extent.size):
			return {"ok":false,"code":"west_landing_extent_changed:"+label}
		all_meshes.append_array(meshes)
		records.append({"id":spec.body,"group":group,"body":body,"shape":shape,"meshes":meshes,"bounds":bounds})
	if materials.size()!=2: return {"ok":false,"code":"west_landing_shared_material_budget"}
	return {"ok":true,"groups":records,"meshes":all_meshes}
