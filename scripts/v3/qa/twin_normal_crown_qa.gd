extends Node
const SourceBinding = preload("res://scripts/v3/qa/twin_source_binding.gd")
static var _source_binding: Dictionary = {}
## AUTHORING ONLY. Root installs the normal exported-MAIN hook separately.
## Read-only source validation; all progress comes from original normal gameplay.
const Pilot = preload("res://scripts/v3/gameplay/canal/canal_transport_physics/transport_pilot.gd")
const Store = preload("res://scripts/v3/core/twin_world_store.gd")
const Director = preload("res://scripts/v3/gameplay/actions/twin_action_director.gd")
const Catalog = preload("res://scripts/v3/campaign/twin_campaign_catalog.gd")
static var SOURCE_PROFILE := ""
# Bound to the observed dev75 natural Whale record report; no progress is imported.
# preflight still validates the original Store/Director and exact receipt prefix.
static var SOURCE_REPORT_SHA256 := ""
static var NINETEEN_DIGEST := ""
static var SEVENTEEN_DIGEST := ""
const BASE_SEVENTEEN := ["I1:rescue:brief","I1:rescue:channel","I1:rescue:contact","I1:rescue:evacuate","I1:evidence:trace","I1:evidence:engineer","I1:evidence:ledger","I1:evidence:echo","F1:needs:listen","F1:needs:nursery","F1:needs:route","F1:repair:plan","F1:repair:light","F1:repair:grow","F1:repair:confirm","I1:whale:brief","I1:whale:engage"]
const SOURCE_GOALS := ["I1:rescue:brief","I1:rescue:channel","I1:rescue:contact","I1:rescue:evacuate","I1:evidence:trace","I1:evidence:engineer","I1:evidence:ledger","I1:evidence:echo","F1:needs:listen","F1:needs:nursery","F1:needs:route","F1:repair:plan","F1:repair:light","F1:repair:grow","F1:repair:confirm","I1:whale:brief","I1:whale:engage","I1:whale:disable","I1:whale:record"]
const EXPECTED := ["I1:rescue:brief","I1:rescue:channel","I1:rescue:contact","I1:rescue:evacuate","I1:evidence:trace","I1:evidence:engineer","I1:evidence:ledger","I1:evidence:echo","F1:needs:listen","F1:needs:nursery","F1:needs:route","F1:repair:plan","F1:repair:light","F1:repair:grow","F1:repair:confirm","I1:whale:brief","I1:whale:engage","I1:whale:disable","I1:whale:record","F1:crown:brief","F1:crown:engage","F1:crown:disable","F1:crown:restore"]
const STAGES := ["brief","engage","first_bound","half","second_bound","victory","record"]
const WEST := "F1:crown_host_west"
const HIGH := "F1:crown_host_high"
const CORE := "boss:crown_core"
const COMMON_CANDIDATE := Vector3(4,15,-23)
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
var last_region := ""
var last_heartbeat := 0.0
var last_combat_key := ""
var last_completed: Array = []
var current_attempt := -1
var wanted_fire := false
var managed_fire := false
var managed_brake := false
var fire_floor_milli := 0
var navigation_braking := false
var core_hits: Array = []
var last_core_hp_milli := 160000
var report_cache: Dictionary = {}
var native_exit_requested := false


