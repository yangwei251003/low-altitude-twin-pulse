extends "res://scripts_tools/v3/capture_assets.gd"
## Isolated raw-GLB assembly diagnosis. Never replaces a production resource.
const ShoreCapture = preload("res://scripts_tools/v3/capture_shore.gd")
const SOURCE = "res://assets/v3/candidates/shore_root_t03a_p12/shore_root_t03a_diagnostic.glb"
const EXPECTED_SHA = "0427331a7cca5709a36ad7ed49de4b8843dd31e14d5aa1dd96e2270c3e3d4eac"
const EXPECTED_TRIANGLES = 869522
const POSITION = Vector3(-24.5, 0, -6)
const CANDIDATE_QUERY_LAYER = 1 << 22
const ANCHORS = {"GroundOrigin":Vector3.ZERO, "BridgeJoin":Vector3(4.5,4.5,0), "WestBlend":Vector3(-4.3,0.34,0)}
var candidate: Node3D
var checks: Array = []
var failures: Array = []
var mesh_report: Array = []
var support_samples: Array = []
var sweep_samples: Array = []
var baseline_samples: Array = []
var baseline_only = false
var input_hashes: Dictionary = {}
var production_geometry: Dictionary = {}
var visual_only = false
var collision_ready = false
var collision_body_count = 0
var default_camera_size = 0.0
var finished = false
var profile_id = ""
var started_usec = 0

func _run() -> void:
	started_usec = Time.get_ticks_usec()
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--qa-profile="): profile_id = arg.trim_prefix("--qa-profile=")
		if arg.begins_with("--capture-output="): output = arg.trim_prefix("--capture-output=")
		if arg == "--shore-visual-only": visual_only = true
		if arg == "--shore-baseline-only": baseline_only = true
	var allowed_output = ProjectSettings.globalize_path("res://artifacts/v3/art/shore-p12-").replace("\\", "/")
	output = output.replace("\\", "/").simplify_path()
	if not profile_id.begins_with("qa_visual_shore_p12_") or (DisplayServer.get_name() == "headless" and not baseline_only) or not output.begins_with(allowed_output):
		push_error("Use a rendered QA process, unique qa_visual_shore_p12_ profile and artifacts/v3/art/shore-p12-<batch> output")
		quit(2)
		return
	if FileAccess.file_exists(output.path_join("capture.json")) or FileAccess.file_exists(output.path_join("01-default-game-camera.png")) or DirAccess.make_dir_recursive_absolute(output) != OK:
		push_error("Refusing to overwrite an existing diagnosis report")
		quit(2)
		return
	input_hashes = _review_inputs()
	_check(input_hashes[SOURCE] == EXPECTED_SHA, "frozen diagnostic GLB SHA256")
	_check(not input_hashes.values().has(""), "all fingerprinted source and production inputs readable")
	if not failures.is_empty(): await _finish(); return
	session = load("res://scenes/v3/main.tscn").instantiate()
	root.add_child(session)
	_check(session.start_flight("solo") and session._load_region("F1"), "isolated real F1 session loaded")
	if not failures.is_empty(): await _finish(); return
	session.set_process(false)
	session.set_physics_process(false)
	session.inputs.set_process(false)
	session.inputs.set_physics_process(false)
	default_camera_size = session.flight_camera.target_size
	production_geometry = _production_geometry()
	_check(session.world.art_traversal.imported, "existing production root arch remains loaded")
	var document = GLTFDocument.new()
	var state = GLTFState.new()
	_check(document.append_from_file(ProjectSettings.globalize_path(SOURCE), state) == OK, "raw GLB parsed directly; no candidate import cache required")
	if not failures.is_empty(): await _finish(); return
	candidate = document.generate_scene(state) as Node3D
	_check(candidate != null, "actual diagnostic scene generated")
	if candidate == null: await _finish(); return
	_check(candidate.transform.is_equal_approx(Transform3D.IDENTITY), "unit GLB root without corrective scale or rotation")
	if not failures.is_empty(): await _finish(); return
	session.world.add_child(candidate)
	candidate.position = POSITION
	var meshes = candidate.find_children("*", "MeshInstance3D", true, false)
	var actual_triangles = 0
	var material_ids: Dictionary = {}
	var names: Array = []
	for mesh: MeshInstance3D in meshes:
		names.append(str(mesh.name))
		if mesh.mesh == null:
			_check(false, "candidate mesh has geometry: " + str(mesh.name))
			continue
		var triangles = mesh.mesh.get_faces().size() / 3
		actual_triangles += triangles
		for surface in range(mesh.mesh.get_surface_count()):
			var material = mesh.get_active_material(surface)
			if material != null: material_ids[material.get_instance_id()] = str(material.resource_name)
		mesh_report.append({"node":str(mesh.name), "triangles":triangles, "surfaces":mesh.mesh.get_surface_count(), "transform":str(mesh.transform)})
		if visual_only: continue
		var shape = mesh.mesh.create_trimesh_shape()
		if shape == null:
			_check(false, "actual candidate trimesh created: " + str(mesh.name))
			continue
		shape.backface_collision = true
		var body = StaticBody3D.new()
		body.name = "DiagnosticActualTriangleCollision"
		body.collision_layer = 1 | CANDIDATE_QUERY_LAYER
		body.collision_mask = 0
		body.set_meta("entity_id", "terrain:shore_p12_diagnostic")
		mesh.add_child(body)
		var collider = CollisionShape3D.new()
		collider.shape = shape
		body.add_child(collider)
		collision_body_count += 1
	names.sort()
	_check(names == ["LivingRoots", "RockMasses"] and actual_triangles == EXPECTED_TRIANGLES, "two actual meshes and all 869522 source triangles loaded", {"names":names, "triangles":actual_triangles})
	_check(material_ids.size() == 3, "three basic-color materials; no PBR acceptance", {"actual":material_ids.values()})
	for id in ANCHORS:
		var matches = candidate.find_children(str(id), "Node3D", true, false)
		_check(matches.size() == 1 and matches[0].global_position.distance_to(POSITION + ANCHORS[id]) < 0.0001, "unique actual anchor " + str(id))
	_check(session.world.art_traversal.marker_position("EntryWest").distance_to(POSITION + ANCHORS.BridgeJoin) < 0.0001, "candidate BridgeJoin coincides with the unchanged real bridge EntryWest")
	_force_transforms(candidate)
	await physics_frame
	await physics_frame
	collision_ready = not visual_only and collision_body_count == 2
	if not visual_only: _check(collision_ready, "both complete source meshes have actual triangle collision")
	if collision_ready:
		_support_and_sweeps_ready()
		await _passage_sweeps()
	if baseline_only:
		# Same session, original routes and assertions. Only the QA candidate is
		# removed; production bridge/shore/body configuration remain untouched.
		candidate.queue_free()
		await physics_frame
		await physics_frame
		_check(not is_instance_valid(candidate), "QA candidate completely removed before paired baseline")
		await _passage_sweeps(true)
		_check(_production_geometry() == production_geometry, "production bridge and shore unchanged for paired baseline")
		await _finish()
		return
	await _pose(Vector3(-22.5, 6.2, -6), default_camera_size)
	await _capture("01-default-game-camera")
	await _pose(Vector3(-26, 3.2, -1), 16)
	await _capture("02-lower-near-camera")
	await _pose(Vector3(-20, 6.2, -6), 14)
	await _capture("03-actual-bridge-join")
	await _pose(Vector3(-9, 12, -6), 48)
	await _capture("04-shore-and-bridge-overview")
	_check(_production_geometry() == production_geometry, "existing bridge and every production shoreline holder/resource unchanged in QA scene")
	await _finish()

