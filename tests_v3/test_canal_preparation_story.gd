extends SceneTree
## Real saved A -> normal factory/Story Fact/SaveGate -> original heat ability.
## Earlier Director rules and PLAYER observation pose are explicit QA fixtures.
const MAIN=preload("res://scenes/v3/main.tscn")
const Adapter=preload("res://scripts/v3/gameplay/twin_canal_session.gd")
const Proof=preload("res://scripts/v3/gameplay/twin_canal_preparation_proof.gd")
const Ledger=preload("res://scripts/v3/gameplay/twin_i2_result_ledger.gd")
const Store=preload("res://scripts/v3/core/twin_world_store.gd")
const SOURCE="res://tests_v3/candidates/canal_session/evidence/local_cooling_20261020_224906_9bca43/result.json"
const SHA="8731ae899aadc871659624fcca56c02c92dacb150011df6d472a111476499a38"
const OBJECTIVE="I2:canal_service:exchange"
const FACT="I2:canal_exchange_verified"
const C1=Adapter.Assembly.Runtime.CASSETTES[1]
class ErrorLogger extends Logger:
    var guard:=Mutex.new()
    var errors: Array=[]
    func _log_error(function: String,file: String,line: int,code: String,rationale: String,_notify: bool,kind: int,_trace: Array[ScriptBacktrace]) -> void:
        if kind==Logger.ERROR_TYPE_WARNING: return
        guard.lock()
        errors.append({"function":function,"file":file,"line":line,"code":code,"rationale":rationale})
        guard.unlock()
class Observer extends Node:
    var sample: Callable
    func _physics_process(_delta: float) -> void:
        if sample.is_valid(): sample.call()
var logger:=ErrorLogger.new()
var session: Node
var observer: Observer
var profile: String=""
var output: String=""
var checks: Array=[]
var phases: Dictionary={}
var transitions: Array=[]
var fixture_receipts:=0
var finished:=false
var observed_generation: int=-1
var failed_fact: Dictionary={}
var atomic: Dictionary={}
var hot_save_result: Dictionary={}

func _initialize() -> void:
    OS.add_logger(logger)
    _run.call_deferred()

