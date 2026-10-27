extends Node
## Current exported-package screening, not five-minute/endurance acceptance.
## Only this observer and ordinary Pilot commands are added to normal Session.
const Regions = preload("res://scripts/v3/world/twin_region_catalog.gd")
const Layout = preload("res://scripts/v3/campaign/twin_campaign_layout.gd")
const Store = preload("res://scripts/v3/core/twin_world_store.gd")
const Pilot = preload("res://scripts/v3/gameplay/canal/canal_transport_physics/transport_pilot.gd")
const ORDER := ["I2","I3","F4"]
const LONG_I2 := "--qa-performance-long-i2"
const CARGO := "I3:loaded_cassette"
const SIZE := Vector2i(1280,720)
const PHYSICS_BOUNDARY_PRIORITY := 1000
signal sample_ready
class ErrorLogger extends Logger:
	var errors: Array = []
	var guard := Mutex.new()
	func _log_error(function: String,file: String,line: int,code: String,rationale: String,_notify: bool,kind: int,_trace: Array[ScriptBacktrace]) -> void:
		if kind==Logger.ERROR_TYPE_WARNING: return
		guard.lock()
		errors.append({"function":function,"file":file,"line":line,"code":code,"rationale":rationale,"kind":kind})
		guard.unlock()
class FlightCommands extends Node:
	var owner_session: Node
	var pilot: RefCounted
	var active := false
	func _physics_process(delta: float) -> void:
		if active and pilot!=null and is_instance_valid(owner_session) and owner_session.active and not owner_session.simulation_paused:
			pilot.tick(delta,true,false) # Commands original Flight only; no solver tick.
var logger := ErrorLogger.new()
var session: Node
var flight: FlightCommands
var output := ""
var profile := ""
var seconds := 30.0
var long_i2 := false
var target_seconds: Dictionary = {}
var watchdog_seconds := 210.0
var collect_cpu := false
var diagnostic_reasons: Array[String] = []
var disable_3d_diagnostic := false
var mobile_renderer_diagnostic := false
var game_viewport: Viewport
var original_disable_3d := false
var render_override_applied := false
var render_native_start: Dictionary = {}
var render_live_start: Dictionary = {}
var started := 0
var previous := 0
var recording := false
var finished := false
var stage := "setup"
var frames: Array = []
var resources: Array = []
var events: Array = []
var checks: Array = []
var issues: Array[String] = []
var results: Array = []
var callbacks: Array = []
var next_resource := 0.0
var expected_quality: Dictionary = {}
var _phase_first_physics_usec := 0
var _phase_last_physics_usec := 0
var _phase_physics_count := 0
var _phase_process_usec := 0
var _phase_process_frame := -1
var _phase_previous_physics_frame := -1
var _phase_node_pending_usec := 0
var _phase_node_pending_frame := -1
var _phase_node_span_usec := 0
var _phase_node_sample_count := 0
var _phase_node_invalid := false
var _phase_node_order_ok := true

static func long_i2_preflight(args: PackedStringArray) -> Dictionary:
	if LONG_I2 not in args: return {"ok":true}
	var profiles: Array = Array(args).filter(func(arg: String): return arg.begins_with("--qa-profile="))
	var outputs: Array = Array(args).filter(func(arg: String): return arg.begins_with("--qa-performance-output="))
	var durations: Array = Array(args).filter(func(arg: String): return arg.begins_with("--qa-performance-seconds="))
	if args.count(LONG_I2)!=1 or profiles.size()!=1 or outputs.size()!=1 or durations!=["--qa-performance-seconds=12"]: return {"ok":false,"code":"long_i2_exact_arguments_required"}
	var profile_name: String = str(profiles[0]).trim_prefix("--qa-profile=")
	var directory: String = str(outputs[0]).trim_prefix("--qa-performance-output=").replace("\\","/")
	if not profile_name.begins_with("qa_campaign_performance_") or profile_name!=profile_name.validate_filename() or not directory.is_absolute_path() or not directory.get_file().begins_with("campaign-performance-") or ".." in directory: return {"ok":false,"code":"long_i2_isolated_profile_output_required"}
	for arg: String in args:
		if arg!=LONG_I2 and arg!=profiles[0] and arg!=outputs[0] and arg!=durations[0]: return {"ok":false,"code":"long_i2_unexpected_argument"}
	return {"ok":true}

