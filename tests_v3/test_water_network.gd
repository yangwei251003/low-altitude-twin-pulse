extends SceneTree
## Pure reservoir rules only: no world, graphics, network or human-play evidence.

const Water = preload("res://scripts/v3/gameplay/environment/twin_water_network.gd")
var checks := 0
var failures: Array[String] = []
var partition_measurement: Dictionary = {}

func _init() -> void:
	_test_study_and_copy_boundaries()
	_test_controls_and_atomic_failure()
	_test_conservative_split_merge_and_mixing()
	_test_gravity_pumps_and_rate()
	_test_partition_pause_and_replay()
	_test_invalid_definitions_and_snapshots()
	var sample = _new_study()
	print("V3_WATER_NETWORK_TESTS " + JSON.stringify({"checks":checks, "failures":failures,
		"snapshot_bytes":JSON.stringify(sample.snapshot()).to_utf8_buffer().size(),
		"frame_partition_measurement":partition_measurement,
		"scope":"pure rules; I2 not integrated; no GPU, LAN, performance or human-play claim"}))
	quit(0 if failures.is_empty() else 1)

func _check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures.append(label)
		push_error(label)

func _new_study():
	var state = Water.new()
	_check(state.load_definition().ok, "actual four-reservoir study loads")
	return state

func _node(id: String, capacity: int = 1000, clean: int = 0, dirty: int = 0, base: int = 0, area: int = 1000) -> Dictionary:
	return {"id":id, "capacity_ml":capacity, "clean_ml":clean, "dirty_ml":dirty, "base_mm":base, "area_cm2":area}

func _pump(id: String, source: String, target: String, rate: int = 1000) -> Dictionary:
	return {"id":id, "from":source, "to":target, "kind":"pump", "max_rate_ml_s":rate,
		"conductance_ml_s_per_mm":0, "pump_head_mm":100000, "initial_open_permille":1000,
		"initial_powered":true, "bidirectional":false}

func _gravity(id: String, source: String, target: String, reverse: bool = false) -> Dictionary:
	return {"id":id, "from":source, "to":target, "kind":"gravity", "max_rate_ml_s":50000,
		"conductance_ml_s_per_mm":5000, "pump_head_mm":0, "initial_open_permille":1000,
		"initial_powered":false, "bidirectional":reverse}

func _definition(nodes: Array, edges: Array) -> Dictionary:
	return {"schema_version":1, "id":"test:water", "version":1, "nodes":nodes, "edges":edges}

func _configured(definition: Dictionary):
	var state = Water.new()
	_check(state.configure(definition).ok, "bounded fixture definition accepted")
	return state

func _totals(state) -> Array:
	var clean := 0
	var dirty := 0
	for node in state.definitions().nodes:
		var actual: Dictionary = state.get_node(node.id)
		clean += int(actual.clean_ml)
		dirty += int(actual.dirty_ml)
	return [clean, dirty]

func _invariants(state, expected: Array, label: String) -> void:
	var nonnegative := true
	var within_capacity := true
	var limited := true
	for node in state.definitions().nodes:
		var value: Dictionary = state.get_node(node.id)
		nonnegative = nonnegative and value.clean_ml >= 0 and value.dirty_ml >= 0
		within_capacity = within_capacity and value.volume_ml <= node.capacity_ml
	for edge in state.definitions().edges:
		limited = limited and absi(int(state.get_edge(edge.id).last_transfer_ml)) <= int(ceil(float(edge.max_rate_ml_s) / 10.0))
	_check(nonnegative and within_capacity, label + ": no negative component or overflow")
	_check(_totals(state) == expected, label + ": clean/dirty totals independently conserved")
	_check(limited, label + ": every actual transfer respects quantized rate bound")
	_check(state.validate_snapshot(state.snapshot()).ok, label + ": produced state passes restore contract")

