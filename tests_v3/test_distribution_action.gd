extends SceneTree
## Production Director + data only. "validated" facts are explicit trusted
## fixtures, not proof of physical observations, consensus or Store commits.
const Director=preload("res://scripts/v3/gameplay/actions/twin_action_director.gd")
const ClinicData=preload("res://tests_v3/test_clinic_action.gd")
const DistributionProgress=preload("res://scripts/v3/gameplay/actions/twin_distribution_progress.gd")
const PATH:="res://data/v3/actions/distribution_action.json"
const ACTION:="I2:distribution_audit"
const GOALS:=[ACTION+":expose",ACTION+":trace",ACTION+":share_access"]
const TARGETS:=["I2:distribution_back_exposed","I2:distribution_route_verified","I2:distribution_access_committed"]
const FLAGS:=["I2:distribution_back_observed","I2:distribution_trace_verified","I2:distribution_access_shared"]
const FINDINGS:=["I2:distribution_back_route","I2:label_flow_disagreement","I2:shared_access_plan"]
var checks:=0
var failures: Array[String]=[]
var director=Director.new()
var legacy=Director.new()
var extension: Dictionary={}
var legacy_complete: Dictionary={}
var complete: Dictionary={}

func _initialize() -> void:
	var old_paths: Array=ClinicData.OLD_EXTENSIONS.duplicate()
	old_paths.append(ClinicData.CLINIC_PATH)
	var new_paths: Array=old_paths.duplicate()
	new_paths.append(PATH)
	var old_loaded: Dictionary=legacy.load_definitions(Director.DEFAULT_PATH,old_paths)
	var loaded: Dictionary=director.load_definitions(Director.DEFAULT_PATH,new_paths)
	_check(old_loaded.get("ok",false),"production eight-action definitions load")
	_check(loaded.get("ok",false),"candidate ninth action loads: "+str(loaded.get("code")))
	if old_loaded.get("ok",false) and loaded.get("ok",false):
		extension=JSON.parse_string(FileAccess.get_file_as_string(PATH))
		_content()
		_legacy_replay()
		if not legacy_complete.is_empty():
			_trust_and_order()
			_paths()
			if not complete.is_empty(): _reload_and_repeat(new_paths)
	print("DISTRIBUTION_ACTION checks=%d failures=%d" % [checks,failures.size()])
	print("DISTRIBUTION_ACTION_RESULT "+JSON.stringify({"passed":failures.is_empty(),"checks":checks,"failures":failures,"scope":"nine_actions_34_objectives_data_candidate","limits":["Pure Director and JSON with explicitly trusted fact fixtures only.","Evidence metadata is not executed by Director: no real G/LOS, sample acquisition, water, bridge movement, Store, two-player agreement or network proof.","Early observations belong to existing mechanism/history adapters; this suite only verifies deferred fact eligibility and exact-once data results.","5–8 minutes is an unmeasured design target, not a human or scripted playthrough duration."]}))
	quit(0 if failures.is_empty() else 1)

func _check(ok: bool,label: String) -> void:
	checks+=1
	if not ok:
		failures.append(label)
		push_error(label)

func _same(a: Variant,b: Variant) -> bool:
	return JSON.parse_string(JSON.stringify(a))==JSON.parse_string(JSON.stringify(b))

func _event(index: int,option: String,suffix: String="") -> Dictionary:
	return {"id":"qa_distribution_data:"+str(GOALS[index])+suffix,"type":"fact","target_id":TARGETS[index],"option":option}

func _trusted() -> Dictionary:
	return {"is_authority":true,"validated":true,"region_id":"I2"}

func _unchanged(result: Dictionary,state: Dictionary) -> bool:
	return not result.get("changed",false) and result.get("effects",[]).is_empty() and _same(result.get("state"),state)

