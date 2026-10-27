extends SceneTree
## Pure state/data regression. Root runs this serially; no scene or save IO fixture.

const Ecology = preload("res://scripts/v3/ecology/twin_ecology_state.gd")
var checks := 0
var failures: Array = []

func _init() -> void:
	_test_routes_and_copies()
	_test_time_authority_and_context()
	_test_supply_policies()
	_test_hazards_and_weather()
	_test_determinism_and_restore()
	_test_invalid_snapshots_and_definitions()
	var sample = _new_state(2718)
	_run_for(sample, 100.0, "I1")
	print("V3_ECOLOGY_STATE_TESTS " + JSON.stringify({"checks":checks, "failures":failures,
		"actors":sample.get_actors().size(), "snapshot_bytes":JSON.stringify(sample.snapshot(), "", true, true).to_utf8_buffer().size(),
		"scope":"pure fixed-step ecology, route data and JSON snapshot replay; no engine collision corridor check, facilities integration, LAN, NPC visuals, performance or human fun evidence"}))
	quit(0 if failures.is_empty() else 1)

func _check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures.append(label)
		push_error(label)

func _new_state(seed: int = 817):
	var state = Ecology.new()
	_check(state.load_routes(Ecology.DEFAULT_PATH, seed).ok, "authored ecology loads")
	return state

func _run_for(state, seconds: float, active: String = "I1", context: Dictionary = {}) -> Array:
	var events: Array = []
	var remaining := seconds
	while remaining > 0.000001:
		var step := minf(10.0, remaining)
		var result: Dictionary = state.advance(step, active, context)
		if not result.ok:
			_check(false, "bounded helper advance accepted: " + str(result.code))
			break
		events.append_array(result.events)
		remaining -= step
	return events

func _event_count(events: Array, type: String, actor: String = "") -> int:
	var total := 0
	for event in events:
		if event.type == type and (actor.is_empty() or event.actor_id == actor): total += 1
	return total

func _at(actor: Dictionary) -> Vector3:
	return Vector3(float(actor.position[0]), float(actor.position[1]), float(actor.position[2]))

func _test_routes_and_copies() -> void:
	var state = _new_state()
	_check(state.get_actors("I1").size() == 3 and state.get_actors("F1").size() == 2, "three port workers and two forest actors")
	_check(state.get_actor("missing").is_empty() and state.get_actors("missing").is_empty(), "unknown actor access is empty")
	var original: Dictionary = state.snapshot()
	var actor: Dictionary = state.get_actor("I1:inspection_01")
	_check(actor.purpose.length() > 10 and actor.role == "inspection", "actor has observable purpose and role")
	actor.position[0] = 999
	actor.phase = "forged"
	var list: Array = state.get_actors()
	list[0].position[1] = 999
	var copy: Dictionary = state.snapshot()
	copy.contexts.I1.danger_nodes.append("junction")
	copy.actors.clear()
	var definition: Dictionary = state.definitions()
	definition.actors.clear()
	_check(state.snapshot() == original and state.definitions().actors.size() == 5, "all actor/snapshot/definition getters isolate nested values")
	var input := {"I1":{"danger_nodes":["junction"]}}
	state.advance(0.25, "I1", input)
	input.I1.danger_nodes.clear()
	_check(state.snapshot().contexts.I1.danger_nodes == ["junction"], "host context is copied instead of aliased")
	for item in state.definitions().regions:
		if item.id != "F1": continue
		for node in item.nodes: _check(float(node.position[1]) >= 12.0, "F1 route stays at least 12m high: " + str(node.id))
	var events := _run_for(state, 240.0)
	_check(_event_count(events, "repair_progress", "I1:repair_01") > 0, "repair work emits facility-facing progress")
	_check(_event_count(events, "transport_arrival", "I1:water_01") > 0, "water delivery follows real route and work")
	_check(_event_count(events, "pollination_progress", "F1:pollinator_01") > 0, "unseen forest remains productive")
	var seen: Dictionary = {}
	var unique := true
	for event in events:
		if seen.has(event.id): unique = false
		seen[event.id] = true
	_check(not events.is_empty() and events[0].event_id == events[0].id and events[0].kind == events[0].type and events[0].region == events[0].region_id and int(events[0].serial) > 0, "facility event canonical fields and compatibility aliases agree")
	_check(unique and not events.is_empty(), "every work event has a unique stable serial id")
	var after_work: Dictionary = state.snapshot()
	if not events.is_empty(): events[0].position[0] = 999
	_check(state.snapshot() == after_work, "returned events do not alias actor positions")
	_check(state.get_actors().size() == 5, "long advance never spawns extra actors")

