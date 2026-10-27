extends SceneTree
## Production-material viewport capture. No shader/texture replacement, image-file
## decoding, abilities, geometry edits or performance/human-play acceptance.
## Run after normal import with --rendering-method gl_compatibility --windowed
## --resolution 1280x720 --script res://scripts_tools/v3/capture_forest_floor_integrated.gd
## -- --qa-profile=qa_visual_<unique>
## --capture-output=res://artifacts/v3/art/forest-floor-integrated-<unique>

const SIZE := Vector2i(1280, 720)
const SETTLE_FRAMES := 8
const TEXTURE_PATH := "res://assets/v3/materials/forest_floor_surface_v1.png"
const SHADER_PATH := "res://assets/v3/materials/twin_ground_study.gdshader"
const TARGETS := ["Shore_west/Surface", "Shore_east/Surface"]
const INPUTS := [
	"res://scripts_tools/v3/capture_forest_floor_integrated.gd",
	SHADER_PATH, TEXTURE_PATH, TEXTURE_PATH + ".import",
	"res://assets/v3/materials/twin_water_study.gdshader",
	"res://assets/v3/materials/twin_shore_profile.gdshaderinc",
	"res://scripts/v3/art/twin_ground_surface.gd",
	"res://scripts/v3/twin_test_world.gd",
	"res://scripts/v3/twin_session.gd",
	"res://scripts/v3/world/twin_shore_layout.gd",
	"res://data/v3/terrain/f1_shore_layout.json",
	"res://data/v3/terrain/f1_growth_crossing.json",
	"res://scenes/v3/main.tscn", "res://project.godot"
]
const VIEWS := [
	{"id":"01-south-curve", "position":Vector3(0,6,18), "size":42.0},
	{"id":"02-wet-bank", "position":Vector3(-6,2,36), "size":22.0},
	{"id":"03-normal-flight", "position":Vector3(-23,4.5,28), "size":26.0},
	{"id":"04-distant-context", "position":Vector3(0,6,8), "size":50.0}
]

# Official Logger API: https://docs.godotengine.org/en/stable/classes/class_logger.html
# Callbacks may run on render/worker threads; do not print or touch scene objects.
class CaptureLogger extends Logger:
	var guard := Mutex.new()
	var errors: Array = []
	var warnings: Array = []
	var error_total := 0
	var warning_total := 0
	func _log_error(function: String, file: String, line: int, code: String, rationale: String, _editor_notify: bool, error_type: int, _script_backtraces: Array[ScriptBacktrace]) -> void:
		guard.lock()
		var item := {"function":function, "file":file, "line":line, "code":code, "rationale":rationale, "type":error_type}
		if error_type == Logger.ERROR_TYPE_WARNING:
			warning_total += 1
			if warnings.size() < 128: warnings.append(item)
		else:
			error_total += 1
			if errors.size() < 128: errors.append(item)
		guard.unlock()
	func _log_message(message: String, error: bool) -> void:
		if not error or not (message.contains("ERROR:") or message.contains("SCRIPT ERROR:")): return
		guard.lock()
		error_total += 1
		if errors.size() < 128: errors.append({"stderr":message})
		guard.unlock()
	func snapshot() -> Dictionary:
		guard.lock()
		var result := {"error_count":error_total, "warning_count":warning_total, "errors":errors.duplicate(true), "warnings":warnings.duplicate(true)}
		guard.unlock()
		return result

var session
var output := ""
var profile := ""
var checks: Array = []
var shots: Array = []
var bank_records: Array = []
var industrial_materials: Array = []
var industrial_before: Array = []
var input_paths: Array = []
var hashes_before: Dictionary = {}
var import_record: Dictionary = {}
var expected_profile: Dictionary = {}
var capture_logger := CaptureLogger.new()
var finishing := false

func _initialize() -> void:
	OS.add_logger(capture_logger)
	call_deferred("_run")

