extends SceneTree
## Real production I2 geometry + Bridge/FlightBody/Rules/PhysicsServer; small
## Session and reliable-transport ports. No MAIN wiring, Store writes or ENet.
## Pilot placements and explicitly labelled invalid-pose saves are QA fixtures.
const Adapter = preload("res://scripts/v3/gameplay/twin_shared_access_session.gd")
const Bridge = preload("res://scripts/v3/world/twin_shared_access_bridge.gd")
const World = preload("res://scripts/v3/twin_test_world.gd")
const Body = preload("res://scripts/v2/flight_body.gd")
const Catalog = preload("res://scripts/v2/catalog.gd")
const Rules = preload("res://scripts/v3/gameplay/twin_ability_rules.gd")
var host
var world
var body
var adapter
var client
var guest
var guest_view
var rules = Rules.new()
var checks: Array[Dictionary] = []
var failures: Array[String] = []
var finished := false
var initial: Dictionary = {}
var service_packet: Dictionary = {}

class NetworkPort extends RefCounted:
	var mode := "solo"
	var session_id := "qa-shared-access-session"
	var guests: Dictionary = {2:{}}
	var events: Array[Dictionary] = []
	func is_authority() -> bool: return mode != "guest"
	func send_event(peer: int, event: Dictionary) -> void: events.append({"peer":peer, "event":event.duplicate(true)})

class SessionPort extends Node3D:
	var network = NetworkPort.new()
	var region_id := "I1"
	var active := true
	var owns_world := true
	var simulation_paused := false
	var received_session := ""
	var players: Dictionary = {}
	var entities: Dictionary = {}
	var writes := 0
	var notes: Array = []
	func _commit(_receipt: String, _changes: Dictionary) -> bool:
		writes += 1
		return false
	func _apply_pause_state() -> void: pass
	func _note_all(message: String) -> void: notes.append(message)

class ErrorLog extends Logger:
	var errors: Array = []
	func _log_error(fn: String, file: String, line: int, code: String, reason: String, _notify: bool, kind: int, _traces: Array[ScriptBacktrace]) -> void:
		errors.append({"function":fn, "file":file, "line":line, "code":code, "reason":reason, "kind":kind})
var logger = ErrorLog.new()

func _init() -> void:
	OS.add_logger(logger)
	_run.call_deferred()

func _check(ok: bool, label: String, details: Variant = null) -> void:
	checks.append({"passed":ok, "label":label, "details":details})
	if not ok: failures.append(label)

func _healthy() -> bool:
	return not finished and failures.is_empty() and logger.errors.is_empty()

func _run() -> void:
	create_timer(100).timeout.connect(func():
		if not finished:
			_check(false, "bounded fixture timeout")
			_finish())
	host = SessionPort.new()
	root.add_child(host)
	adapter = Adapter.new()
	adapter.setup(host)
	_prepare_boundaries()
	if _healthy(): await _start_world()
	if _healthy(): await _confirmation_and_real_motion()
	if _healthy(): await _restore_and_freeze()
	if _healthy(): await _network_barrier()
	_finish()

