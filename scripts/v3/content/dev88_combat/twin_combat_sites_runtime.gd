extends Node3D
## Optional, bounded native combat. Session owns the one physics tick, player
## weapons, original save barrier, pause and transport. No campaign/Boss edits.
const Catalog = preload("res://scripts/v3/content/dev88_combat/twin_combat_sites_catalog.gd")
const State = preload("res://scripts/v3/content/dev88_combat/twin_combat_sites_state.gd")
const View = preload("res://scripts/v3/content/dev88_combat/twin_combat_site_view.gd")
const Actor = preload("res://scripts/v3/content/dev88_combat/twin_combat_site_actor.gd")
const Payload = preload("res://scripts/v3/content/dev88_combat/twin_combat_site_payload.gd")
const Layout = preload("res://scripts/v3/campaign/twin_campaign_layout.gd")
const WeaponCycle = preload("res://scripts/v3/gameplay/twin_weapon_cycle.gd")
const MASK := 1 | 2 | 4 | 8 | 32
const PUBLISH_SECONDS := .1
var session
var enabled := true
var error := ""
var pilot: FlightBodyV2
var navigation_world: Node3D
var environment_query: Callable
var perception_visibility: Callable
var target_visibility: Callable
var combat_seed := 880026
var unit_sequence := 0
var difficulty := 0
var exposure_window_s := 4.0
var enemies: Array = []
var epoch := 0
var serial := 0
var _world: Node3D
var _spec: Dictionary = {}
var _phase := "idle"
var _bounds := AABB()
var _protected: Array[AABB] = []
var _units: Dictionary = {}
var _payload
var _wave := 0
var _entered := false
var _destroyed := 0
var _neutralized := 0
var _saved: Dictionary = State.empty()
var _bolts: Array = []
var _bullet_serial := 0
var _warning_serial := 0
var _warning_gap := 0.0
var _publish_clock := 0.0
var _last_frame := -1
var _last_edge := ""
var _last_reason := ""
var _sealed: Dictionary = {}
var _settlement_source: Node
var _settlement_target: Node
var _remote_session := ""
var _remote_epoch := -1
var _remote_serial := -1
var _required_epoch := 1
var _remote_view: Dictionary = {}
var _pending: Dictionary = {}
var _remote_bullets: Dictionary = {}
var _projection_ids: Dictionary = {}
var _remote_bullet_mesh: SphereMesh
var _enemy_material: Material
var _friendly_material: Material
var _cues: Node3D

func _ready() -> void:
	set_process(false)
	set_physics_process(false)

func setup(owner_session) -> void:
	session = owner_session

func bind_world() -> Dictionary:
	clear()
	if not enabled or Catalog.sites(str(session.region_id)).is_empty(): return _r(true, "combat_region_inactive")
	if not is_instance_valid(session.world) or not session.world.is_inside_tree(): return _r(false, "actual_combat_world_required")
	_world = session.world
	navigation_world = _world
	if _world.has_method("sample_environment"): environment_query = _world.sample_environment
	var saved: Variant = session.world_cache.get("world", {}).get("combat_sites_v1", State.empty())
	if not State.valid(saved): return _fault("combat_sites_saved_state_invalid")
	_saved = saved.duplicate(true)
	_build_protected()
	if session.network.is_authority():
		if epoch >= View.MAX_COUNTER: return _fault("combat_epoch_limit")
		epoch += 1
		serial = 0
		publish()
	else:
		_required_epoch = maxi(1, _remote_epoch + 1)
		_consume_pending()
	return _r(true, "combat_sites_bound_developed_not_playtested")

func clear() -> void:
	_teardown_attempt()
	_world = null
	navigation_world = null
	environment_query = Callable()
	_protected.clear()
	_spec.clear()
	_phase = "idle"
	_wave = 0
	_entered = false
	_last_frame = -1
	_publish_clock = 0.0
	_last_edge = ""
	_last_reason = ""
	_sealed.clear()
	_settlement_source = null
	_settlement_target = null
	error = ""

func reset_connection() -> void:
	clear()
	epoch = 0
	serial = 0
	unit_sequence = 0
	_bullet_serial = 0
	_warning_serial = 0
	_warning_gap = 0.0
	_remote_session = ""
	_remote_epoch = -1
	_remote_serial = -1
	_required_epoch = 1
	_remote_view.clear()
	_pending.clear()
	_saved = State.empty()

func active() -> bool:
	return enabled and not _spec.is_empty() and _phase in ["approach", "running", "ready"]

func completed(id: String) -> bool:
	return _saved.get("completed", {}).has(id)

func completion_serial(id: String) -> int:
	return int(_saved.get("completed", {}).get(id, {}).get("serial", 0))

func completed_sites() -> Array:
	var ids: Array = _saved.get("completed", {}).keys()
	ids.sort()
	return ids

func completed_rewards() -> Array:
	var result: Array = []
	for id: String in completed_sites(): result.append(str(_saved.completed[id].reward_id))
	return result

func journal_rows(region: String = "") -> Array:
	var result: Array = []
	for site: Dictionary in Catalog.sites(region):
		var running: bool = active() and str(_spec.id) == str(site.id)
		var mode: String = {"intercept":"分批截击", "escort":"实体服务机护送", "defend":"实体服务机防守"}.get(str(site.mode), "可选遭遇")
		result.append({"title":str(site.name), "status":"已完成" if completed(str(site.id)) else "进行中" if running else "未开始",
			"text":mode + " · 到站牌 G 启动，交接后保存。" + ("\n" + hint_text() if running else "\n正常射击、抽电停机、过热或接管均可应对；退出标线可撤回。"),
			"anchor":{"anchor_id":str(site.id), "region":str(site.region), "label":str(site.name) + " · G 联络", "position":site.terminal.duplicate()}})
	return result

