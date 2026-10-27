class_name TwinContentRegistry
extends RefCounted

const REGISTRY_PATH := "res://data/v3/content_registry.json"

func load_registry(path: String = REGISTRY_PATH) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {"ok": false, "code": "registry_missing"}
	var parser := JSON.new()
	if parser.parse(FileAccess.get_file_as_string(path)) != OK or not parser.data is Dictionary:
		return {"ok": false, "code": "invalid_json"}
	var checked := validate(parser.data)
	if not checked.ok:
		return checked
	return {"ok": true, "code": "loaded", "data": parser.data}

func validate(data: Dictionary) -> Dictionary:
	if int(data.get("schema_version", 0)) != 1:
		return {"ok": false, "code": "unsupported_schema"}
	var ids: Dictionary = {}
	for collection in ["regions", "abilities", "bosses", "objectives"]:
		if not data.get(collection) is Array:
			return {"ok": false, "code": "missing_collection", "collection": collection}
		ids[collection] = {}
		for item in data[collection]:
			if not item is Dictionary or str(item.get("id", "")).is_empty() or not data.get("status_legend", {}).has(item.get("status", "")):
				return {"ok": false, "code": "invalid_entry", "collection": collection}
			if ids[collection].has(item.id):
				return {"ok": false, "code": "duplicate_id", "id": item.id}
			ids[collection][item.id] = true
	for region in data.regions:
		if not str(region.get("world", "")) in ["industrial", "fantasy"] or not ids.bosses.has(region.get("boss_id", "")):
			return {"ok": false, "code": "invalid_region_reference", "id": region.id}
	for boss in data.bosses:
		if not ids.regions.has(boss.get("region_id", "")):
			return {"ok": false, "code": "invalid_boss_reference", "id": boss.id}
	for objective in data.objectives:
		if not ids.regions.has(objective.get("region_id", "")):
			return {"ok": false, "code": "invalid_objective_reference", "id": objective.id}
	return {"ok": true, "code": "valid"}
