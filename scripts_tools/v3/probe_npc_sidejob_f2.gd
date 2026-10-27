extends "res://scripts_tools/v3/probe_optics_main.gd"
## Root-run optional-job observer. Inherits original 65s wall bound, MAIN, light,
## native whole-hull mirror pose, SaveGate/fresh Reader and bounded audio teardown.
## Root source run: pinned editor --headless --path <project> --script <this absolute file> --
## --qa-profile=qa_optics84_sidejob86_<unique> --probe-output=<STATE/evidence/optics-probe-sidejob86-unique>
## --probe-expect-version=3.0.0-dev.86 ; outer owned-Job timeout80s. No capture flag.
## Release EXE external-script execution is NOT supported or claimed.
const Contact = preload("res://scripts/v3/ecology/twin_npc_contact.gd")
const JOB := "sidejob:F2:two_mirror_watch"
const NPC := "F2:lamp_01"
const REWARD := "npc_sidejob:F2:two_mirror_watch"
const BASE_PATH := "res://scripts_tools/v3/probe_optics_main.gd"
const BASE_SHA := "de233d2ae9dd9f8c3bf90fb3cf25144c322701d7d18c4a89c19b73994e4ea99d"
const REPORT_LIMIT := 64*1024
var contacts: Array=[]
var dialogues: Array=[]
var initial_protected: Dictionary={}
var input_before: Dictionary={}

func _arguments() -> bool:
	for arg: String in OS.get_cmdline_user_args():
		if arg=="--probe-capture-views": return false
		if arg.begins_with("--qa-profile=") and not arg.begins_with("--qa-profile=qa_optics84_sidejob86_"): return false
	return super._arguments() and expected_version=="3.0.0-dev.86"

