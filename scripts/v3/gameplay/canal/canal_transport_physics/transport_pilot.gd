extends RefCounted
## Candidate host controller. Commands the real FlightBody; never assigns poses,
## velocity or cargo ownership. A waypoint is not a completed logistics action.
const FlightBody = preload("res://scripts/v2/flight_body.gd")
const MAX_SPEED := 1.8
const CLEARANCE := 0.18
const OBSTACLES := 1 | 2 | 4 | 8 | 32
const SPEED_SCALES := [1.0, .75, .5, .35, .2, .1, .05]
const MIN_SWEEP_SPEED := .01
const PICKUP_TOLERANCE := .025
const PICKUP_MAX_ADJUSTMENT := .35
const PICKUP_LOAD_OFFSET := Vector3(0,-1.1,0)
const PICKUP_POSITION_GAIN := .8
const PICKUP_VELOCITY_DAMPING := .45
const PICKUP_WIND_COMPENSATION_LIMIT := .06
var body: FlightBody
var target := Vector3.ZERO
var state := "unbound"
var serial := 0
var settled_seconds := 0.0
var clear_seconds := 0.0
var last_probe: Dictionary = {}
var speed_plan: Dictionary = {}
var mode := "route"
var alignment_cargo: WeakRef
var alignment_origin := Vector3.ZERO
var pickup_wind_compensation: Dictionary = {}

func bind(candidate: FlightBody) -> bool:
	if is_instance_valid(body) or not is_instance_valid(candidate) or not candidate.is_inside_tree() or candidate.stats.is_empty(): return false
	body = candidate
	state = "idle"
	return true

func go_to(point: Vector3, action_serial: int) -> bool:
	if not is_instance_valid(body) or not point.is_finite() or point.length() > 1000 or action_serial <= serial: return false
	if point.y < -10 or point.y > body.max_altitude: return false
	target = point
	serial = action_serial
	settled_seconds = 0.0
	clear_seconds = 0.0
	speed_plan = {}
	mode = "route"
	alignment_cargo = null
	pickup_wind_compensation = {}
	state = "traveling"
	return true

func go_to_pickup_alignment(cargo: RigidBody3D, action_serial: int) -> bool:
	# A local empty-hook adjustment, not a substitute route or an attach action.
	if not is_instance_valid(body) or not body.is_inside_tree() or not body.cargo_items.is_empty(): return false
	if not is_instance_valid(cargo) or not cargo.is_inside_tree() or cargo is FlightBody or cargo.get_world_3d().space != body.get_world_3d().space: return false
	if not cargo.global_position.is_finite() or not cargo.linear_velocity.is_finite() or not cargo.angular_velocity.is_finite() or cargo.linear_velocity.length() > .12 or cargo.angular_velocity.length() > .15: return false
	var goal := cargo.global_position - PICKUP_LOAD_OFFSET
	if body.global_position.distance_to(goal) > PICKUP_MAX_ADJUSTMENT or not go_to(goal,action_serial): return false
	mode = "pickup_alignment"
	alignment_cargo = weakref(cargo)
	alignment_origin = cargo.global_position
	return true

