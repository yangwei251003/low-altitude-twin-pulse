extends Node
const SourceBinding = preload("res://scripts/v3/qa/twin_source_binding.gd")
static var _source_binding: Dictionary = {}
## AUTHORING ONLY: same natural F2 investigation46 -> Mirrorwing50.
## No source46 evidence exists yet; both preflight/run refuse the empty binding.
const Pilot = preload("res://scripts/v3/qa/twin_normal_flight_pilot.gd")
const Store = preload("res://scripts/v3/core/twin_world_store.gd")
const Director = preload("res://scripts/v3/gameplay/actions/twin_action_director.gd")
const Catalog = preload("res://scripts/v3/campaign/twin_campaign_catalog.gd")
const I2Results = preload("res://scripts/v3/gameplay/twin_i2_result_ledger.gd")
const AbilityRules = preload("res://scripts/v3/gameplay/twin_ability_rules.gd")
const Encounter = preload("res://scripts/v3/campaign/twin_campaign_encounter.gd")
static var SOURCE_PROFILE := "qa_normal_campaign_20261021_012725_b90f8a6f"
static var SOURCE_REPORT_SHA256 := "7181560a1211c8935fabc85c61052ef16a5ff6f803faacdb7f279e0b067a3a5f"
static var FORTYSIX_DIGEST := "2db87ac19846e1909b90580eede8243a430956dbddadcdca9077d331f66bb5d6"
const SOURCE_GOALS := ["I1:rescue:brief","I1:rescue:channel","I1:rescue:contact","I1:rescue:evacuate","I1:evidence:trace","I1:evidence:engineer","I1:evidence:ledger","I1:evidence:echo","F1:needs:listen","F1:needs:nursery","F1:needs:route","F1:repair:plan","F1:repair:light","F1:repair:grow","F1:repair:confirm","I1:whale:brief","I1:whale:engage","I1:whale:disable","I1:whale:record","F1:crown:brief","F1:crown:engage","F1:crown:disable","F1:crown:restore","I1:underdeck:read","I1:underdeck:enter","I1:underdeck:release","I1:underdeck:traverse","I2:clinic_supply:diagnose","I2:clinic_supply:connect","I2:clinic_supply:stabilize","I2:clinic_supply:confirm","I2:distribution_audit:expose","I2:distribution_audit:trace","I2:distribution_audit:share_access","I2:canal_service:brief","I2:canal_service:exchange","I2:canal_service:service","I2:canal_service:order","I2:twin_pump_guardian:plan","I2:twin_pump_guardian:engage","I2:twin_pump_guardian:stop","I2:twin_pump_guardian:decision","F2:mirror_evidence:records","F2:mirror_evidence:archive","F2:mirror_evidence:light","F2:mirror_evidence:decision"]
const EXPECTED := ["I1:rescue:brief","I1:rescue:channel","I1:rescue:contact","I1:rescue:evacuate","I1:evidence:trace","I1:evidence:engineer","I1:evidence:ledger","I1:evidence:echo","F1:needs:listen","F1:needs:nursery","F1:needs:route","F1:repair:plan","F1:repair:light","F1:repair:grow","F1:repair:confirm","I1:whale:brief","I1:whale:engage","I1:whale:disable","I1:whale:record","F1:crown:brief","F1:crown:engage","F1:crown:disable","F1:crown:restore","I1:underdeck:read","I1:underdeck:enter","I1:underdeck:release","I1:underdeck:traverse","I2:clinic_supply:diagnose","I2:clinic_supply:connect","I2:clinic_supply:stabilize","I2:clinic_supply:confirm","I2:distribution_audit:expose","I2:distribution_audit:trace","I2:distribution_audit:share_access","I2:canal_service:brief","I2:canal_service:exchange","I2:canal_service:service","I2:canal_service:order","I2:twin_pump_guardian:plan","I2:twin_pump_guardian:engage","I2:twin_pump_guardian:stop","I2:twin_pump_guardian:decision","F2:mirror_evidence:records","F2:mirror_evidence:archive","F2:mirror_evidence:light","F2:mirror_evidence:decision","F2:mirrorwing_warden:plan","F2:mirrorwing_warden:engage","F2:mirrorwing_warden:stop","F2:mirrorwing_warden:record"]
const PLAN := "F2:mirrorwing_warden:plan"
const ENGAGE := "F2:mirrorwing_warden:engage"
const STOP := "F2:mirrorwing_warden:stop"
const RECORD := "F2:mirrorwing_warden:record"
const REWARD := "boss:F2:mirrorwing_warden"
const REVEAL_SOURCE := "F2:reveal_source"
const STAGES := ["plan","engage","half","stop","complete"]
const MASK := 1 | 2 | 4 | 8 | 32
class ErrorLogger extends Logger:
	var errors: Array = []
	var guard := Mutex.new()
	func _log_error(function: String,file: String,line: int,code: String,rationale: String,_notify: bool,kind: int,_trace: Array[ScriptBacktrace]) -> void:
		if kind==Logger.ERROR_TYPE_WARNING: return
		guard.lock()
		errors.append({"function":function,"file":file,"line":line,"code":code,"rationale":rationale,"kind":kind})
		guard.unlock()
var session: Node
var pilot: RefCounted
var logger := ErrorLogger.new()
var output := ""
var stop_after := "complete"
var choice := "balanced_service"
var max_seconds := 600.0
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
var last_completed: Array = []
var actual_abilities: Array = []
var actual_interactions: Array = []
var route: Dictionary = {}
var report_cache: Dictionary = {}
var native_exit_requested := false
var wanted_fire := false
var managed_fire := false
var fire_target := ""
var navigating := false
var patrol_enabled := false
var patrol_approach := false
var patrol_side := 1.0
var last_patrol_target := Vector3.INF
var original_attempt := -1
var last_combat_key := ""
var combat_transitions: Array = []
var damage_samples: Array = []
var reveal_observations: Array = []
var part_visits: Array = []
var battle_baseline: Dictionary = {}
var last_observed_shots := 0
var last_part_key := ""
var patrol_warning_token := ""
var damage_evidence: Dictionary = {}
var inherited_victory := false
var last_fire_observation := ""
var last_boss: Dictionary = {}
var phase_two_observed := false
var gui_actions: Array = []


static func _bound() -> bool:
	return SOURCE_REPORT_SHA256.length()==64 and FORTYSIX_DIGEST.length()==64

