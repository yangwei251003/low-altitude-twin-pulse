extends SceneTree

var session: GameSessionV2
var job_id = "M02"
var maximum_seconds = 180.0
var qa_case = ""
var started_ms = 0
var samples: Array = []
var transitions: Array = []
var service_changes: Array = []
var setup_transactions: Array = []
var stop_reason = "simulation_budget"
var last_key = ""
var next_sample = 0.0
var last_action_time = 0.0
var gate_approached = false
var gate_entry = Vector3.ZERO
var service_id = ""
var service_tool = ""
var control_mode = "transit"
var distance_flown = 0.0
var previous_position = Vector3.ZERO
var output_file = ""
var diagnose_profile = ""
var source_fingerprints: Dictionary = {}
var progress_position = Vector3.ZERO
var progress_value = 0.0
var requested_start_tool = ""
var service_seat = Vector3.INF
var next_service_attempt = 0.0
var service_attempts: Array = []
var route_grid: AStarGrid2D
var route_height = 12.0
var route_path = PackedVector2Array()
var route_goal = Vector3.INF
var route_active = false
var route_plans: Array = []
var route_blocked_seconds = 0.0
var qa_windowed = false
var capture_directory = ""
var capture_active = false
var capture_frames: Array = []
var capture_failures: Array = []
var next_capture_ms = 0
var input_trace: FileAccess

func _initialize() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument == "--qa-windowed": qa_windowed = true
		if argument.begins_with("--qa-capture-dir="): capture_directory = argument.trim_prefix("--qa-capture-dir=").replace("\\","/")
		if argument.begins_with("--qa-job="): job_id = argument.trim_prefix("--qa-job=")
		if argument.begins_with("--qa-start-tool="): requested_start_tool = argument.trim_prefix("--qa-start-tool=")
		if argument.begins_with("--qa-seconds="): maximum_seconds = clampf(float(argument.trim_prefix("--qa-seconds=")),30.0,900.0)
		if argument.begins_with("--v2-qa=continuous_"): qa_case = argument.trim_prefix("--v2-qa=").validate_filename()
		if argument.begins_with("--qa-diagnose-profile=continuous_"): diagnose_profile = argument.trim_prefix("--qa-diagnose-profile=").validate_filename()
	if qa_case.is_empty() or job_id not in ["M01","M02","M03","M05","M07","M09","M11","M13","M16"] or (DisplayServer.get_name() != "headless" and not qa_windowed):
		printerr("Continuous replay requires headless or explicit --qa-windowed, a supported --qa-job, and a fresh --v2-qa=continuous_<case> profile.")
		quit(2)
		return
	if diagnose_profile.is_empty() and DirAccess.dir_exists_absolute("user://qa_v2/session_"+qa_case):
		printerr("Choose a fresh QA case; existing profiles are never reused.")
		quit(2)
		return
	if not capture_directory.is_empty():
		if DisplayServer.get_name() == "headless" or not qa_windowed or not capture_directory.is_absolute_path() or DirAccess.dir_exists_absolute(capture_directory):
			printerr("PNG recording requires --qa-windowed, a real render window, and a fresh absolute --qa-capture-dir.")
			quit(2)
			return
		if DirAccess.make_dir_recursive_absolute(capture_directory) != OK:
			printerr("Cannot create capture directory")
			quit(2)
			return
		input_trace = FileAccess.open(capture_directory.path_join("inputs.jsonl"),FileAccess.WRITE)
		if input_trace == null:
			printerr("Cannot create route input trace");quit(2);return
	Engine.physics_ticks_per_second = 60
	for path in ["res://scripts_tools/qa_v2_continuous.gd","res://scripts/v2/flight_body.gd","res://scripts/v2/pilot_input.gd","res://scripts/v2/save_repository.gd","res://scripts/v2/task_runner.gd","res://scripts/v2/session.gd","res://scripts/v2/combat.gd","res://scripts/v2/region_world.gd","res://scripts/v2/region_layout.gd","res://scripts/v2/worldui_builder.gd","res://data/worldui/R1.json","res://data/worldui/R2.json","res://data/worldui/R3.json","res://data/worldui/R4.json","res://data/v2/world_content.json"]:
		source_fingerprints[path] = FileAccess.get_sha256(path)
	call_deferred("_run" if diagnose_profile.is_empty() else "_diagnose_save")

