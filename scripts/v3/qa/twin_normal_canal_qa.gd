extends Node
const SourceBinding = preload("res://scripts/v3/qa/twin_source_binding.gd")
static var _source_binding: Dictionary = {}
## AUTHORING ONLY. The actual natural Distribution34 source is NOT yet bound.
## Normal menu/Pilot/keys/G only. Original host modules own all physics/proof.
const Pilot = preload("res://scripts/v3/gameplay/canal/canal_transport_physics/transport_pilot.gd")
const Store = preload("res://scripts/v3/core/twin_world_store.gd")
const Director = preload("res://scripts/v3/gameplay/actions/twin_action_director.gd")
const Catalog = preload("res://scripts/v3/campaign/twin_campaign_catalog.gd")
const ClinicProgress = preload("res://scripts/v3/gameplay/actions/twin_clinic_progress.gd")
const DistributionProgress = preload("res://scripts/v3/gameplay/actions/twin_distribution_progress.gd")
const Cabinet = preload("res://scripts/v3/world/twin_distribution_cabinet.gd")
const I2Results = preload("res://scripts/v3/gameplay/twin_i2_result_ledger.gd")
const AbilityRules = preload("res://scripts/v3/gameplay/twin_ability_rules.gd")
const CanalAdapter = preload("res://scripts/v3/gameplay/twin_canal_session.gd")
const CanalRules = CanalAdapter.Assembly.Runtime
const CanalBench = CanalAdapter.Assembly.Workbench
static var SOURCE_PROFILE := "qa_normal_campaign_20261021_012725_b90f8a6f"
static var SOURCE_REPORT_SHA256 := "8f116915c2a9460f1b204b521f4e1f271f73184733b767f41d0c94297efbbbb8"
static var THIRTYFOUR_DIGEST := "58937558d8940309ce5fc25a018534db9c3eec239d9ff6c2da5b722dfe52a9ef"
static var THIRTYONE_DIGEST := ""
const BASE_THIRTYONE := ["I1:rescue:brief","I1:rescue:channel","I1:rescue:contact","I1:rescue:evacuate","I1:evidence:trace","I1:evidence:engineer","I1:evidence:ledger","I1:evidence:echo","F1:needs:listen","F1:needs:nursery","F1:needs:route","F1:repair:plan","F1:repair:light","F1:repair:grow","F1:repair:confirm","I1:whale:brief","I1:whale:engage","I1:whale:disable","I1:whale:record","F1:crown:brief","F1:crown:engage","F1:crown:disable","F1:crown:restore","I1:underdeck:read","I1:underdeck:enter","I1:underdeck:release","I1:underdeck:traverse","I2:clinic_supply:diagnose","I2:clinic_supply:connect","I2:clinic_supply:stabilize","I2:clinic_supply:confirm"]
const SOURCE_GOALS := ["I1:rescue:brief","I1:rescue:channel","I1:rescue:contact","I1:rescue:evacuate","I1:evidence:trace","I1:evidence:engineer","I1:evidence:ledger","I1:evidence:echo","F1:needs:listen","F1:needs:nursery","F1:needs:route","F1:repair:plan","F1:repair:light","F1:repair:grow","F1:repair:confirm","I1:whale:brief","I1:whale:engage","I1:whale:disable","I1:whale:record","F1:crown:brief","F1:crown:engage","F1:crown:disable","F1:crown:restore","I1:underdeck:read","I1:underdeck:enter","I1:underdeck:release","I1:underdeck:traverse","I2:clinic_supply:diagnose","I2:clinic_supply:connect","I2:clinic_supply:stabilize","I2:clinic_supply:confirm","I2:distribution_audit:expose","I2:distribution_audit:trace","I2:distribution_audit:share_access"]
const EXPECTED := ["I1:rescue:brief","I1:rescue:channel","I1:rescue:contact","I1:rescue:evacuate","I1:evidence:trace","I1:evidence:engineer","I1:evidence:ledger","I1:evidence:echo","F1:needs:listen","F1:needs:nursery","F1:needs:route","F1:repair:plan","F1:repair:light","F1:repair:grow","F1:repair:confirm","I1:whale:brief","I1:whale:engage","I1:whale:disable","I1:whale:record","F1:crown:brief","F1:crown:engage","F1:crown:disable","F1:crown:restore","I1:underdeck:read","I1:underdeck:enter","I1:underdeck:release","I1:underdeck:traverse","I2:clinic_supply:diagnose","I2:clinic_supply:connect","I2:clinic_supply:stabilize","I2:clinic_supply:confirm","I2:distribution_audit:expose","I2:distribution_audit:trace","I2:distribution_audit:share_access","I2:canal_service:brief","I2:canal_service:exchange","I2:canal_service:service","I2:canal_service:order"]
const STAGES := ["cooling","ordered","served","complete"]
const BRIEF := "I2:canal_service:brief"
const EXCHANGE := "I2:canal_service:exchange"
const SERVICE := "I2:canal_service:service"
const DISPATCH := "I2:canal_service:order"
const BRIEF_TARGET := "I2:canal_briefing"
const DISPATCH_TARGET := "I2:canal_dispatch"
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
var stop_after := "complete"
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
var site_transitions: Array = []
var fresh_ready_sample: Dictionary = {}
var local_cooling_sample: Dictionary = {}
var route: Dictionary = {}
var report_cache: Dictionary = {}
var native_exit_requested := false


