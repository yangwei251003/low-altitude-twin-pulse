extends Node3D
## Host-internal physical candidate. No Store, reward, network or healing API.
## Caller alone advances Custody/Rules; this module consumes real pending work.
const Flight = preload("res://scripts/v2/flight_body.gd")
const Catalog = preload("res://scripts/v2/catalog.gd")
const Rules = preload("res://scripts/v3/candidates/canal_service_loop/canal_service_runtime.gd")
const Custody = preload("res://scripts/v3/candidates/canal_transport_physics/cargo_custody.gd")
const Dock = preload("res://scripts/v3/candidates/canal_transport_physics/dock_lift.gd")
const Departure = preload("res://scripts/v3/candidates/canal_workbench/beneficiary_departure.gd")
const FlightState = preload("res://scripts/v3/candidates/canal_checkpoint/flight_state.gd")
const History = preload("res://scripts/v3/candidates/canal_checkpoint/history_state.gd")
const Pilot = preload("res://scripts/v3/candidates/canal_transport_physics/transport_pilot.gd")
const ProgressState = preload("res://scripts/v3/candidates/canal_checkpoint/canal_workbench_progress.gd")
const MASK := 1 | 2 | 4 | 8 | 32
const POWER_ID := "I2:canal_workbench_power"
const MATCH_KEYS := ["serial","kind","actor","cassette_id","source","destination","route","job"]
const PARK := Vector3(6.25,.94,4.65)
const POINT_A := Vector3(6.25,.94,6)
const POINT_B := Vector3(6.95,.94,6)
const TOOL_SIZE := Vector3(.12,.08,.12)
const TOOL_SPEED := .22
const STAGES := ["approach","scan_out","scan_back","retract"]
const ENDPOINTS: Array[Vector3] = [POINT_A,POINT_B,POINT_A,PARK]
var beneficiary: Flight
var rack: StaticBody3D
var power_target: StaticBody3D
var head: AnimatableBody3D
var arm: AnimatableBody3D
var neck: AnimatableBody3D
var _fixed: Array[StaticBody3D] = []
var _fixed_geometry: Dictionary = {}
var _moving: Array[AnimatableBody3D] = []
var _rules: RefCounted
var _custody: RefCounted
var _carrier: WeakRef
var _cargos: Dictionary = {}
var _berths: Dictionary = {}
var _berth_poses: Dictionary = {}
var _berth_geometry: Dictionary = {}
var _beneficiary_ref: WeakRef
var _beneficiary_geometry: Dictionary = {}
var _space := RID()
var _environment: Callable
var _configured := false
var _authority := false
var _closed := false
var _in_tick := false
var _last_frame := -1
var _charge := 0.0
var _charge_serial := 0
var _phase := "unconfigured"
var _code := "unconfigured"
var _stage := 0
var _action: Dictionary = {}
var _work_cargo: WeakRef
var _support_stable := 0.0
var _bound_pose := Transform3D.IDENTITY
var _pose_bound := false
var _health := 0.0
var _collision_count := 0
var _scan_distance := 0.0
var _measurements: Array = []
var _receipt: Dictionary = {}
var _receipt_count := 0
var _departure: RefCounted
var _last_gate: Dictionary = {}
var _last_motion: Dictionary = {}
var _departure_report: Dictionary = {}
var _preflight: Array = []
var _committed := false
var _tool_position := PARK
var _restored_history: Dictionary = {}
var _progress_history: Dictionary = {}
var _terminal_pilot: RefCounted
var _wait_support_history := 0.0
var _scan_restore_pending := false
var _scan_ready_frame := -1
var _scan_sources: Array = []
var _scan_revalidated := 0
var _capture_requested_frame := -1
var _capture_ready_frame := -1
var _capture_expired := false
const CAPTURE_SETTLE_FRAMES := 12

func configure(context: Dictionary, authority: bool = true) -> Dictionary:
    return _configure(context,authority,{})

## Fresh reconstruction of an already committed result. Historical measurements
## retain stable identity; no measurement is relabeled with a new instance ID.
func configure_completed(context: Dictionary, saved: Dictionary, authority: bool = true) -> Dictionary:
    if not saved.get("checkpoint") is Dictionary or not saved.get("history") is Dictionary or not saved.get("physics") is Dictionary: return {"ok":false,"code":"completed_envelope_required"}
    if not context.get("rules") is RefCounted: return {"ok":false,"code":"actual_rules_required"}
    var state: Dictionary = context.rules.snapshot()
    if state.is_empty() or int(state.jobs_completed) != 1 or not state.pending_action.is_empty(): return {"ok":false,"code":"completed_rule_state_required"}
    var history: Dictionary = History.validate(saved.history,state,POINT_A,POINT_B,TOOL_SIZE,Departure.ROUTE[-1])
    if not history.ok: return history
    var cp: Dictionary = saved.checkpoint
    if not FlightState.validate(cp.get("beneficiary"),History.BENEFICIARY_ID) or not FlightState.number(cp.get("workbench_charge"),0,100) or not FlightState.integer(cp.get("workbench_charge_serial"),1,2147483647): return {"ok":false,"code":"completed_state_invalid"}
    if FlightState.transform(cp.beneficiary.pose).origin.distance_to(Departure.ROUTE[-1]) >= .18: return {"ok":false,"code":"completed_terminal_pose"}
    if not context.get("custody") is RefCounted or context.custody.docked_snapshot().is_empty(): return {"ok":false,"code":"completed_real_custody_required"}
    return _configure(context,authority,saved)

