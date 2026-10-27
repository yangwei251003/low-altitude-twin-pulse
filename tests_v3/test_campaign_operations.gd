extends SceneTree
## Actual MAIN operation/physics/Store check. Only QA actor observation poses
## and explicit obstacle fixtures are authored; this is not a flown route.
const MAIN = preload("res://scenes/v3/main.tscn")
const Regions = preload("res://scripts/v3/world/twin_region_catalog.gd")
const Layout = preload("res://scripts/v3/campaign/twin_campaign_layout.gd")
const Catalog = preload("res://scripts/v3/campaign/twin_campaign_catalog.gd")
const Campaign = preload("res://scripts/v3/gameplay/twin_campaign_session.gd")
const Store = preload("res://scripts/v3/core/twin_world_store.gd")
const GROUPS := {"I3":["I3:cooling_valve"],"F3":["F3:signal_breaker","F3:signal_hold"],
	"I4":["I4:defence_breaker"],"F4":["F4:limited_bus","F4:test_hold","F4:core_charge_breaker"]}
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
var checks: Array = []
var operations: Array = []
var reloads: Array = []
var finished := false

func _initialize() -> void:
	OS.add_logger(logger)
	_run.call_deferred()

func _run() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--qa-profile="): profile = arg.trim_prefix("--qa-profile=")
		if arg.begins_with("--output="): output = arg.trim_prefix("--output=")
	if not profile.begins_with("qa_campaign_operations_") or profile!=profile.validate_filename() or not output.begins_with("res://artifacts/v3/campaign-operations-") or ".." in output or DirAccess.dir_exists_absolute(output) or DirAccess.dir_exists_absolute("user://profiles_v3/"+profile):
		quit(2)
		return
	DirAccess.make_dir_recursive_absolute(output)
	create_timer(90).timeout.connect(func():
		if not finished:
			_check(false,"bounded actual MAIN operations check")
			_finish())
	Regions._entries = Regions.entries()
	for item: Dictionary in Regions._entries:
		if str(item.id) not in GROUPS: continue
		var spec: Dictionary = Layout.definition(str(item.id))
		item.playable = true
		item.spawn = spec.spawn.duplicate()
		item.bounds = spec.bounds.duplicate()
	if not _new_main():
		_finish()
		return
	for region: String in GROUPS:
		session.set_physics_process(true)
		if not _check(session._load_region(region) and session.region_id==region,"actual MAIN loads operation development region: "+region):
			_finish()
			return
		await physics_frame
		await physics_frame
		session.set_physics_process(false) # Isolate operation transactions from autosave.
		var expected: Dictionary = {}
		for id: String in GROUPS[region]:
			var operated: Dictionary = await _exercise(id)
			if not operated.get("ok",false):
				_finish()
				return
			expected[id] = operated.expected
		await _disk_reopen(region,expected)
		if finished: return
	_check(operations.size()==7 and reloads.size()==4,"seven real devices and four disk-backed MAIN reopen checks executed")
	_finish()

func _new_main() -> bool:
	session = MAIN.instantiate()
	root.add_child(session)
	var ready: bool = session.profile_ready and session.start_flight("solo")
	if ready:
		session.inputs.test_enabled = true
		session.inputs.test_frame = {"axes":{},"held":["brake"],"edges":[]}
	return _check(ready,"new actual MAIN/Store opens QA solo")

