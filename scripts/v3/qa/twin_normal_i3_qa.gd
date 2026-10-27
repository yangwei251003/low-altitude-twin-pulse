extends Node
const SourceBinding = preload("res://scripts/v3/qa/twin_source_binding.gd")
static var _source_binding: Dictionary = {}
## AUTHORING ONLY. Ordinary same-natural-profile 50->54 tasks / 54->58 Boss.
## Empty independent bindings refuse before Store/output I/O. No progress fixture.
const FlightPilot = preload("res://scripts/v3/qa/twin_normal_flight_pilot.gd")
const Pilot = preload("res://scripts/v3/gameplay/canal/canal_transport_physics/transport_pilot.gd")
const Store = preload("res://scripts/v3/core/twin_world_store.gd")
const Director = preload("res://scripts/v3/gameplay/actions/twin_action_director.gd")
const Catalog = preload("res://scripts/v3/campaign/twin_campaign_catalog.gd")
const I2Results = preload("res://scripts/v3/gameplay/twin_i2_result_ledger.gd")
const Cargo = preload("res://scripts/v3/gameplay/twin_thermal_cargo_session.gd")
const Encounter = preload("res://scripts/v3/campaign/twin_campaign_encounter.gd")
const AbilityRules = preload("res://scripts/v3/gameplay/twin_ability_rules.gd")
static var SOURCE_PROFILE := "qa_normal_campaign_20261021_012725_b90f8a6f"
static var SOURCE_REPORT := "artifacts/v3/normal-f2-boss-20261021_054010_cb585820/normal-f2-boss-20261021_054010_cb585820.json"
static var SOURCE_REPORT_SHA256 := "54103bb3ca1c1d5ba4d31dd4c936a80ceb352a9e047bd372df52f04092311942"
static var FIFTY_DIGEST := "419b5811badc7edfdaee5e8ec89d84478ebfca9739c5b512ece7d4947e9cb324"
static var SOURCE54_REPORT := "artifacts/v3/normal-i3-tasks-20261021_060005_46de93c6/normal-i3-tasks-20261021_060005_46de93c6.json"
static var SOURCE54_REPORT_SHA256 := "073957917797b59c7e5c913b197d0ca9447a456b53a610c0f83d714c7178e72c"
static var FIFTYFOUR_DIGEST := "b9aad745e539152b7b5ecd3978c11d23b3f0011947e9f9da4fe421b81000ff2a"
const SOURCE_GOALS := ["I1:rescue:brief","I1:rescue:channel","I1:rescue:contact","I1:rescue:evacuate","I1:evidence:trace","I1:evidence:engineer","I1:evidence:ledger","I1:evidence:echo","F1:needs:listen","F1:needs:nursery","F1:needs:route","F1:repair:plan","F1:repair:light","F1:repair:grow","F1:repair:confirm","I1:whale:brief","I1:whale:engage","I1:whale:disable","I1:whale:record","F1:crown:brief","F1:crown:engage","F1:crown:disable","F1:crown:restore","I1:underdeck:read","I1:underdeck:enter","I1:underdeck:release","I1:underdeck:traverse","I2:clinic_supply:diagnose","I2:clinic_supply:connect","I2:clinic_supply:stabilize","I2:clinic_supply:confirm","I2:distribution_audit:expose","I2:distribution_audit:trace","I2:distribution_audit:share_access","I2:canal_service:brief","I2:canal_service:exchange","I2:canal_service:service","I2:canal_service:order","I2:twin_pump_guardian:plan","I2:twin_pump_guardian:engage","I2:twin_pump_guardian:stop","I2:twin_pump_guardian:decision","F2:mirror_evidence:records","F2:mirror_evidence:archive","F2:mirror_evidence:light","F2:mirror_evidence:decision","F2:mirrorwing_warden:plan","F2:mirrorwing_warden:engage","F2:mirrorwing_warden:stop","F2:mirrorwing_warden:record"]
const EXPECTED := ["I1:rescue:brief","I1:rescue:channel","I1:rescue:contact","I1:rescue:evacuate","I1:evidence:trace","I1:evidence:engineer","I1:evidence:ledger","I1:evidence:echo","F1:needs:listen","F1:needs:nursery","F1:needs:route","F1:repair:plan","F1:repair:light","F1:repair:grow","F1:repair:confirm","I1:whale:brief","I1:whale:engage","I1:whale:disable","I1:whale:record","F1:crown:brief","F1:crown:engage","F1:crown:disable","F1:crown:restore","I1:underdeck:read","I1:underdeck:enter","I1:underdeck:release","I1:underdeck:traverse","I2:clinic_supply:diagnose","I2:clinic_supply:connect","I2:clinic_supply:stabilize","I2:clinic_supply:confirm","I2:distribution_audit:expose","I2:distribution_audit:trace","I2:distribution_audit:share_access","I2:canal_service:brief","I2:canal_service:exchange","I2:canal_service:service","I2:canal_service:order","I2:twin_pump_guardian:plan","I2:twin_pump_guardian:engage","I2:twin_pump_guardian:stop","I2:twin_pump_guardian:decision","F2:mirror_evidence:records","F2:mirror_evidence:archive","F2:mirror_evidence:light","F2:mirror_evidence:decision","F2:mirrorwing_warden:plan","F2:mirrorwing_warden:engage","F2:mirrorwing_warden:stop","F2:mirrorwing_warden:record","I3:cooling_route:brief","I3:cooling_route:ledger","I3:cooling_route:exchange","I3:cooling_route:dock","I3:furnace_crawler:plan","I3:furnace_crawler:engage","I3:furnace_crawler:stop","I3:furnace_crawler:record"]
const BRIEF := "I3:cooling_route:brief"
const LEDGER := "I3:cooling_route:ledger"
const EXCHANGE := "I3:cooling_route:exchange"
const DOCK := "I3:cooling_route:dock"
const PLAN := "I3:furnace_crawler:plan"
const ENGAGE := "I3:furnace_crawler:engage"
const STOP := "I3:furnace_crawler:stop"
const RECORD := "I3:furnace_crawler:record"
const REWARD := "boss:I3:furnace_crawler"
const RAD := "I3:boss_radiator"
const MASK := 1|2|4|8|32
const TASK_STAGES := ["brief","ledger","exchange","dock","complete"]
const BOSS_STAGES := ["plan","engage","half","stop","complete"]

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
var segment := "tasks"
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
var assist_owns_command := false
var patrol_enabled := false
var patrol_side := 1.0
var last_patrol_target := Vector3.INF
var original_attempt := -1
var last_combat_key := ""
var combat_transitions: Array = []
var damage_samples: Array = []
var last_boss: Dictionary = {}
var phase_two_observed := false
var cargo_observations: Array = []
var thermal_observations: Array = []
var battle_baseline: Dictionary = {}
var last_observed_shots := 0
var last_part_key := ""
var part_visits: Array = []
var dodge_token := ""

