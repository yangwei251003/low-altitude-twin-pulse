extends Node

# Opt-in packaged-runtime smoke test. It never reads a normal player's profile.
var checks = 0
var failures: Array[String] = []
var output = ""
var game: Node3D
var combat_payload: Dictionary = {}
var captures: Array = []
var worldui_smoke_requested = false
var worldui_payload: Dictionary = {"requested":false,"executed":false}

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--evidence-dir="): output = argument.trim_prefix("--evidence-dir=")
		if argument == "--v2-verify-worldui-smoke": worldui_smoke_requested = true
	if not is_instance_valid(game) or not game.qa_mode or output.is_empty() or not output.is_absolute_path():
		push_error("Release verification requires an explicitly isolated QA profile and absolute evidence directory")
		get_tree().quit(2)
		return
	call_deferred("_run")

func check(value: bool, label: String) -> void:
	checks += 1
	if not value: failures.append(label)
	print("EXPORT_V2_", "PASS " if value else "FAIL ", label)

func _capture(name: String) -> void:
	if DisplayServer.get_name() == "headless":
		check(false,"release graphics verification requires a real renderer")
		return
	RenderingServer.viewport_set_update_mode(get_tree().root.get_viewport_rid(),RenderingServer.VIEWPORT_UPDATE_ALWAYS)
	RenderingServer.force_draw(false)
	var image = get_tree().root.get_texture().get_image()
	var nonblank = not image.is_empty() and image.get_width()>=800 and image.get_height()>=450
	var probe = image.duplicate()
	probe.resize(64,36)
	var minimum=1.0;var maximum=0.0
	for y in 36:
		for x in 64:
			var light=probe.get_pixel(x,y).get_luminance()
			minimum=minf(minimum,light);maximum=maxf(maximum,light)
	nonblank=nonblank and maximum-minimum>.03
	check(nonblank,"exported viewport contains nonblank geometry/UI: "+name)
	var destination=output.path_join(name+".png")
	check(image.save_png(destination) == OK,"actual exported viewport saved: "+name)
	captures.append({"name":name,"width":image.get_width(),"height":image.get_height(),"nonblank":nonblank,"sha256":FileAccess.get_sha256(destination)})

