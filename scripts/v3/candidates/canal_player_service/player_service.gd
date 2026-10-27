extends RefCounted
## Candidate host adapter. One existing Rules credit -> <=25 hull HP, using
## the existing full-checkpoint Store transaction. No new reward ledger.
## Caller has already excluded active entity leases before supplying ability.
const Flight = preload("res://scripts/v2/flight_body.gd")
const Capture = preload("res://scripts/v3/candidates/canal_checkpoint/player_checkpoint.gd")
const State = preload("res://scripts/v3/candidates/canal_checkpoint/flight_state.gd")
const Repository = preload("res://scripts/v3/candidates/canal_checkpoint/checkpoint_repository.gd")
const Executor = preload("res://scripts/v3/candidates/canal_transport_executor/canal_transport_executor.gd")
const Bench = preload("res://scripts/v3/candidates/canal_workbench/workbench.gd")
const Cooling = preload("res://scripts/v3/candidates/canal_cooling_station/cooling_station.gd")
const MAX_REPAIR_HP := 25.0
const RANGE_M := 4.0
var _context: Dictionary = {}
var _executor: RefCounted
var _bench: WeakRef
var _cooling: WeakRef
var _player: WeakRef
var _repository: RefCounted
var _observer = Capture.new()
var _configured := false
var _busy := false
var _reload_required := false

func configure(context: Dictionary, executor: RefCounted, workbench: Node3D,
        cooling: Node3D, player: Flight, repository: RefCounted) -> Dictionary:
    if _configured: return _bad("already_bound")
    if not is_instance_valid(executor) or executor.get_script() != Executor or not is_instance_valid(workbench) or workbench.get_script() != Bench or not is_instance_valid(cooling) or cooling.get_script() != Cooling or not is_instance_valid(repository) or repository.get_script() != Repository:
        return _bad("actual_dependencies_required")
    if not _live(player) or not _live(workbench) or not _live(cooling) or player.get_world_3d() != workbench.get_world_3d() or player.get_world_3d() != cooling.get_world_3d(): return _bad("same_live_world_required")
    if context.get("rules") != executor._rules or context.get("rules") != workbench._rules or context.get("custody") != executor._custody or context.get("custody") != workbench._custody or player == context.get("carrier"):
        return _bad("dependency_binding")
    _context = context.duplicate()
    _executor = executor
    _bench = weakref(workbench)
    _cooling = weakref(cooling)
    _player = weakref(player)
    _repository = repository
    _configured = true
    return {"ok":true,"code":"bound_candidate_service"}

## Call after the normal host chain, once per physics frame. The underlying
## capture handles repeated same-frame observations without adding time.
func observe(ability_state: Dictionary, world_clock: float,
        authority: bool = true, paused: bool = false) -> Dictionary:
    var gate: Dictionary = _gate(authority,paused)
    if not gate.ok:
        _observer.reset_observation()
        return gate
    var sampled: Dictionary = _capture(ability_state,world_clock)
    # Do not retain a stale mutable envelope as authorization for a later press.
    return {"ok":sampled.ok,"code":sampled.code,"observed_usec":sampled.get("observed_usec",350000 if sampled.ok else 0)}

## Cancellation/pause/active-lease handling clears only observation credit.
func reset_observation() -> void:
    _observer.reset_observation()

## No await, physics advancement or external callback occurs in this method.
## Only a host press can reach it; a network payload is not proof of service.
func request(request_serial: Variant, expected_generation: Variant,
        ability_state: Dictionary, world_clock: float,
        authority: bool = true, paused: bool = false) -> Dictionary:
    var gate: Dictionary = _gate(authority,paused)
    if not gate.ok: return gate
    if not State.integer(request_serial,1,Capture.Site.MAX_COUNTER) or not State.integer(expected_generation,0,Capture.Site.MAX_COUNTER): return _bad("request_sequence")
    _busy = true
    var result: Dictionary = _request(int(request_serial),int(expected_generation),ability_state,world_clock)
    _busy = false
    return result

