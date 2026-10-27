extends "res://scripts_tools/v3/probe_optics_main.gd"
## Source86 MAIN. Overrides parent65s timer; only initial LOW PLAYER pose is authored.
const Cargo = preload("res://scripts/v3/gameplay/twin_thermal_cargo_session.gd")
const Pilot = preload("res://scripts/v3/gameplay/canal/canal_transport_physics/transport_pilot.gd")
const EmptyPilot = preload("res://scripts/v3/qa/twin_normal_flight_pilot.gd")
const Contact = preload("res://scripts/v3/ecology/twin_npc_contact.gd")
const Anchors = preload("res://scripts/v3/ecology/twin_npc_anchors.gd")
const ACTOR := "I3:coolant_01"
const JOB := "sidejob:I3:dock_recheck"
const REWARD := "npc_sidejob:I3:dock_recheck"
class Commands extends Node:
 var owner_session: Node
 var pilot: RefCounted
 var enabled := false
 func _physics_process(delta: float) -> void:
  if not enabled or pilot==null or not is_instance_valid(owner_session) or not owner_session.active or owner_session.simulation_paused: return
  if not owner_session.thermal_cargo.supported() or not owner_session.thermal_cargo.module.status().assist.is_empty(): return
  pilot.tick(delta,true,false) # Commands only. Session remains sole ordinary module advance.
var driver: Commands
var serial := 0
var phase := "preflight"
var initial: Dictionary = {}
var initial_story: Dictionary = {}
var emitted: Dictionary = {}
var last_progress := 0
var last_position := Vector3.ZERO
var flight_started := false
var flown := 0.0
var max_step := 0.0
var loaded_frames := 0

func _run() -> void:
 if not _arguments(): print("NPC_I3_ARGUMENTS_REJECTED"); quit(2); return
 began=Time.get_ticks_msec()
 report={"checks":[],"observations":[],"poses":[],"native_events":[],"dialogues":[],"route":[],"profile":profile,"user_dir":OS.get_user_data_dir(),"version":ProjectSettings.get_setting("application/config/version"),"protocol":Network.PROTOCOL,"scope":"Fresh original MAIN/explicit I3 QA area, only pre-MAIN cooling flag fixture and one initial full-hull-clear LOW PLAYER pose. Canonical loaded Pilot1.8/real Flight/Joint2kg/ordinary G/assist/HIGH350ms; unloaded NPC interception uses existing QAFlight max6 and original sweeps/inertia. Real delivery BEFORE optional acceptance; new native inspection afterwards. No NPC/event/cargo/proof/Story/sidejob/time/serial fixtures, manual simulation or protected profile. Not natural travel/manual comfort/LAN/full campaign. Terminal audio QA cleanup, not normal quit input coverage."}
 var ok: bool=_check(report.version=="3.0.0-dev.86" and Network.PROTOCOL==28,"actual Source86/LAN28 before Store/Main")
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
 if not profile.begins_with("qa_npc_i3_86_") or profile.length()>96 or profile!=profile.validate_filename() or DirAccess.dir_exists_absolute("user://profiles_v3/"+profile): return false
 if not output.is_absolute_path() or "://" in output or ".." in output or "\n" in output or "\r" in output or not output.get_file().begins_with("npc-i3-probe-") or DirAccess.dir_exists_absolute(output) or FileAccess.file_exists(output): return false
 var roots: Dictionary=Binding._roots()
 return not roots.is_empty() and Binding._approved(output+"/result.json",roots,false) and DirAccess.make_dir_recursive_absolute(output)==OK

