extends SceneTree
## Isolated real bodies/joints. Initial placements and named obstruction bodies
## are QA fixtures; no route, Store, service or complete I2 exchange is asserted.
const Flight = preload("res://scripts/v2/flight_body.gd")
const Catalog = preload("res://scripts/v2/catalog.gd")
const Pilot = preload("res://scripts/v3/candidates/canal_transport_physics/transport_pilot.gd")
const Dock = preload("res://scripts/v3/candidates/canal_transport_physics/dock_lift.gd")
const Custody = preload("res://scripts/v3/candidates/canal_transport_physics/cargo_custody.gd")
const DT := 1.0/60.0
const MASK := 1|2|4|8|32
var checks := 0
var failures: Array = []
var observations: Dictionary = {}
var finished := false
class ErrorLogger extends Logger:
	var errors: Array = []
	func _log_error(function: String,file: String,line: int,code: String,rationale: String,_notify: bool,error_type: int,_backtraces: Array[ScriptBacktrace]) -> void:
		errors.append({"function":function,"file":file,"line":line,"code":code,"rationale":rationale,"type":error_type})
var logger := ErrorLogger.new()

func _init() -> void:
	OS.add_logger(logger)
	_run.call_deferred()

func _run() -> void:
	create_timer(105).timeout.connect(func():
		if not finished:
			print("CARGO_INERTIA_TIMEOUT "+JSON.stringify({"observations":observations,"failures":failures,"engine_errors":logger.errors}))
			quit(2))
	await _swing_case("low_wall",Vector3(1.6,2.05,0),Vector3(.15,.6,4),Vector3(3.2,0,0))
	await _swing_case("high_side_beam",Vector3(1.6,3.3,0),Vector3(.15,.3,2),Vector3(3.2,0,0))
	await _swing_case("rising_load_beam",Vector3(2.0,2.9,0),Vector3(.2,.2,2),Vector3(4,0,0))
	await _dock_boundary()
	await _invalid_envelopes()
	_check(logger.errors.is_empty(),"no captured engine errors",{"errors":logger.errors})
	finished = true
	print("V3_CARGO_INERTIA_RESULT "+JSON.stringify({"checks":checks,"failures":failures,"engine_errors":logger.errors,"observations":observations,
		"scope":"isolated physical swing / geometric negative control / dock handoff; no full exchange, service, Store, network or human-play proof"}))
	quit(0 if failures.is_empty() else 1)

func _fixture(on_berth: bool = false, frozen: bool = false) -> Dictionary:
	var vp := SubViewport.new()
	vp.size = Vector2i(32,32)
	vp.own_world_3d = true
	vp.world_3d = World3D.new()
	vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	root.add_child(vp)
	var world := Node3D.new()
	vp.add_child(world)
	_box(world,"Ground",Vector3(0,-.65,0),Vector3(24,.5,24))
	var berth: StaticBody3D = _box(world,"ActualBerth",Vector3.ZERO,Vector3(2,.5,2)) if on_berth else null
	var body := Flight.new()
	body.configure(Catalog.resolve_build(Catalog.default_build("tr01")))
	body.freeze = true
	body.position = Vector3(0,1.55 if on_berth else 3.2,0)
	body.hold_height = body.position.y
	world.add_child(body)
	body.collision_layer = 8
	body.collision_mask = MASK
	body.command = {"active":true,"mode":"assisted","planar":Vector3.ZERO,"vertical":0.0,"brake":true}
	var cargo := RigidBody3D.new()
	cargo.name = "PhysicalCassette"
	cargo.mass = 2.0
	cargo.freeze = not on_berth
	cargo.position = Vector3(0,.46 if on_berth else 2.1,0)
	cargo.collision_layer = 8
	cargo.collision_mask = MASK
	cargo.continuous_cd = true
	cargo.can_sleep = false
	cargo.contact_monitor = true
	cargo.max_contacts_reported = 12
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(.4,.4,.4)
	collision.shape = shape
	cargo.add_child(collision)
	world.add_child(cargo)
	var pilot := Pilot.new()
	var ctx := {"vp":vp,"world":world,"body":body,"cargo":cargo,"shape":collision,"berth":berth,"pilot":pilot,"ok":false}
	if not _check(pilot.bind(body),"fixture binds actual FlightBody"): return ctx
	for i in (60 if on_berth else 3): await physics_frame
	if on_berth:
		var custody := Custody.new()
		ctx.custody = custody
		var configured: Dictionary = custody.configure({"load":cargo},{"berth":berth},{"carrier":body},true)
		if not _check(configured.ok,"dock fixture uses real custody registry",configured): return ctx
		var seated: Dictionary = custody.seat("load","berth",1,custody.revision)
		if not _check(seated.ok,"cargo genuinely starts over real support",seated): return ctx
		for i in 30:
			await physics_frame
			custody.step(DT)
		if not _check(custody.report().cargos.load.phase=="docked" and cargo.get_colliding_bodies().has(berth),"initial berth becomes docked only through real stable contact"): return ctx
		var picked: Dictionary = custody.pickup("load","carrier",2,custody.revision)
		if not _check(picked.ok,"real supported pickup creates physical joint",picked): return ctx
	else:
		if not _check(body.attach_cargo(cargo,"load",2.0),"initial aerial fixture attaches actual PinJoint"): return ctx
		cargo.collision_mask = MASK
	if not _check(body.cargo_joint is PinJoint3D and body.cargo_items.size()==1 and is_equal_approx(body.cargo_kg,2),"exactly one actual 2kg load and joint"): return ctx
	ctx.ok = true
	if not frozen and not on_berth:
		body.freeze = false
		cargo.freeze = false
		for i in 40: await physics_frame
	return ctx

