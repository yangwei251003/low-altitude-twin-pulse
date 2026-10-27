class_name TwinClinicSession
extends RefCounted
const I2Results = preload("res://scripts/v3/gameplay/twin_i2_result_ledger.gd")
## Host lifecycle for the clinic. One physical module runs online, either in the
## visited world or in an isolated, non-rendered World3D. No offline catch-up.
const Works = preload("res://scripts/v3/world/twin_clinic_waterworks.gd")
const LayoutMigration = preload("res://scripts/v3/world/twin_clinic_layout_migration.gd")
const Progress = preload("res://scripts/v3/gameplay/actions/twin_clinic_progress.gd")
const DistributionProgress = preload("res://scripts/v3/gameplay/actions/twin_distribution_progress.gd")
var session
var module: Node3D
var progress = Progress.new()
var background: SubViewport
var background_entities: Dictionary = {}
var serial := 0
var epoch := 0
var expected_serial := -1
var expected_epoch := -1
var applied_serial := -1
var expected_region := ""
var pending: Dictionary = {}
var publish_clock := 0.0
var ready := false
var error := ""

func setup(owner_session) -> void:
	session = owner_session

func reset_connection() -> void:
	clear()
	serial = 0
	epoch = 0
	expected_serial = -1
	expected_epoch = -1
	applied_serial = -1
	expected_region = ""
	pending.clear()
	progress = Progress.new()

func clear() -> void:
	# A visible module belongs to its world; a background module to the viewport.
	if is_instance_valid(background):
		background.get_parent().remove_child(background)
		background.queue_free()
	background = null
	module = null
	background_entities.clear()
	ready = false
	error = ""

func persistent_state(history_override: Dictionary = {}) -> Dictionary:
	if not ready or not is_instance_valid(module): return {}
	return {"version":1, "mechanism":module.snapshot(), "history":progress.snapshot() if history_override.is_empty() else history_override.duplicate(true)}

func prepare(world_data: Dictionary, destination: String, authority: bool) -> Dictionary:
	var checked: Dictionary = I2Results.validate_world(world_data)
	if not checked.ok: return {"ok":false, "error":"i2_results:" + str(checked.error)}
	var clinic_completed: Array = checked.projected.clinic.completed
	var clinic_flags: Dictionary = checked.projected.clinic.flags
	var envelope: Variant = world_data.get("environment", {}).get("I2_water")
	var tracker = Progress.new()
	var restored: Dictionary = tracker.prepare_restore(envelope, clinic_completed, clinic_flags)
	if not restored.ok: return {"ok":false, "error":"clinic_history:" + str(restored.code)}
	if restored.needs_init and destination != "I2": return {"ok":true, "module":null, "progress":tracker}
	var candidate = Works.new()
	var mechanism: Dictionary = {} if restored.needs_init else envelope.mechanism
	var migrated := false
	if authority and not mechanism.is_empty():
		var migration: Dictionary = LayoutMigration.prepare(mechanism)
		if not migration.ok:
			candidate.free()
			return {"ok":false, "error":"clinic_migration:" + str(migration.code)}
		mechanism = migration.state
		migrated = migration.migrated
	var loaded: Dictionary = candidate.load_layout(mechanism, authority)
	if not loaded.ok:
		candidate.free()
		return {"ok":false, "error":"clinic_mechanism:" + str(loaded.code)}
	if not tracker.adopt_restore(restored):
		candidate.free()
		return {"ok":false, "error":"clinic_history_adoption"}
	candidate.set_service_available(bool(tracker.snapshot().commissioned))
	return {"ok":true, "module":candidate, "progress":tracker, "migrated":migrated,
		"state":{"version":1, "mechanism":candidate.snapshot(), "history":tracker.snapshot()}}

func discard(prepared: Dictionary) -> void:
	var candidate = prepared.get("module")
	if is_instance_valid(candidate) and not candidate.is_inside_tree(): candidate.free()

