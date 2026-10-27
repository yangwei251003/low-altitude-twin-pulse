extends RefCounted
## Normal MAIN physical participant; Root owns lifecycle and the existing Store.
## Bootstrap / WAIT / scan / transport / original departure host site.
## No Store ownership, RPC, rewards or player UI. Root owns normal integration.
const Assembly = preload("res://scripts/v3/gameplay/canal/canal_assembly/canal_assembly.gd")
const STATE_PATH := "world.environment.I2_canal"
const WaitCheckpoint = Assembly.WaitCheckpoint
const ScanCheckpoint = Assembly.ScanCheckpoint
const ProgressCheckpoint = Assembly.ProgressCheckpoint
const StartupCheckpoint = Assembly.StartupCheckpoint
const StoryService=preload("res://scripts/v3/gameplay/canal/canal_checkpoint/canal_story_service.gd")
const PauseBoundary=preload("res://scripts/v3/gameplay/canal/canal_checkpoint/canal_pause_boundary.gd")
const IDS := [Assembly.Runtime.CASSETTES[0], Assembly.Runtime.CASSETTES[1], Assembly.CARRIER_ID, Assembly.RELAY_ID, Assembly.VALVE_ID, Assembly.Workbench.POWER_ID]
const NAMES := ["冷却匣 0", "冷却匣 1", "换匣运输机", "回冷供电点", "回冷阀", "检修台供电点"]
const PHYSICAL_KEYS := ["position", "temperature", "charge", "charge_capacity", "power_threshold", "powered"]
var session
var module: Node3D
var ready := false
var error := ""
var _world: Node3D
var _registered: Dictionary = {}
var _entities: Dictionary = {}
var _paused := false
var _busy := false
var _pause_bodies: Dictionary = {}
var _pause_joints: Dictionary = {}
var _last_body_modes: Dictionary = {}
var _pause_fault := ""
var _pause_details: Dictionary = {}
var _pause_restores := 0
var _pause_wait_capture: Dictionary = {}
var _pause_wait_guard: String = ""
var _pause_request: Dictionary = {}
var _pause_scan_owned := false
var _pause_application: Dictionary = {}
const PAUSE_REQUEST_FRAMES := 60
var _story_service=StoryService.new()

func setup(owner_session) -> void:
    if session == owner_session: return
    clear()
    session = owner_session
    _story_service.setup(self)

## Compatible lifecycle. Save validation is pure; restore adoption remains
## pending until actual current-space contacts and owned physical state pass.
## Preparing never creates a physics world or claims a detached site is ready.
func prepare(world_data: Dictionary, destination: String, authority: bool, _discoveries: Array = []) -> Dictionary:
    var environment: Variant = world_data.get("environment", {})
    if not environment is Dictionary: return _result(false, "invalid_environment")
    if environment.has("canal_candidate_checkpoint"): return _result(false,"candidate_repository_envelope_not_main_state")
    var saved: Dictionary={}
    if environment.has("I2_canal"):
        var scan: bool=environment.I2_canal is Dictionary and environment.I2_canal.get("kind")==ScanCheckpoint.KIND
        var progress: bool=environment.I2_canal is Dictionary and environment.I2_canal.get("kind")==ProgressCheckpoint.KIND
        var startup: bool=environment.I2_canal is Dictionary and environment.I2_canal.get("kind")==StartupCheckpoint.KIND
        var valid: Dictionary=StartupCheckpoint.validate(environment.I2_canal) if startup else (ProgressCheckpoint.validate(environment.I2_canal) if progress else (ScanCheckpoint.validate(environment.I2_canal) if scan else WaitCheckpoint.validate(environment.I2_canal)))
        if not valid.ok: return _result(false,"canal_saved:"+str(valid.code))
        saved=environment.I2_canal.duplicate(true)
    if destination not in ["I1", "F1", "I2"]: return _result(false, "unsupported_region")
    if destination == "I2" and not authority: return _result(false, "canal_client_state_not_supported")
    return {"ok":true, "code":"prepared_not_live", "error":"", "destination":destination, "authority":authority, "module":Assembly.new() if destination == "I2" else null,"saved":saved}

func discard(prepared: Dictionary) -> void:
    var candidate: Variant = prepared.get("module")
    if candidate is Assembly and is_instance_valid(candidate) and candidate != module and candidate.get_parent() == null:
        candidate.free()

