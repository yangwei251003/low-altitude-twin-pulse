extends Node3D

var profile = PilotProfile.new()
var router: FlightInput
var ui
var arena: Node3D
var camera: Camera3D
var player: PlayerDrone
var enemies: Array = []
var effects: Array = []
var dangers: Array = []
var objectives: Array = []
var selected_mission = 0
var difficulty = 0
var in_flight = false
var mission_time = 0.0
var stage = 0
var run_id = ""
var launch_point = Vector3(-14,1.65,8)
var last_reward = 0
var music: AudioStreamPlayer
var marker: Node3D
var target_marker: Node3D
var auto_test = false
var practice_mode = false
var test_driver = null
var sound_cache = {}
var abandoned = false
var district: HarborDistrict
var navigation=FlightNavigation.new()
var map_spec: Dictionary
var flight_bounds: Rect2
var camera_focus=Vector3.ZERO
var map_overview=false
var salvage: Array=[]
var supplies: Array=[]
var gates_passed=0
var bonus_parts=0
var enemies_defeated=0
var encounter_serial=0
var vfx_budget=0
var used_auto_fire=false

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	auto_test = OS.is_debug_build() and "--autotest" in OS.get_cmdline_user_args()
	if auto_test:
		profile = PilotProfile.new("user://automated_test.json")
		profile.data = profile.defaults()
	else:
		profile.load_profile()
	if not auto_test and profile.data.settings.fullscreen:DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
	difficulty = int(profile.data.settings.difficulty)
	router = FlightInput.new()
	add_child(router)
	router.apply_config(profile.data.settings.input)
	router.device_lost.connect(func(): if in_flight: pause_game("控制器已断开，已暂停。键盘仍可操作。"))
	var environment = WorldEnvironment.new()
	var env = Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color("25444f")
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("b7cbd1")
	env.ambient_light_energy = 0.32
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.ssao_enabled=true
	env.ssao_radius=2.2
	env.ssao_intensity=1.5
	env.ssao_light_affect=.35
	env.glow_enabled=true
	env.glow_intensity=.22
	env.tonemap_exposure=1.0
	environment.environment = env
	add_child(environment)
	var sun = DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-52,-25,0)
	sun.light_color = Color("fff0d9")
	sun.light_energy = 1.05
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 180
	sun.directional_shadow_mode=DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	sun.shadow_blur=1.5
	add_child(sun)
	camera = Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 36
	camera.far = 240
	add_child(camera)
	_set_camera()
	ui = load("res://scripts/game_ui.gd").new()
	ui.world = self
	add_child(ui)
	music = AudioStreamPlayer.new()
	add_child(music)
	if DisplayServer.get_name()!="headless" and ResourceLoader.exists("res://assets/audio/harbor.wav"):
		music.stream = load("res://assets/audio/harbor.wav")
		music.finished.connect(func(): music.play())
		music.play()
	set_volume(float(profile.data.settings.volume))
	show_hangar()
	if auto_test:
		test_driver = load("res://tests/flight_driver.gd").new()
		test_driver.world = self
		add_child(test_driver)

func _exit_tree() -> void:
	for child in get_children():
		if child is AudioStreamPlayer:
			child.stop();child.stream=null
	GameVisuals.models.clear();GameVisuals.mats.clear();GameVisuals.surfaces.clear();GameVisuals.primitives.clear()
	sound_cache.clear()

func _set_camera() -> void:
	var high = int(profile.data.settings.camera) == 1
	var focus=Vector3.ZERO if map_overview or not in_flight else camera_focus
	camera.position = focus+Vector3(30,58 if high else 46,38)
	camera.look_at(focus,Vector3.UP)
	camera.size = (map_spec.size.y*1.25 if not map_spec.is_empty() else 100.0) if map_overview or not in_flight else 37.0

