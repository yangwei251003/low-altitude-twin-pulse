extends SceneTree
## Two real MAIN/ENet peers. Only region, current opportunity and clear PLAYER poses are QA fixtures.
const MAIN = preload("res://scenes/v3/main.tscn")
const Regions = preload("res://scripts/v3/world/twin_region_catalog.gd")
const View = preload("res://scripts/v3/world/twin_campaign_mechanism_view.gd")
const LOW := "F2:record_low"
const HIGH := "F2:record_high"
const PAIR := "F2:paired_records"
const MIRROR := "F2:clock_mirror"
const BYPASS := "F2:clock_mirror_bypass"
class ReadingOpportunity:
	extends "res://scripts/v3/gameplay/twin_opening_story.gd"
	func current_targets() -> Array:
		if ready and session != null and session.region_id == "F2":
			return [{"type":"fact","target_id":"F2:paired_records","options":["both_read"]}]
		return super.current_targets()
class ErrorLog extends Logger:
	var errors: Array = []
	var guard := Mutex.new()
	func _log_error(function: String, file: String, line: int, code: String, rationale: String, _notify: bool, kind: int, _trace: Array[ScriptBacktrace]) -> void:
		if kind == Logger.ERROR_TYPE_WARNING: return
		guard.lock()
		if errors.size() < 16: errors.append({"function":function,"file":file,"line":line,"code":code,"rationale":rationale})
		guard.unlock()
var logger := ErrorLog.new()
var session: Node
var role := ""
var profile := ""
var run_id := ""
var evidence := ""
var began := 0
var quit_started := 0
var finished := false
var peer_id := 0
var checks: Array = []
var actions: Array = []
var keys: Array = []
var fixtures: Array = []
var notices: Array = []
var last_campaign: Dictionary = {}
var baseline_story: Dictionary = {}
var baseline_personal: Dictionary = {}
var guest_mechanism_baseline: Dictionary = {}

func _initialize() -> void:
	OS.add_logger(logger)
	_run.call_deferred()

func _process(_delta: float) -> bool:
	if finished:
		if quit_started > 0 and Time.get_ticks_msec()-quit_started > 8000:
			print("GUEST_MECHANISMS_QUIT_WATCHDOG_FAILED original Session._quit did not finish")
			quit(1)
	elif began > 0 and Time.get_ticks_msec()-began > 90000:
		_check(false,"90s monotonic peer bound")
		_finish()
	return false

func _check(ok: bool, label: String, actual: Variant = null) -> bool:
	checks.append({"passed":ok,"label":label,"actual":actual.duplicate(true) if actual is Array or actual is Dictionary else actual})
	return ok

func _write(name: String, data: Dictionary) -> void:
	var target: String = evidence.path_join(name+".json")
	if FileAccess.file_exists(target) or FileAccess.file_exists(target+".pending"):
		_check(false,"new evidence only",name); return
	var file := FileAccess.open(target+".pending",FileAccess.WRITE)
	if file == null: _check(false,"evidence open",name); return
	file.store_string(JSON.stringify(data,"\t")); file.close()
	_check(DirAccess.rename_absolute(target+".pending",target)==OK,"small atomic evidence",name)

func _read(name: String) -> Dictionary:
	var target: String = evidence.path_join(name+".json")
	if not FileAccess.file_exists(target) or FileAccess.get_file_as_bytes(target).size()>32768: return {}
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(target))
	return data if data is Dictionary else {}

func _tick() -> bool:
	await physics_frame
	await process_frame
	return not finished

func _wait_file(name: String) -> Dictionary:
	var data: Dictionary = _read(name)
	while data.is_empty():
		if not await _tick(): return {}
		data = _read(name)
	return data

