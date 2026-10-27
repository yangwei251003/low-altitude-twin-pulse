class_name PilotInputV2
extends Node

signal pause_requested(reason: String)
signal source_changed(source: String)

var legacy: FlightInput
var source = "keyboard"
var mode = "assisted"
var epoch = 0
var active = false
var phone_frame: Dictionary = {}
var test_frame: Dictionary = {}
var test_enabled = false
var tick = 0
var edge_ids: Dictionary = {}
var last_frame: Dictionary = {}
var throttle = 0.0
var resume_throttle = 0.0
## V2 keeps its existing layout unless V3 explicitly opts in. The setting is a
## presentation/input preference; it never changes FlightBody physics.
var v3_control_scheme := "legacy"

func set_control_scheme(value: String) -> void:
	v3_control_scheme = value if value in ["heading", "map"] else "legacy"

func configure_input(saved: Dictionary) -> void:
	var config = saved.duplicate(true)
	# A different profile is a replacement, not a patch over the previous pilot.
	# Read fresh defaults without entering another input node into the scene tree:
	# the connected device and this node's signal connections remain unchanged.
	var defaults = FlightInput.new()
	legacy.config = defaults.config.duplicate(true)
	defaults.free()
	legacy.config.merge({"axis_x":2,"axis_y":3,"axis_yaw":0,"axis_vertical":1,"layout_version":2}, true)
	legacy.release_states()
	legacy.calibrating = false
	legacy.calibrate_time = 0.0
	legacy.samples = 0
	legacy.calibration_phase = ""
	legacy.layer = 0
	for action in FlightInput.KEY_BINDINGS:
		var name = "flight_" + action
		if not InputMap.has_action(name): InputMap.add_action(name)
		InputMap.action_erase_events(name)
		for code in FlightInput.KEY_BINDINGS[action]:
			var key = InputEventKey.new()
			key.physical_keycode = code
			InputMap.action_add_event(name, key)
	var mouse = InputEventMouseButton.new()
	mouse.button_index = MOUSE_BUTTON_LEFT
	InputMap.action_add_event("flight_fire", mouse)
	for pair in [["fire",JOY_BUTTON_X],["brake",JOY_BUTTON_A],["interact",JOY_BUTTON_B],["utility",JOY_BUTTON_Y],["target",JOY_BUTTON_RIGHT_SHOULDER],["low",JOY_BUTTON_DPAD_DOWN],["high",JOY_BUTTON_DPAD_UP],["pause",JOY_BUTTON_START]]:
		var button = InputEventJoypadButton.new()
		button.button_index = pair[1]
		InputMap.action_add_event("flight_" + pair[0], button)
	if int(config.get("layout_version", 1)) < 2:
		# Preserve calibration and custom buttons; upgrade the old default stick assignment.
		if int(config.get("axis_x",0)) == 0 and int(config.get("axis_y",1)) == 1:
			config["axis_x"] = 2
			config["axis_y"] = 3
		config["axis_yaw"] = 0
		config["axis_vertical"] = 1
		config["layout_version"] = 2
	legacy.apply_config(config)
	legacy.refresh_non_pointer_fire_bindings()

func reset_throttle() -> void:
	throttle = 0.0
	resume_throttle = 0.0

func can_resume() -> bool:
	if source == "phone": return true # The server validates its authenticated matching frame.
	if legacy.movement().length() > 0.05: return false
	if legacy.held("yaw_left") or legacy.held("yaw_right") or legacy.held("high") or legacy.held("low"): return false
	if legacy.device < 0: return true
	if absf(legacy.axis_value(int(legacy.config.axis_yaw))) > 0.05: return false
	var vertical = -legacy.axis_value(int(legacy.config.axis_vertical))
	if legacy.config.invert_vertical: vertical *= -1.0
	return absf((vertical+1.0)*0.5-resume_throttle) < 0.06 if mode == "manual_throttle" else absf(vertical)<0.05

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	legacy = FlightInput.new()
	add_child(legacy)
	configure_input({})
	legacy.device_lost.connect(func(): clear(); pause_requested.emit("controller_lost"))
	for pair in [["yaw_left", KEY_Z], ["yaw_right", KEY_C]]:
		var action = "v2_" + pair[0]
		if not InputMap.has_action(action): InputMap.add_action(action)
		var key = InputEventKey.new()
		key.physical_keycode = pair[1]
		InputMap.action_add_event(action, key)

func clear() -> void:
	phone_frame.clear()
	test_frame.clear()
	edge_ids.clear()
	if is_instance_valid(legacy): legacy.release_states()
	Input.action_release("v2_yaw_left")
	Input.action_release("v2_yaw_right")

func take_control(next_source: String) -> void:
	clear()
	epoch += 1
	source = next_source
	source_changed.emit(source)

func receive_phone(frame: Dictionary) -> void:
	if source != "phone": return
	phone_frame = frame.duplicate(true)

