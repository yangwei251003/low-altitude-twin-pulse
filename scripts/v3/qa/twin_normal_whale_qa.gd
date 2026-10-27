extends Node
const SourceBinding = preload("res://scripts/v3/qa/twin_source_binding.gd")
static var _source_binding: Dictionary = {}
## AUTHORING COPY. Root alone installs the exported-MAIN hook.
## Drives ordinary commands/actions; never installs progress or physical fixtures.
const Pilot = preload("res://scripts/v3/gameplay/canal/canal_transport_physics/transport_pilot.gd")
const Store = preload("res://scripts/v3/core/twin_world_store.gd")
const Director = preload("res://scripts/v3/gameplay/actions/twin_action_director.gd")
const Catalog = preload("res://scripts/v3/campaign/twin_campaign_catalog.gd")
const Rules = preload("res://scripts/v3/gameplay/twin_ability_rules.gd")
static var SOURCE_PROFILE := ""
static var FIRST_NINE_DIGEST := ""
static var SOURCE_REPORT_SHA256 := ""
static var SEVENTEEN_DIGEST := ""
const FIRST_NINE := ["I1:rescue:brief","I1:rescue:channel","I1:rescue:contact","I1:rescue:evacuate","I1:evidence:trace","I1:evidence:engineer","I1:evidence:ledger","I1:evidence:echo","F1:needs:listen"]
const SOURCE_GOALS := ["I1:rescue:brief","I1:rescue:channel","I1:rescue:contact","I1:rescue:evacuate","I1:evidence:trace","I1:evidence:engineer","I1:evidence:ledger","I1:evidence:echo","F1:needs:listen","F1:needs:nursery","F1:needs:route","F1:repair:plan","F1:repair:light","F1:repair:grow","F1:repair:confirm","I1:whale:brief","I1:whale:engage"]
const EXPECTED := ["I1:rescue:brief","I1:rescue:channel","I1:rescue:contact","I1:rescue:evacuate","I1:evidence:trace","I1:evidence:engineer","I1:evidence:ledger","I1:evidence:echo","F1:needs:listen","F1:needs:nursery","F1:needs:route","F1:repair:plan","F1:repair:light","F1:repair:grow","F1:repair:confirm","I1:whale:brief","I1:whale:engage","I1:whale:disable","I1:whale:record"]
const STAGES := ["started", "first_side", "half", "victory", "record"]
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
var pilot: RefCounted
var logger := ErrorLogger.new()
var output := ""
var stop_after := "record"
var max_seconds := 300.0
var started_usec := 0
var running := false
var stopping := false
var finished := false
var phase := "not_started"
var reached_stages: Array[String] = []
var checks: Array = []
var failures: Array[String] = []
var events: Array = []
var samples: Array = []
var save_callbacks: Array = []
var preservation: Dictionary = {}
var initial: Dictionary = {}
var final_reader: Dictionary = {}
var initial_digest := ""
var command_serial := 0
var physics_frames := 0
var actual_distance := 0.0
var previous_position := Vector3.ZERO
var max_frame_distance := 0.0
var last_body_id := 0
var last_heartbeat := 0.0
var last_combat_key := ""
var last_completed: Array = []
var current_attempt := -1
var wanted_fire := false
var managed_fire := false
var managed_brake := false
var decoy_cycle := ""
var core_hits: Array = []
var last_core_health := 120.0
var report_cache: Dictionary = {}
var native_exit_requested := false

## Run BEFORE MAIN/Store creation. Original Store loader only reads an existing
## dedicated profile. A valid partial 17->18->19 prefix may be resumed as-is.
static func preflight(args: PackedStringArray) -> Dictionary:
	_source_binding = {}
	var bound: Dictionary = SourceBinding.prepare(args,"normal-whale",SOURCE_GOALS,EXPECTED)
	if not bound.get("ok",false): return {"ok":false,"code":bound.get("code","source_binding_rejected"),"config":{}}
	_source_binding = bound.binding
	args = bound.args
	SOURCE_PROFILE = str(_source_binding.constants["SOURCE_PROFILE"])
	SOURCE_REPORT_SHA256 = str(_source_binding.constants["SOURCE_REPORT_SHA256"])
	FIRST_NINE_DIGEST = str(_source_binding.constants["FIRST_NINE_DIGEST"])
	SEVENTEEN_DIGEST = str(_source_binding.constants["SEVENTEEN_DIGEST"])
	var values: Dictionary = {}
	for argument: String in args:
		var key := ""
		var value := ""
		if argument == "--qa-normal-whale":
			key = "enabled"
			value = "true"
		else:
			for pair: Array in [["--qa-profile=","profile"],["--qa-normal-output=","output"],["--qa-normal-seconds=","seconds"],["--qa-whale-stop-after=","stage"]]:
				if argument.begins_with(str(pair[0])):
					key = str(pair[1])
					value = argument.trim_prefix(str(pair[0]))
					break
		if key.is_empty() or value.is_empty() or values.has(key): return {"ok":false,"code":"unknown_empty_or_duplicate_whale_cli","config":{}}
		values[key] = value
	for key: String in ["enabled","profile","output","seconds"]:
		if not values.has(key): return {"ok":false,"code":"four_normal_whale_arguments_required","config":{}}
	if values.size() < 4 or values.size() > 5: return {"ok":false,"code":"invalid_whale_argument_count","config":{}}
	if values.profile != SOURCE_PROFILE or not DirAccess.dir_exists_absolute("user://profiles_v3/" + SOURCE_PROFILE): return {"ok":false,"code":"same_existing_natural_profile_required","config":{}}
	var seconds: String = str(values.seconds)
	if not seconds.is_valid_int() or str(seconds.to_int()) != seconds or seconds.to_int() < 30 or seconds.to_int() > 300: return {"ok":false,"code":"whale_seconds_30_to_300_required","config":{}}
	var stage: String = str(values.get("stage","record"))
	if stage not in STAGES: return {"ok":false,"code":"invalid_whale_stop_stage","config":{}}
	var selected_output: String = str(values.output).replace("\\","/")
	if not _output_valid(selected_output): return {"ok":false,"code":"new_absolute_normal_whale_json_required","config":{}}
	var reader = Store.new("user://profiles_v3/" + SOURCE_PROFILE)
	var loaded: Dictionary = reader.load_profile()
	if not loaded.get("ok",false) or loaded.get("recovered",false): return {"ok":false,"code":"unrecovered_original_profile_required","config":{}}
	var saved: Dictionary = reader.snapshot()
	if not SourceBinding.start_matches(_source_binding,saved): return {"ok":false,"code":"verified_initial_source_generation_changed","config":{}}
	var verified: Dictionary = _source_check(saved)
	if not verified.ok: return {"ok":false,"code":verified.code,"config":{}}
	if verified.victory_committed and stage in ["started","first_side","half"]: return {"ok":false,"code":"requested_fight_stage_already_bypassed_by_real_saved_victory","config":{}}
	return {"ok":true,"code":"natural_whale_prefix_verified","config":{"profile":SOURCE_PROFILE,"output":selected_output,"max_seconds":seconds.to_int(),"stop_after":stage,"source_profile_id":saved.profile_id,"source_lineage_id":saved.lineage_id,"source_receipts_sha256":verified.source_receipts_sha256}}

