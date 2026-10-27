extends SceneTree
## Combat-water rig only. Direct QA region/actor observation fixtures; no story
## prefix, work completion, Boss fight, synthetic water or fabricated fact.
const MAIN = preload("res://scenes/v3/main.tscn")
const Pump = preload("res://scripts/v3/gameplay/twin_pump_guardian_mechanisms.gd")
const Facilities = preload("res://scripts/v3/gameplay/twin_facility_registry.gd")
const Store = preload("res://scripts/v3/core/twin_world_store.gd")
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
var finished := false
var checks: Array = []
var operations: Array = []
var water_state: Dictionary = {}
var saved_envelope: Dictionary = {}
var reloaded: Dictionary = {}
var callbacks: Array = []

func _initialize() -> void:
	OS.add_logger(logger)
	_run.call_deferred()

func _run() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--qa-profile="): profile = arg.trim_prefix("--qa-profile=")
		if arg.begins_with("--output="): output = arg.trim_prefix("--output=")
	if not profile.begins_with("qa_pump_guardian_main_") or profile!=profile.validate_filename() or not output.begins_with("res://artifacts/v3/pump-guardian-main-") or ".." in output or DirAccess.dir_exists_absolute(output) or DirAccess.dir_exists_absolute("user://profiles_v3/"+profile):
		quit(2)
		return
	DirAccess.make_dir_recursive_absolute(output)
	create_timer(20).timeout.connect(func():
		if not finished:
			_check(false,"20 second simulation bound for the small Pump MAIN slice",_diagnostics())
			_finish())
	if not _new_main() or not _check(session._load_region("I2") and session.region_id=="I2","original empty-QA MAIN factory loads actual I2",_diagnostics()):
		_finish()
		return
	await _frame()
	if finished: return
	if not _geometry():
		_finish()
		return
	var facilities_before: Dictionary = _facility_bodies()
	if not _check(facilities_before.size()==15 and session.facilities.all_ready("I2"),"all four original facilities retain their 15 actual registered targets",facilities_before):
		_finish()
		return
	if not await _operate(Pump.VALVE) or not await _operate(Pump.PLUG):
		_finish()
		return
	if not _check(session.campaign.mechanisms.boss_environment("I2").get("civilian_supply_isolated",false),"real withdrawn plug leaves an open physical gap and the original civilian check bypass",_diagnostics()):
		_finish()
		return
	if not await _near(Pump.RELAY):
		_finish()
		return
	var used: int = session.stats.abilities
	session._action_received(1,"ability",{"ability":"charge","target_id":Pump.RELAY,"mode":"add"})
	if not _check(session.stats.abilities==used+1 and session.entities[Pump.RELAY].charge==35.0,"original nearby/LOS charge ability supplies the actual combat relay",_diagnostics()):
		_finish()
		return
	var mechanisms: RefCounted = session.campaign.mechanisms
	var initial: Dictionary = mechanisms.network.snapshot()
	var initial_level: float = mechanisms.network.get_node(Pump.BASIN).level_m
	var started_seconds: float = mechanisms.network.elapsed_seconds()
	var initial_tick: int = int(initial.tick)
	var civilian_unchanged := true
	var resident_samples := 0
	# Observe EACH actual physics signal before the next original Session tick.
	# This reaches exactly 80 solver quanta without inventing a simulation step,
	# then the original drain-charge intent removes power before quantum 81 flows.
	for unused in 510:
		await physics_frame
		if finished: return
		var observed: Dictionary = mechanisms.network.snapshot()
		civilian_unchanged = civilian_unchanged and int(observed.nodes[Pump.CIVILIAN].clean_ml)==300000 and int(observed.nodes[Pump.CIVILIAN].dirty_ml)==0
		resident_samples += 1
		if int(observed.tick)-initial_tick>=80: break
	var threshold: Dictionary = mechanisms.network.snapshot()
	var actual_level: float = mechanisms.network.get_node(Pump.BASIN).level_m
	var elapsed: float = mechanisms.network.elapsed_seconds()-started_seconds
	var original_pending_usec: int = int(initial.pending_usec)
	var remaining_pending_usec: int = int(threshold.pending_usec)
	var newly_elapsed_seconds: float = 8.0+float(remaining_pending_usec-original_pending_usec)/1000000.0
	var physical: Dictionary = mechanisms.boss_environment("I2")
	var valid: Dictionary = mechanisms.network.validate_snapshot(threshold)
	water_state = {"initial":initial,"after_80_quanta":threshold,"initial_level_m":initial_level,"actual_level_m":actual_level,"solver_elapsed_seconds":elapsed,"newly_elapsed_seconds_from_quantum_and_pending_balance":newly_elapsed_seconds,"preexisting_pending_usec":original_pending_usec,"remaining_pending_usec":remaining_pending_usec,"physics_frame":Engine.get_physics_frames(),"environment":physical,"validation":valid,"resident_unchanged_each_frame":civilian_unchanged,"resident_samples":resident_samples}
	var conserved: bool = civilian_unchanged and valid.get("ok",false) and int(threshold.tick)-initial_tick==80 and int(threshold.nodes[Pump.BASIN].clean_ml)==1200000 and int(threshold.nodes[Pump.RETURN].clean_ml)==1000000 and int(threshold.nodes[Pump.CIVILIAN].clean_ml)==300000 and int(threshold.nodes[Pump.CIVILIAN].dirty_ml)==0
	if not _check(conserved and initial_level==2.0 and actual_level==3.0 and absf(elapsed-newly_elapsed_seconds)<.000001 and physical.get("civilian_supply_isolated",false),"80 real 100ms solver quanta transfer 400000ml: actual newly elapsed time reconciles prior pending, basin 2→3m and civilian reserve remains exactly 300000ml",water_state):
		_finish()
		return
	used = session.stats.abilities
	session._action_received(1,"ability",{"ability":"charge","target_id":Pump.RELAY,"mode":"drain"})
	if not _check(session.stats.abilities==used+1 and session.entities[Pump.RELAY].charge==0.0,"original charge drain stops the pump at the observed physical threshold",_diagnostics()):
		_finish()
		return
	await _frame()
	if finished: return
	_check(_facility_bodies()==facilities_before,"water rig operations retain original four-facility bodies, shapes and filters")
	_check(not session.campaign.active() and session.story.state.get("completed",[]).is_empty() and session.store.snapshot().personal.discoveries.is_empty(),"small rig QA invents no prior Story, work result, Boss victory or reward")
	for unused in 20:
		if not session.environment_save_gate.pending(): break
		await _frame()
		if finished: return
	var requested: Dictionary = session.request_environment_save(func(result: Dictionary): callbacks.append(result.duplicate(true)))
	if not _check(requested.get("ok",false) and callbacks.is_empty(),"original Session accepts an asynchronous environment save",requested):
		_finish()
		return
	for unused in 20:
		await _frame()
		if finished: return
		if not callbacks.is_empty(): break
	if not _check(callbacks.size()==1 and callbacks[0].get("ok",false) and callbacks[0].get("completed",false),"original SaveGate completes the real Pump/water Store publication",callbacks):
		_finish()
		return
	var reader = Store.new(session.store.root_path)
	var opened: Dictionary = reader.load_profile()
	var disk: Dictionary = reader.snapshot()
	saved_envelope = disk.world.get("environment",{}).get("campaign_I2",{}).duplicate(true)
	if not _check(opened.get("ok",false) and mechanisms.validate_state(saved_envelope.get("mechanisms",{})).get("ok",false) and int(saved_envelope.mechanisms.simulation.nodes[Pump.BASIN].clean_ml)==1200000,"independent original Store reader verifies the published combat-water envelope",{"opened":opened,"envelope":saved_envelope}):
		_finish()
		return
	var expected: Dictionary = {}
	for id: String in Pump.DEVICES: expected[id] = session.world.objects[id].global_transform
	session.network.close()
	session.free()
	session = null
	await process_frame
	await physics_frame
	await process_frame
	if finished: return
	if not _new_main() or not _check(session._load_region("I2"),"fresh MAIN reads the same QA Store and normally loads I2",_diagnostics()):
		_finish()
		return
	# No new simulation frame before comparing the actual original restored state.
	var actual: Dictionary = session.campaign.mechanisms.persistent_state()
	var matches: bool = session.store.matches_persisted_value(actual,saved_envelope.mechanisms)
	_check(matches and _facility_bodies().size()==15 and session.facilities.all_ready("I2"),"fresh MAIN restores the original physical water/controls and all four facilities",{"expected":saved_envelope.mechanisms,"actual":actual,"diagnostics":_diagnostics()})
	await _frame() # Let restored StaticBody transforms reach the ordinary server boundary.
	if finished: return
	for id: String in expected:
		var body: PhysicsBody3D = session.world.objects[id]
		var pose: Transform3D = body.global_transform
		var physical_pose: Transform3D = PhysicsServer3D.body_get_state(body.get_rid(),PhysicsServer3D.BODY_STATE_TRANSFORM)
		var same: bool = pose.origin.distance_to(expected[id].origin)<.002 and pose.basis.is_equal_approx(expected[id].basis) and physical_pose.origin.distance_to(expected[id].origin)<.002 and physical_pose.basis.is_equal_approx(expected[id].basis)
		_check(same,"fresh MAIN restores actual body/server position and angle: "+id,{"expected":expected[id],"actual":pose,"physics":physical_pose})
	var rig: Node3D = session.world.get_node(Pump.RIG)
	_check(absf(rig.get_node("BasinWater").position.y-2.985)<.00001 and session.campaign.mechanisms.boss_environment("I2").get("civilian_supply_isolated",false),"restored visible basin surface and actual isolation match the saved water")
	reloaded = {"state_matches":matches,"water_level_m":session.campaign.mechanisms.network.get_node(Pump.BASIN).level_m,"generation":session.store.snapshot().generation,"facilities":_facility_bodies()}
	_finish()

