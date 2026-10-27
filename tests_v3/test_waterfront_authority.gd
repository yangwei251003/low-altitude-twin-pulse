extends SceneTree
## Real FlightBody force integration, not a MAIN/transport or network simulation.
## Only phase-start poses/velocities and a homogeneous water column are fixtures.
## No test code assigns water_seconds, invokes _integrate_forces, or moves a live body.
const FlightBody = preload("res://scripts/v2/flight_body.gd")
const Catalog = preload("res://scripts/v2/catalog.gd")
const IDS := ["authority", "prediction"]
const WATER_HEIGHT := -1.2
const INITIAL_Y := -5.0
const DRAG_SAMPLE_SECONDS := 0.4
const WET_SECONDS := 3.2
const INITIAL_VELOCITY := Vector3(2.0, 0.0, 0.0)

var viewport: SubViewport
var world: Node3D
var bodies: Dictionary = {}
var events: Dictionary = {}
var phase_starts: Dictionary = {}
var measurements: Dictionary = {}
var phase := "setup"
var checks := 0
var failures: Array = []
var finished := false

class TestLogger extends Logger:
	var errors: Array = []
	func _log_error(function: String, file: String, line: int, code: String, rationale: String, _notify: bool, error_type: int, _backtraces: Array[ScriptBacktrace]) -> void:
		errors.append({"function":function, "file":file, "line":line, "code":code, "rationale":rationale, "type":error_type})

var logger := TestLogger.new()

func _init() -> void:
	OS.add_logger(logger)
	_run.call_deferred()

