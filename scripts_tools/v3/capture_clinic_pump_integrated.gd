extends "res://scripts_tools/v3/capture_clinic_integrated.gd"
## Actual MAIN/I2 imported shell in production light/camera/HUD. Historical
## progression and pilot positions are declared QA fixtures, not human play.
const SELF_PATH := "res://scripts_tools/v3/capture_clinic_pump_integrated.gd"
var saved_before: Dictionary = {}
var additional_inputs: Array[String] = []
var diagnostic_only := false

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
	if regex.compile("^qa_visual_clinic_pump_[A-Za-z0-9_-]+$")!=OK: return false
	if profile_count!=1 or output_count!=1 or regex.search(profile)==null: return false
	output=ProjectSettings.globalize_path(output).replace("\\","/").simplify_path()
	var allowed := ProjectSettings.globalize_path("res://artifacts/v3/art").replace("\\","/").simplify_path()
	if not output.is_absolute_path() or output.get_base_dir().to_lower()!=allowed.to_lower(): return false
	if not output.get_file().begins_with("clinic-pump-integrated-") or output.get_file()=="clinic-pump-integrated-": return false
	if DirAccess.dir_exists_absolute(output) or FileAccess.file_exists(output): return false
	if DirAccess.dir_exists_absolute("user://profiles_v3/"+profile) or FileAccess.file_exists("user://profiles_v3/"+profile): return false
	return OS.is_debug_build() and DisplayServer.get_name()!="headless" and RenderingServer.get_current_rendering_method()=="gl_compatibility" and RenderingServer.is_render_loop_enabled() and Engine.physics_ticks_per_second==60

func _run() -> void:
	started_usec=Time.get_ticks_usec()
	if not _arguments_valid():
		push_error("PUMP_CAPTURE requires a fresh QA profile/output and source Compatibility renderer")
		OS.remove_logger(capture_logger)
		quit(2)
		return
	if DirAccess.make_dir_recursive_absolute(output)!=OK:
		push_error("PUMP_CAPTURE cannot create fresh output")
		OS.remove_logger(capture_logger)
		quit(2)
		return
	create_timer(180.0,true,false,true).timeout.connect(_timeout)
	root.size=SIZE
	input_paths.assign(INPUTS)
	input_paths.append(SELF_PATH)
	input_paths.append_array(additional_inputs)
	input_paths.append("res://tests_v3/test_clinic_pump_art.gd")
	for directory in ["res://scripts/v3","res://data/v3","res://scenes/v3"]: _collect_inputs(directory)
	# These two standalone development files are not loaded by MAIN/World or
	# this pump review. Their assigned writer can work while we capture the
	# actual production dependencies; the isolated trial has its own fixture.
	for inactive in ["res://scripts/v3/world/twin_trial_flow_station.gd","res://data/v3/terrain/i2_trial_flow_layout.json"]:
		input_paths.erase(inactive)
	_add_import_hashes()
	hashes_before=_input_hashes()
	session=MAIN.instantiate()
	root.add_child(session)
	if not _check(session.profile_ready and session.store.root_path=="user://profiles_v3/"+profile and session.start_flight("solo"),"fresh MAIN opens isolated I1"):
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
	if not _check(session.region_id=="I2" and session._facilities_ready() and session.world.build_errors.is_empty(),"real region travel constructs complete I2"):
		await _finish()
		return
	body=session.players[1]
	inventories.I2=_scene_inventory(session.world)
	_extend_scene_inputs(inventories.I2)
	var module: Node3D = session.clinic.module
	if not _check(module.pump_art.get("ok",false) and module.pump_art.mesh_count==6 and module.pump_art.triangles==13600,"production waterworks installs complete imported shell"):
		await _finish()
		return
	_check(not module.fixed_bodies.PumpRoof.get_node("Visual").visible and module.get_meta("authored_pump_shell",false),"real old gray shell is replaced by independent visual groups")
	saved_before=session.store.snapshot()
	await _place(Vector3(-7,1.8,14.5),"clear exterior south of real 3.4m pump entrance")
	await _capture("01-I2-pump-entrance-default","Production imported shell from the entrance, fixed default 26m camera and actual 720p HUD.")
	if finishing: return
	await _capture("02-I2-pump-entrance-zoom2","Same real outside position; two ordinary zoom steps inspect roof overlap, steel paint, jamb marks and ground.",2)
	if finishing: return
	await _place(Vector3(-7,1.8,9.5),"clear interior pose; independent physical test covers flown-envelope entrance passage")
	await _capture("03-I2-pump-interior-default","Actual production cutaway of the imported roof and walls; permanent wall feet and floor remain.")
	if finishing: return
	_check(_roof_probe(),"actual physics roof still blocks ray while its imported presentation fades")
	await _capture("04-I2-pump-interior-zoom2","Actual interior with two ordinary zoom steps; inspect material, mechanism visibility and retained navigation geometry.",2)
	if finishing: return
	await _place(Vector3(-7,5,14.5),"clear elevated exterior for roof and wall relationship")
	await _capture("05-I2-pump-raised-exterior","Raised pilot outside the unchanged collision shell, default production camera; not an alternate art camera.")
	if finishing: return
	_check(_same(saved_before,session.store.snapshot()) and session.story.state.completed.size()==27,"visual review leaves all production progression and save state unchanged")
	await _finish()

