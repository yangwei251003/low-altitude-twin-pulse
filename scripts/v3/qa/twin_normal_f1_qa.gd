extends Node
const SourceBinding = preload("res://scripts/v3/qa/twin_source_binding.gd")
static var _source_binding: Dictionary = {}
## Same-profile F1 continuation AUTHORING COPY. Root installs this separately.
## Never imports a prior result into Store or writes a progress/physical fixture.
const Pilot = preload("res://scripts/v3/gameplay/canal/canal_transport_physics/transport_pilot.gd")
const Store = preload("res://scripts/v3/core/twin_world_store.gd")
const GOAL := "I1:whale:engage"
const SOURCE_GOALS := ["I1:rescue:brief", "I1:rescue:channel", "I1:rescue:contact", "I1:rescue:evacuate", "I1:evidence:trace", "I1:evidence:engineer", "I1:evidence:ledger", "I1:evidence:echo", "F1:needs:listen"]
static var SOURCE_PROFILE := ""
static var SOURCE_RECEIPTS_SHA256 := ""
static var SOURCE_REPORT_SHA256 := ""
const EXPECTED := ["I1:rescue:brief","I1:rescue:channel","I1:rescue:contact","I1:rescue:evacuate","I1:evidence:trace","I1:evidence:engineer","I1:evidence:ledger","I1:evidence:echo","F1:needs:listen","F1:needs:nursery","F1:needs:route","F1:repair:plan","F1:repair:light","F1:repair:grow","F1:repair:confirm","I1:whale:brief","I1:whale:engage"]
const Director = preload("res://scripts/v3/gameplay/actions/twin_action_director.gd")
const Catalog = preload("res://scripts/v3/campaign/twin_campaign_catalog.gd")
const MASK := 1 | 2 | 4 | 8 | 32
class ErrorLogger extends Logger:
	var errors: Array = []
	var guard := Mutex.new()
	func _log_error(function: String, file: String, line: int, code: String, rationale: String, _notify: bool, kind: int, _trace: Array[ScriptBacktrace]) -> void:
		if kind == Logger.ERROR_TYPE_WARNING: return
		guard.lock()
		errors.append({"function":function,"file":file,"line":line,"code":code,"rationale":rationale,"kind":kind})
		guard.unlock()
var session: Node
var logger := ErrorLogger.new()
var pilot: RefCounted
var output := ""
var profile := ""
var max_seconds := 300.0
var started_usec := 0
var started_frame := 0
var running := false
var finished := false
var phase := "not_started"
var command_serial := 0
var physics_frames := 0
var actual_distance := 0.0
var max_frame_distance := 0.0
var last_body_id := 0
var last_position := Vector3.ZERO
var last_region := ""
var last_heartbeat := 0.0
var previous_completed: Array = []
var events: Array = []
var samples: Array = []
var checks: Array = []
var failures: Array[String] = []
var save_callbacks: Array = []
var initial: Dictionary = {}
var final_reader: Dictionary = {}
var _success_exit_report: Dictionary = {}

