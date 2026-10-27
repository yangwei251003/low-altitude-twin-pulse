class_name GameInterfaceV2
extends CanvasLayer

const MENU_ART = "res://assets/v2/ui/waterfront_menu.png"
const INK = Color("102b35")
const MINT = Color("97ead2")
const PAPER = Color("f1f4e9")
const MUTED = Color("a9bec4")
const LOBBY_TOUR = [
	["page_任务","找到本次航线","点击左侧「出航」。这里查看航线顺序、奖励和出航简报。"],
	["page_机库","认识你的飞机","点击「整备」，查看已拥有的机体。中央展示的是实际三维飞机。"],
	["page_配装","进入装配工作台","点击「配装」。机身上的工具会随真实配装变化，出航前在这里检查。"],
	["device","确认操控设备","点击「设备」。连接手机手柄或检查当前设备；现在不必立即配对。"],
	["settings","调整舒适度","点击「设置」。可调整字号、音量、操控和环境强度，按自己的节奏飞行。"],
	["tutorial","找到实飞课程","点击「教学」。实飞课程根据真实操作推进，与这个大厅漫游分别保存。"],
	["departure","准备开始航行","点击「准备出航」查看简报。看清目标后再确认起飞，漫游不会替你出航。"]
]

var session: GameSessionV2
var root: Control
var panel: Control
var toast_label: Label
var toast_clock = 0.0
var font_scale = 1.0
var draft: Dictionary = {}
var hud_title: Label
var hud_action: Label
var hud_condition: Label
var hud_stats: Label
var hud_target: Label
var hud_bar: ProgressBar
var minimap: MapSurface
var hud_overlay: NavigationOverlay
var phone_status: Label
var phone_code: Label
var bind_action = ""
var modal_open = false
var screen_mode = ""
var shell_frame: PanelContainer
var brand_block: Control
var frame_caption: Control
var hud_task_panel: PanelContainer
var hud_control_panel: PanelContainer
var hud_telemetry_panel: PanelContainer
var hud_region: Label
var hud_quality: Label
var hud_service: Button
var hud_hint: Label
var hud_controls: HBoxContainer
var hud_map_frame: PanelContainer
var lobby_top: PanelContainer
var lobby_nav: PanelContainer
var lobby_tools: PanelContainer
var auxiliary_open = false
var lobby_bottom: PanelContainer
var lobby_drawer: PanelContainer
var lobby_home: Control
var tutorial_panel: PanelContainer
var tutorial_title: Label
var tutorial_text: Label
var tutorial_keys: Label
var tutorial_progress: ProgressBar
var tutorial_highlight: TutorialHighlight
var action_controls: Dictionary = {}
var tutorial_cache = ""
var _tutorial_source: Node
var _splash_next: Callable
var _splash_clock = 0.0
var _splash_done = false
var _map: MapSurface
var prepared_job: Dictionary = {}
var overview_header: PanelContainer
var overview_inset: PanelContainer
var lobby_tour_panel: PanelContainer
var lobby_tour_spotlight: LobbySpotlight
var _lobby_tour_voice_key = ""

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	root = Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	var theme = Theme.new()
	theme.default_font = load("res://assets/fonts/NotoSansSC-Medium.ttf")
	theme.default_font_size = 17
	theme.set_color("font_color","Label",PAPER)
	theme.set_color("font_color","Button",PAPER)
	theme.set_color("font_disabled_color","Button",Color("72878c"))
	for type in ["Button","OptionButton"]:
		theme.set_stylebox("normal",type,_style(Color("1c3c47"),Color("355660")))
		theme.set_stylebox("hover",type,_style(Color("2c5660"),MINT))
		theme.set_stylebox("pressed",type,_style(Color("356b68"),MINT))
		theme.set_stylebox("disabled",type,_style(Color("192c34"),Color("293f47")))
		theme.set_stylebox("focus",type,_style(Color(0,0,0,0),MINT))
	theme.set_stylebox("background","ProgressBar",_style(Color("173b43")))
	theme.set_stylebox("fill","ProgressBar",_style(Color("87d4b8")))
	theme.set_constant("separation","VBoxContainer",9)
	theme.set_constant("separation","HBoxContainer",9)
	theme.set_constant("h_separation","HFlowContainer",7)
	theme.set_constant("v_separation","HFlowContainer",7)
	theme.set_constant("scrollbar_width","VScrollBar",8)
	root.theme = theme
	root.resized.connect(_layout)
	toast_label = Label.new()
	toast_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	toast_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	toast_label.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	toast_label.offset_top = -52
	toast_label.offset_bottom = -14
	toast_label.offset_left = 24
	toast_label.offset_right = -24
	toast_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	toast_label.add_theme_color_override("font_color",Color("e6deb0"))
	toast_label.add_theme_color_override("font_outline_color",Color("0e242b"))
	toast_label.add_theme_constant_override("outline_size",5)
	root.add_child(toast_label)
	tutorial_highlight = TutorialHighlight.new()
	tutorial_highlight.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tutorial_highlight.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(tutorial_highlight)

func _style(color: Color, border = Color.TRANSPARENT) -> StyleBoxFlat:
	var box = StyleBoxFlat.new()
	box.bg_color = color
	box.border_color = border
	box.set_border_width_all(1 if border.a>0 else 0)
	box.set_corner_radius_all(10)
	box.content_margin_left = 14
	box.content_margin_right = 14
	box.content_margin_top = 11
	box.content_margin_bottom = 11
	return box

func apply_scale(value: float) -> void:
	font_scale = clampf(value,1.0,1.5)
	if is_instance_valid(root):
		root.theme.default_font_size = int(17*font_scale)
		_rescale(root)
		_layout.call_deferred()

func _rescale(node: Node) -> void:
	if node is Control and node.has_meta("base_font_size"):
		node.add_theme_font_size_override("font_size",int(float(node.get_meta("base_font_size"))*font_scale))
	if node is Button and not node is CheckBox: node.custom_minimum_size.y = 42*font_scale
	if node is Button and node.text == "×": node.custom_minimum_size.x = 48*font_scale
	for child in node.get_children(): _rescale(child)

func _clear() -> void:
	_hide_lobby_tour()
	if is_instance_valid(panel): panel.queue_free(); root.remove_child(panel)
	panel = Control.new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(panel)
	root.move_child(toast_label,-1)
	if is_instance_valid(tutorial_highlight): root.move_child(tutorial_highlight,-1)
	phone_status = null
	lobby_top = null
	lobby_nav = null
	lobby_tools = null
	auxiliary_open = false
	lobby_bottom = null
	lobby_drawer = null
	lobby_home = null
	tutorial_panel = null
	action_controls.clear()
	_map = null
	overview_header = null
	overview_inset = null
	if is_instance_valid(tutorial_highlight): tutorial_highlight.target = null; tutorial_highlight.queue_redraw()
	modal_open = false
	shell_frame = null
	brand_block = null
	frame_caption = null
	hud_task_panel = null
	hud_control_panel = null
	hud_telemetry_panel = null
	hud_map_frame = null
	hud_stats = null
	hud_target = null
	hud_service = null

func _label(parent: Node, text: String, size_px = 18, color = Color("e2ebe8")) -> Label:
	var label = Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size",int(size_px*font_scale))
	label.set_meta("base_font_size",size_px)
	label.add_theme_color_override("font_color",color)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(label)
	return label

func _button(parent: Node, text: String, action: Callable, hint = "") -> Button:
	var button = Button.new()
	button.text = text
	button.tooltip_text = hint if not hint.is_empty() else text
	button.custom_minimum_size.y = 42*font_scale
	button.custom_minimum_size.x = 48*font_scale if text == "×" else 42
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	button.clip_text = true
	button.focus_mode = Control.FOCUS_ALL
	button.pressed.connect(func():
		var clicked_action = str(button.get_meta("tutorial_action",""))
		session.play_sound("ui")
		action.call()
		_lobby_tour_action(clicked_action)
		if session.flight_active and not get_tree().paused and is_instance_valid(button) and button.is_inside_tree(): button.release_focus())
	parent.add_child(button)
	return button

func _tag(control: Control, id: String) -> Control:
	control.set_meta("tutorial_action", id)
	action_controls[id] = control
	return control

func _tutorial() -> Node:
	var candidate: Variant = session.get("tutorial")
	return candidate if candidate is Node and is_instance_valid(candidate) else null

func _ui_action(id: String) -> void:
	var director = _tutorial()
	if director != null: director.on_ui_action(id)

func _focus_first(node: Node = null) -> void:
	if node == null: node = panel
	if not is_instance_valid(node): return
	var candidates: Array[Button] = []
	_focus_candidates(node,candidates)
	for button in candidates:
		if bool(button.get_meta("primary_action",false)):
			button.grab_focus()
			return
	if not candidates.is_empty(): candidates[0].grab_focus()

func _focus_candidates(node: Node, candidates: Array[Button]) -> void:
	if node is Control and not node.is_visible_in_tree(): return
	if node is Button and not node.disabled and node.focus_mode != Control.FOCUS_NONE:
		candidates.append(node)
	for child in node.get_children(): _focus_candidates(child,candidates)

func _primary(button: Button) -> Button:
	button.set_meta("primary_action",true)
	button.add_theme_stylebox_override("normal",_style(Color("a4dfc4")))
	button.add_theme_stylebox_override("hover",_style(Color("c4f1dc"),Color("effff6")))
	button.add_theme_stylebox_override("pressed",_style(Color("77bda5")))
	button.add_theme_color_override("font_color",Color("123831"))
	button.add_theme_color_override("font_focus_color",Color("123831"))
	button.add_theme_color_override("font_hover_color",Color("123831"))
	button.add_theme_color_override("font_pressed_color",Color("123831"))
	return button

func _card(parent: Node, accent = false) -> VBoxContainer:
	var frame = PanelContainer.new()
	frame.add_theme_stylebox_override("panel",_style(Color("17343e"),Color("467265") if accent else Color("2b4a54")))
	parent.add_child(frame)
	var column = VBoxContainer.new()
	column.add_theme_constant_override("separation",6)
	frame.add_child(column)
	return column

func _menu_backdrop() -> void:
	var background = TextureRect.new()
	background.name = "WaterfrontMenuArt"
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	background.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if ResourceLoader.exists(MENU_ART): background.texture = load(MENU_ART)
	panel.add_child(background)
	panel.move_child(background,0)

func _row(parent: Node) -> HBoxContainer:
	var row = HBoxContainer.new()
	parent.add_child(row)
	return row

func _icon_button(parent: Node, symbol: String, action: Callable, hint: String) -> Button:
	var button = _button(parent,symbol,action,hint)
	button.custom_minimum_size = Vector2(48,48)
	button.add_theme_font_size_override("font_size",22)
	button.text_overrun_behavior = TextServer.OVERRUN_NO_TRIMMING
	return button

func _scroll(parent: Node) -> VBoxContainer:
	var scroll = ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(scroll)
	var column = VBoxContainer.new()
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(column)
	return column

func _shell(title: String, is_modal = false) -> VBoxContainer:
	_clear()
	modal_open = is_modal
	screen_mode = "modal" if is_modal else "hangar"
	if is_modal:
		var shade = ColorRect.new()
		shade.color = Color(0.02,0.06,0.08,0.43)
		shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		panel.add_child(shade)
	var bg = PanelContainer.new()
	bg.name = "MenuConsole"
	bg.add_theme_stylebox_override("panel",_style(Color(0.035,0.085,0.105,0.94 if is_modal else 0.91),Color("34505a")))
	panel.add_child(bg)
	shell_frame = bg
	# Flow tabs compute their wrapped height after the parent receives width.
	# Refit once that minimum changes, instead of retaining the initial tall size.
	bg.minimum_size_changed.connect(_layout.call_deferred)
	var margin = MarginContainer.new()
	for side in ["left","right","top","bottom"]: margin.add_theme_constant_override("margin_"+side,8)
	bg.add_child(margin)
	var column = VBoxContainer.new()
	margin.add_child(column)
	var header = _row(column)
	_label(header,title,27,PAPER)
	if is_modal: _button(header,"×",func(): session.resume_game() if session.flight_active else show_hangar(session.selected_page),"关闭").size_flags_horizontal = Control.SIZE_SHRINK_END
	_layout.call_deferred()
	_focus_first.call_deferred(column)
	return column

