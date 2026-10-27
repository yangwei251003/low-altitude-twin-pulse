extends SceneTree
## Actual GPU layout captures; no pointer/hardware or performance claim.
var game: GameSessionV2
var output="res://artifacts/worldui/ui_matrix"
func _initialize() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--qa-output="): output=argument.trim_prefix("--qa-output=")
	if not output.begins_with("res://artifacts/worldui/") or output.contains("..") or DirAccess.dir_exists_absolute(output):
		push_error("UI captures require a fresh artifacts/worldui directory");quit(2);return
	call_deferred("run")
func run() -> void:
	if DisplayServer.get_name()=="headless" or not Array(OS.get_cmdline_user_args()).any(func(a):return str(a).begins_with("--v2-qa=")):quit(2);return
	DirAccess.make_dir_recursive_absolute(output)
	game=GameSessionV2.new();root.add_child(game)
	for i in range(5):await process_frame
	game.update_setting("quality","standard")
	for dimensions in [Vector2i(1280,720),Vector2i(1920,1080),Vector2i(1024,768)]:
		DisplayServer.window_set_size(dimensions)
		for scale in [1.0,1.25,1.5]:
			game.update_setting("ui_scale",scale)
			var prefix="%dx%d_%d"%[dimensions.x,dimensions.y,roundi(scale*100)]
			for page in ["主页","任务","配装"]:
				game.ui.show_hangar(page);await capture(prefix+"_"+{"主页":"lobby","任务":"regions","配装":"loadout"}[page])
			game.launch_exploration("R1");game.pilot.freeze=true;game.input.active=false
			await capture(prefix+"_hud")
			game.pause_game();await capture(prefix+"_pause");game.show_hangar()
	game.phone.stop_server();game.queue_free()
	for i in range(3):await process_frame
	print("WORLDUI_UI_CAPTURE_COMPLETE");quit()
func capture(label: String) -> void:
	for i in range(10):await process_frame
	await RenderingServer.frame_post_draw
	var pixels=root.get_texture().get_image()
	print("WORLDUI_UI_CAPTURE ",label," ",pixels.get_size()," ",pixels.save_png(output+"/"+label+".png"))