## Read-only App guard, called BEFORE instantiating MAIN/opening any Store.
## Accept exactly this dedicated four-argument CLI, with no fallback profile.
static func preflight(args: PackedStringArray) -> Dictionary:
	_source_binding = {}
	var bound: Dictionary = SourceBinding.prepare(args,"normal-f1",SOURCE_GOALS,EXPECTED)
	if not bound.get("ok",false): return {"ok":false,"code":bound.get("code","source_binding_rejected"),"config":{}}
	_source_binding = bound.binding
	args = bound.args
	SOURCE_PROFILE = str(_source_binding.constants["SOURCE_PROFILE"])
	SOURCE_REPORT_SHA256 = str(_source_binding.constants["SOURCE_REPORT_SHA256"])
	SOURCE_RECEIPTS_SHA256 = str(_source_binding.constants["SOURCE_RECEIPTS_SHA256"])
	var values: Dictionary = {}
	for argument: String in args:
		var key := ""
		var value := ""
		if argument == "--qa-normal-f1":
			key = "enabled"
			value = "true"
		else:
			for pair: Array in [["--qa-profile=", "profile"], ["--qa-normal-output=", "output"], ["--qa-normal-seconds=", "seconds"]]:
				if argument.begins_with(str(pair[0])):
					key = str(pair[1])
					value = argument.trim_prefix(str(pair[0]))
					break
		if key.is_empty(): return {"ok":false,"code":"unknown_or_missing_normal_f1_cli_value","config":{}}
		if values.has(key): return {"ok":false,"code":"duplicate_normal_f1_cli","config":{}}
		if value.is_empty(): return {"ok":false,"code":"empty_normal_f1_cli_value","config":{}}
		values[key] = value
	if values.size() != 4: return {"ok":false,"code":"all_four_normal_f1_arguments_required","config":{}}
	var selected_profile: String = str(values.profile)
	if selected_profile != SOURCE_PROFILE:
		return {"ok":false,"code":"only_verified_first_segment_profile_accepted","config":{}}
	if not DirAccess.dir_exists_absolute("user://profiles_v3/" + selected_profile): return {"ok":false,"code":"existing_verified_profile_required","config":{}}
	# Original loader only reads existing generations. No commit/fork/reset.
	var reader = Store.new("user://profiles_v3/" + selected_profile)
	var loaded: Dictionary = reader.load_profile()
	if not loaded.get("ok", false) or loaded.get("recovered", false): return {"ok":false,"code":"unrecovered_original_save_required","config":{}}
	if not SourceBinding.start_matches(_source_binding,reader.snapshot()): return {"ok":false,"code":"source_binding_initial_snapshot_changed","config":{}}
	var verified: Dictionary = _source_check(reader.snapshot())
	if not verified.ok: return {"ok":false,"code":verified.code,"config":{}}
	var selected_output: String = str(values.output).replace("\\", "/")
	if not selected_output.is_absolute_path() or "://" in selected_output or ".." in selected_output or "\n" in selected_output or "\r" in selected_output or not selected_output.get_file().begins_with("normal-f1-") or selected_output.get_extension() != "json" or FileAccess.file_exists(selected_output) or DirAccess.dir_exists_absolute(selected_output):
		return {"ok":false,"code":"new_absolute_normal_f1_json_required","config":{}}
	var selected_seconds: String = str(values.seconds)
	if not selected_seconds.is_valid_int() or str(selected_seconds.to_int()) != selected_seconds or selected_seconds.to_int() < 30 or selected_seconds.to_int() > 300:
		return {"ok":false,"code":"normal_f1_seconds_30_to_300_required","config":{}}
	return {"ok":true,"code":"normal_f1_preflight_valid","config":{"profile":selected_profile,"output":selected_output,"max_seconds":selected_seconds.to_int(),"source_profile_id":str(reader.snapshot().profile_id),"source_lineage_id":str(reader.snapshot().lineage_id)}}

## Root adds this Node to Session, then calls run deferred after Session._ready.
## options = {profile, output: absolute .json, max_seconds: 30..300}.
func run(owner_session: Node, options: Dictionary = {}) -> Dictionary:
	if running or finished: return {"ok":false,"code":"already_started"}
	session = owner_session
	profile = str(options.get("profile", ""))
	output = str(options.get("output", "")).replace("\\", "/")
	max_seconds = float(options.get("max_seconds", 300.0))
	if not is_instance_valid(session) or profile != SOURCE_PROFILE or profile != profile.validate_filename() or not output.is_absolute_path() or ".." in output or not output.get_file().begins_with("normal-f1-") or output.get_extension() != "json" or FileAccess.file_exists(output) or not is_finite(max_seconds) or max_seconds < 30.0 or max_seconds > 300.0:
		return {"ok":false,"code":"isolated_profile_absolute_new_output_and_bound_required"}
	if not is_inside_tree() or session.store.root_path != "user://profiles_v3/" + profile:
		return {"ok":false,"code":"mounted_normal_session_profile_required"}
	if DirAccess.make_dir_recursive_absolute(output.get_base_dir()) != OK:
		return {"ok":false,"code":"output_directory_unavailable"}
	if not SourceBinding.start_matches(_source_binding,session.store.snapshot()): return {"ok":false,"code":"source_binding_initial_snapshot_changed"}
	var verified: Dictionary = _source_check(session.store.snapshot())
	if not verified.ok: return verified
	if str(options.get("source_profile_id", "")) != str(session.store.snapshot().profile_id) or str(options.get("source_lineage_id", "")) != str(session.store.snapshot().lineage_id):
		return {"ok":false,"code":"preflight_profile_identity_changed"}
	OS.add_logger(logger)
	started_usec = Time.get_ticks_usec()
	started_frame = Engine.get_physics_frames()
	process_mode = Node.PROCESS_MODE_ALWAYS
	process_physics_priority = 10 # After normal Session input; before Flight integration.
	running = true
	set_process(true)
	set_physics_process(true)
	_execute.call_deferred()
	return {"ok":true,"code":"observing_verified_F1_continuation","goal":GOAL,"max_seconds":max_seconds}

