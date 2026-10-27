extends SceneTree
## Real production I2 geometry, real FlightBody + 2 kg PinJoint fixture.
## One initial placement per airframe. No further pose/velocity assignment.
## Not Session/Store/network, berths, unloading, service or human-play evidence.
const World = preload("res://scripts/v3/twin_test_world.gd")
const Flight = preload("res://scripts/v2/flight_body.gd")
const Catalog = preload("res://scripts/v2/catalog.gd")
const Pilot = preload("res://scripts/v3/candidates/canal_transport_physics/transport_pilot.gd")
const START := Vector3(14.75,1.8,23)
const NORTH := Vector3(14.75,1.8,6)
const HIGH_SOUTH := Vector3(14.75,9,23)
const HIGH_NORTH := Vector3(14.75,9,6)
const OBSTACLES := 1 | 2 | 4 | 8 | 32
const MAX_LEG_SECONDS := 27.0
const MAX_BLOCKED_SECONDS := 3.0
var viewport: SubViewport
var world: World
var body: Flight
var cargo: RigidBody3D
var pilot: RefCounted
var checks: int = 0
var failures: Array = []
var observations: Dictionary = {}
var sources: Dictionary = {}
var active_record: Dictionary = {}
var active_leg: Dictionary = {}
var rescued_count: int = 0
var water_entries: int = 0
var cargo_water_seen: bool = false
var body_contacts: Dictionary = {}
var cargo_contacts: Dictionary = {}
var finished: bool = false
var serial: int = 0
var step_seconds: float = 1.0/60.0

class ErrorLogger extends Logger:
	var errors: Array = []
	func _log_error(function: String,file: String,line: int,code: String,rationale: String,_notify: bool,error_type: int,_backtraces: Array[ScriptBacktrace]) -> void:
		errors.append({"function":function,"file":file,"line":line,"code":code,"rationale":rationale,"type":error_type})
var logger := ErrorLogger.new()

func _init() -> void:
	OS.add_logger(logger)
	_run.call_deferred()

func _run() -> void:
	create_timer(220.0).timeout.connect(func():
		if not finished:
			print("I2_LOADED_ROUTE_TIMEOUT " + JSON.stringify({"checks":checks,"failures":failures,
				"observations":observations,"active":active_record,"leg":active_leg,"engine_errors":logger.errors}))
			quit(2))
	step_seconds = 1.0 / float(Engine.physics_ticks_per_second)
	_check(Engine.time_scale == 1.0 and Engine.physics_ticks_per_second == 60,"normal 60 Hz physics with no simulation speed-up")
	viewport = SubViewport.new()
	viewport.name = "IsolatedI2LoadedRoute"
	viewport.size = Vector2i(32,32)
	viewport.own_world_3d = true
	viewport.world_3d = World3D.new()
	viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	root.add_child(viewport)
	world = World.new()
	viewport.add_child(world)
	world.build("I2",{},true)
	_check(world.build_errors.is_empty(),"production I2 builds in its actual independent physics space",{"errors":world.build_errors})
	if not world.build_errors.is_empty():
		await _finish()
		return
	_check(is_instance_valid(world.clinic) and is_instance_valid(world.distribution) and is_instance_valid(world.trial) and is_instance_valid(world.shared_access),"all four real facilities present")
	_check(world.waterfront != null and world.waterfront_install.get("ok",false),"actual canal terrain replaces original ground collision")
	var art_ok: bool = world.clinic.gravity_art.get("ok",false) and world.clinic.reception_art.get("ok",false) and world.clinic.pump_art.get("ok",false) and world.clinic.ground_art.get("ok",false)
	art_ok = art_ok and world.shared_access.deck_art.get("ok",false) and world.shared_access.landing_art.get("ok",false)
	_check(art_ok,"production imported clinic and bridge art/collision contracts loaded")
	_collect_sources()
	observations.fixture = {"start":_v(START),"north":_v(NORTH),"cargo_size_m":[.4,.4,.4],
		"cargo_mass_kg":2.0,"initial_load_offset_m":[0,-1.1,0],"physics_hz":Engine.physics_ticks_per_second,
		"geometry":"World.build I2, default initial facility poses; no duplicate candidate facilities",
		"environment":"production query sampled each physics step; explicit world clock, default clear weather",
		"scope":"one initial pose per airframe, no placement/velocity writes during route; no Session, service or delivery"}
	for frame_id: String in ["tr01","hx02"]:
		await _run_airframe(frame_id)
	_check(_sources_unchanged(),"all recorded geometry/pilot/flight inputs retain exact bytes")
	_check(logger.errors.is_empty(),"no engine errors",{"errors":logger.errors})
	await _finish()

