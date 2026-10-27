extends Node
const SourceBinding = preload("res://scripts/v3/qa/twin_source_binding.gd")
static var _source_binding: Dictionary = {}
## AUTHORING ONLY: same natural I4 decision75 -> F4 Ending84.
## Root bound actual natural75 report; original ROUTE.md remains untouched.
const Pilot = preload("res://scripts/v3/qa/twin_normal_flight_pilot.gd")
const Store = preload("res://scripts/v3/core/twin_world_store.gd")
const Director = preload("res://scripts/v3/gameplay/actions/twin_action_director.gd")
const Catalog = preload("res://scripts/v3/campaign/twin_campaign_catalog.gd")
const I2Results = preload("res://scripts/v3/gameplay/twin_i2_result_ledger.gd")
const AbilityRules = preload("res://scripts/v3/gameplay/twin_ability_rules.gd")
const Encounter = preload("res://scripts/v3/campaign/twin_campaign_encounter.gd")
static var SOURCE_PROFILE := "qa_normal_campaign_20261021_012725_b90f8a6f"
static var SOURCE_REPORT := "artifacts/v3/normal-i4-20261021_061149_2f6abfd7/normal-i4-20261021_061149_2f6abfd7.json"
static var SOURCE_REPORT_SHA256 := "a13ebc302fa9d12611103c02c5c09f6434ebd6a5fb7515339b14519c3165f183"
static var SEVENTYFIVE_DIGEST := "6e7c86de9c5ab2dc0b9e35a00fbe3c42b0f7010f60e1e986f59dd0d14c1fa8a4"
const SOURCE_GOALS := ["I1:rescue:brief","I1:rescue:channel","I1:rescue:contact","I1:rescue:evacuate","I1:evidence:trace","I1:evidence:engineer","I1:evidence:ledger","I1:evidence:echo","F1:needs:listen","F1:needs:nursery","F1:needs:route","F1:repair:plan","F1:repair:light","F1:repair:grow","F1:repair:confirm","I1:whale:brief","I1:whale:engage","I1:whale:disable","I1:whale:record","F1:crown:brief","F1:crown:engage","F1:crown:disable","F1:crown:restore","I1:underdeck:read","I1:underdeck:enter","I1:underdeck:release","I1:underdeck:traverse","I2:clinic_supply:diagnose","I2:clinic_supply:connect","I2:clinic_supply:stabilize","I2:clinic_supply:confirm","I2:distribution_audit:expose","I2:distribution_audit:trace","I2:distribution_audit:share_access","I2:canal_service:brief","I2:canal_service:exchange","I2:canal_service:service","I2:canal_service:order","I2:twin_pump_guardian:plan","I2:twin_pump_guardian:engage","I2:twin_pump_guardian:stop","I2:twin_pump_guardian:decision","F2:mirror_evidence:records","F2:mirror_evidence:archive","F2:mirror_evidence:light","F2:mirror_evidence:decision","F2:mirrorwing_warden:plan","F2:mirrorwing_warden:engage","F2:mirrorwing_warden:stop","F2:mirrorwing_warden:record","I3:cooling_route:brief","I3:cooling_route:ledger","I3:cooling_route:exchange","I3:cooling_route:dock","I3:furnace_crawler:plan","I3:furnace_crawler:engage","I3:furnace_crawler:stop","I3:furnace_crawler:record","F3:separate_network:sample","F3:separate_network:listen","F3:separate_network:isolate","F3:separate_network:feed","F3:mycelial_choir:plan","F3:mycelial_choir:engage","F3:mycelial_choir:stop","F3:mycelial_choir:record","I4:array_witness:brief","I4:array_witness:archive","I4:array_witness:witness","I4:array_witness:shelter","I4:array_witness:isolate","I4:prism_array:plan","I4:prism_array:engage","I4:prism_array:stop","I4:prism_array:decision"]
const EXPECTED := ["I1:rescue:brief","I1:rescue:channel","I1:rescue:contact","I1:rescue:evacuate","I1:evidence:trace","I1:evidence:engineer","I1:evidence:ledger","I1:evidence:echo","F1:needs:listen","F1:needs:nursery","F1:needs:route","F1:repair:plan","F1:repair:light","F1:repair:grow","F1:repair:confirm","I1:whale:brief","I1:whale:engage","I1:whale:disable","I1:whale:record","F1:crown:brief","F1:crown:engage","F1:crown:disable","F1:crown:restore","I1:underdeck:read","I1:underdeck:enter","I1:underdeck:release","I1:underdeck:traverse","I2:clinic_supply:diagnose","I2:clinic_supply:connect","I2:clinic_supply:stabilize","I2:clinic_supply:confirm","I2:distribution_audit:expose","I2:distribution_audit:trace","I2:distribution_audit:share_access","I2:canal_service:brief","I2:canal_service:exchange","I2:canal_service:service","I2:canal_service:order","I2:twin_pump_guardian:plan","I2:twin_pump_guardian:engage","I2:twin_pump_guardian:stop","I2:twin_pump_guardian:decision","F2:mirror_evidence:records","F2:mirror_evidence:archive","F2:mirror_evidence:light","F2:mirror_evidence:decision","F2:mirrorwing_warden:plan","F2:mirrorwing_warden:engage","F2:mirrorwing_warden:stop","F2:mirrorwing_warden:record","I3:cooling_route:brief","I3:cooling_route:ledger","I3:cooling_route:exchange","I3:cooling_route:dock","I3:furnace_crawler:plan","I3:furnace_crawler:engage","I3:furnace_crawler:stop","I3:furnace_crawler:record","F3:separate_network:sample","F3:separate_network:listen","F3:separate_network:isolate","F3:separate_network:feed","F3:mycelial_choir:plan","F3:mycelial_choir:engage","F3:mycelial_choir:stop","F3:mycelial_choir:record","I4:array_witness:brief","I4:array_witness:archive","I4:array_witness:witness","I4:array_witness:shelter","I4:array_witness:isolate","I4:prism_array:plan","I4:prism_array:engage","I4:prism_array:stop","I4:prism_array:decision","F4:vein_reunion:council","F4:vein_reunion:industry","F4:vein_reunion:living","F4:vein_reunion:test","F4:vein_reunion:plan","F4:twin_vein_core:plan","F4:twin_vein_core:engage","F4:twin_vein_core:stop","F4:twin_vein_core:decision"]
const COUNCIL := "F4:vein_reunion:council"
const INDUSTRY := "F4:vein_reunion:industry"
const LIVING := "F4:vein_reunion:living"
const TEST := "F4:vein_reunion:test"
const REVIEW := "F4:vein_reunion:plan"
const PLAN := "F4:twin_vein_core:plan"
const ENGAGE := "F4:twin_vein_core:engage"
const STOP := "F4:twin_vein_core:stop"
const DECISION := "F4:twin_vein_core:decision"
const REVIEW_CHOICE := "F4:plans_reviewed"
const CHOICE := "F4:chapter_choice"
const CHOICE_OPTION := "shared_stewardship"
const REWARD := "boss:F4:twin_vein_core"
const STAGES := ["council","industry","living","test","review","plan","engage","half","stop","complete"]
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
var max_seconds := 900.0
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


var environment_observations: Array = []
var device_observations: Array = []
var inherited_goals: Array = []
var patrol_z_side := -1.0

var load_observations: Array = []
var growth_observations: Array = []
var final_gate_observations: Array = []
var ending_observations: Array = []
var inherited_boss_devices := false

static func _bound() -> bool:
	if SOURCE_REPORT.is_empty() or SOURCE_REPORT_SHA256.length()!=64 or SEVENTYFIVE_DIGEST.length()!=64: return false
	for digest: String in [SOURCE_REPORT_SHA256,SEVENTYFIVE_DIGEST]:
		for letter: String in digest:
			if letter not in "0123456789abcdef": return false
	return true



