class_name TwinInterface
extends CanvasLayer

signal action_requested(action: String, payload: Dictionary)
const ABILITIES = ["blink", "push_pull", "force_field", "light", "heat", "charge", "growth", "decoy", "echo", "takeover"]
const NAMES = ["折跃", "牵引 / 排斥", "局部力场", "光束", "热量", "电荷", "生长", "诱导分身", "协作分身", "机械接管"]
var hangar: PanelContainer
var menu: PanelContainer
var menu_content: VBoxContainer
var hud: Control
var title: Label
var vitals: Label
var objective: Label
var target_info: Label
var environment_status: Label
var message: Label
var boss_info: Label
var explore_button: Button
var gate_button: Button
var vote: PanelContainer
var vote_text: Label
var address: LineEdit
var frames: OptionButton
var ability_buttons: Array[Button] = []
var ability_title: Label
var ability_description: Label
var weapon_status: Label
var suggestion_buttons: Array[Button] = []
var selected = 0
var message_time = 0.0
var wheel: PanelContainer
var branch_list: VBoxContainer
var current_vote: Dictionary = {}
var radio: PanelContainer
var radio_speaker: Label
var radio_text: Label
var radio_queue: Array = []
var pilot_marker: Node2D
var target_marker: Node2D
var objective_marker: Node2D
var task_panel: PanelContainer
var top_panel: PanelContainer
var bottom_panel: PanelContainer
var movement_hint: Label
var flight_details: Label
var details_button: Button
var details_open = false
var travel: PanelContainer
var travel_choices: VBoxContainer
var chapter_choice: PanelContainer
var chapter_vote_read: Button
var journal: PanelContainer
var campaign_book: PanelContainer
var controller_navigation := false
var _pointer_press_owned := false
var controls_help: Label
var front: Control
var assist_button: Button
var assist_status: Label
var heading_controls := true

func install_front(session) -> void:
	# Preserve the existing menu visibility gate used by flight input and modals.
	# Its old controls remain available to compatibility callers, but are hidden.
	for child: Node in menu.get_children():
		if child is Control: child.hide()
	menu.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	menu.add_theme_stylebox_override("panel",StyleBoxEmpty.new())
	front = load("res://scripts/v3/ui/front/twin_front_shell.gd").new()
	menu.add_child(front)
	front.setup(session)