func _diagnose_save()->void:
	var path = "user://qa_v2/session_"+diagnose_profile
	var repository = SaveRepositoryV2.new(path)
	var records:Array = []
	for name in DirAccess.get_files_at(path):
		if not name.begins_with("profile_g"): continue
		var source = FileAccess.get_file_as_string(path.path_join(name))
		var envelope = JSON.parse_string(source)
		if not envelope is Dictionary: continue
		var raw_payload = str(envelope.get("payload_json",""))
		var payload = JSON.parse_string(raw_payload) if envelope.get("format") == 2 else envelope.get("payload")
		if not payload is Dictionary: continue
		var risks:Array = []
		_float_roundtrip_risks(payload,"payload",risks)
		var number_pattern = RegEx.new()
		number_pattern.compile("-?[0-9]+\\.[0-9]+(?:[eE][+-]?[0-9]+)?")
		var lexical_changes:Array = []
		for matched in number_pattern.search_all(raw_payload if envelope.get("format") == 2 else source):
			var lexical = matched.get_string()
			var decoded = JSON.parse_string(lexical)
			if not decoded is float: continue
			var encoded = JSON.stringify(decoded,"",true,true)
			if encoded != lexical: lexical_changes.append({"before":lexical,"after":encoded})
		var actual_hash = raw_payload.sha256_text() if envelope.get("format") == 2 else repository._canonical(payload).sha256_text()
		records.append({"file":name,"format":envelope.get("format",1),"expected_hash":envelope.payload_sha256,"actual_hash":actual_hash,"canonical_parsed_hash":repository._canonical(payload).sha256_text(),"valid_profile":repository._validate(payload),"valid_generation":not repository._read_generation(path.path_join(name)).is_empty(),"wallet_parts":payload.wallet.parts,"completed_stages":payload.campaign.completed_stages,"completed_missions":payload.campaign.completed_missions,"roundtrip_risks":risks,"lexical_float_changes":lexical_changes})
	var result = {"scope":"Read-only diagnosis of explicitly isolated continuous QA profile; no commits or player profile access","profile":path,"generations":records}
	var output = "res://artifacts/v2/continuous_save_diagnostic_"+qa_case+".json"
	var file = FileAccess.open(output,FileAccess.WRITE)
	if file: file.store_string(JSON.stringify(result,"\t",true,true)); file.close()
	print("CONTINUOUS_SAVE_DIAGNOSTIC ",JSON.stringify(result,"",true,true))
	quit()

func _float_roundtrip_risks(value,path:String,result:Array)->void:
	if value is Dictionary:
		for key in value: _float_roundtrip_risks(value[key],path+"."+str(key),result)
	elif value is Array:
		for i in value.size(): _float_roundtrip_risks(value[i],path+"["+str(i)+"]",result)
	elif value is float:
		var encoded = JSON.stringify(value,"",true,true)
		var decoded = JSON.parse_string(encoded)
		if decoded != value: result.append({"path":path,"encoded":encoded,"decoded":str(decoded),"reencoded":JSON.stringify(decoded,"",true,true)})

