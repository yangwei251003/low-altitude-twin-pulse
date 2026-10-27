extends SceneTree
## Real MAIN/Session/Store/PhysicsServer integration. The six previous actions
## and a nonzero ecology inventory are explicit saved fixtures, not playthroughs.
## Peer registration and received packets are injected; this is not ENet or GPU QA.
const MAIN = preload("res://scenes/v3/main.tscn")
const Store = preload("res://scripts/v3/core/twin_world_store.gd")
const Director = preload("res://scripts/v3/gameplay/actions/twin_action_director.gd")
const Codec = preload("res://scripts/v3/network/twin_snapshot_codec.gd")
const DT := 1.0 / 60.0
const FRONT := "I1:underdeck_grille"
const LATCH := "I1:underdeck_latch"
const FLAG := "opening:underdeck_latched"
const DISCOVERY := "opening:underdeck_worker_bypass"
const ENTRY := "I1:underdeck:enter"
const RELEASE := "I1:underdeck:release"
const TRAVERSE := "I1:underdeck:traverse"
var session
var guest_store
var profile := ""
var base := ""
var checks: Array = []
var failures: Array = []
var packets: Array = []
var pressure_sources: Array = []
var inventory_fixture: Dictionary = {}
var done := false
var phase := "setup"

func _initialize() -> void: _run.call_deferred()

func check(ok: bool, label: String, details: Dictionary = {}) -> void:
	checks.append({"phase":phase, "label":label, "passed":ok, "details":details})
	if not ok:
		failures.append(label)
		push_error("UNDERDECK_SESSION " + label + " " + JSON.stringify(details))

func _run() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--qa-profile="): profile = arg.trim_prefix("--qa-profile=")
		if arg.begins_with("--qa-network="):
			push_error("No automatic network QA mode in this test")
			quit(2)
			return
	if not profile.begins_with("qa_underdeck_") or profile != profile.validate_filename():
		push_error("A fresh --qa-profile=qa_underdeck_<unique> is required")
		quit(2)
		return
	base = "user://qa_v3_underdeck/" + profile
	if DirAccess.dir_exists_absolute(base) or DirAccess.dir_exists_absolute("user://profiles_v3/" + profile):
		push_error("Refusing reused QA paths")
		quit(2)
		return
	create_timer(150.0).timeout.connect(func():
		if not done:
			check(false, "bounded integration test timed out")
			_finish(2))
	session = MAIN.instantiate()
	root.add_child(session)
	session.set_process(false)
	session.set_physics_process(false)
	check(session.profile_ready and session.start_flight("solo"), "real MAIN opens isolated QA profile and starts solo")
	if not session.active or not is_instance_valid(session.world) or not is_instance_valid(session.world.underdeck):
		check(false, "production world must contain the actual underdeck module")
		_finish(1)
		return
	if not session.story.has_method("observe_underdeck") or not session.story.has_method("reset_underdeck_tracking"):
		check(false, "production Story underdeck adapter must be integrated")
		_finish(1)
		return
	_freeze_bodies()
	if not _seed_previous_actions():
		_finish(1)
		return
	guest_store = Store.new(base.path_join("guest"))
	check(guest_store.load_profile().ok and guest_store.commit({"id":"qa-guest-bootstrap"}).ok, "independent QA guest identity is durable")
	_join_guest()
	check(session.store.fork_branch("before-underdeck", "QA before seventh action", false).ok, "snapshot branch before new action")
	session.world_cache = session.store.snapshot()
	await _read_plan()
	if not _completed("I1:underdeck:read"):
		_finish(1)
		return
	check(session.store.fork_branch("after-read", "QA choose entrance", false).ok, "independent branch after actual inspection")
	session.world_cache = session.store.snapshot()
	await _main_entrance_and_release()
	if not _completed(RELEASE):
		_finish(1)
		return
	await _north_exit_and_rewards()
	if not _completed(TRAVERSE):
		_finish(1)
		return
	await _branches_and_side_route()
	if failures.is_empty():
		await _whale_packet_pressure()
		# A packet-budget failure must not hide the original guest lifecycle checks.
		await _guest_snapshot_ordering()
	_finish(0 if failures.is_empty() else 1)

func _freeze_bodies() -> void:
	for body in session.players.values():
		body.freeze = true
		body.set_process(false)
		body.set_physics_process(false)
		body.linear_velocity = Vector3.ZERO
		body.angular_velocity = Vector3.ZERO

