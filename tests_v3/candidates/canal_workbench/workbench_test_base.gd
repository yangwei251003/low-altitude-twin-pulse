extends SceneTree
## Explicit QA initialization only. All subsequent cargo/Flight motion uses
## real forces, existing Bootstrap/Executor/Custody and the candidate tools.
const World = preload("res://scripts/v3/twin_test_world.gd")
const Bootstrap = preload("res://scripts/v3/candidates/canal_transport_executor/canal_transport_bootstrap.gd")
const Pilot = preload("res://scripts/v3/candidates/canal_transport_physics/transport_pilot.gd")
const Executor = preload("res://scripts/v3/candidates/canal_transport_executor/canal_transport_executor.gd")
const Bench = preload("res://scripts/v3/candidates/canal_workbench/workbench.gd")
const Departure = preload("res://scripts/v3/candidates/canal_workbench/beneficiary_departure.gd")
const Flight = preload("res://scripts/v2/flight_body.gd")
const Catalog = preload("res://scripts/v2/catalog.gd")
const Rules = preload("res://scripts/v3/candidates/canal_service_loop/canal_service_runtime.gd")
const DT := 1.0/60.0
const OBSERVERS := [Vector3(18,5.75,-10.6),Vector3(18,2.7,-10.8),Vector3(17.8,2.7,-7.85)]
var checks := 0
var failures: Array = []
var records: Array = []
var inputs: Dictionary = {}
var finished := false
var vp: SubViewport
var world: World
var boot: RefCounted
var executor: RefCounted
var bench: Node3D
var context: Dictionary = {}
var ticks := 0
var thermal_ticks := 0
var thermal_elapsed := 0
var before_lines: Array = []
var lift_command_checks := 0
var lift_deadband_samples := 0
var lift_max_fallback_error := 0.0
var lift_command_consistent := true
var invalid_contact_evidence: Dictionary = {}
var wait_pilot: RefCounted
var executor_running := false
var expected_custody_fault := false
var unexpected_executor_fault: Dictionary = {}
var expected_executor_fault: Dictionary = {}
var hold_bindings: Dictionary = {}
var hold_evidence: Dictionary = {"samples":0,"external_samples":0,"idle_samples":0,
    "full_probe_samples":0,"binding_valid":true,"max_external_horizontal_error_m":0.0,
    "first_external":{},"last_external":{}}
var cleanup_evidence: Dictionary = {}
var handoff_evidence: Dictionary = {}
class ErrorLogger extends Logger:
    var errors: Array = []
    func _log_error(function: String,file: String,line: int,code: String,rationale: String,_notify: bool,error_type: int,_backtraces: Array[ScriptBacktrace]) -> void:
        errors.append({"function":function,"file":file,"line":line,"code":code,"rationale":rationale,"type":error_type})
var logger := ErrorLogger.new()

func _exchange_mode() -> bool:
    return false

func _init() -> void:
    OS.add_logger(logger)
    _run.call_deferred()