func _configure(context: Dictionary, authority: bool, completed: Dictionary, waiting: Dictionary = {}, scanning: Dictionary = {}, progress_wait: bool = false, progress: Dictionary = {}) -> Dictionary:
    if not authority: return {"ok":false,"code":"not_authority"}
    if _configured or _closed or not is_inside_tree() or not global_transform.is_equal_approx(Transform3D.IDENTITY): return {"ok":false,"code":"fresh_identity_world_node_required"}
    if not context.get("carrier") is Flight or not context.get("cargos") is Dictionary or not context.get("berths") is Dictionary: return {"ok":false,"code":"context_types"}
    var carrier: Flight = context.carrier
    var custody: Variant = context.get("custody")
    var rules: Variant = context.get("rules")
    var environment: Variant = context.get("environment_query")
    if not is_instance_valid(carrier) or not carrier.is_inside_tree() or carrier.get_world_3d().space != get_world_3d().space: return {"ok":false,"code":"same_world_required"}
    if not custody is RefCounted or not is_instance_valid(custody) or custody.get_script() != Custody or not rules is RefCounted or not is_instance_valid(rules) or rules.get_script() != Rules: return {"ok":false,"code":"actual_rules_custody_required"}
    if not environment is Callable or not environment.is_valid() or context.cargos.size() != 2 or context.berths.size() != 4: return {"ok":false,"code":"registry_contract"}
    var state: Dictionary = rules.snapshot()
    if progress.is_empty() and not progress_wait and completed.is_empty() and scanning.is_empty() and (state.is_empty() or int(state.jobs_completed) != 0 or int(state.service_credit) != 0 or not state.pending_action.is_empty()): return {"ok":false,"code":"unserved_candidate_only"}
    if not progress.is_empty() and not ProgressState.validate(progress,state,get_script()).ok: return {"ok":false,"code":"progress_committed_contract"}
    if progress_wait and (waiting.is_empty() or not validate_wait_progress(waiting).ok or not rules.validate_snapshot(state).ok or int(state.jobs_completed)!=0): return {"ok":false,"code":"progress_wait_contract"}
    if not scanning.is_empty() and (not validate_scan(scanning).ok or not Rules._same(state.pending_action,scanning.action) or int(state.jobs_completed)!=0): return {"ok":false,"code":"scan_pending_contract"}
    if not custody.report().get("authority",false): return {"ok":false,"code":"host_custody_required"}
    var seen: Dictionary = {carrier.get_instance_id():true}
    for id: String in Rules.CASSETTES:
        var cargo: Variant = context.cargos.get(id)
        if not cargo is RigidBody3D or not _same_world(cargo) or seen.has(cargo.get_instance_id()): return {"ok":false,"code":"cargo_identity"}
        seen[cargo.get_instance_id()] = true
    for id: String in Rules.BERTHS:
        var berth: Variant = context.berths.get(id)
        if not berth is StaticBody3D or not _same_world(berth) or seen.has(berth.get_instance_id()) or not Dock._support(berth).ok: return {"ok":false,"code":"berth_identity"}
        seen[berth.get_instance_id()] = true
    # Check all volumes against actual existing World physics before creation.
    _preflight.clear()
    for row: Dictionary in fixed_definition():
        var proof: Dictionary = _query_box(AABB(row.center-row.size*.5,row.size).grow(-.001),Vector3.ZERO,[])
        _preflight.append({"part":row.id,"result":proof})
        if not proof.clear: return {"ok":false,"code":"new_structure_obstructed","preflight":_preflight.duplicate(true)}
    for at: Vector3 in [PARK,POINT_A,POINT_B]:
        for box: AABB in _tool_boxes(at):
            var checked: Dictionary = _query_box(box,Vector3.ZERO,[])
            if not checked.clear: return {"ok":false,"code":"tool_envelope_obstructed","detail":checked}
    var start_box: AABB = AABB(Vector3(5.9,.34,5.3),Vector3(1.4,.48,1.4)) if completed.is_empty() else FlightState.transform(completed.checkpoint.beneficiary.pose)*AABB(Vector3(-.7,-.24,-.7),Vector3(1.4,.48,1.4))
    if not waiting.is_empty(): start_box = FlightState.transform(waiting.beneficiary.pose)*AABB(Vector3(-.7,-.24,-.7),Vector3(1.4,.48,1.4))
    if not scanning.is_empty(): start_box = FlightState.transform(scanning.beneficiary.pose)*AABB(Vector3(-.7,-.24,-.7),Vector3(1.4,.48,1.4))
    if not progress.is_empty(): start_box = FlightState.transform(progress.beneficiary.pose)*AABB(Vector3(-.7,-.24,-.7),Vector3(1.4,.48,1.4))
    var start: Dictionary = _query_box(start_box,Vector3.ZERO,[])
    if not start.clear: return {"ok":false,"code":"beneficiary_initial_obstructed","detail":start}
    _rules = rules
    _custody = custody
    _carrier = weakref(carrier)
    _environment = environment
    _space = get_world_3d().space
    for id: String in context.cargos: _cargos[id] = weakref(context.cargos[id])
    for id: String in context.berths:
        _berths[id] = weakref(context.berths[id])
        _berth_poses[id] = context.berths[id].global_transform
        _berth_geometry[id] = _shape_identity(context.berths[id])
    for row: Dictionary in fixed_definition():
        var part: StaticBody3D = _fixed_box(row.id,row.center,row.size,row.color)
        _fixed.append(part)
        _fixed_geometry[part.get_instance_id()] = _shape_identity(part)
        if row.id == "RepairRack": rack = part
        if row.id == "PowerContact": power_target = part
    power_target.set_meta("target_id",POWER_ID)
    power_target.set_meta("charge",0.0)
    for id: String in ["ProbeHead","ProbeNeck","ProbeArm","ProbeCarriage"]:
        var moving := AnimatableBody3D.new()
        moving.name = id
        moving.sync_to_physics = false
        moving.collision_layer = 1
        moving.collision_mask = MASK
        var collision := CollisionShape3D.new()
        collision.shape = BoxShape3D.new()
        moving.add_child(collision)
        var visual := MeshInstance3D.new()
        visual.mesh = BoxMesh.new()
        visual.material_override = _material(Color("ddbb5d"))
        moving.add_child(visual)
        add_child(moving)
        _moving.append(moving)
    head = _moving[0]
    neck = _moving[1]
    arm = _moving[2]
    _set_tool(PARK)
    var initial_scan_or_wait: Dictionary=progress if not progress.is_empty() else (scanning if not scanning.is_empty() else waiting)
    if not initial_scan_or_wait.is_empty():
        waiting=initial_scan_or_wait
        var made: Dictionary=FlightState.create_progress(self,waiting.beneficiary,History.BENEFICIARY_ID,47,_environment) if not progress.is_empty() or (progress_wait and int(waiting.version)==2) else FlightState.create(self,waiting.beneficiary,History.BENEFICIARY_ID,47,_environment,true,true)
        if not made.ok: return made
        beneficiary=made.body
        _charge=float(waiting.charge)
        _charge_serial=int(waiting.charge_serial)
        power_target.set_meta("charge",_charge)
        _wait_support_history=float(waiting.support_observed_seconds)
        _support_stable=0.0 # Historical contacts are not new-space evidence.
    elif completed.is_empty():
        beneficiary = Flight.new()
        beneficiary.name = "BeneficiaryInspectionTR01"
        beneficiary.configure(Catalog.resolve_build(Catalog.default_build("tr01")))
        beneficiary.max_altitude = 18.0
        add_child(beneficiary)
        # Sole initialization placement, not a continuation/restore operation.
        beneficiary.global_position = Vector3(6.6,.58,6)
        beneficiary.collision_mask |= 2
        beneficiary.safe_position = beneficiary.global_position
        beneficiary.hold_height = beneficiary.global_position.y
        beneficiary.environment_query = _environment
        beneficiary.environment_hazards_authoritative = true
        beneficiary.environment_sample = _environment.call(beneficiary.global_position)
    else:
        var made: Dictionary = FlightState.create(self,completed.checkpoint.beneficiary,History.BENEFICIARY_ID,47,_environment)
        if not made.ok: return made
        beneficiary = made.body
        _restored_history = completed.history.duplicate(true)
        _charge = float(completed.checkpoint.workbench_charge)
        _charge_serial = int(completed.checkpoint.workbench_charge_serial)
        power_target.set_meta("charge",_charge)
        _committed = true
        _receipt_count = 1 # Historical count, not an emitted completion event.
        _scan_distance = float(_restored_history.first_work.scan_distance_m)
        _terminal_pilot = Pilot.new()
        if not _terminal_pilot.bind(beneficiary) or not _terminal_pilot.probe(Vector3.ZERO).clear or not _terminal_pilot.go_to(Departure.ROUTE[-1],1): return {"ok":false,"code":"restored_terminal_obstructed"}
    _beneficiary_ref = weakref(beneficiary)
    _beneficiary_geometry = _shape_identity(beneficiary,false)
    _health = beneficiary.health
    _collision_count = beneficiary.collision_count
    if completed.is_empty() and waiting.is_empty(): _rest()
    elif waiting.is_empty(): _brake_beneficiary()
    _configured = true
    _authority = true
    _phase = "waiting" if completed.is_empty() else "restored_settling"
    _code = "configured_physical_candidate" if completed.is_empty() else "restored_history_no_new_receipt"
    if not scanning.is_empty():
        _action=scanning.action.duplicate(true)
        for key: String in ["serial","job"]: _action[key]=int(_action[key])
        _work_cargo=_cargos[str(_action.cassette_id)]
        _bound_pose=FlightState.transform(scanning.bound_pose)
        _pose_bound=true
        _stage=int(scanning.stage)
        _scan_distance=float(scanning.scan_distance_m)
        _health=float(scanning.health_baseline)
        _collision_count=int(scanning.collision_baseline)
        _scan_sources=scanning.measurements.duplicate(true)
        _scan_restore_pending=true
        _set_tool(FlightState.vec(scanning.tool))
        _phase=STAGES[_stage]
        _code="scan_restored_pending_real_revalidation"
    if not progress.is_empty():
        _set_tool(FlightState.vec(progress.tool))
        if not ProgressState.apply(self,progress): return {"ok":false,"code":"progress_original_departure_restore"}
    return {"ok":true,"code":_code,"preflight":_preflight.duplicate(true)}