static func preflight(args: PackedStringArray) -> Dictionary:
	_source_binding = {}
	var bound: Dictionary = SourceBinding.prepare(args,"normal-f4",SOURCE_GOALS,EXPECTED)
	if not bound.get("ok",false): return {"ok":false,"code":bound.get("code","source_binding_rejected"),"config":{}}
	_source_binding = bound.binding
	args = bound.args
	SOURCE_PROFILE = str(_source_binding.constants.get("SOURCE_PROFILE",SOURCE_PROFILE))
	SOURCE_REPORT = str(_source_binding.constants.get("SOURCE_REPORT",SOURCE_REPORT))
	SOURCE_REPORT_SHA256 = str(_source_binding.constants.get("SOURCE_REPORT_SHA256",SOURCE_REPORT_SHA256))
	SEVENTYFIVE_DIGEST = str(_source_binding.constants.get("SEVENTYFIVE_DIGEST",SEVENTYFIVE_DIGEST))
	if not _bound(): return {"ok":false,"code":"root_must_bind_actual_I4Decision75_report_and_receipts","config":{}}
	var values: Dictionary = {}
	for argument: String in args:
		var key := ""
		var value := ""
		if argument=="--qa-normal-f4":
			key="enabled"
			value="true"
		else:
			for pair: Array in [["--qa-profile=","profile"],["--qa-normal-output=","output"],["--qa-normal-seconds=","seconds"],["--qa-f4-stop-after=","stage"]]:
				if argument.begins_with(str(pair[0])):
					key=str(pair[1])
					value=argument.trim_prefix(str(pair[0]))
					break
		if key.is_empty() or value.is_empty() or values.has(key): return {"ok":false,"code":"unknown_empty_or_duplicate_f4_cli","config":{}}
		values[key]=value
	for key: String in ["enabled","profile","output","seconds"]:
		if not values.has(key): return {"ok":false,"code":"four_f4_arguments_required","config":{}}
	if values.size()<4 or values.size()>5 or values.profile!=SOURCE_PROFILE: return {"ok":false,"code":"same_natural_QA_profile_required","config":{}}
	var seconds: String=str(values.seconds)
	if not seconds.is_valid_int() or str(seconds.to_int())!=seconds or seconds.to_int()<60 or seconds.to_int()>900: return {"ok":false,"code":"seconds_60_to_900_required","config":{}}
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
	return {"ok":true,"code":"natural_I4Decision75_prefix_verified","config":{"profile":SOURCE_PROFILE,"output":selected_output,"max_seconds":seconds.to_int(),"stop_after":stage,"source_profile_id":saved.profile_id,"source_lineage_id":saved.lineage_id,"source_receipts_sha256":SEVENTYFIVE_DIGEST}}



func run(owner_session: Node,options: Dictionary={}) -> Dictionary:
	if not _bound(): return {"ok":false,"code":"actual_I4Decision75_source_not_bound"}
	if running or stopping or finished: return {"ok":false,"code":"already_started"}
	session=owner_session
	output=str(options.get("output","")).replace("\\","/")
	max_seconds=float(options.get("max_seconds",900))
	stop_after=str(options.get("stop_after","complete"))
	if not is_instance_valid(session) or not is_inside_tree() or options.get("profile")!=SOURCE_PROFILE or session.store.root_path!="user://profiles_v3/"+SOURCE_PROFILE or not _output_valid(output) or not is_finite(max_seconds) or max_seconds<60 or max_seconds>900 or stop_after not in STAGES: return {"ok":false,"code":"mounted_same_profile_new_output_and_bound_required"}
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
	return {"ok":true,"code":"observing_natural_F4","stop_after":stop_after}



static func _source_check(saved: Dictionary) -> Dictionary:
	if not SourceBinding.same_identity(_source_binding,saved): return {"ok":false,"code":"source_binding_identity_changed"}
	if not _bound(): return {"ok":false,"code":"actual_I4Decision75_source_not_bound"}
	var world: Variant=saved.get("world")
	if not world is Dictionary or world.get("region_id") not in ["I4","F4"] or world.get("branch_id")!="main": return {"ok":false,"code":"same_natural_I4_or_F4_main_branch_required"}
	if not world.get("actions") is Dictionary or not world.actions.get("opening") is Dictionary: return {"ok":false,"code":"source_story_schema"}
	var state: Dictionary=world.actions.opening
	var completed: Variant=state.get("completed")
	if not completed is Array or completed.size()<75 or completed.size()>84 or completed!=EXPECTED.slice(0,completed.size()) or world.get("completed_objectives")!=completed: return {"ok":false,"code":"only_exact_natural_75_to_84_prefix_accepted"}
	if not state.get("receipts") is Dictionary or state.receipts.size()!=completed.size() or _receipts_digest(state,SOURCE_GOALS)!=SEVENTYFIVE_DIGEST: return {"ok":false,"code":"actual_original_75_receipts_changed"}
	var director=Director.new()
	var definitions: Dictionary=director.load_definitions(Director.DEFAULT_PATH,Catalog.extension_paths())
	if not definitions.get("ok",false) or not director.validate_state(state).get("ok",false): return {"ok":false,"code":"original_Director_replay_rejected"}
	var discoveries: Variant=saved.get("personal",{}).get("discoveries")
	if not discoveries is Array: return {"ok":false,"code":"original_personal_discoveries_required"}
	var valid: Dictionary=I2Results.validate_world(world,discoveries)
	if not valid.get("ok",false): return {"ok":false,"code":"original_I2_physical_boundary:"+str(valid.get("error",""))}
	for flag: String in ["I2:region_route_open","campaign_boss:I2","F2:region_route_open","campaign_boss:F2","I3:region_route_open","campaign_boss:I3","F3:region_route_open","campaign_boss:F3","I4:region_route_open","campaign_boss:I4","I4:chapter_decision_saved"]:
		if not world.get("flags",{}).get(flag,false): return {"ok":false,"code":"actual_original_prior_region_required:"+flag}
	for finding: String in ["F3:living_isolation","F3:operation_record","I4:operation_record","boss:I4:prism_array"]:
		if discoveries.count(finding)!=1: return {"ok":false,"code":"original_unique_source_findings_required:"+finding}
	if state.get("choices",{}).get("I4:prism_array:decision") not in ["public_caps","regional_cosign"]: return {"ok":false,"code":"original_I4_actual_choice_required"}
	var prior: Variant=world.get("environment",{}).get("campaign_I4")
	if not prior is Dictionary or not prior.get("mechanisms") is Dictionary or not prior.get("encounter") is Dictionary or prior.get("version")!=1 or prior.get("observed")!=true: return {"ok":false,"code":"actual_original_I4_envelope_required"}
	var checker=Encounter.new()
	if not checker.configure("prism_array").get("ok",false) or not checker.validate_snapshot(prior.encounter).get("ok",false) or not prior.encounter.get("state",{}).get("completed",false): return {"ok":false,"code":"original_I4_two_phase_victory_invalid"}
	for history: String in ["I4:evidence_chain","I4:route_record","I4:defence_record"]:
		if not prior.mechanisms.get("histories",{}).has(history): return {"ok":false,"code":"original_actual_I4_history_required:"+history}
	var envelope: Variant=world.get("environment",{}).get("campaign_F4")
	if envelope==null:
		if completed.size()!=75: return {"ok":false,"code":"F4_progress_without_physical_envelope"}
		return {"ok":true,"code":"legal_natural_I4_decision75","source_receipts_sha256":SEVENTYFIVE_DIGEST,"completed":completed.duplicate()}
	if not envelope is Dictionary or envelope.get("version")!=1 or not envelope.get("mechanisms") is Dictionary or not envelope.get("encounter") is Dictionary or not envelope.get("observed") is bool: return {"ok":false,"code":"original_F4_physical_envelope_required"}
	var proof: Dictionary=envelope.mechanisms
	if proof.get("region_id")!="F4" or not proof.get("histories") is Dictionary or not proof.get("facts") is Dictionary: return {"ok":false,"code":"original_F4_mechanism_identity"}
	for requirement: Array in [[INDUSTRY,"F4:industrial_link_verified","F4:industrial_record"],[LIVING,"F4:living_link_verified","F4:living_record"],[TEST,"F4:dual_load_verified","F4:dual_load_record"],[REVIEW,"F4:plans_reviewed","F4:plans_read"]]:
		if requirement[0] in completed and (not proof.facts.has(requirement[1]) or not proof.histories.has(requirement[2])): return {"ok":false,"code":"original_F4_physical_history_missing:"+str(requirement[0])}
	if TEST in completed:
		var readings: Variant=proof.histories["F4:dual_load_record"].get("readings")
		if not readings is Dictionary or readings.size()!=2 or readings.get("industrial",{}).get("test_serial")!=readings.get("living",{}).get("test_serial"): return {"ok":false,"code":"original_same_serial_two_load_samples_required"}
	if REVIEW in completed and proof.histories["F4:plans_read"].size()!=3: return {"ok":false,"code":"original_three_plans_read_required"}
	if not envelope.encounter.is_empty():
		checker=Encounter.new()
		if not checker.configure("twin_vein_core").get("ok",false) or not checker.validate_snapshot(envelope.encounter).get("ok",false): return {"ok":false,"code":"original_F4_encounter_snapshot_rejected"}
	if ENGAGE in completed and (not envelope.observed or envelope.encounter.is_empty()): return {"ok":false,"code":"actual_original_full_attack_cycle_required"}
	var stopped: bool=STOP in completed
	var committed: bool=world.get("flags",{}).get("campaign_boss:F4",false)
	if committed!=envelope.encounter.get("state",{}).get("completed",false) or world.get("flags",{}).get("F4:boss_stopped",false)!=stopped or discoveries.count(REWARD)!=(1 if committed else 0): return {"ok":false,"code":"original_F4_victory_result_mismatch"}
	if stopped and not committed: return {"ok":false,"code":"original_committed_two_phase_encounter_required"}
	var decided: bool=DECISION in completed
	if discoveries.count("F4:operation_record")!=(1 if decided else 0) or world.get("flags",{}).get("F4:region_route_open",false)!=decided or world.get("flags",{}).get("F4:chapter_decision_saved",false)!=decided: return {"ok":false,"code":"original_F4_decision_result_mismatch"}
	if decided and state.get("choices",{}).get(DECISION)!=CHOICE_OPTION: return {"ok":false,"code":"only_original_default_shared_stewardship_continuation"}
	if decided and Catalog.ending(state.choices).get("ending_id")!=CHOICE_OPTION: return {"ok":false,"code":"original_shared_stewardship_ending_required"}
	return {"ok":true,"code":"legal_natural_F4_prefix","source_receipts_sha256":SEVENTYFIVE_DIGEST,"completed":completed.duplicate()}


