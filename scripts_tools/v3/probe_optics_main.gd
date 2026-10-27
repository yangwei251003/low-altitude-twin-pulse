extends SceneTree
## Root-run original MAIN observer. No OS input/window API or manual simulation.
const MAIN = preload("res://scenes/v3/main.tscn")
const Store = preload("res://scripts/v3/core/twin_world_store.gd")
const Regions = preload("res://scripts/v3/world/twin_region_catalog.gd")
const PathSolver = preload("res://scripts/v3/campaign/twin_optical_path.gd")
const Binding = preload("res://scripts/v3/qa/twin_source_binding.gd")
const Network = preload("res://scripts/v3/twin_network.gd")
const M1 := "F2:clock_mirror"
const M2 := "F2:clock_mirror_bypass"
const RECEIVER := "F2:clock_receiver"
const AT := Vector3(17,14,7)
const PNG_LIMIT := 4*1024*1024
class ErrorLogger extends Logger:
	var guard := Mutex.new()
	var errors: Array = []
	func _log_error(function: String,file: String,line: int,code: String,rationale: String,_notify: bool,kind: int,_trace: Array[ScriptBacktrace]) -> void:
		if kind == Logger.ERROR_TYPE_WARNING: return
		guard.lock()
		errors.append({"function":function,"file":file,"line":line,"code":code,"rationale":rationale})
		guard.unlock()
var session: Node
var obstacle: StaticBody3D
var logger := ErrorLogger.new()
var profile := ""
var output := ""
var expected_version := ""
var capture := false
var png_bytes := 0
var finished := false
var expired := false
var began := 0
var report := {"checks":[],"observations":[],"poses":[],"ability_actions":[],"images":[],"fixture_scope":"Original solo MAIN; explicit F2 area load and full-hull-clear frozen PLAYER pose, two temporary opaque/scout-layer obstacle fixtures, temporary receiver-back pose while normally paused. Host lock/ability goes through original Network/Rules. No Story prefix, task/reward/fact/HP/clock/thermal authoring. Fresh SaveGate/fresh MAIN restore precedes one explicit new-private legacy missing-entity Store fixture. No natural travel/flight, physical controller, human comfort or LAN proof; graphical evidence only when actual viewport PNGs exist. QA terminal teardown is not normal player quit evidence."}
func _initialize() -> void:
	OS.add_logger(logger)
	_run.call_deferred()
func _run() -> void:
	if not _arguments():
		print("OPTICS_MAIN_ARGUMENTS_REJECTED")
		quit(2)
		return
	began = Time.get_ticks_msec()
	report.merge({"profile":profile,"version":ProjectSettings.get_setting("application/config/version"),"protocol":Network.PROTOCOL,"executable":OS.get_executable_path(),"engine_arguments":Array(OS.get_cmdline_args()),"display_server":DisplayServer.get_name(),"direct_release_exe_execution":false,"capture_requested":capture})
	create_timer(65.0).timeout.connect(func():
		if not finished:
			expired = true
			_check(false,"65 second original MAIN probe deadline"))
	root.size = Vector2i(1280,720)
	root.content_scale_size = Vector2i(1280,720)
	var ok: bool = _check(str(report.version)==expected_version,"actual project/pack version equals explicit expected version")
	if ok: ok = await _exercise()
	if not ok and report.checks.all(func(row: Dictionary): return row.passed): _check(false,"probe did not reach its real terminal boundary")
	await _finish(ok)
