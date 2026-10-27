extends SceneTree
## One selected later Boss in actual MAIN. Only the development-area access,
## prior Director rule receipts, and collision-checked PLAYER poses are QA.
const MAIN=preload("res://scenes/v3/main.tscn")
const Regions=preload("res://scripts/v3/world/twin_region_catalog.gd")
const Layout=preload("res://scripts/v3/campaign/twin_campaign_layout.gd")
const Campaign=preload("res://scripts/v3/gameplay/twin_campaign_session.gd")
const Store=preload("res://scripts/v3/core/twin_world_store.gd")
const BOSSES={"I3":"furnace_crawler","F3":"mycelial_choir","I4":"prism_array","F4":"twin_vein_core"}
class ErrorLogger extends Logger:
    var guard:=Mutex.new()
    var errors: Array=[]
    func _log_error(function: String,file: String,line: int,code: String,rationale: String,_notify: bool,kind: int,_trace: Array[ScriptBacktrace]) -> void:
        if kind==Logger.ERROR_TYPE_WARNING: return
        guard.lock()
        errors.append({"function":function,"file":file,"line":line,"code":code,"rationale":rationale})
        guard.unlock()
var logger:=ErrorLogger.new()
var session: Node
var profile: String=""
var output: String=""
var region: String=""
var boss: String=""
var reward: String=""
var checks: Array=[]
var trace: Array=[]
var operations: Array=[]
var shots: Array=[]
var damage_receipts: Array=[]
var other_damage: Array=[]
var victory: Dictionary={}
var fixture_receipts:=0
var phase_two:=false
var warning_token: String=""
var trace_key: String=""
var finished:=false
var start_msec:=0
var initial_environment: Dictionary={}
var prepared_environment: Dictionary={}

func _initialize() -> void:
    OS.add_logger(logger)
    _run.call_deferred()