func run(owner_session: Node,absolute_output: String,seconds_per_region: float=30.0,cpu_scopes: bool=false,render_diagnostic: bool=false) -> void:
	session = owner_session
	output = absolute_output.replace("\\","/")
	seconds = seconds_per_region
	collect_cpu = cpu_scopes
	disable_3d_diagnostic = render_diagnostic
	var mobile_flags: int = OS.get_cmdline_user_args().count("--qa-renderer-mobile-diagnostic")
	mobile_renderer_diagnostic = mobile_flags==1
	if mobile_flags>1 or (mobile_renderer_diagnostic and disable_3d_diagnostic):
		push_error("Mobile renderer diagnostic requires one explicit flag and cannot disable 3D")
		get_tree().quit(2); return
	diagnostic_reasons.clear()
	if collect_cpu: diagnostic_reasons.append("cpu_scopes")
	if disable_3d_diagnostic: diagnostic_reasons.append("disabled_3d")
	if mobile_renderer_diagnostic: diagnostic_reasons.append("mobile_renderer")
	long_i2 = LONG_I2 in OS.get_cmdline_user_args()
	if not long_i2_preflight(OS.get_cmdline_user_args()).ok or (long_i2 and (seconds!=12.0 or collect_cpu or render_diagnostic or mobile_renderer_diagnostic)):
		push_error("Long I2 requires isolated normal 300/12/12 measurement"); get_tree().quit(2); return
	target_seconds = {"I2":300.0 if long_i2 else seconds,"I3":seconds,"F4":seconds}
	watchdog_seconds = 210.0+(300.0-seconds if long_i2 else 0.0)
	game_viewport = session.get_viewport()
	original_disable_3d = game_viewport.disable_3d
	if OS.get_cmdline_user_args().count("--disable-3d-diagnostic")!=(1 if disable_3d_diagnostic else 0) or not (game_viewport is Window) or game_viewport!=session._presentation_viewport or original_disable_3d:
		push_error("Render diagnostic requires explicit matching flag and ordinary enabled game Window viewport")
		get_tree().quit(2)
		return
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--qa-profile="): profile = arg.trim_prefix("--qa-profile=")
	if not output.is_absolute_path() or not output.get_file().begins_with("campaign-performance-") or ".." in output or not profile.begins_with("qa_campaign_performance_") or profile!=profile.validate_filename() or session.store.root_path!="user://profiles_v3/"+profile or not is_finite(seconds) or seconds<5 or seconds>30:
		push_error("Performance screening requires absolute dedicated output, qa_campaign_performance_ profile and 5..30 seconds per region")
		get_tree().quit(2)
		return
	OS.add_logger(logger)
	DirAccess.make_dir_recursive_absolute(output)
	started = Time.get_ticks_usec()
	previous = started
	process_physics_priority = PHYSICS_BOUNDARY_PRIORITY
	recording = true
	get_tree().physics_frame.connect(_phase_on_physics_frame)
	get_tree().process_frame.connect(_phase_on_process_frame)
	process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().create_timer(watchdog_seconds).timeout.connect(func():
		if not finished:
			_issue("%d_second_total_runtime_bound" % int(watchdog_seconds))
			_finish())
	expected_quality = _quality()
	_write_json("prepared.json",{"status":"starting_not_a_result","diagnostic_only":not diagnostic_reasons.is_empty(),"diagnostic_reasons":diagnostic_reasons.duplicate(),"environment":_environment(),"seconds_per_region":seconds,"target_seconds":target_seconds,"long_i2":long_i2,"observer_watchdog_seconds":watchdog_seconds,"order":ORDER,"pid":OS.get_process_id()})
	if not _check(not OS.has_feature("editor") and DisplayServer.get_name()!="headless" and RenderingServer.get_current_rendering_method()==("mobile" if mobile_renderer_diagnostic else str(ProjectSettings.get_setting_with_override("rendering/renderer/rendering_method"))) and (RenderingServer.get_current_rendering_method()!="mobile" or RenderingServer.get_current_rendering_driver_name()==("vulkan" if mobile_renderer_diagnostic else str(ProjectSettings.get_setting_with_override("rendering/rendering_device/driver")))),"actual exported requested renderer; Mobile diagnostic requires Vulkan without fallback") or not _check(session.profile_ready and session.store.snapshot().personal.discoveries.is_empty() and session.world_cache.world.get("actions",{}).get("opening",{}).get("completed",[]).is_empty(),"fresh independent QA without prior progression"):
		_finish(); return
	Regions._entries = Regions.entries()
	for item: Dictionary in Regions._entries:
		if item.id in ORDER:
			item.playable = true
			var layout: Dictionary = Layout.definition(str(item.id))
			if not layout.is_empty(): item.spawn=layout.spawn.duplicate(); item.bounds=layout.bounds.duplicate()
	session.inputs.test_enabled = true
	session.inputs.test_frame = {"axes":{},"held":["brake"],"edges":[]}
	flight = FlightCommands.new()
	flight.process_physics_priority = 10
	flight.owner_session = session
	add_child(flight)
	if not _check(session.start_flight("solo"),"ordinary Session starts solo"): _finish(); return
	for id: String in ORDER:
		stage = "load:"+id
		var load_start: int = Time.get_ticks_usec()
		if not _check(session._load_region(id) and session.region_id==id,"ordinary QA region loads "+id): _finish(); return
		await _next()
		if finished: return
		events.append({"kind":"load","region":id,"wall_seconds":float(Time.get_ticks_usec()-load_start)/1000000.0})
		stage = "initial_ready:"+id
		if not await _ready_region(id): _finish(); return
		var setup: Dictionary = {"kind":"idle_baseline","reason":"default live modules; no physical workload fabricated"}
		if id=="I3": setup = await _try_cargo()
		elif id=="F4": setup = await _try_light()
		if finished: return
		setup["initial_live_modules"] = _diagnostics()
		_phase_audit_physics_order(id) # Read-only, before the original three-second warmup.
		stage = "warmup:"+id
		session.flight_camera.target_size = 26
		session.flight_camera.snap(session.players[1].global_position)
		var warm_start: int = Time.get_ticks_usec()
		while Time.get_ticks_usec()-warm_start<3000000:
			await _next()
			if finished: return
		events.append({"kind":"warmup","region":id,"wall_seconds":float(Time.get_ticks_usec()-warm_start)/1000000.0})
		if disable_3d_diagnostic:
			stage = "render_transition:"+id
			var before_render_toggle: Dictionary = _native_identity()
			if not _check(before_render_toggle.owner_status.ok and before_render_toggle.owner_status.render_disabled and before_render_toggle.game_viewport!=before_render_toggle.physics_viewport,"original separate physics owner remains UPDATE_DISABLED: "+id,before_render_toggle.owner_status): _finish(); return
			# Only the ordinary game Window renders; never change RegionPhysicsOwner.
			game_viewport.disable_3d = true
			render_override_applied = true
			render_native_start = _native_identity()
			render_live_start = _diagnostics()
			if not _check(render_native_start==before_render_toggle,"render flag preserves native region/space/body identity: "+id): _finish(); return
			for unused in 2:
				await _next()
				if finished: return
		await _measure(id,setup)
		if finished: return
		if disable_3d_diagnostic:
			_restore_rendering()
			stage = "render_restore:"+id
			for unused in 2:
				await _next()
				if finished: return
			if not _check(not game_viewport.disable_3d,"ordinary 3D restored before original SaveGate: "+id): _finish(); return
		flight.active = false
		stage = "save:"+id
		if not await _save(id): _finish(); return
		print("CAMPAIGN_PERFORMANCE_PROGRESS "+JSON.stringify({"region":id,"result":results.back(),"elapsed_seconds":_elapsed()}))
	var reader = Store.new(session.store.root_path)
	var opened: Dictionary = reader.load_profile()
	var disk: Dictionary = reader.snapshot()
	_check(opened.get("ok",false) and disk==session.store.snapshot() and disk.personal.discoveries.is_empty() and disk.world.get("actions",{}).get("opening",{}).get("completed",[]).is_empty(),"independent original Store exact readback; no fabricated progression")
	_finish()

