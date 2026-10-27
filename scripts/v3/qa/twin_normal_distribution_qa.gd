extends Node
const SourceBinding = preload("res://scripts/v3/qa/twin_source_binding.gd")
static var _source_binding: Dictionary = {}
## Explicit exported MAIN observer. Bound to the actual dev78 natural Clinic31 COMPLETE report.
## Commands only: original Pilot, normal keys/G, original Rules/Consensus/Store.
const Pilot = preload("res://scripts/v3/gameplay/canal/canal_transport_physics/transport_pilot.gd")
const Store = preload("res://scripts/v3/core/twin_world_store.gd")
const Director = preload("res://scripts/v3/gameplay/actions/twin_action_director.gd")
const Catalog = preload("res://scripts/v3/campaign/twin_campaign_catalog.gd")
const ClinicProgress = preload("res://scripts/v3/gameplay/actions/twin_clinic_progress.gd")
const DistributionProgress = preload("res://scripts/v3/gameplay/actions/twin_distribution_progress.gd")
const Cabinet = preload("res://scripts/v3/world/twin_distribution_cabinet.gd")
const I2Results = preload("res://scripts/v3/gameplay/twin_i2_result_ledger.gd")
const AbilityRules = preload("res://scripts/v3/gameplay/twin_ability_rules.gd")
static var SOURCE_PROFILE := ""
static var SOURCE_REPORT_SHA256 := ""
static var THIRTYONE_DIGEST := ""
static var TWENTYSEVEN_DIGEST := ""
const BASE_TWENTYSEVEN := ["I1:rescue:brief","I1:rescue:channel","I1:rescue:contact","I1:rescue:evacuate","I1:evidence:trace","I1:evidence:engineer","I1:evidence:ledger","I1:evidence:echo","F1:needs:listen","F1:needs:nursery","F1:needs:route","F1:repair:plan","F1:repair:light","F1:repair:grow","F1:repair:confirm","I1:whale:brief","I1:whale:engage","I1:whale:disable","I1:whale:record","F1:crown:brief","F1:crown:engage","F1:crown:disable","F1:crown:restore","I1:underdeck:read","I1:underdeck:enter","I1:underdeck:release","I1:underdeck:traverse"]
const SOURCE_GOALS := ["I1:rescue:brief","I1:rescue:channel","I1:rescue:contact","I1:rescue:evacuate","I1:evidence:trace","I1:evidence:engineer","I1:evidence:ledger","I1:evidence:echo","F1:needs:listen","F1:needs:nursery","F1:needs:route","F1:repair:plan","F1:repair:light","F1:repair:grow","F1:repair:confirm","I1:whale:brief","I1:whale:engage","I1:whale:disable","I1:whale:record","F1:crown:brief","F1:crown:engage","F1:crown:disable","F1:crown:restore","I1:underdeck:read","I1:underdeck:enter","I1:underdeck:release","I1:underdeck:traverse","I2:clinic_supply:diagnose","I2:clinic_supply:connect","I2:clinic_supply:stabilize","I2:clinic_supply:confirm"]
const EXPECTED := ["I1:rescue:brief","I1:rescue:channel","I1:rescue:contact","I1:rescue:evacuate","I1:evidence:trace","I1:evidence:engineer","I1:evidence:ledger","I1:evidence:echo","F1:needs:listen","F1:needs:nursery","F1:needs:route","F1:repair:plan","F1:repair:light","F1:repair:grow","F1:repair:confirm","I1:whale:brief","I1:whale:engage","I1:whale:disable","I1:whale:record","F1:crown:brief","F1:crown:engage","F1:crown:disable","F1:crown:restore","I1:underdeck:read","I1:underdeck:enter","I1:underdeck:release","I1:underdeck:traverse","I2:clinic_supply:diagnose","I2:clinic_supply:connect","I2:clinic_supply:stabilize","I2:clinic_supply:confirm","I2:distribution_audit:expose","I2:distribution_audit:trace","I2:distribution_audit:share_access"]
const STAGES := ["expose","trace","complete"]
const EXPOSE := "I2:distribution_audit:expose"
const TRACE := "I2:distribution_audit:trace"
const SHARE := "I2:distribution_audit:share_access"
const BACK := "I2:distribution_back_exposed"
const DOOR_RELAY := "I2:distribution_relay"
const DOOR_LOCK := "I2:distribution_lock"
const ISOLATION := "I2:trial_isolation_handle"
const TRIAL_RELAY := "I2:trial_relay"
const TRIAL_CONTROL := "I2:trial_controller"
const GAUGE_A := "I2:trial_gauge_a"
const GAUGE_B := "I2:trial_gauge_b"
const BRIDGE_RELAY := "I2:shared_bridge_relay"
const SERVICE_CONTROL := "I2:shared_bridge_service_control"
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
var trial_transitions: Array = []
var route: Dictionary = {}
var report_cache: Dictionary = {}
var native_exit_requested := false


