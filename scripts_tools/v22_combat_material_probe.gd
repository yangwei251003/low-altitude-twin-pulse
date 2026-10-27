extends SceneTree
## Owner-run inspection. --prepared verifies the production vertex-color helper
## without editing imported resources. --capture also requires --v2-qa=<unique>
## and a real renderer: an explicitly staged, static R2 art fixture, not combat
## or natural-encounter evidence. This script never edits a source asset.

const ASSET_ROOT = "res://assets/models/v22_combat/"
const ASSETS = ["enemy_scout","enemy_harasser","enemy_suppressor","enemy_support","weapon_pulse","weapon_burst","weapon_lance","wreck_core","wreck_rotor","wreck_panel"]
var failures: Array[String] = []
var findings: Array[Dictionary] = []
var models: Array[Dictionary] = []
var output = ""
var prepared = false
var capture = false
var capture_output = "res://artifacts/v22/combat_material_capture"
var prepared_checks = 0
var prepared_surfaces = 0
var runtime_prepared_surfaces = 0
var screenshots: Array[Dictionary] = []
var capture_sources: Dictionary = {}
var session: GameSessionV2
var submitted_draws = 0
var completed_draws = 0
var last_draw_process = -1
var last_draw_us = 0
var original_render_loop = true
var manual_draw_active = false

func _initialize() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--output="): output = argument.trim_prefix("--output=")
		elif argument in ["--prepared","--prepared=true"]: prepared = true
		elif argument in ["--capture","--capture=true"]: capture = true
		elif argument.begins_with("--capture-output="): capture_output = argument.trim_prefix("--capture-output=").trim_suffix("/")
	call_deferred("run")

func rgba(value: Color) -> Array:
	return [value.r,value.g,value.b,value.a]

func material_info(material: Material) -> Dictionary:
	if material==null:return {"present":false}
	var result = {"present":true,"class":material.get_class(),"resource_name":material.resource_name,"resource_path":material.resource_path,"instance_id":material.get_instance_id(),"local_to_scene":material.resource_local_to_scene,"render_priority":material.render_priority}
	if material is BaseMaterial3D:
		result.merge({"vertex_color_use_as_albedo":material.vertex_color_use_as_albedo,"vertex_color_is_srgb":material.vertex_color_is_srgb,"albedo":rgba(material.albedo_color),"albedo_texture":material.albedo_texture.resource_path if material.albedo_texture!=null else "","emission_enabled":material.emission_enabled,"emission":rgba(material.emission),"emission_energy_multiplier":material.emission_energy_multiplier,"emission_operator":material.emission_operator,"metallic":material.metallic,"roughness":material.roughness,"shading_mode":material.shading_mode,"transparency":material.transparency,"blend_mode":material.blend_mode,"no_depth_test":material.no_depth_test})
	elif material is ShaderMaterial:
		result["shader_path"] = material.shader.resource_path if material.shader!=null else ""
		result["shader_sha256"] = material.shader.code.sha256_text() if material.shader!=null else ""
	if material.next_pass!=null:
		result["next_pass_class"] = material.next_pass.get_class()
		result["next_pass_path"] = material.next_pass.resource_path
	return result

func color_info(mesh: Mesh, surface: int) -> Dictionary:
	var arrays = mesh.surface_get_arrays(surface)
	if arrays.size()<=Mesh.ARRAY_COLOR:return {"present":false,"vertex_count":0,"color_count":0}
	var vertices:Variant = arrays[Mesh.ARRAY_VERTEX]
	var colors:Variant = arrays[Mesh.ARRAY_COLOR]
	var vertex_count = vertices.size() if vertices is PackedVector3Array else 0
	if not colors is PackedColorArray or colors.is_empty():return {"present":false,"vertex_count":vertex_count,"color_count":0}
	var minimum = Color(INF,INF,INF,INF)
	var maximum = Color(-INF,-INF,-INF,-INF)
	var total = Color(0,0,0,0)
	var unique: Dictionary = {}
	var first_colors: Array = []
	var nonwhite = 0
	for value in colors:
		minimum = Color(minf(minimum.r,value.r),minf(minimum.g,value.g),minf(minimum.b,value.b),minf(minimum.a,value.a))
		maximum = Color(maxf(maximum.r,value.r),maxf(maximum.g,value.g),maxf(maximum.b,value.b),maxf(maximum.a,value.a))
		total += value
		if value.r<.95 or value.g<.95 or value.b<.95:nonwhite += 1
		var key = value.to_html(true)
		if not unique.has(key):
			unique[key] = true
			if first_colors.size()<12:first_colors.append(rgba(value))
	return {"present":true,"vertex_count":vertex_count,"color_count":colors.size(),"minimum_rgba":rgba(minimum),"maximum_rgba":rgba(maximum),"mean_rgba":rgba(total/float(colors.size())),"nonwhite_count":nonwhite,"unique_rgba8_count":unique.size(),"first_unique_colors_rgba":first_colors}

