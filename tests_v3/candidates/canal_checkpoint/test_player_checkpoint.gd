extends SceneTree
## Real lane-clear F5 site is a declared fixture; transport/work is not replayed.
## Source run: 57 checks passed, actual F5/F9 and subsequent host continuation.
## The prior 51/1 energy-prerequisite failure remains in fixture provenance.
## New player pose/history/ability values remain explicit QA fixtures.
const World = preload("res://scripts/v3/twin_test_world.gd")
const Restore = preload("res://scripts/v3/candidates/canal_checkpoint/canal_checkpoint_restore.gd")
const Capture = preload("res://scripts/v3/candidates/canal_checkpoint/player_checkpoint.gd")
const Repository = preload("res://scripts/v3/candidates/canal_checkpoint/checkpoint_repository.gd")
const State = preload("res://scripts/v3/candidates/canal_checkpoint/flight_state.gd")
const Pilot = preload("res://scripts/v3/candidates/canal_transport_physics/transport_pilot.gd")
const FIXTURE := "res://tests_v3/candidates/canal_checkpoint/evidence/checkpoint_v3_lane_clear_passed_actual.json"
const FIXTURE_SHA := "c02925ec7c6c38c6d2cf3acf841d2b54e265547a5f4faac3f1668718e6d2490f"
const DT := 1.0/60.0
var checks := 0
var failures: Array = []
var evidence: Dictionary = {}
var views: Array[SubViewport] = []
var world: World
var restorer = Restore.new()
var live: Dictionary = {}
var player: RigidBody3D
var pilot = Pilot.new()
var observer = Capture.new()
var ability: Dictionary = {"energy":37.5,"selected":"charge","cooldown":.21,"actor_revision":4,"station_serial":9}
var live_ticks := 0
var elapsed_usec := 0
var finished := false

class ErrorLog extends Logger:
    var errors: Array = []
    func _log_error(fn: String,file: String,line: int,code: String,reason: String,_notify: bool,kind: int,_traces: Array[ScriptBacktrace]) -> void:
        errors.append({"function":fn,"file":file,"line":line,"code":code,"reason":reason,"kind":kind})
var logger := ErrorLog.new()

func _init() -> void:
    OS.add_logger(logger)
    _run.call_deferred()

