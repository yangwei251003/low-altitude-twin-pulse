extends "res://tests_v3/candidates/canal_session/test_canal_session.gd"
## Same MAIN / Store. Historical WAIT is explicit; all NEW work/transport is real.
const Scan=Adapter.ScanCheckpoint
const Wait=Adapter.WaitCheckpoint
const Store=preload("res://scripts/v3/core/twin_world_store.gd")
const FIXTURE="res://tests_v3/candidates/canal_session/scan_fixture/actual_wait_78.json"
const FIXTURE_SHA="85da0cd7541076c33b7a00ce5ed3aa5ad83904b06feb0dd263602788aebbc9ea"
var exchange: bool=false
var first_capture: Dictionary={}
var obstruction: StaticBody3D
var sweep_block_tested: bool=false
var synchronized_samples: int=0
var endpoint_count: int=0

func _run() -> void:
    exchange="--exchange" in OS.get_cmdline_user_args()
    create_timer(245 if exchange else 65).timeout.connect(func():
        if not done:
            _check(false,"bounded scan restore probe",adapter.module.status(true) if is_instance_valid(adapter.module) else adapter.status())
            _finish())
    var script: Script=Adapter
    if not _check(script.can_instantiate(),"scan dependencies parse"): _finish(); return
    if not _check(profile.begins_with("qa_canal_session_") and not DirAccess.dir_exists_absolute("user://profiles_v3/"+profile),"isolated MAIN QA profile"): _finish(); return
    if not _check(FileAccess.get_sha256(FIXTURE)==FIXTURE_SHA,"original 78 PASS WAIT fixture bytes"): _finish(); return
    var fixture: Variant=JSON.parse_string(FileAccess.get_file_as_string(FIXTURE))
    if not _check(Wait.validate(fixture).ok,"historical WAIT validated unchanged"): _finish(); return
    session=MAIN.instantiate()
    root.add_child(session)
    session.set_process(false)
    session.set_physics_process(false)
    session.inputs.set_process(false)
    session.inputs.set_physics_process(false)
    if not _check(session.profile_ready and session.start_flight("solo"),"real MAIN started") or not _seed_old27(): _finish(); return
    var seeded: Dictionary=session.store.commit({"id":"qa-explicit-78-wait","set":{"world.environment.I2_canal":fixture}})
    if not _check(seeded.ok,"historical actual WAIT imported to same isolated Store"): _finish(); return
    session.world_cache=session.store.snapshot()
    if not _check(session._load_region("I2"),"actual production I2 loaded"): _finish(); return
    session.owns_world=false
    session.inputs.test_enabled=true
    session.inputs.test_frame={"axes":{},"held":["brake"]}
    _player_pose(Vector3(3.5,2.8,5.4))
    adapter.setup(session)
    var prepared: Dictionary=adapter.prepare(session.world_cache.world,"I2",true)
    var initial_adopt: Dictionary=adapter.adopt(prepared) if prepared.ok else {"ok":false,"code":"prepare_failed"}
    if not _check(prepared.ok and initial_adopt.ok,"same adapter restores historical WAIT before new work",{"prepare":prepared.get("code"),"adopt":initial_adopt}): _finish(); return
    for unused in 240:
        if not await _frame(): _finish(); return
        if adapter.ready: break
    if not _check(adapter.ready,"actual support allows WAIT adoption"): _finish(); return
    if not await _ability({"ability":"charge","target_id":Adapter.Assembly.Workbench.POWER_ID},"actual Rules/LOS charges workbench"): _finish(); return
    if not exchange:
        snapshots.original_work_los=_los_detail(Wait.Rules.CASSETTES[1])
        # Original playable work probe's successful western observation point.
        # This is a declared player-only LOS fixture, not a new travel proof.
        _player_pose(Vector3(2.5,3,8.5))
        if not await _frame(): _finish(); return
        if not await _ability({"ability":"heat","mode":"cool","target_id":Wait.Rules.CASSETTES[1]},"actual Rules/LOS cools supported WORK cartridge"): _finish(); return
    # Explicit range/LOS fixture, not a claimed player route. No owned cargo,
    # tool, carrier or beneficiary pose is changed by the probe.
    _player_pose(Vector3(8,3.2,27))
    if not await _frame(): _finish(); return
    if not await _ability({"ability":"takeover","target_id":Adapter.Assembly.CARRIER_ID},"actual Rules/LOS requests one work order"): _finish(); return
    var ctx: Dictionary=adapter.context()
    for unused in (13200 if exchange else 1800):
        if not await _frame(): _finish(); return
        var work: Dictionary=ctx.workbench.report()
        if work.measurements.size()>endpoint_count:
            if not _check(_tools_synchronized(ctx.workbench),"endpoint recorded only after actual PhysicsServer arrival",work): _finish(); return
            endpoint_count=work.measurements.size()
            synchronized_samples+=1
        if not sweep_block_tested and work.phase=="scan_out" and float(work.scan_distance_m)>.04:
            if not await _block_original_scan(ctx): _finish(); return
            sweep_block_tested=true
        if work.phase=="scan_back" and float(work.scan_distance_m)>.82 and ctx.executor.report().controller.get("arrived",false):
            if "--session-gate" in OS.get_cmdline_user_args():
                if not await _exercise_session_save_gate(ctx): _finish(); return
                work=ctx.workbench.report()
            _check(not adapter.capture_persistent_state().ok,"pure scan capture does not secretly settle or move a tool")
            var begun: Dictionary=adapter.prepare_scan_capture()
            if not _check(begun.ok and not begun.ready,"explicit scan barrier starts without claiming submitted target applied",begun): _finish(); return
            var target_before: Vector3=ctx.workbench.head.global_position
            var distance_before: float=float(work.scan_distance_m)
            var settled: Dictionary={}
            for unused_settle in Wait.Bench.CAPTURE_SETTLE_FRAMES+1:
                if not await _frame(): _finish(); return
                settled=adapter.prepare_scan_capture()
                if not settled.ok or settled.ready: break
            snapshots["capture_barrier"]=settled
            if not _check(settled.get("ready",false) and _tools_synchronized(ctx.workbench) and ctx.workbench.head.global_position==target_before and ctx.workbench.report().scan_distance_m==distance_before,"real physics settles unchanged target without scan progress",settled):
                adapter.release_scan_capture()
                _finish(); return
            synchronized_samples+=1
            first_capture=adapter.capture_persistent_state()
            if not first_capture.get("ok",false):
                snapshots["capture_rejection"]=adapter.module.capture_scan()
            break # Mature state: schema rejection fails immediately, never waits.
    if not _check(first_capture.get("ok",false),"actual partial scan captures once after two endpoint proofs",first_capture if not first_capture.is_empty() else adapter.module.status(true)): _finish(); return
    _check(sweep_block_tested and synchronized_samples==3,"original obstacle and actual endpoint/capture synchronization verified",{"samples":synchronized_samples})
    var original: Dictionary=first_capture.envelope.duplicate(true)
    snapshots.original_scan=original
    _check(original.kind==Scan.KIND and original.workbench.stage==2 and original.workbench.measurements.size()==2 and original.workbench.scan_distance_m>.82 and original.workbench.scan_distance_m<1.4,"original current stage/distance/partial endpoints retained")
    _check(original.executor.receipt_count==(10 if exchange else 0) and original.rules.pending_action.serial==(11 if exchange else 1),"occupancy is reached by actual original transport receipts",ctx.executor.report())
    _check(original.custody.version==(1 if exchange else 2) and ctx.carrier.cargo_items.size()==(0 if exchange else 1),"real empty/docked versus carried branch",ctx.custody.report())
    _check(original.rules.jobs_completed==0 and original.rules.service_credit==0 and original.rules.thermal_ledger.work_added==0,"no work receipt or credit before real tool completion")
    _check(not Wait.validate(original).ok and not Adapter.Assembly.Checkpoint.validate(original).ok,"scan is not weakened old WAIT or completed-safe")
    for field: String in ["stage","distance","endpoint","pending","duplicate_holder","tool","rules_type"]:
        var bad: Dictionary=original.duplicate(true)
        match field:
            "stage": bad.workbench.stage=0
            "distance": bad.workbench.scan_distance_m=1.4
            "endpoint": bad.workbench.measurements[0].hit[1]+=1
            "pending": bad.rules.pending_action.serial+=1
            "duplicate_holder": bad.rules.cassettes[Wait.Rules.CASSETTES[0]].holder=bad.rules.cassettes[Wait.Rules.CASSETTES[1]].holder
            "tool": bad.workbench.tools[0].pose[9]+=.1
            "rules_type": bad.rules=[]
        _check(not adapter.prepare({"environment":{"I2_canal":bad}},"I2",true).ok,"invalid scan "+field+" rejected without scene/disk mutation")
    var old_site: Node3D=adapter.module
    var replacement: Dictionary=adapter.prepare({"environment":{"I2_canal":original}},"I2",true)
    _check(replacement.ok and not adapter.adopt(replacement).ok and adapter.module==old_site,"candidate cannot replace an adopted live site")
    adapter.discard(replacement)
    if not _check(adapter.set_paused(true).ok,"pause freezes scan and pre-stop momentum"): _finish(); return
    session.simulation_paused=true
    for unused in 12:
        if not await _frame(): _finish(); return
    _check(adapter.capture_persistent_state().envelope==original,"paused envelope preserves original moving tool/counters")
    session.canal=adapter
    session.owns_world=true
    var disk_before: Dictionary=session.store.snapshot()
    session.store.failure_point="before_publish"
    _check(not session._save_environment() and session.store.snapshot()==disk_before and adapter.capture_persistent_state().envelope==original,"same Store failed write preserves paused live scan and old generation")
    _check(adapter.release_scan_capture().ok and adapter.release_scan_capture().ok and adapter.capture_persistent_state().envelope==original,"failed publication releases barrier idempotently without corrupting paused pre-stop capture")
    session.store.failure_point=""
    if not _check(session._save_environment(),"same MAIN Session transaction writes scan envelope"): _finish(); return
    var reopened=Store.new(session.store.root_path)
    if not _check(reopened.load_profile().ok,"same Store generation reopens"): _finish(); return
    var saved: Dictionary=reopened.snapshot().world.environment.I2_canal
    _check(session.store.matches_persisted_value(original,saved) and Scan.validate(saved).ok,"JSON retains all scan/controller/device/ledger values")
    _check(reopened.snapshot().generation==int(disk_before.generation)+1,"single generation no new repository")
    for id: String in Adapter.IDS: _check(not reopened.snapshot().world.entities.I2.has(id),"no split target save "+id)
    session.owns_world=false
    session.canal=null
    adapter.clear()
    session.simulation_paused=false
    session.world_cache=reopened.snapshot()
    if not _check(session._load_region("I2"),"fresh real MAIN I2 physical world"): _finish(); return
    session.owns_world=false
    _player_pose(Vector3(8,3.2,27))
    adapter.setup(session)
    prepared=adapter.prepare(session.world_cache.world,"I2",true)
    if not _check(prepared.ok and adapter.adopt(prepared).ok and not adapter.ready,"fresh scan construction is not ready/adopted yet"): _finish(); return
    var fresh_bodies: Array[Node]=adapter.module.find_children("*","RigidBody3D",true,false)
    var frozen: bool=fresh_bodies.size()==4
    for body: RigidBody3D in fresh_bodies: frozen=frozen and body.freeze
    _check(frozen and adapter.context().is_empty(),"all four bodies/controller/tools constructed frozen before validation")
    # A real small occluder lies in the restored head-to-beneficiary ray, not
    # within either body's volume. Historical endpoint facts cannot bypass it.
    obstruction=StaticBody3D.new()
    obstruction.name="QA_CurrentScanRayOccluder"
    obstruction.collision_layer=1
    obstruction.collision_mask=0
    var shape:=BoxShape3D.new()
    shape.size=Vector3(.03,.012,.03)
    var collision:=CollisionShape3D.new()
    collision.shape=shape
    obstruction.add_child(collision)
    session.world.add_child(obstruction)
    var tool: Vector3=Wait.State.vec(original.workbench.tool)
    obstruction.global_position=Vector3(tool.x,.855,tool.z)
    obstruction.force_update_transform()
    var no_progress: bool=true
    for unused in 45:
        if not await _frame(): _finish(); return
        var recovering: Dictionary=adapter.module._restorer._bench.report()
        no_progress=no_progress and not adapter.ready and recovering.scan_distance_m==original.workbench.scan_distance_m and recovering.tool_position==tool and not recovering.committed
    _check(no_progress,"new actual ray obstruction prevents ready/scan progress despite saved endpoint history")
    obstruction.free()
    obstruction=null
    for unused in 240:
        if not await _frame(): _finish(); return
        if adapter.ready: break
    if not _check(adapter.ready,"actual new support/rays release same-frame adopt",adapter.module.status(true)): _finish(); return
    ctx=adapter.context()
    var adopted: Dictionary=ctx.workbench.report()
    _check(adopted.scan_distance_m==original.workbench.scan_distance_m and adopted.tool_position==tool and adopted.phase=="scan_back" and not adopted.committed,"adopt keeps exact partial tool/distance/stage without advancing work")
    _check(Wait.Rules._same(ctx.rules.snapshot(),original.rules) and ctx.custody.last_serial==original.custody.last_serial and ctx.executor.report().receipt_count==original.executor.receipt_count,"original pending/ledger/custody/counters unchanged at adopt")
    _check(adopted.scan_source_observations==saved.workbench.measurements and adopted.scan_revalidated==2,"persisted endpoint records kept separately from new current-space rays")
    var fresh_rays: bool=adopted.measurements.size()==2
    for row: Dictionary in adopted.measurements: fresh_rays=fresh_rays and row.body_id==ctx.workbench.beneficiary.get_instance_id() and row.physics_frame>0
    _check(fresh_rays,"revalidation contains actual current beneficiary identity, not relabeled old body IDs")
    snapshots.adopted_scan=adopted
    snapshots.adopted_rules=ctx.rules.snapshot()
    for unused in 1200:
        if not await _frame(): _finish(); return
        var progress: Dictionary=ctx.workbench.report()
        if progress.measurements.size()>2 and endpoint_count==2:
            if not _check(_tools_synchronized(ctx.workbench),"remaining endpoint backed by actual physical tool after restore",progress): _finish(); return
            endpoint_count=3
        if progress.committed: break
    var completed: Dictionary=ctx.workbench.report()
    var state: Dictionary=ctx.rules.snapshot()
    if not _check(completed.committed,"remaining original physical scan commits after restore",completed): _finish(); return
    _check(completed.receipt_count==1 and state.jobs_completed==1 and state.service_credit==1 and state.thermal_ledger.work_added==Wait.Rules.WORK_HEAT_MJ,"one actual work receipt and original 25kJ/one credit only",state)
    _check(completed.measurements.size()==3 and absf(float(completed.scan_distance_m)-1.4)<.00001 and completed.tool_position==Wait.Bench.PARK,"original remaining scan completes full 1.4m then retracts")
    _check(completed.receipt.receipt.serial==original.rules.pending_action.serial and completed.receipt.source_observations==saved.workbench.measurements,"same reserved work serial with traceable persisted endpoint sources")
    var historical: Dictionary=Adapter.Assembly.Checkpoint.new()._history(completed,ctx.workbench.beneficiary,Engine.get_physics_frames())
    _check(not historical.is_empty() and Wait.Bench.History.validate(historical,state,Wait.Bench.POINT_A,Wait.Bench.POINT_B,Wait.Bench.TOOL_SIZE,Wait.Bench.Departure.ROUTE[-1]).ok,"new actual endpoint proof remains compatible with unchanged completed-safe history validator")
    for unused in 30:
        if not await _frame(): _finish(); return
    _check(ctx.rules.snapshot().jobs_completed==1 and ctx.rules.snapshot().service_credit==1 and ctx.workbench.report().receipt_count==1,"subsequent host ticks do not repeat completion")
    snapshots.final_rules=ctx.rules.snapshot()
    snapshots.final_workbench=ctx.workbench.report()
    _finish()

