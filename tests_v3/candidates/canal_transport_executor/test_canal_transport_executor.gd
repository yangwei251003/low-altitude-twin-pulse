extends SceneTree
## One actual I2 route; reusable factory/bootstrap is production candidate code.
## Test loop only supplies physics ticks, independent thermal input and a named
## removable obstruction. It never drives legs or manufactures any receipt.
const World = preload("res://scripts/v3/twin_test_world.gd")
const Bootstrap = preload("res://scripts/v3/candidates/canal_transport_executor/canal_transport_bootstrap.gd")
const Executor = preload("res://scripts/v3/candidates/canal_transport_executor/canal_transport_executor.gd")
const Rules = preload("res://scripts/v3/candidates/canal_service_loop/canal_service_runtime.gd")
const Flight = preload("res://scripts/v2/flight_body.gd")
const DT := 1.0/60.0
var checks := 0
var failures: Array = []
var records: Array = []
var inputs: Dictionary = {}
var finished := false
var vp: SubViewport
var world: World
var bootstrap: RefCounted
var executor: RefCounted
var context: Dictionary = {}
var ticks := 0
var thermal_ticks := 0
var elapsed_usec := 0
var reentry_enabled := false
var reentry_result: Dictionary = {}
var reentry_before := -1
var obstacle: StaticBody3D
var first_block: Dictionary = {}
var blocked_ticks := 0
var wall_created_tick := -1
var wall_removed_tick := -1
var wall_last_block_tick := -1
var wall_consecutive_ticks := 0
var wall_longest_consecutive_ticks := 0
var wall_longest_reported_seconds := 0.0
var wall_pending_preserved := true
var alignment_records: Dictionary = {}
var obstacle_removed := false
var thermal_added := false
var thermal_removed := false
var paused_checked := false
var last_phase := ""
var last_count := 0
var maximum_tick_usec := 0
class ErrorLogger extends Logger:
    var errors: Array = []
    func _log_error(function: String,file: String,line: int,code: String,rationale: String,_notify: bool,error_type: int,_backtraces: Array[ScriptBacktrace]) -> void:
        errors.append({"function":function,"file":file,"line":line,"code":code,"rationale":rationale,"type":error_type})
var logger := ErrorLogger.new()

func _init() -> void:
    OS.add_logger(logger)
    _run.call_deferred()