func _arguments() -> bool:
	var seen: Dictionary = {}
	for arg: String in OS.get_cmdline_user_args():
		var key := ""
		var value := ""
		for pair: Array in [["--qa-profile=","profile"],["--probe-output=","output"],["--probe-expect-version=","version"]]:
			if arg.begins_with(pair[0]): key=pair[1]; value=arg.trim_prefix(pair[0]); break
		if arg=="--probe-capture-views": key="capture"; value="true"
		if key.is_empty() or value.is_empty() or seen.has(key): return false
		seen[key]=value
	if not seen.has_all(["profile","output","version"]): return false
	profile = str(seen.profile)
	output = str(seen.output).replace("\\","/").trim_suffix("/")
	expected_version = str(seen.version)
	capture = seen.has("capture")
	if not profile.begins_with("qa_optics84_") or profile.length()>96 or profile!=profile.validate_filename() or DirAccess.dir_exists_absolute("user://profiles_v3/"+profile): return false
	if capture and DisplayServer.get_name()=="headless": return false
	if not output.is_absolute_path() or "://" in output or ".." in output or "\n" in output or "\r" in output or not output.get_file().begins_with("optics-probe-") or DirAccess.dir_exists_absolute(output) or FileAccess.file_exists(output): return false
	var roots: Dictionary = Binding._roots()
	if roots.is_empty() or not Binding._approved(output+"/result.json",roots,false): return false
	return DirAccess.make_dir_recursive_absolute(output)==OK