static func preflight(args: PackedStringArray) -> Dictionary:
	_source_binding = {}
	var bound: Dictionary = SourceBinding.prepare(args,"normal-canal",SOURCE_GOALS,EXPECTED)
	if not bound.get("ok",false): return {"ok":false,"code":bound.get("code","source_binding_rejected"),"config":{}}
	_source_binding = bound.binding
	THIRTYONE_DIGEST = str(_source_binding.constants["THIRTYONE_DIGEST"])
	args = bound.args
	SOURCE_PROFILE = str(_source_binding.constants.get("SOURCE_PROFILE",SOURCE_PROFILE))
	SOURCE_REPORT_SHA256 = str(_source_binding.constants.get("SOURCE_REPORT_SHA256",SOURCE_REPORT_SHA256))
	THIRTYFOUR_DIGEST = str(_source_binding.constants.get("THIRTYFOUR_DIGEST",THIRTYFOUR_DIGEST))
	if SOURCE_REPORT_SHA256.length()!=64 or THIRTYFOUR_DIGEST.length()!=64: return {"ok":false,"code":"root_must_bind_actual_successful_distribution_evidence","config":{}}
	var values: Dictionary = {}
	for argument: String in args:
		var key := ""
		var value := ""
		if argument == "--qa-normal-canal":
			key = "enabled"
			value = "true"
		else:
			for pair: Array in [["--qa-profile=","profile"],["--qa-normal-output=","output"],["--qa-normal-seconds=","seconds"],["--qa-canal-stop-after=","stage"]]:
				if argument.begins_with(str(pair[0])):
					key = str(pair[1])
					value = argument.trim_prefix(str(pair[0]))
					break
		if key.is_empty() or value.is_empty() or values.has(key): return {"ok":false,"code":"unknown_empty_or_duplicate_canal_cli","config":{}}
		values[key] = value
	for key: String in ["enabled","profile","output","seconds"]:
		if not values.has(key): return {"ok":false,"code":"four_normal_canal_arguments_required","config":{}}
	if values.size() < 4 or values.size() > 5: return {"ok":false,"code":"invalid_canal_argument_count","config":{}}
	if values.profile != SOURCE_PROFILE or not DirAccess.dir_exists_absolute("user://profiles_v3/" + SOURCE_PROFILE): return {"ok":false,"code":"same_existing_natural_profile_required","config":{}}
	var seconds: String = str(values.seconds)
	if not seconds.is_valid_int() or str(seconds.to_int()) != seconds or seconds.to_int() < 30 or seconds.to_int() > 600: return {"ok":false,"code":"canal_seconds_30_to_600_required","config":{}}
	var stage: String = str(values.get("stage","complete"))
	if stage not in STAGES: return {"ok":false,"code":"invalid_canal_stop_stage","config":{}}
	var selected_output: String = str(values.output).replace("\\","/")
	if not _output_valid(selected_output): return {"ok":false,"code":"new_absolute_normal_canal_json_required","config":{}}
	var reader = Store.new("user://profiles_v3/" + SOURCE_PROFILE)
	var loaded: Dictionary = reader.load_profile()
	if not loaded.get("ok",false) or loaded.get("recovered",false): return {"ok":false,"code":"unrecovered_original_profile_required","config":{}}
	var saved: Dictionary = reader.snapshot()
	if not SourceBinding.start_matches(_source_binding,saved): return {"ok":false,"code":"source_binding_initial_snapshot_changed","config":{}}
	var verified: Dictionary = _source_check(saved)
	if not verified.ok: return {"ok":false,"code":verified.code,"config":{}}
	return {"ok":true,"code":"natural_canal_prefix_verified","config":{"profile":SOURCE_PROFILE,"output":selected_output,"max_seconds":seconds.to_int(),"stop_after":stage,"source_profile_id":saved.profile_id,"source_lineage_id":saved.lineage_id,"source_receipts_sha256":verified.source_receipts_sha256}}


