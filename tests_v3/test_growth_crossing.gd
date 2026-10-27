extends SceneTree
## Real production Session / PhysicsServer / Store regression, not rendered art,
## propulsion-control, human handling, performance, or LAN acceptance.
## Fixtures: frozen production bodies moved through real collisions; replenished
## ability energy/cooldowns; ten historical reducer events; explicit growth revoke.
## Run: Godot --headless --path . --script res://tests_v3/test_growth_crossing.gd --
##      --qa-profile=qa_growth_<never-used-unique>
const Session = preload("res://scripts/v3/twin_session.gd")
const Catalog = preload("res://scripts/v2/catalog.gd")
const Director = preload("res://scripts/v3/gameplay/actions/twin_action_director.gd")
const Store = preload("res://scripts/v3/core/twin_world_store.gd")
const PREFIX_EVENTS := [
	["talk", "npc:linlan", "rescue_brief", "I1"],
	["fact", "I1:rescue_channel", "charge", "I1"],
	["reach", "I1:rescue_pocket", "", "I1"],
	["reach", "I1:rescue_exit", "", "I1"],
	["inspect", "I1:burn_trace", "", "I1"],
	["talk", "npc:ruanheng", "reverse_flow", "I1"],
	["inspect", "I1:energy_ledger", "", "I1"],
	["inspect", "I1:beacon_echo", "", "I1"],
	["talk", "npc:atai", "needs", "F1"],
	["inspect", "F1:dry_nursery", "", "F1"]
]
const WEST_JOIN := [[23.5,2.925269127],[24.0,4.129740238],[25.0,4.070995331],[26.0,4.065418243],[26.5,4.081121445]]
var session
var profile := ""
var checks: Array = []
var failures: Array = []
var stage := "setup"
var done := false
var gate_diagnostics: Array = []
var last_gate_ticks: Array = []

func _init() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--qa-profile="): profile=arg.trim_prefix("--qa-profile=")
		if arg.begins_with("--qa-network="):
			push_error("Growth crossing regression does not open network QA mode")
			quit(2)
			return
	if not profile.begins_with("qa_growth_") or profile.length()<=10 or profile!=profile.validate_filename() or profile.contains("..") or DirAccess.dir_exists_absolute("user://profiles_v3/"+profile):
		push_error("Use a never-used --qa-profile=qa_growth_<unique>")
		quit(2)
		return
	_run.call_deferred()

func _check(ok: bool, label: String, details: Dictionary = {}) -> void:
	checks.append({"stage":stage,"name":label,"passed":ok})
	if not ok:
		failures.append({"stage":stage,"name":label,"details":details})
		push_error("GROWTH_CROSSING "+label+" "+JSON.stringify(details))

func _settle() -> void:
	await physics_frame
	await physics_frame
	await process_frame

func _freeze() -> void:
	session.set_process(false)
	session.set_physics_process(false)
	session.inputs.set_process(false)
	session.inputs.set_physics_process(false)
	session.interface.clear_dialogue()
	for body in session.players.values():
		body.freeze=true
		body.set_process(false)
		body.set_physics_process(false)
		body.linear_velocity=Vector3.ZERO
		body.angular_velocity=Vector3.ZERO
	for body in session.world.objects.values():
		if body is RigidBody3D: body.freeze=true

func _place(at: Vector3) -> void:
	var body=session.players[1]
	body.global_transform=Transform3D(Basis.IDENTITY,at)
	body.linear_velocity=Vector3.ZERO
	body.angular_velocity=Vector3.ZERO
	body.hold_height=at.y
	session.entities["player:1"].position=at
	await _settle()

func _ray(a: Vector3,b: Vector3,excluded: Array[RID] = [],mask: int = 1) -> Dictionary:
	var query:=PhysicsRayQueryParameters3D.create(a,b,mask)
	var rids: Array[RID]=[session.players[1].get_rid()]
	rids.append_array(excluded)
	query.exclude=rids
	query.hit_back_faces=true
	return session.get_world_3d().direct_space_state.intersect_ray(query)

func _id(hit: Dictionary) -> String:
	return str(hit.collider.get_meta("entity_id","")) if not hit.is_empty() else ""

