extends Node
const SourceBinding = preload("res://scripts/v3/qa/twin_source_binding.gd")
## Exported MAIN observer. No fixture progress, pose placement, manual solver
## ticks, retries/respawns, changed clock, or alternate Rules/Store writer.
const Pilot = preload("res://scripts/v3/gameplay/canal/canal_transport_physics/transport_pilot.gd")
const Store = preload("res://scripts/v3/core/twin_world_store.gd")
const GOAL := "F1:needs:listen"
const EXPECTED := ["I1:rescue:brief", "I1:rescue:channel", "I1:rescue:contact", "I1:rescue:evacuate", "I1:evidence:trace", "I1:evidence:engineer", "I1:evidence:ledger", "I1:evidence:echo", GOAL]
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
	var values: Dictionary = {}
	for argument: String in args:
		var key := ""
		var value := ""
		if argument == "--qa-normal-campaign":
			key = "enabled"
			value = "true"
		else:
			for pair: Array in [["--qa-profile=", "profile"], ["--qa-normal-output=", "output"], ["--qa-normal-seconds=", "seconds"]]:
				if argument.begins_with(str(pair[0])):
					key = str(pair[1])
					value = argument.trim_prefix(str(pair[0]))
					break
		if key.is_empty(): return {"ok":false,"code":"unknown_or_missing_normal_campaign_cli_value","config":{}}
		if values.has(key): return {"ok":false,"code":"duplicate_normal_campaign_cli","config":{}}
		if value.is_empty(): return {"ok":false,"code":"empty_normal_campaign_cli_value","config":{}}
		values[key] = value
	if values.size() != 4: return {"ok":false,"code":"all_four_normal_campaign_arguments_required","config":{}}
	var selected_profile: String = str(values.profile)
	if not selected_profile.begins_with("qa_normal_campaign_") or selected_profile.length() <= "qa_normal_campaign_".length() or selected_profile.length() > 96 or selected_profile != selected_profile.validate_filename():
		return {"ok":false,"code":"dedicated_normal_campaign_profile_required","config":{}}
	if DirAccess.dir_exists_absolute("user://profiles_v3/" + selected_profile): return {"ok":false,"code":"existing_normal_campaign_profile_refused","config":{}}
	var selected_output: String = str(values.output).replace("\\", "/")
	if not selected_output.is_absolute_path() or "://" in selected_output or ".." in selected_output or "\n" in selected_output or "\r" in selected_output or not selected_output.get_file().begins_with("normal-campaign-") or selected_output.get_extension() != "json" or FileAccess.file_exists(selected_output) or DirAccess.dir_exists_absolute(selected_output):
		return {"ok":false,"code":"new_absolute_normal_campaign_json_required","config":{}}
	var selected_seconds: String = str(values.seconds)
	if not selected_seconds.is_valid_int() or str(selected_seconds.to_int()) != selected_seconds or selected_seconds.to_int() < 30 or selected_seconds.to_int() > 300:
		return {"ok":false,"code":"normal_campaign_seconds_30_to_300_required","config":{}}
	return {"ok":true,"code":"normal_campaign_preflight_valid","config":{"profile":selected_profile,"output":selected_output,"max_seconds":selected_seconds.to_int()}}

## Root adds this Node to Session, then calls run deferred after Session._ready.
## options = {profile, output: absolute .json, max_seconds: 30..300}.
func run(owner_session: Node, options: Dictionary = {}) -> Dictionary:
	if running or finished: return {"ok":false,"code":"already_started"}
	session = owner_session
	profile = str(options.get("profile", ""))
	output = str(options.get("output", "")).replace("\\", "/")
	max_seconds = float(options.get("max_seconds", 300.0))
	if not is_instance_valid(session) or not profile.begins_with("qa_normal_campaign_") or profile != profile.validate_filename() or not output.is_absolute_path() or ".." in output or not output.get_file().begins_with("normal-campaign-") or output.get_extension() != "json" or FileAccess.file_exists(output) or not is_finite(max_seconds) or max_seconds < 30.0 or max_seconds > 300.0:
		return {"ok":false,"code":"isolated_profile_absolute_new_output_and_bound_required"}
	if not is_inside_tree() or session.store.root_path != "user://profiles_v3/" + profile:
		return {"ok":false,"code":"mounted_normal_session_profile_required"}
	if DirAccess.make_dir_recursive_absolute(output.get_base_dir()) != OK:
		return {"ok":false,"code":"output_directory_unavailable"}
	OS.add_logger(logger)
	started_usec = Time.get_ticks_usec()
	started_frame = Engine.get_physics_frames()
	process_mode = Node.PROCESS_MODE_ALWAYS
	process_physics_priority = 10 # After normal Session input; before Flight integration.
	running = true
	set_process(true)
	set_physics_process(true)
	_execute.call_deferred()
	return {"ok":true,"code":"observing_real_new_game","goal":GOAL,"max_seconds":max_seconds}

