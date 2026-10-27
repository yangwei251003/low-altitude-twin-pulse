class_name TwinWorldStore
extends RefCounted
## One host writer. A validated generation rename is the only commit point.
## The previous complete generations are the backup; temporary files never recover.

const SCHEMA_VERSION = 3
const MAX_FILE_BYTES = 16 * 1024 * 1024
const MAX_INTEGER = 9007199254740991
const KEEP_GENERATIONS = 3
const RETIRE_CERT_LIMIT = 4
const RETIRE_CERT_MAX_CHARS = 1024 * 1024

var root_path: String
var read_only = false
var notice = ""
## QA fault injection: before_write / after_write / before_publish.
var failure_point = ""
var _data: Dictionary
var _loaded = false
var _load_failed = false
var _busy = false
# Only complete, previously validated text; never payload Dictionary references.
var _retire_certificates: Array[Dictionary] = []
## Existing --cpu diagnostic only. Scalar timing is never persisted or networked.
var qa_phase_enabled := false
var qa_last_phases: Dictionary = {}
var _qa_cost_active := false
var _qa_phase := ""
var _qa_phase_started := 0
var _qa_read_group := ""
var _qa_read_stage := ""
var _qa_read_started := 0
var data: Dictionary:
	get: return snapshot()

func _qa_phase_mark(next: String) -> void:
	if not _qa_cost_active: return
	var now := Time.get_ticks_usec()
	if not _qa_phase.is_empty():
		qa_last_phases.phase_usec[_qa_phase] += now-_qa_phase_started
		qa_last_phases.phase_count[_qa_phase] += 1
	_qa_phase = next
	_qa_phase_started = now

func _qa_read_mark(next: String) -> void:
	if not _qa_cost_active or _qa_read_group.is_empty(): return
	var now := Time.get_ticks_usec()
	if not _qa_read_stage.is_empty():
		var stats: Dictionary = qa_last_phases.read_groups[_qa_read_group]
		stats[_qa_read_stage+"_usec"] += now-_qa_read_started
		stats[_qa_read_stage+"_count"] += 1
	_qa_read_stage = next
	_qa_read_started = now

func _qa_begin_phases() -> void:
	var now := Time.get_ticks_usec()
	_qa_cost_active = true
	_qa_phase = ""; _qa_read_group = ""; _qa_read_stage = ""
	qa_last_phases = {"schema":1,"complete":false,"start_usec":now,"total_usec":0,
		"phase_usec":{},"phase_count":{},"read_groups":{}}
	for phase: String in ["ready","transaction_candidate","candidate_validate","prepare_generation","encode_hash_size","write_flush","tmp_readback","rename","retire"]:
		qa_last_phases.phase_usec[phase] = 0
		qa_last_phases.phase_count[phase] = 0
	for group: String in ["ready","tmp","retire"]:
		qa_last_phases.read_groups[group] = {"calls":0,"read_usec":0,"read_count":0,
			"json_sha_usec":0,"json_sha_count":0,"validate_usec":0,"validate_count":0}
	_qa_phase_mark("ready")

func _init(path: String = "user://profiles_v3/default") -> void:
	root_path = path.trim_suffix("/")
	_data = _defaults()

func _defaults() -> Dictionary:
	var world = {"region_id":"I1", "branch_id":"main", "flags":{}, "choices":{}, "entities":{}, "completed_objectives":[]}
	return {"schema_version":SCHEMA_VERSION, "generation":0, "profile_id":_uuid(), "lineage_id":_uuid(),
		"world_revision":0, "saved_at_utc":"", "world":world,
		"personal":{"builds":[], "collections":[], "discoveries":[]}, "encounter":{},
		"branches":{"main":{"label":"Main", "parent_id":"", "world":world.duplicate(true)}},
		"ledger":{"commits":{}, "guest_received":{}, "guest_outbox":{}}}

func snapshot() -> Dictionary:
	return _data.duplicate(true)

func _uuid() -> String:
	return Crypto.new().generate_random_bytes(16).hex_encode()

func _result(ok: bool, error: String = "", duplicate: bool = false) -> Dictionary:
	return {"ok":ok, "error":error, "duplicate":duplicate, "read_only":read_only, "recovered":false, "generation":int(_data.generation), "world_revision":int(_data.world_revision)}

func _fail(error: String) -> Dictionary:
	notice = error
	return _result(false, error)

