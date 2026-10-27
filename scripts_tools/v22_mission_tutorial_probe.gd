extends "res://scripts_tools/qa_v2_continuous.gd"

## Reuses the continuous real-physics driver; only this probe opts QA back into
## the production teaching hooks. No teleports, enemy damage, action completion,
## warning counters, tutorial evidence, or mission outcomes are injected.
## Run with --headless --script res://scripts_tools/v22_mission_tutorial_probe.gd
## -- --v2-qa=continuous_<unique> --qa-job=M02 --qa-seconds=900
## M03 uses the same arguments. Add --qa-full-mission to require mission completion
## as well as the lesson; otherwise stop when the actual lesson is completed.
## --qa-natural-route disables lesson-aware waiting/cover routing and exposes
## whether following task objectives alone can leave a lesson unfinished.

var require_full_mission = false
var natural_route = false
var teaching_started = false
var teaching_tick = -1
var teaching_step = ""
var teaching_visits: Array = []
var real_task_completions: Array = []
var cover_decisions: Array = []
var teaching_samples: Array = []
var hold_position = Vector3.ZERO
var cover_point = Vector3.INF
var cover_phase = ""
var cover_attempt_started = -1.0
var original_auto_fire = true
var probe_changed_auto_fire = false
var last_teaching_sample = -10.0

func _initialize() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument == "--qa-full-mission": require_full_mission = true
		if argument == "--qa-natural-route": natural_route = true
	super._initialize()
	source_fingerprints["res://scripts_tools/v22_mission_tutorial_probe.gd"] = FileAccess.get_sha256("res://scripts_tools/v22_mission_tutorial_probe.gd")
	source_fingerprints["res://scripts/v2/tutorial_director.gd"] = FileAccess.get_sha256("res://scripts/v2/tutorial_director.gd")

func _drive(action: Dictionary) -> void:
	if job_id not in ["M02","M03"]:
		stop_reason = "unsupported_tutorial_course"
		maximum_seconds = session.run_seconds
		return
	if not teaching_started:
		if not is_instance_valid(session.tutorial):
			stop_reason = "tutorial_director_missing"
			maximum_seconds = session.run_seconds
			return
		teaching_started = true
		original_auto_fire = bool(session.repository.data.settings.get("auto_fire",true))
		session.runner.action_completed.connect(_observe_task_completion)
		session.tutorial.auto_start(job_id)
		output_file = "res://artifacts/v2/v22_mission_tutorial_" + job_id + "_" + qa_case + ".json"
		_observe_step()
	_tick_teaching()
	var state: Dictionary = session.tutorial.get_state()
	if str(state.status) == "completed":
		_restore_auto_fire()
		if not require_full_mission:
			stop_reason = "tutorial_completed"
			maximum_seconds = session.run_seconds
			_write_input(Vector3.ZERO,0.0,false)
			return
	if natural_route:
		super._drive(action)
		return
	if job_id == "M02" and str(state.step) == "swing":
		control_mode = "tutorial:stabilize_real_cargo"
		_move_to(hold_position,false,false)
		return
	if job_id == "M03" and str(state.step) == "cover":
		# This is the same user-facing setting that permits holding fire. The
		# second real defend wave must remain alive long enough to practice cover.
		if not probe_changed_auto_fire:
			session.update_setting("auto_fire",false)
			probe_changed_auto_fire = not bool(session.combat.auto_fire)
		if _live_enemies().size() > 0:
			_drive_cover(action)
			return
	super._drive(action)

func _tick_teaching() -> void:
	var tick = Engine.get_physics_frames()
	if tick == teaching_tick: return
	teaching_tick = tick
	# qa_mode suppresses exactly these two calls in GameSessionV2. Keep QA save
	# isolation enabled and call the actual implementations once per physics tick.
	session._update_tutorial_evidence(1.0 / float(Engine.physics_ticks_per_second))
	session.tutorial.physics_update(1.0 / float(Engine.physics_ticks_per_second),session.pilot,session.input.last_frame)
	_observe_step()
	if session.run_seconds-last_teaching_sample >= 2.0:
		last_teaching_sample = session.run_seconds
		teaching_samples.append(_teaching_sample())

func _observe_step() -> void:
	var state: Dictionary = session.tutorial.get_state()
	var key = str(state.status)+":"+str(state.step)
	if key == teaching_step: return
	teaching_step = key
	var record = _teaching_sample()
	teaching_visits.append(record)
	print("V22_TEACHING_STEP ",JSON.stringify(record))
	if str(state.step) == "swing":
		hold_position = session.pilot.global_position
		hold_position.y = maxf(hold_position.y,session.world.surface_height(hold_position)+3.2)
	if str(state.step) == "cover":
		cover_point = Vector3.INF
		cover_phase = ""
		cover_attempt_started = -1.0

