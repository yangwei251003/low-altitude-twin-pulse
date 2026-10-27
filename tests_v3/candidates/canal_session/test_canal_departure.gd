extends "res://tests_v3/candidates/canal_session/test_canal_scan.gd"
## Historical actual ten-receipt scan is explicit. All remaining work/departure
## and post-consumption ticks use original controllers in the current World.
const Progress=Adapter.ProgressCheckpoint
const DEPARTURE_FIXTURE="res://tests_v3/candidates/canal_session/progress_fixture/actual_scan_exchange.json"
const DEPARTURE_SHA="56afda69dbac803f0986539203a4a582fb476b8cabfc7705ece27195828ba3fa"
var phases: Dictionary={}
var terminal_ready: bool=false
var completed_observer=Adapter.Assembly.Checkpoint.new()

func _run() -> void:
    create_timer(90).timeout.connect(func():
        if not done:
            _check(false,"bounded original committed departure",adapter.module.status(true) if is_instance_valid(adapter.module) else adapter.status())
            _finish())
    if not _check(profile.begins_with("qa_canal_session_") and not DirAccess.dir_exists_absolute("user://profiles_v3/"+profile),"isolated actual MAIN departure profile"): _finish(); return
    if not _check(FileAccess.get_sha256(DEPARTURE_FIXTURE)==DEPARTURE_SHA,"pinned actual ten-receipt scan source"): _finish(); return
    var fixture: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(DEPARTURE_FIXTURE))
    if not _check(Scan.validate(fixture).ok and fixture.executor.receipt_count==10,"historical source remains strict original scan"): _finish(); return
    session=MAIN.instantiate()
    root.add_child(session)
    session.set_process(false)
    session.set_physics_process(false)
    session.inputs.set_process(false)
    session.inputs.set_physics_process(false)
    session.canal_runtime_enabled=false
    if not _check(session.profile_ready and session.start_flight("solo"),"actual MAIN starts") or not _seed_old27(): _finish(); return
    if not _check(session.store.commit({"id":"qa-departure-actual-scan","set":{"world.environment.I2_canal":fixture}}).ok,"same original Store imports declared historical scan"): _finish(); return
    session.world_cache=session.store.snapshot()
    if not _check(session._load_region("I2"),"actual current I2 World"): _finish(); return
    session.owns_world=false
    _player_pose(Vector3(8,3.2,27))
    adapter.setup(session)
    var prepared: Dictionary=adapter.prepare(session.world_cache.world,"I2",true)
    if not _check(prepared.ok and adapter.adopt(prepared).ok,"strict real scan reconstruction starts"): _finish(); return
    for unused in 240:
        if not await _frame(): _finish(); return
        if adapter.ready: break
    if not _check(adapter.ready,"current support and rays release historical scan"): _finish(); return
    for unused in 4400:
        if not await _frame(): _finish(); return
        var ctx: Dictionary=adapter.context()
        var bench=ctx.workbench
        if bench._phase=="commit" and not phases.has("commit"):
            if not await _save_restore("commit"): _finish(); return
            continue
        if not bench._committed: continue
        var label: String=""
        if bench._departure==null: label="committed"
        elif bench._departure._phase=="lift" and bench.beneficiary.linear_velocity.y>.15: label="lift"
        elif bench._departure._phase=="route" and bench._departure._leg_started: label="route_"+str(bench._departure._index)
        if not label.is_empty() and not phases.has(label):
            if not await _save_restore(label): _finish(); return
            continue
        if bench.report().departure.get("arrived",false):
            var terminal: Dictionary=completed_observer.capture(ctx,ctx.executor,bench,ctx.cooling,true,false)
            if terminal.ok:
                terminal_ready=true
                snapshots["actual_completed_safe"]=terminal.envelope
                if not await _save_restore("terminal"): _finish(); return
                break
    if not _check(terminal_ready and phases.has("commit") and phases.has("committed") and phases.has("lift") and phases.has("route_1") and phases.has("route_2") and phases.has("route_3"),"original departure covers pre-receipt commit/confirmed work/lift/all three route legs/actual terminal",phases.keys()): _finish(); return
    # Original external Store transaction / prepare+adopt contract. No player
    # healing is asserted by this isolated ledger test (Session integration is Root).
    var ctx: Dictionary=adapter.context()
    for unused in 90:
        if not await _frame(): _finish(); return
        ctx=adapter.context()
        if ctx.executor._phase=="idle" and ctx.executor._last_controller.get("arrived",false) and float(ctx.executor._last_controller.get("settled_seconds",0))>=.35: break
    var service: Dictionary=ctx.rules.prepare_service(int(ctx.rules.snapshot().revision),int(ctx.rules.snapshot().service_serial)+1,true,false)
    if not _check(service.ok,"original Rules prepares exactly one existing service credit"): _finish(); return
    var future: Dictionary=adapter.capture_persistent_state().envelope.duplicate(true)
    future.rules=service.candidate.duplicate(true)
    future.executor.fields._waiting_for_beneficiary=true
    future.executor.fields._code="awaiting_new_beneficiary"
    if not _check(Progress.validate(future).ok,"prepared consumed ledger requires original beneficiary wait flag"): _finish(); return
    if not _check(session.store.commit({"id":"qa-departure-service-consumed","set":{"world.environment.I2_canal":future}}).ok,"same Store commits exact service candidate before adoption"): _finish(); return
    if not _check(ctx.rules.adopt_service(service,true,false).ok and ctx.executor.wait_for_next_beneficiary(true).ok,"original Rules and safe idle executor adopt consumed service once"): _finish(); return
    if not await _save_restore("claimed"): _finish(); return
    ctx=adapter.context()
    var source: Dictionary=ctx.rules.snapshot()
    for unused in 90:
        if not await _frame(): _finish(); return
    var after: Dictionary=ctx.rules.snapshot()
    _check(after.jobs_completed==1 and after.services_consumed==1 and after.service_credit==0 and after.service_serial==source.service_serial and after.pending_action.is_empty() and ctx.executor._waiting_for_beneficiary,"restored claim never replays work/service or creates job2")
    _check(ctx.workbench._receipt_count==1 and ctx.workbench._receipt.is_empty() and not ctx.workbench._progress_history.is_empty(),"restored history is not a newly emitted receipt")
    snapshots["phases"]=phases
    snapshots["final"]=adapter.module.status(true)
    _finish()

