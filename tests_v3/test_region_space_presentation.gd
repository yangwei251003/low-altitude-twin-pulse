extends SceneTree
## Real renderer and production region geometry; isolated ownership experiment.
## Not MAIN travel, facility advancement, loading, save or network acceptance.
const Space = preload("res://scripts/v3/world/twin_region_space.gd")
const World = preload("res://scripts/v3/twin_test_world.gd")
const Capture = preload("res://scripts_tools/v3/capture_hud_visibility.gd")
var logger = Capture.CaptureLogger.new()
var checks: Array = []
var shots: Array = []
var output := ""
var finished := false
var initial_world: World3D
var camera: Camera3D
var rig = FlightCameraV22.new()
var pilot: FlightBodyV2
var regions: Dictionary = {}
var identities: Dictionary = {}

func _initialize() -> void:
	OS.add_logger(logger)
	_run.call_deferred()

func _run() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--output="): output = arg.trim_prefix("--output=")
	if not output.begins_with("res://artifacts/v3/region-space-") or ".." in output or DirAccess.dir_exists_absolute(output) or DisplayServer.get_name() == "headless":
		quit(2); return
	DirAccess.make_dir_recursive_absolute(output)
	create_timer(45).timeout.connect(func():
		if not finished: _check(false,"bounded presentation probe"); _finish())
	initial_world = root.find_world_3d()
	root.size = Vector2i(1280,720)
	for id: String in ["I2","I1"]:
		var owner = Space.new()
		root.add_child(owner)
		var world = World.new()
		if not _check(owner.mount(world).ok,"stable owner mounts "+id): _finish(); return
		world.build(id,{},true)
		if not _check(world.build_errors.is_empty(),"production geometry builds "+id,world.build_errors): _finish(); return
		regions[id] = owner
		identities[id] = _identity(world)
	_check(regions.I2.world.space != regions.I1.world.space,"regions have separate actual physics spaces")
	var unsupported := SubViewport.new()
	unsupported.own_world_3d = true
	root.add_child(unsupported)
	_check(not regions.I2.present_on(unsupported).ok,"unique-copy viewport is rejected")
	unsupported.free()
	# Match Session's Node3D actor parent; FlightBody adds its ground marker
	# beside itself and deliberately requires a spatial parent.
	var actor_root := Node3D.new()
	actor_root.name = "QAPlayerContext"
	root.add_child(actor_root)
	camera = Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	actor_root.add_child(camera)
	camera.current = true
	rig.configure(camera)
	rig.target_size = 26
	pilot = FlightBodyV2.new()
	pilot.name = "QAPlayerSameInstance"
	pilot.configure(CatalogV2.resolve_build(CatalogV2.default_build("tr01")))
	pilot.sandbox_rules = {"unlimited_power":true}
	pilot.max_altitude = 27
	actor_root.add_child(pilot)
	var player_instance: int = pilot.get_instance_id()
	var player_rid: RID = pilot.get_rid()
	var camera_instance: int = camera.get_instance_id()
	# A plain dynamic probe demonstrates the old space continues physics even
	# when no viewport renders it. It is a QA object, not shipped game content.
	var falling := RigidBody3D.new()
	falling.name = "QAOnlyBackgroundGravity"
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3.ONE * .2
	shape.shape = box
	falling.add_child(shape)
	regions.I2.region.add_child(falling)
	falling.position = Vector3(-24,16,23)
	var background_before := 0.0
	for index in 3:
		var id: String = "I1" if index == 1 else "I2"
		if not _check(regions[id].present_on(root).ok,"normal root viewport presents "+id): _finish(); return
		# These are explicit travel setup poses, never represented as flown legs.
		var spawn := Vector3(-18,2.5,32) if id == "I1" else Vector3(-19,1.2,11.5)
		pilot.global_position = spawn
		PhysicsServer3D.body_set_state(pilot.get_rid(),PhysicsServer3D.BODY_STATE_TRANSFORM,pilot.global_transform)
		pilot.linear_velocity = Vector3.ZERO
		pilot.hold_height = spawn.y
		pilot.safe_position = spawn
		pilot.environment_query = regions[id].region.sample_environment
		pilot.command = {"active":true,"mode":"assisted","body_relative":false,"planar":Vector3.ZERO,"vertical":0.0,"yaw":0.0,"brake":true,"fire":false}
		rig.snap(spawn)
		if index == 1: background_before = falling.position.y
		for frame in 45:
			await physics_frame
			if finished: return
			pilot.environment_sample = regions[id].region.sample_environment(pilot.global_position)
			rig.update(1.0/60,pilot.global_position,pilot.linear_velocity)
		_check(root.find_world_3d() == regions[id].world and camera.get_world_3d() == regions[id].world,"root camera shares selected existing world "+id)
		_check(PhysicsServer3D.body_get_space(pilot.get_rid()) == regions[id].world.space,"same player has actual destination physics space "+id)
		_check(pilot.get_instance_id() == player_instance and pilot.get_rid() == player_rid and camera.get_instance_id() == camera_instance,"player and camera instances preserved "+id)
		for key: String in regions:
			_check(regions[key].status().ok and regions[key].status().render_disabled and _identity(regions[key].region) == identities[key],"original region bodies remain in stable space "+key)
		if index == 1:
			_check(falling.position.y < background_before-.5,"unrendered I2 physics still advances",{"before_y":background_before,"after_y":falling.position.y})
		_check(pilot.health == 100 and pilot.collision_count == 0,"setup/braking incurs no hidden damage "+id)
		await RenderingServer.frame_post_draw
		if finished: return
		var path: String = output.path_join("%02d-%s-root-viewport.png" % [index+1,id])
		var frame_image := root.get_texture().get_image()
		_check(frame_image.save_png(path) == OK,"real root-viewport capture "+id)
		shots.append(path)
	_finish()

func _identity(world: Node3D) -> Dictionary:
	var result: Dictionary = {}
	for body: PhysicsBody3D in world.find_children("*","PhysicsBody3D",true,false):
		if str(body.name).begins_with("QAOnly"): continue
		result[str(world.get_path_to(body))] = [body.get_instance_id(),body.get_rid().get_id(),PhysicsServer3D.body_get_space(body.get_rid()).get_id()]
	return result

func _check(ok: bool, name: String, detail: Variant = null) -> bool:
	checks.append({"ok":ok,"name":name,"detail":detail})
	return ok

func _finish() -> void:
	if finished: return
	finished = true
	_check(logger.errors.is_empty(),"zero engine errors",logger.errors)
	var failed: Array = checks.filter(func(row: Dictionary) -> bool: return not row.ok)
	var file := FileAccess.open(output.path_join("result.json"),FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify({"passed":failed.is_empty(),"checks":checks,"failures":failed,"shots":shots,"scope":"root viewport/production geometry/stable physics owners; not MAIN/save/facility/network integration"},"\t"))
	if initial_world != null: root.world_3d = initial_world
	quit(0 if failed.is_empty() else 1)
