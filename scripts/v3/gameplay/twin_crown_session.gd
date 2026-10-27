class_name TwinCrownSession
extends RefCounted
## Host adapter: physical approval precedes rules, presentation and durable events.
const Encounter = preload("res://scripts/v3/gameplay/twin_crown_encounter.gd")
const HOST_PREFIX = "F1:crown_host_"
const CORE = "boss:crown_core"
var session
var encounter = Encounter.new()
var shot_sequences: Dictionary = {}
var reset_serial = 0

func setup(owner_session) -> void:
	session = owner_session

func clear() -> void:
	encounter = Encounter.new()
	shot_sequences.clear()
	reset_serial = 0

func active() -> bool:
	return session.boss_active and session.region_id == "F1"

func arena():
	return session.world.crown_arena

func ready() -> bool:
	return is_instance_valid(arena()) and arena().imported

func _spec(peer: int, slot: int = 0) -> Dictionary:
	var body = session.players[peer]
	return {"position":arena().to_local(body.global_position), "entry_position":arena().to_local(arena().retry_position(slot)),
		"health":body.health, "max_health":body.maximum_health, "downed":not body.enabled, "owner":str(peer)}

func start(campaign: bool) -> bool:
	if not ready() or active() or session.pending_completion: return false
	var roster: Dictionary = {}
	var peers: Array = session.players.keys()
	peers.sort()
	for slot in range(peers.size()):
		var peer = int(peers[slot])
		if session.players[peer].enabled and arena().in_combat_space(session.players[peer].global_position):
			roster[session._actor_id(peer)] = _spec(peer, slot)
	var result: Dictionary = encounter.start(roster)
	if not result.ok: return false
	session.boss_campaign = campaign and "F1:crown:brief" in session.story.state.get("completed", [])
	session.boss_active = true
	_handle(result.events)
	sync_view()
	session._note_all("冠兽占据了支脉：照亮宿主后催生根系，或用热量逼它离开。留意不同高度的预警。")
	return true

func sync_players() -> bool:
	if not active() or not ready(): return false
	var before_reset = reset_serial
	var current: Dictionary = encounter.get_state().get("players", {})
	for id in current:
		var peer = int(str(id).trim_prefix("player:"))
		if not session.players.has(peer) or (session.players[peer].enabled and not arena().in_combat_space(session.players[peer].global_position)):
			_handle(encounter.remove_player(id).events)
			if reset_serial != before_reset: return false
	var peers: Array = session.players.keys()
	peers.sort()
	for slot in range(peers.size()):
		var peer = int(peers[slot])
		var id: String = session._actor_id(peer)
		var body = session.players[peer]
		current = encounter.get_state().get("players", {})
		if not current.has(id):
			if body.enabled and arena().in_combat_space(body.global_position): _handle(encounter.add_player(id, _spec(peer, slot)).events)
		else: _handle(encounter.sync_player_state(id, _spec(peer, slot)).events)
		# A whole-team reset has already replaced every physical sample.
		if reset_serial != before_reset: return false
	return true

func advance(delta: float) -> void:
	if not sync_players(): return
	var remaining = minf(delta, 0.25)
	while remaining > 0.000001 and active():
		var step = minf(remaining, 0.1)
		remaining -= step
		var before: Dictionary = encounter.snapshot()
		var result: Dictionary = encounter.advance(step)
		var after: Dictionary = encounter.get_state()
		if before.state.position_mm != after.position_mm:
			if not arena().motion_clear([before.state.position_mm, after.position_mm]):
				# Candidate events have not escaped this adapter. Roll back the entire
				# candidate, stop at the last safe pose, and advance this time once.
				encounter.restore(before)
				_handle(encounter.interrupt_movement(str(before.state.movement.get("token", ""))).events)
				result = encounter.advance(step)
		_handle(result.events)
		if not active(): return
		sync_view()
		_apply_attacks()
	sync_view()

