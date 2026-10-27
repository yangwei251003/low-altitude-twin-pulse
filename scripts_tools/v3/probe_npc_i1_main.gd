extends "res://scripts_tools/v3/probe_optics_main.gd"
## Source MAIN probe only. The inherited 65s run/timer is NOT called.
const ACTOR := "I1:water_01"
const JOB := "sidejob:I1:cooling_handoff"
const REWARD := "npc_sidejob:I1:cooling_handoff"
const Contact = preload("res://scripts/v3/ecology/twin_npc_contact.gd")
const Anchors = preload("res://scripts/v3/ecology/twin_npc_anchors.gd")
var initial: Dictionary = {}
var initial_story: Dictionary = {}
var emitted: Dictionary = {}
var phase := "preflight"
var last_progress := 0
var pose_count := 0

func _run() -> void:
 if not _arguments():
  print("NPC_I1_ARGUMENTS_REJECTED"); quit(2); return
 began=Time.get_ticks_msec()
 report={"checks":[],"observations":[],"poses":[],"ability_actions":[],"native_events":[],"dialogues":[],"profile":profile,"user_dir":OS.get_user_data_dir(),"version":ProjectSettings.get_setting("application/config/version"),"protocol":Network.PROTOCOL,"scope":"Fresh original solo I1 MAIN, original Network/Rules charge and Story explore/Contact/sidejob/SaveGate. Bounded full-hull-clear frozen PLAYER observation poses only; no NPC/event/cargo/cycle/clock/flag/Story/sidejob writes, no manual simulation. Ecology route cargo, NOT PinJoint transport. Not natural player flight, physical keyboard, LAN or full campaign. Terminal cleanup uses original probe audio drain, not normal Session quit UI evidence."}
 var ok: bool=_check(report.version=="3.0.0-dev.86" and Network.PROTOCOL==28,"actual source86/LAN28 before MAIN Store")
 if ok: ok=await _exercise()
 await _finish(ok)

func _arguments() -> bool:
 var seen: Dictionary={}
 for arg: String in OS.get_cmdline_user_args():
  var key: String=""
  for pair: Array in [["--qa-profile=","profile"],["--probe-output=","output"]]:
   if arg.begins_with(pair[0]):
    key=pair[1]
    if seen.has(key): return false
    seen[key]=arg.trim_prefix(pair[0]); break
  if key.is_empty(): return false
 if not seen.has_all(["profile","output"]): return false
 profile=str(seen.profile); output=str(seen.output).replace("\\","/").trim_suffix("/")
 if not profile.begins_with("qa_npc_i1_86_") or profile.length()>96 or profile!=profile.validate_filename() or DirAccess.dir_exists_absolute("user://profiles_v3/"+profile): return false
 if not output.is_absolute_path() or "://" in output or ".." in output or "\n" in output or "\r" in output or not output.get_file().begins_with("npc-i1-probe-") or DirAccess.dir_exists_absolute(output) or FileAccess.file_exists(output): return false
 var roots: Dictionary=Binding._roots()
 return not roots.is_empty() and Binding._approved(output+"/result.json",roots,false) and DirAccess.make_dir_recursive_absolute(output)==OK

