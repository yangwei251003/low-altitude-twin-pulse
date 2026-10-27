extends SceneTree
## Explicit fresh QA World/player initialization only. Afterwards actual
## PilotInput -> Flight forces, real LOS -> Ability.resolve -> device acceptance.
## Tests the in-place thermal path AND its physical cleanup, not a human/UI run.
const World = preload("res://scripts/v3/twin_test_world.gd")
const Assembly = preload("res://scripts/v3/candidates/canal_assembly/canal_assembly.gd")
const Flight = preload("res://scripts/v2/flight_body.gd")
const Catalog = preload("res://scripts/v2/catalog.gd")
const Inputs = preload("res://scripts/v2/pilot_input.gd")
const Ability = preload("res://scripts/v3/gameplay/twin_ability_rules.gd")
const Rules = Assembly.Runtime
const PLAYER := "player:qa_assembly"
const DT := 1.0/60.0
const MASK := 1|2|4|8|32
var viewport: SubViewport
var world: Node3D
var assembly: Node3D
var player: Flight
var inputs: Inputs
var ability=Ability.new()
var entities: Dictionary={}
var targets: Dictionary={}
var checks:=0
var failures: Array=[]
var trace: Array=[]
var finished:=false
var output:=""
var ticks:=0
var cooldown:=0.0
var last_phase:=""
var original_structures: Dictionary={}
var work_snap: Dictionary={}
var initial_temperature_position:=Vector3.ZERO
var waiting_max_distance:=0.0
var observations: Dictionary={"waiting_ticks":0,"work_ticks":0,"receipt_changes":[],"handoff_frames":0,"maximum_player_distance_from_initial":0.0}
class ErrorLog extends Logger:
    var errors: Array=[]
    func _log_error(fn: String,file: String,line: int,code: String,reason: String,_notify: bool,kind: int,_traces: Array[ScriptBacktrace]) -> void:
        errors.append({"function":fn,"file":file,"line":line,"code":code,"reason":reason,"kind":kind})
var logger:=ErrorLog.new()

func _initialize() -> void:
    OS.add_logger(logger)
    for argument: String in OS.get_cmdline_user_args():
        if argument.begins_with("--output="): output=argument.trim_prefix("--output=")
    _run.call_deferred()

