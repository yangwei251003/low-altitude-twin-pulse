extends "res://scripts_tools/qa_v2_render.gd"
## Native-window matrix; explicit arguments below are mandatory (no inherited defaults).
## --v2-qa=<unique> --qa-mode=matrix --qa-gpu-stress=false --qa-duration=160
## --qa-phase-seconds=20 --qa-quality=standard --qa-output=res://artifacts/v22/<fresh-directory>
## Long run: --qa-duration=1800 --qa-phase-seconds=225. Low remains available.
## All eight phases share one native process; setup/warmup/PNG are excluded.
## Godot frame_post_draw means completed viewport updates, not an OS present counter:
## https://docs.godotengine.org/en/stable/classes/class_renderingserver.html#signals
## https://docs.godotengine.org/en/stable/classes/class_displayserver.html#class-displayserver-method-window-can-draw
const WINDOW_SIZE = Vector2i(1440,810)
const WARMUP_SECONDS = 3.0
const NO_DRAW_US = 5000000
var window_quality = "standard"
var window_route_start = Vector3.ZERO
var window_route_end = Vector3.ZERO
var window_route_data: Dictionary = {}
var window_vsync = -1
var window_adapter = ""
var window_frame_cap = 0
var window_render_scale = 1.0
var window_focused_draws = 0
var window_unfocused_draws = 0
var window_phase_origin = Vector3.ZERO
var window_previous_position = Vector3.ZERO
var window_flight_distance = 0.0
var window_live_min = 8
var window_live_max = 0
var window_cargo_max_distance = 0.0
var window_motion_samples = 0
var window_next_refill_s = 12.0

func _initialize() -> void:
	var options: Dictionary={}
	for argument in OS.get_cmdline_user_args():
		if not argument.begins_with("--qa-") and not argument.begins_with("--v2-qa="): continue
		var split=argument.find("=")
		if split<0: push_error("Window probe options require explicit values.");quit(2);return
		var key=argument.substr(0,split)
		if options.has(key): push_error("Duplicate window probe option: "+key);quit(2);return
		options[key]=argument.substr(split+1)
	var required={"--qa-mode":"matrix","--qa-gpu-stress":"false"}
	for key in required:
		if options.get(key,"")!=required[key]:
			push_error("Window probe requires "+key+"="+required[key]);quit(2);return
	var requested_duration=str(options.get("--qa-duration",""))
	var requested_phase=str(options.get("--qa-phase-seconds",""))
	if not requested_duration.is_valid_float() or not requested_phase.is_valid_float():
		push_error("Explicit numeric duration and phase seconds are mandatory.");quit(2);return
	var total=float(requested_duration);var phase=float(requested_phase)
	if total not in [160.0,1800.0] or not is_equal_approx(phase*8.0,total):
		push_error("Use 160/20 or 1800/225 seconds for all eight day/night phases.");quit(2);return
	window_quality=str(options.get("--qa-quality","standard"))
	if window_quality not in ["standard","low"]:
		push_error("qa-quality must be standard or low.");quit(2);return
	var destination=str(options.get("--qa-output",""))
	if str(options.get("--v2-qa","")).is_empty() or not destination.begins_with("res://artifacts/v22/") or destination.contains("..") or FileAccess.file_exists(destination+"/matrix_report.json"):
		push_error("Use a unique QA profile and fresh artifacts/v22 output directory.");quit(2);return
	for argument in OS.get_cmdline_args():
		if argument.begins_with("--fixed-fps") or argument=="--disable-render-loop" or argument=="--headless":
			push_error("Native window timing requires the ordinary real-time render loop.");quit(2);return
	if not OS.is_debug_build(): push_error("Synthetic input requires the debug engine.");quit(2);return
	super._initialize()

func _source_hashes() -> Dictionary:
	var hashes=super._source_hashes()
	var own_path="res://scripts_tools/v22_window_perf_probe.gd"
	hashes[own_path]=FileAccess.get_sha256(own_path)
	return hashes

