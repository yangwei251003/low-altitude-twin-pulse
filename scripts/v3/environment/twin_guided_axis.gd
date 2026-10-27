class_name TwinGuidedAxis
extends RefCounted
## Pure bounded axis integrator. Collision approval belongs to its host adapter.
## Same-tick impulses are summed BEFORE saturation; snapshots expose their
## effective velocity, never a delayed command queue. No wall clock or nodes.
const ALGORITHM := "guided_axis_v1"
const MAX_SERIAL := 9007199254740000
# Vector3 components/normalization/dot products use float32 in the shipped build.
# Reserve eight relative float32 epsilons for normalize -> multiply -> squared
# length, rather than an absolute tolerance that fails at the legal 9 N.s cap.
# At 9 N.s this is ~0.00007725 squared units, ~0.00000430 N.s in magnitude.
const FLOAT32_EPSILON := 1.1920928955078125e-7
const IMPULSE_SQUARED_REL_TOL := 8.0 * FLOAT32_EPSILON
const CONFIG_KEYS := ["travel_m", "mass_kg", "damping_per_second", "max_speed_mps", "max_impulse_ns"]
const SAVE_KEYS := ["algorithm", "config_sha256", "position_m", "velocity_mps", "last_serial"]
var _config: Dictionary = {}
var _digest := ""
var _position := 0.0
var _velocity := 0.0
var _last: Dictionary = {}
var _pending: Dictionary = {}

func configure(config: Dictionary) -> Dictionary:
	if not _config.is_empty(): return _result(false, "already_configured")
	if not _exact(config, CONFIG_KEYS): return _result(false, "config_keys")
	for key in CONFIG_KEYS:
		if not _number(config[key], 0.000001, 100.0): return _result(false, "config_range")
	_config = config.duplicate(true)
	for key in CONFIG_KEYS: _config[key] = float(_config[key])
	_digest = JSON.stringify(_config, "", true, true).sha256_text()
	return _result(true, "configured")

func set_active_peers(peers: Array) -> Dictionary:
	if _config.is_empty(): return _result(false, "not_configured")
	if peers.size() > 2: return _result(false, "peer_limit")
	var next: Dictionary = {}
	for peer in peers:
		if not peer is int or peer <= 0 or peer > 2147483647 or next.has(str(peer)): return _result(false, "peer_invalid")
		next[str(peer)] = int(_last.get(str(peer), -1))
	var removed: Array = []
	for peer in _pending:
		if not next.has(peer): removed.append({"peer_id":int(peer), "action_serial":int(_last[peer])})
	for request in removed: _pending.erase(str(request.peer_id))
	_last = next
	return {"ok":true, "code":"roster_synced", "cancelled":removed}

func can_accept(impulse: Vector3, peer: int, serial: int) -> Dictionary:
	if _config.is_empty(): return _result(false, "not_configured")
	var limit_squared := pow(float(_config.max_impulse_ns), 2)
	if not impulse.is_finite() or impulse.length_squared() > limit_squared * (1.0 + IMPULSE_SQUARED_REL_TOL): return _result(false, "impulse_range")
	if not _last.has(str(peer)): return _result(false, "peer_not_active")
	if serial < 0 or serial > MAX_SERIAL or serial <= int(_last[str(peer)]): return _result(false, "stale_action")
	if _pending.has(str(peer)): return _result(false, "peer_already_acted_this_tick")
	return _result(true, "impulse_accepted")

func apply_impulse(impulse: Vector3, peer: int, serial: int) -> Dictionary:
	var checked := can_accept(impulse, peer, serial)
	if not checked.ok: return checked
	_last[str(peer)] = serial
	_pending[str(peer)] = float(impulse.x)
	return {"ok":true, "code":"impulse_accepted", "velocity_mps":effective_velocity(), "peer_id":peer, "action_serial":serial}

func effective_velocity() -> float:
	if _config.is_empty(): return 0.0
	var total := 0.0
	var peers := _pending.keys()
	peers.sort()
	for peer in peers: total += float(_pending[peer])
	return clampf(_velocity + total / float(_config.mass_kg), -float(_config.max_speed_mps), float(_config.max_speed_mps))