func _new_main() -> bool:
	session = MAIN.instantiate()
	root.add_child(session)
	var ok: bool = session.profile_ready and session.start_flight("solo")
	if ok:
		session.inputs.test_enabled = true
		session.inputs.test_frame = {"axes":{},"held":["brake"],"edges":[]}
	return _check(ok and not session.canal_runtime_enabled,"actual MAIN starts solo with ordinary default Canal flag",_diagnostics())

func _geometry() -> bool:
	var rig: Node3D = session.world.get_node_or_null(Pump.RIG)
	if not _check(is_instance_valid(rig) and Pump.fixed_specifications().size()==21 and Pump.tank_specifications().size()==3,"actual MAIN installs the 21-solid/3-surface combat rig"): return false
	var good := true
	var count := 0
	for child: Node in rig.get_children():
		if child is PhysicsBody3D: count += 1
	good = count==21
	for spec: Dictionary in Pump.fixed_specifications():
		var body := rig.get_node_or_null(str(spec.id)) as PhysicsBody3D
		var shape: CollisionShape3D = _shape(body)
		var valid: bool = is_instance_valid(body) and shape!=null and not shape.disabled and shape.shape is BoxShape3D and body.collision_layer==1 and body.collision_mask==11 and body.global_position.is_equal_approx(_vector(spec.position)) and shape.shape.size.is_equal_approx(_vector(spec.size))
		good = good and valid
		_check(valid,"original rig solid retains authored real collision: "+str(spec.id))
	for spec: Dictionary in Pump.tank_specifications():
		var surface := rig.get_node_or_null(str(spec.id)+"Water") as MeshInstance3D
		var valid: bool = is_instance_valid(surface) and surface.mesh is BoxMesh and absf(surface.position.y-(float(spec.initial_level)-.015))<.00001
		good = good and valid
		_check(valid,"original water surface follows its own actual reservoir: "+str(spec.id))
	for spec: Dictionary in Pump.device_specifications():
		var body: PhysicsBody3D = session.world.objects.get(spec.id)
		var shape: CollisionShape3D = _shape(body)
		var valid: bool = body!=null and shape!=null and not shape.disabled and shape.shape is BoxShape3D and shape.shape.size.is_equal_approx(_vector(spec.size)) and body.global_position.is_equal_approx(_vector(spec.position)) and body.collision_layer==8 and body.collision_mask==11 and body.get_meta("entity_id","")==spec.id and session.entities.has(spec.id)
		good = good and valid
		_check(valid,"three original interactive target collision/identity: "+str(spec.id))
	return good

