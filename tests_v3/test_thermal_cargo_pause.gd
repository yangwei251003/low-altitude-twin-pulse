extends SceneTree
## Native request-pause boundary on the original Flight/Custody bodies.
## No callback replacement, transform write during pause, Store IO or LAN.
const BaseFixture = preload("res://tests_v3/test_thermal_cargo_session.gd")
const ProgressFixture = preload("res://tests_v3/test_thermal_cargo_progress.gd")
const CargoSession = preload("res://scripts/v3/gameplay/twin_thermal_cargo_session.gd")
const Flight = preload("res://scripts/v2/flight_body.gd")
const Catalog = preload("res://scripts/v2/catalog.gd")
const Pilot = preload("res://scripts/v3/candidates/canal_transport_physics/transport_pilot.gd")
const Store = preload("res://scripts/v3/core/twin_world_store.gd")
const DT := 1.0/60.0
var checks := 0
var failures := 0
var frames := 0
var finished := false
var fixture: Dictionary = {}

func _initialize() -> void:
	call_deferred("_run")

func _check(condition: bool,label: String) -> bool:
	checks += 1
	if not condition: failures += 1; push_error("THERMAL PAUSE: "+label)
	return condition

func _brake() -> Dictionary:
	return {"active":true,"mode":"assisted","body_relative":false,"planar":Vector3.ZERO,"vertical":0.0,"yaw":0.0,"brake":true,"fire":false}

func _setup() -> void:
	var viewport := SubViewport.new()
	viewport.world_3d = World3D.new()
	viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	root.add_child(viewport)
	var world := BaseFixture.FixtureWorld.new()
	viewport.add_child(world)
	var ground := StaticBody3D.new()
	ground.position.y = -.5
	ground.collision_layer = 1
	CargoSession._box(ground,Vector3(80,1,80),Color("394b55"))
	world.add_child(ground)
	var high := StaticBody3D.new()
	high.position = Vector3(17,10.8,-3)
	high.collision_layer = 1
	CargoSession._box(high,Vector3(6,.8,6),Color("71858e"))
	world.add_child(high)
	world._entity("loaded_cassette","Unique cargo",Vector3(-10,3,18),Vector3(1.5,1.5,1.5),["movable","fieldable"],{},Color("aa9772"))
	world._entity("high_dock","High berth",Vector3(17,11.2,-3),Vector3(1.5,1.5,1.5),["mechanical"],{},Color("71858e"))
	_check(CargoSession.install(world).ok,"single actual cargo installed")
	var session := ProgressFixture.ProgressSession.new()
	root.add_child(session)
	session.world = world
	session.entities = world.definitions.duplicate(true)
	var players: Array = []
	for peer in [1,2]:
		var body := Flight.new()
		body.configure(Catalog.resolve_build(Catalog.default_build("tr01")))
		body.max_altitude = 26.0
		world.add_child(body)
		body.global_position = Vector3(-10 if peer == 1 else -16,4.1,18)
		body.hold_height = body.global_position.y
		body.safe_position = body.global_position
		body.environment_query = world.sample_environment
		body.environment_sample = world.sample_environment(body.global_position)
		body.command = _brake()
		session.players[peer] = body
		session.identities[peer] = "pause-role-"+str(peer)
		players.append(body)
	var module := CargoSession.new()
	module.setup(session)
	_check(module.bind_world().ok,"two actual original players bind")
	fixture = {"viewport":viewport,"world":world,"session":session,"player":players[0],"other":players[1],"module":module}

func _frame(pilot = null) -> bool:
	await physics_frame
	if finished: return false
	frames += 1
	fixture.player.environment_sample = fixture.world.sample_environment(fixture.player.global_position)
	fixture.other.command = _brake()
	if pilot != null and fixture.module.status().assist.is_empty(): pilot.tick(DT,true,false)
	else: fixture.player.command = _brake()
	var result: Dictionary = fixture.module.advance(DT)
	return true if result.ok else _check(false,"ordinary native advance "+str(result)+" "+JSON.stringify(fixture.module.status()))

