extends SceneTree
## Pure history/transaction tests. Samples use explicit host-boundary fixtures
## matching the separately measured cabinet viewpoints. The branch regression
## additionally uses a real isolated Store; no rays, Session or network run.
const Progress = preload("res://scripts/v3/gameplay/actions/twin_distribution_progress.gd")
const Cabinet = preload("res://scripts/v3/world/twin_distribution_cabinet.gd")
const Axis = preload("res://scripts/v3/environment/twin_guided_axis.gd")
const Store = preload("res://scripts/v3/core/twin_world_store.gd")
var checks := 0
var failures: Array = []
var layout: Dictionary = {}
var qa_store_path := ""
class TestLogger extends Logger:
	var errors: Array = []
	func _log_error(function: String, file: String, line: int, code: String, rationale: String, _editor_notify: bool, kind: int, _backtraces: Array[ScriptBacktrace]) -> void:
		errors.append({"function":function,"file":file,"line":line,"code":code,"rationale":rationale,"type":kind})
var logger := TestLogger.new()

func _init() -> void:
	OS.add_logger(logger)
	_run.call_deferred()

func _run() -> void:
	layout=JSON.parse_string(FileAccess.get_file_as_string(Cabinet.PATH))
	_test_configuration_and_initialization()
	for method in ["manual","service_lock"]: _test_prepare_save_restore(method)
	_test_pending_retry_and_first_method()
	_test_invalid_observations()
	_test_invalid_history_and_mechanism()
	_test_story_ownership_and_network()
	_test_real_store_branch_discovery()
	print("V3_DISTRIBUTION_PROGRESS_TESTS "+JSON.stringify({"checks":checks,"failures":failures,"engine_errors":logger.errors,"qa_store_path":ProjectSettings.globalize_path(qa_store_path),"scope":"host evidence/schema fixtures plus real isolated Store commits/branch switches/reload; no physical observation, Session, Director reward flow, LAN, GPU or human gameplay"}))
	var failed: bool = not failures.is_empty() or not logger.errors.is_empty()
	OS.remove_logger(logger)
	quit(1 if failed else 0)

func _check(ok: bool, name: String, detail: Variant = null) -> void:
	checks+=1
	if not ok: failures.append({"check":name,"detail":detail})

func _progress():
	var value = Progress.new()
	_check(value.configure(layout).ok,"pure helper configures using exact live cabinet definition")
	return value

func _mechanism(method: String = "manual", serial: int = 22) -> Dictionary:
	var axis = Axis.new()
	axis.configure(Cabinet._axis_config(layout))
	var state: Dictionary = axis.snapshot()
	state.position_m=1.2 if method=="manual" else 0.0
	state.last_serial={"1":3,"2":-1}
	return {"version":1,"layout_sha256":JSON.stringify(layout,"",true,true).sha256_text(),"serial":serial,
		"axis":state,"door_fraction":0.0 if method=="manual" else 0.75,
		"electric_latched":false,"cover_blocked":false,"door_blocked":false}

func _sample(method: String, mechanism: Dictionary) -> Dictionary:
	return {"ok":true,"code":"back_observed","mechanism_serial":mechanism.serial,"method":method,
		"observer":[18.0,5.75,-10.6] if method=="manual" else [17.8,2.7,-7.85],
		"cover_position_m":mechanism.axis.position_m,"door_fraction":mechanism.door_fraction,
		"electric_latched":mechanism.electric_latched,"panel_hits":[5,5],"center_hits":[true,true]}

func _saved_fixture(method: String = "manual") -> Dictionary:
	var progress = _progress()
	var mechanism := _mechanism(method)
	var candidate: Dictionary = progress.prepare_observation(_sample(method,mechanism),mechanism)
	_check(candidate.ok,"explicit valid host sample prepares history",candidate)
	var submission: Dictionary = progress.prepare_retry(candidate,mechanism)
	_check(submission.ok and progress.adopt_saved(submission),"external successful-commit fixture adopts prepared history",submission)
	return {"progress":progress,"mechanism":mechanism,"envelope":submission.envelope}

