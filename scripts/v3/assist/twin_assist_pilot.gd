extends "res://scripts/v3/gameplay/canal/canal_transport_physics/transport_pilot.gd"
## Product command composer. Reuses the production transport pilot's read-only
## full-hull/cargo/inertia sweeps, but never calls its command-writing tick().
## Session sends the returned command through the same local/Host input path.
var last_command: Dictionary = {}
var blocked_seconds := 0.0

func compose(delta: float, point: Vector3, precision: bool = false) -> Dictionary:
	var command := neutral()
	if not is_instance_valid(body) or not body.enabled or not point.is_finite(): return command
	var offset: Vector3 = point - body.global_position
	var loaded := not body.cargo_items.is_empty()
	var top_speed := 1.8 if loaded else 5.0
	if precision: top_speed = 1.2
	var desired: Vector3 = Vector3(offset.x, 0, offset.z).limit_length(minf(top_speed, float(body.stats.speed_mps)))
	var vertical := clampf(offset.y * 1.2, -1.8, 1.8)
	if loaded: vertical = clampf(vertical, -.7, .7)
	if precision: vertical = clampf(vertical, -.7, .7)
	# Ordinary upward input is needed when the real landing gear/load is still
	# supported. Do not ignore the floor in the conservative free-flight probe.
	if body.grounded and offset.y > .5:
		command.brake = false
		command.vertical = .45
		state = "lifting"
		last_command = command
		return command
	speed_plan = _select_velocity(Vector3(desired.x, vertical, desired.z))
	last_probe = speed_plan.get("probe", {})
	if not bool(last_probe.get("clear", false)):
		blocked_seconds += delta
		state = "blocked"
		last_command = command
		return command
	blocked_seconds = 0.0
	var selected: Vector3 = speed_plan.get("selected_velocity", Vector3.ZERO)
	var rise := maxf(.1, float(body.stats.rise_mps if selected.y >= 0 else body.stats.fall_mps))
	command.planar = Vector3(selected.x, 0, selected.z) / maxf(.1, float(body.stats.speed_mps))
	# Turn through the same yaw input as a human pilot. World-planar thrust
	# remains independent so turning cannot bend a narrow authored corridor.
	var horizontal := Vector2(selected.x,selected.z)
	if horizontal.length()>.45 and Vector2(offset.x,offset.z).length()>.65:
		var course := atan2(-selected.x,-selected.z)
		var error := wrapf(course-float(body.heading),-PI,PI)
		var yaw_speed := maxf(.1,deg_to_rad(float(body.stats.yaw_deg_s)))
		if absf(error)>.035: command.yaw = clampf(-error*2.0/yaw_speed,-.8,.8)
	command.vertical = selected.y / rise
	# Stay on the real vertical-input path until the target is reached; no
	# direct hold-height, pose, velocity, force or time assignment is required.
	if absf(offset.y) > .04 and absf(float(command.vertical)) <= .02:
		command.vertical = signf(offset.y) * .021
	command.brake = false
	var tolerance := .22 if precision else .35
	if offset.length() <= tolerance and body.linear_velocity.length() < .3:
		settled_seconds += delta
	else: settled_seconds = 0.0
	state = "arrived" if settled_seconds >= .25 else "traveling"
	last_command = command
	return command

static func neutral() -> Dictionary:
	return {"active":true, "mode":"assisted", "body_relative":false,
		"planar":Vector3.ZERO, "pitch":0.0, "roll":0.0, "vertical":0.0,
		"yaw":0.0, "brake":true, "fire":false, "interact":false, "edges":[]}
