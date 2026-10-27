extends SceneTree
## Actual MAIN I4 route. Only the first clear aircraft pose is a spatial QA
## fixture; all later movement uses the original Pilot/Flight commands.
const MAIN = preload("res://scenes/v3/main.tscn")
const Regions = preload("res://scripts/v3/world/twin_region_catalog.gd")
const Layout = preload("res://scripts/v3/campaign/twin_campaign_layout.gd")
const Pilot = preload("res://scripts/v3/gameplay/canal/canal_transport_physics/transport_pilot.gd")
const Store = preload("res://scripts/v3/core/twin_world_store.gd")
const GOAL := "I4:array_witness:shelter"
const FACT := "I4:storm_route_verified"
const BREAKER := "I4:defence_breaker"
const MASK := 1|2|4|8|32
const START := Vector3(20,12,1.8)
const END := Vector3(14,6.4,-3)

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
		# Ordinary Session owns physics/mechanisms. This node only replaces the
		# QA player's input command AFTER ordinary Session input, at priority 10.
		pilot.tick(delta,true,false)

var logger := ErrorLogger.new()
var session: Node
var driver: FlightCommands
var profile := ""
var output := ""
var finished := false
var complete := false
var checks: Array = []
var phases: Array = []
var trace: Array = []
var callbacks: Array = []
var initial_device_poses: Dictionary = {}
var fixture_receipts := 0
var fixture_completed: Array = []
var start_frame := 0
var route_started_frame := 0
var last_position := Vector3.ZERO
var sampled_frames := 0
var distance_m := 0.0
var maximum_frame_step_m := 0.0
var largest_overlap: Array = []
var initial_collision_count := 0
var initial_damage_taken := 0.0
var final_disk: Dictionary = {}

func _initialize() -> void:
	OS.add_logger(logger)
	_run.call_deferred()