static func preflight(args: PackedStringArray) -> Dictionary:
	_source_binding = {}
	var bound: Dictionary = SourceBinding.prepare(args,"normal-crown",SOURCE_GOALS,EXPECTED)
	if not bound.get("ok",false): return {"ok":false,"code":bound.get("code","source_binding_rejected"),"config":{}}
	_source_binding = bound.binding
	args = bound.args
	SOURCE_PROFILE = str(_source_binding.constants["SOURCE_PROFILE"])
	SOURCE_REPORT_SHA256 = str(_source_binding.constants["SOURCE_REPORT_SHA256"])
	SEVENTEEN_DIGEST = str(_source_binding.constants["SEVENTEEN_DIGEST"])
	NINETEEN_DIGEST = str(_source_binding.constants["NINETEEN_DIGEST"])
	if SOURCE_REPORT_SHA256.length()!=64 or NINETEEN_DIGEST.length()!=64: return {"ok":false,"code":"root_must_bind_actual_successful_whale_evidence","config":{}}
	var values: Dictionary = {}
	for argument: String in args:
		var key := ""
		var value := ""
		if argument == "--qa-normal-crown":
			key = "enabled"
			value = "true"
		else:
			for pair: Array in [["--qa-profile=","profile"],["--qa-normal-output=","output"],["--qa-normal-seconds=","seconds"],["--qa-crown-stop-after=","stage"]]:
				if argument.begins_with(str(pair[0])):
					key = str(pair[1])
					value = argument.trim_prefix(str(pair[0]))
					break
		if key.is_empty() or value.is_empty() or values.has(key): return {"ok":false,"code":"unknown_empty_or_duplicate_crown_cli","config":{}}
		values[key] = value
	for key: String in ["enabled","profile","output","seconds"]:
		if not values.has(key): return {"ok":false,"code":"four_normal_crown_arguments_required","config":{}}
	if values.size() < 4 or values.size() > 5: return {"ok":false,"code":"invalid_crown_argument_count","config":{}}
	if values.profile != SOURCE_PROFILE or not DirAccess.dir_exists_absolute("user://profiles_v3/" + SOURCE_PROFILE): return {"ok":false,"code":"same_existing_natural_profile_required","config":{}}
	var seconds: String = str(values.seconds)
	if not seconds.is_valid_int() or str(seconds.to_int()) != seconds or seconds.to_int() < 30 or seconds.to_int() > 300: return {"ok":false,"code":"crown_seconds_30_to_300_required","config":{}}
	var stage: String = str(values.get("stage","record"))
	if stage not in STAGES: return {"ok":false,"code":"invalid_crown_stop_stage","config":{}}
	var selected_output: String = str(values.output).replace("\\","/")
	if not _output_valid(selected_output): return {"ok":false,"code":"new_absolute_normal_crown_json_required","config":{}}
	var reader = Store.new("user://profiles_v3/" + SOURCE_PROFILE)
	var loaded: Dictionary = reader.load_profile()
	if not loaded.get("ok",false) or loaded.get("recovered",false): return {"ok":false,"code":"unrecovered_original_profile_required","config":{}}
	var saved: Dictionary = reader.snapshot()
	if not SourceBinding.start_matches(_source_binding,saved): return {"ok":false,"code":"verified_initial_source_generation_changed","config":{}}
	var verified: Dictionary = _source_check(saved)
	if not verified.ok: return {"ok":false,"code":verified.code,"config":{}}
	if verified.victory_committed and stage in ["brief","engage","first_bound","half","second_bound"]: return {"ok":false,"code":"requested_fight_stage_already_bypassed_by_real_saved_victory","config":{}}
	return {"ok":true,"code":"natural_crown_prefix_verified","config":{"profile":SOURCE_PROFILE,"output":selected_output,"max_seconds":seconds.to_int(),"stop_after":stage,"source_profile_id":saved.profile_id,"source_lineage_id":saved.lineage_id,"source_receipts_sha256":verified.source_receipts_sha256}}

