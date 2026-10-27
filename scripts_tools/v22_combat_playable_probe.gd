extends SceneTree
## Owner-run integration sample. Only setup places the aircraft; every subsequent
## position, projectile, hit and destruction is produced by the real game.
## --v2-qa=<unique> [--capture] [--day-only|--night-only] [--probe-region=R2]
## [--probe-seed=22015] Each region/seed is one independent, unretried sample.
## [--probe-output=res://artifacts/v22/combat_playable] [--probe-limit=120]
const ALTITUDE = 3.4
const SAMPLE_INTERVAL = .1
var session: GameSessionV2
var output = "res://artifacts/v22/combat_playable"
var capture = false
var branch_mode = "both"
var region_id = "R2"
var seed_value = 22015
var limit_s = 120.0
var clock_s = 0.0
var branch_start = 0.0
var phase = "initializing"
var branch = ""
var checks: Array = []
var failures: Array[String] = []
var receipts: Array = []
var director_events: Array = []
var trajectory: Array = []
var transitions: Array = []
var screenshots: Array = []
var fixtures: Array = []
var source_hashes: Dictionary = {}
var selected_entry = Vector3.ZERO
var entry_direction = Vector3(0,0,1)
var fixture_building = Vector3.ZERO
var fixture_asset = ""
var night_contact: Dictionary = {}
var output_explicit = false
var selected_foe
var entry_actor_id = ""
var cover_box = AABB()
var cover_name = ""
var buildings: Array[Dictionary] = []
var route_grid: AStarGrid2D
var path: PackedVector2Array = []
var path_goal = Vector3.INF
var path_finish = Vector3.ZERO
var path_rebuild_at = 0.0
var next_sample = 0.0
var wall_started = 0
var entered_legal: Dictionary = {}
var branch_results: Array = []
var capture_warning = false
var total_distance = 0.0
var previous_position = Vector3.ZERO
var first_entry_sample: Dictionary = {}
var wreck_samples: Array = []
var control_goal = Vector3.ZERO
var control_waypoint = Vector3.ZERO
var cover_plans: Array = []

func _initialize() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument=="--capture": capture=true
		elif argument=="--day-only": branch_mode="day"
		elif argument=="--night-only": branch_mode="night"
		elif argument.begins_with("--probe-region="): region_id=argument.trim_prefix("--probe-region=").to_upper()
		elif argument.begins_with("--probe-seed="): seed_value=int(argument.trim_prefix("--probe-seed="))
		elif argument.begins_with("--probe-output="): output=argument.trim_prefix("--probe-output=").trim_suffix("/");output_explicit=true
		elif argument.begins_with("--probe-limit="): limit_s=clampf(float(argument.trim_prefix("--probe-limit=")),30,240)
	call_deferred("_run")

func _run() -> void:
	wall_started=Time.get_ticks_msec()
	if region_id not in ["R1","R2","R3","R4"]:
		push_error("--probe-region must be R1, R2, R3 or R4.");quit(2);return
	if not output_explicit: output+="/"+region_id+"_seed"+str(seed_value)
	var qa=false
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--v2-qa=") and argument.length()>8: qa=true
	if not qa or not OS.is_debug_build():
		push_error("A unique --v2-qa profile and debug engine are required for synthetic input.");quit(2);return
	if capture and DisplayServer.get_name()=="headless":
		push_error("--capture requires a real GPU renderer; headless pixels are not accepted.");quit(2);return
	if not output.begins_with("res://artifacts/v22/"):
		push_error("Probe evidence must stay under res://artifacts/v22/.");quit(2);return
	DirAccess.make_dir_recursive_absolute(output)
	for id in ["session","flight_body","combat","enemy_actor","enemy_brain","encounter_director","damage_model","combat_feedback","night_visibility","pilot_input","region_world"]:
		source_hashes[id]=FileAccess.get_sha256("res://scripts/v2/"+id+".gd")
	source_hashes["probe"]=FileAccess.get_sha256("res://scripts_tools/v22_combat_playable_probe.gd")
	session=GameSessionV2.new();root.add_child(session)
	for i in 5: await process_frame
	var updates={"settings.quality":"low","settings.auto_fire":false,"settings.difficulty":1,
		"settings.practice_invincible":false,"settings.control_mode":"assisted",
		"settings.environment_wind":0.0,"settings.environment_weather":0.0,
		"settings.environment_interference":0.0,"settings.environment_damage":1.0,
		"settings.camera_zoom":32.0,"world.combat_regions":{}}
	session.repository.commit({"id":"playable-fixture:"+str(Time.get_ticks_usec()),"set":updates,
		"append":{"campaign.completed_missions":session.content.missions.map(func(item):return item.id)}})
	session.active_build=CatalogV2.default_build("tr01");session.save_build(session.active_build)
	if branch_mode!="night": await _day_branch()
	if branch_mode!="day" and failures.is_empty(): await _night_branch()
	await _finish()

func _phase(next: String) -> void:
	phase=next;transitions.append({"branch":branch,"phase":phase,"time_s":clock_s})
	print("V22_PLAYABLE_PHASE ",region_id," ",branch," ",phase," ",snappedf(clock_s,.01))

func _check(condition: bool, label: String, detail: Dictionary={}) -> bool:
	checks.append({"branch":branch,"phase":phase,"time_s":clock_s,"label":label,"ok":condition,"detail":detail})
	if not condition: failures.append(branch+": "+label)
	return condition

