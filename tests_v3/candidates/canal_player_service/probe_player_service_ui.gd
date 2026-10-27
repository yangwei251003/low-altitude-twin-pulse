extends SceneTree
## Real candidate scene + G/F9 events. Uses a completed actual saved envelope
## in a unique QA profile. ONE initial player placement is a declared fixture,
## not a flight/transport/work completion. No direct health or ledger writes.
const Scene = preload("res://scripts/v3/candidates/canal_playable/canal_playable.tscn")
const Repository = preload("res://scripts/v3/candidates/canal_checkpoint/checkpoint_repository.gd")
const Capture = preload("res://scripts/v3/candidates/canal_checkpoint/player_checkpoint.gd")
const State = preload("res://scripts/v3/candidates/canal_checkpoint/flight_state.gd")
const SOURCE := "res://tests_v3/candidates/canal_player_service/evidence/first_player_checkpoint_actual.json"
const SOURCE_SHA := "90fa185b241fe2a8ce84c40bb2ad1ad047cbd53f62eb7f0ba70b4d6c3721e093"
const INPUT_SEED := "res://tests_v3/candidates/canal_player_service/evidence/ui_input_seed_paths.json"
const ENTRY := "res://tests_v3/candidates/canal_player_service/probe_player_service_ui.gd"
const QA_POSITION := Vector3(3.5,2.8,5.4)
var play: Node3D
var output := ""
var profile := ""
var checks := 0
var failures: Array = []
var evidence: Dictionary = {}
var shots: Array = []
var before_hashes: Dictionary = {}
var input_paths: Array[String] = []
var finished := false
var started_ms := 0

class ErrorLog extends Logger:
    var errors: Array = []
    func _log_error(fn: String,file: String,line: int,code: String,reason: String,_notify: bool,kind: int,_traces: Array[ScriptBacktrace]) -> void:
        errors.append({"function":fn,"file":file,"line":line,"code":code,"reason":reason,"kind":kind})
var logger := ErrorLog.new()

func _init() -> void:
    OS.add_logger(logger)
    for arg: String in OS.get_cmdline_user_args():
        if arg.begins_with("--capture-output="): output = arg.trim_prefix("--capture-output=")
    _run.call_deferred()

