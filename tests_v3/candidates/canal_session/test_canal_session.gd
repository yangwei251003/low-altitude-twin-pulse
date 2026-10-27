extends SceneTree
## Real MAIN/Session/World + original Assembly. QA old27 grants I2 entry only.
## One stationary player pose is a LOS/input fixture, NOT a flown route.
## Automatic world save is explicitly disabled: no persistence integration yet.
const MAIN = preload("res://scenes/v3/main.tscn")
const Adapter = preload("res://scripts/v3/gameplay/twin_canal_session.gd")
const Director = preload("res://scripts/v3/gameplay/actions/twin_action_director.gd")
const ActionData = preload("res://tests_v3/test_clinic_action.gd")
const DT := 1.0/60.0
var session
var adapter = Adapter.new()
var output := ""
var profile := ""
var done := false
var checks: Array = []
var failures: Array = []
var snapshots: Dictionary = {}
class ErrorLog extends Logger:
    var errors: Array = []
    func _log_error(fn: String, file: String, line: int, code: String, reason: String, _notify: bool, kind: int, _trace: Array[ScriptBacktrace]) -> void:
        errors.append({"function":fn, "file":file, "line":line, "code":code, "reason":reason, "kind":kind})
var logger = ErrorLog.new()

func _initialize() -> void:
    OS.add_logger(logger)
    for arg: String in OS.get_cmdline_user_args():
        if arg.begins_with("--output="): output = arg.trim_prefix("--output=")
        if arg.begins_with("--qa-profile="): profile = arg.trim_prefix("--qa-profile=")
    _run.call_deferred()

