extends SceneTree
## Declared actual saved-site fixture, not a replay of transport/work. New
## player pose/resources are QA setup; damage uses the real public settlement.
const World = preload("res://scripts/v3/twin_test_world.gd")
const Restore = preload("res://scripts/v3/candidates/canal_checkpoint/canal_checkpoint_restore.gd")
const Capture = preload("res://scripts/v3/candidates/canal_checkpoint/player_checkpoint.gd")
const Repository = preload("res://scripts/v3/candidates/canal_checkpoint/checkpoint_repository.gd")
const State = preload("res://scripts/v3/candidates/canal_checkpoint/flight_state.gd")
const Pilot = preload("res://scripts/v3/candidates/canal_transport_physics/transport_pilot.gd")
const Service = preload("res://scripts/v3/candidates/canal_player_service/player_service.gd")
const FIXTURE := "res://tests_v3/candidates/canal_checkpoint/evidence/checkpoint_v3_lane_clear_passed_actual.json"
const FIXTURE_SHA := "c02925ec7c6c38c6d2cf3acf841d2b54e265547a5f4faac3f1668718e6d2490f"
const DT := 1.0/60.0
const PLAYER_POSE := Vector3(3.5,2.8,5.4)
var checks := 0
var failures: Array = []
var evidence: Dictionary = {}
var views: Array[SubViewport] = []
var hosts: Array[Dictionary] = []
var finished := false
var healthy := true

class ErrorLog extends Logger:
    var errors: Array = []
    func _log_error(fn: String,file: String,line: int,code: String,reason: String,_notify: bool,kind: int,_traces: Array[ScriptBacktrace]) -> void:
        errors.append({"function":fn,"file":file,"line":line,"code":code,"reason":reason,"kind":kind})
var logger := ErrorLog.new()

func _init() -> void:
    OS.add_logger(logger)
    _run.call_deferred()

