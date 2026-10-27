class_name EnemyBrainV22
extends RefCounted
## Intent only. The owner moves the CharacterBody, owns attack telegraphs and
## resolves physical hits. Perception memory never receives director/player GPS.

const PROFILES = {
	"scout":{"speed":4.6,"accel":3.6,"yaw":1.6,"range":42.0,"fov":75.0,"reaction":.95,"stand":20.0,"error":1.4},
	"harasser":{"speed":5.2,"accel":4.8,"yaw":2.0,"range":32.0,"fov":60.0,"reaction":.65,"stand":12.0,"error":1.0},
	"suppressor":{"speed":2.6,"accel":2.3,"yaw":1.0,"range":36.0,"fov":65.0,"reaction":.85,"stand":20.0,"error":.8},
	"support":{"speed":3.5,"accel":3.0,"yaw":1.3,"range":30.0,"fov":65.0,"reaction":.9,"stand":23.0,"error":1.5}
}
const MEMORY_SECONDS = 8.0
const MIN_ALTITUDE = 2.8
const MAX_ALTITUDE = 30.0
var body: CharacterBody3D
var combat: Node3D
var navigation_world: Node3D
# Optional illumination permission; still followed by physical LOS and FOV.
var perception_visibility: Callable
var role = "shooter"
var profile: Dictionary
var ambient = false
var state = "patrol"
var heading = 0.0
var desired_velocity = Vector3.ZERO
var last_seen_position = Vector3.ZERO
var last_seen_velocity = Vector3.ZERO
var memory_age = 999.0
var confidence = 0.0
var seen = false
var target: CollisionObject3D
var patrol_target = Vector3.ZERO
var home = Vector3.ZERO
var time_s = 0.0
var reaction_time = 0.0
var report_progress = 0.0
var reported = false
var _rng = RandomNumberGenerator.new()
var _sense_left = 0.0
var _aim_left = 0.0
var _aim_error = Vector3.ZERO
var _noise_position = Vector3.ZERO
var _noise_left = 0.0
var _lost_left = 0.0
var _flank_side = 1.0
var _avoid_left = 0.0
var _avoid_direction = Vector3.ZERO
var _path_left = 0.0
var _path: PackedVector3Array = []
var _path_goal = Vector3.INF
var _grids: Dictionary = {}
var _report_pulse = false
var _objective_position = Vector3.INF
var _objective_ref: WeakRef
var _configured = false

func configure(subject: CharacterBody3D, archetype: String, seed_value: int, is_ambient = false) -> void:
	body=subject;role=archetype;ambient=is_ambient
	combat=body.get("combat")
	var key={"shooter":"harasser","charger":"harasser","boss":"suppressor"}.get(role,role)
	profile=PROFILES.get(key,PROFILES.harasser).duplicate()
	_rng.seed=seed_value;_flank_side=-1.0 if _rng.randf()<.5 else 1.0
	home=body.global_position;patrol_target=home+Vector3(0,0,-14)
	heading=body.rotation.y;_sense_left=_rng.randf_range(0,.10)
	# Mission facility coordinates are an assigned objective, not a moving GPS feed.
	if not ambient and bool(body.get_meta("allow_facility_target",true)) and is_instance_valid(combat):
		var facility=combat.get("facility")
		if facility is CollisionObject3D:
			_objective_position=facility.global_position;_objective_ref=weakref(facility)
	_configured=true

func set_patrol_target(point: Vector3) -> void:
	if point.is_finite(): patrol_target=_bounded(point);_path.clear();_path_left=0

func hear_noise(point: Vector3, strength = 1.0) -> void:
	if not _configured or not point.is_finite() or strength<=0: return
	if body.global_position.distance_to(point)>clampf(strength,0,2)*45.0: return
	# Hearing gives a deliberately imprecise location, never a target reference.
	var angle=_rng.randf()*TAU;var radius=_rng.randf_range(2.5,6.0)
	_noise_position=_bounded(point+Vector3(cos(angle)*radius,0,sin(angle)*radius))
	_noise_left=5.0
	if not seen and state!="retreat": state="notice"