static func preflight(args: PackedStringArray) -> Dictionary:
	_source_binding = {}
	var bound: Dictionary = SourceBinding.prepare(args,"normal-distribution",SOURCE_GOALS,EXPECTED)
	if not bound.get("ok",false): return {"ok":false,"code":bound.get("code","source_binding_rejected"),"config":{}}
	_source_binding = bound.binding
	args = bound.args
	SOURCE_PROFILE = str(_source_binding.constants["SOURCE_PROFILE"])
	SOURCE_REPORT_SHA256 = str(_source_binding.constants["SOURCE_REPORT_SHA256"])
	TWENTYSEVEN_DIGEST = str(_source_binding.constants["TWENTYSEVEN_DIGEST"])
	THIRTYONE_DIGEST = str(_source_binding.constants["THIRTYONE_DIGEST"])
	if SOURCE_REPORT_SHA256.length()!=64 or THIRTYONE_DIGEST.length()!=64: return {"ok":false,"code":"root_must_bind_actual_successful_clinic_evidence","config":{}}
	var values: Dictionary = {}
	for argument: String in args:
		var key := ""
		var value := ""
		if argument == "--qa-normal-distribution":
			key = "enabled"
			value = "true"
		else:
			for pair: Array in [["--qa-profile=","profile"],["--qa-normal-output=","output"],["--qa-normal-seconds=","seconds"],["--qa-distribution-stop-after=","stage"]]:
				if argument.begins_with(str(pair[0])):
					key = str(pair[1])
					value = argument.trim_prefix(str(pair[0]))
					break
		if key.is_empty() or value.is_empty() or values.has(key): return {"ok":false,"code":"unknown_empty_or_duplicate_distribution_cli","config":{}}
		values[key] = value
	for key: String in ["enabled","profile","output","seconds"]:
		if not values.has(key): return {"ok":false,"code":"four_normal_distribution_arguments_required","config":{}}
	if values.size() < 4 or values.size() > 5: return {"ok":false,"code":"invalid_distribution_argument_count","config":{}}
	if values.profile != SOURCE_PROFILE or not DirAccess.dir_exists_absolute("user://profiles_v3/" + SOURCE_PROFILE): return {"ok":false,"code":"same_existing_natural_profile_required","config":{}}
	var seconds: String = str(values.seconds)
	if not seconds.is_valid_int() or str(seconds.to_int()) != seconds or seconds.to_int() < 30 or seconds.to_int() > 600: return {"ok":false,"code":"distribution_seconds_30_to_600_required","config":{}}
	var stage: String = str(values.get("stage","complete"))
	if stage not in STAGES: return {"ok":false,"code":"invalid_distribution_stop_stage","config":{}}
	var selected_output: String = str(values.output).replace("\\","/")
	if not _output_valid(selected_output): return {"ok":false,"code":"new_absolute_normal_distribution_json_required","config":{}}
	var reader = Store.new("user://profiles_v3/" + SOURCE_PROFILE)
	var loaded: Dictionary = reader.load_profile()
	if not loaded.get("ok",false) or loaded.get("recovered",false): return {"ok":false,"code":"unrecovered_original_profile_required","config":{}}
	var saved: Dictionary = reader.snapshot()
	if not SourceBinding.start_matches(_source_binding,saved): return {"ok":false,"code":"verified_initial_source_generation_changed","config":{}}
	var verified: Dictionary = _source_check(saved)
	if not verified.ok: return {"ok":false,"code":verified.code,"config":{}}
	return {"ok":true,"code":"natural_distribution_prefix_verified","config":{"profile":SOURCE_PROFILE,"output":selected_output,"max_seconds":seconds.to_int(),"stop_after":stage,"source_profile_id":saved.profile_id,"source_lineage_id":saved.lineage_id,"source_receipts_sha256":verified.source_receipts_sha256}}


