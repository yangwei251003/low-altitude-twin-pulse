extends SceneTree
## Real solo Session, UI handlers, PhysicsServer and isolated Store regression.
## Scripted poses / zero-time firing pulses are fixtures, not human usability,
## normal combat difficulty, rendered graphics, performance or network evidence.
const Main = preload("res://scenes/v3/main.tscn")
const Store = preload("res://scripts/v3/core/twin_world_store.gd")
const Rules = preload("res://scripts/v3/gameplay/twin_ability_rules.gd")
const StoryFixtures = preload("res://tests_v3/test_crown_action_data.gd")
var session
var profile = ""
var checks: Array = []
var failures: Array = []
var notices: Array = []
var intents: Array = []
var source_hashes: Dictionary = {}
var default_hashes: Dictionary = {}
var saved_brief: Dictionary = {}

func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--qa-profile="): profile = arg.trim_prefix("--qa-profile=")
	if not profile.begins_with("qa_guidance_") or profile != profile.validate_filename() or DirAccess.dir_exists_absolute("user://profiles_v3/" + profile):
		push_error("A fresh isolated qa_guidance_<unique> profile is required")
		quit(2)
		return
	_run.call_deferred()

func check(ok: bool, label: String, detail: Dictionary = {}) -> void:
	checks.append({"name":label, "passed":ok, "detail":detail})
	if not ok:
		failures.append(label)
		push_error("GUIDANCE SESSION: " + label + " " + JSON.stringify(detail))

func tree_hashes(path: String) -> Dictionary:
	var result: Dictionary = {}
	if not DirAccess.dir_exists_absolute(path): return result
	for name in DirAccess.get_files_at(path): result[path.path_join(name)] = FileAccess.get_sha256(path.path_join(name))
	for name in DirAccess.get_directories_at(path): result.merge(tree_hashes(path.path_join(name)))
	return result

func settle() -> void:
	await physics_frame
	await physics_frame
	await process_frame

func place(at: Vector3) -> void:
	var body = session.players[1]
	body.freeze = true
	body.set_process(false)
	body.set_physics_process(false)
	body.global_position = at
	body.force_update_transform()
	PhysicsServer3D.body_set_state(body.get_rid(), PhysicsServer3D.BODY_STATE_TRANSFORM, body.global_transform)
	body.linear_velocity = Vector3.ZERO
	body.hold_height = at.y
	session.entities["player:1"].position = at
	if session.boss_active and session.region_id == "I1": session.encounter.set_player_position("1", at)
	await settle()

func key(code: Key) -> void:
	var event = InputEventKey.new()
	event.pressed = true
	event.physical_keycode = code
	session._unhandled_input(event)

func details_button(node: Node) -> Button:
	if node is Button and node.text in ["展开提示", "收起提示"]: return node
	for child in node.get_children():
		var found = details_button(child)
		if found != null: return found
	return null

func visible_suggestions() -> Array:
	var ids: Array = []
	for button in session.interface.suggestion_buttons:
		if button.is_visible_in_tree(): ids.append(str(button.get_meta("ability", "")))
	return ids

func current_beams() -> int:
	var count = 0
	for child in session.world.get_children():
		if child is MeshInstance3D and child.mesh is CylinderMesh and is_equal_approx(child.mesh.top_radius, 0.055): count += 1
	return count

func combat_health() -> Dictionary:
	var state: Dictionary = session.crown.encounter.get_state() if session.crown.active() else session.encounter.get_state()
	var result = {"core":state.get("core_health", -1), "pilot":session.players[1].health}
	for id in state.get("nodes", {}): result[id] = state.nodes[id].health
	return result

func fire_input() -> void:
	# Route an actual mapped fire action through PilotInput -> solo transport ->
	# production host physics loop. Zero delta isolates feedback from regen/timers;
	# resetting weapon pacing here is an explicit repeated-refusal fixture.
	session.weapon_cooldowns[1] = 0.0
	Input.action_press("flight_fire")
	session._physics_process(0.0)
	Input.action_release("flight_fire")
	check(bool(session.players[1].command.get("fire", false)), "mapped fire input reaches host command")

