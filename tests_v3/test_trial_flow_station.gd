extends SceneTree
## Isolated real physics/Rules fixtures; not a Session playthrough. This bench
## binds the real candidate cabinet/Link. No save or reward is written.
const Link = preload("res://scripts/v3/world/twin_trial_isolation_link.gd")
const FLOOR_PATH := "res://data/v3/terrain/i2_distribution_trial_layout.json"
const Station = preload("res://scripts/v3/world/twin_trial_flow_station.gd")
const Runtime = preload("res://scripts/v3/environment/twin_trial_flow_runtime.gd")
const Cabinet = preload("res://scripts/v3/world/twin_distribution_cabinet.gd")
const FlightBody = preload("res://scripts/v2/flight_body.gd")
const Catalog = preload("res://scripts/v2/catalog.gd")
const Rules = preload("res://scripts/v3/gameplay/twin_ability_rules.gd")
var world: Node3D
var station: Node3D
var cabinet: Node3D
var link: Node3D
var players: Dictionary = {}
var entities: Dictionary = {}
var rules = Rules.new()
var initial: Dictionary = {}
var checks := 0
var failures: Array = []
var measurements: Dictionary = {}
var serial := 500
var finished := false
class ErrorLog extends Logger:
	var errors: Array = []
	func _log_error(fn: String, file: String, line: int, code: String, rationale: String, _notify: bool, kind: int, _traces: Array[ScriptBacktrace]) -> void:
		errors.append({"function":fn,"file":file,"line":line,"code":code,"rationale":rationale,"kind":kind})
var logger := ErrorLog.new()

func _init() -> void:
	OS.add_logger(logger)
	_run.call_deferred()

func _run() -> void:
	create_timer(90).timeout.connect(func():
		if not finished:
			print("TRIAL_STATION_TIMEOUT "+JSON.stringify({"checks":checks,"failures":failures,"engine_errors":logger.errors}))
			quit(2))
	_invalid_layouts()
	world=Node3D.new()
	root.add_child(world)
	cabinet=Cabinet.new()
	var result: Dictionary = cabinet.configure(JSON.parse_string(FileAccess.get_file_as_string(FLOOR_PATH)))
	_check(result.ok,"existing real cabinet configures",result)
	if not result.ok:
		cabinet.free()
		await _finish()
		return
	world.add_child(cabinet)
	_prop(Vector3(18,-.1,-6),Vector3(30,.2,30))
	for row in [[1,"tr01"],[2,"hx02"]]:
		var body := FlightBody.new()
		body.configure(Catalog.resolve_build(Catalog.default_build(row[1])))
		body.freeze=true
		body.position=Vector3(25,12+int(row[0])*2,20)
		world.add_child(body)
		body.set_process(false)
		body.set_physics_process(false)
		players[row[0]]=body
	# Old mechanism is opened by a legal saved-pose fixture solely to compare
	# the SAME thirty original rays before/after adding the independent bench.
	var open: Dictionary = cabinet.snapshot()
	open.axis.position_m=1.2
	open.door_fraction=1.0
	open.electric_latched=true
	_check(cabinet.apply_snapshot(open).ok,"old open saved-pose fixture validates")
	await _settle()
	var original_rays := _cabinet_rays()
	station=Station.new()
	result=station.load_layout()
	_check(result.ok,"real independent bench and water definition configure",result)
	if not result.ok:
		station.free()
		station=null
		await _finish()
		return
	world.add_child(station)
	link=Link.new()
	_check(link.configure().ok,"real isolation fitting configures")
	world.add_child(link)
	var isolation: Dictionary=link.snapshot()
	isolation.axis.position_m=.8
	_check(link.apply_snapshot(isolation).ok,"explicit TRIAL saved-pose fixture; real operation covered by connected suite")
	_check(station.attach_link(link).ok,"bench binds real same-world Link")
	initial=station.snapshot()
	_reset_entities()
	await _settle()
	_check(_cabinet_rays()==original_rays and original_rays.size()==30,"all thirty old first-hit collider/point results unchanged by bench and actual connected pipes")
	await _old_routes()
	_geometry_and_restore()
	await _manual_route()
	await _pulse_and_return()
	await _full_capacity_and_return()
	await _obstruction_and_pause()
	await _client()
	await _finish()

