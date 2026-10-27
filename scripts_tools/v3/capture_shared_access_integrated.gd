extends "res://scripts_tools/v3/capture_clinic_integrated.gd"
## Source-only production MAIN diagnostic. No second bridge, fabricated axis,
## reward, choice, material or camera is installed. Historical27 and pilot starting
## poses are declared QA fixtures; abilities use actual number/Tab/F dispatch.
## --qa-profile=qa_visual_clinic_shared_access_<unique>
## --capture-output=res://artifacts/v3/art/shared-access-integrated-<unique>
const SharedAccess = preload("res://scripts/v3/gameplay/twin_shared_access_session.gd")
const Bridge = SharedAccess.Bridge
const CAPTURE_PATH := "res://scripts_tools/v3/capture_shared_access_integrated.gd"
const WALL_LIMIT := 200.0
var bridge
var bridge_layout: Dictionary = {}
var baseline_story: Dictionary = {}
var baseline_personal: Dictionary = {}
var endpoint_records: Array = []
var readbacks: Array = []
var raw_inputs: Dictionary = {}
var raw_shots: Array = []

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
		else: return false
	var regex := RegEx.new()
	if regex.compile("^qa_visual_clinic_shared_access_[A-Za-z0-9_-]+$") != OK: return false
	if profile_count != 1 or output_count != 1 or regex.search(profile) == null: return false
	output = ProjectSettings.globalize_path(output).replace("\\", "/").simplify_path()
	var allowed := ProjectSettings.globalize_path("res://artifacts/v3/art").replace("\\", "/").simplify_path()
	if not output.is_absolute_path() or output.get_base_dir().to_lower() != allowed.to_lower(): return false
	if not output.get_file().begins_with("shared-access-integrated-") or output.get_file() == "shared-access-integrated-": return false
	if DirAccess.dir_exists_absolute(output) or FileAccess.file_exists(output): return false
	if DirAccess.dir_exists_absolute("user://profiles_v3/" + profile) or FileAccess.file_exists("user://profiles_v3/" + profile): return false
	return OS.is_debug_build() and DisplayServer.get_name() != "headless" and RenderingServer.get_current_rendering_method() == "gl_compatibility" and RenderingServer.is_render_loop_enabled() and Engine.physics_ticks_per_second == 60

