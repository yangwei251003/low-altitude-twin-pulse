class_name TwinCampaignLateMechanisms
extends "res://scripts/v3/campaign/twin_campaign_mechanisms.gd"
## Later regions compose the tested F2/I3 base. All mechanisms use original
## entities, live body poses and PhysicsServer rays; no additional world store.

func configure(owner_world: Node3D, real_bodies: Dictionary = {}, is_authority: bool = true) -> Dictionary:
	var result: Dictionary = super.configure(owner_world,real_bodies,is_authority)
	if not result.ok: return result
	for id in ["F4:industrial_gauge","F4:living_gauge"]:
		if region == "F4" and is_instance_valid(_body(id)):
			var at: Vector3 = _body(id).global_position
			_markers[id] = {"id":id,"position":[at.x,at.y,at.z],"radius":3.0}
	return result

func advance(delta: float, entities: Dictionary, players: Dictionary, paused: bool = false) -> Dictionary:
	var old_tick: int = int(_state.get("tick",0))
	var before: Dictionary = _state.get("facts",{}).duplicate(true)
	var result: Dictionary = super.advance(delta,entities,players,paused)
	if not result.ok or paused: return result
	for _step in range(int(_state.tick)-old_tick):
		match region:
			"F3": _observe_signal()
			"I4":
				_observe_evidence_channel(result.entity_changes)
				_observe_storm_routes()
				_observe_defence()
			"F4": _observe_final_links(result.entity_changes)
	result.facts_changed = before != _state.facts
	return result

func observe_interaction(peer, id: String, method: String = "") -> Dictionary:
	var result: Dictionary = super.observe_interaction(peer,id,method)
	if not result.ok or region != "F4": return result
	if id == "F4:choice_terminal" and method in ["shared_stewardship","industrial_lifeline","living_vein"]:
		var plans: Dictionary = _state.histories.get("F4:plans_read",{})
		plans[method] = true
		_state.histories["F4:plans_read"] = plans
		if plans.size() == 3: _set_fact("F4:plans_reviewed","all_read")
	if id in ["F4:industrial_gauge","F4:living_gauge"]:
		var test: Dictionary = _state.histories.get("F4:load_test",{})
		if not bool(test.get("active",false)) or not _view.get("dual_load_valid",false): return _no("load_test_not_active")
		var side := "industrial" if id == "F4:industrial_gauge" else "living"
		test.readings[side] = {"test_serial":int(test.test_serial),"tick":int(_state.tick),"load_w":int(_view.get(side+"_draw_w",0))}
		_state.histories["F4:load_test"] = test
		if test.readings.has("industrial") and test.readings.has("living"):
			if int(test.readings.industrial.test_serial) == int(test.test_serial) and int(test.readings.living.test_serial) == int(test.test_serial):
				if not _state.histories.has("F4:dual_load_record"): _state.histories["F4:dual_load_record"] = test.duplicate(true)
				_set_fact("F4:dual_load_verified",str(test.method))
	return result

func verified_nutrient_route() -> String:
	return "grown_path" if region == "F3" and bool(_view.get("nutrient_supported",false)) else ""

func boss_environment(requested_region: String = "") -> Dictionary:
	var target: String = region if requested_region.is_empty() else requested_region
	if target != region: return {}
	if target == "F3":
		if not is_instance_valid(_body("F3:signal_breaker")) or not is_instance_valid(_body("F3:nutrient_bridge")): return {}
		return {"signal_isolated":bool(_view.get("signal_open",false)),"nutrient_connected":bool(_view.get("nutrient_supported",false))}
	if target == "I4":
		if not is_instance_valid(_body("I4:witness_receiver")) or not is_instance_valid(_body("I4:defence_breaker")): return {}
		return {"receiver_lit":bool(_view.get("witness_lit",false)),"defence_isolated":bool(_view.get("defence_isolated",false))}
	if target == "F4":
		# The final combat controls are separate real targets. Completing the
		# approach puzzle does not silently turn on three boss part conditions.
		var charge: Node3D = _body("F4:core_charge_breaker")
		var thermal: Variant = _entities.get("F4:core_thermal_sink")
		var living: Node3D = _body("F4:core_living_support")
		if not is_instance_valid(charge) or not is_instance_valid(_body("F4:core_thermal_sink")) or not thermal is Dictionary or not _number(thermal.get("temperature")) or not is_instance_valid(living): return {}
		var live: Dictionary = _entities.get("F4:core_living_support",{})
		return {"charge_loop_open":charge.global_position.distance_to(Vector3(-5,14,-27)) >= 1.4,
			"thermal_sink_ready":float(thermal.temperature) <= 35.0,
			"living_support_ready":float(live.get("growth",0.0)) >= .7 and _support_span("F4:core_living_support",Vector3(3.5,13,-27),Vector3(6.5,13,-27),2.0),
			"both_lifelines_connected":bool(_view.get("industrial_connected",false)) and bool(_view.get("living_connected",false))}
	return super.boss_environment(requested_region)