func _request(serial: int, generation: int, ability: Dictionary, clock: float) -> Dictionary:
    var rules: RefCounted = _context.rules
    var state: Dictionary = rules.snapshot()
    if not rules.validate_snapshot(state).ok or int(state.jobs_completed) != 1: return _bad("first_service_unavailable")
    var previous: Dictionary = _repository.read()
    if not previous.ok: return _bad("repository:"+str(previous.code))
    # A retried press after success/loading is a no-op, even if the player has
    # since taken damage. No absolute old health is reapplied.
    if int(state.services_consumed) == 1:
        if int(state.service_serial) != serial: return _bad("awaiting_new_beneficiary")
        if previous.empty or not _same_result(previous.envelope.site,state) or int(previous.envelope.site.rules.services_consumed) != 1 or int(previous.envelope.site.rules.service_serial) != serial:
            return _uncertain("consumed_state_not_persisted")
        return {"ok":true,"code":"already_serviced","healed_hp":0.0,"duplicate":true,"generation":int(previous.generation),"service_serial":serial}
    if int(state.service_credit) != 1 or int(state.services_consumed) != 0: return _bad("first_service_unavailable")
    if int(previous.generation) != generation: return _bad("generation_changed")
    if not previous.empty:
        if not _same_result(previous.envelope.site,state): return _bad("saved_first_result_mismatch")
        if int(previous.envelope.site.rules.services_consumed) != 0 or int(previous.envelope.site.rules.service_serial) != int(state.service_serial): return _uncertain("saved_consumption_requires_reload")
    var player: Flight = _player.get_ref()
    if player.health >= player.maximum_health: return _bad("hull_already_full")
    var access: Dictionary = interaction()
    if not access.ok: return access
    var captured: Dictionary = _capture(ability,clock)
    if not captured.ok: return _bad("safe_checkpoint:"+str(captured.code))
    var source: Dictionary = captured.envelope
    if source.site.rules != state: return _bad("source_changed")
    var prepared: Dictionary = rules.prepare_service(int(state.revision),serial,true,false)
    if not prepared.ok: return _bad("prepare_service:"+str(prepared.code))
    var candidate: Dictionary = source.duplicate(true)
    var healed: float = minf(MAX_REPAIR_HP,float(source.player.flight.maximum_health)-float(source.player.flight.health))
    candidate.site.rules = prepared.candidate.duplicate(true)
    candidate.player.flight.health = float(source.player.flight.health)+healed
    candidate.player.flight.state.damage.health = candidate.player.flight.health
    var checked: Dictionary = Capture.validate(candidate)
    if not checked.ok: return _bad("repair_candidate:"+str(checked.code))
    # Existing Store ledger identifies the original physical first-work proof.
    # The request contains the full checkpoint, including consumption+health.
    var work_key: String = JSON.stringify(source.site.history.first_work,"",true,true).sha256_text()
    var transaction: String = "canal-player-service:"+work_key+":"+str(serial)
    var saved: Dictionary = _repository.save(candidate,transaction,generation)
    if not saved.ok:
        var reread: Dictionary = _repository.read()
        if not reread.ok or int(reread.generation) != generation: return _uncertain("save_outcome_requires_reload:"+str(saved.code))
        return _bad("save_failed:"+str(saved.code))
    # A duplicate receipt can legally point at a *later* Store generation.
    # It is never permission to apply a cached health value to the live world.
    if not _repository._store.matches_persisted_value(candidate,saved.envelope): return _uncertain("saved_candidate_readback_mismatch")
    if Engine.get_physics_frames() != int(source.physics.frame) or rules.snapshot() != state or State.capture(player,Capture.PLAYER_ID) != source.player.flight or player.collision_count != int(source.player.collision_count):
        return _uncertain("committed_live_state_changed")
    var adopted: Dictionary = rules.adopt_service(prepared,true,false)
    if not adopted.ok: return _uncertain("committed_rules_adoption:"+str(adopted.code))
    var waiting: Dictionary = _executor.wait_for_next_beneficiary(true)
    if not waiting.ok: return _uncertain("committed_waiting_state:"+str(waiting.code))
    # Flight's public damage restore is used with an identical damage schema;
    # only health differs. Armor, components, damage serial and all resources,
    # timers, velocities and collision history remain the same live values.
    player.restore_damage_state(candidate.player.flight.state.damage)
    if State.capture(player,Capture.PLAYER_ID) != candidate.player.flight: return _uncertain("committed_player_adoption")
    _observer.reset_observation()
    return {"ok":true,"code":"service_committed","healed_hp":healed,"duplicate":false,"generation":int(saved.generation),"service_serial":serial,"health":player.health,"waiting_for_beneficiary":true}

