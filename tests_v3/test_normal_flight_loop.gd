extends SceneTree
## New-profile first-action loop using only the original PilotInput axes and
## FlightBody forces. No authored player transform, velocity, action state or fact.
const MAIN = preload("res://scenes/v3/main.tscn")
const REWARD := "opening:rescue_log"
const DT := 1.0/60.0
class ErrorLogger extends Logger:
	var guard := Mutex.new()
	var errors: Array = []
	func _log_error(function: String,file: String,line: int,code: String,rationale: String,_notify: bool,kind: int,_trace: Array[ScriptBacktrace]) -> void:
		if kind==Logger.ERROR_TYPE_WARNING: return
		guard.lock()
		errors.append({"function":function,"file":file,"line":line,"code":code,"rationale":rationale})
		guard.unlock()
var logger := ErrorLogger.new()
var session: Node
var pilot: FlightBodyV2
var profile := ""
var output := ""
var stage := ""
var checks: Array = []
var trajectory: Array = []
var waypoints: Array = []
var finished := false
var frames := 0
var path_m := 0.0
var max_step_m := 0.0
var previous := Vector3.ZERO
var started_usec := 0
var save_result: Dictionary = {}
var saved_state: Dictionary = {}

func _initialize() -> void:
	OS.add_logger(logger)
	_run.call_deferred()