func refusal(label: String, expected_code: String) -> void:
	# Allow the previous different-code notification to age naturally. Do not
	# rewrite production timestamps or call the throttler instead of shooting.
	await create_timer(0.96).timeout
	var before_health = combat_health()
	var before_energy = session.entities["player:1"].energy
	var before_shots = session.stats.shots
	var before_beams = current_beams()
	var before_notices = notices.size()
	fire_input()
	var first_notice: Dictionary = session.shot_notices.get(1, {}).duplicate(true)
	var text = session.interface.message.text
	check(str(first_notice.get("code", "")) == expected_code, label + " uses actual refusal code", {"notice":first_notice, "message":text})
	check(notices.size() == before_notices + 1 and not text.is_empty(), label + " produces exactly one player notice")
	for i in range(5): fire_input()
	check(notices.size() == before_notices + 1 and session.shot_notices.get(1, {}) == first_notice, label + " repeated fire is rate-limited without changing notice timestamp")
	check(session.interface.message.text == text, label + " feedback remains stable during repeated refusal")
	check(combat_health() == before_health, label + " never changes pilot or boss health", {"before":before_health, "after":combat_health()})
	check(session.entities["player:1"].energy == before_energy, label + " never consumes ability energy")
	check(session.stats.shots == before_shots and current_beams() == before_beams, label + " produces no accepted shot or beam", {"shots_before":before_shots, "shots_after":session.stats.shots, "beams_before":before_beams, "beams_after":current_beams()})

func toggle_boss_details(label: String) -> void:
	var button = details_button(session.interface)
	check(button != null, label + " has real expand/collapse button")
	if button == null: return
	if session.interface.details_open: button.pressed.emit()
	session._refresh_interface()
	var compact: String = session.interface.objective.text
	var before: Dictionary = session.store.snapshot()
	button.pressed.emit()
	session._refresh_interface()
	var expanded: String = session.interface.objective.text
	check(session.interface.details_open and expanded.begins_with(compact) and expanded.length() > compact.length(), label + " expands tactical help by button", {"compact":compact, "expanded":expanded})
	button.pressed.emit()
	session._refresh_interface()
	check(not session.interface.details_open and session.interface.objective.text == compact, label + " collapses back to exact compact objective")
	check(session.store.snapshot() == before, label + " toggling is presentation only")

func _run() -> void:
	source_hashes = tree_hashes("res://data/v3")
	default_hashes = tree_hashes("user://profiles_v3/default")
	session = Main.instantiate()
	root.add_child(session)
	check(session.profile_ready and session.start_flight("solo"), "real main scene starts isolated solo session")
	if not session.active:
		finish()
		return
	session.set_process(false)
	session.set_physics_process(false)
	session.inputs.set_process(false)
	session.inputs.set_physics_process(false)
	session.inputs.legacy.set_process(false)
	session.interface.set_process(false)
	session.network.event_received.connect(func(event):
		if event.get("kind", "") == "notice": notices.append(event.duplicate(true)))
	session.network.action_received.connect(func(peer, verb, payload): intents.append({"peer":peer,"verb":verb,"payload":payload.duplicate(true)}))
	check(session.network.mode == "solo" and session.network.guests.is_empty() and session.store.root_path == "user://profiles_v3/" + profile, "no UDP peers and only explicitly isolated QA store")
	await _test_briefing()
	await _test_selection_and_distance()
	await _test_whale_feedback()
	await _test_fantasy()
	finish()

