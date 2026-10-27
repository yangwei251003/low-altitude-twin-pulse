extends RefCounted
## Fresh subtree only. No Bootstrap, pickup/place/work receipt or Store writes.
const Scan=preload("res://scripts/v3/candidates/canal_checkpoint/canal_scan_checkpoint.gd")
const Wait=preload("res://scripts/v3/candidates/canal_checkpoint/canal_wait_checkpoint.gd")
const State=Wait.State
const Bootstrap=preload("res://scripts/v3/candidates/canal_transport_executor/canal_transport_bootstrap.gd")
const Rules=Wait.Rules
const Executor=Wait.Executor
const Custody=Wait.Custody
const Bench=Wait.Bench
const Cooling=Wait.Cooling
var _site: Node3D
var _saved: Dictionary={}
var _context: Dictionary={}
var _rules_baseline: Dictionary={}
var _bodies: Dictionary={}
var _bench: Node3D
var _cooling: Node3D
var _executor: RefCounted
var _carried: bool=false
var _custody_ready: bool=false
var _phase: String="fresh"
var _code: String="fresh"
var _detail: Dictionary={}
var _last_frame: int=-1
var _ready_frame: int=-1
var _support_usec: int=0
var _activated: bool=false
var _paused_motion: Dictionary={}

func prepare(world: Node3D, saved: Dictionary, environment: Callable, authority: bool=true) -> Dictionary:
    if not authority or _phase!="fresh": return _reply(false,"fresh_host_restore_required")
    var valid: Dictionary=Scan.validate(saved)
    if not valid.ok: return valid
    if not is_instance_valid(world) or not world.is_inside_tree() or not environment.is_valid() or not world.global_transform.is_equal_approx(Transform3D.IDENTITY): return _reply(false,"live_identity_owner_required")
    if world.has_node("CanalRestoredCandidateSite") or world.has_node("CanalTransportCandidateSite"): return _reply(false,"existing_site")
    for id: String in Rules.BERTHS:
        var proof: Dictionary=Bootstrap._site_preflight(world,id,Executor.BERTH_POINTS[id])
        if not proof.ok: return _reply(false,"berth_clearance:"+id)
    _saved=saved.duplicate(true)
    _carried=saved.custody.version==2
    _site=Node3D.new()
    _site.name="CanalRestoredCandidateSite"
    world.add_child(_site)
    var berths: Dictionary={}
    for id: String in Rules.BERTHS:
        var berth:=StaticBody3D.new()
        berth.name="CandidateBerth_"+id
        berth.collision_layer=1
        berth.collision_mask=0
        berth.add_child(Bootstrap._box(Vector3(2,.5,2)))
        _site.add_child(berth)
        berth.global_position=Executor.BERTH_POINTS[id]
        berth.force_update_transform()
        berths[id]=berth
    var cargos: Dictionary={}
    for id: String in Rules.CASSETTES:
        var cargo:=RigidBody3D.new()
        cargo.name=id.replace(":","_")
        cargo.freeze=true
        cargo.contact_monitor=true
        cargo.max_contacts_reported=16
        cargo.add_child(Bootstrap._box(Vector3(.4,.4,.4)))
        _site.add_child(cargo)
        Wait.apply_rigid_fresh(cargo,saved.bodies[id])
        cargos[id]=cargo
        _bodies[id]=cargo
    var made: Dictionary=State.create(_site,saved.carrier,Rules.CARRIER,45,environment,true,true)
    if not made.ok: return _fail(made.code)
    _bodies[Rules.CARRIER]=made.body
    Wait.apply_rigid_fresh(made.body,saved.bodies[Rules.CARRIER])
    var rules=Rules.new()
    if not rules.configure().ok or not rules.restore(saved.rules).ok: return _fail("rule_restore")
    _rules_baseline=rules.snapshot()
    if not Rules._same(_rules_baseline,saved.rules): return _fail("rule_restore_changed_value")
    var custody=Custody.new()
    var registered: Dictionary=custody.configure(cargos,berths,{Rules.CARRIER:made.body},true)
    if not registered.ok: return _fail("custody_configure:"+str(registered.code))
    _context={"carrier":made.body,"cargos":cargos,"berths":berths,"custody":custody,"rules":rules,"environment_query":environment}
    if _carried:
        var attached: Dictionary=custody.restore_wait_fresh(saved.custody,Rules.CASSETTES[0],Rules.CARRIER,Rules.CASSETTES[1],Rules.WORK,true)
        if not attached.ok: return _fail("joint_restore:"+str(attached.code))
        _custody_ready=true
    _bench=Bench.new()
    _site.add_child(_bench)
    var bench: Dictionary=_bench.configure_scan(_context,saved.workbench,true)
    if not bench.ok: return _fail("workbench_restore:"+str(bench.code))
    _bodies[Wait.Safe.BENEFICIARY_ID]=_bench.beneficiary
    Wait.apply_rigid_fresh(_bench.beneficiary,saved.bodies[Wait.Safe.BENEFICIARY_ID])
    _cooling=Cooling.new()
    _site.add_child(_cooling)
    var cooling: Dictionary=_cooling.configure(cargos,berths,custody,true)
    if not cooling.ok: return _fail("cooling_configure:"+str(cooling.code))
    cooling=_cooling.restore_fresh(saved.cooling,true)
    if not cooling.ok: return _fail("cooling_restore:"+str(cooling.code))
    _executor=Executor.new()
    var controller: Dictionary=_executor.configure_scan_restored(_context,saved.executor,true)
    if not controller.ok: return _fail("executor_restore:"+str(controller.code))
    var clear: Dictionary=_clearance()
    if not clear.ok: return _fail(clear.code)
    _phase="frozen_prepared"
    _code="all_bodies_joint_rules_devices_built_before_unfreeze"
    _detail={"body_count":_bodies.size(),"all_frozen":true,"rules_unchanged":rules.snapshot()==_rules_baseline,"occupancy":"carried" if _carried else "docked","saved_tool":saved.workbench.tool.duplicate(),"saved_distance":saved.workbench.scan_distance_m,"saved_stage":saved.workbench.stage,"saved_pending":saved.rules.pending_action.duplicate(true)}
    if _carried:
        _detail["joint"]={"source":saved.custody.joint.duplicate(true),"local_a":State.xyz(PhysicsServer3D.pin_joint_get_local_a(made.body.cargo_joint.get_rid())),"local_b":State.xyz(PhysicsServer3D.pin_joint_get_local_b(made.body.cargo_joint.get_rid()))}
    return report()

