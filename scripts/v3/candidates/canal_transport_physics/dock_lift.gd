extends RefCounted
## Host-only departure from one verified flat box support. No custody changes,
## pose writes or collision exceptions. Other obstacles remain in every query.
const Flight = preload("res://scripts/v2/flight_body.gd")
const Pilot = preload("res://scripts/v3/candidates/canal_transport_physics/transport_pilot.gd")
const MASK := 1 | 2 | 4 | 8 | 32
var body: Flight
var cargo: RigidBody3D
var support: StaticBody3D
var joint: PinJoint3D
var support_box := AABB()
var target := Vector3.ZERO
var serial := 0
var state := "idle"
var reason := ""
var stable_seconds := 0.0
var ordinary: RefCounted
var mode := "departure"

func begin(carrier: Flight, berth: StaticBody3D, action_serial: int, authority: bool = true) -> Dictionary:
	return _begin(carrier,berth,action_serial,authority,false)

func begin_approach(carrier: Flight, berth: StaticBody3D, action_serial: int, authority: bool = true) -> Dictionary:
	return _begin(carrier,berth,action_serial,authority,true)

func _begin(carrier: Flight, berth: StaticBody3D, action_serial: int, authority: bool, approach: bool) -> Dictionary:
	if not authority: return _result(false,"not_authority")
	if state not in ["idle","clear","ready"] or action_serial <= serial: return _result(false,"busy_or_replay")
	if not is_instance_valid(carrier) or not carrier.is_inside_tree() or not carrier.enabled or carrier.cargo_items.size()!=1: return _result(false,"one_live_load_required")
	if carrier.linear_velocity.length()>.2: return _result(false,"carrier_not_settled")
	var item: Dictionary = carrier.cargo_items.values()[0]
	if not is_instance_valid(item.body) or not is_instance_valid(item.joint) or not item.joint is PinJoint3D: return _result(false,"actual_joint_required")
	var load: RigidBody3D = item.body
	if not load.is_inside_tree() or load.linear_velocity.length()>.2: return _result(false,"load_not_settled")
	if not approach and (not load.contact_monitor or not load.get_colliding_bodies().has(berth)): return _result(false,"actual_support_contact_required")
	var checked := _support(berth)
	if not checked.ok: return checked
	if berth.get_world_3d().space != carrier.get_world_3d().space or load.get_world_3d().space != carrier.get_world_3d().space: return _result(false,"different_space")
	var load_bounds := _bounds(load)
	var hull_bounds := _bounds(carrier)
	if not load_bounds.ok or not hull_bounds.ok: return _result(false,"unsupported_load_envelope")
	var slab: AABB = checked.bounds
	var box: AABB = load_bounds.bounds
	var gap := box.position.y-slab.end.y
	if not _above(box,slab) or hull_bounds.bounds.position.y <= slab.end.y+.1: return _result(false,"support_not_below_load")
	if approach:
		if gap<.25 or gap>1.0: return _result(false,"approach_height_out_of_range")
	elif absf(gap)>.04: return _result(false,"actual_support_contact_required")
	body=carrier
	cargo=load
	support=berth
	joint=item.joint
	support_box=slab
	target=carrier.global_position+Vector3.UP*.65
	mode="approach" if approach else "departure"
	if approach: target.y=carrier.global_position.y-gap+.25
	serial=action_serial
	state="approaching" if approach else "lifting"
	reason=""
	stable_seconds=0.0
	ordinary=Pilot.new()
	ordinary.bind(body)
	return _result(true,"approach_started" if approach else "lift_started")

func report() -> Dictionary:
	var result := _result(state in ["lifting","clear","approaching","ready"],reason)
	result.target=target
	return result

