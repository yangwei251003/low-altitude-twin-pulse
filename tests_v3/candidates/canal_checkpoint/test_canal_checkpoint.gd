extends "res://tests_v3/candidates/canal_workbench/workbench_test_base.gd"
## One real production-I2 exchange/work/departure run, then capture-only checks.
## Inherits the original explicit site/power fixtures; no simulated receipts,
## cargo/aircraft pose writes, service consumption, restore or second route run.
const Checkpoint = preload("res://scripts/v3/candidates/canal_checkpoint/canal_checkpoint.gd")
const Cooling = preload("res://scripts/v3/candidates/canal_cooling_station/cooling_station.gd")
const RestoreDiagnostics = preload("res://tests_v3/candidates/canal_cooling_station/restore_precision_diagnostics.gd")
var checkpoint_evidence: Dictionary = {}
var checkpoint_checks_started := false
var cooling: Node3D
var restoring_device := false
var cooling_handoff_frames := 0

func _exchange_mode() -> bool:
    return true

func _collect_inputs() -> void:
    super._collect_inputs()
    for path: String in ["res://scripts/v3/candidates/canal_checkpoint/canal_checkpoint.gd","res://tests_v3/candidates/canal_checkpoint/test_canal_checkpoint.gd","res://scripts/v3/candidates/canal_cooling_station/cooling_station.gd","res://scripts/v3/environment/twin_guided_axis.gd"]:
        inputs[path] = FileAccess.get_sha256(path)
    inputs["res://tests_v3/candidates/canal_cooling_station/restore_precision_diagnostics.gd"] = FileAccess.get_sha256("res://tests_v3/candidates/canal_cooling_station/restore_precision_diagnostics.gd")

func _physics() -> void:
    await super._physics()
    if context.is_empty(): return
    if not is_instance_valid(cooling):
        cooling = Cooling.new()
        world.add_child(cooling)
        var configured: Dictionary = cooling.configure(context.cargos,context.berths,context.custody,true)
        if not _check(configured.ok,"actual cooling device fits unchanged exchange world",configured): return
        _check(cooling.apply_charge(35,7,true).ok,"declared host fixture energizes real cooling relay; valve remains shut")
    if not restoring_device:
        var moved: Dictionary = cooling.advance(DT,true)
        if not moved.ok: _check(false,"actual cooling device advances once in host physics frame",moved)

func _thermal_clock() -> void:
    thermal_ticks += 1
    var next_usec: int = roundi(float(thermal_ticks)*1000000.0/60.0)
    var facts: Dictionary = cooling.facts()
    var state: Dictionary = context.rules.snapshot()
    var pending: Dictionary = state.pending_action
    var physical: Dictionary = executor.report()
    # Exact real drop/commit handoff, matching the current playable contract.
    # Keep all other physical/Rules mismatches visible to Rules validation.
    var handoff: bool = pending.get("kind","") == "place" and physical.phase in ["fall","commit"] and physical.released and context.carrier.cargo_items.is_empty()
    if handoff:
        for key: String in Executor.MATCH_KEYS:
            if not physical.action.has(key) or physical.action[key] != pending[key]: handoff = false
    if handoff:
        var berth: String = str(pending.destination)
        var id: String = str(pending.cassette_id)
        if berth in [Rules.SOUTH_0,Rules.SOUTH_1] and facts.contacts[berth] == id and state.cassettes[id].holder == Rules.CARRIER and context.custody.support_info(id,berth).get("supported",false):
            facts.contacts[berth] = ""
            cooling_handoff_frames += 1
    var advanced: Dictionary = context.rules.step(next_usec-thermal_elapsed,facts,true,false)
    thermal_elapsed = next_usec
    if not advanced.ok: _check(false,"single rule clock consumes actual station facts with exact handoff",advanced)

func _finish() -> void:
    if finished: return
    if not checkpoint_checks_started and failures.is_empty() and is_instance_valid(bench):
        checkpoint_checks_started = true
        await _checkpoint_cases()
    await super._finish()