func _exercise() -> bool:
	if not await _open(): return false
	var protected: Dictionary = _protected()
	var initial: Dictionary = session.store.snapshot()
	report["identity"]={"profile_id":initial.profile_id,"lineage_id":initial.lineage_id,"initial_generation":initial.generation}
	if not _check(protected.story.get("completed",[]).is_empty() and session.entities.has(M2) and is_equal_approx(float(session.entities[M1].angle),deg_to_rad(15)) and is_equal_approx(float(session.entities[M2].angle),deg_to_rad(-15)),"fresh original F2 factory has unchanged first angle and real new adjustable mirror"): return false
	if not await _expect(false,-1,"initial physical route unaligned"): return false
	if not await _light(M1) or not await _expect(true,2,"original first mirror45 single path"): return false
	if not await _capture("single",2): return false
	if not await _light(M1) or not await _expect(false,-1,"first75 with second-15 remains invalid"): return false
	if not await _light(M2) or not await _expect(true,3,"actual first75 second15 three-segment route"): return false
	if not await _capture("dual",3): return false
	if not await _blocked(1,2,"opaque layer1 on outgoing second leg"): return false
	if not await _blocked(4,1,"scout layer4 on intermediate leg"): return false
	if not await _pause(true): return false
	var paused: Dictionary = session.campaign.mechanisms.persistent_state()
	if not await _frames(12): return false
	if not _check(session.campaign.mechanisms.persistent_state()==paused,"ordinary common pause leaves complete mechanism state/tick unchanged"): return false
	if not await _receiver_back(): return false
	if not _check(session.campaign.mechanisms.persistent_state()==paused,"paused receiver fixture does not author mechanism state/history"): return false
	if not await _pause(false): return false
	if not await _place() or not await _expect(true,3,"original resume recomputes unaltered three-segment path"): return false
	if not await _light(M2) or not await _expect(false,-1,"original ability turns second15 to45 and breaks route"): return false
	if not _check(_protected()==protected and not session.inputs.test_enabled and not session.boss_active,"all optical actions leave Story/choices/rewards/receipts unchanged without test input or Boss start"): return false
	var expected_angles: Array = [float(session.entities[M1].angle),float(session.entities[M2].angle)]
	var saved: Dictionary = await _save()
	if saved.is_empty(): return false
	report["ordinary_save"]=_save_summary(saved)
	var saved_mechanisms: Dictionary = saved.world.environment.campaign_F2.mechanisms.duplicate(true)
	await _retire()
	if expired or not await _open(): return false
	var identity_ok: bool = session.store.snapshot().profile_id==initial.profile_id and session.store.snapshot().lineage_id==initial.lineage_id
	if not _check(identity_ok and _angle_matches(M1,expected_angles[0]) and _angle_matches(M2,expected_angles[1]),"fresh original MAIN restores normally saved mirror75/45 entity and actual native body poses with same UUID/lineage",_angles()): return false
	if not _check(session.store.matches_persisted_value(saved_mechanisms.histories,session.campaign.mechanisms.persistent_state().histories),"fresh original campaign adapter retains accepted legacy-shape optical history"): return false
	if not await _expect(false,-1,"fresh MAIN physically recalculates saved wrong second angle"): return false
	if not _check(_protected()==protected,"ordinary save/restart has no Story or reward advancement"): return false
	# Only now author the separately identified legacy INPUT fixture in this new QA profile.
	var before: Dictionary = session.store.snapshot()
	var legacy: Dictionary = before.world.entities.F2.duplicate(true)
	if not _check(legacy.has(M2),"normal SaveGate really persisted new entity before compatibility fixture"): return false
	legacy.erase(M2)
	session.active=false # Explicit QA terminal boundary: prevent recapture overwriting the legacy fixture.
	session.environment_save_gate.cancel("qa_optics_legacy_boundary")
	var tx_id := "qa-optics84-legacy-missing-bypass"
	var committed: Dictionary = session.store.commit({"id":tx_id,"set":{"world.entities.F2":legacy}})
	var after: Dictionary = session.store.snapshot()
	report["legacy_compatibility_input"]={"transaction_id":tx_id,"only_authored_path":"world.entities.F2","only_removed_entity":M2,"fixture_not_natural_old_save":true,"generation_before":before.generation,"generation_after":after.generation,"result":committed,"allowed_new_Store_ledger_receipt":tx_id}
	var same_other: Dictionary = after.duplicate(true)
	for key: String in ["generation","world_revision","saved_at_utc","ledger","branches"]: same_other[key]=before[key].duplicate(true) if before[key] is Dictionary or before[key] is Array else before[key]
	same_other.world.entities.F2=before.world.entities.F2.duplicate(true)
	var prior_commits: Dictionary = after.ledger.commits.duplicate(true)
	prior_commits.erase(tx_id)
	var ledger_ok: bool = after.ledger.guest_received==before.ledger.guest_received and after.ledger.guest_outbox==before.ledger.guest_outbox and prior_commits==before.ledger.commits and after.ledger.commits.has(tx_id)
	if not _check(committed.get("ok",false) and same_other==before and ledger_ok and session.store.matches_persisted_value(legacy,after.world.entities.F2),"explicit compatibility commit changes only missing-entity shape and named Store receipt, never Story/facts/history/personal rewards"): return false
	await _retire()
	if expired or not await _open(): return false
	if not _check(_angle_matches(M2,deg_to_rad(-15)) and _angle_matches(M1,expected_angles[0]),"fresh original factory overlays legacy entries but supplies absent mirror default-15 in actual bodies",_angles()): return false
	if not await _expect(false,-1,"legacy accepted fact is not substituted for live second-mirror validity"): return false
	return _check(_protected()==protected and session.store.matches_persisted_value(saved_mechanisms.histories,session.campaign.mechanisms.persistent_state().histories),"legacy input fixture/reopen preserves original Story/receipts/rewards and accepted history")
func _open() -> bool:
	session=MAIN.instantiate()
	root.add_child(session)
	if not _check(session.profile_ready and session.store.root_path=="user://profiles_v3/"+profile and session.start_flight("solo"),"original solo MAIN mounts exactly private probe profile"): return false
	if not _check(session._load_region("F2"),"explicit QA area fixture loads original F2 factory, without a Story prefix"): return false
	if not await _frames(12): return false
	if not _check(session.active and session.region_id=="F2" and session.players.has(1) and session.world.build_errors.is_empty() and session.campaign.supported() and not session.inputs.test_enabled,"original F2 World/actor/mechanisms and normal input are ready"): return false
	return await _place()
