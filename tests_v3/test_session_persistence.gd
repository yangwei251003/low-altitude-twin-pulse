extends SceneTree
## Real main.tscn + real store integration. Network lifecycle callbacks are injected;
## this suite is not an ENet latency, rendering, or human playtest claim.

const MAIN = preload("res://scenes/v3/main.tscn")
const Store = preload("res://scripts/v3/core/twin_world_store.gd")
const REPORT_PREFIX = "res://artifacts/v3/session-persistence"

class CapturedTransport extends TwinNetwork:
	var sent_events: Array = []
	var sent_actions: Array = []
	func _ready() -> void: pass
	func send_event(peer_id: int, event: Dictionary) -> void: sent_events.append({"peer":peer_id,"event":event.duplicate(true)})
	func send_action(verb: String, payload: Dictionary = {}) -> void: sent_actions.append({"verb":verb,"payload":payload.duplicate(true)})

var checks: Array[Dictionary] = []
var failures: Array[String] = []
var base = ""
var profile = ""
var session
var started_utc = ""
var cases: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	started_utc = Time.get_datetime_string_from_system(true) + "Z"
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--qa-profile="): profile = argument.trim_prefix("--qa-profile=")
		if argument.begins_with("--qa-network="):
			print("REFUSED: automatic network QA mode is not allowed in this suite")
			quit(2)
			return
	if not profile.begins_with("qa_session_") or profile != profile.validate_filename():
		print("REFUSED: pass --qa-profile=qa_session_<unique>; real/default profiles are never used")
		quit(2)
		return
	base = "user://qa_v3_session/" + profile
	if DirAccess.dir_exists_absolute(base) or DirAccess.dir_exists_absolute("user://profiles_v3/" + profile):
		print("REFUSED: this QA run requires a fresh unique profile")
		quit(2)
		return
	_test_bootstrap_and_gate()
	_test_guest_disconnect()
	_test_session_reset()
	_test_paused_snapshot_restore()
	_test_paused_guest_spawn()
	_test_rewards_and_branch()
	_test_receipt_channel_recovery()
	_test_ring_angle_branch()
	_test_choice_failure()
	_test_boss_failure()
	_test_pending_completion_branch()
	_test_pending_completion_travel()
	_test_failed_load_gate()
	_dispose_session()
	_write_report()
	print("V3_SESSION_PERSISTENCE checks=%d failures=%d qa_path=%s" % [checks.size(), failures.size(), ProjectSettings.globalize_path(base)])
	for failure in failures: print("FAIL: " + failure)
	quit(0 if failures.is_empty() else 1)

func _check(condition: bool, label: String) -> void:
	checks.append({"case":cases[-1] if not cases.is_empty() else "setup", "label":label, "passed":condition})
	if not condition: failures.append(label)

func _case(name: String) -> void:
	cases.append(name)
	print("SESSION_CASE " + name)

func _instantiate() -> void:
	_dispose_session()
	session = MAIN.instantiate()
	root.add_child(session)
	# Prevent unsolicited physics, autosave, input, or snapshot activity. All tested
	# operations below still invoke the production session and transport methods.
	session.process_mode = Node.PROCESS_MODE_DISABLED

func _dispose_session() -> void:
	if is_instance_valid(session):
		session.network.close()
		session.active = false
		session.free()
	session = null

func _store(name: String):
	var result = Store.new(base.path_join(name))
	_check(result.load_profile().ok, name + " QA store opens")
	_check(result.commit({"id":"test-bootstrap"}).ok, name + " identity is durable")
	return result

func _fresh(name: String) -> void:
	_instantiate()
	session.store = _store(name)
	session.world_cache = session.store.snapshot()
	session.profile_ready = true
	_check(session.start_flight("solo"), name + " starts real solo scene")
	_check(session.world != null and session.players.has(1), name + " world and real flight body exist")

func _disk_matches(store, expected: Dictionary, label: String) -> void:
	var reread = Store.new(store.root_path)
	_check(reread.load_profile().ok, label + " reload opens")
	_check(reread.snapshot() == expected, label + " reload equals committed state")