func _run() -> void:
    create_timer(55).timeout.connect(func():
        if not done:
            _check(false, "55 second bound", adapter.status())
            _finish())
    if not _check(profile.begins_with("qa_canal_session_") and not DirAccess.dir_exists_absolute("user://profiles_v3/" + profile), "new isolated QA profile required"): _finish(); return
    var script: Script = Adapter
    if not _check(script.can_instantiate(), "adapter parsed before MAIN mutation"): _finish(); return
    session = MAIN.instantiate()
    root.add_child(session)
    session.set_process(false)
    session.set_physics_process(false)
    session.inputs.set_process(false)
    session.inputs.set_physics_process(false)
    if not _check(session.profile_ready and session.start_flight("solo"), "real MAIN starts solo"): _finish(); return
    if not _seed_old27(): _finish(); return
    if not _check(session._load_region("I2"), "production MAIN constructs and presents actual I2"): _finish(); return
    # No source hook exists yet. Owns_world=false blocks the existing eight-
    # second autosave, which otherwise stores partial six-target state only.
    session.owns_world = false
    session.inputs.test_enabled = true
    session.inputs.test_frame = {"axes":{}, "held":["brake"]}
    var player: FlightBodyV2 = session.players[1]
    player.freeze = true
    player.global_transform = Transform3D(Basis.IDENTITY, Vector3(8,3.2,27))
    player.linear_velocity = Vector3.ZERO
    player.angular_velocity = Vector3.ZERO
    player.hold_height = player.global_position.y
    player.force_update_transform()
    PhysicsServer3D.body_set_state(player.get_rid(), PhysicsServer3D.BODY_STATE_TRANSFORM, player.global_transform)
    await physics_frame
    await physics_frame
    snapshots.original_facilities = _facilities()
    var original_world: Node = session.world
    var original_player: Node = player
    var saved_before: Dictionary = session.store.snapshot().duplicate(true)
    adapter.setup(session)
    _check(not adapter.prepare({}, "I2", false).ok, "client cannot create an unreplicated live site")
    _check(not adapter.prepare({"environment":{"canal_candidate_checkpoint":{}}}, "I2", true).ok, "existing unsupported saved state cannot silently initialize a fresh site")
    var prepared: Dictionary = adapter.prepare(session.world_cache.world, "I2", true)
    if not _check(prepared.ok and not prepared.module.is_inside_tree() and not adapter.ready, "prepare remains detached and unready"): _finish(); return
    var actual_world = session.world
    var detached_world = session.World.new()
    session.world = detached_world # Explicit lifecycle-negative fixture only.
    var detached_adopt: Dictionary = adapter.adopt(prepared)
    session.world = actual_world
    detached_world.free()
    _check(not detached_adopt.ok and detached_adopt.code == "live_current_world_required" and prepared.module.get_parent() == null and not adapter.ready, "detached current World cannot consume the candidate or claim ready")
    var installed: Dictionary = adapter.adopt(prepared, session.world_cache.world)
    if not _check(installed.ok and not adapter.ready, "adopt only starts real Bootstrap", installed): _finish(); return
    var identity: int = adapter.module.get_instance_id()
    for unused in 2700:
        if not await _frame(): _finish(); return
        if adapter.ready: break
    if not _check(adapter.ready, "actual original cargo pickup/lift reaches WAIT", adapter.module.status(true)): _finish(); return
    _check(adapter.module.get_instance_id() == identity and session.world == original_world and session.players[1] == original_player, "same installed site/world/player throughout bootstrap")
    _check(adapter.status().target_count == 6 and _facilities() == snapshots.original_facilities, "six real targets appear without replacing the four facilities")
    var ctx: Dictionary = adapter.context()
    for id: String in Adapter.IDS:
        var body: PhysicsBody3D = session.world.objects[id]
        _check(body.is_inside_tree() and body.get_world_3d().space == session.world.get_world_3d().space and body.get_meta("entity_id", "") == id and session.world.definitions[id].id == id and session.entities[id].id == id, "body/definition/entity registration: " + id)
    _check(ctx.carrier.cargo_items.size() == 1 and ctx.rules.snapshot().jobs_completed == 0, "bootstrap is real carrying, not a completed service")
    var relay: String = Adapter.Assembly.RELAY_ID
    var valve: String = Adapter.Assembly.VALVE_ID
    _check(session._line_clear(player.global_position, session.world.objects[relay].global_position, player.get_rid(), relay), "actual relay LOS accepts new entity_id metadata")
    var actor: String = session._actor_id(1)
    var energy: float = float(session.entities[actor].energy)
    var revision: int = int(session.entities[actor].revision)
    var charged: Dictionary = adapter.use_ability(1, {"ability":"charge", "target_id":relay})
    if not _check(charged.ok, "real Rules-authorized relay charge accepted once", charged): _finish(); return
    _check(is_equal_approx(float(ctx.cooling.report().charge), 35.0) and session.entities[relay].charge == ctx.cooling.report().charge and session.entities[relay].powered, "physical and generic charge agree after domain acceptance")
    _check(is_equal_approx(float(session.entities[actor].energy), energy-8.0) and int(session.entities[actor].revision) == revision+1 and is_equal_approx(float(session.cooldowns[1]), .35), "one real actor energy/revision/cooldown commit")
    _rejected(1, {"ability":"charge", "target_id":relay}, "cooldown", "cooldown rejection is atomic")
    for unused in 24:
        if not await _frame(): _finish(); return
    _rejected(999, {"ability":"charge", "target_id":relay}, "actor_missing", "unknown peer cannot spend host energy or touch device")
    var owner_before: String = str(session.entities[actor].owner)
    session.entities[actor].owner = "different_peer" # Explicit hostile-owner fixture.
    _rejected(1, {"ability":"charge", "target_id":relay}, "not_owner", "real Rules denies peer with mismatched actor ownership")
    session.entities[actor].owner = owner_before
    _rejected(1, {"ability":"charge", "target_id":relay, "actor_revision":-1}, "stale_actor", "stale actor transaction rejected")
    _rejected(1, {"ability":"heat", "target_id":relay}, "unsupported_target", "unmatched ability cannot change a conductive target")
    var high_target: PhysicsBody3D = session.world.objects[Adapter.Assembly.Workbench.POWER_ID]
    var high_los: bool = session._line_clear(player.global_position, high_target.global_position, player.get_rid(), Adapter.Assembly.Workbench.POWER_ID)
    _check(player.global_position.distance_to(high_target.global_position) > 12.0, "workbench is outside actual charge range from this QA pose")
    _rejected(1, {"ability":"charge", "target_id":Adapter.Assembly.Workbench.POWER_ID}, "out_of_range" if high_los else "line_of_sight_required", "remote workbench rejected by actual range/first-hit ordering")
    # The domain can reject after a VALID generic private commit. No live
    # actor/target energy, revision or cooldown may leak from that staging.
    _check(adapter.module.set_paused(true, true).ok, "domain independently unavailable fixture")
    _rejected(1, {"ability":"charge", "target_id":relay}, "canal:not_available", "late domain refusal rolls back generic intent without mutation")
    _check(adapter.module.set_paused(false, true).ok, "domain resumes through public controller API")
    if not await _frame(): _finish(); return
    # Real opaque collider in the ray, not a supplied line_of_sight=false flag.
    var wall := StaticBody3D.new()
    wall.collision_layer = 1
    var shape_node := CollisionShape3D.new()
    var box := BoxShape3D.new()
    box.size = Vector3(.8,.8,.8)
    shape_node.shape = box
    wall.add_child(shape_node)
    session.world.add_child(wall)
    wall.global_position = player.global_position.lerp(session.world.objects[relay].global_position, .5)
    await physics_frame
    await physics_frame
    _rejected(1, {"ability":"charge", "target_id":relay}, "line_of_sight_required", "real occluder denies ability with no charge or energy change")
    wall.free()
    if not await _frame(): _finish(); return
    var serial: int = int(adapter.module.status().device_serial)
    var pushed: Dictionary = adapter.use_ability(1, {"ability":"push_pull", "mode":"pull", "target_id":valve})
    if not _check(pushed.ok and pushed.physics_executed_by_assembly, "actual valve impulse uses the single Assembly path", pushed): _finish(); return
    _check(int(adapter.module.status().device_serial) == serial+1 and int(ctx.cooling.snapshot().axis.last_serial["1"]) == serial+1, "one axis impulse serial, no generic RigidBody second execution")
    for unused in 90:
        if not await _frame(): _finish(); return
    _check(ctx.cooling.facts().valve_open and session.entities[valve].position.is_equal_approx(ctx.cooling.valve.global_position), "actual swept valve moves and entity follows the real body", ctx.cooling.report())
    # Explicit lease fixture only, not a fabricated successful takeover.
    session.entities[relay].merge({"owner":"qa_existing_lease", "revision":123, "takeover_remaining":5.0}, true)
    if not await _frame(): _finish(); return
    _check(session.entities[relay].owner == "qa_existing_lease" and session.entities[relay].revision == 124 and session.entities[relay].takeover_remaining < 5.0, "physical synchronization preserves owner and normal Rules timer revision")
    var control_state: Dictionary = ctx.rules.snapshot().duplicate(true)
    _check(adapter.set_paused(true).ok, "adapter pauses controls")
    _rejected(1, {"ability":"charge", "target_id":relay}, "canal_paused_or_busy", "paused transaction is atomic")
    for unused in 10:
        if not await _frame(): _finish(); return
    _check(ctx.rules.snapshot() == control_state, "pause accrues no private rule time; physical freeze remains host responsibility")
    _check(adapter.set_paused(false).ok and not adapter.status().persistence_supported and not adapter.status().client_state_supported, "unsupported save/client scope is explicit")
    var replacement: Dictionary = adapter.prepare({}, "I2", true)
    var denied: Dictionary = adapter.adopt(replacement)
    _check(not denied.ok and adapter.module.get_instance_id() == identity, "failed adoption preserves live old site")
    adapter.discard(replacement)
    _check(session.store.snapshot() == saved_before, "QA-disabled automatic saves leave original isolated Store untouched after initial history")
    _check(ctx.rules.snapshot().jobs_completed == 0 and ctx.rules.snapshot().service_credit == 0 and not adapter.module.status().ordered, "short adapter test awards no work or service and issues no work order")
    # Explicit lifecycle fixture: a newer registry owner reuses one stable ID.
    # clear must compare identities, not delete every familiar ID by name.
    var newer := StaticBody3D.new()
    session.world.add_child(newer)
    var newer_entity: Dictionary = {"id":relay, "revision":777, "owner":"new_owner"}
    session.world.objects[relay] = newer
    session.world.definitions[relay] = {"id":relay, "name":"new registry owner"}
    session.world.initial_transforms[relay] = Transform3D.IDENTITY
    session.entities[relay] = newer_entity
    adapter.clear()
    _check(session.world.objects.get(relay) == newer and is_same(session.entities.get(relay), newer_entity) and session.world.definitions[relay].name == "new registry owner", "clear preserves same-ID newer physical and entity registrations")
    newer.free()
    session.world.objects.erase(relay)
    session.world.definitions.erase(relay)
    session.world.initial_transforms.erase(relay)
    session.entities.erase(relay)
    _check(_facilities() == snapshots.original_facilities and is_instance_valid(original_world) and is_instance_valid(original_player), "clear removes own site, preserves World/player/four facilities")
    for id: String in Adapter.IDS:
        _check(not session.world.objects.has(id) and not session.entities.has(id) and not session.world.definitions.has(id), "clear unregisters only owned target: " + id)
    _finish()

