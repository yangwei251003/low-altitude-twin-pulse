extends SceneTree
## Pure historical-envelope compatibility. No MAIN, restore, physics bodies,
## profile repository/Store, contact claim or natural-goal completion.
const Safe = preload("res://scripts/v3/gameplay/canal/canal_checkpoint/canal_checkpoint.gd")
const Wait = preload("res://scripts/v3/gameplay/canal/canal_checkpoint/canal_wait_checkpoint.gd")
const Rules = Wait.Rules
const Executor = Wait.Executor
const SOURCE := "res://artifacts/v3/normal-distribution-20261021_041616_4b196777/normal-distribution-20261021_041616_4b196777.json"
const SOURCE_SHA256 := "e6b8e72a466c0aa2b09a0d2613c175904be6236346d50aa77af76652daa8b6f6"
const OLD := "2b3614b9f1dcb9723ceb04d466d74ec053e69cebff89a1a4d038ea4d5a90e7d5"
class ErrorLogger extends Logger:
	var errors: Array = []
	func _log_error(function: String, file: String, line: int, code: String, rationale: String, _notify: bool, kind: int, _trace: Array[ScriptBacktrace]) -> void:
		if kind != Logger.ERROR_TYPE_WARNING:
			errors.append({"function":function,"file":file,"line":line,"code":code,"rationale":rationale,"kind":kind})
var logger := ErrorLogger.new()
var checks: Array = []
var failures: Array[String] = []

func _initialize() -> void:
	OS.add_logger(logger)
	_run.call_deferred()