func _run() -> void:
    create_timer(225).timeout.connect(func():
        if not finished:
            _check(false,"225 second actual physics bound",_sample())
            _finish())
    for script: Script in [World,Assembly,Flight,Inputs]:
        if not _check(script.can_instantiate(),"actual dependency can instantiate",script.resource_path): _finish(); return
    if not _check(Engine.physics_ticks_per_second==60 and Engine.time_scale==1.0,"normal unaccelerated 60 Hz"): _finish(); return
    viewport=SubViewport.new()
    viewport.world_3d=World3D.new()
    viewport.render_target_update_mode=SubViewport.UPDATE_DISABLED
    root.add_child(viewport)
    world=World.new()
    viewport.add_child(world)
    world.build("I2",{},true)
    if not _check(world.build_errors.is_empty(),"caller creates real production I2 with four facilities",world.build_errors): _finish(); return
    for i in 3: await physics_frame
    original_structures=_structures()
    # The caller owns this actual player and input, not the Assembly. Sole pose
    # fixture starts at the previously verified west observation approach.
    player=Flight.new()
    player.name="QA_ExternalPlayer"
    player.configure(Catalog.resolve_build(Catalog.default_build("tr01")))
    player.max_altitude=18
    player.position=Vector3(2.5,3,8.5)
    player.hold_height=player.position.y
    player.safe_position=player.position
    player.environment_query=world.sample_environment
    player.environment_hazards_authoritative=true
    world.add_child(player)
    inputs=Inputs.new()
    inputs.test_enabled=true
    inputs.active=true
    inputs.test_frame={"axes":{},"held":["brake"]}
    viewport.add_child(inputs)
    entities[PLAYER]={"owner":"1","tags":["player"],"health":player.health,"energy":100.0,"position":player.global_position,"revision":0}
    assembly=Assembly.new()
    assembly.name="CanalAssembly"
    world.add_child(assembly)
    var denied: Dictionary=assembly.configure(world,world.sample_environment,false)
    _check(not denied.ok and assembly.get_child_count()==0,"non-host configure creates no actors",denied)
    var made: Dictionary=assembly.configure(world,world.sample_environment,true)
    if not _check(made.ok,"Assembly initializes existing factory in the caller's actual space",made): _finish(); return
    _check(assembly.find_children("*","Camera3D",true,false).is_empty() and assembly.find_children("*","Control",true,false).is_empty() and assembly.find_children("*","PilotInputV2",true,false).is_empty(),"Assembly owns no camera, UI or player input")
    for i in 3300:
        if not await _frame(): return
        if assembly.status().ready: break
    if not _check(assembly.status().ready,"real bootstrap seats, grips, lifts and reaches WAIT",assembly.status(true)): _finish(); return
    var ctx: Dictionary=assembly.context()
    _check(is_instance_valid(ctx.cooling) and is_instance_valid(ctx.workbench) and assembly.status().rack_art_ok,"actual cooling and imported physical workbench exist")
    _check(assembly.is_ancestor_of(ctx.carrier) and ctx.carrier.get_world_3d().space==world.get_world_3d().space,"ownership is inside Assembly without replacing World3D")
    _check(ctx.cargos.size()==2 and ctx.berths.size()==4 and ctx.carrier.cargo_items.size()==1,"same two 2kg loads/four docks and actual PinJoint bootstrap")
    _sync_targets()
    _check(targets.size()==6 and targets[Assembly.Workbench.POWER_ID]==ctx.workbench.power_target and targets[Assembly.VALVE_ID]==ctx.cooling.valve,"six target entries bind actual bodies")
    await _authority_and_pause()
    if finished: return
    if not failures.is_empty(): _finish(); return
    var original_position: Vector3=ctx.cargos[Rules.CASSETTES[1]].global_position
    initial_temperature_position=original_position
    if not _use(Assembly.Workbench.POWER_ID,"charge",""): _finish(); return
    for i in 24:
        if not await _frame(): return
    if not _use(Rules.CASSETTES[1],"heat","cool"): _finish(); return
    var cooled: Dictionary=ctx.rules.snapshot()
    _check(cooled.thermal_ledger.ability_removed==25000000 and float(ctx.rules.status().temperatures_c[Rules.CASSETTES[1]])<=45,"real thermal action pays exact 25 kJ removal",cooled.thermal_ledger)
    _check(ctx.cargos[Rules.CASSETTES[1]].global_position.distance_to(original_position)<.02,"in-place solution did not move supported WORK load")
    for i in 300:
        if not await _frame(): return
    _check(waiting_max_distance<.18 and ctx.rules.snapshot().pending_action.is_empty() and not assembly.status().ordered,"waiting carrier is held by swept Pilot before any work order",{"max_wait_distance":waiting_max_distance,"state":assembly.status(true)})
    if not await _fly_to(Vector3(8,3.2,27)): return
    if not _use(Assembly.RELAY_ID,"charge",""): _finish(); return
    for i in 24:
        if not await _frame(): return
    if not _use(Assembly.VALVE_ID,"push_pull","pull"): _finish(); return
    for i in 120:
        if not await _frame(): return
    _check(ctx.cooling.facts().powered and ctx.cooling.facts().valve_open,"actual south-side pull opens powered cooling axis through original sweep",ctx.cooling.report())
    if not _use(Assembly.CARRIER_ID,"takeover",""): _finish(); return
    _check(assembly.status().ordered,"one accepted host capability hands controller to original Executor")
    var duplicate: Dictionary=assembly.apply_authorized_ability(Assembly.CARRIER_ID,"takeover","",[],true)
    _check(not duplicate.ok and duplicate.code=="work_order_exists","second order cannot create another Executor or demand",duplicate)
    if not await _fly_to(Vector3(2.5,3,8.5)): return
    for i in 9600:
        if not await _frame(): return
        var row: Dictionary=ctx.workbench.report()
        if row.committed and work_snap.is_empty(): work_snap={"work":row,"rules":ctx.rules.snapshot(),"executor":ctx.executor.report()}
        if _complete(ctx): break
    var state: Dictionary=ctx.rules.snapshot()
    _check(not work_snap.is_empty() and work_snap.work.receipt_count==1 and work_snap.work.receipt.receipt.serial==1,"first work is actual original cassette scan/return and single receipt",work_snap)
    _check(ctx.workbench.report().phase=="departed" and ctx.workbench.report().departure.arrived,"same actual beneficiary flies off and reaches separated endpoint",ctx.workbench.report())
    _check(_complete(ctx),"normal continuous host physically returns both cassettes to distinct south docks",_sample())
    _check(ctx.executor.report().receipt_count==6,"local-work cleanup uses six real move/place/pick receipts",ctx.executor.report())
    _check(state.jobs_completed==1 and state.service_credit==1 and state.services_consumed==0 and not state.job_requested and state.thermal_ledger.work_added==Rules.WORK_HEAT_MJ,"existing sole work/service/25kJ ledger only",state)
    _check(int(assembly.status().cooling_transfer_delay_count)>0,"actual place/cooling overlap uses exact original pending handoff",assembly.status())
    _check(int(state.pump_total_ml)>0,"real returned supported loads allow the original powered closed cooling loop",ctx.cooling.facts())
    _check(_structures()==original_structures,"original four facility transforms/shapes/RIDs are unchanged")
    for i in 300:
        if not await _frame(): return
    var final_state: Dictionary=ctx.rules.snapshot()
    _check(final_state.jobs_completed==1 and final_state.service_credit==1 and final_state.services_consumed==0 and ctx.workbench.report().receipt_count==1 and final_state.pending_action.is_empty(),"five more seconds do not fabricate work, consume service or restart transport")
    _check(ctx.carrier.collision_count==0 and ctx.carrier.health==ctx.carrier.maximum_health and not ctx.carrier.water_contact and ctx.workbench.beneficiary.collision_count==0 and player.collision_count==0,"real carrier/beneficiary/player preserve contact and water gates",_sample())
    var preserved: Dictionary=ctx.rules.snapshot()
    _check(assembly.close(false).code=="not_authority" and not assembly.status().closed,"non-host close cannot take control")
    _check(assembly.close(true).ok and ctx.rules.snapshot()==preserved and assembly.target_definitions().is_empty(),"host close preserves rules and withdraws only owned targets")
    _check(not assembly.advance(DT,true).ok and not assembly.apply_authorized_ability(Assembly.RELAY_ID,"charge").ok,"closed site never advances or accepts abilities")
    assembly.free()
    _check(is_instance_valid(world) and is_instance_valid(player) and _structures()==original_structures,"destroying owned Assembly leaves external World/player/four facilities")
    _finish()

