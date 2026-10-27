extends SceneTree
## Only the NEW completed current-build acceptance chain's private profile.
## Does not import/copy/create completed objectives or alter a historical save.
const Main = preload("res://scenes/v3/main.tscn")
const Driver = preload("res://scripts_tools/v3/acceptance_optional_driver.gd")
const ChoiceDriver = preload("res://scripts_tools/v3/acceptance_choices_driver.gd")
const PresentationDriver = preload("res://scripts_tools/v3/acceptance_presentation_driver.gd")
const CompletionDriver = preload("res://scripts_tools/v3/acceptance_completion_driver.gd")
const Store = preload("res://scripts/v3/core/twin_world_store.gd")
class ErrorLog extends Logger:
	var errors: Array = []
	var guard := Mutex.new()
	func _log_error(function: String, file: String, line: int, code: String, reason: String, _notify: bool, kind: int, _trace: Array[ScriptBacktrace]) -> void:
		if kind == Logger.ERROR_TYPE_WARNING: return
		guard.lock()
		if errors.size() < 30: errors.append({"function":function,"file":file,"line":line,"code":code,"reason":reason})
		guard.unlock()
var logger := ErrorLog.new()
var session: Node
var controller: Node
var options: Dictionary = {}
var source: Dictionary = {}
var initial: Dictionary = {}
var report: Dictionary = {}
var finishing := false
var output := ""

func _initialize() -> void:
	OS.add_logger(logger)
	_run.call_deferred()

func _run() -> void:
	for arg: String in OS.get_cmdline_user_args():
		var split := arg.find("=")
		if split < 0: quit(2); return
		var key := arg.substr(0,split)
		if key not in ["--qa-profile","--source-chain","--region","--mode","--output"] or options.has(key): quit(2); return
		options[key] = arg.substr(split+1)
	if options.size() != 5: quit(2); return
	output = str(options["--output"])
	var chain_path := str(options["--source-chain"]).replace("\\","/")
	if not chain_path.is_absolute_path() or ".." in chain_path or not chain_path.ends_with("/chain.json") or not "/normal-chain-20261022_" in chain_path or not output.is_absolute_path() or ".." in output or FileAccess.file_exists(output): quit(2); return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(chain_path))
	if not parsed is Dictionary or parsed.get("state") != "complete" or parsed.get("completed",[]).size() != 16 or parsed.get("profile") != options["--qa-profile"] or parsed.get("target",{}).get("app_version") != ProjectSettings.get_setting("application/config/version"): quit(2); return
	source = parsed
	if options["--mode"] not in ["all","stories","combat","secrets","choices","presentation","panels","summary"] or options["--region"] not in ["I1","F1","I2","F2","I3","F3","I4","F4"]: quit(2); return
	if options["--mode"] in ["presentation","panels"]:
		root.unfocusable = true
		root.keep_title_visible = false
		root.size = Vector2i(1280,720)
		root.position = Vector2i(-10000,-10000)
		root.mode = Window.MODE_MINIMIZED
		root.mode = Window.MODE_WINDOWED
		set_meta("acceptance_output",output)
	session = Main.instantiate()
	root.add_child(session)
	await process_frame
	initial = session.store.snapshot()
	if not session.profile_ready or initial.get("profile_id") != source.identity.id or initial.get("lineage_id") != source.identity.lineage:
		quit(2); return
	var recover_choice: bool = options["--mode"]=="choices" and str(initial.world.branch_id)!="main" and initial.branches.get("main",{}).get("world",{}).get("actions",{}).get("opening",{}).get("completed",[]).size()==84
	if initial.world.actions.opening.completed.size()!=84 and not recover_choice: quit(2); return
	if not session.start_flight("solo"): quit(2); return
	controller = ChoiceDriver.new() if options["--mode"]=="choices" else PresentationDriver.new() if options["--mode"] in ["presentation","panels"] else CompletionDriver.new() if options["--mode"]=="summary" else Driver.new()
	session.add_child(controller)
	controller.attach(session)
	if recover_choice:
		controller.home_branch = "main"
		if not await controller.recover_main(): await _finish(false,"normal_main_recovery_failed"); return
		controller._rebind()
		initial = session.store.snapshot()
	create_timer(1500).timeout.connect(func(): _finish(false,"bounded_optional_region_timeout"))
	await controller._next()
	if not await controller._dismiss(): await _finish(false,"opening_dialogue_or_ending_did_not_close"); return
	var ok: bool = await controller.play_region(str(options["--region"]),str(options["--mode"]))
	await _finish(ok,"completed" if ok else "native_optional_case_failed")

