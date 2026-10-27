extends "res://scripts_tools/v3/probe_optics_main.gd"
## Source MAIN probe only. The inherited 65s run/timer is NOT called.
const ACTOR := "I2:service_01"
const JOB := "sidejob:I2:service_handoff"
const REWARD := "npc_sidejob:I2:service_handoff"
const Contact = preload("res://scripts/v3/ecology/twin_npc_contact.gd")
const Anchors = preload("res://scripts/v3/ecology/twin_npc_anchors.gd")
var initial: Dictionary = {}
var initial_story: Dictionary = {}
var emitted: Dictionary = {}
var phase := "preflight"
var last_progress := 0
var pose_count := 0
var prepare_path := ""
var prepare_sha := ""
var prepared_report: Dictionary = {}
var prepared_snapshot: Dictionary = {}
const I2Ledger = preload("res://scripts/v3/gameplay/twin_i2_result_ledger.gd")

func _run() -> void:
 if not _arguments():
  print("NPC_I2_ARGUMENTS_REJECTED"); quit(2); return
 began=Time.get_ticks_msec()
 report={"checks":[],"observations":[],"poses":[],"ability_actions":[],"native_events":[],"dialogues":[],"profile":profile,"user_dir":OS.get_user_data_dir(),"version":ProjectSettings.get_setting("application/config/version"),"protocol":Network.PROTOCOL,"scope":"Exactly bound independently prepared37 QA profile; original solo I2 MAIN, Story explore/Contact/sidejob/SaveGate. Bounded full-hull-clear frozen PLAYER observation poses only; no NPC/event/cargo/cycle/clock/flag/Story/sidejob writes, no manual simulation. Ecology route cargo, NOT PinJoint transport. Not natural player flight, physical keyboard, LAN or full campaign. Terminal cleanup uses original probe audio drain, not normal Session quit UI evidence."}
 var ok: bool=_check(report.version=="3.0.0-dev.86" and Network.PROTOCOL==28,"actual source86/LAN28 before MAIN Store")
 if ok: ok=await _exercise()
 await _finish(ok)

func _arguments() -> bool:
 var seen: Dictionary={}
 for arg: String in OS.get_cmdline_user_args():
  var key: String=""
  for pair: Array in [["--qa-profile=","profile"],["--probe-output=","output"],["--prepare-report=","prepare_path"],["--prepare-sha256=","prepare_sha"]]:
   if arg.begins_with(pair[0]):
    key=pair[1]
    if seen.has(key): return false
    seen[key]=arg.trim_prefix(pair[0]); break
  if key.is_empty(): return false
 if not seen.has_all(["profile","output","prepare_path","prepare_sha"]): return false
 profile=str(seen.profile); output=str(seen.output).replace("\\","/").trim_suffix("/")
 prepare_path=str(seen.prepare_path).replace("\\","/"); prepare_sha=str(seen.prepare_sha)
 if not profile.begins_with("qa_npc_i2_86_") or profile.length()>96 or profile!=profile.validate_filename() or not DirAccess.dir_exists_absolute("user://profiles_v3/"+profile): return false
 if not output.is_absolute_path() or "://" in output or ".." in output or "\n" in output or "\r" in output or not output.get_file().begins_with("npc-i2-probe-") or DirAccess.dir_exists_absolute(output) or FileAccess.file_exists(output): return false
 var roots: Dictionary=Binding._roots()
 if roots.is_empty() or not Binding._approved(output+"/result.json",roots,false): return false
 var source: Dictionary=Binding._small_json(prepare_path,prepare_sha,64*1024,roots,false)
 if not source.ok: print("NPC_I2_BINDING_REJECT "+str(source.get("code","source"))); return false
 prepared_report=source.value
 if not _verify_prepared(): return false
 return DirAccess.make_dir_recursive_absolute(output)==OK