func _test_time_authority_and_context() -> void:
	var state = _new_state()
	_check(state.elapsed_seconds() == 0.0, "initial explicit simulation time is zero")
	state.advance(0.375, "I1")
	_check(state.elapsed_seconds() == 0.375, "elapsed time includes persisted fractional step without snapshot copies")
	var before: Dictionary = state.snapshot()
	_check(state.advance(0.0, "F1", {"I1":{"powered":false}}).code == "paused", "zero delta reports pause")
	_check(state.snapshot() == before, "pause preserves context/RNG/fraction/actors")
	_check(state.advance(2.0, "I1", {"I1":{"powered":false}}, false).code == "authority_required", "guest advance rejected")
	_check(state.snapshot() == before, "guest rejection has no mutation")
	for delta in [-1.0, 10.001, INF, NAN]:
		_check(state.advance(delta, "I1").code == "invalid_delta", "invalid delta rejected without clamping")
		_check(state.snapshot() == before, "invalid delta cannot mutate state")
	_check(state.advance(1.0, "UNKNOWN").code == "unknown_active_region" and state.snapshot() == before, "unknown active region rejected atomically")
	var result: Dictionary = state.advance(0.625, "I1", {"UNKNOWN":{}, "I1":{"weather":"lava", "powered":"yes", "danger_nodes":["missing"], "magic":5}})
	_check(result.ok and result.warnings.size() == 5 and result.ticks == 1, "bad context fields report bounded warnings without crashing")
	_check(state.snapshot().contexts.I1.weather == "clear" and state.snapshot().contexts.I1.powered, "unknown values preserve prior valid context")
	_check(state.snapshot().pending_usec == 0 and state.snapshot().tick == 1, "fractional deltas accumulate to one fixed step")
	var far_before: Dictionary = state.get_actor("F1:forest_01")
	state.advance(10.0, "I1")
	_check(_at(state.get_actor("F1:forest_01")).distance_to(_at(far_before)) > 1.0, "offscreen region moves while port is active")

func _test_supply_policies() -> void:
	var state = _new_state()
	var inspection: Dictionary = state.get_actor("I1:inspection_01")
	var events := _run_for(state, 10.0, "I1", {"I1":{"powered":false}, "F1":{"powered":false}})
	_check(_at(inspection) == _at(state.get_actor(inspection.id)), "main-power inspection waits in place")
	_check(_event_count(events, "repair_progress", "I1:repair_01") == 1, "maintenance reserve allows useful repair during blackout")
	_check(state.get_actor("I1:repair_01").reserve_remaining == 35.0, "backup maintenance charge persists and drains per explicit second")
	_check(_event_count(events, "pollination_progress") > 0, "living pollinator ignores industrial power loss")
	_check(state.get_actor("I1:water_01").reason == "supply_unavailable", "empty carrier waits at unpowered source")
	_check(_event_count(events, "transport_arrival") == 0, "unloaded carrier cannot create a delivery")
	_run_for(state, 40.0)
	_check(state.get_actor("I1:repair_01").reason == "reserve_depleted", "repair reserve is finite")
	_check(state.get_actor("F1:forest_01").reason == "reserve_depleted", "forest maintenance has its own finite reserve")
	state.advance(1.0, "I1", {"I1":{"maintenance_powered":true}})
	_check(state.get_actor("I1:repair_01").reserve_remaining == 2.0, "restored maintenance supply recharges gradually")
	_check(state.get_actor("I1:inspection_01").reason == "power_unavailable", "maintenance circuit does not silently energize inspection supply")
	state.advance(1.0, "I1", {"I1":{"powered":false,"maintenance_powered":true}})
	_check(state.snapshot().contexts.I1.maintenance_powered and not state.snapshot().contexts.I1.supply_powered, "explicit circuit overrides overall power in the same packet")
	var carrier = _new_state(9)
	_run_for(carrier, 7.0)
	_check(carrier.get_actor("I1:water_01").cargo, "source work actually loads one cargo")
	var arrivals := _run_for(carrier, 130.0, "F1", {"I1":{"supply_powered":false}})
	_check(_event_count(arrivals, "transport_arrival", "I1:water_01") == 1, "loaded carrier completes exactly one trip during supply outage")
	var stopped: Dictionary = carrier.get_actor("I1:water_01")
	_check(stopped.node == "water" and stopped.next_node == "" and stopped.reason == "supply_unavailable" and not stopped.cargo, "carrier returns to source and waits without teleporting or refilling")
	_run_for(carrier, 8.0, "I1", {"I1":{"supply_powered":true}})
	_check(carrier.get_actor("I1:water_01").cargo, "supply recovery resumes the existing actor and loads next trip")