func _test_briefing() -> void:
	await place(Vector3(-18, 2.5, 35))
	check(session.story.state.revision == 0, "fresh profile begins before rescue briefing")
	key(KEY_G)
	check(session.story.state.revision == 1 and session.interface.radio.visible, "actual nearby G commits rescue briefing and starts dialogue")
	saved_brief = session.store.snapshot()
	var anchor: Dictionary = session.story.display_anchor()
	check(anchor.get("requested_id", "") == "I1:rescue_channel" and anchor.get("anchor_id", "") == "I1:rescue_pocket", "rescue channel displays stranded maintenance drone destination", {"anchor":str(anchor)})
	check(anchor.get("position", Vector3.INF).is_equal_approx(session.story.rescue_drone.global_position), "displayed destination matches real maintenance-drone position")
	session.story.refresh(session.players[1].global_position)
	session.flight_camera.snap(session.players[1].global_position)
	session._refresh_interface()
	check(session.story.visuals["I1:rescue_pocket"].is_visible_in_tree(), "real rescue destination 3D marker becomes visible")
	check(session.interface.objective_marker.active and session.interface.objective_marker.visible and session.interface.objective_marker.destination == anchor.position, "HUD objective cue projects the same destination")
	for i in range(4):
		session.story.refresh(session.players[1].global_position)
		session._refresh_interface()
		session.story.observe(0.3)
	check(session.story.state.revision == 1 and session.store.snapshot() == saved_brief, "display refresh and closed-route observation cannot pre-complete rescue")
	check(session.world.gate_fraction < 0.95, "channel still physically closed after briefing display")
	var reader = Store.new(session.store.root_path)
	check(reader.load_profile().ok and reader.snapshot().world.actions.opening.revision == 1, "independent Store reload sees only genuinely completed briefing")
	while session.interface.radio.visible: key(KEY_G)
	check(session.story.state.revision == 1, "G advances dialogue without completing rescue route")

func _test_selection_and_distance() -> void:
	var relay: Vector3 = session.entities["I1:relay"].position
	await place(relay + Vector3(3, 4, 12))
	session.locks[1] = "I1:relay"
	session._refresh_interface()
	check(visible_suggestions() == ["charge", "takeover"], "real relay exposes only its two relevant ability buttons", {"ids":visible_suggestions()})
	for button in session.interface.suggestion_buttons:
		if not button.visible: continue
		var expected: String = button.get_meta("ability")
		var before_entities = session.entities.duplicate(true)
		var before_stats = session.stats.duplicate(true)
		var before_intents = intents.size()
		var before_store = session.store.snapshot()
		button.pressed.emit()
		session._refresh_interface()
		check(session.selected_ability == expected and session.interface.ABILITIES[session.interface.selected] == expected, "suggestion button really selects " + expected)
		check(session.locks.get(1) == "I1:relay", "suggestion " + expected + " preserves original target lock")
		check(session.entities == before_entities and session.stats == before_stats and intents.size() == before_intents and session.store.snapshot() == before_store, "suggestion " + expected + " cannot cast, spend or save")
	key(KEY_6)
	session._refresh_interface()
	check(session.interface.ability_description.text.contains("13.0m") and session.interface.ability_description.text.contains("1.0m"), "actual UI computes 13m spatial distance and 1m approach, not horizontal sqrt153", {"description":session.interface.ability_description.text})
	check(session.interface.ability_title.text.contains("12m") and float(Rules.DEFINITIONS.charge.range) == 12.0, "actual selected charge UI displays production 12m limit")
	check(session.interface.target_marker.caption.text.contains("13.0m") and session.interface.target_marker.caption.text.contains("低 4.0m"), "target label includes actual signed vertical offset", {"caption":session.interface.target_marker.caption.text})
	await place(relay + Vector3(3, 0, 12))
	session._refresh_interface()
	check(session.interface.ability_description.text.contains("12.4m"), "changing only height updates displayed Euclidean distance")
	for code in [KEY_1, KEY_7, KEY_8, KEY_9, KEY_0]:
		key(code)
		session._refresh_interface()
		check(not session.interface.ability_description.text.contains("X ") and not session.interface.target_info.text.contains("X 反向"), "selected " + session.selected_ability + " never invents an inverse in current-ability or target UI", {"bottom":session.interface.ability_description.text,"target":session.interface.target_info.text})
	await place(Vector3(-35, 10, 35))
	session.players[1].command = {"planar":Vector3.RIGHT}
	session.cooldowns[1] = 0.0
	key(KEY_1)
	session._refresh_interface()
	var from: Vector3 = session.players[1].global_position
	var energy: float = session.entities["player:1"].energy
	var casts: int = session.stats.abilities
	key(KEY_F)
	var sent: Dictionary = intents.back()
	check(sent.verb == "ability" and sent.payload.ability == "blink" and sent.payload.point.is_equal_approx(from + Vector3.RIGHT * 6), "F blink submits actual forward 6m point, independent of distant locked relay", {"intent":str(sent)})
	check(session.players[1].global_position.is_equal_approx(from + Vector3.RIGHT * 6) and session.stats.abilities == casts + 1, "real clear-path blink moves the physics body exactly 6m")
	check(is_equal_approx(session.entities["player:1"].energy, energy - Rules.DEFINITIONS.blink.energy) and session.locks[1] == "I1:relay", "real blink consumes rules energy and preserves lock")
	session.cooldowns[1] = 0.0
	from = session.players[1].global_position
	key(KEY_X)
	check(intents.back().payload.mode == "" and intents.back().payload.point.is_equal_approx(from + Vector3.RIGHT * 6) and session.players[1].global_position.is_equal_approx(from + Vector3.RIGHT * 6), "actual X blink retains same forward behavior, no invented reverse")
	var saved = session.store.snapshot()
	session.locks[1] = "unknown:missing"
	session._refresh_interface()
	check(visible_suggestions().is_empty() and not session.interface.target_marker.has_target, "unknown locked target clears suggestions and selected-target cue safely")
	check(session.story.target_anchor("unknown:missing").is_empty() and session.store.snapshot() == saved, "unknown display lookup is empty and read-only")
	var original = session.story.state.duplicate(true)
	session.story.state = {"revision":99999}
	session.story.serial += 1
	session._refresh_interface()
	check(session.story.display_anchor().is_empty() and not session.interface.objective_marker.active, "unsupported objective state leaves no stale destination cue")
	session.story.state = original
	session.story.serial += 1
	session._refresh_interface()