func _join_fixture(id: int, guest) -> void:
	# Model the transport's registered peer state, then emit its real signal.
	# No socket listener or second game process is required for persistence tests.
	session.network.guests[id] = guest.data.profile_id
	session.network.guest_joined.emit(id, guest.data.profile_id)

func _leave_fixture(id: int) -> void:
	session.network._peer_left(id)

func _gate_interact(id: int = 1) -> void:
	session.world.gate_open = true
	session.players[id].global_position = session.world.objects[session.region_id + ":beacon"].global_position
	session._action_received(id, "interact", {})

func _test_bootstrap_and_gate() -> void:
	_case("bootstrap_and_profile_gate")
	_instantiate()
	_check(session.profile_ready, "real _ready enables profile only after bootstrap")
	_check(not session.active and not session.owns_world, "launch does not automatically start a world")
	_check(session.store.root_path == "user://profiles_v3/" + profile, "explicit isolated launch profile used")
	var before: Dictionary = session.store.snapshot()
	_check(int(before.generation) > 0, "bootstrap created a durable generation")
	_check(before.ledger.commits.has("profile-bootstrap-v3"), "production bootstrap receipt exists")
	_disk_matches(session.store, before, "bootstrap identity")
	session.profile_ready = false
	for mode in ["solo", "host", "guest"]:
		_check(not session.start_flight(mode), "profile gate rejects " + mode)
	_check(not session.active and not session.owns_world and session.players.is_empty(), "blocked start has no live world or players")
	_check(session.store.snapshot() == before, "blocked starts preserve profile bytes")

func _test_guest_disconnect() -> void:
	_case("guest_disconnect_cannot_save_host_world")
	_fresh("guest_disconnect")
	var before: Dictionary = session.store.snapshot()
	# The displayed world now belongs to another host, with a deliberately distinct
	# persistent state. The real disconnected callback must destroy that state.
	session.owns_world = false
	session.network.mode = "guest"
	session.entities["I1:relay"].charge = 88.0
	session.entities["I1:thermal"].temperature = 123.0
	session.pending_packet = {"sequence":90}
	session.received_sequence = 89
	session.received_session = "old-host"
	session.network._server_left()
	_check(session.network.mode == "disconnected" and not session.network.is_authority(), "host departure never promotes guest to authority")
	_check(not session.active and not session.owns_world, "guest world ownership revoked")
	_check(session.world == null and session.players.is_empty() and session.entities.is_empty(), "remote world and bodies discarded")
	_check(session.pending_packet.is_empty() and session.received_sequence == -1 and session.received_session.is_empty(), "disconnect clears stale snapshots")
	_check(session._save_environment(), "disconnected save request is a harmless no-op")
	_check(session.store.snapshot() == before, "remote environment never enters personal world memory")
	_disk_matches(session.store, before, "guest disconnect")
	# A failed connection uses the same boundary even if an old world was present.
	_check(session.start_flight("solo"), "own solo world can reopen after disconnect")
	session.owns_world = false
	session.network.mode = "guest"
	session.network._connection_failed()
	_check(not session.active and session.world == null and not session.network.is_authority(), "connection failure leaves no authority or stale world")
	_check(session.store.snapshot() == before, "connection failure preserves durable personal world")

func _test_session_reset() -> void:
	_case("new_connection_rejects_old_snapshots")
	_fresh("connection_reset")
	session.received_sequence = 9000
	session.received_session = "previous-session"
	session.packet_sequence = 9100
	session.pending_packet = {"session_id":"previous-session", "sequence":9001}
	session.choice_proposal = {"proposal_id":"old-vote"}
	# An empty address deliberately fails before opening a socket. Resetting the
	# session is required even on failure and is exercised through start_flight.
	_check(not session.start_flight("guest", ""), "invalid new connection is rejected")
	_check(session.received_sequence == -1 and session.packet_sequence == 0 and session.received_session.is_empty(), "new connection resets both sequence spaces")
	_check(session.pending_packet.is_empty() and session.choice_proposal.is_empty(), "new connection clears packet and proposal backlog")
	_check(not session.active and not session.owns_world and session.world == null, "failed new connection cannot reuse previous world")
	_check(session.start_flight("solo"), "recovery creates a fresh real world")
	var packet: Dictionary = session._snapshot()
	packet.session_id = "new-host-session"
	packet.sequence = 1
	packet.players = {}
	packet.rewards = {}
	session.network.mode = "guest"
	session.owns_world = false
	session._apply_snapshot(packet)
	_check(session.received_sequence == 1 and session.received_session == "new-host-session", "sequence one accepted for the new host")
	var stale: Dictionary = packet.duplicate(true)
	stale.session_id = "previous-session"
	stale.sequence = 99999
	session._apply_snapshot(stale)
	_check(session.received_sequence == 1, "old host packet rejected even with larger sequence")
	packet.sequence = 2
	session._apply_snapshot(packet)
	_check(session.received_sequence == 2, "next current-session snapshot still accepted")

