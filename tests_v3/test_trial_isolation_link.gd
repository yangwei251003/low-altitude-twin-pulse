extends "res://tests_v3/test_distribution_trial_floor.gd"
## Reuses only the frozen floor suite's real-body/query/cleanup helpers.
## Saved poses and authority input fixtures are explicit, not a Session playthrough.
const Link = preload("res://scripts/v3/world/twin_trial_isolation_link.gd")
const Rules = preload("res://scripts/v3/gameplay/twin_ability_rules.gd")
var link: Node3D
var link_initial: Dictionary={}
var rules=Rules.new()

func _run() -> void:
	create_timer(70).timeout.connect(func():
		if not finished:
			print("V3_TRIAL_ISOLATION_TIMEOUT "+JSON.stringify({"checks":checks,"failures":failures,"engine_errors":logger.errors}))
			quit(2))
	original_sha=FileAccess.get_sha256(Cabinet.PATH)
	viewport=SubViewport.new()
	viewport.own_world_3d=true
	viewport.world_3d=World3D.new()
	root.add_child(viewport)
	world=Node3D.new()
	viewport.add_child(world)
	cabinet=Cabinet.new()
	var layout: Variant=JSON.parse_string(FileAccess.get_file_as_string(CANDIDATE))
	if not layout is Dictionary:
		_check(false,"candidate floor JSON loads")
		await _finish()
		return
	var configured: Dictionary=cabinet.configure(layout)
	_check(configured.ok,"actual candidate cabinet configures",configured)
	if not configured.ok:
		cabinet.free()
		await _finish()
		return
	world.add_child(cabinet)
	for row in [[1,"tr01"],[2,"hx02"]]:
		var body:=FlightBody.new()
		body.configure(Catalog.resolve_build(Catalog.default_build(row[1])))
		body.freeze=true
		body.position=Vector3(25,12+int(row[0])*2,20)
		world.add_child(body)
		body.set_process(false)
		body.set_physics_process(false)
		players[row[0]]=body
	_cabinet_pose(1.2,1.0)
	await _settle()
	var baseline:=_thirty_rays()
	link=Link.new()
	configured=link.configure()
	_check(configured.ok,"independent hollow fitting configures before tree",configured)
	if not configured.ok:
		link.free()
		await _finish()
		return
	world.add_child(link)
	link_initial=link.snapshot()
	entities={}
	for item in link.target_definitions(): entities[item.id]=item
	await _settle()
	_check(link.synchronize_impulse_roster(players).ok,"actual two-body roster accepted")
	_geometry(baseline)
	await _real_operation(baseline)
	await _obstruction_cases_link()
	await _permissions_restore()
	await _finish()

func _cabinet_pose(distance: float,fraction: float) -> void:
	var state: Dictionary=cabinet.snapshot()
	state.axis.position_m=distance
	state.axis.velocity_mps=0.0
	state.door_fraction=fraction
	state.electric_latched=fraction==1.0
	_check(cabinet.apply_snapshot(state).ok,"declared old-cabinet saved-pose fixture validates")

func _link_pose(position_m: float) -> void:
	var state: Dictionary=link_initial.duplicate(true)
	state.axis.position_m=position_m
	_check(link.apply_snapshot(state).ok,"explicit isolation saved-pose fixture validates")
	entities[Link.HANDLE].pinned=false
	entities[Link.HANDLE].field_remaining=0.0
	link.set_simulation_paused(false)
	_check(link.synchronize_impulse_roster(players).ok,"restored fixture registers current bodies without reviving stale input")