func _test_whale_feedback() -> void:
	# Combat activation is a named development fixture; it neither grants the
	# campaign briefing nor claims the preceding actions were played.
	session._start_boss(false)
	check(session.boss_active and not session.boss_campaign, "explicit development whale fixture has no campaign eligibility")
	session._physics_process(0.0) # Warm input context before mapped fire.
	var point: Vector3 = session.entities["boss:port"].position
	session.locks[1] = "boss:port"
	await place(point + Vector3.UP * 40)
	await refusal("whale beyond actual 36m", "out_of_range")
	var notices_before = notices.size()
	await create_timer(2.25).timeout
	fire_input()
	check(notices.size() == notices_before + 1, "same-code shooting notice naturally reappears after throttle interval")
	await place(point + Vector3.UP * 5)
	check(not session._line_clear(session.players[1].global_position, point, session.players[1].get_rid(), "boss:port"), "closed imported whale armor truly blocks ray")
	await refusal("closed whale armor", "occluded")
	var events: Array = session.encounter.advance(2.7)
	session._handle_boss_events(events)
	session._sync_boss_entities()
	await settle()
	check(session.encounter.get_state().nodes_open and session._line_clear(session.players[1].global_position, point, session.players[1].get_rid(), "boss:port"), "actual open armor provides clear positive-control shot path")
	# Test-owned blocker, using actual PhysicsServer geometry, separates world
	# occlusion from boss armor. No mocked LOS or production asset mutation.
	var blocker = StaticBody3D.new()
	blocker.collision_layer = 1
	blocker.collision_mask = 0
	var shape_node = CollisionShape3D.new()
	var box = BoxShape3D.new()
	box.size = Vector3(2, 0.25, 2)
	shape_node.shape = box
	blocker.add_child(shape_node)
	session.world.add_child(blocker)
	blocker.global_position = point + Vector3.UP * 2.5
	await settle()
	check(not session._line_clear(session.players[1].global_position, point, session.players[1].get_rid(), "boss:port"), "test obstacle genuinely intersects open-pod ray")
	await create_timer(1.3).timeout # Same occlusion code must age its full 2.2s.
	await refusal("open pod behind real obstacle", "occluded")
	blocker.free()
	await settle()
	var before_health: float = session.encounter.get_state().nodes.port.health
	var before_shots: int = session.stats.shots
	var before_beams = current_beams()
	fire_input()
	check(session.stats.shots == before_shots + 1 and session.encounter.get_state().nodes.port.health == before_health - 9 and current_beams() == before_beams + 1, "removing obstacle permits real shot, beam and exactly9 damage")
	toggle_boss_details("whale")

