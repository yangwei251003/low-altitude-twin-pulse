extends RefCounted
## Read-only pre-commit check for the existing static-body light/Y-angle adapter.
## Same real-shape sampling idea as CampaignSession G, without changing its path.
const STEPS := 8
const MAX_SHAPES := 8
const MASK := 1 | 2 | 4 | 8
const MARGIN_M := .001

static func inspect(owner_world: Node3D, body: StaticBody3D, old_angle: float, next_angle: float) -> Dictionary:
	var result := {"ok":false,"code":"invalid_rotation_geometry","entity_id":"","steps":STEPS,"shape_count":0,"queries":0,"blockers":[]}
	if not is_instance_valid(owner_world) or not owner_world.is_inside_tree() or not is_instance_valid(body) or not body.is_inside_tree(): return result
	if body.get_world_3d()!=owner_world.get_world_3d() or not body.get_rid().is_valid(): return result
	result.entity_id=str(body.get_meta("entity_id",""))
	if not is_finite(old_angle) or not is_finite(next_angle) or absf(old_angle)>PI+.001 or absf(next_angle)>PI+.001 or not is_equal_approx(wrapf(next_angle-old_angle,-PI,PI),PI/6.0): return result
	if not is_equal_approx(wrapf(body.rotation.y-old_angle,-PI,PI),0.0): return result
	# This is the World.synchronize static Y-angle adapter, not F1's Z rotor.
	if not is_zero_approx(body.rotation.x) or not is_zero_approx(body.rotation.z) or not body.scale.is_equal_approx(Vector3.ONE): return result
	var parent := body.get_parent() as Node3D
	if not is_instance_valid(parent) or not _frame(parent.global_transform): return result
	var old_pose: Transform3D=body.global_transform
	if not _frame(old_pose): return result
	var native: Variant=PhysicsServer3D.body_get_state(body.get_rid(),PhysicsServer3D.BODY_STATE_TRANSFORM)
	if not native is Transform3D or not native.is_equal_approx(old_pose) or PhysicsServer3D.body_get_space(body.get_rid())!=owner_world.get_world_3d().space: return result
	var next_pose: Transform3D=parent.global_transform*Transform3D(Basis(Vector3.UP,next_angle),body.position)
	if not _frame(next_pose): return result
	var owners := body.get_shape_owners()
	if owners.is_empty() or owners.size()>MAX_SHAPES: return result
	var shapes: Array=[]
	var registered := 0
	for owner: int in owners:
		var count: int=body.shape_owner_get_shape_count(owner)
		if count<1 or registered+count>MAX_SHAPES: return result
		registered+=count
		if body.is_shape_owner_disabled(owner): continue
		var local_pose: Transform3D=body.shape_owner_get_transform(owner)
		if not _frame(local_pose): return result
		for index in count:
			var shape: Shape3D=body.shape_owner_get_shape(owner,index)
			# The current F2 physical light mirrors use these real BoxShapes.
			# Other adapters require their own explicit geometry contract.
			var box := shape as BoxShape3D
			if box==null or not box.size.is_finite() or minf(box.size.x,minf(box.size.y,box.size.z))<=0 or maxf(box.size.x,maxf(box.size.y,box.size.z))>32.0: return result
			shapes.append({"shape":box,"pose":local_pose})
	if shapes.is_empty() or registered!=PhysicsServer3D.body_get_shape_count(body.get_rid()): return result
	result.shape_count=shapes.size()
	var query := PhysicsShapeQueryParameters3D.new()
	query.collision_mask=MASK
	query.exclude=[body.get_rid()] # Never exclude the requesting pilot or another mirror.
	query.margin=MARGIN_M
	query.collide_with_bodies=true
	query.collide_with_areas=false
	# Include the real start pose, eight bounded intermediate/final orientations.
	# This is discrete native shape sampling, not a mathematical continuous sweep.
	for step in range(STEPS+1):
		var pose: Transform3D=old_pose.interpolate_with(next_pose,float(step)/float(STEPS))
		for row: Dictionary in shapes:
			query.shape=row.shape
			query.transform=pose*row.pose
			var hits: Array[Dictionary]=owner_world.get_world_3d().direct_space_state.intersect_shape(query,4)
			result.queries+=1
			if not hits.is_empty():
				for hit: Dictionary in hits:
					var collider: Variant=hit.get("collider")
					result.blockers.append({"step":step,"path":str(collider.get_path()) if collider is Node else "","entity_id":str(collider.get_meta("entity_id","")) if collider is Object else "","rid":str(hit.get("rid"))})
				result.code="rotation_blocked"
				return result
	result.ok=true
	result.code="rotation_clear"
	return result

static func _frame(value: Transform3D) -> bool:
	for vector: Vector3 in [value.origin,value.basis.x,value.basis.y,value.basis.z]:
		if not vector.is_finite(): return false
	return maxf(absf(value.origin.x),maxf(absf(value.origin.y),absf(value.origin.z)))<=1000.0 and value.basis.determinant()>.9999 and value.basis.is_equal_approx(value.basis.orthonormalized())
