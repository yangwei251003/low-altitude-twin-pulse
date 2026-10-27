extends SceneTree

const Director = preload("res://scripts/v3/gameplay/actions/twin_action_director.gd")
const Store = preload("res://scripts/v3/core/twin_world_store.gd")
var checks := 0
var failures: Array[String] = []
var director = Director.new()
var qa_path := ""
var completed_state: Dictionary = {}

func _initialize() -> void:
	qa_path = "user://qa_v3_actions/" + str(Time.get_unix_time_from_system()).replace(".", "_") + "_" + str(Time.get_ticks_usec())
	var loaded = director.load_definitions()
	_check(loaded.ok, "opening definitions load: " + loaded.code)
	if loaded.ok:
		_test_definitions()
		_test_event_guards()
		_test_progression_and_restore()
		_test_alternative_routes()
		_test_corrupt_state()
		_test_store_boundaries()
	print("V3_ACTION_TESTS " + JSON.stringify({"checks":checks,"failures":failures,"qa_path":ProjectSettings.globalize_path(qa_path),"actions":4,"objective_units":15,"scope":"pure reducer + isolated store; no scene, graphics, human timing or LAN transport claim"}))
	quit(0 if failures.is_empty() else 1)

func _check(condition: bool, label: String) -> void:
	checks += 1
	if not condition: failures.append(label)

func _events() -> Array:
	var events: Array = []
	for action in director.definitions().actions:
		for objective in action.objectives:
			var matcher = objective.events[0]
			events.append({"id":"qa:" + objective.id,"type":matcher.type,"target_id":matcher.target_id,"option":matcher.options[0],"_region":action.region_id})
	return events

func _context(event: Dictionary) -> Dictionary:
	return {"is_authority":true,"validated":true,"region_id":event._region}

func _apply(state: Dictionary, event: Dictionary) -> Dictionary:
	return director.apply_event(state, event, _context(event))

func _same_json(left: Variant, right: Variant) -> bool:
	return JSON.parse_string(JSON.stringify(left)) == JSON.parse_string(JSON.stringify(right))

func _write(path: String, contents: String) -> void:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var file = FileAccess.open(path, FileAccess.WRITE)
	_check(file != null, "write isolated fixture")
	if file:
		file.store_string(contents)
		file.close()

func _test_definitions() -> void:
	var data = director.definitions()
	_check(data.actions.size() == 4 and _events().size() == 15, "honest four action fifteen goal scope")
	_check(data.characters.size() == 3 and data.markers.size() == 11, "persistent characters and explicit interaction markers")
	_check(director.validate(data).ok, "valid definition independently validates")
	data.actions[0].title = "external mutation"
	_check(director.definitions().actions[0].title != "external mutation", "definitions defensive copy")
	var bad = director.definitions()
	bad.actions[0].completion_text = ["not a string"]
	_check(not director.validate(bad).ok, "invalid authored outcome text rejected")
	bad = director.definitions()
	bad.actions[0].erase("completion_text")
	_check(director.validate(bad).ok, "legacy action without outcome text still loads")
	bad = director.definitions()
	bad.actions[1].id = bad.actions[0].id
	_check(not director.validate(bad).ok, "duplicate action rejected")
	bad = director.definitions()
	bad.actions[0].prerequisites = [bad.actions[3].id]
	_check(not director.validate(bad).ok, "forward/cyclic prerequisite rejected")
	bad = director.definitions()
	bad.actions[0].objectives[0].after = [bad.actions[0].objectives[3].id]
	_check(not director.validate(bad).ok, "forward objective dependency rejected")
	bad = director.definitions()
	bad.actions[0].objectives[1].events = bad.actions[0].objectives[0].events.duplicate(true)
	_check(not director.validate(bad).ok, "ambiguous event match rejected")
	bad = director.definitions()
	bad.actions[0].objectives[0].events[0].target_id = "npc:missing"
	_check(not director.validate(bad).ok, "missing marker rejected")
	bad = director.definitions()
	bad.markers[0].region = "F1"
	_check(not director.validate(bad).ok, "cross-region marker rejected")
	bad = director.definitions()
	bad.markers[0].position = [0, INF, 0]
	_check(not director.validate(bad).ok, "nonfinite marker rejected")
	bad = director.definitions()
	bad.markers[0].position = [51, 1, 0]
	_check(not director.validate(bad).ok, "out of bounds marker rejected")
	bad = director.definitions()
	bad.actions[0].objectives[0].effects[0].character_id = "npc:missing"
	_check(not director.validate(bad).ok, "unknown dialogue character rejected")
	bad = director.definitions()
	bad.actions[0].effects[0].type = "grant_currency"
	_check(not director.validate(bad).ok, "unimplemented reward type rejected")
	bad = director.definitions()
	bad.characters[0].replies[0].after = "unknown:goal"
	_check(not director.validate(bad).ok, "unknown reply prerequisite rejected")
	bad = director.definitions()
	bad.schema_version = 999
	_check(not director.validate(bad).ok, "future definition schema rejected")
	var initial = director.definitions()
	_write(qa_path.path_join("invalid.json"), "{broken")
	_check(not director.load_definitions(qa_path.path_join("invalid.json")).ok, "malformed json load rejected")
	_check(director.definitions() == initial, "failed load retains valid cache")
	_write(qa_path.path_join("future.json"), JSON.stringify(bad))
	_check(not director.load_definitions(qa_path.path_join("future.json")).ok and director.definitions() == initial, "future schema load retains cache")
	_check(not director.load_definitions(qa_path.path_join("absent.json")).ok, "missing definitions rejected")
	var empty = Director.new()
	_check(empty.default_state().is_empty() and not empty.validate_state({}).ok, "unloaded director cannot silently create a save")

