extends SceneTree
## Actual MAIN/Session/Story/Store transaction from explicitly pinned PHYSICAL
## service evidence. Earlier Director receipts and PLAYER positions are QA
## fixtures, not proof of flying the preceding campaign or route again.
const MAIN=preload("res://scenes/v3/main.tscn")
const Store=preload("res://scripts/v3/core/twin_world_store.gd")
const Adapter=preload("res://scripts/v3/gameplay/twin_canal_session.gd")
const Progress=Adapter.ProgressCheckpoint
const OBJECTIVE="I2:canal_service:service"
const REWARD="I2:canal_calibration"
const TARGET=Adapter.Assembly.Workbench.POWER_ID
class ErrorLogger extends Logger:
    var guard:=Mutex.new()
    var errors: Array=[]
    func _log_error(function: String,file: String,line: int,code: String,rationale: String,_notify: bool,kind: int,_trace: Array[ScriptBacktrace]) -> void:
        if kind==Logger.ERROR_TYPE_WARNING: return
        guard.lock()
        errors.append({"function":function,"file":file,"line":line,"code":code,"rationale":rationale})
        guard.unlock()
var logger:=ErrorLogger.new()
var session: Node
var profile: String=""
var output: String=""
var source_path: String=""
var source_sha: String=""
var checks: Array=[]
var phases: Dictionary={}
var finished:=false
var fixture_receipts:=0
var last_region_load: Dictionary={}

func _initialize() -> void:
    OS.add_logger(logger)
    _run.call_deferred()

