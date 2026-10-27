extends SceneTree

var failures=[]
var world

func _initialize() -> void:call_deferred("run")

func check(condition: bool,description: String) -> void:
	print("RUNTIME_", "PASS " if condition else "FAIL ",description)
	if not condition:failures.append(description)

func run() -> void:
	world=load("res://scenes/main.tscn").instantiate()
	world.profile=PilotProfile.new("user://runtime_qa.json")
	root.add_child(world)
	await process_frame
	world.auto_test=true
	world.profile.data=world.profile.defaults()
	check(world.ui.current_screen=="hangar","startup opens hangar")
	world.ui.show_help();check(world.ui.current_screen=="help","manual opens")
	world.show_hangar()
	world.ui.show_settings();check(world.ui.current_screen=="settings","settings opens")
	world.ui._return_from_settings();check(world.ui.current_screen=="hangar","settings returns to hangar")
	world.start_mission(0)
	for i in range(10):await physics_frame
	check(world.in_flight and world.ui.current_screen=="hud","launch creates HUD and flight")
	var before=world.mission_time
	world.pause_game("QA")
	for i in range(10):await process_frame
	check(paused and world.mission_time==before,"pause stops simulation clock")
	world.ui.show_settings();world.ui._return_from_settings()
	check(paused and world.ui.current_screen=="pause","in-flight settings returns to pause")
	world.resume_game()
	for i in range(10):await physics_frame
	check(not paused and world.mission_time>before,"resume continues simulation")
	world._notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	check(not paused,"test driver focus is isolated")
	world.auto_test=false
	world._notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	check(paused and world.ui.current_screen=="pause","real focus loss pauses")
	world.auto_test=true
	world.start_mission(0)
	check(world.player.health==130 and world.mission_time==0 and not paused,"restart resets health and mission state")
	world.player.take_damage(1000)
	check(not world.in_flight and paused and world.ui.current_screen=="results","death presents result")
	check(world.profile.data.parts==0 and world.profile.data.completed.is_empty(),"failed mission grants no currency or unlock")
	world.show_hangar()
	check(not paused and world.ui.current_screen=="hangar","return after death restores hangar")
	world.start_practice()
	check(world.practice_mode and world.enemies.is_empty() and world.in_flight,"practice is accessible with no enemies")
	world.player.take_damage(1000)
	check(world.player.health==world.player.maximum_health,"practice cannot cause a damage failure")
	world.restart_mission()
	check(world.practice_mode and world.enemies.is_empty(),"practice restart remains non-combat")
	world.finish_mission(true)
	check(world.profile.data.parts==0 and world.profile.data.completed.is_empty() and world.profile.data.records.is_empty(),"practice cannot grant campaign progress or records")
	world.show_hangar();world.start_mission(0)
	check(not world.practice_mode and world.enemies.size()>0,"campaign enemies return after practice")
	check(FileAccess.file_exists("res://assets/licenses/Godot-runtime.txt"), "runtime license is present without rewriting source files")
	print("RUNTIME_CHECKS_OK" if failures.is_empty() else "RUNTIME_CHECKS_FAILED")
	quit(0 if failures.is_empty() else 1)