static func preflight(args: PackedStringArray) -> Dictionary:
	_source_binding = {}
	var bound: Dictionary = SourceBinding.prepare(args,"normal-f2-boss",SOURCE_GOALS,EXPECTED)
	if not bound.get("ok",false): return {"ok":false,"code":bound.get("code","source_binding_rejected"),"config":{}}
	_source_binding = bound.binding
	args = bound.args
	SOURCE_PROFILE = str(_source_binding.constants.get("SOURCE_PROFILE",SOURCE_PROFILE))
	SOURCE_REPORT_SHA256 = str(_source_binding.constants.get("SOURCE_REPORT_SHA256",SOURCE_REPORT_SHA256))
	FORTYSIX_DIGEST = str(_source_binding.constants.get("FORTYSIX_DIGEST",FORTYSIX_DIGEST))
	if not _bound(): return {"ok":false,"code":"root_must_bind_actual_F2Investigation46_report_and_receipts","config":{}}
	var values: Dictionary = {}
	for argument: String in args:
		var key := ""
		var value := ""
		if argument=="--qa-normal-f2-boss":
			key="enabled"
			value="true"
		else:
			for pair: Array in [["--qa-profile=","profile"],["--qa-normal-output=","output"],["--qa-normal-seconds=","seconds"],["--qa-f2-boss-stop-after=","stage"]]:
				if argument.begins_with(str(pair[0])):
					key=str(pair[1])
					value=argument.trim_prefix(str(pair[0]))
					break
		if key.is_empty() or value.is_empty() or values.has(key): return {"ok":false,"code":"unknown_empty_or_duplicate_f2_boss_cli","config":{}}
		values[key]=value
	for key: String in ["enabled","profile","output","seconds"]:
		if not values.has(key): return {"ok":false,"code":"four_f2_boss_arguments_required","config":{}}
	if values.size()<4 or values.size()>5 or values.profile!=SOURCE_PROFILE: return {"ok":false,"code":"same_natural_QA_profile_required","config":{}}
	var seconds: String=str(values.seconds)
	if not seconds.is_valid_int() or str(seconds.to_int())!=seconds or seconds.to_int()<60 or seconds.to_int()>600: return {"ok":false,"code":"seconds_60_to_600_required","config":{}}
	var stage: String=str(values.get("stage","complete"))
	var selected_output: String=str(values.output).replace("\\","/")
	if stage not in STAGES or not _output_valid(selected_output): return {"ok":false,"code":"invalid_stage_or_new_output","config":{}}
	if not DirAccess.dir_exists_absolute("user://profiles_v3/"+SOURCE_PROFILE): return {"ok":false,"code":"existing_natural_profile_required_no_replacement","config":{}}
	var reader=Store.new("user://profiles_v3/"+SOURCE_PROFILE)
	var loaded: Dictionary=reader.load_profile()
	if not loaded.get("ok",false) or loaded.get("recovered",false): return {"ok":false,"code":"unrecovered_original_profile_required","config":{}}
	var saved: Dictionary=reader.snapshot()
	if not SourceBinding.start_matches(_source_binding,saved): return {"ok":false,"code":"source_binding_initial_snapshot_changed","config":{}}
	var checked: Dictionary=_source_check(saved)
	if not checked.ok: return {"ok":false,"code":checked.code,"config":{}}
	return {"ok":true,"code":"natural_F2Investigation46_prefix_verified","config":{"profile":SOURCE_PROFILE,"output":selected_output,"max_seconds":seconds.to_int(),"stop_after":stage,"source_profile_id":saved.profile_id,"source_lineage_id":saved.lineage_id,"source_receipts_sha256":FORTYSIX_DIGEST}}

static func _source_check(saved: Dictionary) -> Dictionary:
	if not SourceBinding.same_identity(_source_binding,saved): return {"ok":false,"code":"source_binding_identity_changed"}
	if not _bound(): return {"ok":false,"code":"actual_F2Investigation46_source_not_bound"}
	var world: Variant=saved.get("world")
	if not world is Dictionary or world.get("region_id") not in ["I2","F2"] or world.get("branch_id")!="main": return {"ok":false,"code":"same_natural_I2_or_F2_main_branch_required"}
	if not world.get("actions") is Dictionary or not world.actions.get("opening") is Dictionary: return {"ok":false,"code":"source_story_schema"}
	var state: Dictionary=world.actions.opening
	var completed: Variant=state.get("completed")
	if not completed is Array or completed.size()<46 or completed.size()>50 or completed!=EXPECTED.slice(0,completed.size()) or world.get("completed_objectives")!=completed: return {"ok":false,"code":"only_exact_natural_46_to_50_prefix_accepted"}
	if not state.get("receipts") is Dictionary or state.receipts.size()!=completed.size() or _receipts_digest(state,SOURCE_GOALS)!=FORTYSIX_DIGEST: return {"ok":false,"code":"actual_original_46_receipts_changed"}
	var director=Director.new()
	var definitions: Dictionary=director.load_definitions(Director.DEFAULT_PATH,Catalog.extension_paths())
	if not definitions.get("ok",false) or not director.validate_state(state).get("ok",false): return {"ok":false,"code":"original_Director_replay_rejected"}
	var discoveries: Variant=saved.get("personal",{}).get("discoveries")
	if not discoveries is Array: return {"ok":false,"code":"original_personal_discoveries_required"}
	var valid: Dictionary=I2Results.validate_world(world,discoveries)
	if not valid.get("ok",false): return {"ok":false,"code":"original_I2_physical_boundary:"+str(valid.get("error",""))}
	for flag: String in ["I2:region_route_open","campaign_boss:I2","F2:clock_path_restored","F2:chapter_decision_saved"]:
		if not world.get("flags",{}).get(flag,false): return {"ok":false,"code":"actual_original_I2_F2_investigation_required:"+flag}
	for finding: String in ["boss:I2:twin_pump_guardian","I2:operation_record","F2:contradictory_records","F2:aligned_timeline"]:
		if discoveries.count(finding)!=1: return {"ok":false,"code":"original_unique_source_findings_required:"+finding}
	if state.get("choices",{}).get("F2:mirror_evidence:decision")!="publish_context": return {"ok":false,"code":"original_default_publish_context_source_required"}
	var envelope: Variant=world.get("environment",{}).get("campaign_F2")
	if not envelope is Dictionary or envelope.get("version")!=1 or not envelope.get("mechanisms") is Dictionary or not envelope.get("encounter") is Dictionary or not envelope.get("observed") is bool: return {"ok":false,"code":"original_F2_physical_envelope_required"}
	var proof: Dictionary=envelope.mechanisms
	if not proof.get("readings",{}).has("F2:record_low") or not proof.get("readings",{}).has("F2:record_high") or not proof.get("histories",{}).has("F2:clock_light_path"): return {"ok":false,"code":"original_two_record_and_reflection_history_required"}
	if not envelope.encounter.is_empty():
		var checker=Encounter.new()
		if not checker.configure("mirrorwing_warden").get("ok",false) or not checker.validate_snapshot(envelope.encounter).get("ok",false): return {"ok":false,"code":"original_F2_encounter_snapshot_rejected"}
	if ENGAGE in completed and (not envelope.observed or envelope.encounter.is_empty()): return {"ok":false,"code":"actual_original_full_attack_cycle_required"}
	var stopped: bool=STOP in completed
	var committed: bool=world.get("flags",{}).get("campaign_boss:F2",false)
	if committed!=envelope.encounter.get("state",{}).get("completed",false) or world.get("flags",{}).get("F2:boss_stopped",false)!=stopped or discoveries.count(REWARD)!=(1 if committed else 0): return {"ok":false,"code":"original_F2_victory_result_mismatch"}
	if stopped and not committed: return {"ok":false,"code":"original_committed_two_phase_encounter_required"}
	if discoveries.count("F2:operation_record")!=(1 if RECORD in completed else 0) or world.get("flags",{}).get("F2:region_route_open",false)!=(RECORD in completed): return {"ok":false,"code":"original_F2_record_result_mismatch"}
	return {"ok":true,"code":"legal_natural_F2_Boss_prefix","source_receipts_sha256":FORTYSIX_DIGEST,"completed":completed.duplicate()}