func tick(delta: float, host_authority: bool = true, suspended: bool = false) -> Dictionary:
	if not is_instance_valid(body) or not body.is_inside_tree(): return {"state":"unbound","arrived":false}
	if not host_authority: return {"state":"not_authority","arrived":false}
	if not is_finite(delta) or delta <= 0.0 or delta > 0.1: return {"state":"invalid_delta","arrived":false}
	if suspended or not body.enabled or state == "idle":
		pickup_wind_compensation = {}
		_brake()
		settled_seconds = 0.0
		return {"state":"suspended" if suspended else "idle","arrived":false}
	if mode == "pickup_alignment":
		var cargo: Variant = alignment_cargo.get_ref() if alignment_cargo != null else null
		if not cargo is RigidBody3D or not is_instance_valid(cargo) or not cargo.is_inside_tree() or not body.cargo_items.is_empty() or cargo.global_position.distance_to(alignment_origin) > .05 or cargo.linear_velocity.length() > .12 or cargo.angular_velocity.length() > .15:
			state = "blocked"
			settled_seconds = 0.0
			last_probe = {"clear":false,"reason":"alignment_target_changed"}
			speed_plan = {"commanded":false,"reason":"alignment_target_changed","attempts":[],"probe":last_probe}
			_brake()
			return report()
		target = cargo.global_position - PICKUP_LOAD_OFFSET
	var offset := target - body.global_position
	var horizontal := Vector3(offset.x,0,offset.z)
	var precise: bool = mode == "pickup_alignment"
	var desired := horizontal.limit_length(MAX_SPEED) if horizontal.length() > .02 else Vector3.ZERO
	var vertical := clampf(offset.y * 1.2, -.7, .7)
	if precise:
		# FlightBody already closes a velocity loop through the real attitude
		# dynamics. Keep this local position loop slower and oppose measured
		# motion before crossing the target; do not snap or clear physical speed.
		pickup_wind_compensation = _pickup_wind_feedforward()
		if not pickup_wind_compensation.ok:
			state = "blocked"
			settled_seconds = 0.0
			clear_seconds = 0.0
			last_probe = {"clear":false,"reason":"invalid_alignment_environment"}
			speed_plan = {"commanded":false,"reason":"invalid_alignment_environment","attempts":[],"probe":last_probe}
			_brake()
			return report()
		var damped: Vector3 = offset * PICKUP_POSITION_GAIN - body.linear_velocity * PICKUP_VELOCITY_DAMPING + Vector3(pickup_wind_compensation.requested_compensation)
		desired = Vector3(damped.x,0,damped.z).limit_length(.25)
		vertical = clampf(damped.y,-.25,.25)
	speed_plan = _select_velocity(Vector3(desired.x,vertical,desired.z))
	last_probe = speed_plan.probe
	if not last_probe.clear:
		if state != "blocked": body.hold_height = body.global_position.y
		state = "blocked"
		clear_seconds = 0.0
		settled_seconds = 0.0
		_brake()
		return report()
	if state == "blocked":
		clear_seconds += delta
		if clear_seconds < .25:
			_brake()
			return report()
	state = "traveling"
	var selected: Vector3 = speed_plan.selected_velocity
	desired = Vector3(selected.x,0,selected.z)
	vertical = selected.y
	# FlightBody uses hold_height when normalized vertical is within its .02
	# deadband. Match that fallback's (height_error * 2) to the swept velocity;
	# assigning the distant waypoint here would silently bypass a reduced speed.
	body.hold_height = body.global_position.y + vertical * .5
	var rise := float(body.stats.rise_mps if vertical >= 0 else body.stats.fall_mps)
	body.command = {"active":true,"mode":"assisted","body_relative":false,
		"planar":desired / float(body.stats.speed_mps), "vertical":vertical / rise,
		"yaw":0.0,"brake":false,"fire":false}
	speed_plan.commanded = true
	var cargo_still := true
	for item: Dictionary in body.cargo_items.values():
		if not is_instance_valid(item.body) or item.body.linear_velocity.length() > .3: cargo_still = false
	var position_tolerance: float = PICKUP_TOLERANCE if precise else .18
	var speed_tolerance: float = .04 if precise else .18
	if offset.length() < position_tolerance and body.linear_velocity.length() < speed_tolerance and cargo_still and (not precise or body.angular_velocity.length() < .08):
		settled_seconds += delta
	else: settled_seconds = 0.0
	if settled_seconds >= .35: state = "arrived"
	return report()

