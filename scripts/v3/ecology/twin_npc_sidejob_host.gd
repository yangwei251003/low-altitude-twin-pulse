extends RefCounted
## Four optional jobs only. Sole writes go through original Session Gate/_commit.
const Model = preload("res://scripts/v3/ecology/twin_npc_sidejob_state.gd")
const Proofs = preload("res://scripts/v3/ecology/twin_npc_sidejob_proofs.gd")
const Contact = preload("res://scripts/v3/ecology/twin_npc_contact.gd")
const KIND := "npc_sidejob_state_v1"
var session
var labels: Callable
var definitions: Dictionary={}
var error: String=""
var _offers: Dictionary={}
var _events: Array=[]
var _context: String=""
var _serial:=0
var _remote_serial:=-1
var _remote: Dictionary={}
var _pending_projection: Dictionary={}
var _last_optical_tick:=-1

func setup(owner_session,key_labels: Callable) -> bool:
 session=owner_session; labels=key_labels
 for region: String in ["i1","i2","f2","i3"]:
  var parsed: Variant=JSON.parse_string(FileAccess.get_file_as_string("res://data/v3/campaign/npc_sidejob_"+region+".json"))
  if not parsed is Dictionary or not Model.SPECS.has(parsed.get("id","")) or parsed.get("schema_version")!=1 or not parsed.get("steps") is Array or parsed.steps.size()!=3:
   error="sidejob_definition_invalid"; return false
  definitions[parsed.id]=parsed
 return definitions.size()==4

func reset_connection() -> void:
 clear_transient(); _serial=0; _remote_serial=-1; _remote.clear(); _pending_projection.clear()

func forget_peer(peer: int) -> void:
 _offers.erase(peer)

func clear_transient() -> void:
 _offers.clear(); _events.clear(); _context=""; _last_optical_tick=-1

func contact(peer: int,reply: Dictionary) -> bool:
 if not _host() or not error.is_empty(): return false
 _refresh_context()
 var id:=_job(str(reply.source_actor_id))
 if id.is_empty(): return false
 var loaded: Dictionary=_state()
 if not loaded.ok: session._note(peer,"可选委托记录暂不可用，原记录已保留。"); return true
 if not loaded.state.jobs.has(id) and _offers.get(peer,"")!=id:
  _offers[peer]=id
  _say(peer,reply,[definitions[id].offer,"这是可选委托。逐句结束后，再次靠近按{contact}才接下；离开不接单。"])
  return true
 var kind: String="accept" if not loaded.state.jobs.has(id) else ("claim" if loaded.state.jobs[id].status=="ready" else "witness")
 _offers.erase(peer)
 var actor_id: String=reply.source_actor_id
 var operation:=func() -> bool:
  if not _host(): return false
  var fresh: Dictionary=Contact.prepare(session,peer,actor_id)
  if not fresh.get("ok",false): return false
  var current: Dictionary=_state()
  if not current.ok: return false
  var evidence: Dictionary=Proofs.baseline(session) if kind=="accept" else Proofs.claim_context(session)
  if kind=="accept": evidence.identity=str(session.identities.get(peer,session.world_cache.profile_id))
  elif kind=="witness":
   var actor: Dictionary=session.ecology.simulation.get_actor(actor_id)
   evidence={"cargo":fresh.cargo,"cycle":int(actor.get("cycles",0))}
  var proposed: Dictionary=Model.propose(current.state,id,kind,evidence)
  if not proposed.ok:
   session._note(peer,"南湾工序服务尚未恢复，这条委托先保留。" if proposed.code=="canal_service_not_restored" else "可选委托记录暂不能确认，原进度没有改变。")
   return true
  if proposed.changed and not session._commit("npc-sidejob:"+id+":"+kind,proposed.set,proposed.discovery): return false
  if proposed.changed: publish()
  var row: Dictionary=proposed.state.jobs.get(id,{})
  var lines: Array=[]
  if row.get("status")=="complete": lines=[definitions[id].consequence]
  elif row.get("status")=="ready": lines=[definitions[id].ready]
  elif kind=="accept": lines=["已接下可选委托："+str(definitions[id].title),definitions[id].work_hint]
  elif row.get("witnessed",false): lines=["本轮带货已核对。请跟到交接处，再来联络。"]
  else: lines=[definitions[id].work_hint]
  # Only first transitions, after the original Store commit has succeeded.
  var cue: String="interaction"
  if proposed.changed and proposed.code=="accepted": cue="task_step"
  elif proposed.changed and proposed.code=="completed": cue="task_complete"
  _say(peer,fresh,lines,cue)
  return true
 _gate(operation,peer)
 return true

