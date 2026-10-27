extends SceneTree
## Pure content/reducer regression. No scene, combat, physics, store or LAN evidence.
## Host facts below are fixtures; this suite does not prove their physical validity.

const Director = preload("res://scripts/v3/gameplay/actions/twin_action_director.gd")
const EXTENSION_PATH := "res://data/v3/actions/whale_action.json"
const RECORD_DISCOVERY := "opening:whale_raw_command_record"
const EXPECTED_ACTIONS := ["I1:rescue", "I1:evidence", "F1:needs", "F1:repair", "I1:whale"]
# Fixed public event contracts, not generated from whichever matchers happen to load.
# Each row is objective ID, event type, target ID, option, region ID.
const BASE_EVENTS := [
	["I1:rescue:brief", "talk", "npc:linlan", "rescue_brief", "I1"],
	["I1:rescue:channel", "fact", "I1:rescue_channel", "charge", "I1"],
	["I1:rescue:contact", "reach", "I1:rescue_pocket", "", "I1"],
	["I1:rescue:evacuate", "reach", "I1:rescue_exit", "", "I1"],
	["I1:evidence:trace", "inspect", "I1:burn_trace", "", "I1"],
	["I1:evidence:engineer", "talk", "npc:ruanheng", "reverse_flow", "I1"],
	["I1:evidence:ledger", "inspect", "I1:energy_ledger", "", "I1"],
	["I1:evidence:echo", "inspect", "I1:beacon_echo", "", "I1"],
	["F1:needs:listen", "talk", "npc:atai", "needs", "F1"],
	["F1:needs:nursery", "inspect", "F1:dry_nursery", "", "F1"],
	["F1:needs:route", "reach", "F1:nursery_landing", "flight", "F1"],
	["F1:repair:plan", "talk", "npc:atai", "repair_plan", "F1"],
	["F1:repair:light", "fact", "F1:light_receiver", "aligned", "F1"],
	["F1:repair:grow", "fact", "F1:growth_bridge", "grown", "F1"],
	["F1:repair:confirm", "inspect", "F1:shared_junction", "", "F1"],
]
const WHALE_EVENTS := [
	["I1:whale:brief", "inspect", "I1:whale_briefing", "confirm_plan", "I1"],
	["I1:whale:engage", "fact", "I1:whale_engaged", "started", "I1"],
	["I1:whale:disable", "fact", "I1:whale_defeated", "committed", "I1"],
	["I1:whale:record", "fact", "I1:whale_raw_record", "retrieved", "I1"],
]

var checks := 0
var failures: Array[String] = []
var director = Director.new()
var base_director = Director.new()
var legacy_complete: Dictionary = {}
var final_state: Dictionary = {}

func _initialize() -> void:
	var base_loaded: Dictionary = base_director.load_definitions(Director.DEFAULT_PATH)
	var merged_loaded: Dictionary = director.load_definitions(Director.DEFAULT_PATH, [EXTENSION_PATH])
	_check(base_loaded.get("ok", false), "base definitions load: " + str(base_loaded.get("code")))
	_check(merged_loaded.get("ok", false), "extension loads through production merge API: " + str(merged_loaded.get("code")))
	if base_loaded.get("ok", false) and merged_loaded.get("ok", false):
		_test_merged_schema()
		_test_legacy_progress_and_prerequisite()
		if not legacy_complete.is_empty():
			_test_whale_progression()
		if not final_state.is_empty():
			_test_record_idempotency()
			_test_receipt_replay_and_replies()
	print("V3_WHALE_ACTION_DATA_TESTS " + JSON.stringify({
		"checks": checks, "failures": failures, "expected_actions": 5, "expected_objectives": 19,
		"scope": "pure schema, reducer and in-memory JSON receipt replay only; no battle, physical interaction, actual save IO, LAN, graphics, performance or human timing evidence"
	}))
	quit(0 if failures.is_empty() else 1)