func _run() -> void:
	started_ms = Time.get_ticks_msec()
	session = GameSessionV2.new()
	root.add_child(session)
	await process_frame
	if not session.qa_mode or not session.repository.root_path.begins_with("user://qa_v2/"):
		printerr("Refusing to run without an isolated QA repository")
		quit(2)
		return
	if not session.repository.data.campaign.completed_missions.is_empty() or not session.repository.data.campaign.completed_stages.is_empty():
		printerr("Continuous replay must start with a fresh QA profile; choose a new case name")
		quit(2)
		return
	var prerequisites: Array = []
	var prerequisite_stages: Array = []
	for job in session.content.missions:
		if job.id == job_id: break
		prerequisites.append(job.id)
		for stage in job.get("stages",[]): prerequisite_stages.append(stage.id)
	var free_modules: Array = []
	for id in session.content.catalog.free_tool_map.values(): free_modules.append(id)
	var setup_id = "qa:continuous:"+job_id+":setup"
	var seeded = session.repository.commit({"id":setup_id,"append":{"campaign.completed_missions":prerequisites,"campaign.completed_stages":prerequisite_stages,"owned_modules":free_modules},"set":{"settings.practice_invincible":false,"settings.difficulty":0,"settings.auto_fire":true}})
	if not seeded.ok:
		printerr("QA fixture setup failed: "+str(seeded.error))
		quit(2)
		return
	setup_transactions.append({"id":setup_id,"completed_prerequisites":prerequisites,"completed_prerequisite_stages":prerequisite_stages,"free_modules":free_modules,"practice_invincible":false,"difficulty":0})
	var build = CatalogV2.default_build("tr01")
	if job_id == "M07": build.slots.tool = "clearance_base"
	if job_id == "M16": build.slots.tool = "delivery_base"
	if not requested_start_tool.is_empty(): build.slots.tool = requested_start_tool
	if not session.save_build(build):
		printerr("Legal free-only TR01 setup was rejected")
		quit(2)
		return
	session.input.test_enabled = true
	session.launch_job(job_id)
	if qa_windowed and not capture_directory.is_empty():
		root.minimize_disabled = true
		root.title = "低空小队 · 任务路线记录 " + job_id + " · 可切换应用"
	if not session.flight_active:
		printerr("Mission did not launch: "+session.message)
		quit(2)
		return
	_build_route_grid()
	if not capture_directory.is_empty():
		capture_active = true
		_capture_loop.call_deferred()
	previous_position = session.pilot.global_position
	progress_position = previous_position
	output_file = "res://artifacts/v2/continuous_"+job_id+"_"+qa_case+".json"
	while session.run_seconds < maximum_seconds:
		await physics_frame
		if not is_instance_valid(session.runner) or not is_instance_valid(session.pilot):
			stop_reason = "session_objects_missing"
			break
		distance_flown += previous_position.distance_to(session.pilot.global_position)
		previous_position = session.pilot.global_position
		if session.pause_reasons.has("result"):
			stop_reason = "result"
			break
		if paused:
			stop_reason = "paused:"+str(session.pause_reasons.keys())
			break
		if not session.pilot.global_position.is_finite():
			stop_reason = "nonfinite_position"
			break
		var action = session.runner.current_action()
		if action.is_empty(): continue
		var key = str(session.stage_index)+":"+str(session.runner.action_index)
		if key != last_key:
			if not last_key.is_empty(): transitions.back()["left_at_seconds"] = session.run_seconds
			last_key = key
			last_action_time = session.run_seconds
			gate_approached = false
			service_id = ""
			service_tool = ""
			service_seat = Vector3.INF
			route_active = false
			route_goal = Vector3.INF
			gate_entry = session.runner.target_position()-session.runner.gate_normal*7.0
			transitions.append({"key":key,"stage_id":session.runner.stage.id,"action_type":action.type,"label":action.get("label",""),"cargo_id":action.get("cargo_id",""),"cargo_snapshot":_cargo_snapshot(),"entered_at_seconds":session.run_seconds,"position":_vector(session.pilot.global_position)})
			print("CONTINUOUS_ACTION ",JSON.stringify(transitions.back()))
		if session.pilot.global_position.distance_to(progress_position)>1.0 or absf(session.runner.progress_s-progress_value)>0.1:
			last_action_time = session.run_seconds
			progress_position = session.pilot.global_position
			progress_value = session.runner.progress_s
		_drive(action)
		if session.run_seconds >= next_sample:
			var sample = _sample()
			samples.append(sample)
			print("CONTINUOUS_PROGRESS ",JSON.stringify(sample))
			next_sample = session.run_seconds + 10.0
		if session.run_seconds-last_action_time>180.0:
			stop_reason = "no_motion_or_task_progress_180_simulated_seconds"
			break
	await _finish()

