extends "res://scripts_tools/v3/acceptance_frontend.gd"
## Observe the shipping assistant through native UI in a fresh ordinary Main.
## No QA driver, pose, health, clock or progress writes.
var observations: Array=[]

func _run() -> void:
	var profile:=""
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--qa-profile="): profile=arg.trim_prefix("--qa-profile=")
		elif arg.begins_with("--output="): output=arg.trim_prefix("--output=")
	if not profile.begins_with("qa_assist94_") or profile!=profile.validate_filename() or not output.is_absolute_path() or FileAccess.file_exists(output) or ".." in output: quit(2); return
	if DirAccess.dir_exists_absolute("user://profiles_v3/"+profile): quit(2); return
	session=Main.instantiate()
	root.add_child(session)
	await _settle()
	front=session.interface.front
	if not _check(logger.errors.is_empty(),"all assistant modules compile and initialize",logger.errors): await _finish(); return
	if not _check(is_instance_valid(session.flight_assist),"production assistant loaded"): await _finish(); return
	_check(not session.active and not session.flight_assist.enabled,"lobby never starts flying or assisting automatically")
	front.navigate("assist")
	await _settle()
	await _capture("assist_page")
	var launch: BaseButton=_button_containing("单人出航并开启")
	if not _check(launch!=null,"normal assist launch button exists"): await _finish(); return
	await _accept(launch)
	var deadline:=Time.get_ticks_msec()+35000
	while (not session.active or front._loading or not session.flight_assist.enabled) and Time.get_ticks_msec()<deadline: await process_frame
	if not _check(session.active and session.flight_assist.enabled,"native lobby action enters ordinary flight and enables assistant"): await _finish(); return
	_check(session.qa_mode.is_empty(),"no alternate QA flight driver")
	var first_id: String=session.flight_assist.status().objective_id
	await _observe_goal(120)
	if not _check(first_id in session.story.state.get("completed",[]),"assistant naturally completed first objective",observations): await _finish(); return
	_check(not session.flight_assist.enabled,"single-objective scope stops after completion")
	var initial: Vector3=session.players[1].global_position
	var start: Dictionary=session.start_flight_assist("chapter")
	_check(start.get("ok",false),"can continue current chapter")
	for frame in range(60): await physics_frame
	session._ui_action("menu",{})
	await _settle()
	for frame in range(20): await physics_frame
	_check(session.flight_assist.enabled and session.flight_assist.state=="suspended","menu suspends assistant without dropping requested scope",session.flight_assist.status())
	front.resume_flight()
	await _settle()
	for frame in range(15): await physics_frame
	Input.action_press("flight_left")
	for frame in range(3): await physics_frame
	Input.action_release("flight_left")
	_check(not session.flight_assist.enabled,"real manual axis immediately takes control")
	start=session.start_flight_assist("chapter")
	_check(start.get("ok",false),"assistant can restart after manual takeover")
	deadline=Time.get_ticks_msec()+300000
	while session.flight_assist.enabled and session.story.state.get("completed",[]).size()<4 and Time.get_ticks_msec()<deadline:
		await create_timer(.5).timeout
		_observe()
	_check(session.story.state.get("completed",[]).size()>=4,"actual channel ability, rescue flight and evacuation complete",observations)
	_check(initial.distance_to(session.players[1].global_position)>2,"assistant moved real aircraft through original physics")
	await _capture("assist_rescue")
	session.flight_assist.stop("检查结束，保留实际取得的进度")
	_check(not session.flight_assist.enabled and not session.interface.assist_status.visible,"explicit stop clears HUD assistance state")
	var completed: Array=session.story.state.get("completed",[]).duplicate()
	session._return_to_hangar()
	deadline=Time.get_ticks_msec()+15000
	while session.active and Time.get_ticks_msec()<deadline: await process_frame
	_check(not session.active,"ordinary return saves and exits flight")
	var reader=load("res://scripts/v3/core/twin_world_store.gd").new(session.store.root_path)
	var opened: Dictionary=reader.load_profile()
	_check(opened.get("ok",false) and reader.snapshot().world.get("actions",{}).get("opening",{}).get("completed",[])==completed,"independent reader sees exact naturally earned progress")
	await _finish()

func _observe_goal(seconds: int) -> void:
	var deadline:=Time.get_ticks_msec()+seconds*1000
	while session.flight_assist.enabled and Time.get_ticks_msec()<deadline:
		await create_timer(.5).timeout
		_observe()

func _observe() -> void:
	var value: Dictionary=session.flight_assist.status()
	var pilot=session.flight_assist._pilot
	var probe: Dictionary=pilot.last_probe if pilot!=null else {}
	var key:=str([value.objective_id,value.state,value.step,value.message,session.flight_assist._step_data.get("point_index",-1),probe.get("reason",""),probe.get("collider",""),int(Time.get_ticks_msec()/15000)])
	if observations.is_empty() or str(observations.back().key)!=key:
		var boss: Dictionary=session.flight_assist._combat.boss_state() if session.flight_assist._combat!=null else {}
		observations.append({"key":key,"state":value,"position":str(session.players[1].global_position),"target":str(session.flight_assist._nav_target),"health":session.players[1].health,"boss":{ "core":boss.get("core_hp_milli",boss.get("core_health",-1)),"parts":boss.get("parts",{}),"environment":boss.get("environment",{}) },"probe":str(probe),"completed":session.story.state.get("completed",[]).size()})
		print("ASSIST_STATE ",JSON.stringify(observations.back()))
