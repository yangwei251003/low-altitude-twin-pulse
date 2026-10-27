extends Node
## Explicit packaged observer. Root mounts AFTER preflight and ordinary MAIN.
const SUITE := "f2-patrol-lan"
const PROTOCOL := 25
const CONTRACT := 1
const Store = preload("res://scripts/v3/core/twin_world_store.gd")
const Hangar = preload("res://scripts/v3/gameplay/twin_hangar.gd")
const Catalog = preload("res://scripts/v2/catalog.gd")
const Build = preload("res://scripts/v3/network/twin_build_contract.gd")
const Regions = preload("res://scripts/v3/world/twin_region_catalog.gd")
const FIELDS := {"--qa-suite":"suite","--qa-profile":"profile","--qa-lan-patrol-role":"role","--qa-lan-patrol-run":"run_id","--qa-lan-patrol-evidence":"evidence"}

class ErrorLogger extends Logger:
	var errors: Array = []
	var mutex := Mutex.new()
	func _log_error(function: String,file: String,line: int,code: String,rationale: String,_notify: bool,kind: int,_trace: Array[ScriptBacktrace]) -> void:
		if kind == Logger.ERROR_TYPE_WARNING: return
		mutex.lock()
		errors.append({"function":function,"file":file,"line":line,"code":code,"rationale":rationale})
		mutex.unlock()

const Layout = preload("res://scripts/v3/campaign/twin_campaign_layout.gd")
const ID := "F2:patrol_01"

var session: Node
var patrol
var config: Dictionary={}
var logger := ErrorLogger.new()
var began := 0
var last_write := 0
var last_good: Dictionary={}
var lease_diagnostic: Dictionary={}
var started := false
var queued := false
var finishing := false
var host_ready := false
var ack := 0
var result: Dictionary={}
var commands: Array=[]
var errors: Array=[]
var fixtures: Array=[]
var guest_setup: Dictionary={}
var baseline_discoveries: Array=[]
var baseline_story: Dictionary={}
var holding := false
var stop_fire_frame := -1
var hold_receipt: Dictionary={}
var release_receipt: Dictionary={}
var staged_guest := false
var first_warning: Dictionary={}
var first_bullet: Dictionary={}
var reliable_events: Array=[]
var damage_rows: Array=[]
var hit_receipts: Array=[]
var first_charge_frame := -1
var observed_epoch := -1
var network_event_count := 0
var mesh_evidence: Dictionary={}
var previous_hp := 32.0
var observed_event_serial := 0
var old_view: Dictionary={}
var last_packet: Dictionary={}
var old_packet: Dictionary={}
var mesh_checks := 0
var replay_count := 0
var atom_probe: Dictionary={}
var warning_pause: Dictionary={}
var warning_pause_pending := false
var warning_pause_deadline_usec := 0
var travel_result: Dictionary={}
var store_result: Dictionary={}

static func _normalized(path: String) -> String:
	return path.replace("\\","/").simplify_path().trim_suffix("/").to_lower()

static func _json(path: String) -> Dictionary:
	var file := FileAccess.open(path,FileAccess.READ)
	if file == null or file.get_length() > 1048576: return {}
	var value: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	return value if value is Dictionary else {}

static func _lease(cfg: Dictionary) -> Dictionary:
	var value := _json(str(cfg.evidence).path_join("controller.json"))
	if value.is_empty(): return {"ok":false,"transient":true,"code":"controller_read_pending"}
	for key: String in ["suite","run_id"]:
		if value.get(key) != cfg[key]: return {"ok":false,"transient":false,"code":"controller_identity:"+key}
	if value.get("port") != 26742 or value.get("lock_held") != true: return {"ok":false,"transient":false,"code":"controller_lock_required"}
	var stamp: Variant = value.get("heartbeat_unix")
	if not (stamp is int or stamp is float) or not is_finite(float(stamp)): return {"ok":false,"transient":false,"code":"controller_stamp_invalid"}
	var age: float = Time.get_unix_time_from_system()-float(stamp)
	if absf(age) > 8.0: return {"ok":false,"transient":false,"code":"controller_stamp_expired","age":age}
	return {"ok":true,"transient":false,"controller":value,"age":age}

