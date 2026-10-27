extends SceneTree
## Native Button.pressed callbacks and actual Session/UI, with temporary profile storage.
## A controlled UI fixture: not pointer/controller hardware, manual flight or GPU evidence.

class IsolatedSession:
	extends "res://scripts/v2/session.gd"
	var fixture_path = ""
	func _ready() -> void:
		process_mode = Node.PROCESS_MODE_ALWAYS
		qa_mode = true
		content = CatalogV2.content()
		profiles = ProfileCatalogV22.new(fixture_path+"/profiles",fixture_path+"/nonexistent_legacy_source")
		profiles.initialize()
		repository = profiles.open_profile("default")
		repository.commit({"id":"ui-smoke:init","set":{"settings.fullscreen":false,"settings.mute":true,"settings.auto_fire":false}})
		active_build = selected_build()
		selected_frame = str(active_build.airframe_id)
		input = PilotInputV2.new()
		add_child(input)
		input.configure_input(repository.data.settings.get("input",{}))
		input.pause_requested.connect(func(reason): pause_game(reason))
		phone = PhoneServerV2.new()
		add_child(phone)
		phone.status_changed.connect(_phone_changed)
		_setup_view()
		ui = GameInterfaceV2.new()
		ui.session = self
		add_child(ui)
		if ResourceLoader.exists("res://scripts/v2/tutorial_director.gd"):
			tutorial = load("res://scripts/v2/tutorial_director.gd").new()
			add_child(tutorial)
			tutorial.configure(self)
		apply_settings()
		show_hangar()

var game: IsolatedSession
var fixture_root = ""
var checks = 0
var failures: Array[String] = []

func _initialize() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--retry-root="): fixture_root = argument.trim_prefix("--retry-root=").replace("\\","/")
	if DisplayServer.get_name() != "headless" or fixture_root.is_empty() or not fixture_root.is_absolute_path() or DirAccess.dir_exists_absolute(fixture_root):
		printerr("Requires headless and a fresh absolute --retry-root=<temporary directory>.")
		quit(2)
		return
	call_deferred("run")

func check(value: bool, description: String) -> void:
	checks += 1
	if not value: failures.append(description)
	print("WORLDUI_RETRY_CHECK ",JSON.stringify({"pass":value,"check":description}))

func settle(frames = 6) -> void:
	for tick in frames: await process_frame

func find_button(node: Node, text: String) -> Button:
	if node is Button and node.text == text and node.is_visible_in_tree(): return node
	for child in node.get_children():
		var match_button = find_button(child,text)
		if match_button != null: return match_button
	return null

func snapshot() -> String:
	var data: Dictionary = game.repository.data
	return JSON.stringify({"wallet":data.wallet,"campaign":data.campaign,"records":data.records,"builds":data.builds,"owned_modules":data.owned_modules,"owned_airframes":data.owned_airframes})

func click_retry(mode: String) -> void:
	game.fail_run("Isolated retry UI fixture; no combat-completion claim")
	await settle()
	check(paused and game.pause_reasons.has("result"),mode+" failure enters paused result")
	var retry = find_button(game.ui.panel,"再次出航")
	check(retry != null and not retry.disabled,mode+" retry button is reachable")
	if retry == null: return
	retry.grab_focus()
	check(root.gui_get_focus_owner()==retry,mode+" retry accepts native UI focus")
	retry.pressed.emit()
	await settle()
	if is_instance_valid(game.pilot): game.pilot.freeze = true
	check(game.flight_active and not paused and not game.pause_reasons.has("result"),mode+" retry returns to active flight")
	check(game.input.active and game.ui.screen_mode=="hud",mode+" retry restores input and HUD")

func run() -> void:
	root.content_scale_size=Vector2i.ZERO
	root.size=Vector2i(1280,720)
	game=IsolatedSession.new()
	game.fixture_path=fixture_root
	root.add_child(game)
	await settle()
	game.launch_job("M01")
	await settle()
	game.pilot.freeze=true
	var original_run=game.run_id
	await click_retry("formal mission")
	check(str(game.current_job.get("id",""))=="M01" and not bool(game.current_job.get("training",false)),"Formal retry retains mission semantics")
	check(game.run_id==original_run,"Formal retry resumes existing campaign run")
	game.show_hangar()
	await settle()
	game.launch_exploration("R1")
	await settle()
	game.pilot.freeze=true
	var prior_exploration=snapshot()
	await click_retry("free exploration")
	check(bool(game.current_job.get("exploration",false)) and str(game.current_job.get("region_id",""))=="R1","Exploration retry relaunches the same region")
	check(snapshot()==prior_exploration,"Exploration retry leaves formal checkpoint and progression unchanged")
	game.show_hangar()
	await settle()
	# Explicit progression fixture, not a gameplay-completion claim: suspend a
	# different formal mission to prove practice cannot replace that checkpoint.
	var completed_stages: Array = []
	for stage in game.get_job("M01").stages: completed_stages.append(stage.id)
	var setup=game.repository.commit({"id":"retry-fixture:unlock-M02","set":{"campaign.completed_missions":["M01"],"campaign.completed_stages":completed_stages}})
	check(bool(setup.get("ok",false)),"Fixture unlocks M02 through validated repository transaction")
	game.launch_job("M02")
	await settle()
	game.pilot.freeze=true
	game.show_hangar()
	await settle()
	check(str(game.repository.data.campaign.active_checkpoint.get("job_id",""))=="M02","A different formal M02 checkpoint is suspended before practice")
	game.launch_tutorial_practice("M01")
	await settle()
	game.pilot.freeze=true
	var prior_practice=snapshot()
	await click_retry("independent practice")
	check(bool(game.current_job.get("training",false)) and bool(game.current_job.get("loaner",false)),"Practice retry remains an independent loaner session")
	check(game.stage_index==0 and game.run_id.begins_with("training:"),"Practice retry starts a fresh practice run")
	check(snapshot()==prior_practice,"Practice retry leaves formal checkpoint and progression unchanged")
	game.show_hangar()
	await settle()
	print("WORLDUI_RETRY_SUMMARY ",JSON.stringify({"checks":checks,"failed":failures.size(),"failures":failures,"fixture_root":fixture_root,"scope":"Headless actual native Button.pressed callbacks and Session launch flow. Explicit failure fixture, no pointer/controller hardware, combat-completion, visual-quality or performance claim."}))
	game.queue_free()
	await settle()
	quit(0 if failures.is_empty() else 1)
