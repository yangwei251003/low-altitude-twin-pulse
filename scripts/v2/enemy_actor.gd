class_name EnemyActorV22
extends CharacterBody3D
## Physics/weapon owner; perception and intent are owned by EnemyBrainV22.
const Brain = preload("res://scripts/v2/enemy_brain.gd")
const DamageModel = preload("res://scripts/v2/damage_model.gd")
var role="shooter"
var hp=48.0
var max_hp=48.0
var combat:Node3D
var home=Vector3.ZERO
var cooldown=.8
var telegraph=0.0
var attack_direction=Vector3.ZERO
var charge_left=0.0
var age=0.0
var exposure_left=0.0
var model:Node3D
var warning:MeshInstance3D
var beam:MeshInstance3D
var shield:MeshInstance3D
var model_size=1.0
var warning_id=0
var brain=Brain.new()
var damage_state:Dictionary={}
var component_effects:Dictionary={}
var dimensions=Vector3(1.8,.65,1.8)
var damage_origin=Vector3.ZERO
var heading=0.0
var previous_velocity=Vector3.ZERO
var recoil=0.0
var impulse_velocity=Vector3.ZERO
var attack_target:WeakRef
var attack_length=20.0
var dying=false
var _last_state=""
var _rotors:Array[Node3D]=[]

func _ready() -> void:
	collision_layer=4;collision_mask=1|2|4|8|32
	motion_mode=CharacterBody3D.MOTION_MODE_FLOATING
	max_slides=4
	var style={"shooter":"harasser","charger":"harasser","boss":"suppressor"}.get(role,role)
	var widths={"scout":1.6,"harasser":1.8,"suppressor":2.2,"support":1.9}
	dimensions=Vector3(float(widths.get(style,1.8)),.65,float(widths.get(style,1.8)))
	var path="res://assets/models/v22_combat/enemy_"+str(style)+".glb"
	if ResourceLoader.exists(path):model=load(path).instantiate();add_child(model)
	else:model=GameVisuals.asset(self,"enemy_repair" if role=="support" else ("enemy_charger" if role=="charger" else "enemy_patrol"),Vector3.ZERO,.8)
	StreetDressingV2._enable_vertex_colors(model)
	var bounds=AABB();var first=true
	for mesh in model.find_children("*","MeshInstance3D",true,false):
		var box_bounds:AABB=(global_transform.affine_inverse()*mesh.global_transform)*mesh.get_aabb()
		bounds=box_bounds if first else bounds.merge(box_bounds);first=false
	if not first:
		dimensions=bounds.size;damage_origin=bounds.get_center()
	var shape=CollisionShape3D.new();var box=BoxShape3D.new();box.size=dimensions
	shape.shape=box;shape.position=damage_origin;add_child(shape)
	max_hp=float({"boss":96,"support":64,"charger":38,"scout":32,"suppressor":76,"harasser":42}.get(role,48))
	hp=max_hp
	var armor=float({"boss":24,"support":14,"charger":6,"scout":5,"suppressor":22,"harasser":8}.get(role,10))
	damage_state=DamageModel.create_state(max_hp,armor,dimensions)
	component_effects=DamageModel.impairment(damage_state)
	warning=GameVisuals.ring(self,Vector3(0,.35,0),1.5 if role=="boss" else 1.2,Color("ffc574"),.065)
	warning.visible=false
	beam=GameVisuals.box(self,Vector3.ZERO,Vector3(.035,.035,1),Color("e8a65d"));beam.visible=false
	beam.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if role=="boss":shield=GameVisuals.ring(self,Vector3.ZERO,1.8,Color("5cbbdc"),.10)
	var ambient=bool(get_meta("ambient_patrol",false))
	# A mission group receives an initial approach bearing, not ongoing target GPS.
	if not ambient and is_instance_valid(combat.pilot):
		var initial_goal:Vector3=combat.facility.global_position if is_instance_valid(combat.facility) and bool(get_meta("allow_facility_target",true)) else combat.pilot.global_position
		var facing=initial_goal-global_position
		rotation.y=atan2(-facing.x,-facing.z)
	heading=rotation.y
	brain.configure(self,role,int(combat.combat_seed)+int(combat.unit_sequence)*7919,ambient)
	brain.navigation_world=combat.navigation_world
	brain.perception_visibility=combat.perception_visibility
	_collect_rotors(model)
	sync_render_visibility()

