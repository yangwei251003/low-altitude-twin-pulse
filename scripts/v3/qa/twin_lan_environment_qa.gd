extends Node
## Explicit packaged QA. Commands are orchestration, never received game state.
## Gameplay actions use each real peer's original Network/Session path.
const SUITE := "environment-lan"
const CONTRACT := 1
const PROTOCOL := 25
const Cargo = preload("res://scripts/v3/gameplay/twin_thermal_cargo_session.gd")
const Store = preload("res://scripts/v3/core/twin_world_store.gd")
const Hangar = preload("res://scripts/v3/gameplay/twin_hangar.gd")
const BuildContract = preload("res://scripts/v3/network/twin_build_contract.gd")
const Catalog = preload("res://scripts/v2/catalog.gd")
const I4Storm = preload("res://scripts/v3/environment/twin_i4_storm_environment.gd")
const I4Probe = preload("res://scripts/v3/qa/twin_i4_paused_sample_probe.gd")
const FIELDS := {"--qa-suite":"suite","--qa-profile":"profile","--qa-lan-env-role":"role","--qa-lan-env-label":"label","--qa-lan-env-region":"region","--qa-lan-env-run":"run_id","--qa-lan-env-evidence":"evidence","--qa-lan-env-loadout-case":"loadout_case","--qa-lan-env-loadout-variant":"loadout_variant"}
const LOADOUTS := {
    "host":{"frame":"tr01","drive":"stock_drive","utility":"reinforced_guard","discovery":"boss:I1:harbor_whale"},
    "guest_first":{"frame":"tr01","drive":"racing_drive","utility":"guard_base","discovery":"boss:F1:parasitic_crown"},
    "guest_reconnect":{"frame":"ag03","drive":"racing_drive","utility":"guard_base","discovery":"boss:F1:parasitic_crown"}}

class ErrorLogger extends Logger:
    var errors: Array = []
    var guard := Mutex.new()
    func _log_error(function: String,file: String,line: int,code: String,rationale: String,_notify: bool,kind: int,_trace: Array[ScriptBacktrace]) -> void:
        if kind==Logger.ERROR_TYPE_WARNING: return
        guard.lock()
        errors.append({"function":function,"file":file,"line":line,"code":code,"rationale":rationale})
        guard.unlock()

var session: Node
var config: Dictionary = {}
var loadout_setup: Dictionary = {}
var logger := ErrorLogger.new()
var errors: Array = []
var ack := 0
var result: Dictionary = {}
var commands: Array = []
var first_accepted: Dictionary = {}
var first_paused: Dictionary = {}
var latest_accepted: Dictionary = {}
var local_uuid := ""
var host_ready := false
var started_usec := 0
var last_publish_usec := 0
var last_sequence := -1
var save_callbacks: Array = []
var last_save_request: Dictionary = {}
var initial_qa_pose: Dictionary = {}
var disk_readback: Dictionary = {}
var finishing := false
var network_started := false
var network_start_queued := false
var last_good_controller: Dictionary = {}
var controller_diagnostic: Dictionary = {}
var controller_read_failures := 0
var controller_transitions: Array = []
var last_controller_reason := ""
var i4_paused_probe: Dictionary = {}

## Complete wrong identities/leases are fatal. Only a failed/missing/partial
## read is transient; its diagnostic never creates a new timestamp or credit.
static func _controller_read(cfg: Dictionary) -> Dictionary:
    var path: String = cfg.evidence.path_join("controller.json")
    var observed: float = Time.get_unix_time_from_system()
    var detail := {"observed_unix":observed,"path":path}
    if not FileAccess.file_exists(path):
        detail["reason"] = "file_missing"
        return {"ok":false,"transient":true,"code":"controller_file_missing","detail":detail}
    var file := FileAccess.open(path,FileAccess.READ)
    if file==null:
        detail.merge({"reason":"open_failed","open_error":FileAccess.get_open_error()})
        return {"ok":false,"transient":true,"code":"controller_open_failed","detail":detail}
    var length: int = file.get_length()
    detail["file_length"] = length
    if length>1048576:
        file.close()
        detail["reason"] = "file_oversized"
        return {"ok":false,"transient":false,"code":"controller_file_oversized","detail":detail}
    var content: String = file.get_as_text()
    detail["read_error"] = file.get_error()
    file.close()
    var parser := JSON.new()
    if parser.parse(content)!=OK:
        detail.merge({"reason":"parse_failed","parse_line":parser.get_error_line(),"parse_message":parser.get_error_message(),"text_length":content.length()})
        return {"ok":false,"transient":true,"code":"controller_parse_failed","detail":detail}
    var value: Variant = parser.data
    if not value is Dictionary:
        detail.merge({"reason":"complete_non_dictionary","value_type":type_string(typeof(value))})
        return {"ok":false,"transient":false,"code":"controller_schema","detail":detail}
    var expected := {"suite":SUITE,"run_id":cfg.run_id,"region":cfg.region,"port":26742,"lock_held":true}
    if value.get("loadout_case",false)!=cfg.loadout_case:
        detail.merge({"reason":"complete_case_mismatch","expected":cfg.loadout_case,"actual":value.get("loadout_case",false)})
        return {"ok":false,"transient":false,"code":"controller_loadout_case_mismatch","detail":detail}
    if value.get("loadout_variant","HBA")!=cfg.loadout_variant:
        detail.merge({"reason":"complete_variant_mismatch","expected":cfg.loadout_variant,"actual":value.get("loadout_variant","HBA")})
        return {"ok":false,"transient":false,"code":"controller_loadout_variant_mismatch","detail":detail}
    for key: String in expected:
        if value.get(key)!=expected[key]:
            detail.merge({"reason":"complete_identity_or_lock_mismatch","field":key,"expected":expected[key],"actual":value.get(key)})
            return {"ok":false,"transient":false,"code":"controller_identity_or_lock:"+key,"detail":detail}
    var stamp: Variant = value.get("heartbeat_unix")
    if not (stamp is int or stamp is float) or not is_finite(float(stamp)):
        detail.merge({"reason":"complete_invalid_stamp","stamp_type":type_string(typeof(stamp))})
        return {"ok":false,"transient":false,"code":"controller_invalid_stamp","detail":detail}
    var age: float = observed-float(stamp)
    detail.merge({"heartbeat_unix":stamp,"age_seconds":age,"controller_pid":value.get("controller_pid",0)})
    if absf(age)>8.0:
        detail["reason"] = "complete_expired_stamp"
        return {"ok":false,"transient":false,"code":"controller_stamp_expired","detail":detail}
    detail["reason"] = "complete_live_matching_controller"
    return {"ok":true,"transient":false,"code":"controller_live","controller":value,"detail":detail}

