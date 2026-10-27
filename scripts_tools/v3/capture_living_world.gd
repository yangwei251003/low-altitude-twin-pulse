extends "res://scripts_tools/v3/capture_assets.gd"
## Scripted camera on the real game renderer. No human-play or performance claim.
func _run() -> void:
	var safe = false
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--qa-profile=qa_visual_"): safe = true
		if arg.begins_with("--capture-output="): output = arg.trim_prefix("--capture-output=")
	if not safe or output.is_empty() or DisplayServer.get_name() == "headless":
		quit(2)
		return
	DirAccess.make_dir_recursive_absolute(output)
	session = load("res://scenes/v3/main.tscn").instantiate()
	root.add_child(session)
	session.start_flight("solo")
	session.set_process(false)
	session.set_physics_process(false)
	session.inputs.set_process(false)
	session.inputs.set_physics_process(false)
	# Use production charge intents to open the supply route. Only time is
	# accelerated explicitly; these are scripted demonstrations, not playtests.
	await _place(Vector3(-14, 2, 20))
	for attempt in range(2):
		session.cooldowns[1] = 0.0
		session._action_received(1, "ability", {"ability":"charge", "target_id":"I1:relay"})
	for tick in range(140): session.ecology.advance(1.0)
	session.world.synchronize(session.entities, 0.0)
	await _pose(Vector3(-21, 4, 24), 32)
	session.ecology.update_view(1.0, session.players[1].position)
	await _capture("01-harbor-service-apron")
	await _pose(Vector3(34, 6, 22), 32)
	await _capture("02-harbor-freight-apron")
	await _pose(Vector3(0, 6, -8), 36)
	await _capture("03-harbor-upper-bridge")
	await _pose(Vector3(-28, 4, 14), 23)
	session.ecology.update_view(1.0, session.players[1].position)
	await _capture("04-harbor-stock-after-transport")
	var service_evidence: Dictionary = session.ecology.persistent_state()
	session._load_region("F1")
	await _pose(Vector3(0, 7, -6), 38)
	await _capture("05-root-arch")
	var pollinator: Dictionary = session.ecology.simulation.get_actor("F1:pollinator_01")
	var p: Array = pollinator.position
	await _pose(Vector3(p[0], p[1], p[2]) + Vector3(0, -1, 2), 24)
	session.ecology.update_view(1.0, session.players[1].position)
	await _capture("06-fantasy-offscreen-actor")
	var report = FileAccess.open(output.path_join("capture.json"), FileAccess.WRITE)
	report.store_string(JSON.stringify({"purpose":"actual game renderer; scripted camera and accelerated host simulation; partial world under review", "not_evidence_of":["human play", "real-time performance", "final NPC art"], "driver":RenderingServer.get_video_adapter_name(), "shots":shots, "service_after_140_seconds":service_evidence, "offscreen_actor":pollinator, "ability_count":session.stats.abilities, "rejected_abilities":session.stats.rejected_abilities}, "\t"))
	report.close()
	print("V3_LIVING_WORLD_CAPTURE ", output)
	session.network.close()
	session.queue_free()
	await process_frame
	quit()
