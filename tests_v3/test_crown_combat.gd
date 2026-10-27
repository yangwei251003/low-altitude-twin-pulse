extends SceneTree
## Real GLB/physics/session/store regression. Pilot placements and prior-story
## reducer events are fixtures, not a human playthrough or timing measurement.
const Session = preload("res://scripts/v3/twin_session.gd")
const Crown = preload("res://scripts/v3/gameplay/twin_crown_encounter.gd")
const Fixtures = preload("res://tests_v3/test_crown_action_data.gd")
const WEST = "F1:crown_host_west"
const CORE = "boss:crown_core"
var session
var profile = ""
var checks: Array = []
var failures: Array = []
var routes: Array = []

func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--qa-profile="): profile = arg.trim_prefix("--qa-profile=")
	if not profile.begins_with("qa_crowncombat_") or profile != profile.validate_filename() or DirAccess.dir_exists_absolute("user://profiles_v3/" + profile):
		push_error("A fresh isolated qa_crowncombat_<unique> profile is required")
		quit(2)
		return
	_run.call_deferred()

func check(ok: bool, label: String, detail: Dictionary = {}) -> void:
	checks.append({"name":label, "passed":ok, "detail":detail})
	if not ok:
		failures.append(label)
		push_error("CROWN COMBAT: " + label + " " + JSON.stringify(detail))

func settle() -> void:
	await physics_frame
	await physics_frame
	await process_frame

func quiet() -> void:
	session.set_process(false)
	session.set_physics_process(false)
	session.inputs.set_process(false)
	session.inputs.set_physics_process(false)
	for body in session.players.values():
		body.freeze = true
		body.set_process(false)
		body.set_physics_process(false)
		body.linear_velocity = Vector3.ZERO

func place(at: Vector3, peer: int = 1) -> void:
	var body = session.players[peer]
	body.global_position = at
	body.force_update_transform()
	PhysicsServer3D.body_set_state(body.get_rid(), PhysicsServer3D.BODY_STATE_TRANSFORM, body.global_transform)
	body.linear_velocity = Vector3.ZERO
	body.hold_height = at.y
	session.entities[session._actor_id(peer)].position = at
	await settle()

func clear_body(at: Vector3, peer: int = 1) -> bool:
	var body = session.players[peer]
	var query = PhysicsShapeQueryParameters3D.new()
	var shape = BoxShape3D.new()
	shape.size = Vector3(body.stats.width_m, body.stats.height_m, body.stats.length_m)
	query.shape = shape
	query.transform = Transform3D(Basis.IDENTITY, at)
	query.exclude = [body.get_rid()]
	query.collision_mask = 1 | 2 | 8 | 32
	return session.get_world_3d().direct_space_state.intersect_shape(query, 1).is_empty()

func visible_spot(at: Vector3, target: String, radius: float = 2.5) -> Vector3:
	if not at.is_finite(): return Vector3.INF
	for dy in [0.0, 0.5, -0.5, 1.2]:
		for step in range(16):
			var angle = TAU * float(step) / 16
			var point = at + Vector3(sin(angle), dy, cos(angle)).normalized() * radius
			if clear_body(point) and session._line_clear(point, at, session.players[1].get_rid(), target): return point
	return Vector3.INF

func use(ability: String, target: String, mode: String = "") -> void:
	session.cooldowns[1] = 0.0
	session._use_ability(1, {"ability":ability, "target_id":target, "mode":mode})

func advance(seconds: float) -> void:
	var remaining = seconds
	while remaining > 0.000001:
		var delta = minf(0.1, remaining)
		session.crown.advance(delta)
		remaining -= delta
	await settle()

func _run() -> void:
	session = Session.new()
	root.add_child(session)
	check(session.profile_ready and session.start_flight("solo"), "production solo opens isolated profile")
	quiet()
	session._load_region("F1")
	await settle()
	check(session.crown.ready(), "real crown and all six rootstone modules import", {"missing":session.world.crown_arena.missing})
	if not session.crown.ready():
		finish()
		return
	await _test_geometry()
	await _test_spore_source()
	await _test_story_start()
	if session.boss_active:
		await _test_routes_and_retry()
		await _test_damage_preview()
		await _test_pollen_height_and_timing()
		await _test_approved_route_obstruction()
		await _test_victory_and_inspection()
	finish()

