extends SceneTree
## Rendered 300 s asset budget study. Never run alongside capture/Blender.
## Time is monotonic process_frame wall time, not Engine's smoothed delta.

const WARMUP_SECONDS := 5.0
const MEASURE_SECONDS := 300.0
const SIZE := Vector2i(1280, 720)
const SEED := 314159
const PHASES := [
	{"start":0.0, "end":40.0, "id":"I1_asset", "group":"I1"},
	{"start":40.0, "end":80.0, "id":"I1_mechanism", "group":"I1"},
	{"start":80.0, "end":125.0, "id":"I1_boss", "group":"I1"},
	{"start":125.0, "end":130.0, "id":"transition_I1_F1", "group":"transition"},
	{"start":130.0, "end":170.0, "id":"F1_asset", "group":"F1"},
	{"start":170.0, "end":210.0, "id":"F1_chain", "group":"F1"},
	{"start":210.0, "end":255.0, "id":"F1_boss", "group":"F1"},
	{"start":255.0, "end":260.0, "id":"transition_F1_I1", "group":"transition"},
	{"start":260.0, "end":300.0, "id":"I1_return", "group":"I1"},
]

var session
var output := ""
var profile := ""
var frames: Array[Dictionary] = []
var samples: Array[Dictionary] = []
var events: Array[Dictionary] = []
var issues: Array[String] = []
var fired: Dictionary = {}
var source_hashes: Dictionary = {}
var metadata: Dictionary = {}
var last_phase := ""
var start_usec := 0
var previous_usec := 0
var next_sample := 0.0
var initial_camera_basis := Basis.IDENTITY
var maximum_camera_angle_error := 0.0
var window_changed := false
var vsync_changed := false

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	if ProjectSettings.get_setting("application/config/version", "") != "3.0.0-dev.2":
		push_error("Historical dev.2 asset route is no longer compatible with current Boss entry; use profile_crown_flight.gd for the bounded F1 study")
		quit(2)
		return
	if not _arguments_valid():
		quit(2)
		return
	seed(SEED)
	if DirAccess.make_dir_recursive_absolute(output) != OK:
		push_error("Cannot create performance evidence directory")
		quit(2)
		return
	# Hashing happens outside measurement, and again after it to detect concurrent edits.
	source_hashes = _hash_inputs()
	metadata = _environment()
	_write_json("prepared.json", {"status":"starting_not_a_result", "environment":metadata, "source_sha256":source_hashes, "phases":PHASES})
	session = load("res://scenes/v3/main.tscn").instantiate()
	root.add_child(session)
	current_scene = session
	if not session.start_flight("solo") or not session.players.has(1):
		_fail("main.tscn failed to start solo session")
		return
	# Session, mechanisms, HUD, timers and periodic saves remain active. Only manual
	# input and pilot integration are removed; this is explicitly not a flight test.
	session.inputs.set_process(false)
	session.inputs.set_physics_process(false)
	session.inputs.set_process_input(false)
	session.inputs.set_process_unhandled_input(false)
	session.inputs.clear()
	_place(Vector3(-24, 2, 29))
	session.flight_camera.snap(session.players[1].global_position)
	initial_camera_basis = session.camera.global_basis
	if not is_instance_valid(session.world.art_bridge) or not session.world.art_bridge.imported:
		_fail("Industrial GLB/Shutter import absent")
		return
	var warmup_start := Time.get_ticks_usec()
	while Time.get_ticks_usec() - warmup_start < int(WARMUP_SECONDS * 1000000):
		await process_frame
	metadata.warmup_actual_seconds = (Time.get_ticks_usec() - warmup_start) / 1000000.0
	metadata.camera_size = session.camera.size
	metadata.camera_basis = str(initial_camera_basis)
	metadata.camera_offset = str(session.flight_camera.OFFSET)
	metadata.user_dir = OS.get_user_data_dir()
	metadata.profile = profile
	metadata.memory_after_warmup = _memory()
	print("V3_PERF_STARTED ", output, " duration=300 warmup=5 vsync=", metadata.vsync_actual)
	await process_frame
	start_usec = Time.get_ticks_usec()
	previous_usec = start_usec
	var interval_phase: Dictionary = PHASES[0]
	_drive(0.0)
	while true:
		await process_frame
		# Read clock FIRST: prior-frame route/actions/save/render/wait are included.
		var now := Time.get_ticks_usec()
		var elapsed := (now - start_usec) / 1000000.0
		frames.append({"start_s":(previous_usec-start_usec)/1000000.0, "end_s":elapsed,
			"usec":now-previous_usec, "phase":interval_phase.id, "group":interval_phase.group})
		previous_usec = now
		if elapsed >= MEASURE_SECONDS:
			break
		if elapsed >= next_sample:
			_sample(elapsed)
			next_sample = floor(elapsed) + 1.0
		interval_phase = _phase(elapsed)
		# Even a stall that skips a scheduled boundary cannot hide the ensuing load
		# in a steady-state region bin. Attribute the full load interval explicitly.
		if elapsed >= 125.0 and not fired.has("load_F1"): interval_phase = PHASES[3]
		elif elapsed >= 255.0 and not fired.has("load_I1"): interval_phase = PHASES[7]
		_drive(elapsed)
	var measured_seconds := (previous_usec-start_usec)/1000000.0
	var final_stats: Dictionary = session.stats.duplicate(true)
	var final_mechanisms: Dictionary = session.world.mechanism_snapshot()
	var final_memory := _memory()
	# No further scene work is part of measurement. Serializing raw rows is outside it.
	session.set_process(false)
	session.set_physics_process(false)
	session.network.close()
	var end_hashes := _hash_inputs()
	if end_hashes != source_hashes: issues.append("source_or_assets_changed_during_run")
	if window_changed: issues.append("viewport_or_window_changed_during_run")
	if vsync_changed: issues.append("vsync_changed_during_run")
	if maximum_camera_angle_error > 0.001: issues.append("fixed_camera_angle_changed")
	if int(final_stats.get("rejected_abilities", 0)) > 0: issues.append("one_or_more_ability_requests_rejected")
	var groups := {}
	for group in ["I1", "F1", "transition"]:
		groups[group] = _statistics(frames.filter(func(row): return row.group == group))
	var phase_stats := {}
	for phase in PHASES:
		var rows: Array = frames.filter(func(row): return row.phase == phase.id)
		phase_stats[phase.id] = _statistics(rows)
		if rows.is_empty(): issues.append("phase_not_sampled:" + str(phase.id))
	if not _write_csv(): issues.append("raw_frame_csv_write_failed")
	var report := {"status":"measured" if issues.is_empty() else "measured_with_validity_issues",
		"scope":"single-player two-asset budget study; not complete game, LAN, human play or maximum-world acceptance",
		"environment":metadata, "measurement":{"clock":"Time.get_ticks_usec monotonic process_frame intervals", "target_seconds":MEASURE_SECONDS,
		"actual_seconds":measured_seconds, "overshoot_seconds":measured_seconds-MEASURE_SECONDS, "frames":frames.size(),
		"warmup_target_seconds":WARMUP_SECONDS, "include_full_final_interval":true, "percentile":"nearest-rank, ceil(p*N)-1",
		"slow_threshold_ms":33.3, "max_camera_angle_error_radians":maximum_camera_angle_error},
		"overall":_statistics(frames), "groups":groups, "phases":phase_stats, "schedule":PHASES,
		"events":events, "one_second_samples":samples, "final_game_stats":final_stats, "final_mechanisms":final_mechanisms,
		"memory_after_measurement":final_memory, "source_sha256":source_hashes, "source_sha256_after":end_hashes,
		"issues":issues, "limitations":_limitations()}
	if not _write_json("report.json", report): issues.append("report_json_write_failed")
	print("V3_PERF_FINISHED ", JSON.stringify({"output":output,"frames":frames.size(),"seconds":measured_seconds,"issues":issues,"overall":report.overall}))
	session.queue_free()
	await process_frame
	quit(0 if issues.is_empty() else 3)

