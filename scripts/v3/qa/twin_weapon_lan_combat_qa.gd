extends Node
## Explicit packaged observer. Root mounts AFTER preflight and ordinary MAIN.
const SUITE := "weapon-lan-combat"
const PROTOCOL := 25
const CONTRACT := 1
const WEST := "F1:crown_host_west"
const CORE := "boss:crown_core"
const Store = preload("res://scripts/v3/core/twin_world_store.gd")
const Hangar = preload("res://scripts/v3/gameplay/twin_hangar.gd")
const Catalog = preload("res://scripts/v2/catalog.gd")
const Build = preload("res://scripts/v3/network/twin_build_contract.gd")
const Regions = preload("res://scripts/v3/world/twin_region_catalog.gd")
const FIELDS := {"--qa-suite":"suite","--qa-profile":"profile","--qa-lan-weapon-role":"role","--qa-lan-weapon-run":"run_id","--qa-lan-weapon-evidence":"evidence"}

class ErrorLogger extends Logger:
	var errors: Array = []
	var mutex := Mutex.new()
	func _log_error(function: String,file: String,line: int,code: String,rationale: String,_notify: bool,kind: int,_trace: Array[ScriptBacktrace]) -> void:
		if kind == Logger.ERROR_TYPE_WARNING: return
		mutex.lock()
		errors.append({"function":function,"file":file,"line":line,"code":code,"rationale":rationale})
		mutex.unlock()

var session: Node
var config: Dictionary = {}
var logger := ErrorLogger.new()
var began := 0
var last_write := 0
var last_good: Dictionary = {}
var lease_diagnostic: Dictionary = {}
var queued := false
var started := false
var finishing := false
var host_ready := false
var ack := 0
var result: Dictionary = {}
var errors: Array = []
var commands: Array = []
var fixtures: Array = []
var guest_setup: Dictionary = {}
var prepared: Dictionary = {}
var hit_receipt: Dictionary = {}
var hot_owner: Dictionary = {}
var hp_changes: Array = []
var watching := false
var previous_hp := 160000
var first_charge_frame := -1
var holding := false
var stop_fire_frame := -1
var hold_receipt: Dictionary = {}
var release_receipt: Dictionary = {}

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
	var expected: String = "qa_lan_weapon_"+str(cfg.role)+"_"+str(cfg.run_id)
	if cfg.profile != expected or cfg.profile != str(cfg.profile).validate_filename() or DirAccess.dir_exists_absolute("user://profiles_v3/"+expected): return {"ok":false,"code":"fresh_private_profile_required"}
	var evidence: String = OS.get_executable_path().get_base_dir().path_join("artifacts/v3/network/weapon-combat").path_join(cfg.run_id)
	if not str(cfg.evidence).is_absolute_path() or ".." in str(cfg.evidence) or _normalized(cfg.evidence) != _normalized(evidence) or not DirAccess.dir_exists_absolute(evidence): return {"ok":false,"code":"dedicated_package_evidence_required"}
	var lease := _lease(cfg)
	if not lease.ok and not lease.transient: return lease
	return {"ok":true,"config":cfg}

func run(owner_session: Node, options: Dictionary) -> Dictionary:
	if session != null or not is_inside_tree() or options.is_empty(): return {"ok":false,"code":"mount_once"}
	session = owner_session
	config = options.duplicate(true)
	if not session.profile_ready or session.store.root_path != "user://profiles_v3/"+str(config.profile) or session.network.PROTOCOL != PROTOCOL: return {"ok":false,"code":"ordinary_MAIN_private_profile_protocol_required"}
	process_priority = 100
	process_physics_priority = 100 # Observe AFTER the original authority weapon tick.
	began = Time.get_ticks_usec()
	OS.add_logger(logger)
	return {"ok":true,"code":"mounted_ordinary_MAIN"}

