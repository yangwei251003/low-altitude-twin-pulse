extends SceneTree
## One original Flight/Custody load really flies the route using original Pilot.
## Only initial spawn and declared fresh save reconstruction assign poses.
## No Store/profile, copied ledger, simulated docking credit, or LAN claim.
const CargoSession = preload("res://scripts/v3/gameplay/twin_thermal_cargo_session.gd")
const Flight = preload("res://scripts/v2/flight_body.gd")
const Catalog = preload("res://scripts/v2/catalog.gd")
## Historical isolated fixture keeps its candidate Pilot; not current MAIN evidence.
const Pilot = preload("res://scripts/v3/candidates/canal_transport_physics/transport_pilot.gd")
const Store = preload("res://scripts/v3/core/twin_world_store.gd")
const DT := 1.0/60.0
var checks := 0
var failures := 0
var finished := false
var fixtures: Array = []
var pilot_serial := 0
var actual_updraft_seen := false
var frames := 0

class FixtureNetwork:
	extends RefCounted
	func is_authority() -> bool: return true

class FixtureSession:
	extends Node
	var world
	var players: Dictionary = {}
	var entities: Dictionary = {}
	var region_id := "I3"
	var active := true
	var simulation_paused := false
	var network = FixtureNetwork.new()

class FixtureWorld:
	extends Node3D
	var region_id := "I3"
	var objects: Dictionary = {}
	var definitions: Dictionary = {}
	var initial_transforms: Dictionary = {}
	var _labels: Array = []
	var _base_object_materials: Dictionary = {}
	func _label(parent: Node3D,text: String,at: Vector3,tint: Color,size = 24) -> void:
		var label := Label3D.new()
		label.font = load("res://assets/fonts/NotoSansSC-Medium.ttf")
		label.text = text
		label.font_size = size
		label.pixel_size = .018
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		label.modulate = tint
		label.outline_size = 4
		parent.add_child(label)
		label.position = at
		label.visible = false
		_labels.append(label)
	func _entity(key: String,title: String,at: Vector3,size: Vector3,tags: Array,properties: Dictionary,tint: Color,_dynamic = false) -> void:
		var id := "I3:"+key
		var body := StaticBody3D.new()
		body.name = key
		body.position = at
		body.collision_layer = 8
		body.collision_mask = 1|2|8
		body.set_meta("entity_id",id)
		CargoSession._box(body,size,tint)
		add_child(body)
		objects[id] = body
		initial_transforms[id] = body.transform
		var state := {"id":id,"name":title,"position":at,"tags":tags,"owner":"neutral","revision":0}
		state.merge(properties,true)
		definitions[id] = state
	func sample_environment(_at: Vector3) -> Dictionary:
		return {"wind_velocity":Vector3.ZERO,"water":false,"water_height":-1000.0,"nav_quality":1.0,"compass_quality":1.0}

func _initialize() -> void:
	call_deferred("_run")

func _check(condition: bool,label: String) -> bool:
	checks += 1
	if not condition:
		failures += 1
		push_error("THERMAL CARGO: "+label)
	return condition

func _fixture(label: String) -> Dictionary:
	var viewport := SubViewport.new()
	viewport.name = label
	viewport.world_3d = World3D.new()
	viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	root.add_child(viewport)
	var world := FixtureWorld.new()
	viewport.add_child(world)
	var ground := StaticBody3D.new()
	ground.name = "Ground"
	ground.position.y = -.5
	ground.collision_layer = 1
	CargoSession._box(ground,Vector3(80,1,80),Color("394b55"))
	world.add_child(ground)
	var high_support := StaticBody3D.new()
	high_support.name = "ActualHighPad"
	high_support.position = Vector3(17,10.8,-3)
	high_support.collision_layer = 1
	CargoSession._box(high_support,Vector3(6,.8,6),Color("71858e"))
	world.add_child(high_support)
	world._entity("loaded_cassette","Original unique placeholder",Vector3(-10,3,18),Vector3(1.5,1.5,1.5),["movable","fieldable"],{},Color("aa9772"))
	world._entity("high_dock","Original high placeholder",Vector3(17,11.2,-3),Vector3(1.5,1.5,1.5),["mechanical"],{},Color("71858e"))
	var installed: Dictionary = CargoSession.install(world)
	_check(installed.ok,"unique physical cargo install: "+str(installed.get("code","")))
	var session := FixtureSession.new()
	root.add_child(session)
	session.world = world
	session.entities = world.definitions.duplicate(true)
	var player := Flight.new()
	player.name = "ActualPlayer"
	player.configure(Catalog.resolve_build(Catalog.default_build("tr01")))
	player.max_altitude = 26.0
	world.add_child(player)
	player.global_position = Vector3(-10,4.1,18)
	player.hold_height = player.global_position.y
	player.safe_position = player.global_position
	player.environment_hazards_authoritative = true
	player.environment_query = world.sample_environment
	player.environment_sample = world.sample_environment(player.global_position)
	player.command = _brake()
	session.players[1] = player
	var module = CargoSession.new()
	module.setup(session)
	var bound: Dictionary = module.bind_world()
	_check(bound.ok,"original player binds native Custody: "+str(bound.get("code","")))
	var result := {"viewport":viewport,"world":world,"session":session,"player":player,"module":module,"bound":bound.ok}
	fixtures.append(result)
	return result

