extends SceneTree
## Pure encounter behavior only. VERIFIED is an explicit host collision fixture,
## not a real raycast, map, LAN, GPU or player-comfort validation.
const Crown = preload("res://scripts/v3/gameplay/twin_crown_encounter.gd")
const VERIFIED := {"is_authority":true, "line_of_sight":true, "hit_confirmed":true, "sender_id":"1"}
var checks := 0
var failures: Array[String] = []
var observations: Dictionary = {}

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	_test_height_band()
	_test_locked_escape()
	_test_natural_deadline()
	_test_repeated_blocked_routes()
	_test_target_rotation()
	_test_phase_two()
	_test_pause_and_restore()
	print("V3_CROWN_ATTACK_SCHEDULE " + JSON.stringify({"checks":checks, "failed":failures.size(), "failures":failures,
		"observations":observations, "scope":"pure actual clock/shape/hit behavior; host collision and route approval fixtures; no real map/LAN/GPU evidence"}))
	quit(0 if failures.is_empty() else 1)

func _new(points: Array = [Vector3(-10, 24, -3)]):
	var result = Crown.new()
	var loaded: Dictionary = result.load_definition()
	var roster: Dictionary = {}
	for i in points.size():
		var owner := str(i + 1)
		roster["player:" + owner] = {"owner":owner, "position":points[i], "health":1000.0, "max_health":1000.0, "downed":false}
	var started: Dictionary = result.start(roster, 8128) if loaded.ok else loaded
	if not loaded.ok or not started.ok: _check(false, "valid pure fixture loads and starts")
	return result

func _step(state, approve: bool = true) -> Array:
	var result: Dictionary = state.advance(0.1)
	if not result.ok:
		_check(false, "100ms pure time advance accepted")
		return []
	var events: Array = result.events.duplicate(true)
	for event in result.events:
		if event.kind == "movement_requested":
			var response: Dictionary = state.approve_migration(str(event.movement.token), approve)
			if not response.ok: _check(false, "explicit route approval fixture accepted")
			events.append_array(response.events)
	return events

func _steps(state, count: int, approve: bool = true) -> void:
	for i in count: _step(state, approve)

func _high(attack: Dictionary) -> Dictionary:
	for shape in attack.get("shapes", []):
		if shape.kind == "cylinder": return shape
	return {}

func _next_high(state, limit: int = 400) -> Dictionary:
	for i in limit:
		var events: Array = _step(state)
		for event in events:
			if event.kind == "attack_telegraphed" and not _high(event.attack).is_empty(): return event.attack.duplicate(true)
	return {}

func _to_active(state, token: String, limit: int = 50) -> Dictionary:
	for i in limit:
		var attack: Dictionary = state.get_state().attack
		if attack.get("token", "") == token and attack.get("fired", false): return attack
		_step(state)
	return {}

func _test_height_band() -> void:
	var heights := [0.0, 9.999, 10.0, 22.0, 23.0, 27.0]
	for y in heights:
		var point := Vector3(-10, y, -3)
		var state = _new([point])
		var attack := _next_high(state)
		var shape := _high(attack)
		_check(not shape.is_empty() and Crown.contains_shape(shape, point), "stationary selected height %.3fm lies inside its warned pollen column" % y)
		if shape.is_empty(): continue
		var low := float(shape.y_min_mm) / 1000.0
		var high := float(shape.y_max_mm) / 1000.0
		_check(Crown.contains_shape(shape, Vector3(point.x, low, point.z)) and not Crown.contains_shape(shape, Vector3(point.x, high, point.z))
			and not Crown.contains_shape(shape, Vector3(point.x, low - 0.001, point.z)) and Crown.contains_shape(shape, Vector3(point.x, high - 0.001, point.z)),
			"height band %.3fm preserves inclusive lower / exclusive upper boundaries" % y)
	var state = _new()
	var shape := _high(_next_high(state))
	_check(Crown.contains_shape(shape, Vector3(-6.5, 24, -3)) and not Crown.contains_shape(shape, Vector3(-6.499, 24, -3)), "radius 3.500m is included; 3.501m is outside")
	_check(not Crown.contains_shape(shape, Vector3(NAN, 24, -3)), "nonfinite position cannot become a hit")