func _measurement_scope() -> String:
	return "Native visible non-minimized window, automatic render loop and ordinary window swap. Timing is the interval between actual frame_post_draw callbacks, not process FPS or an OS/compositor present counter. Vsync, frame cap, internal 3D scale and focused/unfocused drawn-frame counts are recorded; losing keyboard focus alone does not invalidate a drawable window."

func _on_post_draw() -> void:
	super._on_post_draw()
	if measured and drawing_enabled and not gpu_stress:
		if DisplayServer.window_is_focused(): window_focused_draws+=1
		else: window_unfocused_draws+=1

func _native_long_run() -> bool:
	return mode=="matrix" and not gpu_stress and duration_s>=1800.0

func _matrix() -> void:
	if gpu_stress or mode!="matrix" or duration_s not in [160.0,1800.0] or not is_equal_approx(phase_seconds*8.0,duration_s):
		_fail_once("Window probe inherited incompatible timing parameters");return
	session.repository.commit({"id":"native-window-settings:"+str(Time.get_ticks_usec()),"set":{"settings.quality":window_quality,"settings.fullscreen":false,"settings.ui_scale":1.0,"settings.control_mode":"assisted","settings.auto_fire":false,"settings.camera_zoom":32.0}})
	session.apply_settings()
	# QA-only guard against an accidental title-bar minimization during the
	# authorized long run. Close/Alt-Tab remain available; a non-drawable window
	# still fails immediately, and is never silently restored into the sample.
	root.minimize_disabled = _native_long_run()
	if _native_long_run(): root.title = "低空小队 · 30分钟窗口验证 · 可切换应用"
	DisplayServer.window_set_size(WINDOW_SIZE)
	var usable=DisplayServer.screen_get_usable_rect(DisplayServer.window_get_current_screen())
	DisplayServer.window_set_position(usable.position+(usable.size-WINDOW_SIZE)/2)
	window_vsync=DisplayServer.window_get_vsync_mode()
	window_adapter=RenderingServer.get_video_adapter_name()
	window_frame_cap=Engine.max_fps
	window_render_scale=root.scaling_3d_scale
	var valid_phases=0
	var total_measured=0.0
	for phase in range(8):
		var region="R"+str(phase%4+1)
		var dark=phase>=4
		var label="window_"+region+("_night" if dark else "_day")
		_set_flight(region,dark,["tr01","hx02","ag03","nx04","sh05","at06"][phase%6],true)
		measured=false
		session.input.take_control("keyboard");session.input.test_enabled=true
		session.encounter_director.enabled=false
		if not _configure_window_route(): return
		# Setup-only translation of pilot/cargo. Measurement uses the ordinary
		# input arbiter and flight body along this region's authored road.
		var shift=window_phase_origin-session.pilot.global_position
		session.pilot.global_position=window_phase_origin
		session.pilot.hold_height=window_phase_origin.y
		if is_instance_valid(session.pilot.cargo_body): session.pilot.cargo_body.global_position+=shift
		if is_instance_valid(session.pilot.cargo_joint): session.pilot.cargo_joint.global_position+=shift
		session.world.update_stream(window_phase_origin,true);session._snap_camera()
		soak_effects={};soak_events={}
		session.living.set_weather(["clear","breeze","mist","rain"][phase%4])
		_spawn_pressure_wave()
		window_next_refill_s=12.0
		if soak_cargo_kg<=0 or not CatalogV2.resolve_build(session.active_build,soak_cargo_kg).valid:
			_fail_once("No legal payload in "+label);return
		var hash_before=JSON.stringify(_source_hashes()).sha256_text()
		if hash_before!=source_fingerprint: _fail_once("Source changed before "+label);return
		if not await _native_warmup(label): return
		var before=_window_state()
		if not _check_window(label+" before"): return
		if session.region_id!=region or session.night!=dark:
			_fail_once("Regional day/night fixture mismatch in "+label);return
		window_previous_position=session.pilot.global_position
		window_flight_distance=0.0;window_motion_samples=0
		window_focused_draws=0;window_unfocused_draws=0
		window_live_min=8;window_live_max=0;window_cargo_max_distance=0.0
		var phase_begin=Time.get_ticks_usec();var prior=phase_begin
		var next_window_check=phase_begin
		_begin_samples()
		var target_interval_us=int(phase_seconds*1000000.0)
		var deadline_us=int((phase_seconds+maxf(15.0,phase_seconds*.15))*1000000.0)
		while sample_interval_us<target_interval_us:
			await process_frame
			var now=Time.get_ticks_usec()
			if now-phase_begin>deadline_us or last_completed_us<=0 or now-last_completed_us>NO_DRAW_US:
				_fail_once("Native-window actual-draw deadline exceeded in "+label);break
			if now>=next_window_check:
				if not _check_window(label+" during"): break
				next_window_check=now+250000
			_fly(float(now-prior)/1000000.0,float(now)/1000000.0-float(flight_started_ms)/1000.0)
			prior=now
			if not failures.is_empty(): break
		await _end_samples()
		var after=_window_state()
		_check_window(label+" after")
		var summary=_sample_summary(label)
		summary["frame_post_draw_intervals_ms"]=current_samples.duplicate()
		summary.merge({"region":region,"night":dark,"quality":window_quality,"authored_route":window_route_data,"window_before":before,"window_after":after,"vsync_mode_applies_to_native_window":window_vsync,"window_size_px":[1440,810],"warmup_excluded_s":WARMUP_SECONDS,"requested_measured_s":phase_seconds,"phase_wall_s":float(Time.get_ticks_usec()-phase_begin)/1000000.0,"source_sha256_before":hash_before,"source_sha256_after":JSON.stringify(_source_hashes()).sha256_text(),"fixture":"synthetic_eight_enemy_pressure_with_legal_cargo","natural_director_enabled":false,"practice_damage_protection":session.pilot.practice,"airframe":session.pilot.build.airframe_id,"cargo_kg":soak_cargo_kg,"cargo_rating_kg":session.pilot.stats.cargo_rating_kg,"cargo_max_distance_m":window_cargo_max_distance,"flight_distance_m":window_flight_distance,"moving_samples":window_motion_samples,"live_enemies_min_before_refill":window_live_min,"live_enemies_max":window_live_max,"replacement_waves_including_initial":soak_effects.get("wave_count",0),"roles":SOAK_ROLES,"scene_placement_during_measurement":false,"png_excluded_from_measurement":true})
		summary.merge({"scaling_3d_scale":window_render_scale,"focused_draws":window_focused_draws,"unfocused_draws":window_unfocused_draws,"focus_scope":"mixed" if window_focused_draws>0 and window_unfocused_draws>0 else ("focused" if window_focused_draws>0 else "unfocused")})
		_validate_sample(summary)
		if window_focused_draws+window_unfocused_draws!=int(summary.completed_draws): _fail_once("Draw focus accounting mismatch in "+label)
		if float(summary.measured_interval_s)<phase_seconds: _fail_once("Less than 20 seconds of completed-draw intervals in "+label)
		if summary.source_sha256_after!=hash_before: _fail_once("Source changed during "+label)
		if window_flight_distance<3.0 or window_motion_samples<2: _fail_once("Actual input did not move the aircraft in "+label)
		if window_live_max!=8: _fail_once("Eight-enemy workload was not observed in "+label)
		results.append(summary)
		var console_summary=summary.duplicate()
		console_summary.erase("frame_post_draw_intervals_ms")
		print("V22_WINDOW_SAMPLE ",JSON.stringify(console_summary))
		if not failures.is_empty(): break
		valid_phases+=1;total_measured+=float(summary.measured_interval_s)
		# The inherited capture waits for an ordinary completed draw; no manual
		# rendering is submitted and its readback/write cost is outside sampling.
		await _capture(label)
		if not _check_window(label+" after PNG") or not failures.is_empty(): break
	finished_soak_phases=valid_phases;measured_soak_seconds=total_measured
	if valid_phases!=8 or total_measured<duration_s: _fail_once("Native-window matrix did not finish all eight measured phases")
	results.append({"label":"native_window_matrix_completion","valid_phases":valid_phases,"measured_seconds":total_measured,"requested_phases":8,"requested_seconds":duration_s,"quality":window_quality,"native_long_run":_native_long_run(),"single_process_continuous_run":true,"fixture":"Synthetic flight/cargo/eight-enemy pressure; not natural encounter rates or human comfort.","scope":_measurement_scope()})

