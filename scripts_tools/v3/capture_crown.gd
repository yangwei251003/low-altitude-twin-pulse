extends "res://scripts_tools/v3/capture_assets.gd"
## Rendered asset inspection. Fixture placement and frozen inputs are disclosed;
## ability, health, migration and warnings use the production host adapter.
const WEST = "F1:crown_host_west"
const CORE = "boss:crown_core"
var failures: Array = []
var stages: Array = []

func _run() -> void:
	var safe = false
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--qa-profile=qa_visual_"): safe = true
		if arg.begins_with("--capture-output="): output = arg.trim_prefix("--capture-output=")
	if not safe or DisplayServer.get_name() == "headless" or output.is_empty():
		push_error("Crown capture needs a rendered window, isolated qa_visual profile and output")
		quit(2)
		return
	DirAccess.make_dir_recursive_absolute(output)
	session = load("res://scenes/v3/main.tscn").instantiate()
	root.add_child(session)
	session.start_flight("solo")
	session._load_region("F1")
	session.set_physics_process(false)
	session.set_process(false)
	session.inputs.set_physics_process(false)
	session.inputs.set_process(false)
	await physics_frame
	if not session.crown.ready():
		push_error("Crown capture requires the real six terrain modules and Crown GLB")
		quit(1)
		return
	var arena = session.world.crown_arena
	await _pose(Vector3(8, 13, -23), 26)
	await _capture("01-crown-closed-default-camera")
	await _pose(Vector3(8, 13, -23), 48)
	await _capture("02-six-host-and-landing-rocks-wide")
	await _pose(Vector3(1, 12, -21), 18)
	await _capture("03-west-host-material-and-height")
	await _place(arena.host_position(WEST) + Vector3(0, 0, 2.5))
	_record(session.crown.start(false), "production noncampaign Crown starts")
	_use("light")
	_use("growth")
	_record(session.crown.encounter.get_state().core_open, "real light-growth opens plates")
	await _pose(Vector3(1, 13, -22), 18)
	session.locks[1] = CORE
	session._refresh_interface()
	await _capture("04-real-light-growth-core-open")
	# Retry preserves normal persistent world state and returns pilot to the entry.
	session.crown.retry()
	await _place(arena.host_position(WEST) + Vector3(0, 0, 2.5))
	_use("heat")
	_use("heat")
	var requested: Dictionary = session.crown.encounter.get_state()
	_record(requested.mode == "migration_warning" and requested.movement.get("approved", false), "real heat requests clear ejection")
	await _pose(Vector3(-4, 11, -22), 32)
	await _capture("05-burning-host-warning")
	await _advance(3.1)
	var fallen: Dictionary = session.crown.encounter.get_state()
	_record(fallen.mode == "fallen", "complete articulated model reaches low landing rock")
	await _pose(Vector3(-8, 7, -17), 23)
	await _capture("06-fallen-crown-and-burnt-host")
	# Inspect the production annular/cylinder warning, keeping its actual bounds.
	session.crown.retry()
	await _place(arena.host_position(WEST) + Vector3(0, 0, 2.5))
	await _advance(3.1)
	await _pose(Vector3(0, 11, -22), 32)
	await _capture("07-first-height-dependent-attack-warning")
	await _pose(Vector3(21, 14, -12), 26)
	await _capture("08-east-host-and-clear-approach")
	# Keep real terrain collision; fade only the registered local visual instances.
	await _pose(Vector3(-4, 5, -29), 26)
	_record(session.terrain_visibility.occluded, "actual rear low route selects local terrain fade")
	await _capture("09-local-occlusion-terrain-fade")
	await _pose(Vector3(7, 15, -16), 26)
	_record(not session.terrain_visibility.occluded, "clear flight route restores terrain materials")
	await _capture("10-terrain-restored-on-clear-route")
	session.crown.retry()
	await _pose(Vector3(3, 27, -21), 26)
	await _advance(10.0)
	var pollen: Dictionary = session.crown.encounter.get_state().attack
	_record(not pollen.is_empty() and not pollen.fired and pollen.shapes[0].kind == "cylinder", "27m route receives a fixed-height pollen warning")
	session._refresh_interface()
	await _capture("11-ceiling-route-pollen-warning")
	var health_before: float = session.players[1].health
	await _advance(2.0)
	_record(session.players[1].health < health_before, "pollen survives automatic migration deadline and damages stationary pilot")
	session._refresh_interface()
	await _capture("12-ceiling-route-pollen-active")
	var hashes: Dictionary = {"crown":FileAccess.get_sha256("res://assets/v3/crown/parasitic_crown.glb")}
	for height in [10, 17, 12, 3]: hashes[str(height)] = FileAccess.get_sha256("res://assets/v3/root_buttress/root_buttress_h%d.glb" % height)
	var file = FileAccess.open(output.path_join("capture.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify({"purpose":"actual Compatibility renderer, imported GLB and production host abilities/migration; scripted pilot/camera placement and frozen normal updates; not human play, story acceptance or performance evidence", "asset_sha256":hashes, "stages":stages, "failures":failures, "shots":shots, "driver":RenderingServer.get_video_adapter_name(), "viewport":str(root.size)}, "\t"))
	file.close()
	print("V3_CROWN_CAPTURE ", JSON.stringify({"output":output, "shots":shots.size(), "failures":failures}))
	session.network.close()
	session.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)

func _record(ok: bool, label: String) -> void:
	stages.append({"name":label, "passed":ok})
	if not ok: failures.append(label)

func _pose(at: Vector3, zoom: float) -> void:
	await super._pose(at, zoom)
	for frame in range(60):
		session._update_terrain_visibility(session.players[1], 1.0 / 60.0)
		await process_frame

func _use(ability: String) -> void:
	session.cooldowns[1] = 0.0
	session._action_received(1, "ability", {"ability":ability, "target_id":WEST})

func _advance(seconds: float) -> void:
	var remaining = seconds
	while remaining > 0.000001:
		var step = minf(remaining, 0.1)
		session.crown.advance(step)
		remaining -= step
	await physics_frame
	await physics_frame