func _run() -> void:
    create_timer(35).timeout.connect(func():
        if not finished:
            _check(false,"player checkpoint short timeout")
            _finish())
    for script: Script in [Capture,Repository,Restore]:
        if not _check(script.can_instantiate(),"actual script can instantiate",{"path":script.resource_path}): _finish(); return
    if not _check(FileAccess.get_sha256(FIXTURE)==FIXTURE_SHA and Engine.physics_ticks_per_second==60 and Engine.time_scale==1,"actual fixture and normal physical clock"):
        _finish(); return
    var fixture: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(FIXTURE))
    evidence.fixture = {"path":FIXTURE,"sha256":FIXTURE_SHA,"source":"canal-player-checkpoint-20261020_050633_87e6e4/first_saved.json#site","scope":"actual saved site plus explicitly authored new player/ability/history fixtures"}
    world = _new_world()
    if not _check(world.build_errors.is_empty(),"actual I2 builds",{"errors":world.build_errors}): _finish(); return
    world.clock_seconds = 901.125 # Explicit world-clock fixture, not offline catch-up.
    for i in 3: await physics_frame
    var started: Dictionary = restorer.prepare(world,fixture,world.sample_environment,true)
    if not _check(started.ok,"actual site reconstruction starts",started): _finish(); return
    var ready := false
    for i in 900:
        await physics_frame
        world.clock_seconds += DT
        var state: Dictionary = restorer.tick(DT,true,false)
        if not state.ok:
            _check(false,"saved site restores before player QA",state)
            break
        if state.ready:
            live = restorer.adopt(true)
            ready = live.ok
            break
    if not _check(ready,"actual site is adopted without new work"): _finish(); return
    var row: Dictionary = fixture.checkpoint.carrier.duplicate(true)
    row.id = Capture.PLAYER_ID
    row.pose = State.pose(Transform3D(Basis.IDENTITY,Vector3(3.5,2.8,20)))
    row.velocity = [0.0,0.0,0.0]
    row.angular_velocity = [0.0,0.0,0.0]
    row.state.hold_height = 2.8
    row.state.heading = 0.0
    row.state.safe_position = [3.5,2.8,20.0]
    row.state.battery = 73.25
    row.state.heat = 19.5
    var made: Dictionary = State.create(world,row,Capture.PLAYER_ID,45,world.sample_environment)
    if not _check(made.ok,"fresh explicitly located player fixture",made): _finish(); return
    player = made.body
    var hit: Dictionary = player.apply_combat_hit(6,Vector3.ZERO,player.to_global(Vector3(0,0,.4)),"pulse",{"qa_public_settlement":true})
    player.collision_count = 3 # Declared historical count; not three simulated crashes.
    player.contact_cooldowns[123456789] = player.flight_seconds-1.0
    evidence.damage_receipt = hit.duplicate(true)
    if not _check(not hit.is_empty() and pilot.bind(player) and pilot.go_to(Vector3(3.5,2.8,20),1),"damaged real player holds through original swept Pilot",hit): _finish(); return
    var saved: Dictionary = {}
    var repeated_checked := false
    var progress: Array = []
    for i in 600:
        var advanced: bool = await _tick()
        if not advanced: _finish(); return
        var result: Dictionary = _capture()
        if i % 60==0 or result.ok: progress.append({"tick":i,"code":result.code,"observed_usec":result.get("observed_usec",350000 if result.ok else 0)})
        if result.code=="stability_pending" and not repeated_checked:
            var repeated: Dictionary = _capture()
            _check(not repeated.ok and repeated.observed_usec==result.observed_usec,"same-frame capture cannot gain observation credit",{"first":result,"again":repeated})
            repeated_checked=true
        if result.ok:
            saved=result.envelope.duplicate(true)
            break
    evidence.capture_progress=progress
    if not _check(not saved.is_empty() and repeated_checked,"real player/site capture reaches 350ms",{"trace":progress}): _finish(); return
    _check(saved.player.collision_count==3 and saved.player.flight.health<100 and saved.player.flight.state.battery<73.25 and saved.player.flight.state.heat==19.5 and saved.ability==ability and saved.world_clock==world.clock_seconds,"capture preserves injury battery heat abilities clock and historical collision count")
    _check(player.contact_cooldowns.has(123456789),"expired contact IDs are ignored for persistence without clearing live history")
    var original_rules: Dictionary = live.context.rules.snapshot()
    var recent_stamp: float = player.flight_seconds
    player.contact_cooldowns[987654321]=recent_stamp # Adversarial recent-hit fixture.
    var recent: Dictionary = _capture()
    _check(not recent.ok and recent.code=="recent_player_collision" and live.context.rules.snapshot()==original_rules,"recent collision rejects save without clearing the world",recent)
    player.contact_cooldowns.erase(987654321)
    for key: String in ["unknown_key","version","kind","layout"]:
        var broken: Dictionary=saved.duplicate(true)
        if key=="unknown_key": broken.unexpected=true
        elif key=="version": broken.version=2
        elif key=="kind": broken.kind="other_save"
        else: broken.layout.sha256="0".repeat(64)
        _check(not Capture.validate(broken).ok,"unknown schema/kind/layout is rejected: "+key)
    var bad_ability: Dictionary=saved.duplicate(true)
    bad_ability.ability.takeover_remaining=1.0
    _check(not Capture.validate(bad_ability).ok,"unknown ability lease cannot be silently discarded")
    bad_ability=saved.duplicate(true)
    bad_ability.ability.station_serial=0
    _check(not Capture.validate(bad_ability).ok,"restored command sequence cannot precede existing device inputs")
    var forbidden=Repository.new("user://profiles_v3/default")
    _check(not forbidden.read().ok,"real default profile is refused before Store creation")
    var path: String="user://qa_v3/player_checkpoint_"+str(Time.get_ticks_usec())
    var repo=Repository.new(path)
    var empty: Dictionary=repo.read()
    if not _check(empty.ok and empty.empty and empty.generation==0,"unique QA profile starts empty",empty): _finish(); return
    var stored: Dictionary=repo.save(saved,"first",0)
    if not _check(stored.ok and not stored.duplicate and stored.generation==1,"actual Store publishes first checkpoint generation",{"result":stored.get("code","")}): _finish(); return
    var independent=Repository.new(path)
    var loaded: Dictionary=independent.read()
    _check(loaded.ok and not loaded.empty and Capture.validate(loaded.envelope).ok and _numeric_equal(loaded.envelope,saved),"independent read preserves serialized state without world advancement")
    var duplicate: Dictionary=repo.save(saved,"first",0)
    _check(duplicate.ok and duplicate.duplicate and duplicate.generation==1,"identical transaction retry uses Store receipt without another generation")
    var changed: Dictionary=saved.duplicate(true)
    changed.world_clock+=1.0 # Valid altered persistence candidate, not physical elapsed time.
    var conflict: Dictionary=repo.save(changed,"first",0)
    _check(not conflict.ok and conflict.code=="store:SAVE_RECEIPT_CONFLICT","same ID with another payload remains rejected",conflict)
    var stale: Dictionary=repo.save(saved,"stale",0)
    _check(not stale.ok and stale.code=="generation_changed","stale generation cannot overwrite the current save",stale)
    repo._store.failure_point="before_publish"
    var failed: Dictionary=repo.save(saved,"interrupted",1)
    repo._store.failure_point=""
    var intact: Dictionary=independent.read()
    _check(not failed.ok and intact.ok and intact.generation==1 and _numeric_equal(intact.envelope,loaded.envelope),"real Store failure preserves the previous complete checkpoint",failed)
    loaded.envelope.ability.energy=0
    _check(independent.read().envelope.ability.energy==ability.energy,"read returns an isolated value, not mutable Store state")
    var second_world: World=_new_world()
    if not _check(second_world.build_errors.is_empty(),"fresh destination production I2 builds",{"errors":second_world.build_errors}): _finish(); return
    var blocked_at: Vector3=State.transform(saved.player.flight.pose).origin
    var blocker:=StaticBody3D.new()
    blocker.position=blocked_at
    blocker.collision_layer=1
    var collider:=CollisionShape3D.new()
    var box:=BoxShape3D.new()
    box.size=Vector3(.2,.8,.2)
    collider.shape=box
    blocker.add_child(collider)
    second_world.add_child(blocker)
    for i in 2: await physics_frame
    var children: int=second_world.get_child_count()
    var denied: Dictionary=Capture.restore_player_fresh(second_world,saved.player,second_world.sample_environment)
    _check(not denied.ok and denied.code=="player_envelope_obstructed" and second_world.get_child_count()==children,"fresh restore checks full real envelope before allocating a player",denied)
    blocker.free()
    await physics_frame
    var restored: Dictionary=Capture.restore_player_fresh(second_world,saved.player,second_world.sample_environment)
    if _check(restored.ok,"fresh clear player reconstruction succeeds",{"code":restored.get("code","")}):
        _check(_numeric_equal(State.capture(restored.body,Capture.PLAYER_ID),saved.player.flight) and restored.body.collision_count==3 and restored.body.contact_cooldowns.is_empty(),"new player preserves full damage/timers/resources and collision history without old object IDs")
        _check(not Capture.restore_player_fresh(second_world,saved.player,second_world.sample_environment).ok,"fresh restore cannot replace its existing player")
    _check(player.health==saved.player.flight.health and live.context.rules.snapshot()==original_rules,"failed and successful new-world restore never heals old player or repeats old results")
    # Hash-valid Store data with the wrong application kind must fail closed;
    # Repository may not silently migrate/reset it or replace it on the next save.
    var wrong: Dictionary=saved.duplicate(true)
    wrong.kind="not_a_player_checkpoint"
    var injected: Dictionary=repo._store.commit({"id":"qa-invalid-application-kind","set":{Repository.STATE_PATH:wrong}})
    var rejected: Dictionary=independent.read()
    var refused_save: Dictionary=independent.save(saved,"must-not-reset",2)
    _check(injected.ok and not rejected.ok and not refused_save.ok,"valid Store hash cannot bypass exact application kind on read/save")
    evidence.repository={"path":path,"generation_before_bad_fixture":1,"store_failed_write":failed,"application_rejection":rejected}
    evidence.saved_summary={"health":saved.player.flight.health,"damage":saved.player.flight.state.damage,"battery":saved.player.flight.state.battery,"heat":saved.player.flight.state.heat,"collision_count":saved.player.collision_count,"ability":saved.ability,"world_clock":saved.world_clock,"jobs_completed":saved.site.rules.jobs_completed,"service_credit":saved.site.rules.service_credit}
    _finish()