func _run() -> void:
    create_timer(275 if _exchange_mode() else 165).timeout.connect(func():
        if not finished:
            print("WORKBENCH_TIMEOUT "+JSON.stringify(_result()))
            quit(2))
    for script: Script in [World,Bootstrap,Executor,Bench,Departure,Pilot]:
        if not _check(script.can_instantiate(),"actual dependency instantiates",{"path":script.resource_path}):
            await _finish()
            return
    _collect_inputs()
    if not _check(Engine.physics_ticks_per_second == 60 and Engine.time_scale == 1.0,"normal unaccelerated 60 Hz"):
        await _finish()
        return
    if not await _setup():
        await _finish()
        return
    _boundaries()
    if not _exchange_mode(): _thermal(Rules.CASSETTES[1],-25000)
    if not await _reach_work():
        await _finish()
        return
    _executor_authority_boundary()
    var pending: Dictionary = context.rules.snapshot().pending_action
    _check(pending.kind == "work" and int(pending.serial) == (11 if _exchange_mode() else 1),"real rules select the appropriate pending work",pending)
    _check(executor.report().receipt_count == (10 if _exchange_mode() else 0),"exchange uses all ten real receipts; local cooling avoids cargo moves",executor.report())
    if _exchange_mode(): _check(_physical_work_holder() == Rules.CASSETTES[0],"real replacement cold cartridge now occupies WORK")
    else: _check(_physical_work_holder() == Rules.CASSETTES[1],"local cooling retains the original hot cartridge on its actual support")
    var still: Vector3 = bench.head.global_position
    for i in 12: await _step_bench()
    _check(bench.head.global_position == still and bench.report().code == "work_power_required" and context.rules.snapshot().jobs_completed == 0,"real unpowered target does not start tool or award work",bench.report())
    _check(bench.targets().size() == 1 and bench.targets()[0].body == bench.power_target and bench.power_target.collision_layer != 0,"supply is a real target with collision and state")
    _check(bench.apply_charge(20,1,true,false).ok,"declared trusted-host charge fixture powers actual target")
    _check(not bench.apply_charge(20,1,true,false).ok,"duplicate charge input rejected")
    var scanning := false
    for i in 1500:
        await _step_bench()
        if bench.report().phase == "fault" or not unexpected_executor_fault.is_empty(): break
        if bench.report().phase == "scan_out" and float(bench.report().scan_distance_m) > .05:
            scanning = true
            break
    if not _check(scanning,"actual probe reaches the first collider-derived measurement",bench.report()):
        await _finish()
        return
    if not _exchange_mode(): await _interruptions()
    if not failures.is_empty():
        await _finish()
        return
    # Roof is an explicitly added external QA obstacle. It is never hidden or
    # ignored by the departure query; removed only after actual blocked proof.
    var roof: StaticBody3D = _obstacle("QA_DepartureRoof",Vector3(6.6,1.65,6),Vector3(2,.15,2))
    var work_committed := false
    for i in 2000:
        await _step_bench()
        if bench.report().committed:
            work_committed = true
            break
        if bench.report().phase == "fault" or not unexpected_executor_fault.is_empty(): break
    if not _check(work_committed,"swept physical out-and-back tool returns before one real work receipt",bench.report()):
        roof.free()
        await _finish()
        return
    var committed: Dictionary = context.rules.snapshot()
    _check(committed.jobs_completed == 1 and committed.service_credit == 1 and committed.thermal_ledger.work_added == Rules.WORK_HEAT_MJ and bench.report().receipt_count == 1,"exact service cap and existing 25 kJ work ledger retained",committed.thermal_ledger)
    _check(bench.report().measurements.size() == 3 and absf(float(bench.report().scan_distance_m)-1.4) < .0001 and bench.head.global_position.distance_to(Bench.PARK) < .000001,"actual full scan and final parked endpoint",bench.report())
    if not _exchange_mode(): await _blocked_handoff()
    var trapped := false
    var blocked_stability_cleared := true
    var blocked_stability_samples := 0
    for i in 60:
        await _step_bench()
        var departure: Dictionary = bench.report().departure
        trapped = trapped or str(departure.get("code","")).begins_with("lift_")
        if str(departure.get("code","")).begins_with("lift_"):
            blocked_stability_samples += 1
            blocked_stability_cleared = blocked_stability_cleared and float(departure.get("stable_seconds",-1.0)) == 0.0
    _check(blocked_stability_samples > 0 and blocked_stability_cleared,"every blocked lift frame discards earlier endpoint stability",{"samples":blocked_stability_samples,"all_cleared":blocked_stability_cleared})
    _check(trapped and context.rules.snapshot().jobs_completed == 1 and bench.report().receipt_count == 1 and bench.beneficiary.global_position.y < 1.2,"real roof blocks takeoff but never revokes/repeats committed work",bench.report())
    roof.free()
    var departed := false
    var previous: String = ""
    for i in 4800:
        await _step_bench()
        var row: Dictionary = bench.report()
        if row.phase != previous or i%120 == 0:
            records.append({"stage":"departure","bench":row,"sample":_sample()})
            previous = row.phase
        if row.phase == "fault" or not unexpected_executor_fault.is_empty(): break
        if row.departure.get("arrived",false):
            departed = true
            break
    _check(departed,"same actual beneficiary leaves support and reaches short production canal route",bench.report())
    _check(lift_command_checks > 0 and lift_command_consistent,"every observed lift command keeps height fallback equal to swept climb",{"samples":lift_command_checks,"deadband_samples":lift_deadband_samples,"max_error_mps":lift_max_fallback_error})
    _check(bench.beneficiary.health == bench.beneficiary.maximum_health and bench.beneficiary.collision_count == 0 and not bench.beneficiary.water_contact,"beneficiary flew without contact, water damage, teleport or healing",_sample())
    for i in 20: await _step_bench()
    _check(bench.report().receipt_count == 1 and context.rules.snapshot().service_credit == 1 and context.rules.snapshot().services_consumed == 0,"repeated advancing after departure cannot consume or duplicate service")
    if failures.is_empty(): await _verify_host_continuation(int(pending.serial))
    _check(unexpected_executor_fault.is_empty(),"continuous host executor stays valid during work and subsequent transport",unexpected_executor_fault)
    _check(int(hold_evidence.external_samples) >= 100 and int(hold_evidence.full_probe_samples) == int(hold_evidence.samples) and bool(hold_evidence.binding_valid),"external wait uses a stable original Pilot target/serial and full live sweep each active tick",hold_evidence)
    _check(float(hold_evidence.max_external_horizontal_error_m) <= .20,"normal powered work keeps confirmed anchor within unchanged source gate",hold_evidence)
    _check(context.carrier.health == context.carrier.maximum_health and context.carrier.collision_count == 0 and not context.carrier.water_contact,"continuous waiting and cleanup preserve actual carrier contact/water/health gates",_sample())
    _check(_rays() == before_lines,"all old cabinet first hits remain unchanged after work and departure")
    if not _exchange_mode() and failures.is_empty(): await _identity_negative()
    await _finish()

