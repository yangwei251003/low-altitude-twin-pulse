extends "res://scripts_tools/v3/capture_assets.gd"
## Source-only material A/B capture. Never installs a candidate into production.
const CANDIDATE_ROOT = "res://assets/v3/candidates/forest_floor_p1/"
const CONFIG_PATH = CANDIDATE_ROOT + "candidate.json"
const SHADER_PATH = CANDIDATE_ROOT + "forest_floor_p1.gdshader"
const SETTLE_FRAMES = 8
const TARGETS = ["Shore_west/Surface", "Shore_east/Surface"]
const CORE_INPUTS = [
	"res://scripts_tools/v3/capture_forest_floor_p1.gd",
	"res://scripts_tools/v3/capture_assets.gd",
	"res://assets/v3/materials/twin_ground_study.gdshader",
	"res://assets/v3/materials/twin_water_study.gdshader",
	"res://assets/v3/materials/twin_shore_profile.gdshaderinc",
	"res://scripts/v3/art/twin_ground_surface.gd",
	"res://scripts/v3/twin_test_world.gd",
	"res://scripts/v3/twin_session.gd",
	"res://scripts/v3/gameplay/twin_opening_story.gd",
	"res://scripts/v3/world/twin_shore_layout.gd",
	"res://data/v3/terrain/f1_shore_layout.json",
	"res://data/v3/terrain/f1_growth_crossing.json",
	"res://project.godot"
]
const VIEWS = [
	{"id":"01-south-curve", "position":Vector3(0,6,18), "size":42.0},
	{"id":"02-wet-bank", "position":Vector3(-6,2,36), "size":22.0},
	{"id":"03-normal-flight", "position":Vector3(-23,4.5,28), "size":26.0},
	{"id":"04-distant-context", "position":Vector3(0,6,8), "size":50.0}
]
var originals = {}
var candidates = {}
var checks: Array = []
var config = {}
var texture: ImageTexture
var shader: Shader
var compared_states: Array = []
var input_paths: Array = []

func _run() -> void:
	var safe = false
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--qa-profile=qa_visual_forest_"): safe = true
		if arg.begins_with("--capture-output="): output = arg.trim_prefix("--capture-output=")
	var allowed_root = ProjectSettings.globalize_path("res://artifacts/v3/art/").replace("\\", "/")
	output = ProjectSettings.globalize_path(output).replace("\\", "/").simplify_path()
	if not safe or DisplayServer.get_name() == "headless" or not output.begins_with(allowed_root + "forest-floor-p1-") or output.get_base_dir() != allowed_root.trim_suffix("/"):
		push_error("Requires rendered window, qa_visual_forest_<unique>, and artifacts/v3/art/forest-floor-p1-<unique> output")
		quit(2)
		return
	if DirAccess.dir_exists_absolute(output) or DirAccess.make_dir_recursive_absolute(output) != OK:
		push_error("Capture directory must be new; previous evidence is never overwritten")
		quit(2)
		return
	root.size = Vector2i(1280,720)
	if not _prepare_candidate():
		_finish({}, {})
		return
	input_paths.assign(CORE_INPUTS)
	input_paths.append_array([CONFIG_PATH, SHADER_PATH, str(config.texture_path)])
	var input_before = _input_hashes()
	session = load("res://scenes/v3/main.tscn").instantiate()
	root.add_child(session)
	if not _check(session.start_flight("solo") and session._load_region("F1"), "isolated solo F1 session starts"):
		_finish(input_before, _input_hashes())
		return
	for name in TARGETS:
		var surface = session.world.get_node_or_null(name) as MeshInstance3D
		if not _check(surface != null and surface.material_override is ShaderMaterial, "real F1 bank surface: " + name):
			_finish(input_before, _input_hashes())
			return
		var original = surface.material_override as ShaderMaterial
		originals[name] = original
		var candidate = original.duplicate() as ShaderMaterial
		candidate.shader = shader
		for uniform in ["fantasy_world", "shore_side", "detail_strength", "shore_profile_count", "shore_profile"]:
			var value = original.get_shader_parameter(uniform)
			if value != null: candidate.set_shader_parameter(uniform, value)
		candidate.set_shader_parameter("forest_basecolor", texture)
		for uniform in config.get("parameters", {}):
			candidate.set_shader_parameter(uniform, config.parameters[uniform])
		candidates[name] = candidate
	_check(candidates.size() == 2 and candidates[TARGETS[0]] != originals[TARGETS[0]] and candidates[TARGETS[1]] != originals[TARGETS[1]], "only independent bank material copies receive candidate uniforms")
	# Freeze simulation and node/Tween processing together. Shader uses no TIME.
	session.simulation_paused = true
	session._apply_pause_state()
	session.set_physics_process(false)
	session.set_process(false)
	session.inputs.set_physics_process(false)
	session.inputs.set_process(false)
	paused = true
	var initial_collisions = _collision_signature()
	var water_material = session.world.get_node("Shore_water/Surface").material_override
	for view in VIEWS:
		_pose_fixed(view.position, view.size)
		var baseline = _state_signature()
		_assign_materials(false)
		await _settle_render()
		_save_view(str(view.id) + "-BEFORE", "production", view)
		var before_state = _state_signature()
		_assign_materials(true)
		await _settle_render()
		_save_view(str(view.id) + "-AFTER", "candidate", view)
		var after_state = _state_signature()
		_check(baseline == before_state and before_state == after_state, "same frozen world, camera, clock and pose: " + str(view.id))
		compared_states.append({"view":view.id, "baseline":baseline, "before":before_state, "after":after_state, "equal":baseline == before_state and before_state == after_state})
	_assign_materials(false)
	_check(initial_collisions == _collision_signature(), "all world collision bodies, shapes and transforms unchanged")
	_check(water_material == session.world.get_node("Shore_water/Surface").material_override, "water material resource unchanged")
	for name in TARGETS:
		_check(session.world.get_node(name).material_override == originals[name], "original material restored: " + name)
	_check(shots.size() == 8, "four complete before-after pairs saved")
	var input_after = _input_hashes()
	_check(input_before == input_after, "all source and candidate input bytes unchanged")
	_finish(input_before, input_after)