func _prepare_boundaries() -> void:
	var before: Dictionary = adapter.persistent_state()
	var away: Dictionary = adapter.prepare({}, "I1", true)
	_check(away.ok and away.module == null and away.state.is_empty() and not away.needs_init, "unvisited absent bridge creates no off-region module")
	adapter.adopt(away, {})
	_check(adapter.ready and adapter.persistent_state().is_empty(), "unvisited authority is lifecycle ready without a fabricated save")
	for state in [
		{"completed_objectives":[Adapter.OBJECTIVE]},
		{"actions":{"opening":{"completed":[Adapter.OBJECTIVE]}}},
		{"flags":{Adapter.FLAG:true}},
		{"actions":{"opening":{"choices":{Adapter.OBJECTIVE:"public_span"}}}}
	]:
		var refused: Dictionary = adapter.prepare(state, "I2", true)
		_check(not refused.ok and refused.error == "shared_access_missing_mechanism", "each current-world result prevents absent mechanism reset", state)
	var prior_discovery: Dictionary = adapter.prepare({}, "I2", true, [Adapter.DISCOVERY])
	_check(prior_discovery.ok and prior_discovery.needs_init, "cross-branch personal discovery alone permits fresh current-world bridge")
	var detached = prior_discovery.module
	adapter.discard(prior_discovery)
	_check(not is_instance_valid(detached), "discard frees only its own detached candidate")
	for bad in [{"environment":{"I2_shared_access":null}}, {"flags":{Adapter.FLAG:1}}, {"actions":{"opening":{"choices":{Adapter.OBJECTIVE:"invented"}}}}]:
		_check(not adapter.prepare(bad, "F1", true).ok, "malformed state is rejected even while away", bad)
	_check(adapter.persistent_state() == before and adapter.retry_pending() and adapter.pending_retry() and not adapter.has_pending_observation() and host.writes == 0, "prepare and retry create no hidden choice/Store writer")

func _start_world() -> void:
	var prepared: Dictionary = adapter.prepare({}, "I2", true)
	_check(prepared.ok and prepared.module.get_parent() == null and prepared.needs_init, "initial bridge is prepared detached for caller-owned commit")
	if not prepared.ok: return
	world = World.new()
	host.add_child(world)
	world.build("I2", {}, true, {"shared_access":prepared.module})
	_check(world.build_errors.is_empty(), "actual production I2 builds using the one prepared bridge", world.build_errors)
	if not world.build_errors.is_empty():
		adapter.discard(prepared)
		return
	host.region_id = "I2"
	var bridges := 0
	for child in world.get_children():
		if child is Bridge: bridges += 1
	_check(bridges == 1 and world.shared_access == prepared.module, "production World adopts the prepared bridge without a second overlapping default")
	adapter.discard(prepared)
	_check(is_instance_valid(prepared.module), "discard never frees a World-owned candidate")
	adapter.adopt(prepared, {})
	_check(adapter.ready and adapter.epoch == 2 and adapter.serial >= 1, "host adopts real geometry and publishes a new epoch")
	for definition in adapter.module.target_definitions(): host.entities[definition.id] = definition
	body = Body.new()
	body.configure(Catalog.resolve_build(Catalog.default_build("tr01")))
	body.freeze = true
	body.position = Vector3(25, 10, 18)
	world.add_child(body)
	body.set_process(false)
	body.set_physics_process(false)
	host.players[1] = body
	adapter.sync_roster()
	initial = adapter.module.snapshot()
	await _settle()
	_check(adapter.module.access_report().choice_ready and _physical_matches(adapter.module), "initial real public bridge has both supported routes and immediate physics poses")
	var copy: Dictionary = adapter.persistent_state()
	copy.mechanism.axis.position_m = 8.0
	_check(adapter.module.snapshot().axis.position_m == 0.0, "returned persistent state never aliases live mechanism")

func _settle() -> void:
	await physics_frame
	await physics_frame

func _place(point: Vector3) -> void:
	body.global_transform = Transform3D(Basis.IDENTITY, point)
	body.linear_velocity = Vector3.ZERO
	body.angular_velocity = Vector3.ZERO
	body.force_update_transform()
	PhysicsServer3D.body_set_state(body.get_rid(), PhysicsServer3D.BODY_STATE_TRANSFORM, body.global_transform)
	await _settle()

func _step(delta: float) -> void:
	adapter.advance(delta)
	var timers: Dictionary = rules.advance_states(host.entities, delta)
	if not timers.ok or not rules.commit(timers, host.entities).ok:
		_check(false, "real ability expiry must advance with mechanism")
	await physics_frame