func _run() -> void:
    create_timer(280.0).timeout.connect(func():
        if not finished:
            print("CANAL_EXECUTOR_TIMEOUT "+JSON.stringify(_result()))
            quit(2))
    for dependency: Script in [World,Bootstrap,Executor]:
        if not _check(dependency.can_instantiate(),"actual dependency parses",{"path":dependency.resource_path}):
            await _finish()
            return
    _collect_inputs()
    if not _check(Engine.physics_ticks_per_second == 60 and Engine.time_scale == 1.0,"normal 60 Hz, no time acceleration"):
        await _finish()
        return
    vp = SubViewport.new()
    vp.size = Vector2i(32,32)
    vp.own_world_3d = true
    vp.world_3d = World3D.new()
    vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
    root.add_child(vp)
    world = World.new()
    vp.add_child(world)
    world.build("I2",{},true)
    if not _check(world.build_errors.is_empty() and world.waterfront_install.get("ok",false),"production I2 with actual canal builds",{"errors":world.build_errors}):
        await _finish()
        return
    _check(is_instance_valid(world.clinic) and is_instance_valid(world.distribution) and is_instance_valid(world.trial) and is_instance_valid(world.shared_access),"all four actual production facilities present")
    for art: Dictionary in [world.clinic.gravity_art,world.clinic.reception_art,world.clinic.pump_art,world.shared_access.deck_art,world.shared_access.landing_art]:
        _check(art.get("ok",false),"actual imported facility model",{"path":art.get("path","")})
        var path: String = str(art.get("path",""))
        if not path.is_empty(): inputs[path] = FileAccess.get_sha256(path)
    for i in 3: await physics_frame
    bootstrap = Bootstrap.new()
    var created: Dictionary = bootstrap.create(world,world.sample_environment,true)
    if not _check(created.ok,"shared factory checks support and free columns before creating four real berths",created):
        await _finish()
        return
    _check(not bootstrap.create(world,world.sample_environment,true).ok,"factory does not duplicate its own site")
    var boot_ready := false
    for i in 3300:
        await _physics()
        var prior_boot_phase: String = str(bootstrap.phase)
        var boot: Dictionary = bootstrap.tick(DT,true,false)
        if prior_boot_phase == "align": _record_alignment("bootstrap",boot,bootstrap.context())
        if i%120 == 0: records.append({"stage":"bootstrap","report":boot,"sample":_sample_boot()})
        if not boot.ok:
            _check(false,"physical bootstrap progresses without fault",boot)
            break
        if boot.ready:
            boot_ready = true
            break
    if not _check(boot_ready,"real S0 pickup, Dock lift and flight reach WAIT without a logical receipt",bootstrap.report()):
        await _finish()
        return
    context = bootstrap.context()
    executor = Executor.new()
    var refused: Dictionary = executor.configure(context.carrier,context.cargos,context.berths,context.custody,context.rules,_environment,false)
    _check(not refused.ok,"client cannot bind a controlling executor")
    var bound: Dictionary = executor.configure(context.carrier,context.cargos,context.berths,context.custody,context.rules,_environment,true)
    if not _check(bound.ok,"host binds exact real initial custody",bound):
        await _finish()
        return
    _check(not executor.configure(context.carrier,context.cargos,context.berths,context.custody,context.rules,_environment,true).ok,"executor configure is not reentrant")
    _boundary_calls()
    await _pause_check(18)
    reentry_enabled = true
    var completed := false
    for i in 14500:
        await _physics()
        if not _thermal_clock(): break
        var start_usec: int = Time.get_ticks_usec()
        var row: Dictionary = executor.tick(DT,true,false)
        maximum_tick_usec = maxi(maximum_tick_usec,Time.get_ticks_usec()-start_usec)
        if last_phase == "align": _record_alignment("executor",row,context)
        if not row.ok:
            _check(false,"executor fault preserves evidence",{"report":row,"sample":_sample()})
            break
        if i == 0:
            _check(reentry_result.get("code","") == "reentrant_tick" and int(row.active_ticks) == reentry_before,"environment callback cannot recursively advance executor",reentry_result)
            var before: Dictionary = _logical_state()
            var repeated: Dictionary = executor.tick(DT,true,false)
            _check(not repeated.ok and repeated.code == "same_physics_frame" and _logical_state() == before,"same physical frame cannot advance custody, controls or receipts twice")
        if row.phase != last_phase or int(row.receipt_count) != last_count or i%120 == 0:
            records.append({"stage":"executor","report":row,"sample":_sample()})
            last_phase = str(row.phase)
            last_count = int(row.receipt_count)
        # The original action 3 is empty flight from the south to WORK.
        if obstacle == null and not obstacle_removed and int(row.action.get("serial",0)) == 3 and row.phase == "travel" and context.carrier.global_position.z > 20:
            obstacle = _wall()
            wall_created_tick = ticks
            records.append({"stage":"named_qa_obstruction_created","sample":_sample()})
        if is_instance_valid(obstacle):
            var pending: Dictionary = context.rules.snapshot().pending_action
            wall_pending_preserved = wall_pending_preserved and int(row.receipt_count) == 2 and int(pending.get("serial",0)) == 3
        if is_instance_valid(obstacle) and row.code == "route_blocked":
            var probe: Dictionary = row.controller.get("probe",{})
            if str(probe.get("collider","")).ends_with("ExecutorTestRouteWall"):
                if first_block.is_empty(): first_block = {"report":row,"sample":_sample(),"pending":context.rules.snapshot().pending_action}
                blocked_ticks += 1
                wall_consecutive_ticks = wall_consecutive_ticks+1 if wall_last_block_tick == ticks-1 else 1
                wall_last_block_tick = ticks
                wall_longest_consecutive_ticks = maxi(wall_longest_consecutive_ticks,wall_consecutive_ticks)
                wall_longest_reported_seconds = maxf(wall_longest_reported_seconds,float(row.blocked_seconds))
                if blocked_ticks == 1:
                    _check(row.controller.speed_plan.commanded == false and int(row.receipt_count) == 2,"actual wall blocks original route; no premature third receipt",row)
                    thermal_added = _thermal(1000)
                if blocked_ticks == 61: thermal_removed = _thermal(-1000)
                if blocked_ticks >= 210:
                    wall_removed_tick = ticks
                    var wall_elapsed: Dictionary = _wall_evidence()
                    _check(wall_pending_preserved and float(wall_elapsed.seconds_since_first_hit) > 3.0 and blocked_ticks*DT > 3.0,"wall remains beyond 3 seconds and cumulative rejection preserves pending; not a continuous-block claim",wall_elapsed)
                    obstacle.free()
                    obstacle = null
                    obstacle_removed = true
                    records.append({"stage":"actual_obstacle_removed_only","sample":_sample()})
        if not paused_checked and obstacle_removed and row.phase == "travel" and row.controller.get("speed_plan",{}).get("commanded",false):
            await _pause_check(24)
            paused_checked = true
        if not _physical_safe(): break
        if row.phase == "awaiting_external" and row.action.get("kind","") == "work":
            completed = true
            break
    _check(completed,"ten actions reach real pending work with no await leg driver",executor.report())
    var saved: Dictionary = context.rules.snapshot()
    var report: Dictionary = executor.report()
    _check(report.receipt_count == 10,"exactly ten true physical receipts",{"count":report.receipt_count})
    var receipt_serials: Dictionary = {}
    var expected_kinds := ["move","place","move","pick","move","place","move","pick","move","place"]
    for i in report.receipts.size():
        var receipt: Dictionary = report.receipts[i].receipt
        var pending_identity_ok: bool = not receipt_serials.has(receipt.serial) and int(receipt.serial) == i+1 and i < expected_kinds.size() and receipt.kind == expected_kinds[i]
        for key: String in ["path_clear","endpoint_valid","custody_verified","completed"]: pending_identity_ok = pending_identity_ok and receipt.get(key,false) == true
        _check(pending_identity_ok,"each accepted serial is unique and carries real checked outcome",{"receipt":receipt})
        receipt_serials[receipt.serial] = true
    _check(_real_final(),"cold rests on WORK and hot on S1, empty real hook",_sample())
    _check(saved.pending_action.get("serial",0) == 11 and saved.pending_action.get("kind","") == "work" and saved.jobs_completed == 0 and saved.service_credit == 0 and saved.thermal_ledger.work_added == 0,"unimplemented work remains awaiting_external without fabricated service",saved.pending_action)
    _check(thermal_added and thermal_removed and saved.thermal_ledger.ability_added == Rules.POD_CAPACITY*1000 and saved.thermal_ledger.ability_removed == Rules.POD_CAPACITY*1000,"independent thermal operations progressed while carrier was physically blocked",saved.thermal_ledger)
    _check(obstacle_removed and paused_checked,"physical obstruction/resume and mid-route host pause executed")
    if completed:
        var prior: Dictionary = saved.duplicate(true)
        for i in 12:
            await _physics()
            executor.tick(DT,true,false)
        _check(context.rules.snapshot() == prior and executor.report().receipt_count == 10,"external work wait does not time-complete or duplicate receipt")
        # Named empty fixture support is deliberately invalidated after success.
        # No cargo is moved; loss must fault closed and preserve pending work.
        context.berths[Rules.BUFFER].free()
        await _physics()
        var faulted: Dictionary = executor.tick(DT,true,false)
        _check(not faulted.ok and faulted.phase == "fault" and context.rules.snapshot() == prior,"lost registered support faults without replacing nodes or clearing pending",faulted)
        var count: int = int(faulted.active_ticks)
        var closed: Dictionary = executor.close(true)
        await _physics()
        executor.tick(DT,true,false)
        _check(closed.closed and executor.report().active_ticks == count and context.rules.snapshot() == prior,"close is terminal, brakes and preserves physical/logical ownership")
        executor.close(true)
    _check(logger.errors.is_empty(),"no engine errors",{"errors":logger.errors})
    await _finish()

