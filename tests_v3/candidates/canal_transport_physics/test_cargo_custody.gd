extends SceneTree
## Isolated real bodies/supports, no Session/Store or production berth claim.
## Initial fixture placement only. After that: forces/Flight commands and gravity.
const Custody = preload("res://scripts/v3/candidates/canal_transport_physics/cargo_custody.gd")
const Flight = preload("res://scripts/v2/flight_body.gd")
const Catalog = preload("res://scripts/v2/catalog.gd")
const Pilot = preload("res://scripts/v3/candidates/canal_transport_physics/transport_pilot.gd")
const Dock = preload("res://scripts/v3/candidates/canal_transport_physics/dock_lift.gd")
var viewport: SubViewport
var world: Node3D
var carrier: Flight
var other: Flight
var cargo: RigidBody3D
var second: RigidBody3D
var berth: StaticBody3D
var occupied: StaticBody3D
var custody: RefCounted
var checks: int = 0
var failures: Array = []
var observations: Dictionary = {}
var finished: bool = false
const DT := 1.0/60.0

class ErrorLogger extends Logger:
	var errors: Array = []
	func _log_error(function: String,file: String,line: int,code: String,rationale: String,_notify: bool,error_type: int,_backtraces: Array[ScriptBacktrace]) -> void:
		errors.append({"function":function,"file":file,"line":line,"code":code,"rationale":rationale,"type":error_type})
var logger := ErrorLogger.new()

func _init() -> void:
	OS.add_logger(logger)
	_run.call_deferred()

func _run() -> void:
	var custody_script: Script = Custody
	if not custody_script.can_instantiate():
		_check(false,"custody script can instantiate before any physics fixture")
		finished = true
		print("V3_CARGO_CUSTODY_RESULT "+JSON.stringify({"checks":checks,"failures":failures,"engine_errors":logger.errors,"stage":"script_initialization"}))
		quit(1)
		return
	create_timer(100.0).timeout.connect(func():
		if not finished:
			print("CARGO_CUSTODY_TIMEOUT "+JSON.stringify({"checks":checks,"failures":failures,"observations":observations,"errors":logger.errors}))
			quit(2))
	viewport = SubViewport.new()
	viewport.size = Vector2i(32,32)
	viewport.own_world_3d = true
	viewport.world_3d = World3D.new()
	viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	root.add_child(viewport)
	for frame_id: String in ["tr01","hx02"]:
		await _happy_path(frame_id)
	await _offset_pickup_alignment()
	await _interruptions()
	await _authority_and_faults()
	_check(logger.errors.is_empty(),"no engine errors",{"errors":logger.errors})
	await _cleanup()
	viewport.queue_free()
	await process_frame
	finished = true
	print("V3_CARGO_CUSTODY_RESULT "+JSON.stringify({"checks":checks,"failures":failures,"observations":observations,"engine_errors":logger.errors,
		"scope":"isolated true supports/PinJoint/drop; fixed initial poses are fixtures; no full route, service receipt, Store, networking or human test"}))
	quit(0 if failures.is_empty() else 1)

func _setup(frame_id: String = "tr01",authority: bool = true,cargo_offset: Vector3 = Vector3.ZERO) -> bool:
	await _cleanup()
	world = Node3D.new()
	viewport.add_child(world)
	_box(Vector3(0,-.6,0),Vector3(20,.5,20))
	berth = _box(Vector3.ZERO,Vector3(2,.5,2))
	berth.name = "BerthSouth0"
	occupied = _box(Vector3(3,0,0),Vector3(2,.5,2))
	occupied.name = "BerthSouth1"
	carrier = _flight(frame_id,Vector3(0,1.55,0))
	other = _flight(frame_id,Vector3(0,1.55,3.5))
	cargo = _cargo(Vector3(0,.46,0)+cargo_offset)
	second = _cargo(Vector3(3,.46,0))
	for i in 75: await physics_frame
	custody = Custody.new()
	if not is_instance_valid(custody):
		_check(false,"custody instance exists before configure")
		return false
	var remote: StaticBody3D = _box(Vector3(7,0,0),Vector3(2,.5,2))
	var too_low: StaticBody3D = _box(Vector3(0,-1.5,0),Vector3(2,.5,2))
	var configured: Dictionary = custody.configure({"cold":cargo,"hot":second},{"south0":berth,"south1":occupied,"remote":remote,"too_low":too_low},{"pilot_a":carrier,"pilot_b":other},authority)
	_check(configured.ok,frame_id+": configure actual 2 kg bodies, two berths, two real FlightBodies",configured)
	if not configured.ok: return false
	_check(cargo.get_colliding_bodies().has(berth) and second.get_colliding_bodies().has(occupied),frame_id+": gravity establishes actual support before registry requests")
	return true

