extends RefCounted
## Strict un-ordered carried WAIT envelope. Completed-safe v3 is untouched.
const State=preload("res://scripts/v3/candidates/canal_checkpoint/flight_state.gd")
const Safe=preload("res://scripts/v3/candidates/canal_checkpoint/canal_checkpoint.gd")
const Rules=preload("res://scripts/v3/candidates/canal_service_loop/canal_service_runtime.gd")
const Executor=preload("res://scripts/v3/candidates/canal_transport_executor/canal_transport_executor.gd")
const Custody=preload("res://scripts/v3/candidates/canal_transport_physics/cargo_custody.gd")
const Cooling=preload("res://scripts/v3/candidates/canal_cooling_station/cooling_station.gd")
const Bench=preload("res://scripts/v3/candidates/canal_workbench/workbench.gd")
const Pilot=Executor.Pilot
const KIND="canal_wait_checkpoint_v1"
const VERSION=1
const BODY_KEYS=["pose","velocity","angular_velocity","freeze_mode","sleeping","process","physics_process","layer","mask","mass","can_sleep","continuous_cd","linear_damp","angular_damp","linear_damp_mode","angular_damp_mode","gravity_scale","friction","bounce","rough","absorbent","shape_size"]

static func capture(context: Dictionary, pilot: RefCounted, bench: Node3D, cooling: Node3D, device_serial: int, rule_seconds: float, rule_usec: int) -> Dictionary:
    if context.is_empty() or pilot==null or not is_instance_valid(bench) or not is_instance_valid(cooling): return bad("wait_modules_required")
    var frame: int=Engine.get_physics_frames()
    if context.custody._last_physics_frame!=frame or bench._last_frame!=frame: return bad("current_wait_frame_required")
    var state: Dictionary=context.rules.snapshot()
    var controller: Dictionary=pilot.snapshot_wait(Executor.WAIT_POINT)
    var custody: Dictionary=context.custody.snapshot_wait(Rules.CASSETTES[0],Rules.CARRIER,Rules.CASSETTES[1],Rules.WORK)
    var workbench: Dictionary=bench.snapshot_wait()
    var device: Dictionary=cooling.capture_state(frame)
    if controller.is_empty(): return bad("actual_wait_controller_required")
    if custody.is_empty(): return bad("actual_wait_custody_required")
    if workbench.is_empty(): return bad("actual_wait_workbench_required")
    if not device.ok: return bad("actual_wait_device:"+str(device.code))
    if not context.cargos[Rules.CASSETTES[1]].get_collision_exceptions().is_empty() or not bench.beneficiary.get_collision_exceptions().is_empty(): return bad("wait_unregistered_collision_exception")
    var bodies: Dictionary={Rules.CARRIER:rigid_snapshot(context.carrier),Safe.BENEFICIARY_ID:rigid_snapshot(bench.beneficiary)}
    for id: String in Rules.CASSETTES: bodies[id]=rigid_snapshot(context.cargos[id])
    var saved: Dictionary={"version":VERSION,"kind":KIND,"layout_sha256":Safe.layout_fingerprint(),"physics_hz":Engine.physics_ticks_per_second,
        "rules":state,"custody":custody,"carrier":State.capture_wait(context.carrier,Rules.CARRIER),"bodies":bodies,
        "waiting":controller,"workbench":workbench,"cooling":device.state,"device_serial":device_serial,"rule_seconds":rule_seconds,"rule_usec":rule_usec}
    var valid: Dictionary=validate(saved)
    if not valid.ok: return valid
    if not pilot.probe(Vector3.ZERO).clear: return bad("wait_loaded_clearance")
    return {"ok":true,"code":"captured_actual_unordered_wait","envelope":saved.duplicate(true)}

