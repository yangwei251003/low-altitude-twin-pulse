extends SceneTree
## Existing actual completed-site fixtures, not another transport/work replay.
## The caller creates production I2 worlds; only new candidate bodies restore.
const World = preload("res://scripts/v3/twin_test_world.gd")
const Assembly = preload("res://scripts/v3/candidates/canal_assembly/canal_assembly.gd")
const PlayerCheckpoint = preload("res://scripts/v3/candidates/canal_checkpoint/player_checkpoint.gd")
const State = Assembly.Checkpoint.FlightState
const Rules = Assembly.Runtime
const DT := 1.0/60.0
const FIRST := "res://tests_v3/candidates/canal_player_service/evidence/first_player_checkpoint_actual.json"
const FIRST_SHA := "90fa185b241fe2a8ce84c40bb2ad1ad047cbd53f62eb7f0ba70b4d6c3721e093"
const SPENT := "res://docs/v3/evidence/canal-player-service/04-ui-player-label-54-0/capture/after_service_saved.json"
const SPENT_SHA := "1831a0813a29f8ffd0dd1d6ddf430d2be755a14cf6e92aaee701ad16a8bd2395"
var views: Array[SubViewport] = []
var hosts: Array[Dictionary] = []
var checks := 0
var failures: Array = []
var evidence: Dictionary = {}
var output := ""
var finished := false
class ErrorLog extends Logger:
    var errors: Array = []
    func _log_error(fn: String,file: String,line: int,code: String,reason: String,_notify: bool,kind: int,_traces: Array[ScriptBacktrace]) -> void:
        errors.append({"function":fn,"file":file,"line":line,"code":code,"reason":reason,"kind":kind})
var logger := ErrorLog.new()

func _initialize() -> void:
    OS.add_logger(logger)
    for argument: String in OS.get_cmdline_user_args():
        if argument.begins_with("--output="): output=argument.trim_prefix("--output=")
    _run.call_deferred()

