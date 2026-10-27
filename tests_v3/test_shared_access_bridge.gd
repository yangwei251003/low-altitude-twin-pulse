extends "res://tests_v3/test_distribution_trial_floor.gd"
## Actual production I2 geometry with one explicitly supplied bridge. Pilot placement,
## per-action energy and restored mechanism poses are explicit isolated fixtures.
const World = preload("res://scripts/v3/twin_test_world.gd")
const Bridge = preload("res://scripts/v3/world/twin_shared_access_bridge.gd")
const BridgeArt = preload("res://scripts/v3/art/twin_shared_bridge_art.gd")
const Rules = preload("res://scripts/v3/gameplay/twin_ability_rules.gd")
var bridge: Node3D
var initial: Dictionary={}
var rules=Rules.new()

func _run() -> void:
	_check_restored_art()
	create_timer(90).timeout.connect(func():
		if not finished:
			print("SHARED_ACCESS_TIMEOUT "+JSON.stringify({"checks":checks,"failures":failures,"engine_errors":logger.errors}))
			quit(2))
	viewport=SubViewport.new()
	viewport.own_world_3d=true
	viewport.world_3d=World3D.new()
	root.add_child(viewport)
	bridge=Bridge.new()
	var configured: Dictionary=bridge.load_layout()
	_check(configured.ok,"bridge configures detached before production World adopts it",configured)
	if not configured.ok:
		bridge.free()
		await _finish()
		return
	var production=World.new()
	# Match MAIN lifecycle: the real TrialAssembly must bind only after the
	# production World already belongs to its actual physics space.
	viewport.add_child(production)
	production.build("I2",{},true,{"shared_access":bridge})
	world=production
	_check(production.build_errors.is_empty(),"actual production I2 builds with current reception/pump/cabinet",{"errors":production.build_errors})
	if not production.build_errors.is_empty():
		if bridge.get_parent()==null: bridge.free()
		world.free()
		await _finish()
		return
	var bridge_count:=0
	for child in production.get_children():
		if child is Bridge: bridge_count+=1
	_check(bridge_count==1 and production.shared_access==bridge,"production contains exactly the supplied bridge, not an overlapping default")
	cabinet=production.distribution
	for row in [[1,"tr01"],[2,"hx02"]]:
		var body:=FlightBody.new()
		body.configure(Catalog.resolve_build(Catalog.default_build(row[1])))
		body.freeze=true
		body.position=Vector3(25,12+int(row[0])*2,20)
		world.add_child(body)
		body.set_process(false)
		body.set_physics_process(false)
		players[row[0]]=body
	var opened: Dictionary=cabinet.snapshot()
	opened.axis.position_m=1.2
	opened.axis.velocity_mps=0.0
	opened.door_fraction=1.0
	opened.electric_latched=true
	_check(cabinet.apply_snapshot(opened).ok,"declared cabinet open-save fixture for unchanged 30 sight lines")
	await _settle()
	var before_rays:=_thirty_rays()
	var expected_rays: Array=[]
	for _observer in OBSERVERS:
		for panel in cabinet.layout().panels:
			for _sample in range(5): expected_rays.append(str(cabinet.panel_bodies[panel.id].name))
	_check(before_rays.size()==30 and before_rays==expected_rays,"all 30 production open-cabinet rays first hit their intended back panels",{"actual":before_rays,"expected":expected_rays})
	initial=bridge.snapshot()
	for row in bridge.target_definitions(): entities[row.id]=row
	await _settle()
	_check(bridge.synchronize_impulse_roster(players).ok,"real TR/HX roster accepted")
	_geometry_and_routes(before_rays)
	await _existing_trial_access()
	await _handle_access()
	await _manual_operation()
	await _powered_operation()
	await _fixed_rate_motor_endpoints()
	await _obstructions()
	await _lifecycle()
	await _finish()

