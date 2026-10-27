extends SceneTree
## Real SceneTree/PhysicsServer integration regression. Not a LAN transport,
## rendered-picture, frame-rate, controller or human-play test.

const Session = preload("res://scripts/v3/twin_session.gd")
var session
var checks: Array = []
var profile := ""
var report_path := "res://artifacts/v3/session-physics-report.json"
var started_at := 0

func _init() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--qa-profile="):
			profile = arg.trim_prefix("--qa-profile=")
		if arg.begins_with("--physics-report="):
			report_path = arg.trim_prefix("--physics-report=")
	if not profile.begins_with("qa_physics_") or profile.validate_filename() != profile:
		push_error("This integration test requires an isolated --qa-profile=qa_physics_<unique>.")
		quit(2)
		return
	if not report_path.begins_with("res://artifacts/v3/session-physics") or ".." in report_path:
		push_error("Report must remain under artifacts/v3/session-physics*.")
		quit(2)
		return
	started_at = Time.get_ticks_msec()
	_run.call_deferred()

func _run() -> void:
	session = Session.new()
	root.add_child(session)
	await process_frame
	_check(session.profile_ready, "isolated profile opened", {"profile": profile})
	if not session.profile_ready:
		_finish()
		return
	_check(session.start_flight("solo"), "real session starts solo")
	# We explicitly advance adapters to isolate cases; actual bodies, shapes,
	# physics frames, raycasts and collision sweeps remain live.
	session.set_process(false)
	session.set_physics_process(false)
	session.inputs.set_process(false)
	session.inputs.set_physics_process(false)
	_freeze_players()
	await _settle()
	await _test_blink()
	await _test_weapon_ability_independence()
	await _test_bridge_clearance()
	await _test_growth_bridge()
	await _test_gate_routes()
	await _test_boss_cover_and_damage()
	await _test_boss_warning_contract()
	await _test_boss_membership_and_wipe()
	await _test_boss_victory_warning_cleanup()
	_finish()

func _check(passed: bool, label: String, detail: Dictionary = {}) -> void:
	checks.append({"name": label, "passed": passed, "detail": detail})
	if not passed:
		push_error("PHYSICS REGRESSION: " + label + " " + JSON.stringify(detail))

func _settle() -> void:
	await physics_frame
	await physics_frame
	await process_frame

func _freeze_players() -> void:
	for body in session.players.values():
		body.freeze = true
		body.set_process(false)
		body.set_physics_process(false)
		body.linear_velocity = Vector3.ZERO
		body.angular_velocity = Vector3.ZERO

func _place(at: Vector3, peer_id: int = 1) -> void:
	var body = session.players[peer_id]
	body.freeze = true
	body.global_transform = Transform3D(Basis.IDENTITY, at)
	body.hold_height = at.y
	body.linear_velocity = Vector3.ZERO
	session.entities["player:" + str(peer_id)].position = at
	if session.boss_active:
		session.encounter.set_player_position(str(peer_id), at)
	await _settle()

func _cast(ability: String, target: String = "", point: Vector3 = Vector3.ZERO, mode: String = "") -> void:
	# Cooldown pacing is not under test. Every case still traverses _action_received,
	# authoritative rules, real LOS/sweep/clearance, commit and effect adapters.
	session.cooldowns[1] = 0.0
	session._action_received(1, "ability", {"ability": ability, "target_id": target, "point": point, "mode": mode})

func _ray(from: Vector3, to: Vector3, mask: int = 1) -> Dictionary:
	var query := PhysicsRayQueryParameters3D.create(from, to, mask)
	query.exclude = [session.players[1].get_rid()]
	return session.get_world_3d().direct_space_state.intersect_ray(query)

func _test_blink() -> void:
	await _place(Vector3(-18, 1, 17))
	var before_energy: float = session.entities["player:1"].energy
	var rejected_before: int = session.stats.rejected_abilities
	_cast("blink", "", Vector3(-10, 1, 17))
	_check(session.stats.rejected_abilities == rejected_before + 1, "blink rejects solid relay between two free positions")
	_check(session.players[1].position.is_equal_approx(Vector3(-18, 1, 17)) and session.entities["player:1"].energy == before_energy, "blocked blink neither moves nor spends energy")
	_cast("blink", "", Vector3(-14, 1, 17))
	_check(session.stats.rejected_abilities == rejected_before + 2, "blink rejects occupied destination")
	_check(session.entities["player:1"].energy == before_energy and session.players[1].position.is_equal_approx(Vector3(-18, 1, 17)), "occupied destination consumes no energy")
	await _place(Vector3(-18, 4, 17))
	var applied_before: int = session.stats.abilities
	_cast("blink", "", Vector3(-18, 4, 21))
	_check(session.stats.abilities == applied_before + 1 and session.players[1].position.is_equal_approx(Vector3(-18, 4, 21)), "clear blink really relocates body")
	_check(is_equal_approx(float(session.entities["player:1"].energy), before_energy - 16.0), "successful blink spends exact rule cost")

