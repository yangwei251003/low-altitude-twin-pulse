extends SceneTree
## Explicit saved-mechanism and successful-observation fixtures. Real Cabinet
## configure/validators and Progress are exercised; no rays or live actors run.
## No profile, Store, Session, rewards, network, render or playthrough is created.
const Migration = preload("res://scripts/v3/world/twin_distribution_layout_migration.gd")
const Cabinet = preload("res://scripts/v3/world/twin_distribution_cabinet.gd")
const Progress = preload("res://scripts/v3/gameplay/actions/twin_distribution_progress.gd")
var legacy: Dictionary = {}
var target: Dictionary = {}
var initial: Dictionary = {}
var checks := 0
var failures: Array = []
var finished := false
var hashes_before: Dictionary = {}
class TestLogger extends Logger:
	var errors: Array = []
	func _log_error(function: String,file: String,line: int,code: String,rationale: String,_notify: bool,kind: int,_backtraces: Array[ScriptBacktrace]) -> void:
		errors.append({"function":function,"file":file,"line":line,"code":code,"rationale":rationale,"type":kind})
var logger := TestLogger.new()

func _init() -> void:
	OS.add_logger(logger)
	_run.call_deferred()

func _run() -> void:
	create_timer(45).timeout.connect(func():
		if not finished:
			_check(false,"bounded migration test timeout")
			_finish())
	for path in [Migration.LEGACY_PATH,Migration.CANDIDATE_PATH,Migration.CURRENT_PATH]:
		hashes_before[path]=FileAccess.get_sha256(path)
	var old_json: Variant = JSON.parse_string(FileAccess.get_file_as_string(Migration.LEGACY_PATH))
	var new_json: Variant = JSON.parse_string(FileAccess.get_file_as_string(Migration.CANDIDATE_PATH))
	_check(old_json is Dictionary and new_json is Dictionary,"frozen legacy and reviewed candidate are actual JSON files")
	if not old_json is Dictionary or not new_json is Dictionary:
		_finish()
		return
	legacy=old_json
	target=new_json
	_check(hashes_before[Migration.LEGACY_PATH]==Migration.LEGACY_FILE_SHA and hashes_before[Migration.CANDIDATE_PATH]==Migration.TARGET_FILE_SHA,"raw source hashes are independently locked")
	_check(_hash(legacy)==Migration.LEGACY_STATE_SHA and _hash(target)==Migration.TARGET_STATE_SHA,"actual Godot canonical digests are distinct from raw file hashes")
	var cabinet = Cabinet.new()
	var configured: Dictionary = cabinet.configure(legacy,{},false)
	_check(configured.ok,"real Cabinet configures frozen legacy geometry",configured)
	if configured.ok: initial=cabinet.snapshot()
	cabinet.free()
	if initial.is_empty():
		_finish()
		return
	_test_contract()
	_test_mechanisms()
	_test_empty_history()
	_test_malformed()
	for method in ["manual","service_lock"]: _test_history(method)
	_test_bad_history()
	for path in hashes_before:
		_check(FileAccess.get_sha256(path)==hashes_before[path],"test leaves input bytes unchanged: "+str(path))
	_finish()

func _check(ok: bool,label: String,detail: Variant = null) -> void:
	checks+=1
	if not ok:
		failures.append({"check":label,"detail":detail})
		print("DISTRIBUTION_LAYOUT_MIGRATION_FAIL "+label+" "+str(detail))

func _test_contract() -> void:
	_check(Migration._validate_contract(legacy,target).ok,"only the reviewed five-piece floor substitution is permitted")
	for change in ["stage","panel","other_solid","floor_extent","floor_color","missing_piece"]:
		var bad: Dictionary = target.duplicate(true)
		match change:
			"stage": bad.stage="unreviewed"
			"panel": bad.panels[0].center[0]+=0.01
			"other_solid": bad.fixed_solids[5].color="ffffff"
			"floor_extent": bad.fixed_solids[0].min[2]-=0.01
			"floor_color": bad.fixed_solids[0].color="ffffff"
			"missing_piece": bad.fixed_solids.remove_at(1)
		_check(not Migration._validate_contract(legacy,bad).ok,"contract rejects collateral change: "+change)
	_check(not Migration.prepare(initial,"res://data/v3/terrain/i2_clinic_layout.json").ok,"optional target path cannot select an unrelated reviewed system")
	var default_result: Dictionary = Migration.prepare(initial)
	if hashes_before[Migration.CURRENT_PATH]==Migration.TARGET_FILE_SHA:
		_check(default_result.ok and default_result.migrated,"after production promotion default target uses the same locked candidate")
	else:
		_check(not default_result.ok and default_result.code=="migration_target_not_reviewed","before promotion default path does not silently migrate to the old production target")

