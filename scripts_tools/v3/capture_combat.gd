extends "res://scripts_tools/v3/capture_assets.gd"
## Real GPU warning review; scripted poses do not demonstrate human play or performance.
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
	await _pose(Vector3(14, 5, -20), 26)
	session._start_boss()
	for attack in ["low_sweep", "high_lance", "tractor"]:
		session._telegraph(attack, 1.2)
		session._refresh_interface()
		await _capture("warning-" + attack)
	var file = FileAccess.open(output.path_join("capture.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify({"purpose":"actual GPU warning bounds review; scripted, no human play or performance claim", "shots":shots, "driver":RenderingServer.get_video_adapter_name()}, "\t"))
	file.close()
	print("V3_COMBAT_CAPTURE ", output)
	session.network.close()
	session.queue_free()
	await process_frame
	quit()
