extends Node2D
## One destination cue, distinct from the selected interaction target.
## It reveals the current authored objective only, never a required route.
var camera: Camera3D
var destination := Vector3.ZERO
var caption: Label
var active := false
var at_edge := false
var direction := Vector2.UP
var obstacles: Array[Control] = []

func _ready() -> void:
	caption = Label.new()
	caption.mouse_filter = Control.MOUSE_FILTER_IGNORE
	caption.add_theme_font_override("font", load("res://assets/fonts/NotoSansSC-Medium.ttf"))
	caption.add_theme_font_size_override("font_size", 14)
	caption.add_theme_color_override("font_color", Color("aee3d2"))
	caption.add_theme_constant_override("outline_size", 3)
	caption.add_theme_color_override("font_outline_color", Color("102023"))
	add_child(caption)
	hide()

func show_destination(view_camera: Camera3D, anchor: Dictionary, pilot: Vector3) -> void:
	active = not anchor.is_empty() and anchor.get("position") is Vector3 and anchor.position.is_finite()
	if not active: clear(); return
	camera = view_camera
	destination = anchor.position
	caption.text = "%s · %.0fm\n高差 %+.1fm" % [anchor.label, pilot.distance_to(destination), destination.y - pilot.y]
	_update_position()

func clear() -> void:
	active = false
	hide()

func _process(_delta: float) -> void:
	_update_position()

func _update_position() -> void:
	visible = active and is_instance_valid(camera)
	if not visible: return
	var viewport_size = get_viewport_rect().size
	# Keep the cue within the play area, clear of the persistent top/left/bottom HUD.
	var safe = Rect2(Vector2(320, 120), Vector2(maxf(100, viewport_size.x - 360), maxf(100, viewport_size.y - 272)))
	var projected = camera.unproject_position(destination)
	var centre = safe.get_center()
	var offset = projected - centre
	direction = offset.normalized() if offset.length_squared() > 0.01 else Vector2.UP
	at_edge = not safe.has_point(projected) or camera.is_position_behind(destination)
	if at_edge:
		var scale = minf((safe.size.x * 0.5) / maxf(absf(direction.x), 0.0001), (safe.size.y * 0.5) / maxf(absf(direction.y), 0.0001))
		position = centre + direction * scale
	else: position = projected
	var size = caption.get_minimum_size()
	var offsets = [Vector2(18, -size.y * 0.5), Vector2(-18 - size.x, -size.y * 0.5), Vector2(-size.x * 0.5, 18), Vector2(-size.x * 0.5, -18 - size.y)]
	var best = Vector2.ZERO
	var best_score = INF
	for candidate: Vector2 in offsets:
		var at = position + candidate
		at.x = clampf(at.x, 12, maxf(12, viewport_size.x - size.x - 12))
		at.y = clampf(at.y, 12, maxf(12, viewport_size.y - size.y - 140))
		var rect = Rect2(at - Vector2(4, 2), size + Vector2(8, 4))
		var score = at.distance_to(position + candidate)
		for panel in obstacles:
			if is_instance_valid(panel) and panel.is_visible_in_tree(): score += rect.intersection(panel.get_global_rect()).get_area() * 5
		if score < best_score:
			best_score = score
			best = at - position
	caption.position = best
	queue_redraw()

func _draw() -> void:
	var tint = Color("9edec8")
	if at_edge:
		var tip = direction * 10
		var back = -direction * 6
		var side = direction.orthogonal() * 6
		draw_colored_polygon(PackedVector2Array([tip, back + side, back - side]), tint)
	else:
		draw_arc(Vector2.ZERO, 8, 0, TAU, 24, Color("102023"), 5, true)
		draw_arc(Vector2.ZERO, 8, 0, TAU, 24, tint, 1.8, true)
	var rect = Rect2(caption.position - Vector2(4, 2), caption.get_minimum_size() + Vector2(8, 4))
	draw_rect(rect, Color(0.025, 0.075, 0.08, 0.85))
