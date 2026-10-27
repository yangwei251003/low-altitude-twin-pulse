extends "res://scripts_tools/v3/capture_clinic_integrated.gd"
## Production Trial Assembly, Session abilities, nearby G and existing readout.
## Source/debug --script only; no temporary module, material or UI is installed.
## --qa-profile=qa_visual_clinic_trial_integrated_<unique>
## --capture-output=res://artifacts/v3/art/trial-integrated-<unique>
## Historical27 and stationary pilot placements are explicit QA fixtures.
const TrialSession = preload("res://scripts/v3/gameplay/twin_trial_session.gd")
const Station = TrialSession.Assembly.Station
const Link = TrialSession.Assembly.Link
const Runtime = TrialSession.Runtime
const CAPTURE_PATH := "res://scripts_tools/v3/capture_trial_integrated.gd"
const LINK_APPROACH := Vector3(16,1.3,-5.3)
const POWER_APPROACH := Vector3(18,2.5,-0.5)
const GAUGE_A_APPROACH := Vector3(16.85,2,-0.6)
const GAUGE_B_APPROACH := Vector3(19.15,2,-0.6)
const RETURN_APPROACH := Vector3(18,1.35,-0.5)
var station
var link
var baseline_story: Dictionary = {}
var baseline_personal: Dictionary = {}
var first_history: Dictionary = {}
var gauge_events: Array = []

func _arguments_valid() -> bool:
	var profile_count := 0
	var output_count := 0
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--qa-profile="):
			profile_count+=1
			profile=arg.trim_prefix("--qa-profile=")
		elif arg.begins_with("--capture-output="):
			output_count+=1
			output=arg.trim_prefix("--capture-output=")
		else: return false
	var regex := RegEx.new()
	if regex.compile("^qa_visual_clinic_trial_integrated_[A-Za-z0-9_-]+$")!=OK: return false
	if profile_count!=1 or output_count!=1 or regex.search(profile)==null: return false
	output=ProjectSettings.globalize_path(output).replace("\\","/").simplify_path()
	var allowed := ProjectSettings.globalize_path("res://artifacts/v3/art").replace("\\","/").simplify_path()
	if not output.is_absolute_path() or output.get_base_dir().to_lower()!=allowed.to_lower(): return false
	if not output.get_file().begins_with("trial-integrated-") or output.get_file()=="trial-integrated-": return false
	if DirAccess.dir_exists_absolute(output) or FileAccess.file_exists(output): return false
	if DirAccess.dir_exists_absolute("user://profiles_v3/"+profile) or FileAccess.file_exists("user://profiles_v3/"+profile): return false
	return OS.is_debug_build() and DisplayServer.get_name()!="headless" and RenderingServer.get_current_rendering_method()=="gl_compatibility" and RenderingServer.is_render_loop_enabled() and Engine.physics_ticks_per_second==60

