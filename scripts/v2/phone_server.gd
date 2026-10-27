class_name PhoneServerV2
extends Node

signal input_frame(frame: Dictionary)
signal suspended(reason: String)
signal status_changed
signal resume_requested

const QrEncoder := preload("../../phone/vendor/qr_code/qr_code.gd")
const PROTOCOL := "las-v2"
const TIMEOUT_MS := 250
const HEADER_LIMIT := 8192
const BUFFER_LIMIT := 65536
const RELAY_LIMIT := 16384
const MESSAGE_LIMIT := 4096
const FILES := {"/": "index.html", "/index.html": "index.html", "/app.js": "app.js", "/style.css": "style.css"}
const MIME := {"html": "text/html; charset=utf-8", "js": "text/javascript; charset=utf-8", "css": "text/css; charset=utf-8"}
const AXES := ["left_x", "left_y", "right_x", "right_y"]
const HELD := ["fire", "brake", "interact"]
const EDGES := ["pause", "utility", "target", "tool", "map", "zoom_in", "zoom_out", "recenter"]

var asset_root := "res://phone"
var _http := TCPServer.new()
var _ws_listener := TCPServer.new()
var _relay_listener := TCPServer.new()
var _connections: Array[Dictionary] = []
var _controller: Dictionary = {}
var _hosts: Array[String] = []
var _state := "Stopped"
var _reason := ""
var _http_port := 0
var _ws_port := 0
var _relay_port := 0
var _address := ""
var _session := ""
var _pair_code := ""
var _pair_expires := 0
var _pair_failures := 0
var _cooldown_until := 0
var _token := ""
var _epoch := 0
var _last_seq := -1
var _last_edge := -1
var _last_input := 0
var _last_lease := 0
var _last_ping := 0
var _leases: Dictionary = {}
var _ping_nonce := ""
var _ping_time := 0
var _rtt_ms := -1.0
var _neutral := false
var _approved := false
var _telemetry: Dictionary = {}
var _qr_cache: Dictionary = {}
var _pending: Dictionary = {}
var _pending_edges: Array = []
var _rejected := 0

func _init() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS

func start_server(bind_address: String = "0.0.0.0") -> int:
	if _state != "Stopped":
		return OK
	var total := 0
	for filename in ["index.html", "app.js", "style.css"]:
		var file := FileAccess.open(asset_root.path_join(filename), FileAccess.READ)
		if file == null:
			_reason = "PHONE_ASSET_MISSING"
			status_changed.emit()
			return ERR_FILE_NOT_FOUND
		total += file.get_length()
	if total > 2 * 1024 * 1024:
		return ERR_OUT_OF_MEMORY
	_hosts.assign(["127.0.0.1"])
	for ip in IP.get_local_addresses():
		if _private_ipv4(ip) and not _hosts.has(ip):
			_hosts.append(ip)
	if bind_address != "0.0.0.0":
		if not _hosts.has(bind_address):
			return ERR_INVALID_PARAMETER
		_hosts.assign([bind_address])
	for port in range(8765, 8775, 2):
		if _http.listen(port, bind_address) != OK:
			continue
		if _ws_listener.listen(port + 1, bind_address) == OK:
			_http_port = port
			_ws_port = port + 1
			break
		_http.stop()
	if _http_port == 0:
		_reason = "PORTS_BUSY"
		status_changed.emit()
		return ERR_CANT_CREATE
	var err := _relay_listener.listen(0, "127.0.0.1")
	if err != OK:
		stop_server()
		return err
	_relay_port = _relay_listener.get_local_port()
	var chosen := _hosts[0]
	for ip in _hosts:
		if ip != "127.0.0.1":
			chosen = ip
			break
	_address = "http://%s:%d/" % [chosen, _http_port]
	_session = _random(12)
	_rotate_code()
	_set_state("Listening", "")
	return OK