func _run() -> void:
    for arg: String in OS.get_cmdline_user_args():
        if arg.begins_with("--qa-profile="): profile=arg.trim_prefix("--qa-profile=")
        if arg.begins_with("--output="): output=arg.trim_prefix("--output=")
    if not profile.begins_with("qa_canal_preparation_story_") or profile!=profile.validate_filename() or DirAccess.dir_exists_absolute("user://profiles_v3/"+profile) or not output.begins_with("res://artifacts/v3/canal-preparation-story-") or ".." in output or DirAccess.dir_exists_absolute(output): quit(2); return
    DirAccess.make_dir_recursive_absolute(output)
    if not _check(FileAccess.get_sha256(SOURCE)==SHA,"pinned real successful cold A Store snapshot source"): _finish(); return
    var evidence: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(SOURCE))
    var original: Dictionary=evidence.snapshots.session_gate.saved
    if not _check(evidence.engine_errors.is_empty() and evidence.snapshots.session_gate.succeeded.ok and Adapter.ScanCheckpoint.validate(original).ok and Ledger._local_cooling_history(original,original.rules),"actual saved cold SCAN A validates; no successful endpoint manufactured"): _finish(); return
    phases["source"]={"path":SOURCE,"sha256":SHA,"selector":"snapshots.session_gate.saved","source_final_unrelated_fixture_failures":evidence.failures.size()}
    session=MAIN.instantiate()
    root.add_child(session)
    session.canal_runtime_enabled=true
    session.thermal_cargo.enabled=false
    if not _check(session.profile_ready and session.store.commit({"id":"qa-preparation-story-actual-A-location","set":{"world.region_id":"I2","world.environment.I2_canal":original}}).ok,"new private original Store imports only real A and explicit I2 start location, with no prior-Story fixture"): _finish(); return
    session.world_cache=session.store.snapshot()
    if not _check(session.start_flight("solo") and session.region_id=="I2" and session.canal!=null and session.world.build_errors.is_empty(),"normal MAIN factory builds actual I2/owned SCAN before earlier-rule receipts",_diagnostics()): _finish(); return
    session.inputs.test_enabled=true
    session.inputs.test_frame={"axes":{},"held":["brake"],"edges":[]}
    # Separate the <=30s post-construction actual physics bound from the
    # runner's <=45s whole process/cleanup bound.
    create_timer(30).timeout.connect(func():
        if not finished:
            _check(false,"30 second ordinary physical integration bound",_diagnostics())
            _finish())
    for unused in 300:
        await _frame()
        if finished: return
        if session.canal.ready and session.canal.exchange_fact()=="local_cooling": break
    if not _check(session.canal.ready and session.canal.exchange_fact()=="local_cooling" and int(_rules().get("jobs_completed",-1))==0,"ordinary factory/ticks reacquire actual current350ms cold support; source timers alone are not credit",_diagnostics()): _finish(); return
    var service_anchor: Dictionary=session.story.target_anchor("I2:canal_service_verified")
    if not _check(session.canal.module.status().ordered and service_anchor.get("anchor_id","")=="I2:canal_workbench_power","restored genuine SCAN order guides to bench power without asking for another carrier order",service_anchor): _finish(); return
    if not _fixture_to_exchange(): _finish(); return
    session.store.failure_point="before_publish"
    session.story.load_world()
    var before: Dictionary=session.store.snapshot()
    var before_story: Dictionary=session.story.state.duplicate(true)
    if not _check(_is_exchange_target() and session.story._fact(FACT)=="local_cooling" and not before.world.get("environment",{}).has("I2_canal_preparation"),"ordinary Story target is the exchange fact and no preparation seal exists before publication"): _finish(); return
    observer=Observer.new()
    observer.sample=_observe_original_tick
    root.add_child(observer) # Read only, after MAIN; no calls to any tick API.
    for unused in 180:
        await _frame()
        if finished: return
        if not failed_fact.is_empty(): break
    if not _check(not failed_fact.is_empty() and session.store.snapshot()==before and session.story.state==before_story and OBJECTIVE not in session.story.state.completed and not session.store.snapshot().world.environment.has("I2_canal_preparation"),"ordinary Story Fact/SaveGate failed original Store leaves objective and seal uncommitted",{"failure":failed_fact,"diagnostics":_diagnostics()}): _finish(); return
    phases["failed"]={"generation":before.generation,"fact_boundary":failed_fact,"story_unchanged":session.story.state==before_story}
    session.store.failure_point=""
    for unused in 180:
        await _frame()
        if finished: return
        if not atomic.is_empty(): break
    if not _check(not atomic.is_empty(),"ordinary Fact observer retries through the original SaveGate and commits the preparation",_diagnostics()): _finish(); return
    var disk: Dictionary=_read_disk()
    if disk.is_empty(): _finish(); return
    var saved_proof: Dictionary=disk.world.environment.get("I2_canal_preparation",{})
    var sealed: Dictionary=Proof.validate(saved_proof)
    var cold: Dictionary=disk.world.environment.I2_canal
    var atomic_ok: bool=OBJECTIVE in disk.world.actions.opening.completed and OBJECTIVE in disk.world.completed_objectives and disk.world.actions.opening.choices.get(OBJECTIVE)=="local_cooling" and sealed.get("ok",false) and sealed.get("envelope",{})==cold and Ledger._local_cooling_history(cold,cold.rules) and int(cold.rules.jobs_completed)==0 and int(cold.rules.service_credit)==0 and int(cold.rules.services_consumed)==0 and int(disk.generation)==int(atomic.generation)
    if not _check(atomic_ok,"one observed original Store generation contains the objective plus exact real cold checkpoint/preparation seal, without service/reward",{"observed_first_generation":atomic.generation,"disk_generation":disk.generation,"proof_validation":sealed.get("code"),"proof_sha256":saved_proof.get("sha256"),"same_once_decoded_envelope":sealed.get("envelope",{})==cold,"diagnostics":_diagnostics()}): _finish(); return
    phases["atomic"]={"generation":disk.generation,"proof":saved_proof,"current":cold,"story":disk.world.actions.opening}
    if not _check(_campaign_evidence(disk.world).ok,"original Ledger campaign evidence accepts actual exchange with its real seal"): _finish(); return
    if not await _near_c1(): _finish(); return
    if not _check(int(_rules().get("jobs_completed",-1))==0,"fixture is still before first-work receipt; reheat tests historical A rather than completed-work B",_diagnostics()): _finish(); return
    var heat_before: Dictionary=_rules()
    var ability_count: int=session.stats.abilities
    session._action_received(1,"ability",{"ability":"heat","target_id":C1,"mode":"heat"})
    await _frame()
    if finished: return
    var heated: Dictionary=_rules()
    var actual_heat: bool=session.stats.abilities==ability_count+1 and int(heated.get("command_serial",0))==int(heat_before.command_serial)+1 and int(heated.cassettes[C1].energy_mj)>25000000 and int(heated.jobs_completed)==0 and not Ledger._local_cooling_history(cold,heated)
    if not _check(actual_heat,"original nearby LOS heat ability legally reheats real C1 and invalidates current cold-A eligibility",{"before_rules":heat_before,"after_rules":heated,"diagnostics":_diagnostics()}): _finish(); return
    var requested: Dictionary=session.request_environment_save(func(result: Dictionary): hot_save_result=result.duplicate(true))
    if not _check(requested.ok,"original SaveGate accepts hot current-state save intent",requested): _finish(); return
    for unused in 120:
        await _frame()
        if finished: return
        if not hot_save_result.is_empty(): break
    if not _check(hot_save_result.get("ok",false) and hot_save_result.get("completed",false),"original SaveGate really publishes hot current state; capture restrictions must be reported without endpoint edits",{"result":hot_save_result,"diagnostics":_diagnostics()}): _finish(); return
    disk=_read_disk()
    if disk.is_empty(): _finish(); return
    var current: Dictionary=disk.world.environment.I2_canal
    var retained: Dictionary=disk.world.environment.I2_canal_preparation
    var validated: Dictionary=Proof.validate(retained)
    var campaign: Dictionary=_campaign_evidence(disk.world)
    if not _check(not Ledger._local_cooling_history(current,current.rules) and validated.ok and Ledger._local_cooling_history(validated.envelope,validated.envelope.rules) and retained==saved_proof and campaign.ok and disk.world.actions.opening.completed.count(OBJECTIVE)==1,"new original Store reader sees valid hot physical checkpoint plus the unchanged once-sealed earlier A; Ledger preserves the historical fact",{"campaign":campaign,"proof_sha256":retained.sha256,"current_kind":current.kind,"current_rules":current.rules,"diagnostics":_diagnostics()}): _finish(); return
    var no_proof: Dictionary=disk.world.duplicate(true)
    no_proof.environment.erase("I2_canal_preparation")
    _check(not _campaign_evidence(no_proof).ok,"same valid hot current checkpoint alone cannot impersonate the earlier preparation")
    var corrupt: Dictionary=disk.world.duplicate(true)
    corrupt.environment.I2_canal_preparation.sha256="0".repeat(64)
    _check(not _campaign_evidence(corrupt).ok,"corrupt historical proof still fails the original Ledger while current physics stays independently required")
    _check(disk.personal.discoveries==before.personal.discoveries and int(current.rules.service_credit)==0 and int(current.rules.services_consumed)==0,"preparation and legitimate reheat never create a calibration reward or claim a service")
    phases["hot_saved"]={"generation":disk.generation,"gate":hot_save_result,"current":current,"proof_sha256":retained.sha256,"campaign_evidence":campaign}
    _finish()

