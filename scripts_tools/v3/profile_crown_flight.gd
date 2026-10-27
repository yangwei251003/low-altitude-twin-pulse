extends "res://scripts_tools/v3/profile_assets.gd"
## Real-time, normal rigid-body flight under scripted stick input in the F1 Boss scene.
## Reuses only the historical profiler's reporting/argument helpers, not its route.
const ROUTE = [Vector3(-14,17,-14), Vector3(-14,23,-30), Vector3(-14,26,-40), Vector3(27,26,-43), Vector3(39,23,-32), Vector3(39,18,-15), Vector3(20,20,-11), Vector3(3,17,-16)]
var duration_seconds := 300.0
var route_index := 0
var reached := 0
var flight_distance := 0.0
var previous_position := Vector3.ZERO
var coverage := CrownCoverage.new()
var fingerprint_errors: Array[String] = []
var import_manifest: Dictionary = {}
var measurement_active := false
var last_guard_state: Dictionary = {}
var expected_guard_state: Dictionary = {}
var previous_reset_serial := 0
var initial_flight_seconds := 0.0
var initial_collision_count := 0
var route_wait := 0.0
var timed_out_waypoints: Array = []

func _run() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--perf-seconds="): duration_seconds = float(argument.trim_prefix("--perf-seconds="))
	if duration_seconds not in [30.0, 300.0, 1800.0] or not _arguments_valid() or not OS.is_debug_build():
		push_error("Use 30s smoke, 300s study or 1800s endurance in a debug build with an isolated QA profile")
		quit(2)
		return
	seed(SEED)
	if DirAccess.make_dir_recursive_absolute(output) != OK:
		push_error("Cannot create performance evidence directory")
		quit(2)
		return
	source_hashes = _hash_inputs()
	if not fingerprint_errors.is_empty():
		_fail("Cannot fingerprint runtime imports: " + str(fingerprint_errors))
		return
	metadata = _environment()
	metadata.profile = profile
	metadata.harness = "physical_flight_f1_phase_one_crown"
	metadata.duration_seconds = duration_seconds
	metadata.smoke_only = duration_seconds < 300
	metadata.global_seed_applied_before_scene_load = SEED
	metadata.coverage_policy = CrownCoverage.policy(duration_seconds)
	if not _write_json("prepared.json", {"status":"starting_not_a_result", "environment":metadata, "source_sha256":source_hashes, "imports":import_manifest, "route":_route_json()}):
		push_error("Prepared evidence could not be written; measurement not started")
		quit(2)
		return
	session = load("res://scenes/v3/main.tscn").instantiate()
	root.add_child(session)
	current_scene = session
	if not session.start_flight("solo"):
		_fail("Cannot start isolated production solo session")
		return
	session._load_region("F1")
	if not session.crown.ready():
		_fail("Production Crown and all terrain must import")
		return
	# One disclosed setup placement before warmup, then normal forces/collision forever.
	_place(Vector3(3, 17, -16))
	await physics_frame
	await physics_frame
	var body = session.players[1]
	body.freeze = false
	body.set_physics_process(true)
	body.set_process(true)
	session.inputs.test_enabled = true
	session.inputs.mode = "assisted"
	session.inputs.test_frame = {"axes":{}, "held":["brake"]}
	session.flight_camera.snap(body.global_position)
	initial_camera_basis = session.camera.global_basis
	var warmup_start = Time.get_ticks_usec()
	while Time.get_ticks_usec() - warmup_start < int(WARMUP_SECONDS * 1000000):
		await process_frame
	if not session.crown.start(false):
		_fail("Actual production Crown encounter must start; no obsolete boss_start action")
		return
	metadata.warmup_actual_seconds = (Time.get_ticks_usec() - warmup_start) / 1000000.0
	metadata.memory_after_warmup = _memory()
	metadata.camera_size = session.camera.size
	metadata.camera_basis = str(initial_camera_basis)
	metadata.crown_rng_at_start = session.crown.encounter.get_state().rng
	metadata.crown_rng_origin = "Production start uses its own default seed; global seed does not override encounter or persisted ecology RNG."
	previous_position = body.global_position
	last_phase = "F1_crown_flight"
	await process_frame
	start_usec = Time.get_ticks_usec()
	previous_usec = start_usec
	initial_flight_seconds = body.flight_seconds
	initial_collision_count = body.collision_count
	previous_position = body.global_position
	previous_reset_serial = session.crown.reset_serial
	var baseline: Dictionary = session.crown.encounter.get_state()
	coverage.observe(baseline, session.crown.active(), _effective_roster(baseline), 0.0, 0.0, previous_reset_serial)
	expected_guard_state = _read_guard_state()
	measurement_active = true
	root.focus_exited.connect(_on_focus_exited)
	root.focus_entered.connect(_on_focus_entered)
	root.size_changed.connect(_on_window_size_changed)
	_check_guards(0.0)
	print("V3_CROWN_PERF_STARTED ", JSON.stringify({"seconds":duration_seconds, "output":output, "smoke_only":duration_seconds < 300}))
	while true:
		await process_frame
		var now = Time.get_ticks_usec()
		var elapsed = (now - start_usec) / 1000000.0
		frames.append({"start_s":(previous_usec - start_usec) / 1000000.0, "end_s":elapsed, "usec":now - previous_usec, "phase":"F1_crown_flight", "group":"F1"})
		var frame_seconds = (now - previous_usec) / 1000000.0
		previous_usec = now
		_check_guards(elapsed)
		_observe_flight_and_crown(frame_seconds, elapsed)
		if elapsed >= duration_seconds: break
		_guide(frame_seconds, elapsed)
		if elapsed >= next_sample:
			_sample(elapsed)
			var row: Dictionary = samples.back()
			row.merge({"velocity":str(body.linear_velocity), "health":body.health, "flight_seconds":body.flight_seconds, "collision_count":body.collision_count, "route_index":route_index, "waypoints_reached":reached, "crown_mode":session.crown.encounter.get_state().mode, "crown_effective_roster":coverage.last_roster, "crown_encounter_seconds":coverage.encounter_seconds, "crown_fired_attacks":coverage.fired_attacks.size()})
			next_sample = floor(elapsed) + 1
	measurement_active = false
	var measured = (previous_usec - start_usec) / 1000000.0
	var actual_flight_seconds: float = body.flight_seconds - initial_flight_seconds
	var final_memory = _memory()
	var final_stats: Dictionary = session.stats.duplicate(true)
	session.inputs.test_frame = {"axes":{}, "held":["brake"]}
	session.set_process(false)
	session.set_physics_process(false)
	session.network.close()
	var final_hashes = _hash_inputs()
	if not fingerprint_errors.is_empty(): _issue("runtime_import_fingerprint_failed:" + str(fingerprint_errors))
	if final_hashes != source_hashes: issues.append("runtime_inputs_changed_during_measurement")
	if window_changed or vsync_changed: issues.append("window_or_vsync_changed")
	if maximum_camera_angle_error > 0.001: issues.append("fixed_camera_angle_changed")
	if actual_flight_seconds < measured * 0.7: issues.append("insufficient_normal_physics_time")
	if reached < (3 if duration_seconds < 300 else ROUTE.size()): issues.append("insufficient_route_coverage")
	for issue in coverage.validity_issues(measured, duration_seconds): _issue(issue)
	if not timed_out_waypoints.is_empty(): issues.append("one_or_more_waypoints_stalled")
	if not _write_csv(): issues.append("frame_csv_write_failed")
	var report = {"status":"measured" if issues.is_empty() else "measured_with_validity_issues", "scope":"30s harness smoke only" if duration_seconds < 300 else "single-player F1 actual flight and phase-one Crown load; partial scene, not full delivery acceptance", "environment":metadata,
		"measurement":{"clock":"monotonic process_frame wall intervals", "seconds":measured, "target_seconds":duration_seconds, "frames":frames.size(), "percentile":"nearest-rank ceil(p*N)-1", "full_last_interval_retained":true},
		"overall":_statistics(frames), "route":_route_json(), "flight":{"integrated_seconds":actual_flight_seconds, "distance_metres":flight_distance, "waypoints_reached":reached, "collision_events":body.collision_count - initial_collision_count, "timed_out_waypoints":timed_out_waypoints, "final_position":str(body.global_position)},
		"crown":coverage.report(), "one_second_samples":samples, "events":events, "stats":final_stats, "memory_after_measurement":final_memory, "source_sha256":source_hashes, "source_sha256_after":final_hashes, "imports":import_manifest, "issues":issues,
		"limitations":["Scripted stick input, not human keyboard/controller comfort or enjoyment.", "Only the setup pose is directly assigned; subsequent movement uses normal PilotInput, network solo authority and FlightBody integration with wind, damage and collision.", "Phase-one Crown attacks/migration only: no weapon/ability spam, phase two, maximum chain or LAN stress claim.", "A natural defeat/reset is preserved and recorded; health, armor and energy are not artificially restored by this harness. Reset-crossing movement and encounter-clock deltas are conservatively excluded from coverage only; every wall frame remains in performance statistics.", "Fired attacks are observed production state, including hazards, not inferred warning deadlines. Counts are conservative if observation misses a short active interval; they do not prove hits or human challenge.", "Coverage thresholds establish this bounded workload only. Per-frame guards and coverage polling have overhead retained in raw timings. Focus loss invalidates the run; counters sampled once a second are not peaks.", "No final-art or full-world acceptance; source/import settings/remapped cache fingerprints included. Premeasurement hashing warms filesystem caches; this is not cold-start profiling.", "Wall frame intervals include CPU, scheduling and VSync; not direct GPU timing or presentation latency.", "Memory counters are engine/render estimates, not process working set. Background load is separately coordinated.", "No automatic P95 delivery PASS; a 30s smoke cannot replace the five-minute or thirty-minute requirements."]}
	if not _write_json("report.json", report):
		_issue("report_json_write_failed")
		push_error("Final report write failed; this run cannot exit successfully")
	print("V3_CROWN_PERF_FINISHED ", JSON.stringify({"output":output, "overall":report.overall, "waypoints":reached, "attacks":coverage.fired_attacks.size(), "issues":issues}))
	session.queue_free()
	await process_frame
	quit(0 if issues.is_empty() else 3)

