extends SceneTree
## Real GameSession + four-axis input probe. Owner runs this serially, headless.
## Never assigns aircraft pose/velocity/telemetry or tutorial completion state.
var session: GameSessionV2
var qa_case = ""
var failures: Array[String] = []
var checks = 0
var transitions: Array = []
var samples: Array = []
var elapsed = 0.0
var step_elapsed = 0.0
var previous_step = ""
var start_position = Vector3.ZERO
var brake_speed_seen = false
var zoom_sent = false
var rewards_before: Dictionary
const DT = 1.0 / 60.0

func _initialize() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--v2-qa=tutorial_physics_"): qa_case = argument.trim_prefix("--v2-qa=").validate_filename()
	if qa_case.is_empty() or DisplayServer.get_name() != "headless" or not OS.is_debug_build():
		printerr("Requires a debug headless runtime and fresh --v2-qa=tutorial_physics_<case>.")
		quit(2)
		return
	Engine.physics_ticks_per_second = 60
	call_deferred("_run")

func check(condition: bool, description: String) -> void:
	checks += 1
	if not condition: failures.append(description)
	print("TUTORIAL_PHYSICS_CHECK ",JSON.stringify({"pass":condition,"check":description}))

func _reward_snapshot() -> Dictionary:
	var data: Dictionary = session.repository.data
	return {"wallet":data.wallet.duplicate(true),"campaign":data.campaign.duplicate(true),"records":data.records.duplicate(true),"owned_airframes":data.owned_airframes.duplicate(),"owned_modules":data.owned_modules.duplicate()}

func _run() -> void:
	session = GameSessionV2.new()
	root.add_child(session)
	await process_frame
	if not session.qa_mode or session.repository.root_path != "user://qa_v2/session_"+qa_case:
		printerr("Refusing nonisolated profile")
		quit(2)
		return
	if not session.repository.data.settings.get("tutorial_v22",{}).is_empty() or not session.repository.data.campaign.completed_missions.is_empty():
		printerr("Choose a fresh tutorial_physics case name; this probe does not reset profiles")
		quit(2)
		return
	# Use the same persisted settings API as the UI; no fixture writes to physics.
	session.update_setting("control_mode","assisted")
	session.update_setting("environment_preset","calm")
	session.update_setting("environment_wind",0.0)
	session.update_setting("environment_interference",0.0)
	session.update_setting("environment_weather",0.0)
	session.input.test_enabled = true
	rewards_before = _reward_snapshot()
	session.launch_exploration("R1")
	check(session.flight_active and is_instance_valid(session.pilot),"Real R1 exploration launches")
	if not session.flight_active or not is_instance_valid(session.pilot):
		_finish()
		return
	check(not is_instance_valid(session.runner),"No mission runner can grant task completion")
	start_position = session.pilot.global_position
	session.tutorial.start("M01")
	while elapsed < 100.0 and session.tutorial.get_state().active:
		_drive()
		await physics_frame
		elapsed += DT
		step_elapsed += DT
		if not session.flight_active or not is_instance_valid(session.pilot) or paused:
			check(false,"Flight remains active and unpaused during actual input")
			break
		# QA sessions intentionally suppress the normal tutorial tick. Supply its
		# genuine telemetry and the frame accepted by the real input adapter.
		session.tutorial.physics_update(DT,session.pilot,session.input.last_frame)
		if int(round(elapsed*60.0)) % 60 == 0: samples.append(_sample())
		if step_elapsed > 22.0:
			check(false,"Step timeout: "+previous_step)
			break
	_set_axes()
	var completed: Dictionary = session.tutorial.get_state()
	check(completed.status == "completed" and not completed.active and completed.index == 8,"M01 completes all eight steps using real physics and camera API")
	check(transitions.map(func(entry): return entry.step) == ["lift","hover","yaw90","forward","strafe","brake","land","zoom"],"All eight skills were visited in order")
	check(session.input.last_frame.get("source","") == "test","Real input adapter accepted test axes")
	check(_reward_snapshot() == rewards_before,"Flight tutorial does not grant wallet, campaign, unlock, or record rewards")
	if completed.status == "completed": await _lifecycle()
	_finish()