static func _source_check(saved: Dictionary) -> Dictionary:
	if not SourceBinding.same_identity(_source_binding,saved): return {"ok":false,"code":"source_binding_identity_changed"}
	if SOURCE_REPORT_SHA256.length()!=64 or THIRTYFOUR_DIGEST.length()!=64: return {"ok":false,"code":"actual_distribution_evidence_not_bound"}
	var world: Variant = saved.get("world")
	if not world is Dictionary or world.get("region_id")!="I2" or world.get("branch_id")!="main": return {"ok":false,"code":"same_natural_I2_main_branch_required"}
	if not world.get("actions") is Dictionary or not world.actions.get("opening") is Dictionary or not world.get("flags") is Dictionary: return {"ok":false,"code":"source_story_schema"}
	var state: Dictionary = world.actions.opening
	var completed: Variant = state.get("completed")
	if not completed is Array or completed.size()<34 or completed.size()>38: return {"ok":false,"code":"only_natural_thirty_four_to_thirty_eight_prefix_accepted"}
	if completed!=EXPECTED.slice(0,completed.size()) or world.get("completed_objectives")!=completed or not state.get("receipts") is Dictionary or state.receipts.size()!=completed.size(): return {"ok":false,"code":"exact_natural_prefix_and_receipts_required"}
	if _receipts_digest(state,BASE_THIRTYONE)!=THIRTYONE_DIGEST or _receipts_digest(state,SOURCE_GOALS)!=THIRTYFOUR_DIGEST: return {"ok":false,"code":"actual_natural_source_receipts_changed"}
	var director = Director.new()
	var definitions: Dictionary = director.load_definitions(Director.DEFAULT_PATH,Catalog.extension_paths())
	if not definitions.get("ok",false): return {"ok":false,"code":"original_director_unavailable"}
	var valid: Dictionary = director.validate_state(state)
	if not valid.get("ok",false): return {"ok":false,"code":"original_director_replay_rejected:"+str(valid.get("code",""))}
	var flags: Dictionary = world.flags
	for flag: String in ["I1_gate","F1_gate","I1_boss","campaign_whale_v1","F1_boss","campaign_crown_v1","opening:underdeck_latched","opening:underdeck_route_verified","I2:clinic_ready","I2:distribution_back_observed","I2:distribution_trace_verified","I2:distribution_access_shared"]:
		if not flags.get(flag,false): return {"ok":false,"code":"actual_boss_underdeck_and_commissioned_clinic_history_required"}
	var discoveries: Variant = saved.get("personal",{}).get("discoveries")
	var commits: Variant = saved.get("ledger",{}).get("commits")
	if not discoveries is Array or not commits is Dictionary: return {"ok":false,"code":"original_reward_ledger_required"}
	for prefix: String in ["boss:I1:harbor_whale:opening_v1:main:","boss:F1:parasitic_crown:opening_v1:main:"]:
		var found := false
		for receipt: Variant in commits:
			if str(receipt).begins_with(prefix): found=true
		if not found: return {"ok":false,"code":"actual_two_boss_transactions_required"}
	for discovery: String in ["boss:I1:harbor_whale","opening:whale_raw_command_record","boss:F1:parasitic_crown","opening:crown_imbalance_evidence","opening:underdeck_worker_bypass","I2:clinic_priority_misroute","I2:distribution_back_route","I2:label_flow_disagreement","I2:shared_access_plan"]:
		if discoveries.count(discovery)!=1: return {"ok":false,"code":"actual_source_rewards_and_records_required"}
	var projected: Dictionary = I2Results.validate_world(world,discoveries)
	if not projected.get("ok",false): return {"ok":false,"code":"original_I2_result_boundary:"+str(projected.get("error",""))}
	var clinic_tracker = ClinicProgress.new()
	var clinic: Dictionary = projected.projected.clinic
	var water: Dictionary = clinic_tracker.prepare_restore(world.get("environment",{}).get("I2_water"),clinic.completed,clinic.flags)
	if not water.get("ok",false): return {"ok":false,"code":"original_clinic_water_history:"+str(water.get("code",""))}
	if not world.get("environment",{}).get("I2_water",{}).get("history",{}).get("commissioned",false): return {"ok":false,"code":"durable_actual_clinic_commission_required"}
	var layout: Variant = JSON.parse_string(FileAccess.get_file_as_string(Cabinet.PATH))
	if not layout is Dictionary: return {"ok":false,"code":"original_distribution_layout_unavailable"}
	var tracker = DistributionProgress.new()
	var configured: Dictionary = tracker.configure(layout)
	if not configured.get("ok",false): return {"ok":false,"code":"original_distribution_layout_rejected"}
	var distribution: Dictionary = projected.projected.distribution
	var restored: Dictionary = tracker.prepare_restore(world.get("environment",{}).get("I2_distribution"),distribution.completed,distribution.flags,distribution.discoveries,true)
	if not restored.get("ok",false): return {"ok":false,"code":"original_distribution_history:"+str(restored.get("code",""))}
	# Ordinary Session still validates and attaches original Trial/Bridge/Canal
	# native state. This preflight invents no geometry or observation proof.
	return {"ok":true,"code":"natural_canal_prefix_valid","completed":completed.duplicate(),"source_receipts_sha256":THIRTYFOUR_DIGEST}


func run(owner_session: Node, options: Dictionary = {}) -> Dictionary:
	if running or stopping or finished: return {"ok":false,"code":"already_started"}
	session = owner_session
	output = str(options.get("output","")).replace("\\","/")
	max_seconds = float(options.get("max_seconds",600))
	stop_after = str(options.get("stop_after","complete"))
	if not is_instance_valid(session) or not is_inside_tree() or options.get("profile") != SOURCE_PROFILE or session.store.root_path != "user://profiles_v3/"+SOURCE_PROFILE or not _output_valid(output) or not is_finite(max_seconds) or max_seconds < 30 or max_seconds > 600 or stop_after not in STAGES: return {"ok":false,"code":"mounted_same_profile_new_output_and_bound_required"}
	initial = session.store.snapshot()
	if not SourceBinding.start_matches(_source_binding,initial): return {"ok":false,"code":"source_binding_initial_snapshot_changed"}
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
	return {"ok":true,"code":"observing_natural_canal","stop_after":stop_after,"max_seconds":max_seconds}