func _fixture_to_exchange() -> bool:
    var director=session.story.director
    var state: Dictionary=director.default_state()
    var found:=false
    for action: Dictionary in director.definitions().actions:
        for objective: Dictionary in action.objectives:
            if objective.id==OBJECTIVE: found=true; break
            var matcher: Dictionary=objective.events[0]
            var applied: Dictionary=director.apply_event(state,{"id":"qa-preparation-story-rule-prefix:"+str(objective.id),"type":matcher.type,"target_id":matcher.target_id,"option":matcher.options[0]},{"is_authority":true,"validated":true,"region_id":action.region_id})
            if not applied.get("ok",false) or not applied.get("changed",false): return _check(false,"explicit earlier Director rule receipt is legal",{"objective":objective.id,"code":applied.get("code")})
            state=applied.state
            fixture_receipts+=1
        if found: break
    if not _check(found and OBJECTIVE not in state.completed and "I2:canal_service:brief" in state.completed and director.validate_state(state).ok,"rule-only fixture stops before exchange AFTER real factory adoption; earlier facilities were not played",{"receipts":fixture_receipts}): return false
    var stored: Dictionary=session.store.commit({"id":"qa-preparation-story-earlier-rules-only","set":{"world.actions.opening":state}})
    if not _check(stored.ok,"earlier-rule fixture commits only after the real A site is active",stored): return false
    session.world_cache=session.store.snapshot()
    session.consensus.set_world_revision(int(session.world_cache.world_revision))
    return true

