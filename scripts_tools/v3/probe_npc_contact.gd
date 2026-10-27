extends SceneTree
## Native MAIN contact observer; explicit player pose and temporary opaque obstacle fixtures.
const MAIN = preload("res://scenes/v3/main.tscn")
const Contact = preload("res://scripts/v3/ecology/twin_npc_contact.gd")
const Regions = preload("res://scripts/v3/world/twin_region_catalog.gd")
const OLD = "user://profiles_v3/qa_normal_campaign_20261021_112119_b0f35d51/profile_g000000000426.json"
class ErrorLogger extends Logger:
	var guard := Mutex.new()
	var errors: Array = []
	func _log_error(function: String, file: String, line: int, code: String, rationale: String, _notify: bool, kind: int, _trace: Array[ScriptBacktrace]) -> void:
		if kind == Logger.ERROR_TYPE_WARNING: return
		guard.lock()
		errors.append({"function":function,"file":file,"line":line,"code":code,"rationale":rationale})
		guard.unlock()
var session: Node
var wall: StaticBody3D
var logger := ErrorLogger.new()
var profile := ""
var finished := false
var began := 0
var actions: Array = []
var dialogues: Array = []
var report := {"scope":"Fresh solo MAIN I1; explicit full-hull-clear frozen PLAYER pose, synchronous paused/disabled guard fixtures and one temporary opaque QA obstacle. NPCs and world tick normally. Native G routes through Session/explore. Headless logic only; no naturally flown approach, human, graphics, physical-controller, audio listening or LAN proof.","checks":[],"poses":[],"radio":[]}
func _initialize() -> void:
	OS.add_logger(logger)
	_run.call_deferred()
