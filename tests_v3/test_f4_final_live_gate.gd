extends SceneTree
## Real source MAIN / native F4 mechanisms, not a played final campaign.
## QA PLAYER-only observation poses + ordered Director prefix are explicit.
const MAIN = preload("res://scenes/v3/main.tscn")
const Regions = preload("res://scripts/v3/world/twin_region_catalog.gd")
const TARGET := "F4:chapter_choice"
const ANCHOR := "F4:choice_terminal"
const FINAL_OBJECTIVE := "F4:twin_vein_core:decision"
const OPTIONS := ["shared_stewardship","industrial_lifeline","living_vein"]

class ErrorLogger extends Logger:
    var guard := Mutex.new()
    var errors: Array = []
    func _log_error(function: String,file: String,line: int,code: String,rationale: String,_notify: bool,kind: int,_trace: Array[ScriptBacktrace]) -> void:
        if kind == Logger.ERROR_TYPE_WARNING: return
        guard.lock()
        errors.append({"function":function,"file":file,"line":line,"code":code,"rationale":rationale})
        guard.unlock()

var logger := ErrorLogger.new()
var session: Node
var profile := ""
var output := ""
var finished := false
var checks: Array = []
var evidence: Dictionary = {}
var operations: Array = []
var fixture_receipts := 0
var prepared_payload: Dictionary = {}

func _initialize() -> void:
    OS.add_logger(logger)
    _run.call_deferred()

func _run() -> void:
    for arg: String in OS.get_cmdline_user_args():
        if arg.begins_with("--qa-profile="): profile = arg.trim_prefix("--qa-profile=")
        if arg.begins_with("--output="): output = arg.trim_prefix("--output=")
    if not profile.begins_with("qa_f4_final_live_gate_") or profile != profile.validate_filename() or DirAccess.dir_exists_absolute("user://profiles_v3/"+profile) or not output.begins_with("res://artifacts/v3/f4-final-live-gate-") or ".." in output or DirAccess.dir_exists_absolute(output):
        quit(2)
        return
    DirAccess.make_dir_recursive_absolute(output)
    create_timer(30.0).timeout.connect(func():
        if not finished:
            _check(false,"30 second real MAIN/native gate bound",_status())
            _finish())
    session = MAIN.instantiate()
    root.add_child(session)
    if not _check(session.profile_ready and session.start_flight("solo") and session.region_id=="I1","ordinary fresh QA MAIN starts default I1"): _finish(); return
    session.inputs.test_enabled = true
    session.inputs.test_frame = {"axes":{},"held":["brake"],"edges":[]}
    for unused in 3:
        if not await _frame(): return
    if not _check(session._load_region("F4") and session.region_id=="F4" and session.world.build_errors.is_empty(),"empty QA world builds native F4 BEFORE the explicit Director prefix",_status()): _finish(); return
    if not _check(session.campaign.mechanisms.has_method("final_lifelines_status"),"Root has applied the staged pure native-query API"): _finish(); return
    for unused in 3:
        if not await _frame(): return
    # No heat/HP/angle/growth endpoint fixture: every mechanism uses original
    # authenticated local ability actions, ordinary recovery and native shape.
    if not await _cast("F4:limited_bus","charge",false): _finish(); return
    if not await _cast("F4:living_emitter","light",false): _finish(); return
    for unused in 3:
        if not await _cast("F4:living_support","growth",false): _finish(); return
    var live := false
    for unused in 90:
        if not await _frame(): return
        if _live().get("ok",false) and _view().get("industrial_connected",false) and _view().get("living_connected",false): live = true; break
    if not _check(live and _view().get("industrial_connected",false) and _view().get("living_connected",false),"real 6F/4F/three growth transactions create fresh native bus/beam/full support",_status()): _finish(); return
    if not _fixture_prefix(): _finish(); return
    # Terminal observations never await a physics step: the test does not start
    # a real boss or inject its victory. This is only the declared rule prefix.
    if not _terminal(): _finish(); return
    for option: String in OPTIONS:
        if not _check(session.chapter_choices.read_option(1,TARGET,option),"original final offer records this UUID's explicit read: "+option): _finish(); return
    if not _check(session.chapter_choices.has_read_all(1,TARGET),"all three ORIGINAL final-target acknowledgements exist"): _finish(); return
    if not _prepare_ready("healthy_before_bus_break"): _finish(); return
    if not _near_device("F4:limited_bus") or not await _cooldown(): _finish(); return
    # Critical stale-view case: no await between 6X and both terminal gates.
    var view_before: Dictionary = _view()
    var frame: int = Engine.get_physics_frames()
    if not _cast_now("F4:limited_bus","charge",true): _finish(); return
    if not _terminal(): _finish(); return
    if not _schedule_ready("bus_drain") or not _reject_both("bus_drain",view_before,frame): _finish(); return
    # Legal original 6F restores power, while the previous view can still say
    # false. Do not write charge/powered, advance clocks or import a snapshot.
    if not _near_device("F4:limited_bus") or not await _cooldown(): _finish(); return
    if not _cast_now("F4:limited_bus","charge",false): _finish(); return
    if not _terminal(): _finish(); return
    if not _check(_live().get("ok",false),"original 6F restores a fresh live proof without waiting for cached view",_status()): _finish(); return
    if not _prepare_ready("healthy_after_original_6F"): _finish(); return
    if not _near_device("F4:living_emitter") or not await _cooldown(): _finish(); return
    view_before = _view()
    frame = Engine.get_physics_frames()
    if not _cast_now("F4:living_emitter","light",true): _finish(); return
    if not _terminal(): _finish(); return
    if _schedule_ready("emitter_off"): _reject_both("emitter_off",view_before,frame)
    _check(FINAL_OBJECTIVE not in session.story.state.completed and not session.store.snapshot().personal.discoveries.has("F4:operation_record"),"neither negative probe signs the final choice or awards its discovery")
    _check(not session.campaign.active() and session.campaign.encounter.get_state().is_empty(),"the declared Director prefix never creates or modifies an actual Boss HP state")
    _finish()