func _collect_rotors(node:Node) -> void:
	if node is Node3D and str(node.name).begins_with("Rotor"):_rotors.append(node)
	for child in node.get_children():_collect_rotors(child)

func can_take_damage() -> bool:
	return role!="boss" or exposure_left>0.0

func apply_combat_hit(amount:float,direction:Vector3,point:Vector3,weapon_type="pulse",_context:Dictionary={}) -> Dictionary:
	if hp<=0 or dying:return {}
	damage_state.health=hp
	var receipt=DamageModel.resolve(damage_state,amount,to_local(point)-damage_origin,global_basis.inverse()*direction,weapon_type,{"invulnerable":not can_take_damage()})
	if receipt.is_empty():return {}
	hp=float(receipt.health);component_effects=DamageModel.impairment(damage_state)
	if float(receipt.damage)>0:
		impulse_velocity+=direction.normalized()*minf(1.4,float(receipt.damage)*.05)
		recoil=minf(.12,recoil+float(receipt.damage)*.004)
	return receipt

func take_damage(amount:float,direction:Vector3=Vector3.ZERO) -> void:
	# Legacy/environment callers share the same settlement; no second fake damage.
	if not is_instance_valid(combat):return
	combat.settle_hit(combat.pilot,self,global_position,direction,amount,"collision")

func damage_snapshot() -> Dictionary:
	var value=damage_state.duplicate(true)
	value.health=hp;value.erase("dimensions")
	return value

func restore_damage_state(value:Dictionary) -> void:
	hp=clampf(float(value.get("health",hp)),0,max_hp);damage_state.health=hp
	damage_state.serial=maxi(0,int(value.get("serial",0)))
	damage_state.armor=clampf(float(value.get("armor",damage_state.armor)),0,float(damage_state.maximum_armor))
	var parts:Dictionary=value.get("components",{})
	for id in damage_state.components:
		if parts.has(id):damage_state.components[id].health=clampf(float(parts[id].get("health",damage_state.components[id].maximum)),0,float(damage_state.components[id].maximum))
	component_effects=DamageModel.impairment(damage_state)

func finish_destroyed(source:Node,receipt:Dictionary) -> void:
	if dying:return
	dying=true
	var details=receipt.duplicate(true)
	details.merge({"role":role,"velocity":[velocity.x,velocity.y,velocity.z],"heading":rotation.y,"friendly":false,"killed":true},true)
	combat._record("destroyed",source,self,global_position,float(receipt.get("damage",0)),0,warning_id,"destroyed",details)
	combat.kills+=1;combat.enemy_down.emit(role)
	collision_layer=0;collision_mask=0;visible=false
	set_physics_process(false)
	queue_free()

