extends SceneTree
## One fresh private MAIN. Director prefixes/record/endings are RULE fixtures.
## Only F3 listen and repeat NPC G are actual interactions; no Boss/record win.
const MAIN = preload("res://scenes/v3/main.tscn")
const Replies = preload("res://scripts/v3/campaign/twin_postboss_revisits.gd")
const Store = preload("res://scripts/v3/core/twin_world_store.gd")
const NPC := "npc:lingyin"
const LISTEN := "F3:separate_network:listen"
const RECORD := "F3:mycelial_choir:record"
const FINAL := "F4:twin_vein_core:decision"
class ErrorLog extends Logger:
	var errors: Array = []
	func _log_error(fn: String,file: String,line: int,code: String,why: String,_notify: bool,kind: int,_trace: Array[ScriptBacktrace]) -> void:
		if kind!=Logger.ERROR_TYPE_WARNING: errors.append({"function":fn,"file":file,"line":line,"code":code,"why":why})
class Guard extends Node:
	var deadline: int
	var stop: Callable
	func _process(_delta: float) -> void:
		if Time.get_ticks_usec()>deadline: set_process(false); stop.call_deferred()
var session: Node
var guard: Guard
var logger := ErrorLog.new()
var checks: Array = []
var profile := ""
var output := ""
var finished := false
var complete := false
var started := 0

func _initialize() -> void:
	started=Time.get_ticks_usec()
	var args: Dictionary={}
	for arg: String in OS.get_cmdline_user_args():
		var key: String="profile" if arg.begins_with("--qa-profile=") else ("output" if arg.begins_with("--output=") else "")
		if key.is_empty() or args.has(key): quit(2); return
		args[key]=arg.get_slice("=",1)
	profile=str(args.get("profile","")); output=str(args.get("output",""))
	if args.size()!=2 or not profile.begins_with("qa_postboss67_") or profile.length()<15 or profile!=profile.validate_filename() or DirAccess.dir_exists_absolute("user://profiles_v3/"+profile) or FileAccess.file_exists("user://profiles_v3/"+profile) or not output.begins_with("res://artifacts/v3/postboss-validation67-") or ".." in output or FileAccess.file_exists(output) or DirAccess.dir_exists_absolute(output): quit(2); return
	DirAccess.make_dir_recursive_absolute(output)
	OS.add_logger(logger)
	guard=Guard.new(); guard.deadline=started+35000000
	guard.stop=func(): _check(false,"35 second monotonic private slice bound"); _finish()
	root.add_child.call_deferred(guard); _run.call_deferred()