func flight_direction(input: Vector2) -> Vector3:
	var right=camera.global_basis.x;right.y=0;right=right.normalized()
	var forward=-camera.global_basis.z;forward.y=0;forward=forward.normalized()
	return right*input.x-forward*input.y

func build_district(index: int) -> void:
	map_spec=ExpeditionMaps.data(index)
	flight_bounds=ExpeditionMaps.bounds(index)
	district=HarborDistrict.new()
	district.build(arena,index)
	GameVisuals.batch_static(arena)
	navigation.configure(flight_bounds,district.obstacles)
	launch_point=map_spec.launch

func clear_arena() -> void:
	if is_instance_valid(arena):
		remove_child(arena)
		arena.queue_free()
	enemies.clear()
	effects.clear()
	dangers.clear()
	objectives.clear()
	salvage.clear();supplies.clear()
	arena = Node3D.new()
	arena.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(arena)
	player = null

func show_hangar() -> void:
	get_tree().paused = false
	in_flight = false
	practice_mode = false
	router.release_states()
	router.allow_input = false
	clear_arena()
	map_spec=ExpeditionMaps.data(selected_mission)
	_set_camera()
	ui.show_hangar()
	if not profile.notice.is_empty(): toast(profile.notice)

func start_practice() -> void:
	start_mission(0,true)

func restart_mission() -> void:
	start_mission(selected_mission,practice_mode)

func start_mission(index: int, practice: bool=false) -> void:
	if not profile.can_play(index): return
	practice_mode = practice and index==0
	selected_mission = index
	get_tree().paused = false
	router.release_states()
	clear_arena()
	build_district(index)
	map_overview=false
	camera_focus=Vector3(launch_point.x,0,launch_point.z)
	mission_time = 0
	stage = 0
	last_reward = 0
	bonus_parts=0;gates_passed=0;enemies_defeated=0;encounter_serial=0
	run_id = "%s-%s" % [Time.get_unix_time_from_system(),Time.get_ticks_usec()]
	router.allow_input = true
	router.layer = 0
	difficulty = int(profile.data.settings.difficulty)
	player = PlayerDrone.new()
	player.world = self
	player.router = router
	player.loadout = profile.data.loadout.duplicate()
	player.maximum_health = GameData.DIFFICULTY[difficulty].health
	player.health = player.maximum_health
	player.auto_fire = bool(profile.data.settings.auto_fire)
	used_auto_fire=player.auto_fire
	arena.add_child(player)
	player.position = launch_point
	player.enabled = true
	marker = Node3D.new()
	arena.add_child(marker)
	GameVisuals.ring(marker,Vector3.ZERO,0.8,Color("55cbd0"),0.065)
	GameVisuals.cylinder(marker,Vector3(0,-0.01,0),0.61,0.016,Color(0.06,0.2,0.24,0.28))
	target_marker = Node3D.new()
	arena.add_child(target_marker)
	GameVisuals.ring(target_marker,Vector3.ZERO,1.0,Color("edae65"),0.06)
	for pos in map_spec.objectives:
		_add_objective(pos,"回收补给" if index==0 else ("花园电源" if index==1 else "安全继电器"),"crate" if index==0 else "node")
	for group in map_spec.enemy_groups:
		if practice_mode:continue
		spawn_enemy(group[1],group[0])
		for extra in range(int(GameData.DIFFICULTY[difficulty].extra)):
			if group[1]=="patrol":spawn_enemy("patrol" if extra==0 else "charger",group[0]+Vector3(3+extra*2,0,2))
	for pos in map_spec.salvage:
		if practice_mode:continue
		var visual=GameVisuals.asset(arena,"crate",pos,.65)
		GameVisuals.ring(visual,Vector3(0,.1,0),1.3,Color("d2b675"))
		salvage.append({"position":pos,"node":visual,"taken":false})
	for pos in map_spec.supplies:
		if practice_mode:continue
		var visual=GameVisuals.asset(arena,"node",pos,.8)
		GameVisuals.ring(visual,Vector3(0,.1,0),1.5,Color("7cc9a6"))
		supplies.append({"position":pos,"node":visual,"taken":false})
	in_flight = true
	_set_camera()
	ui.show_hud()
	toast("自由练飞 · 无敌人、无受伤 · 练习制动、航层、回收与返航" if practice_mode else "WASD 飞行 · %s 制动 · 低处停稳按 %s · %s 开火"%[router.binding_label("brake"),router.binding_label("interact"),router.binding_label("fire")])
	sound("ui")

