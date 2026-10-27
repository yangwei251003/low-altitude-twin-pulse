extends SceneTree
## Actual ordinary MAIN/I1; synthetic JoypadButton delivery at Session's input
## entry. Only selected device, neutral/brake input and clear PLAYER poses are QA.
const MAIN = preload("res://scenes/v3/main.tscn")
const Store = preload("res://scripts/v3/core/twin_world_store.gd")
const DEVICE := 27
const THERMAL := "I1:thermal"
const BRIEF := "I1:rescue:brief"

class ErrorLogger extends Logger:
    var guard := Mutex.new()
    var errors: Array = []
    func _log_error(function: String, file: String, line: int, code: String, rationale: String, _notify: bool, kind: int, _trace: Array[ScriptBacktrace]) -> void:
        if kind == Logger.ERROR_TYPE_WARNING: return
        guard.lock()
        errors.append({"function":function,"file":file,"line":line,"code":code,"rationale":rationale})
        guard.unlock()

var logger := ErrorLogger.new()
var session: Node
var profile := ""
var output := ""
var checks: Array = []
var actions: Array = []
var events: Array = []
var inputs: Array = []
var poses: Array = []
var stores: Dictionary = {}
var finished := false
var began := 0

func _initialize() -> void:
    OS.add_logger(logger)
    _run.call_deferred()

func _run() -> void:
    for arg: String in OS.get_cmdline_user_args():
        if arg.begins_with("--qa-profile="): profile = arg.trim_prefix("--qa-profile=")
        if arg.begins_with("--output="): output = arg.trim_prefix("--output=")
    if not profile.begins_with("qa_controller_session_") or profile != profile.validate_filename() or DirAccess.dir_exists_absolute("user://profiles_v3/"+profile) or not output.begins_with("res://artifacts/v3/controller-session-actions-") or ".." in output or DirAccess.dir_exists_absolute(output):
        quit(2)
        return
    began = Time.get_ticks_msec()
    DirAccess.make_dir_recursive_absolute(output)
    create_timer(32.0).timeout.connect(func():
        if not finished:
            _check(false,"32 second ordinary MAIN integration bound; owned runner limit40s",_diagnostics())
            _finish())
    session = MAIN.instantiate()
    root.add_child(session)
    if not _check(session.profile_ready and session.has_method("_controller_button") and session.interface.has_method("_update_controller_focus"),"new original Store and production controller Session/UI APIs are available",_diagnostics()): _finish(); return
    session.network.action_received.connect(func(peer: int, verb: String, payload: Dictionary):
        actions.append({"peer":peer,"verb":verb,"payload":payload.duplicate(true),"physics_frame":Engine.get_physics_frames()}))
    session.network.event_received.connect(func(event: Dictionary):
        events.append({"event":event.duplicate(true),"physics_frame":Engine.get_physics_frames()}))
    if not _check(session.start_flight("solo") and session.region_id == "I1" and session.world.build_errors.is_empty(),"ordinary empty-profile MAIN starts real I1 without Director, entity or world fixtures",_diagnostics()): _finish(); return
    session.inputs.legacy.device = DEVICE # Explicit virtual selected-device fixture.
    session.inputs.test_enabled = true
    session.inputs.test_frame = {"axes":{},"held":["brake"],"edges":[]}
    await _frame()
    await _frame()
    if finished: return
    stores["initial"] = session.store.snapshot()
    if not _check(BRIEF not in session.story.state.get("completed",[]) and session.story.ready and session.entities.has(THERMAL),"actual new Story is uncompleted and real thermal target exists",_diagnostics()): _finish(); return
    if not _filters_and_selection(): _finish(); return
    if not await _thermal_actions(): _finish(); return
    if not _modal_guards(): _finish(); return
    if not await _story_button(): _finish(); return
    if not await _pause_button(): _finish(); return
    if not _disk_readback(): _finish(); return
    _finish()