func _pickup_wind_feedforward() -> Dictionary:
	# Empty-hook precision mode only. Match FlightBody._integrate_forces:
	# its quadratic drag force is .042*density*|v-w|*(w-v), and its assisted
	# horizontal velocity loop asks for acceleration 2*(desired-v). Counter the
	# measured model disturbance through normal commands, never external forces.
	# The .06 m/s cap bounds this model-dependent correction. It is not a promise
	# of accurate gripping in arbitrary wind, damage or unknown external forces.
	var wind: Variant=body.environment_sample.get("wind_velocity",Vector3.ZERO)
	var density: Variant=body.environment_sample.get("density",1.225)
	if not wind is Vector3 or not wind.is_finite() or not (density is float or density is int) or not is_finite(float(density)) or not is_finite(body.mass) or body.mass<=0.0 or not body.linear_velocity.is_finite():
		return {"ok":false,"reason":"invalid_wind_model_input"}
	var drag: Vector3=body.linear_velocity-Vector3(wind)
	var force: Vector3=(-drag*drag.length()*.042*clampf(float(density),.95,1.35)).limit_length(body.mass*7.0)
	var acceleration: Vector3=force/body.mass
	var raw:=Vector3(-acceleration.x*.5,0,-acceleration.z*.5)
	var compensation: Vector3=raw.limit_length(PICKUP_WIND_COMPENSATION_LIMIT)
	return {"ok":true,"wind_velocity":wind,"drag_acceleration":acceleration,"raw_compensation":raw,
		"requested_compensation":compensation,"capped":raw.length()>PICKUP_WIND_COMPENSATION_LIMIT,
		"limit_mps":PICKUP_WIND_COMPENSATION_LIMIT}

func _brake() -> void:
	if not speed_plan.is_empty(): speed_plan.commanded = false
	body.command = {"active":true,"mode":"assisted","body_relative":false,
		"planar":Vector3.ZERO,"vertical":0.0,"yaw":0.0,"brake":true,"fire":false}

func report() -> Dictionary:
	return {"state":state,"arrived":state == "arrived", "serial":serial,
		"mode":mode,"target":target,"position_tolerance_m":PICKUP_TOLERANCE if mode == "pickup_alignment" else .18,
		"distance_m":body.global_position.distance_to(target),"speed_mps":body.linear_velocity.length(),
		"cargo_swing_deg":body.cargo_swing(),"settled_seconds":settled_seconds,"probe":last_probe.duplicate(true),
		"pickup_wind_compensation":pickup_wind_compensation.duplicate(true),
		"speed_plan":speed_plan.duplicate(true)}

func _select_velocity(requested: Vector3) -> Dictionary:
	# Current inertia is never scaled, truncated at the waypoint, or bypassed.
	# Trying a slower future command is permitted only after this full live probe.
	var actual: Dictionary = probe(Vector3.ZERO)
	var plan := {"requested_velocity":requested,"requested_speed_mps":requested.length(),
		"selected_velocity":Vector3.ZERO,"selected_speed_mps":0.0,"scale":0.0,
		"commanded":false,"reason":"actual_motion_unsafe","attempts":[],"actual_probe":actual.duplicate(true),"probe":actual}
	if not actual.clear: return plan
	# A suspended load can move faster or sideways relative to the carrier.
	# This is an actual-inertia gate, never a slower desired-speed candidate.
	# Keep probe() unchanged: Dock uses its existing public envelope contract.
	var load_actual: Dictionary = _cargo_inertia_probe()
	plan.cargo_actual_probe = load_actual
	if not load_actual.clear:
		plan.actual_probe = load_actual.duplicate(true)
		plan.probe = load_actual
		plan.reason = "cargo_inertia_unsafe"
		return plan
	for scale_value: float in SPEED_SCALES:
		var candidate := requested * scale_value
		# Do not use the original near-zero sweep deadband as a way through a wall.
		if requested.length() >= MIN_SWEEP_SPEED and candidate.length() < MIN_SWEEP_SPEED: break
		var checked: Dictionary = probe(candidate)
		plan.attempts.append({"scale":scale_value,"speed_mps":candidate.length(),"probe":checked.duplicate(true)})
		plan.probe = checked
		if checked.clear:
			plan.selected_velocity = candidate
			plan.selected_speed_mps = candidate.length()
			plan.scale = scale_value
			plan.reason = "requested_clear" if scale_value == 1.0 else "reduced_for_stopping_clearance"
			return plan
		if checked.get("blocked_by","") != "desired_velocity":
			plan.reason = "actual_motion_unsafe"
			return plan
	plan.reason = "no_safe_desired_speed"
	return plan