func note_damage(source_position: Vector3) -> void:
	# A received hit supplies an uncertain bearing/point, not automatic vision.
	hear_noise(source_position,2.0)

func step(delta: float) -> Dictionary:
	_report_pulse=false
	if not _configured or not is_instance_valid(body) or not is_instance_valid(combat): return _intent(false,Vector3.ZERO)
	if delta<=0 or not is_finite(delta): return _intent(false,last_seen_position)
	delta=minf(delta,.10);time_s+=delta;memory_age+=delta
	_noise_left=maxf(0,_noise_left-delta);_sense_left-=delta;_aim_left-=delta;_path_left-=delta;_avoid_left=maxf(0,_avoid_left-delta)
	if _sense_left<=0:
		_sense_left=.12
		_sense()
	if seen:
		reaction_time+=delta
		confidence=minf(1,confidence+delta*1.8)
	else:
		reaction_time=0;report_progress=0;confidence=maxf(0,confidence-delta/MEMORY_SECONDS)
	var hp=float(body.get("hp"));var maximum=maxf(1,float(body.get("max_hp")))
	var goal=patrol_target
	if hp/maximum<.24 and role!="boss":
		state="retreat"
		# Escape from remembered danger, not the hidden target's current position.
		var away=(body.global_position-last_seen_position).normalized() if memory_age<MEMORY_SECONDS else (home-body.global_position).normalized()
		goal=_bounded(body.global_position+away*20+Vector3.UP*1.5)
	elif seen and reaction_time<float(profile.reaction):
		state="notice";goal=body.global_position
	elif seen:
		state="pursue"
		var toward=last_seen_position-body.global_position;toward.y=0
		var forward=toward.normalized()
		var lateral=Vector3(-forward.z,0,forward.x)*_flank_side
		goal=last_seen_position-forward*float(profile.stand)
		goal.y=clampf(last_seen_position.y+1.0,MIN_ALTITUDE,MAX_ALTITUDE)
		if role in ["harasser","shooter","charger"]: goal+=lateral*(4.0+sin(time_s*.7)*1.5)
		if role=="scout" and not reported:
			report_progress+=delta
			if report_progress>=2.4:
				# The transmission boundary gets a fresh physical observation. A wall
				# appearing between staggered sense ticks can still interrupt the call.
				var observed=target
				_sense()
				if seen and target==observed: reported=true;_report_pulse=true
				else: report_progress=0
	elif memory_age<MEMORY_SECONDS and confidence>0:
		state="search"
		# Brief prediction uses the last observed velocity only; no target reads.
		goal=last_seen_position+last_seen_velocity*minf(memory_age,.6)
		if body.global_position.distance_to(goal)<3:
			goal+=Vector3(cos(time_s*.6),0,sin(time_s*.6))*minf(7.0,2.0+memory_age)
	elif _noise_left>0:
		state="search";goal=_noise_position
	elif state in ["search","pursue","flank","notice"]:
		state="lost";_lost_left=2.0;target=null;confidence=0
	elif state=="lost":
		_lost_left-=delta;goal=body.global_position
		if _lost_left<=0: state="patrol"
	else:
		state="patrol"
		if _objective_position.is_finite(): goal=_objective_position+Vector3.UP*4
		elif body.global_position.distance_to(patrol_target)<3:
			var old=home;home=patrol_target;patrol_target=old;goal=patrol_target
	if role=="support" and state in ["patrol","pursue"]:
		var ally=_injured_ally()
		if is_instance_valid(ally): goal=ally.global_position+Vector3(4,1,4)
	goal=_bounded(goal)
	var steering=_steer(goal,delta)
	var speed=float(profile.speed)*(0.55 if state=="notice" else 1.0)
	var wanted=steering.normalized()*minf(speed,steering.length()*.75)
	wanted.y=clampf(wanted.y,-2.2,2.2)
	desired_velocity=body.velocity.move_toward(wanted,float(profile.accel)*delta)
	var look=last_seen_position-body.global_position if seen else steering
	look.y=0
	if look.length()>.1:
		var wanted_heading=atan2(-look.x,-look.z)
		heading+=clampf(wrapf(wanted_heading-heading,-PI,PI),-float(profile.yaw)*delta,float(profile.yaw)*delta)
	if _aim_left<=0:
		_aim_left=.7
		_aim_error=Vector3(_rng.randf_range(-1,1),_rng.randf_range(-.4,.4),_rng.randf_range(-1,1))*float(profile.error)
	var aim=last_seen_position+last_seen_velocity*.12+_aim_error
	var can_attack=seen and reaction_time>=float(profile.reaction) and state=="pursue" and role!="support"
	can_attack=can_attack and body.global_position.distance_to(last_seen_position)<32.0
	var aiming=(last_seen_position-body.global_position).normalized()
	can_attack=can_attack and Vector3(-sin(heading),0,-cos(heading)).dot(Vector3(aiming.x,0,aiming.z).normalized())>cos(.30)
	# Recheck LOS at attack time, not just the staggered perception tick.
	can_attack=can_attack and is_instance_valid(target) and _line_clear(body.global_position,last_seen_position,target.get_rid())
	return _intent(can_attack,aim)

