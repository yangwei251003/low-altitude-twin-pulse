extends RefCounted
## Eight encounter strategies driven by live boss/device state. All damage,
## movement, costs, cooldowns and victories remain production-authoritative.
const Pilot = preload("res://scripts/v3/assist/twin_assist_pilot.gd")
const Routes = preload("res://scripts/v3/assist/twin_assist_routes.gd")
const Pump = preload("res://scripts/v3/gameplay/twin_pump_guardian_mechanisms.gd")
var a
var region := ""
var phase := ""
var path: Array = []
var path_index := 0
var patrol := Vector3.INF
var side := 1.0
var warning_token := ""
var elapsed := 0.0
var progress_clock := 0.0
var last_health := ""
var water_stage := ""
var water_high := false
var crown_prepared := false
var rig_route_key := ""
var rig_points: Array = []
var rig_index := 0

func setup(assistant: Node) -> void: a = assistant
func reset() -> void:
	region = ""
	phase = ""
	path.clear()
	path_index = 0
	patrol = Vector3.INF
	warning_token = ""
	elapsed = 0.0
	progress_clock = 0.0
	last_health = ""
	water_stage = ""
	crown_prepared = false
	rig_route_key = ""
	rig_points.clear()
	rig_index = 0

func compose(delta: float, next_region: String) -> Dictionary:
	if region != next_region:
		reset()
		region = next_region
		phase = "enter"
		_prepare_entry()
	elapsed += delta
	var session = a.session
	var state: Dictionary = boss_state()
	if bool(state.get("completed",false)) or (region not in ["I1","F1"] and session.campaign.victory_committed()):
		return Pilot.neutral()
	var health_key := str([state.get("core_health"),state.get("core_hp_milli"),state.get("parts"),state.get("nodes"),state.get("phase")])
	if health_key != last_health:
		last_health = health_key
		progress_clock = elapsed
	if elapsed-progress_clock > 150:
		a.stop("战斗长时间未推进，助手已停下；可以接管或按原重试入口再试。")
		return Pilot.neutral()
	if phase == "enter":
		if bool(session.boss_active):
			phase = "battle"
			path.clear()
			path_index = 0
		else:
			return _fly_path(delta)
	if region == "I1": return _whale(delta,state)
	if region == "F1": return _crown(delta,state)
	return _campaign(delta,state)

func _prepare_entry() -> void:
	var body: FlightBodyV2 = a._body()
	var session = a.session
	if session.boss_active:
		phase = "battle"
		return
	match region:
		"I1": path = [Vector3(-16,11.8,body.global_position.z),Vector3(-16,11.8,-14.5),Vector3(-9,10,-14.5),session.world.boss_position+Vector3(0,4,17)]
		"F1": path = [Vector3(4,15,-8),Vector3(4,15,-23)]
		_:
			var altitude := _altitude()
			path = [Vector3(body.global_position.x,altitude,body.global_position.z),Vector3(0,altitude,float(session.campaign._entry_z)+3),Vector3(0,altitude,float(session.campaign._entry_z)-1)]
	path_index = 0

func _fly_path(delta: float) -> Dictionary:
	if path_index >= path.size(): return Pilot.neutral()
	var command: Dictionary = a.move_to(path[path_index],delta)
	if a._pilot != null and a._pilot.state == "arrived":
		path_index += 1
		a._nav_target = Vector3.INF
	return command

func _whale(delta: float, state: Dictionary) -> Dictionary:
	var session = a.session
	if state.is_empty(): return Pilot.neutral()
	var nodes: Dictionary = state.get("nodes",{})
	var port_powered := bool(nodes.get("port",{}).get("powered",true))
	var starboard_powered := bool(nodes.get("starboard",{}).get("powered",true))
	var target := "boss:port" if port_powered else ("boss:starboard" if starboard_powered else "boss:core")
	var point: Vector3 = a.target_position("boss:port")+Vector3.UP*5.0 if port_powered else a.target_position("boss:starboard")+Vector3(0,3.35,1)
	var command: Dictionary = a.move_to(point,delta)
	if not a.enabled: return Pilot.neutral()
	if state.get("telegraph") == "tractor" and state.get("attack_state") in ["windup","active"]:
		command = Pilot.neutral()
	if port_powered or starboard_powered:
		if bool(state.get("nodes_open",false)) and a._body().global_position.distance_to(point)<.65: a.cast(target,"takeover")
	else:
		command.fire = float(state.get("exposed_remaining",0))>0 and _lock_and_see(target)
	# Original decoy action changes the next warning target; no attack edits.
	if state.get("attack_state") == "recovery" and state.get("telegraph") == "low_sweep" and float(state.get("attack_remaining",2))<1:
		var local: int = session.network.local_id()
		var actor: Dictionary = session.entities.get(session._actor_id(local),{})
		if float(actor.get("decoy_remaining",0))<1 and float(actor.get("energy",0))>=10 and float(session.cooldowns.get(local,0))<=0:
			var decoy: Vector3 = a._body().global_position+Vector3(6,0,0)
			if a.hull_clear(decoy): session.network.send_action("ability",{"ability":"decoy","point":decoy})
	return command