func _cargo_inertia_probe() -> Dictionary:
	# Use each load's own box, not the carrier/load union along a swing velocity.
	# Initial overlap is checked even at rest. No berth/terrain RID is excluded.
	if not is_instance_valid(body) or not body.is_inside_tree():
		return {"clear":false,"reason":"missing_carrier","blocked_by":"cargo_actual_velocity"}
	var exclude: Array[RID] = [body.get_rid()]
	var loads: Array[Dictionary] = []
	for id: Variant in body.cargo_items:
		var item: Variant = body.cargo_items[id]
		if not item is Dictionary or not item.get("body") is RigidBody3D or not is_instance_valid(item.body) or not item.body.is_inside_tree():
			return {"clear":false,"reason":"missing_load","blocked_by":"cargo_actual_velocity","cargo_id":str(id)}
		var cargo: RigidBody3D = item.body
		if cargo.get_world_3d().space != body.get_world_3d().space:
			return {"clear":false,"reason":"different_space","blocked_by":"cargo_actual_velocity","cargo_id":str(id)}
		if not cargo.linear_velocity.is_finite() or not cargo.global_transform.is_finite():
			return {"clear":false,"reason":"invalid_load_motion","blocked_by":"cargo_actual_velocity","cargo_id":str(id)}
		exclude.append(cargo.get_rid())
		var bounds := AABB()
		var initialized := false
		for child: Node in cargo.get_children():
			if child is CollisionPolygon3D and not child.disabled:
				return {"clear":false,"reason":"unsupported_load_envelope","blocked_by":"cargo_actual_velocity","cargo_id":str(id)}
			if not child is CollisionShape3D or child.disabled: continue
			if not child.shape is BoxShape3D or not child.global_transform.is_finite():
				return {"clear":false,"reason":"unsupported_load_envelope","blocked_by":"cargo_actual_velocity","cargo_id":str(id)}
			var size: Vector3 = child.shape.size
			if not size.is_finite() or size.x <= 0 or size.y <= 0 or size.z <= 0 or absf(child.global_basis.determinant()) < .000001:
				return {"clear":false,"reason":"unsupported_load_envelope","blocked_by":"cargo_actual_velocity","cargo_id":str(id)}
			var actual: AABB = child.global_transform * AABB(-size*.5,size)
			if not actual.position.is_finite() or not actual.size.is_finite():
				return {"clear":false,"reason":"unsupported_load_envelope","blocked_by":"cargo_actual_velocity","cargo_id":str(id)}
			bounds = bounds.merge(actual) if initialized else actual
			initialized = true
		if not initialized:
			return {"clear":false,"reason":"missing_load_envelope","blocked_by":"cargo_actual_velocity","cargo_id":str(id)}
		loads.append({"id":str(id),"body":cargo,"bounds":bounds.grow(CLEARANCE)})
	var space: PhysicsDirectSpaceState3D = body.get_world_3d().direct_space_state
	for load: Dictionary in loads:
		var cargo: RigidBody3D = load.body
		var bounds: AABB = load.bounds
		var shape := BoxShape3D.new()
		shape.size = bounds.size
		var query := PhysicsShapeQueryParameters3D.new()
		query.shape = shape
		query.transform = Transform3D(Basis.IDENTITY,bounds.get_center())
		query.collision_mask = OBSTACLES
		query.exclude = exclude
		var proof := {"clear":false,"blocked_by":"cargo_actual_velocity","cargo_id":load.id,
			"velocity":cargo.linear_velocity,"velocity_mps":cargo.linear_velocity.length(),
			"bounds_origin":bounds.position,"bounds_size":bounds.size,"initial_overlap":false}
		var hits := space.intersect_shape(query,1)
		if not hits.is_empty():
			proof.reason = "cargo_envelope_occupied"
			proof.initial_overlap = true
			proof.collider = _collider_path(hits[0])
			return proof
		var speed: float = cargo.linear_velocity.length()
		if speed < MIN_SWEEP_SPEED: continue
		query.motion = cargo.linear_velocity.normalized() * (speed + speed*speed/4.0 + .35)
		var fraction := space.cast_motion(query)
		if fraction.size() != 2 or fraction[0] < .999:
			proof.reason = "cargo_stopping_sweep_blocked"
			proof.motion_m = query.motion.length()
			proof.safe_fraction = fraction[0] if fraction.size() == 2 else 0.0
			proof.collider = ""
			if fraction.size() == 2:
				query.transform.origin += query.motion * minf(1.0,fraction[1]+.0001)
				query.motion = Vector3.ZERO
				hits = space.intersect_shape(query,1)
				if not hits.is_empty(): proof.collider = _collider_path(hits[0])
			return proof
	return {"clear":true,"reason":"cargo_inertia_clear","loads":loads.size()}

