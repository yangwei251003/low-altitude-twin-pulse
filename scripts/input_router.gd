class_name FlightInput
extends Node

const NON_POINTER_FIRE: StringName = &"flight_fire_non_pointer"
const KEY_BINDINGS = {
	"left":[KEY_A,KEY_LEFT],"right":[KEY_D,KEY_RIGHT],"forward":[KEY_W,KEY_UP],"back":[KEY_S,KEY_DOWN],
	"brake":[KEY_SPACE],"low":[KEY_Q],"high":[KEY_E],"fire":[KEY_J],"interact":[KEY_F],
	"utility":[KEY_SHIFT],"target":[KEY_TAB],"pause":[KEY_ESCAPE],"restart":[KEY_R],"map":[KEY_M],"capture":[KEY_F12],"yaw_left":[KEY_Z],"yaw_right":[KEY_C]
}
var config = {"axis_x":0,"axis_y":1,"axis_height":-1,"axis_yaw":2,"axis_vertical":3,"layout_version":1,"invert_x":false,"invert_y":false,"invert_yaw":false,"invert_vertical":false,"deadzone":0.16,"center":{},"min":{},"max":{},"bindings":{},"device_bindings":{"key":{},"joy":{}}}
var device = -1
var override_enabled = false
var override_move = Vector2.ZERO
var override_buttons: Dictionary = {}
var allow_input = true
var pointer_fire_blocked := false
var _virtual_fire_held := false
var layer = 0
var calibrating = false
var calibrate_time = 0.0
var samples = 0
var calibration_phase = ""
signal device_lost
signal calibration_done

func _input(event: InputEvent) -> void:
	if "--input-trace" in OS.get_cmdline_user_args() and event is InputEventKey:
		print("KEY_TRACE pressed=",event.pressed," physical=",event.physical_keycode," keycode=",event.keycode," unicode=",event.unicode," allow=",allow_input," pause_match=",event.is_action_pressed("flight_pause")," high_match=",event.is_action_pressed("flight_high"))
	# Some Windows virtual/remote keyboards expose a correct logical key but
	# an unrelated special scan code. Bridge only that case, leaving physical
	# letter layouts (including AZERTY) and normal hardware input unchanged.
	if event is InputEventKey and not event.echo and event.keycode!=0 and event.physical_keycode>=KEY_SPECIAL and event.physical_keycode!=event.keycode:
		for action in KEY_BINDINGS:
			var action_name="flight_"+action
			for binding in InputMap.action_get_events(action_name):
				if binding is InputEventKey and binding.physical_keycode==event.keycode:
					# A virtual key release must not release another held fire source.
					if action == "fire": _virtual_fire_held = event.pressed
					elif event.pressed: Input.action_press(action_name)
					else: Input.action_release(action_name)
					break

func _ready() -> void:
	for action in KEY_BINDINGS:
		var name = "flight_" + action
		if not InputMap.has_action(name):
			InputMap.add_action(name)
		for key in KEY_BINDINGS[action]:
			var event = InputEventKey.new()
			event.physical_keycode = key
			InputMap.action_add_event(name, event)
	var mouse = InputEventMouseButton.new()
	mouse.button_index = MOUSE_BUTTON_LEFT
	InputMap.action_add_event("flight_fire", mouse)
	for pair in [["fire",JOY_BUTTON_X],["brake",JOY_BUTTON_A],["interact",JOY_BUTTON_B],["utility",JOY_BUTTON_Y],["target",JOY_BUTTON_RIGHT_SHOULDER],["low",JOY_BUTTON_DPAD_DOWN],["high",JOY_BUTTON_DPAD_UP],["pause",JOY_BUTTON_START]]:
		var event = InputEventJoypadButton.new()
		event.button_index = pair[1]
		InputMap.action_add_event("flight_" + pair[0], event)
	Input.joy_connection_changed.connect(_connection)
	var devices = Input.get_connected_joypads()
	if devices.size() > 0:
		device = devices[0]
	refresh_non_pointer_fire_bindings()