func _drive() -> void:
	var state: Dictionary = session.tutorial.get_state()
	var step = str(state.step_id)
	if step != previous_step:
		previous_step = step
		step_elapsed = 0.0
		brake_speed_seen = false
		zoom_sent = false
		var snapshot = _sample()
		snapshot["step"] = step
		transitions.append(snapshot)
		print("TUTORIAL_PHYSICS_STEP ",JSON.stringify(snapshot))
	var pilot = session.pilot
	match step:
		"lift": _set_axes(0,clampf((3.5-pilot.ground_distance)*0.65,-0.35,0.55),0,0,true)
		"hover", "yaw90": _set_axes(0.55 if step == "yaw90" else 0.0,0,0,0,true)
		"forward": _set_axes(0,0,0,0.4)
		"strafe": _set_axes(0,0,0.4,0)
		"brake":
			if Vector2(pilot.linear_velocity.x,pilot.linear_velocity.z).length() > 2.5: brake_speed_seen = true
			_set_axes(0,0,0,0 if brake_speed_seen else 0.45,brake_speed_seen)
		"land":
			# Fly back over the real start pad before descending; never move the body.
			var displacement = start_position-pilot.global_position
			displacement.y = 0
			var speed = Vector2(pilot.linear_velocity.x,pilot.linear_velocity.z).length()
			if displacement.length() > 0.55:
				var desired = displacement.limit_length(2.0)
				var right = Vector3(cos(pilot.heading),0,-sin(pilot.heading))
				var forward = Vector3(-sin(pilot.heading),0,-cos(pilot.heading))
				_set_axes(0,0,clampf(desired.dot(right)/float(pilot.stats.speed_mps),-.4,.4),clampf(desired.dot(forward)/float(pilot.stats.speed_mps),-.4,.4))
			else: _set_axes(0,-.28 if speed < .4 else 0.0,0,0,true)
		"zoom":
			_set_axes(0,0,0,0,true)
			# Let director capture the camera baseline before invoking the real API.
			if step_elapsed > .1 and not zoom_sent:
				session.camera_zoom(1)
				zoom_sent = true

func _set_axes(yaw = 0.0, vertical = 0.0, roll = 0.0, pitch = 0.0, brake = false) -> void:
	session.input.test_frame = {"axes":{"left_x":yaw,"left_y":vertical,"right_x":roll,"right_y":pitch},"held":["brake"] if brake else []}

func _lifecycle() -> void:
	session.show_hangar()
	await process_frame
	session.launch_exploration("R1")
	session.tutorial.configure(session)
	session.tutorial.auto_start("M01")
	check(session.tutorial.get_state().status == "completed" and not session.tutorial.get_state().active,"Completed lesson remains inactive on real flight reentry")
	for repeat_index in 2:
		for deferred_status in ["skipped","deferred"]:
			session.tutorial.replay("M01")
			if deferred_status == "skipped": session.tutorial.skip()
			else: session.tutorial.later()
			session.tutorial.configure(session)
			session.tutorial.auto_start("M01")
			var state: Dictionary = session.tutorial.get_state()
			check(not state.active and state.status == deferred_status,"Persisted "+deferred_status+" survives reentry cycle "+str(repeat_index+1))
			check(bool(state.journal.courses.M01.completed),"Replay lifecycle retains previous completion")
			check(_reward_snapshot() == rewards_before,"No repeated reward after "+deferred_status+" cycle "+str(repeat_index+1))
	# An in-progress replay must resume the achieved step after an actual rebuild.
	session.tutorial.replay("M01")
	previous_step = ""
	var resume_seconds = 0.0
	while session.tutorial.get_state().index == 0 and resume_seconds < 15.0:
		_drive()
		await physics_frame
		resume_seconds += DT
		session.tutorial.physics_update(DT,session.pilot,session.input.last_frame)
	var resume_index = int(session.tutorial.get_state().index)
	check(resume_index == 1,"Replay reaches hover through a second real takeoff")
	_set_axes()
	session.show_hangar()
	await process_frame
	session.launch_exploration("R1")
	session.tutorial.configure(session)
	session.tutorial.auto_start("M01")
	var resumed: Dictionary = session.tutorial.get_state()
	check(resumed.active and resumed.replaying and resumed.index == resume_index,"Persisted in-progress replay resumes at achieved step on real reentry")
	check(session.tutorial.baseline.is_empty(),"Flight rebuild clears displacement evidence")
	session.tutorial.later()
	check(not session.tutorial.get_state().save_pending,"Learning journal saved successfully")
	check(_reward_snapshot() == rewards_before,"Every lifecycle operation leaves gameplay rewards unchanged")

func _sample() -> Dictionary:
	var p: Vector3 = session.pilot.global_position
	var v: Vector3 = session.pilot.linear_velocity
	return {"seconds":elapsed,"position":[p.x,p.y,p.z],"velocity":[v.x,v.y,v.z],"agl":session.pilot.ground_distance,"heading_deg":rad_to_deg(session.pilot.heading),"grounded":session.pilot.is_landed(),"camera_size":session.camera.size,"input":session.input.last_frame.duplicate(true)}

func _finish() -> void:
	var result = {"suite":"V22_tutorial_real_physics","case":qa_case,"checks":checks,"failures":failures,"passed":failures.is_empty(),"seconds":elapsed,"transitions":transitions,"samples":samples,"scope":"Actual GameSession R1 physics and four-axis test input. M01 tutorial only, not mission completion, GPU, phone, or human comfort evidence."}
	var directory = "res://artifacts/v22"
	DirAccess.make_dir_recursive_absolute(directory)
	var file = FileAccess.open(directory.path_join(qa_case+".json"),FileAccess.WRITE)
	if file: file.store_string(JSON.stringify(result,"\t",true,true)); file.close()
	print("TUTORIAL_PHYSICS_RESULT ",JSON.stringify(result,"",true,true))
	paused=false
	session.phone.stop_server()
	session.queue_free()
	await process_frame
	await process_frame
	await create_timer(.2,true,false,true).timeout
	quit(0 if failures.is_empty() else 1)
