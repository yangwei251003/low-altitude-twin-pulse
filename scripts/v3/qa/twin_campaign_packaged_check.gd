extends Node
## Exported EXE resource/graphics check. Session owns all ordinary simulation.
const Regions = preload("res://scripts/v3/world/twin_region_catalog.gd")
const Layout = preload("res://scripts/v3/campaign/twin_campaign_layout.gd")
const Store = preload("res://scripts/v3/core/twin_world_store.gd")
const ORDER := ["I1","F1","I2","F2","I3","F3","I4","F4"]
const ARROWS := {"F2":["F2:clock_mirror"],"I3":["I3:cooling_valve"],"F3":["F3:signal_hold"],"F4":["F4:test_hold","F4:living_emitter"]}
class ErrorLogger extends Logger:
	var guard := Mutex.new()
	var errors: Array = []
	var warnings: Array = []
	func _log_error(function: String,file: String,line: int,code: String,rationale: String,_notify: bool,kind: int,trace: Array[ScriptBacktrace]) -> void:
		var row := {"function":function,"file":file,"line":line,"code":code,"rationale":rationale,"kind":kind,"trace":trace.map(func(item: ScriptBacktrace): return str(item))}
		guard.lock()
		if kind==Logger.ERROR_TYPE_WARNING: warnings.append(row)
		else: errors.append(row)
		guard.unlock()
var logger := ErrorLogger.new()
var session: Node
var output := ""
var profile := ""
var checks: Array = []
var regions: Array = []
var shots: Array = []
var save_callbacks: Array = []
var finished := false
var began_usec := 0

func run(owner_session: Node, absolute_output: String) -> void:
	session = owner_session
	output = absolute_output.replace("\\","/")
	OS.add_logger(logger)
	began_usec = Time.get_ticks_usec()
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--qa-profile="): profile = arg.trim_prefix("--qa-profile=")
	if not output.is_absolute_path() or not output.get_file().begins_with("campaign-package-") or ".." in output or not profile.begins_with("qa_campaign_packaged_") or profile!=profile.validate_filename() or session.store.root_path!="user://profiles_v3/"+profile:
		push_error("Campaign package check requires an absolute dedicated output and unique qa_campaign_packaged_ profile")
		get_tree().quit(2)
		return
	DirAccess.make_dir_recursive_absolute(output)
	get_tree().create_timer(118).timeout.connect(func():
		if not finished:
			_check(false,"118 second total exported-runtime bound",_diagnostics())
			_finish())
	if not _check(not OS.has_feature("editor") and DisplayServer.get_name()!="headless","actual exported binary with a rendered display",{"editor_binary":OS.has_feature("editor"),"display":DisplayServer.get_name(),"executable":OS.get_executable_path()}): _finish(); return
	if not _check(session.profile_ready and session.store.snapshot().personal.discoveries.is_empty() and session.world_cache.world.get("actions",{}).get("opening",{}).get("completed",[]).is_empty(),"fresh independent QA profile has no injected progress or rewards"): _finish(); return
	# Process-local development availability only. No data file, task state,
	# physical environment or gameplay fact is patched to load these areas.
	Regions._entries = Regions.entries()
	for item: Dictionary in Regions._entries:
		if item.id not in ORDER: continue
		item.playable = true
		var layout: Dictionary = Layout.definition(str(item.id))
		if not layout.is_empty():
			item.spawn = layout.spawn.duplicate()
			item.bounds = layout.bounds.duplicate()
	session.inputs.test_enabled = true
	session.inputs.test_frame = {"axes":{},"held":["brake"],"edges":[]}
	if not _check(session.start_flight("solo"),"ordinary Session starts a solo QA world",_diagnostics()): _finish(); return
	for id: String in ORDER:
		if finished: return
		if session.region_id!=id:
			if not _check(session._load_region(id) and session.region_id==id,"ordinary QA Session loads exported region "+id,_diagnostics()): _finish(); return
		var actor: FlightBodyV2 = session.players[1]
		actor.freeze = false
		if not await _wait_ready(id): _finish(); return
		if finished: return
		var probe: Dictionary = _inspect_region(id)
		regions.append(probe)
		if not _check(probe.ok,"package scene/native collisions/default modules/view/audio valid: "+id,probe): _finish(); return
		if not await _capture(id,"default",false): _finish(); return
		if not await _arena_pose(id): _finish(); return
		if not await _capture(id,"arena-observation",true): _finish(); return
		actor.freeze = false
		if not await _save("leave_"+id): _finish(); return
		print("CAMPAIGN_PACKAGE_PROGRESS "+JSON.stringify({"region":id,"shots":shots.size(),"elapsed_seconds":_elapsed(),"ready":_diagnostics()}))
	if not await _save("final"): _finish(); return
	var reader = Store.new(session.store.root_path)
	var loaded: Dictionary = reader.load_profile()
	var disk: Dictionary = reader.snapshot()
	var current: Dictionary = session.store.snapshot()
	_check(loaded.get("ok",false) and disk==current and disk.personal.discoveries.is_empty() and disk.world.get("actions",{}).get("opening",{}).get("completed",[]).is_empty(),"independent original Store reads exactly the published QA world with no injected goals or rewards",{"reader":loaded,"disk_generation":disk.get("generation"),"current_generation":current.get("generation"),"exact_readback_equal":disk==current,"environment_keys":disk.world.get("environment",{}).keys()})
	_finish()

