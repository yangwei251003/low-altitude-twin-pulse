class_name TwinSharedAccessSession
extends RefCounted
## Authority lifecycle and exact reliable-state barrier for the physical bridge.
## World owns the Node. Story owns consensus, its transaction and all rewards.
const Bridge = preload("res://scripts/v3/world/twin_shared_access_bridge.gd")
const FlightBody = preload("res://scripts/v2/flight_body.gd")
const STATE_PATH := "world.environment.I2_shared_access"
const OBJECTIVE := "I2:distribution_audit:share_access"
const FLAG := "I2:distribution_access_shared"
const DISCOVERY := "I2:shared_access_plan"
const FACT := "I2:distribution_access_committed"
const MAX_COUNTER := 9007199254740000
const MAX_PENDING_PACKETS := 8
const MAX_PACKET_BYTES := 32768
const PUBLISH_SECONDS := 0.1
const MAX_ADVANCE_SECONDS := 1.0
const MAX_PHYSICS_DELTA := 0.25
const CONFIRM_DISTANCE := 4.5
const ENVELOPE_KEYS := ["version", "mechanism"]
const EVENT_KEYS := ["kind", "session_id", "region", "epoch", "serial", "state"]
var session
var module
var ready := false
var error := ""
var serial := 0
var epoch := 0
var expected_serial := -1
var expected_epoch := -1
var expected_region := ""
var applied_serial := -1
var pending_network: Array[Dictionary] = []
var publish_clock := 0.0
var _retained_state: Dictionary = {}
var _last_packet: Dictionary = {}
var _bound_session := ""
var _needs_rebuild := true
var _handling_failure := false

func setup(owner_session) -> void:
	session = owner_session

func reset_connection() -> void:
	clear()
	serial = 0
	epoch = 0
	expected_serial = -1
	expected_epoch = -1
	expected_region = ""
	applied_serial = -1
	pending_network.clear()
	_last_packet.clear()
	_bound_session = ""

func clear() -> void:
	# Do not free World-owned children. Keep bounded early reliable packets and
	# the current exact packet for a same-session/epoch local view rebuild.
	module = null
	ready = false
	error = ""
	_retained_state.clear()
	publish_clock = 0.0
	_needs_rebuild = true

func prepare(world_data: Dictionary, destination: String, authority: bool, _discoveries: Array = []) -> Dictionary:
	if destination not in ["I1", "I2", "I3", "I4", "F1", "F2", "F3", "F4"]: return _failure("shared_access_destination")
	var story := _world_results(world_data)
	if not story.ok: return story
	var environment: Variant = world_data.get("environment", {})
	if not environment is Dictionary: return _failure("shared_access_environment")
	var missing: bool = not environment.has("I2_shared_access")
	# Personal discoveries legitimately survive switching to an earlier branch.
	if missing and story.has_results: return _failure("shared_access_missing_mechanism")
	var envelope: Variant = environment.get("I2_shared_access")
	if not missing and (not envelope is Dictionary or not _exact(envelope, ENVELOPE_KEYS) or not _integer(envelope.version, 1, 1)):
		return _failure("shared_access_envelope")
	if not missing and not envelope.mechanism is Dictionary: return _failure("shared_access_mechanism_type")
	var saved: Dictionary = {} if missing else envelope.mechanism.duplicate(true)
	var candidate = Bridge.new()
	# First validate the unmodified save. Authority cleanup happens only on the
	# detached copy, never on the still-playing old scene before Store succeeds.
	var configured: Dictionary = candidate.load_layout(saved, false)
	if not configured.ok:
		candidate.free()
		return _failure("shared_access_mechanism:" + str(configured.code))
	if authority:
		candidate.free()
		candidate = Bridge.new()
		configured = candidate.load_layout(saved, true)
		if not configured.ok:
			candidate.free()
			return _failure("shared_access_host_restore:" + str(configured.code))
	var next := _envelope(candidate.snapshot())
	var result: Dictionary = {"ok":true, "error":"", "destination":destination, "module":null,
		"needs_init":missing and destination == "I2", "migrated":false,
		"stopped":not missing and not _same(saved, next.mechanism),
		"state":{} if missing and destination != "I2" else next}
	if destination == "I2": result.module = candidate
	else: candidate.free() # No hidden simulator, elapsed time or catch-up.
	return result

