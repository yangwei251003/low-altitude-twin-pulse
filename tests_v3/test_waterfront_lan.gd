extends SceneTree
## SOURCE-ONLY QA wrapper around two unmodified real MAIN scenes and real ENet.
## Fixtures: isolated profiles; saved predecessor actions permitting I2 travel;
## one host-side, collision-checked deep-water starting pose; scripted PilotInput.
## Native Session/process/physics stay enabled. No timer/health/received-packet
## injection, persistent freezing, interpolation driver, or fake network authority.
## Natural facility-wait frames are observed only; absence means NOT_COVERED.
const MAIN = preload("res://scenes/v3/main.tscn")
const Director = preload("res://scripts/v3/gameplay/actions/twin_action_director.gd")
const Regions = preload("res://scripts/v3/world/twin_region_catalog.gd")
const DEEP_START := Vector3(14.75, -2.2, 20.0)

var session: TwinSession
var role := ""
var run_id := ""
var profile := ""
var evidence := ""
var ack := 0
var command_result: Dictionary = {}
var errors: Array = []
var started_msec := 0
var shutting_down := false
var input_mode := "assisted"
var connected_bodies: Dictionary = {}
var old_world_id := 0
var old_roster: Dictionary = {}
var old_targets_max := 0
var old_world_exit: Dictionary = {}
var arrival: Dictionary = {}
var region_sequence_baseline := -1
var region_motion_accepted := false
var wait_frames := 0
var wait_after_accept_frames := 0
var wait_samples: Array = []
var wait_violations: Array = []
var last_wait_positions: Dictionary = {}
var subject := 0
var armed := false
var placed := false
var placement: Dictionary = {}
var expected_damage: Dictionary = {}
var initial_health := 0.0
var initial_flight_seconds := 0.0
var water_events: Array = []
var damage_receipts: Array = []
var local_damage_events: Array = []
var rescue_events: Array = []
var input_rpc_count := 0
var zero_input_rpc_count := 0
var last_input_rpc: Dictionary = {}
var wet_integrated_steps := 0
var last_observed_flight := -1.0
var wet_maximum_thrust := 0.0
var actual_water_samples := 0
var rescue_minimum_distance := 1000000.0
var recovery_observation := false
var recovery_samples: Array = []
var engine_errors: Array = []

class CaptureLogger extends Logger:
	var captured: Array = []
	func _log_error(function: String, file: String, line: int, code: String, rationale: String, _notify: bool, error_type: int, _backtraces: Array[ScriptBacktrace]) -> void:
		captured.append({"function":function, "file":file, "line":line, "code":code, "rationale":rationale, "type":error_type})

var logger := CaptureLogger.new()

func _init() -> void:
	OS.add_logger(logger)
	_boot.call_deferred()

func _boot() -> void:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--waterfront-role="): role = argument.trim_prefix("--waterfront-role=")
		elif argument.begins_with("--waterfront-run="): run_id = argument.trim_prefix("--waterfront-run=")
		elif argument.begins_with("--waterfront-evidence="): evidence = argument.trim_prefix("--waterfront-evidence=")
		elif argument.begins_with("--qa-profile="): profile = argument.trim_prefix("--qa-profile=")
		else:
			push_error("WATERFRONT_LAN unknown argument: " + argument)
			quit(2)
			return
	if role not in ["host", "guest"] or run_id.is_empty() or not profile.begins_with("qa_waterfront_lan_") or evidence.is_empty() or not DirAccess.dir_exists_absolute(evidence) or not OS.is_debug_build():
		push_error("WATERFRONT_LAN requires controller, isolated profile and source debug engine")
		quit(2)
		return
	var controller: Dictionary = _read_json(evidence.path_join("controller.json"))
	if controller.get("run_id") != run_id or controller.get("exclusive_port") != 26742 or controller.get("profiles", {}).get(role) != profile:
		push_error("WATERFRONT_LAN controller handshake mismatch")
		quit(2)
		return
	started_msec = Time.get_ticks_msec()
	session = MAIN.instantiate()
	root.add_child(session)
	current_scene = session
	if not session.profile_ready or session.store.root_path != "user://profiles_v3/" + profile or not session.qa_mode.is_empty():
		_fail("MAIN/profile failed or automatic QA flight would override inputs")
		_finish(2)
		return
	if role == "host" and not _seed_predecessors():
		_fail("saved predecessor fixture failed validation/publication")
		_finish(2)
		return
	if not session.start_flight(role, "127.0.0.1"):
		_fail("real MAIN start_flight failed")
		_finish(2)
		return
	session.inputs.test_enabled = true
	session.network.input_received.connect(_on_input_rpc)
	physics_frame.connect(_observe_physics)
	var timer := Timer.new()
	timer.wait_time = 0.05
	timer.timeout.connect(_poll)
	root.add_child(timer)
	timer.start()
	_poll()

