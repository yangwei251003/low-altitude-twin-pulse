extends SceneTree
## Independent module with production TR01/HX02 collision envelopes and actual
## PhysicsServer rays/motions. Explicit placement/snapshot fixtures are not a
## Session/story playthrough, rendering, performance, or human-play evidence.
const Passage = preload("res://scripts/v3/world/twin_underdeck_passage.gd")
const FlightBody = preload("res://scripts/v2/flight_body.gd")
const Catalog = preload("res://scripts/v2/catalog.gd")
const Rules = preload("res://scripts/v3/gameplay/twin_ability_rules.gd")
var world: Node3D
var passage: Node3D
var bodies: Dictionary = {}
var checks := 0
var failures: Array = []
var done := false
var rules := Rules.new()

func _init() -> void:
	_run.call_deferred()

func _check(ok: bool, label: String, details: Dictionary = {}) -> void:
	checks += 1
	if not ok:
		failures.append({"check":label,"details":details})
		push_error("UNDERDECK " + label + " " + JSON.stringify(details))

func _run() -> void:
	create_timer(45).timeout.connect(func():
		if not done:
			push_error("UNDERDECK timeout; no pass implied")
			quit(2))
	_test_layout_rejection()
	world = Node3D.new()
	root.add_child(world)
	passage = Passage.new()
	var loaded: Dictionary = passage.load_layout(true)
	_check(loaded.ok, "independent layout builds", loaded)
	if not loaded.ok:
		passage.free()
		await _finish()
		return
	world.add_child(passage)
	for row in [[1,"tr01"],[2,"hx02"]]:
		var body := FlightBody.new()
		body.configure(Catalog.resolve_build(Catalog.default_build(row[1])))
		body.freeze = true
		body.position = Vector3(-49,10+int(row[0])*3,-44)
		world.add_child(body)
		body.set_process(false)
		body.set_physics_process(false)
		bodies[row[0]] = body
	await _settle()
	_test_geometry()
	_test_snapshot_guards()
	await _test_clock_and_pin()
	await _test_routes()
	await _test_pinch()
	await _test_committed_and_client()
	await _finish()

func _test_layout_rejection() -> void:
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(Passage.PATH))
	for kind in ["roof", "cycle", "void_count", "gate", "nan"]:
		var invalid: Dictionary = data.duplicate(true)
		match kind:
			"roof": invalid.voids[0].max[1] = 6.0
			"cycle": invalid.cycle_usec.period = 8000001
			"void_count": invalid.voids = []
			"gate": invalid.gates.front.travel[0] = 18.0
			"nan": invalid.anchors.entry[0] = NAN
		var candidate := Passage.new()
		var rejected: Dictionary = candidate.configure(invalid)
		_check(not rejected.ok and not candidate.configured and candidate.get_child_count()==0 and candidate.snapshot().is_empty(), "invalid layout atomically refused: " + kind, rejected)
		_check(candidate.configure(data).ok, "failed configure can retry valid layout: " + kind)
		candidate.free()

func _settle() -> void:
	await physics_frame
	await physics_frame
	await process_frame

func _place(id: int, at: Vector3, yaw: float = 0.0) -> void:
	var body: RigidBody3D = bodies[id]
	body.global_transform = Transform3D(Basis(Vector3.UP,yaw),at)
	body.linear_velocity = Vector3.ZERO
	body.angular_velocity = Vector3.ZERO
	PhysicsServer3D.body_set_state(body.get_rid(),PhysicsServer3D.BODY_STATE_TRANSFORM,body.global_transform)
	await _settle()

func _park() -> void:
	for id in bodies: await _place(id,Vector3(-49,10+int(id)*3,-44))

func _ray(a: Vector3, b: Vector3) -> Dictionary:
	var query := PhysicsRayQueryParameters3D.create(a,b,1|8)
	query.hit_back_faces = true
	return world.get_world_3d().direct_space_state.intersect_ray(query)

func _fixture(phase: int = 0, front: float = 0.0, rear: float = 0.0, latched: bool = false) -> void:
	# Explicit mechanism fixture for boundary tests, not an earned story result.
	var state: Dictionary = passage.snapshot()
	state.phase_usec = phase
	state.front_fraction = front
	state.rear_fraction = rear
	state.latched = latched
	state.front_pinned = false
	state.front_obstructed = false
	state.rear_obstructed = false
	_check(passage.apply_snapshot(state).ok,"boundary fixture accepted")

