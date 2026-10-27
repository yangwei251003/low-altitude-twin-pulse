extends SceneTree

var checks = 0
var failures: Array[String] = []
var reports: Array[Dictionary] = []
var prepared_events: Array[Dictionary] = []
var discovery_events: Array[String] = []
var completed: Array = []
var scene: Node3D
var world: RegionWorldV2
var pilot: FlightBodyV2
var rebuilds = 0

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var content = CatalogV2.content()
	for mission in content.missions: completed.append(str(mission.id))
	scene = Node3D.new()
	root.add_child(scene)
	pilot = FlightBodyV2.new()
	pilot.configure(CatalogV2.resolve_build(CatalogV2.default_build("tr01")))
	pilot.freeze = true
	scene.add_child(pilot)
	pilot.set_physics_process(false)
	for region in content.regions:
		for poi in region.pois:
			if bool(poi.hidden): await _test_secret(region,poi)
	_expect(reports.size() == 24,"content contains exactly 24 exercised secrets")
	var output = "res://artifacts/v2/secrets_predicates.json"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://artifacts/v2"))
	var file = FileAccess.open(output,FileAccess.WRITE)
	_expect(file != null,"secret predicate report is writable")
	var report = {
		"suite":"secrets_scene_action_predicates",
		"engine":Engine.get_version_info().string,
		"source_sha256":content.get("_source_sha256",""),
		"evidence":"Automated predicate fixture using real RegionWorldV2.work_secrets and a frozen FlightBodyV2. Places the body, equips catalog-valid tools, injects interaction and velocity, and JSON-round-trips secret_steps before rebuilding the world. Does not directly complete secrets. NOT actual flight, manual gameplay, collision, graphics, timing feasibility, physical controller, or service UI evidence. Mission progression and free-tool ownership are explicit fixtures; M05/M06 briefing-tool exceptions are tested separately from strict completed-mission gates.",
		"checks":checks,"failed":failures.size(),"failures":failures,
		"secrets":reports,"world_rebuilds":rebuilds
	}
	if file != null:
		file.store_string(JSON.stringify(report,"  "))
		file.close()
	print("SECRETS_V2_SUMMARY "+JSON.stringify({"checks":checks,"failed":failures.size(),"failures":failures,"secrets":reports.size(),"world_rebuilds":rebuilds}))
	scene.queue_free()
	await process_frame
	await process_frame
	quit(0 if failures.is_empty() else 1)

func _rebuild(region: Dictionary, saved: Dictionary, night: bool) -> void:
	if is_instance_valid(world):
		world.queue_free()
		await process_frame
	world = RegionWorldV2.new()
	world.configure(region,night,saved)
	world.completed_missions = completed.duplicate()
	world.discovered.connect(func(poi: Dictionary): discovery_events.append(str(poi.id)))
	world.secret_prepared.connect(func(id: String, step: int): prepared_events.append({"id":id,"step":step}))
	scene.add_child(world)
	world.set_process(false)
	rebuilds += 1
	await process_frame

func _equip(tool_id: String, label: String) -> void:
	var build = CatalogV2.default_build("tr01")
	if tool_id == "searchlight_base": build.slots.utility = tool_id
	elif tool_id != "interact": build.slots.tool = tool_id
	var resolved = CatalogV2.resolve_build(build)
	_expect(bool(resolved.valid),label+" fixture tool configuration is physically legal")
	if resolved.valid: pilot.configure(resolved)

func _place(point: Vector3, interact = true, speed = 0.0) -> void:
	pilot.global_position = point
	pilot.linear_velocity = Vector3(speed,0,0)
	pilot.angular_velocity = Vector3.ZERO
	pilot.command = {"active":true,"interact":interact}

func _work(seconds: float) -> void:
	world.work_secrets(pilot,seconds)

func _index(id: String) -> int:
	return int(world.secret_steps.get(id,0))

