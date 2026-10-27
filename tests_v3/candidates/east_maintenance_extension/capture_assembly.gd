extends "res://scripts_tools/v3/capture_clinic_integrated.gd"
## Diagnostic installation in actual MAIN. Old27 and camera placements are
## explicit QA fixtures; no new gameplay result or collision is installed.
const Installer = preload("res://scripts/v3/candidates/east_maintenance_art/east_maintenance_art.gd")
const MODEL_SHA := "946a7ee1c91741302627f6c63489b37a5bb5861ebc79d093959814b4876978b0"
const OWN := "res://tests_v3/candidates/east_maintenance_extension/"
const FOOT_IDS := ["EastFoot1", "EastFoot2", "EastTrackPier1", "EastTrackPier2", "ServiceSocketPost"]
var assembly: Dictionary = {}
var measurements: Dictionary = {}
var physics_before: Dictionary = {}
var facilities_before: Dictionary = {}
var terrain_before: Dictionary = {}
var visual_before: Dictionary = {}
var dry_before := PackedVector3Array()
var attributes_before: Dictionary = {}
var diagnose_only := false

func _run() -> void:
	started_usec = Time.get_ticks_usec()
	if not _arguments_valid():
		push_error("EAST_MAINTENANCE_CAPTURE requires fresh isolated paths and Compatibility")
		quit(2)
		return
	if DirAccess.make_dir_recursive_absolute(output) != OK:
		quit(2)
		return
	create_timer(35.0 if diagnose_only else 105.0, true, false, true).timeout.connect(_timeout)
	root.size = SIZE
	for directory: String in ["res://scripts/v3", "res://data/v3", "res://scenes/v3"]: _collect_inputs(directory)
	input_paths = input_paths.filter(func(path: String) -> bool: return not path.begins_with("res://scripts/v3/candidates/"))
	input_paths.append_array(INPUTS)
	input_paths.append_array([OWN + "capture_assembly.gd", OWN + "run_assembly.py", "res://scripts_tools/v3/dev.py",
		"res://scripts/v3/candidates/east_maintenance_art/east_maintenance_art.gd", Installer.MODEL])
	hashes_before = _input_hashes()
	if not _check(FileAccess.get_sha256(Installer.MODEL) == MODEL_SHA, "candidate GLB is the frozen approved source byte sequence"):
		await _finish()
		return
	session = MAIN.instantiate()
	root.add_child(session)
	if not _check(session.has_method("start_flight") and int(capture_logger.snapshot().error_count) == 0, "MAIN has its real script and no startup parse error"):
		await _finish()
		return
	if not _check(session.profile_ready and session.start_flight("solo"), "fresh actual MAIN starts in an isolated profile"):
		await _finish()
		return
	_hold()
	if not _seed_history():
		await _finish()
		return
	session._ui_action("travel_to", {"region_id":"I2"})
	_hold()
	await physics_frame
	await physics_frame
	if not _check(session.region_id == "I2" and session.world.build_errors.is_empty() and session._facilities_ready()
		and session.world.revetment_art.get("ok", false) and session.world.east_revetment_art.get("ok", false),
		"actual World contains four ready facilities and both already-installed straight banks"):
		await _finish()
		return
	body = session.players[1]
	var installed: Dictionary = session.world.waterfront_install
	dry_before = _raw_faces(installed.meshes.dry_surface.mesh)
	attributes_before = _attribute_report(installed.meshes.dry_surface.mesh)
	physics_before = _physics_record(session.world)
	facilities_before = _facility_record()
	terrain_before = _terrain_record()
	visual_before = _visible_record(installed)
	var children_before: Array = installed.wrapper.get_children()
	var rejected: Dictionary = Installer.install({})
	_check(not rejected.get("ok", false) and installed.wrapper.get_children() == children_before
		and _visible_record(installed) == visual_before, "invalid input rejects without touching the live two-bank scene")
	assembly = Installer.install(installed)
	if not _check(assembly.get("ok", false), "candidate performs its complete visual installation: " + str(assembly.get("code", "missing result"))):
		await _finish()
		return
	await physics_frame
	await physics_frame
	_check(_physics_record(session.world) == physics_before, "all original world bodies, shape bytes, RIDs, layers and PhysicsServer poses are exactly unchanged")
	_check(_facility_record() == facilities_before, "clinic/distribution/trial/shared-access histories, mechanisms and ability targets are unchanged")
	_check(_terrain_record() == terrain_before, "original Waterfront definition, geometry and collision source remain untouched")
	_audit_remaining_surface(installed)
	_audit_import()
	_audit_joints_and_holes()
	var after_first: Dictionary = _visible_record(installed)
	var after_children: Array = installed.wrapper.get_children()
	var repeated: Dictionary = Installer.install(installed)
	_check(not repeated.get("ok", false) and repeated.get("code", "") == "already_installed"
		and _visible_record(installed) == after_first and installed.wrapper.get_children() == after_children
		and _physics_record(session.world) == physics_before, "repeat install rejects atomically without replacing either bank, floor or physics")
	inventories.I2 = _scene_inventory(session.world)
	for path: String in inventories.I2.imported_sources + inventories.I2.material_sources:
		if path not in input_paths: input_paths.append(path)
	_add_import_hashes()
	# Preserve early source hashes; newly discovered imported resources are read
	# before the first captured frame and checked again after full cleanup.
	for path: String in input_paths:
		if not hashes_before.has(path): hashes_before[path] = FileAccess.get_sha256(path) if FileAccess.file_exists(path) else "MISSING"
	if diagnose_only:
		await _finish()
		return
	await _place(Vector3(20.3, 1.8, 11), "east maintenance default view; frozen QA placement, not a flown route")
	await _capture("01-east-maintenance-default", "Actual MAIN, original lighting and 26m orthographic camera; only the diagnostic east-floor candidate is newly installed.")
	await _capture("02-east-maintenance-near", "Three ordinary zoom steps show real imported PBR, foot cutouts and the landward bank join.", 3)
	await _place(Vector3(21.9, 1.8, 3), "north meeting of old maintenance bay and new extension; frozen QA placement")
	await _capture("03-east-maintenance-north-joint", "Original W3/E3 north paving stays visible; inspect its single seam and continuous inspection band at Z2.", 3)
	_check(_physics_record(session.world) == physics_before and _facility_record() == facilities_before,
		"camera presentation, fades and cleanup preparation did not advance or alter four-facility physics/state")
	await _finish()

