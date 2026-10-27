extends SceneTree
## Isolated real physics comparison. Authority motor/impulse and pilot placements
## are explicit fixtures, not Session spells, a connected water route or progress.
const Cabinet = preload("res://scripts/v3/world/twin_distribution_cabinet.gd")
const FlightBody = preload("res://scripts/v2/flight_body.gd")
const Catalog = preload("res://scripts/v2/catalog.gd")
const CANDIDATE := "res://data/v3/terrain/i2_distribution_trial_layout.json"
const LEGACY := "res://data/v3/terrain/i2_distribution_layout_dev18.json"
const FLOOR_IDS := ["ServiceFloor","ServiceFloorRearStrip","ServiceFloorLeftSocketRim","ServiceFloorCentralWeb","ServiceFloorRightSocketRim"]
const OBSERVERS := [Vector3(18,5.75,-10.6),Vector3(18,2.7,-10.8),Vector3(17.8,2.7,-7.85)]
var viewport: SubViewport
var world: Node3D
var cabinet: Node3D
var players: Dictionary = {}
var entities: Dictionary = {}
var checks := 0
var failures: Array = []
var measurements: Dictionary = {}
var finished := false
var action_serial := 1000
var original_sha := ""
class TestLogger extends Logger:
	var errors: Array = []
	func _log_error(function: String,file: String,line: int,code: String,rationale: String,_notify: bool,error_type: int,_backtraces: Array[ScriptBacktrace]) -> void:
		errors.append({"function":function,"file":file,"line":line,"code":code,"rationale":rationale,"type":error_type})
var logger := TestLogger.new()

func _init() -> void:
	OS.add_logger(logger)
	_run.call_deferred()

func _run() -> void:
	create_timer(60).timeout.connect(func():
		if not finished:
			print("V3_DISTRIBUTION_TRIAL_FLOOR_TIMEOUT "+JSON.stringify({"checks":checks,"failures":failures,"engine_errors":logger.errors}))
			quit(2))
	original_sha=FileAccess.get_sha256(Cabinet.PATH)
	var original: Variant=JSON.parse_string(FileAccess.get_file_as_string(LEGACY))
	var candidate: Variant=JSON.parse_string(FileAccess.get_file_as_string(CANDIDATE))
	_check(original is Dictionary and candidate is Dictionary,"both actual layout JSON files load")
	if not original is Dictionary or not candidate is Dictionary:
		await _finish()
		return
	_contract(original,candidate)
	viewport=SubViewport.new()
	viewport.own_world_3d=true
	viewport.world_3d=World3D.new()
	root.add_child(viewport)
	world=Node3D.new()
	viewport.add_child(world)
	for row in [[1,"tr01"],[2,"hx02"]]:
		var body:=FlightBody.new()
		body.configure(Catalog.resolve_build(Catalog.default_build(row[1])))
		body.freeze=true
		body.position=Vector3(25,12+int(row[0])*2,20)
		world.add_child(body)
		body.set_process(false)
		body.set_physics_process(false)
		players[row[0]]=body
	var baseline: Dictionary=await _exercise(original,false)
	var changed: Dictionary=await _exercise(candidate,true)
	if not baseline.is_empty() and not changed.is_empty():
		_check(baseline.closed_rays.size()==30 and changed.closed_rays==baseline.closed_rays,"all 30 closed-state first-hit identities preserved")
		_check(baseline.open_rays.size()==30 and changed.open_rays==baseline.open_rays,"all 30 open-state first-hit identities preserved")
		_check(changed.cover_transform==baseline.cover_transform and changed.door_transform==baseline.door_transform,"real full-stroke endpoints remain identical to old mechanism")
		var before: Dictionary=cabinet.snapshot()
		_check(not cabinet.apply_snapshot(baseline.closed_snapshot).ok and cabinet.snapshot()==before,"old layout hash is rejected atomically; no implicit save migration")
	measurements["baseline"]=baseline
	measurements["candidate"]=changed
	await _finish()

func _check(ok: bool,label: String,details: Dictionary={}) -> void:
	checks+=1
	if not ok:
		failures.append({"check":label,"details":details})
		print("DISTRIBUTION_TRIAL_FLOOR_FAIL "+label+" "+JSON.stringify(details))