func _reject_both(label: String,old_view: Dictionary,frame: int) -> bool:
    var proposal: Dictionary = session.consensus.current_proposal()
    var store_before: Dictionary = session.store.snapshot()
    var mechanism_before: Dictionary = session.campaign.mechanisms.persistent_state()
    var current_view: Dictionary = _view()
    var queried: Dictionary = _live()
    if not _check(old_view.get("industrial_connected",false) and old_view.get("living_connected",false) and current_view==old_view and frame==Engine.get_physics_frames() and not queried.get("ok",true) and queried.get("code")=="final_lifelines_disconnected","fresh native query rejects a SAME-FRAME stale successful view: "+label,{"old_view":old_view,"current_view":current_view,"query":queried,"frame":frame}): return false
    if not _check(session.chapter_choices.confirmation_valid(1,proposal.payload) and store_before.branches.has(proposal.payload.branch_id),"all original UUID/read/range/branch/ready gates still pass before the new live commit gate: "+label,proposal): return false
    session._resolve_ready() # Original ChapterChoices → Story → same Store path.
    var retained: Dictionary = session.consensus.current_proposal()
    var commit_ok: bool = retained==proposal and session.store.snapshot()==store_before and FINAL_OBJECTIVE not in session.story.state.completed
    if not _check(commit_ok,"original ready commit refuses broken CURRENT lifeline without Store/branch/reward mutation: "+label,{"retained":retained,"before_generation":store_before.generation,"after_generation":session.store.snapshot().generation,"query":queried}): return false
    # Explicit ordinary cancellation permits separately testing PREPARE, which
    # must reject BEFORE _save_environment and before creating another branch.
    session.consensus.resolve(str(proposal.proposal_id),false)
    var before_prepare: Dictionary = session.store.snapshot()
    var refused: Dictionary = session.chapter_choices.prepare_proposal(1,TARGET,OPTIONS[0])
    var prepare_ok: bool = not refused.get("ok",true) and refused.get("code")=="final_lifelines_disconnected" and session.store.snapshot()==before_prepare and session.consensus.current_proposal().is_empty()
    var pure: bool = session.campaign.mechanisms.persistent_state()==mechanism_before and _view()==current_view and Engine.get_physics_frames()==frame
    evidence[label] = {"proposal":proposal,"query":queried,"commit_retained":retained,"prepare_refusal":refused,"profile_generation":before_prepare.generation,"branches":before_prepare.branches.keys(),"pure_query_no_clock_fact_or_view_change":pure}
    return _check(prepare_ok and pure,"prepare independently refuses before save/fork; live queries grant no tick/fact/view credit: "+label,evidence[label])