func show_hangar(page = "任务") -> void:
	if page == "图鉴": page = "世界"
	session.selected_page = page
	_clear()
	screen_mode = "lobby"
	lobby_top = _lobby_panel("WorkshopHeader")
	var top = _row(lobby_top)
	var home_button = _button(top,"低空小队",func(): show_hangar("主页"),"返回机库主页")
	home_button.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	home_button.custom_minimum_size.x = 136*font_scale
	_tag(home_button,"page_主页")
	var summary = _profile_summary()
	var departure_context = _departure_context(page == "主页")
	var profile = VBoxContainer.new()
	profile.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(profile)
	var profile_button = _button(profile,str(summary.name),show_profiles,"本地飞行员 · 切换或更名")
	_tag(profile_button,"profiles")
	var resource_text = "自由沙盒 · 零件不限" if str(summary.get("kind","normal")) == "sandbox" else "零件 "+str(int(summary.parts))
	_label(profile,resource_text+"  ·  "+_device_label(),12,MUTED)
	var auxiliary = _button(top,"辅助 ▾",_toggle_auxiliary,"教学、设备与游戏设置")
	auxiliary.size_flags_horizontal = Control.SIZE_SHRINK_END
	auxiliary.custom_minimum_size.x = 96*font_scale
	_tag(auxiliary,"auxiliary")
	lobby_nav = _lobby_panel("PrimaryNavigation")
	var nav = VBoxContainer.new()
	nav.add_theme_constant_override("separation",10)
	lobby_nav.add_child(nav)
	for item in [["出航","任务"],["整备","机库"],["记录","挑战"]]:
		var destination = str(item[1])
		var button = _button(nav,str(item[0]),func(): show_hangar(destination))
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		_tag(button,"page_"+destination)
		if _lobby_group(destination) == _lobby_group(page):
			button.add_theme_stylebox_override("normal",_style(Color("244a4c"),Color("739788")))
			button.add_theme_color_override("font_color",MINT)
	_label(nav,"航线修复\n%d / %d" % [int(summary.completed),session.content.missions.size()],13,MUTED)
	if page != "主页":
		lobby_drawer = _lobby_panel("WorkshopDrawer")
		var body = VBoxContainer.new()
		lobby_drawer.add_child(body)
		var heading = _row(body)
		_label(heading,{"任务":"选择航区","世界":"空域图鉴","手机":"连接设备","机库":"机体与工坊","配装":"装配工作台"}.get(page,page),22,PAPER)
		_button(heading,"×",func(): show_hangar("主页"),"收起面板，查看机库").size_flags_horizontal = Control.SIZE_SHRINK_END
		_lobby_subnavigation(body,page)
		var content = _scroll(body)
		match page:
			"任务": _mission_list(content)
			"机库": _fleet_list(content)
			"配装": _loadout(content)
			"挑战": _challenge_list(content)
			"世界": _world_list(content)
			"设置": _settings(content)
			"手机": _phone(content)
			"教学": _tutorial_menu(content)
	else:
		lobby_home = _lobby_panel("WorkshopWelcome")
		var welcome = VBoxContainer.new()
		lobby_home.add_child(welcome)
		var home_title = _label(welcome,str(departure_context.heading),23,PAPER)
		home_title.max_lines_visible = 2
		home_title.tooltip_text = home_title.text
		var home_summary = _label(welcome,str(departure_context.objective),15,MUTED)
		home_summary.max_lines_visible = 3
		home_summary.text_overrun_behavior = TextServer.OVERRUN_TRIM_WORD_ELLIPSIS
		home_summary.tooltip_text = home_summary.text
		_button(welcome,"查看四个航区",func(): show_hangar("任务"))
	lobby_bottom = _lobby_panel("DepartureCard")
	var departure_body = VBoxContainer.new()
	lobby_bottom.add_child(departure_body)
	var frame: Dictionary = CatalogV2.airframes()[session.selected_frame]
	var departure_title = _label(departure_body,str(frame.name)+" · "+str(departure_context.title),16,PAPER)
	departure_title.max_lines_visible = 2
	departure_title.tooltip_text = departure_title.text
	var departure_status = _label(departure_body,str(departure_context.status),13,MUTED)
	departure_status.max_lines_visible = 2
	departure_status.tooltip_text = departure_status.text
	var departure_row = _row(departure_body)
	var mode = OptionButton.new()
	mode.add_item("辅助飞行"); mode.add_item("手动油门")
	mode.selected = 1 if session.repository.data.settings.get("control_mode","assisted") in ["manual_throttle","advanced"] else 0
	mode.fit_to_longest_item = false
	mode.clip_text = true
	mode.custom_minimum_size = Vector2(124*font_scale,42*font_scale)
	mode.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mode.tooltip_text = "辅助松杆定高；手动模式自己维持油门。"
	mode.item_selected.connect(func(i): session.update_setting("control_mode","manual_throttle" if i==1 else "assisted"))
	departure_row.add_child(mode)
	_tag(mode,"flight_mode")
	var departure = _primary(_button(departure_row,str(departure_context.action),_prepare_departure))
	_tag(departure,"departure")
	_build_auxiliary_menu()
	_connect_tutorial()
	_layout.call_deferred()
	_focus_first.call_deferred()
	_refresh_lobby_tour.call_deferred()

func _build_auxiliary_menu() -> void:
	lobby_tools = _lobby_panel("AuxiliaryMenu")
	var column = VBoxContainer.new()
	lobby_tools.add_child(column)
	for item in [["教学与帮助","教学","tutorial"],["连接设备","手机","device"],["游戏设置","设置","settings"]]:
		var destination = str(item[1])
		var button = _button(column,str(item[0]),func(): show_hangar(destination))
		_tag(button,str(item[2]))
	lobby_tools.hide()

func _toggle_auxiliary() -> void:
	_set_auxiliary_open(not auxiliary_open)

func _set_auxiliary_open(value: bool, move_focus = true) -> void:
	if not is_instance_valid(lobby_tools): return
	auxiliary_open = value
	lobby_tools.visible = value
	var trigger: Control = action_controls.get("auxiliary")
	if trigger is Button: trigger.text = "辅助 ▴" if value else "辅助 ▾"
	_layout.call_deferred()
	if not move_focus: return
	if value: _focus_first.call_deferred(lobby_tools)
	elif is_instance_valid(trigger): trigger.grab_focus.call_deferred()

func _lobby_group(page: String) -> String:
	if page in ["机库","配装"]: return "整备"
	if page in ["挑战","世界"]: return "记录"
	if page in ["手机","设置","教学"]: return "辅助"
	return "出航"

func _lobby_subnavigation(parent: Node, page: String) -> void:
	var items: Array = []
	match _lobby_group(page):
		"整备": items = [["机体","机库"],["配装","配装"]]
		"记录": items = [["挑战","挑战"],["图鉴","世界"],["飞行记录","记录"]]
	if items.is_empty(): return
	var row = _row(parent)
	for item in items:
		var destination = str(item[1])
		var button = _button(row,str(item[0]),func():
			if destination == "记录": show_records()
			else: show_hangar(destination))
		# Primary navigation owns page_机库/page_挑战; do not overwrite its tour target.
		if destination not in ["机库","挑战"]: _tag(button,"page_"+destination)
		if destination == page: _primary(button)

func get_lobby_tour_state() -> Dictionary:
	var stored: Variant = session.repository.data.settings.get("lobby_tour_v22",{})
	return stored.duplicate(true) if stored is Dictionary else {}

func _save_lobby_tour(index: int, status: String, replaying = false) -> bool:
	var previous = get_lobby_tour_state()
	var state = {"version":1,"index":clampi(index,0,LOBBY_TOUR.size()),"status":status,"completed":status == "completed" or bool(previous.get("completed",false)),"replaying":replaying}
	var result: Dictionary = session.repository.commit({"id":"lobby-tour-v22:"+str(Time.get_ticks_usec()),"set":{"settings.lobby_tour_v22":state}})
	if not bool(result.get("ok",false)): toast("大厅引导进度尚未保存，请稍后重试。")
	return bool(result.get("ok",false))

func start_lobby_tour(replay = false) -> void:
	if session.flight_active: toast("返回机库后可继续大厅漫游。现在可以学习实飞课程。"); return
	var state = get_lobby_tour_state()
	var index = 0 if replay else clampi(int(state.get("index",0)),0,LOBBY_TOUR.size()-1)
	_lobby_tour_voice_key = ""
	if _save_lobby_tour(index,"in_progress",replay or bool(state.get("completed",false))): show_hangar("主页")

func _hide_lobby_tour() -> void:
	for control in [lobby_tour_panel,lobby_tour_spotlight]:
		if is_instance_valid(control): control.get_parent().remove_child(control); control.queue_free()
	lobby_tour_panel = null
	lobby_tour_spotlight = null

func _refresh_lobby_tour() -> void:
	_hide_lobby_tour()
	if screen_mode != "lobby" or session.flight_active: return
	var state = get_lobby_tour_state()
	if state.is_empty():
		# QA layouts remain deterministic; tests can explicitly start the real tour.
		if session.qa_mode: return
		if not _save_lobby_tour(0,"in_progress"): return
		state = get_lobby_tour_state()
	if str(state.get("status","")) != "in_progress": return
	var index = clampi(int(state.get("index",0)),0,LOBBY_TOUR.size()-1)
	var target: Control = action_controls.get(str(LOBBY_TOUR[index][0]))
	if not is_instance_valid(target):
		var route = {"page_配装":"机库","page_世界":"挑战"}.get(str(LOBBY_TOUR[index][0]),"")
		if not str(route).is_empty() and session.selected_page != str(route): show_hangar.call_deferred(str(route))
		return
	if str(LOBBY_TOUR[index][0]) in ["device","settings","tutorial"]:
		_set_auxiliary_open(true,false)
		_layout()
	lobby_tour_spotlight = LobbySpotlight.new()
	lobby_tour_spotlight.name = "LobbyTourSpotlight"
	lobby_tour_spotlight.target = target
	lobby_tour_spotlight.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lobby_tour_spotlight.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(lobby_tour_spotlight)
	lobby_tour_panel = PanelContainer.new()
	lobby_tour_panel.name = "LobbyTourCard"
	lobby_tour_panel.add_theme_stylebox_override("panel",_style(Color("12343e"),MINT))
	root.add_child(lobby_tour_panel)
	var content = VBoxContainer.new()
	lobby_tour_panel.add_child(content)
	_label(content,"机库漫游  %d / %d" % [index+1,LOBBY_TOUR.size()],13,MINT)
	_label(content,str(LOBBY_TOUR[index][1]),22,PAPER)
	_label(content,str(LOBBY_TOUR[index][2]),16,PAPER)
	_label(content,"请点击发亮的真实按钮，也可以按 Enter 操作。",13,MUTED)
	var voice_id = ["lobby_mission","lobby_fleet","lobby_loadout","lobby_device","lobby_settings","lobby_tutorial","lobby_prepare"][index]
	if is_instance_valid(session.audio) and session.audio.has_method("voice_text"):
		var subtitle = str(session.audio.voice_text(voice_id))
		if not subtitle.is_empty():
			_label(content,"旁白  "+subtitle,13,MUTED)
			if _lobby_tour_voice_key != voice_id:
				_lobby_tour_voice_key = voice_id
				session.audio.play_voice(voice_id,true)
	var buttons = _row(content)
	_button(buttons,"稍后继续",func(): _pause_lobby_tour("deferred"))
	_button(buttons,"跳过漫游",func(): _pause_lobby_tour("skipped"))
	lobby_tour_panel.minimum_size_changed.connect(_layout_lobby_tour.call_deferred)
	_layout_lobby_tour.call_deferred()
	target.grab_focus.call_deferred()

func _pause_lobby_tour(status: String) -> void:
	var state = get_lobby_tour_state()
	if _save_lobby_tour(int(state.get("index",0)),status,bool(state.get("replaying",false))):
		_hide_lobby_tour()
		_lobby_tour_voice_key = ""
		if is_instance_valid(session.audio) and session.audio.has_method("stop_voice"): session.audio.stop_voice()
		toast("可随时在「教学」中继续或重播大厅漫游。")

func _lobby_tour_action(id: String) -> void:
	if id.is_empty() or session.flight_active: return
	var state = get_lobby_tour_state()
	var index = int(state.get("index",0))
	if state.get("status","") != "in_progress" or index < 0 or index >= LOBBY_TOUR.size(): return
	if id != str(LOBBY_TOUR[index][0]): return
	index += 1
	if not _save_lobby_tour(index,"completed" if index == LOBBY_TOUR.size() else "in_progress",bool(state.get("replaying",false))): return
	if index == LOBBY_TOUR.size():
		_hide_lobby_tour()
		if is_instance_valid(session.audio) and session.audio.has_method("play_voice"): session.audio.play_voice("lobby_complete",true)
		toast("机库漫游完成。确认简报后，再开始你的第一段飞行。")
	else: _refresh_lobby_tour.call_deferred()

func _layout_lobby_tour() -> void:
	if not is_instance_valid(lobby_tour_panel) or not is_instance_valid(lobby_tour_spotlight): return
	if not is_instance_valid(lobby_tour_spotlight.target): return
	var edge = 24.0 if root.size.x >= 1200 else 16.0
	var target_rect = lobby_tour_spotlight.target.get_global_rect().grow(12)
	var desired_width = minf(390.0*font_scale,root.size.x-edge*2)
	var left_space = target_rect.position.x-edge
	var right_space = root.size.x-edge-target_rect.end.x
	var width = desired_width
	var x = edge
	# Prefer a side with room, so vertical clamping cannot move the card over its target.
	if left_space >= 280.0 and (target_rect.get_center().x >= root.size.x*0.5 or right_space < 280.0):
		width = minf(desired_width,left_space)
	elif right_space >= 280.0:
		width = minf(desired_width,right_space)
		x = target_rect.end.x
	else:
		x = (root.size.x-width)*0.5
	lobby_tour_panel.size = Vector2(width,0)
	var y = lobby_top.get_global_rect().end.y+16.0 if is_instance_valid(lobby_top) else edge
	y = clampf(y,edge,maxf(edge,root.size.y-edge-lobby_tour_panel.size.y))
	if left_space < 280.0 and right_space < 280.0:
		y = target_rect.end.y+12.0 if root.size.y-target_rect.end.y >= lobby_tour_panel.size.y+edge else maxf(edge,target_rect.position.y-lobby_tour_panel.size.y-12.0)
	lobby_tour_panel.position = Vector2(x,y)
	lobby_tour_spotlight.queue_redraw()

func _lobby_panel(node_name: String) -> PanelContainer:
	var frame = PanelContainer.new()
	frame.name = node_name
	frame.add_theme_stylebox_override("panel",_style(Color(0.035,0.085,0.105,0.90),Color("42616a")))
	panel.add_child(frame)
	frame.minimum_size_changed.connect(_layout.call_deferred)
	return frame

func _profile_summary() -> Dictionary:
	var result = {"name":"本地飞行员","parts":str(session.repository.data.wallet.parts),"completed":session.repository.data.campaign.completed_missions.size()}
	if session.has_method("list_profiles"):
		for profile in session.list_profiles():
			if bool(profile.get("active",false)):
				result.merge(profile,true)
				break
	return result

func _device_label() -> String:
	if session.input.source == "phone": return "手机手柄已连接"
	if session.input.legacy.device >= 0: return Input.get_joy_name(session.input.legacy.device)
	return "键盘与鼠标"

