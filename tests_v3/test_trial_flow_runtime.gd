extends SceneTree
## Pure trusted-fact fixtures. No real mechanism, observation, Story, save or LAN.
const Runtime = preload("res://scripts/v3/environment/twin_trial_flow_runtime.gd")
var checks := 0
var failures: Array[String] = []
var measurements: Dictionary = {}

func _init() -> void:
	_definition_and_manual()
	_physical_permission_and_pause()
	_pulse_and_resume()
	_return_and_full_capacity()
	_time_and_json_replay()
	_rejection_and_isolation()
	var state = Runtime.new()
	state.load_definition()
	print("V3_TRIAL_FLOW_RUNTIME_TESTS "+JSON.stringify({"checks":checks,"failures":failures,
		"measurements":measurements,"snapshot_bytes":JSON.stringify(state.snapshot()).to_utf8_buffer().size(),
		"scope":"pure rule fixtures; no Node/physics, actual valves, observations, saves, network or human timing"}))
	quit(0 if failures.is_empty() else 1)

func _check(ok: bool, label: String) -> void:
	checks+=1
	if not ok:
		failures.append(label)
		push_error(label)

func _new():
	var state = Runtime.new()
	var loaded: Dictionary = state.load_definition()
	_check(loaded.ok,"real trial definition loads: "+str(loaded.code))
	return state if loaded.ok else null

func _facts(position: float=0.0, powered: bool=false, pulse: bool=false, remaining: float=0.0, returning: bool=false, clear: bool=true) -> Dictionary:
	return {"selector_position":position,"sweep_clear":clear,"powered":powered,
		"takeover_remaining":remaining,"pulse_requested":pulse,"return_requested":returning}

func _amount(state, id: String) -> int:
	return int(state.get_node(id).volume_ml)

func _invariants(state, label: String) -> void:
	var clean := 0
	var dirty := 0
	var bounded := true
	for id in [Runtime.SOURCE,Runtime.RECEIVER_A,Runtime.RECEIVER_B]:
		var node: Dictionary=state.get_node(id)
		clean+=int(node.clean_ml)
		dirty+=int(node.dirty_ml)
		bounded=bounded and int(node.clean_ml)>=0 and int(node.dirty_ml)>=0 and int(node.volume_ml)<=200000
	_check(clean==160000 and dirty==40000 and bounded,label+": both components conserved / capacity / nonnegative")
	var verified: Dictionary=state.validate_snapshot(state.snapshot())
	_check(verified.ok,label+": current snapshot internally consistent: "+str(verified.code))

func _definition_and_manual() -> void:
	var state=_new()
	if state==null: return
	_check(state.definitions().nodes.size()==3 and state.definitions().edges.size()==4,"bounded three nodes / four physical routes")
	_check(is_equal_approx(float(state.get_node(Runtime.SOURCE).level_m),1.9) and is_equal_approx(float(state.get_node(Runtime.RECEIVER_A).level_m),0.25),"actual volume / area determines initial levels")
	var result: Dictionary=state.step(1.9,_facts(-1.0))
	_check(result.ok and int(result.moved_ml)==19000 and result.new_samples.is_empty(),"manual A really moves 19 L into opposite receiver before sample")
	_check(_amount(state,Runtime.RECEIVER_B)==19000 and _amount(state,Runtime.RECEIVER_A)==0 and not state.status().samples.A.complete,"A-to-B mapping, no premature sample")
	result=state.step(0.1,_facts(-1.0))
	_check(result.ok and result.new_samples==["A"] and state.status().samples.A.complete,"actual twentieth litre records first A sample once")
	var first: Dictionary=state.snapshot().samples.A.duplicate(true)
	result=state.step(0.3,_facts(-1.0))
	_check(result.ok and result.new_samples.is_empty() and state.snapshot().samples.A==first and _amount(state,Runtime.RECEIVER_B)==23000,"later manual flow is real but cannot rewrite first sample")
	result=state.step(2.0,_facts(1.0))
	_check(result.ok and result.new_samples==["B"] and state.status().both_samples_recorded and _amount(state,Runtime.RECEIVER_A)==20000,"opposite actual detent records other branch independently")
	_check(int(state.status().samples.A.manual_ml)==20000 and int(state.status().samples.A.pulse_ml)==0,"method accounting comes from actual valid flow")
	_check(is_equal_approx(float(state.get_node(Runtime.RECEIVER_A).level_m),0.35),"20 L raises receiver's real level by 0.1 m")
	_invariants(state,"manual")

