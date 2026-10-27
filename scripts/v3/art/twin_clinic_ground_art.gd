class_name TwinClinicGroundArt
extends RefCounted
## Authored arrival court and eastward receiving approach. Non-overlapping
## visual slabs replace the monolithic render box; full terrain collision stays.
## Two-centimetre sealed joints and the shallow drain use conservative Y=0
## collision. This is surface detail, not an interactive hydraulic channel.
const MODEL_PATH := "res://assets/v3/clinic_ground/clinic_ground.glb"
const PavingBatch = preload("res://scripts/v3/art/twin_i2_paving_batch.gd")
const Maintenance = preload("res://scripts/v3/art/twin_maintenance_paving_art.gd")
const PLAIN_PATH := "res://assets/v3/clinic_ground/clinic_ground_plain_v2.glb"
const ORIGIN := Vector3(-19, 0, 15)
const SIZE := Vector2(6, 6)
const PARTS := {"SlabsAndSeals":680,"DrainAndHardware":2596}
const PLAIN_VARIANTS := {"PlainA":680,"PlainB":740,"PlainP2West":680}
const COURT_START := Vector3(-22,0,12)
const COURT_END := Vector3(-4,0,24)
const APPROACH_START := Vector3(-4,0,12)
const APPROACH_END := Vector3(8,0,18)
# The half-metre east margin keeps both reused 6m modules unscaled while the
# planned 3m receiving route remains centred at X6 (edges X4.5 and X7.5).
const SURFACE_REGIONS := [Rect2(-22,12,18,12), Rect2(-4,12,12,6), Maintenance.REGION]
# Full 2cm seals only face P2 (which has no half-seal). Other neighbours
# meet two 1cm half-seals. The -90 degree turn maps local -X to world -Z.
const TILES := [
	{"id":"DrainEdge","variant":"","at":Vector3(-19,0,15),"turn":0.0},
	{"id":"ServiceWest","variant":"PlainP2West","at":Vector3(-13,0,15),"turn":0.0},
	{"id":"ServiceEast","variant":"PlainB","at":Vector3(-7,0,15),"turn":0.0},
	{"id":"ArrivalWest","variant":"PlainP2West","at":Vector3(-19,0,21),"turn":-90.0},
	{"id":"ArrivalMiddle","variant":"PlainB","at":Vector3(-13,0,21),"turn":0.0},
	{"id":"ArrivalEast","variant":"PlainA","at":Vector3(-7,0,21),"turn":0.0},
	{"id":"ReceivingApproachWest","variant":"PlainA","at":Vector3(-1,0,15),"turn":0.0},
	{"id":"ReceivingApproachEast","variant":"PlainB","at":Vector3(5,0,15),"turn":0.0}
]

static func install(works: Node3D, batch_static: bool = true) -> Dictionary:
	if works.is_inside_tree(): return {"ok":false,"code":"ground_art_before_tree"}
	var ground := works.fixed_bodies.get("Ground") as StaticBody3D
	if ground == null: return {"ok":false,"code":"ground_layout_missing"}
	var old := ground.get_node_or_null("Visual") as MeshInstance3D
	var shape := ground.get_node_or_null("ExactBoxCollision") as CollisionShape3D
	if old == null or shape == null or not shape.shape is BoxShape3D or not ground.basis.is_equal_approx(Basis.IDENTITY):
		return {"ok":false,"code":"ground_box_required"}
	var box: BoxShape3D = shape.shape
	var lo := ground.position - box.size * 0.5
	var hi := ground.position + box.size * 0.5
	var surface := Rect2(Vector2(lo.x,lo.z),Vector2(hi.x-lo.x,hi.z-lo.z))
	if not is_zero_approx(hi.y):
		return {"ok":false,"code":"ground_placement_outside_surface"}
	for region: Rect2 in SURFACE_REGIONS:
		if not surface.encloses(region): return {"ok":false,"code":"ground_placement_outside_surface"}
	var wrapper := Node3D.new()
	wrapper.name = "ClinicAuthoredPaving"
	var models: Array = []
	var tile_records: Array = []
	var triangles := 0
	# Validate all imports before changing the old world render surface.
	for row: Dictionary in TILES:
		var loaded := _tile(str(row.variant))
		if not loaded.ok:
			wrapper.free()
			return loaded
		var model: Node3D = loaded.model
		wrapper.add_child(model)
		model.name = str(row.id)
		model.position = row.at
		model.rotation.y = deg_to_rad(float(row.turn))
		models.append(model)
		triangles += int(loaded.triangles)
		tile_records.append({"id":row.id,"variant":row.variant,"model":model,
			"bounds":AABB(row.at+Vector3(-3,-0.18,-3),Vector3(6,0.18,6)),
			"triangles":loaded.triangles,"turn":row.turn})
	var maintenance := Maintenance.build()
	if not maintenance.ok:
		wrapper.free()
		return maintenance
	wrapper.add_child(maintenance.wrapper)
	# Subtract each connected authored area. The concave approach must not
	# accidentally remove the still-unpaved northeast corner of its bounding box.
	var remainder: Array[Rect2] = [surface]
	for region: Rect2 in SURFACE_REGIONS:
		var next: Array[Rect2] = []
		for patch: Rect2 in remainder: next.append_array(_subtract(patch,region))
		remainder = next
	var surface_patches: Array[MeshInstance3D] = []
	for index in remainder.size():
		var region := remainder[index]
		var lower := Vector3(region.position.x,lo.y,region.position.y)
		var upper := Vector3(region.end.x,hi.y,region.end.y)
		var patch := MeshInstance3D.new()
		patch.name = "RemainingSurface" + str(index)
		var mesh := BoxMesh.new()
		mesh.size = upper - lower
		patch.mesh = mesh
		patch.material_override = old.get_active_material(0)
		patch.position = (lower + upper) * 0.5
		wrapper.add_child(patch)
		surface_patches.append(patch)
	# Sub-surface backing prevents edge views opening an empty void below the
	# 18cm source modules. It never creates a second coplanar top at Y0.
	for index in SURFACE_REGIONS.size():
		var region: Rect2 = SURFACE_REGIONS[index]
		var backing := MeshInstance3D.new()
		backing.name = "PavingBacking" + str(index)
		var mesh := BoxMesh.new()
		mesh.size = Vector3(region.size.x,-0.181-lo.y,region.size.y)
		backing.mesh = mesh
		backing.material_override = old.get_active_material(0)
		backing.position = Vector3(region.get_center().x,(lo.y-0.181)*0.5,region.get_center().y)
		wrapper.add_child(backing)
	var art := {"ok":true,"code":"clinic_paving_ready","path":MODEL_PATH,"plain_path":PLAIN_PATH,
		"triangles":triangles,"mesh_count":16,"model":models[0],"models":models,"tiles":tile_records,
		"wrapper":wrapper,"bounds":AABB(COURT_START+Vector3(0,-0.18,0),Vector3(30,0.18,12)),
		"surface_regions":SURFACE_REGIONS.duplicate(),"surface_patches":surface_patches,"authored_area_m2":288.0,
		"maintenance":maintenance,"all_authored_area_m2":448.0,
		"physical_ground":ground,"collision_policy":"unchanged full Ground box, shallow surface details use Y0"}
	if batch_static:
		var batched: Dictionary = PavingBatch.install(art)
		if not batched.ok:
			wrapper.free()
			return batched
	works.add_child(wrapper)
	old.hide()
	return art