func _seat_both() -> void:
	_check(custody.seat("cold","south0",1,custody.revision).ok,"initial seating reserves actual cold berth")
	_check(custody.seat("hot","south1",2,custody.revision).ok,"initial seating reserves distinct occupied berth")
	_check(custody.report().cargos.cold.phase == "settling","initial placement never instantly declares delivery")
	custody.step(DT)
	var observed_once: Dictionary = custody.report()
	_check(not custody.step(DT).ok and custody.report() == observed_once,"repeating same physical sample cannot fabricate continuous support time")
	for i in 24:
		await physics_frame
		custody.step(DT)
	_check(custody.report().cargos.cold.phase == "docked" and custody.report().cargos.hot.phase == "docked","both actual contacts remain stable for required interval",custody.report())

func _happy_path(frame_id: String) -> void:
	if not await _setup(frame_id): return
	await _seat_both()
	var initial: Dictionary = custody.report()
	var bad: Dictionary = custody.pickup("cold","pilot_a",3,custody.revision-1)
	_check(not bad.ok and bad.code == "stale_revision" and custody.report() == initial,frame_id+": stale expected revision rejects atomically")
	bad = custody.pickup("cold","pilot_b",3,custody.revision)
	_check(not bad.ok and bad.code == "grip_too_far" and custody.report() == initial and other.cargo_items.is_empty(),frame_id+": far player cannot pull load onto hook",bad)
	var proof: Dictionary = custody.support_info("cold","south0")
	_check(proof.supported and proof.support_rid == berth.get_rid() and proof.cargo_rid == cargo.get_rid() and proof.five_rays_on_support,frame_id+": departure gets actual support RID/envelope/contact, not a centre-only location")
	var pose_before: Transform3D = cargo.global_transform
	var speed_before: Vector3 = cargo.linear_velocity
	var picked: Dictionary = custody.pickup("cold","pilot_a",3,custody.revision)
	_check(picked.ok and carrier.cargo_joint is PinJoint3D and carrier.cargo_items.size() == 1 and is_equal_approx(carrier.cargo_kg,2.0),frame_id+": near slow pickup creates one actual joint",picked)
	if not picked.ok: return
	_check(cargo.global_transform == pose_before and cargo.linear_velocity == speed_before,frame_id+": pickup performs no pose/velocity snap")
	_check(cargo.collision_mask == Custody.MASK and cargo.collision_layer == 8,frame_id+": wrapper preserves collision with other bodies despite legacy attach mask narrowing")
	var after_pick: Dictionary = custody.report()
	bad = custody.pickup("cold","pilot_b",4,custody.revision)
	_check(not bad.ok and other.cargo_items.is_empty() and carrier.cargo_items.size() == 1 and custody.report() == after_pick,frame_id+": second player's same-cargo request cannot create a second holder",bad)
	bad = custody.pickup("cold","pilot_a",3,custody.revision)
	_check(not bad.ok and bad.code == "stale_serial" and custody.report() == after_pick,frame_id+": replay cannot recreate joint")
	bad = custody.release_to("cold","south1",4,custody.revision)
	_check(not bad.ok and bad.code == "berth_occupied" and custody.report() == after_pick and is_instance_valid(carrier.cargo_joint),frame_id+": already occupied berth rejects before detachment")
	bad = custody.release_to("cold","remote",4,custody.revision)
	_check(not bad.ok and bad.code == "drop_pose_mismatch" and custody.report() == after_pick,frame_id+": remote berth cannot absorb load")
	_check(bad.diagnostic.pose_rejections.has("footprint") and not bad.diagnostic.footprint_inside,frame_id+": rejected remote drop reports real footprint mismatch",bad)
	bad = custody.release_to("cold","too_low",4,custody.revision)
	_check(not bad.ok and bad.code == "drop_pose_mismatch" and custody.report() == after_pick,frame_id+": excessive release height rejects without detachment")
	_check(bad.diagnostic.pose_rejections.has("above_release_height") and bad.diagnostic.bottom_gap_m>.35,frame_id+": rejected high drop reports true gap without relaxing limit",bad)
	# Fixture only: unobstructed vertical .20 m rise using actual Flight controls.
	# This is not the general dock departure executor or a production berth route.
	carrier.freeze = false
	var settled: bool = false
	var lift_trace: Array = []
	for i in 480:
		await physics_frame
		var vertical: float = clampf((1.75-carrier.global_position.y)*1.2,-.25,.25)
		carrier.hold_height = 1.75
		carrier.command = {"active":true,"mode":"assisted","planar":Vector3.ZERO,"vertical":vertical/float(carrier.stats.rise_mps),"brake":false}
		custody.step(DT)
		if i%60 == 0: lift_trace.append({"body":str(carrier.global_position),"load":str(cargo.global_position),"load_speed":cargo.linear_velocity.length()})
		if absf(carrier.global_position.y-1.75)<.05 and carrier.linear_velocity.length()<.10 and cargo.linear_velocity.length()<.08 and cargo.angular_velocity.length()<.1:
			settled = true
			break
	_check(settled,frame_id+": actual force-controlled rise settles above support",{"trace":lift_trace})
	var gap: float = cargo.global_position.y-.2-.25
	_check(gap>.10 and gap<.35,frame_id+": real load has a bounded nonzero fall to berth",{"gap_m":gap})
	# A new actual object under the cargo blocks the full drop shape, including
	# player/prop collision layers, while the berth itself stays physically present.
	var blocker: StaticBody3D = _box(Vector3(0,.32,0),Vector3(.35,.08,.35))
	blocker.collision_layer = 2
	for i in 2: await physics_frame
	var before_obstacle: Dictionary = custody.report()
	bad = custody.release_to("cold","south0",4,custody.revision)
	_check(not bad.ok and bad.code == "drop_obstructed" and custody.report() == before_obstacle and is_instance_valid(carrier.cargo_joint),frame_id+": actual drop obstruction prevents physical release",bad)
	blocker.queue_free()
	for i in 2: await physics_frame
	var loose: RigidBody3D = _loose_obstruction(Vector3(0,.32,0))
	for i in 2: await physics_frame
	before_obstacle = custody.report()
	bad = custody.release_to("cold","south0",4,custody.revision)
	_check(not bad.ok and bad.code == "drop_obstructed" and custody.report() == before_obstacle and is_instance_valid(carrier.cargo_joint),frame_id+": a different real layer-8 RigidBody also blocks drop",bad)
	loose.queue_free()
	for i in 2: await physics_frame
	pose_before = cargo.global_transform
	speed_before = cargo.linear_velocity
	var joint_ref: WeakRef = weakref(carrier.cargo_joint)
	var released: Dictionary = custody.release_to("cold","south0",4,custody.revision)
	_check(released.ok and joint_ref.get_ref() == null and carrier.cargo_items.is_empty() and carrier.cargo_kg == 0.0,frame_id+": release removes true joint and carried mass synchronously",released)
	if not released.ok:
		observations[frame_id] = {"release_failed":released,"gap":gap,"lift":lift_trace,"state":custody.report()}
		return
	_check(cargo.global_transform == pose_before and cargo.linear_velocity == speed_before and custody.report().cargos.cold.phase == "dropping",frame_id+": release retains actual pose/velocity and is not delivery")
	_check(cargo.collision_mask == Custody.MASK and cargo.collision_layer == 8,frame_id+": released cargo retains actual other-player/load collisions")
	_check(custody.report().cargos.cold.carrier == "" and custody.report().cargos.cold.berth == "south0",frame_id+": in-flight drop has one reserved destination, no second owner")
	var after_release: Dictionary = custody.report()
	bad = custody.release_to("cold","south0",4,custody.revision)
	_check(not bad.ok and custody.report() == after_release,frame_id+": repeated release cannot duplicate drop")
	var fell: bool = false
	var docked: bool = false
	var dock_events: int = 0
	for i in 180:
		await physics_frame
		carrier.command = {"active":true,"mode":"assisted","planar":Vector3.ZERO,"brake":true}
		var row: Dictionary = custody.step(DT)
		if cargo.global_position.y < pose_before.origin.y-.05: fell = true
		for event: Dictionary in row.get("changes",[]):
			if event.cargo_id == "cold" and event.phase == "docked": dock_events += 1
		if custody.report().cargos.cold.phase == "docked":
			docked = true
			break
	_check(fell and docked and dock_events == 1 and cargo.get_colliding_bodies().has(berth),frame_id+": gravity fall and continuous support produce one dock completion",custody.report())
	for i in 15:
		await physics_frame
		var row: Dictionary = custody.step(DT)
		for event: Dictionary in row.get("changes",[]):
			if event.cargo_id == "cold" and event.phase == "docked": dock_events += 1
	_check(dock_events == 1,frame_id+": stable polling does not replay completion")
	var exported: Dictionary = custody.report()
	exported.cargos.cold.phase = "forged"
	_check(custody.report().cargos.cold.phase == "docked" and JSON.parse_string(JSON.stringify(custody.report())) is Dictionary,frame_id+": JSON-safe report is an isolated logical copy, not a physics restore")
	observations[frame_id] = {"lift_trace":lift_trace,"drop_gap_m":gap,"after_drop":custody.report(),"position":str(cargo.global_position),"speed":cargo.linear_velocity.length(),"events":dock_events}