func validate_state(saved: Dictionary) -> Dictionary:
	var checked: Dictionary = super.validate_state(saved)
	if not checked.ok: return checked
	var histories: Dictionary = saved.histories
	if histories.has("F3:signal"):
		var signal_record: Variant = histories["F3:signal"]
		if not signal_record is Dictionary or signal_record.size() != 2 or not _integer(signal_record.get("stable_ticks"),0,3) or signal_record.get("method") not in ["","echo_hold","two_pilots","latched_bypass"]: return _no("signal_history_invalid")
	if histories.has("I4:evidence_chain"):
		var chain: Variant = histories["I4:evidence_chain"]
		if not chain is Dictionary or chain.size() != 3: return _no("evidence_history_invalid")
		for key in _evidence_keys():
			if not _digest(chain.get(key)): return _no("evidence_hash_invalid")
	if histories.has("I4:routes"):
		var routes: Variant = histories["I4:routes"]
		if not routes is Dictionary or routes.size() > 16: return _no("route_history_invalid")
		for peer in routes:
			var route: Variant = routes[peer]
			if not peer is String or not route is Dictionary or route.size() != 3 or not _mm_valid(route.get("last_mm")): return _no("route_actor_invalid")
			for key in ["covered_low","high_window"]:
				if not _integer(route.get(key),0,3): return _no("route_progress_invalid")
	if histories.has("I4:platform"):
		var platform: Variant = histories["I4:platform"]
		if not platform is Dictionary or platform.size() != 2 or not _mm_valid(platform.get("last_mm")) or not _integer(platform.get("stable_ticks"),0,3): return _no("platform_history_invalid")
	if histories.has("F4:plans_read"):
		var plans: Variant = histories["F4:plans_read"]
		if not plans is Dictionary or plans.size() > 3: return _no("plans_history_invalid")
		for key in plans:
			if key not in ["shared_stewardship","industrial_lifeline","living_vein"] or plans[key] != true: return _no("plan_reading_invalid")
	for history_key in ["F4:load_test","F4:dual_load_record"]:
		if not histories.has(history_key): continue
		var test: Variant = histories[history_key]
		if not test is Dictionary or test.size() != 4 or not test.get("active") is bool or not _integer(test.get("test_serial"),0,2147483647) or test.get("method") not in ["","echo_test","two_pilots","latched_test"] or not test.get("readings") is Dictionary: return _no("load_test_invalid")
		if test.readings.size() > 2: return _no("load_readings_invalid")
		for side in test.readings:
			var reading: Variant = test.readings[side]
			if side not in ["industrial","living"] or not reading is Dictionary or reading.size() != 3: return _no("load_reading_invalid")
			for key in ["test_serial","tick","load_w"]:
				if not _integer(reading.get(key),0,2147483647): return _no("load_measurement_invalid")
			if int(reading.test_serial) != int(test.test_serial) or int(reading.tick) > int(saved.tick) or int(reading.load_w) <= 0: return _no("load_measurement_mismatch")
	for history_key in ["F3:signal_record","I4:route_record","I4:defence_record","F4:industrial_record","F4:living_record"]:
		if not histories.has(history_key): continue
		var record: Variant = histories[history_key]
		if not record is Dictionary or not _integer(record.get("tick"),1,int(saved.tick)): return _no("immutable_record_invalid")
	for target in saved.facts:
		if target == "F3:signal_isolation_verified" and not histories.has("F3:signal_record"): return _no("signal_proof_missing")
		if target == "I4:evidence_delivery_verified" and not histories.has("I4:evidence_chain"): return _no("evidence_proof_missing")
		if target == "I4:storm_route_verified" and not histories.has("I4:route_record"): return _no("route_proof_missing")
		if target == "I4:defence_isolated" and not histories.has("I4:defence_record"): return _no("platform_proof_missing")
		if target == "F4:industrial_link_verified" and not histories.has("F4:industrial_record"): return _no("industrial_proof_missing")
		if target == "F4:living_link_verified" and not histories.has("F4:living_record"): return _no("living_proof_missing")
		if target == "F4:plans_reviewed" and histories.get("F4:plans_read",{}).size() != 3: return _no("plan_proof_missing")
		if target == "F4:dual_load_verified" and histories.get("F4:dual_load_record",{}).get("readings",{}).size() != 2: return _no("dual_measurement_proof_missing")
	return _yes("late_mechanism_state_valid")

