extends SceneTree
## Controlled two-process ENet peer. Run only through test_crown_lan.py after asset/code freeze.
const WEST := "F1:crown_host_west"
const CORE := "boss:crown_core"
const MODEL := "res://assets/v3/crown/parasitic_crown.glb"

class PeerSession extends "res://scripts/v3/twin_session.gd":
	var qa_owner
	func _physics_process(delta: float) -> void:
		qa_owner.hold_bodies(self)
		super._physics_process(delta)
		if qa_owner.fire_remaining > 0.0 and network.mode == "guest":
			network.send_input({"active":true,"planar":Vector3.ZERO,"vertical":0.0,"brake":true,"fire":true})
			qa_owner.last_fire_sequence = network._sequence
			qa_owner.fire_remaining = maxf(0.0, qa_owner.fire_remaining - delta)
		qa_owner.hold_bodies(self)
	func _process(delta: float) -> void:
		var incoming: Dictionary = pending_packet.duplicate(true)
		super._process(delta)
		# This is immediately after production snapshot application, with no physics wait.
		if not incoming.is_empty() and received_sequence == int(incoming.get("sequence", -2)):
			qa_owner.applied_snapshot(self, incoming)
		qa_owner.hold_bodies(self)

var session
var role := ""
var label := ""
var profile := ""
var run_id := ""
var evidence := ""
var expected_sha := ""
var reconnect := false
var ack := 0
var result: Dictionary = {}
var errors: Array = []
var commands: Array = []
var notices: Array = []
var received_events: Array = []
var first_crown_snapshot: Dictionary = {}
var first_paused_snapshot: Dictionary = {}
var latest_probe: Dictionary = {}
var applied_count := 0
var fire_remaining := 0.0
var last_fire_sequence := -1
var saved_receipt: Dictionary = {}
var started_msec := 0
var host_left_seen := false
var initial_profile_id := ""
var initial_personal: Dictionary = {}
var last_controller_heartbeat := 0.0

func _initialize() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--qa-profile="): profile = argument.trim_prefix("--qa-profile=")
		elif argument.begins_with("--qa-crown-role="): role = argument.trim_prefix("--qa-crown-role=")
		elif argument.begins_with("--qa-crown-label="): label = argument.trim_prefix("--qa-crown-label=")
		elif argument.begins_with("--qa-crown-run="): run_id = argument.trim_prefix("--qa-crown-run=")
		elif argument.begins_with("--qa-crown-evidence="): evidence = argument.trim_prefix("--qa-crown-evidence=").replace("\\", "/").simplify_path()
		elif argument.begins_with("--qa-crown-sha="): expected_sha = argument.trim_prefix("--qa-crown-sha=")
		elif argument == "--qa-crown-reconnect": reconnect = true
		elif argument.begins_with("--qa-network="):
			push_error("Crown driver refuses the unrelated automatic-flight QA entry.")
			quit(2)
			return
	var base := ProjectSettings.globalize_path("res://artifacts/v3/network/crown/").replace("\\", "/").trim_suffix("/") + "/"
	if role not in ["host", "guest"] or label not in ["host", "guest_first", "guest_reconnect"] or not profile.begins_with("qa_crown_lan_") or profile != profile.validate_filename() or run_id.is_empty() or not evidence.begins_with(base):
		push_error("Invalid isolated Crown LAN QA arguments.")
		quit(2)
		return
	if expected_sha.length() != 64 or not FileAccess.file_exists(MODEL) or FileAccess.get_sha256(MODEL) != expected_sha:
		push_error("Frozen Crown GLB hash is required before any ENet peer starts.")
		quit(2)
		return
	var exists := DirAccess.dir_exists_absolute("user://profiles_v3/" + profile)
	if exists != reconnect or (reconnect and role != "guest"):
		push_error("Only the explicitly marked guest reconnect may reuse its isolated profile.")
		quit(2)
		return
	if not _controller_alive():
		push_error("Missing live locked Python controller; direct peer launch refused.")
		quit(2)
		return
	started_msec = Time.get_ticks_msec()
	_boot.call_deferred()