## The caller first mounts/presents its real World. A failed adopt cannot tear
## down an old valid site. No replacing a live Assembly or clearing its ledger.
func adopt(prepared: Dictionary, _world_data: Dictionary = {}) -> Dictionary:
    if not is_instance_valid(session) or not is_instance_valid(session.world) or not session.world.is_inside_tree(): return _result(false, "live_current_world_required")
    if not prepared.get("ok", false) or str(prepared.get("destination", "")) != session.region_id: return _result(false, "prepared_region_mismatch")
    if is_instance_valid(module): return _result(false, "existing_site_requires_explicit_clear")
    if session.region_id != "I2": return _result(true, "not_in_region")
    if not session.active or not session.network.is_authority() or prepared.get("authority") != true: return _result(false, "not_authority")
    var candidate: Variant = prepared.get("module")
    if not candidate is Assembly or not is_instance_valid(candidate) or candidate.get_parent() != null: return _result(false, "fresh_assembly_required")
    for id: String in IDS:
        if session.world.objects.has(id) or session.world.definitions.has(id) or session.entities.has(id): return _result(false, "target_id_already_registered:" + id)
    candidate.name = "CanalSessionAssembly"
    session.world.add_child(candidate)
    var saved: Dictionary=prepared.get("saved",{})
    var made: Dictionary = candidate.configure(session.world, session.world.sample_environment, true) if saved.is_empty() else candidate.prepare_saved(session.world,session.world.sample_environment,saved,saved.device_serial,true)
    if not made.ok:
        candidate.free()
        return _result(false, "assembly_configure:" + str(made.code))
    module = candidate
    _world = session.world
    _paused = false
    var registered: Dictionary = _sync_targets()
    if not registered.ok:
        clear()
        return registered
    _remember_body_modes()
    if session.simulation_paused and not candidate.status().restore_pending:
        var paused: Dictionary = set_paused(true)
        if not paused.ok:
            clear()
            return paused
    _update_ready()
    return _result(true, "live_bootstrap_not_ready" if saved.is_empty() else "frozen_saved_wait_not_ready")

func clear() -> void:
    _story_service.reset()
    # Match BOTH the original physical object and original entity dictionary.
    # Same IDs in a newly loaded region are not ours to delete.
    for id: String in _registered:
        var body: Variant = _registered[id]
        if is_instance_valid(_world) and is_same(_world.objects.get(id), body):
            _world.objects.erase(id)
            _world.definitions.erase(id)
            _world.initial_transforms.erase(id)
        if is_instance_valid(session) and is_same(session.entities.get(id), _entities.get(id)):
            session.entities.erase(id)
    _registered.clear()
    _entities.clear()
    if is_instance_valid(module):
        if module.is_inside_tree(): module.close(true)
        module.free() # Only this Assembly's children; never its owning World.
    module = null
    _world = null
    ready = false
    error = ""
    _paused = false
    _pause_bodies.clear()
    _pause_joints.clear()
    _last_body_modes.clear()
    _pause_fault = ""
    _pause_details.clear()
    _pause_restores = 0
    _pause_wait_capture.clear()
    _pause_wait_guard = ""
    _pause_request.clear()
    _pause_scan_owned = false
    _pause_application.clear()

func reset_connection() -> void:
    clear() # No packet/epoch state exists in this host-only candidate.

func advance(delta: float) -> Dictionary:
    var issue: String = _binding_issue()
    if not issue.is_empty():
        ready = false
        return _result(false, issue)
    if _story_service.status().reload_required: return _result(false,"committed_claim_requires_reload")
    if _busy: return _result(false, "reentrant_adapter")
    if not _pause_fault.is_empty(): return _result(false, _pause_fault)
    if _paused:
        var integrity: String = _pause_integrity()
        if not integrity.is_empty(): return _pause_failure(integrity)
        if not is_finite(delta) or delta < 0 or delta > minf(.1, 1.0/float(Engine.physics_ticks_per_second)+.000001): return _result(false, "invalid_physics_delta")
        # Bodies and controller state are already stopped. Calling the Assembly
        # again is unnecessary and could execute a suspended controller twice.
        return _result(true, "owned_physics_paused")
    if module.status().restore_pending:
        _busy=true
        var restored: Dictionary=module.advance(delta,true,session.simulation_paused)
        if restored.ok and module.status().restore_ready: restored=module.adopt_saved(true)
        if restored.ok and not module.status().restore_pending:
            restored=_sync_targets()
            if restored.ok: _remember_body_modes()
        _busy=false
        if restored.ok and not module.status().restore_pending: _advance_pause_request()
        error="" if restored.ok else str(restored.code)
        _update_ready()
        return restored
    if session.simulation_paused: return _result(false, "explicit_pause_transition_required")
    _busy = true
    # Exactly once per physics frame; never split/replay Assembly's tick.
    var qa_clock: int=session._qa_cpu_begin()
    var result: Dictionary = module.advance(delta, true, _paused or session.simulation_paused)
    session._qa_cpu_end("canal.module.advance",qa_clock)
    if result.ok:
        qa_clock=session._qa_cpu_begin()
        result = _sync_targets()
        session._qa_cpu_end("canal.targets",qa_clock)
    if result.ok:
        qa_clock=session._qa_cpu_begin()
        _remember_body_modes()
        _story_service.observe()
        session._qa_cpu_end("canal.service_observe",qa_clock)
    _busy = false
    if result.ok: _advance_pause_request()
    error = "" if result.ok else str(result.code)
    _update_ready()
    return result

