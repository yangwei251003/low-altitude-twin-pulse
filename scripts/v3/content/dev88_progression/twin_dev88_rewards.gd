extends RefCounted
## Ownership is derived from actual discovery receipts, never a second currency.
const Secrets = preload("res://scripts/v3/content/dev88_progression/twin_dev88_secrets.gd")
const Routes = preload("res://scripts/v3/content/world_content_next/twin_world_content_catalog.gd")
const MODULES := {"I1":"precision_gimbal", "F1":"long_range_battery", "I2":"cooling_duct", "F2":"night_sensor", "I3":"reinforced_guard", "F3":"burst_capacitor", "I4":"racing_drive", "F4":"cargo_winch"}
static var _notes: Array = []

static func notes(region: String = "") -> Array:
	if _notes.is_empty():
		var base: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/v3/exploration_notes.json"))
		if base is Dictionary: _notes.append_array(base.get("notes", []))
		_notes.append_array(Routes.notes())
		_notes.append_array(Secrets.notes())
	var result: Array = []
	for row: Dictionary in _notes:
		if region.is_empty() or row.region == region: result.append(row.duplicate(true))
	return result

static func unlocks(discoveries: Array) -> Array:
	var result: Array = []
	for region: String in MODULES:
		var total := 0
		var found := 0
		for row: Dictionary in notes(region):
			total += 1
			if str(row.discovery_id) in discoveries: found += 1
		result.append({"region":region, "module_id":str(MODULES[region]), "owned":total > 0 and found == total,
			"found":found, "total":total, "discovery_id":"exploration_set:" + region,
			"condition":region + " 四处独立探索记录"})
	return result
