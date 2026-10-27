extends SceneTree
## Pure mechanism regression. No real physics, engine map, network, save store or human-play claim.
const Crown = preload("res://scripts/v3/gameplay/twin_crown_encounter.gd")
const WEST := "F1:crown_host_west"
const HIGH := "F1:crown_host_high"
const EAST := "F1:crown_host_east"
const VERIFIED := {"is_authority":true, "line_of_sight":true, "hit_confirmed":true, "sender_id":"1"}
var checks := 0
var failures: Array = []

func _init() -> void:
	_test_authority_time_and_copies()
	_test_abilities_and_transactions()
	_test_two_routes_and_movement()
	_test_all_hosts_scorched()
	_test_combat_and_spatial_attacks()
	_test_roster_and_retry()
	_test_snapshot_and_replay()
	_test_authored_spatial_roles()
	_test_real_player_state_sync()
	_test_interrupt_movement_and_rollback()
	_test_independent_retry_entry()
	_test_host_resolved_damage()
	var sample = _new()
	print("V3_CROWN_ENCOUNTER_TESTS " + JSON.stringify({"checks":checks, "failures":failures,
		"snapshot_bytes":JSON.stringify(sample.snapshot(), "", true, true).to_utf8_buffer().size(),
		"scope":"pure crown state, shared ability costs, host-approved movement fixture and JSON replay; no live map/physics/LAN/graphics/performance or human combat timing evidence"}))
	quit(0 if failures.is_empty() else 1)

func _check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures.append(label)
		push_error(label)

func _new(two: bool = false):
	var state = Crown.new()
	_check(state.load_definition().ok, "crown definition loads")
	var players: Dictionary = {"player:1":{"owner":"1", "position":Vector3(-10, 13, -3), "health":100.0, "max_health":100.0, "downed":false}}
	if two: players["player:2"] = {"owner":"2", "position":Vector3(-9, 13, -3), "health":100.0, "max_health":100.0, "downed":false}
	_check(state.start(players, 8128).ok, "crown starts with bounded roster")
	return state

func _test_host_resolved_damage() -> void:
	var state = _new(true)
	state.set_player_position("player:1", Vector3(-2, 5, -6))
	state.advance(5.0)
	var attack: Dictionary = state.get_state().attack
	_check(attack.get("fired", false), "damage preview fixture uses an active real attack")
	var before = state.snapshot()
	for invalid in [-1, 24001, 0.5, NAN, "12000"]:
		var context = VERIFIED.duplicate()
		context.resolved_damage_milli = invalid
		_check(state.apply_attack_hit(attack.token, "player:1", context).code == "invalid_resolved_damage" and state.snapshot() == before, "invalid projected damage rejected atomically: " + str(invalid))
	var protected = VERIFIED.duplicate()
	protected.resolved_damage_milli = 12000
	var result = state.apply_attack_hit(attack.token, "player:1", protected)
	_check(result.ok and state.get_state().players["player:1"].health == 88.0, "host armor result applied once instead of raw damage")
	_check(result.events[0].raw_damage_milli == 24000 and result.events[0].damage_milli == 12000, "event retains raw and resolved damage")
	before = state.snapshot()
	_check(state.apply_attack_hit(attack.token, "player:1", protected).code == "attack_already_hit" and state.snapshot() == before, "protected hit still consumes one attack receipt")
	state.set_player_position("player:2", Vector3(-1, 5, -6))
	protected.resolved_damage_milli = 0
	result = state.apply_attack_hit(attack.token, "player:2", protected)
	_check(result.ok and state.get_state().players["player:2"].health == 100.0, "full protection preserves health")
	_check(state.apply_attack_hit(attack.token, "player:2", protected).code == "attack_already_hit", "full protection also prevents repeated armor settlement")

func _actors(state, energy: float = 500.0) -> Dictionary:
	var actors: Dictionary = {}
	var s: Dictionary = state.get_state()
	for id in s.players:
		var position: Array = s.players[id].position
		actors[id] = {"owner":s.players[id].owner, "tags":["player"], "position":Vector3(position[0], position[1], position[2]),
			"health":s.players[id].health, "downed":s.players[id].downed, "energy":energy, "revision":0}
	return actors

func _intent(ability: String, target: String, mode: String = "", actor: String = "player:1") -> Dictionary:
	return {"ability":ability, "actor_id":actor, "target_id":target, "mode":mode}

func _ability(state, actors: Dictionary, ability: String, target: String, mode: String = "") -> Dictionary:
	var tx: Dictionary = state.resolve_ability(_intent(ability, target, mode), actors, VERIFIED)
	if not tx.ok: return tx
	return state.commit_ability(tx, actors, true)

func _run(state, seconds: float) -> Array:
	var events: Array = []
	var remaining: float = seconds
	while remaining > 0.00001:
		var step: float = minf(5.0, remaining)
		var result: Dictionary = state.advance(step)
		_check(result.ok, "bounded advance accepted")
		events.append_array(result.events)
		remaining -= step
	return events

func _has(events: Array, kind: String) -> bool:
	for event in events:
		if event.kind == kind: return true
	return false

func _approve(state) -> void:
	var movement: Dictionary = state.get_state().movement
	_check(not movement.is_empty(), "movement request exists")
	if not movement.is_empty(): _check(state.approve_migration(movement.token, true).ok, "host corridor approval fixture accepted")