func _capture() -> Dictionary:
    return observer.capture(live.context,live.executor,live.workbench,live.cooling,player,ability,world.clock_seconds,true,false)

func _tick() -> bool:
    await physics_frame
    world.clock_seconds+=DT
    player.environment_sample=world.sample_environment(player.global_position)
    var controlled: Dictionary=pilot.tick(DT,true,false)
    var moved: Dictionary=live.executor.tick(DT,true,false)
    var cooled: Dictionary=live.cooling.advance(DT,true)
    live_ticks+=1
    var next_usec: int=roundi(float(live_ticks)*1000000.0/60.0)
    var flowed: Dictionary=live.context.rules.step(next_usec-elapsed_usec,live.cooling.facts(),true,false)
    elapsed_usec=next_usec
    var worked: Dictionary=live.workbench.advance(DT,true,false)
    if not moved.ok or not cooled.ok or not flowed.ok or not worked.ok or controlled.get("state","")=="blocked":
        _check(false,"actual host continuation remains valid",{"executor":moved,"cooling":cooled,"rules":flowed,"workbench":worked,"player_control":controlled})
        return false
    return true

func _new_world() -> World:
    var view:=SubViewport.new()
    view.own_world_3d=true
    view.world_3d=World3D.new()
    view.render_target_update_mode=SubViewport.UPDATE_DISABLED
    root.add_child(view)
    views.append(view)
    var result=World.new()
    view.add_child(result)
    result.build("I2",{},true)
    return result