static func preflight(args: PackedStringArray) -> Dictionary:
	if args != OS.get_cmdline_user_args() or OS.has_feature("editor") or not OS.is_debug_build(): return {"ok":false,"code":"actual_debug_EXE_arguments_required"}
	var cfg: Dictionary = {}
	for argument: String in args:
		var split: int = argument.find("=")
		var key: String = argument.substr(0,split) if split > 0 else ""
		if not FIELDS.has(key) or cfg.has(FIELDS[key]): return {"ok":false,"code":"unknown_or_duplicate_argument"}
		cfg[FIELDS[key]] = argument.substr(split+1)
	if cfg.size() != FIELDS.size() or cfg.get("suite") != SUITE or cfg.get("role") not in ["host","guest"]: return {"ok":false,"code":"suite_role_fields"}
	var regex := RegEx.new()
	regex.compile("^[0-9]{8}_[0-9]{6}_[0-9]{6}$")
	if regex.search(str(cfg.run_id)) == null: return {"ok":false,"code":"run_id_invalid"}
	var expected: String = "qa_lan_f2_patrol_"+str(cfg.role)+"_"+str(cfg.run_id)
	if cfg.profile != expected or cfg.profile != str(cfg.profile).validate_filename() or DirAccess.dir_exists_absolute("user://profiles_v3/"+expected): return {"ok":false,"code":"fresh_private_profile_required"}
	var evidence: String = OS.get_executable_path().get_base_dir().path_join("artifacts/v3/network/f2-patrol").path_join(cfg.run_id)
	if not str(cfg.evidence).is_absolute_path() or ".." in str(cfg.evidence) or _normalized(cfg.evidence) != _normalized(evidence) or not DirAccess.dir_exists_absolute(evidence): return {"ok":false,"code":"dedicated_package_evidence_required"}
	var lease := _lease(cfg)
	if not lease.ok and not lease.transient: return lease
	return {"ok":true,"config":cfg}

func _guest_hangar() -> bool:
	var before: Dictionary = session.store.snapshot()
	var fixture := {"id":"qa-patrol-lan-ownership:"+str(config.run_id),"append":{"personal.discoveries":["boss:F2:mirrorwing_warden"]}}
	var saved: Dictionary = session.store.commit(fixture)
	if not saved.get("ok",false): _fail("ownership_fixture_failed"); return false
	var unlocked: Dictionary = session.store.snapshot()
	if unlocked.world != before.world or unlocked.profile_id != before.profile_id: _fail("ownership_fixture_changed_world_or_uuid"); return false
	session.interface.action_requested.emit("hangar",{})
	var panel = session.interface.hangar
	if not panel.visible or panel._active: _fail("native_hangar_not_editable"); return false
	var frame := -1
	for index: int in panel._frames.item_count:
		if panel._frames.get_item_metadata(index) == "tr01": frame = index
	if frame < 0: _fail("TR01_option_missing"); return false
	panel._frames.select(frame)
	panel._frames.item_selected.emit(frame)
	var desired := {"weapon":"burst_capacitor","tool":"scan_base","drive":"stock_drive","battery":"stock_battery","utility":"guard_base"}
	for slot: String in Catalog.SLOT_ORDER:
		var picker: OptionButton = panel._slots[slot]
		var index := -1
		for candidate: int in picker.item_count:
			if picker.get_item_metadata(candidate) == desired[slot] and not picker.is_item_disabled(candidate): index = candidate
		if index < 0 or picker.disabled: _fail("owned_compatible_option_missing:"+slot); return false
		picker.select(index)
		picker.item_selected.emit(index)
	var checked: Dictionary = Hangar.validate(unlocked,panel._draft)
	if not checked.get("ok",false) or panel._save.disabled: _fail("native_hangar_validation_failed"); return false
	panel._save.pressed.emit()
	var reader := Store.new(session.store.root_path)
	var opened: Dictionary = reader.load_profile()
	var current: Dictionary = session.store.snapshot()
	var launched: Dictionary = Hangar.launch_build(current)
	if not opened.get("ok",false) or reader.snapshot() != current or not launched.get("ok",false) or not Build.matches(launched.build,{"airframe_id":"tr01","slots":desired}) or current.world != before.world or current.profile_id != before.profile_id or current.personal.discoveries != unlocked.personal.discoveries or int(current.generation) != int(unlocked.generation)+1: _fail("native_hangar_Store_reader_mismatch"); return false
	guest_setup = {"fixture":fixture,"earned_campaign":false,"world_unchanged":true,"reader_equal":true,"uuid":current.profile_id,"hardware":Build.view(launched.build),"native_build":launched.build,"generation":current.generation,"ui_status":panel._status.text}
	session.interface.action_requested.emit("hangar_close",{})
	return true