func targets() -> Array:
    if not _configured or not is_instance_valid(power_target): return []
    return [{"id":POWER_ID,"body":power_target,"position":power_target.global_position,"tags":["charge"],"charge":_charge,"powered":_charge >= 20.0}]

func can_charge(delta: float, serial: int, authority: bool = true, paused: bool = false) -> Dictionary:
    if not _configured or not _authority or not authority: return {"ok":false,"code":"not_authority"}
    if _in_tick or _closed or paused or _phase == "fault": return {"ok":false,"code":"not_available"}
    if not _live(): return {"ok":false,"code":"registered_node_changed"}
    if not is_finite(delta) or absf(delta) > 35.0 or is_zero_approx(delta) or serial <= _charge_serial or serial > 2147483647: return {"ok":false,"code":"charge_bounds_or_replay"}
    return {"ok":true,"code":"accepted_host_ability_result"}

func apply_charge(delta: float, serial: int, authority: bool = true, paused: bool = false) -> Dictionary:
    var checked: Dictionary = can_charge(delta,serial,authority,paused)
    if not checked.ok: return checked
    _charge = clampf(_charge+delta,0,100)
    _charge_serial = serial
    power_target.set_meta("charge",_charge)
    return {"ok":true,"code":"charge_changed","charge":_charge,"powered":_charge >= 20}

func advance(delta: float, authority: bool = true, paused: bool = false) -> Dictionary:
    if not _configured or not _authority or not authority: return _reply(false,"not_authority")
    if _in_tick: return _reply(false,"reentrant_tick")
    if _closed: return _reply(false,"closed")
    if not is_finite(delta) or delta < 0 or delta > minf(.1,1.0/Engine.physics_ticks_per_second+.000001): return _reply(false,"invalid_delta")
    if paused or delta == 0:
        _support_stable = 0
        if _terminal_pilot != null:
            _terminal_pilot.settled_seconds = 0.0
            _terminal_pilot.clear_seconds = 0.0
        if _departure != null: _departure.tick(0,true,true)
        elif _committed: _brake_beneficiary()
        else: _rest()
        return _reply(true,"paused_not_physics_frozen")
    if _last_frame == Engine.get_physics_frames(): return _reply(false,"same_physics_frame")
    if _last_frame >= 0 and Engine.get_physics_frames() > _last_frame+1: _support_stable = 0
    _last_frame = Engine.get_physics_frames()
    _in_tick = true
    if _scan_restore_pending:
        _revalidate_scan(delta)
        # Generic progress has already adopted frozen bodies. Only this
        # pre-receipt endpoint phase resumes itself after fresh real support
        # and all three rays; old partial SCAN's explicit host gate is unchanged.
        if _phase=="commit" and _scan_ready_frame==Engine.get_physics_frames(): _scan_restore_pending=false
    else: _advance(delta)
    _in_tick = false
    return report()

func locks_cassette(id: String) -> bool:
    return not _committed and not _action.is_empty() and str(_action.cassette_id) == id

func close(authority: bool = true) -> Dictionary:
    if not _authority or not authority or _in_tick: return _reply(false,"not_authority_or_reentrant")
    _closed = true
    if _committed: _brake_beneficiary()
    else: _rest()
    return report()

func report() -> Dictionary:
    return {"ok":_configured and not _closed and _phase != "fault","phase":_phase,"code":_code,"charge":_charge,"charge_serial":_charge_serial,"powered":_charge >= 20,"action":_action.duplicate(true),"scan_distance_m":_scan_distance,"measurements":_measurements.duplicate(true),"tool_position":head.global_position if is_instance_valid(head) else Vector3.ZERO,"support_stable_seconds":_support_stable,"wait_support_history_seconds":_wait_support_history,"gate":_last_gate.duplicate(true),"motion":_last_motion.duplicate(true),"committed":_committed,"receipt_count":_receipt_count,"receipt":_receipt.duplicate(true),"departure":_departure_report.duplicate(true),"closed":_closed,"physical_restore_not_implemented":_restored_history.is_empty() and _progress_history.is_empty(),"restored_history":(_restored_history if not _restored_history.is_empty() else _progress_history).duplicate(true),"scan_restore_pending":_scan_restore_pending,"scan_source_observations":_scan_sources.duplicate(true),"scan_revalidated":_scan_revalidated}

func _advance(delta: float) -> void:
    if _phase == "fault": return
    if not _live():
        _fault("registered_node_changed_pending_preserved")
        return
    var environment: Variant = _environment.call(beneficiary.global_position)
    if not environment is Dictionary or not _live():
        _fault("environment_or_registered_node_lost")
        return
    beneficiary.environment_sample = environment
    if not beneficiary.enabled or beneficiary.freeze or beneficiary.health != _health or beneficiary.collision_count != _collision_count or beneficiary.water_contact:
        _fault("beneficiary_damaged_disabled_or_water")
        return
    if _committed:
        if not _restored_history.is_empty():
            var control: Dictionary = _terminal_pilot.tick(delta,true,false)
            var arrived: bool = control.get("arrived",false) and beneficiary.global_position.distance_to(Departure.ROUTE[-1]) < .18 and beneficiary.linear_velocity.length() < .18
            _departure_report = {"ok":true,"arrived":arrived,"phase":"arrived" if arrived else "restored_settling","route_index":Departure.ROUTE.size(),"code":"historical_departure_current_hold","controller":control,"historical":true}
            _phase = "departed" if arrived else "restored_settling"
            _code = "restored_result_kept"
            return
        if _departure == null:
            _departure = Departure.new()
            _departure_report = _departure.begin(beneficiary,rack,true)
            if not _departure_report.ok:
                _departure = null
                _code = "departure_wait:"+str(_departure_report.code)
                _rest()
                return
        _departure_report = _departure.tick(delta,true,false)
        _phase = "departed" if _departure_report.get("arrived",false) else "departing"
        _code = "service_kept:"+str(_departure_report.get("code",""))
        return
    _rest()
    var supported: Dictionary = Departure.support_proof(beneficiary,rack)
    if supported.get("supported",false): _support_stable += delta
    else: _support_stable = 0
    if _pose_bound and (beneficiary.global_position.distance_to(_bound_pose.origin) > .08 or beneficiary.global_basis.y.dot(_bound_pose.basis.y) < .985):
        _fault("beneficiary_moved_old_work_not_transferable")
        return
    var pending: Dictionary = _rules.snapshot().pending_action
    if _action.is_empty():
        if pending.get("kind","") != "work":
            _code = "waiting_for_real_work_proposal"
            return
        if _support_stable < .35:
            _code = "waiting_for_actual_support"
            return
        _action = pending.duplicate(true)
        _work_cargo = _cargos[str(_action.cassette_id)]
        _bound_pose = beneficiary.global_transform
        _pose_bound = true
        _stage = 0
        _phase = STAGES[_stage]
    if not _action_matches(pending):
        _fault("pending_identity_changed_completed_candidate_kept")
        return
    if _capture_requested_frame >= 0:
        _settle_scan_capture()
        return
    _last_gate = _gates(supported)
    if not _last_gate.ok:
        _code = str(_last_gate.code)
        return
    if _phase == "commit":
        if not _tools_synchronized():
            _code = "endpoint_physics_pending"
            return
        _commit()
        return
    var before: Vector3 = head.global_position
    var goal: Vector3 = ENDPOINTS[_stage]
    # Jolt applies an AnimatableBody target at the next physics step. Only
    # acknowledge an endpoint after the actual colliders reached that target.
    if before.distance_to(goal) <= .000001:
        if not _tools_synchronized():
            _code = "endpoint_physics_pending"
            return
        _last_motion = _sweep_tool(before,before)
        if not _last_motion.clear:
            _code = "tool_blocked"
            return
        if _stage in [0,1,2]:
            var endpoint: Dictionary = _scan_proof(before)
            if not endpoint.ok:
                _last_gate = endpoint
                _code = str(endpoint.code)
                return
            endpoint.stage = _stage
            endpoint.physics_frame = Engine.get_physics_frames()
            _measurements.append(endpoint)
        _stage += 1
        _phase = STAGES[_stage] if _stage < STAGES.size() else "commit"
        _code = "actual_endpoint_acknowledged"
        return
    var next: Vector3 = before.move_toward(goal,TOOL_SPEED*delta)
    _last_motion = _sweep_tool(before,next)
    if not _last_motion.clear:
        _code = "tool_blocked"
        return
    if _stage in [1,2]:
        var observation: Dictionary = _scan_proof(next)
        if not observation.ok:
            _last_gate = observation
            _code = str(observation.code)
            return
    _set_tool(next)
    if _stage in [1,2]: _scan_distance += before.distance_to(next)
    _code = "tool_moving"