func _test_geometry() -> void:
	var faces: PackedVector3Array = passage.geometry_faces()
	var collision: ConcavePolygonShape3D = passage.shell.get_node("ExactSurfaceCollision").shape
	_check(faces==collision.get_faces(),"collision retains the exact ordered authoring triangles")
	# Independent float32 replay of the pre-split partition; do not refresh this
	# lock when making a visual change. Runtime validation still checks real bytes.
	var digest := HashingContext.new()
	digest.start(HashingContext.HASH_SHA256)
	digest.update(faces.to_byte_array())
	var actual_sha256 := digest.finish().hex_encode()
	_check(actual_sha256=="8a9138bcf652ba71777aa89ec89bff8b790068b6e0c5b570c252560d51ee6473","visual split preserves the pre-change 696-triangle collision bytes",{"actual_sha256":actual_sha256})
	_test_visual_partition(faces)
	_check(faces.size()>100 and faces.size()<30000,"bounded partition mesh",{"triangles":faces.size()/3})
	var nondegenerate := true
	for i in range(0,faces.size(),3):
		if (faces[i+1]-faces[i]).cross(faces[i+2]-faces[i]).length_squared()<1e-14: nondegenerate=false
	_check(nondegenerate,"no zero-area shell triangle")
	var hidden_box := false
	for child in passage.find_children("*","CollisionShape3D",true,false):
		if child.shape is BoxShape3D and child.shape.size.is_equal_approx(Vector3(17,6,17)): hidden_box=true
	_check(not hidden_box,"no old warehouse box fills the new corridors")
	for side in ["front","rear"]:
		var panel: Node3D = passage.gates[side]
		var physical: PackedVector3Array = panel.get_node("ExactConvexPanel").shape.points
		var corners: Array[Vector3] = []
		for point in physical:
			if point not in corners: corners.append(point)
		# Measured from committed dev.14 in the same engine, then compared byte for
		# byte with this version. ArrayMesh readback differs from scalar literals by
		# a float32 ULP on Y/Z; lock actual prior bytes rather than rounded extents.
		var hull_digest := HashingContext.new()
		hull_digest.start(HashingContext.HASH_SHA256)
		hull_digest.update(physical.to_byte_array())
		var hull_sha := hull_digest.finish().hex_encode()
		_check(physical.size()==36 and corners.size()==8 and hull_sha=="1a854b599e860ef98436c8c70070262ed7cbcceb88c1aee04206c6486aae01ee",side+" preserves exact committed dev14 convex collision bytes", {"points":physical.size(),"sha256":hull_sha})
		_check(not panel.has_node("SolidGrillePanel") and panel.find_children("PanelStripe*","MeshInstance3D",true,false).is_empty(),side+" old rendered box and painted stripes are removed")
		_test_gate_art(side, panel)
	for row in [[Vector3(-35,3,-30),Vector3(-35,0,-30),0.45,"main floor"],[Vector3(-28,4,-23.5),Vector3(-28,1,-23.5),2.3,"side floor"],[Vector3(-32,4,-23.5),Vector3(-32,0,-23.5),0.45,"joining chamber floor"]]:
		var hit := _ray(row[0],row[1])
		_check(not hit.is_empty() and absf(float(hit.position.y)-float(row[2]))<0.002,"actual " + row[3],{"hit":str(hit.get("position"))})
	for x in [-42.0,-35.0,-28.0]:
		for dx in [-1.45,0.0,1.45]:
			for dz in [-1.45,0.0,1.45]:
				var hit := _ray(Vector3(x+dx,7,-26+dz),Vector3(x+dx,5.5,-26+dz))
				_check(not hit.is_empty() and absf(float(hit.position.y)-6.0)<0.002,"roof Y6 supports actual column footprint %s/%s/%s" % [x,dx,dz])
	_check(_ray(Vector3(-24,3.55,-23.5),Vector3(-35,3.55,-23.5)).is_empty(),"high side window is a real opening")
	_check(not _ray(Vector3(-40,2,-17),Vector3(-40,2,-37)).is_empty(),"uncut warehouse wall remains solid")
	_check(passage.get_node("GrayboxMaintenanceMarkings").get_child_count()>8,"repair lanes, frames, lamps and dry water marks remain outside the fade subtree")
	_check(passage.anchor_position("not-an-anchor")==null,"unknown anchor does not fall back to origin")
	var copy: Dictionary = passage.layout()
	copy.outer.min[0] = 0
	_check(passage.layout().outer.min[0]==-43.5,"layout accessor returns copy")
	faces[0]=Vector3(900,900,900)
	_check(passage.geometry_faces()[0]!=faces[0],"geometry accessor returns copy")
	_test_gate_art_motion()