func _filters_and_selection() -> bool:
    var before: Dictionary = _logical_input_state()
    for button: int in [JOY_BUTTON_RIGHT_SHOULDER,JOY_BUTTON_Y,JOY_BUTTON_RIGHT_STICK,JOY_BUTTON_LEFT_STICK,JOY_BUTTON_B,JOY_BUTTON_LEFT_SHOULDER,JOY_BUTTON_DPAD_LEFT,JOY_BUTTON_DPAD_RIGHT,JOY_BUTTON_START,JOY_BUTTON_BACK]:
        _joy(button,true,DEVICE+1)
        _joy(button,false,DEVICE)
    if not _check(_logical_input_state() == before,"other device presses and selected-device releases cannot lock, act, select, pause or open a menu",{"before":before,"after":_logical_input_state()}): return false
    _joy(JOY_BUTTON_LEFT_SHOULDER)
    if not _check(session.interface.selected == 9 and session.selected_ability == "takeover","LB selects previous ability with wrap across all ten original tools",_logical_input_state()): return false
    _joy(JOY_BUTTON_DPAD_RIGHT)
    var visited: Array = []
    for unused in 10:
        visited.append(session.selected_ability)
        _joy(JOY_BUTTON_DPAD_RIGHT)
    if not _check(visited == session.Interface.ABILITIES and session.interface.selected == 0,"D-pad right visits all ten authored abilities exactly once and wraps",visited): return false
    _joy(JOY_BUTTON_DPAD_LEFT)
    _joy(JOY_BUTTON_DPAD_RIGHT)
    return _check(session.interface.selected == 0 and actions.is_empty() and session.interface.controller_navigation,"D-pad left reverses selection; selection uses no gameplay action and valid joy event enables UI navigation",_logical_input_state())

func _thermal_actions() -> bool:
    if not await _near(THERMAL,3.4): return false
    for unused in 4: _joy(JOY_BUTTON_DPAD_RIGHT)
    if not _check(session.selected_ability == "heat","heat is selected through controller cycling rather than assigning Session state",_logical_input_state()): return false
    var lock_start: int = actions.size()
    for unused in session.entities.size()+1:
        _joy(JOY_BUTTON_RIGHT_SHOULDER)
        if session.locks.get(1) == THERMAL: break
    var locked: bool = session.locks.get(1) == THERMAL
    for action: Dictionary in actions.slice(lock_start): locked = locked and action.verb == "lock" and action.peer == 1
    if not _check(locked and actions.size()>lock_start,"RB cycles actual nearby candidates and original Network.send_action locks the real thermal target",actions.slice(lock_start)): return false
    var actor_id: String = session._actor_id(1)
    var old: Dictionary = session.entities[THERMAL].duplicate(true)
    var energy: float = float(session.entities[actor_id].energy)
    var accepted: int = int(session.stats.abilities)
    _joy(JOY_BUTTON_Y)
    if not _check(session.stats.abilities == accepted+1 and float(session.entities[THERMAL].temperature) == float(old.temperature)+25.0 and float(session.entities[actor_id].energy) == energy-8.0 and actions.back().verb == "ability" and actions.back().payload.get("mode","") == "","Y passes an original ability action and heat rule really adds 25C for 8 energy",{"before":old,"after":session.entities[THERMAL].duplicate(true),"energy_before":energy,"energy_after":session.entities[actor_id].energy,"event":actions.back()}): return false
    var rejected: int = session.stats.rejected_abilities
    var state: Dictionary = _rule_state()
    _joy(JOY_BUTTON_Y)
    if not _check(session.stats.rejected_abilities == rejected+1 and _rule_state() == state,"immediate repeat reaches original cooldown rejection without changing actual rule state",{"state":state,"after":_rule_state(),"message":session.interface.message.text}): return false
    if not await _cooldown(): return false
    old = session.entities[THERMAL].duplicate(true)
    energy = float(session.entities[actor_id].energy)
    accepted = session.stats.abilities
    _joy(JOY_BUTTON_RIGHT_STICK)
    if not _check(session.stats.abilities == accepted+1 and float(session.entities[THERMAL].temperature) == float(old.temperature)-25.0 and float(session.entities[actor_id].energy) == energy-8.0 and actions.back().payload.get("mode") == "cool","right-stick press uses the original reverse heat mode and really removes 25C for 8 energy",{"before":old,"after":session.entities[THERMAL].duplicate(true),"event":actions.back()}): return false
    if not await _cooldown() or not await _near(THERMAL,18.0): return false
    state = _rule_state()
    rejected = session.stats.rejected_abilities
    _joy(JOY_BUTTON_Y)
    return _check(session.stats.rejected_abilities == rejected+1 and _rule_state() == state,"controller ability beyond original 12m range is rejected without temperature, energy or revision mutation",{"state":state,"after":_rule_state(),"distance":session.players[1].global_position.distance_to(session.entities[THERMAL].position),"message":session.interface.message.text})

