extends SceneTree
## Rendered production HUD review; fixed QA poses, not flight/performance evidence.
## Run after import, with --rendering-method gl_compatibility --windowed
## --resolution 1280x720 --script res://scripts_tools/v3/capture_hud_visibility.gd
## -- --qa-profile=qa_visual_<unique>
## --capture-output=res://artifacts/v3/art/hud-visibility-<unique>
## Only the real nearby rescue brief is committed. F1 direct load and the closed
## development Crown encounter are explicit QA shortcuts, not campaign progress.
## The original 11 views are retained. A separately instantiated solo session then
## adds real F/F heat with natural cooldown, a restored UI-only 61-degree fixture,
## and one short real rigid-body integration / independently ray-checked AGL view.

const SIZE := Vector2i(1280, 720)
const SETTLE_FRAMES := 8
const INPUTS := [
	"res://scripts_tools/v3/capture_hud_visibility.gd", "res://project.godot",
	"res://scenes/v3/main.tscn", "res://scripts/v3/twin_interface.gd",
	"res://scripts/v3/twin_session.gd", "res://scripts/v3/twin_network.gd",
	"res://scripts/v2/flight_body.gd", "res://scripts/v2/pilot_input.gd",
	"res://scripts/v2/flight_camera.gd",
	"res://scripts/v3/ui/twin_opening_guidance.gd",
	"res://scripts/v3/gameplay/twin_opening_story.gd",
	"res://scripts/v3/gameplay/twin_ability_rules.gd",
	"res://scripts/v3/gameplay/twin_crown_session.gd",
	"res://scripts/v3/art/twin_objective_marker.gd",
	"res://scripts/v3/art/twin_target_marker.gd", "res://scripts/v3/twin_test_world.gd",
	"res://scripts/v3/art/twin_ground_surface.gd",
	"res://assets/v3/materials/twin_ground_study.gdshader",
	"res://assets/v3/materials/forest_floor_surface_v1.png",
	"res://assets/fonts/NotoSansSC-Medium.ttf",
	"res://assets/v3/crown/parasitic_crown.glb",
	"res://assets/v3/root_buttress/root_buttress_h10.glb",
	"res://assets/v3/fantasy_kit/rootstone_terrace.glb",
	"res://assets/v3/fantasy/temple_gate.glb",
	"res://data/v3/actions/opening_actions.json",
	"res://data/v3/actions/whale_action.json", "res://data/v3/actions/crown_action.json",
	"res://data/v3/terrain/f1_shore_layout.json",
	"res://data/v3/terrain/f1_growth_crossing.json"
]

# Logger callbacks can run on render threads; no scene access or printing here.
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
var selection_probes: Array = []
var ui_events: Array = []
var input_paths: Array = []
var hashes_before: Dictionary = {}
var capture_logger := CaptureLogger.new()
var finishing := false
var expected_camera_size := 26.0
var session_phases: Array = []
var live_windows: Array = []
var temperature_fixture: Dictionary = {}
var current_fixture: Dictionary = {}
var current_height_probe: Dictionary = {}
var phase := "original_eleven_views"

func _initialize() -> void:
	OS.add_logger(capture_logger)
	call_deferred("_run")

