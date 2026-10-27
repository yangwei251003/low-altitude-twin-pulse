extends "res://tests_v3/candidates/canal_session/test_canal_scan.gd"
## Original fresh Bootstrap, saved/restored at every distinct controller phase.
const Startup=Adapter.StartupCheckpoint
const PHASES=["initial_contacts","seating","align","lift_wait","lift","travel","verify_wait","waiting"]
var phase_captures: Dictionary={}

func _run() -> void:
    create_timer(90).timeout.connect(func():
        if not done:
            _check(false,"bounded bootstrap sequence",adapter.module.status(true) if is_instance_valid(adapter.module) else adapter.status())
            _finish())
    if not _check(profile.begins_with("qa_canal_session_") and not DirAccess.dir_exists_absolute("user://profiles_v3/"+profile),"isolated startup MAIN profile"): _finish(); return
    session=MAIN.instantiate()
    root.add_child(session)
    session.set_process(false)
    session.set_physics_process(false)
    session.inputs.set_process(false)
    session.inputs.set_physics_process(false)
    session.canal_runtime_enabled=false
    if not _check(session.profile_ready and session.start_flight("solo"),"real MAIN starts") or not _seed_old27(): _finish(); return
    if not _check(session._load_region("I2"),"real production I2 fresh site"): _finish(); return
    session.owns_world=false
    _player_pose(Vector3(3,3.2,27))
    adapter.setup(session)
    var prepared: Dictionary=adapter.prepare(session.world_cache.world,"I2",true)
    if not _check(prepared.ok and adapter.adopt(prepared).ok,"original fresh Bootstrap starts without fixture work or Rules"): _finish(); return
    for unused in 5200:
        if not await _frame(): _finish(); return
        var module=adapter.module
        var phase: String="waiting" if module._ready_for_order else str(module.bootstrap.phase)
        if phase in PHASES and not phase_captures.has(phase):
            if not await _save_restore_phase(phase): _finish(); return
        if phase_captures.size()==PHASES.size() and adapter.ready:
            var ctx: Dictionary=adapter.context()
            if ctx.workbench._support_stable>=.35 and ctx.carrier.global_position.distance_to(Wait.Executor.WAIT_POINT)<.18: break
    if not _check(phase_captures.size()==PHASES.size() and adapter.ready,"all eight original phases resume through actual WAIT",phase_captures.keys()): _finish(); return
    var ctx: Dictionary=adapter.context()
    _check(ctx.rules.snapshot().jobs_completed==0 and ctx.rules.snapshot().service_credit==0 and ctx.rules.snapshot().pending_action.is_empty() and not adapter.module._ordered,"bootstrap never manufactures a transport order/work/service")
    _check(ctx.carrier.cargo_items.size()==1 and ctx.custody.report().cargos[Wait.Rules.CASSETTES[0]].phase=="carried","one real original cold load remains attached")
    snapshots["phases"]=phase_captures
    snapshots["final"]=adapter.module.status(true)
    _finish()

func _save_restore_phase(phase: String) -> bool:
    var capture: Dictionary=adapter.capture_persistent_state()
    if not _check(capture.ok and capture.envelope.kind==Startup.KIND and Startup.validate(capture.envelope).ok,"capture actual startup "+phase,capture if not capture.ok else {}): return false
    var source: Dictionary=capture.envelope
    if phase!="waiting":
        _check(source.rules.is_empty() and source.workbench.is_empty() and source.rule_usec==0 and source.rule_seconds==0,"Rules/workbench/clock remain absent before WAIT: "+phase)
        _check(source.bodies[Wait.Rules.CARRIER].freeze==(phase in ["initial_contacts","seating"]),"original carrier freeze is phase-specific: "+phase)
        if phase=="initial_contacts": _check(source.custody.is_empty() and source.cooling.is_empty(),"initial contacts does not invent Custody/Cooling")
    var gate: Dictionary=adapter.prepare_scan_capture()
    if not _check(gate.ok and gate.ready and not gate.required,"startup needs no stationary scan barrier: "+phase,gate): return false
    session.canal=adapter
    session.owns_world=true
    if not _check(session._save_environment(),"original MAIN Store saves startup "+phase): return false
    var reopened=Store.new(session.store.root_path)
    if not _check(reopened.load_profile().ok,"original Store reopens startup "+phase): return false
    var saved: Dictionary=reopened.snapshot().world.environment.I2_canal
    if not _check(session.store.matches_persisted_value(source,saved) and Startup.validate(saved).ok,"startup JSON preserves present/absent modules "+phase): return false
    session.canal=null
    session.owns_world=false
    adapter.clear()
    session.world_cache=reopened.snapshot()
    if not _check(session._load_region("I2"),"fresh current World for "+phase): return false
    session.owns_world=false
    _player_pose(Vector3(3,3.2,27))
    adapter.setup(session)
    var prepared: Dictionary=adapter.prepare(session.world_cache.world,"I2",true)
    if not _check(prepared.ok and adapter.adopt(prepared).ok,"startup constructed frozen "+phase): return false
    for unused in 20:
        if not await _frame(): return false
        if not adapter.module.status().restore_pending: break
    if not _check(not adapter.module.status().restore_pending,"current frozen PS/joint observation adopts "+phase,adapter.module.status(true)): return false
    var ctx: Dictionary=adapter.context()
    _check(ctx.carrier.freeze==bool(saved.bodies[Wait.Rules.CARRIER].freeze),"carrier original mode restored once "+phase)
    for id: String in Wait.Rules.CASSETTES:
        _check(not ctx.cargos[id].freeze and ctx.cargos[id].global_transform==Wait.State.transform(saved.bodies[id].pose) and ctx.cargos[id].linear_velocity==Wait.State.vec(saved.bodies[id].velocity),"cargo original momentum and simulation restored "+phase+":"+id)
    if phase!="waiting":
        _check(ctx.rules==null and not is_instance_valid(ctx.workbench) and adapter.module.bootstrap.phase==phase,"Bootstrap resumes itself without early Rules/workbench "+phase)
        _check(adapter.module.bootstrap._ticks==int(saved.controller.fields._ticks) and adapter.module.bootstrap._serial==int(saved.controller.fields._serial) and adapter.module.bootstrap._leg==int(saved.controller.fields._leg),"startup counters/route did not replay or advance "+phase)
    var immediate: Dictionary=adapter.capture_persistent_state()
    if not _check(immediate.ok and immediate.envelope.kind==Startup.KIND and Startup.validate(immediate.envelope).ok,"startup immediate zero-credit resave "+phase,immediate if not immediate.ok else {}): return false
    phase_captures[phase]={"source":source,"restored":immediate.envelope}
    return true

func _finish() -> void:
    if done: return
    done=true
    if is_instance_valid(session): session.canal=null
    adapter.clear()
    if is_instance_valid(session): session.free()
    var result: Dictionary={"checks":checks.size(),"failures":failures,"engine_errors":logger.errors,"details":checks,"snapshots":snapshots,"scope":"actual fresh Bootstrap saved/restored in eight phases through original MAIN Store; no synthetic WAIT/transport/work fixture"}
    if not output.is_empty():
        var file:=FileAccess.open(output.path_join("result.json"),FileAccess.WRITE)
        if file: file.store_string(JSON.stringify(result,"\t",true,true))
    print("CANAL_STARTUP ",JSON.stringify({"checks":checks.size(),"failures":failures,"engine_errors":logger.errors}))
    quit(0 if failures.is_empty() and logger.errors.is_empty() else 1)
