class_name TwinEncounterState
extends RefCounted
## Encounter authority only. Attack events must be realised and collision-checked by the world.

const CORE_HEALTH := 120.0
const NODE_HEALTH := 40.0
const REVIVE_DISTANCE := 3.0
const REVIVE_SECONDS := 2.5
const ATTACKS := ["low_sweep", "high_lance", "tractor"]
var _state: Dictionary = {}
var _checkpoint: Dictionary = {}

func start(snapshot: Dictionary) -> Dictionary:
	_checkpoint = snapshot.duplicate(true)
	_state = {"attempt": 0}
	return reset_attempt("start")

func get_state() -> Dictionary:
	return _state.duplicate(true)

func add_player(player_id: String, snapshot: Dictionary) -> Dictionary:
	if _state.is_empty():
		return _reject("encounter_not_started")
	if _state.completed:
		return _reject("encounter_completed")
	if player_id.is_empty():
		return _reject("invalid_player_id")
	if _state.players.has(player_id):
		return _reject("player_already_present")
	if _state.players.size() >= 2:
		return _reject("party_full")
	if not snapshot.get("position") is Vector3 or not snapshot.position.is_finite():
		return _reject("invalid_entrance_position")
	var maximum: Variant = snapshot.get("max_health", 100.0)
	if not (maximum is int or maximum is float) or not is_finite(float(maximum)) or float(maximum) <= 0.0:
		return _reject("invalid_max_health")
	var player := snapshot.duplicate(true)
	player.max_health = float(maximum)
	player.health = float(maximum)
	player.downed = false
	if not _checkpoint.has("players"):
		_checkpoint.players = {}
	# Entry snapshot is also this player's retry location, independent of movement.
	_checkpoint.players[player_id] = player.duplicate(true)
	_state.players[player_id] = player
	return {"ok": true, "code": "player_added", "events": [{"type": "player_joined", "player_id": player_id, "position": player.position, "health": player.health, "attempt": _state.attempt}]}

func remove_player(player_id: String) -> Dictionary:
	if _state.is_empty():
		return _reject("encounter_not_started")
	if not _state.players.has(player_id):
		return _reject("player_missing")
	_state.players.erase(player_id)
	_checkpoint.get("players", {}).erase(player_id)
	var events: Array = [{"type": "player_left", "player_id": player_id}]
	if _state.players.is_empty():
		# A vacant encounter is frozen, not won, lost or rewarded.
		events.append({"type": "encounter_empty", "attempt": _state.attempt})
	elif not _state.completed and _all_players_downed():
		reset_attempt("remaining_players_downed")
		events.append({"type": "attempt_reset", "reason": "remaining_players_downed", "attempt": _state.attempt})
	return {"ok": true, "code": "player_removed", "events": events}

func reset_attempt(reason: String = "manual") -> Dictionary:
	var attempt := int(_state.get("attempt", 0)) + 1
	var players: Dictionary = _checkpoint.get("players", {}).duplicate(true)
	for player_id in players:
		players[player_id].health = float(players[player_id].get("max_health", 100.0))
		players[player_id].downed = false
	_state = {
		"boss_id": "harbor_whale", "attempt": attempt, "reset_reason": reason,
		"players": players, "core_health": CORE_HEALTH, "core_max_health": CORE_HEALTH,
		"phase": "shielded", "overdrive": false, "exposed_remaining": 0.0,
		"nodes": {"port": {"health": NODE_HEALTH, "powered": true}, "starboard": {"health": NODE_HEALTH, "powered": true}},
		"attack_index": 0, "attack_state": "windup", "attack_remaining": 2.0,
		"telegraph": "low_sweep", "nodes_open": false, "completed": false,
	}
	return get_state()

func set_player_position(player_id: String, position: Vector3) -> bool:
	if not position.is_finite() or not _state.get("players", {}).has(player_id):
		return false
	_state.players[player_id].position = position
	return true

func advance(delta: float) -> Array:
	var events: Array = []
	if _state.is_empty() or _state.completed or _state.players.is_empty() or not is_finite(delta) or delta <= 0.0:
		return events
	# Substeps preserve every telegraph/attack transition under a slow render frame.
	var remaining := delta
	while remaining > 0.000001:
		var step := minf(remaining, 0.05)
		remaining -= step
		if float(_state.exposed_remaining) > 0.0:
			_state.exposed_remaining = maxf(0.0, float(_state.exposed_remaining) - step)
			if float(_state.exposed_remaining) <= 0.000001:
				_rearm_nodes()
				events.append({"type": "core_shielded"})
		_state.attack_remaining = float(_state.attack_remaining) - step
		if float(_state.attack_remaining) > 0.000001:
			continue
		match str(_state.attack_state):
			"windup":
				_state.attack_state = "active"
				_state.attack_remaining = 0.65
				events.append({"type": "attack", "attack": _state.telegraph, "overdrive": _state.overdrive})
			"active":
				_state.attack_state = "recovery"
				_state.attack_remaining = 1.5
				_state.nodes_open = true
				events.append({"type": "recovery_started", "duration": 1.5, "nodes_open": true})
			"recovery":
				_state.attack_index = (int(_state.attack_index) + 1) % ATTACKS.size()
				_state.telegraph = ATTACKS[int(_state.attack_index)]
				_state.attack_state = "windup"
				_state.attack_remaining = 1.35 if _state.overdrive else 2.0
				_state.nodes_open = false
				events.append({"type": "telegraph_started", "attack": _state.telegraph, "duration": _state.attack_remaining, "counter": _counter(str(_state.telegraph))})
	return events