func _test_bridge_clearance() -> void:
	await _place(Vector3(0, 4, -14))
	var under_hit = session.players[1].move_and_collide(Vector3(0, 0, 12))
	_check(under_hit == null and session.players[1].position.z > -2.1, "real drone collider passes below upper bridge", {"end": str(session.players[1].position)})
	await _place(Vector3(0, 10, -8))
	var deck_hit = session.players[1].move_and_collide(Vector3(0, -6, 0))
	_check(deck_hit != null and session.players[1].position.y > 7.9, "bridge deck physically stops descending drone", {"end": str(session.players[1].position), "collider": str(deck_hit.get_collider()) if deck_hit else "none"})

func _test_weapon_ability_independence() -> void:
	await _place(Vector3(-18, 4, 17))
	session.cooldowns[1] = 0.0
	session.weapon_cooldowns[1] = 0.0
	session._fire(1)
	_check(session.weapon_cooldowns[1] > 0 and session.cooldowns[1] == 0, "weapon cadence does not consume ability cooldown")
	var used: int = session.stats.abilities
	session._action_received(1, "ability", {"ability":"blink", "point":Vector3(-18, 4, 21)})
	_check(session.stats.abilities == used + 1 and session.players[1].position.is_equal_approx(Vector3(-18, 4, 21)), "blink still moves while the fire button cadence is active")
	var energy: float = session.entities["player:1"].energy
	var rejected: int = session.stats.rejected_abilities
	session._action_received(1, "ability", {"ability":"blink", "point":Vector3(-18, 4, 27)})
	_check(session.stats.rejected_abilities == rejected + 1 and session.entities["player:1"].energy == energy, "repeated ability keeps its own cooldown and does not spend energy")
	session.weapon_cooldowns[1] = 0.0
	session._fire(1)
	_check(session.weapon_cooldowns[1] > 0 and session.cooldowns[1] > 0, "weapon can start its next shot during ability recovery")
	session._restore_player(1, Vector3(-18, 4, 24))
	_freeze_players()
	_check(not session.cooldowns.has(1) and not session.weapon_cooldowns.has(1), "restoring a pilot clears both independent cooldowns")
	await _settle()

func _test_growth_bridge() -> void:
	var growth_id: String = str(session.region_id) + ":growth"
	session.entities[growth_id].growth = 0.0
	session.entities[growth_id].light_level = 0.0
	session.world.synchronize(session.entities, 0.0)
	await _place(Vector3(0, 8, 5))
	_check(_ray(Vector3(0, 8, 5), Vector3(0, 2, 5)).is_empty(), "uncreated growth bridge has no collision")
	await _place(Vector3(11, 4, 18))
	var rejected: int = session.stats.rejected_abilities
	_cast("growth", growth_id)
	_check(session.stats.rejected_abilities == rejected + 1 and session.entities[growth_id].growth == 0.0, "growth cannot create bridge without light")
	_cast("light", growth_id)
	_cast("growth", growth_id)
	_cast("growth", growth_id)
	session.world.synchronize(session.entities, 0.0)
	await _settle()
	_check(float(session.entities[growth_id].growth) >= 0.5 and session.world.growth_bridge.visible, "light and growth create visible bridge state")
	var growth_hit := _ray(Vector3(0, 8, 5), Vector3(0, 2, 5))
	_check(not growth_hit.is_empty() and growth_hit.collider == session.world.growth_bridge, "grown bridge is registered in real physics space")
	await _place(Vector3(0, 8, 5))
	var landing = session.players[1].move_and_collide(Vector3(0, -6, 0))
	_check(landing != null and landing.get_collider() == session.world.growth_bridge and session.players[1].position.y > 5.25, "grown bridge supports actual drone collision")

