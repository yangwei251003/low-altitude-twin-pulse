extends "res://scripts_tools/v3/capture_clinic_integrated.gd"
## Actual production MAIN/I2 camera with a TEMPORARY physically connected bench.
## --qa-profile=qa_visual_clinic_trial_<unique>
## --capture-output=res://artifacts/v3/art/trial-station-candidate-<unique>
## Source/editor --script only. This is not a packaged entry or Session feature.
## Historical27 and trusted actuator inputs are explicit QA fixtures. No new
## action, Session target registration, reward or playthrough claim.
const Link = preload("res://scripts/v3/world/twin_trial_isolation_link.gd")
const Station = preload("res://scripts/v3/world/twin_trial_flow_station.gd")
const TrialRuntime = preload("res://scripts/v3/environment/twin_trial_flow_runtime.gd")
const Cabinet = preload("res://scripts/v3/world/twin_distribution_cabinet.gd")
const Presentation = preload("res://scripts/v3/world/twin_trial_flow_presentation.gd")
const GaugeReadout = preload("res://scripts/v3/ui/twin_trial_gauge_readout.gd")
const SELF_PATH := "res://scripts_tools/v3/capture_trial_station_candidate.gd"
var isolation: Node3D
var trial: Node3D
var trial_entities: Dictionary = {}
var production_saved_before: Dictionary = {}
var candidate_ticks := 0
var cabinet_ticks := 0
var gauge_readout: PanelContainer

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
	if regex.compile("^qa_visual_clinic_trial_[A-Za-z0-9_-]+$")!=OK: return false
	if profile_count!=1 or output_count!=1 or regex.search(profile)==null: return false
	output=ProjectSettings.globalize_path(output).replace("\\","/").simplify_path()
	var allowed := ProjectSettings.globalize_path("res://artifacts/v3/art").replace("\\","/").simplify_path()
	if not output.is_absolute_path() or output.get_base_dir().to_lower()!=allowed.to_lower(): return false
	if not output.get_file().begins_with("trial-station-candidate-") or output.get_file()=="trial-station-candidate-": return false
	if DirAccess.dir_exists_absolute(output) or FileAccess.file_exists(output): return false
	if DirAccess.dir_exists_absolute("user://profiles_v3/"+profile) or FileAccess.file_exists("user://profiles_v3/"+profile): return false
	return OS.is_debug_build() and DisplayServer.get_name()!="headless" and RenderingServer.get_current_rendering_method()=="gl_compatibility" and RenderingServer.is_render_loop_enabled() and Engine.physics_ticks_per_second==60