func tick(delta: float, authority: bool=true, paused: bool=false) -> Dictionary:
    if not authority or _phase in ["fresh","fault","discarded","adopted"]: return _reply(false,"inactive_host_restore")
    if not is_finite(delta) or delta<0 or delta>1.0/60.0+.000001: return _reply(false,"physics_delta")
    if not _live(): return _fail("candidate_identity_lost")
    if _context.rules.snapshot()!=_rules_baseline: return _fail("rules_changed_during_restore")
    if not _joint_matches(): return _fail("restored_joint_changed")
    if paused or delta==0:
        if _activated and _paused_motion.is_empty():
            for id: String in _bodies:
                var body: RigidBody3D=_bodies[id]
                _paused_motion[id]={"velocity":body.linear_velocity,"angular":body.angular_velocity,"sleeping":body.sleeping}
                body.freeze=true
                body.set_process(false)
                body.set_physics_process(false)
        _ready_frame=-1
        _support_usec=0
        return _reply(true,"restore_paused_no_contact_credit")
    if _last_frame==Engine.get_physics_frames(): return _reply(false,"same_physics_frame")
    if _last_frame>=0 and Engine.get_physics_frames()!=_last_frame+1: _support_usec=0
    _last_frame=Engine.get_physics_frames()
    if not _activated:
        var clear: Dictionary=_clearance()
        if not clear.ok: return _fail(clear.code)
        for id: String in _bodies: Wait.unfreeze_original(_bodies[id],_saved.bodies[id])
        _activated=true
        _phase="reacquire_actual_support"
        return _reply(true,"original_momentum_restored_once")
    if not _paused_motion.is_empty():
        for id: String in _bodies:
            var body: RigidBody3D=_bodies[id]
            body.freeze=false
            body.linear_velocity=_paused_motion[id].velocity
            body.angular_velocity=_paused_motion[id].angular
            body.sleeping=_paused_motion[id].sleeping
            body.set_process(_saved.bodies[id].process)
            body.set_physics_process(_saved.bodies[id].physics_process)
        _paused_motion.clear()
    _context.carrier.environment_sample=_context.environment_query.call(_context.carrier.global_position)
    var held: Dictionary=_executor.scan_restore_hold(delta,true)
    if not held.ok: return _fail("restored_controller:"+str(held.code))
    if not _custody_ready:
        var custody: Dictionary=_context.custody.restore_docked_fresh(_saved.custody,true,false)
        if custody.ok: _custody_ready=true
        elif custody.code not in ["restore_support_pending","restore_stability_pending"]: return _fail("restore_custody:"+str(custody.code))
    var worked: Dictionary=_bench.advance(delta,true,false)
    var cooled: Dictionary=_cooling.advance(delta,true)
    if not worked.ok or not cooled.ok: return _fail("restored_device:"+str(worked.code)+":"+str(cooled.code))
    if _bench.head.global_position!=State.vec(_saved.workbench.tool) or _bench.report().scan_distance_m!=_saved.workbench.scan_distance_m: return _fail("restore_advanced_partial_work")
    var supported: bool=_current_support()
    _support_usec=mini(350000,_support_usec+roundi(delta*1000000.0)) if supported else 0
    _ready_frame=Engine.get_physics_frames() if _support_usec>=350000 and _executor.scan_restore_ready() and _bench.scan_restore_ready() else -1
    _phase="ready" if _ready_frame>=0 else "reacquire_actual_support"
    _code="current_support_and_original_joint_ready" if _ready_frame>=0 else "current_support_pending"
    return report()