func _pose(position_m: float,pin_m: float) -> void:
	var state: Dictionary=initial.duplicate(true)
	state.axis.position_m=position_m
	state.pin.position_m=pin_m
	_check(bridge.apply_snapshot(state).ok,"declared mechanism-pose fixture validates")
	entities={}
	for row in bridge.target_definitions(): entities[row.id]=row
	bridge.set_simulation_paused(false)
	_check(bridge.synchronize_impulse_roster(players).ok,"restored fixture resynchronizes real roster")
	_check(_tick(.01).ok,"no-control tick releases restore authorization interlock")

func _tick(delta: float) -> Dictionary:
	var result: Dictionary=bridge.fixed_update(delta,entities,players)
	var advance: Dictionary=rules.advance_states(entities,delta)
	if advance.ok: rules.commit(advance,entities,true)
	return result

func _ability(ability: String,id: String,mode: String="",peer: int=1) -> Dictionary:
	var body: FlightBody=players[peer]
	var target: Vector3=bridge.entity_position(id)
	var excluded: Array[RID]=[body.get_rid()]
	var ray:=PhysicsRayQueryParameters3D.create(body.global_position,target,0xFFFFFFFF,excluded)
	var hit:=world.get_world_3d().direct_space_state.intersect_ray(ray)
	var visible: bool=not hit.is_empty() and hit.collider==bridge.target_bodies[id]
	var actor: String="qa:pilot"+str(peer)
	entities[actor]={"id":actor,"owner":str(peer),"tags":["player"],"position":body.global_position,"health":100.0,"energy":100.0,"revision":0}
	entities[id].position=target
	var resolved: Dictionary=rules.resolve({"ability":ability,"actor_id":actor,"target_id":id,"mode":mode},entities,{"sender_id":str(peer),"line_of_sight":visible})
	if not resolved.ok: return resolved
	action_serial+=1
	for request in resolved.physics_requests:
		var accepted: Dictionary=bridge.can_accept_impulse(request.entity_id,request.impulse,peer,action_serial)
		if not accepted.ok: return accepted
	var committed: Dictionary=rules.commit(resolved,entities,true)
	if not committed.ok: return committed
	for request in resolved.physics_requests:
		var accepted: Dictionary=bridge.apply_authorized_impulse(request.entity_id,request.impulse,peer,action_serial)
		if not accepted.ok: return accepted
	return {"ok":true,"code":"real_rule_executed","first_hit":str(hit.collider.name)}

func _geometry_and_routes(before_rays: Array) -> void:
	_check(_thirty_rays()==before_rays,"new southern bridge preserves all 30 existing cabinet first hits")
	var same:=true
	for body in bridge.fixed_bodies.values()+bridge.moving_bodies.values()+bridge.pin_bodies.values():
		same=same and body.get_child(0).shape.size.is_equal_approx(body.get_node("Visual").mesh.size)
	_check(same,"all deck, rail, bearing and locking solids share exact render/collision size")
	for mode in [[0.0,"public_span"],[8.0,"service_span"]]:
		_pose(mode[0],.3)
		var access: Dictionary=bridge.access_report()
		_check(access.choice_ready and access.mode==mode[1],"both 3 m supported and unobstructed service routes exist at "+str(mode[1]),access)
		var routes: Dictionary=access.routes
		var selected: String="public_short" if mode[0]==0 else "service_short"
		var detour: String="public_bypass" if mode[0]==0 else "service_bypass"
		_check(routes[selected].ok and routes[detour].ok and routes[selected].length_m<routes[detour].length_m,"selected configuration yields a real shorter route, not only a label",access)
		measurements[str(mode[1])]=access
		_check(_thirty_rays()==before_rays,"all old sight rays stay unchanged at "+str(mode[1]))
		for peer in players:
			_check(_body_sweep(peer,Vector3(15,2.1,-4),Vector3(15,2.1,11)).ok,"full TR/HX envelope traverses under supported bridge in "+str(mode[1]),{"peer":peer})
			var flight: Dictionary=_body_sweep(peer,Vector3(10.1,6.45,float(mode[0])),Vector3(19.7,6.45,float(mode[0])))
			_check(flight.ok,"full TR/HX can fly above actual short bridge deck",{"peer":peer,"mode":mode[1],"sweep":flight})
			_check(_body_sweep(peer,Vector3(18,2.3,-7.7),Vector3(18,2.3,-11.2)).ok,"old low cabinet entry unaffected by southern support columns",{"peer":peer})
	_pose(4,0)
	var middle: Dictionary=bridge.access_report()
	_check(not middle.choice_ready and middle.routes.public_bypass.ok and middle.routes.service_bypass.ok,"mid-travel never claims locked choice; fixed bypass remains supported",middle)
	for peer in players:
		_check(_body_sweep(peer,Vector3(10.1,8,0),Vector3(19.7,8,0)).ok,"flight can freely cross above gap without choosing a bridge mode",{"peer":peer})
	var excluded: Array[RID]=[cabinet.cover.get_rid()]
	_check(cabinet._sweep_clear(Vector3(1.2,.16,1.9),Vector3(0,4.08,-1.45),Vector3(1.2,4.08,-1.45),excluded),"whole old cover sweep remains clear")
	excluded=[cabinet.door.get_rid()]
	_check(cabinet._sweep_clear(Vector3(3.4,2.8,.2),Vector3(0,2.605,1),Vector3(0,5.605,1),excluded),"whole old door sweep remains clear")