func _results() -> Dictionary:
	return {"completed":[Progress.EXPOSE],"flags":{Progress.OBSERVED_FLAG:true},"discoveries":[Progress.DISCOVERY]}

func _test_configuration_and_initialization() -> void:
	var not_ready = Progress.new()
	_check(not not_ready.prepare_observation({},{}).ok and not_ready.fact_for(Progress.EXPOSE).is_empty(),"unconfigured helper cannot manufacture a fact")
	var bad := layout.duplicate(true)
	bad.cover.travel_m=2
	_check(not not_ready.configure(bad).ok and not_ready.configure(layout).ok,"failed pure configure does not poison valid retry")
	_check(not not_ready.configure(layout).ok,"live layout cannot silently change under a history")
	var progress = _progress()
	var initial: Dictionary = progress.snapshot()
	var prepared: Dictionary = progress.prepare_restore(null,["I2:clinic_supply:confirm"],{"I2:clinic_ready":true},["I2:clinic_discovery"])
	_check(prepared.ok and prepared.needs_init and prepared.history==initial and progress.snapshot()==initial,"old world with unrelated I2 results can initialize only this missing module")
	var altered := prepared.duplicate(true)
	altered.history.method="manual"
	_check(not progress.adopt_restore(altered) and progress.snapshot()==initial,"modified restore permit cannot change live history")
	_check(progress.adopt_restore(prepared) and not progress.adopt_restore(prepared),"prepared restore adopts exactly once")
	for malformed in [{},[],false,{"version":1}]:
		_check(not progress.prepare_restore(malformed,[],{},[]).ok and progress.snapshot()==initial,"present malformed envelope is not an absent legacy save")
	var results := _results()
	_check(not progress.prepare_restore(null,results.completed,results.flags,results.discoveries).ok,"missing mechanism/history with own results fails closed")
	_check(not progress.prepare_restore(null,[],{},[],false).ok,"network cannot use missing state to reset known history")

func _test_prepare_save_restore(method: String) -> void:
	var progress = _progress()
	var mechanism := _mechanism(method)
	var initial: Dictionary = progress.snapshot()
	var candidate: Dictionary = progress.prepare_observation(_sample(method,mechanism),mechanism)
	_check(candidate.ok and candidate.changed and progress.snapshot()==initial and progress.fact_for(Progress.EXPOSE).is_empty(),"prepared observation produces no fact before external persistent commit: "+method,candidate)
	_check(not candidate.has("mechanism") and not candidate.history.has("mechanism"),"observation candidate never retains a stale complete mechanism")
	var save: Dictionary = progress.prepare_retry(candidate,mechanism)
	_check(save.ok and save.envelope.mechanism==mechanism and progress.snapshot()==initial,"save preparation uses actual supplied latest mechanism without adopting history")
	var altered := save.duplicate(true)
	altered.envelope.history.evidence.panel_hits[0]=3
	_check(not progress.adopt_saved(altered) and progress.snapshot()==initial,"edited prepared commit rejects without live mutation")
	_check(progress.adopt_saved(save) and not progress.adopt_saved(save),"successful external transaction may adopt once only")
	var expected := {"kind":"fact","target":Progress.FACT_TARGET,"option":method}
	_check(progress.fact_for(Progress.EXPOSE)==expected,"only exposed objective obtains stable shared-world method")
	for unknown in ["", "I2:clinic_supply:confirm", "I2:distribution_audit:trial", "I2:distribution_audit:complete"]:
		_check(progress.fact_for(unknown).is_empty(),"no nonexistent future objective or full-action completion is manufactured")
	var outgoing: Dictionary = progress.fact_for(Progress.EXPOSE)
	outgoing.option="forged"
	_check(progress.fact_for(Progress.EXPOSE)==expected,"facts are independent copies with no rewards or actor ownership")
	var copied: Dictionary = progress.snapshot()
	copied.evidence.observer[0]=99
	_check(progress.snapshot().evidence.observer[0]!=99,"history snapshots do not alias nested proof")
	var restart = _progress()
	var roundtrip: Dictionary = JSON.parse_string(JSON.stringify(save.envelope,"",true,true))
	var prepared: Dictionary = restart.prepare_restore(roundtrip,[],{},[])
	_check(prepared.ok and not prepared.needs_init and restart.adopt_restore(prepared) and restart.fact_for(Progress.EXPOSE)==expected,"early discovery survives JSON reload before objective is active")
	roundtrip.history.evidence.observer[0]=77
	_check(restart.snapshot().evidence.observer[0]!=77,"restored history does not share caller-owned arrays")
	var results := _results()
	_check(restart.prepare_restore(save.envelope,results.completed,results.flags,results.discoveries).ok,"already completed expose, flag and discovery receipt validate consistently")