func _place() -> bool:
	var body: FlightBodyV2=session.players[1]
	var envelope:=body.get_node("Envelope") as CollisionShape3D
	var query:=PhysicsShapeQueryParameters3D.new()
	query.shape=envelope.shape
	query.transform=Transform3D(Basis.IDENTITY,AT)*envelope.transform
	query.collision_mask=1|2|4|8|32
	query.exclude=[body.get_rid()]
	var clear: bool=Regions.contains("F2",AT) and session.world.get_world_3d().direct_space_state.intersect_shape(query,1).is_empty()
	if not _check(clear,"explicit player observation pose has whole-envelope native clearance",AT): return false
	body.freeze=true
	body.global_transform=Transform3D(Basis.IDENTITY,AT)
	body.force_update_transform()
	PhysicsServer3D.body_set_state(body.get_rid(),PhysicsServer3D.BODY_STATE_TRANSFORM,body.global_transform)
	body.linear_velocity=Vector3.ZERO
	body.angular_velocity=Vector3.ZERO
	body.hold_height=AT.y
	report.poses.append({"at":AT,"kind":"explicit_QA_player_only_not_flown"})
	return await _frames(2)
func _light(id: String) -> bool:
	var deadline:=Time.get_ticks_msec()+2500
	while Time.get_ticks_msec()<deadline and float(session.cooldowns.get(1,0.0))>0:
		if not await _frames(1): return false
	var before: float=session.entities[id].angle
	var count: int=session.stats.abilities
	session.network.send_action("lock",{"target_id":id})
	session.network.send_action("ability",{"ability":"light","target_id":id,"mode":""})
	if not await _frames(3): return false
	var after: float=session.entities[id].angle
	report.ability_actions.append({"target":id,"before":before,"after":after,"stats_before":count,"stats_after":session.stats.abilities,"lock":session.locks.get(1,"")})
	return _check(session.stats.abilities==count+1 and is_equal_approx(wrapf(after-before,-PI,PI),PI/6.0),"original Host Network/Rules light action rotates actual "+id+" by30 degrees")
func _expect(valid: bool,count: int,label: String) -> bool:
	if not await _frames(14): return false
	var deadline:=Time.get_ticks_msec()+1200
	var view: Dictionary=session.campaign.mechanisms.view_state()
	while Time.get_ticks_msec()<deadline and (view.get("beam_valid")!=valid or count>=0 and view.get("beam_segments",[]).size()!=count):
		if not await _frames(1): return false
		view=session.campaign.mechanisms.view_state()
	report.observations.append({"label":label,"angles":_angles(),"view":view.duplicate(true),"tick":session.campaign.mechanisms.persistent_state().tick})
	return _check(view.get("beam_valid")==valid and (count<0 or view.get("beam_segments",[]).size()==count),label,view)
func _blocked(layer: int,leg: int,label: String) -> bool:
	var segments: Array=session.campaign.mechanisms.view_state().beam_segments
	if not _check(segments.size()==3,"three real segments exist before blocker fixture"): return false
	var a: Array=segments[leg][0]
	var b: Array=segments[leg][1]
	var at:=Vector3(float(a[0])+float(b[0]),float(a[1])+float(b[1]),float(a[2])+float(b[2]))*.0005
	obstacle=StaticBody3D.new()
	obstacle.name="QAOpticsBlocker"+str(layer)
	obstacle.collision_layer=layer
	obstacle.collision_mask=0
	var shape:=CollisionShape3D.new()
	var box:=BoxShape3D.new()
	box.size=Vector3.ONE*.6
	shape.shape=box
	obstacle.add_child(shape)
	session.world.add_child(obstacle)
	obstacle.global_position=at
	var ok: bool=await _expect(false,-1,label+" blocks nearest hit")
	obstacle.queue_free()
	obstacle=null
	if not ok: return false
	return await _expect(true,3,label+" removal restores route")