func _test_gate_art(side: String, panel: Node3D) -> void:
	var art: Node3D = panel.get_node("AuthoredMovingPanel")
	var bodies_found := art.find_children("PanelBody", "MeshInstance3D", true, false)
	_check(bodies_found.size() == 1, side+" imports a single continuous authored door body")
	if bodies_found.size() != 1: return
	var body: MeshInstance3D = bodies_found[0]
	var to_panel := panel.global_transform.affine_inverse() * body.global_transform
	var points := PackedVector3Array()
	for point in body.mesh.get_faces(): points.append(to_panel * point)
	var low := points[0]
	var high := points[0]
	for point in points:
		low = low.min(point)
		high = high.max(point)
	_check(low.is_equal_approx(Vector3(-1.9,-1.6,-0.15)) and high.is_equal_approx(Vector3(1.9,1.6,0.15)),side+" real GLB solid matches physical panel envelope",{"min":str(low),"max":str(high)})
	# Independent triangle-ray samples must encounter both authored solid faces,
	# including inset fields. An empty grille behind a box collider fails this.
	var covered := true
	for x in [-1.7,-1.0,0.0,1.0,1.7]:
		for y in [-1.4,-0.8,0.0,0.8,1.4]:
			var front_hit := false
			var back_hit := false
			for i in range(0, points.size(), 3):
				var hit: Variant = Geometry3D.segment_intersects_triangle(Vector3(x,y,0.25),Vector3(x,y,-0.25),points[i],points[i+1],points[i+2])
				if hit is Vector3:
					front_hit = front_hit or hit.z > 0.08
					back_hit = back_hit or hit.z < -0.08
			covered = covered and front_hit and back_hit
	_check(covered,side+" actual authored triangles close both faces across 25 independent samples")
	var textured := true
	for mesh in art.find_children("*","MeshInstance3D",true,false):
		for surface in range(mesh.mesh.get_surface_count()):
			var arrays: Array = mesh.mesh.surface_get_arrays(surface)
			var material := mesh.get_active_material(surface) as StandardMaterial3D
			textured = textured and arrays[Mesh.ARRAY_TEX_UV] != null and arrays[Mesh.ARRAY_TEX_UV].size() == arrays[Mesh.ARRAY_VERTEX].size()
			textured = textured and material != null and material.albedo_texture != null and material.normal_enabled and material.normal_texture != null
	_check(textured,side+" real import retains UV base color and normal textures on each moving surface")
	_check(art.find_children("*","CollisionObject3D",true,false).is_empty() and art.find_children("*","Camera3D",true,false).is_empty() and art.find_children("*","Light3D",true,false).is_empty(),side+" imported art adds no duplicate collision or studio camera/light")
	_check(art.basis.x.is_equal_approx(Vector3.LEFT if side=="rear" else Vector3.RIGHT),side+" visual parking direction agrees with world slide direction")

func _test_gate_art_motion() -> void:
	var saved: Dictionary = passage.snapshot()
	var front_rail: Node3D = passage.get_node("GrayboxMaintenanceMarkings/FrontFixedRail")
	var rear_rail: Node3D = passage.get_node("GrayboxMaintenanceMarkings/RearFixedRail")
	var fixed_before := [front_rail.global_transform,rear_rail.global_transform]
	_check(passage._lamps.front.material_override != passage._lamps.rear.material_override,"front/rear lamps own distinct materials")
	for rail in [front_rail, rear_rail]:
		var originals: Array[Node] = rail.find_children("StatusLens", "MeshInstance3D", true, false)
		var repeaters: Array[Node] = rail.find_children("StatusRepeater", "MeshInstance3D", true, false)
		_check(originals.size() == 1 and repeaters.size() == 1,"fixed rail has one authored lens and one rear repeater")
		if originals.size() != 1 or repeaters.size() != 1: continue
		var lens: MeshInstance3D = originals[0]
		var repeater: MeshInstance3D = repeaters[0]
		_check(lens.mesh == repeater.mesh and lens.material_override == repeater.material_override,"same gate shares actual lens geometry and live state on both faces")
		var front_center: Vector3 = lens.transform * lens.get_aabb().get_center()
		var back_center: Vector3 = repeater.transform * repeater.get_aabb().get_center()
		_check(front_center.z > 0.22 and back_center.z < -0.22 and is_equal_approx(front_center.y,back_center.y),"two lens faces sit outside opposite sides of opaque rail")
	var next: Dictionary = saved.duplicate(true)
	next.front_fraction = 0.5
	next.rear_fraction = 1.0
	_check(passage.apply_snapshot(next).ok,"explicit half/front full/rear art pose fixture applies")
	_check(front_rail.global_transform == fixed_before[0] and rear_rail.global_transform == fixed_before[1],"both real rails stay fixed while door bodies slide")
	_check(passage.gates.front.get_node("AuthoredMovingPanel").global_position.is_equal_approx(Vector3(-32.9,2.05,-18.5)) and passage.gates.rear.get_node("AuthoredMovingPanel").global_position.is_equal_approx(Vector3(-39.2,2.05,-35.5)),"imported moving roots follow opposite authoritative travel")
	_check(passage._lamps.front.material_override.albedo_color != passage._lamps.rear.material_override.albedo_color,"partial front and fully open rear publish different colors on actual lenses")
	_check(passage.apply_snapshot(saved).ok,"restore original mechanism after art fixture")