func _test_paused_snapshot_restore() -> void:
	_case("paused_first_snapshot_restores_scene")
	_fresh("paused_snapshot")
	session._load_region("F1")
	# A complete host snapshot is captured from the production scene. Growth and
	# angle are fixtures; their ability-to-physics chain is covered by art tests.
	session.entities["F1:growth"].growth = 0.7
	session.entities["F1:mirror"].angle = PI / 6.0
	session.entities["F1:relay"].charge = 70.0
	session.world.initialize_mechanisms(session.entities)
	session._action_received(1, "propose", {"kind":"pause", "payload":{}})
	_check(session.simulation_paused, "host pause fixture uses the real consensus action")
	var packet: Dictionary = session._snapshot()
	packet.session_id = "paused-host-session"
	packet.sequence = 1
	packet.rewards = {}
	var host_pose: Dictionary = packet.mechanisms.duplicate(true)
	# Destroy the prior world, exactly as disconnect does, so this must rebuild
	# geometry from the first incoming packet rather than reuse a grown bridge.
	session._network_event({"kind":"host_left"})
	_check(session.world == null and session.players.is_empty(), "paused reconnect begins without a retained scene")
	session.network.mode = "guest"
	session.active = true
	var before: Dictionary = session.store.snapshot()
	session._apply_snapshot(packet)
	_check(session.region_id == "F1" and session.world != null, "first paused packet builds the correct region")
	_check(session.simulation_paused and not session.world.local_authority, "first paused packet preserves host authority and pause")
	_check(session.world.growth_bridge.visible and session.world.growth_bridge.collision_layer == 1, "paused first packet immediately restores grown bridge visibility and collision")
	_check(session.world.objects["F1:crate"].freeze, "paused first packet immediately freezes dynamic crate")
	_check(session.players.has(1) and session.players[1].freeze, "paused first packet freezes its newly created flight body")
	_check(session.world.mechanism_snapshot() == host_pose, "paused first packet preserves exact host mechanism pose without integrating")
	_check(is_equal_approx(session.world.art_temple.rotor_body.rotation.z, PI / 6.0) and is_equal_approx(session.world.gate_fraction, 1.0), "paused ring and gate are already in their authoritative poses")
	packet.sequence = 2
	session._apply_snapshot(packet)
	_check(session.world.mechanism_snapshot() == host_pose and session.world.objects["F1:crate"].freeze, "repeated paused packet leaves pose and freeze state unchanged")
	_check(session.store.snapshot() == before, "paused remote growth and angle never enter the personal world save")
	_disk_matches(session.store, before, "paused reconnect personal world")

func _test_paused_guest_spawn() -> void:
	_case("host_pause_applies_to_new_roster")
	_fresh("paused_join_host")
	# Solo and LAN host share is_authority(). Keep the no-socket transport mode
	# while injecting the registered guest, as in the other lifecycle fixtures.
	session._action_received(1, "propose", {"kind":"pause", "payload":{}})
	_check(session.simulation_paused and session.players[1].freeze, "host is frozen by real pause consensus before join")
	var guest = _store("paused_join_guest")
	_join_fixture(42, guest)
	_check(session.players.has(42) and session.players[42].freeze, "new guest flight body is frozen immediately on a paused host")
	_check(session.simulation_paused and session.players[1].freeze and session.world.objects["I1:crate"].freeze, "joining does not resume existing pilots or dynamic environment")
	session._action_received(1, "propose", {"kind":"pause", "payload":{}})
	var proposal: Dictionary = session.consensus.current_proposal()
	_check(proposal.get("state") == "pending", "resume now requires both current players")
	session._action_received(42, "confirm", proposal)
	_check(not session.simulation_paused and not session.players[1].freeze and not session.players[42].freeze, "both pilots unfreeze only after agreed resume")
	_check(not session.world.objects["I1:crate"].freeze, "agreed resume releases unpinned host crate")
	_leave_fixture(42)

