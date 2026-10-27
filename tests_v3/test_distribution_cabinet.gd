extends SceneTree
## Independent real PhysicsServer tests. Explicit placement, impulse boundary
## and restore fixtures are not a Session playthrough or an awarded objective.
const Cabinet = preload("res://scripts/v3/world/twin_distribution_cabinet.gd")
const FlightBody = preload("res://scripts/v2/flight_body.gd")
const Catalog = preload("res://scripts/v2/catalog.gd")
const Rules = preload("res://scripts/v3/gameplay/twin_ability_rules.gd")
var world: Node3D
var cabinet: Node3D
var players: Dictionary = {}
var entities: Dictionary = {}
var rules = Rules.new()
var checks := 0
var failures: Array = []
var measurements: Dictionary = {}
var finished := false
var input_serial := 1000
class TestLogger extends Logger:
	var errors: Array = []
	func _log_error(function: String, file: String, line: int, code: String, rationale: String, _editor_notify: bool, error_type: int, _backtraces: Array[ScriptBacktrace]) -> void:
		errors.append({"function":function,"file":file,"line":line,"code":code,"rationale":rationale,"type":error_type})
var logger := TestLogger.new()

func _init() -> void:
	OS.add_logger(logger)
	_run.call_deferred()

func _run() -> void:
	create_timer(60).timeout.connect(func():
		if not finished:
			print("V3_DISTRIBUTION_TIMEOUT " + JSON.stringify({"checks":checks,"failures":failures,"engine_errors":logger.errors}))
			quit(2))
	_test_invalid_layout()
	world = Node3D.new()
	root.add_child(world)
	cabinet = Cabinet.new()
	var result: Dictionary = cabinet.load_layout()
	_check(result.ok,"real layout configures before tree",result)
	if not result.ok:
		cabinet.free()
		await _finish()
		return
	world.add_child(cabinet)
	for row in [[1,"tr01"],[2,"hx02"]]:
		var body := FlightBody.new()
		body.configure(Catalog.resolve_build(Catalog.default_build(row[1])))
		body.freeze=true
		body.position=Vector3(25,12+int(row[0])*2,20)
		world.add_child(body)
		body.set_process(false)
		body.set_physics_process(false)
		players[row[0]]=body
	entities=_entities()
	await _settle()
	_test_geometry()
	_test_snapshot_atomicity()
	await _test_manual_observation()
	await _test_electric_observation()
	await _test_swept_obstructions()
	await _test_axis_lifecycle()
	await _test_client_restore()
	await _finish()

func _check(ok: bool, label: String, details: Dictionary = {}) -> void:
	checks+=1
	if not ok:
		failures.append({"check":label,"details":details})
		print("DISTRIBUTION_FAIL " + label + " " + JSON.stringify(details))

func _settle() -> void:
	await physics_frame
	await physics_frame
	await process_frame

func _place(peer: int, point: Vector3) -> void:
	var body: FlightBody = players[peer]
	body.global_transform=Transform3D(Basis.IDENTITY,point)
	body.linear_velocity=Vector3.ZERO
	body.angular_velocity=Vector3.ZERO
	PhysicsServer3D.body_set_state(body.get_rid(),PhysicsServer3D.BODY_STATE_TRANSFORM,body.global_transform)
	await _settle()

func _park() -> void:
	for peer in players:
		players[peer].enabled=true
		players[peer].health=players[peer].maximum_health
		await _place(peer,Vector3(25,12+int(peer)*2,20))

func _entities() -> Dictionary:
	var result: Dictionary = {}
	for item in cabinet.target_definitions(): result[item.id]=item
	return result

func _fixture(distance: float = 0.0, door_fraction: float = 0.0) -> void:
	# Legal saved-pose fixture, only for boundary/restore cases. The two primary
	# observation routes below open using actual rule transactions and sweeps.
	var state: Dictionary = cabinet.snapshot()
	state.axis.position_m=distance
	state.axis.velocity_mps=0.0
	state.axis.last_serial={}
	state.door_fraction=door_fraction
	state.electric_latched=door_fraction==1.0
	state.cover_blocked=false
	state.door_blocked=false
	_check(cabinet.apply_snapshot(state).ok,"explicit saved-pose fixture validates")
	entities=_entities()
	cabinet.set_simulation_paused(false)
	_check(cabinet.synchronize_impulse_roster(players).ok,"real current two-body roster registered")

