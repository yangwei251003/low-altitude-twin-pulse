extends RefCounted
## Shared native Godot front-end components. No game state or Store writes.
const BG := Color("081e27")
const SURFACE := Color("102c36")
const INK := Color("102e33")
const TEXT := Color("f0f1e7")
const MUTED := Color("a2bbc0")
const ACCENT := Color("85dbc3")
const GOLD := Color("e7bd78")
const LINE := Color("2d4b55")
const FONT_PATH := "res://assets/fonts/NotoSansSC-Medium.ttf"
const FeedbackButton := preload("res://scripts/v3/ui/front/twin_front_button.gd")
static var _font: Font

class CardColumn extends VBoxContainer:
	var background: StyleBoxFlat

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_PASS
		size_flags_horizontal = Control.SIZE_EXPAND_FILL
		add_theme_constant_override("separation", 10)
		resized.connect(queue_redraw)

	func _draw() -> void:
		# Native VBox owns all sizing. Never fight its sort pass with a second
		# deferred layout, which repeatedly changes wrapped-label widths.
		if background != null:
			draw_style_box(background,Rect2(Vector2.ZERO,size).grow(5.0))
			draw_line(Vector2(4, -4), Vector2(minf(36.0, size.x - 4.0), -4), Color("609b93"), 1.0, true)

class TechPanel extends PanelContainer:
	func _init() -> void:
		resized.connect(queue_redraw)

	func _draw() -> void:
		if size.x < 40.0 or size.y < 30.0: return
		# Decoration only; native PanelContainer retains exclusive layout control.
		draw_line(Vector2(20, 3), Vector2(minf(72.0, size.x - 20.0), 3), Color("568f87"), 1.0, true)
		draw_line(Vector2(3, 20), Vector2(3, minf(39.0, size.y - 20.0)), Color("355b62"), 1.0, true)
		for index in range(3):
			var x := size.x - 20.0 - float(index) * 6.0
			draw_line(Vector2(x, size.y - 7.0), Vector2(x - 3.0, size.y - 4.0), Color("567c7a"), 1.0, true)

class HeadingRule extends Control:
	func _init() -> void:
		custom_minimum_size.y = 4
		size_flags_horizontal = Control.SIZE_EXPAND_FILL
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		resized.connect(queue_redraw)

	func _draw() -> void:
		var length := minf(size.x, 190.0)
		draw_line(Vector2.ZERO, Vector2(length, 0), Color("28464f"), 1.0, true)
		draw_line(Vector2.ZERO, Vector2(minf(length, 34.0), 0), Color("85dbc3"), 2.0, true)
		if length > 48.0:
			draw_line(Vector2(40.0, 0), Vector2(48.0, 0), Color("e7bd78"), 2.0, true)

static func label(text: String, size: int = 16, color: Color = Color("e6eee9")) -> Label:
	var node := Label.new()
	node.text = text
	node.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	node.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	node.add_theme_font_override("font", font())
	node.add_theme_font_size_override("font_size", size)
	node.add_theme_color_override("font_color", color)
	return node

static func column(gap: int = 12) -> VBoxContainer:
	var node := VBoxContainer.new()
	node.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	node.add_theme_constant_override("separation",gap)
	return node

static func row(gap: int = 12) -> HBoxContainer:
	var node := HBoxContainer.new()
	node.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	node.add_theme_constant_override("separation",gap)
	return node

static func panel() -> PanelContainer:
	var node := TechPanel.new()
	node.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var style := box(SURFACE,LINE,12,20)
	style.shadow_color = Color(0.0, 0.02, 0.025, 0.22)
	style.shadow_size = 4
	style.shadow_offset = Vector2(0, 3)
	node.add_theme_stylebox_override("panel", style)
	return node

static func card(title: String, body: String = "", eyebrow: String = "") -> VBoxContainer:
	var node := CardColumn.new()
	node.background = box(Color("102b35"),LINE,12,0)
	if not eyebrow.is_empty(): node.add_child(label(eyebrow,11,ACCENT))
	if not title.is_empty(): node.add_child(label(title,21,TEXT))
	if not body.is_empty(): node.add_child(label(body,14,MUTED))
	return node