func _ready() -> void:
	layer = 10
	var root = Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	var theme = Theme.new()
	theme.default_font = load("res://assets/fonts/NotoSansSC-Medium.ttf")
	theme.default_font_size = 16
	root.theme = theme
	hud = Control.new()
	hud.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(hud)
	pilot_marker = preload("res://scripts/v3/art/twin_pilot_marker.gd").new()
	hud.add_child(pilot_marker)
	pilot_marker.hide()
	target_marker = preload("res://scripts/v3/art/twin_target_marker.gd").new()
	hud.add_child(target_marker)
	objective_marker = preload("res://scripts/v3/art/twin_objective_marker.gd").new()
	hud.add_child(objective_marker)
	var top = _panel(hud, Vector2(20, 16), Vector2(1240, 48), 6)
	top_panel = top
	top.set_anchor(SIDE_RIGHT, 1)
	top.offset_right = -20
	var top_row = HBoxContainer.new()
	top_row.add_theme_constant_override("separation", 16)
	top.add_child(top_row)
	title = _label(top_row, "两界共脉", 18, Color("e9eee4"))
	title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	vitals = _label(top_row, "", 14, Color("a8c9c7"))
	vitals.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	vitals.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_button(top_row, "航路 M", func(): action_requested.emit("travel", {}))
	_button(top_row, "纪事 L", func(): action_requested.emit("journal", {}))
	_button(top_row, "手册 H", func(): action_requested.emit("handbook", {}))
	_button(top_row, "大厅 Esc", func(): action_requested.emit("menu", {}))
	task_panel = _panel(hud, Vector2(20, 76), Vector2(272, 0), 8)
	task_panel.custom_minimum_size.x = 272
	# Wrapped labels finish measuring after their container receives its width.
	# Shrink again on that change, including the first frame and paused views.
	task_panel.minimum_size_changed.connect(func(): task_panel.reset_size.call_deferred())
	var left_col = VBoxContainer.new()
	left_col.add_theme_constant_override("separation", 6)
	task_panel.add_child(left_col)
	var task_header = HBoxContainer.new()
	left_col.add_child(task_header)
	var task_title = _label(task_header, "当前目标", 14, Color("8ac4bc"))
	task_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	details_button = Button.new()
	details_button.text = "展开提示"
	details_button.flat = true
	details_button.add_theme_font_size_override("font_size", 13)
	details_button.pressed.connect(func():
		details_open = not details_open
		details_button.text = "收起提示" if details_open else "展开提示"
	)
	task_header.add_child(details_button)
	objective = _label(left_col, "断流之后\n接听林岚的救援呼叫。", 16)
	objective.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	objective.custom_minimum_size.x = 235
	target_info = _label(left_col, "Tab 选择目标\nF 使用能力 · X 反向作用", 14, Color("c4d3d2"))
	target_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	target_info.custom_minimum_size.x = 235
	environment_status = _label(left_col, "", 13, Color("a8c9c7"))
	environment_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	environment_status.custom_minimum_size.x = 235
	environment_status.hide()
	explore_button = _button(left_col, "G 联络 / 调查", func(): if not advance_dialogue(): action_requested.emit("explore", {}))
	assist_button = _button(left_col,"自动驾驶辅助",func(): action_requested.emit("assist_menu",{}))
	assist_status = _label(left_col,"",12,Color("91dacb"))
	assist_status.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	assist_status.hide()
	gate_button = _button(left_col, "提交闸门修复", func(): action_requested.emit("interact", {}))
	boss_info = _label(hud, "", 18, Color("f1bd9e"))
	boss_info.position = Vector2(320, 100)
	boss_info.size = Vector2(700, 90)
	boss_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	boss_info.add_theme_constant_override("outline_size", 5)
	boss_info.add_theme_color_override("font_outline_color", Color("102023"))
	var bottom = _panel(hud, Vector2(20, -96), Vector2(1240, 80), 6)
	bottom_panel = bottom
	bottom.grow_vertical = Control.GROW_DIRECTION_BEGIN
	bottom.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	bottom.offset_left = 20
	bottom.offset_top = -96
	bottom.offset_right = -20
	bottom.offset_bottom = -16
	var bottom_col = VBoxContainer.new()
	bottom.add_child(bottom_col)
	var ability_row = HBoxContainer.new()
	bottom_col.add_child(ability_row)
	ability_title = _label(ability_row, "当前：折跃", 18, Color("b0e1d1"))
	ability_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for i in range(2):
		var button = Button.new()
		button.add_theme_font_size_override("font_size", 14)
		button.custom_minimum_size.y = 32
		button.pressed.connect(func():
			var index = ABILITIES.find(str(button.get_meta("ability", "")))
			if index >= 0: select_ability(index)
		)
		ability_row.add_child(button)
		button.hide()
		suggestion_buttons.append(button)
	_button(ability_row, "B 全部能力", func(): action_requested.emit("wheel", {}))
	var action_row = HBoxContainer.new()
	action_row.add_theme_constant_override("separation", 18)
	bottom_col.add_child(action_row)
	ability_description = _label(action_row, "F 使用 · B 查看全部能力", 14, Color("d4dfd9"))
	ability_description.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ability_description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	movement_hint = _label(action_row, "WASD 飞行 · E/Q 升降 · 空格制动", 13, Color("aabfbd"))
	movement_hint.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	weapon_status = _label(bottom_col, "脉冲炮 · J / 左键 开火 · Tab 锁定", 13, Color("e1d4a9"))
	weapon_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	message = _label(hud, "", 14, Color("e1d4a9"))
	message.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	message.offset_left = 28
	message.offset_top = -258
	message.offset_right = 420
	message.offset_bottom = -142
	message.add_theme_color_override("font_shadow_color", Color(0.02, 0.04, 0.05, 0.95))
	message.add_theme_constant_override("shadow_offset_x", 1)
	message.add_theme_constant_override("shadow_offset_y", 1)
	message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	radio = _panel(hud, Vector2.ZERO, Vector2(650, 155))
	radio.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	radio.offset_left = -690
	radio.offset_right = -30
	radio.offset_top = -280
	radio.offset_bottom = -140
	var radio_col = VBoxContainer.new()
	radio_col.add_theme_constant_override("separation", 8)
	radio.add_child(radio_col)
	radio_speaker = _label(radio_col, "无线电", 16, Color("8dc9bf"))
	radio_text = _label(radio_col, "", 18)
	radio_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	radio_text.custom_minimum_size.x = 610
	_button(radio_col, "继续  G", advance_dialogue)
	radio.hide()
	# Navigation owns its placement; the selected target moves around that caption.
	# One-way avoidance prevents the two labels chasing each other every frame.
	target_marker.panel_obstacles.assign([top, task_panel, bottom, radio, objective_marker.caption])
	objective_marker.obstacles.assign([top, task_panel, bottom, radio])
	menu = _panel(root, Vector2.ZERO, Vector2(570, 560))
	menu.set_anchors_preset(Control.PRESET_CENTER)
	menu.offset_left = -285
	menu.offset_top = -310
	menu.offset_right = 285
	menu.offset_bottom = 310
	var menu_scroll = ScrollContainer.new()
	menu_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	menu.add_child(menu_scroll)
	var col = VBoxContainer.new()
	col.add_theme_constant_override("separation", 12)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	menu_scroll.add_child(col)
	menu_content = col
	_label(col, "低空小队：两界共脉", 30)
	_label(col, "八区冒险 · 两界的日常", 16, Color("8dc9bf"))
	flight_details = _label(col, "", 14, Color("b8cacb"))
	flight_details.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var explanation = _label(col, "从港口的失联呼叫出发，跨越八区，寻找另一端的声音。\n完成行动解锁航路；可独自出航，也可与一位伙伴同行。", 14, Color("b8cacb"))
	explanation.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	frames = OptionButton.new()
	for item in ["TR-01 轻型通用", "HX-02 重载运输", "AG-03 高速敏捷", "NX-04 夜间侦察", "SH-05 防护平台", "AT-06 综合作业"]: frames.add_item(item)
	col.add_child(frames)
	_button(col, "单人出航 / 继续", func(): action_requested.emit("solo", {"frame":frames.selected}))
	_button(col, "创建双人局域网房间", func(): action_requested.emit("host", {"frame":frames.selected}))
	var join_row = HBoxContainer.new()
	col.add_child(join_row)
	address = LineEdit.new()
	address.placeholder_text = "房主的局域网 IPv4 地址"
	address.text = "127.0.0.1"
	address.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	join_row.add_child(address)
	_button(join_row, "加入", func(): action_requested.emit("join", {"address":address.text, "frame":frames.selected}))
	_button(col, "机库配装", func(): action_requested.emit("hangar", {}))
	_button(col, "小队纪事 · 支线与发现", func(): action_requested.emit("journal", {}))
	_button(col, "飞行手册 · 十能力与八区导览", func(): action_requested.emit("handbook", {}))
	_button(col, "终章回顾与角色后记", func(): action_requested.emit("ending_book", {}))
	_button(col, "返回飞行", func(): action_requested.emit("resume", {}))
	branch_list = VBoxContainer.new()
	col.add_child(branch_list)
	_button(col, "保存并退出", func(): action_requested.emit("quit", {}))
	vote = _panel(root, Vector2.ZERO, Vector2(560, 220))
	vote.set_anchors_preset(Control.PRESET_CENTER)
	vote.offset_left = -280
	vote.offset_top = -110
	vote.offset_right = 280
	vote.offset_bottom = 110
	var vote_col = VBoxContainer.new()
	vote.add_child(vote_col)
	_label(vote_col, "小队共同决定", 24)
	vote_text = _label(vote_col, "", 16)
	vote_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vote_text.custom_minimum_size.x = 510
	chapter_vote_read = _button(vote_col,"阅读这次的各项方案",func(): action_requested.emit("campaign_choice_reopen",current_vote.get("payload",{})))
	chapter_vote_read.hide()
	_button(vote_col, "确认当前选择", func(): action_requested.emit("confirm", current_vote))
	_button(vote_col, "暂缓，继续探索", func(): action_requested.emit("cancel", current_vote))
	vote.hide()
	wheel = _panel(root, Vector2.ZERO, Vector2(530, 380))
	wheel.set_anchors_preset(Control.PRESET_CENTER)
	wheel.offset_left = -265
	wheel.offset_top = -190
	wheel.offset_right = 265
	wheel.offset_bottom = 190
	var wheel_col = VBoxContainer.new()
	wheel.add_child(wheel_col)
	_label(wheel_col, "随身能力", 24)
	_label(wheel_col, "数字 1–0 · 手柄方向键左右切换", 14, Color("b8cacb"))
	controls_help = _label(wheel_col, "WASD 飞行 · E/Q 升降 · 空格制动\nTab 选目标 · F 使用 · X 反向（支持时）\nG 联络/调查 · 左键/J 射击 · R 重试\nM 跨界 · P 暂停 · Esc 菜单", 14, Color("b8cacb"))
	controls_help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var grid = GridContainer.new()
	grid.columns = 2
	wheel_col.add_child(grid)
	for i in range(ABILITIES.size()):
		var index = i
		ability_buttons.append(_button(grid, "%d  %s" % [(i + 1) % 10, NAMES[i]], func(): select_ability(index); action_requested.emit("wheel", {})))
	_button(wheel_col, "关闭", func(): action_requested.emit("wheel", {}))
	travel = _panel(root, Vector2.ZERO, Vector2(440, 250))
	travel.set_anchors_preset(Control.PRESET_CENTER)
	travel.offset_left = -220
	travel.offset_top = -125
	travel.offset_right = 220
	travel.offset_bottom = 125
	travel.hide()
	travel_choices = VBoxContainer.new()
	travel.add_child(travel_choices)
	chapter_choice = preload("res://scripts/v3/ui/twin_campaign_choice_panel.gd").new()
	root.add_child(chapter_choice)
	chapter_choice.read_requested.connect(func(target: String, option: String): action_requested.emit("campaign_choice_read",{"target":target,"option":option}))
	chapter_choice.choice_requested.connect(func(target: String, option: String): action_requested.emit("campaign_choice_propose",{"target":target,"option":option}))
	journal = preload("res://scripts/v3/content/dev88_progression/twin_content_journal_panel.gd").new()
	root.add_child(journal)
	journal.close_requested.connect(func(): journal.hide())
	journal.track_requested.connect(func(anchor: Dictionary): action_requested.emit("journal_track", anchor))
	campaign_book = preload("res://scripts/v3/content/final_flow/twin_campaign_book_panel.gd").new()
	root.add_child(campaign_book)
	campaign_book.close_requested.connect(func(): action_requested.emit("campaign_book_close", {}))
	campaign_book.voice_requested.connect(func(cue: String): action_requested.emit("campaign_book_voice", {"cue":cue}))
	hangar = preload("res://scripts/v3/ui/twin_hangar_panel.gd").new()
	root.add_child(hangar)
	hangar.save_requested.connect(func(build: Dictionary, generation: int): action_requested.emit("hangar_save",{"build":build,"generation":generation}))
	hangar.return_requested.connect(func(): action_requested.emit("hangar_return",{}))
	hangar.close_requested.connect(func(): action_requested.emit("hangar_close",{}))
	wheel.hide()
	select_ability(0)
	hud.hide()

