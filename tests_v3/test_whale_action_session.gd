extends SceneTree
## Real Session/Physics/Store adapter regression. Automated placements are fixtures.
## The first 15 goals are reducer-seeded, NOT physically replayed in this suite.
## Boss victory comes from bounded lower-level encounter calls, NOT player combat.
## Peer lifecycle is injected locally; no actual LAN, rendering or human-time claim.

const Main = preload("res://scenes/v3/main.tscn")
const Store = preload("res://scripts/v3/core/twin_world_store.gd")
const Director = preload("res://scripts/v3/gameplay/actions/twin_action_director.gd")
# Access constants only; do not instantiate this other SceneTree test runner.
const DataFixtures = preload("res://tests_v3/test_whale_action_data.gd")
const RECORD := "I1:whale_raw_record"
const DISCOVERY := "opening:whale_raw_command_record"
var session
var guest_store
var profile := ""
var report_path := ""
var auxiliary_root := ""
var checks: Array = []
var failures: Array[String] = []
var stage := "setup"
var started_at := 0

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--qa-profile="): profile = arg.trim_prefix("--qa-profile=")
		if arg.begins_with("--qa-network="):
			push_error("Whale story suite refuses automatic network QA mode")
			quit(2)
			return
	if not profile.begins_with("qa_whale_") or profile.length() <= 9 or profile.validate_filename() != profile or profile.contains(".."):
		push_error("Use a fresh --qa-profile=qa_whale_<unique>; real/default profiles are never used")
		quit(2)
		return
	report_path = "res://artifacts/v3/whale-action-" + profile + ".json"
	auxiliary_root = "user://qa_v3_whale/" + profile
	if DirAccess.dir_exists_absolute("user://profiles_v3/" + profile) or DirAccess.dir_exists_absolute(auxiliary_root) or FileAccess.file_exists(report_path):
		push_error("Whale story suite refuses profile/report reuse")
		quit(2)
		return
	started_at = Time.get_ticks_msec()
	session = Main.instantiate()
	root.add_child(session)
	_check(session.profile_ready and session.store.root_path == "user://profiles_v3/" + profile, "production main opens only the requested isolated profile")
	if not session.profile_ready:
		_finish()
		return
	var started: bool = session.start_flight("solo")
	_check(started, "production solo session starts")
	if not started:
		_finish()
		return
	_quiet_session()
	await _settle()
	_check(session.world.whale_ready(), "real imported whale is available; missing wrapper is a failure, not a skipped test")
	if not session.world.whale_ready():
		_finish()
		return
	var passed: bool = await _test_prerequisite_and_brief()
	if passed: passed = await _test_campaign_start_and_membership()
	if passed: passed = await _test_pending_victory_travel()
	if passed: passed = await _test_record_and_reload()
	if passed: await _test_guest_record_catchup()
	_finish()

func _check(ok: bool, label: String, details: Dictionary = {}) -> void:
	checks.append({"stage": stage, "label": label, "passed": ok, "details": details})
	if not ok:
		failures.append(stage + ": " + label)
		print("WHALE_ACTION_FAIL ", label)

func _same(left: Variant, right: Variant) -> bool:
	return JSON.parse_string(JSON.stringify(left)) == JSON.parse_string(JSON.stringify(right))

func _quiet_session() -> void:
	session.set_process(false)
	session.set_physics_process(false)
	session.inputs.set_process(false)
	session.inputs.set_physics_process(false)
	session.interface.menu.hide()
	session.interface.clear_dialogue()
	for body in session.players.values():
		body.freeze = true
		body.set_process(false)
		body.set_physics_process(false)
		body.linear_velocity = Vector3.ZERO
		body.angular_velocity = Vector3.ZERO

func _settle() -> void:
	await physics_frame
	await physics_frame
	await process_frame