func _exercise_session_save_gate(ctx: Dictionary) -> bool:
    session.canal=adapter
    session.owns_world=true
    var before: Dictionary=session.store.snapshot()
    session.store.failure_point="before_publish"
    var begun: Dictionary=session.request_environment_save()
    if not _check(begun.ok and session.environment_save_gate.pending(),"Session accepts save intent without claiming publication"): return false
    var failed: Dictionary={}
    for unused in 16:
        if not await _frame(): return false
        failed=session._advance_environment_save()
        if failed.get("completed",false): break
    if not _check(failed.get("completed",false) and not failed.ok and session.store.snapshot()==before and ctx.workbench.scan_capture_status().requested_frame==-1,"asynchronous original Store failure preserves generation and releases moving scan",failed): return false
    session.store.failure_point=""
    begun=session.request_environment_save()
    var succeeded: Dictionary={}
    for unused in 16:
        if not await _frame(): return false
        succeeded=session._advance_environment_save()
        if succeeded.get("completed",false): break
    var disk=Store.new(session.store.root_path)
    if not _check(succeeded.get("ok",false) and disk.load_profile().ok and int(disk.snapshot().generation)==int(before.generation)+1 and Scan.validate(disk.snapshot().world.environment.I2_canal).ok and ctx.workbench.scan_capture_status().requested_frame==-1,"asynchronous Session publishes current physical scan once then releases",succeeded): return false
    snapshots.session_gate={"failed":failed,"succeeded":succeeded,"saved":disk.snapshot().world.environment.I2_canal}
    session.owns_world=false
    session.canal=null
    return await _frame()