func _setup(dark: bool) -> bool:
	branch="night" if dark else "day";branch_start=clock_s;_phase("setup")
	if session.flight_active:
		session.show_hangar()
		for i in 3: await process_frame
	session.repository.commit({"id":"playable-reset:"+branch+":"+str(Time.get_ticks_usec()),"set":{"world.combat_regions":{}}})
	session.night=dark;session.launch_exploration(region_id)
	if not _check(session.flight_active and session.region_id==region_id,"Real "+region_id+" exploration launched"): return false
	session.input.take_control("keyboard");session.input.mode="assisted";session.input.test_enabled=true
	session.pilot.practice=false;session.combat.auto_fire=false
	session.encounter_director.enabled=false
	session.encounter_director.configure(session.combat,session.world,session.pilot,region_id,seed_value,true)
	session.encounter_director.enabled=false
	session.combat.combat_seed=seed_value
	session.combat.combat_event.connect(_on_combat)
	session.encounter_director.encounter_event.connect(_on_director)
	selected_foe=null;entry_actor_id="";entered_legal.clear();first_entry_sample.clear()
	night_contact.clear()
	capture_warning=false;path.clear();path_goal=Vector3.INF;buildings.clear()
	var choice=_select_fixture()
	if not _check(not choice.is_empty(),"Authored regional road and cover fixture exists",{"region":region_id,"seed":seed_value}): return false
	selected_entry=choice.entry;entry_direction=choice.direction;fixture_building=choice.building;fixture_asset=choice.asset
	var start: Vector3=choice.start
	# Sole placement operation in each independent branch; no later stage teleports.
	session.pilot.global_position=start
	session.pilot.linear_velocity=Vector3.ZERO;session.pilot.angular_velocity=Vector3.ZERO
	session.pilot.hold_height=start.y;session.pilot.safe_position=start
	session.world.update_stream(start,true);session._snap_camera()
	paused=false;session.pause_reasons.clear()
	previous_position=start
	fixtures.append({"branch":branch,"region":region_id,"start":_v(start),"entry":_v(selected_entry),"entry_direction":_v(entry_direction),"seed":seed_value,
		"region_profile":_json_safe(session.encounter_director._profile),"cover_asset":fixture_asset,
		"placements":1,"actual_damage":true,"invincible":false,"auto_fire":false,
		"environment_disturbance":0,"entry_filter":"Actual camera outside + 90 px margin AND selected road corridor; all director physics/safe/distance checks remain."})
	await _settle_frames(3)
	_collect_buildings()
	_build_navigation()
	var eligible=_nearby_cover(fixture_building)
	if not _check(not eligible.is_empty(),"Loaded regional building provides real tall collision cover"): return false
	cover_box=eligible.box;cover_name=eligible.name
	fixtures.back()["cover"]={"name":cover_name,"position":_v(cover_box.position),"size":_v(cover_box.size)}
	_phase("takeoff")
	var hover=Vector3(start.x,ALTITUDE,start.z)
	var until=clock_s+4.0
	while clock_s<until and session.pilot.global_position.distance_to(hover)>1.0:
		if not await _tick(hover,false,selected_entry): return false
	if not _check(session.pilot.global_position.y>2.4,"Takeoff reached flight altitude through real input"): return false
	session.encounter_director.camera_guard=_camera_guard
	session.encounter_director.enabled=true
	session.encounter_director.rest_left=.5
	_phase("legal_patrol_entry")
	until=clock_s+13.0
	while clock_s<until and not is_instance_valid(selected_foe):
		if session.encounter_director.pending.is_empty() and session.combat.alive_count()==0:
			# Test timing fixture only; production probability/plan selection is intact.
			session.encounter_director.rest_left=minf(.5,session.encounter_director.rest_left)
		if not await _tick(hover,false,selected_entry): return false
		for actor in session.combat.enemies:
			if is_instance_valid(actor) and bool(actor.get_meta("ambient_patrol",false)) and str(actor.role)!="support":
				selected_foe=actor;entry_actor_id=str(actor.get_meta("unit_id",""));break
		if not entered_legal.is_empty() and not is_instance_valid(selected_foe):
			var roles: Array=[]
			for actor in session.combat.enemies:
				if is_instance_valid(actor): roles.append(str(actor.role))
			_check(false,"Fixed seed produced no attacking patrol unit; choose another independent seed, no replacement spawn",{"seed":seed_value,"roles":roles})
			return false
	if not _check(is_instance_valid(selected_foe),"Director materialized a real patrol before timeout",{"director":_json_safe(session.encounter_director.snapshot())}): return false
	_check(not entered_legal.is_empty() and bool(entered_legal.get("distance_ok",false)) and bool(entered_legal.get("offscreen",false)),"Patrol entered at least 45 m away outside the actual camera",entered_legal)
	_check(entry_actor_id.begins_with(region_id+"-E") and str(selected_foe.get_meta("source_kind",""))=="ambient","Patrol retains director identity and source",{"unit_id":entry_actor_id,"role":selected_foe.role})
	var natural_roles: Array=[]
	for actor in session.combat.enemies:
		if is_instance_valid(actor): natural_roles.append({"unit_id":str(actor.get_meta("unit_id","")),"role":str(actor.role)})
	fixtures.back()["natural_roles"]=natural_roles
	first_entry_sample=_actor_sample()
	await _capture("entry")
	return failures.is_empty()