func _observe_task_completion(action: Dictionary) -> void:
	# Observation only. The production runner signal is already connected to
	# GameSessionV2._tutorial_action_completed by normal session construction.
	real_task_completions.append({"seconds":session.run_seconds,"stage":session.runner.stage.id,
		"action_index":session.runner.action_index,"type":action.type,"poi":action.get("poi_id",""),
		"cargo":action.get("cargo_id",""),"tutorial_step":session.tutorial.get_state().step,
		"position":_vector(session.pilot.global_position)})

func _live_enemies() -> Array:
	var result: Array = []
	for enemy in session.combat.enemies:
		if is_instance_valid(enemy) and enemy.hp > 0.0: result.append(enemy)
	return result

func _all_enemy_rays_blocked(point: Vector3) -> bool:
	var enemies = _live_enemies()
	if enemies.is_empty(): return false
	for enemy in enemies:
		if session.combat.line_clear(enemy.global_position,point,enemy.get_rid(),session.pilot.get_rid()): return false
	return true

func _cover_candidate() -> Vector3:
	var position = session.pilot.global_position
	var best = Vector3.INF
	var best_score = INF
	for building in session.world.obstacles:
		if Vector2(float(building.x)-position.x,float(building.z)-position.z).length() > 75.0: continue
		if float(building.h) < 4.0: continue
		var x = float(building.x)
		var z = float(building.z)
		var half_x = float(building.w)*0.5+3.0
		var half_z = float(building.l)*0.5+3.0
		for point in [Vector3(x-half_x,0,z),Vector3(x+half_x,0,z),Vector3(x,0,z-half_z),Vector3(x,0,z+half_z)]:
			point.y = session.world.surface_height(point)+2.2
			if not _all_enemy_rays_blocked(point): continue
			var occupied = false
			for obstacle in session.world.obstacles:
				if absf(point.x-float(obstacle.x)) < float(obstacle.w)*0.5+1.2 and absf(point.z-float(obstacle.z)) < float(obstacle.l)*0.5+1.2:
					occupied = true
					break
			if occupied: continue
			var score = _horizontal(point-position).length()
			if score < best_score:
				best_score = score
				best = point
	return best

func _drive_cover(action: Dictionary) -> void:
	control_mode = "tutorial:wait_real_warning"
	if cover_attempt_started < 0.0: cover_attempt_started = session.run_seconds
	if session.run_seconds-cover_attempt_started > 100.0:
		stop_reason = "cover_driver_timeout_not_proof_of_unplayability"
		maximum_seconds = session.run_seconds
		_write_input(Vector3.ZERO,0.0,false)
		return
	# Do not create synthetic warning/evidence. Approaching the actual mission
	# enemy with fire withheld must cause CombatV2 to issue its normal telegraph.
	if not session.tutorial_cover_pending:
		super._drive(action)
		return
	if not cover_point.is_finite():
		cover_point = _cover_candidate()
		if not cover_point.is_finite():
			control_mode = "tutorial:no_ray_verified_cover_candidate"
			_write_input(Vector3.ZERO,0.0,false)
			return
		cover_phase = "transfer"
		cover_decisions.append({"seconds":session.run_seconds,"point":_vector(cover_point),
			"warning_serial":session.combat._warning_serial,"rays_blocked_when_selected":true})
		print("V22_TEACHING_COVER ",JSON.stringify(cover_decisions.back()))
	var target = cover_point
	if cover_phase == "transfer":
		# Fly over the real geometry, then descend outside its footprint. All
		# movement still goes through PilotInput and rigid-body forces.
		target.y = 18.0
		if _horizontal(cover_point-session.pilot.global_position).length() < 1.5: cover_phase = "descend"
	control_mode = "tutorial:cover_"+cover_phase
	_move_to(target,false,false)
	if cover_phase == "descend" and session.pilot.global_position.distance_to(cover_point) < 1.3:
		if not _all_enemy_rays_blocked(session.pilot.global_position):
			# The enemy may have flown around the wall during transit; re-plan
			# from current raycasts instead of awarding false cover evidence.
			cover_point = Vector3.INF
			cover_phase = ""

func _write_input(desired_velocity: Vector3, vertical: float, interact: bool) -> void:
	super._write_input(desired_velocity,vertical,interact)
	if not teaching_started or natural_route: return
	var state: Dictionary = session.tutorial.get_state()
	if str(state.step) == "swing":
		session.input.test_frame.held.erase("interact")
		session.input.test_frame.held.erase("fire")
		if _horizontal(session.pilot.linear_velocity).length() > 0.2:
			session.input.test_frame.held.append("brake")
	elif str(state.step) == "cover":
		session.input.test_frame.held.erase("fire")

