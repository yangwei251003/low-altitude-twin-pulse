extends SceneTree
## Actual MAIN objects plus explicitly simulated authenticated lifecycle/action
## delivery. No ENet connection, client prediction or two-machine LAN claim.
const MAIN = preload("res://scenes/v3/main.tscn")
const Regions = preload("res://scripts/v3/world/twin_region_catalog.gd")
const Cargo = preload("res://scripts/v3/gameplay/twin_thermal_cargo_session.gd")
const Pilot = preload("res://scripts/v3/gameplay/canal/canal_transport_physics/transport_pilot.gd")
const Store = preload("res://scripts/v3/core/twin_world_store.gd")
const OLD_PEER := 2
const NEW_PEER := 19

class ErrorLogger extends Logger:
	var guard := Mutex.new()
	var errors: Array = []
	func _log_error(function: String,file: String,line: int,code: String,rationale: String,_notify: bool,kind: int,_trace: Array[ScriptBacktrace]) -> void:
		if kind == Logger.ERROR_TYPE_WARNING: return
		guard.lock()
		errors.append({"function":function,"file":file,"line":line,"code":code,"rationale":rationale})
		guard.unlock()

class GuestCommands extends Node:
	var owner_session: Node
	var peer := OLD_PEER
	var pilot: RefCounted
	func _physics_process(delta: float) -> void:
		if not is_instance_valid(owner_session) or not owner_session.active or owner_session.simulation_paused or not owner_session.players.has(peer): return
		if not owner_session.thermal_cargo.supported() or not owner_session.thermal_cargo.module.status().assist.is_empty(): return
		if pilot != null: pilot.tick(delta,true,false)
		else: owner_session.players[peer].command = {"active":true,"mode":"assisted","body_relative":false,"planar":Vector3.ZERO,"vertical":0.0,"yaw":0.0,"brake":true,"fire":false}

var logger := ErrorLogger.new()
var session: Node
var driver: GuestCommands
var profile := ""
var output := ""
var identity := ""
var finished := false
var checks: Array = []
var phases: Dictionary = {}
var callbacks: Array = []
var saved: Dictionary = {}
var rejoined: Dictionary = {}
var start_frame := 0

func _initialize() -> void:
	OS.add_logger(logger)
	_run.call_deferred()

