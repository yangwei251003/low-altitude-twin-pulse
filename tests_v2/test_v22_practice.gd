extends SceneTree
## Production UI/session regression plus explicitly labelled event-hook semantics.
## Owner runs serially. No pilot pose, velocity, telemetry, or tutorial index writes.
var game: GameSessionV2
var qa_case = ""
var fixture_root = ""
var checks = 0
var failures: Array[String] = []
var before: Dictionary = {}
var formal_checkpoint: Dictionary = {}
const DT = 1.0 / 60.0

func _initialize() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--v2-qa=practice_"): qa_case = argument.trim_prefix("--v2-qa=").validate_filename()
	if qa_case.is_empty() or DisplayServer.get_name() != "headless":
		printerr("Requires headless and a fresh --v2-qa=practice_<unique> QA case.")
		quit(2)
		return
	fixture_root = "user://qa_v22/"+qa_case
	if DirAccess.dir_exists_absolute(fixture_root) or DirAccess.dir_exists_absolute("user://qa_v2/session_"+qa_case):
		printerr("Existing fixture preserved. Choose another practice case name.")
		quit(2)
		return
	Engine.physics_ticks_per_second = 60
	call_deferred("_run")

func check(value: bool, description: String) -> void:
	checks += 1
	if not value: failures.append(description)
	print("V22_PRACTICE_CHECK ",JSON.stringify({"pass":value,"check":description}))

func settle() -> void:
	for tick in 5: await process_frame

func _snapshot(repo: SaveRepositoryV2) -> Dictionary:
	var data: Dictionary = repo.data
	return {"wallet":data.wallet.duplicate(true),"campaign":data.campaign.duplicate(true),"records":data.records.duplicate(true),"builds":data.builds.duplicate(true),"selected_build_id":data.selected_build_id,"owned_airframes":data.owned_airframes.duplicate(),"owned_modules":data.owned_modules.duplicate(),"world":data.world.duplicate(true)}

func _buttons(node: Node, label: String, output: Array[Button]) -> void:
	if node is Button and node.text == label and node.is_visible_in_tree(): output.append(node)
	for child in node.get_children(): _buttons(child,label,output)