func _prepare_ready(label: String) -> bool:
    var before: Dictionary = session.store.snapshot()
    var prepared: Dictionary = session.chapter_choices.prepare_proposal(1,TARGET,OPTIONS[0])
    if not _check(prepared.get("ok",false) and session.store.snapshot().branches.size()==before.branches.size()+1,"healthy original prepare retains its legal before-choice branch behavior: "+label,prepared): return false
    prepared_payload = prepared.payload.duplicate(true)
    evidence[label] = {"prepared":prepared,"live":_live(),"generation":session.store.snapshot().generation,"branches_before":before.branches.size(),"branches_after":session.store.snapshot().branches.size()}
    # Explicit scheduling fixture: hold this REAL prepared payload until after
    # the actual ability. Production correctly blocks abilities once solo is
    # already READY; do not bypass that input gate or claim that race exists.
    return true

func _schedule_ready(label: String) -> bool:
    var proposed: Dictionary=session.consensus.propose("campaign_choice",prepared_payload,1)
    evidence[label+"_ready_schedule_fixture"]={"proposal":session.consensus.current_proposal(),"prepared_before_actual_break":true,"scope":"Explicit ready scheduling after original ability, not an ordinary solo-ready input race or ENet evidence."}
    return _check(proposed.get("ok",false) and proposed.get("ready",false),"original Consensus schedules retained prepared payload only AFTER actual ability: "+label,proposed)

func _fixture_prefix() -> bool:
    var director = session.story.director
    var state: Dictionary = director.default_state()
    var found := false
    for action: Dictionary in director.definitions().actions:
        for objective: Dictionary in action.objectives:
            if objective.id==FINAL_OBJECTIVE: found=true; break
            var match_event: Dictionary = objective.events[0]
            var result: Dictionary = director.apply_event(state,{"id":"qa-f4-live-prefix:"+str(objective.id),"type":match_event.type,"target_id":match_event.target_id,"option":match_event.options[0]},{"is_authority":true,"validated":true,"region_id":action.region_id})
            if not result.get("ok",false) or not result.get("changed",false): return _check(false,"ordered Director prefix is a valid rule fixture",{"objective":objective.id,"result":result})
            state = result.state
            fixture_receipts += 1
        if found: break
    if not _check(found and fixture_receipts==83 and director.validate_state(state).get("ok",false) and FINAL_OBJECTIVE not in state.completed,"explicit rule-only prefix stops immediately before final target; no earlier flight or Boss victory claim"): return false
    var written: Dictionary = session.store.commit({"id":"qa-f4-live-director-prefix-only","set":{"world.actions.opening":state}})
    if not _check(written.get("ok",false),"Director fixture is committed only to this new isolated original QA Store",written): return false
    session.world_cache = session.store.snapshot()
    session.consensus.set_world_revision(int(session.world_cache.world_revision))
    session.story.load_world()
    return _check(session.story.ready and session.story.current_targets().any(func(row: Dictionary): return row.target_id==TARGET),"same already-loaded native F4 adopts only the Director fixture")

func _cast(id: String,ability: String,reverse: bool) -> bool:
    if not _near_device(id) or not await _cooldown(): return false
    if not _cast_now(id,ability,reverse): return false
    return await _frame()

