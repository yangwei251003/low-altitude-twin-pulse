extends RefCounted
## Host-internal candidate. One bounded state-machine dispatch per physics tick.
## Never writes a body pose/velocity, creates a timer, or confirms external work.
const Flight = preload("res://scripts/v2/flight_body.gd")
const Pilot = preload("res://scripts/v3/candidates/canal_transport_physics/transport_pilot.gd")
const Dock = preload("res://scripts/v3/candidates/canal_transport_physics/dock_lift.gd")
const Custody = preload("res://scripts/v3/candidates/canal_transport_physics/cargo_custody.gd")
const Rules = preload("res://scripts/v3/candidates/canal_service_loop/canal_service_runtime.gd")
const ScanState = preload("res://scripts/v3/candidates/canal_checkpoint/flight_state.gd")
const WAIT_POINT := Vector3(14.75,2.2,23)
const CENTRE_X := 14.75
const BERTH_POINTS := {"south_0":Vector3(7.7,0,21),"south_1":Vector3(7.7,0,24),
    "north_work":Vector3(10.6,0,6),"north_buffer":Vector3(10.6,5,8)}
const MATCH_KEYS := ["serial","kind","actor","cassette_id","source","destination","route","job"]
var _body: WeakRef
var _cargos: Dictionary = {}
var _berths: Dictionary = {}
var _berth_poses: Dictionary = {}
var _space := RID()
var _custody: RefCounted
var _rules: RefCounted
var _environment: Callable
var _pilot: RefCounted
var _dock: RefCounted
var _configured := false
var _authority := false
var _closed := false
var _in_tick := false
var _last_frame := -1
var _serial := 0
var _phase := "unconfigured"
var _code := "unconfigured"
var _action: Dictionary = {}
var _departure: Dictionary = {}
var _path: Array[Vector3] = []
var _path_index := 0
var _leg_started := false
var _path_complete := false
var _pickup_support: Dictionary = {}
var _release_y := 0.0
var _released := false
var _alignment_seconds := 0.0
var _blocked_tick := false
var _blocked_seconds := 0.0
var _active_ticks := 0
var _last_controller: Dictionary = {}
# A confirmed anchor is immutable during one external/idle wait. The original
# Pilot owns all movement, including recovery after pause or a blocked hold.
var _hold: Dictionary = {}
var _receipts: Array = []
var _receipt_count := 0
var _initial_health := 0.0
var _initial_collisions := 0
var _restored_hold_only := false
var _waiting_for_beneficiary := false
var _scan_restore_pending := false
var _progress_contact_history: Dictionary = {}
var _progress_contact_start := -1

func configure(carrier: Flight, cargos: Dictionary, berths: Dictionary, custody: RefCounted,
        rules: RefCounted, environment_query: Callable, authority: bool = true) -> Dictionary:
    return _configure(carrier,cargos,berths,custody,rules,environment_query,authority,false)

## New instance, already reconstructed real docked bodies. No transport receipts
## are replayed. Before external adoption this controller only maintains anchor.
func configure_restored(context: Dictionary, authority: bool = true) -> Dictionary:
    if not context.get("carrier") is Flight or not context.get("cargos") is Dictionary or not context.get("berths") is Dictionary or not context.get("custody") is RefCounted or not context.get("rules") is RefCounted or not context.get("environment_query") is Callable:
        return {"ok":false,"code":"restore_context"}
    return _configure(context.carrier,context.cargos,context.berths,context.custody,context.rules,context.environment_query,authority,true)

func resume_restored(authority: bool = true) -> Dictionary:
    if not _configured or not _authority or not authority or _closed or _in_tick or not _restored_hold_only: return _reply("restore_adoption_required",false)
    _restored_hold_only = false
    return _reply("restored_controller_adopted",true)

## The only existing beneficiary has already departed. A committed consumption
## does not authorize another work cycle. This entry never alters the Rules
## ledger or creates an aircraft; all subsequent holds use the original Pilot.
func wait_for_next_beneficiary(authority: bool = true) -> Dictionary:
    if not _configured or not _authority or not authority or _closed or _in_tick or _restored_hold_only:
        return _reply("active_adopted_host_required",false)
    if _last_frame != Engine.get_physics_frames() or not _live_registry():
        return _reply("current_host_sample_required",false)
    var state: Dictionary = _rules.snapshot()
    if not _consumed_first_work(state) or _phase != "idle" or not _action.is_empty() or not _departure.is_empty() or not _custody_matches(state):
        return _reply("consumed_first_work_safe_idle_required",false)
    var target: Vector3 = _anchor(str(state.carrier_anchor),2.2)
    if not _carrier().cargo_items.is_empty() or is_instance_valid(_carrier().cargo_joint) or _carrier().global_position.distance_to(target) >= .18 or _carrier().linear_velocity.length() >= .18 or _carrier().angular_velocity.length() > .15 or _hold.get("target") != target or not _hold.get("action",{}).is_empty() or not _last_controller.get("arrived",false) or float(_last_controller.get("settled_seconds",0)) < .35:
        return _reply("actual_empty_anchor_hold_required",false)
    _waiting_for_beneficiary = true
    _code = "awaiting_new_beneficiary"
    return report()

func _consumed_first_work(state: Dictionary) -> bool:
    return _rules.validate_snapshot(state).ok and int(state.jobs_completed) == 1 and int(state.services_consumed) == 1 and int(state.service_credit) == 0 and bool(state.job_requested) and state.pending_action.is_empty()

