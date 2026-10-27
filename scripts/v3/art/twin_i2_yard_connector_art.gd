extends RefCounted
## Continuous authored forecourt. Replaces only its exact visible Y0 surface;
## the existing Ground, pit ramp, facilities and old courtyard remain owned by World.
const Geometry = preload("res://scripts/v3/art/twin_i2_yard_partition.gd")
const MODEL := "res://assets/v3/environment/yard_connector/yard_connector_field.glb"
const SOURCE_SHA := "fad898d7e9f55191ba8f82fe0c761b9f43037c329303c1c98b379e7d42fb6631"
const VISIBLE_AREA := 296.5806327
const BOUNDS := AABB(Vector3(-18.299999237,-.014999999665,-8.75),Vector3(36.25,.014999999665,17.5))
const PARTS := {"ConcreteSurface":370,"SoilSurface":136,"LocalDetails":696}

static func install(world: Node3D) -> Dictionary:
	if not world.find_children("YardConnectorField","Node3D",true,false).is_empty(): return {"ok":false,"code":"already_installed"}
	var cut: Dictionary=Geometry.collect(world)
	if not cut.ok: return cut
	if cut.report.source_attributes_sha256!=SOURCE_SHA or absf(cut.report.visible_replacement_m2-VISIBLE_AREA)>.0005:
		return {"ok":false,"code":"approved_yard_footprint_changed"}
	var packed:=load(MODEL) as PackedScene
	if packed==null: return {"ok":false,"code":"yard_model_missing"}
	var model:=packed.instantiate() as Node3D
	if model==null: return {"ok":false,"code":"yard_model_root"}
	var checked: Dictionary=_validate_model(model)
	if not checked.ok:
		model.free()
		return checked
	var dry: MeshInstance3D=world.waterfront_install.meshes.dry_surface
	var remainder: ArrayMesh=Geometry.Reader._make_mesh(cut.remainder,"continuous yard remainder")
	remainder.surface_set_material(0,dry.mesh.surface_get_material(0))
	# Nothing live changes until the exact source and all imported groups pass.
	model.name="YardConnectorField"
	model.position=Geometry.ORIGIN
	dry.get_parent().add_child(model)
	dry.mesh=remainder
	return {"ok":true,"code":"continuous_yard_installed","model":model,"meshes":checked.meshes,
		"triangles":1202,"materials":3,"source":MODEL,"removed_area_m2":cut.report.visible_replacement_m2,
		"remaining_area_m2":cut.report.retained_m2,"preserved_structural_ground_m2":cut.report.retained_under_structures_m2,
		"original_collision_sha256":cut.report.ground_collision_sha256,"collision_unchanged":true,
		"remaining_visual":cut.remainder.duplicate(true)}

static func _validate_model(model: Node3D) -> Dictionary:
	for kind: String in ["CollisionObject3D","Camera3D","Light3D","AnimationPlayer"]:
		if not model.find_children("*",kind,true,false).is_empty(): return {"ok":false,"code":"yard_visual_only_required"}
	var meshes:=model.find_children("*","MeshInstance3D",true,false)
	if meshes.size()!=3: return {"ok":false,"code":"yard_three_material_groups"}
	var names: Dictionary={}
	var materials: Dictionary={}
	var bounds:=AABB()
	var first:=true
	for view: MeshInstance3D in meshes:
		var label:=str(view.name)
		if not PARTS.has(label) or names.has(label) or view.mesh==null or view.mesh.get_surface_count()!=1:
			return {"ok":false,"code":"yard_mesh_contract"}
		names[label]=true
		var node: Node=view
		while node!=null:
			if node is Node3D and not node.transform.is_equal_approx(Transform3D.IDENTITY): return {"ok":false,"code":"yard_identity_export_required"}
			node=node.get_parent()
		var arrays: Array=view.mesh.surface_get_arrays(0)
		var vertices: PackedVector3Array=arrays[Mesh.ARRAY_VERTEX]
		var indices: PackedInt32Array=arrays[Mesh.ARRAY_INDEX]
		if int((indices.size() if not indices.is_empty() else vertices.size())/3)!=PARTS[label]: return {"ok":false,"code":"yard_triangle_contract"}
		for point: Vector3 in vertices:
			if not point.is_finite() or not BOUNDS.grow(.00003).has_point(point): return {"ok":false,"code":"yard_vertex_bounds"}
		var material:=view.get_active_material(0) as BaseMaterial3D
		if material==null or material.transparency!=BaseMaterial3D.TRANSPARENCY_DISABLED or material.albedo_texture==null or material.normal_texture==null or material.roughness_texture==null or material.metallic_texture==null:
			return {"ok":false,"code":"yard_baked_opaque_pbr_required"}
		materials[material.get_instance_id()]=true
		bounds=view.get_aabb() if first else bounds.merge(view.get_aabb())
		first=false
	if materials.size()!=3 or bounds.position.distance_to(BOUNDS.position)>.00004 or bounds.size.distance_to(BOUNDS.size)>.00004:
		return {"ok":false,"code":"yard_extent_or_materials"}
	return {"ok":true,"meshes":meshes}