func _check(condition: bool, label: String) -> void:
	checks += 1
	if not condition: failures.append(label)

func _event(row: Array, suffix: String = "") -> Dictionary:
	return {"id": "qa_whale:" + str(row[0]) + suffix, "type": row[1], "target_id": row[2], "option": row[3]}

func _context(region: String = "I1") -> Dictionary:
	return {"is_authority": true, "validated": true, "region_id": region}

func _same_json(left: Variant, right: Variant) -> bool:
	return JSON.parse_string(JSON.stringify(left)) == JSON.parse_string(JSON.stringify(right))

func _objective_count(data: Dictionary) -> int:
	var result := 0
	for action in data.get("actions", []): result += action.objectives.size()
	return result

func _test_merged_schema() -> void:
	var base: Dictionary = base_director.definitions()
	var merged: Dictionary = director.definitions()
	_check(base.actions.size() == 4 and _objective_count(base) == 15, "unextended content remains four actions and fifteen objectives")
	_check(merged.actions.size() == 5 and _objective_count(merged) == 19, "extended content has exactly five actions and nineteen objectives")
	_check(merged.content_id == "opening_v1", "merge preserves legacy save content identity")
	_check(director.validate(merged).get("ok", false), "merged content independently satisfies schema")
	var actual_ids: Array = []
	for action in merged.actions: actual_ids.append(action.id)
	_check(actual_ids == EXPECTED_ACTIONS, "original four actions precede the whale action")
	if merged.actions.size() != 5 or base.actions.size() != 4: return
	for index in range(4):
		_check(_same_json(merged.actions[index], base.actions[index]), "legacy action definition unchanged: " + str(base.actions[index].id))
	var whale: Dictionary = merged.actions[4]
	_check(whale.prerequisites == ["F1:repair"], "whale requires completed repair action, not merely a flag")
	var expected_after: Array = []
	for index in WHALE_EVENTS.size():
		if index >= whale.objectives.size():
			_check(false, "missing whale objective at index " + str(index))
			continue
		var objective: Dictionary = whale.objectives[index]
		_check(objective.id == WHALE_EVENTS[index][0] and objective.after == expected_after, "stable sequential whale objective contract: " + str(WHALE_EVENTS[index][0]))
		expected_after = [WHALE_EVENTS[index][0]]
	var record_markers := 0
	for marker in merged.markers:
		if marker.id == "I1:whale_raw_record": record_markers += 1
	_check(record_markers == 0, "dynamic record does not acquire a fabricated static marker")
	var bad: Dictionary = merged.duplicate(true)
	bad.actions[4].prerequisites = ["F1:missing"]
	_check(director.validate(bad).get("code") == "invalid_action_dependencies", "unknown extension prerequisite rejected")
	bad = merged.duplicate(true)
	bad.actions[4].objectives[3].events[0].target_id = "F1:whale_raw_record"
	_check(director.validate(bad).get("code") == "invalid_fact_namespace", "whale record fact cannot cross region namespace")
	bad = merged.duplicate(true)
	bad.actions[4].objectives[3].events[0].type = "inspect"
	_check(director.validate(bad).get("code") == "missing_target_marker", "dynamic record cannot silently become unsupported static inspect")
	var duplicate_load: Dictionary = director.load_definitions(Director.DEFAULT_PATH, [EXTENSION_PATH, EXTENSION_PATH])
	_check(not duplicate_load.get("ok", false), "loading the same extension twice is rejected")
	_check(_same_json(director.definitions(), merged), "failed duplicate merge preserves last valid definitions")