func run(owner_session: Node,options: Dictionary={}) -> Dictionary:
	if not _bound(): return {"ok":false,"code":"actual_F2Investigation46_source_not_bound"}
	if running or stopping or finished: return {"ok":false,"code":"already_started"}
	session=owner_session
	output=str(options.get("output","")).replace("\\","/")
	max_seconds=float(options.get("max_seconds",600))
	stop_after=str(options.get("stop_after","complete"))
	if not is_instance_valid(session) or not is_inside_tree() or options.get("profile")!=SOURCE_PROFILE or session.store.root_path!="user://profiles_v3/"+SOURCE_PROFILE or not _output_valid(output) or not is_finite(max_seconds) or max_seconds<60 or max_seconds>600 or stop_after not in STAGES: return {"ok":false,"code":"mounted_same_profile_new_output_and_bound_required"}
	initial=session.store.snapshot()
	if not SourceBinding.start_matches(_source_binding,initial): return {"ok":false,"code":"source_binding_initial_snapshot_changed"}
	var verified: Dictionary=_source_check(initial)
	if not verified.ok: return verified
	initial_digest=str(verified.source_receipts_sha256)
	if options.get("source_profile_id")!=initial.profile_id or options.get("source_lineage_id")!=initial.lineage_id or options.get("source_receipts_sha256")!=initial_digest: return {"ok":false,"code":"preflight_source_identity_or_receipts_changed"}
	if DirAccess.make_dir_recursive_absolute(output.get_base_dir())!=OK: return {"ok":false,"code":"output_directory_unavailable"}
	OS.add_logger(logger)
	started_usec=Time.get_ticks_usec()
	process_mode=Node.PROCESS_MODE_ALWAYS
	process_physics_priority=10
	running=true
	_execute.call_deferred()
	return {"ok":true,"code":"observing_natural_F2_Boss","stop_after":stop_after}

func _execute() -> void:
	if not _check(session.profile_ready and not session.active and not OS.has_feature("editor"),"actual exported MAIN before ordinary same-profile menu continuation"): _stop("exported_normal_menu_required"); return
	last_completed=initial.world.actions.opening.completed.duplicate()
	session._ui_action("solo",{"frame":0})
	await _next()
	if not _healthy() or not _check(_receipts_digest(session.story.state,SOURCE_GOALS)==initial_digest,"ordinary menu preserves every actual46 source receipt",_status()): _stop("ordinary_source_resume_failed"); return
	if not await _dismiss_radio(): _stop("source_radio_not_closed"); return
	if session.region_id=="I2":
		if not _check(session._can_travel_to("F2"),"ordinary original travel still permits F2"): _stop("ordinary_F2_travel_locked"); return
		_press_key(KEY_M)
		await _next()
		if not _check(session.interface.travel.visible,"ordinary M opens the I2 travel panel"): _stop("ordinary_travel_panel_missing"); return
		session._ui_action("travel_to",{"region_id":"F2"})
		var travel_deadline: float=minf(max_seconds-20.0,_elapsed()+35.0)
		while _live() and session.region_id!="F2" and _elapsed()<travel_deadline: await _next()
	if not _check(_live() and session.region_id=="F2" and session.campaign.supported() and session.world.build_errors.is_empty(),"ordinary F2 scene loads its real original campaign"): _stop("ordinary_F2_factory_unavailable"); return
	if not await _dismiss_radio(): _stop("arrival_radio_not_closed"); return
	_bind_pilot()
	route=_route_definition()
	if not _check(not route.is_empty(),"real briefing/entry/emitter/core/record and unflown high patrol lane are available",route): _stop("actual_F2_Boss_route_unavailable"); return
	inherited_victory=session.campaign.victory_committed()
	if inherited_victory and not _completed(STOP):
		if not await _wait_completed(STOP,5.0): _stop("inherited_committed_victory_not_projected_by_original_Story"); return
	if not _completed(STOP):
		if not _completed(PLAN):
			if not await _navigate([Vector3(_body().global_position.x,route.altitude,_body().global_position.z),route.briefing_high,route.briefing],"original_south_safe_briefing"): _stop("normal_briefing_flight_unproven"); return
			if not await _contact("F2:boss_briefing",PLAN): _stop("normal_plan_G_unproven"); return
			if not _check(not session.campaign.active() and _body().global_position.z>float(route.entry_z),"actual G plan remains south of the original entry line",_status()): _stop("plan_started_Boss_before_actual_entry"); return
		else: _event("inherited_original_plan",{"receipt":_receipt_for(PLAN),"encounter":_boss_state()})
		if _stage("plan"): return
		if not await _dismiss_radio(): _stop("plan_radio_not_closed"); return
		if not session.campaign.active():
			if not await _enter_actual_arena(): _stop("actual_flown_entry_unproven"); return
		else:
			# A legitimate saved battle resumes at the game's ordinary spawn.
			# This candidate flies a lateral rising leg before the northward leg;
			# saved attacks keep running and may still defeat this approach.
			if not await _resume_active_approach(): _stop("resumed_battle_flight_unproven"); return
		if not await _power_actual_reveal(): _stop("separate_Boss_emitter_or_true_body_shadow_unproven"); return
		var observed_deadline: float=minf(max_seconds-20.0,_elapsed()+20.0)
		while _healthy() and not _completed(ENGAGE) and _elapsed()<observed_deadline: await _next()
		if not _check(_completed(ENGAGE) and session.campaign.observed,"original actual full warning-active-recovery cycle durably projects engage",_status()): _stop("actual_full_cycle_unproven"); return
		if _stage("engage"): return
		if not await _fight():
			if not stopping: _stop("actual_normal_F2_battle_incomplete")
			return
		if stopping: return
	else:
		inherited_victory=true
		phase_two_observed=int(_boss_state().get("phase",0))==2
		_event("inherited_original_committed_two_phase_victory",{"receipt":_receipt_for(STOP),"state":_boss_state(),"note":"No new firing or damage is claimed for this inherited valid original victory."})
		for value: String in ["plan","engage","half"]:
			if _stage(value): return
	if _stage("stop"): return
	if not await _dismiss_radio(): _stop("victory_radio_not_closed"); return
	if not _completed(RECORD):
		if not await _navigate([Vector3(_body().global_position.x,route.altitude,_body().global_position.z),route.record_high,route.record],"actual_stopped_core_record"): _stop("post_Boss_record_flight_unproven"); return
		if not await _contact("F2:boss_record",RECORD): _stop("original_post_Boss_G_record_unproven"); return
	else: _event("inherited_original_post_Boss_record",{"receipt":_receipt_for(RECORD)})
	if not _check(session.story.state.completed==EXPECTED and _receipts_digest(session.story.state,SOURCE_GOALS)==initial_digest and session.campaign.victory_committed() and not session.boss_active,"only four actual Boss goals extend unchanged46 source receipts",_status()): _stop("final50_prefix_unproven"); return
	_stage("complete")