static func _output_valid(path: String) -> bool:
	return path.is_absolute_path() and "://" not in path and ".." not in path and "\n" not in path and "\r" not in path and path.get_file().begins_with("normal-whale-") and path.get_extension() == "json" and not FileAccess.file_exists(path) and not DirAccess.dir_exists_absolute(path)

static func _receipts_digest(state: Dictionary, goals: Array) -> String:
	var rows: Dictionary = {}
	var receipts: Variant = state.get("receipts")
	if not receipts is Dictionary: return ""
	for event_id: Variant in receipts:
		var receipt: Variant = receipts[event_id]
		if not event_id is String or not receipt is Dictionary: return ""
		if receipt.get("objective_id") in goals: rows[str(event_id)] = receipt.duplicate(true)
	if rows.size() != goals.size(): return ""
	return JSON.stringify(rows,"",true,true).sha256_text()

static func _source_check(saved: Dictionary) -> Dictionary:
	if not SourceBinding.same_identity(_source_binding,saved):
		return {"ok":false,"code":"verified_source_identity_mismatch"}
	var world: Variant = saved.get("world")
	if not world is Dictionary or world.get("region_id") != "I1" or world.get("branch_id") != "main": return {"ok":false,"code":"existing_natural_main_branch_I1_required"}
	if not world.get("actions") is Dictionary or not world.actions.get("opening") is Dictionary or not world.get("flags") is Dictionary: return {"ok":false,"code":"source_story_schema"}
	var state: Dictionary = world.actions.opening
	var completed: Variant = state.get("completed")
	if not completed is Array or completed.size() < SOURCE_GOALS.size() or completed.size() > EXPECTED.size(): return {"ok":false,"code":"only_natural_seventeen_to_nineteen_prefix_accepted"}
	if completed != EXPECTED.slice(0,completed.size()) or world.get("completed_objectives") != completed or not state.get("receipts") is Dictionary or state.receipts.size() != completed.size(): return {"ok":false,"code":"exact_natural_prefix_and_receipts_required"}
	if _receipts_digest(state,FIRST_NINE) != FIRST_NINE_DIGEST: return {"ok":false,"code":"verified_first_run_receipts_changed"}
	if _receipts_digest(state,SOURCE_GOALS) != SEVENTEEN_DIGEST: return {"ok":false,"code":"actual_dev33_seventeen_source_receipts_changed"}
	var director = Director.new()
	var definitions: Dictionary = director.load_definitions(Director.DEFAULT_PATH,Catalog.extension_paths())
	if not definitions.get("ok",false): return {"ok":false,"code":"original_director_unavailable"}
	var valid: Dictionary = director.validate_state(state)
	if not valid.get("ok",false): return {"ok":false,"code":"original_director_replay_rejected:"+str(valid.get("code",""))}
	var flags: Dictionary = world.flags
	if not flags.get("I1_gate",false) or not flags.get("F1_gate",false) or flags.get("F1_boss",false) or flags.get("campaign_crown_v1",false): return {"ok":false,"code":"natural_gate_or_later_history_mismatch"}
	var victory: bool = bool(flags.get("I1_boss",false))
	if victory != bool(flags.get("campaign_whale_v1",false)) or completed.size() > 17 and not victory: return {"ok":false,"code":"campaign_victory_prefix_mismatch"}
	if victory:
		var commits: Variant = saved.get("ledger",{}).get("commits")
		if not commits is Dictionary: return {"ok":false,"code":"original_victory_ledger_missing"}
		var found := false
		for receipt: Variant in commits:
			if str(receipt).begins_with("boss:I1:harbor_whale:opening_v1:main:"): found = true
		if not found or saved.get("personal",{}).get("discoveries",[]).count("boss:I1:harbor_whale") != 1: return {"ok":false,"code":"original_campaign_victory_receipt_and_reward_required"}
	return {"ok":true,"code":"natural_prefix_valid","completed":completed.duplicate(),"source_receipts_sha256":_receipts_digest(state,SOURCE_GOALS),"victory_committed":victory}