func _intent(can_attack: bool, aim: Vector3) -> Dictionary:
	return {"velocity":desired_velocity,"heading":heading,"state":state,"target":target if seen and is_instance_valid(target) else null,"can_attack":can_attack,"aim_position":aim,"seen":seen,"confidence":confidence,"report_ready":_report_pulse,"report_progress":report_progress/2.4,"report_position":last_seen_position,"memory_age":memory_age}

func _sense() -> void:
	seen=false
	var candidates: Array=[]
	var player=combat.get("pilot")
	if player is CollisionObject3D and bool(player.get("enabled")): candidates.append(player)
	if not ambient and _objective_ref!=null:
		var facility=_objective_ref.get_ref()
		if facility is CollisionObject3D: candidates.append(facility)
	var best: CollisionObject3D
	var best_distance=INF
	for candidate in candidates:
		if not is_instance_valid(candidate) or candidate.is_queued_for_deletion(): continue
		var difference: Vector3=candidate.global_position-body.global_position
		var distance_m=difference.length()
		if distance_m>float(profile.range) or distance_m>=best_distance: continue
		var horizontal=Vector3(difference.x,0,difference.z).normalized()
		if distance_m>4.0 and Vector3(-sin(heading),0,-cos(heading)).dot(horizontal)<cos(deg_to_rad(float(profile.fov))): continue
		if perception_visibility.is_valid() and not bool(perception_visibility.call(body.global_position,candidate.global_position)): continue
		if not _line_clear(body.global_position,candidate.global_position,candidate.get_rid()): continue
		best=candidate;best_distance=distance_m
	if best!=null:
		if target!=best: reaction_time=0;report_progress=0
		target=best;seen=true;last_seen_position=best.global_position;memory_age=0
		last_seen_velocity=best.velocity if best is CharacterBody3D else (best.linear_velocity if best is RigidBody3D else Vector3.ZERO)
		last_seen_velocity=last_seen_velocity.limit_length(12.0)
		confidence=maxf(confidence,.25)

func _line_clear(from: Vector3, to: Vector3, target_rid: RID) -> bool:
	if not body.is_inside_tree(): return false
	if combat.has_method("line_clear"): return bool(combat.line_clear(from,to,body.get_rid(),target_rid))
	var ray=PhysicsRayQueryParameters3D.create(from,to,1|2|4|8|32,[body.get_rid()])
	var hit=body.get_world_3d().direct_space_state.intersect_ray(ray)
	return hit.is_empty() or hit.rid==target_rid