func _guide(dt: float, elapsed: float) -> void:
	var body = session.players[1]
	var target: Vector3 = ROUTE[route_index]
	var error: Vector3 = target - body.global_position
	route_wait += dt
	if error.length() < 1.8:
		reached += 1
		events.append({"time_s":elapsed, "kind":"waypoint_reached", "index":route_index, "position":str(body.global_position)})
		route_index = (route_index + 1) % ROUTE.size()
		route_wait = 0
		error = ROUTE[route_index] - body.global_position
	elif route_wait > 35.0:
		timed_out_waypoints.append({"index":route_index, "time_s":elapsed, "position":str(body.global_position), "distance":error.length()})
		route_index = (route_index + 1) % ROUTE.size()
		route_wait = 0
		error = ROUTE[route_index] - body.global_position
	# Proportional desired velocity; the production body still supplies acceleration,
	# tilt, braking, drag and collision response. No direct velocity/force assignment.
	var desired = (Vector3(error.x, 0, error.z) * 1.4).limit_length(6.0)
	var planar = ((desired - Vector3(body.linear_velocity.x, 0, body.linear_velocity.z) * 0.12) / float(body.stats.speed_mps)).limit_length(0.8)
	var right = session.camera.global_basis.x
	right.y = 0
	var forward = -session.camera.global_basis.z
	forward.y = 0
	var vertical = clampf(error.y * 0.6 / float(body.stats.rise_mps), -0.75, 0.75)
	session.inputs.test_frame = {"axes":{"right_x":planar.dot(right.normalized()), "right_y":planar.dot(forward.normalized()), "left_y":vertical}, "held":[]}

