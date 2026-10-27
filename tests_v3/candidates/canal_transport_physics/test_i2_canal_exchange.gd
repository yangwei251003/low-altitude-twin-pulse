extends SceneTree
## Production I2 geometry + candidate physical berths. No pose/velocity writes
## after initial construction. Stops before work/service, never invents a receipt.
const World = preload("res://scripts/v3/twin_test_world.gd")
const Flight = preload("res://scripts/v2/flight_body.gd")
const Catalog = preload("res://scripts/v2/catalog.gd")
const Pilot = preload("res://scripts/v3/candidates/canal_transport_physics/transport_pilot.gd")
const Dock = preload("res://scripts/v3/candidates/canal_transport_physics/dock_lift.gd")
const Custody = preload("res://scripts/v3/candidates/canal_transport_physics/cargo_custody.gd")
const Rules = preload("res://scripts/v3/candidates/canal_service_loop/canal_service_runtime.gd")
const DT := 1.0/60.0
const MASK := 1 | 2 | 4 | 8 | 32
const CENTRE_X := 14.75
const WAIT_POINT := Vector3(14.75,2.2,23)
const BERTH_POINTS := {
	"south_0":Vector3(7.7,0,21),"south_1":Vector3(7.7,0,24),
	"north_work":Vector3(10.6,0,6),"north_buffer":Vector3(10.6,5,8)}
const MATCH_KEYS := ["serial","kind","actor","cassette_id","source","destination","route","job"]
var viewport: SubViewport
var world: World
var carrier: Flight
var cargos: Dictionary = {}
var berths: Dictionary = {}
var support_permission: Dictionary = {}
var cc: RefCounted
var pilot: RefCounted
var dock: RefCounted
var rules: RefCounted
var rules_started: bool = false
var cc_started: bool = false
var checks: int = 0
var failures: Array = []
var records: Array = []
var active: Dictionary = {}
var receipts: Array = []
var inputs: Dictionary = {}
var fixture_checks: Array = []
var command_serial: int = 0
var physics_ticks: int = 0
var rule_ticks: int = 0
var rule_elapsed_usec: int = 0
var rescue_count: int = 0
var water_entries: int = 0
var finished: bool = false
var fatal: bool = false
var current_action: Dictionary = {}
var cargo_sweep_diagnostics := {"checked":0,"would_block":0,"max_speed_mps":0.0,"max_motion_m":0.0,"first_would_block":{}}

class ErrorLogger extends Logger:
	var errors: Array = []
	func _log_error(function: String,file: String,line: int,code: String,rationale: String,_notify: bool,error_type: int,_backtraces: Array[ScriptBacktrace]) -> void:
		errors.append({"function":function,"file":file,"line":line,"code":code,"rationale":rationale,"type":error_type})
var logger := ErrorLogger.new()

func _init() -> void:
	OS.add_logger(logger)
	_run.call_deferred()

func _run() -> void:
	create_timer(280.0).timeout.connect(func():
		if not finished:
			print("I2_CANAL_EXCHANGE_TIMEOUT "+JSON.stringify(_evidence()))
			quit(2))
	for dependency: Script in [World,Flight,Pilot,Dock,Custody,Rules]:
		if not dependency.can_instantiate():
			_check(false,"dependency can instantiate",{"path":dependency.resource_path})
			await _finish()
			return
	_collect_inputs()
	if not await _build():
		await _finish()
		return
	if not await _bootstrap():
		await _finish()
		return
	for index in 16:
		if fatal: break
		var request: Dictionary = rules.request_action(int(rules.snapshot().revision))
		if not _check(request.ok and request.has("action"),"rules propose a bounded actual next action",request): break
		current_action = request.action.duplicate(true)
		if current_action.kind == "work":
			_check(_physical_work_ready(),"cold really docked at WORK, hot really at a south berth before unperformed work",_sample())
			break
		if current_action.kind not in ["move","pick","place"] or current_action.route != "low":
			_check(false,"only staggered low physical move/pick/place are implemented",current_action)
			break
		var physical: Dictionary = {}
		match current_action.kind:
			"move": physical = await _move_action(current_action)
			"pick": physical = await _pick_action(current_action)
			"place": physical = await _place_action(current_action)
		if not bool(physical.get("completed",false)):
			rules.report_blocked(int(current_action.serial))
			_check(false,"physical action failed; pending kept without receipt",{"action":current_action,"physical":physical,"sample":_sample()})
			break
		if not _confirm(current_action,physical): break
		# A pick receipt proves the real joint. Departure is still a separate real
		# movement before another move can be attempted, not folded into a flag.
		if current_action.kind == "pick":
			if not await _dock_departure(str(current_action.source),str(current_action.cassette_id)): break
	var saved: Dictionary = rules.snapshot()
	_check(saved.pending_action.get("kind","") == "work" and _physical_work_ready(),"exchange ends at pending work, never fabricates a workbench")
	_check(saved.service_credit == 0 and saved.jobs_completed == 0 and saved.services_consumed == 0 and saved.thermal_ledger.work_added == 0,"no work/service/heat receipt manufactured")
	_check(saved.pump_total_ml == 0 and saved.water.nodes[Rules.RESERVOIR].clean_ml == 5700,"unconnected cooling power remains off")
	_check(logger.errors.is_empty(),"no engine errors",{"errors":logger.errors})
	await _finish()