func _turn_ring(times: int) -> void:
	session.players[1].global_position = session.world.art_temple.to_global(Vector3(0, 5.2, 5))
	session.entities["player:1"].energy = 100.0
	for _index in range(times):
		session.cooldowns[1] = 0.0
		session._action_received(1, "ability", {"ability":"light", "target_id":"F1:mirror"})

func _test_receipt_channel_recovery() -> void:
	_case("reliable_receipt_batches_real_store_recovery")
	_fresh("receipt_batches")
	var host_store = session.store
	var visitor = _store("receipt_visitor")
	session.network.close()
	session.network.free()
	var transport = CapturedTransport.new()
	session.network = transport
	session.add_child(transport)
	transport.guest_joined.connect(session._guest_joined)
	transport.guest_left.connect(session._guest_left)
	transport.mode = "host"
	transport.session_id = "receipt-batch-session"
	session.receipts.reset()
	_join_fixture(22, visitor)
	var before: Dictionary = session._snapshot()
	before.erase("sequence")
	for i in range(12):
		_check(host_store.queue_guest_receipt(visitor.data.profile_id, "batch-discovery:" + str(i), {"discoveries":["batch-discovery:" + str(i)]}).ok, "durable backlog discovery " + str(i))
	var after: Dictionary = session._snapshot()
	after.erase("sequence")
	_check(var_to_bytes(before) == var_to_bytes(after), "twelve pending rewards add no bytes or fields to motion payload")
	_check(session.receipts.send_pending(22).count == 8, "real outbox delivers at most eight records in first reliable batch")
	if transport.sent_events.is_empty(): return
	var first: Dictionary = transport.sent_events[-1].event
	session.store = visitor
	session.owns_world = false
	transport.mode = "guest"
	session.received_session = transport.session_id
	visitor.failure_point = "before_publish"
	_check(not session.receipts.receive(first).ok and transport.sent_actions.is_empty(), "failed guest disk publication never acknowledges rewards")
	_check(visitor.snapshot().personal.discoveries.is_empty(), "failed receipt batch publishes no personal rewards")
	visitor.failure_point = ""
	_check(session.receipts.receive(first).count == 8, "recovered disk publishes the complete first batch")
	var generation = visitor.data.generation
	_check(session.receipts.receive(first).count == 8 and visitor.data.generation == generation, "delayed ACK replay neither duplicates discoveries nor rewrites disk")
	var ack: Dictionary = transport.sent_actions[-1]
	session.store = host_store
	session.owns_world = true
	transport.mode = "host"
	session.simulation_paused = true
	session._action_received(22, ack.verb, ack.payload)
	_check(host_store.pending_guest_receipts(visitor.data.profile_id).size() == 4, "paused real session accepts only the eight acknowledged records")
	session.receipts.tick(1.0)
	_check(transport.sent_events[-1].event == first, "ACK does not bypass the two second send interval")
	session.receipts.tick(1.0)
	var second: Dictionary = transport.sent_events[-1].event
	_check(second.receipts.size() == 4, "second interval sends only the remaining backlog")
	session.store = visitor
	session.owns_world = false
	transport.mode = "guest"
	_check(session.receipts.receive(second).count == 4, "remaining real receipts persist while the session is paused")
	ack = transport.sent_actions[-1]
	session.store = host_store
	session.owns_world = true
	transport.mode = "host"
	session._action_received(22, ack.verb, ack.payload)
	_check(host_store.pending_guest_receipts(visitor.data.profile_id).is_empty(), "all backlog records eventually acknowledged after disk recovery")
	_check(visitor.data.personal.discoveries.size() == 12, "twelve discoveries are retained exactly once")
	_disk_matches(visitor, visitor.snapshot(), "batched receipt visitor")
	session.simulation_paused = false
	transport.mode = "solo"