static func validate(saved: Variant) -> Dictionary:
    if not State.exact(saved,["version","kind","layout_sha256","physics_hz","rules","custody","carrier","bodies","waiting","workbench","cooling","device_serial","rule_seconds","rule_usec"]): return bad("wait_envelope_keys")
    if not saved.rules is Dictionary: return bad("wait_rule_ledger_type")
    if not Safe._json_safe(saved): return bad("wait_envelope_keys")
    if saved.version!=VERSION or saved.kind!=KIND or saved.layout_sha256!=Safe.layout_fingerprint() or not State.integer(saved.physics_hz,60,60): return bad("wait_version_layout_physics")
    var rules=Rules.new()
    if not rules.configure().ok or not rules.restore(saved.rules).ok: return bad("wait_rule_ledger")
    var state: Dictionary=rules.snapshot()
    if state.carrier_anchor!=Rules.WAIT or not state.pending_action.is_empty() or int(state.action_serial)!=0 or int(state.jobs_completed)!=0 or int(state.service_credit)!=0 or int(state.services_consumed)!=0 or int(state.service_serial)!=0 or state.cassettes[Rules.CASSETTES[0]].holder!=Rules.CARRIER or state.cassettes[Rules.CASSETTES[1]].holder!=Rules.WORK or state.buffer_enabled: return bad("un_ordered_original_wait_required")
    for row: Dictionary in state.pilots.values():
        if row.peer_id!=0 or row.enabled: return bad("wait_external_holder_not_supported")
    if not State.number(saved.rule_seconds,0,1.0e9) or not State.integer(saved.rule_usec,0,9007199254740991) or roundi(float(saved.rule_seconds)*1000000)!=int(saved.rule_usec) or int(rules.status().elapsed_usec)!=int(saved.rule_usec): return bad("wait_clock_mismatch")
    if not Custody.validate_wait_snapshot(saved.custody,Rules.CASSETTES[0],Rules.CARRIER,Rules.CASSETTES[1],Rules.WORK).ok: return bad("wait_custody")
    if not State.validate_wait(saved.carrier,Rules.CARRIER) or not Bench.validate_wait(saved.workbench).ok or not Pilot.validate_wait(saved.waiting,Executor.WAIT_POINT): return bad("wait_flight_controller_bench")
    if State.transform(saved.carrier.pose).origin.distance_to(Executor.WAIT_POINT)>=.18 or State.vec(saved.carrier.velocity).length()>=.18: return bad("wait_carrier_not_stationary")
    if not Cooling.validate_snapshot(saved.cooling).ok or saved.cooling.paused: return bad("wait_device")
    var minimum: int=maxi(int(saved.cooling.charge_serial),int(saved.workbench.charge_serial))
    minimum=maxi(minimum,int(saved.cooling.axis.last_serial["1"]))
    if not State.integer(saved.device_serial,minimum,2147483647): return bad("wait_device_serial")
    var ids: Array=[Rules.CARRIER,Safe.BENEFICIARY_ID]+Rules.CASSETTES
    if not State.exact(saved.bodies,ids): return bad("wait_body_registry")
    for id: String in ids:
        if not validate_rigid(saved.bodies[id],id): return bad("wait_body:"+id)
    for pair: Array in [[Rules.CARRIER,saved.carrier],[Safe.BENEFICIARY_ID,saved.workbench.beneficiary]]:
        for key: String in ["pose","velocity","angular_velocity"]:
            if saved.bodies[pair[0]][key]!=pair[1][key]: return bad("wait_flight_body_mismatch")
    var cold: Dictionary=saved.bodies[Rules.CASSETTES[0]]
    var hot: Dictionary=saved.bodies[Rules.CASSETTES[1]]
    var joint: Dictionary=saved.custody.joint
    if (State.transform(saved.carrier.pose)*State.vec(joint.local_a)).distance_to(State.transform(cold.pose)*State.vec(joint.local_b))>.08: return bad("wait_joint_separation")
    if State.transform(cold.pose).origin.distance_to(State.transform(saved.carrier.pose).origin)>1.5 or State.vec(cold.velocity).length()>.3: return bad("wait_load_swing_or_speed")
    var hot_bounds: AABB=State.transform(hot.pose)*AABB(Vector3(-.2,-.2,-.2),Vector3(.4,.4,.4))
    var berth_bounds:=AABB(Executor.BERTH_POINTS[Rules.WORK]-Vector3(1,.25,1),Vector3(2,.5,2))
    if absf(hot_bounds.position.y-berth_bounds.end.y)>.025 or hot_bounds.position.x<berth_bounds.position.x+.03 or hot_bounds.end.x>berth_bounds.end.x-.03 or hot_bounds.position.z<berth_bounds.position.z+.03 or hot_bounds.end.z>berth_bounds.end.z-.03: return bad("wait_work_support_pose")
    return {"ok":true,"code":"valid_wait_no_contact_claim"}

