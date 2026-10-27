extends Node
const SourceBinding = preload("res://scripts/v3/qa/twin_source_binding.gd")
static var _source_binding: Dictionary = {}
## Explicit exported MAIN observer: Bound to the observed dev77 natural Underdeck COMPLETE report.
## All flight, impulses, transfer/history, passage checks and Store work belong
## to original production callbacks. This observer never edits a mechanism.
const Pilot = preload("res://scripts/v3/gameplay/canal/canal_transport_physics/transport_pilot.gd")
const Store = preload("res://scripts/v3/core/twin_world_store.gd")
const Director = preload("res://scripts/v3/gameplay/actions/twin_action_director.gd")
const Catalog = preload("res://scripts/v3/campaign/twin_campaign_catalog.gd")
const ClinicProgress = preload("res://scripts/v3/gameplay/actions/twin_clinic_progress.gd")
const I2Results = preload("res://scripts/v3/gameplay/twin_i2_result_ledger.gd")
static var SOURCE_PROFILE := ""
# Verified actual source only; no progress is imported from its report.
static var SOURCE_REPORT_SHA256 := ""
static var TWENTYSEVEN_DIGEST := ""
static var TWENTYTHREE_DIGEST := ""
const SOURCE_GOALS := ["I1:rescue:brief","I1:rescue:channel","I1:rescue:contact","I1:rescue:evacuate","I1:evidence:trace","I1:evidence:engineer","I1:evidence:ledger","I1:evidence:echo","F1:needs:listen","F1:needs:nursery","F1:needs:route","F1:repair:plan","F1:repair:light","F1:repair:grow","F1:repair:confirm","I1:whale:brief","I1:whale:engage","I1:whale:disable","I1:whale:record","F1:crown:brief","F1:crown:engage","F1:crown:disable","F1:crown:restore","I1:underdeck:read","I1:underdeck:enter","I1:underdeck:release","I1:underdeck:traverse"]
const BASE_TWENTYTHREE := ["I1:rescue:brief","I1:rescue:channel","I1:rescue:contact","I1:rescue:evacuate","I1:evidence:trace","I1:evidence:engineer","I1:evidence:ledger","I1:evidence:echo","F1:needs:listen","F1:needs:nursery","F1:needs:route","F1:repair:plan","F1:repair:light","F1:repair:grow","F1:repair:confirm","I1:whale:brief","I1:whale:engage","I1:whale:disable","I1:whale:record","F1:crown:brief","F1:crown:engage","F1:crown:disable","F1:crown:restore"]
const EXPECTED := ["I1:rescue:brief","I1:rescue:channel","I1:rescue:contact","I1:rescue:evacuate","I1:evidence:trace","I1:evidence:engineer","I1:evidence:ledger","I1:evidence:echo","F1:needs:listen","F1:needs:nursery","F1:needs:route","F1:repair:plan","F1:repair:light","F1:repair:grow","F1:repair:confirm","I1:whale:brief","I1:whale:engage","I1:whale:disable","I1:whale:record","F1:crown:brief","F1:crown:engage","F1:crown:disable","F1:crown:restore","I1:underdeck:read","I1:underdeck:enter","I1:underdeck:release","I1:underdeck:traverse","I2:clinic_supply:diagnose","I2:clinic_supply:connect","I2:clinic_supply:stabilize","I2:clinic_supply:confirm"]
const STAGES := ["diagnosed","connected","stabilized","complete"]
const GRAVITY := "I2:clinic_gravity_valve"
const FLAG := "I2:clinic_ready"
const DISCOVERY := "I2:clinic_priority_misroute"
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
var last_water_key := ""
var water_samples: Array = []
var actual_impulses: Array = []
var route: Dictionary = {}
var report_cache: Dictionary = {}
var native_exit_requested := false