static func _normalized(path: String) -> String:
    return path.replace("\\","/").simplify_path().trim_suffix("/").to_lower()

static func _configuration(args: PackedStringArray) -> Dictionary:
    var parsed: Dictionary = {}
    for arg: String in args:
        var split: int = arg.find("=")
        if split<1: return {"ok":false,"code":"unknown_argument"}
        var key: String = arg.substr(0,split)
        if not FIELDS.has(key) or parsed.has(FIELDS[key]): return {"ok":false,"code":"unknown_or_duplicate_argument"}
        parsed[FIELDS[key]] = arg.substr(split+1)
    for key: String in FIELDS.values():
        if key in ["loadout_case","loadout_variant"]: continue # Original seven arguments stay sufficient.
        if str(parsed.get(key,"")).is_empty(): return {"ok":false,"code":"missing_argument:"+key}
    if parsed.has("loadout_case") and parsed.loadout_case!="1": return {"ok":false,"code":"invalid_loadout_case"}
    parsed["loadout_case"] = parsed.has("loadout_case")
    parsed["loadout_variant"] = str(parsed.get("loadout_variant","HBA"))
    if parsed.loadout_variant not in ["HBA","HBA_BURST"] or parsed.loadout_variant=="HBA_BURST" and not parsed.loadout_case: return {"ok":false,"code":"invalid_loadout_variant"}
    if parsed.suite!=SUITE or parsed.role not in ["host","guest"] or parsed.region not in ["I2","I3","I4"]: return {"ok":false,"code":"invalid_suite_role_region"}
    if parsed.loadout_case and parsed.region!="I3": return {"ok":false,"code":"loadout_case_requires_I3"}
    var pattern := RegEx.new()
    pattern.compile("^[0-9]{8}_[0-9]{6}_[0-9]{6}$")
    if pattern.search(parsed.run_id)==null: return {"ok":false,"code":"invalid_run_id"}
    if parsed.label not in (["host"] if parsed.role=="host" else ["guest_first","guest_reconnect"]): return {"ok":false,"code":"invalid_label"}
    if parsed.region=="I4" and parsed.label=="guest_reconnect": return {"ok":false,"code":"I4_short_case_has_no_reconnect"}
    var expected: String = "qa_lan_environment_"+parsed.role+"_"+parsed.region.to_lower()+"_"+parsed.run_id
    if parsed.profile!=expected or parsed.profile!=str(parsed.profile).validate_filename(): return {"ok":false,"code":"isolated_profile_mismatch"}
    var evidence: String = OS.get_executable_path().get_base_dir().path_join("artifacts/v3/network/environment").path_join(parsed.region).path_join(parsed.run_id)
    if not str(parsed.evidence).is_absolute_path() or ".." in str(parsed.evidence) or _normalized(parsed.evidence)!=_normalized(evidence) or not DirAccess.dir_exists_absolute(parsed.evidence): return {"ok":false,"code":"dedicated_executable_evidence_required"}
    return {"ok":true,"code":"configured","config":parsed}

## Root must call this BEFORE constructing MAIN or any Store. No mutations.
static func preflight(args: PackedStringArray) -> Dictionary:
    if args!=OS.get_cmdline_user_args(): return {"ok":false,"code":"actual_process_arguments_required"}
    var parsed: Dictionary = _configuration(args)
    if not parsed.ok: return parsed
    if OS.has_feature("editor") or not OS.is_debug_build(): return {"ok":false,"code":"actual_export_debug_package_required"}
    var cfg: Dictionary = parsed.config
    var lease: Dictionary = _controller_read(cfg)
    if not lease.ok and not lease.transient:
        print("LAN_ENVIRONMENT_CONTROLLER_PREFLIGHT_REJECTED ",JSON.stringify(lease))
        return {"ok":false,"code":lease.code,"controller_diagnostic":lease.detail}
    var exists: bool = DirAccess.dir_exists_absolute("user://profiles_v3/"+cfg.profile)
    if exists != (cfg.label=="guest_reconnect"): return {"ok":false,"code":"fresh_or_reconnect_profile_mismatch"}
    # Isolated MAIN creation is permitted on an unreadable controller; actual
    # network/region start still waits up to8s for a complete original stamp.
    parsed["controller_pending"] = not lease.ok
    parsed["controller_diagnostic"] = lease.detail
    return parsed

## Ordinary MAIN must already be a direct root/current_scene with its original
## node name. Root adds this child, then calls run; no alternate Session class.
func run(owner_session: Node,args: PackedStringArray) -> Dictionary:
    if args!=OS.get_cmdline_user_args(): return {"ok":false,"code":"actual_process_arguments_required"}
    var parsed: Dictionary = _configuration(args)
    if not parsed.ok: return parsed
    if OS.has_feature("editor") or not OS.is_debug_build(): return {"ok":false,"code":"actual_export_debug_package_required"}
    session = owner_session
    config = parsed.config
    if session==null or session.name!="TwinPulseSession" or session.get_parent()!=get_tree().root or get_tree().current_scene!=session or session.store.root_path!="user://profiles_v3/"+config.profile or session.network.PROTOCOL!=PROTOCOL or not session.profile_ready: return {"ok":false,"code":"ordinary_MAIN_profile_or_protocol25_required"}
    process_priority = 100 # Observe AFTER ordinary Session._process applies packets.
    if config.region=="I4": process_physics_priority=100 # Read only, after original Session sampling/correction.
    OS.add_logger(logger)
    local_uuid = str(session.store.snapshot().profile_id)
    started_usec = Time.get_ticks_usec()
    print("LAN_ENVIRONMENT_QA_ACCEPTED ",JSON.stringify({"role":config.role,"label":config.label,"profile_uuid":local_uuid,"protocol":PROTOCOL,"pid":OS.get_process_id(),"loadout_case":config.loadout_case}))
    return {"ok":true,"code":"accepted","contract":CONTRACT}