func _run() -> void:
	if not _arguments_valid():
		push_error("Use a rendered Compatibility window, new qa_visual_<unique> profile and new artifacts/v3/art/forest-floor-integrated-<unique> directory; no other QA driver.")
		OS.remove_logger(capture_logger)
		quit(2)
		return
	if DirAccess.make_dir_recursive_absolute(output) != OK:
		push_error("Cannot create new forest-floor capture directory")
		OS.remove_logger(capture_logger)
		quit(2)
		return
	# Always-processing timer also handles a coroutine stopped by a runtime error.
	create_timer(120.0, true, false, true).timeout.connect(_timeout)
	root.size = SIZE
	input_paths.assign(INPUTS)
	if not _read_import_manifest():
		await _finish()
		return
	hashes_before = _input_hashes()
	if not _hashes_valid(hashes_before):
		await _finish()
		return
	var packed = ResourceLoader.load("res://scenes/v3/main.tscn")
	if not _check(packed is PackedScene, "production main scene loads"):
		await _finish()
		return
	session = packed.instantiate()
	root.add_child(session)
	if not _check(session.profile_ready and session.store.root_path == "user://profiles_v3/" + profile, "session uses the newly isolated profile"):
		await _finish()
		return
	if not _check(session.start_flight("solo") and session.region_id == "I1" and session.players.has(1), "real solo I1 starts without a network QA driver"):
		await _finish()
		return
	_freeze_session()
	var i1 := {"id":"00-I1-production", "position":Vector3(-22,4,30), "size":26.0}
	_inspect_industrial_banks()
	_pose_fixed(i1.position, i1.size)
	await _settle_render()
	_save_view(i1)
	if not _check(session._load_region("F1") and session.region_id == "F1" and session.world.build_errors.is_empty(), "production F1 geometry and mechanisms load"):
		await _finish()
		return
	_freeze_session()
	expected_profile = session.world.shore_layout.shader_data().duplicate(true)
	_inspect_fantasy_banks()
	_verify_shore_parameters("initial")
	var collision_before := _collision_signature()
	var material_ids := _bank_material_ids()
	for view in VIEWS:
		_pose_fixed(view.position, view.size)
		var state_before := _state_signature()
		await _settle_render()
		_save_view(view)
		_check(state_before == _state_signature(), "fixed world/camera/clock during render: " + str(view.id))
	_check(shots.size() == 5, "one industrial and four requested fantasy screenshots saved")
	_check(collision_before == _collision_signature(), "F1 collision objects and shapes unchanged during all material captures")
	_check(material_ids == _bank_material_ids(), "production bank material instances never replaced")
	_check(expected_profile == session.world.shore_layout.shader_data(), "canonical geometry shoreline data unchanged")
	_verify_shore_parameters("final")
	var industrial_after: Array = []
	for material in industrial_materials: industrial_after.append(_material_record(material))
	_check(industrial_after == industrial_before, "F1 texture and shoreline configuration did not mutate retained I1 materials")
	await _finish()

func _arguments_valid() -> bool:
	var profile_count := 0
	var output_count := 0
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--qa-profile="):
			profile_count += 1
			profile = arg.trim_prefix("--qa-profile=")
		elif arg.begins_with("--capture-output="):
			output_count += 1
			output = arg.trim_prefix("--capture-output=")
		elif arg.begins_with("--qa-") or arg.begins_with("--perf-"): return false
	var pattern := RegEx.new()
	if pattern.compile("^qa_visual_[A-Za-z0-9_-]+$") != OK: return false
	if profile_count != 1 or output_count != 1 or pattern.search(profile) == null: return false
	if output.is_empty(): return false
	output = ProjectSettings.globalize_path(output).replace("\\", "/").simplify_path()
	var allowed := ProjectSettings.globalize_path("res://artifacts/v3/art").replace("\\", "/").simplify_path()
	if not output.is_absolute_path() or output.get_base_dir().to_lower() != allowed.to_lower(): return false
	if not output.get_file().begins_with("forest-floor-integrated-") or output.get_file() == "forest-floor-integrated-": return false
	if DirAccess.dir_exists_absolute(output) or FileAccess.file_exists(output): return false
	var profile_path := "user://profiles_v3/" + profile
	if DirAccess.dir_exists_absolute(profile_path) or FileAccess.file_exists(profile_path): return false
	return DisplayServer.get_name() != "headless" and RenderingServer.get_current_rendering_method() == "gl_compatibility" and RenderingServer.is_render_loop_enabled()

