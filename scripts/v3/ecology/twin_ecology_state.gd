class_name TwinEcologyState
extends RefCounted
## Host-owned, JSON-safe, fixed-step route simulation. No Nodes, clocks or rewards.

const DEFAULT_PATH := "res://data/v3/ecology/routes.json"
const SCHEMA := 1
const MAX_ACTORS := 12
const MAX_REGIONS := 8
const MAX_NODES := 24
const MAX_JOBS := 8
const MAX_DELTA := 10.0
const STEP_USEC := 1000000
const RNG_MOD := 2147483647
const MAX_COUNTER := 9007199254740000
const PHASES := ["traveling", "detouring", "working", "waiting", "seeking_shelter", "sheltered"]
const WEATHER := ["clear", "rain", "storm"]
const JOBS := ["inspect", "repair", "pickup", "deliver", "pollinate"]
const EVENT_TYPES := {"inspect":"inspection_complete", "repair":"repair_progress", "pickup":"cargo_loaded", "deliver":"transport_arrival", "pollinate":"pollination_progress"}

var _definition: Dictionary = {}
var _graphs: Dictionary = {}
var _actor_defs: Dictionary = {}
var _state: Dictionary = {}
var _digest := ""

func load_routes(path: String = DEFAULT_PATH, seed: int = 1) -> Dictionary:
	if not FileAccess.file_exists(path): return _result(false, "routes_missing")
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null: return _result(false, "routes_unreadable")
	if file.get_length() > 131072:
		file.close()
		return _result(false, "routes_too_large")
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	if not parsed is Dictionary: return _result(false, "invalid_routes_json")
	return configure(parsed, seed)

func configure(definition: Dictionary, seed: int = 1) -> Dictionary:
	# Validate into local indexes first: a failed reconfigure leaves the old run intact.
	var checked := _validate_definition(definition)
	if not checked.ok: return checked
	if seed < 1 or seed >= RNG_MOD: return _result(false, "invalid_seed")
	_definition = definition.duplicate(true)
	_graphs = checked.graphs
	_actor_defs = checked.actors
	_digest = JSON.stringify(_definition, "", true, true).sha256_text()
	_state = {"schema_version":SCHEMA, "content_id":str(definition.content_id), "routes_digest":_digest,
		"seed":seed, "rng_state":seed, "tick":0, "pending_usec":0, "event_serial":0, "contexts":{}, "actors":{}}
	for region in _sorted(_graphs):
		_state.contexts[region] = {"powered":true, "supply_powered":true, "maintenance_powered":true, "weather":"clear", "danger_nodes":[]}
	for id in _sorted(_actor_defs):
		var actor: Dictionary = _actor_defs[id]
		_state.actors[id] = {"id":id, "region":actor.region, "node":actor.start_node, "next_node":"", "progress":0.0,
			"position":_graphs[actor.region].nodes[actor.start_node].position.duplicate(), "job_index":0,
			"work_left":-1.0, "phase":"waiting", "reason":"initializing", "cargo":false, "cycles":0, "steps_completed":0,
			"reserve_remaining":float(actor.power_policy.reserve_seconds)}
	return _result(true, "configured")

func definitions() -> Dictionary:
	return _definition.duplicate(true)

func snapshot() -> Dictionary:
	return _state.duplicate(true)

func elapsed_seconds() -> float:
	return float(_state.get("tick", 0)) + float(_state.get("pending_usec", 0)) / float(STEP_USEC)

func get_actor(id: String) -> Dictionary:
	if not _state.get("actors", {}).has(id): return {}
	var actor: Dictionary = _state.actors[id].duplicate(true)
	for key in ["name", "role", "purpose", "speed"]: actor[key] = _actor_defs[id][key]
	return actor

func get_actors(region: String = "") -> Array:
	var actors: Array = []
	for id in _sorted(_state.get("actors", {})):
		if region.is_empty() or _state.actors[id].region == region: actors.append(get_actor(id))
	return actors