func _seed_previous_actions() -> bool:
	var legacy = Director.new()
	var loaded: Dictionary = legacy.load_definitions(Director.DEFAULT_PATH, ["res://data/v3/actions/whale_action.json", "res://data/v3/actions/crown_action.json"])
	check(loaded.ok, "six-action fixture uses production Director definitions")
	if not loaded.ok: return false
	var state: Dictionary = legacy.default_state()
	for action in legacy.definitions().actions:
		for objective in action.objectives:
			var matcher: Dictionary = objective.events[0]
			var event := {"id":"qa-prerequisite:" + str(objective.id), "type":matcher.type, "target_id":matcher.target_id, "option":matcher.options[0]}
			var result: Dictionary = legacy.apply_event(state, event, {"is_authority":true, "validated":true, "region_id":action.region_id})
			if not result.get("changed", false):
				check(false, "prior-action fixture replay rejected", {"goal":objective.id,"code":result.get("code")})
				return false
			state = result.state
	check(state.completed.size() == 23 and state.completed_actions.size() == 6 and session.story.director.validate_state(state).ok, "explicit23-goal predecessor fixture validates in seven-action Director")
	# Deliberately persisted nonzero facility inventory; no claim these deliveries
	# occurred through flight in this suite. It detects accidental resets on commits.
	var eco: Dictionary = session.ecology.persistent_state()
	eco.facilities = {"coolant":2, "maintenance":{"I1:thermal":1,"I1:relay":2}, "deliveries":7}
	inventory_fixture = eco.facilities.duplicate(true)
	var saved: Dictionary = session.store.commit({"id":"qa-six-action-prerequisite", "set":{"world.actions.opening":state, "world.flags":state.flags, "world.completed_objectives":state.completed, "world.ecology":eco}, "append":{"personal.discoveries":state.discoveries}})
	check(saved.ok, "previous actions and ecology fixture commit in one real transaction")
	if not saved.ok: return false
	session.world_cache = session.store.snapshot()
	check(session.ecology.restore_world(session.world_cache.world) and session._load_region("I1"), "real world reload accepts saved prerequisite and inventory")
	_freeze_bodies()
	check(session.story.state.completed.size() == 23 and not _completed(ENTRY), "new action has not been completed by fixture")
	check(not session.world.underdeck.snapshot().latched and session.world.underdeck.snapshot().front_fraction == 0.0, "unreleased warehouse starts closed")
	return saved.ok

func _join_guest() -> void:
	# Registered-peer lifecycle fixture only: OfflineMultiplayerPeer stays in use.
	var identity: String = guest_store.snapshot().profile_id
	session.network.guests[2] = identity
	session._guest_joined(2, identity, "hx02")
	_freeze_bodies()
	check(session.players.has(2) and session.players[2].build.airframe_id == "hx02", "real guest lifecycle creates the wider HX02 body without opening UDP")

func _fixture_place(peer: int, at: Vector3) -> void:
	# Explicit starting placement never counts as movement evidence.
	session.story.reset_underdeck_tracking()
	var body = session.players[peer]
	body.global_transform = Transform3D(Basis.IDENTITY, at)
	body.linear_velocity = Vector3.ZERO
	PhysicsServer3D.body_set_state(body.get_rid(), PhysicsServer3D.BODY_STATE_TRANSFORM, body.global_transform)
	session.entities[session._actor_id(peer)].position = at
	await physics_frame
	await physics_frame
	await _ticks(1)

func _ticks(count: int) -> void:
	for i in range(count):
		await physics_frame
		session._physics_process(DT)

func _wait_completed(id: String, max_ticks: int) -> void:
	# Production uses a one-second disk retry backoff; retain the same real ticks.
	for i in range(max_ticks):
		if _completed(id): return
		await _ticks(1)

func _move(peer: int, to: Vector3, label: String) -> bool:
	var body = session.players[peer]
	var count := 0
	var collision: KinematicCollision3D
	while body.global_position.distance_to(to) > 0.001 and count < 400:
		var remaining: Vector3 = to - body.global_position
		var motion: Vector3 = remaining.limit_length(0.15)
		collision = body.move_and_collide(motion)
		await _ticks(1)
		count += 1
		if collision != null: break
	var success: bool = collision == null and body.global_position.distance_to(to) < 0.005
	check(success, label, {"position":str(body.global_position),"target":str(to),"steps":count,"collider":str(collision.get_collider().get_path()) if collision != null else ""})
	return success