func _verify_combat_payload() -> void:
	check(load("res://assets/shaders/v22_combat/visible_body_rim.gdshader") is Shader,"packed visibility-respecting combat rim shader")
	var module_count := 0
	for id in ["damage_model", "enemy_brain", "enemy_actor", "encounter_director", "combat_feedback"]:
		var script = load("res://scripts/v2/"+id+".gd")
		var valid: bool = script is Script and script.can_instantiate()
		check(valid, "packed combat module: "+id)
		if valid: module_count += 1
	var model_path := "res://assets/models/v22_combat/manifest.json"
	var audio_path := "res://assets/audio/v22_combat/manifest.json"
	for path in [model_path, audio_path, "res://assets/models/v22_combat/LICENSE.txt", "res://assets/audio/v22_combat/CREDITS.txt"]:
		check(FileAccess.file_exists(path) and FileAccess.get_file_as_string(path).length()>20, "packed combat manifest/attribution: "+path)
	var models = JSON.parse_string(FileAccess.get_file_as_string(model_path))
	var sounds = JSON.parse_string(FileAccess.get_file_as_string(audio_path))
	var model_ids := ["enemy_scout", "enemy_harasser", "enemy_suppressor", "enemy_support", "weapon_pulse", "weapon_burst", "weapon_lance", "wreck_core", "wreck_rotor", "wreck_panel"]
	var model_seen: Dictionary = {}
	check(models is Dictionary and models.get("models",[]) is Array and models.get("models",[]).size()==10, "ten combat model records packed")
	if models is Dictionary and models.get("models",[]) is Array:
		for entry in models.get("models",[]):
			if not entry is Dictionary:
				check(false, "combat model record is a dictionary")
				continue
			var id := str(entry.get("id",""))
			var path := "res://assets/models/v22_combat/"+id+".glb"
			var valid: bool = id in model_ids and not model_seen.has(id) and entry.get("scene","")==path and entry.get("license","")=="CC0-1.0"
			check(valid, "combat model identity and license: "+id)
			if valid:
				var scene = load(path)
				check(scene is PackedScene, "packed combat model: "+id)
				if scene is PackedScene: model_seen[id] = true
	var families := ["shot_light", "shot_heavy", "near_pass", "impact_metal", "impact_ground", "impact_water", "shield", "component", "destroyed", "wreck", "approach", "warning", "critical"]
	var audio_seen: Dictionary = {}
	var family_counts: Dictionary = {}
	check(sounds is Dictionary and sounds.get("schema",0)==1 and sounds.get("files",[]) is Array and sounds.get("files",[]).size()==37, "37 combat audio records packed")
	if sounds is Dictionary and sounds.get("files",[]) is Array:
		check(str(sounds.get("credits_text","")).replace("\r\n","\n")==FileAccess.get_file_as_string("res://assets/audio/v22_combat/CREDITS.txt").replace("\r\n","\n"), "combat runtime credits agree with manifest")
		for entry in sounds.get("files",[]):
			if not entry is Dictionary:
				check(false, "combat audio record is a dictionary")
				continue
			var id := str(entry.get("id",""))
			var family := str(entry.get("family",""))
			var file := str(entry.get("file",""))
			var valid := not id.is_empty() and not "/" in id and not "\\" in id and file==id+".wav" and family in families and not audio_seen.has(id)
			check(valid, "combat sound identity: "+id)
			if not valid: continue
			var stream = load("res://assets/audio/v22_combat/"+file)
			var decoded: bool = stream is AudioStreamWAV and stream.mix_rate==48000 and not stream.stereo and stream.format==AudioStreamWAV.FORMAT_16_BITS and stream.loop_mode==AudioStreamWAV.LOOP_DISABLED
			check(decoded, "packed combat mono 48k PCM: "+id)
			if decoded:
				check(absf(stream.get_length()-float(entry.get("seconds",0)))<0.03, "packed combat sound duration: "+id)
				audio_seen[id] = true
				family_counts[family] = int(family_counts.get(family,0))+1
	for family in families:
		check(int(family_counts.get(family,0))==(2 if family in ["warning","critical"] else 3), "combat sound variations: "+family)
	combat_payload = {"schema":1,"module_count":module_count,"model_count":model_seen.size(),"audio_count":audio_seen.size(),"family_count":family_counts.size(),"model_manifest_sha256":FileAccess.get_sha256(model_path),"audio_manifest_sha256":FileAccess.get_sha256(audio_path)}

func _worldui_mesh_count(node: Node) -> int:
	var count = 1 if node is MeshInstance3D and node.mesh != null else 0
	for child in node.get_children(): count += _worldui_mesh_count(child)
	return count

func _worldui_top_tile_count(parent: Node) -> int:
	var ground_shader = load("res://assets/shaders/worldui_ground.gdshader")
	var count = 0
	for child in parent.get_children():
		if not child is MeshInstance3D or child.mesh == null or str(child.name).begins_with("Terrain_"): continue
		var material = child.material_override
		if material is ShaderMaterial and material.shader == ground_shader: count += 1
	return count