func _reset_gate_inputs() -> void:
	for key in ["relay", "thermal", "beacon"]:
		var id: String = str(session.region_id) + ":" + str(key)
		session.entities[id] = session.world.definitions[id].duplicate(true)
	session.world.restored_gate = false
	session.world.gate_fraction = 0.0
	session.world.synchronize(session.entities, 0.0)
	session.entities["player:1"].energy = 100.0

func _assert_gate_route(route: String) -> void:
	session.world.synchronize(session.entities, 2.0)
	await _settle()
	_check(session.world.gate_open and is_equal_approx(session.world.gate_fraction, 1.0), route + " opens actual gate body", {"fraction": session.world.gate_fraction})
	var passage: Array[Vector3] = session.world.gate_passage()
	_check(_ray(passage[0], passage[1]).is_empty(), route + " clears the collision passage")

func _test_gate_routes() -> void:
	_reset_gate_inputs()
	await _place(Vector3(-14, 2, 21))
	var passage: Array[Vector3] = session.world.gate_passage()
	var closed := _ray(passage[0], passage[1])
	_check(not closed.is_empty() and closed.collider == session.world.gate, "closed gate really blocks passage")
	_cast("charge", "I1:relay")
	await _assert_gate_route("charge")
	_reset_gate_inputs()
	await _place(Vector3(-29, 2, 12))
	_cast("heat", "I1:thermal")
	session.world.synchronize(session.entities, 0.0)
	_check(not session.world.gate_open, "one heat application below threshold does not open gate")
	_cast("heat", "I1:thermal")
	await _assert_gate_route("heat")
	_reset_gate_inputs()
	await _place(Vector3(25, 4, 32))
	_cast("takeover", "I1:beacon")
	await _assert_gate_route("takeover")
	_reset_gate_inputs()

func _test_boss_cover_and_damage() -> void:
	await _place(Vector3(14, 5, -20))
	session._start_boss()
	_check(session.boss_active, "real session starts whale encounter")
	var body = session.players[1]
	var health_before: float = body.health
	var damage_before: float = body.damage_taken
	session._telegraph("low_sweep", 2.0)
	session._boss_attack("low_sweep")
	_check(body.health < health_before and body.damage_taken > damage_before, "unobstructed boss attack applies real combat damage", {"before": health_before, "after": body.health})
	await _place(Vector3(31, 5, 1))
	var origin: Vector3 = session.world.boss_attack_origin()
	var cover_query := PhysicsRayQueryParameters3D.create(origin, body.global_position, 1 | 8)
	var excluded: Array[RID] = [body.get_rid()]
	for part in session.world.boss_collision_bodies():
		excluded.append(part.get_rid())
	cover_query.exclude = excluded
	var terrain_hit: Dictionary = session.get_world_3d().direct_space_state.intersect_ray(cover_query)
	_check(not terrain_hit.is_empty() and str(terrain_hit.collider.get_meta("entity_id", "")) == "", "boss cover setup hits ordinary terrain", {"collider": str(terrain_hit.get("collider", "none"))})
	health_before = body.health
	session._telegraph("low_sweep", 2.0)
	session._boss_attack("low_sweep")
	_check(is_equal_approx(body.health, health_before), "terrain blocks boss damage", {"before": health_before, "after": body.health, "bug_site_if_failed": "scripts/v3/twin_session.gd:_line_clear empty target_id matched missing metadata"})

func _boss_only(state: Dictionary) -> Dictionary:
	var result := state.duplicate(true)
	result.erase("players")
	return result

