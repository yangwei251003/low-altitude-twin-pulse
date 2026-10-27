extends SceneTree
## Six production viewport captures, not a performance/human-play test.
## After normal import, run with --rendering-method gl_compatibility --windowed
## --resolution 1280x720 --script res://scripts_tools/v3/capture_thermal_bypass_integrated.gd
## -- --qa-profile=qa_visual_thermal_<unique>
## --capture-output=res://artifacts/v3/art/thermal-bypass-<unique>
## Body pose is a frozen QA fixture; AGL remains cached, not measured clearance.
## 5/Tab/F/F/X use Session's input handler. Only production physics advances
## energy, cooldown, temperature/power effects and gate movement. No state refill.

const HudCapture = preload("res://scripts_tools/v3/capture_hud_visibility.gd")
const SIZE := Vector2i(1280, 720)
const MODEL := "res://assets/v3/thermal_bypass/thermal_bypass.glb"
const MODEL_SHA := "c9ae203562a36038b807dccea4e410f26356273c9130251e9d972e80491ab7f9"
const THERMAL := "I1:thermal"
const INPUTS := [
	"res://scripts_tools/v3/capture_thermal_bypass_integrated.gd",
	"res://scripts_tools/v3/capture_hud_visibility.gd", "res://project.godot",
	"res://scenes/v3/main.tscn", "res://scripts/v3/twin_session.gd",
	"res://scripts/v3/twin_interface.gd", "res://scripts/v3/twin_network.gd",
	"res://scripts/v3/twin_test_world.gd", "res://scripts/v2/flight_body.gd",
	"res://scripts/v2/pilot_input.gd", "res://scripts/v2/flight_camera.gd",
	"res://scripts/v3/gameplay/twin_ability_rules.gd",
	"res://scripts/v3/gameplay/twin_opening_story.gd",
	"res://scripts/v3/ui/twin_opening_guidance.gd",
	"res://scripts/v3/art/twin_thermal_bypass.gd",
	"res://scenes/v3/assets/thermal_bypass.tscn", MODEL, MODEL + ".import",
	"res://scripts/v3/art/twin_ground_surface.gd",
	"res://assets/v3/materials/twin_ground_study.gdshader",
	"res://assets/v3/materials/twin_water_study.gdshader",
	"res://assets/v3/materials/twin_shore_profile.gdshaderinc",
	"res://data/v3/actions/opening_actions.json"
]

var session
var art
var body
var output := ""
var profile := ""
var checks: Array = []
var shots: Array = []
var actions: Array = []
var live_windows: Array = []
var pause_probe: Dictionary = {}
var asset_record: Dictionary = {}
var input_paths: Array = []
var hashes_before: Dictionary = {}
var static_materials_before: Dictionary = {}
var authored_materials_before: Dictionary = {}
var capture_logger = HudCapture.CaptureLogger.new()
var finishing := false
var centre := Vector3.ZERO
var fixed_pose := Vector3.ZERO
var expected_zoom := 26.0

func _initialize() -> void:
	OS.add_logger(capture_logger)
	_run.call_deferred()

