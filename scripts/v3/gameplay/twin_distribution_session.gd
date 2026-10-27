class_name TwinDistributionSession
extends RefCounted
## Independent cabinet lifecycle. The visible World owns the physical module;
## unvisited regions retain validated state but never create a background world.
## Only the host can observe/commit. This adapter never awards a discovery.
const Cabinet = preload("res://scripts/v3/world/twin_distribution_cabinet.gd")
const Progress = preload("res://scripts/v3/gameplay/actions/twin_distribution_progress.gd")
const Axis = preload("res://scripts/v3/environment/twin_guided_axis.gd")
const LayoutMigration = preload("res://scripts/v3/world/twin_distribution_layout_migration.gd")
const STATE_PATH := "world.environment.I2_distribution"
const MAX_COUNTER := 9007199254740000
const MAX_PENDING_PACKETS := 8
const RETRY_SECONDS := 0.5
const PUBLISH_SECONDS := 0.1
const MAX_ADVANCE_SECONDS := 1.0 # At most four physical substeps per call.
const EVENT_KEYS := ["kind", "session_id", "region", "epoch", "serial", "state"]
var session
var module: Node3D
var progress = Progress.new()
var ready := false
var error := ""
var serial := 0
var epoch := 0
var expected_serial := -1
var expected_epoch := -1
var expected_region := ""
var applied_serial := -1
var pending_observation: Dictionary = {}
# Bounded reliable packets, separate from the pending disk transaction above.
var pending_network: Array[Dictionary] = []
var publish_clock := 0.0
var retry_clock := 0.0
var _layout: Dictionary = {}
var _retained_state: Dictionary = {}
var _last_applied_packet: Dictionary = {}
var _bound_session := ""
var _needs_rebuild := false

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
	_last_applied_packet.clear()
	_bound_session = ""

func clear() -> void:
	# The caller must first retry/guard any pending observation on travel, branch,
	# restart or quit. This releases references only; World frees its own child.
	module = null
	progress = Progress.new()
	_layout.clear()
	_retained_state.clear()
	pending_observation.clear()
	publish_clock = 0.0
	retry_clock = 0.0
	ready = false
	error = ""
	_needs_rebuild = true
	# Keep bounded early reliable packets across a local view rebuild. consume
	# binds/filter them by the motion session+region+epoch before any adoption.

func prepare(world_data: Dictionary, destination: String, authority: bool, discoveries: Array) -> Dictionary:
	if destination not in ["I1", "I2", "I3", "I4", "F1", "F2", "F3", "F4"]: return _failure("distribution_destination")
	var checked := _world_story(world_data)
	if not checked.ok: return checked
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(Cabinet.PATH))
	if not parsed is Dictionary: return _failure("distribution_layout_json")
	var tracker = Progress.new()
	var configured: Dictionary = tracker.configure(parsed)
	if not configured.ok: return _failure("distribution_layout:" + str(configured.code))
	var environment: Dictionary = world_data.get("environment", {})
	var envelope: Variant = environment.get("I2_distribution")
	if environment.has("I2_distribution") and envelope == null: return _failure("distribution_null_envelope")
	var migrated := false
	if authority and envelope!=null:
		if not envelope is Dictionary or not envelope.get("mechanism") is Dictionary:
			return _failure("distribution_migration_envelope")
		var migration: Dictionary = LayoutMigration.prepare(envelope.mechanism)
		if not migration.ok: return _failure("distribution_migration:"+str(migration.code))
		envelope=envelope.duplicate(true)
		envelope.mechanism=migration.state
		migrated=bool(migration.migrated)
	var restored: Dictionary = tracker.prepare_restore(envelope, checked.completed, world_data.get("flags", {}), discoveries, true)
	if not restored.ok: return _failure("distribution_history:" + str(restored.code))
	if not tracker.adopt_restore(restored): return _failure("distribution_history_adoption")
	var result := {"ok":true, "error":"", "module":null, "progress":tracker,
		"destination":destination, "needs_init":bool(restored.needs_init),
		"stopped":false, "migrated":migrated, "layout":parsed.duplicate(true)}
	var mechanism: Dictionary = {} if restored.needs_init else envelope.mechanism.duplicate(true)
	if authority and not mechanism.is_empty():
		# Stop a COPY. Failed travel/save must not stop or rewind the old world.
		var axis = Axis.new()
		var axis_configured: Dictionary = axis.configure(Cabinet._axis_config(parsed))
		if not axis_configured.ok: return _failure("distribution_axis_configuration")
		var axis_restored: Dictionary = axis.restore(mechanism.axis, true)
		if not axis_restored.ok: return _failure("distribution_axis_restore:" + str(axis_restored.code))
		axis.set_active_peers([])
		result.stopped = _hash(mechanism.axis) != _hash(axis.snapshot())
		mechanism.axis = axis.snapshot()
	if destination != "I2":
		if not restored.needs_init:
			result.state = {"version":1, "mechanism":mechanism, "history":tracker.snapshot()}
			if not tracker.validate_history(result.state.history, mechanism).ok: return _failure("distribution_stopped_history")
		return result
	var candidate = Cabinet.new()
	var loaded: Dictionary = candidate.configure(parsed, mechanism, authority)
	if not loaded.ok:
		candidate.free()
		return _failure("distribution_mechanism:" + str(loaded.code))
	result.module = candidate
	result.state = {"version":1, "mechanism":candidate.snapshot(), "history":tracker.snapshot()}
	return result