func _physics_process(delta:float) -> void:
	if not is_instance_valid(combat) or not is_instance_valid(combat.pilot) or not combat.pilot.enabled or hp<=0:return
	age+=delta;cooldown=maxf(0,cooldown-delta);exposure_left=maxf(0,exposure_left-delta)
	recoil=move_toward(recoil,0,delta*.5)
	if is_instance_valid(shield):shield.visible=exposure_left<=0 and _visible()
	var intent:Dictionary=brain.step(delta)
	heading=float(intent.heading)
	rotation.y=heading
	var state=str(intent.state)
	if state!=_last_state:
		combat._record("ai_state",self,null,global_position,0,0,0,state,{"state":state,"previous_state":_last_state,"ambient":bool(get_meta("ambient_patrol",false))})
		_last_state=state
	if bool(intent.get("report_ready",false)):
		var point:Vector3=intent.get("report_position",global_position)
		combat._record("enemy_report",self,null,point,0,0,0,"report",{"confidence":intent.get("confidence",0),"reported_position":[point.x,point.y,point.z]})
	if role=="support":
		_support_heal()
		telegraph=0;beam.visible=false
	elif charge_left>0:
		charge_left=maxf(0,charge_left-delta)
		velocity=velocity.move_toward(attack_direction*16.0,24.0*delta)
		var hit=move_and_collide(velocity*delta)
		if hit:
			var collider=hit.get_collider()
			if collider is Node and collider!=self and not collider.has_method("finish_destroyed"):
				combat.settle_hit(self,collider,hit.get_position(),attack_direction,17.0,"kinetic",warning_id)
			charge_left=0;cooldown=2.0;velocity=Vector3.ZERO
		_animate(delta)
		return
	elif telegraph>0:
		telegraph-=delta
		velocity=velocity.move_toward(Vector3.ZERO,12.0*delta)
		warning.visible=_visible()
		warning.scale=Vector3.ONE*(1.0+sin(age*18)*.08)
		# Parent heading may keep turning; the warning must remain on the locked
		# world-space firing vector instead of rotating away from the actual bolt.
		beam.global_position=global_position+attack_direction*attack_length*.5
		if absf(attack_direction.dot(Vector3.UP))<.99:beam.look_at(global_position+attack_direction*attack_length,Vector3.UP)
		beam.scale.z=attack_length
		if telegraph<=0:
			warning.visible=false;beam.visible=false
			var target=attack_target.get_ref() if attack_target!=null else null
			if not is_instance_valid(target) or not brain.seen or brain.target!=target or not combat.line_clear(global_position,global_position+attack_direction*attack_length,get_rid(),target.get_rid()):
				cooldown=.45
			elif role=="charger":charge_left=1.2
			elif not combat.fire_bolt(global_position,global_position+attack_direction*50,7.0 if combat.difficulty==0 else 11.0,false,self):
				telegraph=.10;warning.visible=_visible();beam.visible=_visible()
			if role=="boss":exposure_left=combat.exposure_window_s;cooldown=exposure_left+.4
			elif telegraph<=0:cooldown=2.2 if role=="charger" else (2.0 if role=="scout" else 1.3)
	else:
		var target=intent.get("target")
		velocity=Vector3.ZERO if role=="boss" and exposure_left>0 else Vector3(intent.velocity)*float(component_effects.get("thrust",1.0))
		if bool(intent.can_attack) and cooldown<=0 and is_instance_valid(target):
			warning_id=combat.request_warning(self,target)
			if warning_id>0:
				telegraph=1.25 if role in ["charger","suppressor","boss"] else 1.0
				attack_target=weakref(target)
				var difference:Vector3=Vector3(intent.aim_position)-global_position
				attack_direction=difference.normalized()
				attack_length=difference.length()
				velocity=Vector3.ZERO
				beam.visible=_visible();warning.visible=_visible()
				beam.global_position=global_position+difference*.5
				beam.scale.z=difference.length()
				if absf(attack_direction.dot(Vector3.UP))<.99:beam.look_at(global_position+difference,Vector3.UP)
	impulse_velocity=impulse_velocity.move_toward(Vector3.ZERO,delta*3)
	velocity+=impulse_velocity*delta*5
	if combat.environment_query.is_valid():
		var sample:Dictionary=combat.environment_query.call(global_position)
		var air:Vector3=sample.get("wind_velocity",Vector3.ZERO)
		velocity+=(air-velocity)*.035*delta
	move_and_slide()
	_animate(delta)

func _support_heal() -> void:
	warning.visible=false
	if cooldown>0:return
	for ally in combat.enemies:
		if not is_instance_valid(ally) or ally==self or ally.hp<=0 or ally.role=="boss":continue
		if ally.global_position.distance_to(global_position)<18 and combat.line_clear(global_position,ally.global_position,get_rid(),ally.get_rid()):
			var healed=minf(7.0,ally.max_hp-ally.hp)
			if healed>0:
				ally.hp+=healed
				ally.damage_state.health=ally.hp
				combat._record("repair",self,ally,ally.global_position,0,0,0,"repair",{"healed":healed,"health":ally.hp,"max_health":ally.max_hp})
	cooldown=1.5

func _animate(delta:float) -> void:
	var accel=(velocity-previous_velocity)/maxf(.001,delta)
	previous_velocity=velocity
	var local=global_basis.inverse()*accel
	model.rotation.x=lerpf(model.rotation.x,clampf(-local.z*.025,-.30,.30)-recoil,1.0-exp(-delta*8))
	model.rotation.z=lerpf(model.rotation.z,clampf(-local.x*.025,-.30,.30),1.0-exp(-delta*8))
	for i in _rotors.size():_rotors[i].rotate_y(delta*(60+velocity.length()*4)*(1 if i%2==0 else -1))
	sync_render_visibility()

func sync_render_visibility() -> void:
	var revealed=hp>0 and not dying and _visible()
	if is_instance_valid(model):model.visible=revealed
	if is_instance_valid(shield):shield.visible=revealed and exposure_left<=0
	if not revealed:
		if is_instance_valid(warning):warning.visible=false
		if is_instance_valid(beam):beam.visible=false

func _visible() -> bool:
	return not combat.target_visibility.is_valid() or bool(combat.target_visibility.call(global_position))
