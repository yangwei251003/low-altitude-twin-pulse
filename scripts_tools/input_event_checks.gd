extends SceneTree

func _initialize() -> void:call_deferred("run")

func key(code: int,pressed: bool) -> void:
	var event=InputEventKey.new();event.physical_keycode=code;event.pressed=pressed
	Input.parse_input_event(event)

func run() -> void:
	var world=load("res://scenes/main.tscn").instantiate()
	world.profile=PilotProfile.new("user://input_qa.json")
	root.add_child(world)
	await process_frame
	world.auto_test=true
	world.start_mission(0)
	key(KEY_E,true)
	for i in range(4):await process_frame
	key(KEY_E,false)
	print("INPUT_LAYER ",world.router.layer)
	var start=world.player.position
	key(KEY_W,true)
	for i in range(60):await physics_frame
	key(KEY_W,false)
	print("INPUT_MOVEMENT ",world.player.position.distance_to(start))
	key(KEY_ESCAPE,true)
	for i in range(4):await process_frame
	key(KEY_ESCAPE,false)
	print("INPUT_PAUSE ",paused)
	var valid=world.router.layer==1 and world.player.position.distance_to(start)>1 and paused
	world.resume_game();world.router.layer=0
	var injected=InputEventKey.new();injected.physical_keycode=KEY_PAUSE;injected.keycode=KEY_E;injected.pressed=true
	Input.parse_input_event(injected)
	for i in range(4):await process_frame
	print("VIRTUAL_KEY_LAYER ",world.router.layer)
	valid=valid and world.router.layer==1
	injected.pressed=false;Input.parse_input_event(injected)
	key(KEY_W,true)
	for i in range(3):await process_frame
	world.pause_game("input cleanup")
	world.resume_game()
	var clean=world.router.movement()==Vector2.ZERO and not Input.is_action_pressed("flight_forward")
	print("INPUT_RESUME_CLEAN ",clean)
	valid=valid and clean
	injected=InputEventKey.new();injected.physical_keycode=KEY_PAUSE;injected.keycode=KEY_F12;injected.pressed=true
	Input.parse_input_event(injected)
	var released=injected.duplicate();released.pressed=false;Input.parse_input_event(released)
	Input.flush_buffered_events()
	var fast_capture=Input.is_action_just_pressed("flight_capture")
	print("INPUT_FAST_CAPTURE ",fast_capture)
	valid=valid and fast_capture
	print("INPUT_EVENT_CHECKS_OK" if valid else "INPUT_EVENT_CHECKS_FAIL")
	quit(0 if valid else 1)
