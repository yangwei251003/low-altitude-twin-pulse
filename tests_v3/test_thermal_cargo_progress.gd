extends SceneTree
## Short native moving-save/role-rebind fixture. Reuses phase-one physical
## World classes; does not rerun the 58-second outer route or invent credit.
const BaseFixture = preload("res://tests_v3/test_thermal_cargo_session.gd")
const CargoSession = preload("res://scripts/v3/gameplay/twin_thermal_cargo_session.gd")
const Flight = preload("res://scripts/v2/flight_body.gd")
const Catalog = preload("res://scripts/v2/catalog.gd")
const Pilot = preload("res://scripts/v3/candidates/canal_transport_physics/transport_pilot.gd")
const Store = preload("res://scripts/v3/core/twin_world_store.gd")
const DT := 1.0/60.0
const ROLE := "thermal-player-profile-fixture"
var checks := 0
var failures := 0
var frames := 0
var finished := false
var fixtures: Array = []

class ProgressSession:
	extends BaseFixture.FixtureSession
	var identities: Dictionary = {}

func _initialize() -> void:
	call_deferred("_run")

func _check(condition: bool,label: String) -> bool:
	checks += 1
	if not condition: failures += 1; push_error("THERMAL PROGRESS: "+label)
	return condition

func _spawn(fixture: Dictionary,peer: int,identity: String,at: Vector3) -> Flight:
	var body := Flight.new()
	body.name = "ActualRole_"+str(peer)
	body.configure(Catalog.resolve_build(Catalog.default_build("tr01")))
	body.max_altitude = 26.0
	fixture.world.add_child(body)
	body.global_position = at
	body.hold_height = at.y
	body.safe_position = at
	body.environment_query = fixture.world.sample_environment
	body.environment_sample = fixture.world.sample_environment(at)
	body.command = _brake()
	fixture.session.players[peer] = body
	fixture.session.identities[peer] = identity
	return body

func _fixture(label: String,peer: int) -> Dictionary:
	var viewport := SubViewport.new()
	viewport.name = label
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
	var high_pad := StaticBody3D.new()
	high_pad.position = Vector3(17,10.8,-3)
	high_pad.collision_layer = 1
	CargoSession._box(high_pad,Vector3(6,.8,6),Color("71858e"))
	world.add_child(high_pad)
	world._entity("loaded_cassette","Unique cargo",Vector3(-10,3,18),Vector3(1.5,1.5,1.5),["movable","fieldable"],{},Color("aa9772"))
	world._entity("high_dock","High berth",Vector3(17,11.2,-3),Vector3(1.5,1.5,1.5),["mechanical"],{},Color("71858e"))
	_check(CargoSession.install(world).ok,"real single-cargo install")
	var session := ProgressSession.new()
	root.add_child(session)
	session.world = world
	session.entities = world.definitions.duplicate(true)
	var fixture := {"viewport":viewport,"world":world,"session":session,"peer":peer}
	fixture.player = _spawn(fixture,peer,ROLE,Vector3(-10,4.1,18))
	fixture.module = CargoSession.new()
	fixture.module.setup(session)
	_check(fixture.module.bind_world().ok,"actual player plus profile identity binds")
	fixtures.append(fixture)
	return fixture

func _brake() -> Dictionary:
	return {"active":true,"mode":"assisted","body_relative":false,"planar":Vector3.ZERO,"vertical":0.0,"yaw":0.0,"brake":true,"fire":false}

func _frame(fixture: Dictionary,pilot = null) -> bool:
	await physics_frame
	if finished: return false
	frames += 1
	fixture.player.environment_sample = fixture.world.sample_environment(fixture.player.global_position)
	if pilot != null and fixture.module.status().assist.is_empty(): pilot.tick(DT,true,false)
	else: fixture.player.command = _brake()
	var result: Dictionary = fixture.module.advance(DT)
	return true if result.ok else _check(false,"native frame: "+str(result)+" "+JSON.stringify(fixture.module.status()))

func _wait(fixture: Dictionary,mode: String,limit: int) -> bool:
	for _step in range(limit):
		if not await _frame(fixture): return false
		var status: Dictionary = fixture.module.status()
		if mode == "docked" and status.custody.cargos[CargoSession.CARGO].phase == "docked" and fixture.module.ready: return true
		if mode == "assist" and status.assist.is_empty(): return true
	return _check(false,mode+" timeout "+JSON.stringify(fixture.module.status()))

func _unchanged(fixture: Dictionary,before: Dictionary) -> bool:
	return CargoSession._physical_tree_equal(before.cargo,CargoSession._body_snapshot(fixture.world.objects[CargoSession.CARGO])) and CargoSession._physical_tree_equal(before.carrier,CargoSession._body_snapshot(fixture.player)) and fixture.player.cargo_items.is_empty() and int(fixture.module._custody.last_serial) == 0

func _physical(fixture: Dictionary) -> Dictionary:
	return {"cargo":CargoSession._body_snapshot(fixture.world.objects[CargoSession.CARGO]),"carrier":CargoSession._body_snapshot(fixture.player)}

