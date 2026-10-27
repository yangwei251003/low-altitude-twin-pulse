extends PanelContainer
## Read-only notebook. Tracking is a local navigation preference, never a fact.
signal track_requested(anchor: Dictionary)
signal close_requested
var _document: Dictionary = {}
var _region := "I1"
var _selector: OptionButton
var _body: VBoxContainer
var _scroll: ScrollContainer
var _close: Button

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	offset_left = -420
	offset_right = 420
	offset_top = -285
	offset_bottom = 285
	var panel := StyleBoxFlat.new()
	panel.bg_color = Color("101e24")
	panel.border_color = Color("35525a")
	panel.set_border_width_all(1)
	panel.set_corner_radius_all(8)
	add_theme_stylebox_override("panel", panel)
	var margin := MarginContainer.new()
	for side: String in ["left", "top", "right", "bottom"]: margin.add_theme_constant_override("margin_" + side, 16)
	add_child(margin)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 10)
	margin.add_child(column)
	var header := HBoxContainer.new()
	column.add_child(header)
	var title := Label.new()
	title.text = "小队纪事 · 航路、委托与发现"
	title.add_theme_font_size_override("font_size", 22)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	var main_route := Button.new()
	main_route.text = "追踪主线"
	main_route.pressed.connect(func(): track_requested.emit({}))
	header.add_child(main_route)
	_close = Button.new()
	_close.text = "返回飞行"
	_close.pressed.connect(func(): close_requested.emit())
	header.add_child(_close)
	_selector = OptionButton.new()
	_selector.item_selected.connect(func(index: int):
		_region = str(_selector.get_item_metadata(index))
		_render()
	)
	column.add_child(_selector)
	_scroll = ScrollContainer.new()
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	column.add_child(_scroll)
	_body = VBoxContainer.new()
	_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_body.add_theme_constant_override("separation", 10)
	_scroll.add_child(_body)
	visible = false

func show_document(document: Dictionary) -> void:
	_document = document.duplicate(true)
	_region = str(document.get("region", "I1"))
	_selector.clear()
	var selected := 0
	for book: Dictionary in document.get("regions", []):
		var index := _selector.item_count
		_selector.add_item(str(book.get("name", book.get("id", ""))))
		_selector.set_item_metadata(index, str(book.get("id", "")))
		if str(book.get("id", "")) == _region: selected = index
	_selector.select(selected)
	_render()
	show()
	_focus_close.call_deferred()

func _focus_close() -> void:
	if not is_visible_in_tree(): return
	_close.focus_mode = Control.FOCUS_ALL
	_close.grab_focus()

func _render() -> void:
	for child in _body.get_children():
		_body.remove_child(child)
		child.queue_free()
	var selected: Dictionary = {}
	for book: Dictionary in _document.get("regions", []):
		if book.get("id") == _region: selected = book; break
	if selected.is_empty(): return
	_text(str(selected.get("summary", "")), 15, Color("b8cacb"))
	for section: Dictionary in selected.get("sections", []):
		_text(str(section.get("title", "")), 19, Color("8dd4bf"))
		for row: Dictionary in section.get("rows", []):
			var line := HBoxContainer.new()
			_body.add_child(line)
			var label := Label.new()
			label.text = str(row.get("title", "")) + (" · " + str(row.status) if not str(row.get("status", "")).is_empty() else "")
			label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			label.add_theme_font_size_override("font_size", 16)
			line.add_child(label)
			if row.get("anchor") is Dictionary and not row.anchor.is_empty():
				var anchor: Dictionary = row.anchor.duplicate(true)
				var button := Button.new()
				button.text = "追踪"
				button.pressed.connect(func(): track_requested.emit(anchor))
				line.add_child(button)
			_text(str(row.get("text", "")), 14, Color("c9d8d3"))
	_scroll.scroll_vertical = 0

func _text(text: String, size: int, color: Color) -> void:
	if text.is_empty(): return
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	_body.add_child(label)
