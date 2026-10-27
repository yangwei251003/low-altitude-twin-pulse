class_name GameSessionV2
extends Node3D

const ProfileCatalog = preload("res://scripts/v2/profile_catalog.gd")
const CameraRig = preload("res://scripts/v2/flight_camera.gd")
const VisibilityController = preload("res://scripts/v2/visibility_controller.gd")
const FLIGHT_CAMERA_OFFSET = Vector3(32.0, 39.0, 32.0)
const FLIGHT_CAMERA_NEAR_SIZE = 32.0
const FLIGHT_CAMERA_WIDE_SIZE = 44.0

var repository: SaveRepositoryV2
var content: Dictionary
var input: PilotInputV2
var phone: PhoneServerV2
var ui: GameInterfaceV2
var world: RegionWorldV2
var pilot: FlightBodyV2
var combat: CombatV2
var runner: TaskRunnerV2
var camera: Camera3D
var environment: WorldEnvironment
var sun: DirectionalLight3D
var play_root: Node3D
var hangar_root: Node3D
var preview: Node3D
var audio: Node
var current_job: Dictionary = {}
var stage_index = 0
var night = false
var region_id = "R1"
var selected_frame = "tr01"
var selected_page = "主页"
var active_build: Dictionary
var flight_active = false
var pause_reasons: Dictionary = {}
var run_id = ""
var run_seconds = 0.0
var run_parts = 0
var run_completed_stages: Array[String] = []
var regions_at_departure: Array[String] = []
var run_result_success = false
var repeat_run = false
var pending_transaction: Dictionary = {}
var pending_next: Callable
var message = ""
var old_phone_active = false
var qa_mode = false
var frame_samples: Array[float] = []
var previous_usec = 0
var qa_path = ""
var restored_run_state: Dictionary = {}
var run_conditions: Dictionary = {}
var restored_conditions: Dictionary = {}
var departure_poi_id = ""
var visibility_controller: Node
var camera_focus = Vector3.ZERO
var camera_lead = Vector3.ZERO
var profiles = ProfileCatalog.new()
var tutorial: Node
var living: Node3D
var flight_camera = CameraRig.new()
var overview_proxy: Node3D
var waypoint = Vector3.INF
var waypoint_marker: Node3D
var service_navigation_id = ""
var restored_environment: Dictionary = {}
var environment_action_held = false
var environment_cooldown = 0.0
var weather_audio_clock = 0.0
var navigation_was_degraded = false
var tutorial_warning_serial = 0
var tutorial_cover_pending = false
var tutorial_cover_seconds = 0.0
var overview_fog_enabled = false
var environment_explained: Dictionary = {}
var night_visibility: Node3D
var encounter_director: Node
var combat_feedback: Node3D
var restored_damage: Dictionary = {}
var critical_warning_left = 0.0
var combat_context_left = 0.0
var approach_audio_left = 0.0

func combat_point_visible(point: Vector3) -> bool:
	if not night_point_visible(point) or not is_instance_valid(camera) or not is_instance_valid(world):return false
	var origin=camera.project_ray_origin(camera.unproject_position(point))
	var ray=PhysicsRayQueryParameters3D.create(origin,point,1)
	var hit=world.get_world_3d().direct_space_state.intersect_ray(ray)
	return hit.is_empty() or hit.position.distance_to(point)<.7

func enemy_perception_visible(observer: Vector3, target: Vector3) -> bool:
	# Illumination grants detection permission, never wall penetration or GPS.
	if not night:return true
	return observer.distance_to(target)<=22.0 and night_point_visible(target)

func combat_environment_at(point: Vector3) -> Dictionary:
	var sample:Dictionary=living.sample(point) if is_instance_valid(living) else {}
	if is_instance_valid(world):sample.merge(world.surface_at(point),true)
	return sample

func _combat_event(event: Dictionary) -> void:
	if is_instance_valid(encounter_director):encounter_director.note_event(event)
	if str(event.get("kind",""))=="shot" and is_instance_valid(night_visibility):
		var value=event.get("muzzle_position",event.get("position",[]))
		if value is Array and value.size()==3:night_visibility.reveal_flash(Vector3(value[0],value[1],value[2]))
	if is_instance_valid(audio) and audio.has_method("play_combat_event"):
		audio.play_combat_event(event)
		if str(event.get("kind",""))=="hit":
			if float(event.get("shield_absorbed",0))>0:audio.play_combat_event(event.merged({"kind":"shield_absorbed"},true))
			if bool(event.get("component_disabled",false)):audio.play_combat_event(event.merged({"kind":"component_damaged"},true))

func _pilot_damage(receipt: Dictionary) -> void:
	# Combat hits are published by Combat after this callback. Environmental hits
	# enter the same event stream once, after the same actual damage settlement.
	if bool(receipt.get("combat",false)) or not is_instance_valid(combat):return
	var details=receipt.duplicate(true)
	details["surface"]="ground";details["receipt_id"]="pilot-env:%s:%s"%[run_id,str(receipt.get("serial",0))]
	combat._record("hit",null,pilot,pilot.global_position,float(receipt.get("damage",0)),0,0,str(receipt.get("hit_result","hit")),details)

func _update_combat_context(delta: float) -> void:
	if not is_instance_valid(encounter_director):return
	combat_context_left-=delta
	critical_warning_left=maxf(0,critical_warning_left-delta)
	if combat_context_left>0:return
	combat_context_left=.5
	var training=bool(current_job.get("training",false)) or str(current_job.get("id","")) in ["M01","M02","M03"]
	encounter_director.set_suppressed(training or not pilot.enabled)
	encounter_director.set_context({"mission_reserved":0,"environment_warning":str(pilot.environment_sample.get("event_phase","")) in ["warning","active"],"service_active":pilot.is_landed() and not world.nearest_service(pilot.global_position).is_empty()})
	approach_audio_left-=.5
	if approach_audio_left<=0:
		approach_audio_left=5.0
		var nearby:Node3D=null;var distance_m=32.0
		for foe in combat.enemies:
			if not is_instance_valid(foe) or foe.hp<=0:continue
			var distance=foe.global_position.distance_to(pilot.global_position)
			if distance<distance_m:nearby=foe;distance_m=distance
		if is_instance_valid(nearby):combat._record("approach",nearby,null,nearby.global_position)
	if pilot.enabled and pilot.health/maxf(1,pilot.maximum_health)<.28 and critical_warning_left<=0:
		critical_warning_left=8.0
		combat._record("critical_warning",pilot,pilot,pilot.global_position,0,0,0,"",{"pilot_target":true,"component_status":str(pilot.telemetry.get("component_status",""))})

func night_point_visible(point: Vector3) -> bool:
	if not night or not flight_active:return true
	if is_instance_valid(night_visibility):return night_visibility.point_visible(point)
	return is_instance_valid(pilot) and pilot.global_position.distance_to(point)<18.0

func list_profiles() -> Array:
	return profiles.list_profiles()

func select_profile(id: String) -> bool:
	if flight_active or not pending_transaction.is_empty(): notify("请先返回机库再切换飞行员"); return false
	var candidate=profiles.open_profile(id)
	if candidate.read_only or candidate._load_failed: notify(candidate.notice); return false
	if not profiles.select(id): notify("飞行员选择未保存"); return false
	repository=candidate
	active_build=selected_build()
	selected_frame=str(active_build.airframe_id)
	input.configure_input(repository.data.settings.get("input",{}))
	input.reset_throttle()
	if is_instance_valid(tutorial): tutorial.configure(self)
	apply_settings()
	_enter_hangar()
	return true

func rename_profile(value: String) -> bool:
	var clean=value.strip_edges().substr(0,20)
	if clean.is_empty(): return false
	var result=repository.commit({"id":"name:"+str(Time.get_ticks_usec()),"set":{"settings.profile_name":clean}})
	return bool(result.ok)

func is_sandbox() -> bool:
	return is_instance_valid(repository) and str(repository.data.settings.get("profile_kind","normal"))=="sandbox"

func sandbox_rules() -> Dictionary:
	return repository.data.settings.get("sandbox_rules",{}).duplicate(true) if is_sandbox() else {}

func update_sandbox_rule(key: String, value: bool) -> void:
	if not is_sandbox():return
	var rules=sandbox_rules()
	if key=="all":
		for name in ["invincible","unlimited_power","no_overheat"]: rules[name]=value
	elif key in ["invincible","unlimited_power","no_overheat"]: rules[key]=value
	else: return
	update_setting("sandbox_rules",rules)
	if is_instance_valid(pilot) and bool(rules.get("unlimited_power",false)): pilot.battery=100.0

func preview_build(build: Dictionary) -> void:
	if not is_instance_valid(hangar_root):return
	if is_instance_valid(preview):preview.queue_free()
	preview=FleetVisualsV2.make_drone(str(build.get("airframe_id",selected_frame)),build.get("slots",{}))
	if hangar_root.has_method("mount_preview"):hangar_root.mount_preview(preview)
	else:
		hangar_root.add_child(preview)
		preview.position=Vector3(-3,1.8,1)
		preview.scale=Vector3.ONE*3.0