func _finish(ok: bool, reason: String) -> void:
	if finishing: return
	finishing = true
	if controller == null:
		quit(2); return
	controller.fire = false
	Input.action_release("flight_fire")
	controller.pilot = null
	if controller.has_method("recover_main"): await controller.recover_main()
	if not session.simulation_paused:
		controller._key(KEY_P)
		await controller._next()
	var callbacks: Array = []
	var deadline := Time.get_ticks_msec()+12000
	while session.environment_save_gate.pending() and Time.get_ticks_msec() < deadline: await controller._next()
	var request: Dictionary = session.request_environment_save(func(row: Dictionary): callbacks.append(row.duplicate(true)))
	while callbacks.is_empty() and Time.get_ticks_msec() < deadline: await controller._next()
	var reader = Store.new(session.store.root_path)
	var loaded: Dictionary = reader.load_profile()
	var saved: Dictionary = reader.snapshot()
	var durable: bool = loaded.get("ok",false) and not loaded.get("recovered",false) and not callbacks.is_empty() and callbacks[-1].get("ok",false) and callbacks[-1].get("completed",false)
	var unchanged_story: bool = durable and saved.world.actions.opening == initial.world.actions.opening and saved.world.completed_objectives == initial.world.completed_objectives
	controller._check(durable,"original SaveGate and independent reader preserve the run",{"request":request,"callbacks":callbacks,"reader":loaded})
	controller._check(unchanged_story,"all 84 real main receipts and choices remain unchanged")
	report = {"version":ProjectSettings.get_setting("application/config/version"),"source_chain":options["--source-chain"],"profile":source.profile,"profile_id":source.identity.id,"lineage_id":source.identity.lineage,
		"content_source":{"side_stories_sha256":FileAccess.get_sha256("res://data/v3/content/dev88_story/side_stories.json"),"side_story_builder_sha256":FileAccess.get_sha256("res://scripts/v3/content/dev88_story/twin_side_story_builder.gd"),"secrets_sha256":FileAccess.get_sha256("res://data/v3/content/dev88_progression/secrets.json")},
		"region":options["--region"],"mode":options["--mode"],"reason":reason,"passed":ok and durable and unchanged_story and controller.failures.is_empty() and logger.errors.is_empty(),
		"checks":controller.checks,"failures":controller.failures,"engine_errors":logger.errors,"events":controller.events,"outcomes":controller.outcomes,"distance_m":controller.distance,"fresh_generation":saved.get("generation"),
		"native_exit":{"requested":true,"observed_scene_exit":false},"scope":"Source MAIN optional play after a new actual exported natural84 chain. Original flight/keys/abilities/physics/AI/Store only. No old profile, pose/velocity/HP/clock/progress injection, fixture completion, or full graphical/human/LAN claim."}
	_write()
	controller.running = false
	session.tree_exiting.connect(func():
		report.native_exit["observed_scene_exit"] = true
		report.native_exit["audio"] = session.last_audio_shutdown_result
		report.passed = report.passed and bool(session.last_audio_shutdown_result.get("ready",false))
		_write())
	print("OPTIONAL_ACCEPTANCE ",JSON.stringify({"passed":report.passed,"report":output,"region":options["--region"],"outcomes":controller.outcomes.size()}))
	session._quit()

func _write() -> void:
	var file := FileAccess.open(output,FileAccess.WRITE)
	if file != null: file.store_string(JSON.stringify(report,"\t")); file.close()
