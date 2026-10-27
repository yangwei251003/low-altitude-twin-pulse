extends SceneTree
## Development-area construction evidence only. Catalog availability is patched
## in this isolated process; no data file, unlock, objective or reward is authored.
const MAIN = preload("res://scenes/v3/main.tscn")
const Regions = preload("res://scripts/v3/world/twin_region_catalog.gd")
const Layout = preload("res://scripts/v3/campaign/twin_campaign_layout.gd")
const Catalog = preload("res://scripts/v3/campaign/twin_campaign_catalog.gd")
const Store = preload("res://scripts/v3/core/twin_world_store.gd")
const ORDER := ["F2","I3","F3","I4","F4"]
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
var reload_evidence := ""
var checks: Array = []
var shots: Array = []
var reports: Array = []
var finished := false
var save_result: Dictionary = {}
var saved_envelope: Dictionary = {}
var original_availability: Dictionary = {}

func _initialize() -> void:
	OS.add_logger(logger)
	_run.call_deferred()

func _run() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--qa-profile="): profile = arg.trim_prefix("--qa-profile=")
		if arg.begins_with("--output="): output = arg.trim_prefix("--output=")
		if arg.begins_with("--reload-evidence="): reload_evidence = arg.trim_prefix("--reload-evidence=")
	var diagnostic: bool = not reload_evidence.is_empty()
	var valid_evidence: bool = reload_evidence.begins_with("res://artifacts/v3/campaign-worlds-") and reload_evidence.ends_with("/result.json") and ".." not in reload_evidence and FileAccess.file_exists(reload_evidence)
	if not profile.begins_with("qa_campaign_worlds_") or profile!=profile.validate_filename() or not output.begins_with("res://artifacts/v3/campaign-worlds-") or ".." in output or DirAccess.dir_exists_absolute(output) or (DirAccess.dir_exists_absolute("user://profiles_v3/"+profile) and not diagnostic) or (diagnostic and not valid_evidence) or (DisplayServer.get_name()=="headless" and not diagnostic):
		quit(2)
		return
	DirAccess.make_dir_recursive_absolute(output)
	create_timer(75).timeout.connect(func():
		if not finished:
			_check(false,"bounded campaign area construction check")
			_finish())
	root.size = Vector2i(1280,720)
	Regions._entries = Regions.entries()
	for item: Dictionary in Regions._entries:
		var id := str(item.get("id",""))
		if id not in ORDER: continue
		var spec: Dictionary = Layout.definition(id)
		original_availability[id] = bool(item.get("playable",false))
		if not _check(not spec.is_empty(),"authored development layout exists: "+id):
			_finish()
			return
		item.playable = true
		item.spawn = spec.spawn.duplicate()
		item.bounds = spec.bounds.duplicate()
	_check(original_availability.size()==5,"five catalog entries patched only in isolated process",original_availability)
	session = MAIN.instantiate()
	root.add_child(session)
	if not _check(session.profile_ready and session.start_flight("solo"),"actual MAIN opens new isolated solo profile"):
		_finish()
		return
	session.inputs.test_enabled = true
	session.inputs.test_frame = {"axes":{},"held":["brake"],"edges":[]}
	if diagnostic:
		var frozen: Variant = JSON.parse_string(FileAccess.get_file_as_string(reload_evidence))
		if not _check(frozen is Dictionary and frozen.get("saved_F4_envelope",{}) is Dictionary and not frozen.get("saved_F4_envelope",{}).is_empty(),"frozen prior saved F4 envelope is available"):
			_finish()
			return
		saved_envelope = frozen.saved_F4_envelope.duplicate(true)
		var state: Dictionary = session.story.state.duplicate(true)
		var discoveries: Array = session.store.snapshot().personal.discoveries.duplicate()
		await _reopen_and_compare(state,discoveries)
		_finish()
		return
	for id: String in ORDER:
		if not _check(session._load_region(id) and session.region_id==id,"native MAIN adopts development region: "+id):
			_finish()
			return
		await physics_frame
		await physics_frame
		if not _inspect(id):
			_finish()
			return
		await _pause_roundtrip(id)
		if finished: return
		await _capture(id)
		if finished: return
	await _save_and_reopen()
	_finish()

