extends "res://tests_v3/test_trial_flow_station.gd"
## Independent real Cabinet+Link+Station physics. Explicit saved poses isolate
## faults; manual trials and Link use actual Rules transactions. No Session,
## Story, saves, networking, graphics, or claimed human playthrough.

func _run() -> void:
	create_timer(90).timeout.connect(func():
		if not finished:
			print("TRIAL_CONNECTED_TIMEOUT "+JSON.stringify({"checks":checks,"failures":failures}))
			quit(2))
	world=Node3D.new()
	root.add_child(world)
	cabinet=Cabinet.new()
	var configured: Dictionary=cabinet.configure(JSON.parse_string(FileAccess.get_file_as_string(FLOOR_PATH)))
	_check(configured.ok,"real five-piece floor cabinet configures",configured)
	if not configured.ok:
		cabinet.free()
		await _finish()
		return
	world.add_child(cabinet)
	_prop(Vector3(18,-.1,-6),Vector3(30,.2,30))
	for row in [[1,"tr01"],[2,"hx02"]]:
		var body:=FlightBody.new()
		body.configure(Catalog.resolve_build(Catalog.default_build(row[1])))
		body.freeze=true
		body.position=Vector3(25,12+int(row[0])*2,20)
		world.add_child(body)
		body.set_process(false)
		body.set_physics_process(false)
		players[row[0]]=body
	var open: Dictionary=cabinet.snapshot()
	open.axis.position_m=1.2
	open.door_fraction=1.0
	open.electric_latched=true
	_check(cabinet.apply_snapshot(open).ok,"declared cabinet saved-open fixture")
	await _settle()
	var rays:=_cabinet_rays()
	station=Station.new()
	configured=station.load_layout()
	_check(configured.ok,"new five-port station validates before construction",configured)
	if not configured.ok:
		station.free()
		await _finish()
		return
	world.add_child(station)
	initial=station.snapshot()
	_reset_entities()
	await _settle()
	var unbound: Dictionary=initial.duplicate(true)
	unbound.axis.position_m=0.0
	_check(station.apply_snapshot(unbound).ok,"saved A-detent fixture has no fictitious connection")
	for i in range(8): _tick(.25)
	_check(_volumes()==[200000,0,0] and not station.connection_status().ok,"unbound actual A window cannot create trial water")
	var fake:=Node3D.new()
	world.add_child(fake)
	_check(not station.attach_link(fake).ok,"ordinary Node or claimed flag cannot impersonate a Link")
	fake.queue_free()
	link=Link.new()
	_check(link.configure().ok,"actual isolation Link configures")
	world.add_child(link)
	_check(station.attach_link(link).ok and not station.connection_status().trial_ready,"NORMAL binding is not a trial permission")
	await _settle()
	for i in range(8): _tick(.25)
	_check(_volumes()==[200000,0,0],"NORMAL high-side route cannot fill either receiver through local bypass")
	await _fresh_geometry_rejections()
	await _real_link_trial()
	_check(_cabinet_rays()==rays,"all original thirty panel first hits survive actual connected hardware")
	await _old_routes()
	await _two_manual_routes()
	await _pipe_disconnect()
	await _leaf_obstructions()
	await _return_sequence()
	await _restore_connections()
	await _finish()