static func _source_check(saved: Dictionary) -> Dictionary:
	if not SourceBinding.same_identity(_source_binding,saved):
		return {"ok":false,"code":"verified_source_identity_mismatch"}
	if SOURCE_REPORT_SHA256.length()!=64 or THIRTYONE_DIGEST.length()!=64: return {"ok":false,"code":"actual_clinic_evidence_not_bound"}
	var world: Variant = saved.get("world")
	if not world is Dictionary or world.get("region_id")!="I2" or world.get("branch_id")!="main": return {"ok":false,"code":"same_natural_I2_main_branch_required"}
	if not world.get("actions") is Dictionary or not world.actions.get("opening") is Dictionary or not world.get("flags") is Dictionary: return {"ok":false,"code":"source_story_schema"}
	var state: Dictionary = world.actions.opening
	var completed: Variant = state.get("completed")
	if not completed is Array or completed.size()<31 or completed.size()>34: return {"ok":false,"code":"only_natural_thirty_one_to_thirty_four_prefix_accepted"}
	if completed!=EXPECTED.slice(0,completed.size()) or world.get("completed_objectives")!=completed or not state.get("receipts") is Dictionary or state.receipts.size()!=completed.size(): return {"ok":false,"code":"exact_natural_prefix_and_receipts_required"}
	if _receipts_digest(state,BASE_TWENTYSEVEN)!=TWENTYSEVEN_DIGEST or _receipts_digest(state,SOURCE_GOALS)!=THIRTYONE_DIGEST: return {"ok":false,"code":"actual_natural_source_receipts_changed"}
	var director = Director.new()
	var definitions: Dictionary = director.load_definitions(Director.DEFAULT_PATH,Catalog.extension_paths())
	if not definitions.get("ok",false): return {"ok":false,"code":"original_director_unavailable"}
	var valid: Dictionary = director.validate_state(state)
	if not valid.get("ok",false): return {"ok":false,"code":"original_director_replay_rejected:"+str(valid.get("code",""))}
	var flags: Dictionary = world.flags
	for flag: String in ["I1_gate","F1_gate","I1_boss","campaign_whale_v1","F1_boss","campaign_crown_v1","opening:underdeck_latched","opening:underdeck_route_verified","I2:clinic_ready"]:
		if not flags.get(flag,false): return {"ok":false,"code":"actual_boss_underdeck_and_commissioned_clinic_history_required"}
	var discoveries: Variant = saved.get("personal",{}).get("discoveries")
	var commits: Variant = saved.get("ledger",{}).get("commits")
	if not discoveries is Array or not commits is Dictionary: return {"ok":false,"code":"original_reward_ledger_required"}
	for prefix: String in ["boss:I1:harbor_whale:opening_v1:main:","boss:F1:parasitic_crown:opening_v1:main:"]:
		var found := false
		for receipt: Variant in commits:
			if str(receipt).begins_with(prefix): found=true
		if not found: return {"ok":false,"code":"actual_two_boss_transactions_required"}
	for discovery: String in ["boss:I1:harbor_whale","opening:whale_raw_command_record","boss:F1:parasitic_crown","opening:crown_imbalance_evidence","opening:underdeck_worker_bypass","I2:clinic_priority_misroute"]:
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
	return {"ok":true,"code":"natural_distribution_prefix_valid","completed":completed.duplicate(),"source_receipts_sha256":THIRTYONE_DIGEST}


func run(owner_session: Node, options: Dictionary = {}) -> Dictionary:
	if running or stopping or finished: return {"ok":false,"code":"already_started"}
	session = owner_session
	output = str(options.get("output","")).replace("\\","/")
	max_seconds = float(options.get("max_seconds",600))
	stop_after = str(options.get("stop_after","complete"))
	if not is_instance_valid(session) or not is_inside_tree() or options.get("profile") != SOURCE_PROFILE or session.store.root_path != "user://profiles_v3/"+SOURCE_PROFILE or not _output_valid(output) or not is_finite(max_seconds) or max_seconds < 30 or max_seconds > 600 or stop_after not in STAGES: return {"ok":false,"code":"mounted_same_profile_new_output_and_bound_required"}
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
	return {"ok":true,"code":"observing_natural_distribution","stop_after":stop_after,"max_seconds":max_seconds}