func _test_event_guards() -> void:
	var state = director.default_state()
	var events = _events()
	_check(director.validate_state(state).ok, "default state validates")
	var before = state.duplicate(true)
	for context in [{}, {"is_authority":false,"validated":true,"region_id":"I1"}, {"is_authority":true,"region_id":"I1"}, {"is_authority":true,"validated":false,"region_id":"I1"}, {"is_authority":1,"validated":true,"region_id":"I1"}, {"is_authority":true,"validated":1,"region_id":"I1"}, {"is_authority":true,"validated":true,"region_id":"F1"}]:
		var result = director.apply_event(state, events[0], context)
		_check(not result.ok and not result.changed and result.effects.is_empty() and result.state == before, "authority/range/region guard " + str(context))
	var future = _apply(state, events[1])
	_check(not future.ok and future.code == "objective_locked" and future.state == before, "future fact cannot bypass briefing")
	_check(not state.receipts.has(events[1].id), "rejected future event does not consume receipt")
	var story_skip = _apply(state, events[14])
	_check(not story_skip.ok and story_skip.code == "objective_locked", "cannot skip action chain")
	var unsupported = events[0].duplicate(true)
	unsupported.target_id = "npc:missing"
	_check(not _apply(state, unsupported).ok, "unknown target rejected")
	unsupported = events[0].duplicate(true)
	unsupported.option = "repair_plan"
	_check(not _apply(state, unsupported).ok, "unauthored dialogue option rejected")
	unsupported = events[0].duplicate(true)
	unsupported.type = "death"
	_check(not _apply(state, unsupported).ok and state == before, "death is not a progression-reset event")
	unsupported = events[0].duplicate(true)
	unsupported.id = ""
	_check(not _apply(state, unsupported).ok, "empty receipt id rejected")
	unsupported.id = "x".repeat(161)
	_check(not _apply(state, unsupported).ok, "oversized receipt id rejected")
	var brief = _apply(state, events[0])
	_check(brief.ok and brief.changed and brief.state.characters["npc:linlan"].met, "briefing marks persistent character met")
	var fact = _apply(brief.state, events[1])
	_check(fact.ok and fact.changed, "previously rejected fact can be reobserved with same id after unlock")
	var conflicted = events[1].duplicate(true)
	conflicted.id = events[0].id
	_check(director.apply_event(brief.state, conflicted, _context(conflicted)).code == "event_id_conflict", "receipt id cannot be reused for a different event")
	_check(state == before, "all successful and failed reductions leave input unchanged")
	brief.state.flags["forged"] = true
	brief.effects[1].lines[0] = "changed presentation"
	_check(state == before and director.definitions().actions[0].objectives[0].effects[0].lines[0] != "changed presentation", "returned state and effects are detached")

