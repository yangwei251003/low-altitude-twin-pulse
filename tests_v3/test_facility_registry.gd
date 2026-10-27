extends SceneTree
## Real four adapters, their physical modules and one isolated Store. Network
## is an in-memory transport port: this is NOT MAIN, ENet or a playthrough.
## Direct impulses below are explicit physical-caller fixtures, not F-key/LOS
## evidence. Existing MAIN tests remain responsible for Rules/energy ordering.
const Registry = preload("res://scripts/v3/gameplay/twin_facility_registry.gd")
const Store = preload("res://scripts/v3/core/twin_world_store.gd")
const Rules = preload("res://scripts/v3/gameplay/twin_ability_rules.gd")
const Consensus = preload("res://scripts/v3/core/twin_consensus.gd")
const Body = preload("res://scripts/v2/flight_body.gd")
const Catalog = preload("res://scripts/v2/catalog.gd")
var checks: Array[Dictionary] = []
var failures: Array[String] = []
var done := false
var host
var guest
var registry = Registry.new()
var client = Registry.new()
var adapters: Dictionary = {}
var clients: Dictionary = {}
var world: Node3D
var guest_view: SubViewport
var body
var profile := ""

class NetworkPort extends RefCounted:
	var mode := "solo"
	var session_id := "qa-facility-registry"
	var guests: Dictionary = {2:{}}
	var events: Dictionary = {}
	func is_authority() -> bool: return mode != "guest"
	func send_event(_peer: int, event: Dictionary) -> void: events[event.kind] = event.duplicate(true)

class SessionPort extends Node3D:
	var network = NetworkPort.new()
	var consensus = Consensus.new()
	var rules = Rules.new()
	var region_id := "I1"
	var active := true
	var owns_world := true
	var simulation_paused := false
	var received_session := ""
	var _resolving_decision := false
	var entities: Dictionary = {}
	var players: Dictionary = {}
	var world_cache: Dictionary = {}
	var store
	func _commit(receipt: String, changes: Dictionary, _discovery: String = "") -> bool:
		var result: Dictionary = store.commit({"id":receipt+":"+str(store.snapshot().generation), "set":changes})
		if result.ok: world_cache = store.snapshot()
		return bool(result.ok)
	func _persistent_environment() -> Dictionary: return {}
	func _note(_peer: int, _message: String) -> void: pass
	func _note_all(_message: String) -> void: pass
	func _apply_pause_state() -> void: pass

class ErrorLog extends Logger:
	var errors: Array = []
	func _log_error(fn: String, file: String, line: int, code: String, reason: String, _notify: bool, kind: int, _traces: Array[ScriptBacktrace]) -> void:
		errors.append({"function":fn,"file":file,"line":line,"code":code,"reason":reason,"kind":kind})
var logger = ErrorLog.new()

func _init() -> void:
	OS.add_logger(logger)
	_run.call_deferred()

func check(ok: bool, label: String, detail: Variant = null) -> void:
	checks.append({"passed":ok, "label":label, "detail":detail})
	if not ok: failures.append(label)

