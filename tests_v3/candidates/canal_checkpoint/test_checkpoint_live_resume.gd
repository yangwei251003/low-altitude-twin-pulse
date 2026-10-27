extends SceneTree
## Short follow-up to the real 57-pass lane-clear F5/F9 site. The prior 51/1
## energy-prerequisite failure is retained in fixture provenance. Public damage
## and fixture initialization are explicit QA, not combat or another job.
## After static restoration, public QA commands produce a separately captured
## moving-device fixture; only that device is rebuilt for a second 5s run.
const World = preload("res://scripts/v3/twin_test_world.gd")
const Restore = preload("res://scripts/v3/candidates/canal_checkpoint/canal_checkpoint_restore.gd")
const Checkpoint = preload("res://scripts/v3/candidates/canal_checkpoint/canal_checkpoint.gd")
const FlightState = preload("res://scripts/v3/candidates/canal_checkpoint/flight_state.gd")
const Rules = preload("res://scripts/v3/candidates/canal_service_loop/canal_service_runtime.gd")
const Cooling = preload("res://scripts/v3/candidates/canal_cooling_station/cooling_station.gd")
const FIXTURE := "res://tests_v3/candidates/canal_checkpoint/evidence/checkpoint_v3_lane_clear_passed_actual.json"
const FIXTURE_SHA := "c02925ec7c6c38c6d2cf3acf841d2b54e265547a5f4faac3f1668718e6d2490f"
const DT := 1.0/60.0
var checks := 0
var failures: Array = []
var evidence: Dictionary = {}
var inputs: Dictionary = {}
var viewport: SubViewport
var world: World
var restorer: RefCounted
var live: Dictionary = {}
var finished := false

class ErrorLog extends Logger:
	var errors: Array = []
	func _log_error(fn: String,file: String,line: int,code: String,reason: String,_notify: bool,kind: int,_traces: Array[ScriptBacktrace]) -> void:
		errors.append({"function":fn,"file":file,"line":line,"code":code,"reason":reason,"kind":kind})
var logger := ErrorLog.new()

func _init() -> void:
	OS.add_logger(logger)
	_run.call_deferred()

