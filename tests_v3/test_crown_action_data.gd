extends SceneTree
## Pure extension/reducer fixtures; no scene, physics, actual boss victory, durable save or LAN claim.
const Director = preload("res://scripts/v3/gameplay/actions/twin_action_director.gd")
const WHALE_PATH := "res://data/v3/actions/whale_action.json"
const CROWN_PATH := "res://data/v3/actions/crown_action.json"
const DISCOVERY := "opening:crown_imbalance_evidence"
const ACTIONS := ["I1:rescue", "I1:evidence", "F1:needs", "F1:repair", "I1:whale", "F1:crown"]
# Fixed public contracts: objective ID, event type, target ID, option. Region comes from objective ID.
const LEGACY_EVENTS := [
	["I1:rescue:brief", "talk", "npc:linlan", "rescue_brief"],
	["I1:rescue:channel", "fact", "I1:rescue_channel", "charge"],
	["I1:rescue:contact", "reach", "I1:rescue_pocket", ""],
	["I1:rescue:evacuate", "reach", "I1:rescue_exit", ""],
	["I1:evidence:trace", "inspect", "I1:burn_trace", ""],
	["I1:evidence:engineer", "talk", "npc:ruanheng", "reverse_flow"],
	["I1:evidence:ledger", "inspect", "I1:energy_ledger", ""],
	["I1:evidence:echo", "inspect", "I1:beacon_echo", ""],
	["F1:needs:listen", "talk", "npc:atai", "needs"],
	["F1:needs:nursery", "inspect", "F1:dry_nursery", ""],
	["F1:needs:route", "reach", "F1:nursery_landing", "flight"],
	["F1:repair:plan", "talk", "npc:atai", "repair_plan"],
	["F1:repair:light", "fact", "F1:light_receiver", "aligned"],
	["F1:repair:grow", "fact", "F1:growth_bridge", "grown"],
	["F1:repair:confirm", "inspect", "F1:shared_junction", ""],
	["I1:whale:brief", "inspect", "I1:whale_briefing", "confirm_plan"],
	["I1:whale:engage", "fact", "I1:whale_engaged", "started"],
	["I1:whale:disable", "fact", "I1:whale_defeated", "committed"],
	["I1:whale:record", "fact", "I1:whale_raw_record", "retrieved"]
]
const CROWN_EVENTS := [
	["F1:crown:brief", "inspect", "F1:crown_briefing", "confirm_plan"],
	["F1:crown:engage", "fact", "F1:crown_engaged", "started"],
	["F1:crown:disable", "fact", "F1:crown_defeated", "committed"],
	["F1:crown:restore", "fact", "F1:crown_recovered", "verified"]
]
var checks := 0
var failures: Array[String] = []
var director = Director.new()
var legacy = Director.new()
var legacy_complete: Dictionary = {}
var complete: Dictionary = {}

func _initialize() -> void:
	var old_loaded: Dictionary = legacy.load_definitions(Director.DEFAULT_PATH, [WHALE_PATH])
	var loaded: Dictionary = director.load_definitions(Director.DEFAULT_PATH, [WHALE_PATH, CROWN_PATH])
	_check(old_loaded.get("ok", false), "five-action production definitions load")
	_check(loaded.get("ok", false), "crown extension loads through production merge API: " + str(loaded.get("code")))
	if old_loaded.get("ok", false) and loaded.get("ok", false):
		_test_content_contract()
		_test_legacy_replay()
		if not legacy_complete.is_empty():
			_test_crown_order_and_routes()
		if not complete.is_empty():
			_test_deduplication_and_restore()
	print("V3_CROWN_ACTION_DATA_TESTS " + JSON.stringify({"checks":checks, "failures":failures,
		"expected_actions":6, "expected_objectives":23,
		"scope":"pure content schema, event reducer and in-memory JSON replay; host facts/routes are fixtures, not live combat, interaction, save IO, LAN or human timing evidence"}))
	quit(0 if failures.is_empty() else 1)

func _check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)
		push_error(label)

func _same(left, right) -> bool:
	return JSON.parse_string(JSON.stringify(left)) == JSON.parse_string(JSON.stringify(right))

func _event(row: Array, suffix := "") -> Dictionary:
	return {"id":"qa_crown_action:" + str(row[0]) + suffix, "type":row[1], "target_id":row[2], "option":row[3]}

func _context(row: Array, route := "light_root") -> Dictionary:
	return {"is_authority":true, "validated":true, "region_id":str(row[0]).get_slice(":", 0), "combat_route":route}

