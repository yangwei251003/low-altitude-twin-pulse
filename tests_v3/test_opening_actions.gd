extends SceneTree
## Real scene / physics / transaction adapter. Scripted placements are not playtime evidence.
const Main = preload("res://scenes/v3/main.tscn")
const Store = preload("res://scripts/v3/core/twin_world_store.gd")
const Regions = preload("res://scripts/v3/world/twin_region_catalog.gd")
var session
var checks: Array = []
var failures: Array = []
var profile = ""
var capture_output = ""
var capture_index = 0

func _initialize() -> void:
	create_timer(90.0).timeout.connect(func():
		push_error("Opening action QA exceeded its 90-second deadline")
		quit(124))
	call_deferred("_run")

func travel_button(destination: String) -> Button:
	for child in session.interface.travel_choices.get_children():
		if child is Button and child.text.begins_with(str(Regions.definition(destination).name)):
			return child
	return null

func check(ok: bool, label: String) -> void:
	checks.append({"label":label, "passed":ok})
	if not ok:
		failures.append(label)
		print("FAIL ", label)

func place(at: Vector3) -> void:
	var body = session.players[1]
	body.freeze = true
	body.set_physics_process(false)
	body.global_position = at
	body.linear_velocity = Vector3.ZERO
	session.entities["player:1"].position = at
	await physics_frame
	await physics_frame

func explore(id: String, at: Vector3, expected: int) -> void:
	if not capture_output.is_empty(): session.interface.clear_dialogue()
	await place(at)
	session._action_received(1, "explore", {"target_id":id})
	check(int(session.story.state.revision) == expected, "nearby unobstructed " + id + " advances to " + str(expected))
	await capture(expected)

func observe(at: Vector3, expected: int) -> void:
	if not capture_output.is_empty(): session.interface.clear_dialogue()
	await place(at)
	session.story.observe(0.3)
	check(int(session.story.state.revision) == expected, "host spatial/fact observation advances to " + str(expected))
	await capture(expected)

func capture(revision: int) -> void:
	if capture_output.is_empty() or revision not in [1, 4, 7, 8, 9, 11, 13, 14, 15]: return
	capture_index += 1
	session.flight_camera.target_size = 26
	session.flight_camera.snap(session.players[1].global_position)
	session._refresh_interface()
	session.story.refresh(session.players[1].global_position)
	session.interface.vitals.text = "实际游戏视口 · 脚本摆位与操作 · 非真人试玩"
	await create_timer(0.2).timeout
	await RenderingServer.frame_post_draw
	var path = capture_output.path_join("%02d-%s-action-%02d.png" % [capture_index, session.region_id, revision])
	check(root.get_texture().get_image().save_png(path) == OK, "rendered story screenshot saved")

func ability(name: String, target: String, mode = "") -> void:
	session.cooldowns[1] = 0.0
	var before = int(session.stats.abilities)
	session._action_received(1, "ability", {"ability":name, "target_id":target, "mode":mode})
	check(session.stats.abilities == before + 1, "real ability accepted " + name + ":" + mode)

func tick_mechanisms() -> void:
	for i in range(100):
		session.world.synchronize(session.entities, 1.0 / 60)
		await physics_frame

