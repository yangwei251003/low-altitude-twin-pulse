extends SceneTree
## Real scene/input component + GPU sample. Scripted pilot inputs are QA,
## not a human playthrough. Does not fake receipts or finish the transport.
const Scene=preload("res://scripts/v3/candidates/canal_playable/canal_playable.tscn")
const Runtime=preload("res://scripts/v3/candidates/canal_service_loop/canal_service_runtime.gd")
var play
var checks:=0
var failures: Array=[]
var finished:=false
var output:=""
var evidence: Dictionary={}
class ErrorLog extends Logger:
	var errors: Array=[]
	func _log_error(fn: String,file: String,line: int,code: String,reason: String,_notify: bool,kind: int,_traces: Array[ScriptBacktrace]) -> void:
		errors.append({"function":fn,"file":file,"line":line,"code":code,"reason":reason,"kind":kind})
var logger=ErrorLog.new()

func _init() -> void:
	OS.add_logger(logger)
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--capture-output="): output=arg.trim_prefix("--capture-output=")
	_run.call_deferred()

func _check(ok: bool,label: String,details: Variant=null) -> bool:
	checks+=1
	if not ok: failures.append({"label":label,"details":details})
	return ok

func _run() -> void:
	create_timer(110).timeout.connect(func():
		if not finished:
			_check(false,"bounded probe timeout")
			_finish())
	play=Scene.instantiate()
	_configure_playable()
	root.add_child(play)
	play.inputs.test_enabled=true
	for i in 2700:
		if not await _frame(): return
		if play.boot_ready: break
	if not _check(play.boot_ready,"actual S0 bootstrap reaches safe WAIT before interaction",play.bootstrap.report()):
		_finish(); return
	_check(play.station!=null and play.station.configured,"real cooling module installed with bootstrap registry")
	_check(not play.executor_ready and play.context.rules.snapshot().pending_action.is_empty(),"no work order is started for the player")
	await _capture("01-ready-default.png")
	if not await _fly_to(Vector3(8,3.2,27)): return
	# Same UI actions as F/X after selecting each supported tool/target. The
	# host performs actual range/LOS and only accepts physically supported use.
	if not await _select_target(play.RELAY_ID): return
	await _key(KEY_6)
	await _key(KEY_F)
	var charged: Dictionary=play.last_action
	if not _check(charged.ok and play.station.facts().powered,"actual near relay charge validates LOS and powers station",charged):
		_finish(); return
	for i in 30:
		if not await _frame(): return
	if not await _select_target(play.VALVE_ID): return
	await _key(KEY_2)
	await _key(KEY_X)
	var pushed: Dictionary=play.last_action
	if not _check(pushed.ok,"from south, reverse pull commands positive valve travel",pushed):
		_finish(); return
	for i in 120:
		if not await _frame(): return
	_check(play.station.facts().valve_open and play.context.rules.snapshot().pump_total_ml>0,"actual slider opening starts independent closed water circulation",play.station.report())
	await _capture("02-valve-open-target.png")
	play.target=Runtime.CASSETTES[1]
	play.selected_ability="heat"
	var energy: float=float(play.entities[play.PLAYER_ID].energy)
	var rejected: Dictionary=play.use_selected(true)
	_check(not rejected.ok and float(play.entities[play.PLAYER_ID].energy)==energy,"distant or occluded WORK cannot be remotely cooled for free",rejected)
	if not await _select_target(play.CARRIER_ID): return
	await _key(KEY_0)
	await _key(KEY_F)
	var ordered: Dictionary=play.last_action
	if not _check(ordered.ok and play.executor_ready,"near visible carrier accepts one persistent work order",ordered):
		_finish(); return
	var initial_carrier: Vector3=play.context.carrier.global_position
	var initial_player: Vector3=play.player.global_position
	var before_flow: int=int(play.context.rules.snapshot().pump_total_ml)
	if not await _fly_to(Vector3(3.5,3.2,26)): return
	for i in 240:
		if not await _frame(): return
	_check(play.context.carrier.global_position.distance_to(initial_carrier)>1.0 and play.player.global_position.distance_to(initial_player)>3.0,"carrier and independently controlled player both physically move")
	_check(int(play.context.rules.snapshot().pump_total_ml)>before_flow,"real cooling loop advances while player leaves and transport runs")
	var before_pause: Dictionary=play.context.rules.snapshot()
	var paused_positions: Array=[play.player.global_position,play.context.carrier.global_position,play.context.cargos[Runtime.CASSETTES[0]].global_position]
	play.toggle_pause()
	for i in 30:
		if not await _frame(): return
	_check(play.context.rules.snapshot()==before_pause and play.player.global_position==paused_positions[0] and play.context.carrier.global_position==paused_positions[1] and play.context.cargos[Runtime.CASSETTES[0]].global_position==paused_positions[2],"whole sample pause freezes world and physical bodies without accruing cooling")
	play.toggle_pause()
	for i in 30:
		if not await _frame(): return
	_check(play.context.rules.snapshot().jobs_completed==0 and play.context.rules.snapshot().service_credit==0,"sample has not manufactured unimplemented work or service")
	await _capture("03-independent-player-and-carrier.png")
	evidence={"scope":"scripted actual player-input component/physics and injected Godot key events for Tab/2/6/0/F/X; host capabilities and fixed camera; partial transport, no physical keyboard/human/MAIN/save/LAN/work completion","bootstrap":play.bootstrap.report(),"executor":play.executor.report(),"station":play.station.report(),"rules":play.context.rules.status(),"player_position":_vec(play.player.global_position),"carrier_position":_vec(play.context.carrier.global_position)}
	_finish()