func _content() -> void:
	var defs: Dictionary=director.definitions()
	var old: Dictionary=legacy.definitions()
	var actions: Array=[]
	var goals:=0
	for item in defs.actions:
		actions.append(item.id)
		goals+=item.objectives.size()
	var expected: Array=ClinicData.ACTIONS.duplicate()
	expected.append(ACTION)
	_check(actions==expected and goals==34 and old.actions.size()==8,"exact nine-action34-objective candidate, preserving existing order")
	var preserved:=true
	for i in range(8): preserved=preserved and _same(defs.actions[i],old.actions[i])
	_check(preserved,"all eight existing action definitions remain unchanged")
	_check(extension.characters.is_empty() and extension.markers.is_empty() and _same(defs.markers,old.markers) and _same(director.default_state().characters,legacy.default_state().characters),"no duplicate live targets or new character/default-state migration")
	var action: Dictionary=defs.actions[8]
	_check(action.prerequisites==["I2:clinic_supply"] and _same(action.target_minutes,[5,8]),"completed clinic is required; time is design metadata only")
	var chain: Array=[]
	var ordered:=true
	for i in range(3):
		ordered=ordered and action.objectives[i].id==GOALS[i] and action.objectives[i].after==chain and action.objectives[i].events[0].type=="fact" and action.objectives[i].events[0].target_id==TARGETS[i]
		chain=[GOALS[i]]
	_check(ordered,"exact expose-trace-share_access order and independent authority fact targets")
	_check(GOALS[0]==DistributionProgress.EXPOSE and TARGETS[0]==DistributionProgress.FACT_TARGET and FLAGS[0]==DistributionProgress.OBSERVED_FLAG and FINDINGS[0]==DistributionProgress.DISCOVERY,"expose reuses the implemented history, fact and reward identifiers")
	var bindings: Dictionary=extension.host_bindings
	var trace: Dictionary=bindings[TARGETS[1]]
	_check(bindings[TARGETS[0]].retain_before_objective and trace.retain_before_objective and trace.return_preserves_evidence,"already saved observations do not require repeated mechanism work")
	_check(trace.required_records==["A","B"] and trace.sample_ml==20000 and trace.matching==[{"record":"A","receiver_id":"I2:trial_receiver_a","selection_sample":"B"},{"record":"B","receiver_id":"I2:trial_receiver_b","selection_sample":"A"}],"both saved gauge records are bound to actual opposite first20L samples")
	_check(trace.required_current_tank_volume_ml==null and "current_tank_volume" in trace.reject_as_sole_proof and "last_tick_transfer" in trace.reject_as_sole_proof and "one_gauge_only" in trace.reject_as_sole_proof and "each_record_matches_immutable_opposite_sample" in trace.required_validation,"contract forbids replacing two recorded observations with current volume or latest transfer")
	_check(action.objectives[1].events[0].options==["manual_trial","pulse_trial","mixed_trial"],"mixed real work is credited without inventing a pure-pulse history")
	var access: Dictionary=bindings[TARGETS[2]]
	_check(access.required_access_report.choice_ready and access.required_access_report.public_access and access.required_access_report.service_access and access.required_status.locked and access.required_access_report.width_m==3 and access.required_access_report.height_m==2.8,"final fact requires both actual supported routes and inserted lock")
	_check(_same(access.route_lengths_m,{"public_span":{"public":13.4,"service":19.8},"service_span":{"public":39.6,"service":9.6}}) and _same(access.permanent_bypass_lengths_m,{"public":39.6,"service":19.8}),"route tradeoffs match the actual independent bridge result")
	_check(access.requires_explicit_interaction and access.requires_line_of_sight and access.requires_two_player_consensus and access.revalidate_before_commit and not access.chapter_major_choice and access.consumes_major_choice_budget==0 and not access.resident_ai_required,"local allocation preserves four chapter choices and makes no resident-AI claim")
	var without_clinic: Array=ClinicData.OLD_EXTENSIONS.duplicate()
	without_clinic.append(PATH)
	var incomplete=Director.new()
	_check(not incomplete.load_definitions(Director.DEFAULT_PATH,without_clinic).get("ok",false),"cannot load new action without actual clinic prerequisite")