func _run() -> void:
	if not _arguments_valid():
		push_error("THERMAL_CAPTURE requires fresh qa_visual_thermal_ profile/output and debug Compatibility viewport")
		OS.remove_logger(capture_logger)
		quit(2)
		return
	if DirAccess.make_dir_recursive_absolute(output) != OK:
		push_error("THERMAL_CAPTURE cannot create evidence directory")
		OS.remove_logger(capture_logger)
		quit(2)
		return
	create_timer(120.0, true, false, true).timeout.connect(_timeout)
	root.size = SIZE
	input_paths.assign(INPUTS)
	# Hash normal-imported PNGs, descriptors and remap cache, not a decoded image substitute.
	for filename in DirAccess.get_files_at(MODEL.get_base_dir()):
		if filename.ends_with(".png"): input_paths.append(MODEL.get_base_dir().path_join(filename))
	_add_import_hashes()
	hashes_before = _input_hashes()
	var complete_inputs := not hashes_before.is_empty()
	for value in hashes_before.values(): complete_inputs = complete_inputs and str(value).length() == 64
	if not _check(complete_inputs and hashes_before.get(MODEL, "") == MODEL_SHA, "all input bytes/remap cache exist and runtime GLB matches frozen SHA"):
		await _finish()
		return
	var packed = ResourceLoader.load("res://scenes/v3/main.tscn")
	if not _check(packed is PackedScene, "production main scene loads"):
		await _finish()
		return
	session = packed.instantiate()
	root.add_child(session)
	if not _check(session.profile_ready and session.store.root_path == "user://profiles_v3/" + profile, "fresh isolated QA store"):
		await _finish()
		return
	if not _check(session.start_flight("solo") and session.region_id == "I1" and session.players.has(1), "real fresh I1 solo Session"):
		await _finish()
		return
	body = session.players[1]
	art = session.world.art_thermal
	_freeze()
	if not _check(is_instance_valid(art) and art.imported and art.import_errors.is_empty(), "production World imports real thermal wrapper"):
		await _finish()
		return
	centre = session.entities[THERMAL].position
	fixed_pose = centre + Vector3(0, 3, 4)
	body.global_position = fixed_pose
	body.linear_velocity = Vector3.ZERO
	body.angular_velocity = Vector3.ZERO
	session.entities["player:1"].position = fixed_pose
	_camera(26.0)
	_check(centre == Vector3(-29, 1, 8) and art.global_position.distance_to(Vector3(-29, 0, 8)) < 0.0001,
		"actual thermal centre and bottom-origin placement match integrated contract")
	_check(session.network.mode == "solo" and session.qa_mode.is_empty() and not session.boss_active
		and session.story.state.get("completed", []).is_empty(), "no network/combat/story fixture or completed objective")
	asset_record = _inspect_asset()
	static_materials_before = _materials(true)
	authored_materials_before = _materials(false, true)
	if not _asset_checks_passed():
		await _finish()
		return
	_key(KEY_5)
	var tabs := 0
	while str(session.locks.get(1, "")) != THERMAL and tabs < 64:
		_key(KEY_TAB)
		tabs += 1
	_check(session.selected_ability == "heat" and str(session.locks.get(1, "")) == THERMAL,
		"real 5/Tab selection reaches thermal without forging network action")
	actions.append({"input":"5 then Tab", "tab_count":tabs, "ability":session.selected_ability, "lock":str(session.locks.get(1, ""))})
	if session.selected_ability != "heat" or str(session.locks.get(1, "")) != THERMAL:
		await _finish()
		return
	await _fan_stopped_probe("cold20")
	_check(_temperature_is(20.0, false) and float(session.world.gate_fraction) == 0.0 and _other_sources_off(), "fresh cold20 unpowered, gate closed, all alternate sources off")
	await _capture("01-default26-cold20", 26.0)
	await _capture("02-close12-cold20", 12.0)
	if not _cast(KEY_F, 45.0, false):
		await _finish()
		return
	if not await _live_window("first_F_cooldown", 0.0, 1.0):
		await _finish()
		return
	await _capture("03-close12-warm45", 12.0)
	if not _cast(KEY_F, 70.0, true):
		await _finish()
		return
	if not await _live_window("second_F_gate_open", 1.0, 3.0):
		await _finish()
		return
	await _hot_pause_probe()
	await _capture("04-close12-hot70", 12.0)
	await _capture("05-default26-hot70", 26.0)
	if not _cast(KEY_X, 45.0, false):
		await _finish()
		return
	if not await _live_window("X_gate_closed", 0.0, 3.0):
		await _finish()
		return
	await _fan_stopped_probe("cooled45_unpowered")
	await _capture("06-close12-X-cooled45", 12.0)
	_check(int(session.stats.abilities) == 3 and int(session.stats.rejected_abilities) == 0,
		"exactly three genuine accepted casts, no rejected casts")
	_check(session.story.state.get("completed", []).is_empty() and not session.boss_active
		and session.network.mode == "solo", "captures did not complete story, start Boss or open multiplayer")
	_check(_materials(true) == static_materials_before and _materials(false, true) == authored_materials_before,
		"housing/fan materials and shared imported source materials remain unchanged")
	if shots.size() == 6:
		var cold: Dictionary = shots[0].state
		var warm: Dictionary = shots[2].state
		var hot: Dictionary = shots[3].state
		var cooled: Dictionary = shots[5].state
		_check(float(cold.pipe_emission) == 0.0 and float(warm.pipe_emission) > 0.0
			and float(hot.pipe_emission) > float(warm.pipe_emission) and float(hot.pipe_emission) <= 0.16001
			and is_equal_approx(float(cooled.pipe_emission), float(warm.pipe_emission)), "actual dedicated pipe emissions order20/45/70/45 and retain restrained cap")
		_check(cold.lens_emission_color != warm.lens_emission_color and warm.lens_emission_color != hot.lens_emission_color
			and warm.lens_emission_color == cooled.lens_emission_color and float(hot.lens_emission) <= 0.80001,
			"actual temperature-window colour changes and X restores warm appearance")
		_check(shots[0].state == shots[1].state and shots[3].state == shots[4].state,
			"cold and hot default/close pairs share identical captured state and fan phase")
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
	if pattern.compile("^qa_visual_thermal_[A-Za-z0-9_-]+$") != OK: return false
	if profile_count != 1 or output_count != 1 or pattern.search(profile) == null or output.is_empty(): return false
	output = ProjectSettings.globalize_path(output).replace("\\", "/").simplify_path()
	var allowed := ProjectSettings.globalize_path("res://artifacts/v3/art").replace("\\", "/").simplify_path()
	if not output.is_absolute_path() or output.get_base_dir().to_lower() != allowed.to_lower(): return false
	if not output.get_file().begins_with("thermal-bypass-") or output.get_file() == "thermal-bypass-": return false
	if DirAccess.dir_exists_absolute(output) or FileAccess.file_exists(output): return false
	if DirAccess.dir_exists_absolute("user://profiles_v3/" + profile) or FileAccess.file_exists("user://profiles_v3/" + profile): return false
	return OS.is_debug_build() and DisplayServer.get_name() != "headless" and RenderingServer.get_current_rendering_method() == "gl_compatibility" and RenderingServer.is_render_loop_enabled()

