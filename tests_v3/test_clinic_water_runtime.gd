extends SceneTree
## Isolated rules; no world, actual platform, save files, GPU, UDP or human play.

const Runtime = preload("res://scripts/v3/environment/twin_clinic_water_runtime.gd")
const Water = preload("res://scripts/v3/gameplay/environment/twin_water_network.gd")
var checks := 0
var failures: Array[String] = []
var measurements: Dictionary = {}

func _init() -> void:
	_test_definition_and_copies()
	_test_both_routes_and_exact_cutoff()
	_test_interlock_power_and_platform_block()
	_test_final_mixed_transfer()
	_test_time_and_replay()
	_test_atomic_rejection()
	var sample = _new()
	print("V3_CLINIC_WATER_RUNTIME_TESTS " + JSON.stringify({"checks":checks, "failures":failures,
		"measurements":measurements, "snapshot_bytes":JSON.stringify(sample.snapshot()).to_utf8_buffer().size(),
		"scope":"independent rules only; I2 scene, actuators, collision, story, save/network integration and human timing unverified"}))
	quit(0 if failures.is_empty() else 1)

func _check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures.append(label)
		push_error(label)

func _new():
	var state = Runtime.new()
	_check(state.load_definition().ok, "actual clinic definition loads independently")
	return state

func _facts(gravity: int = 0, pump: int = 0, powered: bool = false, blocked: bool = false) -> Dictionary:
	return {"gravity_open_permille":gravity, "pump_open_permille":pump,
		"pump_powered":powered, "platform_blocked":blocked}

func _totals(state) -> Array:
	var total := [0, 0]
	for node in state.definitions().nodes:
		var value: Dictionary = state.get_node(node.id)
		total[0] += int(value.clean_ml)
		total[1] += int(value.dirty_ml)
	return total

func _invariants(state, label: String) -> void:
	var capacities_ok := true
	for node in state.definitions().nodes:
		var value: Dictionary = state.get_node(node.id)
		capacities_ok = capacities_ok and int(value.clean_ml) >= 0 and int(value.dirty_ml) >= 0 and int(value.volume_ml) <= int(value.capacity_ml)
	_check(capacities_ok and int(state.get_node(Runtime.CLINIC).volume_ml) <= Runtime.TARGET_ML, label + ": real capacities / nonnegative quantities / cutoff")
	_check(_totals(state) == [3270000, 430000], label + ": both fluid components independently conserved")
	_check(state.validate_snapshot(state.snapshot()).ok, label + ": snapshot validates its current state")
	_check(int(state.get_edge(Runtime.GRAVITY).last_transfer_ml) <= 5000 and int(state.get_edge(Runtime.PUMP).last_transfer_ml) <= 3000, label + ": each actual transfer respects its own rate")

func _test_definition_and_copies() -> void:
	var state = _new()
	_check(state.definitions().nodes.size() == 4 and state.definitions().edges.size() == 2, "four real reservoirs / two same-source paths, no invented rain inlet")
	_check(_totals(state) == [3270000, 430000], "production initial quantities follow the clinic contract")
	_check(int(state.get_node(Runtime.CLINIC).capacity_ml) == 4000000, "2000 L cutoff does not falsify the 4000 L tank capacity")
	_check(is_equal_approx(float(state.get_node(Runtime.SOURCE).level_m), 8.0), "source initial level is 8 m from actual volume and footprint")
	_check(is_equal_approx(float(state.status().clinic_level_m), 3.5) and is_equal_approx(float(state.status().desired_deck_top_m), 4.0), "empty tank yields a 4 m setpoint, not a claimed physical platform")
	_check(state.get_node("missing").is_empty() and state.get_edge("missing").is_empty(), "unknown IDs return safe empty values")
	var before: Dictionary = state.snapshot()
	var copy: Dictionary = state.snapshot()
	copy.facts.platform_blocked = true
	copy.simulation.nodes.clear()
	var definition: Dictionary = state.definitions()
	definition.nodes.clear()
	var node: Dictionary = state.get_node(Runtime.SOURCE)
	node.clean_ml = 0
	var edge: Dictionary = state.get_edge(Runtime.GRAVITY)
	edge.open_permille = 999
	var view: Dictionary = state.status()
	view.effective_controls[Runtime.GRAVITY].open_permille = 999
	_check(state.snapshot() == before and state.definitions().nodes.size() == 4, "all exposed nested snapshots, controls, definitions and accessors are isolated")
	var study = Water.new()
	_check(study.load_definition().ok and not state.configure(study.definitions()).ok and state.snapshot() == before, "old study cannot silently become production clinic state")
	var facts := _facts(1000)
	_check(state.step(0.01, facts).ok, "subtick sample is accepted without moving fluid")
	facts.gravity_open_permille = 0
	_check(int(state.snapshot().facts.gravity_open_permille) == 1000 and int(state.get_node(Runtime.CLINIC).volume_ml) == 0, "caller fact mutation cannot change installed physical sample")

