extends SceneTree

const Profile = preload("res://scripts/pilot_profile.gd")
const Router = preload("res://scripts/input_router.gd")
var checks = 0
var failures = []
var sandbox: String

func _initialize() -> void:
	sandbox = "user://qa_v2/legacy_" + Crypto.new().generate_random_bytes(8).hex_encode()
	DirAccess.make_dir_recursive_absolute(sandbox)
	call_deferred("run")

func check(condition: bool, description: String) -> void:
	checks += 1
	print("LEGACY_SAFETY_", "PASS " if condition else "FAIL ", description)
	if not condition:failures.append(description)

func write_json(path: String, value) -> void:
	var file = FileAccess.open(path, FileAccess.WRITE)
	file.store_string(JSON.stringify(value))
	file.close()

func run() -> void:
	var path = sandbox.path_join("pilot.json")
	var fixture = Profile.new(path).defaults()
	fixture.parts = 321
	write_json(path + ".bak", fixture)
	var profile = Profile.new(path)
	profile.load_profile()
	check(profile.data.parts == 321, "S01 missing primary recovers valid backup")
	write_json(path, "broken primary")
	profile = Profile.new(path)
	profile.load_profile()
	check(profile.data.parts == 321 and profile.save_profile(), "S03 backup recovery can be saved")
	var backup = JSON.parse_string(FileAccess.get_file_as_string(path + ".bak"))
	check(backup is Dictionary and backup.parts == 321, "S03 recovered save does not overwrite valid backup with corrupt primary")
	for value in [{"damage":0}, 2, [], "wrong", null, {"time":-1,"damage":0,"collisions":0}]:
		var record_path = sandbox.path_join("record_" + str(checks) + ".json")
		fixture = Profile.new(record_path).defaults()
		fixture.records = {"0:0:false:pulse:stable:shield":value}
		write_json(record_path, fixture)
		profile = Profile.new(record_path)
		profile.load_profile()
		check(profile.claim(0, "record", 12.0, 0, 0.0, 0, false) == 100 and profile.data.parts == 100, "S02 malformed record does not interrupt award " + str(checks))
		var reload = Profile.new(record_path)
		reload.load_profile()
		check(reload.data.parts == 100 and reload.best_time(0,0,false) == 12.0, "S02 award and repaired score persist")
	var router = Router.new()
	root.add_child(router)
	router.apply_config({"center":{"0":{}, "1":NAN}, "min":{"0":"bad"}, "max":{"0":[]}, "deadzone":NAN, "axis_x":INF})
	check(router.config.center.is_empty() and router.config.min.is_empty() and router.config.max.is_empty() and is_finite(router.config.deadzone), "nested calibration and nonfinite values are rejected")
	router.rebind("fire", {"type":"key", "code":KEY_K})
	var mouse = false
	var joy = false
	var keyboard = false
	for event in InputMap.action_get_events("flight_fire"):
		if event is InputEventMouseButton:mouse = true
		if event is InputEventJoypadButton:joy = true
		if event is InputEventKey and event.physical_keycode == KEY_K:keyboard = true
	check(mouse and joy and keyboard, "keyboard rebind preserves mouse and gamepad")
	router.rebind("fire", {"type":"joy", "code":JOY_BUTTON_RIGHT_SHOULDER})
	check(router.config.device_bindings.key.fire == KEY_K and router.config.device_bindings.joy.fire == JOY_BUTTON_RIGHT_SHOULDER, "device binding layers persist independently")
	var saved = router.config.duplicate(true)
	router.queue_free()
	await process_frame
	router = Router.new()
	root.add_child(router)
	router.apply_config(saved)
	keyboard = false
	joy = false
	for event in InputMap.action_get_events("flight_fire"):
		if event is InputEventKey and event.physical_keycode == KEY_K:keyboard = true
		if event is InputEventJoypadButton and event.button_index == JOY_BUTTON_RIGHT_SHOULDER:joy = true
	check(keyboard and joy, "both device remaps survive reload")
	router.queue_free()
	await process_frame
	var summary = {"suite":"legacy_safety", "checks":checks, "failures":failures, "ok":failures.is_empty(), "sandbox":sandbox}
	write_json(sandbox.path_join("summary.json"), summary)
	print("LEGACY_SAFETY_SUMMARY ", JSON.stringify(summary))
	quit(0 if failures.is_empty() else 1)
