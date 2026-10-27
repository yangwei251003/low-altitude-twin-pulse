class_name TwinHangarPanel
extends PanelContainer
## Local loadout modal. Session owns persistence and flight lifecycle.
signal save_requested(build: Dictionary, expected_generation: int)
signal return_requested
signal close_requested
const Hangar = preload("res://scripts/v3/gameplay/twin_hangar.gd")
const Catalog = preload("res://scripts/v2/catalog.gd")
const Kit = preload("res://scripts/v3/ui/front/twin_front_kit.gd")
const Equipment = preload("res://scripts/v3/ui/front/twin_front_equipment.gd")
var _profile: Dictionary = {}
var _draft: Dictionary = {}
var _active := false
var _pending := false
var _frames: OptionButton
var _slots: Dictionary = {}
var _resets: Array[Button] = []
var _summary: Label
var _status: Label
var _unlocks: Label
var _save: Button
var _return: Button
var _controls: Array[BaseButton] = []
var _slot_details: Dictionary = {}
var _frame_description: Label
var _mass_caption: Label
var _power_caption: Label
var _mass_bar: ProgressBar
var _power_bar: ProgressBar
var _plan: Control
var _reduce_motion := false
var _display_accent := Color("85dbc3")

class AirframePlan extends Control:
	var frame: Dictionary = {}
	var stats: Dictionary = {}
	var frame_id := ""

	func configure(id: String, source: Dictionary, derived: Dictionary) -> void:
		frame_id = id
		frame = source.duplicate(true)
		stats = derived.duplicate(true)
		queue_redraw()

	func _draw() -> void:
		var font: Font = get_theme_default_font()
		var ink := Color("88c9bd")
		var faint := Color("284954")
		draw_rect(Rect2(Vector2.ZERO, size), Color("0a232d"))
		for index in range(1, 5):
			draw_line(Vector2(size.x*float(index)/5.0, 20), Vector2(size.x*float(index)/5.0, size.y-20), faint, 1)
			draw_line(Vector2(12, size.y*float(index)/5.0), Vector2(size.x-12, size.y*float(index)/5.0), faint, 1)
		if frame.is_empty(): return
		var width: float = maxf(.1, float(frame.get("width_m", 2.0)))
		var length_m: float = maxf(.1, float(frame.get("length_m", 2.0)))
		var scale_m: float = minf((size.x-50.0)/width, (size.y-60.0)/length_m)*.82
		var centre := size*.5+Vector2(0, 5)
		var hull := Rect2(centre-Vector2(width*.13, length_m*.19)*scale_m, Vector2(width*.26, length_m*.38)*scale_m)
		draw_rect(hull, Color("33575f"))
		draw_rect(hull, ink, false, 1.5)
		for rotor: Dictionary in stats.get("rotor_sweeps", []):
			var p: Array = rotor.position_m
			var at := centre+Vector2(float(p[0]), float(p[2]))*scale_m
			draw_line(centre, at, ink, 2.0, true)
			var radius: float = float(rotor.radius_m)*scale_m
			if float(p[1]) > .2: radius *= .86
			draw_arc(at, radius, 0.0, TAU, 32, ink, 1.2, true)
			draw_line(at-Vector2(radius*.7, 0), at+Vector2(radius*.7, 0), Color("d4d9ba"), 1, true)
		for slot: String in stats.get("mounts", {}):
			var p: Array = stats.mounts[slot].position_m
			var at := centre+Vector2(float(p[0]), float(p[2]))*scale_m
			draw_circle(at, 3.4, Color("e6be7d") if slot == "weapon" else Color("8bd9c1"))
		draw_string(font, Vector2(12, 19), frame_id.to_upper()+"  /  %d 旋翼" % int(frame.get("rotor_count", 4)), HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color("e0eadc"))
		draw_string(font, Vector2(12, size.y-10), "俯视布局示意 · 标点为真实挂位", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color("9fbabf"))

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	offset_left = 26; offset_top = 24; offset_right = -26; offset_bottom = -24
	add_theme_stylebox_override("panel", Kit.box(Color("0b222c"), Color("4d716f"), 16, 20))
	var panel_theme := Theme.new()
	panel_theme.default_font = load("res://assets/fonts/NotoSansSC-Medium.ttf")
	panel_theme.default_font_size = 15
	self.theme = panel_theme
	var main: VBoxContainer = Kit.column(14)
	main.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(main)
	var header: HBoxContainer = Kit.row(20)
	header.add_child(Kit.heading("机库配装", "HANGAR / PRE-FLIGHT", "先编辑五槽草稿，再保存为下一次出航的装备。"))
	var close: Button = Kit.button("关闭 / 返回", func(): close_requested.emit())
	close.size_flags_horizontal = Control.SIZE_SHRINK_END
	close.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	header.add_child(close)
	main.add_child(header)
	var body: HBoxContainer = Kit.row(18)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	main.add_child(body)
	var left_scroll := ScrollContainer.new()
	left_scroll.custom_minimum_size.x = 278
	left_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	left_scroll.follow_focus = true
	left_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(left_scroll)
	var left: VBoxContainer = Kit.column(10)
	left_scroll.add_child(left)
	_label(left,"整备机体",16)
	_frames = OptionButton.new()
	_frames.custom_minimum_size.y = 44
	_frames.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_frames.fit_to_longest_item = false
	_frames.clip_text = true
	left.add_child(_frames)
	_controls.append(_frames)
	_frames.item_selected.connect(func(index: int): _choose_frame(str(_frames.get_item_metadata(index))))
	_frame_description = _label(left,"",13)
	_frame_description.add_theme_color_override("font_color", Kit.MUTED)
	_plan = load("res://scripts/v3/ui/front/twin_front_airframe3d.gd").new()
	_plan.custom_minimum_size = Vector2(240, 280)
	_plan.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_plan.set_reduce_motion(_reduce_motion)
	_plan.set_accent(_display_accent)
	left.add_child(_plan)
	_mass_caption = _label(left,"起飞质量",13)
	_mass_bar = _budget_bar(left)
	_power_caption = _label(left,"供电预算",13)
	_power_bar = _budget_bar(left)
	_summary = _label(left,"",14)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = true
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(scroll)
	var column: VBoxContainer = Kit.column(12)
	scroll.add_child(column)
	_label(column,"五槽装配",22)
	for slot: String in Catalog.SLOT_ORDER:
		var key: String = slot
		var card: VBoxContainer = Kit.card(str(Hangar.SLOT_NAMES[slot]), "", "SLOT %02d" % (Catalog.SLOT_ORDER.find(slot)+1))
		column.add_child(card)
		var row: HBoxContainer = Kit.row(10)
		card.add_child(row)
		var picker := OptionButton.new()
		picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		picker.custom_minimum_size.y = 42
		picker.fit_to_longest_item = false
		picker.clip_text = true
		row.add_child(picker)
		_slots[slot] = picker
		_controls.append(picker)
		picker.item_selected.connect(func(index: int):
			if _active or _pending: return
			_draft.slots[key] = str(picker.get_item_metadata(index))
			_refresh())
		var reset: Button = Kit.button("原装", func():
			if _active or _pending: return
			var stock: Dictionary = Catalog.default_build(str(_draft.airframe_id))
			_draft.slots[key] = stock.slots[key]
			_refresh())
		reset.size_flags_horizontal = Control.SIZE_SHRINK_END
		reset.tooltip_text = "仅恢复这个槽位的原装模块；保存配装后生效。"
		row.add_child(reset)
		_resets.append(reset)
		_controls.append(reset)
		_slot_details[slot] = _label(card,"",13)
		_slot_details[slot].add_theme_color_override("font_color", Kit.MUTED)
	var reset_all: Button = _button(column,"恢复整机原装草稿", restore_stock_draft)
	reset_all.tooltip_text = "保留当前机体，只恢复五槽草稿；不会直接改写已保存配装。"
	_resets.append(reset_all)
	_label(column,"探索解锁来源",20)
	_unlocks = _label(column,"",13)
	_unlocks.add_theme_color_override("font_color", Kit.MUTED)
	_button(column,"返回配装顶部",_focus_first)
	var footer: PanelContainer = Kit.panel()
	var footer_column: VBoxContainer = Kit.column(10)
	footer.add_child(footer_column)
	_status = _label(footer_column,"",14)
	_status.add_theme_color_override("font_color", Kit.GOLD)
	var actions: HBoxContainer = Kit.row(12)
	footer_column.add_child(actions)
	_return = _button(actions,"保存战况并返回机库",func(): return_requested.emit())
	_save = _button(actions,"保存配装",_request_save)
	main.add_child(footer)
	_controls.append(close)
	_focus_chain()
	hide()