static func _source_check(saved: Dictionary) -> Dictionary:
	if not SourceBinding.same_identity(_source_binding,saved):
		return {"ok":false,"code":"verified_source_identity_mismatch"}
	if SOURCE_REPORT_SHA256.length()!=64 or NINETEEN_DIGEST.length()!=64: return {"ok":false,"code":"actual_whale_evidence_not_bound"}
	var world: Variant = saved.get("world")
	if not world is Dictionary or world.get("region_id") not in ["I1","F1"] or world.get("branch_id")!="main": return {"ok":false,"code":"same_natural_main_branch_I1_or_F1_required"}
	if not world.get("actions") is Dictionary or not world.actions.get("opening") is Dictionary or not world.get("flags") is Dictionary: return {"ok":false,"code":"source_story_schema"}
	var state: Dictionary = world.actions.opening
	var completed: Variant = state.get("completed")
	if not completed is Array or completed.size()<19 or completed.size()>23: return {"ok":false,"code":"only_natural_nineteen_to_twenty_three_prefix_accepted"}
	if completed!=EXPECTED.slice(0,completed.size()) or world.get("completed_objectives")!=completed or not state.get("receipts") is Dictionary or state.receipts.size()!=completed.size(): return {"ok":false,"code":"exact_natural_prefix_and_receipts_required"}
	if _receipts_digest(state,BASE_SEVENTEEN)!=SEVENTEEN_DIGEST or _receipts_digest(state,SOURCE_GOALS)!=NINETEEN_DIGEST: return {"ok":false,"code":"actual_natural_source_receipts_changed"}
	var director = Director.new()
	var definitions: Dictionary = director.load_definitions(Director.DEFAULT_PATH,Catalog.extension_paths())
	if not definitions.get("ok",false): return {"ok":false,"code":"original_director_unavailable"}
	var valid: Dictionary = director.validate_state(state)
	if not valid.get("ok",false): return {"ok":false,"code":"original_director_replay_rejected:"+str(valid.get("code",""))}
	var flags: Dictionary = world.flags
	if not flags.get("I1_gate",false) or not flags.get("F1_gate",false) or not flags.get("I1_boss",false) or not flags.get("campaign_whale_v1",false): return {"ok":false,"code":"natural_gate_and_whale_record_history_required"}
	var commits: Variant = saved.get("ledger",{}).get("commits")
	var discoveries: Variant = saved.get("personal",{}).get("discoveries")
	if not commits is Dictionary or not discoveries is Array: return {"ok":false,"code":"original_reward_ledger_required"}
	var whale_receipt := false
	var crown_receipt := false
	for receipt: Variant in commits:
		if str(receipt).begins_with("boss:I1:harbor_whale:opening_v1:main:"): whale_receipt=true
		if str(receipt).begins_with("boss:F1:parasitic_crown:opening_v1:main:"): crown_receipt=true
	if not whale_receipt or discoveries.count("boss:I1:harbor_whale")!=1 or discoveries.count("opening:whale_raw_command_record")!=1: return {"ok":false,"code":"actual_whale_victory_and_record_receipts_required"}
	var victory: bool = bool(flags.get("F1_boss",false))
	if victory!=bool(flags.get("campaign_crown_v1",false)) or completed.size()>21 and not victory: return {"ok":false,"code":"crown_victory_prefix_mismatch"}
	if victory and (not crown_receipt or discoveries.count("boss:F1:parasitic_crown")!=1): return {"ok":false,"code":"original_crown_victory_receipt_and_reward_required"}
	return {"ok":true,"code":"natural_crown_prefix_valid","completed":completed.duplicate(),"source_receipts_sha256":NINETEEN_DIGEST,"victory_committed":victory}


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
	return {"ok":true,"code":"observing_natural_crown","stop_after":stop_after,"max_seconds":max_seconds}

