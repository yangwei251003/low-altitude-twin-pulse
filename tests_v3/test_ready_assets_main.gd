extends SceneTree
## Two bounded actual MAIN GPU views. QA poses and direct region loads are
## declared observation shortcuts, not a campaign route or human playtest.
const MAIN = preload("res://scenes/v3/main.tscn")
const Stone = preload("res://scripts/v3/art/twin_f1_thermal_stone_art.gd")
const Apron = preload("res://scripts/v3/art/twin_central_service_apron_art.gd")
const GROUND_SHA := "d665779e1312e2783a2992ab30538164394a3d7d31e76fa8221ba242d9e709fc"
class ErrorLogger extends Logger:
	var guard := Mutex.new()
	var errors: Array = []
	func _log_error(function: String,file: String,line: int,code: String,rationale: String,_notify: bool,kind: int,_trace: Array[ScriptBacktrace]) -> void:
		if kind == Logger.ERROR_TYPE_WARNING: return
		guard.lock()
		errors.append({"function":function,"file":file,"line":line,"code":code,"rationale":rationale})
		guard.unlock()
var logger := ErrorLogger.new()
var session: Node
var pilot: FlightBodyV2
var output := ""
var checks: Array = []
var shots: Array = []
var finished := false

func _initialize() -> void:
	OS.add_logger(logger)
	_run.call_deferred()

func _run() -> void:
	var profile := ""
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--output="): output = arg.trim_prefix("--output=")
		if arg.begins_with("--qa-profile="): profile = arg.trim_prefix("--qa-profile=")
	if not profile.begins_with("qa_ready_assets_") or not output.begins_with("res://artifacts/v3/ready-assets-") or ".." in output or DirAccess.dir_exists_absolute(output) or DisplayServer.get_name()=="headless":
		quit(2)
		return
	DirAccess.make_dir_recursive_absolute(output)
	create_timer(45).timeout.connect(func():
		if not finished:
			_check(false,"bounded MAIN asset check")
			_finish())
	root.size = Vector2i(1280,720)
	session = MAIN.instantiate()
	root.add_child(session)
	if not _check(session.profile_ready and session.start_flight("solo") and session._load_region("I2"),"actual MAIN opens isolated solo and native I2"):
		_finish()
		return
	await physics_frame
	await physics_frame
	session.set_physics_process(false)
	session.inputs.test_enabled = true
	session.inputs.test_frame = {"held":[],"edges":[],"axes":{}}
	pilot = session.players[1]
	pilot.freeze = true
	pilot.set_physics_process(false)
	if not _check(session.world.build_errors.is_empty() and session._facilities_ready(),"I2 has no World build errors and existing facilities ready",session.world.build_errors):
		_finish()
		return
	var world: Node3D = session.world
	var apron: Dictionary = world.central_service_apron_art
	if not _check(apron.get("ok",false),"native MAIN installed new apron",apron.get("code")):
		_finish()
		return
	_check(apron.model.scene_file_path==Apron.MODEL_PATH and apron.model.position.is_equal_approx(Apron.ORIGIN) and apron.triangles==1148 and apron.meshes.size()==3,"explicit apron GLB and crop origin")
	var ground: StaticBody3D = world.waterfront_install.ground
	var shape_node: CollisionShape3D = world.waterfront_install.shape_node
	var shape := shape_node.shape as ConcavePolygonShape3D
	if not _check(shape!=null and ground==world.clinic.fixed_bodies.Ground and Apron.Split._sha(shape.get_faces().to_byte_array())==GROUND_SHA,"original Ground body and collision bytes preserved"):
		_finish()
		return
	var rid := ground.get_rid()
	var shape_id := shape.get_instance_id()
	var exclusions: Array[RID] = []
	for node: Node in world.find_children("*","CollisionObject3D",true,false):
		if node!=ground: exclusions.append(node.get_rid())
	var top := world.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(-4.75,2,1),Vector3(-4.75,-1,1),1,exclusions))
	_check(top.get("collider")==ground and absf(top.get("position",Vector3.INF).y)<.00003,"actual repair-zone Ground ray remains Y0",top.get("position"))
	var raw: Dictionary = Apron.Reader._read_mesh(world.waterfront_install.meshes.dry_surface.mesh)
	_check(raw.ok and absf(Apron.Split._area(raw.geometry)-1640.99582077)<.0005,"actual visible Ground is exact complementary surface")
	await _capture("01-I2-apron-default",Vector3(-3,3,2))
	if finished: return
	_check(ground.get_rid()==rid and shape_node.shape.get_instance_id()==shape_id and Apron.Split._sha(shape.get_faces().to_byte_array())==GROUND_SHA,"camera observation preserves original Ground identity and shape")
	if not _check(session._load_region("F1"),"same native MAIN loads F1"):
		_finish()
		return
	await physics_frame
	await physics_frame
	world = session.world
	if not _check(world.build_errors.is_empty(),"F1 World built without errors",world.build_errors):
		_finish()
		return
	var stone: Node3D = world.art_thermal
	if not _check(is_instance_valid(stone) and stone.imported and stone.import_errors.is_empty(),"native MAIN imported thermal stone",stone.import_errors if is_instance_valid(stone) else null):
		_finish()
		return
	var body: StaticBody3D = world.objects["F1:thermal"]
	var shapes := body.find_children("*","CollisionShape3D",false,false)
	if not _check(shapes.size()==1 and shapes[0].shape is BoxShape3D,"original single thermal box shape"):
		_finish()
		return
	var box: CollisionShape3D = shapes[0]
	var original_rid := body.get_rid()
	var original_shape_id: int = box.shape.get_instance_id()
	_check(body.position==Vector3(-29,1,8) and body.collision_layer==8 and body.collision_mask==11 and box.transform.is_equal_approx(Transform3D.IDENTITY) and box.shape.size==Vector3(3,2,2),"original thermal pose, filters and 3x2x2 collision")
	_check(stone.get_parent()==body and stone.position==Vector3(0,-1,0) and stone.visual.scene_file_path==Stone.MODEL_PATH and not body.get_node("Shape").visible,"visual-only child replaces hidden placeholder at bottom origin")
	var thermal_top := world.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(-29,3,8),Vector3(-29,0,8),8))
	_check(thermal_top.get("collider")==body and is_equal_approx(thermal_top.get("position",Vector3.INF).y,2),"actual thermal box top remains 2m",thermal_top.get("position"))
	await _place(Vector3(-29,4,12))
	var core := stone.visual.find_child("TemperatureCore",true,false) as MeshInstance3D
	var mass := stone.visual.find_child("StoneBody",true,false) as MeshInstance3D
	if not _check(core!=null and mass!=null,"imported core and stone material groups exist"):
		_finish()
		return
	var core_mat := core.get_active_material(0) as BaseMaterial3D
	var stone_mat := mass.get_active_material(0) as BaseMaterial3D
	var unchanged_stone := stone_mat.albedo_color
	world.synchronize(session.entities,0.0)
	var cold := core_mat.albedo_color
	_check(is_equal_approx(float(session.entities["F1:thermal"].temperature),20),"fresh QA thermal state starts at 20")
	_heat("")
	var warm := core_mat.albedo_color
	_check(is_equal_approx(float(session.entities["F1:thermal"].temperature),45) and warm!=cold,"actual heat rule 20 to 45 updates core material")
	_heat("")
	var hot := core_mat.albedo_color
	_check(is_equal_approx(float(session.entities["F1:thermal"].temperature),70) and hot!=warm and bool(session.entities["F1:thermal"].powered),"actual heat rule 45 to 70 updates core and real powered state")
	await _capture("02-F1-thermal-default",Vector3(-29,4,12))
	if finished: return
	_heat("cool")
	_check(is_equal_approx(float(session.entities["F1:thermal"].temperature),45) and core_mat.albedo_color.is_equal_approx(warm) and not bool(session.entities["F1:thermal"].powered),"actual cooling restores retained 45 degree material and powered false")
	_check(stone_mat.albedo_color==unchanged_stone and body.get_rid()==original_rid and box.shape.get_instance_id()==original_shape_id and box.shape.size==Vector3(3,2,2),"temperature and camera preserve stone base material and original collision identity")
	_finish()

