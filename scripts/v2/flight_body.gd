class_name FlightBodyV2
extends RigidBody3D

const MAX_ENVIRONMENT_ACCELERATION = 4.0
const DamageModel = preload("res://scripts/v2/damage_model.gd")

signal collision_event(event: Dictionary)
signal damaged(amount: float, direction: Vector3)
signal disabled
signal damage_resolved(receipt: Dictionary)
signal crash_started

var build: Dictionary = {}
var stats: Dictionary = {}
var command: Dictionary = {}
var telemetry: Dictionary = {}
var model: Node3D
var rotors: Array[Node3D] = []
var health = 100.0
var maximum_health = 100.0
var heat = 0.0
var max_heat = 100.0
var enabled = true
var practice = false
var sandbox_rules: Dictionary = {}
var environment_sample: Dictionary = {}
var environment_query: Callable
# V2/single-player default remains authoritative. V3 prediction may apply water
# forces, but only the host may commit water rescue/health consequences.
var environment_hazards_authoritative := true
var collision_damage_scale = 1.0
var battery = 100.0
var water_seconds = 0.0
var water_contact = false
var safe_position = Vector3.ZERO
signal water_entered
signal rescued
var heading = 0.0
var hold_height = 2.8
var cargo_kg = 0.0
var cargo_body: RigidBody3D
var cargo_joint: PinJoint3D
var cargo_id = ""
var cargo_items: Dictionary = {}
var collision_count = 0
var damage_taken = 0.0
var shield_left = 0.0
var shield_cooldown = 0.0
var recovery_left = 0.0
var flight_seconds = 0.0
var ground_y = 0.0
var ground_distance = 0.0
var grounded = false
var thrust_fraction = 0.0
var last_velocity = Vector3.ZERO
var contact_cooldowns: Dictionary = {}
var ground_projection: MeshInstance3D
var max_altitude = 32.0
var ability_left = 0.0
var ability_cooldown = 0.0
var searchlight: SpotLight3D
var visibility_silhouette: Node3D
var silhouette_parts: Array[Dictionary] = []
var silhouette_material: StandardMaterial3D
var silhouette_strength = 0.0
var occlusion_hint = false
var damage_state: Dictionary = {}
var component_effects: Dictionary = {}
var crash_seconds = 0.0
var crash_reported = false
var environment_acceleration: Vector3 = Vector3.ZERO:
	set(value):
		environment_acceleration = value.limit_length(MAX_ENVIRONMENT_ACCELERATION) if value.is_finite() else Vector3.ZERO

func configure(resolved: Dictionary) -> void:
	build = resolved.build.duplicate(true)
	# The suspended body carries cargo mass; chassis stats always start unloaded.
	stats = CatalogV2.resolve_build(build, 0.0).derived
	mass = float(stats.mass_kg)
	maximum_health = float(stats.health)
	health = maximum_health
	max_heat = float(stats.heat_capacity)
	var armor = {"tr01":14.0,"hx02":24.0,"ag03":10.0,"nx04":12.0,"sh05":36.0,"at06":22.0}.get(str(build.get("airframe_id","tr01")),14.0)
	if build.get("slots",{}).get("utility","")=="reinforced_guard":armor+=12.0
	damage_state=DamageModel.create_state(maximum_health,armor,Vector3(float(stats.get("width_m",1.4)),float(stats.get("height_m",.48)),float(stats.get("length_m",1.4))))
	component_effects=DamageModel.impairment(damage_state)
	if is_inside_tree():
		_refresh_collider()
		_sync_searchlight()

func _ready() -> void:
	contact_monitor = true
	max_contacts_reported = 12
	continuous_cd = true
	collision_layer = 2
	collision_mask = 1 | 4 | 8 | 32
	linear_damp = 0.16
	angular_damp = 0.5
	can_sleep = false
	physics_material_override = PhysicsMaterial.new()
	physics_material_override.friction = 0.4
	physics_material_override.bounce = 0.12
	_refresh_collider()
	model = FleetVisualsV2.make_drone(build.get("airframe_id", "tr01"), build.get("slots", {}))
	add_child(model)
	_find_rotors(model)
	rebuild_visibility_silhouette()
	_sync_searchlight()
	ground_projection = GameVisuals.ring(get_parent(), Vector3.ZERO, 0.9, Color("42c7b2"), 0.055)