func _process(delta: float) -> void:
	message_time = maxf(0, message_time - delta)
	if message_time <= 0 and is_instance_valid(message): message.text = ""
	_update_controller_focus()

func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		var hovered := get_viewport().gui_get_hovered_control()
		_pointer_press_owned = event.pressed and is_instance_valid(hovered) and is_ancestor_of(hovered)
	if event is InputEventJoypadButton and event.pressed:
		controller_navigation = true
	elif event is InputEventKey and event.pressed:
		controller_navigation = false
	elif event is InputEventMouseButton and event.pressed:
		controller_navigation = false
	else:
		return
	_update_controller_focus()

## Ownership lasts for the whole press, even if a HUD drag leaves the button.
func blocks_pointer_fire() -> bool:
	if not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT): _pointer_press_owned = false
	return _pointer_press_owned

## Keep navigation inside the visible modal. Flight HUD buttons never retain
## A/Tab focus and therefore cannot steal the pilot's brake/target controls.
func _update_controller_focus() -> void:
	if not is_instance_valid(menu): return
	var scope: Control
	if is_instance_valid(hangar) and hangar.visible:
		scope = hangar
	else:
		for panel: Control in [campaign_book,journal,menu,chapter_choice,travel,vote,wheel]:
			if is_instance_valid(panel) and panel.visible:
				scope = panel
				break
	if scope==menu and is_instance_valid(front): scope=front.focus_scope()
	var available: Array[BaseButton] = []
	for button: BaseButton in find_children("*","BaseButton",true,false):
		var enabled: bool = scope!=null and scope.is_ancestor_of(button) and button.is_visible_in_tree() and not button.disabled
		button.focus_mode = Control.FOCUS_ALL if enabled else Control.FOCUS_NONE
		if enabled: available.append(button)
	# Native edit controls also belong to the visible modal. In particular the
	# background LAN address must not receive Tab/text while fitting a loadout.
	for edit: LineEdit in find_children("*","LineEdit",true,false):
		edit.focus_mode = Control.FOCUS_ALL if edit.is_visible_in_tree() and (scope==null or scope.is_ancestor_of(edit)) else Control.FOCUS_NONE
	# Also refresh keyboard help when the flight HUD has no open modal.
	var focused: Control = get_viewport().gui_get_focus_owner()
	if scope==null:
		if focused!=null and is_ancestor_of(focused): focused.release_focus()
	elif (focused==null or not scope.is_ancestor_of(focused) or not focused.is_visible_in_tree()) and not available.is_empty():
		available[0].grab_focus()
	if is_instance_valid(movement_hint):
		movement_hint.text = "右杆飞行 · 左杆升降/转向 · A 制动" if controller_navigation else "W/S 前后 · A/D 转向 · E/Q 升降 · 空格制动" if heading_controls else "WASD 飞行 · E/Q 升降 · 空格制动"
	if is_instance_valid(controls_help):
		controls_help.text = "右杆飞行 · 左杆升降/转向 · A 制动\nRB 锁定 · Y 使用 · 按右杆反向 · X 射击\nB 联络/调查 · LB/方向键切换能力\n按左杆选航路 · Start 共同暂停 · Back 菜单\n菜单：方向键移动 · A 确认" if controller_navigation else ("W/S 前后 · A/D 转向 · E/Q 升降" if heading_controls else "WASD 飞行 · Z/C 转向 · E/Q 升降")+"\n空格制动 · Tab 选目标 · F 使用 · X 反向\nG 联络/调查 · 左键/J 射击 · R 重试\nM 跨界 · P 暂停 · Esc 菜单"