func _run() -> void:
    for arg: String in OS.get_cmdline_user_args():
        if arg.begins_with("--qa-profile="): profile=arg.trim_prefix("--qa-profile=")
        if arg.begins_with("--output="): output=arg.trim_prefix("--output=")
        if arg.begins_with("--region="): region=arg.trim_prefix("--region=")
    if region not in BOSSES or not profile.begins_with("qa_remaining_combat_") or profile!=profile.validate_filename() or DirAccess.dir_exists_absolute("user://profiles_v3/"+profile) or not output.begins_with("res://artifacts/v3/campaign-remaining-combat-") or ".." in output or DirAccess.dir_exists_absolute(output): quit(2); return
    boss=BOSSES[region]
    reward="boss:"+region+":"+boss
    start_msec=Time.get_ticks_msec()
    DirAccess.make_dir_recursive_absolute(output)
    create_timer(60).timeout.connect(func():
        if not finished:
            _check(false,"60 second selected-region integration bound; runner hard limit65s",_diagnostics())
            _finish())
    # In-memory QA access only; do not unlock a real campaign/profile.
    Regions._entries=Regions.entries()
    var layout: Dictionary=Layout.definition(region)
    for entry: Dictionary in Regions._entries:
        if entry.id==region:
            entry.playable=true
            entry.spawn=layout.spawn.duplicate()
            entry.bounds=layout.bounds.duplicate()
    session=MAIN.instantiate()
    root.add_child(session)
    session.canal_runtime_enabled=false
    session.thermal_cargo.enabled=false # Separate cargo acceptance is not replayed here.
    if not _check(session.profile_ready and session.store.commit({"id":"qa-remaining-combat-location-only","set":{"world.region_id":region}}).ok,"new isolated original Store receives only an explicit QA start-location fixture"): _finish(); return
    session.world_cache=session.store.snapshot()
    if not _check(session.start_flight("solo") and session.region_id==region and session.world.build_errors.is_empty() and session.campaign.supported(),"ordinary MAIN factory loads actual empty selected area BEFORE any prior-Director fixture",_diagnostics()): _finish(); return
    session.inputs.test_enabled=true
    session.inputs.test_frame={"axes":{},"held":["brake"],"edges":[]}
    var actor: FlightBodyV2=session.players[1]
    actor.damage_resolved.connect(func(receipt: Dictionary):
        var record: Dictionary=receipt.duplicate(true)
        record["attack_token"]=_state().get("attack",{}).get("token","")
        record["physics_frame"]=Engine.get_physics_frames()
        if receipt.get("source")==boss: damage_receipts.append(record)
        else: other_damage.append(record))
    await _frame()
    await _frame()
    if finished: return
    initial_environment=_environment()
    if not _check(not initial_environment.is_empty() and not _conditions_ready(initial_environment),"default real mechanism sample leaves at least one Boss part condition closed",initial_environment): _finish(); return
    if not await _prepare_mechanisms(): _finish(); return
    prepared_environment=_environment()
    if not _check(_conditions_ready(prepared_environment),"original G/Ability changes actual mechanisms until every authored part condition is physically ready",{"environment":prepared_environment,"view":session.campaign.mechanisms.view_state(),"operations":operations}): _finish(); return
    # The first armor shot must have the same real visibility requirement as
    # later shots. Full aircraft clearance alone does not prove weapon LOS.
    if not await _battle_pose(false,str(session.campaign.definition.parts[0]),true): _finish(); return
    for unused in 3:
        await _frame()
        if finished: return
    if not _check(not session.campaign.active() and _state().is_empty(),"real nearby actor and prepared mechanisms cannot start Boss without its Story plan"): _finish(); return
    if not _fixture_through_plan(): _finish(); return
    session.story.load_world()
    for unused in 30:
        await _frame()
        if finished: return
        if session.campaign.active(): break
    if not _check(session.campaign.active() and session.boss_active and int(_state().get("attempt",0))==1,"ordinary MAIN starts the one encounter after the valid current plan and actual arena proximity",_diagnostics()): _finish(); return
    # The initial warning locks onto the actual QA observation pose. Keep that
    # pose until its first real attack calls the original Flight Damage path.
    var closed_part: String=session.campaign.encounter.current_part()
    var closed_id: String=session.world.campaign_arena.target_id(closed_part)
    var hp: int=int(_state().parts[closed_part])
    var fired: int=session.stats.shots
    session._action_received(1,"lock",{"target_id":closed_id})
    session._fire(1)
    if not _check(_state().attack_stage=="warning" and int(_state().parts[closed_part])==hp and session.stats.shots==fired+1,"real host weapon shot cannot damage armored part before recovery even with mechanisms ready",_diagnostics()): _finish(); return
    for unused in 480:
        await _frame()
        if finished: return
        if not damage_receipts.is_empty(): break
    var original_damage: bool=not damage_receipts.is_empty()
    var per_token: Dictionary={}
    for receipt: Dictionary in damage_receipts:
        original_damage=original_damage and receipt.get("source")==boss and receipt.get("weapon_type")=="pulse" and float(receipt.get("damage",0))>0.0 and float(receipt.get("health",100))<float(receipt.get("health_before",100))
        var token: String=str(receipt.attack_token)
        per_token[token]=int(per_token.get(token,0))+1
    for count: int in per_token.values(): original_damage=original_damage and count==1
    if not _check(original_damage and actor.enabled and int(_state().attempt)==1,"authored warning/active geometry and actual LOS cause original player Damage once per attack token",{"receipts":damage_receipts,"per_token":per_token,"diagnostics":_diagnostics()}): _finish(); return
    warning_token="" # Subsequent warning poses are explicit QA, not flown dodges.
    if not await _fight(): _finish(); return
    _finish()

func _prepare_mechanisms() -> bool:
    match region:
        "I3":
            for unused in 2:
                if not await _ability("I3:boss_radiator","heat","cool"): return false
        "F3":
            if not await _operate("F3:signal_breaker") or not await _operate("F3:signal_hold"): return false
            if not await _grow("F3:nutrient_bridge"): return false
        "I4":
            if not await _ability("I4:witness_source","light","on") or not await _operate("I4:defence_breaker"): return false
        "F4":
            if not await _ability("F4:limited_bus","charge","add"): return false
            if not await _ability("F4:living_emitter","light","on") or not await _grow("F4:living_support",false): return false
            if not await _operate("F4:core_charge_breaker"): return false
            for unused in 2:
                if not await _ability("F4:core_thermal_sink","heat","cool"): return false
            if not await _grow("F4:core_living_support"): return false
    # No time injection: current native support/rays are observed by the real
    # mechanisms on ordinary Session ticks, including their 0.3s stability gates.
    for unused in 120:
        await _frame()
        if finished: return false
        if _conditions_ready(_environment()): return true
    return _check(false,"actual physical mechanism conditions settle within ordinary two-second observation",_diagnostics())

