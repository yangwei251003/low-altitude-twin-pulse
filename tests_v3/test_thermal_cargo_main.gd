extends SceneTree
## Original MAIN/Session/Story G/SaveGate/Consensus over one unique empty QA
## profile. Only initial I3 availability/location and the initial aircraft
## observation pose are fixtures; every loaded movement uses native Flight.
const MAIN = preload("res://scenes/v3/main.tscn")
const Regions = preload("res://scripts/v3/world/twin_region_catalog.gd")
const Cargo = preload("res://scripts/v3/gameplay/twin_thermal_cargo_session.gd")
const Pilot = preload("res://scripts/v3/gameplay/canal/canal_transport_physics/transport_pilot.gd")
const Store = preload("res://scripts/v3/core/twin_world_store.gd")
const Codec = preload("res://scripts/v3/network/twin_snapshot_codec.gd")

class ErrorLogger extends Logger:
	var guard := Mutex.new()
	var errors: Array = []
	func _log_error(function: String,file: String,line: int,code: String,rationale: String,_notify: bool,kind: int,_trace: Array[ScriptBacktrace]) -> void:
		if kind == Logger.ERROR_TYPE_WARNING: return
		guard.lock()
		errors.append({"function":function,"file":file,"line":line,"code":code,"rationale":rationale})
		guard.unlock()

class FlightCommands extends Node:
	var owner_session: Node
	var pilot: RefCounted
	func _physics_process(delta: float) -> void:
		if not is_instance_valid(owner_session) or not owner_session.active or owner_session.simulation_paused or pilot == null: return
		if not owner_session.thermal_cargo.supported() or not owner_session.thermal_cargo.module.status().assist.is_empty(): return
		# Runs after ordinary Session input and its single normal module tick.
		# Only commands the real Flight; never advances a second simulation.
		pilot.tick(delta,true,false)

var logger := ErrorLogger.new()
var session: Node
var driver: FlightCommands
var profile := ""
var output := ""
var finished := false
var checks: Array = []
var phases: Dictionary = {}
var callbacks: Array = []
var expected: Dictionary = {}
var restored: Dictionary = {}
var identity := ""
var start_frame := 0

func _initialize() -> void:
	OS.add_logger(logger)
	_run.call_deferred()

