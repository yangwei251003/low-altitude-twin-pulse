extends SceneTree
## Real production session, imported art wrappers, flight envelopes and physics sweeps.
## Requires a fresh qa_art profile; no real saves or existing QA saves are touched.

const MAIN = preload("res://scenes/v3/main.tscn")
const Store = preload("res://scripts/v3/core/twin_world_store.gd")
const REPORT = "res://artifacts/v3/art/integration-report.json"
const HASH_PATHS = [
	"res://scripts/v3/twin_session.gd", "res://scripts/v3/twin_test_world.gd",
	"res://scripts/v3/art/twin_service_bridge.gd", "res://scripts/v3/art/twin_temple_gate.gd",
	"res://scripts/v3/gameplay/twin_ability_rules.gd", "res://scripts/v2/flight_body.gd",
	"res://assets/v3/industrial/service_bridge.glb", "res://assets/v3/fantasy/temple_gate.glb",
	"res://tests_v3/test_art_integration.gd"
]
var session
var profile = ""
var started_utc = ""
var case_name = "setup"
var checks: Array[Dictionary] = []
var failures: Array[String] = []
var frames: Dictionary = {}

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--qa-profile="): profile = arg.trim_prefix("--qa-profile=")
		if arg.begins_with("--qa-network="):
			print("REFUSED: art regression must not enable automatic network flight")
			quit(2)
			return
	if not profile.begins_with("qa_art_") or profile != profile.validate_filename():
		print("REFUSED: use a fresh --qa-profile=qa_art_<unique>")
		quit(2)
		return
	if DirAccess.dir_exists_absolute("user://profiles_v3/" + profile):
		print("REFUSED: existing QA profile must not be reused")
		quit(2)
		return
	started_utc = Time.get_datetime_string_from_system(true) + "Z"
	session = MAIN.instantiate()
	root.add_child(session)
	_check(session.profile_ready, "production session bootstraps isolated profile")
	if not session.profile_ready:
		_finish()
		return
	_check(session.store.root_path == "user://profiles_v3/" + profile, "explicit QA profile is the only profile in use")
	_check(session.start_flight("solo"), "production session starts solo")
	# Control action/animation timing, while keeping PhysicsServer and its collision
	# shapes live. No synthetic collider stands in for the player's flight envelope.
	session.set_process(false)
	session.set_physics_process(false)
	session.inputs.set_process(false)
	session.inputs.set_physics_process(false)
	_freeze()
	await _settle()
	await _test_industrial()
	await _test_fantasy_hole()
	await _test_light_and_growth()
	await _test_snapshot_authority()
	await _test_durable_pose_restore()
	_finish()

func _check(passed: bool, label: String, detail: Dictionary = {}) -> void:
	checks.append({"case":case_name, "name":label, "passed":passed, "detail":detail})
	if not passed:
		failures.append(case_name + ": " + label)
		push_error("ART REGRESSION: " + label + " " + JSON.stringify(detail))

func _case(value: String) -> void:
	case_name = value
	print("ART_CASE " + value)

func _freeze() -> void:
	for body in session.players.values():
		body.freeze = true
		body.set_process(false)
		body.set_physics_process(false)
		body.command = {"active":false, "brake":true}
		body.linear_velocity = Vector3.ZERO
		body.angular_velocity = Vector3.ZERO

func _settle() -> void:
	await physics_frame
	await physics_frame
	await process_frame

func _place(at: Vector3) -> void:
	var body = session.players[1]
	body.freeze = true
	body.global_transform = Transform3D(Basis.IDENTITY, at)
	body.hold_height = at.y
	body.linear_velocity = Vector3.ZERO
	body.angular_velocity = Vector3.ZERO
	session.entities["player:1"].position = at
	await _settle()

func _frame(id: String) -> void:
	var body = session.players[1]
	body.configure(CatalogV2.resolve_build(CatalogV2.default_build(id)))
	_freeze()
	session._register_player_entity(1)
	await _settle()
	var bounds: Vector3 = body.get_node("Envelope").shape.size
	frames[id] = {"airframe":body.build.airframe_id, "envelope":_vector(bounds), "body_class":body.get_script().resource_path}
	_check(body.build.airframe_id == id, id + " uses CatalogV2 default build on real FlightBodyV2", frames[id])
	_check(bounds.x > 1.0 and bounds.y > 0.2 and bounds.z > 1.0, id + " has full three-dimensional flight collision envelope")