func _run() -> void:
    for arg: String in OS.get_cmdline_user_args():
        if arg.begins_with("--qa-profile="): profile=arg.trim_prefix("--qa-profile=")
        if arg.begins_with("--output="): output=arg.trim_prefix("--output=")
        if arg.begins_with("--source-result="): source_path=arg.trim_prefix("--source-result=")
        if arg.begins_with("--source-sha="): source_sha=arg.trim_prefix("--source-sha=")
    if not profile.begins_with("qa_canal_story_") or profile!=profile.validate_filename() or DirAccess.dir_exists_absolute("user://profiles_v3/"+profile) or not output.begins_with("res://artifacts/v3/canal-story-") or ".." in output or DirAccess.dir_exists_absolute(output): quit(2); return
    DirAccess.make_dir_recursive_absolute(output)
    create_timer(40).timeout.connect(func():
        if not finished:
            _check(false,"40 second original Story transaction bound",_diagnostics())
            _finish())
    if not _check(source_path.begins_with("res://tests_v3/candidates/canal_session/evidence/service_") and ".." not in source_path and source_path.ends_with("/result.json") and source_sha.length()==64 and FileAccess.get_sha256(source_path)==source_sha,"pinned exact successful physical service evidence input"): _finish(); return
    var source: Variant=JSON.parse_string(FileAccess.get_file_as_string(source_path))
    if not _check(source is Dictionary and source.get("failures",[1]).is_empty() and source.get("engine_errors",[1]).is_empty(),"source actually passed physical cleanup/claim checks, not a manufactured endpoint"): _finish(); return
    var idle: Dictionary=source.snapshots.phases.transport_idle.source
    var claimed_reference: Dictionary=source.snapshots.phases.claimed.source
    if not _check(Progress.validate(idle).ok and Progress.validate(claimed_reference).ok and idle.rules.service_credit==1 and idle.rules.services_consumed==0 and claimed_reference.rules.service_credit==0 and claimed_reference.rules.services_consumed==1 and claimed_reference.rules.service_serial==1,"real transport_idle and claimed reference share the original versioned ledger contract"): _finish(); return
    phases["source"]={"path":source_path,"sha256":source_sha,"idle_record":"snapshots.phases.transport_idle.source","claimed_record":"snapshots.phases.claimed.source","idle":idle,"claimed_reference":claimed_reference}
    session=MAIN.instantiate()
    root.add_child(session)
    session.canal_runtime_enabled=true
    if not _check(session.profile_ready and session.start_flight("solo"),"actual MAIN starts an empty isolated QA solo"): _finish(); return
    session.inputs.test_enabled=true
    session.inputs.test_frame={"axes":{},"held":["brake"],"edges":[]}
    if not _load_i2("normal factory first loads actual empty I2 BEFORE any prior-Story or physical fixture"): _finish(); return
    if not _check(session.store.commit({"id":"qa-canal-actual-idle-history","set":{"world.environment.I2_canal":idle}}).ok,"only real physical idle history imports before the normal Registry/factory restore"): _finish(); return
    session.world_cache=session.store.snapshot()
    if not _load_i2("original Session factory rebuilds physical idle BEFORE any fictional prior-Story fixture"): _finish(); return
    for unused in 240:
        await _frame()
        if finished: return
        if session.canal.ready and session.canal.story_service_status().ready_credit: break
    if not _check(session.canal.ready and session.canal.story_service_status().ready_credit and session.canal.context().rules.snapshot().service_credit==1,"ordinary Session ticks reacquire actual current support and continuous Safe credit",_diagnostics()): _finish(); return
    var prior: Dictionary=_story_prefix()
    if prior.is_empty(): _finish(); return
    if not _check(session.store.commit({"id":"qa-canal-story-rule-prefix-only","set":{"world.actions.opening":prior}}).ok,"legal prior-rule prefix imports AFTER the actual factory restore; no facility history is fabricated"): _finish(); return
    session.world_cache=session.store.snapshot()
    session.consensus.set_world_revision(int(session.world_cache.world_revision))
    session.story.load_world() # Story reducer only; never ask Registry to accept fictional physical history.
    await _place_actor()
    if finished: return
    var body: FlightBodyV2=session.players[1]
    if not _check(body.enabled and not body.freeze and session._line_clear(body.global_position,session.canal.context().workbench.power_target.global_position,body.get_rid(),TARGET),"actual nearby QA actor has real LOS to original physical service contact"): _finish(); return
    var before: Dictionary=session.store.snapshot()
    var before_story: Dictionary=session.story.state.duplicate(true)
    session.store.failure_point="before_publish"
    session.story.interact(1,{"target_id":TARGET})
    var failed: Dictionary=session.store.snapshot()
    var state: Dictionary=session.canal.context().rules.snapshot()
    if not _check(failed==before and session.story.state==before_story and OBJECTIVE not in session.story.state.completed and state.service_credit==1 and state.services_consumed==0 and failed.personal.discoveries.count(REWARD)==0,"failed original Story Store publication preserves credit1, unfinished objective and reward0",_diagnostics()): _finish(); return
    phases["failed"]={"generation":failed.generation,"rules":state,"story":session.story.state.duplicate(true)}
    session.store.failure_point=""
    # No await between failed publication and retry: the actual Safe proof,
    # player identity and native site are still from this same ordinary frame.
    session.story.interact(1,{"target_id":TARGET})
    var committed: Dictionary=session.store.snapshot()
    var disk: Dictionary=_disk()
    if disk.is_empty(): _finish(); return
    state=session.canal.context().rules.snapshot()
    var stored: Dictionary=disk.world.environment.I2_canal
    var atomic: bool=session.active and int(committed.generation)==int(before.generation)+1 and disk.generation==committed.generation and OBJECTIVE in disk.world.actions.opening.completed and OBJECTIVE in disk.world.completed_objectives and disk.personal.discoveries.count(REWARD)==1 and stored.rules.service_credit==0 and stored.rules.services_consumed==1 and stored.rules.service_serial==1 and Progress.validate(stored).ok and state.service_credit==0 and state.services_consumed==1 and session.canal.context().executor._waiting_for_beneficiary
    if not _check(atomic,"one original Store generation atomically contains Story objective, one discovery and adopted original consumed service",{"before_generation":before.generation,"disk":disk,"diagnostics":_diagnostics()}): _finish(); return
    phases["atomic"]={"generation":disk.generation,"story":session.story.state.duplicate(true),"envelope":stored,"native_rules":state}
    # Use the original Damage path, not an HP assignment. Repeated service must
    # not restore any old health value or publish another reward/generation.
    body.take_damage(25)
    var damaged: Dictionary=body.damage_snapshot()
    var repeat_before: Dictionary=session.store.snapshot()
    session.story.interact(1,{"target_id":TARGET})
    session.story.interact(1,{"target_id":TARGET})
    _check(body.health<body.maximum_health and body.damage_snapshot()==damaged and session.store.snapshot()==repeat_before and session.store.snapshot().personal.discoveries.count(REWARD)==1,"repeated actual Story contact cannot reconsume, reward again or heal original Damage")
    # The declared Director prefix does not supply genuine prior clinic/
    # distribution history. A whole MAIN reload must retain its Registry gate.
    # Test ONLY a fresh owned Assembly from our newly committed envelope in the
    # already valid live I2. Never fake/bypass Registry or call it full save validity.
    var old_bodies: Array=_owned_rids()
    session.canal.clear()
    session.canal=Adapter.new()
    session.canal.setup(session)
    var prepared: Dictionary=session.canal.prepare(session.store.snapshot().world,"I2",true)
    var adopted: Dictionary=session.canal.adopt(prepared) if prepared.get("ok",false) else prepared
    if not _check(adopted.get("ok",false),"fresh original Adapter/owned physical subtree uses our just-committed claimed envelope; this is not a whole-MAIN reload",adopted): _finish(); return
    for unused in 90:
        await _frame()
        if finished: return
    var new_bodies: Array=_owned_rids()
    var fresh: bool=old_bodies.size()==4 and new_bodies.size()==4
    for rid: String in new_bodies: fresh=fresh and rid not in old_bodies
    if not _check(session.canal.ready and fresh,"claimed envelope completes fresh four-body native adoption without reusing old owned RIDs",_diagnostics()): _finish(); return
    await _place_actor()
    if finished: return
    body=session.players[1]
    body.take_damage(10)
    damaged=body.damage_snapshot()
    repeat_before=session.store.snapshot()
    session.story.interact(1,{"target_id":TARGET})
    state=session.canal.context().rules.snapshot()
    _check(body.damage_snapshot()==damaged and session.store.snapshot()==repeat_before and repeat_before.personal.discoveries.count(REWARD)==1 and OBJECTIVE in session.story.state.completed and state.jobs_completed==1 and state.service_credit==0 and state.services_consumed==1 and state.service_serial==1 and state.pending_action.is_empty() and session.canal.context().executor._waiting_for_beneficiary,"fresh claimed physical subtree plus ordinary ticks/contact retain one claim/reward, no old health or job2",_diagnostics())
    phases["restored"]=_diagnostics()
    _finish()