func _seed_old27() -> bool:
    var director = Director.new()
    var loaded: Dictionary = director.load_definitions(Director.DEFAULT_PATH, ActionData.OLD_EXTENSIONS)
    if not _check(loaded.ok, "explicit old27 QA history definitions"): return false
    var state: Dictionary = director.default_state()
    for row: Array in ActionData.OLD_EVENTS:
        var applied: Dictionary = director.apply_event(state, {"id":"qa-canal-old:"+str(row[0]), "type":row[1], "target_id":row[2], "option":row[3]}, {"is_authority":true, "validated":true, "region_id":str(row[0]).get_slice(":",0)})
        if not _check(applied.get("changed",false), "historical fixture event " + str(row[0])): return false
        state = applied.state
    var result: Dictionary = session.store.commit({"id":"qa-canal-old27", "set":{"world.actions.opening":state, "world.flags":state.flags, "world.completed_objectives":state.completed}, "append":{"personal.discoveries":state.discoveries}})
    if not _check(result.ok and state.completed.size() == 27, "only previous27 QA fixture committed, not canal completion"): return false
    session.world_cache = session.store.snapshot()
    return true

func _frame() -> bool:
    await physics_frame
    if done: return false
    session._physics_process(DT)
    var result: Dictionary = adapter.advance(DT)
    if not result.ok:
        _check(false, "same live host Assembly physics step", result)
        return false
    if not logger.errors.is_empty(): return false
    return true