func _start() -> void:
    network_start_queued = false
    var lease: Dictionary = _controller_step()
    if not lease.ok:
        _fail(str(lease.code))
        _shutdown()
        return
    if not lease.ready: return
    var started := false
    if config.loadout_case:
        var prepared := _prepare_local_loadout()
        if not prepared.ok:
            _fail("local_hangar:"+str(prepared.code))
            _shutdown()
            return
        # Same signal/payload as the ordinary menu, not a configured QA body.
        session.interface.action_requested.emit("host" if config.role=="host" else "join",{"frame":session.interface.frames.selected,"address":"127.0.0.1"})
        started = session.active and session.network.mode==("host" if config.role=="host" else "guest")
    else:
        started = session.start_flight("host" if config.role=="host" else "guest","127.0.0.1")
    if not started:
        _fail("ordinary_network_start_failed")
        _shutdown()
        return
    network_started = true
    session.inputs.test_enabled = true
    session.inputs.test_frame = {"axes":{},"held":["brake"],"edges":[]}
    if config.role=="host":
        for unused in 3:
            await get_tree().physics_frame
            await get_tree().process_frame
        # Explicit initial QA region load only, no prior objectives or authority
        # envelope/ownership/pose injections into a facility or cargo.
        if not session._load_region(config.region): _fail("original_region_factory_failed")
    _write_state()

func _process(_delta: float) -> void:
    if session==null or config.is_empty() or started_usec==0 or finishing: return
    if Time.get_ticks_usec()-started_usec>210000000:
        _fail("210_second_peer_bound")
        _shutdown()
        return
    var lease: Dictionary = _controller_step()
    if not lease.ok:
        _fail(str(lease.code))
        _shutdown()
        return
    if not network_started:
        if lease.ready and not network_start_queued:
            network_start_queued = true
            _start.call_deferred()
        if Time.get_ticks_usec()-last_publish_usec>=150000:
            last_publish_usec = Time.get_ticks_usec()
            _write_state()
        return
    if config.role=="host":
        host_ready = session.active and session.region_id==config.region and session._facilities_ready()
        if config.region=="I2": host_ready = host_ready and session.canal!=null and session.canal.ready
        elif config.region=="I3": host_ready = host_ready and session.thermal_cargo.supported() and session.thermal_cargo.module.ready
        elif config.region=="I4": host_ready = host_ready and _i4_evidence().get("installed",false)
    elif session.received_sequence>last_sequence:
        last_sequence = session.received_sequence
        latest_accepted = _accepted_evidence()
        if first_accepted.is_empty(): first_accepted=latest_accepted.duplicate(true)
        if latest_accepted.paused and first_paused.is_empty(): first_paused=latest_accepted.duplicate(true)
    if Time.get_ticks_usec()-last_publish_usec<150000: return
    last_publish_usec = Time.get_ticks_usec()
    var command: Dictionary = _read_json(config.evidence.path_join(config.label+"-command.json"))
    var serial: Variant = command.get("sequence",0)
    var integer_serial: bool = (serial is int or serial is float) and is_finite(float(serial)) and floor(float(serial))==float(serial) and float(serial)>0 and float(serial)<=1000
    if command.get("run_id")==config.run_id and integer_serial and int(serial)>ack:
        ack = int(command.sequence)
        result = _execute(str(command.get("verb","")))
        commands.append({"sequence":ack,"verb":command.get("verb",""),"result":result.duplicate(true),"frame":Engine.get_physics_frames()})
        if commands.size()>32: commands.pop_front()
        if not result.get("ok",false): _fail("command_rejected:"+str(command.get("verb"))+":"+str(result.get("code","")))
        if command.get("verb")=="shutdown": _write_state(); _shutdown(); return
    _write_state()

func _physics_process(_delta: float) -> void:
    if finishing or not network_started or config.get("region")!="I4" or config.get("role")!="guest" or not is_instance_valid(session) or not session.active or session.region_id!="I4": return
    # No tick/clock/UI writes. The original callback and accepted packets run first.
    i4_paused_probe = I4Probe.capture(session) if session.simulation_paused and session.players.has(session.network.local_id()) else {}

func _i4_evidence() -> Dictionary:
    if config.get("region")!="I4" or not is_instance_valid(session.world) or session.region_id!="I4": return {}
    var wall: StaticBody3D=session.world.get_node_or_null("I4StormEnvironment/Windbreak") as StaticBody3D
    var space: RID=session.world.get_world_3d().space
    var installed: bool=is_instance_valid(wall) and wall.get_rid().is_valid() and PhysicsServer3D.body_get_space(wall.get_rid())==space
    var peer: int=session.network.local_id()
    if session.network.is_authority() and session.network.guests.size()==1: peer=int(session.network.guests.keys()[0])
    var row := {"installed":installed,"world_id":session.world.get_instance_id(),"world_space":space.get_id(),"world_clock":session.world.clock_seconds,"phase":I4Storm.phase_at(session.world.clock_seconds),"observed_peer":peer,"observed_identity":session.identities.get(peer,""),"physics_frame":Engine.get_physics_frames(),"probe":i4_paused_probe.duplicate(true)}
    if not session.players.has(peer): return row
    var body: FlightBodyV2=session.players[peer]
    var field: Dictionary=body.environment_sample.get("i4_storm",{})
    var native_pose: Transform3D=PhysicsServer3D.body_get_state(body.get_rid(),PhysicsServer3D.BODY_STATE_TRANSFORM)
    row.merge({"body_id":body.get_instance_id(),"body_rid":body.get_rid().get_id(),"body_space":PhysicsServer3D.body_get_space(body.get_rid()).get_id(),"frozen":body.freeze,"position":[body.global_position.x,body.global_position.y,body.global_position.z],"native_position":[native_pose.origin.x,native_pose.origin.y,native_pose.origin.z],"native_basis":native_pose.basis,"available":field.get("available",false),"cached_clock":field.get("clock_input",-1),"cached_phase":field.get("phase",""),"hud_text":session.interface.environment_status.text,"hud_visible":session.interface.environment_status.is_visible_in_tree()})
    return row

