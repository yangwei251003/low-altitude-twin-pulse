extends SceneTree
## Real Compatibility viewport; scripted inputs/camera, not human play evidence.
var session
var output = ""
var shots: Array = []
var movie_tour = false
var passage_checks: Array = []

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var safe = false
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--qa-profile=qa_visual_"): safe = true
		if arg.begins_with("--capture-output="): output = arg.trim_prefix("--capture-output=")
		if arg == "--asset-tour": movie_tour = true
	if not safe or DisplayServer.get_name() == "headless" or output.is_empty():
		push_error("Use rendered window, qa_visual_<unique> profile and capture-output")
		quit(2)
		return
	DirAccess.make_dir_recursive_absolute(output)
	session = load("res://scenes/v3/main.tscn").instantiate()
	root.add_child(session)
	await create_timer(0.7).timeout
	await _capture("00-menu")
	session.start_flight("solo")
	session.set_physics_process(false)
	session.set_process(false)
	session.inputs.set_physics_process(false)
	session.inputs.set_process(false)
	await _pose(Vector3(-22, 4, 30), 26)
	await _capture("01-I-B-default-camera")
	await _pose(Vector3(-24, 4.5, 25), 19)
	await _capture("02-I-B-closed")
	# A real action through the host adapter, then physics-time state updates.
	await _place(Vector3(-14, 2, 20))
	session.cooldowns[1] = 0.0
	session._action_received(1, "ability", {"ability":"charge", "target_id":"I1:relay"})
	for i in range(44):
		session.world.synchronize(session.entities, 1.0/60.0)
		await physics_frame
	await _pose(Vector3(-24, 4.5, 25), 19)
	await _capture("03-I-B-half-open")
	for i in range(60):
		session.world.synchronize(session.entities, 1.0/60.0)
		await physics_frame
	await _capture("04-I-B-open")
	await _pose(Vector3(-24, 2, 25), 14)
	await _capture("05-I-B-underpass")
	if movie_tour:
		await _fly_passage(session.world.art_bridge.marker_position("UnderStart"), session.world.art_bridge.marker_position("UnderEnd"), "bridge_underpass")
		var passage = session.world.gate_passage()
		await _fly_passage(passage[0], passage[1], "open_shutter")
	session._load_region("F1")
	await _pose(Vector3(-23, 4.5, 28), 26)
	await _capture("06-F-B-default-camera")
	await _pose(Vector3(-24, 4.8, 25), 19)
	await _capture("07-F-B-initial-ring")
	if movie_tour:
		await _fly_passage(Vector3(-24, 5.2, 29), Vector3(-24, 5.2, 21), "temple_hole")
	await _place(Vector3(-24, 5.2, 29))
	for i in range(2):
		session.cooldowns[1] = 0.0
		session._action_received(1, "ability", {"ability":"light", "target_id":"F1:mirror"})
	for i in range(60):
		session.world.synchronize(session.entities, 1.0/60.0)
		await physics_frame
	await _pose(Vector3(-21, 5, 25), 22)
	await _capture("08-F-B-light-on-growth")
	await _place(Vector3(-18, 6.4, 29))
	for i in range(2):
		session.cooldowns[1] = 0.0
		session._action_received(1, "ability", {"ability":"growth", "target_id":"F1:growth"})
	session.world.synchronize(session.entities, 0.0)
	await _pose(Vector3(-14, 6, 25), 30)
	await _capture("09-F-B-grown-route")
	var meta = {"purpose":"actual game viewport, scripted camera and host ability intents; partial art integration, not final game or human playtest", "movie_note":"Movie Maker records engine frames offline with fixed timing; it is not real-time performance or human gameplay evidence" if movie_tour else "no movie", "passage_checks":passage_checks, "driver":RenderingServer.get_video_adapter_name(), "display":DisplayServer.get_name(), "viewport":str(root.size), "shots":shots, "abilities_applied":session.stats.abilities, "abilities_rejected":session.stats.rejected_abilities, "growth":session.entities["F1:growth"], "ring_angle":session.world.rotor_angle, "mechanisms":session.world.mechanism_snapshot()}
	var file = FileAccess.open(output.path_join("capture.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(meta, "\t"))
	print("V3_ASSET_CAPTURE ", JSON.stringify({"output":output, "shots":shots.size(), "abilities":session.stats.abilities, "rejected":session.stats.rejected_abilities}))
	session.network.close()
	session.queue_free()
	await process_frame
	quit()

func _fly_passage(from: Vector3, to: Vector3, label: String) -> void:
	await _place(from)
	session.flight_camera.target_size = 18
	session.flight_camera.snap((from + to) * 0.5)
	var blocked = false
	for i in range(90):
		var collision = session.players[1].move_and_collide((to - from) / 90.0)
		if collision: blocked = true
		await process_frame
	passage_checks.append({"path":label, "blocked":blocked, "reached":session.players[1].position.distance_to(to) < 0.05, "method":"scripted real flight-body sweeps; propulsion frozen"})
	await create_timer(0.7).timeout

func _place(at: Vector3) -> void:
	var body = session.players[1]
	body.freeze = true
	body.set_physics_process(false)
	body.set_process(false)
	body.position = at
	body.linear_velocity = Vector3.ZERO
	session.entities["player:1"].position = at
	await physics_frame
	await physics_frame

func _pose(at: Vector3, zoom: float) -> void:
	await _place(at)
	session.flight_camera.target_size = zoom
	session.flight_camera.snap(at)
	session._refresh_interface()
	await create_timer(0.35).timeout

func _capture(label: String) -> void:
	if session.active:
		session.interface.vitals.text = "脚本动作演示 · 非真人试玩与帧率证据" if movie_tour else "实际游戏视口 · 脚本摆位 · 性能另行测量"
	if movie_tour: await create_timer(1.0).timeout
	await RenderingServer.frame_post_draw
	var path = output.path_join(label + ".png")
	var error = root.get_texture().get_image().save_png(path)
	if error != OK: push_error("Capture failed: " + path)
	shots.append({"id":label, "file":path, "camera_size":session.camera.size, "camera_transform":str(session.camera.global_transform), "draw_calls":Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME), "triangles":Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)})
