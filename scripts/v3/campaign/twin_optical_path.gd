extends RefCounted
## Bounded two-sided mirror reflection. No simulation, facts, entities or Store writes.
## A native nearest-hit query owns every displayed span; never skip unknown bodies.
const MAX_TURNS := 4
const TOTAL_LENGTH_M := 88.0
const MAX_COORDINATE_M := 1000.0
const MIN_SPAN_M := 0.00001
const MASK := 1 | 4 | 8 # Opaque terrain, live scout, mechanism/Boss collision.

static func trace(owner_world: Node3D, source: PhysicsBody3D, first: PhysicsBody3D, receiver: PhysicsBody3D, second: PhysicsBody3D = null) -> Dictionary:
	var result := {"valid":false,"code":"invalid_input","segments":[],"mirror_hits":[],"receiver_hit":Vector3.ZERO,"distance_m":0.0,"turns":0}
	if not is_instance_valid(owner_world) or not owner_world.is_inside_tree(): return result
	var registered: Array[PhysicsBody3D] = [source,first,receiver]
	if second != null: registered.append(second)
	var identities: Dictionary = {}
	for body: PhysicsBody3D in registered:
		if not _body_ready(owner_world,body) or identities.has(body.get_instance_id()): return result
		identities[body.get_instance_id()] = true
	var from: Vector3 = source.global_position
	var direction: Vector3 = source.global_basis.x.normalized()
	if not direction.is_finite() or not is_finite(direction.length_squared()) or direction.length_squared()<.99: return result
	var space: PhysicsDirectSpaceState3D = owner_world.get_world_3d().direct_space_state
	var previous: PhysicsBody3D = source
	var visited: Dictionary = {}
	for unused in range(MAX_TURNS+1):
		var remaining: float = TOTAL_LENGTH_M-float(result.distance_m)
		if not is_finite(remaining) or remaining<=MIN_SPAN_M: return _stop(result,"length_budget")
		var endpoint: Vector3 = from+direction*remaining
		if not endpoint.is_finite(): return _stop(result,"nonfinite_endpoint")
		# Exclude ONLY the just-left convex body, not every visited mirror.
		# Start at its exact surface: no epsilon can jump a thin adjacent blocker.
		var query := PhysicsRayQueryParameters3D.create(from,endpoint,MASK)
		query.exclude = [previous.get_rid()]
		query.hit_from_inside = true
		query.hit_back_faces = true
		var hit: Dictionary = space.intersect_ray(query)
		if hit.is_empty():
			result.segments.append([from,endpoint]) # Actual queried empty span, never a success.
			result.distance_m = TOTAL_LENGTH_M
			return _stop(result,"no_hit_within_budget")
		if not hit.get("position") is Vector3 or not hit.get("normal") is Vector3: return _stop(result,"invalid_native_hit")
		var point: Vector3 = hit.position
		var normal: Vector3 = hit.normal
		var distance: float = from.distance_to(point)
		if not point.is_finite() or not normal.is_finite() or not is_finite(distance) or distance>remaining+.0001: return _stop(result,"invalid_native_hit")
		result.segments.append([from,point])
		result.distance_m += distance
		# An inside/zero-distance hit is a blocker; do not step through it.
		if distance<=MIN_SPAN_M or normal.length_squared()<.5: return _stop(result,"inside_or_degenerate_hit")
		normal = normal.normalized()
		var collider: Variant = hit.get("collider")
		if collider == receiver:
			if result.mirror_hits.is_empty(): return _stop(result,"first_mirror_required")
			var front: Vector3 = -receiver.global_basis.z.normalized()
			if normal.dot(front)<.8 or direction.dot(front)>-.1: return _stop(result,"receiver_back_or_edge")
			result.valid = true
			result.receiver_hit = point
			return _stop(result,"receiver_front")
		var mirror: PhysicsBody3D
		if collider == first: mirror = first
		elif is_instance_valid(second) and collider == second: mirror = second
		else: return _stop(result,"opaque_first_hit")
		var id: int = mirror.get_instance_id()
		if visited.has(id): return _stop(result,"mirror_cycle")
		if result.mirror_hits.is_empty() and mirror != first: return _stop(result,"first_mirror_required")
		# Thin local-X faces reflect; the thick box's edges remain opaque.
		if absf(normal.dot(mirror.global_basis.x.normalized()))<.95: return _stop(result,"mirror_edge")
		if int(result.turns)>=MAX_TURNS: return _stop(result,"turn_budget")
		visited[id] = true
		result.mirror_hits.append({"id":str(mirror.get_meta("entity_id","")),"position":point})
		result.turns += 1
		direction = (direction-2.0*direction.dot(normal)*normal).normalized()
		if not direction.is_finite() or not is_finite(direction.length_squared()) or direction.length_squared()<.99: return _stop(result,"invalid_reflection")
		from = point
		previous = mirror
	return _stop(result,"turn_budget")

static func _body_ready(owner_world: Node3D, body: PhysicsBody3D) -> bool:
	if not is_instance_valid(body) or not body.is_inside_tree() or body.get_world_3d()!=owner_world.get_world_3d() or not body.get_rid().is_valid(): return false
	var frame: Transform3D = body.global_transform
	for vector: Vector3 in [frame.origin,frame.basis.x,frame.basis.y,frame.basis.z]:
		if not vector.is_finite(): return false
	if maxf(absf(frame.origin.x),maxf(absf(frame.origin.y),absf(frame.origin.z)))>MAX_COORDINATE_M: return false
	var determinant: float = frame.basis.determinant()
	if not is_finite(determinant) or absf(determinant)<.000001: return false
	# Read both native physics and visible body poses; never credit a new angle
	# against the previous native collider frame while synchronization is pending.
	var raw: Variant = PhysicsServer3D.body_get_state(body.get_rid(),PhysicsServer3D.BODY_STATE_TRANSFORM)
	if not raw is Transform3D: return false
	var native: Transform3D = raw
	return native.is_equal_approx(frame)

static func _stop(result: Dictionary, code: String) -> Dictionary:
	result.code = code
	return result