func _safe_root() -> bool:
	if root_path.contains("..") or root_path.contains("\\"): return false
	return root_path.begins_with("user://profiles_v3/") or root_path.begins_with("user://qa_v3/") or root_path.begins_with("user://qa_v3_")

func _integer(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and float(value) >= 0 and float(value) <= MAX_INTEGER and floor(float(value)) == float(value)

func _tree_valid(value: Variant, depth: int = 0) -> bool:
	if depth > 28: return false
	if value == null or value is bool: return true
	if value is String: return value.length() <= 8192
	if value is int or value is float: return is_finite(float(value)) and absf(float(value)) <= MAX_INTEGER
	if value is Array:
		if value.size() > 40000: return false
		# A child at depth 29 always fails, even when it is a scalar.
		if depth == 28: return value.is_empty()
		for item in value:
			if item == null or item is bool: continue
			if item is String:
				if item.length() > 8192: return false
			elif item is int or item is float:
				if not (is_finite(float(item)) and absf(float(item)) <= MAX_INTEGER): return false
			elif item is Array or item is Dictionary:
				if not _tree_valid(item, depth + 1): return false
			else: return false
		return true
	if value is Dictionary:
		if value.size() > 40000: return false
		if depth == 28: return value.is_empty()
		for key in value:
			if not key is String or key.is_empty() or key.length() > 256: return false
			var item: Variant = value[key]
			if item == null or item is bool: continue
			if item is String:
				if item.length() > 8192: return false
			elif item is int or item is float:
				if not (is_finite(float(item)) and absf(float(item)) <= MAX_INTEGER): return false
			elif item is Array or item is Dictionary:
				if not _tree_valid(item, depth + 1): return false
			else: return false
		return true
	return false

func _id_valid(value: Variant) -> bool:
	return value is String and not value.is_empty() and value.length() <= 200

func _world_valid(world: Variant, branch_id: String) -> bool:
	if not world is Dictionary or world.get("branch_id") != branch_id or not _id_valid(world.get("region_id")): return false
	for key in ["flags", "choices", "entities"]:
		if not world.get(key) is Dictionary: return false
	return world.get("completed_objectives") is Array

func _validate(value: Dictionary) -> bool:
	if not _tree_valid(value) or value.get("schema_version") != SCHEMA_VERSION: return false
	for key in ["generation", "world_revision"]:
		if not _integer(value.get(key)): return false
	for key in ["profile_id", "lineage_id"]:
		if not _id_valid(value.get(key)): return false
	if not value.get("saved_at_utc") is String: return false
	for key in ["world", "personal", "encounter", "branches", "ledger"]:
		if not value.get(key) is Dictionary: return false
	var active: String = str(value.world.get("branch_id", ""))
	if not _world_valid(value.world, active) or not value.branches.has(active): return false
	for id in value.branches:
		var branch: Variant = value.branches[id]
		if not _id_valid(id) or not branch is Dictionary or not _world_valid(branch.get("world"), id): return false
		if not branch.get("label") is String or not branch.get("parent_id") is String: return false
	if value.branches[active].world != value.world: return false
	for key in ["builds", "collections", "discoveries"]:
		if not value.personal.get(key) is Array: return false
	for key in ["commits", "guest_received", "guest_outbox"]:
		if not value.ledger.get(key) is Dictionary: return false
	for ledger_key in ["commits", "guest_received"]:
		for id in value.ledger[ledger_key]:
			if not _id_valid(id) or not value.ledger[ledger_key][id] is String: return false
	for id in value.ledger.guest_outbox:
		var item: Variant = value.ledger.guest_outbox[id]
		if not item is Dictionary or not item.get("acknowledged") is bool or not _receipt_valid(item.get("receipt")): return false
		if item.receipt.receipt_id != id or item.receipt.lineage_id != value.lineage_id: return false
	return true

func matches_persisted_value(live: Variant, saved: Variant) -> bool:
	# Compare the value one real Store write would publish with its existing
	# readback. Godot JSON normalizes integers AND can round a fractional double.
	# Only encode/decode live once: saved has already crossed this boundary.
	# Exact equality still retains bool/string types, keys, array order and every
	# fractional difference representable by this same persistence format.
	return JSON.parse_string(JSON.stringify(live, "", true, true)) == saved

func _canonical(value: Variant) -> String:
	if value is Dictionary:
		var keys: Array = value.keys()
		keys.sort()
		var pairs = PackedStringArray()
		for key in keys: pairs.append(JSON.stringify(key) + ":" + _canonical(value[key]))
		return "{" + ",".join(pairs) + "}"
	if value is Array:
		var items = PackedStringArray()
		for item in value: items.append(_canonical(item))
		return "[" + ",".join(items) + "]"
	if (value is int or value is float) and is_finite(float(value)) and floor(float(value)) == float(value): return str(int(value))
	return JSON.stringify(value, "", true, true)

func _generation_files() -> Array[String]:
	var files: Array[String] = []
	var directory = DirAccess.open(root_path)
	if directory == null: return files
	for name in directory.get_files():
		if name.begins_with("profile_g") and name.ends_with(".json"):
			var ordinal = name.trim_prefix("profile_g").trim_suffix(".json")
			if ordinal.is_valid_int() and ordinal.length() <= 15 and int(ordinal) > 0: files.append(name)
	files.sort_custom(func(a: String, b: String) -> bool: return _file_generation(a) > _file_generation(b))
	return files

func _file_generation(name: String) -> int:
	return int(name.trim_prefix("profile_g").trim_suffix(".json"))

func _read_generation(path: String) -> Dictionary:
	if not _qa_cost_active: return _read_generation_body(path)
	var group: String = str({"ready":"ready","tmp_readback":"tmp","retire":"retire"}.get(_qa_phase,""))
	if group.is_empty(): return _read_generation_body(path)
	_qa_read_group = group
	_qa_read_stage = ""
	qa_last_phases.read_groups[_qa_read_group].calls += 1
	_qa_read_mark("read")
	var result: Dictionary = _read_generation_body(path)
	_qa_read_mark("")
	_qa_read_group = ""
	return result

func _read_generation_body(path: String) -> Dictionary:
	var file = FileAccess.open(path, FileAccess.READ)
	if file == null: return {}
	if file.get_length() > MAX_FILE_BYTES:
		file.close()
		return {}
	var text = file.get_as_text()
	file.close()
	var payload := _decode_generation_text(text)
	if not payload.is_empty() and not payload.get("future", false):
		if _qa_cost_active and not _qa_read_group.is_empty(): _qa_read_mark("")
		_remember_retire_certificate(path, text)
	return payload

func _decode_generation_text(text: String) -> Dictionary:
	if _qa_cost_active and not _qa_read_group.is_empty(): _qa_read_mark("json_sha")
	var parser = JSON.new()
	if parser.parse(text) != OK or not parser.data is Dictionary: return {}
	var envelope: Dictionary = parser.data
	if _integer(envelope.get("schema_version")) and int(envelope.schema_version) > SCHEMA_VERSION: return {"future":true}
	if envelope.get("format") != 1 or not envelope.get("payload_json") is String or not envelope.get("payload_sha256") is String: return {}
	var serialized: String = envelope.payload_json
	if serialized.sha256_text() != envelope.payload_sha256: return {}
	if parser.parse(serialized) != OK or not parser.data is Dictionary: return {}
	var payload: Dictionary = parser.data
	if _integer(payload.get("schema_version")) and int(payload.schema_version) > SCHEMA_VERSION: return {"future":true}
	if _qa_cost_active and not _qa_read_group.is_empty(): _qa_read_mark("validate")
	if not _validate(payload): return {}
	return payload


func _retire_certificates_allowed() -> bool:
	# Exclude subclasses/overrides, even those that retain this resource path.
	# The exact core Script is already loaded; runtime hot edits are unsupported.
	return get_script() == load("res://scripts/v3/core/twin_world_store.gd")

func _remember_retire_certificate(path: String, text: String) -> void:
	if not _retire_certificates_allowed() or text.length() > RETIRE_CERT_MAX_CHARS: return
	for index in range(_retire_certificates.size()-1, -1, -1):
		var certificate: Dictionary = _retire_certificates[index]
		if certificate.path == path or certificate.text == text: _retire_certificates.remove_at(index)
	# Evict before inserting: at most four retained texts, each <=1 Mi characters.
	while _retire_certificates.size() >= RETIRE_CERT_LIMIT: _retire_certificates.pop_front()
	_retire_certificates.append({"path":path, "text":text})

func _forget_retire_certificate(path: String) -> void:
	for index in range(_retire_certificates.size()-1, -1, -1):
		if _retire_certificates[index].path == path: _retire_certificates.remove_at(index)

func _retirement_generation_valid(path: String) -> bool:
	# Normal load/ready/tmp always use the full reader and its original payload.
	if not _retire_certificates_allowed():
		var payload := _read_generation(path)
		return not payload.is_empty() and not payload.get("future", false)
	var measured := _qa_cost_active and _qa_phase == "retire"
	if measured:
		_qa_read_group = "retire"; _qa_read_stage = ""
		qa_last_phases.read_groups.retire.calls += 1
		_qa_read_mark("read")
	var valid := _retirement_generation_valid_body(path)
	if measured:
		_qa_read_mark(""); _qa_read_group = ""
	return valid

func _retirement_generation_valid_body(path: String) -> bool:
	var file = FileAccess.open(path, FileAccess.READ)
	if file == null: return false
	if file.get_length() > MAX_FILE_BYTES:
		file.close()
		return false
	var text = file.get_as_text()
	file.close()
	# Fresh whole-file I/O ends here. String equality is parent retire work,
	# not read, JSON/SHA or validation time. No path/mtime/generation shortcut.
	if _qa_cost_active and not _qa_read_group.is_empty(): _qa_read_mark("")
	if text.length() <= RETIRE_CERT_MAX_CHARS:
		for certificate: Dictionary in _retire_certificates:
			if text == certificate.text:
				# Keep the already validated String, remapping tmp -> published path.
				_remember_retire_certificate(path, certificate.text)
				return true
	var payload := _decode_generation_text(text)
	if _qa_cost_active and not _qa_read_group.is_empty(): _qa_read_mark("")
	if payload.is_empty() or payload.get("future", false): return false
	_remember_retire_certificate(path, text)
	return true

func load_profile() -> Dictionary:
	if _busy: return _fail("SAVE_BUSY")
	if not _safe_root(): return _fail("SAVE_PATH_OUTSIDE_V3")
	var chosen: Dictionary = {}
	var recovered = false
	var files = _generation_files()
	for name in files:
		var candidate = _read_generation(root_path.path_join(name))
		if candidate.get("future", false):
			read_only = true
			_load_failed = true
			return _fail("SAVE_SCHEMA_NEWER")
		if candidate.is_empty() or int(candidate.generation) != _file_generation(name):
			if chosen.is_empty(): recovered = true
			continue
		if chosen.is_empty(): chosen = candidate
	if chosen.is_empty() and not files.is_empty():
		_load_failed = true
		return _fail("SAVE_NO_VALID_BACKUP")
	if not chosen.is_empty(): _data = chosen
	_loaded = true
	_load_failed = false
	read_only = false
	notice = "SAVE_RECOVERED_BACKUP" if recovered else ""
	var result = _result(true)
	result["recovered"] = recovered
	result["read_only"] = false
	return result

func _ready_to_write() -> Dictionary:
	if not _safe_root(): return _fail("SAVE_PATH_OUTSIDE_V3")
	if read_only: return _fail("SAVE_SCHEMA_NEWER")
	if _busy: return _fail("SAVE_BUSY")
	if not _loaded:
		var loaded = load_profile()
		if not loaded.ok: return loaded
	if _load_failed: return _fail("SAVE_LOAD_REQUIRED")
	# Detect a second writer or newer version before any write, even after loading.
	for name in _generation_files():
		var disk = _read_generation(root_path.path_join(name))
		if disk.get("future", false):
			read_only = true
			return _fail("SAVE_SCHEMA_NEWER")
		if not disk.is_empty():
			if int(disk.generation) != int(_data.generation): return _fail("SAVE_CONCURRENT_WRITE")
			break
	return _result(true)

func _path_allowed(path: String) -> bool:
	if path.is_empty() or path.length() > 256 or path.contains("..") or path.begins_with(".") or path.ends_with("."): return false
	if path.get_slice(".", 0) not in ["world", "personal", "encounter"]: return false
	return path != "world" and path != "world.branch_id" and not path.begins_with("world.branch_id.")

func _apply_path(candidate: Dictionary, path: String, value: Variant, append_values: bool) -> bool:
	if not _path_allowed(path): return false
	var segments = path.split(".")
	var parent: Dictionary = candidate
	for index in range(segments.size() - 1):
		var key = segments[index]
		if not parent.has(key): parent[key] = {}
		if not parent[key] is Dictionary: return false
		parent = parent[key]
	var leaf = segments[-1]
	if append_values:
		if not value is Array: return false
		if not parent.has(leaf): parent[leaf] = []
		if not parent[leaf] is Array: return false
		for item in value:
			if not parent[leaf].has(item): parent[leaf].append(_copy(item))
	else: parent[leaf] = _copy(value)
	return true

func _copy(value: Variant) -> Variant:
	return value.duplicate(true) if value is Dictionary or value is Array else value

func commit(transaction: Dictionary) -> Dictionary:
	if not qa_phase_enabled: return _commit_body(transaction)
	_qa_begin_phases()
	var result: Dictionary = _commit_body(transaction)
	_qa_phase_mark("") # Also closes the current phase on every ordinary rejection.
	qa_last_phases.total_usec = Time.get_ticks_usec()-int(qa_last_phases.start_usec)
	qa_last_phases.complete = true
	_qa_cost_active = false
	_qa_read_group = ""; _qa_read_stage = ""
	return result

func _commit_body(transaction: Dictionary) -> Dictionary:
	var ready = _ready_to_write()
	if not ready.ok: return ready
	if _qa_cost_active: _qa_phase_mark("transaction_candidate")
	if not _tree_valid(transaction) or not _id_valid(transaction.get("id")): return _fail("SAVE_INVALID_TRANSACTION")
	for key in transaction:
		if key not in ["id", "set", "append", "guest_rewards"]: return _fail("SAVE_INVALID_TRANSACTION")
	var id: String = transaction.id
	var fingerprint = _canonical(transaction).sha256_text()
	if _data.ledger.commits.has(id):
		return _result(true, "", true) if _data.ledger.commits[id] == fingerprint else _fail("SAVE_RECEIPT_CONFLICT")
	var candidate = snapshot()
	for kind in ["set", "append"]:
		var changes: Variant = transaction.get(kind, {})
		if not changes is Dictionary: return _fail("SAVE_INVALID_TRANSACTION")
		for path in changes:
			if not _apply_path(candidate, path, changes[path], kind == "append"): return _fail("SAVE_INVALID_PATH")
	var guest_rewards: Variant = transaction.get("guest_rewards", [])
	if not guest_rewards is Array: return _fail("GUEST_INVALID_RECEIPT")
	for reward in guest_rewards:
		if not reward is Dictionary or not _id_valid(reward.get("guest_id")) or not _id_valid(reward.get("reward_id")) or not _reward_payload_valid(reward.get("payload")): return _fail("GUEST_INVALID_RECEIPT")
		var queued = _queue_candidate(candidate, reward.guest_id, reward.reward_id, reward.payload)
		if not queued.ok: return queued
	if candidate.world != _data.world: candidate.world_revision = int(_data.world_revision) + 1
	candidate.branches[candidate.world.branch_id].world = candidate.world.duplicate(true)
	candidate.ledger.commits[id] = fingerprint
	return _persist(candidate)

func fork_branch(branch_id: String, label: String = "", switch_to_new: bool = false) -> Dictionary:
	var ready = _ready_to_write()
	if not ready.ok: return ready
	if not _id_valid(branch_id) or label.length() > 256: return _fail("BRANCH_INVALID_ID")
	if _data.branches.has(branch_id): return _fail("BRANCH_EXISTS")
	var candidate = snapshot()
	var world: Dictionary = candidate.world.duplicate(true)
	world.branch_id = branch_id
	candidate.branches[branch_id] = {"label":label if not label.is_empty() else branch_id, "parent_id":str(candidate.world.branch_id), "world":world}
	if switch_to_new:
		candidate.world = world.duplicate(true)
		candidate.encounter = {}
	# All proposals made before a branch operation become stale.
	candidate.world_revision = int(_data.world_revision) + 1
	return _persist(candidate)

func list_branches() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for id in _data.branches:
		var branch: Dictionary = _data.branches[id]
		result.append({"branch_id":id, "label":branch.label, "parent_id":branch.parent_id, "region_id":branch.world.region_id, "active":id == _data.world.branch_id})
	return result

func branch_world_hash(branch_id: String) -> String:
	if not _data.branches.has(branch_id): return ""
	return _canonical(_data.branches[branch_id].world).sha256_text()

func switch_branch(branch_id: String, world_changes: Dictionary = {}, expected_world_hash: String = "") -> Dictionary:
	var ready = _ready_to_write()
	if not ready.ok: return ready
	if not _data.branches.has(branch_id): return _fail("BRANCH_NOT_FOUND")
	# Prepared content upgrades and the branch switch share one publish point.
	# A target fingerprint prevents applying a prepared world to a stale branch.
	if not world_changes.is_empty():
		if not _tree_valid(world_changes) or expected_world_hash.is_empty() or branch_world_hash(branch_id) != expected_world_hash:
			return _fail("BRANCH_PREPARED_WORLD_STALE")
		for path in world_changes:
			if not path.begins_with("world.") or not _path_allowed(path): return _fail("BRANCH_INVALID_WORLD_PATH")
	if branch_id == _data.world.branch_id:
		return _result(true, "", true) if world_changes.is_empty() else _fail("BRANCH_ALREADY_ACTIVE_WITH_PATCH")
	var candidate = snapshot()
	candidate.world = candidate.branches[branch_id].world.duplicate(true)
	for path in world_changes:
		if not _apply_path(candidate, path, world_changes[path], false): return _fail("BRANCH_INVALID_WORLD_PATH")
	candidate.branches[branch_id].world = candidate.world.duplicate(true)
	candidate.encounter = {}
	candidate.world_revision = int(_data.world_revision) + 1
	return _persist(candidate)

func _receipt_id(lineage_id: String, guest_id: String, reward_id: String) -> String:
	return _canonical([lineage_id, guest_id, reward_id]).sha256_text()

func _reward_payload_valid(payload: Variant) -> bool:
	if not payload is Dictionary or payload.is_empty() or not _tree_valid(payload): return false
	for key in payload:
		if key not in ["discoveries", "collections", "builds"] or not payload[key] is Array: return false
		for item in payload[key]:
			if key == "builds":
				if not item is Dictionary or not _id_valid(item.get("build_id")): return false
			elif not _id_valid(item): return false
	return true

func _receipt_valid(receipt: Variant) -> bool:
	if not receipt is Dictionary or not _tree_valid(receipt): return false
	for key in ["receipt_id", "lineage_id", "guest_id", "reward_id"]:
		if not _id_valid(receipt.get(key)): return false
	return _reward_payload_valid(receipt.get("payload")) and receipt.receipt_id == _receipt_id(receipt.lineage_id, receipt.guest_id, receipt.reward_id)

func _queue_candidate(candidate: Dictionary, guest_id: String, reward_id: String, payload: Dictionary) -> Dictionary:
	var id = _receipt_id(candidate.lineage_id, guest_id, reward_id)
	var receipt = {"receipt_id":id, "lineage_id":str(candidate.lineage_id), "guest_id":guest_id, "reward_id":reward_id, "payload":payload.duplicate(true)}
	if candidate.ledger.guest_outbox.has(id):
		if candidate.ledger.guest_outbox[id].receipt != receipt: return _fail("GUEST_RECEIPT_CONFLICT")
		return {"ok":true, "duplicate":true, "receipt":receipt}
	candidate.ledger.guest_outbox[id] = {"receipt":receipt, "acknowledged":false}
	return {"ok":true, "duplicate":false, "receipt":receipt}

func queue_guest_receipt(guest_id: String, reward_id: String, payload: Dictionary) -> Dictionary:
	var ready = _ready_to_write()
	if not ready.ok: return ready
	if not _id_valid(guest_id) or not _id_valid(reward_id) or not _reward_payload_valid(payload): return _fail("GUEST_INVALID_RECEIPT")
	var candidate = snapshot()
	var queued = _queue_candidate(candidate, guest_id, reward_id, payload)
	if not queued.ok: return queued
	if queued.duplicate:
		var duplicate = _result(true, "", true)
		duplicate["receipt"] = queued.receipt
		return duplicate
	var result = _persist(candidate)
	if result.ok: result["receipt"] = queued.receipt.duplicate(true)
	return result

func pending_guest_receipts(guest_id: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for item in _data.ledger.guest_outbox.values():
		if item.receipt.guest_id == guest_id and not item.acknowledged: result.append(item.receipt.duplicate(true))
	return result

func apply_guest_receipt(receipt: Dictionary) -> Dictionary:
	var ready = _ready_to_write()
	if not ready.ok: return ready
	if not _receipt_valid(receipt): return _fail("GUEST_INVALID_RECEIPT")
	if receipt.guest_id != _data.profile_id: return _fail("GUEST_WRONG_RECIPIENT")
	var id: String = receipt.receipt_id
	var fingerprint = _canonical(receipt).sha256_text()
	if _data.ledger.guest_received.has(id):
		return _result(true, "", true) if _data.ledger.guest_received[id] == fingerprint else _fail("GUEST_RECEIPT_CONFLICT")
	var candidate = snapshot()
	for key in receipt.payload:
		if key == "builds":
			for gift in receipt.payload[key]:
				for existing in candidate.personal.builds:
					if existing is Dictionary and existing.get("build_id") == gift.build_id and existing != gift: return _fail("GUEST_BUILD_CONFLICT")
		if not _apply_path(candidate, "personal." + key, receipt.payload[key], true): return _fail("GUEST_INVALID_RECEIPT")
	candidate.ledger.guest_received[id] = fingerprint
	return _persist(candidate)

func ack_guest_receipt(guest_id: String, receipt_id: String) -> Dictionary:
	var ready = _ready_to_write()
	if not ready.ok: return ready
	if not _data.ledger.guest_outbox.has(receipt_id): return _fail("GUEST_RECEIPT_NOT_FOUND")
	var item: Dictionary = _data.ledger.guest_outbox[receipt_id]
	if item.receipt.guest_id != guest_id: return _fail("GUEST_WRONG_RECIPIENT")
	if item.acknowledged: return _result(true, "", true)
	var candidate = snapshot()
	candidate.ledger.guest_outbox[receipt_id].acknowledged = true
	return _persist(candidate)

func _write_text(path: String, text: String) -> bool:
	var file = FileAccess.open(path, FileAccess.WRITE)
	if file == null: return false
	file.store_string(text)
	file.flush()
	var status = file.get_error()
	file.close()
	return status == OK

func _persist(candidate: Dictionary) -> Dictionary:
	if _qa_cost_active: _qa_phase_mark("candidate_validate")
	if not _validate(candidate): return _fail("SAVE_INVALID_STATE")
	if failure_point == "before_write": return _fail("SAVE_WRITE_FAILED")
	if _qa_cost_active: _qa_phase_mark("prepare_generation")
	if DirAccess.make_dir_recursive_absolute(root_path) != OK: return _fail("SAVE_DIRECTORY_FAILED")
	var next_generation = int(_data.generation) + 1
	for name in _generation_files(): next_generation = maxi(next_generation, _file_generation(name) + 1)
	candidate.generation = next_generation
	candidate.saved_at_utc = Time.get_datetime_string_from_system(true) + "Z"
	if _qa_cost_active: _qa_phase_mark("encode_hash_size")
	var serialized = JSON.stringify(candidate, "", true, true)
	var text = JSON.stringify({"format":1, "schema_version":SCHEMA_VERSION, "payload_json":serialized, "payload_sha256":serialized.sha256_text()}, "", true, true)
	if text.to_utf8_buffer().size() > MAX_FILE_BYTES: return _fail("SAVE_SIZE_LIMIT")
	if _qa_cost_active: _qa_phase_mark("write_flush")
	var target = root_path.path_join("profile_g%012d.json" % next_generation)
	var temporary = target + ".tmp"
	_busy = true
	var error = ""
	if not _write_text(temporary, text): error = "SAVE_WRITE_FAILED"
	elif failure_point == "after_write": error = "SAVE_WRITE_FAILED"
	else:
		if _qa_cost_active: _qa_phase_mark("tmp_readback")
		var readback = _read_generation(temporary)
		if _qa_cost_active: _qa_phase_mark("rename")
		if readback.is_empty() or readback.get("future", false): error = "SAVE_READBACK_FAILED"
		elif failure_point == "before_publish": error = "SAVE_PUBLISH_FAILED"
		elif FileAccess.file_exists(target): error = "SAVE_GENERATION_CONFLICT"
		elif DirAccess.rename_absolute(temporary, target) != OK: error = "SAVE_PUBLISH_FAILED"
		else: _data = readback
	_busy = false
	if not error.is_empty(): return _fail(error)
	# Once the rename succeeds the transaction succeeded. Cleanup cannot reverse it.
	notice = ""
	if _qa_cost_active: _qa_phase_mark("retire")
	_retire_generations()
	return _result(true)

func _retire_generations() -> void:
	var count = 0
	for name in _generation_files():
		var path := root_path.path_join(name)
		if not _retirement_generation_valid(path): continue
		count += 1
		if count > KEEP_GENERATIONS:
			if DirAccess.remove_absolute(path) != OK: notice = "SAVE_BACKUP_CLEANUP_DEFERRED"
			else: _forget_retire_certificate(path)
