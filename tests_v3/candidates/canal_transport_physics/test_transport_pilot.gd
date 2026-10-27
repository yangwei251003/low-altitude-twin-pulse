extends SceneTree
## Isolated real Jolt flight / load / blocking fixture, not a completed I2 route.
const Flight = preload("res://scripts/v2/flight_body.gd")
const Catalog = preload("res://scripts/v2/catalog.gd")
const Pilot = preload("res://scripts/v3/candidates/canal_transport_physics/transport_pilot.gd")
var viewport: SubViewport
var world: Node3D
var body: Flight
var cargo: RigidBody3D
var pilot: RefCounted
var checks := 0
var failures: Array = []
var observations: Dictionary = {}
var finished := false
class ErrorLogger extends Logger:
	var errors: Array = []
	func _log_error(function: String, file: String, line: int, code: String, rationale: String, _notify: bool, error_type: int, _backtraces: Array[ScriptBacktrace]) -> void:
		errors.append({"function":function,"file":file,"line":line,"code":code,"rationale":rationale,"type":error_type})
var logger := ErrorLogger.new()

func _init() -> void:
	OS.add_logger(logger)
	_run.call_deferred()

func _run() -> void:
	create_timer(75).timeout.connect(func():
		if not finished:
			print("TRANSPORT_TIMEOUT " + JSON.stringify(observations))
			quit(2))
	viewport = SubViewport.new()
	viewport.size = Vector2i(32,32)
	viewport.own_world_3d = true
	viewport.world_3d = World3D.new()
	viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	root.add_child(viewport)
	world = Node3D.new()
	viewport.add_child(world)
	_box(Vector3(0,-.5,-4),Vector3(20,1,24),1)
	_box(Vector3(-2.4,2,-6),Vector3(.5,4,18),1)
	_box(Vector3(2.4,2,-6),Vector3(.5,4,18),1)
	_box(Vector3(0,5,-6),Vector3(4.3,.4,18),1)
	body = Flight.new()
	body.configure(Catalog.resolve_build(Catalog.default_build("tr01")))
	body.freeze = true
	body.position = Vector3(0,3,0)
	body.hold_height = 3.0
	world.add_child(body)
	body.collision_layer = 8
	body.collision_mask = 1|2|4|8|32
	body.command = {"active":true,"mode":"assisted","brake":true}
	cargo = RigidBody3D.new()
	cargo.mass = 2.0
	cargo.freeze = true
	cargo.position = Vector3(0,1.9,0)
	cargo.continuous_cd = true
	cargo.can_sleep = false
	cargo.contact_monitor = true
	cargo.max_contacts_reported = 12
	var collider := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(.4,.4,.4)
	collider.shape = shape
	cargo.add_child(collider)
	world.add_child(cargo)
	for i in 3: await physics_frame
	_check(body.attach_cargo(cargo,"cassette_test",2.0),"real 2kg body attached through existing PinJoint")
	cargo.collision_mask = 1|2|4|8|32
	body.add_collision_exception_with(cargo)
	cargo.add_collision_exception_with(body)
	_check(body.cargo_joint is PinJoint3D and is_equal_approx(body.cargo_kg,2.0),"one actual joint and carried mass")
	pilot = Pilot.new()
	_check(pilot.bind(body),"bind to actual flight body")
	_check(not pilot.go_to(Vector3(NAN,3,0),1) and pilot.serial == 0,"invalid waypoint rejected without advancing serial")
	_check(pilot.go_to(Vector3(0,3,-12),1) and not pilot.go_to(Vector3(0,3,-4),1),"new waypoint accepted; duplicate serial does not retarget")
	var original: Dictionary = body.command.duplicate(true)
	_check(pilot.tick(1.0/60.0,false).state == "not_authority" and body.command == original,"guest cannot drive actor")
	_check(pilot.tick(NAN).state == "invalid_delta" and body.command == original,"invalid step cannot drive actor")
	# This layer-2 obstacle misses the carrier hull but blocks its hanging load.
	var blocker := _box(Vector3(0,1.75,-6.3),Vector3(2,.5,1),2)
	body.freeze = false
	cargo.freeze = false
	var blocked_frames := 0
	var minimum_z := 0.0
	var maximum_speed := 0.0
	# Slower safe commands may approach closer than the old all-or-brake pilot.
	# Keep all original clearance/stop assertions, but observe the final stop too.
	for i in 720:
		await physics_frame
		var row: Dictionary = pilot.tick(1.0/60.0)
		if row.state == "blocked": blocked_frames += 1
		minimum_z = minf(minimum_z,body.global_position.z)
		maximum_speed = maxf(maximum_speed,body.linear_velocity.length())
		if i == 359: observations.original_six_seconds = {"minimum_z":minimum_z,"blocked_frames":blocked_frames,"report":pilot.report()}
	observations.blocked = {"body":str(body.global_position),"cargo":str(cargo.global_position),"minimum_z":minimum_z,"frames":blocked_frames,"max_speed":maximum_speed,"report":pilot.report()}
	_check(blocked_frames > 60 and minimum_z > -5.0 and minimum_z < -.5 and maximum_speed > 1.0,"accelerates then sustains braking before cargo-only player-layer blocker")
	_check(body.collision_count == 0 and body.health == body.maximum_health,"approach stops without hull collision or damage")
	_check(cargo.global_position.z > -5.5 and absf(cargo.global_position.y-body.global_position.y+1.1)<.3,"hanging physical load remains attached and before obstacle")
	_check(not pilot.report().arrived,"blocked route never reports arrival")
	blocker.queue_free()
	await physics_frame
	var arrived := false
	var resumed := false
	var travel_steps := 0
	for i in 900:
		await physics_frame
		var row: Dictionary = pilot.tick(1.0/60.0)
		travel_steps += 1
		if row.state == "traveling": resumed = true
		if row.arrived:
			arrived = true
			break
	observations.cleared = {"body":str(body.global_position),"cargo":str(cargo.global_position),"steps":travel_steps,"report":pilot.report()}
	_check(resumed and arrived,"removing blocker resumes physical flight and reaches waypoint")
	_check(body.global_position.distance_to(Vector3(0,3,-12))<.18 and body.linear_velocity.length()<.18,"arrival requires true pose and low real speed")
	_check(cargo.linear_velocity.length()<.3 and is_instance_valid(body.cargo_joint),"arrival waits for load settling with real joint retained")
	_check(body.collision_count == 0 and body.health == body.maximum_health,"unblocked traversal remains collision free")
	var before_target: Vector3 = pilot.target
	_check(pilot.tick(1.0/60.0,true,true).state == "suspended" and body.command.brake and pilot.target == before_target,"suspension brakes without deleting destination")
	if arrived: await _speed_clearance_cases()
	else: _check(false,"speed-selection physical cases require original route to succeed first")
	_check(logger.errors.is_empty(),"no captured engine errors")
	finished = true
	world.queue_free()
	await process_frame
	viewport.queue_free()
	await process_frame
	print("V3_TRANSPORT_PILOT_RESULT " + JSON.stringify({"passed":failures.is_empty(),"checks":checks,"failures":failures,"observations":observations,"engine_errors":logger.errors,"scope":"isolated real flight/load, no logistics ownership, world integration, network or human-play proof"}))
	quit(0 if failures.is_empty() else 1)