func _extend_scene_inputs(inventory: Dictionary) -> void:
	for path in inventory.imported_sources+inventory.material_sources:
		if path not in input_paths: input_paths.append(path)
	_add_import_hashes()
	for path in input_paths:
		if not hashes_before.has(path): hashes_before[path]=FileAccess.get_sha256(path) if FileAccess.file_exists(path) else "MISSING"

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
	var complete := not hashes_before.is_empty()
	for value in hashes_before.values(): complete=complete and str(value).length()==64
	_check(complete and hashes_before==after,"all captured source/import/material inputs retain identical bytes")
	_check(shots.size()==5,"all five real imported-shell review views are saved")
	var logged: Dictionary = capture_logger.snapshot()
	_check(int(logged.error_count)==0,"zero engine/script/shader errors including cleanup")
	var passed := true
	for check in checks: passed=passed and bool(check.passed)
	var report := {"passed":passed,"status":"controlled_material_diagnosis_not_production_lighting" if diagnostic_only else "production_imported_shell_visual_review_not_final_art_acceptance", "profile":profile,"output":output,
		"checks":checks,"shots":shots,"fixture":fixture,"QA_placements":placements,"physical_probes":physical_probes,"final_state":final_state,
		"scene_inventory":inventories,"input_sha256_before":hashes_before,"input_sha256_after":after,"engine_log":logged,
		"engine":Engine.get_version_info(),"renderer":RenderingServer.get_current_rendering_method(),"GPU":RenderingServer.get_video_adapter_name(),
		"viewport":[root.size.x,root.size.y],"wall_seconds":float(Time.get_ticks_usec()-started_usec)/1000000.0,
		"limits":["Production MAIN and actual I2 import, camera, lighting, HUD and cutaway; source script only, not packaged EXE.",
			"Historical27 was replayed as a trusted fixture. Pilot positions are clearance-checked frozen placements, not human flight.",
			"World is paused; no pump activation, new objective, reward, LAN, FPS or human-fun acceptance.",
			"Close views use ordinary wheel zoom; cached AGL is not overwritten or validated.",
			"A completed error-free capture records images for review, not automatic artistic acceptance."]}
	var path := output.path_join("state_checks.json")
	var file: FileAccess = FileAccess.open(path,FileAccess.WRITE) if not FileAccess.file_exists(path) else null
	var wrote := file!=null
	if file!=null:
		file.store_string(JSON.stringify(report,"\t",true,true))
		file.flush()
		wrote=file.get_error()==OK
		file.close()
	if not wrote: push_error("PUMP_CAPTURE cannot write fresh state_checks.json")
	var final_log: Dictionary = capture_logger.snapshot()
	var success: bool = passed and wrote and int(final_log.error_count)==0
	print("CLINIC_PUMP_INTEGRATED_CAPTURE ",JSON.stringify({"passed":success,"shots":shots.size(),"checks":checks.size(),"errors":final_log.error_count,"output":output}))
	OS.remove_logger(capture_logger)
	quit(0 if success else 1)