func hit_part(part_id: String, damage: float, source_id: String, ability: String = "weapon") -> Dictionary:
	if not _active_player(source_id):
		return _reject("source_not_active")
	if _state.completed:
		return _reject("encounter_completed")
	if not is_finite(damage) or damage <= 0.0:
		return _reject("invalid_damage")
	var events: Array = []
	if part_id == "core":
		if float(_state.exposed_remaining) <= 0.0:
			return _reject("core_shielded")
		_state.core_health = maxf(0.0, float(_state.core_health) - damage)
		events.append({"type": "part_hit", "part_id": part_id, "source_id": source_id, "ability": ability, "health": _state.core_health})
		if float(_state.core_health) <= 0.0:
			_state.completed = true
			_state.phase = "defeated"
			_state.telegraph = ""
			events.append({"type": "boss_defeated", "boss_id": _state.boss_id})
		elif not _state.overdrive and float(_state.core_health) <= CORE_HEALTH * 0.5:
			_state.overdrive = true
			_rearm_nodes()
			_state.attack_state = "windup"
			_state.attack_remaining = 2.0
			_state.telegraph = "tractor"
			_state.attack_index = 2
			events.append({"type": "phase_changed", "phase": "overdrive", "core_health": _state.core_health})
			events.append({"type": "telegraph_started", "attack": "tractor", "duration": 2.0, "counter": "brake_or_cover"})
	elif _state.nodes.has(part_id):
		if not _state.nodes_open:
			return _reject("node_armored")
		var node: Dictionary = _state.nodes[part_id]
		if not node.powered:
			return _reject("node_already_off")
		node.health = maxf(0.0, float(node.health) - damage)
		events.append({"type": "part_hit", "part_id": part_id, "health": node.health, "source_id": source_id})
		if float(node.health) <= 0.0:
			node.powered = false
			events.append({"type": "node_disabled", "node_id": part_id, "method": "damage"})
			_check_exposure(events)
	else:
		return _reject("unknown_part")
	return {"ok": true, "code": "applied", "events": events}

func set_node_power(node_id: String, powered: bool, source_id: String) -> Dictionary:
	if not _active_player(source_id):
		return _reject("source_not_active")
	if _state.completed:
		return _reject("encounter_completed")
	if not _state.nodes.has(node_id):
		return _reject("unknown_part")
	if not _state.nodes_open:
		return _reject("node_armored")
	if bool(_state.nodes[node_id].powered) == powered:
		return _reject("unchanged")
	_state.nodes[node_id].powered = powered
	var events: Array = [{"type": "node_power_changed", "node_id": node_id, "powered": powered, "source_id": source_id}]
	if powered:
		_state.exposed_remaining = 0.0
		_state.phase = "overdrive" if _state.overdrive else "shielded"
	else:
		_check_exposure(events)
	return {"ok": true, "code": "applied", "events": events}

func down_player(player_id: String) -> Dictionary:
	if not _state.get("players", {}).has(player_id):
		return _reject("player_missing")
	if _state.completed:
		return _reject("encounter_completed")
	if _state.players[player_id].downed:
		return _reject("already_downed")
	_state.players[player_id].health = 0.0
	_state.players[player_id].downed = true
	var events: Array = [{"type": "player_downed", "player_id": player_id}]
	if _all_players_downed():
		reset_attempt("full_wipe")
		events.append({"type": "attempt_reset", "reason": "full_wipe", "attempt": _state.attempt})
	return {"ok": true, "code": "applied", "events": events}

func revive_player(reviver_id: String, target_id: String, held_seconds: float) -> Dictionary:
	if reviver_id == target_id or not _active_player(reviver_id):
		return _reject("reviver_not_active")
	if not _state.players.has(target_id) or not _state.players[target_id].downed:
		return _reject("target_not_downed")
	if not is_finite(held_seconds) or held_seconds < REVIVE_SECONDS:
		return _reject("revive_incomplete")
	var reviver: Dictionary = _state.players[reviver_id]
	var target: Dictionary = _state.players[target_id]
	if not reviver.get("position") is Vector3 or not target.get("position") is Vector3:
		return _reject("position_missing")
	if reviver.position.distance_to(target.position) > REVIVE_DISTANCE:
		return _reject("revive_out_of_range")
	target.downed = false
	target.health = float(target.get("max_health", 100.0)) * 0.4
	return {"ok": true, "code": "revived", "events": [{"type": "player_revived", "player_id": target_id, "source_id": reviver_id}]}

func _check_exposure(events: Array) -> void:
	for node in _state.nodes.values():
		if node.powered:
			return
	_state.phase = "exposed"
	_state.exposed_remaining = 6.0 if _state.overdrive else 8.0
	events.append({"type": "core_exposed", "duration": _state.exposed_remaining})

func _rearm_nodes() -> void:
	for node in _state.nodes.values():
		node.powered = true
		node.health = NODE_HEALTH
	_state.exposed_remaining = 0.0
	_state.phase = "overdrive" if _state.overdrive else "shielded"
	_state.nodes_open = false

func _active_player(player_id: String) -> bool:
	return _state.get("players", {}).has(player_id) and not _state.players[player_id].get("downed", true)

func _all_players_downed() -> bool:
	if _state.get("players", {}).is_empty():
		return false
	for player in _state.players.values():
		if not bool(player.get("downed", true)):
			return false
	return true

func _counter(attack: String) -> String:
	return {"low_sweep": "climb", "high_lance": "dive_or_cover", "tractor": "brake_or_cover"}.get(attack, "")

func _reject(code: String) -> Dictionary:
	return {"ok": false, "code": code, "events": []}
