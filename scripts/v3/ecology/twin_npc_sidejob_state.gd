extends RefCounted
## Bounded PURE state proposals. No Node/Input/Store/Director/simulation access.
const PATH := "world.npc_sidejobs_v1"
const MAX_ACTIVE := 4
const MAX_INTEGER := 9007199254740000
const SPECS := {
 "sidejob:I1:cooling_handoff":{"region":"I1","npc":"I1:water_01","load":"I1:water_service","arrival":"I1:maintenance_cooling","reward":"npc_sidejob:I1:cooling_handoff"},
 "sidejob:I2:service_handoff":{"region":"I2","npc":"I2:service_01","load":"I2:service_supply","arrival":"I2:service_receiver","reward":"npc_sidejob:I2:service_handoff"},
 "sidejob:F2:two_mirror_watch":{"region":"F2","npc":"F2:lamp_01","reward":"npc_sidejob:F2:two_mirror_watch"},
 "sidejob:I3:dock_recheck":{"region":"I3","npc":"I3:coolant_01","reward":"npc_sidejob:I3:dock_recheck"}}
const ROW_KEYS := ["status","accepted_by","accept_ecology","accept_mechanism","load_id","load_serial","load_cycle","witnessed","work_id","work_serial","work_ecology","aux_id","aux_serial","reward_id"]

static func defaults() -> Dictionary:
 return {"schema_version":1,"revision":0,"jobs":{}}

static func restore(raw: Variant) -> Dictionary:
 if raw is Dictionary and raw.is_empty(): return {"ok":true,"state":defaults()}
 if not raw is Dictionary or raw.size()!=3 or raw.get("schema_version")!=1 or not _number(raw.get("revision")) or not raw.get("jobs") is Dictionary or raw.jobs.size()>4: return _no("sidejob_state_invalid")
 var state: Dictionary=raw.duplicate(true)
 state.revision=int(state.revision)
 for id: Variant in state.jobs:
  if not id is String or not SPECS.has(id) or not _row(state.jobs[id],SPECS[id]): return _no("sidejob_row_invalid")
  for key: String in ["accept_ecology","accept_mechanism","load_serial","load_cycle","work_serial","work_ecology","aux_serial"]: state.jobs[id][key]=int(state.jobs[id][key])
 return {"ok":true,"state":state}

static func propose(raw: Variant,id: String,kind: String,e: Dictionary) -> Dictionary:
 var restored: Dictionary=restore(raw)
 if not restored.ok or not SPECS.has(id): return _no("sidejob_or_state_invalid")
 var before: Dictionary=restored.state
 var next: Dictionary=before.duplicate(true)
 var spec: Dictionary=SPECS[id]
 if kind=="accept":
  if spec.region=="I2" and e.get("service_ready")!=true: return _no("canal_service_not_restored")
  if next.jobs.has(id): return _yes(before,before,"already_started")
  if not _text(e.get("identity")) or not _number(e.get("ecology_serial")) or not _number(e.get("mechanism_tick")): return _no("accept_source_invalid")
  var active:=0
  for row: Dictionary in next.jobs.values():
   if row.status!="complete": active+=1
  if active>=MAX_ACTIVE: return _no("active_limit")
  next.jobs[id]={"status":"active","accepted_by":e.identity,"accept_ecology":int(e.ecology_serial),"accept_mechanism":int(e.mechanism_tick),"load_id":"","load_serial":0,"load_cycle":0,"witnessed":false,"work_id":"","work_serial":0,"work_ecology":0,"aux_id":"","aux_serial":0,"reward_id":""}
  return _yes(before,next,"accepted")
 if not next.jobs.has(id): return _no("not_started")
 var row: Dictionary=next.jobs[id]
 if row.status=="complete": return _yes(before,before,"already_complete")
 if kind=="ecology" and row.status=="active":
  if not _event(e,spec) or int(e.serial)<=int(row.accept_ecology): return _yes(before,before,"irrelevant_event")
  if spec.has("load"):
   if e.kind=="cargo_loaded" and e.target_id==spec.load and int(e.serial)>int(row.load_serial):
    row.load_id=e.event_id; row.load_serial=int(e.serial); row.load_cycle=int(e.cycle); row.witnessed=false
   elif e.kind=="transport_arrival" and e.target_id==spec.arrival and row.witnessed and not row.load_id.is_empty() and int(e.cycle)==int(row.load_cycle) and int(e.serial)>int(row.load_serial):
    row.status="ready"; row.work_id=e.event_id; row.work_serial=int(e.serial)
  elif spec.region=="I3" and not row.work_id.is_empty() and e.kind=="inspection_complete" and e.target_id=="I3:loaded_dock" and int(e.serial)>int(row.work_ecology):
   row.status="ready"; row.aux_id=e.event_id; row.aux_serial=int(e.serial)
 elif kind=="witness" and spec.has("load") and row.status=="active":
  if not row.load_id.is_empty() and e.get("cargo")==true and _number(e.get("cycle")) and int(e.cycle)==int(row.load_cycle): row.witnessed=true
 elif kind=="optical" and spec.region=="F2" and row.status=="active":
  if e.get("valid")==true and e.get("source_on")==true and e.get("code")=="receiver_front" and e.get("segments")==3 and e.get("turns")==2 and e.get("mirror_ids")==["F2:clock_mirror","F2:clock_mirror_bypass"] and _number(e.get("tick")) and int(e.tick)>int(row.accept_mechanism) and _digest(e.get("proof_id")):
   row.status="ready"; row.work_id=e.proof_id; row.work_serial=int(e.tick)
 elif kind=="cargo" and spec.region=="I3" and row.status=="active":
  if e.get("cargo_id")=="I3:loaded_cassette" and e.get("berth")=="I3:high_dock" and e.get("phase")=="docked" and e.get("mass_grams")==2000 and e.get("route") in ["outer_corridor","updraft"] and _number(e.get("serial"),1) and _number(e.get("ecology_serial")) and _digest(e.get("proof_id")):
   if row.work_id!=e.proof_id:
    row.work_id=e.proof_id; row.work_serial=int(e.serial); row.work_ecology=int(e.ecology_serial)
 elif kind=="claim" and row.status=="ready":
  if spec.region=="I1" and (e.get("cooling_safe")!=true or not _number(e.get("coolant"),1) or int(e.coolant)>3): return _yes(before,before,"cooling_not_ready")
  if spec.region=="I2" and e.get("clinic_ready")!=true: return _yes(before,before,"clinic_not_ready")
  if spec.region=="I3" and (e.get("cargo_live")!=true or e.get("cargo_proof_id")!=row.work_id): return _yes(before,before,"cargo_not_currently_verified")
  row.status="complete"; row.reward_id=spec.reward
  return _yes(before,next,"completed",str(spec.reward))
 return _yes(before,next,"observed")

