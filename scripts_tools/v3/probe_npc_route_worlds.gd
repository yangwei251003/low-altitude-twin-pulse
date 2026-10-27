extends "res://tests_v3/test_boss_hit_amount.gd"
## Reuse the tested native logger/teardown; no Boss is started in this probe.
var route_helper: Script
var route_observations: Array = []

func _scope() -> String:
	return "Source next native ordinary MAIN factories, one default-state World at a time. Explicit QA direct region-load fixture bypasses earned travel access only; no graph, actor, Boss, machinery or original-save injection. Read-only fixed sphere/box route-envelope queries, not precise model, all-turn or all-mechanism-state clearance acceptance. ok means native query valid, not route clear. Source-only headless, no OS input, graphics, human play, LAN or natural campaign claim. Inherited terminal QA teardown is not normal SaveQuit evidence."

func _run() -> void:
	var helper_path := "res://scripts_tools/v3/probe_npc_routes.gd"
	var wanted := PackedStringArray(["I1","F1","I2","F2","I3","F3","I4","F4"])
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--qa-profile="): profile = arg.trim_prefix("--qa-profile=")
		if arg.begins_with("--output="): output = arg.trim_prefix("--output=")
		if arg.begins_with("--route-helper="): helper_path = arg.trim_prefix("--route-helper=")
		if arg.begins_with("--regions="): wanted = arg.trim_prefix("--regions=").split(",")
	var managed := OS.get_environment("LOW_ALTITUDE_DEV_HOME").replace("\\","/").trim_suffix("/")
	output = output.replace("\\","/")
	helper_path = helper_path.replace("\\","/")
	if DisplayServer.get_name() != "headless" or managed.is_empty() or not profile.begins_with("qa_npc_route_") or profile != profile.validate_filename() or DirAccess.dir_exists_absolute("user://profiles_v3/"+profile) or not output.begins_with(managed+"/evidence/npc-routes-") or ".." in output or DirAccess.dir_exists_absolute(output) or helper_path != "res://scripts_tools/v3/probe_npc_routes.gd":
		quit(2)
		return
	if DirAccess.make_dir_recursive_absolute(output) != OK: quit(2); return
	if wanted.is_empty() or wanted.size()>8:
		quit(2)
		return
	for id: String in wanted:
		if id not in ["I1","F1","I2","F2","I3","F3","I4","F4"] or wanted.count(id) != 1:
			quit(2)
			return
	boss = "none"
	region = "I1"
	began = Time.get_ticks_msec()
	create_timer(160.0).timeout.connect(func():
		if not finished:
			_check(false,"160 second native World observation bound",_diagnostics())
			_end())
	route_helper = load(helper_path)
	if not _check(route_helper != null,"reviewed read-only route helper loaded"): _end(); return
	session = MAIN.instantiate()
	root.add_child(session)
	if not _check(session.profile_ready and session.start_flight("solo"),"fresh original MAIN/Store starts I1"): _end(); return
	session.inputs.test_enabled = true
	session.inputs.test_frame = {"axes":{},"held":["brake"],"edges":[]}
	for id: String in wanted:
		region = id
		if session.region_id != id and not _check(session._load_region(id),"original complete World factory loads "+id,_diagnostics()): _end(); return
		for unused in 3:
			if not await _frame(): return
		var wait_began := Time.get_ticks_msec()
		# Original Canal boot physically seats/lifts/transports its carrier. Its
		# existing ordinary continuation allows 120s, not a three-frame shortcut.
		var ready_limit := 120000 if id == "I2" else 5000
		while not _region_ready(id) and Time.get_ticks_msec()-wait_began<ready_limit:
			if not await _frame(): return
		var readiness := {"wait_ms":Time.get_ticks_msec()-wait_began,"facilities":session._facilities_ready(),"story":session.story.ready,"ecology":session.ecology.ready,"canal":session.canal.status() if session.canal!=null else {}}
		if not _check(_region_ready(id),"all current-region production participants ready: "+id,readiness): _end(); return
		var observed: Dictionary = route_helper.run(session.world,session.ecology.simulation)
		observed["readiness_wait_ms"] = readiness.wait_ms
		route_observations.append(observed)
		if not _check(observed.get("ok",false) and observed.get("simulation_unchanged",false),"native geometry queries are valid and read-only: "+id, {"code":observed.get("code",""),"rows":observed.get("rows",[]).size(),"clear":observed.get("clear")}): _end(); return
	_end()

func _region_ready(id: String) -> bool:
	return session._facilities_ready() and session.story.ready and session.ecology.ready and session.world.build_errors.is_empty() and (id!="I2" or session.canal!=null and session.canal.status().ready)

func _end() -> void:
	if finished: return
	fixtures.append({"kind":"direct_complete_factory_region_loading_not_earned_story_travel","route_observations":route_observations})
	_finish()