func _test_ring_angle_branch() -> void:
	_case("immediate_branch_switch_preserves_ring_angle")
	_fresh("ring_branch")
	_gate_interact()
	session._action_received(1, "propose", {"kind":"region_change", "payload":{"region_id":"F1"}})
	_check(session.region_id == "F1" and session.store.data.world.region_id == "F1", "real travel action enters and persists F1")
	_check(session._save_environment(), "initial ring pose is durable before branch creation")
	_check(session.store.fork_branch("before-turn", "before ring turn", false).ok, "independent pre-turn world branch exists")
	session.world_cache = session.store.snapshot()
	session.consensus.set_world_revision(int(session.world_cache.world_revision))
	var initial_angle: float = session.entities["F1:mirror"].angle
	var applied: int = session.stats.abilities
	_turn_ring(2)
	_check(session.stats.abilities == applied + 2 and is_zero_approx(float(session.entities["F1:mirror"].angle)), "two real light actions change the ring before autosave")
	_check(is_equal_approx(float(session.store.data.world.entities.F1["F1:mirror"].angle), initial_angle), "ring change is still unsaved when branch UI is invoked")
	session._ui_action("branch", {"id":"before-turn"})
	_check(session.store.data.world.branch_id == "before-turn" and is_equal_approx(float(session.entities["F1:mirror"].angle), initial_angle), "destination branch restores its independent initial ring angle")
	session._ui_action("branch", {"id":"main"})
	_check(session.store.data.world.branch_id == "main" and is_zero_approx(float(session.entities["F1:mirror"].angle)), "immediate return retains the unsaved-before-switch source angle")
	_check(is_zero_approx(session.world.art_temple.rotor_body.rotation.z), "returning ring collision pose matches saved angle before physics")
	_disk_matches(session.store, session.store.snapshot(), "immediate ring branch return")
	# A failed pre-switch save must retain the live, newer angle and old durable
	# snapshot. The error cannot be hidden by loading the requested target branch.
	_turn_ring(1)
	_check(is_equal_approx(float(session.entities["F1:mirror"].angle), PI / 6.0), "newer thirty-degree pose is live before simulated storage failure")
	var before: Dictionary = session.store.snapshot()
	var old_world = session.world
	session.store.failure_point = "before_publish"
	session._ui_action("branch", {"id":"before-turn"})
	_check(session.world == old_world and session.store.data.world.branch_id == "main", "failed angle save blocks branch scene replacement")
	_check(is_equal_approx(float(session.entities["F1:mirror"].angle), PI / 6.0) and session.store.snapshot() == before, "failed switch retains live angle and unchanged committed memory")
	_disk_matches(session.store, before, "failed angle save")
	session.store.failure_point = ""
	session._ui_action("branch", {"id":"before-turn"})
	session._ui_action("branch", {"id":"main"})
	_check(session.store.data.world.branch_id == "main" and is_equal_approx(float(session.entities["F1:mirror"].angle), PI / 6.0), "retry saves the retained angle before switching")
	_disk_matches(session.store, session.store.snapshot(), "retried angle save")