func _run() -> void:
	started_usec = Time.get_ticks_usec()
	if not _arguments_valid():
		push_error("SHARED_ACCESS_CAPTURE requires fresh isolated paths and source debug Compatibility renderer")
		OS.remove_logger(capture_logger)
		quit(2)
		return
	if DirAccess.make_dir_recursive_absolute(output) != OK:
		push_error("SHARED_ACCESS_CAPTURE cannot create fresh output")
		OS.remove_logger(capture_logger)
		quit(2)
		return
	create_timer(WALL_LIMIT, true, false, true).timeout.connect(_timeout)
	root.size = SIZE
	_add_dependency_tree(CAPTURE_PATH)
	_add_dependency_tree("res://project.godot")
	_add_import_hashes()
	hashes_before = _input_hashes()
	if not _check(_hashes_complete() and _archive_text_inputs(), "capture and production text inputs preserved before MAIN construction"):
		await _finish()
		return
	session = MAIN.instantiate()
	if not _check(session.has_method("start_flight") and session.has_method("_facilities_ready"), "MAIN has its actual Session script"):
		await _finish()
		return
	root.add_child(session)
	if not _check(session.profile_ready and session.store.root_path == "user://profiles_v3/" + profile and session.start_flight("solo"), "fresh isolated production MAIN starts I1"):
		await _finish()
		return
	_hold()
	if not _seed_history():
		await _finish()
		return
	_hold()
	inventories.I1 = _scene_inventory(session.world)
	_extend_scene_inputs(inventories.I1)
	session._ui_action("travel_to", {"region_id":"I2"})
	_hold()
	await physics_frame
	await physics_frame
	if not _check(session.region_id == "I2" and session._facilities_ready() and session.world.build_errors.is_empty()
		and session.world.shared_access == session.shared_access.module, "production I2 adopts one world-owned bridge with all four facilities ready"):
		await _finish()
		return
	body = session.players[1]
	bridge = session.shared_access.module
	bridge_layout = bridge.layout()
	baseline_story = session.story.state.duplicate(true)
	baseline_personal = session.store.snapshot().personal.duplicate(true)
	inventories.I2 = _scene_inventory(session.world)
	_extend_scene_inputs(inventories.I2)
	var count := 0
	for node in session.world.find_children("*", "Node3D", true, false):
		if node is Bridge: count += 1
	if not _check(count == 1 and bridge.global_transform.is_equal_approx(Transform3D.IDENTITY)
		and session.store.snapshot().world.environment.has("I2_shared_access") and _hashes_complete() and _archive_text_inputs(), "one actual bridge, saved envelope and immutable discovered resource inputs"):
		await _finish()
		return
	if not _check(bridge.status().mode == "public_span" and bridge.status().locked, "fresh bridge really starts locked at public endpoint"):
		await _finish()
		return
	if not await _record_endpoint("public_span", "initial public"):
		await _finish()
		return
	await _capture("01-I2-shared-public-default-26m", "Production I2 public bridge at its real locked endpoint. Default 26m fixed camera; imported moving deck with surrounding graybox, not whole-region art acceptance.")
	if finishing: return
	await _capture("02-I2-shared-public-zoom3", "Same production pose with three ordinary zoom steps. No model, target or collision scaling.", 3)
	if finishing: return
	if not await _drive_to("service_span") or not await _record_endpoint("service_span", "powered service endpoint"):
		await _finish()
		return
	await _capture("03-I2-shared-service-zoom3", "Real relay charge and service-controller takeover moved and reinserted the pin. Both public and inspection corridors checked; no choice committed.", 3)
	if finishing: return
	if not await _place_checked(_approach(Bridge.PUBLIC_CONTROL, true), "same observer pose as initial public default shot"):
		await _finish()
		return
	await _capture("03b-I2-shared-service-default-26m", "Same observer position and default 26m camera as shot01; actual service endpoint, not a different framing or fabricated bridge pose.")
	if finishing: return
	if not await _underpass():
		await _finish()
		return
	await _capture("04-I2-shared-underpass-zoom3", "Actual full FlightBody move_and_collide crossed beneath the locked service deck from a declared starting pose. Fixed oblique camera, normal zoom3; not human flight evidence.", 3)
	if finishing: return
	if not _check_bridge_cutaway():
		await _finish()
		return
	if not await _drive_to("public_span") or not await _record_endpoint("public_span", "returned public endpoint"):
		await _finish()
		return
	await _capture("05-I2-shared-returned-public-zoom3", "After prior takeover naturally expired, real charge and public-controller takeover returned the same bridge. Independent Store reread matches the current mechanism.", 3)
	if finishing: return
	await _capture("06-I2-shared-returned-default-26m", "Final public endpoint in the normal 26m product camera. Historical27 is unchanged; no clinic, audit or bridge-choice completion was fabricated.")
	if finishing: return
	var restored := true
	for entry in session.terrain_visibility._entries.values():
		if entry.root in bridge.fixed_bodies.values() + bridge.moving_bodies.values(): restored = restored and not entry.installed and is_equal_approx(float(entry.alpha), 1.0)
	_check(restored, "leaving the underpass restores every local bridge panel material")
	_check(session.story.state == baseline_story and session.store.snapshot().personal == baseline_personal and session.story.state.completed.size() == 27, "physical switching and environment saves award no unearned objective, discovery or personal reward")
	_check(session.network.mode == "solo" and session.qa_mode.is_empty() and not session.boss_active and int(session.stats.abilities) == 4, "exactly four real accepted charge/takeover inputs drive this solo diagnostic")
	await _finish()