func _ability(ability: String, id: String) -> bool:
	var actor := "qa:shared-pilot"
	host.entities[actor] = {"id":actor, "owner":"1", "tags":["player"], "position":body.global_position, "energy":100.0, "health":100.0, "revision":0}
	var excluded: Array[RID] = [body.get_rid()]
	var query := PhysicsRayQueryParameters3D.create(body.global_position, adapter.module.entity_position(id), 0xFFFFFFFF, excluded)
	var hit: Dictionary = world.get_world_3d().direct_space_state.intersect_ray(query)
	var visible: bool = not hit.is_empty() and hit.collider == adapter.module.target_bodies[id]
	var result: Dictionary = rules.resolve({"ability":ability, "actor_id":actor, "target_id":id, "mode":""}, host.entities, {"sender_id":"1", "line_of_sight":visible})
	return result.ok and rules.commit(result, host.entities, true).ok

func _obstacle(at: Vector3, size: Vector3) -> StaticBody3D:
	var prop := StaticBody3D.new()
	prop.name = "ConfirmationObstruction"
	prop.position = at
	prop.collision_layer = 1
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	collision.shape = shape
	prop.add_child(collision)
	world.add_child(prop)
	return prop

func _confirmation_ray(mode: String) -> Dictionary:
	var anchor: Dictionary = adapter.choice_anchor(mode)
	var excluded: Array[RID] = [body.get_rid()]
	var query := PhysicsRayQueryParameters3D.create(body.global_position, anchor.position, 0xFFFFFFFF, excluded)
	var hit: Dictionary = world.get_world_3d().direct_space_state.intersect_ray(query)
	return {"observer":str(body.global_position), "target":str(anchor.position),
		"first_collider":"" if hit.is_empty() else str(hit.collider.get_path()),
		"hit_position":"" if hit.is_empty() else str(hit.position),
		"hits_target":not hit.is_empty() and hit.get("rid") == adapter.module.target_bodies[anchor.target_id].get_rid()}

