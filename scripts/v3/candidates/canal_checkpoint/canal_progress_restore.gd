extends RefCounted
## Rebuild a NEW frozen subtree. No live pose writes, replay, clock or receipt.
const Progress=preload("res://scripts/v3/candidates/canal_checkpoint/canal_progress_checkpoint.gd")
const Wait=Progress.Wait
const State=Wait.State
const Parts=Progress.Parts
const Startup=preload("res://scripts/v3/candidates/canal_checkpoint/canal_startup_checkpoint.gd")
const Bootstrap=preload("res://scripts/v3/candidates/canal_transport_executor/canal_transport_bootstrap.gd")
const Rules=Wait.Rules
const TOOL_SYNC_SETTLE_FRAMES=2
var _site: Node3D
var _saved: Dictionary={}
var _context: Dictionary={}
var _bodies: Dictionary={}
var _bench: Node3D
var _cooling: Node3D
var _executor: RefCounted
var _bootstrap_controller: RefCounted
var _waiting_controller: RefCounted
var _startup := false
var _phase: String="fresh"
var _code: String="fresh"
var _ready_frame: int=-1
var _last_frame: int=-1
var _prepared_frame: int=-1
var _readback: Dictionary={}
var _pickup_source_readback: Dictionary={}
var _tool_readback: Dictionary={}
var _tool_readback_trace: Array=[]
var _tool_identities: Array=[]

func prepare(world: Node3D, saved: Dictionary, environment: Callable, authority: bool=true) -> Dictionary:
    if not authority or _phase!="fresh": return _reply(false,"fresh_progress_host_required")
    _startup=saved.get("kind")==Startup.KIND
    var valid: Dictionary=Startup.validate(saved) if _startup else Progress.validate(saved)
    if not valid.ok: return valid
    if not is_instance_valid(world) or not world.is_inside_tree() or not environment.is_valid() or not world.global_transform.is_equal_approx(Transform3D.IDENTITY): return _reply(false,"live_identity_owner_required")
    if world.has_node("CanalRestoredCandidateSite") or world.has_node("CanalTransportCandidateSite"): return _reply(false,"existing_site")
    for id: String in Rules.BERTHS:
        var proof: Dictionary=Bootstrap._site_preflight(world,id,Wait.Executor.BERTH_POINTS[id])
        if not proof.ok: return _reply(false,"berth_clearance:"+id)
    _saved=saved.duplicate(true)
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
        berth.global_position=Wait.Executor.BERTH_POINTS[id]
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
    var made: Dictionary=State.create_progress(_site,saved.carrier,Rules.CARRIER,45,environment)
    if not made.ok: return _fail("progress_carrier:"+str(made.code))
    _bodies[Rules.CARRIER]=made.body
    Wait.apply_rigid_fresh(made.body,saved.bodies[Rules.CARRIER])
    var rules: RefCounted
    if not saved.rules.is_empty():
        rules=Rules.new()
        if not rules.configure().ok or not rules.restore(saved.rules).ok or not Rules._same(rules.snapshot(),saved.rules): return _fail("progress_rules_restore_changed_value")
    var custody: RefCounted
    var restored: Dictionary={"ok":true}
    if not saved.custody.is_empty():
        custody=Wait.Custody.new()
        var registered: Dictionary=custody.configure(cargos,berths,{Rules.CARRIER:made.body},true)
        if not registered.ok: return _fail("progress_custody_configure:"+str(registered.code))
        restored=custody.restore_progress_fresh(saved.custody,true)
        if not restored.ok: return _fail("progress_joint_restore:"+str(restored.code))
    _context={"carrier":made.body,"cargos":cargos,"berths":berths,"custody":custody,"rules":rules,"environment_query":environment}
    if not saved.workbench.is_empty():
        _bench=Wait.Bench.new()
        _site.add_child(_bench)
        restored=_bench.configure_progress(_context,saved.workbench,true)
        if not restored.ok: return _fail("progress_workbench_restore:"+str(restored.code))
        _bodies[Wait.Safe.BENEFICIARY_ID]=_bench.beneficiary
        Wait.apply_rigid_fresh(_bench.beneficiary,saved.bodies[Wait.Safe.BENEFICIARY_ID])
    if not saved.cooling.is_empty():
        _cooling=Wait.Cooling.new()
        _site.add_child(_cooling)
        restored=_cooling.configure(cargos,berths,custody,true)
        if not restored.ok: return _fail("progress_cooling_configure:"+str(restored.code))
        restored=_cooling.restore_fresh(saved.cooling,true)
        if not restored.ok: return _fail("progress_cooling_restore:"+str(restored.code))
    if not _startup:
        _executor=Parts.restore_executor(_context,saved.executor)
        if _executor==null: return _fail("progress_executor_restore")
    elif saved.mode=="bootstrap":
        _bootstrap_controller=Startup.Boot.restore(_context,world,saved.controller)
        if _bootstrap_controller==null: return _fail("progress_bootstrap_restore")
    else:
        _waiting_controller=Parts.restore_pilot(made.body,saved.controller,cargos)
        if _waiting_controller==null: return _fail("progress_preorder_wait_controller")
    if is_instance_valid(_bench) and int(saved.workbench.version) in [3,4]:
        for part: AnimatableBody3D in _bench._moving:
            var shape: CollisionShape3D=part.get_child(0) as CollisionShape3D
            _tool_identities.append({"node_id":part.get_instance_id(),"body_rid":part.get_rid(),"shape_node_id":shape.get_instance_id(),"shape_rid":shape.shape.get_rid()})
    _prepared_frame=Engine.get_physics_frames()
    _phase="frozen_prepared"
    _code="original_bodies_momentum_joint_rules_controllers_built_frozen"
    return report()