func _run() -> void:
	create_timer(35).timeout.connect(func():
		if not finished:
			_check(false,"short live-resume internal timeout")
			_finish())
	for script: Script in [World,Restore,Checkpoint,FlightState]:
		if not _check(script.can_instantiate(),"actual dependency instantiates",{"path":script.resource_path}):
			_finish(); return
	for path: String in [FIXTURE,"res://scripts/v3/candidates/canal_checkpoint/canal_checkpoint_restore.gd","res://scripts/v3/candidates/canal_checkpoint/canal_checkpoint.gd","res://scripts/v3/candidates/canal_checkpoint/flight_state.gd","res://scripts/v3/candidates/canal_checkpoint/history_state.gd","res://scripts/v3/candidates/canal_transport_physics/cargo_custody.gd","res://scripts/v3/candidates/canal_transport_executor/canal_transport_executor.gd","res://scripts/v3/candidates/canal_workbench/workbench.gd","res://scripts/v3/candidates/canal_cooling_station/cooling_station.gd","res://scripts/v3/candidates/canal_service_loop/canal_service_runtime.gd","res://scripts/v2/flight_body.gd","res://scripts/v2/damage_model.gd","res://tests_v3/candidates/canal_checkpoint/test_checkpoint_live_resume.gd"]:
		inputs[path] = FileAccess.get_sha256(path)
	if not _check(Engine.physics_ticks_per_second == 60 and Engine.time_scale == 1.0 and inputs[FIXTURE] == FIXTURE_SHA,"actual lane-clear saved-site bytes and ordinary 60Hz verified"):
		_finish(); return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(FIXTURE))
	if not _check(Checkpoint.validate(parsed).ok,"actual fixture passes complete v3 validation"):
		_finish(); return
	var envelope: Dictionary = parsed.duplicate(true)
	evidence.fixture = {"path":FIXTURE,"sha256":FIXTURE_SHA,"source":"canal-player-checkpoint-20261020_050633_87e6e4/first_saved.json#site","scope":"actual safe checkpoint plus explicitly authored post-result damage/heat fixture, not combat or new work"}
	viewport = SubViewport.new()
	viewport.own_world_3d = true
	viewport.world_3d = World3D.new()
	viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	root.add_child(viewport)
	world = World.new()
	viewport.add_child(world)
	world.build("I2",{},true)
	if not _check(world.build_errors.is_empty(),"actual production I2 builds",{"errors":world.build_errors}):
		_finish(); return
	for i in 3: await physics_frame
	# Only NEW temporary bodies receive one initialization pose. The public hit
	# method uses the actual DamageModel and ZERO impulse direction. The damaged
	# fields are captured before freeing this isolated fixture; no transport body
	# is moved/healed or hit during resumed play.
	var damage_rows: Dictionary = {}
	for key: String in ["carrier","beneficiary"]:
		var owner := Node3D.new()
		world.add_child(owner)
		var id: String = str(envelope.checkpoint[key].id)
		var made: Dictionary = FlightState.create(owner,envelope.checkpoint[key],id,45 if key == "carrier" else 47,world.sample_environment)
		if not _check(made.ok,"fresh explicit damage fixture created",{"code":made.get("code","")}):
			owner.free(); _finish(); return
		var body: RigidBody3D = made.body
		var receipt: Dictionary = body.apply_combat_hit(6.0 if key == "carrier" else 3.0,Vector3.ZERO,body.to_global(Vector3(0,0,.4)),"pulse",{"qa_direct_public_damage":true})
		body.heat = 17.25 if key == "carrier" else 11.5 # Declared fresh thermal initial condition, not an ability claim.
		var row: Dictionary = FlightState.capture(body,id)
		_check(not receipt.is_empty() and row.health < float(parsed.checkpoint[key].health) and row.state.damage.armor < 14.0 and row.state.damage.components.power.health < 32.0 and row.state.damage.serial == 1 and FlightState.validate(row,id),"public damage settlement yields legal nonzero hull armor and component damage",{"body":key,"receipt":receipt,"state":row.state})
		damage_rows[key] = {"receipt":receipt.duplicate(true),"captured":row.duplicate(true)}
		envelope.checkpoint[key] = row
		owner.free()
	evidence.damage_fixture = damage_rows
	if not _check(Checkpoint.validate(envelope).ok and envelope.rules == parsed.rules and envelope.history == parsed.history,"damage fixture preserves original work and sole service ledger"):
		_finish(); return
	# Exercise the actual serialized numeric boundary, not only native Dictionary.
	envelope = JSON.parse_string(JSON.stringify(envelope,"",true,true))
	restorer = Restore.new()
	var prepared: Dictionary = restorer.prepare(world,envelope,world.sample_environment,true)
	if not _check(prepared.ok,"fresh real reconstruction starts",prepared):
		_finish(); return
	var initial_carrier: Dictionary = FlightState.capture(restorer._context.carrier,Rules.CARRIER)
	_check(_numeric_equal(initial_carrier,envelope.checkpoint.carrier),"injured carrier initializes exactly without refilling health armor battery heat or timers",{"expected":envelope.checkpoint.carrier,"actual":initial_carrier})
	var ready: Dictionary = {}
	var trace: Array = []
	for i in 900:
		await physics_frame
		world.clock_seconds += DT
		var state: Dictionary = restorer.tick(DT,true,false)
		if i % 60 == 0 or state.ready or not state.ok: trace.append({"tick":i,"phase":state.phase,"code":state.code,"ready":state.ready})
		if not state.ok:
			_check(false,"injured reconstruction reaches physical ready without fault",state)
			break
		if state.ready:
			ready = state
			break
	evidence.prepare_trace = trace
	if not _check(not ready.is_empty(),"new real contacts and injured anchor holds reach ready",{"trace":trace}):
		_finish(); return
	live = restorer.adopt(true)
	if not _check(live.ok,"current physically verified injured state adopts",{"code":live.get("code","")}):
		_finish(); return
	var adopted_rules: Dictionary = live.context.rules.snapshot()
	var adopted_custody: Dictionary = live.context.custody.docked_snapshot()
	_check(_numeric_equal(adopted_rules,envelope.rules) and _numeric_equal(adopted_custody,envelope.checkpoint.custody),"adoption preserves the original rules ledger and custody sequences")
	evidence.adopted_envelope = live.envelope.duplicate(true)
	var start_device: Dictionary = live.cooling.snapshot()
	var start_axis: Dictionary = live.cooling.snapshot().axis
	var samples: Array = []
	var first_failure: Dictionary = {}
	var tick_count := 0
	var previous_usec := 0
	var maximum_axis_error := 0.0
	var maximum_pose_error := 0.0
	var ids_stable := true
	var state_preserved := true
	var physics_clean := true
	var initial_ids: Array = [live.context.carrier.get_instance_id(),live.workbench.beneficiary.get_instance_id()]
	for id: String in Rules.CASSETTES: initial_ids.append(live.context.cargos[id].get_instance_id())
	for i in 300:
		await physics_frame
		world.clock_seconds += DT
		# Match the actual playable host order: custody/transport, device,
		# sole thermal ledger, then workbench. No controller is ticked twice.
		var moved: Dictionary = live.executor.tick(DT,true,false)
		var pose_before: Dictionary = _device_pose(live.cooling)
		var axis_model = Cooling.Axis.new()
		axis_model.configure(Cooling.axis_config())
		axis_model.restore(live.cooling.snapshot().axis,false)
		var expected_axis: Dictionary = axis_model.preview(DT)
		var cooled: Dictionary = live.cooling.advance(DT,true)
		var next_usec: int = roundi(float(i+1)*1000000.0/60.0)
		var flowed: Dictionary = live.context.rules.step(next_usec-previous_usec,live.cooling.facts(),true,false)
		previous_usec = next_usec
		var worked: Dictionary = live.workbench.advance(DT,true,false)
		tick_count += 1
		if not cooled.ok or not flowed.ok or not moved.ok or not worked.ok:
			first_failure = {"tick":i,"pose_before":pose_before,"pose_after":_device_pose(live.cooling),"cooling":cooled,"rules":flowed,"executor":moved,"workbench":worked}
			break
		var actual_axis: Dictionary = live.cooling.snapshot().axis
		maximum_axis_error = maxf(maximum_axis_error,maxf(absf(float(actual_axis.position_m)-float(expected_axis.position_m)),absf(float(actual_axis.velocity_mps)-float(expected_axis.velocity_mps))))
		var actual_pose: Dictionary = _device_pose(live.cooling)
		maximum_pose_error = maxf(maximum_pose_error,maxf(actual_pose.node_error_m,actual_pose.physics_error_m))
		var balance: Dictionary = live.context.rules.snapshot()
		state_preserved = state_preserved and balance.jobs_completed == adopted_rules.jobs_completed and balance.service_credit == adopted_rules.service_credit and balance.services_consumed == adopted_rules.services_consumed and balance.service_serial == adopted_rules.service_serial and balance.action_serial == adopted_rules.action_serial and balance.pending_action.is_empty() and balance.thermal_ledger.work_added == 25000000 and live.executor.report().receipt_count == 0 and live.workbench.report().receipt.is_empty() and live.workbench.report().measurements.is_empty()
		var current_ids: Array = [live.context.carrier.get_instance_id(),live.workbench.beneficiary.get_instance_id()]
		for id: String in Rules.CASSETTES:
			current_ids.append(live.context.cargos[id].get_instance_id())
			var holder: String = str(envelope.checkpoint.cargos[id].holder)
			physics_clean = physics_clean and balance.cassettes[id].holder == holder and live.context.custody.support_info(id,holder).supported and live.context.custody.report().cargos[id].stable_usec == 350000
		ids_stable = ids_stable and current_ids == initial_ids
		for flight: RigidBody3D in [live.context.carrier,live.workbench.beneficiary]:
			physics_clean = physics_clean and flight.collision_count == 0 and not flight.water_contact and flight.cargo_items.is_empty() and flight.enabled
		if i in [0,59,179,299]: samples.append({"tick":i+1,"rules_revision":balance.revision,"axis":actual_axis.duplicate(true),"device_pose":actual_pose,"carrier":FlightState.capture(live.context.carrier,Rules.CARRIER),"beneficiary":FlightState.capture(live.workbench.beneficiary,Checkpoint.BENEFICIARY_ID),"executor_phase":moved.phase,"workbench_phase":worked.phase})
	evidence.continuation = {"ticks":tick_count,"elapsed_usec":previous_usec,"first_failure":first_failure,"samples":samples,"max_axis_error":maximum_axis_error,"max_pose_error_m":maximum_pose_error,"original_custody":adopted_custody,"final_custody":live.context.custody.docked_snapshot(),"original_rules":adopted_rules,"final_rules":live.context.rules.snapshot()}
	_check(tick_count == 300 and previous_usec == 5000000 and first_failure.is_empty(),"adopted original host chain runs five real seconds without fault",{"ticks":tick_count,"first_failure":first_failure})
	_check(ids_stable and physics_clean,"same two flights and two cargos retain real supports and no water/contact/attachment fault")
	_check(state_preserved,"five seconds do not replay transport/work or duplicate 25kJ result/service credit")
	_check(live.context.custody.docked_snapshot() == adopted_custody,"normal stable continuation preserves physical custody anti-replay counters")
	_check(maximum_axis_error <= 1e-12 and float(start_axis.position_m) == 0.0 and float(start_axis.velocity_mps) == 0.0 and _numeric_equal(live.cooling.snapshot().axis,start_axis),"actual unused saved valve remains stationary without invented motion or replay",{"max_error":maximum_axis_error,"start":start_axis,"end":live.cooling.snapshot().axis})
	_check(maximum_pose_error == 0.0,"each real node and PhysicsServer pose equals the float32 committed axis, including sub-10um steps",{"max_pose_error_m":maximum_pose_error})
	var end_device: Dictionary = live.cooling.snapshot()
	_check(float(start_device.charge) == 0.0 and _numeric_equal(end_device,start_device),"unused real device preserves its exact power revision and observations over five seconds",{"start":start_device,"end":end_device})
	for key: String in ["carrier","beneficiary"]:
		var body: RigidBody3D = live.context.carrier if key == "carrier" else live.workbench.beneficiary
		var after: Dictionary = FlightState.capture(body,str(envelope.checkpoint[key].id))
		var damaged: Dictionary = envelope.checkpoint[key]
		_check(_numeric_equal(after.state.damage,damaged.state.damage) and _numeric_equal(after.health,damaged.health) and _numeric_equal(after.state.damage_taken,damaged.state.damage_taken) and after.state.battery < damaged.state.battery and after.state.battery < 100 and after.state.heat <= damaged.state.heat and after.state.heat > 0,"continued real flight retains original injury and spends rather than refills battery",{"body":key,"before":damaged.state,"after":after.state})
	_check(_numeric_equal(live.workbench.report().restored_history,envelope.history),"historical work/departure remains unchanged during current physical ticks")
	if first_failure.is_empty():
		var unchanged: Dictionary = live.cooling.snapshot().duplicate(true)
		var duplicate: Dictionary = live.cooling.advance(DT,true)
		_check(not duplicate.ok and duplicate.code == "same_physics_frame" and live.cooling.snapshot() == unchanged,"duplicate host tick cannot advance device twice",duplicate)
		await _moving_device_resume()
	_finish()