func discard(prepared: Dictionary) -> void:
	var candidate: Variant = prepared.get("module")
	# Attached modules belong to the candidate World, including queued deletion.
	if is_instance_valid(candidate) and candidate is Node and candidate.get_parent() == null: candidate.free()

func adopt(prepared: Dictionary, _world_data: Dictionary) -> void:
	clear()
	if not prepared.get("ok", false) or not prepared.get("progress") is Progress or not prepared.get("layout") is Dictionary:
		error = "distribution_adopt_unprepared"
		return
	progress = prepared.progress
	_layout = prepared.layout.duplicate(true)
	module = prepared.get("module")
	_retained_state = prepared.get("state", {}).duplicate(true)
	if str(prepared.destination) != str(session.region_id):
		error = "distribution_adopt_region"
		return
	if session.region_id == "I2" and (not is_instance_valid(module) or not module.is_inside_tree()):
		error = "distribution_world_must_own_module"
		return
	if session.network.is_authority():
		ready = is_instance_valid(module) or not _retained_state.is_empty()
		if is_instance_valid(module):
			var synced: Dictionary = module.synchronize_impulse_roster({})
			if not synced.ok:
				_fail_live("distribution_roster:" + str(synced.code))
				return
			_update_target_positions()
		if epoch >= MAX_COUNTER:
			_fail_live("distribution_epoch_limit")
			return
		epoch += 1
		publish()
	else:
		applied_serial = -1
		ready = false # Reliable state must first rebuild the actual collision.
		_needs_rebuild = true

func persistent_state() -> Dictionary:
	if not ready: return {}
	if is_instance_valid(module):
		return {"version":1, "mechanism":module.snapshot(), "history":progress.snapshot()}
	return _retained_state.duplicate(true)

func has_pending_observation() -> bool:
	return not pending_observation.is_empty()

func sync_roster(reset_peer: int = 0) -> void:
	if not _host_local(): return
	var synced: Dictionary = module.synchronize_impulse_roster(session.players)
	if not synced.ok:
		_fail_live("distribution_roster:" + str(synced.code))
		return
	if reset_peer > 0 and session.players.has(reset_peer):
		var body = session.players[reset_peer]
		if is_instance_valid(body) and body.enabled and float(body.health) > 0.0:
			var reset: Dictionary = module.reset_impulse_peer(reset_peer)
			if not reset.ok: _fail_live("distribution_reset_peer:" + str(reset.code))

func set_paused(value: bool) -> void:
	if not is_instance_valid(module): return
	var paused: Dictionary = module.set_simulation_paused(value)
	if not paused.ok:
		error = "distribution_pause:" + str(paused.code)
		ready = false
		return
	if session.network.is_authority(): publish()

