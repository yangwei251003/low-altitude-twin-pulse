extends "res://scripts_tools/v3/capture_assets.gd"
## Review a material-only candidate in the actual game, without changing shipped assets.
## Imported render meshes replace only equivalent west-host meshes in this QA process.
const CANDIDATE = "res://assets/v3/candidates/root_buttress_h10_p3/root_buttress_h10_p3.glb"
const CANDIDATE_SHA = "b751731bc509edbf915d1df61241197ffd8e701e6e5426a298e0672310fe7049"
const BASELINE = "res://assets/v3/root_buttress/root_buttress_h10.glb"
const BASELINE_SHA = "ceaae98c56aa8fa3517d43a11708c352e8741fa801d78a24eba87871a8d29d53"
const WEST = "F1:crown_host_west"
var checks: Array = []
var failures: Array = []

func _run() -> void:
	var safe = false
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--qa-profile=qa_visual_"): safe = true
		if arg.begins_with("--capture-output="): output = arg.trim_prefix("--capture-output=")
	if not safe or DisplayServer.get_name() == "headless" or output.is_empty():
		push_error("Candidate review requires rendered window, isolated visual profile and output")
		quit(2)
		return
	DirAccess.make_dir_recursive_absolute(output)
	_record(FileAccess.get_sha256(CANDIDATE) == CANDIDATE_SHA, "explicit candidate GLB identity")
	_record(FileAccess.get_sha256(BASELINE) == BASELINE_SHA, "frozen p2 baseline GLB identity")
	if not failures.is_empty():
		_finish()
		return
	session = load("res://scenes/v3/main.tscn").instantiate()
	root.add_child(session)
	session.start_flight("solo")
	session._load_region("F1")
	session.set_physics_process(false)
	session.set_process(false)
	session.inputs.set_physics_process(false)
	session.inputs.set_process(false)
	await physics_frame
	var arena = session.world.crown_arena
	var host: Node3D = arena.hosts[WEST]
	var candidate = (load(CANDIDATE) as PackedScene).instantiate() as Node3D
	root.add_child(candidate)
	candidate.hide()
	var render_pairs: Array = []
	var source_meshes = candidate.find_children("*", "MeshInstance3D", true, false)
	var runtime_meshes = host.find_children("*", "MeshInstance3D", true, false)
	_record(source_meshes.size() == 5 and runtime_meshes.size() == 5, "five imported meshes in both assets")
	for source: MeshInstance3D in source_meshes:
		var target = host.find_child(str(source.name), true, false) as MeshInstance3D
		if target == null:
			_record(false, "missing runtime mesh " + str(source.name))
			continue
		var source_transform = candidate.global_transform.affine_inverse() * source.global_transform
		var target_transform = host.global_transform.affine_inverse() * target.global_transform
		_record(source_transform.is_equal_approx(target_transform), "unchanged local transform " + str(source.name))
		_record(_triangle_keys(source.mesh) == _triangle_keys(target.mesh), "imported triangle equivalence within 1mm grid " + str(source.name))
		var overrides: Array = []
		for surface in range(target.get_surface_override_material_count()): overrides.append(target.get_surface_override_material(surface))
		render_pairs.append({"target":target, "source":source, "original_mesh":target.mesh, "overrides":overrides})
	for anchor in ["GroundOrigin", "BodyPerch", "HostTarget", "LowerShelf"]:
		var source = candidate.find_child(anchor, true, false) as Node3D
		var target = host.find_child(anchor, true, false) as Node3D
		_record(source != null and target != null and candidate.to_local(source.global_position).distance_to(host.to_local(target.global_position)) < 0.0001, "unchanged anchor " + anchor)
	if not failures.is_empty():
		candidate.queue_free()
		_finish()
		return
	await _place(arena.host_position(WEST) + Vector3(0, 0, 2.5))
	_record(session.crown.start(false), "production encounter starts")
	await _pair(render_pairs, Vector3(8, 13, -23), 34, "01-default")
	await _pair(render_pairs, Vector3(1, 12, -21), 18, "02-near")
	await _open_core()
	await _pair(render_pairs, Vector3(1, 13, -22), 18, "03-core-open")
	_record(FileAccess.get_sha256(BASELINE) == BASELINE_SHA and FileAccess.get_sha256(CANDIDATE) == CANDIDATE_SHA, "baseline and candidate files unchanged by review")
	candidate.queue_free()
	_finish()

func _pair(pairs: Array, at: Vector3, zoom: float, label: String) -> void:
	_swap(pairs, false)
	await _pose(at, zoom)
	var authority_before: Dictionary = session.crown.encounter.get_state().duplicate(true)
	await _capture(label + "-p2-baseline")
	_swap(pairs, true)
	await _pose(at, zoom)
	await _capture(label + "-p3-candidate")
	_record(session.crown.encounter.get_state() == authority_before, label + " pair retains the same authoritative encounter and HUD state")

func _swap(pairs: Array, candidate: bool) -> void:
	# This local screenshot process is the only place the material-only swap exists.
	var arena = session.world.crown_arena
	for pair in pairs:
		var target: MeshInstance3D = pair.target
		target.mesh = pair.source.mesh if candidate else pair.original_mesh
		for surface in range(target.get_surface_override_material_count()):
			target.set_surface_override_material(surface, null if candidate else pair.overrides[surface])
		if str(target.name).contains("SapKnot"):
			var glow = target.get_active_material(0).duplicate()
			target.set_surface_override_material(0, glow)
			arena._glows[WEST] = glow
	arena.apply_view(arena.last_view, arena.defeated)

func _triangle_keys(mesh: Mesh) -> Array[String]:
	var faces = mesh.get_faces()
	var triangles: Array[String] = []
	for index in range(0, faces.size(), 3):
		var points: Array[String] = []
		for corner in range(3):
			var vertex: Vector3 = faces[index + corner]
			points.append("%d,%d,%d" % [roundi(vertex.x * 1000), roundi(vertex.y * 1000), roundi(vertex.z * 1000)])
		points.sort()
		triangles.append(";".join(points))
	triangles.sort()
	return triangles

func _open_core() -> void:
	await _place(session.world.crown_arena.host_position(WEST) + Vector3(0, 0, 2.5))
	for ability in ["light", "growth"]:
		session.cooldowns[1] = 0.0
		session._action_received(1, "ability", {"ability":ability, "target_id":WEST})
	_record(session.crown.encounter.get_state().core_open, "production light-growth opens core")
	session.locks[1] = "boss:crown_core"

func _record(ok: bool, label: String) -> void:
	checks.append({"passed":ok, "name":label})
	if not ok:
		failures.append(label)
		push_error(label)

func _finish() -> void:
	var file = FileAccess.open(output.path_join("capture.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify({"purpose":"actual Compatibility game camera and lighting; material-only candidate imported render meshes with verified equivalent geometry; production collision/state retained; scripted placement and frozen updates, not human play or performance acceptance", "baseline":BASELINE, "baseline_sha256":BASELINE_SHA, "candidate":CANDIDATE, "candidate_sha256":CANDIDATE_SHA, "checks":checks, "failures":failures, "shots":shots, "driver":RenderingServer.get_video_adapter_name(), "viewport":str(root.size)}, "\t"))
	file.close()
	print("V3_ROOTSTONE_CANDIDATE ", JSON.stringify({"shots":shots.size(), "checks":checks.size(), "failures":failures}))
	if is_instance_valid(session):
		session.network.close()
		session.queue_free()
	quit(0 if failures.is_empty() else 1)