func _run() -> void:
    started_ms = Time.get_ticks_msec()
    create_timer(45).timeout.connect(func():
        if not finished:
            _check(false,"45 second UI probe timeout",_live_details())
            _finish())
    if not _check(_prepare_output(),"new permitted output and genuine 720p Compatibility renderer"):
        output = ""
        _finish(); return
    if not _check(FileAccess.get_sha256(SOURCE)==SOURCE_SHA and Engine.physics_ticks_per_second==60 and Engine.time_scale==1.0,"original completed-player fixture and normal physical clock"):
        _finish(); return
    before_hashes = _collect_inputs()
    if not _write_json("inputs_before.json",before_hashes): _finish(); return
    var source: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(SOURCE))
    if not _check(Capture.validate(source).ok and source.site.rules.jobs_completed==1 and source.site.rules.services_consumed==0 and source.site.rules.service_credit==1,"actual first-work full envelope is eligible before QA import"):
        _finish(); return
    profile = "user://qa_v3/canal_service_ui_"+str(Time.get_ticks_usec())
    if not _check(not DirAccess.dir_exists_absolute(profile),"new isolated QA profile only",{"path":profile}): _finish(); return
    var repository = Repository.new(profile)
    var imported: Dictionary = repository.save(source,"qa-import-actual-first-player-envelope",0)
    if not _check(imported.ok and imported.generation==1,"original full envelope imported through actual Store",{"code":imported.get("code","")}): _finish(); return
    evidence.fixture = {"path":SOURCE,"sha256":SOURCE_SHA,"original":"canal-player-checkpoint-20261020_050633_87e6e4/first_saved.json","original_checks":57,"scope":"real saved first work, imported to unique QA profile; ONE initial player placement is not a route proof"}
    play = Scene.instantiate()
    play.persistence_enabled = true
    play.profile_path = profile
    root.add_child(play)
    current_scene = play
    _neutral_input()
    if not await _wait_loaded(600): _finish(); return
    var first_adopted: Dictionary = play.last_save_result.duplicate(true)
    _check(first_adopted.get("code")=="player_scene_restored" and play.save_generation==1 and first_adopted.initial_player.health==imported.envelope.player.flight.health,"actual scene restores the existing injured player")
    _check(_same(first_adopted.initial_player.state.damage,imported.envelope.player.flight.state.damage) and first_adopted.initial_player.state.battery==imported.envelope.player.flight.state.battery,"initial scene adoption does not repair armor components or battery")
    var original_pose: Transform3D = play.player.global_transform
    var target_pose: Transform3D = original_pose
    target_pose.origin = QA_POSITION
    var excluded: Array[RID] = [play.player.get_rid()]
    var clearance: Dictionary = Capture._clearance(play.player,target_pose,excluded)
    if not _check(clearance.ok,"one initial service-side QA placement clears the actual full body envelope",clearance): _finish(); return
    # The only authored movement of an existing player in this probe. Preserve
    # actual velocity, orientation, damage/resources and every mechanism pose.
    play.player.global_transform = target_pose
    play.player.hold_height = QA_POSITION.y
    play.camera_rig.snap(QA_POSITION)
    evidence.initial_placement = {"from":State.pose(original_pose),"to":State.pose(target_pose),"physics_frame":Engine.get_physics_frames(),"changed_fields":["player.global_transform.origin","player.hold_height","camera_snap"],"subsequent_pose_writes":0}
    _neutral_input()
    for i in 30:
        if not await _frame(): _finish(); return
    if not await _select_workbench(): _finish(); return
    var pre_health: float = play.player.health
    var pre_damage: Dictionary = play.player.damage_snapshot()
    var pre_battery: float = play.player.battery
    var pre_rules: Dictionary = play.context.rules.snapshot()
    var collision_count: int = play.player.collision_count
    _check(pre_health<100 and pre_rules.service_credit==1 and pre_rules.jobs_completed==1,"original saved injury and sole service still exist before G")
    await _capture("01-before-service.png","original injured player, existing first credit; no service yet")
    await _key(KEY_G)
    var trace: Array = []
    var repaired := false
    for i in 1250:
        if not await _frame(): _finish(); return
        if i%60==0: trace.append({"frame":i,"waiting":play._service_requested,"result":play.last_service_result.duplicate(true),"executor_phase":play.executor.report().phase,"player_speed":play.player.linear_velocity.length()})
        if play.last_service_result.get("ok",false):
            repaired = play.last_service_result.code=="service_committed"
            break
        if not play._service_requested: break
    evidence.service_wait = trace
    if not _check(repaired,"real G request reaches physical safe boundary and commits service",{"last":play.last_service_result,"details":_live_details()}): _finish(); return
    var repair: Dictionary = play.last_service_result.duplicate(true)
    var expected_hp: float = minf(100.0,pre_health+25.0)
    var used: Dictionary = play.context.rules.snapshot()
    _check(play.player.health==expected_hp and is_equal_approx(float(repair.healed_hp),expected_hp-pre_health),"actual G restores only min(25, missing hull HP)",repair)
    var post_damage: Dictionary = play.player.damage_snapshot()
    pre_damage.erase("health")
    post_damage.erase("health")
    _check(post_damage==pre_damage and play.player.battery<=pre_battery and play.player.collision_count==collision_count,"G preserves armor component damage and collision history; battery is not refilled")
    _check(used.service_credit==0 and used.services_consumed==1 and used.jobs_completed==1 and used.action_serial==pre_rules.action_serial and used.pending_action.is_empty() and play.executor.report().waiting_for_beneficiary,"G consumes the original credit once and keeps the departed beneficiary completed")
    var disk: Dictionary = repository.read()
    if not _check(disk.ok and disk.generation==2 and play.save_generation==2 and disk.envelope.player.flight.health==expected_hp and disk.envelope.site.rules.services_consumed==1,"G publishes one generation containing both repair and consumption"):
        _finish(); return
    if not _write_json("after_service_saved.json",disk.envelope): _finish(); return
    await _capture("02-after-service.png","actual G committed repair and consumed first credit")
    _check(play.status_text.text.contains("维修已用") and play.note_text.text.contains("机体恢复"),"normal process updated real HUD after service without a manual refresh",{"status":play.status_text.text,"note":play.note_text.text})
    var old_id: int = play.get_instance_id()
    var old_ref: WeakRef = weakref(play)
    await _key(KEY_F9)
    var new_scene := false
    for i in 600:
        await physics_frame
        if finished: return
        if is_instance_valid(current_scene) and current_scene.get_instance_id()!=old_id:
            play = current_scene
            _neutral_input()
            new_scene = true
            break
    if not _check(new_scene,"real F9 reload creates another actual scene instance"): _finish(); return
    if not await _wait_loaded(600): _finish(); return
    var adopted: Dictionary = play.last_save_result.duplicate(true)
    _check(not is_instance_valid(old_ref.get_ref()) and adopted.get("code")=="player_scene_restored","old scene is gone and real new scene reaches ready/adopt")
    _check(play.save_generation==2 and adopted.initial_player.health==disk.envelope.player.flight.health and _same(adopted.initial_player.state.damage,disk.envelope.player.flight.state.damage),"F9 restores persisted repair and original armor/component state")
    _check(adopted.initial_player.state.battery==disk.envelope.player.flight.state.battery and adopted.initial_energy==disk.envelope.ability.energy and adopted.station_serial==disk.envelope.ability.station_serial,"F9 preserves saved battery ability energy and device serial at adoption")
    _check(play.executor.report().waiting_for_beneficiary,"consumed scene adopts the public waiting mode")
    var max_anchor_error := 0.0
    var start_clock: float = play.world.clock_seconds
    for i in 300:
        if not await _frame(): _finish(); return
        max_anchor_error = maxf(max_anchor_error,play.context.carrier.global_position.distance_to(play.executor.report().hold.target))
    var resumed: Dictionary = play.context.rules.snapshot()
    _check(play.world.clock_seconds>=start_clock+4.99 and resumed.jobs_completed==1 and resumed.services_consumed==1 and resumed.service_credit==0 and resumed.service_serial==used.service_serial and resumed.action_serial==used.action_serial and resumed.pending_action.is_empty() and play.workbench.report().receipt_count==1,"five seconds of actual resumed host work preserves the sole consumed result")
    _check(play.player.health==expected_hp and play.player.collision_count==collision_count and max_anchor_error<.18,"resumed player has no extra healing/collision and carrier really holds",{"maximum_anchor_error_m":max_anchor_error})
    var before_repeat: Dictionary = play.context.rules.snapshot()
    await _key(KEY_G)
    for i in 3:
        if not await _frame(): _finish(); return
    var after_repeat: Dictionary = play.context.rules.snapshot()
    _check(play.player.health==expected_hp and after_repeat.service_serial==before_repeat.service_serial and after_repeat.services_consumed==1 and after_repeat.jobs_completed==1 and after_repeat.pending_action.is_empty() and repository.read().generation==2 and not play._service_requested,"post-F9 G cannot repeat the repair or create another Store generation")
    _check(play.note_text.text.contains("已用完") and play.status_text.text.contains("维修已用"),"actual repeated-G HUD explains the retained completed result",{"status":play.status_text.text,"note":play.note_text.text})
    if not await _select_workbench(): _finish(); return
    await _capture("03-restored-five-seconds.png","actual F9 new scene, five normal host seconds, repeated G rejected")
    evidence.repair = repair
    evidence.initial_adopted = first_adopted
    evidence.restored_adopted = adopted
    evidence.final = {"generation":repository.read().generation,"health":play.player.health,"battery":play.player.battery,"collision_count":play.player.collision_count,"rules":resumed,"max_anchor_error_m":max_anchor_error,"normal_host_seconds":play.world.clock_seconds-start_clock}
    _check(shots.size()==3,"exactly three actual GPU captures")
    _finish()