func run(owner_session: Node,options: Dictionary) -> Dictionary:
	if session!=null or not is_inside_tree() or options.is_empty(): return {"ok":false,"code":"mount_once"}
	session=owner_session; config=options.duplicate(true)
	patrol=session.get("ambient_patrol")
	if patrol==null or not session.profile_ready or session.store.root_path!="user://profiles_v3/"+str(config.profile) or session.network.PROTOCOL!=PROTOCOL: return {"ok":false,"code":"promoted_protocol25_MAIN_required"}
	patrol.enabled=true # This fresh QA process only; production default remains false.
	process_priority=100; process_physics_priority=100
	began=Time.get_ticks_usec(); OS.add_logger(logger)
	session.network.event_received.connect(_watch_event)
	session.network.snapshot_received.connect(_watch_packet)
	return {"ok":true,"code":"mounted_actual_MAIN"}

func _process(_delta: float) -> void:
	if session==null or began==0 or finishing: return
	if Time.get_ticks_usec()-began>80000000: _fail("80_second_peer_bound"); _quit(); return
	var lease: Dictionary=_lease(config)
	lease_diagnostic=lease.duplicate(true)
	if lease.ok: last_good=lease.controller.duplicate(true)
	elif not lease.transient: _fail(str(lease.code)); _quit(); return
	elif last_good.is_empty():
		if Time.get_ticks_usec()-began>8000000: _fail("initial_controller_timeout"); _quit()
		return
	elif absf(Time.get_unix_time_from_system()-float(last_good.heartbeat_unix))>8.0: _fail("controller_expired"); _quit(); return
	if not started and not queued: queued=true; _boot.call_deferred()
	if Time.get_ticks_usec()-last_write<50000: return
	last_write=Time.get_ticks_usec()
	var command: Dictionary=_json(str(config.evidence).path_join(str(config.role)+"-command.json"))
	var serial: Variant=command.get("sequence",0)
	if command.get("run_id")==config.run_id and (serial is int or serial is float) and is_finite(float(serial)) and floor(float(serial))==float(serial) and int(serial)>ack and int(serial)<=1000:
		ack=int(serial)
		var verb: String=str(command.get("verb",""))
		result=_execute(verb)
		commands.append({"sequence":ack,"verb":verb,"result":result.duplicate(true),"physics_frame":Engine.get_physics_frames()})
		if not result.get("ok",false): _fail("command:"+verb+":"+str(result.get("code","rejected")))
		if verb=="shutdown": _write(); _quit(); return
	_write()

func _boot() -> void:
	# New-QA region localization only. No Director/facility/enemy result fixture.
	Regions._entries=Regions.entries()
	for item: Dictionary in Regions._entries:
		if item.id=="F2":
			var layout: Dictionary=Layout.definition("F2")
			item.playable=true; item.spawn=layout.spawn.duplicate(); item.bounds=layout.bounds.duplicate()
	var localized: Dictionary=session.store.commit({"id":"qa-patrol-F2-origin:"+str(config.run_id),"set":{"world.region_id":"F2"}})
	if not localized.get("ok",false): _fail("private_region_localization_failed"); _quit(); return
	session.world_cache=session.store.snapshot()
	if config.role=="guest" and not _guest_hangar(): _quit(); return
	var profile: Dictionary=session.store.snapshot()
	baseline_discoveries=profile.personal.discoveries.duplicate(true)
	baseline_story=profile.world.get("actions",{}).duplicate(true)
	session.inputs.test_enabled=true; _hold(false)
	session.interface.action_requested.emit("host" if config.role=="host" else "join",{"frame":session.interface.frames.selected,"address":"127.0.0.1"})
	if not session.active: _fail("ordinary_menu_start_failed"); _quit(); return
	started=true
	if config.role=="host":
		for unused in 3:
			if not await _frame(): return
		if session.region_id!="F2" or not is_instance_valid(patrol.scout): _fail("normal_F2_factory_missing_scout"); return
		if not await _stage_player(1,14.0): _fail("host_observation_pose_unavailable"); return
		host_ready=true
	_write()