func _build() -> bool:
	if not _check(Engine.physics_ticks_per_second == 60 and Engine.time_scale == 1.0,"real normal 60 Hz simulation"): return false
	viewport = SubViewport.new()
	viewport.size = Vector2i(32,32)
	viewport.own_world_3d = true
	viewport.world_3d = World3D.new()
	viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	root.add_child(viewport)
	world = World.new()
	viewport.add_child(world)
	world.build("I2",{},true)
	if not _check(world.build_errors.is_empty(),"actual production I2 builds",{"errors":world.build_errors}): return false
	if not _check(is_instance_valid(world.clinic) and is_instance_valid(world.distribution) and is_instance_valid(world.trial) and is_instance_valid(world.shared_access),"one production instance of each of four facilities"): return false
	_check(world.waterfront != null and world.waterfront_install.get("ok",false),"actual canal ground/water installed")
	for art: Dictionary in [world.clinic.gravity_art,world.clinic.reception_art,world.clinic.pump_art,world.shared_access.deck_art,world.shared_access.landing_art]:
		if not _check(art.get("ok",false),"production imported facility asset/collision available",{"path":art.get("path","")}): return false
		var path: String = str(art.get("path",""))
		if not path.is_empty(): inputs[path] = FileAccess.get_sha256(path)
	for i in 3: await physics_frame
	# No candidate plate is present during the production-space queries.
	for id: String in BERTH_POINTS:
		if not _berth_preflight(id,BERTH_POINTS[id]): return false
	for id: String in BERTH_POINTS: berths[id] = _plate(id,BERTH_POINTS[id])
	carrier = Flight.new()
	carrier.configure(Catalog.resolve_build(Catalog.default_build("tr01")))
	carrier.freeze = true
	carrier.position = BERTH_POINTS[Rules.SOUTH_0]+Vector3.UP*1.55
	carrier.hold_height = carrier.position.y
	carrier.safe_position = carrier.position
	carrier.max_altitude = 18.0
	carrier.command = {"active":true,"mode":"assisted","brake":true}
	world.add_child(carrier)
	carrier.environment_hazards_authoritative = true
	carrier.environment_query = world.sample_environment
	carrier.environment_sample = world.sample_environment(carrier.global_position)
	carrier.rescued.connect(func(): rescue_count += 1)
	carrier.water_entered.connect(func(): water_entries += 1)
	for pair: Array in [[Rules.CASSETTES[0],Rules.SOUTH_0],[Rules.CASSETTES[1],Rules.WORK]]:
		var id: String = str(pair[0])
		var berth_id: String = str(pair[1])
		cargos[id] = _cargo(id,BERTH_POINTS[berth_id]+Vector3.UP*.46)
		support_permission[id] = berth_id
	for i in 75:
		if not await _tick(): return false
	cc = Custody.new()
	var configured: Dictionary = cc.configure(cargos,berths,{Rules.CARRIER:carrier},true)
	if not _check(configured.ok,"physical custody registry matches exactly two real 2 kg cassettes",configured): return false
	cc_started = true
	for pair: Array in [[Rules.CASSETTES[0],Rules.SOUTH_0],[Rules.CASSETTES[1],Rules.WORK]]:
		var seated: Dictionary = cc.seat(str(pair[0]),str(pair[1]),_serial(),cc.revision)
		if not _check(seated.ok,"reserve real initial berth without declaring delivery",seated): return false
	for i in 60:
		if not await _tick(): return false
		if _is_docked(Rules.CASSETTES[0],Rules.SOUTH_0) and _is_docked(Rules.CASSETTES[1],Rules.WORK): break
	return _check(_is_docked(Rules.CASSETTES[0],Rules.SOUTH_0) and _is_docked(Rules.CASSETTES[1],Rules.WORK),"initial cargo truly settles on S0/WORK")

func _bootstrap() -> bool:
	carrier.freeze = false
	pilot = Pilot.new()
	if not _check(pilot.bind(carrier),"pilot controls actual FlightBody"): return false
	if not await _align_pickup(Rules.CASSETTES[0],Rules.SOUTH_0): return false
	var picked: Dictionary = cc.pickup(Rules.CASSETTES[0],Rules.CARRIER,_serial(),cc.revision)
	if not _check(picked.ok and _has_joint(Rules.CASSETTES[0]),"bootstrap cold pickup is a real joint",picked): return false
	dock = Dock.new()
	if not await _dock_departure(Rules.SOUTH_0,Rules.CASSETTES[0]): return false
	for target: Vector3 in [Vector3(CENTRE_X,2.2,21),WAIT_POINT]:
		if not await _leg("bootstrap_wait",target): return false
	if not _check(carrier.global_position.distance_to(WAIT_POINT)<.18 and _has_joint(Rules.CASSETTES[0]) and _is_docked(Rules.CASSETTES[1],Rules.WORK),"only true WAIT/cold-carrier/hot-WORK physical state permits rule initialization"): return false
	rules = Rules.new()
	if not _check(rules.configure().ok,"configure pure rules after physical initial state exists"): return false
	rules_started = true
	return _check(_custody_matches(rules.snapshot()),"rule initial custody exactly matches physical registry/joints")