func _check(ok: bool, label: String, details: Dictionary = {}) -> void:
	checks+=1
	if not ok:
		failures.append({"check":label,"details":details})
		print("TRIAL_STATION_FAIL "+label+" "+JSON.stringify(details))

func _settle() -> void:
	await physics_frame
	await physics_frame
	await process_frame

func _place(peer: int, point: Vector3) -> void:
	var body: FlightBody = players[peer]
	body.global_transform=Transform3D(Basis.IDENTITY,point)
	body.linear_velocity=Vector3.ZERO
	body.angular_velocity=Vector3.ZERO
	body.force_update_transform()
	PhysicsServer3D.body_set_state(body.get_rid(),PhysicsServer3D.BODY_STATE_TRANSFORM,body.global_transform)
	await _settle()

func _park() -> void:
	for peer in players:
		players[peer].enabled=true
		players[peer].health=players[peer].maximum_health
		await _place(peer,Vector3(25,12+int(peer)*2,20))

func _reset_entities() -> void:
	entities={}
	for item in station.target_definitions(): entities[item.id]=item

func _fresh() -> void:
	await _park()
	_check(station.apply_snapshot(initial).ok,"fresh explicit bench-state fixture restores")
	_reset_entities()
	station.set_simulation_paused(false)
	_check(station.synchronize_impulse_roster(players).ok,"real two-body roster assigned")
	# Observing inactive controls after restore disarms stale takeover state.
	_check(_tick(.01).ok,"restored controls first resampled inactive")

func _tick(delta: float, roster: Variant = null) -> Dictionary:
	var result: Dictionary = station.fixed_update(delta,entities,players if roster==null else roster)
	if result.ok and delta>0 and result.code!="paused":
		var expiry: Dictionary = rules.advance_states(entities,delta)
		var committed: Dictionary = rules.commit(expiry,entities)
		if not committed.ok: _check(false,"real ability timers commit",committed)
	return result

func _ability(ability: String, target: String, mode: String = "", peer: int = 1) -> Dictionary:
	var actor := "fixture:player:"+str(peer)
	if not entities.has(actor): entities[actor]={"id":actor,"owner":str(peer),"tags":["player"],"position":players[peer].global_position,"energy":100.0,"health":100.0,"revision":0}
	entities[actor].position=players[peer].global_position
	entities[actor].energy=100.0 # Explicit per-action energy fixture, not gameplay.
	entities[target].position=station.entity_position(target)
	var hit := _ray(players[peer].global_position,entities[target].position,[players[peer].get_rid()])
	var visible: bool = not hit.is_empty() and hit.collider.get_meta("entity_id","")==target
	var transaction: Dictionary = rules.resolve({"ability":ability,"actor_id":actor,"target_id":target,"mode":mode},entities,{"sender_id":str(peer),"line_of_sight":visible})
	if not transaction.ok: return transaction
	for request in transaction.physics_requests:
		var check: Dictionary = station.can_accept_impulse(request.entity_id,request.impulse,peer,int(entities[actor].revision)+1)
		if not check.ok: return check
	var committed: Dictionary = rules.commit(transaction,entities,true)
	if not committed.ok: return committed
	for request in transaction.physics_requests:
		var applied: Dictionary = station.apply_authorized_impulse(request.entity_id,request.impulse,peer,int(entities[actor].revision))
		if not applied.ok: return applied
	return committed

func _invalid_layouts() -> void:
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(Station.PATH))
	for key in ["origin","connection","tanks","motor_speed_mps"]:
		var bad := data.duplicate(true)
		match key:
			"origin": bad.origin=[18,1,-3]
			"connection": bad.connection="already_proves_cabinet"
			"tanks": bad.tanks[0].inner_size[0]=.7
			"motor_speed_mps": bad.motor_speed_mps=NAN
		var candidate := Station.new()
		_check(not candidate.configure(bad).ok and candidate.get_child_count()==0 and candidate.snapshot().is_empty(),"invalid layout rejects before any geometry: "+key)
		candidate.free()

