extends SceneTree
## Production MAIN/HUD GPU review. No engine is launched by authoring this file.
## Run after normal import, with --rendering-method gl_compatibility --windowed
## --resolution 1280x720 --script res://scripts_tools/v3/capture_underdeck_integrated.gd
## -- --qa-profile=qa_visual_underdeck_<unique>
## --capture-output=res://artifacts/v3/art/underdeck-<unique>
## Previous 23 objectives are a saved Director replay fixture, NOT a playthrough.
## One initial body placement; subsequent routes use real move_and_collide with
## frozen production TR01. G/3/9/Tab/F use actual Session input dispatch. Production
## Session physics is explicitly stepped at 1/60; screenshots stop that clock.
## Real product HUD is retained. Cached AGL/zero velocity are not flight telemetry.

const MAIN = preload("res://scenes/v3/main.tscn")
const Director = preload("res://scripts/v3/gameplay/actions/twin_action_director.gd")
const HudCapture = preload("res://scripts_tools/v3/capture_hud_visibility.gd")
const SIZE := Vector2i(1280,720)
const DT := 1.0/60.0
const FRONT := "I1:underdeck_grille"
const LATCH := "I1:underdeck_latch"
const READ := "I1:underdeck:read"
const ENTRY := "I1:underdeck:enter"
const RELEASE := "I1:underdeck:release"
const TRAVERSE := "I1:underdeck:traverse"
const COLLISION_SHA := "8a9138bcf652ba71777aa89ec89bff8b790068b6e0c5b570c252560d51ee6473"
const INPUTS := [
	"res://scripts_tools/v3/capture_underdeck_integrated.gd",
	"res://scripts_tools/v3/capture_hud_visibility.gd","res://project.godot","res://scenes/v3/main.tscn",
	"res://scripts/v3/twin_session.gd","res://scripts/v3/twin_test_world.gd","res://scripts/v3/twin_interface.gd",
	"res://scripts/v3/twin_network.gd","res://scripts/v3/core/twin_world_store.gd",
	"res://scripts/v3/gameplay/twin_opening_story.gd","res://scripts/v3/gameplay/twin_ability_rules.gd",
	"res://scripts/v3/gameplay/actions/twin_action_director.gd","res://scripts/v3/gameplay/actions/twin_underdeck_action.gd",
	"res://scripts/v3/world/twin_underdeck_passage.gd","res://scripts/v3/art/twin_terrain_visibility.gd",
	"res://scripts/v3/art/twin_underdeck_gate_art.gd","res://assets/v3/underdeck_door/panel.glb","res://assets/v3/underdeck_door/fixed_rail.glb",
	"res://scripts/v3/art/twin_underdeck_shell_art.gd","res://assets/v3/underdeck_shell/underdeck_shell.glb",
	"res://scripts/v3/ui/twin_opening_guidance.gd","res://scripts/v3/art/twin_objective_marker.gd",
	"res://scripts/v3/art/twin_target_marker.gd","res://scripts/v2/flight_body.gd","res://scripts/v2/flight_camera.gd",
	"res://scripts/v2/pilot_input.gd","res://scripts/v2/catalog.gd",
	"res://data/v3/terrain/i1_underdeck_layout.json","res://data/v3/actions/opening_actions.json",
	"res://data/v3/actions/whale_action.json","res://data/v3/actions/crown_action.json","res://data/v3/actions/underdeck_action.json",
	"res://scripts/v3/art/twin_ground_surface.gd","res://assets/v3/materials/twin_ground_study.gdshader",
	"res://assets/v3/materials/twin_water_study.gdshader","res://assets/v3/materials/twin_shore_profile.gdshaderinc",
	"res://assets/fonts/NotoSansSC-Medium.ttf",
	"res://assets/v3/industrial/service_bridge.glb","res://assets/v3/industrial_kit/coastal_work_terrace.glb",
	"res://assets/v3/industrial_kit/power_relay_cabinet.glb","res://assets/v3/overpass/maintenance_overpass.glb",
	"res://assets/v3/whale/siphon_whale.glb","res://assets/v3/thermal_bypass/thermal_bypass.glb"
]