func _gates(supported: Dictionary) -> Dictionary:
    if not supported.get("supported",false) or _support_stable < .35: return {"ok":false,"code":"beneficiary_support_unstable","support":supported}
    if _charge < 20.0: return {"ok":false,"code":"work_power_required"}
    var id: String = str(_action.cassette_id)
    var cargo: Variant = _work_cargo.get_ref() if _work_cargo != null else null
    if cargo == null or cargo != _cargos[id].get_ref(): return {"ok":false,"code":"work_cargo_identity_changed"}
    var state: Dictionary = _rules.snapshot()
    var physical: Dictionary = _custody.report()
    if physical.get("paused",false) or not physical.cargos.has(id) or physical.cargos[id].phase != "docked" or physical.cargos[id].berth != Rules.WORK or state.cassettes[id].holder != Rules.WORK:
        return {"ok":false,"code":"actual_work_cassette_required"}
    var support: Dictionary = _custody.support_info(id,Rules.WORK)
    if not support.get("supported",false): return {"ok":false,"code":"work_cassette_contact_required","support":support}
    var temperature: float = float(_rules.status().temperatures_c[id])
    if not is_finite(temperature) or temperature > 45.0: return {"ok":false,"code":"work_cassette_overheated","temperature_c":temperature}
    return {"ok":true,"code":"actual_work_gate","temperature_c":temperature,"support":support,"beneficiary_support":supported}

func _commit() -> void:
    if _committed: return
    if not _tools_synchronized() or head.global_position.distance_to(PARK) > .000001 or _measurements.size() != 3 or _scan_distance < 1.39999:
        _fault("actual_tool_endpoint_evidence_missing")
        return
    if not _all_custody_matches():
        _code = "receipt_custody_conflict"
        return
    var receipt: Dictionary = {}
    for key: String in MATCH_KEYS: receipt[key] = _action[key]
    receipt.merge({"path_clear":true,"endpoint_valid":true,"custody_verified":true,"completed":true})
    # These booleans are derived above from real, immutable identities, swept
    # endpoints, live support and actual Custody, never supplied by a caller.
    var result: Dictionary = _rules.confirm_action(receipt,true,false)
    if not result.ok:
        _code = "receipt_rejected:"+str(result.code)
        return
    _receipt = {"receipt":receipt,"physics_frame":Engine.get_physics_frames(),"gate":_last_gate.duplicate(true),"measurements":_measurements.duplicate(true),"beneficiary_pose":beneficiary.global_transform}
    if not _scan_sources.is_empty(): _receipt["source_observations"]=_scan_sources.duplicate(true)
    _receipt_count = 1
    _committed = true
    _phase = "departing"
    _code = "work_committed_once"

func _all_custody_matches() -> bool:
    var state: Dictionary = _rules.snapshot()
    var actual: Dictionary = _custody.report().cargos
    var carrier: Flight = _carrier.get_ref()
    for id: String in Rules.CASSETTES:
        var holder: String = str(state.cassettes[id].holder)
        if holder == Rules.CARRIER:
            if actual[id].phase != "carried" or actual[id].carrier != Rules.CARRIER or not carrier.cargo_items.has(id): return false
            var item: Dictionary = carrier.cargo_items[id]
            var joint: Variant = item.get("joint")
            if not joint is PinJoint3D or not is_instance_valid(joint) or joint.is_queued_for_deletion() or item.body != _cargos[id].get_ref() or joint.get_node_or_null(joint.node_a) != carrier or joint.get_node_or_null(joint.node_b) != item.body: return false
        elif holder in Rules.BERTHS:
            if actual[id].phase != "docked" or actual[id].berth != holder or not _custody.support_info(id,holder).get("supported",false): return false
        else: return false
    return true

func _scan_proof(at: Vector3) -> Dictionary:
    # Read actual collision shape, never the visual model or catalog dimensions.
    var actual: Dictionary = Dock._bounds(beneficiary)
    if not actual.ok: return {"ok":false,"code":"unsupported_beneficiary_collider"}
    var bounds: AABB = actual.bounds
    var bottom := at-Vector3.UP*TOOL_SIZE.y*.5
    var gap: float = bottom.y-bounds.end.y
    if gap < .04 or gap > .18 or at.x < bounds.position.x or at.x > bounds.end.x or at.z < bounds.position.z or at.z > bounds.end.z: return {"ok":false,"code":"actual_probe_gap_or_footprint","gap_m":gap,"bounds":bounds}
    var query := PhysicsRayQueryParameters3D.create(bottom+Vector3.DOWN*.001,bottom+Vector3.DOWN*.25,MASK,_moving_rids())
    var hit: Dictionary = get_world_3d().direct_space_state.intersect_ray(query)
    if hit.get("collider") != beneficiary: return {"ok":false,"code":"probe_first_hit_not_beneficiary","hit":_hit_name(hit)}
    var real_gap: float = bottom.distance_to(hit.position)
    return {"ok":real_gap >= .04 and real_gap <= .18,"code":"actual_probe_measurement","tool":at,"hit_position":hit.position,"gap_m":real_gap,"bounds":bounds,"body_id":beneficiary.get_instance_id()}

func _sweep_tool(from: Vector3, to: Vector3) -> Dictionary:
    var before: Array[AABB] = _tool_boxes(from)
    var after: Array[AABB] = _tool_boxes(to)
    for i in before.size():
        # Head/neck translate. Telescoping arm changes length; query its whole
        # old/new union so no newly occupied segment is skipped.
        var result: Dictionary
        if i != 2: result = _query_box(before[i],after[i].get_center()-before[i].get_center(),_moving_rids())
        else: result = _query_box(before[i].merge(after[i]),Vector3.ZERO,_moving_rids())
        if not result.clear:
            result.part = str(_moving[i].name)
            return result
    return {"clear":true,"from":from,"to":to}

func _query_box(box: AABB, motion: Vector3, excluded: Array[RID]) -> Dictionary:
    var shape := BoxShape3D.new()
    shape.size = box.size
    var query := PhysicsShapeQueryParameters3D.new()
    query.shape = shape
    query.transform = Transform3D(Basis.IDENTITY,box.get_center())
    query.collision_mask = MASK
    query.exclude = excluded
    var space: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
    var overlaps: Array[Dictionary] = space.intersect_shape(query,1)
    if not overlaps.is_empty(): return {"clear":false,"reason":"initial_overlap","collider":_hit_name(overlaps[0]),"bounds":box}
    if motion.length_squared() > 0:
        query.motion = motion
        var fraction: PackedFloat32Array = space.cast_motion(query)
        if fraction.size() != 2 or fraction[0] < .999:
            return {"clear":false,"reason":"sweep","fraction":fraction,"bounds":box,"motion":motion}
    return {"clear":true}

