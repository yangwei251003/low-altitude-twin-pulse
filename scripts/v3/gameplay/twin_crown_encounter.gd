class_name TwinCrownEncounter
extends RefCounted
## Pure host-owned mechanism. All snapshot numbers are integers (positions: mm).
## No Node, physics, wall clock, rewards or durable world writes. See contract.

const Rules = preload("res://scripts/v3/gameplay/twin_ability_rules.gd")
const DEFAULT_PATH := "res://data/v3/bosses/crown_parasite.json"
const SNAPSHOT_VERSION := 3
const ANCHOR_POINTS := ["target_position", "body_position", "fall_position", "fall_via_position"]
const STEP_USEC := 100000
const MAX_HP := 160000
const HALF_HP := 80000
const MODES := ["attached", "migration_warning", "awaiting_route", "moving", "bound", "fallen", "unrooted", "defeated"]
var _definition: Dictionary = {}
var _fingerprint := ""
var _state: Dictionary = {}
var _rules = Rules.new()

func load_definition(path: String = DEFAULT_PATH) -> Dictionary:
	var file = FileAccess.open(path, FileAccess.READ)
	if file == null: return _no("definition_unreadable")
	var parsed = JSON.parse_string(file.get_as_text())
	if not parsed is Dictionary: return _no("invalid_definition")
	return configure(parsed)

func configure(definition: Dictionary) -> Dictionary:
	if not _state.is_empty(): return _no("already_started")
	if definition.get("schema_version") != 2 or definition.get("id") != "parasitic_crown" or not definition.get("anchors") is Array or definition.anchors.size() != 3:
		return _no("invalid_definition")
	var seen: Dictionary = {}
	for anchor in definition.anchors:
		if not anchor is Dictionary or str(anchor.get("id", "")).is_empty() or seen.has(str(anchor.id)):
			return _no("invalid_anchor")
		for point in ANCHOR_POINTS:
			if not _valid_position(anchor.get(point)): return _no("invalid_anchor_position")
		var exit_mm: Array = _mm(anchor.fall_via_position)
		var landing_mm: Array = _mm(anchor.fall_position)
		if exit_mm[0] != landing_mm[0] or exit_mm[2] != landing_mm[2]: return _no("invalid_fall_via")
		seen[str(anchor.id)] = true
	_definition = definition.duplicate(true)
	_fingerprint = JSON.stringify(_definition, "", true, true).sha256_text()
	return _yes("configured")

func start(players: Dictionary, seed: int = 1, is_authority: bool = true) -> Dictionary:
	if not is_authority: return _no("not_authority")
	if not _state.is_empty(): return _no("already_started")
	if _definition.is_empty():
		var loaded = load_definition()
		if not loaded.ok: return loaded
	if players.is_empty() or players.size() > 2: return _no("invalid_roster")
	var roster: Dictionary = {}
	for id in players:
		var player = _make_player(str(id), players[id])
		if player.is_empty() or _anchor_ids().has(str(id)): return _no("invalid_player")
		roster[str(id)] = player
	var has_healthy_player := false
	for player in roster.values():
		if not player.downed: has_healthy_player = true
	if not has_healthy_player: return _no("invalid_roster_all_downed")
	_state = _fresh(roster, posmod(seed, 2147483646) + 1, 1, 0, 0)
	var events: Array = []
	_emit(events, "encounter_started", {"anchor_id":_state.anchor_id})
	return _yes("started", events)

func _fresh(players: Dictionary, seed: int, attempt: int, serial: int, revision: int) -> Dictionary:
	var anchors: Dictionary = {}
	for spec in _definition.anchors:
		anchors[str(spec.id)] = {"target_position_mm":_mm(spec.target_position), "body_position_mm":_mm(spec.body_position),
			"fall_position_mm":_mm(spec.fall_position), "fall_via_position_mm":_mm(spec.fall_via_position), "temperature":20, "growth_percent":65,
			"light_until":0, "trap_until":0, "root_ready_tick":0, "scorch_until":0, "burning":false}
	var first: String = str(_definition.anchors[0].id)
	var body: Array = anchors[first].body_position_mm.duplicate()
	return {"tick":0, "pending_usec":0, "attempt":attempt, "serial":serial, "revision":revision,
		"rng":seed, "core_hp_milli":MAX_HP, "phase":1, "mode":"attached", "completed":false,
		"anchor_id":first, "position_mm":body, "mode_until":120, "attack_due":30, "attack_index":0,
		"anchors":anchors, "players":players.duplicate(true), "movement":{}, "attack":{}, "hazards":[]}

func get_state() -> Dictionary:
	var result = _state.duplicate(true)
	if result.is_empty(): return result
	result.boss_position = _metres(result.position_mm)
	result.core_health = float(result.core_hp_milli) / 1000.0
	result.core_open = _core_open()
	for id in result.players:
		result.players[id].position = _metres(result.players[id].position_mm)
		result.players[id].health = float(result.players[id].health_milli) / 1000.0
		result.players[id].max_health = float(result.players[id].max_health_milli) / 1000.0
	return result

func definitions() -> Dictionary:
	return _definition.duplicate(true)

func snapshot() -> Dictionary:
	return {"schema_version":SNAPSHOT_VERSION, "definition_id":"parasitic_crown", "definition_fingerprint":_fingerprint, "state":_state.duplicate(true)}

func restore(saved: Dictionary) -> Dictionary:
	if _definition.is_empty():
		var loaded = load_definition()
		if not loaded.ok: return loaded
	var checked = validate_snapshot(saved)
	if not checked.ok: return checked
	_state = _integer_tree(saved.state)
	return _yes("restored")