func _module_names(ids: Array) -> String:
	var names: Array[String] = []
	for id in ids: names.append(str(CatalogV2.modules().get(id,{}).get("name",id)))
	return "、".join(names)

func _departure_context(home: bool) -> Dictionary:
	var job: Dictionary = {}
	var resume = false
	var checkpoint: Variant = session.repository.data.campaign.active_checkpoint
	if home and checkpoint is Dictionary:
		var saved = session.get_job(str(checkpoint.get("job_id","")))
		if not saved.is_empty() and session.job_unlocked(saved): job = saved; resume = true
	if job.is_empty() and not prepared_job.is_empty() and str(prepared_job.get("region_id","")) == session.region_id: job = prepared_job
	if job.is_empty():
		for candidate in session.content.missions:
			if str(candidate.region_id) == session.region_id and session.job_unlocked(candidate) and str(candidate.id) not in session.repository.data.campaign.completed_missions:
				job = candidate; break
	var context = {"job":job,"resume":resume,"heading":"选择下一段航路","objective":"已开放的航区可以自由探索，也可以重玩已修复航线。","title":str(session.get_region(session.region_id).name),"status":"查看航区与已保存的修复进度","action":"准备出航 →"}
	if job.is_empty():
		if not session.region_unlocked(session.region_id): context.status = "航区未开放 · 查看前置任务"
		return context
	var stage: Dictionary = job
	var index = 0
	if job.has("stages") and not job.stages.is_empty():
		if resume: index = clampi(int(checkpoint.get("stage_index",0)),0,job.stages.size()-1)
		stage = job.stages[index]
	var equipment: Dictionary = session.departure_equipment(job)
	var tool_state = "工具就绪" if equipment.missing.is_empty() else "需准备："+_module_names(equipment.missing)
	if not bool(equipment.valid_build): tool_state = "配装需要修正"
	var first = home and not resume and not session.is_sandbox() and session.repository.data.campaign.completed_missions.is_empty() and str(job.id) == "M01"
	context.heading = "继续当前目标" if resume else ("首次起飞 · 从教学航线开始" if first else "本次航线")
	context.title = str(job.name)
	context.objective = str(session.get_region(str(job.region_id)).name)+" · "+str(stage.get("name",job.name))+"
"+str(stage.get("complete_when",job.get("task","沿航线标记完成作业")))
	context.status = str(stage.get("name",job.name))+" · "+tool_state
	context.action = "继续任务 →" if resume else ("教学起飞 →" if first else "准备出航 →")
	return context

func _region_status(id: String) -> Dictionary:
	var result = {"completed":0,"total":0,"job":{},"state":"暂无待办 · 可自由探索","tools":"","missing":false}
	for job in session.content.missions:
		if str(job.region_id) != id: continue
		result.total += 1
		if str(job.id) in session.repository.data.campaign.completed_missions: result.completed += 1
		elif result.job.is_empty() and session.job_unlocked(job): result.job = job
	if not session.region_unlocked(id):
		result.state = "完成 "+str({"R2":"M04","R3":"M08","R4":"M12"}.get(id,"前置航线"))+" 开放"
	elif not result.job.is_empty():
		result.state = str(result.job.name)
		var equipment: Dictionary = session.departure_equipment(result.job)
		result.missing = not bool(equipment.valid_build) or not equipment.missing.is_empty()
		result.tools = "配装需要修正" if not bool(equipment.valid_build) else ("需准备："+_module_names(equipment.missing) if result.missing else "起始工具就绪")
	elif int(result.completed) == int(result.total) and int(result.total)>0:
		result.state = "航线已全部修复 · 可重玩或探索"
	return result

func _prepare_departure() -> void:
	if session.selected_page == "主页":
		var context = _departure_context(true)
		if not context.job.is_empty():
			show_briefing(context.job,bool(context.resume))
			return
	if not prepared_job.is_empty() and str(prepared_job.get("region_id","")) == session.region_id:
		show_briefing(prepared_job)
		return
	prepared_job.clear()
	if not session.region_unlocked(session.region_id):
		show_hangar("任务")
		toast("该航区尚未开放。请查看航区卡片上的前置任务。")
		return
	for job in session.content.missions:
		if str(job.region_id) != session.region_id: continue
		if session.job_unlocked(job) and str(job.id) not in session.repository.data.campaign.completed_missions:
			show_briefing(job)
			return
	show_hangar("任务")
	toast("本航区暂无待办任务，可选择重玩任务或自由出航。")

func show_splash(next: Callable = Callable()) -> void:
	_clear()
	screen_mode = "splash"
	_splash_next = next
	_splash_clock = 0.0
	_splash_done = false
	var center = CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	panel.add_child(center)
	var card = PanelContainer.new()
	card.custom_minimum_size.x = 390
	card.add_theme_stylebox_override("panel",_style(Color(0.025,0.075,0.095,0.89),MINT))
	center.add_child(card)
	var column = VBoxContainer.new()
	card.add_child(column)
	_label(column,"LOW ALTITUDE SQUAD",15,MINT).horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label(column,"低空小队",46,PAPER).horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label(column,"沿岸工坊已就绪",19,MUTED).horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_primary(_button(column,"进入机库  →",_finish_splash)).grab_focus()
	_label(column,"按 Enter / Esc 跳过开场",13,MUTED).horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

func _finish_splash() -> void:
	if _splash_done: return
	_splash_done = true
	if _splash_next.is_valid(): _splash_next.call()
	else: show_profiles()

func show_profiles() -> void:
	var body = _shell("选择本地飞行档案",true)
	var content = _scroll(body)
	_label(content,"进度保存在这台电脑。教学随档案保存，随时可重播。",16,MUTED)
	if session.has_method("list_profiles"):
		for profile in session.list_profiles():
			var card = _card(content,bool(profile.get("active",false)))
			_label(card,str(profile.get("name","飞行员"))+ ("  ·  当前" if profile.get("active",false) else ""),21,PAPER)
			_label(card,"航线 %s  ·  零件 %s  ·  %s" % [str(profile.get("completed",0)),str(profile.get("parts",0)),"自由沙盒" if profile.get("kind","") == "sandbox" else "成长档案"],15,MUTED)
			_primary(_button(card,"进入此档案",func():
				if session.select_profile(str(profile.id)):
					draft.clear()
					prepared_job.clear()
					show_hangar("主页")))
	var rename = _card(content)
	_label(rename,"当前档案名称",16,MUTED)
	var name_edit = LineEdit.new()
	name_edit.text = str(_profile_summary().name)
	name_edit.max_length = 24
	name_edit.custom_minimum_size.y = 44*font_scale
	rename.add_child(name_edit)
	_button(rename,"保存名称",func():
		var clean = name_edit.text.strip_edges()
		if clean.is_empty(): toast("请填写档案名称"); return
		if session.has_method("rename_profile"): session.rename_profile(clean); show_profiles())
	_button(body,"返回机库",func(): show_hangar("主页"))
	_focus_first.call_deferred()

func _tutorial_menu(parent: Node) -> void:
	if not session.flight_active:
		var tour_card = _card(parent,true)
		var tour = get_lobby_tour_state()
		_label(tour_card,"认识机库 · 七步大厅漫游",20,PAPER)
		_label(tour_card,"点击真实页面按钮，了解机库、配装、设备与出航。可随时暂缓，退出后保留步骤。",14,MUTED)
		if str(tour.get("status","")) != "completed": _primary(_button(tour_card,"开始漫游" if tour.is_empty() else "继续大厅漫游",func(): start_lobby_tour()))
		_button(tour_card,"从头重播漫游",func(): start_lobby_tour(true))
	_label(parent,"从实际操作中学会飞行",21,PAPER)
	_label(parent,"中文语音与字幕同步。引导只记录学习进度；跳过、暂缓和重播都不会另外发放任务奖励。",15,MUTED)
	var director = _tutorial()
	var journal: Dictionary = director.get_state().get("journal",{}).get("courses",{}) if director != null else {}
	for entry in [["M01","基础飞行","起飞 / 悬停 / 转向 / 平移 / 制动 / 着陆 / 视野"],["M02","吊挂运输","取货 / 稳定摆动 / 交付"],["M03","观察与掩护","扫描 / 取送路线 / 建筑掩护"]]:
		var card = _card(parent)
		_label(card,entry[0]+"  "+entry[1],20,PAPER)
		_label(card,entry[2],14,MUTED)
		var completed = bool(journal.get(entry[0],{}).get("completed",false))
		var skipped: Array = journal.get(entry[0],{}).get("skipped_steps",[])
		_label(card,("学习已结束 · %d 项按设置略过" % skipped.size() if not skipped.is_empty() else "已完成学习") if completed else "等待实践",13,MINT)
		_primary(_button(card,"重播引导" if completed else "开始学习",func(): _begin_tutorial(entry[0],completed))).disabled = director == null
	_label(parent,"操作提示",18,PAPER)
	_label(parent,"左杆：升降 / 偏航；右杆：前后 / 横移。两种模式都跟随机头方向；辅助自动定高，手动需维持油门。",15,MUTED)
	_label(parent,"风、天气和信号干扰是街区中的偶发环境变化。遇到时会先提示；不需要特意寻找，也不影响核心教学结束。",14,MUTED)
	_button(parent,"查看设备与四轴设置",func(): show_hangar("设置"))

func _begin_tutorial(course: String, replaying: bool) -> void:
	var director = _tutorial()
	if director == null: return
	if session.flight_active:
		toast("请先返回机库，再从第一阶段进入独立练习；当前任务进度会保留。")
		return
	if replaying: director.replay(course)
	else: director.start(course)
	var job = session.get_job(course)
	if job.is_empty(): toast("该引导在出航后开始"); return
	if not session.job_unlocked(job):
		director.later()
		toast("先完成前置任务，再进入这组实飞教学")
		return
	var training_job=job.duplicate(true)
	training_job["training"]=true
	training_job["loaner"]=true
	show_briefing(training_job)
	_layout.call_deferred()

func _place_caption() -> void:
	if not is_instance_valid(frame_caption): return
	var edge = 24.0 if root.size.x >= 1200 else 16.0
	frame_caption.position.y = root.size.y-edge-frame_caption.size.y

func _layout() -> void:
	if not is_instance_valid(root): return
	var viewport_size = root.size
	if viewport_size.x < 1 or viewport_size.y < 1: viewport_size = get_viewport().get_visible_rect().size
	var edge = 24.0 if viewport_size.x >= 1200 else 16.0
	if screen_mode == "lobby" and is_instance_valid(lobby_top):
		var top_height = maxf(86.0,74.0*font_scale)
		var nav_width = clampf(116.0*font_scale,116.0,164.0)
		var right_width = minf(530.0*font_scale,viewport_size.x-nav_width-edge*3-180.0)
		right_width = maxf(330.0,right_width)
		var body_y = edge+top_height+14.0
		lobby_top.position = Vector2(edge,edge)
		lobby_top.size = Vector2(viewport_size.x-edge*2,top_height)
		lobby_nav.position = Vector2(edge,body_y)
		lobby_nav.size = Vector2(nav_width,0)
		lobby_bottom.size = Vector2(right_width,0)
		var bottom_height = maxf(100.0*font_scale,lobby_bottom.get_combined_minimum_size().y)
		lobby_bottom.position = Vector2(viewport_size.x-edge-right_width,viewport_size.y-edge-bottom_height)
		lobby_bottom.size = Vector2(right_width,bottom_height)
		if is_instance_valid(lobby_drawer):
			lobby_drawer.position = Vector2(viewport_size.x-edge-right_width,body_y)
			lobby_drawer.size = Vector2(right_width,maxf(160.0,lobby_bottom.position.y-body_y-12.0))
		if is_instance_valid(lobby_home):
			var home_x = edge+nav_width+14.0
			var available_left = lobby_bottom.position.x-home_x-14.0
			if available_left >= 260.0:
				lobby_home.size = Vector2(minf(300.0*font_scale,available_left),0)
				lobby_home.position = Vector2(home_x,viewport_size.y-edge-lobby_home.size.y)
			else:
				# Stack the compact welcome above departure when two cards cannot fit.
				# Keep the central aircraft display clear rather than covering it with a full drawer.
				lobby_home.size = Vector2(minf(360.0,right_width),0)
				lobby_home.position = Vector2(viewport_size.x-edge-lobby_home.size.x,lobby_bottom.position.y-lobby_home.size.y-12.0)
		if is_instance_valid(lobby_tools):
			lobby_tools.size = Vector2(minf(230.0*font_scale,viewport_size.x-edge*2),0)
			lobby_tools.position = Vector2(viewport_size.x-edge-lobby_tools.size.x,lobby_top.position.y+lobby_top.size.y+8.0)
	if is_instance_valid(shell_frame):
		var width = minf(viewport_size.x-edge*2, maxf(viewport_size.x*0.405,470.0*font_scale))
		if modal_open: width = minf(viewport_size.x-edge*2, 850.0*font_scale)
		var x = (viewport_size.x-width)*0.5 if modal_open else viewport_size.x-width-edge
		shell_frame.position = Vector2(x,edge)
		shell_frame.size = Vector2(width,viewport_size.y-edge*2)
		var left_width = maxf(150.0, x-edge*2)
		if is_instance_valid(brand_block):
			brand_block.position = Vector2(edge,edge)
			brand_block.size = Vector2(minf(left_width,350.0*font_scale),0)
			brand_block.visible = left_width >= 210.0
		if is_instance_valid(frame_caption):
			frame_caption.size = Vector2(minf(left_width,420.0*font_scale),0)
			frame_caption.position = Vector2(edge,viewport_size.y-edge-frame_caption.size.y)
			frame_caption.visible = left_width >= 210.0
	if screen_mode == "hud" and is_instance_valid(hud_task_panel):
		var right_width = minf(240.0*font_scale,viewport_size.x*0.29)
		var left_width = minf(450.0*font_scale,viewport_size.x-right_width-edge*3)
		hud_task_panel.position = Vector2(edge,edge)
		hud_task_panel.size = Vector2(left_width,0)
		hud_control_panel.position = Vector2(viewport_size.x-right_width-edge,edge)
		hud_control_panel.size = Vector2(right_width,0)
		hud_map_frame.visible = viewport_size.y >= 800 and viewport_size.x >= 1200 and font_scale <= 1.25
		hud_telemetry_panel.size = Vector2(minf(550.0*font_scale,viewport_size.x*0.66),0)
		hud_telemetry_panel.position = Vector2(edge,viewport_size.y-edge-hud_telemetry_panel.size.y)
	if is_instance_valid(tutorial_panel):
		var width = minf(430.0*font_scale,viewport_size.x*0.46)
		tutorial_panel.size = Vector2(width,0)
		tutorial_panel.position = Vector2(viewport_size.x-edge-width,viewport_size.y-edge-tutorial_panel.size.y)
		if is_instance_valid(hud_telemetry_panel):
			hud_telemetry_panel.size.x = minf(hud_telemetry_panel.size.x,viewport_size.x-width-edge*3)
	if screen_mode == "overview" and is_instance_valid(overview_header):
		overview_header.position = Vector2(edge,edge)
		overview_header.size = Vector2(viewport_size.x-edge*2,0)
		overview_inset.size = Vector2(minf(330.0*font_scale,viewport_size.x*0.35),minf(270.0*font_scale,viewport_size.y*0.40))
		overview_inset.position = Vector2(viewport_size.x-edge-overview_inset.size.x,viewport_size.y-edge-overview_inset.size.y)
	if is_instance_valid(tutorial_highlight): tutorial_highlight.queue_redraw()
	_layout_lobby_tour()
	if is_instance_valid(toast_label):
		toast_label.offset_top = -48*font_scale
		toast_label.offset_bottom = -12
		toast_label.offset_left = viewport_size.x*0.30 if screen_mode == "hud" else edge
		toast_label.offset_right = -edge