func _observe_signal() -> void:
	var breaker: Node3D = _body("F3:signal_breaker")
	var hold: Node3D = _body("F3:signal_hold")
	var roots: Dictionary = _entities.get("F3:nutrient_bridge",{})
	var supported: bool = float(roots.get("growth",0.0)) >= .7 and _support_span("F3:nutrient_bridge",Vector3(14.5,8,2),Vector3(17.5,8,2),2.0)
	var open := is_instance_valid(breaker) and breaker.global_position.distance_to(Vector3(12,7,9)) <= .4
	var method := ""
	if is_instance_valid(hold):
		var data: Dictionary = _entities.get("F3:signal_hold",{})
		if float(data.get("echo_remaining",0.0)) > 0.0 and bool(data.get("operated",false)): method = "echo_hold"
		elif hold.global_basis.x.normalized().dot(Vector3.FORWARD) > .95: method = "latched_bypass"
		elif _two_at(hold.global_position,Vector3(12,7,9)): method = "two_pilots"
	_view.signal_open = open and not method.is_empty()
	_view.nutrient_supported = supported
	var signal_record: Dictionary = _state.histories.get("F3:signal",{"stable_ticks":0,"method":""})
	if open and supported and not method.is_empty():
		signal_record.stable_ticks = mini(3,int(signal_record.stable_ticks)+1)
		signal_record.method = method
		if int(signal_record.stable_ticks) >= 3:
			if not _state.histories.has("F3:signal_record"): _state.histories["F3:signal_record"] = {"tick":int(_state.tick),"method":method}
			_set_fact("F3:signal_isolation_verified",method)
	else: signal_record.stable_ticks = 0
	_state.histories["F3:signal"] = signal_record

func _observe_evidence_channel(changes: Dictionary) -> void:
	_view.witness_lit = false
	_view.beam_valid = false
	_view.beam_segments = []
	var source: Node3D = _body("I4:witness_source")
	var receiver: Node3D = _body("I4:witness_receiver")
	if not is_instance_valid(source) or not is_instance_valid(receiver): return
	var data: Dictionary = _entities.get("I4:witness_source",{})
	if float(data.get("light_level",0.0)) < .5: return
	var ray: Dictionary = _ray(source.global_position,receiver.global_position,[_rid(source)])
	_view.beam_segments = [[_mm(source.global_position),_mm(ray.get("position",receiver.global_position))]]
	if not _is_body(ray.get("collider"),receiver,"I4:witness_receiver"): return
	_view.witness_lit = true
	_view.beam_valid = true
	var payload: Variant = data.get("payload_hashes")
	if not payload is Dictionary or payload.size() != 3: return
	for key in _evidence_keys():
		if not _digest(payload.get(key)): return
	# Source hashes are loaded by Root from the original committed records, never
	# received from a client. This step models transmission through the actual ray.
	var actual: Dictionary = _entities.get("I4:witness_receiver",{})
	if actual.get("received_hashes",{}) != payload:
		actual["received_hashes"] = payload.duplicate(true)
		actual.revision = int(actual.get("revision",0))+1
		changes["I4:witness_receiver"] = {"received_hashes":actual.received_hashes.duplicate(true),"revision":actual.revision}
	if actual.received_hashes == payload:
		if not _state.histories.has("I4:evidence_chain"): _state.histories["I4:evidence_chain"] = payload.duplicate(true)
		_set_fact("I4:evidence_delivery_verified","optical")