func _run() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--qa-profile="): profile = arg.trim_prefix("--qa-profile=")
		if arg.begins_with("--output="): output = arg.trim_prefix("--output=")
	if not profile.begins_with("qa_thermal_cargo_roster_") or profile != profile.validate_filename() or not output.begins_with("res://artifacts/v3/thermal-cargo-roster-") or ".." in output or DirAccess.dir_exists_absolute(output) or DirAccess.dir_exists_absolute("user://profiles_v3/"+profile):
		quit(2)
		return
	DirAccess.make_dir_recursive_absolute(output)
	start_frame = Engine.get_physics_frames()
	create_timer(30.0).timeout.connect(func():
		if not finished: _check(false,"30 second actual MAIN roster bound",_diagnostics()); _finish())
	Regions._entries = Regions.entries()
	for item: Dictionary in Regions._entries:
		if item.id == "I3": item["playable"] = true
	if not _setup(): _finish(); return
	var low_ready := false
	for _step in range(240):
		if not await _frame(): return
		if _module().ready and _module()._row().phase == "docked": low_ready = true; break
	if not _check(low_ready,"ordinary MAIN observes real low-berth support with two actual players",_diagnostics()): _finish(); return
	# This is the exact host action produced by the ordinary remote Story G.
	# Delivery/authentication is simulated; host range/LOS/Custody remain real.
	session._action_received(OLD_PEER,"lock",{"target_id":Cargo.CARGO})
	session._action_received(OLD_PEER,"thermal_cargo_operate",{"target_id":Cargo.CARGO})
	var picked := false
	for _step in range(900):
		if not await _frame(): return
		if session.players[OLD_PEER].cargo_items.has(Cargo.CARGO) and _module().status().assist.is_empty(): picked = true; break
	if not _check(picked and session.players[OLD_PEER].cargo_kg == 2.0 and session.players[1].cargo_kg == 0.0,"original remote-G intent attaches the unique actual 2kg load to guest only",_diagnostics()): _finish(); return
	var guest: FlightBodyV2 = session.players[OLD_PEER]
	var old_body: WeakRef = weakref(guest)
	var old_joint: WeakRef = weakref(guest.cargo_items[Cargo.CARGO].joint)
	var cargo_identity: int = session.world.objects[Cargo.CARGO].get_instance_id()
	driver.pilot = Pilot.new()
	if not _check(driver.pilot.bind(guest) and driver.pilot.go_to(Vector3(-8.2,5.2,18),1),"canonical original Pilot commands actual guest short loaded flight"): _finish(); return
	var origin: Vector3 = guest.global_position
	var moved := false
	for _step in range(600):
		if not await _frame(): return
		if guest.global_position.distance_to(origin) >= .8 and guest.linear_velocity.length() >= .35: moved = true; break
	if not _check(moved,"guest and original Joint physically fly at least .8m before pause",_diagnostics()): _finish(); return
	session.store.failure_point = "before_write" # Original isolated Store injection.
	if not _joint_pause(): _finish(); return
	for _step in range(240):
		if not await _frame(): return
		if session.simulation_paused: break
	var captured: Dictionary = _module().paused_saved_state()
	if not _check(captured.get("ok",false) and session.simulation_paused and session.players[1].freeze and guest.freeze and session.world.objects[Cargo.CARGO].freeze and session.consensus.current_proposal().is_empty(),"two-participant original Consensus freezes actual host/guest/load at native boundary",_diagnostics()): _finish(); return
	saved = captured.state.duplicate(true)
	if not _check(saved.role_identity == identity and saved.version == 2 and int(saved.custody.last_serial) == 2 and Cargo._vector(saved.carrier.native_velocity).length() >= .3 and session.store._tree_valid(saved),"real pause candidate contains guest identity, original serial2, actual moving native momentum and original Store-safe tree",saved): _finish(); return
	var before: Dictionary = session.store.snapshot()
	var published_before: Dictionary = before.world.get("environment",{}).get("I3_thermal_cargo",{})
	if not _check(not session.store.matches_persisted_value(saved,published_before),"disconnect failure fixture has not already published this exact native boundary"): _finish(); return
	var candidate_text: String = JSON.stringify(saved,"",true,true)
	var old_cargo_pose: Transform3D = session.world.objects[Cargo.CARGO].global_transform
	var old_guest_pose: Transform3D = guest.global_transform
	# Mirror original Network._peer_left table removal before Session callback.
	for table in [session.network.guests,session.network.last_input,session.network.last_action,session.network.received_at]: table.erase(OLD_PEER)
	session._guest_left(OLD_PEER)
	if not await _frame(): return
	var suspended: Dictionary = _module().disconnect_state()
	var retained: bool = suspended.get("ok",false) and session.players.has(OLD_PEER) and session.players[OLD_PEER] == old_body.get_ref() and session.identities.get(OLD_PEER) == identity and guest.freeze and guest.cargo_items.has(Cargo.CARGO) and old_joint.get_ref() != null and session.world.objects[Cargo.CARGO].freeze
	retained = retained and session.store.snapshot() == before and not session.last_commit_result.get("ok",true) and session.last_commit_result.get("receipt") == "thermal-cargo-disconnect" and JSON.stringify(suspended.get("state",{}),"",true,true) == candidate_text
	if not _check(retained,"actual original Store failure preserves old real body, players, Joint, candidate and generation",{"suspended":suspended,"commit":session.last_commit_result,"diagnostics":_diagnostics()}): _finish(); return
	phases["failed_disconnect"] = {"commit":session.last_commit_result.duplicate(true),"candidate":saved,"generation":before.generation}
	print("THERMAL_ROSTER_STAGE failed_Store_retains_old_body frame="+str(Engine.get_physics_frames()))
	# One currently connected transport guest, still no third actual Flight.
	session.network.guests[NEW_PEER] = identity
	session._guest_joined(NEW_PEER,identity,"tr01")
	_check(session.players.size() == 2 and session.players.has(1) and session.players.has(OLD_PEER) and not session.players.has(NEW_PEER) and session.thermal_cargo._queued_join.get("peer_id") == NEW_PEER,"same-identity rejoin is deferred during failed save, never creates a third Flight",_diagnostics())
	for _step in range(3):
		if not await _frame(): return
	_check(session.players.has(OLD_PEER) and session.store.snapshot() == before and guest.global_transform == old_guest_pose and session.world.objects[Cargo.CARGO].global_transform == old_cargo_pose and session.simulation_paused,"failed-save wait keeps original paused poses/generation/players intact")
	session.store.failure_point = ""
	var request: Dictionary = session.request_environment_save(func(result: Dictionary): callbacks.append(result.duplicate(true)))
	if not _check(request.get("ok",false) and callbacks.is_empty(),"explicit original SaveGate retry accepts retained native candidate",request): _finish(); return
	var joined := false
	for _step in range(240):
		if not await _frame(): return
		if not callbacks.is_empty() and session.players.has(NEW_PEER) and not session.players.has(OLD_PEER): joined = true; break
	if not _check(joined and callbacks.size() == 1 and callbacks[0].get("ok",false) and callbacks[0].get("completed",false),"only successful original Store retry removes old peer and activates queued original guest join",{"callbacks":callbacks,"diagnostics":_diagnostics()}): _finish(); return
	guest = session.players[NEW_PEER]
	driver.peer = NEW_PEER
	driver.pilot = null
	var body: RigidBody3D = session.world.objects[Cargo.CARGO]
	var item: Dictionary = guest.cargo_items.get(Cargo.CARGO,{})
	var new_pause: Dictionary = _module().paused_saved_state()
	var joint: PinJoint3D = item.get("joint") as PinJoint3D
	var cached: Dictionary = new_pause.get("state",{})
	var criteria: Dictionary = {
		"item_body_is_original":item.get("body") == body,
		"joint_is_pin":joint != null,
		"joint_native_rid_valid":joint != null and joint.get_rid().is_valid(),
		"joint_endpoint_a_is_new_guest":joint != null and joint.get_node_or_null(joint.node_a) == guest,
		"joint_endpoint_b_is_original_cargo":joint != null and joint.get_node_or_null(joint.node_b) == body,
		"old_body_removed":old_body.get_ref() == null,
		"old_joint_removed":old_joint.get_ref() == null,
		"exactly_two_players":session.players.size() == 2,
		"same_role_identity":session.identities.get(NEW_PEER) == identity,
		"same_cargo_instance":body.get_instance_id() == cargo_identity,
		"actual_guest_load_2kg":guest.cargo_kg == 2.0,
		"session_active":session.active,
		"participant_healthy":session.thermal_cargo.error.is_empty(),
		"common_pause":session.simulation_paused,
		"new_guest_frozen":guest.freeze,
		"original_cargo_frozen":body.freeze,
		"host_frozen":session.players[1].freeze,
		"pause_cache_available":bool(new_pause.get("ok",false)),
		"native_candidate_bytes_exact":var_to_bytes(cached) == var_to_bytes(saved),
		"same_original_serial2":int(_module()._custody.last_serial) == 2}
	var intact: bool = true
	for key: String in ["item_body_is_original","joint_is_pin","joint_native_rid_valid","joint_endpoint_a_is_new_guest","joint_endpoint_b_is_original_cargo","old_body_removed","old_joint_removed","exactly_two_players","same_role_identity","same_cargo_instance","actual_guest_load_2kg","session_active","participant_healthy"]:
		intact = intact and bool(criteria[key])
	var still_paused: bool = true
	for key: String in ["common_pause","new_guest_frozen","original_cargo_frozen","host_frozen","pause_cache_available","native_candidate_bytes_exact","same_original_serial2"]:
		still_paused = still_paused and bool(criteria[key])
	# Both values are original native candidates, so compare exact Variant bytes.
	# Store's one-sided JSON comparator requires an actual persisted RHS and is
	# recorded only to diagnose the original fixture's incorrect API use.
	var parsed_cache: Variant = JSON.parse_string(JSON.stringify(cached,"",true,true))
	var parsed_saved: Variant = JSON.parse_string(JSON.stringify(saved,"",true,true))
	var rejoin_diagnostic: Dictionary = {"criteria":criteria,"failed_criteria":criteria.keys().filter(func(key: String): return not criteria[key]),
		"native_cache_exact":cached == saved,"both_json_readbacks_exact":parsed_cache == parsed_saved,
		"native_cache_full_precision_json_exact":JSON.stringify(cached,"",true,true) == candidate_text,
		"single_sided_persistence_comparator_diagnostic_only":session.store.matches_persisted_value(cached,saved),
		"native_cache_differences":_value_differences(cached,saved),"single_sided_comparator_differences":_value_differences(parsed_cache,saved),
		"old_body":_weak_node_diagnostic(old_body),"old_joint":_weak_node_diagnostic(old_joint),
		"new_joint":_weak_node_diagnostic(weakref(joint)) if joint != null else {},"pause_cache":new_pause,"diagnostics":_diagnostics()}
	if not _check(intact and still_paused,"same identity/new peer restores real Joint in common pause; old real collision/Joint removed before query, original cargo/cache/serial retained",rejoin_diagnostic): _finish(); return
	_check(Cargo._f32_equal(Cargo._xyz(PhysicsServer3D.pin_joint_get_local_a(item.joint.get_rid())),saved.joint.local_a) and Cargo._f32_equal(Cargo._xyz(PhysicsServer3D.pin_joint_get_local_b(item.joint.get_rid())),saved.joint.local_b),"new actual Joint preserves original native local anchors")
	var reader = Store.new(session.store.root_path)
	var opened: Dictionary = reader.load_profile()
	var disk: Dictionary = reader.snapshot().world.get("environment",{}).get("I3_thermal_cargo",{})
	_check(opened.get("ok",false) and session.store.matches_persisted_value(saved,disk) and int(reader.snapshot().generation) > int(before.generation),"independent original Store reader verifies retained candidate was durably published before old body removal",opened)
	rejoined = {"identity":identity,"peer":NEW_PEER,"actual_joint":intact,"still_common_paused":still_paused,"serial":_module()._custody.last_serial,"old_body_removed":old_body.get_ref() == null}
	print("THERMAL_ROSTER_STAGE same_identity_rejoined_paused frame="+str(Engine.get_physics_frames()))
	var count: int = int(_module().pause_request_status().resume_count)
	if not _joint_pause(): _finish(); return # Same original Consensus now resumes.
	var resumed: bool = not session.simulation_paused and session.consensus.current_proposal().is_empty() and int(_module().pause_request_status().resume_count) == count+1 and not guest.freeze and not body.freeze
	resumed = resumed and Cargo._native_readback(guest,saved.carrier) and Cargo._native_readback(body,saved.cargo) and int(_module()._custody.last_serial) == 2
	if not _check(resumed,"both current participants resume original real native momentum exactly once without new pickup/docking serial",_diagnostics()): _finish(); return
	var actual: Dictionary = Cargo._body_snapshot(guest)
	session._apply_pause_state()
	_check(Cargo._body_snapshot(guest) == actual and int(_module().pause_request_status().resume_count) == count+1,"repeated ordinary global unpause cannot inject retained momentum again")
	driver.pilot = Pilot.new()
	_check(driver.pilot.bind(guest) and driver.pilot.go_to(Vector3(-8.2,5.2,18),2),"new actual guest body receives original Pilot commands after resume")
	var resumed_at: Vector3 = guest.global_position
	for _step in range(18):
		if not await _frame(): return
	_check(guest.global_position.distance_to(resumed_at) > .05 and _module()._custody._integrity(Cargo.CARGO).is_empty() and guest.cargo_items.has(Cargo.CARGO) and _module().fact(Cargo.FACT).is_empty(),"rejoined original guest/Joint really continue loaded flight without invented delivery fact",_diagnostics())
	_check(session.story.state.get("completed",[]).is_empty() and session.store.snapshot().personal.discoveries.is_empty(),"roster QA creates no prior Director prefix, task completion or reward")
	_finish()

