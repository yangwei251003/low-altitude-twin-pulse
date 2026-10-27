extends SceneTree
## Real MAIN views; explicit QA poses and historical raised-water fixture.
const MAIN=preload("res://scenes/v3/main.tscn")
const Art=preload("res://scripts/v3/art/twin_west_landing_platform_art.gd")
const LiftArt=preload("res://scripts/v3/art/twin_clinic_lift_deck_art.gd")
const Capture=preload("res://scripts_tools/v3/capture_hud_visibility.gd")
const RAISED="res://tests_v3/fixtures/west_landing_raised_water.json"
var logger=Capture.CaptureLogger.new()
var session: Node
var pilot: FlightBodyV2
var output: String
var checks: Array=[]
var shots: Array=[]
var finished:=false

func _initialize() -> void:
	OS.add_logger(logger)
	_run.call_deferred()

func _run() -> void:
	var profile:=""
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--output="): output=arg.trim_prefix("--output=")
		if arg.begins_with("--qa-profile="): profile=arg.trim_prefix("--qa-profile=")
	if not profile.begins_with("qa_west_landing_") or not output.begins_with("res://artifacts/v3/west-landing-") or ".." in output or DirAccess.dir_exists_absolute(output) or DisplayServer.get_name()=="headless":
		quit(2); return
	DirAccess.make_dir_recursive_absolute(output)
	create_timer(70).timeout.connect(func():
		if not finished: _check(false,"bounded MAIN check"); _finish())
	root.size=Vector2i(1280,720)
	session=MAIN.instantiate()
	root.add_child(session)
	var loaded: bool=session.profile_ready and session.start_flight("solo") and session._load_region("I2")
	if not _check(loaded,"normal MAIN loads I2",session.interface.message.text): _finish(); return
	await physics_frame
	await physics_frame
	if not _check(session._facilities_ready() and session.world.build_errors.is_empty(),"four existing facilities remain ready"): _finish(); return
	# Stop progression only for deterministic art observation. No completion,
	# player traversal or play-time claim follows from these QA placements.
	session.set_physics_process(false)
	session.inputs.test_enabled=true
	session.inputs.test_frame={"held":[],"edges":[],"axes":{}}
	pilot=session.players[1]
	pilot.freeze=true
	pilot.set_physics_process(false)
	var works: Node3D=session.world.clinic
	var art: Dictionary=works.west_landing_platform_art
	if not _check(art.get("ok",false),"normal waterworks installs authored platform",art.get("code")): _finish(); return
	_check(art.source_scene.resource_path==Art.MODEL_PATH and art.triangles==3128 and art.materials==2 and art.model_meshes.size()==4,"explicit production GLB with four meshes and two shared PBR materials")
	var identities: Array=[]
	for row: Dictionary in art.groups:
		var body: StaticBody3D=row.body
		var spec: Dictionary=Art.GROUPS[str(row.group.name)]
		var extent: AABB=spec.extent
		_check(row.group.get_parent()==body and row.group.position.is_equal_approx(Art.ORIGIN-body.position),"separate art owner: "+str(row.id))
		_check(body.collision_layer==1 and body.collision_mask==0 and row.shape.shape.size.is_equal_approx(extent.size) and not body.get_node("Visual").visible,"original solid preserved and graybox hidden: "+str(row.id))
		identities.append({"body":body,"rid":body.get_rid(),"shape":row.shape,"resource":row.shape.shape.get_instance_id(),"pose":body.transform})
	var space:=works.get_world_3d().direct_space_state
	var deck:=works.fixed_bodies.WestLanding as StaticBody3D
	var leg:=works.fixed_bodies.WestLandingLeg as StaticBody3D
	var top:=space.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(-4,6,-3),Vector3(-4,4,-3),1))
	var underside:=space.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(-4,2,-3),Vector3(-4,6,-3),1))
	var leg_hit:=space.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(-10.2,2,-2.75),Vector3(-8.8,2,-2.75),1))
	_check(top.get("collider")==deck and top.position.is_equal_approx(Vector3(-4,5,-3)),"actual platform top remains 5m",top.get("position"))
	_check(underside.get("collider")==deck and underside.position.is_equal_approx(Vector3(-4,4.6,-3)),"underside stays 4.6m with open air below",underside.get("position"))
	_check(leg_hit.get("collider")==leg and leg_hit.position.is_equal_approx(Vector3(-9.6,2,-2.75)),"single offset leg retains exact original face",leg_hit.get("position"))
	var hull:=pilot.get_node("Envelope") as CollisionShape3D
	var sweep:=PhysicsShapeQueryParameters3D.new()
	sweep.shape=hull.shape
	sweep.transform=Transform3D(Basis.IDENTITY,Vector3(-8,2.2,-.6))*hull.transform
	sweep.motion=Vector3(0,0,-4.8)
	sweep.collision_mask=1|8|32
	sweep.exclude=[pilot.get_rid()]
	var passage:=space.cast_motion(sweep)
	_check(space.intersect_shape(sweep,8).is_empty() and passage.size()==2 and passage[0]==1.0,"full aircraft hull can sweep through under-platform air",passage)
	var marks: Array=[]
	for child in works.get_node("GrayboxNavigation").get_children():
		if child is MeshInstance3D and is_equal_approx(child.position.x,-3) and is_equal_approx(child.position.y,5.004): marks.append(child)
	_check(marks.size()==2 and marks.all(func(node: Node3D): return node.visible),"two independent bearing lines remain visible")
	var moving_rid: RID=works.deck.get_rid()
	var lift: Dictionary=works.lift_deck_art
	if not _check(lift.get("ok",false),"normal waterworks installs authored moving deck",lift.get("code")): _finish(); return
	_check(lift.body==works.deck and lift.model.get_parent()==works.deck and lift.model.transform==Transform3D.IDENTITY and lift.model.scene_file_path==LiftArt.MODEL_PATH,"moving visual follows original hydraulic body without an offset")
	_check(lift.triangles==1228 and lift.materials==2 and lift.model_meshes.size()==2 and not works.deck.get_node("Visual").visible,"two imported PBR groups replace the pale moving graybox")
	var moving_identity: Dictionary={}
	for id: String in works.moving_bodies:
		var body: StaticBody3D=works.moving_bodies[id]
		moving_identity[id]={"rid":body.get_rid(),"shape":body.get_node("ExactBoxCollision").shape.get_instance_id(),"size":body.get_node("ExactBoxCollision").shape.size,"layer":body.collision_layer,"mask":body.collision_mask}
	_check(is_equal_approx(float(works.status().deck_top_y),4.0),"arrival moving deck remains one metre below fixed platform")
	for row: Array in [["01-platform-close-low",Vector3(-7,5.8,.8),16.0],["02-platform-default",Vector3(-7,3,2),26.0],["03-platform-yard",Vector3(-7,2,18),42.0],["04-platform-underflight",Vector3(-8,2.2,-4.5),16.0]]:
		await _capture(row[0],row[1],row[2])
		if finished: return
	var entry: Dictionary=session.terrain_visibility._entries.get(deck.get_instance_id(),{})
	_check(not entry.is_empty() and entry.blocked and entry.installed and entry.alpha<.5,"normal camera fades obstructing platform",{"blocked":entry.get("blocked"),"alpha":entry.get("alpha")})
	var opaque:=true
	for mesh: MeshInstance3D in art.model_meshes: opaque=opaque and mesh.mesh.surface_get_material(0).transparency==BaseMaterial3D.TRANSPARENCY_DISABLED
	_check(opaque,"local fade preserves shared imported materials")
	# Actual dev29 full-water state, not a newly completed hydraulic action.
	var fixture: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(RAISED))
	var restored: Dictionary=works.apply_snapshot(fixture.state)
	if not _check(restored.ok,"validated historical raised-water art fixture",restored.get("code")): _finish(); return
	await physics_frame
	await physics_frame
	var raised:=space.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(0,6,-4),Vector3(0,3,-4),1|8))
	_check(raised.get("collider")==works.deck and is_equal_approx(raised.position.y,5.0) and works.deck.get_rid()==moving_rid,"same real moving deck becomes flush at 5m",raised.get("position"))
	_check(lift.model.global_transform.is_equal_approx(works.deck.global_transform),"authored moving deck follows the raised authoritative pose")
	var original_moving:=moving_identity.size()==9
	for id: String in moving_identity:
		var body: StaticBody3D=works.moving_bodies[id]
		var saved: Dictionary=moving_identity[id]
		original_moving=original_moving and body.get_rid()==saved.rid and body.get_node("ExactBoxCollision").shape.get_instance_id()==saved.shape and body.get_node("ExactBoxCollision").shape.size==saved.size and body.collision_layer==saved.layer and body.collision_mask==saved.mask
	_check(original_moving,"all nine moving bodies retain original shapes identities and filters")
	var raw_clear:=true
	for mesh: MeshInstance3D in art.model_meshes:
		for vertex: Vector3 in mesh.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]:
			var point: Vector3=mesh.global_transform*vertex
			if point.x> -2.0+.00003 and point.x<2 and point.z> -6 and point.z< -2 and point.y>3.65 and point.y<5: raw_clear=false
	_check(raw_clear,"authored vertices do not enter the moving deck swept volume")
	await _capture("05-platform-raised-joint",Vector3(-7,5.8,.8),16.0)
	if finished: return
	await _capture("06-moving-deck-underflight",Vector3(-.6,2.2,-4.5),16.0)
	if finished: return
	var lift_entry: Dictionary=session.terrain_visibility._entries.get(works.deck.get_instance_id(),{})
	_check(not lift_entry.is_empty() and lift_entry.blocked and lift_entry.installed and lift_entry.alpha<.5,"normal local camera fades the obstructing moving deck",{"blocked":lift_entry.get("blocked"),"alpha":lift_entry.get("alpha")})
	var lift_opaque:=true
	for mesh: MeshInstance3D in lift.model_meshes: lift_opaque=lift_opaque and mesh.mesh.surface_get_material(0).transparency==BaseMaterial3D.TRANSPARENCY_DISABLED
	_check(lift_opaque,"moving-deck cutaway preserves imported shared material resources")
	for row: Dictionary in identities:
		_check(row.body.get_rid()==row.rid and row.shape.shape.get_instance_id()==row.resource and row.body.transform==row.pose,"camera and water fixture preserve physical identity: "+str(row.body.name))
	_finish()

