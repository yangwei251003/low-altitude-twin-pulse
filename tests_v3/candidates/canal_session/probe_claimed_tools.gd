extends SceneTree
## Eight ordinary physics observations of the exact real Story-committed claim.
## No replay, pose write, manual physics step, or substituted tool geometry.
const MAIN=preload("res://scenes/v3/main.tscn")
const Restore=preload("res://scripts/v3/candidates/canal_checkpoint/canal_progress_restore.gd")
const SOURCE="res://artifacts/v3/canal-story-20261020_231707_c3f674/result.json"
const SHA="dde4d072978edad1bd97b599f9c5aff5a55dc251e43829347edb61ef1f3c5bdc"
class Errors extends Logger:
    var rows: Array=[]
    func _log_error(function: String,file: String,line: int,code: String,rationale: String,_notify: bool,kind: int,_trace: Array[ScriptBacktrace]) -> void:
        if kind!=Logger.ERROR_TYPE_WARNING: rows.append({"function":function,"file":file,"line":line,"code":code,"rationale":rationale})
class Observer extends Node:
    var sample: Callable
    func _physics_process(_delta: float) -> void:
        if sample.is_valid(): sample.call()
var logger:=Errors.new()
var session: Node
var observer: Observer
var restorer:=Restore.new()
var saved: Dictionary={}
var checks: Array=[]
var trace: Array=[]
var profile: String=""
var output: String=""
var finished:=false
var adopted_site: Node3D

func _initialize() -> void:
    OS.add_logger(logger)
    _run.call_deferred()

func _run() -> void:
    for arg: String in OS.get_cmdline_user_args():
        if arg.begins_with("--qa-profile="): profile=arg.trim_prefix("--qa-profile=")
        if arg.begins_with("--output="): output=arg.trim_prefix("--output=")
    if not profile.begins_with("qa_canal_claimed_tools_") or profile!=profile.validate_filename() or DirAccess.dir_exists_absolute("user://profiles_v3/"+profile) or not output.begins_with("res://artifacts/v3/canal-claimed-tools-") or ".." in output or DirAccess.dir_exists_absolute(output): quit(2); return
    DirAccess.make_dir_recursive_absolute(output)
    if not _check(FileAccess.get_sha256(SOURCE)==SHA,"exact actual original Story atomic claimed envelope source"): _finish(); return
    saved=JSON.parse_string(FileAccess.get_file_as_string(SOURCE)).phases.atomic.envelope
    if not _check(Restore.Progress.validate(saved).ok and saved.rules.services_consumed==1 and saved.rules.service_serial==1,"actual claimed progress validates without manufacturing endpoint"): _finish(); return
    session=MAIN.instantiate()
    root.add_child(session)
    session.canal_runtime_enabled=false
    if not _check(session.profile_ready and session.store.commit({"id":"qa-claimed-tools-location-only","set":{"world.region_id":"I2"}}).ok,"fresh private original Store location fixture only"): _finish(); return
    session.world_cache=session.store.snapshot()
    if not _check(session.start_flight("solo") and session.region_id=="I2" and session.world.build_errors.is_empty(),"ordinary MAIN factory constructs actual empty I2 directly"): _finish(); return
    var prepared: Dictionary=restorer.prepare(session.world,saved,Callable(session.world,"sample_environment"),true)
    if not _check(prepared.ok,"original Restorer creates new frozen claimed subtree",prepared): _finish(); return
    # The wall timer starts only after construction. Eight ordinary physics
    # callbacks, rather than process/physics awaits that can skip engine frames.
    create_timer(3).timeout.connect(func():
        if not finished:
            _check(false,"three second post-construction physical observation bound",restorer.report())
            _finish())
    observer=Observer.new()
    observer.sample=_observe
    root.add_child(observer)

func _observe() -> void:
    if finished: return
    var integrity: Dictionary=restorer._frozen_integrity() # Pure readback only.
    trace.append({"physics_frame":Engine.get_physics_frames(),"integrity":integrity,"report":restorer.report()})
    if trace.size()<8: return
    observer.set_physics_process(false)
    var consecutive: bool=true
    for i: int in range(1,trace.size()): consecutive=consecutive and int(trace[i].physics_frame)==int(trace[i-1].physics_frame)+1
    _check(consecutive,"eight consecutive ordinary physical frame readbacks",trace.map(func(row: Dictionary): return row.physics_frame))
    if not _check(integrity.ok,"exact frozen body/joint/tool native integrity within eight original physics steps",trace.back()): _finish(); return
    var tick: Dictionary=restorer.tick(1.0/60.0,true,false)
    if not _check(tick.ok and tick.ready,"unchanged original Restorer tick authorizes current-frame adoption",tick): _finish(); return
    var adopted: Dictionary=restorer.adopt(true)
    if not _check(adopted.ok,"unchanged original Restorer adopts exact claimed subtree",adopted): _finish(); return
    adopted_site=adopted.site
    _check(Restore.Rules._same(adopted.context.rules.snapshot(),saved.rules) and adopted.executor._waiting_for_beneficiary,"restore adds no clock, receipt, reward, service credit or job")
    _finish()

func _check(ok: bool,label: String,actual: Variant=null) -> bool:
    checks.append({"passed":ok,"label":label,"actual":actual})
    return ok

func _finish() -> void:
    if finished: return
    finished=true
    var failures: Array=checks.filter(func(row: Dictionary): return not row.passed)
    var report: Dictionary={"checks":checks,"failures":failures,"engine_errors":logger.rows,"source":SOURCE,"source_sha256":SHA,"trace":trace,"final":restorer.report(),"scope":"Diagnostic only: exact actually committed Story claimed envelope in new original frozen subtree in ordinary MAIN empty I2. Eight consecutive normal physics readbacks (<3s), then unchanged original tick/adopt gate. No tool pose/native state writes, replay, fake prior facility history, full campaign/profile validity, manual physics or support credit."}
    FileAccess.open(output+"/result.json",FileAccess.WRITE).store_string(JSON.stringify(report,"\t",true,true))
    print("CANAL_CLAIMED_TOOLS ",JSON.stringify({"checks":checks.size(),"failures":failures,"engine_errors":logger.rows}))
    if is_instance_valid(observer): observer.free()
    if is_instance_valid(adopted_site): adopted_site.free()
    else: restorer.discard()
    if is_instance_valid(session):
        session.environment_save_gate.cancel("qa_claimed_tools_teardown")
        session.network.close()
        session.free()
    quit(0 if failures.is_empty() and logger.rows.is_empty() else 1)