func _run() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--qa-profile="): profile = arg.trim_prefix("--qa-profile=")
		if arg.begins_with("--output="): output = arg.trim_prefix("--output=")
	if not profile.begins_with("qa_i4_storm_route_") or profile != profile.validate_filename() or not output.begins_with("res://artifacts/v3/i4-storm-route-") or ".." in output or DirAccess.dir_exists_absolute(output) or DirAccess.dir_exists_absolute("user://profiles_v3/"+profile):
		quit(2)
		return
	DirAccess.make_dir_recursive_absolute(output)
	start_frame = Engine.get_physics_frames()
	create_timer(25.0).timeout.connect(func():
		if not finished: _check(false,"25 second actual MAIN I4 route bound",_diagnostics()); _finish())
	if not _setup() or not _seed_prefix() or not _initial_observation_pose(): _finish(); return
	session.story.load_world()
	driver = FlightCommands.new()
	driver.process_physics_priority = 10
	driver.owner_session = session
	driver.pilot = Pilot.new()
	root.add_child(driver)
	if not _check(driver.pilot.bind(session.players[1]),"canonical original Pilot binds actual MAIN Flight"): _finish(); return
	var actor: FlightBodyV2 = session.players[1]
	initial_collision_count = actor.collision_count
	initial_damage_taken = actor.damage_taken
	last_position = actor.global_position
	route_started_frame = Engine.get_physics_frames()
	_phase("first_point_QA_observation_only")
	# Pad2 spans z=1..7, y=10.4..11.2. Exit its actual SOUTH edge first;
	# descending straight through the receiver platform/column is forbidden.
	if not await _leg(Vector3(20,12,-.5),1,"outside_actual_Pad2_south_edge",func() -> bool: return session.players[1].global_position.z <= 0.0): _finish(); return
	if not _check(_route_progress() >= 1 and session.campaign.fact(FACT).is_empty(),"real first covered_low point is observed before any lower-route credit",_diagnostics()): _finish(); return
	if not await _leg(Vector3(20,5.6,-.5),2,"below_platform_via_clear_air",func() -> bool: return session.players[1].global_position.y <= 5.85): _finish(); return
	# Stay south of Support2 (x20,z4), then enter the original low waypoint's
	# 2.5m sphere. No body, waypoint, route counter or mechanism field is moved.
	if not await _leg(Vector3(20,5.6,1.8),3,"original_low_waypoint_observed",func() -> bool: return _route_progress() >= 2): _finish(); return
	if not _check(session.campaign.fact(FACT).is_empty() and GOAL not in session.story.state.completed,"actual low point alone cannot substitute for the supported endpoint",_diagnostics()): _finish(); return
	# Closed breaker top is y5.7. END is genuinely clear above that solid face,
	# .7m from it and 1.4m from the original (14,5,-3) endpoint. It is not a pose
	# inside the 1m breaker box, nor an invented empty centre of the platform.
	if not await _leg(END,4,"original_supported_route_fact",func() -> bool: return session.campaign.fact(FACT) == "covered_low"): _finish(); return
	var support: Dictionary = _support_ray()
	var endpoint_distance: float = actor.global_position.distance_to(Vector3(14,5,-3))
	if not _check(support.get("hit",false) and support.get("target_id") == BREAKER and float(support.get("gap_m",99.0)) >= 0.0 and float(support.get("gap_m",99.0)) <= 1.2 and endpoint_distance <= 2.5 and session.campaign.mechanisms._landing_supported(actor.global_position,actor.get_rid()),"actual first-hit breaker top supplies the unchanged original landing ray and endpoint range",{"support":support,"endpoint_distance_m":endpoint_distance,"actual_position":_xyz(actor.global_position)}): _finish(); return
	for _step: int in range(120):
		if GOAL in session.story.state.completed: break
		if not await _frame(): return
	var receipt: Dictionary = _receipt(GOAL)
	var state: Dictionary = session.campaign.mechanisms.persistent_state()
	if not _check(receipt.get("type") == "fact" and receipt.get("target_id") == FACT and receipt.get("option") == "covered_low" and state.facts.get(FACT) == "covered_low" and state.histories.get("I4:route_record",{}).get("option") == "covered_low","ordinary Story commits the observed physical route with its exact original fact option",{"receipt":receipt,"route_record":state.histories.get("I4:route_record",{}),"diagnostics":_diagnostics()}): _finish(); return
	if not _check(sampled_frames >= 60 and distance_m >= 12.0 and maximum_frame_step_m < .5 and largest_overlap.is_empty() and actor.collision_count == initial_collision_count and actor.damage_taken == initial_damage_taken,"continuous actual native flight has no frame jump, hull penetration, collision or damage",{"samples":sampled_frames,"distance_m":distance_m,"maximum_frame_step_m":maximum_frame_step_m,"overlap":largest_overlap,"collision_count":actor.collision_count,"initial_collision_count":initial_collision_count,"damage_taken":actor.damage_taken}): _finish(); return
	if not _check(_devices_unchanged() and not state.facts.has("I4:defence_isolated") and "I4:array_witness:isolate" not in session.story.state.completed and not session.campaign.active() and not session.boss_active,"closed actual devices remain unchanged; route creates no isolation or Boss credit",_diagnostics()): _finish(); return
	if not await _save(): _finish(); return
	complete = _verify_disk(receipt)
	_finish()

func _setup() -> bool:
	Regions._entries = Regions.entries()
	var layout: Dictionary = Layout.definition("I4")
	for entry: Dictionary in Regions._entries:
		if entry.id == "I4":
			entry["playable"] = true # Process-local development availability only.
			entry["spawn"] = layout.spawn.duplicate()
			entry["bounds"] = layout.bounds.duplicate()
	session = MAIN.instantiate()
	root.add_child(session)
	if not _check(session.profile_ready and session.start_flight("solo") and session._load_region("I4") and session.active and session.region_id == "I4" and session.campaign.supported(),"blank unique QA MAIN loads actual authored I4 before the prior rules fixture",_diagnostics()): return false
	session.inputs.test_enabled = true
	session.inputs.test_frame = {"axes":{},"held":["brake"],"edges":[]}
	for id: String in ["I4:witness_receiver","I4:defence_platform",BREAKER,"I4:civilian_feed"]:
		if not _check(session.world.objects.has(id),"actual authored device exists: "+id): return false
		initial_device_poses[id] = session.world.objects[id].global_transform
	return true

