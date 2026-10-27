extends SceneTree

class FixtureSession:
	extends "res://scripts/v2/session.gd"
	var sound_events: Array[String] = []
	func _ready() -> void: pass
	func _process(_delta: float) -> void: pass
	func _physics_process(_delta: float) -> void: pass
	func _notification(_what: int) -> void: pass
	func play_sound(event: String) -> void: sound_events.append(event)
	func list_profiles() -> Array: return [{"id":"fixture","name":"布局测试员","active":true,"parts":72,"completed":0,"kind":"normal"}]

var failures: Array[String] = []
var checks = 0
var game: FixtureSession

func _initialize() -> void:
	call_deferred("run")

func check(value: bool, description: String) -> void:
	checks += 1
	if not value:
		failures.append(description)
		print("UI_LAYOUT_V2_FAIL ",description)

func settle() -> void:
	for index in range(4): await process_frame

func run() -> void:
	root.content_scale_size = Vector2i.ZERO
	game = FixtureSession.new()
	root.add_child(game)
	game.content = CatalogV2.content()
	game.repository = SaveRepositoryV2.new("user://qa_v2/ui_layout_"+str(Time.get_ticks_usec()))
	game.repository.load_profile()
	game.active_build = CatalogV2.default_build()
	game.input = PilotInputV2.new()
	game.add_child(game.input)
	game.phone = PhoneServerV2.new()
	game.add_child(game.phone)
	game.ui = GameInterfaceV2.new()
	game.ui.session = game
	game.add_child(game.ui)
	for dimensions in [Vector2i(1280,720),Vector2i(1920,1080),Vector2i(1024,768)]:
		root.size = dimensions
		await settle()
		for scale in [1.0,1.25,1.5]:
			game.ui.apply_scale(scale)
			for page in ["主页","任务","机库","配装","挑战","世界","教学","设置","手机"]:
				game.ui.show_hangar(page)
				await settle()
				validate_frame(str(dimensions)+" "+str(scale)+" "+page)
				var has_art = game.ui.panel.get_node_or_null("WaterfrontMenuArt") != null
				check(not has_art,"all V2.2 lobby pages preserve actual 3D workshop "+page)
				check(game.ui.lobby_top != null and game.ui.lobby_nav != null and game.ui.lobby_bottom != null,"native profile/navigation/departure controls remain available "+page)
			game.ui.show_briefing(game.content.missions[0])
			await settle()
			validate_frame(str(dimensions)+" "+str(scale)+" briefing")
	game.ui.show_hangar("设置")
	await settle()
	var preview_button = find_button(game.ui.panel,"试听声音")
	check(preview_button != null,"settings has a native sound preview button")
	if preview_button != null: preview_button.pressed.emit()
	check(not game.sound_events.is_empty(),"sound preview button invokes session audio callback")
	check(find_button(game.ui.panel,"恢复默认音量") != null,"settings has a native default-volume button")
	check(find_button(game.ui.panel,"关于与素材鸣谢") != null,"settings exposes visible source credits")
	game.ui.show_credits()
	await settle()
	validate_frame("credits")
	check(find_button(game.ui.panel,"返回设置") != null,"credits has a native return button")
	game.world = RegionWorldV2.new()
	game.world.configure(game.content.regions[0],false,game.repository.data.world)
	game.world.scenery_hint = "F 互动 · 切换街区起降引导灯"
	game.pilot = FlightBodyV2.new()
	game.pilot.configure(CatalogV2.resolve_build(CatalogV2.default_build()))
	game.pilot.freeze = true
	game.add_child(game.pilot)
	game.current_job = {"id":"explore:R1","name":"自由探索"}
	game.flight_active = true
	for dimensions in [Vector2i(1280,720),Vector2i(1920,1080),Vector2i(1024,768)]:
		root.size = dimensions
		await settle()
		for scale in [1.0,1.25,1.5]:
			game.ui.apply_scale(scale)
			game.ui.show_hud()
			await settle()
			var ui = game.ui
			var viewport = Rect2(Vector2.ZERO,ui.root.size).grow(1)
			for card in [ui.hud_task_panel,ui.hud_control_panel,ui.hud_telemetry_panel]:
				check(viewport.encloses(card.get_global_rect()),"HUD card in viewport "+str(dimensions)+" scale "+str(scale)+" "+card.name)
			check(not ui.hud_task_panel.get_global_rect().intersects(ui.hud_control_panel.get_global_rect()),"HUD task does not cover native controls")
			check(not ui.hud_telemetry_panel.get_global_rect().intersects(ui.hud_task_panel.get_global_rect()),"HUD telemetry does not cover task card")
			check(ui.hud_hint.text == game.world.scenery_hint,"world scenery interaction hint reaches HUD")
			if ui.hud_map_frame.visible:
				check(not ui.hud_map_frame.get_global_rect().intersects(ui.hud_controls.get_global_rect()),"minimap stays outside button bounds")
	game.world.free()
	game.queue_free()
	await process_frame
	print("UI_LAYOUT_V2_SUMMARY ",JSON.stringify({"checks":checks,"failures":failures,"ok":failures.is_empty(),"scope":"V2.2 native lobby/briefing/credits geometry and callbacks at 1280x720, 1920x1080, 1024x768 and 100/125/150 percent font sizes; no GPU visual, controller or human comfort evidence."}))
	quit(0 if failures.is_empty() else 1)

func validate_frame(context: String) -> void:
	var ui = game.ui
	var viewport = Rect2(Vector2.ZERO,ui.root.size).grow(1)
	var frames: Array = [ui.shell_frame] if is_instance_valid(ui.shell_frame) else [ui.lobby_top,ui.lobby_nav,ui.lobby_bottom,ui.lobby_drawer,ui.lobby_home,ui.lobby_tools]
	var buttons: Array[Button] = []
	for container in frames:
		if not is_instance_valid(container) or not container.visible: continue
		check(viewport.encloses(container.get_global_rect()),"native panel inside viewport "+context+" "+container.name+" actual="+str(container.get_global_rect()))
		check(container.size.x < ui.root.size.x,"menu retains visible 3D world margin "+context)
		buttons.clear()
		collect_buttons(container,buttons)
		for button in buttons:
			if not button.is_visible_in_tree(): continue
			var bounds = button.get_global_rect()
			var frame = container.get_global_rect().grow(1)
			check(bounds.position.x >= frame.position.x and bounds.end.x <= frame.end.x,"button horizontal fit "+context+" "+button.text)
			check(button.focus_mode != Control.FOCUS_NONE,"native menu button supports keyboard focus "+context+" "+button.text)

func collect_buttons(node: Node, result: Array[Button]) -> void:
	if node is Button: result.append(node)
	for child in node.get_children(): collect_buttons(child,result)

func find_button(node: Node, text: String) -> Button:
	if node is Button and node.text == text: return node
	for child in node.get_children():
		var found = find_button(child,text)
		if found != null: return found
	return null