func tick(delta: float, authority: bool=true, paused: bool=false) -> Dictionary:
    if not authority or _phase not in ["frozen_prepared","ready"] or not _live(): return _reply(false,"progress_frozen_restore_required")
    if not is_finite(delta) or delta<0 or delta>1.0/60.0+.000001: return _reply(false,"physics_delta")
    _ready_frame=-1
    if paused or delta==0: return _reply(true,"progress_restore_paused_frozen")
    var frame: int=Engine.get_physics_frames()
    if _last_frame==frame: return _reply(false,"same_physics_frame")
    _last_frame=frame
    if frame<=_prepared_frame: return _reply(true,"fresh_physics_observation_required")
    var checked: Dictionary=_frozen_integrity()
    if not checked.ok:
        # Creation can occur after a process/input callback. The next MAIN
        # physics callback can precede Jolt applying the new kinematic target.
        # Only this exact native-tool-pose mismatch may wait, for at most two
        # new physics frames. _frozen_integrity already proved the unchanged
        # original body/joint state AND each tool's exact target/RID/geometry.
        if str(checked.code)=="progress_tool_physics_not_synchronized" and frame-_prepared_frame<=TOOL_SYNC_SETTLE_FRAMES:
            var clearance: Dictionary=_clearance()
            if not clearance.ok: return _reply(true,"current_clearance_pending:"+str(clearance.code))
            _code="fresh_tool_native_target_pending"
            return report()
        return _fail(str(checked.code))
    checked=_clearance()
    if not checked.ok: return _reply(true,"current_clearance_pending:"+str(checked.code))
    _phase="ready"
    _ready_frame=frame
    _code="frozen_physics_joint_readback_ready_no_clock_advance"
    return report()

func adopt(authority: bool=true) -> Dictionary:
    if not authority or _phase!="ready" or _ready_frame!=Engine.get_physics_frames() or not _live(): return _reply(false,"current_progress_ready_required")
    var checked: Dictionary=_frozen_integrity()
    if not checked.ok: return _fail(str(checked.code))
    checked=_clearance()
    if not checked.ok: return _reply(false,"progress_current_clearance_required")
    # One same-frame adoption. The original next normal tick owns all motion,
    # new contacts, tool work, Rules time and any eventual receipt.
    for id: String in _bodies:
        Wait.unfreeze_original(_bodies[id],_saved.bodies[id])
        _bodies[id].freeze=bool(_saved.bodies[id].freeze)
    _phase="adopted"
    return {"ok":true,"code":"adopted_original_progress_no_receipt","site":_site,"context":_context.duplicate(),"executor":_executor if _executor!=null else Wait.Executor.new(),"workbench":_bench,"cooling":_cooling,"ordered":not _startup,"ready_for_order":not _startup or _saved.mode=="waiting","bootstrap":_bootstrap_controller,"waiting":_waiting_controller,"rule_seconds":_saved.rule_seconds,"rule_usec":_saved.rule_usec}