func _modal_guards() -> bool:
    _joy(JOY_BUTTON_BACK)
    if not _check(session.interface.menu.visible,"BACK opens actual ordinary menu without sending a gameplay action",_logical_input_state()): return false
    if not _guard_panel(session.interface.menu,"menu",true): return false
    _joy(JOY_BUTTON_BACK)
    if not _check(not session.interface.menu.visible,"BACK closes ordinary menu",_logical_input_state()): return false
    # Visibility-only UI context fixtures; no fake proposal, participants,
    # chapter choice, transport event or authoritative result is installed.
    for pair: Array in [[session.interface.vote,"vote"],[session.interface.wheel,"ability wheel"],[session.interface.travel,"travel"],[session.interface.chapter_choice,"chapter choice"]]:
        var panel: Control = pair[0]
        panel.show()
        if not _guard_panel(panel,str(pair[1]),false): panel.hide(); return false
        panel.hide()
    session.interface._update_controller_focus()
    var flight_focus: Array = _focus_rows(session.interface)
    var no_focus := true
    for row: Dictionary in flight_focus:
        if row.visible and row.focus_mode != Control.FOCUS_NONE: no_focus = false
    return _check(no_focus,"leaving modal context removes button focus from flight HUD",flight_focus)

func _guard_panel(panel: Control,label: String,require_buttons: bool) -> bool:
    session.interface._update_controller_focus()
    var before: Dictionary = _logical_input_state()
    var rules_before: Dictionary = _rule_state()
    for button: int in [JOY_BUTTON_Y,JOY_BUTTON_RIGHT_STICK,JOY_BUTTON_LEFT_STICK,JOY_BUTTON_RIGHT_SHOULDER,JOY_BUTTON_LEFT_SHOULDER,JOY_BUTTON_DPAD_LEFT,JOY_BUTTON_DPAD_RIGHT,JOY_BUTTON_B,JOY_BUTTON_START]: _joy(button)
    var preserved: bool = _logical_input_state() == before and _rule_state() == rules_before
    if not _check(preserved,label+" context cannot leak ability/lock/investigate/pause/selection into flight",{"before":before,"after":_logical_input_state(),"rule_before":rules_before,"rule_after":_rule_state()}): return false
    var rows: Array = _focus_rows(panel)
    var enabled_count := 0
    var focus_valid := true
    for row: Dictionary in rows:
        if row.visible and not row.disabled:
            enabled_count += 1
            focus_valid = focus_valid and row.focus_mode == Control.FOCUS_ALL
    return _check(focus_valid and (not require_buttons or enabled_count>0),label+" focus matches actual enabled modal buttons (empty panels cover guards only)",{"buttons":rows,"enabled_count":enabled_count})

func _story_button() -> bool:
    var marker: Dictionary = session.story.markers["npc:linlan"]
    var target: Vector3 = session.story._point(marker)
    if not await _place_near_point(target,"npc:linlan",2.6): return false
    if not _check(session.story.nearest(session.players[1].global_position) == "npc:linlan","actual player pose/range/LOS selects Linlan as original G contact",_diagnostics()): return false
    var before: Dictionary = session.store.snapshot()
    var count: int = actions.size()
    _joy(JOY_BUTTON_B)
    var after: Dictionary = session.store.snapshot()
    stores["after_B_brief"] = after
    if not _check(BRIEF in session.story.state.get("completed",[]) and BRIEF in after.world.actions.opening.completed and after.generation == before.generation+1 and actions.size()==count+1 and actions.back().verb == "explore" and actions.back().payload.get("target_id") == "npc:linlan" and session.interface.radio.visible and not session.interface.radio_text.text.is_empty(),"B follows original nearby Story/explore action, durably completes real first brief and opens authored dialogue",{"before_generation":before.generation,"after_generation":after.generation,"event":actions.back() if not actions.is_empty() else {},"dialogue":session.interface.radio_text.text,"story":session.story.state}): return false
    var first_line: String = session.interface.radio_text.text
    var queue_count: int = session.interface.radio_queue.size()
    count = actions.size()
    _joy(JOY_BUTTON_B)
    if not _check(actions.size()==count and session.store.snapshot()==after and (session.interface.radio_text.text!=first_line or not session.interface.radio.visible or session.interface.radio_queue.size()<queue_count),"B advances real dialogue without issuing another explore or repeating its Store transaction",{"first_line":first_line,"next_line":session.interface.radio_text.text,"remaining":session.interface.radio_queue.size()}): return false
    for unused in 16:
        if not session.interface.radio.visible: break
        _joy(JOY_BUTTON_B)
    return _check(not session.interface.radio.visible and session.store.snapshot()==after,"controller can finish authored dialogue without duplicating completion or memory",_diagnostics())