func _configure_window_route() -> bool:
	# Pick a 24 m corridor near the region's living area, on authored roads.
	# Clearance includes cargo and structures. No poses change during sampling.
	var anchor: Vector3=session.living.anchor
	var best_score=INF
	window_route_data={}
	for road in session.world.layout.get("roads",[]):
		if bool(road.get("bridge",false)): continue
		for i in range(road.points.size()-1):
			var raw_a=road.points[i];var raw_b=road.points[i+1]
			var a=Vector3(float(raw_a[0]),0,float(raw_a[1]));var b=Vector3(float(raw_b[0]),0,float(raw_b[1]))
			var length_m=a.distance_to(b)
			if length_m<28.0: continue
			var along=(b-a).normalized()
			var near=Geometry3D.get_closest_point_to_segment(Vector3(anchor.x,0,anchor.z),a,b)
			var center=a+along*clampf(a.distance_to(near),14.0,length_m-14.0)
			var start=center-along*12.0;var end=center+along*12.0
			var altitude=-INF;var minimum_surface=INF
			for j in range(13):
				var p=start.lerp(end,float(j)/12.0)
				var height=session.world.surface_height(p)
				altitude=maxf(altitude,height+6.0);minimum_surface=minf(minimum_surface,height)
				for obstacle in session.world.obstacles:
					var rotor_extra=9.0 if str(obstacle.get("asset",""))=="turbine" else 0.0
					if absf(p.x-float(obstacle.x))<=float(obstacle.w)*.5+4.0+rotor_extra and absf(p.z-float(obstacle.z))<=float(obstacle.l)*.5+4.0:
						altitude=maxf(altitude,float(obstacle.get("base_y",0))+float(obstacle.h)+4.0+rotor_extra)
			if altitude>28.0: continue
			var score=Vector2(center.x-anchor.x,center.z-anchor.z).length()+(altitude-minimum_surface-6.0)*3.0
			if score>=best_score: continue
			best_score=score;start.y=altitude;end.y=altitude
			window_route_start=start;window_route_end=end;window_phase_origin=start
			window_route_data={"source":"world.layout.roads","start":[start.x,start.y,start.z],"end":[end.x,end.y,end.z],"altitude_m":altitude,"minimum_surface_m":minimum_surface,"cargo_clearance_m":6.0}
	if window_route_data.is_empty():
		_fail_once("No safe authored native-window flight corridor in "+session.region_id);return false
	return true

