extends SceneTree

var session: GameSessionV2
var output = "res://artifacts/v2/render"
var results: Array = []
var mode = "matrix"
var duration_s = 1800.0
var phase_seconds = 225.0
var started = 0
var current_samples: Array[float] = []
var previous_us = 0
var failures: Array = []
var soak_waypoint = 0
var soak_cargo_kg = 0.0
var source_snapshot: Dictionary = {}
var flight_started_ms = 0
var soak_events: Dictionary = {}
var soak_effects: Dictionary = {}
const SOAK_ROLES = ["scout","scout","harasser","harasser","suppressor","suppressor","support","support"]
const DRAW_TIMEOUT_US = 10000000
var gpu_stress = false
var stress_override = ""
var phase_seconds_explicit = false
var drawing_enabled = false
var draw_queued = false
var draw_pending: Dictionary = {}
var last_submit_process = -1
var last_submit_us = 0
var last_completed_us = 0
var submitted_draws = 0
var completed_draws = 0
var pre_draws = 0
var unexpected_post_draws = 0
var duplicate_process_draws = 0
var skipped_pending_processes = 0
var measured = false
var sample_epoch = 0
var sample_submitted = 0
var sample_completed = 0
var sample_first_draw = 0
var sample_last_draw = 0
var sample_interval_us = 0
var sample_draw_ms: Array[float] = []
var sample_frame_step_ms: Array[float] = []
var sample_gpu_ms: Array[float] = []
var sample_cpu_ms: Array[float] = []
var sample_draw_calls: Array[float] = []
var sample_primitives: Array[float] = []
var invalid_draw_samples = 0
var last_draw_stats: Dictionary = {}
var measured_soak_seconds = 0.0
var finished_soak_phases = 0
var source_fingerprint = ""
var old_render_loop = true
var old_low_processor_usage = false

func _encounter_position() -> Vector3:
	var point: Vector3 = session.living.field.event_definition().center+Vector3(0,4,0)
	if session.region_id=="R2": point.y=session.world.surface_height(point)+2.8
	return point

func _initialize() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--qa-mode="): mode = argument.trim_prefix("--qa-mode=")
		if argument.begins_with("--qa-duration="): duration_s = float(argument.trim_prefix("--qa-duration="))
		if argument.begins_with("--qa-phase-seconds="):
			phase_seconds = maxf(1.0,float(argument.trim_prefix("--qa-phase-seconds=")))
			phase_seconds_explicit = true
		if argument.begins_with("--qa-output="): output = argument.trim_prefix("--qa-output=")
		if argument.begins_with("--qa-gpu-stress="): stress_override = argument.trim_prefix("--qa-gpu-stress=").to_lower()
	gpu_stress = mode in ["soak","profile22"] if stress_override.is_empty() else stress_override == "true"
	if not phase_seconds_explicit: phase_seconds = maxf(1.0,duration_s/8.0)
	call_deferred("_run")