func _arguments_valid() -> bool:
	var profiles := 0
	var outputs := 0
	var diagnostic_flags := 0
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--qa-profile="): profiles += 1; profile = arg.trim_prefix("--qa-profile=")
		elif arg.begins_with("--capture-output="): outputs += 1; output = arg.trim_prefix("--capture-output=")
		elif arg == "--diagnose-only": diagnostic_flags += 1; diagnose_only = true
		else: return false
	var regex := RegEx.new()
	if regex.compile("^qa_visual_clinic_east_maintenance_[A-Za-z0-9_-]+$") != OK: return false
	if profiles != 1 or outputs != 1 or diagnostic_flags > 1 or regex.search(profile) == null: return false
	output = ProjectSettings.globalize_path(output).replace("\\", "/").simplify_path()
	var allowed: String = ProjectSettings.globalize_path(OWN + "evidence").replace("\\", "/").simplify_path()
	if output.get_base_dir().to_lower() != allowed.to_lower() or not output.get_file().begins_with("diagnose-" if diagnose_only else "capture-"): return false
	if DirAccess.dir_exists_absolute(output) or FileAccess.file_exists(output): return false
	if DirAccess.dir_exists_absolute("user://profiles_v3/" + profile) or FileAccess.file_exists("user://profiles_v3/" + profile): return false
	if not OS.is_debug_build() or Engine.physics_ticks_per_second != 60: return false
	if diagnose_only: return DisplayServer.get_name() == "headless"
	return DisplayServer.get_name() != "headless" and RenderingServer.get_current_rendering_method() == "gl_compatibility" \
		and RenderingServer.is_render_loop_enabled()