func _arguments_valid() -> bool:
	var run_enabled := false
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--qa-profile="): profile = arg.trim_prefix("--qa-profile=")
		if arg.begins_with("--perf-output="): output = arg.trim_prefix("--perf-output=").replace("\\", "/").simplify_path()
		if arg == "--perf-run": run_enabled = true
		if arg.begins_with("--qa-network=") or arg.begins_with("--qa-duration="):
			push_error("Do not mix LAN QA automation with performance study")
			return false
	var regex := RegEx.new()
	regex.compile("^qa_perf_[A-Za-z0-9_-]+$")
	var evidence_root := ProjectSettings.globalize_path("res://artifacts/v3/performance/").replace("\\", "/").simplify_path()
	if not run_enabled or regex.search(profile) == null or output.is_empty() or not output.is_absolute_path() or not output.to_lower().begins_with(evidence_root.to_lower().trim_suffix("/") + "/"):
		push_error("Require --perf-run, unique --qa-profile=qa_perf_* and new --perf-output=<project>/artifacts/v3/performance/<run>")
		return false
	if DirAccess.dir_exists_absolute("user://profiles_v3/" + profile) or DirAccess.dir_exists_absolute(output):
		push_error("Profile and output must both be new; evidence is never overwritten")
		return false
	if DisplayServer.get_name() == "headless" or RenderingServer.get_current_rendering_method() != "gl_compatibility":
		push_error("Study requires real Compatibility window; headless is only allowed for --check-only")
		return false
	if root.size != SIZE or DisplayServer.window_get_size() != SIZE:
		push_error("Study requires actual 1280x720 window and viewport; use --resolution 1280x720 --windowed")
		return false
	if Engine.max_fps != 0 or not is_equal_approx(Engine.time_scale, 1.0):
		push_error("Do not add an artificial max_fps limit or change time_scale")
		return false
	if not RenderingServer.is_render_loop_enabled():
		push_error("Render loop must be enabled")
		return false
	if DisplayServer.window_get_vsync_mode() != int(ProjectSettings.get_setting("display/window/vsync/vsync_mode", 1)):
		push_error("Actual VSync must match delivery project default; do not disable it for this study")
		return false
	return true