func _place(at: Vector3, peer_id: int = 1) -> void:
	var body = session.players[peer_id]
	body.freeze = true
	body.global_transform = Transform3D(Basis.IDENTITY, at)
	body.hold_height = at.y
	body.linear_velocity = Vector3.ZERO
	body.angular_velocity = Vector3.ZERO
	session.entities["player:" + str(peer_id)].position = at
	if session.boss_active: session.encounter.set_player_position(str(peer_id), at)
	await _settle()

func _press_g() -> void:
	# Explicitly finish fixture dialogue before exercising the real G -> request -> host path.
	session.interface.menu.hide()
	session.interface.clear_dialogue()
	var key = InputEventKey.new()
	key.pressed = true
	key.keycode = KEY_G
	key.physical_keycode = KEY_G
	session._unhandled_input(key)

func _body_clear(point: Vector3) -> bool:
	var body = session.players[1]
	var shape = BoxShape3D.new()
	shape.size = Vector3(float(body.stats.width_m), float(body.stats.height_m), float(body.stats.length_m))
	var query = PhysicsShapeQueryParameters3D.new()
	query.shape = shape
	query.transform = Transform3D(Basis.IDENTITY, point)
	query.collision_mask = 1 | 2 | 8 | 32
	query.exclude = [body.get_rid()]
	return session.get_world_3d().direct_space_state.intersect_shape(query, 1).is_empty()

func _inspection_spot(anchor: Vector3, target_id: String) -> Vector3:
	if not anchor.is_finite(): return Vector3.INF
	for height in [0.0, 0.6, -0.6, 1.5]:
		for step in range(12):
			var angle := TAU * float(step) / 12.0
			var direction := Vector3(sin(angle), height, cos(angle)).normalized()
			var point := anchor + direction * 2.5
			if _body_clear(point) and session._line_clear(point, anchor, session.players[1].get_rid(), target_id): return point
	return Vector3.INF

func _wall_between(from: Vector3, to: Vector3) -> StaticBody3D:
	var wall = StaticBody3D.new()
	wall.name = "QAWhaleInspectionOccluder"
	wall.collision_layer = 1
	wall.collision_mask = 0
	var collision = CollisionShape3D.new()
	var box = BoxShape3D.new()
	box.size = Vector3.ONE * 0.65
	collision.shape = box
	wall.add_child(collision)
	session.world.add_child(wall)
	wall.global_position = from.lerp(to, 0.5)
	return wall

func _seed_previous_four_actions() -> bool:
	# Deliberate fixture: replay stable public events in the old pure reducer, then
	# commit that validated historical state. This does not replay their physics.
	var old = Director.new()
	var loaded: Dictionary = old.load_definitions(Director.DEFAULT_PATH)
	_check(loaded.get("ok", false), "fixture loads original four-action definitions")
	if not loaded.get("ok", false): return false
	var state: Dictionary = old.default_state()
	for row in DataFixtures.BASE_EVENTS:
		var event = {"id":"qa_whale_seed:" + str(row[0]), "type":row[1], "target_id":row[2], "option":row[3]}
		var reduced: Dictionary = old.apply_event(state, event, {"is_authority":true, "validated":true, "region_id":row[4]})
		if not reduced.get("ok", false) or not reduced.get("changed", false):
			_check(false, "historical reducer fixture advances " + str(row[0]))
			return false
		state = reduced.state
	_check(state.completed.size() == 15 and session.story.director.validate_state(state).get("ok", false), "fixture is a real validated fifteen-receipt state")
	var changes: Dictionary = {"world.actions.opening":state, "world.flags.I1_gate":true, "world.flags.F1_gate":true, "world.flags.I1_boss":true}
	for flag in state.flags: changes["world.flags." + str(flag)] = state.flags[flag]
	var discoveries: Array = state.discoveries.duplicate()
	discoveries.append("boss:I1:harbor_whale")
	var saved: Dictionary = session.store.commit({"id":"qa_fixture:old_four_actions_and_dev_victory", "set":changes, "append":{"world.completed_objectives":state.completed, "personal.discoveries":discoveries}})
	_check(saved.get("ok", false), "historical goals, travel gates and old DEV-only win explicitly committed as fixtures")
	if not saved.get("ok", false): return false
	session.world_cache = session.store.snapshot()
	session.consensus.set_world_revision(int(session.world_cache.world_revision))
	session._load_region("I1")
	_quiet_session()
	await _settle()
	return true