func _body_clear() -> bool:
	var body=session.players[1]
	for child in body.get_children():
		if not child is CollisionShape3D or child.disabled: continue
		var query:=PhysicsShapeQueryParameters3D.new()
		query.shape=child.shape
		query.transform=child.global_transform
		query.collision_mask=body.collision_mask
		query.exclude=[body.get_rid()]
		query.margin=0.001
		if not session.get_world_3d().direct_space_state.intersect_shape(query,1).is_empty(): return false
	return true

func _body_overlap_details() -> Array:
	var result: Array = []
	var body = session.players[1]
	for child in body.get_children():
		if not child is CollisionShape3D or child.disabled: continue
		var query := PhysicsShapeQueryParameters3D.new()
		query.shape = child.shape
		query.transform = child.global_transform
		query.collision_mask = body.collision_mask
		query.exclude = [body.get_rid()]
		query.margin = 0.001
		for hit in session.get_world_3d().direct_space_state.intersect_shape(query, 32):
			var collider = hit.get("collider")
			result.append({"body_shape":str(child.name), "collider":str(collider.get_path()) if collider is Node else str(collider),
				"entity_id":str(collider.get_meta("entity_id", "")) if collider is Node else "", "shape_index":hit.get("shape", -1),
				"layer":collider.collision_layer if collider is CollisionObject3D else -1})
	return result

func _gate_details() -> Dictionary:
	var body = session.players[1]
	return {"gate_fraction":session.world.gate_fraction, "obstructed":session.world.gate_obstructed,
		"open":session.world.gate_open, "body_clear":_body_clear(), "overlaps":_body_overlap_details(),
		"body_position":str(body.global_position), "body_y":body.global_position.y,
		"body_height":body.stats.height_m, "gate_y":session.world.gate.global_position.y,
		"gate_bottom":session.world.gate.global_position.y-2.5,
		"relay_state":session.entities["F1:relay"].duplicate(true)}

func _travel(a: Vector3,b: Vector3,label: String) -> bool:
	await _place(a)
	var clear: bool=_body_clear()
	var body=session.players[1]
	var hit=body.move_and_collide(b-a)
	session.entities["player:1"].position=body.global_position
	var ok: bool=clear and hit==null and body.global_position.distance_to(b)<0.02
	_check(ok,label,{"initial_clear":clear,"end":str(body.global_position),"collider":str(hit.get_collider().get_path()) if hit else ""})
	await _settle()
	return ok

func _cast(name: String,target: String = "",mode: String = "",point: Vector3 = Vector3.ZERO) -> bool:
	# Explicit stamina/time fixture, not a claim about a natural play cadence.
	session.cooldowns[1]=0.0
	session.entities["player:1"].energy=100.0
	var used: int=session.stats.abilities
	session._action_received(1,"ability",{"ability":name,"target_id":target,"mode":mode,"point":point})
	var accepted: bool=session.stats.abilities==used+1
	_check(accepted,"production ability accepted: "+name+":"+target+":"+mode)
	return accepted

func _ticks(seconds: float,steps: int = 8,observe_gate: bool = false) -> void:
	last_gate_ticks = []
	for i in range(steps):
		session.world.synchronize(session.entities,seconds/float(steps))
		_freeze()
		await _settle()
		if observe_gate:
			var observed := _gate_details()
			observed["tick"] = i
			observed["delta"] = seconds/float(steps)
			last_gate_ticks.append(observed)
	# Refresh only the optical query after transforms reach PhysicsServer. A second
	# zero-delta mechanism tick clears the per-tick gate_obstructed observation even
	# when the last real closing tick correctly stopped at an occupied volume.
	if is_instance_valid(session.world.art_temple):
		session.world._resolve_light_path(session.entities)
	_freeze()

func _run() -> void:
	create_timer(90).timeout.connect(func():
		if not done:
			push_error("GROWTH_CROSSING timeout; no pass implied")
			quit(2))
	session=Session.new()
	root.add_child(session)
	_check(session.profile_ready and session.store.root_path=="user://profiles_v3/"+profile,"only fresh isolated production profile opened")
	if not session.profile_ready: await _finish(); return
	_check(session.start_flight("solo"),"production solo session starts without ENet")
	if not session.active: await _finish(); return
	_freeze()
	if not _seed_route_fixture(): await _finish(); return
	_check(session._load_region("F1"),"real F1 builds with new crossing and shore data")
	_freeze()
	await _settle()
	if session.region_id!="F1": await _finish(); return
	_check(session.world.build_errors.is_empty(),"no required F1 scene dependency failed",{"errors":session.world.build_errors})
	_test_structure()
	_test_foundation_water()
	_test_joins()
	await _test_ungrown()
	await _grow_from_real_actions()
	await _test_gate_and_routes()
	await _test_switch()
	await _test_revoke()
	await _test_saved_route_choices()
	await _finish()