static func _binding(which: String) -> Dictionary:
	if which=="tasks": return {"path":SOURCE_REPORT,"sha":SOURCE_REPORT_SHA256,"digest":FIFTY_DIGEST,"count":50,"end":54,"stages":TASK_STAGES}
	if which=="boss": return {"path":SOURCE54_REPORT,"sha":SOURCE54_REPORT_SHA256,"digest":FIFTYFOUR_DIGEST,"count":54,"end":58,"stages":BOSS_STAGES}
	return {}

static func _bound(which: String) -> bool:
	var b: Dictionary=_binding(which)
	return not SOURCE_REPORT.is_empty() and SOURCE_REPORT_SHA256.length()==64 and FIFTY_DIGEST.length()==64 and not b.is_empty() and not str(b.path).is_empty() and str(b.sha).length()==64 and str(b.digest).length()==64

static func preflight(args: PackedStringArray) -> Dictionary:
	_source_binding = {}
	var bound: Dictionary = SourceBinding.prepare(args,"normal-i3",SOURCE_GOALS,EXPECTED)
	if not bound.get("ok",false): return {"ok":false,"code":bound.get("code","source_binding_rejected"),"config":{}}
	_source_binding = bound.binding
	args = bound.args
	SOURCE_PROFILE = str(_source_binding.constants.get("SOURCE_PROFILE",SOURCE_PROFILE))
	SOURCE_REPORT = str(_source_binding.constants.get("SOURCE_REPORT",SOURCE_REPORT))
	SOURCE_REPORT_SHA256 = str(_source_binding.constants.get("SOURCE_REPORT_SHA256",SOURCE_REPORT_SHA256))
	FIFTY_DIGEST = str(_source_binding.constants.get("FIFTY_DIGEST",FIFTY_DIGEST))
	SOURCE54_REPORT = str(_source_binding.constants.get("SOURCE54_REPORT",SOURCE54_REPORT))
	SOURCE54_REPORT_SHA256 = str(_source_binding.constants.get("SOURCE54_REPORT_SHA256",SOURCE54_REPORT_SHA256))
	FIFTYFOUR_DIGEST = str(_source_binding.constants.get("FIFTYFOUR_DIGEST",FIFTYFOUR_DIGEST))
	# Parse text only; no Store/file/output lookup before the selected source binds.
	var values: Dictionary={}
	for argument: String in args:
		var key := ""
		var value := ""
		if argument=="--qa-normal-i3": key="enabled"; value="true"
		else:
			for pair: Array in [["--qa-profile=","profile"],["--qa-normal-output=","output"],["--qa-normal-seconds=","seconds"],["--qa-i3-segment=","segment"],["--qa-i3-stop-after=","stage"]]:
				if argument.begins_with(str(pair[0])):
					key=str(pair[1]); value=argument.trim_prefix(str(pair[0])); break
		if key.is_empty() or value.is_empty() or values.has(key): return {"ok":false,"code":"unknown_empty_duplicate_i3_cli","config":{}}
		values[key]=value
	var which: String=str(values.get("segment","tasks"))
	if not _bound(which): return {"ok":false,"code":"Root_must_bind_actual_50_or_independent_54_report_SHA_and_receipts","config":{}}
	for key: String in ["enabled","profile","output","seconds","segment"]:
		if not values.has(key): return {"ok":false,"code":"five_i3_arguments_required","config":{}}
	var b: Dictionary=_binding(which)
	var seconds: String=str(values.seconds)
	var stage: String=str(values.get("stage","complete"))
	var path: String=str(values.output).replace("\\","/")
	if values.size()<5 or values.size()>6 or values.profile!=SOURCE_PROFILE or stage not in b.stages or not seconds.is_valid_int() or str(seconds.to_int())!=seconds or seconds.to_int()<60 or seconds.to_int()>600: return {"ok":false,"code":"same_profile_legal_stage_60_to_600_seconds_required","config":{}}
	if not _output_valid(path): return {"ok":false,"code":"new_absolute_scoped_output_required","config":{}}
	if not DirAccess.dir_exists_absolute("user://profiles_v3/"+SOURCE_PROFILE): return {"ok":false,"code":"original_profile_required_no_replacement","config":{}}
	var reader=Store.new("user://profiles_v3/"+SOURCE_PROFILE)
	var loaded: Dictionary=reader.load_profile()
	if not loaded.get("ok",false) or loaded.get("recovered",false): return {"ok":false,"code":"unrecovered_original_profile_required","config":{}}
	var saved: Dictionary=reader.snapshot()
	if not SourceBinding.start_matches(_source_binding,saved): return {"ok":false,"code":"source_binding_initial_snapshot_changed","config":{}}
	var checked: Dictionary=_source_check(saved,which)
	if not checked.ok: return {"ok":false,"code":checked.code,"config":{}}
	return {"ok":true,"code":"natural_I3_source_verified","config":{"profile":SOURCE_PROFILE,"output":path,"segment":which,"stop_after":stage,"max_seconds":seconds.to_int(),"source_profile_id":saved.profile_id,"source_lineage_id":saved.lineage_id,"source_receipts_sha256":b.digest}}

