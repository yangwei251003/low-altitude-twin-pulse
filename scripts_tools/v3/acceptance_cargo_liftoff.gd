extends SceneTree
## A bounded ordinary E/brake input on THIS acceptance run's actual carried save.
## No pose/velocity/clock/custody/progress writes, no historical-chain mutation.
const Main = preload("res://scenes/v3/main.tscn")
const Controller = preload("res://scripts_tools/v3/acceptance_flight_driver.gd")
const Store = preload("res://scripts/v3/core/twin_world_store.gd")
var session: Node
var driver: Node
var output := ""
var initial: Dictionary = {}
var report: Dictionary = {}
var finishing := false

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var args: Dictionary = {}
	for arg: String in OS.get_cmdline_user_args():
		var split := arg.find("=")
		if split<0:quit(2);return
		args[arg.substr(0,split)] = arg.substr(split+1)
	if args.size()!=2 or args.get("--qa-profile")!="qa_normal_campaign_20261022_200054_c089dd46" or not args.has("--output"):quit(2);return
	output=str(args["--output"])
	if not output.is_absolute_path() or FileAccess.file_exists(output) or ".." in output:quit(2);return
	if ProjectSettings.get_setting("application/config/version")!="3.0.0-dev.92":quit(2);return
	session=Main.instantiate()
	root.add_child(session)
	await process_frame
	initial=session.store.snapshot()
	if not session.profile_ready or initial.world.branch_id!="main" or initial.world.region_id!="I3" or initial.world.actions.opening.completed.size()!=53:quit(2);return
	if not session.start_flight("solo"):quit(2);return
	var until:=Time.get_ticks_msec()+15000
	while not session.thermal_cargo.module.status().get("ready",false) and Time.get_ticks_msec()<until:await physics_frame;await process_frame
	driver=Controller.new()
	session.add_child(driver)
	driver.attach(session)
	driver.pilot=null
	if not await driver._dismiss():await _finish(false,"dialogue_not_closed");return
	var body=driver._body()
	var before: Dictionary=session.thermal_cargo.module.status()
	var valid: bool=before.get("ready",false) and before.custody.cargos["I3:loaded_cassette"].phase=="carried" and body.cargo_items.has("I3:loaded_cassette") and absf(body.cargo_kg-2.0)<.0001
	if not driver._check(valid,"native restored PinJoint and actual 2kg custody before ordinary lift",before):await _finish(false,"actual_carried_save_required");return
	report["before_position"]=str(body.global_position)
	report["before_cargo"]=before
	var saved_cargo: Dictionary=initial.world.environment.I3_thermal_cargo
	var module=session.thermal_cargo.module
	var saved_pose: Transform3D=module._transform(saved_cargo.cargo.native_pose)
	var size: Vector3=module._vector(saved_cargo.cargo.contract.size)
	var deep: Transform3D=saved_pose;deep.origin.y-=.1
	var side: Transform3D=saved_pose;side.origin.x+=3.0
	driver._check(module._restore_berth_contact(size,saved_pose,module._berths[module.LOW]) and not module._restore_berth_contact(size,deep,module._berths[module.LOW]) and not module._restore_berth_contact(size,side,module._berths[module.LOW]) and not module._restore_berth_contact(size,saved_pose,body),"native saved support is accepted; deep, side and other-body counterexamples remain rejected (read-only geometry)")
	until=Time.get_ticks_msec()+12000
	while driver._healthy() and body.global_position.y<7.0 and Time.get_ticks_msec()<until:
		Input.action_press("flight_high")
		await driver._next()
	Input.action_release("flight_high")
	Input.action_press("flight_brake")
	until=Time.get_ticks_msec()+8000
	while driver._healthy() and body.linear_velocity.length()>.12 and Time.get_ticks_msec()<until:await driver._next()
	Input.action_release("flight_brake")
	var after: Dictionary=session.thermal_cargo.module.status()
	report["after_position"]=str(body.global_position)
	report["after_cargo"]=after
	var probe=Controller.Pilot.new()
	var clear: bool=probe.bind(body)
	if clear:
		probe.go_to(body.global_position,1)
		probe.tick(1.0/60.0,true,false)
		clear=bool(probe.report().get("probe",{}).get("clear",false))
	probe=null
	var ok: bool=driver._check(driver._healthy() and body.global_position.y>=6.5 and clear and body.cargo_items.has("I3:loaded_cassette") and after.custody.cargos["I3:loaded_cassette"].phase=="carried","ordinary E and brake lift the real load clear of LOW; original Pilot envelope now clear",after)
	await _finish(ok,"ordinary_lift_completed" if ok else "ordinary_lift_not_proven")

func _finish(ok: bool, reason: String) -> void:
	if finishing:return
	finishing=true
	Input.action_release("flight_high")
	Input.action_release("flight_brake")
	driver.pilot=null
	if not session.simulation_paused:driver._key(KEY_P);await driver._next()
	var callbacks: Array=[]
	var until:=Time.get_ticks_msec()+15000
	while session.environment_save_gate.pending() and Time.get_ticks_msec()<until:await driver._next()
	var request: Dictionary=session.request_environment_save(func(row: Dictionary):callbacks.append(row.duplicate(true)))
	while callbacks.is_empty() and Time.get_ticks_msec()<until:await driver._next()
	var reader=Store.new(session.store.root_path)
	var loaded: Dictionary=reader.load_profile()
	var saved: Dictionary=reader.snapshot()
	var unchanged: bool=saved.world.actions.opening.completed==initial.world.actions.opening.completed and saved.world.actions.opening.receipts==initial.world.actions.opening.receipts and saved.world.completed_objectives==initial.world.completed_objectives
	driver._check(loaded.get("ok",false) and not loaded.get("recovered",false) and not callbacks.is_empty() and callbacks[-1].get("completed",false) and unchanged,"original SaveGate/fresh Reader keep exactly the same53 goals and receipts",{"request":request,"callbacks":callbacks,"reader":loaded})
	report.merge({"passed":ok and driver.failures.is_empty(),"reason":reason,"version":ProjectSettings.get_setting("application/config/version"),"profile":"qa_normal_campaign_20261022_200054_c089dd46","profile_id":saved.profile_id,"lineage_id":saved.lineage_id,"generation":saved.generation,"initial_goals":53,"final_goals":saved.world.actions.opening.completed.size(),"checks":driver.checks,"failures":driver.failures,"events":driver.events,"distance_m":driver.distance,"native_exit":{"observed":false},"scope":"Source MAIN on the existing NEW acceptance profile, ordinary Input.action_press flight_high/brake only. Actual carried restore, original physics/custody and original save; no task advance, pose/velocity/clock/progress assignment, save editing or old-chain mutation."})
	driver.running=false
	_write()
	session.tree_exiting.connect(func():report.native_exit={"observed":true,"audio":session.last_audio_shutdown_result};report.passed=report.passed and session.last_audio_shutdown_result.get("ready",false);_write())
	session._quit()

func _write() -> void:
	var file=FileAccess.open(output,FileAccess.WRITE)
	if file!=null:file.store_string(JSON.stringify(report,"\t"));file.close()
