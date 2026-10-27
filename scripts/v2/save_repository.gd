class_name SaveRepositoryV2
extends RefCounted

const SCHEMA_VERSION = 2
const CONTENT_VERSION = "2.2-living-world-2026-10-14"
const LayoutMigration = preload("res://scripts/v2/layout_save_migration.gd")
const MAX_FILE_BYTES = 8 * 1024 * 1024
const MAX_INTEGER = 9007199254740991
const MUTABLE_ROOTS = ["owned_airframes", "owned_modules", "builds", "selected_build_id", "campaign", "world", "records", "settings", "legacy_v1"]

var data: Dictionary
var notice: String = ""
var root_path: String
var failure_point: String = ""
var read_only: bool = false
var pending_transaction: Dictionary = {}
var _pending_generation: Dictionary = {}
var _busy: bool = false
var _load_failed: bool = false
var _loaded: bool = false
var _layout_backup_ready: bool = false

func _init(path: String = "user://profiles/default") -> void:
	root_path = path.trim_suffix("/")
	data = defaults()

func defaults() -> Dictionary:
	return {
		"schema_version":2, "content_version":CONTENT_VERSION, "generation":0,
		"profile_id":Crypto.new().generate_random_bytes(16).hex_encode(), "saved_at_utc":"",
		"wallet":{"parts":0}, "owned_airframes":["tr01"],
		"owned_modules":["pulse_base", "scan_base", "guard_base"],
		"builds":[{"schema_version":2, "build_id":"tr01_default", "airframe_id":"tr01", "slots":{"weapon":"pulse_base", "tool":"scan_base", "drive":"stock", "battery":"stock", "utility":"guard_base"}, "cosmetic_id":"ivory_teal", "cargo_kg":0.0}],
		"selected_build_id":"tr01_default",
		"campaign":{"completed_stages":[], "completed_missions":[], "active_checkpoint":null},
		"world":{"layout_revision":1, "regions":{}, "discovered_pois":[], "restored_objects":{}, "outposts":[]},
		"ledger":{"receipts":[], "repeat_counters":{}}, "records":[],
		"settings":{"difficulty":0, "auto_fire":false, "volume":0.55, "camera":0, "fullscreen":false, "input":{}, "control_mode":"assisted", "quality":"standard"},
		"legacy_v1":{"source_sha256":"", "completed":[], "records":{}, "facility":[], "unmapped":[]}
	}


func ensure_layout_revision() -> Dictionary:
	if not _loaded and not load_profile(): return _fail("LAYOUT_MIGRATION_FAILED: profile_load")
	if read_only or _load_failed: return _fail("LAYOUT_MIGRATION_FAILED: profile_read_only")
	var proposal = LayoutMigration.plan(data, CatalogV2.content())
	if not proposal.ok: return _fail(str(proposal.error))
	if not bool(proposal.get("changed", false)): return _result(true)
	if not _backup_layout_sources(): return _fail("LAYOUT_MIGRATION_FAILED: backup")
	var result = commit({"id":"migration:world-layout:0-to-1","set":proposal.set})
	if result.ok and int(data.world.get("layout_revision", 0)) != LayoutMigration.REVISION:
		return _fail("LAYOUT_MIGRATION_FAILED: stale_receipt")
	if result.ok: result["migrated"] = true
	return result

func _backup_layout_sources() -> bool:
	if _layout_backup_ready: return true
	var files = _generation_files()
	if files.is_empty():
		_layout_backup_ready = true
		return true
	var destination = root_path.path_join("layout_backups").path_join("revision_0_generation_%06d" % int(data.generation))
	if DirAccess.make_dir_recursive_absolute(destination) != OK: return false
	if FileAccess.file_exists(root_path.path_join("manifest.json")): files.append("manifest.json")
	for name in files:
		if not _copy_migration_source(root_path.path_join(name), destination.path_join(name)): return false
	_layout_backup_ready = true
	return true

func _result(ok: bool, error: String = "", duplicate: bool = false) -> Dictionary:
	return {"ok":ok, "error":error, "duplicate":duplicate}

func _fail(error: String) -> Dictionary:
	notice = error
	return _result(false, error)

func _finite_number(value) -> bool:
	return (value is int or value is float) and is_finite(float(value))

func _integer(value, minimum: int = 0) -> bool:
	return _finite_number(value) and float(value) >= minimum and float(value) <= MAX_INTEGER and floor(float(value)) == float(value)