func _exercise() -> bool:
	report["fixture_scope"]="Fresh private solo original MAIN loaded into F2, no Story prefix. Only full-hull-clear frozen PLAYER pose fixtures near mirrors/actual moving NPC; normal ecology/mechanism ticks. Native G uses Session -> Story.nearest -> Network explore -> Contact.prepare. Lock/light uses original Host Rules. One explicit existing Store.failure_point=before_write QA fault at ready claim, cleared on all normal/failed exits and teardown. No sidejob/fact/reward/ecology serial/tick/angle/time authoring, direct Model/contact invocation, OS input, screenshots, old profiles or clone/reset. Logic only, not natural flight/human/physical-controller/graphics/LAN proof. QA terminal teardown is not normal quit evidence."
	input_before=_input_hashes()
	report["input_sha256_before"]=input_before
	if not _check(input_before.get(BASE_PATH)==BASE_SHA,"exact original optics MAIN probe dependency is pinned"): return false
	if not await _open(): return false
	if not _check(session.get("sidejobs")!=null and session.sidejobs.error.is_empty(),"actual MAIN includes enabled optional Host module"): return false
	session.network.action_received.connect(func(peer: int,verb: String,payload: Dictionary):
		if verb=="explore" and contacts.size()<12: contacts.append({"peer":peer,"target":payload.get("target_id","")}))
	session.network.event_received.connect(func(event: Dictionary):
		if event.get("kind")=="dialogue" and dialogues.size()<12: dialogues.append(event.duplicate(true)))
	initial_protected=_protected()
	var initial: Dictionary=session.store.snapshot()
	report["identity"]={"profile_id":initial.profile_id,"lineage_id":initial.lineage_id,"initial_generation":initial.generation}
	if not _check(_row().is_empty() and initial_protected.story.get("completed",[]).is_empty(),"fresh profile starts without this job or completed Story prefix"): return false
	if not await _expect(false,-1,"initial real mirrors are unaligned"): return false
	if not await _contact("offer") or not await _close_dialogue(): return false
	if not _check(_row().is_empty() and _reward_count()==0,"first actual NPC dialogue only offers; no acceptance/reward"): return false
	if not await _contact("accept") or not await _close_dialogue(): return false
	if not _check(_row().get("status")=="active" and _reward_count()==0,"second native G contact accepts through original Gate/Store"): return false
	if not await _frames(8): return false
	if not _check(_row().get("status")=="active","unaligned physical route cannot become ready"): return false
	if not await _place() or not await _light(M1) or not await _expect(true,2,"original45 single mirror remains valid"): return false
	if not _check(_row().get("status")=="active" and _reward_count()==0,"valid original single mirror cannot satisfy two-mirror optional proof"): return false
	if not await _light(M1) or not await _expect(false,-1,"first75 and untouched second-15 remain unaligned"): return false
	if not _check(_row().get("status")=="active","wrong second angle cannot become ready"): return false
	if not await _light(M2) or not await _expect(true,3,"original light yields75/15 actual three-segment route"): return false
	var trace: Dictionary=PathSolver.trace(session.world,session.world.objects["F2:clock_source"],session.world.objects[M1],session.world.objects[RECEIVER],session.world.objects[M2])
	var mirror_ids: Array=[]
	for hit: Dictionary in trace.mirror_hits: mirror_ids.append(hit.id)
	report["actual_dual_trace"]=_plain(trace)
	if not _check(trace.valid and trace.code=="receiver_front" and trace.turns==2 and trace.segments.size()==3 and mirror_ids==[M1,M2],"independent original native ray really hits both mirrors then receiver front"): return false
	var until:=Time.get_ticks_msec()+3000
	while _row().get("status")!="ready" and Time.get_ticks_msec()<until:
		if not await _frames(1): return false
	if not _check(_row().get("status")=="ready" and _reward_count()==0 and session.sidejobs.error.is_empty(),"new actual dual observation is saved ready, without premature reward",_row()): return false
	if not await _failed_claim(): return false
	if not await _contact("claim") or not await _close_dialogue(): return false
	if not _check(_row().get("status")=="complete" and _reward_count()==1 and _claim_receipts()==1,"near native G claim atomically completes and awards once",_row()): return false
	var completed: Dictionary=_row()
	if not await _contact("repeat complete contact") or not await _close_dialogue(): return false
	if not _check(_row()==completed and _reward_count()==1 and _claim_receipts()==1,"repeat contact neither rewrites job nor repeats reward receipt"): return false
	if not _check(_main_untouched() and not session.inputs.test_enabled and not session.boss_active,"only new optional discovery differs; Story/choices/objectives/guest receipts unchanged"): return false
	var saved: Dictionary=await _save()
	if saved.is_empty(): return false
	if not _check(saved.world.get("npc_sidejobs_v1",{}).get("jobs",{}).get(JOB,{})==completed,"independent original Reader restores exactly completed optional row"): return false
	var file: String=session.store.root_path.path_join("profile_g%012d.json" % int(saved.generation))
	report["ordinary_save"]={"generation":saved.generation,"profile_id":saved.profile_id,"lineage_id":saved.lineage_id,"file":file,"sha256":FileAccess.get_sha256(file),"job":completed}
	if not _check(FileAccess.file_exists(file) and str(report.ordinary_save.sha256).length()==64,"actual Reader generation file has a recorded SHA, no guessed quit generation"): return false
	await _retire()
	if expired or not await _open(): return false
	if not _check(session.store.snapshot().profile_id==initial.profile_id and session.store.snapshot().lineage_id==initial.lineage_id and _row()==completed and _reward_count()==1 and _angle_matches(M1,deg_to_rad(75)) and _angle_matches(M2,deg_to_rad(15)),"fresh original MAIN preserves same UUID/lineage, optional row/reward and both physical mirror angles"): return false
	if not await _expect(true,3,"fresh MAIN recomputes saved physical dual path"): return false
	if not _check(_main_untouched() and _claim_receipts()==1,"fresh MAIN still has no mainline advancement or duplicate reward"): return false
	report["generation_after_restore"]=session.store.snapshot().generation
	return _check(_input_hashes()==input_before,"all small source/data inputs stay byte-identical through observation")