func _add_objective(pos: Vector3, title: String, asset: String) -> void:
	var object = GameVisuals.asset(arena,asset,pos)
	var ring = GameVisuals.ring(arena,pos+Vector3(0,0.13,0),1.45,Color("dfab55"),0.065)
	objectives.append({"position":pos,"title":title,"progress":0.0,"done":false,"object":object,"ring":ring})

func _physics_process(delta: float) -> void:
	if not in_flight or get_tree().paused or not is_instance_valid(player): return
	mission_time += delta
	used_auto_fire=used_auto_fire or player.auto_fire
	marker.position = Vector3(player.position.x,0.12,player.position.z)
	target_marker.visible = is_instance_valid(player.target)
	if target_marker.visible:
		target_marker.position = Vector3(player.target.position.x,0.14,player.target.position.z)
	var done = 0
	for objective in objectives:
		if objective.done:
			done += 1
			continue
		var distance = Vector2(player.position.x-objective.position.x,player.position.z-objective.position.z).length()
		if distance < 2.3 and player.position.y < 2.2 and player.velocity.length()<2.6 and router.held("interact"):
			objective.progress = minf(1.0,float(objective.progress)+delta/1.45)
			if objective.progress >= 1:
				objective.done = true
				objective.ring.material_override = GameVisuals.material(Color("6db9ac"),0.35)
				objective.object.visible = selected_mission != 0
				sound("interact")
				toast("回收完成" if selected_mission==0 else "节点重启，设施已恢复")
				effect(objective.position+Vector3.UP,Color("86d8c4"),1.5)
		else:
			objective.progress = maxf(0,float(objective.progress)-delta*0.15)
	if done>stage and stage<8:
		stage=done
		if selected_mission==1 and difficulty>0:
			spawn_enemy("charger",objectives[done-1].position+Vector3(7,4.1,5))
	if selected_mission==2 and done==objectives.size() and stage<8:
		stage=8
		spawn_enemy("boss",map_spec.boss)
		toast("安全锁已解除。北港检修场：蜂巢管家已激活。")
	var can_return = selected_mission<2 and done==objectives.size()
	if can_return and player.position.distance_to(launch_point)<2.7 and router.layer==0 and router.held("interact") and player.velocity.length()<2.6:
		finish_mission(true)
	if selected_mission == 2 and stage == 9:
		finish_mission(true)
	_update_exploration()
	_update_effects(delta)
	ui.update_hud()

func _process(delta: float) -> void:
	if in_flight and is_instance_valid(player) and not get_tree().paused:
		var target_focus=Vector3(player.position.x,0,player.position.z)
		camera_focus=camera_focus.lerp(target_focus,1.0-exp(-delta*3.0))
		_set_camera()
	if router.pressed("map") and in_flight:
		map_overview=not map_overview
		_set_camera()
	if router.pressed("pause"):
		if in_flight and ui.current_screen in ["hud","pause"]:
			if get_tree().paused: resume_game()
			else: pause_game("")
	if router.pressed("restart") and in_flight and not get_tree().paused:
		restart_mission()
	if Input.is_action_just_pressed("flight_capture"):
		capture_frame("manual")

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT and in_flight and not auto_test and is_instance_valid(ui):
		pause_game("窗口失去焦点，已暂停。")