func _run() -> void:
    create_timer(40).timeout.connect(func():
        if not finished:
            _check(false,"bounded service test timeout")
            _finish())
    for script: Script in [Service,Restore,Capture]:
        if not _check(script.can_instantiate(),"candidate script can instantiate",{"path":script.resource_path}): _finish(); return
    if not _check(FileAccess.get_sha256(FIXTURE)==FIXTURE_SHA and Engine.physics_ticks_per_second==60 and Engine.time_scale==1,"actual saved source and physical clock"): _finish(); return
    var fixture: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(FIXTURE))
    evidence.fixture = {"path":FIXTURE,"sha256":FIXTURE_SHA,"source":"canal-player-checkpoint-20261020_050633_87e6e4/first_saved.json#site","scope":"actual first-work result; new player fixture and public damage are QA, not replayed combat/work"}
    var first: Dictionary = await _restore(fixture)
    if first.is_empty(): _finish(); return
    var row: Dictionary = fixture.checkpoint.carrier.duplicate(true)
    row.id = Capture.PLAYER_ID
    row.pose = State.pose(Transform3D(Basis.IDENTITY,PLAYER_POSE))
    row.velocity = [0.0,0.0,0.0]
    row.angular_velocity = [0.0,0.0,0.0]
    row.state.hold_height = PLAYER_POSE.y
    row.state.heading = 0.0
    row.state.safe_position = State.xyz(PLAYER_POSE)
    row.state.battery = 73.25
    row.state.heat = 19.5
    var made: Dictionary = Capture.restore_player_fresh(first.world,{"flight":row,"collision_count":3},first.world.sample_environment)
    if not _check(made.ok,"full real player envelope clears service-side initial pose",made): _finish(); return
    first.player = made.body
    first.player.contact_cooldowns[123456789] = first.player.flight_seconds-1.0
    first.pilot = Pilot.new()
    if not _check(first.pilot.bind(first.player) and first.pilot.go_to(PLAYER_POSE,1),"original swept Pilot maintains actual player fixture"): _finish(); return
    var path: String = "user://qa_v3/player_service_"+str(Time.get_ticks_usec())
    var repo = Repository.new(path)
    first.service = Service.new()
    var bound: Dictionary = first.service.configure(first.live.context,first.live.executor,first.live.workbench,first.live.cooling,first.player,repo)
    if not _check(bound.ok,"service binds actual host dependencies",bound): _finish(); return
    var independent = Repository.new(path)
    var baseline: Dictionary = await _safe(first)
    if baseline.is_empty(): _finish(); return
    _check(first.service.interaction().ok,"actual workbench first-hit is reachable from player pose",first.service.interaction())
    var untouched: Dictionary = first.live.context.rules.snapshot()
    var healthy_player: Dictionary = State.capture(first.player,Capture.PLAYER_ID)
    var full: Dictionary = first.service.request(1,0,first.ability,first.world.clock_seconds)
    _check(not full.ok and full.code=="hull_already_full" and independent.read().generation==0 and first.live.context.rules.snapshot()==untouched and State.capture(first.player,Capture.PLAYER_ID)==healthy_player,"full hull leaves credit disk and actual body untouched",full)
    var premature: Dictionary = first.live.executor.wait_for_next_beneficiary(true)
    _check(not premature.ok and not first.live.executor.report().waiting_for_beneficiary,"public wait entry cannot hide an unconsumed first service",premature)
    # Two real public damage settlements: a small component injury and a hull
    # hit large enough to leave >25HP missing. ZERO impulse is explicit QA.
    var component_hit: Dictionary = first.player.apply_combat_hit(6,Vector3.ZERO,first.player.to_global(Vector3(0,0,.4)),"pulse",{"qa_service_fixture":true})
    var hull_hit: Dictionary = first.player.apply_combat_hit(36,Vector3.ZERO,first.player.global_position,"pulse",{"qa_service_fixture":true})
    evidence.damage_receipts = [component_hit.duplicate(true),hull_hit.duplicate(true)]
    _check(not component_hit.is_empty() and not hull_hit.is_empty() and first.player.maximum_health-first.player.health>25 and first.player.damage_snapshot().components.power.health<32,"real DamageModel creates nonzero component armor and >25 hull injury")
    baseline = await _safe(first)
    if baseline.is_empty(): _finish(); return
    var stored: Dictionary = repo.save(baseline,"pre-service",0)
    if not _check(stored.ok and stored.generation==1,"prior complete checkpoint is actually published",{"code":stored.get("code","")}): _finish(); return
    for request: Array in [[1,1,false,false],[1,1,true,true],[0,1,true,false],[1.5,1,true,false]]:
        var before: Dictionary = first.live.context.rules.snapshot()
        var old_player: Dictionary = State.capture(first.player,Capture.PLAYER_ID)
        var denied: Dictionary = first.service.request(request[0],request[1],first.ability,first.world.clock_seconds,request[2],request[3])
        _check(not denied.ok and first.live.context.rules.snapshot()==before and State.capture(first.player,Capture.PLAYER_ID)==old_player and independent.read().generation==1,"unauthorized paused or invalid sequence cannot consume or heal",{"request":request,"result":denied})
    var blocker := StaticBody3D.new()
    blocker.name = "QAServiceLOSBlocker"
    blocker.position = (first.player.global_position+first.live.workbench.power_target.global_position)*.5
    blocker.collision_layer = 1
    var collision := CollisionShape3D.new()
    var shape := BoxShape3D.new()
    shape.size = Vector3(.2,.2,.2)
    collision.shape = shape
    blocker.add_child(collision)
    first.world.add_child(blocker)
    for i in 2:
        if not await _tick(): _finish(); return
    var blocked: Dictionary = first.service.request(1,1,first.ability,first.world.clock_seconds)
    _check(not blocked.ok and blocked.code=="service_obstructed" and str(blocked.first_hit).contains("QAServiceLOSBlocker") and independent.read().generation==1 and first.live.context.rules.snapshot().service_credit==1,"real obstruction blocks service without removing collision or credit",blocked)
    blocker.free()
    baseline = await _safe(first)
    if baseline.is_empty(): _finish(); return
    var before_fail: Dictionary = first.live.context.rules.snapshot()
    var player_before_fail: Dictionary = State.capture(first.player,Capture.PLAYER_ID)
    repo._store.failure_point = "before_publish"
    var failed: Dictionary = first.service.request(1,1,first.ability,first.world.clock_seconds)
    repo._store.failure_point = ""
    var preserved: Dictionary = independent.read()
    _check(not failed.ok and str(failed.code).begins_with("save_failed:") and not first.service.report().reload_required,"actual generation publish failure is reported as retryable",failed)
    # Both values are already read back. Re-encoding one can round a double a
    # second time; compare the two persisted values directly and retain each
    # independent condition, rather than a single opaque combined assertion.
    var unchanged: Dictionary = {"generation":preserved.generation==1,"persisted_envelope":preserved.envelope==stored.envelope,"rules":first.live.context.rules.snapshot()==before_fail,"player":State.capture(first.player,Capture.PLAYER_ID)==player_before_fail}
    evidence.failed_write_unchanged = unchanged.duplicate(true)
    _check(unchanged.generation and unchanged.persisted_envelope and unchanged.rules and unchanged.player,"failed write leaves original generation credit and every player field unchanged",unchanged)
    var before_repair: Dictionary = State.capture(first.player,Capture.PLAYER_ID)
    var repaired: Dictionary = first.service.request(1,1,first.ability,first.world.clock_seconds)
    if not _check(repaired.ok and repaired.code=="service_committed" and repaired.healed_hp==25 and repaired.generation==2,"same real request succeeds after storage fault is removed",repaired): _finish(); return
    var after_repair: Dictionary = State.capture(first.player,Capture.PLAYER_ID)
    var expected: Dictionary = before_repair.duplicate(true)
    expected.health += 25.0
    expected.state.damage.health = expected.health
    _check(after_repair==expected and first.player.collision_count==3,"only hull health changes; armor component damage serial battery heat timers position and velocity remain exact")
    var consumed: Dictionary = first.live.context.rules.snapshot()
    _check(consumed.jobs_completed==1 and consumed.service_credit==0 and consumed.services_consumed==1 and consumed.service_serial==1 and consumed.job_requested and consumed.pending_action.is_empty() and first.live.executor.report().waiting_for_beneficiary,"original ledger consumes exactly once and executor explicitly awaits a new beneficiary")
    var saved_repair: Dictionary = independent.read()
    _check(saved_repair.generation==2 and Capture.validate(saved_repair.envelope).ok and saved_repair.envelope.player.flight.health==after_repair.health and saved_repair.envelope.site.rules.services_consumed==1,"single real Store generation contains both consumed credit and repaired absolute hull")
    var duplicate: Dictionary = first.service.request(1,1,first.ability,first.world.clock_seconds)
    var extra: Dictionary = first.service.request(2,2,first.ability,first.world.clock_seconds)
    _check(duplicate.ok and duplicate.code=="already_serviced" and duplicate.healed_hp==0 and not extra.ok and extra.code=="awaiting_new_beneficiary" and State.capture(first.player,Capture.PLAYER_ID)==after_repair and first.live.context.rules.snapshot()==consumed and independent.read().generation==2,"old press is idempotent and a new press cannot reuse the departed beneficiary",{"duplicate":duplicate,"new_request":extra})
    var max_anchor_error := 0.0
    var original_action_serial: int = int(consumed.action_serial)
    for i in 300:
        if not await _tick(): _finish(); return
        max_anchor_error = maxf(max_anchor_error,first.live.context.carrier.global_position.distance_to(first.live.executor.report().hold.target))
    var ongoing: Dictionary = first.live.context.rules.snapshot()
    _check(ongoing.pending_action.is_empty() and ongoing.action_serial==original_action_serial and ongoing.jobs_completed==1 and ongoing.services_consumed==1 and ongoing.service_credit==0 and first.live.workbench.report().receipt_count==1,"five seconds of real host chain never starts or awards a second work order")
    _check(max_anchor_error<.18 and first.live.executor.report().waiting_for_beneficiary and first.live.executor.report().controller.arrived,"consumed waiting uses real swept Pilot against wind",{"maximum_anchor_error_m":max_anchor_error})
    var command_before: Dictionary = first.live.context.carrier.command.duplicate(true)
    var custody_before: Dictionary = first.live.context.custody.report()
    var client_tick: Dictionary = first.live.executor.tick(DT,false,false)
    _check(not client_tick.ok and first.live.context.carrier.command==command_before and first.live.context.custody.report()==custody_before,"client cannot advance the new waiting mode or write input")
    var paused_tick: Dictionary = first.live.executor.tick(0,true,true)
    _check(paused_tick.ok and first.live.context.rules.snapshot()==ongoing and first.live.context.custody.report()==custody_before,"host pause only brakes; no custody or Rules advancement")
    var later: Dictionary = await _safe(first)
    if later.is_empty(): _finish(); return
    var later_save: Dictionary = repo.save(later,"post-service-normal-save",2)
    if not _check(later_save.ok and later_save.generation==3,"normal full checkpoint remains valid after service",{"code":later_save.get("code","")}): _finish(); return
    var health_later: float = first.player.health
    var late_duplicate: Dictionary = first.service.request(1,1,first.ability,first.world.clock_seconds)
    _check(late_duplicate.ok and late_duplicate.generation==3 and late_duplicate.healed_hp==0 and first.player.health==health_later and independent.read().envelope==later_save.envelope,"old request cannot roll back a later saved generation or reapply health",late_duplicate)
    # A fresh isolated actual World, not a reset of the first live instance.
    var second: Dictionary = await _restore(later_save.envelope.site)
    if second.is_empty(): _finish(); return
    second.world.clock_seconds = float(later_save.envelope.world_clock)
    second.ability = later_save.envelope.ability.duplicate(true)
    var restored_player: Dictionary = Capture.restore_player_fresh(second.world,later_save.envelope.player,second.world.sample_environment)
    if not _check(restored_player.ok,"consumed checkpoint restores its real player",{"code":restored_player.get("code","")}): _finish(); return
    second.player = restored_player.body
    _check(repo._store.matches_persisted_value(State.capture(second.player,Capture.PLAYER_ID),later_save.envelope.player.flight) and second.player.collision_count==3,"fresh player keeps saved damage resources and collision count exactly across JSON")
    second.pilot = Pilot.new()
    if not _check(second.pilot.bind(second.player) and second.pilot.go_to(State.transform(later_save.envelope.player.flight.pose).origin,1),"restored player resumes normal swept hold"): _finish(); return
    second.service = Service.new()
    if not _check(second.service.configure(second.live.context,second.live.executor,second.live.workbench,second.live.cooling,second.player,independent).ok,"fresh service adapter binds restored objects"): _finish(); return
    var health_at_load: float = second.player.health
    var repeated_after_load: Dictionary = second.service.request(1,3,second.ability,second.world.clock_seconds)
    _check(repeated_after_load.ok and repeated_after_load.code=="already_serviced" and second.player.health==health_at_load and second.live.executor.report().waiting_for_beneficiary,"fresh adopt derives waiting from consumed Rules and old request is still a no-op",repeated_after_load)
    var restored_max_error := 0.0
    for i in 300:
        if not await _tick(): _finish(); return
        restored_max_error = maxf(restored_max_error,second.live.context.carrier.global_position.distance_to(second.live.executor.report().hold.target))
    var final_state: Dictionary = second.live.context.rules.snapshot()
    _check(final_state.pending_action.is_empty() and final_state.action_serial==original_action_serial and final_state.services_consumed==1 and final_state.service_credit==0 and final_state.jobs_completed==1 and second.live.workbench.report().receipt_count==1 and restored_max_error<.18,"restored consumed world runs another five seconds without new pending work credit or wind drift",{"maximum_anchor_error_m":restored_max_error})
    evidence.result = {"profile":path,"repair":repaired,"failed_publish":failed,"health_before":before_repair.health,"health_after":after_repair.health,"before_damage":before_repair.state.damage,"after_damage":after_repair.state.damage,"original_max_anchor_error_m":max_anchor_error,"restored_max_anchor_error_m":restored_max_error,"service_serial":final_state.service_serial,"action_serial":final_state.action_serial,"generation":independent.read().generation}
    _finish()