# Additive wall-clock markers only. Original frame timestamps/counters stay intact.
func _phase_on_physics_frame() -> void:
	if not recording or finished: return
	var now: int = Time.get_ticks_usec()
	if _phase_physics_count == 0: _phase_first_physics_usec = now
	_phase_last_physics_usec = now
	_phase_physics_count += 1
	# The whole first raw row is partial, including a late callback with no A.
	if frames.is_empty(): return
	var frame: int = Engine.get_physics_frames()
	if _phase_node_pending_frame >= 0: _phase_node_fail("unpaired_before_next_signal")
	if frame != _phase_previous_physics_frame + _phase_physics_count: _phase_node_fail("signal_frame_counter_invalid")
	_phase_node_pending_usec = now
	_phase_node_pending_frame = frame

func _physics_process(_delta: float) -> void:
	if not recording or finished or frames.is_empty(): return
	var now: int = Time.get_ticks_usec()
	var frame: int = Engine.get_physics_frames()
	if process_physics_priority != PHYSICS_BOUNDARY_PRIORITY or process_thread_group != Node.PROCESS_THREAD_GROUP_INHERIT:
		_phase_node_fail("observer_order_changed")
	if _phase_node_pending_frame < 0:
		_phase_node_fail("callback_without_signal"); return
	if frame != _phase_node_pending_frame: _phase_node_fail("callback_frame_mismatch")
	elif now < _phase_node_pending_usec: _phase_node_fail("callback_time_reversed")
	else:
		_phase_node_span_usec += now - _phase_node_pending_usec
		_phase_node_sample_count += 1
	_phase_node_pending_frame = -1
	_phase_node_pending_usec = 0

func _phase_node_fail(code: String) -> void:
	_phase_node_invalid = true
	_issue("phase_node_"+code)

func _phase_default_main_group(node: Node) -> bool:
	var cursor: Node = node
	while cursor != null:
		# Even explicit MAIN_THREAD owns a separate group; priority is not global.
		if cursor.process_thread_group != Node.PROCESS_THREAD_GROUP_INHERIT: return false
		cursor = cursor.get_parent()
	return true

func _phase_audit_physics_order(id: String) -> void:
	var pending: Array[Node] = [get_tree().root]
	var external := 0
	var internal := 0
	var violations: Array = []
	while not pending.is_empty():
		var node: Node = pending.pop_back()
		pending.append_array(node.get_children(true))
		var has_external: bool = node.is_physics_processing()
		var has_internal: bool = node.is_physics_processing_internal()
		if not has_external and not has_internal: continue
		if has_external: external += 1
		if has_internal: internal += 1
		var priority_ok: bool = node.process_physics_priority == PHYSICS_BOUNDARY_PRIORITY if node == self else node.process_physics_priority < PHYSICS_BOUNDARY_PRIORITY
		if not priority_ok or not _phase_default_main_group(node):
			violations.append({"path":str(node.get_path()),"priority":node.process_physics_priority,"default_group":_phase_default_main_group(node)})
	_phase_node_order_ok = violations.is_empty()
	_check(_phase_node_order_ok,"same default-main-group physics callbacks before observer: "+id,{"priority":PHYSICS_BOUNDARY_PRIORITY,"external":external,"internal":internal,"violations":violations})
	if not _phase_node_order_ok: _phase_node_fail("order_not_verified:"+id)

func _phase_node_columns(old: Dictionary, physics_frame: int) -> Dictionary:
	var columns: Dictionary = {"physics_node_span_usec":0,"physics_node_sample_count":0}
	if not frames.is_empty():
		if _phase_node_pending_frame >= 0: _phase_node_fail("unpaired_at_process")
		if _phase_node_sample_count != _phase_physics_count: _phase_node_fail("paired_count_mismatch")
		if not _phase_node_order_ok: _phase_node_fail("order_not_verified")
		var old_valid: bool = int(old["process_frame_usec"]) > 0 and _phase_physics_count == physics_frame - _phase_previous_physics_frame
		if _phase_physics_count > 0:
			old_valid = old_valid and int(old["physics_first_usec"]) > 0 and int(old["physics_last_usec"]) >= int(old["physics_first_usec"]) and int(old["process_frame_usec"]) >= int(old["physics_last_usec"])
			if _phase_node_span_usec > int(old["process_frame_usec"]) - int(old["physics_first_usec"]): _phase_node_fail("span_exceeds_original_P")
		else:
			old_valid = old_valid and _phase_first_physics_usec == 0 and _phase_last_physics_usec == 0
			if _phase_node_span_usec != 0 or _phase_node_sample_count != 0: _phase_node_fail("zero_signal_has_node_samples")
		if not old_valid: _phase_node_fail("existing_marker_invalid")
		if not _phase_node_invalid:
			columns["physics_node_span_usec"] = _phase_node_span_usec
			columns["physics_node_sample_count"] = _phase_node_sample_count
	_phase_node_pending_usec = 0
	_phase_node_pending_frame = -1
	_phase_node_span_usec = 0
	_phase_node_sample_count = 0
	_phase_node_invalid = false
	return columns