## Process/UI calls only request. Ordinary advance() finishes the scan barrier,
## validates native/Node state at the actual physics boundary, then freezes.
## Root keeps Consensus pending and simulation_paused=false until ready=true.
func request_pause() -> Dictionary:
    var issue: String=_binding_issue()
    if not issue.is_empty() or _busy or not _pause_fault.is_empty(): return {"ok":false,"code":issue if not issue.is_empty() else (_pause_fault if not _pause_fault.is_empty() else "reentrant_adapter"),"pending":false,"ready":false}
    if _paused or _pause_request.get("pending",false): return pause_request_status()
    _story_service.invalidate_observation()
    _pause_request={"ok":true,"code":"pause_requested_next_physics_boundary","pending":true,"ready":false,"requested_frame":Engine.get_physics_frames()}
    return pause_request_status()

func pause_request_status() -> Dictionary:
    if _paused:
        var integrity: String=_pause_integrity()
        return {"ok":integrity.is_empty(),"code":"owned_physics_paused_with_valid_capture" if integrity.is_empty() else integrity,"pending":false,"ready":integrity.is_empty() and _pause_wait_capture.get("ok",false),"physics_frame":_pause_request.get("physics_frame",-1)}
    return _pause_request.duplicate(true) if not _pause_request.is_empty() else {"ok":true,"code":"pause_not_requested","pending":false,"ready":false}

## Read-only evidence from the actual application boundary, never the earlier
## UI/request frame. Native pose and momentum were sampled before mode changes.
func pause_boundary_snapshot() -> Dictionary:
    if not _paused or _pause_application.is_empty(): return {"ok":false,"code":"not_paused_at_recorded_boundary"}
    var integrity: String=_pause_integrity()
    if not integrity.is_empty(): return {"ok":false,"code":integrity}
    return _pause_application.duplicate(true)

func cancel_pause_request() -> Dictionary:
    if _paused: return {"ok":false,"code":"already_paused_requires_explicit_resume","pending":false,"ready":true}
    if _busy: return {"ok":false,"code":"reentrant_adapter","pending":true,"ready":false}
    if _pause_scan_owned and is_instance_valid(module): module.release_scan_capture()
    _pause_scan_owned=false
    _pause_request.clear()
    return {"ok":true,"code":"pause_request_cancelled_without_body_mutation","pending":false,"ready":false}

func _advance_pause_request() -> void:
    if not _pause_request.get("pending",false) or _paused: return
    if not Engine.is_in_physics_frame(): return
    if Engine.get_physics_frames()-int(_pause_request.requested_frame)>PAUSE_REQUEST_FRAMES:
        _pause_request_failed("pause_physics_boundary_timeout")
        return
    var bench: Variant=module.workbench
    var owns_new_barrier: bool=is_instance_valid(bench) and bench._capture_requested_frame<0
    var prepared: Dictionary=module.prepare_scan_capture()
    if owns_new_barrier and prepared.get("code","")!="scan_capture_not_required" and prepared.get("ok",false): _pause_scan_owned=true
    if not prepared.get("ok",false):
        _pause_request_failed("pause_scan:"+str(prepared.get("code","unavailable")))
        return
    if not prepared.get("ready",false):
        _pause_request.code="pause_scan_capture_settling"
        return
    var result: Dictionary=_freeze_current_boundary()
    if result.ok:
        _pause_request={"ok":true,"code":"owned_physics_paused_with_valid_capture","pending":false,"ready":true,"physics_frame":Engine.get_physics_frames()}
        if _pause_scan_owned: module.release_scan_capture()
        _pause_scan_owned=false
    elif result.get("pending",false):
        _pause_request.code=result.code
        _pause_request["details"]=result.get("details",{})
    else:
        _pause_request_failed(str(result.code))