static func preflight(args: PackedStringArray) -> Dictionary:
	_source_binding = {}
	var bound: Dictionary = SourceBinding.prepare(args,"normal-clinic",SOURCE_GOALS,EXPECTED)
	if not bound.get("ok",false): return {"ok":false,"code":bound.get("code","source_binding_rejected"),"config":{}}
	_source_binding = bound.binding
	args = bound.args
	SOURCE_PROFILE = str(_source_binding.constants["SOURCE_PROFILE"])
	SOURCE_REPORT_SHA256 = str(_source_binding.constants["SOURCE_REPORT_SHA256"])
	TWENTYTHREE_DIGEST = str(_source_binding.constants["TWENTYTHREE_DIGEST"])
	TWENTYSEVEN_DIGEST = str(_source_binding.constants["TWENTYSEVEN_DIGEST"])
	if SOURCE_REPORT_SHA256.length()!=64 or TWENTYSEVEN_DIGEST.length()!=64: return {"ok":false,"code":"root_must_bind_actual_successful_underdeck_evidence","config":{}}
	var values: Dictionary = {}
	for argument: String in args:
		var key := ""
		var value := ""
		if argument == "--qa-normal-clinic":
			key = "enabled"
			value = "true"
		else:
			for pair: Array in [["--qa-profile=","profile"],["--qa-normal-output=","output"],["--qa-normal-seconds=","seconds"],["--qa-clinic-stop-after=","stage"]]:
				if argument.begins_with(str(pair[0])):
					key = str(pair[1])
					value = argument.trim_prefix(str(pair[0]))
					break
		if key.is_empty() or value.is_empty() or values.has(key): return {"ok":false,"code":"unknown_empty_or_duplicate_clinic_cli","config":{}}
		values[key] = value
	for key: String in ["enabled","profile","output","seconds"]:
		if not values.has(key): return {"ok":false,"code":"four_normal_clinic_arguments_required","config":{}}
	if values.size() < 4 or values.size() > 5: return {"ok":false,"code":"invalid_clinic_argument_count","config":{}}
	if values.profile != SOURCE_PROFILE or not DirAccess.dir_exists_absolute("user://profiles_v3/" + SOURCE_PROFILE): return {"ok":false,"code":"same_existing_natural_profile_required","config":{}}
	var seconds: String = str(values.seconds)
	if not seconds.is_valid_int() or str(seconds.to_int()) != seconds or seconds.to_int() < 30 or seconds.to_int() > 600: return {"ok":false,"code":"clinic_seconds_30_to_600_required","config":{}}
	var stage: String = str(values.get("stage","complete"))
	if stage not in STAGES: return {"ok":false,"code":"invalid_clinic_stop_stage","config":{}}
	var selected_output: String = str(values.output).replace("\\","/")
	if not _output_valid(selected_output): return {"ok":false,"code":"new_absolute_normal_clinic_json_required","config":{}}
	var reader = Store.new("user://profiles_v3/" + SOURCE_PROFILE)
	var loaded: Dictionary = reader.load_profile()
	if not loaded.get("ok",false) or loaded.get("recovered",false): return {"ok":false,"code":"unrecovered_original_profile_required","config":{}}
	var saved: Dictionary = reader.snapshot()
	if not SourceBinding.start_matches(_source_binding,saved): return {"ok":false,"code":"verified_initial_source_generation_changed","config":{}}
	var verified: Dictionary = _source_check(saved)
	if not verified.ok: return {"ok":false,"code":verified.code,"config":{}}
	return {"ok":true,"code":"natural_clinic_prefix_verified","config":{"profile":SOURCE_PROFILE,"output":selected_output,"max_seconds":seconds.to_int(),"stop_after":stage,"source_profile_id":saved.profile_id,"source_lineage_id":saved.lineage_id,"source_receipts_sha256":verified.source_receipts_sha256}}

