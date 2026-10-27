class_name TwinAudioSettingsV3
extends VBoxContainer
## Add to the menu's scrolling VBox, then call setup(audio_manager).
## Changes are audible immediately; saving is debounced and never changes mute.

const CHANNELS := [["master","主音量"],["music","背景音乐"],["sfx","音效"],["ambient","环境"],["rotor","旋翼"],["ui","界面提示"]]
var _manager: WeakRef
var _content: VBoxContainer
var _toggle: Button
var _mute: CheckButton
var _preview: Button
var _hint: Label
var _save_timer: Timer
var _sliders: Dictionary = {}
var _values: Dictionary = {}
var _refreshing := false
var _pending_save := false

func setup(audio_manager: Node) -> void:
	_manager = weakref(audio_manager)
	if _content == null: _build()
	refresh()

func refresh() -> void:
	var manager = _audio()
	if manager == null or _content == null: return
	_refreshing = true
	var mix: Dictionary = manager.get_mix()
	for entry in CHANNELS:
		var key: String = entry[0]
		_sliders[key].value = roundf(float(mix.get(key, 0.8)) * 100.0)
		_values[key].text = "%d%%" % int(_sliders[key].value)
	_mute.button_pressed = bool(mix.get("mute", false))
	_refreshing = false
	_hint.text = "音量会自动保存。静音时试听也保持静音。"

func _build() -> void:
	name = "AudioSettings"
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_theme_constant_override("separation", 6)
	_toggle = Button.new()
	_toggle.name = "SoundToggle"
	_toggle.text = "声音  ▸"
	_toggle.toggle_mode = true
	_toggle.alignment = HORIZONTAL_ALIGNMENT_LEFT
	_toggle.focus_mode = Control.FOCUS_ALL
	_toggle.custom_minimum_size.y = 36
	_toggle.tooltip_text = "展开音量设置"
	_toggle.toggled.connect(func(open: bool):
		_content.visible = open
		_toggle.text = "声音  ▾" if open else "声音  ▸"
		_toggle.tooltip_text = "收起音量设置" if open else "展开音量设置"
		if open: refresh()
	)
	add_child(_toggle)
	_content = VBoxContainer.new()
	_content.name = "SoundControls"
	_content.add_theme_constant_override("separation", 7)
	add_child(_content)
	var focus_order: Array[Control] = [_toggle]
	for entry in CHANNELS:
		var key: String = entry[0]
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		_content.add_child(row)
		var label := Label.new()
		label.text = str(entry[1])
		label.custom_minimum_size.x = 88
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		row.add_child(label)
		var slider := HSlider.new()
		slider.name = "Volume_" + key
		slider.min_value = 0
		slider.max_value = 100
		slider.step = 5
		slider.focus_mode = Control.FOCUS_ALL
		slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		slider.custom_minimum_size = Vector2(125, 32)
		slider.tooltip_text = str(entry[1]) + "：方向键或手柄左右调整"
		row.add_child(slider)
		var value := Label.new()
		value.custom_minimum_size.x = 46
		value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		value.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		row.add_child(value)
		_sliders[key] = slider
		_values[key] = value
		slider.value_changed.connect(func(amount: float): _changed_channel(key, amount))
		focus_order.append(slider)
	_mute = CheckButton.new()
	_mute.name = "Mute"
	_mute.text = "静音"
	_mute.focus_mode = Control.FOCUS_ALL
	_mute.custom_minimum_size.y = 36
	_mute.toggled.connect(func(muted: bool):
		if _refreshing: return
		var manager = _audio()
		if manager == null: return
		manager.set_mix({"mute":muted}, false)
		_hint.text = "当前已静音" if muted else "静音已关闭"
		_schedule_save()
	)
	_content.add_child(_mute)
	focus_order.append(_mute)
	_preview = Button.new()
	_preview.name = "PreviewSound"
	_preview.text = "试听提示音"
	_preview.focus_mode = Control.FOCUS_ALL
	_preview.custom_minimum_size.y = 36
	_preview.pressed.connect(func():
		var manager = _audio()
		if manager == null: return
		manager.preview_mix()
		var mix: Dictionary = manager.get_mix()
		_hint.text = "当前已静音" if bool(mix.get("mute", false)) else "试听提示音"
	)
	_content.add_child(_preview)
	focus_order.append(_preview)
	_hint = Label.new()
	_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_hint.add_theme_font_size_override("font_size", 13)
	_hint.modulate = Color("adc5c0")
	_content.add_child(_hint)
	# UI focus uses the same visible order for keyboard and controller. The
	# first/last items retain automatic links to other controls in the menu.
	for index in range(focus_order.size()):
		var control: Control = focus_order[index]
		if index > 0:
			control.focus_neighbor_top = control.get_path_to(focus_order[index - 1])
			control.focus_previous = control.get_path_to(focus_order[index - 1])
		if index + 1 < focus_order.size():
			control.focus_neighbor_bottom = control.get_path_to(focus_order[index + 1])
			control.focus_next = control.get_path_to(focus_order[index + 1])
	_save_timer = Timer.new()
	_save_timer.name = "SaveAudioPreferences"
	_save_timer.wait_time = 0.35
	_save_timer.one_shot = true
	_save_timer.timeout.connect(_flush_save)
	add_child(_save_timer)
	_content.hide()

func _changed_channel(key: String, amount: float) -> void:
	_values[key].text = "%d%%" % int(amount)
	if _refreshing: return
	var manager = _audio()
	if manager == null: return
	manager.set_mix({key:amount / 100.0}, false)
	_schedule_save()

func _schedule_save() -> void:
	_pending_save = true
	if is_inside_tree(): _save_timer.start()

func _flush_save() -> void:
	if not _pending_save: return
	var manager = _audio()
	if manager != null: manager.set_mix({}, true)
	_pending_save = false

func _audio():
	return _manager.get_ref() if _manager != null else null

func _exit_tree() -> void:
	_flush_save()
