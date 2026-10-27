extends SceneTree
## <3s micro probe. The actual Flight script/state-sync callback is untouched.
const Boundary=preload("res://scripts/v3/candidates/canal_checkpoint/canal_pause_boundary.gd")
const Flight=preload("res://scripts/v2/flight_body.gd")
const Catalog=preload("res://scripts/v2/catalog.gd")
var checks: Array=[]
var failures: Array=[]
var output: String=""
var site: Node3D
var flight: Flight
var cargo: RigidBody3D
var joint: PinJoint3D
var driver: Driver
var idle_mismatch: bool=false

class Driver extends Node:
    const B=preload("res://scripts/v3/candidates/canal_checkpoint/canal_pause_boundary.gd")
    var bodies: Array=[]
    var requested: bool=false
    var captured: Array=[]
    var result: Dictionary={}
    var frame: int=-1
    func _physics_process(_delta: float) -> void:
        if not requested or not captured.is_empty(): return
        var samples: Array=[]
        for body: RigidBody3D in bodies:
            var sample: Dictionary=B.sample(body)
            if not sample.ok: result=sample; return
            samples.append(sample)
        captured=samples
        for sample: Dictionary in captured:
            result=B.freeze(sample)
            if not result.ok: return
        frame=Engine.get_physics_frames()
        result={"ok":true,"code":"frozen_at_normal_physics_process_boundary"}

func _initialize() -> void:
    for arg: String in OS.get_cmdline_user_args():
        if arg.begins_with("--output="): output=arg.trim_prefix("--output=")
    call_deferred("_run")

func _run() -> void:
    site=Node3D.new()
    root.add_child(site)
    flight=Flight.new()
    flight.configure(Catalog.resolve_build(Catalog.default_build("tr01")))
    site.add_child(flight)
    flight.global_position=Vector3(0,5,0) # New-body initialization only.
    flight.hold_height=5
    flight.command={"active":true,"mode":"assisted","body_relative":false,"planar":Vector3(.2,0,0),"vertical":0.0,"yaw":0.0,"brake":false,"fire":false}
    cargo=RigidBody3D.new()
    cargo.mass=2
    var collision:=CollisionShape3D.new()
    var shape:=BoxShape3D.new()
    shape.size=Vector3(.4,.4,.4)
    collision.shape=shape
    cargo.add_child(collision)
    site.add_child(cargo)
    cargo.global_position=Vector3(0,3.9,0) # New-body initialization only.
    joint=PinJoint3D.new()
    site.add_child(joint)
    joint.global_position=cargo.global_position
    joint.node_a=joint.get_path_to(flight)
    joint.node_b=joint.get_path_to(cargo)
    joint.exclude_nodes_from_collision=true
    driver=Driver.new()
    driver.bodies=[flight,cargo]
    site.add_child(driver)
    for unused in 8: await physics_frame
    for unused in 6:
        await physics_frame
        await process_frame
        var sample: Dictionary=Boundary.sample(flight)
        if sample.has("pose") and flight.flight_seconds>.07 and sample.pose!=sample.node_pose:
            idle_mismatch=true
            break
    _check(idle_mismatch,"ordinary idle-frame dynamic Node/Server mismatch is observed without pose writes")
    driver.requested=true
    for unused in 15:
        await physics_frame
        await process_frame
        if not driver.captured.is_empty(): break
    _check(driver.result.get("ok",false) and driver.captured.size()==2,"next normal physics-process boundary samples both bodies exactly",driver.result)
    if driver.captured.size()!=2 or not driver.result.get("ok",false): _finish(); return
    var anchors: Array=[PhysicsServer3D.pin_joint_get_local_a(joint.get_rid()),PhysicsServer3D.pin_joint_get_local_b(joint.get_rid()),joint.get_rid()]
    var clock: float=flight.flight_seconds
    for unused in 10:
        await physics_frame
        for sample: Dictionary in driver.captured:
            if not Boundary.frozen(sample).ok: failures.append("frozen native body changed")
    _check(flight.flight_seconds==clock,"original Flight integrator does not accrue time while owned body frozen")
    _check([PhysicsServer3D.pin_joint_get_local_a(joint.get_rid()),PhysicsServer3D.pin_joint_get_local_b(joint.get_rid()),joint.get_rid()]==anchors,"same real PinJoint RID/anchors during pause")
    for sample: Dictionary in driver.captured:
        _check(Boundary.resume(sample).ok,"native pose/RID and original nonzero momentum restored without transform write")
    for unused in 6: await physics_frame
    _check(flight.flight_seconds>clock,"original Flight callback still runs after resume (not replaced)")
    # An exceptional committed-state failure cannot wait for a valid logical
    # save cache. Preserve the CURRENT Server pose even from an idle mismatch;
    # the operation has no resume path and never writes a stale Node transform.
    for unused in 6:
        await physics_frame
        await process_frame
        if PhysicsServer3D.body_get_state(flight.get_rid(),PhysicsServer3D.BODY_STATE_TRANSFORM)!=flight.global_transform: break
    var fatal_rows: Array=[]
    var fatal_trace: Array=[{"phase":"before_hold","frame":Engine.get_physics_frames(),"bodies":[_native_diag(flight),_native_diag(cargo)]}]
    for body: RigidBody3D in [flight,cargo]:
        fatal_rows.append(Boundary.hold_native_for_reload(body))
    fatal_trace.append({"phase":"immediate_after_hold","frame":Engine.get_physics_frames(),"bodies":[_native_diag(flight),_native_diag(cargo)]})
    _check(fatal_rows[0].ok and fatal_rows[1].ok,"exceptional reload-only hold preserves current native poses without Node synchronization",fatal_rows)
    var held_clock: float=flight.flight_seconds
    var same_native: bool=true
    for unused in 5:
        await physics_frame
        fatal_trace.append({"phase":"subsequent_physics_signal","frame":Engine.get_physics_frames(),"bodies":[_native_diag(flight),_native_diag(cargo)]})
        for row: Dictionary in fatal_rows:
            same_native=same_native and row.ok and PhysicsServer3D.body_get_state(row.rid,PhysicsServer3D.BODY_STATE_TRANSFORM)==row.pose and PhysicsServer3D.body_get_state(row.rid,PhysicsServer3D.BODY_STATE_LINEAR_VELOCITY)==Vector3.ZERO
    _check(same_native,"reload-only hold keeps exact current native pose and zero momentum",fatal_trace)
    _check(flight.flight_seconds==held_clock,"reload-only hold prevents a queued original Flight callback from accruing logical time",{"clock_at_hold":held_clock,"clock_after":flight.flight_seconds,"trace":fatal_trace})
    _finish()

