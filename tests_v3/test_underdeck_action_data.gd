extends SceneTree
## Pure production Director/data checks. Context is explicitly a validated-fact
## fixture: no physical crossing, one-second signal, disk save or LAN is simulated.
const Director = preload("res://scripts/v3/gameplay/actions/twin_action_director.gd")
const WHALE_PATH := "res://data/v3/actions/whale_action.json"
const CROWN_PATH := "res://data/v3/actions/crown_action.json"
const UNDERDECK_PATH := "res://data/v3/actions/underdeck_action.json"
const DISCOVERY := "opening:underdeck_worker_bypass"
const LATCH_FLAG := "opening:underdeck_latched"
const ROUTE_FLAG := "opening:underdeck_route_verified"
const MEMORY := "opening:kept_worker_repair_route"
const ROUTES := ["held_grille", "main_flight", "side_flight", "side_blink"]
const ACTIONS := ["I1:rescue", "I1:evidence", "F1:needs", "F1:repair", "I1:whale", "F1:crown", "I1:underdeck"]
# Fixed existing public events, independent of the newly authored data.
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
	["I1:whale:record", "fact", "I1:whale_raw_record", "retrieved"],
	["F1:crown:brief", "inspect", "F1:crown_briefing", "confirm_plan"],
	["F1:crown:engage", "fact", "F1:crown_engaged", "started"],
	["F1:crown:disable", "fact", "F1:crown_defeated", "committed"],
	["F1:crown:restore", "fact", "F1:crown_recovered", "verified"]
]
const EVENTS := [
	["I1:underdeck:read", "inspect", "I1:underdeck_log", "read_plan"],
	["I1:underdeck:enter", "fact", "I1:underdeck_entry", "main_flight"],
	["I1:underdeck:release", "fact", "I1:underdeck_safety_lock", "released"],
	["I1:underdeck:traverse", "fact", "I1:underdeck_transit", "verified"]
]
var checks := 0
var failures: Array[String] = []
var director = Director.new()
var legacy = Director.new()
var legacy_complete: Dictionary = {}
var complete: Dictionary = {}

func _initialize() -> void:
	var old_loaded: Dictionary = legacy.load_definitions(Director.DEFAULT_PATH, [WHALE_PATH, CROWN_PATH])
	var loaded: Dictionary = director.load_definitions(Director.DEFAULT_PATH, [WHALE_PATH, CROWN_PATH, UNDERDECK_PATH])
	_check(old_loaded.get("ok", false), "existing six-action production data loads")
	_check(loaded.get("ok", false), "underdeck extension loads through production Director: " + str(loaded.get("code")))
	if old_loaded.get("ok", false) and loaded.get("ok", false):
		_content_contract()
		_old_state_replay()
		if not legacy_complete.is_empty():
			_order_and_authority()
			_routes_and_effects()
			if not complete.is_empty(): _restore_and_deduplicate()
	print("UNDERDECK_ACTION_DATA checks=%d failures=%d" % [checks, failures.size()])
	print("UNDERDECK_ACTION_DATA_RESULT " + JSON.stringify({"passed":failures.is_empty(), "checks":checks, "failures":failures, "limits":["Pure Director with explicit validated-fact fixtures only.", "No scene geometry, genuine entering/leaving, continuous signal, store failure, first-frame restore, network or human-duration acceptance."]}))
	quit(0 if failures.is_empty() else 1)

func _check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)
		push_error(label)

func _same(left, right) -> bool:
	return JSON.parse_string(JSON.stringify(left)) == JSON.parse_string(JSON.stringify(right))

func _event(row: Array, suffix := "") -> Dictionary:
	return {"id":"qa_underdeck_data:" + str(row[0]) + suffix, "type":row[1], "target_id":row[2], "option":row[3]}

func _context(row: Array) -> Dictionary:
	return {"is_authority":true, "validated":true, "region_id":str(row[0]).get_slice(":", 0)}

