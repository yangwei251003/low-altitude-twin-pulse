extends SceneTree
## Real production Session + SceneTree/PhysicsServer regression.
## New isolated QA profile only. Scripted placements/sweeps are fixtures, not
## propulsion, human handling, screenshots, GPU/performance or network evidence.
## Run: Godot --headless --path . --script res://tests_v3/test_shore_world.gd --
##      --qa-profile=qa_shore_<unique>
const Session = preload("res://scripts/v3/twin_session.gd")
const Catalog = preload("res://scripts/v2/catalog.gd")
const Ground = preload("res://scripts/v3/art/twin_ground_surface.gd")
const Store = preload("res://scripts/v3/core/twin_world_store.gd")
class FaultSession:
	extends Session
	var reject_preparation := false
	var last_prepared_world
	func _prepare_region(id: String, destination_world: Dictionary = {}) -> Dictionary:
		if reject_preparation: return {"ok":false,"error":"QA injected preparation rejection; source files untouched"}
		var prepared: Dictionary = super._prepare_region(id, destination_world)
		last_prepared_world = prepared.get("world")
		return prepared
var session
var checks: Array = []
var failures: Array = []
var profile := ""
var done := false
var i1_water: ShaderMaterial
var i1_ground: ShaderMaterial
var i1_phase := 0.0

func _init() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--qa-profile="): profile = arg.trim_prefix("--qa-profile=")
		if arg.begins_with("--qa-network="):
			push_error("Shore integration must not open network mode")
			quit(2)
			return
	if not profile.begins_with("qa_shore_") or profile != profile.validate_filename() or DirAccess.dir_exists_absolute("user://profiles_v3/" + profile):
		push_error("Requires a never-used --qa-profile=qa_shore_<unique>")
		quit(2)
		return
	_run.call_deferred()

func _check(ok: bool, label: String, detail: Dictionary = {}) -> void:
	checks.append({"passed":ok,"name":label})
	if not ok:
		failures.append({"name":label,"detail":detail})
		push_error("SHORE_WORLD " + label + " " + JSON.stringify(detail))

func _settle() -> void:
	await physics_frame
	await physics_frame
	await process_frame

func _freeze() -> void:
	session.set_process(false)
	session.set_physics_process(false)
	session.inputs.set_process(false)
	session.inputs.set_physics_process(false)
	for body in session.players.values():
		body.freeze = true
		body.set_process(false)
		body.set_physics_process(false)
		body.linear_velocity = Vector3.ZERO
		body.angular_velocity = Vector3.ZERO
	for object in session.world.objects.values():
		if object is RigidBody3D: object.freeze = true

func _place(at: Vector3) -> void:
	var body = session.players[1]
	body.global_transform = Transform3D(Basis.IDENTITY, at)
	body.hold_height = at.y
	body.linear_velocity = Vector3.ZERO
	body.angular_velocity = Vector3.ZERO
	session.entities["player:1"].position = at
	await _settle()

func _ray(from: Vector3, to: Vector3, mask: int = 1, more_excluded: Array[RID] = []) -> Dictionary:
	var query := PhysicsRayQueryParameters3D.create(from,to,mask)
	var excluded: Array[RID] = [session.players[1].get_rid()]
	excluded.append_array(more_excluded)
	query.exclude = excluded
	query.hit_back_faces = true
	return session.get_world_3d().direct_space_state.intersect_ray(query)

func _identity(hit: Dictionary) -> String:
	return str(hit.collider.get_meta("entity_id","")) if not hit.is_empty() else ""

func _sweep(from: Vector3, to: Vector3, label: String) -> void:
	await _place(from)
	var body = session.players[1]
	var initial: Array = []
	for child in body.get_children():
		if not child is CollisionShape3D or child.disabled: continue
		var query := PhysicsShapeQueryParameters3D.new()
		query.shape = child.shape
		query.transform = child.global_transform
		query.collision_mask = body.collision_mask
		query.exclude = [body.get_rid()]
		query.margin = 0.001
		initial.append_array(session.get_world_3d().direct_space_state.intersect_shape(query,4))
	var hit = body.move_and_collide(to-from)
	_check(initial.is_empty() and hit == null and body.global_position.distance_to(to)<0.02,label,{
		"initial_overlap_count":initial.size(),"end":str(body.global_position),
		"collider":str(hit.get_collider().get_path()) if hit != null else ""})