func _seed_prefix() -> bool:
	var director: RefCounted = session.story.director
	var state: Dictionary = director.default_state()
	var found := false
	for action: Dictionary in director.definitions().actions:
		for objective: Dictionary in action.objectives:
			if objective.id == GOAL: found = true; break
			var matcher: Dictionary = objective.events[0]
			var applied: Dictionary = director.apply_event(state,{"id":"qa-i4-route-prior-rules:"+str(objective.id),"type":matcher.type,"target_id":matcher.target_id,"option":matcher.options[0]}, {"is_authority":true,"validated":true,"region_id":action.region_id})
			if not applied.get("ok",false) or not applied.get("changed",false): return _check(false,"ordered prior Director rules fixture validates",{"objective":objective.id,"result":applied})
			state = applied.state
			fixture_receipts += 1
		if found: break
	if not _check(found and director.validate_state(state).get("ok",false) and GOAL not in state.completed,"explicit prior rules fixture stops before the one current route objective",{"prior_receipts":fixture_receipts}): return false
	fixture_completed = state.completed.duplicate()
	var stored: Dictionary = session.store.commit({"id":"qa-i4-route-prior-rules-and-already-loaded-region","set":{"world.actions.opening":state,"world.completed_objectives":fixture_completed,"world.region_id":"I4"}})
	if not _check(stored.get("ok",false),"only already-loaded region and prior rules receipts/index are seeded; no route/physics proof",stored): return false
	session.world_cache = session.store.snapshot()
	session.consensus.set_world_revision(int(session.world_cache.world_revision))
	return true

func _initial_observation_pose() -> bool:
	var actor: FlightBodyV2 = session.players[1]
	var hits: Array = _hull_hits(Transform3D(Basis.IDENTITY,START))
	if not _check(hits.is_empty() and Regions.contains("I4",START),"only initial QA observation pose near first waypoint has real full-hull clearance",{"position":_xyz(START),"hits":hits}): return false
	actor.global_transform = Transform3D(Basis.IDENTITY,START)
	actor.force_update_transform()
	PhysicsServer3D.body_set_state(actor.get_rid(),PhysicsServer3D.BODY_STATE_TRANSFORM,actor.global_transform)
	actor.linear_velocity = Vector3.ZERO
	actor.angular_velocity = Vector3.ZERO
	actor.hold_height = START.y
	actor.safe_position = START
	return true

func _leg(point: Vector3,serial: int,label: String,reached: Callable) -> bool:
	if not _check(driver.pilot.go_to(point,serial),"original Pilot receives waypoint: "+label,_xyz(point)): return false
	for _step: int in range(1200):
		if not await _frame(): return false
		if reached.call():
			_phase(label)
			return true
	return _check(false,"actual native leg reaches "+label,_diagnostics())

func _frame() -> bool:
	await physics_frame
	await process_frame
	if finished: return false
	if route_started_frame > 0:
		var actor: FlightBodyV2 = session.players[1]
		var at: Vector3 = actor.global_position
		var step: float = at.distance_to(last_position)
		distance_m += step
		maximum_frame_step_m = maxf(maximum_frame_step_m,step)
		last_position = at
		sampled_frames += 1
		var hits: Array = _hull_hits(actor.global_transform)
		if hits.size() > largest_overlap.size(): largest_overlap = hits
		if sampled_frames % 15 == 0: trace.append({"frame":Engine.get_physics_frames(),"position":_xyz(at),"velocity":_xyz(actor.linear_velocity),"progress":_route_progress(),"fact":session.campaign.fact(FACT)})
	return true