func _read_import_manifest() -> bool:
	var config := ConfigFile.new()
	if not _check(config.load(TEXTURE_PATH + ".import") == OK, "normal texture import descriptor exists"): return false
	import_record = {"source":TEXTURE_PATH, "type":config.get_value("remap", "type", ""), "mipmaps_requested":config.get_value("params", "mipmaps/generate", false), "remaps":{}}
	_check(import_record.type == "CompressedTexture2D", "import descriptor declares CompressedTexture2D")
	_check(import_record.mipmaps_requested == true, "production import enables mipmaps")
	if not config.has_section("remap"): return false
	for key in config.get_section_keys("remap"):
		if key == "path" or key.begins_with("path."):
			var path := str(config.get_value("remap", key, ""))
			import_record.remaps[key] = path
			if not _check(path.begins_with("res://.godot/imported/") and FileAccess.file_exists(path), "normal imported texture cache exists: " + key): return false
			if path not in input_paths: input_paths.append(path)
	return _check(not import_record.remaps.is_empty(), "at least one actual imported texture remap is recorded")

func _freeze_session() -> void:
	session.simulation_paused = true
	session._apply_pause_state()
	session.set_physics_process(false)
	session.set_process(false)
	session.inputs.set_physics_process(false)
	session.inputs.set_process(false)
	paused = true

func _pose_fixed(at: Vector3, zoom: float) -> void:
	var body = session.players[1]
	body.freeze = true
	body.set_physics_process(false)
	body.set_process(false)
	body.global_position = at
	body.linear_velocity = Vector3.ZERO
	body.angular_velocity = Vector3.ZERO
	session.entities["player:1"].position = at
	session.flight_camera.target_size = zoom
	session.flight_camera.snap(at)
	session._refresh_interface()
	session.interface.vitals.text = "生产地面材质实机检查 · 脚本固定摆位 · 非真人/性能验收"

func _inspect_industrial_banks() -> void:
	var sides: Array = []
	for mesh in session.world.find_children("*", "MeshInstance3D", true, false):
		var material = mesh.material_override
		if not material is ShaderMaterial or material.shader == null or material.shader.resource_path != SHADER_PATH: continue
		industrial_materials.append(material)
		industrial_before.append(_material_record(material))
		sides.append(float(material.get_shader_parameter("shore_side")))
		_check(material.get_shader_parameter("fantasy_world") == false, "I1 bank retains industrial branch: " + str(mesh.get_path()))
		_check(material.get_shader_parameter("forest_basecolor") == null, "I1 bank has no forest texture binding: " + str(mesh.get_path()))
	sides.sort()
	_check(industrial_materials.size() == 2 and sides == [-1.0, 1.0], "both real I1 bank materials inspected")

func _inspect_fantasy_banks() -> void:
	var imported = ResourceLoader.load(TEXTURE_PATH)
	_check(imported is CompressedTexture2D and imported.resource_path == TEXTURE_PATH, "normal ResourceLoader resolves the production compressed texture")
	for name in TARGETS:
		var surface = session.world.get_node_or_null(name) as MeshInstance3D
		if not _check(surface != null and surface.material_override is ShaderMaterial, "real F1 bank surface exists: " + name): continue
		var material = surface.material_override as ShaderMaterial
		_check(material.shader != null and material.shader.resource_path == SHADER_PATH, "bank uses actual production shader: " + name)
		_check(material.get_shader_parameter("fantasy_world") == true, "fantasy shader branch enabled: " + name)
		var texture = material.get_shader_parameter("forest_basecolor")
		if not _check(texture is CompressedTexture2D, "bound forest texture is CompressedTexture2D: " + name): continue
		_check(texture == imported and texture.resource_path == TEXTURE_PATH, "bank binds normal imported resource, not a runtime ImageTexture: " + name)
		_check(texture.get_width() == 1254 and texture.get_height() == 1254, "actual imported texture dimensions are 1254 square: " + name)
		var image: Image = texture.get_image()
		var has_image: bool = image != null and not image.is_empty()
		_check(has_image and image.has_mipmaps(), "actual imported texture contains mipmaps: " + name)
		var record := _material_record(material)
		record["node"] = name
		record["width"] = texture.get_width()
		record["height"] = texture.get_height()
		record["has_mipmaps"] = image.has_mipmaps() if has_image else false
		record["mipmap_count"] = image.get_mipmap_count() if has_image else 0
		bank_records.append(record)
	_check(bank_records.size() == 2, "both fantasy banks verified through production bindings")