func stop_server() -> void:
	if not _controller.is_empty():
		_suspend("SERVER_STOPPED")
	for connection in _connections:
		_close_connection(connection)
	_connections.clear()
	_controller = {}
	_http.stop()
	_ws_listener.stop()
	_relay_listener.stop()
	_http_port = 0
	_ws_port = 0
	_token = ""
	_pair_code = ""
	_approved = false
	_neutral = false
	_pending = {}
	_pending_edges.clear()
	_qr_cache.clear()
	_set_state("Stopped", "")

func approve_control() -> bool:
	if not _connected() or _token.is_empty():
		return false
	_approved = true
	_new_epoch()
	_set_state("TakingControl", "CENTER_STICKS")
	_issue_lease(Time.get_ticks_msec())
	return true

func resume_control() -> bool:
	if not _approved or not _connected() or not _neutral or Time.get_ticks_msec() - _last_input > TIMEOUT_MS:
		return false
	_pending = {}
	_pending_edges.clear()
	_set_state("Active", "")
	_send_status()
	return true

func suspend_control(reason: String = "manual") -> void:
	if _state in ["Active", "TakingControl"]:
		_suspend(reason)

func get_status() -> Dictionary:
	var addresses: Array[String] = []
	for ip in _hosts:
		addresses.append("http://%s:%d/" % [ip, _http_port])
	return {"state": _state, "address": _address, "addresses": addresses,
		"http_port": _http_port, "ws_port": _ws_port, "pair_code": _pair_code,
		"pair_expires_in": maxi(0, (_pair_expires - Time.get_ticks_msec()) / 1000),
		"cooldown_seconds": maxi(0, (_cooldown_until - Time.get_ticks_msec()) / 1000),
		"paired": not _token.is_empty(), "active": _state == "Active", "neutral": _neutral,
		"rtt_ms": _rtt_ms, "reason": _reason, "control_epoch": _epoch, "rejected_messages": _rejected}

func set_telemetry(value: Dictionary) -> void:
	_telemetry.clear()
	for key in ["altitude_agl_m", "speed_mps", "health", "heat", "cargo_kg", "tool_state", "mode", "auto_fire", "throttle", "resume_throttle", "tutorial_step", "tutorial_text"]:
		if value.has(key) and (value[key] is bool or value[key] is String or value[key] is float or value[key] is int):
			_telemetry[key] = value[key]

func refresh_control_mode(mode: String, throttle: float) -> void:
	_telemetry["mode"]=mode
	_telemetry["resume_throttle"]=clampf(throttle,0.0,1.0)
	if _state in ["Active","TakingControl"]:
		_suspend("mode_changed")
	elif _state not in ["Stopped","Disconnected"]:
		_new_epoch()
		_send_status()

func get_pair_qr_image(address: String = "") -> Image:
	var url := _address if address.is_empty() else address
	if _state == "Stopped" or not url in get_status().addresses:
		return null
	if _qr_cache.has(url):
		return _qr_cache[url]
	var encoder := QrEncoder.new(QrEncoder.ErrorCorrection.MEDIUM)
	encoder.put_byte(url.to_utf8_buffer())
	var result := QrEncoder.generate_image(encoder.encode(), 6)
	_qr_cache[url] = result
	return result

func _exit_tree() -> void:
	stop_server()

func _process(_delta: float) -> void:
	if _state == "Stopped":
		return
	var now := Time.get_ticks_msec()
	if _token.is_empty() and now >= _pair_expires:
		_rotate_code()
	_accept_external(_http, false, now)
	_accept_external(_ws_listener, true, now)
	_accept_relays()
	for connection in _connections.duplicate():
		_poll_connection(connection, now)
	if not _controller.is_empty():
		if now - _last_lease >= 100:
			_issue_lease(now)
		if now - _last_ping >= 500:
			_last_ping = now
			_ping_time = now
			_ping_nonce = _random(8)
			_send(_controller, {"type": "ping", "nonce": _ping_nonce})
		if _state == "Active" and now - _last_input > TIMEOUT_MS:
			_suspend("INPUT_STALE")
		elif _neutral and now - _last_input > TIMEOUT_MS:
			_neutral = false
			status_changed.emit()