func _configure(carrier: Flight, cargos: Dictionary, berths: Dictionary, custody: RefCounted,
        rules: RefCounted, environment_query: Callable, authority: bool, restoring: bool) -> Dictionary:
    if _configured or _closed: return {"ok":false,"code":"already_bound_or_closed"}
    if not authority: return {"ok":false,"code":"authority_required"}
    if not is_instance_valid(carrier) or not carrier.is_inside_tree() or not carrier.enabled or carrier.freeze or carrier.stats.is_empty():
        return {"ok":false,"code":"live_carrier_required"}
    if not is_instance_valid(custody) or custody.get_script() != Custody or not is_instance_valid(rules) or rules.get_script() != Rules or not environment_query.is_valid():
        return {"ok":false,"code":"actual_dependencies_required"}
    if cargos.size() != 2 or berths.size() != 4: return {"ok":false,"code":"registry_bounds"}
    var actual_space: RID = carrier.get_world_3d().space
    var seen: Dictionary = {carrier.get_instance_id():true}
    for id: String in Rules.CASSETTES:
        var cargo: Variant = cargos.get(id)
        if not cargo is RigidBody3D or not is_instance_valid(cargo) or not cargo.is_inside_tree() or cargo.get_world_3d().space != actual_space or seen.has(cargo.get_instance_id()):
            return {"ok":false,"code":"cargo_identity_or_space"}
        if cargo is Flight or absf(cargo.mass-2.0) > .00001 or not cargo.contact_monitor: return {"ok":false,"code":"cargo_contract"}
        seen[cargo.get_instance_id()] = true
    for id: String in Rules.BERTHS:
        var berth: Variant = berths.get(id)
        if not berth is StaticBody3D or not is_instance_valid(berth) or not berth.is_inside_tree() or berth.get_world_3d().space != actual_space or seen.has(berth.get_instance_id()):
            return {"ok":false,"code":"berth_identity_or_space"}
        var shape: Dictionary = Dock._support(berth)
        if not shape.ok or berth.global_position.distance_to(BERTH_POINTS[id]) > .0001 or not shape.bounds.size.is_equal_approx(Vector3(2,.5,2)):
            return {"ok":false,"code":"tested_berth_geometry_required"}
        seen[berth.get_instance_id()] = true
    var initial: Dictionary = rules.snapshot()
    if restoring:
        if initial.is_empty() or not rules.validate_snapshot(initial).ok or int(initial.jobs_completed) != 1 or not initial.pending_action.is_empty() or not carrier.cargo_items.is_empty(): return {"ok":false,"code":"completed_empty_restore_required"}
        var anchor: String = str(initial.carrier_anchor)
        if anchor != Rules.WAIT and not BERTH_POINTS.has(anchor): return {"ok":false,"code":"restore_anchor"}
        var goal: Vector3 = WAIT_POINT if anchor == Rules.WAIT else BERTH_POINTS[anchor]+Vector3.UP*2.2
        if carrier.global_position.distance_to(goal) >= .18 or carrier.linear_velocity.length() >= .18: return {"ok":false,"code":"restore_actual_anchor"}
        for id: String in Rules.CASSETTES:
            if initial.cassettes[id].holder not in Rules.BERTHS: return {"ok":false,"code":"restore_docked_only"}
        if custody.docked_snapshot().is_empty(): return {"ok":false,"code":"restore_real_custody_required"}
    else:
        if initial.is_empty() or not initial.pending_action.is_empty() or initial.carrier_anchor != Rules.WAIT or carrier.global_position.distance_to(WAIT_POINT) >= .18:
            return {"ok":false,"code":"fresh_actual_wait_required"}
        if initial.cassettes[Rules.CASSETTES[0]].holder != Rules.CARRIER or initial.cassettes[Rules.CASSETTES[1]].holder != Rules.WORK:
            return {"ok":false,"code":"initial_holder_contract"}
    var status: Dictionary = custody.report()
    if not status.authority or status.paused: return {"ok":false,"code":"live_host_custody_required"}
    # Validate dependencies before accepting ownership of the controller.
    _body = weakref(carrier)
    _space = actual_space
    _custody = custody
    _rules = rules
    _environment = environment_query
    for id: String in cargos: _cargos[id] = weakref(cargos[id])
    for id: String in berths:
        _berths[id] = weakref(berths[id])
        _berth_poses[id] = berths[id].global_transform
    if not _custody_matches(initial):
        _body = null
        _cargos.clear()
        _berths.clear()
        _berth_poses.clear()
        _custody = null
        _rules = null
        return {"ok":false,"code":"actual_initial_custody_mismatch"}
    _pilot = Pilot.new()
    if not _pilot.bind(carrier): return {"ok":false,"code":"pilot_bind_failed"}
    if restoring and not _pilot.probe(Vector3.ZERO).clear: return {"ok":false,"code":"restore_anchor_obstructed"}
    _restored_hold_only = restoring
    _serial = int(status.last_serial)
    _initial_health = carrier.health
    _initial_collisions = carrier.collision_count
    _authority = true
    _configured = true
    _phase = "idle"
    _code = "restored_anchor_hold_only" if restoring else "configured"
    return {"ok":true,"code":_code}

