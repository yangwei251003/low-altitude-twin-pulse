extends RefCounted
## General pre-order progress, including genuinely absent Bootstrap modules.
const Progress=preload("res://scripts/v3/gameplay/canal/canal_checkpoint/canal_progress_checkpoint.gd")
const Boot=preload("res://scripts/v3/gameplay/canal/canal_checkpoint/canal_bootstrap_progress.gd")
const Wait=Progress.Wait
const State=Wait.State
const Parts=Progress.Parts
const Rules=Wait.Rules
const KIND="canal_startup_checkpoint_v1"
const KEYS=["version","kind","mode","layout_sha256","physics_hz","source_frame","rules","custody","carrier","bodies","controller","workbench","cooling","device_serial","rule_seconds","rule_usec"]

static func capture(owner: Node3D) -> Dictionary:
    if owner._ordered or owner._restore_pending or owner._in_advance or owner._paused or owner._stopped or owner._last_frame!=Engine.get_physics_frames(): return Wait.bad("active_unordered_startup_frame_required")
    var context: Dictionary=owner._context
    var waiting: bool=owner._ready_for_order
    if context.is_empty() or not context.get("carrier") is State.Flight: return Wait.bad("startup_physical_context_required")
    var body_rows: Dictionary={Rules.CARRIER:Progress.rigid_snapshot(context.carrier)}
    for id: String in Rules.CASSETTES: body_rows[id]=Progress.rigid_snapshot(context.cargos[id])
    var workbench: Dictionary={}
    if waiting:
        workbench=owner.workbench.snapshot_wait_progress()
        body_rows[Wait.Safe.BENEFICIARY_ID]=Progress.rigid_snapshot(owner.workbench.beneficiary)
    var custody: Dictionary=context.custody.snapshot_progress() if context.get("custody")!=null else {}
    var cooling: Dictionary=owner.cooling.snapshot() if is_instance_valid(owner.cooling) else {}
    var row: Dictionary={"version":1,"kind":KIND,"mode":"waiting" if waiting else "bootstrap","layout_sha256":Wait.Safe.layout_fingerprint(),"physics_hz":Engine.physics_ticks_per_second,"source_frame":Engine.get_physics_frames(),"rules":context.rules.snapshot() if context.get("rules")!=null else {},"custody":custody,"carrier":State.capture_progress(context.carrier,Rules.CARRIER),"bodies":body_rows,"controller":Parts.pilot_snapshot(owner._waiting,context.cargos) if waiting else Boot.capture(owner.bootstrap),"workbench":workbench,"cooling":cooling,"device_serial":owner._device_serial,"rule_seconds":owner._rule_seconds,"rule_usec":owner._rule_usec}
    var checked: Dictionary=validate(row)
    return {"ok":true,"code":"captured_actual_preorder_progress","envelope":row} if checked.ok else checked

static func validate(row: Variant) -> Dictionary:
    if not State.exact(row,KEYS) or not Wait.Safe._json_safe(row) or row.version!=1 or row.kind!=KIND or row.mode not in ["bootstrap","waiting"] or not Wait.Safe.layout_matches(row) or not State.integer(row.physics_hz,60,60) or not State.integer(row.source_frame,1,9007199254740991): return Wait.bad("startup_schema_version_layout")
    for key: String in ["rules","custody","bodies","controller","workbench","cooling"]:
        if not row[key] is Dictionary: return Wait.bad("startup_module_type:"+key)
    var waiting: bool=row.mode=="waiting"
    var ids: Array=[Rules.CARRIER]+Rules.CASSETTES
    if waiting: ids.append(Wait.Safe.BENEFICIARY_ID)
    if not State.exact(row.bodies,ids) or not State.validate_progress(row.carrier,Rules.CARRIER): return Wait.bad("startup_body_registry_or_flight")
    for id: String in ids:
        if not Progress.validate_rigid(row.bodies[id],id): return Wait.bad("startup_rigid:"+id)
    for key: String in ["pose","velocity","angular_velocity"]:
        if not Parts.same(row.bodies[Rules.CARRIER][key],row.carrier[key]): return Wait.bad("startup_carrier_body_mismatch")
    var minimum_serial: int=0
    if not row.custody.is_empty() and (not Wait.Custody.validate_progress_snapshot(row.custody).ok or not State.exact(row.custody.cargos,Rules.CASSETTES)): return Wait.bad("startup_custody_registry")
    if not row.cooling.is_empty():
        if not Wait.Cooling.validate_snapshot(row.cooling).ok or row.cooling.paused: return Wait.bad("startup_cooling_state")
        minimum_serial=maxi(int(row.cooling.charge_serial),int(row.cooling.axis.last_serial["1"]))
    if not State.integer(row.device_serial,minimum_serial,2147483647): return Wait.bad("startup_device_serial")
    if waiting:
        var rules=Rules.new()
        if not rules.configure().ok or not rules.restore(row.rules).ok or not row.rules.pending_action.is_empty() or row.rules.jobs_completed!=0 or row.rules.service_credit!=0: return Wait.bad("startup_unordered_rules")
        if not Parts.validate_pilot(row.controller) or State.vec(row.controller.target)!=Wait.Executor.WAIT_POINT: return Wait.bad("startup_wait_controller")
        if not Wait.Bench.validate_wait_progress(row.workbench).ok or row.cooling.is_empty() or not Wait.Custody.validate_progress_snapshot(row.custody).ok: return Wait.bad("startup_wait_modules")
        if not State.number(row.rule_seconds,0,1e9) or not State.integer(row.rule_usec,0,9007199254740991) or roundi(float(row.rule_seconds)*1000000.0)!=int(row.rule_usec) or int(rules.status().elapsed_usec)!=int(row.rule_usec): return Wait.bad("startup_wait_clock")
        for key: String in ["pose","velocity","angular_velocity"]:
            if not Parts.same(row.bodies[Wait.Safe.BENEFICIARY_ID][key],row.workbench.beneficiary[key]): return Wait.bad("startup_beneficiary_body_mismatch")
        if row.custody.cargos[Rules.CASSETTES[0]].phase!="carried" or row.custody.cargos[Rules.CASSETTES[1]].phase not in ["settling","docked"] or row.custody.cargos[Rules.CASSETTES[1]].berth!=Rules.WORK: return Wait.bad("startup_wait_physical_holders")
    else:
        if not Boot.validate(row.controller) or not row.rules.is_empty() or not row.workbench.is_empty() or row.rule_seconds!=0 or row.rule_usec!=0: return Wait.bad("startup_absent_rules_bench_clock")
        var started: bool=bool(row.controller.fields._custody_started)
        if started:
            if not Wait.Custody.validate_progress_snapshot(row.custody).ok or row.cooling.is_empty(): return Wait.bad("startup_started_custody_cooling")
        elif not row.custody.is_empty() or not row.cooling.is_empty() or row.device_serial!=0: return Wait.bad("startup_modules_must_remain_absent")
        var frozen_carrier: bool=row.controller.phase in ["initial_contacts","seating"]
        if row.bodies[Rules.CARRIER].freeze!=frozen_carrier: return Wait.bad("startup_original_carrier_freeze")
    for id: String in Rules.CASSETTES:
        if row.bodies[id].freeze: return Wait.bad("startup_original_cargo_must_simulate")
    return {"ok":true,"code":"valid_startup_no_created_absent_modules_or_contact_credit"}