func _pause_request_failed(code: String) -> void:
    if _pause_scan_owned and is_instance_valid(module): module.release_scan_capture()
    _pause_scan_owned=false
    _pause_request={"ok":false,"code":code,"pending":false,"ready":false}

func set_paused(value: bool) -> Dictionary:
    var issue: String = _binding_issue()
    if not issue.is_empty(): return _result(false, issue)
    if _busy: return _result(false, "reentrant_adapter")
    if not _pause_fault.is_empty(): return _result(false, _pause_fault)
    if _paused:
        var integrity: String = _pause_integrity()
        if not integrity.is_empty(): return _pause_failure(integrity)
        if value: return _result(true, "owned_physics_already_paused")
        var resumed: Dictionary = module.set_paused(false, true)
        if not resumed.ok: return resumed
        # No pose writes. Restore each original physical mode and momentum once;
        # sleep is restored last because velocity setters can wake a body.
        for saved: Dictionary in _pause_bodies.values():
            var restored: Dictionary=PauseBoundary.resume(saved)
            if not restored.ok: return _pause_failure(str(restored.code))
        _paused = false
        _pause_bodies.clear()
        _pause_joints.clear()
        _pause_restores += 1
        _pause_wait_capture.clear()
        _pause_wait_guard = ""
        _pause_request.clear()
        _pause_application.clear()
        _remember_body_modes()
        return _result(true, "owned_physics_resumed_once")
    if not value:
        if _pause_request.get("pending",false): cancel_pause_request()
        return _result(true, "owned_physics_already_running")
    # Compatibility for callers already inside the normal authority physics
    # tick. Process/UI callers must use request_pause(), never old Node poses.
    if not Engine.is_in_physics_frame(): return _result(false,"pause_request_required")
    _story_service.invalidate_observation()
    return _freeze_current_boundary()

func _freeze_current_boundary() -> Dictionary:
    var bodies: Array[Node] = module.find_children("*", "RigidBody3D", true, false)
    if bodies.is_empty(): return _result(false, "owned_bodies_missing")
    var captured: Dictionary = {}
    for node: Node in bodies:
        var body := node as RigidBody3D
        var id: int = body.get_instance_id()
        if not owns_body(body) or not body.global_transform.is_finite() or not body.linear_velocity.is_finite() or not body.angular_velocity.is_finite(): return _result(false, "invalid_owned_body")
        var native: Dictionary=PauseBoundary.sample(body)
        if not native.ok:
            return {"ok":false,"code":str(native.code)+":"+str(body.name),"pending":native.get("pending",false),"details":{"node":native.get("node_pose"),"physics":native.get("pose"),"body":str(body.name)}}
        if _last_body_modes.has(id) and _last_body_modes[id] != _body_mode(body):
            return _result(false, "external_body_mode_changed_before_pause:" + str(body.name))
        captured[id] = native
    var joints: Dictionary = _joint_states()
    # Capture before stopping controls: stop legitimately clears Pilot settled
    # time and Cooling axis velocity. Never serialize those zeroed substitutes.
    _pause_wait_capture=module.capture_active_checkpoint()
    if not _pause_wait_capture.get("ok",false):
        var failed_capture: Dictionary={"ok":false,"code":"pause_valid_capture_required:"+str(_pause_wait_capture.get("code","unavailable")),"pending":false,"details":_pause_wait_capture.duplicate(true)}
        if _pause_wait_capture.get("code")=="actual_scan_executor_hold_required":
            var hold: Dictionary=module.executor.inspect_scan_snapshot()
            failed_capture.pending=hold.get("pending",false)
            failed_capture.details["executor"]=hold
        return failed_capture
    var context_at_pause: Dictionary=module.context()
    var boundary_bodies: Dictionary={}
    for id: int in captured:
        var original: Dictionary=captured[id]
        var body: RigidBody3D=original.body.get_ref()
        boundary_bodies[id]={"name":str(body.name),"rid":str(original.rid),"pose":original.node_pose,"physical":original.pose,"freeze":original.freeze,"freeze_mode":original.freeze_mode,"sleeping":original.sleeping,"linear":original.linear,"angular":original.angular,"process":original.process,"physics_process":original.physics_process}
    var application: Dictionary={"ok":true,"code":"actual_native_pause_boundary","physics_frame":Engine.get_physics_frames(),"bodies":boundary_bodies,"carrier_clock":context_at_pause.carrier.flight_seconds,"modules":{"rules":context_at_pause.rules.snapshot().duplicate(true) if context_at_pause.get("rules")!=null else null,"custody":context_at_pause.custody.report().duplicate(true) if context_at_pause.get("custody")!=null else null}}
    var stopped: Dictionary = module.set_paused(true, true)
    if not stopped.ok: return stopped
    _pause_bodies = captured
    _pause_joints = joints
    for saved: Dictionary in _pause_bodies.values():
        var frozen: Dictionary=PauseBoundary.freeze(saved)
        if not frozen.ok: return _pause_failure(str(frozen.code))
    _paused = true
    _pause_application=application
    _pause_wait_guard = _wait_pause_guard()
    return _result(true, "owned_physics_paused")

