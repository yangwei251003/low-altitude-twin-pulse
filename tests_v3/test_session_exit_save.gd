extends SceneTree
## Production MAIN Session initialization/physics/Store; only the final process
## exit is observed instead of executed. No SaveGate operation is replaced.
const MAIN = preload("res://scenes/v3/main.tscn")
const Regions = preload("res://scripts/v3/world/twin_region_catalog.gd")
const Cargo = preload("res://scripts/v3/gameplay/twin_thermal_cargo_session.gd")
const Pilot = preload("res://scripts/v3/gameplay/canal/canal_transport_physics/transport_pilot.gd")
const Store = preload("res://scripts/v3/core/twin_world_store.gd")

class ExitProbe extends "res://scripts/v3/twin_session.gd":
	var quit_records: Array = []
	func _complete_quit() -> void:
		# Deliberately replace only OS/process termination. Original callers have
		# already decided whether the original Store transaction really succeeded.
		quit_records.append({"physics_frame":Engine.get_physics_frames(),"store":store.snapshot(),
			"cargo_capture":thermal_cargo.capture(),"last_commit_result":last_commit_result.duplicate(true)})

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
		pilot.tick(delta,true,false) # Commands only, after ordinary Session input.

var logger := ErrorLogger.new()
var session: ExitProbe
var driver: FlightCommands
var profile := ""
var output := ""
var finished := false
var complete := false
var checks: Array = []
var phases: Array = []
var callbacks: Array = []
var exit_record: Dictionary = {}
var failed_save: Dictionary = {}
var start_frame := 0

func _initialize() -> void:
	OS.add_logger(logger)
	_run.call_deferred()

func _run() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--qa-profile="): profile = arg.trim_prefix("--qa-profile=")
		if arg.begins_with("--output="): output = arg.trim_prefix("--output=")
	if not profile.begins_with("qa_session_exit_save_") or profile != profile.validate_filename() or not output.begins_with("res://artifacts/v3/session-exit-save-") or ".." in output or DirAccess.dir_exists_absolute(output) or DirAccess.dir_exists_absolute("user://profiles_v3/"+profile):
		quit(2)
		return
	DirAccess.make_dir_recursive_absolute(output)
	start_frame = Engine.get_physics_frames()
	create_timer(30.0).timeout.connect(func():
		if not finished: _check(false,"30 second real Session lifecycle bound",_diagnostics()); _finish())
	if not _check(MAIN.get_state().get_node_count() == 1,"normal MAIN scene contains only the inherited production Session root"): _finish(); return
	if not await _proposal_guard(): _finish(); return
	await _close_session()
	if finished: return
	if not _prepare_i3_location() or not _new_session("I3") or not _initial_i3_pose(): _finish(); return
	if not await _actual_loaded_flight(): _finish(); return
	if not await _failed_pending_exit(): _finish(); return
	if not await _successful_pending_exit(): _finish(); return
	complete = true
	_finish()

func _new_session(region: String) -> bool:
	session = ExitProbe.new()
	root.add_child(session)
	if not _check(session.profile_ready and session.start_flight("solo") and session.active and session.region_id == region,"production MAIN Session starts original QA world: "+region,_diagnostics()): return false
	session.inputs.test_enabled = true
	session.inputs.test_frame = {"axes":{},"held":["brake"],"edges":[]}
	return true

func _proposal_guard() -> bool:
	if not _new_session("I1"): return false
	if not _check(session.story.state.get("completed",[]).is_empty() and session.store.snapshot().personal.discoveries.is_empty(),"initial QA has no prior Director fixture, completed objective or reward"): return false
	var identity: String = Crypto.new().generate_random_bytes(16).hex_encode()
	# Only transport delivery is simulated. Both actual Flight bodies and the
	# original Consensus roster are constructed through the normal Session API.
	session.network.guests[2] = identity
	session._guest_joined(2,identity,"tr01")
	if not _check(session.players.size() == 2 and session.players.has(2),"original guest lifecycle constructs the second actual Flight for pending Consensus"): return false
	if not await _frame(): return false
	session._request_pause()
	var proposal: Dictionary = session.consensus.current_proposal()
	if not _check(proposal.get("kind") == "pause" and proposal.get("state") == "pending" and proposal.get("participants",[]).size() == 2 and proposal.get("confirmed",[]).size() == 1 and not session.simulation_paused,"original two-person pause genuinely awaits the other participant",proposal): return false
	var before: Dictionary = session.store.snapshot()
	var world_id: int = session.world.get_instance_id()
	var player_id: int = session.players[1].get_instance_id()
	var save_result: bool = session._save_environment()
	session._ui_action("quit",{})
	session._notification(Node.NOTIFICATION_WM_CLOSE_REQUEST)
	for _step: int in range(3):
		if not await _frame(): return false
	var disk: Dictionary = _read_disk("pending proposal")
	if not _check(not save_result and session.quit_records.is_empty() and session.active and session.world.get_instance_id() == world_id and session.players[1].get_instance_id() == player_id and session.players.size() == 2 and session.consensus.current_proposal() == proposal and not session.environment_save_gate.pending() and session.store.snapshot() == before and disk == before,"pending proposal is neither a successful save nor a menu/window exit; original world/roster/proposal/disk remain",{"save_returned":save_result,"proposal":session.consensus.current_proposal(),"diagnostics":_diagnostics(),"disk_generation":disk.get("generation")}): return false
	session.network.send_action("cancel",{"proposal_id":proposal.proposal_id})
	if not _check(session.consensus.current_proposal().is_empty() and session.quit_records.is_empty(),"explicit original cancel resolves the pending proposal without executing rejected exit"): return false
	_phase("I1_pending_proposal_refused_without_false_save")
	return true