func _phase_on_process_frame() -> void:
	if not recording or finished: return
	_phase_process_usec = Time.get_ticks_usec()
	_phase_process_frame = Engine.get_process_frames()

func _phase_columns(now: int, physics_frame: int) -> Dictionary:
	var columns: Dictionary = {"physics_first_usec":0,"physics_last_usec":0,"physics_signal_count":0,"process_frame_usec":0}
	# run() may begin midway through an iteration; never invent its missing prefix.
	if not frames.is_empty():
		columns["physics_signal_count"] = _phase_physics_count
		var process_valid: bool = _phase_process_frame == Engine.get_process_frames() and _phase_process_usec >= previous and _phase_process_usec <= now
		if process_valid: columns["process_frame_usec"] = _phase_process_usec - started
		else: _issue("phase_process_marker_missing_or_stale")
		if _phase_physics_count > 0:
			if process_valid and previous <= _phase_first_physics_usec and _phase_first_physics_usec <= _phase_last_physics_usec and _phase_last_physics_usec <= _phase_process_usec:
				columns["physics_first_usec"] = _phase_first_physics_usec - started
				columns["physics_last_usec"] = _phase_last_physics_usec - started
			else: _issue("phase_physics_marker_order_invalid")
		elif _phase_first_physics_usec != 0 or _phase_last_physics_usec != 0:
			_issue("phase_zero_count_has_physics_markers")
		if _phase_physics_count != physics_frame - _phase_previous_physics_frame:
			_issue("phase_signal_count_differs_from_original_counter")
	columns.merge(_phase_node_columns(columns, physics_frame))
	_phase_first_physics_usec = 0
	_phase_last_physics_usec = 0
	_phase_physics_count = 0
	_phase_process_usec = 0
	_phase_process_frame = -1
	_phase_previous_physics_frame = physics_frame
	return columns

func _process(_delta: float) -> void:
	if not recording or finished: return
	var now: int = Time.get_ticks_usec()
	var window: Window = get_window()
	var size: Vector2i = DisplayServer.window_get_size()
	var focused: bool = DisplayServer.window_is_focused()
	var visible: bool = window.visible and DisplayServer.window_get_mode()!=DisplayServer.WINDOW_MODE_MINIMIZED
	var row: Dictionary = {"start_s":float(previous-started)/1000000.0,"end_s":float(now-started)/1000000.0,"usec":now-previous,"phase":stage,"region":session.region_id,"physics_frame":Engine.get_physics_frames(),"disable_3d":game_viewport.disable_3d,"diagnostic_only":not diagnostic_reasons.is_empty(),"process_ms":Performance.get_monitor(Performance.TIME_PROCESS)*1000.0,"physics_ms":Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS)*1000.0,"draw_calls":Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),"primitives":Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME),"physics_bodies":Performance.get_monitor(Performance.PHYSICS_3D_ACTIVE_OBJECTS),"collision_pairs":Performance.get_monitor(Performance.PHYSICS_3D_COLLISION_PAIRS),"focused":focused,"visible":visible,"window_w":size.x,"window_h":size.y}
	row.merge(_phase_columns(now, int(row.physics_frame)))
	frames.append(row)
	previous = now
	if stage.begins_with("measure:"):
		if game_viewport.disable_3d!=disable_3d_diagnostic: _issue("render_diagnostic_flag_mismatch:"+session.region_id)
		if not focused: _issue("window_focus_lost:"+session.region_id)
		if not visible: _issue("window_hidden_or_minimized:"+session.region_id)
		if size!=SIZE or get_viewport().size!=SIZE: _issue("window_or_viewport_changed:"+session.region_id)
		if _quality()!=expected_quality: _issue("render_quality_or_vsync_changed:"+session.region_id)
		if Engine.max_fps!=0 or Engine.time_scale!=1.0 or Engine.physics_ticks_per_second!=60 or session.simulation_paused or get_tree().paused or not RenderingServer.is_render_loop_enabled(): _issue("timing_or_pause_changed:"+session.region_id)
	var elapsed: float = _elapsed()
	if elapsed>=next_resource:
		resources.append({"seconds":elapsed,"phase":stage,"region":session.region_id,"engine_static_bytes":OS.get_static_memory_usage(),"engine_static_peak_bytes":OS.get_static_memory_peak_usage(),"render_video_bytes":Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED),"render_texture_bytes":Performance.get_monitor(Performance.RENDER_TEXTURE_MEM_USED),"render_buffer_bytes":Performance.get_monitor(Performance.RENDER_BUFFER_MEM_USED),"nodes":Performance.get_monitor(Performance.OBJECT_NODE_COUNT),"resources":Performance.get_monitor(Performance.OBJECT_RESOURCE_COUNT),"orphans":Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT),"audio":session.audio.diagnostics()})
		next_resource = floor(elapsed)+1.0
	sample_ready.emit()

func _ready_region(id: String) -> bool:
	# Only the observer's wall wait changes. The original assembly alignment,
	# support and facility readiness conditions remain mandatory.
	var deadline: int = Time.get_ticks_usec()+(50000000 if id=="I2" else 5000000)
	while Time.get_ticks_usec()<deadline:
		await _next()
		if finished: return false
		var ready: bool = session.active and session._facilities_ready()
		if id=="I2": ready = ready and session.canal_runtime_enabled and session.canal!=null and session.canal.ready
		if id=="I3": ready = ready and session.thermal_cargo.enabled and session.thermal_cargo.supported() and session.thermal_cargo.module.ready
		if ready: return _check(true,"ordinary default modules ready: "+id)
	return _check(false,"bounded ordinary default module readiness: "+id,_diagnostics())