func _set_tool(at: Vector3) -> void:
    _tool_position = at
    var boxes: Array[AABB] = _tool_boxes(at)
    for i in boxes.size():
        var part: AnimatableBody3D = _moving[i]
        (part.get_child(0).shape as BoxShape3D).size = boxes[i].size
        (part.get_child(1).mesh as BoxMesh).size = boxes[i].size
        part.global_position = boxes[i].get_center()
        # Submit only an already-swept target. Jolt applies kinematic targets
        # on its next step; immediate body_get_state is still the current pose.
        part.force_update_transform()
        PhysicsServer3D.body_set_state(part.get_rid(),PhysicsServer3D.BODY_STATE_TRANSFORM,part.global_transform)

static func _tool_boxes(at: Vector3) -> Array[AABB]:
    return [AABB(at-TOOL_SIZE*.5,TOOL_SIZE),AABB(Vector3(at.x-.02,.98,at.z-.02),Vector3(.04,.02,.04)),AABB(Vector3(at.x-.02,1.0,4.59),Vector3(.04,.04,maxf(.12,at.z-4.59+.06))),AABB(Vector3(at.x-.08,1.04,4.59),Vector3(.16,.025,.12))]

func _moving_rids() -> Array[RID]:
    var result: Array[RID] = []
    for part: AnimatableBody3D in _moving:
        if is_instance_valid(part): result.append(part.get_rid())
    return result

func _live() -> bool:
    if not is_inside_tree() or get_world_3d().space != _space or not global_transform.is_equal_approx(Transform3D.IDENTITY) or not _environment.is_valid(): return false
    if _beneficiary_ref == null or _beneficiary_ref.get_ref() != beneficiary or not _same_world(beneficiary) or _shape_identity(beneficiary,false) != _beneficiary_geometry: return false
    if _carrier == null or not _same_world(_carrier.get_ref()): return false
    for id: String in _cargos:
        if not _same_world(_cargos[id].get_ref()): return false
    for id: String in _berths:
        var berth: Variant = _berths[id].get_ref()
        if not _same_world(berth) or berth.global_transform != _berth_poses[id] or _shape_identity(berth) != _berth_geometry[id]: return false
    for part: StaticBody3D in _fixed:
        if not _same_world(part) or _shape_identity(part) != _fixed_geometry.get(part.get_instance_id()): return false
    if _moving.size() != 4: return false
    if not is_instance_valid(head) or not head.global_position.is_equal_approx(_tool_position): return false
    var boxes: Array[AABB] = _tool_boxes(head.global_position)
    for i in _moving.size():
        var part: AnimatableBody3D = _moving[i]
        if not _same_world(part) or part.collision_layer != 1 or part.collision_mask != MASK: return false
        var shape: Variant = part.get_child(0).shape
        if not shape is BoxShape3D or not part.global_basis.is_equal_approx(Basis.IDENTITY) or not part.global_position.is_equal_approx(boxes[i].get_center()) or not shape.size.is_equal_approx(boxes[i].size): return false
    return true

func _same_world(value: Variant) -> bool:
    return value is PhysicsBody3D and is_instance_valid(value) and value.is_inside_tree() and not value.is_queued_for_deletion() and value.get_world_3d().space == get_world_3d().space

func _action_matches(pending: Dictionary) -> bool:
    if pending.is_empty(): return false
    for key: String in MATCH_KEYS:
        if pending.get(key) != _action.get(key): return false
    return true

func _fault(code: String) -> void:
    _phase = "fault"
    _code = code
    if _committed: _brake_beneficiary()
    else: _rest()

func _rest() -> void:
    if not is_instance_valid(beneficiary) or not beneficiary.is_inside_tree(): return
    beneficiary.command = {"active":true,"mode":"manual_throttle","body_relative":false,"throttle":0.0,"planar":Vector3.ZERO,"vertical":0.0,"yaw":0.0,"pitch":0.0,"roll":0.0,"brake":false,"fire":false}

func _brake_beneficiary() -> void:
    if not is_instance_valid(beneficiary) or not beneficiary.is_inside_tree(): return
    beneficiary.hold_height = beneficiary.global_position.y
    beneficiary.command = {"active":true,"mode":"assisted","body_relative":false,"planar":Vector3.ZERO,"vertical":0.0,"yaw":0.0,"brake":true,"fire":false}

func _reply(ok: bool, code: String) -> Dictionary:
    var result: Dictionary = report()
    result.ok = ok
    result.code = code
    return result

static func fixed_definition() -> Array[Dictionary]:
    var rows: Array[Dictionary] = [
        {"id":"RepairRack","center":Vector3(6.6,.16,6),"size":Vector3(2.4,.32,2.4),"color":Color("60777a")},
        {"id":"ToolRail","center":Vector3(6.6,1.11,4.65),"size":Vector3(1.4,.08,.14),"color":Color("52656b")},
        {"id":"PowerContact","center":Vector3(5.1,1.05,5.4),"size":Vector3(.32,.5,.22),"color":Color("e0b44a")},
        {"id":"PowerPost","center":Vector3(5.1,.44,5.4),"size":Vector3(.12,.72,.12),"color":Color("52656b")},
        {"id":"PowerFoot","center":Vector3(5.1,.04,5.4),"size":Vector3(.3,.08,.3),"color":Color("52656b")},
    ]
    for i in 2:
        var x: float = 5.95 if i == 0 else 7.25
        rows.append({"id":"ToolLeg"+str(i),"center":Vector3(x,.575,4.65),"size":Vector3(.08,.99,.08),"color":Color("52656b")})
        rows.append({"id":"ToolFoot"+str(i),"center":Vector3(x,.04,4.65),"size":Vector3(.24,.08,.24),"color":Color("52656b")})
    # Closed thermal-contact equipment representation, NOT a new water-network edge.
    for i in 2:
        var z: float = 4.75+float(i)*.10
        rows.append({"id":"ThermalReturn"+str(i),"center":Vector3(9.2,.12,z),"size":Vector3(2.8,.06,.06),"color":Color("6d9495")})
        rows.append({"id":"WorkContact"+str(i),"center":Vector3(10.55+float(i)*.10,.12,(z+5.0)*.5),"size":Vector3(.06,.06,5.0-z),"color":Color("6d9495")})
    return rows

func _fixed_box(id: String, at: Vector3, size: Vector3, color: Color) -> StaticBody3D:
    var part := StaticBody3D.new()
    part.name = id
    part.collision_layer = 1
    part.collision_mask = 0
    var collision := CollisionShape3D.new()
    var shape := BoxShape3D.new()
    shape.size = size
    collision.shape = shape
    part.add_child(collision)
    var mesh := MeshInstance3D.new()
    var box := BoxMesh.new()
    box.size = size
    mesh.mesh = box
    mesh.material_override = _material(color)
    part.add_child(mesh)
    add_child(part)
    part.global_position = at
    return part

static func _shape_identity(part: PhysicsBody3D, include_pose: bool = true) -> Dictionary:
    var shapes: Array = []
    for owner: int in part.get_shape_owners():
        for index in part.shape_owner_get_shape_count(owner):
            var shape: Shape3D = part.shape_owner_get_shape(owner,index)
            if not shape is BoxShape3D: return {}
            shapes.append({"size":shape.size,"pose":part.shape_owner_get_transform(owner),"disabled":part.is_shape_owner_disabled(owner)})
    return {"shape":shapes,"pose":part.global_transform if include_pose else Transform3D.IDENTITY,"layer":part.collision_layer,"mask":part.collision_mask}

static func _material(color: Color) -> StandardMaterial3D:
    var material := StandardMaterial3D.new()
    material.albedo_color = color
    material.roughness = .75
    return material

static func _hit_name(hit: Dictionary) -> String:
    var collider: Variant = hit.get("collider")
    return str(collider.get_path()) if collider is Node and is_instance_valid(collider) else str(collider)