func _setup() -> bool:
	session = MAIN.instantiate()
	session.thermal_cargo.enabled = true
	root.add_child(session)
	if not _check(session.profile_ready,"ordinary MAIN opens unique original QA profile"): return false
	var located: Dictionary = session.store.commit({"id":"qa-thermal-roster-location","set":{"world.region_id":"I3"}})
	if not _check(located.get("ok",false),"only QA initial location set to I3"): return false
	session.world_cache = session.store.snapshot()
	if not _check(session.start_flight("solo") and session.active and session.region_id == "I3" and session.thermal_cargo.supported(),"actual original MAIN binds I3 after host exists",_diagnostics()): return false
	session.inputs.test_enabled = true
	session.inputs.test_frame = {"axes":{},"held":["brake"],"edges":[]}
	identity = Crypto.new().generate_random_bytes(16).hex_encode()
	session.network.guests[OLD_PEER] = identity
	session._guest_joined(OLD_PEER,identity,"tr01")
	if not _check(session.players.size() == 2 and session.players.has(OLD_PEER) and session.identities.get(OLD_PEER) == identity,"simulated transport roster drives original guest_joined and a second actual Flight"): return false
	var actor: FlightBodyV2 = session.players[OLD_PEER]
	var at := Vector3(-10,4.1,18)
	var envelope: CollisionShape3D = actor.get_node("Envelope")
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = envelope.shape
	query.transform = Transform3D(Basis.IDENTITY,at)*envelope.transform
	query.collision_mask = Cargo.MASK
	query.exclude = [actor.get_rid()]
	query.margin = .001
	var hits: Array[Dictionary] = session.world.get_world_3d().direct_space_state.intersect_shape(query,8)
	if not _check(hits.is_empty(),"only initial guest observation pose above actual LOW is full-envelope clear",hits.map(func(hit: Dictionary): return str(hit.collider.get_path()))): return false
	actor.global_transform = Transform3D(Basis.IDENTITY,at)
	actor.force_update_transform()
	PhysicsServer3D.body_set_state(actor.get_rid(),PhysicsServer3D.BODY_STATE_TRANSFORM,actor.global_transform)
	actor.linear_velocity = Vector3.ZERO
	actor.angular_velocity = Vector3.ZERO
	actor.hold_height = at.y
	actor.safe_position = at
	driver = GuestCommands.new()
	driver.process_physics_priority = 10
	driver.owner_session = session
	root.add_child(driver)
	return true