func _run() -> void:
	if not _arguments_valid():
		push_error("HUD capture requires Compatibility rendering, a fresh qa_visual_ profile and fresh hud-visibility- output directory.")
		OS.remove_logger(capture_logger)
		quit(2)
		return
	if DirAccess.make_dir_recursive_absolute(output) != OK:
		push_error("Cannot create HUD evidence directory")
		OS.remove_logger(capture_logger)
		quit(2)
		return
	create_timer(120.0, true, false, true).timeout.connect(_timeout)
	root.size = SIZE
	input_paths.assign(INPUTS)
	_add_import_hashes()
	hashes_before = _input_hashes()
	for path in hashes_before:
		if not _check(str(hashes_before[path]).length() == 64, "input bytes exist: " + str(path)):
			await _finish()
			return
	var packed = ResourceLoader.load("res://scenes/v3/main.tscn")
	if not _check(packed is PackedScene, "production scene loads"):
		await _finish()
		return
	session = packed.instantiate()
	root.add_child(session)
	if not _check(session.profile_ready and session.store.root_path == "user://profiles_v3/" + profile, "fresh isolated session store"):
		await _finish()
		return
	if not _check(session.start_flight("solo") and session.players.has(1), "real solo session, no UDP/host fixture"):
		await _finish()
		return
	_freeze_automatic_updates()
	session.interface.action_requested.connect(_record_ui_action)
	_check(session.story.state.get("completed", []).is_empty(), "fresh story has no completed objectives")
	_check(is_instance_valid(session.interface.top_panel) and is_instance_valid(session.interface.bottom_panel)
		and is_instance_valid(session.interface.movement_hint) and is_instance_valid(session.interface.flight_details)
		and is_instance_valid(session.interface.details_button), "production HUD exposes five capture interfaces")

	_pose(Vector3(-36, 5.2, 3), 26.0)
	_check(not session.interface.target_info.visible and not session.interface.details_open, "no-lock compact HUD hides redundant target tutorial")
	await _capture("01-I1-initial", "Same I1 pose/zoom as dev.11 packaged view; actual production vitals.")

	_pose(Vector3(-18, 2.5, 35), 26.0)
	_check(session.interface.explore_button.visible, "nearby G button is visible before real rescue briefing")
	_key(KEY_G)
	session._refresh_interface()
	_check(session.story.state.get("completed", []) == ["I1:rescue:brief"], "real G submits only rescue briefing, no fabricated completion")
	_check(session.interface.radio.visible and session.interface.explore_button.visible, "real dialogue and continue G remain visible")
	await _capture("02-nearby-G-dialogue", "Actual near-range G briefing; radio text comes from committed production story.")
	var dialogue_count := 0
	while session.interface.radio.visible and dialogue_count < 12:
		_key(KEY_G)
		dialogue_count += 1
	_check(not session.interface.radio.visible, "G dismisses real dialogue without submitting another objective")
	_pose(Vector3(15, 3, 39), 26.0)
	_check(session.story.display_anchor().get("anchor_id", "") == "I1:rescue_pocket" and session.interface.objective_marker.at_edge, "rescue destination remains visible as edge guidance")
	await _capture("03-rescue-direction", "Scripted far pose after real brief; rescue/channel/evacuation not completed.")

	_pose(Vector3(-14, 18, 38), 26.0)
	_lock("I1:relay")
	session.interface.select_ability(5)
	session._refresh_interface()
	_check(session.interface.ability_description.text.contains("还需靠近"), "charge displays actual 3D out-of-range distance")
	_check(session.interface.suggestion_buttons[0].visible and session.interface.suggestion_buttons[1].visible, "relay exposes two contextual selection buttons")
	_probe_suggestions()
	session.interface.select_ability(5)
	session._refresh_interface()
	await _capture("04-charge-distance-two-suggestions", "Both real suggestion buttons tested for selection-only behavior; no cast.")
	_key(KEY_B)
	_check(session.interface.wheel.visible and session.interface.ability_buttons.size() == 10, "B opens all ten tools through actual input handler")
	await _capture("05-B-all-abilities", "Expanded ability panel requested through B, not made visible directly.")
	_key(KEY_B)
	_check(not session.interface.wheel.visible and is_equal_approx(Engine.time_scale, 1.0), "B closes panel and restores solo time scale")

	var completed_before: Array = session.story.state.get("completed", []).duplicate()
	if not _check(session._load_region("F1") and session.region_id == "F1", "explicit QA shortcut loads real F1 without claiming travel unlock"):
		await _finish()
		return
	_freeze_automatic_updates()
	_check(session.story.state.get("completed", []) == completed_before, "QA F1 shortcut did not complete any story objective")
	session.interface.select_ability(6)
	_pose(Vector3(-21, 5.5, 27), 26.0)
	_check(not session.interface.ability_description.text.contains("X") and not session.interface.target_info.visible, "growth offers no invented reverse action and no-lock tutorial stays hidden")
	await _capture("06-F1-default-growth-no-X", "Same F1 pose/zoom as dev.11; direct QA region load, I1 story deliberately unfinished.")
	_pose(Vector3(0, 6, 18), 42.0)
	_lock("F1:growth")
	var growth: Dictionary = session.entities.get("F1:growth", {})
	_check(maxf(float(growth.get("light_level", 0)), float(growth.get("environment_light", 0))) < 0.25, "captured roots truly lack light")
	_check(session.interface.target_info.text.contains("缺少光照"), "root condition is visible in compact HUD")
	await _capture("07-F1-shore-unlit-roots", "Same F1-shore pose/zoom as dev.11; unchanged unlit roots, no fabricated ability outcome.")
	_pose(Vector3(-24, 5.2, 29), 26.0)
	_lock("F1:mirror")
	session.interface.select_ability(3)
	session._refresh_interface()
	await _capture("08-mirror-light-tool", "Production ring target and light action/reverse; no mirror state edit.")

	_pose(session.world.crown_arena.host_position("F1:crown_host_west") + Vector3(0, 0, 2.5), 26.0)
	var health_before: float = session.players[1].health
	var energy_before: float = session.entities["player:1"].energy
	if not _check(session.crown.start(false), "actual development Crown encounter starts with valid solo roster"):
		await _finish()
		return
	_check(session.players[1].health == health_before and session.entities["player:1"].energy == energy_before, "encounter setup did not heal or replenish energy")
	_pose(Vector3(1, 13, -22), 18.0)
	_lock("boss:crown_core")
	_check(not session.crown.presentation().core_open and not session.boss_campaign, "closed core uses real encounter state, not fabricated campaign/open-window progress")
	var compact_text: String = session.interface.objective.text
	await _capture("09-core-compact", "Development encounter start; actual closed core, no damage, retry, cooldown edit or reward.")
	var boss_before := _digest(session.crown.encounter.get_state())
	session.interface.details_button.pressed.emit()
	session._refresh_interface()
	_check(session.interface.details_open and session.interface.objective.text.length() > compact_text.length(), "task details button reveals actual combat guidance")
	_check(_digest(session.crown.encounter.get_state()) == boss_before, "expanding guidance does not advance the encounter")
	await _capture("10-core-expanded", "Same pose/state as compact view; only the real details button was pressed.")
	var menu_button := _find_button(session.interface.top_panel, "菜单")
	if _check(menu_button != null, "top menu button exists"):
		menu_button.pressed.emit()
	session._refresh_interface()
	_check(session.interface.menu.visible and session.interface.flight_details.is_visible_in_tree()
		and not session.interface.flight_details.text.is_empty(), "menu exposes actual detailed flight readout")
	await _capture("11-menu-flight-details", "Real menu button; actual detailed flight label, no vitals replacement.")
	_check(session.story.state.get("completed", []) == ["I1:rescue:brief"], "entire capture committed only one real briefing objective")
	_check(int(session.stats.abilities) == 0 and shots.size() == 11, "eleven views without casting or faking campaign progress")
	session_phases.append(_phase_record())
	await _supplemental_views()
	await _finish()