func _grow(id: String,illuminate: bool=true) -> bool:
    if illuminate and not await _ability(id,"light","on"): return false
    # Real span endpoints require the full original 3m collider, not just the
    # .7 scalar lower bound. These are three original growth transactions.
    for unused in 3:
        if not await _ability(id,"growth",""): return false
    return true

func _ability(id: String,ability: String,mode: String) -> bool:
    if not await _near(id): return false
    for unused in 90:
        if float(session.cooldowns.get(1,0))<=0.0 and float(session.entities[session._actor_id(1)].get("energy",0))>=12.0: break
        await _frame()
        if finished: return false
    var before: Dictionary=session.entities[id].duplicate(true)
    var count: int=session.stats.abilities
    session._action_received(1,"ability",{"ability":ability,"target_id":id,"mode":mode})
    await _frame()
    if finished: return false
    var after: Dictionary=session.entities[id].duplicate(true)
    operations.append({"type":"original_ability","target":id,"ability":ability,"mode":mode,"before":before,"after":after,"physics_frame":Engine.get_physics_frames()})
    return _check(session.stats.abilities==count+1,"original authenticated nearby Ability accepted: "+id+":"+ability+":"+mode,{"before":before,"after":after,"diagnostics":_diagnostics()})

func _operate(id: String) -> bool:
    if not await _near(id): return false
    var body: PhysicsBody3D=session.world.objects[id]
    var before: Transform3D=body.global_transform
    var next: Transform3D=before
    var contract: Dictionary=Campaign.OPERATIONS[id]
    if contract.get("angle",false): next.basis=Basis(Vector3.UP,0.0 if absf(wrapf(body.rotation.y,-PI,PI))>.4 else PI*.5)
    else: next.origin=contract.open if before.origin.distance_to(contract.closed)<=.4 else contract.closed
    var generation: int=session.store.snapshot().generation
    session._action_received(1,"lock",{"target_id":id})
    session.interface.clear_dialogue()
    var event:=InputEventKey.new()
    event.physical_keycode=KEY_G
    event.keycode=KEY_G
    event.pressed=true
    session._unhandled_input(event)
    await _frame()
    await _frame()
    if finished: return false
    var native: Transform3D=PhysicsServer3D.body_get_state(body.get_rid(),PhysicsServer3D.BODY_STATE_TRANSFORM)
    var accepted: bool=body.global_position.distance_to(next.origin)<.002 and body.global_basis.is_equal_approx(next.basis) and native.origin.distance_to(next.origin)<.002 and native.basis.is_equal_approx(next.basis) and int(session.store.snapshot().generation)>generation and session.campaign.last_operation_blockers.is_empty()
    operations.append({"type":"original_G","target":id,"before":before,"expected":next,"node":body.global_transform,"native":native,"generation_before":generation,"generation_after":session.store.snapshot().generation})
    return _check(accepted,"original G changes real device and commits the original Store: "+id,{"operation":operations.back(),"diagnostics":_diagnostics()})