func _matches_momentum(fixture: Dictionary,saved: Dictionary) -> bool:
	for pair in [[fixture.player,saved.carrier],[fixture.world.objects[CargoSession.CARGO],saved.cargo]]:
		var actual: Dictionary = CargoSession._body_snapshot(pair[0])
		if not CargoSession._f32_equal(actual.native_velocity,pair[1].native_velocity) or not CargoSession._f32_equal(actual.native_angular_velocity,pair[1].native_angular_velocity): return false
		var pose: Transform3D = CargoSession._transform(actual.native_pose)
		var expected: Transform3D = CargoSession._transform(pair[1].native_pose)
		if not CargoSession._f32_equal(CargoSession._xyz(pose.origin),CargoSession._xyz(expected.origin)) or not pose.basis.is_equal_approx(expected.basis): return false
	return true

func _run() -> void:
	create_timer(45.0).timeout.connect(func():
		if not finished: _check(false,"45 second short moving-save bound"); _finish())
	var source := _fixture("NativeMovingSource",1)
	if not await _wait(source,"docked",240): _finish(); return
	_check(source.module.operate(1,CargoSession.CARGO).ok,"actual native pickup request")
	if not await _wait(source,"assist",1200): _finish(); return
	var pilot := Pilot.new()
	_check(pilot.bind(source.player) and pilot.go_to(Vector3(-8.2,5.2,18),1),"original Pilot starts short real flight")
	var start: Vector3 = source.player.global_position
	var moving := false
	for _step in range(600):
		if not await _frame(source,pilot): _finish(); return
		if source.player.global_position.distance_to(start) >= .8 and source.player.linear_velocity.length() >= .35:
			moving = true
			break
	if not _check(moving,"native cargo actually moves before capture"): _finish(); return
	var capture: Dictionary = source.module.save_state()
	if not _check(capture.ok,"native moving save accepted: "+str(capture.get("code",""))): _finish(); return
	_check(Store.new()._tree_valid(capture.state),"original Store accepts untouched actually sampled moving candidate")
	var saved: Dictionary = JSON.parse_string(JSON.stringify(capture.state,"",true,true))
	# Isolate this completed source branch after its actual moving capture.
	# These frozen source bodies are never used as restoration evidence.
	source.player.freeze = true
	source.world.objects[CargoSession.CARGO].freeze = true
	print("THERMAL_PROGRESS_STAGE moving_capture "+JSON.stringify({"frames":frames,"serial":saved.custody.last_serial,"velocity":saved.carrier.native_velocity,"cargo_velocity":saved.cargo.native_velocity,"role":saved.role_identity},"",true,true))
	_check(saved.version == 2 and saved.role_identity == ROLE and saved.joint.carrier_id == ROLE and saved.custody.row.carrier == ROLE,"stable profile replaces transient peer in all persisted ownership")
	_check(CargoSession.required_roles(saved).size() == 1 and CargoSession.required_roles(saved)[0].identity == ROLE,"Root obtains exact identity/build spawning hint")
	var restored := _fixture("IndependentFreshMovingRestore",7)
	var before: Dictionary = _physical(restored)
	var duplicate: Flight = _spawn(restored,8,ROLE,Vector3(-17,5,18))
	_check(not restored.module.restore_state(saved).ok and _unchanged(restored,before),"duplicate stable profile identity cannot select a carrier")
	restored.session.players.erase(8)
	restored.session.identities.erase(8)
	duplicate.free()
	for kind in ["role","shape","anchor","filter","momentum","serial"]:
		var bad: Dictionary = saved.duplicate(true)
		match kind:
			"role": bad.role_identity = "other-profile"
			"shape": bad.cargo.contract.size[0] += .1
			"anchor": bad.joint.local_a[0] += .4; bad.joint.grip.carrier_local[0] += .4
			"filter": bad.cargo.contract.mask = 1
			"momentum": bad.carrier.native_velocity[0] += .2
			"serial": bad.custody.row.serial = 0
		var rejected: Dictionary = restored.module.restore_state(bad)
		_check(not rejected.ok and _unchanged(restored,before),"corrupt "+kind+" rejected before native mutation: "+str(rejected.get("code","")))
	var result: Dictionary = restored.module.restore_state(saved)
	if not _check(result.ok,"JSON moving snapshot restores into same profile/new peer: "+str(result)): _finish(); return
	_check(_matches_momentum(restored,saved),"native pose/orientation and exact float32 linear/angular momentum restored before next step")
	_check(int(restored.module._custody.last_serial) == int(saved.custody.last_serial) and restored.player.cargo_kg == 2.0 and restored.player.cargo_items.size() == 1 and restored.module.fact(CargoSession.FACT).is_empty(),"actual one-joint load restored without pickup/docking fact or extra serial")
	var joint: PinJoint3D = restored.player.cargo_items[CargoSession.CARGO].joint
	_check(CargoSession._f32_equal(CargoSession._xyz(PhysicsServer3D.pin_joint_get_local_a(joint.get_rid())),saved.joint.local_a) and CargoSession._f32_equal(CargoSession._xyz(PhysicsServer3D.pin_joint_get_local_b(joint.get_rid())),saved.joint.local_b),"native local anchors read back exactly; historical Joint node is not a new anchor")
	_check(not restored.module.restore_state(saved).ok,"live carried state cannot be replaced by replay")
	# Live disconnect is captured before the old Flight is removed, then Root
	# may commit exactly this returned state through its ordinary Store envelope.
	var synchronous_probe: Dictionary = restored.module.save_state()
	print("THERMAL_PROGRESS_STAGE synchronous_capture_probe "+JSON.stringify({"ok":synchronous_probe.ok,"code":synchronous_probe.code,"diagnostic":restored.module.status().capture_diagnostic},"",true,true))
	var requested: Dictionary = restored.module.request_suspend_for_disconnect(7)
	if not _check(requested.ok and requested.pending and not restored.player.freeze,"process callback only registers capture, keeps original player alive/unfrozen"): _finish(); return
	var suspension: Dictionary = {}
	for _step in range(60):
		if not await _frame(restored): _finish(); return
		suspension = restored.module.disconnect_state()
		if suspension.ok: break
	if not _check(suspension.get("ok",false),"next native boundary captures and freezes actual disconnect role: "+JSON.stringify(suspension)+" "+JSON.stringify(restored.module.status().capture_diagnostic)): _finish(); return
	print("THERMAL_PROGRESS_STAGE disconnect_boundary_captured "+JSON.stringify({"frames":frames,"serial":suspension.state.custody.last_serial}))
	_check(restored.world.objects[CargoSession.CARGO].freeze and not restored.module.ready and int(restored.module._custody.last_serial) == int(saved.custody.last_serial),"suspended role remains actual frozen cargo and gives no credit")
	var old_player: Flight = restored.player
	restored.session.players.erase(7)
	restored.session.identities.erase(7)
	old_player.free()
	restored.peer = 19
	restored.player = _spawn(restored,19,"other-profile",Vector3(-16,4.5,18))
	var frozen_pose: Transform3D = restored.world.objects[CargoSession.CARGO].global_transform
	_check(not restored.module.remap_role().ok and restored.world.objects[CargoSession.CARGO].global_transform == frozen_pose and restored.player.cargo_items.is_empty(),"different profile cannot claim suspended load, candidate unchanged")
	restored.session.identities[19] = ROLE
	_check(restored.module.sync_roster().ok,"new peer roster explicitly requests same-role remap")
	var remapped: Dictionary = restored.module.remap_role()
	if not _check(remapped.ok,"same profile/new body rebinds original native Joint: "+str(remapped)): _finish(); return
	_check(_matches_momentum(restored,suspension.state) and restored.player.cargo_items.has(CargoSession.CARGO) and int(restored.module._custody.last_serial) == int(saved.custody.last_serial),"disconnect/rejoin preserves real momentum and original serial under new peer")
	print("THERMAL_PROGRESS_STAGE same_identity_remapped "+JSON.stringify({"frames":frames,"peer":19,"serial":restored.module._custody.last_serial}))
	var return_pilot := Pilot.new()
	_check(return_pilot.bind(restored.player) and return_pilot.go_to(Vector3(-10,4.55,18),2),"restored original player can continue actual flight toward low berth")
	var arrived := false
	for _step in range(1200):
		if not await _frame(restored,return_pilot): _finish(); return
		if return_pilot.report().arrived: arrived = true; break
	if not _check(arrived,"restored real load returns above low berth"): _finish(); return
	var drop: Dictionary = restored.module.operate(19,CargoSession.LOW)
	if not _check(drop.ok,"normal G requests real post-restore drop: "+str(drop)): _finish(); return
	if not await _wait(restored,"docked",1200): _finish(); return
	var final_state: Dictionary = restored.module.save_state()
	_check(final_state.ok and final_state.state.version == 1 and int(final_state.state.custody.last_serial) == int(saved.custody.last_serial)+1,"only actual release/contact increments serial once; supported checkpoint returns to native v1")
	_check(restored.module.fact(CargoSession.FACT).is_empty() and restored.player.cargo_kg == 0.0 and restored.player.cargo_items.is_empty(),"short resume route does not pretend outer/high delivery and releases actual load")
	_finish()

func _finish() -> void:
	if finished: return
	finished = true
	for fixture in fixtures:
		fixture.module.clear()
		if is_instance_valid(fixture.viewport): fixture.viewport.free()
		if is_instance_valid(fixture.session): fixture.session.free()
	print("Thermal cargo progress: %d checks, %d failures, %d actual physics frames. Native moving snapshot, fresh one-cargo Joint, profile remap and real return docking only; no Store, MAIN or LAN acceptance claim." % [checks,failures,frames])
	quit(0 if failures == 0 else 1)
