class_name EncounterDirectorV22
extends Node
## Scheduling never commands acquisition/aim. Position clues come from actual
## noise or a confirmed scout report; pilot position is used only for fairness.
signal encounter_event(event: Dictionary)

const MAX_AMBIENT = 4
const MAX_TOTAL = 8
const MIN_ENTRY_DISTANCE = 45.0
const PROFILES = {
	"R1":{"gap_min":55.0,"gap_max":95.0,"roles":["scout","harasser"],"altitude":5.0,"direction":Vector3(1,0,0)},
	"R2":{"gap_min":45.0,"gap_max":90.0,"roles":["scout","harasser"],"altitude":5.5,"direction":Vector3(0,0,1)},
	"R3":{"gap_min":65.0,"gap_max":110.0,"roles":["scout","harasser","support"],"altitude":6.0,"direction":Vector3(-1,0,0)},
	"R4":{"gap_min":50.0,"gap_max":95.0,"roles":["scout","suppressor","support"],"altitude":7.0,"direction":Vector3(0,0,-1)}
}
var combat: Node3D
var world: Node3D
var pilot: Node3D
var region_id = "R2"
var enabled = true
var suppressed = false
# true means safely OUTSIDE camera coverage, including a margin. Darkness is not
# a substitute. If absent, the active viewport camera is checked conservatively.
var camera_guard: Callable
var phase = "rest"
var time_s = 0.0
var rest_left = 60.0
var alert = 0.0
var load_pressure = 0.0
var sequence = 0
var pending: Dictionary = {}
var registry: Dictionary = {}
var context = {"mission_reserved":0,"environment_warning":false,"service_active":false}
var _rng = RandomNumberGenerator.new()
var _profile: Dictionary
var _tick_accumulator = 0.0
var _noise_position = Vector3.ZERO
var _noise_age = 999.0
var _damage_age = 999.0
var _engagement_age = 999.0
var _reported_encounters: Dictionary = {}
var _seen_events: Array[String] = []
var _chunk_age: Dictionary = {}
var _configured = false

func configure(value_combat: Node3D, value_world: Node3D, value_pilot: Node3D, region: String, seed_value: int, is_enabled = true) -> void:
	combat=value_combat;world=value_world;pilot=value_pilot;region_id=region if PROFILES.has(region) else "R2";enabled=is_enabled
	_profile=PROFILES[region_id].duplicate(true);_rng.seed=seed_value
	rest_left=_rng.randf_range(float(_profile.gap_min),float(_profile.gap_max));_configured=true
	process_mode=Node.PROCESS_MODE_PAUSABLE

func set_context(value: Dictionary) -> void:
	for key in context:
		if value.has(key): context[key]=value[key]

func set_suppressed(value: bool) -> void:
	if value and not suppressed:
		_cancel_pending("suppressed")
		rest_left=maxf(rest_left,45.0)
	suppressed=value

func _physics_process(delta: float) -> void:
	advance(delta)

func advance(delta: float) -> void:
	if not _configured or not enabled or delta<=0 or not is_finite(delta): return
	if not is_instance_valid(combat) or not is_instance_valid(world) or not is_instance_valid(pilot): return
	if is_inside_tree() and get_tree().paused: return
	_tick_accumulator+=delta
	# Fixed director steps make random decisions independent of render frequency.
	while _tick_accumulator+.00000001>=.5:
		_tick_accumulator=maxf(0,_tick_accumulator-.5);_tick(.5)