func _wait_pause(limit: int = 1200) -> bool:
	for _step in range(limit):
		if not await _frame(): return false
		var report: Dictionary = fixture.module.pause_request_status()
		if report.failed: return _check(false,"native pause failure "+str(report))
		if report.ready: return true
	return _check(false,"native pause request timeout "+JSON.stringify(fixture.module.status()))

func _store_candidate(state: Dictionary,label: String) -> bool:
	var valid: bool = Store.new()._tree_valid(state)
	return _check(valid,"original Store untouched "+label+": "+("valid" if valid else _bad_tree(state,"state")))

func _bad_tree(value,path: String) -> String:
	if value is Dictionary:
		for key in value:
			if not key is String: return path+" key="+str(key)+" type="+type_string(typeof(key))
			var bad := _bad_tree(value[key],path+"."+key)
			if not bad.is_empty(): return bad
	elif value is Array:
		for index in range(value.size()):
			var bad := _bad_tree(value[index],path+"["+str(index)+"]")
			if not bad.is_empty(): return bad
	elif not (value == null or value is bool or value is String or value is int or value is float): return path+" type="+type_string(typeof(value))
	return ""

func _hold_and_resume(expected_version: int) -> bool:
	var cached: Dictionary = fixture.module.paused_saved_state()
	if not _check(cached.ok and cached.state.version == expected_version,"pause cache retains original v"+str(expected_version)+" candidate"): return false
	if not _store_candidate(cached.state,"native pause candidate"): return false
	var snapshot_text: String = JSON.stringify(cached.state,"",true,true)
	var records: Array = fixture.module._pause_bodies.duplicate()
	var serial: int = int(fixture.module._custody.last_serial)
	var revision: int = int(fixture.module._custody.revision)
	var observed: int = int(fixture.module.status().journey.get("frames_observed",0))
	fixture.session.simulation_paused = true
	_check(fixture.module.set_paused(true).ok,"Consensus applies already-ready pause idempotently")
	for _step in range(6):
		if not await _frame(): return false
		for record in records:
			var body: RigidBody3D = record.body.get_ref()
			var pose: Transform3D = PhysicsServer3D.body_get_state(body.get_rid(),PhysicsServer3D.BODY_STATE_TRANSFORM)
			_check(body.freeze and pose.is_equal_approx(CargoSession._transform(record.physical.native_pose)),"paused original body holds its native pose")
	_check(int(fixture.module._custody.last_serial) == serial and int(fixture.module._custody.revision) == revision and int(fixture.module.status().journey.get("frames_observed",0)) == observed,"pause awards no serial/support/route-frame credit")
	_check(JSON.stringify(fixture.module.save_state().state,"",true,true) == snapshot_text,"saving while frozen returns original candidate, not cleared native velocity")
	var count: int = int(fixture.module.pause_request_status().resume_count)
	fixture.session.simulation_paused = false
	var resumed: Dictionary = fixture.module.set_paused(false)
	if not _check(resumed.ok,"resume actual original bodies: "+str(resumed)): return false
	for record in records:
		var body: RigidBody3D = record.body.get_ref()
		_check(not body.freeze and CargoSession._native_readback(body,record.physical),"resume restores original native linear/angular momentum exactly once without pose assignment")
	_check(int(fixture.module.pause_request_status().resume_count) == count+1,"one actual resume counted")
	if not await _frame(): return false
	var velocity: Vector3 = PhysicsServer3D.body_get_state(fixture.player.get_rid(),PhysicsServer3D.BODY_STATE_LINEAR_VELOCITY)
	_check(fixture.module.set_paused(false).ok and int(fixture.module.pause_request_status().resume_count) == count+1 and PhysicsServer3D.body_get_state(fixture.player.get_rid(),PhysicsServer3D.BODY_STATE_LINEAR_VELOCITY) == velocity,"repeated unpause cannot inject saved momentum again")
	return true