func _physics() -> void:
    await physics_frame
    ticks += 1
    world.clock_seconds += DT

func _environment(at: Vector3) -> Dictionary:
    if reentry_enabled and executor != null:
        reentry_enabled = false
        reentry_before = int(executor.report().active_ticks)
        reentry_result = executor.tick(DT,true,false)
    return world.sample_environment(at)

func _wall_evidence() -> Dictionary:
    var end_tick: int = wall_removed_tick if wall_removed_tick >= 0 else ticks
    var first_tick: int = int(first_block.get("sample",{}).get("ticks",end_tick))
    return {"created_tick":wall_created_tick,"removed_tick":wall_removed_tick,"first_hit_tick":first_tick,
        "wall_present_seconds":(end_tick-wall_created_tick)*DT if wall_created_tick >= 0 else 0.0,
        "seconds_since_first_hit":(end_tick-first_tick)*DT,"cumulative_rejection_ticks":blocked_ticks,
        "cumulative_rejection_seconds":blocked_ticks*DT,"longest_consecutive_rejection_ticks":wall_longest_consecutive_ticks,
        "longest_consecutive_rejection_seconds":wall_longest_consecutive_ticks*DT,
        "longest_executor_reported_seconds":wall_longest_reported_seconds,"pending_preserved_each_observed_tick":wall_pending_preserved,
        "current_pending":context.rules.snapshot().pending_action if context.has("rules") else {},
        "position":context.carrier.global_position if context.has("carrier") else Vector3.ZERO}

