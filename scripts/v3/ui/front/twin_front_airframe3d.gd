extends Control
## A local, read-only airframe turntable. It never instantiates a session or a
## flight body: FleetVisuals supplies the same editable GLB meshes used in play.
## The owning page frees this Control to release its isolated viewport/world.
const Fleet = preload("res://scripts/v2/fleet_visuals.gd")
const Kit = preload("res://scripts/v3/ui/front/twin_front_kit.gd")
const FRAME_IDS := ["tr01", "hx02", "ag03", "nx04", "sh05", "at06"]
const DEFAULT_YAW := -0.48
const DRAW_INTERVAL := 1.0 / 30.0

var _frame_id := "tr01"
var _definition: Dictionary = {}
var _slots: Dictionary = {}
var _accent := Color("85dbc3")
var _reduce_motion := false
var _viewport: SubViewport
var _texture: TextureRect
var _scene: Node3D
var _pivot: Node3D
var _airframe: Node3D
var _camera: Camera3D
var _rim_light: DirectionalLight3D
var _ring_material: StandardMaterial3D
var _hint: Label
var _badge: Label
var _controls: HBoxContainer
var _yaw := DEFAULT_YAW
var _pitch := 0.0
var _time := 0.0
var _tick := 0.0
var _manual_hold := 0.0
var _dragging := false
var _touch_index := -1
var _hovered := false
var _dirty := true
var _was_shown := false


func _init() -> void:
	name = "Airframe3DPreview"
	custom_minimum_size = Vector2(0, 280)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mouse_filter = Control.MOUSE_FILTER_PASS
	focus_mode = Control.FOCUS_ALL
	mouse_default_cursor_shape = Control.CURSOR_DRAG
	tooltip_text = "拖动查看当前机体与配装；聚焦后左右键转向，Enter 复位。滚轮仍滚动页面。"
	clip_contents = true
	resized.connect(_resize_view)
	visibility_changed.connect(_visibility_changed)
	mouse_entered.connect(func(): _hovered = true; queue_redraw())
	mouse_exited.connect(func(): _hovered = false; _dragging = false; queue_redraw())
	focus_entered.connect(queue_redraw)
	focus_exited.connect(func(): _dragging = false; queue_redraw())


func set_airframe(frame_id: String, definition: Dictionary = {}, slots: Dictionary = {}) -> void:
	_frame_id = frame_id if frame_id in FRAME_IDS else "tr01"
	_definition = definition.duplicate(true)
	_slots = slots.duplicate(true)
	if is_node_ready(): _replace_airframe()


func set_reduce_motion(value: bool) -> void:
	_reduce_motion = value
	if _reduce_motion and is_instance_valid(_pivot):
		_pivot.position.y = 0.12
	_dirty = true


func set_accent(value: Color) -> void:
	_accent = value
	if is_instance_valid(_ring_material):
		_ring_material.albedo_color = _accent
		_ring_material.emission = _accent
	if is_instance_valid(_rim_light): _rim_light.light_color = _accent
	if is_instance_valid(_badge): _badge.add_theme_color_override("font_color", _accent)
	_dirty = true
	queue_redraw()


func _ready() -> void:
	_texture = TextureRect.new()
	_texture.name = "ModelRender"
	_texture.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_texture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_texture.stretch_mode = TextureRect.STRETCH_SCALE
	add_child(_texture)
	_texture.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_texture.offset_top = 14
	_texture.offset_bottom = -34
	_viewport = SubViewport.new()
	_viewport.name = "AirframeViewport"
	_viewport.size = Vector2i(480, 300)
	_viewport.own_world_3d = true
	_viewport.transparent_bg = true
	_viewport.gui_disable_input = true
	_viewport.audio_listener_enable_2d = false
	_viewport.audio_listener_enable_3d = false
	_viewport.physics_object_picking = false
	_viewport.msaa_3d = Viewport.MSAA_2X
	_viewport.positional_shadow_atlas_size = 0
	_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(_viewport)
	_texture.texture = _viewport.get_texture()
	_build_stage()
	_build_controls()
	_replace_airframe()
	_resize_view()
	set_accent(_accent)
	set_reduce_motion(_reduce_motion)
	set_process(true)


