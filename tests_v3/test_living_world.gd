extends SceneTree
const Codec = preload("res://scripts/v3/network/twin_snapshot_codec.gd")
## Real session save/branch/service/remote presentation and route collision checks.
var session
var checks = 0
var failures: Array = []
var profile = ""
var route_envelopes: Dictionary = {}

func _initialize() -> void:
	create_timer(90.0).timeout.connect(func():
		push_error("Living world QA exceeded its 90-second deadline")
		quit(124))
	_run.call_deferred()

func _check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)
		push_error(label)

func _run() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--qa-profile="): profile = arg.trim_prefix("--qa-profile=")
	if not profile.begins_with("qa_ecology_") or profile != profile.validate_filename() or DirAccess.dir_exists_absolute("user://profiles_v3/" + profile):
		quit(2)
		return
	session = load("res://scenes/v3/main.tscn").instantiate()
	root.add_child(session)
	_check(session.start_flight("solo"), "solo boot with isolated ecology state")
	session.set_process(false)
	session.set_physics_process(false)
	session.inputs.set_process(false)
	session.inputs.set_physics_process(false)
	for body in session.players.values():
		body.freeze = true
		body.set_process(false)
		body.set_physics_process(false)
	await physics_frame
	await physics_frame
	await _corridors("I1")
	session.entities["I1:relay"].charge = 80.0
	var before_fantasy: Dictionary = session.ecology.simulation.get_actor("F1:pollinator_01")
	for i in range(140): session.ecology.advance(1.0)
	_check(int(session.ecology.facilities.deliveries) > 0 and int(session.ecology.facilities.coolant) > 0, "powered actual water route reaches cooling service")
	_check(session.ecology.simulation.get_actor("F1:pollinator_01").steps_completed > before_fantasy.steps_completed, "unseen F1 ecology continues during I1 play")
	_check(session.story._submit("talk", "npc:linlan", "rescue_brief"), "first story contact submits through production story transaction")
	_check(int(session.store.snapshot().world.ecology.last_event_serial) == session.ecology.last_event_serial and int(session.store.snapshot().world.ecology.simulation.tick) == 140, "story transaction includes latest ecology and facility changes")
	var weather_checkpoint: Dictionary = session.ecology.simulation.snapshot()
	var fronts: Array = []
	var maximum_storm = 0
	var storm_length = 0
	for second in range(140, 860):
		var sampled: Dictionary = weather_checkpoint.duplicate(true)
		sampled.tick = second
		session.ecology.simulation.restore(sampled)
		var weather = session.ecology.weather_for("I1")
		fronts.append(weather)
		storm_length = storm_length + 1 if weather == "storm" else 0
		maximum_storm = maxi(maximum_storm, storm_length)
	_check("clear" in fronts and "rain" in fronts and "storm" in fronts and maximum_storm <= 39, "seeded weather supplies calm and warning periods with bounded strong gusts")
	_check(fronts.slice(0, 360) != fronts.slice(360, 720), "successive weather fronts vary instead of repeating a fixed phase table")
	session.ecology.simulation.restore(weather_checkpoint)
	_check(session.ecology.simulation.snapshot() == weather_checkpoint, "weather inspection never advances persistent world or RNG")
	var before_pause: Dictionary = session.ecology.persistent_state()
	session.simulation_paused = true
	session.ecology.advance(5.0)
	_check(session.ecology.persistent_state() == before_pause, "pause freezes actors RNG stock and clock")
	session.simulation_paused = false
	var body = session.players[1]
	body.global_position = session.ecology.SERVICE_POSITION
	body.health = body.maximum_health - 40
	var stock = int(session.ecology.facilities.coolant)
	session.store.failure_point = "before_publish"
	_check(not session.ecology._try_service(), "save failure refuses repair")
	_check(body.health == body.maximum_health - 40 and int(session.ecology.facilities.coolant) == stock, "save failure preserves health and stock")
	session.store.failure_point = ""
	_check(session.ecology._try_service(), "durable service consumption succeeds")
	_check(body.health == body.maximum_health - 15 and int(session.ecology.facilities.coolant) == stock - 1, "one stock repairs exactly 25")
	_check(int(session.store.snapshot().world.ecology.facilities.coolant) == stock - 1, "service stock consumed in the persisted world")
	_check(session._save_environment(), "simulation and facilities save in one environment transaction")
	var checkpoint: Dictionary = session.ecology.persistent_state()
	_check(session.store.fork_branch("ecology_checkpoint", "Ecology checkpoint", false).get("ok", false), "create independent ecology branch")
	session.world_cache = session.store.snapshot()
	for i in range(20): session.ecology.advance(1.0)
	_check(session._save_environment(), "advance original branch")
	session._ui_action("branch", {"id":"ecology_checkpoint"})
	_check(session.ecology.persistent_state() == checkpoint, "branch restores exact actors stock events and weather without replay")
	var corrupt: Dictionary = session.world_cache.world.duplicate(true)
	corrupt.ecology.last_event_serial += 1
	_check(not session.ecology.restore_world(corrupt), "reject mismatched facility/simulation serial")
	_check(session.ecology.persistent_state() == checkpoint, "bad restore leaves live state untouched")
	_check(session.store.fork_branch("bad_ecology", "Bad fixture", true).get("ok", false), "create malformed-ecology fixture branch")
	_check(session.store.commit({"id":"qa-bad-ecology", "set":{"world.ecology":corrupt.ecology}}).get("ok", false), "store accepts JSON-valid fixture for domain validation test")
	session.store.switch_branch("ecology_checkpoint")
	session.world_cache = session.store.snapshot()
	var generation = session.world_cache.generation
	session._ui_action("branch", {"id":"bad_ecology"})
	_check(session.active and session.store.snapshot().world.branch_id == "ecology_checkpoint" and session.store.snapshot().generation == generation, "invalid target branch rejected before any disk or session switch")
	# Historical travel permission must not silently provide perpetual power.
	session.world_cache.world.flags.I1_gate = true
	session.entities["I1:relay"].charge = 0.0
	session.entities["I1:relay"].powered = false
	session.entities["I1:beacon"].powered = false
	session.ecology.advance(1.0)
	_check(session.ecology.simulation.get_actor("I1:inspection_01").reason == "power_unavailable", "historical open gate does not override present power loss")
	var saved_actor: Dictionary = session.ecology.simulation.get_actor("I1:water_01")
	_check(session._load_region("F1"), "authoritative travel fixture loads F1 successfully")
	_check(session.ecology.simulation.get_actor("I1:water_01") == saved_actor, "travel rebuilds presentation without resetting offscreen actors")
	_check(is_equal_approx(session.world.clock_seconds, session.ecology.simulation.elapsed_seconds()), "travel retains shared environment phase")
	await physics_frame
	await physics_frame
	await _corridors("F1")
	var packet: Dictionary = session._snapshot()
	var ecological_event: Dictionary = session.ecology.state_event()
	var before_guest: Dictionary = session.ecology.persistent_state()
	session.network.mode = "guest"
	session.owns_world = false
	session.received_session = ""
	session.received_sequence = -1
	packet.paused = true
	session.ecology.applied_serial = -1
	session.ecology.expected_serial = -1
	session.ecology.expected_epoch = -1
	session.ecology.pending.clear()
	session._network_event(ecological_event)
	session._apply_snapshot(packet)
	session.ecology.advance(8.0)
	_check(session.ecology.persistent_state() == before_guest, "guest never simulates or awards facility stock")
	_check(session.ecology.view.targets.size() == 2 and session.simulation_paused, "paused guest reconstructs both F1 actors from authority")
	var next_event: Dictionary = ecological_event.duplicate(true)
	next_event.serial += 2
	next_event.state.actors[0].p += Vector3(0.5, 0, 0)
	var first_id = str(next_event.state.actors[0].id)
	var old_target: Vector3 = session.ecology.view.targets[first_id].p
	session._network_event(next_event)
	_check(session.ecology.view.targets[first_id].p == old_target, "future reliable ecology waits for matching motion serial")
	var next_packet: Dictionary = packet.duplicate(true)
	next_packet.sequence += 1
	next_packet.ecology_serial = next_event.serial
	session._apply_snapshot(next_packet)
	_check(session.ecology.view.targets[first_id].p == next_event.state.actors[0].p, "future ecology applies after matching snapshot even while paused")
	session._network_event(ecological_event)
	_check(session.ecology.view.targets[first_id].p == next_event.state.actors[0].p, "stale reliable event cannot rewind current actor")
	# Reliable channel stays two ticks behind the independent motion channel.
	# Equality-only acceptance used to starve all ecology presentation here.
	var delayed_event: Dictionary = next_event.duplicate(true)
	for delay_step in range(3):
		next_packet.sequence += 1
		next_packet.ecology_serial += 3
		session._apply_snapshot(next_packet)
		delayed_event.serial = next_packet.ecology_serial - 2
		delayed_event.state.actors[0].p += Vector3(0.25, 0, 0)
		session._network_event(delayed_event)
		_check(session.ecology.applied_serial == delayed_event.serial and session.ecology.view.targets[first_id].p == delayed_event.state.actors[0].p, "reliable ecology progresses while motion stays two ticks ahead %d" % delay_step)
	# A new visit to the same region must not accept old-visit data, even if
	# its serial is newer than the last ecology message we managed to receive.
	var prior_visit: Dictionary = delayed_event.duplicate(true)
	prior_visit.serial += 1
	prior_visit.state.actors[0].p += Vector3(10, 0, 0)
	next_packet.sequence += 1
	next_packet.ecology_serial += 3
	next_packet.ecology_epoch += 2
	session._apply_snapshot(next_packet)
	session._network_event(prior_visit)
	_check(session.ecology.applied_serial == delayed_event.serial, "same-region return rejects unseen newer serial from previous visit")
	var current_visit: Dictionary = prior_visit.duplicate(true)
	current_visit.epoch = next_packet.ecology_epoch
	current_visit.serial = next_packet.ecology_serial - 1
	current_visit.state.actors[0].p = old_target
	session._network_event(current_visit)
	_check(session.ecology.applied_serial == current_visit.serial and session.ecology.view.targets[first_id].p == old_target, "delayed state from current visit applies without waiting for exact motion tick")
	var wrong_session: Dictionary = current_visit.duplicate(true)
	wrong_session.session_id += "-stale"
	wrong_session.serial += 1
	wrong_session.state.actors[0].p += Vector3(20, 0, 0)
	session._network_event(wrong_session)
	_check(session.ecology.applied_serial == current_visit.serial, "old session cannot contaminate current ecology stream")
	session.ecology.reset_connection()
	session.received_session = ""
	session.received_sequence = -1
	wrong_session.serial += 10000
	session._network_event(wrong_session)
	session._apply_snapshot(next_packet)
	_check(session.ecology.pending.is_empty(), "first authoritative snapshot discards pre-handshake event from another session")
	session._network_event(current_visit)
	_check(session.ecology.applied_serial == current_visit.serial, "new session lower serial is not blocked by stale pre-handshake cache")
	session._load_region("F1")
	next_packet.sequence += 1
	session._apply_snapshot(next_packet)
	_check(session.ecology.view.targets.size() == 2 and session.ecology.applied_serial == current_visit.serial, "reconstructed same-epoch view replays its latest cached state")
	var newest_motion: Dictionary = next_packet.duplicate(true)
	newest_motion.sequence += 5
	session.network.snapshot_received.emit(newest_motion)
	session.network.snapshot_received.emit(next_packet)
	_check(session.pending_packet.get("sequence", -1) == newest_motion.sequence, "older fallback cannot overwrite newer motion awaiting the same frame")
	session._process(0.0)
	_check(session.received_sequence == newest_motion.sequence and session.pending_packet.is_empty(), "presentation applies retained newest snapshot exactly once")
	var raw = var_to_bytes(packet).compress(FileAccess.COMPRESSION_ZSTD)
	session.network.mode = "solo"
	session.owns_world = true
	session.simulation_paused = false
	session._load_region("I1")
	session._spawn_player(88, "a175f684-840e-4c38-827b-630acc5d4393", Vector3(20, 9, -18))
	session.players[88].freeze = true
	session.players[88].set_physics_process(false)
	session._start_boss()
	var boss_bytes = 0
	for i in range(12):
		session.players[88].position += Vector3(0.07171, -0.03979, 0.15789)
		session.players[88].linear_velocity = Vector3(2.367, -0.147, 0.7789) * (i + 1)
		session.players[1].position += Vector3(-0.13713, 0.01979, 0.23789)
		session.players[1].linear_velocity = Vector3(-1.362, 0.179, 0.5737) * (i + 1)
		session._handle_boss_events(session.encounter.advance(0.3))
		session._sync_boss_entities()
		var boss_packet: Dictionary = session._snapshot()
		_check(Codec.decode(Codec.encode(boss_packet)) == boss_packet, "wire codec preserves exact boss and world state %d" % i)
		boss_bytes = maxi(boss_bytes, var_to_bytes(Codec.encode(boss_packet)).compress(FileAccess.COMPRESSION_ZSTD).size())
	_check(boss_bytes <= 1150, "two-player whale with ecology stays below motion datagram budget")
	print("V3_LIVING_WORLD_TESTS ", JSON.stringify({"checks":checks,"failures":failures,"snapshot_bytes":raw.size(),"boss_snapshot_bytes":boss_bytes,"route_envelope_radius":route_envelopes,"scope":"real scene collision using conservative visual bounds, atomic service persistence, branch restore and injected guest snapshot; not LAN or human play"}))
	session.network.close()
	session.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)

