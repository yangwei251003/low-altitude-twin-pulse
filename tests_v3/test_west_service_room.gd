extends SceneTree
## Real MAIN presentation and unchanged solid; observation poses are explicit.
const MAIN=preload("res://scenes/v3/main.tscn")
const Art=preload("res://scripts/v3/art/twin_west_service_room_art.gd")
const Capture=preload("res://scripts_tools/v3/capture_hud_visibility.gd")
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
	if not profile.begins_with("qa_west_service_") or not output.begins_with("res://artifacts/v3/west-service-") or ".." in output or DirAccess.dir_exists_absolute(output) or DisplayServer.get_name()=="headless":
		quit(2); return
	DirAccess.make_dir_recursive_absolute(output)
	create_timer(75).timeout.connect(func():
		if not finished: _check(false,"bounded MAIN check"); _finish())
	root.size=Vector2i(1280,720)
	session=MAIN.instantiate()
	root.add_child(session)
	if not _check(session.profile_ready and session.start_flight("solo") and session._load_region("I2"),"normal MAIN loads I2"): _finish(); return
	await physics_frame
	await physics_frame
	if not _check(session._facilities_ready() and session.world.build_errors.is_empty(),"existing facilities remain ready"): _finish(); return
	var works: Node3D=session.world.clinic
	var art: Dictionary=works.west_service_room_art
	if not _check(art.get("ok",false),"normal waterworks installs room",art.get("code")): _finish(); return
	var body: StaticBody3D=works.fixed_bodies.WestLowRoof
	var shape: CollisionShape3D=body.get_node("ExactBoxCollision")
	var original_rid:=body.get_rid()
	var shape_id:=shape.shape.get_instance_id()
	_check(art.body==body and art.shape==shape and art.model.get_parent()==body and art.model.position.is_equal_approx(Vector3(0,-1.25,0)),"visual attaches beneath original solid")
	_check(not body.get_node("Visual").visible and body.collision_layer==1 and body.collision_mask==0 and shape.shape.size==Vector3(4,2.5,4),"graybox hidden while original box remains")
	_check(art.model.scene_file_path==Art.MODEL_PATH and art.materials==3,"explicit production GLB and three imported materials")
	var space:=works.get_world_3d().direct_space_state
	var top:=space.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(-14,4,-8),Vector3(-14,1,-8),1))
	var wall:=space.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(-18,1.2,-8),Vector3(-13,1.2,-8),1))
	var gap:=space.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(-13,4,-5.5),Vector3(-13,.1,-5.5),1))
	_check(top.get("collider")==body and top.position.is_equal_approx(Vector3(-14,2.5,-8)),"actual roof remains 2.5m",top.get("position"))
	_check(wall.get("collider")==body and wall.position.is_equal_approx(Vector3(-16,1.2,-8)),"west wall collision unchanged",wall.get("position"))
	_check(gap.is_empty(),"one-metre gap to offset building remains open",gap.get("position"))
	var offset: Dictionary=works.west_offset_room_art
	if not _check(offset.get("ok",false),"front offset room installed in normal waterworks",offset.get("code")): _finish(); return
	var offset_body: StaticBody3D=works.fixed_bodies.WestOffsetRoof
	var offset_shape: CollisionShape3D=offset_body.get_node("ExactBoxCollision")
	var offset_rid:=offset_body.get_rid()
	var offset_shape_id:=offset_shape.shape.get_instance_id()
	_check(offset.body==offset_body and offset.shape==offset_shape and offset.model.get_parent()==offset_body and offset.model.position.is_equal_approx(Vector3(0,-2.05,0)),"offset shell retains its own original body and bottom origin")
	_check(offset.model.scene_file_path=="res://assets/v3/environment/west_offset_room/west_offset_room.glb" and offset.materials==3 and not offset_body.get_node("Visual").visible,"offset approved GLB replaces visible graybox")
	var offset_top:=space.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(-12.5,6,-2.5),Vector3(-12.5,1,-2.5),1))
	var offset_wall:=space.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(-16,1.2,-2.5),Vector3(-12,1.2,-2.5),1))
	_check(offset_top.get("collider")==offset_body and offset_top.position.is_equal_approx(Vector3(-12.5,4.1,-2.5)),"actual offset roof remains 4.1m",offset_top.get("position"))
	_check(offset_wall.get("collider")==offset_body and offset_wall.position.is_equal_approx(Vector3(-14,1.2,-2.5)),"offset original west wall remains solid",offset_wall.get("position"))
	pilot=session.players[1]
	session.inputs.test_enabled=true
	session.inputs.test_frame={"held":["brake"]}
	var hull:=pilot.get_node("Envelope") as CollisionShape3D
	var clear_west_x: float=body.global_position.x-shape.shape.size.x*.5-hull.shape.size.x*.5-.25
	for row: Array in [["01-room-close",Vector3(-17.2,3,-3),16.0],["02-room-default",Vector3(-17.2,2,0),26.0],["03-room-whole-yard",Vector3(-7,2,18),42.0],["04-room-camera-cutaway",Vector3(clear_west_x,.75,-9.5),16.0]]:
		await _capture(row[0],row[1],row[2])
		if finished: return
	_check_cutaway(art,"low room")
	var clear_offset_x: float=offset_body.global_position.x-offset_shape.shape.size.x*.5-hull.shape.size.x*.5-.25
	await _capture("05-offset-room-cutaway",Vector3(clear_offset_x,.75,-2.5),16.0)
	if finished: return
	_check_cutaway(offset,"offset room")
	_check(body.get_rid()==original_rid and shape.shape.get_instance_id()==shape_id and offset_body.get_rid()==offset_rid and offset_shape.shape.get_instance_id()==offset_shape_id and session._facilities_ready(),"camera changes preserve both collision identities and live facilities")
	_finish()

