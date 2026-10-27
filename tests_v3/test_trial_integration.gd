extends "res://tests_v3/test_distribution_session.gd"
## Actual MAIN, Session abilities, nearest-marker G dispatch, Store and region
## transitions. Prior 27 goals and starting pilot placements are explicit QA
## fixtures. No assigned water/sample/Link pose, sockets, GPU or playtime claim.
const Trial = preload("res://scripts/v3/gameplay/twin_trial_session.gd")
const Station = Trial.Assembly.Station
const Link = Trial.Assembly.Link
const Runtime = Trial.Runtime
var expect_trial_save_failure := false

func _run() -> void:
	var count := 0
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--qa-profile="):
			profile=arg.trim_prefix("--qa-profile=")
			count+=1
		elif arg.begins_with("--qa-network") or arg.begins_with("--qa-capture") or arg.begins_with("--qa-suite"):
			check(false,"refuse unrelated automatic drivers")
	if count!=1 or not profile.begins_with("qa_trial_integration_") or profile!=profile.validate_filename():
		check(false,"require a fresh qa_trial_integration_ profile")
	base="user://qa_v3_trial_integration/"+profile
	if DirAccess.dir_exists_absolute(base) or DirAccess.dir_exists_absolute("user://profiles_v3/"+profile):
		check(false,"refuse existing test/profile paths")
	if not failures.is_empty():
		_finish(2)
		return
	create_timer(120).timeout.connect(func():
		if not done:
			check(false,"bounded MAIN trial integration timeout")
			_finish(2))
	session=MAIN.instantiate()
	if not _main_usable():
		check(false,"MAIN retains its complete Session implementation")
		_finish(1)
		return
	root.add_child(session)
	if not _disable_callbacks():
		_finish(1)
		return
	check(session.start_flight("solo"),"fresh actual MAIN starts solo")
	if _healthy() and _seed_history():
		await _travel("I2")
		if _healthy(): await _sample_via_session()
		if _healthy(): await _pending_read_and_return()
		if _healthy(): await _branch_and_restore()
	_finish(0 if failures.is_empty() else 1)

func _steps(count: int, delta: float = DT) -> void:
	for unused in range(count):
		if not _healthy(): return
		await physics_frame
		session._physics_process(delta)
		for name in ["clinic","distribution","trial","shared_access"]:
			var adapter=session.get(name)
			if str(adapter.error).is_empty(): continue
			if name=="trial" and expect_trial_save_failure and adapter.error=="trial_observation_save_failed" and adapter.has_pending_observation(): continue
			check(false,"production "+name+" advance rejected",adapter.error)
			return

func _volumes() -> Array:
	var nodes: Dictionary=session.trial.module.station.snapshot().runtime.simulation.nodes
	var result: Array=[]
	for id in [Runtime.SOURCE,Runtime.RECEIVER_A,Runtime.RECEIVER_B]:
		result.append(int(nodes[id].clean_ml)+int(nodes[id].dirty_ml))
	return result

func _read_at(point: Vector3, marker: String) -> void:
	await _place(point)
	check(_body_clear(),"actual pilot is outside solid geometry before "+marker)
	check(session.story.nearest(point)==marker,"real nearest-marker dispatcher selects "+marker,{"actual":session.story.nearest(point)})
	if _healthy(): _g()