func _test_prerequisite_and_brief() -> bool:
	stage = "prerequisite_and_real_brief_input"
	var anchor: Vector3 = session.story._point(session.story.markers["I1:whale_briefing"])
	var nearby := _inspection_spot(anchor, "I1:whale_briefing")
	_check(nearby.is_finite(), "entrance has a drone-clear and unobstructed inspection position")
	if not nearby.is_finite(): return false
	await _place(nearby)
	_press_g()
	session._action_received(1, "explore", {"target_id":"I1:whale_briefing"})
	_check(session.story.state.revision == 0 and not session.boss_active, "G and direct interaction request cannot bypass missing F1 repair")
	var seeded: bool = await _seed_previous_four_actions()
	if not seeded: return false
	_check(session.story.state.revision == 15 and not session.story.whale_victory_committed() and not session.world.whale_defeated, "old I1_boss flag neither completes campaign nor restores campaign defeat pose")
	session.story.observe(0.3)
	_check(session.story.state.revision == 15, "old dev win cannot auto-complete fifth action")
	await _place(anchor + Vector3(0, 6, 0))
	var before: Dictionary = session.store.snapshot()
	session._action_received(1, "explore", {"target_id":"I1:whale_briefing"})
	_check(_same(session.store.snapshot(), before), "host rejects remote briefing request")
	await _place(nearby)
	var wall = _wall_between(nearby, anchor)
	await _settle()
	_check(not session._line_clear(nearby, anchor, session.players[1].get_rid(), "I1:whale_briefing"), "real collider blocks briefing ray")
	_press_g()
	_check(session.story.state.revision == 15, "nearby G cannot confirm briefing through a wall")
	wall.queue_free()
	await _settle()
	before = session.store.snapshot()
	session.store.failure_point = "before_publish"
	_press_g()
	_check(session.story.state.revision == 15 and _same(session.store.snapshot(), before), "failed briefing save leaves progress and durable store unchanged")
	_check(not session.interface.radio.visible, "failed briefing save publishes no success dialogue")
	session.store.failure_point = ""
	_press_g()
	_check(session.story.state.revision == 16 and session.store.snapshot().world.actions.opening.revision == 16, "unobstructed real G confirms and persists briefing")
	_check(not session.boss_active, "confirming briefing alone does not start combat")
	return session.story.state.revision == 16

func _test_campaign_start_and_membership() -> bool:
	stage = "campaign_trigger_and_membership"
	await _place(session.world.boss_position + Vector3(0, 8, 18))
	session.story.observe(0.3)
	_check(not session.boss_active and session.story.state.revision == 16, "outside 18m does not start campaign encounter")
	await _place(session.world.boss_position + Vector3(0, 0, 17))
	var before: Dictionary = session.store.snapshot()
	session.store.failure_point = "before_publish"
	session.story.observe(0.3)
	_check(session.boss_active and session.boss_campaign and session.story.state.revision == 16, "real proximity starts campaign even if engage progress publication must retry")
	_check(_same(session.store.snapshot(), before), "failed engage progress write does not invent durable receipt")
	session.store.failure_point = ""
	session.story.observe(0.3)
	_check(session.story.state.revision == 17, "host observed live encounter retries engage fact successfully")
	if not session.boss_active or session.story.state.revision != 17: return false
	# Advance only the pure encounter clock; not a dodge or timing performance claim.
	await _place(session.world.spawn_position)
	if not _open_nodes_fixture(): return false
	var partial: Dictionary = session.encounter.hit_part("port", 18.0, "1")
	_check(partial.get("ok", false), "lower-level fixture creates nontrivial damaged-side state")
	session._handle_boss_events(partial.get("events", []))
	var signature := _encounter_signature()
	guest_store = Store.new(auxiliary_root.path_join("guest"))
	var guest_ready: bool = guest_store.load_profile().get("ok", false) and guest_store.commit({"id":"qa_guest_bootstrap"}).get("ok", false)
	_check(guest_ready, "isolated guest identity is durable")
	if not guest_ready: return false
	_join_guest(3)
	_quiet_session()
	await _settle()
	_check(_same(_encounter_signature(), signature) and session.story.state.revision == 17, "joining preserves damaged parts, phase, attempt and story progress")
	_check(session.players[3].enabled and session.players[3].global_position.is_equal_approx(session.world.boss_retry_position(1)), "active-fight guest enters healthy at actual retry anchor")
	session.network._peer_left(3)
	await _settle()
	_check(_same(_encounter_signature(), signature) and session.story.state.revision == 17, "leaving with surviving host preserves encounter and story")
	var attempt := int(session.encounter.get_state().attempt)
	session._action_received(1, "retry", {})
	_quiet_session()
	await _settle()
	_check(session.encounter.get_state().attempt == attempt + 1 and session.story.state.revision == 17 and session.boss_campaign, "manual retry resets fight while retaining campaign identity and committed engage goal")
	return true