func _exercise(id: String) -> Dictionary:
	var world: Node3D = session.world
	if not _check(world.build_errors.is_empty() and session.campaign.supported() and Campaign.OPERATIONS.has(id) and world.objects.has(id),"original device and operate adapter available: "+id): return {"ok":false}
	var body := world.objects[id] as PhysicsBody3D
	var shape: CollisionShape3D
	for child: Node in body.get_children():
		if child is CollisionShape3D: shape = child
	if not _check(shape!=null and shape.shape is BoxShape3D and body.get_meta("entity_id","")==id and body.collision_layer==8 and body.collision_mask==11,"original operation body, box and target filters: "+id): return {"ok":false}
	var initial := body.global_transform
	var contract: Dictionary = Campaign.OPERATIONS[id]
	var expected := initial
	if contract.get("angle",false):
		expected.basis = Basis(Vector3.UP,0.0 if absf(wrapf(body.rotation.y,-PI,PI))>.4 else PI*.5)
	else: expected.origin = contract.open if initial.origin.distance_to(contract.closed)<=.4 else contract.closed
	var actor_ready: bool = await _place_actor(body,shape,expected)
	if not actor_ready: return {"ok":false}
	var actor: FlightBodyV2 = session.players[1]
	_check(session.campaign.operable_near(1,id) and actor.global_position.distance_to(body.global_position)<=4.5 and session._line_clear(actor.global_position,body.global_position,actor.get_rid(),id),"real actor is within 4.5m and LOS: "+id,{"actor":actor.global_position,"device":body.global_position})
	var rid := body.get_rid()
	var shape_id: int = shape.shape.get_instance_id()
	var blocker := StaticBody3D.new()
	blocker.name = "QA_OperationSweepBlocker"
	blocker.collision_layer = 1
	blocker.collision_mask = 0
	world.add_child(blocker)
	var blocked_shape := CollisionShape3D.new()
	var cube := BoxShape3D.new()
	cube.size = Vector3(.16,.16,.16)
	blocked_shape.shape = cube
	blocker.add_child(blocked_shape)
	# Rotation cubes have 0.75m half width: x=.95 lies outside the old
	# axis-aligned box but inside its 45-degree sweep. Translation fixtures
	# occupy the destination and stay outside the old body and actor ray.
	blocker.global_position = initial.origin+Vector3(.95,0,0) if contract.get("angle",false) else expected.origin
	blocker.force_update_transform()
	await physics_frame
	await physics_frame
	var fixture_ok: bool = session._line_clear(actor.global_position,body.global_position,actor.get_rid(),id) and _sweep_hits_fixture(body,shape,initial,expected,blocker)
	if not _check(fixture_ok,"explicit obstacle blocks swept shape while target LOS remains clear: "+id,{"blocker":blocker.global_position}):
		blocker.free()
		return {"ok":false}
	var before: int = session.store.snapshot().generation
	var blocked_handled: bool = session.campaign.operate(1,id)
	await physics_frame
	await physics_frame
	var blocked_pose := body.global_transform
	var after_block: int = session.store.snapshot().generation
	var refused: bool = blocked_handled and blocked_pose.is_equal_approx(initial) and after_block==before
	_check(refused,"real obstruction refuses pose and leaves Store generation unchanged: "+id,{"handled":blocked_handled,"before":before,"after":after_block,"initial":initial,"actual":blocked_pose,"last_operation_blockers":session.campaign.last_operation_blockers})
	blocker.free()
	await physics_frame
	await physics_frame
	if not refused: return {"ok":false}
	var accepted: bool = session.campaign.operate(1,id)
	await physics_frame
	await physics_frame
	var physical: Transform3D = PhysicsServer3D.body_get_state(body.get_rid(),PhysicsServer3D.BODY_STATE_TRANSFORM)
	var actual := body.global_transform
	var after_accept: int = session.store.snapshot().generation
	var moved: bool = accepted and actual.origin.distance_to(expected.origin)<.002 and _angle_error(actual,expected)<.002 and physical.origin.distance_to(expected.origin)<.002 and _angle_error(physical,expected)<.002 and after_accept>after_block
	_check(moved,"unobstructed operation changes real pose and commits original Store: "+id,{"handled":accepted,"expected":expected,"actual":actual,"physics":physical,"generation":after_accept,"message":session.interface.message.text,"last_operation_blockers":session.campaign.last_operation_blockers})
	_check(body.get_rid()==rid and shape.shape.get_instance_id()==shape_id and body.collision_layer==8 and body.collision_mask==11,"operation preserves original body, collision and filters: "+id)
	_check(session.story.state.get("completed",[]).is_empty() and session.store.snapshot().personal.discoveries.is_empty(),"device QA does not fabricate task completion or rewards: "+id)
	operations.append({"id":id,"initial":initial,"expected":expected,"actual":actual,"actor":actor.global_position,"blocked_generation":before,"generation":after_accept,"initial_yaw":initial.basis.get_euler().y,"expected_yaw":expected.basis.get_euler().y})
	return {"ok":moved,"expected":expected}

func _place_actor(body: PhysicsBody3D,shape: CollisionShape3D,next: Transform3D) -> bool:
	var actor: FlightBodyV2 = session.players[1]
	var envelope := actor.get_node("Envelope") as CollisionShape3D
	var offsets: Array[Vector3] = [Vector3(0,3.4,0),Vector3(0,0,3.4),Vector3(0,0,-3.4),Vector3(-3.4,0,0),Vector3(3.4,0,0),Vector3(0,-3.4,0)]
	for offset: Vector3 in offsets:
		var at := body.global_position+offset
		var query := PhysicsShapeQueryParameters3D.new()
		query.shape = envelope.shape
		query.transform = Transform3D(Basis.IDENTITY,at)*envelope.transform
		query.collision_mask = 1|8|32
		query.exclude = [actor.get_rid()]
		query.margin = .002
		var hits: Array[Dictionary] = body.get_world_3d().direct_space_state.intersect_shape(query,8)
		if not hits.is_empty() or not session._line_clear(at,body.global_position,actor.get_rid(),str(body.get_meta("entity_id"))): continue
		# Keep the placed actor outside the device's final volume as well.
		var actor_bounds := AABB(at-envelope.shape.size*.5,envelope.shape.size)
		var final_bounds: AABB = (next*shape.transform)*AABB(-shape.shape.size*.5,shape.shape.size)
		if actor_bounds.intersects(final_bounds): continue
		actor.freeze = true
		actor.global_transform = Transform3D(Basis.IDENTITY,at)
		actor.force_update_transform()
		PhysicsServer3D.body_set_state(actor.get_rid(),PhysicsServer3D.BODY_STATE_TRANSFORM,actor.global_transform)
		actor.linear_velocity = Vector3.ZERO
		actor.angular_velocity = Vector3.ZERO
		await physics_frame
		await physics_frame
		return _check(true,"collision-checked QA actor observation pose",at)
	return _check(false,"no safe nearby actor pose for operation",str(body.get_meta("entity_id")))