static func rigid_snapshot(body: RigidBody3D, allow_initial_frozen: bool = false) -> Dictionary:
    if not is_instance_valid(body) or not body.is_inside_tree() or (body.freeze and not allow_initial_frozen) or body.custom_integrator or body.lock_rotation or body.center_of_mass_mode!=RigidBody3D.CENTER_OF_MASS_MODE_AUTO or not body.inertia.is_zero_approx() or not body.constant_force.is_zero_approx() or not body.constant_torque.is_zero_approx(): return {}
    for axis: int in [PhysicsServer3D.BODY_AXIS_LINEAR_X,PhysicsServer3D.BODY_AXIS_LINEAR_Y,PhysicsServer3D.BODY_AXIS_LINEAR_Z,PhysicsServer3D.BODY_AXIS_ANGULAR_X,PhysicsServer3D.BODY_AXIS_ANGULAR_Y,PhysicsServer3D.BODY_AXIS_ANGULAR_Z]:
        if body.get_axis_lock(axis): return {}
    var shape_size:=Vector3.ZERO
    var count:=0
    for owner: int in body.get_shape_owners():
        if body.is_shape_owner_disabled(owner) or body.shape_owner_get_transform(owner)!=Transform3D.IDENTITY: return {}
        for i: int in body.shape_owner_get_shape_count(owner):
            var shape: Shape3D=body.shape_owner_get_shape(owner,i)
            if not shape is BoxShape3D: return {}
            shape_size=shape.size
            count+=1
    if count!=1 or body.physics_material_override==null: return {}
    var material: PhysicsMaterial=body.physics_material_override
    return {"pose":State.pose(body.global_transform),"velocity":State.xyz(body.linear_velocity),"angular_velocity":State.xyz(body.angular_velocity),
        "freeze_mode":body.freeze_mode,"sleeping":body.sleeping,"process":body.is_processing(),"physics_process":body.is_physics_processing(),"layer":body.collision_layer,"mask":body.collision_mask,"mass":body.mass,"can_sleep":body.can_sleep,"continuous_cd":body.continuous_cd,
        "linear_damp":body.linear_damp,"angular_damp":body.angular_damp,"linear_damp_mode":body.linear_damp_mode,"angular_damp_mode":body.angular_damp_mode,"gravity_scale":body.gravity_scale,
        "friction":material.friction,"bounce":material.bounce,"rough":material.rough,"absorbent":material.absorbent,"shape_size":State.xyz(shape_size)}

static func validate_rigid(row: Variant, id: String) -> bool:
    if not State.exact(row,BODY_KEYS) or not State.pose_valid(row.pose) or not State.vector_valid(row.velocity,.5) or not State.vector_valid(row.angular_velocity,.5): return false
    for key: String in ["sleeping","process","physics_process","can_sleep","continuous_cd","rough","absorbent"]:
        if not row[key] is bool: return false
    for key: String in ["freeze_mode","linear_damp_mode","angular_damp_mode"]:
        if not State.integer(row[key],0,1): return false
    for key: String in ["linear_damp","angular_damp","gravity_scale"]:
        if not State.number(row[key],0,10): return false
    if not State.number(row.friction,0,1) or not State.number(row.bounce,0,1): return false
    var cargo: bool=id in Rules.CASSETTES
    # RigidBody3D.mass stores real_t (float32 here), while Catalog arithmetic
    # is double. Compare its exact native representation, not a looser range.
    var expected_mass: float=float(PackedFloat32Array([2.0 if cargo else float(State.Catalog.resolve_build(State.Catalog.default_build("tr01")).derived.mass_kg)])[0])
    if not State.number(row.mass,expected_mass,expected_mass) or row.layer!=(8 if cargo else 2) or row.mask!=(Custody.MASK if cargo else (47 if id==Safe.BENEFICIARY_ID else 45)): return false
    return State.vector_valid(row.shape_size,2) and State.vec(row.shape_size)==(Vector3(.4,.4,.4) if cargo else Vector3(1.4,.48,1.4))

## Fresh initialized bodies only. Caller validates envelope before this call,
## owns the entire unadopted subtree, and keeps all bodies frozen until ready.
static func apply_rigid_fresh(body: RigidBody3D, row: Dictionary) -> void:
    body.freeze=true
    body.set_process(false)
    body.set_physics_process(false)
    body.global_transform=State.transform(row.pose)
    body.linear_velocity=State.vec(row.velocity)
    body.angular_velocity=State.vec(row.angular_velocity)
    body.freeze_mode=int(row.freeze_mode)
    body.collision_layer=int(row.layer)
    body.collision_mask=int(row.mask)
    for key: String in ["mass","linear_damp","angular_damp","gravity_scale"]: body.set(key,float(row[key]))
    body.linear_damp_mode=int(row.linear_damp_mode)
    body.angular_damp_mode=int(row.angular_damp_mode)
    body.can_sleep=row.can_sleep
    body.continuous_cd=row.continuous_cd
    var material:=PhysicsMaterial.new()
    for key: String in ["friction","bounce","rough","absorbent"]: material.set(key,row[key])
    body.physics_material_override=material
    body.sleeping=row.sleeping
    body.force_update_transform()
    PhysicsServer3D.body_set_state(body.get_rid(),PhysicsServer3D.BODY_STATE_TRANSFORM,body.global_transform)

static func unfreeze_original(body: RigidBody3D, row: Dictionary) -> void:
    body.freeze=false
    body.linear_velocity=State.vec(row.velocity)
    body.angular_velocity=State.vec(row.angular_velocity)
    body.sleeping=row.sleeping
    body.set_process(row.process)
    body.set_physics_process(row.physics_process)

static func bad(code: String) -> Dictionary:
    return {"ok":false,"code":code}