func _capture(label: String,at: Vector3,size: float) -> void:
	pilot.global_transform=Transform3D(Basis.IDENTITY,at)
	pilot.force_update_transform()
	PhysicsServer3D.body_set_state(pilot.get_rid(),PhysicsServer3D.BODY_STATE_TRANSFORM,pilot.global_transform)
	pilot.linear_velocity=Vector3.ZERO
	pilot.angular_velocity=Vector3.ZERO
	pilot.hold_height=at.y
	var hull:=pilot.get_node("Envelope") as CollisionShape3D
	var query:=PhysicsShapeQueryParameters3D.new()
	query.shape=hull.shape
	query.transform=pilot.global_transform*hull.transform
	query.collision_mask=1|8|32
	query.exclude=[pilot.get_rid()]
	query.margin=.002
	var hits:=pilot.get_world_3d().direct_space_state.intersect_shape(query,8)
	if not _check(hits.is_empty(),"declared QA hull clearance: "+label,hits.map(func(row: Dictionary): return str(row.collider.get_path()))):
		_finish(); return
	session.flight_camera.target_size=size
	session.camera.size=size
	session.flight_camera.snap(at)
	await create_timer(.6).timeout
	await RenderingServer.frame_post_draw
	_check(root.get_texture().get_image().save_png(output+"/"+label+".png")==OK,"actual MAIN screenshot: "+label)
	shots.append({"name":label,"qa_pose":at,"camera":session.camera.global_transform,"size":session.camera.size})

func _check(ok: bool,label: String,actual: Variant=null) -> bool:
	checks.append({"passed":ok,"label":label,"actual":actual})
	return ok

func _finish() -> void:
	if finished: return
	finished=true
	var failures:=checks.filter(func(row: Dictionary): return not row.passed)
	FileAccess.open(output+"/result.json",FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failures":failures,"engine_errors":logger.errors,"shots":shots,"scope":"Actual MAIN, fixed platform and moving deck production GLBs, original solids and nine moving-body identities, full hull swept-space and local cutaways. Six frozen QA observation poses; final two use validated historical dev29 water state. Not a flown route, new water/action completion, performance, LAN or final scene-art acceptance."},"\t"))
	print("WEST_LANDING_RESULT "+JSON.stringify({"checks":checks.size(),"failures":failures,"engine_errors":logger.errors}))
	quit(0 if failures.is_empty() and logger.errors.is_empty() else 1)