func _run() -> void:
    create_timer(50).timeout.connect(func():
        if not finished:
            _check(false,"50s restore-only internal bound")
            _finish())
    for script: Script in [Assembly,World,PlayerCheckpoint]:
        if not _check(script.can_instantiate(),"actual restore dependency parses",script.resource_path): _finish(); return
    if not _check(Engine.physics_ticks_per_second==60 and Engine.time_scale==1 and FileAccess.get_sha256(FIRST)==FIRST_SHA and FileAccess.get_sha256(SPENT)==SPENT_SHA,"actual source fixtures and ordinary physics rate"): _finish(); return
    var first: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(FIRST))
    var spent: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(SPENT))
    if not _check(PlayerCheckpoint.validate(first).ok and PlayerCheckpoint.validate(spent).ok,"unchanged full player envelopes validate before taking site subtree"): _finish(); return
    evidence.fixtures={"first":{"path":FIRST,"sha256":FIRST_SHA,"source":"artifacts/v3/art/canal-player-checkpoint-20261020_050633_87e6e4/first_saved.json","source_checks":57},"consumed":{"path":SPENT,"sha256":SPENT_SHA,"source":"artifacts/v3/art/canal-player-service-label-20261020_055635_656dba/after_service_saved.json","source_checks":54},"scope":"pure restoration of actual prior completed work and G-service saves; no new work, player body or Store is created by this test"}
    var first_host: Dictionary=await _new_world(float(first.world_clock))
    if first_host.is_empty(): _finish(); return
    var target: Node3D=_empty_owner(first_host.world,"RestoredAssembly")
    first_host.assembly=target
    var invalid: Dictionary=first.site.duplicate(true)
    invalid.version=2
    var bad: Dictionary=target.prepare_saved(first_host.world,first_host.world.sample_environment,invalid,first.ability.station_serial,true)
    _check(not bad.ok and target.get_child_count()==0 and not target.status().configured,"bad envelope rejects before allocating candidate",bad)
    var denied: Dictionary=target.prepare_saved(first_host.world,first_host.world.sample_environment,first.site,first.ability.station_serial,false)
    _check(not denied.ok and target.get_child_count()==0,"non-host prepare creates no site",denied)
    var replay: Dictionary=target.prepare_saved(first_host.world,first_host.world.sample_environment,first.site,0,true)
    _check(not replay.ok and replay.code=="device_serial_would_replay" and target.get_child_count()==0,"saved device anti-replay serial cannot reset to zero",replay)
    var made: Dictionary=target.prepare_saved(first_host.world,first_host.world.sample_environment,first.site,first.ability.station_serial,true)
    if not _check(made.ok and made.restore_pending and not made.ready,"prepare starts original physical reconstruction, not readiness",made): _finish(); return
    _check(target.context().is_empty() and target.target_definitions().is_empty() and not target.apply_authorized_ability(Assembly.RELAY_ID,"charge").ok,"unadopted modules/targets/abilities stay unavailable")
    _check(target.bootstrap.phase=="unconfigured" and target.find_children("CanalTransportCandidateSite","Node3D",true,false).is_empty() and target.find_children("CanalRestoredCandidateSite","Node3D",true,false).size()==1,"saved path never creates a second fresh Bootstrap/site")
    _check(not target.adopt_saved(true).ok,"prepare alone cannot adopt without current support")
    var pending_tree: Dictionary=_owned_rows(target)
    var unauthorized: Dictionary=target.advance(DT,false)
    _check(not unauthorized.ok and _owned_rows(target)==pending_tree,"non-host preparation tick touches no body commands or state",unauthorized)
    _check(target.set_paused(true,true).ok,"preparation can pause through original restorer")
    for i in 12:
        if not await _frame(): _finish(); return
    _check(not target.status().restore_ready and target.status().rule_usec==0 and target.context().is_empty(),"paused preparation accrues no ready credit or thermal clock")
    _check(target.set_paused(false,true).ok,"resume requires real support reacquisition")
    if not await _await_ready(first_host): _finish(); return
    _check(not target.adopt_saved(false).ok and target.context().is_empty() and target.status().restore_ready,"non-host adopt cannot transfer a ready candidate")
    var ready_frame: int=Engine.get_physics_frames()
    # Intentionally skip only this candidate's next host tick. Stale ready must
    # never be adopted; the next valid tick must recapture support afresh.
    if not await _frame(target): _finish(); return
    var stale: Dictionary=target.adopt_saved(true)
    _check(not stale.ok and stale.code=="restore_adopt:current_ready_required" and Engine.get_physics_frames()>ready_frame,"a later frame cannot adopt stale preparation evidence",stale)
    if not await _await_ready(first_host): _finish(); return
    var adopted: Dictionary=target.adopt_saved(true)
    if not _check(adopted.ok and adopted.ready and not adopted.restore_pending,"original same-frame recheck adopts the actual candidate",adopted): _finish(); return
    first_host.adopted=true
    var ctx: Dictionary=target.context()
    evidence.unconsumed_adoption=_proof(first_host)
    _check(_equal(ctx.rules.snapshot(),first.site.rules) and _equal(ctx.custody.docked_snapshot(),first.site.checkpoint.custody),"original rules and custody replay counters survive adoption")
    _check(_equal(ctx.workbench.report().restored_history,first.site.history) and ctx.executor.report().receipt_count==0 and ctx.workbench.report().receipt.is_empty(),"historical result retained without new transport/work receipt")
    _check(target.status().device_serial==int(first.ability.station_serial) and int(ctx.rules.status().elapsed_usec)==int(target.status().rule_usec),"saved device sequence and kernel clock are preserved")
    _check(target.is_ancestor_of(ctx.workbench) and ctx.workbench.get_parent()!=target and ctx.carrier.get_world_3d().space==first_host.world.get_world_3d().space and target.target_definitions().size()==6,"nested restored site uses caller space and actual six targets")
    _check(ctx.rules.snapshot().service_credit==1 and ctx.rules.snapshot().services_consumed==0 and not target.discard_saved(true).ok,"unspent credit remains single and adopted site cannot be discarded as pending")
    if not await _continue(first_host,300): _finish(); return
    # Duplicate/current-world prepare rejects before changing the established
    # old site. Another World3D is the host's staging boundary, not this module's.
    var old_before: Dictionary=_proof(first_host)
    var duplicate: Node3D=_empty_owner(first_host.world,"RejectedDuplicate")
    var occupied: Dictionary=duplicate.prepare_saved(first_host.world,first_host.world.sample_environment,first.site,first.ability.station_serial,true)
    _check(not occupied.ok and occupied.code=="site_already_present" and duplicate.get_child_count()==0 and _proof(first_host)==old_before,"failed same-world replacement keeps old station/ledger/poses intact",occupied)
    duplicate.free()

    var next_host: Dictionary=await _new_world(float(spent.world_clock))
    if next_host.is_empty(): _finish(); return
    var faulty: Node3D=_empty_owner(next_host.world,"BlockedCandidate")
    next_host.assembly=faulty
    var blocked_start: Dictionary=faulty.prepare_saved(next_host.world,next_host.world.sample_environment,spent.site,spent.ability.station_serial,true)
    if not _check(blocked_start.ok,"negative candidate initially passes saved schema and berth preflight",blocked_start): _finish(); return
    # Explicit new QA obstruction at the future restored beneficiary, before it
    # is created. No actor is moved or made immune to create this failure.
    var blocker:=StaticBody3D.new()
    blocker.name="QA_RestoreTerminalObstruction"
    blocker.collision_layer=1
    var shape:=CollisionShape3D.new()
    var box:=BoxShape3D.new()
    box.size=Vector3(.4,.4,.4)
    shape.shape=box
    blocker.add_child(shape)
    next_host.world.add_child(blocker)
    blocker.global_position=State.transform(spent.site.checkpoint.beneficiary.pose).origin
    var failure: Dictionary={}
    for i in 180:
        if not await _frame(faulty): _finish(); return
        var step: Dictionary=faulty.advance(DT,true,false)
        if not step.ok:
            failure=step
            break
    evidence.obstruction=failure.duplicate(true)
    _check(not failure.is_empty() and str(failure.code).contains("beneficiary_initial_obstructed") and faulty.get_child_count()==0,"actual new obstruction rejects restore and destroys only new candidate",failure)
    _check(is_instance_valid(blocker) and not first_host.assembly.status().closed and first_host.assembly.context().rules.snapshot().service_credit==1,"failed staging leaves blocker and original live station intact")
    next_host.assembly=null
    faulty.free()
    blocker.free()
    for i in 2:
        if not await _frame(): _finish(); return
    var canceled: Node3D=_empty_owner(next_host.world,"CanceledCandidate")
    var cancel_start: Dictionary=canceled.prepare_saved(next_host.world,next_host.world.sample_environment,spent.site,spent.ability.station_serial,true)
    _check(cancel_start.ok and not canceled.discard_saved(false).ok and canceled.discard_saved(true).ok and canceled.get_child_count()==0,"host cancellation frees only an unadopted candidate")
    canceled.free()
    var restored: Node3D=_empty_owner(next_host.world,"ConsumedAssembly")
    next_host.assembly=restored
    var restore_start: Dictionary=restored.prepare_saved(next_host.world,next_host.world.sample_environment,spent.site,spent.ability.station_serial,true)
    if not _check(restore_start.ok,"actual consumed-service envelope begins a clean candidate",restore_start): _finish(); return
    if not await _await_ready(next_host): _finish(); return
    var resumed: Dictionary=restored.adopt_saved(true)
    if not _check(resumed.ok,"consumed historical work adopts without issuing work/service",resumed): _finish(); return
    next_host.adopted=true
    var used: Dictionary=restored.context()
    _check(_equal(used.rules.snapshot(),spent.site.rules) and _equal(used.workbench.report().restored_history,spent.site.history) and used.executor.report().waiting_for_beneficiary,"spent credit and original wait-for-next-beneficiary gate survive",used.executor.report())
    if not await _continue(next_host,300): _finish(); return
    var stable: Dictionary=used.rules.snapshot()
    _check(stable.service_credit==0 and stable.services_consumed==1 and stable.service_serial==spent.site.rules.service_serial and stable.pending_action.is_empty() and used.executor.report().waiting_for_beneficiary,"five live seconds cannot recreate consumed service or a second beneficiary",_proof(next_host))
    var first_clock: int=int(used.rules.status().elapsed_usec)
    var serial: int=int(restored.status().device_serial)
    var declined: Dictionary=used.cooling.apply_charge(35.0,int(spent.site.checkpoint.cooling.charge_serial),true)
    _check(not declined.ok and used.cooling.snapshot().charge_serial==spent.site.checkpoint.cooling.charge_serial,"old saved device command still rejects")
    var accepted: Dictionary=restored.apply_authorized_ability(Assembly.RELAY_ID,"charge","",[],true)
    _check(accepted.ok and restored.status().device_serial==serial+1 and used.cooling.snapshot().charge_serial==serial+1 and used.rules.snapshot()==stable,"next trusted host input continues saved serial without changing reward ledger",accepted)
    var paused_before: Dictionary=used.rules.snapshot()
    _check(restored.set_paused(true,true).ok,"adopted original controllers can pause")
    for i in 12:
        if not await _frame(): _finish(); return
    _check(used.rules.snapshot()==paused_before and int(used.rules.status().elapsed_usec)==first_clock,"pause does not accrue water/thermal time")
    restored.set_paused(false,true)
    if not await _frame(): _finish(); return
    _check(int(used.rules.status().elapsed_usec)-first_clock in [16666,16667],"resume advances one real frame without pause catch-up")
    evidence.consumed_final=_proof(next_host)
    for host: Dictionary in hosts:
        _check(_facilities(host.world)==host.facilities,"restoration left original production facilities and collision shapes unchanged")
    _finish()