func _execute() -> void:
	if not _check(session.profile_ready and not session.active and not OS.has_feature("editor"),"actual exported MAIN before ordinary menu continuation"): _stop("exported_normal_menu_required"); return
	last_completed=initial.world.actions.opening.completed.duplicate()
	_phase("ordinary_menu_resume_natural_clinic_profile")
	session._ui_action("solo",{"frame":0})
	await _next()
	if not _healthy() or not _check(_receipts_digest(session.story.state,SOURCE_GOALS)==initial_digest,"normal menu retains every actual thirty-one source receipt",_status()): _stop("ordinary_source_resume_failed"); return
	if not await _dismiss_radio(): _stop("radio_not_closed"); return
	if not _check(session.region_id=="I2" and session.clinic.ready and session.distribution.ready and session.trial.ready and session.shared_access.ready,"normal I2 loads all four original physical facilities",_status()): _stop("normal_I2_facilities_unavailable"); return
	_bind_pilot()
	route=_route_definition()
	if not _check(not route.is_empty(),"candidate route derives from actual door, interior, gauge anchors, isolation body and bridge inspection API",route): _stop("actual_distribution_route_unavailable"); return
	if not _completed(EXPOSE):
		if not await _expose_back(): _stop("actual_low_door_or_back_reading_unproven"); return
	else: _event("inherited_original_back_reading",{"history":session.distribution.progress.snapshot(),"receipt":_receipt_for(EXPOSE)})
	if _stage("expose"): return
	if not await _dismiss_radio(): _stop("expose_radio_not_closed"); return
	if not _completed(TRACE):
		if not await _trace_actual_samples(): _stop("actual_isolation_samples_or_gauge_readings_unproven"); return
	else: _event("inherited_original_double_reading",{"observed_gauges":session.trial.observed_gauges(),"receipt":_receipt_for(TRACE)})
	if _stage("trace"): return
	if not await _dismiss_radio(): _stop("trace_radio_not_closed"); return
	if not _completed(SHARE):
		if not await _confirm_actual_bridge(): _stop("actual_locked_bridge_or_Consensus_commit_unproven"); return
	else: _event("inherited_original_access_choice",{"receipt":_receipt_for(SHARE),"note":"Original first choice remains; no second physical operation or reward is claimed."})
	if not _check(session.story.state.get("completed",[])==EXPECTED and _receipts_digest(session.story.state,SOURCE_GOALS)==initial_digest,"only the original three distribution goals extend the intact actual Clinic source",_status()): _stop("distribution_final_prefix_unproven"); return
	_stage("complete")

func _route_definition() -> Dictionary:
	var layout: Dictionary = session.distribution.module.layout()
	if layout.get("id")!="i2_distribution_cabinet_v1": return {}
	var origin: Vector3 = _v(layout.origin)
	var opening: Dictionary = layout.observation.door_opening
	var interior: Dictionary = layout.observation.interior
	var low: Vector3 = _v(interior.min)
	var high: Vector3 = _v(interior.max)
	var half: Vector3 = Vector3(float(_body().stats.width_m),float(_body().stats.height_m),float(_body().stats.length_m))*.5+Vector3.ONE*.19
	var center_y: float = clampf(2.8,low.y+half.y+.1,high.y-half.y-.1)
	var middle_x: float = (_v(opening.min).x+_v(opening.max).x)*.5
	if high.y-low.y<=half.y*2.0+.2 or _v(opening.max).x-_v(opening.min).x<=half.x*2.0+.2: return {}
	var inside: Vector3 = origin+Vector3(middle_x,center_y,0)
	var front: Vector3 = origin+Vector3(middle_x,center_y,5)
	var isolation: Variant = session.trial.module.entity_position(ISOLATION)
	if not isolation is Vector3 or not isolation.is_finite(): return {}
	var gauge_a: Vector3 = _v(session.story.markers.get(GAUGE_A,{}).get("position"))
	var gauge_b: Vector3 = _v(session.story.markers.get(GAUGE_B,{}).get("position"))
	var inspect: Vector3 = session.shared_access.inspection_position("service_span",float(_body().stats.height_m)*.5)
	if not gauge_a.is_finite() or not gauge_b.is_finite() or not inspect.is_finite(): return {}
	var altitude: float = minf(float(_body().max_altitude),11.0)
	if altitude<inspect.y+half.y+.2: return {}
	return {"inside":inside,"front":front,"east_airlane":Vector3(origin.x+5,center_y,origin.z+5),
		"east_device_candidates":[Vector3(origin.x+5,center_y,origin.z+2.8),Vector3(origin.x+4.6,center_y+.3,origin.z+3.3)],
		# Native ray/sweep query proved the shallow west views hit HandleStop-1.
		# A wider south angle clears its complete box and still gives +X impulse.
		"isolation_reference":isolation,"isolation_candidate_offsets":[Vector3(-2.8,1.25,2.7),Vector3(-2.8,1.4,3.1),Vector3(-3.2,1.25,3.1)],
		"west_airlane_x":origin.x-3.2,"station_front_z":1.2,"trial_control":Vector3(18,2.6,1.2),
		"gauge_A":gauge_a+Vector3(-.75,.85,3.93),"gauge_B":gauge_b+Vector3(.75,.85,3.93),
		"bridge_inspection":inspect,"external_altitude":altitude,"aircraft_half_extent_with_margin":half,
		"layout_origin":origin,"door_opens_direction":"UP","door_opening":opening,"interior":interior,
		"gauge_note":"Lateral readings keep the nearer return switch from receiving G; actual nearest is rechecked."}