func advance(delta: float, active_region: String, contexts: Dictionary = {}, is_authority: bool = true) -> Dictionary:
	if _state.is_empty(): return _result(false, "not_configured")
	if not is_authority: return _result(false, "authority_required")
	if not is_finite(delta) or delta < 0.0 or delta > MAX_DELTA: return _result(false, "invalid_delta")
	# Empty means the player visits a region without an authored ecology graph.
	# Existing graphs keep advancing; an unknown named graph remains an error.
	if not active_region.is_empty() and not _graphs.has(active_region): return _result(false, "unknown_active_region")
	if contexts.size() > MAX_REGIONS: return _result(false, "context_limit")
	# Pause is a true no-op, including context, RNG and fractional phase.
	if delta == 0.0: return _result(true, "paused")
	if int(_state.tick) > MAX_COUNTER - 11 or int(_state.event_serial) > MAX_COUNTER - MAX_ACTORS * 11:
		return _result(false, "counter_limit")
	var warnings := _update_contexts(contexts)
	_state.pending_usec += int(round(delta * 1000000.0))
	var ticks := 0
	var events: Array = []
	while int(_state.pending_usec) >= STEP_USEC:
		_state.pending_usec -= STEP_USEC
		_state.tick += 1
		ticks += 1
		# All loaded regions advance at the same low frequency, independent of camera.
		for id in _sorted(_actor_defs): _tick_actor(id, events)
	var result := _result(true, "advanced")
	result.events = events
	result.warnings = warnings
	result.ticks = ticks
	return result

func validate_snapshot(candidate: Dictionary) -> Dictionary:
	if _state.is_empty(): return _result(false, "not_configured")
	var keys := ["schema_version", "content_id", "routes_digest", "seed", "rng_state", "tick", "pending_usec", "event_serial", "contexts", "actors"]
	if not _exact_keys(candidate, keys): return _result(false, "snapshot_keys")
	if candidate.schema_version != SCHEMA or candidate.content_id != _state.content_id or candidate.routes_digest != _digest:
		return _result(false, "snapshot_definition_mismatch")
	for key in ["seed", "rng_state"]:
		if not _integer(candidate[key], 1, RNG_MOD - 1): return _result(false, "snapshot_rng")
	for key in ["tick", "event_serial"]:
		if not _integer(candidate[key], 0, MAX_COUNTER): return _result(false, "snapshot_counter")
	if not _integer(candidate.pending_usec, 0, STEP_USEC - 1): return _result(false, "snapshot_phase")
	if not candidate.contexts is Dictionary or not _exact_keys(candidate.contexts, _graphs.keys()): return _result(false, "snapshot_contexts")
	for region in _graphs:
		var context: Variant = candidate.contexts[region]
		if not context is Dictionary or not _exact_keys(context, ["powered", "supply_powered", "maintenance_powered", "weather", "danger_nodes"]): return _result(false, "snapshot_contexts")
		for key in ["powered", "supply_powered", "maintenance_powered"]:
			if not context[key] is bool: return _result(false, "snapshot_contexts")
		if context.weather not in WEATHER or not _danger_valid(context.danger_nodes, region): return _result(false, "snapshot_contexts")
	if not candidate.actors is Dictionary or not _exact_keys(candidate.actors, _actor_defs.keys()): return _result(false, "snapshot_actors")
	var completed := 0
	for id in _actor_defs:
		if not _actor_valid(id, candidate.actors[id], int(candidate.tick)): return _result(false, "snapshot_actor_invalid")
		completed += int(candidate.actors[id].steps_completed)
	if completed != int(candidate.event_serial): return _result(false, "snapshot_event_serial")
	return _result(true, "snapshot_valid")