func _fixture_through_plan() -> bool:
    var director=session.story.director
    var state: Dictionary=director.default_state()
    var plan: String=region+":"+boss+":plan"
    var found:=false
    for action: Dictionary in director.definitions().actions:
        for objective: Dictionary in action.objectives:
            var matcher: Dictionary=objective.events[0]
            var applied: Dictionary=director.apply_event(state,{"id":"qa-remaining-combat-prefix:"+str(objective.id),"type":matcher.type,"target_id":matcher.target_id,"option":matcher.options[0]},{"is_authority":true,"validated":true,"region_id":action.region_id})
            if not applied.get("ok",false) or not applied.get("changed",false): return _check(false,"ordered Director fixture uses legal earlier rule receipts",{"objective":objective.id,"result":applied.get("code")})
            state=applied.state
            fixture_receipts+=1
            if objective.id==plan: found=true; break
        if found: break
    if not _check(found and plan in state.completed and director.validate_state(state).ok,"valid rule-only QA prefix stops at this Boss plan; earlier campaign was not played",{"last_objective":plan,"fixture_receipts":fixture_receipts}): return false
    var stored: Dictionary=session.store.commit({"id":"qa-remaining-combat-plan-rules-only","set":{"world.actions.opening":state}})
    if not _check(stored.ok,"Director fixture commits AFTER real empty-area construction; no physical history injected",stored): return false
    session.world_cache=session.store.snapshot()
    session.consensus.set_world_revision(int(session.world_cache.world_revision))
    return true

func _fight() -> bool:
    for unused in 3300:
        await _frame()
        if finished: return false
        var state: Dictionary=_state()
        phase_two=phase_two or int(state.get("phase",0))==2
        if state.get("completed",false): return _published_victory()
        if not session.players[1].enabled or int(state.attempt)!=1: return _check(false,"weapon/QA observation phase never silently restarts the attempt",_diagnostics())
        var token: String=str(state.get("attack",{}).get("token",""))
        if state.attack_stage=="warning" and token!=warning_token:
            warning_token=token
            if not await _battle_pose(true): return false
            continue
        var part: String=session.campaign.encounter.current_part()
        if not session.campaign.encounter.part_open(part) or float(session.weapon_cooldowns.get(1,0))>0.0: continue
        var actor: FlightBodyV2=session.players[1]
        var id: String=session.world.campaign_arena.target_id(part)
        var target: Node3D=session.world.campaign_arena.targets[id]
        if actor.global_position.distance_to(target.global_position)>36.0 or not session._line_clear(actor.global_position,target.global_position,actor.get_rid(),id):
            if not await _battle_pose(true,part): return false
            continue
        var hp: int=int(state.core_hp_milli) if part=="core" else int(state.parts[part])
        session._action_received(1,"lock",{"target_id":id})
        session._fire(1)
        var after: Dictionary=_state()
        var actual_hp: int=int(after.core_hp_milli) if part=="core" else int(after.parts[part])
        if actual_hp<hp: shots.append({"physics_frame":Engine.get_physics_frames(),"part":part,"phase":state.phase,"hp_before":hp,"hp_after":actual_hp,"environment":state.environment})
        if after.get("completed",false): return _published_victory()
    return _check(false,"actual mechanisms and normal weapons complete two phases within selected-region bound",_diagnostics())

