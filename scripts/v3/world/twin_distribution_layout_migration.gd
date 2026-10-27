class_name TwinDistributionLayoutMigration
extends RefCounted
## Explicit host disk-restore operation. Never call from live packet handling.
## The caller retains the complete history envelope and commits before adoption.
## Missing-module initialization is separate: an empty mechanism is NOT a save.
const Cabinet = preload("res://scripts/v3/world/twin_distribution_cabinet.gd")
const Axis = preload("res://scripts/v3/environment/twin_guided_axis.gd")
const CURRENT_PATH := "res://data/v3/terrain/i2_distribution_layout.json"
const CANDIDATE_PATH := "res://data/v3/terrain/i2_distribution_trial_layout.json"
const LEGACY_PATH := "res://data/v3/terrain/i2_distribution_layout_dev18.json"
const LEGACY_FILE_SHA := "af104d7559ee24adbc29efb8492624d9585b53e55f1c92d6a01d93af920fd279"
const LEGACY_STATE_SHA := "88728b347cf99b21bbf3019dbaebf8614e3968aea99713c9f906cb154b449e38"
const TARGET_FILE_SHA := "61a1e932ad8a1a2a229abc961b342ef3b384b4fa2ff0b7011e027e14f7a3a3b3"
const TARGET_STATE_SHA := "50fbaab9e55ed5def10cf960893c2291ee422ad14f47d0c87a372537b22d19aa"
const FLOOR_PARTS := {
	"ServiceFloor":[[-2.2,1.0,-2.33],[2.2,1.2,3.0]],
	"ServiceFloorRearStrip":[[-2.2,1.0,-2.8],[2.2,1.2,-2.55]],
	"ServiceFloorLeftSocketRim":[[-2.2,1.0,-2.55],[-1.66,1.2,-2.33]],
	"ServiceFloorCentralWeb":[[-1.44,1.0,-2.55],[1.44,1.2,-2.33]],
	"ServiceFloorRightSocketRim":[[1.66,1.0,-2.55],[2.2,1.2,-2.33]],
}

static func prepare(mechanism: Variant, target_path: String = CURRENT_PATH) -> Dictionary:
	if not mechanism is Dictionary or mechanism.is_empty(): return _failure("migration_mechanism_required")
	# The optional path only chooses the reviewed candidate before deployment; it
	# cannot select arbitrary compatible-looking geometry or caller-made layouts.
	if target_path not in [CURRENT_PATH,CANDIDATE_PATH]: return _failure("migration_target_path")
	if FileAccess.get_sha256(target_path)!=TARGET_FILE_SHA: return _failure("migration_target_not_reviewed")
	if FileAccess.get_sha256(LEGACY_PATH)!=LEGACY_FILE_SHA: return _failure("migration_legacy_changed")
	var target: Variant = JSON.parse_string(FileAccess.get_file_as_string(target_path))
	var legacy: Variant = JSON.parse_string(FileAccess.get_file_as_string(LEGACY_PATH))
	if not target is Dictionary or not legacy is Dictionary: return _failure("migration_layout_json")
	if _hash(target)!=TARGET_STATE_SHA: return _failure("migration_target_digest")
	if _hash(legacy)!=LEGACY_STATE_SHA: return _failure("migration_legacy_digest")
	var contract: Dictionary = _validate_contract(legacy,target)
	if not contract.ok: return contract
	var source_digest: Variant = mechanism.get("layout_sha256")
	if not source_digest is String or source_digest not in [LEGACY_STATE_SHA,TARGET_STATE_SHA]:
		return _failure("migration_unknown_layout")
	var axis = Axis.new()
	var configured: Dictionary = axis.configure(Cabinet._axis_config(target))
	if not configured.ok: return _failure("migration_axis_configuration:"+str(configured.code))
	# Complete source validation precedes rewriting. In particular malformed
	# motion/rosters/serials/door latches are not repaired by a known digest.
	var valid: Dictionary = Cabinet._check_snapshot(mechanism,source_digest,axis)
	if not valid.ok: return _failure("migration_source:"+str(valid.code))
	var result: Dictionary = mechanism.duplicate(true)
	result.layout_sha256=TARGET_STATE_SHA
	valid=Cabinet._check_snapshot(result,TARGET_STATE_SHA,axis)
	if not valid.ok: return _failure("migration_result:"+str(valid.code))
	return {"ok":true,"code":"layout_migrated" if source_digest==LEGACY_STATE_SHA else "layout_current",
		"migrated":source_digest==LEGACY_STATE_SHA,"state":result}

static func _validate_contract(legacy: Dictionary, target: Dictionary) -> Dictionary:
	var checked: Dictionary = Cabinet._validate_layout(legacy)
	if not checked.ok: return _failure("migration_legacy_layout:"+str(checked.code))
	checked=Cabinet._validate_layout(target)
	if not checked.ok: return _failure("migration_target_layout:"+str(checked.code))
	var old_contract: Dictionary = legacy.duplicate(true)
	var new_contract: Dictionary = target.duplicate(true)
	old_contract.erase("fixed_solids")
	new_contract.erase("fixed_solids")
	# Unlike broader static upgrades, even stage and observation metadata remain
	# exact here. These five floor boxes are the whole authorization boundary.
	if _hash(old_contract)!=_hash(new_contract): return _failure("migration_nonfloor_contract")
	var old_parts: Dictionary = {}
	var new_parts: Dictionary = {}
	for part in legacy.fixed_solids: old_parts[part.id]=part
	for part in target.fixed_solids: new_parts[part.id]=part
	if not old_parts.has("ServiceFloor") or new_parts.size()!=old_parts.size()+4:
		return _failure("migration_floor_count")
	for id in old_parts:
		if id=="ServiceFloor": continue
		if id in FLOOR_PARTS or not new_parts.has(id) or _hash(old_parts[id])!=_hash(new_parts[id]):
			return _failure("migration_other_solid_changed")
	for id in FLOOR_PARTS:
		if not new_parts.has(id): return _failure("migration_floor_missing")
		var part: Dictionary = new_parts[id]
		if part.color!=old_parts.ServiceFloor.color: return _failure("migration_floor_color")
		for axis in range(3):
			if float(part.min[axis])!=float(FLOOR_PARTS[id][0][axis]) or float(part.max[axis])!=float(FLOOR_PARTS[id][1][axis]):
				return _failure("migration_floor_geometry")
	return {"ok":true,"code":"floor_contract_verified"}

static func _hash(value: Variant) -> String:
	return JSON.stringify(value,"",true,true).sha256_text()

static func _failure(code: String) -> Dictionary:
	return {"ok":false,"code":code,"migrated":false,"state":{}}