func _bind_current(state, actors: Dictionary) -> void:
	var host: String = str(state.get_state().anchor_id)
	_check(_ability(state, actors, "light", host).ok, "light applied")
	_check(_ability(state, actors, "growth", host).ok, "growth binds current host")
	_check(state.get_state().mode == "bound" and state.get_state().core_open, "roots expose core")

func _test_authority_time_and_copies() -> void:
	var state = _new()
	var before: Dictionary = state.snapshot()
	_check(not state.advance(1.0, false).ok and state.snapshot() == before, "client cannot advance")
	_check(state.advance(0.0).ok and state.snapshot() == before, "zero delta has no mutation")
	for delta in [-0.1, 5.1, INF, NAN]:
		_check(not state.advance(delta).ok and state.snapshot() == before, "invalid delta cannot mutate")
	_check(not state.set_player_position("player:1", Vector3(INF, 1, 1)).ok, "nonfinite position rejected")
	_check(state.advance(0.037).ok and int(state.snapshot().state.pending_usec) == 37000, "fractional time retained")
	_check(state.advance(0.063).ok and int(state.snapshot().state.tick) == 1 and int(state.snapshot().state.pending_usec) == 0, "fixed-step boundary")
	var copy: Dictionary = state.get_state()
	copy.players["player:1"].position_mm[0] = 999
	copy.anchors.clear()
	var defs: Dictionary = state.definitions()
	defs.anchors.clear()
	_check(state.get_state().anchors.size() == 3 and state.definitions().anchors.size() == 3, "state and definition copies are isolated")
	_check(not state.start({"player:1":{}}, 1).ok, "start cannot silently reset existing fight")
	_check(not state.add_player("bad", {"owner":"3", "position":Vector3.ZERO, "health":100.0, "max_health":100.0, "downed":false}, false).ok, "guest cannot join through pure authority API")

func _test_abilities_and_transactions() -> void:
	var state = _new(true)
	var actors: Dictionary = _actors(state)
	var baseline: Dictionary = state.snapshot()
	var missing_los: Dictionary = VERIFIED.duplicate()
	missing_los.line_of_sight = false
	_check(not state.resolve_ability(_intent("light", WEST), actors, missing_los).ok, "light needs host LOS")
	var wrong_owner: Dictionary = VERIFIED.duplicate()
	wrong_owner.sender_id = "2"
	_check(not state.resolve_ability(_intent("light", WEST), actors, wrong_owner).ok, "other peer cannot spend player energy")
	_check(not state.resolve_ability(_intent("charge", WEST), actors, VERIFIED).ok, "unrelated ability has unsupported feedback")
	_check(not state.resolve_ability(_intent("growth", WEST), actors, VERIFIED).ok, "growth needs light")
	_check(not state.resolve_ability(_intent("light", "not-a-host"), actors, VERIFIED).ok, "unknown host rejected")
	actors["player:1"].energy = 4.0
	_check(not state.resolve_ability(_intent("light", WEST), actors, VERIFIED).ok, "energy required")
	actors["player:1"].energy = 500.0
	_check(state.snapshot() == baseline, "rejected intents never change crown")
	var tx: Dictionary = state.resolve_ability(_intent("light", WEST), actors, VERIFIED)
	_check(tx.ok and state.snapshot() == baseline and actors["player:1"].energy == 500.0, "resolve is pure")
	_check(not state.commit_ability(tx, actors, false).ok and actors["player:1"].energy == 500.0, "no physics approval spends no energy")
	tx.candidate.state.core_hp_milli = 0
	_check(state.commit_ability(tx, actors, true).ok and state.get_state().core_health == 160.0 and actors["player:1"].energy == 495.0, "commit recomputes candidate and charges exact shared cost")
	_check(not state.commit_ability(tx, actors, true).ok and actors["player:1"].energy == 495.0, "duplicate transaction does not spend again")
	var a: Dictionary = state.resolve_ability(_intent("growth", WEST), actors, VERIFIED)
	var peer2: Dictionary = VERIFIED.duplicate()
	peer2.sender_id = "2"
	var b: Dictionary = state.resolve_ability(_intent("growth", WEST, "", "player:2"), actors, peer2)
	_check(a.ok and b.ok, "two peers can independently preview same lit host")
	_check(state.commit_ability(a, actors, true).ok, "first peer arms and consumes trap")
	_check(not state.commit_ability(b, actors, true).ok and actors["player:2"].energy == 500.0, "second stale target intent costs nothing")
	_check(not _ability(state, actors, "growth", WEST).ok, "root recovery prevents infinite refresh")
	var stale: Dictionary = state.resolve_ability(_intent("heat", WEST), actors, VERIFIED)
	actors["player:1"].revision += 1
	_check(not state.commit_ability(stale, actors, true).ok, "external energy revision invalidates preview")
	state.set_player_position("player:1", Vector3(100, 25, 100))
	actors = _actors(state)
	_check(not state.resolve_ability(_intent("light", WEST), actors, VERIFIED).ok, "actual ability range enforced")
	actors["player:1"].position = Vector3(-10, 13, -3)
	_check(not state.resolve_ability(_intent("light", WEST), actors, VERIFIED).ok, "actor cannot forge nearby position")