func _corridors(region: String) -> void:
	var radius = 0.1
	for actor in session.ecology.view.actors.values(): radius = maxf(radius, _visual_radius(actor, actor) + 0.08)
	route_envelopes[region] = radius
	var definitions: Dictionary = session.ecology.simulation.definitions()
	var nodes: Dictionary = {}
	for graph in definitions.regions:
		if graph.id == region:
			for node in graph.nodes: nodes[node.id] = node
	var checked: Dictionary = {}
	for id in nodes:
		for target in nodes[id].neighbors:
			var key = str(id) + ":" + str(target)
			if checked.has(str(target) + ":" + str(id)): continue
			checked[key] = true
			var a: Array = nodes[id].position
			var b: Array = nodes[target].position
			var start = Vector3(a[0], a[1], a[2])
			var finish = Vector3(b[0], b[1], b[2])
			var blocked = false
			var query = PhysicsShapeQueryParameters3D.new()
			var shape = SphereShape3D.new()
			shape.radius = radius
			query.shape = shape
			query.collision_mask = 1
			var samples = int(ceil(start.distance_to(finish) / 0.35))
			for sample in range(samples + 1):
				query.transform = Transform3D(Basis.IDENTITY, start.lerp(finish, float(sample) / samples))
				if not session.get_world_3d().direct_space_state.intersect_shape(query, 1).is_empty():
					blocked = true
					break
			_check(not blocked, region + " authored route clearance " + key)

func _visual_radius(node: Node, origin: Node3D) -> float:
	var radius = 0.0
	if node is MeshInstance3D and node.mesh != null:
		var bounds: AABB = node.mesh.get_aabb()
		for index in range(8):
			var corner = bounds.position + bounds.size * Vector3(index & 1, (index >> 1) & 1, (index >> 2) & 1)
			radius = maxf(radius, origin.to_local(node.to_global(corner)).length())
	for child in node.get_children(): radius = maxf(radius, _visual_radius(child, origin))
	return radius