func _test_boss_warning_contract() -> void:
	await _place(Vector3(14, 5, -20))
	session._telegraph("low_sweep", 2.0)
	var warning = session.world.boss_warnings[1]
	_check(warning.radius == 2.5 and warning.limits.y == 7.0, "actual warning node exposes exact low-pulse radius and safe altitude")
	var all_rings_match := true
	for child in warning.get_children():
		if child is MeshInstance3D and child.mesh is TorusMesh:
			all_rings_match = all_rings_match and child.mesh.outer_radius == 2.5
	_check(all_rings_match, "all visible warning rings end at the authoritative 2.5m boundary")
	await _place(Vector3(17, 5, -20))
	var health: float = session.players[1].health
	session._boss_attack("low_sweep")
	_check(session.players[1].health == health, "real low-pulse attack cannot hurt a pilot 3m outside a 2.5m warning")
	await _place(Vector3(14, 7, -20))
	session._boss_attack("low_sweep")
	_check(session.players[1].health == health, "reaching the displayed 7m ceiling evades real low pulse")
	await _place(Vector3(14, 8, -20))
	session._telegraph("high_lance", 2.0)
	await _place(Vector3(14, 10.5, -20))
	session._boss_attack("high_lance")
	_check(session.players[1].health == health, "2.5m altitude change evades real high lance")
	await _place(Vector3(14, 9, -20))
	session._boss_attack("high_lance")
	_check(session.players[1].health < health, "remaining inside high-lance height band still takes real damage")
	session._restore_player(1, Vector3(14, 5, -20))
	_freeze_players()
	await _settle()
	session._telegraph("tractor", 2.0)
	health = session.players[1].health
	session.players[1].command = {"brake":true}
	session._boss_attack("tractor")
	_check(session.players[1].health == health, "brake prevents real tractor damage inside its 3.5m mark")
	session.players[1].command = {"brake":false}
	session._boss_attack("tractor")
	_check(session.players[1].health < health, "same tractor position without braking takes damage")
	# Restore the actual current state telegraph before producing a join snapshot.
	session._telegraph("low_sweep", 1.4)
	var packet: Dictionary = session._snapshot()
	packet.paused = true
	session.world.show_boss_warning("", {}, 0.0)
	session.network.mode = "guest"
	session.received_session = ""
	session.received_sequence = -1
	session._apply_snapshot(packet)
	_check(session.world.boss_warnings.has(1) and session.world.boss_warnings[1].radius == 2.5 and session.players[1].freeze, "paused reconnect snapshot restores the real warning without an old effect event")
	session.network.mode = "solo"
	session.world.local_authority = true
	session.simulation_paused = false
	_freeze_players()
	session._guest_joined(2, "qa_physics_late_warning")
	_freeze_players()
	await _place(Vector3(16, 5, -20), 2)
	var guest_health: float = session.players[2].health
	session._boss_attack("low_sweep")
	_check(session.players[2].health == guest_health, "mid-windup join cannot be hit by an unseen personal mark")
	session._telegraph("low_sweep", 1.0)
	_check(session.world.boss_warnings.has(2), "next windup gives the joined pilot an actual mark")
	session.simulation_paused = true
	session._guest_left(2)
	_check(not session._boss_target_positions.has(2) and not session.world.boss_warnings.has(2) and not session._snapshot().boss_marks.has(2), "paused disconnect immediately removes departed mark from host and next snapshot")
	session.simulation_paused = false
	session._restore_player(1, Vector3(14, 5, -20))
	_freeze_players()
	await _settle()
	session.encounter.advance(2.7)
	session._sync_boss_entities()
	# The authored side pod has a solid forward intake; use its actual top opening.
	var firing_at: Vector3 = session.world.boss_parts.port.global_position + Vector3.UP * 5
	await _place(firing_at)
	session.locks[1] = "boss:port"
	var shots: int = session.stats.shots
	var abilities: int = session.stats.abilities
	var node_health: float = session.encounter.get_state().nodes.port.health
	session._fire(1)
	session._action_received(1, "ability", {"ability":"blink", "point":firing_at + Vector3(0, 0, 2)})
	_check(session.stats.shots == shots + 1 and session.encounter.get_state().nodes.port.health < node_health, "real shot damages an open boss compartment")
	_check(session.stats.abilities == abilities + 1 and session.players[1].position.is_equal_approx(firing_at + Vector3(0, 0, 2)), "real firing and blink both succeed in the same combat interval")
	session.encounter.reset_attempt("qa_warning_complete")
	session._sync_boss_entities()