func _controller_step() -> Dictionary:
    var read: Dictionary = _controller_read(config)
    controller_diagnostic = read.detail.duplicate(true)
    if read.ok:
        if last_good_controller.is_empty() and Time.get_ticks_usec()-started_usec>8000000:
            controller_diagnostic.merge({"state":"initial_controller_wait_expired","initial_wait_seconds":float(Time.get_ticks_usec()-started_usec)/1000000.0,"initial_wait_limit_seconds":8.0})
            _record_controller_transition("controller_initial_read_timeout")
            return {"ok":false,"ready":false,"code":"controller_initial_read_timeout"}
        last_good_controller = read.controller.duplicate(true)
        controller_diagnostic["state"] = "live"
    else:
        if not read.transient:
            controller_diagnostic["state"] = "rejected_complete_controller"
            _record_controller_transition(str(read.code))
            return {"ok":false,"ready":false,"code":read.code}
        controller_read_failures += 1
        controller_diagnostic["transient_read_failures"] = controller_read_failures
        if last_good_controller.is_empty():
            var waiting: float = float(Time.get_ticks_usec()-started_usec)/1000000.0
            controller_diagnostic.merge({"state":"waiting_first_complete_controller","initial_wait_seconds":waiting,"initial_wait_limit_seconds":8.0})
            _record_controller_transition(str(read.code))
            return {"ok":waiting<=8.0,"ready":false,"code":"controller_initial_read_timeout" if waiting>8.0 else "waiting_first_complete_controller"}
        var age: float = Time.get_unix_time_from_system()-float(last_good_controller.heartbeat_unix)
        controller_diagnostic.merge({"state":"transient_read_using_original_stamp","last_good_heartbeat_unix":last_good_controller.heartbeat_unix,"last_good_age_seconds":age})
        _record_controller_transition(str(read.code))
        if absf(age)>8.0: return {"ok":false,"ready":false,"code":"controller_last_good_stamp_expired"}
        return {"ok":true,"ready":true,"code":"controller_last_good_original_stamp_still_live"}
    _record_controller_transition("controller_live")
    return {"ok":true,"ready":true,"code":"controller_live"}

func _record_controller_transition(reason: String) -> void:
    if reason==last_controller_reason: return
    last_controller_reason = reason
    controller_transitions.append({"reason":reason,"detail":controller_diagnostic.duplicate(true),"wall_seconds":float(Time.get_ticks_usec()-started_usec)/1000000.0})
    if controller_transitions.size()>16: controller_transitions.pop_front()

func _execute(verb: String) -> Dictionary:
    match verb:
        "observe": return {"ok":true}
        "pause":
            session._request_pause()
            return {"ok":true,"code":"original_pause_intent"}
        "confirm":
            var proposal: Dictionary = session.consensus.current_proposal() if session.network.is_authority() else session.choice_proposal
            if proposal.is_empty(): return {"ok":false,"code":"no_received_proposal"}
            session.network.send_action("confirm",{"proposal_id":proposal.proposal_id,"world_revision":proposal.world_revision})
            return {"ok":true,"code":"original_reliable_confirm"}
        "save":
            if config.role!="host": return {"ok":false,"code":"host_only"}
            save_callbacks.clear()
            last_save_request = session.request_environment_save(func(value: Dictionary): save_callbacks.append(value.duplicate(true)))
            return last_save_request.duplicate(true)
        "read_disk":
            if config.role!="host": return {"ok":false,"code":"host_only"}
            var reader := Store.new(session.store.root_path)
            var loaded: Dictionary = reader.load_profile()
            var current: Dictionary = session.store.snapshot()
            var saved: Dictionary = reader.snapshot()
            var key: String = "I2_canal" if config.region=="I2" else ("campaign_I4" if config.region=="I4" else "I3_thermal_cargo")
            var envelope: Dictionary = saved.world.get("environment",{}).get(key,{})
            disk_readback = {"load":loaded,"profile_uuid":saved.profile_id,"generation":saved.generation,"environment_key":key,"environment":envelope,"matches_original_store_readback":loaded.get("ok",false) and saved==current,"physics_frame":Engine.get_physics_frames()}
            if config.region=="I4": disk_readback["world_region"]=saved.world.region_id
            return {"ok":disk_readback.matches_original_store_readback and not envelope.is_empty(),"code":"independent_original_Store_reader"}
        "place_guest_pickup": return _place_guest()
        "place_i4_guest": return _place_i4_guest()
        "lock_cargo":
            if config.role!="guest" or config.region!="I3": return {"ok":false,"code":"i3_guest_only"}
            session.network.send_action("lock",{"target_id":Cargo.CARGO})
            return {"ok":true,"code":"original_reliable_lock"}
        "g_cargo":
            if config.role!="guest" or config.region!="I3" or session.locks.get(session.network.local_id())!=Cargo.CARGO: return {"ok":false,"code":"received_real_cargo_lock_required"}
            var event := InputEventKey.new()
            event.physical_keycode = KEY_G
            event.pressed = true
            session._unhandled_input(event)
            return {"ok":true,"code":"original_G_input"}
        "shutdown": return {"ok":true,"code":"ordinary_save_and_exit"}
    return {"ok":false,"code":"unknown_command"}