func _supplemental_views() -> void:
	# A new real solo scene keeps the old eleven views and their zero-cast evidence
	# untouched. It uses this run's same isolated QA store, never a user save.
	var first_instance: int = session.get_instance_id()
	var old_scene: WeakRef = weakref(session)
	var old_ui: WeakRef = weakref(session.interface)
	var old_network: WeakRef = weakref(session.network)
	var story_before := _digest(session.story.state)
	session.network.close()
	session.queue_free()
	await process_frame
	await process_frame
	if not _check(old_scene.get_ref() == null and old_ui.get_ref() == null and old_network.get_ref() == null
		and _main_scene_count() == 0, "old session, UI and network are actually freed before rebuilding"):
		return
	session = load("res://scenes/v3/main.tscn").instantiate()
	root.add_child(session)
	phase = "independent_supplemental_solo_scene"
	if not _check(session.profile_ready and session.store.root_path == "user://profiles_v3/" + profile
		and session.get_instance_id() != first_instance and session.start_flight("solo"), "explicit independent supplemental scene uses the same isolated QA store"):
		return
	_freeze_automatic_updates()
	session.interface.action_requested.connect(_record_ui_action)
	_check(_main_scene_count() == 1 and session.interface.action_requested.is_connected(Callable(session, "_ui_action"))
		and session.network.action_received.is_connected(Callable(session, "_action_received")), "new sole session has live production UI and authority signal connections")
	if not _check(session._load_region("F1"), "supplemental scene explicitly QA-loads F1, no campaign unlock"):
		return
	_freeze_automatic_updates()
	_check(_digest(session.story.state) == story_before, "new scene restores actual briefing-only story unchanged")
	_check(not session.boss_active and int(session.stats.abilities) == 0, "supplemental scene starts without old encounter/cast statistics")
	if not _check(OS.is_debug_build(), "live input window supports production neutral QA input hook in debug/editor build"):
		return
	_pose(Vector3(-29, 3.5, 12), 26.0)
	_lock("F1:thermal")
	_key(KEY_5)
	session._refresh_interface()
	_check(session.selected_ability == "heat" and session.interface.selected == 4, "new scene keyboard selection reaches its live Session callback")
	_check(not session.interface.details_open and is_equal_approx(float(session.entities["F1:thermal"].temperature), 20.0), "real thermal target starts at 20 degrees in compact view")
	var initial_energy: float = session.entities["player:1"].energy
	_key(KEY_F)
	_check(int(session.stats.abilities) == 1 and is_equal_approx(float(session.entities["F1:thermal"].temperature), 45.0), "first real F heats production thermal target to 45")
	_check(is_equal_approx(float(session.entities["player:1"].energy), initial_energy - 8.0), "first F pays real 8 energy without refill")
	var cooldown_wait: Dictionary = await _live_physics_window(false)
	live_windows.append(cooldown_wait)
	if not _check(float(session.cooldowns.get(1, 0)) <= 0.0, "production physics naturally expires the first heat cooldown"):
		return
	var energy_before_second: float = session.entities["player:1"].energy
	_key(KEY_F)
	session._refresh_interface()
	_check(int(session.stats.abilities) == 2 and int(session.stats.rejected_abilities) == 0
		and is_equal_approx(float(session.entities["F1:thermal"].temperature), 70.0), "second real F reaches 70 with two accepted casts and no cooldown bypass")
	_check(is_equal_approx(float(session.entities["player:1"].energy), energy_before_second - 8.0), "second F pays 8 from naturally regenerated energy")
	_check(session.interface.target_info.text.contains("温度 70°"), "compact thermal target exposes actual 70-degree result")
	await _capture("12-F1-thermal-real-F-F-70", "Independent solo scene: two actual F inputs heat F1:thermal from 20 to 70; production physics expires cooldown and normal energy regeneration is recorded, never assigned.")

	_pose(Vector3(0, 6, 18), 42.0)
	_lock("F1:growth")
	session.interface.select_ability(6)
	var roots_before: Dictionary = session.entities["F1:growth"].duplicate(true)
	if not _check("thermal" not in roots_before.get("tags", []), "abnormal-temperature UI fixture specifically targets non-thermal roots"):
		return
	var store_before := _digest(session.store.snapshot())
	var all_entities_before := _digest(session.entities)
	var stats_before: Dictionary = session.stats.duplicate(true)
	var notice_before: String = session.interface.message.text
	var notice_time_before: float = session.interface.message_time
	# Presentation-only edge case, explicitly labelled in the raw screenshot.
	# No physics/observer/cast/commit runs while this temporary field is present.
	session.entities["F1:growth"].temperature = 61.0
	current_fixture = {"kind":"UI_ONLY_NOT_GAMEPLAY", "target_id":"F1:growth", "temporary_temperature":61.0,
		"reason":"Non-thermal root abnormal-state presentation; not claimed reachable by player heat.", "simulation_frozen":paused}
	session._refresh_interface()
	session.interface.notify("QA 显示夹具：非热响应根簇临时设为 61°，仅检查异常提示，非可玩过程。")
	_check(session.interface.target_info.text.contains("过热 61°") and session.interface.target_info.text.contains("不能直接调温")
		and not session.interface.target_info.text.contains("X 降温") and not session.interface.target_info.text.contains("F 加热"), "non-thermal roots show abnormal temperature without inventing F/X temperature control")
	await _capture("13-F1-root-61-UI-ONLY-fixture", "UI-only fixture explicitly marked on screen: temporarily set non-thermal roots to 61 while all simulation is frozen; this is not a gameplay state or progression result.")
	temperature_fixture = {"definition":current_fixture.duplicate(true), "entity_before":roots_before,
		"entity_during":session.entities["F1:growth"].duplicate(true), "store_sha256_before":store_before}
	session.entities["F1:growth"] = roots_before.duplicate(true)
	session.interface.message.text = notice_before
	session.interface.message_time = notice_time_before
	current_fixture.clear()
	session._refresh_interface()
	temperature_fixture["entity_restored"] = session.entities["F1:growth"].duplicate(true)
	temperature_fixture["store_sha256_after"] = _digest(session.store.snapshot())
	_check(_digest(session.entities) == all_entities_before and session.stats == stats_before
		and temperature_fixture.store_sha256_after == store_before, "UI-only 61-degree fixture fully restored with no entity/cast/save side effects")

	# Open east-bank ground is a real raised surface (about Y=2.4). Let the real
	# body integrate briefly instead of writing ground_distance or ground_y.
	_pose(Vector3(23, 7, 38), 26.0)
	var integration: Dictionary = await _live_physics_window(true)
	live_windows.append(integration)
	var body = session.players[1]
	var sample: Dictionary = body.telemetry.duplicate(true)
	if not _check(sample.get("position_m") is Vector3 and float(integration.flight_seconds_after) > float(integration.flight_seconds_before), "real _integrate_forces produced a fresh physical height sample"):
		return
	var sample_position: Vector3 = sample.position_m
	var sample_hit := _downward_query(sample_position, body.get_rid())
	var current_hit := _downward_query(body.global_position, body.get_rid())
	if not _check(not sample_hit.is_empty() and not current_hit.is_empty(), "independent downward queries hit actual east-bank collision"):
		return
	var expected_sample_agl := maxf(0.0, sample_position.y - float(sample_hit.position.y))
	var expected_current_agl := maxf(0.0, body.global_position.y - float(current_hit.position.y))
	var sample_lag: float = absf(body.global_position.y - sample_position.y)
	_check(is_equal_approx(float(body.ground_distance), float(sample.altitude_agl_m))
		and absf(float(body.ground_distance) - expected_sample_agl) <= 0.002,
		"production AGL equals fresh integration telemetry and independent ray at its sample origin")
	_check(absf(float(body.ground_y) - float(current_hit.position.y)) <= 0.002
		and absf(float(body.ground_distance) - expected_current_agl) <= sample_lag + 0.002,
		"live world-Y/AGL match current real ground ray within explicitly measured integration sample lag")
	_check(float(current_hit.position.y) > 2.0 and absf(body.global_position.y - float(body.ground_distance)) > 2.0,
		"raised east bank distinguishes world height from AGL, rather than two identical zero-ground values")
	current_height_probe = {"mode":"actual_rigid_body_integration_then_frozen", "telemetry_tick":sample.tick,
		"integration_sample_position":_vec(sample_position), "world_position":_vec(body.global_position),
		"body_ground_y":body.ground_y, "body_agl":body.ground_distance, "telemetry_agl":sample.altitude_agl_m,
		"sample_ray":_ray_record(sample_hit), "current_ray":_ray_record(current_hit),
		"expected_agl_at_sample":expected_sample_agl, "expected_agl_at_current_position":expected_current_agl,
		"vertical_sample_lag_m":sample_lag, "ray_comparison_epsilon_m":0.002,
		"note":"No ground_distance/ground_y assignment. Current body position and the last force-integration sample can differ by one solver step."}
	session.flight_camera.snap(body.global_position)
	session._refresh_interface()
	_check(session.interface.vitals.text.contains("高度 %.1fm / 离地 %.1fm" % [body.global_position.y, body.ground_distance]), "top HUD exposes both actual world Y and actual physical AGL")
	await _capture("14-F1-live-physics-world-Y-and-AGL", "Short actual physics integration on raised east bank, then frozen capture; body AGL independently checked against actual collision rays, with solver sample lag recorded.")
	_check(session.story.state.get("completed", []) == ["I1:rescue:brief"], "supplemental real heat/physics and UI fixture add no story completion")
	_check(shots.size() == 14 and int(session.stats.abilities) == 2 and int(session.stats.rejected_abilities) == 0,
		"original eleven plus three supplemental views; precisely two real heat casts, no rejected or fixture casts")
	session_phases.append(_phase_record())