func _test_rewards_and_branch() -> void:
	_case("gate_guest_receipts_and_branch_replay")
	_fresh("gate_host")
	_check(session.store.fork_branch("before-gate", "before gate").ok, "pre-gate branch is durable")
	session.world_cache = session.store.snapshot()
	session.consensus.set_world_revision(int(session.world_cache.world_revision))
	_gate_interact()
	_check(session.store.data.world.flags.get("I1_gate", false), "solo gate updates the world")
	_check(session.store.data.personal.discoveries == ["gate:I1"], "solo gate awards discovery once")
	var guest_a = _store("guest_a")
	_join_fixture(22, guest_a)
	var pending: Array = session.store.pending_guest_receipts(guest_a.data.profile_id)
	_check(pending.size() == 1 and pending[0].reward_id == "gate:I1", "late guest is offered existing gate reward")
	_check(not session._snapshot().has("rewards"), "motion snapshots exclude durable receipt delivery")
	_gate_interact(22)
	_check(session.store.notice.is_empty(), "guest interaction after solo completion has no transaction conflict")
	if not pending.is_empty():
		_check(guest_a.apply_guest_receipt(pending[0]).ok, "guest durably accepts receipt")
		_check(guest_a.apply_guest_receipt(pending[0]).duplicate, "lost acknowledgment replay does not duplicate reward")
		session._action_received(22, "receipt_ack", {"receipt_id":pending[0].receipt_id})
	_check(session.store.pending_guest_receipts(guest_a.data.profile_id).is_empty(), "host persists real session acknowledgment")
	_leave_fixture(22)
	_join_fixture(23, guest_a)
	_check(session.store.pending_guest_receipts(guest_a.data.profile_id).is_empty(), "same guest identity reconnect does not regrant acknowledged reward")
	_leave_fixture(23)
	var guest_b = _store("guest_b")
	_join_fixture(24, guest_b)
	_gate_interact(24)
	_check(session.store.notice.is_empty(), "different guest revisiting unchanged gate does not conflict with prior roster")
	_check(session.store.pending_guest_receipts(guest_b.data.profile_id).size() == 1, "second guest catch-up remains exactly once")
	_leave_fixture(24)
	session._ui_action("branch", {"id":"before-gate"})
	_check(session.store.data.world.branch_id == "before-gate" and not session.store.data.world.flags.get("I1_gate", false), "real branch UI restores unfinished gate")
	_gate_interact()
	_check(session.store.data.world.flags.get("I1_gate", false), "gate can alter restored branch despite prior profile receipt")
	_check(session.store.data.personal.discoveries == ["gate:I1"], "branch replay preserves single personal discovery")
	_disk_matches(session.store, session.store.snapshot(), "branch replay")
	_disk_matches(guest_a, guest_a.snapshot(), "guest reward")

func _test_choice_failure() -> void:
	_case("major_choice_failure_retains_consensus")
	_fresh("choice_host")
	_gate_interact()
	var guest = _store("choice_guest")
	_join_fixture(32, guest)
	var branch_count: int = session.store.list_branches().size()
	session._action_received(1, "propose", {"kind":"major_choice", "payload":{"value":"shared"}})
	var proposal: Dictionary = session.consensus.current_proposal()
	_check(not proposal.is_empty() and proposal.get("state") == "pending", "host choice waits for guest confirmation")
	_check(session.store.list_branches().size() == branch_count + 1, "independent pre-choice branch saved before vote")
	_check(proposal.get("world_revision", -1) == session.store.data.world_revision, "proposal binds revision after backup creation")
	var before: Dictionary = session.store.snapshot()
	var pending_world = session.world
	var pending_branch = ""
	for branch_id in session.store.data.branches:
		if branch_id != session.store.data.world.branch_id:
			pending_branch = branch_id
			break
	session._ui_action("branch", {"id":pending_branch})
	_check(session.world == pending_world and session.store.snapshot() == before, "pending proposal blocks branch scene and save changes")
	_check(session.consensus.current_proposal() == proposal, "pending branch request preserves both participants' unfinished decision")
	session.store.failure_point = "before_publish"
	if not proposal.is_empty(): session._action_received(32, "confirm", proposal)
	var retry: Dictionary = session.consensus.current_proposal()
	_check(not retry.is_empty() and retry.get("state") == "ready" and retry.get("proposal_id") == proposal.get("proposal_id"), "failed durable choice keeps the same ready proposal")
	_check(session.store.snapshot() == before, "choice failure changes neither committed world nor branch list")
	_disk_matches(session.store, before, "choice failed publication")
	_check(session._save_environment() and session.store.snapshot() == before, "autosave cannot invalidate ready decision")
	var old_world = session.world
	_check(not session.start_flight("solo"), "switching session cannot discard a failed ready decision")
	_check(session.world == old_world and session.consensus.current_proposal().get("state") == "ready", "failed ready decision survives attempted switch")
	session.store.failure_point = ""
	var branch_target = ""
	for branch_id in session.store.data.branches:
		if branch_id != session.store.data.world.branch_id:
			branch_target = branch_id
			break
	_check(not branch_target.is_empty(), "ready-choice branch guard has a real alternate branch")
	session._ui_action("branch", {"id":branch_target})
	_check(session.world == old_world and session.store.snapshot() == before, "ready proposal blocks branch switch even after storage recovers")
	_check(session.consensus.current_proposal() == retry, "blocked branch leaves the ready proposal intact for explicit confirmation")
	if not retry.is_empty(): session._action_received(1, "confirm", retry)
	_check(session.store.data.world.choices.get("supply") == "shared", "explicit confirm retries and commits same choice")
	_check(session.consensus.current_proposal().is_empty(), "successful durable choice clears consensus")
	_check(session.store.list_branches().size() == branch_count + 1, "retry does not create extra backup branches")
	var backups_ok = true
	for branch_id in session.store.data.branches:
		if branch_id != session.store.data.world.branch_id and session.store.data.branches[branch_id].world.choices.has("supply"): backups_ok = false
	_check(backups_ok, "pre-choice branch still has the undecided world")
	_disk_matches(session.store, session.store.snapshot(), "choice retry")
	_leave_fixture(32)