func _execute(verb: String) -> Dictionary:
	match verb:
		"stage_guest":
			if config.role!="host" or _guest_peer()==0 or staged_guest: return {"ok":false,"code":"two_peers_once"}
			_stage_guest.call_deferred(); return {"ok":true,"code":"actual_player_pose_queued"}
		"lock":
			if config.role!="guest": return {"ok":false}
			session.network.send_action("lock",{"target_id":ID}); return {"ok":true}
		"hold":
			if config.role!="guest" or session.locks.get(session.network.local_id())!=ID: return {"ok":false,"code":"actual_lock_required"}
			hold_receipt={"physics_frame":Engine.get_physics_frames(),"input_sequence_before":session.network._sequence,"source":"ordinary_InputRouter_test_frame"}
			stop_fire_frame=Engine.get_physics_frames()+480; _hold(true); return {"ok":true,"code":"bounded_eight_second_ordinary_held_input"}
		"release": _release("controller"); return {"ok":true}
		"warning_pause":
			if config.role!="host" or _guest_peer()==0 or session.simulation_paused or not session.consensus.current_proposal().is_empty() or not warning_pause.is_empty(): return {"ok":false,"code":"fresh_two_peer_warning_boundary_required"}
			warning_pause={"pending":true}
			warning_pause_pending=true
			warning_pause_deadline_usec=Time.get_ticks_usec()+10000000 # Observer wall bound only.
			return {"ok":true,"code":"waiting_actual_new_warning_no_clock_edit"}
		"pause": session._request_pause(); return {"ok":true,"code":"original_Consensus_toggle"}
		"confirm":
			var proposal: Dictionary=session.choice_proposal
			if config.role!="guest" or proposal.get("kind")!="pause": return {"ok":false,"code":"received_proposal_required"}
			session.network.send_action("confirm",{"proposal_id":proposal.proposal_id,"world_revision":proposal.world_revision}); return {"ok":true}
		"replay":
			if config.role!="host" or old_view.is_empty() or _guest_peer()==0: return {"ok":false}
			# True ENet: replay an unchanged previously observed full view, then
			# duplicate the current full view. No fake HP/positions/outcomes.
			for view: Dictionary in [old_view,patrol.presentation(),old_view]:
				session.network.send_event(_guest_peer(),{"kind":patrol.View.KIND,"session_id":session.network.session_id,"region":"F2","state":view.duplicate(true)})
			replay_count+=1; return {"ok":true,"code":"original_reliable_authority_replay"}
		"to_i1": _travel.call_deferred("I1"); return {"ok":config.role=="host"}
		"back_f2": _travel.call_deferred("F2"); return {"ok":config.role=="host"}
		"old_epoch_atomic": return _probe_old_epoch()
		"store_check":
			if config.role=="host":
				_save_store.call_deferred(); return {"ok":true,"code":"original_SaveGate_queued"}
			return _store_check()
		"shutdown": return {"ok":true,"code":"ordinary_quit"}
	return {"ok":false,"code":"unknown_command"}

func _stage_guest() -> void:
	staged_guest=await _stage_player(_guest_peer(),10.0)
	if not staged_guest: _fail("guest_observation_pose_unavailable")
	_write()

func _stage_player(peer: int,radius: float) -> bool:
	if not session.players.has(peer) or not is_instance_valid(patrol.scout): return false
	var target: Vector3=patrol.scout.global_position
	var forward:=Vector3(-sin(patrol.scout.rotation.y),0,-cos(patrol.scout.rotation.y))
	for offset: float in [0.0,.35,-.35,.7,-.7]:
		var at: Vector3=target+forward.rotated(Vector3.UP,offset)*radius
		var body: FlightBodyV2=session.players[peer]
		var envelope:=body.get_node("Envelope") as CollisionShape3D
		var query:=PhysicsShapeQueryParameters3D.new()
		query.shape=envelope.shape; query.transform=Transform3D(Basis.IDENTITY,at)*envelope.transform
		query.collision_mask=1|2|4|8|32; query.exclude=[body.get_rid()]
		if not Regions.contains("F2",at) or not session.world.get_world_3d().direct_space_state.intersect_shape(query,1).is_empty(): continue
		var half:=Vector3(float(body.stats.width_m),float(body.stats.height_m),float(body.stats.length_m)).length()*.5
		if patrol._protected_point(at,Vector3.ONE*half) or not patrol.line_clear(at,target,body.get_rid(),patrol.scout.get_rid()): continue
		# Disclosed PLAYER-only setup pose, not a flown route or enemy fixture.
		body.freeze=true; body.global_transform=Transform3D(Basis.IDENTITY,at); body.force_update_transform()
		PhysicsServer3D.body_set_state(body.get_rid(),PhysicsServer3D.BODY_STATE_TRANSFORM,body.global_transform)
		body.linear_velocity=Vector3.ZERO; body.angular_velocity=Vector3.ZERO; body.hold_height=at.y
		fixtures.append({"kind":"initial_PLAYER_observation_pose_not_flown","peer":peer,"position":[at.x,at.y,at.z],"full_hull_clear":true,"actual_LOS":true,"not_protected":true})
		for unused in 2:
			if not await _frame(): return false
		return true
	return false

