extends SceneTree
## Source MAIN CPU attribution only: no rendering/FPS, affinity or route proof.
const MAIN = preload("res://scenes/v3/main.tscn")
const Store = preload("res://scripts/v3/core/twin_world_store.gd")
const SAMPLE_USEC := 10000000

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
var checks: Array = []
var phases: Dictionary = {}
var totals: Dictionary = {}
var sorted_rows: Array = []
var save_callbacks: Array = []
var save_report: Dictionary = {}
var finished := false
var began_usec := 0
var sample_started_usec := 0
var sample_elapsed_usec := 0
var sample_first_frame := -1
var sample_last_frame := -1
var sample_complete := false

func _initialize() -> void:
    OS.add_logger(logger)
    _run.call_deferred()

func _run() -> void:
    for arg: String in OS.get_cmdline_user_args():
        if arg.begins_with("--qa-profile="): profile = arg.trim_prefix("--qa-profile=")
        if arg.begins_with("--output="): output = arg.trim_prefix("--output=")
    if not profile.begins_with("qa_cpu_i2_") or profile != profile.validate_filename() or DirAccess.dir_exists_absolute("user://profiles_v3/"+profile) or not output.begins_with("res://artifacts/v3/i2-cpu-") or ".." in output or DirAccess.dir_exists_absolute(output):
        quit(2)
        return
    began_usec = Time.get_ticks_usec()
    DirAccess.make_dir_recursive_absolute(output)
    create_timer(70.0).timeout.connect(func():
        if not finished:
            _check(false,"70 second total MAIN warmup/sample/save bound; owned runner80s",_status())
            _finish())
    session = MAIN.instantiate()
    root.add_child(session)
    if not _check(session.profile_ready and session.has_method("_qa_cpu_begin") and session.has_method("_qa_cpu_end") and session.get("qa_cpu_totals") is Dictionary,"ordinary new QA MAIN exposes the Root-owned optional CPU observer API",_status()): _finish(); return
    if not _check(not session.qa_cpu_enabled,"CPU instrumentation is disabled by default",session.qa_cpu_totals.duplicate(true)): _finish(); return
    # Match the observed package path: ordinary fresh I1, then an explicit QA
    # direct I2 factory load. No Store starting-region or predecessor fixture.
    if not _check(session.start_flight("solo") and session.region_id=="I1","ordinary new profile first starts its default I1 world",_status()): _finish(); return
    session.inputs.test_enabled = true
    session.inputs.test_frame = {"axes":{},"held":["brake"],"edges":[]}
    for unused in 3:
        if not await _frame(): return
    phases["initial_i1"] = _status()
    if not _check(session._load_region("I2") and session.region_id=="I2" and session.canal!=null and session.world.build_errors.is_empty(),"after three ordinary I1 frames, explicit QA load builds default I2 with no Story prefix",_status()): _finish(); return
    phases["constructed"] = _status()
    var ready := false
    var last_ready_status_usec: int = began_usec
    while Time.get_ticks_usec()-began_usec < 50000000:
        if not await _frame(): return
        if Time.get_ticks_usec()-last_ready_status_usec>=8000000:
            last_ready_status_usec = Time.get_ticks_usec()
            var current: Dictionary = _status()
            var bootstrap: Dictionary = current.get("canal_bootstrap",{})
            var controller: Dictionary = bootstrap.get("controller",{})
            print("I2_CPU_WARMUP ",JSON.stringify({"wall_seconds":float(last_ready_status_usec-began_usec)/1000000.0,"physics_frame":Engine.get_physics_frames(),"phase":bootstrap.get("phase",""),"code":bootstrap.get("code",""),"ticks":bootstrap.get("ticks",0),"controller_serial":controller.get("serial",0),"distance_m":controller.get("distance_m",null),"speed_mps":controller.get("speed_mps",null),"canal_ready":current.get("canal_ready",false),"facilities_ready":current.get("facilities_ready",false)}))
        if session.active and session.canal!=null and session.canal.ready and session._facilities_ready() and not session.environment_save_gate.pending(): ready=true; break
    if not _check(ready,"default Canal bootstrap and all facilities become ready on ordinary physics before sampling",_status()): _finish(); return
    var initial_order: Dictionary=session.canal.module.status()
    var service_anchor: Dictionary=session.story.target_anchor("I2:canal_service_verified")
    if not _check(not initial_order.ordered and service_anchor.get("anchor_id","")=="I2:canal_carrier" and "0" in str(service_anchor.get("label","")),"fresh ready Canal service guidance points to the real carrier order before bench power",{"order":initial_order,"anchor":service_anchor}): _finish(); return
    phases["sample_start"] = _status()
    phases["resources_start"] = _resources()
    sample_first_frame = Engine.get_physics_frames()
    sample_started_usec = Time.get_ticks_usec()
    session.qa_cpu_enabled = true
    session.trial.module.station.qa_cpu_owner = weakref(session)
    while Time.get_ticks_usec()-sample_started_usec < SAMPLE_USEC:
        if not await _frame(): return
    session.qa_cpu_enabled = false
    session.trial.module.station.qa_cpu_owner = null
    sample_elapsed_usec = Time.get_ticks_usec()-sample_started_usec
    sample_last_frame = Engine.get_physics_frames()
    totals = session.qa_cpu_totals.duplicate(true)
    sorted_rows = _sort_totals(totals)
    phases["sample_end"] = _status()
    phases["resources_end"] = _resources()
    sample_complete = _check(sample_elapsed_usec>=SAMPLE_USEC and sample_last_frame>sample_first_frame and not sorted_rows.is_empty() and _valid_totals(totals) and session.active and session.region_id=="I2" and session.canal.ready,"ten real seconds of unmodified ordinary I2 physics produce valid nonempty CPU counters",{"elapsed_usec":sample_elapsed_usec,"ordinary_physics_frames":sample_last_frame-sample_first_frame,"label_count":totals.size()})
    print("I2_CPU_TOP5 ",JSON.stringify(sorted_rows.slice(0,5)))
    if not sample_complete: _finish(); return
    # One normal save outside the timed CPU window, without replaying any I2
    # actions, altering module clocks, or hand-invoking a physics tick.
    var saved_at_usec: int = Time.get_ticks_usec()
    while Time.get_ticks_usec()-saved_at_usec < 2000000:
        if not session.environment_save_gate.pending(): break
        if not await _frame(): return
    var requested: Dictionary = session.request_environment_save(func(result: Dictionary): save_callbacks.append(result.duplicate(true)))
    if not _check(requested.get("ok",false),"after disabling CPU sampling, one original SaveGate save is requested",requested): _finish(); return
    while Time.get_ticks_usec()-saved_at_usec < 4000000:
        if not save_callbacks.is_empty(): break
        if not await _frame(): return
    var reader := Store.new(session.store.root_path)
    var loaded: Dictionary = reader.load_profile()
    var disk: Dictionary = reader.snapshot()
    save_report = {"requested":requested,"callbacks":save_callbacks,"wall_usec":Time.get_ticks_usec()-saved_at_usec,"reader":loaded,"generation":disk.generation,"canal_kind":disk.world.get("environment",{}).get("I2_canal",{}).get("kind",""),"outside_sample":not session.qa_cpu_enabled}
    _check(save_callbacks.size()==1 and save_callbacks[0].get("ok",false) and save_callbacks[0].get("completed",false) and loaded.get("ok",false) and disk==session.store.snapshot() and disk.world.get("environment",{}).get("I2_canal",{}) is Dictionary and not disk.world.get("environment",{}).get("I2_canal",{}).is_empty(),"one original post-sample save completes and an independent original Store reads its Canal state",save_report)
    _finish()

