extends SceneTree
## Pure adapter/SceneTree regression using actual configured FlightBody envelopes.
## Pose and accepted-blink fixtures are explicit; no physics flight/LOS, Session,
## persistence, UDP, rendered-art, performance or human-play evidence is claimed.
const Adapter = preload("res://scripts/v3/gameplay/actions/twin_underdeck_action.gd")
const FlightBody = preload("res://scripts/v2/flight_body.gd")
const Catalog = preload("res://scripts/v2/catalog.gd")
const Rules = preload("res://scripts/v3/gameplay/twin_ability_rules.gd")
const PATH := "res://data/v3/terrain/i1_underdeck_layout.json"
var world: Node3D
var bodies: Dictionary = {}
var layout: Dictionary = {}
var checks := 0
var failures: Array = []
var finished := false
var rules := Rules.new()

func _initialize() -> void:
	_run.call_deferred()

func _check(ok: bool, label: String, detail: Variant = {}) -> void:
	checks += 1
	if not ok:
		failures.append({"check":label, "detail":detail})
		push_error("UNDERDECK_ACTION " + label + " " + str(detail))

func _run() -> void:
	create_timer(30.0, true).timeout.connect(func():
		if not finished: push_error("UNDERDECK_ACTION timeout"); quit(2))
	layout = JSON.parse_string(FileAccess.get_file_as_string(PATH))
	world = Node3D.new()
	root.add_child(world)
	for pair in [[1, "tr01"], [2, "hx02"]]:
		var body := FlightBody.new()
		body.configure(Catalog.resolve_build(Catalog.default_build(pair[1])))
		body.freeze = true
		world.add_child(body)
		body.set_process(false)
		body.set_physics_process(false)
		bodies[pair[0]] = body
	paused = true
	_test_configuration()
	for peer in bodies:
		_test_entrances(peer)
		_test_blink(peer)
		_test_exit(peer)
	_test_signals()
	_test_peer_reset()
	_test_invalid_and_reset()
	finished = true
	world.queue_free()
	await process_frame
	await process_frame
	print("UNDERDECK_ACTION_RESULT ", JSON.stringify({"checks":checks, "failures":failures,
		"evidence":"Pure fact adapter with real FlightBody shapes and explicit pose/signal fixtures; no integrated gameplay or save test."}))
	quit(0 if failures.is_empty() else 1)

func _new():
	var result := Adapter.new()
	_check(result.configure(layout).ok, "valid current layout configures")
	return result

func _pose(peer: int, at: Vector3, yaw: float = 0.0) -> void:
	var body = bodies[peer]
	body.global_transform = Transform3D(Basis(Vector3.UP, yaw), at)
	body.enabled = true
	body.health = body.maximum_health
	body.linear_velocity = Vector3.ZERO
	body.angular_velocity = Vector3.ZERO

func _players(peer: int) -> Dictionary:
	return {peer:bodies[peer]}

func _entities(open: bool = true, held: bool = false) -> Dictionary:
	return {Adapter.FRONT:{"position":Vector3(-30.8, 2.05, -18.5) if open else Vector3(-35, 2.05, -18.5),
		"tags":["fieldable"], "pinned":held, "pinned_by":"1" if held else "", "field_remaining":4.0 if held else 0.0},
		Adapter.LATCH:{"position":Vector3(-36.3, 2.1, -25), "tags":["echo_operable", "mechanical", "hackable"],
			"owner":"", "revision":0}}

func _step(adapter, peer: int, entities: Dictionary, objective: String, latched: bool = false, delta: float = 0.25) -> Dictionary:
	return adapter.step(delta, _players(peer), entities, objective, latched)

func _expected(target: String, option: String, peer: int) -> Dictionary:
	return {"kind":"fact", "target":target, "option":option, "subject_peer":peer}