func run(owner_session: Node, options: Dictionary = {}) -> Dictionary:
	if running or stopping or finished: return {"ok":false,"code":"already_started"}
	session = owner_session
	output = str(options.get("output","")).replace("\\","/")
	max_seconds = float(options.get("max_seconds",300))
	stop_after = str(options.get("stop_after","record"))
	if not is_instance_valid(session) or not is_inside_tree() or options.get("profile") != SOURCE_PROFILE or session.store.root_path != "user://profiles_v3/"+SOURCE_PROFILE or not _output_valid(output) or not is_finite(max_seconds) or max_seconds < 30 or max_seconds > 300 or stop_after not in STAGES: return {"ok":false,"code":"mounted_same_profile_new_output_and_bound_required"}
	initial = session.store.snapshot()
	if not SourceBinding.start_matches(_source_binding,initial): return {"ok":false,"code":"verified_initial_source_generation_changed"}
	var verified: Dictionary = _source_check(initial)
	if not verified.ok: return verified
	initial_digest = str(verified.source_receipts_sha256)
	if options.get("source_profile_id") != initial.profile_id or options.get("source_lineage_id") != initial.lineage_id or options.get("source_receipts_sha256") != initial_digest: return {"ok":false,"code":"preflight_source_identity_or_receipts_changed"}
	if DirAccess.make_dir_recursive_absolute(output.get_base_dir()) != OK: return {"ok":false,"code":"output_directory_unavailable"}
	OS.add_logger(logger)
	started_usec = Time.get_ticks_usec()
	process_mode = Node.PROCESS_MODE_ALWAYS
	process_physics_priority = 10
	running = true
	_execute.call_deferred()
	return {"ok":true,"code":"observing_natural_whale","stop_after":stop_after,"max_seconds":max_seconds}

func _execute() -> void:
	if not _check(session.profile_ready and not session.active and not OS.has_feature("editor"),"actual exported MAIN before ordinary menu continuation"): _stop("exported_normal_menu_required"); return
	last_completed = initial.world.actions.opening.completed.duplicate()
	_phase("ordinary_menu_resume_natural_I1")
	session._ui_action("solo",{"frame":0})
	await _next()
	if not _healthy() or not _check(session.region_id == "I1" and _receipts_digest(session.story.state,SOURCE_GOALS) == initial_digest,"normal menu restores same seventeen receipt history at its real spawn",_status()): _stop("normal_I1_resume_failed"); return
	_bind_pilot()
	if not await _dismiss_radio(): _stop("radio_not_closed"); return
	if session.story.whale_victory_committed():
		if not await _navigate([Vector3(-16,11.8,32),Vector3(-16,11.8,-14.5),Vector3(session.world.boss_position.x,12,-14.5)],"normal_north_after_saved_victory"): _stop("saved_victory_north_route_blocked"); return
	if not session.story.whale_victory_committed():
		if not await _navigate([Vector3(-16,11.8,32),Vector3(-16,11.8,-14.5),Vector3(-9,10,-14.5),session.world.boss_position+Vector3(0,4,17)],"normal_north_engagement"): _stop("north_route_blocked"); return
		if not _check(session.boss_active and session.boss_campaign and _body().global_position.distance_to(session.world.boss_position) <= 18.0,"only ordinary proximity activates the actual campaign whale",_status()): _stop("normal_engagement_missing"); return
		current_attempt = int(session.encounter.get_state().get("attempt",-1))
		if _stage("started"): return
		var port: Vector3 = session.world.boss_parts.port.global_position
		if not await _navigate([Vector3(port.x,12,-18),port+Vector3.UP*5.0],"first_side_overhead"): _stop("first_side_route_blocked"); return
		if not await _close_node("port"): _stop("first_real_side_not_disabled"); return
		if _stage("first_side"): return
		# Isolated real-armor queries found no shared two-side viewpoint. The
		# outboard station below sees starboard and, later, the exposed core.
		# Only actual normal Pilot flight and live first-hit rays can prove it.
		var starboard: Vector3 = session.world.boss_parts.starboard.global_position
		var firing_station: Vector3 = starboard+Vector3(0,3.35,1)
		if not await _navigate([firing_station],"outboard_starboard_and_core_candidate"): _stop("starboard_vantage_route_blocked"); return
		if not await _close_node("starboard"): _stop("second_real_side_not_disabled"); return
		if not await _fire_core(true): _stop("first_real_exposure_incomplete"); return
		var half: Dictionary = session.encounter.get_state()
		if not _check(half.get("overdrive",false) and is_equal_approx(float(half.get("core_health",0)),57.0) and bool(half.nodes.port.powered) and bool(half.nodes.starboard.powered) and not half.get("nodes_open",true),"seven actual nine-damage hits cause native half-health rearm",half): _stop("half_rearm_not_observed"); return
		if _stage("half"): return
		if not await _navigate([port+Vector3.UP*5.0],"overdrive_return_to_port") or not await _close_node("port"): _stop("overdrive_port_not_disabled"); return
		if not await _navigate([firing_station],"overdrive_return_to_starboard") or not await _close_node("starboard"): _stop("overdrive_starboard_not_disabled"); return
		if not await _fire_core(false): _stop("overdrive_real_exposure_incomplete"); return
	var victory_deadline: float = _elapsed()+8.5
	while _healthy() and (session.pending_completion or not session.story.whale_victory_committed() or "I1:whale:disable" not in session.story.state.get("completed",[])) and _elapsed()<victory_deadline: await _next()
	if not _check(_healthy() and not session.pending_completion and not session.boss_active and session.story.whale_victory_committed() and "I1:whale:disable" in session.story.state.get("completed",[]),"original victory Store commit and automatic disable objective finish",_status()): _stop("original_victory_not_durable"); return
	if _stage("victory"): return
	if "I1:whale:record" not in session.story.state.get("completed",[]):
		if not await _dismiss_radio(): _stop("post_victory_radio_not_closed"); return
		var point: Vector3 = session.world.whale_record_position()
		var approach: Variant = _record_approach(point)
		if approach == null or not await _navigate([Vector3(point.x,maxf(point.y+3.0,_body().global_position.y),point.z),approach],"actual_record_anchor"): _stop("record_route_blocked"); return
		if not await _contact_record(): _stop("record_G_not_committed"); return
	if not _check(session.story.state.get("completed",[]) == EXPECTED and _receipts_digest(session.story.state,SOURCE_GOALS) == initial_digest,"exact nineteen natural goals retain every source receipt",_status()): _stop("unexpected_final_prefix"); return
	if not initial.world.flags.get("campaign_whale_v1",false):
		var exact_damage: bool = core_hits.size()==14
		var expected_before := 120.0
		for hit: Dictionary in core_hits:
			var expected_after := maxf(0.0,expected_before-9.0)
			if float(hit.before)!=expected_before or float(hit.after)!=expected_after or float(hit.decrease)!=expected_before-expected_after:
				exact_damage=false
			expected_before=expected_after
		if not _check(exact_damage and expected_before==0.0 and "half" in reached_stages,"fourteen original nine-damage requests remove exactly 120HP, with the final hit clamped at zero and native rearm",core_hits): _stop("actual_damage_evidence_incomplete"); return
	_stage("record")

