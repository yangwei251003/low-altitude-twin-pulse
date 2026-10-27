extends SceneTree
## Native startup capture only. Direct I2 load is an explicit QA observation,
## not a naturally unlocked route. No Store patch, pose/clock change or manual tick.
const MAIN = preload("res://scenes/v3/main.tscn")
const Canal = preload("res://scripts/v3/gameplay/twin_canal_session.gd")
const Startup = Canal.StartupCheckpoint
const Safe = Canal.WaitCheckpoint.Safe
const OLD_LAYOUT := "2b3614b9f1dcb9723ceb04d466d74ec053e69cebff89a1a4d038ea4d5a90e7d5"

class ErrorLogger extends Logger:
    var guard := Mutex.new()
    var errors: Array = []
    func _log_error(function: String,file: String,line: int,code: String,rationale: String,_notify: bool,kind: int,_trace: Array[ScriptBacktrace]) -> void:
        if kind == Logger.ERROR_TYPE_WARNING: return
        guard.lock()
        errors.append({"function":function,"file":file,"line":line,"code":code,"rationale":rationale})
        guard.unlock()

var logger := ErrorLogger.new()
var session: Node
var profile := ""
var output := ""
var finished := false
var checks: Array = []
var callbacks: Array = []
var capture: Dictionary = {}
var validations: Dictionary = {}
var baseline_store: Dictionary = {}
var diagnostics: Dictionary = {}

func _initialize() -> void:
    OS.add_logger(logger)
    _run.call_deferred()

func _run() -> void:
    for arg: String in OS.get_cmdline_user_args():
        if arg.begins_with("--qa-profile="): profile = arg.trim_prefix("--qa-profile=")
        if arg.begins_with("--output="): output = arg.trim_prefix("--output=")
    if not profile.begins_with("qa_canal_startup_layout_") or profile != profile.validate_filename() or DirAccess.dir_exists_absolute("user://profiles_v3/"+profile) or not output.begins_with("res://artifacts/v3/canal-startup-layout-") or ".." in output or DirAccess.dir_exists_absolute(output):
        quit(2)
        return
    DirAccess.make_dir_recursive_absolute(output)
    create_timer(25.0).timeout.connect(func():
        if not finished:
            _check(false,"25 second native bootstrap capture bound",_status())
            _finish())
    session = MAIN.instantiate()
    root.add_child(session)
    if not _check(session.profile_ready and session.start_flight("solo") and session.region_id=="I1","fresh ordinary QA MAIN starts its default I1",_status()): _finish(); return
    # Ordinary brake input only; no player or cargo observation repositioning.
    session.inputs.test_enabled = true
    session.inputs.test_frame = {"axes":{},"held":["brake"],"edges":[]}
    for unused in 3:
        await physics_frame
        await process_frame
        if finished: return
    if not _check(session._load_region("I2") and session.region_id=="I2" and session.canal!=null,"original factory constructs actual I2 bootstrap with no Story prefix",_status()): _finish(); return
    baseline_store = session.store.snapshot()
    # ORIGINAL gate is polled by Session after its ordinary canal.advance.
    # Our operation only observes the SAME capture entry used by _save_environment.
    var request: Dictionary = session.environment_save_gate.request(_observe_boundary,func(result: Dictionary): callbacks.append(result.duplicate(true)))
    if not _check(request.get("ok",false),"original SaveGate accepts read-only startup capture operation",request): _finish(); return
    for unused in 18:
        await physics_frame
        await process_frame
        if finished: return
        if not callbacks.is_empty(): break
    _check(callbacks.size()==1 and callbacks[0].get("ok",false) and callbacks[0].get("completed",false) and not session.environment_save_gate.pending(),"one original same-physics-boundary capture callback completes",{"callbacks":callbacks,"gate":session.environment_save_gate.last_result,"status":_status()})
    _check(session.store.snapshot()==baseline_store,"pure capture and compatibility validation leave the complete original Store unchanged",{"before_generation":baseline_store.get("generation"),"after_generation":session.store.snapshot().get("generation")})
    if capture.get("ok",false) and capture.get("envelope") is Dictionary:
        var source: Dictionary = capture.envelope
        _check(source.get("kind")==Startup.KIND and source.get("mode")=="bootstrap" and source.get("rules") is Dictionary and source.rules.is_empty(),"source is actual native Bootstrap with genuinely absent Rules",{"kind":source.get("kind"),"mode":source.get("mode"),"rules":source.get("rules"),"controller":source.get("controller"),"diagnostics":diagnostics})
        _check(validations.get("current",{}).get("ok",false),"unmodified native current-layout envelope passes complete Startup.validate",validations.get("current",{}))
        _check(validations.get("legacy",{}).get("ok",false),"only-old-hash copy passes the same complete Startup.validate",validations.get("legacy",{}))
        _check(not validations.get("unknown",{}).get("ok",true),"unknown layout remains rejected by complete Startup.validate",validations.get("unknown",{}))
    else:
        _check(false,"original native startup capture succeeded",capture)
    _finish()