func _record_alignment(stage: String, row: Dictionary, live: Dictionary) -> void:
    # Actual controller reports and current physical measurements only. At most
    # 8 alignments, 12 one-second samples plus first/latest per alignment.
    var controller: Dictionary = row.get("controller",{})
    if controller.get("mode","") != "pickup_alignment": return
    var key: String = stage+":"+str(controller.get("serial",0))
    if not alignment_records.has(key) and alignment_records.size() >= 8: return
    var body: Flight = live.carrier
    var action: Dictionary = row.get("action",{})
    var id: String = str(action.get("cassette_id",Rules.CASSETTES[0]))
    var cargo: RigidBody3D = live.cargos.get(id)
    var sample: Dictionary = {"tick":ticks,"world_clock_seconds":world.clock_seconds,"phase":row.phase,"code":row.code,
        "action_serial":action.get("serial",0),"cargo_id":id,"body_position":body.global_position,
        "body_velocity":body.linear_velocity,"body_angular_velocity":body.angular_velocity,"body_mass_kg":body.mass,
        "environment":body.environment_sample.duplicate(true),"command":body.command.duplicate(true),
        "reported_distance_m":controller.get("distance_m",-1.0),"settled_seconds":controller.get("settled_seconds",0.0),
        "arrived":controller.get("arrived",false),"feedforward":controller.get("pickup_wind_compensation",{}).duplicate(true),
        "speed_plan":controller.get("speed_plan",{}).duplicate(true)}
    if is_instance_valid(cargo):
        sample.cargo_position = cargo.global_position
        sample.actual_hook_error_m = (cargo.global_position-(body.global_position+Vector3(0,-1.1,0))).length()
    if not alignment_records.has(key): alignment_records[key] = {"first":sample.duplicate(true),"last":{},"samples":[],"last_sample_tick":ticks-60}
    var entry: Dictionary = alignment_records[key]
    entry.last = sample.duplicate(true)
    if ticks-int(entry.last_sample_tick) >= 60 and entry.samples.size() < 12:
        entry.samples.append(sample)
        entry.last_sample_tick = ticks

func _thermal_clock() -> bool:
    thermal_ticks += 1
    var next_usec: int = roundi(float(thermal_ticks)*1000000.0/60.0)
    var changed: Dictionary = context.rules.step(next_usec-elapsed_usec,{"powered":false,"valve_open":false,"sweep_clear":false,"contacts":{Rules.SOUTH_0:"",Rules.SOUTH_1:""}},true,false)
    elapsed_usec = next_usec
    return _check_once(changed.ok,"independent rule time rejected",changed)