func _exercise() -> bool:
 _phase("pre_MAIN_cooling_prerequisite")
 var fixture=Store.new("user://profiles_v3/"+profile)
 var opened: Dictionary=fixture.load_profile()
 var before: Dictionary=fixture.snapshot()
 if not _check(opened.get("ok",false) and int(before.generation)==0 and before.world.flags.is_empty() and before.personal.discoveries.is_empty(),"unique fresh original Store before sole fixture"): return false
 var prepared: Dictionary=fixture.commit({"id":"qa-i3-cooling-prerequisite","set":{"world.flags.I3:cooling_ready":true}})
 report["prerequisite"]={"result":prepared,"only_authored_path":"world.flags.I3:cooling_ready","before_MAIN_constructed":true,"not_claiming_main_thermal_completion":true}
 if not _check(prepared.get("ok",false),"original Store accepts explicit cooling prerequisite fixture"): return false
 session=MAIN.instantiate(); root.add_child(session)
 if not _check(session.profile_ready and session.store.root_path=="user://profiles_v3/"+profile and session.world_cache.world.flags.get("I3:cooling_ready")==true and session.start_flight("solo"),"whole original MAIN/Story loads fixture then starts normal solo; no post-start flag patch"): return false
 if not _check(session._load_region("I3"),"explicit original I3 QA area adoption accepts prerequisite; not normal travel"): return false
 if not await _frames(12): return false
 if not _check(session.region_id=="I3" and session.thermal_cargo.supported() and session.sidejobs.error.is_empty() and not session.inputs.test_enabled,"actual I3 participant installed under normal MAIN"): return false
 initial=session.store.snapshot(); initial_story=session.story.state.duplicate(true)
 report["identity"]={"profile_id":initial.profile_id,"lineage_id":initial.lineage_id,"generation":initial.generation}
 if not _check(initial_story.get("completed",[]).is_empty() and _row().is_empty() and session.thermal_cargo.fact(Cargo.FACT).is_empty(),"no Story/sidejob/delivery proof authored"): return false
 driver=Commands.new(); driver.owner_session=session; driver.process_physics_priority=10; root.add_child(driver)
 if not await _place_low(): return false
 var deadline: int=Time.get_ticks_msec()+5000
 while (not _module().ready or _custody().get("phase")!="docked") and Time.get_ticks_msec()<deadline:
  if not await _frames(1): return false
 if not _check(_module().ready and _custody().get("berth")==Cargo.LOW,"original native LOW350ms support before pickup"): return false
 _phase("original_G_pickup")
 _press_g(Cargo.CARGO)
 if not await _assist(35000): return false
 var body: FlightBodyV2=session.players[1]
 if not _check(body.cargo_items.has(Cargo.CARGO) and body.cargo_kg==2.0 and session.world.objects[Cargo.CARGO].mass==2.0 and body.cargo_items[Cargo.CARGO].joint is PinJoint3D and body.cargo_items[Cargo.CARGO].joint.get_node(body.cargo_items[Cargo.CARGO].joint.node_a)==body and body.cargo_items[Cargo.CARGO].joint.get_node(body.cargo_items[Cargo.CARGO].joint.node_b)==session.world.objects[Cargo.CARGO],"actual unique2kg body/native Joint endpoints attached"): return false
 if not _bind(false): return false
 flight_started=true; last_position=body.global_position
 _phase("canonical_loaded_outer")
 for index: int in Cargo.OUTER.size():
  if not await _fly(Cargo.OUTER[index],"outer_"+str(index),45000): return false
  var journey: Dictionary=_module().status().journey
  if not _check(int(journey.get("outer_progress",0))>=index+1 and not journey.get("broken",true),"original native ordered outer sphere "+str(index),journey): return false
 var high: Vector3=session.world.objects[Cargo.HIGH].global_position
 for at: Vector3 in [Vector3(high.x,14,5),Vector3(high.x,14,high.z),high+Vector3.UP*(.25+.2+1.1+.55)]:
  if not await _fly(at,"HIGH_approach",25000): return false
 _phase("original_G_release_native_settle")
 driver.enabled=false
 _press_g(Cargo.HIGH)
 if not await _assist(35000): return false
 deadline=Time.get_ticks_msec()+8000
 while (_custody().get("phase")!="docked" or session.thermal_cargo.fact(Cargo.FACT).is_empty()) and Time.get_ticks_msec()<deadline:
  if not await _frames(1): return false
 var delivery: Dictionary=session.thermal_cargo.capture()
 if not _check(delivery.get("ok",false) and delivery.get("state",{}).get("version")==1 and _custody().get("phase")=="docked" and _custody().get("berth")==Cargo.HIGH and _module().status().proof.get("route")=="outer_corridor" and body.cargo_items.is_empty(),"real HIGH350ms/custody/delivery proof before optional acceptance",_module().status()): return false
 report["real_delivery_before_accept"]={"proof":delivery.state.proof.duplicate(true),"custody":delivery.state.custody.cargos[Cargo.CARGO].duplicate(true),"ecology_serial":session.ecology.simulation.snapshot().event_serial,"loaded_frames":loaded_frames}
 if not _bind(true): return false
 _phase("offer_then_accept_after_real_delivery")
 if not await _contact("offer") or not _check(_row().is_empty(),"first optional contact offers only"): return false
 if not await _contact("accept"): return false
 if not await _wait_status("active",5000): return false
 deadline=Time.get_ticks_msec()+5000
 while _row().get("work_id","").is_empty() and Time.get_ticks_msec()<deadline:
  if not await _frames(1): return false
 var accepted: Dictionary=_row().duplicate(true)
 report["accepted_old_real_delivery"]=accepted
 if not _check(accepted.get("status")=="active" and not accepted.get("work_id","").is_empty() and accepted.get("aux_id","").is_empty(),"already-real delivery alone remains active; no old inspection credited",accepted): return false
 _phase("new_inspection_after_accept_and_cargo_sample")
 if not await _wait_status("ready",65000): return false
 var ready: Dictionary=_row().duplicate(true)
 if not _check(int(ready.aux_serial)>maxi(int(ready.accept_ecology),int(ready.work_ecology)) and emitted.has(str(ready.aux_id)),"ready requires later original queued native inspection",ready): return false
 var event: Dictionary=emitted[ready.aux_id]
 if not _check(event.actor_id==ACTOR and event.kind=="inspection_complete" and event.target_id=="I3:loaded_dock" and int(event.serial)==int(ready.aux_serial),"real ecology inspection source and serial exact",event): return false
 _phase("claim_same_original_cargo")
 if not await _contact("claim") or not await _wait_status("complete",5000): return false
 var completed: Dictionary=_row().duplicate(true)
 var personal: Dictionary=session.store.snapshot().personal
 if not _check(personal.discoveries.count(REWARD)==1 and completed.reward_id==REWARD,"original claim commits exactly one new discovery"): return false
 if not await _contact("repeat"): return false
 if not _check(_row()==completed and session.store.snapshot().personal==personal,"repeat contact cannot alter job/reward"): return false
 _phase("SaveGate_and_independent_Reader")
 return await _readback()

