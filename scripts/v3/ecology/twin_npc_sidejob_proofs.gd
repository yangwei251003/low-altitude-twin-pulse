extends RefCounted
## Read-only Host collectors. Call only from original authority callbacks, never RPC payloads.
const OpticalPath = preload("res://scripts/v3/campaign/twin_optical_path.gd")
const Cargo = preload("res://scripts/v3/gameplay/twin_thermal_cargo_session.gd")

static func baseline(session) -> Dictionary:
 if not _host(session): return {}
 var ecological: Dictionary=session.ecology.simulation.snapshot()
 var tick:=0
 if session.campaign.mechanisms!=null: tick=int(session.campaign.mechanisms.persistent_state().get("tick",0))
 return {"ecology_serial":int(ecological.event_serial),"mechanism_tick":tick,"service_ready":bool(session.world_cache.world.get("flags",{}).get("I2:canal_service_ready",false))}

static func optical(session) -> Dictionary:
 if not _host(session) or session.region_id!="F2" or session.campaign.mechanisms==null: return {}
 var ids: Array=["F2:clock_source","F2:clock_mirror","F2:clock_mirror_bypass","F2:clock_receiver"]
 for id: String in ids:
  if not session.world.objects.get(id) is PhysicsBody3D: return {}
 var active: float=float(session.entities.get(ids[0],{}).get("light_level",0.0))
 if not is_finite(active) or active<.5: return {}
 var path: Dictionary=OpticalPath.trace(session.world,session.world.objects[ids[0]],session.world.objects[ids[1]],session.world.objects[ids[3]],session.world.objects[ids[2]])
 if not path.get("valid",false) or path.get("code")!="receiver_front" or path.segments.size()!=3 or path.turns!=2: return {}
 var mirrors: Array=[]
 var signature: Array=[]
 for hit: Dictionary in path.mirror_hits: mirrors.append(hit.id)
 if mirrors!=[ids[1],ids[2]]: return {}
 for pair: Array in path.segments:
  for point: Vector3 in pair: signature.append([point.x,point.y,point.z])
 var tick: int=session.campaign.mechanisms.persistent_state().tick
 return {"valid":true,"source_on":true,"code":path.code,"segments":3,"turns":2,"mirror_ids":mirrors,"tick":tick,"proof_id":JSON.stringify(signature,"",true,true).sha256_text()}

static func cargo(session) -> Dictionary:
 if not _host(session) or session.region_id!="I3" or not session.thermal_cargo.supported(): return {}
 # Original capture validates the native custody/pose; no coercion or fabricated fact.
 var captured: Dictionary=session.thermal_cargo.capture()
 if not captured.get("ok",false) or not captured.has("state"): return {}
 var state: Dictionary=captured.state
 if state.get("version")!=1 or state.get("cargo_id")!=Cargo.CARGO or state.get("proof",{}).is_empty(): return {}
 var proof: Dictionary=state.proof
 var row: Dictionary=state.custody.get("cargos",{}).get(Cargo.CARGO,{})
 var body: Variant=session.world.objects.get(Cargo.CARGO)
 if not body is RigidBody3D or body.mass!=2.0 or row.get("phase")!="docked" or row.get("berth")!=Cargo.HIGH: return {}
 var native: Variant=PhysicsServer3D.body_get_state(body.get_rid(),PhysicsServer3D.BODY_STATE_TRANSFORM)
 if not native is Transform3D or not native.is_equal_approx(body.global_transform) or body.get_world_3d()!=session.world.get_world_3d(): return {}
 if proof.get("cargo_id")!=Cargo.CARGO or proof.get("completed_serial")!=row.get("completed_serial") or proof.get("release_serial")!=row.get("serial") or proof.get("route") not in ["outer_corridor","updraft"]: return {}
 var stable: Array=[str(proof.cargo_id),str(proof.route)]
 for key: String in ["version","pickup_serial","release_serial","completed_serial","frames_observed","outer_progress","updraft_ticks","updraft_rise_mm"]: stable.append(int(proof[key]))
 return {"cargo_id":Cargo.CARGO,"berth":Cargo.HIGH,"phase":"docked","mass_grams":2000,"route":proof.route,"serial":int(proof.completed_serial),"ecology_serial":int(session.ecology.simulation.snapshot().event_serial),"proof_id":JSON.stringify(stable,"",true,true).sha256_text()}

static func claim_context(session) -> Dictionary:
 if not _host(session): return {}
 if session.region_id=="I1":
  var temperature: float=float(session.entities.get("I1:thermal",{}).get("temperature",20))
  return {"cooling_safe":is_finite(temperature) and temperature<85.0,"coolant":int(session.ecology.facilities.coolant)}
 if session.region_id=="I2":
  if not session.clinic.ready or not is_instance_valid(session.clinic.module): return {}
  var status: Dictionary=session.clinic.module.status()
  var history: Dictionary=session.clinic.progress.snapshot()
  var good: bool=bool(history.get("commissioned",false)) and status.get("clinic_volume_ml")==status.get("target_volume_ml") and float(status.get("clean_fraction",0))>=.95 and status.get("inlet_closed")==true and status.get("platform_blocked")==false and session.clinic.access_clear()
  return {"clinic_ready":good}
 if session.region_id=="I3":
  var live: Dictionary=cargo(session)
  return {"cargo_live":not live.is_empty(),"cargo_proof_id":live.get("proof_id","")}
 return {}

static func ecology_event(session,event: Dictionary,emission_branch: String) -> Dictionary:
 if not _host(session) or emission_branch!=str(session.world_cache.world.branch_id): return {}
 # Current-region observations only; background/offline history is never replayed.
 if event.get("region_id")!=session.region_id: return {}
 var current: Dictionary=session.ecology.simulation.snapshot()
 if not event.get("serial") is int or int(event.serial)>int(current.event_serial) or int(event.serial)<1: return {}
 var expected: String="ecology:%s:%d:%d" % [str(current.content_id),int(current.seed),int(event.serial)]
 if event.get("event_id")!=expected: return {}
 return event.duplicate(true) # Native batch has only JSON values; never a client event.

static func _host(session) -> bool:
 return is_instance_valid(session) and session.active and session.owns_world and session.network.is_authority() and not session.simulation_paused and session.ecology.ready and is_instance_valid(session.world)