func _test_content_contract() -> void:
	var defs: Dictionary = director.definitions()
	var extension = JSON.parse_string(FileAccess.get_file_as_string(CROWN_PATH))
	var ids: Array = []
	var objectives := 0
	for action in defs.actions:
		ids.append(action.id)
		objectives += action.objectives.size()
	_check(ids == ACTIONS and objectives == 23, "exactly six ordered actions and23 objectives")
	_check(defs.content_id == "opening_v1" and director.validate(defs).get("ok", false), "merged identity and schema remain compatible")
	_check(extension.characters.is_empty() and _same(director.default_state().characters, legacy.default_state().characters), "no new default character keys or memories")
	var unchanged := true
	for index in range(5): unchanged = unchanged and _same(defs.actions[index], legacy.definitions().actions[index])
	_check(unchanged, "all five legacy action definitions remain unchanged")
	var crown: Dictionary = defs.actions[5]
	_check(crown.prerequisites == ["I1:whale"] and _same(crown.target_minutes, [5, 8]) and extension.status == "runtime_candidate", "complete whale prerequisite and honest runtime-candidate status without final art or play acceptance")
	var predecessor: Array = []
	for index in range(4):
		_check(crown.objectives[index].id == CROWN_EVENTS[index][0] and crown.objectives[index].after == predecessor, "fixed sequential objective " + str(CROWN_EVENTS[index][0]))
		predecessor = [CROWN_EVENTS[index][0]]
	_check(extension.markers.size() == 1 and extension.markers[0].id == "F1:crown_briefing" and _same(extension.markers[0].position, [0, 11, -1]) and float(extension.markers[0].radius) == 3.0, "only static marker is the authored root-bridge briefing")
	var victory: Dictionary = extension.host_bindings["F1:crown_defeated"]
	_check(victory.encounter_id == "parasitic_crown" and victory.campaign_victory_flag == "campaign_crown_v1" and victory.campaign_receipt_id == "boss:F1:parasitic_crown:opening_v1" and victory.personal_reward_id == "boss:F1:parasitic_crown", "crown victory keeps independent campaign and personal reward identity")
	_check(victory.accepted_combat_routes == ["light_root", "thermal_ejection", "mixed"] and crown.objectives[2].events[0].options == ["committed"], "all combat routes converge on one saved-victory fact")
	var recovery: Dictionary = extension.host_bindings["F1:crown_recovered"]
	_check(recovery.host_anchor_id == "F1:crown_host_west" and recovery.anchor_role == "target_position" and recovery.requires_recovered_host and recovery.requires_explicit_interaction and recovery.requires_line_of_sight and float(recovery.interaction_radius_m) == 3.0 and recovery.missing_anchor_policy == "unavailable_no_origin_fallback", "recovery contract requires actual restored target plus explicit nearby unobstructed inspection")
	var bad: Dictionary = defs.duplicate(true)
	bad.actions[5].objectives[3].events[0].type = "inspect"
	_check(director.validate(bad).get("code") == "missing_target_marker", "dynamic recovered fact cannot silently become a fake static marker")
	var missing = Director.new()
	_check(not missing.load_definitions(Director.DEFAULT_PATH, [CROWN_PATH]).get("ok", false), "crown extension alone cannot omit whale prerequisite")
	_check(not director.load_definitions(Director.DEFAULT_PATH, [WHALE_PATH, CROWN_PATH, CROWN_PATH]).get("ok", false) and _same(director.definitions(), defs), "duplicate extension fails without replacing valid content")

func _test_legacy_replay() -> void:
	var state: Dictionary = legacy.default_state()
	_check(director.validate_state(state).get("ok", false), "old fresh profile replays without character migration")
	for index in LEGACY_EVENTS.size():
		if index == 18:
			var early: Dictionary = director.apply_event(state, _event(CROWN_EVENTS[0]), _context(CROWN_EVENTS[0]))
			_check(early.code == "objective_locked" and early.effects.is_empty() and _same(early.state, state), "whale victory without manually retrieved record cannot start crown")
		var row: Array = LEGACY_EVENTS[index]
		var result: Dictionary = legacy.apply_event(state, _event(row), _context(row))
		_check(result.get("changed", false) and director.validate_state(JSON.parse_string(JSON.stringify(result.state))).get("ok", false), "unchanged legacy receipt prefix replays: " + str(row[0]))
		if not result.get("changed", false): return
		state = result.state
	_check(state.completed.size() == 19 and state.completed_actions.size() == 5 and legacy.hud(state).complete, "five-action completion is built by19 real reducer transitions")
	legacy_complete = JSON.parse_string(JSON.stringify(state))
	var hud: Dictionary = director.hud(legacy_complete, "I1")
	_check(hud.action_id == "F1:crown" and hud.next_region == "F1" and not hud.complete, "old finished profile now points to sixth action in F1")
	var replies_unchanged := true
	for id in ["npc:atai", "npc:linlan", "npc:ruanheng"]:
		replies_unchanged = replies_unchanged and director.dialogue_lines(legacy_complete, id) == legacy.dialogue_lines(state, id)
	_check(replies_unchanged, "future crown replies do not leak into old ending")

