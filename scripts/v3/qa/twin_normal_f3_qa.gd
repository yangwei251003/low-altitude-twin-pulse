extends Node
const SourceBinding = preload("res://scripts/v3/qa/twin_source_binding.gd")
static var _source_binding: Dictionary = {}
## AUTHORING ONLY: same natural I3 record58 -> F3 normal66. Unbound before I/O.
## No actor/Director/environment/HP/clock fixtures or manual simulation.
const Pilot = preload("res://scripts/v3/qa/twin_normal_flight_pilot.gd")
const Store = preload("res://scripts/v3/core/twin_world_store.gd")
const Director = preload("res://scripts/v3/gameplay/actions/twin_action_director.gd")
const Catalog = preload("res://scripts/v3/campaign/twin_campaign_catalog.gd")
const I2Results = preload("res://scripts/v3/gameplay/twin_i2_result_ledger.gd")
const AbilityRules = preload("res://scripts/v3/gameplay/twin_ability_rules.gd")
const Proofs = preload("res://scripts/v3/campaign/twin_campaign_runtime_proofs.gd")
static var SOURCE_PROFILE := "qa_normal_campaign_20261021_012725_b90f8a6f"
static var SOURCE_REPORT := "artifacts/v3/normal-i3-boss-20261021_060248_5956f59a/normal-i3-boss-20261021_060248_5956f59a.json"
static var SOURCE_REPORT_SHA256 := "814107acafcd07ce20b192a2c18435b0491a0bb95c9594232bd126106a85f740"
static var FIFTYEIGHT_DIGEST := "27512fd154e327bf1229a8b44da11517db2fa4038fc0716c48b3043e6bb2f7ba"
const SOURCE_GOALS := ["I1:rescue:brief","I1:rescue:channel","I1:rescue:contact","I1:rescue:evacuate","I1:evidence:trace","I1:evidence:engineer","I1:evidence:ledger","I1:evidence:echo","F1:needs:listen","F1:needs:nursery","F1:needs:route","F1:repair:plan","F1:repair:light","F1:repair:grow","F1:repair:confirm","I1:whale:brief","I1:whale:engage","I1:whale:disable","I1:whale:record","F1:crown:brief","F1:crown:engage","F1:crown:disable","F1:crown:restore","I1:underdeck:read","I1:underdeck:enter","I1:underdeck:release","I1:underdeck:traverse","I2:clinic_supply:diagnose","I2:clinic_supply:connect","I2:clinic_supply:stabilize","I2:clinic_supply:confirm","I2:distribution_audit:expose","I2:distribution_audit:trace","I2:distribution_audit:share_access","I2:canal_service:brief","I2:canal_service:exchange","I2:canal_service:service","I2:canal_service:order","I2:twin_pump_guardian:plan","I2:twin_pump_guardian:engage","I2:twin_pump_guardian:stop","I2:twin_pump_guardian:decision","F2:mirror_evidence:records","F2:mirror_evidence:archive","F2:mirror_evidence:light","F2:mirror_evidence:decision","F2:mirrorwing_warden:plan","F2:mirrorwing_warden:engage","F2:mirrorwing_warden:stop","F2:mirrorwing_warden:record","I3:cooling_route:brief","I3:cooling_route:ledger","I3:cooling_route:exchange","I3:cooling_route:dock","I3:furnace_crawler:plan","I3:furnace_crawler:engage","I3:furnace_crawler:stop","I3:furnace_crawler:record"]
const EXPECTED := ["I1:rescue:brief","I1:rescue:channel","I1:rescue:contact","I1:rescue:evacuate","I1:evidence:trace","I1:evidence:engineer","I1:evidence:ledger","I1:evidence:echo","F1:needs:listen","F1:needs:nursery","F1:needs:route","F1:repair:plan","F1:repair:light","F1:repair:grow","F1:repair:confirm","I1:whale:brief","I1:whale:engage","I1:whale:disable","I1:whale:record","F1:crown:brief","F1:crown:engage","F1:crown:disable","F1:crown:restore","I1:underdeck:read","I1:underdeck:enter","I1:underdeck:release","I1:underdeck:traverse","I2:clinic_supply:diagnose","I2:clinic_supply:connect","I2:clinic_supply:stabilize","I2:clinic_supply:confirm","I2:distribution_audit:expose","I2:distribution_audit:trace","I2:distribution_audit:share_access","I2:canal_service:brief","I2:canal_service:exchange","I2:canal_service:service","I2:canal_service:order","I2:twin_pump_guardian:plan","I2:twin_pump_guardian:engage","I2:twin_pump_guardian:stop","I2:twin_pump_guardian:decision","F2:mirror_evidence:records","F2:mirror_evidence:archive","F2:mirror_evidence:light","F2:mirror_evidence:decision","F2:mirrorwing_warden:plan","F2:mirrorwing_warden:engage","F2:mirrorwing_warden:stop","F2:mirrorwing_warden:record","I3:cooling_route:brief","I3:cooling_route:ledger","I3:cooling_route:exchange","I3:cooling_route:dock","I3:furnace_crawler:plan","I3:furnace_crawler:engage","I3:furnace_crawler:stop","I3:furnace_crawler:record","F3:separate_network:sample","F3:separate_network:listen","F3:separate_network:isolate","F3:separate_network:feed","F3:mycelial_choir:plan","F3:mycelial_choir:engage","F3:mycelial_choir:stop","F3:mycelial_choir:record"]
const PLAN := "F3:mycelial_choir:plan"
const ENGAGE := "F3:mycelial_choir:engage"
const STOP := "F3:mycelial_choir:stop"
const REWARD := "boss:F3:mycelial_choir"
const STAGES := ["sample","listen","isolate","feed","plan","engage","half","stop","complete"]
const SAMPLE := "F3:separate_network:sample"
const LISTEN := "F3:separate_network:listen"
const ISOLATE := "F3:separate_network:isolate"
const FEED := "F3:separate_network:feed"
const RECORD := "F3:mycelial_choir:record"
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
var patrol_side := 1.0
var last_patrol_target := Vector3.INF
var original_attempt := -1
var last_combat_key := ""
var combat_transitions: Array = []
var damage_samples: Array = []
var nutrient_samples: Array = []
var growth_observations: Array = []
var last_evasion_token := ""
var last_boss: Dictionary = {}
var phase_two_observed := false
var gui_actions: Array = []