func _drive(t: float) -> void:
	var phase := _phase(t)
	if str(phase.id) != last_phase:
		last_phase = phase.id
		events.append({"time_s":t,"kind":"phase","id":last_phase})
	if t >= 125.0 and not fired.has("load_F1"):
		_transition("F1", t)
		fired.load_F1 = true
	if t >= 255.0 and not fired.has("load_I1"):
		_transition("I1", t)
		fired.load_I1 = true
	var at := Vector3(-24, 2, 29)
	match str(phase.id):
		"I1_asset":
			at = _path(t, [0,8,16,22,28,33,37,40], [Vector3(-24,2,29),Vector3(-24,2,21),Vector3(-24,2,29),Vector3(-24,6.15,29),Vector3(-24,6.15,26.5),Vector3(-24,6.15,29),Vector3(-14,3,29),Vector3(-14,2,20)])
		"I1_mechanism":
			at = _path(t-40, [0,12,17,23,30,36,40], [Vector3(-14,2,20),Vector3(-14,2,20),Vector3(-14,7,29),Vector3(-24,6.15,29),Vector3(-24,6.15,21),Vector3(-24,6.15,29),Vector3(-24,16,29)])
		"I1_boss": at = _boss_path(t-80)
		"transition_I1_F1", "F1_asset":
			at = _path(maxf(0,t-130), [0,10,20,30,40], [Vector3(-24,5.2,29),Vector3(-24,5.2,21),Vector3(-24,5.2,29),Vector3(-24,5.2,21),Vector3(-24,5.2,29)])
		"F1_chain":
			at = _path(t-170, [0,2,4,8,12,35,40], [Vector3(-24,5.2,29),Vector3(-24,5.2,29),Vector3(-18,6.4,29),Vector3(-18,6.4,29),Vector3(-24,5.2,29),Vector3(-24,5.2,29),Vector3(-24,16,29)])
		"F1_boss": at = _boss_path(t-210)
		"transition_F1_I1": at = Vector3(-24,2,29)
		"I1_return":
			at = _path(t-260,[0,8,16,22,30,37,40],[Vector3(-24,2,29),Vector3(-24,2,21),Vector3(-24,2,29),Vector3(-24,6.15,29),Vector3(-24,6.15,21),Vector3(-24,6.15,29),Vector3(-24,6.15,29)])
	_place(at)
	# Real host intents: no cooldown reset, fake rule success or entity-state injection.
	_action(t,40.5,"charge_up_1","charge","I1:relay")
	_action(t,41.5,"charge_up_2","charge","I1:relay")
	_action(t,45.0,"charge_down_1","charge","I1:relay","drain")
	_action(t,46.0,"charge_down_2","charge","I1:relay","drain")
	_action(t,49.0,"charge_reopen_1","charge","I1:relay")
	_action(t,50.0,"charge_reopen_2","charge","I1:relay")
	_action(t,170.5,"ring_light_1","light","F1:mirror")
	_action(t,171.5,"ring_light_2","light","F1:mirror")
	_action(t,174.5,"growth_1","growth","F1:growth")
	_action(t,175.5,"growth_2","growth","F1:growth")
	for light_time in [185.0,190.0,195.0,200.0]:
		_action(t,light_time,"ring_motion_"+str(light_time),"light","F1:mirror")
	if str(phase.id) in ["I1_boss","F1_boss"] and t-float(phase.start) >= 15.0:
		var key := str(phase.id) + "_start"
		if not fired.has(key):
			fired[key] = true
			session._action_received(1,"boss_start",{})
			events.append({"time_s":t,"kind":"boss_started","region":session.region_id,"active":session.boss_active})
	maximum_camera_angle_error = maxf(maximum_camera_angle_error, initial_camera_basis.get_rotation_quaternion().angle_to(session.camera.global_basis.get_rotation_quaternion()))

