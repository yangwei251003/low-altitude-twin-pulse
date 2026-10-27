extends Button
## Native Button with short, event-driven cockpit feedback. It never changes
## container geometry, consumes input, or delays the original pressed signal.
const CYAN := Color("a4f2db")
const GOLD := Color("f0d29a")
static var _reduced_motion := false
static var _feedback := Callable()
static var _live_buttons: Array[WeakRef] = []

var primary := false
var _hovered := false
var _focused := false
var _held := false
var _highlight := 0.0
var _depression := 0.0
var _sweep := 1.0
var _pulse := 1.0
var _pulse_origin := Vector2.ZERO
var _pointer_origin := Vector2.ZERO
var _pointer_activation := false
var _was_visible := false

static func configure_feedback(reduced_motion: bool, callback: Callable = Callable()) -> void:
	_reduced_motion = reduced_motion
	_feedback = callback
	# Weak references do not keep closed pages or their callbacks alive.
	for index in range(_live_buttons.size() - 1, -1, -1):
		var node = _live_buttons[index].get_ref()
		if not is_instance_valid(node):
			_live_buttons.remove_at(index)
		else:
			node._apply_motion_setting()

func _init() -> void:
	mouse_entered.connect(_on_mouse_entered)
	mouse_exited.connect(_on_mouse_exited)
	focus_entered.connect(_on_focus_entered)
	focus_exited.connect(_on_focus_exited)
	button_down.connect(_on_button_down)
	button_up.connect(_on_button_up)
	pressed.connect(_on_pressed)
	resized.connect(queue_redraw)
	visibility_changed.connect(_on_visibility_changed)
	set_process(false)

func _enter_tree() -> void:
	_live_buttons.append(weakref(self))
	_apply_motion_setting()

func _exit_tree() -> void:
	# All effects are local scalars; there are no outstanding tweens or timers.
	set_process(false)
	for index in range(_live_buttons.size() - 1, -1, -1):
		var node = _live_buttons[index].get_ref()
		if not is_instance_valid(node) or node == self:
			_live_buttons.remove_at(index)
	_hovered = false
	_focused = false
	_held = false
	_highlight = 0.0
	_depression = 0.0
	_sweep = 1.0
	_pulse = 1.0

func _gui_input(event: InputEvent) -> void:
	# Observing the activation origin does not accept or replace native input.
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			_pointer_activation = true
			_pointer_origin = event.position
	elif event is InputEventKey or event is InputEventJoypadButton or event is InputEventAction:
		_pointer_activation = false

func _process(delta: float) -> void:
	if disabled or not is_visible_in_tree():
		_clear_transients()
		return
	_highlight = move_toward(_highlight, _highlight_target(), delta * 7.5)
	_depression = move_toward(_depression, 1.0 if _held else 0.0, delta * 16.0)
	_sweep = minf(1.0, _sweep + delta / 0.52)
	_pulse = minf(1.0, _pulse + delta / 0.44)
	queue_redraw()
	if is_equal_approx(_highlight, _highlight_target()) and is_equal_approx(_depression, 1.0 if _held else 0.0) and _sweep >= 1.0 and _pulse >= 1.0:
		set_process(false)

func _draw() -> void:
	if size.x < 20.0 or size.y < 16.0:
		return
	var bounds := Rect2(Vector2(4.0, 4.0), size - Vector2(8.0, 8.0))
	var tint := CYAN if primary else Color("85dbc3")
	if disabled:
		# Actual Button.disabled is authoritative, even if set after construction.
		draw_line(Vector2(7.0, size.y * 0.35), Vector2(7.0, size.y * 0.65), Color("36515a"), 1.0, true)
		return
	var strength := _highlight if not _reduced_motion else _highlight_target()
	var edge := Color(tint, 0.35 + strength * 0.55)
	var inset := 1.5 * _depression
	draw_line(Vector2(7.0 + inset, size.y * 0.30), Vector2(7.0 + inset, size.y * 0.70), edge, 2.0, true)
	# Edge-only chrome leaves the title's contrast and native alignment intact.
	draw_line(Vector2(15.0, 3.0 + inset), Vector2(minf(size.x - 15.0, 43.0), 3.0 + inset), Color(tint, 0.28 + strength * 0.25), 1.0, true)
	if primary or strength > 0.01:
		var rail_alpha := (0.13 if primary else 0.0) + strength * 0.17
		draw_line(Vector2(16.0, size.y - 4.0 - inset), Vector2(size.x - 16.0, size.y - 4.0 - inset), Color(tint, rail_alpha), 1.0, true)
		for index in range(2):
			var x := size.x - 9.0 - float(index) * 5.0
			draw_line(Vector2(x - 3.0, size.y - 12.0), Vector2(x, size.y - 16.0), Color(tint, 0.26 + strength * 0.35), 1.0, true)
	if _focused:
		_draw_focus_corners(bounds)
	if _reduced_motion:
		return
	if _sweep < 1.0:
		_draw_sweep(bounds, tint)
	if _pulse < 1.0:
		_draw_pulse(bounds, tint)

func _draw_focus_corners(bounds: Rect2) -> void:
	var x0 := bounds.position.x
	var y0 := bounds.position.y
	var x1 := bounds.end.x
	var y1 := bounds.end.y
	var corner := Color(GOLD, 0.85)
	for point in [Vector2(x0, y0), Vector2(x1, y0), Vector2(x0, y1), Vector2(x1, y1)]:
		var horizontal := 6.0 if point.x == x0 else -6.0
		var vertical := 5.0 if point.y == y0 else -5.0
		draw_line(point, point + Vector2(horizontal, 0.0), corner, 1.0, true)
		draw_line(point, point + Vector2(0.0, vertical), corner, 1.0, true)

