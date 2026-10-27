extends "res://scripts_tools/v3/capture_growth_crossing.gd"
## Isolated assembly review only: raw frozen GLB via GLTFDocument, no production replacement.
const SOURCE = "res://asset_sources/v3/growth_approach/west_p2/west_p2_review.glb"
const EXPECTED_SHA = "2f118763033c210b771c528769ea292cd437a58ee8fce883d9be3ebd96b71264"
var checks: Array = []
var failures: Array = []
var candidate: Node3D
var detached: Node3D

func _run() -> void:
	var safe = false
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--qa-profile=qa_visual_"): safe = true
		if arg.begins_with("--capture-output="): output = arg.trim_prefix("--capture-output=")
	if not safe or DisplayServer.get_name() == "headless" or output.is_empty(): quit(2); return
	DirAccess.make_dir_recursive_absolute(output)
	var before = _review_inputs()
	_check(FileAccess.get_sha256(SOURCE) == EXPECTED_SHA, "frozen basic-material GLB SHA")
	if not failures.is_empty(): await _finish(before); return
	session = load("res://scenes/v3/main.tscn").instantiate()
	root.add_child(session)
	if not session.start_flight("solo") or not session._load_region("F1"): quit(1); return
	session.set_process(false)
	session.set_physics_process(false)
	session.inputs.set_process(false)
	session.inputs.set_physics_process(false)
	await _pose(Vector3(-14, 5, 25), 18)
	await _capture("01-graybox-west-join")
	var document = GLTFDocument.new()
	var state = GLTFState.new()
	_check(document.append_from_file(ProjectSettings.globalize_path(SOURCE), state) == OK, "raw explicit GLB parsed by actual Godot GLTFDocument")
	if not failures.is_empty(): await _finish(before); return
	candidate = document.generate_scene(state) as Node3D
	_check(candidate != null, "candidate scene generated")
	if candidate == null: await _finish(before); return
	_check(candidate.transform.is_equal_approx(Transform3D.IDENTITY), "GLB unit root; no corrective scale or rotation")
	session.world.add_child(candidate)
	candidate.position = Vector3(-14.5, 0, 25)
	var meshes = candidate.find_children("*", "MeshInstance3D", true, false)
	var triangles = 0
	for mesh: MeshInstance3D in meshes:
		triangles += mesh.mesh.get_faces().size() / 3
		var body = StaticBody3D.new()
		body.collision_layer = 1
		body.collision_mask = 0
		body.set_meta("entity_id", "terrain:growth_approach:west")
		mesh.add_child(body)
		var collider = CollisionShape3D.new()
		collider.shape = mesh.mesh.create_trimesh_shape()
		collider.shape.backface_collision = true
		body.add_child(collider)
	_check(meshes.size() == 6 and triangles == 22656, "all six source meshes and 22656 actual triangles become both view and collision")
	detached = session.world.get_node("GrowthApproach_west")
	session.world.remove_child(detached)
	await physics_frame
	await physics_frame
	for z in [23.52, 24.0, 25.0, 26.0, 26.48]: _support(Vector3(-11.001, 5.25, z), "formal full-width lip " + str(z))
	for z in [23.52, 25.0, 26.48]: _support(Vector3(-10.751, 5.20, z), "lower nose " + str(z))
	await _pose(Vector3(-14, 5, 25), 18)
	await _capture("02-candidate-west-join")
	await _pose(Vector3(-14, 2.5, 25), 14)
	await _capture("03-candidate-lower-rock-root")
	await _place(Vector3(-24, 5.2, 29))
	for i in range(2): _ability("light", "F1:mirror")
	for i in range(100):
		session.world.synchronize(session.entities, 1.0 / 60.0)
		await physics_frame
	await _place(Vector3(-18, 6.4, 29))
	for i in range(2): _ability("growth", "F1:growth")
	session.world.synchronize(session.entities, 0.0)
	_check(session.world.growth_bridge.collision_layer == 1, "real light path and growth activate the central bridge with candidate collision")
	await _place(Vector3(-14, 2.5, 20))
	_ability("charge", "F1:relay")
	for i in range(100):
		session.world.synchronize(session.entities, 1.0 / 60.0)
		await physics_frame
	_check(session.world.gate_fraction > 0.99, "real relay opens independent gate")
	_check(session.stats.abilities == 5 and session.stats.rejected_abilities == 0, "five real host abilities accepted without resource fixture")
	await _pose(Vector3(-14, 5, 25), 18)
	await _capture("04-candidate-grown-join")
	await _pose(Vector3(0, 5, 25), 35)
	await _capture("05-candidate-route-context")
	await _place(Vector3(-14, 6.5, 25))
	var clear = true
	for i in range(40):
		if session.players[1].move_and_collide(Vector3(0.1, 0, 0)) != null: clear = false
	_check(clear and session.players[1].position.distance_to(Vector3(-10, 6.5, 25)) < 0.02, "actual TR01 body clears west approach to bridge at Y6.5; scripted sweep, not control/play proof")
	await _finish(before)

func _support(at: Vector3, label: String) -> void:
	var query = PhysicsRayQueryParameters3D.create(at + Vector3.UP * 0.1, at - Vector3.UP * 0.1, 1)
	var hit = session.get_world_3d().direct_space_state.intersect_ray(query)
	_check(not hit.is_empty() and candidate.is_ancestor_of(hit.collider) and absf(hit.position.y - at.y) < 0.003, "candidate first-hit collision at " + label)

func _check(ok: bool, label: String) -> void:
	checks.append({"passed":ok, "name":label})
	if not ok: failures.append(label)

func _review_inputs() -> Dictionary:
	var result = _inputs()
	for path in [SOURCE, "res://scripts_tools/v3/capture_growth_approach_west_p2.gd", "res://scripts/v3/twin_interface.gd", "res://scripts/v3/twin_session.gd", "res://scripts/v3/ui/twin_opening_guidance.gd"]:
		result[path] = FileAccess.get_sha256(path)
	return result

func _finish(before: Dictionary) -> void:
	_check(_review_inputs() == before, "source, production and capture inputs unchanged")
	var file = FileAccess.open(output.path_join("capture.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify({"purpose":"Frozen basic-material GLB loaded at runtime with actual triangle collision in isolated QA process. West graybox removed only in this process. No production import replacement, final PBR, full passage validation, performance or human play acceptance.", "source":SOURCE, "input_sha256":before, "checks":checks, "failures":failures, "shots":shots}, "\t"))
	file.close()
	print("WEST_P2_ASSEMBLY ", JSON.stringify({"checks":checks.size(), "failures":failures, "shots":shots.size(), "output":output}))
	if is_instance_valid(detached): detached.free()
	if is_instance_valid(session):
		session.network.close()
		session.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)
