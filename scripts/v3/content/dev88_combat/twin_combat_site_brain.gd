extends "res://scripts/v3/gameplay/twin_f2_patrol_brain.gd"
## Original perception cadence, FOV, aim error, steering and memory. The owner
## supplies only actual target bodies in the active encounter's bounded space.

func _sense() -> void:
	seen = false
	var best: CollisionObject3D
	var best_distance := INF
	for candidate: Variant in combat.candidate_targets(body):
		if not is_instance_valid(candidate) or candidate.is_queued_for_deletion(): continue
		var difference: Vector3 = candidate.global_position - body.global_position
		var distance_m: float = difference.length()
		if distance_m > float(profile.range) or distance_m >= best_distance: continue
		var horizontal := Vector3(difference.x, 0, difference.z).normalized()
		if distance_m > 4.0 and Vector3(-sin(heading), 0, -cos(heading)).dot(horizontal) < cos(deg_to_rad(float(profile.fov))): continue
		if perception_visibility.is_valid() and not bool(perception_visibility.call(body.global_position, candidate.global_position)): continue
		if not _line_clear(body.global_position, candidate.global_position, candidate.get_rid()): continue
		best = candidate
		best_distance = distance_m
	if best != null:
		if target != best: reaction_time = 0.0; report_progress = 0.0
		target = best
		seen = true
		last_seen_position = best.global_position
		memory_age = 0.0
		last_seen_velocity = best.velocity if best is CharacterBody3D else (best.linear_velocity if best is RigidBody3D else Vector3.ZERO)
		last_seen_velocity = last_seen_velocity.limit_length(12.0)
		confidence = maxf(confidence, .25)

func _bounded(point: Vector3) -> Vector3:
	var box: AABB = combat.flight_bounds()
	var dimensions: Vector3 = body.dimensions
	var radius: float = maxf(dimensions.x, dimensions.z) * .5 + .1
	var result := Vector3(clampf(point.x, box.position.x + radius, box.end.x - radius), point.y,
		clampf(point.z, box.position.z + radius, box.end.z - radius))
	var floor_y: float = maxf(box.position.y + dimensions.y * .5 + .1, _terrain(result) + MIN_ALTITUDE)
	result.y = clampf(result.y, minf(floor_y, box.end.y - dimensions.y * .5 - .1), box.end.y - dimensions.y * .5 - .1)
	return combat.allowed_goal(result, body.global_position)
