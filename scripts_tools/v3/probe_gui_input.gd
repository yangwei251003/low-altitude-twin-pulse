extends SceneTree
## Native in-game event/GUI observations only. No Session, Store or OS pointer API.
const Interface = preload("res://scripts/v3/twin_interface.gd")
const Pilot = preload("res://scripts/v2/pilot_input.gd")
var ui: TwinInterface
var pilot: PilotInputV2
var finished := false
var pointer_filter := false
var point := Vector2.ZERO
var report := {"scope":"native_headless_GUI_input_logic_only", "samples":[],
	"button_pressed":[], "action_requested":[], "coverage":[], "ui_cases":[]}
func _initialize() -> void:
	pointer_filter = "--probe-pointer-filter" in OS.get_cmdline_user_args()
	report["pointer_filter"] = pointer_filter
	_run.call_deferred()

func _run() -> void:
	report["display_server"] = DisplayServer.get_name()
	if DisplayServer.get_name() != "headless":
		_finish(2,"headless_required")
		return
	create_timer(20.0).timeout.connect(func(): _finish(2,"frame_deadline"))
	root.size = Vector2i(1280,720)
	root.content_scale_size = Vector2i(1280,720)
	pilot = Pilot.new()
	root.add_child(pilot)
	ui = Interface.new()
	root.add_child(ui)
	ui.menu.hide()
	ui.hud.show()
	pilot.active = true
	ui.action_requested.connect(func(action: String,payload: Dictionary):
		report.action_requested.append({"action":action,"payload":payload.duplicate(true)}))
	ui.show_ability_context("当前工具","原HUD建议按钮逻辑采样",["heat"])
	_watch(ui.explore_button,"explore")
	_watch(ui.suggestion_buttons[0],"suggest_heat")
	report["source_before"] = _sources()
	report["fire_bindings_before"] = []
	for binding in InputMap.action_get_events("flight_fire"):
		report.fire_bindings_before.append(binding.as_text())
	await process_frame
	await process_frame
	await _sample("neutral")
	await _ui_case("explore_mouse",ui.explore_button)
	await _ui_case("suggest_heat_mouse",ui.suggestion_buttons[0])
	_move(Vector2(960,360))
	await process_frame
	_mouse(true)
	await _sample("world_mouse_down")
	_mouse(false)
	await _sample("world_mouse_up")
	await _ui_case("UI_with_J",ui.explore_button,"J")
	await _ui_case("UI_with_synthetic_joyX",ui.explore_button,"joyX")
	await _pointer_drags(ui.explore_button)
	await _source_switch()
	_move(Vector2(960,360))
	_key(KEY_J,true,true)
	await _sample("logical_J_special_scan_down")
	_key(KEY_J,false,true)
	await _sample("logical_J_special_scan_up")
	await _ui_case("UI_with_special_scan_J",ui.explore_button,"specialJ")
	_move(ui.explore_button.get_global_rect().get_center())
	await process_frame
	_mouse(true)
	_extra("joyX",true)
	_key(KEY_J,true,true)
	await _sample("UI_virtual_J_plus_joyX")
	_key(KEY_J,false,true)
	await _sample("UI_virtual_J_released_joyX_held")
	_extra("joyX",false)
	await _sample("UI_virtual_J_and_joyX_released")
	_mouse(false)
	await _sample("UI_combined_sources_released")
	_move(Vector2(960,360))
	await process_frame
	_mouse(true)
	_key(KEY_J,true,true)
	await _sample("world_mouse_plus_virtual_J")
	_key(KEY_J,false,true)
	await _sample("world_mouse_virtual_J_released")
	_mouse(false)
	await _sample("world_mouse_and_virtual_J_released")
	pilot.legacy.rebind("fire",{"type":"key","code":KEY_K})
	report["fire_bindings_after_rebind"] = []
	for binding in InputMap.action_get_events("flight_fire"):
		report.fire_bindings_after_rebind.append(binding.as_text())
	_key(KEY_J,true)
	await _sample("rebound_old_J_down")
	_key(KEY_J,false)
	_key(KEY_K,true)
	await _sample("rebound_K_down")
	_key(KEY_K,false)
	await _sample("rebound_K_up")
	await _ui_case("UI_with_rebound_K",ui.explore_button,"K")
	pilot.configure_input({})
	_snapshot_bindings("after_configure_default")
	_key(KEY_K,true)
	await _sample("configure_default_K_down")
	_key(KEY_K,false)
	_key(KEY_J,true)
	await _sample("configure_default_J_down")
	_key(KEY_J,false)
	await _sample("configure_default_J_up")
	pilot.legacy.rebind("fire",{"type":"joy","code":JOY_BUTTON_Y})
	_snapshot_bindings("after_rebind_joyY")
	_extra("joyX",true)
	await _sample("rebound_old_joyX_down")
	_extra("joyX",false)
	_extra("joyY",true)
	await _sample("rebound_joyY_down")
	_extra("joyY",false)
	await _sample("rebound_joyY_up")
	await _ui_case("UI_with_rebound_joyY",ui.explore_button,"joyY")
	report.coverage.append("joyX is a synthetic native event; no physical controller acceptance")
	report.coverage.append("No Session firing, hit, save, graphics, OS pointer or focus acceptance")
	_finish(0,"observations_collected")

