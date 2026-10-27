extends SceneTree
## Short device diagnostic. The published actual v2 envelope is an explicit
## initial-state QA fixture, NOT a replay of transport/work or full-scene restore.
## Only initial cargo poses are assigned; support must settle again in physics.
const World = preload("res://scripts/v3/twin_test_world.gd")
const Flight = preload("res://scripts/v2/flight_body.gd")
const Catalog = preload("res://scripts/v2/catalog.gd")
const Custody = preload("res://scripts/v3/candidates/canal_transport_physics/cargo_custody.gd")
const Rules = preload("res://scripts/v3/candidates/canal_service_loop/canal_service_runtime.gd")
const Cooling = preload("res://scripts/v3/candidates/canal_cooling_station/cooling_station.gd")
const Diagnostics = preload("res://tests_v3/candidates/canal_cooling_station/restore_precision_diagnostics.gd")
const FIXTURE := "res://tests_v3/candidates/canal_cooling_station/fixtures/checkpoint_v2_actual.json"
const DT := 1.0/60.0
const POSE_LIMIT_M := .00001 # Root agreed physical position contract: 10 micrometres.
var world: World
var viewport: SubViewport
var station: Cooling
var custody: Custody
var berths: Dictionary = {}
var cargos: Dictionary = {}
var checks := 0
var failures: Array = []
var evidence: Dictionary = {}
var finished := false

class ErrorLog extends Logger:
	var errors: Array = []
	func _log_error(fn: String,file: String,line: int,code: String,reason: String,_notify: bool,kind: int,_traces: Array[ScriptBacktrace]) -> void:
		errors.append({"function":fn,"file":file,"line":line,"code":code,"reason":reason,"kind":kind})
var logger := ErrorLog.new()

func _init() -> void:
	OS.add_logger(logger)
	_run.call_deferred()