func _select_fixture() -> Dictionary:
	var candidates: Array=[]
	var profile: Dictionary=session.encounter_director._profile
	var model_metadata: Dictionary={}
	var manifest=JSON.parse_string(FileAccess.get_file_as_string("res://assets/v2/streets/manifest.json"))
	if manifest is Dictionary:
		for item in manifest.get("models",[]): model_metadata[str(item.id)]=item
	for x in range(50,551,100):
		for z in range(50,451,100):
			var entry=Vector3(x,float(profile.altitude),z)
			if session.encounter_director._in_safe_space(entry): continue
			var direction: Vector3=profile.direction
			# Match the production director's authored boundary reversal exactly.
			if x>=550 and direction.x>0 or x<=50 and direction.x<0 or z>=450 and direction.z>0 or z<=50 and direction.z<0: direction=-direction
			var start=entry+direction*62;start.y=1.2
			if start.x<8 or start.x>592 or start.z<8 or start.z>492: continue
			var lateral=Vector3(-direction.z,0,direction.x)
			for item in session.world.obstacles:
				var asset=_building_asset(int(item.style))
				# Keep the validated industrial fixture stable. Other districts use
				# their own actual visual model mapping, not a universal style index.
				if region_id=="R2" and asset!="harbor_warehouse": continue
				if not model_metadata.has(asset): continue
				var metadata: Dictionary=model_metadata[asset]
				var scale_m=minf(minf(float(item.w)/float(metadata.footprint[0]),float(item.l)/float(metadata.footprint[1])),14.5/float(metadata.height))
				if float(metadata.height)*scale_m<5.6: continue
				var center=Vector3(item.x,ALTITUDE,item.z)
				var difference=center-entry
				if absf(difference.dot(lateral))<14 or absf(difference.dot(lateral))>37: continue
				if difference.dot(direction)<12 or difference.dot(direction)>57: continue
				var score=center.distance_to(Vector3(250,ALTITUDE,180))
				if region_id=="R4" and asset!="harbor_warehouse": score+=200
				if region_id in ["R1","R3"] and asset!="office_pavilion": score+=200
				candidates.append({"entry":entry,"start":start,"direction":direction,"building":center,"asset":asset,"score":score})
	candidates.sort_custom(func(a,b):return float(a.score)<float(b.score))
	return {} if candidates.is_empty() else candidates[0]

func _building_asset(style: int) -> String:
	if region_id=="R4": return "harbor_warehouse" if style%2==0 else "office_pavilion"
	if region_id=="R3": return "waterfront_cafe" if style%2==0 else "office_pavilion"
	return ["office_pavilion","waterfront_cafe","canal_apartments","harbor_warehouse"][style]

func _camera_guard(point: Vector3) -> bool:
	if Vector2(point.x-selected_entry.x,point.z-selected_entry.z).length()>12: return false
	return _actually_offscreen(point)

func _actually_offscreen(point: Vector3) -> bool:
	var camera=session.camera
	if camera.is_position_behind(point): return true
	return not root.get_visible_rect().grow(90).has_point(camera.unproject_position(point))

func _collect_buildings() -> void:
	for node in session.world.visibility_occluders:
		if is_instance_valid(node) and str(node.name).begins_with("Building_"):
			_collect_boxes(node,str(node.name))

func _collect_boxes(node: Node, building_name: String) -> void:
	if node is CollisionShape3D and node.shape is BoxShape3D and not node.disabled:
		var box: AABB=node.global_transform*AABB(-node.shape.size*.5,node.shape.size)
		buildings.append({"name":building_name,"box":box})
	for child in node.get_children(): _collect_boxes(child,building_name)

func _nearby_cover(point: Vector3) -> Dictionary:
	var choices: Array=[]
	for item in buildings:
		var box: AABB=item.box
		if box.end.y<5.4 or box.size.x<7 or box.size.z<7: continue
		var center=box.get_center();center.y=point.y
		if center.distance_to(point)>43: continue
		choices.append(item.merged({"score":center.distance_to(point)}))
	choices.sort_custom(func(a,b):return float(a.score)<float(b.score))
	return {} if choices.is_empty() else choices[0]

func _build_navigation() -> void:
	route_grid=AStarGrid2D.new();route_grid.region=Rect2i(0,0,150,125)
	route_grid.cell_size=Vector2(4,4);route_grid.offset=Vector2(2,2)
	route_grid.diagonal_mode=AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	route_grid.update()
	for item in buildings:
		var box: AABB=item.box
		if box.end.y<ALTITUDE-.7: continue
		var min_cell=_cell(box.position-Vector3(3.2,0,3.2))
		var max_cell=_cell(box.end+Vector3(3.2,0,3.2))
		for x in range(min_cell.x,max_cell.x+1):
			for z in range(min_cell.y,max_cell.y+1): route_grid.set_point_solid(Vector2i(x,z))
	# Navigation only steers inputs; it never moves actors or rewrites collision.
	path.clear();path_goal=Vector3.INF

func _cell(point: Vector3) -> Vector2i:
	return Vector2i(clampi(floori(point.x/4),0,149),clampi(floori(point.z/4),0,124))

func _free_cell(point: Vector3) -> Vector2i:
	var cell=_cell(point)
	if not route_grid.is_point_solid(cell): return cell
	for radius in range(1,5):
		var best=cell;var best_distance=INF
		for x in range(-radius,radius+1):
			for z in range(-radius,radius+1):
				var candidate=cell+Vector2i(x,z)
				if not route_grid.region.has_point(candidate) or route_grid.is_point_solid(candidate): continue
				var distance=route_grid.get_point_position(candidate).distance_squared_to(Vector2(point.x,point.z))
				if distance<best_distance: best=candidate;best_distance=distance
		if is_finite(best_distance): return best
	return cell

func _navigation_destination(point: Vector3) -> Vector3:
	if not route_grid.is_point_solid(_cell(point)): return point
	var corrected=route_grid.get_point_position(_free_cell(point))
	return Vector3(corrected.x,point.y,corrected.y)