func _run_airframe(frame_id: String) -> void:
	active_record = {"airframe":frame_id,"legs":[],"high_route":"not_started"}
	observations[frame_id] = active_record
	body_contacts.clear()
	cargo_contacts.clear()
	rescued_count = 0
	water_entries = 0
	cargo_water_seen = false
	serial = 0
	body = Flight.new()
	var resolved: Dictionary = Catalog.resolve_build(Catalog.default_build(frame_id))
	_check(resolved.valid,frame_id + ": real catalog build valid")
	body.configure(resolved)
	body.freeze = true
	body.position = START
	body.hold_height = START.y
	body.safe_position = START
	body.max_altitude = 18.0
	world.add_child(body)
	body.name = "QA_Loaded_" + frame_id
	body.collision_mask = OBSTACLES
	body.environment_hazards_authoritative = true
	body.environment_query = world.sample_environment
	body.environment_sample = world.sample_environment(body.global_position)
	body.command = {"active":true,"mode":"assisted","brake":true}
	body.rescued.connect(func(): rescued_count += 1)
	body.water_entered.connect(func(): water_entries += 1)
	cargo = RigidBody3D.new()
	cargo.name = "QA_2kgCassette_" + frame_id
	cargo.mass = 2.0
	cargo.freeze = true
	cargo.position = START + Vector3.DOWN*1.1
	cargo.continuous_cd = true
	cargo.can_sleep = false
	cargo.contact_monitor = true
	cargo.max_contacts_reported = 16
	var collider := CollisionShape3D.new()
	collider.name = "ActualCassetteEnvelope"
	var shape := BoxShape3D.new()
	shape.size = Vector3(.4,.4,.4)
	collider.shape = shape
	cargo.add_child(collider)
	world.add_child(cargo)
	for index in range(3): await physics_frame
	var attached: bool = body.attach_cargo(cargo,"qa_route_"+frame_id,2.0)
	_check(attached and body.cargo_joint is PinJoint3D and is_equal_approx(body.cargo_kg,2.0),frame_id + ": actual 2 kg PinJoint attached once")
	if not attached:
		await _teardown_airframe()
		return
	cargo.collision_mask = OBSTACLES
	body.add_collision_exception_with(cargo)
	cargo.add_collision_exception_with(body)
	pilot = Pilot.new()
	_check(pilot.bind(body),frame_id + ": unchanged transport pilot binds real body")
	active_record.initial = _sample()
	var initial_probe: Dictionary = pilot.probe(Vector3.ZERO)
	active_record.initial_probe = initial_probe
	_check(initial_probe.get("clear",false),frame_id + ": initial complete hull/load envelope is clear",{"probe":initial_probe,"diagnosis":_probe_diagnosis(Vector3.ZERO)})
	if not initial_probe.get("clear",false):
		active_record.low_route = "initial_envelope_blocked"
		active_record.high_route = "skipped_failed_low"
		await _teardown_airframe()
		return
	body.freeze = false
	cargo.freeze = false
	var outbound: bool = await _leg(frame_id,"low_north",NORTH)
	var inbound: bool = false
	if outbound: inbound = await _leg(frame_id,"low_south",START)
	var low_ok: bool = outbound and inbound and _safe_outcome()
	active_record.low_route = "passed" if low_ok else "failed"
	_check(low_ok,frame_id + ": loaded low route actually reaches north and returns without collision/water/rescue")
	if low_ok:
		active_record.high_route = "running"
		var high_ok: bool = true
		for leg_spec in [["high_climb_south",HIGH_SOUTH],["high_north",HIGH_NORTH],["high_south",HIGH_SOUTH],["high_descend_south",START]]:
			if not await _leg(frame_id,str(leg_spec[0]),leg_spec[1]):
				high_ok = false
				break
		high_ok = high_ok and _safe_outcome()
		active_record.high_route = "passed" if high_ok else "failed"
		_check(high_ok,frame_id + ": same body physically climbs to 9 m, crosses/returns and descends without resets")
	else:
		active_record.high_route = "skipped_failed_low"
	active_record.final = _sample()
	active_record.body_contacts = body_contacts.duplicate(true)
	active_record.cargo_contacts = cargo_contacts.duplicate(true)
	active_record.rescues = rescued_count
	active_record.water_entries = water_entries
	active_record.cargo_water_seen = cargo_water_seen
	await _teardown_airframe()