static func _bound() -> bool:
	return not SOURCE_REPORT.is_empty() and SOURCE_REPORT_SHA256.length()==64 and FIFTYEIGHT_DIGEST.length()==64

static func preflight(args: PackedStringArray) -> Dictionary:
	_source_binding = {}
	var bound: Dictionary = SourceBinding.prepare(args,"normal-f3",SOURCE_GOALS,EXPECTED)
	if not bound.get("ok",false): return {"ok":false,"code":bound.get("code","source_binding_rejected"),"config":{}}
	_source_binding = bound.binding
	args = bound.args
	SOURCE_PROFILE = str(_source_binding.constants.get("SOURCE_PROFILE",SOURCE_PROFILE))
	SOURCE_REPORT = str(_source_binding.constants.get("SOURCE_REPORT",SOURCE_REPORT))
	SOURCE_REPORT_SHA256 = str(_source_binding.constants.get("SOURCE_REPORT_SHA256",SOURCE_REPORT_SHA256))
	FIFTYEIGHT_DIGEST = str(_source_binding.constants.get("FIFTYEIGHT_DIGEST",FIFTYEIGHT_DIGEST))
	if not _bound(): return {"ok":false,"code":"root_must_bind_actual_successful_I3Record58_report_and_receipts","config":{}}
	var values: Dictionary = {}
	for argument: String in args:
		var key := ""
		var value := ""
		if argument=="--qa-normal-f3":
			key="enabled"
			value="true"
		else:
			for pair: Array in [["--qa-profile=","profile"],["--qa-normal-output=","output"],["--qa-normal-seconds=","seconds"],["--qa-f3-stop-after=","stage"]]:
				if argument.begins_with(str(pair[0])):
					key=str(pair[1])
					value=argument.trim_prefix(str(pair[0]))
					break
		if key.is_empty() or value.is_empty() or values.has(key): return {"ok":false,"code":"unknown_empty_or_duplicate_f3_cli","config":{}}
		values[key]=value
	for key: String in ["enabled","profile","output","seconds"]:
		if not values.has(key): return {"ok":false,"code":"four_f3_arguments_required","config":{}}
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
	return {"ok":true,"code":"natural_I3Record58_prefix_verified","config":{"profile":SOURCE_PROFILE,"output":selected_output,"max_seconds":seconds.to_int(),"stop_after":stage,"source_profile_id":saved.profile_id,"source_lineage_id":saved.lineage_id,"source_receipts_sha256":FIFTYEIGHT_DIGEST}}