func _run() -> void:
	game = GameSessionV2.new()
	# The first lobby also resolves profile summaries; keep those reads isolated.
	game.profiles = ProfileCatalogV22.new(fixture_root+"/profiles",fixture_root+"/nonexistent_legacy_source")
	game.profiles.initialize()
	root.add_child(game)
	await settle()
	check(game.qa_mode and game.repository.root_path == "user://qa_v2/session_"+qa_case,"Production session uses isolated requested QA repository")
	if not game.qa_mode or game.repository.root_path != "user://qa_v2/session_"+qa_case:
		_finish()
		return
	# Explicit fixture, not a completed gameplay claim: formal M03 is suspended
	# at the second stage, with a distinct owned hook build and meaningful state.
	var completed_stages: Array = []
	for id in ["M01","M02"]:
		for stage in game.get_job(id).stages: completed_stages.append(stage.id)
	completed_stages.append("M03-S1")
	formal_checkpoint = {"job_id":"M03","stage_index":1,"run_id":"formal-practice-regression-"+qa_case,"seconds":123.25,"repeat":false,"night":true,"conditions":{"difficulty":0,"control_profile_hash":"fixture-formal-hash","control_modes_used":["assisted"],"auto_fire_used":true,"practice":false},"run_state":{"stage_id":"M03-S2","action_index":0,"elapsed_s":17.5,"cargo_records":{},"preparation_flags":{"formal_fixture":true},"stage_start_cargo":{},"stage_start_flags":{},"metrics":{"damage_taken":2.0},"optional":false}}
	var formal_build = CatalogV2.default_build("tr01")
	formal_build.slots.tool = "hook_base"
	# Wallet is intentionally absent from SaveRepositoryV2.MUTABLE_ROOTS;
	# currency must use the production parts_delta transaction field.
	var setup = game.repository.commit({"id":"qa-practice:formal-fixture","parts_delta":437-int(game.repository.data.wallet.parts),"set":{"campaign.completed_missions":["M01","M02"],"campaign.completed_stages":completed_stages,"campaign.active_checkpoint":formal_checkpoint,"builds":[formal_build],"selected_build_id":formal_build.build_id},"append":{"owned_modules":["hook_base","delivery_base"]}})
	print("V22_PRACTICE_FIXTURE ",JSON.stringify({"result":setup,"repository_notice":game.repository.notice,"wallet_parts":game.repository.data.wallet.parts,"currency_api":"parts_delta"}))
	check(bool(setup.get("ok",false)),"Formal M03 S2 fixture passes production save validation"+("; "+str(setup.get("error","unknown failure")) if not bool(setup.get("ok",false)) else ""))
	if not bool(setup.get("ok",false)):
		_finish()
		return
	# commit() returns its JSON readback, where all JSON numbers are floats.
	# First verify fixture values canonically, then freeze the actual stored
	# representation for strict before/after equality. Do not compare later
	# saves against the original GDScript integer literals.
	var stored_checkpoint: Dictionary = game.repository.data.campaign.active_checkpoint
	check(game.repository._canonical(stored_checkpoint) == game.repository._canonical(formal_checkpoint),"Committed formal checkpoint preserves every requested fixture value")
	var type_differences: Array = []
	_checkpoint_type_diff(formal_checkpoint,stored_checkpoint,"checkpoint",type_differences)
	print("V22_PRACTICE_CHECKPOINT_NORMALIZATION ",JSON.stringify(type_differences))
	formal_checkpoint = stored_checkpoint.duplicate(true)
	game.show_hangar()
	await settle()
	before = _snapshot(game.repository)
	check(game.job_unlocked(game.get_job("M03")),"M03 is legally unlocked by fixture prerequisites")
	game.ui._begin_tutorial("M03",false)
	await settle()
	check(not game.flight_active and bool(game.ui.prepared_job.get("training",false)),"Actual tutorial UI prepares independent training briefing")
	check(_snapshot(game.repository) == before,"Opening tutorial briefing preserves formal save")
	var launch: Variant = game.ui.action_controls.get("launch")
	check(launch is Button and str(launch.text) == "开始练习  →","Briefing exposes the real training launch button")
	if not launch is Button:
		_finish()
		return
	launch.pressed.emit()
	await settle()
	check(game.flight_active and is_instance_valid(game.pilot) and is_instance_valid(game.runner),"Native training button launches actual pilot and task runner")
	if not game.flight_active or not is_instance_valid(game.pilot) or not is_instance_valid(game.runner):
		_finish()
		return
	check(game.stage_index == 0 and str(game.runner.stage.id) == "M03-S1","Practice starts at stage zero despite formal S2 checkpoint")
	check(bool(game.current_job.get("training",false)) and bool(game.current_job.get("loaner",false)),"Current session is explicitly training and loaner")
	check(game.pilot.practice and bool(game.run_conditions.get("practice",false)),"Production pilot and run conditions suppress formal rewards")
	check(game.run_id.begins_with("training:") and game.run_id != formal_checkpoint.run_id,"Training has its own run identity")
	check(str(game.pilot.build.slots.tool) == "scan_base" and str(game.selected_build().slots.tool) == "hook_base","Borrowed scanner does not replace owned hook loadout")
	check(game.repository.data.campaign.active_checkpoint == formal_checkpoint and _snapshot(game.repository) == before,"Practice launch preserves checkpoint, wallet, records, builds and unlocks")
	game.pause_game()
	await settle()
	var lesson_before: Dictionary = game.tutorial.get_state().duplicate(true)
	game.ui._begin_tutorial("M01",true)
	check(game.tutorial.get_state() == lesson_before,"Paused-flight different-course request leaves director unchanged")
	check(paused and game.pause_reasons.has("manual") and str(game.current_job.id) == "M03","Rejected course request neither resumes nor replaces current flight")
	check(game.ui.toast_label.text.contains("返回机库"),"Rejected course explains the safe independent-practice entry")
	game.resume_game()
	await settle()
	check(not paused,"Normal pause resume remains available")
	if paused:
		_finish()
		return
	# This subsection exercises the real production completion hook's contract
	# with synthetic event arguments. It is NOT evidence of actual pickup,
	# flight, swing or delivery. No task runner action or progress is changed.
	await _event_order("before_swing",true)
	await _event_order("after_swing",false)
	check(game.stage_index == 0 and game.runner.action_index == 0,"Hook-contract checks never complete a real mission action")
	check(_snapshot(game.repository) == before,"Hook-contract checks preserve all formal gameplay state")
	game.pause_game()
	await settle()
	var return_buttons: Array[Button] = []
	_buttons(game.ui.panel,"返回机库",return_buttons)
	check(return_buttons.size() == 1,"Pause exposes the real return-to-hangar button")
	if return_buttons.size() == 1: return_buttons[0].pressed.emit()
	else: game.show_hangar()
	await settle()
	check(not game.flight_active and not paused,"Returning from independent practice restores hangar")
	check(game.repository.data.campaign.active_checkpoint == formal_checkpoint,"Original formal M03 S2 checkpoint is exactly unchanged after return")
	check(_snapshot(game.repository) == before,"Return preserves wallet, records, builds, unlocks and world state")
	var reopened = SaveRepositoryV2.new(game.repository.root_path)
	check(reopened.load_profile(),"Persisted isolated profile reloads successfully")
	check(_snapshot(reopened) == before,"Disk-reloaded formal save exactly matches the pre-practice snapshot")
	_finish()