## Un-ordered WAIT only. Not a scanning/departure restore and never a receipt.
func snapshot_wait() -> Dictionary:
    if not _configured or _closed or not _authority or not _live() or _phase!="waiting" or _committed or _receipt_count!=0 or not _action.is_empty() or _pose_bound or _stage!=0 or not head.global_position.is_equal_approx(PARK): return {}
    if not Departure.support_proof(beneficiary,rack).get("supported",false): return {}
    var row: Dictionary={"version":1,"charge":_charge,"charge_serial":_charge_serial,"beneficiary":FlightState.capture_wait(beneficiary,History.BENEFICIARY_ID),"support_observed_seconds":_support_stable}
    return row if validate_wait(row).ok else {}

static func validate_wait(saved: Variant) -> Dictionary:
    if not FlightState.exact(saved,["version","charge","charge_serial","beneficiary","support_observed_seconds"]) or saved.version!=1 or not FlightState.number(saved.charge,0,100) or not FlightState.integer(saved.charge_serial,0,2147483647) or not FlightState.number(saved.support_observed_seconds,.35,1.0e9): return {"ok":false,"code":"wait_workbench_schema"}
    if saved.charge_serial==0 and saved.charge!=0.0: return {"ok":false,"code":"wait_workbench_power_history"}
    if not FlightState.validate_wait(saved.beneficiary,History.BENEFICIARY_ID): return {"ok":false,"code":"wait_beneficiary_state"}
    var position: Vector3=FlightState.transform(saved.beneficiary.pose).origin
    if Vector2(position.x-6.6,position.z-6).length()>.3 or position.y<.45 or position.y>.65: return {"ok":false,"code":"wait_beneficiary_left_rack"}
    return {"ok":true,"code":"valid_wait_workbench"}

func configure_wait(context: Dictionary, saved: Dictionary, authority: bool = true) -> Dictionary:
    var checked: Dictionary=validate_wait(saved)
    if not checked.ok: return checked
    return _configure(context,authority,{},saved)

## Same waiting hardware, but the original transport Rules action is already
## pending. This separate boundary does not weaken unordered WAIT loading.
func configure_progress_wait(context: Dictionary, saved: Dictionary, authority: bool=true) -> Dictionary:
    return _configure(context,authority,{},saved,{},true)

func configure_progress(context: Dictionary, saved: Dictionary, authority: bool=true) -> Dictionary:
    return _configure(context,authority,{},{},{},false,saved) if saved.get("version")==3 or saved.get("version")==4 else configure_progress_wait(context,saved,authority)

func snapshot_progress() -> Dictionary:
    var result: Dictionary=inspect_progress()
    return result.snapshot if result.ok else {}

func inspect_progress() -> Dictionary:
    if _phase=="commit": return ProgressState.inspect_commit(self)
    if _committed: return ProgressState.inspect(self)
    var saved: Dictionary=snapshot_wait_progress()
    return {"ok":true,"snapshot":saved} if not saved.is_empty() else {"ok":false,"code":"progress_waiting_workbench_unavailable"}

static func validate_progress(saved: Variant, rules: Dictionary) -> Dictionary:
    # Array.has/in uses Variant type identity: JSON numbers are float while
    # literal version lists are int. Numeric version dispatch must use ==.
    return ProgressState.validate(saved,rules,load("res://scripts/v3/candidates/canal_workbench/workbench.gd")) if saved is Dictionary and (saved.get("version")==3 or saved.get("version")==4) else validate_wait_progress(saved)

func snapshot_wait_progress() -> Dictionary:
    if not _configured or _closed or not _authority or not _live() or _phase!="waiting" or _committed or _receipt_count!=0 or not _action.is_empty() or _pose_bound or _stage!=0 or not head.global_position.is_equal_approx(PARK): return {}
    var row: Dictionary={"version":2,"charge":_charge,"charge_serial":_charge_serial,"beneficiary":FlightState.capture_progress(beneficiary,History.BENEFICIARY_ID),"support_observed_seconds":_support_stable}
    return row if validate_wait_progress(row).ok else {}

static func validate_wait_progress(saved: Variant) -> Dictionary:
    if saved is Dictionary and saved.get("version")==1: return validate_wait(saved)
    if not FlightState.exact(saved,["version","charge","charge_serial","beneficiary","support_observed_seconds"]) or saved.version!=2 or not FlightState.number(saved.charge,0,100) or not FlightState.integer(saved.charge_serial,0,2147483647) or not FlightState.number(saved.support_observed_seconds,0,1e9) or not FlightState.validate_progress(saved.beneficiary,History.BENEFICIARY_ID): return {"ok":false,"code":"progress_waiting_workbench_schema"}
    if saved.charge_serial==0 and saved.charge!=0.0: return {"ok":false,"code":"progress_waiting_power_history"}
    var position: Vector3=FlightState.transform(saved.beneficiary.pose).origin
    if Vector2(position.x-6.6,position.z-6).length()>.3 or position.y<.4 or position.y>.7: return {"ok":false,"code":"progress_waiting_beneficiary_left_rack"}
    return {"ok":true,"code":"valid_progress_waiting_no_current_contact_claim"}


## Separate scan schema: never accepted by unordered WAIT/completed validators.
## Explicit host handshake, never invoked by capture. Keep the already swept
## target and let actual physics finish it. Do not stop the rest of the site.
func prepare_scan_capture(authority: bool=true) -> Dictionary:
    if not authority or not _authority or not _configured or _closed or _in_tick or not _live() or _scan_restore_pending or _committed or not _pose_bound or _stage not in [0,1,2,3] or _phase!=STAGES[_stage] or not _action_matches(_rules.snapshot().pending_action): return {"ok":false,"code":"scan_capture_not_available","ready":false}
    if _capture_requested_frame < 0:
        _capture_requested_frame=Engine.get_physics_frames()
        _capture_ready_frame=-1
        _capture_expired=false
    return scan_capture_status()

func release_scan_capture(authority: bool=true) -> Dictionary:
    if not authority or not _authority or _in_tick: return {"ok":false,"code":"not_authority_or_reentrant"}
    _capture_requested_frame=-1
    _capture_ready_frame=-1
    _capture_expired=false
    # No pose, progress, ledger or report-code writes; paused integrity is kept.
    return {"ok":true,"code":"scan_capture_released"}

func scan_capture_status() -> Dictionary:
    var ready: bool=_capture_requested_frame>=0 and not _capture_expired and _phase in STAGES and _live() and _capture_ready_frame==Engine.get_physics_frames() and _tools_synchronized() and _scan_physical_support()
    return {"ok":_capture_requested_frame>=0 and not _capture_expired,"code":"scan_capture_timeout" if _capture_expired else ("scan_capture_ready" if ready else "scan_capture_settling"),"ready":ready,"requested_frame":_capture_requested_frame,"ready_frame":_capture_ready_frame,"timeout_frames":CAPTURE_SETTLE_FRAMES}

func _settle_scan_capture() -> void:
    _capture_ready_frame=-1
    if _capture_expired:
        _code="scan_capture_timeout"
        return
    # Once settled, continued host ticks revalidate without advancing the tool.
    # A caller must release on both successful and failed Store publication.
    if _tools_synchronized() and _scan_physical_support() and _sweep_tool(head.global_position,head.global_position).clear and (_stage not in [1,2] or _scan_proof(head.global_position).ok):
        _capture_ready_frame=Engine.get_physics_frames()
        _code="scan_capture_ready"
        return
    if Engine.get_physics_frames()-_capture_requested_frame>=CAPTURE_SETTLE_FRAMES:
        _capture_expired=true
        _code="scan_capture_timeout"
    else:
        _code="scan_capture_settling"