func _heat(mode: String) -> void:
	# This bounded art check bypasses cooldown waiting only. The production
	# action, LOS, range, energy, thermal rule and presentation are unchanged.
	session.cooldowns[1] = 0.0
	session._action_received(1,"ability",{"ability":"heat","target_id":"F1:thermal","mode":mode})
	session.world.synchronize(session.entities,0.0)

func _place(at: Vector3) -> void:
	pilot.global_transform = Transform3D(Basis.IDENTITY,at)
	pilot.force_update_transform()
	PhysicsServer3D.body_set_state(pilot.get_rid(),PhysicsServer3D.BODY_STATE_TRANSFORM,pilot.global_transform)
	pilot.linear_velocity = Vector3.ZERO
	pilot.angular_velocity = Vector3.ZERO
	pilot.hold_height = at.y
	await physics_frame
	await physics_frame

func _capture(label: String,at: Vector3) -> void:
	await _place(at)
	var hull := pilot.get_node("Envelope") as CollisionShape3D
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = hull.shape
	query.transform = pilot.global_transform*hull.transform
	query.collision_mask = 1|8|32
	query.exclude = [pilot.get_rid()]
	query.margin = .002
	var hits := pilot.get_world_3d().direct_space_state.intersect_shape(query,8)
	if not _check(hits.is_empty(),"QA aircraft hull clear: "+label,hits.map(func(row: Dictionary): return str(row.collider.get_path()))):
		_finish()
		return
	session.flight_camera.target_size = 26
	session.camera.size = 26
	session.flight_camera.snap(at)
	session.interface.vitals.text = "源码实际MAIN视口 · QA观察摆位 · 非真人试玩"
	await create_timer(.45).timeout
	await RenderingServer.frame_post_draw
	var frame := root.get_texture().get_image()
	_check(frame!=null and not frame.is_empty() and frame.save_png(output+"/"+label+".png")==OK,"actual 1280x720 default 26m MAIN image: "+label)
	shots.append({"name":label,"qa_pose":at,"camera_size":session.camera.size,"camera_transform":session.camera.global_transform,"region":session.region_id})

func _check(ok: bool,label: String,actual: Variant=null) -> bool:
	checks.append({"passed":ok,"label":label,"actual":actual})
	return ok

func _finish() -> void:
	if finished: return
	finished = true
	var failures := checks.filter(func(row: Dictionary): return not row.passed)
	FileAccess.open(output+"/result.json",FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failures":failures,"engine_errors":logger.errors,"shots":shots,"scope":"Actual MAIN GPU/default fixed-oblique 26m camera; two QA observation poses, direct native I2/F1 region loads, production import and original collision readback, real heat/cool action with QA cooldown reset. Not keyboard traversal, campaign progression, human comfort, performance, package or LAN evidence."},"\t"))
	print("READY_ASSETS_MAIN_RESULT "+JSON.stringify({"checks":checks.size(),"failures":failures,"engine_errors":logger.errors}))
	quit(0 if failures.is_empty() and logger.errors.is_empty() else 1)
