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
var visits: Array[String] = []
var geometry: Array[Dictionary] = []

func _initialize() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--ui-smoke-root="): fixture_root = argument.trim_prefix("--ui-smoke-root=").replace("\\","/")
	if fixture_root.is_empty() or not fixture_root.is_absolute_path() or DirAccess.dir_exists_absolute(fixture_root):
		printerr("Requires a fresh absolute --ui-smoke-root=<temporary directory>; existing fixtures and player data are never reused.")
		quit(2)
		return
	call_deferred("run")

func check(value: bool, description: String) -> void:
	checks += 1
	if not value:
		failures.append(description)
		print("WORLDUI_SMOKE_FAIL ",description)

func settle(frames = 6) -> void:
	for tick in frames: await process_frame

func controls(node: Node, result: Array[Button]) -> void:
	if node is Button and node.is_visible_in_tree(): result.append(node)
	for child in node.get_children(): controls(child,result)

func tagged(id: String) -> Button:
	var control: Variant = game.ui.action_controls.get(id)
	return control if control is Button else null

func named(label: String, index = 0) -> Button:
	var found: Array[Button] = []
	controls(game.ui.panel,found)
	var matches: Array[Button] = []
	for button in found:
		if button.text == label: matches.append(button)
	return matches[index] if matches.size()>index else null

func click(button: Button, description: String) -> bool:
	check(is_instance_valid(button),"Button exists: "+description)
	if not is_instance_valid(button): return false
	check(button.is_visible_in_tree() and not button.disabled,"Button usable: "+description)
	if not button.is_visible_in_tree() or button.disabled: return false
	var ancestor = button.get_parent()
	while ancestor != null:
		if ancestor is ScrollContainer: ancestor.ensure_control_visible(button)
		ancestor = ancestor.get_parent()
	button.grab_focus()
	await settle(2)
	check(root.gui_get_focus_owner()==button,"Native focus reaches "+description)
	button.pressed.emit()
	visits.append(description)
	await settle()
	return true

func click_tag(id: String) -> bool:
	if id in ["device","settings","tutorial"]:
		var target = tagged(id)
		if is_instance_valid(target) and not target.is_visible_in_tree():
			if not await click(tagged("auxiliary"),"open auxiliary for "+id): return false
	return await click(tagged(id),id)

func click_text(label: String, index = 0) -> bool:
	return await click(named(label,index),label)

func focus_present(context: String) -> void:
	var owner = root.gui_get_focus_owner()
	check(is_instance_valid(owner) and owner.is_visible_in_tree(),"Focus restored after "+context)

func validate_lobby(context: String) -> void:
	var ui = game.ui
	var bounds = Rect2(Vector2.ZERO,ui.root.size).grow(1)
	var frames: Array = [ui.lobby_top,ui.lobby_nav,ui.lobby_bottom,ui.lobby_drawer,ui.lobby_home]
	for frame in frames:
		if not is_instance_valid(frame): continue
		check(bounds.encloses(frame.get_global_rect()),"Frame fits "+context+" "+frame.name)
	for i in frames.size():
		if not is_instance_valid(frames[i]): continue
		for j in range(i+1,frames.size()):
			if not is_instance_valid(frames[j]): continue
			var overlap = frames[i].get_global_rect().intersection(frames[j].get_global_rect())
			check(overlap.size.x<2 or overlap.size.y<2,"Panels do not overlap "+context+" "+frames[i].name+" / "+frames[j].name)
			if overlap.size.x>=2 and overlap.size.y>=2: geometry.append({"case":context,"a":str(frames[i].name),"b":str(frames[j].name),"overlap":str(overlap)})
	focus_present(context)

func validate_tour(context: String) -> void:
	var card = game.ui.lobby_tour_panel
	var spotlight = game.ui.lobby_tour_spotlight
	check(is_instance_valid(card) and is_instance_valid(spotlight),"Tour exists "+context)
	if not is_instance_valid(card) or not is_instance_valid(spotlight): return
	var target = spotlight.target
	check(is_instance_valid(target) and target.is_visible_in_tree(),"Tour target visible "+context)
	check(root.gui_get_focus_owner()==target,"Tour focuses actual target "+context)
	check(Rect2(Vector2.ZERO,game.ui.root.size).grow(1).encloses(card.get_global_rect()),"Tour card fits "+context)
	check(not card.get_global_rect().intersects(target.get_global_rect()),"Tour leaves target clickable "+context)