func _facility_record() -> Dictionary:
	var result: Dictionary = {}
	for id: String in ["clinic", "distribution", "trial", "shared_access"]:
		var adapter = session.get(id)
		result[id] = {"ready":adapter.ready, "persistent":_digest(adapter.persistent_state()),
			"mechanism":_digest(adapter.module.snapshot())}
	result.targets = _digest(session.world.definitions)
	var target_poses: Dictionary = {}
	for id: String in session.world.objects:
		var target: Node3D = session.world.objects[id]
		target_poses[id] = {"id":target.get_instance_id(), "pose":target.global_transform}
	result.target_poses = _digest(target_poses)
	return result

func _physics_record(node: Node) -> Dictionary:
	var result: Dictionary = {}
	for child: Node in node.find_children("*", "CollisionObject3D", true, false):
		var body3d := child as CollisionObject3D
		var record := {"id":body3d.get_instance_id(), "rid":body3d.get_rid().get_id(), "local":body3d.transform,
			"world":body3d.global_transform, "layer":body3d.collision_layer, "mask":body3d.collision_mask, "shapes":[]}
		if body3d is PhysicsBody3D:
			record.server = PhysicsServer3D.body_get_state(body3d.get_rid(), PhysicsServer3D.BODY_STATE_TRANSFORM)
		for shape_node: Node in body3d.find_children("*", "CollisionShape3D", true, false):
			var collider := shape_node as CollisionShape3D
			if collider.shape == null: continue
			record.shapes.append({"node":collider.get_instance_id(), "id":collider.shape.get_instance_id(),
				"rid":collider.shape.get_rid().get_id(), "disabled":collider.disabled,
				"local":collider.transform, "global":collider.global_transform,
				"data":_digest(PhysicsServer3D.shape_get_data(collider.shape.get_rid()))})
		result[str(body3d.get_path())] = record
	return result

func _terrain_record() -> Dictionary:
	var terrain = session.world.waterfront
	var result := {"definition":_digest(terrain.definition()), "collision":_digest(terrain.collision_faces())}
	for part: String in terrain.part_ids(): result[part] = _digest(terrain.geometry(part))
	return result

