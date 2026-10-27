extends Node
const SourceBinding = preload("res://scripts/v3/qa/twin_source_binding.gd")
static var _source_binding: Dictionary = {}
## AUTHORING ONLY: same natural I2Boss42 -> F2 investigation46, no Boss.
## Unbound source refuses preflight/run before any profile is opened.
const Pilot = preload("res://scripts/v3/qa/twin_normal_flight_pilot.gd")
const Store = preload("res://scripts/v3/core/twin_world_store.gd")
const Director = preload("res://scripts/v3/gameplay/actions/twin_action_director.gd")
const Catalog = preload("res://scripts/v3/campaign/twin_campaign_catalog.gd")
const I2Results = preload("res://scripts/v3/gameplay/twin_i2_result_ledger.gd")
const AbilityRules = preload("res://scripts/v3/gameplay/twin_ability_rules.gd")
static var SOURCE_PROFILE := "qa_normal_campaign_20261021_012725_b90f8a6f"
static var SOURCE_REPORT_SHA256 := "8a2e036263902d7298e2437a49936b4f629b15c000527d7e4fe57c608ced41b2"
static var FORTYTWO_DIGEST := "4f6c3eeb673cd61239c6ddc6365af60144c3ced07e8bacddcd6d3d4b6ed383c3"
const SOURCE_GOALS := ["I1:rescue:brief","I1:rescue:channel","I1:rescue:contact","I1:rescue:evacuate","I1:evidence:trace","I1:evidence:engineer","I1:evidence:ledger","I1:evidence:echo","F1:needs:listen","F1:needs:nursery","F1:needs:route","F1:repair:plan","F1:repair:light","F1:repair:grow","F1:repair:confirm","I1:whale:brief","I1:whale:engage","I1:whale:disable","I1:whale:record","F1:crown:brief","F1:crown:engage","F1:crown:disable","F1:crown:restore","I1:underdeck:read","I1:underdeck:enter","I1:underdeck:release","I1:underdeck:traverse","I2:clinic_supply:diagnose","I2:clinic_supply:connect","I2:clinic_supply:stabilize","I2:clinic_supply:confirm","I2:distribution_audit:expose","I2:distribution_audit:trace","I2:distribution_audit:share_access","I2:canal_service:brief","I2:canal_service:exchange","I2:canal_service:service","I2:canal_service:order","I2:twin_pump_guardian:plan","I2:twin_pump_guardian:engage","I2:twin_pump_guardian:stop","I2:twin_pump_guardian:decision"]
const EXPECTED := ["I1:rescue:brief","I1:rescue:channel","I1:rescue:contact","I1:rescue:evacuate","I1:evidence:trace","I1:evidence:engineer","I1:evidence:ledger","I1:evidence:echo","F1:needs:listen","F1:needs:nursery","F1:needs:route","F1:repair:plan","F1:repair:light","F1:repair:grow","F1:repair:confirm","I1:whale:brief","I1:whale:engage","I1:whale:disable","I1:whale:record","F1:crown:brief","F1:crown:engage","F1:crown:disable","F1:crown:restore","I1:underdeck:read","I1:underdeck:enter","I1:underdeck:release","I1:underdeck:traverse","I2:clinic_supply:diagnose","I2:clinic_supply:connect","I2:clinic_supply:stabilize","I2:clinic_supply:confirm","I2:distribution_audit:expose","I2:distribution_audit:trace","I2:distribution_audit:share_access","I2:canal_service:brief","I2:canal_service:exchange","I2:canal_service:service","I2:canal_service:order","I2:twin_pump_guardian:plan","I2:twin_pump_guardian:engage","I2:twin_pump_guardian:stop","I2:twin_pump_guardian:decision","F2:mirror_evidence:records","F2:mirror_evidence:archive","F2:mirror_evidence:light","F2:mirror_evidence:decision"]
const RECORDS := "F2:mirror_evidence:records"
const ARCHIVE := "F2:mirror_evidence:archive"
const LIGHT := "F2:mirror_evidence:light"
const DECISION := "F2:mirror_evidence:decision"
const CHOICE := "F2:chapter_choice"
const CHOICE_OPTION := "publish_context"
const STAGES := ["records","archive","light","complete"]
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
var gui_actions: Array = []
var mirror_observations: Array = []
var route: Dictionary = {}
var report_cache: Dictionary = {}
var native_exit_requested := false