func _test_configuration() -> void:
	var adapter := Adapter.new()
	_check(adapter.step(0.1, {}, {}, Adapter.ENTER, false).is_empty(), "unconfigured adapter cannot emit")
	_check(not adapter.note_blink(1, Vector3.ZERO, Vector3.LEFT), "unconfigured blink rejected")
	for key in ["schema", "missing_air", "duplicate_void", "nan", "gate_axis", "wrong_plane"]:
		var bad: Dictionary = layout.duplicate(true)
		match key:
			"schema": bad.schema_version = 99
			"missing_air": bad.voids = []
			"duplicate_void": bad.voids.append(bad.voids[0].duplicate(true))
			"nan": bad.outer.min[0] = NAN
			"gate_axis": bad.gates.front.travel[1] = 1.0
			"wrong_plane": bad.voids[0].max[2] = -19.0
		_check(not adapter.configure(bad).ok and not adapter.debug_state().configured, "bad configuration rejected atomically: " + key)
	var data: Dictionary = layout.duplicate(true)
	_check(adapter.configure(data).ok, "valid configuration after rejected attempts")
	data.voids[0].max[2] = 500.0
	_pose(1, Vector3(-35, 2.05, -16.8))
	_step(adapter, 1, _entities(), Adapter.ENTER)
	_pose(1, Vector3(-35, 2.05, -20.2))
	var fact := _step(adapter, 1, _entities(), Adapter.ENTER)
	_check(fact == _expected("I1:underdeck_entry", "main_flight", 1), "caller mutation cannot alter configured portal")
	var before: Dictionary = adapter.debug_state()
	_check(not adapter.configure({}).ok and adapter.debug_state() == before, "failed reconfigure preserves candidate and tracked state")

func _test_entrances(peer: int) -> void:
	var adapter = _new()
	var entities := _entities()
	_pose(peer, Vector3(-35, 2.05, -16.8))
	_check(_step(adapter, peer, entities, Adapter.ENTER).is_empty(), "first outside sample cannot complete: " + str(peer))
	_pose(peer, Vector3(-35, 2.05, -18.4))
	_check(_step(adapter, peer, entities, Adapter.ENTER).is_empty(), "half-crossed body is not a complete entrance: " + str(peer))
	_pose(peer, Vector3(-35, 2.05, -20.2))
	var event := _step(adapter, peer, entities, Adapter.ENTER)
	var expected := _expected("I1:underdeck_entry", "main_flight", peer)
	_check(event == expected, "full actual body clears south portal: " + str(peer))
	event.option = "tampered"
	_pose(peer, Vector3(-20, 9, -10))
	_check(_step(adapter, peer, entities, Adapter.ENTER) == expected, "unacknowledged traversal survives save failure; result is a copy: " + str(peer))
	_check(not adapter.acknowledge(Adapter.RELEASE) and _step(adapter, peer, entities, Adapter.ENTER) == expected, "wrong acknowledgement cannot consume entrance: " + str(peer))
	_check(_step(adapter, peer, entities, "unknown:objective").is_empty() and _step(adapter, peer, entities, Adapter.ENTER) == expected,
		"pending candidate is returned only for its current objective: " + str(peer))
	_check(adapter.acknowledge(Adapter.ENTER) and _step(adapter, peer, entities, Adapter.ENTER).is_empty(), "successful-transaction acknowledgement consumes exactly its candidate: " + str(peer))
	for scenario in ["held", "closed", "expired_pin", "too_high", "edge", "backwards", "initial_inside", "roof"]:
		adapter.reset()
		entities = _entities(scenario != "closed", scenario in ["held", "expired_pin"])
		if scenario == "expired_pin": entities[Adapter.FRONT].field_remaining = 0.0
		var start := Vector3(-35, 2.05, -16.8)
		var end := Vector3(-35, 2.05, -20.2)
		if scenario == "too_high": start.y = 3.6; end.y = 3.6
		if scenario == "edge": start.x = -33.4; end.x = -33.4
		if scenario == "roof": start.y = 7.0; end.y = 7.0
		if scenario == "backwards": start.z = -20.2; end.z = -16.8
		if scenario == "initial_inside": start.z = -20.2; end.z = -22.0
		_pose(peer, start)
		_step(adapter, peer, entities, Adapter.ENTER)
		_pose(peer, end)
		event = _step(adapter, peer, entities, Adapter.ENTER)
		if scenario in ["held", "expired_pin"]:
			_check(event == _expected("I1:underdeck_entry", "held_grille" if scenario == "held" else "main_flight", peer), "actual held status labels method, expired marker does not: " + scenario + str(peer))
		else: _check(event.is_empty(), "no false south crossing: " + scenario + str(peer))
	adapter.reset()
	_pose(peer, Vector3(-24.5, 3.55, -23.5))
	_step(adapter, peer, _entities(false), Adapter.ENTER)
	_pose(peer, Vector3(-30.5, 3.55, -23.5))
	_check(_step(adapter, peer, _entities(false), Adapter.ENTER) == _expected("I1:underdeck_entry", "side_flight", peer), "east window remains a solo method while south is closed: " + str(peer))
	adapter.reset()
	_pose(peer, Vector3(-24.5, 4.75, -23.5))
	_step(adapter, peer, _entities(), Adapter.ENTER)
	_pose(peer, Vector3(-30.5, 4.75, -23.5))
	_check(_step(adapter, peer, _entities(), Adapter.ENTER).is_empty(), "east-window height uses entire body, not its centre: " + str(peer))
	adapter.reset()
	_pose(peer, Vector3(-35, 2.05, -16.8), 0.22)
	_step(adapter, peer, _entities(), Adapter.ENTER)
	_pose(peer, Vector3(-35, 2.05, -20.2), 0.22)
	_check(_step(adapter, peer, _entities(), Adapter.ENTER) == _expected("I1:underdeck_entry", "main_flight", peer), "actual rotated envelope fits the central south route: " + str(peer))