func _thermal(delta_mc: int) -> bool:
    var before: Dictionary = context.rules.snapshot()
    _check(before.cassettes[Rules.CASSETTES[0]].holder == Rules.SOUTH_0,"thermal fixture touches south-seated cold cartridge, not WORK")
    var result: Dictionary = context.rules.apply_command({"serial":int(before.command_serial)+1,"expected_revision":before.revision,"kind":"thermal","cassette_id":Rules.CASSETTES[0],"delta_mc":delta_mc},true,false)
    var after: Dictionary = context.rules.snapshot()
    records.append({"stage":"trusted_host_thermal_fixture_not_player_ability","delta_mc":delta_mc,"before_energy":before.cassettes[Rules.CASSETTES[0]].energy_mj,"after_energy":after.cassettes[Rules.CASSETTES[0]].energy_mj,"result":result})
    return _check(result.ok and after.pending_action == before.pending_action and int(after.cassettes[Rules.CASSETTES[0]].energy_mj)-int(before.cassettes[Rules.CASSETTES[0]].energy_mj) == delta_mc*Rules.POD_CAPACITY,"separate thermal command changes real rules while transport is blocked",result)

func _boundary_calls() -> void:
    var before: Dictionary = _logical_state()
    var denied: Dictionary = executor.tick(DT,false,false)
    _check(not denied.ok and denied.code == "not_authority" and _logical_state() == before,"nonhost tick changes no command, custody, rules or executor progress")
    denied = executor.close(false)
    _check(not denied.ok and _logical_state() == before,"nonhost close cannot stop host controller")
    denied = executor.tick(NAN,true,false)
    _check(not denied.ok and _logical_state() == before,"invalid delta atomically rejects")

func _pause_check(frames: int) -> void:
    var before_rules: Dictionary = context.rules.snapshot()
    var before_custody: Dictionary = context.custody.report()
    var before_ticks: int = int(executor.report().active_ticks)
    var pose_before: Vector3 = context.carrier.global_position
    for i in frames:
        await _physics()
        var paused: Dictionary = executor.tick(DT,true,true)
        if paused.code != "suspended": _check(false,"pause result",paused)
    _check(context.rules.snapshot() == before_rules and context.custody.report() == before_custody and executor.report().active_ticks == before_ticks and context.carrier.command.brake,"pause advances no receipts/contact timer/rules, only normal braking")
    records.append({"stage":"pause_is_not_physics_freeze","frames":frames,"position_before":pose_before,"position_after":context.carrier.global_position})
    _boundary_calls()

func _logical_state() -> Dictionary:
    return {"rules":context.rules.snapshot(),"custody":context.custody.report(),"command":context.carrier.command.duplicate(true),"hold_height":context.carrier.hold_height,"executor":executor.report()}

func _wall() -> StaticBody3D:
    var wall := StaticBody3D.new()
    wall.name = "ExecutorTestRouteWall"
    wall.collision_layer = 1
    wall.collision_mask = 0
    var shape := CollisionShape3D.new()
    var box := BoxShape3D.new()
    box.size = Vector3(3.5,3,.3)
    shape.shape = box
    wall.add_child(shape)
    world.add_child(wall)
    wall.global_position = Vector3(14.75,2.2,14)
    return wall

func _physical_safe() -> bool:
    var body: Flight = context.carrier
    if not body.enabled or body.health != body.maximum_health or body.collision_count != 0 or body.water_contact:
        return _check(false,"actual hull damage or water",_sample())
    return true

func _real_final() -> bool:
    if not context.carrier.cargo_items.is_empty(): return false
    var states: Dictionary = context.custody.report().cargos
    return states[Rules.CASSETTES[0]].phase == "docked" and states[Rules.CASSETTES[0]].berth == Rules.WORK and states[Rules.CASSETTES[1]].phase == "docked" and states[Rules.CASSETTES[1]].berth == Rules.SOUTH_1 and context.custody.support_info(Rules.CASSETTES[0],Rules.WORK).supported and context.custody.support_info(Rules.CASSETTES[1],Rules.SOUTH_1).supported