func _test_legacy_progress_and_prerequisite() -> void:
	var early: Dictionary = director.apply_event(director.default_state(), _event(WHALE_EVENTS[0]), _context())
	_check(early.get("code") == "objective_locked" and not early.get("changed", false), "fresh profile cannot accept whale briefing")
	var state: Dictionary = base_director.default_state()
	for index in BASE_EVENTS.size():
		if index == BASE_EVENTS.size() - 1:
			_check(director.validate_state(state).get("ok", false), "fourteen-goal legacy state validates with extension")
			var before: Dictionary = state.duplicate(true)
			var denied: Dictionary = director.apply_event(state, _event(WHALE_EVENTS[0]), _context())
			_check(denied.get("code") == "objective_locked" and not denied.get("changed", false), "repair light and growth alone do not unlock whale briefing")
			_check(_same_json(denied.get("state", {}), before) and denied.get("effects", []).is_empty(), "locked briefing preserves prior progress and emits no effects")
		var row: Array = BASE_EVENTS[index]
		var result: Dictionary = base_director.apply_event(state, _event(row), _context(str(row[4])))
		_check(result.get("code") == "advanced" and result.get("changed", false), "legacy event advances through unextended director: " + str(row[0]))
		if not result.get("ok", false) or not result.get("changed", false): return
		state = result.state
	_check(state.completed.size() == 15 and state.completed_actions.size() == 4 and state.receipts.size() == 15, "legacy completion comes from fifteen actual reducer events")
	_check(base_director.hud(state).get("complete", false), "original director regards legacy state as complete")
	var restored: Variant = JSON.parse_string(JSON.stringify(state))
	_check(restored is Dictionary, "legacy state survives in-memory JSON serialization")
	if not restored is Dictionary: return
	_check(director.validate_state(restored).get("ok", false), "expanded director replays unchanged legacy receipts without migration or reset")
	var hud: Dictionary = director.hud(restored, "F1")
	_check(hud.get("action_id") == "I1:whale" and hud.get("next_region") == "I1" and not hud.get("complete", true), "completed old content now points back to I1 whale action")
	for character_id in ["npc:linlan", "npc:ruanheng", "npc:atai"]:
		_check(director.dialogue_lines(restored, character_id) == base_director.dialogue_lines(state, character_id), "future whale replies do not leak into legacy completion: " + character_id)
	legacy_complete = restored

func _test_whale_progression() -> void:
	var state: Dictionary = legacy_complete.duplicate(true)
	for index in WHALE_EVENTS.size():
		if index + 1 < WHALE_EVENTS.size():
			var skipped: Dictionary = director.apply_event(state, _event(WHALE_EVENTS[index + 1], ":early"), _context())
			_check(skipped.get("code") == "objective_locked" and not skipped.get("changed", false), "future whale objective cannot skip its predecessor: " + str(WHALE_EVENTS[index + 1][0]))
		var row: Array = WHALE_EVENTS[index]
		var before: Dictionary = state.duplicate(true)
		var result: Dictionary = director.apply_event(state, _event(row), _context())
		_check(result.get("code") == "advanced" and result.get("changed", false), "fixed whale event advances: " + str(row[0]))
		_check(_same_json(state, before), "reducer leaves input state untouched: " + str(row[0]))
		if not result.get("ok", false) or not result.get("changed", false): return
		state = result.state
		_check(state.completed.size() == 16 + index and state.receipts.size() == 16 + index, "exactly one goal and receipt added: " + str(row[0]))
		_check(director.validate_state(state).get("ok", false), "each whale prefix can replay its saved receipts: " + str(row[0]))
		if index < WHALE_EVENTS.size() - 1:
			_check(RECORD_DISCOVERY not in state.discoveries and "I1:whale" not in state.completed_actions, "briefing/start/victory alone does not grant raw record or finish action")
		else:
			var discovery_effects := 0
			for effect in result.effects:
				if effect.type == "discovery" and effect.get("discovery_id") == RECORD_DISCOVERY: discovery_effects += 1
			_check(discovery_effects == 1, "manual record fact emits exactly one authored discovery effect")
	_check(state.completed_actions == EXPECTED_ACTIONS and state.completed.size() == 19, "four whale events finish fifth action with nineteen total goals")
	_check(state.flags.get("opening:whale_action_completed", false) and state.flags.get("opening:upstream_command_trace_known", false), "final action records completion and upstream lead")
	_check(state.discoveries.count(RECORD_DISCOVERY) == 1, "record discovery occurs exactly once")
	_check(director.hud(state, "I1").get("complete", false), "extended HUD completes only after record extraction")
	final_state = state