func _test_progression_and_restore() -> void:
	var state = director.default_state()
	var all_effect_ids: Dictionary = {}
	var events = _events()
	var initial_hud = director.hud(state, "I1")
	_check(initial_hud.objectives.size() == 1 and initial_hud.objectives[0].targets[0].options == ["rescue_brief"], "hud exposes only current actionable topic")
	_check(director.dialogue_lines(state, "npc:missing").is_empty(), "unknown character has no dialogue")
	for index in events.size():
		var before = state.duplicate(true)
		var result = _apply(state, events[index])
		_check(result.ok and result.changed and result.code == "advanced", "progression step " + str(index))
		if not result.ok: return
		_check(state == before and result.state.revision == index + 1, "immutable input and one revision per objective " + str(index))
		for effect in result.effects:
			_check(not all_effect_ids.has(effect.id), "stable effect id unique " + effect.id)
			all_effect_ids[effect.id] = true
		state = JSON.parse_string(JSON.stringify(result.state))
		_check(director.validate_state(state).ok, "JSON save/load validates after step " + str(index))
		var duplicate = _apply(state, events[index])
		_check(duplicate.ok and not duplicate.changed and duplicate.code == "duplicate" and duplicate.effects.is_empty() and duplicate.state == state, "same event replay no reward " + str(index))
		var repeated = events[index].duplicate(true)
		repeated.id += ":new_transport"
		var repeat_result = _apply(state, repeated)
		_check(repeat_result.ok and not repeat_result.changed and repeat_result.code == "already_completed" and repeat_result.effects.is_empty() and repeat_result.state == state, "new event id same completed goal no reward " + str(index))
		if index == 7:
			var hud = director.hud(state, "I1")
			_check(hud.next_region == "F1" and hud.completed_actions == 2 and hud.action_id == "F1:needs", "cross-world HUD asks for real region transition")
			_check(director.hud(state, "F1").next_region.is_empty(), "arrival removes region reminder")
	var hud = director.hud(state, "F1")
	_check(hud.complete and hud.completed_actions == 4 and hud.objectives.is_empty(), "four actions finish with no filler goal")
	_check(state.completed.size() == 15 and state.receipts.size() == 15 and state.choices.size() == 15, "bounded one receipt per objective")
	_check(state.discoveries.size() == 6 and state.flags["opening:local_repair_completed"], "information and durable local repair rewards")
	_check(state.characters["npc:atai"].met and "opening:repair_partner" in state.characters["npc:atai"].memories, "character remembers shared repair")
	_check("幼根重新有了光" in " ".join(director.dialogue_lines(state, "npc:atai")), "post-repair character dialogue changes")
	var compact = JSON.stringify(state)
	_check(not compact.contains("lines") and not compact.contains("检修机困在桥后") and compact.length() < 11000, "persistent state excludes prose and stays compact")
	var invalid_death = {"id":"death:1","type":"death","target_id":"pilot","option":"","_region":"F1"}
	_check(_apply(state, invalid_death).state == state, "death cannot regress committed world progress")
	completed_state = state

func _test_alternative_routes() -> void:
	for rescue_option in ["charge", "heat", "takeover", "aerial"]:
		for route_option in ["flight", "growth", "blink"]:
			var state = director.default_state()
			var events = _events()
			events[1].option = rescue_option
			events[10].option = route_option
			var valid := true
			for event in events:
				var result = _apply(state, event)
				if not result.ok:
					valid = false
					break
				state = result.state
			_check(valid and director.hud(state).complete and director.validate_state(state).ok, "complete alternative " + rescue_option + "/" + route_option)
			_check(state.choices.get("I1:rescue:channel") == rescue_option and state.choices.get("F1:needs:route") == route_option, "retain actual solution " + rescue_option + "/" + route_option)
	var before = _apply(director.default_state(), _events()[0]).state
	var event = _events()[1]
	event.option = "shoot"
	_check(not _apply(before, event).ok, "unsupported solution does not masquerade as verified fact")

