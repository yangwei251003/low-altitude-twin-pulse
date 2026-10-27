extends SceneTree
## Read-only diagnosis of one isolated QA generation; never instantiates MAIN,
## writes the profile or advances physics/controllers.
const Progress=preload("res://scripts/v3/candidates/canal_checkpoint/canal_progress_checkpoint.gd")
var output: String=""

func _initialize() -> void:
    call_deferred("_run")

func _run() -> void:
    var source: String=""
    for arg: String in OS.get_cmdline_user_args():
        if arg.begins_with("--inspect="): source=arg.trim_prefix("--inspect=")
        if arg.begins_with("--output="): output=arg.trim_prefix("--output=")
    var path: String="user://profiles_v3/"+source
    var files: PackedStringArray=DirAccess.get_files_at(path) if source.begins_with("qa_canal_session_") and source.validate_filename()==source else PackedStringArray()
    files.sort()
    var result: Dictionary={"checks":1,"failures":[],"engine_errors":[],"diagnosis":{}}
    if files.is_empty(): result.failures.append("isolated existing QA generation not found")
    else:
        var disk: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(path.path_join(files[-1])))
        var saved: Dictionary=JSON.parse_string(disk.payload_json).world.environment.I2_canal
        result.diagnosis={"path":path.path_join(files[-1]),"progress":Progress.validate(saved),"workbench":Progress.Wait.Bench.validate_progress(saved.workbench,saved.rules),"executor":Progress.Parts.validate_executor(saved.executor,saved.rules),"custody":Progress.Wait.Custody.validate_progress_snapshot(saved.custody),"json_safe":Progress.Wait.Safe._json_safe(saved),"carrier":Progress.State.validate_progress(saved.carrier,Progress.Rules.CARRIER),"beneficiary":Progress.State.validate_progress(saved.workbench.beneficiary,Progress.Wait.Safe.BENEFICIARY_ID)}
        if not result.diagnosis.progress.ok: result.failures.append(result.diagnosis.progress.code)
    if not output.is_empty():
        var file:=FileAccess.open(output.path_join("result.json"),FileAccess.WRITE)
        if file: file.store_string(JSON.stringify(result,"\t",true,true))
    print("CANAL_READ_ONLY ",JSON.stringify(result))
    quit(0 if result.failures.is_empty() else 1)