func _tools_synchronized() -> bool:
    if _moving.size()!=4: return false
    for part: AnimatableBody3D in _moving:
        if not is_instance_valid(part) or not part.is_inside_tree() or part.sync_to_physics or PhysicsServer3D.body_get_state(part.get_rid(),PhysicsServer3D.BODY_STATE_TRANSFORM)!=part.global_transform: return false
    return true

func tool_physics_readback() -> Dictionary:
    # Read only: preserve the actual pending kinematic pose, never resubmit it.
    var rows: Array=[]
    var synchronized: bool=_moving.size()==4
    for part: AnimatableBody3D in _moving:
        var row: Dictionary={"valid":is_instance_valid(part)}
        if not is_instance_valid(part):
            synchronized=false
            rows.append(row)
            continue
        row["name"]=str(part.name)
        row["inside_tree"]=part.is_inside_tree()
        row["sync_to_physics"]=part.sync_to_physics
        if not part.is_inside_tree():
            synchronized=false
            rows.append(row)
            continue
        var rid: RID=part.get_rid()
        var physical: Transform3D=PhysicsServer3D.body_get_state(rid,PhysicsServer3D.BODY_STATE_TRANSFORM)
        row["rid"]=str(rid)
        row["node_pose"]=FlightState.pose(part.global_transform)
        row["native_pose"]=FlightState.pose(physical)
        row["pose_exact"]=physical==part.global_transform
        row["position_error_m"]=physical.origin.distance_to(part.global_position)
        row["native_mode"]=PhysicsServer3D.body_get_mode(rid)
        row["native_shape_count"]=PhysicsServer3D.body_get_shape_count(rid)
        var shape_node: CollisionShape3D=part.get_child(0) as CollisionShape3D
        if is_instance_valid(shape_node) and shape_node.shape is BoxShape3D:
            row["node_shape_rid"]=str(shape_node.shape.get_rid())
            row["node_shape_size"]=FlightState.xyz((shape_node.shape as BoxShape3D).size)
            row["node_shape_local_pose"]=FlightState.pose(shape_node.transform)
            row["node_shape_disabled"]=shape_node.disabled
        if int(row.native_shape_count)==1:
            var shape_rid: RID=PhysicsServer3D.body_get_shape(rid,0)
            var data: Variant=PhysicsServer3D.shape_get_data(shape_rid)
            row["native_shape_rid"]=str(shape_rid)
            row["native_shape_data"]=FlightState.xyz(data) if data is Vector3 else str(data)
            row["native_shape_local_pose"]=FlightState.pose(PhysicsServer3D.body_get_shape_transform(rid,0))
        synchronized=synchronized and not part.sync_to_physics and bool(row.pose_exact)
        rows.append(row)
    return {"physics_frame":Engine.get_physics_frames(),"synchronized":synchronized,"tool_position":FlightState.xyz(_tool_position),"tools":rows}

func snapshot_scan() -> Dictionary:
    var captured: Dictionary=inspect_scan_snapshot()
    return captured.snapshot if captured.ok else {}

func inspect_scan_snapshot() -> Dictionary:
    if not _configured or _closed or not _authority or not _live() or _scan_restore_pending or _committed or _receipt_count!=0 or not _pose_bound or _stage not in [0,1,2,3] or _phase!=STAGES[_stage] or _last_frame!=Engine.get_physics_frames(): return {"ok":false,"code":"scan_capture_phase_or_identity"}
    if not scan_capture_status().ready: return {"ok":false,"code":"scan_capture_barrier_required","barrier":scan_capture_status()}
    if not _action_matches(_rules.snapshot().pending_action) or not _scan_physical_support(): return {"ok":false,"code":"scan_capture_action_or_support"}
    var samples: Array=[]
    for i in _measurements.size():
        var sample: Dictionary=_scan_measurement(_measurements[i])
        if sample.is_empty(): return {"ok":false,"code":"scan_capture_measurement"}
        sample["source_observation"]=_scan_sources[i].get("source_observation",{}).duplicate(true) if i<_scan_sources.size() else {}
        if i<_scan_sources.size() and sample.source_observation.is_empty():
            sample.source_observation=_scan_sources[i].duplicate(true)
            sample.source_observation.erase("source_observation")
        samples.append(sample)
    var tools: Array=[]
    for part: AnimatableBody3D in _moving:
        if PhysicsServer3D.body_get_state(part.get_rid(),PhysicsServer3D.BODY_STATE_TRANSFORM)!=part.global_transform: return {"ok":false,"code":"scan_capture_tool_physics_transform","part":str(part.name),"node":FlightState.pose(part.global_transform),"physics":FlightState.pose(PhysicsServer3D.body_get_state(part.get_rid(),PhysicsServer3D.BODY_STATE_TRANSFORM))}
        tools.append({"pose":FlightState.pose(part.global_transform),"size":FlightState.xyz((part.get_child(0).shape as BoxShape3D).size)})
    var saved: Dictionary={"version":1,"charge":_charge,"charge_serial":_charge_serial,"beneficiary":FlightState.capture_wait(beneficiary,History.BENEFICIARY_ID),"support_observed_seconds":_support_stable,"source_frame":Engine.get_physics_frames(),"action":_action.duplicate(true),"stage":_stage,"tool":FlightState.xyz(head.global_position),"tools":tools,"scan_distance_m":_scan_distance,"bound_pose":FlightState.pose(_bound_pose),"health_baseline":_health,"collision_baseline":_collision_count,"measurements":samples}
    var checked: Dictionary=validate_scan(saved)
    if not checked.ok: return {"ok":false,"code":checked.code,"candidate":saved}
    return {"ok":true,"code":"captured_partial_scan_tool","snapshot":saved}

static func _scan_measurement(measured: Dictionary) -> Dictionary:
    if not measured.get("ok",false) or not measured.get("bounds") is AABB: return {}
    var bounds: AABB=measured.bounds
    return {"stage":measured.stage,"frame":measured.physics_frame,"tool":FlightState.xyz(measured.tool),"hit":FlightState.xyz(measured.hit_position),"gap_m":measured.gap_m,"bounds_position":FlightState.xyz(bounds.position),"bounds_size":FlightState.xyz(bounds.size)}

static func _valid_scan_measurement(row: Variant, index: int, bound: Transform3D, max_frame: int) -> bool:
    if not FlightState.exact(row,["stage","frame","tool","hit","gap_m","bounds_position","bounds_size"]) or not FlightState.integer(row.stage,index,index) or not FlightState.integer(row.frame,1,max_frame) or not FlightState.vector_valid(row.tool,1000) or not FlightState.vector_valid(row.hit,1000) or not FlightState.number(row.gap_m,.04,.18) or not FlightState.vector_valid(row.bounds_position,1000) or not FlightState.vector_valid(row.bounds_size,3): return false
    var tool: Vector3=FlightState.vec(row.tool)
    var hit: Vector3=FlightState.vec(row.hit)
    var bounds:=AABB(FlightState.vec(row.bounds_position),FlightState.vec(row.bounds_size))
    var original: AABB=bound*AABB(Vector3(-.7,-.24,-.7),Vector3(1.4,.48,1.4))
    return bounds.size.x>0 and bounds.size.y>0 and bounds.size.z>0 and bounds.get_center().distance_to(original.get_center())<=.16 and tool.distance_to(ENDPOINTS[index])<=.00001 and Vector2(hit.x-tool.x,hit.z-tool.z).length()<=.00001 and hit.x>=bounds.position.x and hit.x<=bounds.end.x and hit.z>=bounds.position.z and hit.z<=bounds.end.z and absf(hit.y-bounds.end.y)<=.00001 and absf(tool.y-TOOL_SIZE.y*.5-hit.y-float(row.gap_m))<=.00001