func _transition(region: String, t: float) -> void:
	var before := Time.get_ticks_usec()
	session._save_environment()
	session._load_region(region)
	var imported: bool = session.world.art_bridge.imported if region == "I1" else session.world.art_temple.imported
	if not imported: issues.append("missing_import:"+region)
	_place(Vector3(-24,2,29) if region == "I1" else Vector3(-24,5.2,29))
	session.flight_camera.snap(session.players[1].global_position)
	events.append({"time_s":t,"kind":"region_load","region":region,"synchronous_ms":(Time.get_ticks_usec()-before)/1000.0,"imported":imported,"note":"fixed five-second transition bin includes save, synchronous load, deletion and subsequent render upload"})

func _action(t: float, scheduled: float, key: String, ability: String, target: String, mode := "") -> void:
	if t < scheduled or fired.has(key): return
	fired[key] = true
	# A multi-second stall must not silently burst old-region intents in a new region.
	if not target.begins_with(str(session.region_id)+":"):
		issues.append("missed_action:"+key)
		events.append({"time_s":t,"scheduled_s":scheduled,"kind":"missed_action","id":key})
		return
	var before := int(session.stats.abilities)
	var rejected_before := int(session.stats.rejected_abilities)
	session._action_received(1,"ability",{"ability":ability,"target_id":target,"mode":mode})
	var applied := int(session.stats.abilities) > before
	if not applied: issues.append("action_not_applied:"+key)
	events.append({"time_s":t,"scheduled_s":scheduled,"kind":"ability","id":key,"ability":ability,"target":target,"mode":mode,"applied":applied,"rejected":int(session.stats.rejected_abilities)>rejected_before})

func _place(at: Vector3) -> void:
	var body = session.players[1]
	body.freeze = true
	body.set_physics_process(false)
	body.global_position = at
	body.linear_velocity = Vector3.ZERO
	body.angular_velocity = Vector3.ZERO
	body.hold_height = at.y
	session.entities["player:1"].position = at

func _boss_path(t: float) -> Vector3:
	if t < 15:
		return _path(t,[0,3,12,15],[Vector3(-24,16,29),Vector3(-24,16,16),Vector3(26,16,-32),Vector3(26,12,-32)])
	var a := (t-15.0)*TAU/16.0
	return Vector3(14+cos(a)*12,12+sin(a*0.5)*1.5,-32+sin(a)*12)

func _path(t: float, times: Array, points: Array) -> Vector3:
	for i in range(1,times.size()):
		if t <= float(times[i]):
			return (points[i-1] as Vector3).lerp(points[i],clampf((t-float(times[i-1]))/(float(times[i])-float(times[i-1])),0,1))
	return points.back()

func _phase(t: float) -> Dictionary:
	for phase in PHASES:
		if t < float(phase.end): return phase
	return PHASES.back()