func _expose_back() -> bool:
	_phase("real_low_door_power_takeover_and_panel_read")
	var current: Vector3 = _body().global_position
	var east: Vector3 = route.east_airlane
	var altitude: float = route.external_altitude
	if not await _navigate([Vector3(current.x,altitude,current.z),Vector3(east.x,altitude,east.z),east],"outside_actual_cabinet_east_face"): return false
	var cabinet: Dictionary = session.distribution.module.snapshot()
	if not cabinet.get("electric_latched",false):
		var vantage: Vector3 = _visible_candidate(route.east_device_candidates,[DOOR_RELAY,DOOR_LOCK])
		if not _check(vantage.is_finite(),"actual hull-clear east candidate sees both physical devices",{"candidates":route.east_device_candidates,"rays":_candidate_rays(route.east_device_candidates,[DOOR_RELAY,DOOR_LOCK])}): return false
		if not await _navigate([vantage],"actual_low_door_devices"): return false
		if not session.entities[DOOR_RELAY].get("powered",false):
			if not await _cast(DOOR_RELAY,"charge",KEY_6): return false
		if float(session.entities[DOOR_LOCK].get("takeover_remaining",0))<=0:
			if not await _cast(DOOR_LOCK,"takeover",KEY_0): return false
		var deadline: float = minf(max_seconds-10.0,_elapsed()+10.0)
		while _healthy() and not session.distribution.module.snapshot().electric_latched and _elapsed()<deadline: await _next()
		cabinet=session.distribution.module.snapshot()
		if not _check(cabinet.electric_latched and float(cabinet.door_fraction)==1.0 and not cabinet.door_blocked,"actual upward door sweep reaches its permanent full latch",_mechanisms_debug()): return false
	if not await _navigate([east,route.front,route.inside],"through_actual_open_low_door"): return false
	if not await _contact(BACK,EXPOSE): return false
	var history: Dictionary = session.distribution.progress.snapshot()
	return _check(history.back_observed and _receipt_for(EXPOSE).get("option")==history.method,"original successful ten-ray back reading is saved before its matching Story fact",{"history":history,"receipt":_receipt_for(EXPOSE)})

func _trace_actual_samples() -> bool:
	_phase("actual_isolation_handle_then_two_twenty_litre_samples")
	# Leave by the real door. Resumed legal prefixes start at ordinary I2 spawn.
	if _body().global_position.distance_to(Vector3(route.inside))<1.5:
		if not await _navigate([route.front],"leave_actual_cabinet_low_door"): return false
	else:
		var current: Vector3 = _body().global_position
		var front: Vector3 = route.front
		var altitude: float = route.external_altitude
		if not await _navigate([Vector3(current.x,altitude,current.z),Vector3(front.x,altitude,front.z),front],"normal_spawn_to_cabinet_south"): return false
	var west_x: float = route.west_airlane_x
	if not await _navigate([Vector3(west_x,2.8,-5)],"outside_actual_low_isolation_sweep"): return false
	var link: Dictionary = session.trial.module.link.status()
	if not link.trial_ready:
		var handle: Vector3 = _target_position(ISOLATION)
		var candidates: Array = []
		for offset: Vector3 in route.isolation_candidate_offsets: candidates.append(handle+offset)
		var vantage: Vector3 = _visible_candidate(candidates,[ISOLATION])
		if not _check(vantage.is_finite(),"actual low-handle ray and complete aircraft hull share a clear west candidate",{"candidates":candidates,"rays":_candidate_rays(candidates,[ISOLATION])}): return false
		if not await _navigate([vantage],"real_west_isolation_handle_approach"): return false
		if not await _cast(ISOLATION,"push_pull",KEY_2): return false
		var deadline: float = minf(max_seconds-10.0,_elapsed()+8.0)
		while _healthy() and not session.trial.module.link.status().trial_ready and _elapsed()<deadline: await _next()
		link=session.trial.module.link.status()
		if not _check(link.trial_ready and link.high_closed and link.low_open and link.pose_valid and not link.blocked,"original bounded impulse closes high shutters before opening the actual low path",link): return false
	else: _event("inherited_real_trial_isolation",link)
	# Approach around the WEST side, not through the actual source tank.
	if not await _navigate([Vector3(west_x,2.8,-5),Vector3(west_x,2.8,route.station_front_z),Vector3(route.trial_control.x,2.8,route.station_front_z),route.trial_control],"around_actual_bench_west_to_front"): return false
	if not await _pulse_samples(): return false
	if not await _read_gauge("A",GAUGE_A,route.gauge_A): return false
	if not await _read_gauge("B",GAUGE_B,route.gauge_B): return false
	var deadline: float = minf(max_seconds-10.0,_elapsed()+8.0)
	while _healthy() and not _completed(TRACE) and _elapsed()<deadline: await _next()
	var fact: Dictionary = session.trial.committed_flow_fact()
	var readings: Dictionary = session.trial.observed_gauges()
	return _check(_completed(TRACE) and not readings.A.is_empty() and not readings.B.is_empty() and _receipt_for(TRACE).get("option")==fact.get("option"),"both original durable opposite first-sample readings precede the actual method-derived trace receipt",{"fact":fact,"readings":readings,"receipt":_receipt_for(TRACE)})