func _strings(value, maximum: int = 10000) -> bool:
	if not value is Array or value.size() > maximum:return false
	for item in value:
		if not item is String or item.length() > 256:return false
	return true

func _tree_valid(value, depth: int = 0) -> bool:
	if depth > 24:return false
	if value == null or value is bool:return true
	if value is String or value is StringName:return str(value).length() <= 4096
	if value is int or value is float:return _finite_number(value) and absf(float(value)) <= MAX_INTEGER
	if value is Array:
		if value.size() > 20000:return false
		for item in value:
			if not _tree_valid(item, depth + 1):return false
		return true
	if value is Dictionary:
		if value.size() > 20000:return false
		for key in value:
			if not (key is String or key is StringName) or str(key).length() > 256 or not _tree_valid(value[key], depth + 1):return false
		return true
	return false

func _validate(candidate: Dictionary) -> bool:
	if not _tree_valid(candidate) or candidate.get("schema_version") != SCHEMA_VERSION:return false
	if not _integer(candidate.get("generation")) or not candidate.get("profile_id") is String or candidate.profile_id.is_empty():return false
	for key in ["content_version", "saved_at_utc", "selected_build_id"]:
		if not candidate.get(key) is String or candidate[key].length() > 256:return false
	for key in ["wallet", "campaign", "world", "ledger", "settings", "legacy_v1"]:
		if not candidate.get(key) is Dictionary:return false
	if not _integer(candidate.wallet.get("parts")):return false
	if not _strings(candidate.get("owned_airframes")) or not _strings(candidate.get("owned_modules")):return false
	if not candidate.get("builds") is Array or candidate.builds.size() > 1000:return false
	for build in candidate.builds:
		if not build is Dictionary or not build.get("build_id") is String or not build.get("airframe_id") is String or not build.get("slots") is Dictionary:return false
		for slot in ["weapon", "tool", "drive", "battery", "utility"]:
			if not build.slots.get(slot) is String:return false
	if not _strings(candidate.campaign.get("completed_stages")) or not _strings(candidate.campaign.get("completed_missions")):return false
	if not candidate.campaign.has("active_checkpoint"):return false
	var checkpoint = candidate.campaign.active_checkpoint
	if checkpoint != null and not checkpoint is Dictionary and not checkpoint is String:return false
	if not _strings(candidate.world.get("discovered_pois"), 5000) or not _strings(candidate.world.get("outposts")):return false
	if not candidate.world.get("regions") is Dictionary or not candidate.world.get("restored_objects") is Dictionary:return false
	if not _strings(candidate.ledger.get("receipts"), 20000) or not candidate.ledger.get("repeat_counters") is Dictionary:return false
	for count in candidate.ledger.repeat_counters.values():
		if not _integer(count):return false
	if not candidate.get("records") is Array or candidate.records.size() > 10000:return false
	for record in candidate.records:
		if not record is Dictionary:return false
		for metric in ["time", "seconds", "damage", "collisions", "best_time", "best_damage", "best_precision"]:
			if record.has(metric) and (not _finite_number(record[metric]) or float(record[metric]) < 0):return false
	var settings = candidate.settings
	if settings.has("difficulty") and (not _integer(settings.difficulty) or int(settings.difficulty) > 2):return false
	if settings.has("volume") and (not _finite_number(settings.volume) or float(settings.volume) < 0 or float(settings.volume) > 1):return false
	for key in ["auto_fire", "fullscreen"]:
		if settings.has(key) and not settings[key] is bool:return false
	if settings.has("input") and not settings.input is Dictionary:return false
	return true

func _canonical(value) -> String:
	if value is Dictionary:
		var keys = value.keys()
		keys.sort_custom(func(a, b):return str(a) < str(b))
		var pairs: PackedStringArray = []
		for key in keys:pairs.append(JSON.stringify(str(key)) + ":" + _canonical(value[key]))
		return "{" + ",".join(pairs) + "}"
	if value is Array:
		var items: PackedStringArray = []
		for item in value:items.append(_canonical(item))
		return "[" + ",".join(items) + "]"
	if _finite_number(value) and floor(float(value)) == float(value):return str(int(value))
	if value is StringName:return JSON.stringify(str(value))
	return JSON.stringify(value, "", true, true)