func _seed_predecessors() -> bool:
	# Same explicit saved-action fixture as the existing distribution LAN test,
	# but KEEP I1 until the connected guest votes for a real region transition.
	var legacy = Director.new()
	if not legacy.load_definitions(Director.DEFAULT_PATH, ["res://data/v3/actions/whale_action.json", "res://data/v3/actions/crown_action.json", "res://data/v3/actions/underdeck_action.json"]).ok: return false
	var state: Dictionary = legacy.default_state()
	for action in legacy.definitions().actions:
		for objective in action.objectives:
			var matcher: Dictionary = objective.events[0]
			var event := {"id":"qa-waterfront-predecessor:" + str(objective.id), "type":matcher.type, "target_id":matcher.target_id, "option":matcher.options[0]}
			var next: Dictionary = legacy.apply_event(state, event, {"is_authority":true, "validated":true, "region_id":action.region_id})
			if not next.get("changed", false): return false
			state = next.state
	if state.completed.size() != 27 or not session.story.director.validate_state(state).ok: return false
	return bool(session.store.commit({"id":"qa-waterfront-predecessors", "set":{"world.region_id":"I1", "world.actions.opening":state, "world.flags":state.flags, "world.completed_objectives":state.completed}, "append":{"personal.discoveries":state.discoveries}}).ok)

func _observe_physics() -> void:
	if shutting_down or not is_instance_valid(session) or not session.active: return
	# Feed the normal input sampler; do not overwrite body.command or network packets.
	session.inputs.mode = input_mode
	if input_mode == "manual_throttle": session.inputs.throttle = 0.0
	session.inputs.test_frame = {"axes":{"left_x":0.0, "left_y":-1.0 if input_mode == "manual_throttle" else 0.0, "right_x":0.0, "right_y":0.0}, "held":[], "edges":[]}
	for peer in session.players:
		var body: FlightBodyV2 = session.players[peer]
		var instance: int = body.get_instance_id()
		if not connected_bodies.has(instance):
			connected_bodies[instance] = true
			body.water_entered.connect(_on_water_entered.bind(int(peer)))
			body.damage_resolved.connect(_on_damage_receipt.bind(int(peer)))
			body.damaged.connect(_on_local_damage.bind(int(peer)))
			body.rescued.connect(_on_rescued.bind(int(peer)))
	if session.region_id == "I1" and is_instance_valid(session.world):
		old_targets_max = maxi(old_targets_max, session.remote_targets.size())
		old_roster = _roster()
		if old_world_id == 0:
			old_world_id = session.world.get_instance_id()
			session.world.tree_exiting.connect(_old_world_leaving)
	if session.region_id == "I2" and arrival.is_empty() and not session.players.is_empty():
		arrival = {"physics_frame":Engine.get_physics_frames(), "roster":_roster(), "facilities_ready":session._facilities_ready(), "remote_targets":session.remote_targets.size(), "sequence":session.received_sequence}
	if role == "guest" and session.region_id == "I2" and not old_world_exit.is_empty() and session.received_sequence > region_sequence_baseline:
		# consume_all accepted an I2 motion snapshot. Later serial waits may retain
		# those valid I2 targets; they must freeze motion, not erase that cache.
		region_motion_accepted = true
	if role == "guest" and session.region_id == "I2" and not session._facilities_ready():
		wait_frames += 1
		if region_motion_accepted: wait_after_accept_frames += 1
		if wait_samples.size() < 120:
			wait_samples.append({"frame":Engine.get_physics_frames(), "sequence":session.received_sequence, "baseline":region_sequence_baseline, "new_region_motion_accepted":region_motion_accepted, "targets":session.remote_targets.size()})
		for peer in session.players:
			var body: FlightBodyV2 = session.players[peer]
			if not body.freeze: wait_violations.append({"peer":peer, "error":"not frozen while facilities unavailable"})
			if last_wait_positions.has(peer) and body.global_position.distance_to(last_wait_positions[peer]) > 0.0001:
				wait_violations.append({"peer":peer, "error":"position changed between unavailable-facility frames"})
			last_wait_positions[peer] = body.global_position
		if not region_motion_accepted and not session.remote_targets.is_empty(): wait_violations.append({"error":"motion targets present before first accepted I2 motion"})
	else:
		last_wait_positions.clear()
	if armed and session.players.has(subject):
		var body: FlightBodyV2 = session.players[subject]
		var sample: Dictionary = body.environment_sample
		if float(body.flight_seconds) > last_observed_flight:
			last_observed_flight = float(body.flight_seconds)
			if body.water_contact:
				wet_integrated_steps += 1
				wet_maximum_thrust = maxf(wet_maximum_thrust, float(body.thrust_fraction))
			if bool(sample.get("water", false)) and absf(float(sample.get("water_height", 999.0)) + 1.2) < 0.001: actual_water_samples += 1
			if recovery_observation and not body.freeze and recovery_samples.size() < 180:
				recovery_samples.append({"flight_seconds":body.flight_seconds, "position":body.global_position, "velocity":body.linear_velocity, "angular_velocity":body.angular_velocity, "hold_height":body.hold_height, "water_seconds":body.water_seconds, "water_contact":body.water_contact, "health":body.health, "mode":body.command.get("mode", ""), "active":body.command.get("active", false)})
		if not rescue_events.is_empty(): rescue_minimum_distance = minf(rescue_minimum_distance, body.global_position.distance_to(body.safe_position + Vector3.UP * 1.5))