func camera_zoom(steps: float) -> void:
	if not flight_active:return
	if flight_camera.overview:
		camera.size=clampf(camera.size*pow(0.86,steps),40.0 if night else 120.0,1000.0)
		return
	flight_camera.zoom(steps)
	if is_instance_valid(tutorial): tutorial.on_ui_action("zoom")

func recenter_camera() -> void:
	if not is_instance_valid(pilot):return
	if flight_camera.overview: flight_camera.overview_focus=pilot.global_position
	else: _snap_camera()

func open_overview() -> void:
	if not flight_active or flight_camera.overview:return
	pause_game("map")
	overview_fog_enabled=environment.environment.fog_enabled
	environment.environment.fog_enabled=false
	flight_camera.enter_overview(get_viewport().get_visible_rect().size)
	if night:
		flight_camera.overview_focus=pilot.global_position
		camera.size=80.0
	if is_instance_valid(world):world.visible=false
	if is_instance_valid(living):living.visible=false
	if is_instance_valid(combat_feedback):combat_feedback.set_feedback_enabled(false)
	if is_instance_valid(overview_proxy):overview_proxy.visible=true
	if is_instance_valid(night_visibility):night_visibility.update_state(pilot.global_position,pilot.heading,true)
	ui.show_map()

func _restore_overview() -> void:
	if not flight_camera.overview:return
	flight_camera.exit_overview(pilot.global_position)
	environment.environment.fog_enabled=overview_fog_enabled
	if is_instance_valid(world):world.visible=true
	if is_instance_valid(living):living.visible=true
	if is_instance_valid(combat_feedback):combat_feedback.set_feedback_enabled(true)
	if is_instance_valid(overview_proxy):overview_proxy.visible=false
	if is_instance_valid(night_visibility):night_visibility.update_state(pilot.global_position,pilot.heading,false)

func close_overview() -> void:
	_restore_overview()
	resume_game()

func pan_overview(delta_xz: Vector2) -> void:
	flight_camera.pan_overview(delta_xz)

func pan_overview_pixels(pixel_delta: Vector2) -> void:
	var scale_m=camera.size/maxf(1.0,get_viewport().get_visible_rect().size.y)
	var shift=(-camera.global_basis.x*pixel_delta.x+camera.global_basis.y*pixel_delta.y)*scale_m
	flight_camera.pan_overview(Vector2(shift.x,shift.z))

func set_waypoint(point: Vector3) -> void:
	if not point.is_finite():return
	service_navigation_id = ""
	waypoint=Vector3(clampf(point.x,0,600),world.surface_height(point)+0.2,clampf(point.z,0,500))
	if is_instance_valid(waypoint_marker):waypoint_marker.queue_free()
	waypoint_marker=Node3D.new()
	play_root.add_child(waypoint_marker)
	waypoint_marker.position=waypoint
	GameVisuals.ring(waypoint_marker,Vector3.ZERO,2.5,Color("eac07c"),0.13)
	GameVisuals.cylinder(waypoint_marker,Vector3.UP*2.0,0.07,4.0,Color("eac07c"))
	notify("导航点已设置 · 返回飞行后沿金色标记前进")

func _tutorial_action_completed(action: Dictionary) -> void:
	if not is_instance_valid(tutorial):return
	var event={"pickup":"cargo_pickup","deliver":"delivery","scan":"scan","gate":"route"}.get(str(action.get("type","")),"")
	if not event.is_empty():tutorial.on_task_event(event,{"confirmed":true,"stable_delivery":event=="delivery"})
	if str(action.get("type","")) in ["deliver","escort"]:tutorial.on_task_event("route",{"confirmed":true})

func _update_weather(delta: float) -> void:
	var sample=pilot.environment_sample
	var rain=float(sample.get("rain",sample.get("wetness",0.0)))
	var fog=float(sample.get("fog",0.0))
	var env=environment.environment
	env.fog_enabled=fog>0.02 or rain>0.15
	env.fog_density=0.0003+fog*0.0025+rain*0.0007
	env.fog_light_color=Color("a6c3c5") if not night else Color("304b58")
	if float(sample.get("nav_quality",1.0))<0.8:navigation_was_degraded=true
	elif navigation_was_degraded and float(sample.get("nav_quality",1.0))>0.95:
		navigation_was_degraded=false
		if is_instance_valid(tutorial):tutorial.on_task_event("interference",{"confirmed":true})
	weather_audio_clock+=delta
	if weather_audio_clock>=0.15 and is_instance_valid(audio) and audio.has_method("update_environment"):
		weather_audio_clock=0.0
		var machinery_gain=0.0
		if is_instance_valid(living):
			var running=(region_id=="R2" and living.field.fan_enabled) or (region_id=="R4" and not living.platform_locked)
			machinery_gain=(0.4 if running else 0.04)*clampf(1.0-pilot.global_position.distance_to(living.anchor)/70.0,0,1)
		audio.update_environment({"listener_position":pilot.global_position,"wind":clampf(world.current_wind.length()/10.0,0,1),"rain":rain,"region_id":region_id,"night":night,"traffic":0.35 if region_id=="R1" else 0.15,"machinery":machinery_gain})

func _environment_event(event: Dictionary) -> void:
	var kind=str(event.get("kind",""))
	if kind=="environment_warning":
		notify("附近预警 · "+str(event.get("event_label","局部环境变化"))+"，约 %.0f 秒后出现，可绕行或暂候。" % float(event.get("event_seconds",4)))
	elif kind=="environment_active":
		var effect=str(event.get("event_kind",""))
		if not environment_explained.has(effect):
			environment_explained[effect]=true
			if effect in ["vent_pulse","coastal_gust","updraft"] and is_instance_valid(audio):audio.play_voice("cargo_wind",false)
	elif kind=="environment_cleared": notify("局部环境已恢复，继续自由飞行。")
	if str(event.get("kind",""))=="interference_enter": navigation_was_degraded=true
	elif str(event.get("kind",""))=="interference_exit" and navigation_was_degraded:
		navigation_was_degraded=false
		if is_instance_valid(tutorial):tutorial.on_task_event("interference",{"confirmed":true})
	if is_instance_valid(audio) and audio.has_method("play_environment_event"):
		audio.play_environment_event(str(event.get("kind","mechanical")),event.get("position",Vector3.ZERO))

func _update_tutorial_evidence(delta: float) -> void:
	if not is_instance_valid(combat):return
	if int(combat._warning_serial)>tutorial_warning_serial:
		if tutorial_warning_serial==0 and str(current_job.get("id",""))=="M01":
			notify("敌机正在瞄准：留意预警线，移动到建筑后躲避。")
			if is_instance_valid(audio):audio.play_voice("cover",false)
		tutorial_warning_serial=int(combat._warning_serial)
		tutorial_cover_pending=true
	if not tutorial_cover_pending:return
	var alive=0
	var exposed=false
	for enemy in combat.enemies:
		if not is_instance_valid(enemy) or enemy.hp<=0:continue
		alive+=1
		if combat.line_clear(enemy.global_position,pilot.global_position,enemy.get_rid(),pilot.get_rid()):exposed=true
	tutorial_cover_seconds=tutorial_cover_seconds+delta if alive>0 and not exposed else 0.0
	if tutorial_cover_seconds>=1.0:
		tutorial.on_task_event("cover",{"confirmed":true})
		tutorial_cover_pending=false
		tutorial_cover_seconds=0.0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	content = CatalogV2.content()
	var path = "user://profiles/default"
	for argument in OS.get_cmdline_user_args():
		# Profile isolation is also available to exported-build checks; test inputs remain debug-only.
		if argument.begins_with("--v2-qa="):
			qa_mode = true
			qa_path = argument.trim_prefix("--v2-qa=").validate_filename()
			path = "user://qa_v2/session_" + qa_path
	if qa_mode and profiles.base_path == "user://profiles":
		# The standalone QA repository below remains session_<case> for existing harnesses.
		# Profile selection has separate QA-only saves; it must never enumerate player saves.
		# Preserve a catalog explicitly installed by an isolated test fixture.
		profiles = ProfileCatalog.new(path.path_join("profiles"),path.path_join("nonexistent_legacy_source"))
		profiles.initialize()
	if not qa_mode:
		profiles.initialize()
		path = "user://profiles/"+profiles.selected
	if qa_mode:
		repository = SaveRepositoryV2.new(path)
		repository.load_profile()
	else: repository=profiles.open_profile(profiles.selected)
	if int(repository.data.generation) == 0 and not repository.read_only:
		repository.commit({"id":"profile:init", "set":{"settings.auto_fire":true}})
	active_build = selected_build()
	selected_frame = str(active_build.airframe_id)
	input = PilotInputV2.new()
	add_child(input)
	input.configure_input(repository.data.settings.get("input",{}))
	input.mode = str(repository.data.settings.get("control_mode","assisted"))
	input.pause_requested.connect(func(reason): pause_game(reason))
	phone = PhoneServerV2.new()
	add_child(phone)
	phone.input_frame.connect(input.receive_phone)
	phone.suspended.connect(func(reason):
		if input.source == "phone": input.clear(); pause_game("phone:"+reason))
	phone.status_changed.connect(_phone_changed)
	phone.resume_requested.connect(func():
		if flight_camera.overview: close_overview()
		elif flight_active: resume_game())
	_setup_view()
	if ResourceLoader.exists("res://scripts/v2/game_audio.gd"):
		audio = load("res://scripts/v2/game_audio.gd").new()
		add_child(audio)
	ui = GameInterfaceV2.new()
	ui.session = self
	add_child(ui)
	if ResourceLoader.exists("res://scripts/v2/tutorial_director.gd"):
		tutorial=load("res://scripts/v2/tutorial_director.gd").new()
		add_child(tutorial)
		tutorial.configure(self)
	apply_settings()
	show_hangar()
	if not qa_mode and ui.has_method("show_splash"):
		ui.show_splash(func(): ui.show_profiles())
	if not profiles.notice.is_empty(): notify(profiles.notice)
	if not repository.notice.is_empty(): notify(repository.notice)
	get_tree().auto_accept_quit = false
	if qa_mode and "--v2-verify-release" in OS.get_cmdline_user_args():
		var verifier = load("res://scripts/v2/release_verifier.gd").new()
		verifier.game = self
		add_child(verifier)