func _route_definition() -> Dictionary:
	var brief: Vector3=_v(session.story.markers.get("F2:boss_briefing",{}).get("position"))
	var record: Vector3=_v(session.story.markers.get("F2:boss_record",{}).get("position"))
	var entry: float=float(session.campaign._entry_z)
	var centre: Vector3=session.world.campaign_arena.centre()
	var altitude: float=minf(18.0,float(_body().max_altitude)-.5)
	if not brief.is_finite() or not record.is_finite() or not centre.is_finite() or not is_finite(entry) or altitude<16.0 or brief.z<=entry+.1: return {}
	for id: String in [REVEAL_SOURCE,"F2:shadow_receiver"]:
		if not session.world.objects.has(id) or not session.entities.has(id): return {}
	for part: String in ["true_left_wing","true_right_wing","core"]:
		if not session.world.campaign_arena.targets.has(session.world.campaign_arena.target_id(part)): return {}
	var safe_brief: Vector3=brief+Vector3(0,.1,1.7)
	return {"altitude":altitude,"entry_z":entry,"centre":centre,"briefing":safe_brief,"briefing_high":Vector3(brief.x,altitude,safe_brief.z),
		"entry_high":Vector3(centre.x,altitude,entry-1.0),"patrol_z":entry+2.0,"patrol_extent":8.0,
		"record":record+Vector3.UP*.1,"record_high":Vector3(record.x,altitude,record.z),
		"source":_target_position(REVEAL_SOURCE),"note":"Unflown candidate only. Entire hull/real Pilot sweep/real ray gates remain authoritative. Entry stops waiting as soon as the actual original Boss starts, then actual lateral patrol starts immediately."}

func _enter_actual_arena() -> bool:
	if not await _navigate([Vector3(_body().global_position.x,route.altitude,_body().global_position.z),route.briefing_high],"south_airlane_before_actual_entry"): return false
	_phase("continuous_native_cross_entry_no_static_lance_wait")
	command_serial+=1
	if not _hull_clear(route.entry_high) or not pilot.go_to(route.entry_high,command_serial): return _check(false,"real entry waypoint is clear and accepted")
	navigating=true
	var deadline: float=minf(max_seconds-20.0,_elapsed()+20.0)
	while _healthy() and not session.campaign.active() and _elapsed()<deadline: await _next()
	navigating=false
	last_patrol_target=Vector3.INF
	patrol_enabled=true
	return _check(session.campaign.active() and session.boss_active and _body().global_position.z<=float(route.entry_z),"ordinary native flight actually crosses entry before original Boss activation",_status())

func _resume_active_approach() -> bool:
	_phase("ordinary_spawn_continuous_zigzag_to_saved_active_Boss")
	patrol_approach=true
	patrol_enabled=true
	last_patrol_target=Vector3.INF
	var deadline: float=minf(max_seconds-20.0,_elapsed()+180.0)
	var best_z: float=_body().global_position.z
	var last_progress: float=_elapsed()
	while _healthy() and _elapsed()<deadline and (_body().global_position.z>float(route.patrol_z)+.6 or _body().global_position.y<float(route.altitude)-.4):
		await _next()
		if _body().global_position.z<best_z-.5:
			best_z=_body().global_position.z
			last_progress=_elapsed()
		if _elapsed()-last_progress>30.0:
			patrol_approach=false
			return _check(false,"saved active battle approach makes real northward progress",_status())
	patrol_approach=false
	last_patrol_target=Vector3.INF
	return _check(_healthy() and _body().global_position.z<=float(route.patrol_z)+.6 and _body().global_position.y>=float(route.altitude)-.4,"ordinary spawn reaches the real active arena by continuous swept zigzag flight",_status())

func _power_actual_reveal() -> bool:
	_phase("normal_4_Tab_F_separate_Boss_reveal_emitter")
	patrol_enabled=true
	var initial_sample: Dictionary=session.campaign.mechanisms.boss_environment("F2")
	reveal_observations.append(_plain({"kind":"before","environment":initial_sample,"ray":_reveal_ray(),"position":_body().global_position,"source_entity":session.entities[REVEAL_SOURCE]}))
	if not initial_sample.get("true_body_revealed",false) or not initial_sample.get("shadow_verified",false):
		# Wait for the real moving patrol to supply <=16m and first-hit LOS.
		var deadline: float=minf(max_seconds-20.0,_elapsed()+20.0)
		while _healthy() and _elapsed()<deadline and (_body().global_position.distance_to(_target_position(REVEAL_SOURCE))>15.8 or _first_hit_from(_body().global_position,REVEAL_SOURCE).get("entity_id")!=REVEAL_SOURCE): await _next()
		if not _check(_body().global_position.distance_to(_target_position(REVEAL_SOURCE))<=16.0,"ordinary patrol reaches original light range",_status()): return false
		if not await _cast(REVEAL_SOURCE,"light",KEY_4): return false
	var deadline: float=minf(max_seconds-20.0,_elapsed()+5.0)
	var sample: Dictionary=session.campaign.mechanisms.boss_environment("F2")
	while _healthy() and _elapsed()<deadline and (not sample.get("true_body_revealed",false) or not sample.get("shadow_verified",false)):
		await _next()
		sample=session.campaign.mechanisms.boss_environment("F2")
	var ray: Dictionary=_reveal_ray()
	reveal_observations.append(_plain({"kind":"powered_actual_Boss_ray","environment":sample,"ray":ray,"source_entity":session.entities[REVEAL_SOURCE],"position":_body().global_position,"seconds":_elapsed()}))
	return _check(sample.get("true_body_revealed",false) and sample.get("shadow_verified",false) and ray.get("entity_id")==session.world.campaign_arena.target_id("core") and float(session.entities[REVEAL_SOURCE].get("light_level",0))>=.5,"separate sustained emitter ray actually hits the collidable true core before its shadow receiver",{"sample":sample,"ray":ray})