func _move_action(action: Dictionary) -> Dictionary:
	var loaded: bool = not str(action.cassette_id).is_empty()
	var destination: String = str(action.destination)
	var points: Array[Vector3] = []
	var at: Vector3 = carrier.global_position
	var source_point: Vector3 = WAIT_POINT if action.source == Rules.WAIT else BERTH_POINTS[str(action.source)]+Vector3.UP*2.2
	if Vector2(at.x-source_point.x,at.z-source_point.z).length()>.20:
		_check(false,"rule source anchor must match real current lateral position",{"source":str(action.source),"actual":_v(at)})
		return {"completed":false}
	_append_point(points,Vector3(source_point.x,2.2,source_point.z))
	_append_point(points,Vector3(CENTRE_X,2.2,source_point.z))
	var target: Vector3 = WAIT_POINT if destination == Rules.WAIT else BERTH_POINTS[destination]+Vector3.UP*2.2
	var source_north: bool = str(action.source) in [Rules.WORK,Rules.BUFFER]
	var target_north: bool = destination in [Rules.WORK,Rules.BUFFER]
	if source_north != target_north:
		_append_point(points,Vector3(CENTRE_X,2.2,6 if source_north else 23))
		_append_point(points,Vector3(CENTRE_X,2.2,6 if target_north else 23))
	_append_point(points,Vector3(CENTRE_X,2.2,target.z))
	_append_point(points,target)
	if not loaded and destination != Rules.WAIT:
		target = BERTH_POINTS[destination]+Vector3.UP*1.55
		_append_point(points,target)
	var completed_legs: int = 0
	for point: Vector3 in points:
		if not await _leg("move_"+str(action.serial),point):
			return {"completed":false,"legs":completed_legs,"planned":points.size()}
		completed_legs += 1
	return {"path_clear":completed_legs == points.size() and not fatal,
		"endpoint_valid":carrier.global_position.distance_to(target)<.18 and carrier.linear_velocity.length()<.18,
		"custody_verified":_custody_matches(rules.snapshot()),"completed":completed_legs == points.size() and not fatal,
		"evidence":{"waypoints":_vectors(points),"actual":_sample(),"legs":completed_legs}}

func _pick_action(action: Dictionary) -> Dictionary:
	var id: String = str(action.cassette_id)
	var source: String = str(action.source)
	if not await _align_pickup(id,source): return {"completed":false}
	var source_proof: Dictionary = cc.support_info(id,source)
	var offset: Vector3 = cargos[id].global_position-(carrier.global_position+Custody.LOAD_OFFSET)
	if not _check(offset.length()<=Pilot.PICKUP_TOLERANCE and _slow_now(),"pickup rechecks actual centred hook in the same physics frame",{"offset":_v(offset)}): return {"completed":false}
	var picked: Dictionary = cc.pickup(id,Rules.CARRIER,_serial(),cc.revision)
	if not _check(picked.ok,"actual pickup request accepted only at true low-speed support",picked): return {"completed":false}
	var expected: Dictionary = rules.snapshot()
	expected.cassettes[id].holder = Rules.CARRIER
	var same_joint: bool = _has_joint(id)
	return {"path_clear":bool(source_proof.get("supported",false)) and not fatal,
		"endpoint_valid":same_joint and _slow_now(),
		"custody_verified":_custody_matches(expected),"completed":same_joint,
		"evidence":{"pickup":picked,"source_contact":bool(source_proof.get("actual_contact",false)),"actual":_sample()}}