func _bind_pilot() -> void:
	pilot = Pilot.new()
	if not pilot.bind(_body()): _check(false,"original Pilot binds the actual normal-spawn aircraft"); return
	command_serial += 1
	pilot.go_to(_body().global_position,command_serial)

func _navigate(points: Array, label: String) -> bool:
	_phase("flight:"+label)
	for value: Variant in points:
		if not _healthy() or not value is Vector3: return false
		var goal: Vector3 = value
		if not _hull_clear(goal): return _check(false,"candidate waypoint has actual aircraft clearance",{"label":label,"goal":goal,"classification":"driver_candidate_occupied_not_all_player_routes"})
		command_serial += 1
		if not pilot.go_to(goal,command_serial): return _check(false,"ordinary Pilot accepts waypoint",goal)
		var distance: float = _body().global_position.distance_to(goal)
		var best_distance: float = distance
		var last_progress: float = _elapsed()
		var deadline: float = minf(max_seconds-10.0,_elapsed()+maxf(18.0,distance/.6+12.0))
		while _healthy() and _elapsed()<deadline:
			await _next()
			if not _healthy(): return false
			distance = _body().global_position.distance_to(goal)
			if distance<.4 and _body().linear_velocity.length()<.35: break
			if distance<best_distance-.12:
				best_distance=distance
				last_progress=_elapsed()
			if _elapsed()-last_progress>12.0: return _check(false,"ordinary Pilot makes real route progress",{"label":label,"goal":goal,"pilot":pilot.report(),"status":_status(),"classification":"bounded_driver_route_stall"})
		if not _healthy() or not _check(distance<.4 and _body().linear_velocity.length()<.35,"continuous native flight reaches "+label,{"goal":goal,"position":_body().global_position,"pilot":pilot.report()}): return false
	return true

func _close_node(side: String) -> bool:
	_phase("real_open_hatch_takeover:"+side)
	var target: String = "boss:"+side
	session.network.send_action("lock",{"target_id":target})
	var deadline: float = minf(max_seconds-10.0,_elapsed()+17.0)
	var diagnostics_clock := 0.0
	while _healthy() and session.boss_active and _elapsed()<deadline:
		var state: Dictionary = session.encounter.get_state()
		if not bool(state.nodes[side].powered): return _check(true,"actual "+side+" supply is disabled",state.nodes[side])
		var ray: Dictionary = _ray_to(target)
		var distance: float = _body().global_position.distance_to(session.entities[target].position)
		if state.get("nodes_open",false) and distance<=float(Rules.DEFINITIONS.takeover.range)+0.001 and ray.get("entity_id")==target and float(session.cooldowns.get(1,0))<=0 and float(session.entities["player:1"].get("energy",0))>=18:
			var before: int = int(session.stats.abilities)
			session.network.send_action("ability",{"ability":"takeover","target_id":target})
			_event("ordinary_takeover_intent",{"target":target,"ray":ray,"distance":distance,"accepted":int(session.stats.abilities)==before+1,"state":session.encounter.get_state()})
		if _elapsed()>=diagnostics_clock:
			diagnostics_clock=_elapsed()+2.0
			_event("open_hatch_observation",{"target":target,"ray":ray,"distance":distance,"nodes_open":state.get("nodes_open",false),"remaining":state.get("attack_remaining",0)})
		await _next()
	return _check(false,"live open-hatch range and first-hit ray permit "+side,{"ray":_ray_to(target),"status":_status(),"classification":"candidate_vantage_or_window_unproven"})