func rebuild_visibility_silhouette() -> void:
	if is_instance_valid(visibility_silhouette): visibility_silhouette.queue_free()
	silhouette_parts.clear()
	visibility_silhouette = Node3D.new()
	visibility_silhouette.name = "OccludedPilotSilhouette"
	add_child(visibility_silhouette)
	visibility_silhouette.visible = false
	silhouette_material = StandardMaterial3D.new()
	silhouette_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	silhouette_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	silhouette_material.no_depth_test = true
	silhouette_material.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	silhouette_material.render_priority = 20
	silhouette_material.albedo_color = Color(0.30, 1.0, 0.85, 0.0)
	silhouette_material.grow = true
	silhouette_material.grow_amount = 0.035
	_collect_silhouette(model)

func _collect_silhouette(source: Node) -> void:
	if source is MeshInstance3D and source.mesh != null:
		var ghost = MeshInstance3D.new()
		ghost.mesh = source.mesh
		ghost.material_override = silhouette_material
		ghost.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		visibility_silhouette.add_child(ghost)
		silhouette_parts.append({"source":source, "ghost":ghost})
	for child in source.get_children(): _collect_silhouette(child)

func set_occlusion_hint(value: bool, delta: float) -> void:
	occlusion_hint = value
	silhouette_strength = move_toward(silhouette_strength, 0.55 if value else 0.0, delta * 4.0)
	if not is_instance_valid(visibility_silhouette): return
	visibility_silhouette.visible = enabled and silhouette_strength > 0.001
	var tint = silhouette_material.albedo_color
	tint.a = silhouette_strength
	silhouette_material.albedo_color = tint

func _sync_searchlight() -> void:
	var wanted = bool(stats.get("modifiers", {}).get("searchlight_enabled", false))
	if wanted and not is_instance_valid(searchlight):
		searchlight = SpotLight3D.new()
		searchlight.name = "Searchlight"
		searchlight.spot_range = 24.0
		searchlight.spot_angle = 38.0
		searchlight.light_energy = 2.0
		searchlight.rotation.x = -0.65
		add_child(searchlight)
	if is_instance_valid(searchlight): searchlight.visible = wanted

func is_landed() -> bool:
	return grounded

func _update_grounded(state: PhysicsDirectBodyState3D, vertical: float) -> bool:
	grounded = false
	var supported = false
	for index in range(state.get_contact_count()):
		var collider = instance_from_id(state.get_contact_collider_id(index))
		if not collider is PhysicsBody3D or (collider.collision_layer & (1|32)) == 0: continue
		# Jolt reports both the contact point and normal in world coordinates.
		var normal = state.get_contact_local_normal(index)
		if normal.y < 0.7: continue
		supported = true
		var relative = state.linear_velocity - state.get_contact_collider_velocity_at_position(index)
		if vertical <= 0.02 and absf(relative.y) < 0.25 and Vector2(relative.x, relative.z).length() < 0.35 and state.transform.basis.y.y > 0.75:
			grounded = true
	return supported

func _refresh_collider() -> void:
	var shape_node = get_node_or_null("Envelope")
	if shape_node == null:
		shape_node = CollisionShape3D.new()
		shape_node.name = "Envelope"
		add_child(shape_node)
	var shape = BoxShape3D.new()
	shape.size = Vector3(float(stats.get("width_m", 1.4)), float(stats.get("height_m", 0.48)), float(stats.get("length_m", 1.4)))
	shape_node.shape = shape

func _find_rotors(node: Node) -> void:
	if str(node.name).begins_with("Rotor") and node is Node3D: rotors.append(node)
	for child in node.get_children(): _find_rotors(child)