func _authority_and_pause() -> void:
    var ctx: Dictionary=assembly.context()
    var rules_before: Dictionary=ctx.rules.snapshot()
    var custody_before: Dictionary=ctx.custody.report()
    var command_before: Dictionary=ctx.carrier.command.duplicate(true)
    var station_before: Dictionary=ctx.cooling.snapshot()
    var denied: Dictionary=assembly.advance(DT,false)
    _check(not denied.ok and denied.code=="not_authority" and ctx.rules.snapshot()==rules_before and ctx.custody.report()==custody_before and ctx.carrier.command==command_before and ctx.cooling.snapshot()==station_before,"non-host tick touches no commands, custody or rules")
    var same: Dictionary=assembly.advance(DT,true)
    _check(not same.ok and same.code=="same_physics_frame" and ctx.rules.snapshot()==rules_before,"second active call in one physics frame rejected without time")
    _check(assembly.set_paused(true,true).ok,"host explicitly pauses rule/control progression")
    var use: Dictionary=assembly.apply_authorized_ability(Assembly.Workbench.POWER_ID,"charge")
    var paused: Dictionary=assembly.advance(DT,true)
    _check(not use.ok and paused.ok and ctx.rules.snapshot()==rules_before and ctx.carrier.command.get("brake",false),"pause rejects actions, accrues no rule time and brakes without claiming physical freeze")
    var custody_paused: Dictionary=ctx.custody.report()
    var axis_paused: Dictionary=ctx.cooling.snapshot().axis
    for i in 30:
        if not await _frame(): return
    _check(ctx.rules.snapshot()==rules_before and ctx.custody.report()==custody_paused and ctx.cooling.snapshot().axis==axis_paused,"thirty actual host frames paused do not advance cargo observations, axis or rules")
    _check(assembly.set_paused(false,true).ok,"host resumes original controllers")