func _content_contract() -> void:
	var defs: Dictionary = director.definitions()
	var old: Dictionary = legacy.definitions()
	var extension: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(UNDERDECK_PATH))
	var ids: Array = []
	var objective_count := 0
	for action in defs.actions:
		ids.append(action.id)
		objective_count += action.objectives.size()
	_check(ids == ACTIONS and objective_count == 27 and old.actions.size() == 6, "exact seven-action27-objective extension of six existing actions")
	_check(defs.content_id == "opening_v1" and extension.content_id == "opening_underdeck_extension_v1" and extension.extends_content_id == "opening_v1", "stable opening identity and separate extension ID")
	var unchanged := true
	for index in range(6): unchanged = unchanged and _same(defs.actions[index], old.actions[index])
	_check(unchanged, "six existing action definitions and objective IDs remain unchanged by merge")
	_check(extension.characters.is_empty() and _same(director.default_state().characters, legacy.default_state().characters), "no invented character or default-state migration")
	var action: Dictionary = defs.actions[6]
	_check(action.prerequisites == ["F1:crown"] and _same(action.target_minutes, [5, 8]), "full crown completion prerequisite and5-to8-minute design target")
	var sequential := true
	var after: Array = []
	for index in range(4):
		sequential = sequential and action.objectives[index].id == EVENTS[index][0] and action.objectives[index].after == after
		after = [EVENTS[index][0]]
	_check(sequential, "read enter release traverse keep fixed sequential IDs")
	var marker: Dictionary = extension.markers[0] if extension.markers.size() == 1 else {}
	_check(marker.get("id") == "I1:underdeck_log" and marker.get("kind") == "inspect" and marker.get("region") == "I1" and _same(marker.get("position"), [-34, 1.6, -16.7]) and marker.get("radius") == 2.5, "only marker is the actual south-mouth inspection point at2.5m")
	var bindings: Dictionary = extension.host_bindings
	_check(bindings["I1:underdeck_log"].requires_line_of_sight and bindings["I1:underdeck_log"].requires_explicit_interaction and action.objectives[0].events[0].options == ["read_plan"], "manual LOS inspection has fixed read_plan event")
	_check(action.objectives[1].events[0].options == ROUTES, "natural window held door side flight and validated blink share one objective")
	_check(bindings["I1:underdeck_safety_lock"].accepted_control_methods == ["echo", "takeover"] and action.objectives[2].events[0].options == ["released"], "both control methods converge on one adapter-validated release fact")
	var missing = Director.new()
	_check(not missing.load_definitions(Director.DEFAULT_PATH, [WHALE_PATH, UNDERDECK_PATH]).get("ok", false), "missing crown prerequisite rejects extension")
	_check(not missing.load_definitions(Director.DEFAULT_PATH, [WHALE_PATH, UNDERDECK_PATH, CROWN_PATH]).get("ok", false), "extension before its prerequisite rejects content order")

func _old_state_replay() -> void:
	var state: Dictionary = legacy.default_state()
	_check(director.validate_state(state).get("ok", false), "existing fresh state accepts extension without migration")
	for index in range(LEGACY_EVENTS.size()):
		if index == 22:
			var early: Dictionary = director.apply_event(state, _event(EVENTS[0]), _context(EVENTS[0]))
			_check(early.get("code") == "objective_locked" and early.effects.is_empty() and _same(early.state, state), "crown victory without recovered-root inspection cannot begin underdeck")
		var row: Array = LEGACY_EVENTS[index]
		var result: Dictionary = legacy.apply_event(state, _event(row), _context(row))
		if not result.get("changed", false):
			_check(false, "existing event replay failed: " + str(row[0]))
			return
		state = result.state
		if index in [14, 18, 21, 22]:
			_check(director.validate_state(JSON.parse_string(JSON.stringify(state))).get("ok", false), "old saved progress prefix validates after extension: " + str(index + 1))
	legacy_complete = JSON.parse_string(JSON.stringify(state))
	_check(legacy_complete.completed.size() == 23 and legacy_complete.completed_actions.size() == 6 and legacy.hud(legacy_complete).complete, "old completion built from23 genuine reducer transitions")
	var hud: Dictionary = director.hud(legacy_complete, "F1")
	_check(not hud.complete and hud.action_id == "I1:underdeck" and hud.next_region == "I1" and hud.objectives.size() == 1 and hud.objectives[0].id == "I1:underdeck:read", "old completed save now receives explicit return-to-I1 objective")

func _order_and_authority() -> void:
	for index in [1, 2, 3]:
		var result: Dictionary = director.apply_event(legacy_complete, _event(EVENTS[index]), _context(EVENTS[index]))
		_check(result.get("code") == "objective_locked" and not result.changed and result.effects.is_empty() and _same(result.state, legacy_complete), "out-of-order fact cannot open doors or award discovery: " + str(EVENTS[index][0]))
	for context in [
		{"is_authority":false, "validated":true, "region_id":"I1"},
		{"is_authority":true, "validated":false, "region_id":"I1"},
		{"is_authority":true, "validated":true, "region_id":"F1"}]:
		var denied: Dictionary = director.apply_event(legacy_complete, _event(EVENTS[0]), context)
		_check(not denied.ok and not denied.changed and denied.effects.is_empty() and _same(denied.state, legacy_complete), "untrusted unvalidated or wrong-region adapter input rejected")
	var read: Dictionary = director.apply_event(legacy_complete, _event(EVENTS[0]), _context(EVENTS[0]))
	var invalid_route := _event(EVENTS[1])
	invalid_route.option = "through_closed_door"
	var rejected: Dictionary = director.apply_event(read.state, invalid_route, _context(EVENTS[1]))
	_check(rejected.get("code") == "unsupported_event" and rejected.effects.is_empty() and _same(rejected.state, read.state), "unknown route cannot claim physical entry")
	var release_early: Dictionary = director.apply_event(read.state, _event(EVENTS[2]), _context(EVENTS[2]))
	_check(release_early.get("code") == "objective_locked" and not release_early.state.flags.get(LATCH_FLAG, false), "inspection alone cannot unlock inner latch")