func _execute() -> void:
	if not _check(session.profile_ready and not session.active and not OS.has_feature("editor"),"actual exported MAIN before ordinary same-profile menu continuation"): _stop("exported_normal_menu_required"); return
	last_completed=initial.world.actions.opening.completed.duplicate()
	session._ui_action("solo",{"frame":0})
	await _next()
	if not _healthy() or not _check(_receipts_digest(session.story.state,SOURCE_GOALS)==initial_digest,"ordinary menu preserves every actual75 source receipt",_status()): _stop("ordinary_source_resume_failed"); return
	if not await _dismiss_radio(): _stop("source_radio_not_closed"); return
	if session.region_id=="I4":
		if not _check(session._can_travel_to("F4"),"ordinary original I4 decision permits F4"): _stop("ordinary_F4_travel_locked"); return
		_press_key(KEY_M)
		await _next()
		if session.region_id=="I4":
			if not _check(session.interface.travel.visible,"ordinary M exposes current I4 travel panel"): _stop("ordinary_travel_panel_missing"); return
			session._ui_action("travel_to",{"region_id":"F4"})
		var deadline: float=minf(max_seconds-20.0,_elapsed()+35.0)
		while _live() and session.region_id!="F4" and _elapsed()<deadline: await _next()
	if not _check(_live() and session.region_id=="F4" and session.campaign.supported() and session.world.build_errors.is_empty(),"ordinary F4 scene loads real original campaign"): _stop("ordinary_F4_factory_unavailable"); return
	if not await _dismiss_radio(): _stop("arrival_radio_not_closed"); return
	_bind_pilot()
	route=_route_definition()
	if not _check(not route.is_empty(),"actual final-region targets and bounded unflown routes are available",route): _stop("actual_F4_route_unavailable"); return
	for pair: Array in [[COUNCIL,"council"],[INDUSTRY,"industry"],[LIVING,"living"],[TEST,"test"],[REVIEW,"review"]]:
		var objective: String=str(pair[0])
		var stage: String=str(pair[1])
		if _completed(objective):
			inherited_goals.append(objective)
			_event("inherited_original_approach_receipt",{"receipt":_receipt_for(objective),"note":"No new device/flight/read credit claimed for inherited legal progress."})
		else:
			var ok := false
			match stage:
				"council": ok=await _visit_and_contact(route.council,"npc:guanzhi",COUNCIL)
				"industry": ok=await _connect_actual_industry()
				"living": ok=await _grow_actual_living_lifeline()
				"test": ok=await _measure_actual_dual_load()
				"review": ok=await _read_actual_three_plans()
			if not ok:
				if not stopping: _stop("actual_F4_"+stage+"_unproven")
				return
		if _stage(stage): return
	inherited_victory=session.campaign.victory_committed()
	if inherited_victory and not _completed(STOP):
		if not await _wait_completed(STOP,5.0): _stop("inherited_committed_victory_not_projected"); return
	if not _completed(STOP):
		if not session.campaign.active():
			if not await _ensure_actual_lifelines(): _stop("current_lifelines_before_battle_unproven"); return
			if not await _prepare_actual_boss_devices(): _stop("actual_independent_Boss_devices_unproven"); return
		if not _completed(PLAN):
			if not await _navigate([Vector3(_body().global_position.x,route.altitude,_body().global_position.z),route.briefing_high,route.briefing],"original_south_safe_final_briefing"): _stop("normal_briefing_flight_unproven"); return
			if not await _contact("F4:boss_briefing",PLAN): _stop("normal_plan_G_unproven"); return
			if not _check(not session.campaign.active() and _body().global_position.z>float(route.entry_z),"G plan stays south of actual entry line",_status()): _stop("premature_arena_entry"); return
		else: _event("inherited_original_plan",{"receipt":_receipt_for(PLAN),"encounter":_boss_state()})
		if _stage("plan"): return
		if not await _dismiss_radio(): _stop("plan_radio_not_closed"); return
		if not session.campaign.active():
			if not await _enter_actual_arena(): _stop("actual_flown_entry_unproven"); return
		else:
			if not await _resume_active_approach(): _stop("resumed_battle_flight_unproven"); return
		if not await _ensure_actual_boss_environment(): _stop("current_Boss_environment_unproven"); return
		var observed_deadline: float=minf(max_seconds-20.0,_elapsed()+20.0)
		while _healthy() and not _completed(ENGAGE) and _elapsed()<observed_deadline: await _next()
		if not _check(_completed(ENGAGE) and session.campaign.observed,"actual warning-active-recovery cycle durably projects engage",_status()): _stop("actual_full_cycle_unproven"); return
		if _stage("engage"): return
		if not await _fight():
			if not stopping: _stop("actual_normal_final_battle_incomplete")
			return
		if stopping: return
	else:
		inherited_victory=true
		phase_two_observed=int(_boss_state().get("phase",0))==2
		_event("inherited_original_committed_final_victory",{"receipt":_receipt_for(STOP),"state":_boss_state(),"note":"No new firing or damage claimed for inherited original victory."})
		for value: String in ["plan","engage","half"]:
			if _stage(value): return
	if _stage("stop"): return
	if not await _dismiss_radio(): _stop("victory_radio_not_closed"); return
	if not _completed(DECISION):
		# Every repair occurs BEFORE the original proposal. Once solo is ready,
		# production rejects abilities; this candidate never injects F/X there.
		if not await _ensure_actual_lifelines(): _stop("current_final_lifelines_unproven"); return
		if not await _navigate([Vector3(_body().global_position.x,route.altitude,_body().global_position.z),route.choice_high,route.choice],"actual_final_signature_terminal"): _stop("post_Boss_choice_flight_unproven"); return
		if not await _read_or_choose_actual_panel(false): _stop("actual_three_cost_panels_and_final_transaction_unproven"); return
	else: _event("inherited_original_final_signature",{"receipt":_receipt_for(DECISION)})
	if not await _observe_actual_ending(): _stop("actual_Ending84_unproven"); return
	if not _check(session.story.state.completed==EXPECTED and _receipts_digest(session.story.state,SOURCE_GOALS)==initial_digest and session.campaign.victory_committed() and not session.boss_active,"exact nine F4 goals reach Ending84 with unchanged75 source receipts, no extra record",_status()): _stop("final84_prefix_unproven"); return
	_stage("complete")