func _travel(id: String) -> void:
	if config.role!="host": _fail("host_only_QA_travel"); return
	travel_result={"region":id,"ok":session._load_region(id),"scope":"QA lifecycle load, not normal travel/unlock"}
	if not travel_result.ok: _fail("original_QA_region_factory_failed:"+id)
	_write()

func _physics_process(_delta: float) -> void:
	if not started or finishing: return
	if config.role=="guest":
		if holding and (Engine.get_physics_frames()>=stop_fire_frame or is_instance_valid(patrol.scout) and patrol.scout.dying): _release("authority_disabled_or_input_bound")
		return
	_observe_warning_pause()
	var view: Dictionary=patrol.presentation()
	if not view.is_empty() and old_view.is_empty() and int(view.serial)>0: old_view=view.duplicate(true)
	var current_peer: int=_guest_peer()
	if session.weapons._cycles.has(current_peer):
		var current_cycle: Dictionary=session.weapons._cycles[current_peer].cycle.snapshot()
		if float(current_cycle.charge_s)>0.0 and first_charge_frame<0: first_charge_frame=Engine.get_physics_frames()
	if int(patrol.epoch)!=observed_epoch:
		observed_epoch=int(patrol.epoch)
		if is_instance_valid(patrol.scout): previous_hp=float(patrol.scout.hp)
	if is_instance_valid(patrol.scout) and patrol.scout.hp!=previous_hp:
		var peer: int=_guest_peer()
		var cycle: Dictionary=session.weapons._cycles[peer].cycle.snapshot() if session.weapons._cycles.has(peer) else {}
		damage_rows.append({"before":previous_hp,"after":float(patrol.scout.hp),"damage_serial":int(patrol.scout.damage_state.serial),"physics_frame":Engine.get_physics_frames(),"cycle":cycle,"input_sequence":session.network.last_input.get(peer,-1),"command_fire":bool(session.players[peer].command.get("fire",false)) if session.players.has(peer) else false,"stats_shots":session.stats.shots,"epoch":patrol.epoch,"first_charge_frame":first_charge_frame,"charged_frames":Engine.get_physics_frames()-first_charge_frame+1})
		previous_hp=float(patrol.scout.hp)
	for row: Dictionary in patrol.events:
		if int(row.serial)<=observed_event_serial: continue
		observed_event_serial=int(row.serial)
		if row.kind=="warning_started" and first_warning.is_empty(): first_warning=row.duplicate(true)
		if row.kind=="enemy_shot" and first_bullet.is_empty(): first_bullet=row.duplicate(true)
		if row.kind=="hit" and row.detail.get("target")==ID: hit_receipts.append(row.duplicate(true))

func _observe_warning_pause() -> void:
	if not warning_pause_pending: return
	if Time.get_ticks_usec()>warning_pause_deadline_usec:
		warning_pause_pending=false
		warning_pause={"ok":false,"code":"actual_new_warning_not_observed_within_10s"}
		_fail("active_warning_pause_boundary_not_reproduced")
		return
	var before: Dictionary=patrol.presentation()
	# Missing an existing warning means wait for the next REAL one. No extension,
	# telegraph assignment, alternate tick or consensus roundtrip race is used.
	if before.is_empty() or not before.actor.warning.active or int(before.actor.warning.remaining_ms)<850 or patrol._ceasefire_reason()!="none": return
	var frame_before: int=Engine.get_physics_frames()
	var telegraph_before: float=float(patrol.scout.telegraph)
	var before_digest: String=_digest(before)
	session._request_pause() # Host send_action emits original propose synchronously.
	var after: Dictionary=patrol.presentation()
	var proposal: Dictionary=session.consensus.current_proposal()
	var reason_after: String=patrol._ceasefire_reason()
	var same_rank: bool=not after.is_empty() and int(before.epoch)==int(after.epoch) and int(before.serial)==int(after.serial)
	var same_warning: bool=not after.is_empty() and after.actor.warning.active and after.actor.warning.token==before.actor.warning.token
	var ok: bool=Engine.get_physics_frames()==frame_before and same_rank and same_warning and before_digest==_digest(after) and proposal.get("kind")=="pause" and proposal.get("participants",[]).size()==2 and reason_after=="vote" and float(patrol.scout.telegraph)==telegraph_before
	warning_pause_pending=false
	warning_pause={"ok":ok,"scope":"same synchronous Host proposal call before next ordinary physics tick", "physics_frame_before":frame_before,"physics_frame_after":Engine.get_physics_frames(),"epoch":before.epoch,"serial":before.serial,"before_digest":before_digest,"after_digest":_digest(after),"warning_before":before.actor.warning.duplicate(true),"warning_after":after.actor.warning.duplicate(true) if not after.is_empty() else {},"telegraph_before":telegraph_before,"telegraph_after":float(patrol.scout.telegraph),"policy_before":"none","policy_after":reason_after,"proposal":proposal.duplicate(true)}
	if not ok: _fail("active_warning_same_rank_changed_during_original_propose")
	_write()