func _geometry(baseline: Array) -> void:
	_check(link.global_position==Vector3(18,0,-10) and not link.status().station_connected and not link.status().clinic_water_affected,"actual origin and unconnected scope remain explicit")
	_check(_thirty_rays()==baseline and baseline.size()==30,"adding NORMAL fitting preserves all old thirty first hits")
	var same:=true
	for body in link.fixed_bodies.values()+link.moving_bodies.values():
		same=same and body.get_child(0).shape.size.is_equal_approx(body.get_node("Visual").mesh.size)
	_check(same,"all pipe walls and moving shutters use identical render/collision shapes")
	for x in [16.45,19.55]:
		var through:=_ray(Vector3(x,.85,-12.44),Vector3(x,1.35,-12.44))
		_check(through.is_empty(),"real riser bore passes through the exact floor hole",{"x":x,"hit":str(through.get("collider"))})
		var wall:=_ray(Vector3(x-.1,1.1,-12.44),Vector3(x+.1,1.1,-12.44))
		_check(not wall.is_empty() and link.is_ancestor_of(wall.collider),"hole contains actual narrow pipe wall rather than an empty or solid placeholder",{"x":x})
	var excluded: Array[RID]=[]
	for body in link.fixed_bodies.values(): excluded.append(body.get_rid())
	for body in link.moving_bodies.values(): excluded.append(body.get_rid())
	var clear:=true
	for key in link.fixed_bodies:
		if "_Riser_" not in str(key): continue
		var body: StaticBody3D=link.fixed_bodies[key]
		var query:=PhysicsShapeQueryParameters3D.new()
		query.shape=body.get_child(0).shape
		query.transform=body.global_transform
		query.collision_mask=0xFFFFFFFF
		query.exclude=excluded
		query.margin=0.0
		clear=clear and world.get_world_3d().direct_space_state.intersect_shape(query,1).is_empty()
	_check(clear,"entire riser wall volumes fit the holes without overlapping cabinet floor")
	var low_top:=0.0
	for spec in link.layout().fixed:
		if str(spec.id).begins_with("LowCross") or "LowTee" in str(spec.id): low_top=maxf(low_top,float(spec.center[1])+float(spec.size[1])*.5)
	_check(low_top<1.4 and absf(low_top-1.315)<0.00001,"actual low-route crest remains below minimum source head",{"crest_y":low_top})
	measurements["low_route_crest_y"]=low_top
	_gate_ray_check(true,false,"NORMAL")
	for peer in players:
		_check(_body_sweep(peer,Vector3(18,2.3,-7.7),Vector3(18,2.3,-11.2)).ok,"old TR/HX low route stays clear with full fitting",{"peer":peer})
	_cabinet_pose(0,0)
	for peer in players: _check(not _body_sweep(peer,Vector3(18,2.3,-7.7),Vector3(18,2.3,-11.2)).ok,"fitting cannot bypass old closed gate",{"peer":peer})
	var cover_excluded: Array[RID]=[cabinet.cover.get_rid()]
	var door_excluded: Array[RID]=[cabinet.door.get_rid()]
	_check(cabinet._sweep_clear(Vector3(1.2,.16,1.9),Vector3(0,4.08,-1.45),Vector3(1.2,4.08,-1.45),cover_excluded),"full old cover travel remains clear of new fitting")
	_check(cabinet._sweep_clear(Vector3(3.4,2.8,.2),Vector3(0,2.605,1),Vector3(0,5.605,1),door_excluded),"full old rising-door travel remains clear of new fitting")
	_cabinet_pose(1.2,1)

func _gate_ray_check(high_open: bool,low_open: bool,label: String) -> void:
	for side in [-1,1]:
		var x: float=18.0+side*1.55
		var hit:=_ray(Vector3(x,1.52,-12.44),Vector3(x,1.68,-12.44))
		_check(hit.is_empty() if high_open else (not hit.is_empty() and str(hit.collider.name).begins_with("HighShutter")),label+": actual high valve bore matches state",{"side":side})
	var hit:=_ray(Vector3(17.9,1.28,-12.44),Vector3(18.1,1.28,-12.44))
	_check(hit.is_empty() if low_open else (not hit.is_empty() and hit.collider==link.moving_bodies.LowShutter),label+": actual low valve bore matches state")