func _confirmation_and_real_motion() -> void:
	_check(adapter.choice_anchor("unknown").is_empty() and not adapter.choice_confirmation(1, "unknown").ok, "unknown mode cannot choose arbitrary target or mode")
	_check(not adapter.choice_confirmation(9, "public_span").ok and not adapter.choice_confirmation(1, "public_span").ok, "unknown peer and distant actual pilot cannot confirm")
	var public_anchor: Dictionary = adapter.choice_anchor("public_span")
	_check(public_anchor.target_id == Bridge.PUBLIC_CONTROL and public_anchor.position == adapter.module.entity_position(Bridge.PUBLIC_CONTROL), "anchor is the actual module controller, not a fabricated task point")
	# The original east/outside fixture looks through the outer guard rail. Keep
	# that real refusal as evidence; observe the inward-facing controls from the
	# unobstructed high side of the actual landing, as the motor ability test does.
	await _place(Vector3(23.5, 5.97, 3.25))
	var outside: Dictionary = _confirmation_ray("public_span")
	_check(outside.first_collider.ends_with("/EastOuterRail") and adapter.choice_confirmation(1, "public_span").code == "shared_access_obstructed", "outside horizontal fixture is genuinely blocked by the outer guard rail", outside)
	for airframe in ["tr01", "hx02"]:
		body.configure(Catalog.resolve_build(Catalog.default_build(airframe)))
		# Route clearance reaches Y7.81 including its floor offset; hovering above
		# that space keeps the observer from blocking the route being inspected.
		await _place(Vector3(19.7, 8.6, 3.25))
		var choice: Dictionary = adapter.choice_confirmation(1, "public_span")
		_check(choice.ok and choice.mode == "public_span" and choice.access.public_access and choice.access.service_access, "real " + airframe + " can inspect and confirm the public configuration", {"choice":choice, "ray":_confirmation_ray("public_span")})
		if not choice.ok: return
		_check(choice.state == adapter.persistent_state() and choice.fact == {"kind":"fact", "target":Adapter.FACT, "option":"public_span"}, "confirmation returns latest mechanism and only a validated fact")
	body.enabled = false
	_check(not adapter.choice_confirmation(1, "public_span").ok, "disabled pilot cannot confirm")
	body.enabled = true
	var fake := Node3D.new()
	world.add_child(fake)
	host.players[2] = fake
	_check(not adapter.choice_confirmation(2, "public_span").ok, "a positioned non-FlightBody cannot impersonate an observer")
	host.players.erase(2)
	fake.free()
	# Beyond HX's actual right extent x20.8, but before controller west face
	# x21.24; this tests a ray obstruction without occupying the pilot itself.
	var blocker := _obstacle(Vector3(21.0, 6.463, 3.25), Vector3(.1, .12, .3))
	await _settle()
	_check(adapter.choice_confirmation(1, "public_span").code == "shared_access_obstructed", "real opaque collider blocks controller first-hit confirmation")
	blocker.free()
	await _settle()
	var prepared: Dictionary = adapter.choice_confirmation(1, "public_span")
	_check(prepared.ok, "unobstructed proposal can be prepared")
	blocker = _obstacle(Vector3(15, 6.0, 0), Vector3(.2, .2, .2))
	await _settle()
	_check(adapter.choice_confirmation(1, "public_span").code == "shared_access_route_blocked", "new route obstruction invalidates final commit-time recheck even after a successful proposal")
	_check(prepared.ok and prepared.state == adapter.persistent_state(), "stale proposal does not mutate or rewind the physical bridge")
	blocker.free()
	await _settle()
	var unlocked: Dictionary = adapter.module.snapshot()
	unlocked.pin.position_m = 0.0
	_check(adapter.module.apply_snapshot(unlocked).ok, "declared unlocked-pose fixture retains real geometry")
	_check(adapter.choice_confirmation(1, "public_span").code == "shared_access_not_locked_here", "endpoint without inserted pin cannot be confirmed")
	_check(adapter.module.apply_snapshot(initial).ok, "restore original public starting pose for actual motor operation")
	adapter.sync_roster()
	await _step(.01) # Observes released stale controllers after restore.
	body.configure(Catalog.resolve_build(Catalog.default_build("tr01")))
	await _place(Vector3(19.7, 7.1, 3.5))
	_check(_ability("charge", Bridge.RELAY), "actual LOS/Rules charge the bridge relay")
	_check(_ability("takeover", Bridge.SERVICE_CONTROL), "actual LOS/Rules authorize the service controller")
	var count := 0
	while count < 160 and adapter.module.status().mode != "service_span":
		await _step(.05)
		count += 1
		if not _healthy(): return
	_check(adapter.module.status().mode == "service_span" and adapter.module.status().locked, "real motor retracts pin, traverses eight metres and inserts the service lock", adapter.module.status())
	await _place(Vector3(19.7, 7.1, 3.75))
	_check(adapter.choice_confirmation(1, "service_span").code == "shared_access_route_blocked", "low observer occupying the required public bypass prevents confirmation", adapter.module.access_report())
	for airframe in ["tr01", "hx02"]:
		body.configure(Catalog.resolve_build(Catalog.default_build(airframe)))
		await _place(Vector3(19.7, 8.6, 3.75))
		var choice: Dictionary = adapter.choice_confirmation(1, "service_span")
		_check(choice.ok and choice.access.routes.service_short.length_m < choice.access.routes.service_bypass.length_m, "real " + airframe + " confirms a physically shorter service route", {"choice":choice, "ray":_confirmation_ray("service_span")})
		if not choice.ok: return
	_check(not adapter.choice_confirmation(1, "public_span").ok, "caller cannot name the other configuration to fabricate its fact")
	var grip = adapter.module.moving_bodies.BridgeHandle
	grip.position.x += .1
	_check(adapter.choice_confirmation(1, "service_span").code == "shared_access_pose", "manual scene-node tampering cannot bypass actual pose contract")
	grip.position.x -= .1
	await _settle()
	_check(host.writes == 0 and not adapter.has_pending_observation() and adapter.retry_pending(), "all successful and refused choices leave Store/rewards to caller")
	adapter.publish()
	service_packet = host.network.events[-1].event.duplicate(true)

