extends SceneTree
## F3 mechanism/Story/native-Ecology bridge only. No Boss encounter is seeded.
const MAIN = preload("res://scenes/v3/main.tscn")
const Regions = preload("res://scripts/v3/world/twin_region_catalog.gd")
const Layout = preload("res://scripts/v3/campaign/twin_campaign_layout.gd")
const Store = preload("res://scripts/v3/core/twin_world_store.gd")
const PREFIX_STOP := "F3:separate_network:sample"
const ISOLATE := "F3:separate_network:isolate"
const FEED := "F3:separate_network:feed"
const ACTOR := "F3:nutrient_01"
const PROOF := "F3:nutrient_route_proof"
class ErrorLogger extends Logger:
	var guard := Mutex.new()
	var errors: Array = []
	func _log_error(function: String,file: String,line: int,code: String,rationale: String,_notify: bool,kind: int,_trace: Array[ScriptBacktrace]) -> void:
		if kind==Logger.ERROR_TYPE_WARNING: return
		guard.lock()
		errors.append({"function":function,"file":file,"line":line,"code":code,"rationale":rationale})
		guard.unlock()
var logger := ErrorLogger.new()
var session: Node
var profile := ""
var output := ""
var region := "F3"
var finished := false
var checks: Array = []
var phases: Array = []
var source_batches: Array = []
var fixture_receipts := 0
var native_proof: Dictionary = {}

func _initialize() -> void:
	OS.add_logger(logger)
	_run.call_deferred()