func _sample(elapsed: float) -> void:
	var row := _memory()
	row.merge({"time_s":elapsed,"region":session.region_id,"phase":last_phase,"player":str(session.players[1].global_position),
		"draw_calls":Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
		"rendered_primitives":Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME),
		"window_focused":DisplayServer.window_is_focused(),"window_mode":DisplayServer.window_get_mode(),
		"window_size":str(DisplayServer.window_get_size()),"viewport_size":str(root.size),
		"vsync":DisplayServer.window_get_vsync_mode(),"max_fps":Engine.max_fps,"time_scale":Engine.time_scale,
		"simulation_paused":session.simulation_paused,"mechanisms":session.world.mechanism_snapshot(),"boss_active":session.boss_active})
	samples.append(row)
	if root.size != SIZE or DisplayServer.window_get_size() != SIZE: window_changed = true
	if DisplayServer.window_get_vsync_mode() != int(metadata.vsync_actual): vsync_changed = true
	if DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_MINIMIZED and not issues.has("window_minimized"): issues.append("window_minimized")
	if (Engine.max_fps != 0 or not is_equal_approx(Engine.time_scale,1.0) or session.simulation_paused) and not issues.has("timing_or_pause_changed"):
		issues.append("timing_or_pause_changed")

func _statistics(rows: Array) -> Dictionary:
	if rows.is_empty(): return {"frames":0}
	var ordered: Array[float] = []
	var total := 0.0
	var counts := {"gt_33_3ms":0,"gt_50ms":0,"gt_100ms":0}
	var run_frames := 0
	var run_ms := 0.0
	var longest_frames := 0
	var longest_ms := 0.0
	var previous_end := -1.0
	for row in rows:
		var ms := float(row.usec)/1000.0
		ordered.append(ms)
		total += ms
		# A different group/phase gap breaks consecutive runs, never stitch I1 visits.
		if previous_end >= 0 and absf(float(row.start_s)-previous_end)>0.000001:
			run_frames = 0
			run_ms = 0
		previous_end = row.end_s
		if ms>33.3:
			counts.gt_33_3ms += 1
			run_frames += 1
			run_ms += ms
			longest_frames = maxi(longest_frames,run_frames)
			longest_ms = maxf(longest_ms,run_ms)
		else:
			run_frames = 0
			run_ms = 0
		if ms>50: counts.gt_50ms += 1
		if ms>100: counts.gt_100ms += 1
	ordered.sort()
	return {"frames":rows.size(),"sampled_seconds":total/1000.0,"mean_fps":rows.size()*1000.0/total,
		"p50_ms":_percentile(ordered,0.50),"p95_ms":_percentile(ordered,0.95),"p99_ms":_percentile(ordered,0.99),"max_ms":ordered.back(),
		"counts":counts,"longest_consecutive_gt_33_3ms_frames":longest_frames,"longest_consecutive_gt_33_3ms_duration_ms":longest_ms}

func _percentile(ordered: Array[float], fraction: float) -> float:
	return ordered[clampi(int(ceil(ordered.size()*fraction))-1,0,ordered.size()-1)]

func _memory() -> Dictionary:
	return {"engine_static_bytes":OS.get_static_memory_usage(),"engine_static_peak_bytes":OS.get_static_memory_peak_usage(),
		"render_video_bytes":Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED),
		"render_texture_bytes":Performance.get_monitor(Performance.RENDER_TEXTURE_MEM_USED),
		"render_buffer_bytes":Performance.get_monitor(Performance.RENDER_BUFFER_MEM_USED),"node_count":Performance.get_monitor(Performance.OBJECT_NODE_COUNT)}