func _run() -> void:
	started_usec=Time.get_ticks_usec()
	if not _arguments_valid():
		push_error("TRIAL_INTEGRATED_CAPTURE requires fresh isolated paths and source debug Compatibility renderer")
		OS.remove_logger(capture_logger)
		quit(2)
		return
	if DirAccess.make_dir_recursive_absolute(output)!=OK:
		push_error("TRIAL_INTEGRATED_CAPTURE cannot create fresh output")
		OS.remove_logger(capture_logger)
		quit(2)
		return
	create_timer(180.0,true,false,true).timeout.connect(_timeout)
	root.size=SIZE
	# Resolve literal resource references recursively instead of hashing every
	# unrelated experimental file in scripts/data. Runtime-discovered material
	# textures and import caches are added below before their first screenshot.
	_add_dependency_tree(CAPTURE_PATH)
	_add_dependency_tree("res://project.godot")
	_add_import_hashes()
	hashes_before=_input_hashes()
	if not _check(_hashes_complete(),"all declared capture/production resource inputs exist before MAIN construction"):
		await _finish()
		return
	session=MAIN.instantiate()
	if not _check(session.has_method("start_flight") and session.has_method("_facilities_ready"),"MAIN has its actual complete Session script"):
		await _finish()
		return
	root.add_child(session)
	if not _check(session.profile_ready and session.store.root_path=="user://profiles_v3/"+profile and session.start_flight("solo"),"fresh isolated production MAIN starts I1"):
		await _finish()
		return
	_hold()
	if not _seed_history():
		await _finish()
		return
	_hold()
	inventories.I1=_scene_inventory(session.world)
	_extend_scene_inputs(inventories.I1)
	session._ui_action("travel_to",{"region_id":"I2"})
	_hold()
	await physics_frame
	await physics_frame
	if not _check(session.region_id=="I2" and session._facilities_ready() and session.world.build_errors.is_empty()
		and session.world.trial==session.trial.module,"production travel adopts its one real Trial Assembly with all facility streams ready"):
		await _finish()
		return
	body=session.players[1]
	station=session.trial.module.station
	link=session.trial.module.link
	session.trial.gauge_read.connect(_record_gauge)
	baseline_story=session.story.state.duplicate(true)
	baseline_personal=session.store.snapshot().personal.duplicate(true)
	inventories.I2=_scene_inventory(session.world)
	_extend_scene_inputs(inventories.I2)
	if not _check(_hashes_complete() and session.entities.has(Link.HANDLE) and session.entities.has(Station.RELAY)
		and session.entities.has(Station.CONTROLLER) and session.store.snapshot().world.environment.has("I2_trial_flow")
		and is_instance_valid(session.trial_gauge),"registered targets, saved envelope and the existing production readout are present"):
		await _finish()
		return
	if not _check(_volumes()==[200000,0,0] and link.status().phase=="normal" and session.trial.observed_gauges()=={"A":{},"B":{}},"new production Trial starts NORMAL with 200 L source and no fabricated readings"):
		await _finish()
		return
	await _place(POWER_APPROACH,"clear front of production Trial; fixed composition, not a flown route")
	await _capture("01-I2-trial-default-26m","Production I2 Trial, existing HUD and default 26m orthographic camera. Actual NORMAL interlock and empty receivers; no temporary module.")
	if finishing: return
	await _capture("02-I2-trial-empty-zoom3","Same production pose, exactly three ordinary wheel zoom steps. Receiver volumes and physical float sizes are not exaggerated.",3)
	if finishing: return
	await _place(LINK_APPROACH,"production isolation handle approach; full-envelope clearance checked")
	if not await _ability_key(KEY_2,Link.HANDLE,"push isolation handle from NORMAL toward TRIAL"):
		await _finish()
		return
	if not await _advance_trial("settled physical TRIAL interlock",4.0,"trial"):
		await _finish()
		return
	await _place(POWER_APPROACH,"production charge/takeover approach outside the actual bench")
	if not await _ability_key(KEY_6,Station.RELAY,"charge actual trial relay") or not await _ability_key(KEY_0,Station.CONTROLLER,"take over actual pulse controller"):
		await _finish()
		return
	if not await _advance_trial("two complete 20 L samples and neutral selector",9.0,"samples"):
		await _finish()
		return
	if not await _read_window(GAUGE_A_APPROACH,TrialSession.GAUGE_A,Runtime.RECEIVER_A,20000):
		await _finish()
		return
	await _capture("03-I2-trial-receiver-A-20L","Real Session pulse produced two 20 L samples. Nearby G read actual A window and committed its first observation; production UI shows that reading, not live telemetry.",3)
	if finishing: return
	if not await _read_window(GAUGE_B_APPROACH,TrialSession.GAUGE_B,Runtime.RECEIVER_B,20000):
		await _finish()
		return
	await _capture("04-I2-trial-receiver-B-20L","Nearby G read actual B window. B is current, A explicitly last read; each true liquid rise is 10cm. No wrong-route answer or objective is manufactured.",3)
	if finishing: return
	first_history=session.trial.observed_gauges()
	if not _check(int(first_history.A.get("volume_ml",-1))==20000 and int(first_history.B.get("volume_ml",-1))==20000,"both historical 20 L readings were committed by real G"):
		await _finish()
		return
	await _place(RETURN_APPROACH,"production return switch approach with actual first-hit validation")
	if not _check(session.story.nearest(body.global_position)==TrialSession.RETURN_SWITCH,"nearby dispatcher selects the actual return switch"):
		await _finish()
		return
	_g("request actual return pump")
	if not _check(station.snapshot().return_requested,"actual G requests return without setting water or selector state") or not await _advance_trial("full recovery to source and closed return request",6.0,"returned"):
		await _finish()
		return
	if not await _read_window(GAUGE_A_APPROACH,TrialSession.GAUGE_A,Runtime.RECEIVER_A,0) or not await _read_window(GAUGE_B_APPROACH,TrialSession.GAUGE_B,Runtime.RECEIVER_B,0):
		await _finish()
		return
	_check(session.trial.observed_gauges()==first_history,"empty current windows preserve the two original committed sample observations")
	_check(session._save_environment(),"normal production environment save commits the recovered current water state")
	var disk=Store.new(session.store.root_path)
	_check(disk.load_profile().ok and session.store.matches_persisted_value(session.trial.persistent_state(),disk.snapshot().world.environment.I2_trial_flow),"independent Store rereads current empty receivers and retained first observations")
	await _capture("05-I2-trial-returned-0L","Actual G-triggered pump returned all 40 L to source. G reread both empty windows: current UI is 0 L, while saved first 20 L observations remain intact. Production camera with three ordinary zoom steps.",3)
	if finishing: return
	_check(session.story.state==baseline_story and session.store.snapshot().personal==baseline_personal and session.story.state.completed.size()==27,"trial mechanics and saved readings award no undefined objective, discovery or personal reward")
	_check(session.network.mode=="solo" and session.qa_mode.is_empty() and not session.boss_active and int(session.stats.abilities)==3,"exactly three real accepted Session abilities drive this solo diagnostic")
	await _finish()