func restore(candidate: Dictionary) -> Dictionary:
	var checked := validate_snapshot(candidate)
	if not checked.ok: return checked
	_state = candidate.duplicate(true)
	# JSON decodes integral values as floats; normalize counters used by RNG/modulo.
	for key in ["schema_version", "seed", "rng_state", "tick", "pending_usec", "event_serial"]: _state[key] = int(_state[key])
	for actor in _state.actors.values():
		for key in ["job_index", "cycles", "steps_completed"]: actor[key] = int(actor[key])
		actor.progress = _fraction(float(actor.progress))
		# JSON's decimal parse can differ by a final binary digit. The canonical
		# position is derived from the validated graph and binary32 edge fraction.
		_refresh_position(actor)
	return _result(true, "restored")

func _tick_actor(id: String, events: Array) -> void:
	var actor: Dictionary = _state.actors[id]
	var spec: Dictionary = _actor_defs[id]
	var graph: Dictionary = _graphs[actor.region]
	var context: Dictionary = _state.contexts[actor.region]
	var blocked: Array = context.danger_nodes
	var shelter: bool = str(context.weather) in spec.shelter_weather
	var policy: Dictionary = spec.power_policy
	var powered: bool = context[policy.channel]
	var returning_supply := false
	if powered:
		actor.reserve_remaining = minf(float(policy.reserve_seconds), float(actor.reserve_remaining) + 2.0)
	# If a destination becomes dangerous mid-edge, retrace that exact segment.
	# This preserves position, rather than teleporting to a graph node.
	if not str(actor.next_node).is_empty() and actor.next_node in blocked:
		if actor.node in blocked:
			_set_phase(actor, "waiting", "both_edge_ends_dangerous")
			return
		var old_from: String = actor.node
		actor.node = actor.next_node
		actor.next_node = old_from
		actor.progress = _fraction(1.0 - float(actor.progress))
		_set_phase(actor, "detouring", "retreat_from_danger")
		_move(actor, spec.speed)
		return
	if actor.node in blocked: shelter = true
	# Facility power is not the drone's flight battery: evacuation still works.
	if not powered and not shelter:
		match policy.loss:
			"wait":
				_set_phase(actor, "waiting", "power_unavailable")
				return
			"reserve":
				if float(actor.reserve_remaining) <= 0.0:
					_set_phase(actor, "waiting", "reserve_depleted")
					return
				actor.reserve_remaining = maxf(0.0, float(actor.reserve_remaining) - 1.0)
			"return_supply": returning_supply = not actor.cargo
	var job: Dictionary = spec.jobs[int(actor.job_index)]
	var goal: String = spec.shelter_node if shelter else job.node
	if returning_supply: goal = policy.supply_node
	if not str(actor.next_node).is_empty():
		_set_phase(actor, "seeking_shelter" if shelter else ("detouring" if not blocked.is_empty() else "traveling"), "weather_or_danger" if shelter else "route")
		_move(actor, spec.speed)
		return
	if actor.node == goal:
		if shelter:
			_set_phase(actor, "sheltered", "weather_or_danger")
			return
		if returning_supply:
			_set_phase(actor, "waiting", "supply_unavailable")
			return
		if job.kind == "deliver" and not actor.cargo:
			_set_phase(actor, "waiting", "cargo_required")
			return
		_set_phase(actor, "working", job.kind)
		if float(actor.work_left) < 0.0: actor.work_left = float(job.work_seconds) + float(_random() % 3)
		actor.work_left = maxf(0.0, float(actor.work_left) - 1.0)
		if float(actor.work_left) <= 0.0: _finish_job(actor, spec, job, events)
		return
	var path := _path(graph.nodes, actor.node, goal, blocked)
	if path.size() < 2:
		_set_phase(actor, "waiting", "route_blocked")
		return
	actor.next_node = path[1]
	actor.progress = 0.0
	_set_phase(actor, "seeking_shelter" if shelter else ("detouring" if not blocked.is_empty() else "traveling"), "weather_or_danger" if shelter else "route")
	_move(actor, spec.speed)

func _move(actor: Dictionary, speed: float) -> void:
	var nodes: Dictionary = _graphs[actor.region].nodes
	var from := _vector(nodes[actor.node].position)
	var to := _vector(nodes[actor.next_node].position)
	actor.progress = _fraction(minf(1.0, float(actor.progress) + speed / from.distance_to(to)))
	if float(actor.progress) >= 1.0:
		actor.node = actor.next_node
		actor.next_node = ""
		actor.progress = 0.0
	_refresh_position(actor)

