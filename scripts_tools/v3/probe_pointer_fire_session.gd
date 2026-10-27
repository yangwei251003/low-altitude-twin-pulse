extends SceneTree
## Observe ordinary MAIN input through native in-game events, never OS input.
const MAIN = preload("res://scenes/v3/main.tscn")
var session: Node
var point := Vector2.ZERO
var profile := ""
var menu_entry := "direct"
var onboarding := false
var finishing := false
var input_samples: Array = []
var ui_actions: Array = []
var report := {"scope":"headless ordinary solo MAIN input routing; no desktop input, graphics, physical controller or LAN acceptance", "samples":[], "checks":[]}

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--qa-profile="): profile = arg.trim_prefix("--qa-profile=")
		if arg.begins_with("--native-menu="): menu_entry = arg.trim_prefix("--native-menu=")
		if arg == "--onboarding": onboarding = true
	if DisplayServer.get_name() != "headless" or not profile.begins_with("qa_pointer_session_") or profile != profile.validate_filename() or DirAccess.dir_exists_absolute("user://profiles_v3/"+profile):
		quit(2)
		return
	report["version"] = ProjectSettings.get_setting("application/config/version")
	report["profile"] = profile
	report["menu_entry"] = menu_entry
	create_timer(40.0).timeout.connect(func():
		if not finishing:
			_check(false,"internal deadline")
			_finish())
	root.size = Vector2i(1280,720)
	root.content_scale_size = Vector2i(1280,720)
	session = MAIN.instantiate()
	root.add_child(session)
	_check(session.profile_ready,"fresh original Store is ready")
	if not session.profile_ready: _finish(); return
	session.network.input_received.connect(func(peer: int,command: Dictionary):
		if input_samples.size() < 512: input_samples.append({"peer":peer,"fire":bool(command.get("fire",false)),"active":bool(command.get("active",false)),"brake":bool(command.get("brake",false)),"vertical":command.get("vertical",0.0),"planar":str(command.get("planar",Vector3.ZERO)),"frame":Engine.get_physics_frames()}))
	session.interface.action_requested.connect(func(action: String,_payload: Dictionary): ui_actions.append(action))
	if menu_entry in ["mouse","keyboard"]:
		if not await _enter_menu(): _finish(); return
	elif menu_entry == "direct":
		_check(session.start_flight("solo"),"ordinary solo entry succeeds")
	else:
		_check(false,"unknown menu entry mode")
		_finish()
		return
	ui_actions.clear()
	await _frames(6)
	if finishing: return
	_check(session.active and session.players.has(1) and not session.inputs.test_enabled,"real aircraft and normal input source are active")
	if onboarding:
		await _onboarding()
		_finish()
		return
	var button: Button = session.interface.details_button
	var details_before: bool = session.interface.details_open
	report["button"] = {"path":str(button.get_path()),"visible":button.is_visible_in_tree(),"disabled":button.disabled,"rect":str(button.get_global_rect()),"viewport":str(root.get_visible_rect())}
	_check(button.is_visible_in_tree() and not button.disabled and root.get_visible_rect().has_point(button.get_global_rect().get_center()),"actual HUD button is visible, enabled and inside viewport")
	if not button.is_visible_in_tree() or button.disabled or not root.get_visible_rect().has_point(button.get_global_rect().get_center()): _finish(); return
	var pressed := [0]
	button.pressed.connect(func(): pressed[0] += 1)
	_move(button.get_global_rect().get_center())
	await process_frame
	_mouse(true)
	await _sample("HUD_mouse_hold")
	_check(session.shot_notices.is_empty(),"HUD-only press has not entered weapon rejection feedback")
	_key(KEY_J,true)
	await _sample("HUD_plus_J")
	_key(KEY_J,false)
	await _sample("HUD_J_released_mouse_held")
	_mouse(false)
	await _sample("HUD_all_released")
	_check(pressed[0] == 1 and session.interface.details_open != details_before and ui_actions.is_empty(),"native HUD click toggles original hints once without gameplay action")
	_move(Vector2(900,340))
	await process_frame
	_mouse(true)
	await _sample("world_mouse_hold")
	_mouse(false)
	await _sample("world_mouse_release")
	_check(session.shot_notices.has(1) and session.shot_notices[1].code == "target_missing","world click still reaches original weapon validation")
	var expected := {"HUD_mouse_hold":false,"HUD_plus_J":true,"HUD_J_released_mouse_held":false,"HUD_all_released":false,"world_mouse_hold":true,"world_mouse_release":false}
	for row: Dictionary in report.samples:
		_check(not row.commands.is_empty() and row.commands.all(func(command: Dictionary): return command.active and command.fire == expected[row.label]),"actual Session/Network command: "+str(row.label))
	_finish()