func _run() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--qa-profile="): profile = arg.trim_prefix("--qa-profile=")
		if arg.begins_with("--output="): output = arg.trim_prefix("--output=")
		if arg.begins_with("--region="): region = arg.trim_prefix("--region=")
	if region!="F3" or not profile.begins_with("qa_campaign_late_main_") or profile!=profile.validate_filename() or not output.begins_with("res://artifacts/v3/campaign-late-main-") or ".." in output or DirAccess.dir_exists_absolute(output) or DirAccess.dir_exists_absolute("user://profiles_v3/"+profile):
		quit(2)
		return
	DirAccess.make_dir_recursive_absolute(output)
	create_timer(38).timeout.connect(func():
		if not finished:
			_check(false,"F3 bounded 38-second mechanism slice",_diagnostics())
			_finish())
	Regions._entries = Regions.entries()
	var layout: Dictionary = Layout.definition(region)
	for entry: Dictionary in Regions._entries:
		if entry.id==region:
			entry.playable = true
			entry.spawn = layout.spawn.duplicate()
			entry.bounds = layout.bounds.duplicate()
	session = MAIN.instantiate()
	root.add_child(session)
	if not _check(session.profile_ready and session.start_flight("solo") and session._load_region(region) and session.region_id==region and session.campaign.supported(),"actual empty QA MAIN loads F3 before any prior-rule fixture",_diagnostics()):
		_finish()
		return
	session.inputs.test_enabled = true
	session.inputs.test_frame = {"axes":{},"held":["brake"],"edges":[]}
	if not _seed_prefix():
		_finish()
		return
	session.story.load_world()
	_phase("actual_F3_loaded_prior_rules_only")
	if not await _read_marker("F3:root_sample",PREFIX_STOP) or not await _read_marker("npc:lingyin","F3:separate_network:listen"):
		_finish()
		return
	_phase("actual_original_sample_and_NPC_G_receipts")
	if not await _ability("F3:nutrient_bridge","light","on"):
		_finish()
		return
	for unused in 3:
		if not await _ability("F3:nutrient_bridge","growth",""):
			_finish()
			return
	for unused in 20:
		await _frame()
		if finished: return
		if session.campaign.mechanisms.verified_nutrient_route()=="grown_path": break
	var growth: Dictionary = _growth_diagnostics()
	if not _check(session.entities["F3:nutrient_bridge"].growth==1.0 and session.campaign.mechanisms.verified_nutrient_route()=="grown_path","three original growth intents create the full actual collision bridge and supported route",growth):
		_finish()
		return
	_phase("actual_growth_collision_supported")
	if not await _operate("F3:signal_hold") or not await _ability("F3:signal_hold","echo","") or not await _operate("F3:signal_breaker"):
		_finish()
		return
	if not await _wait_goal(ISOLATE,120):
		_finish()
		return
	var mechanism_state: Dictionary = session.campaign.mechanisms.persistent_state()
	var isolation_receipt: Dictionary = _receipt(ISOLATE)
	if not _check(isolation_receipt.get("option")=="echo_hold" and mechanism_state.histories.get("F3:signal_record",{}).get("method")=="echo_hold" and bool(session.world_cache.world.flags.get("F3:signal_isolated",false)),"original echo/G/bridge evidence commits the signal fact, Story receipt and NPC supply flag",{"receipt":isolation_receipt,"mechanism":mechanism_state,"diagnostics":_diagnostics()}):
		_finish()
		return
	_phase("signal_echo_fact_and_supply_committed")
	# Explicitly authorized native-source acceleration: only the ORIGINAL
	# LivingWorld.advance API advances its existing route simulation. Each call
	# completes one source second, then ordinary MAIN consumes its sealed event
	# batch. No event, actor job, context, nutrition, proof or fact is supplied.
	var pickup_seen := false
	var arrival_seen := false
	for unused in 50:
		var before: Dictionary = session.ecology.simulation.snapshot()
		var delta: float = 1.0-float(before.pending_usec)/1000000.0
		session.ecology.advance(delta)
		var after: Dictionary = session.ecology.simulation.snapshot()
		var actor: Dictionary = after.actors[ACTOR]
		pickup_seen = pickup_seen or (bool(actor.cargo) and int(actor.job_index)==1 and int(actor.steps_completed)>=1)
		var arrived: bool = int(actor.cycles)>int(before.actors[ACTOR].cycles) and actor.phase=="waiting" and actor.reason=="job_completed" and actor.node=="service" and not actor.cargo
		arrival_seen = arrival_seen or arrived
		source_batches.append({"delta_via_original_LivingWorld_advance":delta,"before_tick":before.tick,"after_tick":after.tick,"event_serial":after.event_serial,"actor":actor.duplicate(true),"sealed_last_event_serial":session.ecology.last_event_serial,"arrival_this_batch":arrived})
		await _frame() # Original Session's Ecology→Campaign→Story pipeline consumes.
		if finished: return
		native_proof = session.campaign.mechanisms.persistent_state().histories.get(PROOF,{}).duplicate(true)
		if not native_proof.is_empty(): break
		if arrived:
			_check(false,"native Ecology arrival must publish through the original Campaign proof transaction",{"source_batch":source_batches.back(),"diagnostics":_diagnostics()})
			_finish()
			return
	if not _check(pickup_seen and arrival_seen and not native_proof.is_empty() and native_proof.get("route")=="grown_path" and native_proof.get("event",{}).get("actor_id")==ACTOR and native_proof.get("event",{}).get("kind")=="transport_arrival","original named carrier truly picks up then delivers; original sealed native event yields the stored route proof",{"proof":native_proof,"batches":source_batches,"diagnostics":_diagnostics()}):
		_finish()
		return
	if not await _wait_goal(FEED,120):
		_finish()
		return
	_phase("native_arrival_proof_and_actual_feed_Story_committed")
	var reader = Store.new(session.store.root_path)
	var opened: Dictionary = reader.load_profile()
	var disk: Dictionary = reader.snapshot()
	var saved: Dictionary = disk.world.get("environment",{}).get("campaign_F3",{}).get("mechanisms",{})
	var proof: Dictionary = saved.get("histories",{}).get(PROOF,{})
	var state_ok: Dictionary = session.campaign.mechanisms.validate_state(saved)
	var action_ok: Dictionary = session.story.director.validate_state(disk.world.get("actions",{}).get("opening",{}))
	_check(opened.get("ok",false) and state_ok.get("ok",false) and action_ok.get("ok",false) and session.store.matches_persisted_value(native_proof,proof) and disk.world.actions.opening.completed.has(FEED) and disk.personal.discoveries.count("F3:living_isolation")==1,"new original Store reader verifies native proof, actual Story completion and exactly one F3 discovery",{"opened":opened,"mechanism_validation":state_ok,"Story_validation":action_ok,"saved_proof":proof})
	_check(not session.campaign.active() and not session.boss_active,"mechanism slice never starts or fabricates a Boss encounter")
	_finish()

func _seed_prefix() -> bool:
	var director = session.story.director
	var state: Dictionary = director.default_state()
	var found := false
	for action: Dictionary in director.definitions().actions:
		for objective: Dictionary in action.objectives:
			if objective.id==PREFIX_STOP:
				found = true
				break
			var matcher: Dictionary = objective.events[0]
			var applied: Dictionary = director.apply_event(state,{"id":"qa-late-prefix:"+str(objective.id),"type":matcher.type,"target_id":matcher.target_id,"option":matcher.options[0]},
				{"is_authority":true,"validated":true,"region_id":action.region_id})
			if not applied.get("ok",false) or not applied.get("changed",false): return _check(false,"ordered prior Director rules fixture validates",{"objective":objective.id,"result":applied.get("code")})
			state = applied.state
			fixture_receipts += 1
		if found: break
	if not _check(found and director.validate_state(state).ok and PREFIX_STOP not in state.completed,"prior Director rules fixture stops before every current F3 objective",{"prior_receipts":fixture_receipts}): return false
	var stored: Dictionary = session.store.commit({"id":"qa-late-F3-prefix-and-current-region-fixture","set":{"world.actions.opening":state,"world.region_id":"F3"}})
	if not _check(stored.get("ok",false),"already-loaded QA F3 records only the legal prior-rule prefix and matching current-region location",stored): return false
	session.world_cache = session.store.snapshot()
	session.consensus.set_world_revision(int(session.world_cache.world_revision))
	return true