func _execute() -> void:
	initial = session.store.snapshot()
	if not _check(SourceBinding.start_matches(_source_binding,initial),"unchanged exact initial generation and binding"): _finish("source_save_refused"); return
	var verified: Dictionary = _source_check(initial)
	if not _check(verified.ok and session.profile_ready and not session.active, "same verified nine-goal F1 save before normal menu start", verified): _finish("source_save_refused"); return
	previous_completed = SOURCE_GOALS.duplicate()
	if not _check(not OS.has_feature("editor"), "actual exported application continuation"): _finish("exported_exe_required"); return
	_phase("ordinary_menu_resume_existing_F1")
	session._ui_action("solo", {"frame":0})
	await _next()
	if not _healthy() or not _check(session.region_id == "F1" and session.story.state.get("completed", []) == SOURCE_GOALS, "normal menu restores F1 and exact natural source receipts", _status()): _finish("source_F1_resume_failed"); return
	_bind_pilot() # Holds the observed normal spawn; never restores the prior QA's aircraft position.
	var nursery: Variant = _inspection_goal("F1:dry_nursery", Vector3(-18.5,3.3,31), true)
	if nursery == null or not await _navigate([nursery], "dry_nursery"): _finish("nursery_approach_blocked"); return
	if not await _contact("F1:dry_nursery", "F1:needs:nursery"): _finish("nursery_not_read"); return
	if not await _navigate([Vector3(13,7.0,32), Vector3(13,4.7,32)], "east_nursery_landing"): _finish("east_nursery_route_blocked"); return
	if not await _wait_objective("F1:needs:route", 5.0): _finish("east_nursery_arrival_not_observed"); return
	var atai: Variant = _inspection_goal("npc:atai", Vector3(-27.2,2.7,31), true)
	if atai == null or not await _navigate([Vector3(-27.2,7.5,32), atai], "return_for_repair_plan"): _finish("atai_return_route_blocked"); return
	if not await _contact("npc:atai", "F1:repair:plan"): _finish("repair_plan_not_heard"); return
	if not await _navigate([Vector3(-24,5.2,29)], "real_ring_controls"): _finish("ring_approach_blocked"); return
	_phase("actual_ring_light_rotation")
	if not await _ability("light", "F1:mirror") or not await _ability("light", "F1:mirror"): _finish("ring_action_refused"); return
	if not await _wait_objective("F1:repair:light", 6.0): _finish("actual_optical_fact_missing"); return
	if not _check(float(session.entities["F1:growth"].get("environment_light", 0.0)) >= 1.0 and absf(float(session.world.rotor_angle)) < 0.02 and absf(float(session.entities["F1:mirror"].angle)) < 0.001, "real smoothed ring and unobstructed original ray illuminate the receiver", {"rotor":session.world.rotor_angle,"mirror":session.entities["F1:mirror"],"receiver":session.entities["F1:growth"]}): _finish("physical_light_not_aligned"); return
	if not await _navigate([Vector3(-18,6.4,29)], "illuminated_growth_controls"): _finish("growth_approach_blocked"); return
	if not await _ability("growth", "F1:growth") or not await _ability("growth", "F1:growth"): _finish("growth_action_refused"); return
	if not await _wait_objective("F1:repair:grow", 5.0): _finish("real_bridge_fact_missing"); return
	if not _check(_bridge_collision(), "three original downward rays first-hit the actual grown bridge", {"layer":session.world.growth_bridge.collision_layer,"growth":session.entities["F1:growth"]}): _finish("grown_bridge_collision_missing"); return
	var junction: Variant = _inspection_goal("F1:shared_junction", Vector3(26.9,5.0,32), true)
	if junction == null or not await _navigate([Vector3(-16,9.8,32), Vector3(26.5,9.8,32), junction], "east_shared_junction"): _finish("junction_route_blocked"); return
	if not await _contact("F1:shared_junction", "F1:repair:confirm"): _finish("repair_not_confirmed"); return
	_phase("real_beacon_takeover_and_gate_submission")
	if not await _ability("takeover", "F1:beacon"): _finish("beacon_takeover_refused"); return
	var gate_deadline: float = _elapsed() + 5.0
	while _healthy() and (not session.world.gate_open or session.world.gate_fraction < 0.95) and _elapsed() < gate_deadline: await _next()
	if not _check(session.world.gate_open and session.world.gate_fraction >= 0.95 and session.entities["F1:beacon"].get("controlled", false), "actual controlled beacon fully opens the original seal", _status()): _finish("F1_seal_not_open"); return
	session._ui_action("interact", {})
	await _next()
	if not _check(session.world.restored_gate and session.store.snapshot().world.flags.get("F1_gate", false), "original nearby gate button durably unlocks the F1 return route", _status()): _finish("F1_gate_submission_failed"); return
	if not await _dismiss_radio(): _finish("radio_did_not_close"); return
	_phase("ordinary_travel_back_to_I1")
	if not _check(session._can_travel_to("I1"), "normal return travel is available only after actual repair/submission"): _finish("return_travel_locked"); return
	pilot = null
	session._ui_action("travel_to", {"region_id":"I1"})
	var travel_deadline: float = _elapsed() + 8.0
	while _healthy() and session.region_id != "I1" and _elapsed() < travel_deadline: await _next()
	if not _check(_healthy() and session.region_id == "I1" and "F1:repair" in session.story.state.get("completed_actions", []), "original proposal/Store returns to I1 with natural F1 repair", _status()): _finish("ordinary_return_travel_failed"); return
	_bind_pilot()
	var brief: Variant = _inspection_goal("I1:whale_briefing", Vector3(-9,6.2,-14.5), true)
	if brief == null or not await _navigate([Vector3(-16,11.8,32), Vector3(-16,11.8,-14.5), brief], "north_port_briefing"): _finish("north_port_route_blocked"); return
	if not _check(not session.boss_active, "normal approach remains outside whale engagement before real brief", _status()): _finish("premature_boss_start"); return
	if not await _contact("I1:whale_briefing", "I1:whale:brief"): _finish("whale_brief_not_committed"); return
	if not _check(not session.boss_active, "actual G briefing alone does not start the whale", _status()): _finish("brief_started_boss_early"); return
	var centre: Vector3 = session.world.boss_position
	var entry: Vector3 = centre + Vector3(0,4,17)
	if not await _navigate([Vector3(-9,10,-14.5), entry], "real_whale_engagement"): _finish("whale_entry_route_blocked"); return
	if not await _wait_objective(GOAL, 5.0): _finish("physical_engagement_not_observed"); return
	if not _check(session.boss_active and session.boss_campaign and not session.encounter.get_state().get("completed", false) and _body().global_position.distance_to(centre) <= 18.0 and int(session.stats.shots) == 0, "only ordinary proximity starts the genuine campaign encounter; no combat completion", {"encounter":session.encounter.get_state(),"status":_status()}): _finish("actual_whale_engage_not_present"); return
	if not await _save_and_readback(): _finish("engage_save_or_readback_failed"); return
	if not _check(session.story.state.get("completed", []) == EXPECTED and _source_receipts_digest(session.story.state) == SOURCE_RECEIPTS_SHA256 and not session.store.snapshot().world.flags.get("I1_boss", false) and not session.store.snapshot().world.flags.get("campaign_whale_v1", false), "exact original nine plus eight actual continuation goals, without a Boss victory", _status()): _finish("unexpected_progression"); return
	_finish("F1_continuation_complete")