func _route_definition() -> Dictionary:
	for id: String in ["npc:guanzhi","F4:choice_terminal","F4:boss_briefing","F4:industrial_gauge","F4:living_gauge"]:
		if not session.story.markers.has(id): return {}
	for id: String in ["F4:limited_bus","F4:industrial_load","F4:lifeline_bus","F4:living_emitter","F4:living_support","F4:test_hold","F4:industrial_gauge","F4:living_gauge","F4:core_charge_breaker","F4:core_thermal_sink","F4:core_living_support"]:
		if not session.entities.has(id) or not session.world.objects.has(id): return {}
	for part: String in ["charge_return","thermal_return","living_return","core"]:
		if not session.world.campaign_arena.targets.has(session.world.campaign_arena.target_id(part)): return {}
	var altitude: float=minf(20.0,float(_body().max_altitude)-.5)
	var entry: float=float(session.campaign._entry_z)
	var brief: Vector3=_v(session.story.markers["F4:boss_briefing"].position)+Vector3(0,.2,1.6)
	var terminal: Vector3=_v(session.story.markers["F4:choice_terminal"].position)+Vector3(0,.5,2)
	if altitude<18 or not is_finite(entry) or not brief.is_finite() or not terminal.is_finite(): return {}
	return {"altitude":altitude,"entry_z":entry,"centre":session.world.campaign_arena.centre(),
		"council":_v(session.story.markers["npc:guanzhi"].position)+Vector3(0,.2,2),
		"industry":Vector3(-12,11,9),"emitter":Vector3(5,15,9),"living":Vector3(14,15.5,9),
		"hold":Vector3(10,17.5,-2.5),"gauge_industrial":Vector3(15,17.4,-3),"gauge_living":Vector3(21,17.4,-3),
		"core_charge":Vector3(-7.5,15.5,-24.5),"core_thermal":Vector3(0,16,-17),"core_growth":Vector3(5,16,-23),
		"briefing":brief,"briefing_high":Vector3(brief.x,altitude,brief.z),
		"entry_high":Vector3(0,altitude,entry-1),"patrol_z":entry+2,"patrol_extent":9.0,
		"choice":terminal,"choice_high":Vector3(terminal.x,altitude,terminal.z),
		"note":"Unflown exact-production candidate, device centres are never aircraft destinations. QA unloaded Flight Pilot preserves original inertia/full hull/stopping sweeps. High patrol is above original ring world-y ceiling15; locked column/cross still require actual diagonal motion. No collider/clock/HP/Story fixture."}


func _visit_and_contact(point: Vector3,target: String,objective: String) -> bool:
	if not await _dismiss_radio(): return false
	var clear_height: float=maxf(10.0,point.y+3.0)
	if not await _navigate([Vector3(_body().global_position.x,clear_height,_body().global_position.z),Vector3(point.x,clear_height,point.z),point],"actual_"+target): return false
	return await _contact(target,objective)



func _approach(point: Vector3,label: String) -> bool:
	if not await _dismiss_radio(): return false
	return await _navigate([Vector3(_body().global_position.x,route.altitude,_body().global_position.z),Vector3(point.x,route.altitude,point.z),point],label)


func _connect_actual_industry() -> bool:
	if not await _approach(route.industry,"actual_already_inserted_industrial_bus_vantage"): return false
	_phase("normal_6_F_actual_industrial_supply")
	var before: Dictionary=_mechanisms_debug()
	var bus: Node3D=session.world.objects["F4:limited_bus"]
	if bus.global_position.distance_to(Vector3(-12,9,6))>.01:
		if not _check(bus.global_position.distance_to(Vector3(-12,9,8))<=.01,"only a truly unplugged original bus receives the normal G insertion",before): return false
		if not await _operate_to_position("F4:limited_bus",Vector3(-12,9,6)): return false
	var supply: Dictionary=session.entities["F4:limited_bus"]
	if not supply.get("powered",false) or float(supply.get("charge",0))<20:
		if not await _cast("F4:limited_bus","charge",KEY_6): return false
	var emergency: Dictionary=session.entities["F4:lifeline_bus"]
	if not emergency.get("powered",false) or float(emergency.get("charge",0))<20:
		if not await _approach(Vector3(-12,11,15),"actual_emergency_line_recharge_vantage"): return false
		if not await _cast("F4:lifeline_bus","charge",KEY_6): return false
	var deadline: float=minf(max_seconds-20.0,_elapsed()+4.0)
	while _healthy() and _elapsed()<deadline and not session.campaign.mechanisms.view_state().get("industrial_connected",false): await _next()
	if not await _wait_completed(INDUSTRY,6.0): return false
	var after: Dictionary=_mechanisms_debug()
	device_observations.append(_plain({"kind":"industrial_lifeline","seconds":_elapsed(),"before":before,"after":after,"receipt":_receipt_for(INDUSTRY)}))
	return _check(after.view.get("industrial_connected",false) and int(after.view.get("industrial_draw_w",0))==120 and after.state.histories.has("F4:industrial_record"),"actual inserted powered limited bus supplies original120W load while emergency supply remains connected",after)


func _operate_to_position(target: String,goal: Vector3) -> bool:
	if not await _dismiss_radio(): return false
	if not await _select_target(target): return false
	var body: Node3D=session.world.objects[target]
	if body.global_position.distance_to(goal)<=.01: return true
	var ray: Dictionary=_first_hit_from(_body().global_position,target)
	if not _check(session.campaign.operable_near(1,target) and ray.get("entity_id")==target,"original near/LOS G operation is available for "+target,ray): return false
	var before: Vector3=body.global_position
	_record_g(target)
	await _next()
	var row: Dictionary={"kind":"actual_G_position","seconds":_elapsed(),"target":target,"from":before,"actual":body.global_position,"required":goal,"blockers":session.campaign.last_operation_blockers}
	device_observations.append(_plain(row))
	return _check(body.global_position.distance_to(goal)<=.01,"original eight-step swept G actually moves "+target,row)


func _grow_actual_living_lifeline() -> bool:
	if not await _approach(route.emitter,"actual_sustained_emitter_side_vantage"): return false
	_phase("original_4_F_emitter_alignment_then_three_full_growth_steps")
	var before: Dictionary=_mechanisms_debug()
	# Each real F is +30 degrees. Initial -30 needs exactly one. A legal
	# interrupted light-off at yaw0 needs twelve real turns, never angle writes.
	for _turn: int in range(13):
		var source: Dictionary=session.entities["F4:living_emitter"]
		var angle: float=absf(wrapf(float(source.get("angle",0)),-PI,PI))
		if angle<.001 and float(source.get("light_level",0))>=.5: break
		if not await _cast("F4:living_emitter","light",KEY_4): return false
	var source: Dictionary=session.entities["F4:living_emitter"]
	if not _check(absf(wrapf(float(source.get("angle",0)),-PI,PI))<.001 and float(source.get("light_level",0))>=.5,"actual sustained emitter reaches yaw0 by original30-degree input operations",source): return false
	var deadline: float=minf(max_seconds-20.0,_elapsed()+4.0)
	while _healthy() and _elapsed()<deadline and float(session.entities["F4:living_support"].get("environment_light",0))<.5: await _next()
	if not _check(float(session.entities["F4:living_support"].get("environment_light",0))>=.5,"actual emitter first-hit ray illuminates the original living support",_mechanisms_debug()): return false
	if not await _approach(route.living,"actual_growth_volume_clear_vantage"): return false
	if not await _grow_full("F4:living_support",false): return false
	if not await _wait_completed(LIVING,6.0): return false
	var after: Dictionary=_mechanisms_debug()
	growth_observations.append(_plain({"kind":"living_lifeline_complete","seconds":_elapsed(),"before":before,"after":after,"receipt":_receipt_for(LIVING)}))
	return _check(after.view.get("living_connected",false) and after.view.get("beam_valid",false) and after.state.facts.get("F4:living_link_verified")=="growth_support","original continuous light and full native3m collision span complete the living lifeline",after)