## The existing physical workbench power contact is the explicit service point.
## This query keeps every real collision/LOS blocker, including the work tools.
func interaction() -> Dictionary:
    if not _configured or not _bindings_live(): return _bad("binding_lost")
    var body: Flight = _player.get_ref()
    var bench: Node3D = _bench.get_ref()
    var target: StaticBody3D = bench.power_target
    if not _live(target) or target.get_world_3d() != body.get_world_3d(): return _bad("service_target_lost")
    var distance: float = body.global_position.distance_to(target.global_position)
    if distance > RANGE_M: return {"ok":false,"code":"service_out_of_range","distance_m":distance,"range_m":RANGE_M}
    var excluded: Array[RID] = [body.get_rid()]
    var query := PhysicsRayQueryParameters3D.create(body.global_position,target.global_position,Capture.QUERY_MASK,excluded)
    var hit: Dictionary = body.get_world_3d().direct_space_state.intersect_ray(query)
    if hit.get("collider") != target:
        var collider: Variant = hit.get("collider")
        return {"ok":false,"code":"service_obstructed","first_hit":str(collider.get_path()) if collider is Node else "none","distance_m":distance}
    return {"ok":true,"code":"service_point_visible","target_id":Bench.POWER_ID,"position":target.global_position,"distance_m":distance,"range_m":RANGE_M}

func report() -> Dictionary:
    return {"configured":_configured,"busy":_busy,"reload_required":_reload_required,"maximum_repair_hp":MAX_REPAIR_HP,"range_m":RANGE_M}

func _capture(ability: Dictionary, clock: float) -> Dictionary:
    return _observer.capture(_context,_executor,_bench.get_ref(),_cooling.get_ref(),_player.get_ref(),ability,clock,true,false)

func _same_result(site: Dictionary, current: Dictionary) -> bool:
    var history: Dictionary = _bench.get_ref().report().get("restored_history",{})
    if history.is_empty():
        # Live (never-restored) first work carries the same actual receipt.
        var work: Dictionary = _bench.get_ref().report().get("receipt",{})
        var action: Dictionary = {}
        for key: String in Executor.MATCH_KEYS: action[key] = work.get("receipt",{}).get(key)
        return _repository._store.matches_persisted_value(action,site.history.first_work.action) and int(site.history.first_work.frame) == int(work.get("physics_frame",-1)) and int(site.rules.jobs_completed) == int(current.jobs_completed)
    return _repository._store.matches_persisted_value(history.first_work,site.history.first_work) and int(site.rules.jobs_completed) == int(current.jobs_completed)

func _gate(authority: bool, paused: bool) -> Dictionary:
    if not authority: return _bad("authority_required")
    if paused: return _bad("paused")
    if not _configured or not _bindings_live(): return _bad("binding_lost")
    if _busy: return _bad("reentrant_service")
    if _reload_required: return _bad("reload_required")
    if not _executor._authority or not _bench.get_ref()._authority: return _bad("active_host_required")
    return {"ok":true,"code":"host_ready"}

func _bindings_live() -> bool:
    return _player != null and _bench != null and _cooling != null and _live(_player.get_ref()) and _live(_bench.get_ref()) and _live(_cooling.get_ref()) and is_instance_valid(_executor) and not _executor.report().closed and _context.get("rules") == _executor._rules and _context.get("custody") == _executor._custody

func _uncertain(code: String) -> Dictionary:
    _reload_required = true
    return {"ok":false,"code":code,"reload_required":true,"healed_hp":0.0}

static func _live(node: Variant) -> bool:
    return node is Node3D and is_instance_valid(node) and node.is_inside_tree() and not node.is_queued_for_deletion()

static func _bad(code: String) -> Dictionary:
    return {"ok":false,"code":code,"healed_hp":0.0}
