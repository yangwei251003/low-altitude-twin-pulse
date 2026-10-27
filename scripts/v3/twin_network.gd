class_name TwinNetwork
extends Node
## ENet transport only; game authority stays in the host session.

signal input_received(peer_id: int, command: Dictionary)
signal action_received(peer_id: int, verb: String, payload: Dictionary)
signal guest_joined(peer_id: int, profile_id: String, airframe_id: String)
signal guest_left(peer_id: int)
signal snapshot_received(packet: Dictionary)
signal event_received(event: Dictionary)
signal status_changed(message: String)

const DEFAULT_PORT = 26742
# Synchronous region/GLB adoption can exceed ENet's default 5s minimum.
# Keep its original 30s maximum; silent loss may now take that long to report.
const CONNECTED_TIMEOUT_MS = 30000
const SnapshotCodec = preload("res://scripts/v3/network/twin_snapshot_codec.gd")
const FacilityContract = preload("res://scripts/v3/network/twin_facility_contract.gd")
const BuildContract = preload("res://scripts/v3/network/twin_build_contract.gd")
const PROTOCOL = 34 # Guest head-relative input must be interpreted by matching hosts.
var mode = "solo"
var profile_id = ""
var airframe_id = "tr01"
var guests: Dictionary = {}
var guest_builds: Dictionary = {}
var departure_build: Dictionary = {}
var last_input: Dictionary = {}
var last_action: Dictionary = {}
var received_at: Dictionary = {}
var _rate: Dictionary = {}
var _sequence = 0
var session_id = ""
var _lan_trace_enabled: bool = "--lan-trace" in OS.get_cmdline_user_args()
var _lan_trace_seen: Dictionary = {}
var telemetry = {"max_snapshot_bytes":0, "reliable_fallbacks":0, "snapshots_sent":0, "snapshot_encode_rejections":0}

func _lan_trace(label: String, data: Dictionary = {}) -> void:
	if not _lan_trace_enabled or _lan_trace_seen.has(label) or _lan_trace_seen.size() >= 96: return
	_lan_trace_seen[label] = true
	print("V3_LAN_TRACE " + JSON.stringify({"label":label,"mode":mode,"t_usec":Time.get_ticks_usec(),"data":data}))

func _ready() -> void:
	multiplayer.connected_to_server.connect(_connected)
	multiplayer.connection_failed.connect(_connection_failed)
	multiplayer.server_disconnected.connect(_server_left)
	multiplayer.peer_disconnected.connect(_peer_left)

func is_authority() -> bool:
	return mode in ["solo", "host"]

func local_id() -> int:
	return multiplayer.get_unique_id()

func start_solo() -> void:
	_lan_trace("close_origin_start_solo")
	close()
	_lan_trace_seen.clear()
	_lan_trace("start_solo")
	mode = "solo"
	session_id = Crypto.new().generate_random_bytes(12).hex_encode()

func host(port = DEFAULT_PORT) -> Error:
	_lan_trace("close_origin_start_host")
	close()
	_lan_trace_seen.clear()
	_lan_trace("start_host")
	var peer = ENetMultiplayerPeer.new()
	var error = peer.create_server(port, 1, 3)
	if error != OK:
		status_changed.emit("无法创建房间：端口可能已被占用（%s）" % error_string(error))
		return error
	multiplayer.multiplayer_peer = peer
	mode = "host"
	session_id = Crypto.new().generate_random_bytes(12).hex_encode()
	status_changed.emit("房间已开放 · 局域网端口 %d" % port)
	return OK

func join(address: String, identity: String, port = DEFAULT_PORT, frame = "tr01", build: Dictionary = {}) -> Error:
	_lan_trace("close_origin_start_join")
	close()
	_lan_trace_seen.clear()
	_lan_trace("start_join")
	if address.strip_edges().is_empty(): return ERR_INVALID_PARAMETER
	var hardware: Dictionary = BuildContract.view(CatalogV2.default_build(frame) if build.is_empty() else build)
	if not BuildContract.validate(hardware).get("ok",false) or hardware.airframe_id != frame: return ERR_INVALID_PARAMETER
	departure_build = hardware.duplicate(true)
	profile_id = identity
	airframe_id = frame
	var peer = ENetMultiplayerPeer.new()
	var error = peer.create_client(address.strip_edges(), port, 3)
	if error != OK: return error
	mode = "guest"
	multiplayer.multiplayer_peer = peer
	status_changed.emit("正在连接 %s…" % address)
	return OK

func close() -> void:
	_lan_trace("close", {"registered_guests":guests.size()})
	if multiplayer.multiplayer_peer:
		multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	mode = "solo"
	guests.clear()
	guest_builds.clear()
	departure_build.clear()
	last_input.clear()
	last_action.clear()
	received_at.clear()
	_rate.clear()
	_sequence = 0
	session_id = ""