func _place_i4_guest() -> Dictionary:
    if config.role!="host" or config.region!="I4" or session.region_id!="I4" or session.network.guests.size()!=1 or session.simulation_paused: return {"ok":false,"code":"one_real_active_I4_guest_required"}
    var peer: int=int(session.network.guests.keys()[0])
    if not session.players.has(peer) or not initial_qa_pose.is_empty(): return {"ok":false,"code":"single_initial_player_fixture_required"}
    var actor: FlightBodyV2=session.players[peer]
    if not actor.cargo_items.is_empty(): return {"ok":false,"code":"unloaded_player_required"}
    var at:=Vector3(20,12,1.8)
    var shape: CollisionShape3D=actor.get_node("Envelope")
    var query:=PhysicsShapeQueryParameters3D.new()
    query.shape=shape.shape; query.transform=Transform3D(Basis.IDENTITY,at)*shape.transform
    query.exclude=[actor.get_rid()]; query.collision_mask=1|2|4|8|32
    if not session.world.get_world_3d().direct_space_state.intersect_shape(query,1).is_empty(): return {"ok":false,"code":"actual_initial_I4_player_hull_obstructed"}
    actor.global_transform=Transform3D(Basis.IDENTITY,at); actor.force_update_transform()
    PhysicsServer3D.body_set_state(actor.get_rid(),PhysicsServer3D.BODY_STATE_TRANSFORM,actor.global_transform)
    actor.linear_velocity=Vector3.ZERO; actor.angular_velocity=Vector3.ZERO; actor.hold_height=at.y; actor.safe_position=at
    initial_qa_pose={"peer":peer,"identity":session.identities[peer],"position":[at.x,at.y,at.z],"scope":"one initial unloaded PLAYER-only native hull-checked I4 observation pose; not flown route; no clock/phase/HP/Story/cache/HUD writes"}
    return {"ok":true,"code":"initial_I4_player_observation_pose","fixture":initial_qa_pose}

func _place_guest() -> Dictionary:
    if config.role!="host" or config.region!="I3" or session.network.guests.size()!=1: return {"ok":false,"code":"one_real_i3_guest_required"}
    var peer: int = int(session.network.guests.keys()[0])
    if not session.players.has(peer): return {"ok":false,"code":"real_guest_actor_required"}
    var actor: FlightBodyV2 = session.players[peer]
    if not actor.cargo_items.is_empty() or not initial_qa_pose.is_empty(): return {"ok":false,"code":"initial_unloaded_pose_only"}
    var at := Vector3(-10,4.1,18) # Same physically checked empty-hook observation fixture.
    var shape: CollisionShape3D = actor.get_node("Envelope")
    var query := PhysicsShapeQueryParameters3D.new()
    query.shape = shape.shape
    query.transform = Transform3D(Basis.IDENTITY,at)*shape.transform
    query.exclude = [actor.get_rid()]
    query.collision_mask = Cargo.MASK
    if not session.world.get_world_3d().direct_space_state.intersect_shape(query,1).is_empty(): return {"ok":false,"code":"actual_initial_player_hull_obstructed"}
    actor.global_transform = Transform3D(Basis.IDENTITY,at)
    actor.force_update_transform()
    PhysicsServer3D.body_set_state(actor.get_rid(),PhysicsServer3D.BODY_STATE_TRANSFORM,actor.global_transform)
    actor.linear_velocity = Vector3.ZERO
    actor.angular_velocity = Vector3.ZERO
    actor.hold_height = at.y
    actor.safe_position = at
    initial_qa_pose = {"peer":peer,"position":[at.x,at.y,at.z],"scope":"one initial unloaded PLAYER-only clear observation pose; no cargo/joint/holder state written"}
    return {"ok":true,"code":"initial_unloaded_player_pose","fixture":initial_qa_pose}

func _accepted_evidence() -> Dictionary:
    var evidence := {"sequence":session.received_sequence,"physics_frame":Engine.get_physics_frames(),"process_frame":Engine.get_process_frames(),"paused":session.simulation_paused,"region":session.region_id,"facilities_ready":session._facilities_ready(),"canal_epoch":session._expected_canal_epoch,"canal":_canal_probe(),"cargo":_cargo_probe()}
    if config.region=="I4": evidence["i4"]=_i4_evidence()
    if config.loadout_case: evidence["loadout"] = _loadout_probe()
    if config.loadout_variant=="HBA_BURST": evidence["weapon_owner"] = _weapon_owner_probe()
    return evidence