func _grow_full(target: String,portable_light: bool) -> bool:
	var before: Dictionary=session.entities[target].duplicate(true)
	if portable_light and float(session.entities[target].get("growth",0))<1.0:
		var remaining: int=int(ceil((1.0-float(session.entities[target].get("growth",0)))/.35))
		if not await _wait_energy(5.0+float(remaining)*12.0): return false
		if not await _cast(target,"light",KEY_4): return false
	for _step: int in range(3):
		var current: Dictionary=session.entities[target]
		if float(current.get("growth",0))>=1.0: break
		if portable_light and maxf(float(current.get("light_level",0)),float(current.get("environment_light",0)))<.25:
			if not await _cast(target,"light",KEY_4): return false
		if not await _cast(target,"growth",KEY_7): return false
		# Let the ordinary World resize its real shape; do not write shape.size.
		await _next()
	var deadline: float=minf(max_seconds-20.0,_elapsed()+3.0)
	while _healthy() and _elapsed()<deadline and not _full_native_growth_box(target): await _next()
	var row: Dictionary={"kind":"actual_growth_shape","seconds":_elapsed(),"target":target,"before":before,"after":session.entities[target].duplicate(true),"native_full_box":_full_native_growth_box(target),"blockers":session.world.campaign_growth_blockers.get(target,[])}
	growth_observations.append(_plain(row))
	return _check(float(session.entities[target].get("growth",0))>=1.0 and _full_native_growth_box(target),"real light/three original growth inputs produce full3m native collision for "+target,row)


func _full_native_growth_box(target: String) -> bool:
	var body: Variant=session.world.objects.get(target)
	if not body is PhysicsBody3D: return false
	for child: Node in body.get_children():
		if child is CollisionShape3D and not child.disabled and child.shape is BoxShape3D:
			return child.shape.size.is_equal_approx(Vector3(3,.4,3)) and PhysicsServer3D.body_get_state(body.get_rid(),PhysicsServer3D.BODY_STATE_TRANSFORM)==body.global_transform
	return false


func _measure_actual_dual_load() -> bool:
	if not await _ensure_actual_lifelines(): return false
	if not await _approach(route.hold,"actual_latched_load_test_hold_vantage"): return false
	_phase("normal_Tab_G_persistent_test_hold_and_two_original_gauges")
	if not await _select_target("F4:test_hold"): return false
	var hold: Node3D=session.world.objects["F4:test_hold"]
	if hold.global_basis.x.normalized().dot(Vector3.FORWARD)<=.95:
		var ray: Dictionary=_first_hit_from(_body().global_position,"F4:test_hold")
		if not _check(session.campaign.operable_near(1,"F4:test_hold") and ray.get("entity_id")=="F4:test_hold","actual hold is near, visible and clear before original rotation",ray): return false
		_record_g("F4:test_hold")
		await _next()
	if not _check(hold.global_basis.x.normalized().dot(Vector3.FORWARD)>.95,"original swept G rotates actual hold into a persistent90-degree latch",{"actual_rotation":hold.rotation,"blockers":session.campaign.last_operation_blockers}): return false
	var deadline: float=minf(max_seconds-20.0,_elapsed()+4.0)
	var test: Dictionary=session.campaign.mechanisms.persistent_state().histories.get("F4:load_test",{})
	while _healthy() and _elapsed()<deadline and (not test.get("active",false) or test.get("method")!="latched_test"):
		await _next()
		test=session.campaign.mechanisms.persistent_state().histories.get("F4:load_test",{})
	if not _check(test.get("active",false) and test.get("method")=="latched_test" and int(test.get("test_serial",0))>0,"original live dual-load test starts from real latched hardware",test): return false
	var serial: int=int(test.test_serial)
	load_observations.append(_plain({"kind":"actual_test_started","seconds":_elapsed(),"test":test}))
	for item: Array in [["F4:industrial_gauge",route.gauge_industrial],["F4:living_gauge",route.gauge_living]]:
		if not await _approach(item[1],"actual_read_vantage:"+str(item[0])): return false
		if not await _read_actual_gauge(str(item[0]),serial): return false
	if not await _wait_completed(TEST,6.0): return false
	var record: Dictionary=session.campaign.mechanisms.persistent_state().histories.get("F4:dual_load_record",{})
	var readings: Dictionary=record.get("readings",{})
	var same: bool=readings.size()==2 and int(record.get("test_serial",0))==serial
	for side: String in ["industrial","living"]: same=same and int(readings.get(side,{}).get("test_serial",0))==serial
	var row: Dictionary={"kind":"actual_same_serial_pair","seconds":_elapsed(),"serial":serial,"record":record,"receipt":_receipt_for(TEST)}
	load_observations.append(_plain(row))
	return _check(same and int(readings.get("industrial",{}).get("load_w",0))==120 and int(readings.get("living",{}).get("load_w",0))==90 and _receipt_for(TEST).get("option")=="latched_test","two actual near/LOS G readings share the same original test serial and real120W/90W values",row)


func _read_actual_gauge(target: String,serial: int) -> bool:
	if not await _dismiss_radio(): return false
	var side := "industrial" if target.ends_with("industrial_gauge") else "living"
	var deadline: float=minf(max_seconds-20.0,_elapsed()+6.0)
	var next_press := 0.0
	while _healthy() and _elapsed()<deadline:
		var state: Dictionary=session.campaign.mechanisms.persistent_state()
		var test: Dictionary=state.histories.get("F4:load_test",{})
		if not _check(test.get("active",false) and int(test.get("test_serial",0))==serial,"actual live test remains in the same serial before reading "+side,test): return false
		var reading: Dictionary=test.get("readings",{}).get(side,{})
		if int(reading.get("test_serial",0))==serial:
			load_observations.append(_plain({"kind":"actual_G_gauge_read","seconds":_elapsed(),"target":target,"reading":reading,"position":_body().global_position,"test":test}))
			return true
		if _elapsed()>=next_press:
			if not _check(session.story.nearest(_body().global_position)==target,"ordinary nearest G resolves "+target,_status()): return false
			if not _check(_first_hit_from(_body().global_position,target).get("entity_id")==target,"actual complete first-hit ray reaches "+target): return false
			_record_g(target)
			next_press=_elapsed()+.6
		await _next()
	return _check(false,"bounded real same-serial gauge reading arrives for "+target,_mechanisms_debug())


func _wait_energy(required: float) -> bool:
	var deadline: float=minf(max_seconds-20.0,_elapsed()+20.0)
	while _healthy() and _elapsed()<deadline and (float(session.entities[session._actor_id(1)].get("energy",0))<required or float(session.cooldowns.get(1,0))>0): await _next()
	return _check(_healthy() and float(session.entities[session._actor_id(1)].get("energy",0))>=required,"ordinary real energy regeneration is sufficient before portable illumination",{"required":required,"actual":session.entities[session._actor_id(1)].get("energy")})


func _final_gate(label: String) -> Dictionary:
	var deadline: float=minf(max_seconds-20.0,_elapsed()+3.0)
	var current: Dictionary=session.campaign.mechanisms.final_lifelines_status(session.entities)
	while _healthy() and _elapsed()<deadline and str(current.get("code","")).ends_with("pose_pending"):
		await _next()
		current=session.campaign.mechanisms.final_lifelines_status(session.entities)
	final_gate_observations.append(_plain({"label":label,"seconds":_elapsed(),"status":current,"proposal":session.consensus.current_proposal(),"position":_body().global_position}))
	return current


func _ensure_actual_lifelines() -> bool:
	var sample: Dictionary=await _final_gate("before_actual_lifeline_check_or_repair")
	if sample.get("ok",false): return true
	if session.campaign.active() or not session.consensus.current_proposal().is_empty(): return _check(false,"active battle/pending proposal receives no remote repair or fabricated live gate",sample)
	if not await _connect_actual_industry(): return false
	if not await _grow_actual_living_lifeline(): return false
	sample=await _final_gate("after_real_input_lifeline_repair_before_any_proposal")
	return _check(sample.get("ok",false),"original fresh native industrial+light+full-support gate verifies current lifelines",sample)