static func _source_check(saved: Dictionary) -> Dictionary:
	if not SourceBinding.same_identity(_source_binding,saved): return {"ok":false,"code":"source_binding_identity_changed"}
	if not _bound(): return {"ok":false,"code":"actual_I3_record58_source_not_bound"}
	var world: Variant=saved.get("world")
	if not world is Dictionary or world.get("region_id") not in ["I3","F3"] or world.get("branch_id")!="main": return {"ok":false,"code":"same_natural_I3_or_F3_main_branch_required"}
	var state: Variant=world.get("actions",{}).get("opening")
	if not state is Dictionary: return {"ok":false,"code":"source_story_schema"}
	var completed: Variant=state.get("completed")
	if not completed is Array or completed.size()<58 or completed.size()>66 or completed!=EXPECTED.slice(0,completed.size()) or world.get("completed_objectives")!=completed: return {"ok":false,"code":"only_exact_natural_58_to_66_prefix_accepted"}
	if not state.get("receipts") is Dictionary or state.receipts.size()!=completed.size() or _receipts_digest(state,SOURCE_GOALS)!=FIFTYEIGHT_DIGEST: return {"ok":false,"code":"actual_original_58_receipts_changed"}
	var director=Director.new()
	if not director.load_definitions(Director.DEFAULT_PATH,Catalog.extension_paths()).get("ok",false) or not director.validate_state(state).get("ok",false): return {"ok":false,"code":"original_Director_replay_rejected"}
	var discoveries: Variant=saved.get("personal",{}).get("discoveries")
	if not discoveries is Array: return {"ok":false,"code":"original_personal_discoveries_required"}
	var valid: Dictionary=I2Results.validate_world(world,discoveries)
	if not valid.get("ok",false): return {"ok":false,"code":"original_I2_physical_boundary:"+str(valid.get("error",""))}
	for flag: String in ["I3:cooling_ready","campaign_boss:I3","I3:region_route_open"]:
		if not world.get("flags",{}).get(flag,false): return {"ok":false,"code":"actual_original_I3_action_required:"+flag}
	for finding: String in ["boss:I3:furnace_crawler","I3:operation_record","I3:stoppable_route"]:
		if discoveries.count(finding)!=1: return {"ok":false,"code":"original_unique_source_finding:"+finding}
	if "I3:furnace_crawler" not in state.get("completed_actions",[]): return {"ok":false,"code":"original_I3_record_action_incomplete"}
	return {"ok":true,"code":"legal_natural_F3_prefix","source_receipts_sha256":FIFTYEIGHT_DIGEST,"completed":completed.duplicate()}

func run(owner_session: Node,options: Dictionary={}) -> Dictionary:
	if not _bound(): return {"ok":false,"code":"actual_I3Record58_source_not_bound"}
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
	return {"ok":true,"code":"observing_natural_f3","stop_after":stop_after}

