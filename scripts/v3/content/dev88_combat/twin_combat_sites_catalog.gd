extends RefCounted
## Ten optional native combat encounters. No campaign target or Boss replacement.
const PATH := "res://data/v3/content/dev88_combat/sites.json"
static var _sites: Array = []

static func sites(region: String = "") -> Array:
	if _sites.is_empty():
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(PATH))
		if parsed is Dictionary: _sites = parsed.get("sites", [])
	var result: Array = []
	for row: Dictionary in _sites:
		if region.is_empty() or str(row.region) == region: result.append(row.duplicate(true))
	return result

static func definition(id: String) -> Dictionary:
	for row: Dictionary in sites():
		if str(row.id) == id: return row
	return {}

static func markers() -> Array:
	var result: Array = []
	for row: Dictionary in sites():
		result.append({"id":str(row.id), "region":str(row.region), "kind":"npc", "optional":false,
			"combat_site":true, "position":row.terminal.duplicate(), "radius":3.8,
			"label":str(row.name) + " · G 询问 / 启动 / 交接"})
	return result

static func reward_ids() -> Array:
	var result: Array = []
	for row: Dictionary in sites(): result.append(str(row.reward_id))
	return result

static func point(value: Array) -> Vector3:
	return Vector3(float(value[0]), float(value[1]), float(value[2]))

static func bounds(row: Dictionary) -> AABB:
	var values: Array = row.bounds
	return AABB(Vector3(float(values[0]), float(values[1]), float(values[2])),
		Vector3(float(values[3])-float(values[0]), float(values[4])-float(values[1]), float(values[5])-float(values[2])))