func _visible_record(installed: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	for id: String in installed.meshes:
		var view: MeshInstance3D = installed.meshes[id]
		result[id] = {"node":view.get_instance_id(), "mesh":view.mesh.get_instance_id(), "arrays":_digest(view.mesh.surface_get_arrays(0)),
			"material":view.get_active_material(0).get_instance_id(), "transform":view.transform, "visible":view.visible}
	for side: String in ["revetment_art", "east_revetment_art"]:
		var art: Dictionary = session.world.get(side)
		result[side] = _mesh_record(art.wrapper)
	result.north_paving = _mesh_record(session.clinic.module.ground_art.maintenance.wrapper)
	return result

func _mesh_record(node: Node) -> Dictionary:
	var result: Dictionary = {}
	for mesh: MeshInstance3D in node.find_children("*", "MeshInstance3D", true, false):
		result[str(mesh.get_path())] = {"node":mesh.get_instance_id(), "mesh":mesh.mesh.get_instance_id(), "transform":mesh.global_transform,
			"geometry":_digest(_raw_faces(mesh.mesh)), "visible":mesh.visible, "material":mesh.get_active_material(0).get_instance_id()}
	return result

func _audit_remaining_surface(installed: Dictionary) -> void:
	var after: PackedVector3Array = _raw_faces(installed.meshes.dry_surface.mesh)
	var actual_visual: Dictionary = _visible_record(installed)
	var other_unchanged := true
	for key: String in visual_before:
		if key != "dry_surface": other_unchanged = other_unchanged and actual_visual[key] == visual_before[key]
	_check(other_unchanged, "west/east authored banks, old north paving, water, bed and every other visible terrain part retain exact identities and geometry")
	_check(actual_visual.dry_surface.node == visual_before.dry_surface.node and actual_visual.dry_surface.material == visual_before.dry_surface.material,
		"only the existing dry-surface mesh is partitioned; its node and production material survive")
	var holes: Array[Rect2] = []
	var hole_records: Array = []
	for id: String in FOOT_IDS:
		var foot: StaticBody3D = session.world.shared_access.fixed_bodies[id]
		var colliders: Array = foot.find_children("*", "CollisionShape3D", true, false)
		if not _check(colliders.size() == 1 and colliders[0].shape is BoxShape3D, "real footprint collider found: " + id): continue
		var collider: CollisionShape3D = colliders[0]
		var box: BoxShape3D = collider.shape
		var bounds: AABB = collider.global_transform * AABB(-box.size * .5, box.size)
		var rect := Rect2(bounds.position.x, bounds.position.z, bounds.size.x, bounds.size.z)
		holes.append(rect)
		hole_records.append({"id":id, "minimum":_vec(bounds.position), "maximum":_vec(bounds.end)})
	var region := Rect2(16.9, 2, 7.6, 13.6)
	var before_in := _rect_area(dry_before, region)
	var after_in := _rect_area(after, region)
	var before_holes := 0.0
	var after_holes := 0.0
	for hole: Rect2 in holes:
		before_holes += _rect_area(dry_before, hole)
		after_holes += _rect_area(after, hole)
	var removed: float = _area(dry_before) - _area(after)
	_check(holes.size() == 5 and absf(before_holes - 1.16) < .0002 and absf(after_holes - before_holes) < .0002,
		"all five cutouts match actual production footplate/pier colliders and retain the old floor underneath")
	_check(absf(before_in - before_holes - 97.545) < .0002 and absf(removed - 97.545) < .0002
		and absf(after_in - after_holes) < .0002 and absf((_area(dry_before)-before_in)-(_area(after)-after_in)) < .0002,
		"independent polygon intersections prove 97.545m2 removal with no kept overlay or deletion outside the actual east bay")
	var attributes_after: Dictionary = _attribute_report(installed.meshes.dry_surface.mesh)
	# These are the exact three first-run predicates, now separated. The same
	# readback measurement on the original two-bank mesh is evidence, not an
	# alternative threshold or permission to ignore a real changed attribute.
	_check(attributes_after.finite, "remaining mesh positions and UV are finite")
	_check(attributes_after.winding, "remaining mesh cross_squared > 1e-14 and cross dot normal < 0")
	_check(attributes_after.metric_uv, "remaining mesh readback UV differs from worldXZ * .25 by less than 1e-5")
	measurements.attributes = {"before_install":attributes_before, "after_install":attributes_after,
		"criterion_origin":{"finite":"existing Partition._validate, with added explicit UV finite readback",
			"winding":"same MIN_CROSS_SQUARED=1e-14 and clockwise cross dot normal<0 as the production partition",
			"metric_uv":"WaterfrontTerrain._tri authors worldXZ*.25; 1e-5 is a QA readback bound, not a documented Godot storage guarantee"}}
	measurements.partition = {"before_area_m2":_area(dry_before), "after_area_m2":_area(after), "removed_m2":removed,
		"inside_before_m2":before_in, "inside_after_m2":after_in, "hole_area_m2":after_holes, "actual_holes":hole_records}

func _attribute_report(mesh: ArrayMesh) -> Dictionary:
	var arrays: Array = mesh.surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var cached_faces: PackedVector3Array = mesh.get_faces()
	var raw_normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var raw_uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
	# Godot 4.7.2 Mesh::get_faces -> TriangleMesh::create snaps positions at
	# 0.0001m. That auxiliary cache cannot be paired with unmodified UV/normals.
	# Here all three attributes use the same real surface corner index instead.
	var faces := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var raw_cardinality: bool = raw_normals.size() == vertices.size() and raw_uvs.size() == vertices.size()
	if not raw_cardinality:
		return {"finite":false,"winding":false,"metric_uv":false,"cardinality":false,"vertices":vertices.size(),"normals":raw_normals.size(),"uvs":raw_uvs.size(),"indices":indices.size()}
	for corner in (indices.size() if not indices.is_empty() else vertices.size()):
		var index: int = indices[corner] if not indices.is_empty() else corner
		if index < 0 or index >= vertices.size():
			return {"finite":false,"winding":false,"metric_uv":false,"cardinality":false,"invalid_index":index}
		faces.append(vertices[index])
		normals.append(raw_normals[index])
		uvs.append(raw_uvs[index])
	var finite := true
	var winding := true
	var metric_uv := true
	var max_uv_error := 0.0
	var min_cross_squared := INF
	var max_cross_dot_normal := -INF
	var finite_failures := 0
	var uv_failures := 0
	var winding_failures := 0
	var bad_finite: Array = []
	var bad_uv: Array = []
	var bad_winding: Array = []
	var worst_uv: Dictionary = {}
	var cardinality: bool = not faces.is_empty() and faces.size() == normals.size() and faces.size() == uvs.size() and faces.size()%3 == 0
	if not cardinality:
		return {"finite":false,"winding":false,"metric_uv":false,"cardinality":false,"vertices":vertices.size(),"faces":faces.size(),"normals":normals.size(),"uvs":uvs.size(),"indices":indices.size()}
	for index in faces.size():
		var point: Vector3 = faces[index]
		var uv: Vector2 = uvs[index]
		var expected := Vector2(point.x,point.z)*.25
		var is_finite_pair: bool = point.is_finite() and uv.is_finite()
		finite = finite and is_finite_pair
		if not is_finite_pair:
			finite_failures += 1
			if bad_finite.size() < 32: bad_finite.append({"index":index,"position":str(point),"uv":str(uv)})
		var error: float = uv.distance_to(expected)
		if not is_finite(error) or error >= .00001:
			metric_uv = false
			uv_failures += 1
			var row := {"index":index,"position":_vec(point),"uv":[uv.x,uv.y],"expected":[expected.x,expected.y],"delta":[uv.x-expected.x,uv.y-expected.y],"distance":error}
			if bad_uv.size() < 32: bad_uv.append(row)
			if error > max_uv_error: worst_uv = row
		max_uv_error = maxf(max_uv_error,error)
	for first in range(0,faces.size(),3):
		var cross: Vector3 = (faces[first+1]-faces[first]).cross(faces[first+2]-faces[first])
		var cross_squared: float = cross.length_squared()
		var dot_normal: float = cross.dot(normals[first])
		min_cross_squared = minf(min_cross_squared,cross_squared)
		max_cross_dot_normal = maxf(max_cross_dot_normal,dot_normal)
		var valid: bool = cross_squared > 1e-14 and dot_normal < 0
		winding = winding and valid
		if not valid:
			winding_failures += 1
			if bad_winding.size() < 32:
				bad_winding.append({"triangle":first/3,"positions":[_vec(faces[first]),_vec(faces[first+1]),_vec(faces[first+2])],
					"normal":_vec(normals[first]),"cross_squared":cross_squared,"cross_dot_normal":dot_normal,"area_m2":cross.length()*.5})
	var cache_diagnostic := {"scope":"snapped auxiliary cache, never the render-mesh acceptance predicate",
		"same_corner_count":cached_faces.size()==faces.size(),"max_position_difference_m":0.0,
		"winding_failure_count":0,"metric_uv_failure_count":0,"max_world_uv_error":0.0,"first_32_raw_vs_snapped_triangles":[]}
	if cached_faces.size() == faces.size():
		for index in faces.size():
			cache_diagnostic.max_position_difference_m = maxf(float(cache_diagnostic.max_position_difference_m),cached_faces[index].distance_to(faces[index]))
			var cached_error: float = uvs[index].distance_to(Vector2(cached_faces[index].x,cached_faces[index].z)*.25)
			cache_diagnostic.max_world_uv_error = maxf(float(cache_diagnostic.max_world_uv_error),cached_error)
			if cached_error >= .00001: cache_diagnostic.metric_uv_failure_count += 1
		for first in range(0,cached_faces.size(),3):
			var cached_cross: Vector3 = (cached_faces[first+1]-cached_faces[first]).cross(cached_faces[first+2]-cached_faces[first])
			if cached_cross.length_squared() > 1e-14 and cached_cross.dot(normals[first]) < 0: continue
			cache_diagnostic.winding_failure_count += 1
			if cache_diagnostic.first_32_raw_vs_snapped_triangles.size() < 32:
				var raw_cross: Vector3 = (faces[first+1]-faces[first]).cross(faces[first+2]-faces[first])
				cache_diagnostic.first_32_raw_vs_snapped_triangles.append({"triangle":first/3,
					"raw_positions":[_vec(faces[first]),_vec(faces[first+1]),_vec(faces[first+2])],
					"cached_positions":[_vec(cached_faces[first]),_vec(cached_faces[first+1]),_vec(cached_faces[first+2])],
					"raw_area_m2":raw_cross.length()*.5,"raw_cross_squared":raw_cross.length_squared(),"cached_area_m2":cached_cross.length()*.5})
	return {"finite":finite,"winding":winding,"metric_uv":metric_uv,"cardinality":cardinality,
		"vertex_count":vertices.size(),"face_corner_count":faces.size(),"index_count":indices.size(),
		"get_faces_equals_vertex_array":cached_faces.to_byte_array()==vertices.to_byte_array(),"surface_format":mesh.surface_get_format(0),
		"raw_attributes_share_corner_index":true,"snapped_get_faces_diagnostic":cache_diagnostic,
		"minimum_cross_squared":min_cross_squared,"maximum_cross_dot_normal":max_cross_dot_normal,
		"maximum_world_uv_error":max_uv_error,"worst_uv":worst_uv,
		"failure_counts":{"finite":finite_failures,"winding":winding_failures,"metric_uv":uv_failures},
		"first_32_finite_failures":bad_finite,"first_32_winding_failures":bad_winding,"first_32_uv_failures":bad_uv}

func _audit_import() -> void:
	var materials: Dictionary = {}
	var bounds := AABB()
	var first := true
	var triangles := 0
	var rows: Array = []
	for view: MeshInstance3D in assembly.meshes:
		var actual: AABB = view.global_transform * view.get_aabb()
		bounds = actual if first else bounds.merge(actual)
		first = false
		var count: int = _raw_faces(view.mesh).size() / 3
		triangles += count
		var material := view.get_active_material(0) as BaseMaterial3D
		var textures: Dictionary = {}
		var pbr := material != null and view.mesh.get_surface_count() == 1
		if material != null:
			materials[material.get_instance_id()] = true
			pbr = pbr and material.transparency == BaseMaterial3D.TRANSPARENCY_DISABLED and material.normal_enabled
			for slot: String in ["albedo_texture", "normal_texture", "roughness_texture", "metallic_texture"]:
				var texture: Texture2D = material.get(slot)
				var size: int = 2048 if str(view.name) == "FloorSurface" else 1024
				pbr = pbr and texture is CompressedTexture2D and texture.get_width() == size and texture.get_height() == size
				textures[slot] = {"path":texture.resource_path, "size":[texture.get_width(),texture.get_height()]} if texture != null else {"missing":true}
		_check(pbr and view.is_visible_in_tree(), "actual imported opaque PBR and final resolution: " + str(view.name))
		rows.append({"name":str(view.name), "triangles":count, "surfaces":view.mesh.get_surface_count(), "mesh_path":view.mesh.resource_path,
			"minimum":_vec(actual.position), "maximum":_vec(actual.end), "textures":textures})
	_check(assembly.meshes.size() == 2 and triangles == 16724 and materials.size() == 2,
		"actual imported resource is two meshes/two materials/two surfaces/16724 triangles")
	_check(bounds.position.is_equal_approx(Vector3(16.9,-.18,2)) and bounds.end.is_equal_approx(Vector3(24.5,0,15.6)),
		"actual imported bounds place the candidate at its authored metre origin without scale")
	_check(assembly.model.find_children("*", "CollisionObject3D", true, false).is_empty(), "visual candidate adds no collider or collision approximation")
	measurements.imported = {"path":Installer.MODEL, "sha256":FileAccess.get_sha256(Installer.MODEL), "meshes":rows,
		"minimum":_vec(bounds.position), "maximum":_vec(bounds.end), "triangles":triangles}

func _audit_joints_and_holes() -> void:
	var faces := PackedVector3Array()
	for view: MeshInstance3D in assembly.meshes: faces.append_array(_world_faces(view))
	var hole_checks: Array = []
	for row: Dictionary in measurements.partition.actual_holes:
		var center := Vector2((float(row.minimum[0])+float(row.maximum[0]))*.5, (float(row.minimum[2])+float(row.maximum[2]))*.5)
		var hit: Dictionary = _top(faces, center)
		_check(not hit.hit, "actual imported triangles leave the real full-depth foot hole open: " + str(row.id))
		hole_checks.append({"id":row.id,"center_xz":[center.x,center.y],"model_top_hit":hit})
	var north_faces := PackedVector3Array()
	for tile: Dictionary in session.clinic.module.ground_art.maintenance.tiles:
		if tile.id not in ["W3", "E3"]: continue
		for view: MeshInstance3D in tile.meshes: north_faces.append_array(_world_faces(view))
	var joint_checks: Array = []
	for x: float in [18.4, 19.245, 22.3, 23.7]:
		for z: float in [1.97, 1.99, 2.001, 2.015, 2.04]:
			var hit: Dictionary = _top(north_faces if z < 2 else faces, Vector2(x,z))
			_check(hit.hit and float(hit.get("y",-1)) >= -.031 and float(hit.get("y",1)) <= .002,
				"actual north join has a supported visible top at " + str(Vector2(x,z)))
			joint_checks.append({"xz":[x,z],"top":hit})
	var bank_faces := PackedVector3Array()
	for part: Dictionary in session.world.east_revetment_art.parts: bank_faces.append_array(_world_faces(part.mesh))
	var bank_checks: Array = []
	for z: float in [2.45, 5.25, 8.5, 11.7, 15.45]:
		var cap: Dictionary = _top(bank_faces, Vector2(17.24,z))
		var floor_top: Dictionary = _top(faces, Vector2(17.27,z))
		var water_side: Dictionary = _top(faces, Vector2(17.24,z))
		_check(cap.hit and floor_top.hit and not water_side.hit and absf(float(cap.get("y",-1))) < .015
			and float(floor_top.get("y",-1)) >= -.031, "real bank cap meets the floor without an overlaid floor strip at Z" + str(z))
		bank_checks.append({"z":z,"cap":cap,"floor":floor_top,"floor_on_cap":water_side})
	var ground_rays: Array = []
	for z: float in [3, 7, 12, 15]:
		var hit: Dictionary = session.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(23,.3,z),Vector3(23,-.3,z),1|8))
		_check(hit.get("collider") == session.world.waterfront_install.ground and absf(hit.get("position",Vector3.ONE).y)<.001,
			"original physical Ground remains the first floor hit on the three-metre clear route at Z"+str(z))
		ground_rays.append(_ray_record(hit))
	measurements.holes = hole_checks
	measurements.north_joint = joint_checks
	measurements.bank_joint = bank_checks
	measurements.ground_rays = ground_rays