func discard(prepared: Dictionary) -> void:
	var candidate: Variant = prepared.get("module")
	if is_instance_valid(candidate) and candidate is Node and candidate.get_parent() == null: candidate.free()

func adopt(prepared: Dictionary, _world_data: Dictionary) -> void:
	clear()
	if session == null or not prepared.get("ok", false) or prepared.get("destination") != session.region_id:
		error = "shared_access_adopt_unprepared"
		return
	module = prepared.get("module")
	_retained_state = prepared.get("state", {}).duplicate(true)
	if session.region_id == "I2":
		if not is_instance_valid(module) or not module is Bridge or not module.is_inside_tree() or module.authority != session.network.is_authority():
			error = "shared_access_world_must_own_bridge"
			return
		if not module.global_transform.is_equal_approx(Transform3D.IDENTITY) or not module.status().pose_valid:
			error = "shared_access_adopt_pose"
			return
	if session.network.is_authority():
		ready = true
		if is_instance_valid(module):
			var synced: Dictionary = module.synchronize_impulse_roster({})
			if not synced.ok:
				_fail_live("shared_access_roster:" + str(synced.code))
				return
			_update_positions()
		if epoch >= MAX_COUNTER:
			_fail_live("shared_access_epoch_limit")
			return
		epoch += 1
		publish()
	else:
		applied_serial = -1
		_needs_rebuild = true

func persistent_state() -> Dictionary:
	if not ready: return {}
	return _envelope(module.snapshot()) if is_instance_valid(module) else _retained_state.duplicate(true)

func has_pending_observation() -> bool:
	return false

func retry_pending() -> bool:
	return true # No second Store writer or secretly queued choice.

func pending_retry() -> bool:
	return retry_pending()

func sync_roster(reset_peer: int = 0) -> void:
	if not _host_local(): return
	var checked: Dictionary = module.synchronize_impulse_roster(session.players)
	if not checked.ok:
		_fail_live("shared_access_roster:" + str(checked.code))
		return
	if reset_peer > 0 and session.players.has(reset_peer) and session.players[reset_peer].enabled and float(session.players[reset_peer].health) > 0:
		checked = module.reset_impulse_peer(reset_peer)
		if not checked.ok: _fail_live("shared_access_reset_peer:" + str(checked.code))

func set_paused(value: bool) -> void:
	if not is_instance_valid(module): return
	var checked: Dictionary = module.set_simulation_paused(value)
	if not checked.ok:
		_fail_live("shared_access_pause:" + str(checked.code))
		return
	if session.network.is_authority(): publish()

func advance(delta: float) -> void:
	if not _host_local() or session.simulation_paused: return
	if not is_finite(delta) or delta < 0.0 or delta > MAX_ADVANCE_SECONDS:
		_fail_live("shared_access_delta_range")
		return
	if delta == 0.0: return
	var remaining := delta
	while remaining > 0.0000001:
		var part := minf(remaining, MAX_PHYSICS_DELTA)
		var moved: Dictionary = module.fixed_update(part, session.entities, session.players, true)
		if not moved.ok:
			_fail_live("shared_access_update:" + str(moved.code))
			return
		remaining -= part
	_update_positions()
	publish_clock += delta
	if publish_clock >= PUBLISH_SECONDS:
		publish_clock = 0.0
		publish()

func choice_anchor(mode: String) -> Dictionary:
	if mode not in Bridge.MODES or not is_instance_valid(module) or not module.is_inside_tree(): return {}
	var id: String = Bridge.PUBLIC_CONTROL if mode == Bridge.MODES[0] else Bridge.SERVICE_CONTROL
	var at: Variant = module.entity_position(id)
	if not at is Vector3: return {}
	return {"target_id":id, "position":at, "radius":CONFIRM_DISTANCE, "mode":mode}

func inspection_position(mode: String, half_height: float = .34) -> Vector3:
	# A navigation viewpoint derived from the real landing and controller. It
	# never replaces the controller point used by range and first-hit validation.
	var anchor := choice_anchor(mode)
	if anchor.is_empty() or not is_finite(half_height) or half_height < 0: return Vector3.INF
	var layout: Dictionary = module.layout()
	var landing: StaticBody3D = module.fixed_bodies.EastLanding
	var clearance_top := float(layout.deck_top_y) + float(layout.route_height_m) + .01
	return Vector3(landing.global_position.x, clearance_top + maxf(half_height, .34) + .45, anchor.position.z)