func _boot() -> void:
	session = PeerSession.new()
	session.qa_owner = self
	root.add_child(session)
	if not session.profile_ready or session.network.PROTOCOL != 21:
		_fail("isolated profile and protocol 21 are required")
		_finish(2)
		return
	session.inputs.set_process(false)
	session.inputs.set_physics_process(false)
	session.network.status_changed.connect(func(message): _bounded_append(notices, {"text":message,"time_ms":Time.get_ticks_msec() - started_msec}))
	session.network.event_received.connect(_network_event)
	var saved: Dictionary = session.store.snapshot()
	initial_profile_id = str(saved.profile_id)
	initial_personal = saved.personal.duplicate(true)
	if not session.start_flight(role, "127.0.0.1"):
		_fail("production session could not start " + role)
		_finish(2)
		return
	if role == "host":
		session._load_region("F1")
		if not session.crown.ready():
			_fail("real Crown arena/assets are not imported and ready")
			_finish(2)
			return
	var timer := Timer.new()
	timer.wait_time = 0.05
	timer.timeout.connect(_poll)
	root.add_child(timer)
	timer.start()
	_write_state()

func hold_bodies(current) -> void:
	# QA staging keeps real rigid bodies/colliders in authored test poses. Rules still use real time.
	for body in current.players.values():
		body.freeze = true
		body.linear_velocity = Vector3.ZERO
		body.angular_velocity = Vector3.ZERO

func applied_snapshot(current, packet: Dictionary) -> void:
	applied_count += 1
	var boss: Dictionary = packet.get("boss", {})
	if boss.get("type") != "parasitic_crown": return
	var observation: Dictionary = {"sequence":packet.sequence,"paused":packet.paused,"boss":boss.duplicate(true),
		"probe":_probe_core(),"warning_count":current.world.crown_arena.warnings.size(),"physics_frame":Engine.get_physics_frames()}
	latest_probe = observation
	if first_crown_snapshot.is_empty(): first_crown_snapshot = observation.duplicate(true)
	if packet.paused and first_paused_snapshot.is_empty(): first_paused_snapshot = observation.duplicate(true)

func _probe_core() -> Dictionary:
	if not is_instance_valid(session) or not is_instance_valid(session.world) or not session.crown.ready(): return {"ready":false}
	var model = session.world.crown_arena.model
	var centre: Vector3 = model.to_local(model.core_position())
	var hits: Array = []
	for x in [-0.20, 0.0, 0.20]:
		for y in [-0.30, 0.0, 0.30]:
			var from: Vector3 = model.to_global(centre + Vector3(x, y, 5.0))
			var to: Vector3 = model.to_global(centre + Vector3(x, y, -0.05))
			var query := PhysicsRayQueryParameters3D.create(from, to, 8)
			var hit: Dictionary = session.get_world_3d().direct_space_state.intersect_ray(query)
			hits.append("empty" if hit.is_empty() else str(hit.collider.get_meta("entity_id", "unknown")))
	return {"ready":true,"hits":hits,"core":model.core_position(),"model_position":model.global_position}

func _poll() -> void:
	if not _controller_alive() or Time.get_ticks_msec() - started_msec > 180000:
		_fail("controller heartbeat expired or three-minute peer limit reached")
		_finish(2)
		return
	var path := evidence.path_join(label + "-command.json")
	if FileAccess.file_exists(path):
		var parsed = _read_json(path)
		if parsed is Dictionary and parsed.get("run_id") == run_id and int(parsed.get("sequence", 0)) > ack:
			ack = int(parsed.sequence)
			var args = parsed.get("args", {})
			result = _execute(str(parsed.get("verb", "")), args if args is Dictionary else {})
			_bounded_append(commands, {"sequence":ack,"verb":parsed.get("verb"),"args":args,"result":result.duplicate(true),"time_ms":Time.get_ticks_msec() - started_msec})
			if not result.get("ok", false): _fail("command " + str(parsed.get("verb")) + ": " + str(result.get("error", "failed")))
			if parsed.get("verb") == "shutdown":
				_write_state(true)
				session._quit()
				return
	_write_state()