static func _source_check(saved: Dictionary) -> Dictionary:
	if not SourceBinding.same_identity(_source_binding,saved):
		return {"ok":false,"code":"verified_source_identity_mismatch"}
	if SOURCE_REPORT_SHA256.length()!=64 or TWENTYSEVEN_DIGEST.length()!=64: return {"ok":false,"code":"actual_underdeck_evidence_not_bound"}
	var world: Variant = saved.get("world")
	if not world is Dictionary or world.get("region_id") not in ["I1","I2"] or world.get("branch_id")!="main": return {"ok":false,"code":"same_natural_main_branch_I1_or_I2_required"}
	if not world.get("actions") is Dictionary or not world.actions.get("opening") is Dictionary or not world.get("flags") is Dictionary: return {"ok":false,"code":"source_story_schema"}
	var state: Dictionary = world.actions.opening
	var completed: Variant = state.get("completed")
	if not completed is Array or completed.size()<27 or completed.size()>31: return {"ok":false,"code":"only_natural_twenty_seven_to_thirty_one_prefix_accepted"}
	if completed!=EXPECTED.slice(0,completed.size()) or world.get("completed_objectives")!=completed or not state.get("receipts") is Dictionary or state.receipts.size()!=completed.size(): return {"ok":false,"code":"exact_natural_prefix_and_receipts_required"}
	if _receipts_digest(state,BASE_TWENTYTHREE)!=TWENTYTHREE_DIGEST or _receipts_digest(state,SOURCE_GOALS)!=TWENTYSEVEN_DIGEST: return {"ok":false,"code":"actual_natural_source_receipts_changed"}
	var director = Director.new()
	var definitions: Dictionary = director.load_definitions(Director.DEFAULT_PATH,Catalog.extension_paths())
	if not definitions.get("ok",false): return {"ok":false,"code":"original_director_unavailable"}
	var valid: Dictionary = director.validate_state(state)
	if not valid.get("ok",false): return {"ok":false,"code":"original_director_replay_rejected:"+str(valid.get("code",""))}
	var flags: Dictionary = world.flags
	for flag: String in ["I1_gate","F1_gate","I1_boss","campaign_whale_v1","F1_boss","campaign_crown_v1","opening:underdeck_latched","opening:underdeck_route_verified"]:
		if not flags.get(flag,false): return {"ok":false,"code":"actual_two_bosses_and_underdeck_history_required"}
	var discoveries: Variant = saved.get("personal",{}).get("discoveries")
	var commits: Variant = saved.get("ledger",{}).get("commits")
	if not discoveries is Array or not commits is Dictionary: return {"ok":false,"code":"original_reward_ledger_required"}
	for prefix: String in ["boss:I1:harbor_whale:opening_v1:main:","boss:F1:parasitic_crown:opening_v1:main:"]:
		var found := false
		for receipt: Variant in commits:
			if str(receipt).begins_with(prefix): found=true
		if not found: return {"ok":false,"code":"actual_two_boss_transactions_required"}
	for discovery: String in ["boss:I1:harbor_whale","opening:whale_raw_command_record","boss:F1:parasitic_crown","opening:crown_imbalance_evidence","opening:underdeck_worker_bypass"]:
		if discoveries.count(discovery)!=1: return {"ok":false,"code":"actual_source_rewards_and_records_required"}
	var projected: Dictionary = I2Results.validate_world(world,discoveries)
	if not projected.get("ok",false): return {"ok":false,"code":"original_I2_result_boundary:"+str(projected.get("error",""))}
	var tracker = ClinicProgress.new()
	var clinic: Dictionary = projected.projected.clinic
	var restored: Dictionary = tracker.prepare_restore(world.get("environment",{}).get("I2_water"),clinic.completed,clinic.flags)
	if not restored.get("ok",false): return {"ok":false,"code":"original_clinic_water_history:"+str(restored.get("code",""))}
	var confirmed: bool = "I2:clinic_supply:confirm" in completed
	if bool(flags.get(FLAG,false))!=confirmed or discoveries.count(DISCOVERY)!=(1 if confirmed else 0): return {"ok":false,"code":"clinic_durable_flag_or_discovery_prefix_mismatch"}
	return {"ok":true,"code":"natural_clinic_prefix_valid","completed":completed.duplicate(),"source_receipts_sha256":TWENTYSEVEN_DIGEST,"clinic_restore":restored}


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
	return {"ok":true,"code":"observing_natural_clinic","stop_after":stop_after,"max_seconds":max_seconds}