func _live_physics_window(integrate_body: bool) -> Dictionary:
	var body = session.players[1]
	var record := {"kind":"real_body_integration" if integrate_body else "natural_heat_cooldown", "phase":phase,
		"clock_before":session.world.clock_seconds, "physics_tick_before":Engine.get_physics_frames(),
		"flight_seconds_before":body.flight_seconds, "cooldown_before":float(session.cooldowns.get(1, 0)),
		"energy_before":session.entities["player:1"].energy, "health_before":body.health}
	# Existing neutral-input hook prevents incidental keyboard/controller input.
	# The production Session callback owns cooldown decrement and energy recovery.
	session.inputs.test_enabled = true
	session.inputs.test_frame = {"axes":{}, "held":[], "edges":[]}
	if integrate_body:
		body.freeze = false
		body.sleeping = false
	session.set_physics_process(true)
	paused = false
	var waited := 0
	while waited < 90:
		await physics_frame
		await process_frame
		waited += 1
		if integrate_body and waited >= 8: break
		if not integrate_body and float(session.cooldowns.get(1, 0)) <= 0.0: break
	_freeze_automatic_updates()
	record.merge({"clock_after":session.world.clock_seconds, "physics_tick_after":Engine.get_physics_frames(),
		"flight_seconds_after":body.flight_seconds, "cooldown_after":float(session.cooldowns.get(1, 0)),
		"energy_after":session.entities["player:1"].energy, "health_after":body.health, "awaited_frame_pairs":waited})
	_check(float(record.clock_after) > float(record.clock_before) and record.physics_tick_after > record.physics_tick_before,
		"production simulation really advanced: " + str(record.kind))
	var elapsed := float(record.clock_after) - float(record.clock_before)
	record["actual_simulation_seconds"] = elapsed
	_check(absf(float(record.energy_after) - minf(100.0, float(record.energy_before) + elapsed * 9.0)) < 0.0001
		and absf(float(record.cooldown_after) - maxf(0.0, float(record.cooldown_before) - elapsed)) < 0.0001,
		"energy/cooldown changes match normal production elapsed time: " + str(record.kind))
	_check(body.health == record.health_before, "bounded live window did not heal or damage pilot: " + str(record.kind))
	return record