func open(profile: Dictionary, active_session: bool = false, frame_id: String = "") -> void:
	_profile = profile.duplicate(true)
	_active = active_session
	_pending = false
	_frames.clear()
	var frames: Dictionary = Catalog.airframes()
	for id: String in Hangar.FRAME_ORDER:
		_frames.add_item(id.to_upper()+" · "+str(frames[id].name))
		_frames.set_item_metadata(_frames.item_count-1,id)
	var selected: Dictionary = Hangar.launch_build(_profile,frame_id)
	if not selected.get("ok",false):
		_draft = {}
		_summary.text = ""
		_unlocks.text = ""
		_frame_description.text = "当前配装无法读取，原存档保持。"
		_plan.hide()
		_mass_bar.value = 0
		_power_bar.value = 0
		for detail: Label in _slot_details.values(): detail.text = ""
		_frames.disabled = true
		for picker: OptionButton in _slots.values(): picker.disabled = true
		for reset: Button in _resets: reset.disabled = true
		_return.visible = _active
		_status.text = Hangar.error_text(selected)
		_save.disabled = true
		show()
		_focus_first()
		return
	_draft = selected.build.duplicate(true)
	_refresh()
	show()
	_focus_first()

func _choose_frame(id: String) -> void:
	if _active or _pending: return
	var selected: Dictionary = Hangar.launch_build(_profile,id)
	if not selected.get("ok",false):
		_status.text = Hangar.error_text(selected)
		return
	_draft = selected.build.duplicate(true)
	_refresh()