func _run() -> void:
	if DisplayServer.get_name() == "headless": push_error("GPU QA must use a real renderer"); quit(2); return
	if not Array(OS.get_cmdline_user_args()).any(func(a): return str(a).begins_with("--v2-qa=")): push_error("An isolated QA profile is mandatory"); quit(2); return
	if mode not in ["night22","profile22","review22","matrix","autoflight","soak"]: push_error("Unknown GPU QA mode"); quit(2); return
	if duration_s<=0 or not is_finite(duration_s): push_error("QA duration must be finite and positive"); quit(2); return
	if not is_finite(phase_seconds): push_error("QA phase duration must be finite"); quit(2); return
	if mode=="soak" and absf(phase_seconds*8.0-duration_s)>.01: push_error("Soak requires exactly eight phases: phase seconds * 8 must equal duration"); quit(2); return
	if stress_override not in ["","true","false"]: push_error("qa-gpu-stress must be true or false"); quit(2); return
	if mode=="soak" and not gpu_stress: push_error("Soak requires qa-gpu-stress=true; native window measurements use other modes"); quit(2); return
	if gpu_stress and RenderingServer.get_current_rendering_method()!="gl_compatibility": push_error("Synchronized no-swap stress is audited for desktop GL Compatibility; use the project renderer"); quit(2); return
	DirAccess.make_dir_recursive_absolute(output)
	source_snapshot = _source_hashes()
	source_fingerprint = JSON.stringify(source_snapshot).sha256_text()
	await _start_draw_tracking()
	session = GameSessionV2.new()
	root.add_child(session)
	for i in range(5): await process_frame
	session.repository.commit({"id":"qa:unlock", "parts_delta":10000,"append":{"campaign.completed_missions":session.content.missions.map(func(m): return m.id),"owned_airframes":CatalogV2.airframes().keys(),"owned_modules":CatalogV2.modules().keys()}})
	session.input.test_enabled = true
	started = Time.get_ticks_msec()
	if mode == "night22": await _night22()
	elif mode == "profile22": await _profile22()
	elif mode == "review22": await _review22()
	elif mode == "matrix": await _matrix()
	elif mode == "autoflight": await _autoflight()
	else: await _soak()
	measured = false
	await _stop_draw_tracking()
	var source_after = _source_hashes()
	if source_after!=source_snapshot: _fail_once("Source files changed during GPU verification")
	if gpu_stress and (submitted_draws!=completed_draws or completed_draws==0): _fail_once("Submitted/completed GPU draw count mismatch")
	if gpu_stress and pre_draws!=completed_draws: _fail_once("Pre/post GPU draw count mismatch")
	if unexpected_post_draws>0 or duplicate_process_draws>0: _fail_once("Unexpected or duplicate GPU draw detected")
	var performance_target_issues: Array = []
	for result in results:
		if not result.has("completed_draws_per_second") or str(result.label).ends_with("_warmup"): continue
		if float(result.completed_draws_per_second)<60.0 or float(result.p95_ms)>20.0: performance_target_issues.append(result.label)
	var formal_requested = (mode=="soak" and duration_s>=1800.0) or _native_long_run()
	if formal_requested and (measured_soak_seconds<1800.0 or finished_soak_phases!=8): _fail_once("Formal soak did not complete 1800 measured seconds across all eight phases")
	var formal_pass = formal_requested and (gpu_stress or _native_long_run()) and measured_soak_seconds>=1800.0 and finished_soak_phases==8 and failures.is_empty()
	var report = {"mode":mode,"renderer":RenderingServer.get_video_adapter_name(),"driver":RenderingServer.get_current_rendering_method(),"engine":Engine.get_version_info(),"source_snapshot":source_snapshot,"source_sha256":source_fingerprint,"source_snapshot_after":source_after,"content_sha256":session.content.get("_source_sha256",""),"elapsed_wall_s":(Time.get_ticks_msec()-started)/1000.0,"requested_duration_s":duration_s,"measured_soak_s":measured_soak_seconds,"completed_soak_phases":finished_soak_phases,"formal_soak_kind":"native_window_eight_phase" if _native_long_run() else "synchronized_gpu_stress", "formal_soak_requested":formal_requested,"formal_soak_pass":formal_pass,"formal_soak_status":"passed" if formal_pass else ("failed" if formal_requested else "not_run_short_functional_or_other_mode"),"results":results,"failures":failures,"draw_accounting":_draw_accounting(),"performance_goal":{"completed_draws_per_second":60,"p95_ms":20,"scope":_measurement_scope(),"quality":session.repository.data.settings.get("quality","low"),"window_vsync_mode_not_used_by_no_swap_draw":DisplayServer.window_get_vsync_mode(),"engine_max_fps":Engine.max_fps,"engine_time_scale":Engine.time_scale},"performance_target_issues":performance_target_issues,"evidence_scope":_measurement_scope()+" Synthetic flight and eight-enemy pressure fixtures are not natural encounter, phone/controller, novice or comfort evidence. Numeric targets are reported separately from stability; formal soak pass does not imply targets passed."}
	var file = FileAccess.open(output+"/"+mode+"_report.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(report,"\t")); file.close()
	# The full report, including raw intervals, stays in the JSON artifact.
	print("V2_RENDER_REPORT ",JSON.stringify({"report":output+"/"+mode+"_report.json","source_sha256":source_fingerprint,"requested_duration_s":duration_s,"measured_soak_s":measured_soak_seconds,"completed_soak_phases":finished_soak_phases,"formal_soak_pass":formal_pass,"failures":failures,"performance_target_issues":performance_target_issues}))
	session.phone.stop_server()
	session.queue_free()
	for i in range(3): await process_frame
	quit(0 if failures.is_empty() else 1)

func _native_long_run() -> bool:
	return false

func _measurement_scope() -> String:
	return "Synchronized GPU stress: manual force_draw(false, real wall delta), no window swap; not normal presented-window FPS." if gpu_stress else "Native window rendering: intervals between actual frame_post_draw callbacks; process FPS is diagnostic only."

func _fail_once(message: String) -> void:
	if not failures.has(message): failures.append(message)

func _hash_directory(path: String, extensions: Array, hashes: Dictionary) -> void:
	var files = DirAccess.get_files_at(path)
	files.sort()
	for filename in files:
		if filename.get_extension() in extensions: hashes[path+"/"+filename] = FileAccess.get_sha256(path+"/"+filename)
	var directories = DirAccess.get_directories_at(path)
	directories.sort()
	for directory in directories: _hash_directory(path+"/"+directory,extensions,hashes)

func _source_hashes() -> Dictionary:
	var hashes: Dictionary = {}
	_hash_directory("res://scripts/v2",["gd"],hashes)
	_hash_directory("res://assets/shaders",["gdshader","gdshaderinc"],hashes)
	_hash_directory("res://assets/v2",["gdshader","gdshaderinc"],hashes)
	_hash_directory("res://data/worldui",["json"],hashes)
	_hash_directory("res://assets/models/worldui",["glb","json"],hashes)
	for path in ["res://scripts/visuals.gd","res://docs/v2/data/world_content.json"]:
		if FileAccess.file_exists(path): hashes[path]=FileAccess.get_sha256(path)
	for path in ["res://scripts_tools/qa_v2_render.gd","res://project.godot","res://assets/audio/v22/manifest.json","res://assets/audio/v22_combat/manifest.json","res://assets/models/v22_combat/manifest.json"]:
		if FileAccess.file_exists(path): hashes[path] = FileAccess.get_sha256(path)
	return hashes

func _start_draw_tracking() -> void:
	old_render_loop = RenderingServer.render_loop_enabled
	old_low_processor_usage = OS.low_processor_usage_mode
	if gpu_stress:
		RenderingServer.render_loop_enabled = false
		OS.low_processor_usage_mode = false
		RenderingServer.force_sync()
		# Drain any already queued automatic-render callbacks before accounting.
		for i in range(2): await process_frame
		_configure_stress_viewport()
	RenderingServer.viewport_set_measure_render_time(root.get_viewport_rid(),true)
	RenderingServer.frame_pre_draw.connect(_on_pre_draw)
	RenderingServer.frame_post_draw.connect(_on_post_draw)
	drawing_enabled = true
	if gpu_stress: process_frame.connect(_queue_draw)

func _configure_stress_viewport() -> void:
	var viewport = root.get_viewport_rid()
	# SceneTree's root viewport is already active; reactivation is an engine error.
	RenderingServer.viewport_set_update_mode(viewport,RenderingServer.VIEWPORT_UPDATE_ALWAYS)
	RenderingServer.viewport_set_render_direct_to_screen(viewport,false)

func _queue_draw() -> void:
	if not drawing_enabled: return
	if not draw_pending.is_empty():
		skipped_pending_processes += 1
		if Time.get_ticks_usec()-int(draw_pending.started_us)>DRAW_TIMEOUT_US: _fail_once("GPU completion signal timed out")
		return
	if draw_queued: return
	draw_queued = true
	# SceneTree.process_frame is before node processing. Deferred submission lets
	# scene/UI updates finish, and is the only force_draw call in this harness.
	call_deferred("_draw_once",Engine.get_process_frames())

func _draw_once(process_id: int) -> void:
	draw_queued = false
	if not drawing_enabled or not draw_pending.is_empty(): return
	if process_id==last_submit_process:
		duplicate_process_draws += 1
		return
	last_submit_process = process_id
	_configure_stress_viewport()
	var now = Time.get_ticks_usec()
	var real_delta = float(now-last_submit_us)/1000000.0 if last_submit_us>0 else maxf(root.get_process_delta_time(),0.000001)
	last_submit_us = now
	submitted_draws += 1
	draw_pending = {"number":submitted_draws,"process":process_id,"started_us":now,"epoch":sample_epoch if measured else -1,"frame_step_s":real_delta}
	if measured: sample_submitted += 1
	RenderingServer.force_draw(false,real_delta)
	# Queue synchronization also handles a threaded RenderingServer. In the
	# audited desktop GL driver end_frame(false) calls glFinish, not SwapBuffers.
	RenderingServer.force_sync()

func _on_pre_draw() -> void:
	if drawing_enabled or not draw_pending.is_empty(): pre_draws += 1

func _on_post_draw() -> void:
	if not drawing_enabled and draw_pending.is_empty(): return
	if gpu_stress and draw_pending.is_empty():
		unexpected_post_draws += 1
		return
	var now = Time.get_ticks_usec()
	var receipt = draw_pending.duplicate()
	draw_pending.clear()
	completed_draws += 1
	last_completed_us = now
	var viewport = root.get_viewport_rid()
	last_draw_stats = {"draw_calls":RenderingServer.viewport_get_render_info(viewport,RenderingServer.VIEWPORT_RENDER_INFO_TYPE_VISIBLE,RenderingServer.VIEWPORT_RENDER_INFO_DRAW_CALLS_IN_FRAME),"primitives":RenderingServer.viewport_get_render_info(viewport,RenderingServer.VIEWPORT_RENDER_INFO_TYPE_VISIBLE,RenderingServer.VIEWPORT_RENDER_INFO_PRIMITIVES_IN_FRAME),"gpu_ms":RenderingServer.viewport_get_measured_render_time_gpu(viewport),"render_cpu_ms":RenderingServer.viewport_get_measured_render_time_cpu(viewport)}
	if not measured or (gpu_stress and int(receipt.get("epoch",-1))!=sample_epoch): return
	sample_completed += 1
	if sample_first_draw==0: sample_first_draw = completed_draws
	sample_last_draw = completed_draws
	if previous_us>0:
		current_samples.append(float(now-previous_us)/1000.0)
		sample_interval_us += now-previous_us
	previous_us = now
	if gpu_stress:
		sample_draw_ms.append(float(now-int(receipt.started_us))/1000.0)
		sample_frame_step_ms.append(float(receipt.frame_step_s)*1000.0)
	# Driver timing queries may lag several draws; never claim exact attribution.
	if float(last_draw_stats.gpu_ms)>0: sample_gpu_ms.append(float(last_draw_stats.gpu_ms))
	if float(last_draw_stats.render_cpu_ms)>0: sample_cpu_ms.append(float(last_draw_stats.render_cpu_ms))
	sample_draw_calls.append(float(last_draw_stats.draw_calls))
	sample_primitives.append(float(last_draw_stats.primitives))
	if int(last_draw_stats.draw_calls)<=0 or int(last_draw_stats.primitives)<=0: invalid_draw_samples += 1

func _drain_draws() -> void:
	var deadline = Time.get_ticks_usec()+DRAW_TIMEOUT_US
	while not draw_pending.is_empty() or draw_queued:
		if Time.get_ticks_usec()>deadline:
			_fail_once("Pending GPU draw did not drain")
			return
		await process_frame

func _stop_draw_tracking() -> void:
	drawing_enabled = false
	if process_frame.is_connected(_queue_draw): process_frame.disconnect(_queue_draw)
	await _drain_draws()
	if RenderingServer.frame_pre_draw.is_connected(_on_pre_draw): RenderingServer.frame_pre_draw.disconnect(_on_pre_draw)
	if RenderingServer.frame_post_draw.is_connected(_on_post_draw): RenderingServer.frame_post_draw.disconnect(_on_post_draw)
	RenderingServer.render_loop_enabled = old_render_loop
	OS.low_processor_usage_mode = old_low_processor_usage

func _begin_samples() -> void:
	current_samples.clear(); previous_us = 0
	sample_draw_ms.clear(); sample_frame_step_ms.clear(); sample_gpu_ms.clear(); sample_cpu_ms.clear()
	sample_draw_calls.clear(); sample_primitives.clear()
	sample_submitted = 0; sample_completed = 0; invalid_draw_samples = 0
	sample_first_draw = 0; sample_last_draw = 0
	sample_interval_us = 0
	sample_epoch += 1
	measured = true

func _end_samples() -> void:
	# Stop scheduling before draining so each phase has balanced receipt counts.
	var was_drawing = drawing_enabled
	drawing_enabled = false
	await _drain_draws()
	measured = false
	drawing_enabled = was_drawing

func _draw_accounting() -> Dictionary:
	return {"gpu_stress":gpu_stress,"submitted":submitted_draws,"pre_draw":pre_draws,"completed":completed_draws,"unexpected_post_draw":unexpected_post_draws,"duplicate_process_draw":duplicate_process_draws,"skipped_process_while_pending":skipped_pending_processes,"pending":draw_pending.size(),"one_manual_draw_per_process_frame":gpu_stress,"engine_frames_drawn_not_used_for_manual_count":Engine.get_frames_drawn()}

func _set_flight(id: String, dark: bool, frame = "tr01", loaded = false) -> void:
	var load_begin = Time.get_ticks_usec()
	if session.flight_active: session.show_hangar()
	session.active_build = CatalogV2.default_build(frame)
	if loaded: session.active_build.slots.tool = "hook_base"
	session.save_build(session.active_build)
	session.night = dark
	session.launch_exploration(id)
	session.pilot.practice = true
	session.input.test_enabled = true
	paused = false
	session.pause_reasons.clear()
	session.pilot.global_position = session.world.poi_position(str(session.world.region.spawn_poi))+Vector3.UP*6.0
	session.pilot.hold_height = session.pilot.global_position.y
	session.world.update_stream(session.pilot.global_position,true)
	session._snap_camera()
	soak_cargo_kg = 0.0
	if loaded:
		var weight = float(session.pilot.stats.cargo_rating_kg)
		while weight > 0.1 and not CatalogV2.resolve_build(session.active_build,weight).valid: weight -= 0.1
		var cargo = RigidBody3D.new()
		var shape_node = CollisionShape3D.new()
		var shape = BoxShape3D.new()
		shape.size = Vector3(0.6,0.5,0.6)
		shape_node.shape = shape
		cargo.add_child(shape_node)
		GameVisuals.box(cargo,Vector3.ZERO,shape.size,Color("c4bb75"))
		session.play_root.add_child(cargo)
		cargo.global_position = session.pilot.global_position+Vector3.DOWN*1.2
		if session.pilot.attach_cargo(cargo,"soak_payload",weight): soak_cargo_kg = weight
		else: failures.append("Soak legal payload failed to attach")
	_begin_samples()
	flight_started_ms = Time.get_ticks_msec()
	results.append({"label":"scene_construction","region":id,"night":dark,"wall_ms":(Time.get_ticks_usec()-load_begin)/1000.0})

func _fly(delta: float, elapsed: float) -> void:
	if not is_instance_valid(session.pilot): return
	var angle = elapsed * 0.12
	session.input.test_frame = {"axes":{"left_x":sin(elapsed*.2)*.15,"left_y":0.0,"right_x":cos(angle)*.48,"right_y":sin(angle)*.48},"held":["fire"],"edges":[]}
	if mode == "soak":
		var alive = session.combat.alive_count()
		soak_effects["peak_live_enemies"] = maxi(int(soak_effects.get("peak_live_enemies",0)),alive)
		if alive>8: _fail_once("Eight-enemy pressure budget exceeded")
		var encounter: Vector3 = _encounter_position()
		var waypoints = [Vector3(90,18,90),Vector3(510,18,90),Vector3(510,18,410),Vector3(90,18,410),encounter]
		if session.pilot.global_position.distance_to(waypoints[soak_waypoint])<10: soak_waypoint = (soak_waypoint+1)%waypoints.size()
		# First 32 seconds exercise the actual warned local event, then streaming travel.
		var target: Vector3 = encounter if (Time.get_ticks_msec()-flight_started_ms)<32000 else waypoints[soak_waypoint]
		var offset: Vector3 = target-session.pilot.global_position
		var planar = Vector3(offset.x,0,offset.z)
		var direction = planar.normalized()*minf(.88,planar.length()*.6/maxf(1.0,float(session.pilot.stats.speed_mps)))
		var right = Basis(Vector3.UP,session.pilot.heading).x; right.y=0; right=right.normalized()
		var forward = -Basis(Vector3.UP,session.pilot.heading).z; forward.y=0; forward=forward.normalized()
		session.input.test_frame.axes = {"left_x":0.0,"left_y":clampf(offset.y*0.3,-0.8,0.8),"right_x":direction.dot(right),"right_y":direction.dot(forward)}
		var field: Dictionary = session.pilot.environment_sample
		soak_effects["max_wind_mps"]=maxf(float(soak_effects.get("max_wind_mps",0)),float(field.get("wind_strength",0)))
		soak_effects["max_vent_strength"]=maxf(float(soak_effects.get("max_vent_strength",0)),float(field.get("vent_strength",0)))
		soak_effects["min_nav_quality"]=minf(float(soak_effects.get("min_nav_quality",1)),float(field.get("nav_quality",1)))
		if float(field.get("event_strength",0))>.01:soak_effects["active_sample_frames"]=int(soak_effects.get("active_sample_frames",0))+1
		if is_instance_valid(session.pilot.cargo_body):
			var distance=session.pilot.global_position.distance_to(session.pilot.cargo_body.global_position)
			soak_effects["max_cargo_distance_m"]=maxf(float(soak_effects.get("max_cargo_distance_m",0)),distance)
			if not session.pilot.cargo_body.global_position.is_finite() or distance>8.0 or not is_instance_valid(session.pilot.cargo_joint):
				if not failures.has("Invalid cargo pose or joint"):failures.append("Invalid cargo pose or joint")
		elif soak_cargo_kg>0 and not failures.has("Soak payload disappeared"):failures.append("Soak payload disappeared")
	if not session.pilot.global_position.is_finite(): failures.append("Nonfinite flight position"); session.show_hangar()
	if delta>1.0: print("LONG_FRAME_MS ",delta*1000.0)

func _wait_rendered(seconds: float, moving = true) -> void:
	var begin = Time.get_ticks_msec()
	var prior = begin
	while Time.get_ticks_msec()-begin < seconds*1000:
		await process_frame
		var now = Time.get_ticks_msec()
		if moving: _fly((now-prior)/1000.0,(now-flight_started_ms)/1000.0)
		prior = now

func _sample_summary(label: String) -> Dictionary:
	var intervals = _statistics(current_samples)
	var loads: Array = session.world.chunk_load_ms.duplicate() if is_instance_valid(session.world) else []
	loads.sort()
	return {"label":label,"source_sha256":source_fingerprint,"measurement_scope":_measurement_scope(),"sample_count":current_samples.size(),"submitted_draws":sample_submitted if gpu_stress else null,"completed_draws":sample_completed,"first_completed_draw":sample_first_draw,"last_completed_draw":sample_last_draw,"balanced_draw_receipts":sample_submitted==sample_completed if gpu_stress else null,"measured_interval_s":float(intervals.total)/1000.0,"completed_draws_per_second":1000.0/float(intervals.mean) if float(intervals.mean)>0 else 0.0,"p95_ms":intervals.p95,"p99_ms":intervals.p99,"max_ms":intervals.maximum,"synchronized_draw_wall_ms":_statistics(sample_draw_ms),"submitted_real_frame_step_ms":_statistics(sample_frame_step_ms),"gpu_timestamp_ms_lagged":_statistics(sample_gpu_ms),"render_cpu_timestamp_ms_lagged":_statistics(sample_cpu_ms),"timestamp_scope":"Viewport driver queries may lag several completed frames; zero/unavailable readings are omitted, not reported as zero GPU work.","viewport_draw_calls":_statistics(sample_draw_calls),"viewport_primitives":_statistics(sample_primitives),"invalid_draw_samples":invalid_draw_samples,"process_fps_diagnostic_only":Engine.get_frames_per_second(),"memory_bytes":OS.get_static_memory_usage(),"allocator_peak_bytes":OS.get_static_memory_peak_usage(),"chunk_build_p95_ms":loads[mini(loads.size()-1,int(loads.size()*.95))] if not loads.is_empty() else 0.0,"chunk_build_max_ms":loads.back() if not loads.is_empty() else 0.0,"cpu_process_ms_sample":Performance.get_monitor(Performance.TIME_PROCESS)*1000.0,"cpu_physics_ms_sample":Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS)*1000.0}