func _offset_pickup_alignment() -> void:
	# The cassette is initially off the berth's nominal centre, but genuinely
	# supported. From this point it is never repositioned or straightened by QA.
	if not await _setup("tr01",true,Vector3(.13,0,-.045)): return
	await _seat_both()
	var cargo_start: Transform3D = cargo.global_transform
	var carrier_start: Vector3 = carrier.global_position
	var original_offset: Vector3 = cargo.global_position-(carrier.global_position+Custody.LOAD_OFFSET)
	_check(original_offset.length()>.10 and original_offset.length()<.18 and custody.support_info("cold","south0").supported,"offset cassette is already legally supported and within old pickup allowance",{"offset":str(original_offset)})
	var pilot := Pilot.new()
	_check(pilot.bind(carrier),"precise pickup uses ordinary true-flight controller")
	var before_serial: int = pilot.serial
	var before_command: Dictionary = carrier.command.duplicate(true)
	_check(not pilot.go_to_pickup_alignment(second,1) and pilot.serial==before_serial and carrier.command==before_command,"pickup mode cannot substitute a remote route or mutate serial on rejection")
	carrier.freeze = false
	if not _check_bool(pilot.go_to_pickup_alignment(cargo,1),"near offset target starts bounded actual alignment"): return
	var aligned: bool = false
	var trace: Array = []
	for i in 600:
		await physics_frame
		custody.step(DT)
		var row: Dictionary = pilot.tick(DT)
		if i%60==0: trace.append({"body":str(carrier.global_position),"cargo":str(cargo.global_position),"report":row})
		if row.arrived:
			aligned = true
			break
	var actual_offset: Vector3 = cargo.global_position-(carrier.global_position+Custody.LOAD_OFFSET)
	_check(aligned and actual_offset.length()<=.025 and carrier.linear_velocity.length()<.04,"true alignment reaches current cassette centre within 25 mm",{"offset":str(actual_offset),"trace":trace})
	_check(carrier.global_position.distance_to(carrier_start)>.08 and cargo.global_position.distance_to(cargo_start.origin)<.005 and cargo.get_colliding_bodies().has(berth),"carrier flew to offset load; cargo stayed physically on original support")
	if not aligned: return
	var picked: Dictionary = custody.pickup("cold","pilot_a",3,custody.revision)
	_check(picked.ok and carrier.cargo_joint is PinJoint3D,"centred actual pose attaches real PinJoint",picked)
	if not picked.ok: return
	var grip: Dictionary = custody.grip_info("cold")
	var hook_local: Array = grip.cargo_local
	_check(Vector2(float(hook_local[0]),float(hook_local[2])).length()<=.03 and float(hook_local[1])>.4 and float(hook_local[1])<.5,"recorded actual cargo-local joint anchor is central instead of inherited berth offset",grip)
	var route_serial: int = pilot.serial
	_check(not pilot.go_to_pickup_alignment(cargo,route_serial+1) and pilot.serial==route_serial,"precise empty-hook mode cannot be used on an already held cargo")
	var dock := Dock.new()
	var begun: Dictionary = dock.begin(carrier,berth,1,true)
	if not _check_bool(begun.ok,"aligned pickup has real support for ordinary dock departure",begun): return
	var departed: bool = false
	for i in 720:
		await physics_frame
		custody.step(DT)
		var row: Dictionary = dock.tick(DT,true,false)
		if row.clear:
			departed = true
			break
	if not _check_bool(departed,"offset fixture really rises off unchanged support",dock.report()): return
	# Low/normal mode default is preserved when the local alignment job ends.
	_check(pilot.go_to(carrier.global_position,route_serial+1) and pilot.report().position_tolerance_m==.18,"ordinary route retains original 18 cm tolerance after pickup mode")
	var approach: Dictionary = dock.begin_approach(carrier,berth,2,true)
	if not _check_bool(approach.ok,"same physical load begins unchanged bounded approach",approach): return
	var ready: bool = false
	for i in 720:
		await physics_frame
		custody.step(DT)
		var row: Dictionary = dock.tick(DT,true,false)
		if row.ready_for_release:
			ready = true
			break
	if not _check_bool(ready,"actual load returns to finite release-height band",dock.report()): return
	var proof: Dictionary = {}
	for i in 240:
		await physics_frame
		custody.step(DT)
		carrier.command = {"active":true,"mode":"assisted","body_relative":false,"planar":Vector3.ZERO,"vertical":0.0,"brake":true}
		proof = custody.release_info("cold","south0")
		if proof.ok: break
	var before: Dictionary = custody.report()
	var pose: Transform3D = cargo.global_transform
	var velocity: Vector3 = cargo.linear_velocity
	var repeated: Dictionary = custody.release_info("cold","south0")
	_check(repeated==proof and custody.report()==before and cargo.global_transform==pose and cargo.linear_velocity==velocity,"release diagnostics are read-only even when repeated in one physics frame")
	_check(proof.ok and proof.diagnostic.up_dot>=.985 and proof.diagnostic.bottom_gap_m>.1 and proof.diagnostic.bottom_gap_m<=.35 and proof.diagnostic.footprint_inside,"centred pickup passes unchanged real tilt, footprint and drop-height gates",proof)
	if not proof.ok: return
	var old_joint: WeakRef = weakref(carrier.cargo_joint)
	var released: Dictionary = custody.release_to("cold","south0",4,custody.revision)
	if not _check_bool(released.ok and old_joint.get_ref()==null,"centred fixture really releases, preserving all custody checks",released): return
	var landed: bool = false
	for i in 300:
		await physics_frame
		custody.step(DT)
		if custody.report().cargos.cold.phase=="docked":
			landed = true
			break
	_check(landed and pose.origin.y-cargo.global_position.y>.1 and cargo.get_colliding_bodies().has(berth) and custody.report().cargos.cold.completed_serial==4,"offset load really falls and rests on support before completion")
	observations.offset_alignment = {"initial_offset":str(original_offset),"grip":grip,"release":proof,"final":custody.report(),"trace":trace}