func _verify_worldui_smoke() -> void:
	worldui_payload = {"requested":true,"executed":false,"automatic_smoke":true,"quality":"standard","scenes":[],"fixture":{},"formal_checkpoint_preserved":false,"human_playthrough":false,"performance_evidence":false,"scope":"Automatic packed-resource and default-entry construction smoke. QA unlock fixture and paused entry stills; no route flight, teleport, task completion, listening, human-input or performance claim."}
	var failures_before = failures.size()
	var checkpoint_before = game.repository._canonical(game.repository.data.campaign.active_checkpoint)
	check(game.qa_mode and game.repository.root_path.begins_with("user://qa_v2/"),"WorldUI smoke remains inside the existing isolated QA repository")
	if not game.qa_mode or not game.repository.root_path.begins_with("user://qa_v2/"): return
	# No model-manifest JSON export dependency: validate the actual 17 GLB imports.
	var model_ids = ["battery","container","container_low","container_offset","conveyor","crane","research","robot_arm","scanner_gate","service","shore_rock","solar","substation","test_frame","turbine","warehouse","workshop"]
	var model_count = 0
	for id in model_ids:
		var packed = load("res://assets/models/worldui/"+id+".glb")
		check(packed is PackedScene,"packed WorldUI GLB loads: "+id)
		if packed is PackedScene: model_count += 1
	worldui_payload["model_count"] = model_count
	check(load("res://assets/shaders/worldui_ground.gdshader") is Shader,"packed WorldUI ground shader loads")
	var layouts: Dictionary = {}
	for id in ["R1","R2","R3","R4"]:
		var path = "res://data/worldui/"+id+".json"
		check(FileAccess.file_exists(path),"packed authored layout exists: "+id)
		var layout = JSON.parse_string(FileAccess.get_file_as_string(path)) if FileAccess.file_exists(path) else null
		var valid: bool = layout is Dictionary and str(layout.get("region_id",""))==id and not layout.get("land",[]).is_empty() and not layout.get("roads",[]).is_empty() and not layout.get("structures",[]).is_empty()
		check(valid,"packed authored geography parses: "+id)
		if valid: layouts[id] = layout
		var preview = load("res://assets/world_ui/previews/"+id+".png")
		check(preview is Texture2D and preview.get_width()>0 and preview.get_height()>0,"packed actual region preview loads: "+id)
	if failures.size()!=failures_before: return
	# Explicit QA setup opens only the gates needed by exploration. It awards no rewards
	# and never overwrites the M01 checkpoint already exercised by the original verifier.
	var fixture = {"id":"qa:worldui-release-smoke:unlock","append":{"campaign.completed_missions":["M04","M08","M12"]},"set":{"settings.quality":"standard"}}
	var seeded: Dictionary = game.repository.commit(fixture)
	check(bool(seeded.get("ok",false)),"explicit QA-only region-gate/standard-quality fixture commits")
	worldui_payload["fixture"] = {"transaction":fixture,"result":seeded,"not_gameplay_completion":true}
	if not bool(seeded.get("ok",false)): return
	game.apply_settings()
	check(str(game.repository.data.settings.get("quality",""))=="standard","WorldUI smoke uses standard quality")
	check(get_viewport().msaa_3d==Viewport.MSAA_2X and game.environment.environment.ssao_enabled,"standard quality render switches are actually applied")
	check(game.repository._canonical(game.repository.data.campaign.active_checkpoint)==checkpoint_before,"QA unlock fixture preserves original formal checkpoint")
	var window_title = get_tree().root.title
	get_tree().root.title = "WorldUI | Automatic 4-region resource smoke | Not human/performance evidence"
	worldui_payload["executed"] = true
	for setup in [{"id":"R1","night":false},{"id":"R2","night":false},{"id":"R3","night":false},{"id":"R4","night":false},{"id":"R4","night":true}]:
		var id = str(setup.id)
		var dark = bool(setup.night)
		var label = id+("_night" if dark else "_day")
		game.night = dark
		game.departure_poi_id = ""
		game.launch_exploration(id)
		var launched: bool = game.flight_active and is_instance_valid(game.world) and is_instance_valid(game.pilot) and str(game.world.region.id)==id and bool(game.current_job.get("exploration",false))
		check(launched,"real exploration world constructs from packed resources: "+label)
		if not launched: break
		# Freeze simulation at the production spawn, without editing pilot pose or task state.
		# UI remains HUD; this is explicitly an entry construction fixture, not a flight test.
		game.input.clear()
		game.input.active = false
		get_tree().paused = true
		if is_instance_valid(game.night_visibility): game.night_visibility.update_state(game.pilot.global_position,game.pilot.heading,false)
		for i in range(5): await get_tree().process_frame
		var world = game.world
		var spawn_id = str(world.region.spawn_poi)
		var spawn: Vector3 = world.poi_position(spawn_id)
		check(str(world.layout.get("region_id",""))==id and world.layout.get("land",[]).size()==layouts[id].land.size(),"live World uses the matching authored layout: "+label)
		check(world.poi_index.size()==world.region.pois.size() and world.poi_index.has(spawn_id),"live POI index matches region catalog: "+label)
		check(world.poi_nodes.has(spawn_id) and is_instance_valid(world.poi_nodes[spawn_id]) and world.poi_nodes[spawn_id].is_inside_tree(),"entry POI exists as an actual scene node: "+label)
		check(Vector2(game.pilot.global_position.x-spawn.x,game.pilot.global_position.z-spawn.z).length()<0.01,"capture remains at normal exploration entry: "+label)
		var ground_nodes = 0
		for land in layouts[id].land:
			var ground = world.get_node_or_null("Terrain_"+str(land.id))
			if ground is MeshInstance3D and ground.mesh != null: ground_nodes += 1
		check(ground_nodes==layouts[id].land.size(),"all authored terrain perimeter meshes constructed: "+label)
		var top_tiles = _worldui_top_tile_count(world)
		check(top_tiles>0,"live world contains horizontal ground shader mesh tiles: "+label)
		var built_structures: Array = []
		for item in layouts[id].structures:
			var cell = Vector2i(floori(float(item.x)/100.0),floori(float(item.z)/100.0))
			if not world.chunks.has(cell): continue
			var structure = world.chunks[cell].get_node_or_null(str(item.id))
			var mesh_count = _worldui_mesh_count(structure) if is_instance_valid(structure) else 0
			check(is_instance_valid(structure) and structure.get_child_count()>0 and mesh_count>0,"streamed model assembly exists: "+str(item.id)+" / "+label)
			if mesh_count>0: built_structures.append({"id":str(item.id),"asset":str(item.asset),"mesh_count":mesh_count})
		check(not built_structures.is_empty(),"entry contains real WorldUI model assemblies: "+label)
		var minimap = game.ui.minimap
		check(is_instance_valid(minimap) and minimap.is_inside_tree() and str(minimap.region.id)==id,"live HUD map binds to current region: "+label)
		var row = {"region":id,"night":dark,"quality":str(game.repository.data.settings.quality),"layout_sha256":FileAccess.get_sha256("res://data/worldui/"+id+".json"),"terrain_perimeter_mesh_count":ground_nodes,"ground_top_tile_count":top_tiles,"poi_count":world.poi_index.size(),"loaded_poi_count":world.poi_nodes.size(),"spawn_poi":spawn_id,"structures":built_structures,"capture":"worldui_smoke_"+label+"_entry.png"}
		if dark:
			check(is_instance_valid(game.night_visibility) and game.night,"waste-port night visibility controller is active")
			check(not game.night_point_visible(game.pilot.global_position+Vector3(100,0,0)),"waste-port night smoke does not disclose distant entities")
		await _capture("worldui_smoke_"+label+"_entry")
		game.open_overview()
		for i in range(3): await get_tree().process_frame
		var chart = game.ui._map
		var map_bound: bool = is_instance_valid(chart) and chart.is_inside_tree() and chart.is_visible_in_tree() and str(chart.region.id)==id
		var map_meshes = _worldui_mesh_count(game.overview_proxy) if is_instance_valid(game.overview_proxy) else 0
		check(game.flight_camera.overview and map_bound and map_meshes>0,"live regional chart binds to overview mode and a nonempty proxy: "+label)
		var overview_ground_nodes = 0
		if is_instance_valid(game.overview_proxy):
			for land in layouts[id].land:
				var ground = game.overview_proxy.get_node_or_null("Terrain_"+str(land.id))
				if ground is MeshInstance3D and ground.mesh != null: overview_ground_nodes += 1
		check(overview_ground_nodes==layouts[id].land.size(),"all authored overview terrain perimeter meshes constructed: "+label)
		var overview_top_tiles = _worldui_top_tile_count(game.overview_proxy) if is_instance_valid(game.overview_proxy) else 0
		check(overview_top_tiles>0,"overview contains horizontal ground shader mesh tiles: "+label)
		RenderingServer.force_draw(false)
		row["map_bound"] = map_bound
		row["overview_mesh_count"] = map_meshes
		row["overview_terrain_perimeter_mesh_count"] = overview_ground_nodes
		row["overview_ground_top_tile_count"] = overview_top_tiles
		worldui_payload.scenes.append(row)
		game.close_overview()
		game.show_hangar()
		for i in range(4): await get_tree().process_frame
		check(not game.flight_active and game.pending_transaction.is_empty(),"exploration smoke returns through normal hangar transaction: "+label)
		check(game.repository._canonical(game.repository.data.campaign.active_checkpoint)==checkpoint_before,"formal M01 checkpoint survives exploration smoke: "+label)
	get_tree().root.title = window_title
	worldui_payload["formal_checkpoint_preserved"] = game.repository._canonical(game.repository.data.campaign.active_checkpoint)==checkpoint_before
	worldui_payload["settings"] = {"quality":game.repository.data.settings.get("quality",""),"msaa_3d":get_viewport().msaa_3d,"viewport_size":[get_viewport().get_visible_rect().size.x,get_viewport().get_visible_rect().size.y]}
	check(worldui_payload.scenes.size()==5,"all four daytime entries and waste-port night entry checked")
	check(bool(worldui_payload.formal_checkpoint_preserved),"four-region smoke preserves the original M01 formal checkpoint")