func _failed_claim() -> bool:
	if not await _near_npc(): return false
	var prepared: Dictionary=Contact.prepare(session,1,NPC)
	if not _check(prepared.get("ok",false) and session.story.nearest(session.players[1].global_position)==NPC and not session.interface.radio.visible,"faulted claim starts through actual near NPC gates"): return false
	var before: Dictionary=session.store.snapshot()
	var cache_before: Dictionary=session.world_cache.duplicate(true)
	var actions_before:=contacts.size()
	var dialogue_before:=dialogues.size()
	# Existing Store QA fault only; no authored job/personal/mechanism value.
	# No early return between setting and clearing. _retire also clears on teardown.
	session.store.failure_point="before_write"
	var sent: bool=await _g()
	var until:=Time.get_ticks_msec()+2500
	while sent and not expired and session.environment_save_gate.pending() and Time.get_ticks_msec()<until:
		sent=await _frames(1)
	var commit: Dictionary=session.last_commit_result.duplicate(true)
	var gate: Dictionary=session.environment_save_gate.last_result.duplicate(true)
	var unchanged: bool=session.store.snapshot()==before and session.world_cache==cache_before
	var no_dialogue: bool=dialogues.size()==dialogue_before and not session.interface.radio.visible and session.interface.radio_queue.is_empty()
	session.store.failure_point="" # Always before any assertion/return/retry.
	report["save_failure_injection"]={"explicit_QA_fault":"Store.before_write","cleared":session.store.failure_point.is_empty(),"commit":commit,"gate":gate,"store_and_cache_unchanged":unchanged,"no_completion_dialogue":no_dialogue,"explore_delta":contacts.size()-actions_before,"reward_count":_reward_count()}
	return _check(sent and not expired and contacts.size()==actions_before+1 and contacts[-1]=={"peer":1,"target":NPC} and commit.get("ok")==false and commit.get("error")=="SAVE_WRITE_FAILED" and commit.get("receipt")=="npc-sidejob:"+JOB+":claim" and gate.get("completed")==true and gate.get("ok")==false and unchanged and no_dialogue and _row().get("status")=="ready" and _reward_count()==0 and _claim_receipts()==0,"real near-G claim write failure leaves cache/job/personal untouched, no complete dialogue or reward",report.save_failure_injection)

func _contact(label: String) -> bool:
	if not _check(not session.interface.radio.visible and session.interface.radio_queue.is_empty(),label+" begins after original dialogue closed"): return false
	if not await _near_npc(): return false
	var prepared: Dictionary=Contact.prepare(session,1,NPC)
	if not _check(prepared.get("ok",false) and session.story.nearest(session.players[1].global_position)==NPC,label+" has real Contact/ordinary nearest gates",prepared): return false
	var actions_before:=contacts.size()
	var dialogue_before:=dialogues.size()
	if not await _g(): return false
	var until:=Time.get_ticks_msec()+2500
	while dialogues.size()==dialogue_before and Time.get_ticks_msec()<until:
		if not await _frames(1): return false
	var valid: bool=contacts.size()==actions_before+1 and contacts[-1]=={"peer":1,"target":NPC} and dialogues.size()==dialogue_before+1
	if not _check(valid,label+" native G emits exactly one original explore/dialogue",{"actions":contacts.slice(actions_before),"dialogue_count":dialogues.size()-dialogue_before}): return false
	var event: Dictionary=dialogues[-1]
	return _check(event.get("character_id")==NPC and event.get("speaker_name")==prepared.speaker_name and session.interface.radio.visible and session.interface.radio_speaker.text==prepared.speaker_name,label+" uses actual NPC name and original visible radio")

func _close_dialogue() -> bool:
	var count:=contacts.size()
	var shown:=0
	while session.interface.radio.visible and shown<16:
		shown+=1
		if not await _g(): return false
	return _check(not session.interface.radio.visible and session.interface.radio_queue.is_empty() and contacts.size()==count,"native sequential G closes each dialogue without another explore",shown)

func _near_npc() -> bool:
	if not session.ecology.view.actors.has(NPC): return _check(false,"actual F2 resident exists")
	var attempts: Array=[]
	for offset: Vector3 in [Vector3(0,3.2,0),Vector3(3,1,0),Vector3(-3,1,0),Vector3(0,1,3),Vector3(0,1,-3)]:
		var npc: Node3D=session.ecology.view.actors[NPC]
		var at: Vector3=npc.global_position+offset
		if not _clear(at): attempts.append({"at":at,"clear":false}); continue
		var body: FlightBodyV2=session.players[1]
		body.freeze=true
		body.global_transform=Transform3D(Basis.IDENTITY,at)
		body.force_update_transform()
		PhysicsServer3D.body_set_state(body.get_rid(),PhysicsServer3D.BODY_STATE_TRANSFORM,body.global_transform)
		body.linear_velocity=Vector3.ZERO; body.angular_velocity=Vector3.ZERO; body.hold_height=at.y
		if not await _frames(2): return false
		var reply: Dictionary=Contact.prepare(session,1,NPC)
		var nearest: String=session.story.nearest(body.global_position)
		attempts.append({"at":at,"clear":_clear(body.global_position),"contact":reply.get("code",""),"nearest":nearest})
		if _clear(body.global_position) and reply.get("ok",false) and nearest==NPC:
			report.poses.append({"kind":"QA_PLAYER_only_near_actual_moving_NPC","at":at,"npc_at":npc.global_position,"attempts":attempts})
			return true
	return _check(false,"bounded actual NPC pose search finds no full-hull-clear Contact/nearest fixture",attempts)