func hint_text(_region: String = "") -> String:
	if not active(): return ""
	if _phase == "ready": return str(_spec.name) + " · 条件已成立，回站牌 G 交接并保存"
	if _phase == "approach": return str(_spec.name) + " · 进入标线再交战；站牌 G 可取消"
	var extra := ""
	if is_instance_valid(_payload):
		extra = " · 服务机 %d/64" % ceili(_payload.hp)
		if str(_spec.mode) == "escort": extra += " · 航点 %d/%d" % [mini(_payload.waypoint, _payload.points.size()), _payload.points.size()]
	return "%s · 威胁 %d/%d 批%s\n预警后闪避 / 抽电 / 过热停机 / 接管；退出标线可撤回" % [str(_spec.name), _wave, _spec.waves.size(), extra]

func interact(peer_id: int, id: String) -> bool:
	var site: Dictionary = Catalog.definition(id)
	if site.is_empty(): return false
	if not _host() or str(site.region) != str(session.region_id) or not session.players.has(peer_id): return true
	var body: Variant = session.players[peer_id]
	var at: Vector3 = Catalog.point(site.terminal)
	if not body.enabled or body.health <= 0.0 or body.global_position.distance_to(at) > 3.8 or not session._line_clear(body.global_position, at, body.get_rid()):
		session._note(peer_id, "靠近可选行动站牌，并从无遮挡的一侧联络。")
		return true
	if session.simulation_paused or session.boss_active or session.campaign.active() or not session.consensus.current_proposal().is_empty():
		session._note(peer_id, "当前先处理暂停、共识或Boss；可选行动站会保留。")
		return true
	if completed(id):
		_dialogue(peer_id, site, site.complete_lines)
		return true
	if active():
		if str(_spec.id) != id:
			session._note(peer_id, "先完成或退出当前可选行动，再启动另一处。")
		elif _phase == "ready": _claim(peer_id)
		else:
			_abandon("已撤回可选行动；原主线、玩家状态和已交接记录保持。")
		return true
	_start(peer_id, site)
	return true

func _start(peer_id: int, site: Dictionary) -> void:
	_teardown_attempt()
	_spec = site.duplicate(true)
	_bounds = Catalog.bounds(site)
	_wave = 0
	_entered = false
	_destroyed = 0
	_neutralized = 0
	_phase = "approach"
	error = ""
	_build_protected()
	if str(site.mode) in ["escort", "defend"]:
		_payload = Payload.new()
		_payload.name = "OptionalServiceDrone"
		_payload.combat = self
		_payload.authoritative = true
		_payload.mode = str(site.mode)
		_payload.set_meta("entity_id", str(session.region_id) + ":combat88:payload")
		_payload.position = Catalog.point(site.payload.position)
		for point: Array in site.payload.route: _payload.points.append(Catalog.point(point))
		_world.add_child(_payload)
		if not is_instance_valid(_payload.model) or motion_fraction(_payload, _payload.global_position, Vector3.ZERO) < .999:
			_fail_attempt("服务机起点被实体占用；让开起点后可从站牌重试。", "payload_spawn_occupied")
			return
		_payload.waypoint = 1 if _payload.points.size() > 1 else 0
		_label_payload()
	if not _spawn_wave(0): return
	_build_route_cues()
	_bump()
	_dialogue(peer_id, site, site.intro_lines)
	session._note_all(str(site.name) + " · 已启动可选行动，进入标线后交战")
	publish()

func _claim(peer_id: int) -> void:
	if _phase != "ready" or _spec.is_empty() or completed(str(_spec.id)): return
	var health: int = int(round(float(_payload.hp) * 1000.0)) if is_instance_valid(_payload) else 0
	var prepared: Dictionary = State.prepare(_saved, _spec, _destroyed, _neutralized, health)
	if not prepared.get("ok", false):
		session._note(peer_id, "行动回执无法整理，原记录已保留；尚未发放奖励。")
		return
	if not session._commit("combat88:" + str(_spec.id), {"world.combat_sites_v1":prepared.state}, str(_spec.reward_id)):
		session._note(peer_id, "这次交接尚未写入，服务机和完成条件保留；可再次 G 交接。")
		return
	_saved = prepared.state.duplicate(true)
	_phase = "completed"
	_clear_bolts()
	_bump()
	_dialogue(peer_id, _spec, _spec.complete_lines)
	session._audio_event("task_complete", Catalog.point(_spec.terminal), str(_spec.id))
	session._note_all(str(_spec.complete_title) + " · 发现与交接已保存")
	publish()