func _story_prefix() -> Dictionary:
    var director=session.story.director
    var state: Dictionary=director.default_state()
    var found: bool=false
    for action: Dictionary in director.definitions().actions:
        for objective: Dictionary in action.objectives:
            if objective.id==OBJECTIVE:
                found=true
                break
            var matcher: Dictionary=objective.events[0]
            var option: String="low_route" if matcher.target_id=="I2:canal_exchange_verified" else str(matcher.options[0])
            var applied: Dictionary=director.apply_event(state,{"id":"qa-canal-story-prefix:"+str(objective.id),"type":matcher.type,"target_id":matcher.target_id,"option":option},{"is_authority":true,"validated":true,"region_id":action.region_id})
            if not applied.get("ok",false) or not applied.get("changed",false):
                _check(false,"ordered Director fixture uses only valid prior receipts",{"objective":objective.id,"code":applied.get("code")})
                return {}
            state=applied.state
            fixture_receipts+=1
        if found: break
    if not _check(found and OBJECTIVE not in state.completed and "I2:canal_service:exchange" in state.completed and director.validate_state(state).ok,"legal Director prefix stops before this service objective; preceding campaign was not flown",{"fixture_receipts":fixture_receipts,"last":state.completed[-1] if not state.completed.is_empty() else ""}): return {}
    return state