func _test_fantasy() -> void:
	check(session._load_region("F1"), "actual F1 scene loads for isolated display fixtures")
	await place(Vector3(-24, 5.2, 29))
	# Explicit reducer-only first12 prerequisite fixture for F1 light objective.
	# It is not submitted to Store and cannot be presented as a full playthrough.
	var seeded: Dictionary = session.story.director.default_state()
	for row in StoryFixtures.LEGACY_EVENTS.slice(0, 12):
		var result: Dictionary = session.story.director.apply_event(seeded, {"id":"guidance_fixture:" + str(row[0]),"type":row[1],"target_id":row[2],"option":row[3]}, {"is_authority":true,"validated":true,"region_id":str(row[0]).get_slice(":",0)})
		check(result.get("ok", false), "explicit F1 prerequisite reducer fixture " + str(row[0]))
		if not result.get("ok", false): return
		seeded = result.state
	session.story.state = seeded
	session.story.serial += 1
	var persisted = session.store.snapshot()
	var anchor: Dictionary = session.story.display_anchor()
	check(anchor.get("anchor_id", "") == "F1:mirror" and anchor.get("position", Vector3.INF) == session.world.objects["F1:mirror"].global_position, "F1 light fact points to live physical mirror rather than nonexistent fact coordinate", {"anchor":str(anchor)})
	session.story.refresh(session.players[1].global_position)
	session._refresh_interface()
	check(session.interface.objective_marker.active and session.interface.objective_marker.destination == anchor.position, "F1 fact produces live HUD destination cue")
	check(session.story.state.revision == 12 and session.store.snapshot() == persisted, "F1 display does not align light or save prerequisite fixture")
	for id in ["F1:mirror", "F1:growth"]:
		session.locks[1] = id
		session._refresh_interface()
		var expected: String = "light" if id == "F1:mirror" else "growth"
		check(visible_suggestions() == [expected], "real " + id + " only suggests appropriate tool")
		var before = session.entities.duplicate(true)
		var cast_count: int = session.stats.abilities
		session.interface.suggestion_buttons[0].pressed.emit()
		session._refresh_interface()
		check(session.selected_ability == expected and session.locks[1] == id and session.entities == before and session.stats.abilities == cast_count, "real " + id + " suggestion selects without operating mechanism")
	check(session.entities["F1:growth"].environment_light < 1 and session.entities["F1:growth"].growth < 1, "suggestions do not solve physical light/growth mechanisms")
	await _test_fantasy_temperature_feedback()
	# The retry point is deliberately outside the active arena; it must not
	# create an empty roster. Move into actual combat space before activation.
	await place(session.world.crown_arena.retry_position(0))
	check(not session.crown.start(false) and not session.boss_active, "safe crown retry entrance does not activate an empty combat roster")
	var core: Vector3 = session.world.crown_arena.core_position()
	await place(core + Vector3(0, 0, 7))
	check(session.world.crown_arena.in_combat_space(session.players[1].global_position) and session.crown.start(false), "actual crown development fixture starts after entering real combat space", {"position":str(session.players[1].global_position)})
	if not session.crown.active(): return
	session.locks[1] = "boss:crown_core"
	await settle()
	check(not session.crown.encounter.get_state().core_open, "crown starts physically closed")
	await refusal("closed crown armor", "crown_armored")
	toggle_boss_details("crown")
	_test_target_cycle()
	check(not session.store.snapshot().world.flags.get("campaign_crown_v1", false) and not session.store.snapshot().world.flags.get("campaign_whale_v1", false), "feedback fixtures never award campaign boss victory")