func _execute() -> void:
	if not _check(session.profile_ready and not session.active and not OS.has_feature("editor"),"actual exported MAIN before ordinary menu continuation"): _stop("exported_normal_menu_required"); return
	last_completed=initial.world.actions.opening.completed.duplicate()
	_phase("ordinary_menu_resume_natural_whale_record_profile")
	session._ui_action("solo",{"frame":0})
	await _next()
	if not _healthy() or not _check(_receipts_digest(session.story.state,SOURCE_GOALS)==initial_digest,"normal menu retains every actual nineteen-goal source receipt",_status()): _stop("ordinary_source_resume_failed"); return
	if not await _dismiss_radio(): _stop("radio_not_closed"); return
	if session.region_id=="I1":
		if not _check(session._can_travel_to("F1"),"original M route to F1 available after actual whale record"): _stop("normal_F1_travel_locked"); return
		_phase("ordinary_M_travel_to_F1")
		session._ui_action("travel_to",{"region_id":"F1"})
		var travel_deadline: float = _elapsed()+8.0
		while _healthy() and session.region_id!="F1" and _elapsed()<travel_deadline: await _next()
	if not _check(_healthy() and session.region_id=="F1" and session.crown.ready(),"normal travel restores actual F1 modules and its original spawn",_status()): _stop("normal_F1_arrival_failed"); return
	_bind_pilot()
	var observed: Vector3 = _body().global_position
	if not await _navigate([Vector3(observed.x,12.2,observed.z),Vector3(-18,12.2,8),Vector3(0,12.2,1)],"root_arch_south_brief"): _stop("brief_candidate_route_blocked"); return
	if "F1:crown:brief" not in session.story.state.get("completed",[]):
		if not _check(not session.boss_active,"southern radio candidate remains outside actual combat space"): _stop("premature_crown_start"); return
		if not await _contact("F1:crown_briefing","F1:crown:brief"): _stop("normal_crown_brief_not_committed"); return
	if _stage("brief"): return
	if session.story.crown_victory_committed():
		if not await _navigate([Vector3(4,15,-8),Vector3(4,15,-18)],"north_after_original_saved_crown_victory"): _stop("saved_victory_route_blocked"); return
	if not session.story.crown_victory_committed():
		if not await _dismiss_radio(): _stop("brief_radio_not_closed"); return
		if not await _navigate([Vector3(4,15,-8),COMMON_CANDIDATE],"single_common_host_candidate"): _stop("common_candidate_flight_blocked"); return
		if not await _normal_brake_settle(): _stop("original_space_brake_not_observed"); return
		if not _check(session.boss_active and session.boss_campaign and session.world.crown_arena.engagement(_body().global_position),"ordinary physical approach starts original campaign crown",_status()): _stop("actual_crown_engagement_missing"); return
		current_attempt=int(_encounter_state().get("attempt",-1))
		if _stage("engage"): return
		if not _check(_ray_to(WEST).get("entity_id")==WEST and _ray_to(HIGH).get("entity_id")==HIGH,"single common candidate has actual first-hit LOS to west and high hosts",{"west":_ray_to(WEST),"high":_ray_to(HIGH),"classification":"single_candidate_only_not_all_routes"}): _stop("common_host_LOS_unproven"); return
		var attached: Dictionary = _encounter_state()
		if not _check(attached.get("mode")=="attached" and attached.get("anchor_id")==WEST,"first genuine host is still attached at west before normal light-growth",attached): _stop("first_host_changed_before_candidate_arrival"); return
		if not await _light_growth(WEST): _stop("first_host_pair_rejected"); return
		if not _check(_encounter_state().get("mode")=="bound" and _encounter_state().get("core_open",false),"actual west host binding opens the real core",_encounter_state()): _stop("first_real_binding_missing"); return
		_observe_support("first_bound")
		if _stage("first_bound"): return
		if not await _fire_to(88000,1): _stop("first_eight_real_hits_incomplete"); return
		# Stop normal held fire at 88 HP in the physics observer, not a render
		# coroutine: the next real request crosses the 80 HP phase clamp.
		if not await _light_growth(HIGH): _stop("next_high_trap_pair_rejected"); return
		var prepared: Dictionary = _encounter_state()
		if not _check(prepared.get("anchor_id")==WEST and prepared.get("mode")=="bound" and int(prepared.anchors[HIGH].trap_until)>int(prepared.tick) and int(prepared.anchors[HIGH].light_until)>int(prepared.tick),"next high host trap is armed by actual abilities before half health",prepared): _stop("next_trap_not_prepared_in_real_window"); return
		if not await _fire_to(80000,2): _stop("actual_half_clamp_not_reached"); return
		var half: Dictionary = _encounter_state()
		if not _check(int(half.get("phase",0))==2 and int(half.get("core_hp_milli",0))==80000 and half.movement.get("reason")=="half_health" and half.movement.get("target_id")==HIGH and half.movement.get("approved",false),"native half-health clamps to eighty and approves the real lit-host migration",half): _stop("half_or_real_migration_not_observed"); return
		if _stage("half"): return
		var migration_deadline: float = minf(max_seconds-10.0,_elapsed()+6.0)
		while _healthy() and not (_encounter_state().get("mode")=="bound" and _encounter_state().get("anchor_id")==HIGH) and _elapsed()<migration_deadline: await _next()
		var arrived: Dictionary = _encounter_state()
		var actual_body: Vector3 = session.world.crown_arena.model.global_position
		var expected_body: Vector3 = session.world.crown_arena.to_global(session.world.crown_arena.body_position(arrived.boss_position))
		if not _check(_healthy() and arrived.get("mode")=="bound" and arrived.get("anchor_id")==HIGH and actual_body.distance_to(expected_body)<.01,"ordinary native migration reaches high platform and its real trap binds",{"state":arrived,"actual_body":actual_body,"mapped_body":expected_body}): _stop("native_second_host_arrival_incomplete"); return
		_observe_support("second_bound")
		if _stage("second_bound"): return
		if not await _fire_to(0,2): _stop("second_phase_actual_hits_incomplete"); return
	var victory_deadline: float = _elapsed()+8.5
	while _healthy() and (session.pending_completion or not session.story.crown_victory_committed() or "F1:crown:disable" not in session.story.state.get("completed",[])) and _elapsed()<victory_deadline: await _next()
	if not _check(_healthy() and not session.pending_completion and not session.boss_active and session.story.crown_victory_committed() and "F1:crown:disable" in session.story.state.get("completed",[]),"original crown victory transaction and Story disable are durable",_status()): _stop("crown_victory_not_durable"); return
	if _stage("victory"): return
	if "F1:crown:restore" not in session.story.state.get("completed",[]):
		if not await _dismiss_radio(): _stop("victory_radio_not_closed"); return
		var target: Vector3 = session.world.crown_arena.host_position(WEST)
		var approach: Vector3 = target+Vector3(0,1.2,2.0)
		if not _check(_hull_clear(approach) and session._line_clear(approach,target,_body().get_rid(),WEST),"single recovered-host approach has actual hull clearance and LOS",{"target":target,"candidate":approach}): _stop("recovered_host_candidate_blocked"); return
		if not await _navigate([Vector3(approach.x,maxf(_body().global_position.y,approach.y+2.0),approach.z),approach],"real_recovered_west_host"): _stop("recovered_host_flight_blocked"); return
		if not await _contact("F1:crown_recovered","F1:crown:restore"): _stop("recovered_host_G_not_committed"); return
	if not _check(session.story.state.get("completed",[])==EXPECTED and _receipts_digest(session.story.state,SOURCE_GOALS)==initial_digest,"exact natural twenty-three goals retain all nineteen source receipts",_status()): _stop("unexpected_final_prefix"); return
	if not initial.world.flags.get("campaign_crown_v1",false) and not _check_damage_chain(): _stop("actual_crown_damage_chain_incomplete"); return
	_stage("record")