func tick(delta: float, authority: bool = true, suspended: bool = false) -> Dictionary:
    if not _configured: return _reply("not_configured",false)
    if not _authority or not authority: return _reply("not_authority",false)
    if _in_tick: return _reply("reentrant_tick",false)
    if _closed: return _reply("closed",false)
    if not is_finite(delta) or delta < 0.0 or delta > minf(.1,1.0/float(Engine.physics_ticks_per_second)+.000001):
        return _reply("invalid_physics_delta",false)
    if suspended or delta == 0.0:
        _reset_stability()
        _brake()
        return _reply("suspended",true)
    if _last_frame == Engine.get_physics_frames(): return _reply("same_physics_frame",false)
    _in_tick = true
    if _last_frame >= 0 and Engine.get_physics_frames() > _last_frame+1: _reset_stability()
    _last_frame = Engine.get_physics_frames()
    _active_ticks += 1
    _blocked_tick = false
    _advance(delta)
    _blocked_seconds = _blocked_seconds+delta if _blocked_tick else 0.0
    _in_tick = false
    return report()

func close(authority: bool = true) -> Dictionary:
    if not _authority or not authority: return _reply("not_authority",false)
    if _in_tick: return _reply("reentrant_close",false)
    if not _closed:
        _brake()
        _closed = true
        _phase = "closed"
        _code = "closed_pending_preserved"
    return report()

func report() -> Dictionary:
    return {"ok":_configured and _phase != "fault" and not _closed,"code":_code,"phase":_phase,
        "action":_action.duplicate(true),"departure":_departure.duplicate(true),
        "path_index":_path_index,"path_size":_path.size(),"path_complete":_path_complete,
        "released":_released,"blocked_seconds":_blocked_seconds,"active_ticks":_active_ticks,
        "controller":_last_controller.duplicate(true),"hold":_hold.duplicate(true),"receipt_count":_receipt_count,
        "receipts":_receipts.duplicate(true),"closed":_closed,"physics_restore_required":true,
        "waiting_for_beneficiary":_waiting_for_beneficiary}

func _reply(code: String, ok: bool) -> Dictionary:
    var result: Dictionary = report()
    result.ok = ok
    result.code = code
    return result

func _advance(delta: float) -> void:
    if _phase == "fault":
        _brake()
        return
    if not _live_registry():
        _fault("registered_node_lost_or_changed")
        return
    var body: Flight = _carrier()
    if not body.enabled or body.health < _initial_health or body.collision_count != _initial_collisions or body.water_contact:
        _fault("carrier_damage_disabled_or_water")
        return
    var environment: Variant = _environment.call(body.global_position)
    if not environment is Dictionary or not _live_registry():
        _fault("environment_unavailable")
        return
    body.environment_sample = environment
    var sampled: Dictionary = _custody.step(delta,true,false)
    if not sampled.ok:
        _fault("custody_step:"+str(sampled.code))
        return
    if not _progress_contact_history.is_empty():
        if _progress_contact_start<0: _progress_contact_start=Engine.get_physics_frames()
        var actual: Dictionary=_custody.report().cargos
        for id: String in _progress_contact_history.keys():
            if actual[id].phase=="docked" and int(actual[id].stable_usec)>=Custody.STABLE_USEC and _custody.support_info(id,str(_progress_contact_history[id])).get("supported",false): _progress_contact_history.erase(id)
        if Engine.get_physics_frames()-_progress_contact_start>90:
            _fault("progress_current_support_not_revalidated")
            return
    if not _contacts_safe():
        _fault("unexpected_contact_or_custody_fault")
        return
    _code = "advancing"
    # Exactly one phase dispatch. No while/await and no timer-driven completion.
    match _phase:
        "idle", "awaiting_external": _request(delta)
        "travel": _travel(delta)
        "align": _align(delta)
        "pickup_prepare": _prepare_pickup(delta)
        "approach_wait":
            _brake()
            if _slow(): _begin_dock(true)
        "approach": _dock_tick(delta,true)
        "release_wait": _release()
        "fall": _fall()
        "commit": _commit_receipt()
        "departure_wait":
            _brake()
            if not _departure_valid(): _fault("departure_identity_changed")
            elif _slow(): _begin_dock(false)
        "departure":
            if not _departure_valid(): _fault("departure_identity_changed")
            else: _dock_tick(delta,false)
        _: _fault("invalid_executor_phase")