func _ability(peer: int, ability: String, target: String, extra: Dictionary = {}) -> bool:
	# Wait real simulated cooldown; do not reset it or give extra ability energy.
	while float(session.cooldowns.get(peer, 0.0)) > 0.0: await _ticks(1)
	var before: int = session.stats.abilities
	var request := {"ability":ability,"target_id":target}
	request.merge(extra, true)
	session._action_received(peer, "ability", request)
	var accepted: bool = session.stats.abilities == before + 1
	check(accepted, "production ability accepted: " + ability + " peer" + str(peer), {"message":session.interface.message.text})
	return accepted

func _completed(id: String) -> bool: return id in session.story.state.get("completed", [])

func _read_plan() -> void:
	phase = "manual_inspection"
	await _fixture_place(1, Vector3(-35,2.05,-16.8))
	var before: Dictionary = session.store.snapshot()
	session._action_received(1, "explore", {"target_id":"I1:underdeck_entry","type":"fact","option":"main_flight","validated":true})
	check(session.store.snapshot() == before and not _completed(ENTRY), "client payload cannot submit an entry fact")
	# Real G dispatch, with no dialogue open to consume the key instead.
	session.interface.clear_dialogue()
	var key := InputEventKey.new()
	key.pressed = true
	key.keycode = KEY_G
	key.physical_keycode = KEY_G
	session._unhandled_input(key)
	check(_completed("I1:underdeck:read") and not _completed(ENTRY), "actual nearby G and LOS inspection advances only read")
	check(session.story.state.revision == 24, "new inspection follows existing23 goals")

func _main_entrance_and_release() -> void:
	phase = "main_force_field_entry"
	await _fixture_place(1, Vector3(-35,2.05,-16.8))
	var energy: float = session.entities["player:1"].energy
	var abilities: int = session.stats.abilities
	session._action_received(1, "ability", {"ability":"blink","target_id":"","point":Vector3(-35,2.05,-22.8)})
	check(session.stats.abilities == abilities and session.entities["player:1"].energy == energy and session.players[1].global_position.is_equal_approx(Vector3(-35,2.05,-16.8)), "real closed-door six-metre blink is rejected without energy or position change")
	var moving_packet_recorded := false
	for i in range(520):
		var fraction: float = session.world.underdeck.snapshot().front_fraction
		if not moving_packet_recorded and fraction > 0.1 and fraction < 0.9:
			pressure_sources.append(_packet("moving-front-two-players", false))
			moving_packet_recorded = true
		if fraction >= 0.999: break
		await _ticks(1)
	check(session.world.underdeck.snapshot().front_fraction >= 0.999, "production physics advances natural gate cycle to open")
	if not await _ability(1, "force_field", FRONT): return
	var gate_pose: Transform3D = session.world.underdeck.gates.front.global_transform
	await _ticks(6)
	check(session.entities[FRONT].pinned and session.world.underdeck.gates.front.global_transform == gate_pose, "real force field fixes actual moving panel")
	pressure_sources.append(_packet("held-front-two-players", false))
	if not await _move(1, Vector3(-35,2.05,-23.5), "TR01 moves through held south gate into chamber"): return
	check(_completed(ENTRY) and session.story.state.choices.get(ENTRY) == "held_grille", "only real full-envelope entry commits held-grille route")
	check(not _completed(RELEASE), "being inside does not itself release latch")
	phase = "continuous_signal_and_save_failure"
	await _fixture_place(2, Vector3(-35,2.05,-27.0))
	if not await _ability(2, "echo", LATCH): return
	await _ticks(30)
	check(not _completed(RELEASE), "half-second real echo cannot satisfy one-second latch")
	pressure_sources.append(_packet("guest-echo-held-front-two-players", false))
	session._guest_left(2)
	session.network.guests.erase(2)
	await _ticks(45)
	check(not _completed(RELEASE) and not session.world.underdeck.snapshot().latched, "disconnected echo source cannot finish remaining signal time")
	# Existing echo ownership naturally expires before the other actor reuses it.
	await _ticks(260)
	if not await _ability(1, "echo", LATCH): return
	var before: Dictionary = session.store.snapshot()
	session.store.failure_point = "before_publish"
	await _ticks(60)
	check(not _completed(RELEASE) and session.store.snapshot() == before and not session.world.underdeck.snapshot().latched, "one-second success with actual write failure leaves story store and permanent gate unchanged")
	check(session.story.underdeck_action.debug_state().pending.has(RELEASE), "failed commit retains validated release candidate for retry")
	session.store.failure_point = ""
	await _wait_completed(RELEASE, 65)
	check(_completed(RELEASE) and session.store.snapshot().world.flags.get(FLAG, false) and session.world.underdeck.snapshot().latched, "restored storage commits pending release once and publishes permanent target")
	_check_inventory("release commit")
	var disk = Store.new(session.store.root_path)
	check(disk.load_profile().ok and disk.snapshot() == session.store.snapshot(), "actual new store instance reopens committed release generation")
	session.store = disk
	session.world_cache = disk.snapshot()
	session.simulation_paused = true
	check(session._load_region("I1"), "paused real region reload succeeds after committed release")
	_freeze_bodies()
	_check_gate_pose(true, "release reload before any physics frame")
	check(session.story.underdeck_action.debug_state().signal_seconds == 0.0, "reload does not reuse one-second transient signal")
	session.simulation_paused = false
	_join_guest()