func _check_bool(value: bool,label: String,details: Dictionary = {}) -> bool:
	_check(value,label,details)
	return value

func _interruptions() -> void:
	if not await _setup(): return
	await _seat_both()
	_check(custody.pickup("cold","pilot_a",3,custody.revision).ok,"interruption fixture attaches by validated pickup")
	_check(custody.release_to("cold","south0",4,custody.revision).ok,"interruption fixture really releases over support")
	for i in 8:
		await physics_frame
		custody.step(DT)
	_check(int(custody.report().cargos.cold.stable_usec)>0 and custody.report().cargos.cold.phase == "dropping","partial stable interval is not completion")
	cargo.apply_central_impulse(Vector3(.8,0,0))
	for i in 3: await physics_frame
	custody.step(DT)
	_check(custody.report().cargos.cold.stable_usec == 0 and custody.report().cargos.cold.phase == "dropping","real disturbance clears continuous support timer without freeing reservation",custody.report())
	var blocked: Dictionary = custody.pickup("cold","pilot_b",5,custody.revision)
	_check(not blocked.ok and other.cargo_items.is_empty(),"interrupted release remains exclusive, cannot be picked by second player")
	berth.queue_free()
	await physics_frame
	custody.step(DT)
	_check(custody.report().cargos.cold.phase == "fault" and custody.report().cargos.cold.berth == "south0" and custody.report().cargos.cold.fault == "berth_lost_or_changed","deleted destination yields explicit fault with reservation retained",custody.report())
	_check(is_instance_valid(cargo) and carrier.cargo_items.is_empty(),"fault does not delete or reattach physical load")