func spawn_enemy(kind: String, pos: Vector3) -> DroneEnemy:
	if kind!="node":
		var safe=navigation.nearest_free(navigation.cell(pos))
		var point=navigation.grid.get_point_position(safe)
		pos.x=point.x;pos.z=point.y
	var enemy = preload("res://scripts/tactical_enemy.gd").new()
	enemy.world = self
	enemy.kind = kind
	enemy.encounter_id=encounter_serial
	encounter_serial+=1
	enemy.position = pos
	arena.add_child(enemy)
	enemy.anchor = pos
	enemies.append(enemy)
	return enemy

func live_enemy_count() -> int:
	var count = 0
	for enemy in enemies:
		if is_instance_valid(enemy) and not enemy.dead: count += 1
	return count

func enemy_destroyed(enemy: DroneEnemy) -> void:
	enemies_defeated+=1
	particles(enemy.global_position,Color("eeb780"),26 if enemy.kind=="boss" else 18)
	if enemy.kind == "boss":
		stage = 9

func has_line(from: Node3D, to: Node3D) -> bool:
	if not is_instance_valid(from) or not is_instance_valid(to): return false
	var query = PhysicsRayQueryParameters3D.create(from.global_position,to.global_position,1)
	return get_world_3d().direct_space_state.intersect_ray(query).is_empty()

func find_target(from: Node3D, previous, cycle: bool):
	var available = []
	for enemy in enemies:
		if not is_instance_valid(enemy) or enemy.dead: continue
		if enemy.kind == "boss" and enemy.phase == 2: continue
		if from.position.distance_to(enemy.position)<19.0 and has_line(from,enemy):
			available.append(enemy)
	available.sort_custom(func(a,b): return from.position.distance_squared_to(a.position)<from.position.distance_squared_to(b.position))
	if available.is_empty(): return null
	if available.has(previous):
		if not cycle: return previous
		return available[(available.find(previous)+1)%available.size()]
	return available[0]

func fire_shot(from: Vector3, toward: Vector3, damage: float, friendly: bool, heavy: bool) -> void:
	var shot = PulseShot.new()
	shot.world = self
	shot.direction = (toward-from).normalized()
	shot.damage = damage
	shot.friendly = friendly
	shot.heavy = heavy
	shot.speed = 48 if friendly else float(GameData.DIFFICULTY[difficulty].shot_speed)
	arena.add_child(shot)
	shot.position = from + shot.direction * (0.9 if friendly else 1.1)
	shot.look_at(shot.position+shot.direction,Vector3.UP)

func enemy_warning(enemy: DroneEnemy, toward: Vector3, duration: float) -> void:
	var mark = GameVisuals.ring(arena,Vector3(enemy.position.x,0.13,enemy.position.z),1.0,Color("f0aa5b"),0.09)
	effects.append({"node":mark,"life":duration,"total":duration,"grow":false})
	if enemy.kind == "charger":
		var distance = enemy.position.distance_to(toward)
		var lane = GameVisuals.box(arena,Vector3.ZERO,Vector3(0.15,0.04,distance),Color("e5a657"))
		lane.position = Vector3((enemy.position.x+toward.x)/2,0.13,(enemy.position.z+toward.z)/2)
		var dir = toward-enemy.position
		lane.rotation.y = atan2(dir.x,dir.z)
		effects.append({"node":lane,"life":duration,"total":duration,"grow":false})

func danger_zone(pos: Vector3, radius: float, wait: float, damage: float) -> void:
	var visual = GameVisuals.ring(arena,Vector3(pos.x,0.15,pos.z),radius,Color("e79258"),0.10)
	var center = GameVisuals.ring(arena,Vector3(pos.x,0.16,pos.z),0.35,Color("e79258"),0.065)
	dangers.append({"position":pos,"radius":radius,"time":wait,"initial":wait,"damage":damage,"node":visual,"center":center})

