extends RefCounted
## Versioned normal-chain progress. No Repository, transaction, ticks or rewards.
const Wait=preload("res://scripts/v3/gameplay/canal/canal_checkpoint/canal_wait_checkpoint.gd")
const Parts=preload("res://scripts/v3/gameplay/canal/canal_checkpoint/canal_progress_state.gd")
const State=Wait.State
const Rules=Wait.Rules
const KIND="canal_progress_checkpoint_v1"
const VERSION=1
const KEYS=["version","kind","layout_sha256","physics_hz","source_frame","rules","custody","carrier","bodies","executor","workbench","cooling","device_serial","rule_seconds","rule_usec"]

static func capture(context: Dictionary, executor: RefCounted, bench: Node3D, cooling: Node3D, device_serial: int, rule_seconds: float, rule_usec: int, fresh_adopt_frame: bool=false) -> Dictionary:
    if context.is_empty() or executor==null or not is_instance_valid(bench) or not is_instance_valid(cooling): return Wait.bad("progress_modules_required")
    var frame: int=Engine.get_physics_frames()
    if not fresh_adopt_frame and (executor._last_frame!=frame or context.custody._last_physics_frame!=frame or bench._last_frame!=frame): return Wait.bad("current_progress_frame_required")
    var custody: Dictionary=context.custody.snapshot_progress()
    var controller: Dictionary=Parts.executor_snapshot(executor,context.cargos)
    var inspected: Dictionary=bench.inspect_progress()
    if not inspected.ok: return {"ok":false,"code":"progress_workbench:"+str(inspected.code),"detail":inspected}
    var workbench: Dictionary=inspected.snapshot
    var device: Dictionary={"ok":true,"state":cooling.snapshot()} if fresh_adopt_frame and cooling._integrity().is_empty() else cooling.capture_state(frame)
    if custody.is_empty(): return Wait.bad("progress_actual_custody_required")
    if controller.is_empty(): return Wait.bad("progress_actual_executor_required")
    if workbench.is_empty(): return Wait.bad("progress_workbench_state_required")
    if not device.ok: return Wait.bad("progress_device:"+str(device.code))
    var bodies: Dictionary={Rules.CARRIER:rigid_snapshot(context.carrier),Wait.Safe.BENEFICIARY_ID:rigid_snapshot(bench.beneficiary)}
    for id: String in Rules.CASSETTES: bodies[id]=rigid_snapshot(context.cargos[id])
    var saved: Dictionary={"version":VERSION,"kind":KIND,"layout_sha256":Wait.Safe.layout_fingerprint(),"physics_hz":Engine.physics_ticks_per_second,"source_frame":frame,"rules":context.rules.snapshot(),"custody":custody,"carrier":State.capture_progress(context.carrier,Rules.CARRIER),"bodies":bodies,"executor":controller,"workbench":workbench,"cooling":device.state,"device_serial":device_serial,"rule_seconds":rule_seconds,"rule_usec":rule_usec}
    var checked: Dictionary=validate(saved)
    return {"ok":true,"code":"captured_actual_transport_progress","envelope":saved.duplicate(true)} if checked.ok else checked