var session
var body
var passage
var profile := ""
var output := ""
var checks: Array = []
var shots: Array = []
var actions: Array = []
var routes: Array = []
var fixtures: Array = []
var physics_ticks := 0
var input_paths: Array = []
var hashes_before: Dictionary = {}
var protected_materials: Dictionary = {}
var capture_logger = HudCapture.CaptureLogger.new()
var finishing := false
var phase := "setup"

func _initialize() -> void:
	OS.add_logger(capture_logger)
	_run.call_deferred()

func _run() -> void:
	if not _arguments_valid():
		push_error("UNDERDECK_CAPTURE requires a fresh qa_visual_underdeck profile/output and debug Compatibility viewport")
		OS.remove_logger(capture_logger)
		quit(2)
		return
	if DirAccess.make_dir_recursive_absolute(output)!=OK:
		push_error("UNDERDECK_CAPTURE cannot create evidence directory")
		OS.remove_logger(capture_logger)
		quit(2)
		return
	create_timer(150.0,true,false,true).timeout.connect(_timeout)
	root.size = SIZE
	input_paths.assign(INPUTS)
	_add_import_hashes()
	hashes_before = _input_hashes()
	var complete := true
	for value in hashes_before.values(): complete = complete and str(value).length()==64
	if not _check(complete,"curated input files/import remaps exist"):
		await _finish()
		return
	session = MAIN.instantiate()
	root.add_child(session)
	# Disable callbacks only. PROCESS_MODE_DISABLED would remove child Jolt bodies
	# from their physics space, invalidating movement/collision evidence.
	session.set_process(false)
	session.set_physics_process(false)
	if not _check(session.profile_ready and session.store.root_path=="user://profiles_v3/"+profile and session.start_flight("solo"),"actual MAIN opens isolated fresh profile and solo I1"):
		await _finish()
		return
	if not _check(is_instance_valid(session.world.underdeck) and session.story.has_method("reset_underdeck_tracking"),"production World/Story contain underdeck integration"):
		await _finish()
		return
	if not _seed_previous_actions():
		await _finish()
		return
	body = session.players[1]
	passage = session.world.underdeck
	session.set_process(false)
	session.set_physics_process(false)
	session.inputs.set_process(false)
	session.inputs.set_physics_process(false)
	body.freeze = true
	body.set_process(false)
	body.set_physics_process(false)
	body.linear_velocity = Vector3.ZERO
	body.angular_velocity = Vector3.ZERO
	session.inputs.test_enabled = true
	session.inputs.test_frame = {"axes":{},"held":[],"edges":[]}
	session.world.set_effects_paused(true)
	session.story.reset_underdeck_tracking()
	body.global_transform = Transform3D(Basis.IDENTITY,Vector3(-35,2.05,-16.8))
	body.force_update_transform()
	PhysicsServer3D.body_set_state(body.get_rid(),PhysicsServer3D.BODY_STATE_TRANSFORM,body.global_transform)
	session.entities["player:1"].position = body.global_position
	fixtures.append({"type":"one_initial_frozen_body_placement","position":_vec(body.global_position),"frame":body.build.airframe_id,"resets_adapter_motion_history":true})
	await physics_frame
	await physics_frame
	session.story.reset_underdeck_tracking()
	protected_materials = _protected_material_state()
	_check(session.network.mode=="solo" and session.qa_mode.is_empty() and not session.boss_active and body.build.airframe_id=="tr01","solo TR01 without automatic QA network or Boss mode")
	if not _check(_collision_sha()==COLLISION_SHA and _body_clear(),"actual unchanged shell collision and clear south starting body"):
		await _finish()
		return
	await _ticks(1)
	phase = "south_inspection"
	await _capture("01-south-closed-default26",26.0,false,"南口默认镜头：实际关闭门板、洞口边与产品任务 HUD")
	await _capture("02-south-closed-close12",12.0,false,"南口近景：实际 GLB 实体门板、材质、挂轮与固定上轨")
	_advance_dialogue()
	_key(KEY_G,"manual inspection")
	if not _check(_completed(READ) and not _completed(ENTRY),"actual G/LOS commits only the new inspection"):
		await _finish()
		return
	_advance_dialogue()
	phase = "held_south_entry"
	for unused in range(240):
		if passage.status().phase=="opening_warning": break
		await _ticks(1)
	if not _check(passage.status().phase=="opening_warning","natural cycle reaches opening warning without assigning phase or lamp"):
		await _finish()
		return
	await _capture("03-south-opening-warning-default26",26.0,false,"自然开门预警：核对灯是否与关闭态同色、是否受门框遮挡；不人为改色")
	for unused in range(520):
		if float(passage.snapshot().front_fraction)>=0.999: break
		await _ticks(1)
	if not _check(float(passage.snapshot().front_fraction)>=0.999,"production ticks reach natural front opening"):
		await _finish()
		return
	if not await _cast(KEY_3,"force_field",FRONT,10.0):
		await _finish()
		return
	await _ticks(6)
	_check(session.entities[FRONT].pinned and passage.status().phase=="field_hold","real force field holds the actual open panel")
	await _capture("04-south-held-default26",26.0,false,"同一南口：法定力场定住自然打开的真实门片")
	if not await _move(Vector3(-35,2.05,-23.5),"south open portal to turning chamber"):
		await _finish()
		return
	if not _check(_completed(ENTRY) and session.story.state.choices.get(ENTRY)=="held_grille","actual full-body movement commits held-grille entry"):
		await _finish()
		return
	_advance_dialogue()
	_select(KEY_9,"echo",LATCH)
	await _capture("05-interior-default26",26.0,true,"廊内默认镜头：常显地面/墙脚，顶壳和上墙正常淡出；锁仍独立")
	await _capture("06-interior-latch-close12",12.0,true,"廊内近景：西壁安全锁、侧台高差与标线；检查灰盒明暗")
	phase = "east_window_detour"
	if not await _move(Vector3(-35,3.55,-23.5),"rise in real turning chamber") or not await _move(Vector3(-25,3.55,-23.5),"exit through always-open east high window"):
		await _finish()
		return
	await _capture("07-east-window-default26",26.0,false,"东侧高窗外默认镜头：由实际碰撞移动退出，未直接摆到窗外")
	if not await _move(Vector3(-29,3.55,-23.5),"return into raised side duct"):
		await _finish()
		return
	await _capture("08-east-duct-close12",12.0,true,"侧廊近景：Y2.3 侧台不随顶壳淡出，高窗路径真实存在")
	if not await _move(Vector3(-35,3.55,-23.5),"side duct to turning chamber") or not await _move(Vector3(-35,2.05,-23.5),"descend to inner latch approach"):
		await _finish()
		return
	phase = "continuous_latch_release"
	if not await _cast(KEY_9,"echo",LATCH,12.0):
		await _finish()
		return
	await _ticks(30)
	_check(not _completed(RELEASE),"half second signal is insufficient; no direct latch flag fixture")
	for unused in range(180):
		if _completed(RELEASE) and float(passage.snapshot().front_fraction)>=0.999 and float(passage.snapshot().rear_fraction)>=0.999: break
		await _ticks(1)
	if not _check(_completed(RELEASE) and passage.snapshot().latched and float(passage.snapshot().front_fraction)>=0.999 and float(passage.snapshot().rear_fraction)>=0.999,"real continuous echo/save opens both independent gate bodies"):
		await _finish()
		return
	_advance_dialogue()
	await _capture("09-latch-released-close12",12.0,true,"互锁真实保存后：内锁与地面常显，两端门独立收起")
	phase = "north_traversal"
	if not await _move(Vector3(-35,2.05,-33),"main corridor toward north portal"):
		await _finish()
		return
	_check(not _completed(TRAVERSE),"inside north approach has not impersonated exit crossing")
	await _capture("10-north-inside-default26",26.0,true,"北口廊内默认镜头：尚未越出口；检查屋顶与支柱遮挡")
	if not await _move(Vector3(-35,2.05,-37.2),"full body crosses actual north portal"):
		await _finish()
		return
	_check(_completed(TRAVERSE) and session.story.state.completed.size()==27,"actual north crossing commits the four new goals after explicit23-goal fixture")
	_advance_dialogue()
	await _capture("11-north-outside-default26",26.0,true,"北口外默认镜头：实际穿出后仍由相机射线决定淡出，不按包围盒强制恢复")
	_check(int(session.stats.abilities)==2 and int(session.stats.rejected_abilities)==0,"exactly two genuine accepted ability casts, no rejected cast")
	await _finish()