func _test_two_routes_and_movement() -> void:
	var heat = _new()
	var actors: Dictionary = _actors(heat)
	_check(_ability(heat, actors, "heat", WEST).ok and heat.get_state().mode == "attached", "first heat warms without ejection")
	var second: Dictionary = _ability(heat, actors, "heat", WEST)
	_check(second.ok and actors["player:1"].energy == 484.0 and _has(second.events, "attack_telegraphed"), "second heat costs total16 and announces spore cost")
	var s: Dictionary = heat.get_state()
	_check(s.mode == "migration_warning" and s.anchors[WEST].temperature == 70 and s.hazards.size() == 1, "heat requests fall and scorches host")
	var start: Array = s.position_mm.duplicate()
	_run(heat, 2.0)
	_check(heat.get_state().mode == "awaiting_route" and heat.get_state().position_mm == start, "unapproved fall never teleports")
	_check(not _ability(heat, actors, "growth", WEST).ok, "hot host cannot grow")
	_approve(heat)
	_run(heat, 1.1)
	_check(heat.get_state().mode == "moving" and heat.get_state().position_mm != start, "approved fall follows intermediate 3D positions")
	_run(heat, 1.0)
	s = heat.get_state()
	_check(s.mode == "fallen" and int(s.mode_until) - int(s.tick) == 40 and s.position_mm[1] == 6000, "heat route gives exactly4sec on actual arrival")
	_check(_ability(heat, actors, "heat", WEST).ok and heat.get_state().mode == "fallen", "already burning host does not refresh fall")
	_check(_ability(heat, actors, "heat", WEST, "cool").ok, "cool from95 to70")
	_check(_ability(heat, actors, "heat", WEST, "cool").ok, "cool from70 to45")
	_check(_ability(heat, actors, "heat", WEST, "cool").ok and not heat.get_state().anchors[WEST].burning, "cool below40 restores attachment eligibility")
	var light = _new()
	_run(light, 9.0)
	light.set_player_position("player:1", Vector3(0, 20, -10))
	actors = _actors(light)
	_check(_ability(light, actors, "light", HIGH).ok and _ability(light, actors, "growth", HIGH).ok, "single player prearms distant high host")
	_run(light, 4.2) # Nominal cycle waits for the already telegraphed pollen to finish.
	s = light.get_state()
	_check(s.movement.get("target_id", "") == HIGH, "fresh light selects next attachment")
	_approve(light)
	_run(light, 4.0)
	s = light.get_state()
	_check(s.mode == "bound" and s.anchor_id == HIGH and int(s.mode_until) - int(s.tick) == 60, "timed root landing gives6sec window, longer than heat")
	_check(s.anchors[HIGH].trap_until == 0 and int(s.anchors[HIGH].root_ready_tick) > int(s.tick), "trap consumed with recovery")
	var expired = _new()
	actors = _actors(expired)
	expired.set_player_position("player:1", Vector3(0, 20, -10))
	actors = _actors(expired)
	_ability(expired, actors, "light", HIGH)
	_ability(expired, actors, "growth", HIGH)
	_run(expired, 10.0)
	_check(expired.get_state().anchors[HIGH].trap_until == 0, "early trap expires rather than permanent remote win button")
	var blocked = _new()
	_run(blocked, 13.2)
	s = blocked.get_state()
	_check(blocked.approve_migration(str(s.movement.get("token", "")), false).ok and blocked.get_state().position_mm == s.position_mm and blocked.get_state().core_open, "blocked corridor holds position with attackable fallback")

func _test_combat_and_spatial_attacks() -> void:
	var state = _new()
	_check(not state.hit_core("player:1", 9.0, 1, VERIFIED).ok, "attached core rejects bullets")
	var actors: Dictionary = _actors(state)
	_bind_current(state, actors)
	var denied: Dictionary = VERIFIED.duplicate()
	denied.hit_confirmed = false
	_check(not state.hit_core("player:1", 9.0, 1, denied).ok, "pure state requires host actual-hit evidence")
	_check(not state.hit_core("player:1", 100.0, 1, VERIFIED).ok, "unbounded caller damage rejected")
	_check(state.hit_core("player:1", 50.0, 1, VERIFIED).ok, "first confirmed shot deals damage")
	_check(not state.hit_core("player:1", 50.0, 2, VERIFIED).ok and state.get_state().core_health == 110.0, "new sequence cannot bypass230ms cadence")
	_run(state, 0.23)
	var phase: Dictionary = state.hit_core("player:1", 50.0, 2, VERIFIED)
	_check(phase.ok and _has(phase.events, "phase_changed") and state.get_state().core_health == 80.0 and state.get_state().phase == 2, "half gate absorbs overflow and forces second phase without healing")
	_check(not state.hit_core("player:1", 9.0, 2, VERIFIED).ok, "forced move closes core")
	var movement: Dictionary = state.get_state().movement
	state.approve_migration(movement.token, false)
	_run(state, 0.23)
	_check(not state.hit_core("player:1", 9.0, 2, VERIFIED).ok, "accepted shot sequence cannot replay after cooldown")
	_check(state.hit_core("player:1", 50.0, 3, VERIFIED).ok, "second phase can be damaged")
	_run(state, 0.23)
	var victory: Dictionary = state.hit_core("player:1", 50.0, 4, VERIFIED)
	_check(victory.ok and _has(victory.events, "boss_defeated") and state.get_state().completed, "single player defeats without rewards")
	var won: Dictionary = state.snapshot()
	_check(not state.hit_core("player:1", 9.0, 5, VERIFIED).ok and state.advance(5.0).ok and state.snapshot() == won, "victory event cannot repeat")
	var attacks = _new(true)
	attacks.set_player_position("player:1", Vector3(-3, 5, -6))
	var events: Array = _run(attacks, 3.0)
	var attack: Dictionary = attacks.get_state().attack
	_check(_has(events, "attack_telegraphed") and attack.shapes[0].kind == "annular_prism", "visible low annulus warning")
	_check(Crown.contains_shape(attack.shapes[0], Vector3(-3, 5, -6)), "annulus includes unsafe flight lane")
	_check(not Crown.contains_shape(attack.shapes[0], Vector3(-3, 11, -6)) and not Crown.contains_shape(attack.shapes[0], Vector3(-10, 5, -6)), "height and inner-circle routes avoid root wave")
	_check(not attacks.apply_attack_hit(attack.token, "player:1", VERIFIED).ok, "warning deals no damage")
	_run(attacks, 2.0)
	denied = VERIFIED.duplicate()
	denied.line_of_sight = false
	_check(not attacks.apply_attack_hit(attack.token, "player:1", denied).ok, "terrain occlusion flag prevents damage")
	_check(attacks.apply_attack_hit(attack.token, "player:1", VERIFIED).ok and attacks.get_state().players["player:1"].health == 76.0, "active shape damages confirmed player")
	_check(not attacks.apply_attack_hit(attack.token, "player:1", VERIFIED).ok, "one explosion cannot damage repeatedly every frame")
	attacks.set_player_position("player:2", Vector3(-3, 23, -6))
	_check(not attacks.apply_attack_hit(attack.token, "player:2", VERIFIED).ok, "high route avoids actual pure volume")
	_run(attacks, 1.2)
	_check(not attacks.apply_attack_hit(attack.token, "player:1", VERIFIED).ok, "expired token rejected")
	var both = _new()
	actors = _actors(both)
	_bind_current(both, actors)
	both.hit_core("player:1", 50.0, 1, VERIFIED)
	_run(both, 0.23)
	both.hit_core("player:1", 50.0, 2, VERIFIED)
	movement = both.get_state().movement
	both.approve_migration(movement.token, false)
	_run(both, 1.0)
	attack = both.get_state().attack
	_check(attack.get("shapes", []).size() == 2, "phase2 combines low and high shapes")
	for shape in attack.get("shapes", []):
		_check(not Crown.contains_shape(shape, Vector3(-10, 24, -3)), "phase2 permits leaving the warned height band")

