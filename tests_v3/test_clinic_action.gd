extends SceneTree
## Pure production Director/data regression. Every fact uses an explicit trusted
## context fixture; this does not exercise G/LOS, water, physics, disk or ENet.
const Director = preload("res://scripts/v3/gameplay/actions/twin_action_director.gd")
const OLD_EXTENSIONS := ["res://data/v3/actions/whale_action.json", "res://data/v3/actions/crown_action.json", "res://data/v3/actions/underdeck_action.json"]
const CLINIC_PATH := "res://data/v3/actions/clinic_action.json"
const ACTIONS := ["I1:rescue", "I1:evidence", "F1:needs", "F1:repair", "I1:whale", "F1:crown", "I1:underdeck", "I2:clinic_supply"]
const FLAG := "I2:clinic_ready"
const DISCOVERY := "I2:clinic_priority_misroute"
const MEMORY := "I2:clinic_restored_patient_access"
# Fixed historical public events, not generated from the extension under test.
const OLD_EVENTS := [
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
	["F1:crown:restore", "fact", "F1:crown_recovered", "verified"],
	["I1:underdeck:read", "inspect", "I1:underdeck_log", "read_plan"],
	["I1:underdeck:enter", "fact", "I1:underdeck_entry", "main_flight"],
	["I1:underdeck:release", "fact", "I1:underdeck_safety_lock", "released"],
	["I1:underdeck:traverse", "fact", "I1:underdeck_transit", "verified"]
]
const EVENTS := [
	["I2:clinic_supply:diagnose", "fact", "I2:clinic_demand", "identified"],
	["I2:clinic_supply:connect", "fact", "I2:clinic_feed", "gravity"],
	["I2:clinic_supply:stabilize", "fact", "I2:clinic_water_ready", "verified"],
	["I2:clinic_supply:confirm", "fact", "I2:clinic_water_check", "commissioned"]
]
var checks := 0
var failures: Array[String] = []
var director = Director.new()
var legacy = Director.new()
var legacy_complete: Dictionary = {}
var complete: Dictionary = {}

func _initialize() -> void:
	var extensions: Array = OLD_EXTENSIONS.duplicate()
	extensions.append(CLINIC_PATH)
	var old_loaded: Dictionary = legacy.load_definitions(Director.DEFAULT_PATH, OLD_EXTENSIONS)
	var loaded: Dictionary = director.load_definitions(Director.DEFAULT_PATH, extensions)
	_check(old_loaded.get("ok", false), "existing seven-action production definitions load")
	_check(loaded.get("ok", false), "clinic loads through production Director with I2 enabled: " + str(loaded.get("code")))
	if old_loaded.get("ok", false) and loaded.get("ok", false):
		_content()
		_legacy_replay()
		if not legacy_complete.is_empty():
			_order_and_trust()
			_routes()
			if not complete.is_empty(): _restore_and_repeat()
	print("CLINIC_ACTION checks=%d failures=%d" % [checks, failures.size()])
	print("CLINIC_ACTION_RESULT " + JSON.stringify({"passed":failures.is_empty(), "checks":checks, "failures":failures, "limits":["Production Director and JSON data with explicitly trusted fact fixtures only.", "No manual G/LOS, scene physics, actual transfer, stability timing, Store transaction, LAN, GPU or human-duration acceptance."]}))
	quit(0 if failures.is_empty() else 1)

func _check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)
		push_error(label)

func _same(a: Variant, b: Variant) -> bool:
	return JSON.parse_string(JSON.stringify(a)) == JSON.parse_string(JSON.stringify(b))

func _event(row: Array, suffix: String = "") -> Dictionary:
	return {"id":"qa_clinic_data:" + str(row[0]) + suffix, "type":row[1], "target_id":row[2], "option":row[3]}

func _context(row: Array) -> Dictionary:
	return {"is_authority":true, "validated":true, "region_id":str(row[0]).get_slice(":", 0)}

func _unchanged(result: Dictionary, original: Dictionary) -> bool:
	return not result.get("changed", false) and result.get("effects", []).is_empty() and _same(result.get("state"), original)