func _test_hazards_and_weather() -> void:
	var state = _new_state()
	state.advance(1.0, "I1", {"I1":{"danger_nodes":["junction"]}})
	var actor: Dictionary = state.get_actor("I1:inspection_01")
	_check(actor.next_node == "shelter" and actor.phase == "detouring", "blocked junction selects an authored alternate route")
	var events := _run_for(state, 100.0)
	_check(_event_count(events, "inspection_complete", actor.id) > 0, "detour still reaches real work destination")
	state.advance(1.0, "I1", {"I1":{"danger_nodes":[]}})
	_check(state.snapshot().contexts.I1.danger_nodes.is_empty(), "cleared hazard restores graph access")
	var retreat = _new_state()
	retreat.advance(2.0, "I1")
	var before: Dictionary = retreat.get_actor("I1:inspection_01")
	retreat.advance(1.0, "I1", {"I1":{"danger_nodes":["junction"]}})
	actor = retreat.get_actor(before.id)
	_check(actor.next_node == "dock" and actor.reason == "retreat_from_danger", "hazard introduced mid-edge reverses on that edge")
	_check(_at(before).distance_to(_at(actor)) <= float(actor.speed) + 0.001, "retreat obeys one-second travel distance rather than teleporting")
	before = actor
	retreat.advance(1.0, "I1", {"I1":{"danger_nodes":["dock","junction"]}})
	actor = retreat.get_actor(before.id)
	_check(_at(actor) == _at(before) and actor.reason == "both_edge_ends_dangerous", "no safe edge endpoint means hold, never enter forbidden point")
	retreat.advance(2.0, "I1", {"I1":{"danger_nodes":[]}})
	_check(_at(retreat.get_actor(before.id)) != _at(before), "same actor resumes from retained edge progress after danger clears")
	var storm = _new_state()
	var storm_events := _run_for(storm, 100.0, "I1", {"I1":{"powered":false,"weather":"storm"}, "F1":{"powered":false,"weather":"storm"}})
	var sheltered := true
	for item in storm.get_actors():
		if item.phase != "sheltered": sheltered = false
	_check(sheltered and storm_events.is_empty(), "storm evacuates all five even with facility power down, with no work while sheltered")
	var rain = _new_state()
	_run_for(rain, 100.0, "F1", {"F1":{"weather":"rain"}})
	_check(rain.get_actor("F1:pollinator_01").phase == "sheltered", "rain shelters delicate pollinator")
	_check(rain.get_actor("F1:forest_01").steps_completed > 0, "forest machine continues rain-tolerant work")
	var recovered := _run_for(rain, 100.0, "F1", {"F1":{"weather":"clear"}})
	_check(_event_count(recovered, "pollination_progress") > 0, "clear weather resumes pollination without actor respawn")

func _test_determinism_and_restore() -> void:
	var first = _new_state(445)
	var second = _new_state(445)
	var first_events: Array = []
	var second_events: Array = []
	for tick in range(160):
		first_events.append_array(first.advance(0.25, "I1").events)
	for tick in range(40):
		second_events.append_array(second.advance(1.0, "F1").events)
	_check(first.snapshot() == second.snapshot() and first_events == second_events, "same seed and quantized elapsed time are independent of view region and frame partition")
	_check(first.snapshot().rng_state != 445, "work cadence consumes persistent seeded RNG rather than global random")
	first.advance(0.375, "I1", {"I1":{"maintenance_powered":false}, "F1":{"weather":"rain"}})
	var saved: Dictionary = JSON.parse_string(JSON.stringify(first.snapshot(), "", true, true))
	var restored = _new_state(999)
	_check(restored.restore(saved).ok, "JSON roundtrip restores geometry/phase/RNG/context/cargo/reserve")
	_check(restored.elapsed_seconds() == first.elapsed_seconds(), "elapsed time restores the same integer and fractional clock")
	_check(typeof(restored.snapshot().schema_version) == TYPE_INT, "JSON-decoded schema version is normalized to the integer state contract")
	if restored.snapshot() != first.snapshot():
		print("V3_ECOLOGY_IMMEDIATE_DIFF " + JSON.stringify(_snapshot_differences(first.snapshot(), restored.snapshot())))
	_check(restored.snapshot() == first.snapshot(), "restore is exactly equal immediately, before any further simulation")
	saved.actors.clear()
	_check(restored.get_actors().size() == 5, "restore also takes a deep copy")
	var uninterrupted := _run_for(first, 143.625, "I1")
	var resumed := _run_for(restored, 143.625, "F1")
	if first.snapshot() != restored.snapshot():
		print("V3_ECOLOGY_SNAPSHOT_DIFF " + JSON.stringify(_snapshot_differences(first.snapshot(), restored.snapshot())))
	_check(first.snapshot() == restored.snapshot(), "save/reload continues exact persistent state including unseen region")
	_check(uninterrupted == resumed, "replayed explicit deltas emit identical event IDs and payloads")
	_check(first.validate_snapshot(first.snapshot()).ok, "own long-running snapshot satisfies integrity contract")