func _physical_permission_and_pause() -> void:
	var state=_new()
	if state==null: return
	var result: Dictionary=state.step(1.0,_facts(-0.99))
	_check(result.ok and int(result.moved_ml)==0,"nearby but not physically arrived detent cannot open flow")
	result=state.step(1.0,_facts(-1.0,false,false,0.0,false,false))
	_check(result.ok and int(result.moved_ml)==0 and state.status().reason=="mechanism_blocked","blocked actual mechanism does not flow")
	state.step(0.09,_facts())
	result=state.step(0.01,_facts(-1.0))
	_check(result.ok and int(result.moved_ml)==100,"previous neutral time does not become newly opened flow credit")
	state.step(0.04,_facts(-1.0))
	var before: Dictionary=state.snapshot()
	_check(state.step(5.0,_facts(1.0,true,false,0.0,true),true,true).ok and state.snapshot()==before,"pause preserves prior earned remainder but adds no time/input")
	_check(state.step(0.0,_facts(1.0)).ok and state.snapshot()==before,"zero delta cannot change mode/pose facts")
	_check(not state.step(0.1,_facts(-1.0),false).ok and state.snapshot()==before,"client cannot advance rules")
	result=state.step(0.06,_facts(-1.0))
	_check(result.ok and int(result.moved_ml)==1000,"resume only settles 0.04 before pause plus 0.06 after, no paused budget")
	_invariants(state,"permissions / paused remainder")
	state=_new()
	if state==null: return
	state.step(0.04,_facts(-1.0))
	result=state.step(0.06,_facts(-1.0,false,false,0.0,false,false))
	_check(result.ok and int(result.moved_ml)==400 and state.status().reason=="mechanism_blocked","blocked interval settles only the preceding authorized 40 ms at bucket boundary")
	result=state.step(0.1,_facts(-1.0,false,false,0.0,false,false))
	_check(result.ok and int(result.moved_ml)==0,"subsequent wholly blocked bucket has no retained flow to release")

func _pulse_and_resume() -> void:
	var state=_new()
	if state==null: return
	var result: Dictionary=state.step(0.1,_facts(0.0,true,true,8.0))
	_check(result.ok and result.desired_selector==-1.0 and int(result.moved_ml)==0,"pulse requests A without teleporting the real selector")
	result=state.step(0.2,_facts(-1.0,true,true,7.9,false,false))
	_check(result.ok and int(result.moved_ml)==0,"desired A plus blocked sweep still cannot supply water")
	result=state.step(0.7,_facts(-1.0,true,true,7.7))
	_check(result.ok and int(state.status().samples.A.moved_ml)==7000,"seven litres are retained as an incomplete actual pulse")
	result=state.step(0.2,_facts(-1.0,false,true,7.0))
	_check(result.ok and int(result.moved_ml)==0 and result.desired_selector==0.0,"power loss stops new flow and requests safe physical neutral")
	result=state.step(0.1,_facts(-1.0,true,true,8.0))
	_check(result.ok and int(result.moved_ml)==0 and result.desired_selector==0.0,"renewed control cannot bypass the required neutral reset")
	state.step(0.1,_facts(0.0,true,true,7.9))
	result=state.step(1.3,_facts(-1.0,true,true,7.8))
	_check(result.ok and int(result.moved_ml)==13000 and result.new_samples==["A"] and result.desired_selector==0.0,"resume supplies only missing 13 L and requests middle before B")
	result=state.step(0.2,_facts(-1.0,true,true,6.5))
	_check(result.ok and int(result.moved_ml)==0,"old A detent cannot act as B while travelling between them")
	result=state.step(0.1,_facts(0.0,true,true,6.3))
	_check(result.ok and result.desired_selector==1.0,"actual neutral authorizes next requested B motion")
	result=state.step(2.0,_facts(1.0,true,true,6.2))
	_check(result.ok and result.new_samples==["B"] and result.desired_selector==0.0,"B gets exactly its 20 L and requests neutral")
	state.step(0.1,_facts(0.0,true,true,4.2))
	result=state.step(2.0,_facts(0.0,true,true,4.1))
	_check(result.ok and int(result.moved_ml)==0 and state.status().phase=="done" and state.status().both_samples_recorded,"held request cannot loop or repeat completed trials")
	_check(int(state.status().samples.A.pulse_ml)==20000 and int(state.status().samples.B.pulse_ml)==20000,"actual pulse method survives interruption")
	_invariants(state,"pulse / resumed")