func _test_corrupt_state() -> void:
	if completed_state.is_empty(): return
	for mutation in ["schema", "content", "unknown_goal", "order", "flag", "choice", "discovery", "memory", "receipt_hash", "receipt_count", "revision", "extra"]:
		var bad = completed_state.duplicate(true)
		match mutation:
			"schema": bad.schema_version = 999
			"content": bad.content_id = "another_story"
			"unknown_goal": bad.completed[0] = "unknown:goal"
			"order": bad.completed.reverse()
			"flag": bad.flags["forged_access"] = true
			"choice": bad.choices["I1:rescue:channel"] = "takeover"
			"discovery": bad.discoveries.append("unearned")
			"memory": bad.characters["npc:atai"].memories.clear()
			"receipt_hash": bad.receipts[_events()[0].id].fingerprint = "forged"
			"receipt_count": bad.receipts.erase(_events()[0].id)
			"revision": bad.revision += 1
			"extra": bad["unsafe_extension"] = true
		_check(not director.validate_state(bad).ok, "corrupt saved state rejected: " + mutation)
		var reduced = _apply(bad, _events()[0])
		_check(not reduced.ok and reduced.state == bad and reduced.effects.is_empty(), "corrupt state never reset silently: " + mutation)
	_check(director.hud({}).has("error") and director.dialogue_lines({}, "npc:atai").is_empty(), "corrupt state presentation fails closed")

func _test_store_boundaries() -> void:
	var host = Store.new(qa_path.path_join("host"))
	var guest = Store.new(qa_path.path_join("guest"))
	_check(host.load_profile().ok and guest.load_profile().ok, "isolated host and guest stores load")
	var state = director.default_state()
	_check(host.commit({"id":"qa:bootstrap","set":{"world.actions.opening":state}}).ok, "store accepts opening namespace")
	_check(host.fork_branch("before_actions", "行动前独立分支", false).ok, "fork retains independent initial action state")
	var events = _events()
	var reduced = _apply(state, events[0])
	var before = host.snapshot()
	host.failure_point = "before_publish"
	_check(not host.commit({"id":"qa:brief","set":{"world.actions.opening":reduced.state}}).ok, "action save failure injected")
	_check(host.snapshot() == before and director.hud(host.data.world.actions.opening).action_id == "I1:rescue", "failed save leaves durable progress and live snapshot unchanged")
	_check(host.data.world.actions.opening.revision == 0, "failed objective remains pending for retry")
	host.failure_point = ""
	_check(host.commit({"id":"qa:brief","set":{"world.actions.opening":reduced.state}}).ok, "same action transaction retries after fault recovery")
	state = reduced.state
	for index in range(1, 4): state = _apply(state, events[index]).state
	var reward_id = "opening:rescue_log"
	var gift = {"guest_id":guest.data.profile_id,"reward_id":reward_id,"payload":{"discoveries":[reward_id]}}
	var tx = {"id":"qa:rescue","set":{"world.actions.opening":state},"append":{"personal.discoveries":[reward_id]},"guest_rewards":[gift]}
	_check(host.commit(tx).ok, "world action + personal discovery + guest outbox commit atomically")
	var restored = Store.new(host.root_path)
	_check(restored.load_profile().ok and director.validate_state(restored.data.world.actions.opening).ok and _same_json(restored.data.world.actions.opening, state), "action progress exactly restored from real disk")
	var pending = host.pending_guest_receipts(guest.data.profile_id)
	_check(pending.size() == 1 and guest.apply_guest_receipt(pending[0]).ok, "guest receives personal discovery after delayed delivery")
	_check(guest.apply_guest_receipt(pending[0]).duplicate and guest.data.personal.discoveries == [reward_id], "guest reconnect replay cannot duplicate discovery")
	_check(guest.data.world.get("actions", {}).is_empty(), "guest receipt does not copy host world story")
	_check(host.switch_branch("before_actions").ok, "restore pre-action branch")
	_check(host.data.world.actions.opening.revision == 0 and host.data.personal.discoveries == [reward_id], "branch rewinds world goals but retains personal discovery")
	var replay = host.data.world.actions.opening
	for index in range(4): replay = _apply(replay, events[index]).state
	_check(replay.completed_actions == ["I1:rescue"], "same objective event ids can progress a different branch")
	_check(host.commit({"id":"qa:rescue:other_branch","set":{"world.actions.opening":replay},"append":{"personal.discoveries":[reward_id]},"guest_rewards":[gift]}).ok, "branch replay world commit succeeds with stable guest receipt")
	_check(host.pending_guest_receipts(guest.data.profile_id).size() == 1 and host.data.personal.discoveries == [reward_id], "branch replay does not farm guest or host rewards")
	_check(host.switch_branch("main").ok and _same_json(host.data.world.actions.opening, state), "returning to main restores its independent progress")