func _process(_delta: float) -> void:
	if session == null or began == 0 or finishing: return
	if Time.get_ticks_usec()-began > 80000000: _fail("80_second_peer_bound"); _quit(); return
	var lease := _lease(config)
	lease_diagnostic = lease.duplicate(true)
	if lease.ok: last_good = lease.controller.duplicate(true)
	elif not lease.transient: _fail(str(lease.code)); _quit(); return
	elif last_good.is_empty():
		if Time.get_ticks_usec()-began > 8000000: _fail("initial_controller_wait_expired"); _quit()
		return
	elif absf(Time.get_unix_time_from_system()-float(last_good.heartbeat_unix)) > 8.0: _fail("original_last_good_stamp_expired"); _quit(); return
	if not started and not queued:
		queued = true
		_boot.call_deferred()
	if started and config.role == "guest":
		var view: Dictionary = session.weapons.presentation(session.network.local_id())
		if float(view.get("heat",0)) > 0.0:
			if holding: _release("original_owner_heat_event")
			var label: Label = session.interface.weapon_status
			if hot_owner.is_empty() and label.text == session.weapons.hud(session.network.local_id()) and "蓄能炮" in label.text and "热量" in label.text:
				hot_owner = {"view":view.duplicate(true),"hud":label.text,"hud_visible":label.is_visible_in_tree(),"serial":session.weapons._remote_serial,"session_id":session.weapons._remote_session,"physics_frame":Engine.get_physics_frames(),"local_cycle_count":session.weapons._cycles.size()}
	if Time.get_ticks_usec()-last_write < 50000: return
	last_write = Time.get_ticks_usec()
	var command := _json(str(config.evidence).path_join(str(config.role)+"-command.json"))
	var serial: Variant = command.get("sequence",0)
	if command.get("run_id") == config.run_id and (serial is int or serial is float) and is_finite(float(serial)) and floor(float(serial)) == float(serial) and int(serial) > ack and int(serial) <= 1000:
		ack = int(serial)
		var verb: String = str(command.get("verb",""))
		result = _execute(verb)
		commands.append({"sequence":ack,"verb":verb,"result":result.duplicate(true),"physics_frame":Engine.get_physics_frames()})
		if not result.get("ok",false): _fail("command:"+verb+":"+str(result.get("code","rejected")))
		if verb == "shutdown": _write(); _quit(); return
	_write()

func _boot() -> void:
	if config.role == "guest" and not _guest_hangar(): _quit(); return
	session.interface.action_requested.emit("host" if config.role == "host" else "join",{"frame":session.interface.frames.selected,"address":"127.0.0.1"})
	if not session.active: _fail("original_menu_network_start_failed"); _quit(); return
	started = true
	session.inputs.test_enabled = true
	_hold(false)
	if config.role == "host":
		for unused in 3:
			if not await _frame(): return
		if not session._load_region("F1") or not session.crown.ready(): _fail("original_F1_factory_or_import_failed"); _quit(); return
		host_ready = true
	_write()

func _guest_hangar() -> bool:
	var before: Dictionary = session.store.snapshot()
	var fixture := {"id":"qa-weapon-lan-ownership:"+str(config.run_id),"append":{"personal.discoveries":["boss:F2:mirrorwing_warden","I3:cooling_overdraft"]}}
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
	var desired := {"weapon":"burst_capacitor","tool":"scan_base","drive":"stock_drive","battery":"stock_battery","utility":"cooling_duct"}
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

func _execute(verb: String) -> Dictionary:
	match verb:
		"prepare_crown":
			if config.role != "host" or not host_ready or session.players.size() != 2 or not prepared.is_empty(): return {"ok":false,"code":"two_real_peers_prepare_once"}
			prepared = {"pending":true}
			_prepare_crown.call_deferred()
			return {"ok":true,"code":"original_development_preparation_queued"}
		"lock_core":
			if config.role != "guest": return {"ok":false}
			session.network.send_action("lock",{"target_id":CORE})
			return {"ok":true,"code":"original_reliable_lock"}
		"hold_once":
			if config.role != "guest" or not hold_receipt.is_empty() or session.locks.get(session.network.local_id()) != CORE: return {"ok":false,"code":"guest_actual_lock_once_required"}
			hold_receipt = {"physics_frame":Engine.get_physics_frames(),"input_sequence_before":session.network._sequence,"source":"ordinary_InputRouter_test_frame"}
			stop_fire_frame = Engine.get_physics_frames()+54
			_hold(true)
			return {"ok":true,"code":"original_held_fire_for_at_most_54_guest_physics_frames"}
		"release": _release("controller_release"); return {"ok":true}
		"pause": session._request_pause(); return {"ok":true,"code":"original_Consensus_pause_intent"}
		"confirm":
			var proposal: Dictionary = session.choice_proposal
			if config.role != "guest" or proposal.get("kind") != "pause": return {"ok":false,"code":"received_pause_proposal_required"}
			session.network.send_action("confirm",{"proposal_id":proposal.proposal_id,"world_revision":proposal.world_revision})
			return {"ok":true,"code":"original_reliable_guest_confirmation"}
		"shutdown": return {"ok":true,"code":"ordinary_quit"}
	return {"ok":false,"code":"unknown_command"}