static func validate_scan(saved: Variant) -> Dictionary:
    if not FlightState.exact(saved,["version","charge","charge_serial","beneficiary","support_observed_seconds","source_frame","action","stage","tool","tools","scan_distance_m","bound_pose","health_baseline","collision_baseline","measurements"]): return {"ok":false,"code":"scan_workbench_keys"}
    var wait: Dictionary={"version":saved.version,"charge":saved.charge,"charge_serial":saved.charge_serial,"beneficiary":saved.beneficiary,"support_observed_seconds":saved.support_observed_seconds}
    if not validate_wait(wait).ok or not FlightState.integer(saved.source_frame,1,9007199254740991) or not FlightState.integer(saved.stage,0,3) or not FlightState.pose_valid(saved.bound_pose) or not FlightState.vector_valid(saved.tool,1000) or not FlightState.number(saved.scan_distance_m,0,1.40001) or not FlightState.number(saved.health_baseline,.00001,100) or not FlightState.integer(saved.collision_baseline,0,2147483647): return {"ok":false,"code":"scan_workbench_state"}
    var action: Variant=saved.action
    if not FlightState.exact(action,Rules.ACTION_KEYS) or not action.blocked is bool or not FlightState.integer(action.serial,1,9007199254740991) or action.kind!="work" or action.actor!="workbench" or action.cassette_id not in Rules.CASSETTES or action.source!=Rules.WORK or action.destination!=Rules.WORK or action.route!="stationary" or not FlightState.integer(action.job,1,1): return {"ok":false,"code":"scan_work_action"}
    if saved.beneficiary.health!=saved.health_baseline or saved.beneficiary.wait.collision_count!=saved.collision_baseline: return {"ok":false,"code":"scan_beneficiary_baseline"}
    var bound: Transform3D=FlightState.transform(saved.bound_pose)
    var actual: Transform3D=FlightState.transform(saved.beneficiary.pose)
    if bound.origin.distance_to(Vector3(6.6,.56,6))>.08 or bound.basis.y.dot(Vector3.UP)<.985 or actual.origin.distance_to(bound.origin)>.08 or actual.basis.y.dot(bound.basis.y)<.985: return {"ok":false,"code":"scan_bound_beneficiary"}
    var stage: int=int(saved.stage)
    var start: Vector3=PARK if stage==0 else ENDPOINTS[stage-1]
    var goal: Vector3=ENDPOINTS[stage]
    var at: Vector3=FlightState.vec(saved.tool)
    var along: float=(at-start).dot((goal-start).normalized())
    if along<-.000001 or along>start.distance_to(goal)+.000001 or (at-(start+(goal-start).normalized()*along)).length()>.000001: return {"ok":false,"code":"scan_tool_off_segment"}
    var distance: float=0.0 if stage==0 else (along if stage==1 else (.7+along if stage==2 else 1.4))
    if absf(float(saved.scan_distance_m)-distance)>.00001: return {"ok":false,"code":"scan_distance_stage_mismatch"}
    if not saved.tools is Array or saved.tools.size()!=4: return {"ok":false,"code":"scan_tool_registry"}
    var boxes: Array[AABB]=_tool_boxes(at)
    for i in 4:
        var row: Variant=saved.tools[i]
        if not FlightState.exact(row,["pose","size"]) or not FlightState.pose_valid(row.pose) or not FlightState.vector_valid(row.size,10) or FlightState.transform(row.pose)!=Transform3D(Basis.IDENTITY,boxes[i].get_center()) or FlightState.vec(row.size)!=boxes[i].size: return {"ok":false,"code":"scan_tool_pose_or_shape"}
    if not saved.measurements is Array or saved.measurements.size()!=stage: return {"ok":false,"code":"scan_partial_endpoint_count"}
    var previous: int=0
    for i in stage:
        var row: Variant=saved.measurements[i]
        if not FlightState.exact(row,["stage","frame","tool","hit","gap_m","bounds_position","bounds_size","source_observation"]): return {"ok":false,"code":"scan_measurement_keys"}
        var current: Dictionary=row.duplicate(true)
        current.erase("source_observation")
        if not _valid_scan_measurement(current,i,bound,int(saved.source_frame)) or int(row.frame)<=previous or not row.source_observation is Dictionary: return {"ok":false,"code":"scan_measurement_values"}
        if not row.source_observation.is_empty() and not _valid_scan_measurement(row.source_observation,i,bound,9007199254740991): return {"ok":false,"code":"scan_source_observation"}
        previous=int(row.frame)
    return {"ok":true,"code":"valid_partial_scan_no_live_contact_claim"}

func configure_scan(context: Dictionary, saved: Dictionary, authority: bool=true) -> Dictionary:
    var checked: Dictionary=validate_scan(saved)
    if not checked.ok: return checked
    return _configure(context,authority,{},{},saved)

func _revalidate_scan(delta: float) -> void:
    _scan_ready_frame=-1
    if not _live() or not _action_matches(_rules.snapshot().pending_action): _fault("scan_restore_identity_changed"); return
    beneficiary.environment_sample=_environment.call(beneficiary.global_position)
    _rest()
    if beneficiary.freeze or not beneficiary.enabled or beneficiary.health!=_health or beneficiary.collision_count!=_collision_count or beneficiary.water_contact or beneficiary.global_position.distance_to(_bound_pose.origin)>.08 or beneficiary.global_basis.y.dot(_bound_pose.basis.y)<.985: _fault("scan_restore_beneficiary_changed"); return
    var supported: Dictionary=Departure.support_proof(beneficiary,rack)
    _support_stable=_support_stable+delta if supported.get("supported",false) else 0.0
    _last_gate={"ok":_scan_physical_support(),"code":"scan_actual_support_revalidation"}
    if not _last_gate.ok: _code="scan_revalidate_support_pending"; return
    if not _tools_synchronized(): _code="scan_revalidate_physics_pending"; return
    _last_motion=_sweep_tool(head.global_position,head.global_position)
    if not _last_motion.clear: _code="scan_revalidate_tool_obstructed"; return
    if _stage in [1,2] and not _scan_proof(head.global_position).ok: _code="scan_revalidate_current_ray"; return
    if _scan_revalidated<_scan_sources.size():
        # Real new-space ray, no tool motion or extra scan-distance credit.
        var observation: Dictionary=_scan_proof(ENDPOINTS[_scan_revalidated])
        if not observation.ok: _code="scan_revalidate_endpoint_ray"; return
        observation["stage"]=_scan_revalidated
        observation["physics_frame"]=Engine.get_physics_frames()
        _measurements.append(observation)
        _scan_revalidated+=1
    if _scan_revalidated==_scan_sources.size(): _scan_ready_frame=Engine.get_physics_frames()
    _code="scan_actual_support_rays_ready" if _scan_ready_frame>=0 else "scan_endpoint_revalidation_pending"

func scan_restore_ready() -> bool:
    return _scan_restore_pending and _scan_ready_frame==Engine.get_physics_frames() and _phase in STAGES and _live() and _tools_synchronized() and _action_matches(_rules.snapshot().pending_action) and _scan_physical_support() and _sweep_tool(head.global_position,head.global_position).clear

func resume_scan(authority: bool=true) -> Dictionary:
    if not authority or not _authority or _in_tick or not scan_restore_ready(): return {"ok":false,"code":"current_scan_ready_required"}
    _scan_restore_pending=false
    return {"ok":true,"code":"same_scan_continues_no_receipt"}


func _scan_physical_support() -> bool:
    # Load may preserve a powerless/overheated stopped scan. Those operational
    # gates remain enforced by normal _advance, not by restoration readiness.
    if _support_stable<.35 or not Departure.support_proof(beneficiary,rack).get("supported",false) or not _all_custody_matches(): return false
    var id: String=str(_action.get("cassette_id",""))
    if not _cargos.has(id) or _work_cargo==null or _work_cargo.get_ref()!=_cargos[id].get_ref(): return false
    var state: Dictionary=_rules.snapshot()
    return state.cassettes[id].holder==Rules.WORK and _custody.support_info(id,Rules.WORK).get("supported",false)