func _support_and_sweeps_ready() -> void:
	# Candidate-only mask attributes support to this geometry even where the
	# retained production bridge/shore overlaps. Actual flight still uses layer 1.
	for x in [3.55, 4.0, 4.49]:
		for z in [-2.75, -1.375, 0.0, 1.375, 2.75]:
			var at = POSITION + Vector3(x, 4.5, z)
			var query = PhysicsRayQueryParameters3D.create(at + Vector3.UP * 0.15, at - Vector3.UP * 0.15, CANDIDATE_QUERY_LAYER)
			var hit = session.get_world_3d().direct_space_state.intersect_ray(query)
			var ok = not hit.is_empty() and candidate.is_ancestor_of(hit.collider) and absf(hit.position.y - 4.5) < 0.003
			support_samples.append({"world":str(at), "hit":str(hit.get("position", Vector3.INF)), "passed":ok})
	_check(support_samples.all(func(row): return row.passed), "15 actual candidate-only ray samples retain the 5.5m bridge interface", {"samples":support_samples})

func _passage_sweeps(baseline: bool = false) -> void:
	var body = session.players[1]
	var envelope = body.get_node_or_null("Envelope") as CollisionShape3D
	_check(envelope != null and envelope.shape is BoxShape3D, "passage uses the real configured flight body envelope")
	if envelope == null: return
	for side in [-1.3, 0.0, 1.3]:
		for reverse in [false, true]:
			var from = Vector3(-21.0, 5.8, -6.0 + side)
			var to = Vector3(-18.5, 5.8, -6.0 + side)
			if reverse:
				var swap = from
				from = to
				to = swap
			await _place(from)
			var actual_start = body.global_position
			var blocked = false
			var collider_name = ""
			var contact = ""
			var normal = ""
			for step in range(50):
				var hit = body.move_and_collide((to - from) / 50.0)
				if hit != null:
					blocked = true
					collider_name = str(hit.get_collider().get_path())
					contact = str(hit.get_position())
					normal = str(hit.get_normal())
					break
			var reached = body.global_position.distance_to(to) < 0.02
			var row = {"from":str(from), "to":str(to), "actual_start":str(actual_start), "actual_end":str(body.global_position), "body_size":str(envelope.shape.size), "blocked":blocked, "reached":reached, "collider":collider_name, "contact":contact, "normal":normal, "candidate_present":not baseline, "method":"scripted real-body sweep at Y5.8; no propulsion/control/whole-width guarantee"}
			if baseline: baseline_samples.append(row)
			else: sweep_samples.append(row)
			_check(not blocked and reached, ("baseline without candidate " if baseline else "actual ") + "bridge-mouth passage sample " + str(side) + (" reverse" if reverse else " forward"), row)

