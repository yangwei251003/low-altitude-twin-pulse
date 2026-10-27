extends "res://tests_v3/candidates/east_maintenance_extension/capture_assembly.gd"
## Read-only actual MAIN verification AFTER World installs the production asset.
## Inherited candidate helpers are measurements only: no install() is called here.
const ProductionArt = preload("res://scripts/v3/art/twin_i2_east_maintenance_art.gd")
const ProductionTerrain = preload("res://scripts/v3/world/twin_i2_waterfront_terrain.gd")

func _run() -> void:
	started_usec = Time.get_ticks_usec()
	if not _production_arguments_valid():
		push_error("EAST_MAINTENANCE_PRODUCTION requires fresh isolated paths and Compatibility")
		quit(2)
		return
	if DirAccess.make_dir_recursive_absolute(output) != OK:
		quit(2)
		return
	create_timer(50.0, true, false, true).timeout.connect(_timeout)
	root.size = SIZE
	for directory: String in ["res://scripts/v3", "res://data/v3", "res://scenes/v3"]: _collect_inputs(directory)
	input_paths = input_paths.filter(func(path: String) -> bool: return not path.begins_with("res://scripts/v3/candidates/"))
	input_paths.append_array(INPUTS)
	input_paths.append_array([OWN + "capture_production.gd", OWN + "run_production.py", OWN + "capture_assembly.gd",
		"res://scripts_tools/v3/dev.py", "res://scripts/v3/candidates/east_maintenance_art/east_maintenance_art.gd", ProductionArt.MODEL])
	# The historical helper preloads its old Installer; hash that dependency but
	# never invoke it or use its candidate GLB as proof of the production import.
	hashes_before = _input_hashes()
	if not _check(FileAccess.get_sha256(ProductionArt.MODEL) == MODEL_SHA, "production GLB bytes match the approved editable-source delivery"):
		await _finish()
		return
	session = MAIN.instantiate()
	root.add_child(session)
	if not _check(session.has_method("start_flight") and int(capture_logger.snapshot().error_count) == 0,
		"MAIN has its real script and no startup parse error"):
		await _finish()
		return
	if not _check(session.profile_ready and session.start_flight("solo"), "fresh actual MAIN starts in an isolated production-probe profile"):
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
		and session.world.revetment_art.get("ok", false) and session.world.east_revetment_art.get("ok", false)
		and session.world.east_maintenance_art.get("ok", false),
		"production World automatically installs both banks and the east extension with all four facilities ready"):
		await _finish()
		return
	body = session.players[1]
	assembly = session.world.east_maintenance_art
	var installed: Dictionary = session.world.waterfront_install
	var identity: Dictionary = assembly_identity(session.world)
	measurements.assembly_identity = identity.details
	for row: Dictionary in identity.checks:
		_check(row.passed, str(row.name) + " actual=" + JSON.stringify(row.actual))
	physics_before = _physics_record(session.world)
	facilities_before = _facility_record()
	terrain_before = _terrain_record()
	visual_before = _visible_record(installed)
	_audit_production_physics(installed)
	_audit_production_surface(installed)
	_audit_import()
	_audit_joints_and_holes()
	inventories.I2 = _scene_inventory(session.world)
	for path: String in inventories.I2.imported_sources + inventories.I2.material_sources:
		if path not in input_paths: input_paths.append(path)
	_check(ProductionArt.MODEL in inventories.I2.imported_sources,
		"actual live mesh resources report the production GLB path")
	_add_import_hashes()
	for path: String in input_paths:
		if not hashes_before.has(path): hashes_before[path] = FileAccess.get_sha256(path) if FileAccess.file_exists(path) else "MISSING"
	await _place(Vector3(20.3, 1.8, 11), "production east maintenance default view; frozen QA pose, not a flown route")
	await _capture("01-east-maintenance-production-default", "Actual World automatically loaded the production floor; original lighting and default 26m camera.")
	await _place(Vector3(21.9, 1.8, 3), "production north seam inspection; frozen QA pose")
	await _capture("02-east-maintenance-production-north-joint", "Normal zoom3 view of the original north paving, continuous inspection band and new production floor.", 3)
	_check(_physics_record(session.world) == physics_before and _facility_record() == facilities_before,
		"read-only probes and camera presentation preserve all four facility histories, targets, mechanisms and original physics")
	_check(_terrain_record() == terrain_before, "production capture leaves original terrain definition, geometry and collision bytes unchanged")
	await _finish()