func advance(delta: float) -> Dictionary:
	if not _host() or not is_instance_valid(_world): return _r(true, "combat_host_inactive")
	if not is_finite(delta) or delta <= 0.0 or delta > minf(.1, 1.0 / float(Engine.physics_ticks_per_second) + .000001): return _fault("ordinary_combat_physics_delta_required")
	if _last_frame == Engine.get_physics_frames(): return _fault("duplicate_combat_physics_tick")
	_last_frame = Engine.get_physics_frames()
	if not active(): return _r(true, "no_active_combat_site")
	var reason: String = _ceasefire_reason()
	if reason != "none":
		_suspend(reason)
		return _r(true, "combat_ceasefire_" + reason)
	var live: Array = _live_players()
	if live.is_empty():
		_fail_attempt("行动已中止；按原救援/重试恢复机体后可回站牌再来。", "all_pilots_disabled")
		return _r(true, "combat_pilots_disabled")
	pilot = live[0]
	var present_player := false
	var entered_player := false
	for body: Variant in live:
		if _bounds.grow(4.0).has_point(body.global_position): present_player = true
		if _bounds.has_point(body.global_position) and not _protected_point(body.global_position, _body_half(body)): entered_player = true
	if not _entered and not entered_player:
		_suspend("approach")
		return _r(true, "approach_waits_for_real_pilot")
	_entered = true
	if not present_player:
		_abandon("已离开可选行动标线，安全撤回；原主线和已保存记录保持。")
		return _r(true, "combat_safe_exit")
	if _phase == "ready":
		_suspend("none")
		return _r(true, "combat_ready_for_native_save_handoff")
	_phase = "running"
	_last_reason = "none"
	_warning_gap = maxf(0.0, _warning_gap - delta)
	for id: String in _units.keys():
		var actor: Variant = _units[id].actor
		if not is_instance_valid(actor) or actor.dying or actor.neutralized: continue
		var state: Dictionary = session.entities.get(id, {})
		_units[id]["ability_state"] = {"charge":float(state.get("charge", 70.0)), "temperature":float(state.get("temperature", 20.0)), "pinned":bool(state.get("pinned", false))}
		if float(state.get("charge", 70.0)) <= 0.0 or float(state.get("temperature", 20.0)) >= 70.0:
			actor.stop_by_ability()
			continue
		var controlled_now: bool = bool(state.get("controlled", false))
		if controlled_now != actor.controlled:
			actor.controlled = controlled_now
			actor.cancel_warning()
			actor.brain.ceasefire()
		for player: Variant in live:
			var player_state: Dictionary = session.entities.get(session._actor_id(_peer(player)), {})
			if float(player_state.get("decoy_remaining", 0.0)) > 0.0 and player_state.get("decoy_position") is Vector3:
				actor.brain.hear_noise(player_state.decoy_position, .8)
		actor.host_tick(delta, "pinned" if bool(state.get("pinned", false)) else "none")
	_advance_bolts(delta)
	if _phase == "failed":
		_bump()
		publish()
		return _r(true, "combat_payload_disabled")
	_sync_entities()
	if is_instance_valid(_payload):
		var hold: bool = _wave_live() > 0
		_payload.host_tick(delta, hold)
	if _wave_live() == 0:
		if _wave < _spec.waves.size():
			var next: Dictionary = _spec.waves[_wave]
			if not is_instance_valid(_payload) or str(_spec.mode) != "escort" or int(_payload.waypoint) > int(next.get("escort_waypoint", 0)):
				if not _spawn_wave(_wave): return _r(false, "combat_next_spawn_blocked")
		elif not is_instance_valid(_payload) or str(_spec.mode) == "defend" or _payload.arrived:
			_phase = "ready"
			_clear_bolts()
			session._note_all(str(_spec.name) + " · 条件已成立，回站牌 G 交接")
	_sync_entities()
	_bump()
	_publish_clock += delta
	var edge: String = _edge_key()
	if edge != _last_edge or _publish_clock >= PUBLISH_SECONDS:
		_last_edge = edge
		_publish_clock = 0.0
		publish()
	return _r(true, "native_optional_combat_tick")

func _spawn_wave(index: int) -> bool:
	if _spec.is_empty() or index < 0 or index >= _spec.waves.size(): return false
	_clear_units()
	_clear_bolts()
	var wave: Dictionary = _spec.waves[index]
	if wave.units.size() > View.MAX_UNITS: return false
	for row: Dictionary in wave.units:
		unit_sequence += 1
		var id := str(session.region_id) + ":combat88:unit:" + str(unit_sequence)
		var actor = Actor.new()
		actor.name = "CombatSiteUnit" + str(unit_sequence)
		actor.role = str(row.role)
		actor.combat = self
		actor.authoritative = true
		actor.set_meta("entity_id", id)
		actor.set_meta("unit_id", id)
		actor.position = Catalog.point(row.position)
		var facing: Vector3 = Catalog.point(row.patrol_to) - actor.position
		actor.rotation.y = atan2(-facing.x, -facing.z)
		_world.add_child(actor)
		var spawn_ok: bool = is_instance_valid(actor.model) and _spawn_clear(actor)
		if not spawn_ok:
			# These are alternatives for a fresh factory spawn only. No live actor
			# is moved between points after it has entered the native simulation.
			for alternative: Array in row.get("spawn_alternates", []):
				actor.position = Catalog.point(alternative)
				actor.force_update_transform()
				if _spawn_clear(actor): spawn_ok = true; break
		if not spawn_ok:
			actor.free()
			_fail_attempt("航线起点被实体占用；让开标线后回站牌重试，尚未发放奖励。", "enemy_spawn_occupied")
			return false
		actor.brain.set_patrol_target(Catalog.point(row.patrol_to))
		_units[id] = {"actor":actor, "counted":false}
		enemies.append(actor)
	_wave = index + 1
	_sync_entities()
	return true

func _spawn_clear(body: CharacterBody3D) -> bool:
	for player: Variant in _live_players():
		if player.global_position.distance_to(body.global_position) < 5.0: return false
	return motion_fraction(body, body.global_position, Vector3.ZERO) >= .999

func _wave_live() -> int:
	var count := 0
	for row: Dictionary in _units.values():
		if is_instance_valid(row.actor) and not row.actor.dying and not row.actor.neutralized and row.actor.hp > 0.0: count += 1
	return count

func _claimable_actor(target: Variant) -> bool:
	return is_instance_valid(target) and target in enemies and not target.dying and not target.neutralized and target.hp > 0.0

func candidate_targets(attacker: CharacterBody3D) -> Array:
	var result: Array = []
	if attacker.controlled:
		for other: Variant in enemies:
			if may_attack(attacker, other): result.append(other)
	else:
		for body: Variant in _live_players():
			if may_attack(attacker, body): result.append(body)
		if is_instance_valid(_payload) and may_attack(attacker, _payload): result.append(_payload)
	return result

func candidate_players() -> Array:
	var result: Array = []
	for body: Variant in _live_players():
		if may_target(body): result.append(body)
	return result

func may_target(body: Variant) -> bool:
	return body in _live_players() and bool(body.command.get("active", true)) and _ceasefire_reason() == "none" and _bounds.has_point(body.global_position) and not _protected_point(body.global_position, _body_half(body))

func may_attack(attacker: Variant, target: Variant) -> bool:
	if not _claimable_actor(attacker) or not is_instance_valid(target) or _ceasefire_reason() != "none" or _protected_point(attacker.global_position, attacker.dimensions * .5): return false
	if attacker.controlled: return target != attacker and _claimable_actor(target) and not target.controlled
	if target == _payload: return is_instance_valid(_payload) and not _payload.dying and _payload.hp > 0.0 and _bounds.has_point(_payload.global_position)
	return may_target(target)

func flight_bounds() -> AABB:
	return _bounds

func allowed_goal(point: Vector3, from: Vector3) -> Vector3:
	return from if _protected_point(point, Vector3.ONE) else point