func _observe_storm_routes() -> void:
	var routes: Dictionary = _state.histories.get("I4:routes",{})
	var paths := {"covered_low":[Vector3(20,12,4),Vector3(20,5,4),Vector3(14,5,-3)],"high_window":[Vector3(20,12,4),Vector3(32,20,10),Vector3(14,5,-3)]}
	for peer in _players:
		if not _active(_players[peer]): continue
		var id := str(peer)
		var at: Vector3 = _player_position(_players[peer])
		var record: Dictionary = routes.get(id,{"last_mm":_mm(at),"covered_low":0,"high_window":0})
		if at.distance_to(_metres(record.last_mm)) > 5.0:
			record.covered_low = 0
			record.high_window = 0
		for option in paths:
			var progress: int = int(record[option])
			if progress < 3 and at.distance_to(paths[option][progress]) <= 2.5:
				record[option] = progress+1
				if progress == 2 and _landing_supported(at,_player_rid(_players[peer])):
					if not _state.histories.has("I4:route_record"): _state.histories["I4:route_record"] = {"tick":int(_state.tick),"option":option,"peer":str(peer)}
					_set_fact("I4:storm_route_verified",option)
				elif progress == 2: record[option] = 2
		record.last_mm = _mm(at)
		routes[id] = record
	_state.histories["I4:routes"] = routes

func _observe_defence() -> void:
	_view.defence_isolated = false
	var platform: Node3D = _body("I4:defence_platform")
	var breaker: Node3D = _body("I4:defence_breaker")
	var civilian: Node3D = _body("I4:civilian_feed")
	if not is_instance_valid(platform) or not is_instance_valid(breaker) or not is_instance_valid(civilian): return
	var sample: Dictionary = _state.histories.get("I4:platform",{"last_mm":_mm(platform.global_position),"stable_ticks":0})
	var position_ok: bool = platform.global_position.distance_to(Vector3(14,4.2,-3)) <= .35
	var stopped: bool = platform.global_position.distance_to(_metres(sample.last_mm)) <= .02
	var support: Dictionary = _ray(platform.global_position+Vector3.UP*.6,platform.global_position-Vector3.UP*1.2,[_rid(platform)])
	var feed: Dictionary = _entities.get("I4:civilian_feed",{})
	var supplied: bool = bool(feed.get("powered",false)) and float(feed.get("charge",0.0)) >= 20.0
	var open: bool = breaker.global_position.distance_to(Vector3(14,5,-.5)) <= .4
	if position_ok and stopped and not support.is_empty() and supplied and open:
		sample.stable_ticks = mini(3,int(sample.stable_ticks)+1)
		if int(sample.stable_ticks) >= 3:
			_view.defence_isolated = true
			var method := "field_lock" if bool(_entities.get("I4:defence_platform",{}).get("pinned",false)) else "mechanical_lock"
			if not _state.histories.has("I4:defence_record"): _state.histories["I4:defence_record"] = {"tick":int(_state.tick),"method":method,"civilian_charge_milli":int(round(float(feed.charge)*1000.0))}
			_set_fact("I4:defence_isolated",method)
	else: sample.stable_ticks = 0
	sample.last_mm = _mm(platform.global_position)
	_state.histories["I4:platform"] = sample

## Pure terminal guard: no facts, clocks, effects, view or entity writes.
## Call with the current Session entity dictionaries, never the prior _view.
func final_lifelines_status(entities: Dictionary) -> Dictionary:
	if region != "F4" or not authority or not is_instance_valid(world) or not world.is_inside_tree(): return {"ok":false,"code":"final_lifelines_live_host_required"}
	for id in ["F4:limited_bus","F4:industrial_load","F4:lifeline_bus","F4:living_emitter","F4:living_support"]:
		var body: PhysicsBody3D = _body(id) as PhysicsBody3D
		if not is_instance_valid(body) or not body.is_inside_tree() or body.get_world_3d().space != world.get_world_3d().space: return {"ok":false,"code":"final_lifelines_body_missing","target":id}
		var native: Transform3D = PhysicsServer3D.body_get_state(body.get_rid(),PhysicsServer3D.BODY_STATE_TRANSFORM)
		if native != body.global_transform: return {"ok":false,"code":"final_lifelines_native_pose_pending","target":id}
	# A just-accepted light-on also rotates this real emitter. Do not sign a
	# stored new angle using a prior-frame body/ray before World synchronizes it.
	var emitter: Node3D = _body("F4:living_emitter")
	var light: Dictionary = entities.get("F4:living_emitter",{})
	if light.has("angle") and absf(wrapf(emitter.rotation.y-float(light.angle),-PI,PI)) > .00001: return {"ok":false,"code":"final_lifelines_emitter_pose_pending"}
	var industrial: Dictionary = _sample_final_industrial(entities)
	var living: Dictionary = _sample_final_living(entities)
	var ok: bool = industrial.connected and living.supported
	return {"ok":ok,"code":"final_lifelines_currently_verified" if ok else "final_lifelines_disconnected","industrial":industrial,"living":living}