func _run() -> void:
	var profile_count := 0
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--qa-profile="):
			profile = arg.trim_prefix("--qa-profile=")
			profile_count += 1
		elif arg.begins_with("--qa-network") or arg.begins_with("--qa-capture") or arg.begins_with("--qa-suite"):
			check(false, "isolated test refuses socket/capture/suite drivers")
	var base: String = "user://qa_v3_facility_registry/" + profile
	if profile_count != 1 or not profile.begins_with("qa_facility_registry_") or profile != profile.validate_filename():
		check(false, "one fresh qa_facility_registry_ profile is required")
	elif DirAccess.dir_exists_absolute(base) or DirAccess.dir_exists_absolute("user://profiles_v3/" + profile):
		check(false, "existing profiles are never opened")
	if not failures.is_empty():
		_finish()
		return
	create_timer(120.0).timeout.connect(func():
		if not done:
			check(false, "bounded registry fixture timeout")
			_finish())
	_registration()
	host = SessionPort.new()
	root.add_child(host)
	host.store = Store.new(base)
	var loaded: Dictionary = host.store.load_profile()
	check(loaded.ok, "real isolated Store opens", loaded)
	host.world_cache = host.store.snapshot()
	host.consensus.configure([1], int(host.world_cache.world_revision))
	adapters = _new_adapters()
	var incomplete: Dictionary = adapters.duplicate()
	incomplete.erase("shared_access")
	check(not Registry.new().setup(host, incomplete).ok, "setup refuses a three-instance registry missing the real bridge adapter")
	check(registry.setup(host, adapters).ok, "fixed table binds all four real adapter instances")
	check(not registry.setup(host, adapters).ok, "setup cannot silently replace a live registry")
	await _prepare_and_adopt()
	if _healthy(): await _authority_and_pause()
	if _healthy(): await _four_streams()
	if _healthy(): await _off_region()
	_finish()

func _registration() -> void:
	var original: Array = Registry.definitions()
	check(Registry.validate_definitions(original).ok, "production registration has unique identities, paths, targets and slots")
	for key in ["id", "path", "slot", "event", "serial_key"]:
		var bad: Array = original.duplicate(true)
		bad[1][key] = bad[0][key]
		check(not Registry.validate_definitions(bad).ok, "conflicting registration rejected: " + key)
	var bad: Array = original.duplicate(true)
	bad[1].targets.append(bad[0].targets[0])
	check(not Registry.validate_definitions(bad).ok, "two facilities cannot claim one ability target")
	bad = original.duplicate(true)
	bad[2].impulses.append("I2:unowned")
	check(not Registry.validate_definitions(bad).ok and original == Registry.definitions(), "unowned impulse rejected without mutating fixed definitions")

func _new_adapters() -> Dictionary:
	return {"clinic":Registry.Clinic.new(), "distribution":Registry.Distribution.new(), "trial":Registry.Trial.new(), "shared_access":Registry.SharedAccess.new()}

func _healthy() -> bool:
	return not done and failures.is_empty() and logger.errors.is_empty()