func _freeze() -> void:
	session.set_process(false)
	session.set_physics_process(false)
	session.inputs.set_process(false)
	session.inputs.set_physics_process(false)
	for pilot in session.players.values():
		pilot.freeze = true
		pilot.set_process(false)
		pilot.set_physics_process(false)
	session.world.set_effects_paused(true)
	# Session.simulation_paused stays false, so real F/X validation remains active.
	paused = true

func _camera(zoom: float) -> void:
	expected_zoom = zoom
	session.flight_camera.target_size = zoom
	session.flight_camera.snap(centre)
	session.story.refresh(fixed_pose, 0.0)
	session._refresh_interface()

func _key(code: Key) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = code
	event.keycode = code
	event.pressed = true
	session._unhandled_input(event)

func _cast(code: Key, expected_temperature: float, expected_power: bool) -> bool:
	var before := {"energy":session.entities["player:1"].energy, "cooldown":session.cooldowns.get(1, 0), "stats":session.stats.duplicate(true), "thermal":_safe(session.entities[THERMAL])}
	_key(code)
	var record := {"input":"X" if code == KEY_X else "F", "before":before,
		"after":{"energy":session.entities["player:1"].energy, "cooldown":session.cooldowns.get(1, 0), "stats":session.stats.duplicate(true), "thermal":_safe(session.entities[THERMAL])}}
	actions.append(record)
	return _check(_temperature_is(expected_temperature, expected_power)
		and int(session.stats.abilities) == int(before.stats.abilities) + 1
		and int(session.stats.rejected_abilities) == int(before.stats.rejected_abilities)
		and is_equal_approx(float(session.entities["player:1"].energy), float(before.energy) - 8.0)
		and is_equal_approx(float(session.cooldowns.get(1, 0)), 0.35), "real " + str(record.input) + " applies temperature, power,8 energy and normal cooldown")