func _execute() -> void:
	if not _check(session.profile_ready and not session.active and not OS.has_feature("editor"),"actual exported MAIN before ordinary menu continuation"): _stop("exported_normal_menu_required"); return
	last_completed=initial.world.actions.opening.completed.duplicate()
	_phase("ordinary_menu_resume_natural_underdeck_profile")
	session._ui_action("solo",{"frame":0})
	await _next()
	if not _healthy() or not _check(_receipts_digest(session.story.state,SOURCE_GOALS)==initial_digest,"normal menu retains every actual twenty-seven source receipt",_status()): _stop("ordinary_source_resume_failed"); return
	if not await _dismiss_radio(): _stop("radio_not_closed"); return
	if session.region_id=="I1":
		if not _check(session._can_travel_to("I2"),"original completed Underdeck opens the normal M route to I2"): _stop("normal_I2_travel_locked"); return
		_press_key(KEY_M)
		if session.interface.travel.visible:
			session._ui_action("travel_to",{"region_id":"I2"})
		else:
			var proposal: Dictionary = session.consensus.current_proposal()
			if not _check(session.region_id=="I2" or proposal.get("kind")=="region_change" and proposal.get("payload",{}).get("region_id")=="I2","normal M follows its actual destination or region-change proposal",_status()): _stop("normal_M_destination_unavailable"); return
		var travel_deadline: float = _elapsed()+10.0
		while _healthy() and session.region_id!="I2" and _elapsed()<travel_deadline: await _next()
	if not _check(_healthy() and session.region_id=="I2" and session.clinic.ready and is_instance_valid(session.clinic.module),"normal travel loads the actual clinic waterworks and original I2 spawn",_status()): _stop("normal_I2_arrival_failed"); return
	_bind_pilot()
	route=_route_definition()
	if not _check(not route.is_empty(),"candidate derives from actual clinic south canopy gap, landing and valve-stop geometry",route): _stop("actual_clinic_layout_route_unavailable"); return
	var observed: Vector3 = _body().global_position
	var front: Vector3 = route.south_opening
	var altitude: float = float(route.external_altitude)
	if not await _navigate([Vector3(observed.x,altitude,observed.z),Vector3(front.x,altitude,front.z),front,route.check],"real_southern_clinic_opening"): _stop("clinic_south_candidate_route_blocked"); return
	if not _completed("I2:clinic_supply:diagnose"):
		if not await _contact("I2:clinic_demand","I2:clinic_supply:diagnose"): _stop("normal_clinic_diagnosis_G_not_committed"); return
	if _stage("diagnosed"): return
	if not await _dismiss_radio(): _stop("diagnosis_radio_not_closed"); return
	var inherited_route: String = str(session.clinic.progress.snapshot().route_method)
	if inherited_route.is_empty():
		if not await _navigate([front,Vector3(front.x,altitude,front.z),route.valve_overhead,route.valve_approach],"real_west_south_gravity_valve_approach"): _stop("high_valve_candidate_route_blocked"); return
		if not await _push_gravity_valve(): _stop("normal_gravity_impulse_rejected"); return
		var opening_deadline: float = minf(max_seconds-10.0,_elapsed()+8.0)
		while _healthy() and str(session.clinic.progress.snapshot().route_method).is_empty() and _elapsed()<opening_deadline: await _next()
		if not _check(session.clinic.progress.snapshot().route_method=="gravity" and int(session.clinic.module.status().clinic_volume_ml)>0 and float(session.clinic.module.status().gravity_fraction)>=.995,"original impulse completes physical rail travel and produces the first clean gravity transfer",_water_debug()): _stop("actual_gravity_transfer_unproven"); return
	else:
		_event("inherited_original_water_route",{"route":inherited_route,"history":session.clinic.progress.snapshot(),"note":"No new impulse or route credit is invented; this is original persisted water history."})
	var connect_deadline: float = minf(max_seconds-10.0,_elapsed()+8.0)
	while _healthy() and not _completed("I2:clinic_supply:connect") and _elapsed()<connect_deadline: await _next()
	if not _check(_completed("I2:clinic_supply:connect") and _receipt_for("I2:clinic_supply:connect").get("option")==session.clinic.progress.snapshot().route_method,"original Story saves the actual first-transfer method",_water_debug()): _stop("original_connect_fact_not_committed"); return
	if _stage("connected"): return
	if not await _dismiss_radio(): _stop("connect_radio_not_closed"); return
	# The caller never stands on the moving deck/linkage or inside access_clear's
	# actual 7x1.5x3m passage box. Return through the same observed south gap.
	if _body().global_position.distance_to(Vector3(route.check))>.22:
		if not await _navigate([route.valve_overhead,Vector3(front.x,altitude,front.z),front,route.check],"return_outside_actual_lift_sweep"): _stop("clinic_return_candidate_route_blocked"); return
	_phase("observe_actual_two_million_ml_cutoff_and_two_second_access")
	var stable_deadline: float = minf(max_seconds-10.0,_elapsed()+240.0)
	while _healthy() and not (_completed("I2:clinic_supply:stabilize") and _water_ready()) and _elapsed()<stable_deadline: await _next()
	if not _check(_completed("I2:clinic_supply:stabilize") and _water_ready(),"actual 2000L clean supply, automatic closed inlet, 5m deck and unobstructed access remain stable for two ordinary seconds",_water_debug()): _stop("actual_water_or_access_stability_unproven"); return
	if _stage("stabilized"): return
	if not _completed("I2:clinic_supply:confirm"):
		if not await _contact("I2:clinic_water_check","I2:clinic_supply:confirm"): _stop("normal_water_confirmation_G_not_committed"); return
	if not _check(session.story.state.get("completed",[])==EXPECTED and _receipts_digest(session.story.state,SOURCE_GOALS)==initial_digest and session.clinic.progress.snapshot().commissioned,"actual manual confirmation commits only the original four clinic goals and commissioned water history",_status()): _stop("clinic_final_prefix_or_commission_unproven"); return
	_stage("complete")