func _run() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--qa-profile="): profile=arg.trim_prefix("--qa-profile=")
		if arg.begins_with("--mechanism-role="): role=arg.trim_prefix("--mechanism-role=")
		if arg.begins_with("--mechanism-run="): run_id=arg.trim_prefix("--mechanism-run=")
		if arg.begins_with("--mechanism-evidence="): evidence=arg.trim_prefix("--mechanism-evidence=").replace("\\","/")
	var managed: String = OS.get_environment("LOW_ALTITUDE_DEV_HOME").replace("\\","/").trim_suffix("/")
	if role not in ["host","guest"] or managed.is_empty() or run_id.is_empty() or run_id!=run_id.validate_filename() or profile!="qa_guest_mechanisms_"+role+"_"+run_id or DirAccess.dir_exists_absolute("user://profiles_v3/"+profile) or evidence!=managed+"/evidence/guest-mechanisms-"+run_id or not DirAccess.dir_exists_absolute(evidence) or FileAccess.file_exists(evidence.path_join(role+".json")):
		print("GUEST_MECHANISMS_ARGUMENTS_REJECTED"); quit(2); return
	began=Time.get_ticks_msec()
	session=MAIN.instantiate(); root.add_child(session)
	var opportunity := ReadingOpportunity.new()
	if not _check(opportunity.setup(session),"QA current-opportunity wrapper loads original definitions"): _finish(); return
	session.story=opportunity
	if not _check(session.profile_ready and session.store.root_path=="user://profiles_v3/"+profile and session.start_flight(role,"127.0.0.1"),"original MAIN fresh private profile/ENet"): _finish(); return
	if not _check(session.network.PROTOCOL==27 and ProjectSettings.get_setting("application/config/version")=="3.0.0-dev.84","current84/LAN27 resources"): _finish(); return
	session.inputs.test_enabled=true
	session.inputs.test_frame={"axes":{},"held":["brake"],"edges":[]}
	session.network.action_received.connect(_action)
	session.network.event_received.connect(_event)
	if role=="host":
		if not _check(session._load_region("F2") and session.region_id=="F2","explicit QA region fixture via original load, no travel claim"): _finish(); return
		fixtures.append({"kind":"QA_region_entry_not_natural_travel","region":"F2"})
		_write("host-started",{"ready":true,"protocol":session.network.PROTOCOL})
		await _host()
	else: await _guest()
	if not finished: _finish()

func _baseline() -> void:
	baseline_story=session.story.state.duplicate(true)
	baseline_personal=session.store.snapshot().personal.duplicate(true)
	fixtures.append({"kind":"current_targets_only_F2_paired_records_opportunity","state_or_receipts_written":false})
	_check(session.story.director.validate_state(baseline_story).get("ok",false) and baseline_story.get("completed",[]).is_empty(),"original fresh Director state remains legal/empty")

func _action(sender: int, verb: String, payload: Dictionary) -> void:
	if role!="host" or verb not in ["ability","explore"] or actions.size()>=12: return
	var id: String = str(payload.get("target_id",""))
	var at: Vector3 = session.entities.get(id,{}).get("position",Vector3.INF)
	if session.story.markers.has(id): at=session.world.to_global(_v(session.story.markers[id].position))
	actions.append({"sender":sender,"verb":verb,"target":id,"ability":payload.get("ability",""),"distance":session.players[sender].global_position.distance_to(at) if at.is_finite() else -1.0,"host_angle":session.entities.get(id,{}).get("angle"),"sequence":session.network.last_action.get(sender)})

func _event(event: Dictionary) -> void:
	if event.get("kind")=="notice" and notices.size()<12: notices.append(str(event.get("text","")))
	if event.get("kind")=="campaign_state" and event.get("region")=="F2" and int(event.get("serial",-1))==session.campaign._applied_serial:
		last_campaign=event.duplicate(true) # Genuine host authority RPC, never a positive file replay.

static func _v(value: Array) -> Vector3:
	return Vector3(value[0],value[1],value[2])

