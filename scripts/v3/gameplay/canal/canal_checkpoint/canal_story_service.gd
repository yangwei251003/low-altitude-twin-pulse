extends RefCounted
## Original MAIN Store bridge: prepare only, then adopt AFTER Root's atomic
## Story transaction. No Repository, Story mutation, reward or player healing.
const Progress=preload("res://scripts/v3/gameplay/canal/canal_checkpoint/canal_progress_checkpoint.gd")
const State=Progress.State
const Rules=Progress.Rules
const RANGE_M=4.0
var _adapter: WeakRef
var _observer=Progress.Wait.Safe.new()
var _observation: Dictionary={"ok":false,"code":"not_observed"}
var _prepared: Dictionary={}
var _reload_required: bool=false

func setup(adapter: RefCounted) -> void:
    _adapter=weakref(adapter)

func reset() -> void:
    invalidate_observation()
    _reload_required=false

func invalidate_observation() -> void:
    _observer.reset_observation()
    _observation={"ok":false,"code":"not_observed"}
    _prepared.clear()

func observe() -> void:
    var adapter: RefCounted=_adapter.get_ref() if _adapter!=null else null
    if adapter==null or not adapter._binding_issue().is_empty() or adapter._paused or adapter.session.simulation_paused or _reload_required:
        _observer.reset_observation()
        _observation={"ok":false,"code":"site_not_available"}
        return
    var ctx: Dictionary=adapter.context()
    var rules: Variant=ctx.get("rules")
    var bench: Variant=ctx.get("workbench")
    var executor: Variant=ctx.get("executor")
    var cooling: Variant=ctx.get("cooling")
    if rules==null or ctx.get("custody")==null or not is_instance_valid(bench) or not is_instance_valid(executor) or not is_instance_valid(cooling) or not bench._committed or bench._phase!="departed" or executor._phase!="idle" or int(rules.snapshot().service_credit)!=1:
        _observer.reset_observation()
        _observation={"ok":false,"code":"completed_safe_site_pending"}
        return
    _observation=_observer.capture(ctx,executor,bench,cooling,true,false)

func status() -> Dictionary:
    var adapter: RefCounted=_adapter.get_ref() if _adapter!=null else null
    var ctx: Dictionary=adapter.context() if adapter!=null else {}
    var rules: Variant=ctx.get("rules")
    var claimed: bool=rules!=null and int(rules.snapshot().services_consumed)==1
    return {"ready_credit":bool(_observation.get("ok",false)) and int(_observation.get("envelope",{}).get("physics",{}).get("frame",-1))==Engine.get_physics_frames(),"claimed":claimed,"code":_observation.get("code","not_observed"),"reload_required":_reload_required}

func prepare(peer_id: int) -> Dictionary:
    _prepared.clear()
    var access: Dictionary=_access(peer_id)
    if not access.ok: return access
    var adapter: RefCounted=_adapter.get_ref()
    var ctx: Dictionary=adapter.context()
    var rules: Dictionary=ctx.rules.snapshot()
    var saved: Dictionary=adapter.session.store.snapshot()
    if int(rules.services_consumed)==1:
        var disk: Dictionary=saved.world.get("environment",{}).get("I2_canal",{})
        var persisted: Dictionary=disk.get("rules",{})
        if int(persisted.get("services_consumed",0))!=1 or int(persisted.get("service_serial",-1))!=int(rules.service_serial) or int(persisted.get("jobs_completed",0))!=1 or not ctx.executor._waiting_for_beneficiary: return _bad("claimed_state_requires_reload")
        var duplicate: Dictionary=adapter.capture_persistent_state()
        if not duplicate.ok: return _bad("claimed_capture:"+str(duplicate.code))
        _prepared={"ok":true,"code":"already_claimed","duplicate":true,"peer_id":peer_id,"envelope":duplicate.envelope,"prepared_rules":{},"service_serial":int(rules.service_serial),"healed_hp":0.0}
        return _prepared.duplicate(true)
    if int(rules.jobs_completed)!=1 or int(rules.service_credit)!=1 or not rules.pending_action.is_empty(): return _bad("original_service_credit_required")
    # Pure repeated same-frame capture does not accrue observer time. Every
    # preceding interval was observed only after the ordinary authority tick.
    observe()
    if not _observation.ok: return _bad("service_safe:"+str(_observation.code))
    var capture: Dictionary=adapter.capture_persistent_state()
    if not capture.ok or capture.envelope.kind!=Progress.KIND: return _bad("service_progress_capture_required")
    var prepared_rules: Dictionary=ctx.rules.prepare_service(int(rules.revision),int(rules.service_serial)+1,true,false)
    if not prepared_rules.ok: return _bad("prepare_service:"+str(prepared_rules.code))
    var envelope: Dictionary=capture.envelope.duplicate(true)
    envelope.rules=prepared_rules.candidate.duplicate(true)
    envelope.executor.fields._waiting_for_beneficiary=true
    envelope.executor.fields._code="awaiting_new_beneficiary"
    var valid: Dictionary=Progress.validate(envelope)
    if not valid.ok: return _bad("prepared_claim:"+str(valid.code))
    _prepared={"ok":true,"code":"prepared_not_committed","duplicate":false,"peer_id":peer_id,"actor_id":adapter.session._actor_id(peer_id),"actor_revision":access.actor_revision,"player_position":State.xyz(access.body.global_position),"player_health":access.body.health,"physics_frame":Engine.get_physics_frames(),"expected_generation":int(saved.generation),"lineage_id":saved.lineage_id,"branch_id":saved.world.branch_id,"envelope":envelope,"prepared_rules":prepared_rules,"source_rules":rules,"service_serial":int(prepared_rules.candidate.service_serial)}
    return _prepared.duplicate(true)

