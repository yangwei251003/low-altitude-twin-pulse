class_name TwinCampaignEncounter
extends RefCounted
## Host-only reusable encounter rules. Real physics, damage and Store stay in Session.
## Environment is replaced by a fresh host sample, never inferred from a G press.
const PATH := "res://data/v3/campaign/bosses.json"
const STEP_USEC := 100000
const LEGACY_I4_LANCE_COUNTER := "移开光带、改变高度或移实体遮光板"
const CURRENT_I4_LANCE_COUNTER := "横移离开光带、改变高度或借固定掩体"
var _definition: Dictionary = {}
var _digest := ""
var _legacy_counter_digest := ""
var _state: Dictionary = {}
var _actors: Dictionary = {}

func configure(boss_id: String) -> Dictionary:
	if not _state.is_empty(): return _no("already_started")
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(PATH))
	if not data is Dictionary or data.get("schema_version") != 1: return _no("invalid_boss_definitions")
	for spec in data.get("bosses", []):
		if spec.get("id") != boss_id: continue
		if not spec.get("parts") is Array or spec.parts.size() < 2 or spec.parts.size() > 3 or not spec.get("patterns") is Array or spec.patterns.is_empty(): return _no("invalid_boss_definition")
		_definition = spec.duplicate(true)
		_digest = JSON.stringify(_definition, "", true, true).sha256_text()
		_legacy_counter_digest = _legacy_i4_counter_fingerprint(_definition)
		return _yes("configured")
	return _no("unknown_boss")

func definition() -> Dictionary:
	return _definition.duplicate(true)

func bind_actors(actors: Dictionary, is_authority: bool = true) -> Dictionary:
	if not is_authority: return _no("authority_required")
	if actors.size() > 2: return _no("party_limit")
	var valid: Dictionary = {}
	for id in actors:
		if not id is String or id.is_empty() or id.length() > 80 or not actors[id] is Dictionary: return _no("invalid_actor")
		var actor: Dictionary = actors[id]
		if not _position(actor.get("position")) or not actor.get("active") is bool: return _no("invalid_actor")
		valid[id] = {"position_mm":_mm(actor.position), "active":actor.active}
	_actors = valid
	return _yes("actors_bound")

func start(centre: Vector3, is_authority: bool = true) -> Dictionary:
	if not is_authority: return _no("authority_required")
	if _definition.is_empty() or not _state.is_empty() or not _position(centre): return _no("invalid_start")
	if _alive_ids().is_empty(): return _no("active_player_required")
	_state = _fresh(_mm(centre), 1, 0)
	var events: Array = []
	_telegraph(events)
	return _yes("started", events)

func reset_attempt(is_authority: bool = true) -> Dictionary:
	if not is_authority: return _no("authority_required")
	if _state.is_empty() or _state.completed or _alive_ids().is_empty(): return _no("cannot_retry")
	var attempt: int = int(_state.attempt) + 1
	var serial: int = int(_state.serial)
	var centre: Array = _state.centre_mm.duplicate()
	_state = _fresh(centre, attempt, serial)
	var events: Array = []
	_emit(events, "encounter_reset", {"attempt":attempt})
	_telegraph(events)
	# Root resets all bodies/temporary mechanisms from its entrance checkpoint.
	return _yes("retry_whole_attempt", events)

func observe_environment(sample: Dictionary, context: Dictionary) -> Dictionary:
	if context.get("is_authority") != true or context.get("physical_sample") != true: return _no("physical_host_sample_required")
	if _state.is_empty() or _state.completed: return _no("not_active")
	if not _valid_environment(sample): return _no("invalid_environment_sample")
	_state.environment = sample.duplicate(true)
	return _yes("environment_sampled")