static func _bound() -> bool:
	return SOURCE_REPORT_SHA256.length()==64 and FORTYTWO_DIGEST.length()==64

static func preflight(args: PackedStringArray) -> Dictionary:
	_source_binding = {}
	var bound: Dictionary = SourceBinding.prepare(args,"normal-f2",SOURCE_GOALS,EXPECTED)
	if not bound.get("ok",false): return {"ok":false,"code":bound.get("code","source_binding_rejected"),"config":{}}
	_source_binding = bound.binding
	args = bound.args
	SOURCE_PROFILE = str(_source_binding.constants.get("SOURCE_PROFILE",SOURCE_PROFILE))
	SOURCE_REPORT_SHA256 = str(_source_binding.constants.get("SOURCE_REPORT_SHA256",SOURCE_REPORT_SHA256))
	FORTYTWO_DIGEST = str(_source_binding.constants.get("FORTYTWO_DIGEST",FORTYTWO_DIGEST))
	if not _bound(): return {"ok":false,"code":"root_must_bind_actual_I2Boss42_report_and_receipts","config":{}}
	var values: Dictionary = {}
	for argument: String in args:
		var key := ""
		var value := ""
		if argument=="--qa-normal-f2":
			key="enabled"
			value="true"
		else:
			for pair: Array in [["--qa-profile=","profile"],["--qa-normal-output=","output"],["--qa-normal-seconds=","seconds"],["--qa-f2-stop-after=","stage"]]:
				if argument.begins_with(str(pair[0])):
					key=str(pair[1])
					value=argument.trim_prefix(str(pair[0]))
					break
		if key.is_empty() or value.is_empty() or values.has(key): return {"ok":false,"code":"unknown_empty_or_duplicate_f2_cli","config":{}}
		values[key]=value
	for key: String in ["enabled","profile","output","seconds"]:
		if not values.has(key): return {"ok":false,"code":"four_f2_arguments_required","config":{}}
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
	return {"ok":true,"code":"natural_I2Boss42_prefix_verified","config":{"profile":SOURCE_PROFILE,"output":selected_output,"max_seconds":seconds.to_int(),"stop_after":stage,"source_profile_id":saved.profile_id,"source_lineage_id":saved.lineage_id,"source_receipts_sha256":FORTYTWO_DIGEST}}

