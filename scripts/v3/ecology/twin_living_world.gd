class_name TwinLivingWorld
extends RefCounted
## Session adapter. Simulation, bounded facility stock and consumption share one save.
const State = preload("res://scripts/v3/ecology/twin_ecology_state.gd")
const CampaignNpc = preload("res://scripts/v3/campaign/twin_campaign_npc_routes.gd")
const View = preload("res://scripts/v3/art/twin_ecology_view.gd")
const Anchors = preload("res://scripts/v3/ecology/twin_npc_anchors.gd")
const SERVICE_POSITION = Vector3(-29, 2.0, 13)
var session
var simulation = State.new()
var facilities: Dictionary = {"coolant":0, "maintenance":{}, "deliveries":0}
var last_event_serial = 0
var view
var ready = false
var service_clock = 0.0
var weather_seed = 1
var serial = 0
var epoch = 0
var expected_serial = -1
var expected_epoch = -1
var applied_serial = -1
var pending: Dictionary = {}

func reset_connection() -> void:
	serial = 0
	epoch = 0
	expected_serial = -1
	expected_epoch = -1
	applied_serial = -1
	pending.clear()

func setup(owner_session) -> bool:
	session = owner_session
	var built: Dictionary = _expanded_simulation(1)
	ready = built.ok
	if ready: simulation = built.simulation
	return ready

func _expanded_simulation(seed: int) -> Dictionary:
	var previous = State.new()
	if not previous.load_routes(State.DEFAULT_PATH, seed).get("ok", false): return {"ok":false}
	var combined: Dictionary = CampaignNpc.combined_definition(previous.definitions())
	if not combined.ok: return {"ok":false}
	var expanded = State.new()
	if not expanded.configure(combined.definition, seed).get("ok", false): return {"ok":false}
	return {"ok":true,"simulation":expanded,"previous":previous}

func restore_world(world_data: Dictionary, apply: bool = true) -> bool:
	var seed = 1 + int(str(session.world_cache.get("lineage_id", "twinpulse")).hash()) % 2147483646
	var built: Dictionary = _expanded_simulation(seed)
	if not built.ok: return false
	var candidate = built.simulation
	var saved: Variant = world_data.get("ecology", {})
	if not saved is Dictionary: return false
	var next_facilities: Dictionary = {"coolant":0, "maintenance":{}, "deliveries":0}
	var serial = 0
	if not saved.is_empty():
		if saved.size() != 3 or not saved.get("simulation") is Dictionary or not saved.get("facilities") is Dictionary: return false
		if not candidate.restore(saved.simulation).get("ok", false):
			# The old graph must validate its own history before the new graph
			# adds residents. RNG, jobs, cargo and old routes are preserved.
			if not built.previous.restore(saved.simulation).get("ok", false): return false
			var migrated: Dictionary = CampaignNpc.migrate_snapshot(built.previous, candidate)
			if not migrated.get("ok", false) or not candidate.restore(migrated.snapshot).get("ok", false): return false
		var raw: Dictionary = saved.facilities
		if raw.size() != 3 or not raw.get("maintenance") is Dictionary: return false
		if not _integer(raw.get("coolant"), 0, 3) or not _integer(raw.get("deliveries"), 0, 9007199254740000): return false
		if raw.maintenance.size() > 8: return false
		for id in raw.maintenance:
			if id not in ["I1:thermal", "I1:relay", "F1:grove_care"] or not _integer(raw.maintenance[id], 0, 3): return false
		if not _integer(saved.get("last_event_serial"), 0, 9007199254740000): return false
		serial = int(saved.last_event_serial)
		if serial != int(saved.simulation.event_serial): return false
		next_facilities = raw.duplicate(true)
		for key in ["coolant", "deliveries"]: next_facilities[key] = int(next_facilities[key])
		for id in next_facilities.maintenance: next_facilities.maintenance[id] = int(next_facilities.maintenance[id])
	if not apply: return true
	simulation = candidate
	weather_seed = int(simulation.snapshot().seed)
	facilities = next_facilities
	last_event_serial = serial
	service_clock = 0.0
	ready = true
	return true