func _try_cargo() -> Dictionary:
	stage = "setup_native_G:I3"
	var result := {"kind":"idle_baseline","attempted":"one clear initial QA observer pose; original G and automatic physical departure","setup_pose_fixture":[-10,4.1,18],"attached":false}
	if not _initial_pose(Vector3(-10,4.1,18)): result["reason"]="initial_aircraft_clearance_blocked"; return result
	session.interface.clear_dialogue()
	session.network.send_action("lock",{"target_id":CARGO})
	var key := InputEventKey.new()
	key.physical_keycode=KEY_G; key.keycode=KEY_G; key.pressed=true
	session._unhandled_input(key)
	var deadline: int = Time.get_ticks_usec()+8000000
	while Time.get_ticks_usec()<deadline:
		await _next()
		if finished: return result
		if session.players[1].cargo_items.has(CARGO) and session.thermal_cargo.module.status().assist.is_empty():
			var item: Dictionary = session.players[1].cargo_items[CARGO]
			result["attached"] = item.joint is PinJoint3D and item.joint.get_rid().is_valid() and session.players[1].cargo_kg==2.0
			if result.attached:
				flight.pilot = Pilot.new()
				if flight.pilot.bind(session.players[1]) and flight.pilot.go_to(Vector3(-8.2,5.2,18),1):
					result["kind"]="original_G_2kg_Pilot_commands"
					flight.active = true
			break
	result["status"] = session.thermal_cargo.module.status()
	return result

func _try_light() -> Dictionary:
	stage = "setup_original_light:F4"
	var result := {"kind":"idle_baseline","boss_active":session.campaign.active(),"reason":"Empty QA has no prior Story plan; no fake prefix is imported.","setup_pose_fixture":[9.5,15.4,6],"abilities":[]}
	if not _initial_pose(Vector3(9.5,15.4,6)): result["setup_blocked"]=true; return result
	for ability: Dictionary in [{"target":"F4:living_emitter","ability":"light","mode":"on"},{"target":"F4:living_support","ability":"growth","mode":""},{"target":"F4:living_support","ability":"growth","mode":""},{"target":"F4:living_support","ability":"growth","mode":""}]:
		for unused in 40:
			if float(session.cooldowns.get(1,0))<=0: break
			await _next()
			if finished: return result
		var before: int = session.stats.abilities
		session._action_received(1,"ability",{"target_id":ability.target,"ability":ability.ability,"mode":ability.mode})
		await _next()
		if finished: return result
		var accepted: bool = session.stats.abilities==before+1
		result.abilities.append({"ability":ability.ability,"accepted":accepted,"message":session.interface.message.text})
		if not accepted: break
	result["view"] = session.campaign.mechanisms.view_state()
	if result.view.get("beam_valid",false): result.kind="actual_original_optical_baseline"
	return result

func _initial_pose(at: Vector3) -> bool:
	var body: FlightBodyV2 = session.players[1]
	var envelope := body.get_node("Envelope") as CollisionShape3D
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape=envelope.shape; query.transform=Transform3D(Basis.IDENTITY,at)*envelope.transform
	query.collision_mask=1|2|4|8|32; query.exclude=[body.get_rid()]
	if not Regions.contains(session.region_id,at) or not session.world.get_world_3d().direct_space_state.intersect_shape(query,1).is_empty(): return false
	# Disclosed once before each affected area's warmup, never during measurement.
	body.global_transform=Transform3D(Basis.IDENTITY,at)
	body.force_update_transform()
	PhysicsServer3D.body_set_state(body.get_rid(),PhysicsServer3D.BODY_STATE_TRANSFORM,body.global_transform)
	body.linear_velocity=Vector3.ZERO; body.angular_velocity=Vector3.ZERO; body.hold_height=at.y; body.safe_position=at
	return true