func _valid_totals(value: Dictionary) -> bool:
    for label: Variant in value:
        if not label is String or not value[label] is Dictionary: return false
        var row: Dictionary = value[label]
        for key: String in ["count","total_usec","max_usec"]:
            if not row.get(key) is int or row[key]<0: return false
        if row.count<1 or row.max_usec>row.total_usec: return false
    return true

func _sort_totals(value: Dictionary) -> Array:
    var rows: Array = []
    for label: Variant in value:
        if not value[label] is Dictionary: continue
        var row: Dictionary = value[label]
        var count: int = int(row.get("count",0))
        rows.append({"label":str(label),"count":count,"total_usec":row.get("total_usec",0),"max_usec":row.get("max_usec",0),"mean_usec":float(row.get("total_usec",0))/float(maxi(count,1)),"wall_window_percent":100.0*float(row.get("total_usec",0))/float(maxi(sample_elapsed_usec,1))})
    rows.sort_custom(func(a: Dictionary,b: Dictionary):
        if a.total_usec!=b.total_usec: return a.total_usec>b.total_usec
        return a.label<b.label)
    return rows

func _resources() -> Dictionary:
    return {"memory_static_bytes":Performance.get_monitor(Performance.MEMORY_STATIC),"memory_static_max_bytes":Performance.get_monitor(Performance.MEMORY_STATIC_MAX),"object_count":Performance.get_monitor(Performance.OBJECT_COUNT),"resource_count":Performance.get_monitor(Performance.OBJECT_RESOURCE_COUNT),"node_count":Performance.get_monitor(Performance.OBJECT_NODE_COUNT),"orphan_node_count":Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT),"last_process_seconds":Performance.get_monitor(Performance.TIME_PROCESS),"last_physics_process_seconds":Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS)}