func persistent_state() -> Dictionary:
	return {"simulation":simulation.snapshot(), "facilities":facilities.duplicate(true), "last_event_serial":last_event_serial}

func bind_world() -> void:
	view = View.new()
	view.name = "LivingWorldPresentation"
	view.view_camera = session.camera
	session.world.add_child(view)
	view.configure(session.region_id, simulation.definitions())
	if session.network.is_authority():
		epoch += 1
		apply_view(view_packet())
		publish()
	else:
		# This view is empty even if a previous view already displayed this tick.
		applied_serial = -1

func weather_for(region: String) -> String:
	var tick = int(simulation.elapsed_seconds())
	var local_tick = tick + (97 if region == "F1" else 0)
	var cycle = int(local_tick / 360)
	var phase = local_tick % 360
	# Per-world, per-front variation, derived from persisted seed and elapsed
	# simulation time. Reloading/visiting another region never rerolls weather.
	var noise = (weather_seed + (cycle % 2147483647) * 48271 + (69621 if region == "F1" else 0)) % 2147483647
	var rain_start = 180 + noise % 60
	var storm_start = rain_start + 20 + int(noise / 61) % 15
	var storm_end = storm_start + 20 + int(noise / 919) % 20
	if phase >= storm_start and phase < storm_end: return "storm"
	if phase >= rain_start and phase < storm_end + 20: return "rain"
	return "clear"

func advance(delta: float) -> void:
	if not ready or not session.owns_world or not session.network.is_authority() or session.simulation_paused: return
	var contexts: Dictionary = {}
	var known_regions: Array = []
	for definition: Dictionary in simulation.definitions().regions:
		var region: String = str(definition.id)
		known_regions.append(region)
		if region not in ["I1", "F1"]:
			contexts[region] = CampaignNpc.region_context(region, session.world_cache.world.get("flags", {}), weather_for(region))
			continue
		var source: Dictionary = session.entities if region == session.region_id else session.world_cache.world.get("entities", {}).get(region, {})
		var relay: Dictionary = source.get(region + ":relay", {})
		var thermal: Dictionary = source.get(region + ":thermal", {})
		var beacon: Dictionary = source.get(region + ":beacon", {})
		var power = bool(relay.get("powered", false)) or float(relay.get("charge", 0)) >= 40 or bool(beacon.get("powered", false))
		var maintenance = power or float(thermal.get("temperature", 20)) >= 55
		var danger: Array = []
		if region == "I1" and float(thermal.get("temperature", 20)) >= 85: danger.append("maintenance")
		contexts[region] = {"powered":power, "supply_powered":power, "maintenance_powered":maintenance, "weather":weather_for(region), "danger_nodes":danger}
	var result: Dictionary = simulation.advance(delta, session.region_id if session.region_id in known_regions else "", contexts, true)
	if not result.get("ok", false): return
	var emission_branch: String = str(session.world_cache.world.branch_id)
	for event in result.events:
		var serial = int(event.serial)
		if serial <= last_event_serial: continue
		if event.kind == "transport_arrival" and event.target_id == "I1:maintenance_cooling":
			facilities.coolant = mini(3, int(facilities.coolant) + 1)
			facilities.deliveries = int(facilities.deliveries) + 1
		elif event.kind == "repair_progress" and event.target_id in ["I1:thermal", "I1:relay", "F1:grove_care"]:
			facilities.maintenance[event.target_id] = mini(3, int(facilities.maintenance.get(event.target_id, 0)) + 1)
		last_event_serial = serial
	# Seal the whole native batch before preparing a campaign proof. The later
	# campaign tick re-samples the physical support, then commits both snapshots.
	for event: Dictionary in result.events: session.campaign.queue_ecology_event(event,emission_branch)
	session.sidejobs.ecology_batch(result.events,emission_branch)
	session.field_requests.ecology_batch(result.events,emission_branch)
	apply_view(view_packet())
	if int(result.get("ticks", 0)) > 0: publish()
	service_clock += delta
	if service_clock >= 2.0:
		service_clock = 0.0
		_try_service()