func _test_locked_escape() -> void:
	var state = _new([Vector3(-10, 18, -3)])
	var warning := _next_high(state)
	var saved: Dictionary = state.snapshot()
	var destinations := [Vector3(-6, 18, -3), Vector3(-10, 23, -3), Vector3(-10, 13, -3)]
	var labels := ["lateral", "ascending", "descending"]
	for i in destinations.size():
		var branch = Crown.new()
		var restored: Dictionary = branch.restore(saved)
		if not restored.ok:
			_check(false, "escape fixture restores valid warning")
			continue
		branch.set_player_position("player:1", destinations[i])
		var active := _to_active(branch, str(warning.get("token", "")))
		_check(not active.is_empty() and active.shapes == warning.shapes, "%s escape does not drag the locked warning after the player" % labels[i])
		var hit: Dictionary = branch.apply_attack_hit(str(warning.get("token", "")), "player:1", VERIFIED)
		_check(hit.get("code") == "outside_attack" and branch.get_state().players["player:1"].health == 1000.0, "%s escape avoids actual pure damage at activation" % labels[i])

func _test_natural_deadline() -> void:
	var state = _new()
	_steps(state, 119)
	var before: Dictionary = state.get_state()
	_check(before.tick == 119 and not _high(before.attack).is_empty() and not before.attack.fired, "natural initial high warning exists immediately before twelve-second deadline")
	_step(state)
	var at_deadline: Dictionary = state.get_state()
	var attack: Dictionary = at_deadline.attack
	_check(at_deadline.tick == 120 and not attack.is_empty() and attack.get("fired", false), "twelve-second automatic migration does not erase the newly active high attack")
	var hit: Dictionary = state.apply_attack_hit(str(attack.get("token", "")), "player:1", VERIFIED)
	_check(hit.ok and state.get_state().players["player:1"].health == 976.0, "stationary 24m pilot takes real pure damage across the natural twelve-second boundary")
	_check(state.apply_attack_hit(str(attack.get("token", "")), "player:1", VERIFIED).get("code") == "attack_already_hit", "one active high attack cannot hit twice")
	_steps(state, 13)
	_check(state.get_state().mode == "migration_warning" and state.get_state().attack.is_empty(), "automatic migration resumes after the active attack finishes")
	observations.natural_hit_tick = at_deadline.tick

func _test_repeated_blocked_routes() -> void:
	var state = _new()
	var refused := 0
	var hit_tokens: Array[String] = []
	for i in 500:
		var events := _step(state, false)
		for event in events:
			if event.kind == "movement_blocked": refused += 1
		var s: Dictionary = state.get_state()
		var attack: Dictionary = s.attack
		if refused < 1 or s.mode != "unrooted" or attack.is_empty() or not attack.get("fired", false): continue
		var token := str(attack.token)
		if token in hit_tokens: continue
		var hit: Dictionary = state.apply_attack_hit(token, "player:1", VERIFIED)
		if hit.ok: hit_tokens.append(token)
		if refused >= 3 and hit_tokens.size() >= 2: break
	_check(refused >= 3, "route remains refused through at least two repeated fallback cycles")
	_check(hit_tokens.size() >= 2 and state.get_state().players["player:1"].health <= 952.0, "repeated fallback produces at least two actual high hits instead of cancelled warning-only events")
	observations.repeated_blocked_routes = refused
	observations.fallback_hit_tokens = hit_tokens

func _test_target_rotation() -> void:
	var points := [Vector3(-10, 24, -3), Vector3(10, 24, 4)]
	var state = _new(points)
	var selected: Array[int] = []
	for i in 4:
		var shape := _high(_next_high(state))
		selected.append(_selected(shape, points))
	_check(selected == [1, 2, 1, 2] or selected == [2, 1, 2, 1], "four actual high warnings alternate both healthy players instead of sharing low/high parity")
	observations.high_target_order = selected
	var departed = _new(points)
	_next_high(departed)
	departed.remove_player("player:1")
	var after_leave: Array[int] = []
	for i in 2: after_leave.append(_selected(_high(_next_high(departed)), points))
	_check(after_leave == [2, 2], "departed player is excluded from subsequent high warning selection")
	var downed = _new(points)
	_next_high(downed)
	downed.down_player("player:2")
	var after_down: Array[int] = []
	for i in 2: after_down.append(_selected(_high(_next_high(downed)), points))
	_check(after_down == [1, 1], "downed player is excluded without resetting the surviving player's encounter")