func _restore(saved: Dictionary) -> Dictionary:
    var view := SubViewport.new()
    view.own_world_3d = true
    view.world_3d = World3D.new()
    view.render_target_update_mode = SubViewport.UPDATE_DISABLED
    root.add_child(view)
    views.append(view)
    var world = World.new()
    view.add_child(world)
    world.build("I2",{},true)
    if not _check(world.build_errors.is_empty(),"production I2 geometry builds",{"errors":world.build_errors}): return {}
    for i in 3:
        if not await _tick(): return {}
    var restorer = Restore.new()
    var started: Dictionary = restorer.prepare(world,saved,world.sample_environment,true)
    if not _check(started.ok,"real completed site reconstruction begins",{"code":started.get("code","")}): return {}
    for i in 600:
        if not await _tick(): return {}
        world.clock_seconds += DT
        var result: Dictionary = restorer.tick(DT,true,false)
        if not result.ok:
            _check(false,"site reconstruction remains valid",result)
            return {}
        if result.ready:
            var live: Dictionary = restorer.adopt(true)
            if not _check(live.ok,"real support ready/adopt succeeds",{"code":live.get("code","")}): return {}
            var host: Dictionary = {"world":world,"live":live,"ticks":0,"usec":0,"ability":{"energy":37.5,"selected":"charge","cooldown":.21,"actor_revision":4,"station_serial":9},"observer":Capture.new()}
            hosts.append(host)
            return host
    _check(false,"site restore bounded wait",restorer.report())
    return {}