func _statistics(values: Array) -> Dictionary:
	if values.is_empty(): return {"count":0,"total":0.0,"mean":0.0,"p95":0.0,"p99":0.0,"minimum":0.0,"maximum":0.0}
	var sorted = values.duplicate()
	sorted.sort()
	var total = 0.0
	for value in sorted: total += float(value)
	return {"count":sorted.size(),"total":total,"mean":total/sorted.size(),"p95":sorted[mini(sorted.size()-1,int(sorted.size()*.95))],"p99":sorted[mini(sorted.size()-1,int(sorted.size()*.99))],"minimum":sorted.front(),"maximum":sorted.back()}

func _capture(label: String) -> void:
	var was_measured = measured
	await _end_samples()
	# Wait for the regular scheduler/native loop to complete a fresh image. A
	# capture never submits another draw, so it cannot inflate timing or counters.
	var wanted_after = completed_draws
	var deadline = Time.get_ticks_usec()+DRAW_TIMEOUT_US
	while completed_draws<=wanted_after:
		if Time.get_ticks_usec()>deadline:
			_fail_once("No newly completed frame for capture: "+label)
			measured = was_measured
			return
		await process_frame
	var was_drawing = drawing_enabled
	drawing_enabled = false
	await _drain_draws()
	var image = root.get_texture().get_image()
	if image==null or image.is_empty():
		_fail_once("Empty GPU image: "+label)
		drawing_enabled = was_drawing; measured = was_measured; previous_us = 0
		return
	var path = output+"/"+label+".png"
	var saved = image.save_png(path)
	if saved!=OK: _fail_once("PNG write failed: "+label)
	var min_luma = 1.0
	var max_luma = 0.0
	var seen = {}
	for x in range(int(image.get_width()*.12),int(image.get_width()*.80),4):
		for y in range(int(image.get_height()*.25),int(image.get_height()*.73),4):
			var pixel = image.get_pixel(x,y)
			var luma = pixel.get_luminance()
			min_luma = minf(min_luma,luma); max_luma = maxf(max_luma,luma)
			seen[pixel.to_html(false)] = true
	var report = {"label":label,"kind":"completed_draw_capture","source_sha256":source_fingerprint,"png_path":path,"png_sha256":FileAccess.get_sha256(path) if saved==OK else "","pixel_bytes":image.get_data().size(),"completed_draw":completed_draws,"submitted_draw":submitted_draws if gpu_stress else null,"capture_submitted_extra_draw":false,"image_age_ms":float(Time.get_ticks_usec()-last_completed_us)/1000.0,"width":image.get_width(),"height":image.get_height(),"scene_luma_range":max_luma-min_luma,"sampled_unique_colors":seen.size(),"controls":_control_bounds(session.ui.root)}
	if max_luma-min_luma<0.05 or seen.size()<12: failures.append("Blank/low-detail rendered scene: "+label)
	results.append(report)
	drawing_enabled = was_drawing
	measured = was_measured
	previous_us = 0