func ecology_batch(batch: Array,branch: String) -> void:
 if not _host() or not error.is_empty(): return
 _refresh_context()
 var loaded: Dictionary=_state()
 if not loaded.ok: return
 for event: Dictionary in batch:
  var id:=_job(str(event.get("actor_id","")))
  if id.is_empty() or not loaded.state.jobs.has(id) or loaded.state.jobs[id].status!="active": continue
  var spec: Dictionary=Model.SPECS[id]
  var row: Dictionary=loaded.state.jobs[id]
  if spec.has("load"):
   var relevant: bool=event.get("kind")=="cargo_loaded" and event.get("target_id")==spec.load or event.get("kind")=="transport_arrival" and event.get("target_id")==spec.arrival and row.witnessed
   if not relevant: continue
  elif spec.region!="I3" or row.work_id.is_empty() or event.get("kind")!="inspection_complete" or event.get("target_id")!="I3:loaded_dock": continue
  var proof: Dictionary=Proofs.ecology_event(session,event,branch)
  if proof.is_empty(): continue
  if _events.size()>=16:
   error="sidejob_event_budget"; session._note_all("可选委托事件暂未记录；已保存进度保留，本次不补记完成。"); return
  _events.append({"job":id,"proof":proof})

func advance() -> void:
 if not _host() or not error.is_empty() or session.environment_save_gate.pending(): return
 _refresh_context()
 var loaded: Dictionary=_state()
 if not loaded.ok: return
 var optical_needed:=false
 var cargo_needed:=false
 var f2: String="sidejob:F2:two_mirror_watch"
 var i3: String="sidejob:I3:dock_recheck"
 if session.region_id=="F2" and loaded.state.jobs.get(f2,{}).get("status")=="active" and session.campaign.mechanisms!=null:
  var view: Dictionary=session.campaign.mechanisms.view_state()
  var tick: int=session.campaign.mechanisms.persistent_state().tick
  optical_needed=bool(view.get("beam_valid",false)) and view.get("beam_segments",[]).size()==3 and tick!=_last_optical_tick
  if optical_needed: _last_optical_tick=tick
 if session.region_id=="I3" and loaded.state.jobs.get(i3,{}).get("status")=="active" and loaded.state.jobs[i3].work_id.is_empty():
  cargo_needed=not session.thermal_cargo.fact("I3:loaded_dock_verified").is_empty()
 if _events.is_empty() and not optical_needed and not cargo_needed: return
 var captured_context: String=_context
 var count: int=_events.size()
 var batch: Array=_events.slice(0,count).duplicate(true)
 var operation:=func() -> bool:
  if not _host() or captured_context!=_context_key(): return false
  var current: Dictionary=_state()
  if not current.ok: return false
  var candidate: Dictionary=current.state
  if cargo_needed:
   var cargo: Dictionary=Proofs.cargo(session)
   if not cargo.is_empty():
    var step: Dictionary=Model.propose(candidate,i3,"cargo",cargo)
    if not step.ok: return false
    candidate=step.state
  if optical_needed:
   var optical: Dictionary=Proofs.optical(session)
   if not optical.is_empty():
    var step: Dictionary=Model.propose(candidate,f2,"optical",optical)
    if not step.ok: return false
    candidate=step.state
  for item: Dictionary in batch:
   var step: Dictionary=Model.propose(candidate,item.job,"ecology",item.proof)
   if not step.ok: return false
   candidate=step.state
  if candidate!=current.state and not session._commit("npc-sidejob-observe",{Model.PATH:candidate}): return false
  for unused in count: _events.pop_front()
  if candidate!=current.state: publish()
  return true
 _gate(operation)

func _gate(operation: Callable,peer: int=0) -> void:
 # Existing I2/I3 explore can already be inside the original ready capture barrier.
 if session._canal_action_in_capture:
  if not operation.call() and peer>0: session._note(peer,"可选委托保存未完成，尚未发奖。")
  return
 if session.environment_save_gate.pending():
  if peer>0: session._note(peer,"现场正在保存，请稍后再联络；这次尚未确认。")
  return
 session.environment_save_gate.request(operation,func(result: Dictionary):
  if not result.get("ok",false) and peer>0: session._note(peer,"可选委托保存未完成，尚未发奖。"))

func publish(peer: int=0) -> void:
 if not _authority(): return
 var projected: Dictionary=Model.projection(_raw())
 if not projected.ok: return
 if peer==0 or _serial==0: _serial+=1
 var event: Dictionary={"kind":KIND,"session_id":session.network.session_id,"serial":maxi(1,_serial),"branch_id":str(session.world_cache.world.branch_id),"state":projected}
 if peer>1: session.network.send_event(peer,event)
 else:
  for id in session.network.guests: session.network.send_event(int(id),event)