func _test_geometry() -> void:
	var arena = session.world.crown_arena
	await place(arena.retry_position(0))
	check(clear_body(arena.retry_position(0)) and clear_body(arena.retry_position(1)), "both entry bodies clear actual root arch and terrain")
	var definitions: Dictionary = arena.definition
	for spec in definitions.anchors:
		var point: Vector3 = arena.host_position(spec.id)
		var spot = visible_spot(point, spec.id)
		check(spot.is_finite(), "actual host target reachable with clear body and ray: " + str(spec.id), {"target":str(point), "spot":str(spot)})
		for destination in definitions.anchors:
			if spec.id == destination.id: continue
			var from: Vector3 = arena.vector(spec.body_position)
			var to: Vector3 = arena.vector(destination.body_position)
			var points: Array = Crown.build_route([roundi(from.x * 1000), roundi(from.y * 1000), roundi(from.z * 1000)], [roundi(to.x * 1000), roundi(to.y * 1000), roundi(to.z * 1000)], roundi(maxf(from.y, to.y) * 1000) + 3000)
			var result: Dictionary = arena.motion_result(points)
			routes.append({"source":spec.id, "target":destination.id, "result":result})
			check(result.clear, "whole articulated body clears migration " + str(spec.id) + " to " + str(destination.id), result)
		var falling: Array = Crown.build_route([roundi(spec.body_position[0]*1000), roundi(spec.body_position[1]*1000), roundi(spec.body_position[2]*1000)], [roundi(spec.fall_position[0]*1000), roundi(spec.fall_position[1]*1000), roundi(spec.fall_position[2]*1000)], roundi(maxf(spec.body_position[1]+2, spec.fall_via_position[1])*1000))
		var fall_result: Dictionary = arena.motion_result(falling)
		routes.append({"source":spec.id, "target":"fall", "result":fall_result})
		check(fall_result.clear, "whole articulated body clears ejection " + str(spec.id), fall_result)
		var fall_world: Vector3 = arena.to_global(arena.body_position(spec.fall_position))
		for limb in ["FL", "FR", "BL", "BR"]:
			var contact: Node3D = arena.model.visual.find_child("ClawContact_" + limb, true, false)
			check(contact != null, "actual limb contact anchor exists: " + limb)
			if contact == null: continue
			var foot = fall_world + arena.model.to_local(contact.global_position)
			var query = PhysicsRayQueryParameters3D.create(foot + Vector3.UP * 0.2, foot - Vector3.UP * 0.2, 1)
			var hit = session.get_world_3d().direct_space_state.intersect_ray(query)
			check(not hit.is_empty() and absf(hit.position.y - (foot.y - arena.BODY_CLEARANCE)) < 0.03, "actual landing claw has support below physical clearance: " + str(spec.id) + ":" + limb, {"foot":str(foot), "hit":str(hit.get("position", Vector3.INF))})
	check(arena.model.position.is_equal_approx(arena.body_position(definitions.anchors[0].body_position)), "rendered body and colliders use the exact same clearance mapping as sweep queries")

func _test_story_start() -> void:
	var at: Vector3 = session.world.crown_arena.host_position(WEST)
	var spot = visible_spot(at, WEST)
	if not spot.is_finite(): return
	await place(spot)
	session.story.observe(0.3)
	check(not session.boss_active, "unbriefed approach cannot start campaign crown")
	var state: Dictionary = session.story.director.default_state()
	for row in Fixtures.LEGACY_EVENTS:
		var result: Dictionary = session.story.director.apply_event(state, {"id":"fixture:" + row[0], "type":row[1], "target_id":row[2], "option":row[3]}, {"is_authority":true, "validated":true, "region_id":str(row[0]).get_slice(":", 0)})
		if not result.get("changed", false):
			check(false, "legacy fixture reducer transition " + str(row[0]))
			return
		state = result.state
	check(session._commit("qa_prior_story", {"world.actions.opening":state}), "prior nineteen reducer objectives seeded in isolated store")
	session.story.load_world()
	await place(Vector3(0, 11, 0))
	session.interface.clear_dialogue()
	session.story.interact(1, {"target_id":"F1:crown_briefing"})
	check("F1:crown:brief" in session.story.state.completed, "root-arch briefing validates real position and sight")
	await place(spot)
	var body = session.players[1]
	body.health = body.maximum_health * 0.5
	body.damage_state.health = body.health
	session.story.observe(0.3)
	check(session.boss_active and session.boss_campaign, "briefed physical approach starts crown campaign")
	if session.boss_active:
		check(absf(session.crown.encounter.get_state().players["player:1"].health - body.health) < 0.001, "entry preserves half-health physical pilot")
		check("F1:crown:engage" in session.story.state.completed, "started fact follows successful encounter start")