## Session must SKIP these bodies in its generic freeze/resume loop. Calling
## that loop first destroys the original mode evidence (e.g. bootstrap's
## intentionally frozen carrier); this adapter refuses observed mode changes.
func owns_body(body: Variant) -> bool:
    return body is RigidBody3D and is_instance_valid(body) and is_instance_valid(module) and module.is_inside_tree() and body.is_inside_tree() and module.is_ancestor_of(body) and body.get_world_3d().space == module.get_world_3d().space

func _body_mode(body: RigidBody3D) -> Dictionary:
    return {"freeze":body.freeze, "freeze_mode":body.freeze_mode, "process":body.is_processing(), "physics_process":body.is_physics_processing()}

func _remember_body_modes() -> void:
    _last_body_modes.clear()
    for node: Node in module.find_children("*", "RigidBody3D", true, false):
        var body := node as RigidBody3D
        _last_body_modes[body.get_instance_id()] = _body_mode(body)

func _joint_states() -> Dictionary:
    var result: Dictionary = {}
    for node: Node in module.find_children("*", "Joint3D", true, false):
        var joint := node as Joint3D
        var row: Dictionary={"rid":joint.get_rid(), "a":joint.node_a, "b":joint.node_b, "pose":joint.global_transform}
        if joint is PinJoint3D:
            row.merge({"local_a":PhysicsServer3D.pin_joint_get_local_a(joint.get_rid()),"local_b":PhysicsServer3D.pin_joint_get_local_b(joint.get_rid()),"bias":joint.get_param(PinJoint3D.PARAM_BIAS),"damping":joint.get_param(PinJoint3D.PARAM_DAMPING),"clamp":joint.get_param(PinJoint3D.PARAM_IMPULSE_CLAMP),"exclude_pair":joint.exclude_nodes_from_collision})
        result[joint.get_instance_id()] = row
    return result

func _pause_integrity() -> String:
    if module.find_children("*", "RigidBody3D", true, false).size() != _pause_bodies.size(): return "paused_body_set_changed"
    if _joint_states() != _pause_joints: return "paused_joint_changed"
    for saved: Dictionary in _pause_bodies.values():
        var body: Variant = saved.body.get_ref()
        if not owns_body(body) or body.get_rid() != saved.rid or body.get_world_3d().space != saved.space: return "paused_body_identity_changed"
        var checked: Dictionary=PauseBoundary.frozen(saved)
        if not checked.ok:
            _pause_details=checked.duplicate(true)
            _pause_details["body"]=str(body.name)
            return str(checked.code)+":"+str(body.name)
    return ""

func _pause_failure(code: String) -> Dictionary:
    _pause_fault = code
    error = code
    ready = false
    var result: Dictionary = _result(false, code)
    result.details = _pause_details.duplicate(true)
    return result # Never teleport/re-freeze a tampered body silently.