static func _subtract(surface: Rect2, hole: Rect2) -> Array[Rect2]:
	var result: Array[Rect2] = []
	if not surface.intersects(hole):
		result.append(surface)
		return result
	var cut := surface.intersection(hole)
	for candidate: Rect2 in [
		Rect2(surface.position,Vector2(cut.position.x-surface.position.x,surface.size.y)),
		Rect2(Vector2(cut.end.x,surface.position.y),Vector2(surface.end.x-cut.end.x,surface.size.y)),
		Rect2(Vector2(cut.position.x,surface.position.y),Vector2(cut.size.x,cut.position.y-surface.position.y)),
		Rect2(Vector2(cut.position.x,cut.end.y),Vector2(cut.size.x,surface.end.y-cut.end.y))
	]:
		if candidate.has_area(): result.append(candidate)
	return result

static func _tile(variant: String) -> Dictionary:
	var plain := not variant.is_empty()
	if plain and not PLAIN_VARIANTS.has(variant): return {"ok":false,"code":"ground_variant_unknown"}
	var packed := load(PLAIN_PATH if plain else MODEL_PATH) as PackedScene
	if packed == null: return {"ok":false,"code":"ground_glb_missing"}
	var model := packed.instantiate() as Node3D
	if model == null: return {"ok":false,"code":"ground_root_type"}
	if plain:
		var selection := model.find_child(variant,true,false) as Node3D
		if selection == null: return _reject(model,"ground_variant_missing")
		for other: String in PLAIN_VARIANTS:
			var sibling := model.find_child(other,true,false) as Node3D
			if sibling == null or sibling.get_parent() != selection.get_parent(): return _reject(model,"ground_variant_structure")
		for other: String in PLAIN_VARIANTS:
			if other != variant: model.find_child(other,true,false).free()
	var meshes := model.find_children("*", "MeshInstance3D", true, false)
	var triangles := 0
	var bounds := AABB()
	var first := true
	if meshes.size() != 2: return _reject(model,"ground_part_count")
	for mesh: MeshInstance3D in meshes:
		if mesh.mesh == null or mesh.mesh.get_surface_count() != 1: return _reject(model,"ground_part_contract")
		if not plain and not PARTS.has(str(mesh.name)): return _reject(model,"ground_part_contract")
		var ancestor: Node = mesh
		while ancestor != null:
			if ancestor is Node3D and not ancestor.transform.is_equal_approx(Transform3D.IDENTITY): return _reject(model,"ground_nonidentity")
			ancestor = ancestor.get_parent()
		var count := int(mesh.mesh.get_faces().size() / 3)
		if not plain and count != int(PARTS[str(mesh.name)]): return _reject(model,"ground_geometry")
		triangles += count
		bounds = mesh.get_aabb() if first else bounds.merge(mesh.get_aabb())
		first = false
		var material := mesh.get_active_material(0) as BaseMaterial3D
		if material == null or material.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED or material.albedo_texture == null or material.normal_texture == null or material.roughness_texture == null or material.metallic_texture == null:
			return _reject(model,"ground_pbr")
	if triangles != (int(PLAIN_VARIANTS[variant]) if plain else 3276): return _reject(model,"ground_variant_geometry")
	if not bounds.position.is_equal_approx(Vector3(-3,-0.18,-3)) or not bounds.end.is_equal_approx(Vector3(3,0,3)):
		return _reject(model,"ground_module_bounds")
	if not model.find_children("*","CollisionObject3D",true,false).is_empty() or not model.find_children("*","Light3D",true,false).is_empty() or not model.find_children("*","Camera3D",true,false).is_empty():
		return _reject(model,"ground_no_embedded_gameplay")
	return {"ok":true,"model":model,"triangles":triangles}

static func _reject(model: Node3D, code: String) -> Dictionary:
	model.free()
	return {"ok":false,"code":code}