func _normal_brake_settle() -> bool:
	_phase("ordinary_Space_settle_not_crown_immunity")
	navigation_braking=true
	_set_brake(true)
	var deadline: float = minf(max_seconds-10.0,_elapsed()+2.0)
	var observed := false
	while _healthy() and _elapsed()<deadline:
		await _next()
		if _body().telemetry.get("brake_active",false) and _native_velocity().length()<.35:
			observed=true
			break
	_set_brake(false)
	navigation_braking=false
	if _healthy():
		command_serial+=1
		pilot.go_to(_body().global_position,command_serial)
	return _check(observed,"original Space reaches native Flight braking without a Pilot overwrite",_status())

func _encounter_state() -> Dictionary:
	return session.crown.encounter.get_state()

func _cast(ability: String, target: String) -> bool:
	_phase("normal_ability:"+ability+":"+target)
	var deadline: float = minf(max_seconds-10.0,_elapsed()+2.0)
	while _healthy() and float(session.cooldowns.get(1,0))>0 and _elapsed()<deadline: await _next()
	if not _healthy(): return false
	session.network.send_action("lock",{"target_id":target})
	var before: int = int(session.stats.abilities)
	session.network.send_action("ability",{"ability":ability,"target_id":target})
	return _check(int(session.stats.abilities)==before+1,"original Crown Rules accepts actual "+ability+" on "+target,{"ray":_ray_to(target),"state":_encounter_state(),"status":_status()})