func _tick(delta: float) -> void:
	time_s+=delta;_noise_age+=delta;_damage_age+=delta;_engagement_age+=delta
	alert=maxf(0,alert-delta*.012);load_pressure=maxf(0,load_pressure-delta*.025)
	rest_left=maxf(0,rest_left-delta)
	_refresh_registry();_refresh_chunks()
	var active_threats=_active_threat_count()
	if active_threats>0:
		phase="engaged";_engagement_age=0;load_pressure=minf(1,load_pressure+delta*.04)
	elif phase=="engaged": phase="recover";rest_left=maxf(rest_left,45.0)
	if suppressed or bool(context.environment_warning) or bool(context.service_active):
		_cancel_pending("protected_window");rest_left=maxf(rest_left,8.0);return
	var health=_health_fraction()
	if health<.4 or _damage_age<18 or load_pressure>.72:
		_cancel_pending("recovery");rest_left=maxf(rest_left,45.0);phase="recover";return
	if not pending.is_empty():
		pending.eta=float(pending.eta)-delta;pending.ttl=float(pending.ttl)-delta
		# Virtual units advance along an authored entry corridor before materializing.
		pending.progress=minf(6.0,float(pending.progress)+delta*1.2)
		if float(pending.ttl)<=0: _cancel_pending("entry_expired");rest_left=maxf(rest_left,20);return
		if float(pending.eta)<=0: _materialize()
		return
	if _restore_virtual_unit(): return
	if rest_left>0 or active_threats>0 or _budget_available()<1: return
	# A quiet interval can pass with no encounter. No mandatory encounter chain.
	if _rng.randf()>.62+alert*.28:
		rest_left=_new_gap();phase="rest";return
	_plan(false,Vector3.INF,"")

func note_event(event: Dictionary) -> void:
	if not _configured: return
	var key=str(event.get("receipt_id",event.get("event_id","")))+":"+str(event.get("source_unit_id",event.get("source_id","")))+":"+str(event.get("kind",""))
	if key!="::" and _seen_events.has(key): return
	_seen_events.append(key)
	if _seen_events.size()>128: _seen_events.pop_front()
	var kind=str(event.get("kind",""));var point=_point(event.get("position",event.get("report_position")),Vector3.INF)
	var player_source=bool(event.get("source_is_player",event.get("friendly",false))) or _is_player_id(str(event.get("source_unit_id",event.get("source_id",""))))
	var player_target=bool(event.get("target_is_player",event.get("pilot_target",false))) or _is_player_id(str(event.get("target_unit_id",event.get("target_id",""))))
	if kind in ["shot","explosion"] and point.is_finite():
		alert=minf(1,alert+(.10 if player_source else .04));_noise_position=point;_noise_age=0
		# Combat owns one acoustic delivery to nearby brains. The director must not
		# deliver the same sound again or advance each brain's clue RNG twice.
	if kind in ["hit","damage","damage_receipt"] and player_target and float(event.get("actual_damage",event.get("damage",0)))>0:
		_damage_age=0;load_pressure=minf(1,load_pressure+.25);rest_left=maxf(rest_left,45.0)
	if kind=="warning_started" and player_target: load_pressure=minf(1,load_pressure+.10)
	if kind in ["scout_report","enemy_report"]: _receive_report(event)
	if kind in ["target_lost","disengaged"]: rest_left=maxf(rest_left,45.0)
	if kind=="ai_state" and str(event.get("state","")) in ["search","lost"]: rest_left=maxf(rest_left,45.0)

func _receive_report(event: Dictionary) -> void:
	if suppressed or not pending.is_empty() or _damage_age<18 or _health_fraction()<.4 or bool(context.environment_warning): return
	var source_id=str(event.get("source_unit_id",event.get("source_id","")))
	var unit=_unit_record(source_id)
	if unit.is_empty() or str(unit.role)!="scout" or not bool(event.get("confirmed",str(event.get("kind",""))=="enemy_report")): return
	var encounter_id=str(unit.encounter_id)
	if _reported_encounters.has(encounter_id) or float(event.get("report_age_s",0))>2: return
	var actor=_actor(unit);var point=_point(event.get("report_position",event.get("reported_position",event.get("position"))),Vector3.INF)
	if not is_instance_valid(actor) or actor.is_queued_for_deletion() or float(actor.get("hp"))<=0 or not point.is_finite() or actor.global_position.distance_to(point)>45: return
	# The brain's completed continuous visual report is required, not a random cue.
	var brain=_brain(actor)
	if brain==null or not bool(brain.get("reported")) or not bool(brain.get("seen")) or float(brain.get("memory_age"))>.3: return
	var remembered: Vector3=brain.get("last_seen_position")
	if remembered.distance_to(point)>2.0: return
	_reported_encounters[encounter_id]=true
	alert=minf(1,alert+.35)
	if _budget_available()>0: _plan(true,point,encounter_id)