func _region_selector(parent: Node, refresh: Callable) -> void:
	var grid = GridContainer.new()
	grid.name = "FourRegionSelection"
	grid.columns = 2
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation",8)
	grid.add_theme_constant_override("v_separation",8)
	parent.add_child(grid)
	for region in session.content.regions:
		var card = _card(grid,str(region.id) == session.region_id)
		card.get_parent().size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_region_preview(card,region)
		var region_id = str(region.id)
		var unlocked = session.region_unlocked(region_id)
		var button = _button(card,str(region.name),func():
			session.region_id = region_id
			session.departure_poi_id = ""
			prepared_job.clear()
			refresh.call())
		_tag(button,"region_"+region_id)
		button.tooltip_text = str(region.name)+" · 查看航区与任务"
		var status = _region_status(region_id)
		_label(card,"已修复 %d / %d" % [int(status.completed),int(status.total)],12,MINT)
		var state_label = _label(card,str(status.state),12,MUTED)
		state_label.max_lines_visible = 2
		state_label.tooltip_text = state_label.text
		if not str(status.tools).is_empty():
			var tools_label = _label(card,str(status.tools),12,Color("e8c58f") if status.missing else MUTED)
			tools_label.max_lines_visible = 2
			tools_label.tooltip_text = tools_label.text
		if bool(status.missing):
			_tag(_button(card,"查看工具补救 →",func(): session.region_id=region_id; show_briefing(status.job)),"region_tools_"+region_id)

func _region_preview(parent: Node, region: Dictionary) -> void:
	var path = "res://assets/world_ui/previews/"+str(region.id)+".png"
	if ResourceLoader.exists(path):
		var preview = TextureRect.new()
		preview.texture = load(path)
		preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		preview.custom_minimum_size = Vector2(0,92)
		preview.mouse_filter = Control.MOUSE_FILTER_IGNORE
		parent.add_child(preview)
	else:
		var preview = MapSurface.new()
		preview.session = session
		preview.region = region
		preview.preview_only = true
		preview.custom_minimum_size = Vector2(0,92)
		preview.mouse_filter = Control.MOUSE_FILTER_IGNORE
		parent.add_child(preview)

func _mission_list(parent: Node) -> void:
	_region_selector(parent,func(): show_hangar("任务"))
	var checkpoint: Variant = session.repository.data.campaign.active_checkpoint
	if checkpoint is Dictionary:
		_primary(_button(parent,"继续上次出航  →  "+str(checkpoint.job_id),func(): session.launch_job(str(checkpoint.job_id),true)))
	_label(parent,"修复航线",13,MUTED)
	for mission in session.content.missions:
		if mission.region_id != session.region_id: continue
		var complete = mission.id in session.repository.data.campaign.completed_missions
		var available = session.job_unlocked(mission)
		var card = _card(parent,available and not complete)
		_label(card,"%s  /  %s" % [mission.id,"已修复" if complete else ("可出航" if available else "等待前置任务")],12,MINT if available else MUTED)
		var button = _button(card,str(mission.name)+"  →",func(): show_briefing(mission))
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.disabled = not available
		_label(card,"首航 %d 零件  ·  %s" % [mission.first_reward_parts,"夜间行动" if mission.time_variant == "night" else "街区作业"],14,Color("b7c6c2"))
	var explore = _card(parent)
	_label(explore,"自由探索",20,PAPER)
	_label(explore,"从已开放的前哨起飞，发现街角的新线索。",14,MUTED)
	var outposts = session.available_outposts(session.region_id)
	var departure = OptionButton.new()
	departure.custom_minimum_size.y = 42
	for i in range(outposts.size()):
		departure.add_item(str(outposts[i].name))
		if outposts[i].id == session.departure_poi_id: departure.selected = i
	departure.item_selected.connect(func(i): session.departure_poi_id = str(outposts[i].id))
	explore.add_child(departure)
	_primary(_button(explore,"自由出航  →",func(): session.launch_exploration(session.region_id))).disabled = not session.region_unlocked(session.region_id)

func show_briefing(job: Dictionary, resume = false) -> void:
	prepared_job = job.duplicate(true)
	var body = _shell("出航简报 / "+str(job.id),true)
	var content = _scroll(body)
	_label(content,str(job.name),29,PAPER)
	_label(content,str(session.get_region(str(job.region_id)).name)+"  ·  "+("夜间作业" if job.get("time_variant","")=="night" else "沿岸航线"),15,MINT)
	var overview = _card(content,true)
	_label(overview,"本次目标",15,MINT)
	_label(overview,str(job.get("task",job.get("route_choice","按航线标记完成任务"))),19)
	var build = session.selected_build()
	_label(overview,"出航机体  "+str(job.get("airframe_id",build.airframe_id)).to_upper()+("  ·  本次借用" if bool(job.get("loaner",false)) else "  ·  当前配装"),15,MUTED)
	if job.has("stages"):
		_label(content,"任务流程",20,PAPER)
		for i in range(job.stages.size()):
			var stage = job.stages[i]
			var card = _card(content)
			_label(card,"%02d  %s" % [i+1,str(stage.name)],20,MINT)
			_label(card,str(stage.complete_when),16)
		if not str(job.get("alternative_plan","")).is_empty(): _label(content,str(job.alternative_plan),16,MUTED)
	else:
		_label(content,str(job.get("bronze_initial","")),18)
		_label(content,"借用机体："+str(job.get("airframe_id",session.active_build.airframe_id)).to_upper() if bool(job.get("loaner",false)) else "使用当前配装",17)
	var equipment: Dictionary = session.departure_equipment(job)
	var equipment_card = _card(content)
	_label(equipment_card,"出航检查 · "+str(equipment.stage_name),17,MINT)
	if not bool(equipment.valid_build): _label(equipment_card,"当前配装不合法，请先修正后出航。",15,Color("e6ad8a"))
	elif equipment.missing.is_empty(): _label(equipment_card,"起始作业工具就绪",15,MUTED)
	else:
		var names: Array[String] = []
		for id in equipment.missing:
			var module: Dictionary = CatalogV2.modules().get(id,{})
			var suffix = "（本次出航提供，可在服务柜换装）" if id in equipment.grants else ""
			names.append(str(module.get("name",id))+suffix)
		_label(equipment_card,"需要准备："+"、".join(names),15,Color("e8c58f"))
		_label(equipment_card,"任务中的工具按阶段更换，不要求同时装备。",13,MUTED)
	_button(equipment_card,"前往配装",func(): draft.clear(); show_hangar("配装"))
	var buttons = _row(body)
	_button(buttons,"返回",func(): show_hangar(session.selected_page))
	if bool(job.get("training",false)):
		_label(body,"独立练习 · 从第一阶段开始，借用所需工具，不改正式任务进度，不发奖励。",15,MINT)
		_tag(_primary(_button(buttons,"开始练习  →",func(): _ui_action("launch"); session.launch_tutorial_practice(str(job.id)))),"launch")
	else:
		var launch = _primary(_button(buttons,"确认出航  →",func(): _ui_action("launch"); session.launch_job(str(job.id),resume)))
		_tag(launch,"launch")
		launch.disabled = not bool(equipment.valid_build)
	_focus_first.call_deferred()

func _fleet_list(parent: Node) -> void:
	for id in CatalogV2.airframes():
		var item = CatalogV2.airframes()[id]
		var owned = id in session.repository.data.owned_airframes
		var card = _card(parent,id == session.selected_frame)
		var row = _row(card)
		_button(row,str(id).to_upper()+"  "+str(item.name),func(): session.preview_frame(id))
		_button(row,"装配" if owned else "%d 零件"%int(item.cost),func():
			if owned or session.purchase(id,true):
				var build = CatalogV2.default_build(id)
				for existing in session.repository.data.builds:
					if existing.airframe_id == id: build = existing.duplicate(true); break
				session.save_build(build); show_hangar("配装"))
		_label(card,"%.1f kg  ·  %.0f m/s  ·  载荷 %.1f kg" % [item.dry_mass_kg,item.motion_limits.speed_mps,item.cargo_rating_kg],14,MUTED)
	_label(parent,"模块工坊",22)
	for id in CatalogV2.modules():
		var item = CatalogV2.modules()[id]
		if int(item.get("cost",0))<=0: continue
		var owned = id in session.repository.data.owned_modules
		_button(parent,"%s  ·  %s" % [item.name,"已制造" if owned else "%d 零件"%int(item.cost)],func(): session.purchase(id); show_hangar("机库")).disabled = owned

func _loadout(parent: Node) -> void:
	if draft.is_empty(): draft = session.selected_build()
	var frames = OptionButton.new()
	frames.fit_to_longest_item = false
	frames.clip_text = true
	var owned: Array = session.repository.data.owned_airframes
	for i in range(owned.size()):
		frames.add_item(str(owned[i]).to_upper()+" "+str(CatalogV2.airframes()[owned[i]].name))
		if owned[i] == draft.airframe_id: frames.selected = i
	frames.item_selected.connect(func(i): draft = CatalogV2.default_build(str(owned[i])); session.preview_frame(str(owned[i])); show_hangar("配装"))
	parent.add_child(frames)
	var names = {"weapon":"武器","tool":"工具","drive":"动力","battery":"电源","utility":"辅助"}
	for slot in CatalogV2.SLOT_ORDER:
		var row = _row(parent)
		_label(row,names[slot],17)
		var option = OptionButton.new()
		option.fit_to_longest_item = false
		option.clip_text = true
		option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(option)
		var ids: Array = []
		for id in CatalogV2.modules():
			var item = CatalogV2.modules()[id]
			if item.slot != slot or (id not in session.repository.data.owned_modules and not str(id).begins_with("stock_")): continue
			ids.append(id)
			option.add_item(str(item.name))
			if id == draft.slots.get(slot) or (draft.slots.get(slot) == "stock" and id == "stock_"+slot): option.selected = ids.size()-1
		option.item_selected.connect(func(i):
			draft.slots[slot]=ids[i]
			if session.has_method("preview_build"): session.preview_build(draft)
			show_hangar("配装"))
		_tag(option,"slot_"+str(slot))
	var result = CatalogV2.resolve_build(draft,0,session.repository.data.owned_airframes,session.repository.data.owned_modules)
	var derived: Dictionary = result.derived
	if not derived.is_empty():
		_label(parent,"质量 %.2f kg   功率 %.0f / %.0f PU\n推重比 %.2f   桨幅 %.2f × %.2f m" % [derived.mass_kg,derived.power_pu,derived.capacity_pu,derived.thrust_ratio,derived.width_m,derived.length_m],18)
	for problem in result.errors: _label(parent,str(problem.code)+" · "+str(problem.slot)+"\n"+str(problem.actual)+" / "+str(problem.limit),16,Color("e6ad8a"))
	var row = _row(parent)
	_button(row,"恢复已保存配装",func(): draft = session.selected_build(); show_hangar("配装"))
	_primary(_button(row,"保存配装",func(): if session.save_build(draft): toast("配装已保存"); show_hangar("配装"))).disabled = not result.valid
	if not prepared_job.is_empty(): _button(parent,"返回出航简报",func(): show_briefing(prepared_job))

func _challenge_list(parent: Node) -> void:
	_region_selector(parent,func(): show_hangar("挑战"))
	for challenge in session.content.airframe_challenges:
		if challenge.region_id != session.region_id: continue
		_button(parent,str(challenge.airframe_id).to_upper()+" · "+str(challenge.name),func(): show_briefing(challenge)).disabled = not session.job_unlocked(challenge)
	_label(parent,"地区作业",22)
	var mode_names = {"race":"竞速航线","precision":"精密作业","salvage":"风险回收"}
	for mode in session.content.mode_configs:
		if mode.region_id != session.region_id: continue
		_button(parent,mode_names[mode.mode],func(): session.launch_job(str(mode.id))).disabled = not session.job_unlocked(mode)
	_label(parent,"最近记录",21)
	var records: Array = session.repository.data.records
	for i in range(records.size()-1,maxi(-1,records.size()-6),-1):
		var record = records[i]
		_label(parent,"%s  ·  %s  ·  %.1f s" % [record.get("job_id","V1"),record.get("outcome",""),float(record.get("seconds",0))],16)
	_button(parent,"查看飞行记录",func(): show_records())