func _run() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--qa-profile="): profile = arg.trim_prefix("--qa-profile=")
		if arg.begins_with("--capture-output="): capture_output = arg.trim_prefix("--capture-output=")
	if not capture_output.is_empty():
		if DisplayServer.get_name() == "headless":
			quit(2)
			return
		DirAccess.make_dir_recursive_absolute(capture_output)
	if not profile.begins_with("qa_opening_") or DirAccess.dir_exists_absolute("user://profiles_v3/" + profile):
		push_error("A unique qa_opening_ profile is required")
		quit(2)
		return
	check(Regions.entries().size() == 8, "catalog contains all eight planned stable region IDs")
	check(Regions.playable("I2") and Regions.can_travel("I1", "I2"), "integrated clinic is offered as the third development space")
	for id in ["I3", "I4", "F2", "F3", "F4"]:
		check(not Regions.playable(id) and not Regions.can_travel("I1", id), "unimplemented region remains unavailable: " + id)
	session = Main.instantiate()
	root.add_child(session)
	check(session.profile_ready and session.start_flight("solo"), "real main scene starts isolated solo profile")
	session.set_process(false)
	session.set_physics_process(false)
	session.inputs.set_process(false)
	session.inputs.set_physics_process(false)
	await place(Vector3(-18, 3, 40))
	session._action_received(1, "explore", {"target_id":"npc:linlan"})
	check(session.story.state.revision == 0, "remote interaction rejected")
	session._action_received(1, "explore", {"target_id":"I1:rescue_channel", "type":"fact", "option":"charge", "validated":true})
	check(session.story.state.revision == 0, "client cannot submit a mechanism fact")
	await place(Vector3(-18, 2.5, 35))
	var before: Dictionary = session.store.snapshot()
	session.store.failure_point = "before_publish"
	session._action_received(1, "explore", {"target_id":"npc:linlan"})
	check(session.story.state.revision == 0 and session.store.snapshot() == before, "failed publication leaves action and store unchanged")
	check(not session.interface.radio.visible, "failed publication emits no success dialogue")
	session.store.failure_point = ""
	await explore("npc:linlan", Vector3(-18, 2.5, 35), 1)
	check(session.interface.radio.visible, "saved interaction publishes actual radio dialogue")
	var queued_lines = session.interface.radio_queue.size()
	var virtual_key = InputEventKey.new()
	virtual_key.pressed = true
	virtual_key.keycode = KEY_G
	virtual_key.physical_keycode = KEY_F13
	session._unhandled_input(virtual_key)
	check(session.interface.radio_queue.size() == queued_lines - 1, "virtual special scan code falls back to printable G for radio")
	var saved_generation = session.store.snapshot().generation
	session._action_received(1, "explore", {"target_id":"npc:linlan"})
	check(session.story.state.revision == 1 and session.store.snapshot().generation == saved_generation, "repeat conversation does not recommit objective/rewards")
	check(session.store.fork_branch("before-route", "Before choosing route", false).ok, "independent branch saved before route")
	session.world_cache = session.store.snapshot()
	session.story.observe(0.3)
	check(session.story.state.revision == 1, "closed gate and no aerial arrival cannot advance")
	await place(Vector3(-14, 2.5, 20))
	ability("charge", "I1:relay")
	await tick_mechanisms()
	await observe(Vector3(-14, 2.5, 20), 2)
	check(session.story.state.choices["I1:rescue:channel"] == "charge", "host derives charge route from actual gate")
	await observe(Vector3(-24, 6.15, 21.2), 3)
	await place(Vector3(-20, 2.5, 32))
	session.store.failure_point = "before_publish"
	session.story.observe(0.3)
	check(session.story.state.revision == 3 and not session.interface.message.text.contains("检修机已恢复返航"), "failed final-objective save cannot announce the rescue outcome")
	session.story.refresh(session.players[1].position, 2.0)
	check(session.story.rescue_return == 0.0 and session.story.rescue_drone.position.is_equal_approx(Vector3(-24, 6.15, 21.2)), "failed rescue publication keeps maintenance drone at the actual rescue pocket")
	session.store.failure_point = ""
	await observe(Vector3(-20, 2.5, 32), 4)
	check(session.interface.message.text.contains("检修机已恢复返航") and session.interface.message.text.contains("烧痕"), "committed rescue names its result and next investigation")
	session.story.refresh(session.players[1].position, 1.0)
	check(is_equal_approx(session.story.rescue_return, 0.2) and session.story.rescue_drone.visible, "live committed rescue begins its return instead of jumping to the completed pose")
	var return_pose: Vector3 = session.story.rescue_drone.position
	session.story.refresh(session.players[1].position, 0.0)
	check(session.story.rescue_drone.position == return_pose, "paused zero-delta presentation retains return pose")
	# Same-session snapshot serial can precede reliable story state. This models
	# that existing ready transition, not an end-to-end network timing test.
	session.story.ready = false
	session.story.refresh(session.players[1].position, 1.0)
	check(not session.story.rescue_drone.visible and session.story.rescue_drone.position == return_pose, "waiting for authoritative story state hides and freezes the known return pose")
	session.story.ready = true
	session.story.refresh(session.players[1].position, 1.0)
	check(is_equal_approx(session.story.rescue_return, 0.4), "later story serial resumes existing return rather than treating it as first synchronization")
	session.story.refresh(session.players[1].position, 4.0)
	var reception_pose = Vector3(-20, 4, 32)
	check(session.story.rescue_return == 1.0 and session.story.rescue_drone.visible and session.story.rescue_drone.position.is_equal_approx(reception_pose), "rescued maintenance drone remains visible at the existing reception beacon")
	check(session.story.rescue_status.visible, "nearby completed rescue is identified as the maintenance drone")
	session.story.refresh(reception_pose + Vector3.RIGHT * 13, 0.0)
	check(not session.story.rescue_status.visible, "standby identity does not clutter distant exploration")
	session.interface.clear_dialogue()
	await capture(4)
	session._load_region("I1")
	await physics_frame
	await physics_frame
	check(session.story.rescue_return == 1.0 and session.story.rescue_drone.visible and session.story.rescue_drone.position.is_equal_approx(reception_pose), "real region reload restores committed standby immediately without replaying evacuation")
	session.interface.message.text = "repeat probe"
	session.story.observe(0.3)
	check(session.interface.message.text == "repeat probe", "repeat spatial observation does not replay completion announcement")
	check("opening:rescue_log" in session.store.snapshot().personal.discoveries, "first action grants durable discovery")
	await explore("I1:burn_trace", Vector3(-12, 2.5, 14), 5)
	await explore("npc:ruanheng", Vector3(-10.5, 2.5, 18), 6)
	await explore("I1:energy_ledger", Vector3(-21, 6.8, 25), 7)
	await explore("I1:beacon_echo", Vector3(29, 5.2, 34), 8)
	check(session.story.info().next_region == "F1", "next world is a result of evidence, not a reset")
	check(session.story.objective_text(session.players[1].position).contains("靠近跨界信标"), "locked travel guidance names the real prerequisite")
	session._ui_action("travel", {})
	check(session.interface.travel.visible and travel_button("F1") != null and travel_button("F1").disabled and travel_button("I2") != null and travel_button("I2").disabled, "actual multi-destination menu shows both locked routes before prerequisites")
	session._ui_action("travel_to", {"region_id":"F1"})
	check(session.region_id == "I1" and not session.world.restored_gate, "actual travel input still refuses before beacon restoration")
	session._action_received(1, "interact", {})
	check(session.world.restored_gate, "real beacon repair unlocks travel")
	await place(Vector3(-18, 2.5, 35))
	var travel_text: String = session.story.objective_text(session.players[1].position)
	check(travel_text.contains("按 M 选择巨木神殿") and not travel_text.contains("靠近跨界信标"), "restored travel guidance names destination selection without sending the player back across the map")
	await capture(8)
	session._ui_action("travel", {})
	check(session.region_id == "I1" and session.interface.travel.visible and travel_button("F1") != null and not travel_button("F1").disabled and travel_button("I2").disabled, "repaired beacon enables only F1 while clinic keeps its own prerequisite")
	if travel_button("F1") != null and not travel_button("F1").disabled: travel_button("F1").pressed.emit()
	check(session.region_id == "F1" and session.story.state.revision == 8, "travel preserves opening action state")
	if session.region_id != "F1":
		session.network.close()
		session.queue_free()
		await process_frame
		quit(1)
		return
	await explore("npc:atai", Vector3(-29, 2.5, 31), 9)
	await explore("F1:dry_nursery", Vector3(-18.5, 3.3, 31), 10)
	await observe(Vector3(13, 4.7, 32), 11)
	await explore("npc:atai", Vector3(-29, 2.5, 31), 12)
	session.story.observe(0.3)
	check(session.story.state.revision == 12, "unaligned light cannot complete optical objective")
	await place(Vector3(-24, 5.2, 29))
	ability("light", "F1:mirror")
	ability("light", "F1:mirror")
	await tick_mechanisms()
	await observe(Vector3(-24, 5.2, 29), 13)
	check(session.entities["F1:growth"].environment_light >= 1, "real ray reaches growth receiver")
	var elapsed: Dictionary = session.rules.advance_states(session.entities, 30.0)
	session.rules.commit(elapsed, session.entities)
	session.world.synchronize(session.entities, 0.0)
	check(session.entities["F1:growth"].environment_light >= 1, "environmental light stays aligned after thirty seconds instead of forcing a timer sprint")
	await place(Vector3(-18, 6.4, 29))
	ability("growth", "F1:growth")
	ability("growth", "F1:growth")
	session.world.synchronize(session.entities, 0.0)
	await observe(Vector3(-18, 6.4, 29), 14)
	await place(Vector3(-24, 5.2, 29))
	ability("light", "F1:mirror", "off")
	session.world.synchronize(session.entities, 0.0)
	await explore("F1:shared_junction", Vector3(29, 5.2, 34), 14)
	check(session.story.state.completed_actions.size() == 3, "repair cannot be certified while actual light is off")
	# Restore saved physical state at objective 14, as a real reload would.
	session._load_region("F1")
	await physics_frame
	await physics_frame
	session.world.synchronize(session.entities, 0.0)
	await explore("F1:shared_junction", Vector3(29, 5.2, 34), 15)
	check(session.interface.message.text.contains("局部回流停止") and session.interface.message.text.contains("鲸机"), "repair outcome points at the actual next boss action")
	check(not session.story.info().complete and session.story.state.completed_actions.size() == 4 and session.story.info().action_id == "I1:whale", "original four actions finish and unlock the authored whale continuation")
	await explore("F1:secret:seasonal_rest", Vector3(-35, 1.6, -12), 15)
	check("secret:grove:seasonal_rest" in session.store.snapshot().personal.discoveries, "cave note has its own durable discovery")
	var note_generation = session.store.snapshot().generation
	await explore("F1:secret:seasonal_rest", Vector3(-35, 1.6, -12), 15)
	check(session.store.snapshot().generation == note_generation, "rereading secret adds no duplicate commit")
	check(session.story.state.completed.size() == 15, "optional secret does not inflate main objective count")
	var visitor = Store.new("user://qa_v3_opening/" + profile + "-guest")
	check(visitor.load_profile().ok and visitor.commit({"id":"bootstrap"}).ok, "isolated guest profile exists")
	var guest_identity: String = visitor.snapshot().profile_id
	session.network.guests[2] = guest_identity
	session.store.failure_point = "before_publish"
	session._guest_joined(2, guest_identity)
	check(session.store.pending_guest_receipts(guest_identity).is_empty() and session.receipt_catchup.has(guest_identity), "failed join catch-up remains queued")
	session.store.failure_point = ""
	session._retry_receipt_catchup()
	check(not session.receipt_catchup.has(guest_identity) and session.store.pending_guest_receipts(guest_identity).size() >= session.story.state.discoveries.size(), "online catch-up recovers without reconnect")
	for receipt in session.store.pending_guest_receipts(guest_identity):
		check(visitor.apply_guest_receipt(receipt).ok, "visitor accepts recovered discovery receipt")
	check("opening:shared_repair_record" in visitor.snapshot().personal.discoveries, "recovered catch-up includes completed repair")
	session._guest_left(2)
	session.network.guests.erase(2)
	var final_state: Dictionary = session.story.state.duplicate(true)
	var final_discoveries: Array = session.store.snapshot().personal.discoveries.duplicate()
	var fresh_store = Store.new(session.store.root_path)
	check(fresh_store.load_profile().ok, "fresh reader opens published profile")
	check(session.story.director.validate_state(fresh_store.snapshot().world.actions.opening).ok, "JSON reload reconstructs validated action receipts")
	session._reset_players()
	check(session.story.state == final_state, "failure retry preserves committed story")
	session.story.last_blink[1] = {"time":Time.get_ticks_msec(), "position":Vector3(13, 3.8, 32)}
	session.story._root_route[1] = Time.get_ticks_msec()
	session._ui_action("branch", {"id":"before-route"})
	check(session.story.state.revision == 1 and session.region_id == "I1", "branch switch restores earlier action and region")
	check(session.story.last_blink.is_empty() and session.story._root_route.is_empty(), "branch restore cannot reuse route proof from another world state")
	check(session.story.rescue_return == 0.0 and session.story.rescue_drone.visible and session.story.rescue_drone.position.is_equal_approx(Vector3(-24, 6.15, 21.2)), "earlier branch restores the still-stranded maintenance drone")
	check(session.store.snapshot().personal.discoveries == final_discoveries, "branch switch retains personal discoveries")
	await observe(Vector3(-24, 6.15, 21.2), 2)
	check(session.story.state.choices["I1:rescue:channel"] == "aerial", "closed-door alternative uses real upper rear position")
	# Reliable action state may arrive before/after its motion snapshot.
	var expected: Dictionary = session.story.state.duplicate(true)
	var event = {"session_id":session.network.session_id, "serial":500, "state":expected, "ready":true}
	session.network.mode = "guest"
	session.owns_world = false
	session.story.reset_connection()
	session.received_session = ""
	session.story.receive(event)
	check(not session.story.ready, "early reliable state waits for session snapshot")
	session.received_session = event.session_id
	session.story.consume(500)
	check(session.story.ready and session.story.state == expected, "matching snapshot activates reliable state")
	session.story.refresh(Vector3.ZERO, 0.0)
	check(session.story.rescue_return == 0.0 and session.story.rescue_drone.visible, "first guest state establishes an unfinished rescue visual baseline")
	var applied = session.story.state_applications
	for i in range(100): session.story.consume(500)
	check(session.story.state_applications == applied, "unchanged motion snapshots do not replay or copy action receipts")
	session.story.consume(501)
	check(not session.story.ready, "new snapshot hides obsolete action state")
	session.story.refresh(Vector3.ZERO, 1.0)
	check(not session.story.rescue_drone.visible and session.story.rescue_return == 0.0, "actual next-serial consumption waits without discarding the guest visual baseline")
	var newer = event.duplicate(true)
	newer.serial = 501
	newer.state = final_state
	session.story.receive(newer)
	check(session.story.ready and session.story.state == final_state, "late reliable state restores current progress")
	session.story.refresh(Vector3.ZERO, 1.0)
	check(is_equal_approx(session.story.rescue_return, 0.2) and session.story.rescue_drone.visible, "actual late reliable completion animates for an already synchronized guest")
	session.story.receive(event)
	check(session.story.state == final_state, "old reliable replay cannot regress progress")
	newer.serial = 502
	newer.session_id = "another-session"
	session.story.receive(newer)
	check(session.story.state == final_state, "different session cannot replace story")
	session.story.reset_connection()
	newer.session_id = event.session_id
	newer.serial = 503
	session.story.receive(newer)
	session.story.consume(503)
	session.story.refresh(Vector3.ZERO, 0.0)
	check(session.story.ready and session.story.rescue_return == 1.0 and session.story.rescue_drone.visible and session.story.rescue_drone.position.is_equal_approx(reception_pose), "reconnected guest restores completed standby without replaying rescue")
	var report = {"checks":checks, "count":checks.size(), "failures":failures, "qa_profile":profile, "scope":"real production scene, physics queries and durable transactions; scripted placement, no human playtime or two-PC LAN claim"}
	var path = "res://artifacts/v3/opening-actions-" + profile + ".json"
	var file = FileAccess.open(path, FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t"))
	file.close()
	print("OPENING_ACTIONS_RESULT ", JSON.stringify({"checks":checks.size(), "failures":failures, "report":path}))
	session.network.close()
	session.free()
	quit(0 if failures.is_empty() else 1)