func _prepare_i3_location() -> bool:
	Regions._entries = Regions.entries()
	for entry: Dictionary in Regions._entries:
		if entry.id == "I3": entry["playable"] = true # Process-local QA availability only.
	var control: RefCounted = Store.new("user://profiles_v3/"+profile)
	var loaded: Dictionary = control.load_profile()
	if not _check(loaded.get("ok",false),"original Store reopens the same unique QA after I1 teardown",loaded): return false
	var located: Dictionary = control.commit({"id":"qa-exit-save-I3-location-only","set":{"world.region_id":"I3"}})
	return _check(located.get("ok",false),"only next QA start location is set to I3; no Director/cargo/route state fixture",located)

func _initial_i3_pose() -> bool:
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
	if not _check(hits.is_empty(),"only initial I3 QA aircraft observation pose has actual full-envelope clearance",hits.map(func(hit: Dictionary): return str(hit.collider.get_path()))): return false
	actor.global_transform = Transform3D(Basis.IDENTITY,at)
	actor.force_update_transform()
	PhysicsServer3D.body_set_state(actor.get_rid(),PhysicsServer3D.BODY_STATE_TRANSFORM,actor.global_transform)
	actor.linear_velocity = Vector3.ZERO
	actor.angular_velocity = Vector3.ZERO
	actor.hold_height = at.y
	actor.safe_position = at
	return true

func _actual_loaded_flight() -> bool:
	for _step: int in range(240):
		if not await _frame(): return false
		if _module() != null and _module().ready and _module()._row().get("phase") == "docked": break
	if not _check(session.thermal_cargo.supported() and _module().ready and int(_module()._row().stable_usec) >= 350000,"ordinary MAIN observes original 350ms low-berth support",_diagnostics()): return false
	session.network.send_action("lock",{"target_id":Cargo.CARGO})
	var event := InputEventKey.new()
	event.physical_keycode = KEY_G
	event.keycode = KEY_G
	event.pressed = true
	session._unhandled_input(event)
	var picked := false
	for _step: int in range(900):
		if not await _frame(): return false
		if session.players[1].cargo_items.has(Cargo.CARGO) and _module().status().assist.is_empty(): picked = true; break
	if not _check(picked and _load_intact(),"original G/Custody picks the unique actual 2kg body with a real native Joint",_diagnostics()): return false
	driver = FlightCommands.new()
	driver.process_physics_priority = 10
	driver.owner_session = session
	driver.pilot = Pilot.new()
	root.add_child(driver)
	var actor: FlightBodyV2 = session.players[1]
	var origin: Vector3 = actor.global_position
	if not _check(driver.pilot.bind(actor) and driver.pilot.go_to(Vector3(-8.2,5.2,18),1),"canonical Pilot commands original actual loaded Flight"): return false
	for _step: int in range(600):
		if not await _frame(): return false
		if actor.global_position.distance_to(origin) >= .8 and actor.linear_velocity.length() >= .35: break
	if not _check(actor.global_position.distance_to(origin) >= .8 and actor.linear_velocity.length() >= .35 and _load_intact(),"actual player and Joint fly at least .8m before lifecycle capture",_diagnostics()): return false
	_phase("I3_real_G_pickup_and_native_loaded_motion")
	return true

