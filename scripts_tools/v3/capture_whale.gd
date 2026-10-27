extends "res://scripts_tools/v3/capture_assets.gd"
## Actual game renderer, imported asset and production encounter poses.
## Scripted progression is a visual inspection fixture, never a human playtest.
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
	if not session.world.whale_ready():
		push_error("Whale GLB wrapper did not load")
		quit(1)
		return
	await _pose(Vector3(14, 9, -27), 26)
	await _capture("01-whale-closed-default")
	session._start_boss()
	await _pose(Vector3(23, 9, -27), 30)
	session._handle_boss_events(session.encounter.advance(2.7))
	session._sync_boss_entities()
	session._update_boss_warning()
	session._refresh_interface()
	await _capture("02-whale-side-hatches-open")
	session._handle_boss_events(session.encounter.set_node_power("port", false, "1").get("events", []))
	session._handle_boss_events(session.encounter.set_node_power("starboard", false, "1").get("events", []))
	session._sync_boss_entities()
	await _pose(Vector3(14, 10, -25), 26)
	session.locks[1] = "boss:core"
	session._refresh_interface()
	await _capture("03-whale-core-exposed")
	session._handle_boss_events(session.encounter.hit_part("core", 65, "1").get("events", []))
	session._sync_boss_entities()
	session._refresh_interface()
	await _capture("04-whale-overdrive-warning")
	session._handle_boss_events(session.encounter.advance(2.7))
	session.encounter.set_node_power("port", false, "1")
	session.encounter.set_node_power("starboard", false, "1")
	# The fixture uses noncampaign completion; explicitly show the durable defeated view.
	session._handle_boss_events(session.encounter.hit_part("core", 65, "1").get("events", []))
	session.world.set_boss_state({}, true)
	await _pose(session.world.whale_record_position() + Vector3(0, 2, 2), 26)
	await _capture("05-whale-stopped-record-position")
	await _pose(session.world.boss_retry_position(0), 30)
	await _capture("06-north-maintenance-deck")
	var file = FileAccess.open(output.path_join("capture.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify({"purpose":"actual Compatibility renderer and imported GLB; scripted encounter and camera; not full story, human challenge or performance acceptance", "model_sha256":FileAccess.get_sha256("res://assets/v3/whale/siphon_whale.glb"), "record":str(session.world.whale_record_position()), "retry":str(session.world.boss_retry_position(0)), "shots":shots, "driver":RenderingServer.get_video_adapter_name()}, "\t"))
	file.close()
	print("V3_WHALE_CAPTURE ", output)
	session.network.close()
	session.queue_free()
	await process_frame
	quit()
