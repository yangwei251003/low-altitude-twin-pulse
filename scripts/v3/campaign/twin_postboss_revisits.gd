extends RefCounted
## Display only, called after original G range/LOS/current-objective handling.
## No process, persistence, events, clocks, rewards or authority simulation.
const DATA_PATH := "res://data/v3/campaign/postboss_revisits.json"
static var _loaded := false
static var _data: Dictionary = {}

static func reply(committed: Dictionary, region_id: String, target_id: String) -> Dictionary:
	if committed.get("content_id", "") != "opening_v1": return {}
	if not committed.get("completed") is Array or not committed.get("flags") is Dictionary or not committed.get("choices") is Dictionary: return {}
	if not _loaded:
		_loaded = true
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(DATA_PATH))
		if parsed is Dictionary: _data = parsed
	for row: Dictionary in _data.get("reactions", []):
		if row.region_id != region_id or row.target_id != target_id or row.after not in committed.completed: continue
		var flags_match := true
		for key: String in row.required_flags:
			if not committed.flags.get(key) is bool or not committed.flags[key]: flags_match = false
		if not flags_match: return {}
		var choice: String = str(committed.choices.get(row.choice_objective_id, "")) if not str(row.choice_objective_id).is_empty() else ""
		for variant: Dictionary in row.variants:
			if variant.option == choice:
				return {"character_id":str(row.character_id), "lines":variant.lines.duplicate()}
		return {} # Unknown/missing saved choice retains original dialogue.
	return {}