func adopt(prepared: Dictionary) -> Dictionary:
    if _prepared.is_empty() or not Progress.Parts.same(prepared,_prepared): return _bad("unprepared_story_service")
    var access: Dictionary=_access(int(prepared.peer_id))
    if not access.ok: return _uncertain(str(access.code)) if not prepared.duplicate else access
    var adapter: RefCounted=_adapter.get_ref()
    var ctx: Dictionary=adapter.context()
    if prepared.duplicate:
        _prepared.clear()
        return {"ok":true,"code":"already_claimed","duplicate":true,"service_serial":prepared.service_serial,"healed_hp":0.0}
    var saved: Dictionary=adapter.session.store.snapshot()
    var persisted: Dictionary=saved.world.get("environment",{}).get("I2_canal",{})
    if int(saved.generation)<=int(prepared.expected_generation) or saved.lineage_id!=prepared.lineage_id or saved.world.branch_id!=prepared.branch_id or not adapter.session.store.matches_persisted_value(prepared.envelope,persisted): return _bad("story_service_not_committed_in_original_store")
    if Engine.get_physics_frames()!=int(prepared.physics_frame) or access.actor_revision!=int(prepared.actor_revision) or State.xyz(access.body.global_position)!=prepared.player_position or access.body.health!=prepared.player_health or not Rules._same(ctx.rules.snapshot(),prepared.source_rules): return _uncertain("committed_live_state_changed")
    var adopted: Dictionary=ctx.rules.adopt_service(prepared.prepared_rules,true,false)
    if not adopted.ok: return _uncertain("rules_adoption:"+str(adopted.code))
    var waiting: Dictionary=ctx.executor.wait_for_next_beneficiary(true)
    if not waiting.ok: return _uncertain("beneficiary_wait:"+str(waiting.code))
    _prepared.clear()
    _observer.reset_observation()
    _observation={"ok":false,"code":"claimed"}
    return {"ok":true,"code":"adopted_original_story_service","duplicate":false,"service_serial":prepared.service_serial,"waiting_for_beneficiary":true}