func _contract(original: Dictionary,candidate: Dictionary) -> void:
	var unchanged:=original.duplicate(true)
	unchanged.fixed_solids=candidate.fixed_solids.duplicate(true)
	_check(unchanged==candidate,"only fixed_solids changed; version/id/origin/targets/all other keys retained")
	var old_parts: Dictionary={}
	for part in original.fixed_solids: old_parts[part.id]=part
	var count:=0
	var volume:=0.0
	var preserved:=true
	for part in candidate.fixed_solids:
		if str(part.id) in FLOOR_IDS:
			count+=1
			var size:=_v(part.max)-_v(part.min)
			volume+=float(size.x)*float(size.y)*float(size.z)
			preserved=preserved and float(part.min[1])==1.0 and float(part.max[1])==1.2 and part.color==old_parts.ServiceFloor.color
		else: preserved=preserved and old_parts.get(part.id)==part
	_check(preserved and count==5 and candidate.fixed_solids.size()==original.fixed_solids.size()+4,"five floor pieces and every original non-floor part remain exact")
	_check(absf(volume-(4.4*0.2*5.8-2.0*0.22*0.2*0.22))<0.00001,"floor volume removed equals exactly two 0.22m square through-holes",{"floor_volume_m3":volume})
	for altered in ["origin","door_size","cover_travel"]:
		var bad:=candidate.duplicate(true)
		if altered=="origin": bad.origin[0]+=0.02
		elif altered=="door_size": bad.door.size[0]+=0.02
		else: bad.cover.travel_m+=0.02
		var probe:=Cabinet.new()
		_check(not probe.configure(bad).ok,"old placement and actuator dimensions still reject changes: "+altered)
		probe.free()

func _exercise(layout: Dictionary,has_holes: bool) -> Dictionary:
	await _park()
	if is_instance_valid(cabinet):
		cabinet.queue_free()
		await _settle()
	cabinet=Cabinet.new()
	var configured: Dictionary=cabinet.configure(layout)
	_check(configured.ok,"unmodified production Cabinet configures "+("candidate" if has_holes else "baseline"),configured)
	if not configured.ok:
		cabinet.free()
		return {}
	world.add_child(cabinet)
	await _settle()
	entities={}
	for item in cabinet.target_definitions(): entities[item.id]=item
	_check(cabinet.synchronize_impulse_roster(players).ok,"real two-body roster accepted in isolated physics world")
	var result: Dictionary={"closed_rays":_thirty_rays(),"closed_snapshot":cabinet.snapshot()}
	_floor_rays(has_holes)
	if has_holes: _matching_floor_collision()
	for peer in players:
		var swept:=_body_sweep(peer,Vector3(18,2.3,-7.7),Vector3(18,2.3,-11.2))
		_check(not swept.ok and swept.stage=="sweep","closed gate blocks real full-body low route",{"peer":peer,"candidate":has_holes,"sweep":swept})
	var cover_excluded: Array[RID]=[cabinet.cover.get_rid()]
	var door_excluded: Array[RID]=[cabinet.door.get_rid()]
	_check(cabinet._sweep_clear(_v(layout.cover.size),_v(layout.cover.center),_v(layout.cover.center)+Vector3.RIGHT*1.2,cover_excluded),"entire 1.2m cover sweep remains clear")
	_check(cabinet._sweep_clear(_v(layout.door.size),_v(layout.door.center),_v(layout.door.center)+Vector3.UP*3.0,door_excluded),"entire 3m door sweep remains clear")
	# Trusted motor and approved-impulse boundary fixtures; no fake completion flag.
	entities[Cabinet.RELAY_ID].powered=true
	entities[Cabinet.LOCK_ID].controlled=true
	entities[Cabinet.LOCK_ID].owner="1"
	entities[Cabinet.LOCK_ID].takeover_remaining=8.0
	action_serial+=1
	_check(cabinet.apply_authorized_impulse(Cabinet.COVER_ID,Vector3.RIGHT*9.0,1,action_serial).ok,"authorized 9 N.s input starts real cover integration")
	var travelled:=true
	for unused in range(50):
		var tick: Dictionary=cabinet.fixed_update(0.05,entities,players)
		travelled=travelled and bool(tick.ok) and not bool(tick.get("cover_blocked",false)) and not bool(tick.get("door_blocked",false))
	_check(travelled and is_equal_approx(float(cabinet.snapshot().axis.position_m),1.2) and float(cabinet.snapshot().door_fraction)==1.0,"actual bounded integration reaches both full endpoints with no new floor obstruction")
	result["cover_transform"]=str(cabinet.cover.global_transform)
	result["door_transform"]=str(cabinet.door.global_transform)
	result["open_rays"]=_thirty_rays()
	for peer in players:
		var swept:=_body_sweep(peer,Vector3(18,2.3,-7.7),Vector3(18,2.3,-11.2))
		_check(swept.ok,"open low route passes every actual TR/HX shape",{"peer":peer,"candidate":has_holes,"sweep":swept})
		for point in OBSERVERS:
			await _place(peer,point)
			var observed: Dictionary=cabinet.observe_back(peer,players[peer])
			_check(observed.ok,"real full-body old observation position remains readable",{"peer":peer,"candidate":has_holes,"position":str(point),"sample":observed})
		await _park()
	if has_holes: await _obstruction_cases()
	return result