func _restore_auto_fire() -> void:
	if not probe_changed_auto_fire: return
	session.update_setting("auto_fire",original_auto_fire)
	probe_changed_auto_fire = false

func _teaching_sample() -> Dictionary:
	var state: Dictionary = session.tutorial.get_state()
	return {"seconds":session.run_seconds,"stage":session.stage_index,"action":session.runner.action_index,
		"step":state.step,"status":state.status,"hold":state.hold,"cargo_count":session.pilot.cargo_items.size(),
		"swing_deg":session.pilot.cargo_swing(),"speed":session.pilot.linear_velocity.length(),
		"position":_vector(session.pilot.global_position),"warning_serial":session.combat._warning_serial,
		"observed_warning_serial":session.tutorial_warning_serial,"cover_pending":session.tutorial_cover_pending,
		"cover_seconds":session.tutorial_cover_seconds,"live_enemies":_live_enemies().size(),
		"all_enemy_rays_blocked":_all_enemy_rays_blocked(session.pilot.global_position),
		"task_condition":session.runner.condition}

func _sample() -> Dictionary:
	var result = super._sample()
	if teaching_started: result["tutorial"] = _teaching_sample()
	return result

func _finish() -> void:
	var mission_completed = job_id in session.repository.data.campaign.completed_missions
	var state: Dictionary = session.tutorial.get_state() if is_instance_valid(session.tutorial) else {}
	var course_record: Dictionary = state.get("journal",{}).get("courses",{}).get(job_id,{})
	var lesson_completed = str(state.get("status","")) == "completed" and bool(course_record.get("evidence_complete",false))
	var ok = lesson_completed and (mission_completed or not require_full_mission)
	var record = {"suite":"v22_mission_tutorial_continuous","engine":Engine.get_version_info().string,
		"job_id":job_id,"ok":ok,"tutorial_completed":lesson_completed,"mission_completed":mission_completed,
		"full_mission_required":require_full_mission,"stop_reason":stop_reason,"simulated_seconds":session.run_seconds,
		"driver_strategy":"task_objectives_only" if natural_route else "lesson_guided_stabilization_and_real_cover",
		"elapsed_wall_seconds":(Time.get_ticks_msec()-started_ms)/1000.0,"qa_root":session.repository.root_path,
		"setup_fixture_transactions":setup_transactions,"source_fingerprints_at_start":source_fingerprints,
		"course_record":course_record,"tutorial_visits":teaching_visits,"tutorial_samples":teaching_samples,
		"real_task_completions":real_task_completions,"cover_decisions":cover_decisions,
		"action_visits":transitions,"service_changes":service_changes,"distance_flown_m":distance_flown,
		"damage_taken":session.pilot.damage_taken,"collisions":session.pilot.collision_count,
		"stage_receipts":session.repository.data.campaign.completed_stages.filter(func(id):return str(id).begins_with(job_id+"-")),
		"final":_sample(),"samples":samples,"combat_events":session.combat.events.duplicate(true),
		"final_cargo":_cargo_snapshot(),
		"not_covered_by_guided_success":["delivery-before-swing and independent-practice checkpoint replay variants require separate coverage","M03 clearing the last enemy before practicing cover"],
		"evidence_scope":"Headless continuous real PilotInput/rigid-body/TaskRunner/combat plus actual TutorialDirector and Session evidence hooks. Only isolated prerequisite/equipment setup is seeded. Fire setting and service changes use production user actions. No teleport, injected kills/damage/completions/warnings/teaching evidence. Tutorial-only success does not assert full mission completion. Driver timeout is not proof of human unplayability. No graphics or real controller/phone validation."}
	if output_file.is_empty(): output_file = "res://artifacts/v2/v22_mission_tutorial_"+job_id+"_"+qa_case+".json"
	DirAccess.make_dir_recursive_absolute("res://artifacts/v2")
	var file = FileAccess.open(output_file,FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(record,"\t",true,true))
		file.close()
	print("V22_MISSION_TUTORIAL_SUMMARY ",JSON.stringify({"job":job_id,"ok":ok,"tutorial_completed":lesson_completed,
		"mission_completed":mission_completed,"stop_reason":stop_reason,"step":state.get("step",""),
		"seconds":session.run_seconds,"output":output_file,"task_completions":real_task_completions.size()}))
	paused = false
	session.phone.stop_server()
	session.queue_free()
	await process_frame
	await process_frame
	await create_timer(.2,true,false,true).timeout
	quit(0 if ok else 1)