func _seed_previous_actions() -> bool:
	var legacy = Director.new()
	var loaded: Dictionary = legacy.load_definitions(Director.DEFAULT_PATH,["res://data/v3/actions/whale_action.json","res://data/v3/actions/crown_action.json"])
	if not _check(loaded.ok,"load production six-action prerequisite definitions"): return false
	var state: Dictionary = legacy.default_state()
	var replay: Array = []
	for action in legacy.definitions().actions:
		for objective in action.objectives:
			var matcher: Dictionary = objective.events[0]
			var event := {"id":"qa-capture-prerequisite:"+str(objective.id),"type":matcher.type,"target_id":matcher.target_id,"option":matcher.options[0]}
			var result: Dictionary = legacy.apply_event(state,event,{"is_authority":true,"validated":true,"region_id":action.region_id})
			if not _check(result.get("changed",false),"prerequisite fixture replay "+str(objective.id)): return false
			state = result.state
			replay.append(event)
	if not _check(state.completed.size()==23 and state.completed_actions.size()==6 and session.story.director.validate_state(state).ok,"exactly old23 objectives fixture, no new objective injected"): return false
	var saved: Dictionary = session.store.commit({"id":"qa-capture-six-action-prerequisite","set":{"world.actions.opening":state,"world.flags":state.flags,"world.completed_objectives":state.completed},"append":{"personal.discoveries":state.discoveries}})
	if not _check(saved.ok,"explicit predecessor replay commits to isolated store"): return false
	fixtures.append({"type":"six_old_actions_Director_replay_not_playthrough","completed_objectives":state.completed,"events":replay})
	session.world_cache = session.store.snapshot()
	return _check(session._load_region("I1") and session.story.state.completed.size()==23 and not session.world.underdeck.snapshot().latched,"real I1 reload restores only predecessor state; new passage remains unreleased")