func _place_action(action: Dictionary) -> Dictionary:
	var id: String = str(action.cassette_id)
	var destination: String = str(action.destination)
	if not await _wait_slow("before_approach"): return {"completed":false}
	var start: Dictionary = dock.begin_approach(carrier,berths[destination],_serial(),true)
	if not _check(start.ok,"real bounded approach begins",start): return {"completed":false}
	if not await _dock_loop("approach",true): return {"completed":false}
	if not await _wait_slow("before_release"): return {"completed":false}
	var cargo: RigidBody3D = cargos[id]
	var before_y: float = cargo.global_position.y
	var joint_ref: WeakRef = weakref(carrier.cargo_joint)
	var release_proof: Dictionary = cc.release_info(id,destination)
	records.append({"stage":"release_preflight","cargo":id,"proof":release_proof,"grip":cc.grip_info(id),"actual":_sample()})
	var released: Dictionary = cc.release_to(id,destination,_serial(),cc.revision)
	if not _check(released.ok and joint_ref.get_ref() == null,"release removes the real joint, does not yet confirm a place",released): return {"completed":false}
	support_permission[id] = destination
	var landed: bool = false
	active = {"stage":"free_fall","cargo":id,"destination":destination,"samples":[]}
	records.append(active)
	for i in 300:
		if not await _tick(): break
		_brake()
		if i%30 == 0: active.samples.append(_sample())
		if _is_docked(id,destination):
			landed = true
			break
	active.finish = _sample()
	var expected: Dictionary = rules.snapshot()
	expected.cassettes[id].holder = destination
	var fall: float = before_y-cargo.global_position.y
	var support: Dictionary = cc.support_info(id,destination)
	return {"path_clear":landed and not fatal,
		"endpoint_valid":landed and support.get("supported",false) and fall>.10,
		"custody_verified":_custody_matches(expected),
		"completed":landed and fall>.10 and carrier.cargo_items.is_empty(),
		"evidence":{"fall_m":fall,"actual_contact":support.get("actual_contact",false),"state":cc.report(),"actual":_sample()}}

func _align_pickup(id: String, berth_id: String) -> bool:
	var cargo: RigidBody3D = cargos[id]
	active = {"stage":"pickup_alignment","cargo":id,"berth":berth_id,"start":_sample(),"samples":[]}
	records.append(active)
	if not _check(_is_docked(id,berth_id) and pilot.go_to_pickup_alignment(cargo,_serial()),"only nearby real docked cargo permits local empty-hook alignment",active.start): return false
	var blocked: float = 0.0
	for i in 600:
		if not await _tick(): break
		var row: Dictionary = pilot.tick(DT,true,false)
		if i%60 == 0: active.samples.append({"controller":row,"actual":_sample()})
		blocked = blocked+DT if row.state == "blocked" else 0.0
		if blocked >= 3.0:
			_fail("pickup_alignment_blocked",{"controller":row,"actual":_sample()})
			break
		if row.arrived:
			var offset: Vector3 = cargo.global_position-(carrier.global_position+Custody.LOAD_OFFSET)
			active.finish = {"offset":_v(offset),"controller":row,"actual":_sample()}
			return _check(offset.length()<=Pilot.PICKUP_TOLERANCE and _slow_now() and _is_docked(id,berth_id),"actual local alignment settles within 25 mm without moving cargo",active.finish)
	active.finish = _sample()
	return _check(false,"bounded local pickup alignment did not settle",active)

func _confirm(action: Dictionary, physical: Dictionary) -> bool:
	var pending: Dictionary = rules.snapshot().pending_action
	var receipt: Dictionary = {}
	for key: String in MATCH_KEYS:
		if not _check(pending.has(key) and pending[key] == action[key],"receipt identity matches pending "+key): return false
		receipt[key] = action[key]
	for key: String in ["path_clear","endpoint_valid","custody_verified","completed"]:
		receipt[key] = physical.get(key,false)
		if not _check(receipt[key] is bool and receipt[key],"physical evidence required for "+key,physical): return false
	var applied: Dictionary = rules.confirm_action(receipt,true,false)
	receipts.append({"receipt":receipt.duplicate(true),"physical_evidence":physical.get("evidence",{}),"result":applied})
	return _check(applied.ok and _custody_matches(rules.snapshot()),"receipt accepted only after physical custody/endpoint match",applied)

func _dock_departure(berth_id: String, id: String) -> bool:
	if not await _wait_slow("before_departure"): return false
	var start: Dictionary = dock.begin(carrier,berths[berth_id],_serial(),true)
	if not _check(start.ok,"real contact/joint permits controlled departure",start): return false
	if not await _dock_loop("departure",false): return false
	support_permission.erase(id)
	return _check(_has_joint(id) and pilot.probe(Vector3.ZERO).clear,"normal full-envelope pilot is genuinely clear after lifting")

func _dock_loop(label: String, approach: bool) -> bool:
	active = {"stage":label,"samples":[],"start":_sample()}
	records.append(active)
	var blocked: float = 0.0
	for i in 720:
		if not await _tick(): break
		var row: Dictionary = dock.tick(DT,true,false)
		if i%60 == 0: active.samples.append({"actual":_sample(),"controller":row})
		blocked = blocked+DT if row.state == "blocked" else 0.0
		if blocked >= 3.0:
			active.blocked = {"controller":row,"diagnosis":_probe_diagnosis(Vector3.DOWN*.18 if approach else Vector3.UP*.35)}
			_fail("sustained_dock_block",active)
			break
		if (approach and row.get("ready_for_release",false)) or (not approach and row.get("clear",false)):
			active.finish = _sample()
			return _check(true,"actual "+label+" controller completed")
	active.finish = _sample()
	return _check(false,"actual "+label+" failed without route substitution",active)