func _setup_view() -> void:
	environment = WorldEnvironment.new()
	var env = Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color("a9c9d2")
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("c9dfdf")
	env.ambient_light_energy = 0.75
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	environment.environment = env
	add_child(environment)
	sun = DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-48,-30,0)
	sun.light_color = Color("ffedcd")
	sun.light_energy = 1.0
	add_child(sun)
	camera = Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 38
	camera.near = 0.1
	camera.far = 230
	add_child(camera)
	camera.current = true
	flight_camera.configure(camera)

func selected_build() -> Dictionary:
	for build in repository.data.builds:
		if build.build_id == repository.data.selected_build_id: return build.duplicate(true)
	return CatalogV2.default_build()

func region_unlocked(id: String) -> bool:
	if is_sandbox(): return id in ["R1","R2","R3","R4"]
	if id not in ["R1","R2","R3","R4"]: return false
	var gate = {"R1":"","R2":"M04","R3":"M08","R4":"M12"}[id]
	return gate.is_empty() or gate in repository.data.campaign.completed_missions

func job_unlocked(job: Dictionary) -> bool:
	if is_sandbox(): return true
	if not region_unlocked(str(job.region_id)): return false
	var prerequisite = job.get("prerequisite_mission", null)
	if job.has("unlock_required_mission") and str(job.unlock_required_mission) not in repository.data.campaign.completed_missions: return false
	return prerequisite == null or str(prerequisite) in repository.data.campaign.completed_missions

func get_region(id: String) -> Dictionary:
	for value in content.regions:
		if value.id == id: return value
	return content.regions[0]

func available_outposts(id: String) -> Array:
	var result: Array = []
	var region = get_region(id)
	for poi in region.pois:
		if is_sandbox() or poi.id == region.spawn_poi or poi.id in repository.data.world.outposts: result.append(poi)
	return result

func all_jobs() -> Array:
	return content.missions + content.airframe_challenges + content.mode_configs

func get_job(id: String) -> Dictionary:
	for value in all_jobs():
		if value.id == id: return value
	return {}

func show_hangar() -> void:
	_leave_flight(_enter_hangar)

func quit_safely() -> void:
	_leave_flight(func(): get_tree().quit())

func _leave_flight(next: Callable) -> void:
	if not pending_transaction.is_empty(): ui.show_save_error("请先完成待处理保存"); return
	var updates:Dictionary={}
	if flight_active and is_instance_valid(encounter_director) and not bool(current_job.get("training",false)):
		updates["world.combat_regions."+region_id]=encounter_director.snapshot()
	var checkpoint: Variant = repository.data.campaign.active_checkpoint
	if flight_active and current_job.has("stages") and checkpoint is Dictionary and checkpoint.get("job_id","")==current_job.id and checkpoint.get("run_id","")==run_id:
		# Resume at the committed stage boundary, but never erase the run's conditions or time.
		var updated: Dictionary = checkpoint.duplicate(true)
		updated["conditions"] = run_conditions.duplicate(true)
		updated["seconds"] = run_seconds
		if is_instance_valid(living): updated["environment_state"]=living.snapshot()
		updated["damage_state"]=pilot.damage_snapshot()
		updates["campaign.active_checkpoint"]=updated
	if not updates.is_empty():_transact({"id":"suspend:"+run_id+":"+str(Time.get_ticks_usec()),"set":updates},next)
	else:next.call()

func _enter_hangar() -> void:
	service_navigation_id = ""
	if is_instance_valid(ui):ui.toast("")
	get_tree().paused = false
	pause_reasons.clear()
	flight_active = false
	if is_instance_valid(phone) and phone.get_status().active: phone.suspend_control("hangar")
	active_build = selected_build()
	selected_frame = str(active_build.airframe_id)
	input.active = false
	input.clear()
	if is_instance_valid(play_root): play_root.queue_free()
	visibility_controller = null
	if is_instance_valid(night_visibility):night_visibility.set_night(false)
	night_visibility=null
	world = null; pilot = null; runner = null; combat = null; living = null
	encounter_director=null;combat_feedback=null
	flight_camera.overview=false
	waypoint=Vector3.INF
	current_job = {}
	if is_instance_valid(audio): audio.update_flight({},false,region_id,night)
	if is_instance_valid(hangar_root): hangar_root.queue_free()
	if ResourceLoader.exists("res://scripts/v2/hangar_stage.gd"):
		hangar_root=load("res://scripts/v2/hangar_stage.gd").new()
		add_child(hangar_root)
		hangar_root.configure(repository.data.settings)
	else:
		hangar_root = Node3D.new()
		add_child(hangar_root)
		StreetDressingV2.slab(hangar_root,Vector3(0,-0.45,0),Vector3(35,0.6,28),1,Color("526c72"))
		for side in [-1,1]:
			for mark in range(7):
				GameVisuals.box(hangar_root,Vector3(side*5.3,-0.10,-6+mark*1.8),Vector3(0.25,0.03,0.85),Color("d6b975"))
			StreetDressingV2.prop(hangar_root,"utility_cabinet",Vector3(side*7,0,-3),PI/2*side)
			StreetDressingV2.prop(hangar_root,"street_lamp",Vector3(side*6,0,-6))
			StreetDressingV2.prop(hangar_root,"planter",Vector3(side*10,0,0))
		StreetDressingV2.prop(hangar_root,"bicycle_rack",Vector3(-9,0,-4))
		StreetDressingV2.prop(hangar_root,"wayfinding_sign",Vector3(7,0,-7))
		GameVisuals.cylinder(hangar_root,Vector3(0,0,0),4.3,0.4,Color("c8d4d1"))
		GameVisuals.ring(hangar_root,Vector3(0,0.22,0),3.8,Color("56c9b7"),0.13)
		for x in [-8,8]:
			GameVisuals.box(hangar_root,Vector3(x,0.8,3),Vector3(3.2,1.6,2.2),Color("526c79"))
			GameVisuals.asset(hangar_root,"crate",Vector3(x,1.6,3))
		GameVisuals.asset(hangar_root,"hangar",Vector3(0,0,-10),1.2)
	preview_frame(selected_frame)
	camera.size = 17.0
	camera.position = Vector3(13,15,19)
	camera.look_at(Vector3(3.2,0.8,0),Vector3.UP)
	if hangar_root.has_method("camera_pose"):
		var pose: Dictionary=hangar_root.camera_pose()
		camera.position=pose.position
		camera.look_at(pose.target,Vector3.UP)
		camera.size=float(pose.size)
	set_lighting(false)
	ui.show_hangar(selected_page)
	if is_instance_valid(audio) and audio.has_method("set_context"): audio.set_context("hangar")

func preview_frame(id: String) -> void:
	selected_frame = id
	if is_instance_valid(preview): preview.queue_free()
	if not is_instance_valid(hangar_root): return
	preview = FleetVisualsV2.make_drone(id,active_build.slots if id == active_build.airframe_id else CatalogV2.default_build(id).slots)
	if hangar_root.has_method("mount_preview"):
		hangar_root.mount_preview(preview)
		return
	hangar_root.add_child(preview)
	preview.position = Vector3(-3.0,1.8,1)
	preview.scale = Vector3.ONE * 3.0

func _ensure_world_layout() -> bool:
	var result = repository.ensure_layout_revision()
	if result.ok: return true
	notify("区域更新存档尚未完成："+str(result.error)+"；原存档已保留，请重试。")
	return false