func _route_definition() -> Dictionary:
	var layout: Dictionary = session.clinic.module.layout()
	if layout.get("id")!="i2_clinic_waterworks_v1": return {}
	var solids: Dictionary = {}
	var roof_top := 0.0
	for solid: Dictionary in layout.get("fixed_solids",[]):
		solids[str(solid.id)]=solid
		roof_top=maxf(roof_top,_v(solid.max).y)
	for id: String in ["ClinicCanopyLeft","ClinicCanopyRight","EastLanding","GravityClosedStop"]:
		if not solids.has(id): return {}
	var left: Dictionary = solids.ClinicCanopyLeft
	var right: Dictionary = solids.ClinicCanopyRight
	var landing: Dictionary = solids.EastLanding
	var stop: Dictionary = solids.GravityClosedStop
	var check_at: Vector3 = _v(layout.anchors.water_check)
	var valve_at: Vector3 = _v(layout.gravity_valve.center)
	if not check_at.is_finite() or not valve_at.is_finite(): return {}
	var gap_low: float = _v(left.max).x
	var gap_high: float = _v(right.min).x
	var floor_y: float = _v(landing.max).y
	var canopy_y: float = minf(_v(left.min).y,_v(right.min).y)
	var projected_half := Vector3(float(_body().stats.width_m),float(_body().stats.height_m),float(_body().stats.length_m))*.5+Vector3.ONE*.19
	var check_y: float = check_at.y+.2
	if gap_high-gap_low<=projected_half.x*2.0 or check_y-projected_half.y<=floor_y or check_y+projected_half.y>=canopy_y: return {}
	var check := Vector3((gap_low+gap_high)*.5,check_y,check_at.z)
	var front := Vector3(check.x,check.y,_v(landing.max).z+2.5)
	var altitude: float = minf(_body().max_altitude,roof_top+3.0)
	if altitude<=roof_top+projected_half.y: return {}
	# Pure west is occluded by the real closed end-stop. Derive a south offset
	# whose ray is outside its z-max at the stop's closest-to-valve x face.
	var west_dx := 2.5
	var stop_dx: float = valve_at.x-_v(stop.max).x
	if stop_dx<=0.0: return {}
	var south_offset: float = maxf(2.5,(_v(stop.max).z-valve_at.z+.08)*west_dx/stop_dx+.12)
	var approach := Vector3(valve_at.x-west_dx,valve_at.y,valve_at.z+south_offset)
	return {"check":check,"south_opening":front,"external_altitude":altitude,
		"valve_approach":approach,"valve_overhead":Vector3(approach.x,altitude,approach.z),
		"south_gap_x":[gap_low,gap_high],"landing_top_y":floor_y,"canopy_bottom_y":canopy_y,
		"actual_valve_anchor":valve_at,"actual_closed_stop":stop,"gap_half_extent_with_margin":projected_half}