func _pause_button() -> bool:
    var actor: FlightBodyV2 = session.players[1]
    actor.freeze = false # End QA observation hold before ordinary native pause.
    await _frame()
    await _frame()
    if finished: return false
    var sequence: int = session.consensus._sequence
    var count: int = actions.size()
    _joy(JOY_BUTTON_START)
    if not _check(actions.size()==count+1 and actions.back().verb=="propose" and actions.back().payload.get("kind")=="pause" and session.consensus._sequence==sequence+1 and session.consensus.current_proposal().is_empty() and session.simulation_paused and actor.freeze,"Start invokes original Network action and solo Consensus resolves actual native pause",{"event":actions.back(),"diagnostics":_diagnostics()}): return false
    var actual: Transform3D = PhysicsServer3D.body_get_state(actor.get_rid(),PhysicsServer3D.BODY_STATE_TRANSFORM)
    var clock: float = session.world.mechanism_snapshot().get("clock",0.0)
    for unused in 8: await _frame()
    if not _check(PhysicsServer3D.body_get_state(actor.get_rid(),PhysicsServer3D.BODY_STATE_TRANSFORM)==actual and session.world.mechanism_snapshot().get("clock",0.0)==clock,"ordinary paused physics frames preserve native body pose and mechanism clock",_diagnostics()): return false
    _joy(JOY_BUTTON_START)
    return _check(not session.simulation_paused and not actor.freeze and session.consensus._sequence==sequence+2 and session.consensus.current_proposal().is_empty(),"second Start resumes through original Consensus without changing participants",_diagnostics())

func _disk_readback() -> bool:
    stores["final"] = session.store.snapshot()
    var reader := Store.new("user://profiles_v3/"+profile)
    var opened: Dictionary = reader.load_profile()
    stores["independent_reader"] = reader.snapshot() if opened.get("ok",false) else opened
    return _check(opened.get("ok",false) and reader.snapshot() == stores.final and BRIEF in reader.snapshot().world.actions.opening.completed,"independent original Store opens exact controller-authored first Story record",opened)

func _joy(button: int,pressed: bool=true,device: int=DEVICE) -> void:
    var event := InputEventJoypadButton.new()
    event.device = device
    event.button_index = button
    event.pressed = pressed
    var prior: Dictionary = _logical_input_state()
    session._unhandled_input(event)
    inputs.append({"button":button,"pressed":pressed,"device":device,"before":prior,"after":_logical_input_state(),"physics_frame":Engine.get_physics_frames()})

func _logical_input_state() -> Dictionary:
    return {"selection":session.interface.selected,"ability":session.selected_ability,"lock":str(session.locks.get(1,"")),"actions":actions.size(),"abilities":session.stats.abilities,"rejected":session.stats.rejected_abilities,"paused":session.simulation_paused,"proposal":session.consensus.current_proposal(),"menu":session.interface.menu.visible}

func _rule_state() -> Dictionary:
    return {"target":session.entities.get(THERMAL,{}).duplicate(true),"actor":session.entities.get(session._actor_id(1),{}).duplicate(true),"abilities":session.stats.abilities}

func _focus_rows(parent: Node) -> Array:
    var rows: Array = []
    for child: Node in parent.get_children():
        if child is BaseButton: rows.append({"path":str(child.get_path()),"visible":child.is_visible_in_tree(),"disabled":child.disabled,"focus_mode":child.focus_mode})
        rows.append_array(_focus_rows(child))
    return rows

func _cooldown() -> bool:
    for unused in 90:
        if session.cooldowns.get(1,0.0)<=0.0: return true
        await _frame()
        if finished: return false
    return _check(false,"original ability cooldown expires on ordinary MAIN physics",_diagnostics())

func _near(id: String,distance: float) -> bool:
    return await _place_near_point(session.world.objects[id].global_position,id,distance)