func _content() -> void:
	var defs: Dictionary = director.definitions()
	var old: Dictionary = legacy.definitions()
	var extension: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(CLINIC_PATH))
	var ids: Array = []
	var goals := 0
	for action in defs.actions:
		ids.append(action.id)
		goals += action.objectives.size()
	_check(ids == ACTIONS and goals == 31 and old.actions.size() == 7, "exact eight-action31-goal sequence")
	_check(defs.content_id == "opening_v1" and extension.content_id == "opening_clinic_extension_v1", "extension retains opening state identity")
	var old_unchanged := true
	for index in range(7): old_unchanged = old_unchanged and _same(defs.actions[index], old.actions[index])
	_check(old_unchanged, "all seven earlier actions remain byte-value equivalent after merge")
	_check(extension.characters.is_empty() and _same(director.default_state().characters, legacy.default_state().characters), "no new character/default-state migration")
	var action: Dictionary = defs.actions[7]
	_check(action.prerequisites == ["I1:underdeck"] and _same(action.target_minutes, [5, 8]), "requires complete underdeck and carries only a design-duration target")
	var sequential := true
	var after: Array = []
	for index in range(4):
		sequential = sequential and action.objectives[index].id == EVENTS[index][0] and action.objectives[index].after == after
		after = [EVENTS[index][0]]
	_check(sequential, "four fixed objectives retain diagnose-connect-stabilize-confirm order")
	var markers: Dictionary = {}
	for marker in extension.markers: markers[str(marker.id)] = marker
	var markers_ok: bool = markers.size() == 2
	for id in ["I2:clinic_demand", "I2:clinic_water_check"]:
		var marker: Dictionary = markers.get(id, {})
		markers_ok = markers_ok and marker.get("region") == "I2" and marker.get("kind") == "inspect" and _same(marker.get("position"), [7, 5.8, -3]) and marker.get("radius") == 3
	_check(markers_ok, "both explicit inspection markers use actual shared checkpoint at3m")
	var bindings: Dictionary = extension.host_bindings
	_check(bindings["I2:clinic_demand"].requires_explicit_interaction and bindings["I2:clinic_water_check"].requires_explicit_interaction and bindings["I2:clinic_demand"].requires_line_of_sight and bindings["I2:clinic_water_check"].requires_line_of_sight, "manual facts declare real G and LOS boundary")
	_check(bindings["I2:clinic_feed"].retain_before_objective and bindings["I2:clinic_water_ready"].navigation_marker_id == "I2:clinic_water_check", "early flow evidence retained and stable-state navigation resolves")
	_check(action.objectives[1].events[0].options == ["gravity", "pump"] and action.objectives[3].events[0].type == "fact", "two feed paths and manual revalidation fact are explicit")
	var without_underdeck: Array = OLD_EXTENSIONS.slice(0, 2)
	without_underdeck.append(CLINIC_PATH)
	var incomplete = Director.new()
	_check(not incomplete.load_definitions(Director.DEFAULT_PATH, without_underdeck).get("ok", false), "clinic cannot load without required underdeck action")

func _legacy_replay() -> void:
	var state: Dictionary = legacy.default_state()
	_check(director.validate_state(state).get("ok", false), "fresh old save accepts new action without mutation")
	for index in range(OLD_EVENTS.size()):
		if index == 26:
			var early: Dictionary = director.apply_event(state, _event(EVENTS[0]), _context(EVENTS[0]))
			_check(early.get("code") == "objective_locked" and _unchanged(early, state), "unlatched traversal objective must complete before clinic even after release")
		var row: Array = OLD_EVENTS[index]
		var result: Dictionary = legacy.apply_event(state, _event(row), _context(row))
		if not result.get("changed", false):
			_check(false, "legacy public event failed: " + str(row[0]))
			return
		state = result.state
		if index in [14, 22, 25, 26]:
			_check(director.validate_state(JSON.parse_string(JSON.stringify(state))).get("ok", false), "historical saved prefix accepted: " + str(index + 1))
	legacy_complete = JSON.parse_string(JSON.stringify(state))
	_check(legacy_complete.completed.size() == 27 and legacy_complete.completed_actions.size() == 7 and legacy.hud(legacy_complete).complete, "old completed save reconstructed by27 reducer transitions")
	var hud: Dictionary = director.hud(legacy_complete, "I1")
	_check(not hud.complete and hud.action_id == "I2:clinic_supply" and hud.next_region == "I2" and hud.objectives.size() == 1 and hud.objectives[0].id == EVENTS[0][0], "old completed save gets explicit I2 diagnosis destination")