func _leg(label: String,target: Vector3) -> bool:
	active = {"stage":label,"target":_v(target),"start":_sample(),"samples":[]}
	records.append(active)
	if not _check(pilot.go_to(target,_serial()),"waypoint commands real flight"): return false
	var blocked: float = 0.0
	for i in 1440:
		if not await _tick(): break
		var row: Dictionary = pilot.tick(DT,true,false)
		_observe_cargo_velocity_sweeps()
		if i%60 == 0:
			var sample: Dictionary = _sample()
			sample.speed_plan = row.speed_plan.duplicate(true)
			active.samples.append(sample)
		if row.speed_plan.commanded and row.speed_plan.scale < 1.0 and not active.has("first_speed_reduction"):
			active.first_speed_reduction = {"report":row,"actual":_sample()}
		blocked = blocked+DT if row.state == "blocked" else 0.0
		if row.state == "blocked" and not active.has("first_block"):
			var offset: Vector3 = target-carrier.global_position
			var horizontal: Vector3 = Vector3(offset.x,0,offset.z).limit_length(Pilot.MAX_SPEED)
			active.first_block = {"report":row,"actual":_sample(),"diagnosis":_probe_diagnosis(Vector3(horizontal.x,clampf(offset.y*1.2,-.7,.7),horizontal.z))}
		if blocked >= 3.0:
			_fail("sustained_route_block",active)
			break
		if row.arrived:
			active.finish = _sample()
			return _check(carrier.global_position.distance_to(target)<.18 and carrier.linear_velocity.length()<.18,"actual waypoint reached and stopped",active.finish)
	active.finish = _sample()
	return _check(false,"actual waypoint failed; no teleport/height change",active)

func _wait_slow(label: String) -> bool:
	active = {"stage":label,"samples":[]}
	records.append(active)
	for i in 240:
		if not await _tick(): break
		_brake()
		if i%60 == 0: active.samples.append(_sample())
		if _slow_now(): return true
	return _check(false,"true custody speed/angular thresholds not reached",active)

func _tick() -> bool:
	await physics_frame
	physics_ticks += 1
	world.clock_seconds += DT
	carrier.environment_sample = world.sample_environment(carrier.global_position)
	if cc_started:
		var updated: Dictionary = cc.step(DT,true,false)
		if not updated.ok: return _fail("custody_step_rejected",updated)
		for state: Dictionary in cc.report().cargos.values():
			if state.phase == "fault": return _fail("custody_fault",state)
	if rules_started:
		rule_ticks += 1
		var next_usec: int = roundi(float(rule_ticks)*1000000.0/60.0)
		# No actual cooling couplers/power were installed in this fixture.
		var row: Dictionary = rules.step(next_usec-rule_elapsed_usec,{"powered":false,"valve_open":false,"sweep_clear":false,"contacts":{Rules.SOUTH_0:"",Rules.SOUTH_1:""}},true,false)
		if not row.ok: return _fail("rule_clock_rejected",row)
		rule_elapsed_usec = next_usec
	return _safe()

func _safe() -> bool:
	if not carrier.enabled or carrier.health != carrier.maximum_health or carrier.collision_count != 0 or rescue_count != 0 or water_entries != 0 or carrier.water_contact:
		return _fail("hull_damage_disabled_or_water",_sample())
	if not carrier.global_position.is_finite() or not carrier.linear_velocity.is_finite(): return _fail("nonfinite_carrier",{})
	var bad: Array = []
	for hit: Node in carrier.get_colliding_bodies(): bad.append(str(hit.get_path()))
	for id: String in cargos:
		var cargo: RigidBody3D = cargos[id]
		var allowed: StaticBody3D = berths.get(str(support_permission.get(id,"")))
		for hit: Node in cargo.get_colliding_bodies():
			if hit != allowed: bad.append(id+" -> "+str(hit.get_path()))
		if _cargo_water(cargo): return _fail("cargo_enters_actual_water",{"cargo":id,"actual":_sample()})
	if not bad.is_empty(): return _fail("unexpected_actual_contact",{"contacts":bad,"actual":_sample()})
	return true

func _has_joint(id: String) -> bool:
	if carrier.cargo_items.size() != 1 or not carrier.cargo_items.has(id): return false
	var item: Dictionary = carrier.cargo_items[id]
	var joint: Variant = item.get("joint")
	return is_instance_valid(joint) and joint is PinJoint3D and not joint.is_queued_for_deletion() and item.body == cargos[id] and joint.get_node_or_null(joint.node_a) == carrier and joint.get_node_or_null(joint.node_b) == cargos[id] and is_equal_approx(carrier.cargo_kg,2.0)

func _is_docked(id: String, berth_id: String) -> bool:
	if not cc_started: return false
	var state: Dictionary = cc.report().cargos[id]
	return state.phase == "docked" and state.berth == berth_id and cc.support_info(id,berth_id).get("supported",false)