func _test_both_routes_and_exact_cutoff() -> void:
	for method in ["gravity", "pump"]:
		var state = _new()
		var facts: Dictionary = _facts(1000) if method == "gravity" else _facts(0, 1000, true)
		var rain_before: Dictionary = state.get_node("I2:rain_tank")
		var waste_before: Dictionary = state.get_node("I2:waste_sump")
		var accepted := true
		var moved := 0
		var simulated_seconds := 0.0
		for index in range(20):
			var result: Dictionary = state.step(5.0, facts)
			accepted = accepted and bool(result.ok)
			moved += int(result.moved_ml)
			simulated_seconds += 5.0
			if state.status().automatic_cutoff: break
		_check(accepted and state.status().automatic_cutoff, method + ": real rules reach the float cutoff within bounded explicit time")
		_check(moved == 2000000 and int(state.get_node(Runtime.CLINIC).volume_ml) == 2000000, method + ": exactly 2000 L transferred, no overrun or invented delivery")
		_check(int(state.get_node(Runtime.SOURCE).volume_ml) == 1200000 and float(state.status().clean_fraction) == 1.0, method + ": source keeps 1200 L, only clean source enters clinic")
		_check(float(state.status().clinic_level_m) == 4.5 and float(state.status().desired_deck_top_m) == 5.0, method + ": shared real tank geometry produces intended 4.5 / 5 m levels")
		_check(state.status().inlet_closed and int(state.get_edge(Runtime.GRAVITY).open_permille) == 0 and int(state.get_edge(Runtime.PUMP).open_permille) == 0, method + ": automatic inlet closure overrides the still-open physical selector")
		_check(state.get_node("I2:rain_tank") == rain_before and state.get_node("I2:waste_sump") == waste_before, method + ": disconnected dirty reservoirs remain unchanged")
		var stable_nodes: Dictionary = state.snapshot().simulation.nodes
		for index in range(4): state.step(5.0, facts)
		_check(state.snapshot().simulation.nodes == stable_nodes and int(state.status().last_tick_transfer_ml) == 0, method + ": continued host time cannot overfill after cutoff")
		measurements[method + "_five_second_observation_upper_bound_s"] = simulated_seconds
		_invariants(state, method + " complete")

