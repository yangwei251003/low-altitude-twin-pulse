class_name TwinUnderdeckAction
extends RefCounted
## Host-only evidence adapter. Never saves, grants rewards, or moves a body/gate.
## step must run once per authority physics tick after accepted movement and rules.
const FlightBody = preload("res://scripts/v2/flight_body.gd")
const ENTER := "I1:underdeck:enter"
const RELEASE := "I1:underdeck:release"
const TRAVERSE := "I1:underdeck:traverse"
const FRONT := "I1:underdeck_grille"
const LATCH := "I1:underdeck_latch"
const MAX_DELTA := 0.25
const POSITION_EPS := 0.002
const SIGNAL_SECONDS := 1.0
var _layout: Dictionary = {}
var _portals: Dictionary = {}
var _air: Array[AABB] = []
var _samples: Dictionary = {}
var _body_refs: Dictionary = {}
var _crossings: Dictionary = {}
var _blinks: Dictionary = {}
var _pending: Dictionary = {}
var _objective := ""
var _signal_key := ""
var _signal_seconds := 0.0

func configure(layout: Dictionary) -> Dictionary:
	var checked := _check_layout(layout)
	if not checked.ok: return checked
	_layout = layout.duplicate(true)
	_portals = checked.portals
	_air = checked.air
	reset()
	return {"ok":true, "code":"configured"}

func reset() -> void:
	_samples.clear()
	_body_refs.clear()
	_crossings.clear()
	_blinks.clear()
	_pending.clear()
	_objective = ""
	_signal_key = ""
	_signal_seconds = 0.0

func reset_peer(peer: int) -> void:
	# Respawning one body must not erase any already verified world fact. Pending
	# facts survive until transaction acknowledgement or a full world/reset boundary.
	_samples.erase(peer)
	_body_refs.erase(peer)
	_crossings.erase(peer)
	_blinks.erase(peer)
	if _signal_key.ends_with(":" + str(peer)):
		_signal_key = ""
		_signal_seconds = 0.0

func acknowledge(objective_id: String) -> bool:
	# Caller may acknowledge only after the existing Story transaction succeeds.
	if not _pending.has(objective_id): return false
	_pending.erase(objective_id)
	if objective_id == RELEASE:
		_signal_key = ""
		_signal_seconds = 0.0
	return true

func note_blink(peer: int, from: Vector3, to: Vector3) -> bool:
	# This is NOT a client command. Call only at the accepted physical blink exit.
	if _layout.is_empty() or peer <= 0 or not from.is_finite() or not to.is_finite(): return false
	if from.distance_to(to) <= POSITION_EPS or from.distance_to(to) > 9.0 + POSITION_EPS: return false
	if not _blinks.has(peer) and _blinks.size() >= 2: return false
	var reference: WeakRef = _body_refs.get(peer)
	if reference == null: return false # No observed live body yet: fail closed.
	var body = reference.get_ref()
	if not is_instance_valid(body) or not body is FlightBody or not body.is_inside_tree(): return false
	if not body.enabled or not _finite(body.health) or float(body.health) <= 0.0: return false
	var executed := _sample(body)
	var previous: Dictionary = _samples.get(peer, {})
	if executed.is_empty() or previous.is_empty() or previous.instance != executed.instance or previous.shape != executed.shape: return false
	if executed.position.distance_to(to) > POSITION_EPS: return false
	# The production blink translates, never rotates. Reconstruct its start from
	# the ACTUAL shape/rotation at execution, not the older observer position.
	# `from` is trusted only because this hook runs after authority sweep+commit.
	var begin := _translated_sample(executed, from)
	var portal: Dictionary = _portals.east
	if from.x < float(portal.plane) - POSITION_EPS or from.x <= to.x + POSITION_EPS: return false
	if begin.bounds.end.x <= float(portal.plane) + POSITION_EPS or executed.bounds.end.x > float(portal.plane) + POSITION_EPS: return false
	if not _fits_portal(begin, executed, portal, {}) or not _inside_air(executed.corners): return false
	_blinks[peer] = {"instance":executed.instance, "shape":executed.shape.duplicate(true), "from":from, "to":executed.position}
	return true

func _translated_sample(sample: Dictionary, origin: Vector3) -> Dictionary:
	var shifted := sample.duplicate(true)
	var offset: Vector3 = origin - sample.position
	var corners: Array[Vector3] = []
	for point in sample.corners: corners.append(point + offset)
	shifted.position = origin
	shifted.bounds = AABB(sample.bounds.position + offset, sample.bounds.size)
	shifted.corners = corners
	return shifted