func _execute() -> void:
	initial = session.store.snapshot()
	var opening: Dictionary = initial.world.get("actions", {}).get("opening", {})
	var blank: bool = session.profile_ready and not session.active and int(initial.generation) == 1 and initial.world.region_id == "I1" and initial.world.flags.is_empty() and initial.world.completed_objectives.is_empty() and opening.get("completed", []).is_empty() and initial.personal.discoveries.is_empty() and initial.personal.collections.is_empty() and initial.ledger.guest_received.is_empty() and initial.ledger.guest_outbox.is_empty()
	if not _check(blank, "initial profile has only ordinary bootstrap, no previous campaign results", {"generation":initial.generation,"region":initial.world.region_id,"flags":initial.world.flags,"completed":opening.get("completed", []),"discoveries":initial.personal.discoveries}): _finish("nonempty_or_already_running_profile"); return
	if not _check(not OS.has_feature("editor"), "driver is running inside the actual exported application"): _finish("exported_exe_required"); return
	_phase("ordinary_solo_start")
	session._ui_action("solo", {"frame":0}) # Same menu action and original start/load path.
	await _next()
	if not _healthy(): _finish("ordinary_start_failed"); return
	if not _check(session.region_id == "I1" and session.players.size() == 1 and session.story.state.get("completed", []).is_empty(), "normal new game starts I1 at its original spawn", _status()): _finish("not_original_new_game"); return
	_bind_pilot()
	if not await _contact("npc:linlan", "I1:rescue:brief"): _finish("brief_not_completed"); return
	# South/east approach to the real relay, outside the bridge's side wall.
	if not await _navigate([Vector3(-14,3.3,32), Vector3(-13,3.0,22)], "relay_approach"): _finish("relay_route_blocked"); return
	if not await _charge_relay(): _finish("real_charge_or_gate_did_not_open"); return
	if not await _wait_objective("I1:rescue:channel", 5.0): _finish("channel_fact_not_observed"); return
	# Overfly the existing bridge rail before descending towards its real pocket.
	var pocket: Variant = _inspection_goal("I1:rescue_pocket", Vector3(-24,7.2,21.2), false)
	if pocket == null or not await _navigate([Vector3(-16,9.8,22), Vector3(-24,9.8,21.2), pocket], "rescue_pocket"): _finish("pocket_route_blocked"); return
	if not await _wait_objective("I1:rescue:contact", 5.0): _finish("actual_contact_not_observed"); return
	if not await _navigate([Vector3(-24,9.8,21.2), Vector3(-16,9.8,32), Vector3(-20,3.4,32)], "return_to_reception"): _finish("return_route_blocked"); return
	if not await _wait_objective("I1:rescue:evacuate", 5.0): _finish("evacuation_not_observed"); return
	if not await _dismiss_radio(): _finish("radio_did_not_close"); return
	var trace: Variant = _inspection_goal("I1:burn_trace", Vector3(-11,2.6,14), true)
	if trace == null or not await _navigate([Vector3(-11,3.4,32), Vector3(-11,3.4,14), trace], "burn_trace_approach"): _finish("trace_route_blocked"); return
	if not await _contact("I1:burn_trace", "I1:evidence:trace"): _finish("trace_not_read"); return
	var engineer: Variant = _inspection_goal("npc:ruanheng", Vector3(-9,2.6,18), true)
	if engineer == null or not await _navigate([engineer], "engineer_approach"): _finish("engineer_route_blocked"); return
	if not await _contact("npc:ruanheng", "I1:evidence:engineer"): _finish("engineer_not_heard"); return
	var ledger: Variant = _inspection_goal("I1:energy_ledger", Vector3(-21,6.8,25), true)
	if ledger == null or not await _navigate([Vector3(-16,9.8,25), Vector3(-21,9.8,25), ledger], "ledger_approach"): _finish("ledger_route_blocked"); return
	if not await _contact("I1:energy_ledger", "I1:evidence:ledger"): _finish("ledger_not_read"); return
	var echo: Variant = _inspection_goal("I1:beacon_echo", Vector3(26.9,5.0,32), true)
	if echo == null or not await _navigate([Vector3(-16,9.8,32), Vector3(26.5,9.8,32), echo], "beacon_echo_approach"): _finish("beacon_route_blocked"); return
	if not await _contact("I1:beacon_echo", "I1:evidence:echo"): _finish("echo_not_read"); return
	_phase("ordinary_gate_submission")
	if not _check(session.world.gate_open and _body().global_position.distance_to(session.world.objects["I1:beacon"].global_position) <= 7.0, "actual opened gate and nearby physical beacon permit submission", _status()): _finish("gate_submission_conditions_missing"); return
	session._ui_action("interact", {})
	await _next()
	if not _check(session.world.restored_gate and session.store.snapshot().world.flags.get("I1_gate", false), "ordinary gate button durably restores navigation"): _finish("gate_submission_failed"); return
	if not await _dismiss_radio(): _finish("radio_did_not_close"); return
	_phase("ordinary_travel_to_F1")
	if not _check(session._can_travel_to("F1"), "original travel conditions open F1"): _finish("normal_travel_locked"); return
	pilot = null # Do not command the old world's waypoint while normal travel resets it.
	session._ui_action("travel_to", {"region_id":"F1"})
	var travel_deadline: float = _elapsed() + 8.0
	while _healthy() and session.region_id != "F1" and _elapsed() < travel_deadline: await _next()
	if not _check(_healthy() and session.region_id == "F1", "original proposal/Consensus/Store really changes region to F1", _status()): _finish("ordinary_travel_failed"); return
	_bind_pilot() # The Session may recreate/reset its real aircraft during travel.
	var atai: Variant = _inspection_goal("npc:atai", Vector3(-27.2,2.7,31), true)
	if atai == null or not await _navigate([atai], "atai_first_contact"): _finish("atai_route_blocked"); return
	if not await _contact("npc:atai", GOAL): _finish("atai_not_heard"); return
	if not await _save_and_readback(): _finish("final_original_save_failed"); return
	var completed: Array = session.story.state.get("completed", [])
	if not _check(completed == EXPECTED and not session.boss_active and int(session.stats.shots) == 0, "only the nine naturally ordered first-segment goals are complete; no premature Boss", {"completed":completed,"expected":EXPECTED,"stats":session.stats}): _finish("unexpected_progression"); return
	_finish("first_segment_complete")

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
		print("NORMAL_CAMPAIGN_PROGRESS " + JSON.stringify(_plain(row)))
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