func _physics_process(_delta: float) -> void:
	if _state == "Active" and not _pending.is_empty():
		_pending["edges"] = _pending_edges.duplicate(true)
		input_frame.emit(_pending)
		_pending = {}
		_pending_edges.clear()

func _accept_external(listener: TCPServer, websocket: bool, now: int) -> void:
	var accepted := 0
	while listener.is_connection_available() and accepted < 8:
		accepted += 1
		var tcp := listener.take_connection()
		if _connections.size() >= 12 or not _private_ipv4(tcp.get_connected_host()):
			tcp.disconnect_from_host()
			continue
		tcp.set_no_delay(true)
		_connections.append({"tcp": tcp, "websocket": websocket, "header": PackedByteArray(),
			"created": now, "bridge": null, "peer": null, "validated": false,
			"response": PackedByteArray(), "offset": 0, "up": PackedByteArray(), "down": PackedByteArray(),
			"hello": false, "violations": 0, "rate_start": now, "rate_count": 0, "opened": false})

func _accept_relays() -> void:
	while _relay_listener.is_connection_available():
		var stream := _relay_listener.take_connection()
		var found := false
		for connection in _connections:
			var bridge: StreamPeerTCP = connection.bridge
			if bridge != null and bridge.get_local_port() == stream.get_connected_port() and connection.peer == null:
				var peer := WebSocketPeer.new()
				peer.inbound_buffer_size = 8192
				peer.outbound_buffer_size = 8192
				peer.max_queued_packets = 32
				peer.supported_protocols = PackedStringArray([PROTOCOL])
				if peer.accept_stream(stream) == OK:
					connection.peer = peer
					found = true
				break
		if not found:
			stream.disconnect_from_host()

func _poll_connection(connection: Dictionary, now: int) -> void:
	var tcp: StreamPeerTCP = connection.tcp
	tcp.poll()
	if tcp.get_status() != StreamPeerTCP.STATUS_CONNECTED:
		_drop(connection, "DISCONNECTED")
		return
	if not connection.validated:
		if now - int(connection.created) > 3000:
			_drop(connection, "HEADER_TIMEOUT")
			return
		var amount := tcp.get_available_bytes()
		if amount > HEADER_LIMIT or connection.header.size() + amount > HEADER_LIMIT:
			_drop(connection, "HEADER_TOO_LARGE")
			return
		if amount == 0:
			return
		var read := tcp.get_partial_data(amount)
		if read[0] != OK:
			_drop(connection, "READ_FAILED")
			return
		connection.header.append_array(read[1])
		var raw: String = connection.header.get_string_from_ascii()
		if not raw.contains("\r\n\r\n"):
			return
		var request := _parse_header(raw)
		if request.is_empty() or not _valid_host(str(request.headers.get("host", "")), _ws_port if connection.websocket else _http_port):
			_drop(connection, "BAD_HOST_OR_HEADER")
			return
		connection.validated = true
		if connection.websocket:
			if not _valid_upgrade(request):
				_drop(connection, "BAD_ORIGIN_OR_PROTOCOL")
				return
			# WebSocketPeer does not expose received Origin. A bounded loopback relay
			# validates the original HTTP request before the engine parses RFC6455.
			connection.bridge = StreamPeerTCP.new()
			if connection.bridge.connect_to_host("127.0.0.1", _relay_port) != OK:
				_drop(connection, "RELAY_FAILED")
				return
			connection.bridge.set_no_delay(true)
			connection.up = connection.header
		else:
			_prepare_http(connection, request)
	if not connection.websocket:
		if now - int(connection.created) > 3000:
			_drop(connection, "HTTP_TIMEOUT")
			return
		var written := tcp.put_partial_data(connection.response.slice(connection.offset))
		if written[0] != OK:
			_drop(connection, "HTTP_WRITE_FAILED")
			return
		connection.offset += int(written[1])
		if connection.offset >= connection.response.size():
			_drop(connection, "HTTP_DONE")
		return
	var bridge: StreamPeerTCP = connection.bridge
	bridge.poll()
	if bridge.get_status() == StreamPeerTCP.STATUS_CONNECTING:
		return
	if bridge.get_status() != StreamPeerTCP.STATUS_CONNECTED:
		_drop(connection, "RELAY_DISCONNECTED")
		return
	if not _pump(tcp, bridge, connection, "up") or not _pump(bridge, tcp, connection, "down"):
		_drop(connection, "BUFFER_LIMIT")
		return
	var peer: WebSocketPeer = connection.peer
	if peer == null:
		return
	peer.poll()
	if peer.get_ready_state() == WebSocketPeer.STATE_CLOSED:
		_drop(connection, "DISCONNECTED")
		return
	if peer.get_ready_state() != WebSocketPeer.STATE_OPEN:
		if now - int(connection.created) > 3000:
			_drop(connection, "HANDSHAKE_TIMEOUT")
		return
	if not connection.opened:
		connection.opened = true
		_send(connection, {"type": "hello", "protocol": 2, "session_id": _session})
	var count := 0
	while peer.get_available_packet_count() > 0 and count < 32:
		count += 1
		var packet := peer.get_packet()
		if packet.size() > MESSAGE_LIMIT or not peer.was_string_packet():
			_violation(connection, "MESSAGE_LIMIT", true)
			return
		if now - int(connection.rate_start) >= 1000:
			connection.rate_start = now
			connection.rate_count = 0
		connection.rate_count += 1
		if connection.rate_count > 120:
			_violation(connection, "RATE_LIMIT", true)
			return
		var message: Variant = JSON.parse_string(packet.get_string_from_utf8())
		if not message is Dictionary:
			_violation(connection, "BAD_JSON")
			continue
		_handle_message(connection, message, now)
		if not _connections.has(connection):
			return
	if not connection.hello and now - int(connection.created) > 5000:
		_drop(connection, "HELLO_TIMEOUT")
	elif _controller != connection and now - int(connection.created) > 150000:
		_drop(connection, "PAIR_TIMEOUT")