func choice_confirmation(peer_id: int, mode: String) -> Dictionary:
	# Call again immediately before the external Story transaction. Never accept
	# a client-supplied route report, saved successful result or proposed pose.
	if not _host_local() or session.simulation_paused: return _failure("shared_access_unavailable")
	if mode not in Bridge.MODES: return _failure("shared_access_mode")
	if not session.players.has(peer_id): return _failure("shared_access_player")
	var body: Variant = session.players[peer_id]
	if not is_instance_valid(body) or not body is FlightBody or not body.is_inside_tree() or body.get_world_3d() != module.get_world_3d(): return _failure("shared_access_player")
	if not body.enabled or not is_finite(float(body.health)) or float(body.health) <= 0 or (body.collision_layer & 2) == 0: return _failure("shared_access_player")
	var status: Dictionary = module.status()
	if not module.global_transform.is_equal_approx(Transform3D.IDENTITY) or not status.pose_valid: return _failure("shared_access_pose")
	if not status.locked or status.mode != mode: return _failure("shared_access_not_locked_here")
	var anchor := choice_anchor(mode)
	if anchor.is_empty(): return _failure("shared_access_anchor")
	var sensor: Vector3 = body.global_position
	if not sensor.is_finite() or sensor.distance_to(anchor.position) > CONFIRM_DISTANCE: return _failure("shared_access_too_far")
	# A teleported/interpenetrating body is not an admissible observer. Use each
	# actual enabled owner shape, not a point or an invented capsule radius.
	var shape_count := 0
	for owner in body.get_shape_owners():
		if body.is_shape_owner_disabled(owner): continue
		for index in range(body.shape_owner_get_shape_count(owner)):
			shape_count += 1
			var query := PhysicsShapeQueryParameters3D.new()
			query.shape = body.shape_owner_get_shape(owner, index)
			query.transform = body.global_transform * body.shape_owner_get_transform(owner)
			query.collision_mask = 0xFFFFFFFF
			query.exclude = [body.get_rid()]
			query.margin = 0.0
			if not module.get_world_3d().direct_space_state.intersect_shape(query, 1).is_empty(): return _failure("shared_access_body_occupied")
	if shape_count == 0: return _failure("shared_access_player_shape")
	var excluded: Array[RID] = [body.get_rid()]
	var ray := PhysicsRayQueryParameters3D.create(sensor, anchor.position, 0xFFFFFFFF, excluded)
	var hit: Dictionary = module.get_world_3d().direct_space_state.intersect_ray(ray)
	if hit.is_empty() or hit.get("rid") != module.target_bodies[anchor.target_id].get_rid(): return _failure("shared_access_obstructed")
	var access: Dictionary = module.access_report()
	if not access.get("ok", false) or not access.get("choice_ready", false) or access.get("mode") != mode or not access.get("public_access", false) or not access.get("service_access", false) or access.get("width_m") != 3.0 or access.get("height_m") != 2.8:
		return _failure("shared_access_route_blocked")
	return {"ok":true, "code":"shared_access_confirmable", "error":"", "mode":mode,
		"target_id":anchor.target_id, "anchor":[anchor.position.x, anchor.position.y, anchor.position.z],
		"mechanism_serial":int(module.snapshot().serial), "state":persistent_state(), "access":access.duplicate(true),
		"fact":{"kind":"fact", "target":FACT, "option":mode}}

static func confirmation_message(code: String) -> String:
	match code:
		"shared_access_not_locked_here": return "桥还没有锁在这一端。先调整桥位并插好锁销，再确认。"
		"shared_access_too_far": return "靠近所选一端的控制台，再确认通路安排。"
		"shared_access_obstructed": return "控制台被结构遮住了。换到能看清控制面的一侧。"
		"shared_access_body_occupied": return "机体贴住了结构。离开障碍物后再检查。"
		"shared_access_route_blocked": return "有人或物件挡住了通路。请让开桥面及绕廊上方，再确认。"
		_: return "当前还不能确认共用桥，请检查现场后再试。"