func _execute() -> void:
	if not _check(session.profile_ready and not session.active and not OS.has_feature("editor"),"exported ordinary MAIN before existing-profile menu continuation"): _stop("exported_normal_menu_required"); return
	last_completed=initial.world.actions.opening.completed.duplicate()
	session._ui_action("solo",{"frame":0})
	await _next()
	if not _healthy() or not _check(_receipts_digest(session.story.state,SOURCE_GOALS)==initial_digest,"normal menu preserves original natural58 receipts",_status()): _stop("ordinary_source_resume_failed"); return
	if not await _dismiss_radio(): _stop("source_radio_not_closed"); return
	if session.region_id=="I3":
		if not _check(session._can_travel_to("F3"),"original complete I3 action permits normal F3 travel"): _stop("normal_F3_travel_locked"); return
		_press_key(KEY_M)
		await _next()
		if not _check(session.interface.travel.visible,"ordinary M opens the actual travel panel"): _stop("normal_travel_panel_missing"); return
		gui_actions.append({"kind":"normal_M_then_original_travel_menu_action","destination":"F3","seconds":_elapsed()})
		session._ui_action("travel_to",{"region_id":"F3"})
		var travel_deadline: float=minf(max_seconds-20.0,_elapsed()+40.0)
		while _live() and session.region_id!="F3" and _elapsed()<travel_deadline: await _next()
	if not _check(_live() and session.region_id=="F3" and session.campaign.supported() and session.campaign.mechanisms!=null,"original normal travel restores the actual F3 World",_status()): _stop("normal_F3_world_unavailable"); return
	if not await _dismiss_radio(): _stop("arrival_radio_not_closed"); return
	_bind_pilot()
	route=_route_definition()
	if not _check(not route.is_empty(),"candidate route derives from actual F3 markers and device bodies",route): _stop("F3_route_missing"); return
	if not _completed(SAMPLE):
		if not await _marker_flight("F3:root_sample",SAMPLE): _stop("normal_sample_G_unproven"); return
	if _stage("sample"): return
	if not _completed(LISTEN):
		if not await _marker_flight("npc:lingyin",LISTEN): _stop("normal_NPC_talk_unproven"); return
	if _stage("listen"): return
	if not _completed(ISOLATE):
		# Current goal61 requires real bridge support before it can complete.
		# This compensates no rule: the authored hint omission stays documented.
		if not await _prepare_signal(): _stop("real_light_growth_G_echo_isolation_unproven"); return
	if _stage("isolate"): return
	if not _completed(STOP):
		# Echo has only five seconds. Use the ORIGINAL G latch before waiting
		# for a named NPC or entering the whole real Boss battle.
		if not await _ensure_latched(): _stop("real_persistent_G_latch_unproven"); return
	if not _completed(FEED):
		if not await _wait_nutrient(): _stop("native_named_nutrient_delivery_unproven"); return
	if _stage("feed"): return
	if not _completed(STOP):
		if not _completed(PLAN):
			if not await _marker_flight("F3:boss_briefing",PLAN): _stop("normal_safe_briefing_unproven"); return
			if not _check(not session.campaign.active(),"normal briefing remains outside actual entry"): _stop("unsafe_briefing"); return
		if _stage("plan"): return
		if not await _dismiss_radio(): _stop("plan_radio_not_closed"); return
		# Also fly this corridor after a legitimate partial-Boss save: no
		# inherited report endpoint becomes the new aircraft spawn.
		if _body().global_position.z>route.entry_z_actual:
			if not await _navigate([Vector3(_body().global_position.x,route.altitude,_body().global_position.z),Vector3(0,route.altitude,-17),Vector3(0,route.altitude,route.entry_z_actual-1.0)],"continuous_actual_arena_approach"): _stop("normal_entry_flight_unproven"); return
		if not _check(session.campaign.active(),"normal flown entry starts/restores original F3 encounter",_status()): _stop("original_Boss_not_started"); return
		patrol_enabled=true
		var observed_deadline: float=minf(max_seconds-20.0,_elapsed()+20.0)
		while _healthy() and not _completed(ENGAGE) and _elapsed()<observed_deadline: await _next()
		if not _check(_completed(ENGAGE) and session.campaign.observed,"real complete warning/active/recovery cycle saves engage"): _stop("actual_full_cycle_unobserved"); return
		if _stage("engage"): return
		if not await _fight():
			if not stopping: _stop("actual_two_phase_battle_incomplete")
			return
		if stopping: return
	else:
		_event("inherited_committed_F3_victory",{"receipt":_receipt_for(STOP),"state":_boss_state()})
		for value: String in ["plan","engage","half"]:
			if _stage(value): return
	if _stage("stop"): return
	if not _completed(RECORD):
		if not await _marker_flight("F3:boss_record",RECORD): _stop("real_postcombat_record_G_unproven"); return
	if not _check(session.story.state.completed==EXPECTED and _receipts_digest(session.story.state,SOURCE_GOALS)==initial_digest,"eight real F3 goals extend unchanged original58 receipts",_status()): _stop("actual66_prefix_unproven"); return
	_stage("complete")

func _route_definition() -> Dictionary:
	var entry: float=float(session.campaign._entry_z)
	var briefing: Vector3=_v(session.story.markers.get("F3:boss_briefing",{}).get("position"))
	var altitude: float=minf(15.0,float(_body().max_altitude)-.5)
	if not is_finite(entry) or not briefing.is_finite() or briefing.z<=entry+.1 or altitude<12.5: return {}
	for id: String in ["F3:nutrient_bridge","F3:signal_hold","F3:signal_breaker"]:
		if not session.world.objects.has(id): return {}
	return {"altitude":altitude,"entry_z_actual":entry,"patrol_z":-17.0,"patrol_extent":19.0,"note":"Unflown candidate waypoints only; original full aircraft hull and Pilot sweeps stay mandatory. No pose assignment."}

func _marker_flight(target: String,objective: String) -> bool:
	if not await _dismiss_radio(): return false
	var marker: Vector3=_v(session.story.markers.get(target,{}).get("position"))
	if not marker.is_finite(): return _check(false,"actual marker exists: "+target)
	var near: Vector3=marker+Vector3(0,1.8,1.0)
	if not await _navigate([Vector3(_body().global_position.x,route.altitude,_body().global_position.z),Vector3(marker.x,route.altitude,marker.z+1.0),near],"original_marker:"+target): return false
	return await _contact(target,objective)

func _approach_device(id: String) -> bool:
	var at: Vector3=_target_position(id)
	if not at.is_finite(): return _check(false,"real device position exists",id)
	if not await _dismiss_radio(): return false
	return await _navigate([Vector3(_body().global_position.x,route.altitude,_body().global_position.z),Vector3(at.x,route.altitude,at.z),at+Vector3.UP*3.4],"actual_device:"+id)