func _build_stage() -> void:
	_scene = Node3D.new()
	_scene.name = "DisplayStage"
	_viewport.add_child(_scene)
	var environment := WorldEnvironment.new()
	var lighting := Environment.new()
	lighting.background_mode = Environment.BG_COLOR
	lighting.background_color = Color(0, 0, 0, 0)
	lighting.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	lighting.ambient_light_color = Color("9ab8b6")
	lighting.ambient_light_energy = 0.65
	lighting.reflected_light_source = Environment.REFLECTION_SOURCE_DISABLED
	lighting.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	# No realtime shadows, screen-space effects, glow buffers, physics or audio.
	environment.environment = lighting
	_scene.add_child(environment)
	var key := DirectionalLight3D.new()
	key.name = "SoftKey"
	key.light_color = Color("fff1d9")
	key.light_energy = 1.15
	key.rotation_degrees = Vector3(-48, -28, 0)
	key.shadow_enabled = false
	_scene.add_child(key)
	_rim_light = DirectionalLight3D.new()
	_rim_light.name = "TealRim"
	_rim_light.light_energy = 0.75
	_rim_light.rotation_degrees = Vector3(-18, 142, 0)
	_rim_light.shadow_enabled = false
	_scene.add_child(_rim_light)
	_camera = Camera3D.new()
	_camera.name = "PreviewCamera"
	_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	_camera.keep_aspect = Camera3D.KEEP_HEIGHT
	_camera.size = 2.6
	_camera.near = 0.05
	_camera.far = 30.0
	_scene.add_child(_camera)
	_camera.position = Vector3(3.4, 2.8, 4.6)
	_camera.look_at(Vector3(0, 0.05, 0), Vector3.UP)
	_camera.current = true
	_pivot = Node3D.new()
	_pivot.name = "Turntable"
	_pivot.position.y = 0.12
	_scene.add_child(_pivot)
	var platform := CylinderMesh.new()
	platform.top_radius = 1.52
	platform.bottom_radius = 1.45
	platform.height = 0.07
	platform.radial_segments = 48
	platform.rings = 1
	var platform_material := StandardMaterial3D.new()
	platform_material.albedo_color = Color("15333d")
	platform_material.metallic = 0.48
	platform_material.roughness = 0.44
	_mesh(platform, platform_material, Vector3(0, -0.5, 0))
	_ring_material = StandardMaterial3D.new()
	_ring_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_ring_material.emission_enabled = true
	_ring_material.emission_energy_multiplier = 1.1
	for radius: float in [1.52, 1.27]:
		var ring := TorusMesh.new()
		ring.inner_radius = radius - 0.008
		ring.outer_radius = radius + 0.008
		ring.rings = 48
		ring.ring_segments = 6
		_mesh(ring, _ring_material, Vector3(0, -0.455, 0))
	# Four small docking ticks make a readable spatial reference while rotating.
	for index in range(4):
		var tick_mesh := BoxMesh.new()
		tick_mesh.size = Vector3(0.045, 0.018, 0.18)
		var angle := PI * 0.5 * float(index)
		var tick := _mesh(tick_mesh, _ring_material, Vector3(sin(angle) * 1.39, -0.446, cos(angle) * 1.39))
		tick.rotation.y = angle


func _mesh(mesh: Mesh, material: Material, position_value: Vector3) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.material_override = material
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	instance.position = position_value
	_scene.add_child(instance)
	return instance


func _build_controls() -> void:
	_badge = Kit.label("3D  /  当前配装", 10, _accent)
	_badge.autowrap_mode = TextServer.AUTOWRAP_OFF
	add_child(_badge)
	_badge.position = Vector2(12, 8)
	_hint = Kit.label("拖动旋转 · ← → 转向 · Enter 复位", 10, Color("b9d0cf"))
	_hint.autowrap_mode = TextServer.AUTOWRAP_OFF
	_hint.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	add_child(_hint)
	_hint.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	_hint.offset_left = 12
	_hint.offset_top = -29
	_hint.offset_bottom = -5
	_hint.offset_right = -140
	_controls = HBoxContainer.new()
	_controls.add_theme_constant_override("separation", 4)
	_controls.mouse_filter = Control.MOUSE_FILTER_PASS
	add_child(_controls)
	_controls.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	_controls.offset_left = -130
	_controls.offset_right = -8
	_controls.offset_top = -31
	_controls.offset_bottom = -3
	var left := _turn_button("‹", "向左旋转", func(): _rotate_manual(-PI / 8.0, 0.0))
	var reset := _turn_button("复位", "还原展示角度", _reset_view)
	var right := _turn_button("›", "向右旋转", func(): _rotate_manual(PI / 8.0, 0.0))
	_controls.add_child(left)
	_controls.add_child(reset)
	_controls.add_child(right)