func _draw_sweep(bounds: Rect2, tint: Color) -> void:
	# The vertices are clamped inside the button: no overlay captures input and
	# no oversized canvas item spills into adjacent controls or scroll panels.
	var band := minf(52.0, size.x * 0.22)
	var skew := minf(size.y * 0.40, 24.0)
	var travel := lerpf(-band - skew, size.x + band, _sweep)
	var clipped := PackedVector2Array([
		Vector2(clampf(travel, bounds.position.x, bounds.end.x), bounds.position.y),
		Vector2(clampf(travel + band, bounds.position.x, bounds.end.x), bounds.position.y),
		Vector2(clampf(travel + band - skew, bounds.position.x, bounds.end.x), bounds.end.y),
		Vector2(clampf(travel - skew, bounds.position.x, bounds.end.x), bounds.end.y),
	])
	var vertices := PackedVector2Array()
	for point in clipped:
		if vertices.is_empty() or not point.is_equal_approx(vertices[vertices.size() - 1]):
			vertices.append(point)
	if vertices.size() > 1 and vertices[0].is_equal_approx(vertices[vertices.size() - 1]):
		vertices.remove_at(vertices.size() - 1)
	# At entry/exit the clipped band can collapse to a line. Never submit a
	# degenerate polygon to CanvasItem's triangulator.
	if vertices.size() < 3:
		return
	var opacity := sin(_sweep * PI) * (0.11 if primary else 0.08)
	draw_polygon(vertices, PackedColorArray([Color(tint, opacity)]))

func _draw_pulse(bounds: Rect2, tint: Color) -> void:
	var remaining := 1.0 - _pulse
	var expansion := 1.0 - remaining * remaining
	var radius := 5.0 + expansion * minf(104.0, size.x * 0.48)
	var alpha := remaining * 0.70
	# A segmented local wave and four fine sparks; visible for 0.44 seconds.
	# Segment inclusion also clips the ring without changing Control clipping.
	for index in range(48):
		var angle := float(index) / 48.0 * TAU
		var next_angle := float(index + 1) / 48.0 * TAU
		var a := _pulse_origin + Vector2(cos(angle), sin(angle)) * radius
		var b := _pulse_origin + Vector2(cos(next_angle), sin(next_angle)) * radius
		if bounds.has_point(a) and bounds.has_point(b):
			draw_line(a, b, Color(tint, alpha), 1.2, true)
	for index in range(4):
		var angle := 0.45 + float(index) * PI * 0.5
		var direction := Vector2(cos(angle), sin(angle))
		var a := _pulse_origin + direction * (7.0 + expansion * 29.0)
		var b := a + direction * (remaining * 6.0)
		if bounds.has_point(a) and bounds.has_point(b):
			draw_line(a, b, Color(GOLD, alpha * 0.75), 1.0, true)

func _highlight_target() -> float:
	if disabled:
		return 0.0
	return 1.0 if _hovered else (0.65 if _focused else 0.0)

func _on_mouse_entered() -> void:
	_hovered = true
	if disabled:
		return
	_start_sweep()
	_emit_feedback("hover")

func _on_mouse_exited() -> void:
	_hovered = false
	_wake()

func _on_focus_entered() -> void:
	_focused = true
	if disabled:
		return
	if not _hovered:
		_start_sweep()
		_emit_feedback("focus")
	else:
		_wake()

func _on_focus_exited() -> void:
	_focused = false
	_wake()

func _on_button_down() -> void:
	if disabled:
		return
	_held = true
	_wake()

func _on_button_up() -> void:
	_held = false
	_wake()

func _on_pressed() -> void:
	if disabled:
		return
	_pulse_origin = _pointer_origin if _pointer_activation else size * 0.5
	_pulse_origin.x = clampf(_pulse_origin.x, 5.0, maxf(5.0, size.x - 5.0))
	_pulse_origin.y = clampf(_pulse_origin.y, 5.0, maxf(5.0, size.y - 5.0))
	_pointer_activation = false
	if not _reduced_motion:
		_pulse = 0.0
		_sweep = 0.0
	_wake()
	_emit_feedback("press")

func _emit_feedback(event: String) -> void:
	if _feedback.is_valid() and is_inside_tree() and is_visible_in_tree():
		_feedback.call(event, primary)

func _start_sweep() -> void:
	if not _reduced_motion:
		_sweep = 0.0
	_wake()

func _wake() -> void:
	if _reduced_motion:
		_apply_motion_setting()
	elif is_inside_tree() and is_visible_in_tree() and not disabled:
		set_process(true)
	queue_redraw()

func _apply_motion_setting() -> void:
	if _reduced_motion:
		_sweep = 1.0
		_pulse = 1.0
		_highlight = _highlight_target()
		_depression = 0.0
		set_process(false)
	queue_redraw()

func _clear_transients() -> void:
	_highlight = 0.0
	_depression = 0.0
	_sweep = 1.0
	_pulse = 1.0
	_held = false
	set_process(false)
	queue_redraw()

func _on_visibility_changed() -> void:
	var showing := is_visible_in_tree()
	if not showing:
		_hovered = false
		_focused = false
		_clear_transients()
	elif not _was_visible:
		_focused = has_focus()
		_apply_motion_setting()
	_was_visible = showing