func _test_all_hosts_scorched() -> void:
	var state = _new()
	for id in [WEST, HIGH, EAST]:
		var point: Array = state.get_state().anchors[id].target_position_mm
		state.set_player_position("player:1", Vector3(float(point[0]) / 1000.0, float(point[1]) / 1000.0 + 1.0, float(point[2]) / 1000.0))
		var actors: Dictionary = _actors(state)
		_check(_ability(state, actors, "heat", id).ok and _ability(state, actors, "heat", id).ok, "each host can be scorched by two paid heat intents")
	_check(state.get_state().hazards.size() == 3, "hazards bounded by three authored hosts")
	_approve(state)
	_run(state, 7.0)
	_check(state.get_state().mode == "unrooted" and state.get_state().core_open, "all hosts burnt leaves attackable fallback, no softlock")
	var unrooted_events: Array = _run(state, 3.0)
	_check(_has(unrooted_events, "attack_active") and not state.get_state().attack.is_empty(), "empty host search does not cancel fallback attacks before activation")
	_run(state, 10.0)
	for id in [WEST, HIGH, EAST]:
		_check(not state.get_state().anchors[id].burning and state.get_state().anchors[id].temperature == 20, "authored recovery restores scorched host")

func _test_roster_and_retry() -> void:
	var state = _new()
	var actors: Dictionary = _actors(state)
	_bind_current(state, actors)
	state.hit_core("player:1", 9.0, 1, VERIFIED)
	var before: Dictionary = state.get_state()
	_check(state.add_player("player:2", {"owner":"2", "position":Vector3(-9, 13, -3), "health":100.0, "max_health":100.0, "downed":false}).ok, "join ongoing fight")
	var joined: Dictionary = state.get_state()
	_check(joined.core_health == before.core_health and joined.phase == before.phase and joined.mode_until == before.mode_until and joined.attempt == before.attempt and joined.anchors == before.anchors, "join preserves boss phase health host state and attempt")
	_check(not state.add_player("player:3", {"owner":"3", "position":Vector3.ZERO, "health":100.0, "max_health":100.0, "downed":false}).ok, "third player rejected")
	state.down_player("player:2")
	_check(not state.revive_player("player:1", "player:2", 1.0, VERIFIED).ok, "revive hold must complete")
	_check(state.revive_player("player:1", "player:2", 2.5, VERIFIED).ok and state.get_state().players["player:2"].health == 40.0, "nearby cooperative rescue restores40percent")
	state.down_player("player:2")
	var wipe: Dictionary = state.remove_player("player:1")
	var reset_state: Dictionary = state.get_state()
	_check(wipe.ok and _has(wipe.events, "encounter_reset") and reset_state.attempt == 2 and reset_state.core_health == 160.0 and reset_state.phase == 1, "leave last healthy player triggers whole-attempt reset")
	_check(reset_state.players["player:2"].health == 100.0 and reset_state.players["player:2"].position_mm == reset_state.players["player:2"].entry_mm and reset_state.hazards.is_empty(), "wipe restores entrance health and transient environment")
	state.remove_player("player:2")
	var empty: Dictionary = state.snapshot()
	_check(state.advance(5.0).ok and state.snapshot() == empty and not state.get_state().completed, "empty encounter freezes and never rewards/completes")
	_check(state.add_player("player:1", {"owner":"1", "position":Vector3(-10, 13, -3), "health":100.0, "max_health":100.0, "downed":false}).ok and state.get_state().attempt == 2, "returning player does not restart attempt")
	var single = _new()
	var down: Dictionary = single.down_player("player:1")
	_check(_has(down.events, "encounter_reset") and single.get_state().attempt == 2, "single-player down retries whole encounter")