func _result() -> Dictionary:
    var result: Dictionary = super._result()
    result.checkpoint_evidence = checkpoint_evidence.duplicate(true)
    result.checkpoint_scope = "v3 complete safe entity/device state capture plus fresh cooling-device restore only; no whole-scene restore or Store integration"
    result.cooling_handoff_frames = cooling_handoff_frames
    return result

func _checkpoint_cases() -> void:
    var checkpoint_script: Script = Checkpoint
    if not _check(checkpoint_script.can_instantiate(),"checkpoint Script instantiates before tests"): return
    # Real bounded slider motion is allowed in a checkpoint; no zero-velocity
    # requirement is invented for this explicitly integrated mechanism.
    if not _check(cooling.apply_impulse(Vector3(0,0,.9),9,true).ok,"real valve impulse before checkpoint observation"): return
    await _step_bench()
    var observer = Checkpoint.new()
    var before: Dictionary = _read_only_state()
    var denied: Dictionary = observer.capture(context,executor,bench,cooling,false)
    _check(not denied.ok and denied.code == "authority_required" and before == _read_only_state(),"nonhost capture neither advances nor writes host physics")
    var paused: Dictionary = observer.capture(context,executor,bench,cooling,true,true)
    _check(not paused.ok and paused.code == "paused" and before == _read_only_state(),"paused observation produces no checkpoint or gameplay change")
    var first: Dictionary = observer.capture(context,executor,bench,cooling)
    checkpoint_evidence.first = first.duplicate(true)
    if not _check(not first.ok and first.code == "stability_pending" and first.observed_usec == 0,"actual terminal observation begins with zero credited intervals",first): return
    var same: Dictionary = observer.capture(context,executor,bench,cooling)
    _check(same == first and before == _read_only_state(),"same-frame repeat accrues no stability and capture is read-only")
    var captured: Dictionary = {}
    var samples: Array = []
    # At most one extra second after the original real ten-step route and work.
    # Existing host controllers continue; checkpoint itself never drives them.
    for i in 60:
        await _step_bench()
        var state_before: Dictionary = _read_only_state()
        var sample: Dictionary = observer.capture(context,executor,bench,cooling)
        if state_before != _read_only_state():
            _check(false,"observation may not alter Rules/Custody/commands/poses")
            return
        samples.append({"frame":Engine.get_physics_frames(),"code":sample.code,"observed_usec":sample.get("observed_usec",sample.get("envelope",{}).get("physics",{}).get("observed_usec",0))})
        if sample.ok:
            captured = sample
            break
        if sample.code != "stability_pending":
            checkpoint_evidence.first_live_failure = sample.duplicate(true)
            break
    checkpoint_evidence.samples = samples
    if not _check(not captured.is_empty() and captured.ok,"actual stable completed scene yields capture-only envelope",{"last":samples.back() if not samples.is_empty() else {},"failure":checkpoint_evidence.get("first_live_failure",{})}): return
    var envelope: Dictionary = captured.envelope.duplicate(true)
    checkpoint_evidence.envelope = envelope.duplicate(true)
    _check(envelope.physics.frame == Engine.get_physics_frames() and envelope.physics.observed_usec == 350000 and envelope.rules == context.rules.snapshot(),"one current physics frame plus original Rules ledger captured exactly")
    _check(envelope.version == 3 and envelope.checkpoint.cooling == cooling.snapshot() and float(envelope.checkpoint.cooling.axis.velocity_mps) > 0.0,"v3 captures same-frame real bounded moving valve without forcing it stationary",envelope.checkpoint.cooling)
    _check(envelope.rules.jobs_completed == 1 and envelope.rules.services_consumed == 0 and envelope.rules.service_credit == 1 and envelope.history.first_work.action.serial == 11 and executor.report().receipt_count == 10,"ten actual transport receipts and work11 retained without service manufacture")
    var encoded: String = JSON.stringify(envelope,"",true,true)
    var decoded: Variant = JSON.parse_string(encoded)
    var valid: Dictionary = Checkpoint.validate(decoded)
    _check(valid.ok,"strict envelope accepts real JSON float-number boundary",valid)
    _check(encoded.find("RID(") == -1 and encoded.find("instance_id") == -1 and encoded.find("Vector3") == -1,"persistent identity contains no transient RID/node or Variant string placeholders")
    _reject_mutation(envelope,"version",1,"unknown checkpoint version rejected")
    var bad: Dictionary = envelope.duplicate(true)
    bad.layout.sha256 = "0".repeat(64)
    _check(not Checkpoint.validate(bad).ok,"foreign layout rejected before any entity construction")
    bad = envelope.duplicate(true)
    bad.unexpected = true
    _check(not Checkpoint.validate(bad).ok,"unknown envelope fields rejected")
    bad = envelope.duplicate(true)
    bad.checkpoint.cargos[Rules.CASSETTES[1]].holder = bad.checkpoint.cargos[Rules.CASSETTES[0]].holder
    _check(not Checkpoint.validate(bad).ok,"two real cargo IDs cannot serialize one occupied berth")
    bad = envelope.duplicate(true)
    bad.rules.cassettes[Rules.CASSETTES[0]].energy_mj += 1
    _check(not Checkpoint.validate(bad).ok,"original water and thermal conservation validation retained")
    bad = envelope.duplicate(true)
    bad.checkpoint.carrier.pose[0] = 0.0
    _check(not Checkpoint.validate(bad).ok,"degenerate basis rejected")
    bad = envelope.duplicate(true)
    bad.checkpoint.carrier.velocity[0] = NAN
    _check(not Checkpoint.validate(bad).ok,"non-finite physics values rejected")
    bad = envelope.duplicate(true)
    bad.checkpoint.cargos[Rules.CASSETTES[0]].pose[10] += .10
    _check(not Checkpoint.validate(bad).ok,"floating serialized cargo cannot claim original support")
    bad = envelope.duplicate(true)
    bad.history.first_work.action.serial = int(envelope.rules.action_serial)+1
    _check(not Checkpoint.validate(bad).ok,"future work receipt cannot accompany older Rules state")
    bad = envelope.duplicate(true)
    bad.checkpoint.cooling.contact_observation[Rules.SOUTH_0] = Rules.CASSETTES[0]
    _check(not Checkpoint.validate(bad).ok,"checkpoint device observation must match actual saved custody")
    var intact: Dictionary = _read_only_state()
    captured.envelope.rules.cassettes[Rules.CASSETTES[0]].energy_mj += 42
    var again: Dictionary = observer.capture(context,executor,bench,cooling)
    _check(again.ok and again.envelope.rules == intact.rules and intact == _read_only_state(),"returned envelope mutation cannot alias host or subsequent capture")
    var reset: Dictionary = observer.capture(context,executor,bench,cooling,true,true)
    var restarted: Dictionary = observer.capture(context,executor,bench,cooling)
    _check(not reset.ok and restarted.code == "stability_pending" and restarted.observed_usec == 0,"paused observer discards old continuous-stability credit")
    await _cooling_restore_cases()
    # Explicit destructive negative fixture AFTER a successful full physical
    # exchange: a real upward force removes support; no pose or velocity writes.
    # Original host then correctly faults. No automatic recovery is claimed.
    expected_custody_fault = true
    var cargo: RigidBody3D = context.cargos[Rules.CASSETTES[0]]
    var berth: String = str(context.rules.snapshot().cassettes[Rules.CASSETTES[0]].holder)
    cargo.apply_central_impulse(Vector3.UP*1.0)
    var unsupported: Dictionary = {}
    var rejected: Dictionary = {}
    for i in 12:
        await _step_bench()
        var support: Dictionary = context.custody.support_info(Rules.CASSETTES[0],berth)
        var attempt: Dictionary = observer.capture(context,executor,bench,cooling)
        if not support.supported:
            unsupported = support
            rejected = attempt
            break
    checkpoint_evidence.support_loss = {"physical":unsupported,"capture":rejected,"custody":context.custody.report(),"executor":executor.report().phase}
    _check(not unsupported.is_empty() and not unsupported.supported and not rejected.is_empty() and not rejected.ok,"actual support loss refuses fresh checkpoint despite completed work",checkpoint_evidence.support_loss)
    _check(context.rules.snapshot().jobs_completed == 1 and context.rules.snapshot().service_credit == 1 and bench.report().receipt_count == 1,"physical instability never erases or repeats original completed result")
    _check(Checkpoint.validate(envelope).ok,"old valid serialized observation remains internally valid; it is not current-contact authorization")
    checkpoint_evidence.json_bytes = encoded.to_utf8_buffer().size()
    checkpoint_evidence.restore_implemented = false
    checkpoint_evidence.cooling_device_restore_only = true

