extends RefCounted
## In-progress stationary first-work scan, independent of WAIT/completed-safe.
const Wait=preload("res://scripts/v3/candidates/canal_checkpoint/canal_wait_checkpoint.gd")
const State=Wait.State
const Safe=Wait.Safe
const Rules=Wait.Rules
const Executor=Wait.Executor
const Custody=Wait.Custody
const Bench=Wait.Bench
const Cooling=Wait.Cooling
const KIND="canal_scan_checkpoint_v1"
const VERSION=1

static func capture(context: Dictionary, executor: RefCounted, bench: Node3D, cooling: Node3D, device_serial: int, rule_seconds: float, rule_usec: int) -> Dictionary:
    if context.is_empty() or executor==null or not is_instance_valid(bench) or not is_instance_valid(cooling): return Wait.bad("scan_modules_required")
    var frame: int=Engine.get_physics_frames()
    if context.custody._last_physics_frame!=frame or bench._last_frame!=frame: return Wait.bad("current_scan_frame_required")
    var state: Dictionary=context.rules.snapshot()
    var carried: bool=state.cassettes[Rules.CASSETTES[0]].holder==Rules.CARRIER
    var custody: Dictionary=context.custody.snapshot_wait(Rules.CASSETTES[0],Rules.CARRIER,Rules.CASSETTES[1],Rules.WORK) if carried else context.custody.docked_snapshot()
    var workbench: Dictionary=bench.snapshot_scan()
    var controller: Dictionary=executor.snapshot_scan()
    var device: Dictionary=cooling.capture_state(frame)
    if custody.is_empty():
        var denied: Dictionary=Wait.bad("actual_scan_custody_required")
        denied["detail"]=context.custody.inspect_wait_snapshot(Rules.CASSETTES[0],Rules.CARRIER,Rules.CASSETTES[1],Rules.WORK) if carried else context.custody.report()
        return denied
    if workbench.is_empty():
        var denied: Dictionary=Wait.bad("actual_scan_tool_evidence_required")
        denied["detail"]=bench.inspect_scan_snapshot()
        return denied
    if controller.is_empty(): return Wait.bad("actual_scan_executor_hold_required")
    if not device.ok: return Wait.bad("actual_scan_device:"+str(device.code))
    for body: RigidBody3D in [context.carrier,context.cargos[Rules.CASSETTES[0]],context.cargos[Rules.CASSETTES[1]],bench.beneficiary]:
        if not carried and not body.get_collision_exceptions().is_empty(): return Wait.bad("scan_unregistered_collision_exception")
    if not context.cargos[Rules.CASSETTES[1]].get_collision_exceptions().is_empty() or not bench.beneficiary.get_collision_exceptions().is_empty(): return Wait.bad("scan_unregistered_collision_exception")
    var bodies: Dictionary={Rules.CARRIER:Wait.rigid_snapshot(context.carrier),Safe.BENEFICIARY_ID:Wait.rigid_snapshot(bench.beneficiary)}
    for id: String in Rules.CASSETTES: bodies[id]=Wait.rigid_snapshot(context.cargos[id])
    var saved: Dictionary={"version":VERSION,"kind":KIND,"layout_sha256":Safe.layout_fingerprint(),"physics_hz":Engine.physics_ticks_per_second,"rules":state,"custody":custody,"carrier":State.capture_wait(context.carrier,Rules.CARRIER),"bodies":bodies,"executor":controller,"workbench":workbench,"cooling":device.state,"device_serial":device_serial,"rule_seconds":rule_seconds,"rule_usec":rule_usec}
    var checked: Dictionary=validate(saved)
    if not checked.ok: return checked
    if not executor._pilot.probe(Vector3.ZERO).clear: return Wait.bad("scan_carrier_clearance")
    return {"ok":true,"code":"captured_actual_partial_scan","envelope":saved.duplicate(true)}