func _plan(reinforcement: bool, clue: Vector3, parent_id: String) -> void:
	var entries=legal_entries()
	if entries.is_empty(): rest_left=12.0;_emit("entry_deferred",{"reason":"no_legal_entry"});return
	var entry: Dictionary=entries[_rng.randi_range(0,entries.size()-1)]
	sequence+=1
	var encounter_id=region_id+"-E%05d"%sequence
	var count=1 if reinforcement else mini(_budget_available(),1 if _rng.randf()<.45 else 2)
	var roles: Array=[]
	for i in count:
		roles.append("harasser" if reinforcement and region_id!="R4" else ("suppressor" if reinforcement else _profile.roles[_rng.randi_range(0,_profile.roles.size()-1)]))
	if region_id=="R2" and not reinforcement: roles[0]="scout"
	var goal: Vector3=entry.target
	if clue.is_finite(): goal=_road_point(clue,float(entry.position.y))
	elif _noise_age<20: goal=_road_point(_noise_position,float(entry.position.y))
	pending={"encounter_id":encounter_id,"parent_id":parent_id,"source_kind":"reinforcement" if reinforcement else "ambient","entry_id":entry.id,"entry":entry.position,"direction":entry.direction,"target":goal,"roles":roles,"unit_seed":_rng.randi(),"eta":_rng.randf_range(5,9) if reinforcement else _rng.randf_range(3,6),"ttl":22.0,"progress":0.0}
	phase="incoming"
	_emit("patrol_planned",{"encounter_id":encounter_id,"entry_id":entry.id,"source_kind":pending.source_kind,"eta":pending.eta})

func legal_entries() -> Array[Dictionary]:
	var result: Array[Dictionary]=[]
	if not _configured or not is_instance_valid(world): return result
	var authored: Variant=world.get("layout")
	if authored is Dictionary and not authored.is_empty():
		for entry in authored.get("entries",[]):
			var p=_point(entry.get("position"),Vector3.INF)
			var target=_point(entry.get("target"),Vector3.INF)
			if not p.is_finite() or not target.is_finite(): continue
			var direction=(target-p).normalized()
			if direction.length_squared()<.5: continue
			if _entry_legal(p,direction): result.append({"id":str(entry.get("id","")),"position":p,"direction":direction,"target":target})
		return result
	# Stable authored road grid gateways. These roads exist in every district;
	# per-region direction/height identifies its approach corridor.
	for x in range(50,600,100):
		for z in range(50,500,100):
			var p=Vector3(x,float(_profile.altitude),z)
			var direction: Vector3=_profile.direction
			if x>=550 and direction.x>0 or x<=50 and direction.x<0 or z>=450 and direction.z>0 or z<=50 and direction.z<0: direction=-direction
			if _entry_legal(p,direction): result.append({"id":region_id+"-road-%d-%d"%[x,z],"position":p,"direction":direction,"target":p+direction*42})
	return result

