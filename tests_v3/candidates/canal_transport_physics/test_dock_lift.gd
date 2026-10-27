extends SceneTree
## Actual support contact -> real joint -> controlled lift -> normal flight.
## Does not validate grasp requests, custody, production berths or networking.
const Flight = preload("res://scripts/v2/flight_body.gd")
const Catalog = preload("res://scripts/v2/catalog.gd")
const Lift = preload("res://scripts/v3/candidates/canal_transport_physics/dock_lift.gd")
const Pilot = preload("res://scripts/v3/candidates/canal_transport_physics/transport_pilot.gd")
var viewport: SubViewport
var world: Node3D
var body: Flight
var cargo: RigidBody3D
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
	create_timer(60).timeout.connect(func():
		if not finished:
			print("DOCK_LIFT_TIMEOUT "+JSON.stringify(observations))
			quit(2))
	viewport=SubViewport.new()
	viewport.size=Vector2i(32,32)
	viewport.own_world_3d=true
	viewport.world_3d=World3D.new()
	viewport.render_target_update_mode=SubViewport.UPDATE_DISABLED
	root.add_child(viewport)
	world=Node3D.new()
	viewport.add_child(world)
	_box(Vector3(0,-.5,0),Vector3(20,1,20),1)
	var berth := _box(Vector3(0,0,0),Vector3(2,.5,2),1)
	body=Flight.new()
	body.configure(Catalog.resolve_build(Catalog.default_build("tr01")))
	body.position=Vector3(0,1.55,0)
	body.hold_height=1.55
	body.freeze=true
	body.command={"active":true,"mode":"assisted","brake":true}
	world.add_child(body)
	cargo=RigidBody3D.new()
	cargo.mass=2.0
	cargo.position=Vector3(0,.46,0)
	cargo.can_sleep=false
	cargo.continuous_cd=true
	cargo.contact_monitor=true
	cargo.max_contacts_reported=16
	cargo.collision_layer=8
	cargo.collision_mask=1|2|4|8|32
	var collider := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size=Vector3(.4,.4,.4)
	collider.shape=shape
	cargo.add_child(collider)
	world.add_child(cargo)
	for i in 90: await physics_frame
	_check(cargo.get_colliding_bodies().has(berth) and cargo.linear_velocity.length()<.02,"load settles by gravity on real berth support")
	_check(body.attach_cargo(cargo,"lift_cassette",2.0),"existing FlightBody creates actual cargo joint")
	cargo.collision_mask=1|2|4|8|32
	body.add_collision_exception_with(cargo)
	cargo.add_collision_exception_with(body)
	var joint: PinJoint3D=body.cargo_joint
	var ordinary=Pilot.new()
	ordinary.bind(body)
	_check(not ordinary.probe(Vector3.UP*.3).clear,"ordinary conservative envelope really blocks initial support contact")
	var lift=Lift.new()
	var command_before: Dictionary=body.command.duplicate(true)
	_check(not lift.begin(body,berth,1,false).ok and lift.state=="idle","non-host cannot start departure")
	berth.constant_linear_velocity=Vector3(.1,0,0)
	_check(not lift.begin(body,berth,1).ok,"conveyor-like support cannot use flat stationary exemption")
	berth.constant_linear_velocity=Vector3.ZERO
	var extra := CollisionShape3D.new()
	extra.shape=BoxShape3D.new()
	extra.position=Vector3(0,4,0)
	berth.add_child(extra)
	_check(not lift.begin(body,berth,1).ok,"support RID containing another obstacle cannot be excluded")
	berth.remove_child(extra)
	extra.free()
	_check(lift.begin(body,berth,1).ok,"verified single horizontal support starts bounded lift")
	_check(not lift.begin(body,berth,1).ok and lift.serial==1,"replay cannot restart departure")
	_check(not lift.tick(1.0/60.0,false).ok and body.command==command_before,"non-host tick cannot change command")
	_check(not lift.tick(NAN).ok and body.command==command_before,"invalid delta cannot change command")
	var blocker := _box(Vector3(0,2.3,0),Vector3(4,.2,4),2)
	for i in 3: await physics_frame
	body.freeze=false
	var max_y := body.global_position.y
	var blocked := 0
	for i in 90:
		await physics_frame
		var response: Dictionary=lift.tick(1.0/60.0)
		if response.state=="blocked": blocked+=1
		max_y=maxf(max_y,body.global_position.y)
	observations.blocked={"frames":blocked,"max_y":max_y,"reason":lift.reason,"cargo":str(cargo.global_position)}
	_check(blocked>60 and max_y<1.7,"real overhead obstacle blocks lifting without disabling any collider")
	_check(not lift.report().clear,"blocked departure never reports clear")
	blocker.queue_free()
	await physics_frame
	var cleared := false
	var steps := 0
	var samples: Array=[]
	for i in 720:
		await physics_frame
		var response: Dictionary=lift.tick(1.0/60.0)
		steps+=1
		if i%60==0: samples.append({"body":str(body.global_position),"cargo":str(cargo.global_position),"state":response.state,"reason":response.code,"speed":body.linear_velocity.length()})
		if response.clear:
			cleared=true
			break
	observations.lift={"steps":steps,"samples":samples,"body":str(body.global_position),"cargo":str(cargo.global_position),"report":lift.report()}
	_check(cleared,"removing overhead blocker resumes and physically completes departure")
	_check(body.global_position.distance_to(Vector3(0,2.2,0))<.12 and cargo.global_position.y-.2>.7,"actual body and load rise above original support")
	_check(ordinary.probe(Vector3.ZERO).clear,"ordinary full-envelope flight becomes clear with support included again")
	_check(body.cargo_joint==joint and body.cargo_items.size()==1 and is_equal_approx(body.cargo_kg,2.0),"departure preserves original joint and one real 2kg load")
	var arrived := false
	if cleared:
		ordinary.go_to(Vector3(0,2.2,-4),1)
		for i in 600:
			await physics_frame
			var response: Dictionary=ordinary.tick(1.0/60.0)
			if response.arrived:
				arrived=true
				break
	observations.normal={"arrived":arrived,"body":str(body.global_position),"cargo":str(cargo.global_position),"report":ordinary.report()}
	_check(arrived,"normal pilot continues 4m actual loaded flight after departure")
	var returned := false
	if arrived:
		ordinary.go_to(Vector3(0,2.2,0),2)
		for i in 600:
			await physics_frame
			if ordinary.tick(1.0/60.0).arrived:
				returned=true
				break
	_check(returned,"same loaded body returns physically over the original berth")
	var settle_steps := 0
	for i in 180:
		await physics_frame
		ordinary.tick(1.0/60.0)
		settle_steps+=1
		if body.linear_velocity.length()<.1 and cargo.linear_velocity.length()<.1: break
	var approach_start: Dictionary=lift.begin_approach(body,berth,2)
	observations.approach_start={"response":approach_start,"settle_steps":settle_steps,"body_speed":body.linear_velocity.length(),"cargo_speed":cargo.linear_velocity.length(),"body":str(body.global_position),"cargo":str(cargo.global_position)}
	_check(approach_start.ok,"settled load above real flat support starts controlled approach")
	var ready := false
	for i in 600:
		if not approach_start.ok: break
		await physics_frame
		if lift.tick(1.0/60.0).ready_for_release:
			ready=true
			break
	var bounds: Dictionary=Lift._bounds(cargo)
	var actual_gap: float=bounds.bounds.position.y-.25
	observations.approach={"ready":ready,"gap_m":actual_gap,"body":str(body.global_position),"cargo":str(cargo.global_position),"report":lift.report()}
	_check(ready and actual_gap>.2 and actual_gap<.3,"bounded approach reaches an actual 20-30cm release gap")
	_check(body.cargo_joint==joint and body.cargo_items.size()==1,"approach itself does not detach or transfer custody")
	if ready:
		var before_y := cargo.global_position.y
		body.release_cargo("lift_cassette")
		var grounded := 0
		for i in 180:
			await physics_frame
			if cargo.get_colliding_bodies().has(berth) and cargo.linear_velocity.length()<.02: grounded+=1
		observations.drop={"actual_fall_m":before_y-cargo.global_position.y,"grounded_frames":grounded,"cargo":str(cargo.global_position)}
		_check(not is_instance_valid(joint) and grounded>21 and before_y-cargo.global_position.y>.2,"actual release falls by gravity and settles on real support")
	_check(body.health==body.maximum_health and body.collision_count==0,"support departure and normal flight cause no hull damage")
	_check(logger.errors.is_empty(),"no engine errors")
	finished=true
	world.queue_free()
	await process_frame
	viewport.queue_free()
	await process_frame
	print("V3_DOCK_LIFT_RESULT "+JSON.stringify({"checks":checks,"failures":failures,"observations":observations,"engine_errors":logger.errors,"scope":"real isolated support departure only; no custody, production berth, save, network or human test"}))
	quit(0 if failures.is_empty() else 1)

func _box(at: Vector3,size: Vector3,layer: int) -> StaticBody3D:
	var box := StaticBody3D.new()
	box.position=at
	box.collision_layer=layer
	box.collision_mask=0
	var collider := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size=size
	collider.shape=shape
	box.add_child(collider)
	world.add_child(box)
	return box

func _check(value: bool,label: String) -> void:
	checks+=1
	if not value: failures.append(label)
