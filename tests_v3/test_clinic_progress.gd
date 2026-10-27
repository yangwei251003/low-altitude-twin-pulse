extends SceneTree
## Pure rule/history fixtures only. Uses the actual hydraulic runtime, but no
## Waterworks scene/physics, Session, Store, network or completed player journey.
const Progress = preload("res://scripts/v3/gameplay/actions/twin_clinic_progress.gd")
const Runtime = preload("res://scripts/v3/environment/twin_clinic_water_runtime.gd")
var checks := 0
var failures: Array = []
class TestLogger extends Logger:
	var errors: Array = []
	var guard := Mutex.new()
	func _log_error(function: String, file: String, line: int, code: String, rationale: String, _editor_notify: bool, error_type: int, _script_backtraces: Array[ScriptBacktrace]) -> void:
		guard.lock()
		errors.append({"function":function,"file":file,"line":line,"code":code,"rationale":rationale,"type":error_type})
		guard.unlock()
var error_logger := TestLogger.new()

func _init() -> void:
	OS.add_logger(error_logger)
	_run.call_deferred()

func _check(ok: bool, label: String, detail: Variant = null) -> void:
	checks+=1
	if not ok: failures.append({"check":label,"detail":detail})

func _rig(route: String = "gravity") -> Dictionary:
	var water = Runtime.new()
	_check(water.load_definition().ok,"fixture loads unchanged production water definition")
	return {"water":water,"progress":Progress.new(),"serial":0,"route":route,"blocked":false}

func _mechanism(rig: Dictionary) -> Dictionary:
	var runtime: Dictionary = rig.water.snapshot()
	return {"schema_version":2,"serial":int(rig.serial),"runtime":runtime,
		"gravity_fraction":1.0 if int(runtime.facts.gravity_open_permille)>0 else 0.0,
		"pump_fraction":1.0 if int(runtime.facts.pump_open_permille)>0 else 0.0,
		"pump_latched":int(runtime.facts.pump_open_permille)>0,"powered":bool(runtime.facts.pump_powered),"platform_blocked":bool(runtime.facts.platform_blocked)}

func _status(rig: Dictionary, top_error: float = 0.0) -> Dictionary:
	var status: Dictionary = rig.water.status()
	status.deck_top_y=float(status.desired_deck_top_m)+top_error
	return status

func _advance(rig: Dictionary, delta: float = 0.25, access: bool = true, top_error: float = 0.0) -> Dictionary:
	var before := _mechanism(rig)
	var facts := {"gravity_open_permille":1000 if rig.route=="gravity" else 0,
		"pump_open_permille":1000 if rig.route=="pump" else 0,"pump_powered":rig.route=="pump","platform_blocked":bool(rig.blocked)}
	var step: Dictionary = rig.water.step(delta,facts)
	if step.ok and delta>0: rig.serial=int(rig.serial)+1
	var after := _mechanism(rig)
	var status := _status(rig,top_error)
	var observed: Dictionary = rig.progress.observe(delta,before,after,status,step,access)
	return {"before":before,"after":after,"status":status,"step":step,"observed":observed}

func _fill(rig: Dictionary) -> void:
	var all_valid := true
	for unused in range(1000):
		if int(rig.water.status().clinic_volume_ml)==Runtime.TARGET_ML: break
		var row := _advance(rig,0.1)
		all_valid=all_valid and bool(row.observed.ok)
	_check(all_valid and int(rig.water.status().clinic_volume_ml)==Runtime.TARGET_ML,"real rule ticks reach cutoff with valid per-step history")

func _envelope(rig: Dictionary) -> Dictionary:
	return {"version":1,"mechanism":_mechanism(rig),"history":rig.progress.snapshot()}