func show_records(page = 0, legacy = false) -> void:
	var body = _shell("V1 历史记录" if legacy else "V2 飞行记录",true)
	_button(body,"V2 飞行记录" if legacy else "V1 历史记录",func(): show_records(0,not legacy))
	var list = _scroll(body)
	var rows: Array = session.repository.data.records.duplicate()
	if legacy:
		var saved: Variant = session.repository.data.legacy_v1.get("records",{})
		rows = saved.values() if saved is Dictionary else (saved if saved is Array else [])
	if rows.is_empty(): _label(list,"暂无记录",18); return
	var first = maxi(0,rows.size()-1-page*20)
	for i in range(first,maxi(-1,first-20),-1):
		var record: Variant = rows[i]
		if not record is Dictionary: continue
		_label(list,"%s  ·  %s  ·  %.1f s" % [record.get("job_id",record.get("mission","V1")),record.get("outcome","历史"),float(record.get("seconds",record.get("time",0)))],20)
		_label(list,"损伤 %.1f  |  碰撞 %d  |  强度 %d  |  %s%s" % [float(record.get("damage",0)),int(record.get("collisions",0)),int(record.get("difficulty",0)),str(record.get("airframe_id","V1")),"  ·  借机" if record.get("loaner",false) else ""],16)
		if not legacy: _label(list,"%s  |  %s  |  %s" % ["夜间" if record.get("night",false) else "日间",str(record.get("control_mode","assisted")),"辅助开火" if record.get("auto_fire",false) else "手动开火"],16)
	var navigation = _row(body)
	_button(navigation,"上一页",func(): show_records(page-1,legacy)).disabled = page == 0
	_button(navigation,"下一页",func(): show_records(page+1,legacy)).disabled = first<20

func _world_list(parent: Node) -> void:
	_region_selector(parent,func(): show_hangar("世界"))
	var map = MapSurface.new()
	map.session = session
	map.region = session.get_region(session.region_id)
	map.custom_minimum_size = Vector2(300,300)
	parent.add_child(map)
	for sector in map.region.sectors:
		var found = 0
		var total = 0
		for poi in map.region.pois:
			if poi.sector_id == sector.id: total += 1; found += int(poi.id in session.repository.data.world.discovered_pois)
		_label(parent,"%s  %d / %d" % [sector.name,found,total],17)

func _check(parent: Node, label: String, key: String, fallback = false) -> void:
	var check = CheckBox.new()
	check.text = label
	check.disabled = session.flight_active and key == "practice_invincible"
	check.button_pressed = bool(session.repository.data.settings.get(key,fallback))
	check.toggled.connect(func(value): session.update_setting(key,value))
	parent.add_child(check)

func _setting_option(parent: Node, title: String, key: String, labels: Array, values: Array) -> void:
	_label(parent,title,17)
	var option = OptionButton.new()
	option.fit_to_longest_item = false
	option.clip_text = true
	option.disabled = session.flight_active and key == "difficulty"
	if key == "control_mode" and session.flight_active and is_instance_valid(session.pilot): option.disabled = not session.pilot.is_landed()
	for i in range(labels.size()):
		option.add_item(str(labels[i]))
		if session.repository.data.settings.get(key,32.0 if key == "camera_zoom" else values[0]) == values[i]: option.selected = i
	option.item_selected.connect(func(i): session.update_setting(key,values[i]))
	parent.add_child(option)

func _sandbox_settings(parent: Node) -> void:
	var card = _card(parent,true)
	_label(card,"沙盒规则",21,MINT)
	_label(card,"此档案已开放全部机体、模块与航区，零件不限。以下保护仅作用于沙盒。",14,MUTED)
	var rules: Dictionary = session.sandbox_rules()
	for entry in [["invincible","机体无敌"],["unlimited_power","电力不限"],["no_overheat","关闭过热"]]:
		var check = CheckBox.new()
		check.text = entry[1]
		check.button_pressed = bool(rules.get(entry[0],false))
		check.toggled.connect(func(value): session.update_sandbox_rule(entry[0],value))
		card.add_child(check)
	var row = _row(card)
	_button(row,"全部开启",func(): session.update_sandbox_rule("all",true); _refresh_settings())
	_button(row,"全部关闭",func(): session.update_sandbox_rule("all",false); _refresh_settings())

func _refresh_settings() -> void:
	if session.flight_active:
		var body = _shell("飞行设置",true)
		_settings(_scroll(body))
	else: show_hangar("设置")

func _settings(parent: Node) -> void:
	_label(parent,"飞行与显示",20,PAPER)
	_setting_option(parent,"飞行模式","control_mode",["辅助飞行 · 自动定高","手动油门 · 姿态自稳"],["assisted","manual_throttle"])
	_label(parent,"左杆控制升降与偏航，右杆控制前后与横移。手动油门需要主动维持高度；改变机头朝向后，前飞方向也随之改变。",14,MUTED)
	_setting_option(parent,"任务强度","difficulty",["休闲","标准","熟练"],[0,1,2])
	_check(parent,"辅助开火","auto_fire",true)
	_check(parent,"自由练习保护","practice_invincible")
	_check(parent,"全屏","fullscreen")
	_setting_option(parent,"画质","quality",["低","标准"],["low","standard"])
	_setting_option(parent,"出航默认视野","camera_zoom",["近景 · 24 米","标准 · 32 米","宽景 · 44 米","远景 · 60 米"],[24.0,32.0,44.0,60.0])
	_setting_option(parent,"字号","ui_scale",["100%","125%","150%"],[1.0,1.25,1.5])
	_check(parent,"减少动态效果","reduced_motion",false)
	_check(parent,"显示教学字幕","subtitles",true)
	var environment = _card(parent)
	_label(environment,"飞行环境",21,PAPER)
	_setting_option(environment,"环境预设","environment_preset",["平静练习","标准街区","真实挑战"],["calm","standard","realistic"])
	for entry in [["environment_wind","风力"],["environment_weather","天气"],["environment_damage","碰撞损伤"],["environment_interference","信号干扰"]]:
		_setting_option(environment,entry[1],entry[0],["关闭","标准","增强"],[0.0,1.0,2.0])
	if session.has_method("is_sandbox") and session.is_sandbox(): _sandbox_settings(parent)
	var sound = _card(parent)
	_label(sound,"声音",21,PAPER)
	_label(sound,"调节后点击试听；机库音乐与飞行环境声会连续播放。",14,MUTED)
	_check(sound,"静音","mute",false)
	var defaults = {"volume":0.8,"music_volume":0.65,"sfx_volume":0.85,"ui_volume":0.75,"ambient_volume":0.62,"birds_volume":0.5,"rotor_volume":0.85,"voice_volume":1.0}
	for key in ["volume","music_volume","sfx_volume","ambient_volume","birds_volume","rotor_volume","voice_volume","ui_volume"]:
		var heading = _row(sound)
		_label(heading,{"volume":"总音量","music_volume":"背景音乐","sfx_volume":"动作效果","ambient_volume":"街区环境","birds_volume":"鸟鸣","rotor_volume":"旋翼","voice_volume":"教学语音","ui_volume":"界面提示"}[key],16)
		var amount = _label(heading,"",14,MINT)
		amount.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		var slider = HSlider.new()
		slider.min_value = 0; slider.max_value = 1; slider.step = 0.05
		slider.custom_minimum_size.y = 26*font_scale
		slider.value = float(session.repository.data.settings.get(key,defaults[key]))
		amount.text = "%d%%" % roundi(slider.value*100)
		slider.value_changed.connect(func(value): amount.text = "%d%%" % roundi(value*100))
		slider.drag_ended.connect(func(changed): if changed: session.update_setting(key,slider.value))
		# Keyboard/controller adjustments do not emit drag_ended.
		slider.focus_exited.connect(func(): if not is_equal_approx(float(session.repository.data.settings.get(key,defaults[key])),slider.value): session.update_setting(key,slider.value))
		sound.add_child(slider)
	var actions = _row(sound)
	_primary(_button(actions,"试听声音",func():
		if is_instance_valid(session.audio) and session.audio.has_method("preview_mix"): session.audio.preview_mix()
		else: session.play_sound("ui")))
	_button(actions,"恢复默认音量",_reset_sound)
	_label(parent,"输入设备",21)
	_label(parent,Input.get_joy_name(session.input.legacy.device) if session.input.legacy.device>=0 else "键盘与鼠标",17)
	for action in ["forward","back","left","right","high","low","yaw_left","yaw_right","brake","interact","fire","utility","target"]:
		var names = {"forward":"前进","back":"后退","left":"左移","right":"右移","high":"升高 / 增油门","low":"下降 / 减油门","yaw_left":"机头左转","yaw_right":"机头右转","brake":"制动","interact":"作业","fire":"开火","utility":"机体能力","target":"防护"}
		_button(parent,names[action]+"  ·  "+session.input.legacy.binding_label(action),func(): bind_action = action; toast("等待新的键盘键或手柄按键"))
	_label(parent,"Mode 2 四轴",18,PAPER)
	for pair in [["axis_yaw","左杆横向 · 偏航",0],["axis_vertical","左杆纵向 · 升降",1],["axis_x","右杆横向 · 横滚",2],["axis_y","右杆纵向 · 俯仰",3]]:
		_label(parent,pair[1],15,MUTED)
		var axis = OptionButton.new()
		for n in range(8): axis.add_item("轴 "+str(n))
		axis.selected = clampi(int(session.input.legacy.config.get(pair[0],pair[2])),0,7)
		axis.item_selected.connect(func(n):
			var config: Dictionary = session.input.legacy.config.duplicate(true)
			config[pair[0]] = n
			config["layout_version"] = 2
			session.input.configure_input(config)
			session.update_setting("input",config))
		parent.add_child(axis)
	for pair in [["invert_yaw","反转偏航"],["invert_vertical","反转升降"],["invert_x","反转横滚"],["invert_y","反转俯仰"]]:
		var check = CheckBox.new()
		check.text = pair[1]
		check.button_pressed = bool(session.input.legacy.config.get(pair[0],false))
		check.toggled.connect(func(value):
			var config: Dictionary = session.input.legacy.config.duplicate(true)
			config[pair[0]] = value
			session.input.configure_input(config)
			session.update_setting("input",config))
		parent.add_child(check)
	_button(parent,"手柄校准",func(): session.input.legacy.begin_calibration(); toast("校准已开始"))
	_button(parent,"迁入 V1 存档",func():
		var source = OS.get_environment("APPDATA").path_join("LowAltitudeHangar/pilot.json")
		var result = session.repository.migrate_v1(source)
		if result.ok:
			session.input.configure_input(session.repository.data.settings.get("input",{}))
			session.apply_settings()
			show_hangar("设置")
		toast("迁移完成，V1 原档保持不变" if result.ok else str(result.error))).disabled = session.flight_active
	_button(parent,"关于与素材鸣谢",show_credits)

func show_credits() -> void:
	var body = _shell("关于与素材鸣谢",true)
	var content = _scroll(body)
	_label(content,"低空小队 / V2.2",27,PAPER)
	_label(content,"沿岸工坊、无人机与街区组成可以探索的低空世界。感谢开放素材与工具的作者。",16,MUTED)
	var audio_manifest: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://assets/audio/v22/manifest.json")) if FileAccess.file_exists("res://assets/audio/v22/manifest.json") else {}
	var credit_text = ""
	if is_instance_valid(session.audio) and session.audio.has_method("get_audio_credits"): credit_text = session.audio.get_audio_credits()
	if credit_text.is_empty() and audio_manifest is Dictionary: credit_text = str(audio_manifest.get("credits_text",""))
	if not credit_text.is_empty() and (not audio_manifest is Dictionary or audio_manifest.get("credits",[]).is_empty()):
		_label(content,"音乐与声音",21,MINT)
		_label(content,credit_text,15,PAPER)
	if audio_manifest is Dictionary:
		for entry in audio_manifest.get("credits",audio_manifest.get("music",[])):
			var card = _card(content)
			_label(card,str(entry.get("title",entry.get("id","Music")))+" — "+str(entry.get("author","")),18,PAPER)
			_label(card,str(entry.get("license","")),13,MUTED)
			if not str(entry.get("changes","")).is_empty(): _label(card,str(entry.changes),13,MUTED)
			var row = _row(card)
			_credit_link(row,"作品原页",str(entry.get("source_url",entry.get("source_page",""))))
			_credit_link(row,"作者",str(entry.get("author_url","")))
			_credit_link(row,"许可",str(entry.get("license_url","")))
	var sources = [
		["res://assets/v2/streets/LICENSES.txt","街区模型"],
		["res://assets/licenses/KenneyNature.txt","自然场景素材"],
		["res://assets/licenses/KenneyIndustrial.txt","工业场景素材"],
		["res://assets/licenses/KenneyParticles.txt","粒子素材"]
	]
	for source in sources:
		if FileAccess.file_exists(source[0]):
			_label(content,source[1],21,MINT)
			_label(content,FileAccess.get_file_as_string(source[0]),14,MUTED)
	var model_links = _row(content)
	_credit_link(model_links,"Kenney 车辆原页","https://kenney.nl/assets/car-kit")
	_credit_link(model_links,"CC0 许可","https://creativecommons.org/publicdomain/zero/1.0/")
	_label(content,"引擎与字体",21,MINT)
	_label(content,"Godot Engine · MIT License\nNoto Sans SC · SIL Open Font License",15,PAPER)
	var links = _row(content)
	_credit_link(links,"Godot 许可","https://godotengine.org/license/")
	_credit_link(links,"字体项目","https://github.com/notofonts/noto-cjk")
	_button(body,"返回设置",_refresh_settings)
	_focus_first.call_deferred()

