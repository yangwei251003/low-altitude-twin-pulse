extends RefCounted
## Exact, single-caption voice routing into the original TwinAudioV3 interface.
## No players, buses, simulation, save writes or network transport are created.
const SOURCE := "res://data/v3/content/dev88_presentation/voice_lines.json"
const EVENTS := "res://data/v3/content/dev88_presentation/audio_events.json"
static var _book: Dictionary = {}
static var _events: Dictionary = {}
static var _key_pattern: RegEx
static var _spaces: RegEx

static func cue_for_line(character_id: String, text: String, speaker_name: String = "") -> String:
	var data: Dictionary = _data()
	var line := text.strip_edges()
	var by_character: Dictionary = data.get("by_character", {}).get(character_id, {})
	if by_character.has(line): return str(by_character[line])
	var by_speaker: Dictionary = data.get("by_speaker", {}).get(speaker_name, {})
	if by_speaker.has(line): return str(by_speaker[line])
	var any_voice: Dictionary = data.get("by_text", {})
	if any_voice.has(line): return str(any_voice[line])
	# Runtime input relabeling can change a key hint. Only unambiguous authored
	# fallback keys are included; conflicting source lines return no voice.
	var normalized := _normalize(line)
	var normalized_character: Dictionary = data.get("normalized_by_character", {}).get(character_id, {})
	if normalized_character.has(normalized): return str(normalized_character[normalized])
	var normalized_speaker: Dictionary = data.get("normalized_by_speaker", {}).get(speaker_name, {})
	if normalized_speaker.has(normalized): return str(normalized_speaker[normalized])
	return str(data.get("normalized_by_text", {}).get(normalized, ""))

static func cue_for_dialogue(character_id: String, lines: Array, speaker_name: String = "") -> String:
	return cue_for_line(character_id, str(lines[0]), speaker_name) if lines.size() == 1 else ""

static func cue_for(route: String, line_index: int = 0) -> String:
	var data: Dictionary = _data()
	var routes: Dictionary = data.get("routes", {})
	if routes.has(route):
		var ids: Array = routes[route]
		return str(ids[line_index]) if line_index >= 0 and line_index < ids.size() else ""
	if data.get("cue_index", {}).has(route): return route
	return ""

static func subtitle(cue_id: String) -> Dictionary:
	var row: Dictionary = _data().get("cue_index", {}).get(cue_id, {})
	return row.duplicate(true)

static func event_definitions() -> Dictionary:
	if _events.is_empty():
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(EVENTS))
		if parsed is Dictionary: _events = parsed.get("events", {})
	return _events.duplicate(true)

static func voice_ids() -> Array:
	return _data().get("cue_index", {}).keys()

static func _normalize(text: String) -> String:
	if _key_pattern == null:
		_key_pattern = RegEx.new()
		_key_pattern.compile(str(_data().get("normalization_pattern", "")))
		_spaces = RegEx.new()
		_spaces.compile("\\s+")
	return _spaces.sub(_key_pattern.sub(text, "", true), "", true)

static func _data() -> Dictionary:
	if _book.is_empty():
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(SOURCE))
		if parsed is Dictionary: _book = parsed
	return _book
