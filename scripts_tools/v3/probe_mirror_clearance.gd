extends "res://scripts_tools/v3/probe_optics_main.gd"
## Observe original light rotation beside an actually clear whole aircraft hull.
func _exercise() -> bool:
	report.fixture_scope = "New private original Main/F2 area and stationary-player pose fixtures only. Find an initial whole-hull-clear pose whose future mirror shape intersects the actual player. Original Host lock/light then observe native overlap, energy, angle, health. No Story/fact/HP/time/mirror pose fixture; no save/old-profile/graphics/LAN claim."
	if not await _open(): return false
	var actor: FlightBodyV2 = session.players[1]
	var envelope := actor.get_node("Envelope") as CollisionShape3D
	var mirror: PhysicsBody3D = session.world.objects[M2]
	var mirror_shape: CollisionShape3D
	for child: Node in mirror.get_children():
		if child is CollisionShape3D and child.shape != null:
			mirror_shape = child
			break
	if not _check(mirror_shape != null,"actual mirror collider exists"): return false
	var found := false
	var position := Vector3.ZERO
	var future_hits: Array = []
	for x: float in [.7,.9,1.1,1.3,1.5]:
		for z: float in [1.4,1.6,1.8,2.0]:
			var at: Vector3 = mirror.global_position+Vector3(x,0,z)
			var clear_query := PhysicsShapeQueryParameters3D.new()
			clear_query.shape = envelope.shape
			clear_query.transform = Transform3D(Basis.IDENTITY,at)*envelope.transform
			clear_query.collision_mask = 1|2|4|8|32
			clear_query.exclude = [actor.get_rid()]
			if not session.world.get_world_3d().direct_space_state.intersect_shape(clear_query,1).is_empty(): continue
			actor.freeze = true
			actor.global_transform = Transform3D(Basis.IDENTITY,at)
			actor.force_update_transform()
			PhysicsServer3D.body_set_state(actor.get_rid(),PhysicsServer3D.BODY_STATE_TRANSFORM,actor.global_transform)
			actor.linear_velocity = Vector3.ZERO
			actor.angular_velocity = Vector3.ZERO
			actor.hold_height = at.y
			if not await _frames(2): return false
			var future_query := PhysicsShapeQueryParameters3D.new()
			future_query.shape = mirror_shape.shape
			future_query.transform = Transform3D(Basis(Vector3.UP,deg_to_rad(15)),mirror.global_position)*mirror_shape.transform
			future_query.collision_mask = 2
			future_query.exclude = [mirror.get_rid()]
			future_hits = session.world.get_world_3d().direct_space_state.intersect_shape(future_query,16)
			if future_hits.any(func(hit: Dictionary): return hit.get("collider")==actor):
				found = true
				position = at
				break
		if found: break
	if not _check(found,"native initial-clear and future-mirror-overlap player pose found"): return false
	var angle_before: float = session.entities[M2].angle
	var energy_before: float = session.entities["player:1"].energy
	var health_before: float = actor.health
	var abilities_before: int = session.stats.abilities
	session.network.send_action("lock",{"target_id":M2})
	session.network.send_action("ability",{"ability":"light","target_id":M2,"mode":""})
	if not await _frames(6): return false
	var final_query := PhysicsShapeQueryParameters3D.new()
	final_query.shape = envelope.shape
	final_query.transform = actor.global_transform*envelope.transform
	final_query.collision_mask = 8
	final_query.exclude = [actor.get_rid()]
	var actual_hits: Array = session.world.get_world_3d().direct_space_state.intersect_shape(final_query,16)
	var intersects_mirror: bool = actual_hits.any(func(hit: Dictionary): return hit.get("collider")==mirror)
	var accepted: bool = int(session.stats.abilities)>abilities_before
	var native_actual: Transform3D = PhysicsServer3D.body_get_state(actor.get_rid(),PhysicsServer3D.BODY_STATE_TRANSFORM)
	report["rotation_clearance"] = {"fixture_position":position,"initial_clear":true,"future_actual_mirror_shape_overlaps_actor":true,
		"ability_accepted":accepted,"angle_before":angle_before,"angle_after":session.entities[M2].angle,
		"energy_before":energy_before,"energy_after":session.entities["player:1"].energy,
		"health_before":health_before,"health_after":actor.health,"actual_actor_mirror_overlap":intersects_mirror,"host_clearance_preflight":session.last_light_rotation_clearance.duplicate(true),
		"actual_query_hits":actual_hits.map(func(hit: Dictionary): return {"collider_id":hit.get("collider_id"),"entity_id":str(hit.collider.get_meta("entity_id","")),"shape":hit.get("shape")}),"actual_actor_position":actor.global_position,"native_actor_position":native_actual.origin}
	var rejected_safely: bool = not accepted and not intersects_mirror and is_equal_approx(float(session.entities[M2].angle),angle_before) and is_equal_approx(float(session.entities["player:1"].energy),energy_before)
	if not _check(rejected_safely,"near blocked rotation leaves actual hull clear, mirror angle and energy unchanged",report.rotation_clearance): return false
	if not await _place(): return false
	return await _light(M2)