func _prepare_and_adopt() -> void:
	var before: Dictionary = host.store.snapshot()
	var outside: Dictionary = registry.prepare(before.world, "I1", true, [])
	check(outside.ok and outside.initialization.is_empty() and outside.states.is_empty(), "unvisited missing facilities need no eager persistence or physical scene")
	if not outside.ok: return
	check(registry.adopt(outside, before.world).ok and registry.all_ready("I1"), "initial I1 lifecycle does not demand an absent I2 scene")
	var prepared: Dictionary = registry.prepare(before.world, "I2", true, [])
	check(prepared.ok, "all four real preparations succeed through their distinct signatures", prepared.get("error"))
	if not prepared.ok: return
	check(prepared.initialization.size() == 4 and prepared.states.keys() == prepared.initialization.keys() and host.store.snapshot() == before, "prepare returns four existing envelope paths without writing or adopting")
	check(not registry.adopt(prepared, before.world).ok, "unattached/wrong-region candidate is rejected before any live adoption")
	var detached: Array = prepared.modules.values()
	registry.discard(prepared)
	var all_freed := true
	for node in detached:
		if is_instance_valid(node): all_freed = false
	check(all_freed and adapters.clinic.module == null and adapters.distribution.module == null and adapters.trial.module == null and adapters.shared_access.module == null, "discard frees only detached candidates and preserves all current adapters")
	prepared = registry.prepare(before.world, "I2", true, [])
	check(prepared.ok, "candidate can be prepared again after discard")
	if not prepared.ok: return
	host.store.failure_point = "before_publish"
	check(not host._commit("facilities-fixture", prepared.initialization) and host.store.snapshot() == before, "caller transaction failure writes no partial facility generation")
	registry.discard(prepared)
	host.store.failure_point = ""
	prepared = registry.prepare(before.world, "I2", true, [])
	check(prepared.ok and host._commit("facilities-fixture", prepared.initialization), "caller commits all initial envelopes in one real Store transaction")
	if not prepared.ok: return
	check(int(host.store.snapshot().generation) == int(before.generation) + 1, "initialization has one Store commit point")
	host.region_id = "I2"
	world = _attach(host, prepared)
	registry.discard(prepared)
	check(prepared.modules.values().all(func(node): return is_instance_valid(node) and node.get_parent() == world), "discard leaves attached candidate children to their owning World")
	var adopted: Dictionary = registry.adopt(prepared, host.world_cache.world)
	check(adopted.ok and registry.all_ready("I2") and adapters.trial.module.connection_status().ok, "world-attached real modules adopt with Link and Station connected", adopted)
	body = Body.new()
	body.configure(Catalog.resolve_build(Catalog.default_build("tr01")))
	body.freeze = true
	body.position = Vector3(25,10,5)
	host.add_child(body)
	body.set_process(false)
	body.set_physics_process(false)
	host.players[1] = body
	registry.sync_roster()
	await physics_frame
	await physics_frame
	var patch: Dictionary = registry.persistent_states()
	check(patch.size() == 4 and patch.has("world.environment.I2_water") and patch.has("world.environment.I2_distribution") and patch.has("world.environment.I2_trial_flow") and patch.has(Registry.SharedAccess.STATE_PATH), "persistent patch retains four existing paths without a registry envelope")
	var corrupt: Dictionary = _world_with_states(host.world_cache.world, patch)
	corrupt.environment.I2_trial_flow.station.version = 1
	var rejected: Dictionary = registry.prepare(corrupt, "I2", true, [])
	check(not rejected.ok and registry.persistent_states() == patch and registry.all_ready("I2"), "late strict Trial failure discards earlier preparations without replacing live modules")
	corrupt = _world_with_states(host.world_cache.world, patch)
	corrupt.environment.I2_shared_access.mechanism.layout_sha256 = "unknown-bridge"
	rejected = registry.prepare(corrupt, "I2", true, [])
	check(not rejected.ok and registry.persistent_states() == patch and registry.all_ready("I2"), "fourth strict bridge failure discards preceding three candidates without replacing live modules")

func _attach(port, prepared: Dictionary) -> Node3D:
	var container := Node3D.new()
	container.name = "FacilityFixtureWorld"
	port.add_child(container)
	port.entities.clear()
	for id in Registry.IDS:
		var module: Node3D = prepared.modules[id]
		if module == null: continue
		container.add_child(module)
		for definition in module.target_definitions(): port.entities[definition.id] = definition
	return container

