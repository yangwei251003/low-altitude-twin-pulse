extends Node

var world
var mission=0
var elapsed=0.0
var path=PackedVector2Array()
var path_index=0
var route_clock=0.0
var report_clock=0.0
var results=[]
var started=false
var goal=Vector3.ZERO
var orbit_angle=0.0
var last_position=Vector3.ZERO
var stuck_time=0.0
var difficulty=0
var frame_times=[]
var captured=false

func _ready() -> void:
	process_mode=Node.PROCESS_MODE_ALWAYS
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--difficulty="):difficulty=clampi(int(arg.trim_prefix("--difficulty=")),0,2)
	world.profile.data.settings.difficulty=difficulty
	world.router.override_enabled=true
	call_deferred("_launch")

func _launch() -> void:
	world.start_mission(mission)
	started=true;elapsed=0;route_clock=0;path.clear();path_index=0;stuck_time=0;frame_times.clear();captured=false
	last_position=world.player.position
	print("AUTO_START mission=",mission," difficulty=",difficulty," loadout=",world.player.loadout)

func _physics_process(delta: float) -> void:
	if not started:return
	if not world.in_flight:
		started=false
		var success=world.profile.data.completed.has(mission)
		var record={"mission":mission,"success":success,"time":world.mission_time,"health":world.player.health,"collisions":world.player.collision_count,"damage":world.player.damage_taken,"reward":world.last_reward}
		if not frame_times.is_empty():
			frame_times.sort()
			var sum=0.0
			for ms in frame_times:sum+=ms
			record["mean_fps"]=1000.0/(sum/frame_times.size())
			record["p95_frame_ms"]=frame_times[int(frame_times.size()*.95)]
			record["frames"]=frame_times.size()
		results.append(record);print("AUTO_RESULT ",JSON.stringify(record))
		if DisplayServer.get_name()!="headless":
			await world.capture_frame("result_map%d"%mission)
		if not success:_end(1);return
		if mission==2:_end(0);return
		if mission==0:world.profile.buy_module("charge");world.profile.equip("charge")
		if mission==1 and difficulty<2:world.profile.buy_module("cooler");world.profile.equip("cooler")
		mission+=1
		call_deferred("_launch")
		return
	if world.get_tree().paused:return
	elapsed+=delta;route_clock-=delta;report_clock-=delta
	if elapsed>650:_fail("timeout");return
	var pilot=world.player
	var buttons={"fire":true}
	var combat=null
	var nearest=22.0
	for enemy in world.enemies:
		if not is_instance_valid(enemy) or enemy.dead or (enemy.kind=="boss" and enemy.phase==2):continue
		var distance=pilot.position.distance_to(enemy.position)
		if distance<nearest:nearest=distance;combat=enemy
	var interact=false
	if is_instance_valid(combat):
		orbit_angle+=delta*.38
		var away=pilot.position-combat.position;away.y=0
		if away.length()<.1:away=Vector3(1,0,0)
		var radial=away.normalized().rotated(Vector3.UP,.40)
		goal=combat.position+radial*(11.0 if combat.kind!="boss" else 13.0)
	else:
		goal=world.launch_point
		var distance=INF
		for item in world.objectives:
			if not item.done and pilot.position.distance_to(item.position)<distance:
				distance=pilot.position.distance_to(item.position);goal=item.position
		if world.selected_mission==2 and world.stage>=8:goal=world.map_spec.boss+Vector3(-13,0,10)
		interact=true
	# Exercise the visible defensive mechanics, including supplies and telegraphs.
	if pilot.health<pilot.maximum_health*.6:
		var supply_distance=INF
		for supply in world.supplies:
			var d=pilot.position.distance_to(supply.position)
			if not supply.taken and d<supply_distance:
				supply_distance=d;goal=supply.position;interact=true
	var evade=Vector3.ZERO
	for danger in world.dangers:
		var predicted=pilot.position+pilot.velocity*clampf(danger.time,0,1.5)
		var away=predicted-danger.position;away.y=0
		if away.length()<danger.radius+.7:
			if away.length()<.2:away=Vector3(1,0,1)
			var forward=goal-pilot.position;forward.y=0;forward=forward.normalized()
			var side=Vector3(-forward.z,0,forward.x)
			if side.dot(away)<0:side=-side
			evade+=(forward*.45+side).normalized()*8.0
	if evade.length()>.1:
		goal=pilot.position+evade;interact=false;route_clock=0
		if pilot.shield_cooldown<=0:buttons.utility_pressed=true
	if is_instance_valid(combat) and combat.state=="warn" and pilot.shield_cooldown<=0:
		buttons.utility_pressed=true
	goal.x=clampf(goal.x,world.flight_bounds.position.x+3,world.flight_bounds.end.x-3)
	goal.z=clampf(goal.z,world.flight_bounds.position.y+3,world.flight_bounds.end.y-3)
	var flat_distance=Vector2(pilot.position.x-goal.x,pilot.position.z-goal.z).length()
	if route_clock<=0:
		path=world.navigation.path(pilot.position,goal);path_index=1 if path.size()>1 else 0;route_clock=1.1
	var waypoint=goal
	if path_index<path.size():
		waypoint=Vector3(path[path_index].x,pilot.position.y,path[path_index].y)
		if Vector2(pilot.position.x-waypoint.x,pilot.position.z-waypoint.z).length()<1.5:path_index+=1
	if flat_distance<4:waypoint=goal
	var error=waypoint-pilot.position;error.y=0
	var desired=error.normalized()*minf(float(GameData.MODULES[pilot.loadout.drive].speed),error.length()*2.2)
	var command=(desired-Vector3(pilot.velocity.x,0,pilot.velocity.z)*.45)/float(GameData.MODULES[pilot.loadout.drive].speed)
	var right=world.flight_direction(Vector2.RIGHT)
	var back=world.flight_direction(Vector2.DOWN)
	world.router.override_move=Vector2(command.dot(right),command.dot(back)).limit_length(1)
	if interact and flat_distance<2.0:
		buttons.brake=true;buttons.interact=true;buttons.low_pressed=true
	else:buttons.high_pressed=true
	world.router.override_buttons=buttons
	if report_clock<=0:
		print("AUTO_TICK mission=",mission," t=",int(elapsed)," pos=",pilot.position," goal=",goal," hp=",pilot.health," combat=",combat.kind if is_instance_valid(combat) else "none")
		if pilot.position.distance_to(last_position)<.25 and not interact:stuck_time+=5
		else:stuck_time=0
		last_position=pilot.position;report_clock=5
		if stuck_time>35:_fail("stuck");return

func _fail(reason: String) -> void:
	print("AUTO_FAILURE ",reason)
	results.append({"mission":mission,"success":false,"reason":reason,"position":str(world.player.position),"goal":str(goal)})
	_end(1)

func _process(delta: float) -> void:
	if DisplayServer.get_name()=="headless" or not started or not world.in_flight or get_tree().paused:return
	if elapsed>5:frame_times.append(delta*1000.0)
	if elapsed>32 and not captured:
		captured=true
		world.capture_frame("combat_map%d"%mission)

func _end(code: int) -> void:
	var out=FileAccess.open("res://artifacts/playthrough_%s%d.json"%["" if DisplayServer.get_name()=="headless" else "graphical_",difficulty],FileAccess.WRITE)
	out.store_string(JSON.stringify({"difficulty":difficulty,"result":code,"runs":results},"\t"));out.close()
	print("AUTO_EXIT ",code)
	get_tree().quit(code)