func _capture(label: String) -> void:
	session.interface.vitals.text = "岸肩诊断 · 未减面 · 微共面残片 · 非正式验收"
	await RenderingServer.frame_post_draw
	var path = output.path_join(label + ".png")
	var error = root.get_texture().get_image().save_png(path)
	_check(error == OK, "actual GPU viewport saved: " + label)
	shots.append({"id":label, "file":path, "sha256":FileAccess.get_sha256(path), "camera_size":session.camera.size,
		"camera_transform":str(session.camera.global_transform), "pilot":str(session.players[1].global_position),
		"draw_calls":Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
		"render_primitives":Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)})

func _force_transforms(node: Node) -> void:
	if node is Node3D: node.force_update_transform()
	for child in node.get_children(): _force_transforms(child)

func _production_geometry() -> Dictionary:
	var result: Dictionary = {}
	for node in session.world.get_children():
		if str(node.name).begins_with("Shore_") or node == session.world.art_traversal:
			var spatial = node as Node3D
			if spatial == null: continue
			var resources: Array = []
			for mesh: MeshInstance3D in spatial.find_children("*", "MeshInstance3D", true, false):
				resources.append([str(mesh.get_path()), mesh.mesh.get_instance_id(), str(mesh.transform)])
			result[str(spatial.name)] = {"instance":spatial.get_instance_id(), "transform":str(spatial.transform), "meshes":resources}
	return result

func _review_inputs() -> Dictionary:
	var result: Dictionary = {}
	for path in ShoreCapture.INPUTS + [SOURCE, "res://assets/v3/root_arch/f1_root_arch.glb", "res://scenes/v3/main.tscn",
		"res://scripts_tools/v3/capture_shore_p12_diagnostic.gd", "res://scripts_tools/v3/capture_assets.gd", "res://scripts_tools/v3/capture_shore.gd",
		"res://scripts/v2/flight_camera.gd", "res://scripts/v2/flight_body.gd", "res://scripts/v3/art/twin_traversal_structure.gd"]:
		result[path] = FileAccess.get_sha256(path)
	return result

func _check(ok: bool, label: String, detail: Dictionary = {}) -> void:
	checks.append({"name":label, "passed":ok, "detail":detail})
	if not ok: failures.append(label)

func _finish() -> void:
	if finished: return
	finished = true
	_check(_review_inputs() == input_hashes, "candidate, source scripts and production inputs unchanged before/after")
	var report = {"purpose":"Actual Compatibility viewport of a raw frozen GLB added only to this isolated QA process. Existing production bridge and shoreline retained.",
		"status":"diagnostic only, not art/gameplay/performance acceptance", "source":SOURCE, "expected_sha256":EXPECTED_SHA,
		"profile":profile_id, "placement":str(POSITION), "input_sha256":input_hashes, "checks":checks, "failures":failures,
		"shots":shots, "meshes":mesh_report, "default_game_camera_size":default_camera_size,
		"collision_mode":"visual only; no passage evidence" if visual_only else "full actual concave triangles; layer 1 plus isolated candidate-query bit",
		"collision_ready":collision_ready, "collision_bodies":collision_body_count, "support_samples":support_samples, "sweeps":sweep_samples,
		"paired_baseline_only":baseline_only, "baseline_sweeps":baseline_samples,
		"limits":["869522 triangles, deliberately not retopologized; frame counters are not performance acceptance.",
			"12 micro coplanar reports remain; independent pair-area sum 1.306336372408623e-9 square metres, not waived.",
			"Basic colors only; wide upper gray band and short root-base rims still require visual decisions.",
			"Six scripted Y5.8 flight-body samples, if executed, do not prove every route/height or human comfort."],
		"elapsed_seconds":(Time.get_ticks_usec() - started_usec) / 1000000.0,
		"adapter":RenderingServer.get_video_adapter_name(), "display":DisplayServer.get_name(), "viewport":str(root.size)}
	var file = FileAccess.open(output.path_join("capture.json"), FileAccess.WRITE)
	var write_ok = file != null
	if write_ok:
		file.store_string(JSON.stringify(report, "\t"))
		file.flush()
		write_ok = file.get_error() == OK
		file.close()
	print("SHORE_P12_DIAGNOSTIC ", JSON.stringify({"checks":checks.size(), "failures":failures, "shots":shots.size(), "collision_ready":collision_ready, "output":output, "report_written":write_ok}))
	if is_instance_valid(candidate) and not candidate.is_inside_tree(): candidate.free()
	if is_instance_valid(session):
		session.network.close()
		session.queue_free()
	await process_frame
	quit(0 if failures.is_empty() and write_ok else 1)