func _observe_original_tick() -> void:
    if finished: return
    var saved: Dictionary=session.store.snapshot()
    var done: bool=OBJECTIVE in saved.world.get("actions",{}).get("opening",{}).get("completed",[])
    var has_proof: bool=saved.world.get("environment",{}).has("I2_canal_preparation")
    if int(saved.generation)!=observed_generation:
        observed_generation=int(saved.generation)
        transitions.append({"frame":Engine.get_physics_frames(),"generation":saved.generation,"exchange_completed":done,"has_proof":has_proof,"gate":session.environment_save_gate.last_result.duplicate(true)})
    if atomic.is_empty() and done: atomic={"generation":saved.generation,"frame":Engine.get_physics_frames(),"has_proof":has_proof}
    var gate: Dictionary=session.environment_save_gate.last_result
    if failed_fact.is_empty() and session.store.failure_point=="before_publish" and gate.get("completed",false) and not gate.get("ok",true) and session.interface.message.text.contains("行动记录保存失败"):
        failed_fact={"generation":saved.generation,"frame":Engine.get_physics_frames(),"completed":done,"has_proof":has_proof,"gate":gate.duplicate(true),"message":session.interface.message.text,"store_notice":session.store.notice}

func _near_c1() -> bool:
    var target: Node3D=session.world.objects[C1]
    var actor: FlightBodyV2=session.players[1]
    var at: Vector3=target.global_position+Vector3.UP*3.4
    var envelope: CollisionShape3D=actor.get_node("Envelope") as CollisionShape3D
    var query:=PhysicsShapeQueryParameters3D.new()
    query.shape=envelope.shape
    query.transform=Transform3D(Basis.IDENTITY,at)*envelope.transform
    query.collision_mask=1|2|8|32
    query.exclude=[actor.get_rid()]
    if not _check(session.world.get_world_3d().direct_space_state.intersect_shape(query,1).is_empty() and session._line_clear(at,target.global_position,actor.get_rid(),C1),"explicit PLAYER-only QA heat observation pose has actual full hull clearance/range/LOS",at): return false
    actor.freeze=true
    actor.global_transform=Transform3D(Basis.IDENTITY,at)
    actor.force_update_transform()
    PhysicsServer3D.body_set_state(actor.get_rid(),PhysicsServer3D.BODY_STATE_TRANSFORM,actor.global_transform)
    actor.linear_velocity=Vector3.ZERO
    actor.angular_velocity=Vector3.ZERO
    actor.hold_height=at.y
    await _frame()
    return not finished

func _campaign_evidence(world: Dictionary) -> Dictionary:
    var completed: Dictionary={}
    for id: String in world.get("actions",{}).get("opening",{}).get("completed",[]): completed[id]=true
    return Ledger._campaign_evidence(world,completed,world.get("actions",{}).get("opening",{}).get("choices",{}))

