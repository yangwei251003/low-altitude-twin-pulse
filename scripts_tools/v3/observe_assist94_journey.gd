extends "res://scripts_tools/v3/acceptance_assist94.gd"
## Continued observation of this turn's naturally earned private progress.
## The shipping assistant drives. This observer only supplies explicit decisions.
func _run() -> void:
	var profile:=""
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--qa-profile="): profile=arg.trim_prefix("--qa-profile=")
		elif arg.begins_with("--output="): output=arg.trim_prefix("--output=")
	if profile!="qa_assist94_20261022_233052_57082e" or not output.is_absolute_path() or FileAccess.file_exists(output) or ".." in output: quit(2); return
	session=Main.instantiate()
	root.add_child(session)
	await _settle()
	front=session.interface.front
	if not _check(logger.errors.is_empty() and is_instance_valid(session.flight_assist),"modules ready"): await _finish(); return
	front.navigate("modes")
	await _settle()
	await _accept(_button_containing("单人出航"))
	var deadline:=Time.get_ticks_msec()+35000
	while (front._loading or not session.players.has(1)) and Time.get_ticks_msec()<deadline: await process_frame
	if not _check(session.players.has(1),"ordinary saved flight restored"): await _finish(); return
	var before: Array=session.story.state.get("completed",[]).duplicate()
	_check(before.size()>=4,"continues actual progress from current isolated run",before)
	_check(session.qa_mode.is_empty(),"only production assistant drives")
	var response: Dictionary=session.start_flight_assist("journey")
	if not _check(response.get("ok",false),"continuous assistant starts"): await _finish(); return
	deadline=Time.get_ticks_msec()+2400000
	while session.flight_assist.enabled and logger.errors.is_empty() and Time.get_ticks_msec()<deadline:
		await create_timer(.5).timeout
		_observe()
		if session.interface.chapter_choice.visible:
			await _explicit_choice()
		elif session.flight_assist.state=="waiting_choice" and "亲自按 G" in session.flight_assist.message:
			_key(KEY_G)
			await _settle()
			_check(not session.flight_assist.enabled,"manual bridge confirmation takes over")
			session.start_flight_assist("journey")
	var completed: Array=session.story.state.get("completed",[]).duplicate()
	var status: Dictionary=session.flight_assist.status()
	var detail: Dictionary={"assistant":status,"completed":completed,"position":str(session.players[1].global_position),"velocity":str(session.players[1].linear_velocity),"step_data":str(session.flight_assist._step_data),"routes":str(session.flight_assist._steps),"observations":observations}
	if session.flight_assist._combat!=null: detail.boss_state=session.flight_assist._combat.boss_state()
	if session.flight_assist._pilot!=null: detail.pilot={"state":session.flight_assist._pilot.state,"probe":str(session.flight_assist._pilot.last_probe)}
	_check(completed.size()==84,"continuous product assistant reached all 84 actual main objectives",detail)
	session.flight_assist.stop("本次观察结束")
	await _capture("journey_end")
	session._return_to_hangar()
	deadline=Time.get_ticks_msec()+15000
	while session.active and Time.get_ticks_msec()<deadline: await process_frame
	_check(not session.active,"normal return persists this run's earned progress")
	await _finish()

func _explicit_choice() -> void:
	var panel: Control=session.interface.chapter_choice
	var target: String=panel._target
	var boxes: Array=[]
	for child: Node in panel._content.get_children():
		if child is CheckBox: boxes.append(child)
	for box: CheckBox in boxes:
		if not box.button_pressed: await _accept(box)
	if panel._review_only:
		for child: Node in panel._content.get_children():
			if child is Button and child.text=="返回，继续考虑": await _accept(child); break
	elif not panel._buttons.is_empty():
		await _accept(panel._buttons[0])
	_check(not panel.visible,"test pilot explicitly read and confirmed original choice UI",target)

func _key(code: int) -> void:
	for pressed: bool in [true,false]:
		var event:=InputEventKey.new()
		event.physical_keycode=code
		event.keycode=code
		event.pressed=pressed
		Input.parse_input_event(event)