func _control_bounds(node: Node) -> Array:
	var issues: Array = []
	if node is Label and node.is_visible_in_tree() and node.size.x>0 and node.size.y>0:
		if node.get_minimum_size().y>node.size.y+1: issues.append({"text":node.text,"kind":"label_height","actual":node.size.y,"needed":node.get_minimum_size().y})
	for child in node.get_children(): issues.append_array(_control_bounds(child))
	return issues

func _matrix() -> void:
	for id in CatalogV2.airframes():
		session.show_hangar()
		session.preview_frame(id)
		session.ui.show_hangar("机库")
		await _wait_rendered(0.5,false)
		await _capture("airframe_"+id)
	var cases = [[1280,720,1.0],[1920,1080,1.0],[2560,1440,1.0],[1680,720,1.0],[1024,768,1.0],[1280,720,1.25],[1280,720,1.5]]
	for item in cases:
		DisplayServer.window_set_size(Vector2i(item[0],item[1]))
		session.ui.apply_scale(item[2])
		session.show_hangar()
		await _wait_rendered(1,false)
		await _capture("hangar_%dx%d_%d" % [item[0],item[1],int(item[2]*100)])
		_set_flight("R1",false)
		await _wait_rendered(2)
		await _capture("flight_%dx%d_%d" % [item[0],item[1],int(item[2]*100)])
	DisplayServer.window_set_size(Vector2i(1280,720))
	session.ui.apply_scale(1.0)
	for region in ["R1","R2","R3","R4"]:
		for dark in [false,true]:
			for repetition in range(3):
				_set_flight(region,dark,"hx02" if dark else "tr01")
				var label = region+("_night" if dark else "_day")+"_repeat_"+str(repetition+1)
				await _wait_rendered(5)
				results.append(_sample_summary(label+"_warmup"))
				if repetition==0: await _capture(region+("_night" if dark else "_day"))
				_begin_samples()
				await _wait_rendered(10)
				await _end_samples()
				var sample = _sample_summary(label)
				_validate_sample(sample)
				results.append(sample)
				print("V2_MATRIX_SAMPLE ",JSON.stringify(sample))