func _test_mechanisms() -> void:
	var moving: Dictionary = initial.duplicate(true)
	moving.serial=31
	moving.axis.position_m=0.48
	moving.axis.velocity_mps=1.15
	moving.axis.last_serial={"1":12,"2147483647":9}
	var partial: Dictionary = moving.duplicate(true)
	partial.serial=32
	partial.door_fraction=0.45
	partial.cover_blocked=true
	var latched: Dictionary = partial.duplicate(true)
	latched.serial=33
	latched.door_fraction=1.0
	latched.electric_latched=true
	latched.door_blocked=true
	var rows: Array = [["initial",initial],["moving_cover",moving],["partial_door",partial],["latched_door",latched]]
	for row in rows:
		var name: String = row[0]
		var saved: Dictionary = row[1]
		var before: Dictionary = saved.duplicate(true)
		var expected: Dictionary = saved.duplicate(true)
		expected.layout_sha256=Migration.TARGET_STATE_SHA
		var migrated: Dictionary = Migration.prepare(saved,Migration.CANDIDATE_PATH)
		_check(migrated.ok and migrated.migrated and _same(migrated.state,expected) and _same(saved,before),name+": only layout digest changes; live caller state is untouched",migrated.code)
		if not migrated.ok: continue
		var repeated: Dictionary = Migration.prepare(migrated.state,Migration.CANDIDATE_PATH)
		_check(repeated.ok and not repeated.migrated and _same(repeated.state,expected),name+": repeated preparation is idempotent and fully validates current state")
		var json_state: Dictionary = JSON.parse_string(JSON.stringify(migrated.state,"",true,true))
		var json_result: Dictionary = Migration.prepare(json_state,Migration.CANDIDATE_PATH)
		_check(json_result.ok and not json_result.migrated and _same(json_result.state,json_state),name+": real JSON reload preserves all values without coerced repairs")
		var client = Cabinet.new()
		var accepted: Dictionary = client.configure(target,migrated.state,false)
		_check(accepted.ok and _same(client.snapshot(),expected),name+": real new Cabinet restores complete motion/roster without helper-side stopping",accepted)
		if accepted.ok:
			var live_before: Dictionary = client.snapshot()
			_check(not client.apply_snapshot(saved).ok and _same(client.snapshot(),live_before),name+": actual client apply_snapshot still atomically refuses old digest")
		client.free()
		var rejected_client = Cabinet.new()
		_check(not rejected_client.configure(target,saved,false).ok and not rejected_client.configured,name+": new client configure cannot implicitly migrate an old packet")
		rejected_client.free()
		var host = Cabinet.new()
		var host_result: Dictionary = host.configure(target,migrated.state,true)
		var stopped: Dictionary = expected.duplicate(true)
		stopped.axis.velocity_mps=0.0
		_check(host_result.ok and _same(host.snapshot(),stopped),name+": existing authority restore stop is separate from migration and preserves position/roster")
		host.free()
		migrated.state.axis.last_serial["1"]=999
		_check(_same(saved,before) and _same(repeated.state,expected),name+": returned states do not alias caller or other results")