func _integrate_forces(state: PhysicsDirectBodyState3D) -> void:
	if not enabled or stats.is_empty():
		grounded = false
		return
	var dt = state.step
	flight_seconds += dt
	shield_left = maxf(0.0, shield_left - dt)
	shield_cooldown = maxf(0.0, shield_cooldown - dt)
	recovery_left = maxf(0.0, recovery_left - dt)
	ability_left = maxf(0.0, ability_left - dt)
	ability_cooldown = maxf(0.0, ability_cooldown - dt)
	var origin = state.transform.origin
	var query = PhysicsRayQueryParameters3D.create(origin, origin + Vector3.DOWN * 100.0, 1 | 32)
	var hit = state.get_space_state().intersect_ray(query)
	ground_y = float(hit.position.y) if not hit.is_empty() else -2.0
	ground_distance = maxf(0.0, origin.y - ground_y)
	var input_active = bool(command.get("active", false))
	var vertical = float(command.get("vertical", 0.0)) if input_active else 0.0
	var brake = (input_active and bool(command.get("brake", false))) or (ability_left > 0.0 and build.get("airframe_id", "") == "ag03")
	var manual = str(command.get("mode", "assisted")) == "manual_throttle"
	var collective = clampf(float(command.get("throttle",0.0)),0.0,1.0)
	var resting = _update_grounded(state, collective-0.02 if manual else vertical) and (collective <= 0.02 if manual else vertical <= 0.02)
	if resting:
		hold_height = origin.y
	elif absf(vertical) > 0.02:
		hold_height = origin.y + vertical * 0.7
	else:
		hold_height = clampf(hold_height, ground_y + float(stats.get("height_m",0.48))*0.5 + 0.18, max_altitude)
	var vertical_target = vertical * (float(stats.rise_mps) if vertical > 0 else float(stats.fall_mps))
	if absf(vertical) <= 0.02: vertical_target = clampf((hold_height - origin.y) * 2.0, -float(stats.fall_mps), float(stats.rise_mps))
	if origin.y > max_altitude: vertical_target = minf(vertical_target, (max_altitude - origin.y) * 2.0)
	var tilt_limit = deg_to_rad(float(stats.tilt_deg))
	var target_accel = Vector3.ZERO
	var local_axes = Vector3(float(command.get("roll",0.0)),0.0,-float(command.get("pitch",0.0))).limit_length(1.0)
	var planar: Vector3 = Basis(Vector3.UP, heading) * local_axes if input_active else Vector3.ZERO
	# Legacy headless drivers can still supply a world-space planar command explicitly.
	if not bool(command.get("body_relative",false)) and not Vector3(command.get("planar",Vector3.ZERO)).is_zero_approx(): planar = command.planar
	if str(command.get("mode", "assisted")) in ["advanced", "manual_throttle"] and not brake:
		var local_intent = Vector3(float(command.get("roll", 0.0)), 0.0, -float(command.get("pitch", 0.0))).limit_length(1.0)
		target_accel = Basis(Vector3.UP, heading) * local_intent * (9.8 * tan(tilt_limit))
		target_accel -= Vector3(state.linear_velocity.x, 0.0, state.linear_velocity.z) * 0.12
	else:
		var target_velocity = Vector3.ZERO if brake else planar * float(stats.speed_mps)
		target_accel = (target_velocity - Vector3(state.linear_velocity.x, 0.0, state.linear_velocity.z)) * 2.0
		var load_ratio = cargo_kg / maxf(0.1, float(stats.get("cargo_rating_kg", 3.0)))
		var limit = float(stats.brake_mps2 if brake or planar.length() < 0.05 else stats.accel_mps2) * (1.0 - 0.30 * clampf(load_ratio, 0.0, 1.0))
		target_accel = target_accel.limit_length(limit)
	target_accel = target_accel.limit_length(9.8 * tan(tilt_limit))
	var target_up = Vector3(target_accel.x, 9.8, target_accel.z).normalized()
	if not component_effects.is_empty():
		target_up=(target_up+Basis(Vector3.UP,heading).x*float(component_effects.get("roll_bias",0.0))*.045).normalized()
	heading -= float(command.get("yaw", 0.0)) * deg_to_rad(float(stats.yaw_deg_s)) * dt if input_active else 0.0
	var heading_forward = Vector3(-sin(heading), 0.0, -cos(heading))
	var target_right = heading_forward.cross(target_up).normalized()
	var target_back = target_right.cross(target_up).normalized()
	var target_basis = Basis(target_right, target_up, target_back).orthonormalized()
	var rotation_error = state.transform.basis.get_rotation_quaternion().inverse() * target_basis.get_rotation_quaternion()
	if rotation_error.w < 0.0: rotation_error = -rotation_error
	var axis = Vector3(rotation_error.x, rotation_error.y, rotation_error.z)
	var world_error = state.transform.basis * axis * 2.0
	var recovery_gain = 0.60 if recovery_left > 0.0 else 1.0
	var response = clampf(0.08 / float(stats.get("modifiers", {}).get("attitude_response_s", 0.08)), 0.65, 1.35)
	response*=float(component_effects.get("stability",1.0))
	var angular_accel = world_error * 28.0 * recovery_gain * response - state.angular_velocity * 7.5
	if ability_left > 0 and build.airframe_id == "tr01": angular_accel = world_error * 40.0 - state.angular_velocity * 10.0
	var inverse_inertia = state.inverse_inertia_tensor
	if absf(inverse_inertia.determinant()) > 0.000001:
		state.apply_torque(inverse_inertia.inverse() * angular_accel)
	var vertical_accel = clampf((vertical_target - state.linear_velocity.y) * 5.0, -7.0, 12.0)
	var loaded_mass = mass + cargo_kg
	var lift = loaded_mass * (9.8 + vertical_accel) / maxf(0.40, state.transform.basis.y.y)
	if manual: lift = collective * float(stats.thrust_n) if input_active else 0.0
	# Ground contact carries the weight until an explicit climb command releases it.
	if resting and not manual: lift = loaded_mass * 9.8 * 0.15
	if origin.y > max_altitude: lift = minf(lift,loaded_mass*9.8*0.8)
	if battery <= 0.0: lift *= 0.72
	lift = clampf(lift, 0.0, float(stats.thrust_n)*float(component_effects.get("thrust",1.0)))
	thrust_fraction = lift / float(stats.thrust_n)
	if not bool(sandbox_rules.get("unlimited_power",false)):
		battery = maxf(0.0,battery-dt*thrust_fraction*0.035*float(component_effects.get("power_use",1.0)))
	state.apply_central_force(state.transform.basis.y * lift)
	state.apply_central_force(mass * environment_acceleration)
	var air: Vector3 = environment_sample.get("wind_velocity",Vector3.ZERO)
	var drag = state.linear_velocity-air
	var density = clampf(float(environment_sample.get("density",1.225)),0.95,1.35)
	state.apply_central_force((-drag * drag.length() * 0.042 * density).limit_length(mass*7.0))
	var touching_water = bool(environment_sample.get("water",false)) and origin.y < float(environment_sample.get("water_height",-0.6))+0.23
	if touching_water:
		if not water_contact: water_entered.emit()
		water_seconds += dt
		state.apply_central_force((-state.linear_velocity*mass*5.0 + Vector3.UP*mass*12.0).limit_length(mass*30.0))
		if water_seconds > 2.5 and environment_hazards_authoritative:
			state.transform.origin = safe_position + Vector3.UP * 1.5
			state.linear_velocity = Vector3.ZERO
			state.angular_velocity = Vector3.ZERO
			hold_height = state.transform.origin.y
			water_seconds = 0.0
			take_damage(12.0)
			rescued.emit()
		elif not environment_hazards_authoritative:
			water_seconds = minf(water_seconds, 2.5)
	else:
		water_seconds = 0.0
		if grounded and origin.y > -0.2: safe_position = origin
	water_contact = touching_water
	for item in cargo_items.values():
		var body: RigidBody3D = item.body
		if not is_instance_valid(body): continue
		var cargo_field: Dictionary = environment_query.call(body.global_position) if environment_query.is_valid() else environment_sample
		var cargo_air = body.linear_velocity-Vector3(cargo_field.get("wind_velocity",air))
		var cargo_density=clampf(float(cargo_field.get("density",density)),0.95,1.35)
		body.apply_central_force((-cargo_air*cargo_air.length()*0.06*cargo_density).limit_length(body.mass*7.0))
		var rope_direction = (body.global_position - origin).normalized()
		var relative_velocity = body.linear_velocity - state.linear_velocity
		var tangent = relative_velocity - rope_direction * relative_velocity.dot(rope_direction)
		var damping = float(stats.get("modifiers", {}).get("cargo_damping_multiplier", 1.0))
		if ability_left > 0 and build.airframe_id == "hx02": damping = 1.6
		var damping_force = (-tangent * body.mass * 1.2 * damping).limit_length(body.mass * 7.0)
		body.apply_central_force(damping_force)
		state.apply_central_force(-damping_force)
	_check_contacts(state)
	last_velocity = state.linear_velocity
	telemetry = {"tick":Engine.get_physics_frames(), "position_m":origin, "velocity_mps":state.linear_velocity, "speed_mps":Vector2(state.linear_velocity.x, state.linear_velocity.z).length(), "altitude_agl_m":ground_distance, "vertical_mps":state.linear_velocity.y, "mass_kg":mass + cargo_kg, "cargo_kg":cargo_kg, "thrust_fraction":thrust_fraction, "health":health, "heat":heat, "swing_deg":cargo_swing(), "grounded":grounded, "brake_active":brake, "environment_acceleration":environment_acceleration, "flight_state":"recovering" if recovery_left > 0.0 else ("landed" if grounded else "flying")}
	telemetry.merge({"heading_deg":fposmod(rad_to_deg(heading),360.0),"throttle":collective,"battery":battery,"airspeed_mps":drag.length(),"wind_velocity":air,"water_contact":touching_water,"nav_quality":environment_sample.get("nav_quality",1.0),"compass_quality":environment_sample.get("compass_quality",1.0)})
	telemetry.merge({"max_health":maximum_health,"armor":damage_state.get("armor",0.0),"max_armor":damage_state.get("maximum_armor",0.0),"rotor_damage":component_effects.get("rotor_damage",0.0),"motor_damage":component_effects.get("motor_damage",0.0),"sensor_damage":component_effects.get("sensor_damage",0.0),"component_status":DamageModel.status_text(damage_state)})