func wall_at(at: Vector3) -> StaticBody3D:
	var wall = StaticBody3D.new()
	wall.collision_layer = 1
	wall.collision_mask = 0
	var shape = BoxShape3D.new()
	shape.size = Vector3.ONE * 0.55
	var collider = CollisionShape3D.new()
	collider.shape = shape
	wall.add_child(collider)
	session.world.add_child(wall)
	wall.global_position = at
	return wall

func _test_spore_source() -> void:
	var arena = session.world.crown_arena
	var attack = {"kind":"burning_spores", "anchor_id":WEST}
	var source: Vector3 = arena.attack_origin(attack)
	var point = source + Vector3(0, 1.5, 5)
	var old_view: Dictionary = arena.last_view.duplicate(true)
	var old_position: Vector3 = arena.model.position
	arena.apply_view({"type":"parasitic_crown", "position":Vector3(25, 20, 25), "core_open":false})
	await settle()
	check(arena.attack_origin(attack).is_equal_approx(source), "burning source remains at actual host after crown moves")
	check(arena.attack_line_clear(attack, point, session.players[1].get_rid()), "host-front spore ray has real initial clearance")
	var false_source = arena.attack_origin({"kind":"root_pollen"})
	var unrelated = wall_at(false_source.lerp(point, 0.5))
	await settle()
	check(arena.attack_line_clear(attack, point, session.players[1].get_rid()), "wall on remote crown ray does not block old host spores")
	var blocking = wall_at(source.lerp(point, 0.5))
	await settle()
	check(not arena.attack_line_clear(attack, point, session.players[1].get_rid()), "wall on actual host ray blocks old host spores")
	unrelated.free()
	blocking.free()
	arena.apply_view(old_view)
	check(arena.model.position.is_equal_approx(old_position), "source regression restores production pose")

func _test_routes_and_retry() -> void:
	var arena = session.world.crown_arena
	var core: Vector3 = arena.core_position()
	check(not session._line_clear(core + Vector3(0, 0, 9), core, session.players[1].get_rid(), CORE), "closed real plates stop frontal core ray")
	var energy = float(session.entities["player:1"].energy)
	use("light", WEST)
	use("growth", WEST)
	check(session.crown.encounter.get_state().mode == "bound", "real host rays and light-growth transaction open crown")
	check(is_equal_approx(float(session.entities["player:1"].energy), energy - 17), "two abilities consume their costs once")
	check(visible_spot(arena.core_position(), CORE, 7.0).is_finite(), "open real plates expose shootable core")
	var saved_growth = session.entities["F1:growth"].get("growth", 0.0)
	session.crown.retry()
	quiet()
	await settle()
	check(session.players[1].global_position.distance_to(arena.retry_position(0)) < 0.01 and session.players[1].health == session.players[1].maximum_health, "whole retry restores resources at independent safe entry")
	check(session.entities["F1:growth"].get("growth", 0.0) == saved_growth and "F1:crown:brief" in session.story.state.completed, "retry preserves prior mechanism and story progress")
	await place(visible_spot(arena.host_position(WEST), WEST))
	use("heat", WEST)
	use("heat", WEST)
	var state: Dictionary = session.crown.encounter.get_state()
	check(state.mode == "migration_warning" and state.movement.get("approved", false), "two real heat operations request physically approved ejection")
	await advance(3.1)
	state = session.crown.encounter.get_state()
	check(state.mode == "fallen" and state.core_open, "ejection reaches actual low ledge and opens core")
	check(arena.model.global_position.distance_to(arena.to_global(arena.body_position(arena.definition.anchors[0].fall_position))) < 0.01, "model and pure fallen positions agree")
	session.crown.retry()
	quiet()
	await settle()