func _approach(target: String, confirmation: bool) -> Vector3:
	# One derivation point follows the authored controller and deck dimensions.
	# Above-route confirmation avoids the pilot itself blocking the 2.8m corridor.
	var at: Vector3 = bridge.entity_position(target)
	var envelope := body.get_node("Envelope") as CollisionShape3D
	var half_y: float = (envelope.shape as BoxShape3D).size.y * 0.5
	var top: float = bridge.global_position.y + float(bridge_layout.deck_top_y)
	var y: float = top + 2.1
	if confirmation: y = top + float(bridge_layout.route_height_m) + maxf(0.8, half_y + 0.1)
	return Vector3(at.x - 1.6, y, at.z)

func _place_checked(at: Vector3, reason: String) -> bool:
	await _place(at, reason)
	if finishing: return false
	return _check(_envelope_clear(), "full hull with every collision layer is clear: " + reason)

func _envelope_clear() -> bool:
	var envelope := body.get_node("Envelope") as CollisionShape3D
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = envelope.shape
	query.transform = envelope.global_transform
	query.collision_mask = 0xFFFFFFFF
	query.margin = 0.001
	query.exclude = [body.get_rid()]
	return session.get_world_3d().direct_space_state.intersect_shape(query, 1).is_empty()

func _drive_to(mode: String) -> bool:
	var target: String = Bridge.PUBLIC_CONTROL if mode == "public_span" else Bridge.SERVICE_CONTROL
	if not await _place_checked(_approach(target, false), "layout-derived live controls approach for " + mode): return false
	# Never force controlled=false or energy/cooldown. Two simultaneous controllers
	# are a genuine mutual exclusion, so observe their natural release first.
	if not _controls_released() and not await _advance_bridge("prior takeover natural release", 9.0, "released"): return false
	if not await _ability_key(KEY_6, Bridge.RELAY, "charge the actual bridge relay"): return false
	if not await _ability_key(KEY_0, target, "take over " + mode + " controller"): return false
	return await _advance_bridge("locked " + mode, 9.0, mode)

func _controls_released() -> bool:
	for id in [Bridge.PUBLIC_CONTROL, Bridge.SERVICE_CONTROL]:
		var entity: Dictionary = session.entities.get(id, {})
		if bool(entity.get("controlled", false)) and float(entity.get("takeover_remaining", 0.0)) > 0.0: return false
	return true

func _ability_key(number: Key, target: String, purpose: String) -> bool:
	if float(session.cooldowns.get(1, 0.0)) > 0.0 and not await _advance_bridge("production ability cooldown", 2.0, "cooldown"): return false
	if not _select(number, target): return false
	var before: Dictionary = _state()
	var accepted: int = int(session.stats.abilities)
	var rejected: int = int(session.stats.rejected_abilities)
	_key(KEY_F)
	actions.append({"input":"number/Tab/F", "number_key":int(number), "target":target, "purpose":purpose, "before":before, "after":_state()})
	return _check(int(session.stats.abilities) == accepted + 1 and int(session.stats.rejected_abilities) == rejected, "real selected F accepted: " + purpose)

func _advance_bridge(label: String, seconds: float, condition: String) -> bool:
	var begin := Time.get_ticks_usec()
	var first_tick := simulated_ticks
	var before: Dictionary = _state()
	var reached := false
	paused = false
	session.world.set_effects_paused(false)
	for unused in range(int(ceil(seconds / DT))):
		await physics_frame
		if finishing: return false
		session._physics_process(DT)
		simulated_ticks += 1
		var healthy := true
		for name in ["clinic", "distribution", "trial", "shared_access"]:
			var adapter = session.get(name)
			if not str(adapter.error).is_empty():
				_check(false, "production " + name + " update rejected: " + str(adapter.error))
				healthy = false
		if not healthy or session.simulation_paused: break
		if condition == "released": reached = _controls_released()
		elif condition == "cooldown": reached = float(session.cooldowns.get(1, 0.0)) <= 0.0
		elif condition in Bridge.MODES: reached = bridge.status().mode == condition and bridge.status().locked
		else:
			_check(false, "unknown bridge wait condition: " + condition)
			break
		if reached: break
	_hold()
	live_windows.append({"name":label, "wall_seconds":float(Time.get_ticks_usec() - begin) / 1000000.0, "fixed_steps":simulated_ticks - first_tick,
		"simulated_seconds":float(simulated_ticks - first_tick) * DT, "before":before, "after":_state(), "reached":reached})
	return _check(reached, "bounded real Session physics reaches " + label)