func _setup() -> bool:
    thermal_ticks = 0
    thermal_elapsed = 0
    executor_running = false
    expected_custody_fault = false
    unexpected_executor_fault.clear()
    expected_executor_fault.clear()
    hold_bindings.clear()
    vp = SubViewport.new()
    vp.size = Vector2i(32,32)
    vp.own_world_3d = true
    vp.world_3d = World3D.new()
    vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
    root.add_child(vp)
    world = World.new()
    vp.add_child(world)
    world.build("I2",{},true)
    if not _check(world.build_errors.is_empty() and world.waterfront_install.get("ok",false),"actual production I2/four facilities/canal builds",{"errors":world.build_errors}): return false
    _check(is_instance_valid(world.clinic) and is_instance_valid(world.distribution) and is_instance_valid(world.trial) and is_instance_valid(world.shared_access),"all production facilities retained")
    var open: Dictionary = world.distribution.snapshot()
    open.axis.position_m = 1.2
    open.axis.velocity_mps = 0.0
    open.door_fraction = 1.0
    open.electric_latched = true
    _check(world.distribution.apply_snapshot(open).ok,"declared open-cabinet saved-pose fixture for original thirty rays")
    for i in 3: await _physics()
    before_lines = _rays()
    var expected_lines: Array = []
    for _observer in OBSERVERS:
        for spec: Dictionary in world.distribution.layout().panels:
            for _sample in 5: expected_lines.append(str(world.distribution.panel_bodies[spec.id].name))
    _check(before_lines.size() == 30 and before_lines == expected_lines,"thirty baseline rays first hit their actual original panels",{"actual":before_lines,"expected":expected_lines})
    boot = Bootstrap.new()
    var created: Dictionary = boot.create(world,world.sample_environment,true)
    if not _check(created.ok,"unchanged physical transport bootstrap creates candidate fixture",created): return false
    var ready := false
    for i in 3300:
        await _physics()
        var result: Dictionary = boot.tick(DT,true,false)
        if not result.ok: break
        if result.ready:
            ready = true
            break
    if not _check(ready,"real initial support, pickup, lift and WAIT bootstrap",boot.report()): return false
    context = boot.context()
    executor = Executor.new()
    var configured: Dictionary = executor.configure(context.carrier,context.cargos,context.berths,context.custody,context.rules,world.sample_environment,true)
    if not _check(configured.ok,"executor binds real WAIT context",configured): return false
    bench = Bench.new()
    world.add_child(bench)
    var new_parts: Dictionary = bench.configure(context,true)
    if not _check(new_parts.ok,"new structure passes actual production collision preflight",new_parts): return false
    # Explicit pre-order QA setup: keep the already confirmed WAIT through real
    # flight input while the new beneficiary settles. Do not request transport
    # before the test chooses its local-cooling or exchange input.
    wait_pilot = Pilot.new()
    if not _check(wait_pilot.bind(context.carrier) and wait_pilot.go_to(Executor.WAIT_POINT,1),"pre-order setup uses real WAIT controller, not pose correction"): return false
    for i in 45: await _step_bench()
    _check(Departure.support_proof(bench.beneficiary,bench.rack).supported,"beneficiary really lands on original candidate support",Departure.support_proof(bench.beneficiary,bench.rack))
    _check(_rays() == before_lines,"new workbench leaves original thirty actual rays unchanged")
    _routes()
    return failures.is_empty()

func _reach_work() -> bool:
    executor_running = true
    var ready := false
    for i in (14000 if _exchange_mode() else 60):
        await _physics()
        _thermal_clock()
        var row: Dictionary = executor.tick(DT,true,false)
        _record_executor(row)
        bench.advance(DT,true,false)
        if i%180 == 0: records.append({"stage":"transport","executor":row,"bench":bench.report(),"sample":_sample()})
        if not row.ok or bench.report().phase == "fault": break
        if row.phase == "awaiting_external" and row.action.get("kind","") == "work":
            ready = true
            break
    return _check(ready,"continuous executor yields actual pending work without fake receipt",executor.report())

func _step_bench(paused: bool = false) -> void:
    await _physics()
    if not paused: _thermal_clock()
    if executor_running:
        var already_faulted: bool = executor.report().phase == "fault"
        var row: Dictionary = executor.tick(DT,true,paused)
        if not paused: _record_executor(row)
        # Only the deliberate cargo-displacement negative fixture continues
        # contact sampling after Executor has correctly faulted. The first fault
        # frame already ran Custody.step; subsequent frames have one explicit QA
        # owner. This is not production recovery or another transport controller.
        if expected_custody_fault and already_faulted and not paused:
            var sampled: Dictionary = context.custody.step(DT,true,false)
            if not sampled.ok: _check(false,"negative fixture retains one custody contact sampler",sampled)
    else:
        if not paused:
            var setup_sample: Dictionary = context.custody.step(DT,true,false)
            if not setup_sample.ok: _check(false,"single pre-order owner advances actual custody",setup_sample)
        context.carrier.environment_sample = world.sample_environment(context.carrier.global_position)
        wait_pilot.tick(DT,true,paused)
    bench.advance(DT,true,paused)
    var departure: Dictionary = bench.report().departure
    if not paused and departure.get("phase","") == "lift" and departure.get("code","") == "lifting":
        var controller: Dictionary = departure.controller
        var fallback: float = (float(controller.command_hold_height)-float(controller.command_body_y))*2.0
        var error: float = absf(fallback-float(controller.swept_climb_mps))
        lift_command_checks += 1
        lift_max_fallback_error = maxf(lift_max_fallback_error,error)
        lift_command_consistent = lift_command_consistent and error <= .00001
        if absf(float(controller.command_vertical)) <= .02: lift_deadband_samples += 1