func _test_crown_order_and_routes() -> void:
	for route in ["light_root", "thermal_ejection", "mixed"]:
		var state: Dictionary = legacy_complete.duplicate(true)
		for index in range(4):
			if route == "light_root" and index < 3:
				var future: Dictionary = director.apply_event(state, _event(CROWN_EVENTS[index + 1], ":early"), _context(CROWN_EVENTS[index + 1]))
				_check(future.code == "objective_locked" and future.effects.is_empty(), "cannot skip to " + str(CROWN_EVENTS[index + 1][0]))
			var before: Dictionary = state.duplicate(true)
			var result: Dictionary = director.apply_event(state, _event(CROWN_EVENTS[index]), _context(CROWN_EVENTS[index], route))
			_check(result.get("changed", false) and _same(state, before), route + " accepts fixed objective and preserves input: " + str(CROWN_EVENTS[index][0]))
			if not result.get("changed", false): return
			state = result.state
			if route == "light_root" and index < 3:
				_check(DISCOVERY not in state.discoveries and "F1:crown" not in state.completed_actions, "briefing engagement and saved victory cannot substitute for physical recovery inspection")
			if index == 3:
				var findings := 0
				var duplicate_boss_rewards := 0
				for effect in result.effects:
					if effect.type == "discovery" and effect.discovery_id == DISCOVERY: findings += 1
					if effect.type == "discovery" and str(effect.discovery_id).begins_with("boss:"): duplicate_boss_rewards += 1
				_check(findings == 1 and duplicate_boss_rewards == 0, route + " emits one evidence finding without issuing another boss reward")
		_check(state.completed_actions == ACTIONS and state.completed.size() == 23 and state.receipts.size() == 23 and director.hud(state).complete, route + " completes same six actions and23 goals")
		if complete.is_empty(): complete = state
		else: _check(_same(state, complete), route + " has identical progress flags discoveries memories and receipts")
	_check(complete.flags.get("opening:crown_action_completed", false) and complete.flags.get("opening:crossworld_imbalance_evidence", false), "completion preserves meaningful branch flags")
	for context in [
		{"is_authority":false, "validated":true, "region_id":"F1"},
		{"is_authority":true, "validated":false, "region_id":"F1"},
		{"is_authority":true, "validated":true, "region_id":"I1"}]:
		var denied: Dictionary = director.apply_event(legacy_complete, _event(CROWN_EVENTS[0]), context)
		_check(not denied.ok and denied.effects.is_empty() and _same(denied.state, legacy_complete), "authority validation and region gates reject invalid adapter input")

func _test_deduplication_and_restore() -> void:
	for index in [2, 3]:
		for suffix in ["", ":second_peer"]:
			var replayed: Dictionary = director.apply_event(complete, _event(CROWN_EVENTS[index], suffix), _context(CROWN_EVENTS[index]))
			_check(replayed.ok and not replayed.changed and replayed.effects.is_empty() and _same(replayed.state, complete) and replayed.state.discoveries.count(DISCOVERY) == 1, "repeated saved victory or recovery emits no reward again: " + str(index) + suffix)
	var reopened = Director.new()
	reopened.load_definitions(Director.DEFAULT_PATH, [WHALE_PATH, CROWN_PATH])
	var saved = JSON.parse_string(JSON.stringify(complete))
	_check(reopened.validate_state(saved).get("ok", false), "23-goal JSON state validates with freshly loaded definitions")
	var event_by_goal: Dictionary = {}
	for id in saved.receipts:
		var receipt: Dictionary = saved.receipts[id]
		event_by_goal[receipt.objective_id] = {"id":id, "type":receipt.type, "target_id":receipt.target_id, "option":receipt.option}
	var replay: Dictionary = reopened.default_state()
	for goal in saved.completed:
		var result: Dictionary = reopened.apply_event(replay, event_by_goal[goal], {"is_authority":true, "validated":true, "region_id":str(goal).get_slice(":", 0)})
		if not result.get("changed", false):
			_check(false, "saved event cannot replay: " + str(goal))
			return
		replay = result.state
	_check(_same(replay, saved), "replaying all23 receipts reproduces exact flags memories choices and discoveries")
	var tampered: Dictionary = saved.duplicate(true)
	tampered.receipts[_event(CROWN_EVENTS[3]).id].option = "automatic"
	_check(not reopened.validate_state(tampered).get("ok", false), "tampered automatic recovery cannot replace explicit verified receipt")
	_check("\n".join(reopened.dialogue_lines(saved, "npc:atai")).contains("冠兽不是最早的起因") and "\n".join(reopened.dialogue_lines(saved, "npc:ruanheng")).contains("还没有指向某个阵营"), "restored ending retains ecological cause and evidence limits")