## Keep native key/joy aggregation while excluding a UI-owned mouse press.
func refresh_non_pointer_fire_bindings() -> void:
	if not InputMap.has_action(NON_POINTER_FIRE): InputMap.add_action(NON_POINTER_FIRE)
	_virtual_fire_held = false
	Input.action_release(NON_POINTER_FIRE)
	InputMap.action_erase_events(NON_POINTER_FIRE)
	InputMap.action_set_deadzone(NON_POINTER_FIRE, InputMap.action_get_deadzone("flight_fire"))
	for binding in InputMap.action_get_events("flight_fire"):
		if not binding is InputEventMouse: InputMap.action_add_event(NON_POINTER_FIRE, binding)

func apply_config(saved: Dictionary) -> void:
	for key in config:
		var value=saved.get(key)
		if key in ["bindings", "device_bindings", "center", "min", "max"]:continue
		if typeof(value)==typeof(config[key]) or (_finite_number(value) and (config[key] is float or config[key] is int)):
			if not (value is float or value is int) or _finite_number(value):config[key]=value
	for axis in ["axis_x","axis_y","axis_height","axis_yaw","axis_vertical"]:config[axis]=clampi(int(config[axis]),-1,7)
	config.deadzone=clampf(float(config.deadzone),.05,.4)
	for kind in ["center", "min", "max"]:
		config[kind] = {}
		var raw = saved.get(kind, {})
		if raw is Dictionary:
			for axis in range(8):
				var axis_key = str(axis)
				if _finite_number(raw.get(axis_key)):config[kind][axis_key] = clampf(float(raw[axis_key]), -1.0, 1.0)
	for axis in range(8):
		var axis_key = str(axis)
		var center = float(config.center.get(axis_key, 0.0))
		if float(config.min.get(axis_key, -1.0)) >= center:config.min.erase(axis_key)
		if float(config.max.get(axis_key, 1.0)) <= center:config.max.erase(axis_key)
	var legacy = saved.get("bindings", {})
	if legacy is Dictionary:
		for action in legacy:
			if action is String and legacy[action] is Dictionary:rebind(action, legacy[action])
	var layers = saved.get("device_bindings", {})
	if layers is Dictionary:
		for kind in ["key", "joy"]:
			var bindings = layers.get(kind, {})
			if bindings is Dictionary:
				for action in bindings:
					if action is String and _finite_number(bindings[action]):rebind(action, {"type":kind, "code":bindings[action]})

func _finite_number(value) -> bool:
	return (value is float or value is int) and is_finite(float(value))

func rebind(action: String, bind: Dictionary) -> void:
	var name = "flight_" + action
	if not InputMap.has_action(name):
		return
	if bind.get("type","") not in ["key","joy"] or not _finite_number(bind.get("code")):return
	var code = int(bind.code)
	if code < 0 or (bind.type == "joy" and code >= JOY_BUTTON_MAX) or (bind.type == "key" and code == 0):return
	for binding in InputMap.action_get_events(name):
		if (bind.type == "key" and binding is InputEventKey) or (bind.type == "joy" and binding is InputEventJoypadButton):
			InputMap.action_erase_event(name, binding)
	var event
	if bind.type == "key":
		event = InputEventKey.new()
		event.physical_keycode = int(bind.code)
	else:
		event = InputEventJoypadButton.new()
		event.button_index = int(bind.code)
	InputMap.action_add_event(name, event)
	config.bindings[action] = {"type":bind.type, "code":code}
	config.device_bindings[bind.type][action] = code
	if action == "fire": refresh_non_pointer_fire_bindings()

func binding_label(action: String) -> String:
	for event in InputMap.action_get_events("flight_"+action):
		if event is InputEventKey:return OS.get_keycode_string(event.physical_keycode)
		if event is InputEventJoypadButton:return "手柄 %d"%event.button_index
	return "未映射"

