extends "res://scripts_tools/v3/capture_waterfront_integrated.gd"
## Actual MAIN/Compatibility/normal camera. Seven explicitly frozen review poses;
## no additional light, material, model or physical obstacle is added for capture.

func _run() -> void:
	started_usec = Time.get_ticks_usec()
	if not _arguments_valid():
		push_error("REVETMENT_CAPTURE requires fresh isolated clinic paths and Compatibility")
		quit(2)
		return
	if DirAccess.make_dir_recursive_absolute(output) != OK:
		quit(2)
		return
	create_timer(120.0,true,false,true).timeout.connect(_timeout)
	root.size = SIZE
	session = MAIN.instantiate()
	root.add_child(session)
	if not _check(session.profile_ready and session.start_flight("solo"),"isolated actual MAIN starts"):
		await _finish()
		return
	_hold()
	if not _seed_history():
		await _finish()
		return
	session._ui_action("travel_to",{"region_id":"I2"})
	_hold()
	await physics_frame
	await physics_frame
	body = session.players[1]
	if not _check(session.region_id == "I2" and session.world.build_errors.is_empty() and is_instance_valid(session.clinic.module) and session.clinic.module == session.world.clinic and session.clinic.module.is_inside_tree() and session.world.revetment_art.get("ok",false) and session.world.east_revetment_art.get("ok",false),"actual I2 binds its live clinic and both sets of four authored straight-bank lengths"):
		await _finish()
		return
	for directory in ["res://scripts/v3","res://data/v3","res://scenes/v3"]: _collect_inputs(directory)
	# Isolated transport candidates are not a dependency of this MAIN capture.
	input_paths = input_paths.filter(func(path: String) -> bool: return not path.begins_with("res://scripts/v3/candidates/"))
	input_paths.append_array(INPUTS)
	input_paths.append("res://scripts_tools/v3/capture_revetment_integrated.gd")
	inventories.I2 = _scene_inventory(session.world)
	for path in inventories.I2.imported_sources + inventories.I2.material_sources:
		if path not in input_paths: input_paths.append(path)
	_add_import_hashes()
	hashes_before = _input_hashes()
	var art: Dictionary = session.world.revetment_art
	var east: Dictionary = session.world.east_revetment_art
	var installed: Dictionary = session.world.waterfront_install
	var shape: ConcavePolygonShape3D = installed.shape_node.shape
	_check(art.ground == session.clinic.module.fixed_bodies.Ground and art.shape == shape and shape.get_faces() == session.world.waterfront.collision_faces(art.ground.position),"same physical Ground and exact original concave collision faces")
	_check(art.wrapper.find_children("*","CollisionObject3D",true,false).is_empty(),"authored presentation adds no collision body")
	_check(art.parts.size() == 4 and art.material_count == 2,"three shared 4m modules plus one independent short module")
	for part: String in ["bank","dry_surface"]:
		var actual: PackedVector3Array = installed.meshes[part].mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
		_check(actual == east.geometry[part].faces,"rendered "+part+" uses exact twice-clipped remainder")
	for part: String in ["bed","outer","underside","water"]:
		var actual: PackedVector3Array = installed.meshes[part].mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
		_check(actual == session.world.waterfront.geometry(part).faces,"untouched original visible geometry: "+part)
	var records: Array = []
	for part: Dictionary in art.parts:
		var bounds: AABB = part.model.global_transform*part.mesh.mesh.get_aabb()
		_check(absf(bounds.position.x-12.25)<.0001 and absf(bounds.end.x-12.6)<.0001 and absf(bounds.position.y+2.8)<.0001 and absf(bounds.end.y)<.0001,"authored wall remains behind water-side plane: "+str(part.id))
		records.append({"id":part.id,"path":part.path,"sha256":FileAccess.get_sha256(part.path),"triangles":part.triangles,"minimum":_vec(bounds.position),"maximum":_vec(bounds.end)})
	var rays: Array = []
	for z: float in [2.31,6.3,10.3,14.3,15.59]:
		var hit: Dictionary = session.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(14,-.5,z),Vector3(12,-.5,z),1|2|4|8|32))
		_check(hit.get("collider") == art.ground and absf(hit.get("position",Vector3.ZERO).x-12.6)<.002,"original continuous bank collision at join "+str(z))
		rays.append(_ray_record(hit))
	physical_probes.revetment = {"summary":art.summary,"parts":records,"rays":rays,"triangles":art.triangles,"collision_changed":false}
	var east_records: Array = []
	var east_rays: Array = []
	_check(east.ground == art.ground and east.shape == shape and east.parts.size() == 4 and east.material_count == 2 and east.triangles == 16628,"east reused sources share unchanged Ground and expected mesh budget")
	_check(east.wrapper.find_children("*","CollisionObject3D",true,false).is_empty(),"east presentation adds no collision body")
	for part: Dictionary in east.parts:
		var bounds: AABB = part.model.global_transform*part.mesh.mesh.get_aabb()
		_check(absf(bounds.position.x-16.9)<.0001 and absf(bounds.end.x-17.25)<.0001 and absf(bounds.position.y+2.8)<.0001 and absf(bounds.end.y)<.0001,"east wall stays landward of original water plane: "+str(part.id))
		east_records.append({"id":part.id,"path":part.path,"sha256":FileAccess.get_sha256(part.path),"triangles":part.triangles,"minimum":_vec(bounds.position),"maximum":_vec(bounds.end)})
	for z: float in [2.31,6.3,10.3,14.3,15.59]:
		var hit: Dictionary = session.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(15.5,-.5,z),Vector3(18,-.5,z),1|2|4|8|32))
		_check(hit.get("collider") == art.ground and absf(hit.get("position",Vector3.ZERO).x-16.9)<.002,"original east collision at join "+str(z))
		east_rays.append(_ray_record(hit))
	physical_probes.east_revetment = {"summary":east.report,"parts":east_records,"rays":east_rays,"triangles":east.triangles,"collision_changed":false}
	await _place(Vector3(14.75,1.8,10),"west-bank central default view")
	await _capture("01-I2-revetment-default","Actual imported paired straight banks, default production 26m camera. Flared banks and surrounding ground remain unfinished.")
	await _capture("02-I2-revetment-near","Three legal wheel steps; inspect baked weathering, top strip and model joins.",3)
	await _place(Vector3(14.75,-.35,11),"below bank above real water")
	await _capture("03-I2-revetment-below","Frozen QA pose below the bank; real waterline and production occlusion, no flown-route claim.",3)
	await _place(Vector3(14.75,1.8,15),"long-to-short wall connection")
	await _capture("04-I2-revetment-short-joint","Real 4m-to-1.3m join and transition to the remaining gray flare.",4)
	await _place(Vector3(14.75,1.8,4),"north endpoint under bridge")
	await _capture("05-I2-revetment-north-end","North authored endpoint next to unchanged gray cross-bank; normal camera.")
	await _place(Vector3(20.3,1.8,11),"east landward maintenance-side context")
	await _capture("06-I2-east-bank-landward","Fixed production view from the east shore; inspect cap and adjoining unfinished ground.")
	await _place(Vector3(14.75,.2,18),"south opening looking across both straight shore ends")
	await _capture("07-I2-paired-banks-south","Both rigid straight-bank ends and the remaining gray flare; same production camera.")
	await _finish()