func _restore_and_freeze() -> void:
	await _place(Vector3(25, 10, 18))
	var moving: Dictionary = initial.duplicate(true)
	moving.axis.position_m = 4.0
	moving.axis.velocity_mps = 1.25
	moving.axis.last_serial = {"1":77}
	moving.pin.position_m = 0.0
	moving.pin.last_serial = {"1":75}
	moving.serial = 50
	var raw_world: Dictionary = {"environment":{"I2_shared_access":Adapter._envelope(moving)}}
	var original: Dictionary = raw_world.duplicate(true)
	var prepared: Dictionary = adapter.prepare(raw_world, "I2", true)
	_check(prepared.ok and prepared.stopped and prepared.state.mechanism.axis.position_m == 4.0 and prepared.state.mechanism.axis.velocity_mps == 0.0 and prepared.state.mechanism.axis.last_serial.is_empty() and prepared.state.mechanism.pin.last_serial.is_empty(), "host detached reconstruction clears old velocity/input roster while retaining exact bridge position")
	_check(raw_world == original, "authority normalization never mutates saved input")
	if not prepared.ok: return
	adapter.discard(prepared)
	var bad: Dictionary = original.duplicate(true)
	bad.environment.I2_shared_access.mechanism.pin.position_m = .3
	_check(not adapter.prepare(bad, "F1", true).ok, "invalid pin alignment rejects even outside I2")
	bad = original.duplicate(true)
	bad.environment.I2_shared_access.mechanism.extra = true
	_check(not adapter.prepare(bad, "I2", true).ok, "unknown saved mechanism keys reject atomically")
	var away: Dictionary = adapter.prepare(raw_world, "F1", true)
	_check(away.ok and away.module == null and away.state.mechanism.axis.position_m == 4.0, "off-region retains validated stopped mechanism without hidden simulation")
	var old = adapter.module
	host.region_id = "F1"
	adapter.adopt(away, raw_world)
	old.get_parent().remove_child(old)
	old.free()
	var retained: Dictionary = adapter.persistent_state()
	for unused in range(3): adapter.advance(1.0)
	_check(adapter.persistent_state() == retained and adapter.choice_anchor("public_span").is_empty(), "off-region time cannot move bridge or offer an imaginary anchor")
	prepared = adapter.prepare(raw_world, "I2", true)
	host.region_id = "I2"
	world.add_child(prepared.module)
	adapter.adopt(prepared, raw_world)
	adapter.sync_roster()
	# Previous authorized controller remains present in the Session entity map.
	# A restored host must require its release instead of continuing old control.
	host.entities[Bridge.RELAY].powered = true
	host.entities[Bridge.SERVICE_CONTROL].controlled = true
	host.entities[Bridge.SERVICE_CONTROL].owner = "1"
	host.entities[Bridge.SERVICE_CONTROL].takeover_remaining = 8.0
	adapter.advance(.25)
	_check(adapter.module.snapshot().axis.position_m == 4.0 and not adapter.module.status().motor_active, "restored mechanism cannot resume stale takeover ownership")
	host.entities[Bridge.SERVICE_CONTROL].controlled = false
	host.entities[Bridge.SERVICE_CONTROL].takeover_remaining = 0.0
	adapter.advance(.01)
	var before: Dictionary = adapter.module.snapshot()
	adapter.advance(0.0)
	_check(adapter.module.snapshot() == before, "zero delta neither accumulates time nor changes mechanism serial")
	_check(adapter.module.apply_authorized_impulse(Bridge.HANDLE, Vector3.BACK * 9, 1, 80).ok, "real restored axis accepts a fresh bounded impulse")
	adapter.set_paused(true)
	host.simulation_paused = true
	before = adapter.module.snapshot()
	adapter.advance(.25)
	_check(before.axis.velocity_mps == 0.0 and adapter.module.snapshot() == before, "pause clears accepted velocity without accumulating delayed movement")
	adapter.set_paused(false)
	host.simulation_paused = false
	adapter.advance(.25)
	_check(adapter.module.snapshot().axis.position_m == 4.0, "resume does not release pre-pause impulses")
	await _settle()