static func assembly_identity(world: Node3D) -> Dictionary:
	var art: Dictionary = world.get("east_maintenance_art")
	var installed: Dictionary = world.get("waterfront_install")
	var model: Node3D = art.model
	var wrapper: Node3D = installed.wrapper
	var direct: Array = []
	var instances: Array = []
	for child: Node in wrapper.get_children():
		var row := {"name":str(child.name),"path":str(child.get_path()),"instance_id":child.get_instance_id(),
			"scene_file_path":child.scene_file_path,"is_assembly_model":child == model}
		direct.append(row)
		if str(child.name) == "EastMaintenanceExtension" or child.scene_file_path == ProductionArt.MODEL: instances.append(row)
	var recursive: Array = []
	for child: Node in wrapper.find_children("EastMaintenanceExtension", "Node3D", true, false):
		recursive.append({"path":str(child.get_path()),"instance_id":child.get_instance_id(),"scene_file_path":child.scene_file_path})
	var details := {"model":str(model.get_path()),"model_instance_id":model.get_instance_id(),"name":str(model.name),
		"parent":str(model.get_parent().get_path()),"expected_parent":str(wrapper.get_path()),
		"scene_file_path":model.scene_file_path,"model_path":str(art.get("model_path","")),
		"expected_asset_path":ProductionArt.MODEL,"direct_children":direct,"direct_production_instances":instances,
		"recursive_same_name_nodes":recursive,"candidate_absent":not wrapper.has_node("EastMaintenanceExtensionCandidate")}
	# GLTF may contain a same-named authored child inside its imported scene root.
	# Single installation is an identity/ownership property of direct siblings;
	# recursive author names remain diagnostic and never count as another install.
	var rows := [
		{"name":"production model belongs to the original terrain wrapper","passed":model.get_parent()==wrapper,"actual":[details.parent,details.expected_parent]},
		{"name":"production installed root has its stable name","passed":str(model.name)=="EastMaintenanceExtension","actual":details.name},
		{"name":"production scene root reports the formal asset path","passed":model.scene_file_path==ProductionArt.MODEL,"actual":details.scene_file_path},
		{"name":"World install result reports the formal asset path","passed":str(art.get("model_path",""))==ProductionArt.MODEL,"actual":details.model_path},
		{"name":"exactly one direct production instance is assembly.model","passed":instances.size()==1 and bool(instances[0].is_assembly_model),"actual":instances},
		{"name":"no historical diagnostic candidate sibling is installed","passed":details.candidate_absent,"actual":details.candidate_absent}]
	return {"details":details,"checks":rows}

func _production_arguments_valid() -> bool:
	var profiles := 0
	var outputs := 0
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--qa-profile="): profiles += 1; profile = arg.trim_prefix("--qa-profile=")
		elif arg.begins_with("--capture-output="): outputs += 1; output = arg.trim_prefix("--capture-output=")
		else: return false
	var regex := RegEx.new()
	if regex.compile("^qa_visual_clinic_east_maintenance_production_[A-Za-z0-9_-]+$") != OK: return false
	if profiles != 1 or outputs != 1 or regex.search(profile) == null: return false
	output = ProjectSettings.globalize_path(output).replace("\\", "/").simplify_path()
	var allowed: String = ProjectSettings.globalize_path(OWN + "evidence").replace("\\", "/").simplify_path()
	if output.get_base_dir().to_lower() != allowed.to_lower() or not output.get_file().begins_with("production-"): return false
	if DirAccess.dir_exists_absolute(output) or FileAccess.file_exists(output): return false
	if DirAccess.dir_exists_absolute("user://profiles_v3/" + profile) or FileAccess.file_exists("user://profiles_v3/" + profile): return false
	return OS.is_debug_build() and Engine.physics_ticks_per_second == 60 and DisplayServer.get_name() != "headless" \
		and RenderingServer.get_current_rendering_method() == "gl_compatibility" and RenderingServer.is_render_loop_enabled()