func _entry_legal(point: Vector3, direction: Vector3) -> bool:
	if not point.is_finite() or point.x<5 or point.x>595 or point.z<5 or point.z>495: return false
	if not is_instance_valid(pilot) or Vector2(point.x-pilot.global_position.x,point.z-pilot.global_position.z).length()<MIN_ENTRY_DISTANCE: return false
	if not _outside_camera(point) or _in_safe_space(point): return false
	var chunks=world.get("chunks");var cell=Vector2i(floori(point.x/100),floori(point.z/100))
	if not chunks is Dictionary or not chunks.has(cell) or not is_instance_valid(chunks[cell]): return false
	var id=chunks[cell].get_instance_id()
	if not _chunk_age.has(id) or time_s-float(_chunk_age[id])<.5: return false
	if not world.is_inside_tree(): return false
	var space=world.get_world_3d().direct_space_state
	var ground=PhysicsRayQueryParameters3D.create(point,point+Vector3.DOWN*30,1|32)
	if space.intersect_ray(ground).is_empty(): return false
	var sphere=SphereShape3D.new();sphere.radius=1.35
	var query=PhysicsShapeQueryParameters3D.new();query.shape=sphere;query.collision_mask=1|2|4|8|32;query.transform=Transform3D(Basis.IDENTITY,point)
	if not space.intersect_shape(query,1).is_empty(): return false
	query.motion=direction.normalized()*18
	var sweep=space.cast_motion(query)
	return sweep.size()>0 and float(sweep[0])>.99

func _outside_camera(point: Vector3) -> bool:
	if camera_guard.is_valid(): return bool(camera_guard.call(point))
	if not world.is_inside_tree(): return false
	var camera=world.get_viewport().get_camera_3d()
	if camera==null: return false
	if camera.is_position_behind(point): return true
	var rect=world.get_viewport().get_visible_rect().grow(90)
	return not rect.has_point(camera.unproject_position(point))

func _in_safe_space(point: Vector3) -> bool:
	var region=world.get("region")
	if not region is Dictionary: return true
	for poi in region.get("pois",[]):
		if not poi.has("service_function") and str(poi.get("id",""))!=str(region.get("spawn_poi","")): continue
		var p=Vector2(float(poi.position_xz_m[0]),float(poi.position_xz_m[1]))
		if Vector2(point.x,point.z).distance_to(p)<22: return true
	return false

func _materialize() -> void:
	var point: Vector3=pending.entry+pending.direction*float(pending.progress)
	if _budget_available(false)<pending.roles.size() or not _entry_legal(point,pending.direction): pending.eta=2.0;return
	# Combat's documented formation offset is +X 2.3 m per unit. Every member,
	# not only the leader, must pass the full distance/camera/collision predicate.
	for i in pending.roles.size():
		if not _entry_legal(point+Vector3(i*2.3,0,0),pending.direction): pending.eta=2.0;return
	if not combat.has_method("spawn_patrol"): _cancel_pending("spawn_api_missing");rest_left=45;return
	var plan=pending.duplicate(true);pending.clear()
	var actors: Array=combat.spawn_patrol(plan.roles,point,plan.target)
	for i in actors.size():
		var actor=actors[i]
		if not actor is CharacterBody3D: continue
		var id=str(plan.encounter_id)+"-U%02d"%(i+1)
		_register_actor(actor,id,str(actor.get("role")),plan,int(plan.unit_seed)+i)
	phase="patrol";rest_left=_new_gap()
	_emit("patrol_entered",{"encounter_id":plan.encounter_id,"entry_id":plan.entry_id,"count":actors.size(),"position":_vec(point),"source_kind":plan.source_kind})

func _register_actor(actor: CharacterBody3D, id: String, unit_role: String, plan: Dictionary, unit_seed: int) -> void:
	actor.set_meta("unit_id",id);actor.set_meta("entity_id",id);actor.set_meta("source_kind",str(plan.source_kind));actor.set_meta("ambient_patrol",true);actor.set_meta("allow_facility_target",false)
	actor.set_meta("encounter_id",str(plan.encounter_id));actor.set_meta("ai_seed",unit_seed)
	var brain=_brain(actor)
	if brain!=null:
		brain.configure(actor,unit_role,unit_seed,true);brain.set("navigation_world",world);brain.set_patrol_target(plan.target)
	registry[id]={"unit_id":id,"encounter_id":str(plan.encounter_id),"source_kind":str(plan.source_kind),"entry_id":str(plan.entry_id),"role":unit_role,"seed":unit_seed,"target":plan.target,"entry":plan.entry,"direction":plan.direction,"actor":weakref(actor),"status":"active","age":0.0}

