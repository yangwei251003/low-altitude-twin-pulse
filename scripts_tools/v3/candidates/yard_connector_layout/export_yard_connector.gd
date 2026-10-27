extends SceneTree
## Later authorized headless invocation only. Never installs the proposed paving.
const World = preload("res://scripts/v3/twin_test_world.gd")
const Geometry = preload("res://scripts_tools/v3/candidates/yard_connector_layout/yard_connector_geometry.gd")
const CONTRACT := "res://scripts_tools/v3/candidates/yard_connector_layout/input_contract.json"
const BASE := "res://scripts_tools/v3/candidates/yard_connector_layout/exports"
var output := ""
var world: Node3D
var viewport: SubViewport
var done := false
class ErrorLog extends Logger:
    var errors: Array = []
    func _log_error(fn: String,file: String,line: int,code: String,reason: String,_notify: bool,kind: int,_traces: Array[ScriptBacktrace]) -> void:
        errors.append({"function":fn,"file":file,"line":line,"code":code,"reason":reason,"kind":kind})
var logger := ErrorLog.new()

func _initialize() -> void:
    OS.add_logger(logger)
    _run.call_deferred()

func _run() -> void:
    create_timer(45).timeout.connect(func():
        if not done: _finish({"ok":false,"code":"45_second_export_timeout"}))
    for arg: String in OS.get_cmdline_user_args():
        if arg.begins_with("--output="): output=arg.trim_prefix("--output=")
    var base: String = ProjectSettings.globalize_path(BASE).replace("\\","/").simplify_path()
    output=ProjectSettings.globalize_path(output).replace("\\","/").simplify_path()
    if DisplayServer.get_name()!="headless" or output.get_base_dir()!=base or output.get_file().is_empty() or DirAccess.dir_exists_absolute(output) or FileAccess.file_exists(output):
        _finish({"ok":false,"code":"new_explicit_export_child_directory_required"}); return
    var contract: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(CONTRACT))
    var before: Dictionary = _hashes(contract.geometry_inputs_sha256)
    if before!=contract.geometry_inputs_sha256:
        _finish({"ok":false,"code":"production_geometry_changed_review_contract","actual":before}); return
    viewport=SubViewport.new()
    viewport.world_3d=World3D.new()
    viewport.render_target_update_mode=SubViewport.UPDATE_DISABLED
    root.add_child(viewport)
    world=World.new()
    viewport.add_child(world) # Match actual World lifecycle; no detached bind calls.
    world.build("I2",{},true)
    var prepared: Dictionary = Geometry.collect(world)
    if not prepared.ok: _finish(prepared); return
    if not logger.errors.is_empty(): _finish({"ok":false,"code":"engine_error","errors":logger.errors}); return
    var after: Dictionary = _hashes(contract.geometry_inputs_sha256)
    if before!=after: _finish({"ok":false,"code":"input_changed"}); return
    if DirAccess.make_dir_recursive_absolute(output)!=OK: _finish({"ok":false,"code":"mkdir"}); return
    var groups: Dictionary = {}
    for name: String in ["source","visible","remainder","under_structures"]:
        var row: Dictionary = _write_geometry(name,prepared[name])
        if not row.ok: _finish(row); return
        groups[name]=row
    var result: Dictionary = {"ok":true,"schema_version":1,"kind":"actual_final_i2_yard_connector_input","engine":Engine.get_version_info(),
        "rect_xz":[-24,10.5,36.6,17.5],"godot_origin":[-5.7,0,19.25],"coordinates":"world Godot X/Y-up/Z metres; all visible vertices exactly Y0",
        "source_method":"surface_get_arrays; no Mesh.get_faces/BVH quantization","groups":groups,"report":_json_value(prepared.report),
        "geometry_input_sha256_before":before,"geometry_input_sha256_after":after,"contract_sha256":FileAccess.get_sha256(CONTRACT),
        "tool_sha256":{"geometry":FileAccess.get_sha256("res://scripts_tools/v3/candidates/yard_connector_layout/yard_connector_geometry.gd"),"exporter":FileAccess.get_sha256(get_script().resource_path)},
        "scope":"read-only actual World build; no scene/mesh/collision replacement, no gameplay or art verdict"}
    if not _json_file("geometry.json",result): _finish({"ok":false,"code":"manifest_write"}); return
    _finish({"ok":true,"code":"actual_final_geometry_exported","output":output,"report":result.report,"manifest_sha256":FileAccess.get_sha256(output.path_join("geometry.json"))})

func _write_geometry(name: String,data: Dictionary) -> Dictionary:
    var files: Dictionary = {}
    for key: String in ["faces","normals","uv","tangents"]:
        if not data.has(key): continue
        var bytes: PackedByteArray = data[key].to_byte_array()
        var filename: String = name+"."+key+".f32le"
        var file := FileAccess.open(output.path_join(filename),FileAccess.WRITE)
        if file==null: return {"ok":false,"code":"binary_open:"+filename}
        file.store_buffer(bytes); file.flush()
        var error: Error = file.get_error()
        file.close()
        if error!=OK: return {"ok":false,"code":"binary_write:"+filename}
        files[key]={"file":filename,"bytes":bytes.size(),"sha256":FileAccess.get_sha256(output.path_join(filename))}
    var ids: Array = []
    if data.has("source_triangles"):
        for id: int in data.source_triangles: ids.append(id)
    else:
        for id in int(data.faces.size()/3): ids.append(id)
    return {"ok":true,"vertex_count":data.faces.size(),"triangle_count":data.faces.size()/3,"source_final_triangle_ids":ids,"files":files}

func _json_file(name: String,value: Variant) -> bool:
    var file := FileAccess.open(output.path_join(name),FileAccess.WRITE)
    if file==null: return false
    file.store_string(JSON.stringify(value,"  ",true,true)); file.flush()
    var error: Error = file.get_error(); file.close()
    return error==OK

static func _hashes(expected: Dictionary) -> Dictionary:
    var result: Dictionary = {}
    for path: String in expected: result[path]=FileAccess.get_sha256("res://"+path)
    return result

static func _json_value(value: Variant) -> Variant:
    if value is Vector3: return [value.x,value.y,value.z]
    if value is Rect2: return [value.position.x,value.position.y,value.size.x,value.size.y]
    if value is Dictionary:
        var result: Dictionary = {}
        for key: Variant in value: result[key]=_json_value(value[key])
        return result
    if value is Array:
        var result: Array = []
        for item: Variant in value: result.append(_json_value(item))
        return result
    return value

func _finish(result: Dictionary) -> void:
    if done: return
    done=true
    result.engine_errors=logger.errors.duplicate(true)
    if not logger.errors.is_empty(): result.ok=false
    print("I2_YARD_CONNECTOR_EXPORT "+JSON.stringify(result))
    if is_instance_valid(viewport): viewport.free()
    quit(0 if result.get("ok",false) else 1)
