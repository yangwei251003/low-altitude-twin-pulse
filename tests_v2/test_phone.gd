extends SceneTree

var server: Node
var failures: Array[String] = []
var mode := "unit"
var deadline := 0
var auto_approved := false
var frames := 0
var suspensions := 0
var checks: Array[String] = []
var probe: WebSocketPeer
var probe_messages: Array[Dictionary] = []
var probe_token := ""
var probe_epoch := 0
var probe_lease := ""
var probe_seq := 0

func _initialize() -> void:
	var base: String = get_script().resource_path.get_base_dir().get_base_dir()
	var source: GDScript = load(base.path_join("scripts/v2/phone_server.gd"))
	if source == null or not source.can_instantiate():
		printerr("PHONE_TEST: script load failed")
		quit(1)
		return
	server = source.new()
	server.asset_root = base.path_join("phone")
	root.add_child.call_deferred(server)
	_run.call_deferred()

func _check(condition: bool, name: String) -> void:
	checks.append(name)
	if not condition:
		failures.append(name)
	print(("PASS " if condition else "FAIL ") + name)

func _run() -> void:
	var frame := {"schema": 2, "control_epoch": 1, "seq": 1, "sample_ms": 1,
		"axes": {"left_x": 0, "left_y": 0.2, "right_x": -0.3, "right_y": 0.4},
		"held": ["fire"], "edges": [{"id": 1, "action": "tool", "kind": "pressed"}],
		"context": "flight", "neutral": false}
	_check(server._frame_error(frame) == "", "valid frame")
	for action in ["utility", "target"]:
		var ability_frame: Dictionary = frame.duplicate(true)
		ability_frame.edges[0].action = action
		_check(server._frame_error(ability_frame) == "", "ability/guard action accepted: " + action)
	var bad: Dictionary = frame.duplicate(true)
	bad.axes.left_y = NAN
	_check(server._frame_error(bad) == "BAD_AXIS", "NaN rejected")
	bad = frame.duplicate(true)
	bad.axes.left_y = 1.001
	_check(server._frame_error(bad) == "BAD_AXIS", "out of range rejected")
	bad = frame.duplicate(true)
	bad.seq = 0.5
	_check(server._frame_error(bad) == "BAD_SCHEMA_OR_SEQUENCE", "fractional sequence rejected")
	bad = frame.duplicate(true)
	bad.edges[0].action = "purchase"
	_check(server._frame_error(bad) == "BAD_EDGE", "action whitelist")
	_check(server._parse_header("GET /../pilot.json HTTP/1.1\r\nHost: 127.0.0.1:8765\r\n\r\n").is_empty(), "path traversal rejected")
	_check(server._parse_header("GET /%2e%2e/pilot.json HTTP/1.1\r\nHost: 127.0.0.1:8765\r\n\r\n").is_empty(), "encoded path rejected")
	_check(server._parse_header("GET / HTTP/1.1\r\nHost: one\r\nHost: two\r\n\r\n").is_empty(), "duplicate Host rejected")
	_check(server._parse_header("POST / HTTP/1.1\r\nHost: one\r\n\r\n").is_empty(), "POST rejected")
	_check(server._parse_header("GET / HTTP/1.1\r\nHost: one\r\nX-Long: " + "x".repeat(8200) + "\r\n\r\n").is_empty(), "header bound")
	_check(server._parse_header("GET / HTTP/1.1\r\nHost: one\r\nTransfer-Encoding: chunked\r\n\r\n").is_empty(), "request bodies rejected")
	_check(server._parse_header("GET / HTTP/1.1\r\nHost: one\r\n\r\nGET / HTTP/1.1\r\n\r\n").is_empty(), "request smuggling rejected")
	var connection := {"peer": null, "violations": 0}
	var now := Time.get_ticks_msec()
	server._state = "Active"
	server._epoch = 1
	server._leases = {"valid": now, "expired": now - 251}
	var message := {"frame": frame, "lease_nonce": "valid"}
	server._receive_input(connection, message, now)
	_check(server._pending_edges.size() == 1 and server._last_input == now, "accepted edge queued once")
	server._receive_input(connection, message, now + 20)
	_check(server._pending_edges.size() == 1 and server._last_input == now, "duplicate seq cannot refresh watchdog")
	frame.seq = 2
	server._receive_input(connection, message, now + 30)
	_check(server._pending_edges.size() == 1, "edge repeated in new frame is deduplicated")
	frame.seq = 3
	message.lease_nonce = "expired"
	server._receive_input(connection, message, now + 40)
	_check(server._last_seq == 2 and server._last_input == now + 30, "expired lease cannot refresh accepted sequence")
	message.lease_nonce = "valid"
	frame.control_epoch = 0
	server._receive_input(connection, message, now + 45)
	_check(server._last_seq == 2, "old epoch rejected")
	frame.control_epoch = 1
	frame.neutral = true
	server._receive_input(connection, message, now + 50)
	_check(server._pending.axes.left_y == 0 and server._pending.held.is_empty() and server._pending_edges.is_empty(), "neutral overrides axis held and pending edges")
	_manual_suspend_unit(frame, connection, now)
	server._state = "Stopped"
	server._pending = {}
	_check(server.start_server("127.0.0.1") == OK, "localhost listeners")
	var status: Dictionary = server.get_status()
	_check(not status.has("token") and str(status.pair_code).length() == 6, "status omits token")
	_check(not server.resume_control(), "resume without pairing refused")
	_check(not server.approve_control(), "approve without pairing refused")
	var second: Node = server.get_script().new()
	second.asset_root = server.asset_root
	_check(second.start_server("127.0.0.1") == OK and second.get_status().http_port != status.http_port, "occupied port selects distinct pair")
	second.stop_server()
	second.free()
	var qr: Image = server.get_pair_qr_image()
	_check(qr != null and qr.get_width() > 100, "offline QR generation")
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--qr-output="):
			_check(qr.save_png(argument.trim_prefix("--qr-output=")) == OK, "QR verification artifact")
	await _network_suspend_checks()
	status = server.get_status()
	server.input_frame.connect(func(_frame: Dictionary): frames += 1)
	server.suspended.connect(func(_reason: String): suspensions += 1)
	if "--serve" in OS.get_cmdline_user_args():
		mode = "serve"
		paused = true
		deadline = Time.get_ticks_msec() + 60000
		print("PHONE_READY " + JSON.stringify(status))
	else:
		_finish()