func _rectangle(points: PackedVector3Array, start: int) -> Dictionary:
	var low := points[start]
	var high := low
	for i in range(start, start + 6):
		low = low.min(points[i])
		high = high.max(points[i])
	var size := high - low
	var axis := 0 if size.x == 0.0 else 1 if size.y == 0.0 else 2
	var u := (axis + 1) % 3
	var v := (axis + 2) % 3
	var normal := (points[start+1]-points[start]).cross(points[start+2]-points[start]).normalized()
	var area := 0.0
	for i in [start, start+3]: area += (points[i+1]-points[i]).cross(points[i+2]-points[i]).length() * 0.5
	return {"low":low,"high":high,"axis":axis,"plane":low[axis],"u":u,"v":v,"normal":normal,"area":area,
		"valid":size[axis]==0.0 and size[u]>0.0 and size[v]>0.0 and absf(area-size[u]*size[v])<0.00001 and points[start]==points[start+3] and points[start+2]==points[start+4]}

func _test_visual_partition(original: PackedVector3Array) -> void:
	# GLB import may reorder triangle indices and choose the other diagonal.
	# Check actual triangles, not consecutive six-vertex rectangle assumptions.
	# Unique original-face ownership + area + pairwise polygon intersections
	# prove full coverage without accepting overlaps or invented caps.
	var old: Array[Dictionary] = []
	var assigned: Array = []
	for i in range(0,original.size(),6):
		old.append(_rectangle(original,i))
		assigned.append([])
	var valid := true
	var unmatched := 0
	var unmatched_samples: Array = []
	var rendered_triangles := 0
	for path in ["PermanentNavigation/Surface","OccludingCover/Surface"]:
		var visual: MeshInstance3D = passage.shell.get_node(path)
		valid = valid and visual.transform==Transform3D.IDENTITY and visual.get_parent().transform==Transform3D.IDENTITY
		for surface in range(visual.mesh.get_surface_count()):
			var arrays: Array = visual.mesh.surface_get_arrays(surface)
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			# Imported GLB surfaces share indexed vertices. Expand actual render
			# indices before checking the same exact original-face partition.
			var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
			if not indices.is_empty():
				var expanded := PackedVector3Array()
				for index in indices: expanded.append(vertices[index])
				vertices = expanded
			valid = valid and vertices.size()%3==0
			for i in range(0,vertices.size()-2,3):
				var low := vertices[i].min(vertices[i+1]).min(vertices[i+2])
				var high := vertices[i].max(vertices[i+1]).max(vertices[i+2])
				var cross := (vertices[i+1]-vertices[i]).cross(vertices[i+2]-vertices[i])
				var area := cross.length()*0.5
				valid = valid and area>0.00000001
				var owners: Array[int] = []
				for j in range(old.size()):
					var prior: Dictionary = old[j]
					var axis: int = prior.axis
					if absf(low[axis]-prior.plane)>0.000003 or absf(high[axis]-prior.plane)>0.000003 or cross.normalized().dot(prior.normal)<0.9999: continue
					var u: int = prior.u
					var v: int = prior.v
					if low[u]>=prior.low[u]-0.000003 and high[u]<=prior.high[u]+0.000003 and low[v]>=prior.low[v]-0.000003 and high[v]<=prior.high[v]+0.000003: owners.append(j)
				if owners.size()==1:
					var prior: Dictionary = old[owners[0]]
					var polygon := PackedVector2Array()
					for vertex in [vertices[i],vertices[i+1],vertices[i+2]]: polygon.append(Vector2(vertex[prior.u],vertex[prior.v]))
					if Geometry2D.is_polygon_clockwise(polygon): polygon.reverse()
					assigned[owners[0]].append({"area":area,"polygon":polygon})
				else:
					unmatched += 1
					if unmatched_samples.size()<4:
						var nearest := INF
						var prior_match: Dictionary = {}
						for prior in old:
							var axis: int = prior.axis
							if high[axis]-low[axis]>0.001: continue
							var distance: float = absf(low[axis]-prior.plane) + (low-prior.low).length() + (high-prior.high).length()
							if distance<nearest:
								nearest = distance
								prior_match = prior
						unmatched_samples.append({"low":str(low),"high":str(high),"normal":str(cross.normalized()),"nearest":str(prior_match)})
				rendered_triangles += 1
	var coverage := true
	var disjoint := true
	for j in range(old.size()):
		var area := 0.0
		var pieces: Array = assigned[j]
		for a in range(pieces.size()):
			area += float(pieces[a].area)
			for b in range(a+1,pieces.size()):
				for polygon in Geometry2D.intersect_polygons(pieces[a].polygon,pieces[b].polygon):
					var twice_area := 0.0
					for k in range(polygon.size()): twice_area += polygon[k].cross(polygon[(k+1)%polygon.size()])
					if absf(twice_area)>0.000002: disjoint=false
		if absf(area-float(old[j].area))>0.00003: coverage=false
	_check(valid and unmatched==0,"every imported visual triangle remains on exactly one original face with original winding",{"unmatched":unmatched,"rendered_triangles":rendered_triangles,"samples":unmatched_samples})
	_check(coverage and disjoint,"navigation and cover partition every original face once, without holes/overlaps/new caps")
	_check(passage.shell.get_node("PermanentNavigation").get_meta("terrain_visibility_keep",false) and not passage.shell.get_node("OccludingCover").get_meta("terrain_visibility_keep",false),"only navigation subtree is protected from camera fade")