func _join_guest(peer_id: int) -> void:
	# Inject production transport lifecycle; no real peer/socket is claimed.
	var identity: String = guest_store.snapshot().profile_id
	session.network.guests[peer_id] = identity
	session.network.guest_joined.emit(peer_id, identity, "tr01")

func _encounter_signature() -> Dictionary:
	var state: Dictionary = session.encounter.get_state()
	state.erase("players")
	return state

func _open_nodes_fixture() -> bool:
	for step in range(180):
		if session.encounter.get_state().get("nodes_open", false): return true
		session._handle_boss_events(session.encounter.advance(0.05))
	_check(false, "bounded encounter fixture reaches a recovery window")
	return false

func _victory_fixture() -> bool:
	# Deliberate lower-level fixture: real state machine produces its own victory
	# event; no fabricated boss_defeated event and no direct completed/HP mutation.
	for phase in range(2):
		if not _open_nodes_fixture(): return false
		for part in ["port", "starboard"]:
			var hit: Dictionary = session.encounter.hit_part(part, 40.0, "1")
			_check(hit.get("ok", false), "fixture disables valid open side in phase " + str(phase))
			if not hit.get("ok", false): return false
			session._handle_boss_events(hit.get("events", []))
		for shot in range(7):
			var hit: Dictionary = session.encounter.hit_part("core", 9.0, "1")
			if not hit.get("ok", false):
				_check(false, "fixture core damage accepted within actual exposure")
				return false
			session._handle_boss_events(hit.get("events", []))
		if phase == 0: _check(session.encounter.get_state().overdrive and not session.encounter.get_state().completed, "fixture traverses mandatory half-health reassembly")
	_check(session.encounter.get_state().completed, "real encounter reducer produces final victory")
	return session.encounter.get_state().completed