func _credit_link(parent: Node, label: String, url: String) -> void:
	if not url.begins_with("https://"): return
	_button(parent,label,func(): OS.shell_open(url),url)

func _reset_sound() -> void:
	var result = session.repository.commit({"id":"sound-defaults:"+str(Time.get_ticks_usec()),"set":{"settings.volume":0.8,"settings.music_volume":0.65,"settings.sfx_volume":0.85,"settings.ui_volume":0.75,"settings.ambient_volume":0.62,"settings.birds_volume":0.5,"settings.rotor_volume":0.85,"settings.voice_volume":1.0,"settings.mute":false}})
	if not result.ok: toast("音量设置未保存："+str(result.error)); return
	session.apply_settings()
	if session.flight_active:
		var body = _shell("飞行设置",true)
		_settings(_scroll(body))
	else: show_hangar("设置")
	toast("已恢复默认音量，点击试听检查声音")

func _phone(parent: Node) -> void:
	phone_status = _label(parent,"",18)
	var status = session.phone.get_status()
	if int(status.get("http_port",0)) == 0:
		_button(parent,"开启局域网手机手柄",func():
			var error = session.phone.start_server()
			if error != OK: toast("端口开启失败："+str(error))
			show_hangar("手机") if not session.flight_active else show_phone())
	else:
		for address in status.get("addresses",[]): _label(parent,str(address),17)
		phone_code = _label(parent,"配对码  "+str(status.pair_code),28,Color("b7e5c9"))
		var image = session.phone.get_pair_qr_image()
		if image != null:
			var qr = TextureRect.new()
			qr.texture = ImageTexture.create_from_image(image)
			qr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
			qr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			qr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			qr.custom_minimum_size = Vector2(208,208)
			parent.add_child(qr)
		_button(parent,"允许这台手机接管",session.approve_phone)
		_button(parent,"键盘 / 手柄接管并关闭服务",func(): session.desktop_control(); show_phone() if session.flight_active else show_hangar("手机"))

func show_phone() -> void:
	var body = _shell("手机手柄",true)
	_phone(_scroll(body))

func show_hud() -> void:
	_clear()
	screen_mode = "hud"
	hud_overlay = NavigationOverlay.new()
	hud_overlay.session = session
	hud_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	hud_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(hud_overlay)
	var top = PanelContainer.new()
	top.name = "FlightTaskCard"
	top.add_theme_stylebox_override("panel",_style(Color(0.035,0.085,0.105,0.88),Color("385b5e")))
	panel.add_child(top)
	hud_task_panel = top
	var info = VBoxContainer.new()
	info.add_theme_constant_override("separation",5)
	top.add_child(info)
	hud_title = _label(info,str(session.current_job.get("name",session.current_job.id)),13,MINT)
	hud_action = _label(info,"",18,PAPER)
	hud_action.max_lines_visible = 3
	hud_target = _label(info,"",13,MUTED)
	hud_target.max_lines_visible = 1
	hud_condition = _label(info,"",14,Color("e3d2a4"))
	hud_condition.max_lines_visible = 3
	hud_bar = ProgressBar.new()
	hud_bar.custom_minimum_size.y = 5
	hud_bar.show_percentage = false
	hud_bar.max_value = 1
	info.add_child(hud_bar)
	hud_service = _button(info,"引导至服务柜",_guide_service)
	hud_service.visible = false
	_tag(hud_service,"service_guidance")
	var controls_card = PanelContainer.new()
	controls_card.name = "FlightControls"
	controls_card.add_theme_stylebox_override("panel",_style(Color(0.035,0.085,0.105,0.86),Color("385b5e")))
	panel.add_child(controls_card)
	hud_control_panel = controls_card
	var controls = VBoxContainer.new()
	controls.add_theme_constant_override("separation",6)
	controls_card.add_child(controls)
	hud_region = _label(controls,"",13,MUTED)
	hud_region.max_lines_visible = 2
	hud_quality = _label(controls,"",13,Color("e9c38d"))
	hud_quality.max_lines_visible = 2
	hud_quality.visible = false
	_tag(hud_quality,"flight_signal")
	hud_controls = _row(controls)
	_button(hud_controls,"暂停",func(): session.pause_game(),"Esc · 暂停飞行")
	_tag(_button(hud_controls,"航图",_open_map,"打开三维全域航图"),"map")
	var camera_controls = _row(controls)
	_tag(_button(camera_controls,"−",func(): _zoom_camera(1),"拉远视野"),"camera_zoom")
	_button(camera_controls,"归中",func(): session.recenter_camera(),"恢复跟随飞机")
	_button(camera_controls,"+",func(): _zoom_camera(-1),"拉近视野")
	hud_map_frame = PanelContainer.new()
	hud_map_frame.add_theme_stylebox_override("panel",_style(Color("122d35"),Color("34505a")))
	controls.add_child(hud_map_frame)
	minimap = MapSurface.new()
	minimap.name = "FlightMinimap"
	minimap.session = session
	minimap.region = session.world.region
	minimap.custom_minimum_size = Vector2(0,146)
	minimap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud_map_frame.add_child(minimap)
	var footer = PanelContainer.new()
	footer.name = "FlightTelemetry"
	footer.add_theme_stylebox_override("panel",_style(Color(0.035,0.085,0.105,0.88),Color("385b5e")))
	panel.add_child(footer)
	hud_telemetry_panel = footer
	footer.resized.connect(_place_telemetry)
	var telemetry = VBoxContainer.new()
	telemetry.add_theme_constant_override("separation",5)
	footer.add_child(telemetry)
	hud_stats = _label(telemetry,"",16,PAPER)
	for id in ["flight_vertical","flight_sticks","flight_yaw","flight_brake","flight_cover"]: _tag(hud_stats,id)
	hud_hint = _label(telemetry,"",13,MINT)
	_tag(hud_action,"flight_interact")
	hud_hint.max_lines_visible = 2
	_connect_tutorial()
	_layout()
	update_hud()
	_layout.call_deferred()

func _zoom_camera(amount: float) -> void:
	if session.has_method("camera_zoom"):
		session.camera_zoom(-amount)
		_ui_action("camera_zoom")

func _open_map() -> void:
	if session.flight_active and session.has_method("open_overview"): session.open_overview()
	else: show_map()

func _connect_tutorial() -> void:
	var director = _tutorial()
	if director == null: return
	if _tutorial_source != director:
		if is_instance_valid(_tutorial_source) and _tutorial_source.state_changed.is_connected(_update_tutorial): _tutorial_source.state_changed.disconnect(_update_tutorial)
		_tutorial_source = director
		if not director.state_changed.is_connected(_update_tutorial): director.state_changed.connect(_update_tutorial)
	_update_tutorial(director.get_state())

func _update_tutorial(state: Dictionary) -> void:
	if screen_mode != "hud" or not bool(state.get("active",false)):
		if is_instance_valid(tutorial_panel): tutorial_panel.queue_free(); panel.remove_child(tutorial_panel); tutorial_panel = null
		if is_instance_valid(tutorial_highlight): tutorial_highlight.target = null; tutorial_highlight.queue_redraw()
		return
	if not is_instance_valid(tutorial_panel):
		tutorial_panel = _lobby_panel("FlightTutorial")
		var column = VBoxContainer.new()
		column.add_theme_constant_override("separation",5)
		tutorial_panel.add_child(column)
		tutorial_title = _label(column,"",16,MINT)
		tutorial_title.max_lines_visible = 2
		tutorial_text = _label(column,"",15,PAPER)
		tutorial_text.max_lines_visible = 4
		tutorial_keys = _label(column,"",13,MINT)
		tutorial_keys.max_lines_visible = 2
		tutorial_progress = ProgressBar.new()
		tutorial_progress.custom_minimum_size.y = 5
		tutorial_progress.show_percentage = false
		tutorial_progress.max_value = 1
		column.add_child(tutorial_progress)
		var actions = _row(column)
		_button(actions,"稍后学",func(): var director = _tutorial(); if director != null: director.later())
		_button(actions,"跳过引导",func(): var director = _tutorial(); if director != null: director.skip())
	tutorial_title.text = "%s  ·  %d/%d  %s" % [str(state.course),mini(int(state.index)+1,int(state.count)),int(state.count),str(state.title)]
	tutorial_text.text = str(state.subtitle) if bool(session.repository.data.settings.get("subtitles",true)) else str(state.instruction)
	tutorial_text.tooltip_text = str(state.instruction)
	tutorial_keys.text = str(state.get("bindings",""))
	var duration = float(state.get("hold_required",0))
	tutorial_progress.value = clampf(float(state.get("hold",0))/duration,0,1) if duration>0 else float(state.index)/maxf(1,float(state.count))
	var control: Variant = action_controls.get(str(state.get("highlight","")))
	tutorial_highlight.target = control if is_instance_valid(control) else null
	tutorial_highlight.queue_redraw()
	_layout.call_deferred()

func _place_telemetry() -> void:
	if not is_instance_valid(hud_telemetry_panel): return
	var edge = 24.0 if root.size.x >= 1200 else 16.0
	hud_telemetry_panel.position.y = root.size.y-edge-hud_telemetry_panel.size.y

func update_hud() -> void:
	if modal_open or not is_instance_valid(hud_stats) or not is_instance_valid(session.pilot): return
	var pilot = session.pilot
	if is_instance_valid(session.runner):
		var action = session.runner.current_action()
		hud_action.text = str(action.get("label","阶段提交中"))
		hud_condition.text = session.runner.condition
		if session.night and hud_condition.text.begins_with("敌机 "):
			var visible_enemies = 0
			if is_instance_valid(session.combat):
				for enemy in session.combat.enemies:
					if is_instance_valid(enemy) and float(enemy.get("hp")) > 0 and session.combat_point_visible(enemy.global_position): visible_enemies += 1
			var parts = hud_condition.text.split("|")
			hud_condition.text = "视野内敌机 %d" % visible_enemies+("  |  "+str(parts[1]).strip_edges() if parts.size()>1 else "")
		hud_bar.value = clampf(session.runner.progress_s/maxf(0.1,float(action.get("duration_s",1.5))),0,1)
	else:
		hud_action.text = "自由巡航"
		hud_condition.text = "沿街区探索，在服务柜旁着陆整备。"
		hud_bar.value = 0
	if is_instance_valid(hud_service):
		var missing: Array = session.equipment_missing_for(pilot.build,session.runner.current_action(),session.runner.stage) if is_instance_valid(session.runner) else []
		hud_service.visible = not missing.is_empty()
		if not missing.is_empty():
			var names: Array[String] = []
			for id in missing: names.append(str(CatalogV2.modules().get(id,{}).get("name",id)))
			hud_condition.text = "需要工具："+"、".join(names)
			var destination: Dictionary = session.service_destination()
			hud_service.text = "引导至 %s · %.0fm" % [str(destination.name),float(destination.distance_m)] if not destination.is_empty() else "查看整备补救"
			hud_service.tooltip_text = "服务柜旁着陆停稳后更换工具。"
	if not session.world.secret_hint.is_empty(): hud_condition.text = session.world.secret_hint
	if is_instance_valid(hud_target):
		hud_target.visible = is_instance_valid(session.runner) and not session.runner.current_action().is_empty()
		if hud_target.visible:
			# target_position includes the authored operation height; marker root is at ground level.
			var target: Vector3 = session.runner.target_position()
			var offset: Vector3 = target-pilot.global_position
			hud_target.text = "目标 %.0fm · 高差 %+.1fm" % [Vector2(offset.x,offset.z).length(),offset.y]
	hud_bar.visible = is_instance_valid(session.runner)
	hud_region.text = str(session.world.region.name)+(" · 夜航" if session.night else " · 日间")
	var event_phase = str(pilot.environment_sample.get("event_phase","none"))
	if event_phase in ["warning","active"]:
		hud_region.text += "\n%s · %s %ds" % ["预警" if event_phase == "warning" else "遭遇",str(pilot.environment_sample.get("event_label","局部环境")),ceili(maxf(0,float(pilot.environment_sample.get("event_seconds",0))))]
	elif session.world.current_wind.length()>0.30:
		hud_region.text += "\n侧风 %.0f°" % fposmod(rad_to_deg(atan2(session.world.current_wind.x,session.world.current_wind.z)),360)
	hud_region.add_theme_color_override("font_color",Color("efd28c") if event_phase == "warning" else MUTED)
	var telemetry: Dictionary = pilot.telemetry
	var bearing = fposmod(-float(telemetry.get("heading_deg",rad_to_deg(pilot.heading))),360.0)
	var heading_name = ["北","东北","东","东南","南","西南","西","西北"][int(round(bearing/45.0))%8]
	var power = "油门 %.0f%%" % (float(telemetry.get("throttle",0))*100) if session.input.mode == "manual_throttle" else "辅助定高"
	hud_stats.text = "离地高度 %.1fm · 地速 %.1fm/s · %03d° %s\n机体 %.0f/%.0f · 装甲 %.0f/%.0f\n电量 %.0f%% · 载荷 %.1fkg · 热量 %.0f%%\n%s · %02d:%02d" % [pilot.ground_distance,Vector2(pilot.linear_velocity.x,pilot.linear_velocity.z).length(),roundi(bearing)%360,heading_name,pilot.health,pilot.maximum_health,float(pilot.damage_state.get("armor",0)),float(pilot.damage_state.get("maximum_armor",0)),float(telemetry.get("battery",pilot.battery)),pilot.cargo_kg,pilot.heat/pilot.max_heat*100,power,int(session.run_seconds)/60,int(session.run_seconds)%60]
	var component_lines:PackedStringArray=[]
	for id in pilot.damage_state.get("components",{}):
		var part:Dictionary=pilot.damage_state.components[id]
		component_lines.append("%s %.1f / %.1f"%[DamageModelV22.COMPONENT_NAMES.get(id,id),float(part.health),float(part.maximum)])
	hud_stats.tooltip_text="部件状态（游戏数值）\n"+"\n".join(component_lines)
	var quality_notes: Array[String] = []
	for quality in [["nav_quality","导航"],["compass_quality","罗盘"],["scan_quality","扫描"]]:
		var value = float(telemetry.get(quality[0],pilot.environment_sample.get(quality[0],1.0)))
		if value < 0.95: quality_notes.append("%s %.0f%%" % [quality[1],value*100])
	hud_quality.text = "环境干扰 · "+" / ".join(quality_notes)
	hud_quality.visible = not quality_notes.is_empty()
	hud_quality.tooltip_text = "游戏世界中的环境影响，不代表手机网络连接质量。"
	var scenery: Variant = session.world.get("scenery_hint")
	hud_hint.text = str(scenery).replace("[F]","["+session.input.legacy.binding_label("interact")+"]") if scenery is String and not scenery.is_empty() else session.input.legacy.binding_label("brake")+" 制动  ·  "+session.input.legacy.binding_label("interact")+" 作业"
	if session.night: hud_hint.text += "\n夜航视野有限 · 借机灯与城市灯辨路"
	hud_action.tooltip_text = hud_action.text
	hud_condition.tooltip_text = hud_condition.text
	minimap.queue_redraw()
	hud_overlay.queue_redraw()