func _operate(id: String) -> bool:
	if not await _near(id): return false
	var body: PhysicsBody3D = session.world.objects[id]
	var shape: CollisionShape3D = _shape(body)
	var initial: Transform3D = body.global_transform
	var expected: Transform3D = initial
	if id==Pump.VALVE: expected.basis = Basis(Vector3.UP,PI*.5)
	else: expected.origin = Pump.PLUG_OPEN
	var rid: RID = body.get_rid()
	var shape_id: int = shape.shape.get_instance_id()
	var before: Dictionary = session.store.snapshot()
	var old_entity: Dictionary = session.entities[id].duplicate(true)
	var old_water: Dictionary = session.campaign.mechanisms.persistent_state()
	session.store.read_only = true
	_press_g(id)
	var refused: bool = session.store.snapshot()==before and body.global_transform.is_equal_approx(initial) and session.entities[id]==old_entity and session.campaign.mechanisms.persistent_state()==old_water
	_check(refused,"original G/Store read_only rolls back device pose, entity and hydraulic ledger: "+id,{"message":session.interface.message.text,"initial":initial,"actual":body.global_transform,"generation":session.store.snapshot().generation})
	session.store.read_only = false
	if not refused: return false
	var blocker := StaticBody3D.new()
	blocker.name = "QA_PumpSweepObstacle"
	blocker.collision_layer = 1
	blocker.collision_mask = 0
	var collision := CollisionShape3D.new()
	var cube := BoxShape3D.new()
	cube.size = Vector3(.12,.12,.12)
	collision.shape = cube
	blocker.add_child(collision)
	session.world.add_child(blocker)
	blocker.global_position = initial.origin+Vector3(.64,0,0) if id==Pump.VALVE else expected.origin
	blocker.force_update_transform()
	await _frame()
	if finished: return false
	var actor: FlightBodyV2 = session.players[1]
	var clear_los: bool = session._line_clear(actor.global_position,body.global_position,actor.get_rid(),id)
	var generation: int = session.store.snapshot().generation
	_press_g(id)
	var blocked: bool = clear_los and not session.campaign.last_operation_blockers.is_empty() and body.global_transform.is_equal_approx(initial) and int(session.store.snapshot().generation)==generation
	_check(blocked,"actual obstacle blocks original G swept travel with unchanged Store generation: "+id,{"blockers":session.campaign.last_operation_blockers.duplicate(true),"message":session.interface.message.text,"obstacle":blocker.global_position})
	blocker.free()
	if not blocked: return false
	_press_g(id)
	await _frame()
	if finished: return false
	var physical: Transform3D = PhysicsServer3D.body_get_state(rid,PhysicsServer3D.BODY_STATE_TRANSFORM)
	var moved: bool = body.global_transform.origin.distance_to(expected.origin)<.002 and body.global_basis.is_equal_approx(expected.basis) and physical.origin.distance_to(expected.origin)<.002 and physical.basis.is_equal_approx(expected.basis) and int(session.store.snapshot().generation)>generation and body.get_rid()==rid and shape.shape.get_instance_id()==shape_id and body.collision_layer==8 and body.collision_mask==11
	_check(moved,"unobstructed original G completes actual pose/server travel and original Store commit: "+id,{"initial":initial,"expected":expected,"actual":body.global_transform,"physics":physical,"blockers":session.campaign.last_operation_blockers,"message":session.interface.message.text})
	operations.append({"id":id,"read_only_rollback":refused,"physical_block":blocked,"moved":moved,"actual":body.global_transform})
	return moved