func _ticks(count: int) -> void:
	for unused in range(count):
		if finishing: return
		await physics_frame
		session._physics_process(DT)
		physics_ticks += 1
		await process_frame

func _move(target: Vector3, label: String) -> bool:
	var from: Vector3 = body.global_position
	var start_clear := _body_clear()
	var steps := 0
	var tick_before := physics_ticks
	var hit: KinematicCollision3D
	if start_clear:
		while body.global_position.distance_to(target)>0.001 and steps<240 and not finishing:
			hit = body.move_and_collide((target-body.global_position).limit_length(0.15))
			steps += 1
			await _ticks(1)
			if hit!=null: break
	var success: bool = start_clear and hit==null and body.global_position.distance_to(target)<0.005 and _body_clear()
	var record := {"label":label,"method":"actual_frozen_FlightBody_move_and_collide","from":_vec(from),"to_requested":_vec(target),"to_actual":_vec(body.global_position),"max_step_m":0.15,"steps":steps,"physics_ticks":physics_ticks-tick_before,"initial_clear":start_clear,"success":success,"collider":str(hit.get_collider().get_path()) if hit!=null else ""}
	routes.append(record)
	return _check(success,"actual collision path: "+label,record)

func _body_clear() -> bool:
	var envelope: CollisionShape3D = body.get_node("Envelope")
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = envelope.shape
	query.transform = envelope.global_transform
	query.collision_mask = 1|8
	query.exclude = [body.get_rid()]
	query.margin = 0.0
	return PhysicsServer3D.body_get_space(body.get_rid())==session.world.get_world_3d().space and PhysicsServer3D.body_get_space(passage.shell.get_rid())==session.world.get_world_3d().space and session.world.get_world_3d().direct_space_state.intersect_shape(query,1).is_empty()