func run() -> void:
	for asset in ASSETS:
		var path = ASSET_ROOT+asset+".glb"
		if not ResourceLoader.exists(path):failures.append("Missing imported asset: "+path);continue
		var original_file_sha = FileAccess.get_sha256(path)
		var packed = load(path) as PackedScene
		if packed==null:failures.append("Asset is not PackedScene: "+path);continue
		var model = packed.instantiate()
		root.add_child(model)
		var original = _snapshot_sources(model) if prepared else []
		if prepared:
			StreetDressingV2._enable_vertex_colors(model)
			_verify_prepared(asset,model,original)
			# A second instance must retain all imported material flags and colors.
			# The helper may share its duplicate cache, never modify PackedScene data.
			var untouched = packed.instantiate()
			_verify_untouched(asset,untouched,original)
			untouched.free()
		var model_result = {"asset":asset,"source_sha256":original_file_sha,"meshes":[]}
		for node in model.find_children("*","MeshInstance3D",true,false):
			var mesh: Mesh = node.mesh
			if mesh==null:failures.append(asset+" / "+str(node.name)+": missing mesh");continue
			var mesh_result = {"node":str(model.get_path_to(node)),"mesh_name":mesh.resource_name,"surface_count":mesh.get_surface_count(),"material_override":material_info(node.material_override),"material_overlay":material_info(node.material_overlay),"surfaces":[]}
			for index in range(mesh.get_surface_count()):
				var source_material = mesh.surface_get_material(index)
				var override_material = node.get_surface_override_material(index)
				var active_material = node.get_active_material(index)
				var colors = color_info(mesh,index)
				var surface = {"index":index,"name":mesh.surface_get_name(index) if mesh is ArrayMesh else "","mesh_material":material_info(source_material),"surface_override":material_info(override_material),"effective_material":material_info(active_material),"vertex_colors":colors}
				mesh_result.surfaces.append(surface)
				if bool(colors.present) and active_material is BaseMaterial3D and not active_material.vertex_color_use_as_albedo:
					findings.append({"asset":asset,"mesh":str(node.name),"surface":index,"issue":"Imported COLOR_0 exists but effective material ignores vertex color"})
				if bool(colors.present) and int(colors.color_count)!=int(colors.vertex_count):failures.append(asset+" / "+str(node.name)+": vertex/color count mismatch")
			model_result.meshes.append(mesh_result)
			print("V22_COMBAT_MATERIAL_MESH ",JSON.stringify({"asset":asset,"mesh":mesh_result}))
		if model_result.meshes.is_empty():failures.append("No mesh instances: "+asset)
		models.append(model_result)
		model.queue_free()
		await process_frame
		if prepared: _check(FileAccess.get_sha256(path)==original_file_sha,asset+": GLB source bytes unchanged")
	if capture and failures.is_empty(): await _capture_session()
	var report = {"ok":failures.is_empty(),"engine":Engine.get_version_info(),"renderer":RenderingServer.get_current_rendering_method(),"inspected_models":models.size(),"expected_models":ASSETS.size(),"prepared":prepared,"prepared_checks":prepared_checks,"prepared_surfaces":prepared_surfaces,"findings":findings,"failures":failures,"models":models,"capture_requested":capture,"runtime_prepared_surfaces":runtime_prepared_surfaces,"screenshots":screenshots,"capture_source_sha256":capture_sources,"capture_submitted_draws":submitted_draws,"capture_completed_draws":completed_draws,"scope":"Imported GLB inspection; prepared checks use the existing production helper and verify untouched source materials, COLOR_0 and a fresh instance. Optional screenshots use a real Session, normal lighting/night/visibility, static four-role R2 placement, brains and weapons held. Static art comparison only; no combat, encounter, FPS or human-comfort claim."}
	if not output.is_empty():
		DirAccess.make_dir_recursive_absolute(output.get_base_dir())
		var file = FileAccess.open(output,FileAccess.WRITE)
		if file==null:
			failures.append("Cannot write requested report: "+output)
			report.ok=false
		else:file.store_string(JSON.stringify(report,"\t"));file.close()
	print("V22_COMBAT_MATERIAL_REPORT ",JSON.stringify(report))
	quit(0 if failures.is_empty() else 1)