func _execute(verb: String, args: Dictionary) -> Dictionary:
	if verb == "shutdown":
		return {"ok":true}
	if verb == "state": return {"ok":true}
	if verb == "action":
		if str(args.get("verb")) not in ["ability", "lock"]: return {"ok":false,"error":"unsupported QA intent"}
		session.network.send_action(str(args.verb), args.get("payload", {}))
		return {"ok":true,"transport_sequence":session.network._sequence}
	if verb == "fire":
		if role != "guest": return {"ok":false,"error":"shooting fixture uses real guest input RPC"}
		fire_remaining = clampf(float(args.get("seconds", 0.3)), 0.05, 0.4)
		return {"ok":true}
	if verb == "replay_fire":
		if role != "guest" or last_fire_sequence < 0: return {"ok":false,"error":"no previously issued input sequence"}
		session.network.rpc_id(1, "_receive_input", last_fire_sequence, {"active":true,"planar":Vector3.ZERO,"vertical":0.0,"brake":true,"fire":true})
		return {"ok":true,"replayed_sequence":last_fire_sequence}
	if role != "host": return {"ok":false,"error":"host fixture required"}
	var guest := _guest_peer()
	if verb == "fixture_split":
		if guest == 0: return {"ok":false,"error":"guest has not joined"}
		if not _near_host(1, WEST, -1.8): return {"ok":false,"error":"host staging pose overlaps actual geometry"}
		if not _place(guest, session.world.spawn_position + Vector3(3, 0, 0)): return {"ok":false,"error":"south staging pose overlaps actual geometry"}
		var started: bool = session.crown.start(false)
		return {"ok":started,"fixture":"direct QA encounter start; no story completion fabricated"}
	if verb == "near_host":
		var peer := 1 if args.get("peer", "guest") == "host" else guest
		return {"ok":peer > 0 and _near_host(peer, str(args.get("target", WEST)), -1.8 if peer == 1 else 1.8)}
	if verb == "reset_pair":
		if guest == 0 or not session.crown.active(): return {"ok":false,"error":"two active peers and encounter required"}
		session.crown.retry()
		var placed := _near_host(1, WEST, -1.8) and _near_host(guest, WEST, 1.8)
		session.cooldowns.clear()
		session.weapon_cooldowns.clear()
		session.crown.sync_players()
		return {"ok":placed,"fixture":"whole-attempt retry plus explicit pose/cooldown staging"}
	if verb == "shooter":
		return {"ok":guest > 0 and _place(guest, session.world.crown_arena.core_position() + Vector3(0, 0.15, 7))}
	if verb == "pause":
		session.simulation_paused = bool(args.get("value", true))
		session._apply_pause_state()
		return {"ok":true,"fixture":"QA sets pause directly; not a consensus acceptance test"}
	if verb == "receipt":
		if guest == 0: return {"ok":false,"error":"no guest identity"}
		var reward := "qa:crown_lan:" + run_id
		var queued: Dictionary = session.store.queue_guest_receipt(str(session.identities[guest]), reward, {"discoveries":[reward]})
		if not queued.get("ok", false): return queued
		saved_receipt = queued.receipt.duplicate(true)
		session.world_cache = session.store.snapshot()
		session.receipts.send_pending(guest)
		return {"ok":true,"reward_id":reward,"receipt_id":saved_receipt.receipt_id,"fixture":"QA discovery uses real durable outbox; not a Boss victory reward claim"}
	if verb == "resend_receipt":
		if guest == 0 or saved_receipt.is_empty(): return {"ok":false,"error":"no issued receipt"}
		session.network.send_event(guest, {"kind":"receipt_batch","session_id":session.network.session_id,"receipts":[saved_receipt.duplicate(true)]})
		return {"ok":true,"fixture":"deliberate reliable duplicate delivery"}
	return {"ok":false,"error":"unknown command"}

func _near_host(peer: int, id: String, side: float) -> bool:
	var point: Vector3 = session.world.crown_arena.host_position(id)
	return point.is_finite() and _place(peer, point + Vector3(side, 0, 5))

func _place(peer: int, point: Vector3) -> bool:
	if not session.players.has(peer) or not point.is_finite(): return false
	var body = session.players[peer]
	var shape := BoxShape3D.new()
	shape.size = Vector3(body.stats.width_m, body.stats.height_m, body.stats.length_m)
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = shape
	query.transform = Transform3D(Basis.IDENTITY, point)
	query.collision_mask = 1 | 2 | 8
	query.exclude = [body.get_rid()]
	if not session.get_world_3d().direct_space_state.intersect_shape(query, 1).is_empty(): return false
	body.global_position = point
	body.safe_position = point
	body.hold_height = point.y
	body.linear_velocity = Vector3.ZERO
	body.angular_velocity = Vector3.ZERO
	body.freeze = true
	body.force_update_transform()
	PhysicsServer3D.body_set_state(body.get_rid(), PhysicsServer3D.BODY_STATE_TRANSFORM, body.global_transform)
	session.entities[session._actor_id(peer)].position = point
	return true

func _guest_peer() -> int:
	if session.network.guests.size() != 1: return 0
	return int(session.network.guests.keys()[0])