func _native_diag(body: RigidBody3D) -> Dictionary:
    var rid: RID=body.get_rid()
    return {"name":str(body.name),"rid":str(rid),"node":body.global_transform,"native":PhysicsServer3D.body_get_state(rid,PhysicsServer3D.BODY_STATE_TRANSFORM),"linear":PhysicsServer3D.body_get_state(rid,PhysicsServer3D.BODY_STATE_LINEAR_VELOCITY),"angular":PhysicsServer3D.body_get_state(rid,PhysicsServer3D.BODY_STATE_ANGULAR_VELOCITY),"node_linear":body.linear_velocity,"node_angular":body.angular_velocity,"freeze":body.freeze,"freeze_mode":body.freeze_mode,"sleeping":body.sleeping,"enabled":body.enabled if body is Flight else null,"flight_seconds":body.flight_seconds if body is Flight else null}

func _check(ok: bool, label: String, detail: Variant=null) -> void:
    checks.append({"ok":ok,"label":label,"detail":detail})
    if not ok: failures.append(label)

func _finish() -> void:
    var paused_frame: int=driver.frame
    var sampled: Array=[]
    for row: Dictionary in driver.captured:
        var item: Dictionary=row.duplicate()
        item.erase("body")
        sampled.append(item)
    site.free()
    var result: Dictionary={"checks":checks.size(),"failures":failures,"engine_errors":[],"details":checks,"physics_frame":paused_frame,"samples":sampled,"scope":"actual FlightBody/rigid cargo/PinJoint; idle mismatch and next physics-process exact sample/freeze/resume; no MAIN or callback replacement"}
    if not output.is_empty():
        var file:=FileAccess.open(output.path_join("result.json"),FileAccess.WRITE)
        if file: file.store_string(JSON.stringify(result,"\t",true,true))
    print("CANAL_PAUSE_BOUNDARY ",JSON.stringify(result))
    quit(0 if failures.is_empty() else 1)