func _tick(delta: float, roster: Variant = null) -> Dictionary:
	var result: Dictionary = cabinet.fixed_update(delta,entities,players if roster==null else roster)
	if result.ok and delta>0 and result.code!="paused":
		var expiry: Dictionary = rules.advance_states(entities,delta)
		var timer_commit: Dictionary = rules.commit(expiry,entities)
		if not timer_commit.ok: _check(false,"production entity timer commit failed",timer_commit)
	return result

func _ray(start: Vector3, finish: Vector3, exclude: Array[RID] = []) -> Dictionary:
	return world.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(start,finish,0xFFFFFFFF,exclude))

func _sweep(peer: int, start: Vector3, finish: Vector3) -> Dictionary:
	var body: FlightBody = players[peer]
	for owner in body.get_shape_owners():
		if body.is_shape_owner_disabled(owner): continue
		for index in range(body.shape_owner_get_shape_count(owner)):
			var query := PhysicsShapeQueryParameters3D.new()
			query.shape=body.shape_owner_get_shape(owner,index)
			query.transform=Transform3D(Basis.IDENTITY,start)*body.shape_owner_get_transform(owner)
			query.exclude=[body.get_rid()]
			query.collision_mask=0xFFFFFFFF
			query.margin=0.0
			var overlap := world.get_world_3d().direct_space_state.intersect_shape(query,1)
			if not overlap.is_empty(): return {"ok":false,"stage":"start","collider":str(overlap[0].collider)}
			query.motion=finish-start
			var fractions := world.get_world_3d().direct_space_state.cast_motion(query)
			if fractions.size()!=2 or fractions[0]<0.99999: return {"ok":false,"stage":"sweep","fractions":str(fractions)}
			query.transform.origin=finish
			query.motion=Vector3.ZERO
			overlap=world.get_world_3d().direct_space_state.intersect_shape(query,1)
			if not overlap.is_empty(): return {"ok":false,"stage":"end","collider":str(overlap[0].collider)}
	return {"ok":true}

func _clear(peer: int) -> bool:
	return _sweep(peer,players[peer].global_position,players[peer].global_position).ok

func _impulse(value: Vector3, peer: int = 1) -> Dictionary:
	input_serial+=1
	return cabinet.apply_authorized_impulse(Cabinet.COVER_ID,value,peer,input_serial)

func _ability(ability: String, target: String, peer: int = 1, mode: String = "") -> Dictionary:
	var actor := "fixture:player:"+str(peer)
	if not entities.has(actor):
		entities[actor]={"id":actor,"owner":str(peer),"tags":["player"],"position":players[peer].global_position,"energy":100.0,"health":100.0,"revision":0}
	entities[actor].position=players[peer].global_position
	entities[target].position=cabinet.entity_position(target)
	var hit := _ray(players[peer].global_position,entities[target].position,[players[peer].get_rid()])
	var los: bool = not hit.is_empty() and hit.collider.get_meta("entity_id","")==target
	measurements["ability_"+ability+"_"+target]={"observer":str(players[peer].global_position),"target":str(entities[target].position),"distance_m":players[peer].global_position.distance_to(entities[target].position),"first_hit_target":los}
	var result: Dictionary = rules.resolve({"ability":ability,"actor_id":actor,"target_id":target,"mode":mode},entities,{"sender_id":str(peer),"line_of_sight":los})
	if not result.ok: return result
	for request in result.physics_requests:
		var check: Dictionary = cabinet.can_accept_impulse(request.entity_id,request.impulse,peer,int(entities[actor].revision)+1)
		if not check.ok: return check
	var committed: Dictionary = rules.commit(result,entities,true)
	if not committed.ok: return committed
	for request in result.physics_requests:
		var applied: Dictionary = cabinet.apply_authorized_impulse(request.entity_id,request.impulse,peer,int(entities[actor].revision))
		if not applied.ok: return applied
	return committed