func _pump(source: StreamPeerTCP, destination: StreamPeerTCP, connection: Dictionary, key: String) -> bool:
	var available := source.get_available_bytes()
	if available + connection[key].size() > RELAY_LIMIT:
		return false
	if available > 0:
		var result := source.get_partial_data(available)
		if result[0] != OK:
			return false
		connection[key].append_array(result[1])
	if not connection[key].is_empty():
		var result := destination.put_partial_data(connection[key])
		if result[0] != OK:
			return false
		connection[key] = connection[key].slice(int(result[1]))
	return true

func _parse_header(raw: String) -> Dictionary:
	if raw.length() > HEADER_LIMIT or raw.count("\r\n\r\n") != 1 or not raw.ends_with("\r\n\r\n"):
		return {}
	var lines := raw.trim_suffix("\r\n\r\n").split("\r\n")
	var first := lines[0].split(" ", false)
	if first.size() != 3 or first[2] != "HTTP/1.1" or not first[0] in ["GET", "HEAD"] or first[1].contains("..") or first[1].contains("%"):
		return {}
	var headers: Dictionary = {}
	for line in lines.slice(1):
		var split := line.find(":")
		if split <= 0 or line.begins_with(" ") or line.begins_with("\t"):
			return {}
		var key := line.substr(0, split).to_lower()
		if headers.has(key):
			return {}
		headers[key] = line.substr(split + 1).strip_edges()
	if headers.has("transfer-encoding") or (headers.has("content-length") and headers["content-length"] != "0"):
		return {}
	return {"method": first[0], "path": first[1], "headers": headers}

func _valid_host(host: String, port: int) -> bool:
	for ip in _hosts:
		if host == "%s:%d" % [ip, port]:
			return true
	return false