func _test_malformed() -> void:
	for raw in [null,[],false,{},42]:
		var result: Dictionary = Migration.prepare(raw,Migration.CANDIDATE_PATH)
		_check(not result.ok and not result.migrated and result.state.is_empty(),"absent/malformed mechanism is never silently initialized",raw)
	var cases: Array = []
	for row in [["unknown","layout_sha256","0".repeat(64)],["extra","unexpected",true],["serial","serial",1.5],["door","door_fraction",1.1],["latch","electric_latched",true],["boolean","cover_blocked",1]]:
		var bad: Dictionary = initial.duplicate(true)
		bad[row[1]]=row[2]
		cases.append([row[0],bad])
	for row in [["velocity_nan","velocity_mps",NAN],["velocity_limit","velocity_mps",2.01],["position_limit","position_m",1.21],["axis_hash","config_sha256","0".repeat(64)],["roster","last_serial",{"01":3}]]:
		var bad: Dictionary = initial.duplicate(true)
		bad.axis[row[1]]=row[2]
		cases.append([row[0],bad])
	var missing: Dictionary = initial.duplicate(true)
	missing.erase("door_blocked")
	cases.append(["missing",missing])
	for row in cases:
		var bad: Dictionary = row[1]
		# Variant bytes preserve NaN payloads without asking JSON to encode a
		# deliberately non-JSON numeric value merely for our no-mutation check.
		var before: PackedByteArray = var_to_bytes(bad)
		var result: Dictionary = Migration.prepare(bad,Migration.CANDIDATE_PATH)
		_check(not result.ok and result.state.is_empty() and var_to_bytes(bad)==before,"full source validation rejects without mutation: "+str(row[0]),result.code)
		if row[0]!="unknown":
			bad.layout_sha256=Migration.TARGET_STATE_SHA
			_check(not Migration.prepare(bad,Migration.CANDIDATE_PATH).ok,"already-current digest does not bypass validation: "+str(row[0]))

func _test_empty_history() -> void:
	var tracker = Progress.new()
	tracker.configure(target)
	var empty: Dictionary = tracker.snapshot()
	var migrated: Dictionary = Migration.prepare(initial,Migration.CANDIDATE_PATH)
	if not migrated.ok: return
	var envelope := {"version":1,"mechanism":migrated.state,"history":empty.duplicate(true)}
	var restored: Dictionary = tracker.prepare_restore(envelope,[],{},[Progress.DISCOVERY])
	_check(restored.ok and tracker.adopt_restore(restored) and _same(tracker.snapshot(),empty) and tracker.fact_for(Progress.EXPOSE).is_empty(),"unobserved branch stays unobserved despite another branch's personal discovery")

func _history_fixture(method: String) -> Dictionary:
	var tracker = Progress.new()
	var configured: Dictionary = tracker.configure(legacy)
	_check(configured.ok,"legacy Progress validates actual frozen layout: "+method)
	var mechanism: Dictionary = initial.duplicate(true)
	mechanism.serial=22
	mechanism.axis.position_m=1.2 if method=="manual" else 0.0
	mechanism.axis.last_serial={"1":3,"2":-1}
	mechanism.door_fraction=0.0 if method=="manual" else 0.75
	# Successful ray result is an explicit trusted-boundary fixture, not a ray
	# executed in this test. Existing physical route evidence remains separate.
	var sample := {"ok":true,"code":"back_observed","mechanism_serial":22,"method":method,
		"observer":[18.0,5.75,-10.6] if method=="manual" else [17.8,2.7,-7.85],
		"cover_position_m":mechanism.axis.position_m,"door_fraction":mechanism.door_fraction,
		"electric_latched":false,"panel_hits":[5,5],"center_hits":[true,true]}
	var observation: Dictionary = tracker.prepare_observation(sample,mechanism)
	_check(observation.ok,"historical successful observation prepares via actual Progress: "+method,observation)
	if not observation.ok: return {}
	# A later door/cover pose must retain the FIRST observation, not be overwritten
	# with its old pose or with a new observation fabricated during migration.
	mechanism.serial=29
	mechanism.axis.position_m=0.35
	mechanism.axis.velocity_mps=-0.25
	mechanism.door_fraction=1.0
	mechanism.electric_latched=true
	var submission: Dictionary = tracker.prepare_retry(observation,mechanism)
	_check(submission.ok,"historical evidence remains valid with latest mechanism: "+method,submission)
	return submission.get("envelope",{}).duplicate(true)