func _light_growth(target: String) -> bool:
	if not await _cast("light",target): return false
	return await _cast("growth",target)

func _fire_to(hp_milli: int, required_phase: int) -> bool:
	_phase("normal_fire_to_"+str(hp_milli)+"_milli_phase_"+str(required_phase))
	session.network.send_action("lock",{"target_id":CORE})
	fire_floor_milli=hp_milli
	wanted_fire=true
	var deadline: float = minf(max_seconds-10.0,_elapsed()+6.5)
	while _healthy() and _elapsed()<deadline:
		var state: Dictionary = _encounter_state()
		if int(state.get("core_hp_milli",160000))<=hp_milli and int(state.get("phase",0))==required_phase:
			wanted_fire=false
			_set_fire(false)
			_observe_combat(state)
			return true
		if not state.get("core_open",false):
			wanted_fire=false
			_set_fire(false)
			return _check(false,"actual Crown core window reaches requested native HP boundary",{"state":state,"ray":_ray_to(CORE)})
		await _next()
	wanted_fire=false
	_set_fire(false)
	return false

func _physics_process(delta: float) -> void:
	if not running or stopping or not _live() or session.simulation_paused: return
	physics_frames+=1
	var body: FlightBodyV2 = _body()
	if last_body_id==body.get_instance_id() and last_region==session.region_id:
		var moved: float = previous_position.distance_to(body.global_position)
		actual_distance+=moved
		max_frame_distance=maxf(max_frame_distance,moved)
	last_body_id=body.get_instance_id()
	last_region=session.region_id
	previous_position=body.global_position
	var state: Dictionary = _encounter_state() if session.region_id=="F1" else {}
	_observe_combat(state)
	if stopping: return
	# Crown has NO brake immunity or decoy retargeting. Hold real navigation;
	# original light-growth binding, actual terrain and geometry decide safety.
	if pilot!=null and not navigation_braking: pilot.tick(delta,true,false)
	var may_fire: bool = wanted_fire and not state.is_empty() and int(state.get("core_hp_milli",0))>fire_floor_milli and state.get("core_open",false) and not state.get("completed",false) and str(session.locks.get(1,""))==CORE and _ray_to(CORE).get("entity_id")==CORE
	_set_fire(may_fire)

func _observe_combat(state: Dictionary) -> void:
	if state.is_empty(): return
	var attempt: int = int(state.get("attempt",-1))
	if current_attempt<0: current_attempt=attempt
	if attempt!=current_attempt:
		_check(false,"original Crown attempt continues without native whole-wipe reset",{"before":current_attempt,"actual":attempt,"state":state})
		_stop("actual_crown_attempt_reset")
		return
	var key: String = JSON.stringify([state.get("attempt"),state.get("mode"),state.get("phase"),state.get("core_hp_milli"),state.get("anchor_id"),state.get("position_mm"),state.get("movement"),state.get("attack",{}).get("token"),state.get("attack",{}).get("fired"),_body().health])
	if key!=last_combat_key:
		last_combat_key=key
		_event("ordinary_crown_transition",{"state":state,"actual_model_position":session.world.crown_arena.model.global_position,"actor_position":_body().global_position,"native_velocity":_native_velocity(),"shots":session.stats.shots,"core_ray":_ray_to(CORE),"west_ray":_ray_to(WEST),"high_ray":_ray_to(HIGH)})
	var health: int = int(state.get("core_hp_milli",160000))
	if health<last_core_hp_milli:
		core_hits.append({"seconds":_elapsed(),"before_hp_milli":last_core_hp_milli,"after_hp_milli":health,"decrease_milli":last_core_hp_milli-health,"requested_damage_milli":9000,"phase":state.get("phase"),"shots":session.stats.shots})
	last_core_hp_milli=health

