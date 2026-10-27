extends SceneTree
## Owner-run headless native UI integration test; no mocks of tour progression.
## All profile reads/writes, including the first lobby, use a fresh QA catalog.
var game: GameSessionV2
var qa_case = ""
var fixture_root = ""
var checks = 0
var failures: Array[String] = []
var baselines: Dictionary = {}
var visited: Array = []
const STEPS = ["page_任务","page_机库","page_配装","device","settings","tutorial","departure"]

func _initialize() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--v2-qa=lobby_tour_"): qa_case = argument.trim_prefix("--v2-qa=").validate_filename()
	if qa_case.is_empty() or DisplayServer.get_name() != "headless":
		printerr("Requires headless and a fresh --v2-qa=lobby_tour_<case>; never uses player profiles.")
		quit(2)
		return
	fixture_root = "user://qa_v22/"+qa_case
	if DirAccess.dir_exists_absolute(fixture_root) or DirAccess.dir_exists_absolute("user://qa_v2/session_"+qa_case):
		printerr("Choose a fresh lobby_tour case. Existing QA fixtures are preserved.")
		quit(2)
		return
	call_deferred("_run")

func check(condition: bool, description: String) -> void:
	checks += 1
	if not condition: failures.append(description)
	print("LOBBY_TOUR_CHECK ",JSON.stringify({"pass":condition,"check":description}))

func settle() -> void:
	for tick in 5: await process_frame

func _protected_snapshot(repo: SaveRepositoryV2) -> Dictionary:
	var data: Dictionary = repo.data
	return {"wallet":data.wallet.duplicate(true),"campaign":data.campaign.duplicate(true),"records":data.records.duplicate(true),"builds":data.builds.duplicate(true),"owned_airframes":data.owned_airframes.duplicate(),"owned_modules":data.owned_modules.duplicate(),"flight_tutorial":data.settings.get("tutorial_v22",{}).duplicate(true)}

func _state() -> Dictionary:
	return game.ui.get_lobby_tour_state()

func _click_tag(id: String) -> bool:
	# Auxiliary actions are still real Buttons, reached by the real menu trigger.
	if id in ["device","settings","tutorial"]:
		var target: Variant = game.ui.action_controls.get(id)
		if is_instance_valid(target) and not target.is_visible_in_tree():
			if not await _click_tag("auxiliary"): return false
	var candidate: Variant = game.ui.action_controls.get(id)
	if not candidate is Button or not is_instance_valid(candidate):
		check(false,"Real tagged Button exists: "+id)
		return false
	var button: Button = candidate
	check(button.is_visible_in_tree() and not button.disabled,"Real button is available: "+id)
	if button.disabled or not button.is_visible_in_tree(): return false
	# Emit the actual native Button signal, exercising the production wrapper,
	# page action, pressed callback and durable save. Never call tour advance.
	button.pressed.emit()
	await settle()
	return true

func _find_buttons(node: Node, label: String, result: Array[Button]) -> void:
	if node is Button and node.text == label and node.is_visible_in_tree(): result.append(node)
	for child in node.get_children(): _find_buttons(child,label,result)

func _click_text(label: String, scope: Node = null) -> bool:
	var matches: Array[Button] = []
	_find_buttons(game.ui.root if scope == null else scope,label,matches)
	check(matches.size() == 1,"One native button labelled "+label)
	if matches.size() != 1: return false
	check(not matches[0].disabled,"Button enabled: "+label)
	if matches[0].disabled: return false
	matches[0].pressed.emit()
	await settle()
	return true

func _switch_profile(index: int) -> void:
	game.ui.show_hangar("主页")
	await settle()
	await _click_tag("profiles")
	var matches: Array[Button] = []
	_find_buttons(game.ui.panel,"进入此档案",matches)
	check(matches.size() == 3,"Profile selector exposes all three real profile buttons")
	if matches.size() != 3: return
	matches[index].pressed.emit()
	await settle()
	var id: String = ProfileCatalogV22.IDS[index]
	check(game.profiles.selected == id and game.repository.root_path == fixture_root+"/profiles/"+id,"Native profile button selects isolated "+id)

func _assert_protected(label: String) -> void:
	for id in ProfileCatalogV22.IDS:
		var repo = game.profiles.open_profile(id)
		check(_protected_snapshot(repo) == baselines[id],label+": gameplay and flight tutorial unchanged in "+id)