func _run() -> void:
	create_timer(35.0).timeout.connect(func():
		if not finished: _check(false,"35 second actual pause bound"); _finish())
	var unbound := CargoSession.new()
	_check(not unbound.request_pause().ok and not unbound.set_paused(true).ok,"unbound helper cannot claim a real pause")
	_setup()
	var docked := false
	for _step in range(240):
		if not await _frame(): _finish(); return
		if fixture.module._row().phase == "docked": docked = true; break
	if not _check(docked,"initial native 350ms support actually settles"): _finish(); return
	var docked_state: Dictionary = fixture.module.save_state()
	if not _check(docked_state.ok,"actual docked state captured") or not _store_candidate(docked_state.state,"docked candidate"): _finish(); return
	_check(fixture.module.request_pause().pending,"docked request waits for next ordinary physical boundary")
	if not await _wait_pause(): _finish(); return
	_check(not fixture.player.freeze and not fixture.other.freeze,"module freezes no unladen player; original Session owns global roster pause")
	if not await _hold_and_resume(1): _finish(); return
	print("THERMAL_PAUSE_STAGE actual_docked_pause_resume frames="+str(frames))
	var picked: Dictionary = fixture.module.operate(1,CargoSession.CARGO)
	if not _check(picked.ok and not fixture.module.status().assist.is_empty(),"G starts actual attached short departure"): _finish(); return
	_check(fixture.module.request_pause().pending,"pause requested during native short assistance")
	if not await _frame(): _finish(); return
	_check(fixture.module.pause_request_status().pending and not fixture.player.freeze and not fixture.world.objects[CargoSession.CARGO].freeze,"uncapturable assist continues real physics, no premature freeze or fabricated save")
	if not await _wait_pause(): _finish(); return
	_check(fixture.player.freeze and fixture.world.objects[CargoSession.CARGO].freeze and not fixture.other.freeze,"actual cargo and loaded original Flight freeze, unrelated player untouched")
	if not await _hold_and_resume(2): _finish(); return
	print("THERMAL_PAUSE_STAGE actual_assist_pause_resume frames="+str(frames))
	var pilot := Pilot.new()
	_check(pilot.bind(fixture.player) and pilot.go_to(Vector3(-8.2,5.2,18),1),"original Pilot begins actual short loaded flight")
	var start: Vector3 = fixture.player.global_position
	var moving := false
	for _step in range(600):
		if not await _frame(pilot): _finish(); return
		if fixture.player.global_position.distance_to(start) >= .8 and fixture.player.linear_velocity.length() >= .35: moving = true; break
	if not _check(moving,"load really flies before moving pause"): _finish(); return
	_check(fixture.module.request_pause().pending,"moving request waits for actual native boundary")
	if not await _wait_pause(): _finish(); return
	var moving_state: Dictionary = fixture.module.paused_saved_state()
	_check(CargoSession._vector(moving_state.state.carrier.native_velocity).length() >= .3,"moving pause cached real nonzero native momentum before freeze")
	if not await _hold_and_resume(2): _finish(); return
	var resumed_at: Vector3 = fixture.player.global_position
	for _step in range(15):
		if not await _frame(pilot): _finish(); return
	_check(fixture.player.global_position.distance_to(resumed_at) > .05 and fixture.player.cargo_kg == 2.0 and fixture.module.fact(CargoSession.FACT).is_empty(),"resumed real Joint continues native loaded flight without false delivery fact")
	print("THERMAL_PAUSE_STAGE actual_moving_pause_resume frames="+str(frames))
	_finish()

func _finish() -> void:
	if finished: return
	finished = true
	if not fixture.is_empty():
		fixture.module.clear()
		if is_instance_valid(fixture.viewport): fixture.viewport.free()
		if is_instance_valid(fixture.session): fixture.session.free()
	print("Thermal cargo pause: %d checks, %d failures, %d actual physics frames; native docked/assist/moving boundaries only, no Store IO, MAIN or LAN acceptance claim." % [checks,failures,frames])
	quit(0 if failures == 0 else 1)