func _network_barrier() -> void:
	guest_view = SubViewport.new()
	guest_view.own_world_3d = true
	guest_view.size = Vector2i(2, 2)
	guest_view.render_target_update_mode = SubViewport.UPDATE_DISABLED
	root.add_child(guest_view)
	guest = SessionPort.new()
	guest.network.mode = "guest"
	guest.owns_world = false
	guest.region_id = "I2"
	guest.simulation_paused = true
	guest_view.add_child(guest)
	client = Adapter.new()
	client.setup(guest)
	var prepared: Dictionary = client.prepare({}, "I2", false)
	guest.add_child(prepared.module)
	client.adopt(prepared, {})
	for definition in client.module.target_definitions(): guest.entities[definition.id] = definition
	await _settle()
	var before: Dictionary = client.module.snapshot()
	var foreign: Dictionary = service_packet.duplicate(true)
	foreign.session_id = "another-session"
	foreign.epoch = 800
	foreign.serial = 800
	client.receive(foreign)
	client.receive(service_packet)
	_check(not client.ready and client.module.snapshot() == before, "early reliable events cannot establish connection identity or readiness")
	guest.received_session = service_packet.session_id
	_check(client.consume(int(service_packet.serial), int(service_packet.epoch), "I2") and client.ready, "motion reference binds identity and applies its exact reliable bridge state")
	_check(Adapter._same(client.module.snapshot(), service_packet.state.mechanism) and _physical_matches(client.module), "first paused frame restores exact bridge/pin collision before ready")
	var hit := _deck_hit(client.module)
	_check(not hit.is_empty() and hit.collider == client.module.moving_bodies.BridgeDeck, "real first-frame ray hits the moved deck at its saved service position")
	var newer: Dictionary = service_packet.duplicate(true)
	newer.serial += 1
	before = client.module.snapshot()
	_check(not client.consume(int(newer.serial), int(newer.epoch), "I2") and not client.ready, "new motion reference waits for that exact reliable serial")
	client.receive(service_packet)
	_check(not client.ready and client.module.snapshot() == before, "late old state cannot release the newer serial barrier")
	client.receive(newer)
	_check(client.ready and client.module.snapshot() == before, "matching reliable serial releases unchanged real geometry")
	var corrupt: Dictionary = newer.duplicate(true)
	corrupt.serial += 1
	corrupt.state.mechanism.axis.position_m = 9.0
	client.consume(int(corrupt.serial), int(corrupt.epoch), "I2")
	client.receive(corrupt)
	_check(not client.ready and client.module.snapshot() == before and _physical_matches(client.module), "invalid whole snapshot cannot partially move collision or publish ready")
	var repair: Dictionary = newer.duplicate(true)
	repair.serial = corrupt.serial
	client.receive(repair)
	_check(client.ready, "valid exact replacement can recover after rejected corrupted payload")
	var mismatch: Dictionary = repair.duplicate(true)
	mismatch.serial += 1
	mismatch.state.mechanism.blocked = not mismatch.state.mechanism.blocked
	client.consume(int(mismatch.serial), int(mismatch.epoch), "I2")
	client.receive(mismatch)
	_check(not client.ready and client.module.snapshot() == before, "equal mechanism serial cannot smuggle a different mechanism state")
	var branch: Dictionary = service_packet.duplicate(true)
	branch.serial = int(mismatch.serial) + 1
	branch.epoch += 1
	branch.state = Adapter._envelope(initial)
	client.receive(branch)
	_check(not client.ready, "future branch event waits for the motion epoch")
	_check(client.consume(int(branch.serial), int(branch.epoch), "I2") and client.ready and client.module.snapshot().axis.position_m == 0.0, "new branch epoch may restore older legitimate public geometry")
	_check(not client.consume(int(repair.serial), int(repair.epoch), "I2"), "previous-epoch motion cannot rewind the new branch")
	var old = client.module
	client.clear()
	guest.remove_child(old)
	old.free()
	prepared = client.prepare({}, "I2", false)
	guest.add_child(prepared.module)
	client.adopt(prepared, {})
	_check(not client.ready, "same-epoch local view rebuild starts behind barrier")
	_check(client.consume(int(branch.serial), int(branch.epoch), "I2") and client.ready and _physical_matches(client.module), "cached exact state reconstructs same-epoch paused view without requiring a new host publication")
	before = client.module.snapshot()
	client.advance(.25)
	client.set_paused(true)
	client.set_paused(false)
	_check(client.module.snapshot() == before and not client.choice_confirmation(1, "public_span").ok, "guest cannot advance or authorize choices even with complete geometry")
	var stream: Dictionary = branch.duplicate(true)
	for i in range(12):
		stream.serial = int(branch.serial) + i + 1
		stream.epoch = int(branch.epoch) + 1
		client.receive(stream)
	_check(client.pending_network.size() == Adapter.MAX_PENDING_PACKETS, "future reliable packet cache remains bounded")
	client.reset_connection()
	_check(client.pending_network.is_empty() and client.serial == 0 and client.epoch == 0 and client.expected_epoch == -1, "connection reset clears identity, epochs and caches")
	guest.received_session = "replacement-host"
	old = guest.get_child(0)
	guest.remove_child(old)
	old.free()
	prepared = client.prepare({}, "I2", false)
	guest.add_child(prepared.module)
	client.adopt(prepared, {})
	var connected: Dictionary = branch.duplicate(true)
	connected.session_id = guest.received_session
	connected.epoch = 1
	connected.serial = 1
	client.receive(branch)
	_check(not client.consume(1, 1, "I2"), "old host event is rejected after explicit reconnect")
	client.receive(connected)
	_check(client.ready and client.applied_serial == 1 and _physical_matches(client.module), "new host can start low counters only after reset and actual collision reconstruction")