func _module(): return session.thermal_cargo.module
func _custody() -> Dictionary: return _module().status().get("custody",{}).get("cargos",{}).get(Cargo.CARGO,{})
func _row() -> Dictionary: return session.world_cache.get("world",{}).get("npc_sidejobs_v1",{}).get("jobs",{}).get(JOB,{})

func _place_low() -> bool:
 var body: FlightBodyV2=session.players[1]
 var at:=Vector3(-10,4.1,18)
 var envelope: CollisionShape3D=body.get_node("Envelope")
 var query:=PhysicsShapeQueryParameters3D.new()
 query.shape=envelope.shape; query.transform=Transform3D(Basis.IDENTITY,at)*envelope.transform
 query.collision_mask=Cargo.MASK; query.exclude=[body.get_rid()]; query.margin=.001
 if not _check(session.world.get_world_3d().direct_space_state.intersect_shape(query,1).is_empty(),"sole initial PLAYER LOW observation pose has native whole-hull clearance"): return false
 body.global_transform=Transform3D(Basis.IDENTITY,at); body.force_update_transform()
 PhysicsServer3D.body_set_state(body.get_rid(),PhysicsServer3D.BODY_STATE_TRANSFORM,body.global_transform)
 body.linear_velocity=Vector3.ZERO; body.angular_velocity=Vector3.ZERO; body.hold_height=at.y; body.safe_position=at
 report.poses.append({"at":at,"only_initial_PLAYER_fixture":true,"before_any_loaded_flight":true})
 return await _frames(2)

func _bind(empty: bool) -> bool:
 driver.pilot=EmptyPilot.new() if empty else Pilot.new()
 serial=0
 if not _check(driver.pilot.bind(session.players[1]),"bind original canonical loaded / QA unloaded command pilot",{"empty":empty}): return false
 serial+=1; driver.enabled=true
 return driver.pilot.go_to(session.players[1].global_position,serial)

func _fly(at: Vector3,label: String,budget: int) -> bool:
 serial+=1
 if not _check(driver.pilot.go_to(at,serial),"original Pilot accepts "+label,at): return false
 var deadline: int=mini(began+170000,Time.get_ticks_msec()+budget)
 var best: float=session.players[1].global_position.distance_to(at)
 var progress: int=Time.get_ticks_msec()
 while Time.get_ticks_msec()<deadline:
  if not await _frames(1): return false
  var body: FlightBodyV2=session.players[1]
  var distance: float=body.global_position.distance_to(at)
  if distance<.4 and body.linear_velocity.length()<.35:
   report.route.append({"label":label,"at":body.global_position,"speed":body.linear_velocity.length(),"loaded":not body.cargo_items.is_empty()}); return true
  if distance<best-.1: best=distance; progress=Time.get_ticks_msec()
  if Time.get_ticks_msec()-progress>10000: return _check(false,"bounded original Pilot route stall "+label,driver.pilot.report())
 return _check(false,"original route deadline "+label,driver.pilot.report())