func _measure(id: String,setup: Dictionary) -> void:
	var body: FlightBodyV2 = session.players[1]
	var first: int = frames.size()
	var at_start: int = Time.get_ticks_usec()
	var physics_start: int = Engine.get_physics_frames()
	var old_position: Vector3 = body.global_position
	var distance := 0.0
	var carry_frames := 0
	var boss_frames := 0
	var optical_frames := 0
	var waypoints := 0
	var native_start: Dictionary = render_native_start if disable_3d_diagnostic else {}
	var live_start: Dictionary = render_live_start if disable_3d_diagnostic else {}
	session.qa_cpu_totals.clear()
	session.qa_store_commit_wall.clear()
	session.qa_cpu_enabled=collect_cpu
	if collect_cpu and id=="I2": session.trial.module.station.qa_cpu_owner=weakref(session)
	stage = "measure:"+id
	while Time.get_ticks_usec()-at_start<int(float(target_seconds[id])*1000000.0):
		await _next()
		if finished: return
		distance += body.global_position.distance_to(old_position)
		old_position = body.global_position
		if body.cargo_items.has(CARGO) and body.cargo_items[CARGO].joint is PinJoint3D and body.cargo_items[CARGO].joint.get_rid().is_valid(): carry_frames += 1
		if session.campaign.active(): boss_frames += 1
		if session.campaign.mechanisms!=null and session.campaign.mechanisms.view_state().get("beam_valid",false): optical_frames += 1
		if id=="I3" and flight.active and flight.pilot.state=="arrived":
			waypoints += 1
			flight.pilot.go_to(Vector3(-8.2,5.2,22 if waypoints%2==1 else 18),waypoints+1)
	var elapsed: float = float(Time.get_ticks_usec()-at_start)/1000000.0
	session.qa_cpu_enabled=false
	if id=="I2": session.trial.module.station.qa_cpu_owner=null
	var native_end: Dictionary = _native_identity() if disable_3d_diagnostic else {}
	if disable_3d_diagnostic:
		_check(native_end==native_start,"same native world/space/body identity during diagnostic ROI: "+id,{"before":native_start,"after":native_end})
		_check(Engine.get_physics_frames()>physics_start and session.active and session._facilities_ready(),"original physics advances and facilities remain ready: "+id,_diagnostics())
	var selected: Array = frames.slice(first)
	var summary: Dictionary = _statistics(selected)
	var measured_cpu: Dictionary=session.qa_cpu_totals.duplicate(true) if collect_cpu else {}
	results.append({"region":id,"setup":setup,"target_seconds":target_seconds[id],"seconds":elapsed,"frames":selected.size(),"statistics":summary,"physics_frames":Engine.get_physics_frames()-physics_start,"physics_seconds_per_wall_second":float(Engine.get_physics_frames()-physics_start)/60.0/elapsed,"actual_distance_m":distance,"valid_joint_carry_frames":carry_frames,"actual_Pilot_waypoints":waypoints,"pilot":flight.pilot.report() if id=="I3" and flight.pilot!=null else {},"active_boss_frames":boss_frames,"actual_optical_frames":optical_frames,"scope":"Original real 2kg flight only if carry/distance/waypoint evidence is present; F4 Boss load is absent unless active_boss_frames > 0. Idle/optical baseline does not satisfy combat-load acceptance."})
	results.back()["render_diagnostic"]={"diagnostic_only":disable_3d_diagnostic or mobile_renderer_diagnostic,"renderer_mobile_diagnostic":mobile_renderer_diagnostic,"disable_3d":game_viewport.disable_3d,"original_disable_3d":original_disable_3d,"native_start":native_start,"native_end":native_end,"live_start":live_start,"live_end":_diagnostics() if disable_3d_diagnostic else {},"render_counts":_render_counts(selected),"scope":"Explicit presentation-only diagnostic if requested; native simulation, facilities, optics, cargo, input, HUD and VSync remain ordinary. No normal-performance acceptance from disabled 3D or an alternate renderer."}
	results.back()["cpu_scopes"]={"enabled":collect_cpu,"inclusive_totals":measured_cpu,"scope":"Optional same-window manual CPU scopes incur observer overhead; nested groups overlap and must not be summed. Timing only, no alternate simulation or physics gates."}
	results.back()["cpu_scopes"]["store_commit_wall"]={"enabled":collect_cpu,"max_samples":8,"phase_schema":1,"time_origin_usec":started,
		"samples":session.qa_store_commit_wall.duplicate(true) if collect_cpu else [],
		"scope":"Original synchronous store.commit call only, excluding Session capture/transaction preparation and post-call handling; includes original Store validation/candidate/serialization/IO/cleanup. Absolute Time.get_ticks_usec; subtract time_origin_usec for original CSV alignment. Last8 per ROI, not all calls if clipped. Wall interval includes waits/preemption, not CPU/IO self. Nested store_phases are scalar diagnostics: outer phases are disjoint; ready/tmp/retire read subphases are INCLUDED in their parents and must not be added. rename includes publish guards. Read counts are attempted stages. Existing --cpu scope overhead is diagnostic only."}
	stage = "after_measure:"+id

func _native_identity() -> Dictionary:
	var body_rids: Array[int] = []
	var pending: Array[Node] = [session.world]
	while not pending.is_empty():
		var item: Node = pending.pop_back()
		var native_body := item as PhysicsBody3D
		if native_body!=null: body_rids.append(native_body.get_rid().get_id())
		for child: Node in item.get_children(): pending.append(child)
	body_rids.sort()
	var actors := {}
	for peer in session.players:
		var body: FlightBodyV2 = session.players[peer]
		actors[str(peer)]={"node":body.get_instance_id(),"rid":body.get_rid().get_id(),"space":PhysicsServer3D.body_get_space(body.get_rid()).get_id(),"cargo_kg":body.cargo_kg}
	return {"region":session.region_id,"world_node":session.world.get_instance_id(),"world3d":session.world.get_world_3d().get_instance_id(),"space":session.world.get_world_3d().space.get_id(),"game_viewport":game_viewport.get_instance_id(),"physics_owner":session._region_space.get_instance_id(),"physics_viewport":session._region_space.viewport.get_instance_id(),"owner_update_mode":session._region_space.viewport.render_target_update_mode,"owner_status":session._region_space.status(),"body_rids":body_rids,"players":actors}

func _render_counts(rows: Array) -> Dictionary:
	if rows.is_empty(): return {}
	var draws: Array = rows.map(func(row: Dictionary): return float(row.draw_calls))
	var primitives: Array = rows.map(func(row: Dictionary): return float(row.primitives))
	return {"draw_calls":{"min":draws.min(),"max":draws.max(),"first":draws.front(),"last":draws.back()},"primitives":{"min":primitives.min(),"max":primitives.max(),"first":primitives.front(),"last":primitives.back()},"scope":"Observed native counts; disabled 3D should approach the actual 2D baseline. No invented count threshold."}

func _restore_rendering() -> void:
	if render_override_applied and is_instance_valid(game_viewport):
		game_viewport.disable_3d = original_disable_3d
		render_override_applied = false

func _save(label: String) -> bool:
	var deadline: int = Time.get_ticks_usec()+4000000
	while session.environment_save_gate.pending() and Time.get_ticks_usec()<deadline:
		await _next()
		if finished: return false
	var before: int = callbacks.size()
	var requested: Dictionary = session.request_environment_save(func(row: Dictionary): callbacks.append({"region":label,"result":row.duplicate(true)}))
	if not requested.get("ok",false): return _check(false,"original SaveGate accepts "+label,requested)
	while callbacks.size()==before and Time.get_ticks_usec()<deadline:
		await _next()
		if finished: return false
	return _check(callbacks.size()==before+1 and callbacks[before].result.get("ok",false) and callbacks[before].result.get("completed",false),"original SaveGate completes "+label,{"callbacks":callbacks.slice(before),"commit":session.last_commit_result})