func _frozen_integrity() -> Dictionary:
    if _context.rules!=null:
        if not Rules._same(_context.rules.snapshot(),_saved.rules): return Wait.bad("progress_rules_changed_during_restore")
    elif not _saved.rules.is_empty(): return Wait.bad("progress_absent_rules_replaced")
    for id: String in _bodies:
        var body: RigidBody3D=_bodies[id]
        if not body.freeze or body.is_processing() or body.is_physics_processing() or body.global_transform!=State.transform(_saved.bodies[id].pose): return Wait.bad("progress_frozen_body_changed:"+id)
        var physical: Transform3D=PhysicsServer3D.body_get_state(body.get_rid(),PhysicsServer3D.BODY_STATE_TRANSFORM)
        var basis_error: float=0.0
        for axis: int in 3:
            for component: int in 3: basis_error=maxf(basis_error,absf(physical.basis[axis][component]-body.global_basis[axis][component]))
        _readback[id]={"position_error_m":physical.origin.distance_to(body.global_position),"basis_max_component_error":basis_error,"node":State.pose(body.global_transform),"physics":State.pose(physical)}
        # Jolt converts Basis -> normalized float Quaternion -> Basis. Rotated
        # dynamic loads therefore need not retain bit-identical matrix entries.
        # Position stays exact; only the bounded representation round-trip is
        # accepted. This is unrelated to pending kinematic scan target settling.
        if physical.origin!=body.global_position or basis_error>.000001: return Wait.bad("progress_physics_pose_not_synchronized:"+id)
    if not _saved.custody.is_empty() and not _saved.custody.joint.is_empty():
        var data: Dictionary=_saved.custody.joint
        var joint: PinJoint3D=_context.carrier.cargo_joint
        if not is_instance_valid(joint) or PhysicsServer3D.pin_joint_get_local_a(joint.get_rid())!=State.vec(data.local_a) or PhysicsServer3D.pin_joint_get_local_b(joint.get_rid())!=State.vec(data.local_b) or joint.exclude_nodes_from_collision!=data.exclude_pair or joint.solver_priority!=int(data.solver_priority) or joint.get_param(PinJoint3D.PARAM_BIAS)!=float(data.bias) or joint.get_param(PinJoint3D.PARAM_DAMPING)!=float(data.damping) or joint.get_param(PinJoint3D.PARAM_IMPULSE_CLAMP)!=float(data.impulse_clamp): return Wait.bad("progress_joint_changed")
    if is_instance_valid(_bench) and int(_saved.workbench.version) in [3,4]:
        _tool_readback=_bench.tool_physics_readback()
        _tool_readback["prepared_frame"]=_prepared_frame
        _tool_readback["saved_tools"]=_saved.workbench.tools.duplicate(true)
        var targets: Dictionary=_tool_restore_targets_intact()
        _tool_readback["restore_target_integrity"]=targets
        if _tool_readback_trace.size()<3 and (_tool_readback_trace.is_empty() or int(_tool_readback_trace[-1].physics_frame)!=Engine.get_physics_frames()): _tool_readback_trace.append(_tool_readback.duplicate(true))
        if not targets.ok: return targets
        if not _bench._tools_synchronized(): return Wait.bad("progress_tool_physics_not_synchronized")
    return {"ok":true,"code":"original_frozen_state_verified"}