func _record_executor(row: Dictionary) -> void:
    if not row.ok:
        if expected_custody_fault:
            if expected_executor_fault.is_empty(): expected_executor_fault = row.duplicate(true)
        elif unexpected_executor_fault.is_empty():
            unexpected_executor_fault = {"executor":row.duplicate(true),"sample":_sample()}
            _check(false,"continuous host executor remains healthy",unexpected_executor_fault)
        return
    var hold: Dictionary = row.get("hold",{})
    if hold.is_empty() or row.phase not in ["idle","awaiting_external"]: return
    var action: Dictionary = hold.action
    var key: String = str(hold.anchor)+":"+str(action.get("serial",0))
    var binding: Dictionary = {"controller_serial":hold.controller_serial,"target":hold.target,"action":action.duplicate(true)}
    if hold_bindings.has(key):
        hold_evidence.binding_valid = bool(hold_evidence.binding_valid) and hold_bindings[key] == binding
    else: hold_bindings[key] = binding
    var controller: Dictionary = row.controller
    hold_evidence.binding_valid = bool(hold_evidence.binding_valid) and controller.get("serial",-1) == hold.controller_serial and controller.get("target",Vector3.INF) == hold.target
    hold_evidence.samples = int(hold_evidence.samples)+1
    var plan: Dictionary = controller.get("speed_plan",{})
    if plan.has("actual_probe") and controller.has("probe"):
        hold_evidence.full_probe_samples = int(hold_evidence.full_probe_samples)+1
    if row.action.get("kind","") == "work":
        hold_evidence.external_samples = int(hold_evidence.external_samples)+1
        var offset: Vector3 = context.carrier.global_position-Vector3(hold.target)
        var horizontal: float = Vector2(offset.x,offset.z).length()
        hold_evidence.max_external_horizontal_error_m = maxf(float(hold_evidence.max_external_horizontal_error_m),horizontal)
        var sample: Dictionary = {"frame":Engine.get_physics_frames(),"hold":hold.duplicate(true),
            "carrier":context.carrier.global_position,"velocity":context.carrier.linear_velocity,
            "horizontal_error_m":horizontal,"environment":context.carrier.environment_sample.duplicate(true),
            "controller":controller.duplicate(true)}
        if hold_evidence.first_external.is_empty(): hold_evidence.first_external = sample.duplicate(true)
        hold_evidence.last_external = sample
    elif row.phase == "idle": hold_evidence.idle_samples = int(hold_evidence.idle_samples)+1

func _executor_authority_boundary() -> void:
    var before: Dictionary = {"executor":executor.report(),"rules":context.rules.snapshot(),
        "custody":context.custody.report(),"command":context.carrier.command.duplicate(true)}
    var refused: Dictionary = executor.tick(DT,false,false)
    var after: Dictionary = {"executor":executor.report(),"rules":context.rules.snapshot(),
        "custody":context.custody.report(),"command":context.carrier.command.duplicate(true)}
    _check(not refused.ok and refused.code == "not_authority" and before == after,"nonhost external wait cannot write flight input, custody, rules or controller")

func _verify_host_continuation(work_serial: int) -> void:
    if _exchange_mode():
        # A replacement now at 45 C with no new work demand requires no further
        # transport. Test its REAL idle hold; do not invent a cleanup job.
        var count: int = int(executor.report().receipt_count)
        for i in 300:
            await _step_bench()
            if not unexpected_executor_fault.is_empty(): break
        var idle_state: Dictionary = context.rules.snapshot()
        var idle_report: Dictionary = executor.report()
        cleanup_evidence = {"mode":"correct_idle_after_cold_work","executor":idle_report,"sample":_sample()}
        _check(idle_report.ok and idle_report.phase == "idle" and idle_report.hold.get("anchor","") == Rules.WORK and idle_report.receipt_count == count and count == 10 and idle_state.pending_action.is_empty() and not idle_state.job_requested,"exchange work ends in actual anchored idle without redundant new job",cleanup_evidence)
        return
    # Local work still leaves the cold cartridge on the carrier. Require its
    # first genuine cleanup move/place through the original southern route.
    var receipt: Dictionary = {}
    for i in 2700:
        for event: Dictionary in executor.report().receipts:
            var candidate: Dictionary = event.receipt
            if int(candidate.serial) > work_serial and candidate.kind == "place" and candidate.cassette_id == Rules.CASSETTES[0] and candidate.destination == Rules.SOUTH_0:
                receipt = event.duplicate(true)
                break
        if not receipt.is_empty() or not unexpected_executor_fault.is_empty(): break
        await _step_bench()
    var actual: Dictionary = context.custody.report().cargos[Rules.CASSETTES[0]]
    var state: Dictionary = context.rules.snapshot()
    cleanup_evidence = {"mode":"actual_cold_return_after_local_work","place_receipt":receipt,
        "cargo":actual,"support":context.custody.support_info(Rules.CASSETTES[0],Rules.SOUTH_0),
        "executor":executor.report(),"sample":_sample()}
    _check(not receipt.is_empty() and actual.phase == "docked" and actual.berth == Rules.SOUTH_0 and int(actual.stable_usec) >= 350000 and cleanup_evidence.support.get("supported",false) and state.cassettes[Rules.CASSETTES[0]].holder == Rules.SOUTH_0,"post-work host performs real cleanup move/drop/stable support without resetting WAIT",cleanup_evidence)
    _check(state.jobs_completed == 1 and state.service_credit == 1 and state.services_consumed == 0 and bench.report().receipt_count == 1,"cleanup never fabricates another work or consumes service")