func _run() -> void:
	DirAccess.make_dir_recursive_absolute(output)
	check(not OS.is_debug_build(),"running release runtime, not editor binary")
	check(ProjectSettings.get_setting("application/run/main_scene") == "res://scenes/v2_main.tscn","embedded V2 main scene")
	for path in ["res://data/v2/world_content.json","res://phone/index.html","res://phone/app.js","res://phone/style.css","res://assets/v2/audio/audio_manifest.json","res://assets/licenses/Godot-runtime.txt","res://phone/vendor/qr_code/LICENSE.md"]:
		check(FileAccess.file_exists(path) and FileAccess.get_file_as_string(path).length()>20,"packed file: "+path)
	var catalog = load("res://scripts/v2/catalog.gd")
	for id in ["bench","bus_stop","street_lamp","traffic_light","wayfinding_sign","recycling_bins","planter","coffee_kiosk","bicycle_rack","bollards","promenade_railing","utility_cabinet","cafe_table","street_tree","street_tree_round","street_tree_slender","pergola","office_pavilion","waterfront_cafe","harbor_warehouse","canal_apartments","car_sedan","car_suv","car_delivery","car_van"]:
		check(load("res://assets/v2/streets/"+id+".glb") is PackedScene,"packed V2.1 street model: "+id)
	check(load("res://assets/v2/ui/waterfront_menu.png") is Texture2D,"packed menu illustration")
	for id in ["ground","water"]: check(load("res://assets/v2/"+id+".gdshader") is Shader,"packed world shader: "+id)
	check(FileAccess.file_exists("res://assets/v2/audio/source_credits.json"),"packed audio source credits")
	var content: Dictionary = catalog.content()
	check(ProjectSettings.get_setting("application/config/custom_user_dir_name")=="LowAltitudeSquadV22LivingWorld","V2.2 isolated save directory")
	_verify_combat_payload()
	var v22_manifest=JSON.parse_string(FileAccess.get_file_as_string("res://assets/audio/v22/manifest.json"))
	check(v22_manifest is Dictionary and v22_manifest.get("music",[]).size()>=6,"V2.2 complete playlist packed")
	if v22_manifest is Dictionary:
		for group in ["music","environment","voice"]:
			for entry in v22_manifest.get(group,[]):check(load("res://assets/audio/v22/"+str(entry.file)) is AudioStream,"packed V2.2 sound: "+str(entry.id))
	for id in ["weather_station","ventilator","gantry_crane","lift_platform","shore_bank","bridge_deck","floating_dock","pedestrian_citizen","pedestrian_walker","pedestrian_worker","construction_barrier","shore_reeds","seagull"]:
		check(load("res://assets/models/v22/"+id+".glb") is PackedScene,"packed editable-origin V2.2 model: "+id)
	check(content.regions.size()==4 and content.missions.size()==16,"runtime catalog is full V2")
	for id in catalog.airframes().keys()+catalog.modules().keys():
		if str(id).begins_with("stock") or id == "none": continue
		check(ResourceLoader.exists("res://assets/v2/models/"+str(id)+".glb"),"packed GLB: "+str(id))
	var manifest = JSON.parse_string(FileAccess.get_file_as_string("res://assets/v2/audio/audio_manifest.json"))
	for asset in manifest.assets:
		var stream = load("res://assets/v2/audio/"+str(asset.file))
		check(stream is AudioStreamWAV and stream.mix_rate==48000 and stream.format==AudioStreamWAV.FORMAT_16_BITS,"packed 48k PCM: "+str(asset.id))
	for i in range(10): await get_tree().process_frame
	if is_instance_valid(game.audio) and game.audio.has_method("get_combat_audio_debug"):
		var combat_audio: Dictionary = game.audio.get_combat_audio_debug()
		check(combat_audio.get("loaded_streams",0)==37 and combat_audio.get("voice_limit",0)==12, "release combat audio loads all assets with bounded voices")
	else:
		check(false, "release combat audio API is installed")
	check(game.repository.root_path.begins_with("user://qa_v2/"),"release startup uses explicitly isolated QA profile")
	check(game.profiles.base_path == game.repository.root_path.path_join("profiles"),"release profile selector uses this session's isolated QA catalog")
	check(not game.flight_active and is_instance_valid(game.preview),"release opens real hangar and model")
	await _capture("release_hangar")
	var http = HTTPRequest.new()
	http.timeout = 5.0
	add_child(http)
	check(game.phone.start_server("127.0.0.1")==OK,"release local phone server explicitly opens an available port pair")
	var status: Dictionary = game.phone.get_status()
	for path in ["/","/app.js","/style.css"]:
		var request_error = http.request("http://127.0.0.1:%d%s" % [status.http_port,path])
		check(request_error==OK,"release phone request initiated: "+path)
		if request_error == OK:
			var response: Array = await http.request_completed
			check(response[1]==200 and response[3].size()>100,"release serves embedded phone asset: "+path)
	game.phone.stop_server()
	game.launch_job("M01")
	check(game.flight_active and is_instance_valid(game.pilot) and is_instance_valid(game.runner),"release constructs playable M01")
	get_tree().paused = false
	game.pause_reasons.clear()
	game.input.active = true
	var start: Vector3 = game.pilot.global_position
	Input.action_press("flight_high")
	for i in range(90): await get_tree().physics_frame
	Input.action_release("flight_high")
	check(game.pilot.global_position.y>start.y+0.5,"real keyboard action drives exported rigid body upward")
	await _capture("release_flight")
	game.set_lighting(true)
	for i in range(10):await get_tree().process_frame
	check(is_instance_valid(game.night_visibility),"release night visibility is installed")
	check(not game.night_point_visible(game.pilot.global_position+Vector3(100,0,0)),"release darkness hides distant world")
	await _capture("release_night")
	game.open_overview()
	for i in range(5):await get_tree().process_frame
	check(not game.night_point_visible(game.pilot.global_position+Vector3(100,0,0)),"release overview cannot bypass darkness")
	await _capture("release_night_map")
	game.close_overview()
	game.pause_game("manual")
	check(get_tree().paused,"release pause stops simulation")
	game.resume_game()
	check(not get_tree().paused,"release explicit neutral resume works")
	game.show_hangar()
	for i in range(5): await get_tree().process_frame
	check(game.repository.data.campaign.active_checkpoint.job_id=="M01","release checkpoint survives return to hangar")
	if worldui_smoke_requested: await _verify_worldui_smoke()
	var report = {"suite":"exported_release","game_version":"2.2.0","combat_payload":combat_payload,"worldui_payload":worldui_payload,"display_server":DisplayServer.get_name(),"captures":captures,"checks":checks,"failures":failures,"ok":failures.is_empty(),"executable":OS.get_executable_path(),"engine":Engine.get_version_info().string,"renderer":RenderingServer.get_video_adapter_name(),"driver":RenderingServer.get_current_rendering_method(),"content_sha256":content.get("_source_sha256",""),"evidence_scope":"Extracted release executable, packed combat modules/models/audio/attribution, real rendered startup and keyboard-action flight, local HTTP only. Resource loading is not audio-output/listening evidence, a complete campaign or physical mobile-device test."}
	var file = FileAccess.open(output.path_join("release_summary.json"),FileAccess.WRITE)
	file.store_string(JSON.stringify(report,"\t"))
	file.close()
	print("EXPORT_V2_SUMMARY ",JSON.stringify(report))
	get_tree().quit(0 if failures.is_empty() else 1)