func reset_peer(peer: int) -> Dictionary:
	# Host actor recreation only. A new actor has a new revision sequence;
	# ordinary repeated roster synchronization must never call this.
	if not _last.has(str(peer)): return _result(false, "peer_not_active")
	var cancelled: Array = []
	if _pending.has(str(peer)):
		cancelled.append({"peer_id":peer, "action_serial":int(_last[str(peer)])})
		_pending.erase(str(peer))
	_last[str(peer)] = -1
	return {"ok":true, "code":"actor_recreated", "cancelled":cancelled}

func preview(delta: float) -> Dictionary:
	if _config.is_empty(): return _result(false, "not_configured")
	if not _number(delta, 0.0, 0.25): return _result(false, "delta_range")
	if delta == 0.0: return {"ok":true, "code":"paused", "position_m":_position, "velocity_mps":effective_velocity()}
	var speed := effective_velocity()
	var decay := exp(-float(_config.damping_per_second) * delta)
	var destination := _position + speed * (1.0 - decay) / float(_config.damping_per_second)
	var limit := float(_config.travel_m)
	var next_speed := speed * decay
	if destination <= 0.0 or destination >= limit: next_speed = 0.0
	return {"ok":true, "code":"proposed", "position_m":clampf(destination, 0.0, limit), "velocity_mps":next_speed}

func advance(delta: float, blocked: bool = false) -> Dictionary:
	var next := preview(delta)
	if not next.ok or delta == 0.0: return next
	if not blocked: _position = float(next.position_m)
	_velocity = 0.0 if blocked else float(next.velocity_mps)
	_pending.clear()
	return {"ok":true, "code":"blocked" if blocked else "advanced", "position_m":_position, "velocity_mps":_velocity}

func stop() -> Dictionary:
	var cancelled: Array = []
	for peer in _pending: cancelled.append({"peer_id":int(peer), "action_serial":int(_last[peer])})
	_pending.clear()
	_velocity = 0.0
	return {"ok":true, "code":"stopped", "cancelled":cancelled}

func snapshot() -> Dictionary:
	if _config.is_empty(): return {}
	return {"algorithm":ALGORITHM, "config_sha256":_digest, "position_m":_position,
		"velocity_mps":effective_velocity(), "last_serial":_last.duplicate(true)}

func validate_snapshot(raw: Variant) -> Dictionary:
	if _config.is_empty(): return _result(false, "not_configured")
	if not raw is Dictionary or not _exact(raw, SAVE_KEYS): return _result(false, "snapshot_keys")
	if raw.algorithm != ALGORITHM or raw.config_sha256 != _digest: return _result(false, "snapshot_version")
	if not _number(raw.position_m, 0.0, float(_config.travel_m)) or not _number(raw.velocity_mps, -float(_config.max_speed_mps), float(_config.max_speed_mps)): return _result(false, "snapshot_motion")
	if not raw.last_serial is Dictionary or raw.last_serial.size() > 2: return _result(false, "snapshot_roster")
	for peer in raw.last_serial:
		if not peer is String or not peer.is_valid_int() or str(int(peer)) != peer or int(peer) <= 0 or int(peer) > 2147483647: return _result(false, "snapshot_peer")
		if not _number(raw.last_serial[peer], -1, MAX_SERIAL) or floor(float(raw.last_serial[peer])) != float(raw.last_serial[peer]): return _result(false, "snapshot_serial")
	return _result(true, "valid")

func restore(raw: Variant, clear_velocity: bool = true) -> Dictionary:
	var checked := validate_snapshot(raw)
	if not checked.ok: return checked
	_position = float(raw.position_m)
	_velocity = 0.0 if clear_velocity else float(raw.velocity_mps)
	_last = raw.last_serial.duplicate(true)
	for peer in _last: _last[peer] = int(_last[peer])
	_pending.clear()
	return _result(true, "restored")

func copy_for_trial():
	var result = get_script().new()
	result._config = _config.duplicate(true)
	result._digest = _digest
	result._position = _position
	result._velocity = _velocity
	result._last = _last.duplicate(true)
	result._pending = _pending.duplicate(true)
	return result

static func _exact(value: Dictionary, keys: Array) -> bool:
	if value.size() != keys.size(): return false
	for key in value:
		if not key is String or key not in keys: return false
	return true

static func _number(value: Variant, low: float, high: float) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and float(value) >= low and float(value) <= high

static func _result(ok: bool, code: String) -> Dictionary:
	return {"ok":ok, "code":code}