func _sweep_hits_fixture(body: PhysicsBody3D,shape: CollisionShape3D,old: Transform3D,next: Transform3D,fixture: StaticBody3D) -> bool:
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = shape.shape
	query.collision_mask = 1
	query.exclude = [body.get_rid()]
	query.margin = .001
	query.transform = old*shape.transform
	var old_hits: Array[Dictionary] = body.get_world_3d().direct_space_state.intersect_shape(query,16)
	for hit: Dictionary in old_hits:
		if hit.get("collider")==fixture: return false
	for step in range(1,9):
		query.transform = old.interpolate_with(next,float(step)/8.0)*shape.transform
		var hits: Array[Dictionary] = body.get_world_3d().direct_space_state.intersect_shape(query,16)
		for hit: Dictionary in hits:
			if hit.get("collider")==fixture: return true
	return false

func _disk_reopen(region: String,expected: Dictionary) -> void:
	var reader = Store.new(session.store.root_path)
	var loaded: Dictionary = reader.load_profile()
	if not _check(loaded.get("ok",false),"new original Store reader opens operation generation: "+region):
		_finish()
		return
	var persisted: Dictionary = reader.snapshot().world.get("entities",{}).get(region,{})
	for id: String in expected:
		var row: Dictionary = persisted.get(id,{})
		var pose: Transform3D = expected[id]
		var point: Variant = row.get("position")
		var matches: bool = point is Array and point.size()==3 and _vector(point).distance_to(pose.origin)<.002 and absf(wrapf(float(row.get("angle",INF))-pose.basis.get_euler().y,-PI,PI))<.002
		_check(matches,"real disk entity stores physical operation position/angle: "+id,row)
	session.network.close()
	session.free()
	session = null
	await process_frame
	await physics_frame
	if not _new_main() or not _check(session._load_region(region),"fresh MAIN reloads operated region: "+region):
		_finish()
		return
	session.set_physics_process(false)
	await physics_frame
	await physics_frame
	var restored: Dictionary = {}
	for id: String in expected:
		var body: PhysicsBody3D = session.world.objects[id]
		var pose: Transform3D = expected[id]
		var physical: Transform3D = PhysicsServer3D.body_get_state(body.get_rid(),PhysicsServer3D.BODY_STATE_TRANSFORM)
		var actual := body.global_transform
		var valid: bool = actual.origin.distance_to(pose.origin)<.002 and _angle_error(actual,pose)<.002 and physical.origin.distance_to(pose.origin)<.002 and _angle_error(physical,pose)<.002
		_check(valid,"fresh MAIN restores real scene and physics operation pose: "+id,{"expected":pose,"actual":actual,"physics":physical})
		restored[id] = actual
	_check(session.campaign.error.is_empty() and session.world.build_errors.is_empty(),"reloaded operation adapter and World remain valid: "+region)
	reloads.append({"region":region,"restored":restored,"generation":session.store.snapshot().generation})

static func _angle_error(a: Transform3D,b: Transform3D) -> float:
	return absf(wrapf(a.basis.get_euler().y-b.basis.get_euler().y,-PI,PI))

static func _vector(value: Array) -> Vector3:
	return Vector3(float(value[0]),float(value[1]),float(value[2]))

func _check(ok: bool,label: String,actual: Variant=null) -> bool:
	checks.append({"passed":ok,"label":label,"actual":actual})
	return ok

func _finish() -> void:
	if finished: return
	finished = true
	var failures: Array = checks.filter(func(row: Dictionary): return not row.passed)
	FileAccess.open(output+"/result.json",FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failures":failures,"engine_errors":logger.errors,"operations":operations,"reloads":reloads,"scope":"Actual MAIN, QA-only playable development catalog, seven production campaign.operate devices, actual nearby/LOS actor observation placements, real swept-physics obstruction with unchanged Store generation, accepted original Store operation commits and four fresh MAIN/disk reloads. No production Store comparator or tolerance changes; 0.002m/radian checks are physical pose accuracy only. No flown route, task completion, unlock, graphics, balance, LAN or full campaign evidence."},"\t"))
	print("CAMPAIGN_OPERATIONS_RESULT "+JSON.stringify({"checks":checks.size(),"failures":failures,"engine_errors":logger.errors,"operations":operations.size(),"reloads":reloads.size()}))
	if is_instance_valid(session):
		session.network.close()
		session.free()
		session = null
	await process_frame
	quit(0 if failures.is_empty() and logger.errors.is_empty() and operations.size()==7 and reloads.size()==4 else 1)