func _press_g(id: String) -> void:
	session._action_received(1,"lock",{"target_id":id})
	session.interface.clear_dialogue() # Close radio text so G reaches its normal device action.
	var event := InputEventKey.new()
	event.physical_keycode = KEY_G
	event.keycode = KEY_G
	event.pressed = true
	session._unhandled_input(event) # Original G→Story→Transport→Campaign operation path.

func _near(id: String) -> bool:
	var actor: FlightBodyV2 = session.players[1]
	var body: PhysicsBody3D = session.world.objects[id]
	var at: Vector3 = body.global_position+Vector3.UP*3.4
	var shape := actor.get_node("Envelope") as CollisionShape3D
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = shape.shape
	query.transform = Transform3D(Basis.IDENTITY,at)*shape.transform
	query.collision_mask = 1|2|8|32
	query.exclude = [actor.get_rid()]
	var hits: Array[Dictionary] = session.world.get_world_3d().direct_space_state.intersect_shape(query,8)
	if not _check(hits.is_empty() and session._line_clear(at,body.global_position,actor.get_rid(),id),"QA observation position has full aircraft clearance and actual nearby LOS: "+id,{"at":at,"hits":hits.map(func(hit: Dictionary): return str(hit.collider.get_path()))}): return false
	actor.freeze = true
	actor.global_transform = Transform3D(Basis.IDENTITY,at)
	actor.force_update_transform()
	PhysicsServer3D.body_set_state(actor.get_rid(),PhysicsServer3D.BODY_STATE_TRANSFORM,actor.global_transform)
	actor.linear_velocity = Vector3.ZERO
	actor.angular_velocity = Vector3.ZERO
	actor.hold_height = at.y
	await _frame()
	return not finished