func _north_exit_and_rewards() -> void:
	phase = "real_north_crossing"
	await _fixture_place(1, Vector3(-35,2.05,-37.2))
	await _ticks(3)
	check(not _completed(TRAVERSE), "setup outside northern validation point cannot impersonate traversal")
	await _fixture_place(1, Vector3(-35,2.05,-30))
	var before: Dictionary = session.store.snapshot()
	session.store.failure_point = "before_publish"
	if not await _move(1, Vector3(-35,2.05,-37.2), "TR01 moves from real corridor through north portal"): return
	check(not _completed(TRAVERSE) and session.store.snapshot() == before and DISCOVERY not in session.store.snapshot().personal.discoveries, "failed traversal save grants no discovery and keeps durable old state")
	check(session.story.underdeck_action.debug_state().pending.has(TRAVERSE), "north-crossing candidate survives failed save after body exits")
	var pending_before_respawn: Dictionary = session.story.underdeck_action.debug_state().pending
	var revision_before_retry: int = session.story.state.revision
	session._restore_player(2, session.world.spawn_position + Vector3(3,0,0))
	_freeze_bodies()
	check(session.story.underdeck_action.debug_state().pending == pending_before_respawn and session.store.snapshot() == before, "other peer real respawn preserves validated unsaved crossing and durable state")
	session.store.failure_point = ""
	await _wait_completed(TRAVERSE, 65)
	check(_completed(TRAVERSE) and session.story.state.completed.size() == 27 and session.story.state.revision == revision_before_retry + 1, "retry commits actual crossing once as27th objective after teammate respawn")
	_check_reward_once("first completion")
	_check_inventory("traversal commit")
	await _ticks(5)
	_check_reward_once("repeat observation")
	packets.append(_packet("first-open", true))