func _pulse_samples() -> bool:
	var status: Dictionary = session.trial.module.station.status()
	if status.both_samples_recorded:
		_event("inherited_actual_first_samples",status)
		return _samples_exact(status)
	if not session.entities[TRIAL_RELAY].get("powered",false):
		if not await _cast(TRIAL_RELAY,"charge",KEY_6): return false
	for cycle: int in range(3):
		if not _healthy(): return false
		if float(session.entities[TRIAL_CONTROL].get("takeover_remaining",0))<=0:
			if not await _cast(TRIAL_CONTROL,"takeover",KEY_0): return false
		var deadline: float = minf(max_seconds-10.0,_elapsed()+11.0)
		var next_poll := 0.0
		while _healthy() and _elapsed()<deadline:
			await _next()
			if _elapsed()<next_poll: continue
			next_poll=_elapsed()+.25
			status=session.trial.module.station.status()
			_record_trial_transition(status,cycle)
			if status.both_samples_recorded: return _check(_samples_exact(status),"actual isolated 200L loop forms both immutable 20L samples from real flow",status)
			if float(session.entities[TRIAL_CONTROL].get("takeover_remaining",0))<=0: break
	return _check(false,"bounded ordinary pulse attempts produce both actual first samples",_mechanisms_debug())

func _samples_exact(status: Dictionary) -> bool:
	if not status.get("both_samples_recorded",false): return false
	var total := 0
	for label: String in ["A","B"]:
		var sample: Dictionary = status.get("samples",{}).get(label,{})
		if not sample.get("complete",false) or int(sample.get("clean_ml",-1))+int(sample.get("dirty_ml",-1))!=20000 or int(sample.get("manual_ml",-1))+int(sample.get("pulse_ml",-1))!=20000: return false
		total+=int(sample.manual_ml)+int(sample.pulse_ml)
	return total==40000

func _record_trial_transition(status: Dictionary, cycle: int) -> void:
	var key: String = JSON.stringify([status.get("phase"),status.get("reason"),status.get("desired_selector"),int(float(status.samples.A.moved_ml)/5000.0),int(float(status.samples.B.moved_ml)/5000.0)])
	if not trial_transitions.is_empty() and trial_transitions[-1].get("key")==key: return
	var row: Dictionary = {"key":key,"cycle":cycle,"seconds":_elapsed(),"status":status,"link":session.trial.module.link.status()}
	trial_transitions.append(_plain(row))
	_event("actual_trial_transition",row)

func _read_gauge(label: String, target: String, at: Vector3) -> bool:
	if not session.trial.observed_gauges()[label].is_empty():
		_event("inherited_original_gauge_reading",{"label":label,"reading":session.trial.observed_gauges()[label]})
		return true
	# Whole-hull native query proved z=1.2 clear including .22m arrival
	# uncertainty and .36m minimum braking margin. Align before descending.
	var current: Vector3 = _body().global_position
	if not await _navigate([Vector3(at.x,current.y,at.z),at],"actual_gauge_"+label+"_front"): return false
	if not await _dismiss_radio(): return false
	var deadline: float = minf(max_seconds-10.0,_elapsed()+8.0)
	var next_press := 0.0
	while _healthy() and session.trial.observed_gauges()[label].is_empty() and _elapsed()<deadline:
		if _elapsed()>=next_press:
			var nearest: String = session.story.nearest(_body().global_position)
			if not _check(nearest==target,"nearest normal G is the selected gauge, not the central return switch",{"actual":nearest,"expected":target,"position":_body().global_position}): return false
			_record_g(target)
			next_press=_elapsed()+.6
		await _next()
	var reading: Dictionary = session.trial.observed_gauges()[label]
	var sample: Dictionary = reading.get("sample",{})
	return _check(not reading.is_empty() and reading.get("receiver_id")==("I2:trial_receiver_a" if label=="A" else "I2:trial_receiver_b") and int(sample.get("clean_ml",-1))+int(sample.get("dirty_ml",-1))==20000 and not session.trial.has_pending_observation(),"actual near/LOS G durably saves receiver "+label+" and its complete opposite first sample",reading)


