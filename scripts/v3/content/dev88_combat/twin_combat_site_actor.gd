extends "res://scripts/v2/enemy_actor.gd"
## V2 editable GLBs, dimensions, role HP/armor, component DamageModel and rotors.
## Exactly one Host tick; projected Guests only receive poses and animate meshes.
const SiteBrain = preload("res://scripts/v3/content/dev88_combat/twin_combat_site_brain.gd")
var authoritative := false
var ceasefire_reason := "none"
var neutralized := false
var controlled := false

func _ready() -> void:
	if role not in ["scout", "harasser", "suppressor", "support"]: role = "scout"
	set_meta("ambient_patrol", true)
	set_meta("allow_facility_target", false)
	brain = SiteBrain.new()
	super._ready()
	set_physics_process(false)

func _physics_process(_delta: float) -> void:
	pass

func host_tick(delta: float, reason: String) -> void:
	if not authoritative or dying or neutralized or hp <= 0.0: return
	age += delta
	cooldown = maxf(0.0, cooldown - delta)
	recoil = move_toward(recoil, 0.0, delta * .5)
	ceasefire_reason = reason
	if reason != "none":
		cancel_warning()
		brain.ceasefire()
		velocity = Vector3.ZERO
		_animate(delta)
		return
	var old_target: Variant = attack_target.get_ref() if attack_target != null else null
	if telegraph > 0.0 and not combat.may_attack(self, old_target):
		cancel_warning()
		cooldown = .45
	var intent: Dictionary = brain.step(delta)
	heading = float(intent.heading)
	rotation.y = heading
	if role == "support":
		cancel_warning()
		_repair_ally()
		velocity = Vector3(intent.velocity) * float(component_effects.get("thrust", 1.0))
	elif telegraph > 0.0:
		telegraph = maxf(0.0, telegraph - delta)
		velocity = velocity.move_toward(Vector3.ZERO, 12.0 * delta)
		warning.visible = _visible()
		warning.scale = Vector3.ONE * (1.0 + sin(age * 18.0) * .08)
		_draw_warning()
		if telegraph <= 0.0:
			warning.visible = false
			beam.visible = false
			var target: Variant = attack_target.get_ref() if attack_target != null else null
			if not is_instance_valid(target) or not brain.seen or brain.target != target or not combat.may_attack(self, target) or not combat.projectile_path_clear(global_position, global_position + attack_direction * attack_length, get_rid(), target.get_rid()):
				cooldown = .45
			elif combat.fire_bolt(global_position, global_position + attack_direction * 50.0, 7.0, controlled, self):
				cooldown = 2.0 if role == "scout" else 1.3
			else: cooldown = .45
	else:
		velocity = Vector3(intent.velocity) * float(component_effects.get("thrust", 1.0))
		var target: Variant = intent.get("target")
		if bool(intent.can_attack) and cooldown <= 0.0 and is_instance_valid(target) and combat.may_attack(self, target):
			warning_id = combat.request_warning(self, target)
			if warning_id > 0:
				telegraph = 1.25 if role == "suppressor" else 1.0
				attack_target = weakref(target)
				var difference: Vector3 = Vector3(intent.aim_position) - global_position
				attack_direction = difference.normalized()
				attack_length = difference.length()
				velocity = Vector3.ZERO
				warning.visible = _visible()
				beam.visible = _visible()
				_draw_warning()
	impulse_velocity = impulse_velocity.move_toward(Vector3.ZERO, delta * 3.0)
	velocity += impulse_velocity * delta * 5.0
	if combat.environment_query.is_valid():
		var sample: Dictionary = combat.environment_query.call(global_position)
		velocity += (Vector3(sample.get("wind_velocity", Vector3.ZERO)) - velocity) * .035 * delta
	_move_native(delta)
	_animate(delta)

func _repair_ally() -> void:
	if cooldown > 0.0: return
	for ally: Variant in combat.enemies:
		if not is_instance_valid(ally) or ally == self or ally.hp <= 0.0 or ally.dying or ally.neutralized or ally.controlled != controlled: continue
		if ally.global_position.distance_to(global_position) < 18.0 and combat.line_clear(global_position, ally.global_position, get_rid(), ally.get_rid()):
			var healed: float = minf(7.0, ally.max_hp - ally.hp)
			if healed > 0.0:
				ally.hp += healed
				ally.damage_state.health = ally.hp
				combat.note_repair(self, ally, healed)
	cooldown = 1.5

func _move_native(delta: float) -> void:
	var fraction: float = combat.motion_fraction(self, global_position, velocity * delta)
	velocity *= fraction if fraction >= .999 else maxf(0.0, fraction - .001)
	move_and_slide()

func _draw_warning() -> void:
	beam.global_position = global_position + attack_direction * attack_length * .5
	if absf(attack_direction.dot(Vector3.UP)) < .99: beam.look_at(global_position + attack_direction * attack_length, Vector3.UP)
	beam.scale.z = attack_length

func cancel_warning() -> void:
	telegraph = 0.0
	attack_target = null
	if is_instance_valid(warning): warning.visible = false
	if is_instance_valid(beam): beam.visible = false

func apply_combat_hit(amount: float, direction: Vector3, point: Vector3, weapon_type = "pulse", context: Dictionary = {}) -> Dictionary:
	if not authoritative or not combat.settlement_active_for(self): return {}
	return super.apply_combat_hit(amount, direction, point, weapon_type, context)

func finish_destroyed(source: Node, receipt: Dictionary) -> void:
	if dying or neutralized: return
	dying = true
	cancel_warning()
	velocity = Vector3.ZERO
	collision_layer = 0
	collision_mask = 0
	visible = false
	combat.actor_disabled(self, source, receipt, false)

func stop_by_ability() -> void:
	if dying or neutralized: return
	neutralized = true
	cancel_warning()
	velocity = Vector3.ZERO
	collision_layer = 0
	collision_mask = 0
	visible = false
	combat.actor_disabled(self, null, {}, true)

func present_tick(delta: float) -> void:
	if not authoritative and not dying and not neutralized: _animate(delta)