static func _source_check(saved: Dictionary, which: String) -> Dictionary:
	if not SourceBinding.same_identity(_source_binding,saved): return {"ok":false,"code":"source_binding_identity_changed"}
	if not _bound(which): return {"ok":false,"code":"actual_source_not_bound"}
	var b: Dictionary=_binding(which)
	var world: Variant=saved.get("world")
	if not world is Dictionary or world.get("branch_id")!="main" or world.get("region_id") not in (["F2","I3"] if which=="tasks" else ["I3"]): return {"ok":false,"code":"same_natural_branch_region_required"}
	if not world.get("actions") is Dictionary or not world.actions.get("opening") is Dictionary: return {"ok":false,"code":"source_story_missing"}
	var state: Dictionary=world.actions.opening
	var completed: Variant=state.get("completed")
	if not completed is Array or completed.size()<int(b.count) or completed.size()>int(b.end) or completed!=EXPECTED.slice(0,completed.size()) or world.get("completed_objectives")!=completed: return {"ok":false,"code":"only_exact_natural_selected_prefix"}
	if not state.get("receipts") is Dictionary or state.receipts.size()!=completed.size() or _receipts_digest(state,SOURCE_GOALS)!=FIFTY_DIGEST or _receipts_digest(state,EXPECTED.slice(0,int(b.count)))!=b.digest: return {"ok":false,"code":"original_source_receipts_changed"}
	var director=Director.new()
	var defs: Dictionary=director.load_definitions(Director.DEFAULT_PATH,Catalog.extension_paths())
	if not defs.get("ok",false) or not director.validate_state(state).get("ok",false): return {"ok":false,"code":"original_Director_replay_rejected"}
	var discoveries: Variant=saved.get("personal",{}).get("discoveries")
	if not discoveries is Array: return {"ok":false,"code":"original_discoveries_required"}
	var ledger: Dictionary=I2Results.validate_world(world,discoveries)
	if not ledger.get("ok",false): return {"ok":false,"code":"original_I2_results:"+str(ledger.get("error",""))}
	for key: String in ["I2:region_route_open","campaign_boss:I2","F2:region_route_open","campaign_boss:F2"]:
		if not world.get("flags",{}).get(key,false): return {"ok":false,"code":"prior_real_victory_record_required:"+key}
	for key: String in ["boss:I2:twin_pump_guardian","I2:operation_record","boss:F2:mirrorwing_warden","F2:operation_record"]:
		if discoveries.count(key)!=1: return {"ok":false,"code":"prior_unique_findings_required:"+key}
	if EXCHANGE in completed:
		var thermal: Dictionary=world.get("environment",{}).get("campaign_I3",{}).get("mechanisms",{}).get("thermal",{})
		if int(thermal.get("source_loss_j",0))<10000 or thermal.get("first_record",{}).is_empty() or int(thermal.get("source_loss_j",-1))!=int(thermal.get("sink_gain_j",-2))+int(thermal.get("dissipated_j",-2)): return {"ok":false,"code":"real_conserved_thermal_history_required"}
	if DOCK in completed:
		var cargo: Dictionary=world.get("environment",{}).get("I3_thermal_cargo",{})
		var proof: Dictionary=cargo.get("proof",{})
		var row: Dictionary=cargo.get("custody",{}).get("cargos",{}).get(Cargo.CARGO,{})
		if cargo.get("version")!=1 or proof.get("route") not in ["outer_corridor","updraft"] or row.get("phase")!="docked" or row.get("berth")!=Cargo.HIGH or int(proof.get("pickup_serial",0))<1 or int(proof.get("release_serial",0))<=int(proof.get("pickup_serial",0)) or proof.get("completed_serial")!=row.get("completed_serial"): return {"ok":false,"code":"original_unique_2kg_HIGH_custody_proof_required"}
	if ENGAGE in completed:
		var env: Dictionary=world.get("environment",{}).get("campaign_I3",{})
		var checker=Encounter.new()
		if not env.get("observed",false) or not checker.configure("furnace_crawler").get("ok",false) or not checker.validate_snapshot(env.get("encounter",{})).get("ok",false): return {"ok":false,"code":"original_encounter_cycle_snapshot_required"}
	if STOP in completed and (not world.get("flags",{}).get("campaign_boss:I3",false) or discoveries.count(REWARD)!=1 or not world.get("environment",{}).get("campaign_I3",{}).get("encounter",{}).get("state",{}).get("completed",false)): return {"ok":false,"code":"actual_committed_two_phase_victory_required"}
	if discoveries.count("I3:operation_record")!=(1 if RECORD in completed else 0) or world.get("flags",{}).get("I3:region_route_open",false)!=(RECORD in completed): return {"ok":false,"code":"original_record_result_mismatch"}
	return {"ok":true,"code":"legal_natural_I3_prefix","source_receipts_sha256":b.digest,"completed":completed.duplicate()}

func run(owner_session: Node, options: Dictionary={}) -> Dictionary:
	segment=str(options.get("segment","tasks"))
	if not _bound(segment): return {"ok":false,"code":"actual_source_not_bound"}
	if running or stopping or finished: return {"ok":false,"code":"already_started"}
	session=owner_session
	output=str(options.get("output","")).replace("\\","/")
	max_seconds=float(options.get("max_seconds",600))
	stop_after=str(options.get("stop_after","complete"))
	var b: Dictionary=_binding(segment)
	if not is_instance_valid(session) or not is_inside_tree() or options.get("profile")!=SOURCE_PROFILE or session.store.root_path!="user://profiles_v3/"+SOURCE_PROFILE or not _output_valid(output) or not is_finite(max_seconds) or max_seconds<60 or max_seconds>600 or stop_after not in b.stages: return {"ok":false,"code":"mounted_same_profile_legal_output_and_bound_required"}
	initial=session.store.snapshot()
	if not SourceBinding.start_matches(_source_binding,initial): return {"ok":false,"code":"source_binding_initial_snapshot_changed"}
	var verified: Dictionary=_source_check(initial,segment)
	if not verified.ok: return verified
	initial_digest=str(verified.source_receipts_sha256)
	if options.get("source_profile_id")!=initial.profile_id or options.get("source_lineage_id")!=initial.lineage_id or options.get("source_receipts_sha256")!=initial_digest: return {"ok":false,"code":"preflight_source_identity_changed"}
	if DirAccess.make_dir_recursive_absolute(output.get_base_dir())!=OK: return {"ok":false,"code":"output_directory_unavailable"}
	OS.add_logger(logger)
	started_usec=Time.get_ticks_usec()
	process_mode=Node.PROCESS_MODE_ALWAYS
	process_physics_priority=10
	running=true
	_execute.call_deferred()
	return {"ok":true,"code":"observing_natural_I3","segment":segment,"stage":stop_after}