func _refresh_position(actor: Dictionary) -> void:
	var nodes: Dictionary = _graphs[actor.region].nodes
	if str(actor.next_node).is_empty():
		actor.position = nodes[actor.node].position.duplicate()
		return
	var at := _vector(nodes[actor.node].position).lerp(_vector(nodes[actor.next_node].position), float(actor.progress))
	actor.position = [at.x, at.y, at.z]

func _fraction(value: float) -> float:
	# Persist the same precision as Godot's Vector3 arithmetic. This makes JSON
	# roundtrips canonical without hiding drift in tolerant snapshot comparisons.
	return float(PackedFloat32Array([value])[0])

func _finish_job(actor: Dictionary, spec: Dictionary, job: Dictionary, events: Array) -> void:
	if job.kind == "pickup": actor.cargo = true
	if job.kind == "deliver": actor.cargo = false
	_state.event_serial += 1
	actor.steps_completed += 1
	var event := {"id":"ecology:%s:%d:%d" % [_state.content_id, int(_state.seed), int(_state.event_serial)],
		"type":EVENT_TYPES[job.kind], "actor_id":actor.id, "region_id":actor.region,
		"target_id":job.target_id, "amount":1, "tick":int(_state.tick), "cycle":int(actor.cycles),
		"position":actor.position.duplicate()}
	event["serial"] = int(_state.event_serial)
	event["event_id"] = event.id
	event["kind"] = event.type
	event["region"] = actor.region
	events.append(event)
	actor.job_index = (int(actor.job_index) + 1) % spec.jobs.size()
	if int(actor.job_index) == 0: actor.cycles += 1
	actor.work_left = -1.0
	_set_phase(actor, "waiting", "job_completed")

func _path(nodes: Dictionary, start: String, goal: String, blocked: Array) -> Array:
	if goal in blocked: return []
	var queue: Array = [start]
	var parents: Dictionary = {start:""}
	var head := 0
	while head < queue.size() and head < MAX_NODES:
		var node: String = queue[head]
		head += 1
		if node == goal:
			var path: Array = []
			var cursor := goal
			while not cursor.is_empty():
				path.push_front(cursor)
				cursor = parents[cursor]
			return path
		var neighbors: Array = nodes[node].neighbors.duplicate()
		neighbors.sort()
		for neighbor in neighbors:
			if neighbor in blocked or parents.has(neighbor): continue
			parents[neighbor] = node
			queue.append(neighbor)
	return []

func _update_contexts(contexts: Dictionary) -> Array:
	var warnings: Array = []
	for region in contexts:
		if not _graphs.has(region):
			warnings.append({"code":"unknown_region", "region":str(region)})
			continue
		var input: Variant = contexts[region]
		if not input is Dictionary or input.size() > 16:
			warnings.append({"code":"invalid_region_context", "region":region})
			continue
		# Explicit channels in the same packet override the overall supply value.
		if input.get("powered") is bool:
			for channel in ["powered", "supply_powered", "maintenance_powered"]:
				_state.contexts[region][channel] = input.powered
		for key in input:
			var valid := false
			match key:
				"powered", "supply_powered", "maintenance_powered": valid = input[key] is bool
				"weather": valid = input[key] in WEATHER
				"danger_nodes": valid = _danger_valid(input[key], region)
				_:
					warnings.append({"code":"unknown_context_key", "region":region, "field":str(key)})
					continue
			if not valid:
				warnings.append({"code":"invalid_context_value", "region":region, "field":key})
				continue
			_state.contexts[region][key] = input[key].duplicate() if input[key] is Array else input[key]
	return warnings

func _danger_valid(value: Variant, region: String) -> bool:
	if not value is Array or value.size() > MAX_NODES: return false
	var seen: Dictionary = {}
	for id in value:
		if not id is String or not _graphs[region].nodes.has(id) or seen.has(id): return false
		seen[id] = true
	return true