func _prepare_actual_boss_devices() -> bool:
	_phase("original_independent_Boss_devices_before_normal_briefing")
	# Since plan is still incomplete, normal north-side inspection is permitted.
	# This never starts the encounter, changes its clock or edits an entity.
	var before: Dictionary=_mechanisms_debug()
	var state: Dictionary=session.campaign.mechanisms.boss_environment("F4")
	if _all_boss_fields(state):
		inherited_boss_devices=true
		environment_observations.append(_plain({"kind":"inherited_current_Boss_devices","seconds":_elapsed(),"environment":state}))
		return true
	if not _check(not session.campaign.active(),"all real independent Boss operations precede normal combat",before): return false
	var breaker: Node3D=session.world.objects["F4:core_charge_breaker"]
	if breaker.global_position.distance_to(Vector3(-5,14,-27))<1.4:
		if not await _approach(route.core_charge,"actual_Boss_charge_breaker_southwest_vantage"): return false
		if not await _operate_to_position("F4:core_charge_breaker",Vector3(-5,14,-24.5)): return false
	if float(session.entities["F4:core_thermal_sink"].get("temperature",200))>35:
		if not await _approach(route.core_thermal,"actual_Boss_thermal_sink_south_vantage"): return false
		for _cool: int in range(8):
			if float(session.entities["F4:core_thermal_sink"].get("temperature",200))<=35: break
			if not await _cast("F4:core_thermal_sink","heat",KEY_5,true): return false
	if float(session.entities["F4:core_living_support"].get("growth",0))<1.0 or not _full_native_growth_box("F4:core_living_support"):
		if not await _approach(route.core_growth,"actual_Boss_growth_volume_clear_south_vantage"): return false
		if not await _grow_full("F4:core_living_support",true): return false
	var deadline: float=minf(max_seconds-20.0,_elapsed()+5.0)
	while _healthy() and _elapsed()<deadline and not _all_boss_fields(session.campaign.mechanisms.boss_environment("F4")): await _next()
	var after: Dictionary=_mechanisms_debug()
	device_observations.append(_plain({"kind":"independent_Boss_devices","seconds":_elapsed(),"before":before,"after":after,"note":"Charge breaker displacement, real5/X thermal cooling and separate core full-span growth; no approach-device substitution."}))
	return _check(_all_boss_fields(after.boss_environment),"actual independent charge/thermal/living devices and both present lifelines jointly open final Boss gates",after)


func _all_boss_fields(sample: Dictionary) -> bool:
	for field: String in ["charge_loop_open","thermal_sink_ready","living_support_ready","both_lifelines_connected"]:
		if sample.get(field)!=true: return false
	return true


func _ensure_actual_boss_environment() -> bool:
	var sample: Dictionary=session.campaign.mechanisms.boss_environment("F4")
	var row: Dictionary={"kind":"current_Boss_environment","seconds":_elapsed(),"environment":sample,"proposal":session.consensus.current_proposal(),"devices":_mechanisms_debug()}
	environment_observations.append(_plain(row))
	return _check(_all_boss_fields(sample),"all four current physical Boss environment fields qualify; old action facts alone never open armour",row)


func _read_actual_three_plans() -> bool:
	if not await _approach(route.choice,"actual_three_plans_preread_terminal"): return false
	return await _read_or_choose_actual_panel(true)


func _read_or_choose_actual_panel(review_only: bool) -> bool:
	if not await _dismiss_radio(): return false
	var target: String=REVIEW_CHOICE if review_only else CHOICE
	_phase("original_three_CheckBoxes_"+("preread_only" if review_only else "final_signature"))
	if not _check(session.story.nearest(_body().global_position)=="F4:choice_terminal","ordinary near G resolves the actual shared terminal",_status()): return false
	if not review_only:
		var live: Dictionary=await _final_gate("at_terminal_before_final_G")
		if not _check(live.get("ok",false) and session.consensus.current_proposal().is_empty(),"actual native final lifelines are ready BEFORE any solo proposal",live): return false
	var spec: Dictionary=session.chapter_choices.specification(target)
	if not _check(spec.get("options",[]).size()==3 and bool(spec.get("review_only",false))==review_only,"original target presents the proper three-option read mode",spec): return false
	var branches_before: Array=session.store.snapshot().branches.keys()
	_record_g("F4:choice_terminal")
	await _next()
	var panel: Variant=session.interface.chapter_choice
	if not _check(panel.visible and panel._target==target and panel._review_only==review_only,"original G opens the actual current three-option panel"): return false
	var boxes: Array[CheckBox]=[]
	var panel_text: Array[String]=[]
	for child: Node in panel._content.get_children():
		if child is CheckBox: boxes.append(child)
		elif child is Label: panel_text.append(child.text)
	if not _check(boxes.size()==3 and panel._buttons.size()==(0 if review_only else 3),"actual panel has three separate read boxes and correct explicit proposal buttons",panel_text): return false
	for index: int in range(3):
		var option: Dictionary=spec.options[index]
		var text: String="收益："+str(option.benefit)+"\n负担："+str(option.cost)
		if not _check(not str(option.benefit).is_empty() and not str(option.cost).is_empty() and text in panel_text,"visible actual benefit/cost text precedes reading "+str(option.id),panel_text): return false
		var was_read: bool=boxes[index].button_pressed
		if not was_read and not await _ui_accept(boxes[index]): return false
		var identity: String=str(session.identities.get(1,""))
		var reading: Array=session.chapter_choices.readings.get(target,{}).get(identity,[])
		var row: Dictionary={"kind":"actual_CheckBox","target":target,"seconds":_elapsed(),"option":str(option.id),"identity":identity,"was_checked":was_read,"is_checked":boxes[index].button_pressed,"host_acknowledged":str(option.id) in reading,"visible_benefit_cost":text,"path":str(boxes[index].get_path()),"input":"previously acknowledged read" if was_read else "focused GUI ui_accept press/release"}
		gui_actions.append(row)
		if not _check(boxes[index].button_pressed and str(option.id) in reading,"original Host stable identity acknowledges actual GUI reading "+str(option.id),row): return false
	if not _check(session.chapter_choices.has_read_all(1,target),"original per-UUID table contains all three reads for this exact target"): return false
	if review_only:
		if not await _wait_completed(REVIEW,6.0): return false
		var after: Array=session.store.snapshot().branches.keys()
		if not _check(after==branches_before and not _completed(DECISION) and not session.story.state.get("choices",{}).has(DECISION) and session.campaign.mechanisms.persistent_state().histories.get("F4:plans_read",{}).size()==3,"preread completes80 without any final choice or new branch",_status()): return false
		_press_key(KEY_ESCAPE)
		await _next()
		return _check(not panel.visible,"ordinary Escape closes preread so later flight/abilities use normal input")
	# Re-sample before proposing. No input that can mutate a mechanism follows
	# the actual Button: a ready solo proposal blocks abilities by production.
	var current: Dictionary=await _final_gate("after_three_final_reads_before_explicit_proposal")
	if not _check(current.get("ok",false) and session.consensus.current_proposal().is_empty(),"original final prepare gate samples present native lifelines after all three UUID reads",current): return false
	var selected := -1
	for index: int in range(spec.options.size()):
		if str(spec.options[index].id)==CHOICE_OPTION: selected=index
	if not _check(selected>=0 and selected<panel._buttons.size(),"shared_stewardship is an actual offered final Button"): return false
	var button: Button=panel._buttons[selected]
	if not _check(not button.disabled and button.text=="提出："+str(spec.options[selected].label),"original explicit final Button is enabled after the three readings",{"text":button.text,"disabled":button.disabled}): return false
	if not await _ui_accept(button): return false
	gui_actions.append({"kind":"actual_final_Button","target":target,"option":CHOICE_OPTION,"seconds":_elapsed(),"path":str(button.get_path()),"input":"focused GUI ui_accept press/release","note":"original prepare/commit gate; no F/X after proposal"})
	if not await _wait_completed(DECISION,15.0): return false
	var saved: Dictionary=session.store.snapshot()
	var added: Array=[]
	for id: Variant in saved.branches:
		if id not in branches_before and str(id).begins_with("before-chapter-"): added.append(str(id))
	return _check(added.size()==1 and session.story.state.get("choices",{}).get(DECISION)==CHOICE_OPTION and session.consensus.current_proposal().is_empty(),"original final proposal creates one before-choice branch and commits shared_stewardship through native live gates",{"created_branches":added,"receipt":_receipt_for(DECISION),"readings":session.chapter_choices.readings})


func _observe_actual_ending() -> bool:
	var deadline: float=minf(max_seconds-20.0,_elapsed()+4.0)
	var ending: Dictionary=Catalog.ending(session.story.state.get("choices",{}))
	while _healthy() and _elapsed()<deadline and (not session.story.info().get("complete",false) or not str(session.interface.objective.text).contains(str(ending.get("title","missing_ending")))): await _next()
	var row: Dictionary={"seconds":_elapsed(),"ending":ending,"info":session.story.info(),"actual_objective_text":session.interface.objective.text,"original_detailed_text":session.story.objective_text(_body().global_position,true),"receipt":_receipt_for(DECISION),"completed":session.story.state.completed}
	ending_observations.append(_plain(row))
	return _check(ending.get("ending_id")==CHOICE_OPTION and ending.get("title")=="一起照料的脉络" and session.story.info().get("complete",false) and session.story.state.completed.size()==84 and str(session.interface.objective.text).contains(str(ending.title)),"original completed Director and visible normal objective HUD present Ending84, without a fictional85th record",row)


