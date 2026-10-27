extends SceneTree

const Rules = preload("res://scripts/v3/gameplay/twin_ability_rules.gd")
const Encounter = preload("res://scripts/v3/gameplay/twin_encounter_state.gd")
const Registry = preload("res://scripts/v3/gameplay/twin_content_registry.gd")
var failures: Array[String] = []
var checks := 0

func _init() -> void:
	_test_ability_guards()
	_test_ten_actions_and_expiration()
	_test_concurrent_ownership()
	_test_encounter()
	_test_encounter_membership()
	_test_registry()
	if failures.is_empty():
		print("PASS gameplay: %d checks (logic only; no graphics, network or human-play evidence)" % checks)
		quit(0)
	else:
		for message in failures:
			push_error(message)
		print("FAIL gameplay: %d/%d failed" % [failures.size(), checks])
		quit(1)

func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)

func _entities() -> Dictionary:
	return {
		"p1": {"id": "p1", "owner": "peer1", "position": Vector3.ZERO, "tags": ["player"], "energy": 1000.0, "health": 100.0, "revision": 0},
		"p2": {"id": "p2", "owner": "peer2", "position": Vector3(1, 0, 0), "tags": ["player"], "energy": 1000.0, "health": 100.0, "revision": 0},
		"machine": {"id": "machine", "owner": "enemy", "position": Vector3(3, 0, 0), "tags": ["movable", "fieldable", "photosensitive", "solar", "thermal", "combustible", "conductive", "electrical", "mechanical", "hackable", "enemy", "echo_operable"], "temperature": 20.0, "charge": 0.0, "revision": 0},
		"plant": {"id": "plant", "position": Vector3(2, 0, 0), "tags": ["photosensitive", "growable", "thermal"], "light_level": 0.0, "growth": 0.0, "temperature": 20.0, "revision": 0},
		"stone": {"id": "stone", "position": Vector3(2, 0, 0), "tags": [], "revision": 0}
	}

func _intent(ability: String, target_id: String = "machine", mode: String = "") -> Dictionary:
	return {"actor_id": "p1", "ability": ability, "target_id": target_id, "mode": mode, "point": Vector3(4, 0, 0)}

func _context() -> Dictionary:
	return {"sender_id": "peer1", "line_of_sight": true}

func _test_ability_guards() -> void:
	var rules = Rules.new()
	var entities := _entities()
	var original := entities.duplicate(true)
	_check(rules.resolve(_intent("heat"), entities, _context()).ok, "supported action resolves")
	_check(entities == original, "resolve is pure")
	_check(rules.resolve(_intent("heat"), entities, {}).code == "not_owner", "missing authority denied")
	_check(rules.resolve(_intent("heat"), entities, {"sender_id": "peer2", "line_of_sight": true}).code == "not_owner", "other peer cannot control actor")
	_check(rules.resolve(_intent("heat"), entities, {"sender_id": "peer1"}).code == "line_of_sight_required", "wall/unchecked LOS denied")
	_check(rules.resolve(_intent("heat", "stone"), entities, _context()).code == "unsupported_target", "stone does not gain arbitrary heat power")
	_check(rules.resolve(_intent("charge", "p2"), entities, _context()).code == "player_target_not_supported", "no default player griefing")
	_check(rules.resolve(_intent("unknown"), entities, _context()).code == "unknown_ability", "unknown action denied")
	_check(rules.resolve(_intent("heat", "machine", "evil"), entities, _context()).code == "invalid_mode", "unknown mode denied")
	entities.machine.position = Vector3(100, 0, 0)
	_check(rules.resolve(_intent("heat"), entities, _context()).code == "out_of_range", "distance denied")
	entities = _entities()
	entities.p1.energy = 1.0
	_check(rules.resolve(_intent("heat"), entities, _context()).code == "insufficient_energy", "energy denied")
	entities = _entities()
	entities.p1.downed = true
	_check(rules.resolve(_intent("heat"), entities, _context()).code == "actor_downed", "downed cannot cast")
	entities = _entities()
	var blink: Dictionary = rules.resolve(_intent("blink"), entities, _context())
	_check(blink.ok and blink.code == "physics_required", "blink requires physical sweep")
	_check(rules.commit(blink, entities).code == "physics_not_approved" and entities.p1.energy == 1000.0, "blocked physical action spends nothing")
	_check(rules.commit(blink, entities, true).ok and entities.p1.position == Vector3.ZERO, "rules never teleport scene/state automatically")
	_check(rules.commit(blink, entities, true).code == "stale_transaction", "transaction cannot replay")
	var invalid_blink := _intent("blink")
	invalid_blink.point = Vector3(INF, 0, 0)
	_check(rules.resolve(invalid_blink, entities, _context()).code == "invalid_destination", "nonfinite destination denied")