func _branches_and_side_route() -> void:
	phase = "branches_and_side_blink"
	session.simulation_paused = true
	session._ui_action("branch", {"id":"after-read"})
	_freeze_bodies()
	check(session.world_cache.world.branch_id == "after-read" and not _completed(ENTRY), "production branch action restores only committed read")
	_check_gate_pose(false, "unreleased branch before any physics frame")
	packets.append(_packet("newer-closed-zero-serial", true))
	session.simulation_paused = false
	await _fixture_place(2, Vector3(-25.5,3.55,-23.5))
	if not await _ability(2, "blink", "", {"point":Vector3(-31.5,3.55,-23.5)}): return
	await _ticks(1)
	check(_completed(ENTRY) and session.story.state.choices.get(ENTRY) == "side_blink", "actual wider HX02 six-metre side blink records that accepted path", {"body":str(session.players[2].global_position),"adapter":session.story.underdeck_action.debug_state(),"story_revision":session.story.state.revision,"choice":session.story.state.choices.get(ENTRY, "")})
	if not await _move(2, Vector3(-35,3.55,-23.5), "HX02 travels through upper turning chamber"): return
	if not await _move(2, Vector3(-35,2.05,-23.5), "HX02 descends into main corridor"): return
	if not await _ability(2, "takeover", LATCH): return
	await _ticks(30)
	check(not _completed(RELEASE), "half-second takeover remains incomplete")
	session.simulation_paused = true
	var paused_gate: Dictionary = session.world.underdeck.snapshot()
	var paused_signal: Dictionary = session.story.underdeck_action.debug_state()
	await _ticks(30)
	check(session.world.underdeck.snapshot() == paused_gate and session.story.underdeck_action.debug_state() == paused_signal, "simulation pause advances neither gate nor continuous latch evidence")
	session.simulation_paused = false
	await _ticks(29)
	check(not _completed(RELEASE), "takeover remains incomplete before total one second excluding pause")
	await _ticks(1)
	check(_completed(RELEASE), "takeover reaches one second of actual unpaused host ticks", {"adapter":session.story.underdeck_action.debug_state(),"latch":session.entities[LATCH]})
	await _ticks(90)
	if not await _move(2, Vector3(-35,2.05,-37.2), "HX02 physically exits north after takeover"): return
	check(_completed(TRAVERSE), "second route independently commits its branch world progression")
	_check_reward_once("second branch completion")
	_check_inventory("second branch completion")
	session.simulation_paused = true
	session._ui_action("branch", {"id":"main"})
	_freeze_bodies()
	check(session.world_cache.world.branch_id == "main" and _completed(TRAVERSE), "main branch retains its own complete route")
	_check_gate_pose(true, "main branch restore before any physics frame")
	packets.append(_packet("latest-main-open", true))
	_check_reward_once("branch round trip")
	var disk = Store.new(session.store.root_path)
	check(disk.load_profile().ok and disk.snapshot() == session.store.snapshot(), "completed branch round trip matches actual reopened disk generation")

func _check_inventory(label: String) -> void:
	var actual: Dictionary = session.store.snapshot().world.get("ecology", {}).get("facilities", {})
	check(int(actual.get("coolant", -1)) >= int(inventory_fixture.coolant) and int(actual.get("deliveries", -1)) >= int(inventory_fixture.deliveries) and int(actual.get("maintenance", {}).get("I1:thermal", -1)) >= 1 and int(actual.get("maintenance", {}).get("I1:relay", -1)) >= 2, label + " preserves prior nonzero ecology stock and maintenance")

func _check_reward_once(label: String) -> void:
	var state: Dictionary = session.store.snapshot()
	var received: Array = []
	for receipt in session.store.pending_guest_receipts(guest_store.snapshot().profile_id):
		if receipt.reward_id == DISCOVERY: received.append(receipt)
	check(state.personal.discoveries.count(DISCOVERY) == 1 and received.size() == 1, label + " has one host discovery and one stable guest receipt")
	if received.size() == 1:
		var applied: Dictionary = guest_store.apply_guest_receipt(received[0])
		var duplicate: Dictionary = guest_store.apply_guest_receipt(received[0])
		check(applied.ok and duplicate.ok and duplicate.duplicate and guest_store.snapshot().personal.discoveries.count(DISCOVERY) == 1, label + " applies real guest receipt idempotently without socket delivery claims")

func _check_gate_pose(opened: bool, label: String) -> void:
	var expected := 1.0 if opened else 0.0
	var state: Dictionary = session.world.underdeck.snapshot()
	var valid: bool = bool(state.latched) == opened and state.front_fraction == expected and state.rear_fraction == expected
	var poses: Dictionary = {}
	for side in ["front", "rear"]:
		var body: PhysicsBody3D = session.world.underdeck.gates[side]
		var spec: Dictionary = session.world.underdeck.layout().gates[side]
		var centre := Vector3(spec.center[0], spec.center[1], spec.center[2])
		var travel := Vector3(spec.travel[0], spec.travel[1], spec.travel[2])
		var actual: Transform3D = PhysicsServer3D.body_get_state(body.get_rid(), PhysicsServer3D.BODY_STATE_TRANSFORM)
		poses[side] = {"node":str(body.global_position),"physics":str(actual.origin),"expected":str(centre + travel * expected)}
		valid = valid and body.global_position.distance_to(centre + travel * expected) < 0.001 and actual.origin.distance_to(body.global_position) < 0.001
	check(valid, label + " restores real gate transforms and PhysicsServer state immediately", {"state":state,"poses":poses})
	check(session.entities[FRONT].position.distance_to(session.world.underdeck.gates.front.global_position) < 0.001, label + " keeps ability target on moving front panel")