func _run() -> void:
	_test_restore_missing()
	for route in ["gravity","pump"]: _test_route(route)
	_test_observation_guards()
	_test_stability_conditions()
	_test_restore_guards()
	_test_reliable_history()
	print("V3_CLINIC_PROGRESS_TESTS "+JSON.stringify({"checks":checks,"failures":failures,"engine_errors":error_logger.errors,"scope":"pure history with real hydraulic rule transitions; mechanism/status/access are explicit host-boundary fixtures, not physical validation or gameplay"}))
	var failed: bool = not failures.is_empty() or not error_logger.errors.is_empty()
	OS.remove_logger(error_logger)
	quit(1 if failed else 0)

func _test_reliable_history() -> void:
	var rig := _rig()
	_advance(rig)
	var envelope := _envelope(rig)
	var observer = Progress.new()
	var permit: Dictionary = observer.prepare_restore(envelope,[],{})
	_check(observer.adopt_reliable_history(envelope.history,envelope.mechanism) and observer.snapshot()==rig.progress.snapshot(),"bound reliable mechanism and its full observed history are adopted together without waiting for Story")
	_check(not observer.adopt_restore(permit),"network adoption invalidates an older disk restore permit")
	var initial: Dictionary = observer.snapshot()
	var invalid: Dictionary = envelope.history.duplicate(true)
	invalid.observed_serial+=1
	_check(not observer.adopt_reliable_history(invalid,envelope.mechanism) and observer.snapshot()==initial,"invalid reliable history is rejected without changing live history")
	var mechanism: Dictionary = envelope.mechanism.duplicate(true)
	mechanism.runtime.simulation.nodes[Progress.CLINIC].clean_ml+=1
	_check(not observer.adopt_reliable_history(envelope.history,mechanism) and observer.snapshot()==initial,"history adoption cannot hide nonconserved water")
	envelope.history.first_transfer.clean_ml+=1
	_check(observer.snapshot()==initial,"adopted history never aliases the incoming packet")

func _test_restore_missing() -> void:
	var progress = Progress.new()
	var initial: Dictionary = progress.snapshot()
	var prepared: Dictionary = progress.prepare_restore(null,["I1:underdeck:read"],{"opening:underdeck_latched":true})
	_check(prepared.ok and prepared.needs_init and prepared.history==initial and progress.snapshot()==initial,"old world without I2 state/results may initialize without mutating live history")
	var changed: Dictionary = prepared.duplicate(true)
	changed.history.observed_serial=10
	_check(not progress.adopt_restore(changed) and progress.snapshot()==initial,"edited prepared history cannot be adopted")
	_check(progress.adopt_restore(prepared) and not progress.adopt_restore(prepared),"restore permit adopts once only")
	var live_flags: Dictionary = {}
	live_flags.I1_gate = true
	_check(typeof(live_flags.keys()[0])==TYPE_STRING_NAME,"live world dot assignment exercises StringName key")
	_check(progress.prepare_restore(null,[],live_flags).ok,"valid in-memory travel flag is compatible with restored JSON flags")
	_check(not progress.prepare_restore(null,[],{7:true}).ok,"numeric flag keys remain invalid")
	_check(not progress.prepare_restore(null,[],{&"I2:unknown":true}).ok,"interned unknown clinic flags remain invalid")
	_check(not progress.prepare_restore(null,[],{StringName(Progress.READY_FLAG):1}).ok,"interned clinic flag still requires boolean value")
	for saved in [{},[],{"version":1},false]:
		var rejected: Dictionary = progress.prepare_restore(saved,[],{})
		_check(not rejected.ok and progress.snapshot()==initial,"present malformed state is not treated as an old missing state")
	for row in [[[Progress.DIAGNOSE],{}],[[],{Progress.READY_FLAG:true}],[[Progress.DIAGNOSE,Progress.CONNECT],{}]]:
		_check(not progress.prepare_restore(null,row[0],row[1]).ok,"missing I2 state with any existing achievement fails closed")
	_check(not progress.prepare_restore(null,[Progress.CONNECT],{}).ok,"story prerequisites are checked before allowing restore")
	_check(not progress.prepare_restore(null,[],{Progress.READY_FLAG:1}).ok,"ready flag must be a real boolean")
	_check(progress.fact_for(Progress.DIAGNOSE).is_empty() and progress.fact_for(Progress.CONFIRM).is_empty() and progress.fact_for("unknown").is_empty(),"manual/unknown objectives never receive automatic facts")