func _run() -> void:
	create_timer(35).timeout.connect(func():
		if not finished:
			_check(false,"short device diagnostic internal timeout")
			_finish())
	var cooling_script: Script = Cooling
	var custody_script: Script = Custody
	if not _check(cooling_script.can_instantiate() and custody_script.can_instantiate(),"actual device and custody scripts instantiate"):
		_finish(); return
	var raw: Variant = JSON.parse_string(FileAccess.get_file_as_string(FIXTURE))
	if not _check(raw is Dictionary and raw.get("version",0) == 2,"actual published v2 checkpoint fixture loaded"):
		_finish(); return
	var envelope: Dictionary = raw
	var original_device: Dictionary = envelope.checkpoint.cooling.duplicate(true)
	evidence.fixture = {"path":FIXTURE,"sha256":FileAccess.get_sha256(FIXTURE),"source_frame":envelope.physics.frame,
		"scope":"published actual checkpoint initializes QA bodies once; new contacts are required; old native floating-point low bits were not logged"}
	viewport = SubViewport.new()
	viewport.own_world_3d = true
	viewport.world_3d = World3D.new()
	viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	root.add_child(viewport)
	world = World.new()
	viewport.add_child(world)
	world.build("I2",{},true)
	if not _check(world.build_errors.is_empty(),"actual production I2 builds",world.build_errors):
		_finish(); return
	for pair: Array in [[Rules.SOUTH_0,Vector3(7.7,0,21)],[Rules.SOUTH_1,Vector3(7.7,0,24)],[Rules.WORK,Vector3(10.6,0,6)],[Rules.BUFFER,Vector3(10.6,5,8)]]:
		berths[pair[0]] = _box("InitialFixtureBerth_"+str(pair[0]),pair[1],Vector3(2,.5,2))
	for id: String in Rules.CASSETTES:
		var saved_cargo: Dictionary = envelope.checkpoint.cargos[id]
		var cargo := RigidBody3D.new()
		cargo.name = "InitialFixture_"+id.replace(":","_")
		cargo.mass = 2.0
		cargo.transform = _pose(saved_cargo.pose)
		cargo.collision_layer = 8
		cargo.collision_mask = 47
		cargo.contact_monitor = true
		cargo.max_contacts_reported = 16
		cargo.continuous_cd = true
		cargo.can_sleep = false
		var collision := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = Vector3(.4,.4,.4)
		collision.shape = shape
		cargo.add_child(collision)
		world.add_child(cargo)
		cargos[id] = cargo
	var carrier = Flight.new()
	carrier.configure(Catalog.resolve_build(Catalog.default_build("tr01")))
	carrier.freeze = true # Explicit nonparticipating registry fixture, no flight claim.
	carrier.position = Vector3(-20,3,18)
	world.add_child(carrier)
	for i in 75: await physics_frame
	custody = Custody.new()
	if not _check(custody.configure(cargos,berths,{Rules.CARRIER:carrier},true).ok,"actual same-world custody registry configures"):
		_finish(); return
	for index in 2:
		var id: String = Rules.CASSETTES[index]
		var seated: Dictionary = custody.seat(id,str(envelope.checkpoint.cargos[id].holder),index+1,custody.revision)
		if not _check(seated.ok,"initial saved cargo reacquires actual support before seating",seated):
			_finish(); return
	for i in 30:
		await physics_frame
		var stepped: Dictionary = custody.step(DT,true,false)
		if not stepped.ok:
			_check(false,"real custody stability sampling",stepped)
			_finish(); return
	evidence.supports = {}
	for id: String in Rules.CASSETTES:
		var support: Dictionary = custody.support_info(id,str(envelope.checkpoint.cargos[id].holder))
		evidence.supports[id] = support
		if not _check(support.supported and custody.report().cargos[id].phase == "docked" and custody.report().cargos[id].stable_usec == 350000,"fresh physics proves stable cargo support",support):
			_finish(); return
	if not _new_station(): _finish(); return
	var seeded: Dictionary = station.restore_fresh(original_device,true)
	if not _check(seeded.ok,"explicit actual saved device initializes fresh supported fixture",seeded):
		_finish(); return
	evidence.fixture_restore = _diagnostic(original_device,original_device)
	# A real physics advance generates a NEW native double snapshot. Its exact
	# bytes are captured below before and after the same full-precision JSON path.
	await physics_frame
	custody.step(DT,true,false)
	var moved: Dictionary = station.advance(DT,true)
	if not _check(moved.ok and station.capture_state(Engine.get_physics_frames()).ok,"device advances with reacquired live support",moved):
		_finish(); return
	var saved: Dictionary = station.snapshot().duplicate(true)
	var encoded: String = JSON.stringify(saved,"",true,true)
	var decoded: Variant = JSON.parse_string(encoded)
	if not _check(decoded is Dictionary and Cooling.validate_snapshot(decoded).ok,"new native snapshot survives strict JSON validation"):
		_finish(); return
	var parsed: Dictionary = decoded
	evidence.encoded_device = encoded
	station.free()
	if not _new_station(): _finish(); return
	var restored: Dictionary = station.restore_fresh(parsed,true)
	if not _check(restored.ok,"fresh-only replacement restores current JSON payload",restored):
		_finish(); return
	var diagnostic: Dictionary = _diagnostic(saved,parsed)
	evidence.native_roundtrip = diagnostic
	# Preserve the previous combined condition AS DIAGNOSTIC, with its original
	# label and booleans. Its failure must not be silently reported as fixed.
	evidence.original_combined_assertion = {"label":"fresh restore synchronizes real collider, charge, revision, position and velocity",
		"passed":diagnostic.node_lt_1um and diagnostic.physics_lt_1um and diagnostic.native_dictionary_equal}
	var current: Dictionary = station.snapshot()
	var actual_pose: Transform3D = PhysicsServer3D.body_get_state(station.valve.get_rid(),PhysicsServer3D.BODY_STATE_TRANSFORM)
	var expected: Vector3 = Cooling.VALVE_CLOSED+Vector3(0,0,float(parsed.axis.position_m))
	_check(station.valve.global_position.distance_to(expected) <= POSE_LIMIT_M and actual_pose.origin.distance_to(expected) <= POSE_LIMIT_M,"restored real valve and collider satisfy agreed 10um physical contract",diagnostic)
	_check(_same_json_values(current,parsed),"all payload values preserved; integral JSON numbers normalized by schema",diagnostic)
	_check(float(current.axis.velocity_mps) == float(parsed.axis.velocity_mps) and float(current.axis.velocity_mps) > 0.0,"bounded saved mechanical speed preserved exactly from payload")
	var unchanged: Dictionary = current.duplicate(true)
	_check(not station.apply_charge(1,int(parsed.charge_serial),true).ok and not station.apply_impulse(Vector3(0,0,.1),int(parsed.axis.last_serial["1"]),true).ok and station.snapshot() == unchanged,"restored command serials reject replay without state mutation")
	_check(not station.capture_state(Engine.get_physics_frames()).ok,"restored contact history alone cannot authorize current sample")
	var candidate = Cooling.Axis.new()
	candidate.configure(Cooling.axis_config())
	candidate.restore(parsed.axis,false)
	var predicted: Dictionary = candidate.preview(DT)
	await physics_frame
	custody.step(DT,true,false)
	var advanced: Dictionary = station.advance(DT,true)
	var after: Dictionary = station.snapshot()
	evidence.next_real_tick = {"predicted":predicted,"actual":after,"support":station.facts().contacts}
	_check(advanced.ok and float(after.axis.position_m) == float(predicted.position_m) and float(after.axis.velocity_mps) == float(predicted.velocity_mps),"first physical tick follows exact saved axis state without duplicate impulse",evidence.next_real_tick)
	_check(station.capture_state(Engine.get_physics_frames()).ok and station.facts().contacts == after.contact_observation,"fresh support, not saved hit, permits next current sample")
	_finish()