func _prepared_count(id: String) -> int:
	var count = 0
	for event in prepared_events:
		if event.id == id: count += 1
	return count

func _discovered_count(id: String) -> int:
	return discovery_events.count(id)

func _bearing_valid(point: Vector3, origin: Vector3, step: Dictionary) -> bool:
	if not step.has("bearing_deg"): return true
	var bearing = rad_to_deg(atan2(point.x-origin.x,point.z-origin.z))
	return absf(wrapf(bearing-float(step.bearing_deg),-180,180)) < 25

func _point_for_step(origin: Vector3, step: Dictionary, bearing_valid = true) -> Dictionary:
	var offset: Array = step.get("offset_xz_m",[0,0])
	var seat = origin+Vector3(offset[0],2.8,offset[1])
	var radius = float(step.radius_m)
	if _bearing_valid(seat,origin,step) == bearing_valid: return {"valid":true,"point":seat}
	# Search the declared workspace, not a substituted completion position.
	for x in range(-16,17):
		for z in range(-16,17):
			var point = seat+Vector3(x*radius/16.0,0,z*radius/16.0)
			if Vector2(point.x-seat.x,point.z-seat.z).length() >= radius: continue
			if point.distance_to(origin) >= 14.0: continue
			if _bearing_valid(point,origin,step) == bearing_valid: return {"valid":true,"point":point}
	return {"valid":false,"point":seat}

func _unchanged(id: String, index: int, events: int, label: String) -> void:
	_expect(_index(id) == index and _prepared_count(id) == events and _discovered_count(id) == 0,label)