func _routes_and_effects() -> void:
	var original: Dictionary = legacy_complete.duplicate(true)
	for route in ROUTES:
		var state: Dictionary = legacy_complete.duplicate(true)
		var immutable := true
		var no_early_discovery := true
		for index in range(4):
			var row: Array = EVENTS[index].duplicate()
			if index == 1: row[3] = route
			var before: Dictionary = state.duplicate(true)
			var result: Dictionary = director.apply_event(state, _event(row), _context(row))
			immutable = immutable and _same(state, before)
			if not result.get("changed", false):
				_check(false, route + " failed objective " + str(row[0]))
				return
			state = result.state
			if index < 3: no_early_discovery = no_early_discovery and DISCOVERY not in state.discoveries and not state.flags.get(ROUTE_FLAG, false)
			if index < 2: no_early_discovery = no_early_discovery and not state.flags.get(LATCH_FLAG, false)
			if index == 2:
				_check(state.flags.get(LATCH_FLAG, false) and not before.flags.get(LATCH_FLAG, false) and not state.flags.get(ROUTE_FLAG, false), route + " release returns candidate permanent flag without mutating caller")
			if index == 3:
				var discoveries: Array = []
				for effect in result.effects:
					if effect.type == "discovery": discoveries.append(effect.discovery_id)
				_check(discoveries == [DISCOVERY], route + " traversal emits exactly one discovery and no resource or boss reward")
		_check(immutable and no_early_discovery, route + " keeps input isolated and withholds traversal finding until final fact")
		_check(state.completed_actions == ACTIONS and state.completed.size() == 27 and state.receipts.size() == 27 and director.hud(state).complete and state.choices[EVENTS[1][0]] == route, route + " completes the same four new goals once")
		_check(state.flags.get(LATCH_FLAG, false) and state.flags.get(ROUTE_FLAG, false) and state.characters["npc:ruanheng"].memories.count(MEMORY) == 1 and state.discoveries.count(DISCOVERY) == 1, route + " retains permanent route finding and Ruanheng memory")
		if complete.is_empty(): complete = state.duplicate(true)
		else: _check(_same(state.flags, complete.flags) and _same(state.discoveries, complete.discoveries) and _same(state.characters, complete.characters), route + " has identical consequences without route-specific extra rewards")
	_check(_same(legacy_complete, original) and director.validate_state(legacy_complete).ok and legacy_complete.completed.size() == 23, "independent old branch remains valid and unchanged")

func _restore_and_deduplicate() -> void:
	for index in [2, 3]:
		for suffix in ["", ":second_peer"]:
			var result: Dictionary = director.apply_event(complete, _event(EVENTS[index], suffix), _context(EVENTS[index]))
			_check(result.ok and not result.changed and result.effects.is_empty() and _same(result.state, complete), "repeat release/traverse has no extra effects: " + str(index) + suffix)
	var reopened = Director.new()
	reopened.load_definitions(Director.DEFAULT_PATH, [WHALE_PATH, CROWN_PATH, UNDERDECK_PATH])
	var saved: Dictionary = JSON.parse_string(JSON.stringify(complete))
	_check(reopened.validate_state(saved).get("ok", false), "freshly loaded Director validates exact27-goal JSON state")
	var events_by_goal: Dictionary = {}
	for id in saved.receipts:
		var receipt: Dictionary = saved.receipts[id]
		events_by_goal[receipt.objective_id] = {"id":id, "type":receipt.type, "target_id":receipt.target_id, "option":receipt.option}
	var replay: Dictionary = reopened.default_state()
	for goal in saved.completed:
		var result: Dictionary = reopened.apply_event(replay, events_by_goal[goal], {"is_authority":true, "validated":true, "region_id":str(goal).get_slice(":", 0)})
		if not result.get("changed", false):
			_check(false, "saved receipt replay failed: " + str(goal))
			return
		replay = result.state
	_check(_same(replay, saved), "all27 saved receipts reproduce exact goals flags memories and discoveries")
	var tampered: Dictionary = saved.duplicate(true)
	tampered.flags[LATCH_FLAG] = false
	_check(not reopened.validate_state(tampered).get("ok", false), "release receipt cannot coexist with tampered closed permanent flag")
	tampered = saved.duplicate(true)
	tampered.discoveries.append(DISCOVERY)
	_check(not reopened.validate_state(tampered).get("ok", false), "duplicated saved discovery is rejected rather than rewarded twice")
	tampered = saved.duplicate(true)
	tampered.receipts[_event(EVENTS[3]).id].option = "near_exit"
	_check(not reopened.validate_state(tampered).get("ok", false), "proximity cannot replace verified traversal receipt on restore")
	var conflict := _event(EVENTS[1])
	conflict.option = "side_blink" # Existing completed branch used held_grille.
	var denied: Dictionary = reopened.apply_event(saved, conflict, _context(EVENTS[1]))
	_check(denied.get("code") == "event_id_conflict" and denied.effects.is_empty() and _same(denied.state, saved), "same receipt ID cannot rewrite its accepted route")
	_check(not reopened.dialogue_lines(saved, "npc:ruanheng").is_empty() and saved.characters["npc:ruanheng"].memories.has(MEMORY), "restored completed route retains Ruanheng follow-up and memory")