func _leg(frame_id: String,label: String,target: Vector3) -> bool:
	serial += 1
	active_leg = {"id":label,"target":_v(target),"start":_sample(),"samples":[],"max_speed_mps":0.0,
		"max_cargo_speed_mps":0.0,"max_swing_deg":0.0,"min_cargo_bottom_y":1000.0,
		"blocked_seconds":0.0,"arrival":false,"stop_reason":"timeout"}
	active_record.legs.append(active_leg)
	var accepted: bool = pilot.go_to(target,serial)
	_check(accepted,frame_id + "/" + label + ": waypoint is an accepted command, not a pose change")
	if not accepted: return false
	var blocked_run: float = 0.0
	var maximum_steps: int = int(ceil(MAX_LEG_SECONDS/step_seconds))
	for index in range(maximum_steps):
		await physics_frame
		world.clock_seconds += step_seconds
		body.environment_sample = world.sample_environment(body.global_position)
		var report: Dictionary = pilot.tick(step_seconds,true,false)
		_capture_contacts()
		active_leg.max_speed_mps = maxf(float(active_leg.max_speed_mps),body.linear_velocity.length())
		active_leg.max_cargo_speed_mps = maxf(float(active_leg.max_cargo_speed_mps),cargo.linear_velocity.length())
		active_leg.max_swing_deg = maxf(float(active_leg.max_swing_deg),body.cargo_swing())
		var load_bounds: AABB = cargo.get_node("ActualCassetteEnvelope").global_transform * AABB(Vector3(-.2,-.2,-.2),Vector3(.4,.4,.4))
		active_leg.min_cargo_bottom_y = minf(float(active_leg.min_cargo_bottom_y),load_bounds.position.y)
		if index % 60 == 0: active_leg.samples.append(_sample())
		if report.state == "blocked":
			blocked_run += step_seconds
			active_leg.blocked_seconds += step_seconds
			if not active_leg.has("first_blocked"):
				active_leg.first_blocked = {"sample":_sample(),"report":report,"actual_obstacles":_probe_diagnosis(_desired_velocity(target))}
		else: blocked_run = 0.0
		active_leg.elapsed_seconds = float(index+1)*step_seconds
		if not _safe_outcome():
			active_leg.stop_reason = "contact_damage_water_or_joint_loss"
			break
		if blocked_run >= MAX_BLOCKED_SECONDS:
			active_leg.stop_reason = "sustained_physical_envelope_block"
			break
		if report.arrived:
			active_leg.arrival = true
			active_leg.stop_reason = "arrived"
			break
	active_leg.finish = _sample()
	active_leg.final_report = pilot.report()
	var actual_arrival: bool = active_leg.arrival and body.global_position.distance_to(target)<.18 and body.linear_velocity.length()<.18 and cargo.linear_velocity.length()<.3 and pilot.settled_seconds>=.35
	_check(actual_arrival,frame_id + "/" + label + ": true pose + hull/load rest prove arrival",{"stop":active_leg.stop_reason,"finish":active_leg.finish,"report":active_leg.final_report,"blocked":active_leg.get("first_blocked",{})})
	return actual_arrival and _safe_outcome()