func _run() -> void:
	session=MAIN.instantiate(); root.add_child(session)
	if not _check(session.profile_ready and session.start_flight("solo") and session._load_region("F3"),"fresh MAIN loads actual F3 before any rule fixture"): _finish(); return
	session.inputs.test_enabled=true; session.inputs.test_frame={"axes":{},"held":["brake"],"edges":[]}
	if not _seed(_prefix(LISTEN),"listen"): _finish(); return
	var actor: FlightBodyV2=session.players[1]
	var point: Vector3=session.story._point(session.story.markers[NPC])
	var pose := Transform3D(Basis.IDENTITY,point+Vector3(0,1.4,1.8))
	var envelope: CollisionShape3D=actor.get_node("Envelope")
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape=envelope.shape; query.transform=pose*envelope.transform
	query.exclude=[actor.get_rid()]; query.collision_mask=1|2|4|8|32; query.margin=.001
	if not _check(session.world.get_world_3d().direct_space_state.intersect_shape(query,1).is_empty(),"sole initial QA full-hull observation pose clear"): _finish(); return
	# Sole spatial fixture; all later movement is original Flight with brake input.
	actor.global_transform=pose; actor.force_update_transform()
	PhysicsServer3D.body_set_state(actor.get_rid(),PhysicsServer3D.BODY_STATE_TRANSFORM,pose)
	actor.linear_velocity=Vector3.ZERO; actor.angular_velocity=Vector3.ZERO
	actor.hold_height=pose.origin.y; actor.safe_position=pose.origin
	if not await _frames(4): return
	if not _check(session.story.nearest(actor.global_position)==NPC and session._line_clear(actor.global_position,point,actor.get_rid(),NPC),"ordinary nearest and actual LOS resolve same original NPC"): _finish(); return
	var expected: Array=[]
	for action: Dictionary in session.story.director.definitions().actions:
		for objective: Dictionary in action.objectives:
			if objective.id==LISTEN:
				for effect: Dictionary in objective.effects:
					if effect.type=="dialogue" and effect.character_id==NPC: expected.append_array(effect.lines)
	_g()
	if not await _frames(8): return
	var receipt: Dictionary={}
	for item: Dictionary in session.story.state.receipts.values():
		if item.objective_id==LISTEN: receipt=item
	if not _check(receipt.get("type")=="talk" and receipt.get("target_id")==NPC and _radio()==expected and session.interface.radio_speaker.text=="苓音 · 养护棚","actual G prioritizes current original talk, exact original lines only, named speaker",{"receipt":receipt,"radio":_radio()}): _finish(); return
	if not await _drain(): _finish(); return
	var before_record: Dictionary=_prefix(RECORD)
	if not _check(session.story.director.validate_state(before_record).ok and before_record.flags.get("F3:boss_stopped",false) and Replies.reply(before_record,"F3",NPC).is_empty(),"legal stopped-Boss rule prefix without record has no revisit"): _finish(); return
	if not _seed(_prefix(RECORD,true),"record_RULES_ONLY_NOT_ACTUAL_BOSS_OR_G_RECORD"): _finish(); return
	var preserved: Dictionary=_signature()
	var revisit: Dictionary=Replies.reply(session.story.state,"F3",NPC)
	if not _check(not revisit.is_empty(),"legal completed-record rules fixture permits local NPC revisit"): _finish(); return
	for repeat in 2:
		_g()
		if not await _frames(4): return
		if not _check(_radio()==revisit.lines and session.interface.radio_speaker.text=="苓音 · 养护棚","actual same-NPC G/repeat presents exact new lines",repeat): _finish(); return
		if not await _drain(): _finish(); return
		if not _check(_signature()==preserved,"repeat G adds no Story completion/choice/receipt/personal or guest reward"): _finish(); return
	var reader := Store.new(session.store.root_path)
	if not _check(reader.load_profile().ok and reader.snapshot().world.actions.opening==session.story.state,"fresh original Store retains exact fixture plus real talk state"): _finish(); return
	if not _f4_selectors(): _finish(); return
	complete=true; _finish()

func _prefix(stop: String, include: bool=false, ending: String="") -> Dictionary:
	var state: Dictionary=session.story.director.default_state()
	for action: Dictionary in session.story.director.definitions().actions:
		for objective: Dictionary in action.objectives:
			if objective.id==stop and not include: return state
			var match_event: Dictionary=objective.events[0]
			var option: String=ending if objective.id==FINAL and not ending.is_empty() else str(match_event.options[0])
			var applied: Dictionary=session.story.director.apply_event(state,{"id":"qa-revisit-rule:"+str(objective.id)+":"+ending,"type":match_event.type,"target_id":match_event.target_id,"option":option},{"is_authority":true,"validated":true,"region_id":action.region_id})
			if not applied.get("ok",false) or not applied.get("changed",false): return {}
			state=applied.state
			if objective.id==stop: return state
	return {}

func _seed(state: Dictionary, label: String) -> bool:
	if not _check(not state.is_empty() and session.story.director.validate_state(state).ok,"legal original Director prefix: "+label): return false
	var tx: Dictionary=session.store.commit({"id":"qa-revisit-fixture:"+label,"set":{"world.region_id":"F3","world.actions.opening":state,"world.completed_objectives":state.completed.duplicate()}})
	if not _check(tx.get("ok",false),"only private QA receives explicit rule-prefix fixture",tx): return false
	session.world_cache=session.store.snapshot(); session.consensus.set_world_revision(int(session.world_cache.world_revision)); session.story.load_world()
	return session.story.ready