static func _world_faces(view: MeshInstance3D) -> PackedVector3Array:
	var faces: PackedVector3Array = _raw_faces(view.mesh)
	for index in faces.size(): faces[index] = view.global_transform * faces[index]
	return faces

static func _raw_faces(mesh: Mesh) -> PackedVector3Array:
	var faces := PackedVector3Array()
	for surface in mesh.get_surface_count():
		var arrays: Array = mesh.surface_get_arrays(surface)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
		if indices.is_empty(): faces.append_array(vertices)
		else:
			for index: int in indices: faces.append(vertices[index])
	return faces

static func _top(faces: PackedVector3Array, point: Vector2) -> Dictionary:
	var hit := false
	var high := -INF
	for first in range(0, faces.size(), 3):
		var a: Vector3 = faces[first]
		var b: Vector3 = faces[first+1]
		var c: Vector3 = faces[first+2]
		var denominator: float = (b.x-a.x)*(c.z-a.z)-(c.x-a.x)*(b.z-a.z)
		if absf(denominator) < 1e-16: continue
		var v: float = ((point.x-a.x)*(c.z-a.z)-(c.x-a.x)*(point.y-a.z))/denominator
		var w: float = ((b.x-a.x)*(point.y-a.z)-(point.x-a.x)*(b.z-a.z))/denominator
		if v < -.0000001 or w < -.0000001 or v+w > 1.0000001: continue
		var y: float = a.y*(1-v-w)+b.y*v+c.y*w
		if y < -.3 or y > .1: continue
		hit = true
		high = maxf(high,y)
	return {"hit":true,"y":high} if hit else {"hit":false}

