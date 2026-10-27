extends PanelContainer
## A local, rereadable presentation. It never accepts or completes a task.
signal close_requested
signal voice_requested(cue: String)
var pages: Array = []
var _index := 0
var _heading: Label
var _selector: OptionButton
var _body: Label
var _scroll: ScrollContainer
var _previous: Button
var _next: Button
var _voice: Button
var _close: Button

func _ready() -> void:
	name = "CampaignBook"
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	offset_left = 70; offset_right = -70; offset_top = 48; offset_bottom = -48
	mouse_filter = Control.MOUSE_FILTER_STOP
	var panel := StyleBoxFlat.new()
	panel.bg_color = Color("101e24")
	panel.border_color = Color("35525a")
	panel.set_border_width_all(1)
	panel.set_corner_radius_all(8)
	add_theme_stylebox_override("panel", panel)
	var margin := MarginContainer.new()
	for side: String in ["left", "right", "top", "bottom"]: margin.add_theme_constant_override("margin_" + side, 20)
	add_child(margin)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 14)
	margin.add_child(column)
	_heading = Label.new()
	_heading.add_theme_font_size_override("font_size", 24)
	_heading.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(_heading)
	_selector = OptionButton.new()
	_selector.item_selected.connect(_show_page)
	column.add_child(_selector)
	_scroll = ScrollContainer.new()
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	column.add_child(_scroll)
	_body = Label.new()
	_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_body.add_theme_font_size_override("font_size", 19)
	_body.add_theme_constant_override("line_spacing", 6)
	_scroll.add_child(_body)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	column.add_child(row)
	_previous = _button(row, "上一页", func(): _show_page(_index - 1))
	_next = _button(row, "下一页", func(): _show_page(_index + 1))
	_voice = _button(row, "听这一页 · 中文合成语音", _read_page)
	var space := Control.new()
	space.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(space)
	_close = _button(row, "返回", func(): close_requested.emit())
	hide()

func show_book(title: String, rows: Array, selected_id := "") -> void:
	pages = rows.duplicate(true)
	if pages.is_empty(): return
	_heading.text = title
	_selector.clear()
	var at := 0
	for i in range(pages.size()):
		_selector.add_item(str(pages[i].get("title", "记录")))
		if str(pages[i].get("id", "")) == selected_id: at = i
	show()
	_show_page(at)
	_focus_close.call_deferred()

func _show_page(index: int) -> void:
	if pages.is_empty(): return
	voice_requested.emit("")
	_index = clampi(index, 0, pages.size() - 1)
	_selector.select(_index)
	var page: Dictionary = pages[_index]
	_body.text = str(page.get("title", "")) + "\n\n" + "\n\n".join(PackedStringArray(page.get("lines", [])))
	_previous.disabled = _index == 0
	_next.disabled = _index == pages.size() - 1
	_voice.visible = not str(page.get("voice_id", "")).is_empty()
	_scroll.scroll_vertical = 0

func _read_page() -> void:
	if pages.is_empty(): return
	voice_requested.emit(str(pages[_index].get("voice_id", "")))

func _focus_close() -> void:
	if is_visible_in_tree():
		_close.focus_mode = Control.FOCUS_ALL
		_close.grab_focus()

func _button(parent: Control, title: String, callback: Callable) -> Button:
	var button := Button.new()
	button.text = title
	button.pressed.connect(callback)
	parent.add_child(button)
	return button