func _test_study_and_copy_boundaries() -> void:
	var state = _new_study()
	_check(state.definitions().nodes.size() == 4 and state.definitions().edges.size() == 5, "study remains bounded at four tanks / five links")
	_check(_totals(state) == [670000, 430000], "study independently contains 1100 L in two conserved components")
	_check(is_equal_approx(float(state.get_node("I2:clean_cistern").level_m), 8.0), "water level uses real volume / footprint plus base height")
	_check(state.get_node("missing").is_empty() and state.get_edge("missing").is_empty(), "unknown accessor IDs are safe empty values")
	var before: Dictionary = state.snapshot()
	var definition: Dictionary = state.definitions()
	definition.nodes[0].clean_ml = 0
	var node: Dictionary = state.get_node("I2:clean_cistern")
	node.clean_ml = -100
	var edge: Dictionary = state.get_edge("I2:clean_to_clinic")
	edge.open_permille = 1000
	var saved: Dictionary = state.snapshot()
	saved.nodes.clear()
	_check(state.snapshot() == before and state.definitions().nodes.size() == 4, "definition / node / edge / snapshot accessors do not leak mutable state")
	var controls := {"I2:clean_to_clinic":{"open_permille":1000}}
	_check(state.step(0.1, controls).ok, "host opens real study feed")
	controls["I2:clean_to_clinic"].open_permille = 0
	_check(state.get_edge("I2:clean_to_clinic").open_permille == 1000 and state.get_node("I2:clinic_tank").volume_ml > 0, "command alias cannot change installed control")
	_check(state.get_node("I2:clinic_tank").dirty_ml == 0, "clean-only feed does not invent a dirty component")

func _test_controls_and_atomic_failure() -> void:
	var state = _new_study()
	var before: Dictionary = state.snapshot()
	var batches: Array = [
		{"I2:clean_to_clinic":{"open_permille":1000}, "missing":{"powered":true}},
		{"I2:rain_to_clinic":{"powered":true}, "I2:clinic_drain":{"open_permille":1001}},
		{"I2:clean_to_clinic":{"open_permille":-1}},
		{"I2:clean_to_clinic":{"open_permille":1.5}},
		{"I2:rain_to_clinic":{"powered":1}},
		{"I2:clean_to_clinic":{"powered":true}},
		{"I2:clean_to_clinic":{"invent_water":true}},
		{"I2:clean_to_clinic":{}},
		[{"edge_id":"I2:rain_to_clinic", "powered":true}, {"edge_id":"I2:rain_to_clinic", "powered":false}],
		[{"edge_id":"I2:rain_to_clinic", "powered":true}, {"edge_id":"I2:clinic_drain", "unknown":0}],
		true, null]
	for batch in batches:
		var rejected: Dictionary = state.step(0.1, batch)
		_check(not rejected.ok and state.snapshot() == before, "invalid / duplicated control batch rejected without a partial change: " + rejected.code)
	for delta in [-0.1, 5.001, INF, NAN]:
		_check(not state.step(delta, {"I2:rain_to_clinic":{"powered":true}}).ok and state.snapshot() == before, "bad delta rejects control and clock atomically")
	_check(not state.step(1.0, {"I2:rain_to_clinic":{"powered":true}}, false).ok and state.snapshot() == before, "client call cannot mutate power, volume or clock")
	_check(state.step(0.0, {"I2:rain_to_clinic":{"powered":true}}).ok and state.snapshot() == before, "zero delta is a true no-op including valid controls")
	_check(state.step(2.0, {"I2:rain_to_clinic":{"powered":true}}, true, true).ok and state.snapshot() == before, "paused nonzero call consumes no time / controls")
	_check(state.step(0.1, [{"edge_id":"I2:rain_to_clinic", "powered":true}]).ok and state.get_node("I2:clinic_tank").dirty_ml > 0, "unique command-list form performs actual dirty mixture transport")
	var empty = Water.new()
	_check(not empty.step(0.1).ok and not empty.restore(before).ok, "unconfigured state cannot simulate or restore")