func _watch_packet(packet: Dictionary) -> void:
	if config.get("role")!="guest" or not packet.get("ambient",{}) is Dictionary: return
	last_packet=packet.duplicate(true)
	if packet.get("region")=="F2" and not packet.ambient.is_empty() and old_packet.is_empty(): old_packet=packet.duplicate(true)

func _watch_event(event: Dictionary) -> void:
	if config.get("role")!="guest" or event.get("kind")!=patrol.View.KIND or not event.get("state") is Dictionary: return
	network_event_count+=1
	var view: Dictionary=event.state
	var current: Dictionary=patrol.presentation()
	var accepted: bool=patrol.View.valid(view) and not current.is_empty() and _digest(current)==_digest(view)
	if accepted:
		if view.actor.warning.active and first_warning.is_empty(): first_warning={"source":"actual_network.event_received","epoch":view.epoch,"serial":view.serial,"warning":view.actor.warning.duplicate(true)}
		if not view.bullets.is_empty() and first_bullet.is_empty(): first_bullet={"source":"actual_network.event_received","epoch":view.epoch,"serial":view.serial,"bullets":view.bullets.duplicate(true)}
		if patrol._remote_bullets.size()!=view.bullets.size(): _fail("Guest_mesh_count_mismatch")
		for row: Dictionary in view.bullets:
			var mesh: MeshInstance3D=patrol._remote_bullets.get(row.id)
			mesh_checks+=1
			if not is_instance_valid(mesh) or mesh.global_transform!=Transform3D(row.basis,row.position) or mesh.get_child_count()!=0: _fail("Guest_exact_mesh_pose_or_type_mismatch")
			if is_instance_valid(mesh): mesh_evidence={"id":row.id,"actual":mesh.global_transform,"expected":Transform3D(row.basis,row.position),"exact_equal":mesh.global_transform==Transform3D(row.basis,row.position),"type":"MeshInstance3D","children":mesh.get_child_count()}
	reliable_events.append({"epoch":view.get("epoch",-1),"serial":view.get("serial",-1),"accepted_current":accepted,"current_digest":_digest(current)})
	if reliable_events.size()>128: reliable_events.pop_front()

func _fingerprint() -> Dictionary:
	var roster: Dictionary={}
	for peer: int in session.players:
		var body: FlightBodyV2=session.players[peer]
		roster[peer]={"id":body.get_instance_id(),"rid":str(body.get_rid()),"pose":body.global_transform,"velocity":body.linear_velocity,"health":body.health}
	return {"region":session.region_id,"world_id":session.world.get_instance_id(),"space":str(session.world.get_world_3d().space),"received_sequence":session.received_sequence,"entities":_digest(session.entities),"ambient":_digest(patrol.presentation()),"roster":roster}

func _probe_old_epoch() -> Dictionary:
	if config.role!="guest" or session.region_id!="I1" or old_packet.is_empty(): return {"ok":false,"code":"real_captured_F2_and_current_I1_required"}
	var packet: Dictionary=old_packet.duplicate(true)
	var old_sequence: int=int(packet.sequence)
	packet.sequence=session.received_sequence+1 # NEGATIVE transport metadata only.
	var before: Dictionary=_fingerprint()
	var allowed: bool=patrol.can_receive(packet.ambient,str(packet.session_id),"F2")
	session._apply_snapshot(packet) # Original whole-packet boundary, synchronous.
	var after: Dictionary=_fingerprint()
	atom_probe={"ok":not allowed and before==after,"kind":"negative_transport_sequence_fixture_original_apply","source":"actual captured ENet F2 packet, enemy view unchanged","old_sequence":old_sequence,"probe_sequence":packet.sequence,"view_epoch":packet.ambient.epoch,"can_receive":allowed,"before":before,"after":after}
	return atom_probe

