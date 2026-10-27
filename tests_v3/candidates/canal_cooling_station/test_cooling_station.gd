extends SceneTree
## Actual production I2 geometry, guided valve and real 2 kg contact bodies.
## Rules' two south holders are an explicit initial-state fixture; this test
## does not execute transport, work, service, saving, abilities or networking.
const World=preload("res://scripts/v3/twin_test_world.gd")
const Flight=preload("res://scripts/v2/flight_body.gd")
const Catalog=preload("res://scripts/v2/catalog.gd")
const Custody=preload("res://scripts/v3/candidates/canal_transport_physics/cargo_custody.gd")
const Runtime=preload("res://scripts/v3/candidates/canal_service_loop/canal_service_runtime.gd")
const Station=preload("res://scripts/v3/candidates/canal_cooling_station/cooling_station.gd")
const DT:=1.0/60.0
var world: World
var station: Station
var viewport: SubViewport
var cc=Custody.new()
var rules=Runtime.new()
var berths: Dictionary={}
var cargos: Dictionary={}
var checks:=0
var failures: Array=[]
var finished:=false
var elapsed_usec:=0
var rule_frames:=0
var evidence: Dictionary={}

class ErrorLog extends Logger:
	var errors: Array=[]
	func _log_error(fn: String,file: String,line: int,code: String,reason: String,_notify: bool,kind: int,_traces: Array[ScriptBacktrace]) -> void:
		errors.append({"function":fn,"file":file,"line":line,"code":code,"reason":reason,"kind":kind})
var logger=ErrorLog.new()

func _init() -> void:
	OS.add_logger(logger)
	_run.call_deferred()

func _check(ok: bool,label: String,details: Variant=null) -> bool:
	checks+=1
	if not ok: failures.append({"label":label,"details":details})
	return ok