func validate_snapshot(saved: Dictionary) -> Dictionary:
	if saved.get("schema_version") != SNAPSHOT_VERSION or saved.get("definition_id") != "parasitic_crown" or saved.get("definition_fingerprint") != _fingerprint:
		return _no("snapshot_definition_mismatch")
	if not saved.get("state") is Dictionary or not _json_tree_valid(saved.state): return _no("invalid_snapshot")
	var s: Dictionary = _integer_tree(saved.state)
	for key in ["tick", "pending_usec", "attempt", "serial", "revision", "rng", "core_hp_milli", "phase", "mode_until", "attack_due", "attack_index"]:
		if not _nonnegative_integer(s.get(key)): return _no("invalid_counter")
	if int(s.pending_usec) >= STEP_USEC or int(s.attempt) < 1 or int(s.phase) not in [1, 2] or int(s.core_hp_milli) > MAX_HP:
		return _no("invalid_counter")
	if int(s.rng) < 1 or int(s.rng) >= 2147483647 or int(s.tick) > 2147483647: return _no("invalid_counter")
	if not s.get("mode") in MODES or not s.get("completed") is bool or not _valid_mm(s.get("position_mm")):
		return _no("invalid_boss")
	if s.completed != (s.mode == "defeated") or s.completed != (int(s.core_hp_milli) == 0): return _no("invalid_completion")
	if (int(s.phase) == 1 and int(s.core_hp_milli) <= HALF_HP) or (int(s.phase) == 2 and int(s.core_hp_milli) > HALF_HP): return _no("invalid_phase")
	if not s.get("anchors") is Dictionary or s.anchors.size() != 3 or not s.anchors.has(str(s.get("anchor_id", ""))): return _no("invalid_anchors")
	for spec in _definition.anchors:
		if not s.anchors.has(str(spec.id)) or not s.anchors[str(spec.id)] is Dictionary: return _no("invalid_anchors")
		var a: Dictionary = s.anchors[str(spec.id)]
		for point in ANCHOR_POINTS:
			if a.get(point + "_mm") != _mm(spec[point]): return _no("invalid_anchor_position")
		for key in ["growth_percent", "light_until", "trap_until", "root_ready_tick", "scorch_until"]:
			if not _nonnegative_integer(a.get(key)): return _no("invalid_anchor_state")
		if not a.get("temperature") is float and not a.get("temperature") is int: return _no("invalid_anchor_state")
		if int(a.temperature) < -40 or int(a.temperature) > 200 or int(a.growth_percent) > 100 or not a.get("burning") is bool: return _no("invalid_anchor_state")
	if not s.get("players") is Dictionary or s.players.size() > 2: return _no("invalid_roster")
	var has_healthy_player := false
	for id in s.players:
		var p = s.players[id]
		if s.anchors.has(id) or not p is Dictionary or not _valid_player_identity(str(id), p.get("owner")): return _no("invalid_player")
		for key in ["health_milli", "max_health_milli", "last_shot_sequence", "next_shot_usec"]:
			if not _nonnegative_integer(p.get(key)): return _no("invalid_player")
		if int(p.max_health_milli) <= 0 or int(p.max_health_milli) > 1000000 or int(p.health_milli) > int(p.max_health_milli): return _no("invalid_player")
		if not p.get("downed") is bool or p.downed != (int(p.health_milli) == 0) or str(p.get("owner", "")).is_empty(): return _no("invalid_player")
		if not _valid_mm(p.get("position_mm")) or not _valid_mm(p.get("entry_mm")): return _no("invalid_player")
		if int(p.next_shot_usec) > int(s.tick) * STEP_USEC + int(s.pending_usec) + 230000: return _no("invalid_player_cooldown")
		if not p.downed: has_healthy_player = true
	if not s.players.is_empty() and not s.completed and not has_healthy_player: return _no("unresolved_fullwipe")
	if not s.get("movement") is Dictionary or not s.get("attack") is Dictionary or not s.get("hazards") is Array or s.hazards.size() > 3:
		return _no("invalid_transients")
	var movement: Dictionary = s.movement
	if not movement.is_empty():
		if not movement.get("token") is String or not movement.get("approved") is bool or not movement.get("points_mm") is Array or movement.points_mm.size() != 4: return _no("invalid_movement")
		for point in movement.points_mm:
			if not _valid_mm(point): return _no("invalid_movement")
		if not movement.get("arrival") in ["attached", "fallen"] or not s.anchors.has(str(movement.get("target_id", ""))) or not _nonnegative_integer(movement.get("start_tick")): return _no("invalid_movement")
	if (s.mode in ["migration_warning", "awaiting_route", "moving"]) != (not movement.is_empty()): return _no("invalid_movement_mode")
	if s.mode == "moving" and not movement.approved: return _no("unapproved_movement")
	if not s.attack.is_empty() and not _valid_attack(s.attack, s.players): return _no("invalid_attack")
	var tokens: Dictionary = {}
	for hazard in s.hazards:
		if not hazard is Dictionary or not _valid_attack(hazard, s.players) or tokens.has(hazard.token): return _no("invalid_hazard")
		tokens[hazard.token] = true
	if s.completed and (not movement.is_empty() or not s.attack.is_empty() or not s.hazards.is_empty()): return _no("invalid_completion")
	return _yes("valid_snapshot")

func advance(delta: float, is_authority: bool = true) -> Dictionary:
	if not is_authority: return _no("not_authority")
	if _state.is_empty(): return _no("not_started")
	if not is_finite(delta) or delta < 0.0 or delta > 5.0: return _no("invalid_delta")
	if delta == 0.0 or _state.completed or _state.players.is_empty(): return _yes("unchanged")
	var usec: int = int(round(delta * 1000000.0))
	if usec == 0: return _yes("unchanged")
	_state.pending_usec += usec
	var events: Array = []
	while int(_state.pending_usec) >= STEP_USEC:
		_state.pending_usec -= STEP_USEC
		_state.tick += 1
		_step(events)
	_state.revision += 1
	return _yes("advanced", events)