func _test_ten_actions_and_expiration() -> void:
	var rules = Rules.new()
	var entities := _entities()
	for ability in ["blink", "push_pull", "force_field", "light", "heat", "charge", "decoy", "echo", "takeover"]:
		var outcome: Dictionary = rules.resolve(_intent(ability), entities, _context())
		_check(outcome.ok, "action resolves: " + ability)
		_check(rules.commit(outcome, entities, true).ok, "action commits: " + ability)
	_check(entities.machine.pinned, "force field pins supported target")
	_check(rules.resolve(_intent("push_pull"), entities, _context()).code == "target_pinned", "pinned blocks impulse")
	_check(entities.machine.temperature == 45.0, "heat changes temperature")
	_check(entities.machine.charge == 35.0 and entities.machine.powered, "charge powers electrical target")
	_check(entities.machine.owner == "peer1" and entities.machine.controlled, "takeover changes ownership")
	_check(rules.resolve(_intent("growth", "plant"), entities, _context()).code == "growth_needs_light", "growth needs light")
	rules.commit(rules.resolve(_intent("light", "plant"), entities, _context()), entities)
	_check(rules.commit(rules.resolve(_intent("growth", "plant"), entities, _context()), entities).ok, "light plus growth genuinely combines")
	_check(is_equal_approx(float(entities.plant.growth), 0.35), "growth exact state")
	entities.plant.temperature = 100.0
	_check(rules.resolve(_intent("growth", "plant"), entities, _context()).code == "growth_temperature", "hot plant cannot grow")
	var expiration: Dictionary = rules.advance_states(entities, 10.0)
	_check(rules.commit(expiration, entities).ok, "status expiration commits")
	_check(not entities.machine.pinned and not entities.machine.operated, "temporary pin and echo expire")
	_check(entities.machine.owner == "enemy" and not entities.machine.controlled, "control returns to original owner")
	_check(entities.machine.powered, "alternate electric supply survives expired solar input")
	_check(entities.p1.decoy_remaining == 0.0, "decoy lifetime bounded")
	_check(rules.advance_states(entities, -1.0).code == "invalid_delta", "negative time rejected")

func _test_concurrent_ownership() -> void:
	var rules = Rules.new()
	var entities := _entities()
	var first: Dictionary = rules.resolve(_intent("takeover"), entities, _context())
	var second_intent := _intent("takeover")
	second_intent.actor_id = "p2"
	var second: Dictionary = rules.resolve(second_intent, entities, {"sender_id": "peer2", "line_of_sight": true})
	_check(first.ok and second.ok, "two intents may read the same initial snapshot")
	rules.commit(first, entities)
	_check(rules.commit(second, entities).code == "stale_transaction", "only first ownership transaction wins")
	_check(entities.p2.energy == 1000.0 and entities.machine.owner == "peer1", "losing peer spends no energy and steals no control")
	_check(rules.resolve(second_intent, entities, {"sender_id": "peer2", "line_of_sight": true}).code == "target_busy", "new conflicting takeover also denied")
	second_intent.ability = "force_field"
	_check(rules.resolve(second_intent, entities, {"sender_id": "peer2", "line_of_sight": true}).code == "target_busy", "field cannot override partner control lease")
	var stale := _intent("heat")
	stale.expected_revision = 0
	_check(rules.resolve(stale, entities, _context()).code == "stale_target", "client target revision checked")