func _run() -> void:
	create_timer(45).timeout.connect(func():
		if not done:
			push_error("SHORE_WORLD timed out; no pass is implied")
			quit(2))
	session = FaultSession.new()
	root.add_child(session)
	_check(session.profile_ready, "fresh isolated production profile opened")
	if not session.profile_ready: await _finish(); return
	_check(session.start_flight("solo"), "production session starts without ENet")
	if not session.active: await _finish(); return
	_freeze()
	await _settle()
	i1_water = Ground.water_material("I1")
	i1_ground = Ground.material_for("I1",-1)
	i1_phase = float(i1_water.get_shader_parameter("wind_phase"))
	_check(int(i1_water.get_shader_parameter("shore_profile_count"))==0 and int(i1_ground.get_shader_parameter("shore_profile_count"))==0,"I1 starts with independent straight-shore material")
	var old_world = session.world
	_check(session._load_region("F1"), "F1 candidate succeeds via new bool load contract")
	_freeze()
	await _settle()
	_check(not is_instance_valid(old_world), "successful load frees prior I1 world instead of leaving hidden collision")
	if session.region_id != "F1": await _finish(); return
	_check(session.world.build_errors.is_empty() and session.world.shore_layout!=null,"F1 exposes validated shore layout")
	_test_structure_and_materials()
	await _test_water_bed_banks()
	await _test_foundations()
	await _test_routes()
	await _test_optics_growth()
	await _test_return_isolation()
	await _test_region_failure_transactions()
	await _finish()

func _test_structure_and_materials() -> void:
	var world = session.world
	var water_node = world.get_node_or_null("Shore_water")
	_check(water_node!=null and water_node.find_children("*","CollisionObject3D",true,false).is_empty(),"F1 water surface has no physics body")
	var stale_boxes: Array = []
	for node in world.find_children("*","CollisionShape3D",true,false):
		if not node.shape is BoxShape3D: continue
		for size in [Vector3(44,1.2,100),Vector3(44,3,100),Vector3(125,1,125)]:
			if node.shape.size.is_equal_approx(size): stale_boxes.append(str(node.get_path()))
	_check(stale_boxes.is_empty(),"old enormous F1 shore/water boxes are absent, including hidden colliders",{"found":stale_boxes})
	for part in world.shore_layout.part_ids():
		var holder = world.get_node_or_null("Shore_"+str(part).replace(":","_"))
		_check(holder!=null and holder.get_meta("terrain_stage","")=="replaceable_graybox",str(part)+" is explicitly removable graybox")
		if holder==null: continue
		var mesh: ArrayMesh = holder.get_node("Surface").mesh
		var faces: PackedVector3Array = mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
		var shapes = holder.find_children("*","CollisionShape3D",true,false)
		if part=="water":
			_check(shapes.is_empty(),"rendered water has no generated surface collider")
		else:
			_check(shapes.size()==1 and shapes[0].shape is ConcavePolygonShape3D and shapes[0].shape.get_faces()==faces,str(part)+" live collider is exactly the rendered triangle list")
	var f_water: ShaderMaterial = water_node.get_node("Surface").material_override
	var left: ShaderMaterial = world.get_node("Shore_west/Surface").material_override
	var right: ShaderMaterial = world.get_node("Shore_east/Surface").material_override
	var data: Dictionary = world.shore_layout.shader_data()
	_check(f_water!=i1_water and left!=i1_ground and left!=right,"F1 water and side materials are independent from I1 and each other")
	for material in [f_water,left,right]:
		var points: PackedVector4Array = material.get_shader_parameter("shore_profile")
		_check(int(material.get_shader_parameter("shore_profile_count"))==data.count and points.size()==32 and points.slice(0,data.count)==data.water_points,"actual material receives same 21 water-edge rows as geometry")
	world.clock_seconds = 123.25
	world.synchronize(session.entities,0.0)
	_freeze()
	_check(is_equal_approx(float(f_water.get_shader_parameter("wind_phase")),123.25) and is_equal_approx(float(i1_water.get_shader_parameter("wind_phase")),i1_phase),"F1 wind phase cannot mutate cached I1 water")
	_check(int(i1_water.get_shader_parameter("shore_profile_count"))==0 and int(i1_ground.get_shader_parameter("shore_profile_count"))==0,"F1 shore configuration leaves I1 uniforms untouched")
	var compared := 0
	var disagreements := 0
	for z in [-45.0,-14.0,2.0,12.0,25.0,38.0,42.0]:
		var edge: Dictionary = world.shore_layout.bank_edges(z)
		for x in [float(edge.left_water)-0.2,float(edge.left_water)+0.2,0.0,float(edge.right_water)-0.2,float(edge.right_water)+0.2]:
			compared += 1
			if world.sample_environment(Vector3(x,-2.5,z)).water != world.shore_layout.is_water_xz(x,z): disagreements += 1
	_check(compared==35 and disagreements==0,"live environment water query matches curved shore and foundation exclusions")

