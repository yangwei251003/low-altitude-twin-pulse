class_name TwinClinicReceptionArt
extends RefCounted
## Editable GLB shells wrap the unchanged authority-owned physical module.
## Covers are identity in Works space: neither a cutaway nor an import changes
## fixed-body local coordinates, save data or collision layers.
const MODEL_PATH := "res://assets/v3/clinic_reception/clinic_reception.glb"
const ORIGIN := Vector3(7, 5, -6)
const SUPPORT_PATH := "res://assets/v3/clinic_reception/clinic_reception_support.glb"
const SUPPORT_ORIGIN := Vector3(7, 0, -6)
const GROUPS := {
	"ReceptionFrontFloor":{"paths":["Structure/FloorFront"],"boxes":["EastLanding"]},
	"ReceptionRearFloor":{"paths":["Structure/FloorRear"],"boxes":["ClinicRearFloor"]},
	"ReceptionCanopyLeft":{"paths":["Occlusion/CanopyLeft"],"boxes":["ClinicCanopyLeft"]},
	"ReceptionCanopyRight":{"paths":["Occlusion/CanopyRight"],"boxes":["ClinicCanopyRight"]},
	"ReceptionRearRoofLeft":{"paths":["Occlusion/RearRoofLeft"],"boxes":["ClinicRearRoofLeft"]},
	"ReceptionRearRoofRight":{"paths":["Occlusion/RearRoofRight"],"boxes":["ClinicRearRoofRight"]},
	"ReceptionRoom":{"paths":["Structure/ShellWalls","Structure/CornerPosts","Structure/FrontPosts","Structure/DoorFrame","Structure/WindowFrames","Structure/Drainage","Glazing/StaticWindows","Doors"],"boxes":[]},
	"ReceptionMedicalSign":{"paths":["Occlusion/MedicalSign"],"boxes":[]},
	"ReceptionStretcher":{"paths":["Furniture/Stretcher"],"boxes":[]},
	"ReceptionBed":{"paths":["Furniture/TreatmentBed"],"boxes":[]},
	"ReceptionDesk":{"paths":["Furniture/ReceptionDesk"],"boxes":[]},
	"ReceptionFixtures":{"paths":["Lighting/InteriorFixtureDesk","Lighting/InteriorFixtureBeds"],"boxes":[]},
	"ReceptionServiceStatus":{"paths":["Lighting/ReceptionStatus"],"boxes":[]}
}
const LIGHTS := {"InteriorLightDesk":Vector3(0,2.82,-2.75), "InteriorLightBeds":Vector3(3.2,2.82,-2.1)}