func _update_effects(delta: float) -> void:
	for i in range(effects.size()-1,-1,-1):
		var fx = effects[i]
		fx.life -= delta
		if not is_instance_valid(fx.node):
			effects.remove_at(i)
			continue
		if fx.grow: fx.node.scale = Vector3.ONE * (1+(1-fx.life/fx.total)*0.8)
		if fx.life <= 0:
			fx.node.queue_free()
			effects.remove_at(i)
	for i in range(dangers.size()-1,-1,-1):
		var danger = dangers[i]
		danger.time -= delta
		danger.center.scale = Vector3.ONE * (1+(1-danger.time/danger.initial)*2)
		if danger.time<=0:
			effect(danger.position,Color("f3b372"),danger.radius)
			if player.global_position.distance_to(danger.position)<danger.radius: player.take_damage(danger.damage)
			danger.node.queue_free()
			danger.center.queue_free()
			dangers.remove_at(i)

func effect(pos: Vector3, color: Color, radius: float) -> void:
	var fx = GameVisuals.ring(arena,pos,radius,color,0.08)
	effects.append({"node":fx,"life":0.45,"total":0.45,"grow":true})

func mission_status() -> String:
	var done = 0
	for objective in objectives:
		if objective.done: done += 1
	if selected_mission==0:
		if done<objectives.size(): return "回收补给  %d / %d\n靠近金色圆环 · 低航层停稳 · 按住 %s" % [done,objectives.size(),router.binding_label("interact")]
		return "返回起降坪\n青色 H 标识 · 低航层停稳 · 按住 %s"%router.binding_label("interact")
	if selected_mission==1:
		if done<objectives.size():return "重启花园电源  %d / %d\n避开干扰 · 低处停稳按住 %s" % [done,objectives.size(),router.binding_label("interact")]
		return "设施已恢复 · 返回起降坪\n无需清空所有敌人，稳妥返航"
	if selected_mission==2 and done<objectives.size():return "解除安全继电器  %d / %d\n穿越码头，低处停稳按住 %s"%[done,objectives.size(),router.binding_label("interact")]
	var boss = get_boss()
	if is_instance_valid(boss):
		return ["","蜂巢协议 · 读取地面预警\n避开圆环，趁恢复间隙开火","护盾阶段 · 击破两侧节点\nTab 切换目标，核心暂时受保护","核心暴露 · 把握攻击窗口\n先走位避险，再停稳输出"][boss.phase]
	return "检修场已恢复"

func get_boss():
	for enemy in enemies:
		if is_instance_valid(enemy) and enemy.kind=="boss" and not enemy.dead:return enemy
	return null

func finish_mission(success: bool) -> void:
	if not in_flight: return
	in_flight = false
	player.enabled = false
	router.allow_input = false
	if success and not practice_mode:
		last_reward = profile.claim(selected_mission,run_id,mission_time,player.collision_count,player.damage_taken,difficulty,used_auto_fire,bonus_parts)
		sound("complete")
	get_tree().paused = true
	ui.show_results(success)

func pause_game(reason: String) -> void:
	if not in_flight: return
	router.release_states()
	get_tree().paused = true
	ui.show_pause(reason)

func resume_game() -> void:
	router.release_states()
	get_tree().paused = false
	ui.show_hud()

func toast(message: String) -> void:
	if is_instance_valid(ui): ui.toast(message)

func sound(id: String, volume: float = 0) -> void:
	if DisplayServer.get_name()=="headless":return
	var path = "res://assets/audio/"+id+".wav"
	if not ResourceLoader.exists(path): return
	if not sound_cache.has(id): sound_cache[id] = load(path)
	var stream = AudioStreamPlayer.new()
	stream.stream = sound_cache[id]
	stream.volume_db = -9+volume+linear_to_db(maxf(.001,float(profile.data.settings.volume)))
	add_child(stream)
	stream.finished.connect(stream.queue_free)
	stream.play()

func set_volume(value: float) -> void:
	profile.data.settings.volume = value
	if is_instance_valid(music):music.volume_db = -10+linear_to_db(maxf(.001,value))