func _blocked_handoff() -> void:
    var held: Dictionary = executor.report().hold.duplicate(true)
    var before_receipts: int = int(executor.report().receipt_count)
    var bounds := AABB()
    var found := false
    for child: Node in context.carrier.get_children():
        if child is CollisionShape3D and not child.disabled and child.shape is BoxShape3D:
            var size: Vector3 = child.shape.size
            var actual: AABB = child.global_transform*AABB(-size*.5,size)
            bounds = bounds.merge(actual) if found else actual
            found = true
    if not _check(found and not held.is_empty(),"handoff obstruction derives from actual held hull bounds"): return
    # A visible physical QA lid outside the hull by 10 cm, inside Pilot's
    # unchanged 18 cm clearance. It obstructs permission without placing a wall
    # through the aircraft, changing its velocity, or weakening real collision.
    var at := Vector3(bounds.get_center().x,bounds.end.y+.12,bounds.get_center().z)
    var lid: StaticBody3D = _obstacle("QA_HoldHandoffLid",at,Vector3(bounds.size.x+.8,.04,bounds.size.z+.8))
    var pending: Dictionary = {}
    var retained := true
    var blocked_frames := 0
    var first_block: Dictionary = {}
    for i in 30:
        await _step_bench()
        var row: Dictionary = executor.report()
        var state: Dictionary = context.rules.snapshot()
        if pending.is_empty(): pending = state.pending_action.duplicate(true)
        retained = retained and not pending.is_empty() and pending.kind == "move" and state.pending_action == pending and row.hold == held and row.receipt_count == before_receipts
        if row.code == "anchor_hold_blocked" and str(row.controller.get("probe",{}).get("collider","")).contains("QA_HoldHandoffLid"):
            blocked_frames += 1
            if first_block.is_empty(): first_block = row.duplicate(true)
        if not unexpected_executor_fault.is_empty(): break
    _check(blocked_frames > 0 and retained and context.carrier.get_colliding_bodies().is_empty(),"real hold obstruction retains same newly reserved move and controller without a receipt or contact",{"blocked_frames":blocked_frames,"pending":pending,"first_block":first_block,"retained":retained})
    lid.free()
    var resumed := false
    var final_row: Dictionary = {}
    for i in 180:
        await _step_bench()
        final_row = executor.report()
        if not unexpected_executor_fault.is_empty(): break
        if final_row.phase == "travel":
            resumed = true
            break
    var offset: Vector3 = context.carrier.global_position-Vector3(held.target)
    handoff_evidence = {"blocked_frames":blocked_frames,"first_block":first_block,
        "held":held,"pending":pending,"resumed":final_row,"actual_position":context.carrier.global_position,
        "horizontal_error_m":Vector2(offset.x,offset.z).length(),"custody":context.custody.report()}
    _check(resumed and context.rules.snapshot().pending_action == pending and final_row.receipt_count == before_receipts and Vector2(offset.x,offset.z).length() <= .20,"removing obstruction hands same pending to transport only after real anchor recovery",handoff_evidence)