func step(delta: float, players: Dictionary, entities: Dictionary, objective_id: String, committed_latched: bool) -> Dictionary:
	if _layout.is_empty() or not is_finite(delta) or delta < 0.0 or delta > MAX_DELTA: return {}
	if delta == 0.0: return {} # Pause does not consume blink tokens/samples or retry facts.
	if players.size() > 2: return {}
	var current: Dictionary = {}
	var references: Dictionary = {}
	var seen_bodies: Dictionary = {}
	for peer in players:
		if not peer is int or peer <= 0: return {}
		var body = players[peer]
		if typeof(body) != TYPE_OBJECT or not is_instance_valid(body) or not body is FlightBody or not body.is_inside_tree(): return {}
		if seen_bodies.has(body.get_instance_id()): return {}
		seen_bodies[body.get_instance_id()] = true
		if not _finite(body.health): return {}
		if not body.enabled or float(body.health) <= 0.0: continue
		var sample := _sample(body)
		if sample.is_empty(): return {} # Invalid active envelopes reject the whole tick.
		current[peer] = sample
		references[peer] = weakref(body)
	if objective_id != _objective:
		_crossings.clear()
		_signal_key = ""
		_signal_seconds = 0.0
		_objective = objective_id
	for peer in _crossings.keys():
		if not current.has(peer): _crossings.erase(peer)
		elif not committed_latched: _crossings[peer].erase("north")
	var peers: Array = current.keys()
	peers.sort() # Stable winner if both eligible bodies complete in one tick.
	for peer in peers:
		var now: Dictionary = current[peer]
		var before: Dictionary = _samples.get(peer, {})
		if before.is_empty() or before.instance != now.instance or before.shape != now.shape:
			_crossings.erase(peer)
			if not before.is_empty() and _signal_key.ends_with(":" + str(peer)):
				_signal_key = ""
				_signal_seconds = 0.0
			continue
		if objective_id == ENTER and not _pending.has(ENTER):
			var blink: Dictionary = _blinks.get(peer, {})
			if not blink.is_empty() and blink.instance == now.instance and blink.shape == now.shape:
				_pending[ENTER] = _fact("I1:underdeck_entry", "side_blink", peer)
				_crossings.erase(peer)
				continue
			for portal_id in ["south", "east"]:
				var method := _cross(peer, before, now, portal_id, entities)
				if not method.is_empty():
					_pending[ENTER] = _fact("I1:underdeck_entry", method, peer)
					break
		elif objective_id == TRAVERSE and committed_latched and not _pending.has(TRAVERSE):
			if not _cross(peer, before, now, "north", entities).is_empty():
				_pending[TRAVERSE] = _fact("I1:underdeck_transit", "verified", peer)
	if objective_id == RELEASE:
		var valid := _signals(entities.get(LATCH, {}), current)
		if valid.is_empty():
			_signal_key = ""
			_signal_seconds = 0.0
		elif not _pending.has(RELEASE):
			if not valid.has(_signal_key):
				_signal_key = str(valid.keys()[0])
				_signal_seconds = 0.0
			_signal_seconds = minf(SIGNAL_SECONDS, _signal_seconds + delta)
			if _signal_seconds >= SIGNAL_SECONDS - 0.000000001:
				_pending[RELEASE] = _fact("I1:underdeck_safety_lock", "released", int(valid[_signal_key]))
	elif objective_id != RELEASE:
		_signal_key = ""
		_signal_seconds = 0.0
	# Every accepted positive tick consumes all tokens, even for unknown objectives.
	# A later flight crossing can never inherit an unrelated historical blink.
	_blinks.clear()
	_samples = current
	_body_refs = references
	return _pending.get(objective_id, {}).duplicate(true)

func debug_state() -> Dictionary:
	# Diagnostic copy, not a save format. Respawn uses reset_peer; world uses reset.
	return {"configured":not _layout.is_empty(), "tracked_peers":_samples.keys(), "tracked_body_peers":_body_refs.keys(), "crossings":_crossings.duplicate(true),
		"blinks":_blinks.duplicate(true), "pending":_pending.duplicate(true), "objective":_objective,
		"signal_key":_signal_key, "signal_seconds":_signal_seconds}