func _profile22() -> void:
	DisplayServer.window_set_size(Vector2i(1440,810))
	_set_flight("R1",false,"tr01",true)
	session.pilot.global_position=Vector3(345,5.5,370)
	session.pilot.hold_height=5.5
	session.world.update_stream(session.pilot.global_position,true)
	session._snap_camera()
	session.input.test_frame={"axes":{},"held":[],"edges":[]}
	await _wait_rendered(3,false)
	for variant in ["original","one_split","no_shadow","scale_75","original_repeat"]:
		session.sun.shadow_enabled=variant!="no_shadow"
		session.sun.directional_shadow_mode=DirectionalLight3D.SHADOW_ORTHOGONAL if variant in ["one_split","scale_75"] else DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
		session.sun.directional_shadow_max_distance=50.0 if variant in ["one_split","scale_75"] else 80.0
		root.scaling_3d_scale=.75 if variant=="scale_75" else 1.0
		await _wait_rendered(2,false)
		_begin_samples()
		await _wait_rendered(12,false)
		await _end_samples()
		var sample=_sample_summary(variant)
		_validate_sample(sample)
		results.append(sample)
		print("V22_PROFILE_SAMPLE ",JSON.stringify(sample))
		await _capture("profile_"+variant)

func _soak() -> void:
	DisplayServer.window_set_size(Vector2i(1440,810))
	for phase in range(8):
		soak_waypoint = 0
		_set_flight("R"+str(phase%4+1),phase>=4,["tr01","hx02","ag03","nx04","sh05","at06"][phase%6],true)
		measured = false
		# Explicit synthetic stability fixture. Natural director validation belongs
		# to the continuous-play probe, never to this eight-unit stress workload.
		if is_instance_valid(session.encounter_director): session.encounter_director.enabled = false
		var encounter: Vector3 = _encounter_position()
		var translation = encounter-session.pilot.global_position
		session.pilot.global_position = encounter
		session.pilot.hold_height = session.pilot.global_position.y
		if is_instance_valid(session.pilot.cargo_body): session.pilot.cargo_body.global_position += translation
		session.world.update_stream(encounter,true)
		session._snap_camera()
		soak_events = {}; soak_effects = {}
		session.living.environment_event.connect(func(event):
			var key = str(event.get("kind","unknown"))
			soak_events[key] = int(soak_events.get(key,0))+1)
		session.living.set_weather(["clear","breeze","mist","rain"][phase%4])
		_spawn_pressure_wave()
		await _wait_rendered(2)
		await _capture("soak_phase_"+str(phase))
		results.append({"label":"soak_configuration_"+str(phase),"source_sha256":source_fingerprint,"region":session.region_id,"night":session.night,"airframe":session.pilot.build.airframe_id,"cargo_kg":soak_cargo_kg,"cargo_rating_kg":session.pilot.stats.cargo_rating_kg,"fixture":"synthetic_eight_enemy_pressure","natural_director_enabled":false,"roles":SOAK_ROLES,"requested_measured_s":phase_seconds})
		print("V2_SOAK_PHASE ",phase," ",session.region_id," night=",session.night," cargo_kg=",soak_cargo_kg," synthetic_enemies=8")
		_begin_samples()
		var phase_begin = Time.get_ticks_usec()
		var prior = phase_begin
		var deadline = phase_begin+int(maxf(phase_seconds*2.0,phase_seconds+30.0)*1000000.0)
		var next_wave = 35.0
		var next_heartbeat = 30.0
		while float(sample_interval_us)/1000000.0<phase_seconds:
			await process_frame
			var now = Time.get_ticks_usec()
			if now>deadline or (last_completed_us>0 and now-last_completed_us>DRAW_TIMEOUT_US):
				_fail_once("Soak phase "+str(phase)+" exceeded actual-draw deadline")
				break
			var elapsed = float(now-phase_begin)/1000000.0
			_fly(float(now-prior)/1000000.0,float(now)/1000000.0-float(flight_started_ms)/1000.0)
			prior = now
			if elapsed>=next_wave:
				_spawn_pressure_wave()
				next_wave = elapsed+35.0
			if elapsed>=next_heartbeat:
				print("V22_SOAK_HEARTBEAT ",JSON.stringify({"elapsed_wall_s":float(Time.get_ticks_msec()-started)/1000.0,"phase":phase,"sample":_sample_summary("live"),"draw_accounting":_draw_accounting(),"effects":soak_effects}))
				next_heartbeat = elapsed+30.0
		await _end_samples()
		var phase_sample = _sample_summary("soak_phase_"+str(phase))
		phase_sample["region"] = session.region_id
		phase_sample["night"] = session.night
		phase_sample["fixture"] = "synthetic_eight_enemy_pressure"
		phase_sample["local_environment_events"] = soak_events.duplicate()
		phase_sample["effects"] = soak_effects.duplicate()
		phase_sample["source_sha256_after"] = JSON.stringify(_source_hashes()).sha256_text()
		phase_sample["phase_wall_s"] = float(Time.get_ticks_usec()-phase_begin)/1000000.0
		phase_sample["requested_measured_s"] = phase_seconds
		_validate_sample(phase_sample)
		if phase_sample.source_sha256_after!=source_fingerprint: _fail_once("Source changed in soak phase "+str(phase))
		var completed_seconds = float(phase_sample.measured_interval_s)
		measured_soak_seconds += completed_seconds
		if completed_seconds>=phase_seconds: finished_soak_phases += 1
		else: _fail_once("Insufficient actual-draw duration in phase "+str(phase))
		results.append(phase_sample)
		print("V2_SOAK_SAMPLE ",JSON.stringify(phase_sample))
		await _capture("soak_phase_"+str(phase)+"_end")
		if completed_seconds<phase_seconds: break