func _failed_pending_exit() -> bool:
	for _step: int in range(120):
		if not session.environment_save_gate.pending(): break
		if not await _frame(): return false
	if not _check(not session.environment_save_gate.pending(),"prior original background save is complete before isolated fault injection"): return false
	var before: Dictionary = session.store.snapshot()
	var world_id: int = session.world.get_instance_id()
	var actor_id: int = session.players[1].get_instance_id()
	var joint_id: int = session.players[1].cargo_items[Cargo.CARGO].joint.get_instance_id()
	session.store.failure_point = "before_write" # Original Store fault, never a fake operation result.
	var request: Dictionary = _request_save("fault")
	if not _check(request.get("ok",false) and session.environment_save_gate.pending(),"original physical SaveGate is genuinely pending before exit requests",request): return false
	session._ui_action("quit",{})
	session._notification(Node.NOTIFICATION_WM_CLOSE_REQUEST)
	if not _check(session.quit_records.is_empty() and session.environment_save_gate.pending(),"duplicate menu/window exits wait behind the real existing gate"): return false
	for _step: int in range(240):
		if not await _frame(): return false
		if not callbacks.is_empty(): break
	var result: Dictionary = callbacks[0] if not callbacks.is_empty() else {}
	var disk: Dictionary = _read_disk("failed queued exit")
	var preserved: bool = callbacks.size() == 1 and result.get("label") == "fault" and not result.get("result",{}).get("ok",true) and result.get("result",{}).get("completed",false) and session.last_commit_result.get("error") == "SAVE_WRITE_FAILED"
	preserved = preserved and session.quit_records.is_empty() and not session.environment_save_gate.pending() and session.active and session.world.get_instance_id() == world_id and session.players[1].get_instance_id() == actor_id and session.players[1].cargo_items[Cargo.CARGO].joint.get_instance_id() == joint_id and _load_intact() and int(_module()._custody.last_serial) == 2 and session.store.snapshot() == before and disk == before
	if not _check(preserved,"real Store write failure completes unsuccessfully; no quit, no World/Joint/serial loss and no disk publication",{"callback":result,"diagnostics":_diagnostics(),"disk_generation":disk.get("generation")}): return false
	failed_save = {"callback":result,"generation":before.generation,"world_id":world_id,"actor_id":actor_id,"joint_id":joint_id}
	session.store.failure_point = ""
	for _step: int in range(4):
		if not await _frame(): return false
	if not _check(session.quit_records.is_empty() and not session.environment_save_gate.pending() and session.active and _load_intact(),"failed gate clears queued exit: removing write fault alone cannot auto-retry or quit",_diagnostics()): return false
	_phase("I3_real_Store_failure_preserves_world_and_clears_exit_intent")
	return true

func _successful_pending_exit() -> bool:
	var request: Dictionary = _request_save("explicit_retry")
	if not _check(request.get("ok",false) and session.environment_save_gate.pending(),"explicit retry creates a new real pending physical save",request): return false
	session._ui_action("quit",{})
	session._notification(Node.NOTIFICATION_WM_CLOSE_REQUEST)
	session._ui_action("quit",{})
	if not _check(session.quit_records.is_empty(),"three repeated exits are retained until real Store publication"): return false
	for _step: int in range(240):
		if not await _frame(): return false
		if not session.quit_records.is_empty(): break
	if not _check(session.quit_records.size() == 1 and callbacks.size() == 2,"successful queued lifecycle eventually reaches final quit exactly once",_diagnostics()): return false
	exit_record = session.quit_records[0].duplicate(true)
	var retry: Dictionary = callbacks[1]
	var captured: Dictionary = exit_record.cargo_capture
	var published: Dictionary = exit_record.store.world.get("environment",{}).get("I3_thermal_cargo",{})
	var disk: Dictionary = _read_disk("successful queued exit")
	var actual_valid: Dictionary = _module()._validate_progress(published)
	var saved: bool = retry.get("label") == "explicit_retry" and retry.result.get("ok",false) and retry.result.get("completed",false) and int(retry.quit_count) == 0 and int(exit_record.physics_frame) > int(retry.physics_frame) and int(exit_record.store.generation) > int(retry.generation)
	saved = saved and captured.get("ok",false) and published.get("version") == 2 and published.get("role_identity") == session.identities[1] and int(published.get("custody",{}).get("last_serial",-1)) == 2 and actual_valid.get("ok",false) and session.store._tree_valid(captured.state) and session.store.matches_persisted_value(captured.state,published) and disk == exit_record.store and _load_intact()
	if not _check(saved,"first real retry succeeds, then a fresh later native capture/Store generation precedes sole quit; independent reader matches actual one-cargo state",{"retry":retry,"quit_frame":exit_record.physics_frame,"quit_generation":exit_record.store.generation,"native_state_validation":actual_valid,"published":published,"diagnostics":_diagnostics()}): return false
	for _step: int in range(5):
		if not await _frame(): return false
	return _check(session.quit_records.size() == 1 and not session.environment_save_gate.pending() and _load_intact() and int(_module()._custody.last_serial) == 2 and session.story.state.get("completed",[]).is_empty() and session.store.snapshot().personal.discoveries.is_empty(),"consumed duplicate exit intent never fires twice and creates no route/docking/task reward",_diagnostics())