func _authority_and_pause() -> void:
	check(registry.owner_for_target("I2:trial_relay") == "trial" and registry.impulse_owner("I2:trial_relay").is_empty() and registry.impulse_owner("I2:trial_selector") == "trial", "ability ownership and impulse ownership remain exact and distinct")
	check(registry.impulse_owner(Registry.SharedAccess.Bridge.PIN) == "shared_access" and registry.impulse_owner(Registry.SharedAccess.Bridge.HANDLE) == "shared_access" and registry.owner_for_target(Registry.SharedAccess.Bridge.RELAY) == "shared_access" and registry.impulse_owner(Registry.SharedAccess.Bridge.RELAY).is_empty(), "bridge grip/pin and electrical relay have distinct exact registered routes")
	check(registry.owner_for_target("I2:unknown").is_empty() and not registry.can_accept_impulse("I2:unknown", Vector3.RIGHT, 1, 1).ok, "unknown I2 prefix never grants an impulse route")
	for id in ["I2:clinic_gravity_valve", "I2:distribution_cover", "I2:trial_isolation_handle"]:
		var accepted: Dictionary = registry.can_accept_impulse(id, Vector3.RIGHT, 1, 1)
		check(accepted.ok, "real roster permits explicit physical fixture impulse: " + id, accepted)
		if not accepted.ok: return
		check(registry.apply_authorized_impulse(id, Vector3.RIGHT, 1, 1).ok, "registry dispatches to the sole real mechanical owner: " + id)
		check(not registry.apply_authorized_impulse(id, Vector3.RIGHT, 1, 1).ok, "module retains its real same-serial replay rejection: " + id)
	check(registry.can_accept_impulse(Registry.SharedAccess.Bridge.PIN, Vector3.UP * 9, 1, 1).ok and registry.apply_authorized_impulse(Registry.SharedAccess.Bridge.PIN, Vector3.UP * 9, 1, 1).ok, "fourth module receives actual upward pin impulse through the registry")
	registry.advance(0.5)
	await physics_frame
	check(float(adapters.clinic.module.snapshot().axis.position_m) > 0.0 and float(adapters.distribution.module.snapshot().axis.position_m) > 0.0 and float(adapters.trial.module.snapshot().link.axis.position_m) > 0.0, "one lifecycle advance moves three independent real mechanisms")
	check(adapters.shared_access.module.snapshot().pin.position_m == 0.0, "real bridge lock physically retracts before the deck can move")
	check(registry.can_accept_impulse(Registry.SharedAccess.Bridge.HANDLE, Vector3.BACK * 9, 1, 2).ok and registry.apply_authorized_impulse(Registry.SharedAccess.Bridge.HANDLE, Vector3.BACK * 9, 1, 2).ok, "registry grants bridge movement only after actual lock clearance")
	registry.advance(0.1)
	await physics_frame
	check(adapters.shared_access.module.snapshot().axis.position_m > 0.0 and _poses(adapters), "fourth real deck moves and PhysicsServer follows its actual transform")
	host.simulation_paused = true
	registry.set_paused(true)
	var stopped: Dictionary = registry.persistent_states()
	registry.advance(0.2)
	check(registry.persistent_states() == stopped and _poses(adapters), "paused lifecycle preserves all mechanics and publishes their actual physical transforms")
	var before: Dictionary = host.store.snapshot()
	check(not registry.has_pending_observation() and registry.pending_retry() and host.store.snapshot() == before, "empty retry loop invents no observation, reward or save")
	registry.publish()
	var refs: Array = registry.wire_refs()
	check(host.network.events.size() == 4 and refs.size() == 4 and refs[0][0] == 1 and refs[1][0] == 2 and refs[2][0] == 3 and refs[3][0] == 4, "four reliable kinds use stable slot/epoch/serial wire references")
	check(registry.legacy_refs().size() == 8, "legacy eight-field query remains available only outside the wire packet")