func _statistics(rows: Array) -> Dictionary:
	if rows.is_empty(): return {"frames":0}
	var ordered: Array[float] = []
	var total := 0.0
	var counts := {"gt_33_3ms":0,"gt_50ms":0,"gt_100ms":0}
	var streak := 0
	var streak_ms := 0.0
	var longest := 0
	var longest_ms := 0.0
	var reported_physics_max := 0.0
	for row: Dictionary in rows:
		var ms: float = float(row.usec)*.001
		ordered.append(ms); total+=ms
		reported_physics_max=maxf(reported_physics_max,float(row.physics_ms))
		if ms>33.3:
			counts.gt_33_3ms+=1; streak+=1; streak_ms+=ms
			longest=maxi(longest,streak); longest_ms=maxf(longest_ms,streak_ms)
		else: streak=0; streak_ms=0.0
		if ms>50: counts.gt_50ms+=1
		if ms>100: counts.gt_100ms+=1
	ordered.sort()
	return {"frames":rows.size(),"wall_seconds":total*.001,"mean_fps":float(rows.size())*1000.0/total,"p50_ms":ordered[clampi(int(ceil(ordered.size()*.5))-1,0,ordered.size()-1)],"p95_ms":ordered[clampi(int(ceil(ordered.size()*.95))-1,0,ordered.size()-1)],"p99_ms":ordered[clampi(int(ceil(ordered.size()*.99))-1,0,ordered.size()-1)],"max_ms":ordered.back(),"counts":counts,"longest_gt_33_3ms_frames":longest,"longest_gt_33_3ms_duration_ms":longest_ms,"reported_physics_monitor_max_ms":reported_physics_max,"physical_tick_budget_ms":1000.0/60.0}

func _quality() -> Dictionary:
	return {"vsync":DisplayServer.window_get_vsync_mode(),"window_mode":DisplayServer.window_get_mode(),"msaa":get_viewport().msaa_3d,"scaling":get_viewport().scaling_3d_scale,"camera_target_size":session.flight_camera.target_size}

func _environment() -> Dictionary:
	var environment: Dictionary = {"editor_binary":OS.has_feature("editor"),"debug_build":OS.is_debug_build(),"godot":Engine.get_version_info(),"executable":OS.get_executable_path(),"executable_sha256":FileAccess.get_sha256(OS.get_executable_path()),"runtime_cwd":DirAccess.open(".").get_current_dir(),"profile":profile,"cpu":OS.get_processor_name(),"logical_processors":OS.get_processor_count(),"display":DisplayServer.get_name(),"renderer":RenderingServer.get_current_rendering_method(),"driver":RenderingServer.get_current_rendering_driver_name(),"device":RenderingServer.get_video_adapter_name(),"vendor":RenderingServer.get_video_adapter_vendor(),"api_version":RenderingServer.get_video_adapter_api_version(),"screen_refresh_hz":DisplayServer.screen_get_refresh_rate(),"window_size":str(DisplayServer.window_get_size()),"viewport_size":str(get_viewport().size),"max_fps":Engine.max_fps,"physics_ticks_per_second":Engine.physics_ticks_per_second,"time_scale":Engine.time_scale,"renderer_settings":{"depth_prepass":ProjectSettings.get_setting_with_override("rendering/driver/depth_prepass/enable"),"force_vertex_shading":ProjectSettings.get_setting_with_override("rendering/shading/overrides/force_vertex_shading")},"quality":_quality(),"args":OS.get_cmdline_args(),"monitor_scope":"Godot 4.7.2 TIME_PROCESS/TIME_PHYSICS_PROCESS cache the preceding approximately one-second interval maxima, not per-frame means; repeated CSV averages are not average CPU costs. Some monitors are unavailable in release. These are not GPU timestamps. Wall process-frame intervals include CPU, rendering, scheduling and VSync. Memory is engine/render estimates, not OS working set or physical VRAM."}
	environment["renderer_mobile_diagnostic"] = mobile_renderer_diagnostic
	environment["project_renderer_default"] = str(ProjectSettings.get_setting_with_override("rendering/renderer/rendering_method"))
	environment["project_rd_driver_default"] = str(ProjectSettings.get_setting_with_override("rendering/rendering_device/driver"))
	# Three adjacent reads after the slow environment queries, never per frame.
	var elapsed_before := _elapsed()
	var unix_seconds := Time.get_unix_time_from_system()
	var elapsed_after := _elapsed()
	environment["time_alignment"] = {"elapsed_before":elapsed_before,"unix_seconds":unix_seconds,"elapsed_after":elapsed_after}
	return environment

func _diagnostics() -> Dictionary:
	return {"region":session.region_id,"active":session.active,"message":session.interface.message.text,"world_errors":session.world.build_errors if is_instance_valid(session.world) else [],"facilities_ready":session._facilities_ready(),"canal_default_enabled":session.canal_runtime_enabled,"canal":session.canal.status() if session.canal!=null else {},"thermal_default_enabled":session.thermal_cargo.enabled,"thermal":session.thermal_cargo.module.status() if session.thermal_cargo.module!=null else {},"commit":session.last_commit_result}

func _next() -> void:
	await sample_ready

func _elapsed() -> float:
	return float(Time.get_ticks_usec()-started)/1000000.0

func _issue(value: String) -> void:
	if value not in issues: issues.append(value)

func _check(ok: bool,label: String,actual: Variant=null) -> bool:
	checks.append({"passed":ok,"label":label,"actual":actual})
	return ok

func _write_json(name: String,value: Dictionary) -> bool:
	var file := FileAccess.open(output.path_join(name),FileAccess.WRITE)
	if file==null: return false
	file.store_string(JSON.stringify(value,"\t")); file.flush()
	return file.get_error()==OK