func advance(delta: float, paused: bool = false, is_authority: bool = true) -> Dictionary:
	if not is_authority: return _no("authority_required")
	if not is_finite(delta) or delta < 0.0 or delta > 10.0: return _no("invalid_delta")
	if _state.is_empty(): return _no("not_started")
	if paused or delta == 0.0 or _state.completed or _alive_ids().is_empty(): return _yes("frozen")
	_state.pending_usec += int(round(delta * 1000000.0))
	var events: Array = []
	while int(_state.pending_usec) >= STEP_USEC:
		_state.pending_usec -= STEP_USEC
		_state.tick += 1
		if int(_state.exposed_until) > 0 and int(_state.tick) >= int(_state.exposed_until):
			_rearm()
			_emit(events, "core_shielded")
		if int(_state.tick) < int(_state.transition_tick): continue
		match str(_state.attack_stage):
			"warning":
				_state.attack_stage = "active"
				_state.transition_tick = int(_state.tick) + int(_state.attack.active_ticks)
				_emit(events, "attack_active", {"attack":_state.attack.duplicate(true)})
			"active":
				_state.attack_stage = "recovery"
				_state.transition_tick = int(_state.tick) + int(_definition.recovery_ticks)
				_emit(events, "attack_expired", {"token":_state.attack.token})
				_emit(events, "recovery_started", {"part_id":current_part()})
			"recovery":
				_state.pattern_index = (int(_state.pattern_index) + 1) % _definition.patterns.size()
				_telegraph(events)
	return _yes("advanced", events)

func current_part() -> String:
	if _state.is_empty(): return ""
	for id in _part_order():
		if int(_state.parts[id]) > 0: return str(id)
	return "core"

func part_open(part_id: String) -> bool:
	if _state.is_empty() or _state.completed: return false
	if part_id == "core": return int(_state.exposed_until) > int(_state.tick)
	if part_id != current_part() or _state.attack_stage != "recovery": return false
	for condition in _definition.part_conditions.get(part_id, []):
		var actual: Variant = _state.environment.get(condition.field)
		match str(condition.op):
			"eq":
				if actual != condition.value: return false
			"le":
				if not actual is int and not actual is float: return false
				if float(actual) > float(condition.value): return false
			"ge":
				if not actual is int and not actual is float: return false
				if float(actual) < float(condition.value): return false
			_: return false
	return true

func hit_part(part_id: String, damage_milli: int, actor_id: String, shot_sequence: int, context: Dictionary) -> Dictionary:
	if context.get("is_authority") != true or context.get("hit_confirmed") != true or context.get("line_of_sight") != true: return _no("host_physical_hit_required")
	if _state.is_empty() or _state.completed or actor_id not in _alive_ids(): return _no("actor_inactive")
	if damage_milli < 1 or damage_milli > 50000 or shot_sequence < 1: return _no("invalid_damage_or_sequence")
	if part_id != "core" and not _state.parts.has(part_id): return _no("unknown_part")
	if shot_sequence <= int(_state.last_sequences.get(actor_id, 0)): return _no("replayed_shot")
	if int(_state.tick) < int(_state.shot_after.get(actor_id, 0)): return _no("shot_cooldown")
	_state.last_sequences[actor_id] = shot_sequence
	_state.shot_after[actor_id] = int(_state.tick) + 2
	if not part_open(part_id): return _no("part_shielded")
	var events: Array = []
	if part_id == "core":
		var hp: int = maxi(0, int(_state.core_hp_milli) - damage_milli)
		var half: int = int(_definition.core_hp_milli) >> 1
		if int(_state.phase) == 1 and hp <= half:
			_state.core_hp_milli = half
			_state.phase = 2
			_rearm()
			_emit(events, "attack_expired", {"token":_state.attack.get("token", "")})
			_emit(events, "phase_changed", {"phase":2})
			_telegraph(events)
		else:
			_state.core_hp_milli = hp
			if hp == 0:
				_state.completed = true
				_state.attack_stage = "defeated"
				_emit(events, "attack_expired", {"token":_state.attack.get("token", "")})
				_state.attack = {}
				_emit(events, "boss_defeated", {"boss_id":_definition.id})
	else:
		_state.parts[part_id] = maxi(0, int(_state.parts[part_id]) - damage_milli)
		if int(_state.parts[part_id]) == 0:
			_emit(events, "part_disabled", {"part_id":part_id})
			if current_part() == "core":
				_state.exposed_until = int(_state.tick) + int(_definition.exposure_ticks)
				_emit(events, "core_exposed", {"until_tick":_state.exposed_until})
	_emit(events, "part_hit", {"part_id":part_id, "actor_id":actor_id, "core_hp_milli":_state.core_hp_milli})
	return _yes("hit", events)