func _confirm_actual_bridge() -> bool:
	_phase("real_service_bridge_motor_pin_and_explicit_Consensus_G")
	var west_x: float = route.west_airlane_x
	# Gauge viewpoints are UNDER the real deck. Leave around the bench before
	# rising north of the bridge; never ascend through a landing/deck.
	if _body().global_position.x>west_x-1.0 and _body().global_position.z>float(route.station_front_z)-1.0 and _body().global_position.y<4:
		if not await _navigate([Vector3(west_x,_body().global_position.y,route.station_front_z),Vector3(west_x,2.8,route.station_front_z),Vector3(west_x,2.8,-5)],"out_from_under_real_bridge"): return false
	var current: Vector3 = _body().global_position
	var inspect: Vector3 = route.bridge_inspection
	var altitude: float = route.external_altitude
	if not await _navigate([Vector3(current.x,altitude,current.z),Vector3(inspect.x,altitude,inspect.z),inspect],"above_actual_routes_to_inside_control_view"): return false
	var status: Dictionary = session.shared_access.module.status()
	if not (status.locked and status.mode=="service_span"):
		if not session.entities[BRIDGE_RELAY].get("powered",false):
			if not await _cast(BRIDGE_RELAY,"charge",KEY_6): return false
		if float(session.entities[SERVICE_CONTROL].get("takeover_remaining",0))<=0:
			if not await _cast(SERVICE_CONTROL,"takeover",KEY_0): return false
		var deadline: float = minf(max_seconds-10.0,_elapsed()+11.0)
		while _healthy() and _elapsed()<deadline:
			await _next()
			status=session.shared_access.module.status()
			if status.locked and status.mode=="service_span": break
		if not _check(status.locked and status.mode=="service_span" and status.pose_valid and not status.blocked,"actual bridge retracts its pin, moves 8m, reinserts and locks at service_span",_mechanisms_debug()): return false
	else: _event("inherited_actual_service_bridge_pose",status)
	var access: Dictionary = session.shared_access.module.access_report()
	if not _check(access.get("ok",false) and access.get("choice_ready",false) and access.get("public_access",false) and access.get("service_access",false),"actual current body clears both supported routes before original G/Consensus",access): return false
	if not await _contact(SERVICE_CONTROL,SHARE): return false
	return _check(_receipt_for(SHARE).get("option")=="service_span" and session.story.state.get("choices",{}).get(SHARE)=="service_span" and session.consensus.current_proposal().is_empty(),"normal G commits only the actually locked service arrangement through original solo Consensus and Store",{"receipt":_receipt_for(SHARE),"choices":session.story.state.get("choices",{}),"last_commit":session.last_commit_result})

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
	var deadline: float = minf(max_seconds-10.0,_elapsed()+8.0)
	while _healthy() and (float(session.cooldowns.get(1,0))>0 or float(session.entities[session._actor_id(1)].energy)<cost or ability=="takeover" and float(session.entities[target].get("takeover_remaining",0))>0) and _elapsed()<deadline: await _next()
	if not _healthy(): return false
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

func _mechanisms_debug() -> Dictionary:
	if not _live() or session.region_id!="I2": return {}
	return {"cabinet":session.distribution.module.snapshot() if session.distribution.ready else {},"back_history":session.distribution.progress.snapshot(),"isolation":session.trial.module.link.status() if session.trial.ready else {},"trial":session.trial.module.station.status() if session.trial.ready else {},"gauges":session.trial.observed_gauges(),"bridge":session.shared_access.module.status() if session.shared_access.ready else {},"clinic":session.clinic.module.status() if session.clinic.ready else {},"facility_errors":{"clinic":session.clinic.error,"distribution":session.distribution.error,"trial":session.trial.error,"shared_access":session.shared_access.error}}


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
	return path.is_absolute_path() and "://" not in path and ".." not in path and "\n" not in path and "\r" not in path and path.get_file().begins_with("normal-distribution-") and path.get_extension() == "json" and not FileAccess.file_exists(path) and not DirAccess.dir_exists_absolute(path)

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
	_event("actual_stage_observed",{"stage":value,"state":_mechanisms_debug(),"status":_status()})
	if stop_after==value:
		_stop("normal_distribution_complete" if value=="complete" else "requested_stage_pause")
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
	var complete: bool = reason=="normal_distribution_complete" and failures.is_empty() and logger.errors.is_empty() and preserved and saved_now and matches_live and saved.world.actions.opening.completed==EXPECTED
	var stage_stopped: bool = reason=="requested_stage_pause" and stop_after in reached_stages and failures.is_empty() and logger.errors.is_empty() and preserved and saved_now and matches_live and preservation.common_paused
	if complete:
		for reward: String in ["I2:distribution_back_route","I2:label_flow_disagreement","I2:shared_access_plan"]:
			_check(saved.personal.discoveries.count(reward)==1,"original distribution discovery is unique and durable: "+reward,saved.personal.discoveries)
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
	report_cache["distribution_segment_complete"]=false
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
	print("NORMAL_DISTRIBUTION_EXIT_WATCHDOG_FAIL "+JSON.stringify(report_cache.native_exit))
	# Do not use tree.quit/OS.kill as a fallback around a rejected Store gate.
	# The runner's already bounded private Job remains the external hard limit.