func _test_blink(peer: int) -> void:
	var adapter = _new()
	var entities := _entities(false)
	var start := Vector3(-24.5, 3.55, -23.5)
	var end := start + Vector3.LEFT * 6.0
	_pose(peer, start)
	_step(adapter, peer, entities, Adapter.ENTER)
	var before: Dictionary = adapter.debug_state()
	_check(not adapter.note_blink(peer, start, end) and adapter.debug_state() == before, "unexecuted request cannot record a blink; real body is still outside: " + str(peer))
	_pose(peer, end)
	_check(_step(adapter, peer, entities, Adapter.ENTER) == _expected("I1:underdeck_entry", "side_flight", peer), "later movement cannot make a previously rejected request into blink evidence: " + str(peer))
	adapter.reset()
	_pose(peer, start)
	_step(adapter, peer, entities, Adapter.ENTER)
	_pose(peer, end) # Explicit authority-approved, executed translation fixture.
	_check(adapter.note_blink(peer, start, end), "post-execution body records bounded one-tick receipt: " + str(peer))
	before = adapter.debug_state()
	_check(adapter.step(0, _players(peer), entities, Adapter.ENTER, false).is_empty() and adapter.debug_state() == before, "pause cannot consume accepted blink token: " + str(peer))
	_check(_step(adapter, peer, entities, Adapter.ENTER) == _expected("I1:underdeck_entry", "side_blink", peer), "same approved six-metre segment crosses actual window: " + str(peer))
	for drift_after in [false, true]:
		adapter.reset()
		_pose(peer, start)
		_step(adapter, peer, entities, Adapter.ENTER)
		var actual_from := start + Vector3(-0.4, 0.05, -0.05)
		var actual_to := actual_from + Vector3.LEFT * 6.0
		_pose(peer, actual_from) # Movement since the preceding observer sample.
		_pose(peer, actual_to)
		_check(adapter.note_blink(peer, actual_from, actual_to), "actual execution can differ from old sample by more than2mm: " + str(peer) + str(drift_after))
		if drift_after: _pose(peer, actual_to + Vector3(-0.08, 0.01, 0))
		_check(_step(adapter, peer, entities, Adapter.ENTER) == _expected("I1:underdeck_entry", "side_blink", peer), "execution-time receipt survives ordinary next-physics movement: " + str(peer) + str(drift_after))
	for kind in ["wrong_peer", "wrong_to"]:
		adapter.reset()
		_pose(peer, start)
		_step(adapter, peer, entities, Adapter.ENTER)
		_pose(peer, end)
		before = adapter.debug_state()
		_check(not adapter.note_blink(3 - peer if kind == "wrong_peer" else peer, start, end + Vector3.UP if kind == "wrong_to" else end)
			and adapter.debug_state() == before, "mismatched live-body receipt rejects atomically: " + kind + str(peer))
		_check(_step(adapter, peer, entities, Adapter.ENTER) == _expected("I1:underdeck_entry", "side_flight", peer), "rejected receipt cannot relabel ordinary flight: " + kind + str(peer))
	for initial_partial in [false, true]:
		adapter.reset()
		var partial := Vector3(-25.5, 3.55, -23.5)
		_pose(peer, partial if initial_partial else start)
		_step(adapter, peer, entities, Adapter.ENTER)
		if not initial_partial:
			_pose(peer, partial)
			_step(adapter, peer, entities, Adapter.ENTER)
		_pose(peer, partial + Vector3.LEFT * 6.0)
		_check(adapter.note_blink(peer, partial, partial + Vector3.LEFT * 6.0), "post-execution blink fits side-window from partial envelope start: " + str(peer) + str(initial_partial))
		_check(_step(adapter, peer, entities, Adapter.ENTER) == _expected("I1:underdeck_entry", "side_blink", peer), "partial entry needs no historical fully-outside sample: " + str(peer) + str(initial_partial))
	for kind in ["roof", "edge", "inside", "reverse", "tail_outside"]:
		adapter.reset()
		var bad_from := start
		var bad_to := end
		match kind:
			"roof": bad_from.y = 4.75; bad_to.y = 4.75
			"edge": bad_from.z = -21.95; bad_to.z = -21.95
			"inside": bad_from.x = -30.5; bad_to.x = -32.0
			"reverse": bad_from = end; bad_to = start
			"tail_outside": bad_to.x = -26.6
		_pose(peer, bad_from)
		_step(adapter, peer, entities, Adapter.ENTER)
		_pose(peer, bad_to)
		before = adapter.debug_state()
		_check(not adapter.note_blink(peer, bad_from, bad_to) and adapter.debug_state() == before, "actual shape/direction rejects invalid side entry: " + kind + str(peer))
		_check(_step(adapter, peer, entities, Adapter.ENTER).is_empty(), "invalid executed fixture cannot earn entrance: " + kind + str(peer))
	adapter.reset()
	_pose(peer, end)
	_check(not adapter.note_blink(peer, start, end), "spawn before first positive observer sample fails closed: " + str(peer))
	for invalid_body in ["disabled", "changed_shape"]:
		adapter.reset()
		_pose(peer, start)
		_step(adapter, peer, entities, Adapter.ENTER)
		_pose(peer, end)
		_check(adapter.note_blink(peer, start, end), "valid receipt before lifecycle change: " + invalid_body + str(peer))
		var old_shape = bodies[peer].get_node("Envelope").shape
		if invalid_body == "disabled": bodies[peer].enabled = false
		else:
			var shape := BoxShape3D.new()
			shape.size = old_shape.size + Vector3(0.01, 0, 0)
			bodies[peer].get_node("Envelope").shape = shape
		_check(_step(adapter, peer, entities, Adapter.ENTER).is_empty(), "inactive/reconfigured body cannot consume a receipt: " + invalid_body + str(peer))
		bodies[peer].get_node("Envelope").shape = old_shape
		bodies[peer].enabled = true
	adapter.reset()
	_pose(peer, start)
	_step(adapter, peer, entities, Adapter.ENTER)
	_pose(peer, end)
	_check(adapter.note_blink(peer, start, end), "valid receipt before unknown-objective tick: " + str(peer))
	_check(_step(adapter, peer, entities, "unknown").is_empty() and adapter.debug_state().blinks.is_empty(), "any positive tick consumes receipt without inventing unrelated objectives: " + str(peer))
	_pose(peer, start)
	_step(adapter, peer, entities, Adapter.ENTER)
	_pose(peer, end)
	_check(_step(adapter, peer, entities, Adapter.ENTER) == _expected("I1:underdeck_entry", "side_flight", peer), "later flight never inherits a consumed blink: " + str(peer))
	_check(not adapter.note_blink(peer, Vector3.ZERO, Vector3.INF) and not adapter.note_blink(peer, Vector3.ZERO, Vector3.LEFT * 9.1), "invalid/unbounded blink evidence rejected: " + str(peer))