func _place_near_point(target: Vector3,id: String,distance: float) -> bool:
    for direction: Vector3 in [Vector3.UP,Vector3.FORWARD,Vector3.BACK,Vector3.LEFT,Vector3.RIGHT]:
        var at: Vector3 = target+direction*distance
        if not _clear_pose(at) or not session._line_clear(at,target,session.players[1].get_rid(),id): continue
        var actor: FlightBodyV2 = session.players[1]
        actor.freeze = true
        actor.global_transform = Transform3D(Basis.IDENTITY,at)
        actor.force_update_transform()
        PhysicsServer3D.body_set_state(actor.get_rid(),PhysicsServer3D.BODY_STATE_TRANSFORM,actor.global_transform)
        actor.linear_velocity = Vector3.ZERO
        actor.angular_velocity = Vector3.ZERO
        actor.hold_height = at.y
        poses.append({"target":id,"distance":distance,"position":[at.x,at.y,at.z],"kind":"explicit QA PLAYER-only frozen observation; actual hull/range/LOS checked"})
        await _frame()
        return not finished
    return _check(false,"actual geometry permits clear QA player observation near "+id,{"distance":distance,"target":str(target),"diagnostics":_diagnostics()})

func _clear_pose(at: Vector3) -> bool:
    if not session.Regions.contains("I1",at): return false
    var actor: FlightBodyV2 = session.players[1]
    var shape: CollisionShape3D = actor.get_node("Envelope")
    var query := PhysicsShapeQueryParameters3D.new()
    query.shape = shape.shape
    query.transform = Transform3D(Basis.IDENTITY,at)*shape.transform
    query.collision_mask = 1|2|8|32
    query.exclude = [actor.get_rid()]
    return session.world.get_world_3d().direct_space_state.intersect_shape(query,1).is_empty()

func _frame() -> void:
    await physics_frame
    await process_frame # Original MAIN owns every rule/physics clock.

func _diagnostics() -> Dictionary:
    if not is_instance_valid(session): return {"session":"not_installed"}
    return {"profile_ready":session.profile_ready,"active":session.active,"region":session.region_id,"mode":session.network.mode,"selected_device":session.inputs.legacy.device,"message":session.interface.message.text,"generation":session.store.snapshot().get("generation",-1),"story":session.story.state.duplicate(true),"stats":session.stats.duplicate(true),"pause":session.simulation_paused,"proposal":session.consensus.current_proposal(),"controller_api":session.has_method("_controller_button"),"world_errors":session.world.build_errors if is_instance_valid(session.world) else []}

func _check(ok: bool,label: String,actual: Variant=null) -> bool:
    checks.append({"passed":ok,"label":label,"actual":actual})
    return ok

func _finish() -> void:
    if finished: return
    finished = true
    var failures: Array = checks.filter(func(row: Dictionary): return not row.passed)
    var report := {"checks":checks,"failures":failures,"engine_errors":logger.errors,"actions":actions,"events":events,"injected_buttons":inputs,"player_pose_fixtures":poses,"stores":stores,"diagnostics":_diagnostics(),"wall_seconds":float(Time.get_ticks_msec()-began)/1000.0,"scope":"Actual ordinary empty-profile MAIN/I1. Synthetic InputEventJoypadButton events are delivered directly to Session._unhandled_input, then production controller routing and original Network.send_action authority signal. Selected device27 and neutral/brake input are explicit QA; collision-checked player-only observation holds/poses are not flown navigation. Modal visibility fixtures test guards/focus without fabricating an authoritative vote or chapter decision. Original thermal rules/cooldowns, real first Linlan Story/Store/dialogue and solo original Consensus pause/resume; original actions/stats are only observed. No physical controller, OS event dispatch/GUI navigation, remote reliable RPC, ENet/two-PC LAN, listening, comfort or full-flow claim."}
    FileAccess.open(output+"/result.json",FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
    print("CONTROLLER_SESSION_ACTIONS_RESULT ",JSON.stringify({"checks":checks.size(),"failures":failures,"engine_errors":logger.errors,"wall_seconds":report.wall_seconds}))
    if is_instance_valid(session):
        session.environment_save_gate.cancel("qa_controller_session_teardown")
        session.thermal_cargo.clear()
        if session.canal != null: session.canal.clear()
        session.network.close()
        session.free()
        session = null
    await process_frame
    await physics_frame
    await process_frame
    quit(0 if failures.is_empty() and logger.errors.is_empty() else 1)