func _published_victory() -> bool:
    var saved: Dictionary=session.store.snapshot()
    var complete: bool=phase_two and not shots.is_empty() and not damage_receipts.is_empty() and _state().get("completed",false) and int(_state().core_hp_milli)==0 and session.campaign.victory_committed() and not session.pending_completion and not session.boss_active and int(_state().attempt)==1 and saved.personal.discoveries.count(reward)==1 and _victory_commits(saved)==1
    if not _check(complete,"real original weapon HP loss reaches both phases and exactly one original Store victory/reward",{"shots":shots.size(),"phase_two":phase_two,"victory_commits":_victory_commits(saved),"diagnostics":_diagnostics()}): return false
    var generation: int=saved.generation
    for repeat in 3: session._finish_boss()
    var repeated: Dictionary=session.store.snapshot()
    _check(int(repeated.generation)==generation and repeated.personal.discoveries.count(reward)==1 and _victory_commits(repeated)==1,"repeated normal finish adds no generation, victory receipt or reward")
    var reader=Store.new(session.store.root_path)
    var opened: Dictionary=reader.load_profile()
    var disk: Dictionary=reader.snapshot()
    var envelope: Dictionary=disk.world.get("environment",{}).get("campaign_"+region,{})
    var encounter_valid: Dictionary=session.campaign.encounter.validate_snapshot(envelope.get("encounter",{}))
    var mechanism_valid: Dictionary=session.campaign.mechanisms.validate_state(envelope.get("mechanisms",{}))
    var disk_ok: bool=opened.ok and encounter_valid.ok and mechanism_valid.ok and disk.personal.discoveries.count(reward)==1 and _victory_commits(disk)==1 and disk.world.flags.get("campaign_boss:"+region,false) and envelope.get("encounter",{}).get("state",{}).get("completed",false)
    _check(disk_ok,"independent original Store reader verifies real completed encounter/mechanism ledger and unique reward",{"opened":opened,"encounter_validation":encounter_valid,"mechanism_validation":mechanism_valid,"envelope":envelope})
    victory={"generation":generation,"successful_shots":shots.size(),"phase_two":phase_two,"reward_count":disk.personal.discoveries.count(reward),"victory_commits":_victory_commits(disk),"disk_valid":disk_ok,"attempt":_state().attempt}
    session._refresh_interface()
    var actor_position: Vector3=session.players[1].global_position
    var contact: String=session.story.nearest(actor_position)
    var hud_ok: bool=not session.boss_active and session.interface.boss_info.text.is_empty() and session.interface.objective.text==session.story.objective_text(actor_position,session.interface.details_open) and session.interface.explore_button.visible==(not contact.is_empty() or session.interface.radio.visible)
    _check(hud_ok,"real committed victory restores original Story objective/contact HUD while retaining completed encounter",{"objective":session.interface.objective.text,"boss_info":session.interface.boss_info.text,"contact":contact,"completed_encounter":_state().get("completed",false)})
    return complete and disk_ok and hud_ok

func _victory_commits(snapshot: Dictionary) -> int:
    var count:=0
    for id: String in snapshot.ledger.commits:
        if id.begins_with("campaign-boss:"+boss+":"): count+=1
    return count

func _near(id: String) -> bool:
    if not _check(session.world.objects.has(id) and session.entities.has(id),"actual mechanism target exists: "+id): return false
    var body: Node3D=session.world.objects[id]
    for offset: Vector3 in [Vector3(0,3.4,0),Vector3(0,0,3.4),Vector3(0,0,-3.4),Vector3(-3.4,0,0),Vector3(3.4,0,0),Vector3(0,-3.4,0)]:
        var at: Vector3=body.global_position+offset
        if _clear_pose(at) and session._line_clear(at,body.global_position,session.players[1].get_rid(),id): return await _place(at,"near "+id)
    return _check(false,"real device has a collision-free nearby player observation pose with LOS",{"id":id,"diagnostics":_diagnostics()})

func _battle_pose(avoid_attack: bool,part: String="",require_entry: bool=false) -> bool:
    var centre: Vector3=session.world.campaign_arena.centre()
    for offset: Vector3 in [Vector3(6,6,9),Vector3(-6,6,-9),Vector3(-6,6,9),Vector3(6,6,-9),Vector3(8,8,9),Vector3(-8,8,-9)]:
        var at: Vector3=centre+offset
        if require_entry and at.z>float(Layout.definition(region).boss_arena.entry_z): continue
        if not _clear_pose(at): continue
        if avoid_attack and _inside_attack(at): continue
        if not part.is_empty():
            var id: String=session.world.campaign_arena.target_id(part)
            var target: Node3D=session.world.campaign_arena.targets[id]
            if at.distance_to(target.global_position)>36.0 or not session._line_clear(at,target.global_position,session.players[1].get_rid(),id): continue
        return await _place(at,"battle observation, not flown evasion")
    return _check(false,"actual aircraft hull/attack geometry permits a safe QA weapon observation pose",_diagnostics())

func _inside_attack(at: Vector3) -> bool:
    var state: Dictionary=_state()
    if state.get("attack_stage") not in ["warning","active"]: return false
    var mm: Array=[int(round(at.x*1000)),int(round(at.y*1000)),int(round(at.z*1000))]
    for shape: Dictionary in state.get("attack",{}).get("shapes",[]):
        if Campaign.Encounter.contains_shape(shape,mm): return true
    return false

