class_name PlayerDrone
extends CharacterBody3D

var world
var router: FlightInput
var loadout: Dictionary
var enabled = false
var health = 100.0
var maximum_health = 100.0
var heat = 0.0
var overheated = false
var shield_left = 0.0
var shield_cooldown = 0.0
var shot_cooldown = 0.0
var collision_cooldown = 0.0
var collision_count = 0
var damage_taken = 0.0
var model: Node3D
var shield_visual: MeshInstance3D
var target = null
var heading = 0.0
var auto_fire = false
var flight_time = 0.0
var invulnerability=0.0
var target_scan=0.0

func _ready() -> void:
	collision_layer = 2
	collision_mask = 1
	motion_mode = CharacterBody3D.MOTION_MODE_FLOATING
	var col = CollisionShape3D.new()
	var shape = SphereShape3D.new()
	shape.radius = 0.67
	col.shape = shape
	add_child(col)
	model = GameVisuals.asset(self, "player")
	GameVisuals.asset(model, "module_" + loadout.weapon, Vector3(0,-0.28,-0.12))
	GameVisuals.asset(model, "module_" + loadout.utility, Vector3(0,0.25,0.2))
	if loadout.drive == "agile":
		GameVisuals.asset(model, "module_agile", Vector3.ZERO)
	shield_visual = GameVisuals.sphere(self, Vector3.ZERO, 1.2, Color(0.25,0.85,0.92,0.15))
	shield_visual.visible = false

func _physics_process(delta: float) -> void:
	GameVisuals.rotors(model,delta)
	shield_visual.visible = shield_left > 0
	if not enabled: return
	flight_time += delta
	var drive = GameData.MODULES[loadout.drive]
	var input = router.movement()
	var desired = world.flight_direction(input) * float(drive.speed)
	var braking = router.held("brake")
	if braking: desired *= 0.18
	var accel = float(drive.brake) if braking else float(drive.accel)
	velocity.x = move_toward(velocity.x,desired.x,accel*delta)
	velocity.z = move_toward(velocity.z,desired.z,accel*delta)
	var height = 1.65 if router.layer == 0 else 4.1
	velocity.y = clampf((height-position.y)*5.0,-4.0,4.0)
	var speed_before = velocity.length()
	move_and_slide()
	position.x = clampf(position.x,world.flight_bounds.position.x+1,world.flight_bounds.end.x-1)
	position.z = clampf(position.z,world.flight_bounds.position.y+1,world.flight_bounds.end.y-1)
	if get_slide_collision_count() > 0 and speed_before > 4 and collision_cooldown <= 0:
		collision_count += 1
		take_damage(4.0)
		collision_cooldown = 1.0
		world.toast("碰撞：提前按 %s 制动，或切换高航层越障"%router.binding_label("brake"))
	model.rotation.z = lerpf(model.rotation.z,-velocity.x*0.023,8*delta)
	model.rotation.x = lerpf(model.rotation.x,velocity.z*0.023,8*delta)
	target_scan-=delta
	if router.pressed("target"): target = world.find_target(self, target, true)
	elif target_scan<=0:
		target=world.find_target(self,target,false)
		target_scan=.12
	if is_instance_valid(target):
		var direction = target.global_position-global_position
		heading = atan2(-direction.x,-direction.z)
	elif Vector2(velocity.x,velocity.z).length() > 0.4:
		heading = atan2(-velocity.x,-velocity.z)
	model.rotation.y = lerp_angle(model.rotation.y,heading,delta*10)
	shot_cooldown -= delta
	invulnerability=maxf(0,invulnerability-delta)
	collision_cooldown -= delta
	shield_cooldown = maxf(0,shield_cooldown-delta)
	shield_left = maxf(0,shield_left-delta)
	heat = maxf(0,heat-delta*(24 if loadout.utility == "cooler" else 14))
	if overheated and heat < 30: overheated = false
	if router.pressed("utility") and loadout.utility == "shield" and shield_cooldown <= 0:
		shield_left = 2.4
		shield_cooldown = 14.0
		world.sound("shield")
	if (router.held("fire") or auto_fire) and shot_cooldown <= 0 and not overheated and is_instance_valid(target):
		var weapon = GameData.MODULES[loadout.weapon]
		var from = global_position + Vector3(0,-0.08,0)
		var aim=target.global_position
		if target is CharacterBody3D:aim+=target.velocity*minf(.3,global_position.distance_to(aim)/48.0)
		world.fire_shot(from,aim,weapon.damage,true,loadout.weapon == "charge")
		shot_cooldown = weapon.rate
		heat = minf(100,heat+float(weapon.heat))
		if heat >= 99: overheated = true
		world.sound("shot", -7 if loadout.weapon == "pulse" else -3)

func take_damage(amount: float) -> void:
	if world.practice_mode:return
	if not enabled or shield_left > 0 or invulnerability>0: return
	invulnerability=.32
	var final_damage = amount * float(GameData.DIFFICULTY[world.difficulty].damage)
	health = maxf(0, health-final_damage)
	damage_taken += final_damage
	world.effect(global_position,Color("e89866"),0.5)
	world.sound("hit")
	if health <= 0:
		enabled = false
		world.finish_mission(false)