func _cast(ability: String, target: String, mode: String = "") -> void:
	session.cooldowns[1] = 0.0
	session._action_received(1, "ability", {"ability":ability, "target_id":target, "mode":mode})

func _advance(seconds: float) -> void:
	var count = maxi(1, ceili(seconds * 60.0))
	for _index in range(count):
		session.world.synchronize(session.entities, seconds / float(count))
		await physics_frame
	await _settle()

func _sweep(from: Vector3, to: Vector3) -> Dictionary:
	await _place(from)
	var body = session.players[1]
	var collision = body.move_and_collide(to - from)
	return {"collision":collision, "end":body.global_position, "target":to,
		"collider":collision.get_collider() if collision else null}

func _clear_sweep(from: Vector3, to: Vector3, label: String) -> void:
	var sweep: Dictionary = await _sweep(from, to)
	_check(sweep.collision == null and sweep.end.distance_to(to) < 0.03, label,
		{"from":_vector(from), "to":_vector(to), "end":_vector(sweep.end), "collider":str(sweep.collider)})

func _test_industrial() -> void:
	_case("industrial_import_and_real_envelopes")
	var bridge = session.world.art_bridge
	_check(is_instance_valid(bridge) and bridge.imported, "I1 loads imported GLB bridge with named moving part")
	_check(bridge.slats.size() == 16 and bridge.slat_origins.size() == 16, "I1 imports all sixteen shutter slats")
	if not bridge.imported: return
	for id in ["tr01", "hx02"]:
		await _frame(id)
		await _clear_sweep(bridge.marker_position("UnderStart"), bridge.marker_position("UnderEnd"), id + " passes below imported bridge")
		await _clear_sweep(bridge.marker_position("UnderEnd"), bridge.marker_position("UnderStart"), id + " passes below bridge in reverse")
		var passage: Array[Vector3] = session.world.gate_passage()
		var blocked: Dictionary = await _sweep(passage[0], passage[1])
		_check(blocked.collision != null and blocked.collider == bridge.shutter_body, id + " closed shutter physically stops flight body", {"end":_vector(blocked.end), "collider":str(blocked.collider)})
		var landing: Dictionary = await _sweep(bridge.marker_position("DeckProbe"), bridge.marker_position("DeckProbe") + Vector3.DOWN * 6.0)
		_check(landing.collision != null and landing.collider == bridge.get_node("BridgeStructure") and landing.end.y > bridge.global_position.y + 4.8,
			id + " bridge deck physically stops descent", {"end":_vector(landing.end), "collider":str(landing.collider)})
	_check(float(frames.hx02.envelope[0]) > float(frames.tr01.envelope[0]), "hx02 clearance checks use a genuinely wider collider")
	await _place(Vector3(-14, 2, 21))
	var applied: int = session.stats.abilities
	_cast("charge", "I1:relay")
	_cast("charge", "I1:relay")
	_check(session.stats.abilities == applied + 2, "two actual charge actions reach authoritative relay rules")
	await _advance(1.6)
	_check(session.world.gate_open and is_equal_approx(bridge.lift, bridge.TRAVEL), "relay opens imported shutter to full travel")
	_check(bridge.shutter_body.collision_layer == 0, "fully retracted shutter no longer blocks physics")
	for id in ["tr01", "hx02"]:
		await _frame(id)
		var passage: Array[Vector3] = session.world.gate_passage()
		await _clear_sweep(passage[0], passage[1], id + " flies through opened shutter")
		await _clear_sweep(passage[1], passage[0], id + " flies back through opened shutter")
	var open_snapshot: Dictionary = session.world.mechanism_snapshot().duplicate(true)
	var partial: Dictionary = open_snapshot.duplicate(true)
	partial.gate = 0.36
	session.world.local_authority = false
	session.world.apply_mechanism_snapshot(partial)
	var partial_pose: Transform3D = bridge.shutter_body.global_transform
	var partial_slat: Transform3D = bridge.slats[0].global_transform
	session.world.synchronize(session.entities, 10.0)
	_check(is_equal_approx(bridge.lift, 0.36 * bridge.TRAVEL), "I1 guest does not advance partial shutter from host snapshot")
	session.world.apply_mechanism_snapshot(partial)
	_check(bridge.shutter_body.global_transform.is_equal_approx(partial_pose) and bridge.slats[0].global_transform.is_equal_approx(partial_slat), "I1 repeated snapshot preserves both shutter collision and visual slat pose")
	session.world.apply_mechanism_snapshot(open_snapshot)
	session.world.local_authority = true
	await _place(session.world.objects["I1:beacon"].global_position + Vector3(0, 2, 4))
	session._action_received(1, "interact", {})
	_check(session.store.data.world.flags.get("I1_gate", false), "actual gate interaction durably records I1 repair")
	_check(session._save_environment(), "industrial persistent mechanism inputs save successfully")