func _check_contacts(state: PhysicsDirectBodyState3D) -> void:
	var now = flight_seconds
	for i in range(state.get_contact_count()):
		var object_id = state.get_contact_collider_id(i)
		if now - float(contact_cooldowns.get(object_id, -10.0)) < 0.7: continue
		var normal = state.get_contact_local_normal(i)
		var relative = last_velocity - state.get_contact_collider_velocity_at_position(i)
		var normal_speed = maxf(0.0, -relative.dot(normal))
		if normal_speed < 1.6: continue
		contact_cooldowns[object_id] = now
		var scrape = normal_speed < relative.length() * 0.5
		var energy = 0.5 * mass * normal_speed * normal_speed
		var amount = clampf((energy - mass * 1.2) * 0.16, 0.0, 45.0)
		if scrape and build.get("slots", {}).get("utility", "") == "reinforced_guard": amount *= 0.65
		collision_count += 1
		recovery_left = clampf(normal_speed * 0.1, 0.15, 1.5)
		var event = {"kind":"scrape" if scrape else ("landing" if normal.y > 0.6 else "frontal"), "point":state.get_contact_local_position(i), "normal":normal, "normal_speed_mps":normal_speed, "estimated_energy_j":energy, "damage":amount}
		collision_event.emit(event)
		var contact_point=state.get_contact_local_position(i)
		apply_combat_hit(amount*collision_damage_scale,normal,contact_point,"collision",{"combat":false})