func _test_encounter() -> void:
	var encounter = Encounter.new()
	var snapshot := {"players": {"p1": {"position": Vector3.ZERO, "max_health": 100.0, "equipment": ["owned_module"], "resources": 77}, "p2": {"position": Vector3(1, 0, 0), "max_health": 100.0}}}
	encounter.start(snapshot)
	_check(encounter.hit_part("core", 20.0, "p1").code == "core_shielded", "shooting shield does not damage core")
	_check(encounter.set_node_power("port", false, "p1").code == "node_armored", "node power cannot bypass armored timing")
	var events: Array = encounter.advance(2.7)
	_check(events.any(func(event): return event.type == "attack") and encounter.get_state().nodes_open, "telegraph advances into attack and recovery")
	_check(encounter.set_node_power("port", false, "p1").ok, "environmental node power path works")
	_check(encounter.hit_part("starboard", 40.0, "p2").ok, "damage is alternative node path")
	_check(encounter.get_state().phase == "exposed", "both nodes required for weakness")
	_check(encounter.hit_part("core", 65.0, "p1").ok and encounter.get_state().overdrive, "half health changes mechanics without adding health")
	_check(encounter.hit_part("core", 1.0, "p1").code == "core_shielded", "second phase restores guard rather than free damage")
	encounter.advance(2.7)
	encounter.set_node_power("port", false, "p1")
	encounter.set_node_power("starboard", false, "p2")
	_check(encounter.hit_part("core", 60.0, "p2").ok and encounter.get_state().completed, "boss can be completed through second weakness")
	encounter.reset_attempt()
	_check(encounter.get_state().core_health == 120.0 and not encounter.get_state().completed, "manual retry resets whole boss")
	encounter.down_player("p1")
	_check(encounter.revive_player("p2", "p1", 1.0).code == "revive_incomplete", "revive requires held time")
	encounter.set_player_position("p2", Vector3(10, 0, 0))
	_check(encounter.revive_player("p2", "p1", 3.0).code == "revive_out_of_range", "remote revival denied")
	encounter.set_player_position("p2", Vector3(1, 0, 0))
	_check(encounter.revive_player("p2", "p1", 3.0).ok and encounter.get_state().players.p1.health == 40.0, "nearby partner revives")
	encounter.down_player("p1")
	var attempt_before := int(encounter.get_state().attempt)
	encounter.down_player("p2")
	var state: Dictionary = encounter.get_state()
	_check(state.attempt == attempt_before + 1 and state.reset_reason == "full_wipe", "all down resets entire attempt")
	_check(not state.players.p1.downed and state.core_health == 120.0, "full wipe restores players and boss")
	_check(state.players.p1.resources == 77 and state.players.p1.equipment == ["owned_module"], "owned assets are not deducted")
	state.core_health = 1.0
	_check(encounter.get_state().core_health == 120.0, "state getter is isolated")
	_check(snapshot.players.p1.resources == 77, "checkpoint input unmodified")
	var solo = Encounter.new()
	solo.start({"players": {"solo": {"position": Vector3.ZERO, "max_health": 100.0}}})
	solo.down_player("solo")
	_check(solo.get_state().attempt == 2, "single-player down also retries")