func _real_operation(baseline: Array) -> void:
	await _place(1,Vector3(16,1.3,-5.3))
	_check(_body_sweep(1,players[1].global_position,players[1].global_position).ok,"real pilot can occupy front handle approach")
	var target: Vector3=link.entity_position(Link.HANDLE)
	var ignored: Array[RID]=[players[1].get_rid()]
	var ray:=PhysicsRayQueryParameters3D.create(players[1].global_position,target,0xFFFFFFFF,ignored)
	var hit:=world.get_world_3d().direct_space_state.intersect_ray(ray)
	var visible: bool=not hit.is_empty() and hit.collider==link.target_bodies[Link.HANDLE]
	_check(visible,"front handle is a real first-hit ability target, not hidden under floor")
	entities["qa:pilot"]={"id":"qa:pilot","owner":"1","tags":["player"],"position":players[1].global_position,"energy":100.0,"health":100.0,"revision":0}
	entities[Link.HANDLE].position=target
	var resolved: Dictionary=rules.resolve({"ability":"push_pull","actor_id":"qa:pilot","target_id":Link.HANDLE},entities,{"sender_id":"1","line_of_sight":visible})
	_check(resolved.ok,"actual Rules accept physical handle from clear approach",resolved)
	if resolved.ok:
		var accepted:=true
		for request in resolved.physics_requests: accepted=accepted and bool(link.can_accept_impulse(request.entity_id,request.impulse,1,1).ok)
		_check(accepted,"approved rule impulse prechecks against real axis")
		if accepted:
			_check(rules.commit(resolved,entities,true).ok,"declared QA actor pays production ability transaction")
			for request in resolved.physics_requests: _check(link.apply_authorized_impulse(request.entity_id,request.impulse,1,1).ok,"committed impulse executes without teleporting")
	var exclusive:=true
	var advanced:=true
	for unused in range(30):
		var result: Dictionary=link.fixed_update(.05,entities,players)
		advanced=advanced and bool(result.ok) and not bool(result.get("blocked",false))
		var status: Dictionary=link.status()
		exclusive=exclusive and not (float(status.high_open_fraction)>0.0 and float(status.low_open_fraction)>0.0)
	_check(advanced and link.status().trial_ready,"real integration reaches stable TRIAL with no hidden geometry obstruction",link.status())
	_check(exclusive,"every integrated transition closes high route before low route begins opening")
	_gate_ray_check(false,true,"TRIAL")
	_check(_thirty_rays()==baseline,"TRIAL shutter poses preserve old thirty first hits")
	await _park()
	_link_pose(.4)
	_gate_ray_check(false,false,"DEADBAND")
	_check(link.status().phase=="both_closed" and not link.status().trial_ready,"mid-travel has a real all-closed interval")
	_link_pose(.8)
	action_serial+=1
	_check(link.apply_authorized_impulse(Link.HANDLE,Vector3.LEFT*9,1,action_serial).ok,"reverse full-axis impulse accepted")
	exclusive=true
	for unused in range(30):
		var result: Dictionary=link.fixed_update(.05,entities,players)
		var status: Dictionary=link.status()
		exclusive=exclusive and bool(result.ok) and not (float(status.high_open_fraction)>0 and float(status.low_open_fraction)>0)
	_check(exclusive and link.status().phase=="normal","reverse operation closes low side before restoring NORMAL")
	_gate_ray_check(true,false,"RETURNED NORMAL")

func _obstruction_cases_link() -> void:
	await _park()
	for row in [[0.0,Vector3(18.05,.65,-6.85),Vector3(.08,.08,.08),9.0,"handle"],
		[0.0,Vector3(16.45,1.6,-12.37),Vector3(.012,.012,.012),9.0,"high follower"],
		[0.4,Vector3(18,1.28,-12.37),Vector3(.012,.012,.012),9.0,"low follower opening"],
		[0.8,Vector3(18,1.28,-12.37),Vector3(.012,.012,.012),-9.0,"low follower closing"]]:
		_link_pose(float(row[0]))
		var prop:=StaticBody3D.new()
		prop.collision_layer=32
		prop.position=row[1]
		var collision:=CollisionShape3D.new()
		var shape:=BoxShape3D.new()
		shape.size=row[2]
		collision.shape=shape
		prop.add_child(collision)
		world.add_child(prop)
		await _settle()
		var poses: Dictionary={}
		for id in link.moving_bodies: poses[id]=link.moving_bodies[id].transform
		action_serial+=1
		_check(link.apply_authorized_impulse(Link.HANDLE,Vector3.RIGHT*float(row[3]),1,action_serial).ok,"full input accepted before "+str(row[4])+" obstruction")
		var result: Dictionary=link.fixed_update(.25,entities,players)
		var same:=true
		for id in poses: same=same and link.moving_bodies[id].transform==poses[id]
		_check(result.ok and result.blocked and same and float(link.snapshot().axis.velocity_mps)==0.0,"whole coupled mechanism stops before swept "+str(row[4]),result)
		prop.queue_free()
		await _settle()
		_check(link.fixed_update(.1,entities,players).ok and float(link.snapshot().axis.position_m)==float(row[0]),"clearing object does not release a queued impulse")