func _run() -> void:
	root.size = Vector2i(1280,720)
	game = GameSessionV2.new()
	# Install the isolated profile catalog BEFORE _ready() builds the real UI.
	game.profiles = ProfileCatalogV22.new(fixture_root+"/profiles",fixture_root+"/nonexistent_legacy_source")
	game.profiles.initialize()
	for id in ProfileCatalogV22.IDS: baselines[id] = _protected_snapshot(game.profiles.open_profile(id))
	root.add_child(game)
	await settle()
	check(game.qa_mode and game.repository.root_path == "user://qa_v2/session_"+qa_case,"Session itself uses the requested QA repository")
	if not game.qa_mode or not game.repository.root_path.begins_with("user://qa_"):
		check(false,"Refuse non-QA session")
		_finish()
		return
	await _switch_profile(0)
	check(_state().is_empty(),"Fresh profile has no invented lobby progress")
	game.ui.start_lobby_tour()
	await settle()
	check(_state().get("index",-1) == 0 and _state().get("status","") == "in_progress","Explicit start begins first step")
	check(is_instance_valid(game.ui.lobby_tour_panel),"Native tour card is shown")
	if not is_instance_valid(game.ui.lobby_tour_panel):
		_finish()
		return
	for dimensions in [Vector2i(1280,720),Vector2i(1920,1080),Vector2i(1024,768)]:
		for scale in [1.0,1.25,1.5]:
			root.size = dimensions
			game.ui.apply_scale(scale)
			await settle()
			var viewport = Rect2(Vector2.ZERO,game.ui.root.size).grow(1)
			check(viewport.encloses(game.ui.lobby_tour_panel.get_global_rect()),"Tour card fits "+str(dimensions)+" / "+str(scale))
			check(not game.ui.lobby_tour_panel.get_global_rect().intersects(game.ui.lobby_tour_spotlight.target.get_global_rect()),"Tour leaves actual target clickable "+str(dimensions)+" / "+str(scale))
	root.size = Vector2i(1280,720)
	game.ui.apply_scale(1.0)
	await settle()
	for index in STEPS.size():
		check(int(_state().get("index",-1)) == index,"Step index before real click "+str(index+1))
		# Visiting another real page must not substitute for the requested action.
		await _click_tag("page_主页")
		check(int(_state().get("index",-1)) == index,"Wrong native button does not advance step "+str(index+1))
		check(game.ui.lobby_tour_spotlight.target == game.ui.action_controls.get(STEPS[index]),"Spotlight follows real step button "+str(index+1))
		check(get_root().gui_get_focus_owner() == game.ui.lobby_tour_spotlight.target,"Keyboard focus is the highlighted button "+str(index+1))
		var clicked = await _click_tag(STEPS[index])
		if not clicked: break
		visited.append(STEPS[index])
		check(int(_state().get("index",-1)) == index+1,"Only correct native click advances step "+str(index+1))
	check(visited == STEPS,"All seven actual page/departure buttons were pressed in order")
	check(_state().get("status","") == "completed" and bool(_state().get("completed",false)),"Seventh real click completes the tour")
	check(not game.flight_active and not game.ui.prepared_job.is_empty() and game.current_job.is_empty(),"Departure opens a concrete briefing without starting flight")
	check(game.ui.action_controls.get("launch") is Button,"Briefing still requires the separate actual launch button")
	_assert_protected("Full tour")
	game.show_hangar()
	await settle()
	check(not is_instance_valid(game.ui.lobby_tour_panel) and _state().status == "completed","Completed tour does not restart on hangar reentry")
	await _click_tag("tutorial")
	await _click_text("从头重播漫游")
	check(int(_state().index) == 0 and bool(_state().replaying),"Native replay starts step zero")
	await _click_tag("page_任务")
	await _click_text("稍后继续",game.ui.lobby_tour_panel)
	check(_state().status == "deferred" and int(_state().index) == 1,"Later retains the achieved step")
	game.show_hangar()
	await settle()
	check(not is_instance_valid(game.ui.lobby_tour_panel) and _state().status == "deferred","Deferred tour remains quiet on reentry")
	await _click_tag("tutorial")
	await _click_text("继续大厅漫游")
	check(_state().status == "in_progress" and int(_state().index) == 1,"Native continue resumes the saved step")
	await _click_tag("page_机库")
	await _click_text("跳过漫游",game.ui.lobby_tour_panel)
	check(_state().status == "skipped" and int(_state().index) == 2,"Skip saves its position without marking new completion")
	game.show_hangar()
	await settle()
	check(not is_instance_valid(game.ui.lobby_tour_panel) and _state().status == "skipped","Skipped tour stays quiet on reentry")
	await _click_tag("tutorial")
	await _click_text("从头重播漫游")
	await _click_tag("page_任务")
	var default_progress = _state().duplicate(true)
	await _switch_profile(1)
	check(_state().is_empty() and not is_instance_valid(game.ui.lobby_tour_panel),"Second QA profile does not inherit first profile tour")
	game.ui.start_lobby_tour()
	await settle()
	await _click_tag("page_任务")
	await _click_tag("page_机库")
	await _click_text("稍后继续",game.ui.lobby_tour_panel)
	var second_progress = _state().duplicate(true)
	await _switch_profile(0)
	check(_state() == default_progress and is_instance_valid(game.ui.lobby_tour_panel),"First profile independently resumes its in-progress step")
	await _switch_profile(1)
	check(_state() == second_progress and not is_instance_valid(game.ui.lobby_tour_panel),"Second profile independently retains its deferred step")
	await _switch_profile(2)
	check(_state().is_empty(),"Third QA profile remains untouched")
	game.ui.start_lobby_tour()
	await settle()
	await _click_text("跳过漫游",game.ui.lobby_tour_panel)
	check(_state().status == "skipped" and not bool(_state().completed) and int(_state().index) == 0,"Skipping a fresh tour never claims completion")
	game.show_hangar()
	await settle()
	check(not is_instance_valid(game.ui.lobby_tour_panel),"Fresh skipped tour does not reappear automatically")
	_assert_protected("Replay, skip, later, resume, and profile switches")
	check(not game.flight_active,"No tour operation launched a mission")
	_finish()

func _finish() -> void:
	print("V22_LOBBY_TOUR_RESULT ",JSON.stringify({"suite":"V22_lobby_tour_native_ui","case":qa_case,"checks":checks,"failures":failures,"passed":failures.is_empty(),"visited_buttons":visited,"fixture_root":fixture_root,"scope":"Actual GameSession and native Button.pressed callbacks with separate persisted QA profiles. Headless layout/state evidence, not human click, visual quality, GPU, or controller evidence."},"",true,true))
	quit(0 if failures.is_empty() else 1)