func _run() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--qa-profile="): profile = arg.trim_prefix("--qa-profile=")
		if arg.begins_with("--output="): output = arg.trim_prefix("--output=")
	if not profile.begins_with("qa_thermal_cargo_main_") or profile != profile.validate_filename() or not output.begins_with("res://artifacts/v3/thermal-cargo-main-") or ".." in output or DirAccess.dir_exists_absolute(output) or DirAccess.dir_exists_absolute("user://profiles_v3/"+profile):
		quit(2)
		return
	DirAccess.make_dir_recursive_absolute(output)
	start_frame = Engine.get_physics_frames()
	create_timer(45.0).timeout.connect(func():
		if not finished: _check(false,"45 second actual MAIN thermal bound",_diagnostics()); _finish())
	Regions._entries = Regions.entries()
	for item: Dictionary in Regions._entries:
		if item.id == "I3": item["playable"] = true # Process-local availability fixture only.
	if not _new_main(true) or not _initial_observation_pose(): _finish(); return
	var low_ready := false
	for _step in range(240):
		if not await _frame(): return
		if _module().ready and _module()._row().phase == "docked": low_ready = true; break
	if not _check(low_ready,"ordinary MAIN observes original low-berth 350ms support",_diagnostics()): _finish(); return
	_check(session.story.state.get("completed",[]).is_empty() and session.store.snapshot().personal.discoveries.is_empty(),"empty QA has no prior Director prefix, completion or rewards")
	phases["low_support"] = _diagnostics()
	_press_g(Cargo.CARGO)
	var picked := false
	for _step in range(1200):
		if not await _frame(): return
		if session.players[1].cargo_items.has(Cargo.CARGO) and _module().status().assist.is_empty(): picked = true; break
	if not _check(picked,"original G/Story/Transport creates actual player 2kg load and finishes native short departure",_diagnostics()): _finish(); return
	var player: FlightBodyV2 = session.players[1]
	var item: Dictionary = player.cargo_items[Cargo.CARGO]
	_check(item.body == session.world.objects[Cargo.CARGO] and item.joint is PinJoint3D and item.joint.get_rid().is_valid() and item.joint.get_node(item.joint.node_a) == player and item.joint.get_node(item.joint.node_b) == item.body and player.cargo_kg == 2.0,"same original body and native Joint endpoints carry exact real 2kg mass")
	var packet: Dictionary = session._snapshot()
	var wire: Dictionary = Codec.encode(packet)
	var decoded: Dictionary = Codec.decode(wire) if not wire.is_empty() else {}
	var view: Dictionary = decoded.get("thermal_cargo",{})
	var native_pose: Array = Cargo._pose(PhysicsServer3D.body_get_state(item.body.get_rid(),PhysicsServer3D.BODY_STATE_TRANSFORM))
	_check(not view.is_empty() and view == packet.get("thermal_cargo",{}) and Cargo._f32_equal(view.get("pose",[]),native_pose) and view.get("weight_kg") == 2.0 and view.get("phase") == "carried" and view.get("role_identity") == session.identities[1],"actual MAIN complete thermal snapshot survives original Codec encode/decode with full native pose/2kg/carried/stable identity",{"view":view,"wire_empty":wire.is_empty()})
	print("THERMAL_MAIN_STAGE actual_G_pickup frame="+str(Engine.get_physics_frames()))
	if not _fly_to(Vector3(-8.2,5.2,18),1): _finish(); return
	var origin: Vector3 = player.global_position
	var moved := false
	for _step in range(600):
		if not await _frame(): return
		if player.global_position.distance_to(origin) >= .8 and player.linear_velocity.length() >= .35: moved = true; break
	if not _check(moved,"original Pilot commands actually fly the MAIN player and attached load at least .8m, speed >=.35m/s",_diagnostics()): _finish(); return
	if not await _save("moving"): _finish(); return
	var moving_disk: Dictionary = _disk_candidate()
	if not _check(not moving_disk.is_empty() and moving_disk.version == 2 and moving_disk.role_identity == identity and int(moving_disk.custody.row.serial) == 2,"independent original Store reader sees real carried state and original serial",moving_disk): _finish(); return
	phases["moving_store_event"] = moving_disk
	print("THERMAL_MAIN_STAGE moving_Store frame="+str(Engine.get_physics_frames()))
	if not await _pause_cycle(): _finish(); return
	_check(session.story.state.get("completed",[]).is_empty() and session.store.snapshot().personal.discoveries.is_empty() and session.thermal_cargo.fact(Cargo.FACT).is_empty(),"short actual flight/save/pause creates no high-dock/outer-route task credit or reward")
	await _close_main()
	if finished: return
	# Reopen the final immutable Store event after source teardown. Never compare
	# a moving host later against an older event-time physics packet.
	expected = _disk_candidate()
	if not _check(not expected.is_empty() and expected.version == 2,"final published original carried candidate available for fresh MAIN"): _finish(); return
	if not _new_main(false): _finish(); return
	player = session.players[1]
	var body: RigidBody3D = session.world.objects[Cargo.CARGO]
	var native_ok: bool = Cargo._native_readback(player,expected.carrier) and Cargo._native_readback(body,expected.cargo)
	var same_serial: bool = int(_module()._custody.last_serial) == int(expected.custody.last_serial)
	var actual_joint: bool = player.cargo_kg == 2.0 and player.cargo_items.has(Cargo.CARGO) and player.cargo_items[Cargo.CARGO].body == body and player.cargo_items[Cargo.CARGO].joint is PinJoint3D
	restored = {"identity":session.identities[1],"same_identity":session.identities[1] == identity,"same_serial":same_serial,"native_pose_momentum":native_ok,"actual_joint":actual_joint,"serial":_module()._custody.last_serial,"expected_serial":expected.custody.last_serial}
	if not _check(restored.same_identity and same_serial and native_ok and actual_joint,"fresh normal MAIN/same profile restores original one-cargo native Joint, pose and momentum without new serial",restored): _finish(); return
	_check(_module()._custody._integrity(Cargo.CARGO).is_empty() and session.thermal_cargo.fact(Cargo.FACT).is_empty(),"fresh actual native integrity is valid without manufactured delivery fact")
	if not _fly_to(Vector3(-8.2,5.2,18),2): _finish(); return
	for _step in range(18):
		if not await _frame(): return
	_check(_module()._custody._integrity(Cargo.CARGO).is_empty() and session.active and player.cargo_items.has(Cargo.CARGO),"fresh MAIN continues ordinary native loaded flight across actual physics ticks",_diagnostics())
	print("THERMAL_MAIN_STAGE fresh_MAIN_restored frame="+str(Engine.get_physics_frames()))
	_finish()