func launch_job(id: String, resume = false) -> void:
	if not _ensure_world_layout(): return
	var job = get_job(id)
	if job.is_empty() or not job_unlocked(job): notify("请先完成前置任务"); return
	var loaner = bool(job.get("loaner",false))
	var build = selected_build()
	if loaner:
		build = CatalogV2.default_build(str(job.airframe_id))
		var tools: Array = job.get("loaner_tool_sequence", ["scan_base"])
		build.slots.tool = tools[0] if not tools.is_empty() else "scan_base"
		if job.has("loaner_utility"): build.slots.utility = job.loaner_utility
	var resolved = CatalogV2.resolve_build(build,0,repository.data.owned_airframes,repository.data.owned_modules,loaner)
	if not resolved.valid: notify("当前配装无效，请先在配装台修正"); return
	var additions: Array = []
	if not loaner:
		for grant in content.economy.free_tools:
			if grant.mission == id: additions.append(content.catalog.free_tool_map[grant.id])
	var checkpoint: Variant = repository.data.campaign.active_checkpoint
	var next_stage = 0
	var next_run = Crypto.new().generate_random_bytes(8).hex_encode()
	var next_time = 0.0
	var is_repeat = id in repository.data.campaign.completed_missions
	var restore_checkpoint = checkpoint is Dictionary and checkpoint.get("job_id", "") == id and (resume or not is_repeat)
	if restore_checkpoint:
		next_stage = int(checkpoint.get("stage_index",0))
		next_run = str(checkpoint.get("run_id",next_run))
		next_time = float(checkpoint.get("seconds",0))
		night = bool(checkpoint.get("night",night))
		is_repeat = bool(checkpoint.get("repeat",false))
	if job.has("stages"): next_stage = clampi(next_stage,0,job.stages.size()-1)
	var variant = str(job.get("time_variant","both"))
	if variant in ["night","day"]: night = variant == "night"
	var checkpoint_value = {"layout_revision":1,"job_id":id,"stage_index":next_stage,"run_id":next_run,"seconds":next_time,"repeat":is_repeat,"night":night}
	checkpoint_value["conditions"] = {"difficulty":int(repository.data.settings.get("difficulty",0)),"control_profile_hash":JSON.stringify(input.legacy.config).sha256_text(),"control_modes_used":[input.mode],"auto_fire_used":bool(repository.data.settings.get("auto_fire",true)),"practice":false}
	if restore_checkpoint and checkpoint.has("run_state"): checkpoint_value.run_state = checkpoint.run_state.duplicate(true)
	if restore_checkpoint and checkpoint.has("conditions"): checkpoint_value.conditions = checkpoint.conditions.duplicate(true)
	for key in ["environment_state","damage_state"]:
		if restore_checkpoint and checkpoint.has(key): checkpoint_value[key] = checkpoint[key].duplicate(true)
	var launch_receipt = "resume:"+next_run+":"+str(repository.data.generation) if restore_checkpoint else "launch:"+next_run
	var tx = {"id":launch_receipt,"append":{"owned_modules":additions}}
	if job.has("stages"): tx["set"] = {"campaign.active_checkpoint":checkpoint_value}
	var result = repository.commit(tx)
	if not result.ok: notify("出航保存失败："+str(result.error)); return
	current_job = job.duplicate(true)
	stage_index = next_stage
	run_id = next_run
	run_seconds = next_time
	run_parts = 0
	repeat_run = is_repeat
	active_build = build
	# Read the authority after commit; a pre-commit alias may still contain the previous layout.
	var committed_checkpoint: Dictionary = repository.data.campaign.active_checkpoint if job.has("stages") else checkpoint_value
	restored_run_state = committed_checkpoint.get("run_state",{}).duplicate(true) if restore_checkpoint else {}
	restored_conditions = committed_checkpoint.get("conditions",{}).duplicate(true) if restore_checkpoint else {}
	restored_environment=committed_checkpoint.get("environment_state",{}).duplicate(true) if restore_checkpoint else {}
	restored_damage=committed_checkpoint.get("damage_state",{}).duplicate(true) if restore_checkpoint else {}
	region_id = str(job.region_id)
	_build_flight(resolved)

func retry_current_run() -> void:
	# Keep practice/exploration semantics and preserve the formal campaign checkpoint.
	if bool(current_job.get("training",false)):
		launch_tutorial_practice(str(current_job.get("id","")))
	elif bool(current_job.get("exploration",false)):
		launch_exploration(str(current_job.get("region_id",region_id)))
	else:
		launch_job(str(current_job.get("id","")),true)

func launch_tutorial_practice(id: String) -> void:
	if not _ensure_world_layout(): return
	if id not in ["M01","M02","M03"]:return
	var job=get_job(id)
	if job.is_empty() or not job_unlocked(job):notify("请先完成前置任务");return
	# A fresh loaner session never replaces the player's formal checkpoint/build.
	current_job=job.duplicate(true)
	current_job["training"]=true
	current_job["loaner"]=true
	current_job["loaner_tool_sequence"]=content.catalog.free_tool_map.values()
	current_job["loaner_utility"]="guard_base"
	current_job["name"]=str(job.name)+" · 独立练习"
	stage_index=0;run_seconds=0;run_parts=0;repeat_run=false
	run_id="training:"+Crypto.new().generate_random_bytes(8).hex_encode()
	restored_run_state={};restored_conditions={};restored_environment={}
	restored_damage={}
	active_build=CatalogV2.default_build("tr01")
	active_build.slots.tool="hook_base" if id=="M02" else "scan_base"
	region_id=str(job.region_id)
	_build_flight(CatalogV2.resolve_build(active_build))
	if is_instance_valid(tutorial):tutorial.auto_start(id)
	notify("独立练习从第一阶段开始，借用工具；原任务进度与奖励保持不变。")

func launch_exploration(id: String) -> void:
	if not _ensure_world_layout(): return
	restored_environment={}
	restored_damage={}
	if not region_unlocked(id): notify("该地区尚未开放"); return
	restored_conditions = {}
	restored_run_state = {}
	active_build = selected_build()
	var resolved = CatalogV2.resolve_build(active_build,0,repository.data.owned_airframes,repository.data.owned_modules)
	if not resolved.valid: notify("请先恢复合法配装"); return
	region_id = id
	current_job = {"id":"explore:"+id,"name":"自由探索","region_id":id,"exploration":true}
	run_id = Crypto.new().generate_random_bytes(8).hex_encode()
	run_seconds = 0; run_parts = 0
	_build_flight(resolved)