func _crown(delta: float, state: Dictionary) -> Dictionary:
	if state.is_empty(): return Pilot.neutral()
	var command: Dictionary = a.move_to(Vector3(4,15,-23),delta)
	if not a.enabled: return Pilot.neutral()
	if a._body().global_position.distance_to(Vector3(4,15,-23))>.6: return command
	var anchor := str(state.get("anchor_id","F1:crown_host_west"))
	var anchors: Dictionary = state.get("anchors",{})
	var tick := int(state.get("tick",0))
	var current: Dictionary = anchors.get(anchor,{})
	if state.get("mode") == "attached":
		if int(current.get("light_until",0))<=tick: a.cast(anchor,"light")
		else: a.cast(anchor,"growth")
		return command
	if int(state.get("phase",1)) == 1 and int(state.get("core_hp_milli",160000))<=88000:
		var high: Dictionary = anchors.get("F1:crown_host_high",{})
		if int(high.get("light_until",0))<=tick:
			a.cast("F1:crown_host_high","light")
			return command
		if int(high.get("trap_until",0))<=tick:
			a.cast("F1:crown_host_high","growth")
			return command
		crown_prepared = true
	command.fire = bool(state.get("core_open",false)) and _lock_and_see("boss:crown_core")
	return command

func _campaign(delta: float, state: Dictionary) -> Dictionary:
	var session = a.session
	if state.is_empty(): return Pilot.neutral()
	var environment: Dictionary = session.campaign.mechanisms.boss_environment(region)
	var part: String = session.campaign.encounter.current_part()
	if region == "I2":
		var level := int(environment.get("water_level_mm",-1))
		if not water_stage.is_empty() or (part == "low_pump" and level>2000) or (part == "high_pump" and level<3000):
			if water_stage.is_empty():
				water_high = part == "high_pump"
				water_stage = "valve"
			return _pump_water(delta,environment)
	if region == "F2" and (not bool(environment.get("true_body_revealed",false)) or not bool(environment.get("shadow_verified",false))):
		var point: Vector3 = a.target_position("F2:reveal_source")+Vector3(0,2,3)
		var command: Dictionary = a.move_to(point,delta)
		if a._body().global_position.distance_to(point)<.6: a.cast("F2:reveal_source","light")
		return command
	if region == "I3" and float(session.entities.get("I3:boss_radiator",{}).get("temperature",0))>35:
		var point := Vector3(-5,10,-17)
		var command: Dictionary = a.move_to(point,delta)
		if a._body().global_position.distance_to(point)<.6: a.cast("I3:boss_radiator","heat","cool")
		return command
	if region == "I4" and not bool(environment.get("receiver_lit",false)):
		var point: Vector3 = a.target_position("I4:witness_source")+Vector3(0,2,3)
		var command: Dictionary = a.move_to(point,delta)
		if a._body().global_position.distance_to(point)<.6: a.cast("I4:witness_source","light")
		return command
	var command := _patrol(delta,state)
	if not a.enabled: return Pilot.neutral()
	var target: String = session.world.campaign_arena.target_id(part)
	command.fire = str(state.get("attack_stage","")) == "recovery" and _lock_and_see(target)
	return command