func capture_frame(label: String) -> void:
	if DisplayServer.get_name() == "headless": return
	await RenderingServer.frame_post_draw
	var folder = ProjectSettings.globalize_path("res://artifacts/screenshots") if OS.is_debug_build() else OS.get_executable_path().get_base_dir()+"/screenshots"
	DirAccess.make_dir_recursive_absolute(folder)
	var filename=label
	if label=="manual":filename="游戏截图_"+Time.get_datetime_string_from_system().replace(":","-")+"_"+str(Time.get_ticks_msec())
	var result=get_viewport().get_texture().get_image().save_png(folder+"/"+filename+".png")
	if label=="manual":toast("截图已保存到游戏目录的 screenshots 文件夹" if result==OK else "截图保存失败，请检查游戏目录是否可写。")

func can_attack(candidate: DroneEnemy) -> bool:
	var active=0
	for enemy in enemies:
		if is_instance_valid(enemy) and enemy!=candidate and not enemy.dead and enemy.state in ["warn","charge"] and enemy.position.distance_to(player.position)<30:
			active+=1
	return active<int(GameData.DIFFICULTY[difficulty].attackers)

func _update_exploration() -> void:
	for item in salvage:
		if not item.taken and player.position.distance_to(item.position+Vector3.UP*1.65)<2.0 and router.layer==0:
			item.taken=true;item.node.visible=false;bonus_parts+=15
			toast("发现散落零件 +15 · 完成行动后结算");sound("interact")
	for item in supplies:
		if not item.taken and player.health<player.maximum_health and player.position.distance_to(item.position+Vector3.UP*1.65)<2.5 and router.held("interact") and player.velocity.length()<2.6:
			item.taken=true;item.node.visible=false
			player.health=minf(player.maximum_health,player.health+float(GameData.DIFFICULTY[difficulty].heal))
			toast("现场维修完成 · 本补给点已用尽");sound("interact")
	if gates_passed<map_spec.gates.size() and player.position.distance_to(map_spec.gates[gates_passed])<1.9:
		gates_passed+=1
		sound("interact")
		if gates_passed==map_spec.gates.size():
			if not practice_mode:bonus_parts+=20
			toast("飞行航线完成 · 继续练习回收与返航" if practice_mode else "飞行航线完成 +20 · 制动与航层练习达成")
		else:toast("穿越飞行门 %d / %d · 注意下一道门的航层"%[gates_passed,map_spec.gates.size()])

func beam(from: Vector3,to: Vector3,color: Color,life: float=.2,width: float=.045) -> void:
	var length=from.distance_to(to)
	if length<.05:return
	var b=GameVisuals.box(arena,(from+to)*.5,Vector3(width,width,length),color)
	b.look_at(to,Vector3.UP)
	b.material_override=GameVisuals.material(color,.7)
	effects.append({"node":b,"life":life,"total":life,"grow":false})

func particles(pos: Vector3,color: Color,amount: int=12) -> void:
	if effects.size()>80:return
	var p=CPUParticles3D.new()
	p.amount=amount;p.lifetime=.48;p.one_shot=true;p.explosiveness=.92
	p.direction=Vector3.UP;p.spread=180;p.gravity=Vector3(0,-2.5,0)
	p.initial_velocity_min=2;p.initial_velocity_max=5
	p.scale_amount_min=.08;p.scale_amount_max=.28
	var mesh=QuadMesh.new();mesh.size=Vector2(.7,.7)
	var mat=StandardMaterial3D.new()
	mat.transparency=BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.billboard_mode=BaseMaterial3D.BILLBOARD_ENABLED
	mat.albedo_texture=load("res://assets/vfx/spark.png")
	mat.albedo_color=color;mesh.material=mat;p.mesh=mesh
	arena.add_child(p);p.position=pos;p.emitting=true
	effects.append({"node":p,"life":.7,"total":.7,"grow":false})