func _verify_shore_parameters(stage: String) -> void:
	var count := int(expected_profile.get("count", 0))
	var points: PackedVector4Array = expected_profile.get("water_points", PackedVector4Array()).duplicate()
	_check(count >= 2 and count <= 32 and points.size() == count, "canonical F1 shoreline is bounded: " + stage)
	points.resize(32)
	for path in ["Shore_west/Surface", "Shore_east/Surface", "Shore_water/Surface"]:
		var surface = session.world.get_node_or_null(path) as MeshInstance3D
		if not _check(surface != null and surface.material_override is ShaderMaterial, "shore material available: " + stage + ":" + path): continue
		var material = surface.material_override as ShaderMaterial
		_check(material.get_shader_parameter("shore_profile_count") == count and material.get_shader_parameter("shore_profile") == points, "all 32 shader rows match the real geometry profile: " + stage + ":" + path)

func _material_record(material: ShaderMaterial) -> Dictionary:
	var texture = material.get_shader_parameter("forest_basecolor")
	return {"instance_id":material.get_instance_id(), "shader":material.shader.resource_path if material.shader != null else "",
		"fantasy_world":material.get_shader_parameter("fantasy_world"), "shore_side":material.get_shader_parameter("shore_side"),
		"texture_class":texture.get_class() if texture is Texture2D else "none", "texture_path":texture.resource_path if texture is Texture2D else "",
		"shore_count":material.get_shader_parameter("shore_profile_count"), "shore_points":str(material.get_shader_parameter("shore_profile"))}

func _bank_material_ids() -> Array:
	var ids: Array = []
	for path in TARGETS:
		var surface = session.world.get_node_or_null(path) as MeshInstance3D
		ids.append(surface.material_override.get_instance_id() if surface != null and surface.material_override != null else -1)
	return ids

func _settle_render() -> void:
	for unused in range(SETTLE_FRAMES): await RenderingServer.frame_post_draw

func _save_view(view: Dictionary) -> void:
	var path := output.path_join(str(view.id) + ".png")
	if not _check(not FileAccess.file_exists(path), "screenshot path is new: " + str(view.id)): return
	var image: Image = root.get_texture().get_image()
	if not _check(image != null and not image.is_empty(), "actual viewport readback is nonempty: " + str(view.id)): return
	_check(image.get_size() == SIZE and root.size == SIZE, "actual capture resolution is 1280x720: " + str(view.id))
	_check(is_equal_approx(float(session.camera.size), float(view.size)) and session.camera.projection == Camera3D.PROJECTION_ORTHOGONAL, "requested fixed oblique orthographic size: " + str(view.id))
	if not _check(image.save_png(path) == OK, "raw rendered PNG saved: " + str(view.id)): return
	var sha := FileAccess.get_sha256(path)
	_check(sha.length() == 64, "saved PNG has a real byte hash: " + str(view.id))
	shots.append({"id":view.id, "region":session.region_id, "file":path, "png_sha256":sha,
		"resolution":[image.get_width(), image.get_height()], "requested_position":_vector(view.position),
		"pilot_position":_vector(session.players[1].global_position), "camera_size":session.camera.size,
		"camera_transform":_transform(session.camera.global_transform), "settle_render_frames":SETTLE_FRAMES,
		"world_clock_seconds":session.world.clock_seconds, "input_sha256":_input_hashes()})

func _state_signature() -> Dictionary:
	return {"camera":_transform(session.camera.global_transform), "camera_size":session.camera.size,
		"pilot":_transform(session.players[1].global_transform), "world_clock":session.world.clock_seconds,
		"mechanisms":session.world.mechanism_snapshot().duplicate(true), "entities_sha256":JSON.stringify(session.entities, "", true, true).sha256_text()}

func _collision_signature() -> Array:
	var result: Array = []
	for object in session.world.find_children("*", "CollisionObject3D", true, false):
		var shapes: Array = []
		for shape in object.find_children("*", "CollisionShape3D", true, false):
			shapes.append({"path":str(shape.get_path()), "resource_id":shape.shape.get_instance_id() if shape.shape != null else -1, "transform":_transform(shape.global_transform), "disabled":shape.disabled})
		result.append({"path":str(object.get_path()), "transform":_transform(object.global_transform), "layer":object.collision_layer, "mask":object.collision_mask, "shapes":shapes})
	return result