static func _source_check(saved: Dictionary) -> Dictionary:
	if not SourceBinding.same_identity(_source_binding,saved): return {"ok":false,"code":"source_binding_identity_changed"}
	if not _bound(): return {"ok":false,"code":"actual_I2Boss42_source_not_bound"}
	var world: Variant=saved.get("world")
	if not world is Dictionary or world.get("region_id") not in ["I2","F2"] or world.get("branch_id")!="main": return {"ok":false,"code":"same_natural_I2_or_F2_main_branch_required"}
	if not world.get("actions") is Dictionary or not world.actions.get("opening") is Dictionary: return {"ok":false,"code":"source_story_schema"}
	var state: Dictionary=world.actions.opening
	var completed: Variant=state.get("completed")
	if not completed is Array or completed.size()<42 or completed.size()>46 or completed!=EXPECTED.slice(0,completed.size()) or world.get("completed_objectives")!=completed: return {"ok":false,"code":"only_exact_natural_42_to_46_prefix_accepted"}
	if not state.get("receipts") is Dictionary or state.receipts.size()!=completed.size() or _receipts_digest(state,SOURCE_GOALS)!=FORTYTWO_DIGEST: return {"ok":false,"code":"actual_original_42_receipts_changed"}
	var director=Director.new()
	var definitions: Dictionary=director.load_definitions(Director.DEFAULT_PATH,Catalog.extension_paths())
	if not definitions.get("ok",false) or not director.validate_state(state).get("ok",false): return {"ok":false,"code":"original_Director_replay_rejected"}
	var discoveries: Variant=saved.get("personal",{}).get("discoveries")
	if not discoveries is Array: return {"ok":false,"code":"original_personal_discoveries_required"}
	var valid: Dictionary=I2Results.validate_world(world,discoveries)
	if not valid.get("ok",false): return {"ok":false,"code":"original_I2_physical_boundary:"+str(valid.get("error",""))}
	for flag: String in ["I2:canal_service_ready","campaign_boss:I2","I2:chapter_decision_saved","I2:region_route_open"]:
		if not world.get("flags",{}).get(flag,false): return {"ok":false,"code":"actual_original_I2_Boss_action_required:"+flag}
	for finding: String in ["boss:I2:twin_pump_guardian","I2:operation_record","I2:canal_calibration","I2:pump_priority_order"]:
		if discoveries.count(finding)!=1: return {"ok":false,"code":"original_unique_source_findings_required:"+finding}
	if "F2:mirrorwing_warden:plan" in completed or world.get("flags",{}).get("campaign_boss:F2",false): return {"ok":false,"code":"F2_Boss_outside_investigation_scope"}
	if DECISION in completed and state.get("choices",{}).get(DECISION)!=CHOICE_OPTION: return {"ok":false,"code":"existing_other_F2_choice_is_preserved_not_rewritten"}
	return {"ok":true,"code":"legal_natural_F2_investigation_prefix","source_receipts_sha256":FORTYTWO_DIGEST,"completed":completed.duplicate()}

func run(owner_session: Node,options: Dictionary={}) -> Dictionary:
	if not _bound(): return {"ok":false,"code":"actual_I2Boss42_source_not_bound"}
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
	return {"ok":true,"code":"observing_natural_F2_investigation","stop_after":stop_after}