func _test_encounter_membership() -> void:
	var encounter = Encounter.new()
	var entrance := {"position": Vector3(2, 1, 0), "max_health": 80.0, "health": 0.0, "downed": true}
	_check(encounter.add_player("p2", entrance).code == "encounter_not_started", "join does not silently start a fight")
	encounter.start({"players": {"p1": {"position": Vector3.ZERO, "max_health": 100.0}}})
	encounter.advance(2.7)
	encounter.set_node_power("port", false, "p1")
	encounter.set_node_power("starboard", false, "p1")
	encounter.hit_part("core", 65.0, "p1")
	encounter.advance(2.7)
	encounter.hit_part("port", 12.0, "p1")
	var before := _without_players(encounter.get_state())
	_check(encounter.add_player("p2", entrance).ok, "partner can join in overdrive recovery")
	_check(_without_players(encounter.get_state()) == before, "join preserves every boss field including phase, node damage, timers and attempt")
	var joined: Dictionary = encounter.get_state().players.p2
	_check(joined.position == entrance.position and joined.health == 80.0 and not joined.downed, "join uses supplied entrance with full health")
	_check(entrance.health == 0.0 and entrance.downed, "join does not mutate caller snapshot")
	_check(encounter.add_player("third", entrance).code == "party_full", "encounter enforces 1-2 player scope")
	encounter.down_player("p2")
	_check(encounter.add_player("p2", entrance).code == "player_already_present" and encounter.get_state().players.p2.downed, "duplicate join cannot heal a downed participant")
	var departed: Dictionary = encounter.remove_player("p2")
	_check(departed.ok and _without_players(encounter.get_state()) == before, "normal leave preserves complete boss progress")
	_check(encounter.remove_player("missing").code == "player_missing", "unknown leave does not alter state")
	_check(encounter.add_player("p2", {"position": Vector3(INF, 0, 0)}).code == "invalid_entrance_position", "nonfinite entry position denied")
	_check(encounter.add_player("p2", {"position": Vector3.ZERO, "max_health": -1}).code == "invalid_max_health", "nonpositive entry health denied")
	_check(encounter.add_player("", entrance).code == "invalid_player_id", "empty participant ID denied")
	encounter.add_player("p2", entrance)
	encounter.down_player("p2")
	var previous_attempt: int = encounter.get_state().attempt
	departed = encounter.remove_player("p1")
	_check(departed.events.any(func(event): return event.type == "attempt_reset" and event.reason == "remaining_players_downed"), "departure leaving only downed partner emits explicit reset")
	var state: Dictionary = encounter.get_state()
	_check(state.attempt == previous_attempt + 1 and state.core_health == 120.0 and not state.players.p2.downed, "remaining downed participant receives whole-attempt reset")
	_check(state.players.size() == 1 and not state.players.has("p1") and state.players.p2.position == entrance.position, "retry checkpoint updates membership and entry position")
	encounter.down_player("p2")
	_check(encounter.get_state().players.size() == 1 and not encounter.get_state().players.has("p1"), "later retry does not resurrect departed participant")
	before = _without_players(encounter.get_state())
	departed = encounter.remove_player("p2")
	_check(departed.events.any(func(event): return event.type == "encounter_empty") and not departed.events.any(func(event): return event.type in ["attempt_reset", "boss_defeated"]), "last departure empties without wipe or victory event")
	_check(_without_players(encounter.get_state()) == before and not encounter.get_state().completed, "empty party cannot complete or reset encounter")
	_check(encounter.advance(30.0).is_empty() and _without_players(encounter.get_state()) == before, "vacant encounter freezes attack and weakness timers")
	_check(encounter.add_player("p2", entrance).ok and _without_players(encounter.get_state()) == before, "reconnect resumes preserved vacant encounter")
	encounter.advance(2.7)
	encounter.set_node_power("port", false, "p2")
	encounter.set_node_power("starboard", false, "p2")
	encounter.hit_part("core", 120.0, "p2")
	_check(encounter.add_player("p1", entrance).code == "encounter_completed", "late join cannot retroactively participate in completed fight")

func _without_players(state: Dictionary) -> Dictionary:
	var boss_state := state.duplicate(true)
	boss_state.erase("players")
	return boss_state

func _test_registry() -> void:
	var registry = Registry.new()
	var loaded: Dictionary = registry.load_registry()
	_check(loaded.ok, "registry parses and references validate")
	if not loaded.ok:
		return
	var data: Dictionary = loaded.data
	_check(data.regions.size() == 8 and data.bosses.size() == 8 and data.abilities.size() == 10, "full scope identities registered")
	_check(data.objectives.size() == 3 and data.release_scope.main_objectives_complete == 0, "planned 84 not falsely represented as implemented")
	for ability in data.abilities:
		_check(Rules.DEFINITIONS.has(ability.id) and float(ability.energy) == Rules.DEFINITIONS[ability.id].energy and float(ability.range) == Rules.DEFINITIONS[ability.id].range, "registry matches actual rules: " + str(ability.id))
	data.regions.append(data.regions[0])
	_check(registry.validate(data).code == "duplicate_id", "duplicate registry identity rejected")