func claim_attack_hit(token: String, actor_id: String, context: Dictionary) -> Dictionary:
	if context.get("is_authority") != true or context.get("line_of_sight") != true or context.get("physical_hit") != true: return _no("host_collision_required")
	if _state.is_empty() or _state.completed or actor_id not in _alive_ids(): return _no("actor_inactive")
	if _state.attack_stage != "active" or _state.attack.get("token") != token: return _no("attack_inactive")
	if actor_id in _state.attack.hit_actors: return _no("duplicate_attack_hit")
	var inside := false
	for shape in _state.attack.shapes:
		if contains_shape(shape, _actors[actor_id].position_mm): inside = true
	if not inside: return _no("outside_warning_shape")
	_state.attack.hit_actors.append(actor_id)
	var events: Array = []
	_emit(events, "player_damage_requested", {"actor_id":actor_id, "token":token, "damage_milli":_state.attack.damage_milli})
	# This does not mutate player health. Root uses its existing armor/damage path.
	return _yes("damage_claimed", events)

func snapshot() -> Dictionary:
	return {"schema_version":1, "definition_id":_definition.get("id", ""), "definition_digest":_digest, "state":_state.duplicate(true)}

func get_state() -> Dictionary:
	return _state.duplicate(true)

func restore(candidate: Dictionary) -> Dictionary:
	var checked: Dictionary = validate_snapshot(candidate)
	if not checked.ok: return checked
	_state = _integer_tree(candidate.state)
	return _yes("restored")

func _definition_digest_matches(value: Variant) -> bool:
	return value == _digest or (not _legacy_counter_digest.is_empty() and value == _legacy_counter_digest)

static func _legacy_i4_counter_fingerprint(spec: Dictionary) -> String:
	# Only the currently corrected I4 definition has this one counterfactual.
	# Copy the ENTIRE current definition, changing exactly one prose leaf back.
	# Every other field remains inside the original full-precision digest.
	if spec.get("id") != "prism_array" or spec.get("region_id") != "I4" or not spec.get("patterns") is Array: return ""
	var legacy: Dictionary = spec.duplicate(true)
	var found := -1
	for index: int in range(legacy.patterns.size()):
		var pattern: Variant = legacy.patterns[index]
		if not pattern is Dictionary or pattern.get("id") != "prism_lance": continue
		if found >= 0 or pattern.get("counter") != CURRENT_I4_LANCE_COUNTER: return ""
		found = index
	if found < 0: return ""
	legacy.patterns[found]["counter"] = LEGACY_I4_LANCE_COUNTER
	return JSON.stringify(legacy, "", true, true).sha256_text()

func validate_snapshot(candidate: Dictionary) -> Dictionary:
	if _definition.is_empty() or candidate.size() != 4 or candidate.get("schema_version") != 1 or candidate.get("definition_id") != _definition.id or not _definition_digest_matches(candidate.get("definition_digest")): return _no("definition_mismatch")
	if not candidate.get("state") is Dictionary: return _no("invalid_state")
	var s: Dictionary = candidate.state
	var expected: Array = _fresh([0,0,0], 1, 0).keys()
	if s.size() != expected.size(): return _no("state_keys")
	for key in expected:
		if not s.has(key): return _no("state_keys")
	for key in ["attempt", "serial", "tick", "pending_usec", "core_hp_milli", "phase", "pattern_index", "transition_tick", "exposed_until"]:
		if not _integer(s[key], 0, 2147483647): return _no("invalid_counter")
	if int(s.attempt) < 1 or int(s.pending_usec) >= STEP_USEC or int(s.phase) not in [1,2] or int(s.pattern_index) >= _definition.patterns.size(): return _no("invalid_phase")
	if int(s.core_hp_milli) > int(_definition.core_hp_milli) or not s.completed is bool or s.completed != (int(s.core_hp_milli) == 0): return _no("invalid_completion")
	var half: int = int(_definition.core_hp_milli) >> 1
	if (int(s.phase) == 1 and int(s.core_hp_milli) <= half) or (int(s.phase) == 2 and int(s.core_hp_milli) > half): return _no("invalid_health_phase")
	if not _valid_mm(s.centre_mm) or not _valid_environment(s.environment): return _no("invalid_environment")
	if not s.parts is Dictionary or s.parts.size() != _definition.parts.size(): return _no("invalid_parts")
	var any_part_alive := false
	var encountered_alive := false
	var order: Array = _definition.parts.duplicate()
	if int(s.phase) == 2: order.reverse()
	for id in order:
		if not _integer(s.parts.get(id), 0, int(_definition.part_hp_milli)): return _no("invalid_part_hp")
		if int(s.parts[id]) > 0:
			any_part_alive = true
			encountered_alive = true
		elif encountered_alive: return _no("invalid_part_order")
	if not s.completed and any_part_alive != (int(s.exposed_until) == 0): return _no("invalid_exposure")
	if not s.completed and int(s.exposed_until) > 0 and int(s.exposed_until) <= int(s.tick): return _no("expired_exposure")
	for key in ["last_sequences", "shot_after"]:
		if not s[key] is Dictionary or s[key].size() > 16: return _no("invalid_shot_receipts")
		for id in s[key]:
			if not id is String or id.is_empty() or id.length() > 80 or not _integer(s[key][id],0,2147483647): return _no("invalid_shot_receipt")
	if s.completed:
		if s.attack_stage != "defeated" or not s.attack is Dictionary or not s.attack.is_empty(): return _no("invalid_defeated_attack")
	else:
		if s.attack_stage not in ["warning", "active", "recovery"] or int(s.transition_tick) <= int(s.tick): return _no("invalid_attack_stage")
		if not _attack_valid(s.attack): return _no("invalid_attack")
	return _yes("snapshot_valid")