func _run() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() == 1 and args[0].begins_with("--qa-profile="): profile = args[0].trim_prefix("--qa-profile=")
	if DisplayServer.get_name() != "headless" or not profile.begins_with("qa_npc_contact_") or profile != profile.validate_filename() or DirAccess.dir_exists_absolute("user://profiles_v3/"+profile):
		print("NPC_CONTACT_ARGUMENTS_REJECTED")
		quit(2)
		return
	began = Time.get_ticks_msec()
	report["profile"] = profile
	report["version"] = ProjectSettings.get_setting("application/config/version")
	create_timer(30.0).timeout.connect(func():
		if not finished:
			_check(false,"30 second native MAIN wall bound")
			_finish())
	root.size = Vector2i(1280,720)
	session = MAIN.instantiate()
	root.add_child(session)
	if not _check(session.profile_ready and session.store.root_path == "user://profiles_v3/"+profile and session.start_flight("solo"),"ordinary MAIN starts only the named new QA Store"): _finish(); return
	for unused in 3:
		if not await _frame(): return
	if not _check(session.region_id == "I1" and session.players.has(1) and session.network.is_authority() and not session.inputs.test_enabled and session.world.build_errors.is_empty(),"real I1 actor, normal input, authority and world are ready"): _finish(); return
	session.network.action_received.connect(func(peer: int,verb: String,payload: Dictionary):
		if verb == "explore": actions.append({"peer":peer,"target":payload.get("target_id","")}))
	session.network.event_received.connect(func(event: Dictionary):
		if event.get("kind") == "dialogue": dialogues.append(event.duplicate(true)))
	var before := _protected()
	report["generation_before"] = session.store.snapshot().generation
	_check(before.story.get("completed",[]).is_empty(),"new profile has no completed objective before contact")
	_check(session.story.nearest(session.story._point(session.story.markers["npc:linlan"])) == "npc:linlan","original static task marker has G priority, without pressing G there")
	var id := "I1:repair_01"
	_reject(id,"out_of_range","far original spawn")
	if not await _near(id):
		_check(false,"full-hull-clear live NPC approach fixture exists")
		_finish()
		return
	var body: FlightBodyV2 = session.players[1]
	var reply: Dictionary = Contact.prepare(session,1,id)
	report["contact_before"] = reply
	_check(reply.get("ok",false) and session.story.nearest(body.global_position) == id,"real live NPC is ready and wins ordinary nearby selection")
	if not reply.get("ok",false): _finish(); return
	var was_paused: bool = session.simulation_paused
	session.simulation_paused = true
	_reject(id,"paused","synchronous pause guard fixture")
	session.simulation_paused = was_paused
	var was_enabled: bool = body.enabled
	body.enabled = false
	_reject(id,"player_disabled","synchronous enabled guard fixture")
	body.enabled = was_enabled
	_reject("F1:pollinator_01","other_region","actual resident from another region")
	_reject("I1:qa_unknown_contact","actor_missing","unknown resident")
	wall = StaticBody3D.new()
	wall.name = "QAContactOpaqueObstacle"
	wall.collision_layer = 1
	wall.collision_mask = 0
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3.ONE*0.3
	shape.shape = box
	wall.add_child(shape)
	var mesh := MeshInstance3D.new()
	var cube := BoxMesh.new()
	cube.size = box.size
	mesh.mesh = cube
	wall.add_child(mesh)
	session.world.add_child(wall)
	wall.global_position = body.global_position.lerp(reply.position,0.5)
	for unused in 2:
		if not await _frame(): return
	_check(_clear_pose(body.global_position),"temporary opaque obstacle does not overlap complete player hull")
	_reject(id,"occluded","temporary opaque QA geometry")
	wall.queue_free()
	wall = null
	for unused in 2:
		if not await _frame(): return
	reply = Contact.prepare(session,1,id)
	if not _check(reply.get("ok",false) and session.story.nearest(body.global_position) == id,"removing QA obstacle restores original ready/nearest gates"): _finish(); return
	var actor: Dictionary = session.ecology.simulation.get_actor(id)
	if not await _g(): return
	_check(actions == [{"peer":1,"target":id}] and dialogues.size() == 1,"one native G reaches original explore action and solo requester dialogue exactly once")
	if dialogues.size() != 1: _finish(); return
	var event: Dictionary = dialogues[0]
	_check(event.get("character_id") == id and event.get("speaker_name") == actor.name and event.get("lines",[]).size() >= 2 and event.lines[0] == actor.purpose,"original event carries actual resident name and I1 duty")
	for text: String in event.get("lines",[]):
		var visible: bool = session.interface.radio.visible
		var speaker: String = session.interface.radio_speaker.text
		var actual: String = session.interface.radio_text.text
		report.radio.append({"visible":visible,"speaker":speaker,"text":actual})
		_check(visible and speaker == actor.name and actual == text,"original GUI shows each actual line with resident name")
		if not await _g(): return
	_check(not session.interface.radio.visible and session.interface.radio_queue.is_empty() and actions.size() == 1 and dialogues.size() == 1,"successive native G closes original dialogue without another action")
	_check(_protected() == before,"Story, choices, objective/Story receipts and personal/guest rewards unchanged")
	_check(not session.boss_active and not session.boss_campaign and not session.inputs.test_enabled,"no Boss start or test input source")
	report["generation_after"] = session.store.snapshot().generation
	report["ecology_tick"] = session.ecology.simulation.snapshot().tick
	_compatibility()
	_finish()
func _near(id: String) -> bool:
	for offset: Vector3 in [Vector3(0,3.2,0),Vector3(3,1,0),Vector3(-3,1,0),Vector3(0,1,3),Vector3(0,1,-3)]:
		var presented: Node3D = session.ecology.view.actors[id]
		var at := presented.global_position+offset
		if not _clear_pose(at): continue
		var body: FlightBodyV2 = session.players[1]
		body.freeze = true
		body.global_transform = Transform3D(Basis.IDENTITY,at)
		body.force_update_transform()
		PhysicsServer3D.body_set_state(body.get_rid(),PhysicsServer3D.BODY_STATE_TRANSFORM,body.global_transform)
		body.linear_velocity = Vector3.ZERO
		body.angular_velocity = Vector3.ZERO
		body.hold_height = at.y
		report.poses.append({"at":at,"kind":"explicit_QA_player_only_not_flown","physics_frame":Engine.get_physics_frames()})
		for unused in 2:
			if not await _frame(): return false
		if _clear_pose(body.global_position) and Contact.prepare(session,1,id).get("ok",false) and session.story.nearest(body.global_position) == id: return true
	return false