func tick(delta: float, authority: bool = true, suspended: bool = false) -> Dictionary:
	if not authority: return _result(false,"not_authority")
	if not is_finite(delta) or delta<=0 or delta>.1: return _result(false,"invalid_delta")
	if state=="idle": return _result(false,"not_started")
	if not is_instance_valid(body) or not body.is_inside_tree(): return _stop("missing_carrier")
	if suspended or not body.enabled:
		_brake()
		stable_seconds=0.0
		return _result(false,"suspended")
	if not _same_attachment(): return _stop("attachment_changed")
	var checked := _support(support)
	if not checked.ok or not checked.bounds.is_equal_approx(support_box): return _stop("support_changed")
	var load_bounds := _bounds(cargo)
	var hull_bounds := _bounds(body)
	if not load_bounds.ok or not hull_bounds.ok: return _stop("unsupported_envelope")
	var load_box: AABB = load_bounds.bounds
	if not _above(load_box,support_box) or load_box.position.y<support_box.end.y-.025: return _stop("load_left_support_column")
	if mode=="approach" and load_box.position.y<support_box.end.y+.15: return _stop("approach_undershot")
	if hull_bounds.bounds.position.y<support_box.end.y+.1: return _stop("hull_below_support")
	# The excluded RID is permitted only because its sole enabled shape is this
	# unchanged horizontal box entirely below the load. No collision is disabled.
	var merged: AABB = hull_bounds.bounds.merge(load_box).grow(Pilot.CLEARANCE)
	var query := PhysicsShapeQueryParameters3D.new()
	var shape := BoxShape3D.new()
	shape.size=merged.size
	query.shape=shape
	query.transform=Transform3D(Basis.IDENTITY,merged.get_center())
	query.collision_mask=MASK
	query.exclude=[body.get_rid(),cargo.get_rid(),support.get_rid()]
	var space := body.get_world_3d().direct_space_state
	if not space.intersect_shape(query,1).is_empty(): return _stop("other_initial_overlap")
	var offset := target-body.global_position
	var desired := Vector3(offset.x,0,offset.z).limit_length(.3)
	var vertical := clampf(offset.y*1.2,-.18,0.0) if mode=="approach" else clampf(offset.y*1.2,0.0,.35)
	for velocity: Vector3 in [body.linear_velocity,cargo.linear_velocity,Vector3(desired.x,vertical,desired.z)]:
		if velocity.length()<.01: continue
		query.motion=velocity.normalized()*(velocity.length()+velocity.length_squared()/4.0+.2)
		var fraction := space.cast_motion(query)
		if fraction.size()!=2 or fraction[0]<.999: return _stop("other_stopping_sweep")
	# Once the ordinary full-envelope query passes, an executor may safely use
	# the ordinary pilot again. No route/receipt is confirmed by this module.
	var normal: Dictionary=ordinary.probe(Vector3.ZERO)
	var end_clear: bool=normal.clear
	if mode=="approach": end_clear=absf(load_box.position.y-support_box.end.y-.25)<.05
	if end_clear and offset.length()<.08 and body.linear_velocity.length()<.12 and cargo.linear_velocity.length()<.15:
		stable_seconds+=delta
	else: stable_seconds=0.0
	if mode=="approach": state="ready" if stable_seconds>=.35 else "approaching"
	else: state="clear" if stable_seconds>=.35 else "lifting"
	reason=""
	body.hold_height=target.y
	body.command={"active":true,"mode":"assisted","body_relative":false,
		"planar":desired/float(body.stats.speed_mps),"vertical":vertical/float(body.stats.fall_mps if vertical<0 else body.stats.rise_mps),"yaw":0.0,"brake":false,"fire":false}
	if state in ["clear","ready"]: _brake()
	return _result(true,"clear_for_normal_flight" if state=="clear" else ("ready_for_release" if state=="ready" else state))

func _same_attachment() -> bool:
	if not is_instance_valid(cargo) or not cargo.is_inside_tree() or not is_instance_valid(joint) or joint.is_queued_for_deletion() or body.cargo_items.size()!=1: return false
	var item: Dictionary=body.cargo_items.values()[0]
	return item.body==cargo and item.joint==joint and joint.get_node_or_null(joint.node_a)==body and joint.get_node_or_null(joint.node_b)==cargo

static func _support(berth: StaticBody3D) -> Dictionary:
	if not is_instance_valid(berth) or not berth.is_inside_tree() or berth.is_queued_for_deletion() or berth.collision_layer & MASK == 0: return {"ok":false,"code":"missing_support"}
	if berth.constant_linear_velocity.length_squared()>0 or berth.constant_angular_velocity.length_squared()>0: return {"ok":false,"code":"moving_support"}
	var owners := berth.get_shape_owners()
	if owners.size()!=1: return {"ok":false,"code":"single_box_support_required"}
	var owner: int=owners[0]
	if berth.is_shape_owner_disabled(owner) or berth.shape_owner_get_shape_count(owner)!=1: return {"ok":false,"code":"single_box_support_required"}
	var shape: Shape3D=berth.shape_owner_get_shape(owner,0)
	var pose: Transform3D=berth.global_transform*berth.shape_owner_get_transform(owner)
	if not shape is BoxShape3D or not pose.basis.is_equal_approx(Basis.IDENTITY): return {"ok":false,"code":"horizontal_unscaled_box_required"}
	return {"ok":true,"bounds":pose*AABB(-shape.size*.5,shape.size)}

static func _bounds(part: RigidBody3D) -> Dictionary:
	var result := AABB()
	var first := true
	for owner: int in part.get_shape_owners():
		if part.is_shape_owner_disabled(owner): continue
		var pose: Transform3D=part.global_transform*part.shape_owner_get_transform(owner)
		for i in part.shape_owner_get_shape_count(owner):
			var shape: Shape3D=part.shape_owner_get_shape(owner,i)
			if not shape is BoxShape3D: return {"ok":false}
			var box: AABB=pose*AABB(-shape.size*.5,shape.size)
			result=box if first else result.merge(box)
			first=false
	return {"ok":not first,"bounds":result}

static func _above(box: AABB,slab: AABB) -> bool:
	return box.position.x>=slab.position.x+.05 and box.end.x<=slab.end.x-.05 and box.position.z>=slab.position.z+.05 and box.end.z<=slab.end.z-.05

func _brake() -> void:
	if not is_instance_valid(body): return
	body.hold_height=body.global_position.y
	body.command={"active":true,"mode":"assisted","body_relative":false,"planar":Vector3.ZERO,"vertical":0.0,"yaw":0.0,"brake":true,"fire":false}

func _stop(code: String) -> Dictionary:
	_brake()
	state="blocked"
	reason=code
	stable_seconds=0.0
	return _result(false,code)

func _result(ok: bool,code: String) -> Dictionary:
	return {"ok":ok,"code":code,"state":state,"clear":state=="clear","ready_for_release":state=="ready","mode":mode,"serial":serial,"settled_seconds":stable_seconds}
