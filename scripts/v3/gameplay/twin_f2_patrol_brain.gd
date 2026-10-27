extends "res://scripts/v2/enemy_brain.gd"
## Single F2 adapter. Original step/profile/FOV/reaction/memory/aim stay inherited.
## Only candidate enumeration, map bounds and physical steering differ from V2.

func _sense() -> void:
	seen=false
	var candidates: Array=combat.candidate_players()
	var best: CollisionObject3D
	var best_distance: float=INF
	for candidate: Variant in candidates:
		if not is_instance_valid(candidate) or candidate.is_queued_for_deletion(): continue
		var difference: Vector3=candidate.global_position-body.global_position
		var distance_m: float=difference.length()
		if distance_m>float(profile.range) or distance_m>=best_distance: continue
		var horizontal:=Vector3(difference.x,0,difference.z).normalized()
		if distance_m>4.0 and Vector3(-sin(heading),0,-cos(heading)).dot(horizontal)<cos(deg_to_rad(float(profile.fov))): continue
		if perception_visibility.is_valid() and not bool(perception_visibility.call(body.global_position,candidate.global_position)): continue
		if not _line_clear(body.global_position,candidate.global_position,candidate.get_rid()): continue
		best=candidate
		best_distance=distance_m
	if best!=null:
		if target!=best: reaction_time=0; report_progress=0
		target=best
		seen=true
		last_seen_position=best.global_position
		memory_age=0
		last_seen_velocity=best.velocity if best is CharacterBody3D else (best.linear_velocity if best is RigidBody3D else Vector3.ZERO)
		last_seen_velocity=last_seen_velocity.limit_length(12.0)
		confidence=maxf(confidence,.25)

func _bounded(point: Vector3) -> Vector3:
	# Same original altitude clearance, constrained to the actual negative map.
	var box: AABB=combat.flight_bounds()
	var dimensions: Vector3=body.get("dimensions")
	var radius: float=maxf(dimensions.x,dimensions.z)*.5
	var result:=Vector3(clampf(point.x,box.position.x+radius,box.end.x-radius),point.y,clampf(point.z,box.position.z+radius,box.end.z-radius))
	var floor_y: float=maxf(MIN_ALTITUDE,_terrain(result)+MIN_ALTITUDE)
	result.y=clampf(result.y,minf(floor_y,box.end.y-radius),box.end.y-radius)
	return combat.allowed_goal(result,body.global_position)

func _sweep(from: Vector3, motion: Vector3) -> float:
	# Current actual collider and same World3D, including pilots; no sphere proxy.
	return float(combat.motion_fraction(body,from,motion))

func _route(_goal: Vector3) -> PackedVector3Array:
	# V2's positive600x500 A* is inapplicable. Original local swept avoidance
	# remains active; a blocked single patrol stops instead of gaining a fake path.
	return PackedVector3Array()

func ceasefire() -> void:
	# Genuine safety-policy transition, not a save/checkpoint or objective fact.
	seen=false
	target=null
	reaction_time=0.0
	confidence=0.0
	memory_age=999.0
	report_progress=0.0
	_noise_left=0.0
	state="patrol"
	_path.clear()