func _turn_button(caption: String, hint: String, callback: Callable) -> Button:
	var button := Kit.button(caption, callback)
	button.custom_minimum_size = Vector2(28, 28)
	button.tooltip_text = hint
	button.add_theme_font_size_override("font_size", 12)
	button.add_theme_stylebox_override("normal", Kit.box(Color(0.04, 0.13, 0.17, 0.72), Color("365f67"), 4, 5))
	button.add_theme_stylebox_override("hover", Kit.box(Color("21474e"), _accent, 4, 5))
	button.add_theme_stylebox_override("pressed", Kit.box(Color("0e262e"), _accent, 4, 5))
	return button


func _replace_airframe() -> void:
	if not is_instance_valid(_pivot): return
	if is_instance_valid(_airframe):
		_pivot.remove_child(_airframe)
		_airframe.queue_free()
	_airframe = Fleet.make_drone(_frame_id, _slots)
	_airframe.name = "Displayed_" + _frame_id
	_airframe.process_mode = Node.PROCESS_MODE_DISABLED
	_pivot.add_child(_airframe)
	var bounds: Dictionary = {"found": false, "box": AABB()}
	_collect_bounds(_airframe, Transform3D.IDENTITY, bounds)
	if bool(bounds.found):
		var box: AABB = bounds.box
		var span := maxf(maxf(box.size.x, box.size.z), box.size.y)
		var scale_value := 2.40 / maxf(span, 0.1)
		_airframe.scale = Vector3.ONE * scale_value
		_airframe.position = -box.get_center() * scale_value
	_reset_view()
	_badge.text = _frame_id.to_upper() + "  /  当前机体与配装"
	_badge.tooltip_text = str(_definition.get("name", _frame_id))
	_dirty = true


func _collect_bounds(node: Node, inherited: Transform3D, result: Dictionary) -> void:
	var local := inherited
	if node is Node3D: local = inherited * (node as Node3D).transform
	if node is MeshInstance3D and (node as MeshInstance3D).mesh != null:
		var mesh_instance := node as MeshInstance3D
		mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var box: AABB = local * mesh_instance.get_aabb()
		var accumulated: AABB = result.box
		result.box = accumulated.merge(box) if bool(result.found) else box
		result.found = true
	for child: Node in node.get_children(): _collect_bounds(child, local, result)


func _resize_view() -> void:
	if not is_instance_valid(_viewport): return
	var available := Vector2(maxf(2.0, size.x), maxf(2.0, size.y - 48.0))
	var ratio := minf(1.0, minf(640.0 / available.x, 400.0 / available.y))
	var target := Vector2i(maxi(2, roundi(available.x * ratio)), maxi(2, roundi(available.y * ratio)))
	if _viewport.size != target: _viewport.size = target
	if is_instance_valid(_camera):
		var aspect := float(target.x) / float(target.y)
		_camera.size = maxf(2.6, 3.6 / maxf(0.2, aspect))
	_dirty = true
	queue_redraw()


func _visibility_changed() -> void:
	if not is_visible_in_tree():
		_dragging = false
		_touch_index = -1
		if is_instance_valid(_viewport): _viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	else:
		_dirty = true
	_was_shown = false


func _shown_in_canvas() -> bool:
	if not is_visible_in_tree() or size.x < 2.0 or size.y < 2.0: return false
	var visible_rect := get_global_rect()
	if not visible_rect.intersects(get_viewport_rect()): return false
	var ancestor := get_parent()
	while ancestor != null:
		if ancestor is Control and (ancestor as Control).clip_contents:
			visible_rect = visible_rect.intersection((ancestor as Control).get_global_rect())
			if not visible_rect.has_area(): return false
		ancestor = ancestor.get_parent()
	return true