func _execute() -> void:
	if not _check(session.profile_ready and not session.active and not OS.has_feature("editor"),"actual exported MAIN before ordinary same-profile menu continuation"): _stop("exported_normal_menu_required"); return
	last_completed=initial.world.actions.opening.completed.duplicate()
	session._ui_action("solo",{"frame":0})
	await _next()
	if not _healthy() or not _check(_receipts_digest(session.story.state,SOURCE_GOALS)==initial_digest,"normal menu retains every actual forty-two source receipt",_status()): _stop("ordinary_source_resume_failed"); return
	if not await _dismiss_radio(): _stop("radio_not_closed"); return
	if session.region_id=="I2":
		_phase("ordinary_M_travel_from_I2_to_F2")
		if not _check(session._can_travel_to("F2"),"original completed I2 action permits normal F2 travel"): _stop("ordinary_F2_travel_locked"); return
		_press_key(KEY_M)
		await _next()
		if not _check(session.interface.travel.visible,"ordinary M opens original I2 two-destination travel panel"): _stop("ordinary_travel_panel_unavailable"); return
		session._ui_action("travel_to",{"region_id":"F2"})
		var deadline: float=minf(max_seconds-10.0,_elapsed()+35.0)
		while _live() and session.region_id!="F2" and _elapsed()<deadline: await _next()
	if not _check(_live() and session.region_id=="F2" and session.campaign.supported() and session.campaign.mechanisms!=null,"normal F2 World/Arena/mechanisms load through original travel",_status()): _stop("normal_F2_world_unavailable"); return
	if not await _dismiss_radio(): _stop("arrival_radio_not_closed"); return
	_bind_pilot()
	route=_route_definition()
	if not _check(not route.is_empty(),"route derives marker and mirror positions from original loaded World",route): _stop("actual_F2_route_unavailable"); return
	if not _completed(RECORDS):
		if not await _read_records(): _stop("two_actual_readings_unproven"); return
	else: _event("inherited_original_two_record_receipt",{"receipt":_receipt_for(RECORDS),"proof":_mechanisms_debug()})
	if _stage("records"): return
	if not await _dismiss_radio(): _stop("records_radio_not_closed"); return
	if not _completed(ARCHIVE):
		if not await _navigate([Vector3(_body().global_position.x,16,_body().global_position.z),route.archive_high,route.archive],"archive_platform"): _stop("archive_route_unproven"); return
		if not await _contact("npc:shuyao",ARCHIVE): _stop("original_archive_talk_unproven"); return
	else: _event("inherited_original_archive_receipt",{"receipt":_receipt_for(ARCHIVE)})
	if _stage("archive"): return
	if not await _dismiss_radio(): _stop("archive_radio_not_closed"); return
	if not _completed(LIGHT):
		if not await _reflect_actual_light(): _stop("actual_reflected_light_unproven"); return
	else: _event("inherited_original_reflection_receipt",{"receipt":_receipt_for(LIGHT),"proof":_mechanisms_debug()})
	if _stage("light"): return
	if not await _dismiss_radio(): _stop("light_radio_not_closed"); return
	if not _completed(DECISION):
		if not await _navigate([Vector3(_body().global_position.x,16,_body().global_position.z),route.choice_high,route.choice],"choice_platform"): _stop("choice_route_unproven"); return
		if not await _choose_actual_panel(): _stop("actual_cost_panels_or_original_choice_transaction_unproven"); return
	else: _event("inherited_original_choice_receipt",{"receipt":_receipt_for(DECISION),"note":"Legitimate previous UI reading/choice is retained, not re-enacted."})
	if not _check(_completed(DECISION) and session.story.state.completed==EXPECTED and _receipts_digest(session.story.state,SOURCE_GOALS)==initial_digest and not session.boss_active and not session.campaign.active(),"four actual investigation goals extend intact source; no F2 Boss begins",_status()): _stop("F2_final_prefix_or_scope_unproven"); return
	_stage("complete")

func _route_definition() -> Dictionary:
	for marker: String in ["F2:record_low","F2:record_high","npc:shuyao","F2:choice_terminal"]:
		if not session.story.markers.has(marker): return {}
	for target: String in ["F2:clock_source","F2:clock_mirror","F2:clock_receiver"]:
		if not session.entities.has(target) or not session.world.objects.has(target): return {}
	var low: Vector3=session.story._point(session.story.markers["F2:record_low"])
	var high: Vector3=session.story._point(session.story.markers["F2:record_high"])
	var archive: Vector3=session.story._point(session.story.markers["npc:shuyao"])
	var terminal: Vector3=session.story._point(session.story.markers["F2:choice_terminal"])
	var mirror: Vector3=_target_position("F2:clock_mirror")
	return {"low":low+Vector3.UP*.1,"low_high":Vector3(low.x,16,low.z),
		"high_high":Vector3(high.x,16,high.z),"high":high+Vector3.UP*.1,
		"archive_high":Vector3(archive.x,16,archive.z),"archive":archive+Vector3.UP*.1,
		"mirror_high":Vector3(mirror.x+3.5,16,mirror.z+2),"mirror":mirror+Vector3(3.5,1.8,2),
		"choice_high":Vector3(terminal.x,16,terminal.z),"choice":terminal+Vector3.UP*.1,
		"note":"Unflown candidate. Full aircraft AABB and original Pilot swept flight are mandatory. No waypoints set body pose."}

