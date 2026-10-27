extends Node
## Acceptance controller: ordinary keys and original FlightBody commands only.
## Never assigns pose, velocity, HP, clock, rewards, task state or Store data.
const Pilot = preload("res://scripts/v3/qa/twin_normal_flight_pilot.gd")
const Regions = preload("res://scripts/v3/world/twin_region_catalog.gd")
const Rules = preload("res://scripts/v3/gameplay/twin_ability_rules.gd")
const RouteSearch = preload("res://scripts_tools/v3/acceptance_native_route.gd")
var session: Node
var pilot: RefCounted
var events: Array = []
var failures: Array = []
var checks: Array = []
var started := 0
var serial := 0
var running := false
var fire := false
var distance := 0.0
var previous := Vector3.ZERO
var previous_region := ""
var previous_body := 0
var previous_branch := ""
var last_command: Dictionary = {}
var phase := "initializing"
var last_heartbeat := 0

func attach(owner_session: Node) -> void:
	session = owner_session
	started = Time.get_ticks_usec()
	process_physics_priority = 10
	running = true
	_rebind()

func _rebind() -> bool:
	pilot = Pilot.new()
	if not pilot.bind(_body()): return _check(false,"original Flight Pilot binds")
	previous = _body().global_position
	previous_region = session.region_id
	previous_body = _body().get_instance_id()
	previous_branch = str(session.world_cache.world.branch_id)
	return true

func _body() -> FlightBodyV2:
	return session.players.get(session.network.local_id()) as FlightBodyV2

func _physics_process(delta: float) -> void:
	if not running or not is_instance_valid(session) or not session.active or not is_instance_valid(_body()): return
	if previous_region == session.region_id and previous_body==_body().get_instance_id() and previous_branch==str(session.world_cache.world.branch_id):
		var moved := previous.distance_to(_body().global_position)
		distance += moved
		if moved > 2.0: _check(false,"no unexplained aircraft placement",{"distance":moved,"phase":phase})
	previous = _body().global_position
	previous_region = session.region_id
	previous_body = _body().get_instance_id()
	previous_branch = str(session.world_cache.world.branch_id)
	if not _body().enabled: _check(false,"aircraft remains operational",{"phase":phase}); running = false; return
	if pilot != null and not session.simulation_paused: last_command = pilot.tick(delta,true,false)
	if fire: Input.action_press("flight_fire")
	else: Input.action_release("flight_fire")
	if Time.get_ticks_msec()-last_heartbeat>10000:
		last_heartbeat=Time.get_ticks_msec()
		print("ACCEPTANCE_HEARTBEAT ",JSON.stringify({"phase":phase,"position":_body().global_position,"region":session.region_id,"branch":previous_branch,"speed":_body().linear_velocity.length()}))

func _healthy() -> bool:
	return running and failures.is_empty() and is_instance_valid(_body()) and _body().enabled

func _next() -> void:
	await get_tree().physics_frame
	await get_tree().process_frame

func _key(code: Key) -> void:
	var key := InputEventKey.new()
	key.pressed = true; key.physical_keycode = code; key.keycode = code
	session._unhandled_input(key)

func ui_accept(button: BaseButton) -> bool:
	await _next()
	if not _check(button.is_visible_in_tree() and not button.disabled,"actual GUI control is visible and enabled",str(button.get_path())): return false
	button.grab_focus()
	await _next()
	if not _check(button.has_focus(),"ordinary game GUI owns focus",button.text): return false
	for pressed: bool in [true,false]:
		var event := InputEventAction.new()
		event.action = &"ui_accept"; event.pressed = pressed
		event.strength = 1.0 if pressed else 0.0
		Input.parse_input_event(event)
		await _next()
	_event("focused_GUI_accept",button.text)
	return _healthy()

func _dismiss() -> bool:
	if session.interface.campaign_book.visible: _key(KEY_ESCAPE); await _next()
	var until := Time.get_ticks_msec() + 12000
	while _healthy() and session.interface.radio.visible and Time.get_ticks_msec() < until:
		_key(KEY_G)
		await _next()
	return not session.interface.radio.visible and _healthy()

func _check(ok: bool, label: String, details: Variant = {}) -> bool:
	checks.append({"ok":ok,"label":label,"details":details})
	if not ok:
		failures.append({"label":label,"details":details})
		print("ACCEPTANCE_FAIL ",label," ",JSON.stringify(details))
	return ok

func _event(kind: String, details: Variant = {}) -> void:
	if events.size() < 6000: events.append({"kind":kind,"seconds":float(Time.get_ticks_usec()-started)/1000000.0,"region":session.region_id,"details":details})
	print("ACCEPTANCE_EVENT ",kind," ",JSON.stringify(details))