func _enter_actual_arena() -> bool:
	if not await _navigate([Vector3(_body().global_position.x,route.altitude,_body().global_position.z),route.briefing_high],"south_airlane_before_actual_entry"): return false
	_phase("continuous_native_cross_entry_no_static_final_attack_wait")
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



func _patrol() -> void:
	if not patrol_enabled or navigating or route.is_empty() or not session.campaign.active(): return
	var state: Dictionary=_boss_state()
	var attack: Dictionary=state.get("attack",{})
	var locked: bool=state.get("attack_stage") in ["warning","active"]
	var target: Vector3=last_patrol_target
	if locked and str(attack.get("token",""))!=patrol_warning_token:
		patrol_warning_token=str(attack.get("token",""))
		var shapes: Array=attack.get("shapes",[])
		if shapes.is_empty():
			_check(false,"original locked final attack contains its actual damage geometry",state)
			_stop("actual_attack_geometry_missing")
			return
		var centre: Vector3=_v(shapes[0].centre_mm)/1000.0
		var velocity: Vector3=_native_velocity()
		patrol_side=signf(velocity.x) if absf(velocity.x)>.25 else (1.0 if centre.x<=0 else -1.0)
		patrol_z_side=signf(velocity.z) if absf(velocity.z)>.25 else (-1.0 if centre.z>float(route.patrol_z) else 1.0)
		if absf(centre.x+patrol_side*6.0)>24.0: patrol_side=-signf(centre.x)
		if centre.z+patrol_z_side*6.0 < -35.0: patrol_z_side=1.0
		if centre.z+patrol_z_side*6.0 > 34.0: patrol_z_side=-1.0
		target=Vector3(centre.x+patrol_side*6.0,route.altitude,centre.z+patrol_z_side*6.0)
		_event("actual_warning_locked_then_continuous_diagonal_command",{"token":patrol_warning_token,"pattern":attack.get("pattern_id"),"shapes":shapes,"native_velocity":velocity,"target":target,"position":_body().global_position,"note":"Both planar coordinates change; pure X movement cannot leave both crossed lanes. High actual patrol lies above ring world-y15; disc/cross remain locked and require real movement. No attack time/pose/velocity edits."})
	elif not locked:
		if patrol_approach:
			if not last_patrol_target.is_finite() or _body().global_position.distance_to(last_patrol_target)<1.0:
				patrol_side=-1.0 if _body().global_position.x>0 else 1.0
				target=Vector3(patrol_side*float(route.patrol_extent),route.altitude,maxf(float(route.patrol_z),_body().global_position.z-6.0))
		elif not last_patrol_target.is_finite() or _body().global_position.distance_to(last_patrol_target)<1.0:
			patrol_side=-1.0 if _body().global_position.x>0 else 1.0
			patrol_z_side=-1.0 if _body().global_position.z>float(route.patrol_z) else 1.0
			target=Vector3(patrol_side*float(route.patrol_extent),route.altitude,float(route.patrol_z)+patrol_z_side*4.0)
	if target!=last_patrol_target:
		if not target.is_finite() or absf(target.x)>30.0 or target.z < -36.0 or target.z>35.0 or not _hull_clear(target):
			_check(false,"actual diagonal patrol target has full hull clearance inside ordinary bounds",{"target":target,"status":_status()})
			_stop("actual_patrol_candidate_blocked")
			return
		last_patrol_target=target
		command_serial+=1
		if not pilot.go_to(target,command_serial):
			_check(false,"ordinary Pilot accepts actual diagonal command",target)
			_stop("actual_patrol_command_rejected")



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
	return path.is_absolute_path() and "://" not in path and ".." not in path and "\n" not in path and "\r" not in path and path.get_file().begins_with("normal-f4-") and path.get_extension() == "json" and not FileAccess.file_exists(path) and not DirAccess.dir_exists_absolute(path)




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
	report_cache["f4_segment_complete"]=false
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
	print("NORMAL_F4_EXIT_WATCHDOG_FAIL "+JSON.stringify(report_cache.native_exit))
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
			report_cache["f4_segment_complete"]=false
			report_cache["requested_stage_stopped"]=false
			report_cache["failures"].append("Original final-exit audio drain did not become ready.")
	report_cache["engine_errors"]=_plain(logger.errors)
	if not logger.errors.is_empty():
		report_cache["complete"]=false
		report_cache["f4_segment_complete"]=false
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
		if completed!=EXPECTED.slice(0,completed.size()) or _receipts_digest(session.story.state,SOURCE_GOALS)!=initial_digest:
			_check(false,"actual Story retains exact original prefix and all75 source receipts",_status())
			_stop("original_prefix_changed")




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
	print("NORMAL_F4_EVENT "+JSON.stringify(row))




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
		print("NORMAL_F4_PROGRESS "+JSON.stringify(_plain(row)))




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
		_stop("normal_f4_complete" if value=="complete" else "requested_stage_pause")
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
	var complete: bool = reason=="normal_f4_complete" and failures.is_empty() and logger.errors.is_empty() and preserved and saved_now and matches_live and saved.world.actions.opening.completed==EXPECTED
	var stage_stopped: bool = reason=="requested_stage_pause" and stop_after in reached_stages and failures.is_empty() and logger.errors.is_empty() and preserved and saved_now and matches_live and preservation.common_paused
	if complete:
		for reward: String in [REWARD,"F4:operation_record"]:
			_check(saved.personal.discoveries.count(reward)==1,"original Boss reward/record is unique and durable: "+reward,saved.personal.discoveries)
		_check(saved.world.environment.I2_water.history.commissioned,"original commissioned clinic history remains durable after F4")
		complete=failures.is_empty()
	_write_report(reason,complete,stage_stopped)



func _write_report(reason: String,complete: bool,stage_stopped: bool) -> void:
	finished=true
	running=false
	var report: Dictionary={"complete":complete,"f4_segment_complete":complete,"requested_stage_stopped":stage_stopped,"requested_stage":stop_after,"reached_stages":reached_stages,"stop_reason":reason,"phase":phase,"seconds":_elapsed(),"max_seconds":max_seconds,"profile":SOURCE_PROFILE,"user_dir":OS.get_user_data_dir(),"executable":OS.get_executable_path(),"exported_application":not OS.has_feature("editor"),"runtime_cwd":DirAccess.open(".").get_current_dir(),"source_generation":initial.get("generation"),"initial_completed":initial.world.actions.opening.completed,"source_report_sha256":SOURCE_REPORT_SHA256,"source_receipts_sha256":initial_digest,"physics_frames":physics_frames,"actual_distance_m":actual_distance,"max_frame_distance_m_excluding_normal_travel":max_frame_distance,"checks":checks,"failures":failures,"engine_errors":logger.errors,"events":events,"ten_second_samples":samples,"route":route,"actual_abilities":actual_abilities,"actual_interactions":actual_interactions,"combat_transitions":combat_transitions,"actual_damage_samples":damage_samples,"actual_part_visits":part_visits,"actual_reveal_observations":reveal_observations,"actual_device_observations":device_observations,"actual_environment_observations":environment_observations,"actual_choice_ui_actions":gui_actions,"actual_load_observations":load_observations,"actual_growth_observations":growth_observations,"actual_final_gate_observations":final_gate_observations,"actual_ending_observations":ending_observations,"inherited_boss_devices":inherited_boss_devices,"inherited_goals":inherited_goals,"phase_two_observed":phase_two_observed,"battle_baseline":battle_baseline,"damage_evidence":damage_evidence,"inherited_committed_victory":inherited_victory,"attempt":original_attempt,"status":_status(),"preservation":preservation,"fresh_reader":final_reader,"story_receipts":session.story.state.get("receipts",{}),"stats":session.stats,"pilot":pilot.report() if pilot!=null and is_instance_valid(pilot.body) else {},"scope":"AUTHORING only, same natural I4 choice75 to F4 Ending84. Actual source75 path/SHA/exact receipt digest must be bound first. Ordinary MAIN/menu/M/spawn, unloaded QA Flight Pilot original inertia/full hull/stopping sweeps, near/LOS G, original6F inserted limited bus with emergency supply retained, original4F emitter30degree alignment and three7F full native collision growth, real G hold latch and two actual same-serial gauge readings, per-UUID three-option preread with no choice, independent Boss G charge breaker/5X cooling/4F plus7F separate core growth, real entry/full cycle and three-part two-phase reversed held weapon/LOS/HP chains, current four Boss environment fields, original victory Store/reward, actual final three CheckBoxes and focused ui_accept shared_stewardship Button through original prepare AND commit fresh-native lifeline gates, original final Store and normal visible Ending84, SaveGate/fresh reader/session._quit/audio drain. No fictional85th record, ActorPose/HP/time/delta/environment/Story/flags fixture, direct Store.commit/fire/encounter advance, profile clone/rollback/import, abilities after ready proposal, LAN/human/fun/full-game acceptance claim. All routes/normal combat remain unflown and may fail with legal progress preserved."}
	report.merge(SourceBinding.audit(_source_binding))
	report["native_exit"]={"requested":true,"through":"session._quit","observed_scene_exit":false,"watchdog_failed":false}
	report["actual_GUI_actions"]=gui_actions
	report_cache=_plain(report)
	var written: bool=_flush_report()
	print("NORMAL_F4_RESULT "+JSON.stringify({"complete":complete,"requested_stage_stopped":stage_stopped,"written":written,"reason":reason,"phase":phase,"seconds":_elapsed(),"failures":failures,"engine_errors":logger.errors}))
	native_exit_requested=true
	_native_exit_watchdog.call_deferred()
	session._quit()