func _test_fantasy_temperature_feedback() -> void:
	# Actual heat casts use the authored thermal target and production host LOS.
	# Growth temperatures/light below are explicit UI/rule boundary fixtures:
	# authored F1:growth has no thermal tag and cannot be directly heated.
	var before_entities: Dictionary = session.entities.duplicate(true)
	var before_store: Dictionary = session.store.snapshot()
	var before_story: Dictionary = session.story.state.duplicate(true)
	var before_at: Vector3 = session.players[1].global_position
	var before_lock: String = session.locks[1]
	var before_selected: int = session.interface.selected
	var before_details: bool = session.interface.details_open
	var before_cooldown: float = session.cooldowns.get(1, 0.0)
	var button = details_button(session.interface)
	check(button != null, "F1 temperature feedback has real details control")
	if button == null: return
	if session.interface.details_open: button.pressed.emit()
	var thermal: Dictionary = session.entities["F1:thermal"]
	await place(thermal.position + Vector3(0, 3, 4))
	session.locks[1] = "F1:thermal"
	key(KEY_5)
	session._refresh_interface()
	check(thermal.temperature == 20.0 and session.interface.target_info.text.contains("温度 20°"), "compact selected heat retains real initial thermal reading", {"target":session.interface.target_info.text})
	var casts: int = session.stats.abilities
	var energy: float = session.entities["player:1"].energy
	# Session processing is disabled by this test. Reset only pacing between two
	# real F intents, not target state, LOS, rules results or energy expenditure.
	for i in range(2):
		session.cooldowns[1] = 0.0
		key(KEY_F)
	session._refresh_interface()
	check(session.stats.abilities == casts + 2 and session.entities["F1:thermal"].temperature == 70.0 and is_equal_approx(session.entities["player:1"].energy, energy - 16.0), "two real host heat actions reach70 and spend16 energy", {"temperature":session.entities["F1:thermal"].temperature,"new_casts":session.stats.abilities - casts,"message":session.interface.message.text})
	check(session.interface.target_info.visible and session.interface.target_info.text.contains("温度 70°"), "compact heat reflects actual70 rather than hiding action result", {"target":session.interface.target_info.text})
	button.pressed.emit()
	session._refresh_interface()
	check(session.interface.details_open and session.interface.target_info.text.contains("温度 70°"), "expanded thermal readout agrees with compact actual result")
	button.pressed.emit()
	await place(session.entities["F1:growth"].position + Vector3(0, 0, 3))
	session.locks[1] = "F1:growth"
	key(KEY_7)
	var growth: Dictionary = session.entities["F1:growth"]
	check("thermal" not in growth.tags, "authored F1 root fixture does not silently acquire heat support")
	growth.environment_light = 1.0
	growth.growth = 0.0
	var validation_context = {"sender_id":"1", "line_of_sight":true}
	# This context explicitly isolates temperature from physical light/LOS. It
	# is never submitted through an action and does not claim a solved light ray.
	var growth_intent = {"actor_id":"player:1", "target_id":"F1:growth", "ability":"growth"}
	var heat_intent = {"actor_id":"player:1", "target_id":"F1:growth", "ability":"heat"}
	for sample in [{"temperature":0,"code":"valid","status":""}, {"temperature":60,"code":"valid","status":""}, {"temperature":-1,"code":"growth_temperature","status":"过冷"}, {"temperature":61,"code":"growth_temperature","status":"过热"}]:
		growth.temperature = float(sample.temperature)
		var validated: Dictionary = session.rules.validate(growth_intent, session.entities, validation_context)
		session._refresh_interface()
		var compact: String = session.interface.target_info.text
		check(str(validated.get("code", "")) == sample.code, "production growth rule temperature boundary " + str(sample.temperature), {"result":validated})
		if str(sample.status).is_empty():
			check(compact.contains("已获得光照") and compact.contains("生长") and not compact.contains("过冷") and not compact.contains("过热"), "compact valid boundary retains light/growth without false thermal warning " + str(sample.temperature), {"target":compact})
		else:
			check(compact.contains(sample.status) and compact.contains("%d°" % sample.temperature) and compact.contains("不能直接调温") and not compact.contains("5 热量") and not compact.contains("X 降温") and not compact.contains("F 加热"), "compact unsupported root explains thermal block without unavailable remedy " + str(sample.temperature), {"target":compact})
		button.pressed.emit()
		session._refresh_interface()
		check(session.interface.details_open and session.interface.target_info.text.contains("温度 %d°" % sample.temperature) and session.interface.target_info.text.contains("已获得光照"), "expanded growth preserves exact boundary reading and light " + str(sample.temperature), {"target":session.interface.target_info.text})
		button.pressed.emit()
	check(session.rules.validate(heat_intent, session.entities, validation_context).get("code") == "unsupported_target", "real nonthermal root cannot execute suggested heat")
	# Explicit synthetic support-matrix fixture only; this is not an authored
	# F1 target change. It checks the alternative UI branch for a thermal plant.
	growth.tags = growth.tags.duplicate()
	growth.tags.append("thermal")
	for sample in [{"temperature":-1,"remedy":"F 加热"}, {"temperature":61,"remedy":"X 降温"}]:
		growth.temperature = float(sample.temperature)
		session._refresh_interface()
		check(session.rules.validate(heat_intent, session.entities, validation_context).get("ok", false) and session.interface.target_info.text.contains(sample.remedy) and not session.interface.target_info.text.contains("不能直接调温"), "explicit thermal plant fixture exposes supported remedy " + str(sample.temperature), {"target":session.interface.target_info.text})
	# Restore all modified entity dictionaries before the existing Crown fixture.
	for id in ["F1:thermal", "F1:growth", "player:1"]: session.entities[id] = before_entities[id].duplicate(true)
	await place(before_at)
	session.cooldowns[1] = before_cooldown
	session.locks[1] = before_lock
	session.interface.select_ability(before_selected)
	if session.interface.details_open != before_details: button.pressed.emit()
	session._refresh_interface()
	check(session.entities == before_entities and session.players[1].global_position == before_at, "thermal fixtures fully restore entities and pilot pose before Crown")
	check(session.cooldowns[1] == before_cooldown and session.locks[1] == before_lock and session.interface.selected == before_selected and session.interface.details_open == before_details, "thermal fixtures restore cooldown lock tool and details state")
	check(session.store.snapshot() == before_store and session.story.state == before_story, "thermal feedback and boundary fixtures never save or advance opening objectives")