func _key(code: Key, label: String) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.pressed = true
	session._unhandled_input(event)
	actions.append({"kind":"production_input_handler","key":OS.get_keycode_string(code),"label":label,"tick":physics_ticks})

func _advance_dialogue() -> void:
	# Consume only currently visible dialogue with its normal G action; do not
	# hide the radio/task panels or call another nearby interaction after closing.
	for unused in range(24):
		if not session.interface.radio.visible: break
		_key(KEY_G,"advance visible product dialogue")
	_check(not session.interface.radio.visible,"current dialogue advanced through actual G")

func _select(code: Key, ability: String, target: String) -> bool:
	session.flight_camera.snap(body.global_position)
	_key(code,"select "+ability)
	var tabs := 0
	while str(session.locks.get(1,""))!=target and tabs<64:
		_key(KEY_TAB,"cycle actual target list")
		tabs += 1
	return _check(session.selected_ability==ability and str(session.locks.get(1,""))==target,"real key/Tab selects "+ability+" / "+target,{"tabs":tabs})

func _cast(code: Key, ability: String, target: String, cost: float) -> bool:
	for unused in range(180):
		if float(session.cooldowns.get(1,0.0))<=0.0: break
		await _ticks(1)
	if not _select(code,ability,target): return false
	var energy: float = session.entities["player:1"].energy
	var accepted: int = session.stats.abilities
	var rejected: int = session.stats.rejected_abilities
	_key(KEY_F,"cast "+ability)
	return _check(int(session.stats.abilities)==accepted+1 and int(session.stats.rejected_abilities)==rejected and is_equal_approx(float(session.entities["player:1"].energy),energy-cost),"actual F validates LOS/range/energy and applies "+ability,{"energy_before":energy,"energy_after":session.entities["player:1"].energy,"message":session.interface.message.text})

func _capture(id: String, zoom: float, shell_fades: bool, purpose: String) -> void:
	if finishing: return
	session.flight_camera.target_size = zoom
	session.flight_camera.snap(body.global_position)
	# Use production _process (fader, pilot hint, markers, Story display) with
	# explicit visual-only time. No physics/door/ability clock runs in this loop.
	for unused in range(12):
		session._process(0.1)
		await RenderingServer.frame_post_draw
	session._refresh_interface()
	var before := _state()
	for unused in range(8): await RenderingServer.frame_post_draw
	if finishing: return
	var after := _state()
	var frame: Image = root.get_texture().get_image()
	if not _check(frame!=null and not frame.is_empty() and frame.get_size()==SIZE and root.size==SIZE and session.camera.projection==Camera3D.PROJECTION_ORTHOGONAL and is_equal_approx(float(session.camera.size),zoom) and before==after,"stable actual720p product frame: "+id): return
	var path := output.path_join(id+".png")
	if not _check(not FileAccess.file_exists(path) and frame.save_png(path)==OK,"write fresh unedited viewport PNG: "+id): return
	var alphas: Array = []
	var correct := true
	var covers: Array = passage.shell.get_node("OccludingCover").find_children("*", "MeshInstance3D", true, false)
	_check(covers.size() == 3 and passage.shell.get_meta("authored_shell", false), "actual imported shell includes cover/details/towers: " + id)
	for cover in covers:
		var expected_alpha := 1.0 if not shell_fades else 0.0 if cover.get_meta("terrain_visibility_cutaway_detail", false) else 0.20
		for surface in range(cover.mesh.get_surface_count()):
			var material: BaseMaterial3D = cover.get_active_material(surface)
			alphas.append(material.albedo_color.a)
			correct = correct and is_equal_approx(material.albedo_color.a,expected_alpha)
	_check(correct,"production shell fade expectation: "+id,{"expected_fade":shell_fades,"alphas":alphas})
	_check(_protected_material_state()==protected_materials,"navigation/gates/lock/markings retain opaque material bindings: "+id)
	_check(_collision_sha()==COLLISION_SHA and _body_clear(),"unchanged shell collision and nonembedded full capture body: "+id)
	_check(session.interface.hud.visible and not session.interface.menu.visible and not str(session.interface.title.text).contains("QA"),"actual product HUD retained without QA replacement: "+id)
	shots.append({"id":id,"file":path,"png_sha256":FileAccess.get_sha256(path),"resolution":[SIZE.x,SIZE.y],"purpose":purpose,
		"state":after,"camera":{"focus_body":_vec(body.global_position),"size":session.camera.size,"transform":_transform(session.camera.global_transform)},
		"cover_alpha":alphas,"navigation_screen_samples":_navigation_samples(),"fade_candidates":_fade_entries(),
		"input_sha256":_input_hashes(),"hud":{"title":session.interface.title.text,"vitals":session.interface.vitals.text,"objective":session.interface.objective.text,"target":session.interface.target_info.text,"message":session.interface.message.text},
		"readability_review":"PENDING: PNG must be viewed for floor/portal/lock readability and lighting; opacity/projection checks alone do not prove visibility.",
		"height_provenance":{"body_frozen":body.freeze,"body_world_Y":body.global_position.y,"cached_AGL":body.ground_distance,"limitation":"No actual flight integration; cached AGL and zero velocity may be stale. Body clearance uses actual collision envelope separately."}})