func _test_boss_failure() -> void:
	_case("boss_completion_failure_can_retry")
	_fresh("boss_host")
	session._start_boss()
	_check(session.boss_active, "real session starts encounter")
	var before: Dictionary = session.store.snapshot()
	session.store.failure_point = "before_publish"
	session._handle_boss_events([{"type":"boss_defeated"}])
	_check(session.pending_completion and session.boss_active, "failed victory remains pending rather than falsely completed")
	_check(session.store.snapshot() == before, "failed victory awards nothing before durable commit")
	_disk_matches(session.store, before, "boss failed publication")
	session._action_received(1, "retry", {})
	_check(session.pending_completion and session.boss_active, "retry while storage fails preserves victory obligation")
	var old_world = session.world
	_check(not session.start_flight("solo"), "session switch cannot lose pending boss completion")
	_check(session.world == old_world and session.pending_completion, "pending victory survives blocked switch")
	session.store.failure_point = ""
	session._action_received(1, "retry", {})
	_check(not session.pending_completion and not session.boss_active, "successful explicit retry completes encounter")
	_check(session.store.data.world.flags.get("I1_boss", false), "victory world flag is durable")
	_check(session.store.data.personal.discoveries == ["boss:I1:harbor_whale"], "victory discovery awarded exactly once")
	var finished: Dictionary = session.store.snapshot()
	session._finish_boss()
	_check(session.store.snapshot() == finished, "repeated completion callback is a no-op")
	_disk_matches(session.store, finished, "boss retry")

func _test_pending_completion_travel() -> void:
	_case("cross_region_cannot_misattribute_pending_campaign_victory")
	_fresh("boss_travel")
	_gate_interact()
	session._start_boss()
	# This case isolates the storage/travel boundary, not authored story progression.
	session.boss_campaign = true
	session.store.failure_point = "before_publish"
	session._handle_boss_events([{"type":"boss_defeated"}])
	var before: Dictionary = session.store.snapshot()
	var old_world = session.world
	session._action_received(1, "propose", {"kind":"region_change", "payload":{"region_id":"F1"}})
	_check(session.pending_completion and session.region_id == "I1" and session.world == old_world, "failed pending victory prevents crossing out of its original arena")
	_check(session.consensus.current_proposal().is_empty() and session.store.snapshot() == before, "failed travel request makes neither proposal nor save change")
	_check(not session._save_environment(), "pending victory cannot be reported as successful environment save")
	session.store.failure_point = ""
	session._action_received(1, "propose", {"kind":"region_change", "payload":{"region_id":"F1"}})
	_check(not session.pending_completion and session.region_id == "F1", "recovered storage commits victory before crossing")
	var flags: Dictionary = session.store.snapshot().world.flags
	_check(flags.get("I1_boss", false) and flags.get("campaign_whale_v1", false) and not flags.get("F1_boss", false), "crossing never reattributes I1 campaign victory to F1")
	_disk_matches(session.store, session.store.snapshot(), "campaign victory before travel")