func _injured_ally() -> CharacterBody3D:
	for ally in combat.get("enemies"):
		if not is_instance_valid(ally) or ally==body or float(ally.get("hp"))<=0: continue
		if float(ally.get("hp"))>=float(ally.get("max_hp"))*.8 or body.global_position.distance_to(ally.global_position)>20: continue
		if _line_clear(body.global_position,ally.global_position,ally.get_rid()): return ally
	return null

func _terrain(point: Vector3) -> float:
	if is_instance_valid(navigation_world) and navigation_world.has_method("terrain_height"):
		return float(navigation_world.terrain_height(point))
	return 0.0

func _bounded(point: Vector3) -> Vector3:
	var result=Vector3(clampf(point.x,3,597),point.y,clampf(point.z,3,497))
	var floor_y=maxf(MIN_ALTITUDE,_terrain(result)+MIN_ALTITUDE)
	result.y=clampf(result.y,minf(floor_y,MAX_ALTITUDE),MAX_ALTITUDE)
	return result

func _sweep(from: Vector3, motion: Vector3) -> float:
	if not body.is_inside_tree() or motion.length()<.01: return 1.0
	var query=PhysicsShapeQueryParameters3D.new();var sphere=SphereShape3D.new();sphere.radius=.95
	query.shape=sphere;query.transform=Transform3D(Basis.IDENTITY,from);query.motion=motion
	query.collision_mask=1|4|8|32;query.exclude=[body.get_rid()]
	var result=body.get_world_3d().direct_space_state.cast_motion(query)
	return float(result[0]) if result.size()>0 else 0.0

func _steer(goal: Vector3, _delta: float) -> Vector3:
	var from=body.global_position
	var offset=goal-from
	var probe=offset.limit_length(5.0)
	if _sweep(from,probe)>.98:
		if _avoid_left>0: return _avoid_direction*3
		_path.clear();return offset
	if state=="pursue": state="flank"
	if _path_left<=0 and (goal.distance_to(_path_goal)>5 or _path.is_empty()):
		_path_left=.8;_path_goal=goal;_path=_route(goal)
	while not _path.is_empty() and from.distance_to(_path[0])<2.2: _path.remove_at(0)
	if not _path.is_empty() and _sweep(from,(_path[0]-from).limit_length(4.0))>.9: return _path[0]-from
	if _avoid_left>0: return _avoid_direction*3
	var direction=Vector3(offset.x,0,offset.z).normalized()
	if direction.length()<.1: direction=Vector3.FORWARD
	var side=Vector3(-direction.z,0,direction.x)*_flank_side
	for candidate in [side+direction*.2,-side+direction*.2,Vector3.UP,Vector3.DOWN,-direction]:
		var test: Vector3=candidate.normalized()
		if (test.y>0 and from.y>MAX_ALTITUDE-1) or (test.y<0 and from.y<maxf(MIN_ALTITUDE,_terrain(from)+MIN_ALTITUDE)+1): continue
		if _sweep(from,test*4)>.9:
			_avoid_direction=test;_avoid_left=.65;return test*3
	return Vector3.ZERO