func _test_invalid_layout() -> void:
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(Cabinet.PATH))
	var inputs: Array = []
	var bad := data.duplicate(true)
	bad.cover.travel_m=2.0
	inputs.append(bad)
	bad=data.duplicate(true)
	bad.fixed_solids[0].max=bad.fixed_solids[0].min.duplicate()
	inputs.append(bad)
	bad=data.duplicate(true)
	bad.panels[1].id=Cabinet.PANEL_IDS[0]
	inputs.append(bad)
	bad=data.duplicate(true)
	bad.observation.min_hits=1
	inputs.append(bad)
	for invalid in inputs:
		var candidate := Cabinet.new()
		_check(not candidate.configure(invalid).ok and candidate.get_child_count()==0 and candidate.snapshot().is_empty(),"bad layout atomically rejected before any geometry")
		candidate.free()

func _test_geometry() -> void:
	_check(cabinet.global_position==Vector3(18,0,-10),"actual world placement matches explicit root origin")
	_check(cabinet.fixed_bodies.size()==28 and cabinet.target_definitions().size()==3 and cabinet.panel_bodies.size()==2,"bounded solids including five-piece floor, exactly three ability targets and two physical plates")
	var match_all := true
	for body in cabinet.get_children():
		if not body is StaticBody3D: continue
		var visual := body.get_node("Visual") as MeshInstance3D
		var collider := body.get_child(0) as CollisionShape3D
		match_all=match_all and visual.mesh is BoxMesh and collider.shape is BoxShape3D and visual.mesh.size==collider.shape.size
	_check(match_all,"each actual rendered graybox part shares collision dimensions")
	var hit := _ray(Vector3(18,5.7,-11.5),Vector3(18,3.7,-11.5))
	_check(not hit.is_empty() and hit.collider==cabinet.cover,"closed cover actually blocks the well, no whole upper-floor hidden box")
	for peer in players:
		var swept := _sweep(peer,Vector3(18,2.3,-7.7),Vector3(18,2.3,-11.2))
		_check(not swept.ok and swept.stage=="sweep","closed real gate blocks full TR/HX travel and swept blink",{"peer":peer,"sweep":swept})
	var defs: Array = cabinet.target_definitions()
	defs[0].tags.clear()
	_check(not cabinet.target_definitions()[0].tags.is_empty() and cabinet.entity_position("unknown")==null,"target and layout accessors return independent values")

func _test_snapshot_atomicity() -> void:
	var baseline: Dictionary = cabinet.snapshot()
	var cases: Array = [null,{},[]]
	for key in baseline:
		var missing := baseline.duplicate(true)
		missing.erase(key)
		cases.append(missing)
	for pair in [["version",2],["serial",0.5],["serial",-1],["serial",9007199254740001],["door_fraction",NAN],["door_fraction",1.01],["electric_latched",1],["layout_sha256","bad"],["extra",false]]:
		var invalid := baseline.duplicate(true)
		invalid[pair[0]]=pair[1]
		cases.append(invalid)
	var invalid := baseline.duplicate(true)
	invalid.electric_latched=true
	cases.append(invalid)
	invalid=baseline.duplicate(true)
	invalid.axis.position_m=1.2001
	cases.append(invalid)
	invalid=baseline.duplicate(true)
	invalid.axis.last_serial={"01":4}
	cases.append(invalid)
	for raw in cases:
		var pose: Transform3D = cabinet.cover.transform
		_check(not cabinet.apply_snapshot(raw).ok and cabinet.snapshot()==baseline and cabinet.cover.transform==pose,"malformed snapshot rejects atomically without collision or state mutation")
	var copy: Dictionary = cabinet.snapshot()
	copy.axis.last_serial["1"]=999
	_check(cabinet.snapshot()==baseline,"nested returned snapshot is isolated")
	_check(cabinet.apply_snapshot(JSON.parse_string(JSON.stringify(baseline,"",true,true))).ok,"JSON numeric round-trip is accepted")