func _read_marker(id: String,objective: String) -> bool:
	var marker: Dictionary = session.story.markers[id]
	var point: Vector3 = session.story._point(marker)
	if not await _place(point+Vector3.UP*1.4,"actual G reading "+id): return false
	var actor: FlightBodyV2 = session.players[1]
	if not _check(actor.global_position.distance_to(point)<=float(marker.radius) and session._line_clear(actor.global_position,point,actor.get_rid(),id),"actual manual source is near and visible: "+id): return false
	_press_g()
	if not await _wait_goal(objective,60): return false
	var receipt: Dictionary = _receipt(objective)
	return _check(receipt.get("target_id")==id and receipt.get("type") in ["inspect","talk"],"original G creates the actual named source receipt: "+id,receipt)

func _operate(id: String) -> bool:
	if not await _near(id): return false
	var body: PhysicsBody3D = session.world.objects[id]
	var old: Transform3D = body.global_transform
	var expected: Transform3D = old
	if id=="F3:signal_hold": expected.basis = Basis(Vector3.UP,PI*.5)
	else: expected.origin = Vector3(12,7,9)
	var generation: int = session.store.snapshot().generation
	session._action_received(1,"lock",{"target_id":id})
	_press_g()
	await _frame()
	if finished: return false
	var physical: Transform3D = PhysicsServer3D.body_get_state(body.get_rid(),PhysicsServer3D.BODY_STATE_TRANSFORM)
	return _check(body.global_position.distance_to(expected.origin)<.002 and body.global_basis.is_equal_approx(expected.basis) and physical.origin.distance_to(expected.origin)<.002 and physical.basis.is_equal_approx(expected.basis) and int(session.store.snapshot().generation)>generation and session.campaign.last_operation_blockers.is_empty(),"original G completes actual hold/breaker travel and Store commit: "+id,{"expected":expected,"actual":body.global_transform,"physics":physical,"diagnostics":_diagnostics()})

func _ability(id: String,ability: String,mode: String) -> bool:
	if not await _near(id): return false
	for unused in 40:
		if float(session.cooldowns.get(1,0))<=0: break
		await _frame()
		if finished: return false
	var count: int = session.stats.abilities
	session._action_received(1,"ability",{"ability":ability,"target_id":id,"mode":mode})
	await _frame()
	if finished: return false
	return _check(session.stats.abilities==count+1,"original nearby/LOS ability accepts "+ability+" on "+id,_diagnostics())

func _near(id: String) -> bool:
	return await _place(session.world.objects[id].global_position+Vector3.UP*3.4,"near "+id)

func _place(at: Vector3,label: String) -> bool:
	var actor: FlightBodyV2 = session.players[1]
	var shape := actor.get_node("Envelope") as CollisionShape3D
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = shape.shape
	query.transform = Transform3D(Basis.IDENTITY,at)*shape.transform
	query.collision_mask = 1|2|8|32
	query.exclude = [actor.get_rid()]
	var hits: Array[Dictionary] = session.world.get_world_3d().direct_space_state.intersect_shape(query,8)
	if not _check(hits.is_empty() and Regions.contains(region,at),"QA observation pose has actual full-aircraft clearance: "+label,{"at":at,"hits":hits.map(func(hit: Dictionary): return str(hit.collider.get_path()))}): return false
	actor.freeze = true
	actor.global_transform = Transform3D(Basis.IDENTITY,at)
	actor.force_update_transform()
	PhysicsServer3D.body_set_state(actor.get_rid(),PhysicsServer3D.BODY_STATE_TRANSFORM,actor.global_transform)
	actor.linear_velocity = Vector3.ZERO
	actor.angular_velocity = Vector3.ZERO
	actor.hold_height = at.y
	await _frame()
	return not finished

func _press_g() -> void:
	session.interface.clear_dialogue()
	var event := InputEventKey.new()
	event.physical_keycode = KEY_G
	event.keycode = KEY_G
	event.pressed = true
	session._unhandled_input(event)

func _wait_goal(id: String,frames: int) -> bool:
	for unused in frames:
		if id in session.story.state.get("completed",[]): return _check(true,"original Story commits current objective: "+id,_receipt(id))
		await _frame()
		if finished: return false
	return _check(false,"original Story commits current objective: "+id,_diagnostics())