func _swing_case(id: String, obstacle_at: Vector3, obstacle_size: Vector3, impulse: Vector3) -> void:
	var ctx: Dictionary = await _fixture()
	if not ctx.ok:
		await _dispose(ctx)
		return
	var body: Flight = ctx.body
	var cargo: RigidBody3D = ctx.cargo
	var pilot: RefCounted = ctx.pilot
	var obstacle := _box(ctx.world,id,obstacle_at,obstacle_size,2)
	for i in 2: await physics_frame
	var old_initial: Dictionary = pilot.probe(Vector3.ZERO)
	if not _check(old_initial.clear,id+": fixture starts with clear original full envelope",old_initial):
		await _dispose(ctx)
		return
	_check(pilot.go_to(Vector3(0,3.2,-2),1),id+": unchanged real flight waypoint accepted")
	# Impulse changes real momentum; neither body's pose nor velocity is assigned.
	cargo.apply_central_impulse(impulse)
	var found := false
	var event: Dictionary = {}
	var samples: Array = []
	var contacts := 0
	var rejected_frames := 0
	var longest_rejection := 0
	var streak := 0
	var gate_brakes := true
	for i in 60:
		await physics_frame
		var original: Dictionary = pilot.probe(Vector3.ZERO)
		var own: Dictionary = pilot._cargo_inertia_probe()
		var load_box := _bounds(cargo).grow(Pilot.CLEARANCE)
		var merged_box := _bounds(body).merge(_bounds(cargo)).grow(Pilot.CLEARANCE)
		# Counterfactual measurements use actual PhysicsServer queries, not fake
		# success flags: union-along-swing is the rejected implementation option.
		var union_swing: Dictionary = _cast(ctx,merged_box,cargo.linear_velocity)
		var flat_swing: Dictionary = _cast(ctx,load_box,Vector3(cargo.linear_velocity.x,0,cargo.linear_velocity.z))
		var row: Dictionary = pilot.tick(DT)
		var cargo_rejected: bool = row.speed_plan.reason=="cargo_inertia_unsafe"
		if cargo_rejected:
			rejected_frames += 1
			streak += 1
			longest_rejection = maxi(longest_rejection,streak)
			gate_brakes = gate_brakes and body.command.brake and not row.speed_plan.commanded and row.speed_plan.attempts.is_empty() and not row.arrived
		else: streak = 0
		contacts += _contacts(cargo,body)
		var distinguishes: bool = original.clear and not own.clear and not own.get("initial_overlap",false) and str(own.get("collider","")).ends_with("/"+id)
		if id=="high_side_beam": distinguishes = original.clear and own.clear and not union_swing.clear and row.speed_plan.commanded
		if id=="rising_load_beam": distinguishes = distinguishes and cargo.linear_velocity.y>.05 and flat_swing.clear
		var snapshot := {"frame":i,"body_at":body.global_position,"cargo_at":cargo.global_position,"body_velocity":body.linear_velocity,"cargo_velocity":cargo.linear_velocity,
			"cargo_angular":cargo.angular_velocity,"old_actual":original,"own_actual":own,"union_along_swing":union_swing,"flattened_load_sweep":flat_swing,"controller":row}
		if i%15==0: samples.append(snapshot)
		if distinguishes:
			found = true
			event = snapshot
			break
	_check(found,id+": actual physical query establishes the intended difference",{"event":event,"samples":samples})
	if id=="high_side_beam":
		_check(found and event.controller.speed_plan.commanded and event.controller.speed_plan.cargo_actual_probe.clear,"high-only obstacle does not become a cargo gate from sweeping the whole hull along load velocity",event)
	else:
		_check(found and event.controller.speed_plan.reason=="cargo_inertia_unsafe" and event.controller.speed_plan.attempts.is_empty() and body.command.brake and not event.controller.arrived,id+": own cargo inertia rejects before desired-speed search",event)
	# Keep the real obstruction briefly, then remove only this named QA body.
	# Removal tests recovery; it never moves either actor or erases momentum.
	for i in 90:
		await physics_frame
		var row: Dictionary = pilot.tick(DT)
		var rejected: bool = row.speed_plan.reason=="cargo_inertia_unsafe"
		if rejected:
			rejected_frames += 1
			streak += 1
			longest_rejection = maxi(longest_rejection,streak)
			gate_brakes = gate_brakes and body.command.brake and not row.speed_plan.commanded and row.speed_plan.attempts.is_empty() and not row.arrived
		else: streak = 0
		contacts += _contacts(cargo,body)
	obstacle.queue_free()
	await physics_frame
	var arrived := false
	for i in 600:
		await physics_frame
		var row: Dictionary = pilot.tick(DT)
		contacts += _contacts(cargo,body)
		if row.arrived:
			arrived = true
			break
	_check(gate_brakes,id+": every observed cargo rejection uses braking without arrival or speed fallback")
	_check(arrived and body.global_position.distance_to(Vector3(0,3.2,-2))<.18 and body.linear_velocity.length()<.18,id+": removal recovers real stable travel without retarget or teleport",pilot.report())
	_check(contacts==0 and body.collision_count==0 and body.health==body.maximum_health and body.cargo_joint is PinJoint3D,id+": hull and cargo remain collision free with real joint",{"cargo_contacts":contacts,"body_collisions":body.collision_count,"health":body.health})
	observations[id] = {"difference":event,"samples":samples,"cargo_reject_frames":rejected_frames,"longest_consecutive_rejection":longest_rejection,"final":pilot.report(),"cargo_contacts":contacts}
	await _dispose(ctx)