func _seed_route_fixture() -> bool:
	# This is historical prerequisite data, deliberately NOT ten replayed quests.
	var director=Director.new()
	var loaded: Dictionary=director.load_definitions(Director.DEFAULT_PATH)
	_check(loaded.get("ok",false),"fixture director loads original authored actions")
	if not loaded.get("ok",false): return false
	var state: Dictionary=director.default_state()
	for i in range(PREFIX_EVENTS.size()):
		var row: Array=PREFIX_EVENTS[i]
		var result: Dictionary=director.apply_event(state,{"id":"qa_growth_history:"+str(i),"type":row[0],"target_id":row[1],"option":row[2]},{"is_authority":true,"validated":true,"region_id":row[3]})
		if not result.get("ok",false) or not result.get("changed",false):
			_check(false,"historical fixture event "+str(i),result)
			return false
		state=result.state
	_check(state.completed.size()==10 and session.story.director.validate_state(state).get("ok",false),"ten historical objectives validate against production extended story")
	var changes: Dictionary={"world.actions.opening":state,"world.region_id":"F1","world.entities.F1":{},"world.flags.F1_gate":false,"world.completed_objectives":state.completed}
	for flag in state.flags: changes["world.flags."+str(flag)]=state.flags[flag]
	var saved: Dictionary=session.store.commit({"id":"qa_growth_history_fixture","set":changes,"append":{"personal.discoveries":state.discoveries}})
	_check(saved.get("ok",false),"explicit historical fixture committed, without claiming its physics")
	if not saved.get("ok",false): return false
	for route in ["flight","growth","blink"]:
		var forked: Dictionary=session.store.fork_branch("growth-route-"+route,"QA route "+route,false)
		_check(forked.get("ok",false),"fresh independent pre-route branch "+route)
		if not forked.get("ok",false): return false
	session.world_cache=session.store.snapshot()
	session.consensus.set_world_revision(int(session.world_cache.world_revision))
	return true

func _test_structure() -> void:
	stage="structure"
	var stale: Array=[]
	for node in session.world.find_children("*","CollisionShape3D",true,false):
		if node.shape is BoxShape3D and node.shape.size.is_equal_approx(Vector3(30,0.8,5)): stale.append(str(node.get_path()))
	for node in session.world.find_children("*","MeshInstance3D",true,false):
		if node.mesh is BoxMesh and node.mesh.size.is_equal_approx(Vector3(30,0.8,5)): stale.append(str(node.get_path()))
	_check(stale.is_empty(),"old 30x0.8x5 permanent board has no visible mesh or hidden collider",{"stale":stale})
	for side in ["west","east"]:
		var body=session.world.get_node_or_null("GrowthApproach_"+side)
		_check(body is StaticBody3D and body.get_meta("terrain_stage","")=="replaceable_graybox",side+" approach is a clearly replaceable physical graybox")
		if body==null: continue
		var faces: PackedVector3Array=body.get_node("Surface").mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
		var shapes=body.find_children("*","CollisionShape3D",true,false)
		_check(shapes.size()==1 and shapes[0].shape is ConcavePolygonShape3D and shapes[0].shape.get_faces()==faces,side+" live collision exactly matches actual rendered triangles")
	_check(session.world.growth_bridge.position.is_equal_approx(Vector3(0,5,25)) and session.world.gate.position.is_equal_approx(Vector3(6,5.4,26)),"stateful bridge/gate origins retain their existing contract")
	_check(session.world.gate.get("imported") == true and session.world.gate.get("triangles") == 18528 and session.world.gate.get("collision_parts") == 4,"production rising seal loads all four authored collision meshes")
	var empty_corner = _ray(Vector3(3,7.88,29.49),Vector3(9,7.88,29.49))
	_check(empty_corner.is_empty(),"authored empty upper seal corner has no hidden graybox collision")
	var water=session.world.get_node_or_null("Shore_water")
	_check(water!=null and water.find_children("*","CollisionObject3D",true,false).is_empty(),"new foundation does not introduce a colliding water plate")

