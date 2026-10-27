extends SceneTree
## Visual composition fixture only; deliberately separate from real-input route acceptance.
var session: GameSessionV2
var output="res://artifacts/worldui/visual_pass_01"
func _initialize() -> void:call_deferred("run")
func run() -> void:
	if DisplayServer.get_name()=="headless":quit(2);return
	if not Array(OS.get_cmdline_user_args()).any(func(a):return str(a).begins_with("--v2-qa=")):quit(2);return
	for arg in OS.get_cmdline_user_args():
		if str(arg).begins_with("--worldui-output="):output=str(arg).trim_prefix("--worldui-output=")
	DirAccess.make_dir_recursive_absolute(output)
	DisplayServer.window_set_size(Vector2i(1600,900))
	session=GameSessionV2.new();root.add_child(session)
	for i in range(6):await process_frame
	session.repository.commit({"id":"visual_fixture_unlock","append":{"campaign.completed_missions":session.content.missions.map(func(m):return m.id)}})
	session.update_setting("quality","standard")
	session.ui.show_hangar("主页");await capture("lobby")
	session.ui.show_hangar("任务");await capture("regions")
	for rid in ["R1","R2","R3","R4"]:
		for dark in ([false,true] if rid=="R4" else [false]):
			session.night=dark;session.launch_exploration(rid)
			for i in range(8):await process_frame
			session.input.active=false;session.pilot.freeze=true
			await capture(rid+("_night" if dark else "_day")+"_hud")
			session.ui.root.hide()
			hide_names(session.world)
			await capture(rid+("_night" if dark else "_day")+"_entry")
			session.flight_camera.target_size=54
			await create_timer(.8).timeout
			await capture(rid+("_night" if dark else "_day")+"_wide")
			session.flight_camera.enter_overview(Vector2(1600,900));session.overview_proxy.visible=true
			await capture(rid+("_night" if dark else "_day")+"_layout")
			# Authored composition checks: same default camera, explicit fixture poses.
			# These are GPU stills, never counted as flight/mission completion evidence.
			session.overview_proxy.visible=false;session.flight_camera.overview=false;session.flight_camera.target_size=32
			var poses={"R1":[Vector3(201,7,148),Vector3(320,6,83)],"R2":[Vector3(330,14,81),Vector3(145,9,320)],"R3":[Vector3(91,5,307),Vector3(285,9,87)],"R4":[Vector3(241,6,143),Vector3(460,8,268)]}
			for i in range(2):
				session.pilot.global_position=poses[rid][i];session.world.update_stream(session.pilot.global_position,true)
				session.flight_camera.snap(session.pilot.global_position)
				for f in range(12):await process_frame
				hide_names(session.world)
				await capture(rid+("_night" if dark else "_day")+("_route" if i==0 else "_landmark"))
			session.show_hangar()
			for i in range(4):await process_frame
	session.phone.stop_server();quit()
func capture(label: String) -> void:
	for i in range(4):await process_frame
	await RenderingServer.frame_post_draw
	var error=root.get_texture().get_image().save_png(output+"/"+label+".png")
	print("WORLDUI_CAPTURE ",label," ",error)
func hide_names(node: Node) -> void:
	if node is Label3D:node.hide()
	for child in node.get_children():hide_names(child)