func _test_peer_reset() -> void:
	var adapter = _new()
	var entities := _entities()
	_pose(1, Vector3(-35, 2.05, -16.8))
	_pose(2, Vector3(-24.5, 3.55, -23.5))
	adapter.step(0.25, bodies, entities, Adapter.ENTER, false)
	_pose(1, Vector3(-35, 2.05, -20.2))
	var expected := _expected("I1:underdeck_entry", "main_flight", 1)
	_check(adapter.step(0.25, bodies, entities, Adapter.ENTER, false) == expected, "peer1 earns entrance but simulated failed save leaves it unacknowledged")
	_pose(2, Vector3(-30.5, 3.55, -23.5))
	_check(adapter.note_blink(2, Vector3(-24.5, 3.55, -23.5), bodies[2].global_position), "peer2 has separate transient execution receipt")
	adapter.reset_peer(2)
	var state: Dictionary = adapter.debug_state()
	_check(state.tracked_peers == [1] and state.tracked_body_peers == [1] and not state.crossings.has(2) and not state.blinks.has(2), "peer2 reset clears only its motion/body/receipt records", state)
	_check(adapter.step(0.25, bodies, entities, Adapter.ENTER, false) == expected, "teammate revive does not erase peer1 pending world fact")
	adapter.reset_peer(1)
	_check(adapter.step(0.25, bodies, entities, Adapter.ENTER, false) == expected, "even fact-owner revive preserves an already verified pending fact")
	_check(adapter.acknowledge(Adapter.ENTER) and adapter.step(0.25, bodies, entities, Adapter.ENTER, false).is_empty(), "pending after peer resets still needs one transaction acknowledgement")
	for reset_owner in [false, true]:
		adapter.reset()
		entities = _entities()
		_pose(1, Vector3(-35, 2.1, -25))
		_pose(2, Vector3(-34, 2.1, -25))
		_activate(entities, "echo", 1)
		for unused in range(3): _signal_tick(adapter, entities, bodies)
		adapter.reset_peer(1 if reset_owner else 2)
		state = adapter.debug_state()
		_check(is_equal_approx(float(state.signal_seconds), 0.0 if reset_owner else 0.75), "only signal owner's reset clears incomplete continuity: " + str(reset_owner))
		var event := _signal_tick(adapter, entities, bodies)
		_check(event.is_empty() if reset_owner else event == _expected("I1:underdeck_safety_lock", "released", 1), "teammate reset preserves continuity; owner restart cannot shortcut one second: " + str(reset_owner))
		if reset_owner:
			_check(is_equal_approx(float(adapter.debug_state().signal_seconds), 0.25), "owner signal restarts from fresh positive delta")
			for unused in range(3): event = _signal_tick(adapter, entities, bodies)
		adapter.reset_peer(1)
		_check(adapter.step(0.25, {}, entities, Adapter.RELEASE, false) == _expected("I1:underdeck_safety_lock", "released", 1), "earned lock-release candidate survives owner reset/offline and save retry: " + str(reset_owner))
	adapter.reset()
	_check(adapter.debug_state().pending.is_empty() and adapter.debug_state().tracked_body_peers.is_empty(), "full world reset still removes all pending facts and live weak references")