func _ability_key(number: Key, target: String, purpose: String) -> bool:
	if float(session.cooldowns.get(1,0.0))>0.0 and not await _advance_trial("production ability cooldown",2.0,"cooldown"): return false
	if not _select(number,target): return false
	var before: Dictionary=_state()
	var accepted: int=int(session.stats.abilities)
	var rejected: int=int(session.stats.rejected_abilities)
	_key(KEY_F)
	actions.append({"input":"number/Tab/F","number_key":int(number),"target":target,"purpose":purpose,"before":before,"after":_state()})
	return _check(int(session.stats.abilities)==accepted+1 and int(session.stats.rejected_abilities)==rejected,"actual selected F accepted: "+purpose)

func _advance_trial(label: String, seconds: float, condition: String) -> bool:
	var begin:=Time.get_ticks_usec()
	var first_tick:=simulated_ticks
	var before: Dictionary=_state()
	var reached:=false
	paused=false
	session.world.set_effects_paused(false)
	for unused in range(int(ceil(seconds/DT))):
		await physics_frame
		if finishing: return false
		session._physics_process(DT)
		simulated_ticks+=1
		var healthy:=true
		for name in ["clinic","distribution","trial"]:
			var adapter=session.get(name)
			if not str(adapter.error).is_empty():
				_check(false,"production "+name+" update rejected: "+str(adapter.error))
				healthy=false
		if not healthy or session.simulation_paused: break
		if condition=="trial": reached=link.status().phase=="trial" and station.connection_status().trial_ready
		elif condition=="samples": reached=_volumes()==[160000,20000,20000] and station.status().both_samples_recorded and station.status().selector_position==0.0
		elif condition=="returned": reached=_volumes()==[200000,0,0] and not station.snapshot().return_requested
		elif condition=="cooldown": reached=float(session.cooldowns.get(1,0.0))<=0.0
		else:
			_check(false,"unknown Trial wait condition: "+condition)
			break
		if reached: break
	_hold()
	live_windows.append({"name":label,"wall_seconds":float(Time.get_ticks_usec()-begin)/1000000.0,"fixed_steps":simulated_ticks-first_tick,
		"simulated_seconds":float(simulated_ticks-first_tick)*DT,"before":before,"after":_state(),"reached":reached})
	return _check(reached,"bounded real Session physics reaches "+label)