func motion_fraction(body: CharacterBody3D, from: Vector3, motion: Vector3) -> float:
	if not is_instance_valid(_world) or not is_instance_valid(body) or not body.is_inside_tree() or not from.is_finite() or not motion.is_finite(): return 0.0
	var fraction := 1.0
	var found := false
	for child: Node in body.get_children():
		if not child is CollisionShape3D or child.disabled: continue
		if not child.shape is BoxShape3D: return 0.0
		found = true
		var query := PhysicsShapeQueryParameters3D.new()
		query.shape = child.shape
		query.transform = child.global_transform
		query.transform.origin += from - body.global_position
		var start: AABB = query.transform * AABB(-child.shape.size * .5, child.shape.size)
		var finish: AABB = start
		finish.position += motion
		var swept: AABB = start.merge(finish)
		if not _bounds.encloses(swept): return 0.0
		for protected: AABB in _protected:
			if protected.intersects(swept): return 0.0
		query.collision_mask = MASK
		query.exclude = [body.get_rid()]
		var space: PhysicsDirectSpaceState3D = _world.get_world_3d().direct_space_state
		if not space.intersect_shape(query, 1).is_empty(): return 0.0
		if motion.length() < .000001: continue
		query.motion = motion
		var cast: PackedFloat32Array = space.cast_motion(query)
		if cast.size() != 2: return 0.0
		fraction = minf(fraction, float(cast[0]))
	return fraction if found else 0.0

func line_clear(from: Vector3, to: Vector3, source: RID, target: RID) -> bool:
	var hit: Dictionary = _ray(from, to, source)
	return not hit.is_empty() and hit.get("rid") == target

func projectile_path_clear(from: Vector3, to: Vector3, source: RID, target: RID) -> bool:
	var hit: Dictionary = _ray(from, to, source)
	return hit.is_empty() or hit.get("rid") == target

func _ray(from: Vector3, to: Vector3, source: RID) -> Dictionary:
	if not is_instance_valid(_world) or not from.is_finite() or not to.is_finite(): return {}
	return _world.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(from, to, MASK, [source]))

func owns_projection(id: String) -> bool:
	return _projection_ids.has(id) or _units.has(id) or id == str(session.region_id) + ":combat88:payload" and is_instance_valid(_payload)

func owns_target(id: String) -> bool:
	if not enabled or not _units.has(id): return false
	var body: Variant = _units[id].actor
	return _claimable_actor(body)

func weapon_context(peer: int) -> Dictionary:
	var id: String = str(session.locks.get(peer, ""))
	var result := {"is_authority":session.network.is_authority(), "held_fire":false, "enabled":false, "paused":bool(session.simulation_paused), "target_id":id, "target_valid":false, "line_of_sight":false, "part_open":false}
	if not session.players.has(peer): return result
	var player: Variant = session.players[peer]
	result.held_fire = bool(player.command.get("fire", false))
	result.enabled = bool(player.enabled)
	var live: bool = owns_target(id) and may_target(player)
	if live:
		var actor: Variant = _units[id].actor
		live = not actor.controlled and player.global_position.distance_to(actor.global_position) <= 36.0
		result.line_of_sight = live and line_clear(player.global_position, actor.global_position, player.get_rid(), actor.get_rid())
	result.target_valid = live
	result.part_open = live
	return result

func fire_player(peer: int, amount: float) -> bool:
	if not _host() or not session.players.has(peer): return false
	var context: Dictionary = weapon_context(peer)
	if not context.target_valid or not context.line_of_sight or session.simulation_paused: return false
	var profile: Dictionary = WeaponCycle.weapon_profile(session.players[peer].build)
	if not profile.get("ok", false) or not is_finite(amount) or amount != float(profile.profile.damage): return false
	var actor: Variant = _units[str(context.target_id)].actor
	var body: Variant = session.players[peer]
	var hit: Dictionary = _ray(body.global_position, actor.global_position, body.get_rid())
	if hit.get("rid") != actor.get_rid(): return false
	session.stats.shots += 1
	session._audio_event("shot", body.global_position, str(peer))
	session._beam(body.global_position, hit.position, Color("f4d497"))
	var receipt: Dictionary = _settle_native(body, actor, hit.position, (actor.global_position - body.global_position).normalized(), amount, "pulse", 0)
	if not receipt.is_empty():
		_bump()
		publish()
	return not receipt.is_empty()

func request_warning(attacker: CharacterBody3D, target: CollisionObject3D) -> int:
	if not _host() or _warning_gap > 0.0 or _warning_serial >= View.MAX_COUNTER or not may_attack(attacker, target): return 0
	for other: Variant in enemies:
		if is_instance_valid(other) and other != attacker and other.telegraph > 0.0: return 0
	if not line_clear(attacker.global_position, target.global_position, attacker.get_rid(), target.get_rid()): return 0
	_warning_gap = .65
	_warning_serial += 1
	session._audio_event("boss_warning", attacker.global_position, str(attacker.get_meta("entity_id", "")))
	return _warning_serial

func fire_bolt(from: Vector3, to: Vector3, amount: float, friendly: bool, source: CollisionObject3D) -> bool:
	if not _host() or _ceasefire_reason() != "none" or not _claimable_actor(source) or source.controlled != friendly or amount != 7.0 or _bolts.size() >= View.MAX_BOLTS or _bullet_serial >= View.MAX_COUNTER or not from.is_finite() or not to.is_finite() or from.distance_squared_to(to) < .0001: return false
	var visual: MeshInstance3D = _bolt_visual(friendly)
	_world.add_child(visual)
	visual.global_position = from
	visual.scale = Vector3(.45, .45, 2.6)
	var direction: Vector3 = (to - from).normalized()
	if absf(direction.dot(Vector3.UP)) < .99: visual.look_at(from + direction, Vector3.UP)
	_bullet_serial += 1
	_bolts.append({"id":_bullet_serial, "position":from, "direction":direction, "remaining":3.0,
		"source":source.get_rid(), "source_ref":weakref(source), "warning_id":int(source.warning_id), "friendly":friendly, "amount":amount, "visual":visual})
	session._audio_event("shot", from, str(source.get_meta("entity_id", "")))
	return true