func _check(condition: bool, label: String) -> void:
	prepared_checks += 1
	if not condition: failures.append(label)

func _snapshot_sources(model: Node) -> Array:
	var result: Array = []
	for node in model.find_children("*","MeshInstance3D",true,false):
		if node.mesh==null: continue
		for index in range(node.mesh.get_surface_count()):
			var arrays = node.mesh.surface_get_arrays(index)
			var colors: Variant = arrays[Mesh.ARRAY_COLOR]
			result.append({"path":model.get_path_to(node),"surface":index,"mesh":node.mesh,
				"source":node.mesh.surface_get_material(index),"source_info":material_info(node.mesh.surface_get_material(index)),
				"active_info":material_info(node.get_active_material(index)),
				"colors":colors.duplicate() if colors is PackedColorArray else colors})
	return result

func _verify_prepared(asset: String, model: Node, original: Array) -> void:
	for before in original:
		var node = model.get_node(before.path) as MeshInstance3D
		var index = int(before.surface)
		var label = asset+" / "+str(before.path)+" / "+str(index)
		var material = node.get_active_material(index)
		var has_colors = before.colors is PackedColorArray and not before.colors.is_empty()
		if has_colors:
			prepared_surfaces += 1
			_check(material is BaseMaterial3D,label+": prepared material remains BaseMaterial3D")
			if material is BaseMaterial3D:
				_check(material.vertex_color_use_as_albedo,label+": effective material enables COLOR_0")
				_check(not material.vertex_color_is_srgb,label+": linear imported colors are not decoded twice")
		_check(node.mesh==before.mesh,label+": source mesh identity unchanged")
		_check(node.mesh.surface_get_material(index)==before.source,label+": source material identity unchanged")
		_check(material_info(before.source)==before.source_info,label+": source material properties unchanged")
		_check(node.mesh.surface_get_arrays(index)[Mesh.ARRAY_COLOR]==before.colors,label+": original COLOR_0 unchanged")
	# Repeat the exact helper: it must keep the effective resources stable.
	var active: Array = []
	for before in original: active.append(model.get_node(before.path).get_active_material(int(before.surface)))
	StreetDressingV2._enable_vertex_colors(model)
	for i in range(original.size()):
		var before = original[i]
		_check(model.get_node(before.path).get_active_material(int(before.surface))==active[i],asset+": helper is idempotent / "+str(before.path))

func _verify_untouched(asset: String, model: Node, original: Array) -> void:
	for before in original:
		var node = model.get_node(before.path) as MeshInstance3D
		var index = int(before.surface)
		_check(material_info(node.get_active_material(index))==before.active_info,asset+": fresh instance retains imported material / "+str(before.path))
		_check(node.mesh.surface_get_arrays(index)[Mesh.ARRAY_COLOR]==before.colors,asset+": fresh instance retains COLOR_0 / "+str(before.path))