func _run() -> void:
	started_usec = Time.get_ticks_usec()
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--qa-profile="): profile = arg.trim_prefix("--qa-profile=")
		if arg.begins_with("--output="): output = arg.trim_prefix("--output=")
		if arg.begins_with("--stage="): stage = arg.trim_prefix("--stage=")
	if not profile.begins_with("qa_normal_flight_") or profile!=profile.validate_filename() or not output.begins_with("res://artifacts/v3/normal-flight-") or ".." in output or stage not in ["flight","reload"]:
		quit(2)
		return
	if stage=="flight" and (DirAccess.dir_exists_absolute("user://profiles_v3/"+profile) or DirAccess.dir_exists_absolute(output)):
		quit(2)
		return
	DirAccess.make_dir_recursive_absolute(output)
	create_timer(125.0 if stage=="flight" else 25.0).timeout.connect(func():
		if not finished:
			_check(false,"bounded normal flight loop deadline")
			_finish())
	session = MAIN.instantiate()
	root.add_child(session)
	if not _check(session.profile_ready and session.interface.menu.visible,"normal MAIN opens original hangar menu"):
		_finish()
		return
	# Emit the actual existing menu button; no direct start/region shortcut.
	var start: Button
	for node: Node in session.interface.menu.find_children("*","Button",true,false):
		if node.text=="单人出航 / 继续": start = node
	if not _check(start!=null,"normal solo/continue button available"):
		_finish()
		return
	start.pressed.emit()
	if not _check(session.active and session.region_id=="I1" and session.players.has(1) and session.world.build_errors.is_empty(),"normal solo button loads I1 with original player and world"):
		_finish()
		return
	pilot = session.players[1]
	previous = pilot.global_position
	session.inputs.test_enabled = true
	await _hold_for(pilot.global_position,.35)
	_check(not pilot.freeze and pilot.enabled and pilot.get_rid().is_valid() and not pilot.sleeping,"original dynamic FlightBody remains active")
	if stage=="reload":
		await _reload_check()
		_finish()
		return
	var spawn := pilot.global_position
	_check(session.story.state.get("completed",[]).is_empty() and session.store.snapshot().personal.discoveries.count(REWARD)==0,"new QA profile has no preseeded action or reward")
	session._action_received(1,"explore",{"target_id":"npc:linlan"})
	await _hold_for(spawn,.4)
	if not _check("I1:rescue:brief" in session.story.state.completed,"nearby normal Story interaction commits Linlan briefing"):
		_finish()
		return
	if not await _fly_to("relay approach",Vector3(-14,2.5,20),24):
		_finish()
		return
	var actions_before: int = session.stats.abilities
	session._action_received(1,"ability",{"ability":"charge","target_id":"I1:relay"})
	await _hold_for(Vector3(-14,2.5,20),1.8)
	if not _check(session.stats.abilities==actions_before+1 and session.world.gate_fraction>=.95 and "I1:rescue:channel" in session.story.state.completed,"real nearby charge, physical gate and Story observation open rescue route",{"abilities":session.stats.abilities,"gate_fraction":session.world.gate_fraction,"story":session.story.state.completed}):
		_finish()
		return
	# Climb on the clear east approach, then cross the real shutter opening at
	# its authored centre altitude. The gate is never bypassed by a QA teleport.
	for row: Array in [["east climb",Vector3(-15.5,6.15,29),20.0],["south gate approach",Vector3(-24,6.15,28.5),18.0],["through open gate to rescue",Vector3(-24,6.15,21.2),18.0]]:
		if not await _fly_to(str(row[0]),row[1],float(row[2])):
			_finish()
			return
	await _hold_for(Vector3(-24,6.15,21.2),.5)
	if not _check("I1:rescue:contact" in session.story.state.completed,"actual flown arrival naturally observes stranded maintenance drone"):
		_finish()
		return
	for row: Array in [["return through open gate",Vector3(-24,6.15,28.5),18.0],["south exit above beacon",Vector3(-20,6.15,32),14.0],["descend to reception",Vector3(-20,2.5,32),14.0]]:
		if not await _fly_to(str(row[0]),row[1],float(row[2])):
			_finish()
			return
	await _hold_for(Vector3(-20,2.5,32),.6)
	var snapshot: Dictionary = session.store.snapshot()
	if not _check("I1:rescue:evacuate" in session.story.state.completed and "I1:rescue" in session.story.state.completed_actions and snapshot.personal.discoveries.count(REWARD)==1,"real evacuation completes first action and grants one durable reward"):
		_finish()
		return
	_check(path_m>45 and max_step_m<.8 and pilot.flight_seconds>10 and pilot.enabled,"continuous original-body flight, bounded frame motion and no disabled rescue",{"path_m":path_m,"max_step_m":max_step_m,"flight_seconds":pilot.flight_seconds,"collisions":pilot.collision_count,"health":pilot.health})
	# Use the real asynchronous environment/Store path and then the menu's
	# production save-and-quit path. A second process verifies actual disk data.
	save_result = {}
	var requested: Dictionary = session.request_environment_save(func(result: Dictionary): save_result = result.duplicate(true))
	var save_wait := 0
	while save_result.is_empty() and save_wait<300:
		await _hold_for(Vector3(-20,2.5,32),DT)
		save_wait += 1
	if not _check(requested.get("ok",false) and save_result.get("ok",false),"real original Store save completes",{"requested":requested,"result":save_result}):
		_finish()
		return
	saved_state = session.store.snapshot()
	_write_report()
	# Do not set finished: a refused quit must reach the watchdog and fail.
	session._ui_action("quit",{})

func _reload_check() -> void:
	var first: Variant = JSON.parse_string(FileAccess.get_file_as_string(output+"/flight.json"))
	if not _check(first is Dictionary and first.get("failures",[]).is_empty() and first.get("profile","")==profile,"first process left valid flight/save evidence"):
		return
	var snapshot: Dictionary = session.store.snapshot()
	_check("I1:rescue:evacuate" in session.story.state.completed and "I1:rescue" in session.story.state.completed_actions and snapshot.personal.discoveries.count(REWARD)==1,"fresh MAIN process restores first action and exactly one reward from disk")
	_check(session.story.state.choices.get("I1:rescue:channel","")=="charge" and bool(session.entities["I1:relay"].powered),"original saved charge route and relay survive reentry")
	var completed: Array = session.story.state.completed.duplicate()
	var generation: int = snapshot.generation
	session._action_received(1,"explore",{"target_id":"npc:linlan"})
	await _hold_for(pilot.global_position,.5)
	var after: Dictionary = session.store.snapshot()
	_check(session.story.state.completed==completed and after.personal.discoveries.count(REWARD)==1 and int(after.generation)==generation,"repeat normal NPC interaction does not repeat objective, reward or Store commit")
	saved_state = after