func _process(delta: float) -> void:
	if not enabled:
		crash_seconds+=delta
		thrust_fraction=move_toward(thrust_fraction,0.0,delta*.9)
		if not crash_reported and crash_seconds>=2.1:
			crash_reported=true
			disabled.emit()
	for i in range(rotors.size()): rotors[i].rotate_y(delta * (28.0 + thrust_fraction * 80.0) * (1.0 if i % 2 == 0 else -1.0) * (1.0 if enabled else maxf(0,1.0-crash_seconds*.6)))
	if is_instance_valid(visibility_silhouette) and visibility_silhouette.visible:
		for part in silhouette_parts:
			if is_instance_valid(part.source): part.ghost.global_transform = part.source.global_transform
	if is_instance_valid(ground_projection):
		ground_projection.global_position = Vector3(global_position.x, ground_y + 0.06, global_position.z)
		ground_projection.visible = enabled

func take_damage(amount: float, direction: Vector3 = Vector3.ZERO) -> void:
	apply_combat_hit(amount,direction,global_position,"collision",{"combat":false})

func _combat_protection(direction: Vector3) -> Dictionary:
	var protection={"invulnerable":practice or bool(sandbox_rules.get("invincible",false)),"shield_multiplier":1.0}
	if shield_left > 0.0:
		var shield = stats.get("modifiers", {})
		var arc_ok = build.airframe_id != "sh05" or direction.is_zero_approx() or (-global_basis.z).angle_to(-direction) <= deg_to_rad(float(shield.get("shield_arc_deg",100.0))*0.5)
		if arc_ok: protection.shield_multiplier=float(shield.get("shield_damage_multiplier",0.45))
	return protection