func _joint_pause() -> bool:
	var guest_peer: int = OLD_PEER if session.players.has(OLD_PEER) else NEW_PEER
	session._request_pause()
	var proposal: Dictionary = session.consensus.current_proposal()
	if not _check(proposal.get("kind") == "pause" and proposal.get("state") == "pending" and proposal.get("participants",[]).size() == 2 and proposal.get("confirmed",[]).size() == 1,"original two-participant pause proposal awaits actual current guest",proposal): return false
	session._action_received(guest_peer,"confirm",{"proposal_id":proposal.proposal_id,"world_revision":int(session.world_cache.world_revision)})
	return true

func _module():
	return session.thermal_cargo.module

func _frame() -> bool:
	await physics_frame
	await process_frame
	return not finished

func _diagnostics() -> Dictionary:
	if not is_instance_valid(session): return {"session":"not_installed"}
	var roster: Dictionary = {}
	for peer in session.players:
		var body: FlightBodyV2 = session.players[peer]
		roster[str(peer)] = {"identity":session.identities.get(peer,""),"id":body.get_instance_id(),"frozen":body.freeze,"cargo_kg":body.cargo_kg,"pose":Cargo._pose(body.global_transform),"native_velocity":Cargo._xyz(PhysicsServer3D.body_get_state(body.get_rid(),PhysicsServer3D.BODY_STATE_LINEAR_VELOCITY))}
	return {"active":session.active,"paused":session.simulation_paused,"players":roster,"transport_guests":session.network.guests.duplicate(),"proposal":session.consensus.current_proposal(),"message":session.interface.message.text,"commit":session.last_commit_result,"generation":session.store.snapshot().generation,
		"participant_error":session.thermal_cargo.error,"queued_join":session.thermal_cargo._queued_join.duplicate(),"disconnect_peer":session.thermal_cargo._disconnect_peer,"module":_module().status() if _module() != null else {}}