func _request(delta: float) -> void:
    var state: Dictionary = _rules.snapshot()
    if _scan_restore_pending:
        _code="scan_restore_adoption_required"
        _hold_position(delta,state,_action)
        return
    if _waiting_for_beneficiary:
        if not _consumed_first_work(state) or not _custody_matches(state):
            _fault("waiting_beneficiary_state_changed")
            return
        _code = "awaiting_new_beneficiary"
        _hold_position(delta,state,{})
        return
    if _restored_hold_only:
        if not state.pending_action.is_empty() or not _custody_matches(state):
            _fault("restore_hold_state_changed")
            return
        _code = "restored_anchor_hold_only"
        _hold_position(delta,state,{})
        return
    if not _custody_matches(state):
        _fault("rules_physics_holder_mismatch")
        return
    # Once a transport action is returned, retain that exact identity while
    # recovering a held anchor. Do not ask for another action/serial each frame.
    var requested: Dictionary
    if not _hold.is_empty() and _action.get("kind","") in ["move","pick","place"] and _action.get("route","") == "low" and _action.get("source","") != Rules.BUFFER and _action.get("destination","") != Rules.BUFFER:
        if not _action_matches():
            _block("pending_action_changed_during_anchor_handoff")
            return
        requested = {"ok":true,"action":_action.duplicate(true)}
    else:
        requested = _rules.request_action(int(state.revision),true,false)
    if not requested.ok:
        _block("request:"+str(requested.code))
        return
    if not requested.has("action"):
        _action.clear()
        _phase = "idle"
        _code = "waiting_for_work_order"
        _hold_position(delta,state,{})
        return
    _action = requested.action.duplicate(true)
    if _action.kind not in ["move","pick","place"] or _action.route != "low" or _action.source == Rules.BUFFER or _action.destination == Rules.BUFFER:
        _phase = "awaiting_external"
        _code = "awaiting_external:"+str(_action.kind)
        _hold_position(delta,state,_action)
        return
    if not _hold.is_empty() or _action.kind == "move":
        # A completed drop proves cargo support, not the carrier's horizontal
        # anchor. Dock/release braking can drift in wind. Every new route starts
        # with a live Pilot hold, including when no external-work hold existed.
        # Retain the pending action while recovering; do not emit a move receipt.
        var held_anchor: String = str(_hold.get("anchor",state.carrier_anchor))
        if str(state.carrier_anchor) != held_anchor or (_action.kind == "move" and str(_action.source) != held_anchor):
            _fault("held_anchor_changed_before_handoff")
            return
        _code = "waiting_anchor_handoff"
        var held_action: Dictionary = _hold.get("action",{}).duplicate(true)
        if not _hold_position(delta,state,held_action): return
    # The original physical source gate remains mandatory after a held recovery.
    if _action.kind == "move":
        var origin: Vector3 = _anchor(str(_action.source),2.2)
        var at: Vector3 = _carrier().global_position
        if Vector2(at.x-origin.x,at.z-origin.z).length() > .20:
            _fault("source_anchor_mismatch")
            return
    _hold.clear()
    _path_complete = false
    _released = false
    _pickup_support.clear()
    _last_controller.clear()
    match _action.kind:
        "move":
            _path = _route(_action)
            _path_index = 0
            _leg_started = false
            _phase = "travel"
        "pick":
            var id: String = str(_action.cassette_id)
            if not _docked(id,str(_action.source)):
                _block("pickup_alignment_precondition")
                return
            var hook_goal: Vector3=_cargo(id).global_position-Pilot.PICKUP_LOAD_OFFSET
            if _carrier().global_position.distance_to(hook_goal)>Pilot.PICKUP_MAX_ADJUSTMENT:
                # After stationary work the empty carrier is already at this
                # anchor's high hold. No inter-berth move exists to descend it.
                # Use the ordinary full swept Pilot before local hook alignment.
                if not _pilot.go_to(_anchor(str(_action.source),1.55),_next_serial()):
                    _block("pickup_source_approach_rejected")
                    return
                _phase="pickup_prepare"
                return
            if not _pilot.go_to_pickup_alignment(_cargo(id),_next_serial()):
                _block("pickup_alignment_precondition")
                return
            _alignment_seconds = 0.0
            _phase = "align"
        "place": _phase = "approach_wait"

func _hold_position(delta: float, state: Dictionary, external_action: Dictionary) -> bool:
    var anchor_id: String = str(state.carrier_anchor)
    if anchor_id != Rules.WAIT and not BERTH_POINTS.has(anchor_id):
        _fault("unknown_confirmed_hold_anchor")
        return false
    var identity: Dictionary = {}
    if not external_action.is_empty():
        for key: String in MATCH_KEYS: identity[key] = external_action[key]
    var target: Vector3 = _anchor(anchor_id,2.2)
    if _hold.is_empty() or _hold.anchor != anchor_id or _hold.action != identity:
        var controller_serial: int = _next_serial()
        if not _pilot.go_to(target,controller_serial):
            _fault("hold_anchor_rejected")
            return false
        _hold = {"anchor":anchor_id,"target":target,"action":identity,
            "controller_serial":controller_serial}
    if _pilot.serial != int(_hold.controller_serial) or _pilot.target != target:
        _fault("hold_controller_binding_changed")
        return false
    _last_controller = _pilot.tick(delta,true,false)
    if _last_controller.state == "blocked":
        _block("anchor_hold_blocked",false)
        return false
    if _last_controller.state not in ["traveling","arrived"]:
        _block("anchor_hold:"+str(_last_controller.state))
        return false
    # Even after arrival, the Pilot is ticked on every host frame. Its full live
    # carrier/load envelopes, inertia checks and swept climb remain in effect.
    return _last_controller.arrived and _carrier().global_position.distance_to(target) < .18 and _carrier().linear_velocity.length() < .18

func _travel(delta: float) -> void:
    if not _action_matches():
        _block("pending_action_changed")
        return
    if not _custody_matches(_rules.snapshot()):
        _fault("transport_custody_changed")
        return
    if not _leg_started:
        if not _pilot.go_to(_path[_path_index],_next_serial()):
            _fault("waypoint_rejected")
            return
        _leg_started = true
    _last_controller = _pilot.tick(delta,true,false)
    if _last_controller.state == "blocked":
        _block("route_blocked",false)
        return
    if not _last_controller.arrived: return
    var body: Flight = _carrier()
    if body.global_position.distance_to(_path[_path_index]) >= .18 or body.linear_velocity.length() >= .18:
        _fault("arrival_evidence_mismatch")
        return
    _path_index += 1
    _leg_started = false
    if _path_index == _path.size():
        _path_complete = true
        _phase = "commit"
        _brake()

func _prepare_pickup(delta: float) -> void:
    if not _action_matches(): _block("pickup_source_pending_changed"); return
    var id: String=str(_action.cassette_id)
    if not _docked(id,str(_action.source)):
        _block("pickup_source_contact_pending")
        return
    _last_controller=_pilot.tick(delta,true,false)
    if _last_controller.state=="blocked": _block("pickup_source_approach_blocked",false); return
    if not _last_controller.get("arrived",false): return
    if not _pilot.go_to_pickup_alignment(_cargo(id),_next_serial()):
        _block("pickup_local_alignment_rejected")
        return
    _alignment_seconds=0.0
    _phase="align"