func _drive(action: Dictionary) -> void:
	var target = session.runner.target_position()
	var needed = str(action.get("tool_id",""))
	if not needed.is_empty() and str(session.pilot.build.slots.tool) != needed:
		if service_tool != needed:
			service_tool = needed
			service_id = _choose_service()
			service_seat = _service_landing_point(service_id) if not service_id.is_empty() else Vector3.INF
			route_active = false
			route_goal = Vector3.INF
		if service_id.is_empty() or not service_seat.is_finite():
			control_mode = "no_service_available"
			_write_input(Vector3.ZERO,0.0,false)
			return
		# A real service remains authoritative: no midair equip or threat/cargo bypass.
		target = service_seat
		target.y = session.world.surface_height(target)+0.05
		control_mode = "service:"+service_id
		var distance = _horizontal(target-session.pilot.global_position).length()
		if distance<1.2 and session.pilot.is_landed() and session.pilot.linear_velocity.length()<0.35 and session.run_seconds>=next_service_attempt:
			var before = str(session.pilot.build.slots.tool)
			next_service_attempt=session.run_seconds+1.0
			session.switch_service("tool",needed)
			service_attempts.append({"seconds":session.run_seconds,"poi":service_id,"wanted":needed,"before":before,"after":session.pilot.build.slots.tool,"threats":session.combat.nearby_threats(),"cargo_kg":session.pilot.cargo_kg,"notice":session.message})
			if session.pilot.build.slots.tool != before:
				service_changes.append({"seconds":session.run_seconds,"poi":service_id,"from":before,"to":session.pilot.build.slots.tool,"grounded":session.pilot.is_landed(),"speed":session.pilot.linear_velocity.length(),"position":_vector(session.pilot.global_position)})
				print("CONTINUOUS_SERVICE ",JSON.stringify(service_changes.back()))
				service_id = ""
				service_tool = ""
				service_seat = Vector3.INF
				route_goal = Vector3.INF
				route_active = false
				_write_input(Vector3.ZERO,0.5,false)
				return
		_move_to(target,false,true)
		return
	control_mode = str(action.type)
	if action.type == "gate":
		if session.pilot.global_position.distance_to(gate_entry)<1.2: gate_approached = true
		target = target+session.runner.gate_normal*5.0 if gate_approached else gate_entry
	elif action.type == "return": target.y = session.world.surface_height(target)+0.05
	elif action.type == "pickup": target.y = session.world.surface_height(target)+2.0
	elif action.type == "deliver": target.y = session.world.surface_height(target)+3.6
	elif action.type == "defend":
		target.y = session.world.surface_height(target)+6.0
		if session.runner.action_started:
			target += Vector3(sin(session.run_seconds*0.3),0,cos(session.run_seconds*0.3))*4.0
	elif action.type == "escort" and is_instance_valid(session.runner.facility):
		target = session.runner.facility.global_position+Vector3(0,4.0,0)
	elif action.type == "scan" and action.has("scan_facing_deg"):
		var angle = deg_to_rad(float(action.scan_facing_deg))
		target += Vector3(sin(angle),0,cos(angle))*3.0
	if action.type == "scan" and action.has("scan_path_m"):
		target += Vector3(sin(session.run_seconds*0.4),0,cos(session.run_seconds*0.4))*2.0
	_move_to(target,true,action.type=="return",0.4 if action.type=="pickup" else 4.8)

func _build_route_grid() -> void:
	# A fixed regional cruise plane keeps graph edges at a physically meaningful altitude.
	# Tall structures (including the entire turbine blade sweep) are routed around.
	route_height=12.0
	for land in session.world.layout.get("land",[]): route_height=maxf(route_height,float(land.height)+6.0)
	route_height=minf(route_height,session.pilot.max_altitude-2.0)
	route_grid=AStarGrid2D.new()
	route_grid.region=Rect2i(0,0,150,125)
	route_grid.cell_size=Vector2(4,4)
	route_grid.offset=Vector2(2,2)
	route_grid.diagonal_mode=AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	route_grid.update()
	for x in range(150):
		for z in range(125):
			var point=Vector3(x*4+2,route_height,z*4+2)
			var blocked=session.world.surface_height(point)>route_height-3.5
			for item in session.world.obstacles:
				if float(item.get("base_y",0))+float(item.h)<route_height-3.5: continue
				var delta=Vector2(point.x-float(item.x),point.z-float(item.z)).rotated(-float(item.get("yaw",0)))
				var half=Vector2(float(item.w),float(item.l))*.5+Vector2(3.5,3.5)
				if str(item.asset)=="turbine": half=Vector2(12.0,6.0)
				if absf(delta.x)<half.x and absf(delta.y)<half.y: blocked=true; break
			route_grid.set_point_solid(Vector2i(x,z),blocked)

func _route_cell(point: Vector3) -> Vector2i:
	return Vector2i(clampi(floori(point.x/4.0),0,149),clampi(floori(point.z/4.0),0,124))