func _valid_upgrade(request: Dictionary) -> bool:
	var headers: Dictionary = request.headers
	var host := str(headers.get("host", ""))
	var origin := "http://%s:%d" % [host.get_slice(":", 0), _http_port]
	var connection_tokens: Array[String] = []
	for part in str(headers.get("connection", "")).to_lower().split(","):
		connection_tokens.append(part.strip_edges())
	return request.method == "GET" and request.path == "/control" and headers.get("origin", "") == origin \
		and str(headers.get("upgrade", "")).to_lower() == "websocket" \
		and "upgrade" in connection_tokens \
		and headers.get("sec-websocket-version", "") == "13" \
		and headers.get("sec-websocket-protocol", "") == PROTOCOL \
		and str(headers.get("sec-websocket-key", "")).length() == 24

func _prepare_http(connection: Dictionary, request: Dictionary) -> void:
	var body := PackedByteArray()
	var code := "404 Not Found"
	var mime := "text/plain; charset=utf-8"
	if FILES.has(request.path):
		var filename: String = FILES[request.path]
		var file := FileAccess.open(asset_root.path_join(filename), FileAccess.READ)
		if file != null:
			var content := file.get_as_text()
			if filename == "index.html":
				content = content.replace("__WS_PORT__", str(_ws_port)).replace("__SESSION_ID__", _session)
			body = content.to_utf8_buffer()
			mime = MIME[filename.get_extension()]
			code = "200 OK"
	var header := "HTTP/1.1 %s\r\nContent-Type: %s\r\nContent-Length: %d\r\nConnection: close\r\nCache-Control: no-store\r\nX-Content-Type-Options: nosniff\r\nReferrer-Policy: no-referrer\r\nContent-Security-Policy: default-src 'self'; script-src 'self'; style-src 'self'; connect-src 'self' ws:; frame-ancestors 'none'; base-uri 'none'; form-action 'none'\r\n\r\n" % [code, mime, body.size()]
	connection.response = header.to_utf8_buffer()
	if request.method != "HEAD":
		connection.response.append_array(body)

func _handle_message(connection: Dictionary, message: Dictionary, now: int) -> void:
	var kind: Variant = message.get("type", null)
	if kind == "hello":
		if message.get("protocol") != 2 or message.get("session_id") != _session or not message.get("page_nonce") is String or str(message.page_nonce).length() > 64:
			_violation(connection, "PROTOCOL_MISMATCH", true)
			return
		connection.hello = true
		return
	if not connection.hello:
		_violation(connection, "HELLO_REQUIRED", true)
		return
	if kind == "pair":
		_pair(connection, message, now)
		return
	if connection != _controller or _token.is_empty():
		_violation(connection, "PAIR_REQUIRED")
		return
	if message.get("token", "") != _token:
		_violation(connection, "BAD_TOKEN", true)
		return
	match kind:
		"input":
			_receive_input(connection, message, now)
		"pong":
			if message.get("nonce", "") == _ping_nonce and not _ping_nonce.is_empty():
				_rtt_ms = float(now - _ping_time)
				_ping_nonce = ""
		"suspend":
			_suspend("PHONE_INTERRUPTED")
		"resume":
			if not resume_control():
				_send(connection, {"type": "error", "code": "CENTER_STICKS_OR_COMPUTER_APPROVAL"})
			else: resume_requested.emit()
		"release":
			_drop(connection, "PHONE_RELEASED")
		_:
			_violation(connection, "UNKNOWN_MESSAGE")

func _pair(connection: Dictionary, message: Dictionary, now: int) -> void:
	if not _controller.is_empty():
		_send(connection, {"type": "error", "code": "CONTROL_BUSY"})
		return
	if now < _cooldown_until:
		_send(connection, {"type": "error", "code": "PAIR_COOLDOWN", "retry_ms": _cooldown_until - now})
		return
	if now > _pair_expires or message.get("code", "") != _pair_code or message.get("requested_role", "") != "controller":
		_pair_failures += 1
		if _pair_failures >= 5:
			_cooldown_until = now + 30000
			_rotate_code()
		_send(connection, {"type": "error", "code": "PAIR_DENIED"})
		return
	_controller = connection
	_token = _random(32)
	_approved = false
	_new_epoch()
	_set_state("ConnectedIdle", "COMPUTER_APPROVAL_REQUIRED")
	_send(connection, {"type": "paired", "protocol": 2, "token": _token,
		"control_epoch": _epoch, "input_hz": 30, "timeout_ms": TIMEOUT_MS})
	_issue_lease(now)