func _route_json() -> Array:
	var result: Array = []
	for point in ROUTE: result.append([point.x, point.y, point.z])
	return result

func _effective_roster(state: Dictionary) -> Array[String]:
	var result: Array[String] = []
	for id in state.get("players", {}):
		var player: Dictionary = state.players[id]
		var peer := int(str(id).trim_prefix("player:"))
		if player.downed or int(player.health_milli) <= 0 or not session.players.has(peer): continue
		var body = session.players[peer]
		if body.enabled and session.crown.arena().in_combat_space(body.global_position): result.append(str(id))
	result.sort()
	return result

func _observe_flight_and_crown(dt: float, elapsed: float) -> void:
	var state: Dictionary = session.crown.encounter.get_state()
	var serial: int = session.crown.reset_serial
	coverage.observe(state, session.crown.active(), _effective_roster(state), dt, elapsed, serial)
	var body = session.players[1]
	var movement := flight_step(previous_position, body.global_position, previous_reset_serial, serial, route_wait)
	flight_distance += float(movement.distance)
	route_wait = float(movement.route_wait)
	if movement.reset:
		events.append({"time_s":elapsed, "kind":"production_encounter_reset", "from_serial":previous_reset_serial, "reset_serial":serial, "attempt":state.get("attempt", 0), "from":str(previous_position), "to":str(body.global_position), "excluded_distance":previous_position.distance_to(body.global_position)})
	elif movement.unexpected_jump:
		# A large legitimate movement during a slow frame is still measured. Size
		# alone is not proof of a teleport, nor grounds to reject a slow frame.
		events.append({"time_s":elapsed, "kind":"large_nonreset_displacement_retained", "metres":movement.distance})
	previous_position = body.global_position
	previous_reset_serial = serial