func _run() -> void:
	started_usec=Time.get_ticks_usec()
	if not _arguments_valid():
		push_error("TRIAL_CAPTURE requires fresh qa_visual_clinic_trial_ profile and trial-station-candidate- output, source debug Compatibility renderer")
		OS.remove_logger(capture_logger)
		quit(2)
		return
	if DirAccess.make_dir_recursive_absolute(output)!=OK:
		push_error("TRIAL_CAPTURE cannot create fresh output directory")
		OS.remove_logger(capture_logger)
		quit(2)
		return
	create_timer(180.0,true,false,true).timeout.connect(_timeout)
	root.size=SIZE
	input_paths.assign(INPUTS)
	input_paths.append(SELF_PATH)
	input_paths.append("res://tests_v3/test_trial_flow_station.gd")
	input_paths.append("res://tests_v3/test_trial_flow_runtime.gd")
	for directory in ["res://scripts/v3","res://data/v3","res://scenes/v3"]: _collect_inputs(directory)
	# Independent bridge candidate is not loaded by this captured world.
	for inactive in ["res://scripts/v3/world/twin_shared_access_bridge.gd","res://data/v3/terrain/i2_shared_access_layout.json","res://scripts/v3/world/twin_trial_assembly.gd","res://scripts/v3/gameplay/twin_trial_session.gd"]:
		input_paths.erase(inactive)
	_add_import_hashes()
	hashes_before=_input_hashes()
	if not _check(_hashes_complete(),"source, candidate definition, tests and capture utilities exist before MAIN construction"):
		await _finish()
		return
	session=MAIN.instantiate()
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
	if not _check(_hashes_complete(),"I1 historical fixture includes actual material/import cache inputs"):
		await _finish()
		return
	session._ui_action("travel_to",{"region_id":"I2"})
	_hold()
	await physics_frame
	await physics_frame
	if not _check(session.region_id=="I2" and session._facilities_ready() and session.world.build_errors.is_empty()
		and session.world.distribution==session.distribution.module and session.world.clinic==session.clinic.module,"real travel adopts complete production I2 facilities"):
		await _finish()
		return
	body=session.players[1]
	inventories.I2=_scene_inventory(session.world)
	_extend_scene_inputs(inventories.I2)
	if not _check(_hashes_complete() and inventories.I2.imported_sources.size()>0,"production I2 imported models, PBR and cache files are included in input hashes"):
		await _finish()
		return
	production_saved_before=session.store.snapshot()
	trial=Station.new()
	var loaded: Dictionary = trial.load_layout({},true)
	if not _check(loaded.ok,"independent candidate configures from actual station/layout/runtime files"):
		trial.free()
		trial=null
		await _finish()
		return
	trial.name="TemporaryTrialFlowDiagnostic"
	session.world.add_child(trial)
	isolation=Link.new()
	var link_loaded: Dictionary=isolation.configure()
	if not _check(link_loaded.ok,"actual isolation Link configures beside production five-piece cabinet floor"):
		isolation.free()
		isolation=null
		await _finish()
		return
	session.world.add_child(isolation)
	if not _check(trial.attach_link(isolation).ok,"bench binds actual same-world Link"):
		await _finish()
		return
	var presentation := Presentation.new()
	trial.add_child(presentation)
	var signs: Dictionary = presentation.setup(trial,session.camera)
	if not _check(signs.ok,"presentation adds depth-tested receiver identities without changing station state"):
		await _finish()
		return
	gauge_readout=GaugeReadout.new()
	session.interface.hud.add_child(gauge_readout)
	gauge_readout.setup_layout(session.interface.bottom_panel,
		[session.interface.top_panel,session.interface.task_panel,session.interface.radio],session.interface.pilot_marker)
	for entity in trial.target_definitions(): trial_entities[entity.id]=entity
	await physics_frame
	await physics_frame
	inventories.candidate=_scene_inventory(trial)
	inventories.candidate.stage="temporary connected low-trial graybox, not registered Session gameplay"
	inventories.isolation=_scene_inventory(isolation)
	_check(trial.global_position==Vector3(18,0,-3) and trial.get_meta("stage")=="connected_low_trial_candidate"
		and trial.connection_status().ok and not trial.connection_status().trial_ready,"candidate has real pipe binding but starts closed in NORMAL")
	_check(not session.entities.has(Station.SELECTOR) and not session.entities.has(Station.RELAY) and not session.entities.has(Station.CONTROLLER)
		and not session.store.snapshot().world.environment.has("I2_trial_flow"),"candidate is not registered in production abilities, save or objectives")
	if not _check(_trial_volumes()==[200000,0,0],"actual temporary bench begins with empty receivers and original 200 L"):
		await _finish()
		return
	await _place(Vector3(18,2,-.6),"clear front of temporary connected trial bench")
	await _capture("01-I2-trial-default-26m","Actual production I2, HUD, light and default fixed 26m camera. Temporary bench and real low service pipes connected through the cabinet holes; NORMAL leaves trial closed. No new registered action.")
	if finishing: return
	await _capture("02-I2-trial-empty-zoom3","Same actual pose, three ordinary wheel zoom steps. Both receivers are empty; liquids and floats are unscaled physical quantities.",3)
	if finishing: return
	if not await _pulse_candidate():
		await _finish()
		return
	await _place(Vector3(16.85,1.55,-.6),"clear exterior position facing actual receiver A gauge")
	var read_a: Dictionary = trial.observe_gauge(1,body,TrialRuntime.RECEIVER_A)
	physical_probes.receiver_a=_json_observation(read_a)
	_check(read_a.ok and int(read_a.get("volume_ml",-1))==20000 and bool(read_a.get("cabinet_connected",false)),"actual first-hit receiver A window reads local 20 L only")
	_check(gauge_readout.apply_observation(read_a),"local readout accepts only the successful actual receiver A observation")
	await _capture("03-I2-trial-receiver-A-20L","Actual receiver A holds 20 L (10cm liquid rise), obtained via the opposite physical selector route. Three normal zoom steps; gauge reading is local after real through-cabinet transfer.",3)
	if finishing: return
	await _place(Vector3(19.15,1.55,-.6),"clear exterior position facing actual receiver B gauge")
	gauge_readout.mark_previous()
	var read_b: Dictionary = trial.observe_gauge(1,body,TrialRuntime.RECEIVER_B)
	physical_probes.receiver_b=_json_observation(read_b)
	_check(read_b.ok and int(read_b.get("volume_ml",-1))==20000 and bool(read_b.get("cabinet_connected",false)),"actual first-hit receiver B window reads local 20 L only")
	_check(gauge_readout.apply_observation(read_b),"local readout shows B current and A explicitly previous without decoding a route answer")
	await _capture("04-I2-trial-receiver-B-20L","Actual receiver B has the other 20 L sample and true float position. Depth-tested A/B identities and a panel of only actual observed readings; three ordinary zoom steps.",3)
	if finishing: return
	gauge_readout.clear_readings()
	if not await _open_existing_cabinet():
		await _finish()
		return
	await _place(Vector3(18,2.7,-10.8),"existing low cabinet passage behind its physically raised door; QA placement, not flown traversal")
	var back: Dictionary = session.distribution.module.observe_back(1,body)
	physical_probes.existing_cabinet_observation=back
	_check(back.ok and back.get("method","")=="service_lock","candidate geometry preserves actual low-passage backplate first hits")
	await _capture("05-I2-existing-low-passage","Existing production low passage/default 26m camera after explicitly scripted physical actuator inputs. No G, early-knowledge commit or new trial fact was sent.")
	if finishing: return
	_check(_same(production_saved_before,session.store.snapshot()) and session.story.state.completed.size()==27,
		"temporary candidate and physical-only cabinet fixture do not change production saves, objectives or discoveries")
	_check(session.network.mode=="solo" and session.qa_mode.is_empty() and not session.boss_active and int(session.stats.abilities)==0,
		"no Session spell/RPC/autonomous QA/Boss is misrepresented as candidate interaction")
	await _finish()