func _main_scene_count() -> int:
	var count := 0
	for child in root.get_children():
		if child.scene_file_path == "res://scenes/v3/main.tscn": count += 1
	return count

func _downward_query(origin: Vector3, exclude: RID) -> Dictionary:
	var query := PhysicsRayQueryParameters3D.create(origin, origin + Vector3.DOWN * 100.0, 1 | 32)
	query.exclude = [exclude]
	return session.get_world_3d().direct_space_state.intersect_ray(query)

func _ray_record(hit: Dictionary) -> Dictionary:
	return {"position":_vec(hit.position), "normal":_vec(hit.normal), "collider_path":str(hit.collider.get_path()),
		"entity_id":str(hit.collider.get_meta("entity_id", "")), "collision_layer":hit.collider.collision_layer}

func _phase_record() -> Dictionary:
	return {"phase":phase, "session_instance_id":session.get_instance_id(), "stats":session.stats.duplicate(true),
		"logger_instance_id":capture_logger.get_instance_id(),
		"story_completed":session.story.state.get("completed", []).duplicate(), "world_clock_seconds":session.world.clock_seconds,
		"health":session.players[1].health, "energy":session.entities["player:1"].energy}

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
	if profile_count != 1 or output_count != 1 or pattern.search(profile) == null or output.is_empty(): return false
	output = ProjectSettings.globalize_path(output).replace("\\", "/").simplify_path()
	var allowed := ProjectSettings.globalize_path("res://artifacts/v3/art").replace("\\", "/").simplify_path()
	if not output.is_absolute_path() or output.get_base_dir().to_lower() != allowed.to_lower(): return false
	if not output.get_file().begins_with("hud-visibility-") or output.get_file() == "hud-visibility-": return false
	if DirAccess.dir_exists_absolute(output) or FileAccess.file_exists(output): return false
	if DirAccess.dir_exists_absolute("user://profiles_v3/" + profile) or FileAccess.file_exists("user://profiles_v3/" + profile): return false
	return DisplayServer.get_name() != "headless" and RenderingServer.get_current_rendering_method() == "gl_compatibility" and RenderingServer.is_render_loop_enabled()