func receive(event: Dictionary) -> void:
 if session.network.mode!="guest" or not session.active or event.get("kind")!=KIND or str(event.get("session_id","")).is_empty(): return
 if not session.received_session.is_empty() and event.session_id!=session.received_session: return
 if not _counter(event.get("serial")) or int(event.serial)<=_remote_serial or not event.get("state") is Dictionary: return
 var data: Dictionary=event.state
 if data.get("schema_version")!=1 or not _counter(data.get("revision")) or not data.get("jobs") is Dictionary or data.jobs.size()>4: return
 for id: Variant in data.jobs:
  if not id is String or not Model.SPECS.has(id) or not data.jobs[id] is Dictionary: return
  var row: Dictionary=data.jobs[id]
  if row.size()!=3 or row.get("status") not in ["active","ready","complete"] or not row.get("carrying_witnessed") is bool or not row.get("primary_verified") is bool: return
 if not _pending_projection.is_empty() and _pending_projection.session_id==event.session_id and int(event.serial)<=int(_pending_projection.serial): return
 _pending_projection=event.duplicate(true)
 consume_projection()

func consume_projection() -> void:
 if session.network.mode!="guest" or not session.active or session.received_session.is_empty() or _pending_projection.is_empty(): return
 if _pending_projection.session_id!=session.received_session:
  _pending_projection.clear(); return
 if int(_pending_projection.serial)>_remote_serial:
  _remote_serial=int(_pending_projection.serial)
  _remote=_pending_projection.state.duplicate(true) # Display only; never Store/propose.
 _pending_projection.clear()

func completed_rewards() -> Array:
 return Model.completed_rewards(_raw()) if _authority() else []

func render_lines(lines: Array) -> Array:
 var keys: Dictionary=labels.call() if labels.is_valid() else {}
 var result: Array=[]
 for raw: Variant in lines:
  if not raw is String: continue
  var line: String=raw
  for token: String in ["contact","ability","brake"]:
   line=line.replace("{"+token+"}",str(keys.get(token,"当前联络/能力/制动键")))
  result.append(line)
 return result

func display_rows() -> Array:
 var data: Dictionary=_remote if session.network.mode=="guest" else Model.projection(_raw())
 var rows: Array=[]
 for id: String in data.get("jobs",{}):
  if definitions.has(id): rows.append({"title":definitions[id].title,"region":Model.SPECS[id].region,"npc_id":Model.SPECS[id].npc,"status":data.jobs[id].status})
 return rows

func hint_text(region: String) -> String:
 var data: Dictionary=_remote if session.network.mode=="guest" else Model.projection(_raw())
 for id: String in data.get("jobs",{}):
  if not definitions.has(id) or Model.SPECS[id].region!=region: continue
  var row: Dictionary=data.jobs[id]
  if row.status=="complete": continue
  var detail: String="完成实际作业后联络委托人"
  if row.status=="ready": detail="靠近委托人按{contact}交接"
  elif Model.SPECS[id].has("load"): detail="等本轮到货" if row.carrying_witnessed else "找到本轮带货的同伴，按{contact}验货"
  elif region=="F2": detail="选择光束，调好两镜三段光路"
  elif region=="I3": detail="等巡检机完成高台复核" if row.primary_verified else "将2kg载荷送稳高台"
  return str(render_lines(["可选："+str(definitions[id].title)+" · "+detail])[0])
 return ""

func _say(peer: int,reply: Dictionary,extra: Array,cue: String="interaction") -> void:
 var lines: Array=reply.lines.duplicate()
 lines.append_array(extra)
 session.network.send_event(peer,{"kind":"dialogue","character_id":reply.character_id,"speaker_name":reply.speaker_name,"lines":lines,"sidejob_templates":true})
 session._audio_event(cue,reply.position,reply.source_actor_id)
func _raw() -> Variant:
 return session.world_cache.world.get("npc_sidejobs_v1",{})
func _state() -> Dictionary:
 return Model.restore(_raw())
func _job(actor: String) -> String:
 for id: String in Model.SPECS:
  if Model.SPECS[id].npc==actor: return id
 return ""
func _authority() -> bool:
 return is_instance_valid(session) and session.active and session.owns_world and session.network.is_authority()
func _host() -> bool:
 return _authority() and not session.simulation_paused and not session.boss_active and not session.pending_completion and session.consensus.current_proposal().is_empty()
func _context_key() -> String:
 return str(session.network.session_id)+":"+str(session.world_cache.world.branch_id)+":"+str(session.region_id)
func _refresh_context() -> void:
 var value:=_context_key()
 if value!=_context:
  _offers.clear(); _events.clear(); _last_optical_tick=-1; _context=value
func _counter(value: Variant) -> bool:
 return (value is int or value is float) and is_finite(float(value)) and float(value)>=0 and float(value)<=Model.MAX_INTEGER and floor(float(value))==float(value)