func _test_pending_victory_travel() -> bool:
	stage = "pending_victory_and_travel"
	await _place(session.world.spawn_position)
	var before: Dictionary = session.store.snapshot()
	session.store.failure_point = "before_publish"
	if not _victory_fixture(): return false
	_check(session.pending_completion and session.boss_active and not session.story.whale_victory_committed(), "failed victory publication stays pending and cannot qualify campaign completion")
	_check(_same(session.store.snapshot(), before), "failed victory publishes neither campaign flag nor reward")
	session.story.observe(0.3)
	_check(session.story.state.revision == 17, "pending victory cannot advance the defeated objective")
	var old_world = session.world
	session._action_received(1, "propose", {"kind":"region_change", "payload":{"region_id":"F1"}})
	_check(session.region_id == "I1" and session.world == old_world and session.pending_completion and session.boss_campaign, "travel cannot discard or relabel unsaved I1 campaign victory")
	_check(_same(session.store.snapshot(), before), "failed pending-victory travel preserves durable world")
	session.store.failure_point = ""
	session._action_received(1, "propose", {"kind":"region_change", "payload":{"region_id":"F1"}})
	_quiet_session()
	await _settle()
	var saved: Dictionary = session.store.snapshot()
	_check(session.region_id == "F1" and not session.pending_completion, "same travel request first saves victory then switches region after storage recovers")
	_check(saved.world.flags.get("campaign_whale_v1", false) and saved.world.flags.get("I1_boss", false) and not saved.world.flags.get("F1_boss", false), "recovered victory belongs to I1 campaign, never F1 dev encounter")
	var has_campaign_receipt := false
	for receipt in saved.ledger.commits:
		if str(receipt).begins_with("boss:I1:harbor_whale:opening_v1:"): has_campaign_receipt = true
	_check(has_campaign_receipt, "campaign victory has its own durable receipt namespace")
	_check(saved.personal.discoveries.count("boss:I1:harbor_whale") == 1, "campaign win cannot duplicate existing dev-win discovery")
	session._action_received(1, "propose", {"kind":"region_change", "payload":{"region_id":"I1"}})
	_quiet_session()
	await _settle()
	session.story.observe(0.3)
	_check(session.region_id == "I1" and session.story.state.revision == 18 and session.world.whale_defeated, "return restores defeated geometry and reconciles durable victory into third whale goal")
	_check(DISCOVERY not in session.store.snapshot().personal.discoveries and not session.boss_active, "victory alone neither extracts record nor restarts encounter")
	return session.region_id == "I1" and session.story.state.revision == 18

func _reload_from_disk() -> bool:
	var reader = Store.new(session.store.root_path)
	var loaded: Dictionary = reader.load_profile()
	_check(loaded.get("ok", false), "fresh Store reads published profile from disk")
	if not loaded.get("ok", false): return false
	_check(session.story.director.validate_state(reader.snapshot().world.actions.opening).get("ok", false), "disk-loaded story receipts validate")
	session.store = reader
	session.world_cache = reader.snapshot()
	var started: bool = session.start_flight("solo")
	_check(started, "production session reloads disk state")
	_quiet_session()
	await _settle()
	return started

func _test_record_and_reload() -> bool:
	stage = "real_record_anchor_input_and_reload"
	var loaded: bool = await _reload_from_disk()
	if not loaded: return false
	_check(session.story.state.revision == 18 and session.world.whale_defeated and not session.boss_active, "victory-before-extraction survives full session reload")
	var anchor: Vector3 = session.world.whale_record_position()
	_check(anchor.is_finite() and session.story.markers.has(RECORD), "record target resolves from actual imported model after reload")
	if not anchor.is_finite() or not session.story.markers.has(RECORD): return false
	_check(session.story._point(session.story.markers[RECORD]).is_equal_approx(anchor), "story record uses live world anchor, not JSON placeholder")
	var nearby := _inspection_spot(anchor, "boss:core")
	_check(nearby.is_finite(), "defeated whale has a drone-clear record approach with real LOS")
	if not nearby.is_finite(): return false
	await _place(anchor + Vector3(0, 5, 0))
	var before: Dictionary = session.store.snapshot()
	session._action_received(1, "explore", {"target_id":RECORD, "type":"fact", "option":"retrieved", "validated":true})
	_check(_same(session.store.snapshot(), before), "client fields cannot bypass record distance validation")
	await _place(nearby)
	for i in range(4): session.story.observe(0.3)
	_check(session.story.state.revision == 18 and DISCOVERY not in session.store.snapshot().personal.discoveries, "standing beside actual record does not auto-extract it")
	var wall = _wall_between(nearby, anchor)
	await _settle()
	_check(not session._line_clear(nearby, anchor, session.players[1].get_rid(), "boss:core"), "actual collider blocks record inspection ray")
	_press_g()
	_check(session.story.state.revision == 18, "nearby G cannot retrieve record through blocking geometry")
	wall.queue_free()
	await _settle()
	before = session.store.snapshot()
	session.store.failure_point = "before_publish"
	_press_g()
	_check(session.story.state.revision == 18 and _same(session.store.snapshot(), before), "failed record publication preserves pending goal and grants no discovery")
	session.store.failure_point = ""
	_press_g()
	_check(session.story.state.revision == 19 and "I1:whale" in session.story.state.completed_actions and session.story.info().get("action_id", "") == "F1:crown", "real G finishes fifth action and points to the new sixth action")
	_check(session.store.snapshot().personal.discoveries.count(DISCOVERY) == 1, "record reward is persisted exactly once")
	if session.story.state.revision != 19: return false
	before = session.store.snapshot()
	for i in range(3): session._action_received(1, "explore", {"target_id":RECORD})
	_check(_same(session.store.snapshot(), before), "repeated direct inspection does not create commits or repeated rewards")
	loaded = await _reload_from_disk()
	_check(loaded and session.story.state.revision == 19 and session.store.snapshot().personal.discoveries.count(DISCOVERY) == 1, "completed fifth action and unique discovery survive fresh disk/session reload")
	return loaded