func _test_manual_observation() -> void:
	await _park()
	_fixture()
	for point in [Vector3(18,5.75,-10.6),Vector3(17.8,2.7,-7.85),Vector3(22,2.7,-11),Vector3(18,2.7,-14)]:
		await _place(1,point)
		var sample: Dictionary = cabinet.observe_back(1,players[1])
		_check(not sample.ok,"closed cabinet cannot award observation by proximity from top/front/side/back",{"point":str(point),"sample":sample})
	await _place(1,Vector3(17.6,5.75,-10.6))
	_check(_clear(1),"manual approach uses actual clear whole body above inspection deck")
	var legal_pushes := true
	for unused in range(4):
		if float(cabinet.snapshot().axis.position_m)>=1.2: break
		var result := _ability("push_pull",Cabinet.COVER_ID)
		legal_pushes=legal_pushes and bool(result.ok)
		for tick in range(7):
			var moved := _tick(0.05)
			legal_pushes=legal_pushes and bool(moved.ok) and not bool(moved.get("cover_blocked",false))
	_check(legal_pushes and float(cabinet.snapshot().axis.position_m)>1.0,"real LOS/Rules/impulse path physically opens the cover without direct success fixture",{"state":cabinet.snapshot()})
	for unused in range(8): _tick(0.1)
	measurements.manual_open_state=cabinet.snapshot()
	var empty_ray := _ray(Vector3(18,5.7,-11.5),Vector3(18,3.7,-11.5),[players[1].get_rid()])
	_check(empty_ray.is_empty(),"open well is truly empty through both separated ceiling layers")
	for peer in players:
		await _park()
		await _place(peer,Vector3(18,5.75,-10.6))
		var sample: Dictionary = cabinet.observe_back(peer,players[peer])
		measurements["manual_"+str(peer)]=sample
		_check(sample.ok and sample.method=="manual" and sample.panel_hits[0]>=3 and sample.panel_hits[1]>=3,"both actual plates readable through open well using real TR/HX body",sample)
		var before: Dictionary = cabinet.snapshot()
		cabinet.observe_back(peer,players[peer])
		_check(cabinet.snapshot()==before,"observation is a read-only evidence sample with no local reward/state change")
	await _park()
	await _place(1,Vector3(18,5.75,-10.6))
	var obstruction := _prop(Vector3(17.8,2.85,-12.11),Vector3(0.3,0.22,0.04))
	await _settle()
	var blocked: Dictionary = cabinet.observe_back(1,players[1])
	_check(not blocked.ok,"one physically covered plate rejects two-plate observation",blocked)
	obstruction.queue_free()
	await _settle()
	await _place(1,Vector3(18,11,-10.6))
	_check(cabinet.observe_back(1,players[1]).code=="too_far","distance uses actual three-dimensional body sensor")
	await _place(1,Vector3(18,4.9,-10))
	_check(cabinet.observe_back(1,players[1]).code=="body_occupied","body intersecting real upper deck cannot observe from an illegal pose")
	await _park()