func _inspect(id: String) -> bool:
	var world: Node3D = session.world
	var layout: Dictionary = Layout.definition(id)
	if not _check(world.build_errors.is_empty() and world.campaign_layout.get("ok",false) and is_instance_valid(world.campaign_arena) and session.campaign.supported() and session.campaign.error.is_empty(),"layout, arena and Session adapter ready: "+id,{"build_errors":world.build_errors,"adapter_error":session.campaign.error}): return false
	var pilot: FlightBodyV2 = session.players[1]
	var declared := _vector(layout.spawn)
	var hull := pilot.get_node("Envelope") as CollisionShape3D
	for point: Vector3 in [declared,pilot.global_position]:
		var query := PhysicsShapeQueryParameters3D.new()
		query.shape = hull.shape
		query.transform = Transform3D(Basis.IDENTITY,point)*hull.transform
		query.collision_mask = 1|8|32
		query.exclude = [pilot.get_rid()]
		query.margin = .002
		var hits: Array[Dictionary] = world.get_world_3d().direct_space_state.intersect_shape(query,8)
		if not _check(hits.is_empty(),"full aircraft free at declared/actual spawn: "+id,{"point":point,"hits":hits.map(func(row: Dictionary): return str(row.collider.get_path()))}): return false
	var expected_top := -INF
	for solid: Dictionary in layout.solids:
		var at := _vector(solid.position)
		var size := _vector(solid.size)
		var top := at.y+size.y*.5
		if absf(declared.x-at.x)<=size.x*.5 and absf(declared.z-at.z)<=size.z*.5 and top<declared.y-.3: expected_top = maxf(expected_top,top)
	var ray: Dictionary = world.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(declared+Vector3.UP*.1,declared+Vector3.DOWN*50,1))
	_check(is_finite(expected_top) and not ray.is_empty() and is_equal_approx(ray.position.y,expected_top) and ray.collider.has_meta("campaign_purpose"),"actual solid ground ray beneath spawn: "+id,{"expected_top":expected_top,"actual":ray.get("position")})
	var devices: Array = []
	for spec: Dictionary in Catalog.physical_entities(id):
		var key := str(spec.id)
		var body := world.objects.get(key) as PhysicsBody3D
		var valid: bool = body!=null and session.entities.has(key) and body.get_meta("entity_id","")==key
		if valid:
			valid = body.global_position.distance_to(_vector(spec.position))<.001 and body.collision_layer==8 and body.collision_mask==11 and Vector3(session.entities[key].position).distance_to(body.global_position)<.001
			var physical: Transform3D = PhysicsServer3D.body_get_state(body.get_rid(),PhysicsServer3D.BODY_STATE_TRANSFORM)
			valid = valid and physical.origin.distance_to(body.global_position)<.001
		_check(valid,"real device position, target identity and filters: "+key)
		devices.append({"id":key,"actual":body.global_position if body!=null else null,"layer":body.collision_layer if body!=null else null,"mask":body.collision_mask if body!=null else null})
	var arena: Node3D = world.campaign_arena
	var metadata: Dictionary = {}
	for node: Node in world.find_children("*","CollisionObject3D",true,false):
		if node.has_meta("entity_id"):
			var key := str(node.get_meta("entity_id"))
			metadata[key] = int(metadata.get(key,0))+1
	var unique: bool = arena.targets.size()==arena.definition.parts.size()+1
	for key: String in arena.targets:
		var body: PhysicsBody3D = arena.targets[key]
		unique = unique and metadata.get(key,0)==1 and body.get_meta("entity_id","")==key and world.objects.get(key)==body and arena.definitions.get(key,{}).get("id")==key and session.entities.has(key) and body.collision_layer==8 and body.collision_mask==0
	_check(unique,"arena targets have unique real entity metadata and masks: "+id,{"targets":arena.targets.keys(),"counts":metadata})
	_check(not session.campaign.active() and not session.boss_active and session.story.state.get("completed",[]).is_empty(),"no Boss engagement or task completion manufactured: "+id)
	reports.append({"region":id,"declared_spawn":declared,"actual_player":pilot.global_position,"ground_top":expected_top,"devices":devices,"arena_targets":arena.targets.keys(),"metadata":metadata})
	return true