func _new_world(saved_clock: float) -> Dictionary:
    var viewport:=SubViewport.new()
    viewport.world_3d=World3D.new()
    viewport.render_target_update_mode=SubViewport.UPDATE_DISABLED
    root.add_child(viewport)
    views.append(viewport)
    var world:=World.new()
    viewport.add_child(world)
    world.build("I2",{},true)
    if not _check(world.build_errors.is_empty(),"caller-built actual production I2",world.build_errors): return {}
    world.clock_seconds=saved_clock # Explicit caller-owned initialization, not Assembly mutation.
    var host: Dictionary={"world":world,"assembly":null,"adopted":false,"facilities":{}}
    hosts.append(host)
    for i in 3:
        if not await _frame(): return {}
    host.facilities=_facilities(world)
    return host

func _empty_owner(world: Node3D,label: String) -> Node3D:
    var result:=Assembly.new()
    result.name=label
    world.add_child(result)
    return result

func _await_ready(host: Dictionary) -> bool:
    for i in 900:
        if not await _frame(): return false
        if host.assembly.status().restore_ready: return true
    return _check(false,"bounded real support and anchor reacquisition",host.assembly.status(true))

func _frame(skip: Node3D=null) -> bool:
    await physics_frame
    if finished: return false
    for host: Dictionary in hosts:
        host.world.clock_seconds+=DT
        var owner: Variant=host.assembly
        if owner==null or not is_instance_valid(owner) or owner==skip: continue
        var row: Dictionary=owner.advance(DT,true,false)
        if not row.ok:
            return _check(false,"normal parallel host remains valid",{"result":row,"status":owner.status(true)})
    if not logger.errors.is_empty(): return _check(false,"no runtime errors during real restoration",logger.errors)
    return true