func _spawn_pressure_wave() -> void:
	session.combat.clear_enemies(true)
	session.combat.spawn_wave(SOAK_ROLES,session.pilot.global_position)
	for enemy in session.combat.enemies:
		enemy.set_meta("qa_pressure_fixture",true)
		enemy.set_meta("source_kind","qa_pressure_fixture")
	if session.combat.alive_count()!=8: _fail_once("Pressure fixture did not create eight enemies")
	soak_effects["wave_count"] = int(soak_effects.get("wave_count",0))+1
	soak_effects["peak_live_enemies"] = maxi(int(soak_effects.get("peak_live_enemies",0)),session.combat.alive_count())

func _validate_sample(sample: Dictionary) -> void:
	if int(sample.sample_count)<2: _fail_once("Too few actual draws: "+str(sample.label))
	if int(sample.sample_count)!=maxi(0,int(sample.completed_draws)-1): _fail_once("Each interval must join two consecutive completed draws: "+str(sample.label))
	if gpu_stress and not bool(sample.balanced_draw_receipts): _fail_once("Unbalanced phase draw receipts: "+str(sample.label))
	if int(sample.invalid_draw_samples)>0: _fail_once("Empty viewport workload in measured draws: "+str(sample.label))

func _autoflight() -> void:
	# Replay only inputs through the real arbiter and body, never teleport gates.
	session.show_hangar()
	session.save_build(CatalogV2.default_build("tr01"))
	session.launch_job("M01")
	session.pilot.practice = true
	session.input.test_enabled = true
	var deadline = Time.get_ticks_msec()+int(duration_s*1000)
	var seen_action = ""
	var gate_approached = false
	var next_log = 0
	while Time.get_ticks_msec()<deadline and not session.pause_reasons.has("result"):
		await process_frame
		if not is_instance_valid(session.runner): break
		var action = session.runner.current_action()
		if action.is_empty(): continue
		var key = str(session.stage_index)+":"+str(session.runner.action_index)
		if key != seen_action:
			seen_action = key
			gate_approached = false
			await _capture("autoflight_stage_"+key.replace(":","_"))
		var target = session.runner.target_position()
		if action.type == "gate":
			var entry: Vector3 = target-session.runner.gate_normal*7.0
			if session.pilot.global_position.distance_to(entry)<1.2: gate_approached = true
			target = target+session.runner.gate_normal*5.0 if gate_approached else entry
		elif action.type == "return": target.y = 0.08
		else: target.y = 2.8
		var delta = target-session.pilot.global_position
		var planar = Vector3(delta.x,0,delta.z)
		if action.type == "return" and planar.length()>1.5: target.y = 2.8
		# Rise above buildings on long transfers, then settle before gate alignment.
		if planar.length()>38: target.y = 18.0
		delta = target-session.pilot.global_position
		var desired_speed = minf(7.0,planar.length()*0.75)
		if absf(delta.y)>1.2 and planar.length()<38: desired_speed = minf(desired_speed,1.5)
		var desired = planar.normalized()*desired_speed
		var right = Basis(Vector3.UP,session.pilot.heading).x; right.y=0; right=right.normalized()
		var forward = -Basis(Vector3.UP,session.pilot.heading).z; forward.y=0; forward=forward.normalized()
		var vertical = clampf(delta.y*0.6,-0.7,0.7)
		if absf(delta.y)<0.12: vertical=0
		session.input.test_frame = {"axes":{"left_x":0,"left_y":vertical,"right_x":desired.dot(right)/float(session.pilot.stats.speed_mps),"right_y":desired.dot(forward)/float(session.pilot.stats.speed_mps)},"held":["interact","fire"],"edges":[]}
		if action.get("warning_observed_required",false) and not session.runner.warning_observed: session.input.test_frame.held.erase("fire"); session.combat.auto_fire=false
		else: session.combat.auto_fire=true
		if Time.get_ticks_msec()>=next_log:
			print("V2_REPLAY_PROGRESS ",JSON.stringify({"stage":session.stage_index,"action":session.runner.action_index,"seconds":session.run_seconds,"position":str(session.pilot.global_position),"target":str(target),"condition":session.runner.condition}))
			next_log = Time.get_ticks_msec()+10000
	var complete = session.pause_reasons.has("result") and session.stage_index == 2 and session.runner.action_index == session.runner.actions.size()
	results.append({"label":"M01_input_replay","completed":complete,"stage":session.stage_index,"action":session.runner.action_index,"seconds":session.run_seconds,"position":str(session.pilot.global_position),"condition":session.runner.condition})
	if not complete: failures.append("M01 input replay did not finish within allotted time")