func _sample_boot() -> Dictionary:
    var c: Dictionary = bootstrap.context()
    return _sample_context(c)

func _sample() -> Dictionary:
    return _sample_context(context)

func _sample_context(c: Dictionary) -> Dictionary:
    if c.is_empty() or not is_instance_valid(c.get("carrier")): return {}
    var body: Flight = c.carrier
    var result: Dictionary = {"ticks":ticks,"position":body.global_position,"velocity":body.linear_velocity,"health":body.health,"collisions":body.collision_count,"water":body.water_contact,"cargo_count":body.cargo_items.size(),"cargos":{},"environment":body.environment_sample.duplicate(true)}
    for id: String in c.cargos:
        var load: RigidBody3D = c.cargos[id]
        if not is_instance_valid(load): continue
        var contacts: Array = []
        for hit: Node in load.get_colliding_bodies(): contacts.append(str(hit.get_path()))
        result.cargos[id] = {"position":load.global_position,"velocity":load.linear_velocity,"angular":load.angular_velocity,"up_dot":load.global_basis.y.dot(Vector3.UP),"contacts":contacts}
    if is_instance_valid(c.get("custody")): result.custody = c.custody.report()
    return result

func _collect_inputs() -> void:
    for path: String in ["res://scripts/v3/candidates/canal_transport_executor/canal_transport_executor.gd","res://scripts/v3/candidates/canal_transport_executor/canal_transport_bootstrap.gd","res://tests_v3/candidates/canal_transport_executor/test_canal_transport_executor.gd",
            "res://scripts/v3/candidates/canal_transport_physics/transport_pilot.gd","res://scripts/v3/candidates/canal_transport_physics/dock_lift.gd","res://scripts/v3/candidates/canal_transport_physics/cargo_custody.gd","res://scripts/v3/candidates/canal_service_loop/canal_service_runtime.gd","res://scripts/v2/flight_body.gd","res://scripts/v3/twin_test_world.gd","res://data/v3/terrain/i2_clinic_layout.json","res://data/v3/terrain/i2_shared_access_layout.json"]:
        inputs[path] = FileAccess.get_sha256(path)

func _check(ok: bool, label: String, details: Dictionary = {}) -> bool:
    checks += 1
    if not ok:
        failures.append({"label":label,"details":details.duplicate(true)})
        print("FAIL "+label+" "+JSON.stringify(details))
    return ok

func _check_once(ok: bool,label: String,details: Dictionary) -> bool:
    return true if ok else _check(false,label,details)

func _result() -> Dictionary:
    return {"checks":checks,"failures":failures,"engine_errors":logger.errors,"records":records,"first_block":first_block,"blocked_ticks":blocked_ticks,
        "wall_timing":_wall_evidence(),"alignment_records":alignment_records,
        "executor":executor.report() if executor != null else {},"bootstrap":bootstrap.report() if bootstrap != null else {},"final":_sample(),
        "rules":context.rules.snapshot() if context.has("rules") else {},"input_sha256":inputs,"max_tick_wall_usec_diagnostic_only":maximum_tick_usec,
        "scope":"one real I2 candidate carrier route and host thermal-rule concurrency; no service, saved physics, multiplayer, player ability, graphics or human-play claim"}

func _finish() -> void:
    if finished: return
    finished = true
    var stable := true
    for path: String in inputs:
        if inputs[path].is_empty() or FileAccess.get_sha256(path) != inputs[path]: stable = false
    _check(stable,"recorded source/model input bytes unchanged")
    var evidence: Dictionary = _result()
    if executor != null: executor.close(true)
    if is_instance_valid(world): world.queue_free()
    await process_frame
    if is_instance_valid(vp): vp.queue_free()
    await process_frame
    print("V3_CANAL_TRANSPORT_EXECUTOR_RESULT "+JSON.stringify(evidence))
    quit(0 if failures.is_empty() and logger.errors.is_empty() else 1)