func _wait_ready(id: String) -> bool:
	var deadline: int = Time.get_ticks_usec()+(50000000 if id=="I2" else 5000000)
	var samples := 0
	while Time.get_ticks_usec()<deadline:
		await _frame()
		if finished: return false
		samples += 1
		var ready: bool = session.active and session._facilities_ready()
		if id=="I2": ready = ready and session.canal_runtime_enabled and session.canal!=null and session.canal.ready
		if id=="I3": ready = ready and session.thermal_cargo.enabled and session.thermal_cargo.supported() and session.thermal_cargo.module.ready
		if ready and samples>=8: return _check(true,"ordinary module ticks reach initial readiness: "+id,_diagnostics())
	return _check(false,"ordinary module ticks reach bounded initial readiness: "+id,_diagnostics())

func _inspect_region(id: String) -> Dictionary:
	var world: Node3D = session.world
	var bodies: Array = []
	var native_shapes := 0
	var meshes := 0
	var stack: Array[Node] = [world]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		for child: Node in node.get_children(): stack.append(child)
		if node is MeshInstance3D and node.mesh!=null: meshes += 1
		if not node is PhysicsBody3D or node==session.players[1] or node.collision_layer==0: continue
		var count: int = PhysicsServer3D.body_get_shape_count(node.get_rid())
		if count<1: continue
		native_shapes += count
		bodies.append({"path":str(world.get_path_to(node)),"class":node.get_class(),"layer":node.collision_layer,"mask":node.collision_mask,"native_shape_count":count})
	var mechanism: Dictionary = {"applicable":id in ["F2","I3","F3","I4","F4"],"ok":true,"arrows":[]}
	if mechanism.applicable:
		var view: Node3D = world.campaign_mechanism_view
		mechanism["view_present"] = is_instance_valid(view) and view.get_parent()==world
		mechanism["beam_meshes"] = view._beams.size() if is_instance_valid(view) else 0
		mechanism["endpoint_present"] = is_instance_valid(view) and is_instance_valid(view._receiver) and view._receiver.mesh!=null
		mechanism.ok = mechanism.view_present and mechanism.beam_meshes==4 and mechanism.endpoint_present
		for target: String in ARROWS.get(id,[]):
			var body: Node3D = world.objects.get(target)
			var arrow: Node3D = body.get_node_or_null("MechanismDirection") if is_instance_valid(body) else null
			var valid: bool = arrow!=null and arrow.get_parent()==body and arrow.global_basis.is_equal_approx(body.global_basis) and arrow.get_node_or_null("DirectionStem") is MeshInstance3D and arrow.get_node_or_null("DirectionTip") is MeshInstance3D
			mechanism.arrows.append({"target":target,"ok":valid})
			mechanism.ok = mechanism.ok and valid
	var facilities: Array = []
	var module_ok := true
	if id=="I2":
		for key: String in ["clinic","distribution","trial","shared_access"]:
			var adapter = session.get(key)
			var valid: bool = adapter.ready and is_instance_valid(adapter.module) and adapter.module.get_parent()==world
			facilities.append({"id":key,"ready":adapter.ready,"world_owned":valid})
			module_ok = module_ok and valid
		module_ok = module_ok and session.canal_runtime_enabled and session.canal!=null and session.canal.ready and session.canal.module.get_parent()==world
	if id=="I3": module_ok = session.thermal_cargo.enabled and session.thermal_cargo.supported() and session.thermal_cargo.module.ready
	var sound: Dictionary = _audio()
	return {"id":id,"ok":world.build_errors.is_empty() and bodies.size()>0 and native_shapes>0 and meshes>0 and module_ok and mechanism.ok and sound.resources_ok,"build_errors":world.build_errors.duplicate(),"native_body_count":bodies.size(),"native_shapes":native_shapes,"bodies":bodies,"mesh_instances":meshes,"modules_ok":module_ok,"four_original_facilities":facilities,"mechanism_display":mechanism,"audio":sound,"defaults":{"canal_runtime_enabled":session.canal_runtime_enabled,"canal_bound":session.canal!=null,"thermal_enabled":session.thermal_cargo.enabled,"thermal_bound":session.thermal_cargo.supported()},"physics_frame":Engine.get_physics_frames()}