func _speed_clearance_cases() -> void:
	# The same live carrier and load return toward +Z. No relocation or clearing
	# of velocity: the wall is 1.5m beyond the waypoint, not inside its envelope.
	var wall := _box(Vector3(0,2.4,-6.4),Vector3(4,4.8,.2),1)
	wall.name = "BeyondWaypointWall"
	await physics_frame
	_check(pilot.go_to(Vector3(0,3,-8),2),"new physical waypoint leaves wall beyond destination")
	var reduced_frames := 0
	var sampled_reduction: Dictionary = {}
	var bounded := true
	var direction_preserved := true
	var actual_reject_brakes := true
	var contacts := 0
	var arrived := false
	for i in 900:
		await physics_frame
		var row: Dictionary = pilot.tick(1.0/60.0)
		var plan: Dictionary = row.speed_plan
		bounded = bounded and plan.attempts.size() <= Pilot.SPEED_SCALES.size()
		if not plan.actual_probe.clear:
			actual_reject_brakes = actual_reject_brakes and body.command.brake and not plan.commanded and plan.attempts.is_empty()
		if plan.commanded and plan.scale < 1.0:
			reduced_frames += 1
			var wanted: Vector3 = plan.requested_velocity
			var selected: Vector3 = plan.selected_velocity
			direction_preserved = direction_preserved and selected.dot(wanted) > 0 and selected.cross(wanted).length() < .00001
			direction_preserved = direction_preserved and selected.length() < wanted.length() and plan.probe.clear and plan.actual_probe.clear
			if sampled_reduction.is_empty(): sampled_reduction = row.duplicate(true)
		for other: Node3D in cargo.get_colliding_bodies():
			if other != body: contacts += 1
		if row.arrived:
			arrived = true
			break
	observations.beyond_waypoint = {"arrived":arrived,"reduced_frames":reduced_frames,"first_reduction":sampled_reduction,"final":pilot.report(),"body":str(body.global_position),"cargo":str(cargo.global_position),"cargo_contacts":contacts}
	_check(reduced_frames > 0 and direction_preserved,"desired sweep blocked beyond target causes positive lower speed in exactly the original direction")
	_check(bounded and actual_reject_brakes,"bounded candidate search never replaces an unsafe actual-inertia sweep")
	_check(arrived and body.global_position.distance_to(Vector3(0,3,-8)) < .18 and body.linear_velocity.length() < .18 and cargo.linear_velocity.length() < .3,"wall beyond waypoint still allows real slow stable arrival")
	_check(contacts == 0 and body.collision_count == 0 and body.health == body.maximum_health and is_instance_valid(body.cargo_joint),"adaptive approach preserves full loaded clearance and actual joint without damage")
	# Retarget into the unchanged wall. A smaller intention cannot make the
	# occupied waypoint valid or shorten the current body's stopping envelope.
	_check(pilot.go_to(Vector3(0,3,-6.4),3),"occupied destination is tested as a real attempted route")
	var blocked_frames := 0
	var unsafe_actual_frames := 0
	var false_arrival := false
	var maximum_z := body.global_position.z
	contacts = 0
	for i in 600:
		await physics_frame
		var row: Dictionary = pilot.tick(1.0/60.0)
		if row.state == "blocked": blocked_frames += 1
		false_arrival = false_arrival or row.arrived
		maximum_z = maxf(maximum_z,body.global_position.z)
		var plan: Dictionary = row.speed_plan
		if not plan.actual_probe.clear:
			unsafe_actual_frames += 1
			actual_reject_brakes = actual_reject_brakes and body.command.brake and not plan.commanded and plan.attempts.is_empty()
		for other: Node3D in cargo.get_colliding_bodies():
			if other != body: contacts += 1
	observations.inside_waypoint = {"blocked_frames":blocked_frames,"unsafe_actual_frames":unsafe_actual_frames,"maximum_z":maximum_z,"body":str(body.global_position),"cargo":str(cargo.global_position),"cargo_contacts":contacts,"report":pilot.report()}
	_check(blocked_frames > 60 and not false_arrival and body.global_position.distance_to(pilot.target) > .18,"wall containing waypoint remains blocked and never reports arrival")
	_check(actual_reject_brakes and maximum_z < -7.2 and contacts == 0 and body.collision_count == 0 and body.health == body.maximum_health,"target obstruction stops physical hull and cargo without bypassing actual braking")

func _box(at: Vector3,size: Vector3,layer: int) -> StaticBody3D:
	var box := StaticBody3D.new()
	box.position = at
	box.collision_layer = layer
	box.collision_mask = 0
	var collider := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	collider.shape = shape
	box.add_child(collider)
	world.add_child(box)
	return box

func _check(value: bool,label: String) -> void:
	checks += 1
	if not value: failures.append(label)