func _test_conservative_split_merge_and_mixing() -> void:
	var split := _definition([_node("A", 1000, 3, 4), _node("B"), _node("C")], [_pump("a", "A", "B"), _pump("b", "A", "C")])
	var state = _configured(split)
	state.step(0.1)
	_check(state.get_node("A").volume_ml == 0 and state.get_node("B").volume_ml == 4 and state.get_node("C").volume_ml == 3, "competing pumps share depleted source proportionally with a stable 1 ml tie")
	_invariants(state, [3, 4], "source split")
	var reverse: Dictionary = split.duplicate(true)
	reverse.nodes.reverse()
	reverse.edges.reverse()
	var alternate = _configured(reverse)
	alternate.step(0.1)
	_check(alternate.snapshot() == state.snapshot(), "source/edge definition order cannot bias allocation or fingerprint")
	var merge := _definition([_node("A", 1000, 100), _node("B", 1000, 0, 100), _node("C", 5)], [_pump("a", "A", "C"), _pump("b", "B", "C")])
	state = _configured(merge)
	state.step(0.1)
	_check(state.get_node("C").volume_ml == 5 and state.get_node("C").clean_ml == 3 and state.get_node("C").dirty_ml == 2, "competing inlets respect five-ml destination capacity without destroying mixture")
	_invariants(state, [100, 100], "destination merge")
	var pipeline := _definition([_node("A", 1000, 100), _node("B"), _node("C")], [_pump("a", "A", "B"), _pump("b", "B", "C")])
	state = _configured(pipeline)
	state.step(0.1)
	_check(state.get_node("B").volume_ml == 100 and state.get_node("C").volume_ml == 0, "new arrivals cannot traverse two pipes in the same tick")
	state.step(0.1)
	_check(state.get_node("C").volume_ml == 100, "the intermediate reservoir can supply the next tick")
	_invariants(state, [100, 0], "pipeline")
	state = _new_study()
	var initial := _totals(state)
	for index in range(30):
		var controls := {"I2:clean_to_clinic":{"open_permille":1000 if index % 3 else 200},
			"I2:rain_to_clinic":{"powered":index % 4 != 0}, "I2:clinic_drain":{"open_permille":750},
			"I2:rain_sump_link":{"open_permille":500}, "I2:sump_return":{"powered":true, "open_permille":800}}
		_check(state.step(5.0, controls).ok, "bounded mixed study interval advances")
		_invariants(state, initial, "mixed network interval %d" % index)
	_check(state.get_node("I2:clinic_tank").clean_fraction > 0.0 and state.get_node("I2:clinic_tank").clean_fraction < 1.0, "shared feed leaves a mixed clinic tank, not artificial purification")

func _test_gravity_pumps_and_rate() -> void:
	var definition := _definition([_node("A", 1000, 1000), _node("B"), _node("C")], [_gravity("g", "A", "B")])
	var state = _configured(definition)
	state.step(0.1)
	_check(state.get_node("A").volume_ml == 500 and state.get_node("B").volume_ml == 500, "single gravity link stops at equal head instead of overshooting")
	state.step(5.0)
	_check(state.get_edge("g").last_transfer_ml == 0, "equal head has no gratuitous circulation")
	definition = _definition([_node("A"), _node("B", 1000, 0, 1000), _node("C")], [_gravity("g", "A", "B", true)])
	state = _configured(definition)
	state.step(0.1)
	_check(state.get_edge("g").last_transfer_ml == -500 and state.get_node("A").dirty_ml == 500, "bidirectional gravity follows head reversal and moves the correct component")
	definition.edges[0].bidirectional = false
	state = _configured(definition)
	state.step(1.0)
	_check(state.get_node("A").volume_ml == 0 and state.get_edge("g").eligibility == "no_downhill_head", "one-way valve blocks uphill gravity")
	definition = _definition([_node("A", 1000, 500), _node("B", 1000, 0, 0, 2000), _node("C")], [_pump("p", "A", "B")])
	definition.edges[0].pump_head_mm = 1000
	state = _configured(definition)
	state.step(1.0)
	_check(state.get_node("B").volume_ml == 0 and state.get_edge("p").eligibility == "head_limit", "powered pump still cannot exceed rated lift")
	definition.edges[0].pump_head_mm = 3000
	definition.edges[0].initial_powered = false
	state = _configured(definition)
	state.step(1.0)
	_check(state.get_node("B").volume_ml == 0, "open but unpowered pump transports nothing")
	state.step(0.1, {"p":{"powered":true, "open_permille":0}})
	_check(state.get_node("B").volume_ml == 0, "powered but closed pump transports nothing")
	state.step(0.1, {"p":{"open_permille":1000}})
	_check(state.get_node("B").volume_ml == 100 and state.get_edge("p").last_flow_l_s == 1.0, "power and valve together produce bounded uphill transport with correct output units")
	definition = _definition([_node("A", 1000, 500), _node("B"), _node("C")], [_pump("p", "A", "B", 50000)])
	definition.edges[0].pump_head_mm = 1
	state = _configured(definition)
	state.step(0.1)
	_check(state.get_node("A").volume_ml == 200 and state.get_node("B").volume_ml == 300, "fast pump is volume-clamped within the same tick at its exact 1 mm lift boundary")
	_check(is_equal_approx(float(state.get_node("B").level_m) - float(state.get_node("A").level_m), 0.001), "actual post-transfer water levels respect rated single-link lift")
	state.step(5.0)
	_check(state.get_node("B").volume_ml == 300 and state.get_edge("p").last_transfer_ml == 0 and state.get_edge("p").eligibility == "head_limit", "continued powered steps cannot creep past the single-link lift boundary")
	_invariants(state, [500, 0], "pump lift clamp")
	definition = _definition([_node("A", 1000, 500), _node("B"), _node("C")], [_pump("p", "A", "B", 1)])
	definition.edges[0].initial_open_permille = 333
	state = _configured(definition)
	state.step(5.0)
	state.step(5.0)
	_check(state.get_node("B").volume_ml == 3 and state.get_edge("p").flow_carry == 3300, "sub-ml tick rate persists fractional budget rather than stalling or rounding water into existence")
	_invariants(state, [500, 0], "fractional rate")