static func _source_receipts_digest(state: Dictionary) -> String:
	var rows: Dictionary = {}
	var receipts: Variant = state.get("receipts", {})
	if not receipts is Dictionary: return ""
	for event_id: Variant in receipts:
		var receipt: Variant = receipts[event_id]
		if not event_id is String or not receipt is Dictionary: return ""
		if receipt.get("objective_id") in SOURCE_GOALS: rows[str(event_id)] = receipt.duplicate(true)
	return JSON.stringify(rows, "", true, true).sha256_text()

static func _source_check(saved: Dictionary) -> Dictionary:
	if not SourceBinding.same_identity(_source_binding,saved):
		return {"ok":false,"code":"verified_source_identity_or_generation_mismatch"}
	var world: Variant = saved.get("world", {})
	if not world is Dictionary or int(saved.get("generation", 0)) <= 1 or world.get("region_id") != "F1": return {"ok":false,"code":"existing_F1_save_required"}
	var actions: Variant = world.get("actions", {})
	if not actions is Dictionary or not actions.get("opening") is Dictionary or not world.get("flags") is Dictionary: return {"ok":false,"code":"source_story_or_flags_schema"}
	var state: Dictionary = actions.opening
	if not state.get("receipts") is Dictionary: return {"ok":false,"code":"source_receipts_schema"}
	if state.get("completed", []) != SOURCE_GOALS or saved.world.get("completed_objectives", []) != SOURCE_GOALS or state.get("completed_actions", []) != ["I1:rescue", "I1:evidence"] or state.get("receipts", {}).size() != SOURCE_GOALS.size(): return {"ok":false,"code":"exactly_the_nine_natural_source_goals_required"}
	var flags: Dictionary = saved.world.get("flags", {})
	if not flags.get("I1_gate", false) or flags.get("F1_gate", false) or flags.get("I1_boss", false) or flags.get("campaign_whale_v1", false) or flags.get("F1_boss", false) or flags.get("campaign_crown_v1", false): return {"ok":false,"code":"source_gate_or_boss_history_mismatch"}
	if _source_receipts_digest(state) != SOURCE_RECEIPTS_SHA256: return {"ok":false,"code":"actual_first_segment_receipts_mismatch"}
	var director = Director.new()
	var definitions: Dictionary = director.load_definitions(Director.DEFAULT_PATH, Catalog.extension_paths())
	if not definitions.get("ok", false): return {"ok":false,"code":"original_director_definitions_unavailable"}
	var valid: Dictionary = director.validate_state(state)
	if not valid.get("ok", false): return {"ok":false,"code":"source_director_replay_rejected"}
	return {"ok":true,"code":"verified_same_natural_nine_goal_source","generation":saved.generation,"completed":state.completed,"source_report_sha256":SOURCE_REPORT_SHA256}

