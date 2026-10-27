extends SceneTree
## Real imported hull, host shot/ability adapters and PhysicsServer. Scripted poses
## and time advances isolate regressions; they do not prove human difficulty.
const Session = preload("res://scripts/v3/twin_session.gd")
var session
var profile = ""
var checks: Array = []
var failures: Array = []

func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--qa-profile="): profile = arg.trim_prefix("--qa-profile=")
	if not profile.begins_with("qa_whalecombat_") or profile != profile.validate_filename() or DirAccess.dir_exists_absolute("user://profiles_v3/" + profile):
		push_error("A fresh isolated qa_whalecombat_<unique> profile is required")
		quit(2)
		return
	_run.call_deferred()

func check(ok: bool, label: String, detail: Dictionary = {}) -> void:
	checks.append({"name":label, "passed":ok, "detail":detail})
	if not ok:
		failures.append(label)
		push_error("WHALE COMBAT: " + label + " " + JSON.stringify(detail))

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
	body.linear_velocity = Vector3.ZERO
	body.hold_height = at.y
	session.entities["player:1"].position = at
	session.encounter.set_player_position("1", at)
	await settle()

func advance(seconds: float) -> void:
	session._handle_boss_events(session.encounter.advance(seconds))
	session._sync_boss_entities()
	session._update_boss_warning()
	await settle()

func fire(part: String) -> void:
	session.locks[1] = "boss:" + part
	session.weapon_cooldowns[1] = 0.0
	session._fire(1)
	session._sync_boss_entities()

func _run() -> void:
	session = Session.new()
	root.add_child(session)
	check(session.start_flight("solo"), "starts isolated actual session")
	session.set_process(false)
	session.set_physics_process(false)
	session.inputs.set_process(false)
	session.inputs.set_physics_process(false)
	check(session.world.whale_ready(), "actual whale imported")
	if not session.world.whale_ready():
		finish()
		return
	session._start_boss()
	for part in ["port", "starboard", "core"]:
		var point: Vector3 = session.world.boss_parts[part].global_position
		await place(point + Vector3.UP * 5)
		var before: int = session.stats.shots
		fire(part)
		check(session.stats.shots == before, "closed actual armor blocks shot to " + part)
	await advance(2.7)
	for part in ["port", "starboard"]:
		var point: Vector3 = session.world.boss_parts[part].global_position
		await place(point + Vector3.UP * 5)
		var before: int = session.stats.shots
		fire(part)
		check(session.stats.shots == before + 1 and session.encounter.get_state().nodes[part].health == 31.0, "open " + part + " takes an actual host shot through the cavity", {"position":str(point), "state":session.encounter.get_state().nodes[part]})
		var used: int = session.stats.abilities
		session.cooldowns[1] = 0.0
		session._action_received(1, "ability", {"ability":"takeover", "target_id":"boss:" + part})
		session._sync_boss_entities()
		check(session.stats.abilities == used + 1 and not session.encounter.get_state().nodes[part].powered, "actual takeover shuts down open " + part)
	check(session.encounter.get_state().phase == "exposed", "two stopped side pods expose core")
	var core: Vector3 = session.world.boss_parts.core.global_position
	await place(core + Vector3.UP * 5)
	for i in range(7): fire("core")
	check(session.encounter.get_state().overdrive and session.encounter.get_state().core_health == 57.0, "seven real shots trigger half-health forced rearm")
	var before: int = session.stats.shots
	fire("core")
	check(session.stats.shots == before, "rearmed core cover physically stops same-frame extra shot")
	await advance(2.7)
	for part in ["port", "starboard"]:
		await place(session.world.boss_parts[part].global_position + Vector3.UP * 5)
		for i in range(5): fire(part)
		check(not session.encounter.get_state().nodes[part].powered, "five real shots disable rearmed " + part)
	await place(core + Vector3.UP * 5)
	for i in range(7): fire("core")
	check(not session.boss_active and session.store.snapshot().world.flags.get("I1_boss", false), "actual shot sequence wins and durably records development encounter")
	check(not session.store.snapshot().world.flags.get("campaign_whale_v1", false), "isolated developer fight cannot bypass campaign prerequisites")
	# A separate attempt measures physical shelter, with no mocked LOS answer.
	session._start_boss()
	for slot in range(2):
		await place(session.world.boss_retry_position(slot))
		var body = session.players[1]
		var query = PhysicsShapeQueryParameters3D.new()
		query.shape = body.get_node("Envelope").shape
		query.transform = body.global_transform
		query.collision_mask = 1 | 8
		query.exclude = [body.get_rid()]
		check(session.get_world_3d().direct_space_state.intersect_shape(query, 1).is_empty(), "retry slot " + str(slot) + " has drone clearance")
		var health: float = body.health
		check(not session._line_clear(session.world.boss_attack_origin(), body.global_position, body.get_rid(), "", true), "retry slot " + str(slot) + " has genuine world cover")
		session._telegraph("low_sweep", 2.0)
		session._boss_attack("low_sweep")
		check(body.health == health, "retry shelter blocks actual damage for slot " + str(slot))
	finish()

func finish() -> void:
	var result = {"checks":checks, "failures":failures, "passed":failures.is_empty(), "model_sha256":FileAccess.get_sha256("res://assets/v3/whale/siphon_whale.glb"), "limits":["Scripted poses and explicit encounter time advances; not manual aim, human challenge, timing, performance or two-PC LAN acceptance.", "Real shots and ability intents traverse production host validation and actual imported collision."]}
	var file = FileAccess.open("res://artifacts/v3/whale-combat-" + profile + ".json", FileAccess.WRITE)
	file.store_string(JSON.stringify(result, "\t"))
	file.close()
	print("V3_WHALE_COMBAT checks=%d failures=%d" % [checks.size(), failures.size()])
	if is_instance_valid(session):
		session.network.close()
		session.free()
	quit(0 if failures.is_empty() else 1)