func _floor_rays(has_holes: bool) -> void:
	for x in [16.45,19.55]:
		for dx in [-0.07,0.0,0.07]:
			for dz in [-0.07,0.0,0.07]:
				var top:=Vector3(x+dx,1.35,-12.44+dz)
				var bottom:=Vector3(top.x,0.85,top.z)
				var down:=_ray(top,bottom)
				var up:=_ray(bottom,top)
				_check((down.is_empty() and up.is_empty()) if has_holes else (not down.is_empty() and not up.is_empty()),"socket interior rays traverse only candidate holes",{"x":x,"dx":dx,"dz":dz,"candidate":has_holes})
		for offset in [Vector2(-0.13,0),Vector2(0.13,0),Vector2(0,-0.13),Vector2(0,0.13)]:
			var point:=Vector3(x+offset.x,1.35,-12.44+offset.y)
			var hit:=_ray(point,point-Vector3.UP*0.5)
			_check(not hit.is_empty() and absf(float(hit.position.y)-1.2)<0.00001 and str(hit.collider.name).begins_with("ServiceFloor"),"immediate socket rim remains actual Y1.2 bearing floor",{"candidate":has_holes,"position":str(point)})

func _matching_floor_collision() -> void:
	var matches:=true
	for id in FLOOR_IDS:
		var body: StaticBody3D=cabinet.fixed_bodies[id]
		var collider: CollisionShape3D=body.get_child(0)
		var visual: MeshInstance3D=body.get_node("Visual")
		matches=matches and collider.shape is BoxShape3D and visual.mesh is BoxMesh and collider.shape.size.is_equal_approx(visual.mesh.size)
	_check(matches,"all five rendered floor solids use identical real collision dimensions")

func _thirty_rays() -> Array:
	var found: Array=[]
	for start in OBSERVERS:
		for spec in cabinet.layout().panels:
			var front: Vector3=cabinet.to_global(_v(spec.center)+Vector3.BACK*float(spec.size[2])*0.5)
			for offset in [Vector2.ZERO,Vector2(-0.06,-0.04),Vector2(0.06,-0.04),Vector2(-0.06,0.04),Vector2(0.06,0.04)]:
				var finish:=front+Vector3(offset.x,offset.y,0)
				var hit:=_ray(start,finish-(start-finish).normalized()*0.002)
				found.append("" if hit.is_empty() else str(hit.collider.name))
	return found

func _reset_closed() -> void:
	var state: Dictionary=cabinet.snapshot()
	state.axis.position_m=0.0
	state.axis.velocity_mps=0.0
	state.axis.last_serial={}
	state.door_fraction=0.0
	state.electric_latched=false
	state.cover_blocked=false
	state.door_blocked=false
	_check(cabinet.apply_snapshot(state).ok,"declared saved-pose fixture resets mechanism for obstruction case")
	_check(cabinet.synchronize_impulse_roster(players).ok,"obstruction fixture restores actual roster")