func _run() -> void:
	create_timer(20.0).timeout.connect(func():
		if not finished:
			print("V3_WATERFRONT_AUTHORITY_TIMEOUT " + JSON.stringify({"phase":phase, "checks":checks, "failures":failures, "engine_errors":logger.errors, "measurements":measurements}))
			quit(2))
	viewport = SubViewport.new()
	viewport.size = Vector2i(32, 32)
	viewport.own_world_3d = true
	viewport.world_3d = World3D.new()
	viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	root.add_child(viewport)
	world = Node3D.new()
	world.name = "IsolatedWaterAuthorityFixture"
	viewport.add_child(world)
	for id: String in IDS:
		var body := FlightBody.new()
		body.name = id
		body.configure(Catalog.resolve_build(Catalog.default_build("tr01")))
		_check(body.environment_hazards_authoritative, "new FlightBody defaults to authoritative for V2", {"body":id})
		# Leave the authority body's actual default untouched.
		if id == "prediction": body.environment_hazards_authoritative = false
		body.freeze = true
		body.position = _start_position(id)
		body.command = {"active":true, "mode":"manual_throttle", "throttle":0.0, "roll":0.0, "pitch":0.0, "yaw":0.0, "vertical":0.0, "brake":false, "body_relative":true}
		world.add_child(body)
		# Disable only visual callbacks; keep the physics tree and force integrator live.
		body.set_process(false)
		bodies[id] = body
		events[id] = {"entered":0, "rescued":0, "damage":[], "rescue_elapsed_s":[], "entry_elapsed_s":[]}
		body.water_entered.connect(_on_water_entered.bind(id))
		body.rescued.connect(_on_rescued.bind(id))
		body.damaged.connect(_on_damaged.bind(id))
	await _settle()
	# own_world_3d uses a unique copy of world_3d, not that source resource's space.
	# https://docs.godotengine.org/en/stable/classes/class_viewport.html#class-viewport-property-own-world-3d
	var effective_world: World3D = viewport.find_world_3d()
	var root_world: World3D = root.find_world_3d()
	var root_space: RID = root_world.space if root_world != null else RID()
	for id: String in IDS:
		var body: FlightBody = bodies[id]
		var body_world: World3D = body.get_world_3d()
		var body_space: RID = PhysicsServer3D.body_get_space(body.get_rid())
		var spaces: Dictionary = {"body":id, "server_space":str(body_space), "body_world_space":str(body_world.space), "effective_viewport_space":str(effective_world.space), "source_viewport_space":str(viewport.world_3d.space), "root_space":str(root_space)}
		measurements[id + "_spaces"] = spaces
		_check(body_space.is_valid() and body_world == effective_world and body_space == body_world.space and body_space != root_space, "real body belongs to isolated live physics space", spaces)
		_check(body.get_node("Envelope").shape is BoxShape3D and body.enabled and not body.practice and body.sandbox_rules.is_empty(), "production collider and ordinary damage rules active", {"body":id})
	# Negative control: same real bodies, zero throttle and initial velocity, no water.
	await _prepare_phase(false)
	phase = "dry_control"
	_begin_phase()
	var dry: Dictionary = await _observe(DRAG_SAMPLE_SECONDS)
	_freeze_bodies()
	measurements["dry_control"] = dry
	for id: String in IDS:
		var body: FlightBody = bodies[id]
		_check(events[id].entered == 0 and events[id].rescued == 0 and events[id].damage.is_empty() and is_equal_approx(body.health, body.maximum_health), "dry control causes no water event or damage", {"body":id})
	# This second placement is declared setup, while frozen; never a live rescue.
	await _prepare_phase(true)
	var initial_health: Dictionary = {}
	var initial_damage: Dictionary = {}
	for id: String in IDS:
		initial_health[id] = float(bodies[id].health)
		initial_damage[id] = bodies[id].damage_state.duplicate(true)
	phase = "continuous_deep_water"
	_begin_phase()
	var wet: Dictionary = await _observe(WET_SECONDS)
	_freeze_bodies()
	measurements["wet"] = wet
	measurements["events"] = events.duplicate(true)
	measurements["fixture"] = {"initial_y_m":INITIAL_Y, "water_height_m":WATER_HEIGHT, "initial_velocity_mps":_array(INITIAL_VELOCITY), "manual_throttle":0.0, "physics_ticks_per_second":Engine.physics_ticks_per_second, "water_timer_written_by_test":false, "phase_start_placements":2}
	for id: String in IDS:
		var body: FlightBody = bodies[id]
		var dry_row: Dictionary = dry[id]
		var wet_row: Dictionary = wet[id]
		_check(float(wet_row.elapsed_s) >= WET_SECONDS and float(wet_row.elapsed_s) > 2.5, "actual force integration exceeded rescue delay", {"body":id, "elapsed_s":wet_row.elapsed_s})
		_check(events[id].entered == 1, "one real water-entry event from sustained immersion", {"body":id, "events":events[id]})
		_check(bool(wet_row.all_pre_rescue_samples_submerged) and float(wet_row.maximum_thrust_fraction) == 0.0 and body.collision_count == 0, "zero lift and no collision confound sustained water exposure", {"body":id, "samples":wet_row})
		_check(int(wet_row.maximum_consecutive_wet_steps) >= 150 and int(wet_row.wet_step_gaps) == 0, "at least 150 distinct consecutive real wet physics steps observed", {"body":id, "wet_steps":wet_row.wet_steps, "maximum_consecutive_wet_steps":wet_row.maximum_consecutive_wet_steps, "wet_step_gaps":wet_row.wet_step_gaps, "zero_elapsed_observations":wet_row.zero_elapsed_observations, "rescue_wet_steps":wet_row.rescue_wet_steps})
		_check(float(dry_row.drag_sample_speed_mps) > 1.0 and float(wet_row.drag_sample_speed_mps) < float(dry_row.drag_sample_speed_mps) * 0.6, "water produces stronger actual horizontal resistance than dry control", {"body":id, "dry_mps":dry_row.drag_sample_speed_mps, "wet_mps":wet_row.drag_sample_speed_mps, "dry_sample_s":dry_row.drag_sample_elapsed_s, "wet_sample_s":wet_row.drag_sample_elapsed_s})
		_check(float(dry_row.drag_sample_y) < INITIAL_Y - 0.05 and float(wet_row.drag_sample_y) > float(dry_row.drag_sample_y) + 0.15, "water force changes real vertical motion with identical zero-throttle input", {"body":id, "dry_y":dry_row.drag_sample_y, "wet_y":wet_row.drag_sample_y})
	var authority: FlightBody = bodies.authority
	var prediction: FlightBody = bodies.prediction
	_check(events.authority.rescued == 1 and events.authority.damage.size() == 1 and is_equal_approx(float(initial_health.authority) - authority.health, 12.0), "default-authoritative body commits exactly one rescue and 12 health loss", {"events":events.authority, "health_before":initial_health.authority, "health_after":authority.health})
	if events.authority.rescue_elapsed_s.size() == 1:
		_check(float(events.authority.rescue_elapsed_s[0]) > 2.5 and float(events.authority.rescue_elapsed_s[0]) < 2.75, "rescue follows real accumulated immersion, not injected timer", {"elapsed_s":events.authority.rescue_elapsed_s[0]})
	_check(float(wet.authority.minimum_rescue_distance_m) < 0.15, "physics transform actually reaches declared safe position plus rescue offset", {"minimum_distance_m":wet.authority.minimum_rescue_distance_m, "safe_position":_array(authority.safe_position)})
	_check(events.prediction.rescued == 0 and events.prediction.damage.is_empty() and is_equal_approx(prediction.health, float(initial_health.prediction)) and prediction.damage_state == initial_damage.prediction, "prediction applies no rescue, health loss or damage-state mutation", {"events":events.prediction, "health_before":initial_health.prediction, "health_after":prediction.health})
	_check(prediction.water_contact and prediction.water_seconds >= 2.49 and prediction.water_seconds <= 2.5 and prediction.global_position.y < WATER_HEIGHT, "prediction stays immersed after delay with bounded timer", {"water_seconds":prediction.water_seconds, "position":_array(prediction.global_position)})
	_check(authority.environment_hazards_authoritative and not prediction.environment_hazards_authoritative, "authority flags unchanged throughout real integration")
	await _finish()