func _brake() -> Dictionary:
	return {"active":true,"mode":"assisted","body_relative":false,"planar":Vector3.ZERO,"vertical":0.0,"yaw":0.0,"brake":true,"fire":false}

func _stage(label: String,fixture: Dictionary) -> void:
	var cargo: RigidBody3D = fixture.world.objects[CargoSession.CARGO]
	var info: Dictionary = fixture.module._custody.release_info(CargoSession.CARGO,CargoSession.HIGH)
	print("THERMAL_STAGE "+JSON.stringify({"stage":label,"frames":frames,"player_position":CargoSession._xyz(fixture.player.global_position),
		"player_speed":fixture.player.linear_velocity.length(),"cargo_speed":cargo.linear_velocity.length(),"cargo_angular_speed":cargo.angular_velocity.length(),
		"assist":fixture.module.status().assist,"custody":fixture.module.status().custody,"high_release":info},"",true,true))

func _capture_high_arrival(fixture: Dictionary) -> void:
	# Diagnostic only: this phase-one record is NOT a restorable carried save.
	# Capture the event-time native state rather than comparing a moving host
	# later against an old packet. Phase two owns validated reconstruction.
	var cargo: RigidBody3D = fixture.world.objects[CargoSession.CARGO]
	var player: Flight = fixture.player
	var joint: PinJoint3D = player.cargo_items[CargoSession.CARGO].joint
	var capture := {"diagnostic_only":true,"restorable":false,"frame":Engine.get_physics_frames(),"status":fixture.module.status(),
		"player_pose":CargoSession._pose(player.global_transform),"cargo_pose":CargoSession._pose(cargo.global_transform),
		"native_player_pose":CargoSession._pose(PhysicsServer3D.body_get_state(player.get_rid(),PhysicsServer3D.BODY_STATE_TRANSFORM)),
		"native_cargo_pose":CargoSession._pose(PhysicsServer3D.body_get_state(cargo.get_rid(),PhysicsServer3D.BODY_STATE_TRANSFORM)),
		"player_velocity":CargoSession._xyz(player.linear_velocity),"cargo_velocity":CargoSession._xyz(cargo.linear_velocity),
		"player_angular_velocity":CargoSession._xyz(player.angular_velocity),"cargo_angular_velocity":CargoSession._xyz(cargo.angular_velocity),
		"native_joint_a":CargoSession._xyz(PhysicsServer3D.pin_joint_get_local_a(joint.get_rid())),
		"native_joint_b":CargoSession._xyz(PhysicsServer3D.pin_joint_get_local_b(joint.get_rid())),"grip":fixture.module._custody.grip_info(CargoSession.CARGO)}
	var path := "res://artifacts/v3/thermal_cargo_arrival_"+str(Time.get_unix_time_from_system()).replace(".","_")+".json"
	var file := FileAccess.open(path,FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(capture,"\t",true,true))
		file.close()
		print("THERMAL_ARRIVAL_DIAGNOSTIC "+path)

func _frame(fixture: Dictionary,pilot = null) -> bool:
	await physics_frame
	if finished: return false
	frames += 1
	var body = fixture.player
	body.environment_sample = fixture.world.sample_environment(body.global_position)
	if pilot != null and fixture.module.status().assist.is_empty(): pilot.tick(DT,true,false)
	else: body.command = _brake()
	var advanced: Dictionary = fixture.module.advance(DT)
	if not advanced.ok:
		_check(false,"actual frame rejected "+str(advanced)+" "+JSON.stringify(fixture.module.status()))
		return false
	var force: Vector3 = body.telemetry.get("environment_acceleration",Vector3.ZERO)
	if force.y > 1.0 and body.cargo_items.has(CargoSession.CARGO): actual_updraft_seen = true
	return true