func _native_warmup(label: String) -> bool:
	measured=false
	var begin=Time.get_ticks_usec();var prior=begin;var draws_before=completed_draws
	while Time.get_ticks_usec()-begin<int(WARMUP_SECONDS*1000000.0):
		await process_frame
		var now=Time.get_ticks_usec()
		if not _check_window(label+" warmup"): return false
		if now-begin>NO_DRAW_US or (last_completed_us>0 and now-last_completed_us>NO_DRAW_US):
			_fail_once("Window warmup produced no timely actual draw: "+label);return false
		_fly(float(now-prior)/1000000.0,float(now)/1000000.0-float(flight_started_ms)/1000.0)
		prior=now
		if not failures.is_empty(): return false
	if completed_draws-draws_before<2:
		_fail_once("Too few actual native-window warmup draws: "+label);return false
	return true

func _fly(_delta: float, elapsed: float) -> void:
	if not is_instance_valid(session.pilot) or not session.flight_active:
		_fail_once("Native-window flight fixture disappeared");return
	var target=window_route_start.lerp(window_route_end,.5-.5*cos(elapsed*.2))+Vector3.UP*(.4*sin(elapsed*.3))
	var offset=target-session.pilot.global_position
	var planar=Vector3(offset.x,0,offset.z)
	var direction=planar.normalized()*minf(.75,planar.length()*.6/maxf(1.0,float(session.pilot.stats.speed_mps)))
	var basis=Basis(Vector3.UP,session.pilot.heading)
	session.input.test_frame={"axes":{"left_x":.08*sin(elapsed*.25),"left_y":clampf(offset.y*.35,-.7,.7),"right_x":direction.dot(basis.x),"right_y":direction.dot(-basis.z)},"held":["fire"],"edges":[]}
	var alive=session.combat.alive_count()
	if measured:
		window_live_min=mini(window_live_min,alive);window_live_max=maxi(window_live_max,alive)
		var travel=session.pilot.global_position.distance_to(window_previous_position)
		window_flight_distance+=travel;window_previous_position=session.pilot.global_position
		if travel>.001: window_motion_samples+=1
	if alive>8: _fail_once("Native-window synthetic enemy budget exceeded")
	elif alive<8 and elapsed>=window_next_refill_s:
		# Bounded replenishment exercises actor creation without turning every
		# individual kill into a new eight-actor allocation spike.
		_spawn_pressure_wave()
		window_next_refill_s=elapsed+12.0
	if not is_instance_valid(session.pilot.cargo_body) or not is_instance_valid(session.pilot.cargo_joint):
		_fail_once("Native-window legal cargo/joint disappeared");return
	var cargo_distance=session.pilot.global_position.distance_to(session.pilot.cargo_body.global_position)
	if measured: window_cargo_max_distance=maxf(window_cargo_max_distance,cargo_distance)
	if not session.pilot.global_position.is_finite() or not session.pilot.cargo_body.global_position.is_finite() or cargo_distance>8.0:
		_fail_once("Native-window flight/cargo pose became invalid")