func restore_stock_draft() -> void:
	if _active or _pending or _draft.is_empty(): return
	_draft = Catalog.default_build(str(_draft.airframe_id))
	_refresh()
	_status.text = "原装已放入当前机体草稿；按“保存配装”后用于下次出航。"

func _refresh() -> void:
	if _draft.is_empty(): return
	var checked: Dictionary = Hangar.validate(_profile,_draft)
	var frame: String = str(_draft.airframe_id)
	_frames.select(Hangar.FRAME_ORDER.find(frame))
	_frames.disabled = _active or _pending
	for slot: String in Catalog.SLOT_ORDER:
		var picker: OptionButton = _slots[slot]
		picker.clear()
		var rows: Array = Hangar.module_options(_profile,_draft,slot)
		for row: Dictionary in rows:
			var caption: String = str(row.name) + " · %.2f kg / %.0f PU" % [float(row.mass_kg), float(row.power_pu)]
			if not row.owned: caption += " · 待解锁"
			elif not row.compatible: caption += " · 不兼容"
			elif not row.valid: caption += " · 预算不足"
			picker.add_item(caption)
			var index: int = picker.item_count-1
			picker.set_item_metadata(index,str(row.id))
			picker.set_item_disabled(index,not row.owned or not row.compatible)
			var actual: String = str(_draft.slots.get(slot,""))
			if actual == "stock": actual = "stock_"+slot
			if actual == row.id: picker.select(index)
		picker.disabled = _active or _pending
		var module_id: String = str(_draft.slots.get(slot, ""))
		if module_id == "stock": module_id = "stock_"+slot
		var info: Dictionary = Equipment.module_info({"profile":_profile, "frame_id":frame}, module_id)
		_slot_details[slot].text = str(info.stats) + ("\n" + str(info.get("effects", "")) if not str(info.get("effects", "")).is_empty() else "") + "\n来源 · " + str(info.source).replace("\n", " / ")
	for reset: Button in _resets: reset.disabled = _active or _pending
	var resolved: Dictionary = checked.get("resolved",{})
	var stats: Dictionary = resolved.get("derived",{})
	var frames: Dictionary = Catalog.airframes()
	if not stats.is_empty():
		var armor: float = float(Hangar.BASE_ARMOR[frame])+ (12.0 if _draft.slots.get("utility") == "reinforced_guard" else 0.0)
		_mass_caption.text = "起飞质量 %.2f / %.2f kg" % [float(stats.mass_kg), float(frames[frame].max_takeoff_mass_kg)]
		_power_caption.text = "供电 %.0f / %.0f PU · 余量 %.0f" % [float(stats.power_pu), float(stats.capacity_pu), float(stats.power_margin_pu)]
		_paint_budget(_mass_bar, float(stats.mass_kg), float(frames[frame].max_takeoff_mass_kg))
		_paint_budget(_power_bar, float(stats.power_pu), float(stats.capacity_pu))
		_summary.text = "额定载荷 %.1f kg\n护甲 %.0f · 速度上限 %.1f m/s\n装货前还需核对实际载荷与质量。" % [float(stats.cargo_rating_kg), armor, float(stats.speed_mps)]
		_plan.show()
		_plan.set_airframe(frame, frames[frame], _draft.get("slots",{}))
	_frame_description.text = str({"tr01":"均衡起步 · 适合熟悉航路与日常作业", "hx02":"重载机体 · 留意较慢的升降与制动节奏", "ag03":"轻快机体 · 额定载荷较小，接近作业点前提早制动", "nx04":"稳定观察 · 兼顾巡航与作业空间", "sh05":"结构防护 · 以较低速度换取更厚装甲", "at06":"综合作业 · 在机动、供电与载荷之间取舍"}.get(frame, "核对五槽装备后再出航。"))
	_save.disabled = _active or _pending or not checked.get("ok",false)
	_return.visible = _active
	_status.text = "飞行中仅查看，当前机体与配装不会改变。" if _active else ("正在保存……" if _pending else ("配装有效；保存后用于下次出击。" if checked.get("ok",false) else Hangar.error_text(checked)))
	var owned: Dictionary = Hangar.ownership(_profile)
	var lines: PackedStringArray = ["起始：基础脉冲枪、基础扫描器、原装动力、原装电池、基础防护。"]
	for unlock: Dictionary in owned.get("unlocks",[]):
		lines.append(("已拥有 · " if unlock.owned else "待解锁 · ")+str(unlock.name)+" — "+str(unlock.condition))
	_unlocks.text = "\n".join(lines)
	_focus_chain()