func _configure_playable() -> void:
	play.persistence_enabled=false

func _key(code: int) -> void:
	var event:=InputEventKey.new()
	event.physical_keycode=code
	event.pressed=true
	Input.parse_input_event(event)
	await process_frame
	event=InputEventKey.new()
	event.physical_keycode=code
	event.pressed=false
	Input.parse_input_event(event)
	await process_frame

func _select_target(id: String) -> bool:
	for i in 8:
		if play.target==id: return _check(true,"Tab reaches actual target",id)
		await _key(KEY_TAB)
	_check(false,"Tab could not select expected target",{"expected":id,"actual":play.target})
	_finish()
	return false

func _fly_to(destination: Vector3) -> bool:
	var right: Vector3=play.camera.global_basis.x
	right.y=0; right=right.normalized()
	var forward: Vector3=-play.camera.global_basis.z
	forward.y=0; forward=forward.normalized()
	for i in 1200:
		var offset: Vector3=destination-play.player.global_position
		var desired: Vector3=(Vector3(offset.x,0,offset.z)*.6-play.player.linear_velocity*.5).limit_length(.45)
		var slow: bool=Vector2(offset.x,offset.z).length()<.3 and play.player.linear_velocity.length()<.35 and absf(offset.y)<.25
		play.inputs.test_frame={"axes":{"right_x":desired.dot(right),"right_y":desired.dot(forward),"left_y":clampf(offset.y*.7,-.35,.35)},"held":["brake"] if slow else []}
		if not await _frame(): return false
		if slow:
			play.inputs.test_frame={"axes":{},"held":["brake"]}
			return _check(true,"actual pilot input reaches observation position",_vec(play.player.global_position))
	_check(false,"pilot input did not reach position within bounded flight",{"actual":_vec(play.player.global_position),"destination":_vec(destination)})
	_finish()
	return false

func _frame() -> bool:
	await physics_frame
	if finished: return false
	if not play.fatal.is_empty() or not logger.errors.is_empty():
		_check(false,"playable scene remains healthy",{"fatal":play.fatal,"errors":logger.errors})
		await _capture("failure-current-camera.png")
		_finish(); return false
	return true

func _capture(filename: String) -> void:
	if output.is_empty(): return
	DirAccess.make_dir_recursive_absolute(output)
	await process_frame
	await RenderingServer.frame_post_draw
	var error: int=root.get_texture().get_image().save_png(output.path_join(filename))
	_check(error==OK,"actual GPU screenshot saved",filename)

func _finish() -> void:
	if finished: return
	finished=true
	_check(logger.errors.is_empty(),"no engine errors",logger.errors)
	if evidence.is_empty() and is_instance_valid(play):
		evidence={"scope":"partial or failed live probe; diagnostic state is not success evidence","bootstrap":play.bootstrap.report(),"player_position":_vec(play.player.global_position),"waiting_controller":play.waiting_report.duplicate(true)}
		if play.boot_ready:
			evidence.rules=play.context.rules.snapshot()
			evidence.carrier_position=_vec(play.context.carrier.global_position)
			evidence.carrier_velocity=_vec(play.context.carrier.linear_velocity)
		if play.executor_ready: evidence.executor=play.executor.report()
		if is_instance_valid(play.workbench): evidence.workbench=play.workbench.report()
	var result: Dictionary={"checks":checks,"failures":failures,"engine_errors":logger.errors,"evidence":evidence}
	if not output.is_empty():
		DirAccess.make_dir_recursive_absolute(output)
		var file:=FileAccess.open(output.path_join("result.json"),FileAccess.WRITE)
		if file!=null: file.store_string(JSON.stringify(result,"  "))
	print("V3_CANAL_PLAYABLE_PROBE "+JSON.stringify(result))
	if is_instance_valid(play): play.free()
	quit(0 if failures.is_empty() else 1)

static func _vec(value: Vector3) -> Array:
	return [value.x,value.y,value.z]