func _build_flight(resolved: Dictionary) -> void:
	run_completed_stages.clear()
	regions_at_departure.clear()
	run_result_success = false
	for region in content.regions:
		if region_unlocked(str(region.id)): regions_at_departure.append(str(region.id))
	service_navigation_id = ""
	if is_instance_valid(ui):ui.toast("")
	get_tree().paused = false
	pause_reasons.clear()
	if is_instance_valid(hangar_root): hangar_root.queue_free()
	if is_instance_valid(play_root): play_root.queue_free()
	play_root = Node3D.new()
	play_root.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(play_root)
	world = RegionWorldV2.new()
	world.configure(get_region(region_id),night,repository.data.world)
	world.wind_enabled = str(current_job.get("id","")) != "M01"
	world.completed_missions = repository.data.campaign.completed_missions.duplicate()
	world.completed_stages = repository.data.campaign.completed_stages.duplicate()
	world.active_job_id = str(current_job.get("id",""))
	play_root.add_child(world)
	if ResourceLoader.exists("res://scripts/v2/living_environment.gd"):
		living=load("res://scripts/v2/living_environment.gd").new()
		play_root.add_child(living)
		living.configure(world,region_id,region_id.hash(),repository.data.settings.merged({"wind_enabled":world.wind_enabled}))
		living.environment_event.connect(_environment_event)
		world.living=living
		if not restored_environment.is_empty(): living.restore(restored_environment)
	overview_proxy=CameraRig.build_overview(world)
	play_root.add_child(overview_proxy)
	world.discovered.connect(_discovered)
	world.scenery_used.connect(func(): play_sound("ui"))
	world.secret_prepared.connect(func(id,step):
		if bool(run_conditions.get("practice",false)): return
		var result = repository.commit({"id":"secret:"+id+":"+str(step),"set":{"world.secret_steps."+id:step}})
		if not result.ok: world.secret_steps[id] = maxi(0,step-1); notify("线索进度尚未保存"))
	pilot = FlightBodyV2.new()
	pilot.configure(resolved)
	pilot.set_meta("unit_id","pilot:"+run_id)
	pilot.set_meta("entity_id","pilot:"+run_id)
	if not restored_damage.is_empty():pilot.restore_damage_state(restored_damage)
	if is_instance_valid(living): pilot.environment_query=living.sample
	pilot.practice = bool(current_job.get("training",false)) or (bool(current_job.get("exploration",false)) and int(repository.data.settings.get("difficulty",0)) == 0 and bool(repository.data.settings.get("practice_invincible",false)))
	play_root.add_child(pilot)
	var start_id = str(world.region.spawn_poi)
	if bool(current_job.get("exploration",false)):
		for outpost in available_outposts(region_id):
			if outpost.id == departure_poi_id: start_id = departure_poi_id
	if current_job.has("stages") and stage_index > 0: start_id = str(current_job.stages[stage_index].equipment_plan.get("entry_service_poi",start_id))
	# Suspended cargo is restored 1.5m below the pilot; a 1.2m launch would
	# initialize its collider below the new terrain before the first physics tick.
	var launch_height=1.2
	for record in restored_run_state.get("cargo_records",{}).values():
		if str(record.get("state",""))=="carried":launch_height=2.8;break
	pilot.global_position = world.poi_position(start_id) + Vector3(0,launch_height,0)
	pilot.hold_height = pilot.global_position.y
	pilot.safe_position=pilot.global_position
	pilot.sandbox_rules=sandbox_rules()
	pilot.water_entered.connect(func():
		if is_instance_valid(audio) and audio.has_method("play_environment_event"): audio.play_environment_event("splash",pilot.global_position))
	pilot.rescued.connect(func(): notify("救援浮标已将无人机送回最近安全位置"))
	visibility_controller = VisibilityController.new()
	play_root.add_child(visibility_controller)
	visibility_controller.configure(camera, pilot)
	for occluder in world.visibility_occluders: visibility_controller.register_occluder(occluder)
	world.visibility_occluder_added.connect(visibility_controller.register_occluder)
	pilot.disabled.connect(func(): fail_run("机体已停机，已提交的阶段进度保留"))
	pilot.damage_resolved.connect(_pilot_damage)
	combat = CombatV2.new()
	tutorial_warning_serial=0
	tutorial_cover_pending=false
	tutorial_cover_seconds=0.0
	combat.pilot = pilot
	combat.target_visibility=night_point_visible
	combat.perception_visibility=enemy_perception_visible
	combat.environment_query=combat_environment_at
	combat.navigation_world=world
	combat.combat_seed=run_id.hash()
	combat.auto_fire = bool(repository.data.settings.get("auto_fire",true))
	combat.difficulty = int(restored_conditions.get("difficulty",repository.data.settings.get("difficulty",0)))
	run_conditions = {"difficulty":combat.difficulty,"control_profile_hash":JSON.stringify(input.legacy.config).sha256_text(),"control_modes_used":[input.mode],"auto_fire_used":combat.auto_fire,"practice":pilot.practice}
	if not restored_conditions.is_empty():
		run_conditions = restored_conditions.duplicate(true)
		if input.mode not in run_conditions.control_modes_used: run_conditions.control_modes_used.append(input.mode)
		run_conditions.auto_fire_used = bool(run_conditions.get("auto_fire_used",false)) or combat.auto_fire
	play_root.add_child(combat)
	combat.combat_event.connect(_combat_event)
	if is_instance_valid(audio) and audio.has_method("reset_combat_audio"):audio.reset_combat_audio(run_id)
	if not bool(current_job.get("exploration",false)):
		runner = TaskRunnerV2.new()
		runner.world = world
		runner.pilot = pilot
		runner.combat = combat
		play_root.add_child(runner)
		runner.stage_ready.connect(_stage_complete)
		runner.failed.connect(fail_run)
		runner.action_changed.connect(func(): play_sound("tool"))
		runner.action_completed.connect(_tutorial_action_completed)
		var stage = current_job.stages[stage_index] if current_job.has("stages") else current_job
		if not restored_run_state.is_empty(): runner.resume_stage(stage,restored_run_state)
		else: runner.start_stage(stage)
	input.clear()
	input.reset_throttle()
	input.active = true
	flight_active = true
	if ResourceLoader.exists("res://scripts/v2/night_visibility.gd"):
		night_visibility=load("res://scripts/v2/night_visibility.gd").new()
		play_root.add_child(night_visibility)
		night_visibility.configure(camera,world,pilot,living)
	encounter_director=load("res://scripts/v2/encounter_director.gd").new()
	play_root.add_child(encounter_director)
	encounter_director.configure(combat,world,pilot,region_id,run_id.hash(),not qa_mode)
	var saved_directors:Dictionary=repository.data.world.get("combat_regions",{})
	if saved_directors.has(region_id):encounter_director.restore(saved_directors[region_id])
	combat_feedback=load("res://scripts/v2/combat_feedback.gd").new()
	play_root.add_child(combat_feedback)
	combat_feedback.configure(combat,pilot,camera,combat_point_visible,bool(repository.data.settings.get("reduced_motion",false)))
	combat_feedback.text_scale=clampf(float(repository.data.settings.get("ui_scale",1.0)),1,1.5)
	combat_feedback.shake_requested.connect(func(strength,direction):flight_camera.impact(strength,direction))
	combat_feedback.wreck_impact.connect(func(event):
		if is_instance_valid(audio):audio.play_combat_event(event))
	critical_warning_left=0;combat_context_left=0;approach_audio_left=0
	flight_camera.target_size=clampf(float(repository.data.settings.get("camera_zoom",32.0)),12.0,70.0)
	camera.size=flight_camera.target_size
	set_lighting(night)
	_snap_camera()
	ui.show_hud()
	if is_instance_valid(tutorial) and not qa_mode and str(current_job.get("id","")) in ["M01","M02","M03"]: tutorial.auto_start(str(current_job.id))
	if is_instance_valid(audio) and audio.has_method("set_context"): audio.set_context("explore" if current_job.get("exploration",false) else "action")
	apply_settings()
	if input.source == "phone" and not phone.get_status().active: pause_game("phone:neutral_required")

func _stage_complete(stage: Dictionary) -> void:
	if not flight_active or pause_reasons.has("result") or not pending_transaction.is_empty(): return
	if current_job.has("stages") and str(stage.get("id","")) != str(current_job.stages[stage_index].id): return
	var restorations: Array = runner.staged_restorations.duplicate()
	if bool(run_conditions.get("practice",false)):
		_apply_scene_restorations(restorations)
		if str(stage.get("id","")) not in run_completed_stages: run_completed_stages.append(str(stage.get("id","")))
		if current_job.has("stages") and stage_index+1 < current_job.stages.size(): stage_index += 1; runner.start_stage(current_job.stages[stage_index])
		else: run_result_success = true; _show_result("练习完成","本次未写入奖励或正式成绩")
		return
	if runner.optional:
		var tx = {"id":"optional:"+str(current_job.id)+":"+run_id,"parts_delta":int(current_job.get("optional_delivery_parts",0))}
		_transact(tx,func():
			run_parts += int(tx.parts_delta)
			_apply_scene_restorations(restorations)
			runner.start_stage(current_job.stages[stage_index]))
		return
	if not current_job.has("stages"): _complete_side_job(restorations); return
	var final_stage = stage_index == current_job.stages.size()-1
	var first = str(stage.reward_id) not in repository.data.ledger.receipts
	var reward = int(stage.first_reward_parts) if first else 0
	var tx_id = str(stage.reward_id) if first else "stage:"+run_id+":"+str(stage.id)
	var updates: Dictionary = {}
	for id in stage.poi_ids: updates["world.restored_objects."+str(id)] = true
	var next_state: Dictionary = {}
	if not final_stage:
		var saved = runner.snapshot_run_state()
		next_state = {"stage_id":current_job.stages[stage_index+1].id,"action_index":0,"elapsed_s":0,"cargo_records":saved.cargo_records,"preparation_flags":saved.preparation_flags,"stage_start_cargo":saved.cargo_records,"stage_start_flags":saved.preparation_flags,"metrics":{},"optional":false}
	updates["campaign.active_checkpoint"] = null if final_stage else {"layout_revision":1,"job_id":current_job.id,"stage_index":stage_index+1,"run_id":run_id,"seconds":run_seconds,"repeat":repeat_run,"night":night,"run_state":next_state,"conditions":run_conditions.duplicate(true)}
	if not final_stage:
		updates["campaign.active_checkpoint"]["damage_state"] = pilot.damage_snapshot()
		if is_instance_valid(living): updates["campaign.active_checkpoint"]["environment_state"] = living.snapshot()
	if is_instance_valid(encounter_director): updates["world.combat_regions."+region_id] = encounter_director.snapshot()
	var append = {"campaign.completed_stages":[stage.id]}
	if final_stage:
		append["campaign.completed_missions"] = [current_job.id]
		if content.catalog.outpost_unlocks.has(current_job.id): append["world.outposts"] = [content.catalog.outpost_unlocks[current_job.id]]
		append["records"] = [_record("complete")]
		if repeat_run: reward += int(current_job.get("repeat_reward_parts",30))
	var tx = {"id":tx_id,"parts_delta":reward,"set":updates,"append":append}
	_transact(tx,func():
		run_parts += reward
		if str(stage.id) not in run_completed_stages: run_completed_stages.append(str(stage.id))
		world.completed_missions = repository.data.campaign.completed_missions.duplicate()
		world.completed_stages = repository.data.campaign.completed_stages.duplicate()
		for poi_id in stage.poi_ids: world.restore_object(str(poi_id))
		play_sound("reward")
		notify("阶段已保存，到账 %d 零件" % reward)
		if final_stage: run_result_success = true; _show_result("任务完成",str(current_job.get("world_repair","")))
		else: stage_index += 1; runner.start_stage(current_job.stages[stage_index]))