func _test_invalid_snapshots_and_definitions() -> void:
	var state = _new_state()
	_run_for(state, 19.375)
	var before: Dictionary = state.snapshot()
	var bad: Dictionary = before.duplicate(true)
	bad.actors["I1:water_01"].position[0] += 1.0
	_check(not state.restore(bad).ok and state.snapshot() == before, "off-route forged position rejected atomically")
	bad = before.duplicate(true)
	bad.actors["extra"] = {}
	_check(not state.restore(bad).ok, "extra persisted actor rejected")
	bad = before.duplicate(true)
	bad.actors.erase("F1:forest_01")
	_check(not state.restore(bad).ok, "missing persisted actor rejected rather than respawned")
	bad = before.duplicate(true)
	bad.rng_state = 0
	_check(not state.restore(bad).ok, "invalid persistent RNG state rejected")
	bad = before.duplicate(true)
	bad.pending_usec = Ecology.STEP_USEC
	_check(not state.restore(bad).ok, "invalid fixed-step remainder rejected")
	bad = before.duplicate(true)
	bad.actors["I1:repair_01"].reserve_remaining = 999.0
	_check(not state.restore(bad).ok, "forged backup charge rejected")
	bad = before.duplicate(true)
	bad.actors["F1:pollinator_01"].cargo = true
	_check(not state.restore(bad).ok, "unearned cargo rejected")
	bad = before.duplicate(true)
	bad.event_serial += 1
	_check(not state.restore(bad).ok, "event serial must match completed work, preventing forged dedup position")
	bad = before.duplicate(true)
	bad.contexts.I1.weather = "alien"
	_check(not state.restore(bad).ok, "unknown saved context is rejected rather than silently repaired")
	bad = before.duplicate(true)
	bad.routes_digest = "changed"
	_check(not state.restore(bad).ok, "route revisions require explicit migration")
	_check(state.snapshot() == before, "all failed restores leave the live state untouched")
	var definitions: Dictionary = state.definitions()
	var invalid: Dictionary = definitions.duplicate(true)
	while invalid.actors.size() <= Ecology.MAX_ACTORS: invalid.actors.append(definitions.actors[0].duplicate(true))
	_check(state.configure(invalid).code == "actor_limit" and state.snapshot() == before, "actor limit applies before constructing a new run")
	invalid = definitions.duplicate(true)
	invalid.regions[1].nodes[0].position[1] = 11.9
	_check(state.configure(invalid).code == "fantasy_flight_clearance", "fantasy route below mandated height is invalid")
	invalid = definitions.duplicate(true)
	invalid.regions[0].nodes[0].neighbors = ["missing"]
	_check(not state.configure(invalid).ok, "unknown graph edge rejected")
	invalid = definitions.duplicate(true)
	invalid.actors[1].jobs.remove_at(0)
	_check(state.configure(invalid).code == "invalid_cargo_cycle", "delivery definition cannot omit loading")
	_check(not state.configure(definitions, 0).ok and state.snapshot() == before, "failed seed validation preserves current run")

func _snapshot_differences(left: Variant, right: Variant, path: String = "root") -> Array:
	var differences: Array = []
	if typeof(left) != typeof(right):
		return [{"path":path, "left_type":typeof(left), "right_type":typeof(right), "left":left, "right":right}]
	if left is Dictionary:
		for key in left:
			if not right.has(key): differences.append({"path":path + "." + str(key), "missing":true})
			else: differences.append_array(_snapshot_differences(left[key], right[key], path + "." + str(key)))
	elif left is Array:
		if left.size() != right.size(): return [{"path":path, "left_size":left.size(), "right_size":right.size()}]
		for index in range(left.size()): differences.append_array(_snapshot_differences(left[index], right[index], path + "[%d]" % index))
	elif left != right:
		differences.append({"path":path, "left":left, "right":right})
	return differences