func _step(events: Array) -> void:
	var now: int = int(_state.tick)
	for id in _state.anchors:
		var a: Dictionary = _state.anchors[id]
		if int(a.trap_until) > 0 and now >= int(a.trap_until):
			a.trap_until = 0
			a.growth_percent = 65
			_emit(events, "root_trap_expired", {"anchor_id":id})
		if int(a.scorch_until) > 0 and now >= int(a.scorch_until):
			a.scorch_until = 0
			a.temperature = 20
			a.burning = false
			_emit(events, "host_recovered", {"anchor_id":id})
	_update_attacks(events)
	match str(_state.mode):
		"attached":
			# A normal cycle cannot swallow an already visible warning or its hit.
			# Player-induced binding, heat and phase transitions still interrupt.
			if now >= int(_state.mode_until) and _state.attack.is_empty(): _plan_migration(events, "cycle")
			elif now >= int(_state.attack_due) and _state.attack.is_empty(): _telegraph_normal(events)
		"migration_warning", "awaiting_route":
			if now >= int(_state.mode_until):
				if _state.movement.approved:
					_state.mode = "moving"
					_state.movement.start_tick = now
					_emit(events, "movement_started", {"movement":_state.movement.duplicate(true)})
				else: _state.mode = "awaiting_route"
		"moving":
			var fraction: float = clampf(float(now - int(_state.movement.start_tick)) / 20.0, 0.0, 1.0)
			var points: Array = _state.movement.points_mm
			var progress: float = fraction * float(points.size() - 1)
			var segment: int = mini(points.size() - 2, int(floor(progress)))
			var local: float = progress - float(segment)
			_state.position_mm = _interpolate_mm(points[segment], points[segment + 1], local)
			if fraction >= 1.0: _arrive(events)
		"bound", "fallen":
			if now >= int(_state.mode_until): _plan_migration(events, "window_closed")
		"unrooted":
			if now >= int(_state.mode_until) and _state.attack.is_empty(): _plan_migration(events, "host_search")
			elif now >= int(_state.attack_due) and _state.attack.is_empty(): _telegraph_normal(events)

func ability_options() -> Dictionary:
	return {"light":Rules.DEFINITIONS.light.duplicate(true), "heat":Rules.DEFINITIONS.heat.duplicate(true), "growth":Rules.DEFINITIONS.growth.duplicate(true)}

func resolve_ability(intent: Dictionary, actors: Dictionary, context: Dictionary) -> Dictionary:
	if context.get("is_authority", false) != true: return _no("not_authority")
	if _state.is_empty() or _state.completed: return _no("not_active")
	var actor_id: String = str(intent.get("actor_id", ""))
	var target_id: String = str(intent.get("target_id", ""))
	var ability: String = str(intent.get("ability", ""))
	if ability not in ["light", "heat", "growth"]: return _no("unsupported_ability")
	if not _state.players.has(actor_id) or not actors.get(actor_id) is Dictionary: return _no("actor_missing")
	if _state.players[actor_id].downed: return _no("actor_downed")
	if not _state.anchors.has(target_id): return _no("unsupported_target")
	var actor: Dictionary = actors[actor_id]
	if str(actor.get("owner", "")) != str(_state.players[actor_id].owner): return _no("not_owner")
	if not actor.get("position") is Vector3 or actor.position.distance_to(_vector(_state.players[actor_id].position_mm)) > 0.002: return _no("stale_position")
	var a: Dictionary = _state.anchors[target_id]
	if ability == "growth" and int(a.root_ready_tick) > int(_state.tick): return _no("roots_recovering")
	var entities: Dictionary = {actor_id:actor.duplicate(true), target_id:_anchor_entity(target_id)}
	var rule_result: Dictionary = _rules.resolve(intent, entities, context)
	if not rule_result.ok: return rule_result
	var clone = get_script().new()
	clone._definition = _definition.duplicate(true)
	clone._fingerprint = _fingerprint
	clone._state = _state.duplicate(true)
	var events: Array = []
	for patch in rule_result.patches:
		if patch.entity_id == target_id: clone._apply_host_ability(target_id, ability, patch.changes, events)
	clone._state.revision += 1
	clone._emit(events, "ability_applied", {"ability":ability, "actor_id":actor_id, "target_id":target_id})
	return {"ok":true, "code":"resolved", "expected_revision":int(_state.revision), "intent":intent.duplicate(true),
		"context":context.duplicate(true), "actor_revision":int(actor.get("revision", 0)), "candidate":clone.snapshot(),
		"rule_result":rule_result, "events":events, "cost":float(Rules.DEFINITIONS[ability].energy)}

func commit_ability(transaction: Dictionary, actors: Dictionary, physics_approved: bool = false, is_authority: bool = true) -> Dictionary:
	if not is_authority: return _no("not_authority")
	if not physics_approved: return _no("physics_not_approved")
	if _state.is_empty() or not transaction.get("ok", false) or int(transaction.get("expected_revision", -1)) != int(_state.revision): return _no("stale_transaction")
	if not transaction.get("intent") is Dictionary or not transaction.get("context") is Dictionary: return _no("invalid_transaction")
	var actor_id: String = str(transaction.intent.get("actor_id", ""))
	if not actors.get(actor_id) is Dictionary or int(actors[actor_id].get("revision", 0)) != int(transaction.get("actor_revision", -1)): return _no("stale_actor")
	# Recompute host-owned intent: caller-mutated candidate/events cannot change the state.
	var resolved = resolve_ability(transaction.intent, actors, transaction.context)
	if not resolved.ok: return resolved
	var target_id: String = str(transaction.intent.target_id)
	var entities: Dictionary = {actor_id:actors[actor_id], target_id:_anchor_entity(target_id)}
	var committed = _rules.commit(resolved.rule_result, entities, true)
	if not committed.ok: return committed
	_state = resolved.candidate.state.duplicate(true)
	return _yes("committed", resolved.events)