## No normal pause/capture/resume contract applies after a committed claim
## failed live adoption. Freeze current native poses without synchronizing old
## Node caches; preserve the committed Store and demand a new World from it.
func hold_for_committed_reload(code: String) -> Dictionary:
    var issue: String=_binding_issue()
    if not issue.is_empty() or _busy: return _result(false,issue if not issue.is_empty() else "reentrant_adapter")
    var held: Dictionary={}
    for node: Node in module.find_children("*","RigidBody3D",true,false):
        var body:=node as RigidBody3D
        if not owns_body(body): return _pause_failure("fatal_hold_foreign_body")
        var result: Dictionary=PauseBoundary.hold_native_for_reload(body)
        if not result.ok: return _pause_failure(str(result.code))
        held[body.get_instance_id()]=result
    module.set_paused(true,true)
    if _pause_scan_owned: module.release_scan_capture()
    _pause_scan_owned=false
    _pause_request.clear()
    _pause_wait_capture.clear()
    _pause_wait_guard=""
    _pause_details={"bodies":held,"reload_required":true}
    _pause_failure("committed_claim_reload_required:"+code)
    return {"ok":true,"code":"actual_native_bodies_held_requires_committed_reload","reload_required":true,"bodies":held}

func sync_roster(_reset_peer: int = 0) -> void:
    # Assembly owns its original device serial, not a forged player axis lease.
    # Each accepted ability still validates the actual current Session actor.
    pass

func owns_target(id: String) -> bool:
    return id in IDS

func target_definitions() -> Array[Dictionary]:
    if not _binding_issue().is_empty(): return []
    return module.target_definitions()

func context() -> Dictionary:
    if not _binding_issue().is_empty(): return {}
    return module.context()

## Root computes Story's candidate, writes this envelope in that SAME original
## Store transaction, then calls adopt synchronously. No Store/reward here.
func prepare_story_service(peer_id: int) -> Dictionary:
    return _story_service.prepare(peer_id)

func adopt_story_service(prepared: Dictionary) -> Dictionary:
    return _story_service.adopt(prepared)

func story_service_status() -> Dictionary:
    return _story_service.status()

func exchange_fact() -> String:
    return _story_service.exchange_fact()

## Call before pausing/freezing or taking the synchronous Store transaction.
## Keep ordinary authority ticks running until ready; always release afterward,
## including timeout/publication failure. No Store or actor mutation occurs here.
func prepare_scan_capture() -> Dictionary:
    var issue: String=_binding_issue()
    if not issue.is_empty() or _busy or not _pause_fault.is_empty(): return {"ok":false,"code":issue if not issue.is_empty() else "scan_capture_unavailable","ready":false}
    if _paused:
        var current: Dictionary=capture_persistent_state()
        return {"ok":current.ok,"code":"paused_valid_capture_cached" if current.ok else current.code,"ready":current.ok,"required":false}
    return module.prepare_scan_capture()

func release_scan_capture() -> Dictionary:
    if _busy: return {"ok":false,"code":"reentrant_adapter"}
    if not is_instance_valid(module): return {"ok":true,"code":"scan_capture_already_released"}
    return module.release_scan_capture()

func capture_persistent_state() -> Dictionary:
    var issue: String=_binding_issue()
    if not issue.is_empty() or _busy or not _pause_fault.is_empty(): return _result(false,issue if not issue.is_empty() else "canal_capture_unavailable")
    var captured: Dictionary
    if _paused:
        var integrity: String=_pause_integrity()
        if not integrity.is_empty(): return _pause_failure(integrity)
        if _wait_pause_guard()!=_pause_wait_guard: return _result(false,"paused_wait_state_changed")
        captured=_pause_wait_capture.duplicate(true)
    else:
        captured=module.capture_active_checkpoint()
    if not captured.get("ok",false):
        var failed: Dictionary=_result(false,str(captured.get("code","unsupported_save_phase")))
        failed["detail"]=captured.duplicate(true)
        return failed
    return {"ok":true,"code":"captured_unordered_wait" if captured.envelope.kind==WaitCheckpoint.KIND else ("captured_progress" if captured.envelope.kind==ProgressCheckpoint.KIND else ("captured_startup" if captured.envelope.kind==StartupCheckpoint.KIND else "captured_partial_scan")),"path":STATE_PATH,"envelope":captured.envelope.duplicate(true)}

func persistent_state() -> Dictionary:
    # Compatibility query only: host MUST use fallible capture above to commit.
    var result: Dictionary=capture_persistent_state()
    return result.envelope if result.ok else {}

