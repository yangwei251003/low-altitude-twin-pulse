extends SceneTree
## Short lifecycle regression: real Bootstrap to WAIT, then delete the owning
## Assembly WITHOUT close(). No work order, reward, player or saved fixture.
const World = preload("res://scripts/v3/twin_test_world.gd")
const Assembly = preload("res://scripts/v3/candidates/canal_assembly/canal_assembly.gd")
const DT := 1.0/60.0
var viewport: SubViewport
var world: Node3D
var assembly: Node3D
var checks := 0
var failures: Array = []
var output := ""
var finished := false
var ticks := 0
var exited_status: Dictionary = {}
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
            _check(false,"50s lifecycle bound",{"ticks":ticks})
            _finish())
    for script: Script in [World,Assembly]:
        if not _check(script.can_instantiate(),"real dependency parses",script.resource_path): _finish(); return
    _check(Engine.physics_ticks_per_second==60 and Engine.time_scale==1.0,"normal physics rate")
    viewport=SubViewport.new()
    viewport.world_3d=World3D.new()
    viewport.render_target_update_mode=SubViewport.UPDATE_DISABLED
    root.add_child(viewport)
    world=World.new()
    viewport.add_child(world)
    world.build("I2",{},true)
    if not _check(world.build_errors.is_empty(),"real caller-owned production I2",world.build_errors): _finish(); return
    for i in 3: await physics_frame
    var facilities: Dictionary=_facilities()
    assembly=Assembly.new()
    assembly.name="LifecycleAssembly"
    world.add_child(assembly)
    var configured: Dictionary=assembly.configure(world,world.sample_environment,true)
    if not _check(configured.ok,"same original physical factory",configured): _finish(); return
    for i in 2700:
        await physics_frame
        if finished: return
        ticks+=1
        world.clock_seconds+=DT
        var advanced: Dictionary=assembly.advance(DT,true,false)
        if not advanced.ok or not logger.errors.is_empty():
            _check(false,"real Bootstrap remains valid",{"result":advanced,"errors":logger.errors})
            _finish(); return
        if assembly.status().ready: break
    if not _check(assembly.status().ready,"real WAIT creates the actual Workbench/head before deletion",assembly.status(true)): _finish(); return
    var ctx: Dictionary=assembly.context()
    var original_rules: RefCounted=ctx.rules
    var ledger: Dictionary=original_rules.snapshot()
    var head: WeakRef=weakref(ctx.workbench.head)
    var carrier: WeakRef=weakref(ctx.carrier)
    var site: WeakRef=weakref(assembly.get_node("CanalTransportCandidateSite"))
    _check(ctx.workbench.head.is_inside_tree() and ctx.carrier.cargo_items.size()==1 and is_instance_valid(ctx.carrier.cargo_joint),"deletion exercises live tool and actual loaded PinJoint")
    _check(not assembly.status().closed and not assembly.status().ordered,"no explicit close or fabricated work before destruction")
    # tree_exited is after the children leave. status(true) must not ask their
    # global transforms; the actual free() below is the regression trigger.
    assembly.tree_exited.connect(func(): exited_status=assembly.status(true))
    assembly.free()
    _check(head.get_ref()==null and carrier.get_ref()==null and site.get_ref()==null,"owner free deletes only its live owned subtree")
    _check(exited_status.get("closed",false) and exited_status.get("details_unavailable","")=="owner_not_in_tree","late status is data-only, without descendant reports",exited_status)
    _check(original_rules.snapshot()==ledger,"abrupt deletion does not clear pending or fabricate a receipt")
    _check(_facilities()==facilities,"caller World and four original facility identities remain")
    await physics_frame
    _check(logger.errors.is_empty(),"no detached global-transform or physics errors",logger.errors)
    _finish()

func _facilities() -> Dictionary:
    var result: Dictionary={}
    for id: String in ["clinic","distribution","trial","shared_access"]:
        var node: Node3D=world.get(id)
        result[id]={"id":node.get_instance_id(),"space":node.get_world_3d().space,"pose":node.global_transform}
    return result

func _check(ok: bool,label: String,detail: Variant=null) -> bool:
    checks+=1
    if not ok: failures.append({"label":label,"details":detail})
    return ok

func _finish() -> void:
    if finished: return
    finished=true
    if is_instance_valid(viewport): viewport.free()
    var report: Dictionary={"checks":checks,"failures":failures,"engine_errors":logger.errors,"ticks":ticks,"exited_status":exited_status,"scope":"fresh actual Bootstrap/loaded carrier/Workbench, no-close owner destruction only; not a second full work run"}
    if not output.is_empty():
        var file:=FileAccess.open(output.path_join("result.json"),FileAccess.WRITE)
        if file!=null: file.store_string(JSON.stringify(report,"  ")); file.close()
        else: failures.append({"label":"result_write"})
    print("CANAL_ASSEMBLY_LIFECYCLE_RESULT "+JSON.stringify(report))
    quit(0 if failures.is_empty() and logger.errors.is_empty() else 1)
