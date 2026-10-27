extends SceneTree
## Pure current-Catalog hardware wire regression. No Store/profile writes, MAIN,
## Flight/Custody reconstruction, sockets, LAN or gameplay acceptance is claimed.
const Contract = preload("res://scripts/v3/network/twin_build_contract.gd")
const Catalog = preload("res://scripts/v2/catalog.gd")
const FRAMES := ["tr01", "hx02", "ag03", "nx04", "sh05", "at06"]
var checks: Array = []
var finished := false

class ErrorLogger extends Logger:
	var guard := Mutex.new()
	var errors: Array = []
	func _log_error(function: String, file: String, line: int, code: String, rationale: String, _notify: bool, kind: int, _traces: Array[ScriptBacktrace]) -> void:
		if kind == Logger.ERROR_TYPE_WARNING: return
		guard.lock()
		errors.append({"function":function, "file":file, "line":line, "code":code, "rationale":rationale, "kind":kind})
		guard.unlock()
	func snapshot() -> Array:
		guard.lock()
		var result: Array = errors.duplicate(true)
		guard.unlock()
		return result

var logger := ErrorLogger.new()

func _initialize() -> void:
	OS.add_logger(logger)
	create_timer(8.0).timeout.connect(func() -> void:
		if not finished:
			_check(false, "bounded pure build contract test completes")
			_finish())
	_run.call_deferred()

func _check(condition: bool, label: String, evidence: Variant = null) -> bool:
	checks.append({"ok":condition, "label":label, "evidence":evidence})
	if not condition: printerr("BUILD_CONTRACT_FAIL " + label + " " + JSON.stringify(evidence))
	return condition

func _wire(frame: String = "tr01") -> Dictionary:
	return {"airframe_id":frame, "slots":{"weapon":"pulse_base", "tool":"scan_base",
		"drive":"stock_drive", "battery":"stock_battery", "utility":"guard_base"}}

func _reject(value: Variant, expected_code: String, label: String, catalog_error: String = "") -> void:
	var before: PackedByteArray = var_to_bytes(value)
	var result: Dictionary = Contract.validate(value)
	var rejected: bool = not result.get("ok", true) and result.get("code") == expected_code
	if not catalog_error.is_empty(): rejected = rejected and _has_error(result, catalog_error)
	_check(rejected and var_to_bytes(value) == before, label, result)

func _has_error(result: Dictionary, code: String) -> bool:
	for row: Variant in result.get("errors", []):
		if row is Dictionary and row.get("code") == code: return true
	return false

func _run() -> void:
	var digest: String = Contract.fingerprint()
	_check(digest.length() == 64 and digest == FileAccess.get_sha256(Catalog.CONTENT_PATH),
		"fingerprint hashes the actual current Catalog bytes")
	_test_defaults()
	_test_exact_shape_after_cache()
	_test_catalog_boundaries()
	_test_result_isolation()
	_test_original_role_metadata()
	await process_frame
	_finish()

func _test_defaults() -> void:
	for frame: String in FRAMES:
		var native: Dictionary = Catalog.default_build(frame)
		var before: PackedByteArray = var_to_bytes(native)
		var wire: Dictionary = Contract.view(native)
		var checked: Dictionary = Contract.validate(wire)
		if not _check(checked.get("ok", false) and wire == _wire(frame),
			"default native stock projects into exact five explicit IDs: " + frame, checked): continue
		_check(var_to_bytes(native) == before and Contract.matches(native, wire),
			"native default is unchanged and stock spelling is equivalent: " + frame)
		var direct: Dictionary = Catalog.resolve_build(native)
		_check(direct.get("valid", false) and checked["resolved"]["derived"] == direct["derived"],
			"all derived statistics are the original host Catalog result: " + frame)
		_check(checked["build"]["slots"]["drive"] == "stock_drive" and checked["build"]["slots"]["battery"] == "stock_battery",
			"returned native hardware has explicit canonical stock: " + frame)
	var decoded: Variant = JSON.parse_string(JSON.stringify(_wire(), "", true, true))
	_check(Contract.validate(decoded).get("ok", false), "JSON wire round trip retains the exact ID-only contract")
	_check(not Contract.matches(Catalog.default_build("tr01"), _wire("hx02")),
		"legal but different airframe cannot match a native build")
	var projection: Dictionary = Contract.view(Catalog.default_build())
	projection["slots"]["weapon"] = "burst_capacitor"
	_check(Contract.view(Catalog.default_build()) == _wire(), "caller mutation of a projected wire cannot alter later projection")

