extends SceneTree
## Production CanvasLayer/containers/font and real Camera3D projection only.
## No Session, pilot, physics body, rule changes, saves or network connection.
## Headless layout evidence is not rendered readability or human usability.
const Interface = preload("res://scripts/v3/twin_interface.gd")
const DEFAULT_SIZE = Vector2i(1280, 720)
const BACKGROUND_MARGIN = Vector2(5, 3)
var viewport: SubViewport
var camera: Camera3D
var ui
var marker
var checks: Array = []
var failures: Array = []
var cases: Array = []

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool, label: String, detail: Dictionary = {}) -> void:
	checks.append({"name":label, "passed":ok})
	if not ok:
		failures.append({"name":label, "detail":detail})
		push_error("TARGET MARKER LAYOUT: " + label + " " + JSON.stringify(detail))

func settle() -> void:
	# Let actual container minimum-size and deferred resize notifications settle.
	for i in range(4): await process_frame

func rect_data(rect: Rect2) -> Array:
	return [rect.position.x, rect.position.y, rect.size.x, rect.size.y]

func caption_background() -> Rect2:
	# Check the actual Label rectangle, including the background drawn outside it.
	# Using its minimum size alone can miss a stale larger rect after text shrinks.
	var rect: Rect2 = marker.caption.get_global_rect()
	return Rect2(rect.position - BACKGROUND_MARGIN, rect.size + BACKGROUND_MARGIN * 2)

func visible_panels() -> Array[Control]:
	var result: Array[Control] = []
	for panel in [ui.top_panel, ui.bottom_panel, ui.task_panel, ui.radio]:
		if panel.is_visible_in_tree(): result.append(panel)
	return result

func inspect_case(label: String, world_target: Vector3) -> Rect2:
	var rect = caption_background()
	var overlaps: Array = []
	for panel in visible_panels():
		var obstacle: Rect2 = panel.get_global_rect()
		if rect.intersects(obstacle):
			overlaps.append({"panel":str(panel.get_path()), "rect":rect_data(obstacle), "intersection":rect_data(rect.intersection(obstacle))})
	var screen = Rect2(Vector2.ZERO, Vector2(viewport.size))
	var projected = camera.unproject_position(world_target)
	var detail = {"caption_background":rect_data(rect), "viewport":rect_data(screen), "projected":[projected.x, projected.y], "overlaps":overlaps}
	check(marker.has_target and marker.is_visible_in_tree() and marker.caption.is_visible_in_tree() and rect.has_area() and screen.encloses(rect) and overlaps.is_empty(), label + " caption is visible inside viewport and outside every visible panel", detail)
	check(marker.world_position == world_target and marker.position.distance_to(projected) < 0.05, label + " retains world target and true projected reticle", {"world_target":str(world_target),"stored":str(marker.world_position),"reticle":str(marker.position),"projection":str(projected)})
	cases.append({"name":label, "details_open":ui.details_open, "radio_visible":ui.radio.visible, "layout":detail})
	return rect

func show_at(label: String, screen_at: Vector2, radius: float = 1.2, title: String = "远端活性根簇", condition: String = "目标被遮挡") -> Rect2:
	# Points may lie outside the viewport but remain in front of the real camera.
	# Only the text may move into the viewport; the target is never edge-clamped.
	var world_target = camera.project_position(screen_at, 50.0)
	marker.show_target(camera, world_target, title, 42.7, -3.8, condition, condition == "目标被遮挡", radius)
	await settle()
	return inspect_case(label, world_target)

func set_panels(expanded: bool, with_radio: bool) -> void:
	if ui.details_open != expanded: ui.details_button.pressed.emit()
	ui.objective.text = "两界的支脉\n让接收器持续受光。"
	ui.target_info.text = "锁定：活性根簇\n缺少光照 · 生长 0%"
	if expanded:
		ui.objective.text += "\n调整环的方向，让光束击中根簇。\n桥上与桥下都可以绕行。\n观察受光状态，再决定如何催生。"
		ui.target_info.text += "\n温度 20° · 光足且温度适宜时可催生。"
	ui.radio.visible = with_radio
	ui.radio_speaker.text = "阿苔 · 根谷守林人"
	ui.radio_text.text = "先看看哪条根脉还在回应光。\n不必一直沿着旧路飞，我们可以从另一侧观察。"
	await settle()
	check(ui.top_panel.get_global_rect().has_area() and ui.bottom_panel.get_global_rect().has_area() and ui.task_panel.get_global_rect().has_area() and ui.radio.is_visible_in_tree() == with_radio, "actual HUD panel fixture expanded=%s radio=%s" % [expanded, with_radio])

