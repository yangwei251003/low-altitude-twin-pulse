class_name TwinActionDirector
extends RefCounted
## Pure action reducer. The host adapter verifies actors, range, line of sight and
## mechanism facts. Publish returned effects only after the store commit succeeds.

const DEFAULT_PATH := "res://data/v3/actions/opening_actions.json"
const SCHEMA_VERSION := 1
const EVENT_TYPES := ["talk", "inspect", "reach", "fact"]
const EFFECT_TYPES := ["flag", "discovery", "dialogue", "character_memory"]
var _definitions: Dictionary = {}

func load_definitions(path: String = DEFAULT_PATH, extensions: Array = []) -> Dictionary:
	if not FileAccess.file_exists(path): return _check_result(false, "definitions_missing")
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null: return _check_result(false, "definitions_unreadable")
	if file.get_length() > 1048576:
		file.close()
		return _check_result(false, "definitions_too_large")
	var parser := JSON.new()
	var parsed := parser.parse(file.get_as_text())
	file.close()
	if parsed != OK or not parser.data is Dictionary: return _check_result(false, "invalid_json")
	for extension_path in extensions:
		if not extension_path is String or not FileAccess.file_exists(extension_path): return _check_result(false, "extension_missing")
		var extension = JSON.parse_string(FileAccess.get_file_as_string(extension_path))
		if not extension is Dictionary or extension.get("extends_content_id", "") != parser.data.get("content_id", ""):
			return _check_result(false, "extension_content_mismatch")
		for key in ["characters", "markers", "actions"]:
			if not extension.get(key) is Array or not parser.data.get(key) is Array: return _check_result(false, "invalid_extension_arrays")
			parser.data[key].append_array(extension[key])
		for addition in extension.get("character_reply_extensions", []):
			if not addition is Dictionary or not addition.get("replies") is Array: return _check_result(false, "invalid_extension_replies")
			var found := false
			for character in parser.data.characters:
				if character.id == addition.get("character_id", ""):
					character.replies.append_array(addition.replies)
					found = true
			if not found: return _check_result(false, "unknown_extension_character")
	var result := validate(parser.data)
	if not result.ok: return result
	_definitions = parser.data.duplicate(true)
	return {"ok":true, "code":"loaded", "data":definitions()}

func definitions() -> Dictionary:
	return _definitions.duplicate(true)