func _record(outcome: String) -> Dictionary:
	return {"job_id":current_job.id,"run_id":run_id,"outcome":outcome,"seconds":run_seconds,"damage":pilot.damage_taken,"collisions":pilot.collision_count,"airframe_id":pilot.build.airframe_id,"build_hash":pilot.stats.build_hash,"loaner":bool(current_job.get("loaner",false)),"difficulty":run_conditions.get("difficulty",combat.difficulty),"control_mode":input.mode,"auto_fire":combat.auto_fire,"conditions":run_conditions.duplicate(true),"night":night,"content_version":SaveRepositoryV2.CONTENT_VERSION,"profile_kind":"sandbox" if is_sandbox() else "normal","sandbox_rules":sandbox_rules()}

func _apply_scene_restorations(ids: Array) -> void:
	if not is_instance_valid(world): return
	for id in ids: world.restore_object(str(id))

func _complete_side_job(restorations: Array = []) -> void:
	if pause_reasons.has("result") or not pending_transaction.is_empty(): return
	if bool(run_conditions.get("practice",false)):
		_apply_scene_restorations(restorations)
		run_result_success = true; _show_result("练习完成","本次未写入奖励或正式成绩"); return
	for saved in repository.data.records:
		if str(saved.get("run_id","")) == run_id: return
	var id = str(current_job.id)
	var medal = "完成"
	if current_job.has("medal_time_limit_s"):
		var limits: Dictionary = current_job.medal_time_limit_s
		if run_seconds > float(limits.bronze): fail_run("超出铜牌时限，记录本次练习，不扣零件"); return
		medal = "金牌" if run_seconds <= float(limits.gold) else ("银牌" if run_seconds <= float(limits.silver) else "铜牌")
	var first_id = str(current_job.get("reward_id", "job:"+id+":first"))
	var first = first_id not in repository.data.ledger.receipts
	var reward = int(current_job.get("first_reward_parts",60) if first else current_job.get("repeat_reward_parts",25))
	if str(current_job.get("mode","")) == "salvage":
		reward = 0
		for item in runner.record_metrics().get("extraction_manifest",[]): reward += int(item.get("value",item.get("cargo_value",0)))
	var record = _record(medal)
	record["metrics"] = runner.record_metrics()
	var tx = {"id":first_id if first else "job:"+id+":"+run_id,"parts_delta":reward,"append":{"records":[record]}}
	_transact(tx,func():
		run_parts += reward
		_apply_scene_restorations(restorations)
		run_result_success = true
		_show_result(medal,"记录已按机体、配装和辅助条件归档"))

func _transact(tx: Dictionary, next: Callable) -> void:
	pending_transaction = tx.duplicate(true)
	pending_next = next
	var result = repository.commit(tx)
	if not result.ok:
		pause_game("save_error")
		ui.show_save_error(str(result.error))
		return
	pending_transaction.clear()
	pending_next = Callable()
	next.call()

func retry_save() -> void:
	if pending_transaction.is_empty(): return
	var callback = pending_next
	var result = repository.commit(pending_transaction)
	if not result.ok: ui.show_save_error(str(result.error)); return
	pending_transaction.clear(); pending_next = Callable()
	pause_reasons.erase("save_error")
	get_tree().paused = not pause_reasons.is_empty()
	callback.call()
	if flight_active and pause_reasons.is_empty(): input.active = true; ui.show_hud()

func _discovered(poi: Dictionary) -> void:
	if bool(run_conditions.get("practice",false)): return
	var parts = int(poi.reward.get("parts_first_discovery",0))
	var tx = {"id":"discover:"+str(poi.id),"parts_delta":parts,"append":{"world.discovered_pois":[poi.id]}}
	var result = repository.commit(tx)
	if result.ok:
		notify("发现：%s%s" % [poi.name,"  +%d"%parts if parts>0 else ""])
		play_sound("discover")
	else:
		world.known.erase(poi.id)
		notify("发现尚未保存："+str(result.error))

func purchase(id: String, frame = false) -> bool:
	if not (CatalogV2.airframes() if frame else CatalogV2.modules()).has(id): notify("目录项目不存在"); return false
	var item: Dictionary = CatalogV2.airframes()[id] if frame else CatalogV2.modules()[id]
	var owned_key = "owned_airframes" if frame else "owned_modules"
	if id in repository.data[owned_key]: return true
	var required = str(item.get("unlock_mission",""))
	if not required.is_empty() and required not in repository.data.campaign.completed_missions: notify("工程图尚未解锁："+required); return false
	var cost = int(item.get("cost",0))
	if int(repository.data.wallet.parts) < cost: notify("零件不足"); return false
	var append = {owned_key:[id]}
	if frame: append["builds"] = [CatalogV2.default_build(id)]
	var result = repository.commit({"id":"purchase:"+id,"parts_delta":-cost,"append":append})
	if not result.ok: notify("购买未到账："+str(result.error)); return false
	play_sound("reward"); notify("已制造："+str(item.name)); return true

func save_build(build: Dictionary) -> bool:
	var checked = CatalogV2.resolve_build(build,0,repository.data.owned_airframes,repository.data.owned_modules)
	if not checked.valid: return false
	var builds: Array = repository.data.builds.duplicate(true)
	var replaced = false
	for i in range(builds.size()):
		if builds[i].build_id == build.build_id: builds[i] = build.duplicate(true); replaced = true
	if not replaced: builds.append(build.duplicate(true))
	var result = repository.commit({"id":"build:"+Crypto.new().generate_random_bytes(8).hex_encode(),"set":{"builds":builds,"selected_build_id":build.build_id}})
	if result.ok: active_build = build.duplicate(true); selected_frame = str(build.airframe_id); preview_frame(selected_frame)
	else: notify("配装尚未保存："+str(result.error))
	return bool(result.ok)

func switch_service(slot: String, module_id: String) -> void:
	if not is_instance_valid(pilot): return
	var service = world.nearest_service(pilot.global_position)
	var loaner = bool(current_job.get("loaner",false))
	if loaner:
		var allowed: Array = current_job.get("loaner_tool_sequence",["scan_base"])
		if slot == "tool" and module_id not in allowed: notify("此挑战使用固定借用工具"); return
		if slot == "utility" and module_id != str(current_job.get("loaner_utility","guard_base")): notify("此挑战使用固定辅助模块"); return
		if slot not in ["tool","utility"]: return
	if service.is_empty() or not pilot.is_landed(): notify("需在安全服务柜旁着陆停稳"); return
	if combat.nearby_threats()>0: notify("附近正在交战，请先脱离追击"); return
	if pilot.cargo_kg > 0: notify("先在作业座暂存货物"); return
	var build = pilot.build.duplicate(true)
	build.slots[slot] = module_id
	var checked = CatalogV2.resolve_build(build,0,repository.data.owned_airframes,repository.data.owned_modules,loaner)
	if not checked.valid: notify("此配装不合法"); return
	if not loaner and not save_build(build): return
	var condition = pilot.damage_snapshot()
	pilot.configure(checked)
	pilot.restore_damage_state(condition)
	if is_instance_valid(pilot.model): pilot.model.queue_free()
	pilot.rotors.clear()
	pilot.model = FleetVisualsV2.make_drone(str(build.airframe_id),build.slots)
	pilot.add_child(pilot.model); pilot._find_rotors(pilot.model)
	pilot.rebuild_visibility_silhouette()
	active_build = build
	if not is_instance_valid(runner) or equipment_missing_for(build,runner.current_action(),runner.stage).is_empty(): clear_service_guidance()
	notify("换装完成")

func update_setting(key: String, value: Variant) -> void:
	if key=="control_mode":
		if str(value)=="advanced": value="manual_throttle"
		if str(value) not in ["assisted","manual_throttle"]: return
		if flight_active and is_instance_valid(pilot) and not pilot.is_landed(): notify("请先降落，再切换飞行模式"); return
	if flight_active and key in ["difficulty","practice_invincible"]: notify("返回机库后更改此项"); return
	var result = repository.commit({"id":"setting:"+Crypto.new().generate_random_bytes(8).hex_encode(),"set":{"settings."+key:value}})
	if not result.ok: notify("设置未保存"); return
	if key=="control_mode":
		input.clear()
		input.reset_throttle()
	apply_settings()
	if key=="control_mode" and is_instance_valid(phone): phone.refresh_control_mode(input.mode,input.resume_throttle)