func _process(delta: float) -> void:
	_tick += delta
	if _tick < DRAW_INTERVAL: return
	var elapsed := minf(_tick, 0.1)
	_tick = 0.0
	var shown := _shown_in_canvas()
	if not shown:
		if is_instance_valid(_viewport): _viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
		_was_shown = false
		return
	if not _was_shown:
		_dirty = true
		_was_shown = true
	_manual_hold = maxf(0.0, _manual_hold - elapsed)
	if not _reduce_motion and not _dragging and _touch_index < 0 and _manual_hold <= 0.0:
		_time += elapsed
		_yaw = wrapf(_yaw + elapsed * 0.12, -PI, PI)
		_pivot.position.y = 0.12 + sin(_time * 0.75) * 0.025
		_dirty = true
	if _dirty:
		_pivot.rotation = Vector3(_pitch, _yaw, 0)
		_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
		_dirty = false


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var click := event as InputEventMouseButton
		# Do not consume the wheel: the surrounding page must remain scrollable.
		if click.button_index != MOUSE_BUTTON_LEFT: return
		if click.pressed:
			grab_focus()
			if click.double_click: _reset_view()
			else: _dragging = true
		else: _dragging = false
		accept_event()
	elif event is InputEventMouseMotion and _dragging:
		var motion := event as InputEventMouseMotion
		if not bool(motion.button_mask & MOUSE_BUTTON_MASK_LEFT):
			_dragging = false
			return
		_rotate_manual(motion.relative.x * 0.012, motion.relative.y * 0.006)
		accept_event()
	elif event is InputEventScreenTouch:
		var touch := event as InputEventScreenTouch
		if touch.pressed and _touch_index < 0:
			_touch_index = touch.index
			grab_focus()
		elif not touch.pressed and touch.index == _touch_index: _touch_index = -1
		accept_event()
	elif event is InputEventScreenDrag:
		var drag := event as InputEventScreenDrag
		if drag.index == _touch_index:
			_rotate_manual(drag.relative.x * 0.012, drag.relative.y * 0.006)
			accept_event()
	elif event.is_pressed() and has_focus():
		if event.is_action_pressed("ui_left"):
			_rotate_manual(-PI / 12.0, 0.0)
			accept_event()
		elif event.is_action_pressed("ui_right"):
			_rotate_manual(PI / 12.0, 0.0)
			accept_event()
		elif event.is_action_pressed("ui_accept"):
			_reset_view()
			accept_event()


func _rotate_manual(yaw_delta: float, pitch_delta: float) -> void:
	_yaw = wrapf(_yaw + yaw_delta, -PI, PI)
	_pitch = clampf(_pitch + pitch_delta, -0.28, 0.32)
	_manual_hold = 8.0
	_dirty = true


func _reset_view() -> void:
	_yaw = DEFAULT_YAW
	_pitch = 0.0
	_manual_hold = 6.0
	_dirty = true


func _draw() -> void:
	var color := Color(_accent, 0.64 if _hovered or has_focus() else 0.22)
	var left := 1.0
	var right := maxf(left, size.x - 1.0)
	var bottom := maxf(1.0, size.y - 1.0)
	for point: Vector2 in [Vector2(left, 1), Vector2(right, 1), Vector2(left, bottom), Vector2(right, bottom)]:
		var direction_x := 1.0 if point.x == left else -1.0
		var direction_y := 1.0 if point.y == 1.0 else -1.0
		draw_line(point, point + Vector2(18 * direction_x, 0), color, 1.0, true)
		draw_line(point, point + Vector2(0, 10 * direction_y), color, 1.0, true)
	if has_focus(): draw_rect(Rect2(Vector2(1, 1), size - Vector2(2, 2)), Color(_accent, 0.35), false, 1.0)


func _exit_tree() -> void:
	_dragging = false
	_touch_index = -1
	if is_instance_valid(_viewport): _viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	if is_instance_valid(_texture): _texture.texture = null