func _environment() -> Dictionary:
	return {"utc_started":Time.get_datetime_string_from_system(true),"godot":Engine.get_version_info(),"executable":OS.get_executable_path(),
		"executable_sha256":FileAccess.get_sha256(OS.get_executable_path()),"os":OS.get_name(),"os_version":OS.get_version(),
		"cpu":OS.get_processor_name(),"logical_processors":OS.get_processor_count(),"display":DisplayServer.get_name(),
		"renderer_actual":RenderingServer.get_current_rendering_method(),"driver_actual":RenderingServer.get_current_rendering_driver_name(),
		"device":RenderingServer.get_video_adapter_name(),"vendor":RenderingServer.get_video_adapter_vendor(),"api_version":RenderingServer.get_video_adapter_api_version(),
		"renderer_configured":ProjectSettings.get_setting("rendering/renderer/rendering_method"),"vsync_actual":DisplayServer.window_get_vsync_mode(),
		"vsync_project":ProjectSettings.get_setting("display/window/vsync/vsync_mode",1),"vsync_override":false,
		"viewport_size":str(root.size),"window_size":str(DisplayServer.window_get_size()),"screen_refresh_hz":DisplayServer.screen_get_refresh_rate(),
		"max_fps":Engine.max_fps,"physics_ticks_per_second":Engine.physics_ticks_per_second,"time_scale":Engine.time_scale,
		"render_loop_enabled":RenderingServer.is_render_loop_enabled(),"msaa_3d":root.msaa_3d,"scaling_3d_scale":root.scaling_3d_scale,
		"directional_shadow_size":ProjectSettings.get_setting("rendering/lights_and_shadows/directional_shadow/size"),
		"engine_args":OS.get_cmdline_args(),"user_args":OS.get_cmdline_user_args(),"seed":SEED}

func _hash_inputs() -> Dictionary:
	var paths: Array[String] = ["res://project.godot","res://scripts_tools/v3/profile_assets.gd"]
	for dir in ["res://scripts","res://scenes/v3","res://assets/v3"]: _collect_files(dir,paths)
	paths.sort()
	var result := {}
	for path in paths: result[path] = FileAccess.get_sha256(path)
	return result

func _collect_files(path: String, paths: Array[String]) -> void:
	for file in DirAccess.get_files_at(path):
		if file.get_extension() in ["gd","tscn","tres","glb","gdshader","png","jpg","webp"]: paths.append(path.path_join(file))
	for subdir in DirAccess.get_directories_at(path): _collect_files(path.path_join(subdir),paths)

func _write_json(filename: String, value: Dictionary) -> bool:
	var file := FileAccess.open(output.path_join(filename),FileAccess.WRITE)
	if not file:
		push_error("Cannot write " + filename)
		return false
	file.store_string(JSON.stringify(value,"\t"))
	file.flush()
	return file.get_error() == OK

func _write_csv() -> bool:
	var file := FileAccess.open(output.path_join("frames.csv"),FileAccess.WRITE)
	if not file: return false
	file.store_line("index,start_s,end_s,wall_usec,phase,group")
	for i in frames.size():
		var row: Dictionary = frames[i]
		file.store_line("%d,%.6f,%.6f,%d,%s,%s" % [i,row.start_s,row.end_s,row.usec,row.phase,row.group])
	file.flush()
	return file.get_error() == OK

func _fail(reason: String) -> void:
	push_error(reason)
	_write_json("failure.json",{"status":"not_measured","reason":reason,"environment":metadata})
	if is_instance_valid(session): session.network.close()
	quit(2)

func _limitations() -> Array[String]:
	return ["Current two imported assets and surrounding graybox only, not complete world or maximum population.",
		"Solo authority; no LAN client, real network or two-player load.",
		"Pilot rigid body frozen and script-positioned through waypoints; no human inputs, flight integration or comfort/route-collision acceptance.",
		"Normal session physics, mechanisms, HUD, transient effects, boss and periodic profile saves remain active.",
		"Fixed oblique orientation and default camera size; transitions deliberately teleport/reset camera to asset entrance.",
		"Boss runs normal telegraph/attack cycles; no exhaustive combat, player weapon stress or final boss art.",
		"Five-second warmup is I1 only; F1 first load remains a measured transition. OS/driver caches are not cleared.",
		"Source hashing reads GLB/textures before scene load, so disk caches may already be warm; this is not cold-start storage profiling.",
		"Region load uses internal save/load harness, bypassing player voting/menu; five-second bins include upload/deferred cleanup, later stalls stay in normal bins.",
		"Raw process_frame intervals include CPU, scheduling, render submission and VSync wait; they are not direct GPU timestamps or display presentation latency.",
		"Engine/render memory monitors are estimates, not Windows process working-set or physical shared-GPU allocation; unsupported counters may be zero.",
		"One-second counters are snapshots, not peaks. Per-frame tracing has measurable small overhead, retained equally in repeat runs.",
		"No automatic full-game 720p30 PASS label; inspect raw frames, scene coverage and validity issues before using asset budget evidence."]