func _water_mesh_covers(p: Vector2) -> bool:
	var mesh=session.world.get_node("Shore_water/Surface")
	var faces: PackedVector3Array=mesh.mesh.get_faces()
	for i in range(0,faces.size(),3):
		var tri:=PackedVector2Array()
		for j in range(3):
			var world_point: Vector3=mesh.global_transform*faces[i+j]
			tri.append(Vector2(world_point.x,world_point.z))
		if Geometry2D.is_point_in_polygon(p,tri): return true
	return false

func _test_foundation_water() -> void:
	stage="foundation_water"
	var layout=session.world.shore_layout
	var ignored: Array[RID]=[session.world.gate.get_rid(),session.world.growth_bridge.get_rid()]
	for x in [5.55,6.0,6.45]:
		for z in [22.55,26.0,29.45]:
			var hit:=_ray(Vector3(x,3.1,z),Vector3(x,2.7,z),ignored)
			_check(_id(hit)=="terrain:foundation:south_gate" and absf(float(hit.get("position",Vector3.INF).y)-2.9)<0.002,"closed gate has real Y2.9 support at "+str(Vector2(x,z)),{"hit":_id(hit),"position":str(hit.get("position"))})
	for p in [Vector2(6,24),Vector2(4.85,23),Vector2(7.15,29)]:
		_check(layout.foundation_at(p.x,p.y)=="south_gate" and not layout.is_water_xz(p.x,p.y) and not session.world.sample_environment(Vector3(p.x,-2.5,p.y)).water,"foundation footprint excludes water at "+str(p))
		_check(not _water_mesh_covers(p),"actual water triangles are clipped from foundation at "+str(p))
	for p in [Vector2(4.8,22.3),Vector2(7.2,22.3),Vector2(4.8,29.7),Vector2(7.2,29.7)]:
		_check(layout.foundation_at(p.x,p.y).is_empty() and layout.is_water_xz(p.x,p.y) and session.world.sample_environment(Vector3(p.x,-2.5,p.y)).water,"beveled corner outside real base remains water, not its AABB: "+str(p))
		_check(_water_mesh_covers(p),"actual water triangles retain cut-corner water at "+str(p))
		var hit:=_ray(Vector3(p.x,-1.5,p.y),Vector3(p.x,-4,p.y))
		_check(_id(hit)=="terrain:bed" and absf(float(hit.get("position",Vector3.INF).y)+3.2)<0.002,"corner ray crosses visual water and reaches real bed: "+str(p))
	var base=session.world.get_node_or_null("Shore_foundation_south_gate")
	_check(base!=null,"independent south_gate scene foundation exists")
	if base!=null:
		var faces: PackedVector3Array=base.get_node("Surface").mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
		var shapes=base.find_children("*","CollisionShape3D",true,false)
		_check(shapes.size()==1 and shapes[0].shape is ConcavePolygonShape3D and shapes[0].shape.get_faces()==faces,"south gate foundation mesh/collider use the same faces")

func _test_joins() -> void:
	stage="actual_joins"
	var west=session.world.get_node("GrowthApproach_west")
	var old_rids: Array[RID]=[]
	for body in session.world.terrain_modules[2].find_children("*","CollisionObject3D",true,false): old_rids.append(body.get_rid())
	for sample in WEST_JOIN:
		var z: float=sample[0]
		var expected: float=sample[1]
		var old:=_ray(Vector3(-14.5,7,z),Vector3(-14.5,0.1,z),[west.get_rid()])
		var joined:=_ray(Vector3(-14.5,7,z),Vector3(-14.5,0.1,z),old_rids)
		_check(not old.is_empty() and absf(float(old.position.y)-expected)<0.003,"original imported Rootstone contact remains at measured Z"+str(z),{"position":str(old.get("position")),"expected":expected})
		_check(_id(joined)=="terrain:growth_approach:west" and absf(float(joined.get("position",Vector3.INF).y)-expected)<0.003,"new west seam agrees with actual old support Z"+str(z),{"position":str(joined.get("position")),"hit":_id(joined)})
	for z in [24.1,24.5,25.0,25.5,26.0,26.4]:
		var left:=_ray(Vector3(-14.52,7,z),Vector3(-14.52,0.1,z))
		var right:=_ray(Vector3(-14.48,7,z),Vector3(-14.48,0.1,z))
		_check(not left.is_empty() and not right.is_empty() and absf(float(left.position.y)-float(right.position.y))<0.08,"actual main seam has no floating step at Z"+str(z),{"left":str(left.get("position")),"right":str(right.get("position"))})
	for side in [-1,1]:
		for z in [23.6,24.0,25.0,26.0,26.4]:
			var hit:=_ray(Vector3(float(side)*11.0,7,z),Vector3(float(side)*11.0,4,z))
			_check(_id(hit)=="terrain:growth_approach:"+("west" if side<0 else "east") and absf(float(hit.get("position",Vector3.INF).y)-5.25)<0.002,"formal bridge lip remains Y5.25 across width at "+str(Vector2(float(side)*11.0,z)))
			var nose:=_ray(Vector3(float(side)*10.75,7,z),Vector3(float(side)*10.75,4,z))
			_check(_id(nose)=="terrain:growth_approach:"+("west" if side<0 else "east") and absf(float(nose.get("position",Vector3.INF).y)-5.20)<0.002,"ungrown insertion nose drops 5cm below lip at "+str(Vector2(float(side)*10.75,z)))
	for z in [25.0,26.0,27.3]:
		var before:=_ray(Vector3(15.98,6,z),Vector3(15.98,1,z))
		var after:=_ray(Vector3(16.02,6,z),Vector3(16.02,1,z))
		_check(not before.is_empty() and not after.is_empty() and absf(float(after.position.y)-2.4)<0.002 and absf(float(before.position.y)-float(after.position.y))<0.03,"east approach meets real Y2.4 bank at Z"+str(z),{"before":str(before.get("position")),"after":str(after.get("position"))})