static func install(works: Node3D) -> Dictionary:
	if works.is_inside_tree(): return {"ok":false, "code":"reception_art_before_tree"}
	var packed := load(MODEL_PATH) as PackedScene
	if packed == null: return {"ok":false, "code":"reception_glb_missing"}
	var model := packed.instantiate() as Node3D
	if model == null: return {"ok":false, "code":"reception_root_type"}
	# Godot's scene importer adds a filename root around the glTF design root.
	var design := model.get_node_or_null("ClinicReception") as Node3D
	if design == null: return _reject(model, "reception_design_root")
	var meshes := model.find_children("*", "MeshInstance3D", true, false)
	var triangles := 0
	var materials: Dictionary = {}
	for mesh: MeshInstance3D in meshes:
		if mesh.mesh == null or mesh.mesh.get_surface_count() != 1:
			return _reject(model, "reception_surface:" + str(mesh.name))
		triangles += int(mesh.mesh.get_faces().size() / 3)
		var material := mesh.get_active_material(0) as BaseMaterial3D
		if material == null: return _reject(model, "reception_material:" + str(mesh.name))
		materials[material.get_instance_id()] = true
	if meshes.size() != 186 or triangles != 15951 or materials.size() != 19:
		return _reject(model, "reception_geometry_contract")
	if not model.transform.is_equal_approx(Transform3D.IDENTITY) or not model.find_children("*", "CollisionObject3D", true, false).is_empty() or not model.find_children("*", "Camera3D", true, false).is_empty() or not model.find_children("*", "Light3D", true, false).is_empty():
		return _reject(model, "reception_export_contract")
	for name in LIGHTS:
		var anchor := design.get_node_or_null(NodePath("Anchors/" + name)) as Node3D
		if anchor == null or not _relative(anchor, model).origin.is_equal_approx(LIGHTS[name]):
			return _reject(model, "reception_light_anchor:" + name)
	var prepared: Dictionary = {}
	var assigned: Dictionary = {}
	for name in GROUPS:
		var row := {"branches":[], "shape":null}
		var faces := PackedVector3Array()
		for path in GROUPS[name].paths:
			var branch := design.get_node_or_null(NodePath(path)) as Node3D
			if branch == null: return _reject(model, "reception_group:" + path)
			row.branches.append({"node":branch, "transform":Transform3D(Basis.IDENTITY, ORIGIN) * _relative(branch, model)})
			for mesh: MeshInstance3D in branch.find_children("*", "MeshInstance3D", true, false):
				if assigned.has(mesh.get_instance_id()): return _reject(model, "reception_duplicate_mesh")
				assigned[mesh.get_instance_id()] = true
				var transform := Transform3D(Basis.IDENTITY, ORIGIN) * _relative(mesh, model)
				for vertex in mesh.mesh.get_faces(): faces.append(transform * vertex)
		for id in GROUPS[name].boxes:
			if not works.fixed_bodies.has(id) or works.fixed_bodies[id].get_node_or_null("Visual") == null:
				return _reject(model, "reception_layout:" + id)
		# Floors already have exact full box collision. The other architectural
		# groups use the exported triangles, leaving doors and skylight empty.
		if not name.ends_with("Floor") and name != "ReceptionServiceStatus":
			var shape := ConcavePolygonShape3D.new()
			shape.set_faces(faces)
			shape.backface_collision = true
			row.shape = shape
		prepared[name] = row
	if assigned.size() != meshes.size(): return _reject(model, "reception_unassigned_mesh")
	var status_nodes := model.find_children("ReceptionLight", "MeshInstance3D", true, false)
	if status_nodes.size() != 1: return _reject(model, "reception_status_mesh")
	var status_mesh: MeshInstance3D = status_nodes[0]
	var status_material := status_mesh.get_active_material(0).duplicate() as BaseMaterial3D
	var support := _install_support(works)
	if not support.ok: return _reject(model, str(support.code))
	var covers: Array = []
	var detail_bodies: Dictionary = {}
	for name in prepared:
		var row: Dictionary = prepared[name]
		var cover := Node3D.new()
		cover.name = name
		works.add_child(cover)
		var visual := Node3D.new()
		visual.name = "AuthoredVisual"
		cover.add_child(visual)
		for id in GROUPS[name].boxes:
			var body: StaticBody3D = works.fixed_bodies[id]
			body.get_node("Visual").hide()
			body.get_parent().remove_child(body)
			cover.add_child(body)
		for branch in row.branches:
			var node: Node3D = branch.node
			_clear_owners(node)
			node.get_parent().remove_child(node)
			visual.add_child(node)
			node.transform = branch.transform
		if row.shape != null:
			var body := StaticBody3D.new()
			body.name = name + "Collision"
			body.collision_layer = 1
			body.collision_mask = 0
			var collider := CollisionShape3D.new()
			collider.shape = row.shape
			body.add_child(collider)
			cover.add_child(body)
			detail_bodies[name] = body
		if name == "ReceptionServiceStatus": cover.set_meta("terrain_visibility_keep", true)
		else: covers.append(cover)
		for mesh: MeshInstance3D in cover.find_children("*", "MeshInstance3D", true, false):
			mesh.set_meta("terrain_visibility_single_sided", true)
			# Thin repeated seams/screws should not create a black mesh of alpha
			# layers over the pilot when an actual roof blocks the fixed camera.
			if (name.contains("Roof") or name.contains("Canopy")) and not str(mesh.name).ends_with("_Subdeck"):
				mesh.set_meta("terrain_visibility_cutaway_detail", true)
	status_mesh.material_override = status_material
	var lights: Array = []
	for name in LIGHTS:
		var light := OmniLight3D.new()
		light.name = "Reception" + name
		light.position = ORIGIN + LIGHTS[name]
		light.light_color = Color("ffe7c5")
		light.light_energy = 0.65
		light.omni_range = 4.2
		light.shadow_enabled = false
		works.add_child(light)
		lights.append(light)
	# Collisions, authored cover boundaries and the independent status override
	# are complete. Batch only the original imported visual instances, never the
	# hidden graybox Visual children now nested under those same covers.
	var batched := _batch_static(works, meshes, status_mesh)
	if not batched.ok: return _reject(model, str(batched.code))
	model.free()
	covers.append(support.cover)
	detail_bodies["ReceptionSupport"] = support.detail_body
	return {"ok":true,"code":"reception_art_installed","path":MODEL_PATH,"triangles":triangles,
		"source_mesh_count":meshes.size(),"source_triangles":triangles,"source_material_count":materials.size(),
		"mesh_count":batched.runtime_meshes.size(),"runtime_meshes":batched.runtime_meshes,"model_meshes":batched.runtime_meshes,"batch_report":batched.report,"occluders":covers,"detail_bodies":detail_bodies,
		"status_mesh":status_mesh,"status_material":status_material,"lights":lights,"service_available":false,"support":support}