func _test_boss_membership_and_wipe() -> void:
	session.encounter.advance(2.7)
	session.encounter.set_node_power("port", false, "1")
	session.encounter.set_node_power("starboard", false, "1")
	session.encounter.hit_part("core", 65.0, "1")
	session.encounter.advance(2.7)
	session.encounter.hit_part("port", 12.0, "1")
	session._sync_boss_entities()
	var before := _boss_only(session.encounter.get_state())
	session._guest_joined(2, "qa_physics_guest")
	_freeze_players()
	await _settle()
	_check(session.players.has(2) and session.players[2].enabled and session.players[2].health == session.players[2].maximum_health, "session join spawns healthy real body")
	_check(_boss_only(session.encounter.get_state()) == before, "session join preserves boss damage nodes phase and attempt")
	session._guest_left(2)
	await _settle()
	_check(not session.players.has(2) and _boss_only(session.encounter.get_state()) == before, "session leave preserves ongoing boss attempt")
	session._guest_joined(2, "qa_physics_guest")
	_freeze_players()
	await _settle()
	_check(_boss_only(session.encounter.get_state()) == before, "session reconnect preserves ongoing boss attempt")
	var personal_before: Dictionary = session.store.snapshot().personal.duplicate(true)
	var attempt_before: int = session.encounter.get_state().attempt
	session.entities["I1:crate"].pinned = true
	session.entities["I1:crate"].field_remaining = 4.0
	session.entities["player:1"].decoy_remaining = 6.0
	for peer in [1, 2]:
		var pilot = session.players[peer]
		pilot.apply_combat_hit(10000.0, Vector3.UP, pilot.global_position, "pulse", {"source": "qa_physics_lethal"})
		_check(not pilot.enabled and pilot.health <= 0.0, "lethal actual combat hit downs peer " + str(peer))
		# Advance the real body crash lifecycle; it emits the production disabled signal.
		pilot._process(2.2)
		if peer == 1:
			_check(session.encounter.get_state().players["1"].downed and session.encounter.get_state().attempt == attempt_before, "first down waits for partner instead of resetting")
	_freeze_players()
	await _settle()
	var reset: Dictionary = session.encounter.get_state()
	_check(reset.attempt == attempt_before + 1 and reset.core_health == 120.0 and not reset.overdrive and reset.nodes.port.powered and reset.nodes.starboard.powered, "production full wipe restores full boss attempt")
	for peer in [1, 2]:
		var pilot = session.players[peer]
		var expected: Vector3 = session.world.boss_retry_position(peer - 1)
		_check(pilot.enabled and pilot.health == pilot.maximum_health and pilot.position.is_equal_approx(expected), "full wipe restores healthy peer at entrance " + str(peer), {"position": str(pilot.position)})
	_check(not session.entities["I1:crate"].get("pinned", false) and not session.entities["player:1"].has("decoy_remaining"), "full wipe clears transient arena and actor effects")
	_check(session.store.snapshot().personal == personal_before, "full wipe does not deduct or rewrite owned personal assets")

func _test_boss_victory_warning_cleanup() -> void:
	session.encounter.advance(2.7)
	session.encounter.set_node_power("port", false, "1")
	session.encounter.set_node_power("starboard", false, "1")
	session.encounter.hit_part("core", 65.0, "1")
	session.encounter.advance(2.7)
	session.encounter.set_node_power("port", false, "1")
	session.encounter.set_node_power("starboard", false, "1")
	session.encounter.hit_part("core", 54.0, "1")
	session._sync_boss_entities()
	await _place(session.entities["boss:core"].position + Vector3(0, 2, 7))
	session._telegraph("high_lance", 1.2)
	_check(not session.world.boss_warnings.is_empty(), "victory cleanup fixture has a live visible attack warning")
	session.locks[1] = "boss:core"
	session.weapon_cooldowns[1] = 0.0
	session._fire(1)
	_check(not session.boss_active and not session.pending_completion and session.store.snapshot().world.flags.get("I1_boss", false), "real final shot commits boss victory")
	_check(session.world.boss_warnings.is_empty() and session._boss_target_positions.is_empty() and session._snapshot().boss_marks.is_empty(), "victory immediately clears host warning and guest snapshot even before next physics frame")

func _finish() -> void:
	var failed := checks.filter(func(item): return not item.passed)
	var report := {
		"suite": "session_physics", "profile": profile, "status": "passed" if failed.is_empty() else "failed",
		"checks": checks, "check_count": checks.size(), "failure_count": failed.size(),
		"elapsed_ms": Time.get_ticks_msec() - started_at,
		"evidence": "scripted actual SceneTree + PhysicsServer + production session adapters",
		"not_evidence_for": ["real LAN", "human play", "rendered image quality", "performance", "controller comfort"]
	}
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(report_path.get_base_dir()))
	var file := FileAccess.open(report_path, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(report, "\t"))
		file.close()
	print("SESSION_PHYSICS_RESULT ", JSON.stringify({"checks": checks.size(), "failures": failed.size(), "report": report_path}))
	if is_instance_valid(session):
		# Allow production warning/beam timers to finish before destroying their
		# captured nodes. This suite tests gameplay adapters, not abrupt scene teardown.
		await create_timer(2.3).timeout
		session.network.close()
		session.queue_free()
	await process_frame
	quit(0 if failed.is_empty() else 1)