func _test_secret(region: Dictionary, poi: Dictionary) -> void:
	var id = str(poi.id)
	var steps: Array = poi.get("discovery_steps",[])
	var baseline_failures = failures.size()
	await _rebuild(region,{},false)
	var origin = world.poi_position(id)
	_expect(not steps.is_empty(),id+" has executable discovery steps")
	if steps.is_empty():
		reports.append({"id":id,"completed":false,"steps":0})
		return
	_place(origin+Vector3.UP*2.8,false)
	world.scan_nearby(pilot.global_position,1.0,1000.0)
	_expect(id not in world.known and _discovered_count(id) == 0,id+" passive nearby scanning never reveals a secret")
	var required = str(poi.get("discovery_requires_mission",""))
	var night_only = bool(poi.get("discovery_night_only",false))
	var access_policy = "none" if required.is_empty() else "completed_mission"
	for i in range(steps.size()):
		var step: Dictionary = steps[i]
		var label = id+" step "+str(i+1)
		var tool_id = str(step.tool_id)
		var duration = float(step.duration_s)
		var point_result = _point_for_step(origin,step)
		_expect(bool(point_result.valid),label+" radius and bearing have a reachable intersection")
		if not point_result.valid: break
		var point: Vector3 = point_result.point
		_equip(tool_id,label)
		_place(point)
		var before = _prepared_count(id)
		if i == 0 and not required.is_empty():
			world.completed_missions.clear()
			world.night = night_only
			if required in ["M05","M06"]:
				access_policy = "completed_mission_or_granted_briefing_tool"
				_equip("interact",label+" before briefing tool grant")
				_work(duration+1.0)
				_unchanged(id,i,before,label+" missing mission and missing briefing tool cannot unlock")
				_equip(tool_id,label+" granted briefing tool")
				_work(duration*0.25)
				_expect(world.secret_dwell > 0 and _index(id) == i,label+" granted briefing tool permits preparation before mission completion")
				_place(point,false)
				_work(0.1)
			else:
				_work(duration+1.0)
				_unchanged(id,i,before,label+" matching tool cannot bypass the completed-mission gate")
			world.completed_missions = completed.duplicate()
		if night_only:
			world.night = false
			_place(point)
			_work(duration+1.0)
			_unchanged(id,i,before,label+" daylight cannot satisfy the night-only gate")
		world.night = night_only
		_place(point,false)
		_work(duration+1.0)
		_unchanged(id,i,before,label+" correct location and tool without held interaction do not advance")
		if tool_id != "interact":
			_equip("hook_base" if tool_id == "scan_base" else "scan_base",label+" incorrect tool")
			_place(point)
			_work(duration+1.0)
			_unchanged(id,i,before,label+" wrong tool cannot advance")
			_equip(tool_id,label+" restored tool")
		var offset: Array = step.get("offset_xz_m",[0,0])
		var outside = origin+Vector3(offset[0]+float(step.radius_m)+0.5,2.8,offset[1])
		_place(outside)
		_work(duration+1.0)
		_unchanged(id,i,before,label+" outside this step's workspace cannot advance")
		if step.has("bearing_deg"):
			var wrong_bearing = _point_for_step(origin,step,false)
			_expect(bool(wrong_bearing.valid),label+" bearing-negative fixture remains inside the radius")
			if wrong_bearing.valid:
				_place(wrong_bearing.point)
				_work(duration+1.0)
				_unchanged(id,i,before,label+" incorrect bearing inside radius cannot advance")
		_place(point,true,float(step.max_speed_mps)+0.1)
		_work(duration+1.0)
		_unchanged(id,i,before,label+" passing at excessive speed cannot advance")
		_place(point)
		_work(duration*0.4)
		_unchanged(id,i,before,label+" a short held interaction is insufficient")
		_expect(world.secret_dwell > 0,label+" valid held interaction accumulates dwell")
		_place(point,false)
		_work(0.1)
		_expect(is_zero_approx(world.secret_dwell),label+" releasing interaction resets dwell")
		_place(point)
		_work(duration*0.6)
		_unchanged(id,i,before,label+" interrupted dwell cannot be added together")
		_place(origin+Vector3(30,2.8,30))
		_work(0.1)
		_expect(is_zero_approx(world.secret_dwell),label+" merely passing through then leaving resets dwell")
		_place(point)
		_work(duration-0.1)
		_unchanged(id,i,before,label+" full dwell is required after returning")
		_work(0.11)
		_expect(_index(id) == i+1 and _prepared_count(id) == before+1,label+" actual work_secrets emits exactly one prepared step")
		_expect(_discovered_count(id) == (1 if i+1 == steps.size() else 0),label+" discovery occurs only after the final ordered step")
		var saved: Dictionary = JSON.parse_string(JSON.stringify({"secret_steps":world.secret_steps,"discovered_pois":world.known}))
		var before_rebuild = _prepared_count(id)
		await _rebuild(region,saved,night_only)
		_expect(_index(id) == i+1,label+" JSON checkpoint survives world reconstruction")
		_expect(_prepared_count(id) == before_rebuild,label+" reconstruction does not replay prepared signals")
		if i+1 < steps.size():
			_expect(id not in world.known and is_zero_approx(world.secret_dwell),label+" next step resumes undiscovered with fresh dwell")
	var finished = id in world.known
	_expect(finished,id+" all declared discovery steps complete")
	if finished:
		var prepared_before = _prepared_count(id)
		var discovered_before = _discovered_count(id)
		_place(_point_for_step(origin,steps.back()).point)
		_work(float(steps.back().duration_s)*3.0)
		world.scan_nearby(pilot.global_position,1.0,1000.0)
		_expect(_prepared_count(id) == prepared_before and _discovered_count(id) == discovered_before,id+" discovered secret cannot emit again after world reconstruction")
		_expect(world.known.count(id) == 1,id+" discovered ID is stored exactly once")
	reports.append({"id":id,"region_id":region.id,"steps":steps.size(),"completed_steps":_index(id),"completed":finished,"night_only":night_only,"mission_access":access_policy,"required_mission":required,"prepared_events":_prepared_count(id),"discovery_events":_discovered_count(id),"failed":failures.size()-baseline_failures})

func _expect(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures.append(label)
		push_error("SECRETS_V2_FAIL "+label)