func _align(delta: float) -> void:
    if not _action_matches():
        _block("pending_action_changed")
        return
    _last_controller = _pilot.tick(delta,true,false)
    if _last_controller.state == "blocked":
        _block("alignment_blocked",false)
        return
    _alignment_seconds += delta
    if _alignment_seconds > 10.0:
        _fault("alignment_active_deadline_pending_kept")
        return
    if not _last_controller.arrived: return
    var id: String = str(_action.cassette_id)
    var cargo: RigidBody3D = _cargo(id)
    var offset: Vector3 = cargo.global_position-(_carrier().global_position+Custody.LOAD_OFFSET)
    if offset.length() > Pilot.PICKUP_TOLERANCE or not _slow() or not _docked(id,str(_action.source)):
        _block("pickup_live_precondition")
        return
    _pickup_support = _custody.support_info(id,str(_action.source))
    var picked: Dictionary = _custody.pickup(id,Rules.CARRIER,_next_serial(),int(_custody.revision))
    if not picked.ok:
        _block("pickup:"+str(picked.code))
        return
    if not _joint(id):
        _fault("pickup_joint_missing")
        return
    _phase = "commit"
    _brake()

func _begin_dock(approach: bool) -> void:
    if approach and not _action_matches():
        _block("pending_action_changed")
        return
    var context: Dictionary = _action if approach else _departure
    var berth_id: String = str(context.destination if approach else context.source)
    _dock = Dock.new()
    var result: Dictionary = _dock.begin_approach(_carrier(),_berth(berth_id),_next_serial(),true) if approach else _dock.begin(_carrier(),_berth(berth_id),_next_serial(),true)
    if not result.ok:
        _block("dock_begin:"+str(result.code))
        return
    _phase = "approach" if approach else "departure"

func _dock_tick(delta: float, approach: bool) -> void:
    if approach and not _action_matches():
        _block("pending_action_changed")
        return
    _last_controller = _dock.tick(delta,true,false)
    if _last_controller.state == "blocked":
        _block("dock:"+str(_last_controller.code),false)
        return
    if approach and _last_controller.get("ready_for_release",false):
        _phase = "release_wait"
    elif not approach and _last_controller.get("clear",false):
        if not _joint(str(_departure.cassette_id)) or not _pilot.probe(Vector3.ZERO).clear:
            _block("ordinary_departure_envelope_not_clear")
            return
        _departure.clear()
        _phase = "idle"

func _release() -> void:
    _brake()
    if not _action_matches():
        _block("pending_action_changed")
        return
    if not _slow():
        _code = "waiting_release_velocity"
        return
    var id: String = str(_action.cassette_id)
    var destination: String = str(_action.destination)
    var proof: Dictionary = _custody.release_info(id,destination)
    _last_controller = proof.duplicate(true)
    if not proof.ok:
        _block("release:"+str(proof.code))
        return
    var load: RigidBody3D = _cargo(id)
    _release_y = load.global_position.y
    var joint_ref: WeakRef = weakref(_carrier().cargo_items[id].joint)
    var released: Dictionary = _custody.release_to(id,destination,_next_serial(),int(_custody.revision))
    if not released.ok:
        _block("release:"+str(released.code))
        return
    if joint_ref.get_ref() != null:
        _fault("released_joint_still_live")
        return
    _released = true
    _phase = "fall"

func _fall() -> void:
    _brake()
    # Do not restart a drop if another subsystem changed the reserved action.
    if not _action_matches():
        _block("pending_action_changed_after_release")
        return
    if _docked(str(_action.cassette_id),str(_action.destination)):
        _phase = "commit"

func _commit_receipt() -> void:
    _brake()
    if not _action_matches():
        _block("pending_action_changed_before_receipt")
        return
    var expected: Dictionary = _rules.snapshot()
    var physical: Dictionary = {"path_clear":false,"endpoint_valid":false,"custody_verified":false,"completed":false}
    var id: String = str(_action.cassette_id)
    match _action.kind:
        "move":
            physical.path_clear = _path_complete
            physical.endpoint_valid = _carrier().global_position.distance_to(_path.back()) < .18 and _carrier().linear_velocity.length() < .18
            physical.completed = _path_complete and physical.endpoint_valid
        "pick":
            expected.cassettes[id].holder = Rules.CARRIER
            physical.path_clear = _pickup_support.get("supported",false)
            physical.endpoint_valid = _joint(id) and _slow()
            physical.completed = _joint(id)
        "place":
            expected.cassettes[id].holder = _action.destination
            var landed: bool = _released and _docked(id,str(_action.destination))
            var fall_m: float = _release_y-_cargo(id).global_position.y
            physical.path_clear = landed
            physical.endpoint_valid = landed and fall_m > .10
            physical.completed = landed and fall_m > .10 and _carrier().cargo_items.is_empty()
    physical.custody_verified = _custody_matches(expected)
    for key: String in physical:
        if not physical[key]:
            _block("receipt_physics_pending:"+key)
            return
    var receipt: Dictionary = {}
    for key: String in MATCH_KEYS: receipt[key] = _action[key]
    for key: String in physical: receipt[key] = physical[key]
    # Revision can advance through independent thermal commands. The original
    # action identity AND current physical proof must still match in this call.
    var result: Dictionary = _rules.confirm_action(receipt,true,false)
    if not result.ok:
        _block("receipt:"+str(result.code))
        return
    _receipt_count += 1
    _receipts.append({"receipt":receipt.duplicate(true),"physics_frame":Engine.get_physics_frames(),"custody":_custody.report(),"body_position":_carrier().global_position})
    if _receipts.size() > 32: _receipts.pop_front()
    if not _custody_matches(_rules.snapshot()):
        _fault("post_receipt_custody_mismatch")
        return
    if _action.kind == "pick":
        _departure = _action.duplicate(true)
        _phase = "departure_wait"
    else: _phase = "idle"
    _action.clear()