func _order_and_trust() -> void:
	for index in [1, 2, 3]:
		var denied: Dictionary = director.apply_event(legacy_complete, _event(EVENTS[index]), _context(EVENTS[index]))
		_check(denied.get("code") == "objective_locked" and _unchanged(denied, legacy_complete), "later fact cannot skip diagnosis: " + str(EVENTS[index][0]))
	for context in [
		{"is_authority":false, "validated":true, "region_id":"I2"},
		{"is_authority":true, "validated":false, "region_id":"I2"},
		{"is_authority":true, "validated":true, "region_id":"I1"}]:
		var denied: Dictionary = director.apply_event(legacy_complete, _event(EVENTS[0]), context)
		_check(not denied.ok and _unchanged(denied, legacy_complete), "nonhost unverified and wrong-region facts rejected")
	var raw_inspect: Dictionary = _event(EVENTS[0])
	raw_inspect.type = "inspect"
	var denied: Dictionary = director.apply_event(legacy_complete, raw_inspect, _context(EVENTS[0]))
	_check(denied.get("code") == "unsupported_event" and _unchanged(denied, legacy_complete), "raw marker inspection cannot bypass adapter-validated diagnosis")
	var diagnosed: Dictionary = director.apply_event(legacy_complete, _event(EVENTS[0]), _context(EVENTS[0]))
	var fake_feed: Dictionary = _event(EVENTS[1])
	fake_feed.option = "powered_only"
	denied = director.apply_event(diagnosed.state, fake_feed, _context(EVENTS[1]))
	_check(denied.get("code") == "unsupported_event" and _unchanged(denied, diagnosed.state), "relay power without accepted actual-transfer route is insufficient")
	denied = director.apply_event(diagnosed.state, _event(EVENTS[3]), _context(EVENTS[3]))
	_check(denied.get("code") == "objective_locked" and _unchanged(denied, diagnosed.state), "manual confirm cannot skip flow and stabilization")

func _routes() -> void:
	var untouched: Dictionary = legacy_complete.duplicate(true)
	for route in ["gravity", "pump"]:
		var state: Dictionary = legacy_complete.duplicate(true)
		var inputs_unchanged := true
		var final_effects: Array = []
		for index in range(4):
			var row: Array = EVENTS[index].duplicate()
			if index == 1: row[3] = route
			var original: Dictionary = state.duplicate(true)
			var result: Dictionary = director.apply_event(state, _event(row), _context(row))
			inputs_unchanged = inputs_unchanged and _same(state, original)
			if not result.get("changed", false):
				_check(false, route + " did not advance " + str(row[0]))
				return
			state = result.state
			_check(director.validate_state(JSON.parse_string(JSON.stringify(state))).get("ok", false), route + " saves a valid action prefix after " + str(index + 1))
			if index < 3:
				_check(not state.flags.get(FLAG, false) and DISCOVERY not in state.discoveries and MEMORY not in state.characters["npc:ruanheng"].memories, route + " withholds final service discovery and memory before confirmation")
			if index == 1:
				var alternative: Array = EVENTS[1].duplicate()
				alternative[3] = "pump" if route == "gravity" else "gravity"
				var repeated: Dictionary = director.apply_event(state, _event(alternative, ":other_peer"), _context(alternative))
				_check(repeated.ok and _unchanged(repeated, state) and state.choices[EVENTS[1][0]] == route, route + " cannot also credit alternate route on same objective")
			if index == 3: final_effects = result.effects
		var flags: Array = []
		var findings: Array = []
		var memories: Array = []
		for effect in final_effects:
			if effect.type == "flag": flags.append(effect.key)
			if effect.type == "discovery": findings.append(effect.discovery_id)
			if effect.type == "character_memory": memories.append(effect.memory)
		_check(flags == [FLAG] and findings == [DISCOVERY] and memories == [MEMORY], route + " returns service discovery and memory together in final candidate")
		_check(state.completed_actions == ACTIONS and state.completed.size() == 31 and state.receipts.size() == 31 and director.hud(state).complete, route + " completes8actions31goals once")
		_check(inputs_unchanged and state.discoveries.count(DISCOVERY) == 1 and state.characters["npc:ruanheng"].memories.count(MEMORY) == 1, route + " leaves caller states unchanged and adds exactly one finding/memory")
		if complete.is_empty(): complete = state.duplicate(true)
		else: _check(_same(state.flags, complete.flags) and _same(state.discoveries, complete.discoveries) and _same(state.characters, complete.characters), "both routes restore same service without route-specific duplicate rewards")
	_check(_same(legacy_complete, untouched) and director.validate_state(legacy_complete).ok, "old branch remains independently unchanged and valid")