func _exit_tree() -> void:
	if not native_exit_requested or report_cache.is_empty(): return
	report_cache["native_exit"]["observed_scene_exit"]=true
	if is_instance_valid(session):
		report_cache["native_exit"]["audio"]=_plain(session.last_audio_shutdown_result)
		if not session.last_audio_shutdown_result.get("ready",false):
			report_cache["complete"]=false
			report_cache["distribution_segment_complete"]=false
			report_cache["requested_stage_stopped"]=false
			report_cache["failures"].append("Original final-exit audio drain did not become ready.")
	report_cache["engine_errors"]=_plain(logger.errors)
	if not logger.errors.is_empty():
		report_cache["complete"]=false
		report_cache["distribution_segment_complete"]=false
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
	print("NORMAL_DISTRIBUTION_EVENT "+JSON.stringify(row))

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
		print("NORMAL_DISTRIBUTION_PROGRESS "+JSON.stringify(_plain(row)))

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
		result["water"]=_mechanisms_debug()
		result["pilot"]=pilot.report() if pilot!=null else {}
	return result


func _write_report(reason: String, complete: bool, stage_stopped: bool) -> void:
	finished=true
	running=false
	var report: Dictionary = {"complete":complete,"distribution_segment_complete":complete,"requested_stage_stopped":stage_stopped,"requested_stage":stop_after,"reached_stages":reached_stages,"stop_reason":reason,"phase":phase,"seconds":_elapsed(),"max_seconds":max_seconds,"profile":SOURCE_PROFILE,"user_dir":OS.get_user_data_dir(),"executable":OS.get_executable_path(),"exported_application":not OS.has_feature("editor"),"runtime_cwd":DirAccess.open(".").get_current_dir(),"source_generation":initial.get("generation"),"base_twenty_seven_receipts_sha256":TWENTYSEVEN_DIGEST,"source_report_sha256":SOURCE_REPORT_SHA256,"source_receipts_sha256":initial_digest,"physics_frames":physics_frames,"actual_distance_m":actual_distance,"max_frame_distance_m_excluding_normal_travel":max_frame_distance,"checks":checks,"failures":failures,"engine_errors":logger.errors,"events":events,"ten_second_samples":samples,"route":route,"actual_abilities":actual_abilities,"actual_interactions":actual_interactions,"actual_trial_transitions":trial_transitions,"status":_status(),"preservation":preservation,"fresh_reader":final_reader,"story_receipts":session.story.state.get("receipts",{}),"stats":session.stats,"pilot":pilot.report() if pilot!=null and is_instance_valid(pilot.body) else {},"scope":"Exported MAIN same-natural-profile 31-to-34 continuation only. Original menu/spawn, continuous actual Flight/Pilot swept motion, normal ability keys/Tab/F, real upward low door, two-panel G reading, actual isolation cam, actual 20L opposite first samples and two local G readings, actual 8m bridge motor/pin and explicit G/solo Consensus, original Store/SaveGate/fresh reader and production native audio quit. No actor/mechanism/water/HP/clock/flags/progress fixtures, manual simulation, profile clone/rollback or reward import. Inherited legitimate histories are distinguished from new observations. Bounded unverified route candidate, not whole campaign, fun, LAN, controller or performance acceptance."}
	report.merge(SourceBinding.audit(_source_binding))
	report["native_exit"]={"requested":true,"through":"session._quit","observed_scene_exit":false,"watchdog_failed":false}
	report_cache=_plain(report)
	var written: bool = _flush_report()
	print("NORMAL_DISTRIBUTION_RESULT "+JSON.stringify({"complete":complete,"requested_stage_stopped":stage_stopped,"written":written,"reason":reason,"phase":phase,"seconds":_elapsed(),"failures":failures,"engine_errors":logger.errors}))
	native_exit_requested=true
	_native_exit_watchdog.call_deferred()
	session._quit()