func _check_damage_chain() -> bool:
	var valid: bool = core_hits.size()==18
	var expected_before := 160000
	var phase_two := false
	for hit: Dictionary in core_hits:
		var after: int = maxi(0,expected_before-9000)
		if not phase_two and after<=80000:
			after=80000
			phase_two=true
		if int(hit.before_hp_milli)!=expected_before or int(hit.after_hp_milli)!=after or int(hit.decrease_milli)!=expected_before-after: valid=false
		expected_before=after
	return _check(valid and expected_before==0 and "half" in reached_stages and "second_bound" in reached_stages,"eighteen original nine-damage requests follow exact half and final clamps",core_hits)

func _observe_support(label: String) -> void:
	var rows: Array = []
	var arena: Node3D = session.world.crown_arena
	for limb: String in ["FL","FR","BL","BR"]:
		var foot: Node3D = arena.model.visual.find_child("ClawContact_"+limb,true,false)
		if foot==null:
			rows.append({"limb":limb,"anchor_missing":true})
			continue
		var point: Vector3 = foot.global_position
		var query := PhysicsRayQueryParameters3D.create(point+Vector3.UP*.2,point-Vector3.UP*.2,1)
		var hit: Dictionary = arena.get_world_3d().direct_space_state.intersect_ray(query)
		rows.append({"limb":limb,"foot":point,"support_hit":not hit.is_empty(),"position":hit.get("position"),"collider":str(hit.collider.get_path()) if not hit.is_empty() else ""})
	# Observation only: do not invent an extra player-grounded or claw-contact
	# completion gate that production's original support/motion adapter lacks.
	_event("actual_host_support_rays",{"stage":label,"rows":rows})

func _ray_to(target: String) -> Dictionary:
	if not _live() or session.region_id!="F1" or not session.crown.ready(): return {"entity_id":"","code":"arena_not_ready"}
	var point: Vector3 = session.world.crown_arena.core_position() if target==CORE else session.world.crown_arena.host_position(target)
	if not point.is_finite(): return {"entity_id":"","code":"physical_target_missing"}
	var query := PhysicsRayQueryParameters3D.create(_body().global_position,point,1|8)
	query.exclude=[_body().get_rid()]
	var hit: Dictionary = session.world.get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty(): return {"entity_id":"","code":"no_first_hit","point":point}
	return {"entity_id":str(hit.collider.get_meta("entity_id","")),"collider":str(hit.collider.get_path()),"position":hit.position,"target":target,"distance":_body().global_position.distance_to(point)}

func _contact(target: String, objective: String) -> bool:
	_phase("normal_G:"+target)
	if not await _dismiss_radio(): return false
	var deadline: float = minf(max_seconds-10.0,_elapsed()+8.0)
	var next_press := 0.0
	while _healthy() and objective not in session.story.state.get("completed",[]) and _elapsed()<deadline:
		if not _check(session.story.nearest(_body().global_position)==target,"normal nearest G resolves "+target,_status()): return false
		if _elapsed()>=next_press:
			_press_g()
			next_press=_elapsed()+.6
		await _next()
	return _check(objective in session.story.state.get("completed",[]),"original near/LOS G commits "+objective,_status())


static func _output_valid(path: String) -> bool:
	return path.is_absolute_path() and "://" not in path and ".." not in path and "\n" not in path and "\r" not in path and path.get_file().begins_with("normal-crown-") and path.get_extension() == "json" and not FileAccess.file_exists(path) and not DirAccess.dir_exists_absolute(path)

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
	_event("actual_stage_observed",{"stage":value,"state":_encounter_state(),"status":_status()})
	if stop_after==value:
		_stop("normal_crown_complete" if value=="record" else "requested_stage_pause")
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
	var complete: bool = reason=="normal_crown_complete" and failures.is_empty() and logger.errors.is_empty() and preserved and saved_now and matches_live and saved.world.actions.opening.completed==EXPECTED
	var stage_stopped: bool = reason=="requested_stage_pause" and stop_after in reached_stages and failures.is_empty() and logger.errors.is_empty() and preserved and saved_now and matches_live and preservation.common_paused
	if complete:
		_check(saved.personal.discoveries.count("boss:F1:parasitic_crown")==1 and saved.personal.discoveries.count("opening:crown_imbalance_evidence")==1,"actual original reward and raw-record discovery are each present exactly once",saved.personal.discoveries)
		complete=failures.is_empty()
	_write_report(reason,complete,stage_stopped)