func _rejected(peer: int, payload: Dictionary, code: String, label: String) -> void:
    var before: Dictionary = {"entities":session.entities.duplicate(true), "cooldowns":session.cooldowns.duplicate(true), "device":adapter.context().cooling.snapshot(), "rules":adapter.context().rules.snapshot(), "abilities":session.stats.abilities}
    var result: Dictionary = adapter.use_ability(peer, payload)
    var after: Dictionary = {"entities":session.entities.duplicate(true), "cooldowns":session.cooldowns.duplicate(true), "device":adapter.context().cooling.snapshot(), "rules":adapter.context().rules.snapshot(), "abilities":session.stats.abilities}
    _check(not result.ok and result.code == code and before == after, label, {"result":result, "unchanged":before == after})

func _facilities() -> Dictionary:
    var result: Dictionary = {}
    for name: String in ["clinic", "distribution", "trial", "shared_access"]:
        var facility: Node3D = session.world.get(name)
        result[name] = {"id":facility.get_instance_id(), "transform":facility.global_transform, "space":str(facility.get_world_3d().space)}
    return result

func _check(ok: bool, label: String, detail: Variant = null) -> bool:
    checks.append({"ok":ok, "label":label, "detail":detail})
    if not ok: failures.append(label)
    return ok

func _finish() -> void:
    if done: return
    done = true
    snapshots.final_status = adapter.status()
    adapter.clear()
    if is_instance_valid(session): session.free()
    var report: Dictionary = {"checks":checks.size(), "failures":failures, "engine_errors":logger.errors, "details":checks, "snapshots":snapshots, "scope":"real MAIN source candidate only; old27/profile and initial stationary pose are QA fixtures; no enabled production hooks, saves, network or completed canal work"}
    if not output.is_empty():
        var file := FileAccess.open(output.path_join("result.json"), FileAccess.WRITE)
        if file: file.store_string(JSON.stringify(report,"\t",true,true))
    print("CANAL_SESSION ", JSON.stringify({"checks":checks.size(), "failures":failures, "engine_errors":logger.errors}))
    quit(0 if failures.is_empty() and logger.errors.is_empty() else 1)