func _receive_input(connection: Dictionary, message: Dictionary, now: int) -> void:
	var raw: Variant = message.get("frame")
	if not raw is Dictionary:
		_violation(connection, "BAD_FRAME")
		return
	var frame: Dictionary = raw
	var error := _frame_error(frame)
	if not error.is_empty():
		_violation(connection, error)
		return
	if int(frame.control_epoch) != _epoch or int(frame.seq) <= _last_seq:
		_rejected += 1
		return
	var nonce: Variant = message.get("lease_nonce")
	if not nonce is String or not _leases.has(nonce) or now - int(_leases[nonce]) > TIMEOUT_MS:
		_rejected += 1
		return
	_last_seq = int(frame.seq)
	_last_input = now
	var axes: Dictionary = frame.axes.duplicate()
	var held: Array = frame.held.duplicate()
	if frame.neutral:
		for axis in AXES:
			axes[axis] = 0.0
		held.clear()
		_pending_edges.clear()
	var centered := held.is_empty()
	for axis in AXES:
		if axis == "left_y" and str(_telemetry.get("mode","assisted")) == "manual_throttle":
			centered = centered and not bool(frame.neutral) and absf((float(axes[axis])+1.0)*0.5-float(_telemetry.get("resume_throttle",0.0)))<=0.06
		else:
			centered = centered and absf(float(axes[axis])) <= 0.001
	if _neutral != centered:
		_neutral = centered
		status_changed.emit()
	var fresh_edges: Array = []
	for edge in frame.edges:
		if int(edge.id) > _last_edge:
			_last_edge = int(edge.id)
			if not frame.neutral:
				fresh_edges.append(edge.duplicate())
	if _state == "Active":
		if frame.context != "flight":
			_suspend("CONTEXT_CHANGED")
			return
		for edge in fresh_edges:
			if edge.action == "pause":
				_suspend("PHONE_PAUSED")
				return
			if _pending_edges.size() < 8:
				_pending_edges.append(edge)
		_pending = {"schema": 2, "source": "phone", "device_id": "phone_" + _session,
			"control_epoch": _epoch, "seq": _last_seq, "sample_ms": frame.sample_ms,
			"axes": axes, "held": held, "edges": [], "context": "flight", "neutral": frame.neutral}
	_send(connection, {"type": "ack", "seq": _last_seq, "edge_ack": _last_edge,
		"server_receive_ms": now, "state": _state})

func _frame_error(frame: Dictionary) -> String:
	if frame.get("schema") != 2 or not _uint(frame.get("control_epoch")) or not _uint(frame.get("seq")) or not _uint(frame.get("sample_ms")):
		return "BAD_SCHEMA_OR_SEQUENCE"
	if not frame.get("axes") is Dictionary or not frame.get("held") is Array or not frame.get("edges") is Array or not frame.get("neutral") is bool:
		return "BAD_FRAME_TYPES"
	if frame.axes.size() != 4 or frame.held.size() > 16 or frame.edges.size() > 8 or not frame.get("context") in ["flight", "menu", "calibration"]:
		return "BAD_FRAME_SIZE"
	for axis in AXES:
		var value: Variant = frame.axes.get(axis)
		if not (value is float or value is int) or not is_finite(float(value)) or absf(float(value)) > 1.0:
			return "BAD_AXIS"
	for action in frame.held:
		if not action in HELD:
			return "BAD_HELD"
	for edge in frame.edges:
		if not edge is Dictionary or not _uint(edge.get("id")) or not edge.get("action") in EDGES or edge.get("kind") != "pressed":
			return "BAD_EDGE"
	return ""