func _anchor_entity(id: String) -> Dictionary:
	var a: Dictionary = _state.anchors[id]
	return {"id":id, "position":_vector(a.target_position_mm), "revision":int(_state.revision),
		"tags":["photosensitive", "thermal", "combustible", "plant", "growable", "organic"],
		"temperature":float(a.temperature), "burning":a.burning, "growth":float(a.growth_percent) / 100.0,
		"light_level":1.0 if int(a.light_until) > int(_state.tick) else 0.0}

func _apply_host_ability(id: String, ability: String, changes: Dictionary, events: Array) -> void:
	var a: Dictionary = _state.anchors[id]
	var now: int = int(_state.tick)
	if ability == "light":
		a.light_until = now + 60 if float(changes.light_level) > 0.0 else 0
	elif ability == "growth":
		a.growth_percent = int(round(float(changes.growth) * 100.0))
		if int(a.growth_percent) >= 100:
			a.trap_until = now + 100
			_emit(events, "root_trap_armed", {"anchor_id":id, "expires_tick":a.trap_until})
			if str(_state.anchor_id) == id and _state.mode == "attached": _bind(id, events)
	elif ability == "heat":
		var was_burning: bool = a.burning
		a.temperature = int(round(float(changes.temperature)))
		a.burning = bool(changes.burning)
		if a.burning and not was_burning:
			a.scorch_until = now + 200
			a.trap_until = 0
			a.growth_percent = 65
			_emit(events, "host_scorched", {"anchor_id":id, "until_tick":a.scorch_until})
			_telegraph_burn(id, events)
			if str(_state.anchor_id) == id and _state.mode in ["attached", "bound"]:
				_request_movement(id, "fallen", "heat_ejection", events)
		elif not a.burning and was_burning:
			a.scorch_until = 0
			_emit(events, "host_cooled", {"anchor_id":id})

func _bind(id: String, events: Array) -> void:
	_cancel_attack(events)
	var a: Dictionary = _state.anchors[id]
	a.trap_until = 0
	a.growth_percent = 65
	a.root_ready_tick = int(_state.tick) + 120
	_state.mode = "bound"
	_state.mode_until = int(_state.tick) + 60
	_emit(events, "core_opened", {"reason":"root_bound", "duration_ticks":60, "anchor_id":id})

func _plan_migration(events: Array, reason: String) -> void:
	var candidates: Array = []
	for id in _anchor_ids():
		if id != str(_state.anchor_id) and not _state.anchors[id].burning: candidates.append(id)
	if candidates.is_empty() and not _state.anchors[str(_state.anchor_id)].burning: candidates.append(str(_state.anchor_id))
	if candidates.is_empty():
		var already_unrooted: bool = _state.mode == "unrooted"
		if not already_unrooted: _cancel_attack(events)
		_state.mode = "unrooted"
		_state.movement = {}
		_state.mode_until = int(_state.tick) + 30
		if not already_unrooted:
			_state.attack_due = int(_state.tick) + 10
			_emit(events, "core_opened", {"reason":"no_healthy_host", "duration_ticks":30})
		return
	_state.rng = (int(_state.rng) * 48271) % 2147483647
	var chosen: String = str(candidates[int(_state.rng) % candidates.size()])
	for id in candidates:
		if int(_state.anchors[id].light_until) > maxi(int(_state.tick), int(_state.anchors[chosen].light_until)): chosen = str(id)
	_request_movement(chosen, "attached", reason, events)

func _request_movement(target: String, arrival: String, reason: String, events: Array) -> void:
	_cancel_attack(events)
	var destination: Array = _state.anchors[target]["fall_position_mm" if arrival == "fallen" else "body_position_mm"].duplicate()
	var source: Array = _state.position_mm.duplicate()
	# Rise vertically out of the authored roots before traversing; the previous
	# diagonal lift cut the claws through the real rock rims in every migration.
	var clearance_y: int = maxi(int(source[1]), int(destination[1])) + 3000
	if arrival == "fallen":
		clearance_y = maxi(int(source[1]) + 2000, int(_state.anchors[target].fall_via_position_mm[1]))
	var points: Array = build_route(source, destination, clearance_y)
	var token: String = "move:%d:%d" % [int(_state.attempt), int(_state.serial) + 1]
	_state.movement = {"token":token, "approved":false, "points_mm":points,
		"target_id":target, "arrival":arrival, "reason":reason, "start_tick":0}
	_state.mode = "migration_warning"
	_state.mode_until = int(_state.tick) + (10 if arrival == "fallen" else 20)
	_emit(events, "movement_requested", {"movement":_state.movement.duplicate(true), "warning_until":_state.mode_until})

static func build_route(source: Array, destination: Array, clearance_y: int) -> Array:
	return [source.duplicate(), [source[0], clearance_y, source[2]],
		[destination[0], clearance_y, destination[2]], destination.duplicate()]

func approve_migration(token: String, approved: bool, is_authority: bool = true) -> Dictionary:
	if not is_authority: return _no("not_authority")
	if _state.is_empty() or not _state.mode in ["migration_warning", "awaiting_route"] or str(_state.movement.get("token", "")) != token: return _no("stale_movement")
	var events: Array = []
	if approved:
		_state.movement.approved = true
		_emit(events, "movement_approved", {"token":token})
	else:
		_state.movement = {}
		_state.mode = "unrooted"
		_state.mode_until = int(_state.tick) + 30
		_state.attack_due = int(_state.tick) + 10
		_emit(events, "movement_blocked", {"token":token, "position_mm":_state.position_mm.duplicate()})
	_state.revision += 1
	return _yes("approved" if approved else "blocked", events)