func _clear(at: Vector3) -> bool:
	if not Regions.contains("F2",at): return false
	var body: FlightBodyV2=session.players[1]
	var shape:=body.get_node("Envelope") as CollisionShape3D
	var query:=PhysicsShapeQueryParameters3D.new()
	query.shape=shape.shape; query.transform=Transform3D(Basis.IDENTITY,at)*shape.transform
	query.collision_mask=1|2|4|8|32; query.exclude=[body.get_rid()]
	return session.world.get_world_3d().direct_space_state.intersect_shape(query,1).is_empty()

func _g() -> bool:
	_key(true)
	var ok: bool=await _frames(1)
	_key(false)
	if not ok: return false
	return await _frames(1)
func _key(down: bool) -> void:
	var event:=InputEventKey.new()
	event.keycode=KEY_G; event.physical_keycode=KEY_G; event.pressed=down
	Input.parse_input_event(event)
func _row() -> Dictionary:
	return session.store.snapshot().world.get("npc_sidejobs_v1",{}).get("jobs",{}).get(JOB,{}).duplicate(true)
func _reward_count() -> int:
	return session.store.snapshot().personal.discoveries.count(REWARD)
func _claim_receipts() -> int:
	var count:=0
	for id: String in session.store.snapshot().ledger.commits:
		if id.begins_with("npc-sidejob:"+JOB+":claim:"): count+=1
	return count
func _main_untouched() -> bool:
	var current: Dictionary=_protected()
	current.personal.discoveries.erase(REWARD)
	return current==initial_protected
func _input_hashes() -> Dictionary:
	var values: Dictionary={}
	for path: String in [BASE_PATH,"res://scripts/v3/twin_session.gd","res://scripts/v3/gameplay/twin_opening_story.gd","res://scripts/v3/ecology/twin_living_world.gd","res://scripts/v3/ecology/twin_npc_contact.gd","res://scripts/v3/ecology/twin_npc_sidejob_host.gd","res://scripts/v3/ecology/twin_npc_sidejob_proofs.gd","res://scripts/v3/ecology/twin_npc_sidejob_state.gd","res://data/v3/campaign/npc_sidejob_f2.json","res://scripts/v3/campaign/twin_optical_path.gd"]:
		values[path]=FileAccess.get_sha256(path)
	return values

func _retire() -> void:
	if is_instance_valid(session) and session.store!=null: session.store.failure_point=""
	await super._retire()

func _finish(ok: bool) -> void:
	if finished: return
	finished=true
	_key(false)
	report["input_sha256_after"]=_input_hashes()
	if not input_before.is_empty(): _check(report.input_sha256_after==input_before,"small source inputs unchanged at terminal cleanup")
	report["explore_actions"]=contacts
	report["dialogues"]=_plain(dialogues)
	await _retire()
	report["engine_errors"]=logger.errors
	report["failures"]=report.checks.filter(func(row: Dictionary): return not row.passed)
	report["complete"]=ok and not expired and report.failures.is_empty() and logger.errors.is_empty()
	report["wall_seconds"]=float(Time.get_ticks_msec()-began)/1000.0
	var text: String=JSON.stringify(_plain(report),"\t",true,true)
	if text.to_utf8_buffer().size()>REPORT_LIMIT:
		report={"complete":false,"profile":profile,"version":ProjectSettings.get_setting("application/config/version"),"failure":"64KiB report budget exceeded","wall_seconds":float(Time.get_ticks_msec()-began)/1000.0,"engine_error_count":logger.errors.size()}
		text=JSON.stringify(report,"\t",true,true)
	var file:=FileAccess.open(output+"/result.json",FileAccess.WRITE)
	var written: bool=file!=null
	if file!=null:
		file.store_string(text); file.flush(); written=file.get_error()==OK; file.close()
	print("NPC_SIDEJOB_F2_MAIN_RESULT "+JSON.stringify(_plain(report)))
	quit(0 if report.complete and written else 1)