func _read_records() -> bool:
	var state: Dictionary=session.campaign.mechanisms.persistent_state()
	if not state.get("readings",{}).has("F2:record_low"):
		if not await _navigate([route.low],"low_record"): return false
		if not await _read_marker("F2:record_low"): return false
	else: _event("inherited_low_manual_reading",{"reading":state.readings["F2:record_low"]})
	if not await _dismiss_radio(): return false
	state=session.campaign.mechanisms.persistent_state()
	if not state.get("readings",{}).has("F2:record_high"):
		if not await _navigate([Vector3(_body().global_position.x,16,_body().global_position.z),route.high_high,route.high],"high_record"): return false
		if not await _read_marker("F2:record_high"): return false
	else: _event("inherited_high_manual_reading",{"reading":state.readings["F2:record_high"]})
	if not await _wait_completed(RECORDS,8.0): return false
	var proof: Dictionary=session.campaign.mechanisms.persistent_state()
	return _check(proof.readings.has("F2:record_low") and proof.readings.has("F2:record_high") and proof.facts.get("F2:paired_records")=="both_read","both actual near/LOS G readings underlie the original paired-record fact",proof)

func _read_marker(target: String) -> bool:
	if not await _dismiss_radio(): return false
	_phase("normal_manual_G:"+target)
	var deadline: float=minf(max_seconds-10.0,_elapsed()+8.0)
	var next_press := 0.0
	while _healthy() and not session.campaign.mechanisms.persistent_state().get("readings",{}).has(target) and _elapsed()<deadline:
		if _elapsed()>=next_press:
			if not _check(session.story.nearest(_body().global_position)==target,"normal nearest G resolves actual record "+target,_status()): return false
			_record_g(target)
			next_press=_elapsed()+.6
		await _next()
	return _check(session.campaign.mechanisms.persistent_state().get("readings",{}).has(target),"original Store records explicit near/LOS reading "+target,_mechanisms_debug())

func _reflect_actual_light() -> bool:
	if not await _navigate([Vector3(_body().global_position.x,16,_body().global_position.z),route.mirror_high,route.mirror],"east_of_mirror_actual_ray_vantage"): return false
	_phase("normal_4_Tab_F_real_mirror")
	var before: Dictionary=_mechanisms_debug()
	mirror_observations.append(_plain({"kind":"before","state":before,"seconds":_elapsed()}))
	if session.campaign.mechanisms.fact("F2:clock_light_path").is_empty():
		var angle: float=float(session.entities["F2:clock_mirror"].get("angle",0))
		if absf(wrapf(angle-deg_to_rad(45),-PI,PI))>.001:
			if not _check(absf(wrapf(angle-deg_to_rad(15),-PI,PI))<.001,"ordinary mirror has initial 15-degree setting before the single 30-degree light operation",before): return false
			if not await _cast("F2:clock_mirror","light",KEY_4): return false
	# Fact remains the original physical ray sampler; QA never advances it.
	if not await _wait_completed(LIGHT,8.0): return false
	var proof: Dictionary=session.campaign.mechanisms.persistent_state()
	var view: Dictionary=session.campaign.mechanisms.view_state()
	var actual: Node3D=session.world.objects["F2:clock_mirror"]
	mirror_observations.append(_plain({"kind":"after","state":_mechanisms_debug(),"seconds":_elapsed(),"receipt":_receipt_for(LIGHT)}))
	return _check(view.get("beam_valid",false) and view.get("beam_segments",[]).size()==2 and proof.histories.has("F2:clock_light_path") and proof.facts.get("F2:clock_light_path")=="manual_mirror" and is_equal_approx(actual.rotation.y,float(session.entities["F2:clock_mirror"].angle)),"actual synchronized mirror pose and two first-hit segments produce original manual_mirror fact",{"proof":proof,"view":view,"native_rotation":actual.rotation})