func _configure_connected_timeout(peer_id: int) -> void:
	var transport = multiplayer.multiplayer_peer
	if not transport is ENetMultiplayerPeer: return
	var link: ENetPacketPeer = transport.get_peer(peer_id)
	if not is_instance_valid(link) or not link.is_active(): return
	link.set_timeout(32, CONNECTED_TIMEOUT_MS, CONNECTED_TIMEOUT_MS)
	_lan_trace("connected_timeout_applied", {"minimum_ms":CONNECTED_TIMEOUT_MS,"maximum_ms":CONNECTED_TIMEOUT_MS,"limit":32})

func _connected() -> void:
	_configure_connected_timeout(1)
	_lan_trace("connected_register_send", {"protocol":PROTOCOL})
	_register.rpc_id(1, PROTOCOL, profile_id, airframe_id, FacilityContract.VERSION, FacilityContract.fingerprint(), departure_build, BuildContract.fingerprint())
	status_changed.emit("已连接，正在同步房主世界…")

func _server_left() -> void:
	_lan_trace("close_origin_server_left")
	close()
	mode = "disconnected"
	status_changed.emit("房主已离开；个人已确认成果保留")
	event_received.emit({"kind":"host_left"})

func _connection_failed() -> void:
	_lan_trace("close_origin_connection_failed")
	close()
	mode = "disconnected"
	status_changed.emit("连接失败：检查同一局域网、地址和房主是否已开房")
	event_received.emit({"kind":"host_left"})

func _peer_left(id: int) -> void:
	_lan_trace("peer_left", {"registered":guests.has(id),"registered_guests":guests.size()})
	if guests.has(id):
		guests.erase(id)
		guest_builds.erase(id)
		last_input.erase(id)
		last_action.erase(id)
		received_at.erase(id)
		guest_left.emit(id)

@rpc("any_peer", "call_remote", "reliable", 0)
func _register(protocol: int, identity: String, frame = "tr01", facility_version: int = 0, facility_digest: String = "", hardware: Dictionary = {}, catalog_digest: String = "") -> void:
	if mode != "host": return
	var sender = multiplayer.get_remote_sender_id()
	if guests.has(sender): return
	if protocol != PROTOCOL or not FacilityContract.compatible(facility_version, facility_digest) or identity.is_empty() or identity.length() > 96 or guests.size() >= 1 or frame not in ["tr01", "hx02", "ag03", "nx04", "sh05", "at06"]:
		_lan_trace("register_reject_header")
		multiplayer.multiplayer_peer.disconnect_peer(sender)
		return
	var accepted: Dictionary = BuildContract.validate(hardware)
	if catalog_digest != BuildContract.fingerprint() or not accepted.get("ok",false) or hardware.airframe_id != frame:
		_lan_trace("register_reject_build_catalog")
		multiplayer.multiplayer_peer.disconnect_peer(sender)
		return
	# A visitor owns its local profile. Host recomputes compatibility and physical
	# stats from this identical Catalog; this does not attest remote disk unlocks.
	_configure_connected_timeout(sender)
	guest_builds[sender] = accepted.build.duplicate(true)
	guests[sender] = identity
	received_at[sender] = Time.get_ticks_msec()
	_lan_trace("register_accepted", {"registered_guests":guests.size(),"protocol":protocol})
	guest_joined.emit(sender, identity, frame)

func send_input(command: Dictionary) -> void:
	_sequence += 1
	if is_authority():
		input_received.emit(1, command)
	elif mode == "guest" and multiplayer.multiplayer_peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED:
		_receive_input.rpc_id(1, _sequence, command)

@rpc("any_peer", "call_remote", "unreliable_ordered", 1)
func _receive_input(sequence: int, command: Dictionary) -> void:
	if mode != "host": return
	var sender = multiplayer.get_remote_sender_id()
	if not guests.has(sender) or sequence <= int(last_input.get(sender, -1)): return
	var accepted := validated_input(command)
	if accepted.is_empty(): return
	last_input[sender] = sequence
	received_at[sender] = Time.get_ticks_msec()
	_lan_trace("guest_input_accepted")
	input_received.emit(sender, accepted)

static func validated_input(command: Dictionary) -> Dictionary:
	if command.size() > 18: return {}
	var planar = command.get("planar", Vector3.ZERO)
	if not planar is Vector3 or not planar.is_finite(): return {}
	var flight_mode: Variant = command.get("mode", "assisted")
	if not flight_mode is String or flight_mode not in ["assisted", "advanced", "manual_throttle"]: return {}
	var body_relative: Variant=command.get("body_relative",false)
	if not body_relative is bool: return {}
	var result := {"mode":flight_mode, "body_relative":body_relative, "planar":Vector3(planar.x, 0, planar.z).limit_length(1)}
	for axis: String in ["vertical", "yaw", "pitch", "roll", "throttle"]:
		var value: Variant = command.get(axis, 0.0)
		if not (value is float or value is int) or not is_finite(float(value)): return {}
		result[axis] = clampf(float(value), 0.0 if axis == "throttle" else -1.0, 1.0)
	for flag: String in ["active", "brake", "fire"]:
		var value: Variant = command.get(flag, flag == "active")
		if not value is bool: return {}
		result[flag] = value
	return result