func _refresh_registry() -> void:
	for id in registry.keys():
		var unit: Dictionary=registry[id];unit.age=float(unit.get("age",0))+.5
		if str(unit.status)!="active": continue
		var actor=_actor(unit)
		if not is_instance_valid(actor) or actor.is_queued_for_deletion() or float(actor.get("hp"))<=0:
			unit.status="retired";unit.erase("actor");continue
		var brain=_brain(actor)
		# Offscreen retirement never removes a visible or still-engaged aircraft.
		if actor.global_position.distance_to(pilot.global_position)>150 and float(unit.age)>50 and _outside_camera(actor.global_position) and (brain==null or str(brain.get("state")) in ["patrol","lost","retreat"]):
			actor.queue_free();unit.status="retired";unit.erase("actor")
	# Keep only a bounded history; sequence IDs never recycle.
	if registry.size()>64:
		for id in registry.keys():
			if str(registry[id].status)=="retired": registry.erase(id)
			if registry.size()<=48: break

func _refresh_chunks() -> void:
	var chunks=world.get("chunks");var alive: Dictionary={}
	if not chunks is Dictionary: return
	for chunk in chunks.values():
		if not is_instance_valid(chunk): continue
		var id=chunk.get_instance_id();alive[id]=true
		if not _chunk_age.has(id): _chunk_age[id]=time_s
	for id in _chunk_age.keys():
		if not alive.has(id): _chunk_age.erase(id)

func _budget_available(include_pending = true) -> int:
	var total=0;var ambient_count=0
	for actor in _actors():
		total+=1
		if bool(actor.get_meta("ambient_patrol",false)): ambient_count+=1
	for unit in registry.values():
		if str(unit.status)=="virtual": total+=1;ambient_count+=1
	var reserved=mini(8,maxi(0,int(context.mission_reserved)))
	var waiting=pending.get("roles",[]).size() if include_pending else 0
	return maxi(0,mini(MAX_AMBIENT-ambient_count-waiting,MAX_TOTAL-total-reserved-waiting))

func _actors() -> Array:
	var result: Array=[]
	if not is_instance_valid(combat): return result
	for actor in combat.get("enemies"):
		if is_instance_valid(actor) and not actor.is_queued_for_deletion() and float(actor.get("hp"))>0: result.append(actor)
	return result

func _active_threat_count() -> int:
	var count=0
	for actor in _actors():
		var brain=_brain(actor)
		if brain!=null and str(brain.get("state")) in ["pursue","flank"]: count+=1
	return count

func _health_fraction() -> float:
	return clampf(float(pilot.get("health"))/maxf(1,float(pilot.get("maximum_health"))),0,1)

func _is_player_id(id: String) -> bool:
	return is_instance_valid(pilot) and id in ["player","pilot",str(pilot.get_instance_id()),str(pilot.get_meta("unit_id","player"))]

func _unit_record(id: String) -> Dictionary:
	if registry.has(id): return registry[id]
	for unit in registry.values():
		var actor=_actor(unit)
		if is_instance_valid(actor) and str(actor.get_instance_id())==id: return unit
	return {}

func _actor(unit: Dictionary) -> CharacterBody3D:
	var reference=unit.get("actor")
	return reference.get_ref() if reference is WeakRef else null

func _brain(actor: Node) -> RefCounted:
	for property in actor.get_property_list():
		if str(property.name)=="brain": return actor.get("brain")
	return null

func _cancel_pending(reason: String) -> void:
	if pending.is_empty(): return
	_emit("patrol_cancelled",{"encounter_id":pending.encounter_id,"reason":reason});pending.clear()