func pause_status_text() -> String:
	if session.pause_reasons.has("save_error"): return "保存未完成，请先重试保存。"
	if session.pause_reasons.has("controller_lost"): return "控制器已断开，请重新连接或切回键鼠。"
	for reason in session.pause_reasons:
		if str(reason).begins_with("phone:"): return "手机控制已暂停，请将摇杆回中并在手机上确认恢复。"
	return "当前出航已暂停。"

func show_pause() -> void:
	var body = _shell("出航暂停",true)
	var content = _scroll(body)
	_label(content,pause_status_text(),16,Color("b5c5c4"))
	_primary(_button(content,"继续飞行  →",session.resume_game))
	_button(content,"服务柜",show_service)
	_button(content,"区域地图",_open_map)
	_button(content,"飞行教学",func(): var tutorial_body = _shell("实飞教学",true); _tutorial_menu(_scroll(tutorial_body)))
	_button(content,"手机手柄",show_phone)
	_button(content,"飞行设置",func(): var settings = _shell("飞行设置",true); _settings(_scroll(settings)))
	if is_instance_valid(session.runner):
		_button(content,"任务货物返回领取座",func(): session.runner.recover_cargo(); toast("货物已返回标记领取座"))
		if session.runner.current_action().get("optional",false): _button(content,"略过当前可选货物",func(): session.runner.skip_optional(); session.resume_game())
		if str(session.current_job.get("mode","")) == "salvage": _button(content,"立即撤离",func(): session.runner.begin_extract(); session.resume_game())
		if session.runner.stage.has("optional_actions") and not session.runner.optional: _button(content,"领取可选作业",func(): session.runner.start_stage(session.runner.stage,true); session.resume_game())
	_button(content,"返回机库",session.show_hangar)

func show_service() -> void:
	var body = _shell("安全服务柜",true)
	var column = _scroll(body)
	var destination: Dictionary = session.service_destination()
	var in_range = not session.world.nearest_service(session.pilot.global_position).is_empty()
	if not in_range or not session.pilot.is_landed():
		_label(column,"请在服务柜旁着陆停稳",20,PAPER)
		if not destination.is_empty():
			_label(column,"%s · %.0f m" % [str(destination.name),float(destination.distance_m)],16,MUTED)
			_primary(_button(column,"引导至服务柜",_guide_service))
		else:
			_label(column,"当前没有已知且开放的服务柜。可返回机库整备，再继续任务。",15,MUTED)
			_button(column,"返回机库",session.show_hangar)
		_button(column,"继续飞行",session.resume_game)
		return
	if session.combat.nearby_threats()>0: _label(column,"附近正在交战，请先脱离追击。",15,Color("e8c58f"))
	if session.pilot.cargo_kg>0: _label(column,"先在作业座暂存货物，再更换工具。",15,Color("e8c58f"))
	var allowed: Array = session.repository.data.owned_modules
	if bool(session.current_job.get("loaner",false)):
		allowed = session.current_job.get("loaner_tool_sequence",["scan_base"]).duplicate()
		allowed.append(str(session.current_job.get("loaner_utility","guard_base")))
	for id in allowed:
		var module: Dictionary = CatalogV2.modules().get(id,{})
		if module.is_empty() or module.slot not in ["tool","utility"]: continue
		var equipped = str(session.pilot.build.slots.get(str(module.slot),"")) == str(id)
		var button = _button(column,str(module.name)+(" · 已装备" if equipped else ""),func(): session.switch_service(str(module.slot),id); show_service())
		button.disabled = equipped or session.combat.nearby_threats()>0 or session.pilot.cargo_kg>0
	_button(column,"继续飞行",session.resume_game)

func _guide_service() -> void:
	if session.service_destination().is_empty():
		session.pause_game("service")
		show_service()
		return
	if session.guide_to_service(): session.resume_game()

func show_map() -> void:
	if not session.flight_active:
		var body = _shell("区域航图",true)
		var map = MapSurface.new()
		map.session = session
		map.region = session.get_region(session.region_id)
		map.interactive = true
		map.size_flags_vertical = Control.SIZE_EXPAND_FILL
		map.custom_minimum_size = Vector2(200,200)
		body.add_child(map)
		_label(body,"拖动移动 · 滚轮缩放 · 点击设置航点",14,MUTED)
		_button(body,"返回",func(): show_hangar("世界"))
		return
	_clear()
	screen_mode = "overview"
	modal_open = true
	var surface = OverviewSurface.new()
	surface.session = session
	surface.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	panel.add_child(surface)
	overview_header = _lobby_panel("OverviewToolbar")
	var header = _row(overview_header)
	var heading = VBoxContainer.new()
	heading.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(heading)
	_label(heading,"区域航图 / "+str(session.world.region.name),20,PAPER)
	_label(heading,"夜航 · 仅显示灯光可见区域，机灯与城市灯引路" if session.night else "拖动查看 · 单击标点 · 滚轮缩放",13,MUTED)
	_button(header,"−",func(): _zoom_camera(1),"缩小全图")
	_button(header,"+",func(): _zoom_camera(-1),"放大全图")
	_button(header,"归中",func(): session.recenter_camera())
	_primary(_button(header,"继续飞行",func(): session.close_overview()))
	overview_inset = _lobby_panel("OverviewInset")
	var map = MapSurface.new()
	map.session = session
	map.region = session.world.region
	map.interactive = true
	map.custom_minimum_size = Vector2(180,160)
	overview_inset.add_child(map)
	_map = map
	surface.waypoint_changed.connect(func(): map.queue_redraw())
	_layout.call_deferred()
	_focus_first.call_deferred()

func show_result(title: String, subtitle: String, parts: int, seconds: float) -> void:
	var body = _shell(title,true)
	var column = _scroll(body)
	_label(column,subtitle,22)
	var progress: Dictionary = session.result_progress_summary()
	_label(column,str(progress.task)+" · "+str(progress.region),17,MINT)
	_label(column,str(progress.status),16,PAPER)
	if not progress.stages.is_empty():
		_label(column,"本次练习完成" if bool(progress.practice) else "本次已提交阶段",14,MINT)
		for stage_name in progress.stages: _label(column,"✓ "+str(stage_name),15,MUTED)
	if not str(progress.saved_progress).is_empty(): _label(column,str(progress.saved_progress),15,MUTED)
	if not progress.new_regions.is_empty(): _label(column,"新开放航区："+"、".join(progress.new_regions),17,MINT)
	_label(column,"本次到账 %d 零件\n出航时间 %02d:%02d\n受损 %.0f  ·  碰撞 %d" % [parts,int(seconds)/60,int(seconds)%60,session.pilot.damage_taken,session.pilot.collision_count],21,Color("a1dec3"))
	_button(column,"返回机库",func(): draft.clear(); session.show_hangar())
	_button(column,"再次出航",session.retry_current_run)

func show_save_error(error: String) -> void:
	var body = _shell("尚未保存",true)
	_label(body,error,19,Color("e7b59b"))
	_button(body,"重试保存",session.retry_save)
	_button(body,"退出游戏",func(): get_tree().quit())

func show_quit() -> void:
	var body = _shell("结束本次出航？",true)
	_label(body,"已提交阶段保留。当前阶段从安全台重新开始。",19)
	_button(body,"继续飞行",session.resume_game)
	_button(body,"退出游戏",session.quit_safely)

func toast(text: String) -> void:
	toast_label.text = text
	toast_clock = 5.0

func _process(delta: float) -> void:
	toast_clock -= delta
	if toast_clock <= 0 and is_instance_valid(toast_label): toast_label.text = ""
	if screen_mode == "splash":
		_splash_clock += delta
		if _splash_clock >= 3.0: _finish_splash()
	if is_instance_valid(tutorial_highlight) and is_instance_valid(tutorial_highlight.target): tutorial_highlight.queue_redraw()
	if is_instance_valid(lobby_tour_spotlight): lobby_tour_spotlight.queue_redraw()
	if is_instance_valid(phone_status):
		var status = session.phone.get_status()
		phone_status.text = "%s  |  RTT %.0f ms" % [status.state,float(status.rtt_ms)]
		if is_instance_valid(phone_code): phone_code.text = "配对码  "+str(status.pair_code)

func _input(event: InputEvent) -> void:
	if screen_mode == "lobby" and auxiliary_open and bind_action.is_empty() and event.is_action_pressed("ui_cancel"):
		_set_auxiliary_open(false)
		get_viewport().set_input_as_handled()
		return
	if screen_mode == "splash" and event is InputEventKey and event.pressed and event.keycode in [KEY_ENTER,KEY_ESCAPE,KEY_SPACE]:
		get_viewport().set_input_as_handled()
		_finish_splash()
		return
	if not bind_action.is_empty() and event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		bind_action = ""
		get_viewport().set_input_as_handled()
		toast("已取消按键绑定")
		return
	if bind_action.is_empty(): return
	var binding: Dictionary = {}
	if event is InputEventKey and event.pressed and not event.echo: binding = {"type":"key","code":event.physical_keycode if event.physical_keycode else event.keycode}
	if event is InputEventJoypadButton and event.pressed: binding = {"type":"joy","code":event.button_index}
	if not binding.is_empty():
		session.input.legacy.rebind(bind_action,binding)
		session.update_setting("input",session.input.legacy.config)
		bind_action = ""
		get_viewport().set_input_as_handled()
		toast("按键已保存")