func _clear_pose(at: Vector3) -> bool:
    if not Regions.contains(region,at): return false
    var actor: FlightBodyV2=session.players[1]
    var envelope: CollisionShape3D=actor.get_node("Envelope") as CollisionShape3D
    var query:=PhysicsShapeQueryParameters3D.new()
    query.shape=envelope.shape
    query.transform=Transform3D(Basis.IDENTITY,at)*envelope.transform
    query.collision_mask=1|2|8|32
    query.exclude=[actor.get_rid()]
    return session.world.get_world_3d().direct_space_state.intersect_shape(query,1).is_empty()

func _place(at: Vector3,label: String) -> bool:
    if not _check(_clear_pose(at),"explicit QA PLAYER-only pose has actual hull clearance: "+label,at): return false
    var actor: FlightBodyV2=session.players[1]
    actor.freeze=true
    actor.global_transform=Transform3D(Basis.IDENTITY,at)
    actor.force_update_transform()
    PhysicsServer3D.body_set_state(actor.get_rid(),PhysicsServer3D.BODY_STATE_TRANSFORM,actor.global_transform)
    actor.linear_velocity=Vector3.ZERO
    actor.angular_velocity=Vector3.ZERO
    actor.hold_height=at.y
    await _frame()
    return not finished

func _conditions_ready(environment: Dictionary) -> bool:
    if environment.is_empty(): return false
    for conditions: Array in session.campaign.definition.get("part_conditions",{}).values():
        for condition: Dictionary in conditions:
            if not environment.has(condition.field): return false
            var value: Variant=environment[condition.field]
            match str(condition.op):
                "eq":
                    if value!=condition.value: return false
                "le":
                    if not (value is int or value is float) or float(value)>float(condition.value): return false
                "ge":
                    if not (value is int or value is float) or float(value)<float(condition.value): return false
                _: return false
    return true

func _environment() -> Dictionary:
    return session.campaign.mechanisms.boss_environment(region) if is_instance_valid(session) and session.campaign.mechanisms!=null else {}

func _state() -> Dictionary:
    return session.campaign.encounter.get_state() if is_instance_valid(session) and session.campaign.encounter!=null else {}

func _frame() -> void:
    await physics_frame
    await process_frame # Ordinary MAIN exclusively owns simulation and clocks.
    if finished: return
    if Time.get_ticks_msec()-start_msec>=60000:
        _check(false,"60 second real wall-clock integration bound",_diagnostics())
        _finish()
        return
    var state: Dictionary=_state()
    var key: String=str(state.get("attack",{}).get("token",""))+":"+str(state.get("attack_stage",""))+":"+str(state.get("phase",0))+":"+str(state.get("parts",{}))
    if key!=trace_key:
        trace_key=key
        trace.append({"physics_frame":Engine.get_physics_frames(),"state":state,"actor_health":session.players[1].health,"actor_enabled":session.players[1].enabled})

func _diagnostics() -> Dictionary:
    if not is_instance_valid(session): return {"session":"not_installed"}
    var mechanisms: Variant=session.campaign.mechanisms
    return {"region":session.region_id,"active":session.active,"message":session.interface.message.text,"campaign_error":session.campaign.error,"encounter":_state(),"environment":_environment(),"view":mechanisms.view_state() if mechanisms!=null else {},"mechanism_history":mechanisms.persistent_state() if mechanisms!=null else {},"blockers":session.campaign.last_operation_blockers,"campaign_growth_blockers":session.world.get("campaign_growth_blockers") if is_instance_valid(session.world) else {},"growth_geometry":_growth_geometry(),"world_errors":session.world.build_errors if is_instance_valid(session.world) else [],"generation":session.store.snapshot().generation,"last_commit_result":session.last_commit_result.duplicate(true),"pending_completion":session.pending_completion,"thermal_participant_enabled":session.thermal_cargo.enabled}