func _four_streams() -> void:
	guest_view = SubViewport.new()
	guest_view.world_3d = World3D.new()
	guest_view.render_target_update_mode = SubViewport.UPDATE_DISABLED
	root.add_child(guest_view)
	guest = SessionPort.new()
	guest.network.mode = "guest"
	guest.owns_world = false
	guest.region_id = "I2"
	guest.simulation_paused = true
	guest.received_session = host.network.session_id
	guest_view.add_child(guest)
	clients = _new_adapters()
	check(client.setup(guest, clients).ok, "guest registry binds real independent adapters")
	var prepared: Dictionary = client.prepare({}, "I2", false, [])
	check(prepared.ok, "guest geometry prepares without host-authority migration")
	if not prepared.ok: return
	_attach(guest, prepared)
	check(client.adopt(prepared, {}).ok and not client.all_ready("I2"), "client preparation never grants physical readiness")
	await physics_frame
	await physics_frame
	var refs: Dictionary = {"facility_refs":registry.wire_refs()}
	client.receive(host.network.events.distribution_state)
	client.receive(host.network.events.trial_state)
	client.receive(host.network.events.shared_access_state)
	check(not client.consume_all(refs, "I2") and not clients.clinic.ready and clients.distribution.ready and clients.trial.ready and clients.shared_access.ready, "missing first stream blocks the pilot barrier but does not short-circuit the other three consumers")
	check(not client.receive({"kind":"unregistered_state"}), "unregistered reliable kind is not claimed")
	client.receive(host.network.events.clinic_state)
	check(client.consume_all(refs, "I2") and client.all_ready("I2") and _poses(clients), "all real reliable states reconstruct paused first-frame physics before the combined barrier opens")
	for id in Registry.IDS:
		check(clients[id].module.snapshot() == adapters[id].module.snapshot(), "guest receives exact live mechanism via existing adapter: " + id)
	var malformed: Dictionary = refs.duplicate(true)
	for row in malformed.facility_refs:
		if int(row[0]) == 3: row[2] = NAN
	check(not client.consume_all(malformed, "I2") and not client.all_ready("I2"), "invalid typed reference cannot leave the aggregate input barrier open from an older success")
	check(client.consume_all(refs, "I2"), "valid unchanged references recover without changing adapter acceptance rules")
	var before: Dictionary = client.persistent_states()
	client.advance(0.2)
	check(client.persistent_states() == before and not client.can_accept_impulse("I2:trial_selector", Vector3.RIGHT, 1, 2).ok, "guest loop neither simulates nor grants authority impulses")
	registry.publish()
	var next_refs: Dictionary = {"facility_refs":registry.wire_refs()}
	client.receive(host.network.events.clinic_state)
	client.receive(host.network.events.trial_state)
	client.receive(host.network.events.shared_access_state)
	check(not client.consume_all(next_refs, "I2") and not clients.distribution.ready and clients.clinic.ready and clients.trial.ready and clients.shared_access.ready, "missing second stream independently blocks all-ready while other three restore")
	client.receive(host.network.events.distribution_state)
	check(client.consume_all(next_refs, "I2"), "matching cabinet stream restores the four-way barrier")
	registry.publish()
	next_refs = {"facility_refs":registry.wire_refs()}
	client.receive(host.network.events.clinic_state)
	client.receive(host.network.events.distribution_state)
	client.receive(host.network.events.shared_access_state)
	check(not client.consume_all(next_refs, "I2") and not clients.trial.ready, "new exact Trial reference cannot use an older accepted reliable state")
	client.receive(host.network.events.trial_state)
	check(client.consume_all(next_refs, "I2"), "matching third reliable state releases the unchanged adapter barrier")
	registry.publish()
	next_refs = {"facility_refs":registry.wire_refs()}
	client.receive(host.network.events.clinic_state)
	client.receive(host.network.events.distribution_state)
	client.receive(host.network.events.trial_state)
	var bridge_before: Dictionary = clients.shared_access.module.snapshot()
	check(not client.consume_all(next_refs, "I2") and not client.all_ready("I2") and not clients.shared_access.ready and clients.clinic.ready and clients.distribution.ready and clients.trial.ready, "all original three streams are insufficient when the exact fourth bridge state is missing")
	check(clients.shared_access.module.snapshot() == bridge_before and _poses(clients), "missing bridge packet retains preceding valid real collision without unlocking pilot")
	client.receive(host.network.events.shared_access_state)
	check(client.consume_all(next_refs, "I2") and client.all_ready("I2") and _poses(clients), "actual fourth reliable state restores paused bridge collision before combined ready")
	check(clients.shared_access.module.snapshot() == adapters.shared_access.module.snapshot(), "fourth restored deck/pin snapshot exactly matches the real host")
	client.reset_connection()
	check(clients.clinic.pending.is_empty() and clients.distribution.pending_network.is_empty() and clients.trial.pending_network.is_empty() and clients.shared_access.pending_network.is_empty() and clients.clinic.epoch == 0 and clients.trial.serial == 0 and clients.shared_access.epoch == 0 and clients.shared_access.serial == 0, "connection reset clears all four independent reliable epochs/caches")