func _old_world_leaving() -> void:
	if session.region_id == "I2" and old_world_exit.is_empty():
		# Production clears targets before removing the old world; observe that
		# synchronous signal without overriding Session or injecting a packet.
		region_sequence_baseline = session.received_sequence
		old_world_exit = {"region":session.region_id, "remote_targets":session.remote_targets.size(), "old_targets_observed":old_targets_max, "physics_frame":Engine.get_physics_frames(), "sequence_baseline":region_sequence_baseline}

func _poll() -> void:
	if shutting_down: return
	if Time.get_ticks_msec() - started_msec > 82000:
		_fail("82 second peer deadline")
		_finish(2)
		return
	var controller: Dictionary = _read_json(evidence.path_join("controller.json"))
	if not controller.is_empty() and (controller.get("run_id") != run_id or Time.get_unix_time_from_system() - float(controller.get("heartbeat_unix", 0.0)) > 15.0):
		_fail("controller heartbeat/identity invalid")
		_finish(2)
		return
	var command: Dictionary = _read_json(evidence.path_join(role + "-command.json"))
	if command.get("run_id") == run_id and int(command.get("sequence", 0)) > ack:
		ack = int(command.sequence)
		command_result = _execute(str(command.get("verb", "")))
		if not command_result.get("ok", false): _fail("command failed: " + JSON.stringify(command_result))
		if command.get("verb") == "shutdown":
			_finish(0 if errors.is_empty() and logger.captured.is_empty() else 1)
			return
	_write_state()