func _exercise() -> bool:
 session=MAIN.instantiate(); root.add_child(session)
 if not _check(session.profile_ready and session.store.root_path=="user://profiles_v3/"+profile and session.start_flight("solo"),"fresh private original MAIN start"): return false
 if not await _frames(12): return false
 initial=session.store.snapshot()
 initial_story=session.story.state.duplicate(true)
 report["identity"]={"profile_id":initial.profile_id,"lineage_id":initial.lineage_id,"generation":initial.generation}
 if not _check(session.region_id=="I1" and _row().is_empty() and session.sidejobs.error.is_empty() and session.story.state.get("completed",[]).is_empty() and not session.inputs.test_enabled,"original I1 ready without Story/sidejob prefix"): return false
 _phase("actual_relay_charge")
 var relay: Vector3=session.world.objects["I1:relay"].global_position
 if not await _place_near(relay,"relay_ability_observation"): return false
 session.network.send_action("lock",{"target_id":"I1:relay"})
 for attempt in 3:
  if float(session.entities["I1:relay"].get("charge",0.0))>=40.0: break
  var before: int=session.stats.abilities
  session.network.send_action("ability",{"ability":"charge","target_id":"I1:relay","mode":"add"})
  if not await _wait_cooldown(): return false
  report.ability_actions.append({"ability":"charge","target":"I1:relay","stats_before":before,"stats_after":session.stats.abilities,"charge":session.entities["I1:relay"].charge})
  if not _check(session.stats.abilities==before+1,"original Rules accepts relay charge"): return false
 if not _check(float(session.entities["I1:relay"].charge)>=40.0,"real relay powers I1 ecology supply"): return false
 _phase("offer")
 if not await _contact("offer"): return false
 if not _check(_row().is_empty(),"first contact offers only; no sidejob accepted"): return false
 _phase("accept")
 if not await _contact("accept"): return false
 if not await _wait_row("active",5.0): return false
 var accepted: Dictionary=_row().duplicate(true)
 report["accepted"]=accepted
 _phase("new_cargo_loaded")
 var deadline: int=mini(began+165000,Time.get_ticks_msec()+85000)
 while _row().get("load_id","").is_empty() and Time.get_ticks_msec()<deadline:
  if not await _frames(1): return false
 var loaded: Dictionary=_row().duplicate(true)
 var actor: Dictionary=session.ecology.simulation.get_actor(ACTOR)
 if not _check(not loaded.get("load_id","").is_empty() and int(loaded.load_serial)>int(accepted.accept_ecology) and actor.cargo and int(actor.cycles)==int(loaded.load_cycle),"post-accept native cargo_loaded persisted while same-cycle cargo aboard",{"row":loaded,"actor":actor}): return false
 report["loaded"]=loaded
 _phase("nearby_cargo_witness")
 if not await _contact("witness"): return false
 if not _check(_row().get("witnessed",false) and _row().load_id==loaded.load_id,"real near/LOS contact witnesses actual same-cycle cargo",_row()): return false
 _phase("same_cycle_arrival")
 if not await _wait_row("ready",60.0): return false
 var ready: Dictionary=_row().duplicate(true)
 if not _check(int(ready.work_serial)>int(ready.load_serial) and emitted.has(str(ready.load_id)) and emitted.has(str(ready.work_id)),"load and arrival came from original pending native event queue",ready): return false
 var load_event: Dictionary=emitted[ready.load_id]
 var arrival: Dictionary=emitted[ready.work_id]
 if not _check(load_event.kind=="cargo_loaded" and arrival.kind=="transport_arrival" and load_event.cycle==arrival.cycle and int(arrival.cycle)==int(ready.load_cycle),"original arrival is the witnessed load cycle",{"load":load_event,"arrival":arrival}): return false
 if not _check(int(session.ecology.facilities.coolant)>=1 and float(session.entities["I1:thermal"].temperature)<85.0,"actual coolant stock and thermal claim conditions currently safe"): return false
 _phase("claim")
 if not await _contact("claim") or not await _wait_row("complete",5.0): return false
 var completed: Dictionary=_row().duplicate(true)
 var personal: Dictionary=session.store.snapshot().personal
 if not _check(completed.reward_id==REWARD and personal.discoveries.count(REWARD)==1,"original completion commits exactly one new discovery",completed): return false
 _phase("repeat_no_reward")
 if not await _contact("repeat"): return false
 if not _check(_row()==completed and session.store.snapshot().personal==personal,"repeat contact cannot mutate job/reward"): return false
 _phase("SaveGate_fresh_reader")
 return await _readback()

func _row() -> Dictionary:
 return session.world_cache.get("world",{}).get("npc_sidejobs_v1",{}).get("jobs",{}).get(JOB,{})