func _arena_pose(id: String) -> bool:
	var point: Vector3
	if is_instance_valid(session.world.campaign_arena): point = session.world.campaign_arena.centre()+Vector3(0,3,12)
	else:
		var marker: String = "I1:whale_briefing" if id=="I1" else "F1:crown_briefing"
		if not session.story.markers.has(marker): return _check(false,"authored safe arena observation marker exists: "+id)
		point = session.story._point(session.story.markers[marker])+Vector3(0,2,3)
	var actor: FlightBodyV2 = session.players[1]
	var envelope := actor.get_node("Envelope") as CollisionShape3D
	var selected := Vector3.INF
	var attempts: Array = []
	for offset: Vector3 in [Vector3.ZERO,Vector3(5,0,0),Vector3(-5,0,0),Vector3(0,3,0)]:
		var at: Vector3 = point+offset
		var query := PhysicsShapeQueryParameters3D.new()
		query.shape = envelope.shape
		query.transform = Transform3D(Basis.IDENTITY,at)*envelope.transform
		query.collision_mask = 1|2|8|32
		query.exclude = [actor.get_rid()]
		var hits: Array[Dictionary] = session.world.get_world_3d().direct_space_state.intersect_shape(query,8)
		attempts.append({"at":at,"inside_bounds":Regions.contains(id,at),"hits":hits.map(func(hit: Dictionary): return str(hit.collider.get_path()))})
		if hits.is_empty() and Regions.contains(id,at): selected=at; break
	if not _check(selected.is_finite(),"QA arena observer has actual full-aircraft clearance: "+id,attempts): return false
	actor.freeze = true
	actor.global_transform = Transform3D(Basis.IDENTITY,selected)
	actor.force_update_transform()
	PhysicsServer3D.body_set_state(actor.get_rid(),PhysicsServer3D.BODY_STATE_TRANSFORM,actor.global_transform)
	actor.linear_velocity = Vector3.ZERO
	actor.angular_velocity = Vector3.ZERO
	actor.hold_height = selected.y
	actor.safe_position = selected
	await _frame()
	return not finished