func _pause_roundtrip(id: String) -> void:
	session._request_pause()
	await physics_frame
	var before: Vector3 = session.players[1].global_position
	var clock: float = session.world.clock_seconds
	await physics_frame
	await physics_frame
	_check(session.simulation_paused and session.players[1].freeze and session.players[1].global_position.is_equal_approx(before) and is_equal_approx(session.world.clock_seconds,clock),"normal pause freezes original player and world clock: "+id)
	session._request_pause()
	await physics_frame
	await physics_frame
	_check(not session.simulation_paused and not session.players[1].freeze and session.campaign.error.is_empty() and session.world.build_errors.is_empty(),"normal resume retains valid world and adapter: "+id,session.campaign.error)

func _capture(id: String) -> void:
	var pilot: FlightBodyV2 = session.players[1]
	session.flight_camera.target_size = 26
	session.camera.size = 26
	session.flight_camera.snap(pilot.global_position)
	session.interface.vitals.text = "开发区实际MAIN · QA临时载入 · 非正常解锁通关"
	await create_timer(.3).timeout
	await RenderingServer.frame_post_draw
	var frame: Image = root.get_texture().get_image()
	_check(frame!=null and not frame.is_empty() and frame.save_png(output+"/"+id+"-default.png")==OK,"one actual default 26m GPU view: "+id)
	shots.append({"region":id,"player":pilot.global_position,"camera_size":session.camera.size,"camera_transform":session.camera.global_transform})

func _save_and_reopen() -> void:
	session._request_pause()
	await physics_frame
	if not _check(session.simulation_paused,"final F4 save observes paused real mechanisms"): return
	var requested: Dictionary = session.request_environment_save(func(result: Dictionary): save_result = result.duplicate(true))
	for tick in range(120):
		if not save_result.is_empty(): break
		await physics_frame
	if not _check(requested.get("ok",false) and save_result.get("ok",false),"original Store environment save succeeds",save_result): return
	# Read an actual published generation through a new Store, rather than
	# treating an in-memory envelope as if it already crossed JSON persistence.
	var reader = Store.new(session.store.root_path)
	var reopened: Dictionary = reader.load_profile()
	if not _check(reopened.get("ok",false),"new Store reads published F4 generation",reopened): return
	var saved: Dictionary = reader.snapshot()
	saved_envelope = saved.world.get("environment",{}).get("campaign_F4",{}).duplicate(true)
	if not _check(not saved_envelope.is_empty() and saved_envelope.get("encounter",{}).is_empty() and not bool(saved_envelope.get("observed",true)),"Store saves real F4 mechanism envelope without invented encounter"): return
	var state: Dictionary = session.story.state.duplicate(true)
	var discoveries: Array = saved.personal.discoveries.duplicate()
	await _reopen_and_compare(state,discoveries)

func _reopen_and_compare(state: Dictionary,discoveries: Array) -> void:
	session.network.close()
	session.free()
	await process_frame
	await physics_frame
	# New MAIN owns a new Store object and reads the actual generation files.
	session = MAIN.instantiate()
	root.add_child(session)
	if not _check(session.profile_ready and session.start_flight("solo") and session._load_region("F4"),"fresh actual MAIN/Store reopens saved development area"): return
	session.set_physics_process(false) # Readback before normal mechanism ticks.
	var actual: Dictionary = session.campaign.persistent_states().get("world.environment.campaign_F4",{})
	var story_actual: Dictionary = session.story.state.duplicate(true)
	var discoveries_actual: Array = session.store.snapshot().personal.discoveries.duplicate()
	var envelope_matches: bool = session.store.matches_persisted_value(actual,saved_envelope)
	var story_expected_valid: Dictionary = session.story.director.validate_state(state)
	var story_actual_valid: Dictionary = session.story.director.validate_state(story_actual)
	# A fresh profile's default Story has not necessarily been submitted to
	# world.actions.opening. Both native defaults must cross the same explicit
	# JSON boundary; the original Store helper still roundtrips live only once.
	var story_expected_persisted: Variant = JSON.parse_string(JSON.stringify(state,"",true,true))
	var story_matches: bool = bool(story_expected_valid.get("ok",false)) and bool(story_actual_valid.get("ok",false)) and session.store.matches_persisted_value(story_actual,story_expected_persisted)
	var discoveries_match: bool = discoveries_actual==discoveries
	var evidence: Dictionary = {"expected_envelope":saved_envelope,"actual_envelope":actual,"story_expected":state,"story_actual":story_actual,
		"discoveries_expected":discoveries,"discoveries_actual":discoveries_actual,"envelope_matches":envelope_matches,"story_matches":story_matches,"discoveries_match":discoveries_match,
		"story_expected_validation":story_expected_valid,"story_actual_validation":story_actual_valid,"story_boundary":"both native defaults explicitly cross identical JSON persistence boundary; original Store helper unchanged"}
	var differences: Array = []
	_diff_fields(saved_envelope,actual,"envelope",differences)
	_diff_fields(state,story_actual,"story",differences)
	_diff_fields(discoveries,discoveries_actual,"discoveries",differences)
	print("CAMPAIGN_READBACK_DIFF "+JSON.stringify({"envelope_matches":envelope_matches,"story_matches":story_matches,"discoveries_match":discoveries_match,"fields":differences}))
	_check(envelope_matches and story_matches and discoveries_match,"fresh Store restores exact semantic mechanism state and unchanged story/rewards",evidence)
	_check(session.world.build_errors.is_empty() and session.campaign.error.is_empty(),"reopened World and adapter remain valid")