func _hull_clear(at: Vector3) -> bool:
	var shape := BoxShape3D.new()
	shape.size = Vector3(float(_body().stats.width_m),float(_body().stats.height_m),float(_body().stats.length_m))+Vector3.ONE*.38
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = shape; query.transform = Transform3D(Basis.IDENTITY,at)
	query.collision_mask = 1|2|4|8|32; query.exclude = [_body().get_rid()]
	return session.world.get_world_3d().direct_space_state.intersect_shape(query,1).is_empty()

func _fly_leg(goal: Vector3, label: String, candidate_only := false) -> bool:
	phase = label
	if not _check(_hull_clear(goal),"candidate waypoint has native aircraft clearance",{"point":goal,"label":label,"classification":"candidate_route_only"}): return false
	serial += 1
	if not _check(pilot.go_to(goal,serial),"ordinary Flight Pilot accepts waypoint",label): return false
	var initial := _body().global_position.distance_to(goal)
	var best := initial
	var last_progress := Time.get_ticks_msec()
	var deadline := last_progress + int(maxf(22,initial/.6+15)*1000)
	while _healthy() and Time.get_ticks_msec() < deadline:
		await _next()
		var remaining := _body().global_position.distance_to(goal)
		if remaining < .24 and _body().linear_velocity.length() < .24: return true
		if remaining < best-.1: best = remaining; last_progress = Time.get_ticks_msec()
		if Time.get_ticks_msec()-last_progress > 12000: break
	var details := {"label":label,"goal":goal,"position":_body().global_position,"pilot":pilot.report(),"classification":"bounded_driver_route_stall"}
	if candidate_only and _healthy(): _event("direct_candidate_blocked_replan_above",details); return false
	return _check(false,"continuous native flight reaches waypoint",details)

func fly_to(goal: Vector3, label: String) -> bool:
	if _body().global_position.distance_to(goal) < .2: return true
	if _leg_clear(_body().global_position,goal):
		if await _fly_leg(goal,label+":direct_native_clearance",true):
			_event("native_flight_arrival",{"label":label,"position":_body().global_position})
			return true
		if not _healthy(): return false
	var bounds: Array = Regions.definition(session.region_id).get("bounds",[-40,-1,-40,40,27,40])
	var cruise := minf(25.0,float(bounds[4])-1.0)
	var here := _body().global_position
	if here.distance_to(goal)<24:
		for height: float in [maxf(here.y,goal.y)+3.0,maxf(here.y,goal.y)+7.0]:
			if height>=cruise: continue
			var up := Vector3(here.x,height,here.z)
			var over := Vector3(goal.x,height,goal.z)
			if _leg_clear(here,up) and _leg_clear(up,over) and _leg_clear(over,goal): cruise=height;break
	var points: Array[Vector3] = [Vector3(here.x,cruise,here.z),Vector3(goal.x,cruise,goal.z),goal]
	if not _leg_clear(here,points[0]) or not _leg_clear(points[0],points[1]) or not _leg_clear(points[1],goal):
		return await _planned_flight(goal,label,bounds)
	for index in range(points.size()):
		if _body().global_position.distance_to(points[index]) > .2 and not await _fly_leg(points[index],label+":"+str(index),true):
			if not _healthy():return false
			return await _planned_flight(goal,label,bounds)
	_event("native_flight_arrival",{"label":label,"position":_body().global_position})
	return true

func _planned_flight(goal: Vector3,label: String,bounds: Array) -> bool:
	var search:=RouteSearch.new()
	var path: Array=await search.find(self,goal,bounds)
	if not _check(not path.is_empty(),"native collision route finds a side entry to the inspection point",{"goal":goal,"classification":"bounded_route_search"}):return false
	for waypoint: Vector3 in path:
		if not await _fly_leg(waypoint,label+":native_side_route"):return false
	_event("native_flight_arrival",{"label":label,"position":_body().global_position});return true

func _leg_clear(from: Vector3, to: Vector3) -> bool:
	var shape := BoxShape3D.new()
	shape.size=Vector3(float(_body().stats.width_m),float(_body().stats.height_m),float(_body().stats.length_m))+Vector3.ONE*.38
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape=shape;query.transform=Transform3D(Basis.IDENTITY,from);query.motion=to-from
	query.collision_mask=1|2|4|8|32;query.exclude=[_body().get_rid()]
	var space: PhysicsDirectSpaceState3D=session.world.get_world_3d().direct_space_state
	if not space.intersect_shape(query,1).is_empty():return false
	var motion: PackedFloat32Array=space.cast_motion(query)
	return motion.size()==2 and motion[0]>=.999