func _pump_water(delta: float, environment: Dictionary) -> Dictionary:
	var session = a.session
	var desired := "fill" if water_high else "drain"
	var valve: Vector3 = a.target_position(Pump.VALVE)+Vector3.UP*3.4
	var relay: Vector3 = a.target_position(Pump.RELAY)
	relay.y = 12
	match water_stage:
		"valve":
			if str(session.campaign.mechanisms.view_state().get("direction","neutral"))==desired:
				water_stage = "power"
				return Pilot.neutral()
			var command: Dictionary = _rig_approach(valve,delta,"valve")
			if a._body().global_position.distance_to(valve)<.5: a.operate(Pump.VALVE)
			return command
		"power":
			var command: Dictionary = _rig_approach(relay,delta,"power")
			if a._body().global_position.distance_to(relay)<.5:
				if float(session.entities[Pump.RELAY].get("charge",0))<60: a.cast(Pump.RELAY,"charge")
				else: water_stage = "flow"
			return command
		"flow":
			var level := int(environment.get("water_level_mm",-1))
			if (water_high and level>=3000) or (not water_high and level>=0 and level<=2000): water_stage = "stop"
			return _patrol(delta,boss_state())
		"stop":
			var command: Dictionary = _rig_approach(relay,delta,"stop")
			if a._body().global_position.distance_to(relay)<.5:
				if float(session.entities[Pump.RELAY].get("charge",0))>0: a.cast(Pump.RELAY,"charge","drain")
				else:
					water_stage = ""
					patrol = Vector3.INF
			return command
	return Pilot.neutral()

func _rig_approach(point: Vector3, delta: float, action: String) -> Dictionary:
	var key := action+":"+str(water_high)
	if rig_route_key != key:
		rig_route_key = key
		rig_points.clear()
		rig_index = 0
		var current: Vector3 = a._body().global_position
		# Cross the pump bodies above their full height. First move sideways
		# while climbing out of a locked warning disc, using ordinary input.
		if current.y < 11.7:
			var leave_x := clampf(current.x+(6.0 if current.x>=0 else -6.0),-24.0,24.0)
			rig_points.append(Vector3(leave_x,12,current.z))
		rig_points.append_array([Vector3(point.x,12,-17),Vector3(point.x,12,point.z),point])
	if rig_index >= rig_points.size(): return a.move_to(point,delta,true)
	var command: Dictionary = a.move_to(rig_points[rig_index],delta)
	if a._pilot != null and a._pilot.state == "arrived":
		rig_index += 1
		a._nav_target = Vector3.INF
	return command

func _patrol(delta: float, state: Dictionary) -> Dictionary:
	var body: FlightBodyV2 = a._body()
	var attack: Dictionary = state.get("attack",{})
	var token := str(attack.get("token",""))
	var locked: bool = state.get("attack_stage") in ["warning","active"]
	var line := -17.0
	if region in ["F2","I4","F4"]: line = float(a.session.campaign._entry_z)+2.0
	var extent := float({"I2":20,"F2":8,"I3":16,"F3":19,"I4":9,"F4":9}.get(region,12))
	if locked and token != warning_token and not attack.get("shapes",[]).is_empty():
		warning_token = token
		var shape: Dictionary = attack.shapes[0]
		var raw: Array = shape.get("centre_mm",[0,0,0])
		var centre := Vector3(float(raw[0]),float(raw[1]),float(raw[2]))/1000.0
		side = signf(body.linear_velocity.x) if absf(body.linear_velocity.x)>.3 else (1.0 if body.global_position.x>=centre.x else -1.0)
		var x := clampf(centre.x+side*7.0,-24,24)
		var z := line
		if region in ["I4","F4"]:
			var zside := signf(body.linear_velocity.z) if absf(body.linear_velocity.z)>.3 else (-1.0 if centre.z>line else 1.0)
			z = clampf(centre.z+zside*7.0,-34,30)
		patrol = Vector3(x,_altitude(),z)
	elif not locked and (not patrol.is_finite() or body.global_position.distance_to(patrol)<1.2 or absf(body.global_position.x)>extent-1):
		side = -1.0 if body.global_position.x>0 else 1.0
		patrol = Vector3(side*extent,_altitude(),line)
	if not patrol.is_finite(): patrol = Vector3(side*extent,_altitude(),line)
	return a.move_to(patrol,delta)

func _lock_and_see(target: String) -> bool:
	if not a.enabled: return false
	var session = a.session
	var point: Vector3 = a.target_position(target)
	if not point.is_finite(): return false
	var local: int = session.network.local_id()
	if str(session.locks.get(local,"")) != target: session.network.send_action("lock",{"target_id":target})
	return session._line_clear(a._body().global_position,point,a._body().get_rid(),target)

func boss_state() -> Dictionary:
	match region:
		"I1": return a.session.encounter.get_state()
		"F1": return a.session.crown.encounter.get_state()
	return a.session.campaign.encounter.get_state() if a.session.campaign.supported() else {}

func _altitude() -> float:
	return minf(float(a._body().max_altitude)-.5,float({"I1":12,"F1":15,"I2":12,"F2":18,"I3":14,"F3":15,"I4":18,"F4":20}.get(region,15)))