func _route(goal: Vector3) -> PackedVector3Array:
	var result: PackedVector3Array=[]
	if not is_instance_valid(navigation_world): return result
	# Layered author-known building footprints; dynamic machinery remains swept.
	var obstacles=navigation_world.get("obstacles")
	if not obstacles is Array: return result
	var requested=maxf(body.global_position.y,goal.y)
	var height=5.0 if requested<7 else (11.0 if requested<13 else (18.0 if requested<21 else (26.0 if requested<28 else 30.0)))
	if not _grids.has(height):
		var grid=AStarGrid2D.new();grid.region=Rect2i(0,0,48,40);grid.cell_size=Vector2(12.5,12.5);grid.offset=Vector2(6.25,6.25)
		grid.diagonal_mode=AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES;grid.update()
		for x in range(48):
			for z in range(40):
				if _terrain(Vector3((x+.5)*12.5,height,(z+.5)*12.5))+1.2>=height:
					grid.set_point_solid(Vector2i(x,z))
		for obstacle in obstacles:
			var bottom=float(obstacle.get("base_y",0.0))
			if bottom+float(obstacle.h)+1.2<height or bottom-1.2>height: continue
			for x in range(maxi(0,floori((float(obstacle.x)-float(obstacle.w)*.5-1.5)/12.5)),mini(48,ceili((float(obstacle.x)+float(obstacle.w)*.5+1.5)/12.5))):
				for z in range(maxi(0,floori((float(obstacle.z)-float(obstacle.l)*.5-1.5)/12.5)),mini(40,ceili((float(obstacle.z)+float(obstacle.l)*.5+1.5)/12.5))): grid.set_point_solid(Vector2i(x,z))
		_grids[height]=grid
	var grid: AStarGrid2D=_grids[height]
	var start=Vector2i(clampi(int(body.global_position.x/12.5),0,47),clampi(int(body.global_position.z/12.5),0,39))
	var end=Vector2i(clampi(int(goal.x/12.5),0,47),clampi(int(goal.z/12.5),0,39))
	if grid.is_point_solid(start) or grid.is_point_solid(end): return result
	for point in grid.get_point_path(start,end): result.append(Vector3(point.x,height,point.y))
	return result

func snapshot() -> Dictionary:
	return {"version":1,"state":state,"heading":heading,"memory_age":memory_age,"confidence":confidence,"last_seen_position":_vec(last_seen_position),"last_seen_velocity":_vec(last_seen_velocity),"home":_vec(home),"patrol_target":_vec(patrol_target),"time_s":time_s,"reaction_time":reaction_time,"reported":reported,"report_progress":report_progress,"noise_position":_vec(_noise_position),"noise_left":_noise_left,"rng_state":str(_rng.state),"flank_side":_flank_side,"aim_error":_vec(_aim_error),"aim_left":_aim_left,"sense_left":_sense_left,"lost_left":_lost_left}

func restore(saved: Dictionary) -> void:
	if int(saved.get("version",0))!=1: return
	state=str(saved.get("state","patrol"));heading=float(saved.get("heading",heading));time_s=float(saved.get("time_s",0))
	last_seen_position=_read_vec(saved.get("last_seen_position"),home);last_seen_velocity=_read_vec(saved.get("last_seen_velocity"),Vector3.ZERO)
	home=_read_vec(saved.get("home"),home);patrol_target=_read_vec(saved.get("patrol_target"),patrol_target)
	memory_age=maxf(0,float(saved.get("memory_age",999)));confidence=clampf(float(saved.get("confidence",0)),0,1)
	reaction_time=0;seen=false;target=null;reported=bool(saved.get("reported",false));report_progress=0
	_noise_position=_read_vec(saved.get("noise_position"),home);_noise_left=maxf(0,float(saved.get("noise_left",0)))
	_rng.state=int(str(saved.get("rng_state",_rng.state)));_flank_side=float(saved.get("flank_side",1))
	_aim_error=_read_vec(saved.get("aim_error"),Vector3.ZERO);_aim_left=float(saved.get("aim_left",0));_sense_left=0;_lost_left=float(saved.get("lost_left",0))
	_path.clear();_avoid_left=0

static func _vec(value: Vector3) -> Array: return [value.x,value.y,value.z]
static func _read_vec(value: Variant, fallback: Vector3) -> Vector3:
	if value is Array and value.size()==3:
		var point=Vector3(float(value[0]),float(value[1]),float(value[2]))
		if point.is_finite(): return point
	return fallback