func _save_restore(label: String, early_ticks: int=10) -> bool:
    var captured: Dictionary=adapter.capture_persistent_state()
    if not _check(captured.ok and captured.envelope.kind==Progress.KIND and Progress.validate(captured.envelope).ok,"capture actual committed "+label,captured if not captured.ok else {}): return false
    var source: Dictionary=captured.envelope
    var pre_receipt: bool=label=="commit"
    if pre_receipt:
        _check(source.workbench.version==4 and source.rules.jobs_completed==0 and source.rules.service_credit==0 and source.workbench.measurements.size()==3 and source.workbench.scan_distance_m>=1.39999,"original three endpoints preserved before any work receipt")
    else:
        _check(source.workbench.version==3 and source.rules.jobs_completed==1 and source.workbench.history.first_work.action.serial==source.workbench.history.first_departure.work_serial,"original one work history/serial preserved "+label)
    if label=="claimed":
        var invalid: Dictionary=source.duplicate(true)
        invalid.executor.fields._waiting_for_beneficiary=false
        _check(not Progress.validate(invalid).ok,"consumed ledger without beneficiary wait gate rejected")
    session.canal=adapter
    session.owns_world=true
    if not _check(session._save_environment(),"original Session Store saves "+label): return false
    var reopened=Store.new(session.store.root_path)
    if not _check(reopened.load_profile().ok,"same original Store reopens "+label): return false
    var saved: Dictionary=reopened.snapshot().world.environment.I2_canal
    snapshots["latest_roundtrip"]={"phase":label,"source":source,"saved":saved}
    if not _check(session.store.matches_persisted_value(source,saved),"original Store JSON equality "+label): return false
    if not _check(Progress.validate(saved).ok,"saved progress validates "+label,Progress.validate(saved)): return false
    session.canal=null
    session.owns_world=false
    adapter.clear()
    session.world_cache=reopened.snapshot()
    if not _check(session._load_region("I2"),"fresh real World "+label): return false
    session.owns_world=false
    _player_pose(Vector3(8,3.2,27))
    adapter.setup(session)
    var prepared: Dictionary=adapter.prepare(session.world_cache.world,"I2",true)
    if not _check(prepared.ok and adapter.adopt(prepared).ok,"committed subtree constructed frozen "+label,prepared if not prepared.ok else {}): return false
    for unused in 20:
        if not await _frame(): return false
        if adapter.ready: break
    if not _check(adapter.ready,"actual frozen readback permits adoption "+label,adapter.module.status(true)): return false
    var ctx: Dictionary=adapter.context()
    _check(Wait.Rules._same(ctx.rules.snapshot(),saved.rules) and ctx.workbench._receipt_count==(0 if pre_receipt else 1) and ctx.workbench._receipt.is_empty(),"restore does not step clock or emit work/service "+label)
    _check(ctx.workbench.beneficiary.global_transform==Wait.State.transform(saved.workbench.beneficiary.pose) and ctx.workbench.beneficiary.linear_velocity==Wait.State.vec(saved.workbench.beneficiary.velocity),"same original beneficiary pose/momentum "+label)
    _check(not ctx.workbench.report().departure.get("arrived",false),"source arrival is not new current-space credit "+label)
    if pre_receipt:
        _check(ctx.workbench._scan_restore_pending and ctx.workbench._scan_revalidated==0 and ctx.workbench._measurements.is_empty() and ctx.workbench._scan_sources==saved.workbench.measurements,"saved commit endpoints remain source history until real new-space support/rays")
    elif not saved.workbench.departure.is_empty():
        _check(ctx.workbench._departure._index==int(saved.workbench.departure.index) and ctx.workbench._departure._serial==int(saved.workbench.departure.serial) and ctx.workbench._departure._leg_started==saved.workbench.departure.leg_started and ctx.workbench._departure._stable==0.0 and ctx.workbench._departure._pilot.settled_seconds==0.0,"original route/serial resumes with zero fresh stability "+label)
        _check(ctx.workbench._restored_history.is_empty(),"intermediate departure does not shortcut through completed-safe terminal branch "+label)
    for unused in maxi(1,early_ticks):
        var early: Dictionary=adapter.capture_persistent_state()
        if not _check(early.ok and Progress.validate(early.envelope).ok,"zero-credit/early committed resave "+label+":"+str(unused),early if not early.ok else {}): return false
        if early_ticks>0 and not await _frame(): return false
    phases[label]={"source":source,"restored":adapter.capture_persistent_state().get("envelope",{})}
    return true

func _finish() -> void:
    if done: return
    done=true
    if is_instance_valid(adapter.module): snapshots["final_status"]=adapter.module.status(true)
    if is_instance_valid(session): session.canal=null
    adapter.clear()
    if is_instance_valid(session): session.free()
    var result: Dictionary={"checks":checks.size(),"failures":failures,"engine_errors":logger.errors,"details":checks,"snapshots":snapshots,"scope":"historical actual ten-receipt scan fixture; remaining original work, all departure legs and original consumed ledger; same MAIN Store, no player healing/LAN/input-comfort claim"}
    if not output.is_empty():
        var file:=FileAccess.open(output.path_join("result.json"),FileAccess.WRITE)
        if file: file.store_string(JSON.stringify(result,"\t",true,true))
    print("CANAL_DEPARTURE ",JSON.stringify({"checks":checks.size(),"failures":failures,"engine_errors":logger.errors}))
    quit(0 if failures.is_empty() and logger.errors.is_empty() else 1)