func validate(data: Dictionary) -> Dictionary:
	if data.get("schema_version") != SCHEMA_VERSION: return _check_result(false, "unsupported_schema")
	if not _id(data.get("content_id")): return _check_result(false, "invalid_content_id")
	for key in ["characters", "markers", "actions"]:
		if not data.get(key) is Array: return _check_result(false, "missing_" + key)
	if data.actions.is_empty() or data.actions.size() > 128: return _check_result(false, "invalid_action_count")
	var characters: Dictionary = {}
	for character in data.characters:
		if not character is Dictionary or not _id(character.get("id")): return _check_result(false, "invalid_character")
		if characters.has(character.id): return _check_result(false, "duplicate_character")
		if not _text(character.get("name")) or not _lines(character.get("greeting_lines")): return _check_result(false, "invalid_character_text")
		if not character.get("replies") is Array: return _check_result(false, "invalid_character_replies")
		characters[character.id] = character
	var markers: Dictionary = {}
	for marker in data.markers:
		if not marker is Dictionary or not _id(marker.get("id")): return _check_result(false, "invalid_marker")
		if markers.has(marker.id): return _check_result(false, "duplicate_marker")
		if marker.get("region") not in ["I1", "I2", "I3", "I4", "F1", "F2", "F3", "F4"] or marker.get("kind") not in ["npc", "inspect", "reach"]: return _check_result(false, "invalid_marker_kind")
		if not _text(marker.get("label")) or not marker.get("position") is Array or marker.position.size() != 3: return _check_result(false, "invalid_marker_position")
		for coordinate in marker.position:
			if not _number(coordinate): return _check_result(false, "invalid_marker_position")
		if absf(marker.position[0]) > 50.0 or absf(marker.position[2]) > 50.0 or marker.position[1] < 0 or marker.position[1] > 27: return _check_result(false, "marker_outside_region")
		if not _number(marker.get("radius")) or marker.radius < 0.5 or marker.radius > 8: return _check_result(false, "invalid_marker_radius")
		if marker.kind == "npc" and not characters.has(marker.id): return _check_result(false, "unknown_marker_character")
		markers[marker.id] = marker
	var actions: Dictionary = {}
	var objectives: Dictionary = {}
	var event_owners: Dictionary = {}
	for action in data.actions:
		if not action is Dictionary or not _id(action.get("id")): return _check_result(false, "invalid_action")
		if actions.has(action.id): return _check_result(false, "duplicate_action")
		if action.get("region_id") not in ["I1", "I2", "I3", "I4", "F1", "F2", "F3", "F4"] or not _text(action.get("title")): return _check_result(false, "invalid_action_region")
		if not _dependencies(action.get("prerequisites"), actions): return _check_result(false, "invalid_action_dependencies")
		if not action.get("objectives") is Array or action.objectives.size() < 3 or action.objectives.size() > 5: return _check_result(false, "invalid_objective_count")
		var local_objectives: Dictionary = {}
		for objective in action.objectives:
			if not objective is Dictionary or not _id(objective.get("id")): return _check_result(false, "invalid_objective")
			if objectives.has(objective.id): return _check_result(false, "duplicate_objective")
			if not _text(objective.get("text")) or not _text(objective.get("hint")): return _check_result(false, "invalid_objective_text")
			if not _dependencies(objective.get("after"), local_objectives): return _check_result(false, "invalid_objective_dependencies")
			if not objective.get("events") is Array or objective.events.is_empty(): return _check_result(false, "missing_objective_events")
			for matcher in objective.events:
				if not matcher is Dictionary or matcher.get("type") not in EVENT_TYPES or not _id(matcher.get("target_id")): return _check_result(false, "invalid_event_matcher")
				if not matcher.get("options") is Array or matcher.options.is_empty(): return _check_result(false, "invalid_event_options")
				var options: Dictionary = {}
				for option in matcher.options:
					if not option is String or option.length() > 80 or options.has(option): return _check_result(false, "invalid_event_options")
					options[option] = true
					var fingerprint := _fingerprint({"type":matcher.type, "target_id":matcher.target_id, "option":option})
					if event_owners.has(fingerprint): return _check_result(false, "ambiguous_event_matcher")
					event_owners[fingerprint] = objective.id
				if matcher.type == "fact":
					if not matcher.target_id.begins_with(action.region_id + ":"): return _check_result(false, "invalid_fact_namespace")
				else:
					if not markers.has(matcher.target_id) or markers[matcher.target_id].region != action.region_id: return _check_result(false, "missing_target_marker")
					var expected_kind: String = "npc" if matcher.type == "talk" else matcher.type
					if markers[matcher.target_id].kind != expected_kind: return _check_result(false, "target_kind_mismatch")
			if not _effects_valid(objective.get("effects"), characters): return _check_result(false, "invalid_objective_effects")
			local_objectives[objective.id] = true
			objectives[objective.id] = true
		if action.has("completion_text") and not _text(action.completion_text): return _check_result(false, "invalid_completion_text")
		if not _effects_valid(action.get("effects"), characters): return _check_result(false, "invalid_action_effects")
		actions[action.id] = true
	for character in data.characters:
		for reply in character.replies:
			if not reply is Dictionary or not objectives.has(reply.get("after")) or not _lines(reply.get("lines")): return _check_result(false, "invalid_reply_reference")
	return _check_result(true, "valid")

func default_state() -> Dictionary:
	if _definitions.is_empty(): return {}
	var characters: Dictionary = {}
	for character in _definitions.characters:
		characters[character.id] = {"met":false, "memories":[]}
	return {"schema_version":SCHEMA_VERSION, "content_id":_definitions.content_id,
		"revision":0, "completed":[], "completed_actions":[], "choices":{},
		"flags":{}, "discoveries":[], "characters":characters, "receipts":{}}