class MapSurface extends Control:
	var session: GameSessionV2
	var region: Dictionary
	var preview_only = false
	var interactive = false
	var zoom = 1.0
	var pan = Vector2.ZERO
	var dragging = false
	var drag_distance = 0.0
	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_STOP
		clip_contents = true
		focus_mode = Control.FOCUS_ALL if interactive else Control.FOCUS_NONE
	func _scale() -> float:
		if _night_limited(): return maxf(0.01,minf(size.x-20,size.y-30)/100.0)*zoom
		return maxf(0.01,minf((size.x-20)/600,(size.y-20)/500))*zoom
	func _offset() -> Vector2:
		if _night_limited() and is_instance_valid(session.pilot):
			var p = session.pilot.global_position
			return size/2-Vector2(p.x,p.z)*_scale()+pan
		return (size-Vector2(600,500)*_scale())/2+pan
	func _point(pos: Vector2) -> Vector2: return _offset()+pos*_scale()
	func _visible_at(point: Vector3) -> bool: return session.night_point_visible(point)
	func _night_limited() -> bool: return session.night and session.flight_active
	func _draw() -> void:
		if preview_only:
			_draw_region_preview()
			return
		draw_rect(Rect2(Vector2.ZERO,size),Color("152f36"))
		var scale_m = _scale()
		var offset = _offset()
		var layout=RegionLayoutWorldUI.get_layout(str(region.id))
		for land in layout.get("land",[]):
			var vertices=PackedVector2Array()
			for p in land.points:vertices.append(_point(Vector2(p[0],p[1])))
			draw_colored_polygon(vertices,Color(str(land.color)).darkened(.25))
		for road in layout.get("roads",[]):
			var vertices=PackedVector2Array()
			for p in road.points:vertices.append(_point(Vector2(p[0],p[1])))
			draw_polyline(vertices,Color("a7ab8d") if road.bridge else Color("526b69"),maxf(1,float(road.width)*scale_m),true)
		if _night_limited():draw_string(get_theme_default_font(),Vector2(8,19),"夜航 · 地形与已知航路",HORIZONTAL_ALIGNMENT_LEFT,-1,12,Color("d9e4d8"))
		for poi in region.get("pois",[]):
			var found = poi.id in session.repository.data.world.discovered_pois
			if poi.hidden and not found: continue
			if not found and not _visible_at(Vector3(float(poi.position_xz_m[0]),0,float(poi.position_xz_m[1]))): continue
			var pos = offset+Vector2(poi.position_xz_m[0],poi.position_xz_m[1])*scale_m
			draw_circle(pos,3.0,Color("d8c27a") if poi.hidden else (Color("87d6b3") if found else Color("6a909b")))
		if session.flight_active and is_instance_valid(session.pilot):
			var p = session.pilot.global_position
			draw_circle(offset+Vector2(p.x,p.z)*scale_m,4.0,Color.WHITE)
			if is_instance_valid(session.runner):
				var target = session.runner.target_position()
				if _visible_at(target): draw_arc(offset+Vector2(target.x,target.z)*scale_m,7,0,TAU,24,Color("d5eda6"),2)
		var waypoint: Variant = session.get("waypoint")
		if waypoint is Vector3 and waypoint.is_finite() and _visible_at(waypoint):
			var point = _point(Vector2(waypoint.x,waypoint.z))
			draw_line(point-Vector2(7,0),point+Vector2(7,0),Color("f0c682"),2)
			draw_line(point-Vector2(0,7),point+Vector2(0,7),Color("f0c682"),2)
		if has_focus(): draw_rect(Rect2(Vector2.ONE,size-Vector2.ONE*2),Color("97ead2"),false,2)
	func _gui_input(event: InputEvent) -> void:
		if interactive and event is InputEventMouseButton:
			if event.button_index in [MOUSE_BUTTON_WHEEL_UP,MOUSE_BUTTON_WHEEL_DOWN] and event.pressed:
				zoom = clampf(zoom*(1.15 if event.button_index == MOUSE_BUTTON_WHEEL_UP else 1.0/1.15),1.0,4.0)
				if zoom == 1.0: pan = Vector2.ZERO
				queue_redraw(); accept_event()
			if event.button_index == MOUSE_BUTTON_LEFT:
				if event.pressed: dragging = true; drag_distance = 0; grab_focus()
				else:
					if dragging and drag_distance < 7 and session.flight_active and session.has_method("set_waypoint"):
						var pos = (event.position-_offset())/_scale()
						var waypoint = Vector3(clampf(pos.x,-16,616),0,clampf(pos.y,-16,516))
						if _visible_at(waypoint): session.set_waypoint(waypoint)
						else: session.ui.toast("夜间只能在当前看得见的区域标点。")
					dragging = false
					queue_redraw()
				accept_event()
		if event is InputEventMouseMotion:
			if interactive and dragging:
				drag_distance += event.relative.length()
				pan += event.relative
				pan = pan.clamp(-size*zoom*0.5,size*zoom*0.5)
				queue_redraw()
				accept_event()
			var scale_m = _scale()
			var offset = _offset()
			tooltip_text = ""
			for poi in region.get("pois",[]):
				if poi.hidden and poi.id not in session.repository.data.world.discovered_pois: continue
				if not _visible_at(Vector3(float(poi.position_xz_m[0]),0,float(poi.position_xz_m[1]))): continue
				if (offset+Vector2(poi.position_xz_m[0],poi.position_xz_m[1])*scale_m).distance_to(event.position)<10: tooltip_text = str(poi.name)+" · "+str(poi.kind)
		if interactive and event is InputEventKey and event.pressed:
			match event.keycode:
				KEY_LEFT: pan.x += 24
				KEY_RIGHT: pan.x -= 24
				KEY_UP: pan.y += 24
				KEY_DOWN: pan.y -= 24
				KEY_HOME: zoom = 1; pan = Vector2.ZERO
				_: return
			queue_redraw(); accept_event()
	func _draw_region_preview() -> void:
		draw_rect(Rect2(Vector2.ZERO,size),Color("183b4a"))
		var data: Dictionary = RegionLayoutWorldUI.get_layout(str(region.get("id","R1")))
		var factor = maxf(.001,minf((size.x-10)/600.0,(size.y-10)/500.0))
		var origin = (size-Vector2(600,500)*factor)*.5
		for land in data.get("land",[]):
			var points = PackedVector2Array()
			for point in land.points: points.append(origin+Vector2(float(point[0]),float(point[1]))*factor)
			if points.size()<3: continue
			var elevation = clampf(float(land.get("height",0))/12.0,0,1)
			draw_colored_polygon(points,Color("768b7b").lerp(Color("a7b4a0"),elevation))
			var outline = points.duplicate(); outline.append(points[0])
			draw_polyline(outline,Color("b4ccbd"),1.0,true)
		for road in data.get("roads",[]):
			var points = PackedVector2Array()
			for point in road.points: points.append(origin+Vector2(float(point[0]),float(point[1]))*factor)
			if points.size()>1: draw_polyline(points,Color("dacfa6") if bool(road.get("bridge",false)) else Color("435c60"),maxf(1.0,float(road.get("width",6))*factor),true)

class OverviewSurface extends Control:
	signal waypoint_changed
	var session: GameSessionV2
	var dragging = false
	var drag_distance = 0.0
	func _process(_delta: float) -> void: queue_redraw()
	func _draw() -> void:
		if not is_instance_valid(session.camera) or not is_instance_valid(session.pilot): return
		if is_instance_valid(session.runner): _map_marker(session.runner.target_position(),"当前任务",Color("f4dc91"))
		var point: Variant = session.get("waypoint")
		if point is Vector3 and point.is_finite(): _map_marker(point,"我的航点",Color("f3ad86"))
		_map_marker(session.pilot.global_position,"我的飞机",Color("c5fff0"),true)
	func _map_marker(world_position: Vector3, label: String, color: Color, aircraft = false) -> void:
		if not aircraft and not session.night_point_visible(world_position): return
		var projected = session.camera.unproject_position(world_position)
		var header_y = 120.0
		if is_instance_valid(session.ui.overview_header): header_y = session.ui.overview_header.get_global_rect().end.y+18
		var point = Vector2(clampf(projected.x,22,size.x-22),clampf(projected.y,header_y,size.y-24))
		draw_circle(point,11,Color("102831"))
		draw_arc(point,9,0,TAU,32,color,2.5)
		draw_circle(point,4,color)
		if aircraft:
			var heading = float(session.pilot.heading)
			var forward = Vector3(-sin(heading),0,-cos(heading))
			var direction = (session.camera.unproject_position(world_position+forward)-projected).normalized()
			var side = Vector2(-direction.y,direction.x)
			draw_colored_polygon(PackedVector2Array([point+direction*21,point+direction*10+side*6,point+direction*10-side*6]),color)
		if projected.distance_to(point)>2:
			var direction = (projected-point).normalized()
			var side = Vector2(-direction.y,direction.x)
			draw_colored_polygon(PackedVector2Array([point+direction*18,point+direction*10+side*4,point+direction*10-side*4]),color)
			label += " · 屏外"
		var font = get_theme_default_font()
		var font_size = int(15*session.ui.font_scale)
		var text_width = font.get_string_size(label,HORIZONTAL_ALIGNMENT_LEFT,-1,font_size).x
		var text_position = point+Vector2(16,-10 if aircraft else 24)
		if label.begins_with("我的航点"): text_position = point+Vector2(-text_width-18,6)
		text_position.x = clampf(text_position.x,8,size.x-text_width-20)
		if is_instance_valid(session.ui.overview_inset) and session.ui.overview_inset.get_global_rect().grow(8).has_point(text_position): text_position.x = point.x-text_width-20
		text_position.x = clampf(text_position.x,8,size.x-text_width-20)
		text_position.y = clampf(text_position.y,header_y+font_size,size.y-14)
		draw_rect(Rect2(text_position-Vector2(6,font_size),Vector2(text_width+12,font_size+10)),Color(0.025,0.07,0.09,0.92))
		draw_string(font,text_position,label,HORIZONTAL_ALIGNMENT_LEFT,-1,font_size,color)
	func _gui_input(event: InputEvent) -> void:
		if event is InputEventMouseButton:
			if event.button_index in [MOUSE_BUTTON_WHEEL_UP,MOUSE_BUTTON_WHEEL_DOWN] and event.pressed:
				session.camera_zoom(1 if event.button_index == MOUSE_BUTTON_WHEEL_UP else -1)
				accept_event()
			if event.button_index == MOUSE_BUTTON_LEFT:
				if event.pressed: dragging = true; drag_distance = 0
				else:
					if dragging and drag_distance < 7:
						var origin = session.camera.project_ray_origin(event.position)
						var direction = session.camera.project_ray_normal(event.position)
						var hit: Variant = Plane(Vector3.UP,0).intersects_ray(origin,direction)
						if hit is Vector3:
							if session.night_point_visible(hit): session.set_waypoint(hit); waypoint_changed.emit()
							else: session.ui.toast("夜间只能在当前看得见的区域标点。")
					dragging = false
				accept_event()
		if event is InputEventMouseMotion and dragging:
			drag_distance += event.relative.length()
			if session.has_method("pan_overview_pixels"): session.pan_overview_pixels(event.relative)
			accept_event()

class LobbySpotlight extends Control:
	var target: Control
	func _draw() -> void:
		if not is_instance_valid(target) or not target.is_visible_in_tree(): return
		var rect = target.get_global_rect().grow(6)
		var shade = Color(0.005,0.015,0.02,0.58)
		draw_rect(Rect2(0,0,size.x,maxf(0,rect.position.y)),shade)
		draw_rect(Rect2(0,rect.end.y,size.x,maxf(0,size.y-rect.end.y)),shade)
		draw_rect(Rect2(0,rect.position.y,maxf(0,rect.position.x),rect.size.y),shade)
		draw_rect(Rect2(rect.end.x,rect.position.y,maxf(0,size.x-rect.end.x),rect.size.y),shade)
		draw_rect(rect,Color("97ead2"),false,3)

class TutorialHighlight extends Control:
	var target: Control
	func _draw() -> void:
		if not is_instance_valid(target) or not target.is_visible_in_tree(): return
		var rect = target.get_global_rect().grow(5)
		draw_rect(rect,Color("97ead2"),false,3)
		draw_circle(Vector2(rect.end.x-4,rect.position.y+4),5,Color("f3d79a"))

class NavigationOverlay extends Control:
	var session: GameSessionV2
	func service_marker_placement(projected: Vector2, label_extent: Vector2) -> Dictionary:
		var safe = Rect2(Vector2(24,24),size-Vector2(48,48))
		var marker = Vector2(clampf(projected.x,safe.position.x+12,safe.end.x-12),clampf(projected.y,safe.position.y+12,safe.end.y-12))
		var exclusions: Array[Rect2] = []
		if is_instance_valid(session.ui):
			for card in [session.ui.hud_task_panel,session.ui.hud_control_panel,session.ui.hud_telemetry_panel,session.ui.tutorial_panel]:
				if is_instance_valid(card) and card.is_visible_in_tree(): exclusions.append(card.get_global_rect().grow(18))
		var label_position = Vector2.ZERO
		for attempt in 8:
			label_position = Vector2(marker.x+14,marker.y-label_extent.y*.5)
			if label_position.x+label_extent.x>safe.end.x: label_position.x=marker.x-14-label_extent.x
			label_position.x=clampf(label_position.x,safe.position.x,maxf(safe.position.x,safe.end.x-label_extent.x))
			label_position.y=clampf(label_position.y,safe.position.y,maxf(safe.position.y,safe.end.y-label_extent.y))
			var blocked = false
			for excluded in exclusions:
				if excluded.intersects(Rect2(label_position,label_extent)) or excluded.has_point(marker):
					marker.y = excluded.end.y+label_extent.y*.5+14 if excluded.get_center().y<size.y*.5 else excluded.position.y-label_extent.y*.5-14
					marker.y = clampf(marker.y,safe.position.y+12,safe.end.y-12)
					blocked=true; break
			if not blocked: break
		return {"marker":marker,"label_position":label_position}
	func _draw() -> void:
		if not is_instance_valid(session.pilot) or not is_instance_valid(session.camera): return
		var aircraft = session.pilot.global_position
		var heading = float(session.pilot.heading)
		var center = session.camera.unproject_position(aircraft)
		var forward = Vector3(-sin(heading),0,-cos(heading))
		var nose = (session.camera.unproject_position(aircraft+forward)-center).normalized()
		var side = Vector2(-nose.y,nose.x)
		var tip = center+nose*32
		draw_colored_polygon(PackedVector2Array([tip+nose*9,tip-nose*5+side*7,tip-nose*5-side*7]),Color("132f38"))
		draw_colored_polygon(PackedVector2Array([tip+nose*6,tip-nose*3+side*4,tip-nose*3-side*4]),Color("a7eed5"))
		if not session.service_navigation_id.is_empty():
			var service_point = session.world.poi_position(session.service_navigation_id)
			var projected = session.camera.unproject_position(service_point+Vector3.UP)
			var distance_m = Vector2(service_point.x-aircraft.x,service_point.z-aircraft.z).length()
			var label_text = "服务柜 %.0fm" % distance_m
			var label_size_px = roundi(14.0*session.ui.font_scale) if is_instance_valid(session.ui) else 14
			var font = get_theme_default_font()
			var label_extent = font.get_string_size(label_text,HORIZONTAL_ALIGNMENT_LEFT,-1,label_size_px)
			var placement = service_marker_placement(projected,label_extent)
			var marker: Vector2 = placement.marker
			var direction = (projected-marker).normalized()
			if direction.length()<.1: direction = Vector2.UP
			var perpendicular = Vector2(-direction.y,direction.x)
			draw_colored_polygon(PackedVector2Array([marker+direction*11,marker-direction*7+perpendicular*6,marker-direction*7-perpendicular*6]),Color("f1c178"))
			draw_string(font,placement.label_position+Vector2(0,font.get_ascent(label_size_px)),label_text,HORIZONTAL_ALIGNMENT_LEFT,-1,label_size_px,Color("f1d39c"))
		if not is_instance_valid(session.runner): return
		var target = session.runner.target_position()
		if not session.night_point_visible(target): return
		var p = session.camera.unproject_position(target)
		var bound = Rect2(Vector2(36,160),size-Vector2(72,276))
		var q = Vector2(clampf(p.x,bound.position.x,bound.end.x),clampf(p.y,bound.position.y,bound.end.y))
		if is_instance_valid(session.ui):
			for card in [session.ui.hud_task_panel,session.ui.hud_control_panel,session.ui.hud_telemetry_panel,session.ui.tutorial_panel]:
				if not is_instance_valid(card): continue
				var excluded: Rect2 = card.get_global_rect().grow(18)
				if excluded.has_point(q): q.y = excluded.position.y-18 if card in [session.ui.hud_telemetry_panel,session.ui.tutorial_panel] else excluded.end.y+18
		if p.distance_to(q)>2:
			var direction = (p-q).normalized()
			var right = Vector2(-direction.y,direction.x)
			draw_colored_polygon(PackedVector2Array([q+direction*12,q-direction*8+right*7,q-direction*8-right*7]),Color("d5eda6"))
		else: draw_arc(q,13,0,TAU,32,Color("d5eda6"),2)
