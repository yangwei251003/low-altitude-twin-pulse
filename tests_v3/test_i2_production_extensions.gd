extends SceneTree
## Actual MAIN, automatic production assembly and test-input flight.
## Region initialization and initial camera poses are explicit QA fixtures.
const MAIN=preload("res://scenes/v3/main.tscn")
const Pilot=preload("res://scripts/v3/candidates/canal_transport_physics/transport_pilot.gd")
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
	if not profile.begins_with("qa_i2_extensions_") or not output.begins_with("res://artifacts/v3/i2-production-") or ".." in output or DirAccess.dir_exists_absolute(output) or not OS.is_debug_build() or DisplayServer.get_name()=="headless":
		quit(2); return
	DirAccess.make_dir_recursive_absolute(output)
	create_timer(140).timeout.connect(func():
		if not finished: _check(false,"bounded MAIN route timeout"); _finish())
	root.size=Vector2i(1280,720)
	session=MAIN.instantiate()
	root.add_child(session)
	if not _check(session.profile_ready and session.start_flight("solo"),"actual MAIN starts isolated solo profile"): _finish(); return
	var previous_world: WeakRef=weakref(session.world)
	if not _check(session._load_region("I2"),"actual region loader builds I2 without historical action injection"): _finish(); return
	await physics_frame
	await physics_frame
	var world: Node3D=session.world
	_check(previous_world.get_ref()==null,"ownership-only migration still disposes previous region; no background retention claim")
	_check(session._region_space.status().ok and world.get_parent()==session._region_space.viewport and world.get_world_3d()==session.camera.get_world_3d(),"normal MAIN presents the region's stable space through its original camera")
	_check(PhysicsServer3D.body_get_space(session.players[1].get_rid())==world.get_world_3d().space,"MAIN player actually joins the selected region physics space")
	_check(session._region_space.viewport.get_camera_3d()==null and session._region_space.status().render_disabled,"region owner does not add a second render pass")
	_check(session.ecology.view.view_camera==session.camera,"ecology labels use the actual main camera")
	var signs_bound:=false
	for node: Node in world.trial.station.get_children():
		if node is TwinTrialFlowPresentation: signs_bound=node.camera==session.camera
	_check(signs_bound,"trial receiver labels use the actual main camera")
	if not _check(world.build_errors.is_empty() and session._facilities_ready(),"four production facilities ready",world.build_errors): _finish(); return
	if not _check(world.revetment_closure_art.get("ok",false) and world.inspection_pit.get("ok",false) and world.inspection_pit_art.get("ok",false),"World automatically installs production closure and physical authored pit"): _finish(); return
	_check(session.network.PROTOCOL==21,"changed collision requires protocol21")
	_check(world.revetment_closure_art.model.scene_file_path=="res://assets/v3/environment/i2_revetment_closure/revetment_closure.glb" and world.inspection_pit_art.model.scene_file_path=="res://assets/v3/environment/inspection_pit/inspection_pit.glb","live meshes use production import paths")
	_check(world.revetment_closure_art.triangles==32122 and world.inspection_pit_art.triangles==19640,"actual imported triangle contracts")
	var ground: StaticBody3D=world.waterfront_install.ground
	var shape: ConcavePolygonShape3D=world.waterfront_install.shape_node.shape
	var faces:=shape.get_faces().to_byte_array()
	_check(ground==world.clinic.fixed_bodies.Ground and world.inspection_pit.ground==ground,"single original Ground owns the physical cut")
	var exclude: Array[RID]=[]
	for node: Node in world.find_children("*","CollisionObject3D",true,false):
		if node!=ground: exclude.append(node.get_rid())
	var space:=world.get_world_3d().direct_space_state
	for at: Vector3 in [Vector3(-19,-2.4,2.7),Vector3(-19,-1.2,7.25),Vector3(-19,0,11.5),Vector3(14.75,-2.8,15)]:
		var hit:=space.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(at.x,2,at.z),Vector3(at.x,-3,at.z),1,exclude))
		_check(not hit.is_empty() and absf(hit.position.y-at.y)<.00002,"real floor/ramp/yard/channel ray",{"expected":at,"actual":hit.get("position")})
	body=session.players[1]
	session.inputs.test_enabled=true
	session.flight_camera.target_size=26
	# This single setup pose is not flight evidence. Everything until return is
	# actual test-frame -> PilotInput -> host -> real body; no subsequent pose writes.
	await _pose(Vector3(-19,1.2,11.5))
	await _capture("01-main-pit-entry")
	var pilot=Pilot.new()
	if not _check(pilot.bind(body),"route controller binds actual MAIN player"): _finish(); return
	var input_before: int=session.stats.inputs
	var clock_before: float=world.clock_seconds
	var serial:=0
	for target: Vector3 in [Vector3(-19,1.2,10.2),Vector3(-19,-1.2,4),Vector3(-19,-1.2,2.7),Vector3(-19,-1.2,4),Vector3(-19,1.2,10.2),Vector3(-19,1.2,11.5)]:
		serial+=1
		pilot.go_to(target,serial)
		var report: Dictionary={}
		var arrived:=false
		for frame in 1500:
			await physics_frame
			if finished: return
			report=pilot.tick(1.0/60,true,false)
			var command: Dictionary=body.command.duplicate(true)
			# Convert desired world motion back through the normal camera input axes.
			var right: Vector3=session.camera.global_basis.x; right.y=0; right=right.normalized()
			var forward: Vector3=-session.camera.global_basis.z; forward.y=0; forward=forward.normalized()
			var planar: Vector3=command.planar
			session.inputs.test_frame={"axes":{"right_x":planar.dot(right),"right_y":planar.dot(forward),"left_y":command.vertical,"left_x":0.0},"held":["brake"] if command.brake else []}
			if report.get("arrived",false): arrived=true; break
		if not _check(arrived and body.collision_count==0 and body.health==100,"normal session input route leg "+str(serial)+" without impact",{"position":body.global_position,"report":report,"health":body.health,"collisions":body.collision_count}): _finish(); return
		if serial==3: await _capture("02-main-below-yard")
	_check(session.stats.inputs>input_before+100 and world.clock_seconds>clock_before+1,"normal host input and world clock kept advancing",{"inputs":session.stats.inputs-input_before,"seconds":world.clock_seconds-clock_before})
	_check(ground.get_rid()==world.clinic.fixed_bodies.Ground.get_rid() and shape.get_faces().to_byte_array()==faces,"flight leaves authored physical cut unchanged")
	await _capture("03-main-pit-return")
	# Separate frozen observation fixtures, not extensions of the flown route.
	await _pose(Vector3(17,1.2,25))
	await _capture("04-main-shore-mouth")
	await _pose(Vector3(14.75,1.2,3))
	session.flight_camera.zoom(3)
	for frame in 50: await process_frame
	await _capture("05-main-north-joint")
	_check(session.active and session._facilities_ready(),"MAIN remains active with facilities ready")
	_finish()