func _pulse_candidate() -> bool:
	# Deliberately trusted physical boundary, NOT ability input or remote RPC.
	# These entities are private to the diagnostic and never enter Session.
	var link_before: Dictionary=isolation.snapshot()
	var trial_mode: Dictionary=link_before.duplicate(true)
	trial_mode.axis.position_m=Link.TRAVEL
	trial_mode.axis.velocity_mps=0.0
	if not _check(isolation.apply_snapshot(trial_mode).ok,"explicit saved TRIAL fixture opens actual low path and closes high shutters"):
		return false
	await physics_frame
	await physics_frame
	if not _check(trial.connection_status().trial_ready,"real link pose is stable and ready before candidate transfer"):
		return false
	actions.append({"kind":"explicit_link_saved_pose_fixture_not_player_input","before":link_before,"after":isolation.snapshot()})
	var before: Dictionary = trial.snapshot()
	trial_entities[Station.RELAY].powered=true
	trial_entities[Station.CONTROLLER].controlled=true
	trial_entities[Station.CONTROLLER].owner="1"
	trial_entities[Station.CONTROLLER].takeover_remaining=8.0
	trial.synchronize_impulse_roster(session.players)
	var elapsed := 0.0
	var clear := true
	while elapsed<8.0:
		await physics_frame
		if finishing: return false
		var advanced: Dictionary = trial.fixed_update(DT,trial_entities,session.players,true)
		candidate_ticks+=1
		elapsed+=DT
		trial_entities[Station.CONTROLLER].takeover_remaining=maxf(0.0,8.0-elapsed)
		if not advanced.ok or advanced.get("axis_blocked",false) or advanced.get("float_blocked",false):
			clear=false
			actions.append({"kind":"candidate_physical_failure","step":candidate_ticks,"result":advanced})
			break
		if trial.status().both_samples_recorded and trial.status().selector_position==0.0: break
	var after: Dictionary = trial.snapshot()
	actions.append({"kind":"trusted_local_power_takeover_boundary_fixture_not_Session_input","before":before,"after":after,
		"steps":candidate_ticks,"simulated_seconds":elapsed,"scene_tree_paused":paused,"runtime_facts":"owner1, remaining8→0, actual swept selector positions"})
	physical_probes.trial=_trial_physics()
	return _check(clear and _trial_volumes()==[160000,20000,20000] and trial.status().selector_position==0.0
		and bool(physical_probes.trial.all_physics_poses_match),"swept candidate pulse yields two exact 20 L samples and neutral with actual float poses")