func _manual_suspend_unit(frame: Dictionary, connection: Dictionary, now: int) -> void:
	var observed := {"zeros": 0, "suspensions": 0, "last": {}}
	var on_zero := func(value: Dictionary) -> void:
		observed.zeros += 1
		observed.last = value
		server.suspend_control("recursive-zero")
	var on_suspended := func(_reason: String) -> void:
		observed.suspensions += 1
		server.suspend_control("recursive-signal")
	var on_status := func() -> void: server.suspend_control("recursive-status")
	server.input_frame.connect(on_zero)
	server.suspended.connect(on_suspended)
	server.status_changed.connect(on_status)
	var old_epoch: int = server._epoch
	server.suspend_control("manual")
	_check(server._state == "Stale" and server._reason == "manual" and server._epoch == old_epoch + 1, "manual pause invalidates epoch before callbacks")
	_check(server._leases.is_empty() and server._pending.is_empty() and server._pending_edges.is_empty() and not server._neutral, "manual pause clears lease neutral and queued actions")
	_check(observed.zeros == 1 and observed.suspensions == 1 and observed.last.neutral and observed.last.held.is_empty(), "manual pause emits one zero and one suspension under callback reentry")
	server.suspend_control("settings")
	server.suspend_control("map")
	_check(server._epoch == old_epoch + 1 and observed.suspensions == 1, "repeated manual settings and map interruption is idempotent")
	frame.control_epoch = old_epoch
	frame.seq = 100
	server._receive_input(connection, {"frame": frame, "lease_nonce": "valid"}, now + 60)
	_check(not server._neutral and server._last_seq == -1 and server._pending.is_empty(), "queued old-epoch neutral cannot unlock resume")
	server.input_frame.disconnect(on_zero)
	server.suspended.disconnect(on_suspended)
	server.status_changed.disconnect(on_status)
	server._state = "TakingControl"
	server.suspend_control("manual")
	_check(server._state == "Stale" and server._epoch == old_epoch + 2, "pause during taking-control also invalidates handover")
	server._state = "Listening"
	server.suspend_control()
	_check(server._state == "Listening" and server._epoch == old_epoch + 2, "unpaired listener is unaffected by manual suspension")