func set_visual_preferences(reduced: bool, accent: Color) -> void:
	_reduce_motion=reduced
	_display_accent=accent
	if is_instance_valid(_plan):
		_plan.set_reduce_motion(reduced)
		_plan.set_accent(accent)

func _request_save() -> void:
	if _active or _pending or _draft.is_empty(): return
	var prepared: Dictionary = Hangar.prepare_save(_profile,_draft,false,int(_profile.get("generation",-1)))
	if not prepared.get("ok",false):
		_status.text = Hangar.error_text(prepared)
		return
	_pending = true
	_refresh()
	save_requested.emit(_draft.duplicate(true),int(_profile.generation))

func apply_commit_result(result: Dictionary, fresh_profile: Dictionary = {}) -> void:
	_pending = false
	if result.get("ok",false):
		if fresh_profile.is_empty():
			_refresh()
			_status.text = "保存回调缺少原 Store 读回，请刷新后确认；当前草稿保留。"
			return
		_profile = fresh_profile.duplicate(true)
		_refresh()
		_status.text = "已保存；下一次出击使用此配装。"
	else:
		_refresh()
		_status.text = "配装未保存，草稿保留，可重试："+str(result.get("error",result.get("code","unknown")))

func _unhandled_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("ui_cancel"):
		close_requested.emit()
		get_viewport().set_input_as_handled()

func _focus_chain() -> void:
	var available: Array[BaseButton] = []
	for control: BaseButton in _controls:
		control.focus_mode = Control.FOCUS_ALL
		if control.is_visible_in_tree() and not control.disabled: available.append(control)
	for i: int in available.size():
		available[i].focus_neighbor_top = available[i].get_path_to(available[posmod(i-1,available.size())])
		available[i].focus_neighbor_bottom = available[i].get_path_to(available[(i+1)%available.size()])
		available[i].focus_previous = available[i].focus_neighbor_top
		available[i].focus_next = available[i].focus_neighbor_bottom

func _focus_first() -> void:
	_focus_chain()
	for control: BaseButton in _controls:
		if control.is_visible_in_tree() and not control.disabled:
			control.grab_focus()
			break

func _label(parent: Node, text: String, size: int) -> Label:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.add_theme_font_size_override("font_size",size)
	label.add_theme_color_override("font_color",Color("dbe7df"))
	parent.add_child(label)
	return label

func _button(parent: Node, text: String, pressed: Callable) -> Button:
	var button: Button = Kit.button(text, pressed, text == "保存配装")
	parent.add_child(button)
	_controls.append(button)
	return button

func _budget_bar(parent: Node) -> ProgressBar:
	var bar := ProgressBar.new()
	bar.custom_minimum_size.y = 9
	bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.show_percentage = false
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.add_theme_stylebox_override("background", Kit.box(Color("203c46"), Color("203c46"), 4, 0))
	bar.add_theme_stylebox_override("fill", Kit.box(Kit.ACCENT, Kit.ACCENT, 4, 0))
	parent.add_child(bar)
	return bar

func _paint_budget(bar: ProgressBar, used: float, capacity: float) -> void:
	bar.max_value = maxf(1.0, capacity)
	bar.value = clampf(used, 0.0, bar.max_value)
	var color: Color = Kit.ACCENT if used <= capacity else Color("e7a57c")
	bar.add_theme_stylebox_override("fill", Kit.box(color, color, 4, 0))