func sample() -> Dictionary:
	tick += 1
	var axes = {"left_x":0.0, "left_y":0.0, "right_x":0.0, "right_y":0.0}
	if mode=="manual_throttle": axes.left_y=throttle*2.0-1.0
	var held: Array = []
	var edges: Array = []
	if active:
		if test_enabled and OS.is_debug_build():
			axes.merge(test_frame.get("axes", {}), true)
			held = test_frame.get("held", []).duplicate()
			edges = test_frame.get("edges", []).duplicate()
			test_frame.erase("edges")
		elif source == "phone":
			if not phone_frame.get("neutral", false):
				axes.merge(phone_frame.get("axes", {}), true)
				held = phone_frame.get("held", []).duplicate()
				edges = phone_frame.get("edges", []).duplicate()
		else:
			var move = legacy.movement()
			axes.right_x = move.x
			axes.right_y = -move.y
			axes.left_y = float(legacy.held("high")) - float(legacy.held("low"))
			axes.left_x = float(legacy.held("yaw_right"))-float(legacy.held("yaw_left"))
			if v3_control_scheme == "heading" and not legacy.override_enabled and legacy.allow_input and not legacy.calibrating:
				# W/S follow the real aircraft heading. A/D turn that heading;
				# a connected controller's right stick still has lateral control.
				var key_pitch := float(legacy.held("forward")) - float(legacy.held("back"))
				var stick_pitch := -legacy.axis_value(int(legacy.config.axis_y))
				if legacy.config.invert_y: stick_pitch *= -1.0
				axes.right_y = key_pitch if absf(key_pitch) >= absf(stick_pitch) else stick_pitch
				axes.right_x = legacy.axis_value(int(legacy.config.axis_x))
				if legacy.config.invert_x: axes.right_x *= -1.0
				axes.left_x += float(legacy.held("right")) - float(legacy.held("left"))
			if legacy.device >= 0:
				var yaw = legacy.axis_value(int(legacy.config.axis_yaw))
				axes.left_x += -yaw if legacy.config.invert_yaw else yaw
				var vertical = -legacy.axis_value(int(legacy.config.axis_vertical))
				if legacy.config.invert_vertical: vertical *= -1.0
				if is_zero_approx(float(axes.left_y)): axes.left_y = vertical
			if mode == "manual_throttle" and legacy.device < 0:
				throttle = clampf(throttle + float(axes.left_y) * 0.45 / Engine.physics_ticks_per_second, 0.0, 1.0)
				axes.left_y = throttle * 2.0 - 1.0
			for key in ["fire", "brake", "interact"]:
				if legacy.held(key): held.append(key)
			for key in ["utility", "target", "map"]:
				if legacy.pressed(key): edges.append({"id":tick, "action":key, "kind":"pressed"})
	for key in axes:
		var value = axes[key]
		axes[key] = clampf(float(value), -1.0, 1.0) if (value is float or value is int) and is_finite(float(value)) else 0.0
	var accepted: Array = []
	for edge in edges:
		if not edge is Dictionary: continue
		if edge.get("action", "") not in ["utility", "target", "map", "pause", "tool", "zoom_in", "zoom_out", "recenter"]: continue
		if edge.get("kind", "") not in ["pressed", "released"]: continue
		var edge_number = edge.get("id", -1)
		if not (edge_number is int or edge_number is float) or not is_finite(float(edge_number)) or float(edge_number) < 0 or floor(float(edge_number)) != float(edge_number): continue
		var id = str(edge.get("action", "")) + ":" + str(edge.get("id", -1))
		if not edge_ids.has(id):
			edge_ids[id] = tick
			accepted.append(edge)
	if edge_ids.size() > 256:
		for key in edge_ids.keys():
			if tick - int(edge_ids[key]) > 120: edge_ids.erase(key)
	last_frame = {"schema":2, "source":"test" if test_enabled else source, "seq":tick, "control_epoch":epoch, "axes":axes, "held":held, "edges":accepted, "context":"flight", "neutral":not active}
	if active and mode == "manual_throttle": throttle = (float(axes.left_y)+1.0)*0.5
	return last_frame

func command(camera_basis: Basis) -> Dictionary:
	var frame = sample()
	var axes: Dictionary = frame.axes
	var right = camera_basis.x
	right.y = 0.0
	right = right.normalized()
	var forward = -camera_basis.z
	forward.y = 0.0
	forward = forward.normalized()
	var planar = (right * float(axes.right_x) + forward * float(axes.right_y)).limit_length(1.0)
	var actions: Array = []
	for edge in frame.edges:
		if edge.kind == "pressed": actions.append(edge.action)
	return {"tick":tick, "body_relative":v3_control_scheme != "map", "mode":mode, "planar":planar, "pitch":float(axes.right_y), "roll":float(axes.right_x), "vertical":float(axes.left_y), "throttle":throttle, "yaw":float(axes.left_x), "brake":frame.held.has("brake"), "fire":frame.held.has("fire"), "interact":frame.held.has("interact"), "edges":actions, "active":active}