func _fresh(centre: Array, attempt: int, serial: int) -> Dictionary:
	var parts: Dictionary = {}
	for id in _definition.parts: parts[id] = int(_definition.part_hp_milli)
	return {"attempt":attempt, "serial":serial, "tick":0, "pending_usec":0,
		"centre_mm":centre.duplicate(), "core_hp_milli":int(_definition.core_hp_milli), "phase":1,
		"parts":parts, "environment":_definition.environment_defaults.duplicate(true),
		"pattern_index":0, "attack_stage":"warning", "transition_tick":0,
		"exposed_until":0, "attack":{}, "completed":false, "last_sequences":{}, "shot_after":{}}

func _rearm() -> void:
	for id in _definition.parts: _state.parts[id] = int(_definition.part_hp_milli)
	_state.exposed_until = 0

func _telegraph(events: Array) -> void:
	var spec: Dictionary = _definition.patterns[int(_state.pattern_index)]
	var actors: Array = _alive_ids()
	if actors.is_empty(): return
	var target: Array = _actors[actors[int(_state.serial) % actors.size()]].position_mm
	var warning: int = int(spec.warning_ticks) - (3 if int(_state.phase) == 2 else 0)
	_state.attack_stage = "warning"
	_state.transition_tick = int(_state.tick) + warning
	_state.attack = {"token":"campaign:%s:%d:%d" % [_definition.id,int(_state.attempt),int(_state.serial)+1], "pattern_id":spec.id,
		"damage_milli":int(spec.damage_milli), "active_ticks":int(spec.active_ticks),
		"shapes":_shapes(spec, target), "hit_actors":[]}
	_emit(events, "telegraph_started", {"attack":_state.attack.duplicate(true), "warning_ticks":warning, "counter":spec.counter})

func _shapes(spec: Dictionary, target: Array) -> Array:
	if spec.shape == "ring":
		return [{"kind":"ring", "centre_mm":_state.centre_mm.duplicate(), "inner_mm":int(spec.inner_mm), "outer_mm":int(spec.outer_mm), "y_min_mm":int(spec.y_min_mm), "y_max_mm":int(spec.y_max_mm)}]
	var common := {"kind":"disc" if spec.shape == "locked_disc" else "lane", "centre_mm":target.duplicate(),
		"y_min_mm":maxi(0,int(target[1])-int(spec.height_mm)), "y_max_mm":int(target[1])+int(spec.height_mm)}
	if spec.shape == "locked_disc":
		common["outer_mm"] = int(spec.outer_mm)
		return [common]
	common["width_mm"] = int(spec.width_mm)
	common["length_mm"] = int(spec.length_mm)
	common["axis"] = str(spec.get("axis", "z"))
	if spec.shape == "locked_cross":
		var other: Dictionary = common.duplicate(true)
		other["axis"] = "x" if common.axis == "z" else "z"
		return [common,other]
	return [common]

