class_name TwinClinicLayoutMigration
extends RefCounted
## Host disk-restore only. Live network snapshots must never use this adapter.
## This whitelist changes static structure, never water, axis, history or rewards.
const CURRENT_PATH := "res://data/v3/terrain/i2_clinic_layout.json"
const LEGACY_PATH := "res://data/v3/terrain/i2_clinic_layout_dev16.json"
const LEGACY_FILE_SHA := "4369c0a9c07a0517cb220c713ae0f5f31a3cbdecf063b15e49bb646c313ef6cd"
const LEGACY_STATE_SHA := "6ffe938bf721f5f9b146bde159b41226c368bfc7544b3a4f591a655255598d4c"
const CURRENT_FILE_SHA := "c239fc9b45a00ee9166bad429b3923ac95340b883cb757099b76f40db0e8ed55"

static func prepare(saved: Dictionary) -> Dictionary:
	if saved.is_empty(): return {"ok":true, "migrated":false, "state":{}}
	if FileAccess.get_sha256(CURRENT_PATH) != CURRENT_FILE_SHA:
		return {"ok":false, "code":"migration_target_not_reviewed"}
	var current: Variant = JSON.parse_string(FileAccess.get_file_as_string(CURRENT_PATH))
	if not current is Dictionary: return {"ok":false, "code":"migration_target_json"}
	var digest := JSON.stringify(current, "", true, true).sha256_text()
	if saved.get("layout_sha256") == digest:
		return {"ok":true, "migrated":false, "state":saved.duplicate(true)}
	if saved.get("layout_sha256") != LEGACY_STATE_SHA:
		return {"ok":false, "code":"migration_unknown_layout"}
	if FileAccess.get_sha256(LEGACY_PATH) != LEGACY_FILE_SHA:
		return {"ok":false, "code":"migration_legacy_changed"}
	var legacy: Variant = JSON.parse_string(FileAccess.get_file_as_string(LEGACY_PATH))
	if not legacy is Dictionary or JSON.stringify(legacy, "", true, true).sha256_text() != LEGACY_STATE_SHA:
		return {"ok":false, "code":"migration_legacy_digest"}
	var current_contract: Dictionary = current.duplicate(true)
	var legacy_contract: Dictionary = legacy.duplicate(true)
	for key in ["fixed_solids", "stage"]:
		current_contract.erase(key)
		legacy_contract.erase(key)
	if JSON.stringify(current_contract, "", true, true) != JSON.stringify(legacy_contract, "", true, true):
		return {"ok":false, "code":"migration_mechanism_changed"}
	var result: Dictionary = saved.duplicate(true)
	result.layout_sha256 = digest
	# The caller must still run Works.load_layout's complete snapshot validator.
	return {"ok":true, "migrated":true, "state":result}