func _growth_geometry() -> Dictionary:
    var rows: Dictionary={}
    if not is_instance_valid(session.world): return rows
    for id: String in ["F3:nutrient_bridge","F4:living_support","F4:core_living_support"]:
        if not session.world.objects.has(id): continue
        var body: PhysicsBody3D=session.world.objects[id]
        var rid: RID=body.get_rid()
        var native: Transform3D=PhysicsServer3D.body_get_state(rid,PhysicsServer3D.BODY_STATE_TRANSFORM)
        var shapes: Array=[]
        for child: Node in body.get_children():
            if not child is CollisionShape3D: continue
            var collision: CollisionShape3D=child
            shapes.append({"node":str(collision.get_path()),"shape_rid":str(collision.shape.get_rid()),"disabled":collision.disabled,"size":_xyz((collision.shape as BoxShape3D).size) if collision.shape is BoxShape3D else [],"local_pose":_pose(collision.transform),"world_pose":_pose(collision.global_transform)})
        var native_shapes: Array=[]
        for index: int in PhysicsServer3D.body_get_shape_count(rid):
            var shape: RID=PhysicsServer3D.body_get_shape(rid,index)
            var data: Variant=PhysicsServer3D.shape_get_data(shape)
            native_shapes.append({"shape_rid":str(shape),"data":_xyz(data) if data is Vector3 else str(data),"local_pose":_pose(PhysicsServer3D.body_get_shape_transform(rid,index))})
        rows[id]={"growth":session.entities.get(id,{}).get("growth",-1),"light_level":session.entities.get(id,{}).get("light_level",-1),"environment_light":session.entities.get(id,{}).get("environment_light",-1),"body_rid":str(rid),"body_mode":PhysicsServer3D.body_get_mode(rid),"node_world_pose":_pose(body.global_transform),"native_world_pose":_pose(native),"shapes":shapes,"native_shapes":native_shapes}
    return rows

func _xyz(at: Vector3) -> Array:
    return [at.x,at.y,at.z]

func _pose(at: Transform3D) -> Array:
    return _xyz(at.basis.x)+_xyz(at.basis.y)+_xyz(at.basis.z)+_xyz(at.origin)

func _check(ok: bool,label: String,actual: Variant=null) -> bool:
    checks.append({"passed":ok,"label":label,"actual":actual})
    return ok

func _finish() -> void:
    if finished: return
    finished=true
    var failures: Array=checks.filter(func(row: Dictionary): return not row.passed)
    var report: Dictionary={"region":region,"boss":boss,"checks":checks,"failures":failures,"engine_errors":logger.errors,"fixture_receipts":fixture_receipts,"initial_environment":initial_environment,"prepared_environment":prepared_environment,"operations":operations,"trace":trace,"shots":shots,"damage_receipts":damage_receipts,"other_damage":other_damage,"victory":victory,"diagnostics":_diagnostics(),"wall_seconds":float(Time.get_ticks_msec()-start_msec)/1000.0,"scope":"Selected I3/F3/I4/F4 only. Actual MAIN first constructs empty private QA region; explicit in-memory playable/start-location fixture, then original G/Ability modifies real authored mechanisms and original late adapter observes actual poses/rays/support/thermal/velocity. Only afterward legal prior Director RULE receipts through current Boss plan are imported; they are not played prior flights or prior physical facility evidence and this QA profile is not a whole-campaign/fresh-MAIN restore proof. Collision-checked PLAYER-only frozen observation poses are QA, not flown dodges. Actual original warning/LOS/Flight Damage, normal lock/fire/cooldowns and two-phase HP loss, original Store one victory/reward, duplicate finish and independent disk reader. No Boss/player HP, environment, encounter state, mechanism transform, geometry or simulation clock is set. Canal and separate I3 thermal cargo participant disabled to isolate combat; no cargo-route proof. Headless integration only; no graphics, current performance, LAN, fun/difficulty or full-game completion claim."}
    FileAccess.open(output+"/result.json",FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
    print("CAMPAIGN_REMAINING_COMBAT_RESULT ",JSON.stringify({"region":region,"checks":checks.size(),"failures":failures,"engine_errors":logger.errors,"victory":victory,"diagnostics":report.diagnostics}))
    if is_instance_valid(session):
        session.environment_save_gate.cancel("qa_remaining_combat_teardown")
        session.thermal_cargo.clear()
        if session.canal!=null: session.canal.clear()
        session.network.close()
        session.free()
        session=null
    await process_frame
    await physics_frame
    await process_frame
    quit(0 if failures.is_empty() and logger.errors.is_empty() and not victory.is_empty() else 1)