func _new_gap() -> float: return _rng.randf_range(float(_profile.gap_min),float(_profile.gap_max))
func _road_point(point: Vector3, altitude: float) -> Vector3:
	var authored: Variant=world.get("layout") if is_instance_valid(world) else null
	if authored is Dictionary and not authored.is_empty():
		var best=point
		var best_distance=INF
		for road in authored.get("roads",[]):
			var points: Array=road.get("points",[])
			for i in range(points.size()-1):
				var a=Vector2(float(points[i][0]),float(points[i][1]))
				var b=Vector2(float(points[i+1][0]),float(points[i+1][1]))
				var p=Geometry2D.get_closest_point_to_segment(Vector2(point.x,point.z),a,b)
				var distance_m=p.distance_to(Vector2(point.x,point.z))
				if distance_m<best_distance: best_distance=distance_m;best=Vector3(p.x,altitude,p.y)
		var ground=float(world.terrain_height(best)) if world.has_method("terrain_height") else 0.0
		best.y=clampf(maxf(altitude,ground+float(_profile.altitude)),2.8,30.0)
		return best
	return Vector3(clampf(roundf(point.x/50)*50,50,550),altitude,clampf(roundf(point.z/50)*50,50,450))
func _emit(kind: String, payload: Dictionary) -> void:
	# This is an internal event. Presentation must independently check perception.
	encounter_event.emit(payload.merged({"kind":kind,"region_id":region_id,"time_s":time_s,"player_notice":false}))
static func _vec(point: Vector3) -> Array: return [point.x,point.y,point.z]
static func _point(value: Variant, fallback: Vector3) -> Vector3:
	if value is Vector3: return value if value.is_finite() else fallback
	if value is Array and value.size()==3:
		var result=Vector3(float(value[0]),float(value[1]),float(value[2]))
		if result.is_finite(): return result
	return fallback

func _layout_revision() -> int:
	var authored: Variant=world.get("layout") if is_instance_valid(world) else null
	return int(authored.get("revision",0)) if authored is Dictionary else 0

func _adapt_layout_snapshot(saved: Dictionary) -> Dictionary:
	if int(saved.get("layout_revision",0))==_layout_revision(): return saved
	var authored: Variant=world.get("layout") if is_instance_valid(world) else null
	if not authored is Dictionary or authored.get("entries",[]).is_empty(): return saved
	var result=saved.duplicate(true)
	# Layout changes invalidate spatial memory, not pressure, IDs, RNG, health or receipts.
	result.noise_age=999.0
	var records: Array=result.get("units",[])
	if not result.get("pending",{}).is_empty(): records=records.duplicate();records.append(result.pending)
	for record in records:
		var old_point=_point(record.get("entry"),Vector3.ZERO)
		var nearest: Dictionary={}
		var distance_m=INF
		for entry in authored.entries:
			var p=_point(entry.get("position"),Vector3.INF)
			var d=Vector2(p.x-old_point.x,p.z-old_point.z).length()
			if p.is_finite() and d<distance_m: distance_m=d;nearest=entry
		if nearest.is_empty(): continue
		var p=_point(nearest.position,Vector3.ZERO)
		var target=_point(nearest.target,p+Vector3.FORWARD*20)
		record.entry_id=str(nearest.id);record.entry=_vec(p);record.target=_vec(target)
		record.direction=_vec((target-p).normalized());record.progress=0.0
		if record.has("position"): record.position=_vec(p)
		record.erase("brain")
	result.layout_revision=_layout_revision()
	return result