func _test_exact_shape_after_cache() -> void:
	# Warm the exact legitimate identity first. Every invalid candidate below
	# reuses that identity wherever possible; the cache must never skip shape.
	_check(Contract.validate(_wire()).get("ok", false), "legal identity warmed before shape rejection checks")
	var extra: Dictionary = _wire()
	extra["derived"] = {"mass_kg":0.001, "health":999999.0}
	_reject(extra, "BUILD_WIRE_FIELDS", "cached identity rejects supplied derived stats")
	extra = _wire()
	extra["mass_kg"] = 0.001
	_reject(extra, "BUILD_WIRE_FIELDS", "cached identity rejects a top-level physical statistic")
	extra = _wire()
	extra["build_id"] = "remote_claim"
	_reject(extra, "BUILD_WIRE_FIELDS", "cached identity rejects remote native metadata")
	var missing: Dictionary = _wire()
	missing.erase("airframe_id")
	_reject(missing, "BUILD_WIRE_FIELDS", "required airframe field cannot be absent")
	missing = _wire()
	missing["slots"].erase("tool")
	_reject(missing, "BUILD_WIRE_SLOTS", "required fifth module cannot be absent")
	extra = _wire()
	extra["slots"]["health"] = 999.0
	_reject(extra, "BUILD_WIRE_SLOTS", "cached slot identity rejects an extra stat key")
	var wrong_type: Dictionary = _wire()
	wrong_type["slots"] = []
	_reject(wrong_type, "BUILD_WIRE_SLOTS", "slots must be a dictionary")
	wrong_type = _wire()
	wrong_type["slots"]["weapon"] = 20
	_reject(wrong_type, "BUILD_WIRE_MODULE_ID", "module IDs cannot be numeric")
	wrong_type = _wire()
	wrong_type["slots"]["weapon"] = StringName("pulse_base")
	_reject(wrong_type, "BUILD_WIRE_MODULE_ID", "StringName module ID does not masquerade as JSON String")
	var named_key: Dictionary = {"slots":_wire()["slots"]}
	named_key[StringName("airframe_id")] = "tr01"
	_reject(named_key, "BUILD_WIRE_FIELDS", "StringName top-level key does not bypass exact String keys")
	var named_slot: Dictionary = _wire()
	named_slot["slots"].erase("tool")
	named_slot["slots"][StringName("tool")] = "scan_base"
	_reject(named_slot, "BUILD_WIRE_SLOTS", "StringName slot key does not bypass exact String keys")
	var alias: Dictionary = _wire()
	alias["slots"]["drive"] = "stock"
	_reject(alias, "BUILD_WIRE_MODULE_ID", "legacy stock alias is accepted only by native projection, never on wire")
	wrong_type = _wire()
	wrong_type["airframe_id"] = "a".repeat(65)
	_reject(wrong_type, "BUILD_WIRE_FRAME_ID", "oversized frame ID is bounded before Catalog resolution")
	wrong_type = _wire()
	wrong_type["slots"]["tool"] = "scan_base\n"
	_reject(wrong_type, "BUILD_WIRE_MODULE_ID", "control characters are refused in module IDs")
	_reject([], "BUILD_WIRE_FIELDS", "non-dictionary wire is rejected without mutation")
	_check(not Contract.matches(Catalog.default_build(), extra), "matches also rejects a warmed identity carrying extra fields")
	_check(Contract.validate(_wire()).get("ok", false), "all failed candidates leave the valid cached identity usable")