func _cast_now(id: String,ability: String,reverse: bool) -> bool:
    var count: int = session.stats.abilities
    var before: Dictionary = session.entities[id].duplicate(true)
    session.network.send_action("lock",{"target_id":id})
    session._ui_action("select",{"ability":ability})
    session._send_ability(reverse) # Exact original action used by 6F/6X/4F/4X.
    operations.append({"target":id,"ability":ability,"reverse":reverse,"before":before,"after":session.entities[id].duplicate(true),"frame":Engine.get_physics_frames()})
    return _check(session.stats.abilities==count+1,"original authority ability is actually accepted: "+id+":"+ability+(":X" if reverse else ":F"),operations.back())

func _cooldown() -> bool:
    for unused in 80:
        if float(session.cooldowns.get(1,0.0))<=0.0: return true
        if not await _frame(): return false
    return _check(false,"original ability recovery completes on ordinary Session ticks",_status())

func _near_device(id: String) -> bool:
    var body: Node3D = session.world.objects.get(id)
    if not is_instance_valid(body): return _check(false,"real device exists: "+id)
    for offset: Vector3 in [Vector3(0,3.4,0),Vector3(0,0,3.4),Vector3(0,0,-3.4),Vector3(-3.4,0,0),Vector3(3.4,0,0)]:
        var at: Vector3 = body.global_position+offset
        if _clear(at) and session._line_clear(at,body.global_position,session.players[1].get_rid(),id): return _observe_player(at)
    return _check(false,"device has original LOS and full aircraft clearance: "+id,_status())

func _terminal() -> bool:
    var marker: Dictionary = session.story.markers[ANCHOR]
    var point: Vector3 = session.story._point(marker)
    for offset: Vector3 in [Vector3(0,1.8,1),Vector3(1.8,0,1),Vector3(-1.8,0,1),Vector3(0,1.8,-1)]:
        var at: Vector3 = point+offset
        if _clear(at) and at.distance_to(point)<=float(marker.radius) and session._line_clear(at,point,session.players[1].get_rid(),ANCHOR): return _observe_player(at)
    return _check(false,"terminal has a legitimate close visible QA observer position",_status())

func _clear(at: Vector3) -> bool:
    if not Regions.contains("F4",at): return false
    var actor: FlightBodyV2 = session.players[1]
    var hull: CollisionShape3D = actor.get_node("Envelope")
    var query := PhysicsShapeQueryParameters3D.new()
    query.shape = hull.shape
    query.transform = Transform3D(Basis.IDENTITY,at)*hull.transform
    query.collision_mask = 1|2|8|32
    query.exclude = [actor.get_rid()]
    return session.world.get_world_3d().direct_space_state.intersect_shape(query,1).is_empty()

func _observe_player(at: Vector3) -> bool:
    var actor: FlightBodyV2 = session.players[1]
    actor.freeze = true
    actor.global_transform = Transform3D(Basis.IDENTITY,at)
    actor.force_update_transform()
    PhysicsServer3D.body_set_state(actor.get_rid(),PhysicsServer3D.BODY_STATE_TRANSFORM,actor.global_transform)
    actor.linear_velocity = Vector3.ZERO
    actor.angular_velocity = Vector3.ZERO
    actor.hold_height = at.y
    return true # Only declared QA aircraft observation; no mechanism mutation.

func _live() -> Dictionary:
    return session.campaign.mechanisms.final_lifelines_status(session.entities)

func _view() -> Dictionary:
    return session.campaign.mechanisms.view_state()