func _pause(value: bool) -> bool:
	session._request_pause() # Original solo Consensus path, no direct pause flag assignment.
	var deadline:=Time.get_ticks_msec()+2500
	while session.simulation_paused!=value and Time.get_ticks_msec()<deadline:
		if not await _frames(1): return false
	return _check(session.simulation_paused==value,"original common pause transition "+str(value),session.last_pause_result)
func _receiver_back() -> bool:
	var receiver: PhysicsBody3D=session.world.objects[RECEIVER]
	var original: Transform3D=receiver.global_transform
	receiver.rotation.y+=PI # Temporary physical receiver-only fixture while ordinary world is paused.
	receiver.force_update_transform()
	PhysicsServer3D.body_set_state(receiver.get_rid(),PhysicsServer3D.BODY_STATE_TRANSFORM,receiver.global_transform)
	if not await _frames(2): return false
	var actual: Dictionary=PathSolver.trace(session.world,session.world.objects["F2:clock_source"],session.world.objects[M1],receiver,session.world.objects[M2])
	var ok: bool=_check(not actual.valid and actual.code=="receiver_back_or_edge","real native receiver back face refuses the actual dual ray",actual)
	receiver.global_transform=original
	receiver.force_update_transform()
	PhysicsServer3D.body_set_state(receiver.get_rid(),PhysicsServer3D.BODY_STATE_TRANSFORM,original)
	if not await _frames(2): return false
	return ok
func _save() -> Dictionary:
	var rows: Array=[]
	var request: Dictionary=session.request_environment_save(func(row: Dictionary): rows.append(row.duplicate(true)))
	if not _check(request.get("ok",false),"original asynchronous SaveGate accepts request",request): return {}
	var deadline:=Time.get_ticks_msec()+3000
	while rows.is_empty() and Time.get_ticks_msec()<deadline:
		if not await _frames(1): return {}
	if not _check(not rows.is_empty() and rows[-1].get("ok",false) and rows[-1].get("completed",false),"original SaveGate completes actual private save",rows): return {}
	var reader=Store.new(session.store.root_path)
	var loaded: Dictionary=reader.load_profile()
	var saved: Dictionary=reader.snapshot()
	if not _check(loaded.get("ok",false) and not loaded.get("recovered",false) and saved.world.get("entities",{}).get("F2",{}).has(M2) and session.store.matches_persisted_value(session.campaign.mechanisms.persistent_state().histories,saved.world.get("environment",{}).get("campaign_F2",{}).get("mechanisms",{}).get("histories",{})),"independent original reader loads the real new-entity save and optical history",loaded): return {}
	return saved
func _save_summary(saved: Dictionary) -> Dictionary:
	return {"profile_id":saved.profile_id,"lineage_id":saved.lineage_id,"generation":saved.generation,"stored_current_region":saved.world.region_id,"area_fixture_region":"F2","F2_entities":saved.world.entities.F2.duplicate(true),"F2_mechanisms":saved.world.environment.campaign_F2.mechanisms.duplicate(true)}
func _protected() -> Dictionary:
	var saved: Dictionary=session.store.snapshot()
	return {"story":session.story.state.duplicate(true),"saved_story":saved.world.get("actions",{}).duplicate(true),"choices":saved.world.choices.duplicate(true),"objectives":saved.world.completed_objectives.duplicate(),"personal":saved.personal.duplicate(true),"received":saved.ledger.guest_received.duplicate(true),"outbox":saved.ledger.guest_outbox.duplicate(true)}
func _angle_matches(id: String,angle: float) -> bool:
	var body: PhysicsBody3D=session.world.objects[id]
	var native: Transform3D=PhysicsServer3D.body_get_state(body.get_rid(),PhysicsServer3D.BODY_STATE_TRANSFORM)
	return is_equal_approx(float(session.entities[id].angle),angle) and is_equal_approx(body.rotation.y,angle) and native.is_equal_approx(body.global_transform)