func _run() -> void:
	create_timer(60).timeout.connect(func():
		if not finished:
			_check(false,"internal bounded timeout")
			_finish())
	viewport=SubViewport.new()
	viewport.own_world_3d=true
	viewport.world_3d=World3D.new()
	viewport.render_target_update_mode=SubViewport.UPDATE_DISABLED
	root.add_child(viewport)
	world=World.new()
	viewport.add_child(world)
	world.build("I2",{},true)
	if not _check(world.build_errors.is_empty(),"actual production I2 builds",world.build_errors):
		_finish(); return
	for pair: Array in [[Runtime.SOUTH_0,Vector3(7.7,0,21)],[Runtime.SOUTH_1,Vector3(7.7,0,24)]]:
		berths[pair[0]]=_box("FixtureBerth_"+pair[0],pair[1],Vector3(2,.5,2))
	for index in 2:
		var berth: StaticBody3D=berths[Runtime.SOUTH_0 if index==0 else Runtime.SOUTH_1]
		var cargo:=RigidBody3D.new()
		cargo.name="Real2kgCassette"+str(index)
		cargo.mass=2.0
		cargo.position=berth.position+Vector3.UP*.46
		cargo.collision_layer=8
		cargo.collision_mask=47
		cargo.contact_monitor=true
		cargo.max_contacts_reported=16
		cargo.continuous_cd=true
		cargo.can_sleep=false
		var collider:=CollisionShape3D.new()
		var shape:=BoxShape3D.new()
		shape.size=Vector3(.4,.4,.4)
		collider.shape=shape
		cargo.add_child(collider)
		world.add_child(cargo)
		cargos[Runtime.CASSETTES[index]]=cargo
	var carrier=Flight.new()
	carrier.configure(Catalog.resolve_build(Catalog.default_build("tr01")))
	carrier.freeze=true
	carrier.position=Vector3(-20,3,18)
	world.add_child(carrier)
	for i in 75: await physics_frame
	if not _check(cc.configure(cargos,berths,{Runtime.CARRIER:carrier},true).ok,"unique actual cargo/custody registry configures"):
		_finish(); return
	for index in 2:
		var seated: Dictionary=cc.seat(Runtime.CASSETTES[index],Runtime.SOUTH_0 if index==0 else Runtime.SOUTH_1,index+1,cc.revision)
		if not _check(seated.ok,"real supported initial south seat",seated):
			_finish(); return
	for i in 30:
		await physics_frame
		cc.step(DT,true,false)
	_check(rules.configure().ok,"independent closed cooling rules configure")
	var fixture: Dictionary=rules.snapshot()
	fixture.cassettes[Runtime.CASSETTES[0]].holder=Runtime.SOUTH_0
	fixture.cassettes[Runtime.CASSETTES[1]].holder=Runtime.SOUTH_1
	_check(rules.restore(fixture).ok,"explicit pre-existing south-holder fixture does not award any transport/work receipt")
	station=Station.new()
	world.add_child(station)
	var built: Dictionary=station.configure(cargos,berths,cc,true)
	if not _check(built.ok,"physical cooling station fits production space",built):
		_finish(); return
	await physics_frame
	var facts: Dictionary=station.facts()
	_check(facts.contacts[Runtime.SOUTH_0]==Runtime.CASSETTES[0] and facts.contacts[Runtime.SOUTH_1]==Runtime.CASSETTES[1],"both contacts are real settled bodies",facts)
	_check(not facts.powered and not facts.valve_open,"station starts unpowered with actual closed valve")
	_check(Station.validate_snapshot(station.snapshot()).ok,"fresh device has strict serializable state")
	var before: Dictionary=station.report()
	_check(not station.apply_charge(35,1,false).ok and not station.apply_impulse(Vector3(0,0,9),1,false).ok and not station.advance(DT,false).ok and station.report()==before,"nonhost cannot charge, move or advance")
	_check(station.apply_charge(35,1).ok and station.facts().powered,"bounded real relay charge enables supply")
	before=station.report()
	_check(not station.apply_charge(35,1).ok and station.report()==before,"repeat charge serial is idempotently refused")
	for i in 60: await _tick()
	_check(rules.snapshot().pump_total_ml==0 and rules.status().temperatures_c[Runtime.CASSETTES[1]]==70.0,"power without open physical valve cannot cool")
	var blocker: StaticBody3D=_box("ActualSliderObstruction",Vector3(5.8,1.18,22.7),Vector3(.5,.18,.04))
	await physics_frame
	_check(station.apply_impulse(Vector3(0,0,9),1).ok,"real axis accepts one bounded host impulse")
	var saw_blocked:=false
	for i in 90:
		await _tick()
		saw_blocked=saw_blocked or station.report().blocked
	_check(saw_blocked and float(station.report().axis.position_m)<.081 and not station.facts().valve_open and rules.snapshot().pump_total_ml==0,"physical obstruction prevents valve stroke and cooling",station.report())
	blocker.queue_free()
	await physics_frame
	_check(station.apply_impulse(Vector3(0,0,9),2).ok,"after real obstacle removal a new impulse resumes stroke")
	for i in 120: await _tick()
	_check(station.facts().valve_open and station.facts().sweep_clear and rules.snapshot().pump_total_ml>0,"real open valve/contact starts closed-loop transfer",station.report())
	var saved_device: Dictionary=station.snapshot()
	var json_device: Variant=JSON.parse_string(JSON.stringify(saved_device,"",true,true))
	_check(Station.validate_snapshot(json_device).ok and station.capture_state(Engine.get_physics_frames()).ok,"actual current device state validates across JSON with freshly sampled contact")
	var old_pose: Transform3D=station.valve.global_transform
	var restore_refused: Dictionary=station.restore_fresh(json_device,true)
	_check(not restore_refused.ok and restore_refused.code=="fresh_device_required" and station.snapshot()==saved_device and station.valve.global_transform==old_pose,"used station cannot restore by teleporting its valve or resetting serials",restore_refused)
	_check(not station.advance(DT).ok,"duplicate same-physics-frame station advance is rejected")
	station.set_paused(true)
	var paused_device: Dictionary=station.snapshot()
	_check(Station.validate_snapshot(paused_device).ok and float(paused_device.axis.velocity_mps)==0.0,"pause snapshots preserve stopped axis and consumed input serial")
	var invalid_pause: Dictionary=paused_device.duplicate(true)
	invalid_pause.axis.velocity_mps=.1
	_check(not Station.validate_snapshot(invalid_pause).ok,"paused state cannot hide delayed mechanical velocity")
	var paused: Dictionary=station.report()
	var paused_rules: Dictionary=rules.snapshot()
	for i in 30:
		await physics_frame
		_check(not station.advance(DT).ok,"paused station refuses advance")
		rules.step(16667,station.facts(),true,true)
	_check(station.report()==paused and rules.snapshot()==paused_rules,"pause does not accumulate future fluid/heat or delayed valve impulse")
	station.set_paused(false)
	for i in 900: await _tick()
	var cold: Dictionary=rules.snapshot()
	var temperatures: Dictionary=rules.status().temperatures_c
	_check(float(temperatures[Runtime.CASSETTES[1]])<=45.0 and float(temperatures[Runtime.CASSETTES[1]])>20.0,"actual powered supported loop cools hot cassette to usable threshold",temperatures)
	_check(rules.validate_snapshot(cold).ok,"closed water and heat ledgers remain valid")
	var clean:=0
	var dirty:=0
	for node: Dictionary in cold.water.nodes.values():
		clean+=int(node.clean_ml)
		dirty+=int(node.dirty_ml)
	_check(clean==7600 and dirty==400 and cold.jobs_completed==0 and cold.service_credit==0,"8 L remains separate and cooling never invents completed work or service")
	_check(station.apply_charge(-35,2).ok,"draining actual relay removes supply")
	var stopped: Dictionary=rules.snapshot()
	for i in 60: await _tick()
	_check(rules.snapshot().pump_total_ml==stopped.pump_total_ml and rules.snapshot().cassettes==stopped.cassettes,"unpowered open valve cannot continue pumping or cooling")
	# Remove the test's own cargo node to test real lifetime failure, not a forged
	# occupancy dictionary. No last-known dock flag may authorize future contact.
	cargos[Runtime.CASSETTES[1]].queue_free()
	await physics_frame
	var missing: Dictionary=station.facts()
	_check(not missing.powered and missing.contacts[Runtime.SOUTH_1]=="" and not station.advance(DT).ok,"lost physical body fails closed instead of cooling a stale holder")
	_check(Station.validate_snapshot(saved_device).ok and saved_device.contact_observation[Runtime.SOUTH_1]==Runtime.CASSETTES[1] and missing.contacts[Runtime.SOUTH_1]=="","saved contact observation remains history and never authorizes missing cargo")
	evidence={"scope":"actual valve collision, physical cargo contacts and thermal/water rules; initial holder fixture, no transport/work/service/save/network","final_rules":rules.status(),"station":station.report(),"blocked_observed":saw_blocked}
	_finish()