func _new_main(first: bool) -> bool:
	session = MAIN.instantiate()
	session.thermal_cargo.enabled = true # Explicit QA-only participant opt-in.
	root.add_child(session)
	if not _check(session.profile_ready,"ordinary MAIN opens isolated original QA Store",_diagnostics()): return false
	if first:
		var fixture: Dictionary = session.store.commit({"id":"qa-thermal-start-location","set":{"world.region_id":"I3"}})
		if not _check(fixture.get("ok",false),"only initial QA location set to I3; no Director or mechanism state fixture",fixture): return false
		session.world_cache = session.store.snapshot()
		identity = str(session.world_cache.profile_id)
	var started: bool = session.start_flight("solo")
	if not _check(started and session.active and session.region_id == "I3" and session.thermal_cargo.supported(),"original MAIN starts I3 and binds after actual player exists",_diagnostics()): return false
	session.inputs.test_enabled = true
	session.inputs.test_frame = {"axes":{},"held":["brake"],"edges":[]}
	driver = FlightCommands.new()
	driver.process_physics_priority = 10
	driver.owner_session = session
	root.add_child(driver)
	return true

func _initial_observation_pose() -> bool:
	var actor: FlightBodyV2 = session.players[1]
	var at := Vector3(-10,4.1,18)
	var envelope: CollisionShape3D = actor.get_node("Envelope")
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = envelope.shape
	query.transform = Transform3D(Basis.IDENTITY,at)*envelope.transform
	query.collision_mask = Cargo.MASK
	query.exclude = [actor.get_rid()]
	query.margin = .001
	var hits: Array[Dictionary] = session.world.get_world_3d().direct_space_state.intersect_shape(query,8)
	if not _check(hits.is_empty(),"initial QA aircraft observation pose above actual LOW has real full-envelope clearance",{"at":at,"hits":hits.map(func(hit: Dictionary): return str(hit.collider.get_path()))}): return false
	# The only test-authored aircraft pose, before any loaded flight. Cargo,
	# berth, physics time, Joint and route state are never written by this test.
	actor.global_transform = Transform3D(Basis.IDENTITY,at)
	actor.force_update_transform()
	PhysicsServer3D.body_set_state(actor.get_rid(),PhysicsServer3D.BODY_STATE_TRANSFORM,actor.global_transform)
	actor.linear_velocity = Vector3.ZERO
	actor.angular_velocity = Vector3.ZERO
	actor.hold_height = at.y
	actor.safe_position = at
	return true

func _press_g(id: String) -> void:
	session.network.send_action("lock",{"target_id":id})
	var event := InputEventKey.new()
	event.physical_keycode = KEY_G
	event.keycode = KEY_G
	event.pressed = true
	session._unhandled_input(event)

func _fly_to(point: Vector3,serial: int) -> bool:
	driver.pilot = Pilot.new()
	return _check(driver.pilot.bind(session.players[1]) and driver.pilot.go_to(point,serial),"canonical original Pilot receives actual player waypoint",point)

func _save(label: String) -> bool:
	for _step in range(120):
		if not session.environment_save_gate.pending(): break
		if not await _frame(): return false
	var count: int = callbacks.size()
	var generation: int = int(session.store.snapshot().generation)
	var request: Dictionary = session.request_environment_save(func(result: Dictionary): callbacks.append(result.duplicate(true)))
	if not _check(request.get("ok",false) and callbacks.size() == count,"original asynchronous SaveGate accepts "+label,request): return false
	for _step in range(240):
		if not await _frame(): return false
		if callbacks.size() > count: break
	return _check(callbacks.size() == count+1 and callbacks[count].get("ok",false) and callbacks[count].get("completed",false) and int(session.store.snapshot().generation) > generation,"original SaveGate commits actual "+label+" state through original Store exactly one completion",{"callbacks":callbacks,"commit":session.last_commit_result,"generation":session.store.snapshot().generation})