func _reveal_ray() -> Dictionary:
	var source: Variant=session.world.objects.get(REVEAL_SOURCE)
	var receiver: Variant=session.world.objects.get("F2:shadow_receiver")
	if not source is PhysicsBody3D or not receiver is Node3D: return {"code":"missing_actual_reveal_bodies"}
	var query:=PhysicsRayQueryParameters3D.create(source.global_position,receiver.global_position,1|8)
	query.exclude=[source.get_rid()]
	var hit: Dictionary=session.world.get_world_3d().direct_space_state.intersect_ray(query)
	return {"entity_id":str(hit.collider.get_meta("entity_id","")),"collider":str(hit.collider.get_path()),"position":hit.position,"from":source.global_position,"to":receiver.global_position} if not hit.is_empty() else {"entity_id":"","from":source.global_position,"to":receiver.global_position}

func _fight() -> bool:
	_phase("actual_held_weapon_two_phase_reverse_order")
	patrol_enabled=true
	var observed_damage_count: int=damage_samples.size()
	var last_progress: float=_elapsed()
	while _healthy() and _elapsed()<max_seconds-20.0:
		var state: Dictionary=_boss_state()
		if session.campaign.victory_committed():
			wanted_fire=false
			_set_fire(false)
			patrol_enabled=false
			if not await _wait_completed(STOP,5.0): return false
			damage_evidence=_damage_evidence()
			return _check(state.get("completed",false) and phase_two_observed and damage_evidence.get("ok",false),"actual held weapon damage chain and original Store publish a real two-phase stopped Boss",{"state":state,"evidence":damage_evidence})
		if state.is_empty(): return _check(false,"actual entered Encounter remains present",_status())
		if damage_samples.size()!=observed_damage_count:
			observed_damage_count=damage_samples.size()
			last_progress=_elapsed()
		if _elapsed()-last_progress>35.0: return _check(false,"actual normal weapon/LOS/window route makes HP progress within 35 seconds",{"status":_status(),"state":state,"last_first_hit":_first_hit_from(_body().global_position,fire_target) if not fire_target.is_empty() else {}})
		if int(state.get("phase",0))==2 and "half" not in reached_stages:
			phase_two_observed=true
			reveal_observations.append(_plain({"kind":"phase2_actual_reveal_sample","environment":session.campaign.mechanisms.boss_environment("F2"),"ray":_reveal_ray(),"seconds":_elapsed()}))
			if _stage("half"): return false
		var environment: Dictionary=session.campaign.mechanisms.boss_environment("F2")
		if not environment.get("true_body_revealed",false) or not environment.get("shadow_verified",false):
			wanted_fire=false
			_set_fire(false)
			if not await _power_actual_reveal(): return false
			continue
		var part: String=session.campaign.encounter.current_part()
		var target: String=session.world.campaign_arena.target_id(part)
		if target!=fire_target:
			wanted_fire=false
			_set_fire(false)
			if not await _select_target(target): return false
			fire_target=target
		wanted_fire=true
		await _next()
	return _check(false,"bounded normal flight/light/held weapon route reaches real victory",_status())

func _patrol() -> void:
	if not patrol_enabled or navigating or route.is_empty() or not session.campaign.active(): return
	var state: Dictionary=_boss_state()
	var attack: Dictionary=state.get("attack",{})
	var locked: bool=state.get("attack_stage") in ["warning","active"] and attack.get("pattern_id")=="mirror_lance"
	var target: Vector3=last_patrol_target
	if locked:
		var token: String=str(attack.get("token",""))
		if token!=patrol_warning_token:
			patrol_warning_token=token
			var shape: Dictionary=attack.get("shapes",[])[0] if not attack.get("shapes",[]).is_empty() else {}
			var locked_x: float=float(shape.get("centre_mm",[0,0,0])[0])/1000.0
			var vx: float=_native_velocity().x
			patrol_side=signf(vx) if absf(vx)>.35 else (1.0 if _body().global_position.x<=locked_x else -1.0)
			var target_z: float=maxf(float(route.patrol_z),_body().global_position.z-3.0) if patrol_approach else float(route.patrol_z)
			target=Vector3(locked_x+patrol_side*6.0,route.altitude,target_z)
			_event("actual_lance_locked_then_continuous_lateral_command",{"token":token,"shape":shape,"native_velocity":_native_velocity(),"target":target,"position":_body().global_position})
	else:
		if not last_patrol_target.is_finite() or absf(_body().global_position.x)>float(route.patrol_extent)-1.0:
			patrol_side=-1.0 if _body().global_position.x>0.0 else 1.0
		var target_x: float=patrol_side*float(route.patrol_extent)
		if not last_patrol_target.is_finite() or not is_equal_approx(target_x,last_patrol_target.x):
			var target_z: float=maxf(float(route.patrol_z),_body().global_position.z-6.0) if patrol_approach else float(route.patrol_z)
			target=Vector3(target_x,route.altitude,target_z)
	if target!=last_patrol_target:
		if not target.is_finite() or absf(target.x)>30.0 or not _hull_clear(target):
			_check(false,"actual patrol target stays inside clear ordinary airlane",{"target":target,"status":_status()})
			_stop("actual_patrol_candidate_blocked")
			return
		last_patrol_target=target
		command_serial+=1
		if not pilot.go_to(target,command_serial):
			_check(false,"ordinary Pilot accepts real patrol command",target)
			_stop("actual_patrol_command_rejected")

func _observe_combat() -> void:
	var state: Dictionary=_boss_state()
	if state.is_empty(): return
	var attempt: int=int(state.get("attempt",-1))
	if original_attempt<0:
		original_attempt=attempt
		battle_baseline=state.duplicate(true)
		last_observed_shots=int(session.stats.shots)
	if attempt!=original_attempt:
		_check(false,"normal candidate does not silently turn a full-wipe retry into the original attempt",{"initial_attempt":original_attempt,"actual_attempt":attempt})
		_stop("actual_attempt_reset")
		return
	phase_two_observed=phase_two_observed or int(state.get("phase",0))==2
	var current: String=session.campaign.encounter.current_part()
	var part_key: String=str(state.get("phase",0))+":"+current
	if part_key!=last_part_key:
		last_part_key=part_key
		part_visits.append(_plain({"phase":int(state.phase),"part":current,"parts":state.parts,"core_hp_milli":int(state.core_hp_milli),"seconds":_elapsed()}))
	var key: String=JSON.stringify([state.get("attempt"),state.get("phase"),state.get("attack_stage"),state.get("attack",{}).get("token"),state.get("parts"),state.get("core_hp_milli"),_body().health])
	if key!=last_combat_key:
		last_combat_key=key
		var row: Dictionary={"seconds":_elapsed(),"state":state,"actual_position":_body().global_position,"native_velocity":_native_velocity(),"shots":session.stats.shots,"health":_body().health,"environment":session.campaign.mechanisms.boss_environment("F2")}
		combat_transitions.append(_plain(row))
		_event("actual_combat_transition",row)
	if not last_boss.is_empty():
		for part: String in ["true_left_wing","true_right_wing","core"]:
			var before: int=int(last_boss.get("core_hp_milli",0)) if part=="core" else int(last_boss.get("parts",{}).get(part,0))
			var after: int=int(state.get("core_hp_milli",0)) if part=="core" else int(state.get("parts",{}).get(part,0))
			if after<before:
				var row: Dictionary={"seconds":_elapsed(),"part":part,"before":before,"after":after,"drop":before-after,"damage_phase":int(last_boss.phase),"result_phase":int(state.phase),"shots_before":last_observed_shots,"shots_after":int(session.stats.shots),"position":_body().global_position}
				damage_samples.append(_plain(row))
				if int(session.stats.shots)<=last_observed_shots:
					_check(false,"every observed Boss HP drop follows an actual original weapon shot",row)
					_stop("Boss_HP_drop_without_actual_shot")
					return
	last_boss=state.duplicate(true)
	last_observed_shots=int(session.stats.shots)