func _read_window(at: Vector3, marker: String, receiver: String, expected_ml: int) -> bool:
	await _place(at,"production "+receiver+" reading approach; not a flown route")
	if finishing: return false
	if not _check(session.story.nearest(body.global_position)==marker,"nearest G target is "+marker): return false
	var count:=gauge_events.size()
	_g("read actual "+receiver+" window")
	var ui: Dictionary=session.trial_gauge.readings_snapshot()
	var observed: Dictionary=gauge_events.back() if gauge_events.size()>count else {}
	return _check(gauge_events.size()==count+1 and observed.get("receiver_id")==receiver and int(observed.get("volume_ml",-1))==expected_ml
		and observed.get("center_hit",false) and int(observed.get("hits",0))>=3 and ui.current_receiver==receiver
		and int(ui.readings.get(receiver,{}).get("volume_ml",-1))==expected_ml,"real G first-hit observation updates production readout to "+str(expected_ml)+" ml for "+receiver)

func _record_gauge(peer_id: int, observation: Dictionary) -> void:
	var recorded:=observation.duplicate(true)
	recorded.peer_id=peer_id
	if recorded.get("float_world_position") is Vector3: recorded.float_world_position=_vec(recorded.float_world_position)
	gauge_events.append(recorded)

func _volumes() -> Array:
	var result: Array=[]
	for id in [Runtime.SOURCE,Runtime.RECEIVER_A,Runtime.RECEIVER_B]: result.append(int(station.get_water_node(id).volume_ml))
	return result

func _physics_record() -> Dictionary:
	var aligned:=true
	var poses: Array=[]
	for moving in station.selector_bodies.values()+station.float_bodies.values()+station.valve_bodies.values()+link.moving_bodies.values():
		var actual: Transform3D=PhysicsServer3D.body_get_state(moving.get_rid(),PhysicsServer3D.BODY_STATE_TRANSFORM)
		var matches: bool=actual.is_equal_approx(moving.global_transform)
		aligned=aligned and matches
		poses.append({"node":str(moving.name),"scene_position":_vec(moving.global_position),"physics_position":_vec(actual.origin),"matches":matches})
	return {"all_physics_poses_match":aligned,"moving_bodies":poses,"volumes_ml":_volumes(),"connection":station.connection_status()}

func _state() -> Dictionary:
	var result: Dictionary=super._state()
	if session.distribution.ready: result.distribution=session.distribution.persistent_state()
	if session.trial.ready:
		result.trial=session.trial.persistent_state()
		if is_instance_valid(station) and is_instance_valid(link): result.trial_physics=_physics_record()
	if is_instance_valid(session.trial_gauge): result.trial_gauge_readout=session.trial_gauge.readings_snapshot()
	return result

func _ui_record() -> Dictionary:
	var result: Dictionary=super._ui_record()
	var gauge=session.trial_gauge
	var rectangle: Rect2=gauge.get_global_rect()
	result.trial_gauge={"visible":gauge.is_visible_in_tree(),"rect":[rectangle.position.x,rectangle.position.y,rectangle.size.x,rectangle.size.y],"rows":{}}
	for id in gauge.headings: result.trial_gauge.rows[id]={"heading":gauge.headings[id].text,"value":gauge.values[id].text}
	if not gauge.readings_snapshot().readings.is_empty():
		_check(gauge.is_visible_in_tree() and not gauge.layout_blocked and Rect2(Vector2.ZERO,Vector2(SIZE)).encloses(rectangle),"production observed-reading panel stays visible inside 720p")
	_check(bool(_physics_record().all_physics_poses_match),"all actual trial moving colliders match scene poses in captured frame")
	return result

func _add_dependency_tree(path: String) -> void:
	if path in input_paths: return
	input_paths.append(path)
	if not FileAccess.file_exists(path): return
	if path.get_extension() not in ["gd","json","tscn","tres","gdshader","gdshaderinc","godot"]: return
	var regex:=RegEx.new()
	regex.compile("res://[^\\\"'\\s]+")
	for matched in regex.search_all(FileAccess.get_file_as_string(path)):
		var dependency: String=matched.get_string().get_slice("::",0)
		if FileAccess.file_exists(dependency): _add_dependency_tree(dependency)