func _parse(path: String):
	var file = FileAccess.open(path, FileAccess.READ)
	if file == null:return null
	if file.get_length() > MAX_FILE_BYTES:
		file.close()
		return null
	var text = file.get_as_text()
	file.close()
	var parser = JSON.new()
	if parser.parse(text) != OK:return null
	return parser.data

func _read_generation(path: String) -> Dictionary:
	var envelope = _parse(path)
	if not envelope is Dictionary or not envelope.get("payload_sha256") is String:return {}
	var payload: Dictionary
	if envelope.get("format") == 2:
		# Hash the exact stored JSON bytes; parsing a float can change its decimal spelling.
		var serialized = envelope.get("payload_json")
		if not serialized is String or serialized.sha256_text() != envelope.payload_sha256:return {}
		var parser = JSON.new()
		if parser.parse(serialized) != OK or not parser.data is Dictionary:return {}
		payload = parser.data
	else:
		if not envelope.get("payload") is Dictionary:return {}
		payload = envelope.payload
		if not _tree_valid(payload) or _canonical(payload).sha256_text() != envelope.payload_sha256:return {}
	if not _tree_valid(payload):return {}
	if _integer(payload.get("schema_version")) and int(payload.schema_version) > SCHEMA_VERSION:
		return {"future":true}
	if not _validate(payload):return {}
	return payload

func _generation_files() -> Array:
	var result = []
	if not DirAccess.dir_exists_absolute(root_path):return result
	var dir = DirAccess.open(root_path)
	if dir == null:return result
	for name in dir.get_files():
		if name.begins_with("profile_g") and name.ends_with(".json"):
			var ordinal = name.trim_prefix("profile_g").trim_suffix(".json")
			if ordinal.is_valid_int() and ordinal.length() <= 16:result.append(name)
	result.sort_custom(func(a, b):return int(a.trim_prefix("profile_g").trim_suffix(".json")) > int(b.trim_prefix("profile_g").trim_suffix(".json")))
	return result.slice(0, 256)

func load_profile() -> bool:
	_loaded = true
	notice = ""
	read_only = false
	_load_failed = false
	_pending_generation = {}
	pending_transaction = {}
	var files = _generation_files()
	var chosen: Dictionary = {}
	var recovered = false
	for name in files:
		var loaded = _read_generation(root_path.path_join(name))
		if loaded.get("future", false):
			read_only = true
			_load_failed = true
			notice = "SAVE_SCHEMA_NEWER: 存档来自更新版本，已禁止写入。"
			return false
		if loaded.is_empty():
			recovered = true
			continue
		if chosen.is_empty():chosen = loaded
	if chosen.is_empty():
		if not files.is_empty() or FileAccess.file_exists(root_path.path_join("manifest.json")):
			_load_failed = true
			notice = "SAVE_RECOVERED: 没有可验证的完整存档，原文件已保留，请选择恢复或独立新档。"
			return false
		data = defaults()
		return true
	data = chosen
	var manifest = _parse(root_path.path_join("manifest.json"))
	if not manifest is Dictionary or manifest.get("generation") != data.generation or manifest.get("payload_sha256") != _canonical(data).sha256_text():recovered = true
	if recovered:notice = "SAVE_RECOVERED: 已恢复最近一份完整存档。"
	return true

func _path_allowed(path: String) -> bool:
	if path.length() > 256 or path.is_empty() or path.contains("..") or path.begins_with(".") or path.ends_with("."):return false
	if path == "ledger.repeat_counters" or path.begins_with("ledger.repeat_counters."):return true
	return path.get_slice(".", 0) in MUTABLE_ROOTS

func _apply_path(candidate: Dictionary, path: String, value, append_values: bool) -> bool:
	if not _path_allowed(path):return false
	var segments = path.split(".")
	var parent: Dictionary = candidate
	for index in range(segments.size() - 1):
		var key = segments[index]
		if not parent.has(key):parent[key] = {}
		if not parent[key] is Dictionary:return false
		parent = parent[key]
	var leaf = segments[-1]
	if append_values:
		if not value is Array:return false
		if not parent.has(leaf):parent[leaf] = []
		if not parent[leaf] is Array:return false
		for item in value:
			if not parent[leaf].has(item):parent[leaf].append(item.duplicate(true) if item is Array or item is Dictionary else item)
	else:
		parent[leaf] = value.duplicate(true) if value is Array or value is Dictionary else value
	return true