func _return_and_full_capacity() -> void:
	var state=_new()
	if state==null: return
	state.step(2.0,_facts(-1.0))
	state.step(2.0,_facts(1.0))
	var samples: Dictionary=state.snapshot().samples.duplicate(true)
	var result: Dictionary=state.step(0.1,_facts(1.0,true,false,0.0,true))
	_check(result.ok and int(result.moved_ml)==0 and result.desired_selector==0.0,"return request cannot pump while still in supply detent")
	result=state.step(0.1,_facts(0.0,false,false,0.0,true))
	_check(result.ok and int(result.moved_ml)==0 and state.status().reason=="unpowered","return needs actual power")
	result=state.step(4.0,_facts(0.0,true,false,0.0,true))
	_check(result.ok and int(result.moved_ml)==40000 and state.status().return_complete and _amount(state,Runtime.SOURCE)==200000,"real 2 m pump returns both receivers with no refill shortcut")
	_check(state.snapshot().samples==samples,"return does not erase/duplicate first experiments")
	result=state.step(0.5,_facts(0.0,true,false,0.0,true))
	_check(result.ok and int(result.moved_ml)==0,"empty receivers cannot create returned water")
	state.step(0.1,_facts())
	var accepted:=true
	for unused in range(4): accepted=bool(state.step(5.0,_facts(-1.0)).ok) and accepted
	_check(accepted and _amount(state,Runtime.RECEIVER_B)==200000 and _amount(state,Runtime.SOURCE)==0,"entire 200 L can be moved within real capacities")
	result=state.step(1.0,_facts(-1.0))
	_check(result.ok and int(result.moved_ml)==0 and state.status().reason=="source_empty","empty source supplies no further amount")
	for unused in range(4): accepted=bool(state.step(5.0,_facts(0.0,true,false,0.0,true)).ok) and accepted
	_check(accepted and _amount(state,Runtime.SOURCE)==200000 and state.status().return_complete,"full-volume recovery respects head limit and conserves both components")
	_invariants(state,"full capacity / repeated return")

func _time_and_json_replay() -> void:
	var whole=_new()
	var split=_new()
	if whole==null or split==null: return
	whole.step(5.0,_facts(-1.0))
	for unused in range(300): split.step(1.0/60.0,_facts(-1.0))
	_check(whole.snapshot().simulation==split.snapshot().simulation and whole.snapshot().ledger==split.snapshot().ledger and whole.snapshot().samples==split.snapshot().samples,"five seconds continuous physical facts are equivalent at 60 Hz")
	_check(int(split.snapshot().simulation.tick)==50 and absf(split.elapsed_seconds()-5.0)<0.000001,"solver reuse cannot inflate nested tick or elapsed")
	var large=_new()
	var small=_new()
	if large==null or small==null: return
	large.step(0.3,_facts(-1.0,true,true,0.25))
	for remaining in [0.25,0.20,0.15,0.10,0.05,0.0]: small.step(0.05,_facts(-1.0,true,true,remaining))
	_check(_amount(large,Runtime.RECEIVER_B)==2500 and large.snapshot().simulation==small.snapshot().simulation and large.snapshot().samples==small.snapshot().samples,"0.25 s authority expiry settles exactly 2.5 L with identical large/small steps")
	_check(int(large.snapshot().simulation.tick)==3 and is_equal_approx(large.elapsed_seconds(),0.3) and large.status().desired_selector==0.0,"partial authorization creates no extra hydraulic time and resets safely")
	var before: Dictionary=large.snapshot().simulation.nodes.duplicate(true)
	var result: Dictionary=large.step(0.2,_facts(-1.0,true,true,0.0))
	_check(result.ok and int(result.moved_ml)==0 and large.snapshot().simulation.nodes==before,"no time after expired authority adds flow")
	var mixed=_new()
	if mixed==null: return
	mixed.step(0.03,_facts(-1.0))
	var switching: Dictionary=mixed.step(0.02,_facts(1.0))
	_check(switching.ok and switching.reason=="switching_settle","different route reports bounded one-tick settling rather than silently stealing time")
	var encoded:=JSON.stringify(mixed.snapshot())
	var reloaded=_new()
	if reloaded==null: return
	_check(reloaded.restore(JSON.parse_string(encoded)).ok,"JSON restores partial bucket including authorized route time")
	var m1: Dictionary=mixed.step(0.05,_facts(-1.0))
	var m2: Dictionary=reloaded.step(0.05,_facts(-1.0))
	_check(m1.ok and m2.ok and int(m1.moved_ml)==800 and mixed.snapshot()==reloaded.snapshot(),"restored single-edge tick replays exact quantities/components/samples")
	_check(_amount(mixed,Runtime.RECEIVER_B)==800 and _amount(mixed,Runtime.RECEIVER_A)==0 and int(mixed.snapshot().simulation.tick)==1,"one-tick interlock defers changed route without losing earlier authorized time")
	measurements.expiry_volume_ml=_amount(small,Runtime.RECEIVER_B)
	measurements.mixed_tick=int(mixed.snapshot().simulation.tick)
	_invariants(mixed,"single-edge settled clock")
	var coarse=_new()
	var fine=_new()
	if coarse==null or fine==null: return
	for interval in [[0.03,-1.0,3],[0.02,1.0,2],[0.15,-1.0,15]]:
		coarse.step(float(interval[0]),_facts(float(interval[1])))
		for unused in range(int(interval[2])): fine.step(0.01,_facts(float(interval[1])))
	_check(coarse.snapshot().simulation==fine.snapshot().simulation and coarse.snapshot().samples==fine.snapshot().samples and coarse.snapshot().ledger==fine.snapshot().ledger and _amount(fine,Runtime.RECEIVER_B)==1800,"same actual switching timestamps give identical flow/components/sample/clock across call partitions")