func _test_history(method: String) -> void:
	var envelope: Dictionary = _history_fixture(method)
	if envelope.is_empty(): return
	var before: Dictionary = envelope.duplicate(true)
	var migrated: Dictionary = Migration.prepare(envelope.mechanism,Migration.CANDIDATE_PATH)
	_check(migrated.ok,"known observed mechanism prepares floor upgrade: "+method,migrated.code)
	if not migrated.ok: return
	var next: Dictionary = envelope.duplicate(true)
	next.mechanism=migrated.state
	_check(_same(next.history,before.history) and _same(envelope,before),"migration preserves first method/evidence and never mutates saved envelope: "+method)
	for completed in [false,true]:
		var tracker = Progress.new()
		_check(tracker.configure(target).ok,"target Progress configures reviewed candidate")
		var objectives: Array = [Progress.EXPOSE] if completed else []
		var flags: Dictionary = {Progress.OBSERVED_FLAG:true} if completed else {}
		var discoveries: Array = [Progress.DISCOVERY]
		var old_rejected: Dictionary = tracker.prepare_restore(before,objectives,flags,discoveries)
		_check(not old_rejected.ok,"unchanged Progress rejects old envelope before explicit migration")
		var prepared: Dictionary = tracker.prepare_restore(next,objectives,flags,discoveries)
		_check(prepared.ok and not prepared.needs_init and tracker.adopt_restore(prepared),"early knowledge/completed-ledger fixture restores after migration: "+method+" completed="+str(completed),prepared)
		_check(_same(tracker.snapshot(),before.history),"full original observation survives target restoration")
		_check(tracker.fact_for(Progress.EXPOSE)=={"kind":"fact","target":Progress.FACT_TARGET,"option":method} and tracker.fact_for("I2:distribution_audit:trial").is_empty(),"only existing observation fact remains; no trial/award invented")

func _test_bad_history() -> void:
	var envelope: Dictionary = _history_fixture("manual")
	if envelope.is_empty(): return
	var migrated: Dictionary = Migration.prepare(envelope.mechanism,Migration.CANDIDATE_PATH)
	if not migrated.ok: return
	envelope.mechanism=migrated.state
	for change in ["future","method","hits","observer","missing_history"]:
		var bad: Dictionary = envelope.duplicate(true)
		match change:
			"future": bad.history.evidence.mechanism_serial=30
			"method": bad.history.method="fabricated"
			"hits": bad.history.evidence.center_hits[0]=false
			"observer": bad.history.evidence.observer[1]=100.0
			"missing_history": bad.erase("history")
		var tracker = Progress.new()
		tracker.configure(target)
		var before: Dictionary = tracker.snapshot()
		_check(not tracker.prepare_restore(bad,[],{},[]).ok and _same(tracker.snapshot(),before),"valid migrated mechanism does not repair bad history: "+change)
	var tracker = Progress.new()
	tracker.configure(target)
	_check(not tracker.prepare_restore(envelope,[Progress.EXPOSE],{Progress.OBSERVED_FLAG:true},[]).ok,"migration does not fabricate missing personal receipt for a completed objective")
	_check(not tracker.prepare_restore(envelope,[],{Progress.OBSERVED_FLAG:true},[Progress.DISCOVERY]).ok,"migration does not repair disagreement between story objective and flag")

func _finish() -> void:
	if finished: return
	finished=true
	print("V3_DISTRIBUTION_LAYOUT_MIGRATION_TESTS "+JSON.stringify({"checks":checks,"failures":failures,"engine_errors":logger.errors,"input_hashes":hashes_before,
		"scope":"real Cabinet configuration/strict restore and Progress with explicit saved-state/host-observation fixtures; no disk commit, Session adoption, physical rays, LAN, graphics, playthrough or reward execution"}))
	var failed: bool = not failures.is_empty() or not logger.errors.is_empty()
	OS.remove_logger(logger)
	quit(1 if failed else 0)

static func _hash(value: Variant) -> String:
	return JSON.stringify(value,"",true,true).sha256_text()

static func _same(a: Variant,b: Variant) -> bool:
	return _hash(a)==_hash(b)