func _dock_boundary() -> void:
	var ctx: Dictionary = await _fixture(true)
	if not ctx.ok:
		await _dispose(ctx)
		return
	var body: Flight = ctx.body
	var cargo: RigidBody3D = ctx.cargo
	var berth: StaticBody3D = ctx.berth
	var custody: RefCounted = ctx.custody
	var pilot: RefCounted = ctx.pilot
	var original: Dictionary = pilot.probe(Vector3.ZERO)
	var own: Dictionary = pilot._cargo_inertia_probe()
	_check(not original.clear and not own.clear and own.get("initial_overlap",false),"ordinary envelope and cargo guard both retain actual support obstruction",{"public_probe":original,"cargo_probe":own})
	_check(pilot.go_to(Vector3(0,2.2,0),1),"ordinary departure intent keeps original waypoint contract")
	var refused: Dictionary = pilot.tick(DT)
	_check(refused.state=="blocked" and body.command.brake and not refused.arrived,"ordinary controller cannot silently exclude the berth",refused)
	var dock := Dock.new()
	var started: Dictionary = dock.begin(body,berth,1,true)
	if not _check(started.ok,"existing Dock begins from true support and joint",started):
		await _dispose(ctx)
		return
	var ceiling := _box(ctx.world,"DockCeiling",Vector3(0,2.15,0),Vector3(2,.1,2))
	body.freeze = false
	var blocked := 0
	for i in 90:
		await physics_frame
		custody.step(DT)
		var row: Dictionary = dock.tick(DT)
		if row.state=="blocked": blocked += 1
	_check(blocked>60 and body.cargo_joint is PinJoint3D and body.health==body.maximum_health,"actual departure ceiling blocks existing Dock with load retained",{"blocked_frames":blocked,"dock":dock.report()})
	ceiling.queue_free()
	await physics_frame
	var lifted := false
	for i in 720:
		await physics_frame
		custody.step(DT)
		var row: Dictionary = dock.tick(DT)
		if row.clear:
			lifted = true
			break
	if not _check(lifted,"original Dock physically separates from support after removing only ceiling",dock.report()):
		await _dispose(ctx)
		return
	var handoff: Dictionary = pilot._cargo_inertia_probe()
	var target_y: float = body.global_position.y
	var out_ok: bool = await _dock_leg(ctx,Vector3(0,target_y,-2),2)
	var back_ok := false
	if out_ok: back_ok = await _dock_leg(ctx,Vector3(0,target_y,0),3)
	if not _check(out_ok and back_ok,"ordinary controller accepts only actual safe cargo handoff and returns by real flight",{"handoff":handoff,"pilot":pilot.report()}):
		await _dispose(ctx)
		return
	for i in 240:
		await physics_frame
		custody.step(DT)
		_brake(body)
		if body.linear_velocity.length()<.12 and cargo.linear_velocity.length()<.12 and cargo.angular_velocity.length()<.1: break
	var approach: Dictionary = dock.begin_approach(body,berth,2,true)
	if not _check(approach.ok,"existing approach rechecks real support column and load speed",approach):
		await _dispose(ctx)
		return
	var ready := false
	for i in 720:
		await physics_frame
		custody.step(DT)
		var row: Dictionary = dock.tick(DT)
		if row.ready_for_release:
			ready = true
			break
	var release: Dictionary = {}
	for i in 240:
		await physics_frame
		custody.step(DT)
		_brake(body)
		release = custody.release_info("load","berth")
		if release.ok: break
	if not _check(ready and release.get("ok",false),"unchanged custody pose/speed/footprint permits bounded release after real approach",release):
		await _dispose(ctx)
		return
	var before_drop: float = cargo.global_position.y
	var dropped: Dictionary = custody.release_to("load","berth",3,custody.revision)
	if not _check(dropped.ok and body.cargo_items.is_empty(),"actual release destroys joint only after original physical checks",dropped):
		await _dispose(ctx)
		return
	var events := 0
	for i in 300:
		await physics_frame
		_brake(body)
		var row: Dictionary = custody.step(DT)
		for event: Dictionary in row.get("changes",[]):
			if event.phase=="docked": events += 1
		if custody.report().cargos.load.phase=="docked": break
	_check(events==1 and cargo.global_position.y<before_drop-.1 and cargo.get_colliding_bodies().has(berth) and custody.report().cargos.load.stable_usec==350000,"real gravity fall and stable support complete one physical handoff",custody.report())
	observations.dock = {"initial_public":original,"initial_cargo":own,"handoff_cargo":handoff,"release":release,"final":custody.report(),"health":body.health,"collisions":body.collision_count}
	await _dispose(ctx)