func _continue(host: Dictionary,count: int) -> bool:
    var owner: Node3D=host.assembly
    var ctx: Dictionary=owner.context()
    var before: Dictionary=_proof(host)
    var initial_clock: int=int(ctx.rules.status().elapsed_usec)
    var maximum_anchor_error:=0.0
    for i in count:
        if not await _frame(): return false
        maximum_anchor_error=maxf(maximum_anchor_error,ctx.carrier.global_position.distance_to(Assembly.Checkpoint._anchor(str(ctx.rules.snapshot().carrier_anchor))))
    var after: Dictionary=_proof(host)
    var original: Dictionary=before.rules
    var state: Dictionary=after.rules
    _check(after.ids==before.ids and ctx.carrier.cargo_items.is_empty() and not is_instance_valid(ctx.carrier.cargo_joint),"same real modules and unloaded actors continue without fresh Bootstrap")
    _check(state.jobs_completed==original.jobs_completed and state.service_credit==original.service_credit and state.services_consumed==original.services_consumed and state.service_serial==original.service_serial and state.action_serial==original.action_serial and state.pending_action.is_empty() and state.thermal_ledger.work_added==25000000 and after.history==before.history and ctx.executor.report().receipt_count==0 and ctx.workbench.report().receipt.is_empty(),"continued host preserves historical work credit and receipts")
    _check(int(ctx.rules.status().elapsed_usec)-initial_clock==roundi(float(count)*1000000/60) and maximum_anchor_error<.18,"restored elapsed time advances exactly once and swept carrier holds actual anchor",{"before_usec":initial_clock,"after_usec":ctx.rules.status().elapsed_usec,"max_anchor_error":maximum_anchor_error})
    var support_ok:=true
    for id: String in Rules.CASSETTES:
        var holder: String=str(state.cassettes[id].holder)
        support_ok=support_ok and bool(ctx.custody.support_info(id,holder).supported) and int(ctx.custody.report().cargos[id].stable_usec)==350000
    _check(support_ok and ctx.carrier.collision_count==0 and ctx.workbench.beneficiary.collision_count==0 and not ctx.carrier.water_contact,"actual support/empty-attachment/collision gates remain valid")
    _check(ctx.carrier.health==before.carrier.health and ctx.carrier.battery<=float(before.carrier.state.battery) and ctx.workbench.beneficiary.health==before.beneficiary.health,"restored flight does not heal or refill resources")
    evidence["continue_"+str(state.services_consumed)]={"before":before,"after":after,"max_anchor_error":maximum_anchor_error,"ticks":count}
    return true