## Deliberately mutate actual isolated hardware after a successful check;
## no previous connection result may authorize later changed geometry.
func _fresh_geometry_rejections() -> void:
	for kind: String in ["fixed","moving"]:
		var table: Dictionary = link.fixed_bodies if kind=="fixed" else link.moving_bodies
		var body: StaticBody3D = table.values()[0]
		var collision: CollisionShape3D = body.get_child(0)
		var shape: BoxShape3D = collision.shape
		var visual: MeshInstance3D = body.get_node("Visual")
		var mesh: BoxMesh = visual.mesh
		var original_size: Vector3 = shape.size
		var original_mesh: Vector3 = mesh.size
		var original_pose: Vector3 = body.position
		_check(station.connection_status().ok,"fresh original "+kind+" geometry accepted")
		shape.size = original_size+Vector3(.02,0,0)
		await _settle()
		_check(not station.connection_status().ok,"changed actual "+kind+" collider rejected after prior good result")
		shape.size = original_size
		mesh.size = original_mesh+Vector3(.02,0,0)
		await _settle()
		_check(not station.connection_status().ok,"changed actual "+kind+" visual dimensions rejected")
		mesh.size = original_mesh
		body.position = original_pose+Vector3(.02,0,0)
		await _settle()
		_check(not link.status().pose_valid and not station.connection_status().ok,"public Link and current Station reject changed "+kind+" pose")
		body.position = original_pose
		await _settle()
		_check(link.status().pose_valid and station.connection_status().ok,"exact restored "+kind+" geometry accepted without cached fault")

func _real_link_trial() -> void:
	await _place(1,Vector3(16,1.3,-5.3))
	var values: Dictionary={}
	for row in link.target_definitions(): values[row.id]=row
	values["qa:link_actor"]={"id":"qa:link_actor","owner":"1","tags":["player"],"position":players[1].global_position,"energy":100.0,"health":100.0,"revision":0}
	var hit:=_ray(players[1].global_position,link.entity_position(Link.HANDLE),[players[1].get_rid()])
	var visible: bool=not hit.is_empty() and hit.collider==link.target_bodies[Link.HANDLE]
	_check(visible,"isolation handle is an actual first-hit target")
	var resolved: Dictionary=rules.resolve({"ability":"push_pull","actor_id":"qa:link_actor","target_id":Link.HANDLE},values,{"sender_id":"1","line_of_sight":visible})
	_check(resolved.ok,"production ability accepts isolation-handle action",resolved)
	link.synchronize_impulse_roster(players)
	if resolved.ok:
		for request in resolved.physics_requests:
			_check(link.can_accept_impulse(request.entity_id,request.impulse,1,1).ok,"actual isolation impulse precheck")
		_check(rules.commit(resolved,values,true).ok,"isolation actor pays actual Rules transaction")
		for request in resolved.physics_requests: _check(link.apply_authorized_impulse(request.entity_id,request.impulse,1,1).ok,"approved isolation input applies")
	var exclusive:=true
	for i in range(30):
		var step: Dictionary=link.fixed_update(.05,values,players)
		var state: Dictionary=link.status()
		exclusive=exclusive and step.ok and not (state.high_open_fraction>0 and state.low_open_fraction>0)
	_check(exclusive and station.connection_status().trial_ready,"actual high-close then low-open reaches stable same-world TRIAL")
	await _park()

func _two_manual_routes() -> void:
	for row in [[Vector3(22,2.2,-2.52),0.0,"RB",Runtime.RECEIVER_B],[Vector3(14,2.2,-2.52),.8,"RA",Runtime.RECEIVER_A]]:
		await _fresh()
		await _place(1,row[0])
		var result:=_ability("push_pull",Station.SELECTOR,"push")
		_check(result.ok,"actual Rules drives directional trial from accessible side",result)
		var no_short:=true
		for i in range(58):
			result=_tick(.05)
			var valves: Dictionary=station.status().valves
			no_short=no_short and result.ok and not (valves.SourceA>0 and valves.ReceiveA>0) and not (valves.SourceB>0 and valves.ReceiveB>0)
		var paths: Dictionary=station.flow_paths()
		_check(no_short and station.snapshot().axis.position_m==row[1] and paths.destinations==[row[2]] and paths.forward_clear,"whole real path reaches only opposite receiving box",paths)
		_check(int(station.get_water_node(row[3]).volume_ml)>=20000,"twenty-litre sample comes from real transfer after routed actuation",{"volumes":_volumes()})
		_check(_volumes()[0]+_volumes()[1]+_volumes()[2]==200000,"connected forward motion preserves exact closed-loop volume")
		_valve_rays()
	await _park()