func _execute() -> void:
	if not _check(session.profile_ready and not session.active and not OS.has_feature("editor"),"exported MAIN before ordinary same-profile menu continuation"): _stop("ordinary_exported_menu_required"); return
	last_completed=initial.world.actions.opening.completed.duplicate()
	session._ui_action("solo",{"frame":0})
	await _next()
	if not _healthy() or not await _dismiss_radio(): _stop("ordinary_source_resume_failed"); return
	if session.region_id=="F2":
		if not _check(session._can_travel_to("I3"),"original F2 record permits ordinary I3 travel"): _stop("I3_travel_locked"); return
		_press_key(KEY_M)
		await _next()
		if not _check(session.interface.travel.visible,"ordinary M opens travel panel"): _stop("travel_panel_missing"); return
		session._ui_action("travel_to",{"region_id":"I3"})
		var deadline: float=minf(max_seconds-15.0,_elapsed()+35.0)
		while _live() and session.region_id!="I3" and _elapsed()<deadline: await _next()
	if not _check(_live() and session.region_id=="I3" and session.campaign.supported() and session.thermal_cargo.supported(),"ordinary travel binds real I3 mechanisms and 2kg custody",_status()): _stop("I3_factory_unavailable"); return
	var ready_deadline: float=minf(max_seconds-15.0,_elapsed()+15.0)
	while _healthy() and not _cargo_status().get("ready",false) and _elapsed()<ready_deadline: await _next()
	if not _check(_cargo_status().get("ready",false),"actual native cargo support/restore is ready",_cargo_status()): _stop("native_cargo_not_ready"); return
	if not await _dismiss_radio(): _stop("arrival_radio_not_closed"); return
	_bind_pilot()
	route=_route_definition()
	if not _check(not route.is_empty(),"route derives current markers/devices/entry and berth support",route): _stop("I3_route_geometry_unavailable"); return
	if segment=="tasks": await _tasks()
	else: await _boss()

func _route_definition() -> Dictionary:
	for id: String in ["npc:qiaoshu","I3:cooling_ledger","I3:boss_briefing","I3:boss_record"]:
		if not session.story.markers.has(id): return {}
	for id: String in ["I3:cooling_valve","I3:hot_cassette","I3:cooling_sink",RAD,Cargo.CARGO,Cargo.LOW,Cargo.HIGH]:
		if not session.world.objects.has(id) or not session.entities.has(id): return {}
	var briefing: Vector3=session.story._point(session.story.markers["I3:boss_briefing"])
	var entry: float=float(session.campaign._entry_z)
	if not is_finite(entry) or briefing.z<=entry+.1 or float(_body().max_altitude)<16.2: return {}
	return {"npc":session.story._point(session.story.markers["npc:qiaoshu"])+Vector3.UP*1.6,"ledger":session.story._point(session.story.markers["I3:cooling_ledger"])+Vector3.UP*1.6,"valve":_target_position("I3:cooling_valve")+Vector3.UP*2.7,"briefing":briefing+Vector3(0,1.7,1.4),"record":session.story._point(session.story.markers["I3:boss_record"])+Vector3.UP*1.7,"entry_z_actual":entry,"altitude":14.0,"patrol_z":-17.0,"patrol_extent":16.0,"outer":Cargo.OUTER.duplicate(),"high_berth":session.world.objects[Cargo.HIGH].global_position,"note":"Candidate continuous flight goals, never pose fixtures; actual full loaded envelope/sweeps/LOS decide acceptance."}

func _tasks() -> void:
	if not _completed(BRIEF):
		if not await _navigate([Vector3(-24,7,31),Vector3(route.npc.x,7,route.npc.z),route.npc],"qiaoshu") or not await _contact("npc:qiaoshu",BRIEF): _stop("ordinary_NPC_brief_unproven"); return
	if _stage("brief"): return
	if not await _dismiss_radio(): _stop("brief_radio_pending"); return
	if not _completed(LEDGER):
		if not await _navigate([Vector3(_body().global_position.x,12,_body().global_position.z),Vector3(route.ledger.x,12,route.ledger.z),route.ledger],"cooling_ledger") or not await _contact("I3:cooling_ledger",LEDGER): _stop("ordinary_ledger_unproven"); return
	if _stage("ledger"): return
	if not _completed(EXCHANGE):
		if not await _exchange(): _stop("actual_thermal_exchange_unproven"); return
	else: _event("inherited_actual_thermal_receipt",{"receipt":_receipt_for(EXCHANGE),"history":_mechanisms_debug()})
	if _stage("exchange"): return
	if not _completed(DOCK):
		if not await _transport(): _stop("ordinary_2kg_transport_unproven"); return
	else: _event("inherited_actual_delivered_cargo",{"receipt":_receipt_for(DOCK),"status":_cargo_status()})
	if _stage("dock"): return
	if not _check(session.story.state.completed==EXPECTED.slice(0,54) and not session.campaign.active(),"four actual task goals; no premature Boss plan/start",_status()): _stop("I3_task_final_prefix_failed"); return
	_stage("complete")

func _exchange() -> bool:
	if not await _dismiss_radio(): return false
	if not await _navigate([Vector3(_body().global_position.x,16,_body().global_position.z),Vector3(route.valve.x,16,route.valve.z),route.valve],"thermal_valve"): return false
	if not await _select_target("I3:cooling_valve"): return false
	var before: Dictionary=_mechanisms_debug()
	if not session.campaign.mechanisms.view_state().get("thermal_connected",false):
		if not _check(_body().global_position.distance_to(_target_position("I3:cooling_valve"))<=4.5 and _first_hit_from(_body().global_position,"I3:cooling_valve").get("entity_id")=="I3:cooling_valve","actual valve range/LOS before original G"): return false
		_record_g("I3:cooling_valve")
		await _next()
	# G owns the native rotation; the original mechanism samples only at100ms.
	# Wait for that real sample instead of toggling the valve again or writing a view.
	var connection_deadline: float=minf(max_seconds-20.0,_elapsed()+1.0)
	while _healthy() and not session.campaign.mechanisms.view_state().get("thermal_connected",false) and session.campaign.last_operation_blockers.is_empty() and _elapsed()<connection_deadline: await _next()
	if not _check(session.campaign.last_operation_blockers.is_empty() and session.campaign.mechanisms.view_state().get("thermal_connected",false),"original swept G physically connects actual ±4m thermal ports",_mechanisms_debug()): return false
	# No initial 5/X source cooling: that would destroy the intended >=10kJ budget.
	var deadline: float=minf(max_seconds-20.0,_elapsed()+20.0)
	while _healthy() and not _completed(EXCHANGE) and _elapsed()<deadline: await _next()
	var history: Dictionary=session.campaign.mechanisms.persistent_state().thermal
	thermal_observations.append(_plain({"before":before,"after":_mechanisms_debug()}))
	return _check(_completed(EXCHANGE) and int(history.source_loss_j)>=10000 and int(history.source_loss_j)==int(history.sink_gain_j)+int(history.dissipated_j) and not history.first_record.is_empty() and float(session.entities["I3:hot_cassette"].temperature)<=35 and float(session.entities["I3:cooling_sink"].temperature)>20,"actual conserved source loss/sink gain produces original Story receipt",_mechanisms_debug())