func _pose(at: Vector3) -> void:
	body.freeze=true
	body.global_transform=Transform3D(Basis.IDENTITY,at)
	# A direct Node pose can be overwritten by the pending RigidBody server sync.
	# Explicit QA placements must agree with the real server before resuming.
	PhysicsServer3D.body_set_state(body.get_rid(),PhysicsServer3D.BODY_STATE_TRANSFORM,body.global_transform)
	body.linear_velocity=Vector3.ZERO
	body.angular_velocity=Vector3.ZERO
	body.hold_height=at.y
	body.safe_position=at
	session.inputs.test_frame={"held":["brake"]}
	session.flight_camera.snap(at)
	await physics_frame
	await physics_frame
	_check(body.global_position.distance_to(at)<.001,"explicit QA observation pose actually adopted",{"expected":at,"actual":body.global_position})
	body.freeze=false

func _capture(name: String) -> void:
	# Allow the normal 120ms HUD cadence; do not manually refresh its values.
	await create_timer(.25).timeout
	await process_frame
	await RenderingServer.frame_post_draw
	_check(root.get_texture().get_image().save_png(output+"/"+name+".png")==OK,"actual MAIN screenshot "+name)
	_check(session.interface.vitals.text.contains("高度 %.1fm" % body.global_position.y),"normal HUD reports actual current height "+name,{"text":session.interface.vitals.text,"position":body.global_position,"hud_clock":session.hud_clock})
	shots.append({"name":name,"player":body.global_position,"camera":session.camera.global_transform,"size":session.camera.size,"input_frame":session.inputs.last_frame,"vitals":session.interface.vitals.text})

func _check(ok: bool,label: String,actual: Variant=null) -> bool:
	checks.append({"passed":ok,"label":label,"actual":actual})
	return ok

func _finish() -> void:
	if finished: return
	finished=true
	var failures:=checks.filter(func(row: Dictionary): return not row.passed)
	var result: Dictionary={"checks":checks,"failures":failures,"engine_errors":logger.errors,"shots":shots,"scope":"Actual MAIN production assembly, initial QA pose and test-input route, normal host/wind/camera/HUD; two separate QA shoreline observation poses. No human, full action, LAN, packaged or performance claim."}
	FileAccess.open(output+"/result.json",FileAccess.WRITE).store_string(JSON.stringify(result,"\t"))
	print("I2_PRODUCTION_RESULT "+JSON.stringify({"checks":checks.size(),"failures":failures,"engine_errors":logger.errors}))
	quit(0 if failures.is_empty() and logger.errors.is_empty() else 1)