func _test_fantasy_hole() -> void:
	_case("fantasy_ring_real_envelopes")
	session._load_region("F1")
	_freeze()
	await _settle()
	var temple = session.world.art_temple
	_check(is_instance_valid(temple) and temple.imported, "F1 imports GLB with separate Rotor")
	if not temple.imported: return
	var center: Vector3 = temple.to_global(Vector3(0, 5.2, 0))
	for id in ["tr01", "hx02"]:
		await _frame(id)
		for degrees in [0, 30, 90]:
			session.entities["F1:mirror"].angle = deg_to_rad(float(degrees))
			await _advance(1.3)
			_check(is_equal_approx(session.world.rotor_angle, deg_to_rad(float(degrees))), id + " ring reaches " + str(degrees) + " degrees")
			await _clear_sweep(center + Vector3(0, 0, 3.8), center - Vector3(0, 0, 3.8), id + " passes ring forward at " + str(degrees) + " degrees")
			await _clear_sweep(center - Vector3(0, 0, 3.8), center + Vector3(0, 0, 3.8), id + " passes ring backward at " + str(degrees) + " degrees")
	# Restore the real puzzle's starting angle before testing the actual action chain.
	session.entities["F1:mirror"].angle = -PI / 3.0
	session.world.initialize_mechanisms(session.entities)
	await _settle()