func _tool_restore_targets_intact() -> Dictionary:
    if _bench._moving.size()!=4 or _tool_identities.size()!=4: return Wait.bad("progress_tool_restore_registry_changed")
    for i: int in 4:
        var part: AnimatableBody3D=_bench._moving[i]
        var identity: Dictionary=_tool_identities[i]
        var saved: Dictionary=_saved.workbench.tools[i]
        if not is_instance_valid(part) or not part.is_inside_tree() or not _bench.is_ancestor_of(part) or part.get_instance_id()!=identity.node_id or part.get_rid()!=identity.body_rid or part.sync_to_physics or part.get_world_3d().space!=_site.get_world_3d().space or part.global_transform!=State.transform(saved.pose) or part.get_child_count()!=2: return Wait.bad("progress_tool_restore_target_changed:"+str(i))
        var shape: CollisionShape3D=part.get_child(0) as CollisionShape3D
        if not is_instance_valid(shape) or shape.get_instance_id()!=identity.shape_node_id or not shape.shape is BoxShape3D or shape.shape.get_rid()!=identity.shape_rid or shape.disabled or shape.transform!=Transform3D.IDENTITY or (shape.shape as BoxShape3D).size!=State.vec(saved.size): return Wait.bad("progress_tool_restore_shape_changed:"+str(i))
        var rid: RID=part.get_rid()
        if PhysicsServer3D.body_get_mode(rid)!=PhysicsServer3D.BODY_MODE_KINEMATIC or PhysicsServer3D.body_get_space(rid)!=_site.get_world_3d().space or PhysicsServer3D.body_get_shape_count(rid)!=1 or PhysicsServer3D.body_get_shape(rid,0)!=identity.shape_rid or PhysicsServer3D.body_get_shape_transform(rid,0)!=Transform3D.IDENTITY or PhysicsServer3D.shape_get_data(identity.shape_rid)!=(shape.shape as BoxShape3D).size*.5: return Wait.bad("progress_tool_restore_native_geometry_changed:"+str(i))
    return {"ok":true,"code":"original_four_tool_targets_rids_native_shapes_exact"}

func _clearance() -> Dictionary:
    for id: String in _bodies:
        var body: RigidBody3D=_bodies[id]
        var shape:=BoxShape3D.new()
        shape.size=State.vec(_saved.bodies[id].shape_size)-Vector3.ONE*.002
        var query:=PhysicsShapeQueryParameters3D.new()
        query.shape=shape
        query.margin=0.0
        query.transform=body.global_transform
        query.collision_mask=Wait.Custody.MASK
        var excluded: Array[RID]=[body.get_rid()]
        if id in Rules.CASSETTES and not _saved.custody.is_empty():
            var physical: Dictionary=_saved.custody.cargos[id]
            if physical.phase in ["docked","settling","dropping"]: excluded.append(_context.berths[str(physical.berth)].get_rid())
            elif physical.phase=="carried":
                excluded.append(_context.carrier.get_rid())
                var original_support: String=_verified_pickup_source(id)
                if not original_support.is_empty(): excluded.append(_context.berths[original_support].get_rid())
        elif id==Rules.CARRIER:
            for item: Dictionary in _context.carrier.cargo_items.values(): excluded.append(item.body.get_rid())
        elif id==Wait.Safe.BENEFICIARY_ID and is_instance_valid(_bench): excluded.append(_bench.rack.get_rid())
        query.exclude=excluded
        var hits: Array[Dictionary]=body.get_world_3d().direct_space_state.intersect_shape(query,1)
        if not hits.is_empty(): return Wait.bad("progress_body_obstructed:"+id+":"+str(hits[0].collider.name))
    return {"ok":true,"code":"current_physical_envelopes_clear"}