func _geometry_and_restore() -> void:
	_check(station.global_position==Vector3(18,0,-3) and station.get_meta("stage")=="connected_low_trial_candidate" and station.connection_status().ok,"main footprint and actual binding status are explicit")
	_check(station.window_bodies.size()==3 and station.float_bodies.size()==3 and station.selector_bodies.size()==3,"real separated tank windows, floats and moving selector parts exist")
	var dimensions_match := true
	for child in station.get_children():
		if child is StaticBody3D:
			dimensions_match=dimensions_match and child.get_node("Visual").mesh.size==child.get_child(0).shape.size
	_check(dimensions_match,"each graybox solid uses matching render and collision dimensions")
	_check(_volumes()==[200000,0,0],"actual source starts at 200 L, receivers empty")
	_check(is_equal_approx(float(station.get_water_node(Runtime.SOURCE).level_m),1.9),"actual source water surface starts at world Y1.9")
	var all_water_visual := true
	for visual in station.water_visuals.values(): all_water_visual=all_water_visual and visual is MeshInstance3D and not visual is CollisionObject3D
	_check(all_water_visual,"liquid volume has no invisible blocking body")
	var before: Dictionary = station.snapshot()
	for mutation in ["digest","water","axis","serial"]:
		var bad := before.duplicate(true)
		match mutation:
			"digest": bad.layout_sha256="unknown"
			"water": bad.runtime["invented_water"]=1
			"axis": bad.axis.position_m=NAN
			"serial": bad.serial=.5
		_check(not station.apply_snapshot(bad).ok and station.snapshot()==before,"malformed snapshot atomic: "+mutation)
	_check(station.apply_snapshot(JSON.parse_string(JSON.stringify(before,"",true,true))).ok,"real JSON numeric round-trip validates")
	_check(station.valve_bodies.size()==7,"four routing leaves, two return intakes and check are independent real shapes")
	for port in station.layout().service_ports:
		var point:=station.to_global(Vector3(port.position[0],port.position[1],port.position[2]))
		var side: float=1.0 if port.id=="A" else -1.0
		var hit:=_ray(point+Vector3.RIGHT*side*.002,point+Vector3.RIGHT*side*.08)
		_check(hit.is_empty(),"external socket continues into a true open Link bore",{"port":port.id})
	var old: Dictionary=before.duplicate(true)
	old.version=1
	old.erase("return_valves")
	var before_rejection: Dictionary=station.snapshot()
	var old_result: Dictionary=station.apply_snapshot(old)
	_check(not old_result.ok and station.snapshot()==before_rejection,"unpublished standalone v1 QA samples cannot silently migrate",old_result)

func _manual_route() -> void:
	await _fresh()
	await _place(1,Vector3(22,2.2,-2.52))
	var pushed := _ability("push_pull",Station.SELECTOR,"push")
	_check(pushed.ok,"real LOS and production push physically actuate selector",pushed)
	var advanced := true
	for i in range(54):
		var result := _tick(.05)
		advanced=advanced and result.ok and result.code!="blocked"
	_check(advanced and station.status().selector_position==-1.0,"manual impulse reaches actual A detent without teleport")
	var after := _volumes()
	_check(after[1]==0 and after[2]>=20000 and after[0]+after[2]==200000,"manual A actually fills receiver B and conserves integer volume",{"volumes":after})
	_check(station.status().samples.A.complete and not station.status().samples.B.complete,"first sample is derived from real positive transfer on the selected route")
	await _place(1,Vector3(14,2.2,-2.52))
	_check(_ability("push_pull",Station.SELECTOR,"push").ok,"opposite real push can return selector toward N")
	for i in range(10): _tick(.05)
	var neutral_volumes := _volumes()
	for i in range(10): _tick(.1)
	_check(station.status().selector_position==0.0 and _volumes()==neutral_volumes,"middle mechanical detent actually stops axis and new gravity flow")
	await _place(1,Vector3(18,2,-.6))
	var observed: Dictionary = station.observe_gauge(1,players[1],Runtime.RECEIVER_B)
	_check(observed.ok and observed.sample.complete and observed.cabinet_connected and observed.scope=="connected_low_trial_gauge_only","real outside window yields only local sample/level evidence",observed)
	if observed.ok:
		var expected_y: float = .25+float(observed.volume_ml)/1000000.0/.2+.027
		_check(absf(observed.float_world_position.y-expected_y)<.00001,"float follows true ml-to-cross-section height with authored buoyancy offset")
	var before: Dictionary = station.snapshot()
	station.observe_gauge(1,players[1],Runtime.RECEIVER_B)
	_check(station.snapshot()==before,"observation neither mutates mechanism nor invents any progress flag")
	var blocker := _prop(Vector3(19.15,.75,-2.66),Vector3(.5,1,.03))
	await _settle()
	_check(not station.observe_gauge(1,players[1],Runtime.RECEIVER_B).ok,"real opaque obstruction in front of gauge rejects first-hit reading")
	blocker.queue_free()
	await _settle()
	await _place(1,Vector3(19.15,.7,-2.95))
	_check(station.observe_gauge(1,players[1],Runtime.RECEIVER_B).code=="body_occupied","teleporting body into tank cannot produce observation")