func _test_partition_pause_and_replay() -> void:
	var controls := {"I2:clean_to_clinic":{"open_permille":750}, "I2:rain_to_clinic":{"powered":true}, "I2:clinic_drain":{"open_permille":300}}
	var large = _new_study()
	var small = _new_study()
	var irregular = _new_study()
	large.step(5.0, controls)
	for index in range(50):
		small.step(0.1, controls)
		irregular.step(0.03, controls)
		irregular.step(0.07, controls)
	_check(large.snapshot() == small.snapshot() and small.snapshot() == irregular.snapshot(), "same explicit time with constant controls: 5 s / 100 ms / 30+70 ms partitions have zero state error")
	# Real frame periods are not exact integer microseconds. Test the advertised
	# rounding bound independently, without disguising it as exact equivalence.
	var hz30 = _new_study()
	var hz60 = _new_study()
	for index in range(30): hz30.step(1.0 / 30.0, controls)
	for index in range(60): hz60.step(1.0 / 60.0, controls)
	var elapsed_error := absf(hz30.elapsed_seconds() - hz60.elapsed_seconds())
	var tick_difference := absi(int(hz30.snapshot().tick) - int(hz60.snapshot().tick))
	var volume_l1 := 0
	var one_tick_l1_bound := 0
	for node in hz30.definitions().nodes:
		volume_l1 += absi(int(hz30.get_node(node.id).volume_ml) - int(hz60.get_node(node.id).volume_ml))
	for edge in hz30.definitions().edges:
		one_tick_l1_bound += 2 * int(ceil(float(edge.max_rate_ml_s) / 10.0))
	partition_measurement = {"nominal_seconds":1.0, "elapsed_difference_seconds":elapsed_error,
		"fixed_tick_difference":tick_difference, "node_volume_l1_difference_ml":volume_l1,
		"one_tick_volume_l1_bound_ml":one_tick_l1_bound}
	_check(elapsed_error <= 0.0000451 and tick_difference <= 1, "30/60 Hz same nominal second stays within summed 0.5 microsecond rounding budget and one fixed tick")
	_check(volume_l1 <= one_tick_l1_bound, "30/60 Hz reservoir difference is bounded by one actual fixed-step transport budget")
	_invariants(hz30, [670000, 430000], "30 Hz partition")
	_invariants(hz60, [670000, 430000], "60 Hz partition")
	large.step(0.037, controls)
	var before: Dictionary = large.snapshot()
	_check(before.pending_usec == 37000 and is_equal_approx(large.elapsed_seconds(), 5.037), "subtick phase and elapsed time are explicit")
	large.step(5.0, {}, true, true)
	large.step(0.0)
	_check(large.snapshot() == before, "pause retains existing fractional phase without catch-up")
	var restored = _new_study()
	var decoded: Dictionary = JSON.parse_string(JSON.stringify(before, "", true, true))
	_check(restored.restore(decoded).ok and restored.snapshot() == before, "JSON save/reload is exactly equal, including fractional flow/time phase")
	_check(typeof(restored.snapshot().tick) == TYPE_INT and typeof(restored.get_node("I2:clinic_tank").clean_ml) == TYPE_INT, "JSON numeric values normalize to integer state")
	decoded.nodes.clear()
	_check(restored.snapshot() == before, "restored state is not aliased to caller snapshot")
	for index in range(12):
		var commands := {"I2:rain_to_clinic":{"powered":index % 2 == 0}, "I2:clean_to_clinic":{"open_permille":250 + index * 50}}
		var left: Dictionary = large.step(0.263, commands)
		var right: Dictionary = restored.step(0.263, commands)
		_check(left == right and large.snapshot() == restored.snapshot(), "save/reload deterministic replay interval %d" % index)
	_invariants(restored, [670000, 430000], "replayed study")