func _test_snapshot_and_replay() -> void:
	var a = _new()
	var actors: Dictionary = _actors(a)
	_ability(a, actors, "heat", WEST)
	_ability(a, actors, "heat", WEST)
	_approve(a)
	_run(a, 1.437)
	var saved: Dictionary = a.snapshot()
	var decoded = JSON.parse_string(JSON.stringify(saved, "", true, true))
	var b = Crown.new()
	_check(b.restore(decoded).ok and b.snapshot() == saved, "JSON roundtrip preserves exact integer timers positions and pending fraction")
	for delta in [0.063, 0.5, 1.0, 4.0, 5.0]:
		var ar: Dictionary = a.advance(delta)
		var br: Dictionary = b.advance(delta)
		_check(ar == br and a.snapshot() == b.snapshot(), "restored mid-flight state emits identical events and continues exactly")
	var invalid: Dictionary = saved.duplicate(true)
	invalid.state.position_mm[0] = 0.5
	var intact: Dictionary = b.snapshot()
	_check(not b.restore(invalid).ok and b.snapshot() == intact, "fractional corrupt mm rejected atomically")
	invalid = saved.duplicate(true)
	invalid.state.anchors[WEST].target_position_mm[0] += 1
	_check(not b.restore(invalid).ok, "authored anchor cannot move through save")
	invalid = saved.duplicate(true)
	invalid.state.players["player:1"].downed = true
	_check(not b.restore(invalid).ok, "health/downed mismatch rejected")
	invalid = saved.duplicate(true)
	invalid.state.movement.approved = false
	_check(not b.restore(invalid).ok, "moving save needs corridor approval")
	invalid = saved.duplicate(true)
	invalid.definition_fingerprint = "wrong"
	_check(not b.restore(invalid).ok, "wrong content definition rejected")
	var c = _new()
	var d = _new()
	c.advance(1.0)
	for i in range(10): d.advance(0.1)
	var cs: Dictionary = c.snapshot().state
	var ds: Dictionary = d.snapshot().state
	cs.erase("revision")
	ds.erase("revision")
	_check(cs == ds, "time chunking preserves mechanics; revision intentionally tracks API writes")
	var shot = _new()
	actors = _actors(shot)
	_bind_current(shot, actors)
	shot.hit_core("player:1", 9.0, 1, VERIFIED)
	var restored_shot = Crown.new()
	_check(restored_shot.restore(JSON.parse_string(JSON.stringify(shot.snapshot(), "", true, true))).ok, "accepted shot and cooldown survive JSON restore")
	_check(not restored_shot.hit_core("player:1", 9.0, 2, VERIFIED).ok, "restored shot cooldown cannot be bypassed")
	_run(restored_shot, 0.23)
	_check(not restored_shot.hit_core("player:1", 9.0, 1, VERIFIED).ok and restored_shot.hit_core("player:1", 9.0, 2, VERIFIED).ok, "restored accepted sequence deduplicates after cooldown")

func _test_interrupt_movement_and_rollback() -> void:
	var state = _new()
	var actors: Dictionary = _actors(state)
	_check(_ability(state, actors, "heat", WEST).ok and _ability(state, actors, "heat", WEST).ok, "interrupt fixture requests real heat ejection")
	var warning: Dictionary = state.snapshot()
	var warning_token: String = warning.state.movement.token
	_check(state.interrupt_movement(warning_token).ok and state.get_state().position_mm == warning.state.position_mm and state.get_state().mode == "unrooted", "warning can be interrupted before any motion")
	var restore_warning: Dictionary = state.restore(warning)
	_check(restore_warning.ok, "warning fixture restored without events: " + str(restore_warning.code))
	state.advance(1.0)
	_check(state.get_state().mode == "awaiting_route" and state.interrupt_movement(warning_token).ok, "awaiting approval can be interrupted safely")
	state.restore(warning)
	_approve(state)
	state.advance(2.937)
	var safe: Dictionary = state.snapshot()
	var token: String = safe.state.movement.token
	_check(safe.state.mode == "moving" and safe.state.tick == 29 and safe.state.pending_usec == 37000 and safe.state.position_mm != warning.state.position_mm, "rollback fixture is midflight one tick before arrival with fractional time")
	_check(not state.interrupt_movement(token, false).ok and state.snapshot() == safe, "client cannot stop host movement")
	_check(not state.interrupt_movement("old-token").ok and not state.interrupt_movement("").ok and state.snapshot() == safe, "wrong or empty movement tokens leave entire state unchanged")
	# Candidate events stay private until the adapter sweeps this exact candidate.
	var candidate: Dictionary = state.advance(0.1)
	_check(candidate.ok and _has(candidate.events, "movement_arrived") and _has(candidate.events, "core_opened") and state.get_state().mode == "fallen", "unsafe candidate genuinely crosses arrival and would open core")
	var restored: Dictionary = state.restore(safe)
	_check(restored.ok and restored.events.is_empty() and state.snapshot() == safe, "rollback restores counters and position without publishing candidate events")
	var blocked: Dictionary = state.interrupt_movement(token)
	var stopped: Dictionary = state.snapshot()
	var event: Dictionary = _event_of(blocked.events, "movement_blocked")
	_check(blocked.ok and blocked.code == "movement_interrupted" and event.get("token") == token and event.get("position_mm") == safe.state.position_mm and event.get("reason") == "dynamic_obstacle", "interruption reports the blocked token and last safe pose")
	_check(stopped.state.position_mm == safe.state.position_mm and stopped.state.movement.is_empty() and stopped.state.mode == "unrooted" and state.get_state().core_open, "moving interruption holds last swept-safe position and opens fallback")
	_check(stopped.state.tick == safe.state.tick and stopped.state.pending_usec == safe.state.pending_usec and stopped.state.mode_until == safe.state.tick + 30 and stopped.state.attack_due == safe.state.tick + 10, "interrupt consumes no time and schedules three-second window and one-second attack")
	_check(stopped.state.hazards == safe.state.hazards and stopped.state.revision == safe.state.revision + 1, "interruption preserves independent burning hazards and increments revision once")
	_check(not state.interrupt_movement(token).ok and state.snapshot() == stopped, "replayed interruption token cannot extend window or publish again")
	var replayed_step: Dictionary = state.advance(0.1)
	var committed: Array = blocked.events.duplicate(true)
	committed.append_array(replayed_step.events)
	var after: Dictionary = state.snapshot()
	_check(after.state.tick == 30 and after.state.pending_usec == 37000 and after.state.position_mm == safe.state.position_mm, "rollback plus replacement step advances wall simulation interval exactly once")
	_check(committed.size() == 1 and _has(committed, "movement_blocked") and not _has(committed, "movement_arrived") and not _has(committed, "core_opened") and after.state.serial == safe.state.serial + 1, "only accepted movement-blocked event survives candidate rollback")
	var clone = Crown.new()
	_check(clone.restore(JSON.parse_string(JSON.stringify(after))).ok and clone.snapshot() == after, "interrupted state roundtrips through JSON with exact clocks and event serial")
	var actual: Dictionary = state.advance(0.9)
	var replay: Dictionary = clone.advance(0.9)
	_check(actual == replay and state.snapshot() == clone.snapshot() and _has(actual.events, "attack_telegraphed"), "restored interruption resumes deterministic one-second counterattack")