func _prepare_local_loadout() -> Dictionary:
    if not loadout_setup.is_empty(): return {"ok":false,"code":"setup_once"}
    if session.active or session.network.mode!="solo" or not session.players.is_empty(): return {"ok":false,"code":"inactive_hangar_required"}
    var spec: Dictionary = LOADOUTS[config.label]
    var before: Dictionary = session.store.snapshot()
    var world_before: Dictionary = before.world.duplicate(true)
    var fixture: Dictionary = {}
    var fixture_discoveries: Array = [spec.discovery]
    if config.loadout_variant=="HBA_BURST" and config.label in ["guest_first","guest_reconnect"]:
        fixture_discoveries.append_array(["boss:F2:mirrorwing_warden","I3:cooling_overdraft"])
    if config.label=="guest_reconnect":
        if spec.discovery not in before.personal.discoveries: return {"ok":false,"code":"original_guest_unlock_missing"}
        for discovery: String in fixture_discoveries:
            if discovery not in before.personal.discoveries: return {"ok":false,"code":"original_guest_variant_unlock_missing:"+discovery}
    else:
        # Personal-only ownership fixture; no earned Boss/Story/world claim.
        fixture = {"id":"qa-lan-loadout-unlock:"+config.run_id+":"+config.role,"append":{"personal.discoveries":fixture_discoveries}}
        var unlocked: Dictionary = session.store.commit(fixture)
        if not unlocked.get("ok",false): return {"ok":false,"code":"unlock_fixture_store","detail":unlocked}
    var saved_before: Dictionary = session.store.snapshot()
    if saved_before.world!=world_before or saved_before.profile_id!=local_uuid: return {"ok":false,"code":"fixture_changed_world_or_identity"}
    session.interface.action_requested.emit("hangar",{})
    var panel = session.interface.hangar
    if not panel.visible or panel._active: return {"ok":false,"code":"original_hangar_not_editable"}
    var frame_index := -1
    for index: int in panel._frames.item_count:
        if panel._frames.get_item_metadata(index)==spec.frame: frame_index=index
    if frame_index<0: return {"ok":false,"code":"frame_option_missing"}
    panel._frames.select(frame_index)
    panel._frames.item_selected.emit(frame_index)
    var desired := {"weapon":"pulse_base","tool":"scan_base","drive":spec.drive,"battery":"stock_battery","utility":spec.utility}
    if config.loadout_variant=="HBA_BURST" and config.label=="guest_first":
        desired.weapon = "burst_capacitor"
        desired.utility = "cooling_duct"
    for slot: String in Catalog.SLOT_ORDER:
        var picker: OptionButton = panel._slots[slot]
        var option_index := -1
        for index: int in picker.item_count:
            if picker.get_item_metadata(index)==desired[slot] and not picker.is_item_disabled(index): option_index=index
        if option_index<0 or picker.disabled: return {"ok":false,"code":"owned_compatible_option_missing:"+slot}
        picker.select(option_index)
        picker.item_selected.emit(option_index) # Original UI updates/validates its draft.
    var checked: Dictionary = Hangar.validate(saved_before,panel._draft)
    if not checked.get("ok",false) or panel._save.disabled: return {"ok":false,"code":"original_hangar_rejected","detail":checked}
    panel._save.pressed.emit() # _request_save -> save_requested -> Session -> Store.
    var current: Dictionary = session.store.snapshot()
    var reader := Store.new(session.store.root_path)
    var loaded: Dictionary = reader.load_profile()
    var selected: Dictionary = Hangar.launch_build(reader.snapshot()) if loaded.get("ok",false) else {}
    var wire: Dictionary = BuildContract.view(checked.build)
    var expected := {"airframe_id":spec.frame,"slots":desired}
    if not selected.get("ok",false) or reader.snapshot()!=current or current.profile_id!=local_uuid or current.world!=world_before or current.personal.discoveries!=saved_before.personal.discoveries or int(current.generation)!=int(saved_before.generation)+1 or not BuildContract.matches(selected.build,expected) or wire!=expected:
        return {"ok":false,"code":"original_hangar_save_readback_mismatch","detail":loaded}
    if spec.frame=="ag03" and Catalog.resolve_build(selected.build,2.0).valid: return {"ok":false,"code":"A_must_not_accept_saved_2kg"}
    if config.label=="guest_first" and not Catalog.resolve_build(selected.build,2.0).valid: return {"ok":false,"code":"B_must_accept_original_2kg"}
    loadout_setup = {"prepared":true,"scope":"isolated personal unlock fixture; original native Hangar controls/Store/menu departure; not earned campaign or physical controller input",
        "fixture":fixture,"fixture_discovery":spec.discovery,"fixture_discoveries":fixture_discoveries.duplicate(),"initial_uuid":local_uuid,"before_generation":before.generation,"save_before_generation":saved_before.generation,"saved_generation":current.generation,
        "world_unchanged":current.world==world_before,"personal_discoveries":current.personal.discoveries.duplicate(),"native_build":selected.build.duplicate(true),"hardware":wire,
        "reader_equal":reader.snapshot()==current,"ui_status":panel._status.text,"A_rejects_2kg":not Catalog.resolve_build(selected.build,2.0).valid,
        "network_started_at_save":network_started,"network_mode_at_save":session.network.mode,"physics_frame":Engine.get_physics_frames(),"process_frame":Engine.get_process_frames()}
    session.interface.action_requested.emit("hangar_close",{})
    return {"ok":true,"code":"original_local_hangar_saved"}

func _loadout_probe() -> Dictionary:
    var roster: Dictionary = {}
    for peer: int in session.players:
        var actor: FlightBodyV2 = session.players[peer]
        var wire: Dictionary = BuildContract.view(actor.build)
        var first: Dictionary = BuildContract.validate(wire)
        var cached: Dictionary = BuildContract.validate(wire)
        var resolved: Dictionary = Catalog.resolve_build(actor.build)
        var envelope: CollisionShape3D = actor.get_node_or_null("Envelope")
        var expected_size := Vector3(float(actor.stats.get("width_m",0)),float(actor.stats.get("height_m",0)),float(actor.stats.get("length_m",0)))
        var shape_valid: bool = envelope!=null and envelope.shape is BoxShape3D and envelope.shape.size.is_equal_approx(expected_size)
        var native_shape := false
        if shape_valid:
            for index: int in PhysicsServer3D.body_get_shape_count(actor.get_rid()):
                if PhysicsServer3D.body_get_shape(actor.get_rid(),index)==envelope.shape.get_rid(): native_shape=true
        var native_mass: float = PhysicsServer3D.body_get_param(actor.get_rid(),PhysicsServer3D.BODY_PARAM_MASS)
        var stats_match: bool = resolved.get("valid",false) and first.get("ok",false) and cached.get("ok",false) and actor.stats==resolved.derived and cached.resolved.derived==resolved.derived and first==cached
        var observed: Dictionary = {}
        for key: String in ["mass_kg","power_pu","capacity_pu","speed_mps","accel_mps2","brake_mps2","width_m","height_m","length_m","cargo_rating_kg","thrust_n","build_hash"]: observed[key]=actor.stats.get(key)
        var body_valid: bool = stats_match and shape_valid and native_shape and PhysicsServer3D.body_get_space(actor.get_rid())==session.world.get_world_3d().space and is_equal_approx(actor.mass,float(actor.stats.mass_kg)) and is_equal_approx(native_mass,actor.mass) and is_equal_approx(actor.maximum_health,float(resolved.derived.health))
        roster[str(peer)] = {"identity":session.identities.get(peer,""),"body_id":actor.get_instance_id(),"hardware":wire,"native_build":actor.build.duplicate(true),"derived":observed,
            "catalog_and_cached_status_match":stats_match,"actual_body_matches":body_valid,"native_mass_kg":native_mass,"cargo_kg":actor.cargo_kg,"maximum_health":actor.maximum_health,"maximum_armor":actor.damage_state.get("maximum_armor",-1),"native_shape_matches":shape_valid and native_shape}
    var announced: Dictionary = {}
    for peer in session.network.guest_builds: announced[str(peer)] = BuildContract.view(session.network.guest_builds[peer])
    var applied: Dictionary = {}
    for peer in session.remote_targets:
        var row: Dictionary = session.remote_targets[peer]
        if row.get("build") is Dictionary: applied[str(peer)] = row.build.duplicate(true)
    var selected: Dictionary = Hangar.launch_build(session.store.snapshot())
    var saved: Dictionary = session.world_cache.world.get("environment",{}).get("I3_thermal_cargo",{}) if session.network.is_authority() else {}
    return {"setup":loadout_setup.duplicate(true),"catalog_sha256":BuildContract.fingerprint(),"departure_hardware":BuildContract.view(session._departure_build),
        "local_profile_hardware":BuildContract.view(selected.build) if selected.get("ok",false) else {},"players":roster,"announced_guest_hardware":announced,"applied_snapshot_hardware":applied,
        "saved_role_identity":saved.get("role_identity",""),"saved_role_native_build":saved.get("flight",{}).get("build",{}).duplicate(true)}