func _test_pending_retry_and_first_method() -> void:
	var progress = _progress()
	var first := _mechanism("manual",22)
	var candidate: Dictionary = progress.prepare_observation(_sample("manual",first),first)
	var old_save: Dictionary = progress.prepare_retry(candidate,first)
	_check(old_save.ok and not progress.snapshot().back_observed,"simulated failed disk write leaves live history unadopted")
	var later := _mechanism("service_lock",30)
	later.axis.last_serial={} # Both peers may disconnect after verified observation.
	var second: Dictionary = progress.prepare_observation(_sample("service_lock",later),later)
	_check(second==candidate,"second valid route while write is pending does not replace first observation")
	var retry: Dictionary = progress.prepare_retry(candidate,later)
	_check(retry.ok and retry.envelope.mechanism.serial==30 and retry.envelope.mechanism.axis.position_m==0 and retry.envelope.mechanism.door_fraction==0.75 and retry.envelope.history.method=="manual","retry pairs historical proof with NEW closed-cover/advanced-door/disconnected mechanism",retry)
	_check(not progress.adopt_saved(old_save),"new retry invalidates old whole-frame submission permit")
	_check(not progress.prepare_retry(candidate,first).ok,"retry refuses a mechanism older than one already seen")
	var poisoned := candidate.duplicate(true)
	poisoned.history.evidence.observer[0]+=0.1
	_check(not progress.prepare_retry(poisoned,later).ok,"caller cannot edit prepared proof during a retry")
	_check(progress.adopt_saved(retry) and progress.snapshot().method=="manual","persistent commit adopts original proof despite later cover closure/peer departure")
	later.serial=31
	later.door_fraction=1.0
	later.electric_latched=true
	var done := _sample("service_lock",later)
	var repeated: Dictionary = progress.prepare_observation(done,later)
	_check(repeated.ok and not repeated.changed and repeated.history.method=="manual","second route after commit remains an unchanged first-method history")
	var no_op: Dictionary = progress.prepare_retry(repeated,later)
	_check(no_op.ok and progress.adopt_saved(no_op) and progress.fact_for(Progress.EXPOSE).option=="manual","repeat transaction adds no reward counter or second discovery state")
	var detached: Dictionary = no_op.envelope
	detached.history.evidence.panel_hits.clear()
	_check(progress.snapshot().evidence.panel_hits==[5,5],"adopted proof isolated from outgoing envelope")