func _test_ungrown() -> void:
	stage="ungrown"
	_check(not session.world.growth_bridge.visible and session.world.growth_bridge.collision_layer==0,"fresh branch has no grown bridge")
	for x in [-7.0,0.0,3.0]:
		var hit:=_ray(Vector3(x,8,25),Vector3(x,-4,25))
		_check(_id(hit)=="terrain:bed" and absf(float(hit.get("position",Vector3.INF).y)+3.2)<0.002,"unrepaired central gap has no hidden deck at X"+str(x),{"hit":_id(hit),"position":str(hit.get("position"))})
	for frame in ["tr01","hx02"]:
		session.players[1].configure(Catalog.resolve_build(Catalog.default_build(frame)))
		_freeze()
		await _settle()
		await _travel(Vector3(-5,3,25),Vector3(3,3,25),frame+" passes the former permanent-board volume before growth")
	await _place(Vector3(-16,5.2,30.35))
	session.cooldowns[1]=0.0
	session.entities["player:1"].energy=100.0
	var rejected: int=session.stats.rejected_abilities
	session._action_received(1,"ability",{"ability":"growth","target_id":"F1:growth"})
	_check(session.stats.rejected_abilities==rejected+1 and session.entities["player:1"].energy==100.0 and session.world.growth_bridge.collision_layer==0,"unlit growth is actually rejected without creating bridge or spending energy")

func _grow_from_real_actions() -> void:
	stage="real_light_growth"
	await _place(Vector3(-24,5.2,30))
	_cast("light","F1:mirror")
	_cast("light","F1:mirror")
	await _ticks(1.2)
	var temple=session.world.art_temple
	var hit:=_ray(temple.light_origin(),temple.light_endpoint(),[],1|8)
	_check(temple.light_origin().distance_to(Vector3(-20.8,5.2,26.35))<0.002 and temple.light_endpoint().distance_to(Vector3(-15,5.2,26.35))<0.002,"real aligned beam keeps exact preserved world segment")
	_check(not hit.is_empty() and hit.collider==session.world.objects["F1:growth"] and session.entities["F1:growth"].environment_light>=1.0,"actual first-hit is the root receiver, not the new west approach",{"hit":_id(hit)})
	await _place(Vector3(-16,5.2,30.35))
	_cast("growth","F1:growth")
	await _ticks(0.0,1)
	_check(session.entities["F1:growth"].growth<0.5 and session.world.growth_bridge.collision_layer==0,"one actual growth does not prematurely form the crossing")
	_cast("growth","F1:growth")
	await _ticks(0.0,1)
	_check(session.entities["F1:growth"].growth>=0.5 and session.world.growth_bridge.visible and session.world.growth_bridge.collision_layer==1,"two actual growth actions form the authoritative bridge")
	for x in [-7.0,0.0,3.0,9.0]:
		var landing:=_ray(Vector3(x,8,25),Vector3(x,4,25))
		_check(not landing.is_empty() and landing.collider==session.world.growth_bridge and absf(float(landing.position.y)-5.25)<0.002,"grown bridge really bears at Y5.25 at X"+str(x))
	for side in [-1,1]:
		for z in [23.6,24.5,25.5,26.4]:
			var nose:=_ray(Vector3(float(side)*10.85,7,z),Vector3(float(side)*10.85,4,z))
			_check(not nose.is_empty() and nose.collider==session.world.growth_bridge and absf(float(nose.position.y)-5.25)<0.002,"grown bridge is actual first-hit above recessed insertion nose at "+str(Vector2(float(side)*10.85,z)))