func _free_route_cell(point: Vector3) -> Vector2i:
	var origin=_route_cell(point)
	if not route_grid.is_point_solid(origin): return origin
	for radius in range(1,5):
		for x in range(-radius,radius+1):
			for z in range(-radius,radius+1):
				var candidate=origin+Vector2i(x,z)
				if route_grid.is_in_boundsv(candidate) and not route_grid.is_point_solid(candidate):return candidate
	return Vector2i(-1,-1)

func _route_segment_clear(a: Vector2,b: Vector2) -> bool:
	var steps=maxi(1,ceili(a.distance_to(b)/1.5))
	for index in range(steps+1):
		var point=a.lerp(b,float(index)/steps)
		if route_grid.is_point_solid(_route_cell(Vector3(point.x,route_height,point.y))):return false
	return true

func _route_waypoint(target: Vector3) -> Vector3:
	var position=session.pilot.global_position
	var distance=_horizontal(target-position).length()
	if not route_goal.is_finite() or _horizontal(target-route_goal).length()>6.0:
		route_goal=target
		route_active=distance>16.0
		route_path=PackedVector2Array()
		if route_active:
			var start=_free_route_cell(position);var finish=_free_route_cell(target)
			if start.x>=0 and finish.x>=0:route_path=route_grid.get_point_path(start,finish)
			route_plans.append({"seconds":session.run_seconds,"start":_vector(position),"target":_vector(target),"cruise_height":route_height,"waypoints":route_path.size()})
	if not route_active:return target
	if route_path.is_empty():
		control_mode+="::no_collision_safe_route"
		return Vector3(INF,INF,INF)
	while route_path.size()>1 and Vector2(position.x,position.z).distance_to(route_path[0])<3.0:route_path.remove_at(0)
	if distance<3.0:
		route_active=false
		return target
	control_mode+=":authored_route"
	var skip=0
	for index in range(1,mini(8,route_path.size())):
		if _route_segment_clear(Vector2(position.x,position.z),route_path[index]):skip=index
		else:break
	for index in range(skip):route_path.remove_at(0)
	var next=route_path[0]
	# The final graph cell is approximate; finish at the actual action coordinate.
	if route_path.size()==1:next=Vector2(target.x,target.z)
	return Vector3(next.x,route_height,next.y)

func _motion_blocked(desired: Vector3) -> bool:
	if desired.length()<.1:return false
	var shape=BoxShape3D.new()
	shape.size=Vector3(float(session.pilot.stats.width_m)+.3,float(session.pilot.stats.height_m)+.2,float(session.pilot.stats.length_m)+.3)
	var parameters=PhysicsShapeQueryParameters3D.new()
	parameters.shape=shape
	parameters.transform=Transform3D(Basis.IDENTITY,session.pilot.global_position+Vector3.UP*.12)
	parameters.motion=desired.normalized()*minf(4.0,desired.length())
	parameters.collision_mask=1|32
	parameters.exclude=[session.pilot.get_rid()]
	var motion=session.pilot.get_world_3d().direct_space_state.cast_motion(parameters)
	return motion.size()==2 and float(motion[0])<.97

func _move_to(target:Vector3,allow_interaction:bool,landing:bool,interaction_radius:float=4.8)->void:
	var position=session.pilot.global_position
	var true_distance=_horizontal(target-position).length()
	var waypoint=_route_waypoint(target)
	if not waypoint.is_finite():
		route_blocked_seconds+=1.0/Engine.physics_ticks_per_second
		_write_input(Vector3.ZERO,0.0,false)
		return
	var planar=_horizontal(waypoint-position)
	var distance=planar.length()
	var desired_height=waypoint.y
	# A landing target is not an airborne approach altitude. Establish clearance
	# until centered over it, including when an earlier descent stopped off-seat.
	if landing and not route_active and true_distance >= 0.8:
		desired_height = maxf(session.world.surface_height(position),session.world.surface_height(target))+2.0
		control_mode += ":landing_approach"
	var height_error=desired_height-position.y
	var speed=minf(7.0,distance*.7)
	if session.pilot.cargo_kg>0.0:speed=minf(speed,5.0)
	if route_active:
		if position.y<route_height-.9:speed=0.0
		elif distance>6.0:speed=minf(float(session.pilot.stats.speed_mps)*.65,6.5 if session.pilot.cargo_kg>0 else 9.0)
	elif absf(height_error)>1.2:speed=minf(speed,1.0)
	if landing and not route_active and true_distance >= 0.8 and session.pilot.ground_distance < 0.8:
		speed = 0.0
	var desired=planar.normalized()*speed
	if distance<6.0:
		desired-=_horizontal(session.pilot.linear_velocity)*.35
		desired-=_horizontal(session.pilot.environment_acceleration)*.5
	var vertical=clampf(height_error*.55-session.pilot.linear_velocity.y*.12,-.6,.7)
	if absf(height_error)<.10:vertical=0.0
	if landing and not route_active and true_distance<0.8 and not session.pilot.is_landed():vertical=-.22
	if landing and not route_active and true_distance<0.8 and session.pilot.is_landed():vertical=0.0
	if (route_active or true_distance>4.0) and _motion_blocked(desired):
		desired=Vector3.ZERO
		vertical=maxf(vertical,.35) if position.y<route_height-.7 else 0.0
		control_mode+=":real_collision_wait"
		route_blocked_seconds+=1.0/Engine.physics_ticks_per_second
	var interact=allow_interaction and not route_active and true_distance<interaction_radius and absf(height_error)<.35
	_write_input(desired,vertical,interact)