func _packet(label: String, paused: bool) -> Dictionary:
	var old_pause: bool = session.simulation_paused
	session.simulation_paused = paused
	var packet: Dictionary = session._snapshot()
	session.simulation_paused = old_pause
	var wire: Dictionary = Codec.encode(packet)
	var raw: PackedByteArray = var_to_bytes(wire)
	var compressed: PackedByteArray = raw.compress(FileAccess.COMPRESSION_ZSTD)
	var decoded: Dictionary = Codec.decode(bytes_to_var(compressed.decompress(raw.size(), FileAccess.COMPRESSION_ZSTD)))
	check(not wire.is_empty() and decoded == packet, label + " real production packet round-trips through Codec and ZSTD", {"raw_bytes":raw.size(),"compressed_bytes":compressed.size(),"unreliable_budget_bytes":1150,"uses_reliable_fallback":compressed.size() > 1150,"players":packet.players.size(),"underdeck_serial":packet.mechanisms.underdeck.serial,"sequence":packet.sequence})
	return {"label":label,"packet":decoded,"compressed_bytes":compressed.size()}

func _whale_packet_pressure() -> void:
	phase = "explicit_combined_packet_pressure_fixture"
	# Earlier passage/timer samples came from this run's actual actions. We combine
	# them with a real practice encounter solely to stress the presentation wire.
	# No attack is resolved, no victory occurs, and no persistent flag is assigned.
	check(pressure_sources.size() == 3, "pressure fixture retains three actually observed passage states")
	if pressure_sources.size() != 3: return
	var durable_before: Dictionary = session.store.snapshot()
	session.simulation_paused = true
	var network_peer := 1951275986 # Observed legal 10-digit ENet peer, not peer2 shorthand.
	var identity: String = guest_store.snapshot().profile_id
	session._guest_left(2)
	session.network.guests.erase(2)
	session.network.guests[network_peer] = identity
	session._guest_joined(network_peer, identity, "hx02")
	_freeze_bodies()
	await _fixture_place(1, Vector3(-20.25,6.25,-14.875))
	await _fixture_place(network_peer, Vector3(-24.75,3.55,-23.5))
	session._start_boss(false)
	# Fractional remaining time is obtained from the real encounter clock. This
	# 137ms does not reach the attack transition or apply damage to any player.
	var events: Array = session.encounter.advance(0.137)
	check(session.boss_active and not session.boss_campaign and events.is_empty() and session._boss_target_positions.size() == 2, "practice whale creates two nonzero warning marks without advancing an attack or campaign")
	session._sync_boss_entities()
	session.locks[1] = "boss:port"
	session.locks[network_peer] = "boss:core"
	var peak := 0
	for sample in pressure_sources:
		var observed: Dictionary = sample.packet
		var applied: Dictionary = session.world.underdeck.apply_snapshot(observed.mechanisms.underdeck)
		check(applied.ok, "pressure restore accepts observed " + str(sample.label))
		for id in [FRONT, LATCH]:
			session.entities[id].merge(observed.entities[id].duplicate(true), true)
			# The saved sample was from peer2; retain exactly the same effect while
			# representing the registered 10-digit ENet identity in this fixture.
			for key in ["owner", "echoed_by", "return_owner"]:
				if str(session.entities[id].get(key, "")) == "2": session.entities[id][key] = str(network_peer)
		session.world.synchronize(session.entities, 0.0)
		var measured: Dictionary = _packet("pressure-whale-" + str(sample.label), false)
		var packet: Dictionary = measured.packet
		var has_parts: bool = packet.entities.has("boss:port") and packet.entities.has("boss:starboard") and packet.entities.has("boss:core")
		check(has_parts and packet.players.size() == 2 and packet.players.has(network_peer) and packet.boss_marks.size() == 2 and not packet.boss.completed, "pressure packet contains actual whale parts roster and dual marks: " + str(sample.label))
		peak = maxi(peak, int(measured.compressed_bytes))
		check(int(measured.compressed_bytes) <= 1150, "whale plus observed passage fits1150B: " + str(sample.label), {"compressed_bytes":measured.compressed_bytes,"budget":1150,"fixture":"production encounter and snapshot; earlier actual mechanism sample restored only in memory"})
		if str(sample.label) == "guest-echo-held-front-two-players":
			_varied_whale_packet_pressure(packet, network_peer)
	check(peak > 0 and peak <= 1150, "combined whale-underdeck two-player pressure peak", {"peak_bytes":peak,"samples":pressure_sources.size(),"budget":1150})
	check(session.store.snapshot() == durable_before and not session.pending_completion, "pressure fixture writes no world progress or reward")
	# Restore through the production region loader before the original guest tests.
	check(session._load_region("I1"), "production reload ends pressure practice and restores committed main world")
	_freeze_bodies()
	check(not session.boss_active and session.world.underdeck.snapshot().latched and session.store.snapshot() == durable_before, "pressure teardown retains completed main branch and unchanged Store")

