extends "res://tests_v3/candidates/canal_session/test_canal_departure.gd"
## Actual original pre-Brief thermal/first-work path, no route receipts invented.
const LOCAL_FIXTURE="res://tests_v3/candidates/canal_session/progress_fixture/actual_scan_local_cooling.json"
const LOCAL_SHA="993f21bbffac50b9e61964e2e2afdf143d43a6cab0104f2726f401fb750fa6d4"

func _run() -> void:
    create_timer(25).timeout.connect(func():
        if not done:
            _check(false,"bounded original local cooling proof",adapter.module.status(true) if is_instance_valid(adapter.module) else adapter.status())
            _finish())
    if not _check(profile.begins_with("qa_canal_session_") and not DirAccess.dir_exists_absolute("user://profiles_v3/"+profile),"isolated original MAIN local-cooling profile"): _finish(); return
    if not _check(FileAccess.get_sha256(LOCAL_FIXTURE)==LOCAL_SHA,"pinned actual Rules/LOS 25kJ local-cooling scan source"): _finish(); return
    var fixture: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(LOCAL_FIXTURE))
    if not _check(Scan.validate(fixture).ok and fixture.executor.receipt_count==0 and fixture.rules.pending_action.serial==1,"local stationary work1 is valid with zero transport receipts"): _finish(); return
    session=MAIN.instantiate()
    root.add_child(session)
    session.set_process(false)
    session.set_physics_process(false)
    session.inputs.set_process(false)
    session.inputs.set_physics_process(false)
    session.canal_runtime_enabled=false
    if not _check(session.profile_ready and session.start_flight("solo"),"actual MAIN starts") or not _seed_old27(): _finish(); return
    if not _check(session.store.commit({"id":"qa-local-cooling-history","set":{"world.environment.I2_canal":fixture}}).ok,"same original Store imports declared actual thermal scan"): _finish(); return
    session.world_cache=session.store.snapshot()
    if not _check(session._load_region("I2"),"actual production I2 World"): _finish(); return
    var baseline_story: Dictionary=session.story.state.duplicate(true)
    var baseline_discoveries: Array=session.store.snapshot().personal.discoveries.duplicate(true)
    snapshots["declared_prior_baseline"]={"story":baseline_story,"discoveries":baseline_discoveries}
    session.owns_world=false
    _player_pose(Vector3(8,3.2,27))
    adapter.setup(session)
    var prepared: Dictionary=adapter.prepare(session.world_cache.world,"I2",true)
    if not _check(prepared.ok and adapter.adopt(prepared).ok,"original scan reconstruction starts"): _finish(); return
    for unused in 180:
        if not await _frame(): _finish(); return
        if adapter.ready: break
    if not _check(adapter.ready,"original current rays/support allow scan adoption"): _finish(); return
    var ctx: Dictionary=adapter.context()
    _check(adapter.exchange_fact()=="","adoption retains source history without importing current Custody support time")
    for unused in 32:
        if not await _frame(): _finish(); return
        if adapter.exchange_fact()=="local_cooling": break
    if not _check(adapter.exchange_fact()=="local_cooling","fresh actual350ms Custody support proves current WORK cold preparation before Brief",{"custody":ctx.custody.report(),"support":ctx.custody.support_info(Wait.Rules.CASSETTES[1],Wait.Rules.WORK),"integrity":ctx.custody._integrity(Wait.Rules.CASSETTES[1])}): _finish(); return
    _check(ctx.rules.snapshot().cassettes[Wait.Rules.CASSETTES[1]].energy_mj==25000000 and ctx.executor._receipt_count==0 and "I2:canal_service:exchange" not in session.story.state.get("completed",[]) and "I2:canal_service:service" not in session.story.state.get("completed",[]),"45C local preparation creates no fake ten-receipt route or Canal Story completion",{"rules":ctx.rules.snapshot(),"prior_story_fixture":session.story.state.get("completed",[])})
    # The asynchronous pause handshake must finish a real SCAN capture before
    # freezing. Saving while paused uses that valid pre-stop cache, not a resume.
    var requested: Dictionary=adapter.request_pause()
    if not _check(requested.ok and requested.pending and not requested.ready,"scan pause request initially leaves real simulation running"): _finish(); return
    for unused in 24:
        if not await _frame(): _finish(); return
        if adapter.pause_request_status().ready: break
    var paused: Dictionary=adapter.pause_request_status()
    if not _check(paused.ok and paused.ready and adapter.capture_persistent_state().ok and adapter.prepare_scan_capture().ready,"SCAN handshake yields frozen physical state and valid paused save cache",paused): _finish(); return
    snapshots["scan_pause_boundary"]=adapter.pause_boundary_snapshot()
    session.simulation_paused=true
    if not await _exercise_session_save_gate(ctx): _finish(); return
    session.simulation_paused=false
    if not _check(adapter.set_paused(false).ok,"SCAN resumes original native momentum after paused original Store failure/success"): _finish(); return
    for unused in 900:
        if not await _frame(): _finish(); return
        if ctx.workbench._committed: break
    var state: Dictionary=ctx.rules.snapshot()
    if not _check(ctx.workbench._committed and state.jobs_completed==1 and state.thermal_ledger.work_added==Wait.Rules.WORK_HEAT_MJ and state.cassettes[Wait.Rules.CASSETTES[1]].energy_mj>25000000,"actual original three endpoints commit first-work1 and heat the same cassette"): _finish(); return
    _check(adapter.exchange_fact()=="local_cooling" and ctx.executor._receipt_count<10,"past preparation remains honest local_cooling after actual work heating")
    var no_thermal: Dictionary=state.duplicate(true)
    no_thermal.thermal_ledger.ability_removed=0
    _check(not adapter._story_service._local_cooling_prepared(ctx,no_thermal),"work history without original effective thermal removal cannot prove local cooling")
    if not await _save_restore("local_hot",0): _finish(); return
    _check(adapter.exchange_fact()=="","restored historical preparation never imports old current support credit")
    for unused in 90:
        if not await _frame(): _finish(); return
        if adapter.exchange_fact()=="local_cooling": break
    ctx=adapter.context()
    state=ctx.rules.snapshot()
    _check(adapter.exchange_fact()=="local_cooling" and ctx.workbench._progress_history.first_work.action.serial==1 and state.jobs_completed==1 and state.services_consumed==0 and ctx.executor._receipt_count<10,"original Store/fresh World retains pre-Brief proof only after new actual350ms support")
    _check(session.story.state==baseline_story and session.store.snapshot().personal.discoveries==baseline_discoveries and state.services_consumed==0,"proof adapter preserves seeded Story/discovery baseline and never claims a service",{"baseline":snapshots.declared_prior_baseline,"actual_story":session.story.state,"actual_discoveries":session.store.snapshot().personal.discoveries,"services_consumed":state.services_consumed})
    _finish()

func _finish() -> void:
    if done: return
    done=true
    if is_instance_valid(adapter.module): snapshots["final_status"]=adapter.module.status(true)
    if is_instance_valid(session): session.canal=null
    adapter.clear()
    if is_instance_valid(session): session.free()
    var result: Dictionary={"checks":checks.size(),"failures":failures,"engine_errors":logger.errors,"details":checks,"snapshots":snapshots,"scope":"actual pre-Brief local thermal scan fixture; asynchronous SCAN pause capture/cache, original Store failed/success save while paused; actual remaining three-endpoint work1 and work heating; versioned original Store/fresh World/new support preservation. local_cooling never certifies route or awards Story effects. Normal Consensus input, graphics and LAN remain separate Root evidence."}
    if not output.is_empty():
        var file:=FileAccess.open(output.path_join("result.json"),FileAccess.WRITE)
        if file: file.store_string(JSON.stringify(result,"\t",true,true))
    print("CANAL_LOCAL_COOLING ",JSON.stringify({"checks":checks.size(),"failures":failures,"engine_errors":logger.errors}))
    quit(0 if failures.is_empty() and logger.errors.is_empty() else 1)