func _observe_boundary() -> bool:
    diagnostics = _status()
    capture = session._canal_persistence()
    if not capture.get("ok",false) or not capture.get("envelope") is Dictionary: return false
    var source: Dictionary = capture.envelope
    if source.get("kind")!=Startup.KIND or source.get("mode")!="bootstrap" or not source.get("rules") is Dictionary or not source.rules.is_empty(): return false
    # No await, simulation step, JSON roundtrip or mutation of source between
    # capture and all validation queries. Only a deep COPY's hash is replaced.
    var before: Dictionary = source.duplicate(true)
    var legacy: Dictionary = source.duplicate(true)
    legacy.layout_sha256 = OLD_LAYOUT
    var unknown: Dictionary = source.duplicate(true)
    unknown.layout_sha256 = "0".repeat(64)
    validations = {"current":Startup.validate(source),"legacy":Startup.validate(legacy),"unknown":Startup.validate(unknown)}
    var restored_copy: Dictionary = legacy.duplicate(true)
    restored_copy.layout_sha256 = source.layout_sha256
    _check(source.layout_sha256==Safe.layout_fingerprint() and source.layout_sha256!=OLD_LAYOUT and Safe.layout_fingerprint(true)==OLD_LAYOUT,"source uses new layout and exact counterfactual legacy layout still matches pinned old SHA",{"current":source.layout_sha256,"counterfactual_old":Safe.layout_fingerprint(true),"source_frame":source.source_frame,"observed_frame":Engine.get_physics_frames()})
    _check(source==before and restored_copy==source and source.source_frame==Engine.get_physics_frames(),"pure compatibility query changes only the copy's layout hash and grants no new physics frame or module state")
    return true

func _status() -> Dictionary:
    if not is_instance_valid(session): return {}
    var detail: Dictionary = session.canal.module.bootstrap.report() if session.canal!=null and is_instance_valid(session.canal.module) else {}
    return {"active":session.active,"region":session.region_id,"physics_frame":Engine.get_physics_frames(),"profile":profile,"profile_root":session.store.root_path,"generation":session.store.snapshot().generation,"canal":session.canal.status() if session.canal!=null else {},"bootstrap":detail,"build_errors":session.world.build_errors if is_instance_valid(session.world) else [],"message":session.interface.message.text}

func _check(ok: bool,label: String,actual: Variant=null) -> bool:
    checks.append({"passed":ok,"label":label,"actual":actual})
    return ok

func _finish() -> void:
    if finished: return
    finished = true
    var final_status: Dictionary = _status()
    if is_instance_valid(session):
        session.environment_save_gate.cancel("qa_startup_layout_teardown")
        session.active = false
        session.audio.shutdown()
        session.network.close()
        var deadline: int = Time.get_ticks_usec()+1000000
        while not session.audio.shutdown_status().ready and Time.get_ticks_usec()<deadline:
            await process_frame
        _check(session.audio.shutdown_status().ready,"QA terminal audio references drain on ordinary main frames",session.audio.shutdown_status())
        session.thermal_cargo.clear()
        if session.canal!=null: session.canal.clear()
        session.free()
        session = null
    await process_frame
    await physics_frame
    await process_frame
    var failures: Array = checks.filter(func(row: Dictionary): return not row.passed)
    var report: Dictionary = {"checks":checks,"failures":failures,"engine_errors":logger.errors,"capture":capture,"validations":validations,"callbacks":callbacks,"final_status":final_status,"scope":"Source MAIN isolated fresh QA, default I1 then declared direct I2 observation. Original Session physics and SaveGate invoke original _canal_persistence; actual bootstrap/rules-absent envelope, current full validator and pure deep-copy legacy-hash compatibility only. No profile patch, Store transaction, Story prefix, body/clock modification, synthetic WAIT-to-Startup conversion, manual advance or native restoration claim. Terminal audio drain is QA cleanup, not normal gameplay exit acceptance."}
    var file := FileAccess.open(output+"/result.json",FileAccess.WRITE)
    if file==null: quit(2); return
    file.store_string(JSON.stringify(report,"\t",true,true))
    file.close()
    print("CANAL_STARTUP_LAYOUT_RESULT "+JSON.stringify({"checks":checks.size(),"failures":failures,"engine_errors":logger.errors,"validations":validations}))
    quit(0 if failures.is_empty() and logger.errors.is_empty() else 1)