func _state() -> Dictionary:
	return {"passage":passage.snapshot(),"passage_status":passage.status(),"lamp_colors":_lamp_colors(),"story_completed":session.story.state.completed.duplicate(),"story_choices":session.story.state.choices.duplicate(true),
		"body":_transform(body.global_transform),"body_frozen":body.freeze,"health":body.health,"energy":session.entities["player:1"].energy,"cooldown":session.cooldowns.get(1,0.0),
		"front_transform":_transform(passage.gates.front.global_transform),"rear_transform":_transform(passage.gates.rear.global_transform),"physics_ticks":physics_ticks,"world_clock":session.world.clock_seconds,
		"front_entity":_safe(session.entities[FRONT]),"latch_entity":_safe(session.entities[LATCH])}

func _lamp_colors() -> Dictionary:
	var result: Dictionary = {}
	for id in ["front","rear"]:
		var material: BaseMaterial3D = passage._lamps[id].material_override
		result[id] = _safe(material.albedo_color)
	return result

func _protected_material_state() -> Dictionary:
	var result: Dictionary = {}
	for branch in [passage.shell.get_node("PermanentNavigation"),passage.get_node("GrayboxMaintenanceMarkings"),passage.gates.front,passage.gates.rear,passage.get_node("InnerLatch")]:
		for mesh in branch.find_children("*","MeshInstance3D",true,false):
			for surface in range(mesh.mesh.get_surface_count()):
				var material: BaseMaterial3D = mesh.get_active_material(surface)
				# Lamp colour legitimately changes with phase; bind/alpha must not.
				result[str(passage.get_path_to(mesh))+":"+str(surface)] = {"material_id":material.get_instance_id(),"alpha":material.albedo_color.a,"transparency":material.transparency}
	return result

func _navigation_samples() -> Array:
	var result: Array = []
	for row in [["south_floor",Vector3(-35,0.45,-20)],["inner_floor",Vector3(-35,0.45,-25)],["side_landing",Vector3(-28,2.3,-23.5)],["north_floor",Vector3(-35,0.45,-33)],["inner_latch",passage.anchor_position("inner_latch")]]:
		var pixel: Vector2 = session.camera.unproject_position(row[1])
		result.append({"name":row[0],"world":_vec(row[1]),"pixel":[pixel.x,pixel.y],"inside_viewport":not session.camera.is_position_behind(row[1]) and Rect2(Vector2.ZERO,Vector2(SIZE)).has_point(pixel),"not_an_occlusion_or_pixel_readability_proof":true})
	return result