func _test_route(route: String) -> void:
	var rig := _rig(route)
	var first := _advance(rig)
	var history: Dictionary = rig.progress.snapshot()
	_check(first.observed.ok and history.route_method==route and int(history.first_transfer_ml)==int(first.step.moved_ml) and history.first_transfer.source_id==Runtime.SOURCE and history.first_transfer.destination_id==Runtime.CLINIC,"first true source/destination transfer records route before diagnosis",first.observed)
	_check(rig.progress.fact_for(Progress.CONNECT)=={"kind":"fact","target":"I2:clinic_feed","option":route},"stored first route supplies shared connect evidence")
	var restarted = Progress.new()
	var prepared: Dictionary = restarted.prepare_restore(JSON.parse_string(JSON.stringify(_envelope(rig))),[],{})
	_check(prepared.ok and restarted.adopt_restore(prepared) and restarted.snapshot().route_method==route,"save/restore preserves early operation before any objective completed")
	rig.progress=restarted
	# Changing the current valid inlet later must not rewrite the first method.
	rig.route="pump" if route=="gravity" else "gravity"
	var switched := _advance(rig)
	_check(switched.observed.ok and rig.progress.snapshot().route_method==route and rig.progress.snapshot().first_transfer==history.first_transfer,"later route changes preserve original transfer receipt")
	_fill(rig)
	_check(rig.progress.snapshot().stable_usec==0,"last filling interval is not credited as a whole stable interval")
	var historical: int = rig.water.status().last_tick_transfer_ml
	_check(historical>0,"fixture retains actual stale last-tick transfer at cutoff")
	for unused in range(7): _advance(rig)
	_check(rig.progress.snapshot().stable_usec==1750000 and rig.progress.fact_for(Progress.STABILIZE).is_empty(),"1.75 seconds cannot satisfy 2-second stability")
	var last := _advance(rig)
	_check(last.observed.ok and rig.progress.snapshot().stable_usec==2000000 and rig.progress.snapshot().stabilized_once and not rig.progress.fact_for(Progress.STABILIZE).is_empty(),"stable readiness uses this interval's exact zero transfer, not historical last_tick_transfer")
	var before: Dictionary = rig.progress.snapshot()
	var duplicate: Dictionary = rig.progress.observe(0.25,last.before,last.after,last.status,last.step,true)
	_check(not duplicate.ok and rig.progress.snapshot()==before,"duplicate serial transition cannot accumulate stability twice")
	var state := _mechanism(rig)
	_check(rig.progress.observe(0.25,state,state,_status(rig),{"ok":true,"moved_ml":0},true,true,true).ok and rig.progress.snapshot()==before,"explicit paused observation adds no simulated time")
	var paused_before: Dictionary = state.duplicate(true)
	paused_before.gravity_speed=1.0
	var paused_after: Dictionary = state.duplicate(true)
	paused_after.gravity_speed=0.0
	_check(rig.progress.observe(0.0,paused_before,paused_after,_status(rig),{"ok":true},true).ok and rig.progress.snapshot()==before,"legitimate host pause may cancel velocity while leaving water/pose/history unchanged")
	var confirm: Dictionary = rig.progress.prepare_confirm(state,_status(rig),true)
	_check(confirm.ok and confirm.history.commissioned and not rig.progress.snapshot().commissioned,"confirmation builds a candidate without publishing commission")
	# Simulated failed external transaction: deliberately do not adopt anything.
	_check(rig.progress.snapshot()==before and rig.progress.prepare_confirm(state,_status(rig),true).ok,"failed external save leaves live history uncommissioned and retryable")
	var altered: Dictionary = confirm.duplicate(true)
	altered.history.first_transfer_ml+=1
	_check(not rig.progress.adopt_confirm(altered) and rig.progress.snapshot()==before,"edited confirmation candidate rejected atomically")
	_check(rig.progress.adopt_confirm(confirm) and rig.progress.snapshot().commissioned and not rig.progress.adopt_confirm(confirm),"external successful transaction may adopt confirmation exactly once")
	var full := [Progress.DIAGNOSE,Progress.CONNECT,Progress.STABILIZE,Progress.CONFIRM]
	_check(rig.progress.prepare_restore(_envelope(rig),full,{Progress.READY_FLAG:true}).ok,"commissioned history agrees with completed objectives and durable flag")
	_check(rig.progress.prepare_restore(_envelope(rig),full,{StringName(Progress.READY_FLAG):true}).ok,"interned commissioned flag preserves the same history contract")
	_check(not rig.progress.prepare_restore(_envelope(rig),full,{}).ok and not rig.progress.prepare_restore(_envelope(rig),[],{Progress.READY_FLAG:true}).ok,"world disk restore rejects mismatch on either completion or flag")
	var blocked := _advance(rig,0.25,false)
	_check(blocked.observed.ok and rig.progress.snapshot().stable_usec==0 and rig.progress.snapshot().stabilized_once and rig.progress.snapshot().commissioned,"later blocked resident route clears current timer without revoking durable commissioning")
	_check(rig.progress.prepare_restore(_envelope(rig),full,{Progress.READY_FLAG:true}).ok,"temporarily obstructed but previously completed world remains a legitimate save")
	_check(rig.progress.validate_history(rig.progress.snapshot(),_mechanism(rig)).ok,"network internal validation does not require Story packet ordering")
	var copy: Dictionary = rig.progress.snapshot()
	copy.first_transfer.source_before.clean_ml=0
	_check(rig.progress.snapshot().first_transfer.source_before.clean_ml!=0,"nested history access returns independent copies")

