extends RefCounted
## Exact final-caption routing into the original bounded UI audio pool.
const PATH := "res://data/v3/content/final_flow/voice_routes.json"
static var _book: Dictionary = {}

static func event_definitions() -> Dictionary:
	return _data().get("events", {}).duplicate(true)

static func cue_for_line(character: String, text: String) -> String:
	var key := character + "\n" + text.strip_edges()
	return str(_data().get("by_character", {}).get(key, _data().get("by_text", {}).get(text.strip_edges(), "")))

static func owns(cue: String) -> bool:
	return _data().get("events", {}).has(cue)

static func _data() -> Dictionary:
	if _book.is_empty():
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(PATH))
		if parsed is Dictionary: _book = parsed
	return _book