func _cargo_status() -> Dictionary:
	return session.thermal_cargo.module.status() if _live() and session.thermal_cargo.supported() else {}

func _transport() -> bool:
	if not await _dismiss_radio(): return false
	var status: Dictionary=_cargo_status()
	var row: Dictionary=status.get("custody",{}).get("cargos",{}).get(Cargo.CARGO,{})
	if row.get("phase")=="docked" and row.get("berth")==Cargo.LOW:
		var at: Vector3=session.world.objects[Cargo.CARGO].global_position
		if not await _navigate([Vector3(_body().global_position.x,16,_body().global_position.z),Vector3(at.x,16,at.z),at+Vector3.UP*1.1],"low_pickup_alignment"): return false
		if not await _select_target(Cargo.CARGO): return false
		var settle_deadline: float=minf(max_seconds-20.0,_elapsed()+10.0)
		while _healthy() and (_body().linear_velocity.length()>.12 or _body().angular_velocity.length()>.1 or session.world.objects[Cargo.CARGO].linear_velocity.length()>.12 or session.world.objects[Cargo.CARGO].angular_velocity.length()>.1) and _elapsed()<settle_deadline: await _next()
		if not _check(_body().linear_velocity.length()<=.12 and _body().angular_velocity.length()<=.1,"actual hook is stable before original G pickup",_cargo_status()): return false
		assist_owns_command=true # Only original G module may command bounded alignment/lift.
		_record_g(Cargo.CARGO)
		if not await _wait_cargo_assist(35.0): return false
		assist_owns_command=false
		_bind_pilot()
	status=_cargo_status()
	row=status.get("custody",{}).get("cargos",{}).get(Cargo.CARGO,{})
	if row.get("phase")=="carried":
		if not _check(_body().cargo_items.has(Cargo.CARGO) and is_instance_valid(_body().cargo_items[Cargo.CARGO].joint) and session.world.objects[Cargo.CARGO].mass==2.0 and absf(float(_body().cargo_kg)-2.0)<.0001,"original real 2kg/PinJoint custody before continuous outer route",status): return false
		# A real load may still touch LOW after G relinquishes assistance. Ordinary
		# E takes off vertically before the conservative transport Pilot is used.
		if int(status.get("journey",{}).get("outer_progress",0))==0 and _body().global_position.y<6.5:
			assist_owns_command=true
			var lift_deadline: float=minf(max_seconds-20.0,_elapsed()+12.0)
			while _healthy() and _body().global_position.y<6.5 and _elapsed()<lift_deadline:
				Input.action_press("flight_high")
				await _next()
			Input.action_release("flight_high")
			assist_owns_command=false
			if not _check(_healthy() and _body().global_position.y>=6.5 and _body().cargo_items.has(Cargo.CARGO),"ordinary E lifts the attached real2kg load clear before route commands",_cargo_status()): return false
		var progress: int=int(status.get("journey",{}).get("outer_progress",0))
		for index: int in range(progress,Cargo.OUTER.size()):
			if not await _navigate([Cargo.OUTER[index]],"loaded_outer_"+str(index)): return false
			if not _check(int(_cargo_status().get("journey",{}).get("outer_progress",0))>=index+1 and not _cargo_status().get("journey",{}).get("broken",true),"ordinary native loaded route enters original ordered observation sphere",_cargo_status()): return false
		# Berth top + load half-height + original1.1m hook + .55m approach gap.
		var high: Vector3=session.world.objects[Cargo.HIGH].global_position
		var approach: Vector3=high+Vector3.UP*(.25+.2+1.1+.55)
		if not await _navigate([Vector3(high.x,14,5),Vector3(high.x,14,high.z),approach],"loaded_high_approach"): return false
		if not await _select_target(Cargo.HIGH): return false
		assist_owns_command=true
		_record_g(Cargo.HIGH)
		if not await _wait_cargo_assist(35.0): return false
		assist_owns_command=false
		_bind_pilot()
	var deadline: float=minf(max_seconds-20.0,_elapsed()+12.0)
	while _healthy() and not _completed(DOCK) and _elapsed()<deadline: await _next()
	status=_cargo_status()
	row=status.get("custody",{}).get("cargos",{}).get(Cargo.CARGO,{})
	cargo_observations.append(_plain({"seconds":_elapsed(),"status":status,"position":_body().global_position}))
	return _check(_completed(DOCK) and row.get("phase")=="docked" and row.get("berth")==Cargo.HIGH and status.get("proof",{}).get("route")=="outer_corridor" and not _body().cargo_items.has(Cargo.CARGO),"original release/native350ms HIGH support and outer-route proof commit real delivery",status)

func _wait_cargo_assist(seconds: float) -> bool:
	var deadline: float=minf(max_seconds-20.0,_elapsed()+seconds)
	# G may be queued to the next ordinary physics capture boundary.
	for _frame: int in range(3): await _next()
	while _healthy() and not str(_cargo_status().get("assist","")).is_empty() and _elapsed()<deadline: await _next()
	var status: Dictionary=_cargo_status()
	var row: Dictionary=status.get("custody",{}).get("cargos",{}).get(Cargo.CARGO,{})
	# status.error is the last capture/operation diagnostic, not a current fault:
	# auto-save legitimately refuses assistance/dropping and keeps that old text.
	# Confirm relinquished ownership/current custody here. The caller separately
	# requires actual pickup Joint+mass or actual HIGH350ms/proof/Story receipt;
	# a refused operation still fails those unchanged downstream outcome gates.
	return _check(_healthy() and str(status.get("assist","")).is_empty() and status.get("ready",false) and row.get("phase") in ["carried","dropping","docked"] and str(row.get("fault","")).is_empty(),"original assistance relinquishes command in nonfault native custody; actual outcome checked downstream",status)

