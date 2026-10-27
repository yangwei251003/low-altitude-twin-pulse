extends RefCounted
## Fresh NPC creation only. No operation accepts an already running FlightBody.
const Flight = preload("res://scripts/v2/flight_body.gd")
const Catalog = preload("res://scripts/v2/catalog.gd")
const SCALARS := ["battery","heat","heading","hold_height","shield_left","shield_cooldown","recovery_left","ability_left","ability_cooldown","flight_seconds","damage_taken"]
const TIMERS := ["shield_left","shield_cooldown","recovery_left","ability_left","ability_cooldown"]
const KEYS := ["id","pose","velocity","angular_velocity","health","maximum_health","state"]

static func capture(body: Flight, id: String) -> Dictionary:
	var state: Dictionary = {"damage":body.damage_snapshot(),"safe_position":xyz(body.safe_position)}
	for key: String in SCALARS: state[key] = body.get(key)
	return {"id":id,"pose":pose(body.global_transform),"velocity":xyz(body.linear_velocity),"angular_velocity":xyz(body.angular_velocity),"health":body.health,"maximum_health":body.maximum_health,"state":state}

static func validate(row: Variant, id: String) -> bool:
	if not exact(row,KEYS) or row.id != id or not pose_valid(row.pose) or not vector_valid(row.velocity,.18) or vec(row.velocity).length() >= .18 or not vector_valid(row.angular_velocity,.15) or vec(row.angular_velocity).length() > .15: return false
	if not number(row.maximum_health,100,100) or not number(row.health,.000001,100): return false
	var keys: Array = SCALARS.duplicate()
	keys.append_array(["damage","safe_position"])
	if not exact(row.state,keys) or not vector_valid(row.state.safe_position,1000): return false
	var state: Dictionary = row.state
	if not number(state.battery,0,100) or not number(state.heat,0,100) or not number(state.heading,-1.0e9,1.0e9) or not number(state.hold_height,-1000,1000): return false
	for key: String in TIMERS:
		if not number(state[key],0,3600): return false
	for key: String in ["flight_seconds","damage_taken"]:
		if not number(state[key],0,1.0e12): return false
	var damage: Variant = state.damage
	if not exact(damage,["health","maximum_health","armor","maximum_armor","components","serial"]): return false
	if not number(damage.health,float(row.health),float(row.health)) or not number(damage.maximum_health,100,100) or not number(damage.maximum_armor,14,14) or not number(damage.armor,0,14) or not integer(damage.serial,0,9007199254740991): return false
	if not exact(damage.components,["rotor_left","rotor_right","power","sensor"]): return false
	for key: String in damage.components:
		var component: Variant = damage.components[key]
		var maximum: float = 28.000000000000004 if key.begins_with("rotor") else 32.0
		if not exact(component,["health","maximum"]) or not number(component.maximum,maximum-.000000000001,maximum+.000000000001) or not number(component.health,0,float(component.maximum)): return false
	return true

static func safe_live(body: Flight) -> bool:
	# Transient contact IDs and external forces are deliberately not serialized.
	# Only an uncontacted, enabled, non-cheat NPC can enter this safe boundary.
	return not body.practice and body.sandbox_rules.is_empty() and body.enabled and not body.freeze and body.contact_cooldowns.is_empty() and body.collision_count == 0 and not body.water_contact and body.water_seconds == 0.0 and body.environment_acceleration.is_zero_approx() and body.collision_damage_scale == 1.0 and body.cargo_items.is_empty() and not body.crash_reported