func _test_observation_guards() -> void:
	var rig := _rig()
	var row := _advance(rig)
	for kind in ["moved","source","isolated","serial","clock","route","status","unaccepted","authority","access"]:
		var observer = Progress.new()
		var before: Dictionary = row.before.duplicate(true)
		var after: Dictionary = row.after.duplicate(true)
		var status: Dictionary = row.status.duplicate(true)
		var result: Dictionary = row.step.duplicate(true)
		var authority := true
		var access: Variant = true
		match kind:
			"moved": result.moved_ml+=1
			"source": after.runtime.simulation.nodes[Runtime.SOURCE].clean_ml+=1
			"isolated":
				after.runtime.simulation.nodes[Progress.RAIN].clean_ml-=1
				after.runtime.simulation.nodes[Progress.WASTE].clean_ml+=1
			"serial": after.serial+=1
			"clock": after.runtime.pending_usec+=1
			"route": after.runtime.facts.gravity_open_permille=0
			"status": status.clinic_volume_ml+=1
			"unaccepted": result.ok=false
			"authority": authority=false
			"access": access=1
		var original: Dictionary = observer.snapshot()
		var rejected: Dictionary = observer.observe(0.25,before,after,status,result,access,authority)
		_check(not rejected.ok and observer.snapshot()==original,"malformed host evidence is rejected atomically: "+kind,rejected)
	for delta in [-0.1,0.251,INF,NAN]:
		var observer = Progress.new()
		_check(not observer.observe(delta,row.before,row.after,row.status,row.step,true).ok and observer.snapshot().first_transfer_ml==0,"invalid observation delta never records a route")
	var observer = Progress.new()
	_check(not observer.observe(0.0,row.before,row.after,row.status,row.step,true).ok,"zero delta cannot smuggle a real transfer")
	_check(observer.prepare_restore(_envelope(rig),[],{}).ok,"current valid envelope can be prepared")
	var prepared: Dictionary = observer.prepare_restore(_envelope(rig),[],{})
	observer.prepare_restore({},[],{})
	_check(not observer.adopt_restore(prepared),"failed newer restore preparation invalidates old adoption permit")