func _write_input(desired_velocity:Vector3,vertical:float,interact:bool)->void:
	var right = Basis(Vector3.UP,session.pilot.heading).x
	right.y = 0.0
	right = right.normalized()
	var forward = -Basis(Vector3.UP,session.pilot.heading).z
	forward.y = 0.0
	forward = forward.normalized()
	var scale = float(session.pilot.stats.speed_mps)
	var held: Array = ["fire"]
	if interact: held.append("interact")
	session.input.test_frame = {"axes":{"left_x":0.0,"left_y":vertical,"right_x":clampf(desired_velocity.dot(right)/scale,-1.0,1.0),"right_y":clampf(desired_velocity.dot(forward)/scale,-1.0,1.0)},"held":held,"edges":[]}

	if input_trace:
		input_trace.store_line(JSON.stringify({"seconds":session.run_seconds,"physics_frame":Engine.get_physics_frames(),"command":session.input.test_frame}))

func _capture_loop() -> void:
	while capture_active:
		await RenderingServer.frame_post_draw
		if not capture_active or not is_instance_valid(session): break
		var now = Time.get_ticks_msec()
		if now < next_capture_ms: continue
		next_capture_ms = now+250
		var pixels = root.get_texture().get_image()
		if pixels == null or pixels.is_empty():
			capture_failures.append({"wall_ms":now-started_ms,"error":"empty_viewport"})
			continue
		var filename = "frame_%06d.png" % capture_frames.size()
		var error = pixels.save_png(capture_directory.path_join(filename))
		if error != OK:
			capture_failures.append({"wall_ms":now-started_ms,"error":error})
			continue
		capture_frames.append({"file":filename,"wall_seconds":(now-started_ms)/1000.0,"simulation_seconds":session.run_seconds,"stage":session.stage_index,"action":session.runner.action_index if is_instance_valid(session.runner) else -1,"size":[pixels.get_width(),pixels.get_height()]})

func _service_landing_point(id: String) -> Vector3:
	if id.is_empty() or not session.world.service_unlocked(id):return Vector3.INF
	var center=session.world.poi_position(id)
	var shape=BoxShape3D.new()
	shape.size=Vector3(float(session.pilot.stats.width_m)+.4,float(session.pilot.stats.height_m),float(session.pilot.stats.length_m)+.4)
	for offset in [Vector2(-3,-3),Vector2(-3,0),Vector2(0,-3),Vector2(3,-3),Vector2(-6,0),Vector2(0,-6),Vector2(0,0)]:
		var point=center+Vector3(offset.x,0,offset.y)
		var support=session.world.surface_at(point+Vector3.UP*40)
		if bool(support.water):continue
		point.y=float(support.height)
		var safe=true
		for corner in [Vector3(-1.4,0,-1.4),Vector3(1.4,0,-1.4),Vector3(-1.4,0,1.4),Vector3(1.4,0,1.4)]:
			var edge=session.world.surface_at(point+corner+Vector3.UP*40)
			if bool(edge.water) or absf(float(edge.height)-point.y)>.15:safe=false;break
		if not safe:continue
		var parameters=PhysicsShapeQueryParameters3D.new()
		parameters.shape=shape
		parameters.transform=Transform3D(Basis.IDENTITY,point+Vector3.UP*(shape.size.y*.5+.16))
		parameters.collision_mask=1|8|32
		parameters.exclude=[session.pilot.get_rid()]
		if not session.pilot.get_world_3d().direct_space_state.intersect_shape(parameters,1).is_empty():continue
		return point
	return Vector3.INF