func _test_interlock_power_and_platform_block() -> void:
	var state = _new()
	var before: Dictionary = state.snapshot()
	_check(not state.step(0.1, _facts(1, 1, false)).ok and state.snapshot() == before, "even an unpowered second open valve is an atomic mechanical interlock conflict")
	_check(not state.step(0.1, _facts(1000, 1000, true, true)).ok and state.snapshot() == before, "blockage cannot hide conflicting actual valve positions")
	_check(state.step(1.0, _facts(0, 1000, false)).ok and int(state.get_node(Runtime.CLINIC).volume_ml) == 0 and state.status().reason == "unpowered", "open pump has no flow without effective power")
	_check(state.step(1.0, _facts(0, 0, true)).ok and int(state.get_node(Runtime.CLINIC).volume_ml) == 0, "powered pump with closed valve has no flow")
	state.step(0.1, _facts(1000))
	_check(int(state.get_node(Runtime.CLINIC).volume_ml) == 5000, "gravity path really transports one 5000 ml tick")
	var volume_before := int(state.get_node(Runtime.CLINIC).volume_ml)
	var setpoint_before := float(state.status().desired_deck_top_m)
	var time_before := float(state.elapsed_seconds())
	var blocked: Dictionary = state.step(5.0, _facts(1000, 0, false, true))
	_check(blocked.ok and int(blocked.moved_ml) == 0 and state.status().reason == "platform_blocked", "host obstruction closes the effective inlet before simulating the interval")
	_check(int(state.get_node(Runtime.CLINIC).volume_ml) == volume_before and float(state.status().desired_deck_top_m) == setpoint_before, "obstruction holds both water quantity and hydraulic platform setpoint")
	_check(is_equal_approx(state.elapsed_seconds() - time_before, 5.0) and state.status().inlet_closed, "blocked time progresses explicitly without accumulating a fluid burst")
	var resumed: Dictionary = state.step(0.1, _facts(1000))
	_check(resumed.ok and int(resumed.moved_ml) == 5000, "unblocked inlet resumes only the current rate budget")
	state.step(0.1, _facts(0, 1000, true))
	_check(int(state.get_edge(Runtime.GRAVITY).last_transfer_ml) == 0 and int(state.get_edge(Runtime.PUMP).last_transfer_ml) == 3000, "route switch closes old route and uses new route without parallel transfer")
	state.step(0.01, _facts(0, 1000, true, true))
	_check(state.status().inlet_closed and int(state.get_edge(Runtime.PUMP).flow_carry) == 0, "subtick blockage already closes effective controls and discards fractional flow credit")
	_invariants(state, "blocked / switched")

# Explicit corruption-boundary fixture: preserve both global components while
# moving trusted stored fluid near cutoff and mixing the source. This is NOT a
# gameplay route or proof that disconnected reservoirs can exchange water.
func _near_cutoff_fixture(state, remaining: int, mixed: bool) -> Dictionary:
	var saved: Dictionary = state.snapshot()
	var delivered := Runtime.TARGET_ML - remaining
	saved.simulation.tick = 1
	saved.simulation.nodes[Runtime.SOURCE].clean_ml -= delivered
	saved.simulation.nodes[Runtime.CLINIC].clean_ml += delivered
	if mixed:
		saved.simulation.nodes[Runtime.SOURCE].clean_ml -= 100000
		saved.simulation.nodes[Runtime.SOURCE].dirty_ml += 100000
		saved.simulation.nodes["I2:rain_tank"].clean_ml += 100000
		saved.simulation.nodes["I2:rain_tank"].dirty_ml -= 100000
	return saved

@warning_ignore("integer_division")
func _test_final_mixed_transfer() -> void:
	for method in ["gravity", "pump"]:
		for remaining in [1, 347]:
			var state = _new()
			_check(state.restore(_near_cutoff_fixture(state, remaining, true)).ok, "explicit conserved mixture / near-cutoff fixture validates")
			var source: Dictionary = state.get_node(Runtime.SOURCE)
			var target: Dictionary = state.get_node(Runtime.CLINIC)
			var expected_clean: int = int(source.clean_ml) * remaining / int(source.volume_ml)
			var facts: Dictionary = _facts(1000) if method == "gravity" else _facts(0, 1000, true)
			var result: Dictionary = state.step(0.1, facts)
			_check(result.ok and int(result.moved_ml) == remaining and int(result.cutoff_clamped_ml) > 0, method + ": last tick closes at exact %d ml remainder" % remaining)
			_check(int(state.get_node(Runtime.CLINIC).clean_ml) - int(target.clean_ml) == expected_clean and int(state.get_node(Runtime.CLINIC).dirty_ml) - int(target.dirty_ml) == remaining - expected_clean, method + ": partial tick uses the pre-tick source mixture, never auto-purifies")
			_check(int(state.get_node(Runtime.SOURCE).volume_ml) == int(source.volume_ml) - remaining and int(state.get_node(Runtime.CLINIC).volume_ml) == Runtime.TARGET_ML, method + ": clipping restores untransferred water to its real source")
			_check(state.status().automatic_cutoff and float(state.status().clean_fraction) < 1.0, method + ": cutoff is a volume limit rather than a false water-quality claim")
			_invariants(state, method + " mixed final tick")
	var state = _new()
	_check(state.restore(_near_cutoff_fixture(state, 10000, true)).ok, "mixed pre-cutoff fixture validates")
	var before: Dictionary = state.get_node(Runtime.SOURCE)
	var expected_clean: int = int(before.clean_ml) * 3000 / int(before.volume_ml)
	var result: Dictionary = state.step(0.1, _facts(0, 1000, true))
	_check(result.ok and int(result.cutoff_clamped_ml) == 0 and int(before.clean_ml) - int(state.get_node(Runtime.SOURCE).clean_ml) == expected_clean, "ordinary uncut mixture follows the original core's conservative transfer")
	_invariants(state, "mixed ordinary tick")