func adopt(authority: bool=true) -> Dictionary:
    if not authority or _phase!="ready" or _ready_frame!=Engine.get_physics_frames() or not _live() or not _current_support() or _context.rules.snapshot()!=_rules_baseline: return _reply(false,"current_ready_required")
    if not _executor.scan_restore_ready() or not _bench.scan_restore_ready(): return _reply(false,"current_scan_revalidation_required")
    var moved: Dictionary=_executor.resume_scan_restored(true)
    var worked: Dictionary=_bench.resume_scan(true)
    if not moved.ok or not worked.ok: return _fail("atomic_scan_adopt_failed")
    _phase="adopted"
    return {"ok":true,"code":"adopted_original_partial_scan_no_receipt","site":_site,"context":_context.duplicate(),"executor":_executor,"workbench":_bench,"cooling":_cooling,"ordered":true,"rule_seconds":_saved.rule_seconds,"rule_usec":_saved.rule_usec}

func _current_support() -> bool:
    if not _joint_matches(): return false
    if not _context.custody._integrity(Rules.CASSETTES[0]).is_empty() or not _context.custody._integrity(Rules.CASSETTES[1]).is_empty(): return false
    if not _custody_ready or not Bench.Departure.support_proof(_bench.beneficiary,_bench.rack).get("supported",false): return false
    for id: String in Rules.CASSETTES:
        var holder: String=str(_rules_baseline.cassettes[id].holder)
        if holder!=Rules.CARRIER and not _context.custody.support_info(id,holder).get("supported",false): return false
    var goal: Vector3=Executor.WAIT_POINT if _rules_baseline.carrier_anchor==Rules.WAIT else Executor.BERTH_POINTS[str(_rules_baseline.carrier_anchor)]+Vector3.UP*2.2
    return _executor._pilot.probe(Vector3.ZERO).clear and _context.carrier.global_position.distance_to(goal)<.18 and _context.carrier.linear_velocity.length()<.18