func _pulse_and_return() -> void:
	await _fresh()
	await _place(1,Vector3(18,2.5,-.5))
	_check(_ability("charge",Station.RELAY).ok,"real production charge powers separate bench relay")
	for i in range(5): _tick(.1)
	_check(_volumes()==[200000,0,0],"power alone neither moves selector nor creates water")
	var neutral_paths: Dictionary=station.flow_paths()
	_check(neutral_paths.neutral_clear and not neutral_paths.forward_clear and neutral_paths.destinations.is_empty(),"settled neutral can advance pulse sequencing without granting an open water route",neutral_paths)
	_check(_ability("takeover",Station.CONTROLLER).ok,"real production takeover requests shared-axis pulse")
	var elapsed := 0.0
	var clear_steps := true
	while elapsed<8.0 and not (station.status().both_samples_recorded and station.status().selector_position==0.0):
		var result := _tick(.05)
		clear_steps=clear_steps and result.ok and result.code!="blocked"
		elapsed+=.05
	measurements.pulse_scripted_seconds=elapsed
	_check(clear_steps and elapsed<=8.0 and _volumes()==[160000,20000,20000] and station.status().selector_position==0.0,"authorized motor moves same real selector through both 20 L pulses and neutral",{"elapsed":elapsed,"status":station.status(),"volumes":_volumes()})
	var samples: Dictionary = station.status().samples
	await _place(1,Vector3(18,1.35,-.5))
	var returned: Dictionary = station.request_return(1,players[1])
	_check(returned.ok,"physical front return switch requires real body and LOS",returned)
	for i in range(100): _tick(.05)
	_check(_volumes()==[200000,0,0] and not station.status().return_requested,"powered return pump returns existing water instead of resetting or replenishing it",{"volumes":_volumes(),"status":station.status()})
	_check(station.status().samples==samples,"return retains first sample histories without duplicating them")
	var totals := [0,0]
	for id in [Runtime.SOURCE,Runtime.RECEIVER_A,Runtime.RECEIVER_B]:
		var node: Dictionary = station.get_water_node(id)
		totals[0]+=int(node.clean_ml)
		totals[1]+=int(node.dirty_ml)
	_check(totals==[160000,40000],"both independent components conserved after full pulse and pump return")