func _network_suspend_checks() -> void:
	var status: Dictionary = server.get_status()
	probe = WebSocketPeer.new()
	probe.supported_protocols = PackedStringArray(["las-v2"])
	probe.handshake_headers = PackedStringArray(["Origin: http://127.0.0.1:%d" % status.http_port])
	var error := probe.connect_to_url("ws://127.0.0.1:%d/control" % status.ws_port)
	_check(error == OK, "pause probe starts a real loopback WebSocket")
	var hello := await _probe_wait("hello")
	if hello.is_empty():
		_check(false, "pause probe handshake completed")
		probe.close(-1)
		return
	_probe_send({"type": "hello", "protocol": 2, "session_id": server._session, "page_nonce": "manual-pause-test"})
	_probe_send({"type": "pair", "code": status.pair_code, "requested_role": "controller"})
	var paired := await _probe_wait("paired")
	if paired.is_empty():
		_check(false, "pause probe paired")
		probe.close(-1)
		return
	probe_token = paired.token
	_check(server.approve_control(), "pause probe receives explicit computer approval")
	await _probe_wait("status", "TakingControl")
	_probe_input(0.0, true)
	await _probe_wait("ack")
	_probe_send({"type": "resume", "token": probe_token})
	var active := await _probe_wait("status", "Active")
	_check(not active.is_empty(), "pause probe starts active only after neutral and resume")
	_probe_input(0.7, false)
	await _probe_wait("ack")
	var old_epoch := probe_epoch
	var old_lease := probe_lease
	server.suspend_control("manual")
	var suspended_status := await _probe_wait("status", "Stale")
	_check(not suspended_status.is_empty() and suspended_status.reason == "manual" and probe_epoch > old_epoch, "computer manual pause announces a fresh epoch over WebSocket")
	_probe_send({"type": "resume", "token": probe_token})
	var refused := await _probe_wait("error")
	_check(refused.get("code") == "CENTER_STICKS_OR_COMPUTER_APPROVAL" and not server.get_status().active, "resume immediately after manual pause is rejected")
	var stale := _probe_frame(0.0, true)
	stale.frame.control_epoch = old_epoch
	stale.lease_nonce = old_lease
	_probe_send(stale)
	_probe_send({"type": "resume", "token": probe_token})
	refused = await _probe_wait("error")
	_check(refused.get("code") == "CENTER_STICKS_OR_COMPUTER_APPROVAL" and not server.get_status().neutral, "old-epoch centered packet cannot unlock manual pause")
	_probe_input(0.7, false)
	await _probe_wait("ack")
	_probe_send({"type": "resume", "token": probe_token})
	refused = await _probe_wait("error")
	_check(refused.get("code") == "CENTER_STICKS_OR_COMPUTER_APPROVAL" and not server.get_status().active, "fresh-epoch held stick still cannot resume")
	_probe_input(0.0, true)
	await _probe_wait("ack")
	_check(server.get_status().neutral and not server.get_status().active, "fresh centered frame does not automatically resume")
	_probe_send({"type": "resume", "token": probe_token})
	active = await _probe_wait("status", "Active")
	_check(not active.is_empty() and server.get_status().active, "fresh neutral plus explicit resume restores manual-paused connection")
	_probe_send({"type": "release", "token": probe_token})
	var until := Time.get_ticks_msec() + 1000
	while server.get_status().paired and Time.get_ticks_msec() < until:
		_probe_poll()
		await process_frame
	probe.close(-1)
	probe = null
	_check(not server.get_status().paired, "pause probe releases controller without leaving a paired session")

func _probe_send(message: Dictionary) -> void:
	probe.send_text(JSON.stringify(message))

func _probe_frame(axis: float, neutral: bool) -> Dictionary:
	probe_seq += 1
	return {"type": "input", "token": probe_token, "lease_nonce": probe_lease, "frame": {
		"schema": 2, "control_epoch": probe_epoch, "seq": probe_seq, "sample_ms": Time.get_ticks_msec(),
		"axes": {"left_x": 0.0, "left_y": 0.0, "right_x": axis, "right_y": 0.0},
		"held": [], "edges": [], "context": "flight", "neutral": neutral}}

func _probe_input(axis: float, neutral: bool) -> void:
	_probe_send(_probe_frame(axis, neutral))

func _probe_poll() -> void:
	probe.poll()
	while probe.get_available_packet_count() > 0:
		var message: Variant = JSON.parse_string(probe.get_packet().get_string_from_utf8())
		if not message is Dictionary:
			continue
		if message.get("type") == "ping" and not probe_token.is_empty():
			_probe_send({"type": "pong", "token": probe_token, "nonce": message.nonce})
		elif message.get("type") == "status":
			if probe_epoch != int(message.control_epoch):
				probe_seq = 0
			probe_epoch = int(message.control_epoch)
			probe_lease = str(message.lease_nonce)
		probe_messages.append(message)

func _probe_wait(kind: String, state: String = "") -> Dictionary:
	var until := Time.get_ticks_msec() + 1500
	while Time.get_ticks_msec() < until:
		_probe_poll()
		for index: int in range(probe_messages.size()):
			var message: Dictionary = probe_messages[index]
			if message.get("type") == kind and (state.is_empty() or message.get("state") == state):
				probe_messages.remove_at(index)
				return message
		await process_frame
	return {}

func _process(_delta: float) -> bool:
	if mode == "serve":
		var status: Dictionary = server.get_status()
		if status.paired and not auto_approved:
			auto_approved = server.approve_control()
		if not status.paired:
			auto_approved = false
		if Time.get_ticks_msec() >= deadline:
			print("PHONE_STATS " + JSON.stringify({"frames": frames, "suspensions": suspensions, "rejected": status.rejected_messages}))
			_finish()
	return false

func _finish() -> void:
	server.stop_server()
	print("PHONE_RESULT " + JSON.stringify({"passed": failures.is_empty(), "checks": checks.size(), "failures": failures}))
	server.queue_free()
	quit(0 if failures.is_empty() else 1)