func run() -> void:
	root.content_scale_size = Vector2i.ZERO
	root.size = Vector2i(1280,720)
	game = IsolatedSession.new()
	game.fixture_path = fixture_root
	root.add_child(game)
	await settle()
	for dimensions in [Vector2i(1280,720),Vector2i(1920,1080),Vector2i(1024,768)]:
		root.size = dimensions
		await settle()
		for scale in [1.0,1.25,1.5]:
			game.ui.apply_scale(scale)
			await click_tag("page_主页")
			validate_lobby(str(dimensions)+" / "+str(scale)+" home")
			await click_tag("page_任务")
			validate_lobby(str(dimensions)+" / "+str(scale)+" regions")
			var nav: Array[Button] = []
			controls(game.ui.lobby_nav,nav)
			check(nav.size()==3,"Three primary actions "+str(dimensions)+" / "+str(scale))
			for id in ["R1","R2","R3","R4"]:
				await click_tag("region_"+id)
				check(game.region_id==id,"Region button selects "+id)
				var layout = RegionLayoutWorldUI.get_layout(id)
				check(not layout.get("land",[]).is_empty() and not layout.get("roads",[]).is_empty(),"Preview uses authored land/routes "+id)
			await click_tag("page_机库")
			validate_lobby(str(dimensions)+" / "+str(scale)+" fleet")
			await click_tag("page_配装")
			validate_lobby(str(dimensions)+" / "+str(scale)+" loadout")
			await click_tag("page_挑战")
			validate_lobby(str(dimensions)+" / "+str(scale)+" challenges")
			await click_tag("page_世界")
			validate_lobby(str(dimensions)+" / "+str(scale)+" world")
			await click_tag("page_记录")
			focus_present("records "+str(dimensions)+" / "+str(scale))
			await click_text("×")
			for id in ["device","settings","tutorial"]:
				await click_tag(id)
				validate_lobby(str(dimensions)+" / "+str(scale)+" "+id)
			await click_tag("auxiliary")
			check(game.ui.auxiliary_open and game.ui.lobby_tools.is_visible_in_tree(),"Auxiliary menu opens")
			check(Rect2(Vector2.ZERO,game.ui.root.size).grow(1).encloses(game.ui.lobby_tools.get_global_rect()),"Auxiliary menu fits "+str(dimensions)+" / "+str(scale))
			await click_tag("auxiliary")
			check(not game.ui.auxiliary_open and not tagged("device").is_visible_in_tree(),"Auxiliary menu collapses")
			focus_present("collapse auxiliary")
	# All native tour buttons remain reachable, including auto-opened auxiliary targets.
	for dimensions in [Vector2i(1280,720),Vector2i(1920,1080),Vector2i(1024,768)]:
		root.size = dimensions
		game.ui.apply_scale(1.5)
		await click_tag("page_任务")
		await click_tag("region_R1")
		await click_tag("tutorial")
		await click_text("从头重播漫游")
		for id in ["page_任务","page_机库","page_配装","device","settings","tutorial","departure"]:
			validate_tour(str(dimensions)+" / "+id)
			await click_tag(id)
		check(game.ui.get_lobby_tour_state().get("status","")=="completed","Native tour completes at "+str(dimensions))
		check(not game.flight_active and not game.ui.prepared_job.is_empty(),"Tour opens briefing without automatic flight")
		await click_text("×")
	root.size=Vector2i(1280,720)
	game.ui.apply_scale(1.0)
	await click_tag("page_任务")
	await click_tag("region_R4")
	await click_tag("departure")
	check(game.region_id=="R4" and game.ui.prepared_job.is_empty() and game.ui.screen_mode=="lobby","Locked selected region cannot open an unrelated R1 mission")
	await click_tag("profiles")
	focus_present("profiles")
	await click_text("进入此档案",1)
	check(game.is_sandbox(),"Native profile button enters isolated sandbox")
	await click_tag("page_任务")
	await click_tag("region_R4")
	await click_tag("departure")
	check(str(game.ui.prepared_job.get("region_id",""))=="R4","Departure respects the selected region instead of silently opening R1")
	await click_text("前往配装")
	focus_present("preflight loadout remedy")
	await click_text("保存配装")
	await click_text("返回出航简报")
	focus_present("return from loadout to briefing")
	check(game.ui.action_controls.get("launch") is Button,"Briefing requires explicit launch")
	await click_text("×")
	await click_tag("settings")
	await click_text("关于与素材鸣谢")
	focus_present("credits")
	await click_text("返回设置")
	await click_tag("profiles")
	await click_text("进入此档案",0)
	check(not game.is_sandbox() and game.ui.prepared_job.is_empty(),"Profile switch resets prepared job and restores normal balance")
	await click_tag("page_任务")
	await click_tag("region_R1")
	await click_tag("departure")
	await click_tag("launch")
	check(game.flight_active,"Native launch enters actual flight session")
	if game.flight_active:
		# Freeze only the UI fixture after legitimate launch; not route completion evidence.
		game.pilot.freeze = true
		game.ui.update_hud()
		check(game.ui.hud_stats.text.begins_with("离地高度 "),"Telemetry names ground-relative height explicitly")
		var target_offset: Vector3 = game.runner.target_position()-game.pilot.global_position
		check(game.ui.hud_target.text == "目标 %.0fm · 高差 %+.1fm" % [Vector2(target_offset.x,target_offset.z).length(),target_offset.y],"Task card reports the actual signed target height")
		await click_text("暂停")
		focus_present("pause")
		await click_text("服务柜")
		focus_present("service modal")
		await click_text("继续飞行")
		await click_text("暂停")
		await click_text("飞行设置")
		focus_present("flight settings")
		await click_text("×")
		await click_text("暂停")
		await click_text("区域地图")
		focus_present("overview")
		await click_text("继续飞行")
		game.fail_run("UI smoke fixture failure event")
		await settle()
		focus_present("failure result")
		check(named("再次出航")!=null and named("返回机库")!=null,"Result exposes real retry and hangar actions")
		await click_text("返回机库")
		focus_present("return to hangar")
	print("WORLDUI_UI_SMOKE_SUMMARY ",JSON.stringify({"checks":checks,"failed":failures.size(),"failures":failures,"geometry":geometry,"visits":visits,"fixture_root":fixture_root,"scope":"Native UI callbacks, actual Session in an isolated profile root, UI geometry/focus at 3 resolutions x 3 text scales. Automated fixture only; no pointer/controller hardware, flight-route completion or graphics-quality claims."}))
	game.queue_free()
	await settle()
	quit(0 if failures.is_empty() else 1)