func _wait_docked(fixture: Dictionary,berth: String,limit: int = 240) -> bool:
	for _step in range(limit):
		if not await _frame(fixture): return false
		var row: Dictionary = fixture.module.status().custody.cargos[CargoSession.CARGO]
		if row.phase == "docked" and row.berth == berth and fixture.module.ready: return true
	return _check(false,"actual stable dock timeout "+berth+" "+JSON.stringify(fixture.module.status()))

func _wait_assist(fixture: Dictionary) -> bool:
	for _step in range(1200):
		if not await _frame(fixture): return false
		if fixture.module.status().assist.is_empty(): return true
	return _check(false,"bounded native DockLift assistance timeout")

func _fly(fixture: Dictionary,point: Vector3) -> bool:
	var pilot = Pilot.new()
	pilot_serial += 1
	if not _check(pilot.bind(fixture.player) and pilot.go_to(point,pilot_serial),"original Pilot receives real test route waypoint "+str(point)): return false
	for _step in range(2400):
		if not await _frame(fixture,pilot): return false
		if pilot.report().arrived:
			fixture.player.command = _brake()
			return true
	return _check(false,"real flight waypoint timeout "+str(point)+" position="+str(fixture.player.global_position)+" pilot="+JSON.stringify(pilot.report())+" cargo="+JSON.stringify(fixture.module.status()))