func _test_independent_retry_entry() -> void:
	var state = Crown.new()
	var first: Dictionary = _body_state(Vector3(-9, 12, -2), 60.0, 120.0)
	first.owner = "1"
	first.entry_position = Vector3(-12, 11, 21)
	_check(state.start({"player:1":first}).ok, "start accepts separately authored retry entrance")
	var player: Dictionary = state.get_state().players["player:1"]
	_check(player.position_mm == [-9000, 12000, -2000] and player.health == 60.0 and player.entry_mm == [-12000, 11000, 21000], "half-health engagement preserves actual pose and health without teleporting to entry")
	var second: Dictionary = _body_state(Vector3(-8, 12, -2), 40.0, 80.0)
	second.owner = "2"
	second.entry_position = [-10.0, 11.0, 21.0]
	var before: Dictionary = state.snapshot()
	var invalid: Dictionary = second.duplicate(true)
	invalid.entry_position = Vector3(INF, 11, 21)
	_check(not state.add_player("player:2", invalid).ok and state.snapshot() == before, "nonfinite retry entry rejects join atomically")
	invalid.entry_position = [0, 1]
	var unstarted = Crown.new()
	_check(not unstarted.start({"player:2":invalid}).ok and unstarted.get_state().is_empty(), "malformed retry entry rejects start without encounter creation")
	_check(state.add_player("player:2", second).ok and state.get_state().players["player:2"].position_mm == [-8000, 12000, -2000] and state.get_state().players["player:2"].health == 40.0, "late join preserves actual half-health body separately from its retry slot")
	var sync: Dictionary = _body_state(Vector3(-6, 10, 0), 47.0, 120.0)
	sync.entry_position = Vector3.ZERO
	_check(state.sync_player_state("player:1", sync).ok and state.get_state().players["player:1"].entry_mm == [-12000, 11000, 21000], "ongoing body sync cannot overwrite independently assigned retry slot")
	var saved: Dictionary = state.snapshot()
	var clone = Crown.new()
	_check(clone.restore(JSON.parse_string(JSON.stringify(saved))).ok and clone.snapshot() == saved, "separate current and retry positions survive snapshot restoration")
	state.down_player("player:2")
	var wipe: Dictionary = state.down_player("player:1")
	var retried: Dictionary = state.get_state()
	_check(_has(wipe.events, "encounter_reset") and retried.players["player:1"].position_mm == [-12000, 11000, 21000] and retried.players["player:2"].position_mm == [-10000, 11000, 21000], "whole-team failure returns both players to distinct safe entries instead of engagement positions")
	_check(retried.players["player:1"].health == 120.0 and retried.players["player:2"].health == 80.0 and retried.attempt == 2, "independent entries retain established full-health whole-attempt retry rule")
	var legacy = _new()
	_check(legacy.get_state().players["player:1"].entry_mm == legacy.get_state().players["player:1"].position_mm, "omitted entry position keeps previous current-position default")

func _body_state(position: Vector3, health: float = 100.0, maximum: float = 100.0) -> Dictionary:
	return {"position":position, "health":health, "max_health":maximum, "downed":health == 0.0}

func _event_of(events: Array, kind: String) -> Dictionary:
	for event in events:
		if event.kind == kind: return event
	return {}