func _test_electric_observation() -> void:
	_fixture()
	await _place(1,Vector3(17.8,2.7,-7.85))
	_check(_ability("charge",Cabinet.RELAY_ID).ok,"real reachable relay accepts production charge")
	_check(_tick(0.25).ok and cabinet.snapshot().door_fraction==0.0,"power alone cannot lift the door")
	_check(_ability("takeover",Cabinet.LOCK_ID).ok,"real reachable electrical lock accepts production takeover")
	for unused in range(4): _tick(0.25)
	_check(is_equal_approx(float(cabinet.snapshot().door_fraction),0.5),"one valid powered second gives actual half stroke")
	_check(not cabinet.observe_back(1,players[1]).ok,"half raised gate still blocks required plate centers physically")
	var position_before: Transform3D = cabinet.door.transform
	_check(_tick(0.25,{}).ok and cabinet.door.transform==position_before,"offline takeover owner cannot continue motor")
	players[1].enabled=false
	_check(_tick(0.25).ok and cabinet.door.transform==position_before,"disabled controller cannot continue motor")
	players[1].enabled=true
	entities[Cabinet.RELAY_ID].powered=false
	_check(_tick(0.25).ok and cabinet.door.transform==position_before,"power loss preserves partial physical gate position")
	entities[Cabinet.RELAY_ID].powered=true
	for unused in range(2): _tick(0.25)
	var partial: Dictionary = cabinet.observe_back(1,players[1])
	measurements.partial_gate_observation=partial
	_check(partial.ok and partial.method=="service_lock" and not cabinet.snapshot().electric_latched,"genuinely readable partial opening counts, no artificial fully-open check",partial)
	for unused in range(2): _tick(0.25)
	_check(cabinet.snapshot().electric_latched and cabinet.snapshot().door_fraction==1.0,"two seconds of valid operation reach and retain physical upper latch")
	entities[Cabinet.RELAY_ID].powered=false
	_check(_tick(0.25,{}).ok and cabinet.snapshot().door_fraction==1.0,"latched door stays open after disconnection and power loss")
	await _park()
	for peer in players:
		var swept := _sweep(peer,Vector3(18,2.3,-7.7),Vector3(18,2.3,-11.2))
		measurements["open_door_sweep_"+str(peer)]=swept
		_check(swept.ok,"whole TR/HX passes real full open doorway and room",{"peer":peer,"result":swept})
		await _place(peer,Vector3(18,2.7,-10.8))
		var sample: Dictionary = cabinet.observe_back(peer,players[peer])
		measurements["interior_observation_"+str(peer)]=sample
		_check(sample.ok and sample.method=="service_lock","real full body inside maintenance room reads rear plates",sample)
		await _park()

func _enable_motor_fixture() -> void:
	# Explicit trusted-entity boundary fixture for collision tests, not a spell.
	entities[Cabinet.RELAY_ID].powered=true
	entities[Cabinet.LOCK_ID].controlled=true
	entities[Cabinet.LOCK_ID].owner="1"
	entities[Cabinet.LOCK_ID].takeover_remaining=8.0

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

func _test_swept_obstructions() -> void:
	for peer in players:
		_fixture()
		var body: FlightBody = players[peer]
		var before: Transform3D = cabinet.cover.transform
		var result: Dictionary = {}
		if peer==1:
			await _place(peer,Vector3(18.62+float(body.stats.width_m)*0.5,4.4,-11.45))
			_check(_clear(peer),"reachable cover contact fixture begins clear of every actual solid",{"peer":peer})
			_check(_impulse(Vector3.RIGHT*9).ok,"legal full-axis impulse submitted to real cover")
			result=_tick(0.25)
			_check(result.ok and result.cover_blocked and cabinet.cover.transform==before and cabinet.snapshot().axis.velocity_mps==0.0 and _clear(peer),"entire fast cover sweep stops without penetrating actual TR body",result)
			await _park()
			_check(_tick(0.1).ok and cabinet.cover.transform==before,"clearing cover obstacle alone releases no accumulated force")
		else:
			# The 0.68 m high HX cannot occupy the 0.64 m clear band above
			# the actual end stop and below the upper deck. Do not teleport it
			# into this protected cavity and mislabel existing penetration as crush.
			var above := Vector3(19.72,5.7,-11.45)
			var cavity := Vector3(19.72,4.4,-11.45)
			var descent := _sweep(peer,above,cavity)
			_check(not descent.ok,"HX full envelope is physically excluded from protected cover side cavity",descent)
			await _place(peer,above)
			_check(_clear(peer),"HX waits above actual protective upper deck with full clearance")
			_check(_impulse(Vector3.RIGHT*9).ok,"cover receives actual impulse with HX at legal upper position")
			result=_tick(0.25)
			_check(result.ok and not result.cover_blocked and cabinet.cover.transform!=before and _clear(peer),"cover moves below protective geometry without penetrating legal HX position",result)
			await _park()
		_fixture()
		_enable_motor_fixture()
		await _place(peer,Vector3(18,4.055+float(body.stats.height_m)*0.5,-9))
		_check(_clear(peer),"lift-door obstruction starts above closed door with a real positive gap",{"peer":peer})
		before=cabinet.door.transform
		result=_tick(0.25)
		_check(result.ok and result.door_blocked and cabinet.door.transform==before and _clear(peer),"upward gate full sweep cannot crush TR/HX between door and upper structures",{"peer":peer,"result":result})
		await _park()
		_check(_tick(0.25).ok and cabinet.snapshot().door_fraction>0.0,"clearing gate obstruction permits still-valid motor input")
	for row in [["cover",Vector3(18.85,4.08,-11.45)],["door",Vector3(18,4.25,-9)]]:
		_fixture()
		var prop := _prop(row[1],Vector3(0.08,0.08,0.08))
		await _settle()
		if row[0]=="cover": _impulse(Vector3.RIGHT*9)
		else: _enable_motor_fixture()
		var before: Transform3D = cabinet.cover.transform if row[0]=="cover" else cabinet.door.transform
		var result := _tick(0.25)
		var same: bool = cabinet.cover.transform==before if row[0]=="cover" else cabinet.door.transform==before
		_check(result.ok and same and result[row[0]+"_blocked"],"layer32 solid within swept segment blocks actual actuator",{"part":row[0],"result":result})
		prop.queue_free()
		await _settle()