func _save_store() -> void:
	var callbacks: Array=[]
	store_result={"pending":true}
	var requested: Dictionary=session.request_environment_save(func(row: Dictionary): callbacks.append(row.duplicate(true)))
	if not requested.get("ok",false): _fail("original_SaveGate_request_failed:"+str(requested)); return
	var deadline: int=Time.get_ticks_usec()+5000000
	while callbacks.is_empty() and Time.get_ticks_usec()<deadline:
		if not await _frame(): return
	if callbacks.is_empty() or not callbacks[0].get("ok",false): _fail("original_SaveGate_callback_failed:"+str(callbacks)); return
	_store_check()
	store_result["SaveGate_callback"]=callbacks[0]
	_write()

func _store_check() -> Dictionary:
	var current: Dictionary=session.store.snapshot()
	var reader:=Store.new(session.store.root_path)
	var opened: Dictionary=reader.load_profile()
	store_result={"ok":opened.get("ok",false) and reader.snapshot()==current and current.personal.discoveries==baseline_discoveries and current.world.get("actions",{})==baseline_story and ID not in JSON.stringify(current.world.get("environment",{})),"reader_equal":reader.snapshot()==current,"discoveries_unchanged":current.personal.discoveries==baseline_discoveries,"story_unchanged":current.world.get("actions",{})==baseline_story,"enemy_absent_from_environment":ID not in JSON.stringify(current.world.get("environment",{})),"scope":"no ambient reward; QA ownership baseline disclosed"}
	return store_result

static func _xyz(value: Vector3) -> Array:
	return [value.x,value.y,value.z]

func _patrol_diagnostics() -> Dictionary:
	# QA-only read projection: same actual inputs/body/space and original ray.
	# Never grants LOS, fires, moves a body, or advances a weapon/simulation clock.
	if config.role!="host" or not is_instance_valid(patrol.scout) or not patrol.scout.is_inside_tree(): return {}
	var rows: Dictionary={}
	for peer: int in session.players:
		var body: FlightBodyV2=session.players[peer]
		if not is_instance_valid(body) or not body.is_inside_tree(): continue
		var hit: Dictionary=patrol._ray(body.global_position,patrol.scout.global_position,body.get_rid())
		var collider: Variant=hit.get("collider")
		var collider_name: String=""
		var collider_class: String=""
		var entity_id: String=""
		if is_instance_valid(collider):
			collider_class=collider.get_class()
			if collider is Node:
				collider_name=str(collider.get_path()) if collider.is_inside_tree() else str(collider.name)
				entity_id=str(collider.get_meta("entity_id",""))
		var half:=Vector3(float(body.stats.width_m),float(body.stats.height_m),float(body.stats.length_m)).length()*.5
		rows[str(peer)]={"physics_frame":Engine.get_physics_frames(),"context":patrol.weapon_context(peer),"policy":patrol._ceasefire_reason(),"may_target":patrol.may_target(body),"body_protected":patrol._protected_point(body.global_position,Vector3.ONE*half),"target_protected":patrol._protected_point(patrol.scout.global_position,patrol.scout.dimensions*.5),"distance_m":body.global_position.distance_to(patrol.scout.global_position),"source_rid":str(body.get_rid()),"target_rid":str(patrol.scout.get_rid()),"first_hit":{"empty":hit.is_empty(),"rid":str(hit.get("rid",RID())),"is_actual_scout":not hit.is_empty() and hit.get("rid")==patrol.scout.get_rid(),"collider_path":collider_name,"collider_class":collider_class,"entity_id":entity_id,"shape_index":int(hit.get("shape",-1)),"position":_xyz(hit.position) if hit.has("position") else []},"input_sequence":session.network.last_input.get(peer,-1),"input_age_msec":Time.get_ticks_msec()-int(session.network.received_at.get(peer,Time.get_ticks_msec()))}
	return rows