func _frame() -> bool:
    await physics_frame
    if finished: return false
    ticks+=1
    world.clock_seconds+=DT # Caller-owned clock, never Assembly-owned.
    player.environment_sample=world.sample_environment(player.global_position)
    player.command=inputs.command(Basis.IDENTITY)
    player.command.body_relative=false
    player.command.fire=false
    cooldown=maxf(0,cooldown-DT)
    entities[PLAYER].position=player.global_position
    entities[PLAYER].health=player.health
    entities[PLAYER].energy=minf(100.0,float(entities[PLAYER].energy)+DT*9.0)
    _sync_targets()
    var timed: Dictionary=ability.advance_states(entities,DT)
    if timed.ok: ability.commit(timed,entities)
    var advanced: Dictionary=assembly.advance(DT,true,false)
    if not advanced.ok or not logger.errors.is_empty():
        _check(false,"continuous Assembly remains healthy",{"advance":advanced,"errors":logger.errors,"actual":_sample()})
        _finish(); return false
    var ctx: Dictionary=assembly.context()
    if assembly.status().ready:
        if not assembly.status().ordered:
            observations.waiting_ticks+=1
            waiting_max_distance=maxf(waiting_max_distance,ctx.carrier.global_position.distance_to(Assembly.Executor.WAIT_POINT))
        if not ctx.workbench.report().action.is_empty(): observations.work_ticks+=1
        var phase: String=str(ctx.workbench.report().phase)+":"+str(ctx.executor.report().phase)
        if phase!=last_phase or ticks%180==0:
            trace.append(_sample())
            last_phase=phase
    observations.maximum_player_distance_from_initial=maxf(observations.maximum_player_distance_from_initial,player.global_position.distance_to(Vector3(2.5,3,8.5)))
    return true

func _sync_targets() -> void:
    if not is_instance_valid(assembly): return
    for row: Dictionary in assembly.target_definitions():
        targets[row.id]=row.body
        if not entities.has(row.id): entities[row.id]={"owner":"neutral","revision":0,"tags":row.tags.duplicate()}
        entities[row.id].merge(row.state.duplicate(true),true)

func _use(id: String, tool: String, mode: String) -> bool:
    _sync_targets()
    if cooldown>0 or not targets.has(id): return _check(false,"host input ready",{"cooldown":cooldown,"target":id})
    var body: PhysicsBody3D=targets[id]
    var excluded: Array[RID]=[player.get_rid()]
    var ray:=PhysicsRayQueryParameters3D.create(player.global_position,body.global_position,MASK,excluded)
    var hit: Dictionary=world.get_world_3d().direct_space_state.intersect_ray(ray)
    var intent: Dictionary={"actor_id":PLAYER,"target_id":id,"ability":tool,"mode":mode}
    var resolved: Dictionary=ability.resolve(intent,entities,{"sender_id":"1","line_of_sight":not hit.is_empty() and hit.get("collider")==body})
    if not _check(resolved.ok,"actual range/first-hit/energy rules accept player intent",{"intent":intent,"resolved":resolved,"from":player.global_position,"to":body.global_position,"first_hit":str(hit.get("collider"))}): return false
    var candidate: Dictionary=entities.duplicate(true)
    var staged: Dictionary=ability.commit(resolved,candidate,true)
    if not _check(staged.ok,"generic ability transaction stages privately",staged): return false
    var energy: float=float(entities[PLAYER].energy)
    var applied: Dictionary=assembly.apply_authorized_ability(id,tool,mode,resolved.physics_requests,true)
    if not _check(applied.ok,"real device accepts before adopting actor transaction",applied): return false
    _check(float(entities[PLAYER].energy)==energy,"Assembly did not secretly debit actor energy")
    entities=candidate
    cooldown=.35
    _check(absf(float(entities[PLAYER].energy)-(energy-float(Ability.DEFINITIONS[tool].energy)))<.00001,"only original Ability.commit pays declared cost")
    _sync_targets()
    return true