func _neutral_input() -> void:
    if not is_instance_valid(play) or not is_instance_valid(play.inputs): return
    play.inputs.test_enabled = true
    play.inputs.test_frame = {"axes":{},"held":["brake"]}

func _wait_loaded(limit: int) -> bool:
    for i in limit:
        if not await _frame(): return false
        _neutral_input()
        if play.boot_ready and not play.loading_checkpoint: return true
    return _check(false,"bounded actual scene restoration",_live_details())

func _frame() -> bool:
    await physics_frame
    if finished: return false
    if not is_instance_valid(play) or not play.fatal.is_empty() or not logger.errors.is_empty():
        return _check(false,"actual scene remains healthy",_live_details())
    return true

func _key(code: Key) -> void:
    var event := InputEventKey.new()
    event.keycode = code
    event.physical_keycode = code
    event.pressed = true
    Input.parse_input_event(event)
    await process_frame
    event = InputEventKey.new()
    event.keycode = code
    event.physical_keycode = code
    event.pressed = false
    Input.parse_input_event(event)
    await process_frame

func _select_workbench() -> bool:
    for i in 12:
        if play.target==play.Workbench.POWER_ID: return true
        await _key(KEY_TAB)
        if not await _frame(): return false
    return _check(false,"real Tab reaches the workbench target",{"actual":play.target})