func _tick() -> void:
	await physics_frame
	if finished: return
	var custody: Dictionary=cc.step(DT,true,false)
	var moved: Dictionary=station.advance(DT,true)
	if not custody.ok or not moved.ok:
		_check(false,"actual per-frame adapters accept valid simulation",{"custody":custody,"station":moved})
		return
	rule_frames+=1
	var next_usec: int=roundi(float(rule_frames)*1000000.0/60.0)
	var stepped: Dictionary=rules.step(next_usec-elapsed_usec,station.facts(),true,false)
	if not stepped.ok: _check(false,"runtime accepts actual station facts",stepped)
	elapsed_usec=next_usec

func _box(label: String, at: Vector3, size: Vector3) -> StaticBody3D:
	var body:=StaticBody3D.new()
	body.name=label
	body.position=at
	body.collision_layer=1
	body.collision_mask=0
	var collider:=CollisionShape3D.new()
	var shape:=BoxShape3D.new()
	shape.size=size
	collider.shape=shape
	body.add_child(collider)
	world.add_child(body)
	return body

func _finish() -> void:
	if finished: return
	finished=true
	_check(logger.errors.is_empty(),"no engine errors",logger.errors)
	print("V3_CANAL_COOLING_STATION_TESTS "+JSON.stringify({"checks":checks,"failures":failures,"engine_errors":logger.errors,"evidence":evidence}))
	if is_instance_valid(viewport): viewport.free()
	quit(0 if failures.is_empty() else 1)