func _freeze_automatic_updates() -> void:
	# Keep production simulation_paused false: real G/lock handlers still validate.
	# Only this QA scene tree and automatic processes are frozen between UI actions.
	session.set_process(false)
	session.set_physics_process(false)
	session.inputs.set_process(false)
	session.inputs.set_physics_process(false)
	for body in session.players.values():
		body.freeze = true
		body.set_process(false)
		body.set_physics_process(false)
	paused = true

func _pose(at: Vector3, zoom: float) -> void:
	current_height_probe.clear()
	var body = session.players[1]
	body.global_position = at
	body.linear_velocity = Vector3.ZERO
	body.angular_velocity = Vector3.ZERO
	session.entities["player:1"].position = at
	expected_camera_size = zoom
	session.flight_camera.target_size = zoom
	session.flight_camera.snap(at)
	session.story.refresh(at, 0.0)
	session._refresh_interface()

func _lock(id: String) -> void:
	session.network.send_action("lock", {"target_id":id})
	_check(str(session.locks.get(1, "")) == id, "actual range-validated target lock: " + id)
	session._refresh_interface()

func _key(code: Key) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = code
	event.keycode = code
	event.pressed = true
	session._unhandled_input(event)

func _record_ui_action(action: String, payload: Dictionary) -> void:
	ui_events.append({"action":action, "payload":payload.duplicate(true)})

func _probe_suggestions() -> void:
	for button in session.interface.suggestion_buttons:
		if not button.visible: continue
		var expected := str(button.get_meta("ability", ""))
		var before := _selection_state()
		var event_start := ui_events.size()
		button.pressed.emit()
		session._refresh_interface()
		var after := _selection_state()
		var emitted := ui_events.slice(event_start)
		_check(session.selected_ability == expected, "suggestion selects actual ability: " + expected)
		_check(before == after, "suggestion leaves lock/entities/energy/story/action counters unchanged: " + expected)
		_check(emitted.size() == 1 and emitted[0].action == "select", "suggestion emits select only: " + expected)
		selection_probes.append({"ability":expected, "before":before, "after":after, "ui_events":emitted})

func _selection_state() -> Dictionary:
	return {"lock":str(session.locks.get(1, "")), "entities":_digest(session.entities), "story":_digest(session.story.state),
		"energy":session.entities["player:1"].energy, "health":session.players[1].health, "stats":session.stats.duplicate(true)}

func _capture(id: String, purpose: String) -> void:
	for unused in range(SETTLE_FRAMES): await RenderingServer.frame_post_draw
	var panels := _measure_ui(id)
	var path := output.path_join(id + ".png")
	if not _check(not FileAccess.file_exists(path), "new PNG path: " + id): return
	var image: Image = root.get_texture().get_image()
	if not _check(image != null and not image.is_empty() and image.get_size() == SIZE, "real 1280x720 viewport: " + id): return
	_check(root.size == SIZE and session.camera.projection == Camera3D.PROJECTION_ORTHOGONAL
		and is_equal_approx(float(session.camera.size), expected_camera_size), "requested fixed orthographic camera and viewport: " + id)
	if not _check(image.save_png(path) == OK, "rendered PNG saved: " + id): return
	var image_sha := FileAccess.get_sha256(path)
	_check(image_sha.length() == 64, "actual PNG byte hash: " + id)
	var body = session.players[1]
	var ui = session.interface
	_check(ui.vitals.text.contains("生命 %d" % body.health) and ui.vitals.text.contains("能量 %d" % session.entities["player:1"].energy), "actual production vitals retained: " + id)
	_check(ui.vitals.text.contains("高度 %.1fm / 离地 %.1fm" % [body.global_position.y, body.ground_distance]), "both current Y and stored AGL remain in top HUD: " + id)
	shots.append({"id":id, "purpose":purpose, "file":path, "png_sha256":image_sha,
		"session_phase":phase, "session_instance_id":session.get_instance_id(), "explicit_UI_fixture":current_fixture.duplicate(true),
		"resolution":[image.get_width(), image.get_height()], "region":session.region_id,
		"pilot_position":_vec(body.global_position), "health":body.health, "energy":session.entities["player:1"].energy,
		"ground_distance_readout":body.ground_distance, "selected_ability":session.selected_ability, "lock":str(session.locks.get(1, "")),
		"height_provenance":current_height_probe.duplicate(true) if not current_height_probe.is_empty() else {"mode":"frozen_QA_pose_cached_AGL_not_physical_measurement", "warning":"Body was teleported while frozen. Stored AGL can be zero/stale and must not be interpreted as the actual clearance at this pose."},
		"camera_size":session.camera.size, "camera_transform":_transform(session.camera.global_transform),
		"story_completed":session.story.state.get("completed", []).duplicate(), "panels":panels,
		"vitals_text":ui.vitals.text, "objective_text":ui.objective.text, "ability_title":ui.ability_title.text,
		"ability_action":ui.ability_description.text, "target_info":ui.target_info.text,
		"flight_details":ui.flight_details.text, "world_clock_seconds":session.world.clock_seconds,
		"input_sha256":_input_hashes()})