func _test_guest_record_catchup() -> void:
	stage = "guest_reconnect_reward_catchup"
	_join_guest(5)
	_quiet_session()
	await _settle()
	var identity: String = guest_store.snapshot().profile_id
	var record_receipts: Array = []
	for receipt in session.store.pending_guest_receipts(identity):
		if receipt.reward_id == DISCOVERY: record_receipts.append(receipt)
	_check(record_receipts.size() == 1, "rejoining guest gets exactly one durable record discovery receipt")
	if record_receipts.size() == 1:
		_check(guest_store.apply_guest_receipt(record_receipts[0]).get("ok", false), "guest isolated store accepts record receipt")
		_check(guest_store.apply_guest_receipt(record_receipts[0]).get("duplicate", false), "replayed guest record receipt is idempotent")
		_check(guest_store.snapshot().personal.discoveries.count(DISCOVERY) == 1, "guest discovery is not duplicated by reconnect delivery")
	var anchor: Vector3 = session.world.whale_record_position()
	var nearby := _inspection_spot(anchor, "boss:core")
	if nearby.is_finite():
		await _place(nearby, 5)
		var before: Dictionary = session.store.snapshot()
		session._action_received(5, "explore", {"target_id":RECORD})
		_check(_same(session.store.snapshot(), before), "another peer re-inspecting completed record cannot farm reward")
	else:
		_check(false, "record remains physically approachable after completed reload")
	session.network._peer_left(5)
	await _settle()

func _finish() -> void:
	var report: Dictionary = {
		"checks":checks, "count":checks.size(), "failures":failures, "qa_profile":profile,
		"elapsed_ms":Time.get_ticks_msec() - started_at,
		"model_sha256":FileAccess.get_sha256("res://assets/v3/whale/siphon_whale.glb"),
		"fixtures":["first fifteen objectives generated through pure reducer and committed as history", "I1/F1 travel gates and old dev I1_boss explicitly seeded", "bounded lower-level encounter damage creates real victory event", "scripted player placement and temporary real occluding collider", "local guest lifecycle callbacks without sockets"],
		"scope":"production Session, real physics inspection queries, actual profile transactions and disk reload; no first-four-actions physical replay, player combat, two-PC LAN, rendering, performance, human enjoyment or 3-5 minute validation"
	}
	DirAccess.make_dir_recursive_absolute("res://artifacts/v3")
	var file = FileAccess.open(report_path, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(report, "\t"))
		file.close()
	else:
		failures.append("report could not be written")
	print("V3_WHALE_ACTION_SESSION " + JSON.stringify({"checks":checks.size(), "failures":failures, "report":report_path, "qa_profile":profile}))
	if is_instance_valid(session):
		session.store.failure_point = ""
		session.network.close()
		session.active = false
		session.free()
	quit(0 if failures.is_empty() else 1)