func _ability(ability: String, target: String, mode: String = "") -> bool:
	_phase("ability:" + ability + ":" + target)
	var deadline: float = _elapsed() + 2.0
	while _healthy() and float(session.cooldowns.get(1, 0.0)) > 0.0 and _elapsed() < deadline: await _next()
	if not _healthy(): return false
	session.network.send_action("lock", {"target_id":target})
	var before: int = int(session.stats.abilities)
	session.network.send_action("ability", {"ability":ability,"target_id":target,"mode":mode})
	var settle: float = _elapsed() + 0.65
	while _healthy() and _elapsed() < settle: await _next()
	return _check(int(session.stats.abilities) == before + 1, "original Rules accepts " + ability + " on actual " + target, {"entity":session.entities.get(target, {}),"status":_status()})

func _bridge_collision() -> bool:
	var bridge: StaticBody3D = session.world.growth_bridge
	if not is_instance_valid(bridge) or (bridge.collision_layer & 1) == 0 or not bridge.visible: return false
	for offset: float in [-4.0, 0.0, 4.0]:
		var at: Vector3 = bridge.global_position + Vector3(offset,2,0)
		var query := PhysicsRayQueryParameters3D.create(at, at + Vector3.DOWN * 3.0, 1 | 8)
		var hit: Dictionary = bridge.get_world_3d().direct_space_state.intersect_ray(query)
		if hit.is_empty() or hit.get("rid") != bridge.get_rid(): return false
	return true

func _physics_process(delta: float) -> void:
	if not running or finished or not is_instance_valid(session) or not session.active: return
	physics_frames += 1
	if session.players.has(1):
		var body: FlightBodyV2 = session.players[1]
		if last_body_id == body.get_instance_id() and last_region == session.region_id:
			var moved: float = last_position.distance_to(body.global_position)
			actual_distance += moved
			max_frame_distance = maxf(max_frame_distance, moved)
		last_body_id = body.get_instance_id()
		last_region = session.region_id
		last_position = body.global_position
	if pilot != null and not session.simulation_paused: pilot.tick(delta, true, false)

func _process(_delta: float) -> void:
	if not running or finished: return
	if _elapsed() >= max_seconds: _finish("wall_deadline_incomplete"); return
	if _elapsed() - last_heartbeat >= 10.0:
		last_heartbeat = _elapsed()
		var row: Dictionary = {"seconds":_elapsed(),"phase":phase,"status":_status()}
		samples.append(row)
		print("NORMAL_F1_PROGRESS " + JSON.stringify(_plain(row)))
	if not logger.errors.is_empty(): _finish("engine_error")

func _bind_pilot() -> void:
	pilot = Pilot.new()
	if not pilot.bind(_body()): failures.append("original_pilot_bind_failed"); return
	command_serial = 0
	command_serial += 1
	pilot.go_to(_body().global_position, command_serial) # Only a hold COMMAND at its observed position.

func _navigate(points: Array, label: String) -> bool:
	_phase("flight:" + label)
	for value: Variant in points:
		if not _healthy() or not value is Vector3: return false
		var goal: Vector3 = value
		if not _hull_clear(goal):
			return _check(false, "authored observation waypoint has real clearance: " + label, {"goal":goal,"status":_status(),"classification":"driver_waypoint_occupied_not_proof_all_routes_fail"})
		command_serial += 1
		if not pilot.go_to(goal, command_serial): return _check(false, "original Pilot accepts bounded waypoint: " + label, {"goal":goal})
		var distance: float = _body().global_position.distance_to(goal)
		var deadline: float = minf(max_seconds, _elapsed() + maxf(16.0, distance / 0.65 + 10.0))
		var last_progress: float = _elapsed()
		var best_distance: float = distance
		while _healthy() and _elapsed() < deadline:
			await _next()
			if not _healthy(): return false
			distance = _body().global_position.distance_to(goal)
			if distance < 0.4 and _body().linear_velocity.length() < 0.35: break
			if distance < best_distance - 0.12:
				best_distance = distance
				last_progress = _elapsed()
			if _elapsed() - last_progress > 10.0:
				return _check(false, "normal Pilot route makes physical progress: " + label, {"goal":goal,"remaining_m":distance,"pilot":pilot.report(),"status":_status(),"classification":"driver_route_stalled_not_proof_campaign_impossible"})
		if not _healthy() or not _check(distance < 0.4 and _body().linear_velocity.length() < 0.35, "continuous original Flight reaches " + label, {"goal":goal,"position":_body().global_position,"speed":_body().linear_velocity.length(),"pilot":pilot.report()}): return false
	return true