func _execute() -> void:
	if not _check(session.profile_ready and not session.active and not OS.has_feature("editor"),"actual exported MAIN before ordinary menu continuation"): _stop("exported_normal_menu_required"); return
	last_completed=initial.world.actions.opening.completed.duplicate()
	_phase("ordinary_menu_resume_natural_distribution_profile")
	session._ui_action("solo",{"frame":0})
	await _next()
	if not _healthy() or not _check(_receipts_digest(session.story.state,SOURCE_GOALS)==initial_digest,"normal menu retains all actual thirty-four source receipts",_status()): _stop("ordinary_source_resume_failed"); return
	if not await _dismiss_radio(): _stop("radio_not_closed"); return
	if not _check(session.region_id=="I2" and session.canal_runtime_enabled and session.canal!=null and is_instance_valid(session.canal.module),"normal I2 installs its enabled canonical Canal Assembly",_status()): _stop("normal_canal_not_installed"); return
	_bind_pilot()
	_phase("ordinary_native_bootstrap_or_saved_contact_reobservation")
	var boot_deadline: float = minf(max_seconds-10.0,_elapsed()+120.0)
	while _healthy() and not session.canal.ready and _elapsed()<boot_deadline: await _next()
	if not _check(session.canal.ready and session.canal.module.status().ready and not session.canal.context().is_empty(),"original bootstrap/restore reaches a live current native WORK and carrier without QA placement",_site_debug()): _stop("original_canal_bootstrap_not_ready"); return
	route=_route_definition()
	if not _check(not route.is_empty(),"normal route derives from current adapter registry, native WORK/berths/power and current Story markers",route): _stop("current_canal_route_unavailable"); return
	if not _completed(BRIEF):
		if not await _marker_contact(BRIEF_TARGET,BRIEF): _stop("normal_canal_brief_G_not_committed"); return
	if not await _dismiss_radio(): _stop("brief_radio_not_closed"); return
	if not _completed(EXCHANGE):
		if not await _prepare_local_cooling(): _stop("actual_WORK_cooling_or_durable_preparation_unproven"); return
	else: _event("inherited_original_cassette_preparation",{"receipt":_receipt_for(EXCHANGE),"site":_site_debug(),"note":"Historical proof is retained; today's warmer or relocated cartridge is not relabeled as a new 70-to-45 operation."})
	if _stage("cooling"): return
	if not await _dismiss_radio(): _stop("cooling_radio_not_closed"); return
	if not _completed(SERVICE):
		if not await _order_and_power(): _stop("original_order_or_actual_power_input_unproven"); return
	else: _event("inherited_original_order_and_service",{"receipt":_receipt_for(SERVICE),"site":_site_debug()})
	if _stage("ordered"): return
	if not _completed(SERVICE):
		if not await _wait_and_claim_service(): _stop("actual_safe_site_or_G_Store_service_unproven"); return
	if not _check(_service_consumed_exact(),"original first service consumption and native beneficiary wait agree with current Store",_site_debug()): _stop("native_and_durable_service_disagree"); return
	if _stage("served"): return
	if not await _dismiss_radio(): _stop("service_radio_not_closed"); return
	if not _completed(DISPATCH):
		if not await _dispatch_contact(): _stop("normal_dispatch_G_not_committed"); return
	else: _event("inherited_original_dispatch",{"receipt":_receipt_for(DISPATCH)})
	if not _check(session.story.state.get("completed",[])==EXPECTED and _receipts_digest(session.story.state,SOURCE_GOALS)==initial_digest,"only the four original Canal goals extend intact Distribution34",_status()): _stop("canal_final_prefix_unproven"); return
	_stage("complete")

func _route_definition() -> Dictionary:
	var ctx: Dictionary = session.canal.context()
	if ctx.is_empty() or ctx.get("rules")==null or ctx.get("custody")==null or not is_instance_valid(ctx.get("workbench")): return {}
	var work: Variant = ctx.berths.get(CanalRules.WORK)
	var south0: Variant = ctx.berths.get(CanalRules.SOUTH_0)
	var south1: Variant = ctx.berths.get(CanalRules.SOUTH_1)
	var hot: Variant = ctx.cargos.get(CanalRules.CASSETTES[1])
	if not work is StaticBody3D or not south0 is StaticBody3D or not south1 is StaticBody3D or not hot is RigidBody3D: return {}
	var power: Vector3 = ctx.workbench.power_target.global_position
	var west: Vector3 = power+Vector3(-1.6,1.75,0)
	var brief: Vector3 = _v(session.story.markers.get(BRIEF_TARGET,{}).get("position"))
	var dispatch: Vector3 = _v(session.story.markers.get(DISPATCH_TARGET,{}).get("position"))
	if not brief.is_finite() or not dispatch.is_finite() or not power.is_finite() or west.y>=_body().max_altitude: return {}
	return {"work_berth":work.global_position,"work_cassette_initial_native":hot.global_position,"power_actual":power,"west_service_view":west,
		"south_approach_z":maxf(south0.global_position.z,south1.global_position.z)-6.0,
		"brief_actual":brief,"dispatch_actual":dispatch,
		"cooling_offsets":[Vector3(-2.8,2.35,1),Vector3(-3.0,2.35,2),Vector3(-3.2,2.55,1)],
		"carrier_offsets":[Vector3(-3.5,1,0),Vector3(-4,1.2,.8),Vector3(-3.5,1.5,-.8)],
		"dispatch_candidates":[dispatch+Vector3(1.5,0,0)],
		"canonical_namespace":CanalAdapter.IDS.duplicate(),"note":"No static old candidate path is installed or assumed. Every device position is read again at actual use."}

func _marker_contact(target: String, objective: String) -> bool:
	if not await _dismiss_radio(): return false
	if session.story.nearest(_body().global_position)==target: return await _contact(target,objective)
	var marker: Dictionary = session.story.markers.get(target,{})
	var at: Vector3 = _v(marker.get("position"))
	if not at.is_finite(): return _check(false,"current normal Story marker exists",target)
	var candidates: Array = [at+Vector3(0,.2,1.2),at+Vector3(-1,.2,0),at]
	var chosen := Vector3.INF
	for point: Vector3 in candidates:
		if _hull_clear(point) and session.story.nearest(point)==target:
			chosen=point
			break
	if not _check(chosen.is_finite(),"actual complete hull and nearest G admit the current marker candidate",{"target":target,"candidates":candidates}): return false
	if not await _navigate([chosen],"normal_marker:"+target): return false
	return await _contact(target,objective)