func _run() -> void:
	var bytes: PackedByteArray=FileAccess.get_file_as_bytes(SOURCE)
	if not _check(not bytes.is_empty() and FileAccess.get_sha256(SOURCE)==SOURCE_SHA256,"exact original legal33 report is a read-only historical fixture"): _finish(); return
	var parsed: Variant=JSON.parse_string(bytes.get_string_from_utf8())
	if not _check(parsed is Dictionary,"original report JSON parses"): _finish(); return
	var world: Dictionary=parsed.get("fresh_reader",{}).get("world",{})
	var environment: Dictionary=world.get("environment",{})
	var saved: Variant=environment.get("I2_canal")
	if not _check(saved is Dictionary and saved.get("kind")==Wait.KIND and saved.get("layout_sha256")==OLD and world.get("actions",{}).get("opening",{}).get("completed",[]).size()==33,"actual report contains its complete old WAIT envelope, not a constructed checkpoint"): _finish(); return
	var original: Dictionary=saved
	var original_bytes: PackedByteArray=var_to_bytes(original)
	var environment_bytes: PackedByteArray=var_to_bytes(environment)
	_check(not environment.has("I2_canal_preparation"),"this exact fixture has no preparation seal; no synthetic seal is introduced")
	_check(Safe.LEGACY_EMPTY_BUFFER_LAYOUT==OLD and Safe.layout_fingerprint(true)==OLD,"current canonical layout without the new side bay and with the old Buffer coordinate reproduces exact known old hash")
	_check(Executor.BERTH_POINTS[Rules.BUFFER]==Vector3(6,5,8) and Safe.layout_fingerprint()!=OLD,"current canonical north Buffer is relocated; current fingerprint is distinct")
	_check(original.rules.buffer_enabled==false and original.rules.carrier_anchor!=Rules.BUFFER,"actual old WAIT keeps Buffer disabled and a different carrier anchor")
	var old_valid: Dictionary=Wait.validate(original)
	_check(Safe.layout_matches(original) and old_valid.get("ok",false),"original full WAIT validator accepts the exact old disabled/unreferenced Buffer envelope",old_valid)
	_check(var_to_bytes(original)==original_bytes,"old hash acceptance never upgrades or mutates the original envelope")

	# A local test copy with ONLY its hash changed exercises the current-hash
	# branch. It is not a fresh native capture and is never restored or saved.
	var current: Dictionary=original.duplicate(true)
	current["layout_sha256"]=Safe.layout_fingerprint()
	var current_before: PackedByteArray=var_to_bytes(current)
	var current_valid: Dictionary=Wait.validate(current)
	_check(Safe.layout_matches(current) and current_valid.get("ok",false),"same WAIT values validate through the current-hash branch",current_valid)
	var old_again: Dictionary=current.duplicate(true)
	old_again["layout_sha256"]=OLD
	_check(var_to_bytes(old_again)==original_bytes and var_to_bytes(current)==current_before,"current-hash test changes exactly one field and validators remain read-only")

	for change: Dictionary in [
		{"label":"unknown layout hash","path":["layout_sha256"],"value":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"},
		{"label":"Buffer enabled","path":["rules","buffer_enabled"],"value":true},
		{"label":"carrier anchored at Buffer","path":["rules","carrier_anchor"],"value":Rules.BUFFER},
		{"label":"cold cargo ledger holder Buffer","path":["rules","cassettes",Rules.CASSETTES[0],"holder"],"value":Rules.BUFFER},
		{"label":"hot cargo ledger holder Buffer","path":["rules","cassettes",Rules.CASSETTES[1],"holder"],"value":Rules.BUFFER},
		{"label":"pending action source Buffer","path":["rules","pending_action","source"],"value":Rules.BUFFER},
		{"label":"pending action destination Buffer","path":["rules","pending_action","destination"],"value":Rules.BUFFER},
		{"label":"physical custody berth Buffer","path":["custody","cargos",Rules.CASSETTES[1],"berth"],"value":Rules.BUFFER},
		{"label":"path string containing Buffer","path":["workbench","compatibility_probe"],"value":"/scene/CandidateBerth_north_buffer/shape"},
		{"label":"deep Array String value Buffer","path":["workbench","compatibility_probe"],"value":[{"inside":["ordinary",Rules.BUFFER]}]},
		{"label":"nested Dictionary String key Buffer","path":["workbench","compatibility_probe"],"value":{Rules.BUFFER:0}}
	]:
		var changed: Dictionary=original.duplicate(true)
		_set_at(changed,change.path,change.value)
		_reject(changed,str(change.label),true)
	var absent: Dictionary=original.duplicate(true)
	absent.rules.erase("buffer_enabled")
	_reject(absent,"old compatibility requires explicit false Buffer state",true)
	var nested: Variant="ordinary"
	for unused: int in range(66): nested=[nested]
	var overdeep: Dictionary=original.duplicate(true)
	overdeep.workbench["compatibility_probe"]=nested
	_reject(overdeep,"legacy recursive scan fails closed beyond its 64-level bound",true)

	# Compatibility is only a layout gate, never a replacement for the remaining
	# original strict WAIT rules, rigid shape/filter, water and Joint validation.
	for change: Dictionary in [
		{"label":"non-Buffer collision filter corruption","path":["bodies",Rules.CASSETTES[1],"mask"],"value":0},
		{"label":"non-Buffer cargo shape corruption","path":["bodies",Rules.CASSETTES[1],"shape_size"],"value":[.5,.4,.4]},
		{"label":"original Joint local anchor corruption","path":["custody","joint","local_a"],"value":[99.0,0.0,0.0]},
		{"label":"original water quantity corruption","path":["rules","water","nodes","I2:canal_cooling_reservoir","clean_ml"],"value":-1},
		{"label":"original physics rate corruption","path":["physics_hz"],"value":120},
		{"label":"original clock consistency corruption","path":["rule_usec"],"value":int(original.rule_usec)+1000}
	]:
		for baseline: Dictionary in [original,current]:
			var changed: Dictionary=baseline.duplicate(true)
			_set_at(changed,change.path,change.value)
			_reject(changed,str(change.label)+(" [legacy]" if baseline.layout_sha256==OLD else " [current]"),false)
	_check(var_to_bytes(original)==original_bytes and var_to_bytes(environment)==environment_bytes,"all original envelope/environment bytes remain identical, including preparation-seal absence")
	_check(FileAccess.get_file_as_bytes(SOURCE)==bytes and FileAccess.get_sha256(SOURCE)==SOURCE_SHA256,"historical report bytes remain unchanged; no profile has been opened or cloned")
	_finish()

func _set_at(row: Dictionary, path: Array, value: Variant) -> void:
	var cursor: Dictionary=row
	for index: int in range(path.size()-1): cursor=cursor[str(path[index])]
	cursor[str(path[-1])]=value

func _reject(row: Dictionary, label: String, expect_layout_rejection: bool) -> void:
	var before: PackedByteArray=var_to_bytes(row)
	var gate: bool=Safe.layout_matches(row)
	var valid: Dictionary=Wait.validate(row)
	_check(gate!=expect_layout_rejection and not valid.get("ok",false),label+" is rejected by the correct gate without relaxing strict validation",{"layout_gate":gate,"expected_layout_reject":expect_layout_rejection,"validator":valid})
	_check(var_to_bytes(row)==before,label+" rejection is read-only")

func _check(ok: bool, label: String, detail: Variant=null) -> bool:
	checks.append({"passed":ok,"label":label,"detail":detail})
	if not ok: failures.append(label)
	return ok

func _finish() -> void:
	print("CANAL_LAYOUT_COMPAT_RESULT "+JSON.stringify({"ok":failures.is_empty() and logger.errors.is_empty(),"checks":checks,"failures":failures,"engine_errors":logger.errors,"source_report_sha256":SOURCE_SHA256,"scope":"Pure exact historical WAIT/current-hash compatibility and corruption rejection only. No native restore/capture/Store/profile, no current contact or natural34 completion claim."},"",true,true))
	quit(0 if failures.is_empty() and logger.errors.is_empty() else 1)