func _live_window(label: String, desired_gate: float, limit: float) -> bool:
	var before := {"clock":session.world.clock_seconds, "energy":session.entities["player:1"].energy,
		"cooldown":session.cooldowns.get(1, 0), "health":body.health, "pose":_vec(body.global_position), "fan_phase":art._fan_phase}
	session.inputs.test_enabled = true
	session.inputs.test_frame = {"axes":{}, "held":[], "edges":[]}
	session.world.set_effects_paused(false)
	session.set_physics_process(true)
	paused = false
	var waited := 0
	var reached := false
	while waited < 400:
		await physics_frame
		await process_frame
		if finishing: return false
		waited += 1
		reached = absf(float(session.world.gate_fraction) - desired_gate) <= 0.0001 and float(session.cooldowns.get(1, 0)) <= 0.0
		if reached or float(session.world.clock_seconds) - float(before.clock) >= limit: break
	_freeze()
	var elapsed := float(session.world.clock_seconds) - float(before.clock)
	var record := {"label":label, "before":before, "after":_state(), "actual_simulated_seconds":elapsed,
		"max_simulated_seconds":limit, "awaited_frame_pairs":waited, "gate_target":desired_gate, "reached":reached}
	live_windows.append(record)
	_check(elapsed > 0.0 and absf(float(session.entities["player:1"].energy) - minf(100.0, float(before.energy) + elapsed * 9.0)) < 0.0001
		and absf(float(session.cooldowns.get(1, 0)) - maxf(0.0, float(before.cooldown) - elapsed)) < 0.0001,
		"production physics alone advances energy/cooldown: " + label)
	_check(body.freeze and body.global_position.distance_to(fixed_pose) < 0.0001 and body.health == before.health,
		"fixed capture body/health preserved during real Session ticks: " + label)
	_check(_other_sources_off(), "alternate gate sources stay initially off: " + label)
	return _check(reached and elapsed <= limit + 0.000001, "gate reaches requested physical fraction within bounded real simulation: " + label)

func _fan_stopped_probe(label: String) -> void:
	var before := _state()
	session.world.set_effects_paused(false)
	paused = false
	for unused in range(8):
		await process_frame
		if finishing: return
	_freeze()
	var after := _state()
	_check(before == after and float(art._fan_speed) == 0.0 and not bool(art._powered),
		"actual automatic visual frames leave unpowered fan stationary: " + label)

func _hot_pause_probe() -> void:
	var before := _state()
	# Let real process frames run while the production effects-pause API is active.
	# Session physics stays disabled; this is not a fabricated network pause vote.
	session.world.set_effects_paused(true)
	paused = false
	for unused in range(10):
		await process_frame
		if finishing: return
	var stopped := _state()
	session.world.set_effects_paused(false)
	for unused in range(10):
		await process_frame
		if finishing: return
	_freeze()
	var resumed := _state()
	pause_probe = {"kind":"production_effects_pause_with_actual_process_frames", "before":before, "paused":stopped, "resumed":resumed}
	_check(before == stopped and _temperature_is(70.0, true), "effects pause stops actual hot fan without erasing heat or changing gameplay state")
	_check(resumed.fan_phase != stopped.fan_phase and resumed.fan_transform != stopped.fan_transform
		and resumed.pipe_emission == stopped.pipe_emission and resumed.lens_emission_color == stopped.lens_emission_color
		and resumed.thermal == stopped.thermal and resumed.clock == stopped.clock and resumed.energy == stopped.energy,
		"actual resumed process frames rotate retained fan with unchanged temperature, colour, energy and simulation clock")

func _capture(id: String, zoom: float) -> void:
	_camera(zoom)
	var reference := _state()
	for unused in range(8): await RenderingServer.frame_post_draw
	if finishing: return
	var after := _state()
	var path := output.path_join(id + ".png")
	var image: Image = root.get_texture().get_image()
	var valid := image != null and not image.is_empty() and image.get_size() == SIZE and root.size == SIZE
	valid = valid and session.camera.projection == Camera3D.PROJECTION_ORTHOGONAL and is_equal_approx(float(session.camera.size), expected_zoom)
	if not _check(valid and reference == after, "stable production720p capture reference and requested orthographic camera: " + id): return
	if not _check(not FileAccess.file_exists(path) and image.save_png(path) == OK, "save fresh rendered PNG: " + id): return
	var bound := _bounds(art)
	var box := AABB(Vector3(-1.5, 0, -1), Vector3(3, 2, 2)).grow(0.005)
	_check(box.encloses(bound) and _materials(true) == static_materials_before, "actual posed vertices stay inside old collision envelope; housing unchanged: " + id)
	shots.append({"id":id, "file":path, "png_sha256":FileAccess.get_sha256(path), "resolution":[SIZE.x,SIZE.y],
		"state":after, "camera":{"target":_vec(centre), "size":session.camera.size, "transform":_transform(session.camera.global_transform)},
		"asset_bounds_bottom_local":{"min":_vec(bound.position), "max":_vec(bound.end)}, "input_sha256":_input_hashes(),
		"height_provenance":{"mode":"frozen_QA_body_pose_cached_AGL", "body_world_Y":body.global_position.y, "cached_AGL":body.ground_distance,
			"limitation":"No real flight integration/clearance claim; body was positioned while frozen and ground_distance was never assigned."},
		"vitals_text":session.interface.vitals.text, "target_text":session.interface.target_info.text})