func _test_exit(peer: int) -> void:
	var adapter = _new()
	var entities := _entities()
	for kind in ["unlatched", "outside_start", "backwards", "roof", "valid"]:
		adapter.reset()
		var start := Vector3(-35, 2.05, -33.5)
		var end := Vector3(-35, 2.05, -37.5)
		if kind == "outside_start": start.z = -17.0
		if kind == "backwards": start.z = -37.5; end.z = -33.5
		if kind == "roof": start.y = 7; end.y = 7
		_pose(peer, start)
		_step(adapter, peer, entities, Adapter.TRAVERSE, kind != "unlatched")
		_pose(peer, end)
		var event := _step(adapter, peer, entities, Adapter.TRAVERSE, kind != "unlatched")
		_check(event == _expected("I1:underdeck_transit", "verified", peer) if kind == "valid" else event.is_empty(), "north outward full-envelope transit: " + kind + str(peer))

func _activate(entities: Dictionary, ability: String, peer: int) -> void:
	var actor := "test_actor:" + str(peer)
	entities[actor] = {"id":actor, "owner":str(peer), "tags":["player"], "position":bodies[peer].global_position, "energy":100.0, "health":100.0, "revision":0}
	# Explicit LOS fixture for a rules unit test; no ray/sweep is claimed here.
	var result: Dictionary = rules.resolve({"ability":ability, "actor_id":actor, "target_id":Adapter.LATCH}, entities, {"sender_id":str(peer), "line_of_sight":true})
	_check(result.ok and rules.commit(result, entities).ok, "production rules create actual " + ability + " signal for peer " + str(peer), result.get("code"))