func _weapon_owner_probe() -> Dictionary:
    # Observe the original manager/Label/body only. Never bind a Cycle, receive
    # a synthetic event, hold fire, set heat or manufacture an idle view.
    var rows: Dictionary = {}
    for peer: int in session.players:
        var actor: FlightBodyV2 = session.players[peer]
        var mods: Dictionary = actor.stats.get("modifiers",{})
        rows[str(peer)] = {"identity":session.identities.get(peer,""),"hardware":BuildContract.view(actor.build),
            "build_hash":str(actor.stats.build_hash),"body_heat":actor.heat,"capacity":actor.max_heat,
            "held_fire":bool(actor.command.get("fire",false)),"view":session.weapons.presentation(peer),
            "actual_weapon_modifiers":{"damage":mods.get("weapon_damage"),"interval_s":mods.get("weapon_interval_s"),
                "charge_s":mods.get("weapon_charge_s"),"heat_per_shot":mods.get("weapon_heat"),
                "cooling_multiplier":mods.get("cooling_multiplier"),"heat_dissipation_ps":mods.get("heat_dissipation_ps")}}
    var local: int = session.network.local_id()
    var label: Label = session.interface.weapon_status
    return {"rows":rows,"local_peer":local,"authority":session.network.is_authority(),
        "session_id":session.network.session_id if session.network.is_authority() else session.received_session,
        "region":session.region_id,"boss_active":session.boss_active,"manager_local_cycles":session.weapons._cycles.size(),
        "host_serial":session.weapons._serial,"accepted_remote_serial":session.weapons._remote_serial,
        "accepted_remote_session":session.weapons._remote_session,
        "hud_text":label.text,"manager_hud_text":session.weapons.hud(local) if session.players.has(local) else "",
        "hud_node_path":str(label.get_path()),"hud_visible":label.is_visible_in_tree(),
        "physics_frame":Engine.get_physics_frames(),"process_frame":Engine.get_process_frames()}

func _canal_probe() -> Dictionary:
    if session.region_id!="I2" or session.network.is_authority(): return {}
    var replica = session.canal_replica
    var status: Dictionary = replica.status()
    var native_ok: bool = status.installed and status.ready and status.body_count>0 and status.target_count==6 and session.canal==null
    var shape_count := 0
    var maximum_pose_error := 0.0
    var issues: Array = []
    for path: String in replica._bodies:
        var body: StaticBody3D = replica._bodies[path]
        var rid: RID = body.get_rid()
        var expected: Array = []
        for child: Node in body.get_children():
            if child is CollisionShape3D: expected.append(str(child.shape.get_rid()))
        var actual: Array = []
        for index: int in PhysicsServer3D.body_get_shape_count(rid): actual.append(str(PhysicsServer3D.body_get_shape(rid,index)))
        expected.sort(); actual.sort()
        var pose: Transform3D = PhysicsServer3D.body_get_state(rid,PhysicsServer3D.BODY_STATE_TRANSFORM)
        var difference: float = maxf(pose.origin.distance_to(body.global_position),maxf(pose.basis.x.distance_to(body.global_basis.x),maxf(pose.basis.y.distance_to(body.global_basis.y),pose.basis.z.distance_to(body.global_basis.z))))
        maximum_pose_error = maxf(maximum_pose_error,difference)
        var valid: bool = not expected.is_empty() and expected==actual and PhysicsServer3D.body_get_space(rid)==session.world.get_world_3d().space and PhysicsServer3D.body_get_collision_layer(rid)==body.collision_layer and PhysicsServer3D.body_get_collision_mask(rid)==body.collision_mask
        native_ok = native_ok and valid
        shape_count += actual.size()
        if not valid: issues.append(path)
    native_ok = native_ok and maximum_pose_error<=.002
    return {"status":status,"native_ok":native_ok,"native_shape_count":shape_count,"maximum_pose_error_m":maximum_pose_error,"native_issues":issues,"client_authority_adapter_absent":session.canal==null}

