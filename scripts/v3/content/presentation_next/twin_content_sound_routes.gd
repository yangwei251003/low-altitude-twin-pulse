extends RefCounted
## Pure metadata adapter for the existing TwinAudioV3 event interface.
## Does not create any audio players, buses, gameplay state or network messages.
const CATALOG_PATH := "res://data/v3/content/presentation_next/presentation_catalog.json"
const AUDIO_EVENTS_PATH := "res://data/v3/content/presentation_next/audio_events.json"
static var _catalog: Dictionary = {}

static func catalog() -> Dictionary:
	if _catalog.is_empty():
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(CATALOG_PATH))
		if parsed is Dictionary: _catalog = parsed
	return _catalog.duplicate(true)

static func cue_for(content_event: String, region: String = "") -> String:
	var data: Dictionary = catalog()
	if content_event == "chapter_entry":
		var profiles: Dictionary = data.get("region_sets", {})
		var profile: Dictionary = profiles.get(region, {})
		return str(profile.get("entry_cue", ""))
	var routes: Dictionary = data.get("sound_routes", {})
	return str(routes.get(content_event, ""))

static func region_profile(region: String) -> Dictionary:
	var profiles: Dictionary = catalog().get("region_sets", {})
	var profile: Dictionary = profiles.get(region, {})
	return profile.duplicate(true)

static func event_definitions() -> Dictionary:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(AUDIO_EVENTS_PATH))
	if not parsed is Dictionary: return {}
	var definitions: Dictionary = parsed.get("events", {})
	return definitions.duplicate(true)