func preview_combat_hit(amount: float, direction: Vector3, point: Vector3, weapon_type: String="pulse") -> Dictionary:
	# Pure preview for host transactions; no armor, component, impulse or signal writes.
	if not enabled or not is_finite(amount) or amount<=0 or not direction.is_finite() or not point.is_finite() or damage_state.is_empty():return {}
	var candidate = damage_state.duplicate(true)
	candidate.health = health
	return DamageModel.resolve(candidate,amount,to_local(point),global_basis.inverse()*direction,weapon_type,_combat_protection(direction))

func apply_combat_hit(amount: float, direction: Vector3, point: Vector3, weapon_type: String="pulse", context: Dictionary={}) -> Dictionary:
	if not enabled or not is_finite(amount) or amount<=0 or not direction.is_finite() or not point.is_finite():return {}
	if damage_state.is_empty():return {}
	damage_state.health=health
	var receipt=DamageModel.resolve(damage_state,amount,to_local(point),global_basis.inverse()*direction,weapon_type,_combat_protection(direction))
	if receipt.is_empty():return {}
	health=float(receipt.health)
	component_effects=DamageModel.impairment(damage_state)
	var actual=float(receipt.damage)
	damage_taken+=actual
	receipt.merge(context,true)
	receipt["position"]=[point.x,point.y,point.z]
	receipt["direction"]=[direction.x,direction.y,direction.z]
	receipt["pilot_target"]=true
	if actual>0:
		recovery_left=maxf(recovery_left,clampf(actual*.018,.10,.60))
		apply_central_impulse(direction.normalized()*mass*minf(1.1,actual*.035))
		damaged.emit(actual,direction)
	if health <= 0.0:
		enabled = false
		crash_seconds=0.0
		apply_torque_impulse(Vector3(.2,.1,.3)*mass)
		crash_started.emit()
	damage_resolved.emit(receipt.duplicate(true))
	return receipt