func _assist(budget: int) -> bool:
 if not await _frames(3): return false # Original action can queue for capture boundary.
 var deadline: int=Time.get_ticks_msec()+budget
 while not str(_module().status().assist).is_empty() and Time.get_ticks_msec()<deadline:
  if not await _frames(1): return false
 var status: Dictionary=_module().status()
 return _check(str(status.assist).is_empty() and status.ready and _custody().get("fault","")=="","original assistance relinquishes command; downstream native outcome remains mandatory",status)

func _press_g(target: String) -> void:
 session.network.send_action("lock",{"target_id":target})
 _g()
func _g() -> void:
 var key:=InputEventKey.new(); key.physical_keycode=KEY_G; key.keycode=KEY_G; key.pressed=true
 session._unhandled_input(key); key.pressed=false; session._unhandled_input(key)
func _dismiss() -> bool:
 for unused in 16:
  if not session.interface.radio.visible: return true
  _g()
  if not await _frames(1): return false
 return _check(false,"bounded original G dismisses dialogue")

func _contact(label: String) -> bool:
 if not await _dismiss() or not await _idle_gate(): return false
 if not _check(session.players[1].cargo_items.is_empty(),"unloaded-only QA interception"): return false
 var deadline: int=mini(began+172000,Time.get_ticks_msec()+18000)
 var next_command := 0
 var fresh: Dictionary={}
 while Time.get_ticks_msec()<deadline:
  fresh=Contact.prepare(session,1,ACTOR)
  if fresh.get("ok",false) and session.players[1].global_position.distance_to(fresh.position)<=3.0: break
  if Time.get_ticks_msec()>=next_command:
   var actor: Dictionary=session.ecology.simulation.get_actor(ACTOR)
   var point: Vector3=session.world.to_global(Anchors.local_position(actor))
   serial+=1
   if not driver.pilot.go_to(point+Vector3(0,1.5,2),serial): return _check(false,"unloaded interception command accepted")
   next_command=Time.get_ticks_msec()+500
  if not await _frames(1): return false
 if not _check(fresh.get("ok",false) and session.players[1].global_position.distance_to(fresh.position)<=3.0,"actual unloaded Flight intercepts NPC with original Contact/range/LOS: "+label,fresh.get("code","")): return false
 if not await _idle_gate(): return false
 fresh=Contact.prepare(session,1,ACTOR)
 if not _check(fresh.get("ok",false),"Contact still valid at actual capture request boundary",fresh.get("code","")): return false
 serial+=1; driver.pilot.go_to(session.players[1].global_position,serial) # Brake COMMAND, no pose/velocity assignment.
 session.network.send_action("explore",{"target_id":ACTOR})
 deadline=Time.get_ticks_msec()+5000
 while not session.interface.radio.visible and Time.get_ticks_msec()<deadline:
  if not await _frames(1): return false
 if not _check(session.interface.radio.visible,"original Story dialogue after physical contact "+label): return false
 var lines: Array=[session.interface.radio_text.text]
 for line: Dictionary in session.interface.radio_queue: lines.append(line.text)
 report.dialogues.append({"label":label,"lines":lines,"at":session.players[1].global_position})
 return await _dismiss()

func _idle_gate() -> bool:
 var deadline: int=Time.get_ticks_msec()+5000
 while session.environment_save_gate.pending() and Time.get_ticks_msec()<deadline:
  if not await _frames(1): return false
 return _check(not session.environment_save_gate.pending(),"previous original capture completed")
func _wait_status(expected: String,budget: int) -> bool:
 var deadline: int=mini(began+173000,Time.get_ticks_msec()+budget)
 while _row().get("status","")!=expected and Time.get_ticks_msec()<deadline:
  if not await _frames(1): return false
 return _check(_row().get("status","")==expected,"real sidejob reaches "+expected,_row())

func _frames(count: int) -> bool:
 for unused in count:
  await physics_frame; await process_frame
  if Time.get_ticks_msec()-began>=178000:
   expired=true; return _check(false,"178s exercise bound reserves original audio teardown within180s",{"phase":phase})
  if not logger.errors.is_empty(): return false
  if is_instance_valid(session) and session.active:
   if not session.players.has(1) or not session.players[1].enabled: return _check(false,"actual player remains enabled")
   if flight_started:
    var body: FlightBodyV2=session.players[1]
    var step: float=last_position.distance_to(body.global_position)
    flown+=step; max_step=maxf(max_step,step); last_position=body.global_position
    if step>2.0: return _check(false,"no post-LOW authored or unexplained pose jump",step)
    if not body.cargo_items.is_empty(): loaded_frames+=1
   for item: Dictionary in session.sidejobs._events:
    var event: Dictionary=item.proof
    var id: String=str(event.get("event_id",""))
    if event.get("actor_id")==ACTOR and not emitted.has(id):
     if emitted.size()>=8: return _check(false,"bounded native inspection evidence")
     emitted[id]=event.duplicate(true); report.native_events.append(event.duplicate(true))
  if Time.get_ticks_msec()-last_progress>=10000:
   last_progress=Time.get_ticks_msec(); print("NPC_I3_PROGRESS "+JSON.stringify({"phase":phase,"seconds":float(last_progress-began)/1000.0,"job":_row() if is_instance_valid(session) else {}}))
 return not expired and not finished