func _prepare_local_cooling() -> bool:
	_phase("normal_5_Tab_X_actual_WORK_local_cooling")
	var ctx: Dictionary = session.canal.context()
	var state: Dictionary = ctx.rules.snapshot()
	var id: String = CanalRules.CASSETTES[1]
	if not _check(state.cassettes[id].holder==CanalRules.WORK and int(state.jobs_completed)==0,"unfinished local preparation still addresses the original native WORK cassette",state): return false
	var west: Vector3 = route.west_service_view
	var south_z: float = route.south_approach_z
	if not await _navigate([Vector3(west.x,3.2,south_z),Vector3(west.x,2.8,9.5)],"low_west_airlane_to_actual_WORK"): return false
	var cargo: RigidBody3D = ctx.cargos[id]
	var candidates: Array = []
	for offset: Vector3 in route.cooling_offsets: candidates.append(cargo.global_position+offset)
	var chosen: Vector3 = _visible_candidate(candidates,[id])
	if not _check(chosen.is_finite(),"actual WORK cartridge first-hit ray and full hull have a clear west viewpoint",{"candidates":candidates,"rays":_candidate_rays(candidates,[id])}): return false
	if not await _navigate([chosen],"actual_WORK_cassette_view"): return false
	var before: Dictionary = ctx.rules.snapshot()
	var before_temperature: float = float(ctx.rules.status().temperatures_c[id])
	if before_temperature>45.0:
		if not await _cast(id,"heat",KEY_5,true): return false
		var after: Dictionary = ctx.rules.snapshot()
		var after_temperature: float = float(ctx.rules.status().temperatures_c[id])
		if not _check(after_temperature==before_temperature-25.0 and int(after.thermal_ledger.ability_removed)-int(before.thermal_ledger.ability_removed)==25000000 and int(after.command_serial)==int(before.command_serial)+1,"normal X removes the original 25kJ/25C through canonical thermal accounting",{"before_c":before_temperature,"after_c":after_temperature,"before_rules":before,"after_rules":after}): return false
	else: _event("inherited_original_cold_WORK_state",{"temperature_c":before_temperature,"rules":before,"note":"No new thermal ability is claimed."})
	var deadline: float = minf(max_seconds-10.0,_elapsed()+8.0)
	while _healthy() and _elapsed()<deadline:
		await _next()
		if session.canal.exchange_fact()=="local_cooling" and _cold_supported(): break
	local_cooling_sample=_local_cooling_debug()
	if not _check(session.canal.exchange_fact()=="local_cooling" and _cold_supported(),"same actual WORK body remains cold, uniquely supported with original 350ms Custody and effective native thermal removal",local_cooling_sample): return false
	_event("actual_current_local_cooling_preparation",local_cooling_sample)
	deadline=minf(max_seconds-10.0,_elapsed()+8.0)
	while _healthy() and not _completed(EXCHANGE) and _elapsed()<deadline: await _next()
	return _check(_completed(EXCHANGE) and _receipt_for(EXCHANGE).get("option")=="local_cooling" and int(ctx.executor._receipt_count)==0,"original Story/Store seals actual local cooling without inventing transport receipts",{"receipt":_receipt_for(EXCHANGE),"site":_site_debug()})

func _cold_supported() -> bool:
	var ctx: Dictionary = session.canal.context()
	if ctx.is_empty(): return false
	var id: String = CanalRules.CASSETTES[1]
	var state: Dictionary = ctx.rules.snapshot()
	var physical: Dictionary = ctx.custody.report().cargos.get(id,{})
	var support: Dictionary = ctx.custody.support_info(id,CanalRules.WORK)
	return state.cassettes[id].holder==CanalRules.WORK and float(ctx.rules.status().temperatures_c[id])<=45.0 and physical.get("phase")=="docked" and physical.get("berth")==CanalRules.WORK and int(physical.get("stable_usec",0))==CanalAdapter.WaitCheckpoint.Custody.STABLE_USEC and support.get("supported",false) and support.get("cargo_rid")==ctx.cargos[id].get_rid() and support.get("support_rid")==ctx.berths[CanalRules.WORK].get_rid() and int(state.thermal_ledger.ability_removed)>=25000000

func _local_cooling_debug() -> Dictionary:
	var ctx: Dictionary = session.canal.context()
	if ctx.is_empty(): return {}
	var id: String = CanalRules.CASSETTES[1]
	return {"physics_frame":Engine.get_physics_frames(),"rules":ctx.rules.snapshot(),"temperatures":ctx.rules.status().temperatures_c,"cassette_position":ctx.cargos[id].global_position,"cassette_rid":str(ctx.cargos[id].get_rid()),"custody":ctx.custody.report(),"support":ctx.custody.support_info(id,CanalRules.WORK),"exchange_fact":session.canal.exchange_fact(),"source":"original_current_frame_custody_and_thermal_rules"}