static func flight_step(before: Vector3, after: Vector3, old_serial: int, new_serial: int, wait: float) -> Dictionary:
	var reset_changed := old_serial != new_serial
	var distance := before.distance_to(after)
	return {"reset":reset_changed, "distance":0.0 if reset_changed else distance,
		"route_wait":0.0 if reset_changed else wait, "unexpected_jump":not reset_changed and distance >= 10.0}

func _issue(value: String) -> void:
	if not issues.has(value): issues.append(value)

func _write_json(filename: String, value: Dictionary) -> bool:
	return store_evidence_json(output.path_join(filename), value)

static func store_evidence_json(path: String, value: Dictionary) -> bool:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null: return false
	file.store_string(JSON.stringify(value, "\t"))
	file.flush()
	var ok := file.get_error() == OK
	file.close()
	return ok

func _read_guard_state() -> Dictionary:
	return {"focused":DisplayServer.window_is_focused(), "window_mode":DisplayServer.window_get_mode(),
		"window_size":DisplayServer.window_get_size(), "viewport_size":root.size,
		"vsync":DisplayServer.window_get_vsync_mode(), "max_fps":Engine.max_fps, "time_scale":Engine.time_scale,
		"simulation_paused":session.simulation_paused, "tree_paused":paused, "render_loop":RenderingServer.is_render_loop_enabled(),
		"camera_size":session.camera.size, "msaa":root.msaa_3d, "scaling":root.scaling_3d_scale}

static func guard_issues(current: Dictionary, expected: Dictionary) -> Array[String]:
	var result: Array[String] = []
	if not current.focused: result.append("window_focus_lost")
	if current.window_mode == DisplayServer.WINDOW_MODE_MINIMIZED: result.append("window_minimized")
	if current.window_mode != expected.window_mode: result.append("window_mode_changed")
	if current.window_size != SIZE or current.viewport_size != SIZE: result.append("window_or_viewport_changed")
	if current.vsync != expected.vsync: result.append("vsync_changed")
	if current.max_fps != 0 or not is_equal_approx(float(current.time_scale), 1.0) or current.simulation_paused or current.tree_paused: result.append("timing_or_pause_changed")
	if not current.render_loop: result.append("render_loop_disabled")
	if not is_equal_approx(float(current.camera_size), float(expected.camera_size)): result.append("camera_zoom_changed")
	if current.msaa != expected.msaa or not is_equal_approx(float(current.scaling), float(expected.scaling)): result.append("render_quality_changed")
	return result

func _check_guards(elapsed: float) -> void:
	if not measurement_active: return
	maximum_camera_angle_error = maxf(maximum_camera_angle_error, initial_camera_basis.get_rotation_quaternion().angle_to(session.camera.global_basis.get_rotation_quaternion()))
	var current := _read_guard_state()
	if current != last_guard_state:
		events.append({"time_s":elapsed, "kind":"measurement_guard_state", "state":current.duplicate(true)})
		last_guard_state = current
	for issue in guard_issues(current, expected_guard_state): _issue(issue)

func _on_focus_exited() -> void:
	if not measurement_active: return
	_issue("window_focus_lost")
	events.append({"time_s":(Time.get_ticks_usec() - start_usec) / 1000000.0, "kind":"window_focus_exited"})