func probe(desired_velocity: Vector3) -> Dictionary:
	# Check the full live carrier + swinging load AABB, not merely a centre ray.
	# cast_motion ignores initial overlaps, so intersect_shape must run first.
	# https://docs.godotengine.org/en/stable/classes/class_physicsdirectspacestate3d.html
	if not desired_velocity.is_finite(): return {"clear":false,"reason":"invalid_velocity"}
	var bodies: Array[RigidBody3D] = [body]
	for item: Dictionary in body.cargo_items.values():
		if not is_instance_valid(item.body): return {"clear":false,"reason":"missing_load"}
		bodies.append(item.body)
	var bounds := AABB()
	var initialized := false
	var exclude: Array[RID] = []
	for part in bodies:
		exclude.append(part.get_rid())
		if part.get_world_3d().space != body.get_world_3d().space: return {"clear":false,"reason":"different_space"}
		var part_shapes := 0
		for child: Node in part.get_children():
			if child is CollisionShape3D and not child.disabled and child.shape is BoxShape3D:
				part_shapes += 1
				var size: Vector3 = child.shape.size
				var actual: AABB = child.global_transform * AABB(-size*.5,size)
				bounds = bounds.merge(actual) if initialized else actual
				initialized = true
			elif child is CollisionShape3D and not child.disabled:
				return {"clear":false,"reason":"unsupported_envelope"}
		if part_shapes == 0: return {"clear":false,"reason":"missing_part_envelope"}
	if not initialized: return {"clear":false,"reason":"missing_envelope"}
	bounds = bounds.grow(CLEARANCE)
	var query := PhysicsShapeQueryParameters3D.new()
	var shape := BoxShape3D.new()
	shape.size = bounds.size
	query.shape = shape
	query.transform = Transform3D(Basis.IDENTITY,bounds.get_center())
	query.collision_mask = OBSTACLES
	query.exclude = exclude
	var space := body.get_world_3d().direct_space_state
	var initial := space.intersect_shape(query,1)
	if not initial.is_empty():
		return {"clear":false,"reason":"envelope_occupied","blocked_by":"initial_overlap", "collider":_collider_path(initial[0])}
	# Allow one second for the real attitude/velocity loop plus braking distance.
	# The maximum load speed is intentionally modest; dynamic crossings still
	# require a later berth reservation / route executor, not a safety guarantee.
	for source: String in ["actual_velocity","desired_velocity"]:
		var velocity: Vector3 = body.linear_velocity if source == "actual_velocity" else desired_velocity
		if velocity.length() < MIN_SWEEP_SPEED: continue
		query.motion = velocity.normalized() * (velocity.length() + velocity.length_squared()/4.0 + .35)
		var fraction := space.cast_motion(query)
		if fraction.size() != 2 or fraction[0] < .999:
			var blocker_path := ""
			if fraction.size() == 2:
				# Diagnostic only: inspect the same box at the unsafe fraction. This
				# cannot turn a rejected sweep into permission to fly.
				var diagnostic := PhysicsShapeQueryParameters3D.new()
				diagnostic.shape = shape
				diagnostic.transform = query.transform
				diagnostic.transform.origin += query.motion * minf(1.0, fraction[1] + .0001)
				diagnostic.collision_mask = OBSTACLES
				diagnostic.exclude = exclude
				var hits := space.intersect_shape(diagnostic,1)
				if not hits.is_empty(): blocker_path = _collider_path(hits[0])
			return {"clear":false,"reason":"stopping_sweep_blocked","blocked_by":source,
				"velocity_mps":velocity.length(),"motion_m":query.motion.length(),
				"safe_fraction":fraction[0] if fraction.size() == 2 else 0.0,"collider":blocker_path}
	return {"clear":true,"reason":"clear","parts":bodies.size(),"bounds_size":bounds.size}

