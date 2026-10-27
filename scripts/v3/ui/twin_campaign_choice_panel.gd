extends PanelContainer
## Explicit reading and decision UI. Host still verifies range, eligibility,
## all read acknowledgements and party consensus before a durable choice.
signal read_requested(target_id: String, option: String)
signal choice_requested(target_id: String, option: String)
var _target := ""
var _read: Dictionary = {}
var _buttons: Array[Button] = []
var _content: VBoxContainer
var _review_only := false

func _ready() -> void:
	set_anchors_preset(Control.PRESET_CENTER)
	offset_left = -350
	offset_right = 350
	offset_top = -285
	offset_bottom = 285
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)
	_content = VBoxContainer.new()
	_content.custom_minimum_size.x = 650
	_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_content.add_theme_constant_override("separation",12)
	scroll.add_child(_content)
	hide()

func show_offer(spec: Dictionary, read_options: Array = [], review_only := false) -> void:
	if not spec.get("options") is Array or spec.options.size() < 2 or spec.options.size() > 3: return
	for child in _content.get_children():
		_content.remove_child(child)
		child.queue_free()
	_buttons.clear()
	_read.clear()
	_target = str(spec.get("target_id", ""))
	_review_only = review_only
	for option in read_options: _read[str(option)] = true
	_label(str(spec.get("title","共同决定")),24)
	_label("先逐项阅读收益与负担。提交后会保留选择前分支；合作时需双方确认。",15)
	for option: Dictionary in spec.options:
		var id: String = str(option.id)
		_label(str(option.label),20)
		_label("收益："+str(option.benefit)+"\n负担："+str(option.cost),16)
		var read_button := CheckBox.new()
		read_button.text = "已读这项方案的收益与负担"
		read_button.set_pressed_no_signal(_read.has(id))
		read_button.focus_mode = Control.FOCUS_ALL
		_content.add_child(read_button)
		read_button.toggled.connect(func(checked: bool):
			if checked:
				_read[id] = true
				read_requested.emit(_target,id)
			else: _read.erase(id)
			_update_choices(spec.options.size()))
		if not review_only:
			var choose := Button.new()
			choose.text = "提出："+str(option.label)
			choose.custom_minimum_size.y = 38
			choose.focus_mode = Control.FOCUS_ALL
			_content.add_child(choose)
			_buttons.append(choose)
			choose.pressed.connect(func(): choice_requested.emit(_target,id); hide())
	var close := Button.new()
	close.text = "返回，继续考虑"
	close.custom_minimum_size.y = 38
	_content.add_child(close)
	close.pressed.connect(hide)
	_update_choices(spec.options.size())
	show()
	close.grab_focus()

func _update_choices(required: int) -> void:
	for button in _buttons: button.disabled = _read.size() != required

func _label(value: String, size: int) -> void:
	var label := Label.new()
	label.text = value
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size",size)
	_content.add_child(label)