func _signal_tick(adapter, entities: Dictionary, players: Dictionary, dt: float = 0.25) -> Dictionary:
	var timed: Dictionary = rules.advance_states(entities, dt)
	rules.commit(timed, entities)
	return adapter.step(dt, players, entities, Adapter.RELEASE, false)

func _test_signals() -> void:
	for ability in ["echo", "takeover"]:
		var adapter = _new()
		var entities := _entities()
		_pose(1, Vector3(-35, 2.1, -25))
		_activate(entities, ability, 1)
		for tick in range(3): _check(_signal_tick(adapter, entities, _players(1)).is_empty(), "release not earned before one second: " + ability + str(tick))
		var before: Dictionary = adapter.debug_state()
		var unchanged: Dictionary = entities.duplicate(true)
		_check(adapter.step(0, _players(1), entities, Adapter.RELEASE, false).is_empty() and adapter.debug_state() == before and entities == unchanged, "pause preserves partial signal and external entities: " + ability)
		var expected := _expected("I1:underdeck_safety_lock", "released", 1)
		_check(_signal_tick(adapter, entities, _players(1)) == expected, "continuous production signal reaches one second: " + ability)
		# Simulated write failure: deliberately do not call acknowledge.
		rules.commit(rules.advance_states(entities, 9.0), entities)
		_check(adapter.step(0.25, {}, entities, Adapter.RELEASE, false) == expected
			and float(adapter.debug_state().signal_seconds) == 0.0, "earned candidate survives failed commit/expired source/disconnect while short timer clears: " + ability)
		var copied: Dictionary = adapter.debug_state()
		copied.pending.clear()
		_check(adapter.step(0.25, {}, entities, Adapter.RELEASE, false) == expected, "diagnostic copy cannot erase pending candidate: " + ability)
		_check(adapter.acknowledge(Adapter.RELEASE) and not adapter.acknowledge(Adapter.RELEASE)
			and adapter.step(0.25, {}, entities, Adapter.RELEASE, true).is_empty(), "acknowledge is one-shot and emits no reward: " + ability)
	for broken in ["offline", "disabled", "dead", "expired", "operated_only", "bad_owner", "wrong_tags", "nonfinite", "oversize_timer"]:
		var adapter = _new()
		var entities := _entities()
		_pose(1, Vector3(-35, 2.1, -25))
		_activate(entities, "echo", 1)
		for unused in range(3): _signal_tick(adapter, entities, _players(1))
		var players := _players(1)
		match broken:
			"offline": players = {}
			"disabled": bodies[1].enabled = false
			"dead": bodies[1].health = 0.0
			"expired": entities[Adapter.LATCH].echo_remaining = 0.0
			"operated_only": entities[Adapter.LATCH].erase("echo_remaining")
			"bad_owner": entities[Adapter.LATCH].echoed_by = "01"
			"wrong_tags": entities[Adapter.LATCH].tags = []
			"nonfinite": entities[Adapter.LATCH].echo_remaining = NAN
			"oversize_timer": entities[Adapter.LATCH].echo_remaining = 900.0
		_check(adapter.step(0.25, players, entities, Adapter.RELEASE, false).is_empty() and float(adapter.debug_state().signal_seconds) == 0.0,
			"broken source clears incomplete continuity: " + broken)
		_pose(1, Vector3(-35, 2.1, -25))
	# Switching the valid owner cannot combine two partial signals into one second.
	var adapter = _new()
	var entities := _entities()
	_pose(1, Vector3(-35, 2.1, -25))
	_pose(2, Vector3(-34, 2.1, -25))
	_activate(entities, "echo", 1)
	for unused in range(3): _signal_tick(adapter, entities, bodies)
	rules.commit(rules.advance_states(entities, 6.0), entities)
	_activate(entities, "takeover", 2)
	_check(_signal_tick(adapter, entities, bodies).is_empty() and is_equal_approx(float(adapter.debug_state().signal_seconds), 0.25), "different live owner/method starts a fresh one-second interval")
	for unused in range(2): _signal_tick(adapter, entities, bodies)
	_check(_signal_tick(adapter, entities, bodies) == _expected("I1:underdeck_safety_lock", "released", 2), "cooperative second source can complete independently without mandatory simultaneity")
	# No locally remembered enter receipt is needed after restoring an enter-complete save.
	adapter.reset()
	entities = _entities()
	_activate(entities, "echo", 1)
	var event: Dictionary = {}
	for unused in range(10): event = _signal_tick(adapter, entities, _players(1), 0.1)
	_check(event == _expected("I1:underdeck_safety_lock", "released", 1), "restored-enter objective releases after ten0.1s ticks without re-entering")