func _extend_scene_inputs(inventory: Dictionary) -> void:
	for path in inventory.imported_sources+inventory.material_sources: _add_dependency_tree(path)
	_add_import_hashes()
	for path in input_paths:
		if not hashes_before.has(path): hashes_before[path]=FileAccess.get_sha256(path) if FileAccess.file_exists(path) else "MISSING"

func _hashes_complete() -> bool:
	if hashes_before.is_empty(): return false
	for digest in hashes_before.values():
		if str(digest).length()!=64: return false
	return true

func _finish() -> void:
	if finishing: return
	finishing=true
	var usable: bool=is_instance_valid(session) and session.has_method("start_flight")
	var final_state: Dictionary=_state() if usable and session.players.has(1) else {}
	if is_instance_valid(session):
		if usable:
			session.active=false
			if is_instance_valid(session.network): session.network.close()
		session.free()
	await process_frame
	await process_frame
	var after:=_input_hashes()
	_check(_hashes_complete() and hashes_before==after,"all captured production/helper/import input bytes stayed unchanged")
	_check(shots.size()==5,"all five requested production Trial views saved")
	var logged: Dictionary=capture_logger.snapshot()
	_check(int(logged.error_count)==0,"no engine/script/shader errors including cleanup")
	var passed:=true
	for item in checks: passed=passed and bool(item.passed)
	var report: Dictionary={"passed":passed,"status":"production_trial_scripted_visual_regression_not_art_or_human_acceptance","profile":profile,"output":output,
		"checks":checks,"shots":shots,"actions":actions,"fixture":fixture,"QA_placements":placements,"gauge_events":gauge_events,
		"live_windows":live_windows,"nominal_fixed_step_seconds":DT,"simulated_ticks":simulated_ticks,"final_state":final_state,
		"first_observation_history":first_history,"production_scene_inventory":inventories,"input_sha256_before":hashes_before,"input_sha256_after":after,
		"engine_log":logged,"engine":Engine.get_version_info(),"renderer":RenderingServer.get_current_rendering_method(),"GPU":RenderingServer.get_video_adapter_name(),
		"viewport":[root.size.x,root.size.y],"wall_seconds":float(Time.get_ticks_usec()-started_usec)/1000000.0,
		"limits":["Historical27 is a trusted Director/Store fixture, not a seven-action playthrough. Starting pilot placements are full-envelope-checked QA compositions, not flown routes.",
			"Only the production world-owned Trial Assembly and existing readout are used. No temporary model, material, UI or fabricated water/axis state is installed.",
			"Real number/Tab/F and nearby G dispatch use solo Session authority; this is not ENet, a two-PC test or human understanding evidence.",
			"One 1/60-second production fixed update per awaited physics frame. Frozen screenshots settle production presentation only; this is not a performance or duration benchmark.",
			"Source/receivers conserve 200 L. Two 20 L samples mean true 10cm liquid rises; close views use exactly three normal zoom steps, without scaling liquid or collision.",
			"UI readings update only after successful host window observations. First complete sample observations persist after pumping water back, without any newly defined objective or reward.",
			"Source-only debug entry; PCK, controller comfort, art acceptance and whole-game completion are outside this capture. Cached AGL is recorded, not corrected or verified.",
			"Resource hashes cover literal dependency closure plus actual scene-discovered sources/materials/import caches, not unrelated unreferenced bridge or ground candidates. Parser errors before initialization require the runner's exit/report watchdog."]}
	var path:=output.path_join("state_checks.json")
	var file: FileAccess=FileAccess.open(path,FileAccess.WRITE) if not FileAccess.file_exists(path) else null
	var wrote:=file!=null
	if file!=null:
		file.store_string(JSON.stringify(report,"\t",true,true))
		file.flush()
		wrote=file.get_error()==OK
		file.close()
	if not wrote: push_error("TRIAL_INTEGRATED_CAPTURE cannot write fresh state_checks.json")
	var final_log: Dictionary=capture_logger.snapshot()
	var success: bool=passed and wrote and int(final_log.error_count)==0
	print("TRIAL_INTEGRATED_CAPTURE ",JSON.stringify({"passed":success,"shots":shots.size(),"checks":checks.size(),"errors":final_log.error_count,"output":output}))
	OS.remove_logger(capture_logger)
	quit(0 if success else 1)
