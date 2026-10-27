extends "res://scripts_tools/v3/capture_clinic_integrated.gd"
## Actual MAIN and normal FlightBody integration. Historical27, initial poses and
## analogue input frames are declared QA fixtures, not human play or timing proof.
var water_entries := 0
var water_rescues := 0
var water_damage: Array[Dictionary] = []

func _run() -> void:
	started_usec = Time.get_ticks_usec()
	if not _arguments_valid():
		push_error("WATERFRONT_CAPTURE requires fresh clinic-integrated paths and Compatibility")
		OS.remove_logger(capture_logger)
		quit(2)
		return
	if DirAccess.make_dir_recursive_absolute(output) != OK:
		quit(2)
		return
	create_timer(180.0, true, false, true).timeout.connect(_timeout)
	root.size = SIZE
	session = MAIN.instantiate()
	root.add_child(session)
	if not _check(session.profile_ready and session.start_flight("solo"), "actual isolated MAIN starts"):
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
	body = session.players[1]
	if not _check(session.region_id == "I2" and session._facilities_ready() and session.world.build_errors.is_empty()
		and session.world.waterfront_install.get("ok", false), "production I2 owns real static waterfront and four restored facilities"):
		await _finish()
		return
	for directory in ["res://scripts/v3", "res://data/v3", "res://scenes/v3"]: _collect_inputs(directory)
	input_paths.append_array(INPUTS)
	input_paths.append("res://scripts_tools/v3/capture_waterfront_integrated.gd")
	inventories.I2 = _scene_inventory(session.world)
	for path in inventories.I2.imported_sources + inventories.I2.material_sources:
		if path not in input_paths: input_paths.append(path)
	_add_import_hashes()
	hashes_before = _input_hashes()
	var saved_before: Dictionary = session.store.snapshot()
	var safe_at: Vector3 = body.safe_position
	_check(Regions.contains("I2", safe_at) and safe_at.distance_to(body.global_position)<.001,
		"region travel resets rescue checkpoint to this actual arrival")
	body.water_entered.connect(func(): water_entries += 1)
	body.rescued.connect(func(): water_rescues += 1)
	physical_probes.terrain = session.world.waterfront.definition()
	var space: PhysicsDirectSpaceState3D = session.get_world_3d().direct_space_state
	var bed := space.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(14.75,1,6),Vector3(14.75,-3,6),1))
	_check(bed.get("collider") == session.clinic.module.fixed_bodies.Ground and absf(bed.get("position",Vector3.ZERO).y+2.8)<.002,
		"river column reaches actual bed at -2.8, with no old Y0 or water-surface collider")
	physical_probes.bed = _ray_record(bed)
	var paving := space.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(23,1,0),Vector3(23,-1,0),1))
	_check(paving.get("collider") == session.clinic.module.fixed_bodies.Ground and absf(paving.get("position",Vector3.ONE).y)<.002,
		"authored maintenance paving retains the same Ground body and Y0 support")
	physical_probes.paving = _ray_record(paving)
	await _place(Vector3(15,3,23), "south basin overview")
	await _capture("01-I2-south-basin-default", "Actual production terrain A: graybox bank/bed geometry and non-colliding water; normal fixed 26m camera.")
	await _place(Vector3(14.75,-.35,16), "below bank level, above water")
	await _capture("02-I2-below-bank", "Pilot is physically below the Y0 bank and above -1.2 water. Initial pose is a declared QA placement, not an input flight.", 2)
	if not await _fly_channel(Vector3(14.75,-.35,23),Vector3(14.75,-.35,6),"northbound"):
		await _finish()
		return
	await _capture("03-I2-channel-northbound-stop", "Actual analogue-input traversal and braking with FlightBody forces, wind sampling and unchanged hull; scripted QA, not human control validation.")
	if not await _fly_channel(body.global_position,Vector3(14.75,-.35,23),"southbound"):
		await _finish()
		return
	await _capture("04-I2-channel-southbound-stop", "Same actual corridor flown southbound with normal forces and braking. No pose interpolation during the measured flight.")
	# Assisted descent can bob at the surface; it does not guarantee sustained
	# immersion. Declare a deep-water/zero-throttle starting fixture and let the
	# normal forces, timer, damage and rescue result run without being injected.
	await _place(Vector3(14.75,-2.2,20), "deep-water initial pose for sustained immersion, not an input-driven dive")
	var previous_mode: String = session.inputs.mode
	var previous_throttle: float = session.inputs.throttle
	session.inputs.mode = "manual_throttle"
	session.inputs.throttle = 0.0
	fixture["water_probe"] = {"initial_y":-2.2,"mode":"manual_throttle","throttle":0.0,"timer_or_health_injected":false}
	body.hold_height = -2.2
	body.freeze = false
	paused = false
	var first_rescues := water_rescues
	var health_before: float = body.health
	var expected_damage: Dictionary = body.preview_combat_hit(12.0, Vector3.ZERO, body.global_position, "collision")
	body.damage_resolved.connect(func(receipt: Dictionary): water_damage.append(receipt.duplicate(true)))
	var first_tick := simulated_ticks
	for unused in range(420):
		session.inputs.test_frame = {"axes":{"left_y":-1.0},"held":[],"edges":[]}
		session._physics_process(DT)
		simulated_ticks += 1
		await physics_frame
		if water_rescues > first_rescues: break
	var rescued_at: Vector3 = body.global_position
	_check(water_entries>0 and water_rescues==first_rescues+1 and Regions.contains("I2",rescued_at)
		and rescued_at.distance_to(safe_at+Vector3.UP*1.5)<1.0, "sustained deep-water exposure runs normal timed rescue inside this region")
	_check(water_damage.size()==1 and not expected_damage.is_empty()
		and absf(float(water_damage[0].damage)-float(expected_damage.damage))<.001
		and absf(body.health-(health_before-float(water_damage[0].damage)))<.001,
		"one actual water damage receipt matches ordinary damage-model preview and health loss")
	physical_probes.rescue = {"entries":water_entries,"rescues":water_rescues,"at":_vec(rescued_at),
		"safe_before":_vec(safe_at),"fixed_steps":simulated_ticks-first_tick,"health_before":health_before,
		"expected_damage":expected_damage,"damage_receipts":water_damage,"health_after":body.health}
	_hold()
	session.inputs.mode = previous_mode
	session.inputs.throttle = previous_throttle
	await _capture("05-I2-actual-water-rescue", "Actual existing water rescue after sustained immersion, using this region's checkpoint. No timer, health, or rescue result was injected.")
	var protected_history := true
	for id in saved_before.world.completed_objectives:
		protected_history = protected_history and id in session.store.snapshot().world.completed_objectives
	for id in saved_before.world.actions.opening.completed_actions:
		protected_history = protected_history and id in session.store.snapshot().world.actions.opening.completed_actions
	_check(protected_history,
		"waterfront traversal and rescue preserve completed story/actions")
	_check(session._save_environment(), "actual four-facility save succeeds after terrain traversal")
	var saved: Dictionary = session.store.snapshot()
	var reread = Store.new(session.store.root_path)
	var loaded: Dictionary = reread.load_profile()
	_check(loaded.ok and _same(saved,reread.snapshot()), "independent Store rereads exact post-terrain save")
	await _finish()