func _actor_valid(id: String, value: Variant, tick: int) -> bool:
	var keys := ["id", "region", "node", "next_node", "progress", "position", "job_index", "work_left", "phase", "reason", "cargo", "cycles", "steps_completed", "reserve_remaining"]
	if not value is Dictionary or not _exact_keys(value, keys): return false
	var spec: Dictionary = _actor_defs[id]
	var nodes: Dictionary = _graphs[spec.region].nodes
	if value.id != id or value.region != spec.region or not nodes.has(value.node): return false
	if not value.next_node is String or not _number(value.progress, 0.0, 1.0): return false
	if not _position_valid(value.position): return false
	var expected := _vector(nodes[value.node].position)
	if str(value.next_node).is_empty():
		if float(value.progress) != 0.0: return false
	else:
		if value.next_node not in nodes[value.node].neighbors or _fraction(float(value.progress)) >= 1.0: return false
		expected = expected.lerp(_vector(nodes[value.next_node].position), float(value.progress))
	if expected.distance_to(_vector(value.position)) > 0.001: return false
	if not _integer(value.job_index, 0, spec.jobs.size() - 1): return false
	if not _number(value.work_left, -1.0, float(spec.jobs[int(value.job_index)].work_seconds) + 2.0): return false
	if value.phase not in PHASES or not value.reason is String or value.reason.length() > 64 or not value.cargo is bool: return false
	if not _number(value.reserve_remaining, 0.0, float(spec.power_policy.reserve_seconds)): return false
	if not _integer(value.steps_completed, 0, tick) or not _integer(value.cycles, 0, tick): return false
	if int(value.steps_completed) != int(value.cycles) * spec.jobs.size() + int(value.job_index): return false
	# Carrying water is legal only between the authored pickup and delivery steps.
	var cargo := false
	for index in range(int(value.job_index)):
		if spec.jobs[index].kind == "pickup": cargo = true
		if spec.jobs[index].kind == "deliver": cargo = false
	return value.cargo == cargo