func _facility_bodies() -> Dictionary:
	var result: Dictionary = {}
	for spec: Dictionary in Facilities.definitions():
		var adapter: Variant = session.get(spec.id)
		if adapter==null or not adapter.ready or not is_instance_valid(adapter.module) or adapter.module.get_parent()!=session.world: continue
		for id: String in spec.targets:
			var body: Variant = session.world.objects.get(id)
			if not body is PhysicsBody3D or not is_instance_valid(body): continue
			var shape: CollisionShape3D = _shape(body)
			result[id] = {"body":body.get_instance_id(),"rid":str(body.get_rid()),"shape":shape.shape.get_instance_id() if shape!=null else 0,"layer":body.collision_layer,"mask":body.collision_mask}
	return result

static func _shape(body: PhysicsBody3D) -> CollisionShape3D:
	if body==null: return null
	for child: Node in body.get_children():
		if child is CollisionShape3D: return child
	return null

static func _vector(value: Array) -> Vector3:
	return Vector3(float(value[0]),float(value[1]),float(value[2]))

func _frame() -> void:
	await physics_frame
	await process_frame

func _diagnostics() -> Dictionary:
	if not is_instance_valid(session): return {"session":"not_installed"}
	return {"active":session.active,"region":session.region_id,"message":session.interface.message.text,"world_errors":session.world.build_errors if is_instance_valid(session.world) else [],"campaign_error":session.campaign.error,"view":session.campaign.mechanisms.view_state() if session.campaign.mechanisms!=null else {},"generation":session.store.snapshot().generation,"blockers":session.campaign.last_operation_blockers}

func _check(ok: bool,label: String,actual: Variant=null) -> bool:
	checks.append({"passed":ok,"label":label,"actual":actual})
	return ok

func _finish() -> void:
	if finished: return
	finished = true
	var failures: Array = checks.filter(func(row: Dictionary): return not row.passed)
	var report := {"checks":checks,"failures":failures,"engine_errors":logger.errors,"operations":operations,"water_state":water_state,"saved_envelope":saved_envelope,"callbacks":callbacks,"reloaded":reloaded,"diagnostics":_diagnostics(),"scope":"Actual MAIN empty isolated QA I2, original four facilities/15 targets retained, actual combat rig 21 solids/3 water surfaces/3 interactive targets, full-aircraft-clearance frozen QA observation positions, constructed G event through original Session/Story/Transport, real swept collision rejection, original Store.read_only rollback, original charge add/drain intents, exactly 80 ordinary 100ms WaterNetwork quanta and conservative 400000ml transfer from basin 2m to3m with untouched 300000ml resident reserve. Actual newly elapsed time accounts for preexisting and remaining fractional pending; old pending is not claimed as newly powered time. Original asynchronous environment save and fresh MAIN/same-QA-disk restore of actual water/angle/position. No manual solver advance, water/HP/environment truth mutation, prior-story fixture, task completion, Boss combat, normal unlocked flight, graphics, performance, LAN or full service/campaign acceptance. Only these QA files and unique QA profile are written."}
	FileAccess.open(output+"/result.json",FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
	print("PUMP_GUARDIAN_MAIN_RESULT "+JSON.stringify({"checks":checks.size(),"failures":failures,"engine_errors":logger.errors,"reloaded":reloaded,"diagnostics":report.diagnostics}))
	if is_instance_valid(session):
		session.store.read_only = false
		session.environment_save_gate.cancel("qa_teardown")
		if session.canal!=null: session.canal.clear()
		session.network.close()
		session.free()
		session = null
	await process_frame
	await physics_frame
	await process_frame
	quit(0 if failures.is_empty() and logger.errors.is_empty() and not reloaded.is_empty() else 1)