const BATCH_RENDER_PROPERTIES := ["layers","cast_shadow","gi_mode","transparency","lod_bias","extra_cull_margin","ignore_occlusion_culling","sorting_offset","sorting_use_aabb_center","visibility_range_begin","visibility_range_end","visibility_range_begin_margin","visibility_range_end_margin","visibility_range_fade_mode"]

static func _batch_static(works: Node3D, sources: Array, status: MeshInstance3D) -> Dictionary:
	var buckets: Dictionary = {}
	var skipped: Array = []
	for mesh: MeshInstance3D in sources:
		var cover := mesh as Node3D
		var door := false
		var cursor: Node = mesh
		while cursor != works:
			if str(cursor.name)=="Doors": door=true
			if cursor.get_parent()==works: cover=cursor as Node3D
			cursor=cursor.get_parent()
		var material := mesh.get_active_material(0) as BaseMaterial3D
		var pose := _relative(mesh,works)
		var reason := ""
		if mesh==status: reason="independent_service_status"
		elif door: reason="independent_door_pivot"
		elif material.transparency!=BaseMaterial3D.TRANSPARENCY_DISABLED: reason="transparent_panel"
		elif mesh.material_overlay!=null or mesh.skin!=null or mesh.mesh.get_blend_shape_count()>0: reason="nonstatic_or_overlay"
		elif not mesh.visible or not mesh.visibility_parent.is_empty() or mesh.get_meta("terrain_visibility_keep",false): reason="independent_visibility"
		elif mesh.mesh.surface_get_primitive_type(0)!=Mesh.PRIMITIVE_TRIANGLES: reason="nontriangle_primitive"
		elif not pose.is_finite() or pose.basis.determinant()<=0: reason="nonfinite_or_negative_basis"
		elif not pose.basis.is_equal_approx(pose.basis.orthonormalized()): reason="nonunit_or_nonuniform_or_sheared_basis"
		if not reason.is_empty():
			skipped.append({"name":str(mesh.name),"cover":str(cover.name),"reason":reason})
			continue
		var properties: Dictionary = {}
		for property: String in BATCH_RENDER_PROPERTIES: properties[property]=mesh.get(property)
		var detail: bool=mesh.get_meta("terrain_visibility_cutaway_detail",false)
		var single: bool=mesh.get_meta("terrain_visibility_single_sided",false)
		var format: int=mesh.mesh.surface_get_format(0)
		var key := str(cover.get_instance_id())+":"+str(material.get_instance_id())+":"+str(detail)+":"+str(single)+":"+str(format)+":"+JSON.stringify(properties)
		if not buckets.has(key): buckets[key]={"cover":cover,"material":material,"detail":detail,"single":single,"format":format,"properties":properties,"sources":[]}
		buckets[key].sources.append({"mesh":mesh,"pose":pose})
	var staged: Array = []
	var entries: Array = []
	for bucket: Dictionary in buckets.values():
		if bucket.sources.size()<2: continue
		var tool := SurfaceTool.new()
		tool.begin(Mesh.PRIMITIVE_TRIANGLES)
		tool.set_material(bucket.material)
		var expected_triangles := 0
		var bounds := AABB()
		var first := true
		var names: Array = []
		for source: Dictionary in bucket.sources:
			var mesh: MeshInstance3D=source.mesh
			names.append(str(mesh.name))
			var faces: PackedVector3Array=mesh.mesh.get_faces()
			expected_triangles+=int(faces.size()/3)
			for vertex in faces:
				var point: Vector3=source.pose*vertex
				bounds=AABB(point,Vector3.ZERO) if first else bounds.expand(point)
				first=false
			tool.append_from(mesh.mesh,0,source.pose)
		var merged := tool.commit()
		if merged==null or merged.get_surface_count()!=1 or merged.get_faces().size()!=expected_triangles*3 or not merged.get_aabb().position.is_equal_approx(bounds.position) or not merged.get_aabb().end.is_equal_approx(bounds.end):
			for item: Dictionary in staged: item.node.free()
			return {"ok":false,"code":"reception_batch_geometry_not_equivalent:"+str(bucket.cover.name)}
		var node := MeshInstance3D.new()
		node.name="StaticBatch_"+str(bucket.cover.name)+"_"+str(staged.size())
		node.mesh=merged
		for property: String in bucket.properties: node.set(property,bucket.properties[property])
		node.set_meta("terrain_visibility_single_sided",bucket.single)
		if bucket.detail: node.set_meta("terrain_visibility_cutaway_detail",true)
		staged.append({"node":node,"bucket":bucket})
		entries.append({"cover":str(bucket.cover.name),"runtime_name":str(node.name),"source_count":bucket.sources.size(),"source_names":names,"triangles":expected_triangles,"before_aabb":bounds,"after_aabb":merged.get_aabb(),"material_id":str(bucket.material.get_instance_id()),"detail":bucket.detail,"format":bucket.format})
	# Adopt only after every compatible batch is built and checked. No source
	# instance is merely hidden: the camera fader must collect only live visuals.
	var removed: Dictionary = {}
	for item: Dictionary in staged:
		var bucket: Dictionary=item.bucket
		bucket.cover.get_node("AuthoredVisual").add_child(item.node)
		for source: Dictionary in bucket.sources: removed[source.mesh.get_instance_id()]=true
	var runtime: Array[MeshInstance3D] = []
	for mesh: MeshInstance3D in sources:
		if removed.has(mesh.get_instance_id()):
			mesh.get_parent().remove_child(mesh)
			mesh.free()
		else: runtime.append(mesh)
	for item: Dictionary in staged: runtime.append(item.node)
	return {"ok":true,"runtime_meshes":runtime,"report":{"batch_count":staged.size(),"merged_source_mesh_count":removed.size(),"remaining_source_mesh_count":sources.size()-removed.size(),"skipped":skipped,"entries":entries}}