func _clear_pose(at: Vector3) -> bool:
	if not Regions.contains("I1",at): return false
	var body: FlightBodyV2 = session.players[1]
	var envelope := body.get_node("Envelope") as CollisionShape3D
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = envelope.shape
	query.transform = Transform3D(Basis.IDENTITY,at)*envelope.transform
	query.collision_mask = 1|2|8|32
	query.exclude = [body.get_rid()]
	return session.world.get_world_3d().direct_space_state.intersect_shape(query,1).is_empty()
func _protected() -> Dictionary:
	var saved: Dictionary = session.store.snapshot()
	return {"story":session.story.state.duplicate(true),"saved_story":saved.world.get("actions",{}).duplicate(true),"choices":saved.world.choices.duplicate(true),"objectives":saved.world.completed_objectives.duplicate(),"personal":saved.personal.duplicate(true),"received":saved.ledger.guest_received.duplicate(true),"outbox":saved.ledger.guest_outbox.duplicate(true)}
func _reject(id: String,expected: String,label: String) -> void:
	var actual: Dictionary = Contact.prepare(session,1,id)
	_check(not actual.get("ok",false) and actual.get("code") == expected,label+" rejects",actual)
func _g() -> bool:
	_key(true)
	if not await _frame(): return false
	_key(false)
	return await _frame()
func _key(down: bool) -> void:
	var event := InputEventKey.new()
	event.keycode = KEY_G
	event.physical_keycode = KEY_G
	event.pressed = down
	Input.parse_input_event(event)
func _frame() -> bool:
	await physics_frame
	await process_frame
	return not finished
func _compatibility() -> void:
	var sha := FileAccess.get_sha256(OLD)
	var file := FileAccess.open(OLD,FileAccess.READ)
	if not _check(file != null and file.get_length() <= 16777216,"fixed g426 compatibility input exists within original Store bound"): return
	var outer: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	if not _check(outer is Dictionary and outer.get("payload_json") is String and outer.get("payload_sha256") == str(outer.payload_json).sha256_text(),"fixed g426 original payload checksum is valid"): return
	var payload: Variant = JSON.parse_string(outer.payload_json)
	var saved: Dictionary = payload.get("world",{}).get("ecology",{}).get("simulation",{}) if payload is Dictionary else {}
	var built: Dictionary = session.ecology._expanded_simulation(int(saved.get("seed",0)))
	var restored: Dictionary = built.simulation.restore(saved) if built.get("ok",false) else {"ok":false}
	report["g426_compatibility"] = {"path":OLD,"sha256_before":sha,"sha256_after":FileAccess.get_sha256(OLD),"restore":restored}
	_check(restored.get("ok",false) and report.g426_compatibility.sha256_after == sha,"independent current ecology restores fixed g426 without changing its file")
func _check(ok: bool,label: String,actual: Variant = null) -> bool:
	var captured: Variant = actual.duplicate(true) if actual is Dictionary or actual is Array else actual
	report.checks.append({"passed":ok,"label":label,"actual":captured})
	return ok
func _finish() -> void:
	if finished: return
	finished = true
	_key(false)
	if is_instance_valid(wall): wall.queue_free()
	if is_instance_valid(session):
		session.active = false # QA terminal teardown, not normal player quit evidence.
		session.environment_save_gate.cancel("qa_npc_contact_teardown")
		session.network.close()
		session.audio.shutdown()
		var deadline := Time.get_ticks_msec()+1000
		var drain: Dictionary = {}
		while Time.get_ticks_msec() < deadline:
			drain = session.audio.shutdown_status()
			if drain.get("ready",false): break
			await process_frame
		_check(drain.get("ready",false),"original audio drains during bounded QA teardown",drain)
		if session.canal != null: session.canal.clear()
		session.thermal_cargo.clear()
		session.free()
	session = null
	await process_frame
	await physics_frame
	await process_frame
	report["actions"] = actions
	report["dialogues"] = dialogues
	report["engine_errors"] = logger.errors
	report["failures"] = report.checks.filter(func(row: Dictionary): return not row.passed)
	report["wall_seconds"] = float(Time.get_ticks_msec()-began)/1000.0
	print("NPC_CONTACT_PROBE_RESULT "+JSON.stringify(report))
	quit(0 if report.failures.is_empty() and logger.errors.is_empty() else 1)