func damage_snapshot() -> Dictionary:
	var value=damage_state.duplicate(true)
	value["health"]=health
	value.erase("dimensions")
	return value

func restore_damage_state(value: Dictionary) -> void:
	if value.is_empty():return
	# Restore only matching component schemas; never replace current model dimensions.
	health=clampf(float(value.get("health",health)),0,maximum_health)
	damage_state.health=health
	damage_state.serial=maxi(0,int(value.get("serial",0)))
	if health<=0:
		enabled=false;crash_seconds=0;crash_reported=false
	damage_state.armor=clampf(float(value.get("armor",damage_state.armor)),0,float(damage_state.maximum_armor))
	var parts:Dictionary=value.get("components",{})
	for id in damage_state.components:
		if parts.has(id):damage_state.components[id].health=clampf(float(parts[id].get("health",damage_state.components[id].maximum)),0,float(damage_state.components[id].maximum))
	component_effects=DamageModel.impairment(damage_state)

func activate_guard() -> bool:
	if shield_cooldown > 0.0: return false
	var utility = str(build.get("slots", {}).get("utility", ""))
	if utility != "guard_base" and build.get("airframe_id", "") != "sh05": return false
	shield_left = float(stats.get("modifiers", {}).get("shield_duration_s", 2.0))
	shield_cooldown = float(stats.get("modifiers", {}).get("shield_cooldown_s", 9.0))
	return true

func activate_ability() -> bool:
	if not enabled or ability_cooldown > 0.0: return false
	match str(build.airframe_id):
		"tr01": ability_left = 3.0; ability_cooldown = 10.0
		"hx02": ability_left = 4.0; ability_cooldown = 12.0
		"nx04": ability_left = 20.0; ability_cooldown = 25.0
		"sh05": return activate_guard()
		"at06": ability_left = 2.0; ability_cooldown = 12.0
		"ag03": ability_left = 1.0; ability_cooldown = 8.0
	return true

func attach_cargo(body: RigidBody3D, id: String, weight: float) -> bool:
	if not is_instance_valid(body) or not body.is_inside_tree() or id.is_empty() or not is_finite(weight) or weight <= 0.0: return false
	if cargo_items.has(id): return false
	for item in cargo_items.values():
		if item.body == body: return false
	var checked = CatalogV2.resolve_build(build, cargo_kg + weight)
	if not checked.valid: return false
	cargo_body = body
	cargo_id = id
	cargo_kg += weight
	body.mass = weight
	body.collision_layer = 8
	body.collision_mask = 1|32
	cargo_joint = PinJoint3D.new()
	get_parent().add_child(cargo_joint)
	cargo_joint.global_position = global_position + Vector3.DOWN * 0.65
	cargo_joint.node_a = cargo_joint.get_path_to(self)
	cargo_joint.node_b = cargo_joint.get_path_to(body)
	cargo_items[id] = {"body":body,"joint":cargo_joint,"weight":weight}
	return true

func release_cargo(id: String = "") -> RigidBody3D:
	if id.is_empty(): id = cargo_id
	if not cargo_items.has(id): return null
	var item: Dictionary = cargo_items[id]
	var body: RigidBody3D = item.body
	if is_instance_valid(item.joint): item.joint.queue_free()
	cargo_kg = maxf(0,cargo_kg-float(item.weight))
	cargo_items.erase(id)
	cargo_id = "" if cargo_items.is_empty() else str(cargo_items.keys().back())
	cargo_body = null if cargo_items.is_empty() else cargo_items[cargo_id].body
	cargo_joint = null if cargo_items.is_empty() else cargo_items[cargo_id].joint
	return body

func cargo_swing() -> float:
	var swing = 0.0
	for item in cargo_items.values():
		if is_instance_valid(item.body): swing = maxf(swing,rad_to_deg(Vector3.DOWN.angle_to((item.body.global_position - global_position).normalized())))
	return swing

func _exit_tree() -> void:
	if is_instance_valid(ground_projection): ground_projection.queue_free()