func _waypoint(goal: Vector3) -> Vector3:
	var origin=session.pilot.global_position
	if clock_s>=path_rebuild_at or path_goal.distance_to(goal)>3:
		path_rebuild_at=clock_s+.8;path_goal=goal
		var destination=_free_cell(goal)
		path=route_grid.get_point_path(_free_cell(origin),destination)
		path_finish=_navigation_destination(goal)
	while path.size()>1 and Vector2(origin.x,origin.z).distance_to(path[0])<2.4: path.remove_at(0)
	# Four-metre A* cells are navigation samples, not braking destinations.
	# Pick a farther point only when the real swept aircraft envelope can reach it.
	# This preserves building collision instead of cutting diagonally across corners.
	if origin.distance_to(path_finish)<18 and _flight_corridor_clear(origin,path_finish): return path_finish
	var ahead=-1
	for index in path.size():
		var point=Vector3(path[index].x,goal.y,path[index].y)
		if origin.distance_to(point)>18: break
		if _flight_corridor_clear(origin,point): ahead=index
	if ahead>=0:
		var point=Vector3(path[ahead].x,goal.y,path[ahead].y)
		for i in ahead: path.remove_at(0)
		return point
	if path.size()>1: return Vector3(path[0].x,goal.y,path[0].y)
	return path_finish

func _flight_corridor_clear(from: Vector3, to: Vector3) -> bool:
	var sphere=SphereShape3D.new();sphere.radius=1.05
	var query=PhysicsShapeQueryParameters3D.new();query.shape=sphere
	query.transform=Transform3D(Basis.IDENTITY,from);query.motion=to-from
	query.collision_mask=1|4|8|32;query.exclude=[session.pilot.get_rid()]
	var space=session.world.get_world_3d().direct_space_state
	if not space.intersect_shape(query,1).is_empty(): return false
	if from.distance_to(to)<.05: return true
	var sweep=space.cast_motion(query)
	return sweep.size()>0 and float(sweep[0])>.995

func _tick(goal: Vector3, firing: bool, face: Vector3) -> bool:
	if clock_s>=limit_s or Time.get_ticks_msec()-wall_started>int((limit_s+60)*1000):
		_check(false,"Global sample watchdog exceeded",{"limit_s":limit_s});return false
	if not session.flight_active or not is_instance_valid(session.pilot) or not session.pilot.enabled:
		_check(false,"Pilot remained active during the sample");return false
	var pilot=session.pilot
	var waypoint=_waypoint(goal)
	control_goal=goal;control_waypoint=waypoint
	var offset=waypoint-pilot.global_position;offset.y=0
	var desired=offset.normalized()*minf(7.5,offset.length()*1.2)
	# Convert world-space intention into the same body-relative axes as a controller.
	var right=Basis(Vector3.UP,pilot.heading).x
	var forward=-Basis(Vector3.UP,pilot.heading).z
	var motion=desired/maxf(1,float(pilot.stats.speed_mps))
	var facing=face-pilot.global_position;facing.y=0
	var yaw_error=wrapf(atan2(-facing.x,-facing.z)-pilot.heading,-PI,PI) if facing.length()>.1 else 0.0
	var vertical=clampf((goal.y-pilot.global_position.y)*.45-pilot.linear_velocity.y*.18,-.65,.65)
	var held: Array=["fire"] if firing else []
	if offset.length()<.7 and Vector2(pilot.linear_velocity.x,pilot.linear_velocity.z).length()>.35: held.append("brake")
	session.input.test_frame={"axes":{"left_x":clampf(-yaw_error*1.2,-.8,.8),"left_y":vertical,
		"right_x":motion.dot(right),"right_y":motion.dot(forward)},"held":held,"edges":[]}
	await physics_frame
	clock_s+=1.0/maxi(1,Engine.physics_ticks_per_second)
	if not is_instance_valid(session.pilot): return false
	total_distance+=previous_position.distance_to(session.pilot.global_position)
	previous_position=session.pilot.global_position
	if clock_s>=next_sample:
		next_sample=clock_s+SAMPLE_INTERVAL;_sample()
	if not session.pilot.global_position.is_finite():
		_check(false,"Pilot position remained finite");return false
	return true

func _day_branch() -> void:
	if not await _setup(false): return
	await _combat_chain()