func _open_existing_cabinet() -> bool:
	var module = session.distribution.module
	var local_entities: Dictionary = {}
	for entity in module.target_definitions(): local_entities[entity.id]=entity
	local_entities[Cabinet.RELAY_ID].powered=true
	local_entities[Cabinet.LOCK_ID].controlled=true
	local_entities[Cabinet.LOCK_ID].owner="1"
	local_entities[Cabinet.LOCK_ID].takeover_remaining=8.0
	var before: Dictionary = module.snapshot()
	var clear := true
	for unused in range(126):
		await physics_frame
		if finishing: return false
		var advanced: Dictionary = module.fixed_update(DT,local_entities,session.players,true)
		cabinet_ticks+=1
		local_entities[Cabinet.LOCK_ID].takeover_remaining=maxf(0.0,8.0-float(cabinet_ticks)*DT)
		if not advanced.ok or advanced.get("door_blocked",false):
			clear=false
			break
		if module.snapshot().electric_latched: break
	actions.append({"kind":"existing_cabinet_trusted_actuator_boundary_fixture_not_Session_input","before":before,"after":module.snapshot(),"steps":cabinet_ticks})
	return _check(clear and module.snapshot().electric_latched and module.snapshot().door_fraction==1.0,"existing real door completes its full swept stroke beside candidate external pipes")

func _trial_volumes() -> Array:
	var result: Array = []
	for id in [TrialRuntime.SOURCE,TrialRuntime.RECEIVER_A,TrialRuntime.RECEIVER_B]: result.append(int(trial.get_water_node(id).volume_ml))
	return result

func _trial_physics() -> Dictionary:
	var poses: Array = []
	var aligned := true
	for moving: StaticBody3D in trial.selector_bodies.values()+trial.float_bodies.values()+trial.valve_bodies.values()+isolation.moving_bodies.values():
		var actual: Transform3D = PhysicsServer3D.body_get_state(moving.get_rid(),PhysicsServer3D.BODY_STATE_TRANSFORM)
		var matches := actual.is_equal_approx(moving.global_transform)
		aligned=aligned and matches
		poses.append({"node":str(moving.name),"scene_position":_vec(moving.global_position),"physics_position":_vec(actual.origin),"matches":matches})
	var water: Array = []
	for id in [TrialRuntime.SOURCE,TrialRuntime.RECEIVER_A,TrialRuntime.RECEIVER_B]:
		var visual: MeshInstance3D = trial.water_visuals[id]
		water.append({"id":id,"node":trial.get_water_node(id),"visual_top_y":visual.global_position.y+visual.scale.y*.5,
			"float_world_position":_vec(trial.float_bodies[id].global_position),"water_collision":false})
	return {"all_physics_poses_match":aligned,"moving_bodies":poses,"water":water,"cabinet_connected":trial.connection_status().ok,"link":isolation.snapshot(),"external_service_ports":trial.layout().service_ports}

func _json_observation(raw: Dictionary) -> Dictionary:
	var copy := raw.duplicate(true)
	if copy.get("float_world_position") is Vector3: copy.float_world_position=_vec(copy.float_world_position)
	return copy

func _ui_record() -> Dictionary:
	var result: Dictionary = super._ui_record()
	if is_instance_valid(gauge_readout):
		var rectangle := gauge_readout.get_global_rect()
		result.trial_gauge={"visible":gauge_readout.is_visible_in_tree(),
			"rect":[rectangle.position.x,rectangle.position.y,rectangle.size.x,rectangle.size.y],
			"rows":{}}
		for id in gauge_readout.headings:
			result.trial_gauge.rows[id]={"heading":gauge_readout.headings[id].text,"value":gauge_readout.values[id].text}
		if not gauge_readout.readings_snapshot().readings.is_empty():
			_check(gauge_readout.is_visible_in_tree() and not gauge_readout.layout_blocked
				and Rect2(Vector2.ZERO,Vector2(SIZE)).encloses(rectangle),"actual successful observation readout remains visible within 720p")
	return result