func advance(delta: float) -> void:
	if not _host_local() or session.simulation_paused: return
	if not is_finite(delta) or delta < 0.0 or delta > MAX_ADVANCE_SECONDS:
		_fail_live("distribution_delta_range")
		return
	if delta == 0.0: return
	var remaining := delta
	while remaining > 0.0000001:
		var step := minf(remaining, 0.25)
		var moved: Dictionary = module.fixed_update(step, session.entities, session.players, true)
		if not moved.ok:
			_fail_live("distribution_update:" + str(moved.code))
			return
		remaining -= step
	_update_target_positions()
	publish_clock += delta
	retry_clock += delta
	# No ordinary retry may invalidate a pending shared decision's world revision.
	if has_pending_observation() and retry_clock >= RETRY_SECONDS and session.consensus.current_proposal().is_empty():
		retry_clock = 0.0
		retry_pending()
	if publish_clock >= PUBLISH_SECONDS:
		publish_clock = 0.0
		publish()

func observe(peer_id: int) -> Dictionary:
	if not _host_local() or session.simulation_paused:
		_observation_feedback(peer_id, "distribution_unavailable")
		return _observation_result(false, "distribution_unavailable")
	if not session.players.has(peer_id): return _observation_result(false, "unknown_observer")
	var sample: Dictionary = module.observe_back(peer_id, session.players[peer_id])
	if not sample.ok:
		_observation_feedback(peer_id, str(sample.code))
		var refused := sample.duplicate(true)
		refused.pending = has_pending_observation()
		return refused
	if progress.snapshot().back_observed:
		_observation_feedback(peer_id, "already_observed")
		return {"ok":true, "code":"already_observed", "pending":false, "method":progress.snapshot().method}
	var candidate: Dictionary = progress.prepare_observation(sample, module.snapshot())
	if not candidate.ok:
		_observation_feedback(peer_id, str(candidate.code))
		return _observation_result(false, "distribution_observation:" + str(candidate.code))
	pending_observation = candidate.duplicate(true)
	retry_clock = 0.0
	var saved := retry_pending()
	if not saved and error != "distribution_observation_save_failed":
		_observation_feedback(peer_id, "save_pending")
	var result := _observation_result(saved, "back_observed" if saved else "observation_save_pending")
	result.method = candidate.history.method
	return result

func retry_pending() -> bool:
	if not has_pending_observation(): return true
	if not _host_local(): return false
	if not session.consensus.current_proposal().is_empty() and not session._resolving_decision:
		error = "distribution_save_deferred_for_consensus"
		return false
	# NO cached mechanism or old whole-world snapshot is used on any retry.
	var prepared: Dictionary = progress.prepare_retry(pending_observation, module.snapshot())
	if not prepared.ok:
		error = "distribution_retry:" + str(prepared.code)
		return false
	var changes := {STATE_PATH:prepared.envelope, "world.entities.I2":session._persistent_environment()}
	if not session._commit("distribution-observation", changes):
		error = "distribution_observation_save_failed"
		return false
	if not progress.adopt_saved(prepared):
		# Disk already succeeded. Do not rewind geometry/history to pretend rollback.
		_fail_live("distribution_post_commit_adoption")
		return false
	pending_observation.clear()
	retry_clock = 0.0
	error = ""
	publish()
	session._note_all("配流箱背面的两路去向已记录。")
	return true

func publish(peer_id: int = 0) -> void:
	if session == null or not session.owns_world or not session.network.is_authority(): return
	if session.region_id == "I2" and (not ready or not is_instance_valid(module)): return
	if epoch < 1: return
	if peer_id == 0 or serial == 0:
		if serial >= MAX_COUNTER:
			error = "distribution_serial_limit"
			return
		serial += 1
	if peer_id<=1 and session.network.guests.is_empty(): return
	var event := {"kind":"distribution_state", "session_id":session.network.session_id,
		"region":session.region_id, "epoch":epoch, "serial":serial,
		"state":persistent_state() if session.region_id == "I2" else {}}
	if peer_id > 1: session.network.send_event(peer_id, event)
	else:
		for id in session.network.guests: session.network.send_event(int(id), event)