func _record_endpoint(mode: String, label: String) -> bool:
	var target: String = Bridge.PUBLIC_CONTROL if mode == "public_span" else Bridge.SERVICE_CONTROL
	if not await _place_checked(_approach(target, true), "above the full corridor ceiling for " + label): return false
	var confirmation: Dictionary = session.shared_access.choice_confirmation(1, mode)
	var actual: Dictionary = _physics_record()
	endpoint_records.append({"name":label, "body_position":_vec(body.global_position), "status":bridge.status(), "access":bridge.access_report(), "confirmation":confirmation, "physics":actual})
	if not _check(confirmation.get("ok", false) and actual.all_physics_poses_match, "read-only first-hit confirmation and both real route envelopes accept " + label): return false
	for id in [Bridge.HANDLE, Bridge.PIN, Bridge.RELAY, Bridge.PUBLIC_CONTROL, Bridge.SERVICE_CONTROL]:
		var authored: Vector3 = bridge.entity_position(id)
		var matches: bool = session.entities.has(id) and session.entities[id].position is Vector3 and session.entities[id].position.is_equal_approx(authored)
		if not _check(matches, "production capability target follows actual collider: " + id): return false
	if not _check(session._save_environment(), "production environment save succeeds: " + label): return false
	var disk = Store.new(session.store.root_path)
	var loaded: Dictionary = disk.load_profile()
	var saved: Dictionary = disk.snapshot().get("world", {}).get("environment", {}).get("I2_shared_access", {}) if loaded.ok else {}
	var same: bool = loaded.ok and session.store.matches_persisted_value(session.shared_access.persistent_state(), saved)
	readbacks.append({"name":label, "load":loaded, "matches":same, "saved_bridge":saved, "profile_generation":disk.snapshot().get("generation", -1)})
	return _check(same, "independent Store reread preserves current bridge and pin: " + label)

func _underpass() -> bool:
	var deck: StaticBody3D = bridge.moving_bodies.get("BridgeDeck")
	var spec: Dictionary = {}
	for row in bridge_layout.moving:
		if row.id == "BridgeDeck": spec = row
	if not _check(is_instance_valid(deck) and not spec.is_empty(), "actual authored deck available for derived underpass"): return false
	var bottom: float = deck.global_position.y - float(spec.size[1]) * 0.5
	var y: float = bridge.global_position.y + (bottom - bridge.global_position.y) * 0.45
	var half_z: float = float(spec.size[2]) * 0.5
	var start := Vector3(deck.global_position.x, y, deck.global_position.z - half_z - 1.3)
	var finish := Vector3(deck.global_position.x, y, deck.global_position.z + half_z + 1.3)
	if not await _place_checked(start, "derived bridge-underpass start, not teleported through geometry"): return false
	var before: Dictionary = session.shared_access.persistent_state()
	var moves: Array = []
	var steps := int(ceil(start.distance_to(finish) / 0.15))
	for index in range(steps):
		var destination: Vector3 = start.lerp(finish, float(index + 1) / float(steps))
		var collision: KinematicCollision3D = body.move_and_collide(destination - body.global_position)
		session.entities["player:1"].position = body.global_position
		await physics_frame
		if finishing: return false
		var clear: bool = _envelope_clear()
		moves.append({"position":_vec(body.global_position), "clear":clear, "collider":"" if collision == null else str(collision.get_collider().get_path())})
		if collision != null or not clear:
			physical_probes.underpass = {"start":_vec(start), "finish":_vec(finish), "moves":moves, "passed":false}
			return _check(false, "full-hull underpass blocked by actual collision; retain failure")
	var passed: bool = body.global_position.distance_to(finish) < 0.0001 and _same(before, session.shared_access.persistent_state())
	physical_probes.underpass = {"start":_vec(start), "finish":_vec(finish), "moves":moves, "step_limit_m":0.15, "passed":passed,
		"limit":"Frozen QA starting placement followed by actual move_and_collide, not player flight control or a human comfort test."}
	return _check(passed, "real full hull reaches underpass endpoint without changing bridge state")