func _clear(at: Vector3, body: FlightBodyV2) -> bool:
	if not Regions.contains("F2",at): return false
	var envelope: CollisionShape3D = body.get_node("Envelope")
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape=envelope.shape; query.transform=Transform3D(Basis.IDENTITY,at)*envelope.transform
	query.collision_mask=1|2|4|8|32; query.exclude=[body.get_rid()]
	return session.world.get_world_3d().direct_space_state.intersect_shape(query,1).is_empty()

func _place(target: String, near: bool) -> Dictionary:
	var body: FlightBodyV2 = session.players[peer_id]
	var point: Vector3 = session.entities.get(target,{}).get("position",Vector3.INF)
	if session.story.markers.has(target): point=session.world.to_global(_v(session.story.markers[target].position))
	var offsets: Array = [Vector3(0,2.7,0),Vector3(2.8,1,0),Vector3(-2.8,1,0),Vector3(0,1,2.8)] if near else [Vector3(-20,2,0),Vector3(0,2,20),Vector3(0,2,-20)]
	for offset: Vector3 in offsets:
		var at: Vector3 = point+offset
		if not _clear(at,body) or not session._line_clear(at,point,body.get_rid(),target): continue
		if near and at.distance_to(point)>3.0: continue
		body.freeze=true; body.set_physics_process(false)
		body.global_transform=Transform3D(Basis.IDENTITY,at); body.force_update_transform()
		PhysicsServer3D.body_set_state(body.get_rid(),PhysicsServer3D.BODY_STATE_TRANSFORM,body.global_transform)
		body.linear_velocity=Vector3.ZERO; body.angular_velocity=Vector3.ZERO; body.hold_height=at.y
		var fixture: Dictionary = {"kind":"native_clear_PLAYER_pose_not_flown_no_mechanism_edit","target":target,"near":near,"position":[at.x,at.y,at.z],"distance":at.distance_to(point),"player":peer_id}
		fixtures.append(fixture); return fixture
	return {}

func _place_and_signal(name: String, target: String, near: bool) -> bool:
	var fixture: Dictionary = _place(target,near)
	if not _check(not fixture.is_empty(),"native clear PLAYER fixture "+name,fixture): return false
	for unused in 3:
		if not await _tick(): return false
	while float(session.cooldowns.get(peer_id,0.0))>0.0:
		if not await _tick(): return false
	_write(name,fixture); return true

func _wait_pose(name: String) -> bool:
	var fixture: Dictionary = await _wait_file(name)
	if fixture.is_empty(): return false
	while session.players[peer_id].global_position.distance_to(_v(fixture.position))>0.5:
		if not await _tick(): return false
	return true

func _key(code: Key) -> bool:
	var event := InputEventKey.new()
	event.pressed=true; event.physical_keycode=code; event.keycode=code
	session._unhandled_input(event) # Same original key handler used by normal observers, not OS keyboard evidence.
	keys.append({"code":int(code),"path":"original Session._unhandled_input","frame":Engine.get_physics_frames()})
	for unused in 4:
		if not await _tick(): return false
	return true

func _lock(id: String) -> bool:
	for unused in 48:
		if str(session.locks.get(peer_id,""))==id: return true
		if not await _key(KEY_TAB): return false
	return _check(false,"original Tab finds real target",id)