func _test_light_and_growth() -> void:
	_case("fantasy_action_light_occlusion_growth")
	await _frame("tr01")
	var temple = session.world.art_temple
	await _place(temple.to_global(Vector3(0, 5.2, 5)))
	var applied: int = session.stats.abilities
	_cast("light", "F1:mirror")
	_cast("light", "F1:mirror")
	_check(session.stats.abilities == applied + 2, "two session light actions rotate the real ring")
	_check(is_zero_approx(float(session.entities["F1:mirror"].angle)), "two light actions rotate initial minus sixty degrees to zero")
	await _advance(1.0)
	_check(is_zero_approx(session.world.rotor_angle), "rendered and physical rotor reach aligned angle")
	var growth: Dictionary = session.entities["F1:growth"]
	_check(float(growth.get("light_level", 0.0)) == 0.0, "plant has no direct self-light bypass")
	_check(float(growth.environment_light) == 1.0, "real aligned beam illuminates F1 growth receiver")
	var query = PhysicsRayQueryParameters3D.create(temple.light_origin(), temple.light_endpoint(), 1 | 8)
	var hit: Dictionary = session.get_world_3d().direct_space_state.intersect_ray(query)
	_check(not hit.is_empty() and hit.collider == session.world.objects["F1:growth"], "real optical ray first hits the intended receiver", {"hit":str(hit.get("collider")), "position":str(hit.get("position"))})
	await _place(session.world.objects["F1:growth"].global_position + Vector3(0, 0, 4))
	_cast("growth", "F1:growth")
	_cast("growth", "F1:growth")
	session.world.synchronize(session.entities, 0.0)
	await _settle()
	_check(float(session.entities["F1:growth"].growth) >= 0.5 and session.world.growth_bridge.collision_layer == 1, "beam plus two growth actions enables physical root bridge")
	var landing: Dictionary = await _sweep(session.world.growth_bridge.global_position + Vector3.UP * 3, session.world.growth_bridge.global_position + Vector3.DOWN * 2)
	_check(landing.collision != null and landing.collider == session.world.growth_bridge, "grown root bridge supports the actual flight body", {"end":_vector(landing.end), "collider":str(landing.collider)})
	# Place a real static obstacle across only the optical path, not the pilot-to-plant path.
	var occluder = StaticBody3D.new()
	occluder.name = "QaOpticalOccluder"
	occluder.collision_layer = 1
	var shape_node = CollisionShape3D.new()
	var box = BoxShape3D.new()
	box.size = Vector3(0.4, 2.0, 2.0)
	shape_node.shape = box
	occluder.add_child(shape_node)
	session.world.add_child(occluder)
	occluder.global_position = temple.to_global(Vector3(5.0, 5.2, 1.35))
	session.entities["F1:growth"].growth = 0.0
	await _settle()
	session.world.synchronize(session.entities, 0.0)
	_check(float(session.entities["F1:growth"].environment_light) == 0.0, "physical board blocks optical receiver illumination")
	_check(session.world.light_hit.distance_to(occluder.global_position) < 1.1, "visible beam terminates at the occluding board")
	await _place(session.world.objects["F1:growth"].global_position + Vector3(0, 0, 4))
	var rejected: int = session.stats.rejected_abilities
	var energy: float = session.entities["player:1"].energy
	_cast("growth", "F1:growth")
	_check(session.stats.rejected_abilities == rejected + 1 and session.entities["F1:growth"].growth == 0.0, "occluded plant rejects growth without self-light")
	_check(session.entities["player:1"].energy == energy and session.world.growth_bridge.collision_layer == 0, "rejected growth spends no energy and creates no collision")
	occluder.queue_free()
	await _settle()
	session.world.synchronize(session.entities, 0.0)
	_check(float(session.entities["F1:growth"].environment_light) == 1.0, "removing real occluder restores illumination")
	await _place(temple.to_global(Vector3(0, 5.2, 5)))
	_cast("light", "F1:mirror", "off")
	session.world.synchronize(session.entities, 0.0)
	_check(not session.world.light_enabled and float(session.entities["F1:growth"].environment_light) == 0.0, "switching mirror light off clears receiver illumination")
	_cast("light", "F1:mirror")
	await _advance(0.5)
	_check(is_equal_approx(session.world.rotor_angle, PI / 6.0) and session.world.light_enabled, "next actual light action reaches thirty degrees")
	_check(float(session.entities["F1:growth"].environment_light) == 0.0, "lit but misaligned ring does not illuminate receiver")

func _test_snapshot_authority() -> void:
	_case("authoritative_mechanism_snapshots")
	var world = session.world
	var snapshot: Dictionary = world.mechanism_snapshot().duplicate(true)
	snapshot.merge({"gate":0.43, "open":true, "platform":4.75, "rotor":PI/6.0, "light":true, "hit":Vector3(-18, 6, 26.35), "clock":22.5}, true)
	world.local_authority = false
	world.apply_mechanism_snapshot(snapshot)
	var before: Dictionary = world.mechanism_snapshot().duplicate(true)
	var rotor_before: Transform3D = world.art_temple.rotor_body.global_transform
	var gate_before: Transform3D = world.gate.global_transform
	var platform_before: Transform3D = world.platform.global_transform
	session.entities["F1:mirror"].angle = -PI/2.0
	session.entities["F1:relay"].charge = 100.0
	session.entities["F1:switch"].operated = true
	world.synchronize(session.entities, 10.0)
	await _settle()
	_check(world.mechanism_snapshot() == before, "guest does not integrate received mechanism or optical state")
	_check(world.art_temple.rotor_body.global_transform.is_equal_approx(rotor_before) and world.gate.global_transform.is_equal_approx(gate_before) and world.platform.global_transform.is_equal_approx(platform_before), "guest leaves rotor gate and platform transforms at host snapshot")
	world.apply_mechanism_snapshot(snapshot)
	world.apply_mechanism_snapshot(snapshot)
	_check(world.mechanism_snapshot() == before, "reapplying identical mechanism snapshot is idempotent")
	_check(world.art_temple.rotor_body.global_transform.is_equal_approx(rotor_before), "repeated snapshot does not accumulate rotor transform")
	world.local_authority = true

