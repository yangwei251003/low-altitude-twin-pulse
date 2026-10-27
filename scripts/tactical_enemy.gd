extends DroneEnemy

var path=PackedVector2Array()
var path_clock=0.0
var path_index=0
var turn_sign=1.0
var shot_serial=0
var support_target=null
var active=false

func _ready() -> void:
	super._ready()
	turn_sign=1.0 if encounter_id%2==0 else -1.0
	path_clock=float(encounter_id%11)*.07

func _physics_process(delta: float) -> void:
	if dead or not world.in_flight or not is_instance_valid(world.player):return
	var pilot=world.player
	var distance=global_position.distance_to(pilot.global_position)
	if distance>38 and not active:return
	active=true
	GameVisuals.rotors(model,delta)
	if kind=="node":return
	clock-=delta
	if kind=="boss":
		# The encounter belongs to the maintenance yard. Retreating to a supply
		# point must not leave artillery following the pilot across the entire map.
		if distance>30:
			clock=maxf(clock,.6)
			return
		_boss_logic(delta);return
	var offset=pilot.position-position
	model.rotation.y=lerp_angle(model.rotation.y,atan2(-offset.x,-offset.z),1-exp(-delta*5))
	if kind=="repair":_support(delta)
	if state=="recover":
		_move_tactically(delta)
		if clock<=0 and distance<21 and world.has_line(self,pilot) and world.can_attack(self):
			state="warn"
			clock=(1.10 if kind!="charger" else 1.35)*float(GameData.DIFFICULTY[world.difficulty].telegraph)
			var lead=float(GameData.DIFFICULTY[world.difficulty].lead)
			committed=pilot.position+pilot.velocity*lead
			world.enemy_warning(self,committed,clock)
			if kind!="charger":world.beam(global_position,committed,Color(1,.54,.26,.5),clock,.028)
	elif state=="warn":
		velocity=velocity.move_toward(Vector3.ZERO,delta*16)
		if clock<=0:
			if kind=="charger":
				state="charge";velocity=(committed-position).normalized()*19.0;clock=.85
			else:
				shot_serial+=1
				world.fire_shot(position,committed,12,false,false)
				if kind=="patrol" and world.difficulty>0:
					var side=(committed-position).normalized().cross(Vector3.UP)*1.5
					world.fire_shot(position,committed+side,10,false,false)
					if world.difficulty==2:world.fire_shot(position,committed-side,10,false,false)
				state="recover";clock=2.2*float(GameData.DIFFICULTY[world.difficulty].recovery)
	elif state=="charge":
		move_and_slide()
		if pilot.position.distance_to(position)<1.6:
			pilot.take_damage(20);clock=0
		if clock<=0 or get_slide_collision_count()>0:
			state="recover";clock=2.5*float(GameData.DIFFICULTY[world.difficulty].recovery)
	position.x=clampf(position.x,world.flight_bounds.position.x+1,world.flight_bounds.end.x-1)
	position.z=clampf(position.z,world.flight_bounds.position.y+1,world.flight_bounds.end.y-1)