func _test_damage_preview() -> void:
	var body = session.players[1]
	var before: Dictionary = body.damage_snapshot()
	var preview: Dictionary = body.preview_combat_hit(24, Vector3.FORWARD, body.global_position)
	check(not preview.is_empty() and before == body.damage_snapshot(), "real airframe damage preview changes no armor or components")
	var receipt: Dictionary = body.apply_combat_hit(24, Vector3.FORWARD, body.global_position)
	check(is_equal_approx(receipt.damage, preview.damage) and is_equal_approx(receipt.armor, preview.armor), "single physical damage settlement exactly matches preview")
	session._restore_player(1, session.world.crown_arena.retry_position(0))
	quiet()
	# Exercise the adapter itself, including armor and component receipts. The
	# earlier preview comparison alone cannot prove duplicate attacks settle once.
	var arena = session.world.crown_arena
	var target = Vector3(0, 8, -18)
	check(clear_body(target), "low attack fixture has clear real pilot volume")
	await place(target)
	var before_hit: Dictionary = body.damage_snapshot()
	await advance(5.1)
	var after_hit: Dictionary = body.damage_snapshot()
	var state: Dictionary = session.crown.encounter.get_state()
	check(int(after_hit.serial) == int(before_hit.serial) + 1 and body.health < float(before_hit.health), "production attack applies armor and damage exactly once", {"before":before_hit, "after":after_hit})
	check(absf(state.players["player:1"].health - body.health) < 0.001, "pure and physical health agree after protected production hit")
	session.crown._apply_attacks()
	session.crown._apply_attacks()
	check(body.damage_snapshot() == after_hit, "repeated active token changes no armor, component serial or health")
	session.crown.retry()
	quiet()
	await settle()

func _test_approved_route_obstruction() -> void:
	var arena = session.world.crown_arena
	await place(visible_spot(arena.host_position(WEST), WEST))
	use("heat", WEST)
	use("heat", WEST)
	var state: Dictionary = session.crown.encounter.get_state()
	check(state.mode == "migration_warning" and state.movement.get("approved", false), "route approved before late pilot obstruction")
	if not state.movement.get("approved", false): return
	var waypoint: Vector3 = arena.to_global(arena.body_position(arena.vector(state.movement.points_mm[2]) / 1000.0))
	var core_offset: Vector3 = arena.model.to_local(arena.model.core_position())
	session._spawn_player(2, "qa_crown_route_obstruction", waypoint + core_offset)
	quiet()
	await place(waypoint + core_offset, 2)
	var last_safe: Array = state.position_mm.duplicate()
	for step in range(35):
		await advance(0.1)
		state = session.crown.encounter.get_state()
		if state.mode == "unrooted": break
		last_safe = state.position_mm.duplicate()
	check(state.mode == "unrooted" and state.core_open and state.movement.is_empty(), "late actual pilot obstruction interrupts approved movement safely", {"mode":state.mode, "position":state.position_mm})
	check(state.position_mm == last_safe and arena.model.global_position.distance_to(arena.to_global(arena.body_position(arena.vector(last_safe) / 1000.0))) < 0.001, "rejected candidate never moves rendered or physical crown beyond last safe pose")
	check(session.players[2].enabled, "route rejection does not crush the intervening pilot")
	session._guest_left(2)
	await settle()
	session.crown.retry()
	quiet()
	await settle()

func _test_pollen_height_and_timing() -> void:
	var arena = session.world.crown_arena
	var body = session.players[1]
	var locked := Vector3(3, 27, -21)
	var cases := [locked, locked + Vector3(4.0, 0, 0), locked - Vector3(0, 4.1, 0)]
	for index in cases.size():
		session.crown.retry()
		quiet()
		await place(locked)
		check(clear_body(locked), "27m pollen fixture clears actual imported geometry")
		await advance(10.0)
		var state: Dictionary = session.crown.encounter.get_state()
		var attack: Dictionary = state.attack
		check(not attack.is_empty() and attack.shapes.size() == 1 and attack.shapes[0].kind == "cylinder" and not attack.fired, "production adapter publishes second attack warning before the migration deadline")
		if attack.is_empty(): return
		var warned: Array = attack.shapes.duplicate(true)
		await place(cases[index])
		check(clear_body(cases[index]) and arena.attack_line_clear(attack, body.global_position, body.get_rid()), "real high route has body and attack ray clearance: " + str(index))
		var before: float = body.health
		await advance(2.0)
		state = session.crown.encounter.get_state()
		check(state.mode == "attached" and state.attack.get("fired", false) and state.attack.get("shapes", []) == warned, "actual attack survives 12s deadline and retains its warned position")
		if index == 0:
			check(body.health < before and is_equal_approx(state.players["player:1"].health, body.health), "stationary 27m pilot receives one real armor-resolved hit")
		else:
			check(is_equal_approx(body.health, before), "moving outside the warned volume avoids actual damage: " + str(index))
		var after: Dictionary = body.damage_snapshot()
		await advance(0.5)
		check(body.damage_snapshot() == after, "pollen does not resettle armor or chase the escaped pilot")
	session.crown.retry()
	quiet()
	await settle()