func inspect_point(at: Vector3, id: String, radius := 4.0) -> Vector3:
	if session.story.markers.get(id,{}).get("kind","")=="inspect":
		for elevation: float in [.4,1.0,0.0]:
			var centre := at+Vector3.UP*elevation
			if _hull_clear(centre) and session.story.nearest(centre)==id and session._line_clear(centre,at,_body().get_rid(),id):return centre
	for elevation: float in [1.2,2.0,0.0,-1.0]:
		for spacing: float in [2.6,1.5,3.3]:
			for i in range(16):
				var angle := TAU*float(i)/16.0
				var p := at+Vector3(cos(angle)*spacing,elevation,sin(angle)*spacing)
				if p.y < 1.5 or p.y > 26.5 or p.distance_to(at) > radius-.15 or not _hull_clear(p): continue
				if session.story.markers.has(id) and session.story.nearest(p) != id: continue
				if session._line_clear(p,at,_body().get_rid(),id): return p
	return Vector3.INF

func approach(at: Vector3, id: String, radius := 4.0) -> bool:
	var goal := inspect_point(at,id,radius)
	if not _check(goal.is_finite(),"a real near/LOS inspection position exists",{"id":id,"at":at}): return false
	return await fly_to(goal,"approach:"+id)

func select_target(id: String) -> bool:
	for _attempt in range(session.entities.size()+2):
		if str(session.locks.get(1,"")) == id: return true
		_key(KEY_TAB)
		await _next()
		if not _healthy(): return false
	return _check(false,"normal Tab selects real target",{"expected":id,"actual":session.locks.get(1,"")})

func ability(id: String, ability_id: String, reverse := false) -> bool:
	var deadline := Time.get_ticks_msec()+15000
	var cost: float = Rules.DEFINITIONS[ability_id].energy
	while _healthy() and (float(session.cooldowns.get(1,0)) > 0 or float(session.entities[session._actor_id(1)].get("energy",0)) < cost) and Time.get_ticks_msec() < deadline: await _next()
	if not await select_target(id): return false
	var index: int = session.interface.ABILITIES.find(ability_id)
	if not _check(index >= 0,"ability is available on ordinary bar",ability_id): return false
	_key(KEY_0 if index == 9 else KEY_1+index)
	await _next()
	var revision: int = int(session.entities[id].get("revision",-1))
	var accepted_before: int = int(session.stats.get("abilities",0))
	_key(KEY_X if reverse else KEY_F)
	for _tick in range(20):
		await _next()
		if not _healthy(): return false
		if int(session.stats.get("abilities",0))>accepted_before and int(session.entities[id].get("revision",-1)) > revision:
			_event("native_ability",{"target":id,"ability":ability_id,"reverse":reverse,"revision_before":revision,"revision_after":session.entities[id].revision})
			return true
	return _check(false,"ordinary ability commits a new native revision",{"target":id,"ability":ability_id,"reverse":reverse,"message":session.interface.message.text})

func contact(id: String) -> bool:
	if not await _dismiss(): return false
	var actual: String = session.story.nearest(_body().global_position)
	if not _check(actual == id,"ordinary G chooses the intended nearby contact",{"wanted":id,"actual":actual,"position":_body().global_position}): return false
	_key(KEY_G)
	await _next()
	_event("ordinary_nearby_G",id)
	if not await _dismiss(): return false
	for _settle in range(8): await _next()
	return _healthy()

func travel(destination: String) -> bool:
	if destination == session.region_id: return true
	var queue: Array = [[session.region_id]]
	var visited: Array = []
	var route: Array = []
	while not queue.is_empty():
		var path: Array = queue.pop_front()
		var last := str(path.back())
		if last == destination: route = path; break
		if last in visited: continue
		visited.append(last)
		for next: String in Regions.destinations(last):
			var extended: Array = path.duplicate(); extended.append(next); queue.append(extended)
	if not _check(not route.is_empty(),"normal route graph reaches requested region",destination): return false
	for next: String in route.slice(1):
		if not await _dismiss(): return false
		pilot = null
		if not _check(session._can_travel_to(next),"normal travel is unlocked",next): return false
		session._ui_action("travel_to",{"region_id":next})
		var deadline := Time.get_ticks_msec()+20000
		while _healthy() and session.region_id != next and Time.get_ticks_msec() < deadline: await _next()
		if not _check(session.region_id == next,"original travel/Store adopts next region",next): return false
		if not _rebind(): return false
		await _next()
	_event("normal_travel",destination)
	return true
