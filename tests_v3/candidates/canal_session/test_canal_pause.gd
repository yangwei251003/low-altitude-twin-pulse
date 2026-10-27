extends "res://tests_v3/candidates/canal_session/test_canal_session.gd"
## Only reuses MAIN/profile/old27 setup and evidence helpers. Does not run the
## original ability suite or any work order. All motion after bootstrap is real.
func _run() -> void:
    create_timer(55).timeout.connect(func():
        if not done:
            _check(false, "55 second pause probe bound", adapter.status())
            _finish())
    if not _check(profile.begins_with("qa_canal_session_") and not DirAccess.dir_exists_absolute("user://profiles_v3/"+profile), "fresh isolated MAIN profile"): _finish(); return
    session = MAIN.instantiate()
    root.add_child(session)
    session.set_process(false)
    session.set_physics_process(false)
    session.inputs.set_process(false)
    session.inputs.set_physics_process(false)
    if not _check(session.profile_ready and session.start_flight("solo"), "actual MAIN starts solo"): _finish(); return
    if not _seed_old27(): _finish(); return
    if not _check(session._load_region("I2"), "actual I2/four facilities, not a substitute world"): _finish(); return
    session.owns_world = false # Candidate has no complete persistence hook.
    session.inputs.test_enabled = true
    session.inputs.test_frame = {"axes":{}, "held":["brake"]}
    var player: FlightBodyV2 = session.players[1]
    player.freeze = true
    player.global_transform = Transform3D(Basis.IDENTITY, Vector3(8,3.2,27))
    player.linear_velocity = Vector3.ZERO
    player.angular_velocity = Vector3.ZERO
    player.hold_height = player.global_position.y
    player.force_update_transform()
    PhysicsServer3D.body_set_state(player.get_rid(), PhysicsServer3D.BODY_STATE_TRANSFORM, player.global_transform)
    await physics_frame
    adapter.setup(session)
    var prepared: Dictionary = adapter.prepare(session.world_cache.world, "I2", true)
    if not _check(prepared.ok and adapter.adopt(prepared).ok, "install one original Assembly"): _finish(); return
    var early: Dictionary = _bodies()
    var carrier: RigidBody3D = adapter.context().carrier
    _check(carrier.freeze, "original Bootstrap intentionally freezes carrier before seating")
    var early_pause: Dictionary = adapter.set_paused(true)
    var early_resume: Dictionary = adapter.set_paused(false)
    if not _check(early_pause.ok and early_resume.ok and _restored(early), "fresh pause/resume preserves original freeze/sleep/momentum/process flags", {"pause":early_pause,"resume":early_resume,"before":early,"after":_bodies()}): _finish(); return
    for unused in 2700:
        if not await _frame(): _finish(); return
        if adapter.ready: break
    if not _check(adapter.ready, "original real PinJoint load reaches WAIT", adapter.module.status(true)): _finish(); return
    var ctx: Dictionary = adapter.context()
    var before: Dictionary = _bodies()
    var joints: Dictionary = _joints()
    var rules_before: Dictionary = ctx.rules.snapshot().duplicate(true)
    var rule_usec_before: int = int(adapter.module.status().rule_usec)
    var foreign: Dictionary = _facilities()
    var ability_count: int = int(session.stats.abilities)
    _check(before.size() == 4 and joints.size() == 1 and ctx.carrier.cargo_items.size() == 1, "actual carrier/two cassettes/unregistered beneficiary and one load joint", {"bodies":before,"joints":joints})
    _check(adapter.owns_body(ctx.workbench.beneficiary) and not session.world.objects.values().has(ctx.workbench.beneficiary) and not adapter.owns_body(player), "ownership covers unregistered beneficiary, excludes real player")
    var flight_clock: Dictionary = {"carrier":ctx.carrier.flight_seconds,"beneficiary":ctx.workbench.beneficiary.flight_seconds}
    var pause_result: Dictionary = adapter.set_paused(true)
    if not _check(pause_result.ok, "capture and freeze entire owned set before host generic pause", pause_result): _finish(); return
    session.simulation_paused = true
    # Proposed host call order: generic loop skips adapter.owns_body. Existing
    # Session source is unchanged; only the caller-owned player is frozen here.
    snapshots.before_pause = before
    snapshots.joints = joints
    var maximum_drift := 0.0
    for index in 66:
        if not await _frame(): _finish(); return
        if index in [0,20,40,65]:
            if not _check(adapter.set_paused(true).ok, "repeated pause keeps first capture at frame " + str(index)): _finish(); return
        for id: int in before:
            var body: RigidBody3D = instance_from_id(id)
            maximum_drift = maxf(maximum_drift, body.global_position.distance_to(before[id].pose.origin))
    _check(maximum_drift <= .000001 and _all_frozen(before) and _joints() == joints, "1.1s actual physics pause has no drift or joint replacement", {"maximum_drift_m":maximum_drift,"current":_bodies()})
    _check(ctx.rules.snapshot() == rules_before and ctx.carrier.flight_seconds == flight_clock.carrier and ctx.workbench.beneficiary.flight_seconds == flight_clock.beneficiary, "water/rule and both actual Flight integration clocks do not advance")
    var paused_rule: Dictionary = ctx.rules.snapshot().duplicate(true)
    var rejected: Dictionary = adapter.use_ability(1,{"ability":"charge","target_id":Adapter.Assembly.RELAY_ID})
    _check(not rejected.ok and session.stats.abilities == ability_count and ctx.rules.snapshot() == paused_rule, "paused site accepts no ability or work")
    session.simulation_paused = false
    var resumed: Dictionary = adapter.set_paused(false)
    _check(resumed.ok and _restored(before) and adapter.status().pause_restores == 2, "resume restores original four modes/sleep/linear/angular values exactly once", {"result":resumed,"current":_bodies()})
    var just_resumed: Dictionary = _bodies()
    _check(adapter.set_paused(false).ok and _bodies() == just_resumed and adapter.status().pause_restores == 2, "duplicate resume never reapplies old momentum")
    for unused in 66:
        if not await _frame(): _finish(); return
    var after: Dictionary = _bodies()
    _check(after.keys() == before.keys() and _joints().keys() == joints.keys() and ctx.carrier.cargo_items.size() == 1, "1.1s resumed host keeps all body/RID/joint identities", after)
    _check(int(adapter.module.status().rule_usec) > rule_usec_before, "normal host rule time resumes")
    _check(ctx.carrier.flight_seconds > float(flight_clock.carrier) and ctx.workbench.beneficiary.flight_seconds > float(flight_clock.beneficiary), "both original Flight bodies physically resume")
    _check(ctx.carrier.collision_count == 0 and ctx.workbench.beneficiary.collision_count == 0 and ctx.rules.snapshot().jobs_completed == 0 and ctx.rules.snapshot().service_credit == 0 and session.stats.abilities == ability_count, "resume adds no collision, work, service or ability")
    _check(_facilities() == foreign, "foreign facilities untouched by own pause/resume")
    # Wrong existing generic-call order is explicitly detected, not treated as
    # proof these bodies used to be frozen. Restore that external QA operation
    # through the same public Session method, without touching their poses.
    session.simulation_paused = true
    session._apply_pause_state()
    var wrong_order: Dictionary = adapter.set_paused(true)
    _check(not wrong_order.ok and str(wrong_order.code).begins_with("external_body_mode_changed_before_pause:") and not adapter.status().physics_paused, "generic Session freeze before capture is rejected", wrong_order)
    session.simulation_paused = false
    session._apply_pause_state()
    if not await _frame(): _finish(); return
    _check(adapter.set_paused(true).ok, "valid pause after explicit host-mode correction")
    # Negative QA intrusion only, after all positive physics. Never corrected by
    # adapter; the corrupted candidate is destroyed at teardown, not resumed.
    var affected: RigidBody3D = ctx.cargos[Adapter.Assembly.Runtime.CASSETTES[0]]
    affected.global_position += Vector3(.001,0,0)
    var tampered: Transform3D = affected.global_transform
    var caught: Dictionary = adapter.advance(DT)
    var refused: Dictionary = adapter.set_paused(false)
    _check(not caught.ok and str(caught.code).begins_with("paused_body_pose_changed:") and not refused.ok and affected.global_transform == tampered and affected.freeze, "1mm external pose corruption is reported, never teleported back or silently resumed", {"detected":caught,"resume":refused})
    snapshots.pause_final = adapter.status()
    adapter.clear()
    _check(_facilities() == foreign and is_instance_valid(player) and is_instance_valid(session.world), "clearing faulty owned pause leaves real player/world/four facilities")
    _finish()