func _readback() -> bool:
 if not await _idle_gate(): return false
 var callbacks: Array=[]
 var requested: Dictionary=session.request_environment_save(func(row: Dictionary): callbacks.append(row.duplicate(true)))
 if not _check(requested.get("ok",false),"original final SaveGate accepts request"): return false
 var deadline: int=Time.get_ticks_msec()+6000
 while callbacks.is_empty() and Time.get_ticks_msec()<deadline:
  if not await _frames(1): return false
 if not _check(not callbacks.is_empty() and callbacks[-1].get("ok",false) and callbacks[-1].get("completed",false),"original final SaveGate succeeds",callbacks): return false
 var live: Dictionary=session.store.snapshot()
 var reader=Store.new(session.store.root_path)
 var loaded: Dictionary=reader.load_profile()
 var disk: Dictionary=reader.snapshot()
 report["save"]={"loaded":loaded,"generation":disk.generation,"profile_id":disk.profile_id,"lineage_id":disk.lineage_id,"job":disk.world.get("npc_sidejobs_v1",{}).get("jobs",{}).get(JOB,{}),"discovery_count":disk.personal.discoveries.count(REWARD),"cargo_proof":disk.world.get("environment",{}).get("I3_thermal_cargo",{}).get("proof",{})}
 return _check(loaded.get("ok",false) and not loaded.get("recovered",false) and session.store.matches_persisted_value(live,disk) and disk.profile_id==initial.profile_id and disk.lineage_id==initial.lineage_id and disk.personal.discoveries.count(REWARD)==1 and session.story.state==initial_story and disk.world.get("actions",{})==initial.world.get("actions",{}) and disk.world.flags==initial.world.flags and disk.world.choices==initial.world.choices and disk.world.completed_objectives==initial.world.completed_objectives,"fresh original Reader exactly matches committed sidejob/cargo/identity; original prefix/flags unchanged")

func _phase(value: String) -> void: phase=value; print("NPC_I3_PHASE "+value)
func _finish(ok: bool) -> void:
 if finished: return
 finished=true
 if is_instance_valid(driver):
  if driver.pilot!=null: report["last_pilot"]=driver.pilot.report()
  driver.enabled=false; driver.owner_session=null; driver.free()
 if is_instance_valid(session):
  report["last_job"]=_row().duplicate(true)
  report["npc_at_finish"]=session.ecology.simulation.get_actor(ACTOR)
  if session.players.has(1): report["player_at_finish"]={"at":session.players[1].global_position,"velocity":session.players[1].linear_velocity,"enabled":session.players[1].enabled}
  if session.thermal_cargo.supported(): report["cargo_status"]=_module().status()
  report["last_commit"]=session.last_commit_result.duplicate(true)
 await _retire()
 report["engine_errors"]=logger.errors
 report["failures"]=report.checks.filter(func(row: Dictionary): return not row.passed)
 report["complete"]=ok and not expired and report.failures.is_empty() and logger.errors.is_empty()
 report["phase"]=phase; report["wall_seconds"]=float(Time.get_ticks_msec()-began)/1000.0
 report["actual_flown_m"]=flown; report["max_step_m_after_initial_pose"]=max_step; report["loaded_frames"]=loaded_frames
 if report.wall_seconds>180.0: report["complete"]=false; report["deadline_overrun"]=true
 var text: String=JSON.stringify(_plain(report),"\t",true,true)
 if text.to_utf8_buffer().size()>64*1024: print("NPC_I3_REPORT_LIMIT_FAIL"); quit(1); return
 var file:=FileAccess.open(output+"/result.json",FileAccess.WRITE)
 var written: bool=file!=null
 if file!=null: file.store_string(text); file.flush(); written=file.get_error()==OK; file.close()
 print("NPC_I3_RESULT "+JSON.stringify({"complete":report.complete,"written":written,"phase":phase,"seconds":report.wall_seconds,"errors":logger.errors.size()}))
 quit(0 if report.complete and written else 1)