func _test_axis_lifecycle() -> void:
	_fixture(0.5)
	_check(_impulse(Vector3.RIGHT*9,1).ok and _impulse(Vector3.LEFT*9,2).ok,"two real registered players can supply opposed same-tick impulses")
	_check(_tick(0.1).ok and is_equal_approx(float(cabinet.snapshot().axis.position_m),0.5),"opposed full impulses cancel before limiting")
	var order_states: Array = []
	for order in [[1,2],[2,1]]:
		_fixture(0.5)
		for peer in order: _impulse(Vector3.RIGHT*9,peer)
		_tick(0.1)
		order_states.append([cabinet.snapshot().axis.position_m,cabinet.snapshot().axis.velocity_mps])
	_check(order_states[0]==order_states[1],"two +9 impulses saturate independently of caller order")
	_fixture(0.5)
	_check(not _impulse(Vector3.RIGHT*9.01).ok,"above-spec impulse still rejects")
	var before: Dictionary = cabinet.snapshot()
	_check(not cabinet.fixed_update(NAN,entities,players).ok and cabinet.snapshot()==before,"non-finite delta atomically rejects")
	var invalid := entities.duplicate(true)
	invalid[Cabinet.LOCK_ID].takeover_remaining=-1.0
	_check(not cabinet.fixed_update(0.1,invalid,players).ok and cabinet.snapshot()==before,"invalid trusted input schema does not mutate state")
	_check(_impulse(Vector3.RIGHT*9,2).ok,"accepted input is present before pause fixture")
	before=cabinet.snapshot()
	_check(_tick(0.0).ok and cabinet.snapshot()==before,"zero delta preserves position, velocity, serial and accepted impulse exactly")
	var stopped: Dictionary = cabinet.set_simulation_paused(true)
	_check(stopped.ok and stopped.cancelled.size()==1 and cabinet.snapshot().axis.velocity_mps==0.0,"explicit pause reports and clears accepted motion")
	before=cabinet.snapshot()
	_check(not _impulse(Vector3.RIGHT).ok and _tick(0.1).ok and cabinet.snapshot()==before,"pause cannot accumulate new or delayed input")
	cabinet.set_simulation_paused(false)
	_check(_tick(0.1).ok and cabinet.snapshot().axis.position_m==before.axis.position_m,"unpause produces no stored kick")
	_check(_impulse(Vector3.RIGHT*9).ok,"pin fixture begins with actual accepted impulse")
	entities[Cabinet.COVER_ID].pinned=true
	entities[Cabinet.COVER_ID].field_remaining=4.0
	before=cabinet.snapshot()
	var pinned := _tick(0.1)
	_check(pinned.ok and cabinet.snapshot().axis.position_m==before.axis.position_m and cabinet.snapshot().axis.velocity_mps==0.0 and not _impulse(Vector3.RIGHT).ok,"real pin state stops cover and new impulses")
	_fixture(0.5)
	_impulse(Vector3.LEFT*9,1)
	_impulse(Vector3.RIGHT*9,2)
	var pose: Transform3D = cabinet.cover.transform
	_check(cabinet.reset_impulse_peer(1).ok and cabinet.cover.transform==pose and cabinet.snapshot().axis.velocity_mps==2.0,"one peer recreation preserves teammate input and actual position")
	_check(_tick(0.1).ok and cabinet.snapshot().axis.position_m>0.5,"teammate input still physically moves the cover")
	for direction in [1.0,-1.0]:
		_fixture(1.19 if direction>0 else 0.01)
		for unused in range(5):
			_check(_impulse(Vector3.RIGHT*9.0*direction).ok,"continuous full-axis endpoint input remains valid")
			for tick in range(7): _tick(0.05)
		_check(cabinet.snapshot().axis.position_m==(1.2 if direction>0 else 0.0) and cabinet.snapshot().axis.velocity_mps==0.0,"swept axis settles at exact real endpoint without solver overshoot")
	_fixture()
	pose=cabinet.cover.transform
	cabinet.cover.position.y+=0.02
	before=cabinet.snapshot()
	_check(not _tick(0.1).ok and cabinet.snapshot()==before,"unauthorized pose edit cannot be silently adopted")
	cabinet.cover.transform=pose
	PhysicsServer3D.body_set_state(cabinet.cover.get_rid(),PhysicsServer3D.BODY_STATE_TRANSFORM,cabinet.cover.global_transform)