func _legacy_replay() -> void:
	var state: Dictionary=legacy.default_state()
	var history: Array=ClinicData.OLD_EVENTS.duplicate(true)
	history.append_array(ClinicData.EVENTS)
	var early: Dictionary=_event(0,"manual")
	for i in range(history.size()):
		if i==history.size()-1:
			var locked: Dictionary=director.apply_event(state,early,_trusted())
			_check(locked.get("code")=="objective_locked" and _unchanged(locked,state),"earlier captured exposure fact cannot skip final clinic confirmation")
		var row: Array=history[i]
		var event: Dictionary={"id":"qa_distribution_history:"+str(row[0]),"type":row[1],"target_id":row[2],"option":row[3]}
		var result: Dictionary=legacy.apply_event(state,event,{"is_authority":true,"validated":true,"region_id":str(row[0]).get_slice(":",0)})
		if not result.get("changed",false):
			_check(false,"fixed predecessor receipt failed: "+str(row[0]))
			return
		state=result.state
		if i in [14,22,26,30]:
			_check(director.validate_state(JSON.parse_string(JSON.stringify(state))).ok,"existing saved prefix remains valid at goal "+str(i+1))
	legacy_complete=JSON.parse_string(JSON.stringify(state))
	var hud: Dictionary=director.hud(legacy_complete,"I2")
	_check(state.completed.size()==31 and state.completed_actions.size()==8 and legacy.hud(state).complete,"actual old31-event reducer sequence reconstructs completed eight-action state")
	_check(not hud.complete and hud.action_id==ACTION and hud.objectives.size()==1 and hud.objectives[0].id==GOALS[0],"old completed save gains exactly one current destination, without resetting history")
	var delayed: Dictionary=director.apply_event(legacy_complete,early,_trusted())
	_check(delayed.changed and delayed.state.choices[GOALS[0]]=="manual","the exact earlier fact becomes eligible after unlock; no new observation is demanded by data")

func _trust_and_order() -> void:
	for context in [{"is_authority":false,"validated":true,"region_id":"I2"},{"is_authority":true,"validated":false,"region_id":"I2"},{"is_authority":true,"validated":true,"region_id":"I1"}]:
		var result: Dictionary=director.apply_event(legacy_complete,_event(0,"manual"),context)
		_check(not result.ok and _unchanged(result,legacy_complete),"nonhost/unverified/wrong-region event is rejected atomically")
	for pair in [[1,"manual_trial"],[2,"public_span"]]:
		var result: Dictionary=director.apply_event(legacy_complete,_event(pair[0],pair[1]),_trusted())
		_check(result.get("code")=="objective_locked" and _unchanged(result,legacy_complete),"later fact cannot skip exposure: "+str(pair[0]))
	var state: Dictionary=director.apply_event(legacy_complete,_event(0,"manual"),_trusted()).state
	for option in ["volume_only","one_gauge","powered_only","assumed_map"]:
		var result: Dictionary=director.apply_event(state,_event(1,option),_trusted())
		_check(result.get("code")=="unsupported_event" and _unchanged(result,state),"non-evidence event option cannot complete trace: "+option)
	var raw: Dictionary=_event(1,"manual_trial")
	raw.type="inspect"
	var denied: Dictionary=director.apply_event(state,raw,_trusted())
	_check(denied.get("code")=="unsupported_event" and _unchanged(denied,state),"raw inspection cannot substitute the adapter's double-record fact")
	var premature: Dictionary=director.apply_event(state,_event(2,"public_span"),_trusted())
	_check(premature.get("code")=="objective_locked" and _unchanged(premature,state),"bridge confirmation cannot skip the saved double-sample goal")