func _hull_hits(pose: Transform3D) -> Array:
	var actor: FlightBodyV2 = session.players[1]
	var shape: CollisionShape3D = actor.get_node("Envelope")
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = shape.shape
	query.transform = pose*shape.transform
	query.collision_mask = MASK
	query.exclude = [actor.get_rid()]
	query.margin = .001
	var hits: Array[Dictionary] = session.world.get_world_3d().direct_space_state.intersect_shape(query,8)
	return hits.map(func(hit: Dictionary): return str(hit.collider.get_path()))

func _support_ray() -> Dictionary:
	var actor: FlightBodyV2 = session.players[1]
	# Same production mask/exclusion/length as Base._ray and _landing_supported.
	var ray := PhysicsRayQueryParameters3D.create(actor.global_position,actor.global_position-Vector3.UP*2.0,1|8,[actor.get_rid()])
	var hit: Dictionary = session.world.get_world_3d().direct_space_state.intersect_ray(ray)
	if hit.is_empty(): return {"hit":false}
	var collider: Node = hit.collider
	return {"hit":true,"target_id":str(collider.get_meta("entity_id","")),"collider":str(collider.get_path()),"position":_xyz(hit.position),"gap_m":actor.global_position.y-float(hit.position.y)}

func _route_progress() -> int:
	return int(session.campaign.mechanisms.persistent_state().get("histories",{}).get("I4:routes",{}).get("1",{}).get("covered_low",0))

func _receipt(objective: String) -> Dictionary:
	for value: Dictionary in session.story.state.get("receipts",{}).values():
		if value.get("objective_id") == objective: return value.duplicate(true)
	return {}

func _devices_unchanged() -> bool:
	for id: String in initial_device_poses:
		if not session.world.objects.has(id) or session.world.objects[id].global_transform != initial_device_poses[id]: return false
	return true

func _save() -> bool:
	var request: Dictionary = session.request_environment_save(func(result: Dictionary): callbacks.append(result.duplicate(true)))
	if not _check(request.get("ok",false) and callbacks.is_empty(),"original asynchronous SaveGate accepts actual completed I4 route",request): return false
	for _step: int in range(120):
		if not await _frame(): return false
		if not callbacks.is_empty(): break
	return _check(callbacks.size() == 1 and callbacks[0].get("ok",false) and callbacks[0].get("completed",false),"original SaveGate publishes actual route through original Store exactly once",{"callbacks":callbacks,"commit":session.last_commit_result})

func _verify_disk(receipt: Dictionary) -> bool:
	var reader: RefCounted = Store.new(session.store.root_path)
	var opened: Dictionary = reader.load_profile()
	final_disk = reader.snapshot()
	var mechanism: Dictionary = final_disk.world.get("environment",{}).get("campaign_I4",{}).get("mechanisms",{})
	var action: Dictionary = final_disk.world.get("actions",{}).get("opening",{})
	var mechanism_valid: Dictionary = session.campaign.mechanisms.validate_state(mechanism)
	var action_valid: Dictionary = session.story.director.validate_state(action)
	var stored_receipt: Dictionary = {}
	for value: Dictionary in action.get("receipts",{}).values():
		if value.get("objective_id") == GOAL: stored_receipt = value
	var additional: Array = action.get("completed",[]).filter(func(id: String): return id not in fixture_completed)
	var discoveries: Array = final_disk.personal.get("discoveries",[])
	return _check(opened.get("ok",false) and mechanism_valid.get("ok",false) and action_valid.get("ok",false) and mechanism.get("facts",{}).get(FACT) == "covered_low" and mechanism.get("histories",{}).get("I4:route_record",{}).get("option") == "covered_low" and session.store.matches_persisted_value(receipt,stored_receipt) and additional == [GOAL] and discoveries.count("I4:storm_service_path") == 1,"independent original Store reader validates physical route, exact Story receipt, sole current completion and one discovery",{"opened":opened,"mechanism_validation":mechanism_valid,"action_validation":action_valid,"stored_receipt":stored_receipt,"additional_completed":additional,"discoveries":discoveries})