func _pause_cycle() -> bool:
	session._request_pause()
	var proposal: Dictionary = session.consensus.current_proposal()
	if not _check(not session.simulation_paused and proposal.get("kind") == "pause" and proposal.get("state") == "ready" and session.thermal_cargo.pause_status().get("pending",false),"original Consensus retains ready proposal until real thermal pause boundary",{"proposal":proposal,"pause":session.thermal_cargo.pause_status()}): return false
	for _step in range(240):
		if not await _frame(): return false
		if session.simulation_paused: break
	var saved: Dictionary = _module().paused_saved_state()
	if not _check(session.simulation_paused and saved.get("ok",false) and session.consensus.current_proposal().is_empty() and session.players[1].freeze and session.world.objects[Cargo.CARGO].freeze,"normal MAIN completes Consensus after real player/load capture and freeze",_diagnostics()): return false
	var serial: int = int(_module()._custody.last_serial)
	var count: int = int(_module().pause_request_status().resume_count)
	var records: Array = _module()._pause_bodies.duplicate()
	for _step in range(5):
		if not await _frame(): return false
	_check(int(_module()._custody.last_serial) == serial and _module().paused_saved_state().state == saved.state,"paused normal ticks preserve original serial and cached full state")
	if not await _save("paused cached carried"): return false
	var disk: Dictionary = _disk_candidate()
	_check(not disk.is_empty() and session.store.matches_persisted_value(saved.state,disk),"original Store publishes original pause cache rather than cleared frozen momentum")
	phases["paused_store_event"] = disk
	session._request_pause() # Original solo Consensus resumes synchronously.
	var same: bool = not session.simulation_paused and session.consensus.current_proposal().is_empty() and int(_module().pause_request_status().resume_count) == count+1
	for record in records:
		var body: RigidBody3D = record.body.get_ref()
		same = same and not body.freeze and Cargo._native_readback(body,record.physical)
	if not _check(same,"original Consensus restores real native player/load momentum once without pose write",_diagnostics()): return false
	var before: Dictionary = Cargo._body_snapshot(session.players[1])
	session._apply_pause_state()
	_check(int(_module().pause_request_status().resume_count) == count+1 and Cargo._body_snapshot(session.players[1]) == before,"repeated ordinary Session unpause cannot inject cached momentum again")
	print("THERMAL_MAIN_STAGE original_Consensus_pause_resume frame="+str(Engine.get_physics_frames()))
	return true

func _disk_candidate() -> Dictionary:
	var reader = Store.new("user://profiles_v3/"+profile)
	var opened: Dictionary = reader.load_profile()
	if not _check(opened.get("ok",false),"independent original Store opens isolated QA generation",opened): return {}
	return reader.snapshot().world.get("environment",{}).get("I3_thermal_cargo",{}).duplicate(true)

func _module():
	return session.thermal_cargo.module

func _frame() -> bool:
	await physics_frame
	await process_frame
	return not finished

func _diagnostics() -> Dictionary:
	if not is_instance_valid(session): return {"session":"not_installed"}
	return {"active":session.active,"region":session.region_id,"message":session.interface.message.text if is_instance_valid(session.interface) else "no_ui", "generation":session.store.snapshot().generation if session.store != null else -1,
		"participant_error":session.thermal_cargo.error,"module":session.thermal_cargo.module.status() if session.thermal_cargo.module != null else {},"world_errors":session.world.build_errors if is_instance_valid(session.world) else [],"commit":session.last_commit_result,
		"player_pose":Cargo._pose(session.players[1].global_transform) if session.players.has(1) else [],"player_velocity":Cargo._xyz(session.players[1].linear_velocity) if session.players.has(1) else []}

func _check(ok: bool,label: String,actual: Variant = null) -> bool:
	checks.append({"passed":ok,"label":label,"actual":actual})
	return ok

func _close_main() -> void:
	if is_instance_valid(driver): driver.owner_session = null; driver.free()
	driver = null
	if is_instance_valid(session):
		session.environment_save_gate.cancel("qa_main_reopen")
		session.thermal_cargo.clear()
		session.network.close()
		session.free()
	session = null
	await process_frame
	await physics_frame
	await process_frame

func _finish() -> void:
	if finished: return
	finished = true
	var diagnostics: Dictionary = _diagnostics()
	await _close_main()
	var failures: Array = checks.filter(func(row: Dictionary): return not row.passed)
	var report := {"checks":checks,"failures":failures,"engine_errors":logger.errors,"phases":phases,"callbacks":callbacks,"fresh_expected_event":expected,"restored":restored,"diagnostics":diagnostics,"actual_physics_frames":Engine.get_physics_frames()-start_frame,
		"scope":"Actual original MAIN over one unique initially empty QA Store; only process-local I3 playable and initial I3 region location plus one collision-checked initial player observation pose are fixtures. Original G/Story/Transport creates real 2kg native Joint; canonical original Pilot commands short real loaded flight without manual module/solver advance or transit pose writes. Original SaveGate commits actual moving and paused native candidates to original Store, original Consensus waits for native pause boundary and resumes momentum once, actual thermal snapshot survives original Codec, fresh MAIN same-profile reload rebuilds actual one-load Joint/serial/native pose/momentum and continues physics. No prior Director fixture, high-dock route credit, human playability, graphics/performance, normal unlock, disconnect, two-machine LAN or full-campaign acceptance claim."}
	FileAccess.open(output+"/result.json",FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
	print("THERMAL_CARGO_MAIN_RESULT "+JSON.stringify({"checks":checks.size(),"failures":failures,"engine_errors":logger.errors,"restored":restored,"physics_frames":report.actual_physics_frames}))
	quit(0 if failures.is_empty() and logger.errors.is_empty() and not restored.is_empty() else 1)