func _collider_path(hit: Dictionary) -> String:
	var collider: Variant = hit.get("collider")
	return str(collider.get_path()) if collider is Node and is_instance_valid(collider) else ""

## Serializable stationary WAIT controller, not a general moving-route save.
func snapshot_wait(expected_target: Vector3) -> Dictionary:
	if not is_instance_valid(body) or not body.is_inside_tree() or mode!="route" or state!="arrived" or target!=expected_target or body.global_position.distance_to(target)>=.18 or body.linear_velocity.length()>=.18: return {}
	var saved: Dictionary={"version":1,"mode":mode,"state":state,"target":[target.x,target.y,target.z],"serial":serial,"settled_seconds":settled_seconds,"clear_seconds":clear_seconds}
	return saved if validate_wait(saved,expected_target) else {}

static func validate_wait(saved: Variant, expected_target: Vector3) -> bool:
	if not saved is Dictionary or saved.size()!=7: return false
	for key: Variant in saved:
		if key not in ["version","mode","state","target","serial","settled_seconds","clear_seconds"]: return false
	if saved.version!=1 or saved.mode!="route" or saved.state!="arrived" or not saved.target is Array or saved.target.size()!=3: return false
	for item: Variant in saved.target:
		if not (item is float or item is int) or not is_finite(float(item)): return false
	if Vector3(saved.target[0],saved.target[1],saved.target[2])!=expected_target: return false
	for key: String in ["serial","settled_seconds","clear_seconds"]:
		if not (saved[key] is float or saved[key] is int) or not is_finite(float(saved[key])) or float(saved[key])<0 or float(saved[key])>2147483647: return false
	return float(saved.serial)>=1 and float(saved.serial)==floor(float(saved.serial)) and float(saved.settled_seconds)>=.35

func restore_wait_fresh(candidate: FlightBody, saved: Dictionary, expected_target: Vector3, authority: bool = true) -> Dictionary:
	if not authority or is_instance_valid(body) or state!="unbound" or not validate_wait(saved,expected_target): return {"ok":false,"code":"fresh_wait_controller_required"}
	if not is_instance_valid(candidate) or not candidate.is_inside_tree() or not candidate.freeze or candidate.global_position.distance_to(expected_target)>=.18: return {"ok":false,"code":"frozen_wait_pose_required"}
	if not bind(candidate): return {"ok":false,"code":"wait_bind_failed"}
	target=expected_target
	serial=int(saved.serial)
	mode="route"
	state="arrived"
	settled_seconds=float(saved.settled_seconds)
	clear_seconds=float(saved.clear_seconds)
	# Saved clear/arrived history never authorizes a new move: tick redoes all
	# real overlap/inertia/speed sweeps before its first resumed command.
	return {"ok":true,"code":"restored_wait_no_movement_or_receipt"}