func _boss() -> void:
	if not _completed(STOP):
		if not session.campaign.active():
			# Independent Boss radiator, not the completed cooling-route hot cassette.
			if not await _navigate([Vector3(_body().global_position.x,16,_body().global_position.z),Vector3(-5,16,-17),Vector3(-5,10,-17)],"separate_Boss_radiator_preparation"): _stop("radiator_approach_failed"); return
			for _cool: int in range(2):
				if float(session.entities[RAD].temperature)<=35.0: break
				if not await _cool_radiator(): _stop("actual_Boss_radiator_cooling_failed"); return
		if not _completed(PLAN):
			if not await _navigate([Vector3(0,10,-17),route.briefing],"safe_Boss_briefing") or not await _contact("I3:boss_briefing",PLAN): _stop("safe_Boss_briefing_failed"); return
		if _stage("plan"): return
		if not await _dismiss_radio(): _stop("Boss_brief_radio_pending"); return
		if not session.campaign.active():
			if not await _enter_arena(): _stop("Boss_entry_route_failed"); return
		if not _check(session.campaign.active(),"actual position/plan gate starts original Encounter",_status()): _stop("natural_Boss_start_missing"); return
		patrol_enabled=true
		var deadline: float=minf(max_seconds-20.0,_elapsed()+20.0)
		while _healthy() and not _completed(ENGAGE) and _elapsed()<deadline: await _next()
		if not _check(_completed(ENGAGE),"ordinary full warning/active/recovery gives original engage",_status()): _stop("full_Boss_cycle_unproven"); return
		if _stage("engage"): return
		if not await _fight(): _stop("ordinary_Boss_battle_incomplete"); return
	else:
		_event("inherited_original_Boss_victory",{"receipt":_receipt_for(STOP),"state":_boss_state(),"note":"Earlier completed stages are inherited receipts/snapshot; not re-enacted."})
		for inherited_stage: String in ["plan","engage","half"]:
			if _stage(inherited_stage): return
	if _stage("stop"): return
	wanted_fire=false
	_set_fire(false)
	patrol_enabled=false
	if not _completed(RECORD):
		if not await _dismiss_radio() or not await _navigate([Vector3(_body().global_position.x,14,_body().global_position.z),Vector3(route.record.x,14,route.record.z),route.record],"post_Boss_record") or not await _contact("I3:boss_record",RECORD): _stop("original_victory_record_failed"); return
	if not _check(session.story.state.completed==EXPECTED and _completed(RECORD),"actual eight I3 goals end at original record58",_status()): _stop("I3_Boss_final_prefix_failed"); return
	_stage("complete")

func _cool_radiator() -> bool:
	if not await _dismiss_radio(): return false
	_press_key(KEY_5)
	if not _check(session.selected_ability=="heat","5 selects original heat; 6 charge is not cooling") or not await _select_target(RAD): return false
	var deadline: float=minf(max_seconds-20.0,_elapsed()+20.0)
	while _healthy() and (float(session.cooldowns.get(1,0))>0 or float(session.entities[session._actor_id(1)].energy)<float(AbilityRules.DEFINITIONS.heat.energy) or _body().global_position.distance_to(_target_position(RAD))>11.75 or _first_hit_from(_body().global_position,RAD).get("entity_id")!=RAD) and _elapsed()<deadline: await _next()
	if not _check(_healthy() and float(session.cooldowns.get(1,0))<=0 and float(session.entities[session._actor_id(1)].energy)>=float(AbilityRules.DEFINITIONS.heat.energy) and _body().global_position.distance_to(_target_position(RAD))<=float(AbilityRules.DEFINITIONS.heat.range) and _first_hit_from(_body().global_position,RAD).get("entity_id")==RAD,"actual radiator energy/range/cooldown/first-hit LOS before X",_status()): return false
	var before: float=float(session.entities[RAD].temperature)
	var count: int=int(session.stats.abilities)
	_press_key(KEY_X)
	await _next()
	var after: float=float(session.entities[RAD].temperature)
	var accepted: bool=int(session.stats.abilities)==count+1 and after<before
	actual_abilities.append(_plain({"seconds":_elapsed(),"target":RAD,"ability":"heat","mode":"cool","before":before,"after":after,"accepted":accepted,"position":_body().global_position}))
	return _check(accepted,"original 5/Tab/X actually cools independent Boss radiator",_mechanisms_debug())

func _fight() -> bool:
	patrol_enabled=true
	var progress: float=_elapsed()
	var damage_count: int=damage_samples.size()
	while _healthy() and _elapsed()<max_seconds-20.0:
		var state: Dictionary=_boss_state()
		if session.campaign.victory_committed():
			wanted_fire=false; _set_fire(false); patrol_enabled=false
			var end: float=minf(max_seconds-15.0,_elapsed()+6.0)
			while _healthy() and not _completed(STOP) and _elapsed()<end: await _next()
			return _check(_completed(STOP) and state.get("completed",false) and phase_two_observed and _damage_evidence().get("ok",false),"actual weapon damage chain/two phases and original Store victory",_damage_evidence())
		if damage_samples.size()!=damage_count: damage_count=damage_samples.size(); progress=_elapsed()
		if _elapsed()-progress>40.0: return _check(false,"actual weapon/LOS/armour route makes HP progress within40s",_status())
		if int(state.get("phase",0))==2 and "half" not in reached_stages:
			phase_two_observed=true
			if _stage("half"): return false
		if float(session.entities[RAD].temperature)>35.0:
			wanted_fire=false; _set_fire(false)
			if not await _cool_radiator(): return false
		var part: String=session.campaign.encounter.current_part()
		var target: String=session.world.campaign_arena.target_id(part)
		if target!=fire_target:
			wanted_fire=false; _set_fire(false)
			if not await _select_target(target): return false
			fire_target=target
		wanted_fire=true
		await _next()
	return _check(false,"bounded ordinary I3 Boss battle finishes",_status())

func _enter_arena() -> bool:
	if not await _navigate([Vector3(0,14,-17)],"pre_entry_high_airlane"): return false
	navigating=true
	command_serial+=1
	var target:=Vector3(0,14,float(route.entry_z_actual)-4.0)
	if not _check(_hull_clear(target) and pilot.go_to(target,command_serial),"normal swept entry command accepted",target): return false
	var deadline: float=minf(max_seconds-20.0,_elapsed()+15.0)
	while _healthy() and not session.campaign.active() and _elapsed()<deadline: await _next()
	navigating=false
	last_patrol_target=Vector3.INF
	patrol_enabled=true
	return _check(session.campaign.active(),"continuous ordinary flight crosses actual entry without waiting to hover in warning",_status())