func _advance_bolts(delta: float) -> void:
	for index in range(_bolts.size() - 1, -1, -1):
		var row: Dictionary = _bolts[index]
		row.remaining -= delta
		var source: Variant = row.source_ref.get_ref()
		if row.remaining <= 0.0 or not _claimable_actor(source) or bool(source.controlled) != bool(row.friendly):
			_retire_bolt(index)
			continue
		var from: Vector3 = row.position
		var to: Vector3 = from + Vector3(row.direction) * 18.0 * delta
		if not _bounds.grow(.5).has_point(to) or _protected_point(to, Vector3.ZERO):
			_retire_bolt(index)
			continue
		var hit: Dictionary = _ray(from, to, row.source)
		if not hit.is_empty():
			var target: Variant = hit.get("collider")
			if may_attack(source, target): _settle_native(source, target, hit.position, row.direction, float(row.amount), "kinetic", int(row.warning_id))
			if _phase in ["failed", "blocked"]: return # Failure already retired every owned bolt.
			_retire_bolt(index)
		else:
			row.position = to
			row.visual.global_position = to

func settle_hit(source: Node, target: Node, point: Vector3, direction: Vector3, amount: float, weapon_type = "pulse", warning_id = 0) -> Dictionary:
	if not _host() or source != _settlement_source or target != _settlement_target or not is_instance_valid(target) or _ceasefire_reason() != "none": return {}
	if target in enemies:
		if not _claimable_actor(target): return {}
		if source in _live_players():
			if not may_target(source) or target.controlled: return {}
		elif not may_attack(source, target): return {}
	elif not may_attack(source, target): return {}
	var receipt: Dictionary = target.apply_combat_hit(amount, direction, point, weapon_type, {"source":"combat_sites88", "warning_id":warning_id})
	if receipt.is_empty(): return {}
	if target in enemies:
		target.brain.note_damage(source.global_position)
		if float(receipt.get("damage", 0.0)) > 0.0: session._audio_event("hit", point, str(target.get_meta("entity_id", "")))
		if receipt.get("killed", false): target.finish_destroyed(source, receipt)
	return receipt

func _settle_native(source: Node, target: Node, point: Vector3, direction: Vector3, amount: float, weapon_type: String, warning_id: int) -> Dictionary:
	if _settlement_target != null: return {}
	_settlement_source = source
	_settlement_target = target
	var receipt: Dictionary = settle_hit(source, target, point, direction, amount, weapon_type, warning_id)
	_settlement_source = null
	_settlement_target = null
	return receipt

func settlement_active_for(target: Node) -> bool:
	return target == _settlement_target and is_instance_valid(_settlement_source)

func actor_disabled(actor: Node, _source: Node, _receipt: Dictionary, by_ability: bool) -> void:
	var id: String = str(actor.get_meta("entity_id", ""))
	if not _units.has(id) or _units[id].counted: return
	_units[id].counted = true
	if by_ability: _neutralized += 1
	else: _destroyed += 1
	session.entities.erase(id)
	session._audio_event("interaction" if by_ability else "boss_defeated", actor.global_position, id)
	if by_ability: session._note_all("威胁已停机 · 电荷抽空或温度达到停机范围")

func payload_disabled() -> void:
	_fail_attempt("服务机已停机；按原救援恢复机体后，回站牌 G 可重试。主线和已保存记录保持。", "optional_service_drone_disabled")

func note_repair(_source: Node, target: Node, healed: float) -> void:
	if healed > 0.0: session._audio_event("interaction", target.global_position, "combat88_repair")

func _sync_entities() -> void:
	for id: String in _units:
		var actor: Variant = _units[id].actor
		if not _claimable_actor(actor):
			session.entities.erase(id)
			continue
		var state: Dictionary = session.entities.get(id, {"id":id, "name":_role_label(str(actor.role)),
			"tags":["enemy", "mechanical", "hackable", "conductive", "electrical", "thermal", "fieldable"],
			"revision":0, "owner":"enemy", "charge":70.0, "charge_capacity":100.0, "powered":true,
			"temperature":20.0, "health":float(actor.hp)})
		state.position = actor.global_position
		state.angle = float(actor.rotation.y)
		state.health = float(actor.hp)
		state.revision = maxi(int(state.get("revision", 0)), serial)
		session.entities[id] = state
	# Payload is intentionally not a generic mechanism/weapon lock target.

func _build_protected() -> void:
	_protected.clear()
	var layout: Dictionary = Layout.definition(str(session.region_id))
	for solid: Dictionary in layout.get("solids", []):
		if solid.id != "SouthLanding": continue
		var c: Vector3 = Catalog.point(solid.position)
		var size: Vector3 = Catalog.point(solid.size)
		_protected.append(AABB(Vector3(c.x-size.x*.5-1.0, -1.0, c.z-size.z*.5-1.0), Vector3(size.x+2.0, 28.0, size.z+2.0)))
	var arena: Dictionary = layout.get("boss_arena", {})
	if not arena.is_empty():
		var centre: Vector3 = Catalog.point(arena.centre)
		var half: Vector3 = Catalog.point(arena.half_extents)
		_protected.append(AABB(Vector3(centre.x-half.x-1.0, -1.0, centre.z-half.z-1.0), Vector3(half.x*2.0+2.0, 28.0, half.z*2.0+2.0)))
	for id: String in session.story.markers:
		var marker: Dictionary = session.story.markers[id]
		if marker.get("region") != session.region_id or marker.get("combat_site", false) or marker.get("kind") == "navigation": continue
		var at: Vector3 = session.story._point(marker)
		if not at.is_finite(): continue
		var radius: float = maxf(3.0, minf(4.5, float(marker.get("radius", 3.0))))
		_protected.append(AABB(at-Vector3.ONE*radius, Vector3.ONE*radius*2.0))
	if not _spec.is_empty():
		var at: Vector3 = Catalog.point(_spec.terminal)
		_protected.append(AABB(at-Vector3(3.8, 3.0, 3.8), Vector3(7.6, 6.0, 7.6)))

func _protected_point(point: Vector3, half: Vector3) -> bool:
	for box: AABB in _protected:
		if AABB(box.position-half, box.size+half*2.0).has_point(point): return true
	return false

func _body_half(body: Variant) -> Vector3:
	return Vector3(float(body.stats.width_m), float(body.stats.height_m), float(body.stats.length_m)) * .5