func _is_exchange_target() -> bool:
    for target: Dictionary in session.story.current_targets():
        if target.type=="fact" and target.target_id==FACT: return true
    return false

func _rules() -> Dictionary:
    var ctx: Dictionary=session.canal.context() if is_instance_valid(session) and session.canal!=null else {}
    var rules: Variant=ctx.get("rules")
    return rules.snapshot() if rules!=null else {}

func _read_disk() -> Dictionary:
    var reader=Store.new(session.store.root_path)
    var opened: Dictionary=reader.load_profile()
    if not _check(opened.ok,"independent original Store reader opens the current generation",opened): return {}
    return reader.snapshot()

func _frame() -> void:
    await physics_frame
    await process_frame # Observe; original MAIN owns its one real tick.

func _diagnostics() -> Dictionary:
    if not is_instance_valid(session): return {"session":"not_installed"}
    var ctx: Dictionary=session.canal.context() if session.canal!=null else {}
    var bench: Variant=ctx.get("workbench")
    return {"active":session.active,"region":session.region_id,"message":session.interface.message.text,"generation":session.store.snapshot().generation,"story":session.story.state.duplicate(true),"targets":session.story.current_targets(),"rules":_rules(),"adapter":session.canal.status() if session.canal!=null else {},"assembly":session.canal.module.status(true) if session.canal!=null and is_instance_valid(session.canal.module) else {},"workbench":bench.report() if is_instance_valid(bench) else {},"gate":session.environment_save_gate.last_result.duplicate(true),"gate_pending":session.environment_save_gate.pending(),"last_commit_result":session.last_commit_result.duplicate(true),"store_notice":session.store.notice,"atomic":atomic,"failed_fact":failed_fact,"hot_save_result":hot_save_result}

func _check(ok: bool,label: String,detail: Variant=null) -> bool:
    checks.append({"passed":ok,"label":label,"detail":detail})
    return ok

func _finish() -> void:
    if finished: return
    finished=true
    var failures: Array=checks.filter(func(row: Dictionary): return not row.passed)
    var report: Dictionary={"checks":checks,"failures":failures,"engine_errors":logger.errors,"phases":phases,"generation_transitions":transitions,"fixture_receipts":fixture_receipts,"diagnostics":_diagnostics(),"scope":"Actual MAIN normal factory first adopts exact pinned real cold SCAN A in empty isolated QA I2 and reacquires fresh physical350ms support, then explicitly imports prior Director RULE receipts only. Ordinary Story.observe Fact/SaveGate failed Store and normal retry publish objective/cold physical checkpoint/original proof in the same generation. Original nearby heat Ability reheats real C1; original Gate must publish actual current checkpoint while original Ledger campaign evidence retains historical proof, with missing/corrupt proof negatives and independent Store reader. No scan replay, manufactured successful endpoint, direct physical/thermal/clock mutation or second persistence implementation. PLAYER heat observation pose is explicit QA. Fake prior rule prefix supplies no original four-facility physical history: never a whole Registry/fresh-MAIN/cross-region profile validity claim. No graphics/performance/LAN/full-game acceptance."}
    FileAccess.open(output+"/result.json",FileAccess.WRITE).store_string(JSON.stringify(report,"\t",true,true))
    print("CANAL_PREPARATION_STORY_RESULT ",JSON.stringify({"checks":checks.size(),"failures":failures,"engine_errors":logger.errors,"atomic_generation":atomic.get("generation"),"hot_save":hot_save_result,"diagnostics":report.diagnostics}))
    if is_instance_valid(observer): observer.free()
    if is_instance_valid(session):
        session.store.failure_point=""
        session.environment_save_gate.cancel("qa_preparation_story_teardown")
        if session.canal!=null: session.canal.clear()
        session.network.close()
        session.free()
        session=null
    await process_frame
    await physics_frame
    await process_frame
    quit(0 if failures.is_empty() and logger.errors.is_empty() else 1)