func _proof(host: Dictionary) -> Dictionary:
    var ctx: Dictionary=host.assembly.context()
    var ids: Array=[ctx.rules.get_instance_id(),ctx.custody.get_instance_id(),ctx.executor.get_instance_id(),ctx.cooling.get_instance_id(),ctx.workbench.get_instance_id(),ctx.carrier.get_instance_id(),ctx.workbench.beneficiary.get_instance_id()]
    var cargo_rows: Dictionary={}
    for id: String in Rules.CASSETTES:
        ids.append(ctx.cargos[id].get_instance_id())
        cargo_rows[id]={"pose":ctx.cargos[id].global_transform,"velocity":ctx.cargos[id].linear_velocity}
    return {"ids":ids,"rules":ctx.rules.snapshot(),"custody":ctx.custody.docked_snapshot(),"history":ctx.workbench.report().restored_history,"carrier":State.capture(ctx.carrier,Rules.CARRIER),"beneficiary":State.capture(ctx.workbench.beneficiary,Assembly.Checkpoint.BENEFICIARY_ID),"cargos":cargo_rows,"cooling":ctx.cooling.snapshot(),"serial":host.assembly.status().device_serial}

func _owned_rows(owner: Node3D) -> Dictionary:
    var result: Dictionary={}
    for body: Node in owner.find_children("*","RigidBody3D",true,false):
        result[body.get_instance_id()]={"pose":body.global_transform,"linear":body.linear_velocity,"angular":body.angular_velocity,"command":body.get("command")}
    return result

func _facilities(world: Node3D) -> Dictionary:
    var rows: Dictionary={}
    for body: Node in world.find_children("*","CollisionObject3D",true,false):
        var ancestor: Node=body.get_parent()
        var owned:=false
        while ancestor!=null and ancestor!=world:
            if ancestor.get_script()==Assembly: owned=true; break
            ancestor=ancestor.get_parent()
        if owned or not body is StaticBody3D and not body is AnimatableBody3D: continue
        var shapes: Array=[]
        for id: int in body.get_shape_owners():
            for i in body.shape_owner_get_shape_count(id): shapes.append(body.shape_owner_get_shape(id,i).get_rid())
        rows[body.get_instance_id()]=[body.get_rid(),body.global_transform,body.collision_layer,body.collision_mask,shapes]
    return rows

func _equal(a: Variant,b: Variant) -> bool:
    if a is Dictionary and b is Dictionary:
        if a.size()!=b.size(): return false
        for key: Variant in a:
            if not b.has(key) or not _equal(a[key],b[key]): return false
        return true
    if a is Array and b is Array:
        if a.size()!=b.size(): return false
        for i in a.size():
            if not _equal(a[i],b[i]): return false
        return true
    if (a is int or a is float) and (b is int or b is float): return is_finite(float(a)) and is_finite(float(b)) and absf(float(a)-float(b))<=1e-9
    return a==b

func _check(ok: bool,label: String,detail: Variant=null) -> bool:
    checks+=1
    if not ok: failures.append({"label":label,"details":detail})
    return ok

func _finish() -> void:
    if finished: return
    finished=true
    for viewport: SubViewport in views:
        if is_instance_valid(viewport): viewport.free()
    var report: Dictionary={"checks":checks,"failures":failures,"engine_errors":logger.errors,"evidence":evidence,"scope":"real saved-safe-point Assembly only; no player/Store/network/MAIN or new work completion"}
    if not output.is_empty():
        var file:=FileAccess.open(output.path_join("result.json"),FileAccess.WRITE)
        if file!=null: file.store_string(JSON.stringify(report,"  ")); file.close()
        else: failures.append({"label":"result_write"})
    print("CANAL_ASSEMBLY_RESTORE_RESULT "+JSON.stringify({"checks":checks,"failures":failures,"engine_errors":logger.errors,"output":output}))
    quit(0 if failures.is_empty() and logger.errors.is_empty() else 1)
