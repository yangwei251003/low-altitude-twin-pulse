extends "res://scripts_tools/v3/acceptance_frontend.gd"
## Exercise the actual W/S/A/D action path and original physics in a new profile.

func _run() -> void:
	var profile:=""
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--qa-profile="): profile=arg.trim_prefix("--qa-profile=")
		elif arg.begins_with("--output="): output=arg.trim_prefix("--output=")
	if not profile.begins_with("qa_heading94_") or profile!=profile.validate_filename() or not output.is_absolute_path() or FileAccess.file_exists(output) or ".." in output: quit(2); return
	if DirAccess.dir_exists_absolute("user://profiles_v3/"+profile): quit(2); return
	session=Main.instantiate()
	root.add_child(session)
	await _settle()
	front=session.interface.front
	var accepted: Dictionary=session.network.validated_input({"body_relative":true,"pitch":.8,"roll":-.3,"yaw":.4,"planar":Vector3(1,0,0)})
	_check(accepted.get("body_relative",false) and is_equal_approx(float(accepted.pitch),.8) and is_equal_approx(float(accepted.yaw),.4),"Host input validator preserves bounded head-relative intent")
	_check(session.network.validated_input({"body_relative":"true"}).is_empty(),"Host rejects malformed control basis flag")
	_check(not session.network.validated_input({"body_relative":false,"planar":Vector3(2,0,0)}).body_relative,"legacy world control remains valid on Host")
	front.navigate("modes")
	await _settle()
	var start: BaseButton=_button_containing("单人出航")
	if not _check(start!=null,"normal single-player launch available"): await _finish(); return
	await _accept(start)
	var deadline:=Time.get_ticks_msec()+30000
	while (front._loading or not session.players.has(1)) and Time.get_ticks_msec()<deadline: await process_frame
	if not _check(session.players.has(1),"normal real flight started"): await _finish(); return
	var body=session.players[1]
	await _hold("flight_brake",30)
	var initial_heading: float=body.heading
	await _hold("flight_right",40)
	var turned_heading: float=body.heading
	_check(absf(angle_difference(initial_heading,turned_heading))>.25,"D turns the aircraft heading",{"before":initial_heading,"after":turned_heading})
	await _hold("flight_brake",25)
	var before: Vector3=body.global_position
	var forward:=Basis(Vector3.UP,float(body.heading))*Vector3.FORWARD
	await _hold("flight_forward",45)
	var displacement: Vector3=body.global_position-before
	_check(displacement.dot(forward)>.20,"W moves along turned nose through original physics",{"displacement":str(displacement),"forward":str(forward),"dot":displacement.dot(forward)})
	_check(body.command.get("body_relative",false),"host applied head-relative command")
	await _hold("flight_brake",45)
	before=body.global_position
	forward=Basis(Vector3.UP,float(body.heading))*Vector3.FORWARD
	await _hold("flight_back",35)
	displacement=body.global_position-before
	_check(displacement.dot(forward)<-.1,"S moves backward relative to the nose",{"displacement":str(displacement),"dot":displacement.dot(forward)})
	await _hold("flight_brake",40)
	var camera_back:=Vector3(session.camera.global_basis.z.x,0,session.camera.global_basis.z.z).normalized()
	var nose_back:=Basis(Vector3.UP,float(body.heading))*Vector3.BACK
	_check(camera_back.dot(nose_back)>.95,"rear oblique camera follows actual heading",camera_back.dot(nose_back))
	await _capture("head_relative_flight")
	session._ui_action("menu",{})
	await _settle()
	front.navigate("settings")
	front.dispatch("setting",{"key":"flight_control","value":"map"})
	front.resume_flight()
	await _settle()
	await _hold("flight_forward",3)
	_check(not body.command.get("body_relative",true) and not session.flight_camera.follow_heading,"legacy map option passes through without head-relative remapping")
	await _hold("flight_brake",20)
	front.navigate("settings")
	front.dispatch("setting",{"key":"flight_control","value":"heading"})
	front.resume_flight()
	await _settle()
	await _hold("flight_left",25)
	_check(body.command.get("body_relative",false) and session.flight_camera.follow_heading,"heading mode can be restored in same flight")
	await _hold("flight_brake",20)
	await _finish()

func _hold(action: String, frames: int) -> void:
	Input.action_press(action)
	for index in range(frames): await physics_frame
	Input.action_release(action)
	await physics_frame