func _weak_node_diagnostic(reference: WeakRef) -> Dictionary:
	var value: Variant = reference.get_ref()
	if not is_instance_valid(value): return {"alive":false}
	return {"alive":true,"instance_id":value.get_instance_id(),"class":value.get_class(),"path":str(value.get_path()) if value is Node and value.is_inside_tree() else "outside_tree"}

func _value_differences(left: Variant,right: Variant) -> Array:
	var rows: Array = []
	_append_value_differences(left,right,"state",rows)
	return rows

func _append_value_differences(left: Variant,right: Variant,path: String,rows: Array) -> void:
	if rows.size() >= 24: return
	if left is Dictionary and right is Dictionary:
		for key: Variant in left:
			if not right.has(key): rows.append({"path":path+"."+str(key),"reason":"right_missing"})
			else: _append_value_differences(left[key],right[key],path+"."+str(key),rows)
			if rows.size() >= 24: break
		for key: Variant in right:
			if not left.has(key) and rows.size() < 24: rows.append({"path":path+"."+str(key),"reason":"left_missing"})
	elif left is Array and right is Array:
		if left.size() != right.size(): rows.append({"path":path,"reason":"array_size","left":left.size(),"right":right.size()})
		for index: int in range(mini(left.size(),right.size())):
			_append_value_differences(left[index],right[index],path+"["+str(index)+"]",rows)
			if rows.size() >= 24: break
	elif var_to_bytes(left) != var_to_bytes(right):
		rows.append({"path":path,"left":left,"right":right,"left_type":type_string(typeof(left)),"right_type":type_string(typeof(right)),"left_variant_bytes":var_to_bytes(left).hex_encode(),"right_variant_bytes":var_to_bytes(right).hex_encode()})