func _joint_matches() -> bool:
    if _context.is_empty() or not is_instance_valid(_context.carrier): return false
    var carrier: State.Flight=_context.carrier
    if not _carried: return carrier.cargo_items.is_empty() and not is_instance_valid(carrier.cargo_joint) and carrier.cargo_kg==0
    var joint: PinJoint3D=carrier.cargo_joint
    if not is_instance_valid(joint) or not joint.is_inside_tree() or not joint.get_rid().is_valid(): return false
    var data: Dictionary=_saved.custody.joint
    return PhysicsServer3D.pin_joint_get_local_a(joint.get_rid())==State.vec(data.local_a) and PhysicsServer3D.pin_joint_get_local_b(joint.get_rid())==State.vec(data.local_b) and joint.exclude_nodes_from_collision==data.exclude_pair and joint.solver_priority==data.solver_priority and joint.get_param(PinJoint3D.PARAM_BIAS)==data.bias and joint.get_param(PinJoint3D.PARAM_DAMPING)==data.damping and joint.get_param(PinJoint3D.PARAM_IMPULSE_CLAMP)==data.impulse_clamp

func _clearance() -> Dictionary:
    for id: String in _bodies:
        var body: RigidBody3D=_bodies[id]
        var shape:=BoxShape3D.new()
        shape.size=State.vec(_saved.bodies[id].shape_size)
        var query:=PhysicsShapeQueryParameters3D.new()
        query.shape=shape
        query.transform=body.global_transform
        query.collision_mask=Custody.MASK
        var excluded: Array[RID]=[body.get_rid()]
        # Only a named support beneath the saved physical footprint is excluded
        # from initial overlap; it remains a real colliding body thereafter.
        if id in Rules.CASSETTES:
            var holder: String=str(_rules_baseline.cassettes[id].holder)
            if holder!=Rules.CARRIER: excluded.append(_context.berths[holder].get_rid())
        if id==Wait.Safe.BENEFICIARY_ID: excluded.append(_bench.rack.get_rid())
        query.exclude=excluded
        var hit: Array[Dictionary]=body.get_world_3d().direct_space_state.intersect_shape(query,1)
        if not hit.is_empty(): return Wait.bad("restored_body_obstructed:"+id+":"+str(hit[0].collider.name))
    return {"ok":true,"code":"all_real_envelopes_clear"}

func _live() -> bool:
    if not is_instance_valid(_site) or not _site.is_inside_tree(): return false
    for body: Variant in _bodies.values():
        if not body is RigidBody3D or not is_instance_valid(body) or not body.is_inside_tree() or not _site.is_ancestor_of(body) or body.get_world_3d().space!=_site.get_world_3d().space: return false
    return is_instance_valid(_bench) and is_instance_valid(_cooling)

func discard() -> void:
    if _phase=="adopted": return
    if is_instance_valid(_site): _site.free()
    _context.clear()
    _bodies.clear()
    _phase="discarded"

func report() -> Dictionary:
    return {"ok":_phase not in ["fresh","fault","discarded"],"phase":_phase,"code":_code,"ready":_phase=="ready" and _ready_frame==Engine.get_physics_frames(),"support_observed_usec":_support_usec,"detail":_detail.duplicate(true),"scope":"fresh_stationary_partial_scan_only"}

func _reply(ok: bool, code: String) -> Dictionary:
    var result: Dictionary=report()
    result.ok=ok
    result.code=code
    return result

func _fail(code: String) -> Dictionary:
    discard()
    _phase="fault"
    _code=code
    return report()