func _patrol() -> void:
	if not patrol_enabled or navigating or route.is_empty() or not session.campaign.active(): return
	var state: Dictionary=_boss_state()
	var attack: Dictionary=state.get("attack",{})
	var target: Vector3=last_patrol_target
	var warning: bool=state.get("attack_stage") in ["warning","active"]
	if warning and not attack.get("shapes",[]).is_empty():
		var token: String=str(attack.get("token",""))
		if token!=dodge_token:
			dodge_token=token
			var shape: Dictionary=attack.shapes[0]
			var locked_x: float=float(shape.centre_mm[0])/1000.0
			patrol_side=signf(_native_velocity().x) if absf(_native_velocity().x)>.35 else (1.0 if _body().global_position.x>=locked_x else -1.0)
			if absf(_body().global_position.x)>19.0: patrol_side=-signf(_body().global_position.x)
			var margin: float=float(shape.get("outer_mm",int(shape.get("width_mm",0))/2))/1000.0+2.0
			target=Vector3(clampf(locked_x+patrol_side*maxf(7.0,margin),-25,25),float(route.altitude),float(route.patrol_z))
			_event("actual_warning_changes_ordinary_flight_target",{"shape":shape,"token":token,"target":target,"velocity":_native_velocity(),"pilot":"Root normal_flight_pilot original full stopping sweeps"})
	else:
		if not target.is_finite() or absf(_body().global_position.x)>12.0: patrol_side=-1.0 if _body().global_position.x>0 else 1.0
		target=Vector3(patrol_side*16.0,float(route.altitude),float(route.patrol_z))
	if target!=last_patrol_target:
		if not _check(_hull_clear(target),"warning/patrol destination retains full actual hull clearance",target): _stop("patrol_goal_occupied"); return
		last_patrol_target=target
		command_serial+=1
		if not pilot.go_to(target,command_serial): _check(false,"ordinary patrol command accepted",target); _stop("patrol_command_rejected")

func _mechanisms_debug() -> Dictionary:
	if not _live() or session.region_id!="I3" or session.campaign.mechanisms==null: return {}
	return {"state":session.campaign.mechanisms.persistent_state(),"view":session.campaign.mechanisms.view_state(),"boss_environment":session.campaign.mechanisms.boss_environment("I3"),"cargo":_cargo_status(),"radiator":session.entities.get(RAD,{}).duplicate(true),"encounter":_boss_state(),"last_operation_blockers":session.campaign.last_operation_blockers,"last_commit":session.last_commit_result}

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
	return path.is_absolute_path() and "://" not in path and ".." not in path and "\n" not in path and "\r" not in path and path.get_file().begins_with("normal-i3-") and path.get_extension() == "json" and not FileAccess.file_exists(path) and not DirAccess.dir_exists_absolute(path)

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
	pilot = FlightPilot.new() # No-load commands only; helper delegates unchanged original Pilot when cargo_items is nonempty.
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
	report_cache["i3_segment_complete"]=false
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
	print("NORMAL_I3_EXIT_WATCHDOG_FAIL "+JSON.stringify(report_cache.native_exit))
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
			report_cache["i3_segment_complete"]=false
			report_cache["requested_stage_stopped"]=false
			report_cache["failures"].append("Original final-exit audio drain did not become ready.")
	report_cache["engine_errors"]=_plain(logger.errors)
	if not logger.errors.is_empty():
		report_cache["complete"]=false
		report_cache["i3_segment_complete"]=false
		report_cache["requested_stage_stopped"]=false
	_flush_report()

func _next() -> void:
	await get_tree().physics_frame
	await get_tree().process_frame
	if finished or not is_instance_valid(session): return
	var completed: Array = session.story.state.get("completed",[])
	if completed!=last_completed:
		var b: Dictionary=_binding(segment)
		if completed!=EXPECTED.slice(0,completed.size()) or completed.size()>int(b.end) or _receipts_digest(session.story.state,EXPECTED.slice(0,int(b.count)))!=initial_digest:
			_check(false,"every changed Story remains an exact same-source natural prefix",completed)
			_stop("natural_prefix_diverged")
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
	print("NORMAL_I3_EVENT "+JSON.stringify(row))

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
		print("NORMAL_I3_PROGRESS "+JSON.stringify(_plain(row)))

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
		_stop("normal_i3_complete" if value=="complete" else "requested_stage_pause")
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
	var valid: Dictionary = _source_check(saved,segment) if loaded.get("ok",false) else {"ok":false,"code":"fresh_reader_load_failed"}
	var preserved: bool = loaded.get("ok",false) and not loaded.get("recovered",false) and valid.get("ok",false) and valid.get("source_receipts_sha256")==initial_digest
	var saved_now: bool = not save_callbacks.is_empty() and save_callbacks[-1].get("ok",false) and save_callbacks[-1].get("completed",false)
	var matches_live: bool = preserved and session.store.matches_persisted_value(session.story.state,saved.world.actions.opening)
	final_reader={"loaded":loaded,"prefix_validation":valid,"generation":saved.get("generation"),"world":saved.get("world"),"personal":saved.get("personal"),"lineage_id":saved.get("lineage_id"),"profile_id":saved.get("profile_id")}
	preservation["original_prefix_preserved"]=preserved
	preservation["current_SaveGate_completed"]=saved_now
	preservation["fresh_Story_matches_live"]=matches_live
	preservation["original_factory_restore_ready"]=_cargo_status().get("ready",false)
	if not preserved: _check(false,"fresh original reader retains a legal same-source prefix",final_reader)
	if not saved_now: _check(false,"ordinary SaveGate succeeds before bounded QA stop",preservation)
	if saved_now and not matches_live: _check(false,"fresh original reader exactly matches actual live Story",final_reader)
	var complete: bool = reason=="normal_i3_complete" and failures.is_empty() and logger.errors.is_empty() and preserved and saved_now and matches_live and saved.world.actions.opening.completed==EXPECTED.slice(0,int(_binding(segment).end))
	var stage_stopped: bool = reason=="requested_stage_pause" and stop_after in reached_stages and failures.is_empty() and logger.errors.is_empty() and preserved and saved_now and matches_live and preservation.common_paused
	if complete:
		for reward: String in ([REWARD,"I3:operation_record"] if segment=="boss" else ["I3:cooling_overdraft","I3:stoppable_route"]):
			_check(saved.personal.discoveries.count(reward)==1,"original Boss reward/record is unique and durable: "+reward,saved.personal.discoveries)
		complete=failures.is_empty()
	_write_report(reason,complete,stage_stopped)