func _run() -> void:
	viewport = SubViewport.new()
	viewport.name = "LayoutViewport"
	viewport.size = DEFAULT_SIZE
	viewport.own_world_3d = true
	root.add_child(viewport)
	camera = Camera3D.new()
	camera.name = "ObliqueCamera"
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 26.0
	viewport.add_child(camera)
	camera.position = Vector3(28, 34, 32)
	camera.look_at(Vector3.ZERO, Vector3.UP)
	camera.current = true
	ui = Interface.new()
	viewport.add_child(ui)
	ui.show_game()
	ui.title.text = "巨木神殿"
	ui.vitals.text = "生命 100  能量 100  高度 12.0m / 离地 8.0m  速度 0.0m/s  单人 · 平稳"
	ui.show_ability_context("当前：光束 · 16m", "F 照亮 · X 熄灭", ["light"])
	ui.explore_button.hide()
	ui.gate_button.hide()
	marker = ui.target_marker
	check(ui is CanvasLayer and marker.panel_obstacles.has(ui.top_panel) and marker.panel_obstacles.has(ui.bottom_panel) and marker.panel_obstacles.has(ui.task_panel) and marker.panel_obstacles.has(ui.radio), "production CanvasLayer registers all four actual panels")
	var directions = [
		{"name":"left", "screen":Vector2(-320, 360)},
		{"name":"right", "screen":Vector2(1600, 360)},
		{"name":"top", "screen":Vector2(640, -240)},
		{"name":"bottom", "screen":Vector2(640, 960)},
		{"name":"top-left", "screen":Vector2(-320, -240)},
		{"name":"top-right", "screen":Vector2(1600, -240)},
		{"name":"bottom-left", "screen":Vector2(-320, 960)},
		{"name":"bottom-right", "screen":Vector2(1600, 960)},
	]
	var compact_height = 0.0
	for expanded in [false, true]:
		for with_radio in [false, true]:
			await set_panels(expanded, with_radio)
			if not expanded: compact_height = ui.task_panel.size.y
			else: check(ui.task_panel.size.y > compact_height + 30.0, "expanded task actually occupies more vertical space radio=%s" % with_radio, {"compact_height":compact_height,"expanded_height":ui.task_panel.size.y})
			var prefix = "1280x720 expanded=%s radio=%s " % [expanded, with_radio]
			for row in directions: await show_at(prefix + row.name, row.screen)
			await show_at(prefix + "onscreen boss", Vector2(860, 310), 4.0, "冠兽种心", "装甲闭合")
	# Text length changes must update the measured label bounds in both directions.
	await set_panels(false, true)
	var short_rect = await show_at("short caption before resize", Vector2(-320, -240), 1.2, "根簇", "缺光")
	var long_rect = await show_at("long caption after resize", Vector2(-320, -240), 1.2, "远端根脉接收器与连续受光检修锚点", "能力需再靠近 103.8m")
	var restored_rect = await show_at("short caption restored", Vector2(-320, -240), 1.2, "根簇", "缺光")
	check(long_rect.size.x > short_rect.size.x + 80.0, "long text genuinely changes Label width", {"short":rect_data(short_rect),"long":rect_data(long_rect)})
	check(restored_rect.size.is_equal_approx(short_rect.size), "shortened caption does not retain stale large Label bounds", {"before":rect_data(short_rect),"restored":rect_data(restored_rect)})
	# Real projected body radius, rather than a specific layout offset or scorer.
	for radius in [1.2, 4.0]:
		var centre = Vector2(860, 280)
		var rect = await show_at("silhouette radius %.1fm" % radius, centre, radius, "冠兽种心", "开放")
		var at = camera.project_position(centre, 50.0)
		var projected_radius = centre.distance_to(camera.unproject_position(at + camera.global_basis.x * radius))
		var closest = Vector2(clampf(centre.x, rect.position.x, rect.end.x), clampf(centre.y, rect.position.y, rect.end.y))
		check(centre.distance_to(closest) + 0.05 >= projected_radius, "caption clears projected target silhouette at %.1fm" % radius, {"caption":rect_data(rect),"projected_radius":projected_radius,"nearest_caption_distance":centre.distance_to(closest)})
	# A live viewport resize must recompute projection, anchors and available space.
	for dimensions in [Vector2i(1600, 900), DEFAULT_SIZE]:
		viewport.size = dimensions
		await settle()
		await set_panels(true, true)
		await show_at("resized %s upper-left" % dimensions, Vector2(-320, -240))
		await show_at("resized %s boss" % dimensions, Vector2(dimensions) * Vector2(0.67, 0.4), 4.0, "冠兽种心", "装甲闭合")
	await set_panels(false, false)
	var destination := camera.project_position(Vector2(725, 380), 50.0)
	ui.objective_marker.show_destination(camera, {"position":destination,"label":"检修廊 · 南口 / 东侧高窗"}, Vector3.ZERO)
	await show_at("target beside navigation caption", Vector2(730, 385), 1.2, "检修廊故障栅", "已瞄准")
	var navigation_rect: Rect2 = ui.objective_marker.caption.get_global_rect().grow_individual(4, 2, 4, 2)
	check(not caption_background().intersects(navigation_rect), "selected target and destination backgrounds remain separate at adjacent projected points")
	var stable_caption: Vector2 = marker.caption.global_position
	for i in range(12): await process_frame
	check(marker.caption.global_position.is_equal_approx(stable_caption), "one-way caption avoidance settles without frame-to-frame oscillation")
	ui.objective_marker.clear()
	await test_paused_updates()
	print("TARGET_MARKER_LAYOUT checks=%d failures=%d cases=%d" % [checks.size(), failures.size(), cases.size()])
	print("TARGET_MARKER_LAYOUT_RESULT " + JSON.stringify({"passed":failures.is_empty(),"checks":checks,"cases":cases,"failures":failures,"limits":["Headless production UI/Camera3D layout only; no rendered image, performance or human usability evidence.","Scripted text/panel states and projected target poses; no Session, pilot, rule, save or network access."]}))
	viewport.free()
	quit(0 if failures.is_empty() else 1)