func _cross(peer: int, before: Dictionary, now: Dictionary, portal_id: String, entities: Dictionary) -> String:
	var portal: Dictionary = _portals[portal_id]
	var axis: int = portal.axis
	var plane: float = portal.plane
	var old_box: AABB = before.bounds
	var box: AABB = now.bounds
	var progress: Dictionary = _crossings.get(peer, {})
	var token: Dictionary = progress.get(portal_id, {})
	# All three routes have inward/completion direction -Z or -X.
	var advancing: bool = now.position[axis] < before.position[axis] - 0.0000001
	if box.position[axis] >= plane - POSITION_EPS:
		progress.erase(portal_id)
		_crossings[peer] = progress
		return ""
	if token.is_empty():
		if old_box.position[axis] < plane - POSITION_EPS or not advancing: return ""
		# A north crossing must begin IN the real corridor, never at an exterior point.
		if portal_id == "north" and not _inside_air(before.corners): return ""
		token = {"method":"side_flight" if portal_id == "east" else "main_flight", "held":false}
	if not _fits_portal(before, now, portal, entities):
		progress.erase(portal_id)
		_crossings[peer] = progress
		return ""
	if portal_id == "south":
		var gate: Variant = entities.get(FRONT, {})
		if gate is Dictionary and gate.get("pinned", false) is bool and gate.get("pinned", false) and _timer(gate.get("field_remaining", 0), 4.0): token.held = true
	progress[portal_id] = token
	_crossings[peer] = progress
	if box.end[axis] > plane + POSITION_EPS: return ""
	progress.erase(portal_id)
	if portal_id != "north" and not _inside_air(now.corners): return ""
	return "verified" if portal_id == "north" else "held_grille" if token.held else str(token.method)

func _fits_portal(before: Dictionary, now: Dictionary, portal: Dictionary, entities: Dictionary) -> bool:
	var axis: int = portal.axis
	var motion: Vector3 = now.position - before.position
	var angle: float = before.rotation.angle_to(now.rotation)
	# Endpoint envelopes plus radius*angular arc conservatively enclose intermediate
	# rotations. This can reject a very tight tilted entry; it never shrinks a body.
	var padding := maxf(float(before.radius), float(now.radius)) * absf(angle)
	var lo: Vector3 = before.offset_min.min(now.offset_min) - Vector3.ONE * padding
	var hi: Vector3 = before.offset_max.max(now.offset_max) + Vector3.ONE * padding
	var t0 := 0.0
	var t1 := 1.0
	if absf(motion[axis]) > 0.0000001:
		var a: float = (float(portal.plane) - lo[axis] - before.position[axis]) / motion[axis]
		var b: float = (float(portal.plane) - hi[axis] - before.position[axis]) / motion[axis]
		t0 = clampf(minf(a, b), 0.0, 1.0)
		t1 = clampf(maxf(a, b), 0.0, 1.0)
	var p0: Vector3 = before.position + motion * t0
	var p1: Vector3 = before.position + motion * t1
	var low := p0.min(p1) + lo
	var high := p0.max(p1) + hi
	for lateral in range(3):
		if lateral == axis: continue
		if low[lateral] < portal.low[lateral] - POSITION_EPS or high[lateral] > portal.high[lateral] + POSITION_EPS: return false
	if portal.id == "south":
		var gate: Variant = entities.get(FRONT, {})
		if not gate is Dictionary or not gate.get("position") is Vector3 or not gate.position.is_finite(): return false
		var half := _v(_layout.gates.front.size) * 0.5
		if absf(gate.position.y - _v(_layout.gates.front.center).y) > POSITION_EPS or absf(gate.position.z - float(portal.plane)) > POSITION_EPS: return false
		var closed := _v(_layout.gates.front.center)
		var opened := closed + _v(_layout.gates.front.travel)
		if gate.position.x < closed.x - POSITION_EPS or gate.position.x > opened.x + POSITION_EPS: return false
		if high.x > gate.position.x - half.x + POSITION_EPS and low.x < gate.position.x + half.x - POSITION_EPS: return false
	return true