func _test_invalid_observations() -> void:
	var progress = _progress()
	var state := _mechanism()
	var sample := _sample("manual",state)
	var cases: Array = [null,{},[],false]
	for key in sample:
		var missing := sample.duplicate(true)
		missing.erase(key)
		cases.append(missing)
	for row in [["ok",1],["ok",false],["code","back_covered"],["method","fake"],["observer",[18,INF,-10]],["observer",[18,12,-10.6]],["observer",[18,2.7,-14]],["panel_hits",[2,5]],["panel_hits",[3.5,5]],["panel_hits",[6,5]],["center_hits",[true,false]],["center_hits",[1,true]],["mechanism_serial",21],["cover_position_m",0.0],["extra",true]]:
		var invalid := sample.duplicate(true)
		invalid[row[0]]=row[1]
		cases.append(invalid)
	var before: Dictionary = progress.snapshot()
	for invalid in cases:
		_check(not progress.prepare_observation(invalid,state).ok and progress.snapshot()==before,"invalid or stale observation cannot produce/adopt a history")
	var almost_closed := _mechanism("manual",23)
	almost_closed.axis.position_m=0.01
	_check(not progress.prepare_observation(_sample("manual",almost_closed),almost_closed).ok,"claimed centers behind barely shifted real cover are geometrically impossible")
	var half := _mechanism("service_lock",24)
	half.door_fraction=0.5
	_check(not progress.prepare_observation(_sample("service_lock",half),half).ok,"claimed external centers behind half-open gate reject analytically")
	var valid: Dictionary = progress.prepare_observation(sample,state)
	_check(valid.ok,"rejected forged fields leave the next real sample usable")
	_check(not progress.prepare_observation({},state).ok and progress.prepare_retry(valid,state).ok,"invalid later sample does not destroy valid pending disk-retry evidence")

func _test_invalid_history_and_mechanism() -> void:
	var rig := _saved_fixture()
	var progress = rig.progress
	var history: Dictionary = progress.snapshot()
	var mechanism: Dictionary = rig.mechanism
	var histories: Array = [{},null,[]]
	for key in history:
		var missing := history.duplicate(true)
		missing.erase(key)
		histories.append(missing)
	for row in [["version",2],["back_observed",1],["method",""],["extra",0]]:
		var bad := history.duplicate(true)
		bad[row[0]]=row[1]
		histories.append(bad)
	var absent := history.duplicate(true)
	absent.back_observed=false
	histories.append(absent)
	for key in history.evidence:
		var bad := history.duplicate(true)
		bad.evidence.erase(key)
		histories.append(bad)
	for invalid in histories:
		_check(not progress.validate_history(invalid,mechanism).ok and progress.snapshot()==history,"strict historical schema rejects atomically")
	var machines: Array = [null,{},[]]
	for key in mechanism:
		var bad := mechanism.duplicate(true)
		bad.erase(key)
		machines.append(bad)
	for row in [["version",2],["layout_sha256","bad"],["serial",21],["serial",22.5],["door_fraction",NAN],["electric_latched",true],["extra",false]]:
		var bad := mechanism.duplicate(true)
		bad[row[0]]=row[1]
		machines.append(bad)
	var bad_axis := mechanism.duplicate(true)
	bad_axis.axis.last_serial={"01":4}
	machines.append(bad_axis)
	for invalid in machines:
		_check(not progress.validate_history(history,invalid).ok and progress.snapshot()==history,"real Cabinet snapshot validator remains mandatory")
	var same_serial := mechanism.duplicate(true)
	same_serial.axis.position_m=0.0
	_check(not progress.validate_history(history,same_serial).ok,"same serial cannot silently change observed pose")
	same_serial.serial=23
	_check(progress.validate_history(history,same_serial).ok,"later legitimate cover closure preserves recorded knowledge")
	var service := _saved_fixture("service_lock")
	var reversed: Dictionary = service.mechanism.duplicate(true)
	reversed.serial+=1
	reversed.door_fraction=0.25
	_check(not service.progress.validate_history(service.progress.snapshot(),reversed).ok,"mechanically one-way door cannot reverse its historical travel")