func _finish() -> void:
	if finished: return
	finished=true; recording=false
	_restore_rendering()
	_check(is_instance_valid(game_viewport) and not game_viewport.disable_3d,"ordinary game rendering restored at teardown")
	if is_instance_valid(session): session.qa_cpu_enabled=false
	if flight!=null: flight.active=false
	var csv := FileAccess.open(output.path_join("frames.csv"),FileAccess.WRITE)
	var csv_ok: bool = csv!=null and not frames.is_empty()
	if csv_ok:
		var keys: Array = frames[0].keys()
		csv.store_csv_line(PackedStringArray(keys))
		for row: Dictionary in frames:
			var values := PackedStringArray()
			for key in keys: values.append(str(row[key]))
			csv.store_csv_line(values)
		csv.flush(); csv_ok=csv.get_error()==OK
	var failures: Array = checks.filter(func(row: Dictionary): return not row.passed)
	var valid: bool = results.size()==3 and issues.is_empty() and failures.is_empty() and logger.errors.is_empty() and csv_ok
	var diagnostic_only: bool = not diagnostic_reasons.is_empty()
	var frame_target_met: bool = results.size()==3
	for result: Dictionary in results: frame_target_met=frame_target_met and float(result.statistics.get("p95_ms",INF))<=33.3
	var target_met: bool = not diagnostic_only and frame_target_met
	var report := {"diagnostic_only":diagnostic_only,"renderer_mobile_diagnostic":mobile_renderer_diagnostic,"valid_measurement":valid and not diagnostic_only,"valid_diagnostic_measurement":valid and diagnostic_only,"diagnostic_complete":false,"diagnostic_frame_target_met":diagnostic_only and valid and frame_target_met,"screening_target_met":target_met,"seconds_per_region":seconds,"elapsed_seconds":_elapsed(),"environment":_environment(),"regions":results,"checks":checks,"failures":failures,"issues":issues,"engine_errors":logger.errors,"resource_samples":resources,"events":events,"save_callbacks":callbacks,"raw_frames":frames.size(),"csv_ok":csv_ok,"diagnostics":_diagnostics(),"scope":"Short current exported EXE I2/I3/F4 foreground screening only. No hidden window or affinity override. Actual default modules and ordinary ticks/Session remain running. Single disclosed setup aircraft observation poses only before affected-region warmup; original G/ability/Pilot APIs only, no scene device/HP/Rules/Story-prefix/environment-fact edits. Genuine load/setup/warmup/measurement/save phase intervals remain in raw CSV; steady summaries include complete measurement intervals including the last overshoot. I3 load and F4 optics/Boss coverage are actual recorded evidence, otherwise explicitly idle baseline. Focus/visible/window/quality checked every measured frame; arbitrary occlusion by a non-focus-stealing overlay cannot be proven absent. Sampling overhead is included; no CSV/report disk writes or screenshots during measured windows. Exact original SaveGate/readback retained. P95 target is a diagnostic threshold, never five-minute/30-minute, full combat, LAN, controller/human-comfort/fun or final delivery acceptance."}
	report["diagnostic_reasons"]=diagnostic_reasons.duplicate()
	report["long_i2"]=long_i2; report["target_seconds"]=target_seconds; report["observer_watchdog_seconds"]=watchdog_seconds
	report["frame_phase_sampling"] = {"version":1,"time_base":"integer usec since the same observer started as original start_s/end_s","first_row":"all four markers zero; partial initial iteration excluded from decomposition only","zero_physics":"count/first/last zero; not a zero CPU-cost claim","invalid_markers":"zero sentinel plus phase_* issue; original wall frame retained","scope":"physics signal to process signal, process signal to observer, and remaining wall interval; no CPU-self/GPU attribution"}
	report["physics_node_boundary"] = {"version":1,"priority":PHYSICS_BOUNDARY_PRIORITY,"span":"sum of paired late-node-entry minus original physics-signal timestamps, integer usec per original raw row","count":"one pair per original physics frame; must equal physics_signal_count","first_row":"both new fields zero; no pairing or missing-prefix issue until the first original row has been appended","invalid":"both new fields zero plus phase_node_* issue; all original rows and counters retained","ordering":"read-only default-main-group audit before each original warmup; frozen current closure only, not an automatic guarantee for future dynamic group/priority mutations","scope":"B and original P minus B are wall intervals, including scripts/flushes/waits/preemption; neither is CPU-self, native-self or GPU time"}
	if collect_cpu: report.scope = "CPU instrumentation diagnostic with existing scope overhead; not normal-performance acceptance. " + str(report.scope)
	if long_i2: report.scope = str(report.scope).replace("Short current exported EXE I2/I3/F4 foreground screening only.","One continuous 300-second I2 idle baseline followed by I3/F4 12-second checks.").replace("never five-minute/30-minute", "never full-Boss five-minute/30-minute")
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
	report["qa_audio_shutdown"]=drained
	report["diagnostic_complete"]=diagnostic_only and valid and drained.ready
	var written: bool = _write_json("report.json",report)
	print("CAMPAIGN_PERFORMANCE_RESULT "+JSON.stringify({"diagnostic_only":diagnostic_only,"diagnostic_reasons":diagnostic_reasons,"renderer_mobile_diagnostic":mobile_renderer_diagnostic,"valid_measurement":report.valid_measurement,"valid_diagnostic_measurement":report.valid_diagnostic_measurement,"diagnostic_complete":report.diagnostic_complete,"screening_target_met":target_met,"regions":results,"issues":issues,"failures":failures,"engine_errors":logger.errors,"qa_audio_shutdown":drained}))
	get_tree().quit(0 if valid and written and (target_met or diagnostic_only) and drained.ready else 1)