func _fly_to(label: String,target: Vector3,limit_seconds: float) -> bool:
	var begin := pilot.global_position
	var start_frame := frames
	var arrived := 0
	for tick in range(int(limit_seconds/DT)):
		_drive(target)
		await physics_frame
		_sample()
		if not pilot.enabled or not pilot.global_position.is_finite(): break
		var delta := pilot.global_position-target
		if Vector2(delta.x,delta.z).length()<.75 and absf(delta.y)<.5 and pilot.linear_velocity.length()<1.0: arrived += 1
		else: arrived = 0
		if arrived>=12:
			waypoints.append({"label":label,"target":target,"from":begin,"actual":pilot.global_position,"physics_frames":frames-start_frame})
			return _check(true,"flown waypoint: "+label)
	waypoints.append({"label":label,"target":target,"from":begin,"actual":pilot.global_position,"physics_frames":frames-start_frame,"failed":true})
	return _check(false,"flown waypoint: "+label,{"actual":pilot.global_position,"target":target,"velocity":pilot.linear_velocity,"health":pilot.health,"enabled":pilot.enabled})

func _drive(target: Vector3) -> void:
	var offset := target-pilot.global_position
	var desired := Vector3(offset.x,0,offset.z)*.95
	desired = desired.limit_length(3.8)
	var planar := desired/maxf(1.0,float(pilot.stats.speed_mps))
	var right: Vector3 = session.camera.global_basis.x
	right.y = 0
	right = right.normalized()
	var forward: Vector3 = -session.camera.global_basis.z
	forward.y = 0
	forward = forward.normalized()
	var rate: float = pilot.stats.rise_mps if offset.y>=0 else pilot.stats.fall_mps
	var vertical := clampf((offset.y*1.25-pilot.linear_velocity.y*.35)/maxf(.5,rate),-1,1)
	session.inputs.test_frame = {"axes":{"right_x":planar.dot(right),"right_y":planar.dot(forward),"left_y":vertical,"left_x":0},"held":[],"edges":[]}

func _hold_for(target: Vector3,seconds: float) -> void:
	for tick in range(maxi(1,int(ceil(seconds/DT)))):
		_drive(target)
		await physics_frame
		_sample()

func _sample() -> void:
	frames += 1
	var point := pilot.global_position
	var step := point.distance_to(previous)
	path_m += step
	max_step_m = maxf(max_step_m,step)
	previous = point
	if frames%6==0: trajectory.append({"frame":frames,"position":point,"velocity":pilot.linear_velocity,"health":pilot.health,"story_revision":session.story.state.revision})

func _check(ok: bool,label: String,actual: Variant=null) -> bool:
	checks.append({"passed":ok,"label":label,"actual":actual})
	return ok

func _write_report() -> void:
	var failures := checks.filter(func(row: Dictionary): return not row.passed)
	FileAccess.open(output+"/"+stage+".json",FileAccess.WRITE).store_string(JSON.stringify({"profile":profile,"stage":stage,"checks":checks,"failures":failures,"engine_errors":logger.errors,"elapsed_seconds":float(Time.get_ticks_usec()-started_usec)/1000000.0,"path_m":path_m,"max_step_m":max_step_m,"trajectory":trajectory,"waypoints":waypoints,"store":saved_state,"scope":"Normal hangar button, original dynamic FlightBody driven by bounded test input axes, real nearby Story/charge intents, automatic physical observations and original Store save/reopen. No player transforms/velocities/action facts/state fixtures authored by test. Headless automated route, not keyboard/human comfort, graphics, performance, LAN or full campaign evidence."},"\t"))
	print("NORMAL_FLIGHT_LOOP_RESULT "+JSON.stringify({"stage":stage,"checks":checks.size(),"failures":failures,"engine_errors":logger.errors,"path_m":path_m}))

func _finish() -> void:
	if finished: return
	finished = true
	_write_report()
	var failed: bool = not checks.filter(func(row: Dictionary): return not row.passed).is_empty() or not logger.errors.is_empty()
	if is_instance_valid(session): session.network.close()
	quit(1 if failed else 0)