func _prepare_phase(water: bool) -> void:
	_freeze_bodies()
	await _settle()
	for id: String in IDS:
		var body: FlightBody = bodies[id]
		body.global_transform = Transform3D(Basis.IDENTITY, _start_position(id))
		body.force_update_transform()
		PhysicsServer3D.body_set_state(body.get_rid(), PhysicsServer3D.BODY_STATE_TRANSFORM, body.global_transform)
		body.linear_velocity = Vector3.ZERO
		body.angular_velocity = Vector3.ZERO
		body.safe_position = Vector3(_start_position(id).x, 3.0, 0.0)
		body.environment_sample = {"water":water, "water_height":WATER_HEIGHT, "wind_velocity":Vector3.ZERO, "density":1.225}
		body.environment_acceleration = Vector3.ZERO
	await _settle()

func _begin_phase() -> void:
	for id: String in IDS:
		var body: FlightBody = bodies[id]
		phase_starts[id] = float(body.flight_seconds)
		body.freeze = false
		body.sleeping = false
		body.linear_velocity = INITIAL_VELOCITY
		body.angular_velocity = Vector3.ZERO

func _observe(duration: float) -> Dictionary:
	var result: Dictionary = {}
	for id: String in IDS:
		result[id] = {"elapsed_s":0.0, "drag_sample_speed_mps":-1.0, "drag_sample_elapsed_s":0.0, "drag_sample_y":INITIAL_Y, "maximum_thrust_fraction":0.0, "all_pre_rescue_samples_submerged":true, "minimum_rescue_distance_m":1000000.0, "samples":0, "last_integrated_elapsed_s":0.0, "integrated_samples":0, "zero_elapsed_observations":0, "duplicate_elapsed_observations":0, "wet_steps":0, "consecutive_wet_steps":0, "maximum_consecutive_wet_steps":0, "wet_step_gaps":0, "rescue_wet_steps":0}
	var expected_step := 1.0 / float(Engine.physics_ticks_per_second)
	var max_frames := int(ceil((duration + 1.0) * Engine.physics_ticks_per_second))
	for unused in range(max_frames):
		await physics_frame
		await process_frame
		var done := true
		for id: String in IDS:
			var body: FlightBody = bodies[id]
			var row: Dictionary = result[id]
			var elapsed := float(body.flight_seconds) - float(phase_starts[id])
			row.elapsed_s = elapsed
			row.samples += 1
			done = done and elapsed >= duration
			# A process-frame read can precede the first integration after unfreezing.
			# It is setup, not a dry physics step. Repeated reads cannot inflate counts.
			if elapsed <= 0.0:
				row.zero_elapsed_observations += 1
				continue
			if elapsed <= float(row.last_integrated_elapsed_s):
				row.duplicate_elapsed_observations += 1
				continue
			var contiguous := absf(elapsed - float(row.last_integrated_elapsed_s) - expected_step) < 0.00001
			row.last_integrated_elapsed_s = elapsed
			row.integrated_samples += 1
			row.maximum_thrust_fraction = maxf(float(row.maximum_thrust_fraction), float(body.thrust_fraction))
			if elapsed >= DRAG_SAMPLE_SECONDS and float(row.drag_sample_speed_mps) < 0.0:
				row.drag_sample_speed_mps = Vector2(body.linear_velocity.x, body.linear_velocity.z).length()
				row.drag_sample_elapsed_s = elapsed
				row.drag_sample_y = body.global_position.y
			if phase == "continuous_deep_water":
				# The rescue step itself touched water before the production integrator
				# moved the body. Count its real event/contact once, not its new dry pose.
				var rescue_step: bool = events[id].rescue_elapsed_s.size() == 1 and absf(float(events[id].rescue_elapsed_s[0]) - elapsed) < 0.000001
				var wet_step: bool = body.water_contact and (body.global_position.y < WATER_HEIGHT or rescue_step)
				if wet_step:
					row.wet_steps += 1
					if not contiguous: row.wet_step_gaps += 1
					row.consecutive_wet_steps = int(row.consecutive_wet_steps) + 1 if contiguous else 1
					row.maximum_consecutive_wet_steps = maxi(int(row.maximum_consecutive_wet_steps), int(row.consecutive_wet_steps))
					if rescue_step: row.rescue_wet_steps += 1
				else:
					row.consecutive_wet_steps = 0
				if events[id].rescued == 0:
					row.all_pre_rescue_samples_submerged = bool(row.all_pre_rescue_samples_submerged) and wet_step
				else:
					row.minimum_rescue_distance_m = minf(float(row.minimum_rescue_distance_m), body.global_position.distance_to(body.safe_position + Vector3.UP * 1.5))
			row.final_position = _array(body.global_position)
			row.final_velocity = _array(body.linear_velocity)
		if done: break
	return result