func _input_hashes() -> Dictionary:
	var result: Dictionary = {}
	for path in input_paths: result[path] = FileAccess.get_sha256(path) if FileAccess.file_exists(path) else "MISSING"
	return result

func _hashes_valid(values: Dictionary) -> bool:
	var valid := true
	for path in values:
		if not _check(str(values[path]).length() == 64, "input byte hash available: " + str(path)): valid = false
	return valid

func _vector(value: Vector3) -> Array:
	return [value.x, value.y, value.z]

func _transform(value: Transform3D) -> Dictionary:
	return {"origin":_vector(value.origin), "basis_x":_vector(value.basis.x), "basis_y":_vector(value.basis.y), "basis_z":_vector(value.basis.z)}

func _check(condition: bool, label: String) -> bool:
	checks.append({"name":label, "passed":condition})
	return condition

func _timeout() -> void:
	if finishing:
		quit(3)
		return
	_check(false, "capture exceeded 120 second watchdog; incomplete evidence")
	_finish.call_deferred()

func _finish() -> void:
	if finishing: return
	finishing = true
	var stats: Dictionary = session.stats.duplicate(true) if is_instance_valid(session) else {}
	# Include cleanup errors in the same failed-run decision, before writing report.
	if is_instance_valid(session):
		if is_instance_valid(session.network): session.network.close()
		session.queue_free()
	await process_frame
	await process_frame
	var hashes_after := _input_hashes()
	_check(not hashes_before.is_empty() and hashes_before == hashes_after, "production shader/PNG/GroundSurface and imported cache bytes unchanged")
	for shot in shots: _check(shot.input_sha256 == hashes_before, "same input bytes at capture: " + str(shot.id))
	var logged := capture_logger.snapshot()
	_check(int(logged.error_count) == 0, "no engine, script or shader ERROR during actual session/render/cleanup")
	var passed := not checks.is_empty()
	for check in checks: passed = passed and bool(check.passed)
	var report := {"purpose":"Real production I1/F1 material integration viewport, scripted fixed poses; no runtime shader/texture replacement.",
		"status":"captured_for_art_review_not_final_art_acceptance", "passed":passed, "profile":profile,
		"output":output, "checks":checks, "shots":shots, "banks":bank_records, "industrial_before":industrial_before,
		"texture_import":import_record, "input_sha256_before":hashes_before, "input_sha256_after":hashes_after,
		"shoreline_count":expected_profile.get("count", 0), "shoreline_water_points":str(expected_profile.get("water_points", [])),
		"engine_log":logged, "session_stats":stats, "engine_version":Engine.get_version_info(),
		"gpu":RenderingServer.get_video_adapter_name(), "renderer":RenderingServer.get_current_rendering_method(),
		"display":DisplayServer.get_name(), "viewport":[root.size.x, root.size.y], "window":str(DisplayServer.window_get_size()),
		"limitations":["Five raw viewport PNGs; no image editing", "Texture is surface appearance, not real terrain relief",
			"Scripted paused poses are not human play or performance evidence", "Art quality requires inspection of these exact images",
			"Logger is active before production scene/resource loading; script parse/startup failures must also be checked by the runner exit/log"]}
	var path := output.path_join("capture.json")
	var write_ok := not FileAccess.file_exists(path)
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE) if write_ok else null
	write_ok = write_ok and file != null
	if file != null:
		file.store_string(JSON.stringify(report, "\t", true, true))
		file.flush()
		write_ok = file.get_error() == OK
		file.close()
	if not write_ok: push_error("Production material evidence report could not be written")
	var final_log := capture_logger.snapshot()
	var success: bool = passed and write_ok and int(final_log.error_count) == 0
	print("FOREST_FLOOR_INTEGRATED_CAPTURE ", JSON.stringify({"output":output, "passed":success, "checks":checks.size(), "shots":shots.size(), "engine_errors":final_log.error_count}))
	OS.remove_logger(capture_logger)
	quit(0 if success else 1)