func use_ability(peer: int, intent: Dictionary) -> void:
	if not active() or not sync_players(): return
	var id: String = session._actor_id(peer)
	var body = session.players[peer]
	var target: String = str(intent.target_id)
	var at: Vector3 = arena().host_position(target)
	var actor: Dictionary = session.entities[id].duplicate(true)
	actor.position = arena().to_local(body.global_position)
	var actors = {id:actor}
	var context = {"is_authority":true, "sender_id":str(peer), "line_of_sight":at.is_finite() and session._line_clear(body.global_position, at, body.get_rid(), target)}
	var transaction: Dictionary = encounter.resolve_ability(intent, actors, context)
	var result: Dictionary = encounter.commit_ability(transaction, actors, true) if transaction.get("ok", false) else transaction
	if not result.get("ok", false):
		session.stats.rejected_abilities += 1
		session._note(peer, {"roots_recovering":"宿主根系正在恢复，请改用其他宿主或热量", "unsupported_ability":"宿主可响应光、热和生长", "actor_missing":"进入北侧战区后才能操作冠兽宿主"}.get(str(result.get("code")), session.ERROR_TEXT.get(str(result.get("code")), str(result.get("code")))))
		return
	for key in ["energy", "revision"]: session.entities[id][key] = actors[id][key]
	session.stats.abilities += 1
	session.cooldowns[peer] = 0.35
	session._beam(body.global_position, at, Color("bccd7d"), 0.25)
	_handle(result.events)
	sync_view()

func fire(peer: int, damage: float = 9.0) -> bool:
	if not session.network.is_authority(): return false
	if not active() or not sync_players(): return false
	if str(session.locks.get(peer, "")) != CORE:
		session._shot_rejected(peer, "crown_target", "Tab 选择冠兽种核；宿主用光、热或生长操作。")
		return false
	var body = session.players[peer]
	var point: Vector3 = arena().core_position()
	if not point.is_finite(): return false
	if body.global_position.distance_to(point) > 36:
		session._shot_rejected(peer, "out_of_range", "射程 36m，请靠近冠兽种核。")
		return false
	if not session._line_clear(body.global_position, point, body.get_rid(), CORE):
		if not encounter.get_state().core_open:
			session._shot_rejected(peer, "crown_armored", "冠甲尚未张开，先操作宿主解除防护。")
		else:
			session._shot_rejected(peer, "occluded", "射线被挡住，换高度或绕到种核一侧。")
		return false
	shot_sequences[peer] = int(shot_sequences.get(peer, 0)) + 1
	var result: Dictionary = encounter.hit_core(session._actor_id(peer), damage, shot_sequences[peer],
		{"is_authority":true, "sender_id":str(peer), "line_of_sight":true, "hit_confirmed":true})
	if result.get("ok", false):
		session.stats.shots += 1
		session._audio_event("shot", body.global_position, str(peer))
		session._audio_event("hit", point, CORE)
		session._beam(body.global_position, point, Color("f4d497"))
		_handle(result.events)
		# Half-health closes the physical plates before another pilot fires.
		sync_view()
	else:
		session._shot_rejected(peer, str(result.get("code", "crown_armored")), "种核当前受保护，先操作宿主解除防护。")
	return bool(result.get("ok", false))

func down(peer: int) -> void:
	if not active(): return
	if not encounter.get_state().players.has(session._actor_id(peer)):
		session.call_deferred("_restore_player", peer, session.world.spawn_position)
		return
	_handle(encounter.down_player(session._actor_id(peer)).events)
	sync_view()

func leave(peer: int) -> void:
	if not active(): return
	_handle(encounter.remove_player(session._actor_id(peer)).events)
	sync_view()

func retry() -> void:
	if not active(): return
	_handle(encounter.reset().events)
	sync_view()

func revive(helper: int, target: int, held: float) -> bool:
	if not active() or not sync_players(): return false
	var body = session.players[helper]
	var result: Dictionary = encounter.revive_player(session._actor_id(helper), session._actor_id(target), held,
		{"is_authority":true, "sender_id":str(helper), "line_of_sight":session._line_clear(body.global_position, session.players[target].global_position, body.get_rid())})
	_handle(result.events)
	return result.ok

func _apply_attacks() -> void:
	var state: Dictionary = encounter.get_state()
	var attacks: Array = state.hazards.duplicate(true)
	if not state.attack.is_empty(): attacks.append(state.attack)
	var before_reset = reset_serial
	for attack in attacks:
		if not attack.fired: continue
		for id in state.players:
			var peer = int(str(id).trim_prefix("player:"))
			if not session.players.has(peer) or not session.players[peer].enabled: continue
			var body = session.players[peer]
			var inside = false
			for shape in attack.shapes:
				if Encounter.contains_shape(shape, arena().to_local(body.global_position)): inside = true
			if not inside or not arena().attack_line_clear(attack, body.global_position, body.get_rid()): continue
			var direction: Vector3 = (body.global_position - arena().attack_origin(attack)).normalized()
			var raw_damage = float(attack.damage_milli) / 1000.0
			var preview: Dictionary = body.preview_combat_hit(raw_damage, direction, body.global_position, "pulse")
			if preview.is_empty(): continue
			var hit: Dictionary = encounter.apply_attack_hit(str(attack.token), id, {"is_authority":true, "hit_confirmed":true, "line_of_sight":true,
				"resolved_damage_milli":int(round(float(preview.damage) * 1000.0))})
			if hit.ok: body.apply_combat_hit(raw_damage, direction, body.global_position, "pulse", {"source":"parasitic_crown"})
			_handle(hit.events)
			if reset_serial != before_reset or not active(): return