## This is an explicitly authorized QA device input on the restored host, NOT
## a claim that the player operated this station in the source F5 recording.
## Only Cooling's public commands create motion; no test writes an axis scalar.
func _moving_device_resume() -> void:
	var prior: Dictionary = live.cooling.snapshot()
	var charge_serial: int = int(prior.charge_serial)+1
	var impulse_serial: int = maxi(1,int(prior.axis.last_serial["1"])+1)
	var charged: Dictionary = live.cooling.apply_charge(35.0,charge_serial,true)
	# 0.9 N.s / 2 kg leaves a damped stroke below the 0.28m stop; unlike a
	# maximum stroke it exercises the former sub-10um update failure near 3s.
	var pushed: Dictionary = live.cooling.apply_impulse(Vector3(0,0,.9),impulse_serial,true)
	if not _check(charged.ok and pushed.ok,"public QA station charge and bounded push accept new serials",{"charge":charged,"push":pushed}): return
	await physics_frame
	world.clock_seconds += DT
	var host: Dictionary = _host_step(16667)
	if not _check(host.ok,"same real host advances the commanded valve once",host): return
	var captured: Dictionary = live.cooling.capture_state(Engine.get_physics_frames())
	if not _check(captured.ok,"moving device is captured from the current real physical sample",captured): return
	var native: Dictionary = captured.state.duplicate(true)
	if not _check(float(native.axis.position_m)>float(prior.axis.position_m) and float(native.axis.velocity_mps)>0.0 and native.axis.last_serial["1"]==impulse_serial and native.charge_serial==charge_serial,"movement fixture contains actual displacement velocity and input identities",{"before":prior,"captured":native}): return
	var encoded: String = JSON.stringify(native,"",true,true)
	var parsed: Variant = JSON.parse_string(encoded)
	if not _check(parsed is Dictionary and Cooling.validate_snapshot(parsed).ok and _numeric_equal(parsed,native),"actual moving device JSON preserves values without invented axis state"): return
	var old_station_id: int = live.cooling.get_instance_id()
	live.cooling.free()
	var replacement := Cooling.new()
	live.site.add_child(replacement)
	live.cooling = replacement
	var configured: Dictionary = replacement.configure(live.context.cargos,live.context.berths,live.context.custody,true)
	if not _check(configured.ok,"fresh device binds the existing real supported cargos and custody",configured): return
	var restored: Dictionary = replacement.restore_fresh(parsed,true)
	var restored_state: Dictionary = replacement.snapshot()
	evidence.motion_fixture = {"scope":"Public QA charge/push on restored actual site; device-only fresh reconstruction, not another player action or whole-scene replay","charge_delta":35.0,"impulse_ns":[0,0,.9],"capture_frame":Engine.get_physics_frames(),"captured_state":native,"encoded_device":encoded,"restored_state":restored_state,"old_station_id":old_station_id,"new_station_id":replacement.get_instance_id()}
	if not _check(restored.ok and replacement.get_instance_id()!=old_station_id and _numeric_equal(restored_state,parsed),"fresh physical device restores real saved speed charge and all replay counters",{"restore":restored,"captured":native,"restored":restored_state}): return
	var fresh_pose: Dictionary = _device_pose(replacement)
	_check(fresh_pose.node_error_m == 0.0 and fresh_pose.physics_error_m == 0.0,"fresh node and PhysicsServer equal the captured quantized axis",fresh_pose)
	var replay_charge: Dictionary = replacement.apply_charge(35.0,charge_serial,true)
	var replay_push: Dictionary = replacement.apply_impulse(Vector3(0,0,.9),impulse_serial,true)
	_check(not replay_charge.ok and not replay_push.ok and replacement.snapshot()==restored_state,"reconstructed moving device refuses both old commands without mutation",{"charge":replay_charge,"push":replay_push})
	_check(not replacement.capture_state(Engine.get_physics_frames()).ok,"saved contact observation alone is not a fresh current-frame device sample")
	var before_rules: Dictionary = live.context.rules.snapshot()
	var before_custody: Dictionary = live.context.custody.docked_snapshot()
	var ticks := 0
	var previous_usec := 0
	var micro_steps := 0
	var max_axis_error := 0.0
	var max_pose_error := 0.0
	var ledger_preserved := true
	var first_failure: Dictionary = {}
	var samples: Array = []
	for i in 300:
		await physics_frame
		world.clock_seconds += DT
		var before_axis: Dictionary = replacement.snapshot().axis
		var model = Cooling.Axis.new()
		model.configure(Cooling.axis_config())
		model.restore(before_axis,false)
		var expected: Dictionary = model.preview(DT)
		var next_usec: int = roundi(float(i+1)*1000000.0/60.0)
		var advanced: Dictionary = _host_step(next_usec-previous_usec)
		previous_usec = next_usec
		ticks += 1
		if not advanced.ok:
			first_failure = {"tick":i+1,"host":advanced,"pose":_device_pose(replacement)}
			break
		var actual: Dictionary = replacement.snapshot().axis
		max_axis_error = maxf(max_axis_error,maxf(absf(float(actual.position_m)-float(expected.position_m)),absf(float(actual.velocity_mps)-float(expected.velocity_mps))))
		var delta_position: float = float(actual.position_m)-float(before_axis.position_m)
		if delta_position>0.0 and delta_position<.00001: micro_steps+=1
		var pose: Dictionary = _device_pose(replacement)
		max_pose_error = maxf(max_pose_error,maxf(float(pose.node_error_m),float(pose.physics_error_m)))
		var state: Dictionary = live.context.rules.snapshot()
		ledger_preserved = ledger_preserved and state.jobs_completed==before_rules.jobs_completed and state.service_credit==before_rules.service_credit and state.services_consumed==before_rules.services_consumed and state.service_serial==before_rules.service_serial and state.action_serial==before_rules.action_serial and state.pending_action.is_empty() and state.thermal_ledger.work_added==25000000 and live.executor.report().receipt_count==0 and live.workbench.report().receipt.is_empty() and live.context.custody.docked_snapshot()==before_custody
		if i in [0,59,179,299]: samples.append({"tick":i+1,"axis":actual,"pose":pose,"host":advanced})
	var end: Dictionary = replacement.snapshot()
	evidence.moving_continuation = {"ticks":ticks,"elapsed_usec":previous_usec,"first_failure":first_failure,"max_axis_error":max_axis_error,"max_pose_error_m":max_pose_error,"sub_10um_steps":micro_steps,"start":restored_state,"end":end,"samples":samples}
	_check(ticks==300 and previous_usec==5000000 and first_failure.is_empty(),"reconstructed moving valve completes five seconds of the actual host chain",evidence.moving_continuation)
	_check(max_axis_error<=1e-12 and float(end.axis.position_m)>float(restored_state.axis.position_m) and float(end.axis.velocity_mps)<float(restored_state.axis.velocity_mps) and end.axis.last_serial==restored_state.axis.last_serial,"real moving cooling valve continues original damped velocity and replay sequence",{"max_error":max_axis_error,"start":restored_state.axis,"end":end.axis})
	_check(micro_steps>0 and max_pose_error==0.0,"sub-10um real axis updates keep node and PhysicsServer synchronized",{"sub_10um_steps":micro_steps,"max_pose_error_m":max_pose_error})
	_check(end.charge==restored_state.charge and end.charge_serial==restored_state.charge_serial and end.revision>restored_state.revision and end.paused==restored_state.paused,"device keeps original power/action state while advancing its real mechanism",{"start":restored_state,"end":end})
	_check(ledger_preserved,"moving-device reconstruction never repeats custody work or service results")
	if first_failure.is_empty():
		var current: Dictionary = replacement.capture_state(Engine.get_physics_frames())
		_check(current.ok and _numeric_equal(current.get("state",{}),end),"real current support permits capture after moving-device continuation",current)
		# Adversarial test only AFTER the public-input/rebuild/continuation chain.
		# This intentionally illegal 1mm move must still be rejected, not repaired.
		replacement.valve.global_position += Vector3(0,0,.001)
		var refused: Dictionary = replacement.advance(DT,true)
		evidence.unauthorized_move = {"pose":_device_pose(replacement),"result":refused}
		_check(not refused.ok and refused.code=="valve_pose_changed" and replacement.snapshot()==end,"external 1mm valve displacement remains rejected and cannot rewrite axis state",evidence.unauthorized_move)