func _rejection_and_isolation() -> void:
	var state=_new()
	if state==null: return
	state.step(0.03,_facts(-1.0))
	var original: Dictionary=state.snapshot()
	var trial=state.copy_for_trial()
	_check(trial!=null and trial.snapshot()==original,"validated trial starts at the same pending hydraulic boundary")
	if trial!=null:
		var changed: Dictionary=trial.step(.07,_facts(-1.0))
		_check(changed.ok and _amount(trial,Runtime.RECEIVER_B)==1000 and state.snapshot()==original and _amount(state,Runtime.RECEIVER_B)==0,"candidate advances a complete tick without aliasing live water, credit or ledger")
		var damaged=state.copy_for_trial()
		damaged._state.ledger[Runtime.TO_A].clean_ml=1
		_check(damaged.copy_for_trial()==null and state.snapshot()==original,"trial copy retains full ledger validation and rejects damaged private state")
	var bad_facts:=_facts(0.0,true,true,1.0,true)
	_check(not state.step(0.1,bad_facts).ok and state.snapshot()==original,"conflicting commands reject atomically including existing pending evidence")
	bad_facts=_facts()
	bad_facts["unknown"]=true
	_check(not state.step(0.1,bad_facts).ok and state.snapshot()==original,"unknown physical fact cannot silently enter runtime")
	_check(not state.step(INF,_facts()).ok and not state.step(5.01,_facts()).ok and state.snapshot()==original,"invalid/oversized duration rejects before mutations")
	var malformed: Array=[]
	var bad: Dictionary=original.duplicate(true)
	bad["unknown"]=0
	malformed.append(bad)
	bad=original.duplicate(true)
	bad.simulation.nodes["unknown"]={"clean_ml":0,"dirty_ml":0}
	malformed.append(bad)
	bad=original.duplicate(true)
	bad.simulation.nodes[Runtime.SOURCE].clean_ml-=1
	bad.simulation.nodes[Runtime.RECEIVER_A].clean_ml+=1
	malformed.append(bad)
	bad=original.duplicate(true)
	bad.samples.A.clean_ml=20000
	bad.samples.A.manual_ml=20000
	malformed.append(bad)
	bad=original.duplicate(true)
	bad.credit_usec+=1
	malformed.append(bad)
	bad=original.duplicate(true)
	bad.credit_edge="I2:clean_to_clinic"
	malformed.append(bad)
	bad=original.duplicate(true)
	bad.simulation.definition_digest="wrong-definition"
	malformed.append(bad)
	bad=original.duplicate(true)
	bad.simulation.nodes[Runtime.SOURCE].clean_ml=200001
	malformed.append(bad)
	var rejected:=true
	for value in malformed: rejected=not state.restore(value).ok and state.snapshot()==original and rejected
	_check(rejected,"invalid IDs / conserved-but-unlogged transfer / fake sample / credit time / fingerprint / capacity all reject atomically")
	var definition: Dictionary=state.definitions()
	definition.nodes[0].capacity_ml+=1
	_check(not state.configure(definition).ok and state.snapshot()==original,"wrong topology contract cannot reset an existing valid run")
	var copy: Dictionary=state.snapshot()
	copy.credit_usec=0
	copy.samples.A.clean_ml=17
	var view: Dictionary=state.status()
	view.samples.A.manual_ml=1
	var node: Dictionary=state.get_node(Runtime.SOURCE)
	node.clean_ml=0
	_check(state.snapshot()==original and state.get_node("unknown").is_empty(),"public nested structures never alias authoritative state")
	var bounded=_new()
	if bounded==null: return
	var accepted:=true
	for index in range(100): accepted=bool(bounded.step(0.001,_facts(-1.0 if index%2==0 else 1.0)).ok) and accepted
	_check(accepted and _amount(bounded,Runtime.RECEIVER_B)==500 and _amount(bounded,Runtime.RECEIVER_A)==0 and int(bounded.snapshot().simulation.tick)==1,"adversarial control churn stays bounded to one edge per hydraulic tick")
	_check(bounded.step(0.1,_facts(1.0)).ok and _amount(bounded,Runtime.RECEIVER_A)==1000,"deferred route starts next tick without transferring denied earlier time")
	_invariants(bounded,"bounded adversarial inputs")