func _push_gravity_valve() -> bool:
	_phase("normal_2_Tab_F_push_of_real_gravity_axis")
	_press_key(KEY_2)
	if not _check(session.selected_ability=="push_pull","normal 2 key selects push/pull"): return false
	for _index: int in range(session.entities.size()+2):
		if str(session.locks.get(1,""))==GRAVITY: break
		_press_key(KEY_TAB)
		await _next()
		if not _healthy(): return false
	if not _check(str(session.locks.get(1,""))==GRAVITY,"normal Tab cycle selects the actual high-valve body",_status()): return false
	var ray: Dictionary = _gravity_ray()
	if not _check(ray.get("entity_id")==GRAVITY,"actual first-hit LOS reaches the real valve without excluding its stop or rail",ray): return false
	var deadline: float = minf(max_seconds-10.0,_elapsed()+3.0)
	while _healthy() and float(session.cooldowns.get(1,0))>0 and _elapsed()<deadline: await _next()
	if not _healthy(): return false
	var before: int = int(session.stats.abilities)
	var pose_before: Vector3 = session.clinic.module.entity_position(GRAVITY)
	var revision_before: int = int(session.entities[session._actor_id(1)].revision)
	_press_key(KEY_F)
	var accepted: bool = int(session.stats.abilities)==before+1
	var row: Dictionary = {"seconds":_elapsed(),"accepted":accepted,"before_revision":revision_before,
		"after_revision":session.entities[session._actor_id(1)].revision,"actor_position":_body().global_position,
		"valve_position_before":pose_before,"ray":ray,"native_axis_after":session.clinic.module.snapshot().axis}
	actual_impulses.append(_plain(row))
	return _check(accepted,"original F/Rules/FacilityRegistry accepts one actual bounded impulse",row)

func _gravity_ray() -> Dictionary:
	if not _live() or session.region_id!="I2" or not session.clinic.ready: return {}
	var point: Vector3 = session.clinic.module.entity_position(GRAVITY)
	var query := PhysicsRayQueryParameters3D.create(_body().global_position,point,MASK)
	query.exclude=[_body().get_rid()]
	var hit: Dictionary = session.world.get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty(): return {"entity_id":"","code":"no_first_hit","target":point}
	return {"entity_id":str(hit.collider.get_meta("entity_id","")),"position":hit.position,"collider":str(hit.collider.get_path()),"target":point}