static func _diff_fields(expected: Variant,actual: Variant,path: String,found: Array) -> void:
	if found.size()>=40: return
	if expected is Dictionary and actual is Dictionary:
		var keys: Array = expected.keys()
		for key: Variant in actual:
			if key not in keys: keys.append(key)
		for key: Variant in keys:
			if not expected.has(key) or not actual.has(key): found.append({"path":path+"."+str(key),"expected_has":expected.has(key),"actual_has":actual.has(key)})
			else: _diff_fields(expected[key],actual[key],path+"."+str(key),found)
	elif expected is Array and actual is Array:
		if expected.size()!=actual.size(): found.append({"path":path+".size","expected":expected.size(),"actual":actual.size()})
		for index in range(mini(expected.size(),actual.size())): _diff_fields(expected[index],actual[index],path+"["+str(index)+"]",found)
	elif typeof(expected)!=typeof(actual) or expected!=actual:
		found.append({"path":path,"expected":expected,"actual":actual,"expected_type":type_string(typeof(expected)),"actual_type":type_string(typeof(actual))})

static func _vector(value: Array) -> Vector3:
	return Vector3(float(value[0]),float(value[1]),float(value[2]))

func _check(ok: bool,label: String,actual: Variant=null) -> bool:
	checks.append({"passed":ok,"label":label,"actual":actual})
	return ok

func _finish() -> void:
	if finished: return
	finished = true
	var failures := checks.filter(func(row: Dictionary): return not row.passed)
	var scope := "Actual MAIN GPU construction of five development areas; catalog playable/spawn/bounds patched only in isolated process. Native layout/device/arena physics identity, spawn space and ground ray, normal pause/resume, one original Store F4 save and fresh-MAIN reload. Five default views. No task facts, Boss victory, normal travel unlock, objective completion, human flight, balance, performance, LAN or full campaign acceptance."
	if not reload_evidence.is_empty(): scope = "Short headless fresh-MAIN/Store reload diagnosis from a new QA copy. Expected F4 envelope comes from the frozen prior result. No five-area rebuild/capture, no source-profile write and no new game completion evidence. Original equality gates unchanged."
	FileAccess.open(output+"/result.json",FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failures":failures,"engine_errors":logger.errors,"shots":shots,"regions":reports,"original_availability":original_availability,"saved_F4_envelope":saved_envelope,"reload_evidence":reload_evidence,"scope":scope},"\t"))
	print("CAMPAIGN_WORLDS_RESULT "+JSON.stringify({"checks":checks.size(),"failures":failures,"engine_errors":logger.errors,"images":shots.size()}))
	if is_instance_valid(session):
		session.network.close()
		session.free()
		session = null
	await process_frame
	quit(0 if failures.is_empty() and logger.errors.is_empty() and shots.size()==(5 if reload_evidence.is_empty() else 0) else 1)