func _departure_valid() -> bool:
    if _departure.is_empty(): return false
    var state: Dictionary = _rules.snapshot()
    return state.pending_action.is_empty() and state.cassettes[str(_departure.cassette_id)].holder == Rules.CARRIER and state.carrier_anchor == _departure.source and _joint(str(_departure.cassette_id))

func _action_matches() -> bool:
    var pending: Dictionary = _rules.snapshot().pending_action
    if pending.is_empty() or _action.is_empty(): return false
    for key: String in MATCH_KEYS:
        if pending.get(key) != _action.get(key): return false
    return true

func _custody_matches(state: Dictionary) -> bool:
    var actual: Dictionary = _custody.report().cargos
    var carried := 0
    for id: String in Rules.CASSETTES:
        if not actual.has(id) or not state.get("cassettes",{}).has(id): return false
        var holder: String = str(state.cassettes[id].holder)
        if holder == Rules.CARRIER:
            carried += 1
            if actual[id].phase != "carried" or actual[id].carrier != Rules.CARRIER or not _joint(id): return false
        elif holder in Rules.BERTHS:
            if _progress_contact_history.get(id,"")==holder:
                if actual[id].phase not in ["settling","docked"] or actual[id].berth!=holder: return false
            elif not _docked(id,holder): return false
        else: return false
    return _carrier().cargo_items.size() == carried

func _joint(id: String) -> bool:
    var body: Flight = _carrier()
    if body == null or body.cargo_items.size() != 1 or not body.cargo_items.has(id): return false
    var item: Dictionary = body.cargo_items[id]
    var joint: Variant = item.get("joint")
    return is_instance_valid(joint) and joint is PinJoint3D and not joint.is_queued_for_deletion() and item.body == _cargo(id) and joint.get_node_or_null(joint.node_a) == body and joint.get_node_or_null(joint.node_b) == _cargo(id) and is_equal_approx(body.cargo_kg,2.0)

func _docked(id: String, berth_id: String) -> bool:
    var actual: Dictionary = _custody.report().cargos
    return actual.has(id) and actual[id].phase == "docked" and actual[id].berth == berth_id and _custody.support_info(id,berth_id).get("supported",false)

func _live_registry() -> bool:
    var body: Flight = _carrier()
    if body == null or not body.is_inside_tree() or body.is_queued_for_deletion() or body.get_world_3d().space != _space or not body.global_position.is_finite() or not body.linear_velocity.is_finite(): return false
    if not _environment.is_valid(): return false
    for id: String in _cargos:
        var cargo: RigidBody3D = _cargo(id)
        if cargo == null or not cargo.is_inside_tree() or cargo.is_queued_for_deletion() or cargo.get_world_3d().space != _space or not cargo.global_position.is_finite() or not cargo.linear_velocity.is_finite(): return false
    for id: String in _berths:
        var berth: StaticBody3D = _berth(id)
        if berth == null or not berth.is_inside_tree() or berth.is_queued_for_deletion() or berth.get_world_3d().space != _space or berth.global_transform != _berth_poses[id]: return false
    return true

func _contacts_safe() -> bool:
    var body: Flight = _carrier()
    if not body.get_colliding_bodies().is_empty(): return false
    var custody: Dictionary = _custody.report().cargos
    for id: String in _cargos:
        var state: Dictionary = custody[id]
        if state.phase == "fault": return false
        var permitted: StaticBody3D = null
        if state.phase in ["docked","dropping","settling"]: permitted = _berth(str(state.berth))
        elif not _departure.is_empty() and _departure.cassette_id == id: permitted = _berth(str(_departure.source))
        elif not _action.is_empty() and _action.kind == "pick" and _action.cassette_id == id: permitted = _berth(str(_action.source))
        for hit: Node in _cargo(id).get_colliding_bodies():
            if hit != permitted: return false
        var bounds: Dictionary = Dock._bounds(_cargo(id))
        if not bounds.ok: return false
        var box: AABB = bounds.bounds
        for x: float in [box.position.x,box.end.x]:
            for z: float in [box.position.z,box.end.z]:
                var at := Vector3(x,box.position.y,z)
                var field: Variant = _environment.call(at)
                if not field is Dictionary or (field.get("water",false) and at.y < float(field.get("water_height",-1000))): return false
    return true

func _slow() -> bool:
    var body: Flight = _carrier()
    if body.linear_velocity.length() > .12 or body.angular_velocity.length() > .12: return false
    for item: Dictionary in body.cargo_items.values():
        if not is_instance_valid(item.body) or item.body.linear_velocity.length() > .10 or item.body.angular_velocity.length() > .12 or (item.body.linear_velocity-body.linear_velocity).length() > .18: return false
    return true