func _test_pending_completion_branch() -> void:
	_case("branch_cannot_discard_pending_victory")
	_fresh("boss_branch")
	_check(session.store.fork_branch("before-boss", "before victory", false).ok, "pre-victory alternate branch exists")
	session.world_cache = session.store.snapshot()
	session.consensus.set_world_revision(int(session.world_cache.world_revision))
	session._start_boss()
	var before: Dictionary = session.store.snapshot()
	var old_world = session.world
	session.store.failure_point = "before_publish"
	session._handle_boss_events([{"type":"boss_defeated"}])
	_check(session.pending_completion and session.boss_active, "failed victory supplies a real pending completion")
	session._ui_action("branch", {"id":"before-boss"})
	_check(session.world == old_world and session.store.data.world.branch_id == "main" and session.pending_completion, "branch stays in current scene while pending victory still cannot save")
	_check(session.store.snapshot() == before, "blocked pending-victory switch commits neither reward nor branch")
	_disk_matches(session.store, before, "pending victory blocked branch")
	# The established session policy retries the pending write on a branch attempt.
	# Once that write succeeds the same click may switch; no extra ritual is needed.
	session.store.failure_point = ""
	session._ui_action("branch", {"id":"before-boss"})
	_check(not session.pending_completion and not session.boss_active, "recovered storage finishes pending victory before changing branches")
	_check(session.store.data.world.branch_id == "before-boss", "branch request proceeds after the required victory save succeeds")
	_check(session.store.data.branches.main.world.flags.get("I1_boss", false), "source branch retains durable victory after changing away")
	_check(not session.store.data.world.flags.get("I1_boss", false), "destination pre-victory branch keeps its independent story state")
	_check(session.store.data.personal.discoveries == ["boss:I1:harbor_whale"], "retry-on-switch grants exactly one persistent personal discovery")
	session._ui_action("branch", {"id":"main"})
	_check(session.store.data.world.flags.get("I1_boss", false) and not session.pending_completion, "return to source branch preserves saved victory without pending replay")
	_disk_matches(session.store, session.store.snapshot(), "victory saved before branch switch")

func _test_failed_load_gate() -> void:
	_case("future_profile_blocks_real_ready")
	_dispose_session()
	var launch_root = "user://profiles_v3/" + profile
	var future_path = launch_root.path_join("profile_g999999999999.json")
	var content = JSON.stringify({"schema_version":999, "format":1})
	var file = FileAccess.open(future_path, FileAccess.WRITE)
	_check(file != null, "future version fixture only in unique launch QA profile")
	if file == null: return
	file.store_string(content)
	file.close()
	_instantiate()
	_check(not session.profile_ready and session.store.read_only, "real _ready rejects future version profile")
	for mode in ["solo", "host", "guest"]:
		_check(not session.start_flight(mode), "failed-load entry point rejects " + mode)
	_check(FileAccess.get_file_as_string(future_path) == content, "future generation never overwritten")
	_check(not session.active and session.world == null, "future profile cannot enter gameplay")

func _write_report() -> void:
	var source_hashes: Dictionary = {}
	for path in ["res://scripts/v3/twin_session.gd", "res://scripts/v3/twin_test_world.gd", "res://scripts/v3/art/twin_service_bridge.gd", "res://scripts/v3/art/twin_temple_gate.gd", "res://scripts/v3/twin_network.gd", "res://scripts/v3/core/twin_world_store.gd", "res://scripts/v3/core/twin_consensus.gd", "res://tests_v3/test_session_persistence.gd"]:
		source_hashes[path] = FileAccess.get_sha256(path)
	var result = {"suite":"real_session_persistence", "started_utc":started_utc, "finished_utc":Time.get_datetime_string_from_system(true) + "Z", "checks":checks, "check_count":checks.size(), "failures":failures, "passed":failures.is_empty(), "cases":cases, "profile":profile, "qa_root":ProjectSettings.globalize_path(base), "launch_profile_root":ProjectSettings.globalize_path("user://profiles_v3/" + profile), "engine":Engine.get_version_info(), "source_sha256":source_hashes, "limits":["Real main.tscn instances with processing disabled for deterministic transaction checks.", "Network registration/disconnection callbacks and boss completion events injected; no packet loss, actual two-process ENet, rendering, or human gameplay acceptance is claimed.", "Only unique qa_session launch profile and qa_v3_session stores are written."]}
	DirAccess.make_dir_recursive_absolute(REPORT_PREFIX.get_base_dir())
	var output = FileAccess.open(REPORT_PREFIX + "-" + profile + ".json", FileAccess.WRITE)
	if output != null:
		output.store_string(JSON.stringify(result, "\t"))
		output.close()
	else:
		failures.append("Could not write authorized report artifact")