func adopt(prepared: Dictionary, world_data: Dictionary) -> void:
	clear()
	progress = prepared.progress
	module = prepared.module
	ready = is_instance_valid(module)
	if ready and module.get_parent() == null:
		background = SubViewport.new()
		background.name = "UnvisitedClinicPhysics"
		background.size = Vector2i(2, 2)
		background.world_3d = World3D.new()
		background.render_target_update_mode = SubViewport.UPDATE_DISABLED
		background.gui_disable_input = true
		session.add_child(background)
		background.add_child(module)
		for definition in module.target_definitions():
			var state: Dictionary = definition.duplicate(true)
			state.merge(world_data.get("entities", {}).get("I2", {}).get(definition.id, {}), true)
			background_entities[definition.id] = state
	if ready and session.network.is_authority(): module.synchronize_impulse_roster({})
	if session.network.is_authority():
		epoch += 1
		publish()
	else:
		applied_serial = -1
		ready = false # A host state must reconstruct collision before guest input.

func sync_roster(reset_peer: int = 0) -> void:
	if not ready or not session.network.is_authority(): return
	var roster: Dictionary = session.players if session.region_id == "I2" else {}
	module.synchronize_impulse_roster(roster)
	if reset_peer > 0 and roster.has(reset_peer) and roster[reset_peer].enabled: module.reset_impulse_peer(reset_peer)

func set_paused(value: bool) -> void:
	if not is_instance_valid(module): return
	module.set_simulation_paused(value)
	if session.network.is_authority(): publish()

func advance(delta: float) -> void:
	if not ready or not session.owns_world or not session.network.is_authority() or session.simulation_paused: return
	var local: bool = session.region_id == "I2"
	var entities: Dictionary = session.entities if local else background_entities
	var players: Dictionary = session.players if local else {}
	var remaining := delta
	while remaining > 0.0000001:
		var step := minf(remaining, Works.MAX_DELTA)
		if not local:
			var timed: Dictionary = session.rules.advance_states(entities, step)
			if timed.get("ok", false): session.rules.commit(timed, entities)
		var before: Dictionary = module.snapshot()
		var moved: Dictionary = module.fixed_update(step, entities, players, true)
		if not moved.ok:
			error = "clinic_update:" + str(moved.code)
			push_error(error)
			return
		var observed: Dictionary = progress.observe(step, before, module.snapshot(), module.status(), moved, access_clear(), true, false)
		if not observed.ok:
			error = "clinic_progress:" + str(observed.code)
			# A failed fact observation must not leave a physical step whose
			# transfer history could later be silently saved as a different route.
			module.apply_snapshot(before)
			session.simulation_paused = true
			session._apply_pause_state()
			session._note_all("供水状态校验未通过，世界已暂停；当前保存记录保留。")
			push_error(error)
			return
		remaining -= step
	if local:
		for id in module.target_bodies:
			if entities.has(id): entities[id].position = module.entity_position(id)
	publish_clock += delta
	if publish_clock >= 0.10:
		publish_clock = 0.0
		publish()

func access_clear() -> bool:
	if not is_instance_valid(module) or not module.is_inside_tree(): return false
	if absf(float(module.status().deck_top_y) - 5.0) > 0.00001: return false
	# The three full box surfaces actually meet. A 3m-wide, 1.5m-high corridor
	# above them is queried against terrain, both pilots and movable objects.
	for name in ["WestLanding", "EastLanding"]:
		var body: Node3D = module.fixed_bodies.get(name)
		if not is_instance_valid(body) or not body.global_basis.is_equal_approx(Basis.IDENTITY): return false
		var shape_node: CollisionShape3D = body.get_node_or_null("Collision")
		if shape_node == null:
			for child in body.get_children():
				if child is CollisionShape3D: shape_node = child
		if shape_node == null or not shape_node.shape is BoxShape3D: return false
		var size: Vector3 = shape_node.shape.size
		var centre: Vector3 = shape_node.global_position
		if absf(centre.y + size.y * 0.5 - 5.0) > 0.00001 or size.z < 3.0: return false
		var edge: float = centre.x + size.x * 0.5 if name == "WestLanding" else centre.x - size.x * 0.5
		if absf(edge - (-2.0 if name == "WestLanding" else 2.0)) > 0.00001: return false
	var query := PhysicsShapeQueryParameters3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(7.0, 1.5, 3.0)
	query.shape = shape
	query.transform.origin = Vector3(0, 5.76, -4)
	query.collision_mask = 1 | 2 | 8 | 32
	return module.get_world_3d().direct_space_state.intersect_shape(query, 1).is_empty()