func _contact(target: String, objective: String) -> bool:
	_phase("G:" + target)
	if not await _dismiss_radio(): return false
	var deadline: float = minf(max_seconds, _elapsed() + 7.0)
	var next_press := 0.0
	while _healthy() and _elapsed() < deadline and objective not in session.story.state.get("completed", []):
		var nearest: String = session.story.nearest(_body().global_position)
		if not _check(nearest == target, "normal nearest G selects intended contact", {"expected":target,"nearest":nearest,"status":_status()}): return false
		if _elapsed() >= next_press:
			_press_g()
			next_press = _elapsed() + 0.6
		await _next()
	if not _check(objective in session.story.state.get("completed", []), "normal G actually commits " + objective, _status()): return false
	return await _dismiss_radio()

func _wait_objective(id: String, seconds: float) -> bool:
	_phase("observe:" + id)
	var deadline: float = minf(max_seconds, _elapsed() + seconds)
	while _healthy() and id not in session.story.state.get("completed", []) and _elapsed() < deadline: await _next()
	return _check(id in session.story.state.get("completed", []), "original Story observes and commits " + id, _status())

func _dismiss_radio() -> bool:
	var deadline: float = minf(max_seconds, _elapsed() + 8.0)
	var next_press := 0.0
	while _healthy() and session.interface.radio.visible and _elapsed() < deadline:
		if _elapsed() >= next_press:
			_press_g()
			next_press = _elapsed() + 0.28
		await _next()
	return not session.interface.radio.visible and _healthy()

func _press_g() -> void:
	var key := InputEventKey.new()
	key.pressed = true
	key.physical_keycode = KEY_G
	key.keycode = KEY_G
	session._unhandled_input(key) # Original dialogue/nearest/LOS/Store dispatch.

func _inspection_goal(id: String, preferred: Vector3, require_los: bool) -> Variant:
	var marker: Dictionary = session.story.markers.get(id, {})
	if marker.is_empty(): _check(false, "authored marker exists: " + id); return null
	var point: Vector3 = session.story._point(marker)
	var candidates: Array = [preferred, point + Vector3(0,1.2,0), point + Vector3(1.4,1.2,0), point + Vector3(-1.4,1.2,0), point + Vector3(0,1.2,1.4), point + Vector3(0,1.2,-1.4)]
	var collider: String = "F1:beacon" if id == "F1:shared_junction" else id
	for candidate: Vector3 in candidates:
		if candidate.distance_to(point) >= float(marker.radius) - 0.15 or not _hull_clear(candidate): continue
		if require_los and not session._line_clear(candidate, point, _body().get_rid(), collider): continue
		return candidate
	_check(false, "nearby inspection approach has actual hull clearance and LOS: " + id, {"point":point,"candidates":candidates,"classification":"bounded_driver_approaches_unavailable_other_routes_not_tested"})
	return null

func _hull_clear(point: Vector3) -> bool:
	var body: FlightBodyV2 = _body()
	var shape := BoxShape3D.new()
	shape.size = Vector3(float(body.stats.width_m),float(body.stats.height_m),float(body.stats.length_m)) + Vector3.ONE * 0.38
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = shape
	query.transform = Transform3D(Basis.IDENTITY, point)
	query.collision_mask = MASK
	query.exclude = [body.get_rid()]
	return session.world.get_world_3d().direct_space_state.intersect_shape(query, 1).is_empty()

func _save_and_readback() -> bool:
	_phase("original_SaveGate_and_fresh_reader")
	var deadline: float = minf(max_seconds, _elapsed() + 8.0)
	while _healthy() and session.environment_save_gate.pending() and _elapsed() < deadline: await _next()
	if not _healthy() or session.environment_save_gate.pending(): return false
	var requested: Dictionary = session.request_environment_save(func(row: Dictionary): save_callbacks.append(row.duplicate(true)))
	if not _check(requested.get("ok", false), "original asynchronous save request accepted", requested): return false
	while _healthy() and save_callbacks.is_empty() and _elapsed() < deadline: await _next()
	if not _check(not save_callbacks.is_empty() and save_callbacks[-1].get("ok", false) and save_callbacks[-1].get("completed", false), "original physical SaveGate and Store complete", save_callbacks): return false
	var reader = Store.new(session.store.root_path)
	var loaded: Dictionary = reader.load_profile()
	final_reader = {"loaded":loaded,"generation":reader.snapshot().generation,"world":reader.snapshot().world}
	final_reader.merge({"profile_id":reader.snapshot().profile_id,"lineage_id":reader.snapshot().lineage_id,"prefix_validation":session.story.director.validate_state(reader.snapshot().world.get("actions",{}).get("opening",{}))})
	return _check(loaded.get("ok", false) and reader.snapshot().world.region_id == "I1" and session.store.matches_persisted_value(session.story.state, reader.snapshot().world.get("actions", {}).get("opening", {})) and session.story.director.validate_state(reader.snapshot().world.get("actions", {}).get("opening", {})).get("ok", false), "independent original reader replays the actual Story state and I1 location", {"load":loaded,"completed":reader.snapshot().world.get("actions", {}).get("opening", {}).get("completed", [])})

