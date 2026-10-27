class_name TwinRegionCatalog
extends RefCounted
## Content availability is explicit. A catalog entry is not a finished region.
static var _entries: Array = []

static func entries() -> Array:
	if _entries.is_empty():
		var parsed = JSON.parse_string(FileAccess.get_file_as_string("res://data/v3/regions.json"))
		_entries = parsed.get("regions", []) if parsed is Dictionary else []
	return _entries.duplicate(true)

static func definition(id: String) -> Dictionary:
	for item in entries():
		if item.get("id") == id: return item
	return {}

static func playable(id: String) -> bool:
	return bool(definition(id).get("playable", false))

static func destination(id: String) -> String:
	for link in definition(id).get("links", []):
		if playable(str(link)): return str(link)
	return ""

static func destinations(id: String) -> Array:
	var result: Array = []
	for link in definition(id).get("links", []):
		if playable(str(link)): result.append(str(link))
	return result

static func can_travel(from: String, to: String) -> bool:
	return playable(to) and to in definition(from).get("links", [])

## The same saved chapter action opens the return route. Availability still
## comes from playable(), so metadata cannot make unfinished content playable.
static func required_action(from: String, to: String) -> String:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/v3/campaign/index.json"))
	if not parsed is Dictionary: return ""
	for gate: Dictionary in parsed.get("region_unlocks",[]):
		if gate.get("from") == from and gate.get("to") == to or gate.get("from") == to and gate.get("to") == from:
			return str(gate.get("requires_action",""))
	return ""

static func contains(id: String, point: Vector3) -> bool:
	var bounds: Array = definition(id).get("bounds", [])
	return point.is_finite() and bounds.size() == 6 and point.x >= bounds[0] and point.y >= bounds[1] and point.z >= bounds[2] and point.x <= bounds[3] and point.y <= bounds[4] and point.z <= bounds[5]

static func spawn(id: String) -> Vector3:
	var point: Array = definition(id).get("spawn", [-18, 2.5, 32])
	return Vector3(point[0], point[1], point[2])