func _fire_core(until_half: bool) -> bool:
	_phase("normal_fire_to_half" if until_half else "normal_fire_to_victory")
	session.network.send_action("lock",{"target_id":"boss:core"})
	var deadline: float = minf(max_seconds-10.0,_elapsed()+10.0)
	wanted_fire=true
	while _healthy() and _elapsed()<deadline:
		var state: Dictionary = session.encounter.get_state()
		if until_half and state.get("overdrive",false):
			wanted_fire=false
			_set_fire(false)
			return true
		if state.get("completed",false) or session.story.whale_victory_committed():
			_observe_combat(state)
			wanted_fire=false
			_set_fire(false)
			return not until_half
		if float(state.get("exposed_remaining",0))<=0:
			wanted_fire=false
			_set_fire(false)
			return _check(false,"actual core exposure lasts until required real damage",{"state":state,"ray":_ray_to("boss:core"),"classification":"no_damage_or_transit_window_failure"})
		await _next()
	wanted_fire=false
	_set_fire(false)
	return false

func _physics_process(delta: float) -> void:
	if not running or stopping or not _live() or session.simulation_paused: return
	physics_frames+=1
	var body: FlightBodyV2 = _body()
	if last_body_id==body.get_instance_id():
		var moved: float = previous_position.distance_to(body.global_position)
		actual_distance+=moved
		max_frame_distance=maxf(max_frame_distance,moved)
	last_body_id=body.get_instance_id()
	previous_position=body.global_position
	var state: Dictionary = session.encounter.get_state() if session.boss_active else {}
	_observe_combat(state)
	if stopping: return
	var real_brake: bool = not state.is_empty() and state.get("telegraph")=="tractor" and state.get("attack_state") in ["windup","active"]
	_set_brake(real_brake)
	# No Pilot write while native Space braking: Session's original command must
	# also reach FlightBody, not merely fool the tractor's brake check.
	if not real_brake and pilot!=null: pilot.tick(delta,true,false)
	_prepare_next_warning(state)
	var may_fire: bool = wanted_fire and not state.is_empty() and float(state.get("exposed_remaining",0))>0 and not state.get("completed",false) and str(session.locks.get(1,""))=="boss:core" and _ray_to("boss:core").get("entity_id")=="boss:core"
	_set_fire(may_fire)

func _prepare_next_warning(state: Dictionary) -> void:
	if state.is_empty() or state.get("attack_state")!="recovery" or state.get("telegraph")!="low_sweep" or float(state.get("attack_remaining",2))>1.0: return
	var cycle: String = "%s:%s:%s" % [state.get("attempt"),state.get("overdrive"),last_combat_key]
	# last_combat_key includes changing HP but not remaining time. A successful
	# active decoy also suppresses extra casts for the same imminent warning.
	if decoy_cycle==cycle or float(session.entities["player:1"].get("decoy_remaining",0))>2.6 or float(session.cooldowns.get(1,0))>0 or float(session.entities["player:1"].get("energy",0))<10: return
	var velocity: Vector3 = _body().linear_velocity
	var side: Vector3 = Vector3(-velocity.z,0,velocity.x).normalized() if Vector2(velocity.x,velocity.z).length()>.2 else Vector3.RIGHT
	for direction: Vector3 in [side,-side,Vector3.FORWARD,Vector3.BACK]:
		var point: Vector3 = _body().global_position+direction*6.0
		if not _hull_clear(point) or not session._line_clear(_body().global_position,point,_body().get_rid()): continue
		var before: int = int(session.stats.abilities)
		session.network.send_action("ability",{"ability":"decoy","point":point})
		if int(session.stats.abilities)==before+1:
			decoy_cycle=cycle
			_event("ordinary_decoy_before_next_high_lance",{"point":point,"actual_position":_body().global_position,"actor_decoy":session.entities["player:1"].get("decoy_position"),"remaining":session.entities["player:1"].get("decoy_remaining"),"current_recovery_remaining":state.get("attack_remaining")})
		return

func _observe_combat(state: Dictionary) -> void:
	if state.is_empty(): return
	var attempt: int = int(state.get("attempt",-1))
	if current_attempt<0: current_attempt=attempt
	if attempt!=current_attempt:
		_check(false,"original attempt continues without a native full-wipe reset",{"previous":current_attempt,"actual":attempt,"state":state})
		_stop("actual_attempt_reset")
		return
	var key: String = JSON.stringify([state.get("attempt"),state.get("phase"),state.get("attack_state"),state.get("telegraph"),state.get("nodes_open"),state.get("core_health"),state.get("nodes"),_body().health])
	if key!=last_combat_key:
		last_combat_key=key
		_event("ordinary_combat_transition",{"state":state,"warning_mark":session._boss_target_positions.get(1),"actor_position":_body().global_position,"telemetry_brake_active":_body().telemetry.get("brake_active",false),"native_velocity":_native_velocity(),"shot_counter":session.stats.shots,"core_ray":_ray_to("boss:core"),"port_ray":_ray_to("boss:port"),"starboard_ray":_ray_to("boss:starboard")})
	var health: float = float(state.get("core_health",120))
	if health<last_core_health:
		core_hits.append({"seconds":_elapsed(),"before":last_core_health,"after":health,"decrease":last_core_health-health,"shot_counter":session.stats.shots,"overdrive":state.get("overdrive",false)})
	last_core_health=health

