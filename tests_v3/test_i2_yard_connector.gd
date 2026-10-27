extends SceneTree
## Real MAIN visual check with declared observation poses. No route/FPS claim.
const MAIN=preload("res://scenes/v3/main.tscn")
const Yard=preload("res://scripts/v3/art/twin_i2_yard_connector_art.gd")
const Capture=preload("res://scripts_tools/v3/capture_hud_visibility.gd")
var logger=Capture.CaptureLogger.new()
var session: Node
var body: FlightBodyV2
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
	if not profile.begins_with("qa_i2_yard_") or not output.begins_with("res://artifacts/v3/i2-yard-") or ".." in output or DirAccess.dir_exists_absolute(output) or DisplayServer.get_name()=="headless":
		quit(2); return
	DirAccess.make_dir_recursive_absolute(output)
	create_timer(75).timeout.connect(func():
		if not finished: _check(false,"bounded visual check"); _finish())
	root.size=Vector2i(1280,720)
	session=MAIN.instantiate()
	root.add_child(session)
	if not _check(session.profile_ready and session.start_flight("solo") and session._load_region("I2"),"actual MAIN loads normal I2"): _finish(); return
	await physics_frame
	await physics_frame
	var world: Node3D=session.world
	if not _check(world.build_errors.is_empty() and session._facilities_ready(),"normal facilities remain ready",world.build_errors): _finish(); return
	var art: Dictionary=world.yard_connector_art
	if not _check(art.get("ok",false),"continuous forecourt automatically installed",art.get("code")): _finish(); return
	_check(art.model.scene_file_path==Yard.MODEL and art.model.position==Yard.Geometry.ORIGIN,"production GLB uses actual crop origin")
	_check(art.triangles==1202 and art.materials==3 and absf(art.removed_area_m2-296.5806327)<.0005,"approved continuous surface replaces exact visible area")
	var raw: Dictionary=Yard.Geometry.Reader._read_mesh(world.waterfront_install.meshes.dry_surface.mesh)
	_check(raw.ok and absf(Yard.Geometry.Split._area(raw.geometry)-1977.207571565)<.0005,"remaining ground is exact clipped source")
	var ground: StaticBody3D=world.waterfront_install.ground
	var shape: ConcavePolygonShape3D=world.waterfront_install.shape_node.shape
	var collision_sha: String=Yard.Geometry.Split._sha(shape.get_faces().to_byte_array())
	_check(collision_sha=="d665779e1312e2783a2992ab30538164394a3d7d31e76fa8221ba242d9e709fc" and ground==world.clinic.fixed_bodies.Ground,"actual original collision bytes and body preserved")
	_check(world.clinic.ground_art.ok and world.inspection_pit_art.ok and world.revetment_closure_art.ok,"old courtyard, real pit and shoreline remain installed")
	var excludes: Array[RID]=[]
	for node: Node in world.find_children("*","CollisionObject3D",true,false):
		if node!=ground: excludes.append(node.get_rid())
	for at: Vector3 in [Vector3(-23,0,19),Vector3(-19,0,11.5),Vector3(0,0,25),Vector3(-19,-1.2,7.25),Vector3(14.75,-2.8,15)]:
		var hit:=world.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(at.x,2,at.z),Vector3(at.x,-3,at.z),1,excludes))
		_check(not hit.is_empty() and absf(hit.position.y-at.y)<.00003,"real yard / ramp / waterbed height",{"expected":at,"actual":hit.get("position")})
	body=session.players[1]
	session.inputs.test_enabled=true
	session.inputs.test_frame={"held":["brake"]}
	for row: Array in [["01-yard-pit-interface",Vector3(-19,1.2,11.5),26.0],["02-yard-shore-connection",Vector3(4,2,22),26.0],["03-yard-complete-width",Vector3(-7,2,18),42.0]]:
		await _capture(str(row[0]),row[1],float(row[2]))
	_check(session.active and session._facilities_ready() and shape.get_faces().to_byte_array().size()>0,"actual session remains active after all views")
	_finish()

func _capture(label: String,at: Vector3,size: float) -> void:
	body.freeze=true
	body.global_transform=Transform3D(Basis.IDENTITY,at)
	PhysicsServer3D.body_set_state(body.get_rid(),PhysicsServer3D.BODY_STATE_TRANSFORM,body.global_transform)
	body.linear_velocity=Vector3.ZERO
	body.angular_velocity=Vector3.ZERO
	body.hold_height=at.y
	body.safe_position=at
	session.flight_camera.target_size=size
	session.camera.size=size
	session.flight_camera.snap(at)
	await physics_frame
	await physics_frame
	body.freeze=false
	await create_timer(.35).timeout
	await RenderingServer.frame_post_draw
	_check(root.get_texture().get_image().save_png(output+"/"+label+".png")==OK,"actual MAIN screenshot "+label)
	shots.append({"name":label,"declared_initial_pose":at,"player":body.global_position,"camera":session.camera.global_transform,"size":session.camera.size})

func _check(ok: bool,label: String,actual: Variant=null) -> bool:
	checks.append({"passed":ok,"label":label,"actual":actual})
	return ok

func _finish() -> void:
	if finished: return
	finished=true
	var failures:=checks.filter(func(row: Dictionary): return not row.passed)
	FileAccess.open(output+"/result.json",FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failures":failures,"engine_errors":logger.errors,"shots":shots,"scope":"Real normal MAIN / imported GLB / collision readback / three declared QA observation poses. No route, human, LAN, package or performance claim."},"\t"))
	print("I2_YARD_RESULT "+JSON.stringify({"checks":checks.size(),"failures":failures,"engine_errors":logger.errors}))
	quit(0 if failures.is_empty() and logger.errors.is_empty() else 1)