func commit(transaction: Dictionary) -> Dictionary:
	if not _loaded:
		if not load_profile():return _fail("SAVE_LOAD_REQUIRED")
	if read_only:return _fail("SAVE_SCHEMA_NEWER")
	if _load_failed:return _fail("SAVE_LOAD_REQUIRED")
	if _busy:return _fail("SAVE_BUSY")
	if not _tree_valid(transaction):return _fail("SAVE_INVALID_TRANSACTION: structure")
	var receipt = transaction.get("id", "")
	if not receipt is String or receipt.is_empty() or receipt.length() > 256:return _fail("SAVE_INVALID_TRANSACTION: receipt")
	if data.ledger.receipts.has(receipt):return _result(true, "", true)
	if not pending_transaction.is_empty() and _canonical(pending_transaction) != _canonical(transaction):return _fail("SAVE_PENDING_TRANSACTION")
	if not _pending_generation.is_empty():
		if pending_transaction.get("id") != receipt:return _fail("SAVE_PENDING_TRANSACTION")
		_busy = true
		var retry = _write_manifest(_pending_generation)
		_busy = false
		if not retry.ok:return retry
		data = _pending_generation
		_pending_generation = {}
		pending_transaction = {}
		notice = ""
		_retire_generations()
		return _result(true)
	var delta = transaction.get("parts_delta", 0)
	if not _integer(delta, -MAX_INTEGER):return _fail("SAVE_INVALID_TRANSACTION: currency")
	var next_parts = int(data.wallet.parts) + int(delta)
	if next_parts < 0 or next_parts > MAX_INTEGER:return _fail("SAVE_INVALID_BALANCE")
	var candidate = data.duplicate(true)
	candidate.wallet.parts = next_parts
	for kind in ["set", "append"]:
		var changes = transaction.get(kind, {})
		if not changes is Dictionary:return _fail("SAVE_INVALID_TRANSACTION")
		for path in changes:
			if not _apply_path(candidate, path, changes[path], kind == "append"):return _fail("SAVE_INVALID_PATH")
	candidate.ledger.receipts.append(receipt)
	candidate.generation = int(data.generation) + 1
	for name in _generation_files():
		candidate.generation = maxi(int(candidate.generation), int(name.trim_prefix("profile_g").trim_suffix(".json")) + 1)
	candidate.saved_at_utc = Time.get_datetime_string_from_system(true) + "Z"
	candidate.content_version = CONTENT_VERSION
	if not _validate(candidate):return _fail("SAVE_INVALID_PROFILE")
	pending_transaction = transaction.duplicate(true)
	_busy = true
	var result = _save_generation(candidate)
	_busy = false
	if not result.ok:return result
	data = result.payload
	_pending_generation = {}
	pending_transaction = {}
	notice = ""
	_retire_generations()
	return _result(true)

func _injected(point: String) -> bool:
	return failure_point == point

func _write_text(path: String, text: String) -> bool:
	var file = FileAccess.open(path, FileAccess.WRITE)
	if file == null:return false
	file.store_string(text)
	file.flush()
	var error = file.get_error()
	file.close()
	return error == OK

func _save_generation(candidate: Dictionary) -> Dictionary:
	if _injected("before_write"):return _fail("SAVE_WRITE_FAILED: before_write")
	if root_path.is_empty() or DirAccess.make_dir_recursive_absolute(root_path) != OK:return _fail("SAVE_WRITE_FAILED: directory")
	var target = root_path.path_join("profile_g%06d.json" % int(candidate.generation))
	var temporary = target + ".tmp"
	var serialized = JSON.stringify(candidate, "", true, true)
	var envelope = {"format":2, "payload_json":serialized, "payload_sha256":serialized.sha256_text()}
	var text = JSON.stringify(envelope, "\t", true, true)
	if text.to_utf8_buffer().size() > MAX_FILE_BYTES:return _fail("SAVE_WRITE_FAILED: size_limit")
	if not _write_text(temporary, text):return _fail("SAVE_WRITE_FAILED: write")
	if _injected("after_write"):return _fail("SAVE_WRITE_FAILED: after_write")
	var readback = _read_generation(temporary)
	if readback.is_empty():return _fail("SAVE_WRITE_FAILED: readback")
	if _injected("after_validate") or _injected("before_publish"):return _fail("SAVE_WRITE_FAILED: after_validate")
	# The final generation name is the publish marker. Temporary files are never recovered.
	if FileAccess.file_exists(target):return _fail("SAVE_WRITE_FAILED: generation_conflict")
	if DirAccess.rename_absolute(temporary, target) != OK:return _fail("SAVE_WRITE_FAILED: rename")
	_pending_generation = readback.duplicate(true)
	if _injected("after_generation"):return _fail("SAVE_WRITE_FAILED: after_generation")
	var result = _write_manifest(readback)
	if result.ok:result["payload"] = readback
	return result

