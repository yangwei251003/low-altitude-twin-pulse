extends SceneTree
## Render the real game viewport with the installed Compatibility driver.
## Camera placement is scripted; images are not human-playtest evidence.

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("Visual capture requires a rendering window, not --headless")
		quit(2)
		return
	var profile_ok = false
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--qa-profile=qa_visual_"): profile_ok = true
	if not profile_ok:
		push_error("Use an isolated --qa-profile=qa_visual_<unique>")
		quit(2)
		return
	var session = load("res://scenes/v3/main.tscn").instantiate()
	root.add_child(session)
	await create_timer(1.0).timeout
	await _capture("menu")
	session.start_flight("solo")
	await create_timer(1.0).timeout
	await _capture("I1-spawn")
	session.set_physics_process(false)
	session.players[1].freeze = true
	session.players[1].global_position = Vector3(-3, 5, -8)
	session.flight_camera.snap(session.players[1].global_position)
	await create_timer(1.0).timeout
	await _capture("I1-bridge")
	session._load_region("F1")
	session.players[1].global_position = Vector3(0, 8, -5)
	session.flight_camera.snap(session.players[1].global_position)
	await create_timer(1.0).timeout
	await _capture("F1-root-bridge")
	var meta = {"purpose":"actual game viewport, scripted camera, mechanics graybox; not final art or human playtest", "driver":RenderingServer.get_video_adapter_name(), "display":DisplayServer.get_name(), "viewport":str(root.size), "user_dir":OS.get_user_data_dir()}
	var file = FileAccess.open("res://artifacts/v3/visual/capture.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(meta, "\t"))
	print("V3_VISUAL_CAPTURE ", JSON.stringify(meta))
	session.network.close()
	quit()

func _capture(label: String) -> void:
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute("res://artifacts/v3/visual")
	var error = root.get_texture().get_image().save_png("res://artifacts/v3/visual/" + label + ".png")
	if error != OK: push_error("Capture failed: " + label)
