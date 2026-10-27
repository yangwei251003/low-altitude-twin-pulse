extends SceneTree
## Store serialization-boundary regression, not a Session/playthrough fixture.
## Writes only a fresh owned user://qa_v3_persistent_values/... directory.
const Store = preload("res://scripts/v3/core/twin_world_store.gd")
const VALUE_PATH := "world.environment.qa_persistent_values"
var checks: Array[Dictionary] = []
var failures: Array[String] = []
var finished := false
var qa_path := ""

class TestLogger extends Logger:
	var errors: Array = []
	func _log_error(function: String, file: String, line: int, code: String, rationale: String, _notify: bool, kind: int, _backtraces: Array[ScriptBacktrace]) -> void:
		errors.append({"function":function,"file":file,"line":line,"code":code,"rationale":rationale,"type":kind})

var logger := TestLogger.new()

func _init() -> void:
	OS.add_logger(logger)
	_run.call_deferred()

func _run() -> void:
	create_timer(20.0).timeout.connect(func():
		if not finished:
			_check(false,"bounded persistent-value test timeout")
			_finish())
	qa_path = "user://qa_v3_persistent_values/" + str(Time.get_unix_time_from_system()).replace(".","_") + "_" + Crypto.new().generate_random_bytes(8).hex_encode()
	_check(not DirAccess.dir_exists_absolute(qa_path) and not FileAccess.file_exists(qa_path),"only a new isolated QA directory is used")
	if not failures.is_empty():
		_finish()
		return
	var store = Store.new(qa_path)
	_check(store.has_method("matches_persisted_value"),"production Store exposes the live-to-saved comparison API")
	if not store.has_method("matches_persisted_value"):
		_finish()
		return
	var loaded: Dictionary = store.load_profile()
	_check(loaded.ok,"actual isolated Store opens",loaded)
	if not loaded.ok:
		_finish()
		return
	# Exact binary value from the real clinic-flow failure (20261018_201457).
	# Arithmetic avoids rounding the decimal literal before the Store sees it.
	var live := {"fractional_usec":3.0 / 68719476736.0,"stable_usec":36,
		"nested":{"count":2,"readings":[0,2.0,{"quantity":200,"unit":"L","enabled":true}]},
		"label":"clinic","optional":null}
	var original_live: Dictionary = live.duplicate(true)
	var tx := {"id":"persistent-values-baseline","set":{VALUE_PATH:live}}
	var committed: Dictionary = store.commit(tx)
	_check(committed.ok,"real Store commits the binary-fraction and nested-number fixture",committed)
	if not committed.ok:
		_finish()
		return
	var saved_snapshot: Dictionary = store.snapshot()
	var saved: Dictionary = saved_snapshot.world.environment.qa_persistent_values
	var disk = Store.new(qa_path)
	var reloaded: Dictionary = disk.load_profile()
	_check(reloaded.ok and disk.snapshot()==saved_snapshot,"independent Store readback is exactly the committed snapshot",reloaded)
	var files_before: Dictionary = _file_hashes(qa_path)
	var branch_hash: String = store.branch_world_hash("main")
	var original_saved: Dictionary = saved.duplicate(true)
	_check(live==original_live,"Store commit does not rewrite the caller's live values")
	_check(saved.stable_usec is float and live.stable_usec is int,"fixture reaches real JSON int-to-float readback")
	_check(bool(store.call("matches_persisted_value",live,saved)),"exact binary clinic remainder matches its actual persisted readback",
		{"live_fraction":JSON.stringify(live.fractional_usec,"",true,true),
		"saved_fraction":JSON.stringify(saved.fractional_usec,"",true,true),
		"legacy_canonical_equal":store._canonical(live)==store._canonical(saved)})
	_check(bool(disk.call("matches_persisted_value",live,disk.snapshot().world.environment.qa_persistent_values)),"same live state also matches an independently loaded Store")
	var mixed: Dictionary = live.duplicate(true)
	mixed.stable_usec=36.0
	mixed.nested.count=2.0
	mixed.nested.readings[0]=0.0
	mixed.nested.readings[1]=2
	mixed.nested.readings[2].quantity=200.0
	_check(bool(store.call("matches_persisted_value",mixed,saved)),"nested integral int/float representations preserve the same saved value")
	_check(not bool(store.call("matches_persisted_value",saved,live)),"comparison is directional: unparsed live data is not a saved snapshot")

	var negatives: Array[Dictionary] = []
	var changed: Dictionary = live.duplicate(true)
	changed.fractional_usec += 1.0
	negatives.append({"label":"a real +1 microsecond fractional change remains dirty","value":changed})
	changed=live.duplicate(true)
	changed.stable_usec += 1
	negatives.append({"label":"a +1 stable microsecond change remains dirty","value":changed})
	changed=live.duplicate(true)
	changed.nested.readings[1]=2.125
	negatives.append({"label":"a representable fractional reading change remains dirty","value":changed})
	changed=live.duplicate(true)
	changed.nested.readings[2].enabled=1
	negatives.append({"label":"numeric one cannot substitute for boolean true","value":changed})
	changed=live.duplicate(true)
	changed.nested.count="2"
	negatives.append({"label":"numeric text cannot substitute for a number","value":changed})
	changed=live.duplicate(true)
	changed.nested.readings.append(0)
	negatives.append({"label":"array length remains part of saved state","value":changed})
	changed=live.duplicate(true)
	changed.nested.readings[0]=[0]
	negatives.append({"label":"array nesting cannot substitute for a scalar","value":changed})
	changed=live.duplicate(true)
	changed.nested.readings.reverse()
	negatives.append({"label":"array order remains meaningful","value":changed})
	changed=live.duplicate(true)
	changed.erase("optional")
	negatives.append({"label":"missing key differs from an explicit null","value":changed})
	changed=live.duplicate(true)
	changed["unexpected"]=false
	negatives.append({"label":"additional keys are not ignored","value":changed})
	for item in negatives:
		_check(not bool(store.call("matches_persisted_value",item.value,saved)),item.label)

	var repeated := true
	for unused in range(8):
		repeated = repeated and bool(store.call("matches_persisted_value",live,saved))
	_check(repeated,"unchanged live state repeatedly matches the same saved value")
	_check(live==original_live and saved==original_saved,"comparison mutates neither live nor saved dictionaries")
	_check(store.snapshot()==saved_snapshot and store.branch_world_hash("main")==branch_hash,"comparison changes no generation, world, branch fingerprint or ledger")
	_check(_file_hashes(qa_path)==files_before,"comparison creates, removes and rewrites no QA files")
	var duplicate: Dictionary = store.commit(tx)
	_check(duplicate.ok and duplicate.duplicate and store.snapshot()==saved_snapshot,"existing transaction fingerprint still recognizes an exact retry",duplicate)
	_check(_file_hashes(qa_path)==files_before,"duplicate transaction preserves published bytes")
	# The comparator itself never writes. A real later Store transaction must still
	# persist an actual changed value and advance exactly one generation.
	changed=live.duplicate(true)
	changed.fractional_usec += 1.0
	var updated: Dictionary = store.commit({"id":"persistent-values-changed","set":{VALUE_PATH:changed}})
	_check(updated.ok and int(store.snapshot().generation)==int(saved_snapshot.generation)+1,"actual changed transaction publishes exactly one additional generation",updated)
	var latest = Store.new(qa_path)
	var latest_loaded: Dictionary = latest.load_profile()
	_check(latest_loaded.ok and bool(latest.call("matches_persisted_value",changed,latest.snapshot().world.environment.qa_persistent_values)),"changed value survives a separate Store reload")
	_check(not bool(latest.call("matches_persisted_value",live,latest.snapshot().world.environment.qa_persistent_values)),"old live value cannot match the newly saved microsecond change")
	_finish()

func _file_hashes(path: String) -> Dictionary:
	var result: Dictionary = {}
	var directory = DirAccess.open(path)
	if directory==null: return result
	for file in directory.get_files():
		result[file]=FileAccess.get_sha256(path.path_join(file))
	return result

func _check(ok: bool,label: String,detail: Variant = null) -> void:
	checks.append({"passed":ok,"label":label,"detail":detail})
	if not ok: failures.append(label)

func _finish() -> void:
	if finished: return
	finished=true
	if not logger.errors.is_empty(): _check(false,"no engine errors",logger.errors)
	print("PERSISTENT_VALUES checks=%d failures=%d qa_path=%s" % [checks.size(),failures.size(),ProjectSettings.globalize_path(qa_path)])
	print("PERSISTENT_VALUES_RESULT "+JSON.stringify({"passed":failures.is_empty(),"checks":checks,"failures":failures,"engine_errors":logger.errors,"qa_path":qa_path,
		"limits":["Real isolated Store commit/readback and serialization comparison only; no Session callbacks, migration, physics, network, GPU or playthrough is exercised."]}))
	quit(0 if failures.is_empty() else 1)