func _check_bridge_cutaway() -> bool:
	var structures: Array = bridge.fixed_bodies.values() + bridge.moving_bodies.values()
	var controls: Array = bridge.target_bodies.values() + bridge.pin_bodies.values()
	var faded: Array = []
	var protected := true
	var edges: Array = bridge.find_children("CutawayEdge*", "MeshInstance3D", true, false)
	var edges_intact: bool = edges.size() == 7
	for entry in session.terrain_visibility._entries.values():
		if entry.root in controls: protected = false
		for edge in edges:
			if edge in entry.meshes: edges_intact = false
		if entry.root in structures and entry.installed and float(entry.alpha) <= .21: faded.append(str(entry.root.name))
	for edge in edges:
		edges_intact = edges_intact and edge.is_visible_in_tree() and edge.material_override is StandardMaterial3D and edge.material_override.transparency == BaseMaterial3D.TRANSPARENCY_DISABLED and is_equal_approx(edge.material_override.albedo_color.a, 1.0)
	physical_probes.bridge_cutaway = {"faded_structures":faded,"controls_and_pin_protected":protected,"opaque_edge_cues":edges.size(),"edges_intact":edges_intact,"poses":_physics_record()}
	return _check(not faded.is_empty() and protected and edges_intact and _physics_record().all_physics_poses_match,"underpass panels fade but controls, pin and seven opaque physical-edge cues remain intact without changing collision")

func _physics_record() -> Dictionary:
	var aligned := true
	var poses: Array = []
	for moving in bridge.fixed_bodies.values() + bridge.moving_bodies.values() + bridge.pin_bodies.values():
		var actual: Transform3D = PhysicsServer3D.body_get_state(moving.get_rid(), PhysicsServer3D.BODY_STATE_TRANSFORM)
		var matches: bool = actual.is_equal_approx(moving.global_transform)
		aligned = aligned and matches
		poses.append({"node":str(moving.name), "scene_position":_vec(moving.global_position), "physics_position":_vec(actual.origin), "matches":matches, "layer":moving.collision_layer})
	return {"all_physics_poses_match":aligned and bridge.status().pose_valid, "bodies":poses}

func _art_record() -> Dictionary:
	var imported: Dictionary = bridge.deck_art
	var records: Array = []
	var matched: bool = imported.get("ok",false) and int(imported.get("mesh_count",0)) == 12 and int(imported.get("triangles",0)) == 10912
	var pose: Dictionary = bridge.status()
	for row: Dictionary in imported.get("parts",[]):
		var mesh: MeshInstance3D = row.mesh
		var part_body: StaticBody3D = row.body
		var id := str(row.id)
		var offset := Vector3(0,-float(pose.pin_extension_m) if id in ["LockRod","LockGrip"] else 0.0,float(pose.position_m))
		var expected: Transform3D = bridge.global_transform * Transform3D(Basis.IDENTITY,Vector3(15,5,0)+offset) * row.authored
		var good: bool = mesh.get_parent() == part_body and mesh.global_transform.is_equal_approx(expected) and mesh.transform.is_equal_approx(row.local) and mesh.is_visible_in_tree() and not part_body.get_node("Visual").visible
		matched = matched and good
		records.append({"id":id,"matches":good,"world_position":_vec(mesh.global_position),"expected_position":_vec(expected.origin)})
	var landings: Dictionary = bridge.landing_art
	matched = matched and landings.get("ok",false) and int(landings.get("mesh_count",0)) == 6 and int(landings.get("triangles",0)) == 13908 and int(landings.get("material_count",0)) == 2
	for row: Dictionary in landings.get("parts",[]):
		var mesh: MeshInstance3D = row.mesh
		var part_body: StaticBody3D = row.body
		var expected: Transform3D = bridge.global_transform * Transform3D(Basis.IDENTITY,Vector3(15,5,0)) * row.authored
		var good: bool = mesh.get_parent() == part_body and mesh.global_transform.is_equal_approx(expected) and mesh.transform.is_equal_approx(row.local) and mesh.is_visible_in_tree() and not part_body.get_node("Visual").visible
		matched = matched and good
		records.append({"id":str(row.id),"fixed_landing":true,"matches":good,"world_position":_vec(mesh.global_position),"expected_position":_vec(expected.origin)})
	return {"all_imported_poses_match":matched,"parts":records,"path":imported.get("path",""),"landing_path":landings.get("path","")}