func _window_state() -> Dictionary:
	var size=DisplayServer.window_get_size()
	var texture_size=root.get_texture().get_size()
	return {"root_visible":root.visible,"drawable":DisplayServer.window_can_draw(),"focused":DisplayServer.window_is_focused(),"mode":DisplayServer.window_get_mode(),"minimize_button_disabled_qa_only":root.minimize_disabled,"client_size_px":[size.x,size.y],"viewport_size_px":[root.size.x,root.size.y],"viewport_texture_size_px":[texture_size.x,texture_size.y],"scaling_3d_scale":root.scaling_3d_scale,"quality":session.repository.data.settings.get("quality",""),"vsync_mode":DisplayServer.window_get_vsync_mode(),"render_loop_enabled":RenderingServer.render_loop_enabled,"rendering_method":RenderingServer.get_current_rendering_method(),"adapter":RenderingServer.get_video_adapter_name(),"display_server":DisplayServer.get_name(),"max_fps":Engine.max_fps,"time_scale":Engine.time_scale,"low_processor_usage":OS.low_processor_usage_mode,"completed_draws":completed_draws}

func _check_window(label: String) -> bool:
	var valid=root.visible and DisplayServer.window_can_draw()
	valid=valid and DisplayServer.window_get_mode()==DisplayServer.WINDOW_MODE_WINDOWED and DisplayServer.window_get_size()==WINDOW_SIZE and root.size==WINDOW_SIZE
	valid=valid and RenderingServer.render_loop_enabled and RenderingServer.get_current_rendering_method()=="gl_compatibility" and not window_adapter.is_empty() and RenderingServer.get_video_adapter_name()==window_adapter
	valid=valid and DisplayServer.window_get_vsync_mode()==window_vsync and Engine.max_fps==window_frame_cap and is_equal_approx(Engine.time_scale,1.0)
	valid=valid and is_equal_approx(root.scaling_3d_scale,window_render_scale)
	valid=valid and str(session.repository.data.settings.get("quality",""))==window_quality and not gpu_stress and not paused
	if not valid:
		_fail_once("Visible native-window conditions changed: "+label)
		results.append({"label":"invalid_window_state","phase":label,"state":_window_state()})
	return valid