func _verified_pickup_source(id: String) -> String:
    if _startup or _saved.executor.is_empty() or not _saved.executor.pickup_supported_history or _saved.custody.joint.is_empty(): return ""
    var fields: Dictionary=_saved.executor.fields
    if fields._phase not in ["commit","departure_wait","departure"]: return ""
    var action: Dictionary=fields._action if fields._phase=="commit" else fields._departure
    if action.get("kind")!="pick" or action.get("cassette_id")!=id or action.get("actor")!=Rules.CARRIER or action.get("route")!="low" or action.get("source") not in Rules.BERTHS or action.get("destination")!=Rules.CARRIER: return ""
    var source: String=str(action.source)
    var actual: Dictionary=_saved.custody.cargos[id]
    var joint: Dictionary=_saved.custody.joint
    if actual.phase!="carried" or actual.carrier!=Rules.CARRIER or not str(actual.berth).is_empty() or joint.cargo_id!=id or joint.carrier_id!=Rules.CARRIER or int(joint.grip.serial)!=int(actual.serial) or int(_saved.custody.last_serial)!=int(actual.serial) or int(fields._serial)<int(actual.serial): return ""
    if fields._phase=="commit":
        if _saved.rules.cassettes[id].holder!=source or not Rules._same(action,_saved.rules.pending_action) or int(fields._serial)!=int(actual.serial) or _saved.executor.pilot.mode!="pickup_alignment" or _saved.executor.pilot.alignment_cargo!=id: return ""
    else:
        if _saved.rules.cassettes[id].holder!=Rules.CARRIER or not _saved.rules.pending_action.is_empty() or int(_saved.rules.action_serial)!=int(action.serial) or not fields._action.is_empty(): return ""
        if fields._phase=="departure" and (_saved.executor.dock.is_empty() or _saved.executor.dock.berth!=source or _saved.executor.dock.mode!="departure" or _saved.executor.dock.state not in ["lifting","clear"]): return ""
    for other: String in Rules.CASSETTES:
        if other!=id and _saved.rules.cassettes[other].holder==source: return ""
    if not _context.custody._integrity(id).is_empty() or not _context.custody._same_berth(source): return ""
    var cargo: RigidBody3D=_context.cargos[id]
    var berth: StaticBody3D=_context.berths[source]
    var proof: Dictionary=_context.custody.support_info(id,source)
    # The frozen reconstruction cannot import ContactMonitor time. Reuse its
    # ORIGINAL support geometry/rays against the current real source RID. This
    # is a narrow clearance allowance, never a claim of docked/current350ms.
    if proof.get("cargo_rid")!=cargo.get_rid() or proof.get("support_rid")!=berth.get_rid() or not proof.get("five_rays_on_support",false) or not _context.custody._footprint(proof.cargo_bounds,proof.support_bounds) or absf(float(proof.bottom_gap_m))>.025 or cargo.global_basis.y.dot(Vector3.UP)<.985: return ""
    _pickup_source_readback[id]={"source":source,"phase":fields._phase,"pick_serial":action.serial,"actual_joint_serial":actual.serial,"support_rid":berth.get_rid(),"bottom_gap_m":proof.bottom_gap_m,"five_current_rays":true,"up_dot":cargo.global_basis.y.dot(Vector3.UP),"new_contact_credit":0}
    return source

func _live() -> bool:
    if not is_instance_valid(_site) or not _site.is_inside_tree(): return false
    for body: Variant in _bodies.values():
        if not body is RigidBody3D or not is_instance_valid(body) or not body.is_inside_tree() or not _site.is_ancestor_of(body) or body.get_world_3d().space!=_site.get_world_3d().space: return false
    return (_saved.workbench.is_empty() or is_instance_valid(_bench)) and (_saved.cooling.is_empty() or is_instance_valid(_cooling))

func discard() -> void:
    if _phase=="adopted": return
    if is_instance_valid(_site): _site.free()
    _context.clear()
    _bodies.clear()
    _phase="discarded"

func report() -> Dictionary:
    return {"ok":_phase not in ["fresh","fault","discarded"],"phase":_phase,"code":_code,"ready":_phase=="ready" and _ready_frame==Engine.get_physics_frames(),"scope":"ongoing_transport_frozen_rebuild","new_contact_credit":0,"physical_readback":_readback.duplicate(true),"pickup_source_clearance":_pickup_source_readback.duplicate(true),"tool_physics_readback":_tool_readback.duplicate(true),"tool_first_physics_readbacks":_tool_readback_trace.duplicate(true),"tool_sync_timeout_frames":TOOL_SYNC_SETTLE_FRAMES}

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