func snapshot() -> Dictionary:
	var units: Array=[]
	for unit in registry.values():
		var record=unit.duplicate();record.erase("actor")
		for key in ["target","entry","direction"]: record[key]=_vec(record[key])
		var actor=_actor(unit)
		if is_instance_valid(actor):
			record.position=_vec(actor.global_position);record.hp=float(actor.get("hp"));record.status="virtual"
			if actor.has_method("damage_snapshot"): record.damage_state=actor.damage_snapshot()
			var brain=_brain(actor)
			if brain!=null: record.brain=brain.snapshot()
		units.append(record)
	var plan=pending.duplicate(true)
	if not plan.is_empty():
		for key in ["entry","direction","target"]: plan[key]=_vec(plan[key])
	return {"version":1,"layout_revision":_layout_revision(),"region_id":region_id,"rng_state":str(_rng.state),"sequence":sequence,"time_s":time_s,"phase":phase,"rest_left":rest_left,"alert":alert,"load_pressure":load_pressure,"noise_position":_vec(_noise_position),"noise_age":_noise_age,"damage_age":_damage_age,"engagement_age":_engagement_age,"pending":plan,"units":units,"reported_encounters":_reported_encounters.duplicate(),"seen_events":_seen_events.duplicate(),"tick_accumulator":_tick_accumulator}

func restore(saved: Dictionary) -> void:
	saved=_adapt_layout_snapshot(saved)
	if int(saved.get("version",0))!=1 or str(saved.get("region_id",""))!=region_id: return
	_rng.state=int(str(saved.get("rng_state",_rng.state)));sequence=maxi(0,int(saved.get("sequence",0)));time_s=maxf(0,float(saved.get("time_s",0)))
	phase=str(saved.get("phase","rest"));rest_left=maxf(0,float(saved.get("rest_left",45)));alert=clampf(float(saved.get("alert",0)),0,1);load_pressure=clampf(float(saved.get("load_pressure",0)),0,1)
	_noise_position=_point(saved.get("noise_position"),Vector3.ZERO);_noise_age=maxf(0,float(saved.get("noise_age",999)));_damage_age=maxf(0,float(saved.get("damage_age",999)));_engagement_age=maxf(0,float(saved.get("engagement_age",999)))
	_tick_accumulator=clampf(float(saved.get("tick_accumulator",0)),0,.499999)
	pending=saved.get("pending",{}).duplicate(true)
	if not pending.is_empty():
		for key in ["entry","direction","target"]: pending[key]=_point(pending.get(key),Vector3.ZERO)
	_reported_encounters=saved.get("reported_encounters",{}).duplicate();_seen_events.clear()
	for id in saved.get("seen_events",[]): _seen_events.append(str(id))
	registry.clear()
	for value in saved.get("units",[]):
		var unit: Dictionary=value.duplicate(true)
		for key in ["entry","direction","target"]: unit[key]=_point(unit.get(key),Vector3.ZERO)
		if str(unit.get("status","retired"))!="retired": unit.status="virtual"
		registry[str(unit.unit_id)]=unit
	_chunk_age.clear()

func _restore_virtual_unit() -> bool:
	var live=_actors();var ambient_live=0
	for actor in live:
		if bool(actor.get_meta("ambient_patrol",false)): ambient_live+=1
	if live.size()+maxi(0,int(context.mission_reserved))>=MAX_TOTAL or ambient_live>=MAX_AMBIENT: return false
	for unit in registry.values():
		if str(unit.status)!="virtual": continue
		# Rebind a separately restored Combat actor before creating anything.
		for actor in _actors():
			if str(actor.get_meta("unit_id",""))==str(unit.unit_id): unit.actor=weakref(actor);unit.status="active";break
		if str(unit.status)!="virtual": continue
		var point=_point(unit.get("position"),unit.entry)
		if not _entry_legal(point,unit.direction) or not combat.has_method("spawn_patrol"): continue
		# Its budget was retained in the virtual record; no fresh random draw.
		var actors: Array=combat.spawn_patrol([unit.role],point,unit.target)
		if actors.is_empty(): return false
		var actor=actors[0];var saved=unit.duplicate(true)
		_register_actor(actor,str(unit.unit_id),str(unit.role),unit,int(unit.seed))
		if saved.has("damage_state") and actor.has_method("restore_damage_state"):
			actor.restore_damage_state(saved.damage_state)
		else: actor.set("hp",maxf(.01,float(saved.get("hp",actor.get("hp")))))
		var brain=_brain(actor)
		if brain!=null and saved.has("brain"): brain.restore(saved.brain)
		return true
	return false