func _fade_entries() -> Array:
	var result: Array = []
	for entry in session.terrain_visibility._entries.values():
		result.append({"path":str(session.world.get_path_to(entry.root)),"blocked":entry.blocked,"alpha":entry.alpha,"mesh_count":entry.meshes.size()})
	return result

func _collision_sha() -> String:
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	context.update(passage.shell.get_node("ExactSurfaceCollision").shape.get_faces().to_byte_array())
	return context.finish().hex_encode()

func _completed(id: String) -> bool:
	return id in session.story.state.get("completed",[])

func _arguments_valid() -> bool:
	var profiles := 0
	var outputs := 0
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--qa-profile="):
			profiles += 1
			profile = arg.trim_prefix("--qa-profile=")
		elif arg.begins_with("--capture-output="):
			outputs += 1
			output = arg.trim_prefix("--capture-output=")
		elif arg.begins_with("--qa-") or arg.begins_with("--perf-"): return false
	var pattern := RegEx.new()
	if pattern.compile("^qa_visual_underdeck_[A-Za-z0-9_-]+$")!=OK: return false
	if profiles!=1 or outputs!=1 or pattern.search(profile)==null or output.is_empty(): return false
	output = ProjectSettings.globalize_path(output).replace("\\","/").simplify_path()
	var allowed := ProjectSettings.globalize_path("res://artifacts/v3/art").replace("\\","/").simplify_path()
	if not output.is_absolute_path() or output.get_base_dir().to_lower()!=allowed.to_lower(): return false
	if not output.get_file().begins_with("underdeck-") or output.get_file()=="underdeck-": return false
	if DirAccess.dir_exists_absolute(output) or FileAccess.file_exists(output): return false
	if DirAccess.dir_exists_absolute("user://profiles_v3/"+profile) or FileAccess.file_exists("user://profiles_v3/"+profile): return false
	return OS.is_debug_build() and DisplayServer.get_name()!="headless" and RenderingServer.get_current_rendering_method()=="gl_compatibility" and RenderingServer.is_render_loop_enabled()

func _add_import_hashes() -> void:
	for path in input_paths.duplicate():
		var descriptor := str(path)+".import"
		if not FileAccess.file_exists(descriptor): continue
		if descriptor not in input_paths: input_paths.append(descriptor)
		var config := ConfigFile.new()
		if config.load(descriptor)!=OK or not config.has_section("remap"): continue
		for key in config.get_section_keys("remap"):
			if key=="path" or key.begins_with("path."):
				var cache := str(config.get_value("remap",key,""))
				if not cache.is_empty() and cache not in input_paths: input_paths.append(cache)

func _input_hashes() -> Dictionary:
	var result: Dictionary = {}
	for path in input_paths: result[path] = FileAccess.get_sha256(path) if FileAccess.file_exists(path) else "MISSING"
	return result

func _vec(value: Vector3) -> Array:
	return [value.x,value.y,value.z]

func _transform(value: Transform3D) -> Dictionary:
	return {"origin":_vec(value.origin),"x":_vec(value.basis.x),"y":_vec(value.basis.y),"z":_vec(value.basis.z)}

func _safe(value: Variant) -> Variant:
	if value is Vector3: return _vec(value)
	if value is Color: return [value.r,value.g,value.b,value.a]
	if value is Dictionary:
		var result: Dictionary = {}
		for key in value: result[str(key)] = _safe(value[key])
		return result
	if value is Array:
		var result: Array = []
		for item in value: result.append(_safe(item))
		return result
	return value

func _check(ok: bool, label: String, details: Dictionary = {}) -> bool:
	checks.append({"phase":phase,"name":label,"passed":ok,"details":details})
	return ok

func _timeout() -> void:
	if finishing:
		quit(3)
		return
	_check(false,"150 second watchdog expired")
	_finish.call_deferred()