static func validate(saved: Variant) -> Dictionary:
    if not State.exact(saved,KEYS) or not Wait.Safe._json_safe(saved) or saved.version!=VERSION or saved.kind!=KIND or not Wait.Safe.layout_matches(saved) or not State.integer(saved.physics_hz,60,60) or not State.integer(saved.source_frame,1,9007199254740991): return Wait.bad("progress_envelope_version_layout")
    var rules=Rules.new()
    if not rules.configure().ok or not rules.restore(saved.rules).ok: return Wait.bad("progress_rules_ledger")
    var state: Dictionary=rules.snapshot()
    if state.buffer_enabled: return Wait.bad("progress_external_buffer_not_open")
    for pilot: Dictionary in state.pilots.values():
        if pilot.peer_id!=0 or pilot.enabled: return Wait.bad("progress_external_holder_not_open")
    if not State.number(saved.rule_seconds,0,1e9) or not State.integer(saved.rule_usec,0,9007199254740991) or roundi(float(saved.rule_seconds)*1000000.0)!=int(saved.rule_usec) or int(rules.status().elapsed_usec)!=int(saved.rule_usec): return Wait.bad("progress_rule_clock")
    if not Wait.Custody.validate_progress_snapshot(saved.custody).ok or not State.exact(saved.custody.cargos,Rules.CASSETTES): return Wait.bad("progress_custody")
    if not Parts.validate_executor(saved.executor,state) or not State.validate_progress(saved.carrier,Rules.CARRIER): return Wait.bad("progress_executor_or_flight")
    if not Wait.Bench.validate_progress(saved.workbench,state).ok: return Wait.bad("progress_workbench_state")
    if not saved.executor.fields._action.is_empty() and not Rules._same(saved.executor.fields._action,state.pending_action):
        if int(saved.workbench.version)!=3: return Wait.bad("progress_work_receipt_boundary")
        for key: String in Wait.Executor.MATCH_KEYS:
            if saved.executor.fields._action[key]!=saved.workbench.history.first_work.action[key]: return Wait.bad("progress_work_receipt_identity")
    if int(state.services_consumed)==1 and not saved.executor.fields._waiting_for_beneficiary: return Wait.bad("progress_claimed_beneficiary_must_wait")
    if not Wait.Cooling.validate_snapshot(saved.cooling).ok or saved.cooling.paused: return Wait.bad("progress_cooling")
    var minimum: int=maxi(int(saved.cooling.charge_serial),int(saved.workbench.charge_serial))
    minimum=maxi(minimum,int(saved.cooling.axis.last_serial["1"]))
    if not State.integer(saved.device_serial,minimum,2147483647): return Wait.bad("progress_device_serial")
    var ids: Array=[Rules.CARRIER,Wait.Safe.BENEFICIARY_ID]+Rules.CASSETTES
    if not State.exact(saved.bodies,ids): return Wait.bad("progress_body_registry")
    for id: String in ids:
        if not validate_rigid(saved.bodies[id],id): return Wait.bad("progress_body:"+id)
    for pair: Array in [[Rules.CARRIER,saved.carrier],[Wait.Safe.BENEFICIARY_ID,saved.workbench.beneficiary]]:
        for key: String in ["pose","velocity","angular_velocity"]:
            if not Parts.same(saved.bodies[pair[0]][key],pair[1][key]): return Wait.bad("progress_flight_body_mismatch")
    if saved.carrier.health<saved.executor.fields._initial_health or int(saved.carrier.wait.collision_count)!=int(saved.executor.fields._initial_collisions): return Wait.bad("progress_carrier_baseline")
    var pending: Dictionary=state.pending_action
    for id: String in Rules.CASSETTES:
        var actual: Dictionary=saved.custody.cargos[id]
        var holder: String=str(state.cassettes[id].holder)
        if actual.phase=="carried":
            # A real pickup can exist one tick before its original receipt.
            if holder!=Rules.CARRIER and not (pending.get("kind")=="pick" and pending.cassette_id==id and holder==pending.source and saved.executor.fields._phase=="commit"): return Wait.bad("progress_carried_holder")
        elif actual.phase in ["dropping","settling","docked"]:
            if holder!=actual.berth and not (pending.get("kind")=="place" and pending.cassette_id==id and holder==Rules.CARRIER and actual.berth==pending.destination and saved.executor.fields._released): return Wait.bad("progress_reserved_holder")
        else: return Wait.bad("progress_unowned_cargo_not_normal_chain")
    return {"ok":true,"code":"valid_progress_no_current_contact_claim"}

static func rigid_snapshot(body: RigidBody3D) -> Dictionary:
    var row: Dictionary=Wait.rigid_snapshot(body,true)
    if row.is_empty(): return {}
    row["freeze"]=body.freeze
    return row

static func validate_rigid(row: Variant, id: String) -> bool:
    if not row is Dictionary or not row.get("freeze") is bool or not State.vector_valid(row.get("velocity"),15) or not State.vector_valid(row.get("angular_velocity"),8): return false
    var stationary: Dictionary=row.duplicate(true)
    stationary.erase("freeze")
    stationary.velocity=[0.0,0.0,0.0]
    stationary.angular_velocity=[0.0,0.0,0.0]
    return Wait.validate_rigid(stationary,id)
