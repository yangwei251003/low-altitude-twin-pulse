extends "res://scripts_tools/v3/capture_growth_crossing.gd"
## Raw candidate loaded only in this process, with exact triangle collision.
const Seal = preload("res://scripts/v3/art/twin_rising_seal.gd")
const SOURCE = "res://assets/v3/candidates/rising_seal_p2/rising_seal_p2.glb"
const EXPECTED_SHA = "119deb3dcb6af31234b8445848da8cfb509753aedaf9d80e1e6db0244eed9b1b"
var checks: Array = []
var failures: Array = []
var candidate
var detached: Node3D

func _run() -> void:
	var safe = false
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--qa-profile=qa_visual_"): safe = true
		if arg.begins_with("--capture-output="): output = arg.trim_prefix("--capture-output=")
	if not safe or DisplayServer.get_name() == "headless" or output.is_empty(): quit(2); return
	DirAccess.make_dir_recursive_absolute(output)
	var before = _review_inputs()
	_check(FileAccess.get_sha256(SOURCE) == EXPECTED_SHA, "frozen PBR candidate SHA")
	if not failures.is_empty(): await _finish(before); return
	session = load("res://scenes/v3/main.tscn").instantiate()
	root.add_child(session)
	if not session.start_flight("solo") or not session._load_region("F1"): quit(1); return
	session.set_process(false)
	session.set_physics_process(false)
	session.inputs.set_process(false)
	session.inputs.set_physics_process(false)
	await _pose(Vector3(6, 5.4, 26), 26)
	await _capture("01-graybox-closed")
	var document = GLTFDocument.new()
	var state = GLTFState.new()
	_check(document.append_from_file(ProjectSettings.globalize_path(SOURCE), state) == OK, "actual Godot reads candidate GLB")
	if not failures.is_empty(): await _finish(before); return
	var model = document.generate_scene(state) as Node3D
	_check(model != null and model.transform.is_equal_approx(Transform3D.IDENTITY), "unit root; no corrective transform")
	if model == null: await _finish(before); return
	detached = session.world.gate
	session.world.remove_child(detached)
	candidate = Seal.new()
	candidate.name = "ReviewedRisingSeal"
	candidate.install_model(model)
	candidate.position = Vector3(6, 5.4, 26)
	session.world.add_child(candidate)
	session.world.gate = candidate
	_check(candidate.imported and candidate.collision_parts == 4 and candidate.triangles == 18528, "all four source meshes, 18528 triangles and three anchors mounted")
	await _pose(Vector3(6, 5.4, 26), 26)
	_check(_gate_hit(Vector3(3, 5.4, 26), Vector3(9, 5.4, 26)), "closed core blocks actual physics ray")
	_check(not _gate_hit(Vector3(3, 7.88, 29.49), Vector3(9, 7.88, 29.49)), "empty upper corner is not filled by the old solid box")
	await _capture("02-candidate-closed-default")
	await _pose(Vector3(6, 4.0, 26), 15)
	await _capture("03-candidate-closed-near")
	await _place(Vector3(3, 6.5, 25))
	var blocked = false
	for i in range(60):
		if session.players[1].move_and_collide(Vector3(0.1, 0, 0)) != null:
			blocked = true
			break
	_check(blocked and session.players[1].position.x < 6.5, "actual TR01 sweep is stopped by the closed slab")
	await _place(Vector3(-24, 5.2, 29))
	for i in range(2): _ability("light", "F1:mirror")
	for i in range(100):
		session.world.synchronize(session.entities, 1.0 / 60.0)
		await physics_frame
	await _place(Vector3(-18, 6.4, 29))
	for i in range(2): _ability("growth", "F1:growth")
	session.world.synchronize(session.entities, 0.0)
	await _place(Vector3(-14, 2.5, 20))
	_ability("charge", "F1:relay")
	for i in range(43):
		session.world.synchronize(session.entities, 1.0 / 60.0)
		candidate.set_gate_state(session.world.gate_fraction, session.world.gate_open)
		await physics_frame
	_check(session.world.gate_fraction > 0.45 and session.world.gate_fraction < 0.55, "real relay moves the candidate halfway")
	await _pose(Vector3(6, 6.8, 26), 24)
	await _capture("04-candidate-half-raised")
	for i in range(60):
		session.world.synchronize(session.entities, 1.0 / 60.0)
		candidate.set_gate_state(session.world.gate_fraction, session.world.gate_open)
		await physics_frame
	_check(session.stats.abilities == 5 and session.stats.rejected_abilities == 0, "two light, two growth, one charge accepted; no energy refill")
	_check(session.world.growth_bridge.collision_layer == 1, "real growth restores the independent bridge")
	_check(session.world.gate_fraction > 0.99 and absf(candidate.position.y - 11.4) < 0.001, "six metre opening motion retains the authored pivot")
	_check(not _gate_hit(Vector3(3, 6.5, 26), Vector3(9, 6.5, 26)), "open flight passage has no remaining slab collision")
	await _pose(Vector3(6, 7.0, 26), 26)
	await _capture("05-candidate-raised-default")
	await _pose(Vector3(0, 5, 25), 35)
	await _capture("06-candidate-route-context")
	await _place(Vector3(3, 6.5, 25))
	var clear = true
	for i in range(60):
		if session.players[1].move_and_collide(Vector3(0.1, 0, 0)) != null: clear = false
	_check(clear and session.players[1].position.distance_to(Vector3(9, 6.5, 25)) < 0.02, "actual TR01 sweep crosses the open gate")
	# Explicit power-loss fixture exercises the production anti-crush rule.
	session.entities["F1:relay"].charge = 0.0
	session.entities["F1:relay"].powered = false
	await _place(Vector3(6, 8.6, 26))
	for i in range(100):
		session.world.synchronize(session.entities, 1.0 / 60.0)
		candidate.set_gate_state(session.world.gate_fraction, session.world.gate_open)
		await physics_frame
	_check(session.world.gate_obstructed and session.world.gate_fraction > 0.5, "real body stops closing before the candidate crushes it")
	await _pose(Vector3(6, 8.6, 26), 24)
	await _capture("07-candidate-obstruction")
	await _place(Vector3(0, 6.5, 25))
	for i in range(100):
		session.world.synchronize(session.entities, 1.0 / 60.0)
		candidate.set_gate_state(session.world.gate_fraction, session.world.gate_open)
		await physics_frame
	_check(session.world.gate_fraction < 0.01, "closing completes after the body leaves")
	await _finish(before)