func _combat_chain() -> void:
	_phase("approach_and_receive")
	var until=clock_s+22.0
	var hold=Vector3.INF
	var before=float(session.pilot.health)
	var injury_after_tick=Engine.get_physics_frames()
	var received: Dictionary={}
	while clock_s<until and received.is_empty():
		if not is_instance_valid(selected_foe): break
		if _has_warning() and not hold.is_finite():
			hold=session.pilot.global_position;hold.y=ALTITUDE
			await _capture("warning")
		var goal=hold if hold.is_finite() else selected_foe.global_position+entry_direction*14
		goal.y=ALTITUDE
		if not await _tick(goal,false,selected_foe.global_position): return
		received=_pilot_receipt(injury_after_tick)
	if not _check(not received.is_empty() and session.pilot.health<before,"A hostile physical projectile caused a real pilot injury",{"health_before":before,"health_after":session.pilot.health,"receipt":received}): return
	_check(_complete_warning(received),"Pilot injury followed a complete matching attack warning",{"warning_id":received.get("warning_id",0)})
	if not await _hover_for(.20): return
	await _capture("hit")
	_phase("building_cover")
	var cover_plan=_plan_cover_route()
	if not _check(not cover_plan.is_empty(),"A real building has two blocked endpoints and a reachable collision-safe navigation route",{"enemy":_v(selected_foe.global_position),"pilot":_v(session.pilot.global_position)}): return
	cover_box=cover_plan.box;cover_name=str(cover_plan.building)
	var route: Array[Vector3]=[]
	for point in cover_plan.waypoints: route.append(point)
	var route_index=0
	cover_plans.append({"branch":branch,"building":cover_name,"enemy_at_plan":_v(selected_foe.global_position),"pilot_at_plan":_v(session.pilot.global_position),"approach_path_m":cover_plan.path_length,"waypoints":route.map(func(point):return _v(point))})
	fixtures.back()["active_cover"]={"name":cover_name,"position":_v(cover_box.position),"size":_v(cover_box.size)}
	var hidden_start=-1.0
	var hidden_position=Vector3.ZERO
	var remembered=Vector3.ZERO
	var hidden_travel=0.0
	var memory_drift=0.0
	var witness=false
	var lost=false
	var longest_hidden=0.0
	var best_hidden_travel=0.0
	var factory_hidden_s=0.0
	var previously_seen=bool(selected_foe.brain.seen)
	var cover_observations={"reacquisition_count":0,"last_loss":{},"transitions":[],"timeout_s":45.0}
	cover_plans.back()["perception"]=cover_observations
	if not previously_seen:
		cover_observations.last_loss=_cover_perception_observation(_factory_blocks(selected_foe.global_position,session.pilot.global_position))
	until=clock_s+45.0
	while clock_s<until and not lost:
		if not is_instance_valid(selected_foe): break
		if session.pilot.global_position.distance_to(route[route_index])<1.6:
			if route_index==0: route_index=1
			elif route_index==1: route_index=2 if witness else 0
		var escape_goal=route[route_index]
		if not await _tick(escape_goal,false,escape_goal): return
		var brain=selected_foe.brain
		var blocked=_factory_blocks(selected_foe.global_position,session.pilot.global_position)
		if bool(brain.seen)!=previously_seen:
			var observation=_cover_perception_observation(blocked)
			cover_observations.transitions.append(observation)
			if brain.seen: cover_observations.reacquisition_count+=1
			else: cover_observations.last_loss=observation
			previously_seen=bool(brain.seen)
		if not brain.seen and brain.memory_age>.16 and (blocked or hidden_start>=0):
			if hidden_start<0:
				hidden_start=clock_s;hidden_position=session.pilot.global_position;remembered=brain.last_seen_position
			if blocked: factory_hidden_s+=1.0/maxi(1,Engine.physics_ticks_per_second)
			hidden_travel=hidden_position.distance_to(session.pilot.global_position)
			memory_drift=maxf(memory_drift,remembered.distance_to(brain.last_seen_position))
			longest_hidden=maxf(longest_hidden,clock_s-hidden_start);best_hidden_travel=maxf(best_hidden_travel,hidden_travel)
			if factory_hidden_s>1.0 and clock_s-hidden_start>1.8 and hidden_travel>3:
				witness=true
				if not capture_warning: capture_warning=true;await _capture("building_cover")
		else:
			hidden_start=-1;factory_hidden_s=0
		# A valid wall-cover witness survives legitimate reacquisition. Later loss
		# through range/FOV still has to reach the real brain's finite-memory state.
		if witness and memory_drift<.05 and not brain.seen and str(brain.state) in ["lost","patrol"] and float(brain.memory_age)>=8:
			lost=true
			cover_observations["lost_observation"]=_cover_perception_observation(blocked)
	if not _check(witness and memory_drift<.05,"Actual regional building blocks sight while hidden movement never updates enemy memory",
		{"building":cover_name,"max_hidden_s":longest_hidden,"hidden_motion_m":best_hidden_travel,"memory_drift_m":memory_drift}): return
	if not _check(lost,"Enemy lost the target after its finite memory expired",cover_observations): return
	_phase("reapproach_and_destroy")
	until=clock_s+22.0
	var kills_before=session.combat.kills
	while clock_s<until and is_instance_valid(selected_foe) and selected_foe.hp>0:
		var toward=selected_foe.global_position-session.pilot.global_position;toward.y=0
		var goal=selected_foe.global_position-toward.normalized()*11;goal.y=ALTITUDE
		if not await _tick(goal,true,selected_foe.global_position): return
	var destroyed=_destroyed_receipt(entry_actor_id)
	_check(not destroyed.is_empty() and session.combat.kills>kills_before,"Reapproach and real player fire destroyed the same patrol unit",{"unit_id":entry_actor_id,"receipt":destroyed})
	_check(_friendly_hit_exists(entry_actor_id),"Destruction has preceding real player damage receipts")
	await _capture("destroyed")
	if not destroyed.is_empty():
		_phase("destruction_aftermath")
		var initial_wrecks=_wreck_sample(0)
		var full_serial=-1
		var initial_height=0.0
		var death_point=Vector3(destroyed.position[0],destroyed.position[1],destroyed.position[2])
		for record in initial_wrecks:
			var wreck_point=Vector3(record.position[0],record.position[1],record.position[2])
			if bool(record.full) and float(record.life)>6.4 and wreck_point.distance_to(death_point)<4 and int(record.serial)>full_serial:
				full_serial=int(record.serial);initial_height=float(record.position[1])
		var elapsed=0.0
		for mark in [.3,1.0,2.0]:
			if not await _hover_for(float(mark)-elapsed): return
			elapsed=float(mark)
			_wreck_sample(elapsed)
			await _capture("wreck_"+str(int(roundf(elapsed*1000)))+"ms")
		var final_wrecks: Array=wreck_samples.back().wrecks
		var retained=false;var fell=false
		for record in final_wrecks:
			if int(record.serial)==full_serial:
				retained=true;fell=float(record.position[1])<initial_height-.2 or bool(record.collided)
		_check(full_serial>=0 and retained and fell,"Destroyed hull falls physically and remains for at least two seconds",{"serial":full_serial,"retained":retained,"fell_or_collided":fell})
	branch_results.append({"branch":branch,"region":region_id,"seconds":clock_s-branch_start,"patrol_id":entry_actor_id,
		"injury":received,"target_lost":lost,"memory_drift_m":memory_drift,"kill":destroyed,"pilot_health":session.pilot.health,
		"night_contact":night_contact.duplicate(true),"full_chain":not destroyed.is_empty() and lost and witness})

