extends Node2D
## A selected world target, visually distinct from the pilot's corner brackets.
var camera: Camera3D
var world_position := Vector3.ZERO
var caption: Label
var tint := Color("f2d49c")
var obstructed := false
var has_target := false
var clearance_metres := 1.2
var panel_obstacles: Array[Control] = []

func _ready() -> void:
	# Presentation must follow container resizing even while the world is paused.
	process_mode = Node.PROCESS_MODE_ALWAYS
	caption = Label.new()
	caption.position = Vector2(16, -27)
	caption.mouse_filter = Control.MOUSE_FILTER_IGNORE
	caption.add_theme_font_override("font", load("res://assets/fonts/NotoSansSC-Medium.ttf"))
	caption.add_theme_font_size_override("font_size", 14)
	caption.add_theme_constant_override("outline_size", 3)
	caption.add_theme_color_override("font_outline_color", Color("102023"))
	add_child(caption)
	hide()

func show_target(view_camera: Camera3D, at: Vector3, title: String, distance: float, height_delta: float, condition: String, blocked: bool, silhouette_radius: float = 1.2) -> void:
	camera = view_camera
	world_position = at
	has_target = at.is_finite()
	obstructed = blocked
	clearance_metres = maxf(silhouette_radius, 0.6)
	tint = Color("b9c4c3") if blocked else Color("f2d49c")
	caption.text = "%s · %s\n%.1fm · %s %.1fm" % [title, condition, distance, "高" if height_delta >= 0.0 else "低", absf(height_delta)]
	caption.reset_size()
	caption.add_theme_color_override("font_color", Color("dce5e3") if blocked else Color("fff0d1"))
	_update_position()
	queue_redraw()

func clear_target() -> void:
	has_target = false
	hide()

func _process(_delta: float) -> void:
	_update_position()

func _update_position() -> void:
	visible = has_target and is_instance_valid(camera) and not camera.is_position_behind(world_position)
	if not visible: return
	position = camera.unproject_position(world_position)
	# Keep text beyond the target silhouette rather than covering its weak point.
	# Camera projection sets the gap, so zooming in preserves this separation.
	var projected_edge = camera.unproject_position(world_position + camera.global_basis.x * clearance_metres)
	var gap = maxf(32.0, position.distance_to(projected_edge) + 16.0)
	var size = caption.get_minimum_size()
	var viewport_size = get_viewport_rect().size
	# Include the drawn background, not only the Label, inside the safe area.
	var safe = Rect2(Vector2(17, 15), viewport_size - Vector2(34, 30))
	var offsets = [Vector2(gap, -size.y * 0.5), Vector2(-gap - size.x, -size.y * 0.5), Vector2(-size.x * 0.5, -gap - size.y), Vector2(-size.x * 0.5, gap)]
	var xs: Array[float] = [safe.position.x, maxf(safe.position.x, safe.end.x - size.x)]
	var ys: Array[float] = [safe.position.y, maxf(safe.position.y, safe.end.y - size.y)]
	var blocked_rects: Array[Rect2] = []
	for offset: Vector2 in offsets:
		xs.append(position.x + offset.x)
		ys.append(position.y + offset.y)
	# A far offscreen target collapses all four usual candidates onto one corner.
	# Panel edges add actual free locations, including below an expanded task panel.
	for panel in panel_obstacles:
		if not is_instance_valid(panel) or not panel.is_visible_in_tree(): continue
		var obstacle = panel.get_global_rect()
		blocked_rects.append(obstacle)
		xs.append(obstacle.position.x - size.x - 13.0)
		xs.append(obstacle.end.x + 13.0)
		ys.append(obstacle.position.y - size.y - 11.0)
		ys.append(obstacle.end.y + 11.0)
	var best = Vector2.ZERO
	var best_overlap = INF
	var best_score = INF
	var silhouette = Rect2(position - Vector2.ONE * (gap - 12), Vector2.ONE * (gap - 12) * 2)
	for x in xs:
		for y in ys:
			var at = Vector2(clampf(x, xs[0], xs[1]), clampf(y, ys[0], ys[1]))
			var rect = Rect2(at - Vector2(5, 3), size + Vector2(10, 6))
			var overlap = 0.0
			for obstacle in blocked_rects: overlap += rect.intersection(obstacle).get_area()
			var score = rect.intersection(silhouette).get_area() * 3.0 + rect.get_center().distance_to(position)
			if overlap < best_overlap or (is_equal_approx(overlap, best_overlap) and score < best_score):
				best_overlap = overlap
				best_score = score
				best = at - position
	if not caption.position.is_equal_approx(best):
		caption.position = best
		queue_redraw()

func _draw() -> void:
	if is_instance_valid(caption):
		var rect = Rect2(caption.position - Vector2(5, 3), caption.get_minimum_size() + Vector2(10, 6))
		var end = Vector2(clampf(0, rect.position.x, rect.end.x), clampf(0, rect.position.y, rect.end.y))
		if end.length() > 22:
			draw_line(end.normalized() * 17.0, end, Color(tint, 0.55), 1.0, true)
		draw_rect(rect, Color(0.025, 0.075, 0.08, 0.88))
	for index in range(4):
		var a = Vector2.UP.rotated(float(index) * PI * 0.5) * 12.0
		var b = Vector2.UP.rotated(float(index + 1) * PI * 0.5) * 12.0
		if obstructed: b = a.lerp(b, 0.55)
		draw_line(a, b, Color("102023"), 5.0, true)
		draw_line(a, b, tint, 1.8, true)