func _safe(host: Dictionary) -> Dictionary:
    var trace: Array = []
    for i in 600:
        if not await _tick(): return {}
        var observed: Dictionary = host.observer.capture(host.live.context,host.live.executor,host.live.workbench,host.live.cooling,host.player,host.ability,host.world.clock_seconds,true,false)
        if i%60==0 or observed.ok: trace.append({"tick":i,"code":observed.code})
        if observed.ok: return observed.envelope.duplicate(true)
    _check(false,"actual player and site safe boundary reached in time",{"trace":trace})
    return {}

func _tick() -> bool:
    await physics_frame
    for host: Dictionary in hosts:
        host.world.clock_seconds += DT
        var control: Dictionary = {}
        if host.has("player"):
            host.player.environment_sample = host.world.sample_environment(host.player.global_position)
            control = host.pilot.tick(DT,true,false)
        var moved: Dictionary = host.live.executor.tick(DT,true,false)
        var cooled: Dictionary = host.live.cooling.advance(DT,true)
        host.ticks += 1
        var next_usec: int = roundi(float(host.ticks)*1000000.0/60.0)
        var flowed: Dictionary = host.live.context.rules.step(next_usec-int(host.usec),host.live.cooling.facts(),true,false)
        host.usec = next_usec
        var worked: Dictionary = host.live.workbench.advance(DT,true,false)
        if not moved.ok or not cooled.ok or not flowed.ok or not worked.ok or control.get("state","")=="blocked":
            healthy = false
            _check(false,"normal host chain remains valid",{"executor":moved,"cooling":cooled,"rules":flowed,"workbench":worked,"player":control})
            return false
        if host.has("service"): host.service.observe(host.ability,host.world.clock_seconds,true,false)
    return not finished

func _check(ok: bool, label: String, details: Dictionary = {}) -> bool:
    checks += 1
    if not ok: failures.append({"label":label,"details":details.duplicate(true)})
    return ok

func _finish() -> void:
    if finished: return
    finished = true
    _check(healthy and logger.errors.is_empty(),"no physical host faults or engine errors",{"errors":logger.errors})
    for host: Dictionary in hosts:
        host.live.executor.close(true)
        host.live.workbench.close(true)
    for view: SubViewport in views:
        if is_instance_valid(view): view.free()
    print("V3_CANAL_PLAYER_SERVICE_TESTS "+JSON.stringify({"checks":checks,"failures":failures,"engine_errors":logger.errors,"evidence":evidence,"scope":"real saved-site QA and actual player damage/Store; no new work replay, MAIN integration, multiplayer or human-play claim"}))
    quit(0 if failures.is_empty() and logger.errors.is_empty() else 1)