func _prepare_crown() -> void:
	var peer := _guest_peer()
	if peer == 0 or not await _near(1,session.world.crown_arena.host_position(WEST),WEST,true,3.0) or not await _near(peer,session.world.crown_arena.host_position(WEST),WEST,false,5.0): _fail("actual_player_staging_clearance_failed"); return
	session._start_boss(false)
	if not session.crown.active() or session.boss_campaign: _fail("original_development_Crown_start_failed"); return
	watching = true
	previous_hp = int(session.crown.encounter.get_state().core_hp_milli)
	if previous_hp != 160000: _fail("unexpected_authored_Crown_start_HP"); return
	for ability: String in ["light","growth"]:
		for unused in 120:
			if float(session.cooldowns.get(1,0)) <= 0.0: break
			if not await _frame(): return
		var count: int = session.stats.abilities
		session.network.send_action("ability",{"ability":ability,"target_id":WEST,"mode":"on" if ability == "light" else ""})
		if not await _frame(): return
		if session.stats.abilities != count+1: _fail("original_host_ability_failed:"+ability); return
	if not session.crown.encounter.get_state().core_open or not await _near(peer,session.world.crown_arena.core_position(),CORE,true,7.0): _fail("actual_open_core_or_guest_shooting_ray_failed"); return
	prepared = {"ok":true,"fixture":"original development start, actual player-only clear observation poses and original light/growth; no naturally played Story","guest_peer":peer,"core_hp_milli":session.crown.encounter.get_state().core_hp_milli,"core_open":session.crown.encounter.get_state().core_open,"physics_frame":Engine.get_physics_frames()}
	_write()

func _near(peer: int, point: Vector3, target: String, los: bool, radius: float) -> bool:
	var offsets: Array[Vector3] = [Vector3(0,radius,0)]
	for height: float in [0.0,3.0,-1.0]:
		for index in 16:
			var angle := TAU*float(index)/16.0
			offsets.append(Vector3(cos(angle)*radius,height,sin(angle)*radius))
	for offset: Vector3 in offsets:
		var at := point+offset
		if not _clear(peer,at) or los and not session._line_clear(at,point,session.players[peer].get_rid(),target): continue
		var body: FlightBodyV2 = session.players[peer]
		body.freeze = true
		body.global_transform = Transform3D(Basis.IDENTITY,at)
		body.force_update_transform()
		PhysicsServer3D.body_set_state(body.get_rid(),PhysicsServer3D.BODY_STATE_TRANSFORM,body.global_transform)
		body.linear_velocity = Vector3.ZERO
		body.angular_velocity = Vector3.ZERO
		body.hold_height = at.y
		fixtures.append({"kind":"explicit_PLAYER_only_observation_pose_not_flown","peer":peer,"at":[at.x,at.y,at.z],"native_hull_clear":true,"target":target,"LOS_required":los})
		for unused in 2:
			if not await _frame(): return false
		return true
	return false

func _clear(peer: int, at: Vector3) -> bool:
	if not Regions.contains("F1",at) or not session.world.crown_arena.in_combat_space(at): return false
	var body: FlightBodyV2 = session.players[peer]
	var envelope := body.get_node("Envelope") as CollisionShape3D
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = envelope.shape
	query.transform = Transform3D(Basis.IDENTITY,at)*envelope.transform
	query.collision_mask = 1|2|8|32
	query.exclude = [body.get_rid()]
	return session.get_world_3d().direct_space_state.intersect_shape(query,1).is_empty()

func _physics_process(_delta: float) -> void:
	if not started or finishing: return
	if config.role == "guest":
		if holding and Engine.get_physics_frames() >= stop_fire_frame: _release("54_guest_physics_frame_bound")
		return
	var peer := _guest_peer()
	if not watching or peer == 0: return
	var state: Dictionary = session.crown.encounter.get_state()
	var cycle: Dictionary = session.weapons._cycles[peer].cycle.snapshot() if session.weapons._cycles.has(peer) else {}
	if float(cycle.get("charge_s",0)) > 0.0 and first_charge_frame < 0: first_charge_frame = Engine.get_physics_frames()
	var hp: int = int(state.core_hp_milli)
	if hp != previous_hp:
		var row := {"before_hp_milli":previous_hp,"after_hp_milli":hp,"delta_milli":previous_hp-hp,"physics_frame":Engine.get_physics_frames(),"first_charge_frame":first_charge_frame,"charged_frame_span":Engine.get_physics_frames()-first_charge_frame+1,"physics_ticks_per_second":Engine.physics_ticks_per_second,"cycle":cycle,"body_heat":session.players[peer].heat,"peer":peer,"identity":session.identities[peer],"original_shot_sequence":session.crown.shot_sequences.get(peer,0),"original_player_sequence":state.players.get("player:"+str(peer),{}).get("last_shot_sequence",0),"native_command":session.players[peer].command.duplicate(true),"original_input_sequence":session.network.last_input.get(peer,-1),"stats_shots":session.stats.shots}
		hp_changes.append(row)
		if hit_receipt.is_empty(): hit_receipt = row.duplicate(true)
		previous_hp = hp

