extends "res://scripts_tools/v3/acceptance_frontend.gd"
## Dev94 visual/input evidence, new isolated profile. Never drives OS input.

func _run() -> void:
	var profile:=""
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--qa-profile="): profile=arg.trim_prefix("--qa-profile=")
		elif arg.begins_with("--output="): output=arg.trim_prefix("--output=")
	if not profile.begins_with("qa_front94_") or profile!=profile.validate_filename() or not output.is_absolute_path() or FileAccess.file_exists(output) or ".." in output: quit(2); return
	if DirAccess.dir_exists_absolute("user://profiles_v3/"+profile): quit(2); return
	session=Main.instantiate()
	root.add_child(session)
	await _settle()
	front=session.interface.front
	if not _check(is_instance_valid(front) and session.profile_ready,"front and independent profile ready"): await _finish(); return
	_check(not session.active and session.players.is_empty(),"startup remains lobby without world")
	_check(session.inputs.v3_control_scheme=="heading" and session.flight_camera.follow_heading,"default is head-relative controls and rear oblique follow")
	_check(front._backdrop._scene_art!=null,"imagegen artwork imported and consumed")
	for id: String in front._nav_buttons:
		_check(front._nav_buttons[id].icon!=null,"original navigation icon: "+id)
	await _capture("home")
	var preview=front._body.find_child("SelectedAirframePreview",true,false)
	if not _check(preview!=null,"actual 3D airframe exists"): await _finish(); return
	_check(preview._viewport.own_world_3d and preview._airframe.get_child_count()>0,"isolated real GLB model and world")
	_check(preview._viewport.size.x<=640 and preview._viewport.size.y<=400,"3D rendering size is bounded",str(preview._viewport.size))
	var yaw: float=preview._yaw
	await _accept(preview._controls.get_child(2))
	_check(absf(preview._yaw-yaw)>.1,"native turntable button rotates actual model")
	_check(preview._controls.get_child(2)._pulse<1.0,"native accepted click triggers visible pulse")
	await _capture("model_rotated_click")
	await _accept(preview._controls.get_child(1))
	_check(is_equal_approx(preview._yaw,preview.DEFAULT_YAW),"native reset returns model angle")
	var press_count: int=int(session.audio.debug_state().played) if session.audio.has_method("debug_state") else 0
	await _accept(front._nav_buttons.modes)
	_check(front.page=="modes","navigation remains native and immediate")
	await _capture("modes")
	for page_id: String in ["profile","map","missions","assist","events","results","base","inventory","workshop","shop","friends","room"]:
		front.navigate(page_id)
		await _settle()
		_check(front.page==page_id and front._body.get_child_count()==1,"styled page usable: "+page_id)
		if page_id in ["map","inventory"]: await _capture(page_id)
	front.navigate("inventory")
	front.dispatch("inspect_module",{"id":"pulse_base"})
	await _capture("modal")
	front.back()
	front.navigate("hangar")
	await _settle()
	_check(session.interface.hangar.visible and is_instance_valid(session.interface.hangar._plan._viewport),"hangar uses actual 3D draft preview")
	await _capture("hangar")
	session._ui_action("hangar_close",{})
	front.navigate("settings")
	await _capture("settings")
	front.dispatch("setting",{"key":"reduced_motion","value":true})
	front.navigate("home")
	await _settle()
	preview=front._body.find_child("SelectedAirframePreview",true,false)
	var still_yaw: float=preview._yaw
	await create_timer(.30).timeout
	_check(is_equal_approx(preview._yaw,still_yaw) and preview._reduce_motion,"reduced motion stops model rotation")
	_check(not front._backdrop.is_processing(),"reduced motion stops ambient processing")
	await _accept(preview._controls.get_child(0))
	_check(absf(preview._yaw-still_yaw)>.1 and preview._controls.get_child(0)._pulse>=1.0,"reduced motion preserves manual interaction without pulse")
	front.dispatch("setting",{"key":"flight_control","value":"map"})
	_check(session.inputs.v3_control_scheme=="map" and not session.flight_camera.follow_heading,"original control scheme remains selectable")
	front.dispatch("setting",{"key":"flight_control","value":"heading"})
	front.dispatch("setting",{"key":"reduced_motion","value":false})
	await _capture("home_restored")
	_check(int(session.store.snapshot().generation)==1,"presentation checks never alter campaign progress")
	await _finish()