func _wait_pause_guard() -> String:
    if not is_instance_valid(module): return ""
    var ctx: Dictionary=module.context()
    if ctx.is_empty(): return ""
    var physical: Array=[]
    for node: Node in module.find_children("*","RigidBody3D",true,false):
        var body := node as RigidBody3D
        physical.append([body.get_instance_id(),body.collision_layer,body.collision_mask,body.mass])
    var bench: Dictionary=ctx.workbench.report() if is_instance_valid(ctx.get("workbench")) else {}
    return JSON.stringify({"rules":ctx.rules.snapshot() if ctx.get("rules")!=null else {},"cooling":ctx.cooling.snapshot() if is_instance_valid(ctx.get("cooling")) else {},"custody":ctx.custody.report() if ctx.get("custody")!=null else {},"bench":bench,"bootstrap":module.bootstrap.report() if not module._ready_for_order else {},"physical":physical},"",true,true).sha256_text()

func status() -> Dictionary:
    _update_ready()
    return {"ready":ready, "error":error, "installed":is_instance_valid(module), "live":_binding_issue().is_empty(), "target_count":_registered.size(), "persistence_supported":true,"persistence_scope":"startup_v1 / unordered_wait_v1 / stationary_scan_v1 / progress_v1; host must check fallible capture", "client_state_supported":false, "ordinary_play_enabled":is_instance_valid(session) and session.canal_runtime_enabled, "pause_scope":"all_owned_rigid_bodies_and_original_controllers", "physics_paused":_paused, "paused_body_count":_pause_bodies.size(), "pause_restores":_pause_restores, "pause_fault":_pause_fault, "assembly":module.status() if is_instance_valid(module) else {}}

## Called synchronously instead of generic Session resolve/commit/execute for
## these six IDs. Caller may display feedback but MUST NOT execute the result
## again. This is NOT an RPC and never trusts client-supplied LOS/actor identity.
func use_ability(peer_id: int, payload: Dictionary) -> Dictionary:
    var target: String = str(payload.get("target_id", session.locks.get(peer_id, "") if is_instance_valid(session) else ""))
    if not owns_target(target): return {"handled":false, "ok":false, "code":"outside_canal_domain"}
    var issue: String = _binding_issue()
    if not issue.is_empty(): return _ability_result(false, issue)
    if _busy or _paused or session.simulation_paused or not _pause_fault.is_empty(): return _ability_result(false, "canal_paused_or_busy")
    if not session.players.has(peer_id) or not session.players[peer_id] is FlightBodyV2: return _ability_result(false, "actor_missing")
    var body: FlightBodyV2 = session.players[peer_id]
    if not is_instance_valid(body) or not body.is_inside_tree() or body.get_world_3d().space != _world.get_world_3d().space: return _ability_result(false, "actor_world_mismatch")
    if float(session.cooldowns.get(peer_id, 0.0)) > 0.0: return _ability_result(false, "cooldown")
    var actor: String = session._actor_id(peer_id)
    if not session.entities.get(actor) is Dictionary: return _ability_result(false, "actor_missing")
    var row: Dictionary = {}
    for item: Dictionary in module.target_definitions():
        if item.id == target: row = item; break
    if row.is_empty() or not _registered.has(target) or not is_same(_registered[target], row.body) or not is_same(_world.objects.get(target), row.body) or not is_same(session.entities.get(target), _entities.get(target)):
        return _ability_result(false, "target_missing")
    # Nothing below mutates the live entities until the domain accepts. Even
    # actor pose/health refresh and generic revision increments stay private.
    var candidate: Dictionary = session.entities.duplicate(true)
    candidate[actor].merge({"position":body.global_position, "health":body.health, "downed":not body.enabled}, true)
    candidate[target].merge(_physical_state(row), true)
    var intent: Dictionary = {"actor_id":actor, "ability":str(payload.get("ability", "")), "target_id":target, "mode":str(payload.get("mode", "")), "point":payload.get("point", body.global_position)}
    for key: String in ["actor_revision", "expected_revision"]:
        if payload.has(key): intent[key] = payload[key]
    var los: bool = session._line_clear(body.global_position, row.body.global_position, body.get_rid(), target)
    var resolved: Dictionary = session.rules.resolve(intent, candidate, {"sender_id":str(peer_id), "line_of_sight":los})
    if not resolved.ok: return _ability_result(false, str(resolved.code))
    # Only the single target and authenticated actor may be adopted below.
    for patch: Dictionary in resolved.get("patches", []):
        if str(patch.entity_id) not in [actor, target]: return _ability_result(false, "unexpected_transaction_target")
    var committed: Dictionary = session.rules.commit(resolved, candidate, true)
    if not committed.ok: return _ability_result(false, str(committed.code))
    _busy = true
    var domain_mode: String = str(intent.mode)
    if domain_mode in ["push", "heat", "add"]: domain_mode = ""
    var accepted: Dictionary = module.apply_authorized_ability(target, str(intent.ability), domain_mode, committed.get("physics_requests", []), true)
    _busy = false
    if not accepted.ok: return _ability_result(false, "canal:" + str(accepted.code))
    # No await/reentry between validation and this commit. Physical charge and
    # temperature are authoritative, generic owner/revision/lease remain Rules'.
    for fresh: Dictionary in module.target_definitions():
        if fresh.id == target: candidate[target].merge(_physical_state(fresh), true)
    session.entities[actor].clear()
    session.entities[actor].merge(candidate[actor], true)
    session.entities[target].clear()
    session.entities[target].merge(candidate[target], true)
    session.cooldowns[peer_id] = 0.35
    session.stats.abilities += 1
    var result: Dictionary = _ability_result(true, "committed_once")
    result.merge({"actor_id":actor, "target_id":target, "ability":intent.ability, "domain":accepted.duplicate(true), "physics_executed_by_assembly":not committed.get("physics_requests", []).is_empty()})
    return result