func _execute(verb: String) -> Dictionary:
	if verb == "shutdown": return {"ok":true}
	if verb == "travel":
		if role != "host" or session.region_id != "I1" or session.players.size() != 2: return {"ok":false, "code":"travel_precondition"}
		session._ui_action("travel_to", {"region_id":"I2"})
		return {"ok":true, "dispatch_only":true}
	if verb == "confirm":
		var proposal: Dictionary = session.consensus.current_proposal() if role == "host" else session.choice_proposal
		if proposal.is_empty(): return {"ok":false, "code":"no_actual_proposal"}
		session.network.send_action("confirm", {"proposal_id":proposal.proposal_id, "world_revision":proposal.world_revision})
		return {"ok":true, "dispatch_only":true}
	if verb == "arm":
		if session.region_id != "I2" or not session._facilities_ready(): return {"ok":false, "code":"I2_not_ready"}
		subject = int(session.network.guests.keys()[0]) if role == "host" and session.network.guests.size() == 1 else int(session.network.local_id())
		if not session.players.has(subject): return {"ok":false, "code":"subject_missing"}
		armed = true
		var body: FlightBodyV2 = session.players[subject]
		initial_health = float(body.health)
		initial_flight_seconds = float(body.flight_seconds)
		last_observed_flight = initial_flight_seconds
		return {"ok":true, "subject":subject}
	if verb in ["zero_throttle", "assisted"]:
		if role != "guest" or not armed: return {"ok":false, "code":"guest_not_armed"}
		input_mode = "manual_throttle" if verb == "zero_throttle" else "assisted"
		return {"ok":true, "input_fixture":input_mode}
	if verb == "observe_recovery":
		if not armed or not session.players.has(subject): return {"ok":false, "code":"subject_not_armed"}
		var body: FlightBodyV2 = session.players[subject]
		if body.command.get("mode") != "assisted" or not body.command.get("active", false) or body.global_position.y <= 1.0:
			return {"ok":false, "code":"actual_assisted_recovery_not_started"}
		recovery_observation = true
		recovery_samples.clear()
		return {"ok":true, "fixture":"read-only real integration samples after normal assisted input"}
	if verb == "place_deep":
		if role != "host" or not armed or placed or zero_input_rpc_count < 3: return {"ok":false, "code":"single_pose_requires_real_zero_input_RPC"}
		var body: FlightBodyV2 = session.players[subject]
		var shape: CollisionShape3D = body.get_node("Envelope")
		var query := PhysicsShapeQueryParameters3D.new()
		query.shape = shape.shape
		query.transform = Transform3D(Basis.IDENTITY, DEEP_START) * shape.transform
		query.exclude = [body.get_rid()]
		query.collision_mask = 1 | 2 | 4 | 8 | 32
		query.margin = 0.0
		if not session.get_world_3d().direct_space_state.intersect_shape(query, 1).is_empty(): return {"ok":false, "code":"deep_start_occupied"}
		expected_damage = body.preview_combat_hit(12.0, Vector3.ZERO, body.global_position, "collision")
		initial_health = float(body.health)
		placement = {"point":DEEP_START, "safe_before":body.safe_position, "flight_seconds":body.flight_seconds, "collision_count":body.collision_count, "expected_damage":expected_damage.duplicate(true), "fixture":"one actual host pose; no timer, health or rescue-result injection"}
		body.global_transform = Transform3D(Basis.IDENTITY, DEEP_START)
		body.linear_velocity = Vector3.ZERO
		body.angular_velocity = Vector3.ZERO
		body.force_update_transform()
		PhysicsServer3D.body_set_state(body.get_rid(), PhysicsServer3D.BODY_STATE_TRANSFORM, body.global_transform)
		placed = true
		return {"ok":true, "placement":placement}
	return {"ok":false, "code":"unknown_command"}

func _on_input_rpc(peer: int, command: Dictionary) -> void:
	if role != "host" or not armed or peer != subject: return
	input_rpc_count += 1
	last_input_rpc = command.duplicate(true)
	if command.get("active", false) and command.get("mode") == "manual_throttle" and absf(float(command.get("throttle", 1.0))) < 0.000001: zero_input_rpc_count += 1

func _on_water_entered(peer: int) -> void:
	if armed and peer == subject: water_events.append({"flight_seconds":session.players[peer].flight_seconds, "position":session.players[peer].global_position})

func _on_damage_receipt(receipt: Dictionary, peer: int) -> void:
	if armed and peer == subject: damage_receipts.append(receipt.duplicate(true))

func _on_local_damage(amount: float, direction: Vector3, peer: int) -> void:
	if armed and peer == subject: local_damage_events.append({"amount":amount, "direction":direction, "flight_seconds":session.players[peer].flight_seconds})

func _on_rescued(peer: int) -> void:
	if armed and peer == subject:
		rescue_events.append({"flight_seconds":session.players[peer].flight_seconds, "health":session.players[peer].health, "safe":session.players[peer].safe_position, "receipt":damage_receipts[-1].duplicate(true) if not damage_receipts.is_empty() else {}})