func publish(peer_id: int = 0) -> void:
	if session == null or not session.owns_world or not session.network.is_authority() or not ready or epoch < 1: return
	if peer_id == 0 or serial == 0:
		if serial >= MAX_COUNTER:
			_fail_live("shared_access_serial_limit")
			return
		serial += 1
	if peer_id<=1 and session.network.guests.is_empty(): return
	var event: Dictionary = {"kind":"shared_access_state", "session_id":session.network.session_id,
		"region":session.region_id, "epoch":epoch, "serial":serial,
		"state":persistent_state() if session.region_id == "I2" else {}}
	if peer_id > 1: session.network.send_event(peer_id, event)
	else:
		for peer in session.network.guests: session.network.send_event(int(peer), event)

func receive(event: Dictionary) -> void:
	if session == null or session.network.mode != "guest" or not session.active: return
	if not _exact(event, EVENT_KEYS) or event.get("kind") != "shared_access_state": return
	if not event.session_id is String or event.session_id.is_empty() or event.session_id.length() > 128: return
	if event.region not in ["I1", "I2", "I3", "I4", "F1", "F2", "F3", "F4"] or not event.state is Dictionary: return
	if event.region != "I2" and not event.state.is_empty(): return
	if not _integer(event.serial, 1, MAX_COUNTER) or not _integer(event.epoch, 1, MAX_COUNTER) or var_to_bytes(event).size() > MAX_PACKET_BYTES: return
	if not session.received_session.is_empty() and event.session_id != session.received_session: return
	if not _bound_session.is_empty() and event.session_id != _bound_session: return
	if int(event.epoch) < expected_epoch: return
	for cached in pending_network:
		if cached.session_id == event.session_id and cached.epoch == event.epoch and cached.region == event.region and cached.serial == event.serial: return
	pending_network.append(event.duplicate(true))
	while pending_network.size() > MAX_PENDING_PACKETS: pending_network.pop_front()
	consume(expected_serial, expected_epoch, expected_region)

func consume(snapshot_serial: int, snapshot_epoch: int, region: String) -> bool:
	if session == null or session.network.mode != "guest": return true
	if not _integer(snapshot_serial, 1, MAX_COUNTER) or not _integer(snapshot_epoch, 1, MAX_COUNTER) or region not in ["I1", "I2", "I3", "I4", "F1", "F2", "F3", "F4"]: return false
	if session.received_session.is_empty(): return false
	if _bound_session.is_empty(): _bound_session = session.received_session
	elif _bound_session != session.received_session: return false
	if snapshot_epoch < expected_epoch or (snapshot_epoch == expected_epoch and not expected_region.is_empty() and region != expected_region): return false
	if snapshot_epoch == expected_epoch and snapshot_serial < expected_serial: return false
	var new_context: bool = snapshot_epoch != expected_epoch or region != expected_region
	if new_context:
		applied_serial = -1
		_last_packet.clear()
		_needs_rebuild = true
	if new_context or snapshot_serial != expected_serial: ready = false
	expected_serial = snapshot_serial
	expected_epoch = snapshot_epoch
	expected_region = region
	_filter_network()
	if region != "I2":
		ready = true
		return true
	if session.region_id != region or not is_instance_valid(module) or not module.is_inside_tree() or module.authority: return false
	if ready and not _needs_rebuild and applied_serial == snapshot_serial: return true
	var packet: Dictionary = {}
	for candidate in pending_network:
		if candidate.epoch == snapshot_epoch and candidate.region == region and candidate.serial == snapshot_serial:
			packet = candidate
			break
	if packet.is_empty() and _needs_rebuild and not _last_packet.is_empty() and int(_last_packet.serial) == snapshot_serial: packet = _last_packet
	if packet.is_empty(): return false
	if not _apply_packet(packet):
		pending_network.erase(packet)
		return false
	_last_packet = packet.duplicate(true)
	applied_serial = snapshot_serial
	_needs_rebuild = false
	ready = true
	error = ""
	_filter_network()
	return true