func _validate_definition(data: Dictionary) -> Dictionary:
	if data.get("schema_version") != SCHEMA or not _id(data.get("content_id")): return _result(false, "invalid_routes_schema")
	if not data.get("regions") is Array or data.regions.is_empty() or data.regions.size() > MAX_REGIONS: return _result(false, "region_limit")
	if not data.get("actors") is Array or data.actors.is_empty() or data.actors.size() > MAX_ACTORS: return _result(false, "actor_limit")
	var graphs: Dictionary = {}
	for region in data.regions:
		if not region is Dictionary or not _id(region.get("id")) or graphs.has(region.id): return _result(false, "invalid_region")
		if not region.get("nodes") is Array or region.nodes.size() < 2 or region.nodes.size() > MAX_NODES: return _result(false, "node_limit")
		var nodes: Dictionary = {}
		for node in region.nodes:
			if not node is Dictionary or not _id(node.get("id")) or nodes.has(node.id) or not _position_valid(node.get("position")): return _result(false, "invalid_node")
			if region.id == "F1" and float(node.position[1]) < 12.0: return _result(false, "fantasy_flight_clearance")
			if not node.get("neighbors") is Array or node.neighbors.is_empty() or node.neighbors.size() > MAX_NODES: return _result(false, "invalid_neighbors")
			nodes[node.id] = node.duplicate(true)
		for id in nodes:
			var seen: Dictionary = {}
			for neighbor in nodes[id].neighbors:
				if not neighbor is String or not nodes.has(neighbor) or neighbor == id or seen.has(neighbor): return _result(false, "invalid_edge")
				if id not in nodes[neighbor].neighbors or _vector(nodes[id].position).distance_to(_vector(nodes[neighbor].position)) < 1.0: return _result(false, "invalid_edge")
				seen[neighbor] = true
		for id in nodes:
			if _path(nodes, str(nodes.keys()[0]), id, []).is_empty(): return _result(false, "disconnected_graph")
		graphs[region.id] = {"nodes":nodes}
	var actors: Dictionary = {}
	for actor in data.actors:
		if not actor is Dictionary or not _id(actor.get("id")) or actors.has(actor.id) or not graphs.has(actor.get("region")): return _result(false, "invalid_actor")
		for key in ["name", "role", "purpose"]:
			if not actor.get(key) is String or actor[key].is_empty() or actor[key].length() > 256: return _result(false, "invalid_actor_purpose")
		var nodes: Dictionary = graphs[actor.region].nodes
		if not nodes.has(actor.get("start_node")) or not nodes.has(actor.get("shelter_node")) or not _number(actor.get("speed"), 0.2, 6.0): return _result(false, "invalid_actor_route")
		if not actor.get("power_policy") is Dictionary or not actor.get("shelter_weather") is Array or actor.shelter_weather.size() > 2: return _result(false, "invalid_actor_policy")
		var policy: Dictionary = actor.power_policy
		if policy.get("channel") not in ["powered", "supply_powered", "maintenance_powered"] or policy.get("loss") not in ["ignore", "wait", "reserve", "return_supply"]: return _result(false, "invalid_actor_policy")
		if not _number(policy.get("reserve_seconds"), 0.0, 120.0) or not nodes.has(policy.get("supply_node")): return _result(false, "invalid_actor_policy")
		if policy.loss == "reserve" and float(policy.reserve_seconds) < 1.0: return _result(false, "invalid_actor_policy")
		for weather in actor.shelter_weather:
			if weather not in ["rain", "storm"]: return _result(false, "invalid_actor_policy")
		if not actor.get("jobs") is Array or actor.jobs.is_empty() or actor.jobs.size() > MAX_JOBS: return _result(false, "job_limit")
		var cargo := false
		for job in actor.jobs:
			if not job is Dictionary or not nodes.has(job.get("node")) or job.get("kind") not in JOBS or not _id(job.get("target_id")) or not _number(job.get("work_seconds"), 1.0, 30.0): return _result(false, "invalid_job")
			if job.kind == "pickup":
				if cargo: return _result(false, "invalid_cargo_cycle")
				cargo = true
			if job.kind == "deliver":
				if not cargo: return _result(false, "invalid_cargo_cycle")
				cargo = false
		if cargo: return _result(false, "invalid_cargo_cycle")
		actors[actor.id] = actor.duplicate(true)
	return {"ok":true, "code":"valid", "graphs":graphs, "actors":actors}

func _random() -> int:
	_state.rng_state = (int(_state.rng_state) * 48271) % RNG_MOD
	return int(_state.rng_state)

func _set_phase(actor: Dictionary, phase: String, reason: String) -> void:
	actor.phase = phase
	actor.reason = reason

func _sorted(dict: Dictionary) -> Array:
	var keys: Array = dict.keys()
	keys.sort()
	return keys

func _exact_keys(dict: Dictionary, keys: Array) -> bool:
	if dict.size() != keys.size(): return false
	for key in keys:
		if not dict.has(key): return false
	return true

func _id(value: Variant) -> bool:
	return value is String and not value.is_empty() and value.length() <= 120

func _number(value: Variant, minimum: float, maximum: float) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and float(value) >= minimum and float(value) <= maximum

func _integer(value: Variant, minimum: int, maximum: int) -> bool:
	return _number(value, minimum, maximum) and floor(float(value)) == float(value)

func _position_valid(value: Variant) -> bool:
	if not value is Array or value.size() != 3: return false
	return _number(value[0], -48.0, 48.0) and _number(value[1], 0.0, 26.0) and _number(value[2], -45.0, 45.0)

func _vector(value: Array) -> Vector3:
	return Vector3(float(value[0]), float(value[1]), float(value[2]))

func _result(ok: bool, code: String) -> Dictionary:
	return {"ok":ok, "code":code, "events":[], "warnings":[], "ticks":0}
