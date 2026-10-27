extends RefCounted
## No transforms or callbacks are written. Only accept an actually synchronized
## Node/Server boundary, save native momentum, freeze mode and restore it once.

static func sample(body: RigidBody3D) -> Dictionary:
    if not is_instance_valid(body) or not body.is_inside_tree() or not body.global_transform.is_finite(): return {"ok":false,"code":"live_body_required"}
    var rid: RID=body.get_rid()
    var pose: Transform3D=PhysicsServer3D.body_get_state(rid,PhysicsServer3D.BODY_STATE_TRANSFORM)
    var linear: Vector3=PhysicsServer3D.body_get_state(rid,PhysicsServer3D.BODY_STATE_LINEAR_VELOCITY)
    var angular: Vector3=PhysicsServer3D.body_get_state(rid,PhysicsServer3D.BODY_STATE_ANGULAR_VELOCITY)
    if not pose.is_finite() or not linear.is_finite() or not angular.is_finite(): return {"ok":false,"code":"native_state_invalid"}
    var row: Dictionary={"ok":true,"code":"current_node_server_boundary","body":weakref(body),"rid":rid,"space":body.get_world_3d().space,"pose":pose,"node_pose":body.global_transform,"freeze":body.freeze,"freeze_mode":body.freeze_mode,"sleeping":PhysicsServer3D.body_get_state(rid,PhysicsServer3D.BODY_STATE_SLEEPING),"linear":linear,"angular":angular,"process":body.is_processing(),"physics_process":body.is_physics_processing()}
    if pose!=body.global_transform or linear!=body.linear_velocity or angular!=body.angular_velocity:
        row.ok=false
        row.code="physics_sync_boundary_required"
        row["pending"]=true
    return row

static func freeze(row: Dictionary) -> Dictionary:
    var body: RigidBody3D=row.body.get_ref()
    if not row.ok or not is_instance_valid(body) or body.get_rid()!=row.rid: return {"ok":false,"code":"sampled_body_required"}
    var current: Dictionary=sample(body)
    if not current.ok or current.pose!=row.pose or current.linear!=row.linear or current.angular!=row.angular: return {"ok":false,"code":"boundary_changed_before_freeze"}
    body.freeze=true
    body.linear_velocity=Vector3.ZERO
    body.angular_velocity=Vector3.ZERO
    body.sleeping=true
    body.set_process(false)
    body.set_physics_process(false)
    return frozen(row)

static func frozen(row: Dictionary) -> Dictionary:
    var body: Variant=row.body.get_ref()
    if not body is RigidBody3D or not is_instance_valid(body) or not body.is_inside_tree() or body.get_rid()!=row.rid or body.get_world_3d().space!=row.space: return {"ok":false,"code":"paused_body_identity_changed"}
    if not body.freeze or body.freeze_mode!=row.freeze_mode or body.is_processing() or body.is_physics_processing(): return {"ok":false,"code":"paused_body_mode_changed"}
    var native: Transform3D=PhysicsServer3D.body_get_state(row.rid,PhysicsServer3D.BODY_STATE_TRANSFORM)
    if native!=row.pose or body.global_transform!=row.node_pose: return {"ok":false,"code":"paused_real_pose_changed","native":native,"node":body.global_transform,"expected":row.pose}
    if PhysicsServer3D.body_get_state(row.rid,PhysicsServer3D.BODY_STATE_LINEAR_VELOCITY)!=Vector3.ZERO or PhysicsServer3D.body_get_state(row.rid,PhysicsServer3D.BODY_STATE_ANGULAR_VELOCITY)!=Vector3.ZERO or body.linear_velocity!=Vector3.ZERO or body.angular_velocity!=Vector3.ZERO: return {"ok":false,"code":"paused_native_velocity_changed"}
    return {"ok":true,"code":"same_rid_native_pose_frozen_without_transform_write"}

static func resume(row: Dictionary) -> Dictionary:
    var checked: Dictionary=frozen(row)
    if not checked.ok: return checked
    var body: RigidBody3D=row.body.get_ref()
    body.freeze=bool(row.freeze)
    body.linear_velocity=row.linear
    body.angular_velocity=row.angular
    body.sleeping=bool(row.sleeping)
    body.set_process(bool(row.process))
    body.set_physics_process(bool(row.physics_process))
    if body.get_rid()!=row.rid or PhysicsServer3D.body_get_state(row.rid,PhysicsServer3D.BODY_STATE_TRANSFORM)!=row.pose or PhysicsServer3D.body_get_state(row.rid,PhysicsServer3D.BODY_STATE_LINEAR_VELOCITY)!=row.linear or PhysicsServer3D.body_get_state(row.rid,PhysicsServer3D.BODY_STATE_ANGULAR_VELOCITY)!=row.angular: return {"ok":false,"code":"original_native_momentum_resume_changed"}
    return {"ok":true,"code":"same_rid_pose_and_original_native_momentum_resumed"}

## Exceptional POST-COMMIT failure only. The live logical state cannot be
## serialized or resumed safely, so retain the actual current Server pose and
## stop real dynamics immediately. A stale Node cache is never written back.
## No old momentum is restored; only reloading the committed Store can recover.
static func hold_native_for_reload(body: RigidBody3D) -> Dictionary:
    if not is_instance_valid(body) or not body.is_inside_tree(): return {"ok":false,"code":"fatal_hold_live_body_required"}
    var rid: RID=body.get_rid()
    var pose: Transform3D=PhysicsServer3D.body_get_state(rid,PhysicsServer3D.BODY_STATE_TRANSFORM)
    if not pose.is_finite(): return {"ok":false,"code":"fatal_hold_native_pose_invalid"}
    var linear: Vector3=PhysicsServer3D.body_get_state(rid,PhysicsServer3D.BODY_STATE_LINEAR_VELOCITY)
    var angular: Vector3=PhysicsServer3D.body_get_state(rid,PhysicsServer3D.BODY_STATE_ANGULAR_VELOCITY)
    # Jolt may still dispatch the already queued ORIGINAL Flight callback from
    # the preceding step. Its existing early return is the reload-only stop;
    # normal resumable pause never changes enabled or replaces the callback.
    if body is FlightBodyV2: body.enabled=false
    body.freeze=true
    body.linear_velocity=Vector3.ZERO
    body.angular_velocity=Vector3.ZERO
    body.sleeping=true
    body.set_process(false)
    body.set_physics_process(false)
    if body.get_rid()!=rid or PhysicsServer3D.body_get_state(rid,PhysicsServer3D.BODY_STATE_TRANSFORM)!=pose or PhysicsServer3D.body_get_state(rid,PhysicsServer3D.BODY_STATE_LINEAR_VELOCITY)!=Vector3.ZERO or PhysicsServer3D.body_get_state(rid,PhysicsServer3D.BODY_STATE_ANGULAR_VELOCITY)!=Vector3.ZERO: return {"ok":false,"code":"fatal_hold_changed_native_pose_or_identity"}
    return {"ok":true,"code":"held_actual_native_state_requires_committed_reload","rid":rid,"space":body.get_world_3d().space,"pose":pose,"discarded_linear":linear,"discarded_angular":angular}