func _phase(label: String) -> void:
	var row: Dictionary = {"phase":label,"frame":Engine.get_physics_frames(),"diagnostics":_diagnostics()}
	phases.append(row)
	print("I4_STORM_ROUTE_STAGE "+JSON.stringify(row))

func _diagnostics() -> Dictionary:
	if not is_instance_valid(session): return {"session":"not_installed"}
	var result: Dictionary = {"region":session.region_id,"current_targets":session.story.current_targets(),"last_commit_result":session.last_commit_result,"campaign_error":session.campaign.error,"message":session.interface.message.text,"world_errors":session.world.build_errors if is_instance_valid(session.world) else [],"mechanism":session.campaign.mechanisms.persistent_state() if session.campaign.mechanisms != null else {}}
	if session.players.has(1):
		var actor: FlightBodyV2 = session.players[1]
		var native: Transform3D = PhysicsServer3D.body_get_state(actor.get_rid(),PhysicsServer3D.BODY_STATE_TRANSFORM)
		result["actor"] = {"position":_xyz(actor.global_position),"native_position":_xyz(native.origin),"velocity":_xyz(actor.linear_velocity),"collision_count":actor.collision_count,"damage_taken":actor.damage_taken,"support_ray":_support_ray()}
	if is_instance_valid(driver) and driver.pilot != null: result["pilot"] = driver.pilot.report()
	return result

func _check(ok: bool,label: String,actual: Variant = null) -> bool:
	checks.append({"passed":ok,"label":label,"actual":actual})
	return ok

static func _xyz(value: Vector3) -> Array:
	return [value.x,value.y,value.z]

func _finish() -> void:
	if finished: return
	finished = true
	var diagnostics: Dictionary = _diagnostics()
	if is_instance_valid(driver): driver.owner_session = null; driver.free()
	driver = null
	if is_instance_valid(session):
		session.environment_save_gate.cancel("qa_i4_route_teardown")
		if session.canal != null: session.canal.clear()
		session.thermal_cargo.clear()
		session.network.close()
		session.free()
	session = null
	await process_frame
	await physics_frame
	await process_frame
	var failures: Array = checks.filter(func(row: Dictionary): return not row.passed)
	var report: Dictionary = {"complete":complete,"checks":checks,"failures":failures,"engine_errors":logger.errors,"phases":phases,"trace":trace,"callbacks":callbacks,"diagnostics":diagnostics,"fixture_receipts":fixture_receipts,"fixture_completed":fixture_completed,"physics_frames":Engine.get_physics_frames()-start_frame,"sampled_route_frames":sampled_frames,"distance_m":distance_m,"maximum_frame_step_m":maximum_frame_step_m,"saved_environment":final_disk.get("world",{}).get("environment",{}).get("campaign_I4",{}),
		"scope":"Unique blank original QA MAIN loads actual I4 before an explicitly declared ordered prior-Director rules fixture stopping before I4:array_witness:shelter (prior I4 briefing/archive/witness are fixtures too, not physical completion). One initial full-hull-clear aircraft observation pose near the first waypoint is the only spatial write. Canonical original Pilot commands actual Flight around the receiver platform SOUTH edge, down through clear air and back beneath it south of the real column, then continuously onto the actual closed breaker top's support ray. Ordinary Session ticks alone advance physical route observers/Story. No later aircraft/device/route/velocity writes, manual mechanism advance, relaxed collision masks/thresholds or fabricated event/fact. Original SaveGate/Store and independent reader verify covered_low receipt/discovery. No defence isolation, Boss, played prior campaign, graphics/performance/LAN/human comfort or complete-game claim."}
	FileAccess.open(output+"/result.json",FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
	print("I4_STORM_ROUTE_RESULT "+JSON.stringify({"complete":complete,"checks":checks.size(),"failures":failures,"engine_errors":logger.errors,"physics_frames":report.physics_frames,"distance_m":distance_m}))
	quit(0 if complete and failures.is_empty() and logger.errors.is_empty() else 1)