func _fly_channel(start: Vector3, target: Vector3, label: String) -> bool:
	await _place(start, label + " start pose")
	body.hold_height = start.y
	body.freeze = false
	paused = false
	var first := simulated_ticks
	var collisions: int = body.collision_count
	var maximum_speed := 0.0
	var minimum_y := start.y
	var maximum_y := start.y
	var outside_channel_steps := 0
	var reached := false
	var sampled := false
	for unused in range(900):
		var offset: Vector3 = target-body.global_position
		var desired := Vector3(offset.x,0,offset.z)*1.3
		desired = desired.limit_length(3.2)
		var planar: Vector3 = desired/float(body.stats.speed_mps)
		var right: Vector3 = session.camera.global_basis.x
		right.y = 0
		right = right.normalized()
		var forward: Vector3 = -session.camera.global_basis.z
		forward.y = 0
		forward = forward.normalized()
		var brake: bool = Vector2(offset.x,offset.z).length()<.35
		session.inputs.test_frame = {"axes":{"right_x":planar.dot(right),"right_y":planar.dot(forward)},"held":["brake"] if brake else [],"edges":[]}
		session._physics_process(DT)
		simulated_ticks += 1
		await physics_frame
		maximum_speed = maxf(maximum_speed,body.linear_velocity.length())
		minimum_y = minf(minimum_y,body.global_position.y)
		maximum_y = maxf(maximum_y,body.global_position.y)
		if not session.world.waterfront.is_water_xz(body.global_position.x,body.global_position.z): outside_channel_steps += 1
		sampled = sampled or (body.environment_sample.get("water",false) and absf(float(body.environment_sample.get("water_height",0))+1.2)<.001)
		if brake and body.linear_velocity.length()<.4:
			reached = true
			break
	var ending: Vector3 = body.global_position
	live_windows.append({"name":label,"start":_vec(start),"target":_vec(target),"ending":_vec(ending),
		"fixed_steps":simulated_ticks-first,"maximum_speed_mps":maximum_speed,"minimum_y":minimum_y,"maximum_y":maximum_y,
		"outside_channel_steps":outside_channel_steps,
		"collisions":body.collision_count-collisions,"sampled_real_water":sampled,"reached":reached,
		"method":"QA analogue input through production Session, real physics integration; no intermediate transforms"})
	var okay := _check(reached and body.collision_count==collisions and sampled and not body.water_contact
		and maximum_y<0.0 and outside_channel_steps==0 and absf(ending.y-start.y)<.3, "normal physics clears and brakes below bank in " + label)
	_hold()
	return okay

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
	_check(not hashes_before.is_empty() and hashes_before==after,"captured production inputs unchanged")
	_check(shots.size()==5,"five real MAIN views saved")
	var logged: Dictionary = capture_logger.snapshot()
	_check(int(logged.error_count)==0,"zero engine/shader/script errors including cleanup")
	var passed := true
	for row in checks: passed = passed and bool(row.passed)
	var report := {"passed":passed,"status":"graybox_space_and_runtime_diagnostic_not_final_art",
		"profile":profile,"checks":checks,"shots":shots,"QA_placements":placements,"fixture":fixture,
		"live_windows":live_windows,"physical_probes":physical_probes,"input_sha256_before":hashes_before,
		"input_sha256_after":after,"engine_log":logged,"engine":Engine.get_version_info(),
		"GPU":RenderingServer.get_video_adapter_name(),"renderer":RenderingServer.get_current_rendering_method(),
		"limits":["Historical27 and initial poses are declared QA fixtures.","Analogue input is scripted, not human enjoyment/comfort evidence.",
			"Terrain is a graybox for spatial review, not final shoreline artwork.","Single-process source run, not LAN, standalone or performance acceptance."]}
	var file := FileAccess.open(output.path_join("state_checks.json"),FileAccess.WRITE)
	var wrote := file!=null
	if wrote:
		file.store_string(JSON.stringify(report,"\t",true,true))
		file.flush()
		wrote = file.get_error()==OK
		file.close()
	print("WATERFRONT_INTEGRATED_CAPTURE ",JSON.stringify({"passed":passed and wrote,"checks":checks.size(),"shots":shots.size(),"output":output}))
	OS.remove_logger(capture_logger)
	quit(0 if passed and wrote else 1)