func _check(ok: bool,label: String,actual: Variant = null) -> bool:
	checks.append({"passed":ok,"label":label,"actual":actual})
	return ok

func _finish() -> void:
	if finished: return
	finished = true
	var diagnostics: Dictionary = _diagnostics()
	if is_instance_valid(driver): driver.owner_session = null; driver.free()
	driver = null
	if is_instance_valid(session):
		session.store.failure_point = ""
		session.environment_save_gate.cancel("qa_roster_teardown")
		session.thermal_cargo.clear()
		session.network.close()
		session.free()
	session = null
	await process_frame
	await physics_frame
	await process_frame
	var failures: Array = checks.filter(func(row: Dictionary): return not row.passed)
	var report := {"checks":checks,"failures":failures,"engine_errors":logger.errors,"phases":phases,"callbacks":callbacks,"saved_candidate":saved,"rejoined":rejoined,"diagnostics":diagnostics,"actual_physics_frames":Engine.get_physics_frames()-start_frame,
		"scope":"Actual original MAIN, unique empty QA/I3 profile, host plus one real guest Flight. Transport roster and authenticated guest action/join/leave delivery are explicitly simulated through original Session APIs, no ENet connection. One initial full-envelope-clear guest observation pose; all carried movement uses original Flight/Pilot/Joint and ordinary Session ticks. Original remote G attaches 2kg; two actual participants jointly pause through original Consensus; original Store before_write failure preserves old body/Joint/candidate/players; same-identity new peer queues without third Flight; explicit original SaveGate retry publishes candidate before old-body removal; original same-identity rejoin rebuilds one actual Joint in the retained common pause; both participants resume native momentum once and actual loaded flight continues. No module/solver manual advance, transit pose writes, field claims, prior Director fixture, route completion, reward, real RPC authentication/transport, two-machine LAN, performance or full-campaign acceptance."}
	FileAccess.open(output+"/result.json",FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
	print("THERMAL_CARGO_ROSTER_RESULT "+JSON.stringify({"checks":checks.size(),"failures":failures,"engine_errors":logger.errors,"rejoined":rejoined,"physics_frames":report.actual_physics_frames}))
	quit(0 if failures.is_empty() and logger.errors.is_empty() and not rejoined.is_empty() else 1)