func _authority_and_faults() -> void:
	if not await _setup("tr01",false): return
	var initial: Dictionary = custody.report()
	_check(not custody.seat("cold","south0",1,custody.revision).ok and not custody.step(DT).ok and custody.report() == initial,"client observer cannot claim or advance custody")
	if not await _setup(): return
	await _seat_both()
	initial = custody.report()
	_check(not custody.step(NAN).ok and not custody.step(.11).ok and not custody.step(-.01).ok and custody.report() == initial,"invalid deltas reject atomically")
	_check(custody.step(0).ok and custody.step(DT,true,true).ok and custody.report() == initial,"zero delta and suspended step do not accrue time")
	_check(custody.set_paused(true).ok,"authority explicitly pauses requests")
	initial = custody.report()
	_check(not custody.pickup("cold","pilot_a",3,custody.revision).ok and custody.step(DT).ok and custody.report() == initial,"pause forbids physical attachment and queued progress")
	custody.set_paused(false)
	# Actual impulse, not injected velocity; request cannot claim a moving load.
	cargo.apply_central_impulse(Vector3(0,.8,0))
	await physics_frame
	initial = custody.report()
	var fast: Dictionary = custody.pickup("cold","pilot_a",3,custody.revision)
	_check(not fast.ok and carrier.cargo_items.is_empty() and custody.report() == initial,"moving load rejects pickup without removing berth record",fast)
	for i in 90:
		await physics_frame
		custody.step(DT)
	_check(custody.report().cargos.cold.phase == "docked","actual disturbed load can settle again without teleport")
	_check(custody.pickup("cold","pilot_a",3,custody.revision).ok,"recovered contact permits a new physical pickup")
	carrier.enabled = false
	await physics_frame
	custody.step(DT)
	_check(custody.report().cargos.cold.phase == "fault" and custody.report().cargos.cold.carrier == "pilot_a" and carrier.cargo_items.size() == 1 and is_instance_valid(carrier.cargo_joint),"disabled carrier preserves its real joint/custody for explicit recovery, no second claim",custody.report())
	if not await _setup(): return
	await _seat_both()
	_check(custody.pickup("cold","pilot_a",3,custody.revision).ok,"lost-load fixture starts with actual joint")
	cargo.queue_free()
	await physics_frame
	custody.step(DT)
	_check(custody.report().cargos.cold.phase == "fault" and custody.report().cargos.cold.fault == "cargo_lost" and custody.report().cargos.cold.carrier == "pilot_a","invalid cargo cannot silently clear ownership or produce delivery",custody.report())