func _live_players() -> Array:
	var result: Array = []
	if session == null or not is_instance_valid(_world): return result
	var peers: Array = session.players.keys()
	peers.sort()
	for peer: Variant in peers:
		var body: Variant = session.players[peer]
		if body is FlightBodyV2 and is_instance_valid(body) and body.is_inside_tree() and body.enabled and body.health > 0.0 and body.get_world_3d().space == _world.get_world_3d().space: result.append(body)
	return result

func _ceasefire_reason() -> String:
	if not error.is_empty(): return "fault"
	if session.simulation_paused: return "pause"
	if not session.active: return "no_active_pilots"
	if session.boss_active or session.campaign.active(): return "boss"
	if session.interface.radio.visible: return "radio"
	if session.interface.menu.visible or session.interface.hangar.visible: return "menu"
	var journal: Variant = session.interface.get("journal")
	if is_instance_valid(journal) and journal.visible: return "journal"
	if session.interface.wheel.visible: return "wheel"
	if session.interface.travel.visible: return "travel"
	if session.interface.chapter_choice.visible: return "choice"
	if session.interface.vote.visible or not session.consensus.current_proposal().is_empty(): return "vote"
	return "none"

func _suspend(reason: String) -> void:
	var changed: bool = _last_reason != reason or not _bolts.is_empty()
	_last_reason = reason
	_clear_bolts()
	for actor: Variant in enemies:
		if not is_instance_valid(actor): continue
		if actor.telegraph > 0.0: changed = true
		actor.cancel_warning()
		actor.velocity = Vector3.ZERO
		actor.ceasefire_reason = reason
		actor.brain.ceasefire()
	if is_instance_valid(_payload): _payload.velocity = Vector3.ZERO
	if changed:
		_bump()
		publish()

func _abandon(message: String) -> void:
	_teardown_attempt()
	_spec.clear()
	_phase = "idle"
	_wave = 0
	_entered = false
	_bump()
	session._note_all(message)
	publish()

func _fail_attempt(message: String, code: String) -> void:
	_phase = "blocked" if code in ["enemy_spawn_occupied", "payload_spawn_occupied"] else "failed"
	# This is a retry state, not a save or a terminal runtime fault.
	_clear_bolts()
	for actor: Variant in enemies:
		if not is_instance_valid(actor): continue
		actor.cancel_warning()
		actor.velocity = Vector3.ZERO
		actor.neutralized = true # Transient failed attempt, never counted as a completion.
		actor.collision_layer = 0
		actor.collision_mask = 0
		actor.visible = false
		session.entities.erase(str(actor.get_meta("entity_id", "")))
	if is_instance_valid(_payload):
		_payload.velocity = Vector3.ZERO
		_payload.collision_layer = 0
		_payload.collision_mask = 0
	_bump()
	session._note_all(message)
	publish()

func _clear_units() -> void:
	for id: String in _units:
		if session != null: session.entities.erase(id)
		var body: Variant = _units[id].actor
		if is_instance_valid(body): body.free()
	_units.clear()
	enemies.clear()

func _teardown_attempt() -> void:
	_clear_bolts()
	_clear_units()
	if is_instance_valid(_payload): _payload.free()
	_payload = null
	if is_instance_valid(_cues): _cues.free()
	_cues = null
	for id: String in _projection_ids:
		if session != null: session.entities.erase(id)
	_projection_ids.clear()
	for visual: Variant in _remote_bullets.values():
		if is_instance_valid(visual): visual.free()
	_remote_bullets.clear()
	_remote_bullet_mesh = null
	_enemy_material = null
	_friendly_material = null
	pilot = null

func _retire_bolt(index: int) -> void:
	var visual: Variant = _bolts[index].visual
	if is_instance_valid(visual): visual.free()
	_bolts.remove_at(index)

func _clear_bolts() -> void:
	for row: Dictionary in _bolts:
		if is_instance_valid(row.visual): row.visual.free()
	_bolts.clear()

func _label_payload() -> void:
	if not is_instance_valid(_payload): return
	var label := Label3D.new()
	label.name = "ServiceDroneLabel"
	label.font = load("res://assets/fonts/NotoSansSC-Medium.ttf")
	label.font_size = 18
	label.pixel_size = .022
	label.outline_size = 3
	label.position.y = 1.0
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.text = str(_spec.payload.label)
	_payload.add_child(label)

func _build_route_cues() -> void:
	if is_instance_valid(_cues): _cues.free()
	_cues = Node3D.new()
	_cues.name = "OptionalCombatFlightCues"
	_cues.set_meta("navigation_only", true)
	_world.add_child(_cues)
	var material := StandardMaterial3D.new()
	material.albedo_color = Color("d1b878")
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	var low: Vector3 = _bounds.position
	var high: Vector3 = _bounds.end
	var elevation: float = low.y + .15
	for z: float in [low.z, high.z]:
		_cue_box(Vector3((low.x+high.x)*.5, elevation, z), Vector3(high.x-low.x, .035, .09), material)
	for x: float in [low.x, high.x]:
		_cue_box(Vector3(x, elevation, (low.z+high.z)*.5), Vector3(.09, .035, high.z-low.z), material)
	if str(_spec.mode) == "escort":
		for point: Array in _spec.payload.route:
			var marker := MeshInstance3D.new()
			var ring := TorusMesh.new()
			ring.inner_radius = .72
			ring.outer_radius = .86
			ring.rings = 12
			ring.ring_segments = 4
			marker.mesh = ring
			marker.position = Catalog.point(point)-Vector3.UP*1.1
			marker.material_override = material
			marker.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			_cues.add_child(marker)
	var label := Label3D.new()
	label.name = "SafeExitLabel"
	label.font = load("res://assets/fonts/NotoSansSC-Medium.ttf")
	label.text = "可选战区 · 黄线外停火\n回站牌 G 撤回 / 条件成立后交接"
	label.position = Catalog.point(_spec.terminal)+Vector3.UP*1.7
	label.font_size = 17
	label.pixel_size = .022
	label.outline_size = 3
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_cues.add_child(label)