func _test_catalog_boundaries() -> void:
	var mismatched: Dictionary = _wire()
	mismatched["slots"]["tool"] = "pulse_base"
	_reject(mismatched, "BUILD_WIRE_CATALOG_REJECTED", "host original Catalog rejects a real module in the wrong slot", "BUILD_SLOT_MISMATCH")
	var unknown: Dictionary = _wire()
	unknown["slots"]["tool"] = "qa_unknown_module"
	_reject(unknown, "BUILD_WIRE_CATALOG_REJECTED", "host original Catalog rejects an unknown module ID", "BUILD_UNKNOWN_MODULE")
	unknown = _wire()
	unknown["airframe_id"] = "qa_unknown_frame"
	_reject(unknown, "BUILD_WIRE_CATALOG_REJECTED", "host original Catalog rejects an unknown airframe", "BUILD_UNKNOWN_FRAME")
	# Current actual AG03 base24 + weapon35 + tool5 + drive12 + utility8 =
	# 84 PU against stock 75. No Catalog values or statistics are injected.
	var over_power: Dictionary = _wire("ag03")
	over_power["slots"]["weapon"] = "burst_capacitor"
	over_power["slots"]["drive"] = "racing_drive"
	_reject(over_power, "BUILD_WIRE_CATALOG_REJECTED", "actual 84/75 PU AG03 hardware remains rejected", "BUILD_OVER_POWER")
	var different: Dictionary = _wire()
	different["slots"]["utility"] = "reinforced_guard"
	var checked: Dictionary = Contract.validate(different)
	_check(checked.get("ok", false) and checked["build"]["slots"]["utility"] == "reinforced_guard"
		and checked["resolved"]["derived"]["build_hash"] != Contract.validate(_wire())["resolved"]["derived"]["build_hash"],
		"another legal sixth-ID combination has its own Catalog result")
	_check(not Contract.matches(Catalog.default_build(), different), "module mismatch is not hidden by matching frame or cached defaults")

func _test_result_isolation() -> void:
	var wire: Dictionary = _wire()
	var before: PackedByteArray = var_to_bytes(wire)
	var baseline: Dictionary = Contract.validate(wire)
	var changed: Dictionary = Contract.validate(wire)
	if not _check(baseline.get("ok", false) and changed.get("ok", false), "two valid cached returns prepared for isolation"): return
	changed["build"]["slots"]["tool"] = "cargo_winch"
	_check(changed["resolved"]["build"]["slots"]["tool"] == "scan_base",
		"top-level returned build does not alias its own returned resolved build")
	changed["resolved"]["build"]["slots"]["weapon"] = "burst_capacitor"
	changed["resolved"]["derived"]["mass_kg"] = -100.0
	changed["resolved"]["derived"]["modifiers"]["guard_enabled"] = false
	changed["resolved"]["derived"]["rotor_sweeps"][0]["position_m"][0] = 999.0
	changed["resolved"]["derived"]["mounts"]["tool"]["position_m"][0] = 999.0
	changed["resolved"]["errors"].append({"code":"qa_mutation"})
	var later: Dictionary = Contract.validate(wire)
	_check(later == baseline and later.get("ok", false), "nested stats, geometry, slots and error mutation never pollute a later cached validation")
	_check(var_to_bytes(wire) == before, "validation and mutated result never write the original wire")

func _test_original_role_metadata() -> void:
	# A role-shaped pure input fixture, not a valid physical moving snapshot.
	# Only metadata preservation is tested here; MAIN roster/Joint tests own
	# actual suspended cargo restoration and native momentum evidence.
	var native: Dictionary = Catalog.default_build("hx02")
	native["build_id"] = "qa_original_saved_role_build_id"
	var role: Dictionary = {"identity":"qa_original_cargo_owner", "build":native, "peer_hint":2}
	var original: PackedByteArray = var_to_bytes(role)
	var view: Dictionary = Contract.view(role["build"])
	var checked: Dictionary = Contract.validate(view)
	_check(checked.get("ok", false) and Contract.matches(role["build"], view),
		"saved-role native metadata and legacy stock match the same legal wire hardware")
	_check(var_to_bytes(role) == original and role["build"]["build_id"] == "qa_original_saved_role_build_id"
		and role["build"]["slots"]["drive"] == "stock" and role["build"]["slots"]["battery"] == "stock",
		"projection, validation and matching preserve every original saved-role byte")
	_check(not checked["build"].has("identity") and checked["build"]["build_id"] != role["build"]["build_id"],
		"reconstructed wire build does not replace or claim the original saved native role identity")

func _finish() -> void:
	if finished: return
	finished = true
	var errors: Array = logger.snapshot()
	var failures: Array = checks.filter(func(row: Dictionary) -> bool: return not row["ok"])
	print("BUILD_CONTRACT_RESULT " + JSON.stringify({"checks":checks.size(), "failures":failures.size(),
		"engine_errors":errors, "details":checks, "catalog_sha256":Contract.fingerprint(),
		"scope":"Pure exact build wire/current Catalog/copy-isolation regression only. No Store/profile writes, saved physical cargo restore, MAIN, ENet or LAN acceptance."}))
	quit(0 if failures.is_empty() and errors.is_empty() else 1)