func _cooling_restore_cases() -> void:
    var saved: Dictionary = cooling.snapshot().duplicate(true)
    var parsed: Variant = JSON.parse_string(JSON.stringify(saved,"",true,true))
    _check(Cooling.validate_snapshot(parsed).ok,"device state survives actual JSON boundary")
    var live_before: Dictionary = cooling.report()
    var refused: Dictionary = cooling.restore_fresh(parsed,true)
    _check(not refused.ok and refused.code == "fresh_device_required" and cooling.report() == live_before,"restore cannot teleport a device which has already run",refused)
    # Only this device is destroyed/rebuilt. Cargo, Custody, Rules, flights,
    # workbench and world are kept alive and continue their normal host steps.
    restoring_device = true
    cooling.free()
    cooling = Cooling.new()
    world.add_child(cooling)
    if not _check(cooling.configure(context.cargos,context.berths,context.custody,true).ok,"fresh replacement cooling device initializes in real cleared space"): return
    var fresh: Dictionary = cooling.snapshot()
    var fresh_pose: Transform3D = cooling.valve.global_transform
    var wrong: Dictionary = saved.duplicate(true)
    wrong.axis.velocity_mps = INF
    var bad: Dictionary = cooling.restore_fresh(wrong,true)
    _check(not bad.ok and cooling.snapshot() == fresh and cooling.valve.global_transform == fresh_pose,"bad restored axis atomically preserves fresh device")
    wrong = saved.duplicate(true)
    wrong.axis.last_serial["2"] = 12
    _check(not cooling.restore_fresh(wrong,true).ok and cooling.snapshot() == fresh,"foreign axis actor refused without losing fresh restore opportunity")
    wrong = saved.duplicate(true)
    wrong.axis.last_serial["1"] = -1
    _check(not cooling.restore_fresh(wrong,true).ok and cooling.snapshot() == fresh,"moving valve cannot restore with a reset input sequence")
    wrong = saved.duplicate(true)
    wrong.extra = 1
    _check(not cooling.restore_fresh(wrong,true).ok and cooling.snapshot() == fresh,"unknown device field atomically refused")
    _check(not cooling.restore_fresh(parsed,false).ok and cooling.snapshot() == fresh,"nonhost restore cannot change fresh mechanism")
    var blocker: StaticBody3D = _obstacle("QA_CoolingRestoreObstacle",Cooling.VALVE_CLOSED+Vector3(0,0,.15),Vector3(.5,.18,.02))
    await _step_bench()
    var blocked: Dictionary = cooling.restore_fresh(parsed,true)
    _check(not blocked.ok and blocked.code == "restore_space_obstructed" and cooling.snapshot() == fresh and cooling.valve.global_transform == fresh_pose,"fresh restore sweeps actual closed-to-saved path and preserves all state when blocked",blocked)
    blocker.free()
    await _step_bench()
    var restored: Dictionary = cooling.restore_fresh(parsed,true)
    if not _check(restored.ok,"fresh-only device restore accepts clear actual space",restored): return
    var physical_pose: Transform3D = PhysicsServer3D.body_get_state(cooling.valve.get_rid(),PhysicsServer3D.BODY_STATE_TRANSFORM)
    var expected: Vector3 = Cooling.VALVE_CLOSED+Vector3(0,0,float(saved.axis.position_m))
    var restore_diagnostics: Dictionary = RestoreDiagnostics.inspect(saved,parsed,cooling.snapshot(),cooling.valve.global_position,physical_pose.origin,expected)
    checkpoint_evidence.cooling_restore_precision = restore_diagnostics
    var restore_semantics: Dictionary = RestoreDiagnostics.semantic(saved,cooling.snapshot(),cooling.valve.global_position,physical_pose.origin,expected)
    checkpoint_evidence.cooling_restore_semantics = restore_semantics
    _check(restore_semantics.ok,"fresh restore synchronizes real collider, charge, revision, position and velocity",{"state":cooling.snapshot(),"physics_pose":physical_pose,"precision":restore_diagnostics,"semantics":restore_semantics})
    var after: Dictionary = cooling.snapshot()
    _check(not cooling.apply_charge(1,int(saved.charge_serial),true).ok and not cooling.apply_impulse(Vector3(0,0,.1),int(saved.axis.last_serial["1"]),true).ok and cooling.snapshot() == after,"restored charge and impulse serials reject replay")
    _check(not cooling.restore_fresh(saved,true).ok and cooling.snapshot() == after,"second restore is refused even before first post-restore tick")
    _check(not cooling.capture_state(Engine.get_physics_frames()).ok,"saved contact observation cannot satisfy new same-frame capture")
    var candidate = Cooling.Axis.new()
    candidate.configure(Cooling.axis_config())
    candidate.restore(saved.axis,false)
    var next: Dictionary = candidate.preview(DT)
    restoring_device = false
    await _step_bench()
    var now: Dictionary = cooling.snapshot()
    _check(absf(float(now.axis.position_m)-float(next.position_m)) < .000001 and absf(float(now.axis.velocity_mps)-float(next.velocity_mps)) < .000001 and float(now.axis.velocity_mps) > 0.0,"first real restored tick continues saved bounded velocity without queued duplicate impulse",{"expected":next,"actual":now.axis})
    _check(cooling.capture_state(Engine.get_physics_frames()).ok and cooling.facts().contacts == now.contact_observation,"post-restore capture uses freshly reacquired real support",cooling.report())
    checkpoint_evidence.cooling_restore = {"saved":saved,"restored_state":after,"first_real_tick":now,"only_device_rebuilt":true}

func _reject_mutation(envelope: Dictionary, key: String, value: Variant, label: String) -> void:
    var changed: Dictionary = envelope.duplicate(true)
    changed[key] = value
    _check(not Checkpoint.validate(changed).ok,label)

func _read_only_state() -> Dictionary:
    var cargo_state: Dictionary = {}
    for id: String in Rules.CASSETTES:
        var cargo: RigidBody3D = context.cargos[id]
        cargo_state[id] = {"pose":cargo.global_transform,"velocity":cargo.linear_velocity,"angular_velocity":cargo.angular_velocity,"layer":cargo.collision_layer,"mask":cargo.collision_mask}
    return {"rules":context.rules.snapshot(),"custody":context.custody.report(),"executor":executor.report(),"workbench":bench.report(),"cooling":cooling.snapshot(),"cooling_pose":cooling.valve.global_transform,
        "carrier_pose":context.carrier.global_transform,"carrier_velocity":context.carrier.linear_velocity,"carrier_command":context.carrier.command.duplicate(true),
        "beneficiary_pose":bench.beneficiary.global_transform,"beneficiary_velocity":bench.beneficiary.linear_velocity,"beneficiary_command":bench.beneficiary.command.duplicate(true),"cargos":cargo_state}
