extends SceneTree

const Profiles = preload("res://scripts/v2/profile_catalog.gd")
const Pilot = preload("res://scripts/v2/pilot_input.gd")
var failures: Array[String] = []
var checks = 0
var fixture_root = ""

func _initialize() -> void:
	call_deferred("run")

func check(condition: bool, label: String) -> void:
	checks += 1
	if not condition: failures.append(label)
	print("V22_PROFILE_", "PASS " if condition else "FAIL ", label)

func hashes(directory: String) -> Dictionary:
	var result = {}
	var access = DirAccess.open(directory)
	if access == null: return result
	access.include_hidden = true
	for name in access.get_files(): result[name] = FileAccess.get_sha256(directory.path_join(name))
	return result

func key_codes(action: String) -> Array:
	var result = []
	for event in InputMap.action_get_events("flight_" + action):
		if event is InputEventKey: result.append(event.physical_keycode)
	return result

func joy_codes(action: String) -> Array:
	var result = []
	for event in InputMap.action_get_events("flight_" + action):
		if event is InputEventJoypadButton: result.append(event.button_index)
	return result

func has_mouse_fire() -> bool:
	for event in InputMap.action_get_events("flight_fire"):
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT: return true
	return false

func run() -> void:
	fixture_root = "user://qa_v22/profile_isolation_" + Crypto.new().generate_random_bytes(8).hex_encode()
	var old = SaveRepositoryV2.new(fixture_root.path_join("legacy"))
	check(old.load_profile(), "create isolated legacy fixture")
	check(old.commit({"id":"old:first","parts_delta":321,"append":{"campaign.completed_missions":["M01"]}}).ok, "legacy fixture first generation")
	check(old.commit({"id":"old:second","parts_delta":7}).ok, "legacy fixture has two recoverable generations")
	var old_path = ProjectSettings.globalize_path(old.root_path)
	var old_hashes = hashes(old_path)
	for point in ["after_stage_created", "after_copy", "before_publish"]:
		var destination_root = fixture_root.path_join(point)
		var catalog = Profiles.new(destination_root, old_path)
		catalog.migration_failure_point = point
		catalog.initialize()
		check(catalog.migration_blocked, point + ": failure blocks default initialization")
		check(not DirAccess.dir_exists_absolute(destination_root.path_join("default")), point + ": incomplete default is never published")
		check(DirAccess.dir_exists_absolute(catalog.migration_staging_path), point + ": staging files are preserved")
		var blocked = catalog.open_profile("default")
		check(blocked.read_only and blocked._load_failed and not blocked.commit({"id":"must-not-write"}).ok, point + ": open_profile contract blocks writes")
		check(not catalog.select("default") and catalog.select("free_01"), point + ": sandbox remains usable during blocked import")
		check(hashes(old_path) == old_hashes, point + ": source hashes remain unchanged")
		# A fresh process must retry from the source, never depend on in-memory state.
		var retry = Profiles.new(destination_root, old_path)
		retry.initialize()
		var imported = retry.open_profile("default")
		check(not retry.migration_blocked and not imported.read_only and not imported._load_failed, point + ": restart completes migration")
		check(imported.data.wallet.parts == 328 and imported.data.profile_id == old.data.profile_id and "M01" in imported.data.campaign.completed_missions, point + ": retry preserves actual legacy progress")
		check(FileAccess.file_exists(destination_root.path_join("default/v21_import.json")), point + ": verified receipt is published with profile")

	var empty_root = fixture_root.path_join("empty_previous_attempt")
	check(DirAccess.make_dir_recursive_absolute(empty_root.path_join("default")) == OK, "simulate empty target left by old importer")
	var empty_retry = Profiles.new(empty_root, old_path)
	empty_retry.initialize()
	check(not empty_retry.migration_blocked and empty_retry.open_profile("default").data.wallet.parts == 328, "empty legacy target does not suppress retry")
	var preserved_empty = false
	for directory in DirAccess.get_directories_at(empty_root):
		if directory.begins_with("default.empty-"): preserved_empty = true
	check(preserved_empty, "old empty target is preserved rather than deleted")

	var existing_root = fixture_root.path_join("existing_player")
	var existing = SaveRepositoryV2.new(existing_root.path_join("default"))
	existing.load_profile()
	check(existing.commit({"id":"new:progress","parts_delta":900,"append":{"campaign.completed_missions":["M07"]}}).ok, "create existing V2.2 progression")
	var existing_id = existing.data.profile_id
	var existing_catalog = Profiles.new(existing_root, old_path)
	existing_catalog.initialize()
	var retained = existing_catalog.open_profile("default")
	check(retained.data.profile_id == existing_id and retained.data.wallet.parts == 900 and "M07" in retained.data.campaign.completed_missions, "valid existing target always wins over legacy source")
	check(not FileAccess.file_exists(existing_root.path_join("default/v21_import.json")), "existing player is not mislabeled as imported")

	var broken_root = fixture_root.path_join("broken_existing")
	DirAccess.make_dir_recursive_absolute(broken_root.path_join("default"))
	var broken_path = broken_root.path_join("default/profile_g000001.json")
	var broken_file = FileAccess.open(broken_path, FileAccess.WRITE)
	broken_file.store_string("incomplete previous save"); broken_file.close()
	var broken_hash = FileAccess.get_sha256(broken_path)
	var broken_catalog = Profiles.new(broken_root, old_path)
	broken_catalog.initialize()
	check(broken_catalog.migration_blocked and broken_catalog.open_profile("default").read_only, "unverified nonempty target blocks automatic replacement")
	check(FileAccess.get_sha256(broken_path) == broken_hash, "unverified target bytes are preserved for recovery")
	check(broken_catalog.open_profile("default")._generation_files().size() == 1, "blocked target does not acquire a fresh default generation")

	var broken_source = fixture_root.path_join("broken_source")
	DirAccess.make_dir_recursive_absolute(broken_source)
	var bad_source_file = FileAccess.open(broken_source.path_join("profile_g000001.json"), FileAccess.WRITE)
	bad_source_file.store_string("corrupt source"); bad_source_file.close()
	var invalid_catalog = Profiles.new(fixture_root.path_join("invalid_import"), ProjectSettings.globalize_path(broken_source))
	invalid_catalog.initialize()
	check(invalid_catalog.migration_blocked and not DirAccess.dir_exists_absolute(invalid_catalog.base_path.path_join("default")), "invalid source does not silently create a replacement normal profile")
	var clean_catalog = Profiles.new(fixture_root.path_join("brand_new"), ProjectSettings.globalize_path(fixture_root.path_join("missing_source")))
	clean_catalog.initialize()
	check(not clean_catalog.migration_blocked and clean_catalog.open_profile("default").data.generation > 0, "first-time user without legacy data can create a normal profile")
	check(hashes(old_path) == old_hashes, "all migration scenarios leave source bytes unchanged")

	var input = Pilot.new()
	root.add_child(input)
	var device_before = input.legacy.device
	var profile_a = {"layout_version":2,"axis_x":4,"axis_y":5,"axis_yaw":2,"axis_vertical":3,"axis_height":6,
		"invert_x":true,"invert_y":true,"invert_yaw":true,"invert_vertical":true,"deadzone":0.28,
		"center":{"2":0.12},"min":{"2":-0.8},"max":{"2":0.95},
		"device_bindings":{"key":{"yaw_left":KEY_V,"forward":KEY_I},"joy":{"fire":JOY_BUTTON_B}}}
	var original_a = profile_a.duplicate(true)
	input.configure_input(profile_a)
	check(input.legacy.config.axis_x == 4 and input.legacy.config.invert_vertical and is_equal_approx(input.legacy.config.deadzone, 0.28), "profile A custom axes/flags/deadzone apply")
	check(key_codes("yaw_left") == [KEY_V] and key_codes("forward") == [KEY_I] and joy_codes("fire") == [JOY_BUTTON_B], "profile A custom keyboard and joy bindings apply")
	check(is_equal_approx(input.legacy.config.center["2"], 0.12) and is_equal_approx(input.legacy.config.min["2"], -0.8), "profile A retains its own calibration")
	input.legacy.calibrating = true
	input.legacy.calibrate_time = 3.0
	input.legacy.samples = 50
	input.legacy.allow_input = false
	input.configure_input({})
	check(input.legacy.config.axis_x == 2 and input.legacy.config.axis_y == 3 and input.legacy.config.axis_yaw == 0 and input.legacy.config.axis_vertical == 1 and input.legacy.config.axis_height == -1, "default profile restores complete Mode 2 axis layout")
	check(not input.legacy.config.invert_x and not input.legacy.config.invert_y and not input.legacy.config.invert_yaw and not input.legacy.config.invert_vertical and is_equal_approx(input.legacy.config.deadzone, 0.16), "default profile does not inherit flags or deadzone")
	check(input.legacy.config.center.is_empty() and input.legacy.config.min.is_empty() and input.legacy.config.max.is_empty(), "default profile does not inherit calibration")
	check(input.legacy.config.bindings.is_empty() and input.legacy.config.device_bindings.key.is_empty() and input.legacy.config.device_bindings.joy.is_empty(), "default profile does not retain another pilot's binding records")
	check(key_codes("yaw_left") == [KEY_Z] and key_codes("forward") == [KEY_W,KEY_UP] and joy_codes("fire") == [JOY_BUTTON_X], "default InputMap keys and controller buttons are restored")
	check(has_mouse_fire(), "mouse fire default survives profile switching")
	check(input.legacy.device == device_before and not input.legacy.allow_input, "profile switch preserves actual connected device and UI input gate")
	check(not input.legacy.calibrating and input.legacy.samples == 0 and input.legacy.calibrate_time == 0.0, "unfinished calibration cannot write into the next profile")
	input.configure_input(profile_a)
	check(input.legacy.config.axis_x == 4 and key_codes("yaw_left") == [KEY_V] and is_equal_approx(input.legacy.config.center["2"], 0.12), "switching back restores A from its own saved values")
	check(profile_a == original_a, "configure_input never mutates the caller's saved dictionary")
	input.configure_input({"layout_version":2,"deadzone":0.20})
	check(input.legacy.config.axis_x == 2 and input.legacy.config.axis_y == 3 and input.legacy.config.axis_yaw == 0 and input.legacy.config.axis_vertical == 1, "partial current-layout config inherits V2 Mode 2 defaults")
	input.configure_input({"axis_x":0,"axis_y":1,"center":{"0":0.1},"bindings":{"yaw_right":{"type":"key","code":KEY_B}}})
	check(input.legacy.config.axis_x == 2 and input.legacy.config.axis_y == 3 and is_equal_approx(input.legacy.config.center["0"], 0.1) and key_codes("yaw_right") == [KEY_B], "old layout upgrade preserves that profile's calibration and bindings")
	for index in range(3): input.configure_input({})
	check(InputMap.action_get_events("flight_fire").size() == 3 and key_codes("forward").size() == 2, "repeated switching does not accumulate duplicate input events")
	input.queue_free()
	await process_frame
	print("V22_PROFILE_SUMMARY ", JSON.stringify({"checks":checks,"failures":failures,"ok":failures.is_empty(),"fixture_root":fixture_root,"scope":"isolated migration failure/retry and input mapping tests; no real player saves or physical device input"}))
	quit(0 if failures.is_empty() else 1)