func _damage_evidence() -> Dictionary:
	if battle_baseline.is_empty(): return {"ok":false,"code":"missing_actual_battle_baseline"}
	var totals: Dictionary={}
	for row: Dictionary in damage_samples:
		var key: String=str(row.damage_phase)+":"+str(row.part)
		totals[key]=int(totals.get(key,0))+int(row.drop)
	var half: int=int(session.campaign.definition.core_hp_milli)>>1
	var baseline_phase: int=int(battle_baseline.phase)
	var expected: Dictionary={}
	if baseline_phase==1:
		for part: String in ["true_left_wing","true_right_wing"]: expected["1:"+part]=int(battle_baseline.parts[part])
		expected["1:core"]=int(battle_baseline.core_hp_milli)-half
		for part: String in ["true_left_wing","true_right_wing"]: expected["2:"+part]=int(session.campaign.definition.part_hp_milli)
		expected["2:core"]=half
	else:
		for part: String in ["true_left_wing","true_right_wing"]: expected["2:"+part]=int(battle_baseline.parts[part])
		expected["2:core"]=int(battle_baseline.core_hp_milli)
	var valid: bool=baseline_phase in [1,2] and not damage_samples.is_empty()
	for key: String in expected:
		var amount: int=int(totals.get(key,0))
		# Exposure timeout legitimately rearms wings. Core never heals: exact
		# observed drops include half clamp/final zero, never assume 9 per shot.
		valid=valid and (amount==int(expected[key]) if key.ends_with(":core") else amount>=int(expected[key]))
	var phase2_right_seen := false
	for row: Dictionary in part_visits:
		if int(row.phase)==2 and row.part=="true_right_wing": phase2_right_seen=true
	if baseline_phase==1 or int(battle_baseline.parts.get("true_right_wing",0))>0: valid=valid and phase2_right_seen
	return {"ok":valid,"totals":totals,"required_remaining_from_actual_baseline":expected,"phase2_reverse_right_seen":phase2_right_seen,"baseline_phase":baseline_phase,"note":"HP deltas follow observed before->after chains and actual shot counters. No fixed request-damage/count assertion; partial original snapshots retain earlier evidence."}

func _mechanisms_debug() -> Dictionary:
	if not _live() or session.region_id!="F2" or session.campaign.mechanisms==null: return {}
	return {"boss_environment":session.campaign.mechanisms.boss_environment("F2"),"actual_reveal_ray":_reveal_ray(),"source_entity":session.entities.get(REVEAL_SOURCE,{}).duplicate(true),"separate_puzzle_fact":session.campaign.mechanisms.fact("F2:clock_light_path"),"current_Boss_state":_boss_state()}

func _cast(target: String, ability: String, keycode: Key) -> bool:
	if not await _dismiss_radio(): return false
	_press_key(keycode)
	if not _check(session.selected_ability==ability,"normal ability key selects "+ability): return false
	for _index: int in range(session.entities.size()+2):
		if str(session.locks.get(1,""))==target: break
		_press_key(KEY_TAB)
		await _next()
		if not _healthy(): return false
	if not _check(str(session.locks.get(1,""))==target,"normal Tab selects the actual mechanism "+target,_status()): return false
	var cost: float = float(AbilityRules.DEFINITIONS[ability].energy)
	var ability_range: float=float(AbilityRules.DEFINITIONS[ability].range)
	var deadline: float = minf(max_seconds-20.0,_elapsed()+20.0)
	while _healthy() and (float(session.cooldowns.get(1,0))>0 or float(session.entities[session._actor_id(1)].energy)<cost or _body().global_position.distance_to(_target_position(target))>ability_range-.25 or _first_hit_from(_body().global_position,target).get("entity_id")!=target) and _elapsed()<deadline: await _next()
	if not _healthy(): return false
	if not _check(float(session.cooldowns.get(1,0))<=0 and float(session.entities[session._actor_id(1)].energy)>=cost and _body().global_position.distance_to(_target_position(target))<=ability_range,"after real Tab selection, ordinary patrol supplies actual ability range/energy/cooldown before F",_status()): return false
	var ray: Dictionary = _first_hit_from(_body().global_position,target)
	if not _check(ray.get("entity_id")==target,"actual complete first-hit ray reaches "+target,ray): return false
	var before: int = int(session.stats.abilities)
	var before_entity: Dictionary = session.entities[target].duplicate(true)
	_press_key(KEY_F)
	var accepted: bool = int(session.stats.abilities)==before+1
	var row: Dictionary = {"seconds":_elapsed(),"ability":ability,"target":target,"accepted":accepted,"actor_position":_body().global_position,"before":before_entity,"after":session.entities[target].duplicate(true),"ray":ray}
	actual_abilities.append(_plain(row))
	await _next()
	return _check(accepted,"original normal F/Rules/Registry accepts "+ability+" on "+target,row)


func _wait_completed(objective: String, seconds: float) -> bool:
	var deadline: float=minf(max_seconds-10.0,_elapsed()+seconds)
	while _healthy() and not _completed(objective) and _elapsed()<deadline: await _next()
	return _check(_completed(objective),"original Story/Store completes "+objective,{"status":_status(),"receipt":_receipt_for(objective)})

func _boss_state() -> Dictionary:
	return session.campaign.encounter.get_state() if _live() and session.campaign.supported() else {}