func _prepare_candidate() -> bool:
	if not _check(FileAccess.file_exists(CONFIG_PATH), "candidate lock file exists"): return false
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(CONFIG_PATH))
	if not _check(parsed is Dictionary, "candidate lock parses"): return false
	config = parsed
	var path = str(config.get("texture_path", ""))
	if not _check(path.begins_with(CANDIDATE_ROOT) and FileAccess.file_exists(path), "texture is an explicit candidate-local file"): return false
	if not _check(FileAccess.get_sha256(path) == str(config.get("texture_sha256", "")), "texture bytes match locked generated source"): return false
	if not _check(FileAccess.get_sha256(SHADER_PATH) == str(config.get("shader_sha256", "")), "candidate shader bytes match lock"): return false
	if not _check(FileAccess.get_sha256("res://assets/v3/materials/twin_ground_study.gdshader") == str(config.get("production_shader_sha256", "")), "production before shader matches declared baseline"): return false
	var source = Image.load_from_file(path)
	if not _check(source != null and not source.is_empty(), "source image decodes without import cache"): return false
	if not _check(source.generate_mipmaps() == OK, "runtime-only mipmaps generated"): return false
	texture = ImageTexture.create_from_image(source)
	shader = load(SHADER_PATH) as Shader
	return _check(texture != null and shader != null, "candidate texture and shader resources created")

func _pose_fixed(at: Vector3, zoom: float) -> void:
	var body = session.players[1]
	body.freeze = true
	body.set_physics_process(false)
	body.set_process(false)
	body.position = at
	body.linear_velocity = Vector3.ZERO
	body.angular_velocity = Vector3.ZERO
	session.entities["player:1"].position = at
	session.flight_camera.target_size = zoom
	session.flight_camera.snap(at)
	session._refresh_interface()
	session.interface.vitals.text = "地表材质对照 · 脚本固定摆位 · 非真人/性能验收"

func _assign_materials(use_candidate: bool) -> void:
	for name in TARGETS:
		session.world.get_node(name).material_override = candidates[name] if use_candidate else originals[name]

func _settle_render() -> void:
	for frame in SETTLE_FRAMES:
		await RenderingServer.frame_post_draw