func _test_target_cycle() -> void:
	# Check the set of reachable real targets, independently of the ranking
	# algorithm. No synthetic entities and no expected copy of its sort weights.
	var expected: Array = []
	for id in session.entities:
		if not str(id).begins_with("player:") and session.players[1].global_position.distance_to(session.entities[id].position) <= 45.0: expected.append(str(id))
	expected.sort()
	check(expected.size() > 2 and "boss:crown_core" in expected, "cycle fixture includes actual weapon weakpoint and several nearby entities", {"eligible":expected})
	if expected.is_empty(): return
	var before_entities = session.entities.duplicate(true)
	var before_store = session.store.snapshot()
	var before_casts: int = session.stats.abilities
	var before_rejects: int = session.stats.rejected_abilities
	var before_shots: int = session.stats.shots
	var old_camera: Transform3D = session.camera.transform
	var old_size: float = session.camera.size
	var original_lock: String = session.locks[1]
	key(KEY_5) # A host-compatible ability must not replace a weapon target.
	session.flight_camera.snap(session.players[1].global_position)
	session._refresh_interface()
	check(session.selected_ability == "heat" and session.locks[1] == original_lock, "tool selection and camera/HUD refresh do not auto-replace weapon lock")
	var before_intents: int = intents.size()
	var first: Array = []
	for i in range(expected.size()):
		key(KEY_TAB)
		first.append(str(session.locks.get(1, "")))
		# Recommendations are refreshed during cycling just as they are in play.
		session._refresh_interface()
	var actual = first.duplicate()
	actual.sort()
	check(actual == expected, "one explicit Tab cycle reaches every45m entity exactly once including shooting target", {"expected":expected,"sequence":first})
	var second: Array = []
	for i in range(expected.size()):
		key(KEY_TAB)
		second.append(str(session.locks.get(1, "")))
		session._refresh_interface()
	check(second == first, "unchanged spatial context yields the same complete cycle on second lap", {"first":first,"second":second})
	key(KEY_TAB)
	check(session.locks[1] == first[0], "next explicit Tab wraps to first target without starvation")
	var only_locks = true
	for action in intents.slice(before_intents): only_locks = only_locks and action.verb == "lock" and str(action.payload.get("target_id", "")) in expected
	check(only_locks and intents.size() - before_intents == expected.size() * 2 + 1, "each Tab issues one real lock intent and no ability intent")
	var locked: String = session.locks[1]
	key(KEY_1)
	session.camera.size = old_size * 0.7
	for i in range(3): session._refresh_interface()
	check(session.locks[1] == locked, "changed tool and screen framing without Tab never change current lock")
	var reframed: Array = []
	for i in range(expected.size()):
		key(KEY_TAB)
		reframed.append(str(session.locks.get(1, "")))
		session._refresh_interface()
	var reframed_set = reframed.duplicate()
	reframed_set.sort()
	check(reframed_set == expected, "reordered screen/tool preferences still retain complete target reachability", {"sequence":reframed})
	check(session.entities == before_entities and session.store.snapshot() == before_store, "cycling and target recommendations leave all entities and durable state unchanged")
	check(session.stats.abilities == before_casts and session.stats.rejected_abilities == before_rejects and session.stats.shots == before_shots, "lock navigation never casts, shoots or raises ability rejection")
	session.camera.transform = old_camera
	session.camera.size = old_size