func _test_invalid_and_reset() -> void:
	var adapter = _new()
	var entities := _entities()
	_pose(1, Vector3(-35, 2.1, -25))
	_activate(entities, "echo", 1)
	_signal_tick(adapter, entities, _players(1))
	var before: Dictionary = adapter.debug_state()
	for delta in [-0.1, 0.2501, NAN, INF]:
		_check(adapter.step(delta, _players(1), entities, Adapter.RELEASE, false).is_empty() and adapter.debug_state() == before, "invalid delta atomic rejection: " + str(delta))
	for invalid in [{1:Vector3.ZERO}, {"1":bodies[1]}, {1:bodies[1],2:bodies[1]}, {1:bodies[1],2:bodies[2],3:bodies[1]}]:
		_check(adapter.step(0.1, invalid, entities, Adapter.RELEASE, false).is_empty() and adapter.debug_state() == before, "invalid physical roster rejects whole tick")
	var body_before: Transform3D = bodies[1].global_transform
	var entity_before: Dictionary = entities.duplicate(true)
	adapter.step(0.1, _players(1), entities, "unknown:objective", false)
	_check(bodies[1].global_transform == body_before and entities == entity_before and adapter.debug_state().pending.is_empty(), "unknown objective safe; adapter never mutates body or entities")
	adapter.note_blink(1, Vector3.ZERO, Vector3.LEFT * 6)
	adapter.reset()
	var reset: Dictionary = adapter.debug_state()
	_check(reset.configured and reset.tracked_peers.is_empty() and reset.crossings.is_empty() and reset.blinks.is_empty()
		and reset.pending.is_empty() and reset.signal_key.is_empty() and reset.signal_seconds == 0.0, "reset clears all transient evidence but retains layout")
	# Shape/identity replacement cannot inherit a half-completed physical crossing.
	_pose(1, Vector3(-35, 2.05, -16.8))
	_step(adapter, 1, entities, Adapter.ENTER)
	_pose(1, Vector3(-35, 2.05, -18.4))
	_step(adapter, 1, entities, Adapter.ENTER)
	var old_shape = bodies[1].get_node("Envelope").shape
	var replacement := BoxShape3D.new()
	replacement.size = old_shape.size + Vector3(0.01,0,0)
	bodies[1].get_node("Envelope").shape = replacement
	_pose(1, Vector3(-35, 2.05, -20.2))
	_check(_step(adapter, 1, entities, Adapter.ENTER).is_empty(), "changed actual envelope cannot inherit preceding crossing sample")
	bodies[1].get_node("Envelope").shape = old_shape
	adapter.reset()
	replacement.size = Vector3(5.0, old_shape.size.y, old_shape.size.z)
	bodies[1].get_node("Envelope").shape = replacement
	_pose(1, Vector3(-35, 2.05, -16.8))
	_step(adapter, 1, entities, Adapter.ENTER)
	_pose(1, Vector3(-35, 2.05, -20.2))
	_check(_step(adapter, 1, entities, Adapter.ENTER).is_empty(), "actual collider width rejects entry even though unchanged chassis stats/centre fit")
	bodies[1].get_node("Envelope").shape = old_shape
	adapter.reset()
	_pose(1, Vector3(-35, 2.05, -16.8))
	_pose(2, Vector3(-35, 2.05, -16.8))
	adapter.step(0.25, {2:bodies[2], 1:bodies[1]}, entities, Adapter.ENTER, false)
	_pose(1, Vector3(-35, 2.05, -20.2))
	_pose(2, Vector3(-35, 2.05, -20.2))
	_check(adapter.step(0.25, {2:bodies[2], 1:bodies[1]}, entities, Adapter.ENTER, false) == _expected("I1:underdeck_entry", "main_flight", 1),
		"simultaneous pose-fixture arrivals select stable peer order, not Dictionary insertion order")