func _write_report(reason: String,complete: bool,stage_stopped: bool) -> void:
	finished=true
	running=false
	var report: Dictionary={"complete":complete,"i3_segment_complete":complete,"requested_stage_stopped":stage_stopped,"requested_stage":stop_after,"reached_stages":reached_stages,"stop_reason":reason,"phase":phase,"seconds":_elapsed(),"max_seconds":max_seconds,"profile":SOURCE_PROFILE,"user_dir":OS.get_user_data_dir(),"executable":OS.get_executable_path(),"exported_application":not OS.has_feature("editor"),"runtime_cwd":DirAccess.open(".").get_current_dir(),"source_generation":initial.get("generation"),"initial_goal_count":initial.world.actions.opening.completed.size(),"inherited_new_goal_count":initial.world.actions.opening.completed.size()-int(_binding(segment).count),"segment":segment,"source_profile_id":initial.profile_id,"source_lineage_id":initial.lineage_id,"source_report":_binding(segment).path,"source_report_sha256":_binding(segment).sha,"source_receipts_sha256":initial_digest,"physics_frames":physics_frames,"actual_distance_m":actual_distance,"max_frame_distance_m_excluding_normal_travel":max_frame_distance,"checks":checks,"failures":failures,"engine_errors":logger.errors,"events":events,"ten_second_samples":samples,"route":route,"actual_abilities":actual_abilities,"actual_interactions":actual_interactions,"combat_transitions":combat_transitions,"actual_damage_samples":damage_samples,"actual_thermal_observations":thermal_observations,"actual_cargo_observations":cargo_observations,"phase_two_observed":phase_two_observed,"attempt":original_attempt,"status":_status(),"preservation":preservation,"fresh_reader":final_reader,"story_receipts":session.story.state.get("receipts",{}),"stats":session.stats,"pilot":pilot.report() if pilot!=null and is_instance_valid(pilot.body) else {},"scope":"AUTHORING same-natural-QA-profile I3 tasks50-to54 or independent Boss54-to58. Original exported MAIN/menu/M travel; original Pilot loaded2kg cargo, near/LOS G and native alignment/DockLift/PinJoint/Custody, conserved thermal ports/heat, ordinary heat5/Tab/X on separate Boss radiator, Root QA unladen flight helper with original full stopping sweeps, held input fire with Host LOS/weapon/armour/two-phase gates, original Store/SaveGate/fresh reader and native audio exit. No Director/ActorPose/HP/environment/clock fixture, direct Boss start/load_region/manual simulation/profile clone/rollback. Unflown bounded route, not whole-game/human/controller/LAN/performance acceptance."}
	report.merge(SourceBinding.audit(_source_binding))
	report["native_exit"]={"requested":true,"through":"session._quit","observed_scene_exit":false,"watchdog_failed":false}
	report_cache=_plain(report)
	var written: bool=_flush_report()
	print("NORMAL_I3_RESULT "+JSON.stringify({"complete":complete,"requested_stage_stopped":stage_stopped,"written":written,"reason":reason,"phase":phase,"seconds":_elapsed(),"failures":failures,"engine_errors":logger.errors}))
	native_exit_requested=true
	_native_exit_watchdog.call_deferred()
	session._quit()

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
	if pilot!=null and not assist_owns_command:
		_patrol()
		pilot.tick(delta,true,false)
	var part: String=session.campaign.encounter.current_part() if session.campaign.supported() else ""
	var open: bool=session.campaign.active() and session.campaign.encounter.part_open(part)
	var may_fire: bool=wanted_fire and open and fire_target==session.world.campaign_arena.target_id(part) and str(session.locks.get(1,""))==fire_target and _body().global_position.distance_to(_target_position(fire_target))<=36.0 and _first_hit_from(_body().global_position,fire_target).get("entity_id")==fire_target
	_set_fire(may_fire)

func _boss_state() -> Dictionary:
	return session.campaign.encounter.get_state() if _live() and session.region_id=="I3" and session.campaign.supported() else {}

func _observe_combat() -> void:
	var state: Dictionary=_boss_state()
	if state.is_empty() or int(state.get("attempt",0))<1: return
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
		var row: Dictionary={"seconds":_elapsed(),"state":state,"actual_position":_body().global_position,"native_velocity":_native_velocity(),"shots":session.stats.shots,"health":_body().health,"environment":session.campaign.mechanisms.boss_environment("I3")}
		combat_transitions.append(_plain(row))
		_event("actual_combat_transition",row)
	if not last_boss.is_empty():
		for part: String in ["radiator_west","radiator_east","core"]:
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
		for part: String in ["radiator_west","radiator_east"]: expected["1:"+part]=int(battle_baseline.parts[part])
		expected["1:core"]=int(battle_baseline.core_hp_milli)-half
		for part: String in ["radiator_west","radiator_east"]: expected["2:"+part]=int(session.campaign.definition.part_hp_milli)
		expected["2:core"]=half
	else:
		for part: String in ["radiator_west","radiator_east"]: expected["2:"+part]=int(battle_baseline.parts[part])
		expected["2:core"]=int(battle_baseline.core_hp_milli)
	var valid: bool=baseline_phase in [1,2] and not damage_samples.is_empty()
	for key: String in expected:
		var amount: int=int(totals.get(key,0))
		# Exposure timeout legitimately rearms radiators. Core never heals: exact
		# observed drops include half clamp/final zero, never assume 9 per shot.
		valid=valid and (amount==int(expected[key]) if key.ends_with(":core") else amount>=int(expected[key]))
	var phase2_east_seen := false
	for row: Dictionary in part_visits:
		if int(row.phase)==2 and row.part=="radiator_east": phase2_east_seen=true
	if baseline_phase==1 or int(battle_baseline.parts.get("radiator_east",0))>0: valid=valid and phase2_east_seen
	return {"ok":valid,"totals":totals,"required_remaining_from_actual_baseline":expected,"phase2_reverse_east_seen":phase2_east_seen,"baseline_phase":baseline_phase,"note":"HP deltas follow observed before->after chains and actual shot counters. No fixed request-damage/count assertion; partial original snapshots retain earlier evidence."}