func publish(peer_id: int = 0) -> void:
	if not session.owns_world or not session.network.is_authority(): return
	if ready and is_instance_valid(module): module.set_service_available(bool(progress.snapshot().commissioned))
	if peer_id == 0: serial += 1
	if peer_id<=1 and session.network.guests.is_empty(): return
	var event := {"kind":"clinic_state", "session_id":session.network.session_id, "region":session.region_id,
		"epoch":epoch, "serial":serial, "state":persistent_state() if session.region_id == "I2" else {}}
	if peer_id > 1: session.network.send_event(peer_id, event)
	else:
		for id in session.network.guests: session.network.send_event(int(id), event)

func receive(event: Dictionary) -> void:
	if session.network.mode != "guest" or not session.active: return
	if event.size() != 6 or str(event.get("session_id", "")).is_empty() or not event.get("state") is Dictionary: return
	for key in ["kind", "session_id", "region", "epoch", "serial", "state"]:
		if not event.has(key): return
	if event.kind != "clinic_state": return
	if var_to_bytes(event).size() > 16384: return
	if not _counter(event.get("serial")) or not _counter(event.get("epoch")): return
	if event.get("region") not in ["I1", "I2", "I3", "I4", "F1", "F2", "F3", "F4"]: return
	if not session.received_session.is_empty() and event.session_id != session.received_session: return
	if int(event.epoch) < expected_epoch or int(event.serial) <= applied_serial: return
	if not pending.is_empty() and pending.session_id == event.session_id and int(pending.epoch) == int(event.epoch) and int(event.serial) < int(pending.serial): return
	pending = event.duplicate(true)
	consume(expected_serial, expected_epoch, expected_region)

func consume(snapshot_serial: int, snapshot_epoch: int, region: String) -> bool:
	if session.network.mode != "guest": return true
	# Early reliable traffic cannot choose the host; the first motion packet
	# binds that identity. A foreign high counter must not block its real state.
	if not session.received_session.is_empty() and not pending.is_empty() and pending.session_id != session.received_session:
		pending.clear()
	if region == "I2" and (not _counter(snapshot_serial) or not _counter(snapshot_epoch)): return false
	if snapshot_epoch != expected_epoch or region != expected_region:
		applied_serial = -1
	if region == "I2" and (snapshot_epoch != expected_epoch or region != expected_region or snapshot_serial != expected_serial): ready = false
	expected_serial = snapshot_serial
	expected_epoch = snapshot_epoch
	expected_region = region
	if region != "I2": return true
	if pending.is_empty() or not is_instance_valid(module): return ready
	if session.received_session.is_empty() or pending.session_id != session.received_session: return false
	if pending.region != region or int(pending.epoch) != snapshot_epoch or int(pending.serial) > snapshot_serial: return ready
	if int(pending.serial) <= applied_serial: return ready
	var envelope: Dictionary = pending.state
	if envelope.size() != 3 or envelope.get("version") != 1 or not envelope.get("mechanism") is Dictionary or not envelope.get("history") is Dictionary: return ready
	# Prepare history separately; a rejected physical snapshot must not partially
	# replace the displayed history. Adopt both in this callback before readiness.
	var candidate_history = Progress.new()
	if not candidate_history.adopt_reliable_history(envelope.history, envelope.mechanism): return ready
	var applied: Dictionary = module.apply_snapshot(envelope.mechanism)
	if not applied.ok: return ready
	progress = candidate_history
	module.set_service_available(bool(envelope.history.commissioned))
	applied_serial = int(pending.serial)
	ready = true
	return true

func _counter(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and float(value) >= 1.0 and float(value) <= 9007199254740000.0 and float(value) == floor(float(value))