func apply_settings() -> void:
	var settings: Dictionary = repository.data.settings
	input.mode = str(settings.get("control_mode","assisted"))
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN if bool(settings.get("fullscreen",false)) else DisplayServer.WINDOW_MODE_WINDOWED)
	var low = str(settings.get("quality","low")) == "low"
	sun.shadow_enabled = not (flight_active and night)
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL if low else DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	sun.directional_shadow_max_distance = 80.0 if low else 120.0
	sun.shadow_normal_bias = 2.5
	sun.shadow_bias = 0.12
	RenderingServer.directional_shadow_atlas_set_size(2048 if low else 4096,true)
	get_viewport().msaa_3d = Viewport.MSAA_DISABLED if low else Viewport.MSAA_2X
	# Godot 4.6+ Compatibility supports radius/intensity SSAO for contact depth.
	environment.environment.ssao_enabled = not low
	environment.environment.ssao_radius = 1.5
	environment.environment.ssao_intensity = 1.2
	if is_instance_valid(audio): audio.set_mix(settings)
	if is_instance_valid(combat): combat.auto_fire = bool(settings.get("auto_fire",true))
	if flight_active and is_instance_valid(pilot):
		pilot.sandbox_rules=sandbox_rules()
		pilot.collision_damage_scale=float(settings.get("environment_damage",1.0))*float({"calm":0.5,"standard":1.0,"realistic":1.5}.get(str(settings.get("environment_preset","standard")),1.0))
		run_conditions["auto_fire_used"] = bool(run_conditions.get("auto_fire_used",false)) or combat.auto_fire
		var modes: Array = run_conditions.get("control_modes_used",[])
		if input.mode not in modes: modes.append(input.mode)
		run_conditions["control_modes_used"] = modes
	if is_instance_valid(living): living.set_settings(settings.merged({"wind_enabled":world.wind_enabled}))
	if is_instance_valid(hangar_root) and hangar_root.has_method("set_reduced_motion"): hangar_root.set_reduced_motion(bool(settings.get("reduced_motion",false)))
	if is_instance_valid(ui): ui.apply_scale(float(settings.get("ui_scale",1.0)))

func set_lighting(is_night: bool) -> void:
	if flight_active:night=is_night
	if is_instance_valid(night_visibility):night_visibility.set_night(is_night and flight_active)
	var env = environment.environment
	env.background_color = Color("030810") if is_night else Color("a9c9d2")
	env.ambient_light_color = Color("6d8faa") if is_night else Color("dce8dc")
	env.ambient_light_energy = 0.50 if is_night else 0.28
	sun.light_energy = 0.14 if is_night else 0.42
	sun.shadow_enabled = not is_night
	sun.light_color = Color("a9d5ef") if is_night else Color("fff4e5")

func _physics_process(delta: float) -> void:
	if not flight_active or get_tree().paused or not is_instance_valid(pilot): return
	input.active = true
	pilot.command = input.command(camera.global_basis)
	for edge in pilot.command.edges:
		match str(edge):
			"utility": pilot.activate_ability()
			"target": pilot.activate_guard()
			"pause": pause_game("manual")
			"map": open_overview()
			"zoom_in": camera_zoom(1)
			"zoom_out": camera_zoom(-1)
			"recenter": recenter_camera()
			"tool": pilot.activate_ability()
	if get_tree().paused: return
	run_seconds += delta
	world.update_stream(pilot.global_position)
	world.wind_time = run_seconds
	world.current_wind = world.wind_acceleration(pilot.global_position,run_seconds,pilot.ground_distance)
	pilot.environment_acceleration=Vector3.ZERO
	if is_instance_valid(living):
		living.update_focus(pilot.global_position)
		pilot.environment_sample=living.sample(pilot.global_position)
		if not world.wind_enabled: pilot.environment_sample["wind_velocity"]=Vector3.ZERO
		world.current_wind=pilot.environment_sample.get("wind_velocity",Vector3.ZERO)
		var surface=world.surface_at(pilot.global_position)
		pilot.environment_sample["water"]=bool(surface.get("water",false))
		pilot.environment_sample["water_height"]=float(surface.get("water_height",-0.6))
		environment_cooldown=maxf(0.0,environment_cooldown-delta)
		var pressed=bool(pilot.command.get("interact",false))
		if pressed and not environment_action_held and environment_cooldown<=0:
			var result: Dictionary=living.interact(pilot.global_position)
			if bool(result.get("used",false)):
				notify(str(result.get("message","设施状态已更新")))
				environment_cooldown=0.7
		environment_action_held=pressed
		_update_weather(delta)
	if is_instance_valid(tutorial) and not qa_mode:
		_update_tutorial_evidence(delta)
		tutorial.physics_update(delta,pilot,input.last_frame)
	var sensor = 24.0 if (pilot.ability_left>0 and pilot.build.airframe_id=="nx04") else 15.0
	world.scan_nearby(pilot.global_position,delta,sensor*float(pilot.environment_sample.get("nav_quality",1.0))*(1.0-float(pilot.component_effects.get("sensor_damage",0))*.35))
	world.work_secrets(pilot,delta)
	world.work_scenery(pilot,delta)
	if is_instance_valid(living):
		var hint = living.get_interaction_hint(pilot.global_position)
		if not hint.is_empty():world.scenery_hint=hint
	phone.set_telemetry(pilot.telemetry.merged({"tool_state":runner.condition if is_instance_valid(runner) else "探索","mode":input.mode,"auto_fire":combat.auto_fire,"resume_throttle":input.throttle,"tutorial_step":str(tutorial.get_state().get("step_id","")) if is_instance_valid(tutorial) else "","tutorial_text":str(tutorial.get_state().get("text","")) if is_instance_valid(tutorial) else ""}))
	if is_instance_valid(audio): audio.update_flight(pilot.telemetry,true,region_id,night)
	_update_combat_context(delta)

var hud_refresh_left=0.0

func _process(delta: float) -> void:
	if qa_mode and DisplayServer.get_name() != "headless":
		var now = Time.get_ticks_usec()
		if previous_usec > 0: frame_samples.append((now-previous_usec)/1000.0)
		previous_usec = now
	if flight_active and is_instance_valid(pilot):
		_update_flight_camera(delta)
		if is_instance_valid(combat_feedback):combat_feedback.reduced_motion=bool(repository.data.settings.get("reduced_motion",false))
		if is_instance_valid(night_visibility):night_visibility.update_state(pilot.global_position,pilot.heading,flight_camera.overview)
		_sync_world_visibility()
		if is_instance_valid(visibility_controller): visibility_controller.update_visibility(delta)
		hud_refresh_left-=delta
		if hud_refresh_left<=0:
			hud_refresh_left=0.1
			ui.update_hud()
		# Heading and the own-aircraft marker remain as smooth as the flight view.
		if is_instance_valid(ui.hud_overlay):ui.hud_overlay.queue_redraw()
	elif is_instance_valid(hangar_root) and hangar_root.has_method("tick"): hangar_root.tick(delta)
	elif is_instance_valid(preview): preview.rotation.y += delta*0.10

func _sync_world_visibility() -> void:
	if is_instance_valid(combat):
		for enemy in combat.enemies:
			if is_instance_valid(enemy) and enemy.has_method("sync_render_visibility"):enemy.sync_render_visibility()
	if is_instance_valid(world):
		for poi in world.region.pois:
			if not bool(poi.hidden) or not world.poi_nodes.has(poi.id):continue
			var node=world.poi_nodes[poi.id]
			if is_instance_valid(node):node.visible=not night or poi.id in world.known or night_point_visible(node.global_position)

func _snap_camera() -> void:
	flight_camera.configure(camera)
	flight_camera.snap(pilot.global_position)
	camera_focus=flight_camera.focus
	camera_lead=flight_camera.lead

func _update_flight_camera(delta: float) -> void:
	flight_camera.update(delta,pilot.global_position,pilot.linear_velocity,bool(repository.data.settings.get("reduced_motion",false)) if is_instance_valid(repository) else false)
	camera_focus=flight_camera.focus
	camera_lead=flight_camera.lead

func pause_game(reason = "manual") -> void:
	if not flight_active: return
	pause_reasons[reason] = true
	input.resume_throttle=input.throttle
	if is_instance_valid(phone): phone.set_telemetry({"mode":input.mode,"resume_throttle":input.resume_throttle})
	input.active = false
	input.clear()
	get_tree().paused = true
	if input.source == "phone" and phone.get_status().active and phone.has_method("suspend_control"): phone.suspend_control(reason)
	if is_instance_valid(ui): ui.show_pause()