static func create(parent: Node3D, row: Dictionary, id: String, mask: int, environment: Callable, keep_frozen: bool = false, wait_state: bool = false) -> Dictionary:
	if not is_instance_valid(parent) or not parent.is_inside_tree() or not environment.is_valid() or mask not in [45,47] or not (validate_wait(row,id) if wait_state else validate(row,id)): return {"ok":false,"code":"fresh_flight_contract"}
	var sample: Variant = environment.call(transform(row.pose).origin)
	if not sample is Dictionary: return {"ok":false,"code":"fresh_flight_environment"}
	# World.water labels the whole water column; mirror Flight's actual contact
	# height instead of rejecting a legitimate airborne point above the canal.
	if bool(sample.get("water",false)) and transform(row.pose).origin.y < float(sample.get("water_height",-.6))+.23: return {"ok":false,"code":"fresh_flight_water_contact"}
	var body = Flight.new()
	body.name = id.replace(":","_")
	body.configure(Catalog.resolve_build(Catalog.default_build("tr01")))
	body.freeze = true
	body.max_altitude = 18.0
	parent.add_child(body)
	body.collision_mask = mask
	body.global_transform = transform(row.pose)
	body.linear_velocity = vec(row.velocity)
	body.angular_velocity = vec(row.angular_velocity)
	body.last_velocity = body.linear_velocity
	body.restore_damage_state(row.state.damage)
	for key: String in SCALARS: body.set(key,float(row.state[key]))
	body.safe_position = vec(row.state.safe_position)
	body.environment_query = environment
	body.environment_hazards_authoritative = true
	body.environment_sample = sample.duplicate(true)
	body.command = {"active":true,"mode":"assisted","body_relative":false,"planar":Vector3.ZERO,"vertical":0.0,"yaw":0.0,"brake":true,"fire":false}
	if wait_state:
		body.collision_count = int(row.wait.collision_count)
		body.last_velocity = vec(row.wait.last_velocity)
		body.command = row.wait.command.duplicate(true)
		body.command.planar = vec(row.wait.command.planar)
	body.freeze = keep_frozen
	return {"ok":true,"code":"created_fresh_flight","body":body}

static func xyz(v: Vector3) -> Array:
	return [v.x,v.y,v.z]

static func vec(v: Array) -> Vector3:
	return Vector3(v[0],v[1],v[2])

static func pose(t: Transform3D) -> Array:
	return [t.basis.x.x,t.basis.x.y,t.basis.x.z,t.basis.y.x,t.basis.y.y,t.basis.y.z,t.basis.z.x,t.basis.z.y,t.basis.z.z,t.origin.x,t.origin.y,t.origin.z]

static func transform(v: Array) -> Transform3D:
	return Transform3D(Basis(Vector3(v[0],v[1],v[2]),Vector3(v[3],v[4],v[5]),Vector3(v[6],v[7],v[8])),Vector3(v[9],v[10],v[11]))

static func pose_valid(v: Variant) -> bool:
	if not v is Array or v.size() != 12: return false
	for n: Variant in v:
		if not number(n,-1000,1000): return false
	var t: Transform3D = transform(v)
	return absf(t.basis.determinant()-1.0) < .0001 and t.basis.is_equal_approx(t.basis.orthonormalized())

static func vector_valid(v: Variant, bound: float) -> bool:
	if not v is Array or v.size() != 3: return false
	for n: Variant in v:
		if not number(n,-bound,bound): return false
	return true

static func number(v: Variant, low: float, high: float) -> bool:
	return (v is int or v is float) and is_finite(float(v)) and float(v)>=low and float(v)<=high

static func integer(v: Variant, low: int, high: int) -> bool:
	return number(v,low,high) and floor(float(v)) == float(v)

static func exact(v: Variant, keys: Array) -> bool:
	if not v is Dictionary or v.size() != keys.size(): return false
	for key: Variant in v:
		if not key is String or key not in keys: return false
	return true

## Separate WAIT boundary: old completed-safe validation remains unchanged.
static func capture_wait(body: Flight, id: String) -> Dictionary:
	var result: Dictionary=capture_wait_checked(body,id)
	return result.state if result.ok else {}

static func capture_wait_checked(body: Flight, id: String) -> Dictionary:
	if body.build != Catalog.resolve_build(Catalog.default_build("tr01")).build: return {"ok":false,"code":"wait_flight_build"}
	if not body.enabled or body.practice or not body.sandbox_rules.is_empty() or body.crash_reported: return {"ok":false,"code":"wait_flight_mode"}
	if body.water_contact or body.water_seconds != 0.0: return {"ok":false,"code":"wait_flight_water"}
	if not body.environment_acceleration.is_zero_approx() or body.collision_damage_scale != 1.0: return {"ok":false,"code":"wait_flight_external_force"}
	for stamp: Variant in body.contact_cooldowns.values():
		if not number(stamp,0,body.flight_seconds) or body.flight_seconds-float(stamp)<.7: return {"ok":false,"code":"wait_flight_active_contact_cooldown"}
	var row: Dictionary=capture(body,id)
	var command: Dictionary=body.command.duplicate(true)
	if not command.get("planar") is Vector3: return {"ok":false,"code":"wait_flight_planar_type"}
	command.planar=xyz(command.planar)
	# A new dotted Dictionary key is StringName in Godot; the saved schema
	# deliberately requires String keys before any JSON conversion.
	row["wait"]={"collision_count":body.collision_count,"last_velocity":xyz(body.last_velocity),"command":command}
	var issue: String=wait_validation_issue(row,id)
	if not issue.is_empty(): return {"ok":false,"code":"wait_flight_serialized_state:"+issue,"state":row}
	return {"ok":true,"code":"captured_wait_flight","state":row}