func _host() -> void:
	while session.network.guests.size()!=1 or session.players.size()!=2:
		if not await _tick(): return
	peer_id=int(session.network.guests.keys()[0]); _baseline()
	if not _check(session.world.objects.has(BYPASS) and is_equal_approx(float(session.entities[MIRROR].angle),deg_to_rad(15)) and is_equal_approx(float(session.entities[BYPASS].angle),deg_to_rad(-15)),"real84 dual-mirror initial entities"): return
	if not await _place_and_signal("low-ready",LOW,true): return
	while not session.campaign.mechanisms.persistent_state().readings.has(LOW):
		if not await _tick(): return
	var reading_before: Dictionary = session.campaign.mechanisms.persistent_state().readings.duplicate(true)
	if not _check(session.campaign.navigation_target(PAIR)==HIGH,"Host actual first G advances physical reading navigation",reading_before): return
	_write("low-accepted",{"readings":reading_before,"navigation":session.campaign.navigation_target(PAIR)})
	if (await _wait_file("guest-repeat-sent")).is_empty(): return
	while actions.filter(func(row: Dictionary): return row.verb=="explore").size()<2:
		if not await _tick(): return
	for unused in 8:
		if not await _tick(): return
	_check(session.campaign.mechanisms.persistent_state().readings==reading_before,"repeated real Guest G creates no new read serial or credit")
	if not await _place_and_signal("far-ready",BYPASS,false): return
	var before_rejected: int = int(session.stats.rejected_abilities)
	var before_angle: float = float(session.entities[BYPASS].angle)
	while int(session.stats.rejected_abilities)==before_rejected:
		if not await _tick(): return
	_check(is_equal_approx(float(session.entities[BYPASS].angle),before_angle) and int(session.stats.rejected_abilities)==before_rejected+1,"Host Rules reject real far Guest light with no angle change")
	_write("far-rejected",{"angle":float(session.entities[BYPASS].angle),"rejected":int(session.stats.rejected_abilities)})
	if (await _wait_file("guest-far-done")).is_empty(): return
	if not await _place_and_signal("bypass-ready",BYPASS,true): return
	while not is_equal_approx(float(session.entities[BYPASS].angle),deg_to_rad(15)):
		if not await _tick(): return
	_check(int(session.stats.abilities)==1,"near Guest original light accepted exactly once")
	_write("bypass-accepted",{"angle":float(session.entities[BYPASS].angle)})
	if (await _wait_file("guest-bypass-done")).is_empty(): return
	if not await _place_and_signal("primary-ready",MIRROR,true): return
	while not is_equal_approx(float(session.entities[MIRROR].angle),deg_to_rad(45)) or float(session.cooldowns.get(peer_id,0.0))>0.0:
		if not await _tick(): return
	_write("primary-second-ready",{"angle":float(session.entities[MIRROR].angle),"cooldown":float(session.cooldowns.get(peer_id,0.0))})
	while not is_equal_approx(float(session.entities[MIRROR].angle),deg_to_rad(75)) or not _three_spans(View.wire(session.campaign.mechanisms.view_state())):
		if not await _tick(): return
	_check(int(session.stats.abilities)==3,"three original Guest light successes, no direct angle injection")
	var wire: Dictionary = View.wire(session.campaign.mechanisms.view_state())
	_write("three-spans",{"wire":wire,"primary_angle":float(session.entities[MIRROR].angle),"bypass_angle":float(session.entities[BYPASS].angle),"epoch":session.campaign.epoch,"actions":actions})
	if (await _wait_file("guest-complete")).is_empty(): return
	_check(actions.size()==6 and actions.all(func(row: Dictionary): return int(row.sender)==peer_id),"all two G/four F actions arrived through real ENet sender",actions)
	_write("host-complete",{"passed":checks.all(func(row: Dictionary): return row.passed)})
	while not _read("guest").has("passed") or session.network.guests.has(peer_id):
		if not await _tick(): return