func _sample_via_session() -> void:
	phase="real_controls_and_first_samples"
	check(session.trial.ready and session.world.trial==session.trial.module and session.trial.module.connection_status().ok,"World owns the same connected production Trial assembly adopted by Session")
	check(_volumes()==[200000,0,0] and session.trial.observed_gauges()=={"A":{},"B":{}},"new I2 starts with its bounded 200L and no invented knowledge")
	check(session.trial.committed_flow_fact().is_empty(), "unobserved apparatus supplies no investigation fact")
	await _read_at(Vector3(16.85,2,-.6),Trial.GAUGE_A)
	check(session.trial_gauge.readings_snapshot().readings.get(Runtime.RECEIVER_A,{}).get("volume_ml")==0 and session.trial.observed_gauges().A.is_empty(),"real G displays the empty A window without creating completed-sample history")
	if not _healthy(): return
	await _fork("before_trial_samples")
	await _place(Vector3(16,1.3,-5.3))
	check(_body_clear(),"Link control approach is physically unoccupied in production I2")
	if not await _ability("push_pull",Link.HANDLE,"push"): return
	await _steps(18)
	check(session.trial.module.link.status().phase=="trial","Session push moves the real isolation interlock into settled TRIAL pose",session.trial.module.link.status())
	if not _healthy(): return
	await _place(Vector3(18,2.5,-.5))
	check(_body_clear(),"relay/controller approach clears full production geometry")
	if not await _ability("charge",Station.RELAY): return
	if not await _ability("takeover",Station.CONTROLLER): return
	for unused in range(160):
		await _steps(1,.05)
		if not _healthy(): return
		var status: Dictionary=session.trial.module.station.status()
		if status.both_samples_recorded and status.selector_position==0.0: break
	check(_volumes()==[160000,20000,20000] and session.trial.module.station.status().both_samples_recorded,"actual Session ability lifecycle produces two real 20L samples and conserves the initial 200L",session.trial.module.station.status())
	check(session.trial.committed_flow_fact().is_empty(), "two full physical tanks do not replace two saved G readings")

func _pending_read_and_return() -> void:
	phase="g_read_save_failure_and_real_return"
	var baseline: Dictionary=session.store.snapshot()
	session.store.failure_point="before_publish"
	expect_trial_save_failure=true
	await _read_at(Vector3(16.85,2,-.6),Trial.GAUGE_A)
	check(session.trial.has_pending_observation() and session.trial.observed_gauges().A.is_empty() and session.store.snapshot()==baseline,"failed real Store write keeps G reading pending without publishing history")
	check(session.trial.committed_flow_fact().is_empty(), "unsaved reading cannot manufacture a story fact")
	if not _healthy(): return
	var original_read: Dictionary=session.trial.pending_observation.A.duplicate(true)
	check(original_read.volume_ml==20000 and original_read.sample.destination==Runtime.RECEIVER_A,"pending first observation records actual A water and opposite selector sample")
	await _read_at(Vector3(18,1.35,-.5),Trial.RETURN_SWITCH)
	for unused in range(100):
		await _steps(1,.05)
		if not _healthy(): return
		if _volumes()==[200000,0,0]: break
	check(_volumes()==[200000,0,0] and session.trial.pending_observation.A==original_read,"G return pumps existing water back while the first unsaved reading remains immutable")
	session.store.failure_point=""
	expect_trial_save_failure=false
	var current_pair: Dictionary=session.trial.module.snapshot()
	check(session._save_environment(),"production environment save retries the pending actual read")
	check(session.trial.module.snapshot()==current_pair and session.trial.observed_gauges().A==original_read,"retry saves present mechanism plus historical observation without rewinding")
	check(session.trial.committed_flow_fact().is_empty(), "one saved window cannot establish both routes")
	var disk=Store.new(session.store.root_path)
	check(disk.load_profile().ok and session.store.matches_persisted_value(session.trial.persistent_state(),disk.snapshot().world.environment.I2_trial_flow),"independent disk readback restores the complete production trial envelope")
	await _read_at(Vector3(19.15,2,-.6),Trial.GAUGE_B)
	check(session.trial.observed_gauges().B.get("volume_ml")==0 and session.trial.observed_gauges().B.get("sample",{}).get("moved_ml")==20000,"G may read current empty B after return while preserving its completed first 20L sample",session.trial.observed_gauges().B)
	check(session.trial_gauge.readings_snapshot().readings.get(Runtime.RECEIVER_B,{}).get("volume_ml")==0,"readout shows actual empty B rather than historical sample volume")
	check(session.trial.committed_flow_fact().get("option") == "pulse_trial", "both saved first samples provide the actual pulse method even after return")
	var without_history: Dictionary = session.store.snapshot().world.duplicate(true)
	without_history.environment.erase("I2_trial_flow")
	without_history.completed_objectives.append(Trial.TRACE_OBJECTIVE)
	check(not session.trial.prepare(without_history, "I2", true).ok, "committed trace without mechanism history cannot silently initialize")
	check(session.store.snapshot().personal==original_personal and _same(session.story.state,history_fixture),"mechanical experiments and readouts create no premature action or personal reward")