func _player_pose(at: Vector3) -> void:
    var player: FlightBodyV2=session.players[1]
    player.freeze=true
    player.global_transform=Transform3D(Basis.IDENTITY,at)
    player.linear_velocity=Vector3.ZERO
    player.angular_velocity=Vector3.ZERO
    player.hold_height=at.y
    player.force_update_transform()
    PhysicsServer3D.body_set_state(player.get_rid(),PhysicsServer3D.BODY_STATE_TRANSFORM,player.global_transform)

func _tools_synchronized(bench: Node3D) -> bool:
    for part: AnimatableBody3D in bench._moving:
        if part.sync_to_physics or PhysicsServer3D.body_get_state(part.get_rid(),PhysicsServer3D.BODY_STATE_TRANSFORM)!=part.global_transform: return false
    return true

func _block_original_scan(ctx: Dictionary) -> bool:
    obstruction=StaticBody3D.new()
    obstruction.name="QA_OriginalToolSweepBlocker"
    obstruction.collision_layer=1
    obstruction.collision_mask=0
    var shape:=BoxShape3D.new()
    shape.size=Vector3(.06,.06,.06)
    var collision:=CollisionShape3D.new()
    collision.shape=shape
    obstruction.add_child(collision)
    session.world.add_child(obstruction)
    obstruction.global_position=ctx.workbench.head.global_position+Vector3(.14,0,0)
    obstruction.force_update_transform()
    var blocked: Dictionary={}
    for unused in 120:
        if not await _frame(): return false
        var observed: Dictionary=ctx.workbench.report()
        if observed.code=="tool_blocked": blocked=observed; break
    if not _check(not blocked.is_empty(),"original full tool sweep rejects actual obstacle",ctx.workbench.report()): return false
    var unchanged: bool=true
    for unused in 30:
        if not await _frame(): return false
        var observed: Dictionary=ctx.workbench.report()
        unchanged=unchanged and observed.code=="tool_blocked" and observed.tool_position==blocked.tool_position and observed.scan_distance_m==blocked.scan_distance_m and not observed.committed and _tools_synchronized(ctx.workbench)
    var valid: bool=_check(unchanged,"blocked tool keeps actual pose and distance without receipt",blocked.motion)
    obstruction.free()
    obstruction=null
    return valid