func validate_state(state: Dictionary) -> Dictionary:
	if _definitions.is_empty(): return _check_result(false, "definitions_not_loaded")
	if state.get("schema_version") != SCHEMA_VERSION: return _check_result(false, "unsupported_state_schema")
	if state.get("content_id") != _definitions.content_id: return _check_result(false, "state_content_mismatch")
	for key in ["completed", "completed_actions", "discoveries"]:
		if not state.get(key) is Array: return _check_result(false, "invalid_state_" + key)
	for key in ["choices", "flags", "characters", "receipts"]:
		if not state.get(key) is Dictionary: return _check_result(false, "invalid_state_" + key)
	if state.completed.size() > _objective_count() or state.receipts.size() != state.completed.size(): return _check_result(false, "invalid_receipt_count")
	# Replay at most one compact receipt per goal. This checks prerequisite closure,
	# derived flags, memories and discoveries without trusting a saved reward list.
	var receipt_by_goal: Dictionary = {}
	for event_id in state.receipts:
		var receipt: Variant = state.receipts[event_id]
		if not _id(event_id) or not receipt is Dictionary or not _id(receipt.get("objective_id")): return _check_result(false, "invalid_receipt")
		if receipt_by_goal.has(receipt.objective_id): return _check_result(false, "duplicate_receipt_goal")
		var event := {"id":event_id, "type":receipt.get("type"), "target_id":receipt.get("target_id"), "option":receipt.get("option")}
		if not _event_valid(event) or receipt.get("fingerprint") != _fingerprint(event): return _check_result(false, "invalid_receipt_event")
		receipt_by_goal[receipt.objective_id] = event
	var replay := default_state()
	for objective_id in state.completed:
		if not _id(objective_id) or not receipt_by_goal.has(objective_id): return _check_result(false, "missing_receipt")
		var event: Dictionary = receipt_by_goal[objective_id]
		var match_result := _find_event(event)
		if match_result.is_empty() or match_result.objective.id != objective_id: return _check_result(false, "receipt_target_mismatch")
		if not _eligible(replay, match_result.action, match_result.objective): return _check_result(false, "invalid_saved_order")
		_advance(replay, event, match_result.action, match_result.objective)
	if not _same_json_value(replay, state): return _check_result(false, "state_integrity_mismatch")
	return _check_result(true, "valid")

func apply_event(state: Dictionary, event: Dictionary, context: Dictionary) -> Dictionary:
	if not context.get("is_authority") is bool or context.is_authority != true: return _event_result(false, "authority_required", state)
	if not context.get("validated") is bool or context.validated != true: return _event_result(false, "validation_required", state)
	var checked := validate_state(state)
	if not checked.ok: return _event_result(false, checked.code, state)
	if not _event_valid(event): return _event_result(false, "invalid_event", state)
	var match_result := _find_event(event)
	if match_result.is_empty(): return _event_result(false, "unsupported_event", state)
	if context.get("region_id") != match_result.action.region_id: return _event_result(false, "wrong_region", state)
	if state.receipts.has(event.id):
		if state.receipts[event.id].fingerprint != _fingerprint(event): return _event_result(false, "event_id_conflict", state)
		return _event_result(true, "duplicate", state)
	if event.id.length() > 160: return _event_result(false, "invalid_event", state)
	if match_result.objective.id in state.completed: return _event_result(true, "already_completed", state)
	if not _eligible(state, match_result.action, match_result.objective): return _event_result(false, "objective_locked", state)
	var candidate := state.duplicate(true)
	var effects := _advance(candidate, event, match_result.action, match_result.objective)
	return {"ok":true, "code":"advanced", "changed":true, "state":candidate, "effects":effects}

func hud(state: Dictionary, region_id: String = "") -> Dictionary:
	var result := {"action_id":"", "title":"", "objectives":[], "next_region":"",
		"completed_actions":0, "total_actions":_definitions.get("actions", []).size(), "complete":false}
	var checked := validate_state(state)
	if not checked.ok:
		result["error"] = checked.code
		return result
	result.completed_actions = state.completed_actions.size()
	for action in _definitions.actions:
		if action.id in state.completed_actions or not _all_completed(action.prerequisites, state.completed_actions): continue
		result.action_id = action.id
		result.title = action.title
		if not region_id.is_empty() and action.region_id != region_id: result.next_region = action.region_id
		for objective in action.objectives:
			if _eligible(state, action, objective):
				result.objectives.append({"id":objective.id, "text":objective.text,
					"hint":objective.hint, "targets":objective.events.duplicate(true)})
		return result
	result.complete = state.completed_actions.size() == _definitions.actions.size()
	result.title = "两界已建立第一条共同修复线索" if result.complete else "尚未解锁下一段行动"
	return result

func dialogue_lines(state: Dictionary, character_id: String) -> Array[String]:
	var lines: Array[String] = []
	if not validate_state(state).ok: return lines
	for character in _definitions.characters:
		if character.id != character_id: continue
		var selected: Array = character.greeting_lines
		for reply in character.replies:
			if reply.after in state.completed: selected = reply.lines
		for line in selected: lines.append(line)
		break
	return lines

func _advance(state: Dictionary, event: Dictionary, action: Dictionary, objective: Dictionary) -> Array:
	state.completed.append(objective.id)
	state.choices[objective.id] = event.get("option", "")
	state.receipts[event.id] = {"objective_id":objective.id, "type":event.type,
		"target_id":event.target_id, "option":event.get("option", ""), "fingerprint":_fingerprint(event)}
	state.revision = int(state.revision) + 1
	if event.type == "talk": state.characters[event.target_id].met = true
	var effects: Array = [{"id":"objective:" + objective.id, "type":"objective_completed", "objective_id":objective.id, "action_id":action.id}]
	_apply_effects(state, objective.effects, "objective:" + objective.id, effects)
	var complete := true
	for item in action.objectives:
		if not item.id in state.completed: complete = false
	if complete:
		state.completed_actions.append(action.id)
		effects.append({"id":"action:" + action.id, "type":"action_completed", "action_id":action.id})
		_apply_effects(state, action.effects, "action:" + action.id, effects)
	return effects