func resume_game() -> void:
	if input.source == "keyboard":
		if not input.can_resume(): notify("请松开方向杆；手动模式将油门对齐 %.0f%% 后继续" % (input.resume_throttle*100)); return
		pause_reasons.erase("controller_lost")
	if flight_camera.overview: _restore_overview()
	for key in ["manual","map","service","settings"]: pause_reasons.erase(key)
	if input.source == "phone" and not phone.get_status().active:
		if not phone.resume_control(): notify("手机摇杆回中后，在手机上确认恢复"); return
	if not pause_reasons.is_empty(): notify(ui.pause_status_text()); return
	get_tree().paused = false
	input.clear(); input.active = true
	ui.show_hud()

func _phone_changed() -> void:
	var status = phone.get_status()
	if bool(status.active) and input.source == "phone":
		for key in pause_reasons.keys():
			if str(key).begins_with("phone:"): pause_reasons.erase(key)
		if flight_active and pause_reasons.is_empty(): get_tree().paused = false; input.active = true; ui.show_hud()
	old_phone_active = bool(status.active)

func approve_phone() -> void:
	if phone.approve_control(): input.take_control("phone"); pause_reasons.erase("controller_lost"); pause_game("phone:neutral_required"); notify("手机已获准接管，请回中并确认恢复")
	else: notify("先在手机上完成配对")

func desktop_control() -> void:
	phone.stop_server()
	input.take_control("keyboard")
	pause_reasons.erase("controller_lost")
	for key in pause_reasons.keys():
		if str(key).begins_with("phone:"): pause_reasons.erase(key)
	if flight_active: pause_reasons["manual"] = true
	notify("键盘或已连接手柄接管")

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT and flight_active and is_instance_valid(input) and input.source != "phone" and not (qa_mode and input.test_enabled): pause_game("manual")
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		if flight_active: pause_game("manual"); ui.show_quit()
		else: get_tree().quit()

func _unhandled_input(event: InputEvent) -> void:
	if flight_active and not get_tree().paused:
		if event is InputEventMouseButton and event.pressed:
			if event.button_index==MOUSE_BUTTON_WHEEL_UP: camera_zoom(1)
			elif event.button_index==MOUSE_BUTTON_WHEEL_DOWN: camera_zoom(-1)
		if event is InputEventKey and event.pressed and not event.echo:
			if event.keycode in [KEY_EQUAL,KEY_KP_ADD]: camera_zoom(1)
			elif event.keycode in [KEY_MINUS,KEY_KP_SUBTRACT]: camera_zoom(-1)
			elif event.keycode==KEY_HOME: recenter_camera()
	if event.is_action_pressed("flight_pause"):
		if flight_active:
			if get_tree().paused: resume_game()
			else: pause_game()
	if event.is_action_pressed("flight_capture"): capture()

func result_progress_summary() -> Dictionary:
	var practice = bool(run_conditions.get("practice",false)) or bool(current_job.get("training",false))
	var exploration = bool(current_job.get("exploration",false))
	var result = {"task":str(current_job.get("name","本次出航")),"region":str(get_region(region_id).name),"practice":practice,"stages":[],"new_regions":[],"saved_progress":"","status":""}
	var saved = 0
	for stage in current_job.get("stages",[]):
		if str(stage.id) in run_completed_stages: result.stages.append(str(stage.name))
		if str(stage.id) in repository.data.campaign.completed_stages: saved += 1
	if current_job.has("stages") and not practice: result.saved_progress = "正式修复进度 %d / %d 阶段" % [saved,current_job.stages.size()]
	for region in content.regions:
		if not practice and str(region.id) not in regions_at_departure and region_unlocked(str(region.id)): result.new_regions.append(str(region.name))
	if exploration: result.status = "自由探索结束 · 不计任务阶段"
	elif run_result_success: result.status = "练习目标已完成 · 不发奖励，不改正式进度" if practice else "本次目标已完成"
	else:
		var target = str(runner.current_action().get("label","当前目标")) if is_instance_valid(runner) else "当前目标"
		result.status = ("练习未完成 · " if practice else "未完成目标 · ")+target
		if result.stages.is_empty(): result.status += "
本次尚未提交阶段"
	return result

func _show_result(title: String, subtitle: String) -> void:
	input.active = false
	pause_reasons["result"] = true
	get_tree().paused = true
	if phone.get_status().active: phone.suspend_control("result")
	ui.show_result(title,subtitle,run_parts,run_seconds)
	play_sound("reward")

func fail_run(reason: String) -> void:
	if pause_reasons.has("result"): return
	_show_result("安全回收",reason)

func notify(text: String) -> void:
	message = text
	if is_instance_valid(ui): ui.toast(text)

func play_sound(name: String) -> void:
	if is_instance_valid(audio): audio.play_event(name)

func capture() -> void:
	await RenderingServer.frame_post_draw
	var folder = "res://artifacts/v2/screenshots" if OS.is_debug_build() else "user://screenshots"
	DirAccess.make_dir_recursive_absolute(folder)
	var filename = folder + "/" + Time.get_datetime_string_from_system().replace(":","-") + ".png"
	get_viewport().get_texture().get_image().save_png(filename)
	notify("截图已保存")

func equipment_missing_for(build: Dictionary, action: Dictionary, stage: Dictionary) -> Array[String]:
	var missing: Array[String] = []
	var modules = CatalogV2.modules()
	var slots: Dictionary = build.get("slots",{})
	var required = str(action.get("tool_id",""))
	var equipped = str(slots.get("tool",""))
	var needed: Dictionary = modules.get(required,{})
	var actual: Dictionary = modules.get(equipped,{})
	var matched = required.is_empty() or required == equipped
	matched = matched or (not needed.is_empty() and str(actual.get("ability","")) == str(needed.get("ability","missing")))
	if not matched: missing.append(required)
	if "basic_light" in stage.get("equipment_plan",{}).get("utility_required",[]):
		if str(slots.get("utility","")) != "searchlight_base": missing.append("searchlight_base")
	return missing

func departure_equipment(job: Dictionary) -> Dictionary:
	var build = selected_build()
	var loaner = bool(job.get("loaner",false)) or bool(job.get("training",false))
	if loaner:
		build = CatalogV2.default_build(str(job.get("airframe_id",build.airframe_id)))
		var sequence: Array = job.get("loaner_tool_sequence",["scan_base"])
		if not sequence.is_empty(): build.slots.tool = sequence[0]
		if job.has("loaner_utility"): build.slots.utility = job.loaner_utility
	var stage: Dictionary = job
	if job.has("stages") and not job.stages.is_empty():
		var index = 0
		var checkpoint: Variant = repository.data.campaign.active_checkpoint
		if checkpoint is Dictionary and checkpoint.get("job_id","") == job.id:
			index = clampi(int(checkpoint.get("stage_index",0)),0,job.stages.size()-1)
		stage = job.stages[index]
	var action: Dictionary = {}
	for candidate in stage.get("actions",[]):
		if not str(candidate.get("tool_id","")).is_empty(): action = candidate; break
	var missing = equipment_missing_for(build,action,stage)
	var grants: Array[String] = []
	for grant in content.economy.free_tools:
		if str(grant.mission) == str(job.id): grants.append(str(content.catalog.free_tool_map.get(grant.id,grant.id)))
	var checked = CatalogV2.resolve_build(build,0,repository.data.owned_airframes,repository.data.owned_modules,loaner)
	return {"missing":missing,"grants":grants,"loaner":loaner,"valid_build":bool(checked.valid),"stage_name":str(stage.get("name","当前阶段")),"service_id":str(stage.get("equipment_plan",{}).get("entry_service_poi",""))}

func service_destination() -> Dictionary:
	if not flight_active or not is_instance_valid(world) or not is_instance_valid(pilot): return {}
	var expected = str(runner.stage.get("equipment_plan",{}).get("entry_service_poi","")) if is_instance_valid(runner) else ""
	var known: Array = repository.data.world.discovered_pois
	var best: Dictionary = {}
	var nearest = INF
	for poi in world.region.pois:
		var id = str(poi.id)
		if not poi.has("service_function") or not world.service_unlocked(id): continue
		if id not in known and id != str(world.region.spawn_poi) and id != expected: continue
		var point = world.poi_position(id)
		var distance_m = Vector2(point.x-pilot.global_position.x,point.z-pilot.global_position.z).length()
		if distance_m<nearest:
			nearest = distance_m
			best = {"id":id,"name":str(poi.name),"position":point,"distance_m":distance_m}
	return best

func clear_service_guidance() -> void:
	if service_navigation_id.is_empty(): return
	var point = world.poi_position(service_navigation_id)
	service_navigation_id = ""
	if waypoint.is_finite() and Vector2(waypoint.x-point.x,waypoint.z-point.z).length()<0.1:
		waypoint = Vector3.INF
		if is_instance_valid(waypoint_marker): waypoint_marker.queue_free()
		waypoint_marker = null

func guide_to_service() -> bool:
	var destination = service_destination()
	if destination.is_empty(): notify("当前没有已知且开放的服务柜；请返回机库整备。"); return false
	set_waypoint(destination.position)
	service_navigation_id = str(destination.id)
	notify("已引导至 "+str(destination.name)+" · 着陆停稳后打开服务柜")
	return true