func _existing_trial_access() -> void:
	# The default production World already owns the connected trial. Never
	# duplicate it or move its historic approach to hide the new bridge's impact.
	var assembly: Variant=world.get("trial")
	_check(is_instance_valid(assembly) and assembly.connection_status().ok,"existing production Trial remains the actual connected assembly")
	if not is_instance_valid(assembly): return
	var station: Variant=assembly.station
	var link: Variant=assembly.link
	await _park()
	_pose(0,.3)
	for peer in players:
		await _place(peer,Vector3(18,2.5,-.5))
		var clear: Dictionary=_body_sweep(peer,players[peer].global_position,players[peer].global_position)
		_check(clear.ok,"original TR/HX trial control approach retains the entire real hull envelope",{"peer":peer,"clearance":clear,"position":str(players[peer].global_position)})
		for id in [station.CONTROLLER,station.RELAY,station.SELECTOR]:
			var proof: Dictionary=_existing_target_ray(peer,station,id)
			_check(proof.target_hit,"original trial approach first-hits the actual controller/relay/selector after bridge integration",proof)
		await _place(peer,Vector3(16,1.3,-5.3))
		clear=_body_sweep(peer,players[peer].global_position,players[peer].global_position)
		_check(clear.ok,"original TR/HX low isolation-handle approach retains the full hull envelope",{"peer":peer,"clearance":clear,"position":str(players[peer].global_position)})
		var isolation: Dictionary=_existing_target_ray(peer,link,link.HANDLE)
		_check(isolation.target_hit,"original low isolation approach first-hits its real handle",isolation)
		await _park()
	var supported: bool=not bridge.fixed_bodies.has("PublicSocketPost") and bridge.fixed_bodies.has("PublicSocketCantilever") and bridge.fixed_bodies.has("EastTrackPier0")
	_check(supported,"trial-view-blocking ground post is replaced by a real cantilever and retained track pier")
	if not supported: return
	var beam: AABB=_bridge_box(bridge.fixed_bodies.PublicSocketCantilever)
	var pier: AABB=_bridge_box(bridge.fixed_bodies.EastTrackPier0)
	var common: Vector3=beam.end.min(pier.end)-beam.position.max(pier.position)
	_check(common.x>.001 and common.y>.001 and common.z>.001,"cantilever has a real three-dimensional joint into the original track pier",{"cantilever":str(beam),"pier":str(pier),"joint_depth":str(common)})
	var socket_contacts: Array=[]
	var all_supported:=true
	for id in ["PublicSocketL","PublicSocketR","PublicSocketN","PublicSocketS"]:
		var socket: AABB=_bridge_box(bridge.fixed_bodies[id])
		var overlap: Vector3=beam.end.min(socket.end)-beam.position.max(socket.position)
		var contact: bool=absf(beam.end.y-socket.position.y)<.00001 and overlap.x>.001 and overlap.z>.001
		all_supported=all_supported and contact
		socket_contacts.append({"socket":id,"box":str(socket),"bearing_width_xz":str(Vector2(overlap.x,overlap.z)),"vertical_gap":socket.position.y-beam.end.y,"contact":contact})
	_check(all_supported,"all four unchanged socket pieces rest on real cantilever bearing area",{"contacts":socket_contacts})
	measurements.trial_access_support={"cantilever":str(beam),"pier":str(pier),"socket_contacts":socket_contacts,"limits":"Physical contact geometry, not a structural load calculation."}