func _interruptions() -> void:
    var before: Dictionary = bench.report()
    var rules_before: Dictionary = context.rules.snapshot()
    var held_before: Dictionary = executor.report().hold.duplicate(true)
    for i in 24: await _step_bench(true)
    _check(bench.head.global_position == before.tool_position and bench.report().scan_distance_m == before.scan_distance_m and context.rules.snapshot() == rules_before,"pause keeps physical tool/work unchanged; does not claim rigidbody freeze")
    _check(executor.report().hold == held_before and context.carrier.command.get("brake",false),"paused host brakes while preserving fixed hold binding; no physical freeze claim")
    _check(bench.apply_charge(-20,2,true,false).ok,"real power target can be discharged")
    for i in 30: await _step_bench()
    _check(bench.report().code == "work_power_required" and bench.head.global_position == before.tool_position and context.rules.snapshot().jobs_completed == 0,"power loss halts actual tool without time-completing work")
    _check(bench.apply_charge(20,3,true,false).ok,"power restore accepts fresh host result")
    _thermal(str(bench.report().action.cassette_id),1000)
    for i in 30: await _step_bench()
    _check(bench.report().code == "work_cassette_overheated" and bench.head.global_position == before.tool_position,"one degree above the actual gate stops tool immediately")
    _thermal(str(bench.report().action.cassette_id),-1000)
    # Explicit frozen TR/HX obstruction fixtures occupy a clear volume ahead
    # of the arm; their actual collision shapes, not proxy points, stop it.
    for airframe: String in ["tr01","hx02"]:
        var blocking := Flight.new()
        blocking.configure(Catalog.resolve_build(Catalog.default_build(airframe)))
        blocking.freeze = true
        world.add_child(blocking)
        blocking.global_position = Vector3(bench.head.global_position.x+float(blocking.stats.width_m)*.5+.08,1.02+float(blocking.stats.height_m)*.5,6)
        var blocked_by_hull := false
        var stopped := Vector3.ZERO
        for i in 60:
            await _step_bench()
            if bench.report().code == "tool_blocked":
                if not blocked_by_hull: stopped = bench.head.global_position
                blocked_by_hull = true
        _check(blocked_by_hull and bench.head.global_position == stopped and context.rules.snapshot().jobs_completed == 0,"full actual "+airframe+" collider stops telescoping tool",bench.report())
        blocking.free()
    # Small external object ahead of the head; collision is real, not a flag.
    var location: Vector3 = bench.head.global_position+Vector3.RIGHT*.13
    var obstacle: StaticBody3D = _obstacle("QA_ToolObstacle",location,Vector3(.06,.10,.10))
    var blocked := false
    var blocked_pose := Vector3.ZERO
    for i in 90:
        await _step_bench()
        if bench.report().code == "tool_blocked":
            if not blocked: blocked_pose = bench.head.global_position
            blocked = true
    _check(blocked and bench.head.global_position == blocked_pose and context.rules.snapshot().jobs_completed == 0,"real tool sweep stops at object with no work receipt",bench.report())
    obstacle.free()
    var resumed := false
    for i in 60:
        await _step_bench()
        if bench.head.global_position.distance_to(blocked_pose) > .02:
            resumed = true
            break
    _check(resumed,"removing only named obstruction resumes the same actual stroke")

func _identity_negative() -> void:
    records.append({"stage":"completed_positive_fixture_before_new_negative","bench":bench.report(),"sample":_sample()})
    bench.close(true)
    executor.close(true)
    world.free()
    vp.free()
    context = {}
    if not await _setup(): return
    _thermal(Rules.CASSETTES[1],-25000)
    if not await _reach_work(): return
    bench.apply_charge(20,1,true,false)
    for i in 1200:
        await _step_bench()
        if bench.report().phase == "scan_out": break
    _check(bench.report().phase == "scan_out","separate declared negative fixture reaches real work stroke")
    var old_action: Dictionary = bench.report().action
    var duplicate := Bench.new()
    world.add_child(duplicate)
    var duplicate_result: Dictionary = duplicate.configure(context,true)
    _check(not duplicate_result.ok and duplicate_result.code == "unserved_candidate_only" and duplicate.get_child_count() == 0,"pending work cannot be rebound to a second beneficiary")
    duplicate.free()
    var cargo: RigidBody3D = context.cargos[Rules.CASSETTES[1]]
    expected_custody_fault = true
    cargo.apply_central_impulse(Vector3.RIGHT*1.0)
    var invalid_frames := 0
    var all_invalid_frames_stopped := true
    invalid_contact_evidence = {"first_invalid":{},"first_stable_again":{},"samples":[]}
    for i in 35:
        var tool_before: Vector3 = bench.head.global_position
        var scan_before: float = float(bench.report().scan_distance_m)
        await _step_bench()
        # Custody.step runs first and changes docked -> settling when its actual
        # contact/velocity proof fails. Observe BOTH that state and the current
        # proof, rather than requiring the later workbench branch's code string.
        var custody_state: Dictionary = context.custody.report().cargos[Rules.CASSETTES[1]]
        var support: Dictionary = context.custody.support_info(Rules.CASSETTES[1],Rules.WORK)
        var row: Dictionary = bench.report()
        var invalid: bool = custody_state.phase != "docked" or not support.get("supported",false)
        var sample: Dictionary = {"frame":Engine.get_physics_frames(),"custody":custody_state.duplicate(true),"support":support,"code":row.code,"tool_before":tool_before,"tool_after":bench.head.global_position,"scan_before":scan_before,"scan_after":row.scan_distance_m,"receipt_count":row.receipt_count}
        if invalid:
            invalid_frames += 1
            var stopped: bool = bench.head.global_position == tool_before and float(row.scan_distance_m) == scan_before and row.receipt_count == 0 and context.rules.snapshot().jobs_completed == 0
            all_invalid_frames_stopped = all_invalid_frames_stopped and stopped
            if invalid_contact_evidence.first_invalid.is_empty(): invalid_contact_evidence.first_invalid = sample.duplicate(true)
            if invalid_contact_evidence.samples.size() < 6: invalid_contact_evidence.samples.append(sample)
        elif invalid_frames > 0 and invalid_contact_evidence.first_stable_again.is_empty():
            invalid_contact_evidence.first_stable_again = sample.duplicate(true)
    invalid_contact_evidence.invalid_frames = invalid_frames
    invalid_contact_evidence.all_invalid_frames_stopped = all_invalid_frames_stopped
    _check(invalid_frames > 0 and all_invalid_frames_stopped and context.rules.snapshot().jobs_completed == 0,"every actual unsupported or settling frame stops tool and receipt",invalid_contact_evidence)
    _check(not expected_executor_fault.is_empty() and expected_executor_fault.code == "rules_physics_holder_mismatch" and executor.report().phase == "fault" and context.rules.snapshot().pending_action == old_action,"deliberate custody disruption faults executor and retains original pending instead of silently recovering",{"first_fault":expected_executor_fault})
    # Actual force moves the same registered recipient. No pose write or new
    # body substitution is used to produce the invalidation evidence.
    bench.beneficiary.apply_central_impulse(Vector3.RIGHT*5.0)
    for i in 80:
        await _step_bench()
        if bench.report().phase == "fault" or not unexpected_executor_fault.is_empty(): break
    _check(bench.report().phase == "fault" and not bench.report().committed and bench.report().action == old_action and context.rules.snapshot().jobs_completed == 0,"recipient displacement/damage faults and preserves old action instead of transferring progress",bench.report())
    var before: Dictionary = context.rules.snapshot()
    for i in 20: await _step_bench(true)
    _check(context.rules.snapshot() == before and bench.report().receipt_count == 0,"invalidated beneficiary cannot receive a delayed completion")