func _sample_final_industrial(entities: Dictionary) -> Dictionary:
	var bus: Node3D = _body("F4:limited_bus")
	var load: Node3D = _body("F4:industrial_load")
	var lifeline: Node3D = _body("F4:lifeline_bus")
	var supply: Dictionary = entities.get("F4:limited_bus",{})
	var emergency: Dictionary = entities.get("F4:lifeline_bus",{})
	var consumer: Dictionary = entities.get("F4:industrial_load",{})
	var draw := 0
	if is_instance_valid(bus) and is_instance_valid(load) and is_instance_valid(lifeline):
		var plugged: bool = bus.global_position.distance_to(Vector3(-12,9,6)) <= .35 and (bus.global_transform*Vector3(6,0,0)).distance_to(load.global_position) <= .4
		if plugged and bool(supply.get("powered",false)) and float(supply.get("charge",0.0)) >= 20.0 and bool(emergency.get("powered",false)) and float(emergency.get("charge",0.0)) >= 20.0:
			draw = int(consumer.get("rated_w",120))
			if draw > 0 and draw <= int(supply.get("current_limit_w",500)):
				return {"connected":true,"draw_w":draw}
	return {"connected":false,"draw_w":0}

func _sample_final_living(entities: Dictionary) -> Dictionary:
	var emitter: Node3D = _body("F4:living_emitter")
	var living: Node3D = _body("F4:living_support")
	var illuminated := false
	var segments: Array = []
	var blocker := ""
	if is_instance_valid(emitter) and is_instance_valid(living) and float(entities.get("F4:living_emitter",{}).get("light_level",0.0)) >= .5:
		var nozzle: Vector3 = emitter.to_global(Vector3(0,.1,0))
		var ray: Dictionary = _ray(nozzle,nozzle+emitter.global_basis.x.normalized()*20.0,[_rid(emitter)])
		segments = [[_mm(nozzle),_mm(ray.get("position",nozzle+emitter.global_basis.x.normalized()*20.0))]]
		blocker = str(ray.collider.get_path()) if not ray.is_empty() else ""
		illuminated = _is_body(ray.get("collider"),living,"F4:living_support")
	var roots: Dictionary = entities.get("F4:living_support",{})
	var supported: bool = illuminated and float(roots.get("growth",0.0)) >= .7 and _support_span("F4:living_support",Vector3(12.5,12,6),Vector3(15.5,12,6),2.0)
	return {"supported":supported,"illuminated":illuminated,"beam_segments":segments,"blocker":blocker}