func _measure_ui(shot: String) -> Dictionary:
	var ui = session.interface
	var result: Dictionary = {}
	for pair in [["top", ui.top_panel], ["bottom", ui.bottom_panel], ["task", ui.task_panel],
		["wheel", ui.wheel], ["radio", ui.radio], ["menu", ui.menu], ["vote", ui.vote]]:
		var panel: Control = pair[1]
		var record := _control_record(panel)
		record["controls"] = []
		if panel.is_visible_in_tree():
			_check(_inside(panel.get_global_rect(), Rect2(Vector2.ZERO, Vector2(SIZE))), "visible panel within viewport: " + shot + ":" + str(pair[0]))
			_collect_controls(panel, record.controls, shot)
		result[pair[0]] = record
	if ui.target_marker.is_visible_in_tree():
		var caption_bounds: Rect2 = ui.target_marker.caption.get_global_rect()
		var background := Rect2(caption_bounds.position - Vector2(5, 3), caption_bounds.size + Vector2(10, 6))
		_check(_inside(background, Rect2(Vector2.ZERO, Vector2(SIZE))), "target label background inside viewport: " + shot)
		for panel in ui.target_marker.panel_obstacles:
			if is_instance_valid(panel) and panel.is_visible_in_tree():
				_check(not background.intersects(panel.get_global_rect()), "target label clear of HUD panel: " + shot + ":" + str(panel.get_path()))
	result["overlay_controls"] = []
	_collect_controls(ui.hud, result.overlay_controls, shot, true)
	_check(ui.top_panel.size.y <= 52.0, "top panel at most 52px: " + shot)
	_check(ui.bottom_panel.size.y <= 84.0, "bottom panel at most 84px: " + shot)
	_check(_find_button(ui.bottom_panel, "B 全部能力") != null and ui.details_button.is_visible_in_tree(), "B and task details buttons remain available: " + shot)
	_check(is_instance_valid(ui.explore_button) and is_instance_valid(ui.gate_button), "nearby interaction buttons exist: " + shot)
	var a: Rect2 = ui.top_panel.get_global_rect()
	var b: Rect2 = ui.bottom_panel.get_global_rect()
	var c: Rect2 = ui.task_panel.get_global_rect()
	var union_area := a.get_area() + b.get_area() + c.get_area() - a.intersection(b).get_area() - a.intersection(c).get_area() - b.intersection(c).get_area() + a.intersection(b).intersection(c).get_area()
	result["hud_union_area_px"] = union_area
	result["hud_union_fraction"] = union_area / float(SIZE.x * SIZE.y)
	result["old_review_approx_fraction"] = 0.32
	result["area_note"] = "Top/bottom/task union only. Old 32% is an approximate screenshot-review baseline; this measurement is not an aesthetic pass. Overlays recorded separately."
	return result

func _collect_controls(node: Node, records: Array, shot: String, skip_panels: bool = false) -> void:
	for child in node.get_children():
		if skip_panels and child is PanelContainer: continue
		if child is Control and not child.is_visible_in_tree(): continue
		if child is Label or child is Button or child is LineEdit or child is OptionButton:
			var control := child as Control
			var record := _control_record(control)
			record["text"] = str(control.text)
			var clipped := _clip_rect(control)
			record["visible_after_scroll_clip"] = _rect(clipped)
			record["clipped_by_scroll_or_ancestor"] = clipped != control.get_global_rect()
			var parent := control.get_parent() as Control
			if parent != null:
				record["layout_parent_rect"] = _rect(parent.get_global_rect())
				_check(_inside(control.get_global_rect(), parent.get_global_rect()), "control within layout container: " + shot + ":" + str(control.get_path()))
			if clipped.has_area():
				_check(_inside(clipped, Rect2(Vector2.ZERO, Vector2(SIZE))), "visible text/button within viewport: " + shot + ":" + str(control.get_path()))
				var minimum := control.get_combined_minimum_size()
				_check(control.size.x + 1.0 >= minimum.x and control.size.y + 1.0 >= minimum.y, "text/button at least measured minimum: " + shot + ":" + str(control.get_path()))
			records.append(record)
		_collect_controls(child, records, shot, skip_panels)

func _clip_rect(control: Control) -> Rect2:
	var visible := control.get_global_rect()
	var node := control.get_parent()
	while node != null:
		if node is Control and node.clip_contents: visible = visible.intersection(node.get_global_rect())
		node = node.get_parent()
	return visible

func _control_record(control: Control) -> Dictionary:
	return {"path":str(control.get_path()), "class":control.get_class(), "visible":control.is_visible_in_tree(),
		"rect":_rect(control.get_global_rect()), "minimum_size":_vec2(control.get_combined_minimum_size())}