func _test_stability_conditions() -> void:
	var rig := _rig()
	_fill(rig)
	for unused in range(4): _advance(rig)
	_check(rig.progress.snapshot().stable_usec==1000000,"explicit stable clock reaches one second")
	_check(_advance(rig,0.25,true,0.01).observed.ok and rig.progress.snapshot().stable_usec==0,"hydraulic setpoint alone cannot replace actual deck height")
	for unused in range(4): _advance(rig)
	_check(_advance(rig,0.25,false).observed.ok and rig.progress.snapshot().stable_usec==0,"missing actual 3m route clears continuous stability")
	for unused in range(4): _advance(rig)
	rig.blocked=true
	_check(_advance(rig).observed.ok and rig.progress.snapshot().stable_usec==0,"explicit platform obstruction clears continuous stability")
	rig.blocked=false
	for unused in range(120): _advance(rig,1.0/60.0)
	_check(rig.progress.snapshot().stable_usec==2000000,"60Hz fractional microseconds reach two seconds without per-frame rounding drift")
	_check(not rig.progress.prepare_confirm(_mechanism(rig),_status(rig),false).ok,"confirmation rechecks current physical access")
	var candidate: Dictionary = rig.progress.prepare_confirm(_mechanism(rig),_status(rig),true)
	_advance(rig,0.01)
	_check(not rig.progress.adopt_confirm(candidate) and not rig.progress.snapshot().commissioned,"stale pre-save confirmation cannot overwrite a newer observation")
	# Explicit conserved contamination fixture, not a real player pollution path.
	for clean_fraction in [0.94,0.95]:
		var mixed := _rig()
		var saved: Dictionary = mixed.water.snapshot()
		var dirty := int(3200000.0*(1.0-clean_fraction))
		saved.simulation.nodes[Runtime.SOURCE].clean_ml-=dirty
		saved.simulation.nodes[Runtime.SOURCE].dirty_ml+=dirty
		saved.simulation.nodes[Progress.RAIN].clean_ml+=dirty
		saved.simulation.nodes[Progress.RAIN].dirty_ml-=dirty
		_check(mixed.water.restore(saved).ok,"mixed source fixture keeps both global components conserved")
		_fill(mixed)
		for unused in range(8): _advance(mixed)
		var actual: float = mixed.water.status().clean_fraction
		_check((int(mixed.progress.snapshot().stable_usec)==Progress.STABLE_USEC)==(actual>=0.95),"95-percent component threshold uses actual mixed integer quantities",actual)

func _test_restore_guards() -> void:
	var rig := _rig()
	_advance(rig)
	var envelope := _envelope(rig)
	for kind in ["version","extra","history_missing","route","amount","node","component","serial","fraction","ready","water","historyless"]:
		var bad: Dictionary = envelope.duplicate(true)
		match kind:
			"version": bad.version=2
			"extra": bad.extra=true
			"history_missing": bad.erase("history")
			"route": bad.history.route_method="rain"
			"amount": bad.history.first_transfer_ml+=1
			"node": bad.history.first_transfer.source_id=Runtime.CLINIC
			"component": bad.history.first_transfer.source_before.clean_ml+=1
			"serial": bad.history.observed_serial+=1
			"fraction": bad.history.stable_fractional_usec=NAN
			"ready": bad.history.commissioned=true
			"water": bad.mechanism.runtime.simulation.nodes[Runtime.SOURCE].dirty_ml+=1
			"historyless": bad.history=Progress.new().snapshot()
		var observer = Progress.new()
		var before: Dictionary = observer.snapshot()
		_check(not observer.prepare_restore(bad,[],{}).ok and observer.snapshot()==before,"bad save cannot reset or partially overwrite history: "+kind)
	var valid = Progress.new()
	var prepared: Dictionary = valid.prepare_restore(envelope,[Progress.DIAGNOSE,Progress.CONNECT],{})
	_check(prepared.ok and valid.adopt_restore(prepared),"completed connect with actual transfer restores")
	_check(not valid.prepare_restore(envelope,[Progress.DIAGNOSE,Progress.CONNECT,Progress.STABILIZE],{}).ok,"completed stabilization needs durable observed stability evidence")