func _capture_session() -> void:
	var isolated = false
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--v2-qa=") and argument.trim_prefix("--v2-qa=").length()>0: isolated = true
	if not isolated or not OS.is_debug_build():
		failures.append("Capture requires debug Godot and a unique --v2-qa=<name> profile"); return
	if DisplayServer.get_name()=="headless":
		failures.append("Capture requires a real GPU renderer; headless pixels are not graphics evidence"); return
	if not capture_output.begins_with("res://artifacts/v22/") or ".." in capture_output:
		failures.append("Capture output must stay under res://artifacts/v22/"); return
	DirAccess.make_dir_recursive_absolute(capture_output)
	for source in ["scripts_tools/v22_combat_material_probe.gd","scripts/v2/session.gd","scripts/v2/enemy_actor.gd","scripts/v2/fleet_visuals.gd","scripts/v2/street_dressing.gd","scripts/v2/combat_feedback.gd","scripts/v2/night_visibility.gd","assets/shaders/v22_combat/visible_body_rim.gdshader"]:
		if FileAccess.file_exists("res://"+source): capture_sources[source] = FileAccess.get_sha256("res://"+source)
	for asset in ASSETS: capture_sources[ASSET_ROOT+asset+".glb"] = FileAccess.get_sha256(ASSET_ROOT+asset+".glb")
	root.size = Vector2i(1280,720)
	session = GameSessionV2.new(); root.add_child(session)
	for i in range(5): await process_frame
	var update = session.repository.commit({"id":"material-capture:"+str(Time.get_ticks_usec()),
		"set":{"settings.quality":"low","settings.auto_fire":false,"settings.control_mode":"assisted",
			"settings.environment_wind":0.0,"settings.environment_weather":0.0,"settings.environment_interference":0.0,
			"settings.camera_zoom":32.0,"settings.ui_scale":1.0,"world.combat_regions":{}},
		"append":{"campaign.completed_missions":session.content.missions.map(func(item):return item.id)}})
	if not bool(update.get("ok",false)):
		failures.append("Isolated capture settings were rejected: "+JSON.stringify(update))
		await _cleanup_session(); return
	session.active_build = CatalogV2.default_build("tr01"); session.save_build(session.active_build)
	session.night = false; session.launch_exploration("R2")
	if not session.flight_active or session.region_id!="R2":
		failures.append("Real R2 exploration did not launch")
		await _cleanup_session(); return
	session.input.take_control("keyboard"); session.input.test_enabled = true
	session.input.test_frame = {"axes":{},"held":[],"edges":[]}
	session.encounter_director.enabled = false
	session.combat.auto_fire = false; session.combat.set_physics_process(false)
	session.combat.clear_enemies(true)
	await process_frame
	# Visual fixture only. Production actors and model hooks run normally in _ready;
	# their physics/brains are then held so every camera/light comparison is identical.
	var pilot_position = Vector3(250,4.5,400)
	session.pilot.practice = true; session.pilot.freeze = true
	session.pilot.global_position = pilot_position
	session.pilot.linear_velocity = Vector3.ZERO; session.pilot.angular_velocity = Vector3.ZERO
	session.pilot.heading = 0; session.pilot.rotation = Vector3.ZERO
	session.pilot.hold_height = pilot_position.y; session.pilot.safe_position = pilot_position
	session.world.update_stream(pilot_position,true)
	session.living.set_weather("clear"); session.living.update_focus(pilot_position)
	session.combat.spawn_wave(["scout","harasser","suppressor","support"],pilot_position)
	var positions = [Vector3(248,3.3,396),Vector3(252,3.3,396),Vector3(248,3.0,392.5),Vector3(252,3.0,392.5)]
	if session.combat.enemies.size()!=4: failures.append("Expected four production enemy actors")
	for i in range(mini(4,session.combat.enemies.size())):
		var actor = session.combat.enemies[i]
		actor.set_physics_process(false); actor.velocity = Vector3.ZERO
		actor.global_position = positions[i]; actor.rotation.y = PI; actor.heading = PI
		actor.home = positions[i]
		_verify_live_model(actor)
	session._snap_camera()
	for i in range(4):
		await physics_frame
		await process_frame
	original_render_loop = RenderingServer.render_loop_enabled
	RenderingServer.render_loop_enabled = false
	RenderingServer.force_sync()
	for i in range(2): await process_frame
	RenderingServer.viewport_set_update_mode(root.get_viewport_rid(),RenderingServer.VIEWPORT_UPDATE_ALWAYS)
	RenderingServer.viewport_set_render_direct_to_screen(root.get_viewport_rid(),false)
	RenderingServer.frame_post_draw.connect(_on_completed_draw)
	manual_draw_active = true
	for dark in [false,true]:
		session.set_lighting(dark)
		for camera_size in [32.0,14.0]:
			session.flight_camera.target_size = camera_size; session._snap_camera()
			if is_instance_valid(session.night_visibility): session.night_visibility.update_state(pilot_position,0,false)
			# Allow the production 0.1 s aircraft/LOS caches and native HUD to settle.
			await create_timer(.25,true,false,true).timeout
			var label = "R2_"+("night" if dark else "day")+"_roles_camera"+str(int(camera_size))
			await _capture_frame(label,dark,camera_size)
	manual_draw_active = false
	RenderingServer.frame_post_draw.disconnect(_on_completed_draw)
	RenderingServer.render_loop_enabled = original_render_loop
	if submitted_draws!=completed_draws: failures.append("Capture draw submissions/completions differ")
	await _cleanup_session()

