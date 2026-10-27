extends SceneTree
## Real two-process source MAIN/ENet. Only clear PLAYER poses are fixtures.
const MAIN = preload("res://scenes/v3/main.tscn")
const Regions = preload("res://scripts/v3/world/twin_region_catalog.gd")
class ErrorLog extends Logger:
	var errors: Array = []
	var guard := Mutex.new()
	func _log_error(function: String, file: String, line: int, code: String, rationale: String, _notify: bool, kind: int, _trace: Array[ScriptBacktrace]) -> void:
		if kind == Logger.ERROR_TYPE_WARNING: return
		guard.lock()
		if errors.size() < 16: errors.append({"function":function,"file":file,"line":line,"code":code,"rationale":rationale})
		guard.unlock()
var log := ErrorLog.new()
var session: Node
var role := ""
var profile := ""
var run_id := ""
var evidence := ""
var finished := false
var began := 0
var checks: Array = []
var actions: Array = []
var events: Array = []
var fixtures: Array = []
var actor_id := ""
var peer_id := 0
var baseline_story: Dictionary = {}
var baseline_personal: Dictionary = {}
func _initialize() -> void:
	OS.add_logger(log)
	_run.call_deferred()
func _write(name: String, value: Dictionary) -> void:
	var target := evidence.path_join(name+".json")
	var pending := target+".pending"
	if FileAccess.file_exists(target) or FileAccess.file_exists(pending): _check(false,"new small evidence required",name); return
	var file := FileAccess.open(pending,FileAccess.WRITE)
	if not file: _check(false,"small evidence write",name); return
	file.store_string(JSON.stringify(value,"\t")); file.close()
	if DirAccess.rename_absolute(pending,target)!=OK: _check(false,"atomic small evidence rename",name)
func _read(name: String) -> Dictionary:
	var path := evidence.path_join(name+".json")
	if not FileAccess.file_exists(path) or FileAccess.get_file_as_bytes(path).size()>16384: return {}
	var value: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return value if value is Dictionary else {}
func _check(ok: bool, label: String, actual: Variant = null) -> bool:
	var captured: Variant = actual.duplicate(true) if actual is Dictionary or actual is Array else actual
	checks.append({"passed":ok,"label":label,"actual":captured})
	return ok
func _tick() -> bool:
	await physics_frame
	await process_frame
	return not finished
func _run() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--qa-profile="): profile=arg.trim_prefix("--qa-profile=")
		if arg.begins_with("--contact-role="): role=arg.trim_prefix("--contact-role=")
		if arg.begins_with("--contact-run="): run_id=arg.trim_prefix("--contact-run=")
		if arg.begins_with("--contact-evidence="): evidence=arg.trim_prefix("--contact-evidence=").replace("\\","/")
	var managed := OS.get_environment("LOW_ALTITUDE_DEV_HOME").replace("\\","/").trim_suffix("/")
	if role not in ["host","guest"] or managed.is_empty() or run_id.is_empty() or run_id!=run_id.validate_filename() or profile!="qa_npc_contact_lan_"+role+"_"+run_id or DirAccess.dir_exists_absolute("user://profiles_v3/"+profile) or evidence!=managed+"/evidence/npc-contact-lan-"+run_id or not DirAccess.dir_exists_absolute(evidence) or FileAccess.file_exists(evidence.path_join(role+".json")):
		print("NPC_CONTACT_LAN_ARGUMENTS_REJECTED"); quit(2); return
	began=Time.get_ticks_msec()
	create_timer(24.0).timeout.connect(func():
		if not finished: _check(false,"24 second peer hard bound"); _finish())
	session=MAIN.instantiate()
	root.add_child(session)
	if not _check(session.profile_ready and session.store.root_path=="user://profiles_v3/"+profile and session.start_flight(role,"127.0.0.1"),"original MAIN opens fresh private profile/ENet"): _finish(); return
	session.inputs.test_enabled=true
	session.inputs.test_frame={"axes":{},"held":["brake"],"edges":[]}
	session.network.action_received.connect(_action)
	session.network.event_received.connect(_event)
	if role=="host":
		_write("host-started",{"ready":true,"protocol":session.network.PROTOCOL,"port":session.network.DEFAULT_PORT})
		await _host()
	else: await _guest()
	if not finished: _finish()