func _fly_to(destination: Vector3) -> bool:
    for i in 1200:
        var offset: Vector3=destination-player.global_position
        var desired: Vector3=(Vector3(offset.x,0,offset.z)*.6-player.linear_velocity*.5).limit_length(.45)
        var slow: bool=Vector2(offset.x,offset.z).length()<.3 and player.linear_velocity.length()<.35 and absf(offset.y)<.25
        inputs.test_frame={"axes":{"right_x":desired.x,"right_y":-desired.z,"left_y":clampf(offset.y*.7,-.35,.35)},"held":["brake"] if slow else []}
        if not await _frame(): return false
        if slow:
            inputs.test_frame={"axes":{},"held":["brake"]}
            return _check(true,"external actual PilotInput flight reaches interaction approach",{"actual":player.global_position,"target":destination})
    _check(false,"bounded external player approach",{"actual":player.global_position,"target":destination})
    _finish(); return false

func _complete(ctx: Dictionary) -> bool:
    var state: Dictionary=ctx.rules.snapshot()
    if ctx.workbench.report().phase!="departed" or int(state.jobs_completed)!=1 or not state.pending_action.is_empty() or not ctx.carrier.cargo_items.is_empty(): return false
    var seen: Dictionary={}
    for id: String in Rules.CASSETTES:
        var holder: String=str(state.cassettes[id].holder)
        if holder not in [Rules.SOUTH_0,Rules.SOUTH_1] or seen.has(holder): return false
        seen[holder]=true
        var physical: Dictionary=ctx.custody.report().cargos[id]
        if physical.phase!="docked" or physical.berth!=holder or physical.stable_usec<350000 or not ctx.custody.support_info(id,holder).get("supported",false): return false
    return true

func _structures() -> Dictionary:
    var result: Dictionary={}
    for body: Node in world.find_children("*","CollisionObject3D",true,false):
        if is_instance_valid(assembly) and assembly.is_ancestor_of(body): continue
        if not body is StaticBody3D and not body is AnimatableBody3D: continue
        var shapes: Array=[]
        for owner: int in body.get_shape_owners():
            for i in body.shape_owner_get_shape_count(owner): shapes.append([body.shape_owner_get_shape(owner,i).get_rid(),body.is_shape_owner_disabled(owner)])
        result[body.get_instance_id()]=[body.get_rid(),body.global_transform,body.collision_layer,body.collision_mask,shapes]
    return result

func _sample() -> Dictionary:
    var result: Dictionary={"tick":ticks}
    if is_instance_valid(player): result.player={"position":player.global_position,"health":player.health,"collision_count":player.collision_count}
    if is_instance_valid(assembly):
        result.assembly=assembly.status(true)
        var ctx: Dictionary=assembly.context()
        if is_instance_valid(ctx.get("carrier")):
            result.carrier={"position":ctx.carrier.global_position,"velocity":ctx.carrier.linear_velocity,"health":ctx.carrier.health,"collision_count":ctx.carrier.collision_count}
    return result

func _check(ok: bool, label: String, details: Variant = null) -> bool:
    checks+=1
    if not ok: failures.append({"label":label,"details":details})
    return ok

func _finish() -> void:
    if finished: return
    finished=true
    _check(logger.errors.is_empty(),"no engine errors",logger.errors)
    var report: Dictionary={"checks":checks,"failures":failures,"engine_errors":logger.errors,"last":_sample(),"work_commit":work_snap,"observations":observations,"trace":trace,"scope":"actual production I2 + fresh QA player at (2.5,3,8.5); original PilotInput/Ability, real work/cleanup. No UI/human/MAIN/save/LAN/second exchange route proof."}
    if not output.is_empty():
        var file:=FileAccess.open(output.path_join("result.json"),FileAccess.WRITE)
        if file!=null: file.store_string(JSON.stringify(report,"  ")); file.close()
        else: failures.append({"label":"result_write"})
    print("CANAL_ASSEMBLY_RESULT "+JSON.stringify({"checks":checks,"failures":failures,"engine_errors":logger.errors,"ticks":ticks,"output":output}))
    if is_instance_valid(viewport): viewport.free()
    quit(0 if failures.is_empty() else 1)