func _custody_matches(expected: Dictionary) -> bool:
	var actual: Dictionary = cc.report().cargos
	var carried: int = 0
	for id: String in Rules.CASSETTES:
		var holder: String = str(expected.cassettes[id].holder)
		if holder == Rules.CARRIER:
			carried += 1
			if actual[id].phase != "carried" or actual[id].carrier != Rules.CARRIER or not _has_joint(id): return false
		elif holder in Rules.BERTHS:
			if not _is_docked(id,holder): return false
		else: return false
	return carrier.cargo_items.size() == carried

func _physical_work_ready() -> bool:
	return _is_docked(Rules.CASSETTES[0],Rules.WORK) and (_is_docked(Rules.CASSETTES[1],Rules.SOUTH_0) or _is_docked(Rules.CASSETTES[1],Rules.SOUTH_1)) and carrier.cargo_items.is_empty()

func _slow_now() -> bool:
	if carrier.linear_velocity.length()>.12 or carrier.angular_velocity.length()>.12: return false
	for item: Dictionary in carrier.cargo_items.values():
		if item.body.linear_velocity.length()>.10 or item.body.angular_velocity.length()>.12 or (item.body.linear_velocity-carrier.linear_velocity).length()>.18: return false
	return true

func _brake() -> void:
	carrier.hold_height = carrier.global_position.y
	carrier.command = {"active":true,"mode":"assisted","planar":Vector3.ZERO,"vertical":0.0,"brake":true,"fire":false}

func _berth_preflight(id: String, at: Vector3) -> bool:
	var space: PhysicsDirectSpaceState3D = world.get_world_3d().direct_space_state
	var query := PhysicsShapeQueryParameters3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(2,.5,2)
	query.shape = shape
	query.transform = Transform3D(Basis.IDENTITY,at)
	query.collision_mask = MASK
	var rejected: Array = []
	var foundations: Array = []
	for hit: Dictionary in space.intersect_shape(query,32):
		var body: Variant = hit.get("collider")
		var extent: Dictionary = _collision_bounds(body)
		if not extent.get("ok",false) or extent.bounds.end.y > at.y+.005:
			rejected.append(str(body.get_path()) if body is Node else str(body))
		else: foundations.append(str(body.get_path()))
	var ground_ok: bool = true
	var support_points: Array = []
	for offset: Vector3 in [Vector3.ZERO,Vector3(-.8,0,-.8),Vector3(.8,0,-.8),Vector3(-.8,0,.8),Vector3(.8,0,.8)]:
		var ray := PhysicsRayQueryParameters3D.create(at+offset+Vector3.UP*.02,at+offset+Vector3.DOWN*.3,MASK)
		var hit: Dictionary = space.intersect_ray(ray)
		var valid: bool = not hit.is_empty() and absf(hit.position.y-at.y)<.01
		ground_ok = ground_ok and valid
		support_points.append({"valid":valid,"point":_v(hit.get("position",at)),"path":str(hit.collider.get_path()) if not hit.is_empty() else ""})
	shape = BoxShape3D.new()
	shape.size = Vector3(2,2.35,2)
	query.shape = shape
	query.transform.origin = at+Vector3.UP*(.25+.03+1.175)
	var air_hits: Array = _hit_names(space.intersect_shape(query,32))
	var result: Dictionary = {"id":id,"center":_v(at),"existing_below_support":foundations,"intruding_structure":rejected,"overhead_air":air_hits,"five_base_supports":support_points}
	fixture_checks.append(result)
	return _check(rejected.is_empty() and air_hits.is_empty() and ground_ok,"candidate berth fits actual production support and loading column: "+id,result)

func _collision_bounds(value: Variant) -> Dictionary:
	if not value is CollisionObject3D: return {"ok":false}
	var initialized: bool = false
	var bounds := AABB()
	for owner: int in value.get_shape_owners():
		if value.is_shape_owner_disabled(owner): continue
		var pose: Transform3D = value.global_transform*value.shape_owner_get_transform(owner)
		for i in value.shape_owner_get_shape_count(owner):
			var shape: Shape3D = value.shape_owner_get_shape(owner,i)
			var part := AABB()
			if shape is BoxShape3D: part = pose*AABB(-shape.size*.5,shape.size)
			elif shape is ConcavePolygonShape3D:
				var vertices: PackedVector3Array = shape.get_faces()
				if vertices.is_empty(): return {"ok":false}
				part = AABB(pose*vertices[0],Vector3.ZERO)
				for vertex: Vector3 in vertices: part = part.expand(pose*vertex)
			else: return {"ok":false}
			bounds = bounds.merge(part) if initialized else part
			initialized = true
	return {"ok":initialized,"bounds":bounds}