func _save_view(label: String, variant: String, view: Dictionary) -> void:
	var path = output.path_join(label + ".png")
	var picture = root.get_texture().get_image()
	var error = picture.save_png(path)
	_check(error == OK, "raw viewport PNG saved: " + label)
	shots.append({"id":label, "variant":variant, "file":path, "png_sha256":FileAccess.get_sha256(path), "viewport":str(root.size), "camera_size":session.camera.size, "camera_transform":str(session.camera.global_transform), "pilot_position":str(session.players[1].position), "settle_render_frames":SETTLE_FRAMES, "requested_pose":str(view.position), "texture_sha256":config.texture_sha256 if variant == "candidate" else "none", "shader_sha256":config.shader_sha256 if variant == "candidate" else config.production_shader_sha256})

func _state_signature() -> Dictionary:
	return {"camera":str(session.camera.global_transform), "camera_size":session.camera.size, "pilot":str(session.players[1].transform), "mechanisms":session.world.mechanism_snapshot().duplicate(true), "entities_sha256":JSON.stringify(session.entities).sha256_text(), "lighting":_lighting_signature(), "viewport":str(root.size)}

func _lighting_signature() -> Array:
	var result: Array = []
	for light in session.world.find_children("*", "Light3D", true, false):
		result.append({"path":str(light.get_path()), "transform":str(light.global_transform), "color":str(light.light_color), "energy":light.light_energy, "shadows":light.shadow_enabled})
	for environment in session.world.find_children("*", "WorldEnvironment", true, false):
		var settings = environment.environment
		if settings == null: continue
		result.append({"path":str(environment.get_path()), "resource_id":settings.get_instance_id(), "background":str(settings.background_color), "ambient_color":str(settings.ambient_light_color), "ambient_energy":settings.ambient_light_energy, "tonemap":settings.tonemap_mode})
	return result

func _collision_signature() -> Array:
	var result: Array = []
	for object in session.world.find_children("*", "CollisionObject3D", true, false):
		var shapes: Array = []
		for shape in object.find_children("*", "CollisionShape3D", true, false):
			shapes.append({"path":str(shape.get_path()), "resource_id":shape.shape.get_instance_id() if shape.shape != null else -1, "transform":str(shape.global_transform), "disabled":shape.disabled})
		result.append({"path":str(object.get_path()), "transform":str(object.global_transform), "layer":object.collision_layer, "mask":object.collision_mask, "shapes":shapes})
	return result

func _input_hashes() -> Dictionary:
	var result = {}
	for path in input_paths: result[path] = FileAccess.get_sha256(path)
	return result

func _check(condition: bool, label: String) -> bool:
	checks.append({"name":label, "passed":condition})
	return condition

func _finish(before: Dictionary, after: Dictionary) -> void:
	var passed = not checks.is_empty()
	for check in checks: passed = passed and check.passed
	var report = {"purpose":"Actual Compatibility viewport before/after source-only forest floor material candidate. Fixed same-pose frame waits; no retouching, human play or performance claim.", "status":"diagnostic_material_candidate_not_approved_art", "passed":passed, "checks":checks, "shots":shots, "pairs":compared_states, "input_sha256_before":before, "input_sha256_after":after, "inputs_unchanged":before == after, "candidate":config, "driver":RenderingServer.get_video_adapter_name(), "viewport":str(root.size), "scope":["Only F1 west/east bank material copies replaced", "No geometry, collision, water, Boss or mechanism modification", "Texture supplies surface color, not real roots/rocks/terrain relief", "No performance conclusion; other authorized CPU work may run outside this GPU window"]}
	var file = FileAccess.open(output.path_join("capture.json"), FileAccess.WRITE)
	var write_ok = file != null
	if file != null:
		file.store_string(JSON.stringify(report, "\t"))
		file.flush()
		write_ok = file.get_error() == OK
		file.close()
	paused = false
	if is_instance_valid(session):
		session.network.close()
		session.queue_free()
	print("FOREST_FLOOR_P1_CAPTURE ", JSON.stringify({"output":output, "passed":passed and write_ok, "checks":checks.size(), "shots":shots.size()}))
	quit(0 if passed and write_ok else 1)
