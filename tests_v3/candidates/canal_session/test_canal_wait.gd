extends "res://tests_v3/candidates/canal_session/test_canal_session.gd"
## Actual MAIN + old27 entry fixture. No new work or fake carried/docked state.
const Wait=Adapter.WaitCheckpoint
const Store=preload("res://scripts/v3/core/twin_world_store.gd")
var restored_rules: Dictionary={}

func _run() -> void:
    create_timer(55).timeout.connect(func():
        if not done:
            _check(false,"55 second WAIT restore bound",adapter.status())
            _finish())
    if not _check(profile.begins_with("qa_canal_session_") and not DirAccess.dir_exists_absolute("user://profiles_v3/"+profile),"isolated new QA profile"): _finish(); return
    var script: Script=Adapter
    if not _check(script.can_instantiate(),"WAIT adapter parses before MAIN mutation"): _finish(); return
    session=MAIN.instantiate()
    root.add_child(session)
    session.set_process(false)
    session.set_physics_process(false)
    session.inputs.set_process(false)
    session.inputs.set_physics_process(false)
    if not _check(session.profile_ready and session.start_flight("solo"),"real MAIN starts") or not _seed_old27(): _finish(); return
    if not _check(session._load_region("I2"),"real production I2 and four facilities"): _finish(); return
    session.owns_world=false
    session.inputs.test_enabled=true
    session.inputs.test_frame={"axes":{},"held":["brake"]}
    var player: FlightBodyV2=session.players[1]
    # Sole initial QA player pose; no owned transport/beneficiary/cargo moves.
    player.freeze=true
    player.global_transform=Transform3D(Basis.IDENTITY,Vector3(8,3.2,27))
    player.linear_velocity=Vector3.ZERO
    player.angular_velocity=Vector3.ZERO
    player.hold_height=player.global_position.y
    player.force_update_transform()
    PhysicsServer3D.body_set_state(player.get_rid(),PhysicsServer3D.BODY_STATE_TRANSFORM,player.global_transform)
    await physics_frame
    adapter.setup(session)
    var prepared: Dictionary=adapter.prepare(session.world_cache.world,"I2",true)
    if not _check(prepared.ok and adapter.adopt(prepared).ok,"fresh site starts physical Bootstrap"): _finish(); return
    _check(not adapter.capture_persistent_state().ok,"Bootstrap cannot masquerade as saveable WAIT")
    var captured: Dictionary={}
    for unused in 2700:
        if not await _frame(): _finish(); return
        if adapter.ready and _capture_preconditions_mature():
            captured=adapter.capture_persistent_state()
            break # A mature schema/body rejection is permanent: do not wait it out.
    if not _check(captured.get("ok",false),"real carried WAIT and rack/support are capturable",captured): _finish(); return
    var ctx: Dictionary=adapter.context()
    var charged: Dictionary=adapter.use_ability(1,{"ability":"charge","target_id":Adapter.Assembly.RELAY_ID})
    if not _check(charged.ok,"actual MAIN Rules/LOS charge before saved device state",charged): _finish(); return
    for unused in 24:
        if not await _frame(): _finish(); return
    var pushed: Dictionary=adapter.use_ability(1,{"ability":"push_pull","mode":"pull","target_id":Adapter.Assembly.VALVE_ID})
    if not _check(pushed.ok,"actual MAIN Rules/LOS slider input before capture",pushed): _finish(); return
    if not await _frame(): _finish(); return
    captured=adapter.capture_persistent_state()
    if not _check(captured.ok,"capture original nonzero device/counters",captured): _finish(); return
    var original: Dictionary=captured.envelope.duplicate(true)
    var joint: PinJoint3D=ctx.carrier.cargo_joint
    _check(Wait.State.vec(original.custody.joint.local_a)==PhysicsServer3D.pin_joint_get_local_a(joint.get_rid()) and Wait.State.vec(original.custody.joint.local_b)==PhysicsServer3D.pin_joint_get_local_b(joint.get_rid()),"saved exact actual two local PinJoint anchors")
    _check(original.rules.action_serial==0 and original.rules.jobs_completed==0 and original.rules.service_credit==0,"un-ordered WAIT is not a pickup/work receipt")
    var freeze: Dictionary=adapter.set_paused(true)
    if not _check(freeze.ok,"pause captures whole WAIT before stopping controls",freeze): _finish(); return
    session.simulation_paused=true
    for unused in 12:
        if not await _frame(): _finish(); return
    var paused: Dictionary=adapter.capture_persistent_state()
    if not _check(paused.ok and paused.envelope==original,"paused save uses exact pre-stop flight/device/ledger snapshot",paused): _finish(); return
    # Actual shared Session transaction; the original Store alone owns disk.
    session.canal=adapter
    session.owns_world=true
    var disk_before: Dictionary=session.store.snapshot()
    session.store.failure_point="before_publish"
    var refused_save: bool=session._save_environment()
    _check(not refused_save and session.store.snapshot()==disk_before and adapter.capture_persistent_state().envelope==original,"Store before_publish failure preserves old generation and actual paused scene")
    session.store.failure_point=""
    if not _check(session._save_environment(),"original Session _save_environment commits WAIT through same Store"): _finish(); return
    _check(session.store.snapshot().generation==int(disk_before.generation)+1,"one original generation commit, no second repository")
    for id: String in Adapter.IDS:
        _check(not session.store.snapshot().world.entities.I2.has(id),"no partial charge/temperature record for "+id)
    var reopened=Store.new(session.store.root_path)
    if not _check(reopened.load_profile().ok,"reopen actual checksum/rename generation"): _finish(); return
    var encoded: Variant=reopened.snapshot().world.environment.I2_canal
    _check(session.store.matches_persisted_value(original,encoded),"read-back full WAIT equals authority envelope")
    session.owns_world=false
    if not _check(Wait.validate(encoded).ok,"strict envelope survives JSON roundtrip"): _finish(); return
    for malformed_rules: Variant in [[],null,"not_a_rule_ledger"]:
        var bad_rules: Dictionary=encoded.duplicate(true)
        bad_rules.rules=malformed_rules
        var type_rejection: Dictionary=Wait.validate(bad_rules)
        _check(not type_rejection.ok and type_rejection.code=="wait_rule_ledger_type","malformed rules type is atomically rejected",{"type":typeof(malformed_rules),"result":type_rejection})
    _check(not Adapter.Assembly.Checkpoint.validate(encoded).ok,"old completed-safe v3 cannot accept carried WAIT")
    for field: String in ["version","joint","double_owner","filter","clock","pending"]:
        var bad: Dictionary=encoded.duplicate(true)
        match field:
            "version": bad.version=2
            "joint": bad.custody.joint.local_b=[10,0,0]
            "double_owner": bad.custody.cargos[Wait.Rules.CASSETTES[1]].carrier=Wait.Rules.CARRIER
            "filter": bad.bodies[Wait.Rules.CASSETTES[0]].mask=33
            "clock": bad.rule_usec+=1
            "pending": bad.rules.pending_action={"serial":1}
        _check(not adapter.prepare({"environment":{"I2_canal":bad}},"I2",true).ok,"malformed "+field+" refused before creating any body")
    var existing: Dictionary=adapter.prepare({"environment":{"I2_canal":encoded}},"I2",true)
    _check(existing.ok and not adapter.adopt(existing).ok and ctx.carrier.cargo_joint==joint,"restore cannot replace a still valid old Assembly")
    adapter.discard(existing)
    snapshots.saved_wait=original
    # End old site deliberately only after all negative checks. Root owns real
    # Store transaction/region replacement; this short probe tests new-body path.
    session.canal=null
    adapter.clear()
    session.simulation_paused=false
    session.world_cache=reopened.snapshot()
    if not _check(session._load_region("I2"),"MAIN creates fresh physical I2 for restore"): _finish(); return
    session.owns_world=false
    session.players[1].freeze=true # keep real MAIN player out of restore fixture
    adapter.setup(session)
    prepared=adapter.prepare(session.world_cache.world,"I2",true)
    if not _check(prepared.ok and adapter.adopt(prepared).ok and not adapter.ready,"saved route begins frozen and does not Bootstrap"): _finish(); return
    var frozen_bodies: Array[Node]=adapter.module.find_children("*","RigidBody3D",true,false)
    var all_frozen: bool=frozen_bodies.size()==4
    for body: RigidBody3D in frozen_bodies: all_frozen=all_frozen and body.freeze
    _check(all_frozen and adapter.context().is_empty(),"all four exact bodies constructed before any are unfrozen")
    snapshots.prepared_restore=adapter.module.status(true)
    for unused in 240:
        if not await _frame(): _finish(); return
        if adapter.ready: break
    if not _check(adapter.ready,"new real support and original joint reach current-frame adopt",adapter.module.status(true)): _finish(); return
    ctx=adapter.context()
    var rebuilt: PinJoint3D=ctx.carrier.cargo_joint
    _check(PhysicsServer3D.pin_joint_get_local_a(rebuilt.get_rid())==Wait.State.vec(original.custody.joint.local_a) and PhysicsServer3D.pin_joint_get_local_b(rebuilt.get_rid())==Wait.State.vec(original.custody.joint.local_b),"new real joint keeps both original local anchors exactly")
    _check(rebuilt.exclude_nodes_from_collision==original.custody.joint.exclude_pair and rebuilt.get_param(PinJoint3D.PARAM_BIAS)==original.custody.joint.bias and rebuilt.get_param(PinJoint3D.PARAM_DAMPING)==original.custody.joint.damping and rebuilt.get_param(PinJoint3D.PARAM_IMPULSE_CLAMP)==original.custody.joint.impulse_clamp,"joint parameters and pair filtering preserved")
    _check(ctx.carrier.cargo_items.size()==1 and ctx.carrier.cargo_items[Wait.Rules.CASSETTES[0]].body==ctx.cargos[Wait.Rules.CASSETTES[0]] and ctx.carrier.cargo_kg==2 and ctx.cargos[Wait.Rules.CASSETTES[0]].collision_mask==Wait.Custody.MASK,"one actual carried load and original collision mask")
    _check(ctx.rules.snapshot()==original.rules and ctx.custody.last_serial==original.custody.last_serial and ctx.custody.revision==original.custody.revision,"adopt preserves original Rules and custody counters without pickup receipt")
    _check(not adapter.module.status().ordered and adapter.module.status(true).bootstrap.phase=="not_started_saved_path","restored controller remains un-ordered WAIT with no Bootstrap")
    restored_rules=ctx.rules.snapshot()
    for unused in 66:
        if not await _frame(): _finish(); return
    _check(ctx.carrier.cargo_joint==rebuilt and ctx.rules.snapshot().action_serial==0 and ctx.rules.snapshot().jobs_completed==0 and ctx.rules.snapshot().service_credit==0 and ctx.rules.snapshot().pending_action.is_empty(),"1.1s normal host resumes one joint with no duplicate job/receipt/credit")
    _check(ctx.carrier.collision_count==original.carrier.wait.collision_count and ctx.carrier.health==original.carrier.health and ctx.carrier.battery<=original.carrier.state.battery and ctx.workbench.beneficiary.health==original.workbench.beneficiary.health,"no contact or free health/battery refill on restore")
    _check(ctx.carrier.global_position.distance_to(Wait.Executor.WAIT_POINT)<.18 and ctx.custody.support_info(Wait.Rules.CASSETTES[1],Wait.Rules.WORK).supported,"actual loaded hold and other cassette's real support continue")
    _finish()