func _cue_box(at: Vector3, size: Vector3, material: Material) -> void:
	var visual := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	visual.mesh = mesh
	visual.position = at
	visual.material_override = material
	visual.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_cues.add_child(visual)

func _dialogue(peer: int, spec: Dictionary, lines: Array) -> void:
	session.network.send_event(peer, {"kind":"dialogue", "character_id":str(spec.character_id), "lines":lines.duplicate()})
	session._audio_event("interaction", Catalog.point(spec.terminal), str(spec.id))

func _host() -> bool:
	return session != null and enabled and session.network.is_authority() and session.owns_world

func _peer(body: Variant) -> int:
	for peer: Variant in session.players:
		if session.players[peer] == body: return int(peer)
	return 0

func _bump() -> void:
	if serial < View.MAX_COUNTER: serial += 1
	_sealed.clear()

func _edge_key() -> String:
	var ids: Array = []
	for actor: Variant in enemies:
		if is_instance_valid(actor): ids.append([str(actor.get_meta("entity_id", "")), actor.dying, actor.neutralized, actor.controlled, actor.warning_id, actor.telegraph > 0.0])
	return JSON.stringify([_phase, _wave, ids, _bolts.size()])

func presentation() -> Dictionary:
	if not enabled or not is_instance_valid(_world) or Catalog.sites(str(session.region_id)).is_empty(): return {}
	if session.network.mode == "guest": return _remote_view.duplicate(true)
	if not _sealed.is_empty(): return _sealed.duplicate(true)
	var actors: Array = []
	for id: String in _units:
		var a: Variant = _units[id].actor
		if not is_instance_valid(a): continue
		var alive: bool = not a.dying and not a.neutralized and a.hp > 0.0
		var target: Variant = a.attack_target.get_ref() if a.attack_target != null else null
		var warning: bool = alive and a.telegraph > 0.0 and may_attack(a, target)
		var ability_state: Dictionary = session.entities.get(id, _units[id].get("ability_state", {}))
		actors.append({"id":id, "role":str(a.role), "position":a.global_position, "velocity":a.velocity,
			"heading":float(a.rotation.y), "health":maxf(0.0, float(a.hp)), "armor":float(a.damage_state.armor),
			"alive":alive, "neutralized":bool(a.neutralized), "controlled":bool(a.controlled), "ceasefire":str(a.ceasefire_reason),
			"charge":float(ability_state.get("charge", 70.0)), "temperature":float(ability_state.get("temperature", 20.0)), "pinned":bool(ability_state.get("pinned", false)),
			"recoil":float(a.recoil), "warning_id":int(a.warning_id), "warning_ms":clampi(ceili(a.telegraph*1000.0), 1, 1250) if warning else 0,
			"warning_end":a.global_position+a.attack_direction*a.attack_length if warning else a.global_position})
	var payload: Dictionary = {}
	if is_instance_valid(_payload):
		payload = {"id":str(session.region_id)+":combat88:payload", "position":_payload.global_position,
			"velocity":_payload.velocity, "heading":float(_payload.rotation.y), "health":maxf(0.0, float(_payload.hp)),
			"waypoint":int(_payload.waypoint), "arrived":bool(_payload.arrived), "alive":_payload.hp > 0.0}
	var bullets: Array = []
	for row: Dictionary in _bolts:
		bullets.append({"id":int(row.id), "position":row.visual.global_position, "basis":row.visual.global_basis, "friendly":bool(row.friendly)})
	_sealed = {"version":1, "session_id":session.network.session_id, "region":str(session.region_id), "epoch":epoch, "serial":serial,
		"site_id":str(_spec.get("id", "")), "phase":_phase, "wave":_wave, "total_waves":_spec.get("waves", []).size(),
		"actors":actors, "payload":payload, "bullets":bullets, "saved":_saved.duplicate(true), "error":error}
	return _sealed.duplicate(true)

func publish(peer_id: int = 0) -> void:
	if not _host() or session.network.mode != "host": return
	var view: Dictionary = presentation()
	if view.is_empty() or not View.valid(view): return
	var event := {"kind":View.KIND, "session_id":session.network.session_id, "region":str(session.region_id), "state":view}
	if peer_id > 1: session.network.send_event(peer_id, event)
	else:
		for peer: Variant in session.network.guests: session.network.send_event(int(peer), event)

func can_receive(view: Variant, source_session: String, incoming_region: String) -> bool:
	if session.network.mode != "guest" or not View.valid(view) or view.session_id != source_session or view.region != incoming_region: return false
	if _remote_session == source_session:
		if int(view.epoch) < _remote_epoch: return false
		if int(view.epoch) == _remote_epoch and int(view.serial) < _remote_serial: return false
		if int(view.epoch) == _remote_epoch and int(view.serial) == _remote_serial and view != _remote_view: return false
	return true

func receive_event(event: Dictionary) -> void:
	if session.network.mode != "guest" or event.size() != 4 or event.get("kind") != View.KIND or not event.get("session_id") is String or not event.get("region") is String or not event.get("state") is Dictionary: return
	if not session.received_session.is_empty() and event.session_id != session.received_session: return
	if not can_receive(event.state, str(event.session_id), str(event.region)): return
	if not _pending.is_empty():
		var old: Dictionary = _pending.state
		if event.session_id == _pending.session_id and (int(event.state.epoch) < int(old.epoch) or int(event.state.epoch) == int(old.epoch) and int(event.state.serial) < int(old.serial)): return
	_pending = event.duplicate(true)
	_consume_pending()

func _consume_pending() -> void:
	if _pending.is_empty() or not is_instance_valid(_world) or session.received_session.is_empty() or _pending.session_id != session.received_session or _pending.region != session.region_id or _world != session.world: return
	var view: Dictionary = _pending.state
	if int(view.epoch) < _required_epoch: return
	if receive(view): _pending.clear()