func _status() -> Dictionary:
    if not is_instance_valid(session): return {"session":"not_constructed"}
    var state: Dictionary = session.store.snapshot()
    var canal: Dictionary = session.canal.status() if session.canal!=null else {}
    var bootstrap: Dictionary = session.canal.module.bootstrap.report() if session.canal!=null and is_instance_valid(session.canal.module) and session.canal.module.bootstrap!=null else {}
    return {"active":session.active,"mode":session.network.mode,"region":session.region_id,"profile":profile,"profile_id":state.profile_id,"profile_root":session.store.root_path,"session_id":session.network.session_id,"generation":state.generation,"physics_frame":Engine.get_physics_frames(),"paused":session.simulation_paused,"canal_ready":canal.get("ready",false),"canal_error":canal.get("error",""),"canal_assembly":canal.get("assembly",{}),"canal_bootstrap":bootstrap,"facilities_ready":session._facilities_ready() if is_instance_valid(session.world) else false,"story_ready":session.story.ready,"story_completed":session.story.state.get("completed",[]).duplicate(),"actions":session.stats.actions,"message":session.interface.message.text,"build_errors":session.world.build_errors if is_instance_valid(session.world) else []}

func _frame() -> bool:
    await physics_frame
    await process_frame
    return not finished

func _check(ok: bool,label: String,actual: Variant=null) -> bool:
    checks.append({"passed":ok,"label":label,"actual":actual})
    return ok

func _finish() -> void:
    if finished: return
    finished = true
    if is_instance_valid(session):
        session.qa_cpu_enabled = false
        if totals.is_empty() and session.get("qa_cpu_totals") is Dictionary: totals=session.qa_cpu_totals.duplicate(true)
    var status: Dictionary = _status()
    var resources: Dictionary = _resources()
    if is_instance_valid(session):
        session.environment_save_gate.cancel("qa_i2_cpu_teardown")
        session.thermal_cargo.clear()
        if session.canal!=null: session.canal.clear()
        session.network.close()
        session.free()
    session = null
    await process_frame
    await physics_frame
    await process_frame
    var failures: Array = checks.filter(func(row: Dictionary): return not row.passed)
    var report := {"checks":checks,"failures":failures,"engine_errors":logger.errors,"sample_complete":sample_complete,"sample":{"requested_usec":SAMPLE_USEC,"actual_usec":sample_elapsed_usec,"first_physics_frame":sample_first_frame,"last_physics_frame":sample_last_frame,"ordinary_physics_frames":maxi(0,sample_last_frame-sample_first_frame)},"cpu_totals":totals,"cpu_sorted":sorted_rows,"top5":sorted_rows.slice(0,5),"phases":phases,"post_sample_save":save_report,"status":status,"resources_final":resources,"runtime":{"engine":Engine.get_version_info(),"pid":OS.get_process_id(),"processor_name":OS.get_processor_name(),"processor_count":OS.get_processor_count(),"user_dir":OS.get_user_data_dir(),"debug_build":OS.is_debug_build(),"editor_feature":OS.has_feature("editor")},"wall_seconds":float(Time.get_ticks_usec()-began_usec)/1000000.0,"scope":"Headless source-MAIN CPU attribution with no affinity set. Unique empty QA profile; ordinary default I1 startup and three original physics/process frames, then explicit direct QA _load_region(I2) matching package observation; no Store start-region write or Story prefix. Original factory/default facilities and live Canal bootstrap; neutral/brake test input only. Ten real wall seconds after normal readiness, original physics/process ownership and clocks unchanged. Only Root-owned qa_cpu_enabled/qa_cpu_totals observer data is configured. Timings are inclusive measured scopes, may nest/overlap, must not be summed as exclusive CPU time/utilization; max is one instrumented call, not frame time. Physics frame count is an observation, not FPS or rendering/GPU/human comfort evidence. One original post-sample save/reader is outside timing. No prior I2 objectives, repeated route, module advance, geometry, ownership, physical endpoint or source-package parity claim."}
    FileAccess.open(output+"/result.json",FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
    print("I2_CPU_PROFILE_RESULT ",JSON.stringify({"checks":checks.size(),"failures":failures,"engine_errors":logger.errors,"sample":report.sample,"top5":report.top5,"wall_seconds":report.wall_seconds}))
    quit(0 if failures.is_empty() and logger.errors.is_empty() and sample_complete else 1)