func _water_ready() -> bool:
	if not _live() or session.region_id!="I2" or not session.clinic.ready: return false
	var status: Dictionary = session.clinic.module.status()
	var history: Dictionary = session.clinic.progress.snapshot()
	return int(status.get("clinic_volume_ml",0))==2000000 and float(status.get("clean_fraction",0))>=.95 and status.get("automatic_cutoff",false) and status.get("inlet_closed",false) and not status.get("platform_blocked",true) and absf(float(status.get("deck_top_y",0))-5.0)<=.002 and int(history.get("stable_usec",0))==2000000 and session.clinic.access_clear()

func _water_debug() -> Dictionary:
	if not _live() or session.region_id!="I2" or not session.clinic.ready: return {}
	return {"status":session.clinic.module.status(),"history":session.clinic.progress.snapshot(),
		"mechanism":session.clinic.module.snapshot(),"access_clear":session.clinic.access_clear(),"gravity_ray":_gravity_ray()}

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
	if session.region_id=="I2" and session.clinic.ready:
		var status: Dictionary = session.clinic.module.status()
		var history: Dictionary = session.clinic.progress.snapshot()
		var key: String = JSON.stringify([int(float(status.clinic_volume_ml)/100000.0),int(float(status.gravity_fraction)*20.0),status.platform_blocked,history.route_method,int(float(history.stable_usec)/250000.0),history.commissioned])
		if key!=last_water_key:
			last_water_key=key
			var row: Dictionary = {"seconds":_elapsed(),"position":body.global_position,"native_velocity":_native_velocity(),"water":_water_debug()}
			water_samples.append(_plain(row))
			_event("actual_water_transition",row)
	if pilot!=null: pilot.tick(delta,true,false)

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
		if not _check(session.story.nearest(_body().global_position)==target,"normal nearest G resolves "+target,_status()): return false
		if _elapsed()>=next_press:
			_press_g()
			next_press=_elapsed()+.6
		await _next()
	return _check(objective in session.story.state.get("completed",[]),"original near/LOS G commits "+objective,_status())

static func _output_valid(path: String) -> bool:
	return path.is_absolute_path() and "://" not in path and ".." not in path and "\n" not in path and "\r" not in path and path.get_file().begins_with("normal-clinic-") and path.get_extension() == "json" and not FileAccess.file_exists(path) and not DirAccess.dir_exists_absolute(path)

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
	_event("actual_stage_observed",{"stage":value,"state":_water_debug(),"status":_status()})
	if stop_after==value:
		_stop("normal_clinic_complete" if value=="complete" else "requested_stage_pause")
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
	preservation["original_water_history_resumed"]=true
	if not preserved: _check(false,"fresh original reader retains a legal same-source prefix",final_reader)
	if not saved_now: _check(false,"ordinary SaveGate succeeds before bounded QA stop",preservation)
	if saved_now and not matches_live: _check(false,"fresh original reader exactly matches actual live Story",final_reader)
	var complete: bool = reason=="normal_clinic_complete" and failures.is_empty() and logger.errors.is_empty() and preserved and saved_now and matches_live and saved.world.actions.opening.completed==EXPECTED
	var stage_stopped: bool = reason=="requested_stage_pause" and stop_after in reached_stages and failures.is_empty() and logger.errors.is_empty() and preserved and saved_now and matches_live and preservation.common_paused
	if complete:
		_check(saved.personal.discoveries.count(DISCOVERY)==1 and saved.world.flags.get(FLAG,false) and saved.world.environment.I2_water.history.commissioned,"actual original water commissioning and unique clinic discovery are durable",saved.personal.discoveries)
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
	report_cache["clinic_segment_complete"]=false
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
	print("NORMAL_CLINIC_EXIT_WATCHDOG_FAIL "+JSON.stringify(report_cache.native_exit))
	# Do not use tree.quit/OS.kill as a fallback around a rejected Store gate.
	# The runner's already bounded private Job remains the external hard limit.