func _dock_leg(ctx: Dictionary, target: Vector3, serial: int) -> bool:
	var body: Flight = ctx.body
	var pilot: RefCounted = ctx.pilot
	var custody: RefCounted = ctx.custody
	if not pilot.go_to(target,serial): return false
	for i in 720:
		await physics_frame
		custody.step(DT)
		var row: Dictionary = pilot.tick(DT)
		if row.speed_plan.get("reason","")=="cargo_inertia_unsafe" and (not body.command.brake or row.speed_plan.commanded or row.arrived): return false
		if row.arrived: return true
	return false

func _invalid_envelopes() -> void:
	# Frozen is an initial stationary fixture, not an in-flight velocity reset.
	var ctx: Dictionary = await _fixture(false,true)
	if not ctx.ok:
		await _dispose(ctx)
		return
	var cargo: RigidBody3D = ctx.cargo
	var body: Flight = ctx.body
	var pilot: RefCounted = ctx.pilot
	var obstacle := _box(ctx.world,"RestingClearanceBlock",Vector3(.32,2.1,0),Vector3(.1,.2,.2),2)
	await physics_frame
	var rest: Dictionary = pilot._cargo_inertia_probe()
	_check(cargo.linear_velocity.is_zero_approx() and not rest.clear and rest.get("initial_overlap",false),"zero-speed load still tests actual initial envelope occupancy",rest)
	obstacle.queue_free()
	await physics_frame
	var unsupported := CollisionShape3D.new()
	unsupported.shape = SphereShape3D.new()
	cargo.add_child(unsupported)
	await physics_frame
	var bad: Dictionary = pilot._cargo_inertia_probe()
	_check(not bad.clear and bad.reason=="unsupported_load_envelope","enabled unsupported collider is rejected rather than skipped",bad)
	unsupported.queue_free()
	await physics_frame
	var collision: CollisionShape3D = ctx.shape
	collision.disabled = true
	await physics_frame
	bad = pilot._cargo_inertia_probe()
	_check(not bad.clear and bad.reason=="missing_load_envelope","load with no active collider is rejected",bad)
	collision.disabled = false
	await physics_frame
	# Deliberate registry corruption, with no physics tick while substituted.
	# Actual original joint stays attached to original cargo throughout.
	var other := SubViewport.new()
	other.own_world_3d = true
	other.world_3d = World3D.new()
	other.render_target_update_mode = SubViewport.UPDATE_DISABLED
	root.add_child(other)
	var foreign := RigidBody3D.new()
	foreign.freeze = true
	var foreign_shape := CollisionShape3D.new()
	foreign_shape.shape = BoxShape3D.new()
	foreign.add_child(foreign_shape)
	other.add_child(foreign)
	var original: Dictionary = body.cargo_items.load
	var malformed: Dictionary = original.duplicate()
	malformed.body = foreign
	body.cargo_items.load = malformed
	bad = pilot._cargo_inertia_probe()
	body.cargo_items.load = original
	_check(not bad.clear and bad.reason=="different_space" and body.cargo_joint is PinJoint3D,"foreign-world registry entry fails closed without rebinding actual joint",bad)
	other.queue_free()
	await process_frame
	_check(pilot._cargo_inertia_probe().clear,"restoring only test metadata/colliders restores actual clear geometry")
	observations.envelope_rejection = {"zero_speed_overlap":rest,"foreign_world":bad}
	await _dispose(ctx)