func _probe_diagnosis(desired: Vector3) -> Dictionary:
	var bodies: Array[RigidBody3D] = [carrier]
	var excluded: Array[RID] = [carrier.get_rid()]
	for item: Dictionary in carrier.cargo_items.values():
		bodies.append(item.body)
		excluded.append(item.body.get_rid())
	var bounds := AABB()
	var first: bool = true
	for body: RigidBody3D in bodies:
		var body_bounds: Dictionary = _collision_bounds(body)
		if not body_bounds.ok: return {"code":"unsupported_actual_shape"}
		bounds = body_bounds.bounds if first else bounds.merge(body_bounds.bounds)
		first = false
	bounds = bounds.grow(Pilot.CLEARANCE)
	var shape := BoxShape3D.new()
	shape.size = bounds.size
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = shape
	query.transform = Transform3D(Basis.IDENTITY,bounds.get_center())
	query.collision_mask = MASK
	query.exclude = excluded
	var space: PhysicsDirectSpaceState3D = world.get_world_3d().direct_space_state
	var result: Dictionary = {"bounds_origin":_v(bounds.position),"bounds_size":_v(bounds.size),"initial":_hit_names(space.intersect_shape(query,32)),"sweeps":[]}
	for velocity: Vector3 in [carrier.linear_velocity,desired]:
		if velocity.length()<.01: continue
		query.transform.origin = bounds.get_center()
		query.motion = velocity.normalized()*(velocity.length()+velocity.length_squared()/4+.35)
		var fraction: PackedFloat32Array = space.cast_motion(query)
		var names: Array = []
		if fraction.size() == 2 and fraction[0]<1:
			query.transform.origin += query.motion*minf(1.0,float(fraction[1])+.001)
			query.motion = Vector3.ZERO
			names = _hit_names(space.intersect_shape(query,32))
		result.sweeps.append({"fraction":Array(fraction),"colliders":names})
	return result

func _plate(id: String,at: Vector3) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = "CandidateBerth_"+id
	body.position = at
	body.collision_layer = 1
	body.collision_mask = 0
	var collider := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(2,.5,2)
	collider.shape = shape
	body.add_child(collider)
	world.add_child(body)
	return body

func _cargo(id: String,at: Vector3) -> RigidBody3D:
	var body := RigidBody3D.new()
	body.name = id.replace(":","_")
	body.position = at
	body.mass = 2.0
	body.can_sleep = false
	body.continuous_cd = true
	body.contact_monitor = true
	body.max_contacts_reported = 16
	body.collision_layer = 8
	body.collision_mask = MASK
	var material := PhysicsMaterial.new()
	material.friction = .55
	material.bounce = 0.0
	body.physics_material_override = material
	var collider := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(.4,.4,.4)
	collider.shape = shape
	body.add_child(collider)
	world.add_child(body)
	return body

func _cargo_water(body: RigidBody3D) -> bool:
	var result: Dictionary = _collision_bounds(body)
	if not result.ok: return true
	var bounds: AABB = result.bounds
	for x: float in [bounds.position.x,bounds.end.x]:
		for z: float in [bounds.position.z,bounds.end.z]:
			var at := Vector3(x,bounds.position.y,z)
			var field: Dictionary = world.sample_environment(at)
			if field.get("water",false) and at.y<float(field.get("water_height",-1000)): return true
	return false

func _sample() -> Dictionary:
	var result: Dictionary = {"physics_ticks":physics_ticks,"rule_elapsed_usec":rule_elapsed_usec}
	if is_instance_valid(carrier):
		result.merge({"body":_v(carrier.global_position),"velocity":_v(carrier.linear_velocity),"angular":_v(carrier.angular_velocity),
			"health":carrier.health,"battery":carrier.battery,"collisions":carrier.collision_count,"water":carrier.water_contact,
			"cargo_count":carrier.cargo_items.size(),"environment":carrier.environment_sample.duplicate(true)})
	result.cargos = {}
	for id: String in cargos:
		var body: RigidBody3D = cargos[id]
		result.cargos[id] = {"at":_v(body.global_position),"velocity":_v(body.linear_velocity),"angular":_v(body.angular_velocity),"contacts":[]}
		result.cargos[id].basis = [_v(body.global_basis.x),_v(body.global_basis.y),_v(body.global_basis.z)]
		result.cargos[id].up_dot = body.global_basis.y.dot(Vector3.UP)
		if cc_started: result.cargos[id].grip = cc.grip_info(id)
		for hit: Node in body.get_colliding_bodies(): result.cargos[id].contacts.append(str(hit.get_path()))
	if cc_started: result.custody = cc.report()
	return result