func _obstruction_and_pause() -> void:
	await _fresh()
	serial+=1
	var blocker := _prop(Vector3(17.8,2.2,-2.52),Vector3(.08,.2,.22))
	await _settle()
	_check(station.apply_authorized_impulse(Station.SELECTOR,Vector3.LEFT*9,1,serial).ok,"host impulse boundary fixture accepted for sweep test")
	var before: Dictionary = station.snapshot()
	var step := _tick(.25)
	_check(step.ok and step.axis_blocked and station.snapshot().axis.position_m==before.axis.position_m and _volumes()==[200000,0,0],"whole handle/shaft/spool sweep rejects intermediate obstacle before motion or water commit",step)
	_check(not station.apply_authorized_impulse(Station.SELECTOR,Vector3.LEFT*9,1,serial).ok,"same accepted action serial cannot replay")
	blocker.queue_free()
	await _settle()
	_check(_tick(.1).ok and station.snapshot().axis.position_m==before.axis.position_m,"removing obstacle releases no stored impulse")
	# A legal saved A pose is only an obstruction fixture, not the manual route.
	var a: Dictionary = station.snapshot()
	a.axis.position_m=0.0
	_check(station.apply_snapshot(a).ok,"explicit saved A position validates for float obstruction fixture")
	_reset_entities()
	station.synchronize_impulse_roster(players)
	var float_body: StaticBody3D = station.float_bodies[Runtime.RECEIVER_B]
	blocker=_prop(float_body.global_position+Vector3.UP*.035,Vector3(.2,.02,.15))
	await _settle()
	var old_runtime: Dictionary = station.snapshot().runtime
	var old_float: Transform3D = float_body.global_transform
	step=_tick(.25)
	_check(step.ok and step.float_blocked and station.snapshot().runtime==old_runtime and float_body.global_transform==old_float,"float swept obstruction rejects entire water/time/credit candidate, not only visual motion",step)
	blocker.queue_free()
	await _settle()
	station.set_simulation_paused(true)
	before=station.snapshot()
	_check(_tick(.25).ok and station.snapshot()==before,"paused physics consumes no water/time/queued motion")
	var pause_pose := before.duplicate(true)
	pause_pose.axis.position_m=.8
	_check(station.apply_snapshot(pause_pose).ok,"paused restore accepts valid actual other detent")
	var immediate: Transform3D = PhysicsServer3D.body_get_state(station.selector_bodies.SelectorGrip.get_rid(),PhysicsServer3D.BODY_STATE_TRANSFORM)
	_check(immediate.is_equal_approx(station.selector_bodies.SelectorGrip.global_transform) and is_equal_approx(immediate.origin.x,18.4),"paused restore publishes exact PhysicsServer position in the same frame")
	station.set_simulation_paused(false)
	await _fresh()
	await _place(1,Vector3(18,2.5,-.5))
	_check(_ability("charge",Station.RELAY).ok and _ability("takeover",Station.CONTROLLER).ok,"fresh actual authorized pulse starts for owner invalidation")
	for i in range(12): _tick(.05)
	var axis_before: float = station.snapshot().axis.position_m
	var water_before := _volumes()
	for i in range(5): _tick(.1,{})
	_check(station.snapshot().axis.position_m==axis_before,"offline owner cannot continue motor movement")
	# Runtime can settle pre-loss earned sub-tick credit, but never credit new
	# unauthorized time. A second full interval must keep all water unchanged.
	water_before=_volumes()
	for i in range(5): _tick(.1,{})
	_check(_volumes()==water_before,"offline owner adds no new flow after prior earned credit settles")
	await _fresh()
	await _place(1,Vector3(22,2.2,-2.52))
	_check(_ability("force_field",Station.SELECTOR,"pin").ok,"production field can pin same selector")
	var point_before: Vector3 = station.selector_bodies.SelectorGrip.global_position
	_tick(.1)
	serial+=1
	_check(not station.apply_authorized_impulse(Station.SELECTOR,Vector3.LEFT*9,1,serial).ok and station.selector_bodies.SelectorGrip.global_position==point_before,"field pin rejects new manual impulses")
	before=station.snapshot()
	_check(not station.fixed_update(NAN,entities,players).ok and station.snapshot()==before,"non-finite update cannot mutate physical or hydraulic state")