func _state() -> Dictionary:
	var result: Dictionary = super._state()
	if session.distribution.ready: result.distribution=session.distribution.persistent_state()
	if is_instance_valid(trial) and trial.configured:
		result.trial_candidate=trial.snapshot()
		result.trial_physics=_trial_physics()
	if is_instance_valid(gauge_readout):
		result.trial_gauge_readout=gauge_readout.readings_snapshot()
		result.trial_gauge_readout.visible=gauge_readout.is_visible_in_tree()
		result.trial_gauge_readout.layout_blocked=gauge_readout.layout_blocked
	return result

func _extend_scene_inputs(inventory: Dictionary) -> void:
	for path in inventory.imported_sources+inventory.material_sources:
		if path not in input_paths: input_paths.append(path)
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
	var final_state: Dictionary = _state() if is_instance_valid(session) and session.players.has(1) else {}
	if is_instance_valid(session):
		session.active=false
		if is_instance_valid(session.network): session.network.close()
		session.free()
	await process_frame
	await process_frame
	var after := _input_hashes()
	_check(_hashes_complete() and hashes_before==after,"all captured source/layout/action/import/material bytes remain identical")
	_check(shots.size()==5,"all five requested candidate diagnostic views saved")
	var logged: Dictionary = capture_logger.snapshot()
	_check(int(logged.error_count)==0,"no engine/script/shader error including cleanup")
	var passed := true
	for check in checks: passed=passed and bool(check.passed)
	var report := {"passed":passed,"status":"temporary_connected_sampling_candidate_not_session_or_art_acceptance", "profile":profile,"output":output,
		"checks":checks,"shots":shots,"actions":actions,"fixture":fixture,"QA_placements":placements,"physical_probes":physical_probes,
		"final_state":final_state,"candidate_fixed_steps":candidate_ticks,"cabinet_fixed_steps":cabinet_ticks,"nominal_step_seconds":DT,
		"scene_inventory":inventories,"input_sha256_before":hashes_before,"input_sha256_after":after,"engine_log":logged,
		"engine":Engine.get_version_info(),"renderer":RenderingServer.get_current_rendering_method(),"GPU":RenderingServer.get_video_adapter_name(),
		"viewport":[root.size.x,root.size.y],"wall_seconds":float(Time.get_ticks_usec()-started_usec)/1000000.0,
		"limits":["Production MAIN, legal historical27 fixture and actual region transition. Historical goals were replayed, not played by a person.",
			"Temporary Station is added only to this QA world. It has no Session ability registrations, saved state, global route fact, objective or reward.",
			"Actual linked low pipes pass through the reviewed five-piece floor. A declared saved TRIAL pose initializes the isolation Link; it is not a player action or proof of understanding.",
			"Local trusted power/takeover entity facts drive genuine swept actuator and hydraulic steps. These are direct physical-boundary fixtures, not keyboard F/G or RPC interaction.",
			"World simulation remains paused; one explicit candidate/old-door fixed call per awaited physics frame. No whole-Session playthrough, timing, LAN or performance conclusion.",
			"Frozen pilot poses are checked for actual full-envelope clearance but were not flown. Cached AGL is not overwritten and is not verified.",
			"Production fixed camera, HUD and lighting are preserved; close views use exactly three ordinary zoom steps. Liquid height is not exaggerated.",
			"Two 20 L samples imply 10cm receiver liquid rises. Optional A/B identity meshes and observation-only UI are temporary capture presentation; no formal Session input integration. Screenshots require visual review and are not human usability acceptance.",
			"A parser error before initialization cannot be recorded by this logger; the runner must require natural process success and this completed report."]}
	var path := output.path_join("state_checks.json")
	var file: FileAccess = FileAccess.open(path,FileAccess.WRITE) if not FileAccess.file_exists(path) else null
	var wrote := file!=null
	if file!=null:
		file.store_string(JSON.stringify(report,"\t",true,true))
		file.flush()
		wrote=file.get_error()==OK
		file.close()
	if not wrote: push_error("TRIAL_CAPTURE cannot write fresh state_checks.json")
	var final_log: Dictionary = capture_logger.snapshot()
	var success: bool = passed and wrote and int(final_log.error_count)==0
	print("TRIAL_STATION_CANDIDATE_CAPTURE ",JSON.stringify({"passed":success,"shots":shots.size(),"checks":checks.size(),"errors":final_log.error_count,"output":output}))
	OS.remove_logger(capture_logger)
	quit(0 if success else 1)
