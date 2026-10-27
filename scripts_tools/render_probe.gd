extends SceneTree

var world
func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	world=load("res://scenes/main.tscn").instantiate()
	root.add_child(world)
	await process_frame
	# Isolated render inspection only; never treated as a playthrough or save test.
	world.auto_test=true
	world.profile=PilotProfile.new("user://render_probe_unused.json")
	world.profile.data.completed=[0,1]
	if "--menu" in OS.get_cmdline_user_args():
		world.ui.show_hangar()
		for i in range(90):await process_frame
		await world.capture_frame("hangar_v2")
		print("MENU_RENDER_OK fps=",Engine.get_frames_per_second())
		quit(0);return
	var index=0
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--map="):index=int(arg.trim_prefix("--map="))
	world.start_mission(index)
	world.player.enabled=false
	for enemy in world.enemies:enemy.set_physics_process(false)
	world.map_overview=true
	world._set_camera()
	for i in range(75):await process_frame
	await world.capture_frame("district_%d_overview"%index)
	world.ui.root.visible=false
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://assets/ui/maps"))
	root.get_texture().get_image().save_png("res://assets/ui/maps/map%d.png"%index)
	world.ui.root.visible=true
	world.map_overview=false
	world.camera_focus=Vector3(world.launch_point.x,0,world.launch_point.z)
	world._set_camera()
	for i in range(120):await process_frame
	await world.capture_frame("district_%d_flight"%index)
	print("RENDER_PROBE_OK map=",index," renderer=",RenderingServer.get_current_rendering_method()," fps=",Engine.get_frames_per_second())
	print("RENDER_METRICS objects=",Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME)," primitives=",Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)," draws=",Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)," nodes=",Performance.get_monitor(Performance.OBJECT_NODE_COUNT))
	quit(0)