func _physical_matches(bridge) -> bool:
	for collection in [bridge.moving_bodies, bridge.pin_bodies]:
		for value in collection.values():
			var actual: Transform3D = PhysicsServer3D.body_get_state(value.get_rid(), PhysicsServer3D.BODY_STATE_TRANSFORM)
			if not actual.is_equal_approx(value.global_transform): return false
	return bridge.status().pose_valid

func _deck_hit(bridge) -> Dictionary:
	var at: Vector3 = bridge.moving_bodies.BridgeDeck.global_position
	return bridge.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(at + Vector3.UP * 2, at, 0xFFFFFFFF))

func _finish() -> void:
	if finished: return
	finished = true
	_check(logger.errors.is_empty(), "no engine errors", logger.errors)
	print("SHARED_ACCESS_SESSION_RESULT " + JSON.stringify({"checks":checks.size(), "failures":failures, "results":checks, "engine_errors":logger.errors,
		"scope":"actual production World/Bridge/Rules/PhysicsServer; Session and reliable transport ports; no MAIN wiring, Store, LAN, rendering or playthrough"}))
	if adapter != null: adapter.clear()
	if client != null: client.clear()
	if is_instance_valid(guest_view): guest_view.free()
	if is_instance_valid(host): host.free()
	OS.remove_logger(logger)
	quit(0 if failures.is_empty() else 1)