func _route(action: Dictionary) -> Array[Vector3]:
    var points: Array[Vector3] = []
    var source: Vector3 = _anchor(str(action.source),2.2)
    var destination: Vector3 = _anchor(str(action.destination),2.2)
    _append(points,Vector3(source.x,2.2,source.z))
    _append(points,Vector3(CENTRE_X,2.2,source.z))
    var north_source: bool = action.source in [Rules.WORK,Rules.BUFFER]
    var north_destination: bool = action.destination in [Rules.WORK,Rules.BUFFER]
    if north_source != north_destination:
        _append(points,Vector3(CENTRE_X,2.2,6 if north_source else 23))
        _append(points,Vector3(CENTRE_X,2.2,6 if north_destination else 23))
    _append(points,Vector3(CENTRE_X,2.2,destination.z))
    _append(points,destination)
    if str(action.cassette_id).is_empty() and action.destination != Rules.WAIT: _append(points,_anchor(str(action.destination),1.55))
    return points

func _anchor(id: String, height: float) -> Vector3:
    return WAIT_POINT if id == Rules.WAIT else BERTH_POINTS[id]+Vector3.UP*height

func _append(points: Array[Vector3], point: Vector3) -> void:
    if points.is_empty() or points.back().distance_to(point) > .02: points.append(point)

func _next_serial() -> int:
    _serial = maxi(_serial,int(_custody.last_serial))+1
    return _serial

func _carrier() -> Flight:
    return _body.get_ref() if _body != null else null

func _cargo(id: String) -> RigidBody3D:
    return _cargos[id].get_ref() if _cargos.has(id) else null

func _berth(id: String) -> StaticBody3D:
    return _berths[id].get_ref() if _berths.has(id) else null

func _reset_stability() -> void:
    # These controllers are owned only by this executor. Invalidate continuity
    # evidence across a pause/missed tick; never accumulate unseen settling time.
    if _pilot != null:
        _pilot.settled_seconds = 0.0
        _pilot.clear_seconds = 0.0
    if _dock != null: _dock.stable_seconds = 0.0

func _brake() -> void:
    var body: Flight = _carrier()
    if body == null or not body.is_inside_tree(): return
    body.hold_height = body.global_position.y
    body.command = {"active":true,"mode":"assisted","body_relative":false,"planar":Vector3.ZERO,"vertical":0.0,"yaw":0.0,"brake":true,"fire":false}

func _block(code: String, brake: bool = true) -> void:
    _code = code
    _blocked_tick = true
    if brake: _brake()
    if _action_matches(): _rules.report_blocked(int(_action.serial),true,false)

func _fault(code: String) -> void:
    _brake()
    _code = code
    _phase = "fault"


## Only a physically settled external work hold, never an arbitrary route save.
func snapshot_scan() -> Dictionary:
    var checked: Dictionary=inspect_scan_snapshot()
    return checked.snapshot if checked.ok else {}

func inspect_scan_snapshot() -> Dictionary:
    if not _configured or _closed or not _authority or _in_tick or _scan_restore_pending or _phase!="awaiting_external" or _action.get("kind")!="work" or not _departure.is_empty() or not _live_registry() or not _action_matches() or not _custody_matches(_rules.snapshot()) or _last_frame!=Engine.get_physics_frames(): return {"ok":false,"code":"scan_executor_current_identity_or_frame"}
    var goal: Vector3=_anchor(str(_rules.snapshot().carrier_anchor),2.2)
    if _hold.get("target")!=goal or not _hold.get("action") is Dictionary or _pilot.target!=goal or _pilot.mode!="route" or _pilot.serial!=_serial: return {"ok":false,"code":"scan_executor_original_hold_binding"}
    for key: String in MATCH_KEYS:
        if _hold.action.get(key)!=_action.get(key): return {"ok":false,"code":"scan_executor_original_action_identity"}
    var pilot: Dictionary=_pilot.snapshot_wait(goal)
    if pilot.is_empty(): return {"ok":false,"code":"scan_executor_current_hold_settling","pending":true,"controller":_pilot.report()}
    var saved: Dictionary={"version":1,"serial":_serial,"action":_action.duplicate(true),"anchor":str(_rules.snapshot().carrier_anchor),"controller":pilot,"receipt_count":_receipt_count,"active_ticks":_active_ticks,"initial_health":_initial_health,"initial_collisions":_initial_collisions}
    var valid: Dictionary=validate_scan(saved,_rules.snapshot())
    return {"ok":true,"snapshot":saved} if valid.ok else valid

static func validate_scan(saved: Variant, state: Dictionary) -> Dictionary:
    if not ScanState.exact(saved,["version","serial","action","anchor","controller","receipt_count","active_ticks","initial_health","initial_collisions"]) or saved.version!=1: return {"ok":false,"code":"scan_executor_keys"}
    if not ScanState.integer(saved.serial,1,9007199254740991) or not ScanState.integer(saved.receipt_count,0,32) or not ScanState.integer(saved.active_ticks,1,9007199254740991) or not ScanState.number(saved.initial_health,.00001,100) or not ScanState.integer(saved.initial_collisions,0,2147483647): return {"ok":false,"code":"scan_executor_counters"}
    if not ScanState.exact(saved.action,Rules.ACTION_KEYS) or not saved.action.blocked is bool or not Rules._same(saved.action,state.get("pending_action",{})) or saved.action.kind!="work" or saved.action.actor!="workbench" or int(state.get("jobs_completed",-1))!=0 or saved.anchor!=state.get("carrier_anchor") or saved.anchor not in [Rules.WAIT,Rules.WORK,Rules.SOUTH_0,Rules.SOUTH_1]: return {"ok":false,"code":"scan_executor_action"}
    var goal: Vector3=WAIT_POINT if saved.anchor==Rules.WAIT else BERTH_POINTS[str(saved.anchor)]+Vector3.UP*2.2
    if not Pilot.validate_wait(saved.controller,goal) or saved.controller.serial!=saved.serial: return {"ok":false,"code":"scan_executor_controller"}
    # The sole pending work follows all real completed transport receipts.
    if int(saved.receipt_count)!=int(saved.action.serial)-1: return {"ok":false,"code":"scan_executor_receipt_history"}
    return {"ok":true,"code":"valid_scan_hold_no_receipt"}