func _test_victory_and_inspection() -> void:
	var arena = session.world.crown_arena
	await place(visible_spot(arena.host_position(WEST), WEST))
	use("light", WEST)
	use("growth", WEST)
	var maximum_steps = 90
	session.store.failure_point = "before_publish"
	for step in range(maximum_steps):
		if session.pending_completion: break
		var state: Dictionary = session.crown.encounter.get_state()
		if state.core_open:
			var spot = visible_spot(arena.core_position(), CORE, 7.0)
			if not spot.is_finite():
				check(false, "core has a valid physical firing spot during window")
				break
			await place(spot)
			session.locks[1] = CORE
			session.weapon_cooldowns[1] = 0
			session._fire(1)
		elif state.mode == "attached":
			var spot = visible_spot(arena.host_position(state.anchor_id), state.anchor_id)
			if not spot.is_finite(): break
			await place(spot)
			use("light", state.anchor_id)
			use("growth", state.anchor_id)
		await advance(0.3)
	check(session.pending_completion and session.boss_active and not session.story.crown_victory_committed(), "actual shots finish both phases but failed save keeps victory pending")
	# A teammate may already have emitted disabled before victory, so there is
	# no later disabled signal available to rescue them outside the encounter.
	session._spawn_player(2, "qa_crown_downed_teammate", arena.retry_position(1))
	quiet()
	var teammate = session.players[2]
	teammate.health = 0.0
	teammate.damage_state.health = 0.0
	teammate.enabled = false
	teammate.crash_reported = true
	session.store.failure_point = ""
	session._finish_boss()
	check(not session.boss_active and session.story.crown_victory_committed(), "retry publishes independent crown victory")
	check(teammate.enabled and is_equal_approx(teammate.health, teammate.maximum_health * 0.4) and is_equal_approx(teammate.damage_state.health, teammate.health) and teammate.global_position.distance_to(arena.retry_position(1)) < 0.01, "saved victory rescues already-disabled teammate at safe entry with forty percent health")
	session._guest_left(2)
	check(session.store.snapshot().personal.discoveries.count("boss:F1:parasitic_crown") == 1 and session.store.snapshot().personal.discoveries.count("boss:F1:harbor_whale") == 0, "crown awards exactly its own identity")
	session.story.observe(0.3)
	check("F1:crown:disable" in session.story.state.completed and "F1:crown:restore" not in session.story.state.completed, "victory does not auto-complete recovered-host inspection")
	var spot = visible_spot(arena.host_position(WEST), WEST)
	if spot.is_finite():
		await place(spot)
		session.interface.clear_dialogue()
		session.story.interact(1, {"target_id":"F1:crown_recovered"})
	check("F1:crown:restore" in session.story.state.completed, "explicit recovered-host inspection completes sixth action")
	var before = session.store.snapshot()
	session.story.interact(1, {"target_id":"F1:crown_recovered"})
	check(before == session.store.snapshot(), "repeated recovered inspection creates no duplicate reward or commit")
	check(session.start_flight("solo"), "saved campaign reloads into production session")
	quiet()
	session._load_region("F1")
	await settle()
	check(session.story.crown_victory_committed() and "F1:crown:restore" in session.story.state.completed and session.world.crown_defeated, "disk reload restores stopped crown and completed action")

func finish() -> void:
	var path = "res://artifacts/v3/crown-combat-" + profile + ".json"
	var file = FileAccess.open(path, FileAccess.WRITE)
	if file: file.store_string(JSON.stringify({"checks":checks, "failures":failures, "routes":routes, "scope":"real assets, physics, host ability/fire adapter and isolated store; fixture placements/prior story, no LAN/render/performance/human difficulty acceptance"}, "\t"))
	print("V3_CROWN_COMBAT ", JSON.stringify({"checks":checks.size(), "failures":failures, "report":path}))
	if is_instance_valid(session):
		session.store.failure_point = ""
		session.network.close()
		session.free()
	quit(0 if failures.is_empty() else 1)