func receive(event: Dictionary) -> void:
	if session == null or session.network.mode != "guest" or not session.active: return
	if not _exact(event, EVENT_KEYS) or event.get("kind") != "distribution_state": return
	if not event.session_id is String or event.session_id.is_empty() or event.session_id.length() > 128: return
	if not event.region is String or event.region not in ["I1", "I2", "I3", "I4", "F1", "F2", "F3", "F4"] or not event.state is Dictionary: return
	if not _counter(event.serial) or not _counter(event.epoch) or var_to_bytes(event).size() > 16384: return
	if not session.received_session.is_empty() and event.session_id != session.received_session: return
	if not _bound_session.is_empty() and event.session_id != _bound_session: return
	if int(event.epoch) < expected_epoch: return
	if int(event.epoch) == expected_epoch and event.region == expected_region and int(event.serial) <= applied_serial and not _needs_rebuild: return
	for cached in pending_network:
		if cached.session_id == event.session_id and cached.region == event.region and cached.epoch == event.epoch and cached.serial == event.serial:
			return # An identical serial cannot replace an already queued frame.
	pending_network.append(event.duplicate(true))
	while pending_network.size() > MAX_PENDING_PACKETS: pending_network.pop_front()
	consume(expected_serial, expected_epoch, expected_region)

func consume(snapshot_serial: int, snapshot_epoch: int, region: String) -> bool:
	if session == null or session.network.mode != "guest": return true
	if not _counter(snapshot_serial) or not _counter(snapshot_epoch) or region not in ["I1", "I2", "I3", "I4", "F1", "F2", "F3", "F4"]: return false
	if session.received_session.is_empty(): return false
	if _bound_session.is_empty():
		_bound_session = str(session.received_session)
	elif _bound_session != session.received_session:
		return false # reset_connection is required before accepting a new host.
	if snapshot_epoch < expected_epoch: return false
	if snapshot_epoch == expected_epoch and not expected_region.is_empty() and region != expected_region: return false
	if snapshot_epoch == expected_epoch and snapshot_serial < expected_serial: return false
	var new_context: bool = snapshot_epoch != expected_epoch or region != expected_region
	var new_reference: bool = new_context or snapshot_serial != expected_serial
	if new_context:
		applied_serial = -1
		_last_applied_packet.clear()
		_needs_rebuild = true
	if new_reference: ready = false
	expected_serial = snapshot_serial
	expected_epoch = snapshot_epoch
	expected_region = region
	_filter_network()
	if region != "I2":
		# No cabinet exists here and no state is streamed; retain no foreign pose.
		return true
	if not is_instance_valid(module) or not module.is_inside_tree(): return false
	var candidates: Array[Dictionary] = []
	for packet in pending_network:
		if packet.region == region and int(packet.epoch) == snapshot_epoch and int(packet.serial) <= snapshot_serial and (int(packet.serial) > applied_serial or _needs_rebuild): candidates.append(packet)
	if _needs_rebuild and not _last_applied_packet.is_empty() and int(_last_applied_packet.serial) <= snapshot_serial:
		candidates.append(_last_applied_packet)
	candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a.serial) > int(b.serial))
	for packet in candidates:
		if not _apply_network_packet(packet):
			pending_network.erase(packet)
			continue
		applied_serial = int(packet.serial)
		_last_applied_packet = packet.duplicate(true)
		_needs_rebuild = false
		ready = true
		error = ""
		_filter_network()
		return true
	return ready

func _apply_network_packet(packet: Dictionary) -> bool:
	var tracker = Progress.new()
	var configured: Dictionary = tracker.configure(_layout)
	if not configured.ok: return false
	var restored: Dictionary = tracker.prepare_restore(packet.state, [], {}, [], false)
	if not restored.ok:
		error = "distribution_network_history:" + str(restored.code)
		return false
	if not _last_applied_packet.is_empty():
		var previous: Dictionary = _last_applied_packet.state.mechanism
		var incoming: Dictionary = packet.state.mechanism
		if int(incoming.serial) < int(previous.serial): return false
		if int(incoming.serial) == int(previous.serial) and _hash(incoming) != _hash(previous): return false
	# Within one world epoch committed knowledge never disappears or changes its
	# first method. A legitimate branch change has a new epoch instead.
	if not _last_applied_packet.is_empty() and _last_applied_packet.state.history.back_observed:
		if _hash(_last_applied_packet.state.history) != _hash(packet.state.history): return false
	var checked: Dictionary = module.validate_snapshot(packet.state.mechanism)
	if not checked.ok or not tracker.adopt_restore(restored): return false
	var applied: Dictionary = module.apply_snapshot(packet.state.mechanism)
	if not applied.ok: return false
	# Swap tracker only after complete validation and actual collision adoption.
	progress = tracker
	_update_target_positions()
	return true