func _move_tactically(delta: float) -> void:
	var pilot=world.player
	var toward=pilot.position-position;toward.y=0
	var desired_distance=10.5 if kind=="patrol" else (14.0 if kind=="repair" else 7.0)
	var direction=toward.normalized()
	var flank=Vector3(-direction.z,0,direction.x)*turn_sign
	var goal=pilot.position-direction*desired_distance+flank*4.0
	if kind=="repair" and is_instance_valid(support_target):
		goal=support_target.position-direction*4.0
	path_clock-=delta
	if path_clock<=0:
		path_clock=.85+float(encounter_id%7)*.08
		path=world.navigation.path(position,goal);path_index=1 if path.size()>1 else 0
	var travel=goal-position;travel.y=0
	if path_index<path.size():
		travel=Vector3(path[path_index].x-position.x,0,path[path_index].y-position.z)
		if travel.length()<1.8:path_index+=1
	var steering=travel.normalized()
	var desired_speed=3.2 if kind=="patrol" else (2.7 if kind=="repair" else 4.2)
	if toward.length()<desired_distance*.75:steering=-direction
	# Sweep several short directions; choose progress without a building collision.
	var best=steering;var best_score=-INF
	for angle in [0.0,.55,-.55,1.1,-1.1,1.8,-1.8,PI]:
		var candidate=steering.rotated(Vector3.UP,angle)
		var query=PhysicsRayQueryParameters3D.create(position,position+candidate*3.0,1)
		var hit=get_world_3d().direct_space_state.intersect_ray(query)
		var score=candidate.dot(steering)-(3.0 if not hit.is_empty() else 0.0)
		if score>best_score:best_score=score;best=candidate
	var separation=Vector3.ZERO
	for other in world.enemies:
		if is_instance_valid(other) and other!=self and not other.dead:
			var away=position-other.position;away.y=0
			if away.length_squared()<7.8:separation+=away.normalized()*(2.8-away.length())
	var desired=(best+separation*.75).limit_length(1.0)*desired_speed
	if travel.length()<1.0:desired*=.25
	velocity=velocity.move_toward(desired,delta*6.5)
	var altitude=pilot.position.y
	if best_score<0:altitude=4.1
	velocity.y=clampf((altitude-position.y)*2,-2.5,2.5)
	move_and_slide()

func _support(delta: float) -> void:
	healing_clock-=delta
	if healing_clock>0:return
	healing_clock=1.6
	support_target=null
	var need=0.0
	for other in world.enemies:
		if not is_instance_valid(other) or other==self or other.dead or other.kind in ["boss","node"]:continue
		if other.position.distance_to(position)>13 or not world.has_line(self,other):continue
		var missing=other.maximum_health-other.health
		if missing>need:need=missing;support_target=other
	if is_instance_valid(support_target):
		support_target.health=minf(support_target.maximum_health,support_target.health+9)
		world.beam(position,support_target.position,Color("86dca6"),.65,.09)
		world.effect(support_target.position,Color("86dca6"),.8)

func _boss_logic(_delta: float) -> void:
	if phase==1 and health<maximum_health*.66:
		phase=2
		world.toast("护盾协议：击破左右节点，解除核心保护！")
		for offset in [Vector3(-4.8,.7,0),Vector3(4.8,.7,0)]:shield_nodes.append(world.spawn_enemy("node",position+offset))
	if phase==2:
		var alive=false
		for node in shield_nodes:
			if is_instance_valid(node) and not node.dead:alive=true
		if not alive:phase=3;clock=2.0;world.toast("核心暴露：冲击波要升高跨越，导弹预警要横向躲开。")
	if clock>0:return
	var settings=GameData.DIFFICULTY[world.difficulty]
	if state=="recover":
		state="warn";cycle+=1
		clock=1.65*float(settings.telegraph)
		committed=world.player.position+world.player.velocity*float(settings.lead)
		world.danger_zone(committed,2.6 if phase<3 else 3.0,clock,19)
		if phase==3 or world.difficulty==2:
			world.danger_zone(committed+Vector3(4.6,0,0),2.3,clock+.55,16)
		if cycle%3==0:
			# Low-layer radial pulses are visibly announced and can be overflown.
			world.toast("蜂巢低空冲击波：E 升高，或利用掩体阻挡")
			world.effect(position+Vector3(0,-.6,0),Color("eab071"),3.0)
	else:
		state="recover";clock=(2.8 if phase<3 else 2.15)*float(settings.recovery)
		var spread=2 if world.difficulty==2 else 1
		for i in range(-spread,spread+1):world.fire_shot(position,committed+Vector3(i*2.3,0,0),13,false,false)
		if cycle%3==0:
			for i in range(16):
				var angle=TAU*i/16
				var origin=Vector3(position.x,1.45,position.z)
				world.fire_shot(origin,origin+Vector3(cos(angle),0,sin(angle))*20,12,false,false)
		if phase==2 and cycle%4==0 and world.live_enemy_count()<6:
			world.spawn_enemy("charger",position+Vector3(-7,.4,6))

func take_damage(amount: float) -> void:
	if dead:return
	active=true
	if kind=="boss" and state=="recover" and phase==3:amount*=1.2
	world.particles(global_position,Color("f4bd76"),5)
	super.take_damage(amount)