func _verify_prepared() -> bool:
 var r: Dictionary=prepared_report
 if not r.get("source_report") is Dictionary or not Binding._hex(r.source_report.get("sha256"),64) or r.source_report.get("selector")!="snapshots.phases.claimed.source" or not r.source_report.get("path") is String: return false
 if r.get("schema_version")!=1 or r.get("complete")!=true or r.get("fixture_kind")!="independent_historical_37" or r.get("natural_campaign_replay")!=false or r.get("version")!="3.0.0-dev.86" or r.get("protocol")!=28 or r.get("profile")!=profile or r.get("branch_id")!="main" or r.get("prefix_count")!=37 or r.get("prefix_last")!="I2:canal_service:service": return false
 if r.get("failures")!=[] or r.get("engine_errors")!=[] or not r.get("restore") is Dictionary or not r.get("cleanup") is Dictionary or r.cleanup.get("audio_ready")!=true: return false
 for key: String in ["fresh_main","all_four_ready","canal_ready","ledger_valid","clinic_access_clear"]:
  if r.restore.get(key)!=true: return false
 if not Binding._positive(r.get("generation")) or not Binding._hex(r.get("profile_id"),32) or not Binding._hex(r.get("lineage_id"),32): return false
 for key: String in ["profile_file_sha256","payload_sha256","prefix_digest","opening_state_sha256","prerequisites_sha256"]:
  if not Binding._hex(r.get(key),64): return false
 var path: String="user://profiles_v3/"+profile
 var file_path: String=ProjectSettings.globalize_path(path.path_join("profile_g%012d.json" % int(r.generation)))
 if Binding._norm(str(r.get("profile_root","")))!=Binding._norm(ProjectSettings.globalize_path(path)) or Binding._norm(str(r.get("profile_file","")))!=Binding._norm(file_path) or FileAccess.get_sha256(file_path)!=r.profile_file_sha256: return false
 var file:=FileAccess.open(file_path,FileAccess.READ)
 if file==null or file.get_length()<=0 or file.get_length()>Store.MAX_FILE_BYTES: return false
 var outer: Variant=JSON.parse_string(file.get_as_text()); file.close()
 if not outer is Dictionary or outer.get("format")!=1 or not outer.get("payload_json") is String or outer.get("payload_sha256")!=r.payload_sha256 or outer.payload_json.sha256_text()!=r.payload_sha256: return false
 var reader=Store.new(path)
 var loaded: Dictionary=reader.load_profile()
 var disk: Dictionary=reader.snapshot()
 if not loaded.get("ok",false) or loaded.get("recovered",false) or disk.generation!=r.generation or disk.profile_id!=r.profile_id or disk.lineage_id!=r.lineage_id or disk.world.branch_id!="main": return false
 if not _same_prerequisites(disk) or not disk.world.get("npc_sidejobs_v1",{}).is_empty() or not I2Ledger.validate_world(disk.world,disk.personal.discoveries).get("ok",false): return false
 if FileAccess.get_sha256(file_path)!=r.profile_file_sha256: return false
 prepared_snapshot=disk
 return true

func _same_prerequisites(disk: Dictionary) -> bool:
 var opening: Dictionary=disk.world.get("actions",{}).get("opening",{})
 var completed: Array=opening.get("completed",[])
 if completed.size()!=37 or completed[-1]!="I2:canal_service:service" or JSON.stringify(completed,"",true,true).sha256_text()!=prepared_report.prefix_digest or JSON.stringify(opening,"",true,true).sha256_text()!=prepared_report.opening_state_sha256: return false
 var required: Dictionary={}
 for key: String in ["I2_water","I2_distribution","I2_trial_flow","I2_shared_access","I2_canal"]:
  if not disk.world.get("environment",{}).has(key): return false
  required[key]=disk.world.environment[key]
 return JSON.stringify(required,"",true,true).sha256_text()==prepared_report.prerequisites_sha256