func _process(_delta: float) -> void:
	if not running or finished: return
	if not stopping and _elapsed()>=max_seconds-10.0: _stop("bounded_wall_deadline_incomplete")
	if not stopping and not logger.errors.is_empty(): _stop("engine_error")
	if not stopping and _elapsed()-last_heartbeat>=10.0:
		last_heartbeat=_elapsed()
		var row: Dictionary = {"seconds":_elapsed(),"phase":phase,"status":_status()}
		samples.append(_plain(row))
		print("NORMAL_WHALE_PROGRESS "+JSON.stringify(_plain(row)))

func _ray_to(target: String) -> Dictionary:
	if not _live() or not session.entities.has(target): return {"entity_id":"","code":"target_not_present"}
	var point: Vector3 = session.entities[target].position
	var query := PhysicsRayQueryParameters3D.create(_body().global_position,point,1|8)
	query.exclude=[_body().get_rid()]
	var hit: Dictionary = session.world.get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty(): return {"entity_id":"","code":"no_first_hit","point":point}
	return {"entity_id":str(hit.collider.get_meta("entity_id","")),"collider":str(hit.collider.get_path()),"position":hit.position,"distance":_body().global_position.distance_to(hit.position),"target":target}

func _hull_clear(point: Vector3) -> bool:
	if not _live() or not point.is_finite(): return false
	var body: FlightBodyV2 = _body()
	var shape := BoxShape3D.new()
	shape.size=Vector3(float(body.stats.width_m),float(body.stats.height_m),float(body.stats.length_m))+Vector3.ONE*.38
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape=shape
	query.transform=Transform3D(Basis.IDENTITY,point)
	query.collision_mask=MASK
	query.exclude=[body.get_rid()]
	return session.world.get_world_3d().direct_space_state.intersect_shape(query,1).is_empty()

func _record_approach(point: Vector3) -> Variant:
	for offset: Vector3 in [Vector3(0,2,0),Vector3(1.4,1.7,0),Vector3(-1.4,1.7,0),Vector3(0,1.7,1.4),Vector3(0,1.7,-1.4)]:
		var candidate: Vector3 = point+offset
		if _hull_clear(candidate) and session._line_clear(candidate,point,_body().get_rid(),"boss:core"): return candidate
	_check(false,"bounded record approach candidates have actual hull clearance and LOS",{"point":point,"classification":"other_player_routes_not_tested"})
	return null

func _contact_record() -> bool:
	_phase("normal_G_actual_record")
	var deadline: float = minf(max_seconds-10,_elapsed()+8)
	var next_press := 0.0
	while _healthy() and _elapsed()<deadline and "I1:whale:record" not in session.story.state.get("completed",[]):
		if not _check(session.story.nearest(_body().global_position)=="I1:whale_raw_record","normal nearest G resolves actual record anchor",_status()): return false
		if _elapsed()>=next_press:
			_press_g()
			next_press=_elapsed()+.6
		await _next()
	return _check("I1:whale:record" in session.story.state.get("completed",[]),"original near/LOS G durably extracts raw commands",_status())

func _dismiss_radio() -> bool:
	var deadline: float = minf(max_seconds-10,_elapsed()+8)
	var next_press := 0.0
	while _healthy() and session.interface.radio.visible and _elapsed()<deadline:
		if _elapsed()>=next_press:
			_press_g()
			next_press=_elapsed()+.28
		await _next()
	return _healthy() and not session.interface.radio.visible

func _press_g() -> void:
	var key := InputEventKey.new()
	key.pressed=true
	key.physical_keycode=KEY_G
	key.keycode=KEY_G
	session._unhandled_input(key)

func _set_fire(pressed: bool) -> void:
	if pressed==managed_fire: return
	managed_fire=pressed
	if pressed: Input.action_press("flight_fire")
	else: Input.action_release("flight_fire")

func _set_brake(pressed: bool) -> void:
	if pressed==managed_brake: return
	managed_brake=pressed
	if pressed: Input.action_press("flight_brake")
	else: Input.action_release("flight_brake")

func _stage(value: String) -> bool:
	if value not in reached_stages: reached_stages.append(value)
	_event("actual_stage_observed",{"stage":value,"state":session.encounter.get_state(),"status":_status()})
	if stop_after==value:
		_stop("normal_whale_complete" if value=="record" else "requested_stage_pause")
		return true
	return false

func _stop(reason: String) -> void:
	if stopping or finished: return
	stopping=true
	wanted_fire=false
	_set_fire(false)
	_set_brake(false)
	_preserve_and_report.call_deferred(reason)

