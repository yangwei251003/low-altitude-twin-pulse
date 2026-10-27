extends GutTest

func test_malformed_optional_settings_do_not_break_campaign() -> void:
	var path="user://qa_v2/gut_settings_"+Crypto.new().generate_random_bytes(8).hex_encode()+"/profile.json"
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var p=PilotProfile.new(path)
	p.data.settings={"difficulty":99,"camera":-5,"volume":2.0,"input":"bad","auto_fire":"bad"}
	assert_true(p.save_profile())
	var restored=PilotProfile.new(path);restored.load_profile()
	assert_eq(restored.data.settings.difficulty,2)
	assert_eq(restored.data.settings.camera,0)
	assert_eq(restored.data.settings.volume,1.0)
	assert_typeof(restored.data.settings.input,TYPE_DICTIONARY)
	assert_false(restored.data.settings.auto_fire)

func test_input_config_sanitizes_axes_and_partial_mapping() -> void:
	var router=FlightInput.new();add_child_autofree(router)
	router.apply_config({"axis_x":22,"axis_height":-99,"deadzone":1.0,"bindings":{"fire":{"type":"invalid"},"brake":22},"center":"bad"})
	assert_eq(router.config.axis_x,7)
	assert_eq(router.config.axis_height,-1)
	assert_eq(router.config.deadzone,.4)
	assert_eq(router.binding_label("fire"),"J")
	assert_typeof(router.config.center,TYPE_DICTIONARY)