func _check_cutaway(art: Dictionary,label: String) -> void:
	var body: StaticBody3D=art.body
	var entry: Dictionary=session.terrain_visibility._entries.get(body.get_instance_id(),{})
	_check(not entry.is_empty() and entry.blocked and entry.installed and entry.alpha<.5,"normal local camera fades obstructing "+label,{"blocked":entry.get("blocked"),"alpha":entry.get("alpha")})
	var original_materials:=true
	for mesh: MeshInstance3D in art.model_meshes:
		original_materials=original_materials and mesh.mesh.surface_get_material(0).transparency==BaseMaterial3D.TRANSPARENCY_DISABLED
	_check(original_materials,"cutaway leaves shared imported materials opaque: "+label)

func _capture(label: String,at: Vector3,size: float) -> void:
	pilot.freeze=true
	pilot.global_transform=Transform3D(Basis.IDENTITY,at)
	PhysicsServer3D.body_set_state(pilot.get_rid(),PhysicsServer3D.BODY_STATE_TRANSFORM,pilot.global_transform)
	pilot.linear_velocity=Vector3.ZERO
	pilot.angular_velocity=Vector3.ZERO
	pilot.hold_height=at.y
	pilot.safe_position=at
	var envelope:=pilot.get_node("Envelope") as CollisionShape3D
	var query:=PhysicsShapeQueryParameters3D.new()
	query.shape=envelope.shape
	query.transform=pilot.global_transform*envelope.transform
	query.collision_mask=pilot.collision_mask
	query.exclude=[pilot.get_rid()]
	query.margin=.002
	var hits:=pilot.get_world_3d().direct_space_state.intersect_shape(query,8)
	if not _check(hits.is_empty(),"declared pose has real hull clearance "+label,hits.map(func(row: Dictionary): return str(row.collider.get_path()))):
		_finish(); return
	session.flight_camera.target_size=size
	session.camera.size=size
	session.flight_camera.snap(at)
	await physics_frame
	await physics_frame
	pilot.freeze=false
	await create_timer(.6).timeout
	await RenderingServer.frame_post_draw
	_check(root.get_texture().get_image().save_png(output+"/"+label+".png")==OK,"actual MAIN screenshot "+label)
	shots.append({"name":label,"declared_initial_pose":at,"player":pilot.global_position,"camera":session.camera.global_transform,"size":session.camera.size})

func _check(ok: bool,label: String,actual: Variant=null) -> bool:
	checks.append({"passed":ok,"label":label,"actual":actual})
	return ok

func _finish() -> void:
	if finished: return
	finished=true
	var failures:=checks.filter(func(row: Dictionary): return not row.passed)
	FileAccess.open(output+"/result.json",FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failures":failures,"engine_errors":logger.errors,"shots":shots,"scope":"Normal MAIN, imported low and offset rooms, original collisions, camera cutaways and five explicit QA observation poses; no flight route, human, LAN, performance or release acceptance."},"\t"))
	print("WEST_SERVICE_RESULT "+JSON.stringify({"checks":checks.size(),"failures":failures,"engine_errors":logger.errors}))
	quit(0 if failures.is_empty() and logger.errors.is_empty() else 1)