func _existing_target_ray(peer: int,facility: Variant,id: String) -> Dictionary:
	var body: FlightBody=players[peer]
	var destination: Vector3=facility.entity_position(id)
	var excluded: Array[RID]=[body.get_rid()]
	var query:=PhysicsRayQueryParameters3D.create(body.global_position,destination,0xFFFFFFFF,excluded)
	var hit: Dictionary=world.get_world_3d().direct_space_state.intersect_ray(query)
	return {"peer":peer,"target_id":id,"observer":str(body.global_position),"target":str(destination),
		"first_hit":"" if hit.is_empty() else str(hit.collider.get_path()),"hit_position":"" if hit.is_empty() else str(hit.position),
		"target_hit":not hit.is_empty() and hit.collider==facility.target_bodies[id]}

func _bridge_box(body: StaticBody3D) -> AABB:
	var collision: CollisionShape3D=body.get_child(0)
	var size: Vector3=collision.shape.size
	return collision.global_transform*AABB(-size*.5,size)

func _handle_access() -> void:
	# Actual full-size pilots outside the moving deck, on either side. The
	# relocated handle must remain the first real ray hit and move the axis in
	# both signed directions through production push/pull, not direct impulses.
	for peer in players:
		for side in [-1.0,1.0]:
			for mode in ["","pull"]:
				await _park()
				_pose(4,0)
				await _place(peer,Vector3(12.5,6.1,4.0+float(side)*4.0))
				var clearance: Dictionary=_body_sweep(peer,players[peer].global_position,players[peer].global_position)
				_check(clearance.ok,"TR/HX real handle approach starts clear on either side",{"peer":peer,"side":side,"mode":mode,"sweep":clearance})
				var applied: Dictionary=_ability("push_pull",Bridge.HANDLE,mode,peer)
				var moved: Dictionary=_tick(.05)
				var expected_sign: float=float(side) if mode=="pull" else -float(side)
				_check(applied.ok and moved.ok and not moved.get("blocked",false) and (float(bridge.snapshot().axis.position_m)-4.0)*expected_sign>0.0,"relocated handle is visible and supports real push/pull from both sides and both airframes",{"peer":peer,"side":side,"mode":mode,"ability":applied,"motion":moved})
	await _park()

func _manual_operation() -> void:
	await _park()
	_pose(0,.3)
	action_serial+=1
	_check(not bridge.can_accept_impulse(Bridge.HANDLE,Vector3.BACK*9,1,action_serial).ok,"inserted physical pin rejects bridge impulse before spending an action")
	await _place(1,Vector3(17.4,7.5,-1.9))
	var release:=_ability("push_pull",Bridge.PIN,"pull")
	_check(release.ok,"real upward pull on visible pin withdraws it",release)
	for unused in range(12): _tick(.05)
	_check(bridge.snapshot().pin.position_m==0.0 and not bridge.status().locked,"pin physically retracts before bridge can move",bridge.status())
	await _place(1,Vector3(12.5,6.15,-4))
	var all_accepted:=true
	for pulse in range(14):
		if bridge.snapshot().axis.position_m==8.0: break
		all_accepted=all_accepted and _ability("push_pull",Bridge.HANDLE).ok
		for unused in range(7): _tick(.05)
	_check(all_accepted and bridge.snapshot().axis.position_m==8.0 and not bridge.status().locked,"multiple real limited impulses move the 8 m bridge without teleporting or auto-locking",bridge.status())
	await _place(1,Vector3(17.4,7.5,6.1))
	var lock:=_ability("push_pull",Bridge.PIN)
	_check(lock.ok,"real downward push aligns pin with service socket",lock)
	for unused in range(12): _tick(.05)
	await _park()
	_check(bridge.status().mode=="service_span" and bridge.access_report().choice_ready,"manual service configuration is only ready after actual pin insertion",bridge.status())