func _handle(events: Array) -> void:
	for event in events:
		match str(event.kind):
			"attack_telegraphed": session._audio_event("boss_warning", arena().global_position, str(event.attack.token))
			"attack_active": session._audio_event("boss_attack", arena().global_position, str(event.attack.token))
			"phase_changed": session._audio_event("boss_phase", arena().global_position, "crown")
			"movement_requested":
				var movement: Dictionary = encounter.get_state().movement
				_handle(encounter.approve_migration(str(movement.token), arena().motion_clear(movement.points_mm)).events)
			"movement_blocked": session._note_all("冠兽的迁移被阻挡，核心暂时暴露。")
			"core_opened": session._note_all("冠甲已张开，Tab 锁定种核后射击。")
			"player_hit": _apply_health(event)
			"player_revived":
				var peer = int(str(event.player_id).trim_prefix("player:"))
				if session.players.has(peer): session._restore_player(peer, session.players[peer].global_position)
				_apply_health(event)
			"encounter_reset":
				reset_serial += 1
				session.revive_time.clear()
				var roster: Dictionary = encounter.get_state().players
				for id in roster:
					var peer = int(str(id).trim_prefix("player:"))
					if session.players.has(peer): session._restore_player(peer, arena().to_global(arena().vector(roster[id].entry_mm) / 1000.0))
				session._note_all("冠兽整场已重置，已完成的探索和支脉修复保留。")
			"boss_defeated":
				session.pending_completion = true
				session._finish_boss()

func _apply_health(event: Dictionary) -> void:
	var peer = int(str(event.player_id).trim_prefix("player:"))
	if not session.players.has(peer): return
	var body = session.players[peer]
	body.health = float(event.health_milli) / 1000.0
	body.damage_state.health = body.health
	body.enabled = not bool(event.downed)
	var entity: Dictionary = session.entities[session._actor_id(peer)]
	entity.health = body.health
	entity.downed = not body.enabled

func presentation() -> Dictionary:
	if not active(): return {}
	var state: Dictionary = encounter.get_state()
	if state.is_empty(): return {}
	var anchors: Dictionary = {}
	for id in state.anchors:
		var host: Dictionary = state.anchors[id]
		anchors[id] = {"temperature":host.temperature, "lit":host.light_until > state.tick, "burning":host.burning,
			"growth":float(host.growth_percent) / 100.0, "recovering":host.root_ready_tick > state.tick}
	var attacks: Array = []
	var all_attacks: Array = state.hazards.duplicate(true)
	if not state.attack.is_empty(): all_attacks.append(state.attack)
	for attack in all_attacks:
		attacks.append({"token":attack.token, "kind":attack.kind, "shapes":attack.shapes, "active":attack.fired,
			"remaining":float((attack.end_tick if attack.fired else attack.fire_tick) - state.tick) * 0.1})
	return {"type":"parasitic_crown", "position":arena().vector(state.boss_position), "core_health":state.core_health,
		"core_open":state.core_open, "phase":state.phase, "mode":state.mode, "attempt":state.attempt,
		"anchors":anchors, "attacks":attacks}

func sync_view() -> void:
	if not active(): return
	var view = presentation()
	arena().apply_view(view)
	apply_entities(view)

func apply_entities(view: Dictionary) -> void:
	for id in session.entities.keys():
		if str(id).begins_with(HOST_PREFIX) or id == CORE: session.entities.erase(id)
	if view.is_empty() or not ready(): return
	for id in view.anchors:
		var host: Dictionary = view.anchors[id]
		session.entities[id] = {"id":id, "name":{"F1:crown_host_west":"西侧宿主", "F1:crown_host_high":"高冠宿主", "F1:crown_host_east":"东侧宿主"}.get(id, "宿主"),
			"position":arena().host_position(id), "tags":["photosensitive", "thermal", "growable"], "temperature":host.temperature,
			"light_level":1.0 if host.lit else 0.0, "burning":host.burning, "growth":host.growth, "recovering":host.recovering}
	session.entities[CORE] = {"id":CORE, "name":"冠兽 · 种核", "position":arena().core_position(), "tags":["enemy"], "open":view.core_open}