func _test_time_and_replay() -> void:
	var whole = _new()
	var split = _new()
	var facts := _facts(333)
	whole.step(5.0, facts)
	for index in range(50):
		split.step(0.03, facts)
		split.step(0.07, facts)
	_check(whole.snapshot() == split.snapshot(), "integer-microsecond partitions produce exactly identical reservoir, control and clock state")
	var hz30 = _new()
	var hz60 = _new()
	for index in range(30): hz30.step(1.0 / 30.0, facts)
	for index in range(60): hz60.step(1.0 / 60.0, facts)
	_check(hz30.snapshot().simulation == hz60.snapshot().simulation and int(hz30.snapshot().simulation.tick) == 10, "sub-microsecond carry avoids the old 30/60 Hz one-tick water divergence")
	_check(int(hz30.snapshot().pending_usec) == 0 and int(hz60.snapshot().pending_usec) == 0 and absf(hz30.elapsed_seconds() - hz60.elapsed_seconds()) < 0.000000001, "nominal one-second frame partitions retain sub-nanosecond rather than per-frame rounding error")
	measurements["30_60_hz_elapsed_difference_s"] = absf(hz30.elapsed_seconds() - hz60.elapsed_seconds())
	whole.step(0.0370004, facts)
	var saved: Dictionary = whole.snapshot()
	_check(int(saved.pending_usec) == 37000 and absf(float(saved.fractional_usec) - 0.4) < 0.000001, "partial fixed tick and sub-microsecond time both enter the snapshot")
	var loaded = _new()
	var decoded: Dictionary = JSON.parse_string(JSON.stringify(saved, "", true, true))
	_check(loaded.restore(decoded).ok and loaded.snapshot() == saved, "full-precision JSON restores both clock remainders and conservative state exactly")
	decoded.facts.gravity_open_permille = 0
	decoded.simulation.nodes.clear()
	_check(loaded.snapshot() == saved, "restore does not alias a caller-owned nested snapshot")
	for index in range(8):
		var commands: Dictionary = _facts(0, 777, true, index == 3) if index % 2 else _facts(253, 0, false, index == 4)
		var left: Dictionary = whole.step(0.263, commands)
		var right: Dictionary = loaded.step(0.263, commands)
		_check(left == right and whole.snapshot() == loaded.snapshot(), "restored fractional time / flow / obstruction replay interval %d" % index)
	var before: Dictionary = loaded.snapshot()
	_check(loaded.step(0.0, _facts(0, 1000, true, true)).ok and loaded.snapshot() == before, "zero delta applies no controls, time, blockage or transfer")
	_check(loaded.step(5.0, _facts(), true, true).ok and loaded.snapshot() == before, "paused nonzero input cannot close an existing valve or consume pending time")
	# Nearest-microsecond tie must not turn a later positive tiny delta negative.
	var tie = _new()
	_check(tie.step(0.0999995, facts).ok and tie.step(0.000000000001, facts).ok, "half-microsecond boundary remains valid under a later tiny positive frame")
	_invariants(loaded, "replay")