func interrupt_movement(token: String, is_authority: bool = true) -> Dictionary:
	# The host rolls back an uncommitted candidate step before calling this at the
	# last swept-safe pose. No candidate events may have reached observers.
	if not is_authority: return _no("not_authority")
	if token.is_empty() or _state.is_empty() or not _state.mode in ["moving", "migration_warning", "awaiting_route"] or str(_state.movement.get("token", "")) != token:
		return _no("stale_movement")
	var events: Array = []
	_cancel_attack(events)
	_state.movement = {}
	_state.mode = "unrooted"
	_state.mode_until = int(_state.tick) + 30
	_state.attack_due = int(_state.tick) + 10
	_emit(events, "movement_blocked", {"token":token, "position_mm":_state.position_mm.duplicate(), "reason":"dynamic_obstacle"})
	_state.revision += 1
	return _yes("movement_interrupted", events)

func _arrive(events: Array) -> void:
	var movement: Dictionary = _state.movement
	_state.anchor_id = str(movement.target_id)
	_state.mode = str(movement.arrival)
	_state.movement = {}
	_state.mode_until = int(_state.tick) + (40 if _state.mode == "fallen" else (120 if int(_state.phase) == 1 else 90))
	_state.attack_due = int(_state.tick) + 30
	_emit(events, "movement_arrived", {"anchor_id":_state.anchor_id, "mode":_state.mode, "position_mm":_state.position_mm.duplicate()})
	var a: Dictionary = _state.anchors[str(_state.anchor_id)]
	if _state.mode == "fallen": _emit(events, "core_opened", {"reason":"heat_ejection", "duration_ticks":40})
	elif a.burning: _plan_migration(events, "host_burning_on_arrival")
	elif int(a.trap_until) > int(_state.tick): _bind(str(_state.anchor_id), events)

func hit_core(player_id: String, damage: float, attack_sequence: int, context: Dictionary) -> Dictionary:
	var check = _combat_check(player_id, context)
	if not check.ok: return check
	if str(context.get("sender_id", "")) != str(_state.players[player_id].owner): return _no("not_owner")
	if not _core_open(): return _no("core_closed")
	if not is_finite(damage) or damage <= 0.0 or damage > 50.0: return _no("invalid_damage")
	var p: Dictionary = _state.players[player_id]
	if attack_sequence < 1 or attack_sequence > 9007199254740991: return _no("invalid_attack_sequence")
	if attack_sequence <= int(p.last_shot_sequence): return _no("replayed_attack")
	if _now_usec() < int(p.next_shot_usec): return _no("shot_cooldown")
	if _vector(p.position_mm).distance_to(_vector(_state.position_mm)) > 36.0: return _no("out_of_range")
	var amount: int = int(round(damage * 1000.0))
	if amount < 1: return _no("invalid_damage")
	p.last_shot_sequence = attack_sequence
	p.next_shot_usec = _now_usec() + 230000
	var before_hp: int = int(_state.core_hp_milli)
	_state.core_hp_milli = maxi(0, before_hp - amount)
	var half_gate: bool = int(_state.phase) == 1 and int(_state.core_hp_milli) <= HALF_HP
	if half_gate: _state.core_hp_milli = HALF_HP
	var events: Array = []
	_emit(events, "core_hit", {"player_id":player_id, "attack_sequence":attack_sequence, "damage_milli":before_hp - int(_state.core_hp_milli), "requested_damage_milli":amount})
	if half_gate:
		_state.phase = 2
		_emit(events, "phase_changed", {"phase":2, "core_hp_milli":HALF_HP})
		_plan_migration(events, "half_health")
	elif int(_state.core_hp_milli) == 0:
		_cancel_attack(events)
		_state.completed = true
		_state.mode = "defeated"
		_state.movement = {}
		_state.hazards = []
		_emit(events, "boss_defeated", {"boss_id":"parasitic_crown"})
	_state.revision += 1
	return _yes("hit", events)

func _telegraph_normal(events: Array) -> void:
	var shapes: Array = []
	var centre: Array = _state.anchors[str(_state.anchor_id)].body_position_mm
	var low: Dictionary = {"kind":"annular_prism", "centre_xz_mm":[centre[0], centre[2]], "inner_mm":3000, "outer_mm":14000, "y_min_mm":0, "y_max_mm":10000}
	var alive: Array = []
	for id in _state.players:
		if not _state.players[id].downed: alive.append(id)
	alive.sort()
	if alive.is_empty(): return
	# Phase one alternates low/pollen. Count pollen turns independently of that
	# parity, otherwise the second player is targeted by every pollen column.
	var target_turn: int = int(_state.attack_index) if int(_state.phase) == 2 else (int(_state.attack_index) >> 1)
	var locked: Array = _state.players[alive[target_turn % alive.size()]].position_mm
	var locked_y: int = clampi(int(locked[1]), 0, 27000)
	var high: Dictionary = {"kind":"cylinder", "centre_xz_mm":[locked[0], locked[2]], "inner_mm":0, "outer_mm":3500,
		"y_min_mm":maxi(0, locked_y - 4000), "y_max_mm":mini(28000, locked_y + 4000)}
	if int(_state.phase) == 2: shapes = [low, high]
	else: shapes = [low] if int(_state.attack_index) % 2 == 0 else [high]
	_state.attack_index += 1
	_state.attack = _new_attack(shapes, 24 if int(_state.phase) == 2 else 20, 12, 24000, "root_pollen")
	_state.attack_due = int(_state.tick) + 70
	_emit(events, "attack_telegraphed", {"attack":_state.attack.duplicate(true)})