func _request_save(label: String) -> Dictionary:
	return session.request_environment_save(func(result: Dictionary): callbacks.append({"label":label,"result":result.duplicate(true),"physics_frame":Engine.get_physics_frames(),"generation":session.store.snapshot().generation,"quit_count":session.quit_records.size()}))

func _read_disk(label: String) -> Dictionary:
	var reader: RefCounted = Store.new("user://profiles_v3/"+profile)
	var opened: Dictionary = reader.load_profile()
	if not _check(opened.get("ok",false),"independent original Store reader: "+label,opened): return {}
	return reader.snapshot()

func _load_intact() -> bool:
	if not is_instance_valid(session) or not session.players.has(1) or not session.world.objects.has(Cargo.CARGO): return false
	var actor: FlightBodyV2 = session.players[1]
	var item: Dictionary = actor.cargo_items.get(Cargo.CARGO,{})
	var joint: PinJoint3D = item.get("joint") as PinJoint3D
	return actor.cargo_kg == 2.0 and item.get("body") == session.world.objects[Cargo.CARGO] and joint != null and joint.get_rid().is_valid() and joint.get_node_or_null(joint.node_a) == actor and joint.get_node_or_null(joint.node_b) == item.body and _module()._custody._integrity(Cargo.CARGO).is_empty()

func _module():
	return session.thermal_cargo.module

func _frame() -> bool:
	await physics_frame
	await process_frame
	return not finished

func _phase(label: String) -> void:
	var row: Dictionary = {"phase":label,"frame":Engine.get_physics_frames(),"diagnostics":_diagnostics()}
	phases.append(row)
	print("SESSION_EXIT_SAVE_STAGE "+JSON.stringify(row))

func _diagnostics() -> Dictionary:
	if not is_instance_valid(session): return {"session":"not_installed"}
	var result: Dictionary = {"region":session.region_id,"active":session.active,"owns_world":session.owns_world,"generation":session.store.snapshot().generation,"quit_count":session.quit_records.size(),"gate_pending":session.environment_save_gate.pending(),"gate_result":session.environment_save_gate.last_result.duplicate(),"proposal":session.consensus.current_proposal(),"last_commit_result":session.last_commit_result.duplicate(true),"message":session.interface.message.text,"thermal_error":session.thermal_cargo.error,"module":_module().status() if _module() != null else {},"callbacks":callbacks.duplicate(true)}
	if session.players.has(1):
		var actor: FlightBodyV2 = session.players[1]
		result["player"] = {"id":actor.get_instance_id(),"position":Cargo._xyz(actor.global_position),"velocity":Cargo._xyz(actor.linear_velocity),"cargo_kg":actor.cargo_kg}
	return result

func _check(ok: bool,label: String,actual: Variant = null) -> bool:
	checks.append({"passed":ok,"label":label,"actual":actual})
	return ok

func _close_session() -> void:
	if is_instance_valid(driver): driver.owner_session = null; driver.free()
	driver = null
	if is_instance_valid(session):
		session.store.failure_point = ""
		session.environment_save_gate.cancel("qa_exit_save_teardown")
		if session.canal != null: session.canal.clear()
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
	await _close_session()
	var failures: Array = checks.filter(func(row: Dictionary): return not row.passed)
	var report: Dictionary = {"complete":complete,"checks":checks,"failures":failures,"engine_errors":logger.errors,"phases":phases,"callbacks":callbacks,"exit_record":exit_record,"failed_save":failed_save,"diagnostics":diagnostics,"physics_frames":Engine.get_physics_frames()-start_frame,
		"scope":"One unique initially blank original QA Store. A subclass of the single-root production MAIN Session overrides only final _complete_quit to count/read the true durable Store instead of terminating this QA process. All original initialization, Session physics, original SaveGate operations/results and Store writes/readers remain real. I1 original two actual Flight bodies use simulated transport guest delivery to create an unconfirmed original pause proposal; save/menu-exit/window-close must be refused. No Director prefix. After teardown only QA I3 location/availability and one initial full-hull-clear aircraft observation pose are fixtures. Actual 350ms Custody/G/2kg native Joint/short canonical Pilot flight produce the moving state. Original before_write Store failure must preserve World/Joint/serial/disk and clear pending exit intent. Explicit original retry and duplicate exits must publish first gate, then capture/publish a fresh later physical generation before exactly one final quit. No fabricated operation result, manual module advance, cargo pose writes, new docking/route/task credit, actual OS termination, ENet/LAN, full campaign, performance, graphics or human-comfort claim."}
	FileAccess.open(output+"/result.json",FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
	print("SESSION_EXIT_SAVE_RESULT "+JSON.stringify({"complete":complete,"checks":checks.size(),"failures":failures,"engine_errors":logger.errors,"physics_frames":report.physics_frames,"quit_records":0 if exit_record.is_empty() else 1}))
	quit(0 if complete and failures.is_empty() and logger.errors.is_empty() else 1)