static func projection(raw: Variant) -> Dictionary:
 var loaded: Dictionary=restore(raw)
 if not loaded.ok: return loaded
 var rows: Dictionary={}
 for id: String in loaded.state.jobs:
  var row: Dictionary=loaded.state.jobs[id]
  rows[id]={"status":row.status,"carrying_witnessed":row.witnessed,"primary_verified":not row.work_id.is_empty()}
 return {"ok":true,"schema_version":1,"revision":loaded.state.revision,"jobs":rows}

static func completed_rewards(raw: Variant) -> Array:
 var loaded: Dictionary=restore(raw)
 var rewards: Array=[]
 if not loaded.ok: return rewards
 for id: String in loaded.state.jobs:
  if loaded.state.jobs[id].status=="complete": rewards.append(SPECS[id].reward)
 return rewards

static func _yes(before: Dictionary,next: Dictionary,code: String,discovery: String="") -> Dictionary:
 var changed: bool=before.jobs!=next.jobs
 if changed:
  if int(before.revision)>=MAX_INTEGER: return _no("sidejob_revision_limit")
  next.revision=int(before.revision)+1
  var checked: Dictionary=restore(next)
  if not checked.ok: return checked
  next=checked.state
 return {"ok":true,"changed":changed,"code":code,"state":next.duplicate(true),"set":{PATH:next.duplicate(true)} if changed else {},"discovery":discovery}

static func _event(e: Dictionary,spec: Dictionary) -> bool:
 return _text(e.get("event_id")) and str(e.event_id).begins_with("ecology:") and _number(e.get("serial"),1) and _number(e.get("cycle")) and e.get("actor_id")==spec.npc and e.get("region_id")==spec.region and e.get("kind") in ["cargo_loaded","transport_arrival","inspection_complete"] and _text(e.get("target_id"))

static func _row(value: Variant,spec: Dictionary) -> bool:
 if not value is Dictionary or value.size()!=ROW_KEYS.size() or not value.has_all(ROW_KEYS) or value.status not in ["active","ready","complete"] or not _text(value.accepted_by) or not value.witnessed is bool: return false
 for key: String in ["accept_ecology","accept_mechanism","load_serial","load_cycle","work_serial","work_ecology","aux_serial"]:
  if not _number(value[key]): return false
 for key: String in ["load_id","work_id","aux_id","reward_id"]:
  if not value[key] is String or value[key].length()>200: return false
 if not value.load_id.is_empty() and (not spec.has("load") or int(value.load_serial)<=int(value.accept_ecology)): return false
 if value.witnessed and value.load_id.is_empty(): return false
 if value.status in ["ready","complete"]:
  if value.work_id.is_empty() or int(value.work_serial)<1: return false
  if spec.has("load") and (not value.witnessed or int(value.work_serial)<=int(value.load_serial)): return false
  if spec.region=="F2" and (not _digest(value.work_id) or int(value.work_serial)<=int(value.accept_mechanism)): return false
  if spec.region=="I3" and (not _digest(value.work_id) or value.aux_id.is_empty() or int(value.aux_serial)<=maxi(int(value.accept_ecology),int(value.work_ecology))): return false
 return value.reward_id==spec.reward if value.status=="complete" else value.reward_id.is_empty()

static func _number(value: Variant,minimum: int=0) -> bool:
 return (value is int or value is float) and is_finite(float(value)) and float(value)>=minimum and float(value)<=MAX_INTEGER and floor(float(value))==float(value)
static func _text(value: Variant) -> bool:
 return value is String and not value.is_empty() and value.length()<=200
static func _digest(value: Variant) -> bool:
 if not value is String or value.length()!=64: return false
 for index: int in 64:
  if value.substr(index,1) not in "0123456789abcdef": return false
 return true
static func _no(code: String) -> Dictionary:
 return {"ok":false,"changed":false,"code":code}