func _order_and_power() -> bool:
	_phase("normal_carrier_0_Tab_F_order_then_real_bench_6_Tab_F_power")
	if not await _dismiss_radio(): return false
	var west: Vector3 = route.west_service_view
	var south_z: float = route.south_approach_z
	var assembly: Dictionary = session.canal.module.status()
	if not assembly.ordered:
		var ctx: Dictionary = session.canal.context()
		var carrier: Vector3 = ctx.carrier.global_position
		var candidates: Array = []
		for offset: Vector3 in route.carrier_offsets: candidates.append(carrier+offset)
		var chosen: Vector3 = _visible_candidate(candidates,[CanalAdapter.Assembly.CARRIER_ID])
		if not _check(chosen.is_finite(),"real carrier is visible from a hull-clear south approach",{"candidates":candidates,"rays":_candidate_rays(candidates,[CanalAdapter.Assembly.CARRIER_ID])}): return false
		if not await _navigate([Vector3(west.x,3.2,south_z),Vector3(chosen.x,chosen.y,south_z),chosen],"outside_original_carrier_return_lane_to_order"): return false
		if not await _cast(CanalAdapter.Assembly.CARRIER_ID,"takeover",KEY_0): return false
		if not _check(session.canal.module.status().ordered,"normal carrier takeover configures the one original Executor work order",_site_debug()): return false
	else: _event("inherited_original_Assembly_order",assembly)
	if not await _navigate([Vector3(west.x,3.2,south_z),Vector3(west.x,3.2,west.z),west],"west_safe_service_view_outside_native_transport_and_departure"): return false
	var bench: Dictionary = session.canal.context().workbench.report()
	if not bench.powered:
		if not await _cast(CanalBench.POWER_ID,"charge",KEY_6): return false
	bench=session.canal.context().workbench.report()
	return _check(session.canal.module.status().ordered and bench.powered and float(bench.charge)>=20.0,"original order plus real workbench power enable physical scanning; neither is a service claim",_site_debug())

func _wait_and_claim_service() -> bool:
	_phase("observe_actual_scan_departure_cleanup_and_fresh_safe_site")
	var deadline: float = minf(max_seconds-10.0,_elapsed()+300.0)
	var next_poll := 0.0
	var last_key := ""
	while _healthy() and _elapsed()<deadline:
		await _next()
		var service: Dictionary = session.canal.story_service_status()
		if service.get("ready_credit",false):
			fresh_ready_sample={"physics_frame":Engine.get_physics_frames(),"last_Assembly_frame":session.canal.module.status().last_physics_frame,"service":service,"site":_site_debug()}
			_event("original_same_frame_safe_service_ready",fresh_ready_sample)
			break
		if _elapsed()<next_poll: continue
		next_poll=_elapsed()+.5
		var state: Dictionary = _rules()
		var bench: Dictionary = session.canal.context().workbench.report()
		var executor: Dictionary = session.canal.context().executor.report()
		var key: String = JSON.stringify([bench.phase,bench.measurements.size(),bench.committed,executor.phase,state.pending_action.get("kind"),state.action_serial,state.jobs_completed,service.get("code")])
		if key!=last_key:
			last_key=key
			var row: Dictionary = {"seconds":_elapsed(),"physics_frame":Engine.get_physics_frames(),"site":_site_debug()}
			site_transitions.append(_plain(row))
			_event("original_site_phase_changed",row)
		if bench.phase=="fault" or executor.phase=="fault": return _check(false,"canonical physical controllers remain healthy",_site_debug())
	var ready: Dictionary = session.canal.story_service_status()
	if not _check(not fresh_ready_sample.is_empty() and ready.get("ready_credit",false) and int(fresh_ready_sample.physics_frame)==Engine.get_physics_frames(),"actual current-frame Safe readiness follows real scan, departure, both docked cargos and idle carrier",_site_debug()): return false
	if not await _contact(CanalBench.POWER_ID,SERVICE): return false
	return _check(_service_consumed_exact(),"normal near/LOS G consumes exactly the original service credit in the same Story/Store transaction",_site_debug())

func _service_consumed_exact() -> bool:
	if not _completed(SERVICE): return false
	var ctx: Dictionary = session.canal.context()
	if ctx.is_empty(): return false
	var state: Dictionary = ctx.rules.snapshot()
	var disk: Dictionary = session.store.snapshot().world.get("environment",{}).get("I2_canal",{}).get("rules",{})
	return int(state.get("jobs_completed",-1))==1 and int(state.get("services_consumed",-1))==1 and int(state.get("service_credit",-1))==0 and int(state.get("service_serial",-1))==1 and int(disk.get("jobs_completed",-1))==1 and int(disk.get("services_consumed",-1))==1 and int(disk.get("service_credit",-1))==0 and int(disk.get("service_serial",-1))==1 and ctx.executor.report().get("waiting_for_beneficiary",false) and session.canal.story_service_status().get("claimed",false) and _receipt_for(SERVICE).get("option")=="repaired"

func _dispatch_contact() -> bool:
	_phase("normal_G_current_dispatch_record")
	var west: Vector3 = route.west_service_view
	var candidates: Array = route.dispatch_candidates
	var chosen := Vector3.INF
	var diagnostics: Array = []
	for point: Vector3 in candidates:
		var clear: bool = _hull_clear(point)
		var nearest: String = session.story.nearest(point)
		diagnostics.append({"point":point,"hull_clear":clear,"nearest":nearest})
		if clear and nearest==DISPATCH_TARGET:
			chosen=point
			break
	if not _check(chosen.is_finite(),"actual current dispatch marker has a hull-clear nearest-G candidate",{"candidates":diagnostics}): return false
	# Normal37 resume uses the original spawn, not the previous service pose.
	var hops: Array = []
	if _body().global_position.x<west.x-1.0: hops.append(Vector3(west.x,3.2,route.south_approach_z))
	hops.append_array([Vector3(west.x,3.0,1.9),Vector3(chosen.x,chosen.y,1.9),chosen])
	# Native full sweeps include .22 arrival error + .36 braking expansion;
	# the former front views occupied WestTrackPier1. Physical Pilot still rules.
	if not await _navigate(hops,"under_real_bridge_to_dispatch_front"): return false
	return await _contact(DISPATCH_TARGET,DISPATCH)