func _find_button(node: Node, exact: String) -> Button:
	for child in node.get_children():
		if child is Button and child.text == exact: return child
		var found := _find_button(child, exact)
		if found != null: return found
	return null

func _inside(inner: Rect2, outer: Rect2) -> bool:
	return outer.grow(1.0).encloses(inner)

func _rect(value: Rect2) -> Array:
	return [value.position.x, value.position.y, value.size.x, value.size.y]

func _vec2(value: Vector2) -> Array:
	return [value.x, value.y]

func _vec(value: Vector3) -> Array:
	return [value.x, value.y, value.z]

func _transform(value: Transform3D) -> Dictionary:
	return {"origin":_vec(value.origin), "basis_x":_vec(value.basis.x), "basis_y":_vec(value.basis.y), "basis_z":_vec(value.basis.z)}

func _digest(value: Variant) -> String:
	return JSON.stringify(value, "", true, true).sha256_text()

func _add_import_hashes() -> void:
	for path in INPUTS:
		var descriptor: String = str(path) + ".import"
		if not FileAccess.file_exists(descriptor): continue
		input_paths.append(descriptor)
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

func _check(condition: bool, label: String) -> bool:
	checks.append({"name":label, "passed":condition})
	return condition

func _timeout() -> void:
	if finishing:
		quit(3)
		return
	_check(false, "120 second watchdog: incomplete capture")
	_finish.call_deferred()

func _finish() -> void:
	if finishing: return
	finishing = true
	Engine.time_scale = 1.0
	var stats: Dictionary = session.stats.duplicate(true) if is_instance_valid(session) else {}
	if is_instance_valid(session):
		if is_instance_valid(session.network): session.network.close()
		session.queue_free()
	await process_frame
	await process_frame
	var hashes_after := _input_hashes()
	_check(not hashes_before.is_empty() and hashes_before == hashes_after, "source/assets/import cache unchanged across capture")
	for shot in shots: _check(shot.input_sha256 == hashes_before, "same input hashes at screenshot: " + str(shot.id))
	var logged := capture_logger.snapshot()
	_check(int(logged.error_count) == 0, "no engine/script/shader ERROR including cleanup")
	var passed := not checks.is_empty()
	for check in checks: passed = passed and bool(check.passed)
	var report := {"purpose":"Production 720p HUD visibility and real button/input behavior; fixed scripted QA poses.",
		"status":"captured_for_review_not_aesthetic_acceptance", "passed":passed, "profile":profile, "output":output,
		"checks":checks, "shots":shots, "selection_probes":selection_probes, "ui_events":ui_events, "session_stats":stats,
		"session_phases":session_phases, "live_physics_windows":live_windows, "temperature_UI_fixture":temperature_fixture,
		"input_sha256_before":hashes_before, "input_sha256_after":hashes_after, "engine_log":logged,
		"engine_version":Engine.get_version_info(), "gpu":RenderingServer.get_video_adapter_name(),
		"renderer":RenderingServer.get_current_rendering_method(), "display":DisplayServer.get_name(),
		"viewport":[root.size.x, root.size.y], "window":str(DisplayServer.window_get_size()),
		"limitations":["Raw viewport PNGs, no image editing; no performance or human-play claim.",
			"The original eleven views retain frozen QA poses and cached AGL (possibly zero), explicitly marked per shot. Only view 14 has fresh rigid-body integration and independent ground rays; no landing or flight comfort claim.",
			"Only nearby G rescue brief is committed. F1 direct load bypasses travel for QA; I1 objective remaining in F1 is intentional fixture state.",
			"Crown is started through the production development encounter API with its real closed state; no campaign completion, health refill, ability or cooldown edit.",
			"After the original eleven views the scene is destroyed and a new solo scene is explicitly instantiated from the same isolated QA store; its normal spawn is not a refill of the previous encounter. Separate phase stats are retained.",
			"View 12 uses two real F heat inputs with production cooldown/energy updates. View 13 temporarily assigns only a non-thermal root temperature for UI presentation, visibly labels it, and restores it without physics/save/ability progression.",
			"Scroll-clipped children are recorded separately. Panel dimensions and controls are mechanical checks; image aesthetics need actual review.",
			"Logger starts before scene loading; the runner must also reject parse/startup failures from process exit/log."]}
	var path := output.path_join("capture.json")
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE) if not FileAccess.file_exists(path) else null
	var write_ok := file != null
	if file != null:
		file.store_string(JSON.stringify(report, "\t", true, true))
		file.flush()
		write_ok = file.get_error() == OK
		file.close()
	if not write_ok: push_error("HUD capture report could not be saved")
	var final_log := capture_logger.snapshot()
	var success: bool = passed and write_ok and int(final_log.error_count) == 0
	print("HUD_VISIBILITY_CAPTURE ", JSON.stringify({"output":output, "passed":success, "checks":checks.size(), "shots":shots.size(), "engine_errors":final_log.error_count}))
	OS.remove_logger(capture_logger)
	quit(0 if success else 1)