func _roster() -> Dictionary:
	var result: Dictionary = {}
	for peer in session.players:
		var body: FlightBodyV2 = session.players[peer]
		result[str(peer)] = {"instance_id":body.get_instance_id(), "position":body.global_position, "velocity":body.linear_velocity, "safe":body.safe_position, "health":body.health, "hold_height":body.hold_height, "water_seconds":body.water_seconds, "water_contact":body.water_contact, "flight_seconds":body.flight_seconds, "freeze":body.freeze, "authority":body.environment_hazards_authoritative, "sample":body.environment_sample, "thrust":body.thrust_fraction, "collisions":body.collision_count}
		result[str(peer)]["command_mode"] = str(body.command.get("mode", ""))
		result[str(peer)]["command_active"] = bool(body.command.get("active", false))
	return result

func _write_state() -> void:
	if not is_instance_valid(session): return
	var ready: bool = session.active and is_instance_valid(session.world) and session.players.has(session.network.local_id()) and session._facilities_ready()
	var report: Dictionary = {"run_id":run_id, "role":role, "profile":profile, "main_scene":"res://scenes/v3/main.tscn", "main_node":str(session.get_path()), "network_node":str(session.network.get_path()), "ready":ready, "region":session.region_id, "local_id":session.network.local_id(), "roster":_roster(), "sequence":session.received_sequence, "remote_targets":session.remote_targets.size(), "old_targets_max":old_targets_max, "old_roster":old_roster, "old_world_exit":old_world_exit, "arrival":arrival, "proposal":session.consensus.current_proposal() if role == "host" else session.choice_proposal, "facilities_ready":session._facilities_ready(), "wait_coverage":"OBSERVED" if wait_frames > 0 else "NOT_COVERED", "wait_frames":wait_frames, "wait_violations":wait_violations, "armed":armed, "subject":subject, "placed":placed, "placement":placement, "initial_health":initial_health, "initial_flight_seconds":initial_flight_seconds, "water_events":water_events, "damage_receipts":damage_receipts, "local_damage_events":local_damage_events, "rescue_events":rescue_events, "rescue_minimum_distance":rescue_minimum_distance, "input_rpc_count":input_rpc_count, "zero_input_rpc_count":zero_input_rpc_count, "last_input_rpc":last_input_rpc, "wet_integrated_steps":wet_integrated_steps, "wet_maximum_thrust":wet_maximum_thrust, "actual_water_samples":actual_water_samples, "input_mode":input_mode, "ack":ack, "result":command_result, "errors":errors, "engine_errors":logger.captured, "elapsed_ms":Time.get_ticks_msec() - started_msec, "source_only":true, "same_computer_ENet":true, "native_process_and_physics":true, "timer_or_health_injected":false}
	report.merge({"region_sequence_baseline":region_sequence_baseline, "region_motion_accepted":region_motion_accepted, "wait_after_accept_frames":wait_after_accept_frames, "wait_samples":wait_samples, "recovery_samples":recovery_samples})
	var output := FileAccess.open(evidence.path_join(role + "-state.json"), FileAccess.WRITE)
	if output: output.store_string(JSON.stringify(_json_value(report)))
	else: _fail("state publication failed")

func _json_value(value: Variant) -> Variant:
	if value is Vector3: return [value.x, value.y, value.z]
	if value is Dictionary:
		var result: Dictionary = {}
		for key in value: result[str(key)] = _json_value(value[key])
		return result
	if value is Array:
		var result: Array = []
		for item in value: result.append(_json_value(item))
		return result
	return value

func _read_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path): return {}
	var parser := JSON.new()
	if parser.parse(FileAccess.get_file_as_string(path)) != OK or not parser.data is Dictionary: return {}
	return parser.data

func _fail(message: String) -> void:
	errors.append(message)
	print("WATERFRONT_LAN_FAIL " + message)

func _finish(code: int) -> void:
	shutting_down = true
	_write_state()
	if is_instance_valid(session) and is_instance_valid(session.network): session.network.close()
	OS.remove_logger(logger)
	quit(code)