func _test_story_ownership_and_network() -> void:
	var rig := _saved_fixture()
	var progress = rig.progress
	var envelope: Dictionary = rig.envelope
	var results := _results()
	var all_completed: Array = ["I1:underdeck:read","I2:clinic_supply:confirm",Progress.EXPOSE,"I2:future:result"]
	var flags := {"I2:clinic_ready":true,"I2:future_choice":"other",Progress.OBSERVED_FLAG:true}
	var discoveries := ["I2:other_discovery",Progress.DISCOVERY]
	_check(progress.prepare_restore(envelope,all_completed,flags,discoveries).ok,"claims only explicit own objective/flag/discovery and accepts unrelated I2 state")
	var interned: Dictionary = {StringName(Progress.OBSERVED_FLAG):true}
	_check(progress.prepare_restore(envelope,results.completed,interned,results.discoveries).ok,"live StringName own flag key matches JSON key")
	for row in [[[Progress.EXPOSE],{},[]],[[],{Progress.OBSERVED_FLAG:true},[]],[results.completed,results.flags,[]],[results.completed,{Progress.OBSERVED_FLAG:1},results.discoveries],[results.completed,{7:true},results.discoveries],[{}, {}, []],[[], {}, {}]]:
		_check(not progress.prepare_restore(envelope,row[0],row[1],row[2]).ok,"own Story/flag/discovery partial or malformed state is rejected")
	_check(progress.prepare_restore(envelope,[],{},[Progress.DISCOVERY]).ok,"personal discovery may precede this branch's uncompleted world result")
	var empty := envelope.duplicate(true)
	empty.history={"version":1,"back_observed":false,"method":"","evidence":{}}
	_check(not progress.prepare_restore(empty,results.completed,results.flags,results.discoveries).ok,"completed exposure requires persistent observation history")
	var network = _progress()
	var pending: Dictionary = network.prepare_restore(envelope,[Progress.EXPOSE],{},[],false)
	_check(pending.ok and network.adopt_restore(pending),"authority-bound network history can arrive before separate Story flags/receipt")
	_check(network.validate_history(network.snapshot(),envelope.mechanism).ok,"network internal validation does not require a matching Story revision")
	var first: Dictionary = network.prepare_restore(envelope,[],{},[])
	_check(not network.prepare_restore({},[],{},[]).ok and not network.adopt_restore(first),"failed newer restore invalidates earlier adoption permit without wiping history")
	_check(network.snapshot().back_observed,"failed restore keeps live recorded knowledge")
	var new_config := layout.duplicate(true)
	new_config.stage="another_revision"
	var versioned = Progress.new()
	_check(versioned.configure(new_config).ok and not versioned.prepare_restore(envelope,[],{},[]).ok,"changed layout fingerprint cannot restore old mechanism/proof silently")