func _open_gate() -> void:
	await _place(Vector3(-14,2.5,19))
	_cast("charge","F1:relay")
	await _ticks(1.6)
	_check(session.world.gate_fraction>=0.999 and absf(float(session.world.gate.position.y)-11.4)<0.002,"one real relay charge raises the actual gate to its open pose")

func _test_gate_and_routes() -> void:
	stage="gate_body_routes"
	for frame in ["tr01","hx02"]:
		session.players[1].configure(Catalog.resolve_build(Catalog.default_build(frame)))
		_freeze()
		await _settle()
		await _place(Vector3(3,6.2,25))
		_check(_body_clear(),frame+" starts outside closed gate and above grown bridge")
		var hit=session.players[1].move_and_collide(Vector3(6,0,0))
		_check(hit!=null and hit.get_collider()==session.world.gate,frame+" closed gate blocks the actual body")
		await _place(Vector3(3,6.2,25))
		session.cooldowns[1]=0.0
		session.entities["player:1"].energy=100.0
		var rejected: int=session.stats.rejected_abilities
		session._action_received(1,"ability",{"ability":"blink","point":Vector3(9,6.2,25)})
		_check(session.stats.rejected_abilities==rejected+1 and session.entities["player:1"].energy==100.0 and session.players[1].position.distance_to(Vector3(3,6.2,25))<0.01,frame+" real blink cannot cross closed gate and spends no energy")
		await _open_gate()
		var points: Array[Vector3]=[Vector3(-12,6.2,25),Vector3(-9,6.2,25),Vector3(0,6.2,25),Vector3(9.5,6.2,25),Vector3(11.8,6.6,25.7),Vector3(14,5.1,26),Vector3(16.2,4.1,26.2)]
		for i in range(1,points.size()):
			await _travel(points[i-1],points[i],frame+" real-body upper route segment "+str(i))
			await _travel(points[i],points[i-1],frame+" reverse upper route segment "+str(i))
		await _place(Vector3(0,8,25))
		hit=session.players[1].move_and_collide(Vector3(0,-5,0))
		var bottom: float=session.players[1].position.y-float(session.players[1].stats.height_m)*0.5
		_check(hit!=null and hit.get_collider()==session.world.growth_bridge and absf(bottom-5.25)<0.04,frame+" lands its actual collision body on the grown surface",{"bottom":bottom})
		# Drain from a legal range, then place the same body inside the still-open
		# passage before ticking closure. No manual gate pose or fake occupancy.
		await _place(Vector3(-14,2.5,19))
		_cast("charge","F1:relay","drain")
		await _place(Vector3(6,6.2,25))
		_check(_body_clear(),frame+" body fits within actual open-gate clearance")
		await _ticks(2.0,14,true)
		for observed in last_gate_ticks:
			_check(bool(observed.body_clear) and observed.overlaps.is_empty(),frame+" closing tick "+str(observed.tick)+" has no actual body penetration",observed)
		var closing_details := {"frame":frame, "ticks":last_gate_ticks.duplicate(true), "after_optical_refresh":_gate_details()}
		gate_diagnostics.append(closing_details)
		_check(session.world.gate_obstructed and session.world.gate_fraction>0.0 and _body_clear(),frame+" real closing gate stops without penetrating occupying body",closing_details)
		await _place(Vector3(-3,6.2,25))
		await _ticks(1.6)
		_check(session.world.gate_fraction<=0.001 and not session.world.gate_obstructed,frame+" gate closes after actual body clears")
		await _travel(Vector3(-4,4,33),Vector3(14,4,33),frame+" south Z33 route remains open despite closed gate")
		await _travel(Vector3(14,4,33),Vector3(-4,4,33),frame+" south route is bidirectional")
		await _place(Vector3(4.5,4,33))
		_cast("blink","","",Vector3(12.5,4,33))
		_check(session.players[1].position.distance_to(Vector3(12.5,4,33))<0.01 and absf(float(session.entities["player:1"].energy)-84.0)<0.001,frame+" legal 8m south blink executes and charges real energy")