func _receipt(id: String) -> Dictionary:
	for receipt: Dictionary in session.story.state.get("receipts",{}).values():
		if receipt.get("objective_id")==id: return receipt.duplicate(true)
	return {}

func _growth_diagnostics() -> Dictionary:
	var body: PhysicsBody3D = session.world.objects["F3:nutrient_bridge"]
	var size := Vector3.ZERO
	for node: Node in body.get_children():
		if node is CollisionShape3D and node.shape is BoxShape3D: size = node.shape.size
	var candidate := BoxShape3D.new()
	candidate.size = Vector3(3,.4,3)
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = candidate
	query.transform = body.global_transform
	query.collision_mask = 1|2|8
	query.exclude = [body.get_rid()]
	query.margin = 0.0
	var hits: Array[Dictionary] = session.world.get_world_3d().direct_space_state.intersect_shape(query,8)
	return {"growth":session.entities["F3:nutrient_bridge"].get("growth"),"actual_shape_size":size,"candidate_shape_hits":hits.map(func(hit: Dictionary): return str(hit.collider.get_path())),"production_growth_blockers":session.world.campaign_growth_blockers.get("F3:nutrient_bridge",[]),"route":session.campaign.mechanisms.verified_nutrient_route(),"view":session.campaign.mechanisms.view_state()}

func _frame() -> void:
	await physics_frame
	await process_frame

func _phase(label: String) -> void:
	var row := {"phase":label,"diagnostics":_diagnostics()}
	phases.append(row)
	print("CAMPAIGN_LATE_PROGRESS "+JSON.stringify(row))

func _diagnostics() -> Dictionary:
	if not is_instance_valid(session): return {"session":"not_installed"}
	return {"region":session.region_id,"stored_region":session.world_cache.world.get("region_id"),"message":session.interface.message.text,"world_errors":session.world.build_errors if is_instance_valid(session.world) else [],"campaign_error":session.campaign.error,"last_commit_result":session.last_commit_result.duplicate(true),"blockers":session.campaign.last_operation_blockers,"mechanism":session.campaign.mechanisms.persistent_state() if session.campaign.mechanisms!=null else {},"view":session.campaign.mechanisms.view_state() if session.campaign.mechanisms!=null else {},"native_actor":session.ecology.simulation.snapshot().actors.get(ACTOR,{}),"ecology_event_serial":session.ecology.last_event_serial,"current_targets":session.story.current_targets()}

func _check(ok: bool,label: String,actual: Variant=null) -> bool:
	checks.append({"passed":ok,"label":label,"actual":actual})
	return ok

func _finish() -> void:
	if finished: return
	finished = true
	var failures: Array = checks.filter(func(row: Dictionary): return not row.passed)
	var report := {"region":region,"checks":checks,"failures":failures,"engine_errors":logger.errors,"fixture_receipts":fixture_receipts,"phases":phases,"source_batches":source_batches,"native_proof":native_proof,"diagnostics":_diagnostics(),"scope":"F3 only, actual MAIN blank QA loads in-memory playable development region before a Director-valid prior-rule fixture. Fixture stops before all F3 objectives and sets only matching already-loaded world.region_id; no prior physical services or played campaign are claimed. Current root sample/NPC readings use actual nearby/LOS G. Original light plus three growth abilities must create the real fully supported bridge; actual G hold/breaker and original echo must yield and persist signal isolation before NPC supply becomes powered. Explicit QA actor observation positions have full-hull clearance. Native-source acceleration calls only original LivingWorld.advance with a bounded next-source-second delta, then ordinary MAIN consumes its internally sealed original cargo_loaded/transport_arrival source pipeline and commits the original proof/Story through Store. It never supplies an event, nutrition, actor state, context, fact, HP, proof or synthetic goal. New original Store reader verifies output. No Boss fight, normal flown progression, real-time NPC journey duration, graphics, performance, LAN, human fun or full campaign acceptance."}
	FileAccess.open(output+"/result.json",FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
	print("CAMPAIGN_LATE_MAIN_RESULT "+JSON.stringify({"region":region,"checks":checks.size(),"failures":failures,"engine_errors":logger.errors,"native_proof":native_proof,"diagnostics":report.diagnostics}))
	if is_instance_valid(session):
		session.environment_save_gate.cancel("qa_teardown")
		if session.canal!=null: session.canal.clear()
		session.network.close()
		session.free()
		session = null
	await process_frame
	await physics_frame
	await process_frame
	quit(0 if failures.is_empty() and logger.errors.is_empty() and not native_proof.is_empty() else 1)