func _place_actor() -> void:
    var body: FlightBodyV2=session.players[1]
    body.freeze=true
    body.global_transform=Transform3D(Basis.IDENTITY,Vector3(3.5,2.8,5.4)) # Explicit PLAYER-only QA LOS pose.
    body.force_update_transform()
    body.linear_velocity=Vector3.ZERO
    body.angular_velocity=Vector3.ZERO
    body.hold_height=2.8
    body.freeze=false
    await _frame()

func _frame() -> void:
    await physics_frame
    await process_frame # Observe only; ordinary Session owns its one tick.

func _load_i2(label: String) -> bool:
    var loaded: bool=session._load_region("I2")
    var message: String=session.interface.message.text
    last_region_load={"region":"I2","ok":loaded,"interface_message":message,"prepare_or_adopt_error_from_original_ui":message if not loaded else "","active_after":session.active,"owns_world_after":session.owns_world,"world_build_errors":session.world.build_errors if is_instance_valid(session.world) else []}
    return _check(loaded and session.region_id=="I2" and session.canal!=null and session.world.build_errors.is_empty(),label,_diagnostics())

func _owned_rids() -> Array:
    var result: Array=[]
    for node: Node in session.canal.module.find_children("*","RigidBody3D",true,false): result.append(str((node as RigidBody3D).get_rid()))
    return result

func _disk() -> Dictionary:
    var reader=Store.new(session.store.root_path)
    var loaded: Dictionary=reader.load_profile()
    if not _check(loaded.ok,"independent original Store reader opens the atomic generation",loaded): return {}
    return reader.snapshot()

func _diagnostics() -> Dictionary:
    if not is_instance_valid(session): return {"session":"not_installed"}
    var ctx: Dictionary=session.canal.context() if session.canal!=null else {}
    var rules: Variant=ctx.get("rules")
    return {"active":session.active,"region":session.region_id,"last_region_load":last_region_load.duplicate(true),"generation":session.store.snapshot().generation,"story":session.story.state.duplicate(true),"adapter":session.canal.status() if session.canal!=null else {},"service":session.canal.story_service_status() if session.canal!=null else {},"rules":rules.snapshot() if rules!=null else {},"message":session.interface.message.text}

func _check(ok: bool,label: String,actual: Variant=null) -> bool:
    checks.append({"passed":ok,"label":label,"actual":actual})
    return ok

func _finish() -> void:
    if finished: return
    finished=true
    var failures: Array=checks.filter(func(row: Dictionary): return not row.passed)
    var report: Dictionary={"checks":checks,"failures":failures,"engine_errors":logger.errors,"phases":phases,"fixture_receipts":fixture_receipts,"final":_diagnostics(),"scope":"actual normal MAIN/Session Canal factory restores real pinned idle BEFORE legal prior Director prefix; then original Story.interact/_submit atomic Store. FailedStore/retry/one-generation claim+Story+reward/duplicate/no-old-health; fresh original Adapter/four-body subtree from this same committed envelope in the already valid live I2. Prior rule receipts/PLAYER pose explicit QA, not preceding flights/physical facility history. No whole-MAIN profile-reload validity claim; original Registry gates remain mandatory. No scan/route replay, guest rewards, LAN, graphics or whole-game acceptance."}
    FileAccess.open(output+"/result.json",FileAccess.WRITE).store_string(JSON.stringify(report,"\t",true,true))
    print("CANAL_STORY_TRANSACTION ",JSON.stringify({"checks":checks.size(),"failures":failures,"engine_errors":logger.errors}))
    if is_instance_valid(session):
        session.environment_save_gate.cancel("qa_story_teardown")
        if session.canal!=null: session.canal.clear()
        session.network.close()
        session.free()
    quit(0 if failures.is_empty() and logger.errors.is_empty() else 1)