static func validate(saved: Variant) -> Dictionary:
    if not State.exact(saved,["version","kind","layout_sha256","physics_hz","rules","custody","carrier","bodies","executor","workbench","cooling","device_serial","rule_seconds","rule_usec"]): return Wait.bad("scan_envelope_keys")
    if not saved.rules is Dictionary: return Wait.bad("scan_rule_ledger_type")
    if not Safe._json_safe(saved) or saved.version!=VERSION or saved.kind!=KIND or saved.layout_sha256!=Safe.layout_fingerprint() or not State.integer(saved.physics_hz,60,60): return Wait.bad("scan_version_layout_types")
    var rules=Rules.new()
    if not rules.configure().ok or not rules.restore(saved.rules).ok: return Wait.bad("scan_rule_ledger")
    var state: Dictionary=rules.snapshot()
    if state.pending_action.get("kind")!="work" or not state.job_requested or int(state.jobs_completed)!=0 or int(state.service_credit)!=0 or int(state.services_consumed)!=0 or int(state.service_serial)!=0 or state.buffer_enabled: return Wait.bad("original_first_work_pending_required")
    for row: Dictionary in state.pilots.values():
        if row.peer_id!=0 or row.enabled: return Wait.bad("scan_external_holder_not_supported")
    var carried: bool=state.cassettes[Rules.CASSETTES[0]].holder==Rules.CARRIER
    if carried:
        if state.carrier_anchor!=Rules.WAIT or state.cassettes[Rules.CASSETTES[1]].holder!=Rules.WORK or state.pending_action.cassette_id!=Rules.CASSETTES[1] or not Custody.validate_wait_snapshot(saved.custody,Rules.CASSETTES[0],Rules.CARRIER,Rules.CASSETTES[1],Rules.WORK).ok: return Wait.bad("scan_in_place_occupancy")
    else:
        if state.cassettes[Rules.CASSETTES[0]].holder!=Rules.WORK or state.cassettes[Rules.CASSETTES[1]].holder not in [Rules.SOUTH_0,Rules.SOUTH_1] or state.pending_action.cassette_id!=Rules.CASSETTES[0] or state.carrier_anchor!=Rules.WORK or not Custody.validate_docked_snapshot(saved.custody).ok or not State.exact(saved.custody.cargos,Rules.CASSETTES): return Wait.bad("scan_exchanged_occupancy")
        for id: String in Rules.CASSETTES:
            if saved.custody.cargos[id].berth!=state.cassettes[id].holder: return Wait.bad("scan_docked_holder_mismatch")
    if not State.number(saved.rule_seconds,0,1.0e9) or not State.integer(saved.rule_usec,0,9007199254740991) or roundi(float(saved.rule_seconds)*1000000)!=int(saved.rule_usec) or int(rules.status().elapsed_usec)!=int(saved.rule_usec): return Wait.bad("scan_clock_mismatch")
    if not Bench.validate_scan(saved.workbench).ok or not Rules._same(saved.workbench.action,state.pending_action): return Wait.bad("scan_workbench")
    if not Executor.validate_scan(saved.executor,state).ok or not State.validate_wait(saved.carrier,Rules.CARRIER): return Wait.bad("scan_carrier_controller")
    var goal: Vector3=Executor.WAIT_POINT if state.carrier_anchor==Rules.WAIT else Executor.BERTH_POINTS[str(state.carrier_anchor)]+Vector3.UP*2.2
    if State.transform(saved.carrier.pose).origin.distance_to(goal)>=.18 or State.vec(saved.carrier.velocity).length()>=.18 or saved.carrier.health<saved.executor.initial_health or saved.carrier.wait.collision_count!=saved.executor.initial_collisions or saved.executor.serial<saved.custody.last_serial: return Wait.bad("scan_carrier_anchor_baseline")
    if not Cooling.validate_snapshot(saved.cooling).ok or saved.cooling.paused: return Wait.bad("scan_cooling")
    var minimum: int=maxi(int(saved.cooling.charge_serial),int(saved.workbench.charge_serial))
    minimum=maxi(minimum,int(saved.cooling.axis.last_serial["1"]))
    if not State.integer(saved.device_serial,minimum,2147483647): return Wait.bad("scan_device_serial")
    var ids: Array=[Rules.CARRIER,Safe.BENEFICIARY_ID]+Rules.CASSETTES
    if not State.exact(saved.bodies,ids): return Wait.bad("scan_body_registry")
    for id: String in ids:
        if not Wait.validate_rigid(saved.bodies[id],id): return Wait.bad("scan_body:"+id)
    for pair: Array in [[Rules.CARRIER,saved.carrier],[Safe.BENEFICIARY_ID,saved.workbench.beneficiary]]:
        for key: String in ["pose","velocity","angular_velocity"]:
            if saved.bodies[pair[0]][key]!=pair[1][key]: return Wait.bad("scan_flight_body_mismatch")
    for id: String in Rules.CASSETTES:
        var row: Dictionary=saved.bodies[id]
        var holder: String=str(state.cassettes[id].holder)
        if holder==Rules.CARRIER:
            var joint: Dictionary=saved.custody.joint
            if (State.transform(saved.carrier.pose)*State.vec(joint.local_a)).distance_to(State.transform(row.pose)*State.vec(joint.local_b))>.08 or State.transform(row.pose).origin.distance_to(State.transform(saved.carrier.pose).origin)>1.5 or State.vec(row.velocity).length()>.3: return Wait.bad("scan_joint_separation_or_swing")
        else:
            var pose: Transform3D=State.transform(row.pose)
            var bounds: AABB=pose*AABB(Vector3(-.2,-.2,-.2),Vector3(.4,.4,.4))
            var berth:=AABB(Executor.BERTH_POINTS[holder]-Vector3(1,.25,1),Vector3(2,.5,2))
            if pose.basis.y.dot(Vector3.UP)<.985 or State.vec(row.velocity).length()>.12 or State.vec(row.angular_velocity).length()>.15 or absf(bounds.position.y-berth.end.y)>.025 or bounds.position.x<berth.position.x+.03 or bounds.end.x>berth.end.x-.03 or bounds.position.z<berth.position.z+.03 or bounds.end.z>berth.end.z-.03: return Wait.bad("scan_docked_support_pose:"+id)
    for berth: String in [Rules.SOUTH_0,Rules.SOUTH_1]:
        var expected: String=""
        for id: String in Rules.CASSETTES:
            if state.cassettes[id].holder==berth: expected=id
        if saved.cooling.contact_observation[berth]!=expected: return Wait.bad("scan_cooling_contact_history")
    return {"ok":true,"code":"valid_scan_no_current_contact_claim"}