func set_assist_status(value: Dictionary) -> void:
	var was_assisting: bool=is_instance_valid(assist_status) and assist_status.visible
	if not is_instance_valid(assist_status): return
	var enabled: bool=bool(value.get("enabled",false))
	assist_status.visible=enabled
	assist_status.text=str(value.get("message",""))
	assist_button.text="停止辅助 / 手动接管" if enabled else "自动驾驶辅助"
	if was_assisting and not enabled: notify(str(value.get("message","已交还手动驾驶")))

func select_ability(index: int) -> void:
	selected = clampi(index, 0, ABILITIES.size() - 1)
	for i in range(ability_buttons.size()):
		ability_buttons[i].modulate = Color("87dfc9") if i == selected else Color("c7d2d0")
	action_requested.emit("select", {"ability":ABILITIES[selected]})

func show_ability_context(title_text: String, action_text: String, suggestions: Array) -> void:
	ability_title.text = title_text
	ability_description.text = action_text
	for i in range(suggestion_buttons.size()):
		var button = suggestion_buttons[i]
		button.visible = i < suggestions.size()
		if not button.visible: continue
		var id = str(suggestions[i])
		var index = ABILITIES.find(id)
		button.visible = index >= 0
		if index < 0: continue
		button.set_meta("ability", id)
		button.text = ("已选 " if index == selected else "选择 ") + "%d %s" % [(index + 1) % 10, NAMES[index]]
		button.tooltip_text = "只切换工具；按 F 才使用。是否能作用还取决于距离、遮挡和状态。"
		button.modulate = Color("87dfc9") if index == selected else Color.WHITE