func _audit_production_physics(installed: Dictionary) -> void:
	var ground: StaticBody3D = installed.ground
	var collider: CollisionShape3D = installed.shape_node
	var terrain = session.world.waterfront
	var expected: PackedVector3Array = terrain.collision_faces(ground.position)
	var actual := PackedVector3Array()
	if collider.shape is ConcavePolygonShape3D: actual = collider.shape.get_faces()
	_check(ground == session.clinic.module.fixed_bodies.Ground and ground.collision_layer == 1 and ground.collision_mask == 0
		and ground.transform.is_equal_approx(Transform3D(Basis.IDENTITY, Vector3(0,-.2,0)))
		and collider.transform.is_equal_approx(Transform3D.IDENTITY)
		and collider.shape is ConcavePolygonShape3D and collider.shape.backface_collision
		and actual.to_byte_array() == expected.to_byte_array(),
		"production keeps the original Ground identity, layers, local pose and exact terrain collision faces")
	var mismatches: Array = []
	for path: String in physics_before:
		var row: Dictionary = physics_before[path]
		if row.has("server") and not row.server.is_equal_approx(row.world): mismatches.append(path)
	_check(mismatches.is_empty(), "every live world PhysicsBody pose agrees with its same-frame PhysicsServer pose")
	# Independent configured terrain: compare public original geometry, not a
	# replacement generated by the installer or rounded Mesh.get_faces cache.
	var baseline := ProductionTerrain.new()
	var configured: Dictionary = baseline.configure(session.clinic.module.ground_art.surface_regions)
	var same: bool = configured.get("ok", false) and _digest(baseline.definition()) == _digest(terrain.definition())
	for part: String in terrain.part_ids(): same = same and _digest(baseline.geometry(part)) == _digest(terrain.geometry(part))
	_check(same, "visual installation leaves all original configured terrain geometry and authored-region definitions intact")
	measurements.physics = {"world_body_count":physics_before.size(), "ground_rid":ground.get_rid().get_id(),
		"ground_shape_rid":collider.shape.get_rid().get_id(), "expected_collision_sha256":_digest(expected),
		"actual_collision_sha256":_digest(actual), "server_pose_mismatches":mismatches,
		"scope":"exact original Terrain collision; current four-facility poses and post-capture stability, not a replayed installation"}