func _test_water_bed_banks() -> void:
	for p in [Vector2(0,42),Vector2(-9,42),Vector2(-10,2),Vector2(10,-14)]:
		var hit := _ray(Vector3(p.x,-1.5,p.y),Vector3(p.x,-4,p.y))
		_check(not hit.is_empty() and _identity(hit)=="terrain:bed" and absf(hit.position.y+3.2)<0.002,"actual ray crosses water and first hits bed at "+str(p),{"hit":_identity(hit),"position":str(hit.get("position"))})
		_check(session.world.sample_environment(Vector3(p.x,-2.5,p.y)).water,"new curved water column recognized at "+str(p))
	_check(not session.world.sample_environment(Vector3(-20,-2.5,42)).water and not session.world.sample_environment(Vector3(30,-2.5,42)).water,"dry bank positions are not water")
	for side in [-1,1]:
		var edge: Dictionary = session.world.shore_layout.bank_edges(42)
		var x := (float(edge.left_top)+float(edge.left_water))*.5 if side<0 else (float(edge.right_top)+float(edge.right_water))*.5
		var expected: float = session.world.shore_layout.bank_height(x,42)
		var hit := _ray(Vector3(x,4,42),Vector3(x,-4,42))
		_check(not hit.is_empty() and _identity(hit)==("terrain:west" if side<0 else "terrain:east") and absf(hit.position.y-expected)<0.002,"sloped bank ray agrees with authored profile side "+str(side),{"expected_y":expected,"hit":_identity(hit),"position":str(hit.get("position"))})
	for entry in [[Vector2(-45,42),0.0,"terrain:west"],[Vector2(45,42),2.4,"terrain:east"]]:
		var p: Vector2=entry[0]
		var hit := _ray(Vector3(p.x,5,p.y),Vector3(p.x,-4,p.y))
		_check(not hit.is_empty() and _identity(hit)==entry[2] and absf(hit.position.y-float(entry[1]))<0.002,"retained dry top plane "+str(entry[2]))
	# Different from the old abs(X)<8 environmental approximation.
	_check(session.world.sample_environment(Vector3(-10,0,2)).water and session.world.sample_environment(Vector3(10,0,-14)).water,"water classification actually bends outside old +/-8 channel")

func _test_foundations() -> void:
	var excluded: Array[RID] = []
	for body in session.world.crown_arena.find_children("*","CollisionObject3D",true,false): excluded.append(body.get_rid())
	excluded.append(session.world.gate.get_rid())
	for foundation in session.world.shore_layout.definition().foundations:
		var chosen: Array = []
		var largest := 0.0
		for tri in foundation.top_triangles_xz:
			var a := Vector2(tri[0][0],tri[0][1])
			var b := Vector2(tri[1][0],tri[1][1])
			var c := Vector2(tri[2][0],tri[2][1])
			var area := absf((b-a).cross(c-a))
			if area>largest: largest=area; chosen=tri
		var p := (Vector2(chosen[0][0],chosen[0][1])+Vector2(chosen[1][0],chosen[1][1])+Vector2(chosen[2][0],chosen[2][1]))/3.0
		var top_y: float=foundation.top_y
		var hit := _ray(Vector3(p.x,top_y+.1,p.y),Vector3(p.x,top_y-.2,p.y),1,excluded)
		_check(not hit.is_empty() and _identity(hit)=="terrain:foundation:"+str(foundation.id) and absf(hit.position.y-top_y)<0.002,str(foundation.id)+" actual foundation cap supports its authored top (upper bodies excluded only for attribution)",{"hit":_identity(hit),"position":str(hit.get("position"))})
		_check(not session.world.sample_environment(Vector3(p.x,-2.5,p.y)).water,str(foundation.id)+" excludes water through the same real footprint")