func finish() -> void:
	check(tree_hashes("res://data/v3") == source_hashes, "all authored data bytes remain unchanged")
	check(tree_hashes("user://profiles_v3/default") == default_hashes, "normal default profile remains byte-identical or absent")
	if is_instance_valid(session):
		var reader = Store.new(session.store.root_path)
		check(reader.load_profile().ok and reader.snapshot() == session.store.snapshot(), "isolated final Store reload agrees exactly")
	var result = {"passed":failures.is_empty(),"checks":checks,"failures":failures,"profile":profile,"data_files":source_hashes.size(),"limits":["Headless UI handler, real Session/PhysicsServer/Store regression; no rendered screen or human usability evidence.","Scripted body placement; explicit development boss starts; first12 F1 prerequisites are an in-memory reducer fixture, not played or saved completion.","Mapped fire enters PilotInput and host physics with delta0 and deliberately reset cooldown to isolate refusal feedback; not natural combat timing.","Solo OfflineMultiplayerPeer only; no UDP or performance measurement."]}
	var path = "res://artifacts/v3/opening-guidance-session-" + profile + ".json"
	var file = FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		push_error("Cannot write guidance test report: " + error_string(FileAccess.get_open_error()))
		quit(2)
		return
	file.store_string(JSON.stringify(result, "\t"))
	file.flush()
	var write_ok = file.get_error() == OK
	file.close()
	print("OPENING_GUIDANCE_SESSION checks=%d failures=%d report=%s" % [checks.size(), failures.size(), path])
	Input.action_release("flight_fire")
	Engine.time_scale = 1.0
	if is_instance_valid(session):
		session.network.close()
		session.free()
	quit(0 if failures.is_empty() and write_ok else 1)