func _off_region() -> void:
	var saved: Dictionary = _world_with_states(host.world_cache.world, registry.persistent_states())
	var prepared: Dictionary = registry.prepare(saved, "I1", true, [])
	check(prepared.ok and is_instance_valid(prepared.modules.clinic) and prepared.modules.distribution == null and prepared.modules.trial == null and prepared.modules.shared_access == null, "off-region preparation keeps Clinic physics but no hidden cabinet/Trial/bridge nodes")
	if not prepared.ok: return
	registry.clear()
	host.remove_child(world)
	world.free()
	host.region_id = "I1"
	host.simulation_paused = false
	host.entities.clear()
	check(registry.adopt(prepared, saved).ok and is_instance_valid(adapters.clinic.background) and registry.all_ready("I1"), "Clinic retains its background World while stopped facilities retain only their state")
	await physics_frame
	await physics_frame
	var before: Dictionary = registry.persistent_states()
	var tick: int = int(before["world.environment.I2_water"].mechanism.runtime.simulation.tick)
	registry.advance(0.1)
	var after: Dictionary = registry.persistent_states()
	check(int(after["world.environment.I2_water"].mechanism.runtime.simulation.tick) > tick, "unfiltered advance preserves actual Clinic online background time")
	check(after["world.environment.I2_distribution"] == before["world.environment.I2_distribution"] and after["world.environment.I2_trial_flow"] == before["world.environment.I2_trial_flow"] and after[Registry.SharedAccess.STATE_PATH] == before[Registry.SharedAccess.STATE_PATH], "the same loop preserves cabinet, Trial and bridge off-region freeze")
	registry.reset_connection()
	check(registry.persistent_states().is_empty() and registry.legacy_refs().values().all(func(value): return value == 0), "host reset releases retained/background state and resets original references")

func _world_with_states(source: Dictionary, patch: Dictionary) -> Dictionary:
	var result: Dictionary = source.duplicate(true)
	if not result.has("environment"): result.environment = {}
	for path in patch: result.environment[str(path).trim_prefix("world.environment.")] = patch[path].duplicate(true)
	return result

func _poses(instances: Dictionary) -> bool:
	var clinic = instances.clinic.module
	var bodies: Array = clinic.moving_bodies.values() + [clinic.gravity_valve, clinic.pump_selector, clinic.interlock_bolt]
	bodies.append_array([instances.distribution.module.cover, instances.distribution.module.door])
	var assembly = instances.trial.module
	bodies.append_array(assembly.link.moving_bodies.values())
	bodies.append_array(assembly.station.selector_bodies.values())
	bodies.append_array(assembly.station.valve_bodies.values())
	bodies.append_array(assembly.station.float_bodies.values())
	bodies.append_array(instances.shared_access.module.moving_bodies.values())
	bodies.append_array(instances.shared_access.module.pin_bodies.values())
	for item in bodies:
		if not is_instance_valid(item): return false
		var actual: Transform3D = PhysicsServer3D.body_get_state(item.get_rid(), PhysicsServer3D.BODY_STATE_TRANSFORM)
		if not actual.is_equal_approx(item.global_transform): return false
	return assembly.connection_status().ok and instances.distribution.module._poses_match() and instances.shared_access.module.status().pose_valid

func _finish() -> void:
	if done: return
	done = true
	registry.reset_connection()
	client.reset_connection()
	if is_instance_valid(host): host.free()
	if is_instance_valid(guest_view): guest_view.free()
	check(logger.errors.is_empty(), "zero engine errors", logger.errors)
	print("FACILITY_REGISTRY_RESULT " + JSON.stringify({"checks":checks.size(), "failures":failures.size(), "results":checks, "errors":logger.errors, "scope":"real adapters/physics/Store with in-memory transport; no MAIN/ENet/GPU/playthrough"}))
	OS.remove_logger(logger)
	quit(0 if failures.is_empty() else 1)