func _varied_whale_packet_pressure(packet: Dictionary, network_peer: int) -> void:
	# Serialization-only fixture: deep copies of the third actual production packet.
	# These varied poses are not asserted to be valid movement routes. No body,
	# mechanism, encounter, Store or original packet is changed; marks stay locked.
	var original: Dictionary = packet.duplicate(true)
	var required: bool = packet.players.has(1) and packet.players.has(network_peer) and packet.entities.has(FRONT) and packet.entities.has(LATCH) and packet.entities[FRONT].has("field_remaining") and packet.entities[LATCH].has("echo_remaining") and float(packet.entities[FRONT].get("field_remaining", 0.0)) > 0.0 and float(packet.entities[LATCH].get("echo_remaining", 0.0)) > 0.0
	check(required, "varied pressure uses the actual dual-player held-gate and active-echo packet")
	if not required: return
	var minimum_bytes: int = 2147483647
	var maximum_bytes: int = 0
	var sample_sizes: Array = []
	var peers: Array = [1, network_peer]
	for index in range(12):
		var varied: Dictionary = packet.duplicate(true)
		var step: float = float(index + 1)
		varied.sequence = int(packet.sequence) + index + 1
		for slot in range(peers.size()):
			var peer: int = int(peers[slot])
			var roster: Dictionary = varied.players[peer]
			var direction: float = 1.0 if slot == 0 else -1.0
			roster.position = packet.players[peer].position + Vector3(direction * step * 0.07193, step * 0.01937, -direction * step * 0.08371)
			roster.velocity = Vector3(direction * (2.13791 + step * 0.07931), 0.17391 + step * 0.01379, -direction * (1.71937 + step * 0.07193))
			roster.heading = direction * (0.71237 + float(slot) * 0.51731 + step * 0.02371)
			roster.health = float(packet.players[peer].health) * (0.91371 - float(slot) * 0.07193 - step * 0.00317)
		varied.mechanisms.clock = float(packet.mechanisms.clock) + step * 0.11937
		varied.mechanisms.rotor = float(packet.mechanisms.rotor) + step * 0.01731
		varied.entities[FRONT].field_remaining = maxf(0.1, float(packet.entities[FRONT].field_remaining) - step * 0.01173)
		varied.entities[LATCH].echo_remaining = maxf(0.1, float(packet.entities[LATCH].echo_remaining) - step * 0.01319)
		varied.boss.attack_remaining = maxf(0.1, float(packet.boss.attack_remaining) - step * 0.01783)
		var wire: Dictionary = Codec.encode(varied)
		var raw: PackedByteArray = var_to_bytes(wire)
		var compressed: PackedByteArray = raw.compress(FileAccess.COMPRESSION_ZSTD)
		var decoded: Dictionary = Codec.decode(bytes_to_var(compressed.decompress(raw.size(), FileAccess.COMPRESSION_ZSTD)))
		var details: Dictionary = {"sample":index + 1,"raw_bytes":raw.size(),"compressed_bytes":compressed.size(),"budget":1150,"fixture":"deep-copied production packet; synthetic moving poses and float timers, not a world-route validation"}
		minimum_bytes = mini(minimum_bytes, compressed.size())
		maximum_bytes = maxi(maximum_bytes, compressed.size())
		sample_sizes.append(compressed.size())
		check(not wire.is_empty() and decoded == varied, "varied whale-underdeck packet lossless roundtrip %02d" % (index + 1), details)
		check(compressed.size() <= 1150, "varied whale-underdeck packet fits1150B %02d" % (index + 1), details)
	check(sample_sizes.size() == 12 and maximum_bytes <= 1150, "twelve changing whale-underdeck packet budget", {"samples":sample_sizes.size(),"min_bytes":minimum_bytes,"max_bytes":maximum_bytes,"all_bytes":sample_sizes,"budget":1150})
	check(packet == original, "serialization pressure leaves the actual packet unchanged")