func _write_report(reason: String, complete: bool, stage_stopped: bool) -> void:
	finished=true
	running=false
	_set_fire(false)
	_set_brake(false)
	var report: Dictionary = {"complete":complete,"crown_segment_complete":complete,"requested_stage_stopped":stage_stopped,"requested_stage":stop_after,"reached_stages":reached_stages,"stop_reason":reason,"phase":phase,"seconds":_elapsed(),"max_seconds":max_seconds,"profile":SOURCE_PROFILE,"user_dir":OS.get_user_data_dir(),"executable":OS.get_executable_path(),"exported_application":not OS.has_feature("editor"),"runtime_cwd":DirAccess.open(".").get_current_dir(),"source_generation":initial.get("generation"),"base_seventeen_receipts_sha256":SEVENTEEN_DIGEST,"source_report_sha256":SOURCE_REPORT_SHA256,"source_receipts_sha256":initial_digest,"physics_frames":physics_frames,"actual_distance_m":actual_distance,"max_frame_distance_m_excluding_normal_travel":max_frame_distance,"checks":checks,"failures":failures,"engine_errors":logger.errors,"events":events,"ten_second_samples":samples,"core_damage_observations":core_hits,"status":_status(),"preservation":preservation,"fresh_reader":final_reader,"story_receipts":session.story.state.get("receipts",{}),"stats":session.stats,"pilot":pilot.report() if pilot!=null and is_instance_valid(pilot.body) else {},"scope":"Actual exported MAIN continues only the same naturally obtained legal nineteen-to-twenty-three objective prefix. Normal M travel/spawn, continuous original Flight/Pilot, physical host light-growth, original input shooting, exact eighty-HP clamp, native approved migration and actual core rays, original Crown Store reward, manual recovered-host G, SaveGate/fresh reader and production native-audio exit. No pose, HP, flags, prefix, cooldown, clock or fixture injection. Requested stage pauses and failures are not combat completion. A fresh invocation restarts an unfinished native attempt; no persisted encounter-state claim. No full-campaign, human-fun, LAN, performance or controller acceptance."}
	report.merge(SourceBinding.audit(_source_binding))
	report["native_exit"]={"requested":true,"through":"session._quit","observed_scene_exit":false,"watchdog_failed":false}
	report_cache=_plain(report)
	var written: bool = _flush_report()
	print("NORMAL_CROWN_RESULT "+JSON.stringify({"complete":complete,"requested_stage_stopped":stage_stopped,"written":written,"reason":reason,"phase":phase,"seconds":_elapsed(),"failures":failures,"engine_errors":logger.errors}))
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
	report_cache["crown_segment_complete"]=false
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
	print("NORMAL_CROWN_EXIT_WATCHDOG_FAIL "+JSON.stringify(report_cache.native_exit))
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
			report_cache["crown_segment_complete"]=false
			report_cache["requested_stage_stopped"]=false
			report_cache["failures"].append("Original final-exit audio drain did not become ready.")
	report_cache["engine_errors"]=_plain(logger.errors)
	if not logger.errors.is_empty():
		report_cache["complete"]=false
		report_cache["crown_segment_complete"]=false
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
	print("NORMAL_CROWN_EVENT "+JSON.stringify(row))

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
		result["encounter"]=_encounter_state()
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

func _process(_delta: float) -> void:
	if not running or finished: return
	if not stopping and _elapsed()>=max_seconds-10.0: _stop("bounded_wall_deadline_incomplete")
	if not stopping and not logger.errors.is_empty(): _stop("engine_error")
	if not stopping and _elapsed()-last_heartbeat>=10.0:
		last_heartbeat=_elapsed()
		var row: Dictionary = {"seconds":_elapsed(),"phase":phase,"status":_status()}
		samples.append(_plain(row))
		print("NORMAL_CROWN_PROGRESS "+JSON.stringify(_plain(row)))