func _cast(target: String,ability: String,keycode: Key) -> bool:
	if not await _dismiss_radio(): return false
	_press_key(keycode)
	if not _check(session.selected_ability==ability,"normal key selects "+ability): return false
	if not await _select_target(target): return false
	var cost: float=float(AbilityRules.DEFINITIONS[ability].energy)
	var deadline: float=minf(max_seconds-10.0,_elapsed()+10.0)
	while _healthy() and (float(session.cooldowns.get(1,0))>0 or float(session.entities[session._actor_id(1)].energy)<cost) and _elapsed()<deadline: await _next()
	if not _healthy(): return false
	var hit: Dictionary=_first_hit_from(_body().global_position,target)
	if not _check(hit.get("entity_id")==target,"actual first-hit LOS reaches "+target,hit): return false
	var before: int=int(session.stats.abilities)
	var state: Dictionary=session.entities[target].duplicate(true)
	_press_key(KEY_F)
	var accepted: bool=int(session.stats.abilities)==before+1
	var row: Dictionary={"target":target,"ability":ability,"accepted":accepted,"position":_body().global_position,"before":state,"after":session.entities[target].duplicate(true),"ray":hit,"seconds":_elapsed()}
	actual_abilities.append(_plain(row))
	await _next()
	return _check(accepted,"normal original ability action accepted: "+target+":"+ability,row)

func _operate(target: String) -> bool:
	if not await _dismiss_radio() or not await _select_target(target): return false
	var body: PhysicsBody3D=session.world.objects[target]
	var before: Transform3D=body.global_transform
	var generation: int=int(session.store.snapshot().generation)
	_record_g(target)
	await _next()
	if not _healthy(): return false
	var native: Transform3D=PhysicsServer3D.body_get_state(body.get_rid(),PhysicsServer3D.BODY_STATE_TRANSFORM)
	var expected: Transform3D=before
	if target=="F3:signal_breaker": expected.origin=Vector3(12,7,9) if before.origin.distance_to(Vector3(12,7,6))<=.4 else Vector3(12,7,6)
	else: expected.basis=Basis(Vector3.UP,0.0 if absf(wrapf(before.basis.get_euler().y,-PI,PI))>.4 else PI*.5)
	return _check(body.global_position.distance_to(expected.origin)<.002 and body.global_basis.is_equal_approx(expected.basis) and native.origin.distance_to(expected.origin)<.002 and native.basis.is_equal_approx(expected.basis) and int(session.store.snapshot().generation)>generation and session.campaign.last_operation_blockers.is_empty(),"original near/LOS G sweeps and saves actual native device: "+target,{"before":before,"expected":expected,"native":native,"blockers":session.campaign.last_operation_blockers})

func _prepare_signal() -> bool:
	if not await _approach_device("F3:nutrient_bridge"): return false
	var growth: float=float(session.entities["F3:nutrient_bridge"].get("growth",0.0))
	if growth<1.0:
		if not await _cast("F3:nutrient_bridge","light",KEY_4): return false
		for unused in 3:
			if float(session.entities["F3:nutrient_bridge"].get("growth",0.0))>=1.0: break
			if not await _cast("F3:nutrient_bridge","growth",KEY_7): return false
	growth_observations.append(_plain(_mechanisms_debug()))
	if not _check(float(session.entities["F3:nutrient_bridge"].growth)>=1.0,"three original growth steps reach the actual full3m span",_mechanisms_debug()): return false
	if not await _approach_device("F3:signal_breaker"): return false
	if session.world.objects["F3:signal_breaker"].global_position.distance_to(Vector3(12,7,9))>.4:
		if not await _operate("F3:signal_breaker"): return false
	# At the breaker the actual hold is within12m: original9 provides the
	# first isolate method, without any inserted timer or predicate endpoint.
	if not await _cast("F3:signal_hold","echo",KEY_9): return false
	return await _wait_goal(ISOLATE,6.0)

func _ensure_latched() -> bool:
	var hold: PhysicsBody3D=session.world.objects["F3:signal_hold"]
	if hold.global_basis.x.normalized().dot(Vector3.FORWARD)<=.95:
		if not await _approach_device("F3:signal_hold") or not await _operate("F3:signal_hold"): return false
	var native: Transform3D=PhysicsServer3D.body_get_state(hold.get_rid(),PhysicsServer3D.BODY_STATE_TRANSFORM)
	return _check(hold.global_basis.x.normalized().dot(Vector3.FORWARD)>.95 and native.basis.is_equal_approx(hold.global_basis),"original G latch persists beyond the temporary5s echo",_mechanisms_debug())