func _ability(payload: Dictionary, label: String) -> bool:
    for unused in 60:
        if float(session.cooldowns.get(1,0))<=0: break
        if not await _frame(): return false
    var result: Dictionary=adapter.use_ability(1,payload)
    if not result.ok: result["actual_los"]=_los_detail(str(payload.target_id))
    return _check(result.ok,label,result)

func _los_detail(target_id: String) -> Dictionary:
    var player: FlightBodyV2=session.players[1]
    var target: Node3D=session.world.objects[target_id]
    var query:=PhysicsRayQueryParameters3D.create(player.global_position,target.global_position,1|8)
    query.exclude=[player.get_rid()]
    var hit: Dictionary=session.get_world_3d().direct_space_state.intersect_ray(query)
    return {"from":Wait.State.xyz(player.global_position),"to":Wait.State.xyz(target.global_position),"first":str(hit.collider.get_path()) if not hit.is_empty() else "", "entity_id":str(hit.collider.get_meta("entity_id","")) if not hit.is_empty() else "", "hit":Wait.State.xyz(hit.position) if not hit.is_empty() else []}

func _finish() -> void:
    if done: return
    done=true
    snapshots.final_status=adapter.status()
    if is_instance_valid(adapter.module): snapshots.final_site=adapter.module.status(true)
    if is_instance_valid(obstruction): obstruction.free()
    if is_instance_valid(session): session.canal=null
    adapter.clear()
    if is_instance_valid(session): session.free()
    var result: Dictionary={"checks":checks.size(),"failures":failures,"engine_errors":logger.errors,"details":checks,"snapshots":snapshots,"scope":"same MAIN and Store partial first-work scan; actual exchange" if exchange else "same MAIN and Store partial first-work scan; in-place cooling; restored historical 78 WAIT and QA player LOS placements are fixtures"}
    if not output.is_empty():
        var file:=FileAccess.open(output.path_join("result.json"),FileAccess.WRITE)
        if file: file.store_string(JSON.stringify(result,"\t",true,true))
    print("CANAL_SCAN ",JSON.stringify({"checks":checks.size(),"failures":failures,"engine_errors":logger.errors}))
    quit(0 if failures.is_empty() and logger.errors.is_empty() else 1)