func _hover_for(seconds: float) -> bool:
	var goal=session.pilot.global_position
	var face=goal-Basis(Vector3.UP,session.pilot.heading).z*10
	var until=clock_s+seconds
	while clock_s+.000001<until:
		if not await _tick(goal,false,face): return false
	return true

func _wreck_sample(after_s: float) -> Array:
	var records: Array=[]
	if is_instance_valid(session.combat_feedback):
		for slot in session.combat_feedback.get("_wrecks"):
			if not bool(slot.active) or not is_instance_valid(slot.body): continue
			records.append({"serial":slot.serial,"full":slot.full,"asset":slot.model_id,"life":slot.life,
				"position":_v(slot.body.global_position),"velocity":_v(slot.body.linear_velocity),
				"collided":slot.collided,"visible":slot.body.visible})
	wreck_samples.append({"branch":branch,"after_s":after_s,"time_s":clock_s,"wrecks":records})
	return records

func _plan_cover_route() -> Dictionary:
	# Read actual post-hit positions. Expanded corners are route geometry, not
	# evidence of occlusion: an observer beside a face sees all four such corners.
	var observer: Vector3=selected_foe.global_position
	var origin=session.pilot.global_position
	var options: Array=[]
	for item in buildings:
		var box: AABB=item.box
		if box.end.y<5.4 or box.size.x<7 or box.size.z<7: continue
		var center=box.get_center();center.y=ALTITUDE
		if origin.distance_to(center)>60: continue
		var bearing=center-observer;bearing.y=0
		if bearing.length()<4: continue
		for angle in [0.0,-.20,.20]:
			var away=bearing.normalized().rotated(Vector3.UP,float(angle))
			var half_size=box.size*.5
			var face_distance=minf(half_size.x/maxf(.001,absf(away.x)),half_size.z/maxf(.001,absf(away.z)))
			var tangent=Vector3(-away.z,0,away.x)
			for depth in [8.0,12.0,16.0]:
				var shadow=center+away*(face_distance+float(depth))
				var a=_navigation_destination(shadow+tangent*4)
				var b=_navigation_destination(shadow-tangent*4)
				if a.distance_to(b)<4 or not _flight_corridor_clear(a,a) or not _flight_corridor_clear(b,b): continue
				if not _building_blocks(str(item.name),observer,a) or not _building_blocks(str(item.name),observer,b): continue
				var length_a=_grid_route_length(origin,a);var length_b=_grid_route_length(origin,b)
				var cross_length=_grid_route_length(a,b)
				if not is_finite(length_a) or not is_finite(length_b) or not is_finite(cross_length): continue
				# The lane must be directly flyable, so the hidden-motion witness
				# cannot be obtained by routing around to an exposed side instead.
				if not _flight_corridor_clear(a,b): continue
				if length_b<length_a:
					var swap=a;a=b;b=swap
				var length=minf(length_a,length_b)
				if length>80: continue
				var escape=center+away*88;escape.y=ALTITUDE
				escape.x=clampf(escape.x,8,592);escape.z=clampf(escape.z,8,492)
				escape=_navigation_destination(escape)
				var score=length+cross_length*.2+(0 if str(item.name)==cover_name else 12)
				options.append({"building":str(item.name),"box":box,"waypoints":[a,b,escape],"path_length":length,"score":score})
	options.sort_custom(func(a,b):return float(a.score)<float(b.score))
	return {} if options.is_empty() else options[0]

func _grid_route_length(from: Vector3, to: Vector3) -> float:
	var route=route_grid.get_point_path(_free_cell(from),_free_cell(to))
	if route.is_empty(): return INF
	var length=Vector2(from.x,from.z).distance_to(route[0])
	for i in range(1,route.size()): length+=route[i-1].distance_to(route[i])
	return length+route[route.size()-1].distance_to(Vector2(to.x,to.z))

func _factory_blocks(from: Vector3, to: Vector3) -> bool:
	return _building_blocks(cover_name,from,to)

func _building_blocks(building_name: String, from: Vector3, to: Vector3) -> bool:
	var query=PhysicsRayQueryParameters3D.create(from,to,1)
	var hit=session.world.get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty(): return false
	var node: Node=hit.collider
	while node!=null and node!=session.world:
		if str(node.name)==building_name: return true
		node=node.get_parent()
	return false

func _night_branch() -> void:
	if not await _setup(true): return
	_phase("night_hidden")
	var hidden=not session.night_point_visible(selected_foe.global_position)
	_check(hidden,"Distant patrol remains outside night illumination",_actor_sample())
	_check(session.combat.nearest_target(90)==null,"Night targeting cannot acquire the unlit patrol")
	await _capture("night_hidden")
	_phase("night_approach")
	var until=clock_s+20.0
	var appeared=false
	var warned=false
	while clock_s<until and not warned:
		if not is_instance_valid(selected_foe): break
		var goal=selected_foe.global_position+entry_direction*11;goal.y=ALTITUDE
		if not await _tick(goal,false,selected_foe.global_position): return
		if session.night_point_visible(selected_foe.global_position):
			if not appeared: appeared=true;await _capture("night_local_light")
			warned=_has_warning()
	_check(appeared,"Actual flight brings patrol into a local night light pool")
	_check(warned,"Night patrol notices and warns only after close local contact")
	if is_instance_valid(selected_foe):
		_check(session.combat.nearest_target(36)==selected_foe or session.combat.nearest_target(36)!=null,"Illuminated contact becomes targetable after approach")
	await _capture("night_warning")
	night_contact={"initial_hidden":hidden,"local_visible":appeared,"warning":warned}
	if not failures.is_empty(): return
	# The same production chain now runs at night: no damage/perception overrides,
	# no daytime lighting, and no direct fire calls to compensate for darkness.
	await _combat_chain()