static func _area(faces: PackedVector3Array) -> float:
	var area := 0.0
	for first in range(0, faces.size(), 3): area += (faces[first+1]-faces[first]).cross(faces[first+2]-faces[first]).length()*.5
	return area

static func _rect_area(faces: PackedVector3Array, rect: Rect2) -> float:
	var clip := PackedVector2Array([rect.position,Vector2(rect.end.x,rect.position.y),rect.end,Vector2(rect.position.x,rect.end.y)])
	var total := 0.0
	for first in range(0, faces.size(), 3):
		var triangle := PackedVector2Array()
		for offset in 3: triangle.append(Vector2(faces[first+offset].x,faces[first+offset].z))
		for polygon: PackedVector2Array in Geometry2D.intersect_polygons(triangle,clip):
			var twice := 0.0
			for index in polygon.size(): twice += polygon[index].cross(polygon[(index+1)%polygon.size()])
			total += absf(twice)*.5
	return total

static func _digest(value: Variant) -> String:
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	context.update(var_to_bytes(value))
	return context.finish().hex_encode()

func _state() -> Dictionary:
	var state: Dictionary = super._state()
	if session._facilities_ready(): state.four_facilities = _facility_record()
	return state

func _timeout() -> void:
	if finishing: quit(3); return
	_check(false, "bounded internal capture/diagnostic watchdog expired")
	_finish.call_deferred()