func configure_scan_restored(context: Dictionary, saved: Dictionary, authority: bool=true) -> Dictionary:
    if not authority or _configured or _closed or not context.get("carrier") is Flight or not context.get("rules") is RefCounted or not context.get("custody") is RefCounted or not context.get("cargos") is Dictionary or not context.get("berths") is Dictionary or not context.get("environment_query") is Callable: return {"ok":false,"code":"fresh_scan_host_required"}
    var state: Dictionary=context.rules.snapshot()
    var checked: Dictionary=validate_scan(saved,state)
    if not checked.ok: return checked
    var carrier: Flight=context.carrier
    if not is_instance_valid(carrier) or not carrier.is_inside_tree() or not carrier.freeze or not carrier.enabled or context.rules.get_script()!=Rules or context.custody.get_script()!=Custody or not context.environment_query.is_valid() or context.cargos.size()!=2 or context.berths.size()!=4: return {"ok":false,"code":"scan_actual_frozen_dependencies"}
    var space: RID=carrier.get_world_3d().space
    var seen: Dictionary={carrier.get_instance_id():true}
    for id: String in Rules.CASSETTES:
        var cargo: Variant=context.cargos.get(id)
        if not cargo is RigidBody3D or not is_instance_valid(cargo) or not cargo.is_inside_tree() or not cargo.freeze or cargo.get_world_3d().space!=space or cargo.mass!=2.0 or seen.has(cargo.get_instance_id()): return {"ok":false,"code":"scan_cargo_identity"}
        seen[cargo.get_instance_id()]=true
    for id: String in Rules.BERTHS:
        var berth: Variant=context.berths.get(id)
        if not berth is StaticBody3D or not is_instance_valid(berth) or not berth.is_inside_tree() or berth.get_world_3d().space!=space or berth.global_position!=BERTH_POINTS[id] or seen.has(berth.get_instance_id()): return {"ok":false,"code":"scan_berth_identity"}
        var shape: Dictionary=Dock._support(berth)
        if not shape.ok or not shape.bounds.size.is_equal_approx(Vector3(2,.5,2)): return {"ok":false,"code":"scan_berth_geometry"}
        seen[berth.get_instance_id()]=true
    _pilot=Pilot.new()
    var goal: Vector3=_anchor(str(saved.anchor),2.2)
    var restored: Dictionary=_pilot.restore_wait_fresh(carrier,saved.controller,goal,true)
    if not restored.ok: return restored
    _body=weakref(carrier)
    _space=space
    _custody=context.custody
    _rules=context.rules
    _environment=context.environment_query
    for id: String in Rules.CASSETTES: _cargos[id]=weakref(context.cargos[id])
    for id: String in Rules.BERTHS:
        _berths[id]=weakref(context.berths[id])
        _berth_poses[id]=context.berths[id].global_transform
    _serial=int(saved.serial)
    _action=saved.action.duplicate(true)
    for key: String in ["serial","job"]: _action[key]=int(_action[key])
    var identity: Dictionary={}
    for key: String in MATCH_KEYS: identity[key]=_action[key]
    _hold={"anchor":str(saved.anchor),"target":goal,"action":identity,"controller_serial":_serial}
    _initial_health=float(saved.initial_health)
    _initial_collisions=int(saved.initial_collisions)
    _receipt_count=int(saved.receipt_count)
    _active_ticks=int(saved.active_ticks)
    _authority=true
    _configured=true
    _phase="awaiting_external"
    _scan_restore_pending=true
    _code="scan_frozen_controller_prepared"
    return report()

## Restore warm-up only: no Custody step, Rules request, work or receipt.
func scan_restore_hold(delta: float, authority: bool=true) -> Dictionary:
    if not authority or not _authority or not _scan_restore_pending or _in_tick or not _live_registry() or not _action_matches() or not is_finite(delta) or delta<=0 or delta>1.0/60.0+.000001: return _reply("scan_restore_hold_required",false)
    if _last_frame==Engine.get_physics_frames(): return _reply("same_physics_frame",false)
    if _carrier().health<_initial_health or _carrier().collision_count!=_initial_collisions or _carrier().water_contact: return _reply("scan_restore_carrier_changed",false)
    _last_frame=Engine.get_physics_frames()
    _carrier().environment_sample=_environment.call(_carrier().global_position)
    _last_controller=_pilot.tick(delta,true,false)
    return _reply("scan_restore_actual_hold",_last_controller.state in ["traveling","arrived","blocked"])

func scan_restore_ready() -> bool:
    return _authority and _scan_restore_pending and _last_frame==Engine.get_physics_frames() and _live_registry() and _action_matches() and _custody_matches(_rules.snapshot()) and _last_controller.get("arrived",false) and _pilot.probe(Vector3.ZERO).clear

func resume_scan_restored(authority: bool=true) -> Dictionary:
    if not authority or not scan_restore_ready(): return _reply("current_scan_hold_required",false)
    _scan_restore_pending=false
    return _reply("original_external_action_resumed",true)