func _numeric_equal(a: Variant,b: Variant) -> bool:
    if (a is int or a is float) and (b is int or b is float): return is_finite(float(a)) and is_finite(float(b)) and absf(float(a)-float(b))<=1e-12
    if a is Dictionary and b is Dictionary:
        if a.size()!=b.size(): return false
        for key: Variant in a:
            if not b.has(key) or not _numeric_equal(a[key],b[key]): return false
        return true
    if a is Array and b is Array:
        if a.size()!=b.size(): return false
        for i in a.size():
            if not _numeric_equal(a[i],b[i]): return false
        return true
    return typeof(a)==typeof(b) and a==b

func _check(ok: bool,label: String,details: Dictionary={}) -> bool:
    checks+=1
    if not ok: failures.append({"label":label,"details":details.duplicate(true)})
    return ok

func _finish() -> void:
    if finished: return
    finished=true
    _check(logger.errors.is_empty(),"no engine errors",{"errors":logger.errors})
    if live.get("ok",false):
        live.executor.close(true)
        live.workbench.close(true)
    else: restorer.discard()
    for view: SubViewport in views:
        if is_instance_valid(view): view.free()
    print("V3_PLAYER_CHECKPOINT_TESTS "+JSON.stringify({"checks":checks,"failures":failures,"engine_errors":logger.errors,"evidence":evidence,"scope":"candidate QA player and actual saved-site fixture; no MAIN/profile migration, full action, network or service-consumption claim"}))
    quit(0 if failures.is_empty() and logger.errors.is_empty() else 1)