func _uint(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and float(value) >= 0 and float(value) <= 9007199254740991.0 and floorf(float(value)) == float(value)

func _new_epoch() -> void:
	_epoch += 1
	_last_seq = -1
	_last_edge = -1
	_last_input = 0
	_neutral = false
	_pending = {}
	_pending_edges.clear()
	_leases.clear()
	_emit_zero()

func _suspend(reason: String) -> void:
	if _state in ["Stale", "Disconnected", "Stopped"]:
		return
	# Close the gate before zero-input callbacks can re-enter the host pause path.
	_state = "Stale"
	_reason = reason
	_new_epoch()
	status_changed.emit()
	_send_status()
	suspended.emit(reason)

func _emit_zero() -> void:
	input_frame.emit({"schema": 2, "source": "phone", "device_id": "phone_" + _session,
		"control_epoch": _epoch, "seq": 0, "sample_ms": Time.get_ticks_msec(),
		"axes": {"left_x": 0.0, "left_y": 0.0, "right_x": 0.0, "right_y": 0.0},
		"held": [], "edges": [], "context": "flight", "neutral": true})

func _issue_lease(now: int) -> void:
	_last_lease = now
	for nonce in _leases.keys():
		if now - int(_leases[nonce]) > TIMEOUT_MS:
			_leases.erase(nonce)
	var nonce := _random(12)
	_leases[nonce] = now
	_send(_controller, {"type": "status", "state": _state, "reason": _reason,
		"control_epoch": _epoch, "lease_nonce": nonce, "neutral": _neutral,
		"rtt_ms": _rtt_ms, "telemetry": _telemetry})

func _send_status() -> void:
	if not _controller.is_empty():
		_issue_lease(Time.get_ticks_msec())

func _send(connection: Dictionary, message: Dictionary) -> void:
	if connection.is_empty() or connection.peer == null:
		return
	var peer: WebSocketPeer = connection.peer
	if peer.get_ready_state() == WebSocketPeer.STATE_OPEN:
		if peer.get_current_outbound_buffered_amount() > 16384 or peer.send_text(JSON.stringify(message)) != OK:
			_drop(connection, "SEND_BACKLOG")

func _connected() -> bool:
	return not _controller.is_empty() and _controller.peer != null and _controller.peer.get_ready_state() == WebSocketPeer.STATE_OPEN

func _violation(connection: Dictionary, reason: String, severe: bool = false) -> void:
	_rejected += 1
	connection.violations += 1
	if connection == _controller and _state == "Active":
		_suspend(reason)
	if severe or connection.violations >= 5:
		_drop(connection, reason)
	else:
		_send(connection, {"type": "error", "code": reason})

func _drop(connection: Dictionary, reason: String) -> void:
	if connection == _controller:
		_suspend(reason)
		_controller = {}
		_token = ""
		_approved = false
		_neutral = false
		_rtt_ms = -1.0
		_rotate_code()
		_set_state("Disconnected", reason)
	_close_connection(connection)
	_connections.erase(connection)

func _close_connection(connection: Dictionary) -> void:
	if connection.peer != null:
		connection.peer.close(-1)
	if connection.bridge != null:
		connection.bridge.disconnect_from_host()
	connection.tcp.disconnect_from_host()

func _set_state(value: String, reason: String) -> void:
	_state = value
	_reason = reason
	status_changed.emit()

func _rotate_code() -> void:
	var bytes := Crypto.new().generate_random_bytes(4)
	_pair_code = "%06d" % (bytes.decode_u32(0) % 1000000)
	_pair_expires = Time.get_ticks_msec() + 120000
	_pair_failures = 0
	status_changed.emit()

func _random(bytes: int) -> String:
	return Crypto.new().generate_random_bytes(bytes).hex_encode()

func _private_ipv4(ip: String) -> bool:
	if ip == "127.0.0.1" or ip.begins_with("192.168.") or ip.begins_with("10.") or ip.begins_with("169.254."):
		return true
	var parts := ip.split(".")
	return parts.size() == 4 and parts[0] == "172" and parts[1].is_valid_int() and int(parts[1]) >= 16 and int(parts[1]) <= 31
