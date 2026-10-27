extends "res://scripts/v2/enemy_actor.gd"
## Original mesh, imported bounds, shape, HP32/armor5, DamageModel and animation.
## No auto physics callback: one Host.advance owns all ordinary native ticks.
const PatrolBrain=preload("res://scripts/v3/gameplay/twin_f2_patrol_brain.gd")
var authoritative := false
var ceasefire_reason := "none"

func _ready() -> void:
	role="scout"
	set_meta("ambient_patrol",true)
	set_meta("allow_facility_target",false)
	brain=PatrolBrain.new()
	super._ready()
	set_physics_process(false)

func _physics_process(_delta: float) -> void:
	pass # Fail closed if somebody accidentally enables the legacy auto callback.

func host_tick(delta: float, reason: String) -> void:
	if not authoritative or dying or hp<=0.0: return
	age+=delta
	cooldown=maxf(0.0,cooldown-delta)
	recoil=move_toward(recoil,0,delta*.5)
	ceasefire_reason=reason
	if reason!="none":
		cancel_warning()
		brain.ceasefire()
		velocity=velocity.move_toward(Vector3.ZERO,float(brain.profile.accel)*delta)
		_move_native(delta)
		_animate(delta)
		return
	var old_target: Variant=attack_target.get_ref() if attack_target!=null else null
	if telegraph>0.0 and not combat.may_target(old_target):
		cancel_warning()
		cooldown=.45
	var intent: Dictionary=brain.step(delta)
	heading=float(intent.heading)
	rotation.y=heading
	if str(intent.state)!=_last_state:
		combat.record_transition(_last_state,str(intent.state))
		_last_state=str(intent.state)
	if bool(intent.get("report_ready",false)):
		combat.record_observation(intent) # Read-only local telemetry; no mission event.
	if telegraph>0.0:
		telegraph=maxf(0.0,telegraph-delta)
		velocity=velocity.move_toward(Vector3.ZERO,12.0*delta)
		warning.visible=_visible()
		warning.scale=Vector3.ONE*(1.0+sin(age*18.0)*.08)
		_draw_warning()
		if telegraph<=0.0:
			warning.visible=false; beam.visible=false
			var target: Variant=attack_target.get_ref() if attack_target!=null else null
			if not is_instance_valid(target) or not brain.seen or brain.target!=target or not combat.may_target(target) or not combat.projectile_path_clear(global_position,global_position+attack_direction*attack_length,get_rid(),target.get_rid()):
				cooldown=.45 # Original lost-LOS cancellation.
			elif combat.fire_bolt(global_position,global_position+attack_direction*50.0,7.0,false,self):
				cooldown=2.0 # Original scout, default beginner difficulty0.
			else:
				cooldown=.45 # Safety rejection cancels; never .1s warning spam.
	else:
		velocity=Vector3(intent.velocity)*float(component_effects.get("thrust",1.0))
		var target: Variant=intent.get("target")
		if bool(intent.can_attack) and cooldown<=0.0 and is_instance_valid(target):
			warning_id=combat.request_warning(self,target)
			if warning_id>0:
				telegraph=1.0 # Original scout telegraph, not a new balance value.
				attack_target=weakref(target)
				var difference: Vector3=Vector3(intent.aim_position)-global_position
				attack_direction=difference.normalized()
				attack_length=difference.length()
				velocity=Vector3.ZERO
				warning.visible=_visible(); beam.visible=_visible()
				_draw_warning()
	impulse_velocity=impulse_velocity.move_toward(Vector3.ZERO,delta*3.0)
	velocity+=impulse_velocity*delta*5.0
	if combat.environment_query.is_valid():
		var sample: Dictionary=combat.environment_query.call(global_position)
		velocity+=(Vector3(sample.get("wind_velocity",Vector3.ZERO))-velocity)*.035*delta
	_move_native(delta)
	_animate(delta)

func _move_native(delta: float) -> void:
	# Local avoidance is advisory. The final actual shape sweep includes drift,
	# recoil and protected columns, followed by real CharacterBody collision.
	var fraction: float=combat.motion_fraction(self,global_position,velocity*delta)
	velocity*=fraction if fraction>=.999 else maxf(0.0,fraction-.001)
	move_and_slide()

func _draw_warning() -> void:
	beam.global_position=global_position+attack_direction*attack_length*.5
	if absf(attack_direction.dot(Vector3.UP))<.99: beam.look_at(global_position+attack_direction*attack_length,Vector3.UP)
	beam.scale.z=attack_length

func cancel_warning() -> void:
	telegraph=0.0
	attack_target=null
	if is_instance_valid(warning): warning.visible=false
	if is_instance_valid(beam): beam.visible=false

func apply_combat_hit(amount: float,direction: Vector3,point: Vector3,weapon_type="pulse",context: Dictionary={}) -> Dictionary:
	if not authoritative or not combat.settlement_active_for(self): return {}
	return super.apply_combat_hit(amount,direction,point,weapon_type,context)

func finish_destroyed(source: Node,receipt: Dictionary) -> void:
	if dying: return
	dying=true
	cancel_warning()
	velocity=Vector3.ZERO
	collision_layer=0; collision_mask=0
	visible=false
	set_physics_process(false)
	combat.scout_disabled(source,receipt)
	# Keep one tombstone until visit teardown so late joins cannot resurrect it.
	# No V2 kills/enemy_down, no Story/discovery/reward, no second save.

func present_tick(delta: float) -> void:
	if not authoritative and not dying: _animate(delta) # Pure mesh feedback only.