func _flight(frame_id: String,at: Vector3) -> Flight:
	var body := Flight.new()
	body.configure(Catalog.resolve_build(Catalog.default_build(frame_id)))
	body.position = at # fixture initial placement only
	body.freeze = true
	body.hold_height = at.y
	body.command = {"active":true,"mode":"assisted","brake":true}
	world.add_child(body)
	return body

func _cargo(at: Vector3) -> RigidBody3D:
	var body := RigidBody3D.new()
	body.mass = 2.0
	body.position = at # fixture initial placement only
	body.can_sleep = false
	body.continuous_cd = true
	body.contact_monitor = true
	body.max_contacts_reported = 16
	body.collision_layer = 8
	body.collision_mask = Custody.MASK
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

func _box(at: Vector3,size: Vector3) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.position = at
	body.collision_layer = 1
	body.collision_mask = 0
	var collider := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	collider.shape = shape
	body.add_child(collider)
	world.add_child(body)
	return body

func _loose_obstruction(at: Vector3) -> RigidBody3D:
	var body := RigidBody3D.new()
	body.mass = .5
	body.position = at # separate obstruction fixture, never a registered cassette
	body.collision_layer = 8
	body.collision_mask = Custody.MASK
	var collider := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(.35,.08,.35)
	collider.shape = shape
	body.add_child(collider)
	world.add_child(body)
	return body

func _cleanup() -> void:
	if is_instance_valid(world):
		world.queue_free()
		await process_frame
		await physics_frame
	custody = null

func _check(value: bool,label: String,details: Dictionary = {}) -> void:
	checks += 1
	if not value: failures.append({"check":label,"details":details})