func _enter_menu() -> bool:
	await process_frame
	await process_frame
	var matches: Array = session.interface.menu.find_children("*","Button",true,false).filter(func(button: Button): return button.text == "单人出航 / 继续")
	_check(matches.size() == 1,"original solo button is unambiguous")
	if matches.size() != 1: return false
	var button: Button = matches[0]
	var rect: Rect2 = button.get_global_rect()
	var visible: bool = button.is_visible_in_tree() and not button.disabled and root.get_visible_rect().has_point(rect.get_center())
	_check(visible and not session.active,"initial menu is visible before any flight entry")
	if not visible or session.active: return false
	var pressed := [0]
	button.pressed.connect(func(): pressed[0] += 1)
	var focused_controls: Array = []
	if menu_entry == "mouse":
		_move(rect.get_center())
		await process_frame
		_mouse(true)
		await process_frame
		_mouse(false)
	else:
		for unused in 24:
			if button.has_focus(): break
			var focused: Control = root.gui_get_focus_owner()
			focused_controls.append(str(focused.get_class()) if is_instance_valid(focused) else "none")
			_key(KEY_TAB,true)
			await process_frame
			_key(KEY_TAB,false)
			await process_frame
		_check(button.has_focus(),"native Tab navigation reaches original solo button")
		if not button.has_focus(): return false
		_key(KEY_ENTER,true)
		await process_frame
		_key(KEY_ENTER,false)
	await _frames(6)
	var ok: bool = pressed[0] == 1 and ui_actions == ["solo"] and session.active and session.players.has(1) and not session.interface.menu.visible
	report["menu_observation"] = {"mode":menu_entry,"actual_pressed":pressed[0],"actual_actions":ui_actions.duplicate(),"active":session.active,"menu_visible":session.interface.menu.visible,"frame_id":session.frame_id,"region":session.region_id,"focus_steps":focused_controls,"objective_text":session.interface.objective.text,"completed":session.story.state.get("completed",[]).duplicate()}
	_check(ok,"native menu button enters original solo MAIN exactly once")
	return ok

func _onboarding() -> void:
	var body: FlightBodyV2 = session.players[1]
	var at_start: Vector3 = body.global_position
	await _frames(12)
	var nearest: String = session.story.nearest(body.global_position)
	_key(KEY_G,true)
	await process_frame
	_key(KEY_G,false)
	await _frames(12)
	_check("I1:rescue:brief" in session.story.state.get("completed",[]),"native G at original spawn accepts first Linlan rescue briefing")
	report["onboarding_contact"] = {"spawn":str(at_start),"nearest":nearest,"actions":ui_actions.duplicate(),"radio_visible":session.interface.radio.visible,"objective":session.interface.objective.text,"completed":session.story.state.get("completed",[]).duplicate()}
	for unused in 8:
		if not session.interface.radio.visible: break
		_key(KEY_G,true)
		await process_frame
		_key(KEY_G,false)
		await process_frame
	_check(not session.interface.radio.visible,"native G advances and closes the actual dialogue")
	var height_before := body.global_position.y
	var start_telemetry: Dictionary = body.telemetry.duplicate(true)
	_key(KEY_SPACE,true)
	_key(KEY_E,true)
	await _frames(30)
	_key(KEY_E,false)
	await _frames(30)
	var height_after := body.global_position.y
	_check(height_after > height_before+0.1,"native E takes off before planar flight")
	_key(KEY_SPACE,false)
	var move_start: Vector3 = body.global_position
	_key(KEY_W,true)
	await _frames(60)
	var move_end: Vector3 = body.global_position
	var speed_before_brake := Vector2(body.linear_velocity.x,body.linear_velocity.z).length()
	_key(KEY_W,false)
	_key(KEY_SPACE,true)
	var brake_curve: Array = []
	for unused in 10:
		await _frames(12)
		brake_curve.append({"frame":Engine.get_physics_frames(),"speed":Vector2(body.linear_velocity.x,body.linear_velocity.z).length(),"position":str(body.global_position),"brake":body.telemetry.get("brake_active"),"grounded":body.grounded})
	var speed_after_brake := Vector2(body.linear_velocity.x,body.linear_velocity.z).length()
	_check(move_start.distance_to(move_end)>0.1 and speed_before_brake>0.1,"native W produces physical flight without test input or pose fixtures")
	_check(speed_after_brake < speed_before_brake*0.6+0.05,"native Space physically slows the aircraft")
	_key(KEY_SPACE,false)
	await _frames(12)
	_check(body.enabled and not session.inputs.test_enabled and session.inputs.source != "phone","ordinary aircraft and normal input source remain active")
	report["onboarding_flight"] = {"move_start":str(move_start),"move_end":str(move_end),"speed_before_brake":speed_before_brake,"speed_after_brake":speed_after_brake,"height_before":height_before,"height_after":height_after,"start_telemetry":start_telemetry,"brake_curve":brake_curve,"end_position":str(body.global_position),"health":body.health,"normal_commands":input_samples.duplicate(true)}

func _frames(count: int) -> void:
	for unused in count: await physics_frame
	await process_frame

func _sample(label: String) -> void:
	var before := input_samples.size()
	await _frames(6)
	var hovered: Control = root.gui_get_hovered_control()
	report.samples.append({"label":label,"commands":input_samples.slice(before),"body_fire":bool(session.players[1].command.get("fire",false)),"mouse_left":Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT),"hovered":str(hovered.get_path()) if is_instance_valid(hovered) else "","ui_actions":ui_actions.duplicate(),"weapon_notices":session.shot_notices.duplicate(true)})

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

func _key(code: Key,down: bool) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.pressed = down
	Input.parse_input_event(event)

func _check(ok: bool,label: String) -> void:
	report.checks.append({"passed":ok,"label":label})

func _finish() -> void:
	if finishing: return
	finishing = true
	_mouse(false)
	_key(KEY_J,false)
	for code: Key in [KEY_W,KEY_G,KEY_SPACE,KEY_E]: _key(code,false)
	report["failures"] = report.checks.filter(func(row: Dictionary): return not row.passed)
	if is_instance_valid(session):
		report["store_before_normal_quit"] = {"generation":session.store.snapshot().generation,"profile_id":session.store.snapshot().profile_id,"completed":session.story.state.get("completed",[]).duplicate()}
	print("POINTER_FIRE_SESSION_RESULT "+JSON.stringify(report))
	if is_instance_valid(session): session._quit()
	else: quit(2)