func _capture(filename: String, purpose: String) -> void:
    await process_frame
    await RenderingServer.frame_post_draw
    if finished: return
    var image: Image = root.get_texture().get_image()
    if not _check(image.get_size()==Vector2i(1280,720),"actual capture size",{"file":filename,"size":str(image.get_size())}): return
    var path: String = output.path_join(filename)
    if not _check(not FileAccess.file_exists(path) and image.save_png(path)==OK,"new genuine framebuffer PNG",{"file":filename}): return
    var row: Dictionary = {"file":filename,"sha256":FileAccess.get_sha256(path),"purpose":purpose,"physics_frame":Engine.get_physics_frames(),"scene_instance":play.get_instance_id(),"camera":{"pose":State.pose(play.camera.global_transform),"size":play.camera.size},"player":State.capture(play.player,Capture.PLAYER_ID),"hud":_hud_record()}
    var pilot_screen: Vector2 = play.camera.unproject_position(play.player.global_position)
    var pilot_clearance := Rect2(pilot_screen-Vector2(52,42),Vector2(104,84))
    var panel_rect: Rect2 = play.target_panel.get_global_rect()
    row.player_visibility = {"screen":[pilot_screen.x,pilot_screen.y],"target_panel":[panel_rect.position.x,panel_rect.position.y,panel_rect.size.x,panel_rect.size.y],"target_label_clear":not panel_rect.intersects(pilot_clearance)}
    _check(row.player_visibility.target_label_clear,"target label leaves the actual player projection clear",row.player_visibility)
    shots.append(row)

func _hud_record() -> Array:
    var rows: Array = []
    var viewport := Rect2(Vector2.ZERO,Vector2(1280,720))
    for node: Node in play.find_children("*","Label",true,false):
        var label: Label = node as Label
        if not label.is_visible_in_tree(): continue
        var bounds: Rect2 = label.get_global_rect()
        var minimum: Vector2 = label.get_combined_minimum_size()
        var clipped: Rect2 = bounds
        var ancestor: Node = label.get_parent()
        while ancestor != null:
            if ancestor is Control and ancestor.clip_contents: clipped = clipped.intersection(ancestor.get_global_rect())
            ancestor = ancestor.get_parent()
        var fits: bool = viewport.grow(.5).encloses(bounds) and bounds.size.x+.5>=minimum.x and bounds.size.y+.5>=minimum.y and clipped==bounds
        var row: Dictionary = {"path":str(label.get_path()),"text":label.text,"rect":[bounds.position.x,bounds.position.y,bounds.size.x,bounds.size.y],"minimum_size":[minimum.x,minimum.y],"clip_text":label.clip_text,"fits_without_clip":fits}
        rows.append(row)
        _check(fits,"visible HUD label has room without ancestor clipping",row)
    return rows

func _prepare_output() -> bool:
    if output.is_empty(): output = "res://artifacts/v3/art/canal-player-service-"+Time.get_datetime_string_from_system().replace(":","").replace("T","_")+"_"+str(Time.get_ticks_usec())
    output = ProjectSettings.globalize_path(output).replace("\\","/").simplify_path()
    var allowed: String = ProjectSettings.globalize_path("res://artifacts/v3/art").replace("\\","/").simplify_path()
    if output.get_base_dir().to_lower()!=allowed.to_lower() or not output.get_file().begins_with("canal-player-service-") or DirAccess.dir_exists_absolute(output) or FileAccess.file_exists(output): return false
    if DisplayServer.get_name()=="headless" or RenderingServer.get_current_rendering_method()!="gl_compatibility" or not RenderingServer.is_render_loop_enabled() or root.size!=Vector2i(1280,720): return false
    return DirAccess.make_dir_recursive_absolute(output)==OK