func _contact(label: String) -> bool:
 if not await _dismiss(): return false
 if not await _idle_gate(): return false
 var actor: Dictionary=session.ecology.simulation.get_actor(ACTOR)
 if actor.is_empty() or not await _place_near(session.world.to_global(Anchors.local_position(actor)),"contact_"+label): return false
 var fresh: Dictionary=Contact.prepare(session,1,ACTOR)
 if not _check(fresh.get("ok",false),"original Contact validates actual nearby NPC "+label,fresh.get("code","")): return false
 session.network.send_action("explore",{"target_id":ACTOR})
 var deadline: int=Time.get_ticks_msec()+4500
 while not session.interface.radio.visible and Time.get_ticks_msec()<deadline:
  if not await _frames(1): return false
 if not _check(session.interface.radio.visible,"original Story/Network dialogue appears: "+label): return false
 var lines: Array=[session.interface.radio_text.text]
 for line: Dictionary in session.interface.radio_queue: lines.append(line.text)
 report.dialogues.append({"phase":label,"lines":lines,"speaker":session.interface.radio_speaker.text})
 return await _dismiss()

func _dismiss() -> bool:
 for unused in 16:
  if not session.interface.radio.visible: return true
  var event:=InputEventKey.new(); event.physical_keycode=KEY_G; event.keycode=KEY_G; event.pressed=true
  session._unhandled_input(event)
  event.pressed=false; session._unhandled_input(event)
  if not await _frames(1): return false
 return _check(false,"bounded original G dialogue dismissal")

func _place_near(point: Vector3,label: String) -> bool:
 if pose_count>=8: return _check(false,"bounded player-only pose count")
 var body: FlightBodyV2=session.players[1]
 var envelope: CollisionShape3D=body.get_node("Envelope")
 for offset: Vector3 in [Vector3(0,1.5,2.0),Vector3(2.0,1.5,0),Vector3(-2.0,1.5,0),Vector3(0,1.5,-2.0),Vector3(0,3,0)]:
  var at: Vector3=point+offset
  var query:=PhysicsShapeQueryParameters3D.new()
  query.shape=envelope.shape; query.transform=Transform3D(Basis.IDENTITY,at)*envelope.transform
  query.collision_mask=1|2|4|8|32; query.exclude=[body.get_rid()]; query.margin=.03
  if not Regions.contains("I1",at) or not session.world.get_world_3d().direct_space_state.intersect_shape(query,1).is_empty(): continue
  var target: String="I1:relay" if label.begins_with("relay") else ACTOR
  if not session._line_clear(at,point,body.get_rid(),target): continue
  body.freeze=true; body.global_transform=Transform3D(Basis.IDENTITY,at); body.force_update_transform()
  PhysicsServer3D.body_set_state(body.get_rid(),PhysicsServer3D.BODY_STATE_TRANSFORM,body.global_transform)
  body.linear_velocity=Vector3.ZERO; body.angular_velocity=Vector3.ZERO; body.hold_height=at.y
  pose_count+=1; report.poses.append({"label":label,"at":at,"native_full_envelope_clear":true,"fixture_player_only_not_flown":true})
  return await _frames(2)
 return _check(false,"no bounded full-hull-clear contact pose: "+label,{"target":point,"actor":session.ecology.simulation.get_actor(ACTOR)})

func _idle_gate() -> bool:
 var deadline: int=Time.get_ticks_msec()+5000
 while session.environment_save_gate.pending() and Time.get_ticks_msec()<deadline:
  if not await _frames(1): return false
 return _check(not session.environment_save_gate.pending(),"prior original save barrier finished")

func _wait_cooldown() -> bool:
 if not await _frames(3): return false
 var deadline: int=Time.get_ticks_msec()+2000
 while float(session.cooldowns.get(1,0))>0 and Time.get_ticks_msec()<deadline:
  if not await _frames(1): return false
 return _check(float(session.cooldowns.get(1,0))<=0,"original ability cooldown elapsed normally")

func _wait_row(status: String,seconds: float) -> bool:
 var deadline: int=mini(began+175000,Time.get_ticks_msec()+int(seconds*1000))
 while _row().get("status","")!=status and Time.get_ticks_msec()<deadline:
  if not await _frames(1): return false
 return _check(_row().get("status","")==status,"real job reaches "+status,_row())