func _charge_relay() -> bool:
	_phase("ability:charge_real_relay")
	session.network.send_action("lock", {"target_id":"I1:relay"})
	var attempts := 0
	while _healthy() and float(session.entities["I1:relay"].get("charge", 0.0)) < 40.0 and attempts < 3:
		# Shader compilation can consume wall time without advancing the normal
		# physics cooldown. Observe the real gate before the next input.
		var ready_deadline: float = _elapsed() + 4.0
		while _healthy() and float(session.cooldowns.get(1, 0.0)) > 0.0 and _elapsed() < ready_deadline: await _next()
		if not _check(_healthy() and float(session.cooldowns.get(1, 0.0)) <= 0.0, "native ability cooldown is ready before relay input", _status()): return false
		var before: int = int(session.stats.abilities)
		session.network.send_action("ability", {"ability":"charge","target_id":"I1:relay","mode":"add"})
		attempts += 1
		var until: float = _elapsed() + 0.65
		while _healthy() and _elapsed() < until: await _next()
		if not _check(int(session.stats.abilities) == before + 1, "original Rules accepts actual ranged/LOS relay charge", {"attempt":attempts,"relay":session.entities["I1:relay"],"status":_status()}): return false
	return _check(float(session.entities["I1:relay"].get("charge", 0.0)) >= 40.0 and session.world.gate_open, "real relay state opens the existing physical gate", _status())

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
	var collider: String = "I1:beacon" if id == "I1:beacon_echo" else id
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
	return _check(loaded.get("ok", false) and reader.snapshot().world.region_id == "F1" and session.store.matches_persisted_value(session.story.state, reader.snapshot().world.get("actions", {}).get("opening", {})) and session.story.director.validate_state(reader.snapshot().world.get("actions", {}).get("opening", {})).get("ok", false), "independent original reader replays the actual Story state and F1 location", {"load":loaded,"completed":reader.snapshot().world.get("actions", {}).get("opening", {}).get("completed", [])})

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
		print("NORMAL_CAMPAIGN_COMPLETION " + JSON.stringify(_plain(events[-1])))

func _body() -> FlightBodyV2:
	return session.players[1]

func _healthy() -> bool:
	return running and not finished and failures.is_empty() and logger.errors.is_empty() and is_instance_valid(session) and session.active and session.network.mode == "solo" and session.players.has(1) and session.players[1].enabled and not session.simulation_paused and session.world.build_errors.is_empty()