func _signals(raw: Variant, current: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	if not raw is Dictionary: return result
	var tags: Variant = raw.get("tags", [])
	if not tags is Array: return result
	for row in [["echo", "echo_remaining", "operated", "echoed_by", "echo_operable", 5.0],
		["takeover", "takeover_remaining", "controlled", "owner", "hackable", 8.0]]:
		if row[4] not in tags or not raw.get(row[2], false) is bool or not raw.get(row[2], false) or not _timer(raw.get(row[1], 0), row[5]): continue
		if row[0] == "takeover" and "mechanical" not in tags: continue
		var owner: Variant = raw.get(row[3], "")
		if not owner is String: continue
		for peer in current:
			if str(peer) == owner: result[str(row[0]) + ":" + owner] = peer
	return result

func _sample(body: FlightBodyV2) -> Dictionary:
	var envelope := body.get_node_or_null("Envelope") as CollisionShape3D
	if envelope == null or envelope.disabled or not envelope.shape is BoxShape3D or body.get_shape_owners().size() != 1 or (body.collision_layer & 2) == 0: return {}
	var size: Vector3 = envelope.shape.size
	var transform: Transform3D = envelope.global_transform
	if not size.is_finite() or size.x <= 0 or size.y <= 0 or size.z <= 0 or size.length() > 15.0: return {}
	if not transform.origin.is_finite() or not transform.basis.x.is_finite() or not transform.basis.y.is_finite() or not transform.basis.z.is_finite() or transform.basis.determinant() <= 0.000001: return {}
	var corners: Array[Vector3] = []
	var box := AABB()
	var radius := 0.0
	for x in [-0.5, 0.5]:
		for y in [-0.5, 0.5]:
			for z in [-0.5, 0.5]:
				var point: Vector3 = transform * (size * Vector3(x, y, z))
				box = AABB(point, Vector3.ZERO) if corners.is_empty() else box.expand(point)
				corners.append(point)
				radius = maxf(radius, point.distance_to(body.global_position))
	return {"instance":body.get_instance_id(), "shape":{"size":size, "transform":envelope.transform}, "position":body.global_position,
		"rotation":body.global_basis.get_rotation_quaternion(), "bounds":box, "corners":corners,
		"offset_min":box.position - body.global_position, "offset_max":box.end - body.global_position, "radius":radius}

func _inside_air(corners: Array) -> bool:
	for point in corners:
		var inside := false
		for space in _air:
			if space.grow(POSITION_EPS).has_point(point): inside = true; break
		if not inside: return false
	return true

func _fact(target: String, option: String, peer: int) -> Dictionary:
	return {"kind":"fact", "target":target, "option":option, "subject_peer":peer}

func _timer(value: Variant, maximum: float) -> bool:
	return _finite(value) and float(value) > 0.0 and float(value) <= maximum + 0.000001

func _finite(value: Variant) -> bool:
	return typeof(value) in [TYPE_INT, TYPE_FLOAT] and is_finite(float(value))

func _v(value: Variant) -> Vector3:
	if not value is Array or value.size() != 3: return Vector3.INF
	for number in value:
		if not _finite(number): return Vector3.INF
	return Vector3(value[0], value[1], value[2])

func _box(value: Variant) -> AABB:
	if not value is Dictionary: return AABB()
	var low := _v(value.get("min"))
	var high := _v(value.get("max"))
	if not low.is_finite() or not high.is_finite() or high.x <= low.x or high.y <= low.y or high.z <= low.z: return AABB()
	return AABB(low, high - low)

func _check_layout(data: Dictionary) -> Dictionary:
	var bad := {"ok":false, "code":"invalid_layout"}
	if data.get("schema_version") != 1 or data.get("id") != "i1_underdeck_layout_v1" or not _v(data.get("origin")).is_finite(): return bad
	var outer := _box(data.get("outer"))
	if not outer.has_volume() or outer.size.length() > 50.0: return bad
	if not data.get("voids") is Array or data.voids.size() > 8: return bad
	var spaces: Dictionary = {}
	for item in data.voids:
		if not item is Dictionary or not item.get("id") is String or spaces.has(item.id): return bad
		var box := _box(item)
		if not box.has_volume() or not outer.grow(POSITION_EPS).encloses(box): return bad
		spaces[item.id] = box
	for key in ["main_corridor", "side_duct", "turning_chamber"]:
		if not spaces.has(key): return bad
	var main: AABB = spaces.main_corridor
	var side: AABB = spaces.side_duct
	if absf(main.end.z - outer.end.z) > POSITION_EPS or absf(main.position.z - outer.position.z) > POSITION_EPS or absf(side.end.x - outer.end.x) > POSITION_EPS: return bad
	if not data.get("gates") is Dictionary or not data.gates.get("front") is Dictionary: return bad
	var gate: Dictionary = data.gates.front
	var gate_centre := _v(gate.get("center"))
	var gate_size := _v(gate.get("size"))
	var travel := _v(gate.get("travel"))
	if gate.get("entity_id") != FRONT or not gate_centre.is_finite() or not gate_size.is_finite() or not travel.is_finite(): return bad
	if gate_size.x <= 0 or gate_size.y <= 0 or gate_size.z <= 0 or gate_size.length() > 10 or travel.x <= 0 or absf(travel.y) > POSITION_EPS or absf(travel.z) > POSITION_EPS: return bad
	if absf(gate_centre.z - outer.end.z) > POSITION_EPS: return bad
	var air: Array[AABB] = [main, side, spaces.turning_chamber]
	return {"ok":true, "code":"valid", "air":air, "portals":{
		"south":{"id":"south", "axis":2, "plane":main.end.z, "low":main.position, "high":main.end},
		"east":{"id":"east", "axis":0, "plane":side.end.x, "low":side.position, "high":side.end},
		"north":{"id":"north", "axis":2, "plane":main.position.z, "low":main.position, "high":main.end}}}