func _network_event(event: Dictionary) -> void:
	if event.get("kind") == "host_left": host_left_seen = true
	_bounded_append(received_events, {"kind":event.get("kind"),"time_ms":Time.get_ticks_msec() - started_msec,
		"receipt_ids":event.get("receipts", []).map(func(item): return item.get("receipt_id", "")) if event.get("kind") == "receipt_batch" else []})

func _controller_alive() -> bool:
	var path := evidence.path_join("controller.json")
	var controller = _read_json(path)
	var now := Time.get_unix_time_from_system()
	if controller == null:
		# Windows can briefly deny a read while the controller atomically
		# publishes its next heartbeat. Honor only the last verified lease;
		# failed reads never renew it, and first launch still requires proof.
		return last_controller_heartbeat > 0.0 and now - last_controller_heartbeat < 20.0
	if not controller is Dictionary or controller.get("run_id") != run_id or not controller.get("lock_held", false) or controller.get("crown_sha256") != expected_sha: return false
	last_controller_heartbeat = float(controller.get("heartbeat_unix", 0))
	return now - last_controller_heartbeat < 20.0

func _read_json(path: String):
	if not FileAccess.file_exists(path): return null
	var text := FileAccess.get_file_as_string(path)
	if text.is_empty(): return null
	var parser := JSON.new()
	return parser.data if parser.parse(text) == OK else null

func _state() -> Dictionary:
	var roster: Dictionary = {}
	for peer in session.players:
		var body = session.players[peer]
		roster[str(peer)] = {"position":body.global_position,"health":body.health,"enabled":body.enabled,"identity":session.identities[peer],
			"energy":session.entities.get(session._actor_id(peer), {}).get("energy", -1),"lock":session.locks.get(peer, "")}
	var boss: Dictionary = session.crown.presentation() if session.network.is_authority() and session.crown.active() else session.world_cache.get("remote_boss", {})
	var mechanism: Dictionary = session.crown.encounter.get_state() if role == "host" else {}
	var personal: Dictionary = session.store.snapshot()
	return {"qa_scripted":true,"role":role,"label":label,"run_id":run_id,"profile":profile,"profile_id":initial_profile_id,
		"initial_personal":initial_personal,"protocol":session.network.PROTOCOL,"network_mode":session.network.mode,"active":session.active,
		"session_id":session.network.session_id if role == "host" else session.received_session,"peer_id":session.network.local_id(),"region":session.region_id,
		"players":roster,"boss":boss,"crown_players":mechanism.get("players", {}),"shot_sequences":session.crown.shot_sequences.duplicate(),
		"stats":session.stats.duplicate(),"transport":session.network.telemetry.duplicate(),"paused":session.simulation_paused,
		"received_sequence":session.received_sequence,"applied_count":applied_count,"first_crown_snapshot":first_crown_snapshot,
		"first_paused_snapshot":first_paused_snapshot,"latest_probe":latest_probe,"host_probe":_probe_core() if role == "host" else {},
		"generation":personal.generation,"personal":personal.personal,"guest_received_count":personal.ledger.guest_received.size(),
		"pending_receipts":session.store.pending_guest_receipts(str(session.identities.get(_guest_peer(), ""))).size() if role == "host" else 0,
		"host_left_seen":host_left_seen,"notices":notices,"events":received_events,"commands":commands,"ack":ack,"result":result,
		"last_fire_sequence":last_fire_sequence,"fire_remaining":fire_remaining,"errors":errors,"user_dir":OS.get_user_data_dir(),"elapsed_ms":Time.get_ticks_msec() - started_msec}

func _write_state(final: bool = false) -> void:
	if not is_instance_valid(session): return
	var state: Dictionary = _state()
	state["final"] = final
	var file := FileAccess.open(evidence.path_join(label + "-state.json"), FileAccess.WRITE)
	if file != null: file.store_string(JSON.stringify(_json_value(state), "\t"))
	else: push_error("Unable to write Crown peer evidence.")

func _json_value(value):
	if value is Vector3: return [value.x, value.y, value.z]
	if value is Dictionary:
		var mapped: Dictionary = {}
		for key in value: mapped[str(key)] = _json_value(value[key])
		return mapped
	if value is Array:
		var mapped: Array = []
		for item in value: mapped.append(_json_value(item))
		return mapped
	return value

func _bounded_append(items: Array, value: Dictionary) -> void:
	items.append(value)
	if items.size() > 64: items.pop_front()

func _fail(message: String) -> void:
	errors.append(message)
	push_error(message)

func _finish(code: int) -> void:
	_write_state(true)
	if is_instance_valid(session) and is_instance_valid(session.network): session.network.close()
	quit(code)