func _write_manifest(candidate: Dictionary) -> Dictionary:
	if _injected("before_manifest"):return _fail("SAVE_WRITE_FAILED: before_manifest")
	var target = root_path.path_join("manifest.json")
	var temporary = target + ".tmp"
	var manifest = {"schema_version":2, "generation":candidate.generation, "file":"profile_g%06d.json" % int(candidate.generation), "payload_sha256":_canonical(candidate).sha256_text()}
	if not _write_text(temporary, JSON.stringify(manifest)):return _fail("SAVE_WRITE_FAILED: manifest_write")
	var readback = _parse(temporary)
	if not readback is Dictionary or readback.get("payload_sha256") != manifest.payload_sha256 or readback.get("generation") != manifest.generation:return _fail("SAVE_WRITE_FAILED: manifest_readback")
	if _injected("after_manifest_write"):return _fail("SAVE_WRITE_FAILED: after_manifest_write")
	if DirAccess.rename_absolute(temporary, target) != OK:return _fail("SAVE_WRITE_FAILED: manifest_rename")
	if _injected("after_manifest"):return _fail("SAVE_WRITE_FAILED: after_manifest")
	return _result(true)

func _retire_generations() -> void:
	var valid_count = 0
	for name in _generation_files():
		var path = root_path.path_join(name)
		var generation = _read_generation(path)
		if generation.is_empty():
			if DirAccess.rename_absolute(path, path + ".corrupt." + str(Time.get_ticks_usec())) != OK:notice = "SAVE_WRITE_FAILED: corrupt_generation_cleanup"
			continue
		if generation.has("future"):continue
		valid_count += 1
		if valid_count > 2:
			if DirAccess.remove_absolute(path) != OK:notice = "SAVE_WRITE_FAILED: old_generation_cleanup"

func _copy_migration_source(source: String, destination: String) -> bool:
	if not FileAccess.file_exists(source):return true
	var hash = FileAccess.get_sha256(source)
	if hash.is_empty():return false
	if not FileAccess.file_exists(destination) and DirAccess.copy_absolute(source, destination) != OK:return false
	return FileAccess.get_sha256(destination) == hash and FileAccess.get_sha256(source) == hash

func _legacy_candidate_valid(value) -> bool:
	return value is Dictionary and _tree_valid(value) and value.get("version", 1) == 1 and _integer(value.get("parts")) and value.get("unlocked", []) is Array