func _boss_state() -> Dictionary:
	return session.campaign.encounter.get_state() if _live() and session.campaign.supported() else {}



func _wait_completed(objective: String, seconds: float) -> bool:
	var deadline: float=minf(max_seconds-10.0,_elapsed()+seconds)
	while _healthy() and not _completed(objective) and _elapsed()<deadline: await _next()
	return _check(_completed(objective),"original Story/Store completes "+objective,{"status":_status(),"receipt":_receipt_for(objective)})




func _ui_accept(button: BaseButton) -> bool:
	await _next() # allow the normal modal focus update before grabbing focus
	if not button.is_visible_in_tree() or button.disabled: return _check(false,"normal GUI target is visible and enabled",str(button.get_path()))
	button.grab_focus()
	await _next()
	if not _healthy() or not button.has_focus(): return false
	var press:=InputEventAction.new()
	press.action=&"ui_accept"
	press.pressed=true
	press.strength=1.0
	Input.parse_input_event(press)
	await _next()
	var release:=InputEventAction.new()
	release.action=&"ui_accept"
	release.pressed=false
	Input.parse_input_event(release)
	await _next()
	gui_actions.append({"kind":"actual_GUI_input","seconds":_elapsed(),"path":str(button.get_path()),"text":button.text,"input":"focused GUI ui_accept press/release"})
	return _healthy()


func _cast(target: String, ability: String, keycode: Key,reverse: bool=false) -> bool:
	if not _check(session.consensus.current_proposal().is_empty(),"ordinary ability precedes any pending/ready final proposal"): return false
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
	_press_key(KEY_X if reverse else KEY_F)
	var accepted: bool = int(session.stats.abilities)==before+1
	var row: Dictionary = {"seconds":_elapsed(),"ability":ability,"reverse":reverse,"target":target,"accepted":accepted,"actor_position":_body().global_position,"before":before_entity,"after":session.entities[target].duplicate(true),"ray":ray}
	actual_abilities.append(_plain(row))
	await _next()
	return _check(accepted,"original normal F/X Rules/Registry accepts "+ability+" on "+target,row)




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
	if session.region_id!="F4": return
	_observe_combat()
	if stopping: return
	if pilot!=null:
		_patrol()
		if stopping: return
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



func _fight() -> bool:
	_phase("actual_original_three_branches_two_phase_final_weapon_battle")
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
			return _check(state.get("completed",false) and phase_two_observed and damage_evidence.get("ok",false),"actual held weapon HP chains and original Store publish a real two-phase final victory",{"state":state,"evidence":damage_evidence})
		if state.is_empty(): return _check(false,"actual entered final Encounter remains present",_status())
		if damage_samples.size()!=observed_damage_count:
			observed_damage_count=damage_samples.size()
			last_progress=_elapsed()
		if _elapsed()-last_progress>35.0: return _check(false,"original weapon/LOS/recovery route makes actual HP progress within35 seconds",{"status":_status(),"state":state,"last_first_hit":_first_hit_from(_body().global_position,fire_target) if not fire_target.is_empty() else {}})
		if int(state.get("phase",0))==2 and "half" not in reached_stages:
			phase_two_observed=true
			environment_observations.append(_plain({"kind":"actual_phase2_Boss_environment","seconds":_elapsed(),"environment":session.campaign.mechanisms.boss_environment("F4")}))
			if _stage("half"): return false
		if not _all_boss_fields(session.campaign.mechanisms.boss_environment("F4")):
			wanted_fire=false
			_set_fire(false)
			return await _ensure_actual_boss_environment()
		var part: String=session.campaign.encounter.current_part()
		var target: String=session.world.campaign_arena.target_id(part)
		if target!=fire_target:
			wanted_fire=false
			_set_fire(false)
			if not await _select_target(target): return false
			fire_target=target
		wanted_fire=true
		await _next()
	return _check(false,"bounded actual physical flight and original held weapon finish final Boss",_status())


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
		var row: Dictionary={"seconds":_elapsed(),"state":state,"actual_position":_body().global_position,"native_velocity":_native_velocity(),"shots":session.stats.shots,"health":_body().health,"environment":session.campaign.mechanisms.boss_environment("F4")}
		combat_transitions.append(_plain(row))
		_event("actual_combat_transition",row)
	if not last_boss.is_empty():
		for part: String in ["charge_return","thermal_return","living_return","core"]:
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
	var parts: Array=["charge_return","thermal_return","living_return"]
	if baseline_phase==1:
		for part: String in parts: expected["1:"+part]=int(battle_baseline.parts[part])
		expected["1:core"]=int(battle_baseline.core_hp_milli)-half
		for part: String in parts: expected["2:"+part]=int(session.campaign.definition.part_hp_milli)
		expected["2:core"]=half
	else:
		for part: String in parts: expected["2:"+part]=int(battle_baseline.parts[part])
		expected["2:core"]=int(battle_baseline.core_hp_milli)
	var valid: bool=baseline_phase in [1,2] and not damage_samples.is_empty()
	for key: String in expected:
		var amount: int=int(totals.get(key,0))
		valid=valid and (amount==int(expected[key]) if key.ends_with(":core") else amount>=int(expected[key]))
	var phase2_living_seen := false
	for row: Dictionary in part_visits:
		if int(row.phase)==2 and row.part=="living_return": phase2_living_seen=true
	if baseline_phase==1 or int(battle_baseline.parts.get("living_return",0))>0: valid=valid and phase2_living_seen
	return {"ok":valid,"totals":totals,"required_remaining_from_actual_baseline":expected,"phase2_reverse_living_seen":phase2_living_seen,"baseline_phase":baseline_phase,"note":"Actual before/after HP chains with real shot counters; core240->120->0 clipped thresholds, not fixed9 per request. Timeout-rearmed parts allow extra part damage; inherited legitimate partial snapshots retain earlier evidence."}


func _mechanisms_debug() -> Dictionary:
	if not _live() or session.region_id!="F4" or session.campaign.mechanisms==null: return {}
	var result: Dictionary={"state":session.campaign.mechanisms.persistent_state(),"view":session.campaign.mechanisms.view_state(),"boss_environment":session.campaign.mechanisms.boss_environment("F4"),"final_native_lifelines":session.campaign.mechanisms.final_lifelines_status(session.entities),"current_Boss_state":_boss_state()}
	for id: String in ["F4:limited_bus","F4:industrial_load","F4:lifeline_bus","F4:living_emitter","F4:living_support","F4:test_hold","F4:industrial_gauge","F4:living_gauge","F4:core_charge_breaker","F4:core_thermal_sink","F4:core_living_support"]:
		result[id]=session.entities.get(id,{}).duplicate(true)
		if session.world.objects.has(id): result[id+":actual_position"]=session.world.objects[id].global_position
	return result