static func contains_shape(shape: Dictionary, at_mm: Array) -> bool:
	if not _valid_shape(shape) or not _valid_mm(at_mm): return false
	if int(at_mm[1]) < int(shape.y_min_mm) or int(at_mm[1]) >= int(shape.y_max_mm): return false
	var dx: int = int(at_mm[0]) - int(shape.centre_mm[0])
	var dz: int = int(at_mm[2]) - int(shape.centre_mm[2])
	if shape.kind == "lane":
		return absi(dx) * 2 <= int(shape.width_mm) and absi(dz) * 2 <= int(shape.length_mm) if shape.axis == "z" else absi(dz) * 2 <= int(shape.width_mm) and absi(dx) * 2 <= int(shape.length_mm)
	var r2: int = dx*dx + dz*dz
	return r2 <= int(shape.outer_mm)*int(shape.outer_mm) and r2 >= int(shape.get("inner_mm",0))*int(shape.get("inner_mm",0))

func _valid_environment(value) -> bool:
	if not value is Dictionary or value.size() != _definition.environment_defaults.size(): return false
	for field in _definition.environment_defaults:
		if not value.has(field): return false
		var default: Variant = _definition.environment_defaults[field]
		if default is bool:
			if not value[field] is bool: return false
		elif not _integer(value[field], -1000000,1000000): return false
	return true

static func _valid_shape(shape) -> bool:
	if not shape is Dictionary or shape.get("kind") not in ["ring", "disc", "lane"] or not _valid_mm(shape.get("centre_mm")): return false
	if not _integer(shape.get("y_min_mm"),0,1000000) or not _integer(shape.get("y_max_mm"),1,1000000) or int(shape.y_min_mm) >= int(shape.y_max_mm): return false
	if shape.kind == "lane": return shape.get("axis") in ["x","z"] and _integer(shape.get("width_mm"),1,100000) and _integer(shape.get("length_mm"),1,100000)
	return _integer(shape.get("outer_mm"),1,100000) and _integer(shape.get("inner_mm",0),0,int(shape.outer_mm)-1)

static func _attack_valid(value) -> bool:
	if not value is Dictionary or value.size() != 6: return false
	if not value.get("token") is String or value.token.is_empty() or value.token.length() > 160 or not value.get("pattern_id") is String: return false
	if not _integer(value.get("damage_milli"),1,50000) or not _integer(value.get("active_ticks"),1,100): return false
	if not value.get("shapes") is Array or value.shapes.is_empty() or value.shapes.size() > 2 or not value.get("hit_actors") is Array or value.hit_actors.size() > 2: return false
	for shape in value.shapes:
		if not _valid_shape(shape): return false
	var seen: Dictionary = {}
	for actor in value.hit_actors:
		if not actor is String or actor.is_empty() or actor.length() > 80 or seen.has(actor): return false
		seen[actor] = true
	return true

func _alive_ids() -> Array:
	var ids: Array = []
	for id in _actors:
		if _actors[id].active: ids.append(id)
	ids.sort()
	return ids

func _part_order() -> Array:
	var order: Array = _definition.parts.duplicate()
	if int(_state.get("phase", 1)) == 2: order.reverse()
	return order

func _emit(events: Array, kind: String, details: Dictionary = {}) -> void:
	_state.serial += 1
	var event := {"type":kind,"kind":kind,"boss_id":_definition.id,"tick":int(_state.tick),"attempt":int(_state.attempt),"serial":int(_state.serial),"event_id":"campaign:%s:%d:%d" % [_definition.id,int(_state.attempt),int(_state.serial)]}
	event.merge(details.duplicate(true), true)
	events.append(event)

static func _position(value) -> bool:
	if value is Vector3: return value.is_finite() and maxf(absf(value.x),maxf(absf(value.y),absf(value.z))) <= 1000.0
	if not value is Array or value.size() != 3: return false
	for number in value:
		if not (number is int or number is float) or not is_finite(float(number)) or absf(float(number)) > 1000.0: return false
	return true

static func _valid_mm(value) -> bool:
	if not value is Array or value.size() != 3: return false
	for number in value:
		if not _integer(number,-1000000,1000000): return false
	return true

static func _mm(value) -> Array:
	if value is Vector3: return [int(round(value.x*1000)),int(round(value.y*1000)),int(round(value.z*1000))]
	return [int(round(float(value[0])*1000)),int(round(float(value[1])*1000)),int(round(float(value[2])*1000))]

static func _integer(value, low: int, high: int) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and float(value) == floor(float(value)) and float(value) >= float(low) and float(value) <= float(high)

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

static func _yes(code: String, events: Array = []) -> Dictionary:
	return {"ok":true,"code":code,"events":events}

static func _no(code: String) -> Dictionary:
	return {"ok":false,"code":code,"events":[]}