func _verify_live_model(actor) -> void:
	# No helper call here: verify EnemyActor._ready really prepared the runtime mesh.
	for node in actor.model.find_children("*","MeshInstance3D",true,false):
		if node.mesh==null: continue
		for index in range(node.mesh.get_surface_count()):
			var colors = node.mesh.surface_get_arrays(index)[Mesh.ARRAY_COLOR]
			if not colors is PackedColorArray or colors.is_empty(): continue
			runtime_prepared_surfaces += 1
			var material = node.get_active_material(index)
			if not material is BaseMaterial3D or not material.vertex_color_use_as_albedo or material.vertex_color_is_srgb:
				failures.append("Production actor COLOR_0 preparation failed: "+str(actor.role)+" / "+str(node.name))

func _on_completed_draw() -> void:
	if manual_draw_active: completed_draws += 1

func _draw_once(process_id: int) -> void:
	if not manual_draw_active: return
	if process_id==last_draw_process:
		failures.append("Duplicate manual draw in one process frame"); return
	last_draw_process = process_id
	var now = Time.get_ticks_usec()
	var delta = float(now-last_draw_us)/1000000.0 if last_draw_us>0 else maxf(root.get_process_delta_time(),.000001)
	last_draw_us = now; submitted_draws += 1
	RenderingServer.force_draw(false,delta)
	RenderingServer.force_sync()

func _capture_frame(label: String, dark: bool, camera_size: float) -> void:
	# Two distinct process frames warm newly changed lights/viewport state. The
	# screenshot reads the completed second image and never submits an extra draw.
	for i in range(2):
		await process_frame
		var wanted = submitted_draws+1
		call_deferred("_draw_once",Engine.get_process_frames())
		var deadline = Time.get_ticks_msec()+10000
		while completed_draws<wanted:
			if Time.get_ticks_msec()>deadline:
				failures.append("GPU draw completion timeout: "+label); return
			await process_frame
	var image = root.get_texture().get_image()
	if image==null or image.is_empty(): failures.append("Empty GPU image: "+label); return
	var path = capture_output+"/"+label+".png"
	var saved = image.save_png(path)
	if saved!=OK: failures.append("Cannot save GPU image: "+label)
	var min_luma = 1.0; var max_luma = 0.0; var colors: Dictionary = {}
	for x in range(int(image.get_width()*.25),int(image.get_width()*.85),4):
		for y in range(int(image.get_height()*.2),int(image.get_height()*.75),4):
			var pixel = image.get_pixel(x,y)
			min_luma = minf(min_luma,pixel.get_luminance()); max_luma = maxf(max_luma,pixel.get_luminance())
			colors[pixel.to_html(false)] = true
	if max_luma-min_luma<.05 or colors.size()<12: failures.append("Blank/low-detail capture: "+label)
	var actors: Array = []
	for actor in session.combat.enemies:
		var point = actor.global_position
		var screen = session.camera.unproject_position(point)
		var permitted = session.combat_point_visible(point)
		actors.append({"role":str(actor.role),"position":[point.x,point.y,point.z],"screen":[screen.x,screen.y],
			"night_permission":session.night_point_visible(point),"camera_los_permission":permitted,
			"inside_viewport":root.get_visible_rect().has_point(screen) and not session.camera.is_position_behind(point)})
		if not permitted: failures.append("Fixture actor not visible under production light/LOS: "+label+" / "+str(actor.role))
	var result = {"label":label,"path":path,"sha256":FileAccess.get_sha256(path) if saved==OK else "",
		"width":image.get_width(),"height":image.get_height(),"pixel_bytes":image.get_data().size(),
		"scene_luma_range":max_luma-min_luma,"sampled_unique_colors":colors.size(),"night":dark,"camera_size":camera_size,
		"region":"R2","actors":actors,"submitted_draws":submitted_draws,"completed_draws":completed_draws,
		"draw_calls":RenderingServer.viewport_get_render_info(root.get_viewport_rid(),RenderingServer.VIEWPORT_RENDER_INFO_TYPE_VISIBLE,RenderingServer.VIEWPORT_RENDER_INFO_DRAW_CALLS_IN_FRAME),
		"fixture":"Four production EnemyActor models, static poses, brains/weapon simulation held; normal HUD, fixed camera, exposure and night visibility.",
		"render_method":"Automatic loop disabled; deferred one force_draw(false, real delta) per process frame; completed image readback, no window swap or FPS claim."}
	screenshots.append(result)
	print("V22_COMBAT_MATERIAL_CAPTURE ",JSON.stringify(result))

func _cleanup_session() -> void:
	if is_instance_valid(session):
		if is_instance_valid(session.phone): session.phone.stop_server()
		session.queue_free()
	await process_frame
	await process_frame
	await create_timer(.2,true,false,true).timeout