func _capture_preconditions_mature() -> bool:
    var ctx: Dictionary=adapter.context()
    if not adapter.module._waiting.report().arrived or ctx.workbench.report().support_stable_seconds<.7: return false
    for body: FlightBodyV2 in [ctx.carrier,ctx.workbench.beneficiary]:
        for stamp: Variant in body.contact_cooldowns.values():
            if not Wait.State.number(stamp,0,body.flight_seconds) or body.flight_seconds-float(stamp)<.7: return false
    return true

func _finish() -> void:
    if done: return
    done=true
    snapshots.final_status=adapter.status()
    var final_context: Dictionary=adapter.context()
    if final_context.has("carrier") and is_instance_valid(final_context.workbench):
        snapshots.beneficiary_capture=Wait.State.capture_wait_checked(final_context.workbench.beneficiary,Wait.Safe.BENEFICIARY_ID)
        snapshots.final_wait={"controller":adapter.module._waiting.report(),"custody":final_context.custody.report(),"workbench":final_context.workbench.report(),"beneficiary_wait":Wait.State.capture_wait(final_context.workbench.beneficiary,Wait.Safe.BENEFICIARY_ID),"beneficiary_command":final_context.workbench.beneficiary.command,"beneficiary_pose":Wait.State.pose(final_context.workbench.beneficiary.global_transform),"beneficiary_contacts":final_context.workbench.beneficiary.contact_cooldowns,"beneficiary_support":Wait.Bench.Departure.support_proof(final_context.workbench.beneficiary,final_context.workbench.rack)}
    if is_instance_valid(session): session.canal=null
    adapter.clear()
    if is_instance_valid(session): session.free()
    var report: Dictionary={"checks":checks.size(),"failures":failures,"engine_errors":logger.errors,"details":checks,"snapshots":snapshots,"scope":"actual MAIN unordered WAIT capture + original Session/Store failure/commit/reopen + fresh physical restore; old27/player-start QA fixture; no network/work completion"}
    if not output.is_empty():
        var file:=FileAccess.open(output.path_join("result.json"),FileAccess.WRITE)
        if file: file.store_string(JSON.stringify(report,"\t",true,true))
    print("CANAL_WAIT ",JSON.stringify({"checks":checks.size(),"failures":failures,"engine_errors":logger.errors}))
    quit(0 if failures.is_empty() and logger.errors.is_empty() else 1)