func _test_snapshot_guards() -> void:
	var before: Dictionary = passage.snapshot()
	var pose: Transform3D = passage.gates.front.global_transform
	var malformed: Array = [null,[],{}, {"schema_version":1}]
	for key in Passage.STATE_KEYS:
		var missing: Dictionary = before.duplicate(true)
		missing.erase(key)
		malformed.append(missing)
	for pair in [["phase_usec",-1],["phase_usec",8000000],["phase_usec",0.5],["serial",-1],["serial",INF],["front_fraction",-0.01],["rear_fraction",1.01],["front_fraction",NAN],["latched",1],["front_pinned","false"],["layout_sha256","other"],["schema_version",2]]:
		var bad: Dictionary = before.duplicate(true)
		bad[pair[0]]=pair[1]
		malformed.append(bad)
	var extra: Dictionary = before.duplicate(true)
	extra["unexpected"]=true
	malformed.append(extra)
	for bad in malformed:
		_check(not passage.apply_snapshot(bad).ok and passage.snapshot()==before and passage.gates.front.global_transform==pose,"invalid snapshot atomically preserves state and pose")
	_check(passage.apply_snapshot(before).ok and not passage.apply_snapshot(before).changed and passage.snapshot()==before,"duplicate snapshot is unchanged")
	for delta in [-1.0,INF,NAN,0.251,10.0]:
		_check(not passage.fixed_update(delta,{},bodies).ok and passage.snapshot()==before,"invalid delta cannot advance",{"delta":str(delta)})
	_check(not passage.fixed_update(0.1,{},bodies,false).ok and passage.snapshot()==before,"false authority flag cannot advance")
	_check(passage.fixed_update(0.0,{},bodies).ok and passage.snapshot()==before,"pause zero delta is exactly unchanged")
	_check(not passage.fixed_update(0.1,{Passage.FRONT_ID:{"pinned":true,"field_remaining":INF}},bodies).ok and passage.snapshot()==before,"invalid pin timer is atomic")
	_check(not passage.fixed_update(0.1,{Passage.FRONT_ID:{"pinned":"yes"}},bodies).ok and passage.snapshot()==before,"invalid pin boolean is atomic")
	_check(not passage.fixed_update(0.1,{}, {1:Vector3.ZERO}).ok and passage.snapshot()==before,"player point cannot substitute for collision body")
	_check(not passage.apply_committed({Passage.FLAG:"yes"}).ok and passage.snapshot()==before,"invalid committed flag cannot change geometry")