func _paths() -> void:
	for expose in ["manual","service_lock"]:
		for trace in ["manual_trial","pulse_trial","mixed_trial"]:
			for access in ["public_span","service_span"]:
				var path: String=expose+"/"+trace+"/"+access
				var state: Dictionary=legacy_complete.duplicate(true)
				var options: Array=[expose,trace,access]
				var input_unchanged:=true
				var all_advanced:=true
				var effects: Array=[]
				for i in range(3):
					var before: Dictionary=state.duplicate(true)
					var result: Dictionary=director.apply_event(state,_event(i,options[i]),_trusted())
					input_unchanged=input_unchanged and _same(state,before)
					if not result.get("changed",false):
						all_advanced=false
						break
					state=result.state
					effects.append_array(result.effects)
				_check(all_advanced and input_unchanged,path+" advances without mutating input")
				if not all_advanced: return
				_check(state.completed.size()==34 and state.completed_actions.size()==9 and director.hud(state).complete and director.validate_state(JSON.parse_string(JSON.stringify(state))).ok,path+" is a replay-valid34-goal candidate")
				_check(state.choices[GOALS[0]]==expose and state.choices[GOALS[1]]==trace and state.choices[GOALS[2]]==access,path+" preserves all actual method/mode choices")
				var reward_ids: Array=[]
				for effect in effects:
					if effect.type=="discovery": reward_ids.append(effect.discovery_id)
				var unique:=reward_ids==FINDINGS
				for id in FINDINGS: unique=unique and state.discoveries.count(id)==1
				_check(unique and state.flags[FLAGS[0]] and state.flags[FLAGS[1]] and state.flags[FLAGS[2]],path+" yields three stable independent discovery IDs once")
				var alternate: Dictionary=director.apply_event(state,_event(2,"service_span" if access=="public_span" else "public_span",":other_peer"),_trusted())
				_check(alternate.ok and _unchanged(alternate,state) and state.choices[GOALS[2]]==access,path+" cannot gain a second mode or second reward on this branch")
				if complete.is_empty(): complete=state.duplicate(true)
	_check(director.validate_state(legacy_complete).ok and legacy_complete.completed.size()==31,"all route fixtures leave the old completed branch intact")

func _reload_and_repeat(paths: Array) -> void:
	var saved: Dictionary=JSON.parse_string(JSON.stringify(complete))
	var reloaded=Director.new()
	_check(reloaded.load_definitions(Director.DEFAULT_PATH,paths).ok and reloaded.validate_state(saved).ok,"new Director restores the exact candidate from JSON")
	for i in range(3):
		for suffix in ["",":retry_other_peer"]:
			var result: Dictionary=reloaded.apply_event(saved,_event(i,saved.choices[GOALS[i]],suffix),_trusted())
			_check(result.ok and _unchanged(result,saved),"saved/reissued fact never repeats effects: "+str(i)+suffix)
	var conflicting: Dictionary=_event(2,"service_span")
	var conflict: Dictionary=reloaded.apply_event(saved,conflicting,_trusted())
	_check(conflict.get("code")=="event_id_conflict" and _unchanged(conflict,saved),"same confirmation receipt cannot be rewritten to the other mode")
	var replay: Dictionary=reloaded.default_state()
	var by_goal: Dictionary={}
	for id in saved.receipts:
		var receipt: Dictionary=saved.receipts[id]
		by_goal[receipt.objective_id]={"id":id,"type":receipt.type,"target_id":receipt.target_id,"option":receipt.option}
	for goal in saved.completed:
		var result: Dictionary=reloaded.apply_event(replay,by_goal[goal],{"is_authority":true,"validated":true,"region_id":str(goal).get_slice(":",0)})
		if not result.get("changed",false):
			_check(false,"receipt replay failed: "+str(goal))
			return
		replay=result.state
	_check(_same(replay,saved),"all34 historical receipts reproduce exact final state")
	for field in ["choice","flag","discovery","chapter"]:
		var tampered: Dictionary=saved.duplicate(true)
		match field:
			"choice": tampered.choices[GOALS[2]]="service_span"
			"flag": tampered.flags[FLAGS[1]]=false
			"discovery": tampered.discoveries.erase(FINDINGS[1])
			"chapter": tampered.flags["I2:chapter_major_choice_committed"]=true
		_check(not reloaded.validate_state(tampered).ok,"receipt-derived result rejects tampering: "+field)
	_check(not reloaded.dialogue_lines(saved,"npc:linlan").is_empty() and not reloaded.dialogue_lines(saved,"npc:ruanheng").is_empty(),"existing characters have the new local outcome response after restore")