func _next() -> void:
	await get_tree().physics_frame
	await get_tree().process_frame
	if finished: return
	var now: Array = session.story.state.get("completed", [])
	if now != previous_completed:
		var added: Array = []
		for id: String in now:
			if id not in previous_completed: added.append(id)
		events.append({"kind":"observed_original_completion","seconds":_elapsed(),"physics_frame":Engine.get_physics_frames(),"added":added,"status":_status()})
		previous_completed = now.duplicate()
		print("NORMAL_F1_COMPLETION " + JSON.stringify(_plain(events[-1])))

func _body() -> FlightBodyV2:
	return session.players[1]

func _healthy() -> bool:
	return running and not finished and failures.is_empty() and logger.errors.is_empty() and is_instance_valid(session) and session.active and session.network.mode == "solo" and session.players.has(1) and session.players[1].enabled and not session.simulation_paused and session.world.build_errors.is_empty()

func _phase(value: String) -> void:
	phase = value
	events.append({"kind":"phase","phase":phase,"seconds":_elapsed(),"physics_frame":Engine.get_physics_frames(),"status":_status()})
	print("NORMAL_F1_PHASE " + JSON.stringify(_plain(events[-1])))

func _status() -> Dictionary:
	if not is_instance_valid(session): return {"session_valid":false}
	var result: Dictionary = {"region":session.region_id,"active":session.active,"paused":session.simulation_paused,"profile_root":session.store.root_path,"completed":session.story.state.get("completed", []).duplicate(),"completed_actions":session.story.state.get("completed_actions", []).duplicate(),"story_targets":session.story.current_targets(),"boss_active":session.boss_active,"message":session.interface.message.text,"last_commit":session.last_commit_result,"pending_proposal":session.consensus.current_proposal()}
	if is_instance_valid(session.world):
		result["gate_open"] = session.world.gate_open
		result["gate_fraction"] = session.world.gate_fraction
		result["gate_saved"] = session.world.restored_gate
		result["build_errors"] = session.world.build_errors.duplicate()
	if session.players.has(1):
		var body: FlightBodyV2 = _body()
		result["position"] = body.global_position
		result["velocity"] = body.linear_velocity
		result["health"] = body.health
		result["enabled"] = body.enabled
		result["collision_count"] = body.collision_count
		result["water_contact"] = body.water_contact
		result["nearest_G"] = session.story.nearest(body.global_position)
	return result

func _check(ok: bool, label: String, actual: Variant = null) -> bool:
	checks.append({"passed":ok,"label":label,"actual":_plain(actual)})
	if not ok: failures.append(label)
	return ok

func _elapsed() -> float:
	return float(Time.get_ticks_usec() - started_usec) / 1000000.0