func test_paused_updates() -> void:
	await set_panels(false, false)
	var compact_task: Rect2 = ui.task_panel.get_global_rect()
	# Near the compact task panel's lower edge: expansion can occupy the old
	# label position. Keep this exact world target for every paused check below.
	var world_target = camera.project_position(Vector2(100, compact_task.end.y + 50), 50.0)
	marker.show_target(camera, world_target, "根簇", 42.7, -3.8, "缺光", false, 1.2)
	await settle()
	var initial_rect = inspect_case("before true SceneTree pause", world_target)
	paused = true
	check(paused, "SceneTree is genuinely paused before changing layout")
	# Do not call show_target again here: layout must follow the changed panels
	# through the production marker's own paused-safe processing.
	await set_panels(true, true)
	check(paused and ui.task_panel.get_global_rect().size.y > compact_task.size.y + 30.0 and ui.radio.is_visible_in_tree(), "task expansion and radio activation occur without unpausing", {"old_task":rect_data(compact_task),"new_task":rect_data(ui.task_panel.get_global_rect()),"old_caption_now_overlaps_task":initial_rect.intersects(ui.task_panel.get_global_rect())})
	inspect_case("paused expanded task and active radio", world_target)
	marker.show_target(camera, world_target, "远端根脉接收器与连续受光检修锚点", 42.7, -3.8, "能力需再靠近 103.8m", false, 1.2)
	await settle()
	var long_rect = inspect_case("paused target text grows", world_target)
	check(paused and long_rect.size.x > initial_rect.size.x + 80.0, "paused long text changes actual Label width", {"short":rect_data(initial_rect),"long":rect_data(long_rect)})
	marker.show_target(camera, world_target, "根簇", 42.7, -3.8, "缺光", false, 1.2)
	await settle()
	var short_rect = inspect_case("paused target text shrinks", world_target)
	check(paused and short_rect.size.is_equal_approx(initial_rect.size), "paused short text restores actual Label bounds without a hidden resume", {"original":rect_data(initial_rect),"restored":rect_data(short_rect)})
	for dimensions in [Vector2i(1600, 900), DEFAULT_SIZE]:
		var before_projection = camera.unproject_position(world_target)
		viewport.size = dimensions
		await settle()
		# No show_target/private layout call: camera/viewport changes must update
		# the same target while SceneTree processing remains paused.
		check(paused and before_projection.distance_to(camera.unproject_position(world_target)) > 10.0, "paused viewport resize genuinely changes projection %s" % dimensions)
		inspect_case("paused resized %s same world target" % dimensions, world_target)
	check(paused and marker.world_position == world_target, "entire paused regression preserves the target and never resumes the tree")