func _review22() -> void:
	DisplayServer.window_set_size(Vector2i(1440,810))
	for page in ["主页","任务","配装","教学"]:
		session.ui.show_hangar(page)
		await _wait_rendered(1,false)
		await _capture("v22_lobby_"+page)
	for id in ["R1","R2","R3","R4"]:
		_set_flight(id,false,"tr01")
		session.input.test_frame={"axes":{},"held":[],"edges":[]}
		session.pilot.global_position=session.living.anchor+Vector3(0,5,8)
		session.pilot.hold_height=5
		session.pilot.linear_velocity=Vector3.ZERO
		session.world.update_stream(session.pilot.global_position,true)
		session.living.update_focus(session.pilot.global_position)
		session._snap_camera()
		for zoom in [24,44,68]:
			session.flight_camera.target_size=zoom
			await _wait_rendered(1.0,false)
			await _capture("v22_"+id+"_zoom"+str(zoom))
		session.living.set_weather("rain")
		await _wait_rendered(10,false)
		await _capture("v22_"+id+"_rain")
		session.set_lighting(true)
		await _wait_rendered(0.5,false)
		await _capture("v22_"+id+"_night")
		session.open_overview()
		await _wait_rendered(1,false)
		await _capture("v22_"+id+"_map")
		session.close_overview()
	session.show_hangar()
	session.launch_job("M01")
	session.tutorial.replay("M01")
	await _wait_rendered(1,false)
	await _capture("v22_tutorial_start")