func _wait_goal(objective: String,seconds: float) -> bool:
	var deadline: float=minf(max_seconds-20.0,_elapsed()+seconds)
	while _healthy() and not _completed(objective) and _elapsed()<deadline: await _next()
	return _check(_completed(objective),"original Story/Store commits "+objective,{"receipt":_receipt_for(objective),"status":_status()})

func _wait_nutrient() -> bool:
	_phase("normal_original_named_NPC_pickup_route_delivery")
	var deadline: float=minf(max_seconds-70.0,_elapsed()+180.0)
	var next_sample: float=_elapsed()
	while _healthy() and not _completed(FEED) and _elapsed()<deadline:
		if _elapsed()>=next_sample:
			var state: Dictionary=session.ecology.simulation.snapshot()
			var row: Dictionary={"seconds":_elapsed(),"weather":session.ecology.weather_for("F3"),"actor":state.get("actors",{}).get(Proofs.NUTRIENT_ACTOR,{}),"native_ecology_tick":state.get("tick"),"native_event_serial":state.get("event_serial"),"proof":session.campaign.mechanisms.persistent_state().get("histories",{}).get(Proofs.NUTRIENT_PROOF,{})}
			nutrient_samples.append(_plain(row))
			_event("actual_named_NPC_progress",row)
			next_sample=_elapsed()+5.0
		await _next()
	var proof: Dictionary=session.campaign.mechanisms.persistent_state().get("histories",{}).get(Proofs.NUTRIENT_PROOF,{})
	var event: Dictionary=proof.get("event",{})
	return _check(_completed(FEED) and proof.get("branch_id")==session.world_cache.world.branch_id and proof.get("route")=="grown_path" and event.get("actor_id")==Proofs.NUTRIENT_ACTOR and event.get("target_id")==Proofs.NUTRIENT_RECEIVER and event.get("kind")=="transport_arrival" and int(event.get("amount",0))==1,"original real NPC take/send arrival and same-branch sealed proof complete62",{"proof":proof,"receipt":_receipt_for(FEED),"weather":session.ecology.weather_for("F3")})

func _fight() -> bool:
	_phase("normal_real_F3_three_parts_two_phases")
	patrol_enabled=true
	while _healthy() and _elapsed()<max_seconds-20.0:
		var state: Dictionary=_boss_state()
		if session.campaign.victory_committed():
			wanted_fire=false
			_set_fire(false)
			patrol_enabled=false
			if not await _wait_goal(STOP,6.0): return false
			return _check(state.get("completed",false) and phase_two_observed,"original two-phase damage and durable Store victory stop65",_status())
		if state.is_empty(): return _check(false,"actual F3 Encounter remains present",_status())
		if int(state.get("phase",0))==2:
			phase_two_observed=true
			if "half" not in reached_stages and _stage("half"): return false
		var env: Dictionary=session.campaign.mechanisms.boss_environment("F3")
		if not env.get("signal_isolated",false) or not env.get("nutrient_connected",false): return _check(false,"current original latch/breaker/full support keep F3 armor gate physical",env)
		var part: String=session.campaign.encounter.current_part()
		var target: String=session.world.campaign_arena.target_id(part)
		if target!=fire_target:
			wanted_fire=false
			_set_fire(false)
			if not await _select_target(target): return false
			fire_target=target
		wanted_fire=true
		await _next()
	return _check(false,"bounded continuous flight and original weapon finish F3",_status())

func _patrol() -> void:
	if not patrol_enabled or navigating or route.is_empty(): return
	var state: Dictionary=_boss_state()
	var token: String=str(state.get("attack",{}).get("token",""))
	if token!=last_evasion_token:
		last_evasion_token=token
		patrol_side=-1.0 if _body().global_position.x>=0.0 else 1.0
	if absf(_body().global_position.x)>=16.5 and _body().global_position.x*patrol_side>0.0: patrol_side=-patrol_side
	var target:=Vector3(patrol_side*float(route.patrol_extent),float(route.altitude),float(route.patrol_z))
	if target!=last_patrol_target:
		last_patrol_target=target
		command_serial+=1
		pilot.go_to(target,command_serial)

func _boss_state() -> Dictionary:
	return session.campaign.encounter.get_state() if _live() and session.region_id=="F3" and session.campaign.supported() else {}