func _frames(count: int) -> bool:
 for unused in count:
  await physics_frame; await process_frame
  if Time.get_ticks_msec()-began>=178000:
   expired=true; return _check(false,"178s exercise budget reserves terminal drain within180s; incomplete is failure",{"phase":phase})
  if not logger.errors.is_empty(): return false
  if is_instance_valid(session) and session.active:
   for item: Dictionary in session.sidejobs._events:
    var event: Dictionary=item.proof
    var id: String=str(event.get("event_id",""))
    if event.get("actor_id")==ACTOR and not emitted.has(id):
     if emitted.size()>=8: return _check(false,"bounded native evidence queue")
     emitted[id]=event.duplicate(true); report.native_events.append(event.duplicate(true))
  if Time.get_ticks_msec()-last_progress>=10000:
   last_progress=Time.get_ticks_msec(); print("NPC_I1_PROGRESS "+JSON.stringify({"phase":phase,"seconds":float(last_progress-began)/1000.0,"job":_row() if is_instance_valid(session) and session.active else {}}))
 return not expired and not finished

func _readback() -> bool:
 if not await _idle_gate(): return false
 var callbacks: Array=[]
 var requested: Dictionary=session.request_environment_save(func(row: Dictionary): callbacks.append(row.duplicate(true)))
 if not _check(requested.get("ok",false),"original final SaveGate request accepted"): return false
 var deadline: int=Time.get_ticks_msec()+6000
 while callbacks.is_empty() and Time.get_ticks_msec()<deadline:
  if not await _frames(1): return false
 if not _check(not callbacks.is_empty() and callbacks[-1].get("ok",false) and callbacks[-1].get("completed",false),"original final SaveGate succeeded",callbacks): return false
 var live: Dictionary=session.store.snapshot()
 var reader=Store.new(session.store.root_path)
 var loaded: Dictionary=reader.load_profile()
 var disk: Dictionary=reader.snapshot()
 var job: Dictionary=disk.world.get("npc_sidejobs_v1",{}).get("jobs",{}).get(JOB,{})
 report["save"]={"callbacks":callbacks,"loaded":loaded,"generation":disk.get("generation",-1),"profile_id":disk.get("profile_id",""),"lineage_id":disk.get("lineage_id",""),"job":job,"discovery_count":disk.get("personal",{}).get("discoveries",[]).count(REWARD),"ecology_event_serial":disk.get("world",{}).get("ecology",{}).get("simulation",{}).get("event_serial",-1)}
 return _check(loaded.get("ok",false) and not loaded.get("recovered",false) and session.store.matches_persisted_value(live,disk) and disk.profile_id==initial.profile_id and disk.lineage_id==initial.lineage_id and job.status=="complete" and disk.personal.discoveries.count(REWARD)==1 and session.story.state==initial_story and disk.world.get("actions",{})==initial.world.get("actions",{}) and disk.world.flags==initial.world.flags and disk.world.choices==initial.world.choices and disk.world.completed_objectives==initial.world.completed_objectives,"independent original reader exactly matches committed private save/identity; original Story and choices/objectives unchanged")

func _phase(value: String) -> void:
 phase=value; print("NPC_I1_PHASE "+value)

func _finish(ok: bool) -> void:
 if finished: return
 finished=true
 if is_instance_valid(session):
  report["last_job"]=_row().duplicate(true)
  report["ecology_actor"]=session.ecology.simulation.get_actor(ACTOR)
  report["last_commit"]=session.last_commit_result.duplicate(true)
 await _retire()
 report["engine_errors"]=logger.errors
 report["failures"]=report.checks.filter(func(row: Dictionary): return not row.passed)
 report["complete"]=ok and not expired and report.failures.is_empty() and logger.errors.is_empty()
 report["phase"]=phase; report["wall_seconds"]=float(Time.get_ticks_msec()-began)/1000.0
 if report.wall_seconds>180.0: report["complete"]=false; report["deadline_overrun"]=true
 var text: String=JSON.stringify(_plain(report),"\t",true,true)
 if text.to_utf8_buffer().size()>64*1024:
  print("NPC_I1_REPORT_LIMIT_FAIL"); quit(1); return
 var file:=FileAccess.open(output+"/result.json",FileAccess.WRITE)
 var written: bool=file!=null
 if file!=null:
  file.store_string(text); file.flush(); written=file.get_error()==OK; file.close()
 print("NPC_I1_RESULT "+JSON.stringify({"complete":report.complete,"written":written,"phase":phase,"seconds":report.wall_seconds,"errors":logger.errors.size()}))
 quit(0 if report.complete and written else 1)