func _choose_service()->String:
	var plan:Dictionary=session.runner.stage.get("equipment_plan",{})
	var suggested=str(plan.get("switch_service_poi",plan.get("entry_service_poi","")))
	if not suggested.is_empty() and session.world.poi_index.get(suggested,{}).has("service_function") and _service_landing_point(suggested).is_finite():return suggested
	var best=""
	var distance=INF
	for poi in session.world.region.pois:
		if not poi.has("service_function") or not session.world.service_unlocked(str(poi.id)):continue
		var point=_service_landing_point(str(poi.id))
		if not point.is_finite():continue
		var d=point.distance_to(session.pilot.global_position)
		if d<distance:distance=d;best=str(poi.id)
	return best

func _horizontal(value:Vector3)->Vector3:
	return Vector3(value.x,0,value.z)

func _vector(value:Vector3)->Array:
	return [value.x,value.y,value.z]

func _cargo_snapshot()->Array:
	var result:Array = []
	for id in session.runner.cargo:
		var body = session.runner.cargo[id]
		if is_instance_valid(body):
			result.append({"id":id,"instance_id":body.get_instance_id(),"position":_vector(body.global_position),"mass_kg":body.mass,"held":session.pilot.cargo_items.has(id),"state":session.runner.cargo_records.get(id,{}).get("state","")})
	return result

func _sample()->Dictionary:
	return {"seconds":session.run_seconds,"stage":session.stage_index,"action":session.runner.action_index,"mode":control_mode,"position":_vector(session.pilot.global_position),"target":_vector(session.runner.target_position()),"velocity":_vector(session.pilot.linear_velocity),"condition":session.runner.condition,"health":session.pilot.health,"cargo_kg":session.pilot.cargo_kg,"cargo_swing_deg":session.pilot.cargo_swing(),"grounded":session.pilot.is_landed(),"tool":session.pilot.build.slots.tool,"live_enemies":session.combat.alive_count(),"action_progress_s":session.runner.progress_s,"distance_flown_m":distance_flown}