func _try_service() -> bool:
	if session.region_id != "I1" or session.boss_active or session.pending_completion or session.simulation_paused: return false
	if int(facilities.coolant) <= 0 or not session.consensus.current_proposal().is_empty(): return false
	if float(session.entities.get("I1:thermal", {}).get("temperature", 20)) >= 85: return false
	var ids: Array = session.players.keys()
	ids.sort()
	for id in ids:
		var body = session.players[id]
		if not body.enabled or body.health >= body.maximum_health or body.global_position.distance_to(SERVICE_POSITION) > 4.0: continue
		var old_stock = int(facilities.coolant)
		facilities.coolant = old_stock - 1
		# Consumption commits before health changes. Failed writes neither heal nor
		# spend stock. No inventory reward, guest receipt or offline clock is involved.
		if not session._commit("ecology-service", {"world.ecology":persistent_state()}):
			facilities.coolant = old_stock
			return false
		body.health = minf(body.maximum_health, body.health + 25.0)
		body.damage_state.health = body.health
		session.entities[session._actor_id(id)].health = body.health
		session._note(id, "检修台使用 1 份运来的冷却液，恢复 25 点机体耐久。")
		apply_view(view_packet())
		publish()
		return true
	return false

func view_packet() -> Dictionary:
	var actors: Array = []
	for actor in simulation.get_actors(session.region_id):
		actors.append({"id":actor.id, "p":Anchors.local_position(actor), "phase":actor.phase, "reason":actor.reason, "cargo":actor.cargo})
	return {"actors":actors, "coolant":int(facilities.coolant), "weather":weather_for(session.region_id), "maintenance":facilities.maintenance.duplicate(true)}

func state_event() -> Dictionary:
	return {"kind":"ecology_state", "session_id":session.network.session_id, "serial":serial, "epoch":epoch, "region":session.region_id, "state":view_packet()}

func publish(peer_id: int = 0) -> void:
	if not session.owns_world or not session.network.is_authority(): return
	if peer_id == 0: serial += 1
	var event = state_event()
	if peer_id > 1: session.network.send_event(peer_id, event)
	else:
		for id in session.network.guests: session.network.send_event(int(id), event)

func receive(event: Dictionary) -> void:
	if session.network.mode != "guest" or not session.active: return
	if str(event.get("session_id", "")).is_empty() or not event.get("state") is Dictionary: return
	if not _integer(event.get("epoch"), 1, 9007199254740000) or not _integer(event.get("serial"), 1, 9007199254740000): return
	if not session.received_session.is_empty() and event.session_id != session.received_session: return
	if not pending.is_empty() and pending.session_id != event.session_id: pending.clear()
	if int(event.epoch) < expected_epoch: return
	if int(event.get("serial", -1)) <= applied_serial: return
	if int(event.get("serial", -1)) < int(pending.get("serial", -1)): return
	pending = event.duplicate(true)
	consume(expected_serial, expected_epoch)

func consume(snapshot_serial: int, snapshot_epoch: int) -> void:
	if session.network.mode != "guest": return
	expected_serial = snapshot_serial
	expected_epoch = snapshot_epoch
	if pending.is_empty() or session.received_session.is_empty(): return
	if pending.session_id != session.received_session:
		pending.clear()
		return
	if int(pending.epoch) != expected_epoch or str(pending.region) != session.region_id: return
	# Reliable messages may remain seconds behind the motion channel. Applying
	# the newest received state avoids starvation while a scene epoch prevents
	# an old visit to the same region from leaking into the newly loaded world.
	if int(pending.serial) > expected_serial or int(pending.serial) <= applied_serial: return
	apply_view(pending.state)
	applied_serial = int(pending.serial)

func apply_view(packet: Dictionary) -> void:
	if is_instance_valid(view): view.apply_state(packet)
	if is_instance_valid(session.world):
		session.world.ecology_weather = str(packet.get("weather", "clear"))
		# The existing mechanisms.clock packet carries this exact phase to guests.
		if session.network.is_authority(): session.world.clock_seconds = simulation.elapsed_seconds()

func update_view(delta: float, focus: Vector3) -> void:
	if is_instance_valid(view): view.update_presentation(delta, focus, session.simulation_paused)

func _integer(value: Variant, low: int, high: int) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and float(value) >= low and float(value) <= high and floor(float(value)) == float(value)
