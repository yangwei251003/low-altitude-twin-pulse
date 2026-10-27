extends "res://tests_v3/candidates/canal_session/test_canal_departure.gd"
## Continue an actual saved post-work state. Cover remaining pickup/drop phases
## and the minimal prepare/Store/adopt Story bridge without redoing the scan.
const SERVICE_FIXTURE="res://tests_v3/candidates/canal_session/progress_fixture/actual_afterwork_route3.json"
const SERVICE_SHA="423a6921a2da27c2d072c39fc3f8891926a2f784b0ac14344c0c855b2800c184"
const PICKUP_FIXTURE="res://tests_v3/candidates/canal_session/progress_fixture/actual_commit_pick.json"
const PICKUP_SHA="bb7fd752f0d135710753c4e7337fa18ed18ec074a278575c1ff8a25e37d2f252"
const TRANSPORT_PHASES=["pickup_prepare","align","commit_pick","departure_wait","departure","travel","approach_wait","approach","release_wait","fall","fall_moving","commit_place","idle"]

func _run() -> void:
    var resume_pickup: bool="--commit-pickup" in OS.get_cmdline_user_args()
    var actual_fixture: String=PICKUP_FIXTURE if resume_pickup else SERVICE_FIXTURE
    var actual_sha: String=PICKUP_SHA if resume_pickup else SERVICE_SHA
    var required_phases: Array=TRANSPORT_PHASES.slice(2) if resume_pickup else TRANSPORT_PHASES.duplicate()
    create_timer(120).timeout.connect(func():
        if not done:
            _check(false,"bounded post-work cleanup and original Story service",adapter.module.status(true) if is_instance_valid(adapter.module) else adapter.status())
            _finish())
    if not _check(profile.begins_with("qa_canal_session_") and not DirAccess.dir_exists_absolute("user://profiles_v3/"+profile),"isolated original MAIN service profile"): _finish(); return
    if not _check(FileAccess.get_sha256(actual_fixture)==actual_sha,"pinned actual post-work source fixture",{"path":actual_fixture,"sha256":actual_sha,"continues_real_commit_pick":resume_pickup}): _finish(); return
    var fixture: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(actual_fixture))
    if not _check(Progress.validate(fixture).ok and fixture.rules.jobs_completed==1 and fixture.rules.services_consumed==0,"original saved work/departure/pending pickup remains valid"): _finish(); return
    session=MAIN.instantiate()
    root.add_child(session)
    session.set_process(false)
    session.set_physics_process(false)
    session.inputs.set_process(false)
    session.inputs.set_physics_process(false)
    session.canal_runtime_enabled=false
    if not _check(session.profile_ready and session.start_flight("solo"),"actual MAIN starts") or not _seed_old27(): _finish(); return
    if not _check(session.store.commit({"id":"qa-service-actual-afterwork","set":{"world.environment.I2_canal":fixture}}).ok,"same original Store imports declared historical afterwork"): _finish(); return
    session.world_cache=session.store.snapshot()
    if not _check(session._load_region("I2"),"fresh actual I2 World"): _finish(); return
    session.owns_world=false
    _player_pose(Vector3(8,3.2,27))
    adapter.setup(session)
    var prepared: Dictionary=adapter.prepare(session.world_cache.world,"I2",true)
    if not _check(prepared.ok and adapter.adopt(prepared).ok,"real saved afterwork builds frozen"): _finish(); return
    for unused in 20:
        if not await _frame(): _finish(); return
        if adapter.ready: break
    if not _check(adapter.ready,"frozen readback adopts without new work/service"): _finish(); return
    if resume_pickup and not await _save_restore("transport_commit_pick",0): _finish(); return
    for unused in 6000:
        if not await _frame(): _finish(); return
        var ctx: Dictionary=adapter.context()
        var label: String=str(ctx.executor._phase)
        if label=="commit": label="commit_"+str(ctx.executor._action.kind)
        if label=="travel" and ctx.carrier.linear_velocity.length()<.3: label=""
        if label=="idle" and (not ctx.executor._last_controller.get("arrived",false) or not ctx.carrier.cargo_items.is_empty()): label=""
        if label=="fall" and phases.has("transport_fall"):
            var id: String=str(ctx.executor._action.cassette_id)
            label="fall_moving" if ctx.cargos[id].linear_velocity.y<-.15 else ""
        if label in required_phases and not phases.has("transport_"+label):
            if not await _save_restore("transport_"+label,0): _finish(); return
            continue
        if phases.has("transport_idle") and adapter.story_service_status().ready_credit: break
    var missing: Array=[]
    for phase: String in required_phases:
        if not phases.has("transport_"+phase): missing.append(phase)
    if not _check(missing.is_empty() and adapter.story_service_status().ready_credit,"all actual remaining transport phases and continuous current Safe service",{"missing":missing,"service":adapter.story_service_status()}): _finish(); return
    _check(adapter.exchange_fact()=="low_route","real original ten receipts plus current unique docked custody expose low-route fact")
    var ctx: Dictionary=adapter.context()
    _check(ctx.rules.snapshot().jobs_completed==1 and ctx.rules.snapshot().service_credit==1 and ctx.executor._receipt_count==13,"cleanup adds only original pick/move/place receipts, no extra work or claim")
    session.owns_world=true
    session.players[1].freeze=false
    var far: Dictionary=adapter.prepare_story_service(1)
    _check(not far.ok and far.code=="service_out_of_range","service validates actual nearby player rather than payload position",far)
    _player_pose(Vector3(3.5,2.8,5.4)) # Declared PLAYER-only LOS fixture.
    session.players[1].freeze=false
    if not await _frame(): _finish(); return
    var actor: String=session._actor_id(1)
    var original_owner: String=str(session.entities[actor].owner)
    session.entities[actor].owner="other_peer"
    _check(not adapter.prepare_story_service(1).ok,"foreign-owned actor cannot prepare original service")
    session.entities[actor].owner=original_owner
    var blocker:=StaticBody3D.new()
    blocker.name="QA_Service_Actual_LOS_Blocker"
    blocker.collision_layer=1
    blocker.collision_mask=0
    var collision:=CollisionShape3D.new()
    var shape:=BoxShape3D.new()
    shape.size=Vector3(.18,.18,.18)
    collision.shape=shape
    blocker.add_child(collision)
    session.world.add_child(blocker)
    blocker.global_position=session.players[1].global_position.lerp(ctx.workbench.power_target.global_position,.5)
    blocker.force_update_transform()
    if not await _frame(): blocker.free(); _finish(); return
    var blocked: Dictionary=adapter.prepare_story_service(1)
    _check(not blocked.ok and blocked.code=="service_actual_los_blocked","actual same-world blocker denies Story service without consuming credit",blocked)
    blocker.free()
    if not await _frame(): _finish(); return
    var service: Dictionary=adapter.prepare_story_service(1)
    if not _check(service.ok and not service.duplicate and Progress.validate(service.envelope).ok,"host/LOS/current Safe prepares original consumed candidate",service if not service.ok else {}): _finish(); return
    _check(not adapter.adopt_story_service(service).ok and ctx.rules.snapshot().service_credit==1,"uncommitted service token cannot alter original Rules")
    var before: Dictionary=session.store.snapshot()
    session.store.failure_point="before_publish"
    _check(not session.store.commit({"id":"qa-story-service-failed","set":{"world.environment.I2_canal":service.envelope}}).ok and session.store.snapshot()==before and ctx.rules.snapshot().service_credit==1,"failed original Store transaction does not consume prepared credit")
    session.store.failure_point=""
    if not _check(session.store.commit({"id":"qa-story-service-atomic","set":{"world.environment.I2_canal":service.envelope}}).ok,"original Store commits candidate before adoption"): _finish(); return
    if not _check(adapter.adopt_story_service(service).ok,"post-Store bridge adopts original Rules and safe beneficiary wait"): _finish(); return
    session.owns_world=false
    if not await _save_restore("claimed",0): _finish(); return
    ctx=adapter.context()
    _player_pose(Vector3(3.5,2.8,5.4))
    session.players[1].freeze=false
    for unused in 90:
        if not await _frame(): _finish(); return
    session.owns_world=true
    var duplicate: Dictionary=adapter.prepare_story_service(1)
    if not _check(duplicate.ok and duplicate.duplicate and duplicate.healed_hp==0 and adapter.adopt_story_service(duplicate).ok,"persisted claim is idempotent after restore and never reapplies old health",duplicate if not duplicate.ok else {}): _finish(); return
    session.owns_world=false
    var state: Dictionary=ctx.rules.snapshot()
    _check(state.jobs_completed==1 and state.services_consumed==1 and state.service_credit==0 and state.service_serial==1 and state.pending_action.is_empty() and ctx.executor._waiting_for_beneficiary,"claimed restore plus ordinary ticks cannot manufacture job2 or second service")
    snapshots["phases"]=phases
    _finish()

func _finish() -> void:
    if done: return
    done=true
    if is_instance_valid(adapter.module): snapshots["final_status"]=adapter.module.status(true)
    if is_instance_valid(session): session.canal=null
    adapter.clear()
    if is_instance_valid(session): session.free()
    var result: Dictionary={"checks":checks.size(),"failures":failures,"engine_errors":logger.errors,"details":checks,"snapshots":snapshots,"scope":"pinned ACTUAL afterwork fixture; original same-anchor descent/pickup/departure/loaded travel/approach/free fall/cleanup idle captured through original MAIN Store and fresh Worlds; original prepare/Store/adopt service bridge and claimed idempotency. PLAYER LOS fixture explicit; Story action/reward/healing integration and LAN remain Root."}
    if not output.is_empty():
        var file:=FileAccess.open(output.path_join("result.json"),FileAccess.WRITE)
        if file: file.store_string(JSON.stringify(result,"\t",true,true))
    print("CANAL_SERVICE ",JSON.stringify({"checks":checks.size(),"failures":failures,"engine_errors":logger.errors}))
    quit(0 if failures.is_empty() and logger.errors.is_empty() else 1)