func _inspect_asset() -> Dictionary:
	var meshes := _meshes(art.visual)
	var surfaces := 0
	var triangles := 0
	var names: Dictionary = {}
	var textures: Dictionary = {}
	var pbr_ok := true
	var nodes: Dictionary = {}
	for key in ["FanRotor", "FanBlades", "HeatPipes", "StatusLens", "StaticHousing", "StaticSteel", "StaticSafety", "InteractionCentre", "BaseOrigin"]:
		var found: Array[Node] = art.visual.find_children(key, "", true, false)
		if found.size() == 1 and found[0] is Node3D:
			var node := found[0] as Node3D
			nodes[key] = {"path":str(art.visual.get_path_to(node)), "local_transform":_transform(node.transform), "bottom_local":_vec(art.to_local(node.global_position))}
		else: nodes[key] = {"count":found.size()}
	for mesh in meshes:
		surfaces += mesh.mesh.get_surface_count()
		triangles += int(mesh.mesh.get_faces().size() / 3.0)
		for surface in range(mesh.mesh.get_surface_count()):
			var material := mesh.get_active_material(surface) as BaseMaterial3D
			if material == null:
				pbr_ok = false
				continue
			names[material.resource_name] = true
			pbr_ok = pbr_ok and material.normal_enabled
			for slot in ["albedo_texture", "normal_texture", "roughness_texture", "metallic_texture"]:
				var texture = material.get(slot)
				if not texture is Texture2D:
					pbr_ok = false
					continue
				var texture_path := str(texture.resource_path)
				if textures.has(texture_path): continue
				var imported_image: Image = texture.get_image()
				var mipmaps := imported_image != null and not imported_image.is_empty() and imported_image.has_mipmaps()
				var texture_ok := texture is CompressedTexture2D and texture_path.begins_with(MODEL.get_base_dir() + "/") and FileAccess.file_exists(texture_path + ".import")
				texture_ok = texture_ok and Vector2i(texture.get_width(), texture.get_height()) == Vector2i(1024, 1024) and mipmaps
				pbr_ok = pbr_ok and texture_ok
				textures[texture_path] = {"class":texture.get_class(), "size":[texture.get_width(),texture.get_height()], "has_mipmaps":mipmaps,
					"mipmap_count":imported_image.get_mipmap_count() if imported_image != null else -1, "normal_import":texture_ok}
	var original = session.world.objects[THERMAL]
	var collision_records: Array = []
	for child in original.get_children():
		if child is CollisionShape3D:
			collision_records.append({"disabled":child.disabled, "class":child.shape.get_class() if child.shape != null else "null",
				"size":_vec(child.shape.size) if child.shape is BoxShape3D else [], "transform":_transform(child.transform)})
	var retained_box := collision_records.size() == 1
	if retained_box:
		var collision: Dictionary = collision_records[0]
		retained_box = not collision.disabled and collision["class"] == "BoxShape3D" and collision["size"] == [3.0,2.0,2.0]
		retained_box = retained_box and collision.transform == _transform(Transform3D.IDENTITY) and original.collision_layer == 8
	_check(meshes.size() == 6 and surfaces == 10 and triangles == 11868 and names.size() == 6,
		"real imported draw geometry:6 meshes/10 surfaces/11868 triangles/6 materials")
	_check(pbr_ok and textures.size() == 18, "all18 actual PBR textures are normally imported1024px CompressedTexture2D with mipmaps")
	var nodes_ok := true
	for node_record in nodes.values(): nodes_ok = nodes_ok and node_record.has("path")
	_check(nodes_ok and art._fan.position.distance_to(Vector3(-0.7, 1, 0.68)) < 0.005
		and art._fan_rest.basis.is_equal_approx(Basis.IDENTITY) and art._fan_axis.distance_to(Vector3(0, 0, 1)) < 0.0001,
		"actual key nodes, identity rest pivot and authored fan local+Z axle")
	_check(retained_box and not original.get_node("Shape").visible
		and art.find_children("*", "CollisionObject3D", true, false).is_empty(), "old3x2x2 collision retained, original box mesh hidden, art adds no collision")
	return {"model":MODEL, "sha256":FileAccess.get_sha256(MODEL), "bytes":FileAccess.get_file_as_bytes(MODEL).size(),
		"mesh_count":meshes.size(), "draw_surfaces":surfaces, "triangles":triangles, "materials":names.keys(),
		"textures":textures, "nodes":nodes, "retained_collision":collision_records,
		"draw_note":"Authored mesh/surface submissions, not measured GPU draw calls or a performance result."}