func _phase(value: String) -> void:
	phase = value
	events.append({"kind":"phase","phase":phase,"seconds":_elapsed(),"physics_frame":Engine.get_physics_frames(),"status":_status()})
	print("NORMAL_CAMPAIGN_PHASE " + JSON.stringify(_plain(events[-1])))

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
	var passed: bool = reason == "first_segment_complete" and failures.is_empty() and logger.errors.is_empty()
	var source_audit: Dictionary = SourceBinding.completion_audit(session,initial,final_reader,save_callbacks,EXPECTED)
	passed = passed and source_audit.preservation.values().all(func(value: Variant): return value == true)
	var report: Dictionary = {"complete":passed,"first_segment_complete":passed,"stop_reason":reason,"phase":phase,"goal":GOAL,"seconds":_elapsed(),"max_seconds":max_seconds,"profile":profile,"user_dir":OS.get_user_data_dir(),"executable":OS.get_executable_path(),"exported_application":not OS.has_feature("editor"),"physics_frames":physics_frames,"first_physics_frame":started_frame,"last_physics_frame":Engine.get_physics_frames(),"actual_distance_m":actual_distance,"max_frame_distance_m_excluding_normal_region_reset":max_frame_distance,"checks":checks,"failures":failures,"engine_errors":logger.errors,"events":events,"ten_second_samples":samples,"save_callbacks":save_callbacks,"fresh_reader":final_reader,"status":_status(),"pilot":pilot.report() if pilot != null and is_instance_valid(pilot.body) else {},"story_receipts":session.story.state.get("receipts", {}),"stats":session.stats,"scope":"Actual initially empty exported MAIN: ordinary I1 briefing, real relay charge, continuous Flight rescue/evacuation/investigation, original gate submission, normal travel and first F1 contact. No Director prefix, flags/knowledge/rewards/Store/proofs/scene pose or body-mode edits; no retries/respawns, altered delta or manual simulation ticks. QA route/automation coverage only: a stalled chosen route does not prove every player route is impossible. First-segment success is not eight-region/Boss/LAN/controller/human comfort/fun or complete-game acceptance. Successful observer exit requests original Session capture/save/audio teardown; failure retains QA termination. This is not native window-close input coverage."}
	report.merge(source_audit)
	if not passed and failures.is_empty(): report["incomplete_reason"] = reason
	report["runtime_cwd"] = DirAccess.open(".").get_current_dir()
	if passed: report["native_exit"] = {"through":"session._quit","requested":true,"observed_scene_exit":false,"watchdog_failed":false}
	var file := FileAccess.open(output, FileAccess.WRITE)
	var written: bool = file != null
	if file != null:
		file.store_string(JSON.stringify(_plain(report), "\t", true, true))
		file.flush()
		written = file.get_error() == OK
	print("NORMAL_CAMPAIGN_RESULT " + JSON.stringify({"complete":passed,"written":written,"stop_reason":reason,"phase":phase,"seconds":_elapsed(),"completed":session.story.state.get("completed", []),"failures":failures,"engine_errors":logger.errors}))
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
	_success_exit_report["first_segment_complete"] = false
	_success_exit_report["stop_reason"] = "production_exit_not_completed_within_eight_seconds"
	_success_exit_report["native_exit"]["watchdog_failed"] = true
	if is_instance_valid(session):
		_success_exit_report["native_exit"]["gate_pending"] = session.environment_save_gate.pending()
		_success_exit_report["native_exit"]["gate_result"] = _plain(session.environment_save_gate.last_result)
		_success_exit_report["native_exit"]["last_commit"] = _plain(session.last_commit_result)
	_success_exit_report["failures"].append("Production exit refused or remained pending; Store was not bypassed.")
	_flush_success_exit_report()
	print("NORMAL_CAMPAIGN_EXIT_WATCHDOG_FAIL " + JSON.stringify(_success_exit_report.native_exit))
	# No forced quit around a refused Store gate; the original runner Job is bounded.

func _exit_tree() -> void:
	if _success_exit_report.is_empty(): return
	_success_exit_report["native_exit"]["observed_scene_exit"] = true
	var audio: Dictionary = session.last_audio_shutdown_result if is_instance_valid(session) else {}
	_success_exit_report["native_exit"]["audio"] = _plain(audio)
	_success_exit_report["engine_errors"] = _plain(logger.errors)
	if not audio.get("ready", false) or not logger.errors.is_empty():
		_success_exit_report["complete"] = false
		_success_exit_report["first_segment_complete"] = false
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
