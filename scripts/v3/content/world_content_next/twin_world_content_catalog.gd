extends RefCounted
## Authored content, developed without a playtest in this batch. The catalog
## supplies data; only the original Host ability rules and Store award facts.
const PATH := "res://data/v3/content/world_content_next/regions_next.json"
static var _document: Dictionary = {}

static func definitions() -> Array:
	return _read().get("regions", []).duplicate(true)

static func regions() -> Array:
	return definitions()

static func definition(region_id: String) -> Dictionary:
	for row: Dictionary in definitions():
		if str(row.get("id", "")) == region_id: return row
	return {}

static func notes(region_id: String = "") -> Array:
	var result: Array = []
	for row: Dictionary in definitions():
		if not region_id.is_empty() and str(row.id) != region_id: continue
		result.append_array(row.get("notes", []))
	return result

static func practice_entities(region_id: String) -> Array:
	return definition(region_id).get("entities", []).duplicate(true)

static func route_rows(region_id: String) -> Array:
	return definition(region_id).get("routes", []).duplicate(true)

static func encounters(region_id: String) -> Array:
	return definition(region_id).get("encounters", []).duplicate(true)

static func vector(point: Array) -> Vector3:
	return Vector3(float(point[0]), float(point[1]), float(point[2]))

static func _read() -> Dictionary:
	if _document.is_empty():
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(PATH))
		if parsed is Dictionary: _document = parsed
	return _document