func _choose_actual_panel() -> bool:
	if not await _dismiss_radio(): return false
	_phase("original_G_cost_panel_checkboxes_and_explicit_publish_context")
	if not _check(session.story.nearest(_body().global_position)=="F2:choice_terminal","normal G resolves choice terminal rather than nearby archive NPC",_status()): return false
	var spec: Dictionary=session.chapter_choices.specification(CHOICE)
	if not _check(spec.get("options",[]).size()==2,"original F2 offer has exactly two readable options",spec): return false
	_record_g("F2:choice_terminal")
	await _next()
	var panel: Variant=session.interface.chapter_choice
	if not _check(panel.visible and panel._target==CHOICE and not panel._review_only,"ordinary G opens the actual decision panel"): return false
	var boxes: Array[CheckBox]=[]
	var panel_text: Array[String]=[]
	for child: Node in panel._content.get_children():
		if child is CheckBox: boxes.append(child)
		elif child is Label: panel_text.append(child.text)
	if not _check(boxes.size()==2 and panel._buttons.size()==2,"two actual CheckBoxes and two original explicit choice Buttons exist",panel_text): return false
	for index: int in range(2):
		var option: Dictionary=spec.options[index]
		var block: String="收益："+str(option.benefit)+"\n负担："+str(option.cost)
		if not _check(not str(option.benefit).is_empty() and not str(option.cost).is_empty() and block in panel_text,"actual visible benefit/cost text precedes acknowledgement: "+str(option.id),panel_text): return false
		var before: bool=boxes[index].button_pressed
		# Native focused ui_accept toggles this original Control and read_requested
		# path. No acknowledgement or reducer is called directly.
		if not before and not await _ui_accept(boxes[index]): return false
		await _next()
		var identity: String=str(session.identities.get(1,""))
		var read: Array=session.chapter_choices.readings.get(CHOICE,{}).get(identity,[])
		gui_actions.append({"kind":"actual_CheckBox","input":"focused ui_accept","option":str(option.id),"was_checked":before,"is_checked":boxes[index].button_pressed,"host_acknowledged":str(option.id) in read,"visible_benefit_cost":block,"seconds":_elapsed()})
		if not _check(boxes[index].button_pressed and str(option.id) in read,"real UI checkbox reaches original host identity/read commit: "+str(option.id),gui_actions[-1]): return false
	if not _check(session.chapter_choices.has_read_all(1,CHOICE),"original host confirms both read options, not automatic panel-open reading"): return false
	var selected := -1
	for index: int in range(spec.options.size()):
		if str(spec.options[index].id)==CHOICE_OPTION: selected=index
	if not _check(selected>=0 and selected<panel._buttons.size(),"default publish_context is an actual offered UI Button"): return false
	var button: Button=panel._buttons[selected]
	if not _check(not button.disabled and button.text=="提出："+str(spec.options[selected].label),"actual UI enables explicit proposal only after both acknowledgements",{"text":button.text,"disabled":button.disabled}): return false
	var branches_before: Array=session.store.snapshot().branches.keys()
	# Activate the original visible Button through focused input. The UI path
	# prepares the original branch/proposal/Consensus and original Story commit.
	if not await _ui_accept(button): return false
	gui_actions.append({"kind":"actual_Button_pressed","input":"focused ui_accept","option":CHOICE_OPTION,"text":button.text,"seconds":_elapsed()})
	if not await _wait_completed(DECISION,12.0): return false
	var saved: Dictionary=session.store.snapshot()
	var added: Array=[]
	for id: Variant in saved.branches:
		if id not in branches_before and str(id).begins_with("before-chapter-"): added.append(str(id))
	return _check(added.size()==1 and session.story.state.get("choices",{}).get(DECISION)==CHOICE_OPTION and session.consensus.current_proposal().is_empty(),"original explicit UI proposal creates exactly one decision-before branch and commits publish_context",{"created_branches":added,"receipt":_receipt_for(DECISION),"readings":session.chapter_choices.readings})

func _wait_completed(objective: String, seconds: float) -> bool:
	var deadline: float=minf(max_seconds-10.0,_elapsed()+seconds)
	while _healthy() and not _completed(objective) and _elapsed()<deadline: await _next()
	return _check(_completed(objective),"original Story/Store completes "+objective,{"status":_status(),"receipt":_receipt_for(objective)})