func _on_water_entered(id: String) -> void:
	events[id].entered += 1
	events[id].entry_elapsed_s.append(float(bodies[id].flight_seconds) - float(phase_starts.get(id, 0.0)))

func _on_rescued(id: String) -> void:
	events[id].rescued += 1
	events[id].rescue_elapsed_s.append(float(bodies[id].flight_seconds) - float(phase_starts.get(id, 0.0)))

func _on_damaged(amount: float, _direction: Vector3, id: String) -> void:
	events[id].damage.append({"amount":amount, "phase":phase, "elapsed_s":float(bodies[id].flight_seconds) - float(phase_starts.get(id, 0.0))})

func _freeze_bodies() -> void:
	for body: FlightBody in bodies.values(): body.freeze = true

func _settle() -> void:
	await physics_frame
	await physics_frame
	await process_frame

func _start_position(id: String) -> Vector3:
	return Vector3(-4.0 if id == "authority" else 4.0, INITIAL_Y, 0.0)

func _array(value: Vector3) -> Array:
	return [value.x, value.y, value.z]

func _check(ok: bool, label: String, details: Dictionary = {}) -> void:
	checks += 1
	if not ok:
		failures.append({"check":label, "details":details})
		print("WATERFRONT_AUTHORITY_FAIL " + label + " " + JSON.stringify(details))

func _finish() -> void:
	phase = "cleanup"
	if is_instance_valid(viewport): viewport.queue_free()
	await process_frame
	await process_frame
	finished = true
	print("V3_WATERFRONT_AUTHORITY_TESTS " + JSON.stringify({"checks":checks, "failures":failures, "engine_errors":logger.errors, "measurements":measurements, "scope":"isolated real FlightBody force integration and authority guard; explicit phase-start placement/water/input fixtures; no MAIN wiring, transport, terrain sampler, graphics, performance or human-flight verification"}))
	OS.remove_logger(logger)
	quit(0 if failures.is_empty() and logger.errors.is_empty() else 1)