func _cover_corners() -> Array[Vector3]:
	var minp=cover_box.position-Vector3(6,0,6);var maxp=cover_box.end+Vector3(6,0,6)
	return [Vector3(minp.x,ALTITUDE,maxp.z),Vector3(maxp.x,ALTITUDE,maxp.z),
		Vector3(maxp.x,ALTITUDE,minp.z),Vector3(minp.x,ALTITUDE,minp.z)]

func _on_combat(event: Dictionary) -> void:
	var record=event.duplicate(true);record.probe_time_s=clock_s;record.branch=branch;record.probe_phase=phase
	receipts.append(record)

func _on_director(event: Dictionary) -> void:
	var record=event.duplicate(true);record.probe_time_s=clock_s;record.branch=branch
	director_events.append(record)
	if str(event.get("kind",""))=="patrol_entered" and entered_legal.is_empty():
		var p=Vector3(event.position[0],event.position[1],event.position[2])
		var distance=Vector2(p.x-session.pilot.global_position.x,p.z-session.pilot.global_position.z).length()
		entered_legal={"position":_v(p),"pilot":_v(session.pilot.global_position),"distance_m":distance,
			"distance_ok":distance>=45,"offscreen":_actually_offscreen(p),"count":event.get("count",0),"entry_id":event.get("entry_id","")}

func _has_warning() -> bool:
	for event in receipts:
		if event.branch==branch and event.kind=="warning_started" and event.source_id==entry_actor_id: return true
	return false

func _pilot_receipt(after_tick: int=-1) -> Dictionary:
	for event in receipts:
		if event.branch==branch and int(event.get("tick",0))>after_tick and event.kind=="hit" and bool(event.get("pilot_target",false)) and float(event.get("damage",0))>0 and int(event.get("warning_id",0))>0:
			return event
	return {}

func _complete_warning(receipt: Dictionary) -> bool:
	for warning in receipts:
		if warning.branch!=branch or warning.kind!="warning_started" or int(warning.warning_id)!=int(receipt.get("warning_id",0)): continue
		var duration=1.25 if str(warning.get("role","")) in ["charger","suppressor","boss"] else 1.0
		for shot in receipts:
			if shot.branch==branch and shot.kind=="shot" and not bool(shot.get("friendly",true)) and int(shot.warning_id)==int(warning.warning_id):
				return int(shot.tick)-int(warning.tick)>=int((duration-.02)*Engine.physics_ticks_per_second) and int(receipt.tick)>=int(shot.tick)
	return false

func _destroyed_receipt(id: String) -> Dictionary:
	for event in receipts:
		if event.branch==branch and event.kind=="destroyed" and str(event.target_id)==id and bool(event.get("killed",false)): return event
	return {}

func _friendly_hit_exists(id: String) -> bool:
	for event in receipts:
		if event.branch==branch and event.kind=="hit" and str(event.target_id)==id and bool(event.get("friendly",false)) and float(event.get("damage",0))>0: return true
	return false

func _cover_perception_observation(blocked: bool) -> Dictionary:
	var brain=selected_foe.brain
	var difference: Vector3=session.pilot.global_position-selected_foe.global_position
	var distance_m=difference.length()
	var horizontal=Vector3(difference.x,0,difference.z).normalized()
	var in_range=distance_m<=float(brain.profile.range)
	var in_fov=distance_m<=4.0 or Vector3(-sin(brain.heading),0,-cos(brain.heading)).dot(horizontal)>=cos(deg_to_rad(float(brain.profile.fov)))
	var illumination_allowed=session.enemy_perception_visible(selected_foe.global_position,session.pilot.global_position)
	var line_clear=session.combat.line_clear(selected_foe.global_position,session.pilot.global_position,selected_foe.get_rid(),session.pilot.get_rid())
	var reason="observed" if brain.seen else "no_contact_between_sense_ticks"
	if not brain.seen:
		if not in_range: reason="perception_range"
		elif session.night and distance_m>22.0: reason="night_range"
		elif not illumination_allowed: reason="night_visibility"
		elif not in_fov: reason="field_of_view"
		elif blocked: reason="selected_building_occlusion"
		elif not line_clear: reason="other_physical_occlusion"
	# Gate values are observations at this frame, not a replacement for sensing.
	return {"time_s":clock_s,"seen":brain.seen,"state":brain.state,"memory_age":brain.memory_age,
		"reason_observed":reason,"distance_m":distance_m,"in_range":in_range,"in_fov":in_fov,
		"illumination_allowed":illumination_allowed,"line_clear":line_clear,"selected_building_blocks":blocked,
		"pilot":_v(session.pilot.global_position),"enemy":_v(selected_foe.global_position),"last_seen":_v(brain.last_seen_position)}