func _capture(id: String,kind: String,pose_fixture: bool) -> bool:
	if shots.size()>=16: return _check(false,"at most sixteen package screenshots")
	session.flight_camera.target_size = 26
	session.flight_camera.snap(session.players[1].global_position)
	session.interface.clear_dialogue()
	for unused in 4:
		await _frame()
		if finished: return false
	await RenderingServer.frame_post_draw
	if finished: return false
	var image: Image = get_viewport().get_texture().get_image()
	var path: String = output.path_join(id+"-"+kind+".png")
	var saved: bool = image!=null and not image.is_empty() and image.save_png(path)==OK
	shots.append({"region":id,"view":kind,"path":path,"saved":saved,"pose_fixture":pose_fixture,"actor_position":session.players[1].global_position,"camera_size":session.camera.size,"camera_transform":session.camera.global_transform,"viewport":[get_viewport().size.x,get_viewport().size.y],"audio":_audio(),"physics_frame":Engine.get_physics_frames()})
	return _check(saved,"save actual packaged default oblique frame: "+id+" "+kind)

func _save(label: String) -> bool:
	var deadline: int = Time.get_ticks_usec()+4000000
	while session.environment_save_gate.pending() and Time.get_ticks_usec()<deadline:
		await _frame()
		if finished: return false
	var before: int = save_callbacks.size()
	var request: Dictionary = session.request_environment_save(func(result: Dictionary): save_callbacks.append({"label":label,"result":result.duplicate(true)}))
	if not _check(request.get("ok",false),"original SaveGate accepts "+label,request): return false
	while save_callbacks.size()==before and Time.get_ticks_usec()<deadline:
		await _frame()
		if finished: return false
	return _check(save_callbacks.size()==before+1 and save_callbacks[before].result.get("ok",false) and save_callbacks[before].result.get("completed",false),"original SaveGate completes "+label,{"callbacks":save_callbacks.slice(before),"commit":session.last_commit_result})

func _audio() -> Dictionary:
	var diagnostic: Dictionary = session.audio.diagnostics()
	var buses: Array = []
	var loops: Array = []
	var resources_ok: bool = diagnostic.get("ready",false) and diagnostic.get("missing",[]).is_empty() and not session.audio._streams.is_empty()
	for name: String in ["V3Master","V3Music","V3SFX","V3Ambient","V3Rotor","V3UI"]:
		var index: int = AudioServer.get_bus_index(name)
		var row := {"name":name,"present":index>=0}
		if index>=0:
			var left: float = AudioServer.get_bus_peak_volume_left_db(index,0)
			var right: float = AudioServer.get_bus_peak_volume_right_db(index,0)
			row["peak_left_db"] = left if is_finite(left) else null
			row["peak_right_db"] = right if is_finite(right) else null
			row["muted"] = AudioServer.is_bus_mute(index)
			row["volume_db"] = AudioServer.get_bus_volume_db(index)
		resources_ok = resources_ok and index>=0
		buses.append(row)
	for id: String in session.audio._loops:
		var player: AudioStreamPlayer = session.audio._loops[id]
		var valid: bool = player.stream!=null and player.playing
		loops.append({"id":id,"loaded":player.stream!=null,"playing":player.playing,"bus":player.bus,"volume_db":player.volume_db,"resource":player.stream.resource_path if player.stream!=null else ""})
		resources_ok = resources_ok and valid
	return {"resources_ok":resources_ok,"diagnostics":diagnostic,"loaded_stream_count":session.audio._streams.size(),"buses":buses,"loops":loops,"output_device":AudioServer.output_device,"scope":"Observed local numeric bus meters and playing resources only; no human listening or audible-output claim, no mix/settings writes."}

func _joypads() -> Array:
	var result: Array = []
	for id: int in Input.get_connected_joypads(): result.append({"id":id,"name":Input.get_joy_name(id),"guid":Input.get_joy_guid(id)})
	return result

func _frame() -> void:
	await get_tree().physics_frame
	await get_tree().process_frame

func _elapsed() -> float:
	return float(Time.get_ticks_usec()-began_usec)/1000000.0