func _watch(button: Button,id: String) -> void:
	button.pressed.connect(func(): report.button_pressed.append({"button":id,
		"physics_frame":Engine.get_physics_frames(),"process_frame":Engine.get_process_frames()}))

func _ui_case(label: String,button: Button,extra := "") -> void:
	var rect: Rect2 = button.get_global_rect()
	if not button.is_visible_in_tree() or button.disabled or rect.size.x<=0 or rect.size.y<=0 or not root.get_visible_rect().has_point(rect.get_center()):
		report.coverage.append({"case":label,"not_covered":"original button unavailable"})
		return
	var pressed_before: int = report.button_pressed.size()
	var actions_before: int = report.action_requested.size()
	_move(rect.get_center())
	await process_frame
	_mouse(true)
	await _sample(label+":mouse_down")
	if not extra.is_empty():
		_extra(extra,true)
		await _sample(label+":mouse_plus_"+extra)
	_mouse(false)
	await _sample(label+":mouse_up_extra_held" if not extra.is_empty() else label+":mouse_up")
	if not extra.is_empty():
		_extra(extra,false)
		await _sample(label+":all_released")
	report.ui_cases.append({"case":label,"button":str(button.get_path()),
		"rect_position":[rect.position.x,rect.position.y],"rect_size":[rect.size.x,rect.size.y],
		"actual_pressed_delta":report.button_pressed.size()-pressed_before,
		"actual_action_requested_delta":report.action_requested.size()-actions_before})
	if report.button_pressed.size()<=pressed_before or report.action_requested.size()<=actions_before:
		report.coverage.append({"case":label,"not_covered":"native GUI callbacks not observed"})

func _sample(label: String) -> void:
	await physics_frame
	if pointer_filter: pilot.legacy.pointer_fire_blocked = ui.blocks_pointer_fire()
	var physics_command: Dictionary = pilot.command(Basis.IDENTITY)
	var physics_tick := Engine.get_physics_frames()
	var physics_controller: bool = ui.controller_navigation
	var physics_blocked: Variant = pilot.legacy.pointer_fire_blocked if pointer_filter else null
	await process_frame
	if pointer_filter: pilot.legacy.pointer_fire_blocked = ui.blocks_pointer_fire()
	var process_command: Dictionary = pilot.command(Basis.IDENTITY)
	var hovered: Control = root.gui_get_hovered_control()
	report.samples.append({"label":label,"physics_frame":physics_tick,
		"process_frame":Engine.get_process_frames(),"physics_fire":physics_command.get("fire"),
		"process_fire":process_command.get("fire"),"mouse_left":Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT),
		"physics_pointer_blocked":physics_blocked,
		"process_pointer_blocked":pilot.legacy.pointer_fire_blocked if pointer_filter else null,
		"physics_controller_navigation":physics_controller,"process_controller_navigation":ui.controller_navigation,
		"hovered_control":str(hovered.get_path()) if is_instance_valid(hovered) else "",
		"pressed_count":report.button_pressed.size(),"action_count":report.action_requested.size()})