func _test_routes() -> void:
	for frame in ["tr01","hx02"]:
		session.players[1].configure(Catalog.resolve_build(Catalog.default_build(frame)))
		_freeze()
		await _settle()
		for path in [
			[Vector3(0,3.25,-16),Vector3(0,3.25,4),"root underpass"],
			[Vector3(-35,1.4,-18),Vector3(-35,1.4,-6),"west real cave"],
			[Vector3(35,3.8,-19),Vector3(35,3.8,-7),"east real cave"],
			# This reach remains beyond the old x=-8 shore, with clearance for
			# the complete wide-frame extent across its entire Z interval.
			[Vector3(-9,-2.35,0),Vector3(-9,-2.35,4),"new water reach"]
		]:
			await _sweep(path[0],path[1],frame+" forward "+path[2])
			await _sweep(path[1],path[0],frame+" reverse "+path[2])
		for degrees in [0,30,90]:
			session.entities["F1:mirror"].angle=deg_to_rad(float(degrees))
			session.world.initialize_mechanisms(session.entities)
			_freeze()
			await _settle()
			_check(is_equal_approx(session.world.rotor_angle,deg_to_rad(float(degrees))),frame+" ring physics pose "+str(degrees))
			await _sweep(Vector3(-24,5.2,28.8),Vector3(-24,5.2,21.2),frame+" ring forward "+str(degrees))
			await _sweep(Vector3(-24,5.2,21.2),Vector3(-24,5.2,28.8),frame+" ring reverse "+str(degrees))
		await _place(Vector3(0,-1.4,42))
		var hit = session.players[1].move_and_collide(Vector3(0,-3,0))
		_check(hit!=null and str(hit.get_collider().get_meta("entity_id",""))=="terrain:bed" and session.players[1].position.y < -2.2,frame+" full body passes visual water then lands on solid riverbed",{"end":str(session.players[1].position),"collider":str(hit.get_collider().get_path()) if hit else ""})
		await _place(Vector3(0,-2.35,42))
		var bank_hit = session.players[1].move_and_collide(Vector3(-15,0,0))
		var edge: Dictionary = session.world.shore_layout.bank_edges(42)
		_check(bank_hit!=null and str(bank_hit.get_collider().get_meta("entity_id",""))=="terrain:west" and session.players[1].position.x > float(edge.left_water),frame+" full body correctly stops at curved bank even while its center is in water",{"end":str(session.players[1].position),"edge":edge.left_water})

func _cast(ability: String,target: String) -> void:
	session.cooldowns[1]=0.0
	session.entities["player:1"].energy=100.0
	session._action_received(1,"ability",{"ability":ability,"target_id":target,"point":Vector3.ZERO,"mode":""})