func _apply_effects(state: Dictionary, authored: Array, source: String, effects: Array) -> void:
	for index in authored.size():
		var effect: Dictionary = authored[index].duplicate(true)
		effect["id"] = source + ":" + str(index)
		match effect.type:
			"flag": state.flags[effect.key] = effect.value
			"discovery":
				if not effect.discovery_id in state.discoveries: state.discoveries.append(effect.discovery_id)
			"character_memory":
				var memories: Array = state.characters[effect.character_id].memories
				if not effect.memory in memories: memories.append(effect.memory)
		effects.append(effect)

func _find_event(event: Dictionary) -> Dictionary:
	for action in _definitions.get("actions", []):
		for objective in action.objectives:
			for matcher in objective.events:
				if event.type == matcher.type and event.target_id == matcher.target_id and event.get("option", "") in matcher.options:
					return {"action":action, "objective":objective}
	return {}

func _eligible(state: Dictionary, action: Dictionary, objective: Dictionary) -> bool:
	return not objective.id in state.completed and _all_completed(action.prerequisites, state.completed_actions) and _all_completed(objective.after, state.completed)

func _all_completed(required: Array, completed: Array) -> bool:
	for key in required:
		if not key in completed: return false
	return true

func _dependencies(value: Variant, known: Dictionary) -> bool:
	if not value is Array: return false
	var seen: Dictionary = {}
	for key in value:
		if not _id(key) or not known.has(key) or seen.has(key): return false
		seen[key] = true
	return true

func _effects_valid(value: Variant, characters: Dictionary) -> bool:
	if not value is Array or value.size() > 16: return false
	for effect in value:
		if not effect is Dictionary or effect.get("type") not in EFFECT_TYPES or effect.has("id"): return false
		match effect.type:
			"flag":
				if not _id(effect.get("key")) or not effect.get("value") is bool: return false
			"discovery":
				if not _id(effect.get("discovery_id")) or not _text(effect.get("title")): return false
			"dialogue":
				if not characters.has(effect.get("character_id")) or not _lines(effect.get("lines")): return false
			"character_memory":
				if not characters.has(effect.get("character_id")) or not _id(effect.get("memory")): return false
	return true

func _objective_count() -> int:
	var count := 0
	for action in _definitions.get("actions", []): count += action.objectives.size()
	return count

func _event_valid(event: Dictionary) -> bool:
	return _id(event.get("id")) and event.get("type") in EVENT_TYPES and _id(event.get("target_id")) and event.get("option", "") is String and event.get("option", "").length() <= 80

func _fingerprint(event: Dictionary) -> String:
	return JSON.stringify([event.get("type"), event.get("target_id"), event.get("option", "")]).sha256_text()

func _id(value: Variant) -> bool:
	return value is String and not value.is_empty() and value.length() <= 160 and value == value.strip_edges() and not value.contains("\n") and not value.contains("\r")

func _text(value: Variant) -> bool:
	return value is String and not value.strip_edges().is_empty() and value.length() <= 1200

func _lines(value: Variant) -> bool:
	if not value is Array or value.is_empty() or value.size() > 12: return false
	for line in value:
		if not _text(line): return false
	return true

func _number(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value))

func _same_json_value(left: Variant, right: Variant, depth: int = 0) -> bool:
	# Godot JSON decodes integral numbers as float; Dictionary equality does not
	# normalize nested numeric types. Preserve exact value without accepting bools.
	if depth > 24: return false
	if _number(left) and _number(right): return float(left) == float(right)
	if typeof(left) != typeof(right): return false
	if left is Dictionary:
		if left.size() != right.size(): return false
		for key in left:
			if not right.has(key) or not _same_json_value(left[key], right[key], depth + 1): return false
		return true
	if left is Array:
		if left.size() != right.size(): return false
		for index in left.size():
			if not _same_json_value(left[index], right[index], depth + 1): return false
		return true
	return left == right

func _check_result(ok: bool, code: String) -> Dictionary:
	return {"ok":ok, "code":code}

func _event_result(ok: bool, code: String, state: Dictionary) -> Dictionary:
	return {"ok":ok, "code":code, "changed":false, "state":state.duplicate(true), "effects":[]}