func _test_atomic_rejection() -> void:
	var state = _new()
	state.step(0.237, _facts(333))
	var before: Dictionary = state.snapshot()
	var malformed: Array = [{}, true, null, _facts(1001), _facts(-1), _facts(1, 1)]
	for pair in [["gravity_open_permille", 0.25], ["pump_open_permille", "500"], ["pump_powered", 1], ["platform_blocked", 0], ["unknown", true]]:
		var bad := _facts()
		bad[pair[0]] = pair[1]
		malformed.append(bad)
	for value in malformed:
		_check(not state.step(0.1, value).ok and state.snapshot() == before, "malformed / conflicting full fact sample rejects without partial controls or time")
	for delta in [-0.1, 5.001, INF, NAN]:
		_check(not state.step(delta, _facts(0, 1000, true)).ok and state.snapshot() == before, "out-of-bounds delta atomically rejects all facts")
	_check(not state.step(1.0, _facts(), false).ok and state.snapshot() == before, "non-authoritative caller cannot mutate the independent runtime")
	var broken_saves: Array = []
	for pair in [["schema_version", 2], ["algorithm", "other"], ["pending_usec", 100000], ["pending_usec", -1], ["pending_usec", 0.5], ["fractional_usec", 0.5], ["fractional_usec", -0.50001], ["fractional_usec", NAN], ["facts", []], ["simulation", false], ["unknown", 0]]:
		var bad: Dictionary = before.duplicate(true)
		bad[pair[0]] = pair[1]
		broken_saves.append(bad)
	for pair in [["pending_usec", 1], ["tick", -1], ["definition_digest", "changed"], ["definition_version", 2]]:
		var bad: Dictionary = before.duplicate(true)
		bad.simulation[pair[0]] = pair[1]
		broken_saves.append(bad)
	var bad: Dictionary = before.duplicate(true)
	bad.simulation.nodes[Runtime.SOURCE].clean_ml -= 1
	broken_saves.append(bad)
	bad = before.duplicate(true)
	bad.simulation.nodes[Runtime.CLINIC].dirty_ml = -1
	broken_saves.append(bad)
	bad = before.duplicate(true)
	var excess := Runtime.TARGET_ML + 1 - int(bad.simulation.nodes[Runtime.CLINIC].clean_ml)
	bad.simulation.nodes[Runtime.SOURCE].clean_ml -= excess
	bad.simulation.nodes[Runtime.CLINIC].clean_ml += excess
	broken_saves.append(bad)
	bad = before.duplicate(true)
	bad.facts.platform_blocked = true
	broken_saves.append(bad)
	bad = before.duplicate(true)
	bad.simulation.edges[Runtime.GRAVITY].open_permille = 0
	broken_saves.append(bad)
	bad = before.duplicate(true)
	bad.facts = _facts()
	bad.simulation.edges[Runtime.GRAVITY].open_permille = 0
	bad.simulation.edges[Runtime.GRAVITY].flow_carry = 3
	broken_saves.append(bad)
	for invalid in broken_saves:
		_check(not state.restore(invalid).ok and state.snapshot() == before, "invalid snapshot rejects atomically, preserving prior fluid, controls and all clock phase")
	var changed: Dictionary = state.definitions()
	changed.version += 1
	var future = Runtime.new()
	_check(future.configure(changed).ok and not future.restore(before).ok, "definition version / fingerprint prevents old-config restore")
	for change in ["capacity", "geometry", "topology", "initial_mix"]:
		changed = state.definitions()
		if change == "capacity": changed.nodes[0].capacity_ml += 1
		elif change == "geometry": changed.nodes[0].base_mm += 1
		elif change == "topology": changed.edges[0].to = "I2:rain_tank"
		else: changed.nodes[0].clean_ml -= 1
		_check(not state.configure(changed).ok and state.snapshot() == before, "production contract violation cannot replace active definition: " + change)
	bad = before.duplicate(true)
	bad.simulation.tick = Water.MAX_COUNTER
	_check(state.restore(bad).ok, "maximum legal bounded clock can be restored")
	before = state.snapshot()
	_check(not state.step(0.1, _facts()).ok and state.snapshot() == before, "clock overflow rejects before closing a valve or consuming pending time")
	var empty = Runtime.new()
	_check(not empty.step(0.1, _facts()).ok and not empty.restore(before).ok and empty.snapshot().is_empty() and empty.status().is_empty(), "unconfigured runtime refuses progress and exposes no invented state")