func _mechanisms_debug() -> Dictionary:
	if not _live() or session.region_id!="F3" or session.campaign.mechanisms==null: return {}
	var state: Dictionary=session.ecology.simulation.snapshot()
	return {"mechanisms":session.campaign.mechanisms.persistent_state(),"view":session.campaign.mechanisms.view_state(),"environment":session.campaign.mechanisms.boss_environment("F3"),"encounter":_boss_state(),"observed":session.campaign.observed,"entry_z":session.campaign._entry_z,"npc":state.get("actors",{}).get(Proofs.NUTRIENT_ACTOR,{}),"weather":session.ecology.weather_for("F3"),"growth_blockers":session.world.campaign_growth_blockers,"last_operation_blockers":session.campaign.last_operation_blockers,"last_commit":session.last_commit_result}

func _select_target(target: String) -> bool:
	for _index: int in range(session.entities.size()+2):
		if str(session.locks.get(1,""))==target: return true
		_press_key(KEY_TAB)
		await _next()
		if not _healthy(): return false
	return _check(false,"normal Tab reaches actual target",{"wanted":target,"actual":session.locks.get(1,"")})

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
	var may_fire: bool=wanted_fire and open and fire_target==session.world.campaign_arena.target_id(part) and str(session.locks.get(1,""))==fire_target and _body().global_position.distance_to(_target_position(fire_target))<=36.0 and _first_hit_from(_body().global_position,fire_target).get("entity_id")==fire_target
	_set_fire(may_fire)

func _observe_combat() -> void:
	var state: Dictionary=_boss_state()
	if state.is_empty(): return
	var attempt: int=int(state.get("attempt",-1))
	if original_attempt<0: original_attempt=attempt
	if attempt!=original_attempt:
		_check(false,"normal candidate does not silently consume a full-wipe retry",{"original_attempt":original_attempt,"actual_attempt":attempt,"state":state})
		_stop("actual_attempt_reset")
		return
	phase_two_observed=phase_two_observed or int(state.get("phase",0))==2
	var key: String=JSON.stringify([state.get("attempt"),state.get("phase"),state.get("attack_stage"),state.get("attack",{}).get("pattern_id"),state.get("parts"),state.get("core_hp_milli"),_body().health])
	if key!=last_combat_key:
		last_combat_key=key
		var row: Dictionary={"seconds":_elapsed(),"state":state,"actual_position":_body().global_position,"native_velocity":_native_velocity(),"shots":session.stats.shots,"health":_body().health,"environment":session.campaign.mechanisms.boss_environment("F3")}
		combat_transitions.append(_plain(row))
		_event("actual_combat_transition",row)
	if not last_boss.is_empty():
		for id: String in ["west_voice","upper_voice","east_voice","core"]:
			var before: int=int(last_boss.get("core_hp_milli",0)) if id=="core" else int(last_boss.get("parts",{}).get(id,0))
			var after: int=int(state.get("core_hp_milli",0)) if id=="core" else int(state.get("parts",{}).get(id,0))
			if after<before: damage_samples.append(_plain({"seconds":_elapsed(),"part":id,"before":before,"after":after,"phase":state.phase,"actual_shots":session.stats.shots,"position":_body().global_position}))
	last_boss=state.duplicate(true)

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
	return path.is_absolute_path() and "://" not in path and ".." not in path and "\n" not in path and "\r" not in path and path.get_file().begins_with("normal-f3-") and path.get_extension() == "json" and not FileAccess.file_exists(path) and not DirAccess.dir_exists_absolute(path)

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
	report_cache["f3_segment_complete"]=false
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
	print("NORMAL_F3_EXIT_WATCHDOG_FAIL "+JSON.stringify(report_cache.native_exit))
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
			report_cache["f3_segment_complete"]=false
			report_cache["requested_stage_stopped"]=false
			report_cache["failures"].append("Original final-exit audio drain did not become ready.")
	report_cache["engine_errors"]=_plain(logger.errors)
	if not logger.errors.is_empty():
		report_cache["complete"]=false
		report_cache["f3_segment_complete"]=false
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
	print("NORMAL_F3_EVENT "+JSON.stringify(row))

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
		print("NORMAL_F3_PROGRESS "+JSON.stringify(_plain(row)))

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
		result["F3_mechanisms"]=_mechanisms_debug()
		result["pilot"]=pilot.report() if pilot!=null else {}
	return result