func _on_focus_entered() -> void:
	if measurement_active: events.append({"time_s":(Time.get_ticks_usec() - start_usec) / 1000000.0, "kind":"window_focus_entered"})

func _on_window_size_changed() -> void:
	if measurement_active: _check_guards((Time.get_ticks_usec() - start_usec) / 1000000.0)

func _hash_inputs() -> Dictionary:
	var paths: Array[String] = ["res://project.godot", "res://scripts_tools/v3/profile_assets.gd", "res://scripts_tools/v3/profile_crown_flight.gd"]
	for directory in ["res://scripts", "res://scenes/v3", "res://assets/v3", "res://assets/fonts", "res://data/v3"]: _collect_files(directory, paths)
	var result := fingerprint_paths(paths)
	fingerprint_errors.assign(result.errors)
	import_manifest = result.imports
	return result.sha256

static func fingerprint_paths(paths: Array[String]) -> Dictionary:
	var hashes: Dictionary = {}
	var imports: Dictionary = {}
	var errors: Array[String] = []
	var pending := paths.duplicate()
	var index := 0
	while index < pending.size():
		var path: String = pending[index]
		index += 1
		if hashes.has(path): continue
		var sha := FileAccess.get_sha256(path)
		hashes[path] = sha
		if sha.is_empty(): errors.append("unreadable:" + path)
		if path.ends_with(".import"):
			var config := ConfigFile.new()
			if config.load(path) != OK:
				errors.append("invalid_import_config:" + path)
				continue
			var targets: Array[String] = []
			if config.has_section("remap"):
				for key in config.get_section_keys("remap"):
					if key == "path" or key.begins_with("path."): targets.append(str(config.get_value("remap", key)))
			for dest in config.get_value("deps", "dest_files", []):
				if not targets.has(str(dest)): targets.append(str(dest))
			targets.sort()
			imports[path] = targets
			for target in targets:
				if not target.begins_with("res://.godot/imported/"):
					errors.append("unexpected_import_target:" + target)
				pending.append(target)
		elif FileAccess.file_exists(path + ".import"):
			pending.append(path + ".import")
	return {"sha256":hashes, "imports":imports, "errors":errors}

func _collect_files(path: String, paths: Array[String]) -> void:
	if path == "res://assets/v3/candidates": return
	for file in DirAccess.get_files_at(path):
		if file.get_extension() in ["gd", "tscn", "tres", "glb", "gdshader", "gdshaderinc", "png", "jpg", "webp", "json", "ttf", "otf", "import"]: paths.append(path.path_join(file))
	for directory in DirAccess.get_directories_at(path): _collect_files(path.path_join(directory), paths)