func notify(text: String) -> void:
	if is_instance_valid(front): front.notify(text)
	message.text = text
	message_time = 6.0

func show_dialogue(character_id: String, lines: Array, display_name: String = "") -> void:
	var speaker = {"npc:linlan":"林岚 · 救援调度", "npc:ruanheng":"阮衡 · 港口工程师", "npc:atai":"阿苔 · 根谷守林人",
		"npc:shuyao":"疏谣 · 镜湖档案庭", "npc:qiaoshu":"乔述 · 换班检修台", "npc:lingyin":"苓音 · 养护棚",
		"npc:wenxu":"闻序 · 风暴值守台", "npc:guanzhi":"冠枝 · 冠峰接续台"}.get(character_id, "无线电")
	if not display_name.strip_edges().is_empty(): speaker = display_name.strip_edges().left(64)
	for line in lines:
		radio_queue.append({"speaker":speaker, "text":str(line), "character_id":character_id})
	if not radio.visible: _show_radio_next()

func _show_radio_next() -> void:
	if radio_queue.is_empty():
		radio.hide()
		action_requested.emit("radio_stop", {})
		return
	var line: Dictionary = radio_queue.pop_front()
	radio_speaker.text = str(line.speaker)
	radio_text.text = str(line.text)
	radio.show()
	action_requested.emit("radio_line", {"character_id":str(line.get("character_id", "")), "speaker":str(line.speaker), "text":str(line.text)})