func _status() -> Dictionary:
    if not is_instance_valid(session): return {}
    var support_rays: Array=[]
    if session.region_id=="F4":
        var mechanism=session.campaign.mechanisms
        var bridge: PhysicsBody3D=session.world.objects["F4:living_support"]
        for i: int in range(7):
            var point: Vector3=Vector3(12.5,12,6).lerp(Vector3(15.5,12,6),float(i)/6.0)
            for side: float in [-.8,0.0,.8]:
                var at: Vector3=point+Vector3(0,0,side)
                var hit: Dictionary=mechanism._ray(at+Vector3.UP,at-Vector3.UP)
                support_rays.append({"from":at,"collider":str(hit.collider.get_path()) if not hit.is_empty() else "","expected":mechanism._is_body(hit.get("collider"),bridge,"F4:living_support")})
        for edge: Vector3 in [Vector3(12.35,12,6),Vector3(15.65,12,6)]:
            var hit: Dictionary=mechanism._ray(edge+Vector3.UP*.5,edge-Vector3.UP*1.5,[bridge.get_rid()])
            support_rays.append({"edge":edge,"collider":str(hit.collider.get_path()) if not hit.is_empty() else ""})
    return {"region":session.region_id,"active":session.active,"generation":session.store.snapshot().generation,"message":session.interface.message.text,"view":_view(),"proposal":session.consensus.current_proposal(),"actor_health":session.players[1].health if session.players.has(1) else null,"boss_active":session.campaign.active(),"growth_blockers":session.world.campaign_growth_blockers if is_instance_valid(session.world) else {},"support_rays":support_rays}

func _frame() -> bool:
    await physics_frame
    await process_frame
    return not finished

func _check(ok: bool,label: String,actual: Variant=null) -> bool:
    checks.append({"passed":ok,"label":label,"actual":actual})
    return ok

func _finish() -> void:
    if finished: return
    finished = true
    var status: Dictionary = _status()
    if is_instance_valid(session):
        session.environment_save_gate.cancel("qa_f4_live_gate_teardown")
        session.active = false
        # The accepted4X emits the original spatial tool cue. Keep this
        # same-frame terminal path; the manager must release its native owner.
        session.audio.shutdown()
        session.network.close()
        var deadline: int = Time.get_ticks_usec()+1000000
        while not session.audio.shutdown_status().ready and Time.get_ticks_usec()<deadline:
            await process_frame
        _check(session.audio.shutdown_status().ready,"QA terminal native audio references drain",session.audio.shutdown_status())
        session.thermal_cargo.clear()
        if session.canal!=null: session.canal.clear()
        session.free()
        session = null
    await process_frame
    await physics_frame
    await process_frame
    var failures: Array = checks.filter(func(row: Dictionary): return not row.passed)
    var report: Dictionary = {"checks":checks,"failures":failures,"engine_errors":logger.errors,"operations":operations,"evidence":evidence,"fixture_receipts":fixture_receipts,"final_status":status,"scope":"Actual fresh source MAIN, default I1 then explicit empty F4 load BEFORE ordered Director-through-83 fixture. Native bus/light/full 3m support prepared ONLY by original local authority ability actions and ordinary clocks. PLAYER-only hull/LOS checked observation positions and original Consensus ready scheduling AFTER the actual break are declared QA fixtures, not flown campaign/ENet/Boss victory. Original production blocks ability input once solo is ready. This test explicitly holds the genuine prepared payload, performs real6X/4X, then schedules original Consensus ready with no physics yield; it does not claim a reachable ordinary solo-ready input race. Same-frame successful historical _view remains unchanged; original ready commit/independent prepare reject with exact per-attempt Store and branch baselines. Original 6F restores a healthy real prepare and legal before-choice branch. No heat/HP/clock/angle/growth endpoint write, snapshot rollback, manual simulation tick, successful final signing/Ending or valid whole-profile Registry reopen claim. Emitter-off recovery through its rotation cycle remains untested. QA terminal drain immediately follows the same-frame negative assertions and original4X tool cue; not normal final exit acceptance."}
    var file := FileAccess.open(output+"/result.json",FileAccess.WRITE)
    if file==null: quit(2); return
    file.store_string(JSON.stringify(report,"\t",true,true))
    file.close()
    print("F4_FINAL_LIVE_GATE_RESULT "+JSON.stringify({"checks":checks.size(),"failures":failures,"engine_errors":logger.errors,"fixture_receipts":fixture_receipts}))
    quit(0 if failures.is_empty() and logger.errors.is_empty() else 1)