func _safe_outcome() -> bool:
	return body.enabled and body.health == body.maximum_health and body.collision_count == 0 and body_contacts.is_empty() and cargo_contacts.is_empty() and rescued_count == 0 and water_entries == 0 and not body.water_contact and not cargo_water_seen and is_instance_valid(body.cargo_joint) and body.cargo_items.size() == 1 and body.global_position.is_finite() and cargo.global_position.is_finite()

func _capture_contacts() -> void:
	for other: Node in body.get_colliding_bodies():
		if other != cargo: body_contacts[str(other.get_path())] = true
	for other: Node in cargo.get_colliding_bodies():
		if other != body: cargo_contacts[str(other.get_path())] = true
	cargo_water_seen = cargo_water_seen or _cargo_in_water()

func _cargo_in_water() -> bool:
	var shape: CollisionShape3D = cargo.get_node("ActualCassetteEnvelope")
	var bounds: AABB = shape.global_transform*AABB(Vector3(-.2,-.2,-.2),Vector3(.4,.4,.4))
	# Query actual lower envelope corners, not just hull-centre water status.
	for x: float in [bounds.position.x,bounds.end.x]:
		for z: float in [bounds.position.z,bounds.end.z]:
			var at := Vector3(x,bounds.position.y,z)
			var environment: Dictionary = world.sample_environment(at)
			if environment.get("water",false) and at.y<float(environment.get("water_height",-1000)): return true
	return false

func _sample() -> Dictionary:
	if not is_instance_valid(body) or not is_instance_valid(cargo): return {}
	var cargo_field: Dictionary = world.sample_environment(cargo.global_position)
	return {"body":_v(body.global_position),"velocity":_v(body.linear_velocity),"cargo":_v(cargo.global_position),
		"cargo_velocity":_v(cargo.linear_velocity),"cargo_speed_mps":cargo.linear_velocity.length(),"swing_deg":body.cargo_swing(),
		"health":body.health,"battery":body.battery,"body_water":body.water_contact,"water_seconds":body.water_seconds,
		"environment":body.environment_sample.duplicate(true),"cargo_environment":cargo_field,
		"cargo_below_water":_cargo_in_water(),
		"collision_count":body.collision_count,"body_contact_paths":body_contacts.keys(),"cargo_contact_paths":cargo_contacts.keys(),
		"joint_alive":is_instance_valid(body.cargo_joint),"pilot_state":pilot.state if is_instance_valid(pilot) else "unbound"}

func _desired_velocity(target: Vector3) -> Vector3:
	var offset: Vector3 = target-body.global_position
	var horizontal: Vector3 = Vector3(offset.x,0,offset.z).limit_length(Pilot.MAX_SPEED)
	return Vector3(horizontal.x,clampf(offset.y*1.2,-.7,.7),horizontal.z)