func _test_authored_spatial_roles() -> void:
	var source = _new()
	var definition: Dictionary = source.definitions()
	_check(source.get_state().boss_position == [-10.0, 13.0, -6.0] and definition.anchors[0].target_position == [-10.0, 11.0, -1.5], "default body unchanged while capability target is independently authored")
	# Deliberately separate the target by40m and change fall XYZ: this catches accidental body/target aliases and fixed Y6.
	definition.anchors[0].target_position = [-10, 13, 34]
	definition.anchors[0].fall_position = [-6, 8.75, -4]
	definition.anchors[0].fall_via_position = [-6, 10, -4]
	var state = Crown.new()
	_check(state.configure(definition).ok, "three independently authored positions accepted")
	var player: Dictionary = _body_state(Vector3(-10, 13, 35))
	player.owner = "1"
	_check(state.start({"player:1":player}).ok and state.get_state().position_mm == [-10000, 13000, -6000], "body uses exact authored position without extra offset")
	var actors: Dictionary = _actors(state)
	_check(_ability(state, actors, "heat", WEST).ok and _ability(state, actors, "heat", WEST).ok, "ability range follows exposed target even when body is far away")
	var movement: Dictionary = state.get_state().movement
	_check(movement.points_mm == [[-10000, 13000, -6000], [-10000, 15000, -6000], [-6000, 15000, -4000], [-6000, 8750, -4000]] and state.get_state().hazards[0].shapes[0].centre_xz_mm == [-10000, -6000], "fall first rises at source XZ, traverses independent via with source+2m clearance then reaches authored XYZ; hazard stays at host body XZ")
	_approve(state)
	_run(state, 3.0)
	_check(state.get_state().mode == "fallen" and state.get_state().position_mm == [-6000, 8750, -4000], "approved fall arrives at authored non6m support height")
	state.set_player_position("player:1", Vector3(-10, 13, -6))
	_check(not state.resolve_ability(_intent("light", WEST), _actors(state), VERIFIED).ok, "being near body cannot bypass far capability target range")
	var saved: Dictionary = state.snapshot()
	for point in ["target_position_mm", "body_position_mm", "fall_position_mm", "fall_via_position_mm"]:
		var corrupt: Dictionary = saved.duplicate(true)
		corrupt.state.anchors[WEST][point][0] += 1
		_check(not state.restore(corrupt).ok and state.snapshot() == saved, "snapshot cannot move authored " + point)
	var old_schema: Dictionary = saved.duplicate(true)
	old_schema.schema_version = 1
	_check(not state.restore(old_schema).ok and state.snapshot() == saved, "legacy ambiguous spatial snapshot rejected atomically")
	var invalid: Dictionary = definition.duplicate(true)
	invalid.anchors[0].erase("fall_position")
	var fresh = Crown.new()
	_check(not fresh.configure(invalid).ok and fresh.definitions().is_empty(), "missing independent fall point cannot silently default")
	invalid = definition.duplicate(true)
	invalid.anchors[0].target_position = [NAN, 1, 2]
	_check(not fresh.configure(invalid).ok and fresh.definitions().is_empty(), "nonfinite target definition rejected without partial configuration")
	invalid = definition.duplicate(true)
	invalid.anchors[0].erase("fall_via_position")
	_check(not fresh.configure(invalid).ok and fresh.definitions().is_empty(), "missing exit waypoint cannot silently fall vertically through host")
	invalid = definition.duplicate(true)
	invalid.anchors[0].fall_via_position[0] += 1
	_check(not fresh.configure(invalid).ok and fresh.definitions().is_empty(), "exit waypoint must be above the authored landing XZ for the separate descent segment")
	# A restored pose fixture may differ from the authored attachment center.
	# Clearance must use that current source, not the lower fixed body_position.
	var shifted = _new()
	var pose: Dictionary = shifted.snapshot()
	pose.state.position_mm[1] = 18000
	_check(shifted.restore(pose).ok, "valid restored body pose can differ from nominal attachment height")
	var shifted_actors: Dictionary = _actors(shifted)
	_ability(shifted, shifted_actors, "heat", WEST)
	_ability(shifted, shifted_actors, "heat", WEST)
	_check(shifted.get_state().movement.points_mm == [[-10000, 18000, -6000], [-10000, 20000, -6000], [-20000, 20000, 0], [-20000, 6000, 0]], "fall via clamps above actual changed source before off-platform descent")
	var high_exit = Crown.new()
	definition.anchors[0].fall_via_position = [-6, 24, -4]
	high_exit.configure(definition)
	high_exit.start({"player:1":player})
	var high_actors: Dictionary = _actors(high_exit)
	_ability(high_exit, high_actors, "heat", WEST)
	_ability(high_exit, high_actors, "heat", WEST)
	_check(high_exit.get_state().movement.points_mm[1] == [-10000, 24000, -6000] and high_exit.get_state().movement.points_mm[2] == [-6000, 24000, -4000], "authored higher exit waypoint is retained instead of lowered to source+2m")