func _test_invalid_definitions_and_snapshots() -> void:
	var state = _new_study()
	state.step(0.237, {"I2:rain_to_clinic":{"powered":true}})
	var before: Dictionary = state.snapshot()
	var definitions: Dictionary = state.definitions()
	var mutations: Array = []
	var bad: Dictionary = definitions.duplicate(true)
	bad.nodes.resize(2)
	mutations.append(bad)
	bad = definitions.duplicate(true)
	bad.nodes.append(_node("extra_1"))
	bad.nodes.append(_node("extra_2"))
	mutations.append(bad)
	bad = definitions.duplicate(true)
	bad.nodes.append(bad.nodes[0].duplicate(true))
	mutations.append(bad)
	bad = definitions.duplicate(true)
	bad.nodes[0].capacity_ml = 0
	mutations.append(bad)
	bad = definitions.duplicate(true)
	bad.nodes[0].clean_ml = -1
	mutations.append(bad)
	bad = definitions.duplicate(true)
	bad.nodes[0].area_cm2 = 0
	mutations.append(bad)
	bad = definitions.duplicate(true)
	bad.nodes[0].dirty_ml = Water.MAX_CAPACITY
	mutations.append(bad)
	bad = definitions.duplicate(true)
	bad.edges[0].to = bad.edges[0].from
	mutations.append(bad)
	bad = definitions.duplicate(true)
	bad.edges[0].from = "missing"
	mutations.append(bad)
	bad = definitions.duplicate(true)
	bad.edges[0].max_rate_ml_s = Water.MAX_RATE + 1
	mutations.append(bad)
	bad = definitions.duplicate(true)
	bad.edges[0].conductance_ml_s_per_mm = INF
	mutations.append(bad)
	bad = definitions.duplicate(true)
	bad.edges.append(bad.edges[0].duplicate(true))
	mutations.append(bad)
	bad = definitions.duplicate(true)
	for index in range(4): bad.edges.append(_pump("extra_%d" % index, "I2:rain_tank", "I2:clinic_tank"))
	mutations.append(bad)
	bad = definitions.duplicate(true)
	bad.extra = true
	mutations.append(bad)
	for invalid in mutations:
		_check(not state.configure(invalid).ok and state.snapshot() == before, "invalid definition rejects atomically without replacing active reservoirs")
	mutations.clear()
	for path_and_value in [["schema_version",2], ["algorithm","other"], ["definition_version",2], ["definition_digest","other"], ["tick",-1], ["tick",Water.MAX_COUNTER + 1], ["pending_usec",100000], ["pending_usec",0.5]]:
		bad = before.duplicate(true)
		bad[path_and_value[0]] = path_and_value[1]
		mutations.append(bad)
	bad = before.duplicate(true)
	bad.nodes["I2:clean_cistern"].clean_ml -= 1
	mutations.append(bad)
	bad = before.duplicate(true)
	bad.nodes["I2:clean_cistern"].clean_ml = NAN
	mutations.append(bad)
	bad = before.duplicate(true)
	bad.nodes["I2:clinic_tank"].dirty_ml = -1
	mutations.append(bad)
	bad = before.duplicate(true)
	# Preserve both global totals while overflowing an individual tank.
	bad.nodes["I2:clinic_tank"].clean_ml += 500000
	bad.nodes["I2:clean_cistern"].clean_ml -= 500000
	mutations.append(bad)
	bad = before.duplicate(true)
	bad.nodes.erase("I2:rain_tank")
	mutations.append(bad)
	bad = before.duplicate(true)
	bad.edges["extra"] = {}
	mutations.append(bad)
	for field_and_value in [["flow_carry",10000], ["last_transfer_ml",60001], ["last_direction",-1], ["powered",1], ["open_permille",-1]]:
		bad = before.duplicate(true)
		bad.edges["I2:rain_to_clinic"][field_and_value[0]] = field_and_value[1]
		mutations.append(bad)
	for invalid in mutations:
		_check(not state.restore(invalid).ok and state.snapshot() == before, "invalid save rejects atomically without silently repairing quantities or clocks")
	var changed: Dictionary = definitions.duplicate(true)
	changed.nodes[0].base_mm += 1
	var other = _configured(changed)
	_check(not other.restore(before).ok, "same version with changed geometry still fails definition fingerprint")
	bad = before.duplicate(true)
	bad.tick = Water.MAX_COUNTER
	_check(state.restore(bad).ok, "maximum bounded counter snapshot is valid")
	var at_limit: Dictionary = state.snapshot()
	_check(not state.step(0.1, {"I2:rain_to_clinic":{"powered":false}}).ok and state.snapshot() == at_limit, "counter overflow rejects before changing controls or remainder")