func _action(sender: int, verb: String, payload: Dictionary) -> void:
	if role!="host" or verb!="explore" or actions.size()>=4: return
	var actor: Dictionary=session.ecology.simulation.get_actor(str(payload.get("target_id","")))
	var at := Vector3.INF
	if not actor.is_empty(): at=session.world.to_global(Vector3(actor.position[0],actor.position[1],actor.position[2]))
	actions.append({"sender":sender,"claimed_sender":payload.get("peer_id"),"target":payload.get("target_id"),"sequence":session.network.last_action.get(sender),"distance":session.players[sender].global_position.distance_to(at) if at.is_finite() else -1.0,"frame":Engine.get_physics_frames()})
func _event(event: Dictionary) -> void:
	if event.get("kind") in ["dialogue","notice"] and events.size()<8:
		events.append(event.duplicate(true))
func _clear(at: Vector3, body: FlightBodyV2) -> bool:
	if not Regions.contains("I1",at): return false
	var envelope := body.get_node("Envelope") as CollisionShape3D
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape=envelope.shape; query.transform=Transform3D(Basis.IDENTITY,at)*envelope.transform
	query.collision_mask=1|2|8|32; query.exclude=[body.get_rid()]
	return session.world.get_world_3d().direct_space_state.intersect_shape(query,1).is_empty()
func _place(near: bool) -> Dictionary:
	var body: FlightBodyV2=session.players[peer_id]
	for actor: Dictionary in session.ecology.simulation.get_actors("I1"):
		if not actor_id.is_empty() and actor.id!=actor_id: continue
		var point: Vector3=session.world.to_global(Vector3(actor.position[0],actor.position[1],actor.position[2]))
		var offsets: Array = [Vector3(0,2.6,0),Vector3(2.5,1,0),Vector3(-2.5,1,0),Vector3(0,1,2.5)] if near else [Vector3(12,6,0),Vector3(-12,6,0),Vector3(0,6,12)]
		for offset: Vector3 in offsets:
			var at: Vector3=point+offset
			if not _clear(at,body) or near and not session._line_clear(at,point,body.get_rid(),actor.id): continue
			actor_id=actor.id
			body.freeze=true; body.set_physics_process(false)
			body.global_transform=Transform3D(Basis.IDENTITY,at); body.force_update_transform()
			PhysicsServer3D.body_set_state(body.get_rid(),PhysicsServer3D.BODY_STATE_TRANSFORM,body.global_transform)
			body.linear_velocity=Vector3.ZERO; body.angular_velocity=Vector3.ZERO; body.hold_height=at.y
			var fixture := {"kind":"clear_PLAYER_pose_not_flown_no_NPC_edit","near":near,"actor_id":actor_id,"player_id":peer_id,"position":[at.x,at.y,at.z],"npc_position":[point.x,point.y,point.z],"name":actor.name,"purpose":actor.purpose,"distance":at.distance_to(point)}
			fixtures.append(fixture); return fixture
	return {}
func _baseline() -> void:
	baseline_story=session.story.state.duplicate(true)
	baseline_personal=session.store.snapshot().personal.duplicate(true)
func _host() -> void:
	while session.network.guests.size()!=1 or session.players.size()!=2:
		if not await _tick(): return
	peer_id=int(session.network.guests.keys()[0])
	_baseline()
	var far := _place(false)
	if not _check(not far.is_empty() and far.distance>4.5,"far clear PLAYER fixture near actual I1 roster"): return
	_write("host-far",far)
	while _read("guest-far-done").is_empty():
		if not await _tick(): return
	if not _check(actions.size()==1 and actions[0].sender==peer_id and actions[0].claimed_sender==1 and actions[0].distance>4.5,"original ENet sender ignores forged payload identity and position at far rejection",actions): return
	var near := _place(true)
	if not _check(not near.is_empty(),"near clear PLAYER fixture with actual Host LOS"): return
	_write("host-near",near)
	while _read("guest-done").is_empty():
		if not await _tick(): return
	_check(actions.size()==2 and actions[1].sender==peer_id and actions[1].claimed_sender==1 and actions[1].distance<=4.5,"second original ENet request resolves actual Guest actor near live NPC",actions)
	_check(not session.interface.radio.visible and session.interface.radio_queue.is_empty() and not events.any(func(e: Dictionary): return e.get("kind")=="dialogue"),"Host UI receives no Guest-only dialogue")
