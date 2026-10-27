extends RefCounted
## Read-only helper: Root calls once on the currently READY native MAIN World.
const Ecology = preload("res://scripts/v3/ecology/twin_ecology_state.gd")
const Anchors = preload("res://scripts/v3/ecology/twin_npc_anchors.gd")
const MASK := 0xFFFFFFFF
const CONTACT_LIMIT := 8

static func run(world: Node3D, simulation: RefCounted) -> Dictionary:
	if not is_instance_valid(world) or not world.is_inside_tree():
		return {"ok":false,"code":"world_not_in_tree"}
	if not is_instance_valid(simulation) or simulation.get_script() != Ecology:
		return {"ok":false,"code":"original_ecology_required"}
	if not world.global_basis.is_equal_approx(Basis.IDENTITY):
		return {"ok":false,"code":"unscaled_unrotated_world_required"}
	var before: Dictionary = simulation.call("snapshot")
	var checked: Dictionary = simulation.call("validate_snapshot",before)
	if not checked.get("ok",false): return {"ok":false,"code":"ecology_state_invalid"}
	var definition: Dictionary = simulation.call("definitions")
	var digest: String = JSON.stringify(definition,"",true,true).sha256_text()
	if digest != str(before.get("routes_digest","")):
		return {"ok":false,"code":"original_graph_digest_mismatch"}
	var region: String = str(world.get("region_id"))
	var nodes: Dictionary = {}
	var actor_ids: Array = []
	for spec: Dictionary in definition.actors:
		if str(spec.region) == region: actor_ids.append(str(spec.id))
	for graph: Dictionary in definition.regions:
		if str(graph.id) != region: continue
		for node: Dictionary in graph.nodes: nodes[str(node.id)] = node
	if nodes.is_empty() or actor_ids.is_empty():
		return {"ok":false,"code":"no_authored_actors_in_this_world","region":region}
	var edges: Array = []
	var seen: Dictionary = {}
	var ids: Array = nodes.keys()
	ids.sort()
	for id: String in ids:
		for next_id: String in nodes[id].neighbors:
			var pair: Array = [id,next_id]
			pair.sort()
			var key: String = JSON.stringify(pair)
			if seen.has(key): continue
			seen[key] = true
			edges.append(pair)
	if edges.size() > 64: return {"ok":false,"code":"probe_edge_budget"}
	var sphere := SphereShape3D.new()
	sphere.radius = 0.65
	var box := BoxShape3D.new()
	box.size = Vector3(1.4,0.8,1.4)
	var shapes: Array = [sphere,box]
	var space: PhysicsDirectSpaceState3D = world.get_world_3d().direct_space_state
	var report: Dictionary = {"ok":true,"clear":true,"region":region,"actors":actor_ids,
		"scope":"one_native_world_snapshot_fixed_envelopes_not_mesh_or_gameplay_acceptance",
		"routes_digest":digest,"corridor_binding":"F3 service dock 1.6m above receiver, other nodes unchanged","physics_frame":Engine.get_physics_frames(),
		"world_origin":_xyz(world.global_position),"collision_mask":MASK,"areas":false,
		"excluded_bodies":0,"contact_limit":CONTACT_LIMIT,"margin_m":0.01,
		"sphere_radius_m":0.65,"box_size_m":[1.4,0.8,1.4],"rows":[]}
	for edge: Array in edges:
		for reverse: bool in [false,true]:
			var source: String = str(edge[1] if reverse else edge[0])
			var destination: String = str(edge[0] if reverse else edge[1])
			var a: Vector3 = world.to_global(Anchors.node_position(region,source,nodes[source].position))
			var b: Vector3 = world.to_global(Anchors.node_position(region,destination,nodes[destination].position))
			for shape: Shape3D in shapes:
				var row: Dictionary = _sweep(space,shape,a,b)
				row["from_node"] = source
				row["to_node"] = destination
				report["rows"].append(row)
				if not row.get("ok",false): report["ok"] = false
				if not row.get("clear",false): report["clear"] = false
	var after: Dictionary = simulation.call("snapshot")
	report["simulation_unchanged"] = before == after
	if before != after:
		report["ok"] = false
		report["code"] = "simulation_changed_during_read_only_probe"
	return report

static func _sweep(space: PhysicsDirectSpaceState3D, shape: Shape3D, a: Vector3, b: Vector3) -> Dictionary:
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = shape
	query.collision_mask = MASK
	query.collide_with_bodies = true
	query.collide_with_areas = false
	query.margin = 0.01
	query.transform = Transform3D(Basis.IDENTITY,a)
	var start_hits: Array = _contacts(space,query)
	query.transform.origin = b
	var end_hits: Array = _contacts(space,query)
	query.transform.origin = a
	query.motion = b-a
	var fractions: PackedFloat32Array = space.cast_motion(query)
	var row: Dictionary = {"ok":false,"clear":false,"shape":shape.get_class(),
		"from_m":_xyz(a),"to_m":_xyz(b),"start_contacts":start_hits,"end_contacts":end_hits,
		"cast_usable":start_hits.is_empty(),"impact_contacts":[]}
	if fractions.size() != 2:
		row["code"] = "native_fraction_count"
		return row
	var safe: float = fractions[0]
	var unsafe: float = fractions[1]
	if not is_finite(safe) or not is_finite(unsafe) or safe < 0.0 or safe > unsafe or unsafe > 1.0:
		row["code"] = "native_fraction_invalid"
		return row
	row["ok"] = true
	row["safe_fraction"] = safe
	row["unsafe_fraction"] = unsafe
	row["clear"] = start_hits.is_empty() and end_hits.is_empty() and safe == 1.0 and unsafe == 1.0
	row["code"] = "clear" if row["clear"] else "blocked_envelope"
	if not start_hits.is_empty(): row["code"] = "initial_overlap_cast_not_clearance_proof"
	elif safe < 1.0:
		# Virtual query only: sample 1 mm past unsafe for a bounded collider label.
		# Empty labels do not negate the native cast fraction.
		query.transform.origin = a+(b-a)*minf(1.0,unsafe+0.001/(b-a).length())
		query.motion = Vector3.ZERO
		row["impact_contacts"] = _contacts(space,query)
	return row

static func _contacts(space: PhysicsDirectSpaceState3D, query: PhysicsShapeQueryParameters3D) -> Array:
	var result: Array = []
	var hits: Array[Dictionary] = space.intersect_shape(query,CONTACT_LIMIT)
	for hit: Dictionary in hits:
		var collider: Object = hit.get("collider")
		var item: Dictionary = {"shape_index":int(hit.get("shape",-1))}
		if is_instance_valid(collider):
			item["class"] = collider.get_class()
			if collider is Node: item["path"] = str(collider.get_path())
			if collider is CollisionObject3D: item["collision_layer"] = collider.collision_layer
		result.append(item)
	return result

static func _point(value: Array) -> Vector3:
	return Vector3(float(value[0]),float(value[1]),float(value[2]))

static func _xyz(value: Vector3) -> Array:
	return [value.x,value.y,value.z]