func _powered_operation() -> void:
	await _park()
	_pose(0,.3)
	await _place(1,Vector3(19.7,7.1,3.5))
	_check(_ability("charge",Bridge.RELAY).ok,"real production charge reaches corridor-side relay")
	for unused in range(8): _tick(.05)
	_check(bridge.snapshot().axis.position_m==0 and bridge.status().locked,"power alone cannot choose or move bridge")
	_check(_ability("takeover",Bridge.SERVICE_CONTROL).ok,"specific service target receives actual takeover")
	var elapsed:=0.0
	var clear:=true
	while elapsed<8 and bridge.status().mode!="service_span":
		var result:=_tick(.05)
		clear=clear and result.ok and not result.get("blocked",false)
		elapsed+=.05
	measurements.motor_seconds=elapsed
	_check(clear and elapsed<8 and bridge.status().mode=="service_span","authorized motor physically unlocks, translates, then locks before takeover expiry",bridge.status())
	for unused in range(45): _tick(.05)
	await _park()
	_pose(0,.3)
	entities[Bridge.RELAY].powered=true
	entities[Bridge.SERVICE_CONTROL].controlled=true
	entities[Bridge.SERVICE_CONTROL].owner="1"
	entities[Bridge.SERVICE_CONTROL].takeover_remaining=8.0
	for unused in range(25): _tick(.05)
	var stopped: Dictionary=bridge.snapshot()
	players[1].enabled=false
	for unused in range(6): _tick(.05)
	_check(bridge.snapshot().axis.position_m==stopped.axis.position_m and bridge.snapshot().pin.position_m==stopped.pin.position_m and not bridge.status().motor_active,"disabled controller owner cannot continue motor motion")
	players[1].enabled=true
	entities[Bridge.RELAY].powered=false
	for unused in range(6): _tick(.05)
	_check(bridge.snapshot().axis.position_m==stopped.axis.position_m,"unpowered motor remains at real partial position")
	_pose(0,0)
	entities[Bridge.RELAY].powered=true
	for pair in [[Bridge.PUBLIC_CONTROL,1],[Bridge.SERVICE_CONTROL,2]]:
		entities[pair[0]].controlled=true
		entities[pair[0]].owner=str(pair[1])
		entities[pair[0]].takeover_remaining=8.0
	_check(_tick(.25).ok and bridge.snapshot().axis.position_m==0 and bridge.snapshot().pin.position_m==0,"two simultaneous opposing motor owners cannot silently choose a winner")

func _fixed_rate_motor_endpoints() -> void:
	# Exercise ordinary engine-rate deltas, not only the older .05 fixture.
	# No endpoint, pin or target success is assigned after the starting pose.
	for rate in [60,120]:
		for row in [[0.0,Bridge.SERVICE_CONTROL,"service_span",8.0],[8.0,Bridge.PUBLIC_CONTROL,"public_span",0.0]]:
			await _park()
			_pose(row[0],.3)
			await _place(1,Vector3(19.7,7.1,3.5))
			_check(_ability("charge",Bridge.RELAY).ok and _ability("takeover",row[1]).ok,"real motor authorization at %d Hz toward %s" % [rate,row[2]])
			var delta := 1.0 / float(rate)
			var healthy := true
			var frames := 0
			while frames < rate * 8 and bridge.status().mode != row[2]:
				var result := _tick(delta)
				healthy = healthy and result.ok and not result.get("blocked",false)
				frames += 1
			var snapshot: Dictionary = bridge.snapshot()
			_check(healthy and bridge.status().mode == row[2] and snapshot.axis.position_m == row[3] and snapshot.pin.position_m == .3 and bridge.validate_snapshot(snapshot).ok,"%d Hz reaches exact %s socket then inserts pin before authorization expires" % [rate,row[2]],{"status":bridge.status(),"frames":frames})
	await _park()