func _finish(reason: String) -> void:
	if finished: return
	finished = true
	running = false
	var passed: bool = reason == "F1_continuation_complete" and failures.is_empty() and logger.errors.is_empty()
	var source_audit: Dictionary = SourceBinding.completion_audit(session,initial,final_reader,save_callbacks,EXPECTED)
	passed = passed and source_audit.preservation.values().all(func(value: Variant): return value == true)
	var report: Dictionary = {"complete":passed,"f1_segment_complete":passed,"stop_reason":reason,"phase":phase,"goal":GOAL,"seconds":_elapsed(),"max_seconds":max_seconds,"profile":profile,"user_dir":OS.get_user_data_dir(),"executable":OS.get_executable_path(),"exported_application":not OS.has_feature("editor"),"physics_frames":physics_frames,"first_physics_frame":started_frame,"last_physics_frame":Engine.get_physics_frames(),"actual_distance_m":actual_distance,"max_frame_distance_m_excluding_normal_region_reset":max_frame_distance,"checks":checks,"failures":failures,"engine_errors":logger.errors,"events":events,"ten_second_samples":samples,"save_callbacks":save_callbacks,"fresh_reader":final_reader,"status":_status(),"pilot":pilot.report() if pilot != null and is_instance_valid(pilot.body) else {},"story_receipts":session.story.state.get("receipts", {}),"stats":session.stats,"scope":"Continuation of the exact real nine-goal QA profile, ordinary menu F1 restore, needs/repair physical light/growth/bridge rays, actual beacon takeover and gate submission, normal I1 return, real whale briefing and proximity engagement, original SaveGate/fresh reader. No source receipt/Director/proof/Store/flags/pose/delta/health edits or manual simulation. Boss victory, resumable encounter state, all regions, LAN, controller, performance and human fun remain outside this segment. Route failure is a bounded driver failure, not proof all player routes are impossible."}
	report.merge(source_audit)
	report.merge(SourceBinding.audit(_source_binding))
	report["source_profile"] = SOURCE_PROFILE
	report["source_report_sha256"] = SOURCE_REPORT_SHA256
	report["source_receipts_sha256"] = SOURCE_RECEIPTS_SHA256
	report["source_generation"] = initial.get("generation", -1)
	report["new_completed"] = session.story.state.get("completed", []).filter(func(id: String): return id not in SOURCE_GOALS)
	if not passed and failures.is_empty(): report["incomplete_reason"] = reason
	report["runtime_cwd"] = DirAccess.open(".").get_current_dir()
	if passed: report["native_exit"] = {"through":"session._quit","requested":true,"observed_scene_exit":false,"watchdog_failed":false}
	var file := FileAccess.open(output, FileAccess.WRITE)
	var written: bool = file != null
	if file != null:
		file.store_string(JSON.stringify(_plain(report), "\t", true, true))
		file.flush()
		written = file.get_error() == OK
	print("NORMAL_F1_RESULT " + JSON.stringify({"complete":passed,"written":written,"stop_reason":reason,"phase":phase,"seconds":_elapsed(),"completed":session.story.state.get("completed", []),"failures":failures,"engine_errors":logger.errors}))
	if passed and written:
		_success_exit_report = _plain(report)
		_success_exit_watchdog.call_deferred(Time.get_ticks_usec() + 8000000)
		session._quit()
		return
	get_tree().quit(0 if passed and written else 1)

func _flush_success_exit_report() -> void:
	var file := FileAccess.open(output, FileAccess.WRITE)
	if file == null: return
	file.store_string(JSON.stringify(_success_exit_report, "\t", true, true))
	file.flush()

func _success_exit_watchdog(deadline: int) -> void:
	while is_inside_tree() and Time.get_ticks_usec() < deadline:
		await get_tree().process_frame
	if _success_exit_report.is_empty() or _success_exit_report.native_exit.observed_scene_exit: return
	_success_exit_report["complete"] = false
	_success_exit_report["f1_segment_complete"] = false
	_success_exit_report["stop_reason"] = "production_exit_not_completed_within_eight_seconds"
	_success_exit_report["native_exit"]["watchdog_failed"] = true
	if is_instance_valid(session):
		_success_exit_report["native_exit"]["gate_pending"] = session.environment_save_gate.pending()
		_success_exit_report["native_exit"]["gate_result"] = _plain(session.environment_save_gate.last_result)
		_success_exit_report["native_exit"]["last_commit"] = _plain(session.last_commit_result)
	_success_exit_report["failures"].append("Production exit refused or remained pending; Store was not bypassed.")
	_flush_success_exit_report()
	print("NORMAL_F1_EXIT_WATCHDOG_FAIL " + JSON.stringify(_success_exit_report.native_exit))
	# No forced quit around a refused Store gate; the original runner Job is bounded.

func _exit_tree() -> void:
	if _success_exit_report.is_empty(): return
	_success_exit_report["native_exit"]["observed_scene_exit"] = true
	var audio: Dictionary = session.last_audio_shutdown_result if is_instance_valid(session) else {}
	_success_exit_report["native_exit"]["audio"] = _plain(audio)
	_success_exit_report["engine_errors"] = _plain(logger.errors)
	if not audio.get("ready", false) or not logger.errors.is_empty():
		_success_exit_report["complete"] = false
		_success_exit_report["f1_segment_complete"] = false
		_success_exit_report["failures"].append("Original final-exit audio drain or engine-error gate failed.")
	_flush_success_exit_report()

static func _plain(value: Variant) -> Variant:
	if value is Vector3: return [value.x,value.y,value.z]
	if value is Array:
		var rows: Array = []
		for item: Variant in value: rows.append(_plain(item))
		return rows
	if value is Dictionary:
		var result: Dictionary = {}
		for key: Variant in value: result[str(key)] = _plain(value[key])
		return result
	if value is Object or value is RID: return str(value)
	return value