static func validate_wait(row: Variant, id: String) -> bool:
	return wait_validation_issue(row,id).is_empty()

static func wait_validation_issue(row: Variant, id: String) -> String:
	var keys: Array=KEYS.duplicate()
	keys.append("wait")
	if not exact(row,keys): return "keys"
	if not vector_valid(row.velocity,.5) or vec(row.velocity).length()>.5: return "velocity"
	if not vector_valid(row.angular_velocity,.5) or vec(row.angular_velocity).length()>.5: return "angular_velocity"
	var base: Dictionary=row.duplicate(true)
	base.erase("wait")
	base.velocity=[0.0,0.0,0.0]
	base.angular_velocity=[0.0,0.0,0.0]
	if not validate(base,id): return "base_flight"
	if not exact(row.wait,["collision_count","last_velocity","command"]): return "wait_keys"
	if not integer(row.wait.collision_count,0,2147483647): return "collision_count"
	if not vector_valid(row.wait.last_velocity,10): return "last_velocity"
	var command: Variant=row.wait.command
	if not command is Dictionary or command.size()>12: return "command_type_size"
	var allowed: Array=["active","mode","body_relative","planar","vertical","yaw","pitch","roll","brake","fire","throttle"]
	for key: Variant in command:
		if key not in allowed: return "command_key:"+str(key)
	if command.get("active")!=true or command.get("mode") not in ["assisted","manual_throttle"] or command.get("body_relative")!=false or not vector_valid(command.get("planar"),1): return "command_mode_planar"
	for key: String in ["brake","fire"]:
		if not command.get(key) is bool: return "command_bool:"+key
	if command.fire: return "command_fire"
	for key: String in ["vertical","yaw","pitch","roll","throttle"]:
		if command.has(key) and not number(command[key],0 if key=="throttle" else -1,1): return "command_number:"+key
	return ""

## General normal-chain NPC motion. WAIT/completed validators are unchanged.
## The wider velocity bounds belong to this separate versioned envelope only.
static func capture_progress(body: Flight, id: String) -> Dictionary:
	if body.build != Catalog.resolve_build(Catalog.default_build("tr01")).build or not body.enabled or body.practice or not body.sandbox_rules.is_empty() or body.crash_reported or body.water_contact or body.water_seconds!=0.0 or not body.environment_acceleration.is_zero_approx() or body.collision_damage_scale!=1.0: return {}
	var row: Dictionary=capture(body,id)
	var command: Dictionary=body.command.duplicate(true)
	if not command.get("planar") is Vector3: return {}
	command.planar=xyz(command.planar)
	row["wait"]={"collision_count":body.collision_count,"last_velocity":xyz(body.last_velocity),"command":command}
	return row if validate_progress(row,id) else {}

static func validate_progress(row: Variant, id: String) -> bool:
	if not row is Dictionary or not vector_valid(row.get("velocity"),15.0) or not vector_valid(row.get("angular_velocity"),8.0): return false
	var stationary: Dictionary=row.duplicate(true)
	stationary.velocity=[0.0,0.0,0.0]
	stationary.angular_velocity=[0.0,0.0,0.0]
	return wait_validation_issue(stationary,id).is_empty()

static func create_progress(parent: Node3D, row: Dictionary, id: String, mask: int, environment: Callable) -> Dictionary:
	if not validate_progress(row,id): return {"ok":false,"code":"progress_flight_schema"}
	var stationary: Dictionary=row.duplicate(true)
	stationary.velocity=[0.0,0.0,0.0]
	stationary.angular_velocity=[0.0,0.0,0.0]
	var made: Dictionary=create(parent,stationary,id,mask,environment,true,true)
	if not made.ok: return made
	# This is a new frozen body, never a live continuation pose/momentum write.
	made.body.linear_velocity=vec(row.velocity)
	made.body.angular_velocity=vec(row.angular_velocity)
	made.body.last_velocity=vec(row.wait.last_velocity)
	return made