func _stage(value: String) -> bool:
	if value not in reached_stages: reached_stages.append(value)
	_event("actual_stage_observed",{"stage":value,"state":_mechanisms_debug(),"status":_status()})
	if stop_after==value:
		_stop("normal_f3_complete" if value=="complete" else "requested_stage_pause")
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
	preservation["original_I2_physical_boundary_validated"]=valid.get("ok",false)
	if not preserved: _check(false,"fresh original reader retains a legal same-source prefix",final_reader)
	if not saved_now: _check(false,"ordinary SaveGate succeeds before bounded QA stop",preservation)
	if saved_now and not matches_live: _check(false,"fresh original reader exactly matches actual live Story",final_reader)
	var complete: bool = reason=="normal_f3_complete" and failures.is_empty() and logger.errors.is_empty() and preserved and saved_now and matches_live and saved.world.actions.opening.completed==EXPECTED
	var stage_stopped: bool = reason=="requested_stage_pause" and stop_after in reached_stages and failures.is_empty() and logger.errors.is_empty() and preserved and saved_now and matches_live and preservation.common_paused
	if complete:
		for reward: String in [REWARD,"F3:operation_record","F3:living_isolation"]:
			_check(saved.personal.discoveries.count(reward)==1,"original F3 reward/delivery/record remains unique and durable: "+reward,saved.personal.discoveries)
		var proof: Dictionary=saved.world.environment.get("campaign_F3",{}).get("mechanisms",{}).get("histories",{}).get(Proofs.NUTRIENT_PROOF,{})
		_check(proof.get("event",{}).get("actor_id")==Proofs.NUTRIENT_ACTOR and proof.get("event",{}).get("target_id")==Proofs.NUTRIENT_RECEIVER and proof.get("branch_id")==saved.world.branch_id,"fresh original Store retains the actual same-branch NPC arrival proof",proof)
		complete=failures.is_empty()
	_write_report(reason,complete,stage_stopped)

func _write_report(reason: String,complete: bool,stage_stopped: bool) -> void:
	finished=true
	running=false
	var report: Dictionary={"complete":complete,"f3_segment_complete":complete,"requested_stage_stopped":stage_stopped,"requested_stage":stop_after,"reached_stages":reached_stages,"stop_reason":reason,"phase":phase,"seconds":_elapsed(),"max_seconds":max_seconds,"profile":SOURCE_PROFILE,"user_dir":OS.get_user_data_dir(),"executable":OS.get_executable_path(),"exported_application":not OS.has_feature("editor"),"runtime_cwd":DirAccess.open(".").get_current_dir(),"source_generation":initial.get("generation"),"initial_completed":initial.world.actions.opening.completed.duplicate(),"initial_goal_count":initial.world.actions.opening.completed.size(),"inherited_new_goal_count":initial.world.actions.opening.completed.size()-58,"source_report":SOURCE_REPORT,"source_report_sha256":SOURCE_REPORT_SHA256,"source_receipts_sha256":initial_digest,"physics_frames":physics_frames,"actual_distance_m":actual_distance,"max_frame_distance_m_excluding_normal_travel":max_frame_distance,"checks":checks,"failures":failures,"engine_errors":logger.errors,"events":events,"ten_second_samples":samples,"route":route,"actual_abilities":actual_abilities,"actual_interactions":actual_interactions,"actual_GUI_actions":gui_actions,"growth_observations":growth_observations,"actual_nutrient_samples":nutrient_samples,"combat_transitions":combat_transitions,"actual_damage_samples":damage_samples,"phase_two_observed":phase_two_observed,"attempt":original_attempt,"status":_status(),"preservation":preservation,"fresh_reader":final_reader,"story_receipts":session.story.state.get("receipts",{}),"stats":session.stats,"pilot":pilot.report() if pilot!=null and is_instance_valid(pilot.body) else {},"scope":"AUTHORING unbound natural58-to66 exported ordinary MAIN. Original same-profile menu/M travel, continuous real Pilot/full hull/sweeps, actual near/LOS G sample/NPC/device/record, original4 light and three7 growth, original9 echo then persistent G latch, actual named Ecology take/route/transport arrival and first same-branch proof, normal held flight_fire/Host part/LOS/weapon/two-phase encounter and Store victory. Original SaveGate/fresh reader/Session native audio quit. No actor pose, Director/environment/arrival/HP/time fixture, direct load/start, manual simulation, profile clone/reset/rollback or report-progress import. Unflown route/real battle pending; not whole-game/fun/graphics/LAN/controller/performance acceptance."}
	report.merge(SourceBinding.audit(_source_binding))
	report["native_exit"]={"requested":true,"through":"session._quit","observed_scene_exit":false,"watchdog_failed":false}
	report_cache=_plain(report)
	var written: bool=_flush_report()
	print("NORMAL_F3_RESULT "+JSON.stringify({"complete":complete,"requested_stage_stopped":stage_stopped,"written":written,"reason":reason,"phase":phase,"seconds":_elapsed(),"failures":failures,"engine_errors":logger.errors}))
	native_exit_requested=true
	_native_exit_watchdog.call_deferred()
	session._quit()