func release_states() -> void:
	for action in KEY_BINDINGS:Input.action_release("flight_"+action)
	Input.action_release(NON_POINTER_FIRE)
	override_move=Vector2.ZERO
	override_buttons.clear()
	_virtual_fire_held = false

func _connection(id: int, connected: bool) -> void:
	if connected and device == -1:
		device = id
	elif not connected and id == device:
		device = -1
		calibrating=false
		calibration_phase="设备已断开，校准已停止。"
		release_states()
		device_lost.emit()

func axis_value(axis: int) -> float:
	if device < 0 or axis < 0:
		return 0.0
	var raw = Input.get_joy_axis(device, axis)
	var key = str(axis)
	var center = float(config.center.get(key, 0.0))
	var extent = float(config.max.get(key, 1.0)) - center if raw >= center else center - float(config.min.get(key, -1.0))
	var value = clampf((raw - center) / maxf(extent, 0.1), -1.0, 1.0)
	var deadzone = float(config.deadzone)
	return 0.0 if absf(value) < deadzone else signf(value) * (absf(value) - deadzone) / (1.0-deadzone)

func movement() -> Vector2:
	if override_enabled:
		return override_move.limit_length(1.0)
	if not allow_input or calibrating:
		return Vector2.ZERO
	var keys = Input.get_vector("flight_left","flight_right","flight_forward","flight_back")
	var stick = Vector2(axis_value(int(config.axis_x)), axis_value(int(config.axis_y)))
	if config.invert_x: stick.x *= -1
	if config.invert_y: stick.y *= -1
	return (keys if keys.length() > stick.length() else stick).limit_length(1.0)

func held(action: String) -> bool:
	if override_enabled:
		return override_buttons.get(action, false)
	if action == "fire":
		return allow_input and not calibrating and (_virtual_fire_held or Input.is_action_pressed(NON_POINTER_FIRE) or (not pointer_fire_blocked and Input.is_action_pressed("flight_fire")))
	return allow_input and not calibrating and Input.is_action_pressed("flight_" + action)

func pressed(action: String) -> bool:
	if override_enabled:
		return override_buttons.get(action + "_pressed", false)
	return allow_input and not calibrating and Input.is_action_just_pressed("flight_" + action)

func _process(delta: float) -> void:
	if calibrating:
		calibrate_time += delta
		if calibrate_time < 2.5:
			calibration_phase = "保持摇杆中立，采集中立点…"
			for axis in range(8):
				var key = str(axis)
				var raw = Input.get_joy_axis(device, axis)
				config.center[key] = float(config.center.get(key,0.0)) + raw
			samples += 1
		elif calibration_phase.begins_with("保持"):
			for key in config.center:
				config.center[key] /= maxi(samples, 1)
			calibration_phase = "缓慢推动各摇杆至两端，采集行程…"
		elif calibrate_time < 11.0:
			for axis in range(8):
				var raw = Input.get_joy_axis(device, axis)
				var key = str(axis)
				config.min[key] = minf(float(config.min.get(key,1.0)), raw)
				config.max[key] = maxf(float(config.max.get(key,-1.0)), raw)
		else:
			calibrating = false
			calibration_phase = "校准完成。非回中油门请映射为航层轴；确认低/高端后使用。"
			calibration_done.emit()
	if pressed("low"): layer = 0
	if pressed("high"): layer = 1
	if device >= 0 and int(config.axis_height) >= 0 and allow_input and not calibrating:
		var raw = Input.get_joy_axis(device, int(config.axis_height))
		if raw < -0.35: layer = 0
		elif raw > 0.35: layer = 1

func begin_calibration() -> void:
	if device < 0: return
	calibrating = true
	calibrate_time = 0
	samples = 0
	config.center = {}
	config.min = {}
	config.max = {}
	calibration_phase = "保持摇杆中立"