func _finish() -> void:
	if finishing: return
	finishing = true
	if is_instance_valid(session):
		session.active = false
		if is_instance_valid(session.network): session.network.close()
		session.free()
	await process_frame
	await process_frame
	var after := _input_hashes()
	_check(not hashes_before.is_empty() and hashes_before == after,"captured production inputs unchanged")
	_check(shots.size() == 7,"seven requested actual MAIN review views saved")
	var logged: Dictionary = capture_logger.snapshot()
	_check(int(logged.error_count) == 0,"zero engine/shader/script errors including cleanup")
	var passed := true
	for row in checks: passed = passed and bool(row.passed)
	var report := {"passed":passed,"status":"actual_import_review_not_whole_region_art_acceptance","profile":profile,
		"checks":checks,"shots":shots,"QA_placements":placements,"fixture":fixture,"physical_probes":physical_probes,
		"input_sha256_before":hashes_before,"input_sha256_after":after,"engine_log":logged,
		"engine":Engine.get_version_info(),"GPU":RenderingServer.get_video_adapter_name(),"renderer":RenderingServer.get_current_rendering_method(),
		"limits":["Historical27 and frozen positions are declared QA fixtures, not playthrough.","Actual MAIN assets/camera/lighting only; no alternative scene.","Two 13.3m straight banks are authored; flared shores and grounds remain incomplete. No night, LAN, performance or human enjoyment acceptance."]}
	var file := FileAccess.open(output.path_join("state_checks.json"),FileAccess.WRITE)
	var wrote := file != null
	if wrote:
		file.store_string(JSON.stringify(report,"\t",true,true))
		file.flush()
		wrote = file.get_error() == OK
		file.close()
	print("REVETMENT_INTEGRATED_CAPTURE ",JSON.stringify({"passed":passed and wrote,"checks":checks.size(),"shots":shots.size(),"output":output}))
	OS.remove_logger(capture_logger)
	quit(0 if passed and wrote else 1)