func _preserve_and_report(reason: String) -> void:
	var deadline: float = minf(max_seconds+3.0,_elapsed()+9.0)
	# This is an ordinary solo Consensus pause, never a QA freeze or clock edit.
	if _live() and not session.simulation_paused and session.consensus.current_proposal().is_empty():
		session.network.send_action("propose",{"kind":"pause","payload":{}})
		while _live() and not session.simulation_paused and _elapsed()<deadline and session.consensus.current_proposal().get("kind")=="pause": await _next()
	preservation["common_paused"]=_live() and session.simulation_paused
	preservation["proposal"]=session.consensus.current_proposal()
	if _live() and session.consensus.current_proposal().is_empty():
		while session.environment_save_gate.pending() and _elapsed()<deadline: await _next()
		if not session.environment_save_gate.pending():
			var requested: Dictionary = session.request_environment_save(func(row: Dictionary): save_callbacks.append(row.duplicate(true)))
			preservation["request"]=requested
			while save_callbacks.is_empty() and _elapsed()<deadline: await _next()
		preservation["save_callbacks"]=save_callbacks.duplicate(true)
	var reader = Store.new(session.store.root_path)
	var loaded: Dictionary = reader.load_profile()
	var saved: Dictionary = reader.snapshot()
	var valid: Dictionary = _source_check(saved) if loaded.get("ok",false) else {"ok":false,"code":"fresh_reader_load_failed"}
	var preserved: bool = loaded.get("ok",false) and not loaded.get("recovered",false) and valid.get("ok",false) and valid.get("source_receipts_sha256")==initial_digest
	var saved_now: bool = not save_callbacks.is_empty() and save_callbacks[-1].get("ok",false) and save_callbacks[-1].get("completed",false)
	var matches_live: bool = preserved and session.store.matches_persisted_value(session.story.state,saved.world.actions.opening)
	final_reader={"loaded":loaded,"prefix_validation":valid,"generation":saved.get("generation"),"world":saved.get("world"),"personal":saved.get("personal"),"lineage_id":saved.get("lineage_id"),"profile_id":saved.get("profile_id")}
	preservation["original_prefix_preserved"]=preserved
	preservation["current_SaveGate_completed"]=saved_now
	preservation["fresh_Story_matches_live"]=matches_live
	preservation["encounter_resume_supported"]=false
	if not preserved: _check(false,"fresh original reader retains a legal same-source prefix",final_reader)
	if not saved_now: _check(false,"ordinary SaveGate succeeds before bounded QA stop",preservation)
	if saved_now and not matches_live: _check(false,"fresh original reader exactly matches actual live Story",final_reader)
	var complete: bool = reason=="normal_whale_complete" and failures.is_empty() and logger.errors.is_empty() and preserved and saved_now and matches_live and saved.world.actions.opening.completed==EXPECTED
	var stage_stopped: bool = reason=="requested_stage_pause" and stop_after in reached_stages and failures.is_empty() and logger.errors.is_empty() and preserved and saved_now and matches_live and preservation.common_paused
	if complete:
		_check(saved.personal.discoveries.count("boss:I1:harbor_whale")==1 and saved.personal.discoveries.count("opening:whale_raw_command_record")==1,"actual original reward and raw-record discovery are each present exactly once",saved.personal.discoveries)
		complete=failures.is_empty()
	_write_report(reason,complete,stage_stopped)

func _write_report(reason: String, complete: bool, stage_stopped: bool) -> void:
	finished=true
	running=false
	_set_fire(false)
	_set_brake(false)
	var report: Dictionary = {"complete":complete,"whale_segment_complete":complete,"requested_stage_stopped":stage_stopped,"requested_stage":stop_after,"reached_stages":reached_stages,"stop_reason":reason,"phase":phase,"seconds":_elapsed(),"max_seconds":max_seconds,"profile":SOURCE_PROFILE,"user_dir":OS.get_user_data_dir(),"executable":OS.get_executable_path(),"exported_application":not OS.has_feature("editor"),"runtime_cwd":DirAccess.open(".").get_current_dir(),"source_generation":initial.get("generation"),"source_report_sha256":SOURCE_REPORT_SHA256,"source_receipts_sha256":initial_digest,"physics_frames":physics_frames,"actual_distance_m":actual_distance,"max_frame_distance_m":max_frame_distance,"checks":checks,"failures":failures,"engine_errors":logger.errors,"events":events,"ten_second_samples":samples,"core_damage_observations":core_hits,"status":_status(),"preservation":preservation,"fresh_reader":final_reader,"story_receipts":session.story.state.get("receipts",{}),"stats":session.stats,"pilot":pilot.report() if pilot!=null and is_instance_valid(pilot.body) else {},"scope":"Actual exported MAIN continues only the same naturally obtained legal seventeen-to-nineteen objective prefix. Normal spawn, continuous original Pilot/Flight, original lock/ability/fire/brake, real mesh ray/window/half-health rearm, original Store reward, manual record G and SaveGate/fresh reader. No pose, HP, flags, prefix, cooldown, clock or fixture injection. Requested stage pauses and failures are not combat completion. A fresh invocation restarts an unfinished native attempt; no persisted encounter-state claim. No full-campaign, human-fun, LAN, performance or controller acceptance."}
	report.merge(SourceBinding.audit(_source_binding))
	report["native_exit"]={"requested":true,"through":"session._quit","observed_scene_exit":false,"watchdog_failed":false}
	report_cache=_plain(report)
	var written: bool = _flush_report()
	print("NORMAL_WHALE_RESULT "+JSON.stringify({"complete":complete,"requested_stage_stopped":stage_stopped,"written":written,"reason":reason,"phase":phase,"seconds":_elapsed(),"failures":failures,"engine_errors":logger.errors}))
	# Production alone owns the final capture/save and native audio drain.
	# A failed QA result still exits production normally; the runner owns FAIL.
	native_exit_requested=true
	_native_exit_watchdog.call_deferred()
	session._quit()

func _flush_report() -> bool:
	var file := FileAccess.open(output,FileAccess.WRITE)
	if file==null: return false
	file.store_string(JSON.stringify(report_cache,"\t",true,true))
	file.flush()
	return file.get_error()==OK