func _probe_diagnosis(desired: Vector3) -> Dictionary:
	# Read-only reproduction of the pilot's exact live merged Box envelope.
	# It only names the colliders; it does not override the pilot decision.
	var bounds := AABB()
	var initialized: bool = false
	var excluded: Array[RID] = [body.get_rid(),cargo.get_rid()]
	for part: RigidBody3D in [body,cargo]:
		for child: Node in part.get_children():
			if child is CollisionShape3D and not child.disabled and child.shape is BoxShape3D:
				var size: Vector3 = child.shape.size
				var actual: AABB = child.global_transform*AABB(-size*.5,size)
				bounds = bounds.merge(actual) if initialized else actual
				initialized = true
	if not initialized: return {"reason":"missing_box"}
	bounds = bounds.grow(Pilot.CLEARANCE)
	var shape := BoxShape3D.new()
	shape.size = bounds.size
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = shape
	query.transform = Transform3D(Basis.IDENTITY,bounds.get_center())
	query.collision_mask = OBSTACLES
	query.exclude = excluded
	var space: PhysicsDirectSpaceState3D = world.get_world_3d().direct_space_state
	var result: Dictionary = {"bounds_position":_v(bounds.position),"bounds_size":_v(bounds.size),"initial":_hit_names(space.intersect_shape(query,16)),"sweeps":[]}
	for velocity: Vector3 in [body.linear_velocity,desired]:
		if velocity.length()<.01: continue
		query.transform.origin = bounds.get_center()
		query.motion = velocity.normalized()*(velocity.length()+velocity.length_squared()/4.0+.35)
		var fraction: PackedFloat32Array = space.cast_motion(query)
		var row: Dictionary = {"motion":_v(query.motion),"fraction":Array(fraction),"hit_paths":[]}
		if fraction.size()==2 and fraction[0]<.999:
			query.transform.origin = bounds.get_center()+query.motion*minf(1.0,float(fraction[1])+.001)
			var motion: Vector3 = query.motion
			query.motion = Vector3.ZERO
			row.hit_paths = _hit_names(space.intersect_shape(query,16))
			query.motion = motion
		result.sweeps.append(row)
	return result

func _hit_names(hits: Array[Dictionary]) -> Array:
	var result: Array = []
	for hit in hits:
		var object: Object = hit.get("collider")
		if object is Node: result.append(str(object.get_path()))
	return result

func _collect_sources() -> void:
	for path: String in ["res://scripts/v3/candidates/canal_transport_physics/transport_pilot.gd","res://scripts/v2/flight_body.gd",
		"res://scripts/v3/twin_test_world.gd","res://scripts/v3/world/twin_i2_waterfront_terrain.gd",
		"res://data/v3/terrain/i2_clinic_layout.json","res://data/v3/terrain/i2_distribution_trial_layout.json",
		"res://data/v3/terrain/i2_trial_flow_layout.json","res://data/v3/terrain/i2_shared_access_layout.json"]:
		sources[path] = FileAccess.get_sha256(path)
	for art: Dictionary in [world.clinic.gravity_art,world.clinic.reception_art,world.clinic.pump_art,world.shared_access.deck_art,world.shared_access.landing_art]:
		var path: String = str(art.get("path",""))
		if not path.is_empty(): sources[path] = FileAccess.get_sha256(path)
	_check(not sources.values().has(""),"recorded source and imported-model paths have real bytes")

func _sources_unchanged() -> bool:
	for path in sources:
		if FileAccess.get_sha256(path)!=sources[path]: return false
	return true

func _teardown_airframe() -> void:
	# End-of-case destruction only; never counted as drop/delivery.
	if is_instance_valid(body):
		body.freeze = true
		if is_instance_valid(cargo): cargo.freeze = true
		if not body.cargo_items.is_empty(): body.release_cargo()
		body.queue_free()
	if is_instance_valid(cargo): cargo.queue_free()
	pilot = null
	await process_frame
	await physics_frame

func _finish() -> void:
	finished = true
	if is_instance_valid(world): world.queue_free()
	await process_frame
	if is_instance_valid(viewport): viewport.queue_free()
	await process_frame
	print("V3_I2_LOADED_ROUTE_RESULT " + JSON.stringify({"passed":failures.is_empty(),"checks":checks,"failures":failures,
		"observations":observations,"input_sha256":sources,"engine_errors":logger.errors,
		"scope":"actual production geometry + real isolated loaded flight; not delivery, Store, network, rendered camera or human-play validation"}))
	quit(0 if failures.is_empty() else 1)

func _check(ok: bool,label: String,details: Dictionary={}) -> void:
	checks += 1
	if not ok:
		failures.append({"label":label,"details":details})
		print("FAIL " + label + " " + JSON.stringify(details))

static func _v(value: Vector3) -> Array:
	return [value.x,value.y,value.z]