func _bodies() -> Dictionary:
    var result: Dictionary = {}
    for node: Node in adapter.module.find_children("*","RigidBody3D",true,false):
        var body := node as RigidBody3D
        result[body.get_instance_id()] = {"name":str(body.name),"rid":str(body.get_rid()),"pose":body.global_transform,"freeze":body.freeze,"sleeping":body.sleeping,"linear":body.linear_velocity,"angular":body.angular_velocity,"process":body.is_processing(),"physics_process":body.is_physics_processing()}
    return result

func _joints() -> Dictionary:
    var result: Dictionary = {}
    for node: Node in adapter.module.find_children("*","Joint3D",true,false):
        var joint := node as Joint3D
        result[joint.get_instance_id()] = {"rid":str(joint.get_rid()),"a":str(joint.node_a),"b":str(joint.node_b)}
    return result

func _restored(saved: Dictionary) -> bool:
    var current: Dictionary = _bodies()
    if current.keys() != saved.keys(): return false
    for id: int in saved:
        for key: String in ["rid","freeze","sleeping","linear","angular","process","physics_process"]:
            if current[id][key] != saved[id][key]: return false
    return true

func _all_frozen(saved: Dictionary) -> bool:
    for id: int in saved:
        var body: RigidBody3D = instance_from_id(id)
        if not body.freeze or body.is_processing() or body.is_physics_processing(): return false
        if body.linear_velocity != Vector3.ZERO or body.angular_velocity != Vector3.ZERO: return false
    return true