func _angles() -> Dictionary:
	return {"first":session.entities[M1].angle,"second":session.entities[M2].angle,"first_body":session.world.objects[M1].rotation.y,"second_body":session.world.objects[M2].rotation.y}
func _capture(label: String,count: int) -> bool:
	if not capture: return true
	if not await _frames(6): return false
	await RenderingServer.frame_post_draw
	var view: Dictionary=session.campaign.mechanisms.view_state()
	if not _check(view.beam_valid and view.beam_segments.size()==count,"actual viewport capture still corresponds to "+label+" optical state"): return false
	var image: Image=root.get_texture().get_image()
	if not _check(image!=null and not image.is_empty(),"actual native rendered viewport image exists"): return false
	var bytes: PackedByteArray=image.save_png_to_buffer()
	if not _check(bytes.size()>0 and png_bytes+bytes.size()<=PNG_LIMIT,"combined real PNG files stay within4MiB",bytes.size()): return false
	var path:=output+"/"+label+".png"
	var file:=FileAccess.open(path,FileAccess.WRITE)
	if not _check(file!=null,"new managed viewport PNG can be opened"): return false
	file.store_buffer(bytes)
	file.flush()
	var ok: bool=file.get_error()==OK
	file.close()
	png_bytes+=bytes.size()
	report.images.append({"path":path,"bytes":bytes.size(),"sha256":FileAccess.get_sha256(path),"view":view.duplicate(true),"actual_viewport":true})
	return _check(ok,"actual viewport PNG written for "+label)
func _frames(count: int) -> bool:
	for unused in count:
		await physics_frame
		await process_frame
		if expired or finished: return false
	return true
func _retire() -> void:
	if is_instance_valid(obstacle): obstacle.queue_free()
	obstacle=null
	if is_instance_valid(session):
		session.active=false # Explicit QA terminal cleanup, not ordinary Session._quit.
		session.environment_save_gate.cancel("qa_optics_teardown")
		session.network.close()
		session.audio.shutdown()
		var drain: Dictionary={}
		var deadline:=Time.get_ticks_msec()+1000
		while Time.get_ticks_msec()<deadline:
			drain=session.audio.shutdown_status()
			if drain.get("ready",false): break
			await process_frame
		_check(drain.get("ready",false),"bounded original audio shutdown drains before MAIN replacement",drain)
		if session.canal!=null: session.canal.clear()
		session.thermal_cargo.clear()
		session.free()
	session=null
	await process_frame
	await physics_frame
	await process_frame
func _check(ok: bool,label: String,actual: Variant=null) -> bool:
	report.checks.append({"passed":ok,"label":label,"actual":_plain(actual)})
	return ok
func _plain(value: Variant) -> Variant:
	if value is Vector3: return [value.x,value.y,value.z]
	if value is Array:
		var rows: Array=[]
		for item: Variant in value: rows.append(_plain(item))
		return rows
	if value is Dictionary:
		var rows: Dictionary={}
		for key: Variant in value: rows[str(key)]=_plain(value[key])
		return rows
	if value is Object or value is RID: return str(value)
	return value
func _finish(ok: bool) -> void:
	if finished: return
	finished=true
	await _retire()
	report["engine_errors"]=logger.errors
	report["failures"]=report.checks.filter(func(row: Dictionary): return not row.passed)
	report["complete"]=ok and not expired and report.failures.is_empty() and logger.errors.is_empty()
	report["png_total_bytes"]=png_bytes
	report["wall_seconds"]=float(Time.get_ticks_msec()-began)/1000.0
	var file:=FileAccess.open(output+"/result.json",FileAccess.WRITE)
	var written: bool=file!=null
	if file!=null:
		file.store_string(JSON.stringify(_plain(report),"\t",true,true))
		file.flush()
		written=file.get_error()==OK
	print("OPTICS_MAIN_PROBE_RESULT "+JSON.stringify(_plain(report)))
	quit(0 if report.complete and written else 1)