func _valve_rays() -> void:
	var values: Dictionary=station.status().valves
	for spec in station.layout().valves:
		var center:=station.to_global(Vector3(spec.center[0],spec.center[1],spec.center[2]))
		var normal:=Vector3.UP if spec.id=="Check" else Vector3.RIGHT
		var hit:=_ray(center-normal*.025,center+normal*.025)
		if float(values[spec.id])==0:
			_check(not hit.is_empty() and hit.collider==station.valve_bodies[spec.id],"closed seat has a real blocking leaf: "+spec.id)
		elif float(values[spec.id])==1:
			_check(hit.is_empty(),"open seat has real bore clearance: "+spec.id)

func _pose_axis(distance: float) -> void:
	var saved: Dictionary=station.snapshot()
	saved.axis.position_m=distance
	saved.axis.velocity_mps=0.0
	saved.return_valves={"a":0.0,"b":0.0,"check":0.0}
	saved.return_requested=false
	_check(station.apply_snapshot(saved).ok,"explicit valid axis fixture; water and sample ledger untouched")
	station.synchronize_impulse_roster(players)

func _pipe_disconnect() -> void:
	await _fresh()
	_pose_axis(0)
	var blocker:=_prop(Vector3(15.515,.15,-7.0),Vector3(.03,.03,.02))
	await _settle()
	for i in range(4): _tick(.25)
	_check(_volumes()==[200000,0,0] and not station.flow_paths().forward_clear,"real blocked external bore breaks route, not merely its display")
	blocker.queue_free()
	await _settle()
	var id: String=station.fixed_bodies.keys()[0]
	var body: StaticBody3D=station.fixed_bodies[id]
	var prior:=body.transform
	body.position+=Vector3.RIGHT*.1
	body.force_update_transform()
	var before: Dictionary=station.snapshot()
	_check(not _tick(.1).ok and station.snapshot()==before,"changed physical geometry invalidates its connection proof atomically")
	body.transform=prior
	body.force_update_transform()
	PhysicsServer3D.body_set_state(body.get_rid(),PhysicsServer3D.BODY_STATE_TRANSFORM,body.global_transform)
	await _fresh()
	_pose_axis(0)
	var normal: Dictionary=link.snapshot()
	normal.axis.position_m=0
	normal.axis.velocity_mps=0
	_check(link.apply_snapshot(normal).ok,"actual NORMAL pose fixture closes low route")
	for i in range(4): _tick(.25)
	_check(_volumes()==[200000,0,0] and not station.flow_paths().forward_clear,"closed real cross-link rejects new credit despite A selector")
	normal.axis.position_m=.8
	_check(link.apply_snapshot(normal).ok,"restore real stable trial for further independent faults")

func _leaf_obstructions() -> void:
	for id in ["SourceA","SourceB","ReceiveA","ReceiveB"]:
		await _fresh()
		var spec: Dictionary=station._valve_spec(id)
		var point:=station.to_global(Vector3(spec.center[0],spec.center[1],spec.center[2])+Vector3.UP*.07)
		var blocker:=_prop(point,Vector3(.01,.01,.01))
		await _settle()
		serial+=1
		var impulse:=Vector3.LEFT*9 if id in ["SourceA","ReceiveB"] else Vector3.RIGHT*9
		_check(station.apply_authorized_impulse(Station.SELECTOR,impulse,1,serial).ok,"approved input before routed-leaf fault: "+id)
		var before: Dictionary=station.snapshot()
		var result:=_tick(.25)
		_check(result.ok and result.valve_blocked and station.snapshot().runtime==before.runtime and station.snapshot().axis.position_m==before.axis.position_m and station.snapshot().return_valves==before.return_valves,"intermediate leaf obstruction rejects whole water/credit/pose candidate: "+id,result)
		blocker.queue_free()
		await _settle()
	for id in ["ReturnA","ReturnB","Check"]:
		await _fresh()
		_pose_axis(.8 if id!="ReturnB" else 0.0)
		for i in range(9): _tick(.25)
		_pose_axis(.4)
		entities[Station.RELAY].powered=true # explicit authorized power fixture
		await _place(1,Vector3(18,1.35,-.5))
		_check(station.request_return(1,players[1]).ok,"real return switch before intake/check fault")
		if id=="Check": _tick(.25) # actual intake must open first
		var spec: Dictionary=station._valve_spec(id)
		var shift:=Vector3(spec.travel[0],spec.travel[1],spec.travel[2])*.5
		var point:=station.to_global(Vector3(spec.center[0],spec.center[1],spec.center[2])+shift)
		var blocker:=_prop(point,Vector3(.01,.01,.01))
		await _settle()
		var before: Dictionary=station.snapshot()
		var result:=_tick(.25)
		_check(result.ok and result.valve_blocked and station.snapshot().runtime==before.runtime and station.snapshot().return_valves==before.return_valves,"return intake/check full sweep cannot consume water or clock through obstacle: "+id,result)
		blocker.queue_free()
		await _settle()