func _permissions_restore() -> void:
	_link_pose(0)
	var before: Dictionary=link.snapshot()
	_check(not link.fixed_update(.1,entities,players,false).ok and link.snapshot()==before,"non-authority invocation cannot move valve")
	_check(not link.can_accept_impulse(Link.HANDLE,Vector3.RIGHT*9.01,1,action_serial+1).ok and not link.can_accept_impulse(Link.HANDLE,Vector3.RIGHT,99,1).ok,"oversized and unregistered impulse rejected")
	_check(link.fixed_update(0,{},{}).ok and link.snapshot()==before,"zero delta neither resamples nor mutates state")
	action_serial+=1
	link.apply_authorized_impulse(Link.HANDLE,Vector3.RIGHT*9,1,action_serial)
	link.set_simulation_paused(true)
	before=link.snapshot()
	_check(link.fixed_update(.25,entities,players).ok and link.snapshot()==before,"host pause freezes exact positions and clears pending motion")
	link.set_simulation_paused(false)
	_check(link.fixed_update(.1,entities,players).ok and link.status().axis_position_m==0.0,"resume does not apply old paused impulse")
	entities[Link.HANDLE].pinned=true
	entities[Link.HANDLE].field_remaining=4.0
	link.fixed_update(.01,entities,players)
	_check(not link.can_accept_impulse(Link.HANDLE,Vector3.RIGHT,1,action_serial+1).ok,"actual pin state blocks new input")
	_link_pose(.8)
	before=link.snapshot()
	var malformed: Array=[]
	var bad:=before.duplicate(true)
	bad["low_open"]=true
	malformed.append(bad)
	bad=before.duplicate(true)
	bad.geometry_sha256="other"
	malformed.append(bad)
	bad=before.duplicate(true)
	bad.axis.position_m=.81
	malformed.append(bad)
	bad=before.duplicate(true)
	bad.blocked=1
	malformed.append(bad)
	var rejected:=true
	for value in malformed: rejected=not link.apply_snapshot(value).ok and link.snapshot()==before and rejected
	_check(rejected,"unknown/geometry/out-of-range/wrong-type snapshots reject atomically")
	var copy: Dictionary=link.snapshot()
	copy.axis.position_m=0.0
	_check(link.snapshot()==before,"returned snapshot is isolated")
	var saved: Dictionary=JSON.parse_string(JSON.stringify(before))
	link.queue_free()
	await _settle()
	var guest:=Link.new()
	_check(guest.configure(saved,false).ok and guest.status().trial_ready,"client creates correct TRIAL shutter poses before entering tree")
	world.add_child(guest)
	link=guest
	await _settle()
	_gate_ray_check(false,true,"CLIENT FIRST FRAME")
	before=link.snapshot()
	_check(not link.fixed_update(.1,entities,players).ok and not link.apply_authorized_impulse(Link.HANDLE,Vector3.LEFT,1,9999).ok and link.snapshot()==before,"client rejects all authoritative motion")
	link.set_simulation_paused(true)
	_check(link.snapshot()==before and link.apply_snapshot(before).ok and link.snapshot()==before,"client pause and duplicate state preserve exact authoritative geometry")
	var host:=Link.new()
	saved.axis.velocity_mps=-1.0
	_check(host.configure(saved,true).ok and host.snapshot().axis.position_m==.8 and host.snapshot().axis.velocity_mps==0.0 and host.snapshot().axis.last_serial.is_empty(),"host disk restore retains position but clears stale velocity and peers")
	host.free()

func _finish() -> void:
	finished=true
	_check(FileAccess.get_sha256(Cabinet.PATH)==original_sha,"default cabinet bytes remain untouched")
	if is_instance_valid(viewport): viewport.queue_free()
	await process_frame
	await process_frame
	print("V3_TRIAL_ISOLATION_LINK_TESTS "+JSON.stringify({"checks":checks,"failures":failures,"engine_errors":logger.errors,"measurements":measurements,"scope":"independent candidate-cabinet physics, actual Rules and explicit pose/input fixtures; no trial-station connection, hydraulic flow, clinic change, progress, save IO, LAN, graphics or human-play result"}))
	OS.remove_logger(logger)
	quit(0 if failures.is_empty() and logger.errors.is_empty() else 1)