func _obstruction_cases() -> void:
	for peer in players:
		await _park()
		_reset_closed()
		var body: FlightBody=players[peer]
		await _place(peer,Vector3(18,4.055+float(body.stats.height_m)*0.5,-9))
		_check(_body_sweep(peer,body.global_position,body.global_position).ok,"door obstruction body starts without penetration",{"peer":peer})
		var before: Transform3D=cabinet.door.transform
		var tick: Dictionary=cabinet.fixed_update(0.25,entities,players)
		_check(tick.ok and tick.door_blocked and cabinet.door.transform==before and _body_sweep(peer,body.global_position,body.global_position).ok,"whole rising gate stops safely for either real airframe",{"peer":peer,"result":tick})
	await _park()
	_reset_closed()
	var obstacle:=StaticBody3D.new()
	obstacle.collision_layer=32
	var shape:=BoxShape3D.new()
	shape.size=Vector3.ONE*0.08
	var collision:=CollisionShape3D.new()
	collision.shape=shape
	obstacle.add_child(collision)
	obstacle.position=Vector3(18.85,4.08,-11.45)
	world.add_child(obstacle)
	await _settle()
	var before: Transform3D=cabinet.cover.transform
	action_serial+=1
	_check(cabinet.apply_authorized_impulse(Cabinet.COVER_ID,Vector3.RIGHT*9.0,1,action_serial).ok,"cover receives real input before swept-object case")
	var tick: Dictionary=cabinet.fixed_update(0.25,entities,players)
	_check(tick.ok and tick.cover_blocked and cabinet.cover.transform==before,"cover full swept volume respects small actual object after floor split",tick)
	obstacle.queue_free()
	await _settle()

func _body_sweep(peer: int,start: Vector3,finish: Vector3) -> Dictionary:
	var body: FlightBody=players[peer]
	for owner in body.get_shape_owners():
		if body.is_shape_owner_disabled(owner): continue
		for index in range(body.shape_owner_get_shape_count(owner)):
			var query:=PhysicsShapeQueryParameters3D.new()
			query.shape=body.shape_owner_get_shape(owner,index)
			query.transform=Transform3D(Basis.IDENTITY,start)*body.shape_owner_get_transform(owner)
			query.exclude=[body.get_rid()]
			query.collision_mask=0xFFFFFFFF
			query.margin=0.0
			if not world.get_world_3d().direct_space_state.intersect_shape(query,1).is_empty(): return {"ok":false,"stage":"start"}
			query.motion=finish-start
			var fractions:=world.get_world_3d().direct_space_state.cast_motion(query)
			if fractions.size()!=2 or fractions[0]<0.99999: return {"ok":false,"stage":"sweep","fractions":str(fractions)}
			query.transform.origin=finish
			query.motion=Vector3.ZERO
			if not world.get_world_3d().direct_space_state.intersect_shape(query,1).is_empty(): return {"ok":false,"stage":"end"}
	return {"ok":true}

func _ray(start: Vector3,finish: Vector3) -> Dictionary:
	return world.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(start,finish,0xFFFFFFFF))

func _place(peer: int,point: Vector3) -> void:
	var body: FlightBody=players[peer]
	body.global_transform=Transform3D(Basis.IDENTITY,point)
	body.linear_velocity=Vector3.ZERO
	body.angular_velocity=Vector3.ZERO
	PhysicsServer3D.body_set_state(body.get_rid(),PhysicsServer3D.BODY_STATE_TRANSFORM,body.global_transform)
	await _settle()

func _park() -> void:
	for peer in players: await _place(peer,Vector3(25,12+int(peer)*2,20))

func _settle() -> void:
	await physics_frame
	await physics_frame
	await process_frame

static func _v(value: Array) -> Vector3:
	return Vector3(float(value[0]),float(value[1]),float(value[2]))

func _finish() -> void:
	finished=true
	_check(FileAccess.get_sha256(Cabinet.PATH)==original_sha,"production default layout bytes remain unchanged")
	if is_instance_valid(viewport): viewport.queue_free()
	await process_frame
	await process_frame
	print("V3_DISTRIBUTION_TRIAL_FLOOR_TESTS "+JSON.stringify({"checks":checks,"failures":failures,"engine_errors":logger.errors,"measurements":measurements,"candidate_sha256":FileAccess.get_sha256(CANDIDATE),"original_sha256":original_sha,"scope":"isolated real physics and explicit authority/placement fixtures; no connected plumbing, water transfer, migration, Session, Story, LAN, graphics or human-play verification"}))
	OS.remove_logger(logger)
	quit(0 if failures.is_empty() and logger.errors.is_empty() else 1)