func _finish() -> void:
	if finishing: return
	finishing = true
	if is_instance_valid(session):
		if session.has_method("start_flight"):
			session.active = false
			if is_instance_valid(session.network): session.network.close()
		session.free()
	await process_frame
	await process_frame
	var after: Dictionary = _input_hashes()
	_check(not hashes_before.is_empty() and hashes_before == after, "all discovered runtime, imported assets, QA and source input bytes remain unchanged")
	_check(shots.is_empty() if diagnose_only else shots.size() == 3,
		"diagnostic run does not create new images" if diagnose_only else "three requested real MAIN 720p views were saved")
	var logged: Dictionary = capture_logger.snapshot()
	_check(int(logged.error_count) == 0, "zero engine/script/shader errors through cleanup")
	var passed := true
	for row: Dictionary in checks: passed = passed and bool(row.passed)
	var report := {"passed":passed, "status":"headless_attribute_diagnostic_not_graphics" if diagnose_only else "diagnostic_candidate_actual_MAIN_not_art_acceptance", "profile":profile,
		"checks":checks, "measurements":measurements, "shots":shots, "placements":placements, "fixture":fixture,
		"inventories":inventories, "input_sha256_before":hashes_before, "input_sha256_after":after, "engine_log":logged,
		"engine":Engine.get_version_info(), "GPU":RenderingServer.get_video_adapter_name(), "renderer":RenderingServer.get_current_rendering_method(),
		"elapsed_seconds":float(Time.get_ticks_usec()-started_usec)/1000000.0,
		"limits":["Diagnostic visual installation after real World build; production World/physics are not modified on disk.",
			"Old27 and frozen camera positions are QA fixtures, not playthrough or flown-route evidence.",
			"Triangle samples complement area/identity checks; they are not an exhaustive all-surface contact proof.",
			"No multiplayer, performance, human comfort or complete-region art acceptance."]}
	var file := FileAccess.open(output.path_join("state_checks.json"), FileAccess.WRITE)
	var wrote := file != null
	if wrote:
		file.store_string(JSON.stringify(report,"\t",true,true)); file.flush()
		wrote = file.get_error() == OK
		file.close()
	print("EAST_MAINTENANCE_ASSEMBLY ", JSON.stringify({"passed":passed and wrote,"checks":checks.size(),"shots":shots.size(),"output":output}))
	OS.remove_logger(capture_logger)
	quit(0 if passed and wrote else 1)