func _guest() -> void:
	while session.region_id!="F2" or session.received_sequence<0 or not session._facilities_ready() or not session.story.ready or not session.players.has(session.network.local_id()):
		if not await _tick(): return
	peer_id=session.network.local_id()
	session.players[peer_id].freeze=true; session.players[peer_id].set_physics_process(false)
	_baseline(); guest_mechanism_baseline=session.campaign.mechanisms.persistent_state()
	if not await _wait_pose("low-ready"): return
	if not _check(session.campaign.navigation_target(PAIR)==LOW and session.story.nearest(session.players[peer_id].global_position)==LOW,"Guest initially points at actual low record"): return
	if not await _key(KEY_G): return
	while session.campaign.navigation_target(PAIR)!=HIGH:
		if not await _tick(): return
	if (await _wait_file("low-accepted")).is_empty(): return
	if not _check(last_campaign.get("paired_record_reads",[])==[LOW],"navigation changed only after genuine Host authority campaign event",last_campaign.get("paired_record_reads")): return
	_negative_packets()
	if not await _key(KEY_G): return
	_write("guest-repeat-sent",{"sent":true})
	if not await _wait_pose("far-ready"): return
	if not await _key(KEY_4) or not await _lock(BYPASS) or not _check(session.selected_ability=="light","original4 selects light"): return
	if not await _key(KEY_F): return
	if (await _wait_file("far-rejected")).is_empty(): return
	while "距离太远，请靠近目标" not in notices:
		if not await _tick(): return
	_check(is_equal_approx(float(session.entities[BYPASS].angle),deg_to_rad(-15)),"Guest far rejection retains initial real mirror angle",notices)
	_write("guest-far-done",{"passed":true})
	if not await _wait_pose("bypass-ready"): return
	if not await _key(KEY_F): return
	if (await _wait_file("bypass-accepted")).is_empty(): return
	if not await _wait_angle(BYPASS,15): return
	_write("guest-bypass-done",{"passed":true})
	if not await _wait_pose("primary-ready") or not await _lock(MIRROR): return
	if not await _key(KEY_F) or not await _wait_angle(MIRROR,45): return
	if (await _wait_file("primary-second-ready")).is_empty(): return
	if not await _key(KEY_F) or not await _wait_angle(MIRROR,75): return
	var expected: Dictionary = await _wait_file("three-spans")
	if expected.is_empty(): return
	while not _wire_equal(last_campaign.get("mechanism_view",{}),expected.wire):
		if not await _tick(): return
	_check(_three_spans(last_campaign.mechanism_view) and _view_geometry_matches(last_campaign.mechanism_view),"genuine Host three-span wire and actual Guest view mesh geometry match",last_campaign.mechanism_view)
	_check(not session.owns_world and not session.campaign.mechanisms.authority and session.campaign.mechanisms.persistent_state()==guest_mechanism_baseline,"Guest never advances or restores authoritative F2 mechanism history",session.campaign.mechanisms.persistent_state())
	_write("guest-complete",{"passed":true,"event_epoch":last_campaign.epoch,"event_serial":last_campaign.serial})
	await _wait_file("host-complete")

func _wait_angle(id: String, degrees: float) -> bool:
	var angle: float = deg_to_rad(degrees)
	var body: PhysicsBody3D = session.world.objects[id]
	var native: Variant = PhysicsServer3D.body_get_state(body.get_rid(),PhysicsServer3D.BODY_STATE_TRANSFORM)
	while not is_equal_approx(float(session.entities[id].angle),angle) or absf(wrapf(body.rotation.y-angle,-PI,PI))>0.0001 or not native is Transform3D or not native.is_equal_approx(body.global_transform):
		if not await _tick(): return false
		native=PhysicsServer3D.body_get_state(body.get_rid(),PhysicsServer3D.BODY_STATE_TRANSFORM)
	return _check(true,"real Guest entity/Node/native collider angle "+id+"="+str(degrees),{"entity":float(session.entities[id].angle),"body":body.rotation.y,"native_matches_node":native.is_equal_approx(body.global_transform)})