func _mechanisms_debug() -> Dictionary:
	if not is_instance_valid(session) or session.region_id!="F2" or session.campaign.mechanisms==null: return {}
	var result: Dictionary={"state":session.campaign.mechanisms.persistent_state(),"view":session.campaign.mechanisms.view_state()}
	for id: String in ["F2:clock_source","F2:clock_mirror","F2:clock_receiver"]:
		if session.entities.has(id): result[id]=session.entities[id].duplicate(true)
		if session.world.objects.has(id): result[id+":native_rotation"]=session.world.objects[id].rotation
	return result

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
	return path.is_absolute_path() and "://" not in path and ".." not in path and "\n" not in path and "\r" not in path and path.get_file().begins_with("normal-f2-") and path.get_extension() == "json" and not FileAccess.file_exists(path) and not DirAccess.dir_exists_absolute(path)


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
		_stop("normal_f2_complete" if value=="complete" else "requested_stage_pause")
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
	var complete: bool = reason=="normal_f2_complete" and failures.is_empty() and logger.errors.is_empty() and preserved and saved_now and matches_live and saved.world.actions.opening.completed==EXPECTED
	var stage_stopped: bool = reason=="requested_stage_pause" and stop_after in reached_stages and failures.is_empty() and logger.errors.is_empty() and preserved and saved_now and matches_live and preservation.common_paused
	if complete:
		for discovery: String in ["F2:contradictory_records","F2:aligned_timeline"]:
			_check(saved.personal.discoveries.count(discovery)==1,"original investigation discovery is unique and durable: "+discovery,saved.personal.discoveries)
		_check(saved.world.flags.get("F2:clock_path_restored",false) and saved.world.flags.get("F2:chapter_decision_saved",false),"original reflection and explicit chapter-choice flags remain durable")
		_check(saved.world.actions.opening.choices.get(DECISION)==CHOICE_OPTION and not saved.world.flags.get("campaign_boss:F2",false),"publish_context is durable and no F2 Boss victory is claimed")
		var proof: Dictionary=saved.world.environment.get("campaign_F2",{}).get("mechanisms",{})
		_check(proof.get("readings",{}).has("F2:record_low") and proof.get("readings",{}).has("F2:record_high") and proof.get("histories",{}).has("F2:clock_light_path"),"both original manual readings and actual reflected-light history survive fresh reader",proof)
		var identity: String=str(session.identities.get(1,""))
		var read: Array=saved.world.environment.get("campaign_choices",{}).get("readings",{}).get(CHOICE,{}).get(identity,[])
		_check(read.size()==2 and "publish_raw" in read and CHOICE_OPTION in read,"both original UI option acknowledgements are durable for the actual stable identity",read)
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
	report_cache["f2_segment_complete"]=false
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
	print("NORMAL_F2_EXIT_WATCHDOG_FAIL "+JSON.stringify(report_cache.native_exit))
	# Do not use tree.quit/OS.kill as a fallback around a rejected Store gate.
	# The runner's already bounded private Job remains the external hard limit.


func _exit_tree() -> void:
	if not native_exit_requested or report_cache.is_empty(): return
	report_cache["native_exit"]["observed_scene_exit"]=true
	if is_instance_valid(session):
		report_cache["native_exit"]["audio"]=_plain(session.last_audio_shutdown_result)
		if not session.last_audio_shutdown_result.get("ready",false):
			report_cache["complete"]=false
			report_cache["f2_segment_complete"]=false
			report_cache["requested_stage_stopped"]=false
			report_cache["failures"].append("Original final-exit audio drain did not become ready.")
	report_cache["engine_errors"]=_plain(logger.errors)
	if not logger.errors.is_empty():
		report_cache["complete"]=false
		report_cache["f2_segment_complete"]=false
		report_cache["requested_stage_stopped"]=false
	_flush_report()