func _guest_snapshot_ordering() -> void:
	phase = "guest_snapshot_lifecycle_fixture"
	var protected_host: Dictionary = session.store.snapshot()
	var host_store_path: String = session.store.root_path
	session.active = false
	session.network.close()
	session.free()
	session = MAIN.instantiate()
	root.add_child(session)
	session.set_process(false)
	session.set_physics_process(false)
	session.store = guest_store
	session.world_cache = guest_store.snapshot()
	session.profile_ready = true
	session.network.mode = "guest" # No ENet peer or UDP socket is created.
	session.active = true
	session.owns_world = false
	session.received_session = ""
	session.received_sequence = -1
	session.story.reset_connection()
	var guest_before: Dictionary = guest_store.snapshot()
	var first: Dictionary = packets[0].packet
	session._queue_snapshot(first)
	session._process(0.0)
	check(session.received_sequence == first.sequence and session.simulation_paused and not session.world.underdeck.authority, "first paused guest packet builds a non-authority passage before input")
	_check_gate_pose(true, "guest paused first packet")
	var before: Dictionary = session.world.underdeck.snapshot()
	# This fixture injects packets without an ENet client. Exercise the actual
	# guest world update directly; sending inputs via OfflinePeer would RPC self.
	for i in range(8):
		await physics_frame
		session.world.synchronize(session.entities, DT)
	check(session.world.underdeck.snapshot() == before, "guest world ticks never advance received gate cycle or serial")
	var next: Dictionary = packets[1].packet
	session._queue_snapshot(next)
	session._process(0.0)
	check(session.received_sequence == next.sequence and next.mechanisms.underdeck.serial < first.mechanisms.underdeck.serial, "newer same-session branch packet accepts reset module serial")
	_check_gate_pose(false, "newer unopened branch snapshot")
	session._queue_snapshot(first)
	session._process(0.0)
	check(session.received_sequence == next.sequence and not session.world.underdeck.snapshot().latched, "older same-session open packet cannot reopen newer closed branch")
	var latest: Dictionary = packets[2].packet
	session._queue_snapshot(latest)
	session._process(0.0)
	_check_gate_pose(true, "latest paused main-branch snapshot")
	var final_pose: Dictionary = session.world.underdeck.snapshot()
	var stranger: Dictionary = next.duplicate(true)
	stranger.session_id = "unrelated-session"
	stranger.sequence = int(latest.sequence) + 100
	session._queue_snapshot(stranger)
	session._process(0.0)
	check(session.received_sequence == latest.sequence and session.world.underdeck.snapshot() == final_pose, "foreign session cannot close restored passage despite higher sequence")
	session._queue_snapshot(next)
	session._process(0.0)
	check(session.received_sequence == latest.sequence and session.world.underdeck.snapshot() == final_pose, "delayed closed snapshot cannot roll back newest open state")
	check(guest_store.snapshot() == guest_before, "guest world snapshots never persist remote world into personal profile")
	var reopened = Store.new(host_store_path)
	check(reopened.load_profile().ok and reopened.snapshot() == protected_host, "guest lifecycle leaves original host save unchanged")

func _finish(code: int) -> void:
	if done: return
	done = true
	print("UNDERDECK_SESSION checks=%d failures=%d profile=%s" % [checks.size(), failures.size(), profile])
	print("UNDERDECK_SESSION_RESULT " + JSON.stringify({"passed":code == 0,"checks":checks,"failures":failures,"profile":profile,"limits":["Previous23 objectives replayed as explicit saved fixtures; not a human six-action playthrough.","New objectives use real Session actions, PhysicsBody motion, Store publication and production adapter.","Registered peers and snapshots injected into production methods; no ENet, remote-PC, GPU or performance evidence.","Nonzero previous ecology inventory is an explicit persistence fixture."]}))
	if is_instance_valid(session):
		session.active = false
		session.network.close()
		session.free()
	quit(code)