func _return_sequence() -> void:
	await _fresh()
	for endpoint in [0.0,.8]:
		_pose_axis(endpoint)
		for i in range(9): _tick(.25)
	_pose_axis(.4)
	entities[Station.RELAY].powered=true # fixture isolates hydraulic valve order
	await _place(1,Vector3(18,1.35,-.5))
	_check(station.request_return(1,players[1]).ok,"real near switch begins two-box return")
	var history: Dictionary=station.status().samples
	var ordered:=true
	var no_mid_call_switch:=true
	for i in range(36):
		var before: Dictionary=station.snapshot()
		var prior:=_volumes()
		var result:=_tick(.25)
		var current:=_volumes()
		var gates: Dictionary=station.snapshot().return_valves
		ordered=ordered and result.ok and not (float(gates.a)>0 and float(gates.b)>0)
		if current[2]<prior[2]:
			no_mid_call_switch=no_mid_call_switch and prior[1]==0 and float(before.return_valves.b)==1 and float(before.return_valves.a)==0 and float(before.return_valves.check)==1
		if current[1]<prior[1]:
			ordered=ordered and float(before.return_valves.a)==1 and float(before.return_valves.b)==0 and float(before.return_valves.check)==1
	_check(ordered and no_mid_call_switch,"return A-empty boundary never secretly credits B before its actual intake/check opens")
	_check(_volumes()==[200000,0,0] and station.status().samples==history,"return uses same 200L and preserves samples")
	_valve_rays()
	var volumes:=_volumes()
	entities[Station.RELAY].powered=false
	for i in range(8): _tick(.25)
	_check(_volumes()==volumes and station.snapshot().return_valves=={"a":0.0,"b":0.0,"check":0.0},"stopped pump has closed intakes/check and no gravity reverse bypass")

func _restore_connections() -> void:
	await _fresh()
	var before: Dictionary=station.snapshot()
	var bad:=before.duplicate(true)
	bad.return_valves={"a":1.0,"b":1.0,"check":1.0}
	_check(not station.apply_snapshot(bad).ok and station.snapshot()==before,"impossible simultaneous return intakes reject atomically")
	var view:=SubViewport.new()
	view.own_world_3d=true
	root.add_child(view)
	var remote:=Link.new()
	_check(remote.configure().ok,"foreign-world real Link fixture")
	view.add_child(remote)
	_check(not station.attach_link(remote).ok and station.connection_status().ok,"another World3D cannot replace the valid real link")
	view.queue_free()
	await _settle()
	link.queue_free()
	await _settle()
	_pose_axis(0)
	var water_before: Dictionary=station.snapshot().runtime
	for i in range(4): _tick(.25)
	_check(not station.connection_status().ok and station.snapshot().runtime==water_before,"freed actual Link loses permission without fabricating or consuming saved trial credit")