func _exit_tree() -> void:
	if not native_exit_requested or report_cache.is_empty(): return
	report_cache["native_exit"]["observed_scene_exit"]=true
	if is_instance_valid(session):
		report_cache["native_exit"]["audio"]=_plain(session.last_audio_shutdown_result)
		if not session.last_audio_shutdown_result.get("ready",false):
			report_cache["complete"]=false
			report_cache["clinic_segment_complete"]=false
			report_cache["requested_stage_stopped"]=false
			report_cache["failures"].append("Original final-exit audio drain did not become ready.")
	report_cache["engine_errors"]=_plain(logger.errors)
	if not logger.errors.is_empty():
		report_cache["complete"]=false
		report_cache["clinic_segment_complete"]=false
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
	print("NORMAL_CLINIC_EVENT "+JSON.stringify(row))

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
		print("NORMAL_CLINIC_PROGRESS "+JSON.stringify(_plain(row)))

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
		result["water"]=_water_debug()
		result["pilot"]=pilot.report() if pilot!=null else {}
	return result

func _write_report(reason: String, complete: bool, stage_stopped: bool) -> void:
	finished=true
	running=false
	var report: Dictionary = {"complete":complete,"clinic_segment_complete":complete,"requested_stage_stopped":stage_stopped,"requested_stage":stop_after,"reached_stages":reached_stages,"stop_reason":reason,"phase":phase,"seconds":_elapsed(),"max_seconds":max_seconds,"profile":SOURCE_PROFILE,"user_dir":OS.get_user_data_dir(),"executable":OS.get_executable_path(),"exported_application":not OS.has_feature("editor"),"runtime_cwd":DirAccess.open(".").get_current_dir(),"source_generation":initial.get("generation"),"base_twenty_three_receipts_sha256":TWENTYTHREE_DIGEST,"source_report_sha256":SOURCE_REPORT_SHA256,"source_receipts_sha256":initial_digest,"physics_frames":physics_frames,"actual_distance_m":actual_distance,"max_frame_distance_m_excluding_normal_travel":max_frame_distance,"checks":checks,"failures":failures,"engine_errors":logger.errors,"events":events,"ten_second_samples":samples,"route":route,"water_samples":water_samples,"actual_gravity_impulses":actual_impulses,"status":_status(),"preservation":preservation,"fresh_reader":final_reader,"story_receipts":session.story.state.get("receipts",{}),"stats":session.stats,"pilot":pilot.report() if pilot!=null and is_instance_valid(pilot.body) else {},"scope":"Exported MAIN natural twenty-seven-to-thirty-one continuation only. Original M travel/spawn, continuous Flight/Pilot, south clinic opening, manual diagnosis G, normal 2/Tab/F actual gravity-valve impulse, actual clean transfer/cutoff/lift/access stability, manual confirmation G, original Store/SaveGate/fresh reader and native audio quit. No actor/valve/water/HP/clock/collision/flags/progress fixtures or manual simulation advancement. Earlier legitimate partial water history is explicitly inherited, never credited as this run's new operation. Distribution 31-to-34 is outside this four-goal scope. No whole campaign, fun, LAN, controller or performance acceptance."}
	report.merge(SourceBinding.audit(_source_binding))
	report["native_exit"]={"requested":true,"through":"session._quit","observed_scene_exit":false,"watchdog_failed":false}
	report_cache=_plain(report)
	var written: bool = _flush_report()
	print("NORMAL_CLINIC_RESULT "+JSON.stringify({"complete":complete,"requested_stage_stopped":stage_stopped,"written":written,"reason":reason,"phase":phase,"seconds":_elapsed(),"failures":failures,"engine_errors":logger.errors}))
	native_exit_requested=true
	_native_exit_watchdog.call_deferred()
	session._quit()