func _diagnostic(saved: Dictionary, parsed: Dictionary) -> Dictionary:
	var actual: Transform3D = PhysicsServer3D.body_get_state(station.valve.get_rid(),PhysicsServer3D.BODY_STATE_TRANSFORM)
	var expected: Vector3 = Cooling.VALVE_CLOSED+Vector3(0,0,float(saved.axis.position_m))
	return Diagnostics.inspect(saved,parsed,station.snapshot(),station.valve.global_position,actual.origin,expected)

func _new_station() -> bool:
	station = Cooling.new()
	world.add_child(station)
	var configured: Dictionary = station.configure(cargos,berths,custody,true)
	return _check(configured.ok,"fresh real device binds same live cargo, support and custody",configured)

func _pose(values: Array) -> Transform3D:
	return Transform3D(Basis(Vector3(values[0],values[1],values[2]),Vector3(values[3],values[4],values[5]),Vector3(values[6],values[7],values[8])),Vector3(values[9],values[10],values[11]))

func _same_json_values(a: Variant, b: Variant) -> bool:
	if (a is int or a is float) and (b is int or b is float): return float(a) == float(b)
	if a is Dictionary and b is Dictionary:
		if a.size() != b.size(): return false
		for key: Variant in a:
			if not b.has(key) or not _same_json_values(a[key],b[key]): return false
		return true
	return typeof(a) == typeof(b) and a == b

func _box(label: String,at: Vector3,size: Vector3) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = label
	body.position = at
	body.collision_layer = 1
	body.collision_mask = 0
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	collision.shape = shape
	body.add_child(collision)
	world.add_child(body)
	return body

func _check(ok: bool,label: String,details: Variant=null) -> bool:
	checks += 1
	if not ok: failures.append({"label":label,"details":details})
	return ok

func _finish() -> void:
	if finished: return
	finished = true
	_check(logger.errors.is_empty(),"no engine errors",logger.errors)
	print("V3_CANAL_COOLING_RESTORE_TESTS "+JSON.stringify({"checks":checks,"failures":failures,"engine_errors":logger.errors,"evidence":evidence}))
	if is_instance_valid(viewport): viewport.free()
	quit(0 if failures.is_empty() else 1)