func _branch_and_restore() -> void:
	phase="region_and_branch_restore"
	check(session._save_environment(),"save the current trial before leaving")
	var saved: Dictionary=session.store.snapshot().world.environment.I2_trial_flow.duplicate(true)
	await _travel("I1")
	if not _healthy(): return
	check(session.trial.module==null and session.trial_gauge.readings_snapshot().readings.is_empty(),"leaving I2 removes local mechanisms and clears the ephemeral gauge display")
	var outside: Dictionary=session.trial.persistent_state()
	check(_same(_physical_history(saved),_physical_history(outside)),"departure preserves every physical/water/clock/observation field; only roster replay counters are reset")
	await _steps(3)
	check(session.trial.persistent_state()==outside,"off-region steps preserve the entire retained state including all serials")
	await _travel("I2")
	check(session.trial.ready and _same(_physical_history(session.trial.persistent_state()),_physical_history(saved)),"returning to I2 reconstructs both real mechanisms and first readings")
	check(session.trial.module.link.snapshot().axis.last_serial=={"1":-1} and session.trial.module.station.snapshot().axis.last_serial=={"1":-1},"new local pilot cannot inherit accepted action serials from the departed roster")
	await _switch("before_trial_samples")
	check(session.trial.ready and session.trial.observed_gauges()=={"A":{},"B":{}} and _volumes()==[200000,0,0] and session.trial.module.link.status().phase=="normal","independent prior branch restores its actual untested mechanism and no later observations")
	check(session.trial.committed_flow_fact().is_empty(), "earlier branch has no later physical evidence")
	await _switch("main")
	check(session.trial.ready and _same(_physical_history(session.trial.persistent_state()),_physical_history(saved)),"switching back restores the committed physical state and knowledge without repeating rewards",_difference(_physical_history(saved),_physical_history(_disk(session.trial.persistent_state()))))
	check(int(session.trial.module.link.snapshot().serial)>=int(saved.link.serial) and int(session.trial.module.station.snapshot().serial)>=int(saved.station.serial),"authority reconstruction never decreases mechanism serials")
	check(session.store.snapshot().personal==original_personal and _same(session.story.state,history_fixture),"branch and region changes preserve existing story and personal results")

func _physical_history(envelope: Dictionary) -> Dictionary:
	# Re-entering a region creates a NEW actor roster. Its accepted input sequence
	# and mechanism publication serial must change; water, geometry, flow-credit,
	# first samples and observations must remain exactly the same. Exclude only
	# these three explicit transport/lifecycle fields, with separate checks above.
	var copy: Dictionary=envelope.duplicate(true)
	for part in ["link","station"]:
		copy[part].erase("serial")
		copy[part].axis.erase("last_serial")
	return copy

func _finish(code: int) -> void:
	if done: return
	done=true
	if is_instance_valid(session):
		session.active=false
		session.network.close()
		session.free()
	if not error_logger.errors.is_empty(): code=1
	print("TRIAL_INTEGRATION checks=%d failures=%d profile=%s" % [checks.size(),failures.size(),profile])
	print("TRIAL_INTEGRATION_RESULT "+JSON.stringify({"passed":code==0,"checks":checks,"failures":failures,"engine_errors":error_logger.errors,"limits":["Prior27 goals and pilot placements are explicit fixtures, not a playthrough.","Actual MAIN and native G dispatcher with controlled physics; no ENet, graphics, human timing or performance acceptance."]}))
	OS.remove_logger(error_logger)
	quit(code)

func _difference(a: Variant,b: Variant,path: String="") -> Array:
	var result: Array=[]
	if a is Dictionary and b is Dictionary:
		for key in a:
			if not b.has(key): result.append({"path":path+"/"+str(key),"missing":true})
			else: result.append_array(_difference(a[key],b[key],path+"/"+str(key)))
		for key in b:
			if not a.has(key): result.append({"path":path+"/"+str(key),"extra":true})
	elif a!=b: result.append({"path":path,"expected":a,"actual":b})
	return result