func migrate_v1(source_path: String) -> Dictionary:
	if not _loaded:
		if not load_profile():return _fail("MIGRATION_FAILED: profile_load")
	if read_only or _load_failed:return _fail("MIGRATION_FAILED: profile_read_only")
	var fingerprint_path = source_path if FileAccess.file_exists(source_path) else source_path + ".bak"
	if not FileAccess.file_exists(fingerprint_path):return _fail("MIGRATION_FAILED: source_missing")
	var source_hash = FileAccess.get_sha256(fingerprint_path)
	if source_hash.is_empty():return _fail("MIGRATION_FAILED: source_read")
	var receipt = "migration:v1:" + source_hash + ":1"
	if data.ledger.receipts.has(receipt):return _result(true, "", true)
	var gameplay_receipts: Array = data.ledger.receipts.filter(func(id): return id != "profile:init")
	if not data.legacy_v1.get("source_sha256", "").is_empty() or not gameplay_receipts.is_empty() or int(data.wallet.parts) != 0:return _fail("MIGRATION_FAILED: profile_not_empty")
	var private_dir = root_path.path_join("migration_backups").path_join("v1_" + source_hash)
	if DirAccess.make_dir_recursive_absolute(private_dir) != OK:return _fail("MIGRATION_FAILED: backup_directory")
	if not _copy_migration_source(source_path, private_dir.path_join("pilot.json")) or not _copy_migration_source(source_path + ".bak", private_dir.path_join("pilot.json.bak")):
		return _fail("MIGRATION_FAILED: backup_hash")
	# Parse the verified private copies, never the live V1 file.
	var legacy = _parse(private_dir.path_join("pilot.json"))
	if not _legacy_candidate_valid(legacy):
		var backup = _parse(private_dir.path_join("pilot.json.bak"))
		if _legacy_candidate_valid(backup):legacy = backup
	if not legacy is Dictionary or not _tree_valid(legacy):return _fail("MIGRATION_FAILED: invalid_source")
	if legacy.get("version", 1) != 1:return _fail("MIGRATION_FAILED: unsupported_version")
	if not _integer(legacy.get("parts")):return _fail("MIGRATION_FAILED: invalid_balance")
	var modules = ["pulse_base", "scan_base", "guard_base"]
	var mapping = {"pulse":"pulse_base", "charge":"burst_capacitor", "stable":"stock", "agile":"racing_drive", "shield":"guard_base", "cooler":"cooling_duct"}
	var unmapped = []
	var owned = legacy.get("unlocked", [])
	if not owned is Array:return _fail("MIGRATION_FAILED: invalid_unlocks")
	for item in owned:
		if item is String and mapping.has(item):
			if mapping[item] != "stock" and not modules.has(mapping[item]):modules.append(mapping[item])
		else:unmapped.append({"field":"unlocked", "value":item})
	var settings = defaults().settings
	var old_settings = legacy.get("settings", {})
	if old_settings is Dictionary:
		for key in ["difficulty", "camera"]:
			if _finite_number(old_settings.get(key)):settings[key] = clampi(int(old_settings[key]), 0, 2 if key == "difficulty" else 1)
		if _finite_number(old_settings.get("volume")):settings.volume = clampf(float(old_settings.volume), 0, 1)
		for key in ["auto_fire", "fullscreen"]:
			if old_settings.get(key) is bool:settings[key] = old_settings[key]
		if old_settings.get("input") is Dictionary:settings.input = _sanitize_legacy_input(old_settings.input)
	else:unmapped.append({"field":"settings", "value":old_settings})
	for key in legacy:
		if key not in ["version", "parts", "unlocked", "loadout", "completed", "claimed_runs", "records", "facility", "settings"]:unmapped.append({"field":key, "value":legacy[key]})
	var legacy_state = {"source_sha256":source_hash, "migration_version":1, "completed":legacy.get("completed", []), "records":legacy.get("records", {}), "facility":legacy.get("facility", []), "claimed_runs":legacy.get("claimed_runs", []), "unmapped":unmapped, "loadout_draft":legacy.get("loadout", {}), "original_settings":old_settings, "parts_before":int(legacy.parts), "parts_after":int(legacy.parts)}
	var result = commit({"id":receipt, "parts_delta":int(legacy.parts), "set":{"owned_modules":modules, "settings":settings, "legacy_v1":legacy_state}})
	if result.ok:notice = "V1 进度已保留并迁移；V2 从 M01 开始。旧配装保留为草稿，请确认连续高度操控。"
	return result

func _sanitize_legacy_input(raw: Dictionary) -> Dictionary:
	var clean = {}
	for axis in ["axis_x", "axis_y", "axis_height"]:
		if _finite_number(raw.get(axis)):clean[axis] = clampi(int(raw[axis]), -1, 7)
	for flag in ["invert_x", "invert_y"]:
		if raw.get(flag) is bool:clean[flag] = raw[flag]
	if _finite_number(raw.get("deadzone")):clean.deadzone = clampf(float(raw.deadzone), 0.02, 0.30)
	for key in ["center", "min", "max"]:
		clean[key] = {}
		var values = raw.get(key, {})
		if values is Dictionary:
			for axis in range(8):
				var name = str(axis)
				if _finite_number(values.get(name)):clean[key][name] = clampf(float(values[name]), -1.0, 1.0)
	clean.bindings = {}
	var bindings = raw.get("bindings", {})
	if bindings is Dictionary:
		for action in bindings:
			var binding = bindings[action]
			if binding is Dictionary and binding.get("type") in ["key", "joy"] and _integer(binding.get("code")):
				clean.bindings[action] = {"type":binding.type, "code":int(binding.code)}
	return clean