func _exercise() -> bool:
 report["prepared_binding"]={"report":prepare_path,"sha256":prepare_sha,"profile_file":prepared_report.profile_file,"profile_file_sha256":prepared_report.profile_file_sha256,"generation":prepared_report.generation,"profile_id":prepared_report.profile_id,"lineage_id":prepared_report.lineage_id,"opening_state_sha256":prepared_report.opening_state_sha256,"fixture_kind":prepared_report.fixture_kind,"historical_physical_source":prepared_report.source_report,"controller_Job0_must_be_verified_externally":true}
 session=MAIN.instantiate(); root.add_child(session)
 if not _check(session.profile_ready and session.store.root_path=="user://profiles_v3/"+profile and session.store.snapshot().generation==prepared_report.generation and session.store.snapshot().profile_id==prepared_report.profile_id and session.store.snapshot().lineage_id==prepared_report.lineage_id and session.start_flight("solo"),"original MAIN mounts exactly the prepared profile/generation/identity"): return false
 if session.region_id!="I2" and not _check(session._load_region("I2"),"explicit original I2 area adoption, not natural travel"): return false
 var ready_deadline: int=Time.get_ticks_msec()+20000
 while not (session._facilities_ready() and session.canal!=null and session.canal.ready) and Time.get_ticks_msec()<ready_deadline:
  if not await _frames(1): return false
 if not _check(session.region_id=="I2" and session._facilities_ready() and session.clinic.ready and session.distribution.ready and session.trial.ready and session.shared_access.ready and session.canal!=null and session.canal.ready and not session.inputs.test_enabled,"original MAIN all four facilities and Canal ready"): return false
 initial=session.store.snapshot(); initial_story=session.story.state.duplicate(true)
 report["identity"]={"profile_id":initial.profile_id,"lineage_id":initial.lineage_id,"generation":initial.generation}
 if not _check(JSON.stringify(initial_story,"",true,true).sha256_text()==prepared_report.opening_state_sha256 and initial_story.get("completed",[]).size()==37 and initial.personal==prepared_snapshot.personal and initial.world.flags==prepared_snapshot.world.flags and initial.world.choices==prepared_snapshot.world.choices and initial.world.completed_objectives==prepared_snapshot.world.completed_objectives and _row().is_empty() and session.sidejobs.error.is_empty() and initial.world.flags.get("I2:canal_service_ready")==true and _clinic_ok(),"same prepared37 Story, no sidejob, actual service/Clinic prerequisites now valid"): return false
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
 if not _check(load_event.kind=="cargo_loaded" and load_event.target_id=="I2:service_supply" and arrival.kind=="transport_arrival" and arrival.target_id=="I2:service_receiver" and load_event.cycle==arrival.cycle and int(arrival.cycle)==int(ready.load_cycle),"original arrival is the witnessed load cycle",{"load":load_event,"arrival":arrival}): return false
 if not _check(_clinic_ok(),"original live Clinic volume/quality/inlet/platform/access claim conditions"): return false
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
  if not Regions.contains("I2",at) or not session.world.get_world_3d().direct_space_state.intersect_shape(query,1).is_empty(): continue
  var target: String=ACTOR
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
   last_progress=Time.get_ticks_msec(); print("NPC_I2_PROGRESS "+JSON.stringify({"phase":phase,"seconds":float(last_progress-began)/1000.0,"job":_row() if is_instance_valid(session) and session.active else {}}))
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
 # Store._persist publishes its actual decoded readback; both snapshots already crossed JSON.
 # Require direct whole-tree equality; do not encode/round the published value a second time.
 var checks: Dictionary={"loaded":loaded.get("ok",false) and not loaded.get("recovered",false),"whole_live_disk":live==disk,"profile_id":disk.profile_id==initial.profile_id,"lineage_id":disk.lineage_id==initial.lineage_id,"job_complete":job.status=="complete","unique_reward":disk.personal.discoveries.count(REWARD)==1,"story_unchanged":session.story.state==initial_story,"saved_actions_unchanged":disk.world.get("actions",{})==initial.world.get("actions",{}),"flags_unchanged":disk.world.flags==initial.world.flags,"choices_unchanged":disk.world.choices==initial.world.choices,"objectives_unchanged":disk.world.completed_objectives==initial.world.completed_objectives,"personal_only_new_reward":_personal_only_new_reward(disk.personal)}
 report["readback_components"]=checks
 report["readback_personal"]={"before":initial.personal,"after":disk.personal}
 report["readback_differences"]={"live_disk":_diff(live,disk),"story":_diff(initial_story,session.story.state),"saved_actions":_diff(initial.world.get("actions",{}),disk.world.get("actions",{}))}
 print("NPC_I2_READBACK_COMPONENTS "+JSON.stringify(checks))
 return _check(checks.values().all(func(value: Variant): return value==true),"independent original reader exactly matches current same-profile save; prepared37/flags/choices/objectives/rewards preserved",checks)

func _clinic_ok() -> bool:
 if not session.clinic.ready or not is_instance_valid(session.clinic.module): return false
 var status: Dictionary=session.clinic.module.status()
 return session.clinic.progress.snapshot().get("commissioned",false) and status.get("clinic_volume_ml")==status.get("target_volume_ml") and float(status.get("clean_fraction",0))>=.95 and status.get("inlet_closed")==true and status.get("platform_blocked")==false and session.clinic.access_clear()

func _personal_only_new_reward(personal: Dictionary) -> bool:
 var expected: Dictionary=initial.personal.duplicate(true)
 if REWARD in expected.discoveries: return false
 expected.discoveries.append(REWARD)
 return personal==expected

func _phase(value: String) -> void:
 phase=value; print("NPC_I2_PHASE "+value)

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
  print("NPC_I2_REPORT_LIMIT_FAIL"); quit(1); return
 var file:=FileAccess.open(output+"/result.json",FileAccess.WRITE)
 var written: bool=file!=null
 if file!=null:
  file.store_string(text); file.flush(); written=file.get_error()==OK; file.close()
 print("NPC_I2_RESULT "+JSON.stringify({"complete":report.complete,"written":written,"phase":phase,"seconds":report.wall_seconds,"errors":logger.errors.size()}))
 quit(0 if report.complete and written else 1)

func _diff(a: Variant,b: Variant,path: String="root",depth: int=0) -> Array:
 var result: Array=[]
 if a==b: return result
 if depth>28: return [{"path":path,"code":"depth_bound"}]
 if a is Dictionary and b is Dictionary:
  for key: Variant in a.keys()+b.keys():
   if result.size()>=8: break
   if not a.has(key) or not b.has(key):
    result.append({"path":path+"."+str(key),"code":"key_presence","a":a.has(key),"b":b.has(key)}); continue
   for row: Dictionary in _diff(a[key],b[key],path+"."+str(key),depth+1):
    if result.size()<8: result.append(row)
 elif a is Array and b is Array:
  if a.size()!=b.size(): return [{"path":path,"code":"array_size","a":a.size(),"b":b.size()}]
  for i in a.size():
   for row: Dictionary in _diff(a[i],b[i],path+"["+str(i)+"]",depth+1):
    if result.size()<8: result.append(row)
   if result.size()>=8: break
 else: result.append({"path":path,"code":"value","a":str(a).left(160),"b":str(b).left(160),"a_type":type_string(typeof(a)),"b_type":type_string(typeof(b))})
 return result