func _native_exit_watchdog() -> void:
	await get_tree().create_timer(8.0,true,false,true).timeout
	if not native_exit_requested or report_cache.is_empty(): return
	report_cache["complete"]=false
	report_cache["whale_segment_complete"]=false
	report_cache["requested_stage_stopped"]=false
	report_cache["stop_reason"]="production_exit_not_completed_within_eight_seconds"
	report_cache["native_exit"]["watchdog_failed"]=true
	report_cache["native_exit"]["seconds"]=_elapsed()
	if is_instance_valid(session):
		report_cache["native_exit"]["last_commit"]=_plain(session.last_commit_result)
		report_cache["native_exit"]["gate_result"]=_plain(session.environment_save_gate.last_result)
		report_cache["native_exit"]["gate_pending"]=session.environment_save_gate.pending()
		report_cache["native_exit"]["proposal"]=_plain(session.consensus.current_proposal())
		report_cache["native_exit"]["pending_completion"]=session.pending_completion
	report_cache["failures"].append("Production exit refused or remained pending; Store was not bypassed.")
	_flush_report()
	print("NORMAL_WHALE_EXIT_WATCHDOG_FAIL "+JSON.stringify(report_cache.native_exit))
	# Do not use tree.quit/OS.kill as a fallback around a rejected Store gate.
	# The runner's already bounded private Job remains the external hard limit.

func _exit_tree() -> void:
	_set_fire(false)
	_set_brake(false)
	if not native_exit_requested or report_cache.is_empty(): return
	report_cache["native_exit"]["observed_scene_exit"]=true
	if is_instance_valid(session):
		report_cache["native_exit"]["audio"]=_plain(session.last_audio_shutdown_result)
		if not session.last_audio_shutdown_result.get("ready",false):
			report_cache["complete"]=false
			report_cache["whale_segment_complete"]=false
			report_cache["requested_stage_stopped"]=false
			report_cache["failures"].append("Original final-exit audio drain did not become ready.")
	report_cache["engine_errors"]=_plain(logger.errors)
	if not logger.errors.is_empty():
		report_cache["complete"]=false
		report_cache["whale_segment_complete"]=false
		report_cache["requested_stage_stopped"]=false
	_flush_report()

func _next() -> void:
	await get_tree().physics_frame
	await get_tree().process_frame
	if finished or not is_instance_valid(session): return
	var completed: Array = session.story.state.get("completed",[])
	if completed!=last_completed:
		_event("original_story_prefix_changed",{"before":last_completed,"after":completed.duplicate(),"source_digest":_receipts_digest(session.story.state,SOURCE_GOALS)})
		last_completed=completed.duplicate()

func _body() -> FlightBodyV2:
	return session.players[1]

func _native_velocity() -> Vector3:
	return PhysicsServer3D.body_get_state(_body().get_rid(),PhysicsServer3D.BODY_STATE_LINEAR_VELOCITY)

func _live() -> bool:
	return is_instance_valid(session) and session.active and session.network.mode=="solo" and session.players.has(1) and is_instance_valid(session.players[1]) and is_instance_valid(session.world)

func _healthy() -> bool:
	return running and not stopping and not finished and failures.is_empty() and logger.errors.is_empty() and _live() and _body().enabled and not session.simulation_paused and session.world.build_errors.is_empty()

func _elapsed() -> float:
	return float(Time.get_ticks_usec()-started_usec)/1000000.0

func _phase(value: String) -> void:
	phase=value
	_event("phase",{"phase":phase,"status":_status()})

func _event(kind: String, detail: Dictionary) -> void:
	var row: Dictionary = {"kind":kind,"seconds":_elapsed(),"physics_frame":Engine.get_physics_frames(),"detail":_plain(detail)}
	events.append(row)
	print("NORMAL_WHALE_EVENT "+JSON.stringify(row))

func _check(ok: bool, label: String, detail: Variant = null) -> bool:
	checks.append({"passed":ok,"label":label,"detail":_plain(detail)})
	if not ok: failures.append(label)
	return ok

func _status() -> Dictionary:
	if not is_instance_valid(session): return {"session_valid":false}
	var result: Dictionary = {"region":session.region_id,"active":session.active,"paused":session.simulation_paused,"boss_active":session.boss_active,"boss_campaign":session.boss_campaign,"pending_completion":session.pending_completion,"completed":session.story.state.get("completed",[]).duplicate(),"message":session.interface.message.text,"last_commit":session.last_commit_result,"proposal":session.consensus.current_proposal(),"generation":session.store.snapshot().get("generation")}
	if _live():
		result["position"]=_body().global_position
		result["velocity"]=_body().linear_velocity
		result["native_velocity"]=_native_velocity()
		result["health"]=_body().health
		result["enabled"]=_body().enabled
		result["collision_count"]=_body().collision_count
		result["water_contact"]=_body().water_contact
		result["brake_active"]=_body().telemetry.get("brake_active",false)
		result["nearest_G"]=session.story.nearest(_body().global_position)
		result["encounter"]=session.encounter.get_state()
		result["pilot"]=pilot.report() if pilot!=null else {}
	return result

static func _plain(value: Variant) -> Variant:
	if value is Vector3: return [value.x,value.y,value.z]
	if value is Array:
		var rows: Array = []
		for item: Variant in value: rows.append(_plain(item))
		return rows
	if value is Dictionary:
		var result: Dictionary = {}
		for key: Variant in value: result[str(key)]=_plain(value[key])
		return result
	if value is Object or value is RID: return str(value)
	return value