func _cargo_probe() -> Dictionary:
    if session.region_id!="I3" or not is_instance_valid(session.world) or not session.world.objects.get(Cargo.CARGO) is RigidBody3D: return {}
    var body: RigidBody3D = session.world.objects[Cargo.CARGO]
    var count := 0
    for candidate: Node in session.world.find_children("*","RigidBody3D",true,false):
        if candidate.get_meta("entity_id","")==Cargo.CARGO: count+=1
    var carried: Array = []
    var local: int = session.network.local_id()
    for peer: int in session.players:
        var actor: FlightBodyV2 = session.players[peer]
        if not actor.cargo_items.has(Cargo.CARGO): continue
        var item: Dictionary = actor.cargo_items[Cargo.CARGO]
        var joint: PinJoint3D = item.get("joint") as PinJoint3D
        carried.append({"peer":peer,"identity":session.identities.get(peer,""),"body_id":actor.get_instance_id(),"mass_kg":actor.cargo_kg,"actual_body":item.get("body")==body,"joint_valid":joint!=null and joint.get_rid().is_valid() and joint.get_node_or_null(joint.node_a)==actor and joint.get_node_or_null(joint.node_b)==body})
    var participant = session.thermal_cargo
    var module: RefCounted = participant.module
    var saved: Dictionary = session.store.snapshot().world.get("environment",{}).get("I3_thermal_cargo",{}) if session.network.is_authority() else {}
    var native_presentation: bool = not session.network.is_authority() and module==null and body.freeze and body.get_meta("thermal_remote_presentation",false) and PhysicsServer3D.body_get_space(body.get_rid())==session.world.get_world_3d().space and PhysicsServer3D.body_get_shape_count(body.get_rid())>0 and PhysicsServer3D.body_get_collision_layer(body.get_rid())==8 and PhysicsServer3D.body_get_collision_mask(body.get_rid())==Cargo.MASK
    return {"unique_body_count":count,"body_id":body.get_instance_id(),"mass_kg":body.mass,"native":Cargo._body_snapshot(body),"frozen":body.freeze,"visible":body.visible,"carried":carried,"module":module.status() if module!=null else {},"presentation":participant._presentation.duplicate(true),"native_presentation_ok":native_presentation,"local_actor_loaded_presentation":participant.remote_loaded_actor(session.players.get(local)),"local_cargo_kg":session.players[local].cargo_kg if session.players.has(local) else 0.0,"saved_version":saved.get("version",0),"saved_role_identity":saved.get("role_identity",""),"saved_state":saved,"client_module_absent":module==null}

func _state() -> Dictionary:
    var players: Dictionary = {}
    for peer: int in session.players:
        var actor: FlightBodyV2 = session.players[peer]
        players[str(peer)] = {"identity":session.identities.get(peer,""),"body_id":actor.get_instance_id(),"position":[actor.global_position.x,actor.global_position.y,actor.global_position.z],"frozen":actor.freeze,"cargo_kg":actor.cargo_kg}
    var proposal: Dictionary = session.consensus.current_proposal() if session.network.is_authority() else session.choice_proposal
    var uuid: String = str(session.store.snapshot().profile_id)
    return {"suite":SUITE,"contract":CONTRACT,"run_id":config.run_id,"role":config.role,"label":config.label,"target_region":config.region,"profile":config.profile,"profile_uuid":uuid,"initial_uuid":local_uuid,"actual_package":not OS.has_feature("editor"),"executable":OS.get_executable_path(),"pid":OS.get_process_id(),"protocol":session.network.PROTOCOL,"network_mode":session.network.mode,"active":session.active,"region":session.region_id,"host_ready":host_ready,"facilities_ready":session._facilities_ready() if is_instance_valid(session.world) else false,"session_id":session.network.session_id if session.network.is_authority() else session.received_session,"received_sequence":session.received_sequence,"stats":session.stats.duplicate(true),"transport":session.network.telemetry.duplicate(true),"players":players,"local_peer":session.network.local_id(),"locks":session.locks.duplicate(true),"paused":session.simulation_paused,"proposal":proposal,"first_accepted":first_accepted,"first_paused":first_paused,"latest_accepted":latest_accepted,"canal":session.canal.status() if session.canal!=null else _canal_probe(),"cargo":_cargo_probe(),"generation":session.store.snapshot().generation,"last_commit":session.last_commit_result.duplicate(true),"save_request":last_save_request,"save_callbacks":save_callbacks,"disk_readback":disk_readback,"story_completed":session.story.state.get("completed",[]).duplicate(),"initial_player_pose_fixture":initial_qa_pose,"ack":ack,"result":result,"commands":commands,"errors":errors+logger.errors,"message":session.interface.message.text,"wall_seconds":float(Time.get_ticks_usec()-started_usec)/1000000.0}

func _write_state() -> void:
    if config.is_empty() or session==null: return
    var path: String = config.evidence.path_join(config.label+"-state.json")
    var file := FileAccess.open(path+".tmp",FileAccess.WRITE)
    if file==null: return
    var observed: Dictionary = _state()
    observed["loadout_case"] = config.loadout_case
    observed["loadout_variant"] = config.loadout_variant
    if config.loadout_variant=="HBA_BURST": observed["weapon_owner"] = _weapon_owner_probe()
    if config.loadout_case: observed["loadout"] = _loadout_probe()
    observed["network_started"] = network_started
    if config.region=="I4": observed["i4"]=_i4_evidence()
    observed["controller_lease"] = {"last_good":last_good_controller.duplicate(true),"diagnostic":controller_diagnostic.duplicate(true),"read_failures":controller_read_failures,"transitions":controller_transitions.duplicate(true)}
    file.store_string(JSON.stringify(observed))
    file.close()
    DirAccess.rename_absolute(path+".tmp",path) # Transient sharing violation: preserve prior complete state; next poll retries.

static func _read_json(path: String) -> Dictionary:
    if not FileAccess.file_exists(path): return {}
    var file := FileAccess.open(path,FileAccess.READ)
    if file==null or file.get_length()>1048576: return {}
    var value: Variant = JSON.parse_string(file.get_as_text())
    file.close()
    return value if value is Dictionary else {}

func _fail(code: String) -> void:
    if code not in errors: errors.append(code)
    print("LAN_ENVIRONMENT_QA_ERROR ",code)

func _shutdown() -> void:
    if finishing: return
    finishing = true
    _write_state()
    session._quit() # Original guest close or host asynchronous SaveGate/Store exit.