func advance_dialogue() -> bool:
	if not is_instance_valid(radio) or not radio.visible: return false
	_show_radio_next()
	return true

func clear_dialogue() -> void:
	radio_queue.clear()
	action_requested.emit("radio_stop", {})
	if is_instance_valid(radio): radio.hide()

func show_game() -> void:
	menu.hide()
	journal.hide()
	travel.hide()
	chapter_choice.hide()
	hud.show()

func show_travel(choices: Array) -> void:
	for child in travel_choices.get_children():
		travel_choices.remove_child(child)
		child.queue_free()
	var heading := Label.new()
	heading.text = "选择航路 · 合作时双方确认"
	travel_choices.add_child(heading)
	for choice in choices:
		var destination := str(choice.id)
		var button := _button(travel_choices, str(choice.name), func(): action_requested.emit("travel_to", {"region_id":destination}))
		button.disabled = not bool(choice.available)
		if button.disabled: button.text += " · 尚未开放"
	_button(travel_choices, "继续探索", func(): travel.hide())
	_button(travel_choices, "查看小队纪事", func(): action_requested.emit("journal", {}))
	travel.show()

func show_vote(proposal: Dictionary, paused: bool = false) -> void:
	current_vote = proposal
	vote.visible = not proposal.is_empty()
	if proposal.is_empty(): return
	var kind = str(proposal.get("kind", ""))
	chapter_vote_read.visible = kind == "campaign_choice"
	var payload: Dictionary = proposal.get("payload", {})
	var description = "一起切换到 " + str(payload.get("region_id", ""))
	if kind == "pause": description = "共同恢复世界，双方确认后生效" if paused else "共同暂停世界，双方确认后生效"
	if kind == "major_choice":
		description = "供能方案：" + ("城市优先" if payload.get("value") == "city" else "两界共用") + "\n这会改变当前分支的供能记录。确认前将保留独立分支。"
	if kind == "facility_choice":
		description = "共用桥 · " + ("住区直达接诊台\n住区 13.4m · 巡检绕行 19.8m" if payload.get("mode") == "public_span" else "巡检直达作业台\n巡检 9.6m · 住区绕行 39.6m") + "\n两方均保留通路。确认时会再次检查桥和锁销。"
	if kind == "campaign_choice": description = str(payload.get("description","章节抉择"))+"\n选择前分支已保留。共同确认前，每人须在确认台读完各项方案。"
	vote_text.text = description + "\n已确认 %d / %d" % [proposal.get("confirmed", []).size(), proposal.get("participants", []).size()]

func set_branches(branches: Array) -> void:
	for child in branch_list.get_children(): child.queue_free()
	for item in branches.slice(0, 3):
		if bool(item.get("active", false)): continue
		var id = str(item.get("branch_id", item.get("id", "")))
		if id.is_empty(): continue
		_button(branch_list, "返回分支：" + str(item.get("label", id)), func(): action_requested.emit("branch", {"id":id}))

func _panel(parent: Node, at: Vector2, dimensions: Vector2, vertical_padding: float = 12.0) -> PanelContainer:
	var panel = PanelContainer.new()
	parent.add_child(panel)
	panel.position = at
	panel.size = dimensions
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.035, 0.10, 0.13, 0.97)
	style.border_color = Color("3b686d")
	style.set_border_width_all(1)
	style.set_corner_radius_all(9)
	style.content_margin_left = 16
	style.content_margin_right = 16
	style.content_margin_top = vertical_padding
	style.content_margin_bottom = vertical_padding
	panel.add_theme_stylebox_override("panel", style)
	return panel

func _label(parent: Node, text: String, size = 16, tint = Color("e3e9e4")) -> Label:
	var label = Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", tint)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(label)
	return label

func _button(parent: Node, text: String, callback: Callable) -> Button:
	var button: Button = preload("res://scripts/v3/ui/front/twin_front_kit.gd").button(text,callback)
	button.custom_minimum_size.y = 36
	button.size_flags_horizontal = Control.SIZE_FILL
	for style_name: String in ["normal","hover","pressed","disabled"]:
		var style: StyleBoxFlat=button.get_theme_stylebox(style_name).duplicate()
		style.content_margin_top=4
		style.content_margin_bottom=4
		button.add_theme_stylebox_override(style_name,style)
	button.focus_mode = Control.FOCUS_NONE
	parent.add_child(button)
	return button