func _telegraph_burn(id: String, events: Array) -> void:
	# At most one hazard per host; cooling/reheating replaces that host's prior warning explicitly.
	for index in range(_state.hazards.size() - 1, -1, -1):
		if _state.hazards[index].get("anchor_id") == id:
			_emit(events, "attack_cancelled", {"token":_state.hazards[index].token})
			_state.hazards.remove_at(index)
	var a: Dictionary = _state.anchors[id]
	var shape: Dictionary = {"kind":"cylinder", "centre_xz_mm":[a.body_position_mm[0], a.body_position_mm[2]], "inner_mm":0, "outer_mm":5000, "y_min_mm":0, "y_max_mm":13000}
	var hazard = _new_attack([shape], 15, 40, 20000, "burning_spores")
	# An explicit String key also validates in an in-memory snapshot rollback.
	hazard["anchor_id"] = id
	_state.hazards.append(hazard)
	_emit(events, "attack_telegraphed", {"attack":hazard.duplicate(true)})

func _new_attack(shapes: Array, warning_ticks: int, active_ticks: int, damage: int, kind: String) -> Dictionary:
	return {"token":"attack:%d:%d" % [int(_state.attempt), int(_state.serial) + 1], "kind":kind,
		"fire_tick":int(_state.tick) + warning_ticks, "end_tick":int(_state.tick) + warning_ticks + active_ticks,
		"fired":false, "shapes":shapes, "damage_milli":damage, "hit_players":[]}

func _update_attacks(events: Array) -> void:
	if not _state.attack.is_empty():
		_advance_attack(_state.attack, events)
		if int(_state.tick) >= int(_state.attack.end_tick): _state.attack = {}
	for i in range(_state.hazards.size() - 1, -1, -1):
		_advance_attack(_state.hazards[i], events)
		if int(_state.tick) >= int(_state.hazards[i].end_tick): _state.hazards.remove_at(i)

func _advance_attack(attack: Dictionary, events: Array) -> void:
	if not attack.fired and int(_state.tick) >= int(attack.fire_tick):
		attack.fired = true
		_emit(events, "attack_active", {"attack":attack.duplicate(true)})
	if int(_state.tick) >= int(attack.end_tick): _emit(events, "attack_expired", {"token":attack.token})

func _cancel_attack(events: Array) -> void:
	if not _state.attack.is_empty():
		_emit(events, "attack_cancelled", {"token":_state.attack.token})
		_state.attack = {}

func apply_attack_hit(token: String, player_id: String, context: Dictionary) -> Dictionary:
	var checked = _combat_check(player_id, context)
	if not checked.ok: return checked
	var attack: Dictionary = {}
	if _state.attack.get("token") == token: attack = _state.attack
	for hazard in _state.hazards:
		if hazard.token == token: attack = hazard
	if attack.is_empty() or not attack.fired or int(_state.tick) >= int(attack.end_tick): return _no("attack_inactive")
	if player_id in attack.hit_players: return _no("attack_already_hit")
	var inside := false
	for shape in attack.shapes:
		if contains_shape(shape, _vector(_state.players[player_id].position_mm)): inside = true
	if not inside: return _no("outside_attack")
	# The authoritative adapter previews the real airframe's armor/shield model.
	# Network clients never supply this context. A missing preview retains raw rule tests.
	var resolved_damage = context.get("resolved_damage_milli", attack.damage_milli)
	if not _bounded_integer(resolved_damage, 0, int(attack.damage_milli)): return _no("invalid_resolved_damage")
	attack.hit_players.append(player_id)
	var p: Dictionary = _state.players[player_id]
	p.health_milli = maxi(0, int(p.health_milli) - int(resolved_damage))
	p.downed = int(p.health_milli) == 0
	var events: Array = []
	_emit(events, "player_hit", {"player_id":player_id, "token":token, "damage_milli":int(resolved_damage), "raw_damage_milli":attack.damage_milli,
		"health_milli":p.health_milli, "max_health_milli":p.max_health_milli, "downed":p.downed})
	if p.downed: _emit(events, "player_downed", {"player_id":player_id})
	if _all_downed(): _reset_attempt(events)
	_state.revision += 1
	return _yes("hit", events)

static func contains_shape(shape: Dictionary, position: Vector3) -> bool:
	if not _valid_position(position) or not _valid_shape(shape): return false
	# Use the same millimetre grid as authoritative player state. A float32
	# metre round-trip must not turn the excluded upper edge into a hit.
	var point: Array = _mm(position)
	var dx: int = int(point[0]) - int(shape.centre_xz_mm[0])
	var dz: int = int(point[2]) - int(shape.centre_xz_mm[1])
	var radius_squared: int = dx * dx + dz * dz
	var inner: int = int(shape.inner_mm)
	var outer: int = int(shape.outer_mm)
	return int(point[1]) >= int(shape.y_min_mm) and int(point[1]) < int(shape.y_max_mm) and radius_squared >= inner * inner and radius_squared <= outer * outer

func set_player_position(id: String, position: Vector3, is_authority: bool = true) -> Dictionary:
	if not is_authority: return _no("not_authority")
	if _state.is_empty() or not _state.players.has(id) or not _valid_position(position): return _no("invalid_player_position")
	if _state.players[id].position_mm == _mm(position): return _yes("unchanged")
	_state.players[id].position_mm = _mm(position)
	_state.revision += 1
	return _yes("position_updated")

func sync_player_state(id: String, spec: Dictionary, is_authority: bool = true) -> Dictionary:
	# Host samples the real body before resolving actions; identity, entry and shot receipts stay immutable.
	if not is_authority: return _no("not_authority")
	if _state.is_empty() or _state.completed or not _state.players.has(id): return _no("not_active")
	var physical: Dictionary = _physical_player_state(spec)
	if physical.is_empty(): return _no("invalid_player_state")
	var player: Dictionary = _state.players[id]
	var changed := false
	for key in physical:
		if player[key] != physical[key]: changed = true
	if not changed: return _yes("unchanged")
	var was_downed: bool = player.downed
	player.merge(physical, true)
	var events: Array = []
	if not was_downed and player.downed:
		_emit(events, "player_downed", {"player_id":id, "reason":"host_body_state"})
	if _all_downed(): _reset_attempt(events)
	_state.revision += 1
	return _yes("player_synced", events)