func _advance(seconds: float, entities: Dictionary = {}) -> bool:
	var remaining := seconds
	var ok := true
	for i in range(400):
		if remaining <= 0.0000001: break
		var delta := minf(0.1,remaining)
		var result: Dictionary = passage.fixed_update(delta,entities,bodies)
		ok = ok and bool(result.ok)
		remaining -= delta
	return ok and remaining <= 0.0000001

func _test_clock_and_pin() -> void:
	_fixture()
	_check(_advance(3.0) and passage.status().phase=="opening","real explicit delta enters opening after warning")
	_check(_advance(1.2) and is_equal_approx(passage.snapshot().front_fraction,1.0),"door fully opens at 4.2 seconds")
	await _settle()
	var target: Dictionary = passage.target_definitions()[0]
	var entities := {"p1":{"id":"p1","owner":"1","tags":["player"],"position":Vector3(-35,2.05,-16.8),"energy":100.0,"health":100.0,"revision":0},Passage.FRONT_ID:target}
	var hit := _ray(entities.p1.position,target.position)
	var los: bool = not hit.is_empty() and hit.collider.get_meta("entity_id","")==Passage.FRONT_ID
	var result: Dictionary = rules.resolve({"actor_id":"p1","ability":"force_field","target_id":Passage.FRONT_ID,"mode":"pin"},entities,{"sender_id":"1","line_of_sight":los})
	_check(result.ok and rules.commit(result,entities).ok,"production force-field rule accepts actual moving-panel LOS",{"los":los,"hit_position":str(hit.get("position")),"hit_collider":str(hit.get("collider")),"target":str(target.position),"gate_transform":str(passage.gates.front.global_transform),"result":result})
	var state: Dictionary = passage.snapshot()
	var input_copy: Dictionary = entities.duplicate(true)
	_check(_advance(0.5,entities) and passage.snapshot().phase_usec==state.phase_usec and passage.snapshot().front_fraction==state.front_fraction and passage.status().phase=="field_hold","authorized pin freezes actual panel and local cycle")
	_check(entities==input_copy,"passage never writes ability timer/owner/energy")
	_check(entities.p1.energy==90.0 and entities[Passage.FRONT_ID].field_remaining==4.0,"pin retains production cost and duration; adapter owns expiry")
	entities[Passage.FRONT_ID].pinned=false
	entities[Passage.FRONT_ID].field_remaining=0.0
	_check(_advance(0.9,entities) and passage.status().phase=="closing_warning" and is_equal_approx(passage.snapshot().front_fraction,1.0),"release resumes cycle with closing warning before motion")
	_check(_advance(1.0,entities) and passage.snapshot().front_fraction>0.999,"one-second closing warning keeps passage open")
	_check(_advance(1.2,entities) and passage.snapshot().front_fraction<0.001,"real closing motion returns closed")
	_check(_advance(0.7,entities) and passage.snapshot().phase_usec==0,"cycle wraps at exactly eight active seconds")
	var restored: Variant = JSON.parse_string(JSON.stringify(passage.snapshot(),"",true,true))
	_check(passage.apply_snapshot(restored).ok and passage.snapshot().phase_usec==0,"JSON-safe snapshot round trip")

func _clear(id: int) -> bool:
	var body: PhysicsBody3D = bodies[id]
	var shape_node: CollisionShape3D = body.get_node("Envelope")
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = shape_node.shape
	query.transform = shape_node.global_transform
	query.collision_mask = 1|8
	query.exclude = [body.get_rid()]
	query.margin = 0.0
	return world.get_world_3d().direct_space_state.intersect_shape(query,1).is_empty()

func _travel(id: int, from: Vector3, to: Vector3, label: String) -> void:
	await _place(id,from)
	var clear := _clear(id)
	var body: PhysicsBody3D = bodies[id]
	var hit: KinematicCollision3D = body.move_and_collide(to-from)
	_check(clear and hit==null and body.global_position.distance_to(to)<0.005,"full production envelope travels " + label,{"initial_clear":clear,"position":str(body.global_position),"collider":str(hit.get_collider()) if hit else ""})
	await _settle()
	_check(_clear(id),"route destination clear: " + label)