func _test_real_player_state_sync() -> void:
	var state = Crown.new()
	var first: Dictionary = _body_state(Vector3(-10, 13, -3), 45.0, 120.0)
	first.owner = "1"
	_check(state.start({"player:1":first}).ok and state.get_state().players["player:1"].health == 45.0 and state.get_state().players["player:1"].max_health == 120.0, "start preserves real partial health and maximum")
	var second: Dictionary = _body_state(Vector3(-9, 13, -3), 35.0, 80.0)
	second.owner = "2"
	_check(state.add_player("player:2", second).ok and state.get_state().players["player:2"].health == 35.0, "late join preserves current health instead of free healing")
	var saved: Dictionary = state.snapshot()
	_check(state.sync_player_state("player:1", first).code == "unchanged" and state.snapshot() == saved, "unchanged body sampling emits nothing and preserves revision")
	_check(state.set_player_position("player:1", Vector3(-10, 13, -3)).code == "unchanged" and state.snapshot() == saved, "legacy same-position update also preserves revision")
	var damaged: Dictionary = _body_state(Vector3(-10, 13, -3), 25.0, 120.0)
	_check(not state.sync_player_state("player:1", damaged, false).ok and state.snapshot() == saved, "client cannot sync body health")
	for bad in [
		{"position":Vector3.ZERO, "health":NAN, "max_health":120.0, "downed":false},
		{"position":Vector3.ZERO, "health":121.0, "max_health":120.0, "downed":false},
		{"position":Vector3.ZERO, "health":25.0, "max_health":120.0, "downed":true},
		{"position":Vector3(INF, 0, 0), "health":25.0, "max_health":120.0, "downed":false}]:
		_check(not state.sync_player_state("player:1", bad).ok and state.snapshot() == saved, "invalid physical sample is rejected atomically")
	var actors: Dictionary = _actors(state)
	var pending: Dictionary = state.resolve_ability(_intent("light", WEST), actors, VERIFIED)
	state.sync_player_state("player:1", first)
	_check(state.commit_ability(pending, actors, true).ok and actors["player:1"].energy == 495.0, "unchanged body sample does not invalidate a legitimate pending ability")
	pending = state.resolve_ability(_intent("heat", WEST), actors, VERIFIED)
	_check(state.sync_player_state("player:1", damaged).ok and not state.commit_ability(pending, actors, true).ok and actors["player:1"].energy == 495.0, "changed health invalidates preview without spending energy")
	# Non-physical fields are not writable through the sampling API.
	var player_before: Dictionary = state.get_state().players["player:1"]
	damaged.owner = "2"
	damaged.entry_mm = [0, 0, 0]
	damaged.last_shot_sequence = 999
	damaged.position = Vector3(-9.5, 13, -3)
	state.sync_player_state("player:1", damaged)
	var player_after: Dictionary = state.get_state().players["player:1"]
	_check(player_after.owner == "1" and player_after.entry_mm == player_before.entry_mm and player_after.last_shot_sequence == player_before.last_shot_sequence, "body sampling cannot rewrite ownership retry entry or shot receipts")
	var down: Dictionary = state.sync_player_state("player:2", _body_state(Vector3(-9, 13, -3), 0.0, 80.0))
	_check(_has(down.events, "player_downed") and not _has(down.events, "encounter_reset"), "external collision down leaves living teammate in current attempt")
	var repeat: Dictionary = state.snapshot()
	_check(state.sync_player_state("player:2", _body_state(Vector3(-9, 13, -3), 0.0, 80.0)).code == "unchanged" and state.snapshot() == repeat, "repeated downed sample does not duplicate death events")
	var rescued: Dictionary = state.revive_player("player:1", "player:2", 2.5, VERIFIED)
	var rescue_event: Dictionary = _event_of(rescued.events, "player_revived")
	_check(rescued.ok and state.get_state().players["player:2"].health == 32.0 and rescue_event.get("health_milli") == 32000 and rescue_event.get("max_health_milli") == 80000 and not rescue_event.get("downed", true), "rescue emits actual40percent result for non100 maximum")
	var echo: Dictionary = state.snapshot()
	_check(state.sync_player_state("player:2", _body_state(Vector3(-9, 13, -3), 32.0, 80.0)).code == "unchanged" and state.snapshot() == echo, "body echo of applied rescue does not change encounter again")
	state.sync_player_state("player:2", _body_state(Vector3(-9, 13, -3), 0.0, 80.0))
	var wipe: Dictionary = state.sync_player_state("player:1", _body_state(Vector3(-9.5, 13, -3), 0.0, 120.0))
	_check(_has(wipe.events, "encounter_reset") and state.get_state().attempt == 2 and state.get_state().players["player:1"].health == 120.0 and state.get_state().players["player:2"].health == 80.0, "external fullwipe resets once and returns complete restored roster")
	var restored = Crown.new()
	_check(restored.restore(JSON.parse_string(JSON.stringify(state.snapshot()))).ok and restored.snapshot() == state.snapshot(), "new health and spatial schema preserves exact JSON restoration")
	var attacks = _new()
	attacks.sync_player_state("player:1", _body_state(Vector3(-3, 5, -6), 67.0))
	_run(attacks, 5.0)
	var attack: Dictionary = attacks.get_state().attack
	var hit: Dictionary = attacks.apply_attack_hit(attack.token, "player:1", VERIFIED)
	_check(hit.ok and attacks.get_state().players["player:1"].health == 43.0 and _event_of(hit.events, "player_hit").get("health_milli") == 43000, "boss damage uses previously collision-damaged health and exposes one result for body application")
	for identity in ["p1", "1", "player:01", "player:2"]:
		var invalid = Crown.new()
		_check(not invalid.start({identity:first}).ok and invalid.get_state().is_empty(), "roster rejects mixed or owner-mismatched player ID " + identity)
	var missing: Dictionary = first.duplicate(true)
	missing.erase("health")
	var unstarted = Crown.new()
	_check(not unstarted.start({"player:1":missing}).ok and unstarted.get_state().is_empty(), "omitted real health cannot silently create full-health player")
	var dead: Dictionary = _body_state(Vector3.ZERO, 0.0)
	dead.owner = "1"
	_check(not unstarted.start({"player:1":dead}).ok and unstarted.get_state().is_empty(), "all-downed initial roster rejected instead of creating invalid snapshot")