func _test_optics_growth() -> void:
	session.players[1].configure(Catalog.resolve_build(Catalog.default_build("tr01")))
	session.entities["F1:mirror"].angle=-PI/3.0
	session.entities["F1:mirror"].light_level=0.0
	session.entities["F1:growth"].growth=0.0
	session.world.initialize_mechanisms(session.entities)
	_freeze()
	await _place(Vector3(-24,5.2,30))
	var used: int=session.stats.abilities
	_cast("light","F1:mirror")
	_cast("light","F1:mirror")
	session.world.synchronize(session.entities,1.0)
	_freeze()
	await _settle()
	session.world.synchronize(session.entities,0.0)
	_freeze()
	var temple=session.world.art_temple
	var hit := _ray(temple.light_origin(),temple.light_endpoint(),1|8)
	_check(session.stats.abilities==used+2 and is_zero_approx(session.world.rotor_angle),"two real light actions align ring after curved terrain replacement")
	_check(not hit.is_empty() and hit.collider==session.world.objects["F1:growth"] and float(session.entities["F1:growth"].environment_light)==1.0,"real optical first-hit reaches intended root receiver without terrain obstruction",{"hit":_identity(hit)})
	var before := _ray(Vector3(0,8,25),Vector3(0,4,25))
	_check(before.is_empty(),"ungrown bridge has no collider above retained lower walkway")
	await _place(Vector3(-16,5.2,30.35))
	used=session.stats.abilities
	_cast("growth","F1:growth")
	_cast("growth","F1:growth")
	session.world.synchronize(session.entities,0.0)
	_freeze()
	await _settle()
	var grown := _ray(Vector3(0,8,25),Vector3(0,4,25))
	_check(session.stats.abilities==used+2 and session.world.growth_bridge.collision_layer==1,"real light-growth route still creates bridge")
	_check(not grown.is_empty() and grown.collider==session.world.growth_bridge and absf(grown.position.y-5.25)<0.002,"grown bridge remains real authoritative collision, not part of new static terrain")

func _test_return_isolation() -> void:
	var f1_water: ShaderMaterial=Ground.water_material("F1")
	var f1_phase: float=f1_water.get_shader_parameter("wind_phase")
	_check(session._load_region("I1"),"return F1 to I1 succeeds")
	_freeze()
	await _settle()
	_check(session.world.shore_layout==null and session.world.get_node_or_null("Shore_water")==null,"I1 does not inherit F1 terrain geometry")
	_check(Ground.water_material("I1")==i1_water and Ground.material_for("I1",-1)==i1_ground,"I1 returns to its own cached materials")
	_check(int(i1_water.get_shader_parameter("shore_profile_count"))==0 and int(f1_water.get_shader_parameter("shore_profile_count"))==21,"region re-entry preserves independent profile uniforms")
	_check(not session.world.sample_environment(Vector3(-10,0,2)).water and session.world.sample_environment(Vector3(0,0,42)).water,"I1 environmental water behavior unchanged")
	session.world.clock_seconds=14.5
	session.world.synchronize(session.entities,0.0)
	_freeze()
	_check(is_equal_approx(float(f1_water.get_shader_parameter("wind_phase")),f1_phase),"returning I1 cannot advance F1 cached water phase")

func _same(left, right) -> bool:
	return JSON.parse_string(JSON.stringify(left))==JSON.parse_string(JSON.stringify(right))

func _durable_same(expected: Dictionary) -> bool:
	var reader = Store.new(session.store.root_path)
	return reader.load_profile().ok and _same(reader.snapshot(),expected)

func _world_count() -> int:
	var count := 0
	for child in session.get_children():
		if child is TwinTestWorld: count += 1
	return count