func _actor_sample() -> Dictionary:
	if not is_instance_valid(selected_foe): return {"valid":false,"unit_id":entry_actor_id}
	var brain=selected_foe.brain
	return {"valid":true,"unit_id":entry_actor_id,"position":_v(selected_foe.global_position),"velocity":_v(selected_foe.velocity),
		"hp":selected_foe.hp,"state":brain.state,"seen":brain.seen,"memory_age":brain.memory_age,
		"last_seen":_v(brain.last_seen_position),"telegraph":selected_foe.telegraph,
		"night_visible":session.night_point_visible(selected_foe.global_position),"offscreen":_actually_offscreen(selected_foe.global_position)}

func _sample() -> void:
	trajectory.append({"time_s":clock_s,"branch":branch,"phase":phase,"pilot":_v(session.pilot.global_position),
		"velocity":_v(session.pilot.linear_velocity),"heading":session.pilot.heading,"health":session.pilot.health,
		"damage_taken":session.pilot.damage_taken,"collision_count":session.pilot.collision_count,
		"input":session.input.test_frame.duplicate(true),"navigation_goal":_v(control_goal),"steering_waypoint":_v(control_waypoint),
		"selected_building_blocks":_factory_blocks(selected_foe.global_position,session.pilot.global_position) if is_instance_valid(selected_foe) and not cover_name.is_empty() else false,"enemy":_actor_sample()})

func _settle_frames(count: int) -> void:
	for i in count: await physics_frame

func _capture(label: String) -> void:
	if not capture: return
	await process_frame
	RenderingServer.viewport_set_update_mode(root.get_viewport_rid(),RenderingServer.VIEWPORT_UPDATE_ALWAYS)
	RenderingServer.force_draw(false)
	var image=root.get_texture().get_image()
	var filename=region_id+"_"+branch+"_"+label+".png"
	var result=image.save_png(output+"/"+filename)
	var unique: Dictionary={}
	for x in range(int(image.get_width()*.15),int(image.get_width()*.85),8):
		for y in range(int(image.get_height()*.18),int(image.get_height()*.82),8): unique[image.get_pixel(x,y).to_html(false)]=true
	var valid=result==OK and image.get_width()>=640 and unique.size()>=12
	_check(valid,"Real GPU capture contains rendered scene: "+label,{"unique_colors":unique.size(),"width":image.get_width(),"height":image.get_height()})
	screenshots.append({"branch":branch,"phase":phase,"label":label,"path":output+"/"+filename,
		"sha256":FileAccess.get_sha256(output+"/"+filename),"real_gpu":true,"unique_colors":unique.size(),
		"pilot_health":session.pilot.health,"pilot_damage_taken":session.pilot.damage_taken,"time_s":clock_s,
		"feedback":_json_safe(session.combat_feedback.diagnostics()) if is_instance_valid(session.combat_feedback) else {}})

static func _v(point: Vector3) -> Array: return [point.x,point.y,point.z]

func _json_safe(value: Variant) -> Variant:
	if value is Vector3: return _v(value)
	if value is Dictionary:
		var result: Dictionary={}
		for key in value: result[str(key)]=_json_safe(value[key])
		return result
	if value is Array:
		var result: Array=[]
		for item in value: result.append(_json_safe(item))
		return result
	return value

func _finish() -> void:
	if is_instance_valid(session.input): session.input.test_frame={"axes":{},"held":[],"edges":[]}
	for expected in (["day","night"] if branch_mode=="both" else [branch_mode]):
		var complete=false
		for result in branch_results:
			if str(result.branch)==str(expected) and bool(result.get("full_chain",false)): complete=true
		_check(complete,"Requested "+str(expected)+" branch completed its full combat chain")
	var changed: Array=[]
	for id in source_hashes:
		var file="res://scripts_tools/v22_combat_playable_probe.gd" if id=="probe" else "res://scripts/v2/"+id+".gd"
		if FileAccess.get_sha256(file)!=source_hashes[id]: changed.append(id)
	_check(changed.is_empty(),"Production and probe source hashes stayed stable during the run",{"changed":changed})
	var report={"schema":2,"region":region_id,"ok":failures.is_empty(),"checks":checks,"failures":failures,
		"simulated_seconds":clock_s,"wall_seconds":(Time.get_ticks_msec()-wall_started)/1000.0,
		"branch_mode":branch_mode,"seed":seed_value,"source_sha256":source_hashes,"fixtures":fixtures,
		"branches":branch_results,"stage_transitions":transitions,"combat_receipts":receipts,
		"director_events":director_events,"trajectory":trajectory,"screenshots":screenshots,"wreck_samples":wreck_samples,"cover_plans":cover_plans,
		"flown_distance_m":total_distance,"renderer":DisplayServer.get_name(),
		"graphics_evidence":capture,"direct_damage_injection":false,"post_setup_teleport":false,
		"evidence_scope":"Real GameSession "+region_id+" city, production director legal entry, production flight/input/AI/projectiles/damage. Each selected daylight/night branch requires the complete injury-cover-disengagement-destruction chain. Optional captures are real GPU frames. Scripted test controller is not human comfort, phone/controller hardware, stochastic population-frequency or sustained-performance acceptance."}
	var file=FileAccess.open(output+"/report.json",FileAccess.WRITE)
	if file==null: push_error("Unable to save playable evidence report.");quit(2);return
	file.store_string(JSON.stringify(_json_safe(report),"\t"));file.close()
	print("V22_COMBAT_PLAYABLE_REPORT ",JSON.stringify({"region":region_id,"ok":failures.is_empty(),"checks":checks.size(),"failures":failures,
		"seconds":clock_s,"report":output+"/report.json","captures":screenshots.size()}))
	if is_instance_valid(session.phone): session.phone.stop_server()
	session.queue_free()
	for i in 3: await process_frame
	quit(0 if failures.is_empty() else 1)