func _full_capacity_and_return() -> void:
	# Full-capacity physical regression, both directions. Selector saved-pose
	# fixture isolates the float/pipe clearances; manual input is tested above.
	for endpoint in [0.0,.8]:
		await _fresh()
		var pose: Dictionary = station.snapshot()
		pose.axis.position_m=endpoint
		_check(station.apply_snapshot(pose).ok,"full-capacity real-float fixture restores selected detent")
		_reset_entities()
		var clear_all := true
		for i in range(100):
			var advanced := _tick(.25)
			clear_all=clear_all and advanced.ok and not advanced.get("float_blocked",true) and not advanced.get("axis_blocked",true)
		var receiver: String = Runtime.RECEIVER_B if endpoint==0.0 else Runtime.RECEIVER_A
		_check(clear_all and int(station.get_water_node(receiver).volume_ml)==200000 and int(station.get_water_node(Runtime.SOURCE).volume_ml)==0,"entire 200 L real float stroke clears its own inlet/return pipes",{"endpoint":endpoint,"volumes":_volumes()})
		_check(is_equal_approx(float(station.get_water_node(receiver).level_m),1.25) and absf(station.float_bodies[receiver].global_position.y-1.277)<.00001,"full tank level and actual floating body agree at upper boundary")
		var full := _volumes()
		for i in range(4): _tick(.25)
		_check(_volumes()==full,"empty source/full receiver cannot overflow or create water")
		await _place(1,Vector3(18,2.5,-.5))
		_check(_ability("charge",Station.RELAY).ok,"full-capacity return receives real relay charge")
		await _place(1,Vector3(18,1.35,-.5))
		_check(station.request_return(1,players[1]).ok,"real return control begins full tank pump test")
		clear_all=true
		for i in range(100):
			var advanced := _tick(.25)
			clear_all=clear_all and advanced.ok and not advanced.get("float_blocked",true) and not advanced.get("axis_blocked",true)
		_check(clear_all and _volumes()==[200000,0,0],"all actual floats clear reverse full-capacity stroke and pump returns original 200 L",{"endpoint":endpoint,"volumes":_volumes()})

func _client() -> void:
	await _park()
	var saved: Dictionary = station.snapshot()
	var client := Station.new()
	var result: Dictionary = client.load_layout(saved,false)
	_check(result.ok,"guest validates exact host hydraulic and mechanical snapshot",result)
	if not result.ok:
		client.free()
		return
	# Separate World3D prevents overlapping cloned colliders from corrupting
	# either physics test. This is a snapshot fixture, not ENet evidence.
	var viewport := SubViewport.new()
	viewport.own_world_3d=true
	root.add_child(viewport)
	viewport.add_child(client)
	await _settle()
	var before: Dictionary = client.snapshot()
	_check(not client.fixed_update(.1,entities,{},false).ok and client.snapshot()==before,"guest never advances local water or selector")
	client.set_simulation_paused(true)
	_check(client.apply_snapshot(saved).ok and client.snapshot()==before,"same paused guest snapshot is idempotent")
	var aligned := true
	for body in client.selector_bodies.values()+client.float_bodies.values()+client.valve_bodies.values():
		var actual: Transform3D = PhysicsServer3D.body_get_state(body.get_rid(),PhysicsServer3D.BODY_STATE_TRANSFORM)
		aligned=aligned and actual.is_equal_approx(body.global_transform)
	_check(aligned,"all guest selector and float bodies are aligned on first applied frame")
	viewport.queue_free()
	await _settle()