func receive(view: Dictionary) -> bool:
	if not can_receive(view, session.received_session, str(session.region_id)) or not is_instance_valid(_world) or int(view.epoch) < _required_epoch: return false
	if _remote_session == view.session_id and _remote_epoch == int(view.epoch) and _remote_serial == int(view.serial): return view == _remote_view
	_remote_session = str(view.session_id)
	_remote_epoch = int(view.epoch)
	_remote_serial = int(view.serial)
	_remote_view = view.duplicate(true)
	_saved = view.saved.duplicate(true)
	_spec = Catalog.definition(str(view.site_id))
	if not _spec.is_empty(): _bounds = Catalog.bounds(_spec)
	_phase = str(view.phase)
	_wave = int(view.wave)
	error = str(view.error)
	var incoming: Dictionary = {}
	for row: Dictionary in view.actors: incoming[str(row.id)] = true
	for id: String in _units.keys():
		if incoming.has(id): continue
		var prior: Variant = _units[id].actor
		if is_instance_valid(prior): prior.free()
		_units.erase(id)
		session.entities.erase(id)
		_projection_ids.erase(id)
	enemies.clear()
	for row: Dictionary in view.actors:
		var actor: Variant = _units.get(str(row.id), {}).get("actor")
		if not is_instance_valid(actor):
			actor = Actor.new()
			actor.name = "CombatSiteProjection" + str(_units.size())
			actor.role = str(row.role)
			actor.combat = self
			actor.authoritative = false
			actor.set_meta("entity_id", str(row.id))
			_world.add_child(actor)
			_units[str(row.id)] = {"actor":actor, "counted":not row.alive}
		actor.global_transform = Transform3D(Basis(Vector3.UP, float(row.heading)), row.position)
		actor.force_update_transform()
		actor.velocity = row.velocity
		actor.hp = float(row.health)
		actor.damage_state.armor = float(row.armor)
		actor.dying = not bool(row.alive) and not bool(row.neutralized)
		actor.neutralized = bool(row.neutralized)
		actor.controlled = bool(row.controlled)
		actor.recoil = float(row.recoil)
		actor.ceasefire_reason = str(row.ceasefire)
		actor.visible = bool(row.alive)
		actor.collision_layer = 4 if row.alive else 0
		actor.collision_mask = MASK if row.alive else 0
		actor.warning.visible = int(row.warning_ms) > 0
		actor.beam.visible = int(row.warning_ms) > 0
		if int(row.warning_ms) > 0:
			var span: Vector3 = row.warning_end-row.position
			actor.beam.global_position = row.position+span*.5
			if span.length() > .001 and absf(span.normalized().dot(Vector3.UP)) < .99: actor.beam.look_at(row.warning_end, Vector3.UP)
			actor.beam.scale.z = span.length()
		enemies.append(actor)
		_projection_ids[str(row.id)] = true
		if row.alive:
			session.entities[str(row.id)] = {"id":str(row.id), "name":_role_label(str(row.role)), "position":row.position, "angle":float(row.heading), "tags":["enemy", "mechanical", "hackable", "conductive", "electrical", "thermal", "fieldable"], "owner":"enemy", "revision":_remote_serial, "health":float(row.health), "charge":float(row.charge), "temperature":float(row.temperature), "pinned":bool(row.pinned), "controlled":bool(row.controlled), "powered":float(row.charge) >= 20.0}
		else: session.entities.erase(str(row.id))
	_project_payload(view.payload)
	_project_bullets(view.bullets)
	return true

func present(delta: float) -> void:
	if session == null or session.network.mode != "guest": return
	_consume_pending()
	if session.simulation_paused: return
	for actor: Variant in enemies:
		if is_instance_valid(actor): actor.present_tick(delta)
	if is_instance_valid(_payload): _payload.present_tick(delta)

func _project_payload(row: Dictionary) -> void:
	if row.is_empty():
		if is_instance_valid(_payload): _payload.free()
		_payload = null
		return
	if not is_instance_valid(_payload):
		_payload = Payload.new()
		_payload.name = "OptionalServiceDroneProjection"
		_payload.combat = self
		_payload.authoritative = false
		_world.add_child(_payload)
		_label_payload()
	_payload.global_transform = Transform3D(Basis(Vector3.UP, float(row.heading)), row.position)
	_payload.force_update_transform()
	_payload.velocity = row.velocity
	_payload.hp = float(row.health)
	_payload.waypoint = int(row.waypoint)
	_payload.arrived = bool(row.arrived)
	_payload.dying = not bool(row.alive)
	_payload.collision_layer = 4 if row.alive else 0
	_payload.collision_mask = MASK if row.alive else 0
	_payload.visible = bool(row.alive)

func _project_bullets(rows: Array) -> void:
	var ids: Dictionary = {}
	for row: Dictionary in rows: ids[int(row.id)] = true
	for id: Variant in _remote_bullets.keys():
		if ids.has(id): continue
		var visual: Variant = _remote_bullets[id]
		if is_instance_valid(visual): visual.free()
		_remote_bullets.erase(id)
	for row: Dictionary in rows:
		var visual: Variant = _remote_bullets.get(int(row.id))
		if not is_instance_valid(visual):
			visual = _bolt_visual(bool(row.friendly))
			visual.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
			_world.add_child(visual)
			_remote_bullets[int(row.id)] = visual
		visual.global_transform = Transform3D(row.basis, row.position)

func _bolt_visual(friendly: bool) -> MeshInstance3D:
	if _remote_bullet_mesh == null:
		_remote_bullet_mesh = SphereMesh.new()
		_remote_bullet_mesh.radius = .23
		_remote_bullet_mesh.height = .46
		_remote_bullet_mesh.radial_segments = 8
		_remote_bullet_mesh.rings = 4
	if _enemy_material == null: _enemy_material = GameVisuals.material(Color("ffb05b"), .2)
	if _friendly_material == null: _friendly_material = GameVisuals.material(Color("79cbbf"), .2)
	var visual := MeshInstance3D.new()
	visual.mesh = _remote_bullet_mesh
	visual.material_override = _friendly_material if friendly else _enemy_material
	visual.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return visual

func _fault(code: String) -> Dictionary:
	error = code
	_suspend("fault")
	return _r(false, code)

static func _role_label(role: String) -> String:
	return {"scout":"巡航侦察机", "harasser":"近扰护卫机", "support":"维修支援机", "suppressor":"慢速压制机"}.get(role, "巡航机")

static func _r(ok: bool, code: String) -> Dictionary:
	return {"ok":ok, "code":code}