func _night22() -> void:
	DisplayServer.window_set_size(Vector2i(1440,810))
	for id in ["R1","R2","R3","R4"]:
		_set_flight(id,true,"tr01")
		session.input.test_frame={"axes":{},"held":[],"edges":[]}
		var points={"R1":Vector3(150,4,115),"R2":Vector3(206,4,85),"R3":Vector3(184,4,320),"R4":Vector3(410,4,80)}
		session.pilot.global_position=points[id]
		session.pilot.hold_height=session.pilot.global_position.y
		session.pilot.freeze=false
		session.world.update_stream(session.pilot.global_position,true)
		session._snap_camera()
		for zoom in [24,60]:
			session.flight_camera.target_size=zoom
			await _wait_rendered(1,false)
			await _capture("night22_"+id+"_zoom"+str(zoom))
		session.pilot.heading=PI/2
		await _wait_rendered(1,false)
		await _capture("night22_"+id+"_yaw90")
		session.open_overview()
		await _wait_rendered(.5,false)
		await _capture("night22_"+id+"_map")
		results.append({"label":"night_envelope_"+id,"near_visible":session.night_point_visible(session.pilot.global_position),"far_visible":session.night_point_visible(session.pilot.global_position+Vector3(100,0,0)),"pools":session.night_visibility.active_pools.size()})
		if session.night_point_visible(session.pilot.global_position+Vector3(100,0,0)):failures.append("Night overview leaks distant visibility "+id)
		session.close_overview()
		session.living.set_weather("rain")
		await _wait_rendered(3,false)
		await _capture("night22_"+id+"_rain")
	session.show_hangar()
	session.ui.start_lobby_tour(true)
	await _wait_rendered(.5,false)
	await _capture("lobby_tour_first")
