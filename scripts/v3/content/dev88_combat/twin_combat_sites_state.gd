extends RefCounted
## Only committed complete encounters survive a visit. In-flight HP, projectiles,
## retry attempts and waves are transient, and never write an incomplete save.
const Catalog = preload("res://scripts/v3/content/dev88_combat/twin_combat_sites_catalog.gd")
const RECORD_KEYS := ["serial", "mode", "waves", "destroyed", "neutralized", "payload_health_milli", "reward_id"]

static func empty() -> Dictionary:
	return {"version":1, "serial":0, "completed":{}}

static func valid(value: Variant) -> bool:
	if not value is Dictionary or value.size() != 3 or not _integer(value.get("version"), 1, 1): return false
	if not _integer(value.get("serial"), 0, 10) or not value.get("completed") is Dictionary or value.completed.size() != int(value.serial): return false
	var serials: Dictionary = {}
	for id: Variant in value.completed:
		if not id is String: return false
		var spec: Dictionary = Catalog.definition(id)
		var row: Variant = value.completed[id]
		if spec.is_empty() or not row is Dictionary or row.size() != RECORD_KEYS.size(): return false
		for key: String in RECORD_KEYS:
			if not row.has(key): return false
		if not _integer(row.serial, 1, int(value.serial)) or serials.has(int(row.serial)): return false
		serials[int(row.serial)] = true
		if row.mode != spec.mode or row.reward_id != spec.reward_id or row.waves != spec.waves.size(): return false
		if not _integer(row.destroyed, 0, 12) or not _integer(row.neutralized, 0, 12) or int(row.destroyed) + int(row.neutralized) != _unit_count(spec): return false
		if not _integer(row.payload_health_milli, 0, 64000): return false
		if spec.mode in ["escort", "defend"] and int(row.payload_health_milli) <= 0: return false
		if spec.mode == "intercept" and int(row.payload_health_milli) != 0: return false
	return true

static func prepare(current: Dictionary, spec: Dictionary, destroyed: int, neutralized: int, payload_health_milli: int) -> Dictionary:
	if not valid(current) or spec.is_empty(): return {"ok":false, "code":"combat_sites_saved_state_invalid"}
	if current.completed.has(str(spec.id)): return {"ok":false, "code":"combat_site_already_completed"}
	var next: Dictionary = current.duplicate(true)
	next.serial = int(next.serial) + 1
	next.completed[str(spec.id)] = {"serial":int(next.serial), "mode":str(spec.mode), "waves":spec.waves.size(),
		"destroyed":destroyed, "neutralized":neutralized, "payload_health_milli":payload_health_milli, "reward_id":str(spec.reward_id)}
	return {"ok":valid(next), "code":"combat_site_complete_candidate", "state":next}

static func _unit_count(spec: Dictionary) -> int:
	var total := 0
	for wave: Dictionary in spec.get("waves", []): total += wave.get("units", []).size()
	return total

static func _integer(value: Variant, minimum: int, maximum: int) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and floorf(float(value)) == float(value) and float(value) >= float(minimum) and float(value) <= float(maximum)