func _state() -> Dictionary:
	var result: Dictionary = super._state()
	for name in ["distribution", "trial", "shared_access"]:
		var adapter = session.get(name)
		if adapter.ready: result[name] = adapter.persistent_state()
	if is_instance_valid(bridge):
		result.bridge_status = bridge.status()
		result.bridge_physics = _physics_record()
	return result

func _ui_record() -> Dictionary:
	var result: Dictionary = super._ui_record()
	result.bridge_status = bridge.status()
	result.bridge_access = bridge.access_report()
	_check(bool(_physics_record().all_physics_poses_match), "fixed, moving and pin PhysicsServer poses match each captured frame")
	result.bridge_art = _art_record()
	_check(bool(result.bridge_art.all_imported_poses_match), "12 moving and six fixed imported mesh transforms match original authority bodies and hidden graybox visuals")
	return result

func _capture(id: String, note: String, zoom_steps: int = 0) -> void:
	var before_count := shots.size()
	await super._capture(id, note, zoom_steps)
	if finishing or shots.size() != before_count + 1: return
	# Preserve each unedited viewport PNG and its complete frame evidence immediately,
	# so a later failure cannot erase previously rendered diagnostic states.
	var path := output.path_join(id + "-capturedraw.json")
	var record: Dictionary = shots.back().duplicate(true)
	var written: bool = _write_fresh_json(path, record)
	_check(written, "raw captured frame record saved: " + id)
	if written: raw_shots.append({"path":path, "sha256":FileAccess.get_sha256(path)})

func _add_dependency_tree(path: String) -> void:
	if path in input_paths: return
	input_paths.append(path)
	if not FileAccess.file_exists(path) or path.get_extension() not in ["gd", "json", "tscn", "tres", "gdshader", "gdshaderinc", "godot"]: return
	var regex := RegEx.new()
	regex.compile("res://[^\\\"'\\s]+")
	for matched in regex.search_all(FileAccess.get_file_as_string(path)):
		var dependency: String = matched.get_string().get_slice("::", 0)
		if FileAccess.file_exists(dependency): _add_dependency_tree(dependency)

func _extend_scene_inputs(inventory: Dictionary) -> void:
	for path in inventory.imported_sources + inventory.material_sources: _add_dependency_tree(path)
	_add_import_hashes()
	for path in input_paths:
		if not hashes_before.has(path): hashes_before[path] = FileAccess.get_sha256(path) if FileAccess.file_exists(path) else "MISSING"

func _hashes_complete() -> bool:
	if hashes_before.is_empty(): return false
	for digest in hashes_before.values():
		if str(digest).length() != 64: return false
	return true

func _archive_text_inputs() -> bool:
	for path: String in input_paths:
		if raw_inputs.has(path) or path.get_extension() not in ["gd", "json", "tscn", "tres", "gdshader", "gdshaderinc", "godot", "import"]: continue
		var destination := output.path_join("captured-source").path_join(path.trim_prefix("res://"))
		if DirAccess.make_dir_recursive_absolute(destination.get_base_dir()) != OK or FileAccess.file_exists(destination): return false
		var data := FileAccess.get_file_as_bytes(path)
		var file := FileAccess.open(destination, FileAccess.WRITE)
		if file == null: return false
		file.store_buffer(data)
		file.flush()
		var okay: bool = file.get_error() == OK
		file.close()
		if not okay or FileAccess.get_sha256(destination) != hashes_before.get(path, ""): return false
		raw_inputs[path] = {"path":destination, "bytes":data.size(), "sha256":FileAccess.get_sha256(destination)}
	return true