func _obstructions() -> void:
	await _park()
	_pose(0,.3)
	# Preserve the exact failed grip volume as an external obstruction. Passing
	# after relocation must come from geometry, never excluding handles/props.
	var old_handle:=_obstacle(Vector3(12.5,6.15,0),Vector3(.3,.2,.4))
	await _settle()
	var old_gap: Dictionary=bridge.access_report()
	_check(not old_gap.choice_ready and old_gap.routes.public_short.code=="route_obstructed" and str(old_handle.get_path()) in old_gap.routes.public_short.get("colliders",[]),"former central handle volume still blocks the unchanged 3 m route",old_gap)
	old_handle.queue_free()
	await _settle()
	_check(bridge.access_report().choice_ready,"removing the external old-handle volume restores the actual supported short route")
	for row in [[Vector3(15,4.8,1.9),Vector3(.2,.2,.2),"deck"],[Vector3(12.17,4.4,.8),Vector3(.08,.12,.08),"carriage"],[Vector3(15,5.5,1.9),Vector3(.2,.2,.2),"guard"]]:
		_pose(0,0)
		var prop:=_obstacle(row[0],row[1])
		await _settle()
		action_serial+=1
		_check(bridge.apply_authorized_impulse(Bridge.HANDLE,Vector3.BACK*9,1,action_serial).ok,"authorized axis fixture accepted before "+str(row[2])+" sweep")
		var result:=_tick(.25)
		_check(result.ok and result.blocked and bridge.snapshot().axis.position_m==0 and bridge.snapshot().axis.velocity_mps==0,"whole "+str(row[2])+" path blocks before any partial bridge commit",result)
		prop.queue_free()
		await _settle()
		_check(_tick(.1).ok and bridge.snapshot().axis.position_m==0,"removing obstruction releases no stored impulse")
	for peer in players:
		_pose(0,0)
		await _place(peer,Vector3(15,5.5,2.8))
		_check(_body_sweep(peer,players[peer].global_position,players[peer].global_position).ok,"blocking pilot begins outside existing bridge volume",{"peer":peer})
		action_serial+=1
		_check(bridge.apply_authorized_impulse(Bridge.HANDLE,Vector3.BACK*9,1,action_serial).ok,"body-envelope sweep receives real impulse fixture")
		var result:=_tick(.25)
		_check(result.ok and result.blocked and bridge.snapshot().axis.position_m==0,"full TR/HX envelope stops advancing guard before penetration",{"peer":peer,"result":result})
		await _park()
	_pose(0,0)
	var socket_prop:=_obstacle(Vector3(17.4,4.18,-1.9),Vector3(.06,.06,.06))
	await _settle()
	action_serial+=1
	_check(bridge.apply_authorized_impulse(Bridge.PIN,Vector3.DOWN*9,1,action_serial).ok,"explicit pin impulse fixture accepted")
	var pin_result:=_tick(.25)
	_check(pin_result.ok and pin_result.blocked and bridge.snapshot().pin.position_m==0 and not bridge.status().locked,"obstructed real socket prevents entire pin step and readiness",pin_result)
	socket_prop.queue_free()
	await _settle()
	_pose(0,0)
	var first_velocity:=0.0
	for order in [[1,2],[2,1]]:
		_pose(0,0)
		for peer in order:
			action_serial+=1
			_check(bridge.apply_authorized_impulse(Bridge.HANDLE,Vector3.BACK*(9 if peer==1 else -9),peer,action_serial).ok,"same-tick opposite peer input is accepted")
		_tick(.1)
		first_velocity=float(bridge.snapshot().axis.velocity_mps)
		_check(bridge.snapshot().axis.position_m==0 and first_velocity==0,"same-tick opposite impulses cancel independently of arrival order")
	_pose(0,0)
	action_serial+=1
	bridge.apply_authorized_impulse(Bridge.HANDLE,Vector3.BACK*9,1,action_serial)
	entities[Bridge.HANDLE].pinned=true
	entities[Bridge.HANDLE].field_remaining=4.0
	_tick(.1)
	_check(bridge.snapshot().axis.position_m==0 and bridge.snapshot().axis.velocity_mps==0,"force field physically stops accepted velocity without delayed release")
	entities[Bridge.HANDLE].pinned=false
	entities[Bridge.HANDLE].field_remaining=0.0
	_tick(.1)
	_check(bridge.snapshot().axis.position_m==0,"field expiry does not replay stopped input")
	_pose(0,0)
	action_serial+=1
	bridge.apply_authorized_impulse(Bridge.HANDLE,Vector3.BACK*9,2,action_serial)
	var accepted_velocity: float=bridge.snapshot().axis.velocity_mps
	_check(bridge.reset_impulse_peer(1).ok and bridge.snapshot().axis.velocity_mps==accepted_velocity,"one peer lifecycle reset preserves the other peer's already accepted momentum")
	_check(_tick(.1).ok and bridge.snapshot().axis.position_m>0,"unaffected peer input still drives the actual bridge after teammate reset")