func _sync_targets() -> Dictionary:
    var rows: Array[Dictionary] = module.target_definitions()
    # Validate the whole available set before touching registries.
    var seen: Dictionary = {}
    for row: Dictionary in rows:
        var id: String = str(row.id)
        var body: Variant = row.body
        if id not in IDS or seen.has(id) or not body is PhysicsBody3D or not is_instance_valid(body) or not body.is_inside_tree() or body.get_world_3d().space != _world.get_world_3d().space: return _result(false, "invalid_live_target")
        seen[id] = true
        if _registered.has(id):
            if not is_same(_registered[id], body) or not is_same(_world.objects.get(id), body) or not is_same(session.entities.get(id), _entities.get(id)): return _result(false, "target_registration_replaced:" + id)
        elif _world.objects.has(id) or _world.definitions.has(id) or session.entities.has(id): return _result(false, "target_registration_conflict:" + id)
        if body.has_meta("entity_id") and str(body.get_meta("entity_id")) != id: return _result(false, "body_entity_id_conflict:" + id)
    for row: Dictionary in rows:
        var id: String = str(row.id)
        if not _registered.has(id):
            var definition: Dictionary = {"id":id, "name":NAMES[IDS.find(id)], "tags":row.tags.duplicate(), "abilities":row.abilities.duplicate(), "owner":"neutral", "revision":0}
            definition.merge(_physical_state(row), true)
            _world.objects[id] = row.body
            _world.definitions[id] = definition.duplicate(true)
            _world.initial_transforms[id] = row.body.transform
            row.body.set_meta("entity_id", id)
            session.entities[id] = definition.duplicate(true)
            _entities[id] = session.entities[id]
            _registered[id] = row.body
        else:
            session.entities[id].merge(_physical_state(row), true)
    return _result(true, "physical_targets_synchronized")

func _physical_state(row: Dictionary) -> Dictionary:
    var result: Dictionary = {}
    for key: String in PHYSICAL_KEYS:
        if row.state.has(key): result[key] = row.state[key]
    if result.has("charge") and result.has("power_threshold"): result.powered = float(result.charge) >= float(result.power_threshold)
    return result

func _binding_issue() -> String:
    if not is_instance_valid(session) or not is_instance_valid(module) or not is_instance_valid(_world): return "site_not_installed"
    if not session.active or not session.network.is_authority(): return "not_authority"
    if session.region_id != "I2" or session.world != _world or not _world.is_inside_tree() or not module.is_inside_tree() or module.get_parent() != _world: return "live_current_i2_required"
    if module.get_world_3d().space != _world.get_world_3d().space: return "assembly_space_mismatch"
    return ""

func _update_ready() -> void:
    ready = false
    if not _binding_issue().is_empty() or not error.is_empty(): return
    var state: Dictionary = module.status()
    ready = bool(state.ok) and bool(state.ready) and not bool(state.closed)

func _ability_result(ok: bool, code: String) -> Dictionary:
    if not ok and is_instance_valid(session): session.stats.rejected_abilities += 1
    return {"handled":true, "ok":ok, "code":code}

static func _result(ok: bool, code: String) -> Dictionary:
    return {"ok":ok, "code":code, "error":"" if ok else code}
