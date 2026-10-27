extends "res://scripts_tools/v3/capture_assets.gd"
## Actual viewport review of UI and the integrated H10, scripted poses only.
var checks: Array = []
var failures: Array = []
var hashes: Dictionary = {}

func _run() -> void:
	var safe = false
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--qa-profile=qa_visual_"): safe = true
		if arg.begins_with("--capture-output="): output = arg.trim_prefix("--capture-output=")
	if not safe or DisplayServer.get_name() == "headless" or output.is_empty(): quit(2); return
	DirAccess.make_dir_recursive_absolute(output)
	hashes = _inputs()
	session = load("res://scenes/v3/main.tscn").instantiate()
	root.add_child(session)
	if not session.start_flight("solo"): quit(1); return
	session.set_process(false)
	session.set_physics_process(false)
	session.inputs.set_process(false)
	session.inputs.set_physics_process(false)
	await _place(Vector3(-18, 2.5, 35))
	session._action_received(1, "explore", {"target_id":"npc:linlan"})
	session.interface.clear_dialogue()
	await _pose(Vector3(-18, 2.5, 35), 26)
	session.story.refresh(session.players[1].global_position)
	_check(session.story.state.revision == 1 and session.story.display_anchor().get("anchor_id") == "I1:rescue_pocket", "real rescue briefing produces destination without completing channel")
	await _capture("01-rescue-destination")
	await _pose(Vector3(15, 3, 39), 26)
	_check(session.interface.objective_marker.at_edge, "distant rescue destination remains as one edge direction")
	await _capture("02-objective-edge")
	session.locks[1] = "I1:relay"
	session.interface.select_ability(5)
	await _pose(Vector3(-14, 18, 38), 26)
	_check(session.interface.ability_description.text.contains("还需靠近"), "real charge target uses three-dimensional range feedback")
	await _capture("03-selected-charge-range")
	var count = int(session.stats.abilities)
	session.interface.suggestion_buttons[0].pressed.emit()
	_check(session.stats.abilities == count and session.locks[1] == "I1:relay", "suggestion selection does not cast or change lock")
	session.interface.wheel.show()
	await _capture("04-all-abilities-panel")
	session.interface.wheel.hide()
	if not session._load_region("F1"): quit(1); return
	session.interface.clear_dialogue()
	session.locks[1] = "F1:mirror"
	session.interface.select_ability(3)
	await _pose(Vector3(-24, 5.2, 29), 26)
	await _capture("05-light-tool-matches-ring")
	await _pose(Vector3(8, 13, -23), 34)
	_check(FileAccess.get_sha256("res://assets/v3/root_buttress/root_buttress_h10.glb") == "d8d8877b31a68472610719974df8eeeadb06cb90facaed8a31b86a4b61923850", "actual running H10 is frozen P12")
	await _capture("06-integrated-H10-default")
	await _pose(Vector3(-3, 5, -20), 20)
	await _capture("07-integrated-H10-lower")
	await _place(session.world.crown_arena.host_position("F1:crown_host_west") + Vector3(0, 0, 2.5))
	_check(session.crown.start(false), "real Crown encounter starts")
	for ability in ["light", "growth"]:
		session.cooldowns[1] = 0.0
		session._action_received(1, "ability", {"ability":ability, "target_id":"F1:crown_host_west"})
	_check(session.crown.encounter.get_state().core_open, "light/growth opens core against integrated terrain")
	session.locks[1] = "boss:crown_core"
	await _pose(Vector3(1, 13, -22), 18)
	await _capture("08-core-and-compact-objective")
	session.interface.details_open = true
	session._refresh_interface()
	await _capture("09-expanded-combat-guidance")
	_check(_inputs() == hashes, "reviewed source and asset bytes unchanged during capture")
	var file = FileAccess.open(output.path_join("capture.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify({"purpose":"Actual Compatibility GPU viewport. Scripted poses, first real rescue briefing and Crown light/growth; F1 loading is a QA shortcut, not full-story play or performance evidence.", "checks":checks, "failures":failures, "shots":shots, "input_sha256":hashes}, "\t"))
	file.close()
	print("GUIDANCE_CAPTURE ", JSON.stringify({"checks":checks.size(), "failures":failures, "shots":shots.size(), "output":output}))
	session.network.close()
	session.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)

func _check(ok: bool, label: String) -> void:
	checks.append({"passed":ok, "name":label})
	if not ok: failures.append(label)

func _inputs() -> Dictionary:
	var result = {}
	for path in ["project.godot", "scripts/v3/twin_interface.gd", "scripts/v3/twin_session.gd", "scripts/v3/art/twin_objective_marker.gd", "scripts/v3/ui/twin_opening_guidance.gd", "scripts/v3/gameplay/twin_opening_story.gd", "scripts/v3/gameplay/twin_crown_session.gd", "scripts_tools/v3/capture_guidance.gd", "assets/v3/root_buttress/root_buttress_h10.glb", "data/v3/terrain/f1_shore_layout.json"]:
		result[path] = FileAccess.get_sha256("res://" + path)
	return result