func add_player(id: String, spec: Dictionary, is_authority: bool = true) -> Dictionary:
	if not is_authority: return _no("not_authority")
	if _state.is_empty() or _state.completed: return _no("not_active")
	if _state.players.has(id): return _no("player_exists")
	if _state.players.size() >= 2 or _state.anchors.has(id): return _no("invalid_roster")
	var player = _make_player(id, spec)
	if player.is_empty(): return _no("invalid_player")
	# A downed late join may join a living team, but cannot create an unresolved all-downed roster.
	if player.downed and (_state.players.is_empty() or _all_downed()): return _no("invalid_roster_all_downed")
	_state.players[id] = player
	_state.revision += 1
	var events: Array = []
	_emit(events, "player_joined", {"player_id":id, "entry_mm":player.entry_mm.duplicate()})
	return _yes("joined", events)

func remove_player(id: String, is_authority: bool = true) -> Dictionary:
	if not is_authority: return _no("not_authority")
	if _state.is_empty() or not _state.players.has(id): return _no("player_missing")
	_state.players.erase(id)
	# Preserve hit receipts while a player is present; removal drops references before snapshot.
	if not _state.attack.is_empty(): _state.attack.hit_players.erase(id)
	for hazard in _state.hazards: hazard.hit_players.erase(id)
	var events: Array = []
	_emit(events, "player_left", {"player_id":id})
	if not _state.completed and _all_downed(): _reset_attempt(events)
	_state.revision += 1
	return _yes("left", events)

func down_player(id: String, is_authority: bool = true) -> Dictionary:
	if not is_authority: return _no("not_authority")
	if _state.is_empty() or _state.completed or not _state.players.has(id): return _no("not_active")
	if _state.players[id].downed: return _no("already_downed")
	_state.players[id].health_milli = 0
	_state.players[id].downed = true
	var events: Array = []
	_emit(events, "player_downed", {"player_id":id})
	if _all_downed(): _reset_attempt(events)
	_state.revision += 1
	return _yes("downed", events)

func revive_player(helper: String, target: String, held_seconds: float, context: Dictionary) -> Dictionary:
	if context.get("is_authority", false) != true: return _no("not_authority")
	if _state.is_empty() or _state.completed or helper == target or not _state.players.has(helper) or not _state.players.has(target): return _no("invalid_revive")
	var h: Dictionary = _state.players[helper]
	var p: Dictionary = _state.players[target]
	if str(context.get("sender_id", "")) != str(h.owner): return _no("not_owner")
	if h.downed or not p.downed or not is_finite(held_seconds) or held_seconds < 2.5: return _no("invalid_revive")
	if context.get("line_of_sight", false) != true or _vector(h.position_mm).distance_to(_vector(p.position_mm)) > 3.0: return _no("revive_blocked")
	p.health_milli = maxi(1, int(round(float(p.max_health_milli) * 0.4)))
	p.downed = false
	_state.revision += 1
	var events: Array = []
	_emit(events, "player_revived", {"player_id":target, "helper_id":helper,
		"health_milli":p.health_milli, "max_health_milli":p.max_health_milli, "downed":false})
	return _yes("revived", events)

func reset(is_authority: bool = true) -> Dictionary:
	if not is_authority: return _no("not_authority")
	if _state.is_empty() or _state.completed or _state.players.is_empty(): return _no("not_active")
	var events: Array = []
	_reset_attempt(events)
	_state.revision += 1
	return _yes("reset", events)

func _reset_attempt(events: Array) -> void:
	var players: Dictionary = _state.players.duplicate(true)
	for id in players:
		players[id].health_milli = players[id].max_health_milli
		players[id].downed = false
		players[id].position_mm = players[id].entry_mm.duplicate()
		players[id].next_shot_usec = 0
	var seed: int = int(_state.rng)
	_state = _fresh(players, seed, int(_state.attempt) + 1, int(_state.serial), int(_state.revision))
	_emit(events, "encounter_reset", {"reason":"whole_attempt", "attempt":_state.attempt})

func _combat_check(id: String, context: Dictionary) -> Dictionary:
	if context.get("is_authority", false) != true: return _no("not_authority")
	if _state.is_empty() or _state.completed or not _state.players.has(id): return _no("not_active")
	if _state.players[id].downed: return _no("actor_downed")
	if context.get("hit_confirmed", false) != true or context.get("line_of_sight", false) != true: return _no("physical_hit_required")
	return _yes("valid")

func _core_open() -> bool:
	return not _state.is_empty() and not _state.completed and _state.mode in ["bound", "fallen", "unrooted"]

func _all_downed() -> bool:
	if _state.players.is_empty(): return false
	for p in _state.players.values():
		if not p.downed: return false
	return true

func _make_player(id: String, spec) -> Dictionary:
	if not spec is Dictionary or not _valid_player_identity(id, spec.get("owner")): return {}
	var result: Dictionary = _physical_player_state(spec)
	if result.is_empty(): return {}
	var entry: Array = result.position_mm.duplicate()
	if spec.has("entry_position"):
		if not _valid_position(spec.entry_position): return {}
		entry = _mm(spec.entry_position)
	result.merge({"owner":spec.owner, "entry_mm":entry, "last_shot_sequence":0, "next_shot_usec":0})
	return result

static func _valid_player_identity(id: String, owner) -> bool:
	if not owner is String or not owner.is_valid_int() or owner.length() > 10: return false
	var peer: int = int(owner)
	return peer > 0 and peer <= 2147483647 and str(peer) == owner and id == "player:" + owner

