extends "res://scripts_tools/v3/capture_assets.gd"
## Asset acceptance views in the real fixed-camera scene, never offline renders.
func _run() -> void:
	var safe = false
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--qa-profile=qa_visual_"): safe = true
		if arg.begins_with("--capture-output="): output = arg.trim_prefix("--capture-output=")
	if not safe or DisplayServer.get_name() == "headless" or output.is_empty():
		quit(2)
		return
	DirAccess.make_dir_recursive_absolute(output)
	session = load("res://scenes/v3/main.tscn").instantiate()
	root.add_child(session)
	session.start_flight("solo")
	session.set_physics_process(false)
	session.set_process(false)
	session.inputs.set_physics_process(false)
	session.inputs.set_process(false)
	await _pose(Vector3(-36, 5.2, 3), 26)
	await _capture("01-industrial-terraces-default")
	await _pose(Vector3(-41, 5.4, 6), 19)
	await _capture("02-industrial-stairs-near")
	await _pose(Vector3(-30, 9.2, -4), 26)
	await _capture("03-industrial-upper-route")
	if not "--industrial-only" in OS.get_cmdline_user_args():
		await _pose(Vector3(-14, 2, 20), 16)
		await _capture("04-relay-off")
		session.cooldowns[1] = 0.0
		session._action_received(1, "ability", {"ability":"charge", "target_id":"I1:relay"})
		session.world.synchronize(session.entities, 0)
		await _capture("05-relay-charged")
		session._load_region("F1")
		await _pose(Vector3(-35, 2, -8), 26)
		await _capture("06-fantasy-cave-default")
		await _pose(Vector3(-35, 2, -8), 18)
		await _capture("07-fantasy-cave-near")
		await _pose(Vector3(35, 9, -13), 26)
		await _capture("08-fantasy-upper-route")
		await _pose(Vector3(-21, 5.5, 27), 26)
		await _capture("09-roots-closed")
		await _place(Vector3(-24, 5.2, 29))
		for i in range(2):
			session.cooldowns[1] = 0.0
			session._action_received(1, "ability", {"ability":"light", "target_id":"F1:mirror"})
		for i in range(60):
			session.world.synchronize(session.entities, 1.0/60.0)
			await physics_frame
		await _place(Vector3(-18, 6.4, 29))
		for i in range(2):
			session.cooldowns[1] = 0.0
			session._action_received(1, "ability", {"ability":"growth", "target_id":"F1:growth"})
		session.world.synchronize(session.entities, 0)
		await _pose(Vector3(-19, 6, 26), 26)
		await _capture("10-roots-lit-grown")
	var file = FileAccess.open(output.path_join("capture.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify({"purpose":"real compatibility viewport with scripted placement; partial art, no human play or performance claim", "shots":shots, "driver":RenderingServer.get_video_adapter_name(), "abilities":session.stats.abilities,"rejected":session.stats.rejected_abilities}, "\t"))
	file.close()
	print("V3_KIT_CAPTURE ", output, " shots=", shots.size())
	session.network.close()
	session.queue_free()
	await process_frame
	quit()