func _observe_final_links(changes: Dictionary) -> void:
	var industrial: Dictionary = _sample_final_industrial(_entities)
	_view.industrial_connected = industrial.connected
	_view.industrial_draw_w = industrial.draw_w
	_view.dual_load_valid = false
	var consumer: Dictionary = _entities.get("F4:industrial_load",{})
	if not consumer.is_empty():
		consumer.powered = industrial.connected
		consumer.actual_draw_w = industrial.draw_w
		changes["F4:industrial_load"] = {"powered":industrial.connected,"actual_draw_w":industrial.draw_w}
	if industrial.connected:
		if not _state.histories.has("F4:industrial_record"): _state.histories["F4:industrial_record"] = {"tick":int(_state.tick),"load_w":int(industrial.draw_w)}
		_set_fact("F4:industrial_link_verified","limited_bus")
	var living: Dictionary = _sample_final_living(_entities)
	_view.beam_segments = living.beam_segments
	if not living.beam_segments.is_empty(): _view.living_beam_blocker = living.blocker
	_view.beam_valid = living.illuminated
	var roots: Dictionary = _entities.get("F4:living_support",{})
	if not roots.is_empty():
		var level := 1.0 if living.illuminated else 0.0
		if float(roots.get("environment_light",0.0)) != level:
			roots["environment_light"] = level
			changes["F4:living_support"] = {"environment_light":level}
	var supported: bool = living.supported
	_view.living_connected = supported
	_view.living_draw_w = 90 if supported else 0
	if supported:
		if not _state.histories.has("F4:living_record"): _state.histories["F4:living_record"] = {"tick":int(_state.tick),"growth_milli":int(round(float(roots.growth)*1000.0))}
		_set_fact("F4:living_link_verified","growth_support")
	var hold: Node3D = _body("F4:test_hold")
	var method := ""
	if is_instance_valid(hold):
		var device: Dictionary = _entities.get("F4:test_hold",{})
		if float(device.get("echo_remaining",0.0)) > 0.0 and bool(device.get("operated",false)): method = "echo_test"
		elif hold.global_basis.x.normalized().dot(Vector3.FORWARD) > .95: method = "latched_test"
		elif _two_at(hold.global_position,Vector3(21,16,-5)): method = "two_pilots"
	var ready: bool = bool(_view.industrial_connected) and supported and not method.is_empty() and is_instance_valid(_body("F4:industrial_gauge")) and is_instance_valid(_body("F4:living_gauge"))
	var test: Dictionary = _state.histories.get("F4:load_test",{"active":false,"test_serial":0,"method":"","readings":{}})
	if ready and not bool(test.active):
		test.test_serial = int(test.test_serial)+1
		test.active = true
		test.method = method
		test.readings = {}
	elif not ready:
		test.active = false
		# Historical completed samples survive a later stop; before completion,
		# starting a new test always clears both readings and increments serial.
	_view.dual_load_valid = ready
	_state.histories["F4:load_test"] = test

func _support_span(id: String, start: Vector3, finish: Vector3, width: float) -> bool:
	var body: Node3D = _body(id)
	if not is_instance_valid(body): return false
	var count: int = maxi(2,int(ceil(start.distance_to(finish)/.5)))
	for i in range(count+1):
		var point: Vector3 = start.lerp(finish,float(i)/float(count))
		for side in [-.4,0.0,.4]:
			var at: Vector3 = point+Vector3(0,0,float(side)*width)
			var hit: Dictionary = _ray(at+Vector3.UP,at-Vector3.UP)
			if not _is_body(hit.get("collider"),body,id): return false
	var along: Vector3 = (finish-start).normalized()
	for edge in [start-along*.15,finish+along*.15]:
		var support: Dictionary = _ray(edge+Vector3.UP*.5,edge-Vector3.UP*1.5,[_rid(body)])
		if support.is_empty(): return false
	return true

func _two_at(first: Vector3, second: Vector3) -> bool:
	for a in _players:
		if not _active(_players[a]) or _player_position(_players[a]).distance_to(first) > 2.5: continue
		for b in _players:
			if a != b and _active(_players[b]) and _player_position(_players[b]).distance_to(second) <= 2.5: return true
	return false

func _landing_supported(at: Vector3, player_rid: RID) -> bool:
	var ray: Dictionary = _ray(at,at-Vector3.UP*2.0,[player_rid])
	return not ray.is_empty() and at.y-float(ray.position.y) >= 0.0 and at.y-float(ray.position.y) <= 1.2

static func _evidence_keys() -> Array:
	return ["opening:whale_raw_command_record","F2:aligned_timeline","F3:living_isolation"]

static func _digest(value) -> bool:
	if not value is String or value.length() != 64: return false
	for character in value:
		if character not in "0123456789abcdef": return false
	return true

static func _mm_valid(value) -> bool:
	if not value is Array or value.size() != 3: return false
	for number in value:
		if not _integer(number,-1000000,1000000): return false
	return true

static func _metres(value: Array) -> Vector3:
	return Vector3(float(value[0])/1000.0,float(value[1])/1000.0,float(value[2])/1000.0)
