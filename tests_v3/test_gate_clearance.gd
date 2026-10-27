extends SceneTree
const Main = preload("res://scenes/v3/main.tscn")
var session
var checks: Array = []
var failures: Array = []

func _initialize() -> void: call_deferred("_run")
func check(ok: bool, label: String) -> void:
	checks.append({"label":label,"passed":ok})
	if not ok: failures.append(label)

func _run() -> void:
	var profile = ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--qa-profile="): profile = arg.trim_prefix("--qa-profile=")
	if not profile.begins_with("qa_clearance_") or DirAccess.dir_exists_absolute("user://profiles_v3/" + profile):
		quit(2)
		return
	session = Main.instantiate()
	root.add_child(session)
	session.start_flight("solo")
	session.set_process(false)
	session.set_physics_process(false)
	for region in ["I1", "F1"]:
		session._load_region(region)
		var body = session.players[1]
		body.freeze = true
		body.set_physics_process(false)
		body.configure(CatalogV2.resolve_build(CatalogV2.default_build("hx02")))
		body.global_position = Vector3(-24, 6.15, 23.25) if region == "I1" else Vector3(6, 5.4, 26)
		session.entities[region + ":relay"].charge = 100.0
		session.world.synchronize(session.entities, 2.0)
		await physics_frame
		await physics_frame
		check(is_equal_approx(session.world.gate_fraction, 1.0), region + " initially opens")
		session.entities[region + ":relay"].charge = 0.0
		session.entities[region + ":relay"].powered = false
		session.world.synchronize(session.entities, 2.0)
		check(session.world.gate_obstructed and is_equal_approx(session.world.gate_fraction, 1.0), region + " refuses closing into real wide drone")
		body.global_position = Vector3(-18, 3, 36)
		await physics_frame
		await physics_frame
		session.world.synchronize(session.entities, 2.0)
		check(not session.world.gate_obstructed and is_zero_approx(session.world.gate_fraction), region + " closes after pilot clears doorway")
		var crate = session.world.objects[region + ":crate"]
		crate.freeze = true
		crate.global_position = Vector3(-24, 6.15, 23.25) if region == "I1" else Vector3(6, 5.4, 26)
		session.entities[region + ":crate"].pinned = true
		session.entities[region + ":relay"].charge = 100.0
		session.world.synchronize(session.entities, 2.0)
		await physics_frame
		await physics_frame
		session.entities[region + ":relay"].charge = 0.0
		session.world.synchronize(session.entities, 2.0)
		check(session.world.gate_obstructed, region + " moving conductor also prevents crushing")
	var path = "res://artifacts/v3/gate-clearance-" + profile + ".json"
	var file = FileAccess.open(path, FileAccess.WRITE)
	file.store_string(JSON.stringify({"checks":checks, "failures":failures}, "\t"))
	file.close()
	print("GATE_CLEARANCE_RESULT ", JSON.stringify({"checks":checks.size(),"failures":failures,"report":path}))
	session.network.close()
	session.free()
	quit(0 if failures.is_empty() else 1)