func _test_client_restore() -> void:
	_fixture(1.2,1.0)
	var saved: Dictionary = cabinet.snapshot()
	saved.axis.velocity_mps=-1.0 # Explicit in-motion server snapshot display fixture.
	var data: Dictionary = cabinet.layout()
	cabinet.queue_free()
	await _settle()
	var guest := Cabinet.new()
	_check(guest.configure(data,JSON.parse_string(JSON.stringify(saved,"",true,true)),false).ok,"client restores entire valid state before entering the tree")
	_check(is_equal_approx(guest.door.position.y,5.605) and is_equal_approx(guest.cover.position.x,1.2),"pre-tree geometry already matches remote gate and cover")
	world.add_child(guest)
	cabinet=guest
	await _settle()
	var before: Dictionary = guest.snapshot()
	_check(_sweep(1,Vector3(18,2.3,-7.7),Vector3(18,2.3,-11.2)).ok,"first client physics state contains full real open doorway")
	_check(_ray(Vector3(18,5.7,-11.5),Vector3(18,3.7,-11.5)).is_empty(),"first client physics state contains actual open well")
	_check(not guest.fixed_update(0.1,entities,players,true).ok and not guest.apply_authorized_impulse(Cabinet.COVER_ID,Vector3.RIGHT,1,99999).ok and guest.snapshot()==before,"client cannot advance or submit impulses even when caller claims authority")
	guest.set_simulation_paused(true)
	_check(guest.snapshot()==before,"client local pause does not rewrite received velocity")
	_check(not guest.observe_back(1,players[1]).ok and not guest.reset_impulse_peer(1).ok,"client cannot manufacture observation or mutate lifecycle")
	_check(guest.apply_snapshot(before).ok and not guest.apply_snapshot(before).changed,"duplicate received state is idempotent")
	saved.axis.last_serial.clear()
	data.cover.center[0]=99
	_check(guest.snapshot()==before and guest.layout().cover.center[0]==0,"received nested state/layout is not aliased to caller")
	var host := Cabinet.new()
	_check(host.configure(guest.layout(),before,true).ok and host.snapshot().axis.velocity_mps==0.0 and host.snapshot().axis.position_m==before.axis.position_m,"disk host restore explicitly stops motion while keeping observed geometry")
	host.free()

func _finish() -> void:
	finished=true
	if is_instance_valid(world): world.queue_free()
	await process_frame
	await process_frame
	print("V3_DISTRIBUTION_CABINET_TESTS " + JSON.stringify({"checks":checks,"failures":failures,"engine_errors":logger.errors,"measurements":measurements,"scope":"independent real PhysicsServer and production body/rule fixtures; no world registration, Story, save, LAN, graphics, performance or human-play result"}))
	var failed: bool = not failures.is_empty() or not logger.errors.is_empty()
	OS.remove_logger(logger)
	quit(1 if failed else 0)