func _test_real_store_branch_discovery() -> void:
	# Evidence is an explicit host-boundary fixture, not a played observation.
	# Persistence, branch switching and generation reload below are real Store IO.
	qa_store_path="user://qa_v3_distribution_progress/"+Crypto.new().generate_random_bytes(16).hex_encode()
	var fresh: bool = not DirAccess.dir_exists_absolute(qa_store_path)
	_check(fresh,"branch regression refuses an existing QA profile",qa_store_path)
	if not fresh: return
	var store = Store.new(qa_store_path)
	var loaded: Dictionary = store.load_profile()
	_check(loaded.ok,"fresh isolated Store loads without touching player profile",loaded)
	if not loaded.ok: return
	_check(store.fork_branch("legacy_b","unvisited B before module existed",false).ok,"real Store freezes an unvisited branch with no distribution envelope")
	var progress = _progress()
	var initial_mechanism := _mechanism("manual",1)
	initial_mechanism.axis.position_m=0.0
	initial_mechanism.axis.last_serial={}
	var initial_envelope := {"version":1,"mechanism":initial_mechanism,"history":progress.snapshot()}
	var initialized: Dictionary = store.commit({"id":"qa-distribution-initialized","set":{"world.environment.I2_distribution":initial_envelope}})
	_check(initialized.ok,"real Store persists an initialized but unobserved distribution branch",initialized)
	if not initialized.ok: return
	_check(store.fork_branch("branch_b","initialized unobserved B",false).ok and store.fork_branch("branch_a","observation A",true).ok,"real Store forks unobserved B then switches to independent A")
	var mechanism := _mechanism("manual",22)
	var candidate: Dictionary = progress.prepare_observation(_sample("manual",mechanism),mechanism)
	var submission: Dictionary = progress.prepare_retry(candidate,mechanism)
	_check(submission.ok,"host fixture prepares A observation without assuming a disk success",submission)
	if not submission.ok: return
	var committed: Dictionary = store.commit({"id":"qa-distribution-a-expose","set":{
		"world.environment.I2_distribution":submission.envelope,
		"world.completed_objectives":[Progress.EXPOSE],
		"world.flags":{Progress.OBSERVED_FLAG:true}},
		"append":{"personal.discoveries":[Progress.DISCOVERY]}})
	_check(committed.ok and progress.adopt_saved(submission),"real atomic A commit persists history/world result/personal discovery before adoption",committed)
	if not committed.ok: return
	var a: Dictionary = store.snapshot()
	var a_prepared: Dictionary = progress.prepare_restore(a.world.environment.I2_distribution,a.world.completed_objectives,a.world.flags,a.personal.discoveries)
	_check(a_prepared.ok and not a_prepared.needs_init,"completed A validates its own world result and personal discovery",a_prepared)
	_check(store.switch_branch("branch_b").ok,"real Store switches completed A to prior unobserved B")
	var b: Dictionary = store.snapshot()
	_check(b.world.branch_id=="branch_b" and b.world.completed_objectives.is_empty() and b.world.flags.is_empty() and b.personal.discoveries==[Progress.DISCOVERY],"Store actually retains personal discovery while restoring B's uncompleted world")
	_check(store._canonical(b.world.environment.I2_distribution)==store._canonical(initial_envelope),"branch B retains its real closed mechanism and empty historical evidence")
	var b_prepared: Dictionary = progress.prepare_restore(b.world.environment.I2_distribution,b.world.completed_objectives,b.world.flags,b.personal.discoveries)
	_check(b_prepared.ok and not b_prepared.needs_init and progress.adopt_restore(b_prepared) and not progress.snapshot().back_observed and progress.fact_for(Progress.EXPOSE).is_empty(),"retained personal discovery does not reject B or manufacture an observed fact",b_prepared)
	var reread = Store.new(qa_store_path)
	_check(reread.load_profile().ok,"actual saved B generation reloads from disk")
	var persisted_b: Dictionary = reread.snapshot()
	_check(persisted_b==b,"reload preserves both B's earlier world and A's personal discovery")
	var restarted = _progress()
	var restart_prepared: Dictionary = restarted.prepare_restore(persisted_b.world.environment.I2_distribution,persisted_b.world.completed_objectives,persisted_b.world.flags,persisted_b.personal.discoveries)
	_check(restart_prepared.ok and restarted.adopt_restore(restart_prepared) and restarted.fact_for(Progress.EXPOSE).is_empty(),"fresh helper accepts the real reloaded B without borrowing A history")
	_check(reread.switch_branch("legacy_b").ok,"real Store switches to older branch without a distribution envelope")
	var legacy: Dictionary = reread.snapshot()
	var absent: Variant = legacy.world.get("environment",{}).get("I2_distribution",null)
	_check(absent==null and legacy.personal.discoveries==[Progress.DISCOVERY],"legacy B truly lacks mechanism while global personal discovery survives")
	var legacy_prepared: Dictionary = restarted.prepare_restore(absent,legacy.world.completed_objectives,legacy.world.flags,legacy.personal.discoveries)
	_check(legacy_prepared.ok and legacy_prepared.needs_init and restarted.adopt_restore(legacy_prepared) and restarted.fact_for(Progress.EXPOSE).is_empty(),"personal discovery alone is not a current-world result preventing legacy initialization",legacy_prepared)
	_check(reread.switch_branch("branch_a").ok,"real Store returns to completed A after both earlier branches")
	a=reread.snapshot()
	a_prepared=restarted.prepare_restore(a.world.environment.I2_distribution,a.world.completed_objectives,a.world.flags,a.personal.discoveries)
	_check(a_prepared.ok and restarted.adopt_restore(a_prepared) and restarted.fact_for(Progress.EXPOSE).option=="manual","returning to A restores A's actual historical method and fact")
	_check(not restarted.prepare_restore(a.world.environment.I2_distribution,a.world.completed_objectives,a.world.flags,[]).ok,"completed A still rejects a missing personal discovery")
	_check(a.personal.discoveries==[Progress.DISCOVERY],"real branch switches and reload do not duplicate personal discovery")