func _f4_selectors() -> bool:
	var pending: Dictionary=_prefix(FINAL)
	if not _check(session.story.director.validate_state(pending).ok and pending.flags.get("F4:boss_stopped",false) and Replies.reply(pending,"F4","npc:guanzhi").is_empty(),"stopped Boss without saved decision cannot claim any ending"): return false
	var cues: Dictionary={"shared_stewardship":"共同照料","industrial_lifeline":"应急与生产","living_vein":"先接回活脉"}
	for option: String in cues:
		var state: Dictionary=_prefix(FINAL,true,option)
		var before: PackedByteArray=var_to_bytes(state)
		var reply: Dictionary=Replies.reply(state,"F4","npc:guanzhi")
		if not _check(session.story.director.validate_state(state).ok and reply.get("character_id")=="npc:guanzhi" and reply.get("lines",[]).size()==2 and reply.lines[0].contains(cues[option]) and before==var_to_bytes(state),"exact ending RULE fixture, pure reply, original state unchanged: "+option): return false
	return true

func _signature() -> Dictionary:
	var saved: Dictionary=session.store.snapshot()
	return {"opening":saved.world.actions.opening,"objectives":saved.world.completed_objectives,"personal":saved.personal,"guest_received":saved.ledger.guest_received,"guest_outbox":saved.ledger.guest_outbox}

func _radio() -> Array:
	var lines: Array=[session.interface.radio_text.text] if session.interface.radio.visible else []
	for line: Dictionary in session.interface.radio_queue: lines.append(str(line.text))
	return lines

func _g() -> void:
	var key := InputEventKey.new()
	key.physical_keycode=KEY_G; key.keycode=KEY_G; key.pressed=true; session._unhandled_input(key)
	key.pressed=false; session._unhandled_input(key)

func _drain() -> bool:
	for unused in 12:
		if not session.interface.radio.visible: return _check(session.interface.radio_queue.is_empty(),"original G/advance_dialogue drains whole queue")
		_g()
		if not await _frames(1): return false
	return _check(false,"dialogue failed to close normally")

func _frames(count: int) -> bool:
	for unused in count:
		await physics_frame; await process_frame
		if finished: return false
	return true

func _check(ok: bool,label: String,actual: Variant=null) -> bool:
	checks.append({"passed":ok,"label":label,"actual":actual}); return ok

func _finish() -> void:
	if finished: return
	finished=true; guard.set_process(false)
	var audio: Dictionary={"ready":true}
	if is_instance_valid(session):
		session.active=false; session.environment_save_gate.cancel("private_revisit_fixture_teardown"); session.audio.shutdown(); session.network.close()
		var deadline: int=Time.get_ticks_usec()+1000000
		audio=session.audio.shutdown_status()
		while not audio.ready and Time.get_ticks_usec()<deadline: await process_frame; audio=session.audio.shutdown_status()
		session.free()
	await process_frame
	var failures: Array=checks.filter(func(item: Dictionary): return not item.passed)
	var result: Dictionary={"complete":complete and failures.is_empty() and logger.errors.is_empty() and audio.ready,"checks":checks,"failures":failures,"engine_errors":logger.errors,"audio":audio,"seconds":float(Time.get_ticks_usec()-started)/1000000.0,"scope":"Fresh private MAIN F3 and one initial clear aircraft pose. Actual nearby LOS/G completes original NPC listen and repeated G/radio displays revisit. F3 record/Boss and three F4 endings are explicitly legal Director RULE fixtures, not natural progress, physical battle/record G or LAN. Revisit Story/choices/receipts/personal and guest rewards unchanged; ordinary environment save generation may change. Terminal fixture audio cleanup, no normal save/reload lifecycle claim."}
	FileAccess.open(output+"/result.json",FileAccess.WRITE).store_string(JSON.stringify(result,"\t"))
	print("POSTBOSS_REVISITS67_RESULT "+JSON.stringify({"complete":result.complete,"checks":checks.size(),"failures":failures,"engine_errors":logger.errors}))
	quit(0 if result.complete else 1)