func _asset_checks_passed() -> bool:
	for check in checks:
		if not check.passed: return false
	return true

func _state() -> Dictionary:
	return {"thermal":_safe(session.entities[THERMAL]), "energy":session.entities["player:1"].energy,
		"cooldown":session.cooldowns.get(1, 0), "health":body.health, "body_position":_vec(body.global_position),
		"clock":session.world.clock_seconds, "gate_fraction":session.world.gate_fraction, "gate_open":session.world.gate_open,
		"alternate_sources_off":_other_sources_off(), "fan_phase":art._fan_phase, "fan_speed":art._fan_speed,
		"fan_transform":_transform(art._fan.transform), "visual_temperature":art._temperature, "visual_powered":art._powered,
		"pipe_emission":_group_glow("HeatPipes"), "lens_emission":_group_glow("StatusLens"),
		"lens_emission_color":_color(_group_material("StatusLens").emission), "active_materials":_materials()}

func _temperature_is(value: float, powered: bool) -> bool:
	return is_equal_approx(float(session.entities[THERMAL].temperature), value) and bool(session.entities[THERMAL].powered) == powered

func _other_sources_off() -> bool:
	var relay: Dictionary = session.entities.get("I1:relay", {})
	var beacon: Dictionary = session.entities.get("I1:beacon", {})
	return not session.world.restored_gate and not bool(relay.get("powered", false)) and float(relay.get("charge", 0)) == 0.0 and not bool(beacon.get("powered", false)) and not bool(beacon.get("controlled", false))

func _meshes(node: Node) -> Array[MeshInstance3D]:
	var result: Array[MeshInstance3D] = []
	if node is MeshInstance3D and node.mesh != null: result.append(node)
	for child in node.get_children(): result.append_array(_meshes(child))
	return result

func _bounds(owner: Node3D) -> AABB:
	var bound := AABB()
	var first := true
	for mesh in _meshes(owner):
		var relative: Transform3D = owner.global_transform.affine_inverse() * mesh.global_transform
		for vertex in mesh.mesh.get_faces():
			var point: Vector3 = relative * vertex
			if first:
				bound = AABB(point, Vector3.ZERO)
				first = false
			else: bound = bound.expand(point)
	return bound

func _materials(static_only: bool = false, source: bool = false) -> Dictionary:
	var result: Dictionary = {}
	var excluded: Array = []
	if static_only:
		for key in ["HeatPipes", "StatusLens"]: excluded.append_array(_meshes(art.visual.find_child(key, true, false)))
	for mesh in _meshes(art.visual):
		if mesh in excluded: continue
		for surface in range(mesh.mesh.get_surface_count()):
			var material = (mesh.mesh.surface_get_material(surface) if source else mesh.get_active_material(surface)) as BaseMaterial3D
			if material == null: continue
			result[str(art.visual.get_path_to(mesh)) + ":" + str(surface)] = {"instance":material.get_instance_id(), "name":material.resource_name,
				"albedo":_color(material.albedo_color), "emission_color":_color(material.emission), "emission_enabled":material.emission_enabled,
				"emission_energy":material.emission_energy_multiplier, "roughness":material.roughness, "metallic":material.metallic,
				"normal_enabled":material.normal_enabled, "normal_scale":material.normal_scale}
	return result

func _group_material(key: String) -> BaseMaterial3D:
	return _meshes(art.visual.find_child(key, true, false))[0].get_active_material(0) as BaseMaterial3D

func _group_glow(key: String) -> float:
	var material := _group_material(key)
	return material.emission_energy_multiplier if material.emission_enabled else 0.0

func _vec(value: Vector3) -> Array:
	return [value.x, value.y, value.z]

func _color(value: Color) -> Array:
	return [value.r, value.g, value.b, value.a]

func _transform(value: Transform3D) -> Dictionary:
	return {"origin":_vec(value.origin), "x":_vec(value.basis.x), "y":_vec(value.basis.y), "z":_vec(value.basis.z)}

func _safe(value: Variant) -> Variant:
	if value is Vector3: return _vec(value)
	if value is Color: return _color(value)
	if value is Dictionary:
		var result: Dictionary = {}
		for key in value: result[str(key)] = _safe(value[key])
		return result
	if value is Array:
		var result: Array = []
		for item in value: result.append(_safe(item))
		return result
	return value