func _old_routes() -> void:
	for peer in players:
		await _place(peer,Vector3(18,2.3,-7.7))
		var body: FlightBody = players[peer]
		var clear := _body_clear(body)
		var hit: KinematicCollision3D
		for i in range(35):
			hit=body.move_and_collide(Vector3(0,0,-.1),false,0.001)
			if hit!=null: break
			await physics_frame
		_check(clear and hit==null and absf(body.global_position.z+11.2)<.001 and _body_clear(body),"old fully open cabinet remains traversable by actual TR/HX movement",{"peer":peer,"end":str(body.global_position),"collider":str(hit.get_collider()) if hit else "none"})
		await _park()
	# Exact old closed poses still block their intended apertures.
	var closed: Dictionary = cabinet.snapshot()
	closed.axis.position_m=0.0
	closed.door_fraction=0.0
	closed.electric_latched=false
	cabinet.apply_snapshot(closed)
	await _settle()
	_check(_ray(Vector3(18,5.7,-11.5),Vector3(18,3.7,-11.5)).get("collider")==cabinet.cover,"new pipes preserve actual closed cover blockage")
	_check(_ray(Vector3(18,2.3,-8),Vector3(18,2.3,-10)).get("collider")==cabinet.door,"new pipes preserve actual closed door blockage")
	var old_entities: Dictionary = {}
	for item in cabinet.target_definitions(): old_entities[item.id]=item
	# Existing authorized-input boundary fixture tests full OLD movement with
	# new solids present; this is not a claim of playing either cabinet route.
	old_entities[Cabinet.RELAY_ID].powered=true
	old_entities[Cabinet.LOCK_ID].controlled=true
	old_entities[Cabinet.LOCK_ID].owner="1"
	old_entities[Cabinet.LOCK_ID].takeover_remaining=8.0
	cabinet.synchronize_impulse_roster(players)
	_check(cabinet.apply_authorized_impulse(Cabinet.COVER_ID,Vector3.RIGHT*9,1,999).ok,"old cover actual impulse accepted with new external pipe geometry")
	var clear_motion := true
	for i in range(8):
		var advanced: Dictionary = cabinet.fixed_update(.25,old_entities,players)
		clear_motion=clear_motion and advanced.ok and not advanced.get("cover_blocked",true) and not advanced.get("door_blocked",true)
	_check(clear_motion and cabinet.snapshot().axis.position_m==1.2 and cabinet.snapshot().door_fraction==1.0,"both old mechanisms complete full real swept travel with new bench present")

func _cabinet_rays() -> Array:
	var result: Array = []
	for sensor in [Vector3(18,5.75,-10.6),Vector3(18,2.7,-10.8),Vector3(17.8,2.7,-7.85)]:
		for center in [Vector3(17.8,2.85,-12.17),Vector3(18.2,3.45,-12.17)]:
			for offset in [Vector2.ZERO,Vector2(-.06,-.04),Vector2(.06,-.04),Vector2(-.06,.04),Vector2(.06,.04)]:
				var endpoint: Vector3 = center+Vector3(offset.x,offset.y,0)
				var hit := _ray(sensor,endpoint+(endpoint-sensor).normalized()*.002)
				result.append([hit.get("rid",RID()),hit.get("position",Vector3.ZERO)])
	return result

func _body_clear(body: PhysicsBody3D) -> bool:
	for owner in body.get_shape_owners():
		if body.is_shape_owner_disabled(owner): continue
		for index in range(body.shape_owner_get_shape_count(owner)):
			var query := PhysicsShapeQueryParameters3D.new()
			query.shape=body.shape_owner_get_shape(owner,index)
			query.transform=body.global_transform*body.shape_owner_get_transform(owner)
			query.exclude=[body.get_rid()]
			query.collision_mask=0xFFFFFFFF
			query.margin=0.0
			if not world.get_world_3d().direct_space_state.intersect_shape(query,1).is_empty(): return false
	return true

func _volumes() -> Array:
	var result: Array = []
	for id in [Runtime.SOURCE,Runtime.RECEIVER_A,Runtime.RECEIVER_B]: result.append(int(station.get_water_node(id).volume_ml))
	return result

func _prop(point: Vector3, size: Vector3) -> StaticBody3D:
	var body := StaticBody3D.new()
	var shape := BoxShape3D.new()
	shape.size=size
	var collider := CollisionShape3D.new()
	collider.shape=shape
	body.add_child(collider)
	body.position=point
	body.collision_layer=32
	world.add_child(body)
	return body

func _ray(start: Vector3, finish: Vector3, exclude: Array[RID] = []) -> Dictionary:
	return world.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(start,finish,0xFFFFFFFF,exclude))

func _finish() -> void:
	if finished: return
	finished=true
	_check(logger.errors.is_empty(),"no engine errors",{"engine_errors":logger.errors})
	if is_instance_valid(world): world.queue_free()
	await process_frame
	print("TRIAL_STATION_RESULT "+JSON.stringify({"checks":checks,"failures":failures,"measurements":measurements,"engine_errors":logger.errors,"scope":"actual_connected_bench_physics_and_explicit_poses_not_session_playthrough"}))
	quit(0 if failures.is_empty() else 1)