func _rules() -> Dictionary:
	var ctx: Dictionary = session.canal.context()
	return ctx.rules.snapshot() if not ctx.is_empty() and ctx.get("rules")!=null else {}

func _site_debug() -> Dictionary:
	if not _live() or session.canal==null or not is_instance_valid(session.canal.module): return {}
	var ctx: Dictionary = session.canal.context()
	var result: Dictionary = {"adapter":session.canal.status(),"Assembly":session.canal.module.status(),"service":session.canal.story_service_status(),"physics_frame":Engine.get_physics_frames()}
	if not ctx.is_empty():
		result["rules"]=ctx.rules.snapshot() if ctx.get("rules")!=null else {}
		result["custody"]=ctx.custody.report() if ctx.get("custody")!=null else {}
		result["executor"]=ctx.executor.report() if is_instance_valid(ctx.get("executor")) else {}
		result["workbench"]=ctx.workbench.report() if is_instance_valid(ctx.get("workbench")) else {}
		result["carrier_position"]=ctx.carrier.global_position if is_instance_valid(ctx.get("carrier")) else Vector3.INF
		result["carrier_native_velocity"]=PhysicsServer3D.body_get_state(ctx.carrier.get_rid(),PhysicsServer3D.BODY_STATE_LINEAR_VELOCITY) if is_instance_valid(ctx.get("carrier")) else Vector3.INF
	return result


func _cast(target: String, ability: String, keycode: Key, reverse: bool = false) -> bool:
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
	var deadline: float = minf(max_seconds-10.0,_elapsed()+8.0)
	while _healthy() and (float(session.cooldowns.get(1,0))>0 or float(session.entities[session._actor_id(1)].energy)<cost or ability=="takeover" and float(session.entities[target].get("takeover_remaining",0))>0) and _elapsed()<deadline: await _next()
	if not _healthy(): return false
	var ray: Dictionary = _first_hit_from(_body().global_position,target)
	if not _check(ray.get("entity_id")==target,"actual complete first-hit ray reaches "+target,ray): return false
	var before: int = int(session.stats.abilities)
	var before_entity: Dictionary = session.entities[target].duplicate(true)
	_press_key(KEY_X if reverse else KEY_F)
	var accepted: bool = int(session.stats.abilities)==before+1
	var row: Dictionary = {"seconds":_elapsed(),"ability":ability,"reverse":reverse,"target":target,"accepted":accepted,"actor_position":_body().global_position,"before":before_entity,"after":session.entities[target].duplicate(true),"ray":ray}
	actual_abilities.append(_plain(row))
	await _next()
	return _check(accepted,"original normal F-or-X/Rules/CanalAdapter accepts "+ability+" on "+target,row)


func _completed(id: String) -> bool:
	return id in session.story.state.get("completed",[])

func _receipt_for(objective: String) -> Dictionary:
	for value: Variant in session.story.state.get("receipts",{}).values():
		if value is Dictionary and value.get("objective_id")==objective: return value.duplicate(true)
	return {}

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
	return path.is_absolute_path() and "://" not in path and ".." not in path and "\n" not in path and "\r" not in path and path.get_file().begins_with("normal-canal-") and path.get_extension() == "json" and not FileAccess.file_exists(path) and not DirAccess.dir_exists_absolute(path)

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
			if distance<.22 and _body().linear_velocity.length()<.22: break
			if distance<best_distance-.12:
				best_distance=distance
				last_progress=_elapsed()
			if _elapsed()-last_progress>12.0: return _check(false,"ordinary Pilot makes real route progress",{"label":label,"goal":goal,"pilot":pilot.report(),"status":_status(),"classification":"bounded_driver_route_stall"})
		if not _healthy() or not _check(distance<.22 and _body().linear_velocity.length()<.22,"continuous native flight reaches "+label,{"goal":goal,"position":_body().global_position,"pilot":pilot.report()}): return false
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

func _stage(value: String) -> bool:
	if value not in reached_stages: reached_stages.append(value)
	_event("actual_stage_observed",{"stage":value,"state":_site_debug(),"status":_status()})
	if stop_after==value:
		_stop("normal_canal_complete" if value=="complete" else "requested_stage_pause")
		return true
	return false

func _stop(reason: String) -> void:
	if stopping or finished: return
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
	var complete: bool = reason=="normal_canal_complete" and failures.is_empty() and logger.errors.is_empty() and preserved and saved_now and matches_live and saved.world.actions.opening.completed==EXPECTED
	var stage_stopped: bool = reason=="requested_stage_pause" and stop_after in reached_stages and failures.is_empty() and logger.errors.is_empty() and preserved and saved_now and matches_live and preservation.common_paused
	if complete:
		for reward: String in ["I2:canal_calibration","I2:pump_priority_order"]:
			_check(saved.personal.discoveries.count(reward)==1,"original Canal discovery is unique and durable: "+reward,saved.personal.discoveries)
		_check(saved.world.environment.I2_water.history.commissioned,"original commissioned clinic history remains durable; trial did not rewrite its water result")
		complete=failures.is_empty()
	_write_report(reason,complete,stage_stopped)

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
	report_cache["canal_segment_complete"]=false
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
	print("NORMAL_CANAL_EXIT_WATCHDOG_FAIL "+JSON.stringify(report_cache.native_exit))
	# Do not use tree.quit/OS.kill as a fallback around a rejected Store gate.
	# The runner's already bounded private Job remains the external hard limit.