func _gate_hit(from: Vector3, to: Vector3) -> bool:
	var hit = session.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(from, to, 1))
	return not hit.is_empty() and hit.collider == candidate

func _review_inputs() -> Dictionary:
	var result = _inputs()
	for path in [SOURCE, "res://scripts_tools/v3/capture_rising_seal_p2.gd", "res://scripts/v3/art/twin_rising_seal.gd", "res://scripts/v3/twin_test_world.gd"]:
		result[path] = FileAccess.get_sha256(path)
	return result

func _check(ok: bool, label: String) -> void:
	checks.append({"passed":ok, "name":label})
	if not ok: failures.append(label)

func _finish(before: Dictionary) -> void:
	_check(_review_inputs() == before, "candidate and relevant source inputs unchanged")
	var file = FileAccess.open(output.path_join("capture.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify({"purpose":"Isolated actual GPU assembly of raw PBR GLB and matching triangle collision. Five real abilities; explicit power-loss fixture and scripted body sweeps. No production replacement, human play, performance or two-PC validation.", "source":SOURCE, "input_sha256":before, "checks":checks, "failures":failures, "shots":shots}, "\t"))
	file.close()
	print("RISING_SEAL_P2_ASSEMBLY ", JSON.stringify({"checks":checks.size(), "failures":failures, "shots":shots.size(), "output":output}))
	if is_instance_valid(detached): detached.free()
	if is_instance_valid(session):
		session.network.close()
		session.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)