func _observe_cargo_velocity_sweeps() -> void:
	# Evidence only, never changes pilot commands or permits/rejects a route.
	# Each load uses its OWN current AABB and actual velocity, not hull velocity.
	var excluded: Array[RID] = [carrier.get_rid()]
	for item: Dictionary in carrier.cargo_items.values(): excluded.append(item.body.get_rid())
	for id: String in carrier.cargo_items:
		var cargo: RigidBody3D = carrier.cargo_items[id].body
		var speed: float = cargo.linear_velocity.length()
		cargo_sweep_diagnostics.max_speed_mps = maxf(cargo_sweep_diagnostics.max_speed_mps,speed)
		if speed < .01: continue
		var actual: Dictionary = _collision_bounds(cargo)
		if not actual.ok: continue
		var bounds: AABB = actual.bounds.grow(Pilot.CLEARANCE)
		var shape := BoxShape3D.new()
		shape.size = bounds.size
		var query := PhysicsShapeQueryParameters3D.new()
		query.shape = shape
		query.transform = Transform3D(Basis.IDENTITY,bounds.get_center())
		query.collision_mask = MASK
		query.exclude = excluded
		var space: PhysicsDirectSpaceState3D = world.get_world_3d().direct_space_state
		var names: Array = _hit_names(space.intersect_shape(query,8))
		var initial: bool = not names.is_empty()
		query.motion = cargo.linear_velocity.normalized()*(speed+speed*speed/4.0+.35)
		var motion_m: float = query.motion.length()
		var fraction: PackedFloat32Array = space.cast_motion(query)
		var blocked: bool = initial or fraction.size()!=2 or fraction[0]<.999
		cargo_sweep_diagnostics.checked += 1
		cargo_sweep_diagnostics.max_motion_m = maxf(cargo_sweep_diagnostics.max_motion_m,motion_m)
		if not blocked: continue
		cargo_sweep_diagnostics.would_block += 1
		if not cargo_sweep_diagnostics.first_would_block.is_empty(): continue
		if not initial and fraction.size()==2:
			query.transform.origin += query.motion*minf(1.0,fraction[1]+.0001)
			query.motion = Vector3.ZERO
			names = _hit_names(space.intersect_shape(query,8))
		cargo_sweep_diagnostics.first_would_block = {"physics_ticks":physics_ticks,"stage":active.get("stage",""),"cargo":id,
			"position":_v(cargo.global_position),"velocity":_v(cargo.linear_velocity),"motion_m":motion_m,
			"bounds_origin":_v(bounds.position),"bounds_size":_v(bounds.size),"initial_overlap":initial,"fraction":Array(fraction),"colliders":names}

func _append_point(points: Array[Vector3], point: Vector3) -> void:
	if points.is_empty() or points.back().distance_to(point)>.02: points.append(point)

func _serial() -> int:
	command_serial += 1
	return command_serial

func _fail(code: String,details: Dictionary) -> bool:
	if not fatal:
		fatal = true
		_check(false,code,details)
	return false

func _check(ok: bool,label: String,details: Dictionary = {}) -> bool:
	checks += 1
	if not ok:
		failures.append({"label":label,"details":details.duplicate(true)})
		print("FAIL "+label+" "+JSON.stringify(details))
	return ok

func _collect_inputs() -> void:
	for path: String in ["res://scripts/v3/candidates/canal_transport_physics/transport_pilot.gd","res://scripts/v3/candidates/canal_transport_physics/dock_lift.gd",
		"res://scripts/v3/candidates/canal_transport_physics/cargo_custody.gd","res://scripts/v3/candidates/canal_service_loop/canal_service_runtime.gd",
		"res://scripts/v2/flight_body.gd","res://scripts/v3/twin_test_world.gd","res://scripts/v3/world/twin_i2_waterfront_terrain.gd",
		"res://data/v3/terrain/i2_clinic_layout.json","res://data/v3/terrain/i2_distribution_trial_layout.json",
		"res://data/v3/terrain/i2_trial_flow_layout.json","res://data/v3/terrain/i2_shared_access_layout.json"]:
		inputs[path] = FileAccess.get_sha256(path)

func _evidence() -> Dictionary:
	return {"passed":failures.is_empty(),"checks":checks,"failures":failures,"fixtures":fixture_checks,"records":records,"receipts":receipts,
		"final":_sample(),"pending_action":current_action,"rules":rules.snapshot() if rules_started else {},
		"cargo_velocity_sweeps_diagnostic_only":cargo_sweep_diagnostics.duplicate(true),
		"input_sha256":inputs,"engine_errors":logger.errors,"scope":"real I2 candidate physical exchange only; no performed work, service, Store, multiplayer, graphics or human-play evidence"}

func _finish() -> void:
	if finished: return
	finished = true
	var unchanged: bool = true
	for path: String in inputs:
		if inputs[path].is_empty() or FileAccess.get_sha256(path) != inputs[path]: unchanged = false
	_check(unchanged,"recorded input source/model bytes unchanged")
	var result: Dictionary = _evidence()
	if is_instance_valid(world): world.queue_free()
	await process_frame
	if is_instance_valid(viewport): viewport.queue_free()
	await process_frame
	print("V3_I2_CANAL_EXCHANGE_RESULT "+JSON.stringify(result))
	quit(0 if failures.is_empty() else 1)

static func _v(value: Vector3) -> Array:
	return [value.x,value.y,value.z]

static func _vectors(values: Array[Vector3]) -> Array:
	var result: Array = []
	for value: Vector3 in values: result.append(_v(value))
	return result

static func _hit_names(hits: Array[Dictionary]) -> Array:
	var names: Array = []
	for hit: Dictionary in hits:
		var body: Variant = hit.get("collider")
		names.append(str(body.get_path()) if body is Node else str(body))
	return names