func _checkpoint_type_diff(expected: Variant, actual: Variant, path: String, output: Array) -> void:
	if expected is Dictionary and actual is Dictionary:
		for key in expected:
			if actual.has(key): _checkpoint_type_diff(expected[key],actual[key],path+"."+str(key),output)
	elif expected is Array and actual is Array:
		for index in mini(expected.size(),actual.size()): _checkpoint_type_diff(expected[index],actual[index],path+"["+str(index)+"]",output)
	elif typeof(expected) != typeof(actual):
		output.append({"path":path,"requested_type":type_string(typeof(expected)),"stored_type":type_string(typeof(actual)),"requested_value":expected,"stored_value":actual,"numeric_value_equal":expected == actual})

func _tick_director(frames: int) -> void:
	for tick in frames:
		await physics_frame
		# Actual pilot telemetry is passed untouched; only the named event-hook
		# inputs in _event_order are synthetic test stimuli.
		game.tutorial.physics_update(DT,game.pilot,game.input.last_frame)

func _event_order(label: String, delivery_first: bool) -> void:
	game.tutorial.replay("M02")
	game.tutorial.on_task_event("delivery",{"confirmed":false,"stable_delivery":true})
	check(not game.tutorial.pending_events.has("delivery"),label+": unconfirmed delivery is rejected")
	if delivery_first:
		game._tutorial_action_completed({"type":"deliver"})
		check(game.tutorial.get_state().step_id == "cargo_pickup",label+": confirmed future evidence does not skip the current step")
		check(bool(game.tutorial.pending_events.get("delivery",{}).get("stable_delivery",false)),label+": production hook records confirmed stable delivery")
	game._tutorial_action_completed({"type":"pickup"})
	await _tick_director(1)
	check(game.tutorial.get_state().step_id == "swing",label+": confirmed pickup advances through the normal director predicate")
	if not delivery_first:
		await _tick_director(15)
		check(game.tutorial.get_state().step_id == "swing" and not game.tutorial.pending_events.has("delivery"),label+": empty cargo without evidence cannot pass swing")
		game._tutorial_action_completed({"type":"deliver"})
	var stored: Dictionary = game.repository.data.settings.tutorial_v22.courses.M02
	check(bool(stored.get("task_evidence",{}).get("delivery",{}).get("confirmed",false)),label+": future completion evidence is saved before consumption")
	game.tutorial.configure(game)
	game.tutorial.auto_start("M02")
	check(game.tutorial.get_state().step_id == "swing" and game.tutorial.pending_events.has("delivery"),label+": reload preserves order and pending evidence")
	await _tick_director(130)
	check(game.tutorial.get_state().status == "completed",label+": stable delivery evidence survives swing and is consumed by delivery")
	check(game.tutorial.pending_events.is_empty(),label+": consumed events cannot trigger a second award or completion")

func _finish() -> void:
	print("V22_PRACTICE_RESULT ",JSON.stringify({"suite":"V22_production_independent_practice","case":qa_case,"checks":checks,"failures":failures,"passed":failures.is_empty(),"fixture_root":fixture_root,"scope":"Actual GameSession, native practice/return buttons, isolated persisted M03 S2 fixture. Delivery-order subsection is synthetic production-hook semantics with untouched real pilot telemetry; not actual pickup/delivery or graphical/controller evidence."},"",true,true))
	# Release the real session and let the dummy audio driver retire its active
	# playback objects before shutting down the test process.
	paused = false
	if is_instance_valid(game):
		if is_instance_valid(game.phone): game.phone.stop_server()
		game.queue_free()
	await process_frame
	await process_frame
	await create_timer(0.2,true,false,true).timeout
	quit(0 if failures.is_empty() else 1)