static func _install_support(works: Node3D) -> Dictionary:
	var packed := load(SUPPORT_PATH) as PackedScene
	if packed == null: return {"ok":false,"code":"reception_support_missing"}
	var model := packed.instantiate() as Node3D
	if model == null: return {"ok":false,"code":"reception_support_root"}
	var meshes := model.find_children("*", "MeshInstance3D", true, false)
	var counts := {"SupportStructure":2472,"SupportDetails":2048}
	var faces := PackedVector3Array()
	if meshes.size() != 2 or not model.transform.is_equal_approx(Transform3D.IDENTITY):
		return _reject(model, "reception_support_parts")
	for mesh: MeshInstance3D in meshes:
		if not counts.has(str(mesh.name)) or mesh.mesh == null or mesh.mesh.get_surface_count() != 1 or not _relative(mesh, model).is_equal_approx(Transform3D.IDENTITY):
			return _reject(model, "reception_support_mesh")
		if mesh.mesh.get_faces().size() != int(counts[str(mesh.name)]) * 3:
			return _reject(model, "reception_support_geometry")
		var material := mesh.get_active_material(0) as BaseMaterial3D
		if material == null or material.albedo_texture == null or material.normal_texture == null or material.roughness_texture == null or material.metallic_texture == null:
			return _reject(model, "reception_support_pbr")
		for vertex in mesh.mesh.get_faces(): faces.append(SUPPORT_ORIGIN + vertex)
	var boxes: Array = []
	for id in works.fixed_bodies:
		if str(id).begins_with("ClinicSupportLeg_") or str(id).begins_with("ClinicFootPlate_") or str(id).begins_with("ClinicBearingNode_") or str(id).begins_with("ClinicCrossbeam_"):
			if works.fixed_bodies[id].get_node_or_null("Visual") == null: return _reject(model, "reception_support_old_visual")
			boxes.append(works.fixed_bodies[id])
	if boxes.size() != 14: return _reject(model, "reception_support_layout")
	var shape := ConcavePolygonShape3D.new()
	shape.set_faces(faces)
	shape.backface_collision = true
	var cover := Node3D.new()
	cover.name = "ReceptionSupport"
	works.add_child(cover)
	var visual := Node3D.new()
	visual.name = "AuthoredVisual"
	cover.add_child(visual)
	visual.add_child(model)
	model.position = SUPPORT_ORIGIN
	for mesh in meshes:
		mesh.set_meta("terrain_visibility_single_sided", true)
		if mesh.name == "SupportDetails": mesh.set_meta("terrain_visibility_cutaway_detail", true)
	for body in boxes:
		body.get_node("Visual").hide()
		body.get_parent().remove_child(body)
		cover.add_child(body)
	var body := StaticBody3D.new()
	body.name = "ReceptionSupportCollision"
	body.collision_layer = 1
	body.collision_mask = 0
	var collider := CollisionShape3D.new()
	collider.shape = shape
	body.add_child(collider)
	cover.add_child(body)
	return {"ok":true,"path":SUPPORT_PATH,"cover":cover,"detail_body":body,"triangles":4520,"mesh_count":2,"model_meshes":meshes}

static func set_service_available(art: Dictionary, available: bool) -> void:
	if not art.get("ok", false): return
	var material: BaseMaterial3D = art.status_material
	var color := Color("4bcdb5") if available else Color("dba358")
	material.albedo_color = color
	material.emission_enabled = true
	material.emission = color
	material.emission_energy_multiplier = 0.45
	art.service_available = available

static func _relative(node: Node3D, root: Node3D) -> Transform3D:
	var transform := Transform3D.IDENTITY
	var current: Node = node
	while current != root:
		if current is Node3D: transform = current.transform * transform
		current = current.get_parent()
	return transform

static func _clear_owners(node: Node) -> void:
	# The imported scene root is released after its editable subtrees are placed.
	# Ownership must not retain that root outside the new ancestor chain.
	node.owner = null
	for child in node.get_children(): _clear_owners(child)

static func _reject(model: Node3D, code: String) -> Dictionary:
	model.free()
	return {"ok":false,"code":code}
