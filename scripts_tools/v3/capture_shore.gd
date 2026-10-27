extends "res://scripts_tools/v3/capture_assets.gd"
## Actual rendered geometry study; fixed fixture/camera poses, not free play.
const INPUTS := [
	"res://data/v3/terrain/f1_shore_layout.json",
	"res://scripts/v3/world/twin_shore_layout.gd",
	"res://scripts/v3/twin_test_world.gd",
	"res://scripts/v3/twin_session.gd",
	"res://scripts/v3/art/twin_ground_surface.gd",
	"res://assets/v3/materials/twin_ground_study.gdshader",
	"res://assets/v3/materials/twin_water_study.gdshader",
	"res://assets/v3/materials/twin_shore_profile.gdshaderinc",
	"res://assets/v3/root_buttress/root_buttress_h10.glb",
	"res://assets/v3/root_buttress/root_buttress_h12.glb",
	"res://assets/v3/root_buttress/root_buttress_h17.glb",
	"res://assets/v3/root_buttress/root_buttress_h3.glb",
	"res://assets/v3/crown/parasitic_crown.glb"
]

func _run() -> void:
	var safe := false
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--qa-profile=qa_visual_"): safe = true
		if arg.begins_with("--capture-output="): output = arg.trim_prefix("--capture-output=")
	if not safe or DisplayServer.get_name() == "headless" or output.is_empty():
		quit(2)
		return
	if DirAccess.make_dir_recursive_absolute(output) != OK:
		quit(2)
		return
	var before := _hashes()
	session = load("res://scenes/v3/main.tscn").instantiate()
	root.add_child(session)
	if not session.start_flight("solo") or not session._load_region("F1"):
		quit(1)
		return
	session.set_physics_process(false)
	session.set_process(false)
	session.inputs.set_physics_process(false)
	session.inputs.set_process(false)
	await _pose(Vector3(0, 6, 18), 42)
	await _capture("01-south-curve-and-temple")
	await _pose(Vector3(0, 6, -4), 42)
	await _capture("02-root-arch-and-shore-approaches")
	await _pose(Vector3(10, 12, -24), 48)
	await _capture("03-north-basin-and-boss-foundations")
	await _pose(Vector3(-6, 2, 36), 22)
	await _capture("04-wet-bank-and-open-water")
	if not session._load_region("I1"):
		quit(1)
		return
	await _pose(Vector3(0, 6, 18), 42)
	await _capture("05-industrial-material-isolation")
	var after := _hashes()
	var valid := before == after
	var report := {"purpose":"Actual Compatibility viewport of the replaceable curved-shore graybox. Scripted static camera/pilot placement; no human play or performance claim.",
		"limits":["P2 rock assets remain visually rejected", "Graybox slopes and foundations are not finished Blender art", "No shoreline foam around individual foundations yet"],
		"input_sha256":before, "inputs_unchanged":valid, "shots":shots,
		"driver":RenderingServer.get_video_adapter_name(), "viewport":str(root.size)}
	var file := FileAccess.open(output.path_join("capture.json"), FileAccess.WRITE)
	if file == null:
		quit(1)
		return
	file.store_string(JSON.stringify(report, "\t"))
	file.flush()
	var error := file.get_error()
	file.close()
	session.network.close()
	session.queue_free()
	await process_frame
	print("V3_SHORE_CAPTURE ", JSON.stringify({"output":output, "shots":shots.size(), "inputs_unchanged":valid, "write_error":error}))
	quit(0 if valid and error == OK else 1)

func _hashes() -> Dictionary:
	var result := {}
	for path in INPUTS: result[path] = FileAccess.get_sha256(path)
	return result