func _physics_process(delta: float) -> void:
	if not running or stopping or not _live() or session.simulation_paused: return
	physics_frames+=1
	var body: FlightBodyV2=_body()
	if last_body_id==body.get_instance_id() and last_region==session.region_id:
		var moved: float=previous_position.distance_to(body.global_position)
		actual_distance+=moved
		max_frame_distance=maxf(max_frame_distance,moved)
		if moved>2.0:
			_check(false,"ordinary flight has no unexplained per-tick pose jump",{"distance":moved,"previous":previous_position,"current":body.global_position})
			_stop("unexplained_pose_jump")
			return
	last_body_id=body.get_instance_id()
	last_region=session.region_id
	previous_position=body.global_position
	_observe_combat()
	if stopping: return
	if pilot!=null:
		_patrol()
		pilot.tick(delta,true,false)
	var part: String=session.campaign.encounter.current_part() if session.campaign.supported() else ""
	var open: bool=session.campaign.active() and session.campaign.encounter.part_open(part)
	var ray: Dictionary=_first_hit_from(_body().global_position,fire_target) if wanted_fire else {}
	var may_fire: bool=wanted_fire and open and fire_target==session.world.campaign_arena.target_id(part) and str(session.locks.get(1,""))==fire_target and _body().global_position.distance_to(_target_position(fire_target))<=36.0 and ray.get("entity_id")==fire_target
	var observation: String=JSON.stringify([part,open,may_fire,ray.get("entity_id","") if wanted_fire else "not_requested"])
	if wanted_fire and observation!=last_fire_observation:
		last_fire_observation=observation
		_event("actual_weapon_window_and_first_hit",{"part":part,"open":open,"actual_locked":session.locks.get(1,""),"may_hold_fire":may_fire,"first_hit":ray,"position":_body().global_position})
	_set_fire(may_fire)

func _select_target(target: String) -> bool:
	for _index: int in range(session.entities.size()+2):
		if str(session.locks.get(1,""))==target: return true
		_press_key(KEY_TAB)
		await _next()
		if not _healthy(): return false
	return _check(false,"normal Tab reaches actual target",{"wanted":target,"actual":session.locks.get(1,"")})


func _set_fire(pressed: bool) -> void:
	if managed_fire==pressed: return
	managed_fire=pressed
	if pressed: Input.action_press("flight_fire")
	else: Input.action_release("flight_fire")


func _press_key(keycode: Key) -> void:
	var key := InputEventKey.new()
	key.pressed=true
	key.physical_keycode=keycode
	key.keycode=keycode
	session._unhandled_input(key)


static func _v(value: Variant) -> Vector3:
	if not value is Array or value.size()!=3: return Vector3.INF
	for number: Variant in value:
		if not (number is float or number is int) or not is_finite(float(number)): return Vector3.INF
	return Vector3(value[0],value[1],value[2])


func _contact(target: String, objective: String) -> bool:
	_phase("normal_G:"+target)
	if not await _dismiss_radio(): return false
	var deadline: float = minf(max_seconds-10.0,_elapsed()+8.0)
	var next_press := 0.0
	while _healthy() and objective not in session.story.state.get("completed",[]) and _elapsed()<deadline:
		if _elapsed()>=next_press:
			var nearest: String = session.story.nearest(_body().global_position)
			if not _check(nearest==target,"normal nearest G resolves "+target,{"actual":nearest,"expected":target,"position":_body().global_position}): return false
			_record_g(target)
			next_press=_elapsed()+.6
		await _next()
	return _check(objective in session.story.state.get("completed",[]),"original near/LOS G commits "+objective,_status())


static func _output_valid(path: String) -> bool:
	return path.is_absolute_path() and "://" not in path and ".." not in path and "\n" not in path and "\r" not in path and path.get_file().begins_with("normal-f2-boss-") and path.get_extension() == "json" and not FileAccess.file_exists(path) and not DirAccess.dir_exists_absolute(path)


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
	navigating=true
	last_patrol_target=Vector3.INF
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
			if distance<.22 and _body().linear_velocity.length()<.22: break
			if distance<best_distance-.12:
				best_distance=distance
				last_progress=_elapsed()
			if _elapsed()-last_progress>12.0: return _check(false,"ordinary Pilot makes real route progress",{"label":label,"goal":goal,"pilot":pilot.report(),"status":_status(),"classification":"bounded_driver_route_stall"})
		if not _healthy() or not _check(distance<.22 and _body().linear_velocity.length()<.22,"continuous native flight reaches "+label,{"goal":goal,"position":_body().global_position,"pilot":pilot.report()}): return false
	navigating=false
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


func _target_position(target: String) -> Vector3:
	var value: Variant = session.entities.get(target,{}).get("position")
	return value if value is Vector3 else Vector3.INF


func _first_hit_from(point: Vector3, target: String) -> Dictionary:
	var finish: Vector3 = _target_position(target)
	if not point.is_finite() or not finish.is_finite(): return {"entity_id":"","code":"missing_actual_target_position"}
	var query := PhysicsRayQueryParameters3D.create(point,finish,0xFFFFFFFF)
	query.exclude=[_body().get_rid()]
	var hit: Dictionary = session.world.get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty(): return {"entity_id":"","code":"no_first_hit","target":target,"from":point,"to":finish}
	return {"entity_id":str(hit.collider.get_meta("entity_id","")),"collider":str(hit.collider.get_path()),"position":hit.position,"target":target,"from":point,"to":finish}


func _record_g(target: String) -> void:
	var before: Dictionary = {"generation":session.store.snapshot().get("generation"),"completed":session.story.state.get("completed",[]).duplicate(),"proposal":session.consensus.current_proposal()}
	_press_g()
	actual_interactions.append(_plain({"seconds":_elapsed(),"target":target,"actor_position":_body().global_position,"before":before,"after_generation":session.store.snapshot().get("generation"),"after_proposal":session.consensus.current_proposal(),"message":session.interface.message.text}))


func _completed(id: String) -> bool:
	return id in session.story.state.get("completed",[])


func _receipt_for(objective: String) -> Dictionary:
	for value: Variant in session.story.state.get("receipts",{}).values():
		if value is Dictionary and value.get("objective_id")==objective: return value.duplicate(true)
	return {}


func _flush_report() -> bool:
	var file := FileAccess.open(output,FileAccess.WRITE)
	if file==null: return false
	file.store_string(JSON.stringify(report_cache,"\t",true,true))
	file.flush()
	return file.get_error()==OK


func _native_exit_watchdog() -> void:
	# A timer created in a synchronous cold-load frame can receive that frame's
	# old delta. Count only real monotonic time after the original quit request.
	var deadline_usec: int = Time.get_ticks_usec()+8000000
	while is_inside_tree() and Time.get_ticks_usec()<deadline_usec:
		await get_tree().process_frame
	if not is_inside_tree() or not native_exit_requested or report_cache.is_empty(): return
	report_cache["complete"]=false
	report_cache["f2_boss_segment_complete"]=false
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
	print("NORMAL_F2_BOSS_EXIT_WATCHDOG_FAIL "+JSON.stringify(report_cache.native_exit))
	# Do not use tree.quit/OS.kill as a fallback around a rejected Store gate.
	# The runner's already bounded private Job remains the external hard limit.