func _diagnostics() -> Dictionary:
	if not is_instance_valid(session): return {"session":"not_installed"}
	return {"region":session.region_id,"active":session.active,"message":session.interface.message.text,"world_errors":session.world.build_errors if is_instance_valid(session.world) else [],"canal":session.canal.status() if session.canal!=null else {},"thermal":session.thermal_cargo.module.status() if session.thermal_cargo.module!=null else {},"facility_error":session.facilities.error,"commit":session.last_commit_result.duplicate(true)}

func _check(ok: bool,label: String,actual: Variant=null) -> bool:
	checks.append({"passed":ok,"label":label,"actual":actual})
	return ok

func _finish() -> void:
	if finished: return
	finished = true
	var failures: Array = checks.filter(func(row: Dictionary): return not row.passed)
	var passed: bool = failures.is_empty() and logger.errors.is_empty() and regions.size()==8 and shots.size()==16
	var report := {"passed":passed,"editor_binary":OS.has_feature("editor"),"executable":OS.get_executable_path(),"runtime_cwd":DirAccess.open(".").get_current_dir(),"profile":profile,"version":ProjectSettings.get_setting("application/config/version"),"video_adapter":RenderingServer.get_video_adapter_name(),"renderer":RenderingServer.get_current_rendering_method(),"rendering_driver":RenderingServer.get_current_rendering_driver_name(),"project_renderer_default":str(ProjectSettings.get_setting_with_override("rendering/renderer/rendering_method")),"project_rd_driver_default":str(ProjectSettings.get_setting_with_override("rendering/rendering_device/driver")),"display":DisplayServer.get_name(),"elapsed_seconds":_elapsed(),"checks":checks,"failures":failures,"engine_errors":logger.errors,"engine_warnings":logger.warnings,"regions":regions,"shots":shots,"save_callbacks":save_callbacks,"joypads":_joypads(),"final_audio":_audio(),"diagnostics":_diagnostics(),"scope":"Actual newly exported EXE, own-folder launch and no source --path. Eight direct QA region loads are availability/lifecycle fixtures; default oblique and safe arena camera observations only (at most16). Explicit clear aircraft observation poses, ordinary Session brake input and ordinary ticks, default Canal and I3 participant binding, exported scene/native collision/visual/audio-resource checks, original asynchronous SaveGate and independent exact original Store readback. No injected Director prefix, environment fact, task completion or reward. Numeric local audio meters/connected joypad inventory do not prove human listening/controller use. No normal unlock/flown route, Boss fight, full campaign, LAN, current performance/FPS, human comfort/fun or final-art claim. Complete engine stdout/stderr is additionally retained by the private Job runner, including errors before this opt-in driver loaded."}
	# Session owns this Node. Quit after ordinary owner cleanup, without freeing
	# an ancestor from inside its own child coroutine.
	session.environment_save_gate.cancel("qa_teardown")
	if session.canal!=null: session.canal.clear()
	session.thermal_cargo.clear()
	session.active=false
	session.audio.shutdown()
	session.network.close()
	var deadline: int=Time.get_ticks_usec()+1000000
	var drained: Dictionary=session.audio.shutdown_status()
	while not drained.ready and Time.get_ticks_usec()<deadline:
		await get_tree().process_frame
		drained=session.audio.shutdown_status()
	passed=passed and drained.ready
	report["passed"]=passed
	report["qa_audio_shutdown"]=drained
	var file := FileAccess.open(output.path_join("report.json"),FileAccess.WRITE)
	if file!=null: file.store_string(JSON.stringify(report,"\t"))
	print("CAMPAIGN_PACKAGE_RESULT "+JSON.stringify({"passed":passed,"regions":regions.size(),"shots":shots.size(),"failures":failures,"engine_errors":logger.errors,"elapsed_seconds":_elapsed(),"qa_audio_shutdown":drained}))
	get_tree().quit(0 if passed and file!=null else 1)