func _host_step(delta_usec: int) -> Dictionary:
	var moved: Dictionary = live.executor.tick(DT,true,false)
	var cooled: Dictionary = live.cooling.advance(DT,true)
	var flowed: Dictionary = live.context.rules.step(delta_usec,live.cooling.facts(),true,false)
	var worked: Dictionary = live.workbench.advance(DT,true,false)
	return {"ok":moved.ok and cooled.ok and flowed.ok and worked.ok,"executor":moved,"cooling":cooled,"rules":flowed,"workbench":worked}

func _device_pose(device: Node3D) -> Dictionary:
	var axis: Dictionary = device.snapshot().axis
	var expected: Vector3 = Cooling.VALVE_CLOSED+Vector3(0,0,float(axis.position_m))
	var actual: Transform3D = PhysicsServer3D.body_get_state(device.valve.get_rid(),PhysicsServer3D.BODY_STATE_TRANSFORM)
	return {"axis":axis.duplicate(true),"expected":FlightState.xyz(expected),"node":FlightState.xyz(device.valve.global_position),"physics":FlightState.xyz(actual.origin),"node_error_m":device.valve.global_position.distance_to(expected),"physics_error_m":actual.origin.distance_to(expected)}

func _numeric_equal(a: Variant,b: Variant) -> bool:
	if (a is int or a is float) and (b is int or b is float): return is_finite(float(a)) and is_finite(float(b)) and absf(float(a)-float(b))<=1e-12
	if a is Dictionary and b is Dictionary:
		if a.size()!=b.size(): return false
		for key: Variant in a:
			if not b.has(key) or not _numeric_equal(a[key],b[key]): return false
		return true
	if a is Array and b is Array:
		if a.size()!=b.size(): return false
		for i in a.size():
			if not _numeric_equal(a[i],b[i]): return false
		return true
	return typeof(a)==typeof(b) and a==b

func _check(ok: bool,label: String,details: Dictionary={}) -> bool:
	checks+=1
	if not ok: failures.append({"label":label,"details":details.duplicate(true)})
	return ok

func _finish() -> void:
	if finished: return
	finished=true
	for path: String in inputs: _check(FileAccess.get_sha256(path)==inputs[path],"input bytes unchanged: "+path)
	_check(logger.errors.is_empty(),"no engine errors",{"errors":logger.errors})
	var result: Dictionary={"checks":checks,"failures":failures,"engine_errors":logger.errors,"evidence":evidence,"input_sha256":inputs,"scope":"actual saved fixture; declared public DamageModel settlement; fresh site restore and 5s static-device host continuation; public QA device commands and captured device-only fresh reconstruction plus 5s moving continuation; no Store, combat-play or service-consumption claim"}
	if not live.is_empty() and live.get("ok",false):
		live.executor.close(true)
		live.workbench.close(true)
	elif restorer!=null: restorer.discard()
	if is_instance_valid(viewport): viewport.free()
	print("V3_CHECKPOINT_LIVE_RESUME "+JSON.stringify(result))
	quit(0 if failures.is_empty() and logger.errors.is_empty() else 1)