func send_action(verb: String, payload: Dictionary = {}) -> void:
	_sequence += 1
	if is_authority():
		action_received.emit(1, verb, payload)
	elif mode == "guest" and multiplayer.multiplayer_peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED:
		_receive_action.rpc_id(1, _sequence, verb, payload)

@rpc("any_peer", "call_remote", "reliable", 0)
func _receive_action(sequence: int, verb: String, payload: Dictionary) -> void:
	if mode != "host": return
	var sender = multiplayer.get_remote_sender_id()
	if not guests.has(sender) or sequence <= int(last_action.get(sender, -1)): return
	if verb not in ["ability", "lock", "interact", "explore", "boss_start", "retry", "revive", "propose", "confirm", "cancel", "receipt_ack", "receipt_ack_batch", "campaign_operate", "campaign_choice_open", "campaign_choice_read", "thermal_cargo_operate"] or payload.size() > 12: return
	if var_to_bytes(payload).size() > 8192: return
	if verb == "receipt_ack_batch":
		# Bounded ACK batches do not consume the pilot's ordinary action budget.
		if not payload.get("receipt_ids") is Array or payload.receipt_ids.size() > 8: return
		last_action[sender] = sequence
		action_received.emit(sender, verb, payload)
		return
	var second = Time.get_ticks_msec() / 1000
	var rate: Dictionary = _rate.get(sender, {"second":second, "count":0})
	if rate.second != second: rate = {"second":second, "count":0}
	rate.count += 1
	_rate[sender] = rate
	if int(rate.count) > 24: return
	last_action[sender] = sequence
	action_received.emit(sender, verb, payload)

func publish(packet: Dictionary) -> void:
	if mode != "host" or guests.is_empty(): return
	var encoded: Dictionary = SnapshotCodec.encode(packet)
	if encoded.is_empty():
		_lan_trace("snapshot_publish_reject_codec")
		telemetry.snapshot_encode_rejections += 1
		if int(telemetry.snapshot_encode_rejections) == 1:
			push_warning("Snapshot schema rejected: check protocol fields before publishing new authority state.")
		return
	var raw = var_to_bytes(encoded)
	var packed = raw.compress(FileAccess.COMPRESSION_ZSTD)
	telemetry.max_snapshot_bytes = maxi(int(telemetry.max_snapshot_bytes), packed.size())
	telemetry.snapshots_sent += 1
	_lan_trace("snapshot_publish", {"raw_bytes":raw.size(),"packed_bytes":packed.size(),"reliable":packed.size()>1150})
	# Keep motion datagrams under the practical ENet MTU. Large initial/full states
	# use reliable fragmentation instead of losing an entire unreliable snapshot.
	if packed.size() <= 1150: _receive_snapshot.rpc(packed, raw.size())
	else:
		telemetry.reliable_fallbacks += 1
		_receive_full_snapshot.rpc(packed, raw.size())

@rpc("authority", "call_remote", "unreliable_ordered", 2)
func _receive_snapshot(packed: PackedByteArray, original_size: int) -> void:
	_unpack_snapshot(packed, original_size)

@rpc("authority", "call_remote", "reliable", 2)
func _receive_full_snapshot(packed: PackedByteArray, original_size: int) -> void:
	_unpack_snapshot(packed, original_size)

func _unpack_snapshot(packed: PackedByteArray, original_size: int) -> void:
	_lan_trace("snapshot_receive_header", {"raw_bytes":original_size,"packed_bytes":packed.size()})
	if mode != "guest" or original_size < 1 or original_size > 131072 or packed.size() > 32768: _lan_trace("snapshot_reject_header"); return
	var raw = packed.decompress(original_size, FileAccess.COMPRESSION_ZSTD)
	if raw.size() != original_size: _lan_trace("snapshot_reject_decompress"); return
	var decoded = bytes_to_var(raw)
	if decoded is Dictionary:
		var packet = SnapshotCodec.decode(decoded)
		if not packet.is_empty():
			_lan_trace("snapshot_decode_valid")
			snapshot_received.emit(packet)
		else: _lan_trace("snapshot_reject_codec")
	else: _lan_trace("snapshot_reject_variant", {"variant_type":typeof(decoded)})

func send_event(peer_id: int, event: Dictionary) -> void:
	if peer_id == local_id(): event_received.emit(event)
	elif mode == "host" and guests.has(peer_id): _receive_event.rpc_id(peer_id, event)

@rpc("authority", "call_remote", "reliable", 0)
func _receive_event(event: Dictionary) -> void:
	if mode == "guest": event_received.emit(event)

func stale_peers() -> Array:
	var ids: Array = []
	for id in received_at:
		if Time.get_ticks_msec() - int(received_at[id]) > 400: ids.append(id)
	return ids