static func button(text: String, callback: Callable, primary: bool = false) -> Button:
	var node := FeedbackButton.new()
	node.primary = primary
	node.text = text
	node.custom_minimum_size.y = 46
	node.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	node.focus_mode = Control.FOCUS_ALL
	node.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	node.add_theme_font_override("font",font())
	node.add_theme_font_size_override("font_size",16 if primary else 14)
	node.add_theme_color_override("font_color",Color("f2fff7") if primary else TEXT)
	node.add_theme_color_override("font_hover_color",Color("ffffff"))
	node.add_theme_color_override("font_pressed_color",Color("c0fae6") if primary else ACCENT)
	node.add_theme_color_override("font_focus_color",Color("ffffff") if primary else TEXT)
	node.add_theme_color_override("font_disabled_color",Color("647f87"))
	var normal := box(Color("186c65") if primary else Color("132f3a"),Color("8ce1c7") if primary else Color("3b5b65"),6,14)
	if primary:
		normal.shadow_color = Color(0.18, 0.75, 0.60, 0.12)
		normal.shadow_size = 4
	node.add_theme_stylebox_override("normal",normal)
	node.add_theme_stylebox_override("hover",box(Color("218e7e") if primary else Color("20434c"),Color("c3ffe7") if primary else ACCENT,6,14))
	node.add_theme_stylebox_override("pressed",box(Color("104e4b") if primary else Color("0b222c"),Color("65c8af"),6,14))
	node.add_theme_stylebox_override("disabled",box(Color("112a33"),Color("263e48"),6,14))
	var focus := box(Color(0,0,0,0),Color("f0d29a"),6,0)
	focus.draw_center = false
	focus.set_border_width_all(2)
	focus.expand_margin_left = 3
	focus.expand_margin_right = 3
	focus.expand_margin_top = 3
	focus.expand_margin_bottom = 3
	node.add_theme_stylebox_override("focus",focus)
	if callback.is_valid(): node.pressed.connect(callback)
	else:
		node.disabled = true
		node.tooltip_text = "当前操作尚不可用"
	return node

## callback(event: String, primary: bool): hover / focus / press.
## Root can connect the existing UI audio pool here. Existing and future
## buttons respond immediately when reduced motion is changed in Settings.
static func configure_feedback(reduced_motion: bool, callback: Callable = Callable()) -> void:
	FeedbackButton.configure_feedback(reduced_motion, callback)

static func metric(value: String, caption: String) -> VBoxContainer:
	var node := column(3)
	node.add_child(label(value,27,TEXT))
	node.add_child(label(caption,11,MUTED))
	return node

static func heading(title: String, kicker: String, description: String = "") -> VBoxContainer:
	var node := column(8)
	if not kicker.is_empty(): node.add_child(label(kicker,11,ACCENT))
	node.add_child(label(title,32,TEXT))
	node.add_child(HeadingRule.new())
	if not description.is_empty(): node.add_child(label(description,14,MUTED))
	return node

static func grid(columns: int = 2) -> GridContainer:
	var node := GridContainer.new()
	node.columns = maxi(1,columns)
	node.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	node.add_theme_constant_override("h_separation",14)
	node.add_theme_constant_override("v_separation",14)
	return node

static func font() -> Font:
	if _font == null: _font = load(FONT_PATH) as Font
	return _font

static func box(fill: Color, border: Color = LINE, radius: int = 10, padding: int = 16) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	style.border_color = border
	style.set_border_width_all(1)
	style.set_corner_radius_all(radius)
	style.corner_detail = 4
	style.content_margin_left = padding
	style.content_margin_right = padding
	style.content_margin_top = padding
	style.content_margin_bottom = padding
	return style

static func divider() -> HSeparator:
	var line := HSeparator.new()
	line.add_theme_color_override("separator",LINE)
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return line

static func animate_in(root: Control, reduce_motion: bool = false) -> void:
	if reduce_motion: return
	root.modulate.a = 0.0
	var begin := func():
		if not is_instance_valid(root) or not root.is_inside_tree(): return
		var tween := root.create_tween()
		tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
		tween.tween_property(root,"modulate:a",1.0,.2).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	if root.is_inside_tree(): begin.call()
	else: root.ready.connect(begin,CONNECT_ONE_SHOT)