func _apply_packet(packet: Dictionary) -> bool:
	if not module.global_transform.is_equal_approx(Transform3D.IDENTITY) or not module.status().pose_valid: return false
	var checked := _validate_envelope(packet.state, module)
	if not checked.ok:
		error = "shared_access_network:" + str(checked.error)
		return false
	if not _last_packet.is_empty():
		var previous: Dictionary = _last_packet.state.mechanism
		var incoming: Dictionary = packet.state.mechanism
		if int(incoming.serial) < int(previous.serial): return false
		if incoming.serial == previous.serial and not _same(incoming, previous): return false
	var applied: Dictionary = module.apply_snapshot(packet.state.mechanism)
	if not applied.ok: return false
	if not module.status().pose_valid: return false
	_update_positions()
	return true

func _filter_network() -> void:
	var kept: Array[Dictionary] = []
	for packet in pending_network:
		if packet.session_id != _bound_session or int(packet.epoch) < expected_epoch: continue
		if int(packet.epoch) == expected_epoch and (packet.region != expected_region or int(packet.serial) < expected_serial): continue
		kept.append(packet)
	pending_network = kept

func _update_positions() -> void:
	if not is_instance_valid(module) or session.region_id != "I2": return
	for id in module.target_bodies:
		if session.entities.has(id): session.entities[id].position = module.entity_position(id)

func _host_local() -> bool:
	return session != null and session.active and session.owns_world and session.network.is_authority() and session.region_id == "I2" and ready and is_instance_valid(module) and module.authority and module.is_inside_tree()

func _fail_live(code: String) -> void:
	error = code
	ready = false
	if _handling_failure: return
	_handling_failure = true
	if session != null and session.owns_world and session.network.is_authority():
		session.simulation_paused = true
		session._apply_pause_state()
		session._note_all("共用桥状态校验未通过，世界已暂停；已保存安排保留。")
	push_error(code)
	_handling_failure = false

static func _envelope(mechanism: Dictionary) -> Dictionary:
	return {"version":1, "mechanism":mechanism.duplicate(true)}

static func _validate_envelope(raw: Variant, checker) -> Dictionary:
	if not raw is Dictionary or not _exact(raw, ENVELOPE_KEYS) or not _integer(raw.version, 1, 1): return _failure("shared_access_envelope")
	var checked: Dictionary = checker.validate_snapshot(raw.mechanism)
	return {"ok":true, "error":""} if checked.ok else _failure("shared_access_mechanism:" + str(checked.code))

static func _world_results(world: Dictionary) -> Dictionary:
	var actions: Variant = world.get("actions", {})
	var flags: Variant = world.get("flags", {})
	if not actions is Dictionary or not flags is Dictionary: return _failure("shared_access_world_schema")
	var opening: Variant = actions.get("opening", {})
	if not opening is Dictionary: return _failure("shared_access_opening_schema")
	var choices: Variant = opening.get("choices", {})
	var completed: Variant = opening.get("completed", [])
	var mirrored: Variant = world.get("completed_objectives", [])
	if not choices is Dictionary or not completed is Array or not mirrored is Array: return _failure("shared_access_results_schema")
	if flags.has(FLAG) and not flags[FLAG] is bool: return _failure("shared_access_flag")
	if choices.has(OBJECTIVE) and choices[OBJECTIVE] not in Bridge.MODES: return _failure("shared_access_saved_choice")
	return {"ok":true, "error":"", "has_results":OBJECTIVE in completed or OBJECTIVE in mirrored or bool(flags.get(FLAG, false)) or choices.has(OBJECTIVE)}

static func _same(a: Variant, b: Variant) -> bool:
	if (a is int or a is float) and (b is int or b is float): return is_finite(float(a)) and is_finite(float(b)) and float(a) == float(b)
	if typeof(a) != typeof(b): return false
	if a is Dictionary:
		if a.size() != b.size(): return false
		for key in a:
			if not b.has(key) or not _same(a[key], b[key]): return false
		return true
	if a is Array:
		if a.size() != b.size(): return false
		for i in range(a.size()):
			if not _same(a[i], b[i]): return false
		return true
	return a == b

static func _integer(value: Variant, low: int, high: int) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and float(value) >= low and float(value) <= high and floor(float(value)) == float(value)

static func _exact(value: Dictionary, keys: Array) -> bool:
	if value.size() != keys.size(): return false
	for key in value:
		if not key is String or key not in keys: return false
	return true

static func _failure(code: String) -> Dictionary:
	return {"ok":false, "error":code, "code":code}