func _test_routes() -> void:
	await _park()
	for id in bodies:
		var body = bodies[id]
		var frame: String = body.build.airframe_id
		_fixture()
		await _place(id,Vector3(-35,2.05,-16.8))
		_check(_clear(id),frame+" closed-grille approach is clear")
		var hit: KinematicCollision3D = body.move_and_collide(Vector3(0,0,-5))
		_check(hit!=null and hit.get_collider()==passage.gates.front and body.global_position.z > -18.5,frame+" real closed solid grille blocks full body")
		await _place(id,Vector3(-35,2.05,-16.8))
		var query := PhysicsShapeQueryParameters3D.new()
		query.shape = body.get_node("Envelope").shape
		query.transform = body.global_transform
		query.collision_mask = 1|8
		query.exclude = [body.get_rid()]
		query.motion = Vector3(0,0,-6)
		var sweep: PackedFloat32Array = world.get_world_3d().direct_space_state.cast_motion(query)
		_check(sweep.size()==2 and sweep[0]<0.999,frame+" six-metre blink sweep cannot cross closed grille")
		var entities := {"p1":{"id":"p1","owner":"1","tags":["player"],"position":body.global_position,"energy":100.0,"health":100.0,"revision":0}}
		var blink: Dictionary = rules.resolve({"actor_id":"p1","ability":"blink","point":body.global_position+query.motion},entities,{"sender_id":"1"})
		_check(blink.ok and not rules.commit(blink,entities,false).ok and entities.p1.energy==100.0,frame+" blocked physical approval spends no ability energy")
		await _place(id,Vector3(-49,10+int(id)*3,-44))
		_fixture(4200000,1.0)
		await _travel(id,Vector3(-35,2.05,-16.8),Vector3(-35,2.05,-26),frame+" open front and main corridor")
		_fixture()
		await _travel(id,Vector3(-25.5,3.55,-23.5),Vector3(-31.5,3.55,-23.5),frame+" high side duct (six-metre continuous route)")
		await _travel(id,Vector3(-31.5,3.55,-23.5),Vector3(-35,3.55,-23.5),frame+" upper turning chamber")
		await _travel(id,Vector3(-35,3.55,-23.5),Vector3(-35,2.05,-23.5),frame+" chamber descent")
		await _travel(id,Vector3(-35,2.05,-23.5),Vector3(-35,3.55,-23.5),frame+" failure escape ascend")
		await _travel(id,Vector3(-35,3.55,-23.5),Vector3(-25,3.55,-23.5),frame+" failure escape through always-open side window")
		_fixture(0,1.0,1.0,true)
		await _travel(id,Vector3(-35,2.05,-16.8),Vector3(-35,2.05,-37.2),frame+" committed complete north-south route")
		await _place(id,Vector3(-49,10+int(id)*3,-44))

func _test_pinch() -> void:
	await _park()
	for id in bodies:
		var frame: String = bodies[id].build.airframe_id
		_fixture(6100000,1.0)
		# Centre lies outside the current blade. Its wing/envelope reaches into the
		# next swept strip: a centre-point-only obstruction test would miss this.
		await _place(id,Vector3(-35.0,2.05,-18.5),0.22)
		var initially_clear := _clear(id)
		var blocked := false
		for i in range(25):
			var advanced: Dictionary = passage.fixed_update(0.05,{},bodies)
			if not advanced.ok: _check(false,"pinch update rejected",advanced); break
			if passage.snapshot().front_obstructed: blocked=true; break
		_check(initially_clear and blocked and passage.snapshot().front_fraction>0.0 and _clear(id),frame+" closing sweep stops at actual rotated envelope without penetration",{"initial_clear":initially_clear,"state":passage.snapshot(),"body":str(bodies[id].global_transform)})
		var held: Dictionary = passage.snapshot()
		_check(passage.fixed_update(0.0,{},bodies).ok and passage.snapshot()==held,frame+" zero-delta refresh does not erase obstruction")
		_check(_advance(0.4) and passage.snapshot().front_fraction==held.front_fraction and _clear(id),frame+" repeated closing attempts never squeeze occupied body")
		await _place(id,Vector3(-35,2.05,-16.0))
		_check(_advance(2.0) and passage.snapshot().front_fraction<0.001,frame+" closure resumes after body leaves")
		await _place(id,Vector3(-49,10+int(id)*3,-44))
	# Opening also sweeps: a player standing in front of the parking recess is not
	# crushed when a released shutter retracts sideways.
	_fixture()
	await _place(2,Vector3(-31.5,2.05,-17.7))
	var initial := _clear(2)
	_check(passage.apply_committed({Passage.FLAG:true}).ok,"live committed flag requests safe opening")
	_check(_advance(2.0) and passage.snapshot().front_obstructed and _clear(2) and initial,"opening sweep also protects player at parking recess")
	await _park()
	_check(_advance(2.0) and passage.snapshot().front_fraction>0.999 and passage.snapshot().rear_fraction>0.999,"committed opening completes once both swept volumes clear")