func _test_region_failure_transactions() -> void:
	# Fixture: direct ready consensus isolates the region transaction, without
	# claiming to exercise gate/story travel admission. Only the test subclass
	# rejects prepare; published GLBs, hashes and production code stay untouched.
	_check(session.store.fork_branch("shore_saved_i1","Shore failure fixture",false).ok,"create isolated I1 branch fixture")
	session.world_cache=session.store.snapshot()
	session.consensus.configure([1],int(session.world_cache.world_revision))
	var before: Dictionary=session.store.snapshot()
	var original=session.world
	var actor=session.players[1]
	var at: Vector3=actor.position
	var proposal: Dictionary=session.consensus.propose("region_change",{"region_id":"F1"},1)
	_check(proposal.ok and proposal.ready,"fixture creates ready travel decision")
	session.reject_preparation=true
	session._resolve_ready()
	_check(session.active and session.owns_world and session.network.mode=="solo" and session.world==original and session.players[1]==actor and actor.position==at,"prepare failure keeps current session/world/player live and unmoved")
	_check(_same(session.store.snapshot(),before) and _durable_same(before),"prepare failure changes neither memory nor published save")
	_check(session.consensus.current_proposal().get("proposal_id")==proposal.proposal_id and session.consensus.current_proposal().get("state")=="ready" and not session._resolving_decision,"prepare failure leaves same ready proposal retryable")
	_check(_world_count()==1,"prepare rejection leaks no candidate scene")
	session.reject_preparation=false
	session.store.failure_point="before_publish"
	session._resolve_ready()
	var rejected_candidate=session.last_prepared_world
	_check(is_instance_valid(rejected_candidate) and rejected_candidate!=original and not rejected_candidate.is_inside_tree(),"travel save failure immediately detaches successfully built candidate")
	_check(session.active and session.world==original and session.region_id=="I1" and _same(session.store.snapshot(),before) and _durable_same(before),"travel publish failure preserves live region and durable save")
	_check(session.consensus.current_proposal().get("proposal_id")==proposal.proposal_id and not session._resolving_decision,"travel publish failure keeps ready decision retryable")
	await _settle()
	_check(not is_instance_valid(rejected_candidate) and _world_count()==1,"discarded travel candidate is freed after frame, without duplicate physics world")
	session.store.failure_point=""
	session._resolve_ready()
	_freeze()
	await _settle()
	_check(session.region_id=="F1" and session.store.snapshot().world.region_id=="F1" and session.active and session.consensus.current_proposal().is_empty(),"same ready travel commits and adopts successfully after repair")
	_check(int(session.store.snapshot().generation)==int(before.generation)+1 and not is_instance_valid(original) and _world_count()==1,"retry publishes once and frees previous world")
	before=session.store.snapshot()
	original=session.world
	session.reject_preparation=true
	session._ui_action("branch",{"id":"shore_saved_i1"})
	_check(session.active and session.world==original and session.region_id=="F1" and _same(session.store.snapshot(),before) and _durable_same(before),"branch prepare failure keeps previous branch, live world and disk unchanged")
	_check(_world_count()==1,"branch prepare failure leaves no candidate")
	session.reject_preparation=false
	# Make environment dirty to exercise the save-before-switch failure edge.
	session.entities["F1:relay"].charge=3.0
	session.store.failure_point="before_publish"
	session._ui_action("branch",{"id":"shore_saved_i1"})
	rejected_candidate=session.last_prepared_world
	_check(is_instance_valid(rejected_candidate) and not rejected_candidate.is_inside_tree(),"branch environment-save failure detaches prepared target")
	_check(session.world==original and session.active and _same(session.store.snapshot(),before) and _durable_same(before),"branch environment-save failure does not switch branch or discard live world")
	await _settle()
	_check(not is_instance_valid(rejected_candidate) and _world_count()==1,"branch environment-save candidate is actually freed")
	session.store.failure_point=""
	_check(session._save_environment(),"fixture flushes current environment before isolated switch failure")
	before=session.store.snapshot()
	session.store.failure_point="before_publish"
	session._ui_action("branch",{"id":"shore_saved_i1"})
	rejected_candidate=session.last_prepared_world
	_check(is_instance_valid(rejected_candidate) and not rejected_candidate.is_inside_tree() and session.world==original and session.active,"branch switch-publish failure discards candidate and preserves live world")
	_check(_same(session.store.snapshot(),before) and _durable_same(before),"branch switch-publish failure keeps exact durable branch state")
	await _settle()
	_check(not is_instance_valid(rejected_candidate) and _world_count()==1,"failed switch candidate is freed")
	session.store.failure_point=""
	session._ui_action("branch",{"id":"shore_saved_i1"})
	_freeze()
	await _settle()
	_check(session.active and session.region_id=="I1" and session.store.snapshot().world.branch_id=="shore_saved_i1" and session.store.snapshot().world.region_id=="I1" and _world_count()==1,"branch retry adopts matching saved region and branch")

func _finish() -> void:
	done=true
	print("V3_SHORE_WORLD_CONTRACT "+JSON.stringify({"checks":checks.size(),"failures":failures,"profile":profile,
		"scope":"Real Session and PhysicsServer rays, initial overlaps and production-body scripted sweeps; no propulsion/human/GPU/performance/network acceptance."}))
	if is_instance_valid(session):
		session.network.close()
		session.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)