## Pure observer: never advances, heals, restores, or mutates the production state.
class CrownCoverage extends RefCounted:
	const ENCOUNTER_STEP_USEC := 100000 # TwinCrownEncounter.STEP_USEC; verified by contract test.
	var encounter_seconds := 0.0
	var roster_wall_seconds := 0.0
	var fired_attacks: Dictionary = {}
	var modes_seen: Dictionary = {}
	var attempts: Dictionary = {}
	var roster_transitions: Array[Dictionary] = []
	var errors: Array[String] = []
	var last_roster: Array[String] = []
	var last_clock_usec := 0
	var last_reset := -1
	var initial_reset := 0
	var last_attempt := 0
	var last_eligible := false
	var observations := 0

	static func policy(target: float) -> Dictionary:
		return {"minimum_roster_wall_fraction":0.8, "minimum_encounter_clock_wall_fraction":0.7,
			"minimum_fired_attacks":1 if target < 300 else int(ceil(target / 20.0)),
			"window_seconds":60.0, "minimum_fired_attacks_per_complete_window":0 if target < 300 else 3,
			"rationale":"Normal phase-one attacks use 7s scheduling plus migration gaps. At least 3 observed active attacks per complete minute, 80% eligible roster and 70% advancing encounter clock prevent an early warning or idle remainder from satisfying a long run. These are workload coverage limits, not FPS acceptance."}

	func observe(state: Dictionary, active: bool, effective_roster: Array[String], dt: float, elapsed: float, reset_serial: int) -> void:
		var attempt := int(state.get("attempt", 0))
		var clock_usec := int(state.get("tick", 0)) * ENCOUNTER_STEP_USEC + int(state.get("pending_usec", 0))
		var eligible: bool = active and not state.get("completed", true) and not effective_roster.is_empty()
		var reset_changed: bool = observations > 0 and reset_serial != last_reset
		if observations == 0 or effective_roster != last_roster or eligible != last_eligible or reset_changed:
			roster_transitions.append({"time_s":elapsed, "reset_serial":reset_serial, "attempt":attempt, "boss_active":active, "eligible":eligible, "effective_players":effective_roster.duplicate()})
		if observations == 0: initial_reset = reset_serial
		if observations > 0:
			if reset_serial < last_reset: _error("crown_reset_serial_regressed")
			if not reset_changed and attempt != last_attempt: _error("crown_attempt_changed_without_reset")
			if not reset_changed and clock_usec < last_clock_usec: _error("crown_clock_regressed_without_reset")
		var key := "%d:%d" % [reset_serial, attempt]
		if not attempts.has(key): attempts[key] = {"reset_serial":reset_serial, "attempt":attempt, "start_s":elapsed, "end_s":elapsed, "roster_wall_seconds":0.0, "encounter_seconds":0.0, "fired_attacks":0}
		attempts[key].end_s = elapsed
		# Both endpoints must be eligible. Ambiguous retry-crossing deltas are not
		# credited, but their original wall intervals remain in the frame CSV.
		if observations > 0 and not reset_changed and eligible and last_eligible:
			roster_wall_seconds += dt
			attempts[key].roster_wall_seconds += dt
			var advanced := maxf(0.0, (clock_usec - last_clock_usec) / 1000000.0)
			encounter_seconds += advanced
			attempts[key].encounter_seconds += advanced
		modes_seen[str(state.get("mode", "missing"))] = true
		var attacks: Array = state.get("hazards", []).duplicate()
		var primary: Dictionary = state.get("attack", {})
		if not primary.is_empty(): attacks.append(primary)
		if eligible:
			for attack in attacks:
				if not attack.get("fired", false) or int(state.tick) < int(attack.fire_tick) or int(state.tick) >= int(attack.end_tick): continue
				var token := str(attack.token)
				if fired_attacks.has(token): continue
				fired_attacks[token] = {"time_s":elapsed, "attempt":attempt, "reset_serial":reset_serial, "kind":str(attack.kind), "fire_tick":int(attack.fire_tick), "observed_tick":int(state.tick), "effective_roster":effective_roster.duplicate()}
				attempts[key].fired_attacks += 1
		last_roster = effective_roster.duplicate()
		last_clock_usec = clock_usec
		last_reset = reset_serial
		last_attempt = attempt
		last_eligible = eligible
		observations += 1

	func validity_issues(measured: float, target: float) -> Array[String]:
		var result: Array[String] = errors.duplicate()
		var limits := policy(target)
		if roster_wall_seconds < measured * float(limits.minimum_roster_wall_fraction): result.append("insufficient_crown_effective_roster_time")
		if encounter_seconds < measured * float(limits.minimum_encounter_clock_wall_fraction): result.append("insufficient_crown_clock_progress")
		if fired_attacks.size() < int(limits.minimum_fired_attacks): result.append("insufficient_actual_fired_crown_attacks")
		if target >= 300:
			for index in range(int(floor(minf(measured, target) / 60.0))):
				var count := 0
				for attack in fired_attacks.values():
					if float(attack.time_s) >= index * 60.0 and float(attack.time_s) < (index + 1) * 60.0: count += 1
				if count < int(limits.minimum_fired_attacks_per_complete_window): result.append("insufficient_fired_attacks_in_minute:%d" % index)
		return result

	func report() -> Dictionary:
		return {"fired_attacks":fired_attacks.duplicate(true), "fired_attack_count":fired_attacks.size(), "modes_seen":modes_seen.keys(),
			"effective_roster_wall_seconds":roster_wall_seconds, "encounter_advanced_seconds":encounter_seconds,
			"natural_resets":maxi(0, last_reset - initial_reset), "initial_reset_serial":initial_reset, "final_reset_serial":last_reset,
			"attempts":attempts.values().duplicate(true), "roster_transitions":roster_transitions.duplicate(true), "observation_errors":errors.duplicate()}

	func _error(value: String) -> void:
		if not errors.has(value): errors.append(value)