func _hold(value: bool) -> void:
	holding = value
	session.inputs.test_frame = {"axes":{},"held":["brake","fire"] if value else ["brake"],"edges":[]}

func _release(reason: String) -> void:
	_hold(false)
	if release_receipt.is_empty(): release_receipt = {"reason":reason,"physics_frame":Engine.get_physics_frames(),"input_sequence":session.network._sequence}

func _guest_peer() -> int:
	return int(session.network.guests.keys()[0]) if session.network.guests.size() == 1 else 0

func _frame() -> bool:
	await get_tree().physics_frame
	await get_tree().process_frame
	return not finishing and is_instance_valid(session)

func _state() -> Dictionary:
	var roster: Dictionary = {}
	for peer: int in session.players:
		var body: FlightBodyV2 = session.players[peer]
		roster[str(peer)] = {"identity":session.identities.get(peer,""),"hardware":Build.view(body.build),"build_hash":body.stats.build_hash,"body_id":body.get_instance_id(),"heat":body.heat,"health":body.health,"enabled":body.enabled,"position":[body.global_position.x,body.global_position.y,body.global_position.z],"command_fire":bool(body.command.get("fire",false)),"view":session.weapons.presentation(peer)}
	var local: int = session.network.local_id()
	var boss: Dictionary = session.crown.encounter.get_state() if config.role == "host" else session.world_cache.get("remote_boss",{})
	var cycle: Dictionary = session.weapons._cycles[_guest_peer()].cycle.snapshot() if config.role == "host" and session.weapons._cycles.has(_guest_peer()) else {}
	var announced: Dictionary = {}
	for peer: int in session.network.guest_builds: announced[str(peer)] = Build.view(session.network.guest_builds[peer])
	return {"suite":SUITE,"contract":CONTRACT,"protocol":session.network.PROTOCOL,"run_id":config.run_id,"role":config.role,"label":config.role,"profile":config.profile,"profile_uuid":session.store.snapshot().profile_id,"pid":OS.get_process_id(),"executable":OS.get_executable_path(),"actual_package":not OS.has_feature("editor"),"active":session.active,"region":session.region_id,"ready":host_ready,"facilities_ready":session._facilities_ready() if is_instance_valid(session.world) else false,"session_id":session.network.session_id if session.network.is_authority() else session.received_session,"received_sequence":session.received_sequence,"local_peer":local,"players":roster,"announced_guest_hardware":announced,"locks":session.locks.duplicate(true),"boss":boss,"boss_campaign":session.boss_campaign,"prepared":prepared,"hit_receipt":hit_receipt,"hot_owner":hot_owner,"hp_changes":hp_changes,"cycle":cycle,"guest_setup":guest_setup,"fixtures":fixtures,"holding":holding,"hold_receipt":hold_receipt,"release_receipt":release_receipt,"paused":session.simulation_paused,"proposal":session.consensus.current_proposal() if session.network.is_authority() else session.choice_proposal,"physics_frame":Engine.get_physics_frames(),"hud":session.interface.weapon_status.text,"stats":session.stats.duplicate(true),"transport":session.network.telemetry.duplicate(true),"ack":ack,"result":result,"commands":commands,"errors":errors+logger.errors,"lease":lease_diagnostic,"wall_seconds":float(Time.get_ticks_usec()-began)/1000000.0}

func _write() -> void:
	var path: String = str(config.evidence).path_join(str(config.role)+"-state.json")
	var file := FileAccess.open(path+".tmp",FileAccess.WRITE)
	if file == null: return
	file.store_string(JSON.stringify(_state()))
	file.close()
	DirAccess.rename_absolute(path+".tmp",path)

func _fail(code: String) -> void:
	if code not in errors: errors.append(code)
	print("WEAPON_LAN_QA_ERROR ",code)

func _quit() -> void:
	if finishing: return
	finishing = true
	_hold(false)
	_write()
	session._quit() # Original clean save/close/audio-drain terminal path.