func _finish() -> void:
	if finishing: return
	finishing = true
	var stats: Dictionary = session.stats.duplicate(true) if is_instance_valid(session) else {}
	if is_instance_valid(session):
		session.active = false
		if is_instance_valid(session.network): session.network.close()
		session.queue_free()
	await process_frame
	await process_frame
	var hashes_after := _input_hashes()
	var unchanged := not hashes_before.is_empty() and hashes_before==hashes_after
	for shot in shots: unchanged = unchanged and shot.input_sha256==hashes_before and str(shot.png_sha256).length()==64
	_check(unchanged,"curated code/layout/I1 asset/import bytes unchanged through all captures")
	_check(shots.size()==11,"eleven requested production viewport PNGs saved")
	var logged: Dictionary = capture_logger.snapshot()
	_check(int(logged.error_count)==0,"no engine/script/shader ERROR including cleanup")
	var passed := true
	for item in checks: passed = passed and bool(item.passed)
	var report := {"purpose":"Integrated underdeck fixed-camera visibility and actual seventh-action scripted route review","status":"captured_for_review_not_aesthetic_acceptance","passed":passed,
		"profile":profile,"output":output,"checks":checks,"shots":shots,"actions":actions,"routes":routes,"fixtures":fixtures,"session_stats":stats,
		"explicit_production_physics_ticks":physics_ticks,"fixed_step_seconds":DT,"input_sha256_before":hashes_before,"input_sha256_after":hashes_after,
		"visual_review_flags":{"opening_warning_same_lamp_colors_as_closed":shots[0].state.lamp_colors==shots[2].state.lamp_colors if shots.size()>2 else null,"lighting_and_pixel_readability":"pending_actual_image_review"},
		"input_hash_scope":"Curated capture/Session/story/underdeck/fader/flight/HUD/ground code, definitions, I1 meshes and their direct import remaps; not a whole-project source fingerprint.",
		"engine_log":logged,"engine_version":Engine.get_version_info(),"gpu":RenderingServer.get_video_adapter_name(),"renderer":RenderingServer.get_current_rendering_method(),"display":DisplayServer.get_name(),"viewport":[root.size.x,root.size.y],
		"limitations":["Eleven unedited real viewport PNGs with product HUD; no final visual approval, human-play, controller, LAN or performance conclusion.",
			"Six old actions /23 goals are explicit production Director replay saved fixtures. They were not earned through gameplay here.",
			"One initial teleport and frozen TR01; later moves use actual move_and_collide in0.15m steps. This is collision-path scripting, not flight dynamics or human input.",
			"New action uses actual G and legal3/9/Tab/F; Session physics is explicitly called at1/60 between real physics frames. No new flags/facts, ability energy or cooldown are assigned directly.",
			"Only Session/input/body callbacks are stopped; process_mode and the live PhysicsServer space remain normal. Production Session._process is explicitly called for camera/fader/HUD, and product UI timers still run; no QA text replaces product UI.",
			"HUD AGL and velocity remain cached while body is frozen. Actual envelope overlap checks are separate; this does not validate airborne comfort.",
			"Opaque material and projected navigation-point checks do not prove pixel visibility or readable lighting. Reviewer must inspect each PNG.",
			"External runner must reject parse/startup failure, missing capture.json, nonzero process exit and logged engine errors."]}
	var path := output.path_join("capture.json")
	var file: FileAccess = FileAccess.open(path,FileAccess.WRITE) if not FileAccess.file_exists(path) else null
	var write_ok := file!=null
	if file!=null:
		file.store_string(JSON.stringify(report,"\t",true,true))
		file.flush()
		write_ok = file.get_error()==OK
		file.close()
	if not write_ok: push_error("UNDERDECK_CAPTURE report write failed")
	var final_log: Dictionary = capture_logger.snapshot()
	var success: bool = passed and write_ok and int(final_log.error_count)==0
	print("UNDERDECK_CAPTURE ",JSON.stringify({"passed":success,"checks":checks.size(),"shots":shots.size(),"errors":final_log.error_count,"output":output}))
	OS.remove_logger(capture_logger)
	quit(0 if success else 1)