func _boundaries() -> void:
    var before: Dictionary = {"bench":bench.report(),"rules":context.rules.snapshot(),"custody":context.custody.report(),"command":bench.beneficiary.command.duplicate(true)}
    _check(not bench.advance(DT,false,false).ok and not bench.apply_charge(20,1,false,false).ok,"nonhost cannot move tool, command recipient, power or commit work")
    _check(not bench.advance(NAN,true,false).ok and not bench.apply_charge(INF,1,true,false).ok,"nonfinite input rejects atomically")
    var after: Dictionary = {"bench":bench.report(),"rules":context.rules.snapshot(),"custody":context.custody.report(),"command":bench.beneficiary.command.duplicate(true)}
    _check(before == after,"rejected calls change neither commands nor physical/rule evidence")

func _routes() -> void:
    for type: String in ["tr01","hx02"]:
        var probe := Flight.new()
        probe.configure(Catalog.resolve_build(Catalog.default_build(type)))
        probe.freeze = true
        world.add_child(probe)
        probe.position = Vector3(26,16,26)
        var size := Vector3(float(probe.stats.width_m),float(probe.stats.height_m),float(probe.stats.length_m))
        for pair: Array in [[Vector3(14.75,2.2,23),Vector3(14.75,2.2,6)],[Vector3(14.75,2.2,6),Vector3(10.6,2.2,6)]]:
            var shape := BoxShape3D.new()
            shape.size = size
            var query := PhysicsShapeQueryParameters3D.new()
            query.shape = shape
            query.transform = Transform3D(Basis.IDENTITY,pair[0])
            query.collision_mask = Bench.MASK
            query.exclude = [probe.get_rid(),context.carrier.get_rid()]
            var hits: Array[Dictionary] = world.get_world_3d().direct_space_state.intersect_shape(query,1)
            query.motion = pair[1]-pair[0]
            var cast: PackedFloat32Array = world.get_world_3d().direct_space_state.cast_motion(query)
            _check(hits.is_empty() and cast.size() == 2 and cast[0] >= .999,"new structures preserve actual "+type+" low loading route",{"from":pair[0],"to":pair[1],"fraction":cast})
        probe.free()

func _physics() -> void:
    await physics_frame
    ticks += 1
    world.clock_seconds += DT

func _thermal_clock() -> void:
    thermal_ticks += 1
    var next_usec: int = roundi(float(thermal_ticks)*1000000.0/60.0)
    var result: Dictionary = context.rules.step(next_usec-thermal_elapsed,{"powered":false,"valve_open":false,"sweep_clear":false,"contacts":{Rules.SOUTH_0:"",Rules.SOUTH_1:""}},true,false)
    thermal_elapsed = next_usec
    if not result.ok: _check(false,"single independent rule clock",result)

func _thermal(id: String, delta_mc: int) -> void:
    var state: Dictionary = context.rules.snapshot()
    var result: Dictionary = context.rules.apply_command({"serial":int(state.command_serial)+1,"expected_revision":state.revision,"kind":"thermal","cassette_id":id,"delta_mc":delta_mc},true,false)
    _check(result.ok,"declared host thermal-rule input, not a Session/player ability",{"result":result,"delta_mc":delta_mc,"id":id})

func _physical_work_holder() -> String:
    for id: String in context.cargos:
        var state: Dictionary = context.custody.report().cargos[id]
        if state.phase == "docked" and state.berth == Rules.WORK and context.custody.support_info(id,Rules.WORK).supported: return id
    return ""