func _negative_packets() -> void:
	var before_serial: int = session.campaign._applied_serial
	var original: Dictionary = last_campaign.duplicate(true)
	var candidates: Array = []
	var packet: Dictionary = original.duplicate(true); candidates.append({"kind":"exact_repeat","packet":packet})
	packet=original.duplicate(true); packet.serial=before_serial-1; packet.paired_record_reads=[]; candidates.append({"kind":"old_serial","packet":packet})
	packet=original.duplicate(true); packet.serial=before_serial+100; packet.epoch=int(original.epoch)+1; packet.paired_record_reads=[]; candidates.append({"kind":"wrong_epoch","packet":packet})
	packet=original.duplicate(true); packet.serial=before_serial+100; packet.paired_record_reads=["F2:not_a_record"]; candidates.append({"kind":"bad_read_id","packet":packet})
	packet=original.duplicate(true); packet.serial=before_serial+100; packet.paired_record_reads=[LOW,LOW]; candidates.append({"kind":"duplicate_read_id","packet":packet})
	for candidate: Dictionary in candidates:
		session.campaign.receive(candidate.packet) # NEGATIVE validator probes only; no positive packet fabrication.
		_check(session.campaign._applied_serial==before_serial and session.campaign.navigation_target(PAIR)==HIGH and session.campaign.mechanisms.persistent_state()==guest_mechanism_baseline,"negative direct receive cannot poison navigation: "+str(candidate.kind))

static func _three_spans(wire: Dictionary) -> bool:
	return View.valid_wire(wire) and wire.beam_valid and wire.beam_segments.size()==3

static func _wire_equal(a: Dictionary, b: Dictionary) -> bool:
	if not View.valid_wire(a) or not View.valid_wire(b) or a.beam_valid!=b.beam_valid or a.beam_segments.size()!=b.beam_segments.size(): return false
	for index in a.beam_segments.size():
		for endpoint in 2:
			for axis in 3:
				if float(a.beam_segments[index][endpoint][axis])!=float(b.beam_segments[index][endpoint][axis]): return false
	return true

func _view_geometry_matches(wire: Dictionary) -> bool:
	var view: Node3D = session.world.campaign_mechanism_view
	var count := 0
	for beam: MeshInstance3D in view._beams:
		if beam.visible: count+=1
	if count!=3: return false
	for index in 3:
		var a: Vector3 = _v(wire.beam_segments[index][0])*.001
		var b: Vector3 = _v(wire.beam_segments[index][1])*.001
		var beam: MeshInstance3D = view._beams[index]
		if beam.global_position.distance_to((a+b)*.5)>.003 or absf(float(view._beam_shapes[index].height)-a.distance_to(b))>.003: return false
		if absf(beam.global_basis.y.normalized().dot((b-a).normalized()))<.9999 or beam.material_override!=view._valid_material: return false
	return true

func _finish() -> void:
	if finished: return
	finished=true
	if is_instance_valid(session) and not baseline_story.is_empty():
		_check(session.story.state==baseline_story and session.store.snapshot().personal==baseline_personal,"Story/completed/choices/receipts/personal rewards remain exactly unchanged; normal environment save generations excluded")
	var failures: Array = checks.filter(func(row: Dictionary): return not row.passed)
	_write(role,{"passed":failures.is_empty() and logger.errors.is_empty(),"version":ProjectSettings.get_setting("application/config/version"),"protocol":session.network.PROTOCOL if is_instance_valid(session) else -1,"role":role,"profile":profile,"run_id":run_id,"checks":checks,"failures":failures,"keys":keys,"host_actions":actions,"fixtures":fixtures,"notices":notices,"engine_errors":logger.errors,"seconds":float(Time.get_ticks_msec()-began)/1000.0,"scope":"Two fresh MAIN peers, actual ENet127.0.0.1, explicit F2/current-opportunity/clear-player-pose fixtures. Positive reads/angles/view only original Guest key handler -> reliable action -> Host Rules/native bodies -> original Host broadcast. Invalid receive clones are negative checks only. Not natural campaign, physical LAN, graphics or OS keyboard evidence.","original_quit_requested":is_instance_valid(session)})
	quit_started=Time.get_ticks_msec()
	if is_instance_valid(session): session._quit()
	else: quit(1)