func _test_switch() -> void:
	stage="switch_access"
	await _place(Vector3(15,4.7,21))
	_check(_body_clear() and session._line_clear(session.players[1].position,session.entities["F1:switch"].position,session.players[1].get_rid(),"F1:switch"),"east approach leaves real access and line of sight to original switch")
	_cast("echo","F1:switch")
	await _ticks(3.0)
	_check(absf(float(session.world.platform.position.y)-7.5)<0.002 and session.world.gate_fraction<=0.001,"actual switch echo lifts its platform without incorrectly opening gate")

func _test_revoke() -> void:
	stage="explicit_revoke_fixture"
	await _place(Vector3(0,8,25))
	# No shrink ability exists. This explicit authority-state restoration fixture
	# verifies the runtime removes collision; it is not attributed to a player action.
	session.entities["F1:growth"].growth=0.0
	session.entities["F1:growth"].revision+=1
	await _ticks(0.0,1)
	_check(not session.world.growth_bridge.visible and session.world.growth_bridge.collision_layer==0,"authoritative growth revoke removes both appearance and collision")
	for x in [-7.0,0.0,3.0]:
		var hit:=_ray(Vector3(x,8,25),Vector3(x,-4,25))
		_check(_id(hit)=="terrain:bed", "revoked crossing leaves no stale bridge body at X"+str(x),{"hit":_id(hit)})

func _test_saved_route_choices() -> void:
	for route in ["flight","growth","blink"]:
		stage="actual_saved_route_"+route
		session._ui_action("branch",{"id":"growth-route-"+route})
		_freeze()
		await _settle()
		_check(session.region_id=="F1" and session.story.state.revision==10 and session.world.growth_bridge.collision_layer==0,"independent branch restores legal pre-arrival fixture for "+route)
		if session.story.state.revision!=10: continue
		if route=="flight":
			await _travel(Vector3(-4,4.7,33),Vector3(13,4.7,32),"actual south route reaches nursery without bridge or gate repair")
		elif route=="blink":
			await _place(Vector3(4.5,4,33))
			_cast("blink","","",Vector3(12.5,4,33))
		else:
			await _grow_from_real_actions()
			await _open_gate()
			await _travel(Vector3(-10,6.2,25),Vector3(10,6.2,25),"actual body crosses grown upper route before nursery")
			session.story.observe(0.3)
			_check(session.story.state.revision==10,"entering grown route alone cannot complete nursery arrival")
			await _travel(Vector3(10,6.2,25),Vector3(12,6.5,28),"grown-route player leaves bridge toward nursery")
			await _travel(Vector3(12,6.5,28),Vector3(13,4.7,32),"grown-route player actually reaches nursery")
		stage="actual_saved_route_"+route
		session.story.observe(0.3)
		_check(session.story.state.revision==11 and session.story.state.choices.get("F1:needs:route","")==route,"host derives and commits "+route+" from real current arrival evidence")
		var fresh=Store.new(session.store.root_path)
		var read: Dictionary=fresh.load_profile()
		_check(read.get("ok",false) and fresh.snapshot().world.actions.opening.choices.get("F1:needs:route","")==route,"fresh disk reader retains actual "+route+" choice")
		var generation: int=session.store.snapshot().generation
		session.story.observe(0.3)
		_check(session.store.snapshot().generation==generation,"repeated "+route+" arrival does not duplicate story commit")

func _finish() -> void:
	done=true
	print("V3_GROWTH_CROSSING_CONTRACT "+JSON.stringify({"checks":checks.size(),"failures":failures,"profile":profile,
		"scope":"Actual production SceneTree, PhysicsServer, ability adapter and durable route receipts. Scripted body movement, not propulsion/human/GPU/performance/LAN acceptance.",
		"fixtures":["ten historical reducer events, not replayed quests","frozen production bodies and scripted placements/sweeps","replenished energy and cooldowns","explicit growth revoke state because no shrink ability exists"],"gate_diagnostics":gate_diagnostics,"results":checks}))
	if is_instance_valid(session):
		session.network.close()
		session.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)