func _guest() -> void:
	while session.received_sequence<0 or not session._facilities_ready() or not session.players.has(session.network.local_id()) or session.ecology.applied_serial<=0:
		if not await _tick(): return
	peer_id=session.network.local_id()
	session.players[peer_id].freeze=true; session.players[peer_id].set_physics_process(false)
	_baseline()
	var far: Dictionary={}
	while far.is_empty():
		if not await _tick(): return
		far=_read("host-far")
	actor_id=far.actor_id
	if not await _wait_pose(far): return
	session.network.send_action("explore",{"target_id":actor_id,"peer_id":1,"position":far.npc_position})
	while not events.any(func(e: Dictionary): return e.get("kind")=="notice" and "移出联络距离" in str(e.get("text",""))):
		if not await _tick(): return
	for unused in 12:
		if not await _tick(): return
	if not _check(not session.interface.radio.visible and not events.any(func(e: Dictionary): return e.get("kind")=="dialogue"),"real far request gets Host rejection and no dialogue",events): return
	_write("guest-far-done",{"passed":true})
	var near: Dictionary={}
	while near.is_empty():
		if not await _tick(): return
		near=_read("host-near")
	if not await _wait_pose(near): return
	session.network.send_action("explore",{"target_id":actor_id,"peer_id":1,"position":near.npc_position})
	while not events.any(func(e: Dictionary): return e.get("kind")=="dialogue"):
		if not await _tick(): return
	var dialogues: Array=events.filter(func(e: Dictionary): return e.get("kind")=="dialogue")
	var reply: Dictionary=dialogues[0]
	_check(peer_id!=1 and dialogues.size()==1 and reply.character_id==actor_id and reply.speaker_name==near.name and reply.lines[0]==near.purpose,"real directed Host event names actual NPC and original purpose",reply)
	_check(session.interface.radio.visible and session.interface.radio_speaker.text==near.name and session.interface.radio_text.text==near.purpose,"original Guest radio displays NPC name and duty")
	_check(not session.owns_world and session.ecology.simulation.elapsed_seconds()==0.0 and session.ecology.applied_serial>0,"Guest presents authoritative ecology without locally advancing simulation",{"elapsed":session.ecology.simulation.elapsed_seconds(),"applied_serial":session.ecology.applied_serial})
	_write("guest-done",{"completed":true})
	for unused in 12:
		if not await _tick(): return
func _wait_pose(fixture: Dictionary) -> bool:
	var point := Vector3(fixture.position[0],fixture.position[1],fixture.position[2])
	while session.players[peer_id].global_position.distance_to(point)>0.6 or not session.ecology.view.targets.has(fixture.actor_id):
		if not await _tick(): return false
	return true
func _finish() -> void:
	if finished: return
	finished=true
	if is_instance_valid(session) and not baseline_story.is_empty():
		_check(session.story.state==baseline_story and session.store.snapshot().personal==baseline_personal,"contact changes no Story state or personal rewards")
	var failures: Array=checks.filter(func(row: Dictionary): return not row.passed)
	_write(role,{"passed":failures.is_empty() and log.errors.is_empty(),"version":ProjectSettings.get_setting("application/config/version"),"role":role,"profile":profile,"run_id":run_id,"peer_id":peer_id,"checks":checks,"failures":failures,"actions":actions,"events":events,"fixtures":fixtures,"engine_errors":log.errors,"seconds":float(Time.get_ticks_msec()-began)/1000.0,"protocol":session.network.PROTOCOL if is_instance_valid(session) else -1,"scope":"Two MAIN processes, original ENet127.0.0.1 sender/reply. Source or pinned-editor pack resources as declared by driver, not a direct Release EXE probe. Explicit clear PLAYER poses/brake input, no NPC/Store/progress injection. Headless logical UI is not visual/human/physical LAN evidence; no reconnect/full campaign.","original_quit_requested":is_instance_valid(session)})
	if is_instance_valid(session): session._quit()
	else: quit(1)