func _state() -> Dictionary:
	var view: Dictionary=patrol.presentation()
	var roster: Dictionary={}
	for peer: int in session.players:
		var body: FlightBodyV2=session.players[peer]
		roster[str(peer)]={"identity":session.identities.get(peer,""),"hardware":Build.view(body.build),"build_hash":body.stats.build_hash,"health":body.health,"position":_xyz(body.global_position),"velocity":_xyz(body.linear_velocity),"freeze":body.freeze,"enabled":body.enabled,"command_active":bool(body.command.get("active",false)),"command_fire":bool(body.command.get("fire",false))}
	var announced: Dictionary={}
	for peer: int in session.network.guest_builds: announced[str(peer)]=Build.view(session.network.guest_builds[peer])
	var cycle: Dictionary=session.weapons._cycles[_guest_peer()].cycle.snapshot() if config.role=="host" and session.weapons._cycles.has(_guest_peer()) else {}
	var local_damage_serial: int=int(patrol.scout.damage_state.serial) if is_instance_valid(patrol.scout) else -1
	return {"suite":SUITE,"contract":CONTRACT,"protocol":session.network.PROTOCOL,"run_id":config.run_id,"role":config.role,"profile":config.profile,"profile_uuid":session.store.snapshot().profile_id,"pid":OS.get_process_id(),"executable":OS.get_executable_path(),"actual_package":not OS.has_feature("editor"),"active":session.active,"region":session.region_id,"ready":host_ready,"facilities_ready":session._facilities_ready() if is_instance_valid(session.world) else false,"session_id":session.network.session_id if session.network.is_authority() else session.received_session,"received_sequence":session.received_sequence,"local_peer":session.network.local_id(),"players":roster,"announced_guest_hardware":announced,"locks":session.locks.duplicate(true),"view":view,"view_digest":_digest(view),"old_replay_rank":{"epoch":old_view.get("epoch",-1),"serial":old_view.get("serial",-1)},"replay_count":replay_count,"guest_setup":guest_setup,"fixtures":fixtures,"staged_guest":staged_guest,"first_warning":first_warning,"first_bullet":first_bullet,"mesh_checks":mesh_checks,"mesh_evidence":mesh_evidence,"event_count":network_event_count,"reliable_events":reliable_events,"damage_rows":damage_rows,"hit_receipts":hit_receipts,"cycle":cycle,"local_cycle_count":session.weapons._cycles.size(),"local_patrol_event_count":patrol.events.size(),"scout_authoritative":patrol.scout.authoritative if is_instance_valid(patrol.scout) else false,"scout_auto_physics":patrol.scout.is_physics_processing() if is_instance_valid(patrol.scout) else false,"local_damage_serial":local_damage_serial,"holding":holding,"hold_receipt":hold_receipt,"release_receipt":release_receipt,"paused":session.simulation_paused,"proposal":session.consensus.current_proposal() if session.network.is_authority() else session.choice_proposal,"physics_frame":Engine.get_physics_frames(),"stats":session.stats.duplicate(true),"transport":session.network.telemetry.duplicate(true),"input_router_active":session.inputs.active,"input_test_held":session.inputs.test_frame.get("held",[]).duplicate(),"input_last_held":session.inputs.last_frame.get("held",[]).duplicate(),"input_control_epoch":session.inputs.epoch,"patrol_diagnostics":_patrol_diagnostics(),"atom_probe":atom_probe,"warning_pause":warning_pause,"travel":travel_result,"store_check":store_result,"ack":ack,"result":result,"commands":commands,"errors":errors+logger.errors,"lease":lease_diagnostic,"wall_seconds":float(Time.get_ticks_usec()-began)/1000000.0}

static func _digest(value: Variant) -> String:
	var context:=HashingContext.new(); context.start(HashingContext.HASH_SHA256)
	context.update(var_to_bytes(value)); return context.finish().hex_encode()

func _hold(value: bool) -> void:
	holding=value
	session.inputs.test_frame={"axes":{},"held":["brake","fire"] if value else ["brake"],"edges":[]}
func _release(reason: String) -> void:
	_hold(false)
	if release_receipt.is_empty(): release_receipt={"reason":reason,"physics_frame":Engine.get_physics_frames(),"input_sequence":session.network._sequence}
func _guest_peer() -> int:
	return int(session.network.guests.keys()[0]) if session.network.guests.size()==1 else 0
func _frame() -> bool:
	await get_tree().physics_frame
	await get_tree().process_frame
	return not finishing and is_instance_valid(session)
func _write() -> void:
	var path: String=str(config.evidence).path_join(str(config.role)+"-state.json")
	var file:=FileAccess.open(path+".tmp",FileAccess.WRITE)
	if file==null: return
	file.store_string(JSON.stringify(_state())); file.close()
	DirAccess.rename_absolute(path+".tmp",path)
func _fail(code: String) -> void:
	if code not in errors: errors.append(code)
	print("F2_PATROL_LAN_QA_ERROR ",code)
func _quit() -> void:
	if finishing: return
	finishing=true; _hold(false); _write()
	session._quit() # Original SaveGate/network/audio-drain/exit path.