func _collect_inputs() -> Dictionary:
    var queue: Array = JSON.parse_string(FileAccess.get_file_as_string(INPUT_SEED))
    for i in queue.size(): queue[i] = "res://"+str(queue[i])
    queue.append_array([ENTRY,SOURCE,INPUT_SEED,Scene.resource_path,"res://project.godot"])
    var result: Dictionary = {}
    var pattern := RegEx.new()
    if pattern.compile("res://[^\\s\"'()]+")!=OK:
        _check(false,"dependency expression compiles")
        return result
    while not queue.is_empty():
        var path: String = str(queue.pop_back())
        if result.has(path) or not FileAccess.file_exists(path): continue
        result[path] = FileAccess.get_sha256(path)
        if FileAccess.file_exists(path+".import"): queue.append(path+".import")
        if path.get_extension() in ["gd","json","tscn","tres","godot","gdshader","gdshaderinc","import"]:
            for found: RegExMatch in pattern.search_all(FileAccess.get_file_as_string(path)):
                if FileAccess.file_exists(found.get_string()): queue.append(found.get_string())
    input_paths.assign(result.keys())
    return result

func _live_details() -> Dictionary:
    var row: Dictionary = {"engine_errors":logger.errors}
    if not is_instance_valid(play): return row
    row.fatal = play.fatal
    row.loading = play.loading_checkpoint
    row.notes = play.notes
    row.last_service = play.last_service_result.duplicate(true)
    row.last_save = play.last_save_result.duplicate(true)
    if is_instance_valid(play.player): row.player = State.capture(play.player,Capture.PLAYER_ID)
    if play.executor_ready:
        row.executor = play.executor.report()
        row.rules = play.context.rules.snapshot()
    return row

func _write_json(name: String,value: Variant) -> bool:
    var file := FileAccess.open(output.path_join(name),FileAccess.WRITE)
    if file==null: return _check(false,"artifact open",{"file":name,"error":FileAccess.get_open_error()})
    file.store_string(JSON.stringify(value,"  ",true,true))
    file.flush()
    var error: Error = file.get_error()
    file.close()
    if error!=OK: return _check(false,"artifact write",{"file":name,"error":error})
    return true

func _check(ok: bool,label: String,details: Dictionary = {}) -> bool:
    checks += 1
    if not ok: failures.append({"label":label,"details":details.duplicate(true)})
    return ok

func _finish() -> void:
    if finished: return
    finished = true
    _check(logger.errors.is_empty(),"no engine errors",{"errors":logger.errors})
    var after: Dictionary = {}
    for path: String in input_paths: after[path] = FileAccess.get_sha256(path)
    var changed: Array = []
    for path: String in before_hashes:
        if before_hashes[path]!=after.get(path): changed.append(path)
    _check(changed.is_empty(),"runtime input SHA unchanged",{"changed":changed})
    evidence.profile = profile
    evidence.scope = "Actual candidate scene loaded from a prior real first-order checkpoint, ONE QA player placement, injected G/F9 input events, real host/Store and three GPU frames. No new route, human keyboard, MAIN, LAN or full-work replay claim. Text bounds are mechanical checks; visual readability remains Root review."
    var result: Dictionary = {"checks":checks,"failures":failures,"engine_errors":logger.errors,"shots":shots,"evidence":evidence,"elapsed_seconds":float(Time.get_ticks_msec()-started_ms)/1000.0,"gpu":RenderingServer.get_video_adapter_name(),"renderer":RenderingServer.get_current_rendering_method(),"display":DisplayServer.get_name(),"engine":Engine.get_version_info(),"changed_inputs":changed,"final_diagnostics":_live_details()}
    if not output.is_empty():
        _write_json("inputs_after.json",after)
        # Artifact write failures are part of exit status and printed report.
        result.checks = checks
        result.failures = failures.duplicate(true)
        _write_json("state_checks.json",result)
    result.checks = checks
    result.failures = failures.duplicate(true)
    print("V3_CANAL_PLAYER_SERVICE_UI "+JSON.stringify(result))
    if is_instance_valid(play): play.free()
    quit(0 if failures.is_empty() and logger.errors.is_empty() else 1)

func _same(a: Variant,b: Variant) -> bool:
    if (a is int or a is float) and (b is int or b is float): return is_finite(float(a)) and is_finite(float(b)) and absf(float(a)-float(b))<=1e-10
    if typeof(a)!=typeof(b): return false
    if a is Dictionary:
        if a.size()!=b.size(): return false
        for key: Variant in a:
            if not b.has(key) or not _same(a[key],b[key]): return false
        return true
    if a is Array:
        if a.size()!=b.size(): return false
        for i in a.size():
            if not _same(a[i],b[i]): return false
        return true
    return a==b