func _exit_tree() -> void:
	if not native_exit_requested or report_cache.is_empty(): return
	report_cache["native_exit"]["observed_scene_exit"]=true
	if is_instance_valid(session):
		report_cache["native_exit"]["audio"]=_plain(session.last_audio_shutdown_result)
		if not session.last_audio_shutdown_result.get("ready",false):
			report_cache["complete"]=false
			report_cache["canal_segment_complete"]=false
			report_cache["requested_stage_stopped"]=false
			report_cache["failures"].append("Original final-exit audio drain did not become ready.")
	report_cache["engine_errors"]=_plain(logger.errors)
	if not logger.errors.is_empty():
		report_cache["complete"]=false
		report_cache["canal_segment_complete"]=false
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
	print("NORMAL_CANAL_EVENT "+JSON.stringify(row))

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
		print("NORMAL_CANAL_PROGRESS "+JSON.stringify(_plain(row)))

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
		result["water"]=_site_debug()
		result["pilot"]=pilot.report() if pilot!=null else {}
	return result

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
	if pilot!=null: pilot.tick(delta,true,false)

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

func _candidate_rays(points: Array, targets: Array) -> Array:
	var rows: Array = []
	for point: Vector3 in points:
		var rays: Array = []
		for target: String in targets: rays.append(_first_hit_from(point,target))
		rows.append({"point":point,"hull_clear":_hull_clear(point),"rays":rays})
	return rows

func _visible_candidate(points: Array, targets: Array) -> Vector3:
	for point: Vector3 in points:
		if not _hull_clear(point): continue
		var visible := true
		for target: String in targets:
			if _first_hit_from(point,target).get("entity_id")!=target: visible=false
		if visible: return point
	return Vector3.INF

func _record_g(target: String) -> void:
	var before: Dictionary = {"generation":session.store.snapshot().get("generation"),"completed":session.story.state.get("completed",[]).duplicate(),"proposal":session.consensus.current_proposal()}
	_press_g()
	actual_interactions.append(_plain({"seconds":_elapsed(),"target":target,"actor_position":_body().global_position,"before":before,"after_generation":session.store.snapshot().get("generation"),"after_proposal":session.consensus.current_proposal(),"message":session.interface.message.text}))


func _write_report(reason: String, complete: bool, stage_stopped: bool) -> void:
	finished=true
	running=false
	var report: Dictionary = {"complete":complete,"canal_segment_complete":complete,"requested_stage_stopped":stage_stopped,"requested_stage":stop_after,"reached_stages":reached_stages,"stop_reason":reason,"phase":phase,"seconds":_elapsed(),"max_seconds":max_seconds,"profile":SOURCE_PROFILE,"user_dir":OS.get_user_data_dir(),"executable":OS.get_executable_path(),"exported_application":not OS.has_feature("editor"),"runtime_cwd":DirAccess.open(".").get_current_dir(),"source_generation":initial.get("generation"),"base_thirty_one_receipts_sha256":THIRTYONE_DIGEST,"source_report_sha256":SOURCE_REPORT_SHA256,"source_receipts_sha256":initial_digest,"physics_frames":physics_frames,"actual_distance_m":actual_distance,"max_frame_distance_m_excluding_normal_travel":max_frame_distance,"checks":checks,"failures":failures,"engine_errors":logger.errors,"events":events,"ten_second_samples":samples,"route":route,"actual_abilities":actual_abilities,"actual_interactions":actual_interactions,"actual_site_transitions":site_transitions,"actual_local_cooling":local_cooling_sample,"fresh_service_ready":fresh_ready_sample,"status":_status(),"preservation":preservation,"fresh_reader":final_reader,"story_receipts":session.story.state.get("receipts",{}),"stats":session.stats,"pilot":pilot.report() if pilot!=null and is_instance_valid(pilot.body) else {},"scope":"Exported MAIN same natural Distribution34-to-Canal38 continuation. Original bootstrap/restore and current canonical namespace; normal menu/spawn, actual continuous Flight/Pilot, normal 5/Tab/X effective WORK local cooling with original350ms Custody, 0/Tab/F original carrier order, 6/Tab/F actual bench charge, real three-endpoint scanning and departure, actual cleanup transport/docking and fresh Safe readiness, near/LOS G same-Store service consumption, dispatch G, original SaveGate/fresh reader/native audio quit. No imported progress/receipt/profile, pose/heat/water/HP/time/flags fixture, manual controller advancement, rollback, direct service preparation/adoption or reward write. Older legal physical histories are explicitly inherited. No I2Boss/whole-campaign/fun/LAN/controller/performance acceptance."}
	report.merge(SourceBinding.audit(_source_binding))
	report["native_exit"]={"requested":true,"through":"session._quit","observed_scene_exit":false,"watchdog_failed":false}
	report_cache=_plain(report)
	var written: bool = _flush_report()
	print("NORMAL_CANAL_RESULT "+JSON.stringify({"complete":complete,"requested_stage_stopped":stage_stopped,"written":written,"reason":reason,"phase":phase,"seconds":_elapsed(),"failures":failures,"engine_errors":logger.errors}))
	native_exit_requested=true
	_native_exit_watchdog.call_deferred()
	session._quit()