func exchange_fact() -> String:
    var adapter: RefCounted=_adapter.get_ref() if _adapter!=null else null
    if adapter==null or not adapter._binding_issue().is_empty() or adapter._paused or adapter.session.simulation_paused or _reload_required: return ""
    var ctx: Dictionary=adapter.context()
    if ctx.get("rules")==null or ctx.get("custody")==null or not is_instance_valid(ctx.get("executor")) or ctx.executor._phase=="fault": return ""
    var rules: Dictionary=ctx.rules.snapshot()
    if not ctx.rules.validate_snapshot(rules).ok: return ""
    if _local_cooling_prepared(ctx,rules): return "local_cooling"
    if not ctx.executor._configured or int(ctx.executor._receipt_count)<10 or int(rules.action_serial)<11: return ""
    var actual: Dictionary=ctx.custody.report().cargos
    var occupied: Array=[]
    for id: String in Rules.CASSETTES:
        var holder: String=str(rules.cassettes[id].holder)
        if holder not in Rules.BERTHS or holder in occupied or actual[id].phase!="docked" or actual[id].berth!=holder or int(actual[id].stable_usec)!=Progress.Wait.Custody.STABLE_USEC or not ctx.custody.support_info(id,holder).get("supported",false): return ""
        occupied.append(holder)
    if not ctx.carrier.cargo_items.is_empty(): return ""
    # The first 10 original receipts precede work serial11. Trace-backed routes
    # can be classified without guessing from policy or UI distance.
    var routes: Dictionary={}
    var serials: Dictionary={}
    for row: Dictionary in ctx.executor._receipts:
        var receipt: Dictionary=row.receipt
        if int(receipt.serial)>10: continue
        if not receipt.get("completed",false) or not receipt.get("custody_verified",false) or not receipt.get("path_clear",false) or not receipt.get("endpoint_valid",false) or receipt.route not in ["low","high"]: return ""
        serials[int(receipt.serial)]=true
        routes[str(receipt.route)]=true
    if serials.size()==10: return "mixed_route" if routes.size()==2 else ("high_route" if routes.has("high") else "low_route")
    # Legacy normal progress/SCAN stores retain receipt_count, not raw runtime
    # reports. Their sealed Executor only accepts LOW and validators disallow
    # buffer/manual holders. This branch cannot advertise unsupported high play.
    if rules.buffer_enabled or rules.policy!="staggered": return ""
    for pilot: Dictionary in rules.pilots.values():
        if pilot.enabled or int(pilot.peer_id)!=0: return ""
    if int(rules.jobs_completed)==0:
        if rules.pending_action.get("kind")!="work" or int(rules.pending_action.get("serial",0))!=11 or rules.cassettes[Rules.CASSETTES[0]].holder!=Rules.WORK: return ""
    elif int(rules.jobs_completed)==1:
        if not is_instance_valid(ctx.get("workbench")): return ""
        var history: Dictionary=ctx.workbench.report().restored_history
        if history.is_empty(): history=Progress.Wait.Bench.ProgressState._history(ctx.workbench)
        if history.is_empty() or int(history.first_work.action.serial)!=11: return ""
    else: return ""
    return "low_route"

## Separate proof of preparing the original hot WORK cassette locally. It
## NEVER certifies two-cassette transport or fabricates ten route receipts.
## The original first-work receipt is durable evidence of past preparation;
## subsequent heating/departure does not rewrite it as a current temperature.
func _local_cooling_prepared(ctx: Dictionary, rules: Dictionary) -> bool:
    if ctx.get("custody")==null or not is_instance_valid(ctx.get("executor")): return false
    if rules.buffer_enabled or rules.policy!="staggered" or int(rules.command_serial)<1: return false
    for pilot: Dictionary in rules.pilots.values():
        if pilot.enabled or int(pilot.peer_id)!=0: return false
    if ctx.custody._last_physics_frame!=Engine.get_physics_frames(): return false
    var id: String=Rules.CASSETTES[1]
    var holder: String=str(rules.cassettes[id].holder)
    if not _original_supported_cassette(ctx,rules,id,holder): return false
    var removed: int=int(rules.thermal_ledger.ability_removed)
    var threshold: int=(Rules.COLD_MC-Rules.AMBIENT_MC)*Rules.POD_CAPACITY
    if int(rules.jobs_completed)==0:
        # The initial closed chain has not moved either cassette. Current cold
        # WORK support plus the native thermal balance proves local preparation
        # even before takeover/Brief; command_serial alone is insufficient.
        if holder!=Rules.WORK or int(ctx.executor._receipt_count)!=0 or int(rules.action_serial)>1 or int(rules.thermal_ledger.work_added)!=0 or rules.cassettes[Rules.CASSETTES[0]].holder!=Rules.CARRIER: return false
        var energy: int=int(rules.cassettes[id].energy_mj)
        if energy>threshold or removed<Rules.INITIAL_HEAT_MJ-energy: return false
        var action: Dictionary=rules.pending_action
        return action.is_empty() or (action.kind=="work" and int(action.serial)==1 and action.cassette_id==id and action.source==Rules.WORK and action.destination==Rules.WORK and action.route=="stationary" and int(action.job)==1)
    if int(rules.jobs_completed)!=1 or int(rules.thermal_ledger.work_added)!=Rules.WORK_HEAT_MJ or removed<Rules.INITIAL_HEAT_MJ-threshold or not is_instance_valid(ctx.get("workbench")) or not ctx.workbench._committed or ctx.workbench._receipt_count!=1: return false
    var history: Dictionary=Progress.Wait.Bench.ProgressState._history(ctx.workbench)
    if history.is_empty() or not Progress.Wait.Bench.History.validate(history,rules,Progress.Wait.Bench.POINT_A,Progress.Wait.Bench.POINT_B,Progress.Wait.Bench.TOOL_SIZE,Progress.Wait.Bench.Departure.ROUTE[-1]).ok: return false
    var work: Dictionary=history.first_work.action
    return int(work.serial)==1 and int(work.job)==1 and work.cassette_id==id and work.source==Rules.WORK and work.destination==Rules.WORK

