extends "res://tests_v3/test_boss_hit_amount.gd"
func _scope() -> String:
	return "Actual MAIN I2 with explicit Director-only prefix through Pump plan and collision-checked PLAYER observation poses. This checks safe briefing/no attack at z=-19 and ordinary engagement only after z=-21; previous clinic/distribution/Canal history was not played or restored in this private fixture. No natural Boss win, whole campaign, rendering or LAN proof."

func _run() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--qa-profile="): profile=arg.trim_prefix("--qa-profile=")
		if arg.begins_with("--output="): output=arg.trim_prefix("--output=")
	if not profile.begins_with("qa_pump_safe_entry_") or profile!=profile.validate_filename() or DirAccess.dir_exists_absolute("user://profiles_v3/"+profile) or not output.begins_with("res://artifacts/v3/pump-safe-entry-") or ".." in output or DirAccess.dir_exists_absolute(output): quit(2); return
	if DirAccess.make_dir_recursive_absolute(output)!=OK: quit(2); return
	boss="campaign"
	region="I2"
	began=Time.get_ticks_msec()
	session=MAIN.instantiate()
	root.add_child(session)
	if not _check(session.start_flight("solo") and session._load_region("I2"),"actual empty private MAIN loads current default I2"): _finish(); return
	session.inputs.test_enabled=true
	session.inputs.test_frame={"axes":{},"held":["brake"],"edges":[]}
	await _frame()
	var briefing:=Vector3(0,5,-19)
	if not _check(_clear_pose(briefing),"actual briefing observation pose is whole-hull clear"): _finish(); return
	if not await _place(briefing) or not _plan_fixture("I2:twin_pump_guardian:plan"): _finish(); return
	for unused in 30: await _frame()
	if not _check(not session.campaign.active() and not session.boss_active and session.players[1].health==100.0,"original plan at briefing stays safe during ordinary physics",_diagnostics()): _finish(); return
	var entry:=Vector3(0,8,-21.3)
	if not _check(_clear_pose(entry),"actual arena approach is whole-hull clear") or not await _place(entry): _finish(); return
	for unused in 30:
		if session.campaign.active(): break
		await _frame()
	# The separate engage objective requires witnessing the real attack cycle;
	# encounter startup must not be mistaken for that later observation credit.
	_check(session.campaign.active() and session.boss_active and "I2:twin_pump_guardian:engage" not in session.story.state.completed,"ordinary approach starts combat and withholds the later attack-cycle receipt",_diagnostics())
	_finish()