func _selected(shape: Dictionary, points: Array) -> int:
	if shape.is_empty(): return 0
	for i in points.size():
		if shape.centre_xz_mm == [int(round(points[i].x * 1000.0)), int(round(points[i].z * 1000.0))]: return i + 1
	return 0

func _test_phase_two() -> void:
	var points := [Vector3(-10, 13, -3), Vector3(10, 24, 4)]
	var state = _new(points)
	var actors := {"player:1":{"owner":"1", "tags":["player"], "position":points[0], "health":1000.0, "downed":false, "energy":100.0, "revision":0}}
	var bound := true
	for ability in ["light", "growth"]:
		var transaction: Dictionary = state.resolve_ability({"ability":ability, "actor_id":"player:1", "target_id":"F1:crown_host_west"}, actors, VERIFIED)
		var applied: Dictionary = state.commit_ability(transaction, actors, true) if transaction.get("ok", false) else transaction
		bound = bound and applied.get("ok", false)
	var first: Dictionary = state.hit_core("player:1", 50.0, 1, VERIFIED)
	state.advance(0.23)
	var second: Dictionary = state.hit_core("player:1", 50.0, 2, VERIFIED)
	_check(bound and first.ok and second.ok and state.get_state().phase == 2, "phase-two fixture enters through legal ability and bounded damage APIs")
	if not second.ok: return
	var movement: Dictionary = state.get_state().movement
	state.approve_migration(str(movement.token), false)
	state.set_player_position("player:1", Vector3(-10, 27, -3))
	var warning := _next_high(state)
	_check(warning.get("shapes", []).size() == 2 and Crown.contains_shape(_high(warning), Vector3(-10, 27, -3)), "phase-two combined warning still covers the selected ceiling hover")
	var selected: Array[int] = [_selected(_high(warning), points)]
	var saved: Dictionary = state.snapshot()
	state.set_player_position("player:1", Vector3(-6, 27, -3))
	var active := _to_active(state, str(warning.get("token", "")))
	_check(not active.is_empty() and state.apply_attack_hit(str(warning.get("token", "")), "player:1", VERIFIED).get("code") == "outside_attack", "lateral ceiling escape remains valid against both phase-two shapes")
	state.restore(saved)
	state.set_player_position("player:1", Vector3(-10, 21.999, -3))
	active = _to_active(state, str(warning.get("token", "")))
	_check(not active.is_empty() and state.apply_attack_hit(str(warning.get("token", "")), "player:1", VERIFIED).get("code") == "outside_attack", "descending outside the locked band remains valid against phase-two low wave too")
	for i in 3: selected.append(_selected(_high(_next_high(state)), points))
	_check(selected == [1, 2, 1, 2], "phase two alternates one target on every combined warning")
	observations.phase_two_target_order = selected

func _test_pause_and_restore() -> void:
	var state = _new()
	var warning := _next_high(state)
	var before: Dictionary = state.snapshot()
	var zero: Dictionary = state.advance(0.0)
	_check(zero.ok and zero.events.is_empty() and state.snapshot() == before, "paused zero-step preserves warning geometry, token and activation time")
	var restored = Crown.new()
	var result: Dictionary = restored.restore(JSON.parse_string(JSON.stringify(before)))
	_check(result.ok and restored.get_state().attack.shapes == warning.shapes, "JSON restore preserves the exact locked shape")
	if not result.ok: return
	state.set_player_position("player:1", Vector3(-6, 24, -3))
	restored.set_player_position("player:1", Vector3(-6, 24, -3))
	var original_events: Array = []
	var restored_events: Array = []
	for i in 25:
		original_events.append_array(_step(state))
		restored_events.append_array(_step(restored))
	_check(state.snapshot() == restored.snapshot() and original_events == restored_events and state.get_state().attack.shapes == warning.shapes, "restored and uninterrupted warnings activate identically without retargeting")

func _check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures.append(label)
		push_error(label)