func _restore_and_repeat() -> void:
	var saved: Dictionary = JSON.parse_string(JSON.stringify(complete))
	var reloaded = Director.new()
	var extensions: Array = OLD_EXTENSIONS.duplicate()
	extensions.append(CLINIC_PATH)
	_check(reloaded.load_definitions(Director.DEFAULT_PATH, extensions).get("ok", false) and reloaded.validate_state(saved).get("ok", false), "fresh Director validates full JSON-roundtripped completion")
	for index in range(4):
		for suffix in ["", ":retry_or_other_peer"]:
			var repeated: Dictionary = reloaded.apply_event(saved, _event(EVENTS[index], suffix), _context(EVENTS[index]))
			_check(repeated.ok and _unchanged(repeated, saved), "duplicate/reissued fact has no extra effects: " + str(index) + suffix)
	var conflict: Dictionary = _event(EVENTS[1])
	conflict.option = "pump"
	var denied: Dictionary = reloaded.apply_event(saved, conflict, _context(EVENTS[1]))
	_check(denied.get("code") == "event_id_conflict" and _unchanged(denied, saved), "accepted gravity receipt cannot be rewritten to pump")
	var replay: Dictionary = reloaded.default_state()
	var by_goal: Dictionary = {}
	for id in saved.receipts:
		var receipt: Dictionary = saved.receipts[id]
		by_goal[receipt.objective_id] = {"id":id, "type":receipt.type, "target_id":receipt.target_id, "option":receipt.option}
	for goal in saved.completed:
		var result: Dictionary = reloaded.apply_event(replay, by_goal[goal], {"is_authority":true, "validated":true, "region_id":str(goal).get_slice(":", 0)})
		if not result.get("changed", false):
			_check(false, "saved receipt replay failed: " + str(goal))
			return
		replay = result.state
	_check(_same(replay, saved), "31 historical receipts reproduce exact final state")
	var tampered: Dictionary = saved.duplicate(true)
	tampered.flags[FLAG] = false
	_check(not reloaded.validate_state(tampered).get("ok", false), "saved service cannot disagree with committed confirmation receipt")
	tampered = saved.duplicate(true)
	tampered.discoveries.append(DISCOVERY)
	_check(not reloaded.validate_state(tampered).get("ok", false), "duplicate saved discovery rejected")
	tampered = saved.duplicate(true)
	tampered.characters["npc:i2_clinic_keeper"] = {"met":true, "memories":[]}
	_check(not reloaded.validate_state(tampered).get("ok", false), "undeclared character cannot enter saved state")
	_check(not reloaded.dialogue_lines(saved, "npc:ruanheng").is_empty() and not reloaded.dialogue_lines(saved, "npc:linlan").is_empty(), "existing characters retain post-repair responses")
