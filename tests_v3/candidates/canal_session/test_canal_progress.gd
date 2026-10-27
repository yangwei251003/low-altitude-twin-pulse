extends "res://tests_v3/candidates/canal_session/test_canal_scan.gd"
## First bounded batch: actual transport motion, same Store, fresh frozen rebuild.
const Progress=Adapter.ProgressCheckpoint

func _run() -> void:
    create_timer(90).timeout.connect(func():
        if not done:
            _check(false,"bounded ongoing transport restore",adapter.module.status(true) if is_instance_valid(adapter.module) else adapter.status())
            _finish())
    if not _check(profile.begins_with("qa_canal_session_") and not DirAccess.dir_exists_absolute("user://profiles_v3/"+profile),"new isolated MAIN profile"): _finish(); return
    if not _check(FileAccess.get_sha256(FIXTURE)==FIXTURE_SHA,"original WAIT source bytes unchanged"): _finish(); return
    var fixture: Variant=JSON.parse_string(FileAccess.get_file_as_string(FIXTURE))
    if not _check(Wait.validate(fixture).ok,"old WAIT validator unchanged"): _finish(); return
    session=MAIN.instantiate()
    root.add_child(session)
    session.set_process(false)
    session.set_physics_process(false)
    session.inputs.set_process(false)
    session.inputs.set_physics_process(false)
    session.canal_runtime_enabled=false
    if not _check(session.profile_ready and session.start_flight("solo"),"actual MAIN starts") or not _seed_old27(): _finish(); return
    var seeded: Dictionary=session.store.commit({"id":"qa-progress-actual-wait","set":{"world.environment.I2_canal":fixture}})
    if not _check(seeded.ok,"same Store imports explicit historical WAIT fixture"): _finish(); return
    session.world_cache=session.store.snapshot()
    if not _check(session._load_region("I2"),"actual production I2"): _finish(); return
    session.owns_world=false
    _player_pose(Vector3(8,3.2,27))
    adapter.setup(session)
    var prepared: Dictionary=adapter.prepare(session.world_cache.world,"I2",true)
    if not _check(prepared.ok and adapter.adopt(prepared).ok,"restores actual WAIT source"): _finish(); return
    for unused in 240:
        if not await _frame(): _finish(); return
        if adapter.ready: break
    if not _check(adapter.ready,"actual WAIT contact/hold ready"): _finish(); return
    if not await _ability({"ability":"takeover","target_id":Adapter.Assembly.CARRIER_ID},"real Rules/LOS starts original automatic exchange"): _finish(); return
    var ctx: Dictionary=adapter.context()
    var captured: Dictionary={}
    for unused in 1200:
        if not await _frame(): _finish(); return
        if ctx.executor.report().phase=="travel" and ctx.carrier.linear_velocity.length()>.8 and ctx.carrier.global_position.distance_to(Wait.Executor.WAIT_POINT)>.6:
            var gate: Dictionary=adapter.prepare_scan_capture()
            if not _check(gate.ok and gate.ready and not gate.required,"transport does not request stationary scan barrier",gate): _finish(); return
            captured=adapter.capture_persistent_state()
            break
    if not _check(captured.get("ok",false),"actual moving carrier captured",captured if not captured.is_empty() else adapter.module.status(true)): _finish(); return
    var original: Dictionary=captured.envelope
    snapshots["original_transport"]=original
    _check(original.kind==Progress.KIND and Progress.validate(original).ok,"separate progress kind validates")
    _check(not Wait.validate(original).ok and not Scan.validate(original).ok,"progress does not relax old WAIT or SCAN")
    _check(Wait.State.vec(original.carrier.velocity).length()>.8 and original.executor.fields._phase=="travel","nonstationary velocity and phase preserved")
    _check(original.custody.joint.cargo_id==Wait.Rules.CASSETTES[0] and original.rules.jobs_completed==0 and original.rules.service_credit==0,"real original joint and no invented work credit")
    for field: String in ["velocity","phase","pending","joint","credit","body_registry"]:
        var invalid: Dictionary=original.duplicate(true)
        match field:
            "velocity": invalid.carrier.velocity=[1000,0,0]
            "phase": invalid.executor.fields._phase="completed"
            "pending": invalid.rules.pending_action.serial+=1
            "joint": invalid.custody.joint.local_a=[100,0,0]
            "credit": invalid.rules.service_credit=5
            "body_registry": invalid.bodies.erase(Wait.Rules.CASSETTES[0])
        var bad: Dictionary=adapter.prepare({"environment":{"I2_canal":invalid}},"I2",true)
        _check(not bad.ok,"invalid progress rejected: "+field,bad)
        if bad.ok: adapter.discard(bad)
    session.canal=adapter
    session.owns_world=true
    var before: Dictionary=session.store.snapshot()
    session.store.failure_point="before_publish"
    _check(not session._save_environment() and session.store.snapshot()==before,"original Store failed publication preserves generation")
    session.store.failure_point=""
    if not _check(session._save_environment(),"same Session transaction saves moving progress"): _finish(); return
    var reopened=Store.new(session.store.root_path)
    if not _check(reopened.load_profile().ok,"same Store reopens"): _finish(); return
    var saved: Dictionary=reopened.snapshot().world.environment.I2_canal
    _check(session.store.matches_persisted_value(original,saved) and Progress.validate(saved).ok,"JSON roundtrip preserves source motion/controllers/rules")
    session.canal=null
    session.owns_world=false
    adapter.clear()
    session.world_cache=reopened.snapshot()
    if not _check(session._load_region("I2"),"new production I2 world"): _finish(); return
    session.owns_world=false
    _player_pose(Vector3(8,3.2,27))
    adapter.setup(session)
    prepared=adapter.prepare(session.world_cache.world,"I2",true)
    if not _check(prepared.ok and adapter.adopt(prepared).ok and not adapter.ready,"new progress subtree starts frozen/unadopted"): _finish(); return
    for body: RigidBody3D in adapter.module.find_children("*","RigidBody3D",true,false):
        _check(body.freeze,"fresh body frozen before adoption: "+str(body.name))
    for unused in 20:
        if not await _frame(): _finish(); return
        if adapter.ready: break
    if not _check(adapter.ready,"strict frozen PS/joint readback allows current-frame adoption",adapter.status()): _finish(); return
    ctx=adapter.context()
    _check(ctx.carrier.global_transform==Wait.State.transform(saved.carrier.pose) and ctx.carrier.linear_velocity==Wait.State.vec(saved.carrier.velocity),"adoption restores exact saved native pose and momentum once")
    _check(Wait.Rules._same(ctx.rules.snapshot(),saved.rules) and ctx.executor._phase==saved.executor.fields._phase and ctx.executor._path_index==saved.executor.fields._path_index,"restore never advances rule clock/action/route index")
    _check(ctx.executor._receipt_count==int(saved.executor.fields._receipt_count) and ctx.workbench._receipt_count==0,"no receipt or service during restore")
    var carried: String=str(saved.custody.joint.cargo_id)
    var joint: PinJoint3D=ctx.carrier.cargo_items[carried].joint
    _check(PhysicsServer3D.pin_joint_get_local_a(joint.get_rid())==Wait.State.vec(saved.custody.joint.local_a) and PhysicsServer3D.pin_joint_get_local_b(joint.get_rid())==Wait.State.vec(saved.custody.joint.local_b),"original real local joint anchors read back")
    var immediate: Dictionary=adapter.capture_persistent_state()
    _check(immediate.ok and Progress.validate(immediate.envelope).ok,"same adoption frame can save with zero new contact credit",immediate if not immediate.ok else {})
    var early_samples: int=0
    for unused in 10:
        if not await _frame(): _finish(); return
        var early: Dictionary=adapter.capture_persistent_state()
        if not _check(early.ok and Progress.validate(early.envelope).ok,"new contact revalidation permits early resave "+str(unused),early if not early.ok else {}): _finish(); return
        early_samples+=1
    _check(early_samples==10,"repeated resaves during first 167ms do not restore old stability")
    var at: Vector3=ctx.carrier.global_position
    for unused in 60:
        if not await _frame(): _finish(); return
    _check(ctx.carrier.global_position.distance_to(at)>.3 and ctx.executor.report().phase!="fault","original real transport resumes movement")
    _check(ctx.rules.status().elapsed_usec>int(saved.rule_usec) and ctx.rules.snapshot().jobs_completed==0,"only resumed real ticks advance clock, no work credited")
    snapshots["resumed_progress"]=adapter.module.status(true)
    _finish()

func _finish() -> void:
    if done: return
    done=true
    snapshots["final_status"]=adapter.status()
    if is_instance_valid(session): session.canal=null
    adapter.clear()
    if is_instance_valid(session): session.free()
    var result: Dictionary={"checks":checks.size(),"failures":failures,"engine_errors":logger.errors,"details":checks,"snapshots":snapshots,"scope":"actual moving transport capture/Store/fresh frozen restore; historical WAIT and player LOS placement explicit fixtures; no audio/listening/LAN claim"}
    if not output.is_empty():
        var file:=FileAccess.open(output.path_join("result.json"),FileAccess.WRITE)
        if file: file.store_string(JSON.stringify(result,"\t",true,true))
    print("CANAL_PROGRESS ",JSON.stringify({"checks":checks.size(),"failures":failures,"engine_errors":logger.errors}))
    quit(0 if failures.is_empty() and logger.errors.is_empty() else 1)