func _lifecycle() -> void:
	await _park()
	_pose(0,0)
	var before: Dictionary=bridge.snapshot()
	_check(bridge.fixed_update(0,entities,players).ok and bridge.snapshot()==before,"zero delta preserves snapshot exactly")
	_check(not bridge.fixed_update(.1,entities,players,false).ok and bridge.snapshot()==before,"caller lacking host authority cannot advance")
	for mutation in ["unknown","version","pin_midway","velocity_locked","nan","roster"]:
		var bad: Dictionary=before.duplicate(true)
		match mutation:
			"unknown": bad.extra=true
			"version": bad.version=true
			"pin_midway": bad.axis.position_m=4; bad.pin.position_m=.3
			"velocity_locked": bad.pin.position_m=.3; bad.axis.velocity_mps=1
			"nan": bad.axis.position_m=NAN
			"roster": bad.pin.last_serial={}
		_check(not bridge.apply_snapshot(bad).ok and bridge.snapshot()==before,"invalid restore is atomic: "+mutation)
	action_serial+=1
	bridge.apply_authorized_impulse(Bridge.HANDLE,Vector3.BACK*9,1,action_serial)
	bridge.set_simulation_paused(true)
	var paused: Dictionary=bridge.snapshot()
	for unused in range(4): bridge.fixed_update(.25,entities,players)
	_check(bridge.snapshot()==paused and paused.axis.velocity_mps==0,"pause clears accepted momentum once and adds no backlog")
	bridge.set_simulation_paused(false)
	_tick(.1)
	_check(bridge.snapshot().axis.position_m==0,"resume never applies pre-pause impulse")
	_pose(8,.3)
	var saved: Dictionary=JSON.parse_string(JSON.stringify(bridge.snapshot(),"",true,true))
	var guest=Bridge.new()
	var checked: Dictionary=guest.load_layout(saved,false)
	_check(checked.ok,"strict JSON snapshot configures a client before tree",checked)
	var isolated:=SubViewport.new()
	isolated.own_world_3d=true
	isolated.world_3d=World3D.new()
	root.add_child(isolated)
	isolated.add_child(guest)
	await _settle()
	_check(guest.status().mode=="service_span" and guest.moving_bodies.BridgeDeck.position==bridge.moving_bodies.BridgeDeck.position and guest.pin_bodies.LockRod.position==bridge.pin_bodies.LockRod.position,"client first physical frame already matches restored bridge and pin")
	var client_before: Dictionary=guest.snapshot()
	_check(not guest.fixed_update(.1,entities,{}).ok and guest.snapshot()==client_before,"client has no autonomous mechanism simulation")
	guest.set_simulation_paused(true)
	_check(guest.snapshot()==client_before and guest.apply_snapshot(saved).ok,"client pause is presentation-only and reliable snapshot remains valid")
	var copy: Dictionary=guest.snapshot()
	copy.axis.position_m=0
	_check(guest.snapshot()==client_before,"returned snapshots cannot mutate the authoritative mechanism")
	isolated.queue_free()
	await _settle()
	var malformed: Variant=JSON.parse_string(FileAccess.get_file_as_string(Bridge.PATH))
	malformed.moving[0].size=[0,1,1]
	var rejected=Bridge.new()
	_check(not rejected.configure(malformed).ok and rejected.get_child_count()==0,"invalid layout rejects before building any physical nodes")
	rejected.free()