func _test_committed_and_client() -> void:
	var fresh := Passage.new()
	_check(fresh.load_layout(true,{Passage.FLAG:true}).ok,"saved committed flag accepted before tree")
	_check(fresh.snapshot().front_fraction==1.0 and fresh.snapshot().rear_fraction==1.0,"saved latch restores both open before first frame")
	_check(fresh.gates.front.position.is_equal_approx(Vector3(4.2,2.05,8.5)) and fresh.gates.rear.position.is_equal_approx(Vector3(-4.2,2.05,-8.5)),"saved open actual local poses are set before tree")
	fresh.free()
	var client := Passage.new()
	_check(client.load_layout(false).ok,"client view builds")
	client.position.x += 150
	world.add_child(client)
	var host_state: Dictionary = passage.snapshot()
	_check(client.apply_snapshot(host_state).ok,"client accepts validated host state")
	_check_immediate_panel_poses(client, "first open snapshot")
	var before: Dictionary = client.snapshot()
	_check(not client.fixed_update(0.2,{},{}).ok and client.snapshot()==before,"client cannot advance even with default authority argument")
	_check(not client.apply_committed({Passage.FLAG:false}).ok and client.snapshot()==before,"client cannot directly alter persistent latch")
	_check(not client.apply_snapshot(host_state).changed and client.snapshot()==before,"repeated view snapshot leaves state unchanged")
	_fixture(3500000,0.4166666666666667)
	var fractional: Dictionary = passage.snapshot()
	var encoded := JSON.stringify(fractional,"",true,true)
	_check(client.apply_snapshot(JSON.parse_string(encoded)).ok and client.snapshot()==fractional,"fractional active-phase snapshot round trip preserves exact state")
	_check_immediate_panel_poses(client, "same-frame fractional snapshot")
	var closed: Dictionary = fractional.duplicate(true)
	closed.phase_usec = 0
	closed.front_fraction = 0.0
	closed.rear_fraction = 0.0
	closed.latched = false
	_check(client.apply_snapshot(closed).ok, "same-frame closed snapshot accepted")
	_check_immediate_panel_poses(client, "same-frame closed snapshot")
	var clone := Passage.new()
	_check(clone.load_layout(true).ok,"fresh authority restore instance builds")
	clone.position.x += 300
	world.add_child(clone)
	_check(clone.apply_snapshot(JSON.parse_string(encoded)).ok,"fresh authority restores active phase")
	var replay_ok := true
	for delta in [0.017,0.12,0.003,0.25,0.1]:
		replay_ok = replay_ok and passage.fixed_update(delta,{},bodies).ok and clone.fixed_update(delta,{},{}).ok
	_check(replay_ok and passage.snapshot()==clone.snapshot(),"saved phase replay matches uninterrupted host under equal explicit deltas")
	client.queue_free()
	clone.queue_free()
	await _settle()

func _check_immediate_panel_poses(view: Node3D, label: String) -> void:
	# No await: paused/newly connected guests need usable collision immediately.
	for side in ["front", "rear"]:
		var panel: PhysicsBody3D = view.gates[side]
		var actual: Transform3D = PhysicsServer3D.body_get_state(panel.get_rid(), PhysicsServer3D.BODY_STATE_TRANSFORM)
		_check(actual.is_equal_approx(panel.global_transform), label + " " + side + " PhysicsServer pose matches node immediately", {"actual":str(actual.origin), "expected":str(panel.global_position)})
		var outside := Vector3(0, 0, 0.8 if side == "front" else -0.8)
		var query := PhysicsRayQueryParameters3D.create(panel.global_position + outside, panel.global_position, 1)
		var hit: Dictionary = view.get_world_3d().direct_space_state.intersect_ray(query)
		_check(not hit.is_empty() and hit.collider == panel, label + " " + side + " same-frame ray hits actual published panel")

func _finish() -> void:
	if is_instance_valid(world): world.queue_free()
	await process_frame
	done = true
	print("UNDERDECK_PASSAGE_RESULT " + JSON.stringify({"checks":checks,"failures":failures,"scope":"independent real PhysicsServer module; no action/Session integration, graphics, LAN, performance or human-play claim"}))
	quit(0 if failures.is_empty() else 1)