func _move(next: Vector2) -> void:
	var event := InputEventMouseMotion.new()
	event.position = next
	event.global_position = next
	event.relative = next-point
	event.button_mask = MOUSE_BUTTON_MASK_LEFT if Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) else 0
	point = next
	Input.parse_input_event(event)

func _mouse(down: bool) -> void:
	var event := InputEventMouseButton.new()
	event.position = point
	event.global_position = point
	event.button_index = MOUSE_BUTTON_LEFT
	event.button_mask = MOUSE_BUTTON_MASK_LEFT if down else 0
	event.pressed = down
	Input.parse_input_event(event)

func _key(code: Key,down: bool,special_scan := false) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.physical_keycode = KEY_F1 if special_scan else code
	event.pressed = down
	Input.parse_input_event(event)

func _extra(kind: String,down: bool) -> void:
	if kind in ["joyX","joyY"]:
		var event := InputEventJoypadButton.new()
		event.device = 0
		event.button_index = JOY_BUTTON_X if kind == "joyX" else JOY_BUTTON_Y
		event.pressed = down
		Input.parse_input_event(event)
	elif kind == "specialJ":
		_key(KEY_J,down,true)
	else:
		_key(KEY_J if kind == "J" else KEY_K,down)

func _pointer_drags(button: Button) -> void:
	var rect := button.get_global_rect()
	if not button.is_visible_in_tree() or button.disabled or not root.get_visible_rect().has_point(rect.get_center()):
		report.coverage.append({"case":"pointer_drags","not_covered":"original button unavailable"})
		return
	_move(rect.get_center())
	await process_frame
	_mouse(true)
	await _sample("UI_origin_before_drag")
	_move(Vector2(960,360))
	await _sample("UI_origin_dragged_to_world")
	_mouse(false)
	await _sample("UI_origin_drag_release")
	_move(Vector2(960,360))
	await process_frame
	_mouse(true)
	await _sample("world_origin_before_drag")
	_move(button.get_global_rect().get_center())
	await _sample("world_origin_dragged_to_UI")
	_mouse(false)
	await _sample("world_origin_drag_release")

func _source_switch() -> void:
	_extra("joyX",true)
	await _sample("source_Joy_before_Key")
	_key(KEY_J,true)
	await _sample("source_Joy_to_Key")
	_key(KEY_J,false)
	_extra("joyX",false)
	_extra("joyX",true)
	await _sample("source_Joy_before_Mouse")
	_move(Vector2(960,360))
	await process_frame
	_mouse(true)
	await _sample("source_Joy_to_Mouse")
	_mouse(false)
	_extra("joyX",false)
	await _sample("source_switch_released")

func _snapshot_bindings(label: String) -> void:
	var snapshot := {}
	for action in ["flight_fire","flight_fire_non_pointer"]:
		snapshot[action] = []
		if InputMap.has_action(action):
			for event in InputMap.action_get_events(action): snapshot[action].append(event.as_text())
	report[label] = snapshot

func _sources() -> Dictionary:
	var hashes := {}
	for path in ["res://scripts/v3/twin_interface.gd","res://scripts/v2/pilot_input.gd","res://scripts/input_router.gd"]:
		hashes[path] = FileAccess.get_sha256(path)
	return hashes

func _finish(code: int,reason: String) -> void:
	if finished: return
	finished = true
	_mouse(false)
	_key(KEY_J,false)
	_key(KEY_K,false)
	_extra("joyX",false)
	_extra("joyY",false)
	_key(KEY_J,false,true)
	if is_instance_valid(pilot): pilot.active = false
	report["finish_reason"] = reason
	report["source_after"] = _sources()
	print("GUI_INPUT_PROBE_OBSERVATIONS "+JSON.stringify(report))
	quit(code)