func _original_supported_cassette(ctx: Dictionary, rules: Dictionary, id: String, holder: String) -> bool:
    if holder not in Rules.BERTHS or not ctx.custody._integrity(id).is_empty(): return false
    var row: Dictionary=ctx.custody.report().cargos.get(id,{})
    if row.get("phase")!="docked" or row.get("berth")!=holder or int(row.get("stable_usec",0))!=Progress.Wait.Custody.STABLE_USEC: return false
    for other: String in Rules.CASSETTES:
        if other!=id and rules.cassettes[other].holder==holder: return false
    var proof: Dictionary=ctx.custody.support_info(id,holder)
    return proof.get("supported",false) and proof.get("cargo_rid")==ctx.cargos[id].get_rid() and proof.get("support_rid")==ctx.berths[holder].get_rid()

func _access(peer_id: int) -> Dictionary:
    var adapter: RefCounted=_adapter.get_ref() if _adapter!=null else null
    if adapter==null or not adapter._binding_issue().is_empty() or adapter._busy or adapter._paused or adapter.session.simulation_paused or not adapter.session.owns_world or _reload_required: return _bad("story_service_host_unavailable")
    var session=adapter.session
    if not session.players.has(peer_id): return _bad("service_actor_missing")
    var body: Variant=session.players[peer_id]
    var actor: String=session._actor_id(peer_id)
    var row: Dictionary=session.entities.get(actor,{})
    if not body is State.Flight or not is_instance_valid(body) or not body.is_inside_tree() or body.get_world_3d().space!=adapter._world.get_world_3d().space or not body.enabled or body.freeze or body.water_contact or row.get("owner")!=str(peer_id) or row.get("downed",false) or not State.integer(row.get("revision"),0,9007199254740991): return _bad("service_actor_invalid_or_foreign")
    var ctx: Dictionary=adapter.context()
    if ctx.get("rules")==null or ctx.get("custody")==null or not is_instance_valid(ctx.get("workbench")) or not is_instance_valid(ctx.get("executor")) or not is_instance_valid(ctx.get("cooling")): return _bad("service_workbench_unavailable")
    var target: StaticBody3D=ctx.workbench.power_target
    if body.global_position.distance_to(target.global_position)>RANGE_M: return _bad("service_out_of_range")
    if not session._line_clear(body.global_position,target.global_position,body.get_rid(),Progress.Wait.Bench.POWER_ID): return _bad("service_actual_los_blocked")
    return {"ok":true,"body":body,"actor_revision":int(row.revision)}

func _uncertain(code: String) -> Dictionary:
    var adapter: RefCounted=_adapter.get_ref()
    # Persisted claim cannot be rolled back. Stop owned physics before another
    # ordinary tick could reserve work; Root must reload the committed envelope.
    _reload_required=true
    var held: Dictionary=adapter.hold_for_committed_reload(code) if adapter!=null else {"ok":false,"code":"adapter_missing"}
    var result: Dictionary=_bad("committed_claim_reload_required:"+code)
    result["physical_hold"]=held
    return result

func _bad(code: String) -> Dictionary:
    return {"ok":false,"code":code}