static func _physical_player_state(spec: Dictionary) -> Dictionary:
	if not _valid_position(spec.get("position")) or not spec.get("downed") is bool: return {}
	for key in ["health", "max_health"]:
		if (not spec.get(key) is int and not spec.get(key) is float) or not is_finite(float(spec[key])): return {}
	var health: float = float(spec.health)
	var maximum: float = float(spec.max_health)
	if maximum < 0.001 or maximum > 1000.0 or health < 0.0 or health > maximum: return {}
	var health_milli: int = int(round(health * 1000.0))
	if spec.downed != (health_milli == 0): return {}
	return {"position_mm":_mm(spec.position), "health_milli":health_milli,
		"max_health_milli":int(round(maximum * 1000.0)), "downed":spec.downed}

func _anchor_ids() -> Array:
	var ids: Array = []
	for a in _definition.get("anchors", []): ids.append(str(a.id))
	return ids

func _now_usec() -> int:
	return int(_state.tick) * STEP_USEC + int(_state.pending_usec)

func _emit(events: Array, kind: String, details: Dictionary = {}) -> void:
	_state.serial += 1
	var event: Dictionary = {"event_id":"crown:%d:%d" % [int(_state.attempt), int(_state.serial)], "serial":int(_state.serial),
		"attempt":int(_state.attempt), "tick":int(_state.tick), "kind":kind, "type":kind, "boss_id":"parasitic_crown"}
	event.merge(details.duplicate(true), true)
	events.append(event)

static func _valid_shape(shape) -> bool:
	if not shape is Dictionary or not shape.get("kind") in ["annular_prism", "cylinder"]: return false
	if not shape.get("centre_xz_mm") is Array or shape.centre_xz_mm.size() != 2: return false
	for n in shape.centre_xz_mm:
		if not _bounded_integer(n, -1000000, 1000000): return false
	for key in ["inner_mm", "outer_mm", "y_min_mm", "y_max_mm"]:
		if not _bounded_integer(shape.get(key), 0, 1000000): return false
	return int(shape.inner_mm) < int(shape.outer_mm) and int(shape.y_min_mm) < int(shape.y_max_mm)

static func _valid_attack(a: Dictionary, players: Dictionary) -> bool:
	if not a.get("token") is String or str(a.token).is_empty() or not a.get("kind") is String or not a.get("fired") is bool: return false
	for key in ["fire_tick", "end_tick", "damage_milli"]:
		if not _nonnegative_integer(a.get(key)): return false
	if int(a.end_tick) <= int(a.fire_tick) or int(a.damage_milli) > 50000: return false
	if not a.get("shapes") is Array or a.shapes.is_empty() or a.shapes.size() > 2 or not a.get("hit_players") is Array or a.hit_players.size() > 2: return false
	for shape in a.shapes:
		if not _valid_shape(shape): return false
	var seen: Dictionary = {}
	for id in a.hit_players:
		if not players.has(id) or seen.has(id): return false
		seen[id] = true
	return true

static func _valid_position(p) -> bool:
	if p is Vector3: return p.is_finite() and absf(p.x) <= 1000.0 and absf(p.y) <= 1000.0 and absf(p.z) <= 1000.0
	if not p is Array or p.size() != 3: return false
	for n in p:
		if (not n is int and not n is float) or not is_finite(float(n)) or absf(float(n)) > 1000.0: return false
	return true

static func _valid_mm(p) -> bool:
	if not p is Array or p.size() != 3: return false
	for n in p:
		if not _bounded_integer(n, -1000000, 1000000): return false
	return true

static func _nonnegative_integer(value) -> bool:
	return _bounded_integer(value, 0, 9007199254740991)

static func _bounded_integer(value, minimum: int, maximum: int) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and float(value) == floor(float(value)) and float(value) >= float(minimum) and float(value) <= float(maximum)

static func _json_tree_valid(value, depth: int = 0) -> bool:
	if depth > 10: return false
	if value is Dictionary:
		if value.size() > 40: return false
		for key in value:
			if not key is String or not _json_tree_valid(value[key], depth + 1): return false
		return true
	if value is Array:
		if value.size() > 8: return false
		for child in value:
			if not _json_tree_valid(child, depth + 1): return false
		return true
	if value is String: return value.length() <= 128
	if value is bool: return true
	return _bounded_integer(value, -9007199254740991, 9007199254740991)

static func _integer_tree(value):
	if value is Dictionary:
		var result: Dictionary = {}
		for key in value: result[key] = _integer_tree(value[key])
		return result
	if value is Array:
		var result: Array = []
		for child in value: result.append(_integer_tree(child))
		return result
	if value is float: return int(value)
	return value

static func _mm(position) -> Array:
	if position is Vector3: return [int(round(position.x * 1000.0)), int(round(position.y * 1000.0)), int(round(position.z * 1000.0))]
	return [int(round(float(position[0]) * 1000.0)), int(round(float(position[1]) * 1000.0)), int(round(float(position[2]) * 1000.0))]

static func _vector(position_mm: Array) -> Vector3:
	return Vector3(float(position_mm[0]), float(position_mm[1]), float(position_mm[2])) / 1000.0

static func _metres(position_mm: Array) -> Array:
	return [float(position_mm[0]) / 1000.0, float(position_mm[1]) / 1000.0, float(position_mm[2]) / 1000.0]

static func _interpolate_mm(a: Array, b: Array, weight: float) -> Array:
	return [int(round(lerpf(float(a[0]), float(b[0]), weight))), int(round(lerpf(float(a[1]), float(b[1]), weight))), int(round(lerpf(float(a[2]), float(b[2]), weight)))]

static func _yes(code: String, events: Array = []) -> Dictionary:
	return {"ok":true, "code":code, "events":events}

static func _no(code: String) -> Dictionary:
	return {"ok":false, "code":code, "events":[]}
