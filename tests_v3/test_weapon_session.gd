extends "res://tests_v3/test_boss_hit_amount.gd"
## Reuse actual MAIN/geometry/teardown helpers, not a fake Encounter.
const Hangar = preload("res://scripts/v3/gameplay/twin_hangar.gd")

func _scope() -> String:
	return "Actual MAIN/Crown, original Hangar Store with explicit two-discovery module-ownership fixture, actual saved burst+cooling departure and ordinary held-fire input ticks. Explicit whole-hull-clear observation poses, real original light/growth armor opening and real damage; release/pause cancel, single cooldown/cooling/HUD. A separate labelled 100-heat fixture checks same-body restore retains the below-40% overheat latch. No natural campaign, earned discoveries, hardware controller, graphics, LAN or victory acceptance."

func _run() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--qa-profile="): profile=arg.trim_prefix("--qa-profile=")
		if arg.begins_with("--output="): output=arg.trim_prefix("--output=")
	if not profile.begins_with("qa_weapon_session_") or profile!=profile.validate_filename() or DirAccess.dir_exists_absolute("user://profiles_v3/"+profile) or not output.begins_with("res://artifacts/v3/weapon-session-") or ".." in output or DirAccess.dir_exists_absolute(output): quit(2); return
	if DirAccess.make_dir_recursive_absolute(output)!=OK: quit(2); return
	boss="crown"
	region="F1"
	began=Time.get_ticks_msec()
	create_timer(60.0).timeout.connect(func():
		if not finished: _check(false,"bounded actual weapon Session",_diagnostics()); _finish())
	session=MAIN.instantiate()
	root.add_child(session)
	var grant: Dictionary=session.store.commit({"id":"qa-burst-module-ownership-fixture","append":{"personal.discoveries":["boss:F2:mirrorwing_warden","I3:cooling_overdraft"]}})
	if not _check(grant.get("ok",false),"explicit module-ownership fixture uses original private Store"): _finish(); return
	fixtures.append({"kind":"two_discoveries_for_module_ownership_only","earned_campaign":false})
	var draft: Dictionary=Hangar.launch_build(session.store.snapshot(),"tr01").build
	draft.slots.weapon="burst_capacitor"
	draft.slots.utility="cooling_duct"
	session._ui_action("hangar",{})
	session._ui_action("hangar_save",{"build":draft,"generation":session.store.snapshot().generation})
	session._ui_action("hangar_close",{})
	if not _check(Hangar.launch_build(session.store.snapshot()).build.slots.weapon=="burst_capacitor" and session.start_flight("solo") and session._load_region("F1"),"actual Hangar saved hardware launches into original Crown world"): _finish(); return
	session.inputs.test_enabled=true
	_hold(false)
	var body: FlightBodyV2=session.players[1]
	if not _check(body.build.slots.weapon=="burst_capacitor" and body.build.slots.utility=="cooling_duct","actual Flight owns the saved weapon and cooling duct"): _finish(); return
	if not await _place_near(session.world.crown_arena.host_position(WEST),WEST,true,3.0): _finish(); return
	session._start_boss(false)
	session._action_received(1,"lock",{"target_id":"boss:crown_core"})
	var hp: Dictionary=_hp()
	_hold(true)
	await _frames(30)
	if not _check(_hp()==hp and session.weapons.presentation(1).charge_s==0.0 and body.heat==0.0,"ordinary held input cannot charge or hit through real closed armor",session.weapons.presentation(1)): _finish(); return
	_hold(false)
	await _frame()
	if not await _place_near(session.world.crown_arena.host_position(WEST),WEST,true,3.0) or not await _ability("light",WEST,"on") or not await _ability("growth",WEST,""): _finish(); return
	if not await _place_near(session.world.crown_arena.core_position(),"boss:crown_core",true): _finish(); return
	session._action_received(1,"lock",{"target_id":"boss:crown_core"})
	_hold(true)
	await _frames(20)
	if not _check(_hp()==hp and float(session.weapons.presentation(1).charge_s)>0.0 and float(session.weapons.presentation(1).charge_s)<.7,"real held input visibly charges before any original HP change",session.weapons.presentation(1)): _finish(); return
	_hold(false)
	await _frames(2)
	if not _check(_hp()==hp and session.weapons.presentation(1).charge_s==0.0 and body.heat==0.0,"release cancels real Session charge without firing or heat"): _finish(); return
	_hold(true)
	await _frames(15)
	session.network.send_action("propose",{"kind":"pause","payload":{}})
	for unused in 60:
		if session.simulation_paused: break
		await _frame()
	if not _check(session.simulation_paused and session.weapons.presentation(1).charge_s==0.0,"original Consensus pause cancels transient charge"): _finish(); return
	var frozen: Dictionary=session.weapons.presentation(1)
	await _frames(12)
	if not _check(session.weapons.presentation(1)==frozen and _hp()==hp,"common pause freezes the same burst clock, heat and actual Boss HP"): _finish(); return
	_hold(false)
	session.network.send_action("propose",{"kind":"pause","payload":{}})
	for unused in 60:
		if not session.simulation_paused: break
		await _frame()
	if not _check(not session.simulation_paused,"original Consensus resumes ordinary physical ticks"): _finish(); return
	if not _open("boss:crown_core"):
		if not await _place_near(session.world.crown_arena.host_position(WEST),WEST,true,3.0) or not await _ability("light",WEST,"on") or not await _ability("growth",WEST,""): _finish(); return
	if not await _place_near(session.world.crown_arena.core_position(),"boss:crown_core",true): _finish(); return
	_hold(true)
	for unused in 150:
		await _frame()
		if _hp()!=hp: break
	var view: Dictionary=session.weapons.presentation(1)
	if not _check(float(hp.core_hp_milli)-float(_hp().core_hp_milli)==28000.0 and is_equal_approx(body.heat,32.0) and is_equal_approx(float(view.cooldown_s),1.0),"ordinary held burst reaches real hit28 and commits exactly32 heat/1s once",{"view":view,"hp":_hp()}): _finish(); return
	var after: Dictionary=_hp()
	await _frames(30)
	view=session.weapons.presentation(1)
	if not _check(_hp()==after and is_equal_approx(body.heat,22.0) and is_equal_approx(float(view.cooldown_s),.5),"one clock yields half-second cooldown and real cooling-duct20/s",view): _finish(); return
	session._refresh_interface()
	_check(session.interface.weapon_status.text.contains("热量") and session.interface.weapon_status.text.contains("蓄能炮"),"native HUD shows actual selected weapon and heat",session.interface.weapon_status.text)
	_hold(false)
	# Separate explicit heat fixture, solely for the real same-body restore bug.
	var configured: Dictionary=session.weapons._cycles[1].cycle.configure(body.build,100.0)
	body.heat=100.0
	fixtures.append({"kind":"explicit_100_heat_overheat_latch_fixture_not_earned_shots"})
	if not _check(configured.ok,"labelled heat fixture configures same production Cycle"): _finish(); return
	await _frames(90)
	view=session.weapons.presentation(1)
	if not _check(view.overheated and is_equal_approx(float(view.heat),70.0),"ordinary90 ticks cool to70 while retaining the below40 recovery latch",view): _finish(); return
	var actor: int=body.get_instance_id()
	session._restore_player(1,body.global_position)
	await _frame()
	view=session.weapons.presentation(1)
	_check(body.get_instance_id()==actor and view.overheated and float(view.heat)>40.0 and view.charge_s==0.0,"original same-body restore cancels charge while retaining heat and overheat recovery",view)
	_finish()

func _hold(fire: bool) -> void:
	session.inputs.test_frame={"axes":{},"held":["brake","fire"] if fire else ["brake"],"edges":[]}

func _frames(count: int) -> void:
	for unused in count:
		if not await _frame(): return