func _check_restored_art() -> void:
	var seed = Bridge.new()
	var ready: Dictionary = seed.load_layout()
	_check(ready.ok,"seed bridge configures for authored-art restore regression",ready)
	if not ready.ok:
		seed.free()
		return
	var saved: Dictionary = seed.snapshot()
	seed.free()
	for pose: Array in [[3.5,0.0],[8.0,.3]]:
		var state: Dictionary = saved.duplicate(true)
		state.axis.position_m = pose[0]
		state.pin.position_m = pose[1]
		var restored = Bridge.new()
		var loaded: Dictionary = restored.load_layout(state)
		_check(loaded.ok,"nonzero saved bridge pose configures before art install",loaded)
		if not loaded.ok:
			restored.free()
			continue
		var before: Dictionary = restored.snapshot()
		var art: Dictionary = BridgeArt.install(restored)
		_check(art.get("ok",false),"actual GLB installs on restored authority bodies",{"pose":str(pose),"code":art.get("code","")})
		if art.get("ok",false):
			var matched := true
			for row: Dictionary in art.parts:
				var local_offset := Vector3(0,-float(pose[1]) if str(row.id) in ["LockRod","LockGrip"] else 0.0,float(pose[0]))
				var expected: Transform3D = Transform3D(Basis.IDENTITY,BridgeArt.ORIGIN+local_offset)*row.authored
				var actual: Transform3D = row.body.transform*row.mesh.transform
				matched = matched and actual.is_equal_approx(expected) and not row.body.get_node("Visual").visible
			_check(matched and before == restored.snapshot() and restored.status().pose_valid,
				"restored art has exactly one travel/pin offset and preserves authority state",{"pose":str(pose)})
			var first_child_count: int = restored.get_child_count()
			_check(not BridgeArt.install(restored).ok and restored.get_child_count()==first_child_count,
				"duplicate art installation rejects without duplicating visible parts")
		restored.free()

func _obstacle(at: Vector3,size: Vector3) -> StaticBody3D:
	var prop:=StaticBody3D.new()
	prop.collision_layer=32
	prop.position=at
	var collision:=CollisionShape3D.new()
	var shape:=BoxShape3D.new()
	shape.size=size
	collision.shape=shape
	prop.add_child(collision)
	world.add_child(prop)
	return prop

func _finish() -> void:
	if finished: return
	finished=true
	_check(logger.errors.is_empty(),"no engine errors",{"errors":logger.errors})
	if is_instance_valid(viewport): viewport.queue_free()
	await process_frame
	print("SHARED_ACCESS_RESULT "+JSON.stringify({"checks":checks,"failures":failures,"engine_errors":logger.errors,"measurements":measurements,"scope":"actual_production_I2_with_one_supplied_bridge_not_session_or_resident_ai"}))
	quit(0 if failures.is_empty() else 1)