func _next() -> void:
	await get_tree().physics_frame
	await get_tree().process_frame
	if finished or not is_instance_valid(session): return
	var completed: Array = session.story.state.get("completed",[])
	if completed!=last_completed:
		if completed!=EXPECTED.slice(0,completed.size()) or completed.size()>46 or _receipts_digest(session.story.state,SOURCE_GOALS)!=initial_digest:
			_check(false,"normal observation retains exact investigation-only prefix and all original 42 receipts",completed)
			_stop("unexpected_Story_prefix_or_source_changed")
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
	print("NORMAL_F2_EVENT "+JSON.stringify(row))


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
		print("NORMAL_F2_PROGRESS "+JSON.stringify(_plain(row)))


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



func _write_report(reason: String, complete: bool, stage_stopped: bool) -> void:
	finished=true
	running=false
	var report: Dictionary = {"complete":complete,"f2_segment_complete":complete,"requested_stage_stopped":stage_stopped,"requested_stage":stop_after,"reached_stages":reached_stages,"stop_reason":reason,"phase":phase,"seconds":_elapsed(),"max_seconds":max_seconds,"profile":SOURCE_PROFILE,"user_dir":OS.get_user_data_dir(),"executable":OS.get_executable_path(),"exported_application":not OS.has_feature("editor"),"runtime_cwd":DirAccess.open(".").get_current_dir(),"source_generation":initial.get("generation"),"source_report_sha256":SOURCE_REPORT_SHA256,"source_receipts_sha256":initial_digest,"physics_frames":physics_frames,"actual_distance_m":actual_distance,"max_frame_distance_m_excluding_normal_travel":max_frame_distance,"checks":checks,"failures":failures,"engine_errors":logger.errors,"events":events,"ten_second_samples":samples,"route":route,"actual_abilities":actual_abilities,"actual_interactions":actual_interactions,"actual_cost_panel_actions":gui_actions,"actual_reflection_observations":mirror_observations,"status":_status(),"preservation":preservation,"fresh_reader":final_reader,"story_receipts":session.story.state.get("receipts",{}),"stats":session.stats,"pilot":pilot.report() if pilot!=null and is_instance_valid(pilot.body) else {},"scope":"Exported MAIN same-natural-profile 42-to-46 investigation only. Actual future I2Boss42 source must be bound first. Original menu/spawn/M travel, continuous native Flight/Pilot, original near/LOS G readings and NPC talk, normal 4/Tab/F mirror rotation, original two-segment physical reflection, two real cost-panel CheckBoxes and explicit publish_context Button through original branch/Consensus/Story transaction, original SaveGate/fresh reader and Session native audio quit. No F2 Boss plan/entry/battle, fixture pose/flags/proofs/HP/time/mechanism edit, manual simulation, profile clone/rollback or report-progress import. Inherited legitimate histories are recorded separately. Unflown route candidate; not whole-campaign, fun, LAN, controller or performance acceptance."}
	report.merge(SourceBinding.audit(_source_binding))
	report["native_exit"]={"requested":true,"through":"session._quit","observed_scene_exit":false,"watchdog_failed":false}
	report["initial_completed"]=initial.world.actions.opening.completed.duplicate()
	report_cache=_plain(report)
	var written: bool = _flush_report()
	print("NORMAL_F2_RESULT "+JSON.stringify({"complete":complete,"requested_stage_stopped":stage_stopped,"written":written,"reason":reason,"phase":phase,"seconds":_elapsed(),"failures":failures,"engine_errors":logger.errors}))
	native_exit_requested=true
	_native_exit_watchdog.call_deferred()
	session._quit()



func _ui_accept(button: BaseButton) -> bool:
	await _next() # allow normal modal focus update after a button becomes enabled
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
	gui_actions.append({"seconds":_elapsed(),"path":str(button.get_path()),"text":button.text,"input":"focused GUI ui_accept press/release"})
	return _healthy()