func _finish()->void:
	capture_active = false
	if input_trace: input_trace.flush(); input_trace.close()
	if not is_instance_valid(session) or not is_instance_valid(session.runner) or not is_instance_valid(session.pilot):
		var failure_file = FileAccess.open(output_file,FileAccess.WRITE)
		if failure_file:
			failure_file.store_string(JSON.stringify({"job_id":job_id,"completed":false,"stop_reason":"session_objects_missing","source_fingerprints_at_start":source_fingerprints}))
			failure_file.close()
		printerr("Route ended with missing session objects; recording is not a passing route.")
		quit(1);return
	var completed = job_id in session.repository.data.campaign.completed_missions
	if not transitions.is_empty():
		var last_action = str(transitions.back().key).split(":")
		var advanced = session.stage_index>int(last_action[0]) or (session.stage_index==int(last_action[0]) and session.runner.action_index>int(last_action[1]))
		if completed or advanced: transitions.back()["left_at_seconds"] = session.run_seconds
	var final_sample = _sample()
	var record = {"suite":"continuous_input_replay","engine":Engine.get_version_info().string,"job_id":job_id,"completed":completed,"stop_reason":stop_reason,"simulated_seconds":session.run_seconds,"elapsed_wall_seconds":(Time.get_ticks_msec()-started_ms)/1000.0,"qa_root":session.repository.root_path,"setup_fixture_transactions":setup_transactions,"airframe":"tr01","damage_taken":session.pilot.damage_taken,"collisions":session.pilot.collision_count,"distance_flown_m":distance_flown,"stage_receipts":session.repository.data.campaign.completed_stages,"action_visits":transitions,"completed_actions":transitions.filter(func(item):return item.has("left_at_seconds")),"service_changes":service_changes,"final":final_sample,"samples":samples,"runner_metrics":session.runner.record_metrics(),"evidence_scope":("Headless" if DisplayServer.get_name() == "headless" else "Windowed GPU-rendered")+" continuous PilotInput test_frame commands and actual rigid-body/task/combat simulation. Only QA prerequisite/free-tool inventory setup is seeded. No pilot teleport, direct action completion, injected enemy damage, invincibility, or production predicate bypass. Normal game cargo seating is retained. Optional PNGs are actual viewport frames sampled at up to 4 Hz wall time with timestamps; recording affects timing. Not human playthrough, performance benchmark, phone or physical controller evidence. A stuck bot is not proof of human unplayability."}
	record["render_evidence"] = {"display_server":DisplayServer.get_name(),"windowed_opt_in":qa_windowed,"capture_directory":capture_directory,"requested_wall_capture_hz":4,"frames":capture_frames,"failures":capture_failures,"input_trace":"inputs.jsonl" if not capture_directory.is_empty() else "","performance_evidence":false,"human_playthrough":false,"engine_arguments":OS.get_cmdline_args()}
	if not capture_directory.is_empty():
		var manifest = FileAccess.open(capture_directory.path_join("manifest.json"),FileAccess.WRITE)
		if manifest:
			manifest.store_string(JSON.stringify(record.render_evidence,"\t"));manifest.flush()
			if manifest.get_error()!=OK: capture_failures.append({"error":"manifest_write_failed"})
			manifest.close()
		else: capture_failures.append({"error":"manifest_open_failed"})
	record["combat"] = {"kills":session.combat.kills,"aim_status":session.combat.aim_status,"objective_complete":session.combat.objective_complete(),"boss_phase":session.combat.boss_phase,"events":session.combat.events.duplicate(true)}
	record["source_fingerprints_at_start"] = source_fingerprints
	record["wallet_parts"] = session.repository.data.wallet.parts
	record["requested_start_tool"] = requested_start_tool
	record["route_plans"] = route_plans
	record["route_blocked_seconds"] = route_blocked_seconds
	record["service_attempts"] = service_attempts
	record["stage_receipts"] = session.repository.data.campaign.completed_stages.filter(func(id):return str(id).begins_with(job_id+"-"))
	record["final_cargo_snapshot"] = _cargo_snapshot()
	if session.pause_reasons.has("save_error"):
		var risks:Array = []
		_float_roundtrip_risks(session.pending_transaction,"transaction",risks)
		record["save_failure"] = {"notice":session.repository.notice,"pending_transaction":session.pending_transaction,"roundtrip_risks":risks}
	DirAccess.make_dir_recursive_absolute("res://artifacts/v2")
	var file = FileAccess.open(output_file,FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(record,"\t",true,true))
		file.close()
	print("CONTINUOUS_SUMMARY ",JSON.stringify({"job":job_id,"completed":completed,"stop_reason":stop_reason,"seconds":session.run_seconds,"stage":session.stage_index,"action":session.runner.action_index,"service_changes":service_changes.size(),"output":output_file,"condition":session.runner.condition}))
	paused = false
	session.phone.stop_server()
	var retired_session = weakref(session)
	session.queue_free()
	await process_frame
	await process_frame
	# A SceneTreeTimer uses fixed simulation delta under --fixed-fps. Give the
	# audio server actual wall time to retire playback resources after queue_free.
	var drain_started_ms = Time.get_ticks_msec()
	while Time.get_ticks_msec()-drain_started_ms < 250:
		OS.delay_msec(10)
		await process_frame
	record["cleanup"] = {"session_released":retired_session.get_ref()==null,"audio_drain_wall_s":float(Time.get_ticks_msec()-drain_started_ms)/1000.0}
	var end_fingerprints: Dictionary = {}
	for path in source_fingerprints: end_fingerprints[path] = FileAccess.get_sha256(path)
	record["source_fingerprints_at_end"] = end_fingerprints
	record["source_unchanged"] = end_fingerprints==source_fingerprints
	file = FileAccess.open(output_file,FileAccess.WRITE)
	var report_written = false
	if file:
		file.store_string(JSON.stringify(record,"\t",true,true));file.flush()
		report_written = file.get_error()==OK
		file.close()
	quit(0 if completed and bool(record.cleanup.session_released) and bool(record.source_unchanged) and capture_failures.is_empty() and report_written else 1)