func _write_fresh_json(path: String, value: Dictionary) -> bool:
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE) if not FileAccess.file_exists(path) else null
	if file == null: return false
	file.store_string(JSON.stringify(value, "\t", true, true))
	file.flush()
	var okay: bool = file.get_error() == OK
	file.close()
	return okay

func _timeout() -> void:
	if finishing:
		quit(3)
		return
	_check(false, str(WALL_LIMIT) + " second wall-clock watchdog expired")
	_finish.call_deferred()

func _finish() -> void:
	if finishing: return
	finishing = true
	var usable: bool = is_instance_valid(session) and session.has_method("start_flight")
	var final_state: Dictionary = _state() if usable and session.players.has(1) else {}
	if is_instance_valid(session):
		if usable:
			session.active = false
			if is_instance_valid(session.network): session.network.close()
		session.free()
	await process_frame
	await process_frame
	var after := _input_hashes()
	_check(_hashes_complete() and hashes_before == after, "all fixed production/capture/import inputs stayed unchanged")
	_check(shots.size() == 7 and raw_shots.size() == 7, "all seven actual PNGs and complete capturedraw records saved")
	var logged: Dictionary = capture_logger.snapshot()
	_check(int(logged.error_count) == 0, "zero engine/script/shader errors including cleanup")
	var passed := true
	for item in checks: passed = passed and bool(item.passed)
	var report: Dictionary = {"passed":passed, "status":"production_shared_access_scripted_diagnostic_not_art_acceptance", "profile":profile, "output":output,
		"checks":checks, "shots":shots, "actions":actions, "fixture":fixture, "QA_placements":placements, "live_windows":live_windows,
		"endpoint_records":endpoint_records, "readbacks":readbacks, "physical_probes":physical_probes, "layout":bridge_layout,
		"nominal_fixed_step_seconds":DT, "simulated_ticks":simulated_ticks, "final_state":final_state, "production_scene_inventory":inventories,
		"input_sha256_before":hashes_before, "input_sha256_after":after, "captured_source":raw_inputs, "capturedraw":raw_shots,
		"engine_log":logged, "engine":Engine.get_version_info(), "renderer":RenderingServer.get_current_rendering_method(), "GPU":RenderingServer.get_video_adapter_name(),
		"viewport":[root.size.x, root.size.y], "wall_seconds":float(Time.get_ticks_usec() - started_usec) / 1000000.0,
		"limits":["Historical27 is a real Director/Store fixture, not a seven-action playthrough. Clinic/audit/choice completion is never injected; confirmation is a read-only proof, not G or consensus.",
			"Only the unique production world-owned bridge is used. Existing graybox, camera, material and collision sizes remain unchanged. PNGs are original viewport bytes, not concept art or final art acceptance.",
			"Real number/Tab/F charge and takeover drive public-to-service-to-public; prior control expires naturally. This solo source capture does not establish ENet, packaged behavior or two-PC reliability.",
			"Pilot starting poses are declared full-envelope-tested QA placements. The one short underpass uses actual move_and_collide; it is not a player-flown traversal or comfort measurement.",
			"Normal26m and three legal zoom steps use the same fixed orthographic camera. Frozen presentation settling and fixed callback stepping are not performance or duration evidence. Cached AGL is recorded, not corrected.",
			"Resource fingerprints cover literal dependency closure and actual scene/import resources. Text inputs are copied byte-for-byte; large binary assets are fingerprinted, not duplicated. No unrelated candidate module is installed.",
			"A parser failure before initialization needs an external process timeout and required-report check. The script itself has a bounded wall-clock watchdog and logs cleanup errors."]}
	var wrote: bool = _write_fresh_json(output.path_join("state_checks.json"), report)
	if not wrote: push_error("SHARED_ACCESS_CAPTURE cannot write fresh state_checks.json")
	var final_log: Dictionary = capture_logger.snapshot()
	var success: bool = passed and wrote and int(final_log.error_count) == 0
	print("SHARED_ACCESS_INTEGRATED_CAPTURE ", JSON.stringify({"passed":success, "shots":shots.size(), "checks":checks.size(), "errors":final_log.error_count, "output":output}))
	OS.remove_logger(capture_logger)
	quit(0 if success else 1)