func _filter_network() -> void:
	var kept: Array[Dictionary] = []
	for packet in pending_network:
		if packet.session_id != _bound_session or int(packet.epoch) < expected_epoch: continue
		if int(packet.epoch) == expected_epoch:
			if packet.region != expected_region: continue
			if int(packet.serial) <= applied_serial and not _needs_rebuild: continue
		kept.append(packet)
	pending_network = kept

func _update_target_positions() -> void:
	if not is_instance_valid(module) or session.region_id != "I2": return
	for id in module.target_bodies:
		if session.entities.has(id): session.entities[id].position = module.entity_position(id)

func _host_local() -> bool:
	return session != null and session.active and session.owns_world and session.network.is_authority() and session.region_id == "I2" and ready and is_instance_valid(module) and module.is_inside_tree()

func _fail_live(code: String) -> void:
	error = code
	ready = false
	if session != null and session.owns_world and session.network.is_authority():
		session.simulation_paused = true
		session._apply_pause_state()
	push_error(code)

func _observation_result(ok: bool, code: String) -> Dictionary:
	return {"ok":ok, "code":code, "pending":has_pending_observation()}

func _observation_feedback(peer_id: int, code: String) -> void:
	if session == null or not session.network.is_authority() or not session.players.has(peer_id): return
	var text := "两块背标尚未同时看清；换个角度再观察。"
	match code:
		"too_far": text = "再靠近些，让两块背标都进入 4.5 米观察范围。"
		"back_covered": text = "背标被挡住了；移开上方滑盖，或为检修门供电并接管电锁。"
		"observation_blocked": text = "两块背标还没同时露出；调整高度和角度，避开门盖与其他机体。"
		"body_occupied", "body_invalid", "body_envelope_required": text = "机体还不在可读位置；先离开墙体和门轨，再稳定观察。"
		"distribution_unavailable": text = "目前无法观察；请在水城恢复飞行后再试。"
		"already_observed": text = "这两路去向已经记下了。"
		"save_pending": text = "背标已看清，记录仍待保存；完成当前共同决定后会重试。"
	session._note(peer_id, text)

static func _world_story(world_data: Dictionary) -> Dictionary:
	for key in ["environment", "actions", "flags"]:
		if not world_data.get(key, {}) is Dictionary: return _failure("distribution_world_shape")
	var opening: Variant = world_data.get("actions", {}).get("opening", {})
	if not opening is Dictionary: return _failure("distribution_action_shape")
	var completed: Variant = opening.get("completed", [])
	var receipts: Variant = world_data.get("completed_objectives", [])
	var owned: Array = []
	for ids in [completed, receipts]:
		if not ids is Array or ids.size() > 256: return _failure("distribution_action_ids")
		var seen: Dictionary = {}
		var i2: Array[String] = []
		for id in ids:
			if not id is String or id.is_empty() or id.length() > 128 or seen.has(id): return _failure("distribution_action_ids")
			seen[id] = true
			if id.begins_with("I2:"): i2.append(id)
		i2.sort()
		owned.append(i2)
	if owned[0] != owned[1]: return _failure("distribution_action_receipts_mismatch")
	return {"ok":true, "completed":completed.duplicate()}

static func _counter(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and float(value) >= 1.0 and float(value) <= MAX_COUNTER and floor(float(value)) == float(value)

static func _exact(value: Dictionary, keys: Array) -> bool:
	if value.size() != keys.size(): return false
	for key in value:
		if not key is String or key not in keys: return false
	return true

static func _hash(value: Variant) -> String:
	return JSON.stringify(value, "", true, true).sha256_text()

static func _failure(code: String) -> Dictionary:
	return {"ok":false, "error":code}