func _cast(ctx: Dictionary,bounds: AABB,velocity: Vector3) -> Dictionary:
	var body: Flight = ctx.body
	var cargo: RigidBody3D = ctx.cargo
	var shape := BoxShape3D.new()
	shape.size = bounds.size
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = shape
	query.transform = Transform3D(Basis.IDENTITY,bounds.get_center())
	query.collision_mask = MASK
	var excluded: Array[RID] = [body.get_rid(),cargo.get_rid()]
	query.exclude = excluded
	var space: PhysicsDirectSpaceState3D = body.get_world_3d().direct_space_state
	var hits := space.intersect_shape(query,1)
	if not hits.is_empty(): return {"clear":false,"initial_overlap":true}
	var speed := velocity.length()
	if speed<.01: return {"clear":true,"initial_overlap":false}
	query.motion = velocity.normalized()*(speed+speed*speed/4.0+.35)
	var fractions := space.cast_motion(query)
	return {"clear":fractions.size()==2 and fractions[0]>=.999,"initial_overlap":false,"fraction":Array(fractions),"motion_m":query.motion.length()}

func _bounds(part: PhysicsBody3D) -> AABB:
	var result := AABB()
	var initialized := false
	for child: Node in part.get_children():
		if child is CollisionShape3D and not child.disabled and child.shape is BoxShape3D:
			var size: Vector3 = child.shape.size
			var box: AABB = child.global_transform*AABB(-size*.5,size)
			result = result.merge(box) if initialized else box
			initialized = true
	return result

func _box(world: Node3D,id: String,at: Vector3,size: Vector3,layer: int = 1) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = id
	body.position = at
	body.collision_layer = layer
	body.collision_mask = 0
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	collision.shape = shape
	body.add_child(collision)
	world.add_child(body)
	return body

func _contacts(cargo: RigidBody3D,body: Flight) -> int:
	var count := 0
	for hit: Node in cargo.get_colliding_bodies():
		if hit != body: count += 1
	return count

func _brake(body: Flight) -> void:
	body.command = {"active":true,"mode":"assisted","planar":Vector3.ZERO,"vertical":0.0,"brake":true}

func _dispose(ctx: Dictionary) -> void:
	var vp: SubViewport = ctx.vp
	vp.queue_free()
	await process_frame

func _check(condition: bool,label: String,details: Dictionary = {}) -> bool:
	checks += 1
	if not condition: failures.append({"check":label,"details":details.duplicate(true)})
	return condition