func _test_durable_pose_restore() -> void:
	_case("saved_mechanism_restores_before_input")
	session.entities["F1:mirror"].angle = PI/6.0
	session.entities["F1:relay"].charge = 70.0
	session.world.synchronize(session.entities, 2.0)
	await _place(session.world.objects["F1:beacon"].global_position + Vector3(0, 2, 4))
	session._action_received(1, "interact", {})
	_check(session.store.data.world.flags.get("F1_gate", false), "actual F1 repair interaction durably records open gate")
	_check(session._save_environment(), "physical ring target angle is durably saved")
	var reread = Store.new(session.store.root_path)
	_check(reread.load_profile().get("ok", false), "new store reads saved QA profile from disk")
	_check(is_equal_approx(float(reread.data.world.entities.F1["F1:mirror"].angle), PI/6.0), "disk profile contains ring target angle")
	session.store = reread
	session.world_cache = reread.snapshot()
	session._load_region("F1")
	_freeze()
	_check(session.world.restored_gate and is_equal_approx(session.world.gate_fraction, 1.0), "F1 gate restores fully open before next physics tick")
	_check(is_equal_approx(session.world.rotor_angle, PI/6.0) and is_equal_approx(session.world.art_temple.rotor_body.rotation.z, PI/6.0), "F1 rotor restores saved angle before next physics tick")
	await _settle()
	session.entities["F1:mirror"].angle = 0.0
	session.entities["F1:mirror"].light_level = 1.0
	session.entities["F1:growth"].growth = 0.6
	_check(session._save_environment(), "aligned sustained source and growth saved together")
	session.simulation_paused = true
	session._load_region("F1")
	_freeze()
	_check(session.simulation_paused and session.world.rotor_angle == 0.0, "paused reload restores saved aligned pose")
	_check(float(session.entities["F1:growth"].environment_light) == 1.0, "paused reload resolves real ray without an extra synchronization tick")
	_check(session.world.light_hit.distance_to(session.world.objects["F1:growth"].position) < 1.6, "paused first mechanism packet contains receiver hit instead of old default ray")
	session.simulation_paused = false
	session._load_region("I1")
	_freeze()
	_check(session.world.restored_gate and is_equal_approx(session.world.art_bridge.lift, session.world.art_bridge.TRAVEL), "I1 imported shutter restores at full travel immediately")
	_check(session.world.art_bridge.shutter_body.collision_layer == 0, "restored I1 open shutter is immediately nonblocking")
	await _settle()
	await _frame("hx02")
	var passage: Array[Vector3] = session.world.gate_passage()
	await _clear_sweep(passage[0], passage[1], "wider frame physically passes restored open shutter")

func _vector(value: Vector3) -> Array:
	return [value.x, value.y, value.z]

func _finish() -> void:
	var hashes: Dictionary = {}
	for path in HASH_PATHS: hashes[path] = FileAccess.get_sha256(path)
	var report = {"suite":"art_session_physics_integration", "started_utc":started_utc,
		"finished_utc":Time.get_datetime_string_from_system(true) + "Z", "engine":Engine.get_version_info(),
		"profile":profile, "profile_root":ProjectSettings.globalize_path("user://profiles_v3/" + profile),
		"checks":checks, "check_count":checks.size(), "failures":failures, "passed":failures.is_empty(),
		"frames":frames, "source_sha256":hashes,
		"limits":["Actual main scene, flight-body envelopes, imported wrappers and PhysicsServer shape sweeps; flight dynamics frozen to isolate collision geometry.",
			"Session actions and durable profile reload are real. Mechanism client authority is exercised directly; this is not a two-process ENet loss/latency test.",
			"Headless checks are not rendered appearance, shader GPU compilation, frame rate, controller comfort or human gameplay acceptance."]}
	DirAccess.make_dir_recursive_absolute(REPORT.get_base_dir())
	var file = FileAccess.open(REPORT, FileAccess.WRITE)
	if file == null:
		push_error("Could not write art integration report")
		quit(2)
		return
	file.store_string(JSON.stringify(report, "\t"))
	file.close()
	print("V3_ART_INTEGRATION checks=%d failures=%d report=%s" % [checks.size(), failures.size(), ProjectSettings.globalize_path(REPORT)])
	if is_instance_valid(session):
		session.active = false
		session.network.close()
		session.free()
	quit(0 if failures.is_empty() else 1)