func _rays() -> Array:
    var found: Array = []
    for start: Vector3 in OBSERVERS:
        for spec: Dictionary in world.distribution.layout().panels:
            var center := Vector3(float(spec.center[0]),float(spec.center[1]),float(spec.center[2]))
            var front: Vector3 = world.distribution.to_global(center+Vector3.BACK*float(spec.size[2])*.5)
            for offset: Vector2 in [Vector2.ZERO,Vector2(-.06,-.04),Vector2(.06,-.04),Vector2(-.06,.04),Vector2(.06,.04)]:
                var end: Vector3 = front+Vector3(offset.x,offset.y,0)
                var query := PhysicsRayQueryParameters3D.create(start,end-(start-end).normalized()*.002,Bench.MASK)
                var hit: Dictionary = world.get_world_3d().direct_space_state.intersect_ray(query)
                found.append(str(hit.collider.name) if not hit.is_empty() else "")
    return found

func _obstacle(id: String, at: Vector3, size: Vector3) -> StaticBody3D:
    var body := StaticBody3D.new()
    body.name = id
    body.collision_layer = 1
    var collision := CollisionShape3D.new()
    var shape := BoxShape3D.new()
    shape.size = size
    collision.shape = shape
    body.add_child(collision)
    world.add_child(body)
    body.global_position = at
    return body

func _sample() -> Dictionary:
    if context.is_empty() or not is_instance_valid(bench): return {}
    return {"ticks":ticks,"world_clock":world.clock_seconds,"recipient_position":bench.beneficiary.global_position if is_instance_valid(bench.beneficiary) else null,"recipient_velocity":bench.beneficiary.linear_velocity if is_instance_valid(bench.beneficiary) else null,"recipient_health":bench.beneficiary.health if is_instance_valid(bench.beneficiary) else -1,"recipient_collision_count":bench.beneficiary.collision_count if is_instance_valid(bench.beneficiary) else -1,"carrier_position":context.carrier.global_position,"rules":context.rules.snapshot(),"custody":context.custody.report()}

func _collect_inputs() -> void:
    for path: String in ["res://scripts/v3/candidates/canal_workbench/workbench.gd","res://scripts/v3/candidates/canal_workbench/beneficiary_departure.gd","res://tests_v3/candidates/canal_workbench/workbench_test_base.gd","res://scripts/v3/candidates/canal_transport_executor/canal_transport_executor.gd","res://scripts/v3/candidates/canal_transport_executor/canal_transport_bootstrap.gd","res://scripts/v3/candidates/canal_transport_physics/transport_pilot.gd","res://scripts/v3/candidates/canal_transport_physics/dock_lift.gd","res://scripts/v3/candidates/canal_transport_physics/cargo_custody.gd","res://scripts/v3/candidates/canal_service_loop/canal_service_runtime.gd","res://scripts/v3/twin_test_world.gd","res://scripts/v2/flight_body.gd","res://data/v3/terrain/i2_shared_access_layout.json"]:
        inputs[path] = FileAccess.get_sha256(path)

func _check(ok: bool, label: String, details: Dictionary = {}) -> bool:
    checks += 1
    if not ok:
        failures.append({"label":label,"details":details.duplicate(true)})
        print("WORKBENCH_FAIL "+label+" "+JSON.stringify(details))
    return ok

func _result() -> Dictionary:
    return {"checks":checks,"failures":failures,"engine_errors":logger.errors,"exchange_mode":_exchange_mode(),"bench":bench.report() if is_instance_valid(bench) else {},"executor":executor.report() if executor != null else {},"records":records,"sample":_sample(),"invalid_contact_evidence":invalid_contact_evidence,"hold_evidence":hold_evidence,"cleanup_evidence":cleanup_evidence,"handoff_evidence":handoff_evidence,"unexpected_executor_fault":unexpected_executor_fault,"expected_executor_fault":expected_executor_fault,"lift_commands":{"samples":lift_command_checks,"deadband_samples":lift_deadband_samples,"max_fallback_error_mps":lift_max_fallback_error,"consistent":lift_command_consistent},"input_sha256":inputs,"scope":"independent physical candidate, explicit QA initialization/host thermal/power fixtures; no Session ability, Store, multiplayer, healing or human-play claim"}

func _finish() -> void:
    if finished: return
    finished = true
    for path: String in inputs: _check(not str(inputs[path]).is_empty() and FileAccess.get_sha256(path) == inputs[path],"input bytes stable: "+path)
    _check(logger.errors.is_empty(),"no engine errors",{"errors":logger.errors})
    var result: Dictionary = _result()
    if is_instance_valid(bench): bench.close(true)
    if executor != null: executor.close(true)
    if is_instance_valid(world): world.queue_free()
    await process_frame
    if is_instance_valid(vp): vp.queue_free()
    await process_frame
    print("V3_CANAL_WORKBENCH_RESULT "+JSON.stringify(result))
    quit(0 if failures.is_empty() and logger.errors.is_empty() else 1)