func _add_import_hashes() -> void:
	for path in input_paths.duplicate():
		var descriptor := str(path) + ".import"
		if not FileAccess.file_exists(descriptor): continue
		if descriptor not in input_paths: input_paths.append(descriptor)
		var config := ConfigFile.new()
		if config.load(descriptor) != OK or not config.has_section("remap"): continue
		for key in config.get_section_keys("remap"):
			if key == "path" or key.begins_with("path."):
				var cache := str(config.get_value("remap", key, ""))
				if not cache.is_empty() and cache not in input_paths: input_paths.append(cache)

func _input_hashes() -> Dictionary:
	var result: Dictionary = {}
	for path in input_paths: result[path] = FileAccess.get_sha256(path) if FileAccess.file_exists(path) else "MISSING"
	return result

func _check(ok: bool, label: String) -> bool:
	checks.append({"name":label, "passed":ok})
	return ok

func _timeout() -> void:
	if finishing:
		quit(3)
		return
	_check(false, "120 second watchdog expired before six captures completed")
	_finish.call_deferred()

func _finish() -> void:
	if finishing: return
	finishing = true
	var stats: Dictionary = session.stats.duplicate(true) if is_instance_valid(session) else {}
	if is_instance_valid(session):
		if is_instance_valid(session.network): session.network.close()
		session.queue_free()
	await process_frame
	await process_frame
	var hashes_after := _input_hashes()
	var identical := not hashes_before.is_empty() and hashes_before == hashes_after
	for shot in shots: identical = identical and shot.input_sha256 == hashes_before and str(shot.png_sha256).length() == 64
	_check(identical, "source,GLB,PNG,import descriptors and remap cache unchanged through every capture")
	_check(shots.size() == 6, "six requested real viewport PNGs completed")
	var logged: Dictionary = capture_logger.snapshot()
	_check(int(logged.error_count) == 0, "no engine/script/shader ERROR, including cleanup")
	var passed := _asset_checks_passed()
	var report := {"purpose":"Production I1 thermal bypass, real F/F/X state changes and six rendered camera comparisons.",
		"status":"captured_for_review_not_aesthetic_acceptance", "passed":passed, "profile":profile, "output":output,
		"checks":checks, "shots":shots, "actions":actions, "live_physics_windows":live_windows, "effects_pause_probe":pause_probe,
		"asset":asset_record, "session_stats":stats, "input_sha256_before":hashes_before, "input_sha256_after":hashes_after,
		"engine_log":logged, "engine_version":Engine.get_version_info(), "gpu":RenderingServer.get_video_adapter_name(),
		"renderer":RenderingServer.get_current_rendering_method(), "display":DisplayServer.get_name(), "viewport":[root.size.x,root.size.y],
		"limitations":["Real viewport PNGs; no graphics acceptance, performance measurement or human-play claim.",
			"Body is teleported once and frozen at thermal+(0,3,4); camera snaps to thermal centre. AGL stays cached and may be stale. No clearance/flight test.",
			"Natural production Session ticks consume cooldown/regenerate energy/move gate. The body uses existing neutral QA input and is not integrated.",
			"Effects-pause probe uses production world.set_effects_paused during actual process frames, not multiplayer consensus or a fabricated network action.",
			"70 degrees is powered by real rules. This sequence does not manufacture an unpowered70 state; cold20 and cooled45 prove unpowered stop, hot pause proves retained heat colour.",
			"Logger starts before scene loading; external runner must still reject parse/startup failure or missing report."]}
	var path := output.path_join("capture.json")
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE) if not FileAccess.file_exists(path) else null
	var write_ok := file != null
	if file != null:
		file.store_string(JSON.stringify(report, "\t", true, true))
		file.flush()
		write_ok = file.get_error() == OK
		file.close()
	if not write_ok: push_error("THERMAL_CAPTURE report write failed")
	var final_log: Dictionary = capture_logger.snapshot()
	var success: bool = passed and write_ok and int(final_log.error_count) == 0
	print("THERMAL_BYPASS_CAPTURE ", JSON.stringify({"passed":success, "checks":checks.size(), "shots":shots.size(), "errors":final_log.error_count, "output":output}))
	OS.remove_logger(capture_logger)
	quit(0 if success else 1)