func _audit_production_surface(installed: Dictionary) -> void:
	# East bank installation retains its actual output geometry before the floor
	# was clipped. Read that immutable report; do not reinstall either bank.
	var prior: Dictionary = session.world.east_revetment_art.geometry.dry_surface
	dry_before = prior.faces
	var after: PackedVector3Array = _raw_faces(installed.meshes.dry_surface.mesh)
	var holes: Array[Rect2] = []
	var hole_records: Array = []
	for id: String in FOOT_IDS:
		var foot: StaticBody3D = session.world.shared_access.fixed_bodies[id]
		var colliders: Array = foot.find_children("*", "CollisionShape3D", true, false)
		if not _check(colliders.size() == 1 and colliders[0].shape is BoxShape3D, "real production footprint collider found: " + id): continue
		var collider: CollisionShape3D = colliders[0]
		var box: BoxShape3D = collider.shape
		var bounds: AABB = collider.global_transform * AABB(-box.size*.5, box.size)
		holes.append(Rect2(bounds.position.x, bounds.position.z, bounds.size.x, bounds.size.z))
		hole_records.append({"id":id,"minimum":_vec(bounds.position),"maximum":_vec(bounds.end)})
	var region := Rect2(16.9,2,7.6,13.6)
	var before_in: float = _rect_area(dry_before,region)
	var after_in: float = _rect_area(after,region)
	var before_holes := 0.0
	var after_holes := 0.0
	for hole: Rect2 in holes:
		before_holes += _rect_area(dry_before,hole)
		after_holes += _rect_area(after,hole)
	var removed: float = _area(dry_before)-_area(after)
	_check(holes.size() == 5 and absf(before_holes-1.16)<.0002 and absf(after_holes-before_holes)<.0002,
		"five production foot holes retain 1.16m2 original ground without a visible overlay")
	_check(absf(before_in-before_holes-97.545)<.0002 and absf(removed-97.545)<.0002
		and absf(after_in-after_holes)<.0002 and absf((_area(dry_before)-before_in)-(_area(after)-after_in))<.0002,
		"production raw surface removes exactly 97.545m2 from the actual two-bank remainder and nothing outside the bay")
	var attributes: Dictionary = _attribute_report(installed.meshes.dry_surface.mesh)
	_check(attributes.finite, "production remainder raw positions and UV are finite")
	_check(attributes.winding, "production remainder raw cross_squared > 1e-14 and cross dot normal < 0")
	_check(attributes.metric_uv, "production remainder raw worldXZ UV error is below the original 1e-5 threshold")
	var others: Dictionary = {}
	for part: String in installed.meshes:
		if part == "dry_surface": continue
		var expected: PackedVector3Array = session.world.east_revetment_art.geometry.bank.faces if part == "bank" else session.world.waterfront.geometry(part).faces
		var current: PackedVector3Array = _raw_faces(installed.meshes[part].mesh)
		var unchanged: bool = expected.to_byte_array() == current.to_byte_array()
		_check(unchanged, "production retains original raw visible geometry: " + part)
		others[part] = {"matches":unchanged,"sha256":_digest(current)}
	measurements.partition = {"source":"actual east_revetment_art.geometry.dry_surface before production floor clipping",
		"before_area_m2":_area(dry_before),"after_area_m2":_area(after),"removed_m2":removed,
		"inside_before_m2":before_in,"inside_after_m2":after_in,"hole_area_m2":after_holes,"actual_holes":hole_records}
	measurements.attributes = attributes
	measurements.unchanged_parts = others

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
		var count: int = _raw_faces(view.mesh).size()/3
		triangles += count
		var material := view.get_active_material(0) as BaseMaterial3D
		var textures: Dictionary = {}
		var pbr: bool = material != null and view.mesh.get_surface_count() == 1
		if material != null:
			materials[material.get_instance_id()] = true
			pbr = pbr and material.transparency == BaseMaterial3D.TRANSPARENCY_DISABLED and material.normal_enabled
			for slot: String in ["albedo_texture","normal_texture","roughness_texture","metallic_texture"]:
				var texture: Texture2D = material.get(slot)
				var size: int = 2048 if str(view.name) == "FloorSurface" else 1024
				pbr = pbr and texture is CompressedTexture2D and texture.get_width() == size and texture.get_height() == size
				textures[slot] = {"path":texture.resource_path,"size":[texture.get_width(),texture.get_height()]} if texture != null else {"missing":true}
		_check(pbr and view.is_visible_in_tree() and view.mesh.resource_path.get_slice("::",0) == ProductionArt.MODEL,
			"actual production-path opaque PBR, texture resolution and visible mesh: " + str(view.name))
		rows.append({"name":str(view.name),"triangles":count,"surfaces":view.mesh.get_surface_count(),"mesh_path":view.mesh.resource_path,
			"minimum":_vec(actual.position),"maximum":_vec(actual.end),"textures":textures})
	_check(assembly.meshes.size()==2 and triangles==16724 and materials.size()==2,
		"production model has two meshes/two surfaces/two materials and 16724 actual raw triangles")
	_check(bounds.position.is_equal_approx(Vector3(16.9,-.18,2)) and bounds.end.is_equal_approx(Vector3(24.5,0,15.6)),
		"production model is at its authored metre origin and exact world envelope")
	_check(assembly.model.find_children("*","CollisionObject3D",true,false).is_empty(), "production visual extension adds no collider")
	measurements.imported = {"path":ProductionArt.MODEL,"sha256":FileAccess.get_sha256(ProductionArt.MODEL),"meshes":rows,
		"minimum":_vec(bounds.position),"maximum":_vec(bounds.end),"triangles":triangles}

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
	_check(not hashes_before.is_empty() and hashes_before == after, "all actual runtime/imported/QA input bytes stay unchanged through cleanup")
	_check(shots.size()==2, "two requested production MAIN 720p views were saved")
	var logged: Dictionary = capture_logger.snapshot()
	_check(int(logged.error_count)==0, "zero engine/script/shader errors through cleanup")
	var passed := true
	for row: Dictionary in checks: passed = passed and bool(row.passed)
	var report := {"passed":passed,"status":"production_World_automatic_install_actual_MAIN_not_whole_region_art_acceptance",
		"profile":profile,"checks":checks,"measurements":measurements,"shots":shots,"placements":placements,"fixture":fixture,
		"inventories":inventories,"input_sha256_before":hashes_before,"input_sha256_after":after,"engine_log":logged,
		"engine":Engine.get_version_info(),"GPU":RenderingServer.get_video_adapter_name(),"renderer":RenderingServer.get_current_rendering_method(),
		"elapsed_seconds":float(Time.get_ticks_usec()-started_usec)/1000000.0,
		"limits":["Production World alone installs the model. The probe never calls install or creates replacement physics.",
			"Old27 history and two frozen camera poses are explicit QA fixtures, not playthrough or flown-route evidence.",
			"Historical candidate helper is reused only for raw-array measurements, joint rays and camera tools.",
			"Triangle samples are not an exhaustive all-surface proof. No performance/LAN/human or whole-region art acceptance."]}
	var file := FileAccess.open(output.path_join("state_checks.json"),FileAccess.WRITE)
	var wrote := file != null
	if wrote:
		file.store_string(JSON.stringify(report,"\t",true,true)); file.flush()
		wrote = file.get_error()==OK
		file.close()
	print("EAST_MAINTENANCE_PRODUCTION ",JSON.stringify({"passed":passed and wrote,"checks":checks.size(),"shots":shots.size(),"output":output}))
	OS.remove_logger(capture_logger)
	quit(0 if passed and wrote else 1)