func _exit_tree() -> void:
	_set_fire(false)
	if not native_exit_requested or report_cache.is_empty(): return
	report_cache["native_exit"]["observed_scene_exit"]=true
	if is_instance_valid(session):
		report_cache["native_exit"]["audio"]=_plain(session.last_audio_shutdown_result)
		if not session.last_audio_shutdown_result.get("ready",false):
			report_cache["complete"]=false
			report_cache["f2_boss_segment_complete"]=false
			report_cache["requested_stage_stopped"]=false
			report_cache["failures"].append("Original final-exit audio drain did not become ready.")
	report_cache["engine_errors"]=_plain(logger.errors)
	if not logger.errors.is_empty():
		report_cache["complete"]=false
		report_cache["f2_boss_segment_complete"]=false
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
	print("NORMAL_F2_BOSS_EVENT "+JSON.stringify(row))


func _check(ok: bool, label: String, detail: Variant = null) -> bool:
	checks.append({"passed":ok,"label":label,"detail":_plain(detail)})
	if not ok: failures.append(label)
	return ok


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
		print("NORMAL_F2_BOSS_PROGRESS "+JSON.stringify(_plain(row)))


func _status() -> Dictionary:
	if not is_instance_valid(session): return {"session_valid":false}
	var result: Dictionary = {"region":session.region_id,"active":session.active,"paused":session.simulation_paused,"boss_active":session.boss_active,"pending_completion":session.pending_completion,"completed":session.story.state.get("completed",[]).duplicate(),"message":session.interface.message.text,"last_commit":session.last_commit_result,"proposal":session.consensus.current_proposal(),"generation":session.store.snapshot().get("generation")}
	if _live():
		result["position"]=_body().global_position
		result["velocity"]=_body().linear_velocity
		result["native_velocity"]=_native_velocity()
		result["health"]=_body().health
		result["enabled"]=_body().enabled
		result["collision_count"]=_body().collision_count
		result["nearest_G"]=session.story.nearest(_body().global_position)
		result["mechanisms"]=_mechanisms_debug()
		result["pilot"]=pilot.report() if pilot!=null else {}
	return result


func _stage(value: String) -> bool:
	if value not in reached_stages: reached_stages.append(value)
	_event("actual_stage_observed",{"stage":value,"state":_mechanisms_debug(),"status":_status()})
	if stop_after==value:
		_stop("normal_f2_boss_complete" if value=="complete" else "requested_stage_pause")
		return true
	return false


func _stop(reason: String) -> void:
	if stopping or finished: return
	wanted_fire=false
	_set_fire(false)
	patrol_enabled=false
	stopping=true
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
	preservation["original_physical_histories_resumed"]=true
	if not preserved: _check(false,"fresh original reader retains a legal same-source prefix",final_reader)
	if not saved_now: _check(false,"ordinary SaveGate succeeds before bounded QA stop",preservation)
	if saved_now and not matches_live: _check(false,"fresh original reader exactly matches actual live Story",final_reader)
	var complete: bool = reason=="normal_f2_boss_complete" and failures.is_empty() and logger.errors.is_empty() and preserved and saved_now and matches_live and saved.world.actions.opening.completed==EXPECTED
	var stage_stopped: bool = reason=="requested_stage_pause" and stop_after in reached_stages and failures.is_empty() and logger.errors.is_empty() and preserved and saved_now and matches_live and preservation.common_paused
	if complete:
		for reward: String in [REWARD,"F2:operation_record"]:
			_check(saved.personal.discoveries.count(reward)==1,"original Boss reward/record is unique and durable: "+reward,saved.personal.discoveries)
		_check(saved.world.environment.I2_water.history.commissioned,"original commissioned clinic history remains durable after isolated Boss water")
		complete=failures.is_empty()
	_write_report(reason,complete,stage_stopped)

func _write_report(reason: String,complete: bool,stage_stopped: bool) -> void:
	finished=true
	running=false
	var report: Dictionary={"complete":complete,"f2_boss_segment_complete":complete,"requested_stage_stopped":stage_stopped,"requested_stage":stop_after,"reached_stages":reached_stages,"stop_reason":reason,"phase":phase,"seconds":_elapsed(),"max_seconds":max_seconds,"profile":SOURCE_PROFILE,"user_dir":OS.get_user_data_dir(),"executable":OS.get_executable_path(),"exported_application":not OS.has_feature("editor"),"runtime_cwd":DirAccess.open(".").get_current_dir(),"source_generation":initial.get("generation"),"initial_completed":initial.world.actions.opening.completed,"source_report_sha256":SOURCE_REPORT_SHA256,"source_receipts_sha256":initial_digest,"physics_frames":physics_frames,"actual_distance_m":actual_distance,"max_frame_distance_m_excluding_normal_travel":max_frame_distance,"checks":checks,"failures":failures,"engine_errors":logger.errors,"events":events,"ten_second_samples":samples,"route":route,"actual_abilities":actual_abilities,"actual_interactions":actual_interactions,"combat_transitions":combat_transitions,"actual_damage_samples":damage_samples,"actual_part_visits":part_visits,"actual_reveal_observations":reveal_observations,"phase_two_observed":phase_two_observed,"battle_baseline":battle_baseline,"damage_evidence":damage_evidence,"inherited_committed_victory":inherited_victory,"attempt":original_attempt,"status":_status(),"preservation":preservation,"fresh_reader":final_reader,"story_receipts":session.story.state.get("receipts",{}),"stats":session.stats,"pilot":pilot.report() if pilot!=null and is_instance_valid(pilot.body) else {},"scope":"AUTHORING same-natural-QA-profile investigation46-to-Mirrorwing50 only. Actual source46 report and receipt digest must be bound first. Ordinary exported MAIN/menu/spawn/M, native continuous Pilot/Flight, near/LOS G briefing, real safety-line entry, normal 4/Tab/F for a separate sustained Boss reveal emitter, actual emitter/core/receiver first-hit shadow, real warning-driven lateral flight, ordinary held flight_fire and original Host weapon/cooldown/range/LOS/part recovery gates, actual two-phase reverse order and observed HP chains including clamped half/final hits, original victory Store/reward and post-victory G record, SaveGate/fresh reader and Session native audio exit. No ActorPose, time/delta, mechanism/environment/HP/Story/flags fixture, direct Boss start/fire/Encounter advance, profile clone/rollback/reward import. Bounded unflown candidate; partial original snapshots retain previous evidence explicitly, not whole campaign/fun/LAN/controller/performance acceptance."}
	report.merge(SourceBinding.audit(_source_binding))
	report["native_exit"]={"requested":true,"through":"session._quit","observed_scene_exit":false,"watchdog_failed":false}
	report_cache=_plain(report)
	var written: bool=_flush_report()
	print("NORMAL_F2_BOSS_RESULT "+JSON.stringify({"complete":complete,"requested_stage_stopped":stage_stopped,"written":written,"reason":reason,"phase":phase,"seconds":_elapsed(),"failures":failures,"engine_errors":logger.errors}))
	native_exit_requested=true
	_native_exit_watchdog.call_deferred()
	session._quit()