func _test_record_idempotency() -> void:
	for suffix in ["", ":second_peer"]:
		var result: Dictionary = director.apply_event(final_state, _event(WHALE_EVENTS[3], suffix), _context())
		var expected_code := "duplicate" if suffix.is_empty() else "already_completed"
		_check(result.get("ok", false) and result.get("code") == expected_code and not result.get("changed", true), "record replay is idempotent: " + expected_code)
		_check(result.get("effects", []).is_empty() and _same_json(result.get("state", {}), final_state), "duplicate record emits no reward/dialogue and changes no receipts or memories: " + expected_code)
		_check(result.state.discoveries.count(RECORD_DISCOVERY) == 1, "duplicate record cannot add another discovery: " + expected_code)
	var unchecked: Dictionary = director.apply_event(legacy_complete, _event(WHALE_EVENTS[0]), {"is_authority": true, "validated": false, "region_id": "I1"})
	_check(unchecked.get("code") == "validation_required", "data reducer does not accept an explicitly unvalidated interaction")

func _test_receipt_replay_and_replies() -> void:
	var restored: Variant = JSON.parse_string(JSON.stringify(final_state))
	_check(restored is Dictionary, "complete extension state survives in-memory JSON serialization")
	if not restored is Dictionary: return
	var reopened = Director.new()
	var loaded: Dictionary = reopened.load_definitions(Director.DEFAULT_PATH, [EXTENSION_PATH])
	_check(loaded.get("ok", false), "new director reloads same production content files")
	if not loaded.get("ok", false): return
	_check(reopened.validate_state(restored).get("ok", false), "new director validates serialized nineteen-goal state")
	var receipt_by_goal: Dictionary = {}
	for event_id in restored.receipts:
		var receipt: Dictionary = restored.receipts[event_id]
		receipt_by_goal[receipt.objective_id] = {"id": event_id, "type": receipt.type, "target_id": receipt.target_id, "option": receipt.option}
	var replay: Dictionary = reopened.default_state()
	for objective_id in restored.completed:
		_check(receipt_by_goal.has(objective_id), "saved objective has replayable receipt: " + str(objective_id))
		if not receipt_by_goal.has(objective_id): return
		var region := str(objective_id).get_slice(":", 0)
		var applied: Dictionary = reopened.apply_event(replay, receipt_by_goal[objective_id], _context(region))
		_check(applied.get("code") == "advanced", "public reducer replays saved receipt: " + str(objective_id))
		if not applied.get("ok", false) or not applied.get("changed", false): return
		replay = applied.state
	_check(_same_json(replay, restored), "receipt replay reproduces all flags, discoveries, memories and choices")
	var ending_fragments := {
		"npc:linlan": "鲸机也停下了",
		"npc:ruanheng": "上游中继地址",
		"npc:atai": "老根的失光时刻",
	}
	for character_id in ending_fragments:
		var lines: Array[String] = reopened.dialogue_lines(replay, str(character_id))
		_check(not lines.is_empty() and "\n".join(lines).contains(ending_fragments[character_id]), "replayed ending selects whale-specific reply: " + str(character_id))
		_check(lines != base_director.dialogue_lines(legacy_complete, str(character_id)), "ending reply differs from original fourth-action ending: " + str(character_id))
	_check(replay.characters["npc:linlan"].memories.has("opening:whale_stopped_without_cutting_bus"), "Linlan retains stopped-whale memory after receipt replay")
	_check(replay.characters["npc:ruanheng"].memories.has("opening:whale_raw_record_shared"), "Ruanheng retains shared-record memory after receipt replay")
	_check(replay.characters["npc:atai"].memories.has("opening:upstream_trace_partner"), "Atai retains upstream-partner memory after receipt replay")