func _run() -> void:
	create_timer(115.0).timeout.connect(func():
		if not finished:
			_check(false,"115 second actual-flight bound")
			_finish())
	var host: Dictionary = _fixture("ThermalCargoActualFlight")
	if not host.bound: _finish(); return
	var body_identity: int = host.world.objects[CargoSession.CARGO].get_instance_id()
	_check(host.world.objects[CargoSession.CARGO] is RigidBody3D and host.world.objects[CargoSession.CARGO].mass == 2.0,"same ID now owns one real 2kg body")
	_check(CargoSession.install(host.world).ok and host.world.objects[CargoSession.CARGO].get_instance_id() == body_identity,"install cannot create a second same-ID load")
	if not await _wait_docked(host,CargoSession.LOW): _finish(); return
	_stage("actual_low_support",host)
	var initial: Dictionary = host.module.save_state()
	if not _check(initial.ok,"real initial support produces native docked-only checkpoint"): _finish(); return
	_check(Store.new()._tree_valid(initial.state),"original Store accepts untouched actual docked candidate")
	_check(not host.module.operate(999,CargoSession.CARGO).ok,"unknown peer cannot attach cargo")
	_check(host.module.fact(CargoSession.FACT).is_empty(),"being near low dock is not delivery")
	var pickup: Dictionary = host.module.operate(1,CargoSession.CARGO)
	if not _check(pickup.ok,"normal G requests original physical pickup: "+str(pickup)): _finish(); return
	if not await _wait_assist(host): _finish(); return
	_stage("actual_pickup_departure",host)
	if not _check(host.player.cargo_items.has(CargoSession.CARGO),"actual original PinJoint carries load after local departure"): _finish(); return
	var item: Dictionary = host.player.cargo_items[CargoSession.CARGO]
	_check(item.body == host.world.objects[CargoSession.CARGO] and item.joint is PinJoint3D and item.joint.get_rid().is_valid(),"original body and live PhysicsServer Joint remain unique")
	_check(host.player.cargo_kg == 2.0 and int(item.body.collision_mask) == CargoSession.MASK,"real mass/list and full original cargo collision mask retained")
	_check(not host.module.save_state().ok,"legacy phase-one fixture without a stable profile identity cannot create a carried checkpoint")
	for point in CargoSession.OUTER:
		if not await _fly(host,point): _finish(); return
		_stage("outer_waypoint_"+str(point),host)
	_check(int(host.module.status().journey.outer_progress) == 3 and not host.module.status().journey.broken,"continuous actually flown outer waypoints observed while original Joint remains attached")
	_check(actual_updraft_seen,"crossing actual field during carried flight applied real original Flight acceleration")
	if not await _fly(host,Vector3(17,13.55,-3)): _finish(); return
	_stage("actual_high_arrival_before_G",host)
	_capture_high_arrival(host)
	var drop: Dictionary = host.module.operate(1,CargoSession.HIGH)
	if not _check(drop.ok,"normal G starts physically verified release/short approach: "+str(drop)): _finish(); return
	_stage("G_release_request_"+str(drop.code),host)
	var arrived := false
	for step in range(1200):
		if not await _frame(host): _finish(); return
		var row: Dictionary = host.module.status().custody.cargos[CargoSession.CARGO]
		if row.phase == "docked" and row.berth == CargoSession.HIGH:
			arrived = true
			break
		# A public input retry after native settling is allowed. It never sets pose,
		# custody phase, route flag, joint state or a completion receipt itself.
		if step > 0 and step % 120 == 0 and row.phase == "carried" and host.module.status().assist.is_empty(): host.module.operate(1,CargoSession.HIGH)
	if not _check(arrived,"actual high support/contact + native 350ms docking observed "+JSON.stringify(host.module.status())): _finish(); return
	_stage("actual_high_docked",host)
	_check(host.module.fact(CargoSession.FACT) == "outer_corridor","only native high-dock completion yields actual outer-route fact")
	_check(host.player.cargo_kg == 0.0 and host.player.cargo_items.is_empty(),"original release removes Joint and player load exactly once")
	_check(host.player.environment_acceleration == Vector3.ZERO,"leaving field and release restore original player acceleration")
	_check(host.player.collision_count == 0,"real route and local assistance caused no player collision")
	var saved: Dictionary = host.module.save_state()
	if not _check(saved.ok,"actual high dock captures supported checkpoint: "+str(saved.get("code",""))): _finish(); return
	var exact_release: int = int(saved.state.proof.release_serial)
	_check(exact_release == int(saved.state.custody.cargos[CargoSession.CARGO].completed_serial),"single native release and completed docking serial match")
	var restored: Dictionary = _fixture("ThermalCargoFreshRestore")
	if not restored.bound: _finish(); return
	var decoded: Dictionary = JSON.parse_string(JSON.stringify(saved.state,"",true,true))
	var bad: Dictionary = decoded.duplicate(true)
	bad.cargo_pose[9] += 4.0
	var before: Transform3D = restored.world.objects[CargoSession.CARGO].global_transform
	_check(not restored.module.restore_docked_state(bad).ok and restored.world.objects[CargoSession.CARGO].global_transform == before,"bad restore rejected before changing fresh body")
	_check(restored.module.restore_docked_state(decoded).ok and not restored.module.ready and restored.module.fact(CargoSession.FACT).is_empty(),"valid JSON restore still requires fresh actual support, no instant fact")
	if not await _wait_docked(restored,CargoSession.HIGH): _finish(); return
	_stage("fresh_high_support_restored",restored)
	_check(restored.module.fact(CargoSession.FACT) == "outer_corridor" and int(restored.module.status().custody.last_serial) == exact_release,"fresh contact restoration preserves original receipt without adding credit")
	_check(not restored.module.restore_docked_state(decoded).ok,"live bound history cannot be replaced by replaying restore")
	var teardown: Dictionary = _fixture("ThermalCargoOwnedCleanup")
	if not teardown.bound: _finish(); return
	_check(teardown.module.restore_docked_state(initial.state).ok,"initial real checkpoint can restore into third fresh world")
	if not await _wait_docked(teardown,CargoSession.LOW): _finish(); return
	_check(teardown.module.operate(1,CargoSession.CARGO).ok,"cleanup fixture uses actual native pickup")
	var kept: RigidBody3D = teardown.world.objects[CargoSession.CARGO]
	teardown.module.clear()
	_check(is_instance_valid(kept) and kept.get_parent() == teardown.world and teardown.player.cargo_items.is_empty() and teardown.player.cargo_kg == 0.0,"clear removes only owned Joint/list, preserves original World/player/cargo")
	_finish()

func _finish() -> void:
	if finished: return
	finished = true
	for fixture in fixtures:
		fixture.module.clear()
		if is_instance_valid(fixture.viewport): fixture.viewport.free()
		if is_instance_valid(fixture.session): fixture.session.free()
	print("Thermal cargo session: %d checks, %d failures, %d actual physics frames; one physically flown outer route; docked-only restoration. No normal MAIN, carried-save, disconnect, alternate updraft-route or LAN acceptance claim." % [checks,failures,frames])
	quit(0 if failures == 0 else 1)
