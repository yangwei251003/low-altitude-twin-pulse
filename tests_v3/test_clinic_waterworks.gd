extends SceneTree
## Independent real-PhysicsServer test. Authored starting poses, restored water
## levels and controller registries below are explicit fixtures, not a Session
## playthrough, a completed action, GPU evidence or a human timing result.
const Works = preload("res://scripts/v3/world/twin_clinic_waterworks.gd")
const Runtime = preload("res://scripts/v3/environment/twin_clinic_water_runtime.gd")
const FlightBody = preload("res://scripts/v2/flight_body.gd")
const Catalog = preload("res://scripts/v2/catalog.gd")
const Rules = preload("res://scripts/v3/gameplay/twin_ability_rules.gd")
var world: Node3D
var works: Node3D
var players: Dictionary = {}
var entities: Dictionary = {}
var checks := 0
var failures: Array = []
var finished := false
var rules = Rules.new()
var measurements: Dictionary = {}
var action_serial := 100
class TestLogger extends Logger:
	var errors: Array = []
	func _log_error(function: String, file: String, line: int, code: String, rationale: String, _editor_notify: bool, error_type: int, _script_backtraces: Array[ScriptBacktrace]) -> void:
		errors.append({"function":function,"file":file,"line":line,"code":code,"rationale":rationale,"type":error_type})
var error_logger := TestLogger.new()

func _init() -> void:
	OS.add_logger(error_logger)
	_run.call_deferred()

func _check(ok: bool, label: String, details: Dictionary = {}) -> void:
	checks += 1
	if not ok:
		failures.append({"check":label,"details":details})
		push_error("CLINIC_WATERWORKS " + label + " " + JSON.stringify(details))

func _run() -> void:
	create_timer(60).timeout.connect(func():
		if not finished:
			push_error("CLINIC_WATERWORKS timeout; no pass implied")
			quit(2))
	_test_configure_rejection()
	world = Node3D.new()
	root.add_child(world)
	works = Works.new()
	var loaded: Dictionary = works.load_layout()
	_check(loaded.ok,"actual independent layout configures",loaded)
	if not loaded.ok:
		works.free()
		await _finish()
		return
	world.add_child(works)
	for row in [[1,"tr01"],[2,"hx02"]]:
		var body := FlightBody.new()
		body.configure(Catalog.resolve_build(Catalog.default_build(row[1])))
		body.freeze = true
		body.position = Vector3(23,10+int(row[0])*3,23)
		world.add_child(body)
		body.set_process(false)
		body.set_physics_process(false)
		players[row[0]] = body
	entities = _default_entities()
	await _settle()
	_test_geometry_and_water()
	await _test_flight_clearance()
	await _test_cistern_structure_clearance()
	_test_snapshot_guards()
	await _test_real_gravity_impulse()
	await _test_axis_input_matrix()
	await _test_power_selector_and_interlock()
	await _test_crossbolt_sweep()
	await _test_locked_valve_impulse()
	await _test_lift_sweep_and_volume()
	await _test_client_first_frame()
	await _finish()

func _settle() -> void:
	await physics_frame
	await physics_frame
	await process_frame

func _default_entities() -> Dictionary:
	var result: Dictionary = {}
	for target in works.target_definitions(): result[target.id] = target
	return result

func _place(peer: int, at: Vector3) -> void:
	var body: RigidBody3D = players[peer]
	body.global_transform = Transform3D(Basis.IDENTITY,at)
	body.linear_velocity = Vector3.ZERO
	body.angular_velocity = Vector3.ZERO
	PhysicsServer3D.body_set_state(body.get_rid(),PhysicsServer3D.BODY_STATE_TRANSFORM,body.global_transform)
	await _settle()

func _park() -> void:
	for peer in players: await _place(peer,Vector3(23,10+int(peer)*3,23))

func _placed_body_clear(peer: int) -> bool:
	var body: PhysicsBody3D = players[peer]
	for owner in body.get_shape_owners():
		if body.is_shape_owner_disabled(owner): continue
		for index in range(body.shape_owner_get_shape_count(owner)):
			var query := PhysicsShapeQueryParameters3D.new()
			query.shape = body.shape_owner_get_shape(owner,index)
			query.transform = body.global_transform * body.shape_owner_get_transform(owner)
			query.collision_mask = 1|8|32
			query.exclude = [body.get_rid()]
			query.margin = 0.0
			if not world.get_world_3d().direct_space_state.intersect_shape(query,1).is_empty(): return false
	return true

func _enable_selector_fixture() -> void:
	entities[Works.RELAY_ID].powered=true
	entities[Works.PUMP_ID].controlled=true
	entities[Works.PUMP_ID].owner="1"
	entities[Works.PUMP_ID].takeover_remaining=8.0

func _ray(from: Vector3, to: Vector3) -> Dictionary:
	return world.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(from,to,1|8))

func _body_sweep(peer: int, from: Vector3, to: Vector3) -> Dictionary:
	var body: PhysicsBody3D = players[peer]
	for owner in body.get_shape_owners():
		if body.is_shape_owner_disabled(owner): continue
		for index in range(body.shape_owner_get_shape_count(owner)):
			var query := PhysicsShapeQueryParameters3D.new()
			query.shape = body.shape_owner_get_shape(owner,index)
			query.transform = Transform3D(Basis.IDENTITY,from)*body.shape_owner_get_transform(owner)
			query.collision_mask = 1|8|32
			query.exclude = [body.get_rid()]
			query.margin = 0.0
			var overlaps := world.get_world_3d().direct_space_state.intersect_shape(query,1)
			if not overlaps.is_empty(): return {"ok":false,"stage":"start","collider":str(overlaps[0].collider)}
			query.motion = to-from
			var fractions := world.get_world_3d().direct_space_state.cast_motion(query)
			if fractions.size()!=2 or fractions[0]<0.999: return {"ok":false,"stage":"sweep","fractions":str(fractions)}
			query.transform.origin += to-from
			query.motion = Vector3.ZERO
			overlaps = world.get_world_3d().direct_space_state.intersect_shape(query,1)
			if not overlaps.is_empty(): return {"ok":false,"stage":"end","collider":str(overlaps[0].collider)}
	return {"ok":true}

# Conservation-preserving saved-state boundary fixture. It does not claim that
# the player has travelled here, moved the valve or delivered this much water.
func _fixture(gravity: float = 0.0, pump: float = 0.0, powered: bool = false, volume_ml: int = 0) -> void:
	var state: Dictionary = works.snapshot()
	var water = Runtime.new()
	_check(water.load_definition().ok,"independent fixture uses real production water definition")
	var saved: Dictionary = water.snapshot()
	saved.simulation.nodes[Runtime.SOURCE].clean_ml -= volume_ml
	saved.simulation.nodes[Runtime.CLINIC].clean_ml += volume_ml
	if volume_ml>0: saved.simulation.tick = 1
	saved.facts = {"gravity_open_permille":1000 if gravity>=0.995 else 0,
		"pump_open_permille":1000 if pump==1.0 else 0,"pump_powered":powered,"platform_blocked":false}
	saved.simulation.edges[Runtime.GRAVITY].open_permille = 0 if volume_ml==Runtime.TARGET_ML else saved.facts.gravity_open_permille
	saved.simulation.edges[Runtime.PUMP].open_permille = 0 if volume_ml==Runtime.TARGET_ML else saved.facts.pump_open_permille
	saved.simulation.edges[Runtime.PUMP].powered = powered
	_check(water.restore(saved).ok,"explicit conserved water-level fixture validates")
	state.runtime = water.snapshot()
	state.gravity_fraction = gravity
	state.gravity_speed = 0.0
	state.axis.position_m = gravity*1.2
	state.axis.velocity_mps = 0.0
	state.axis.last_serial = {}
	state.gravity_blocked = false
	state.pump_fraction = pump
	state.pump_latched = pump==1.0
	state.powered = powered
	state.platform_blocked = false
	state.selector_blocked = false
	state.interlock_waiting = false
	state.gravity_pinned = false
	_check(works.apply_snapshot(state).ok,"explicit actuator / water fixture restores atomically")
	works.set_simulation_paused(false)
	entities = _default_entities()
	entities[Works.RELAY_ID].powered = powered
	entities[Works.RELAY_ID].charge = 35.0 if powered else 0.0
	works.synchronize_impulse_roster(players)

func _step(delta: float, roster: Variant = null) -> Dictionary:
	return works.fixed_update(delta,entities,players if roster==null else roster)

func _test_configure_rejection() -> void:
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(Works.PATH))
	for representation in ["json_floats","integer_centers","mixed_centers"]:
		var equivalent: Dictionary = data.duplicate(true)
		if representation=="integer_centers":
			equivalent.tanks[Runtime.SOURCE].center_xz=[-9,-7]
			equivalent.tanks[Runtime.CLINIC].center_xz=[0,-8]
		elif representation=="mixed_centers":
			equivalent.tanks[Runtime.SOURCE].center_xz=[-9.0,-7]
			equivalent.tanks[Runtime.CLINIC].center_xz=[0,-8.0]
		var normalized_candidate := Works.new()
		var normalized_result: Dictionary = normalized_candidate.configure(equivalent)
		_check(normalized_result.ok,"identical numeric tank centers accept JSON/int/mixed representation: "+representation,normalized_result)
		normalized_candidate.free()
	for kind in ["deck_width","tank_area","tank_center_shift","tank_center_type","tank_base_type","bearing","stroke","nan"]:
		var bad: Dictionary = data.duplicate(true)
		match kind:
			"deck_width": bad.moving_parts[0].size[0]=3.9
			"tank_area": bad.tanks[Runtime.CLINIC].inner_size[0]=4
			"tank_center_shift": bad.tanks[Runtime.SOURCE].center_xz[0]=-9.0+0.000001
			"tank_center_type": bad.tanks[Runtime.CLINIC].center_xz[0]="0"
			"tank_base_type": bad.tanks[Runtime.SOURCE].base_y="6"
			"bearing": bad.fixed_solids[8].max[0]=-1.9
			"stroke": bad.pump_selector.stroke_seconds=0.1
			"nan": bad.anchors.entry[0]=NAN
		var candidate := Works.new()
		var result: Dictionary = candidate.configure(bad)
		_check(not result.ok and not candidate.configured and candidate.get_child_count()==0,"malformed layout leaves no half-built scene: "+kind,result)
		_check(candidate.configure(data).ok,"valid configure can retry after atomic rejection")
		candidate.free()

func _test_geometry_and_water() -> void:
	var exact := true
	var physical_count := 0
	for node in works.find_children("*","PhysicsBody3D",true,false):
		if not node.has_node("Visual") or not node.has_node("ExactBoxCollision"): continue
		var mesh: BoxMesh = node.get_node("Visual").mesh
		var shape: BoxShape3D = node.get_node("ExactBoxCollision").shape
		exact = exact and mesh.size.is_equal_approx(shape.size)
		physical_count += 1
	_check(exact and physical_count>35,"every solid graybox component shares its actual mesh/collider dimensions",{"count":physical_count})
	_check(works.moving_bodies.size()==9 and works.deck.get_node("ExactBoxCollision").shape.size==Vector3(4,0.35,4),"full 4x4 deck plus eight real northern linkage components")
	_check(works.gravity_valve is StaticBody3D and works.gravity_valve.collision_layer==8,"mechanical valve is a real collision body driven only by the host guided axis")
	_check(works.layout().gravity_valve.max_speed_mps==6.0 and works.layout().gravity_valve.damping_per_second==0.8,"mechanical speed and damping are explicit fingerprinted parameters")
	_check(not works.layout().gravity_valve.has("joint_end_reserve_m"),"no solver reserve or Jolt joint is used as a rail constraint")
	for row in [[Vector3(0,4.2,-4),Vector3(0,3.5,-4),4.0,"deck"],[Vector3(0,2,-4),Vector3(0,0,-4),1.0,"underpass floor"],[Vector3(-7,1,10),Vector3(-7,0,10),0.4,"pump floor"],[Vector3(-7,3,10),Vector3(-7,3.7,10),3.2,"pump ceiling"]]:
		var hit := _ray(row[0],row[1])
		_check(not hit.is_empty() and absf(float(hit.position.y)-float(row[2]))<0.002,"actual PhysicsServer ray finds "+row[3],{"position":str(hit.get("position"))})
	_check(works.get_node("GrayboxNavigation").get_child_count()>=12,"navigation strips, waterline marks and state lamps are explicit graybox surfaces")
	_check(works.entity_position("missing")==null and works.anchor_position("missing")==null and works.water_level("missing")==null,"unknown spatial IDs never invent an origin")
	_check(works.water_surfaces[Runtime.CLINIC].visible==false and not works.contains_water(Vector3(0,3.55,-8)),"empty clinic tank has no false water surface or fluid volume")
	var source_hit := _ray(Vector3(-9.5,8.2,-7),Vector3(-9.5,7.8,-7))
	_check(source_hit.is_empty() and works.contains_water(Vector3(-9.5,7.9,-7)),"real source water classifies fluid without an invisible collision plate")
	var copy: Dictionary = works.layout()
	copy.moving_parts.clear()
	_check(works.layout().moving_parts.size()==9,"layout accessor isolates nested geometry data")

func _test_flight_clearance() -> void:
	await _park()
	for peer in players:
		var pump_route := _body_sweep(peer,Vector3(-7,1.8,15),Vector3(-7,1.8,9.4))
		_check(pump_route.ok,"TR/HX full actual shape fits low pump doorway "+str(peer),pump_route)
		var under_route := _body_sweep(peer,Vector3(0,2.3,0),Vector3(0,2.3,-7))
		_check(under_route.ok,"TR/HX full actual shape fits 2.65m under-deck path "+str(peer),under_route)
		var high_route := _body_sweep(peer,Vector3(0,3,10),Vector3(0,10,10))
		_check(high_route.ok,"TR/HX actual shape keeps the authored central ascent slot "+str(peer),high_route)
		var blocked := _body_sweep(peer,Vector3(0,3.9,-4),Vector3(0,4.5,-4))
		_check(not blocked.ok,"solid deck cannot be crossed by a full drone envelope "+str(peer))

func _test_cistern_structure_clearance() -> void:
	await _park()
	_check(not works.fixed_bodies.has("UpperDeckLeg"),"old eccentric single post is replaced, not doubled")
	for suffix in ["NW","NE","SW","SE"]:
		var name: String = "GravitySupportLeg_" + suffix
		_check(works.fixed_bodies.has(name),"four-post source has actual terrain collider: "+name)
		var column: StaticBody3D = works.fixed_bodies[name]
		var hit := _ray(column.position+Vector3(1,0,0),column.position-Vector3(1,0,0))
		_check(not hit.is_empty() and hit.collider==column,"new support is physical from side, not scenery: "+name)
	var cover := _ray(Vector3(-9,10,-7),Vector3(-9,8.8,-7))
	_check(not cover.is_empty() and cover.collider==works.fixed_bodies.CisternLid,"clean-water cover is a real solid separate from noncolliding water")
	for peer in players:
		for row in [["between four posts",Vector3(-8.5,2,-11),Vector3(-8.5,2,-6.2)],
			["upper valve approach",Vector3(-10,7,0),Vector3(-10,7,-3)],
			["north-to-east elevated approach",Vector3(-4,7,-11),Vector3(-4,7,-4)]]:
			var route := _body_sweep(peer,row[1],row[2])
			_check(route.ok,str(row[0])+" remains open for real hull "+str(peer),route)
	# New static bodies must not occupy ANY position along the complete mechanism
	# sweep. Query the swept box envelope, excluding only its own body.
	var new_rids: Array = []
	for id in works.fixed_bodies:
		if str(id).begins_with("GravitySupport") or str(id).begins_with("GravityFoot") or str(id).begins_with("GravityBearing") or str(id).begins_with("GravityLongitudinal") or str(id).begins_with("Cistern"):
			new_rids.append(works.fixed_bodies[id].get_rid())
	var layout: Dictionary = works.layout()
	for body in works.gravity_art.get("detail_bodies", {}).values():
		new_rids.append(body.get_rid())
	for id in works.fixed_bodies:
		if str(id).begins_with("Clinic"):
			new_rids.append(works.fixed_bodies[id].get_rid())
	for body in works.reception_art.get("detail_bodies", {}).values():
		new_rids.append(body.get_rid())
	var rows: Array = []
	for part in layout.moving_parts:
		rows.append([part.id,Works._v(part.offset)+Vector3.UP*4,Works._v(part.offset)+Vector3.UP*5,Works._v(part.size)])
	rows.append(["gravity full stroke",Works._v(layout.gravity_valve.center),Works._v(layout.gravity_valve.center)+Works._v(layout.gravity_valve.travel),Works._v(layout.gravity_valve.size)])
	rows.append(["selector full stroke",Works._v(layout.pump_selector.center),Works._v(layout.pump_selector.center)+Works._v(layout.pump_selector.travel),Works._v(layout.pump_selector.size)])
	rows.append(["interlock full stroke",Works._v(layout.interlock_bolt.center),Works._v(layout.interlock_bolt.center)+Works._v(layout.interlock_bolt.park_offset),Works._v(layout.interlock_bolt.size)])
	for row in rows:
		var first: Vector3 = row[1]
		var last: Vector3 = row[2]
		var shape := BoxShape3D.new()
		shape.size = row[3] + (last-first).abs()
		var query := PhysicsShapeQueryParameters3D.new()
		query.shape = shape
		query.transform.origin = (first+last)*0.5
		query.collision_mask = 1|8
		query.margin = 0.001
		var intrusions: Array = []
		for hit in world.get_world_3d().direct_space_state.intersect_shape(query,128):
			if hit.rid in new_rids: intrusions.append(str(hit.collider.name))
		_check(intrusions.is_empty(),str(row[0])+" entire swept envelope avoids new static structure",{"intrusions":intrusions})

func _test_snapshot_guards() -> void:
	var before: Dictionary = works.snapshot()
	var pose: Transform3D = works.deck.transform
	var invalid: Array = [null,[],{}]
	for pair in [["schema_version",1],["layout_sha256","wrong"],["gravity_fraction",1.01],["pump_fraction",NAN],["pump_latched",true],["powered",1],["runtime",false],["serial",-1],["extra",0]]:
		var bad: Dictionary = before.duplicate(true)
		bad[pair[0]]=pair[1]
		invalid.append(bad)
	var bad: Dictionary = before.duplicate(true)
	bad.runtime.simulation.nodes[Runtime.SOURCE].clean_ml-=1
	invalid.append(bad)
	for saved in invalid:
		_check(not works.apply_snapshot(saved).ok and works.snapshot()==before and works.deck.transform==pose,"bad snapshot atomically preserves water and physical pose")
	_check(works.apply_snapshot(before).ok and not works.apply_snapshot(before).changed,"duplicate snapshot is a no-op")
	for delta in [-0.1,0.251,INF,NAN]:
		_check(not _step(delta).ok and works.snapshot()==before,"bad physical step leaves all state unchanged")
	_check(not works.fixed_update(0.1,entities,{1:Vector3.ZERO}).ok and works.snapshot()==before,"player points cannot replace actual flight bodies")
	_check(not works.fixed_update(0.1,entities,players,false).ok and works.snapshot()==before,"client flag cannot advance host mechanisms")
	_check(not works.fixed_update(0.1,{},players).ok and works.snapshot()==before,"missing authoritative mechanism entities do not imply power/control")
	_check(_step(0.0).ok and works.snapshot()==before and works._paused,"zero delta pauses explicit authority integration")
	works.set_simulation_paused(false)

func _resolve(ability: String, target: String, peer: int = 1, mode: String = "") -> Dictionary:
	var actor := "fixture:player:"+str(peer)
	entities[actor]={"id":actor,"owner":str(peer),"tags":["player"],"position":players[peer].global_position,"energy":100.0,"health":100.0,"revision":0}
	entities[target].position=works.entity_position(target)
	var query := PhysicsRayQueryParameters3D.create(players[peer].global_position,entities[target].position,1|8)
	query.exclude=[players[peer].get_rid()]
	var hit := world.get_world_3d().direct_space_state.intersect_ray(query)
	var los: bool = hit.is_empty() or hit.collider.get_meta("entity_id","")==target
	var result: Dictionary = rules.resolve({"actor_id":actor,"ability":ability,"target_id":target,"mode":mode},entities,{"sender_id":str(peer),"line_of_sight":los})
	if not result.ok: return result
	return rules.commit(result,entities,true)

func _impulse(value: Vector3, peer: int = 1) -> Dictionary:
	action_serial += 1
	return works.apply_authorized_impulse(Works.GRAVITY_ID,value,peer,action_serial)

func _test_real_gravity_impulse() -> void:
	_fixture()
	await _place(1,Vector3(-10,7,-2.5))
	var result := _resolve("push_pull",Works.GRAVITY_ID)
	_check(result.ok,"production push rule accepts real valve LOS from the upper approach",result)
	if not result.ok: return
	for request in result.physics_requests:
		_check(_impulse(request.impulse).ok,"authorized production impulse enters guided axis")
	var opened := false
	var accepted := true
	var first_failure: Dictionary = {}
	var max_x := -8.0
	for unused in range(150):
		await physics_frame
		var moved: Dictionary = _step(1.0/60.0)
		accepted = accepted and bool(moved.ok)
		max_x=maxf(max_x,float(works.gravity_valve.position.x))
		if not moved.ok and first_failure.is_empty(): first_failure=moved
		if works.status().gravity_fraction>=0.995:
			opened=true
			break
	_check(accepted and opened,"real rule impulse and swept axis travel reach mechanical open detent",{"fraction":works.status().gravity_fraction,"position":str(works.gravity_valve.position),"max_x":max_x,"first_failure":first_failure})
	_check(absf(works.gravity_valve.position.y-7)<0.005 and absf(works.gravity_valve.position.z+5)<0.005 and works.gravity_valve.position.x<=-6.795,"real valve remains on rail within contact tolerance")
	_check(_step(0.1).ok and int(works.status().clinic_volume_ml)>0,"actual detent position supplies gravity water without a fact shortcut")
	var stable_end := true
	for unused in range(30):
		await physics_frame
		var held_step: Dictionary = _step(1.0/60.0)
		stable_end=stable_end and bool(held_step.ok) and works.gravity_valve.position.x<=-6.795 and float(works.status().gravity_fraction)>=0.995
	_check(stable_end,"real open detent remains valid for thirty additional physics frames with no residual velocity or delayed input",{"position":str(works.gravity_valve.position),"fraction":works.status().gravity_fraction})
	measurements["gravity_end"]={"first_failure":first_failure,"max_first_contact_x":max_x,"settled_x":float(works.gravity_valve.position.x),"settled_fraction":float(works.status().gravity_fraction),"flow_threshold":0.995,"guided_travel_m":works.layout().gravity_valve.travel[0]}
	var before: Dictionary = works.snapshot()
	_check(_step(0.0).ok,"pause entry accepted")
	var held: Transform3D = works.gravity_valve.global_transform
	await _settle()
	_check(works.snapshot()==before and works.gravity_valve.global_transform.is_equal_approx(held),"paused guided valve and water remain frozen across actual physics frames")
	works.set_simulation_paused(false)
	await _park()

func _test_axis_input_matrix() -> void:
	await _park()
	for start_fraction in [0.0,0.01,0.5,0.99,1.0]:
		for direction in [-1.0,1.0]:
			_fixture(float(start_fraction))
			var valid := true
			var inside := true
			for tick in range(64):
				# Explicit authorized full-axis fixture at the real 0.35 s cadence.
				# Production LOS / actor commit are covered by the earlier rule test.
				if tick%21==0: valid = bool(_impulse(Vector3.RIGHT*9.0*direction).ok) and valid
				var result := _step(1.0/60.0)
				valid = bool(result.ok) and valid
				var x: float = works.gravity_valve.position.x
				inside = inside and x>=-8.000001 and x<=-6.799999 and works.gravity_valve.position.y==7.0 and works.gravity_valve.position.z==-5.0
			_check(valid and inside,"full +/-9Ns repeated every 0.35s remains exactly on rail at near/end/mid starts",{"start":start_fraction,"direction":direction,"position":str(works.gravity_valve.position)})
			_check(float(works.status().gravity_fraction)==(0.0 if direction<0 else 1.0) and float(works.status().gravity_speed)==0.0,"continuous outward force ends at real limit with no stored velocity")
	for pair in [[9.0,9.0],[-9.0,-9.0],[9.0,-9.0]]:
		var first: Dictionary = {}
		for order in [[1,2],[2,1]]:
			_fixture(0.5)
			var initial: Dictionary = works.snapshot()
			for peer in order:
				var check_only: Dictionary = works.can_accept_impulse(Works.GRAVITY_ID,Vector3.RIGHT*float(pair[peer-1]),peer,action_serial+1)
				_check(check_only.ok,"both currently registered peers are synchronously approvable")
				_check(_impulse(Vector3.RIGHT*float(pair[peer-1]),peer).ok,"both same-tick authorized inputs are accepted")
			_check(works.snapshot().runtime==initial.runtime and absf(works.gravity_valve.position.x+7.4)<0.000001,"accepted momentum does not move collider or supply water before physics commit")
			var result := _step(0.1)
			_check(result.ok,"combined axis and water candidate commits",result)
			var measured := {"fraction":works.status().gravity_fraction,"speed":works.status().gravity_speed,"position":works.gravity_valve.position,"nodes":works.snapshot().runtime.simulation.nodes}
			if first.is_empty(): first=measured
			else: _check(measured==first,"two-player +/-18Ns and cancellation do not depend on arrival order")
	_fixture(0.5)
	var before: Dictionary = works.snapshot()
	_check(not works.can_accept_impulse("unknown",Vector3.RIGHT,1,9000).ok and not works.can_accept_impulse(Works.GRAVITY_ID,Vector3.RIGHT,3,9000).ok and works.snapshot()==before,"unknown target/peer cannot mutate or allocate unbounded state")
	_check(_impulse(Vector3.RIGHT*9.0).ok,"pause fixture accepts momentum")
	var accepted: Dictionary = works.snapshot()
	var stopped: Dictionary = works.set_simulation_paused(true)
	_check(stopped.cancelled.size()==1 and works.status().gravity_speed==0.0 and not _impulse(Vector3.RIGHT).ok,"pause stops accepted velocity and rejects new impulse")
	var frozen: Dictionary = works.snapshot()
	_check(_step(0.0).ok and works.snapshot()==frozen,"repeated zero-delta pause is exactly unchanged")
	works.set_simulation_paused(false)
	_check(_step(0.1).ok and works.status().gravity_fraction==0.5,"resume releases no queued impulse")
	_check(works.apply_snapshot(accepted).ok and works.status().gravity_speed==0.0,"host saved momentum restores safely stopped")
	_check(not works.apply_authorized_impulse(Works.GRAVITY_ID,Vector3.RIGHT,1,action_serial-1).ok,"restored acted serial is not replayable")
	_check(_step(0.1).ok and works.status().gravity_fraction==0.5,"restored host cannot burst from pre-save queued force")
	_check(_impulse(Vector3.RIGHT*9.0).ok,"pin fixture accepts prior momentum")
	entities[Works.GRAVITY_ID].pinned=true
	entities[Works.GRAVITY_ID].field_remaining=4.0
	_check(_step(0.1).ok and works.status().gravity_speed==0.0 and works.status().gravity_fraction==0.5 and not _impulse(Vector3.RIGHT).ok,"pin cancels current momentum, holds position and rejects further impulses")
	entities[Works.GRAVITY_ID].pinned=false
	entities[Works.GRAVITY_ID].field_remaining=0.0
	_check(_step(0.1).ok and works.status().gravity_fraction==0.5,"release does not replay pinned force")
	_check(_impulse(Vector3.RIGHT*9.0,2).ok,"leaving player has accepted momentum this tick")
	var left: Dictionary = works.synchronize_impulse_roster({1:players[1]})
	_check(left.ok and left.cancelled.size()==1 and works.snapshot().axis.last_serial.size()==1,"explicit roster removal cancels pending input and frees one bounded serial slot")
	_check(_step(0.1,{1:players[1]}).ok and works.status().gravity_fraction==0.5,"offline queued input cannot move valve")
	works.synchronize_impulse_roster(players)
	players[2].enabled=false
	_check(_step(0.1).ok and not _impulse(Vector3.RIGHT,2).ok,"disabled roster member cannot submit input")
	players[2].enabled=true
	works.synchronize_impulse_roster(players)
	_check(_impulse(Vector3.RIGHT*9.0,2).ok,"recreation fixture contains accepted old-actor momentum")
	_check(works.reset_impulse_peer(2).ok and works.snapshot().axis.last_serial["2"]==-1 and works.status().gravity_speed==0.0,"new actor lifecycle clears its pending force and stale revision without moving mechanism")
	_check(works.can_accept_impulse(Works.GRAVITY_ID,Vector3.RIGHT,2,1).ok,"new actor revision one is valid after explicit reset")
	_fixture(0.5)
	_check(_impulse(Vector3.LEFT*9.0,1).ok and _impulse(Vector3.RIGHT*9.0,2).ok,"two real registered peers have opposite accepted inputs before one recreates")
	var held_pose: Transform3D = works.gravity_valve.transform
	var other_serial: int = works.snapshot().axis.last_serial["2"]
	_check(works.reset_impulse_peer(1).ok and works.gravity_valve.transform==held_pose and works.snapshot().axis.last_serial["2"]==other_serial and works.status().gravity_speed==4.5,"one peer recreation keeps teammate's accepted impulse and all actual pose")
	_check(_step(0.1).ok and works.status().gravity_fraction>0.5,"teammate input still drives the actual valve after other actor recreates")
	# Real full bodies rolled as explicit obstacle fixtures, not claimed maneuvers.
	for peer in players:
		_fixture()
		var body: FlightBody = players[peer]
		var at := Vector3(-7.08,6.9+float(body.stats.width_m)*0.5,-5.0)
		body.global_transform=Transform3D(Basis(Vector3.FORWARD,PI*0.5),at)
		PhysicsServer3D.body_set_state(body.get_rid(),PhysicsServer3D.BODY_STATE_TRANSFORM,body.global_transform)
		await _settle()
		_check(_placed_body_clear(peer),"valve obstruction fixture starts clear of all existing solids",{"peer":peer})
		_check(_impulse(Vector3.RIGHT*9.0).ok,"authorized input aimed into real body obstacle")
		var pose: Transform3D = works.gravity_valve.transform
		var result := _step(0.25)
		_check(result.ok and result.gravity_blocked and works.gravity_valve.transform==pose and works.status().gravity_speed==0.0 and _placed_body_clear(peer),"full valve sweep blocks TR/HX without pushing into it or accumulating velocity",{"peer":peer,"result":result})
		await _park()
		_check(_step(0.1).ok and works.gravity_valve.transform==pose,"clearing obstruction alone releases no stored momentum")
		_check(_impulse(Vector3.RIGHT*9.0).ok and _step(0.25).ok and works.status().gravity_fraction>0.0,"new input after clearing body resumes actual movement")
	_fixture()
	var prop := StaticBody3D.new()
	var collider := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size=Vector3(0.1,0.1,0.1)
	collider.shape=box
	prop.add_child(collider)
	prop.collision_layer=32
	prop.position=Vector3(-7.3,7.1,-5)
	world.add_child(prop)
	await _settle()
	_check(_impulse(Vector3.RIGHT*9.0).ok and _step(0.25).gravity_blocked and works.status().gravity_fraction==0.0,"layer32 prop blocks complete high-speed swept valve volume")
	prop.queue_free()
	await _settle()
	var pose: Transform3D = works.gravity_valve.transform
	works.gravity_valve.position.y+=0.006
	before=works.snapshot()
	_check(not _step(0.1).ok and works.snapshot()==before,"unauthorized off-axis pose edit is rejected without changing hydraulic state")
	works.gravity_valve.transform=pose
	PhysicsServer3D.body_set_state(works.gravity_valve.get_rid(),PhysicsServer3D.BODY_STATE_TRANSFORM,works.gravity_valve.global_transform)

func _test_power_selector_and_interlock() -> void:
	_fixture()
	await _place(1,Vector3(-7,1.8,9.7))
	var charged := _resolve("charge",Works.RELAY_ID)
	_check(charged.ok and entities[Works.RELAY_ID].powered,"actual relay target accepts charge through production rules",charged)
	for unused in range(4): _step(0.25)
	_check(works.status().pump_fraction==0.0,"power alone does not move the selector")
	var controlled := _resolve("takeover",Works.PUMP_ID)
	_check(controlled.ok,"actual pump target accepts production takeover",controlled)
	for unused in range(4): _step(0.25)
	_check(is_equal_approx(float(works.status().pump_fraction),0.5) and int(works.status().clinic_volume_ml)==0,"first real selector second reaches half-stroke without opening water")
	var fraction := float(works.status().pump_fraction)
	_check(_step(0.25,{}).ok and works.status().pump_fraction==fraction,"offline owner cannot advance selector")
	players[1].enabled=false
	_check(_step(0.25).ok and works.status().pump_fraction==fraction,"disabled real owner body cannot advance selector")
	players[1].enabled=true
	entities[Works.RELAY_ID].powered=false
	_check(_step(0.25).ok and works.status().pump_fraction==fraction,"loss of effective power holds actual partial valve position")
	entities[Works.RELAY_ID].powered=true
	for unused in range(3): _step(0.25)
	_check(not works.status().pump_latched and int(works.status().clinic_volume_ml)==0,"1.75 powered valid seconds still supplies no water")
	_check(_step(0.25).ok and works.status().pump_latched and int(works.status().clinic_volume_ml)>0,"two valid powered control seconds reach actual open end and begin supply")
	entities[Works.PUMP_ID].controlled=false
	entities[Works.PUMP_ID].owner=""
	entities[Works.PUMP_ID].takeover_remaining=0.0
	var amount := int(works.status().clinic_volume_ml)
	_check(_step(0.1,{}).ok and int(works.status().clinic_volume_ml)>amount,"completed mechanical selection stays latched without indefinite takeover renewal")
	_check(works.interlock_bolt.position.is_equal_approx(Vector3(-7.48,7,-5)),"pump engagement places real crossbolt in high-valve rail")
	await _park()
	_fixture(0.5,0,true)
	entities[Works.PUMP_ID].controlled=true
	entities[Works.PUMP_ID].owner="1"
	entities[Works.PUMP_ID].takeover_remaining=8.0
	_check(_step(0.25).ok and works.status().interlock_waiting and works.status().pump_fraction==0.0 and int(works.status().clinic_volume_ml)==0,"part-open mechanical valve visibly interlocks pump and neither incomplete path feeds")
	_fixture()
	entities[Works.RELAY_ID].powered=true
	entities[Works.PUMP_ID].controlled=true
	entities[Works.PUMP_ID].owner="1"
	entities[Works.PUMP_ID].takeover_remaining=8.0
	var blocker := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size=Vector3(0.08,0.5,0.5)
	shape.shape=box
	blocker.add_child(shape)
	blocker.position=Vector3(-6.51,1.6,7)
	blocker.collision_layer=1
	world.add_child(blocker)
	await _settle()
	_check(_step(0.25).ok and works.status().selector_blocked and works.status().pump_fraction==0.0,"actual selector sweep stops before an external solid instead of teleporting through it")
	blocker.queue_free()
	await _settle()

func _test_crossbolt_sweep() -> void:
	await _park()
	# Full production body shapes, explicitly rolled 90 degrees as a spatial
	# obstruction fixture. This tests geometry, not a claimed player maneuver.
	# The narrow presented side avoids the real rail/end stops; every starting
	# fixture must be clear of current solids, so a failure cannot be attributed
	# to an already intersecting valve or terrain.
	for peer in players:
		for leading_z in [-4.3,-5.2]:
			_fixture()
			_enable_selector_fixture()
			var body: FlightBody = players[peer]
			var at := Vector3(-7.58+float(body.stats.height_m)*0.5,6.9+float(body.stats.width_m)*0.5,float(leading_z)-float(body.stats.length_m)*0.5)
			body.global_transform=Transform3D(Basis(Vector3.FORWARD,PI*0.5),at)
			PhysicsServer3D.body_set_state(body.get_rid(),PhysicsServer3D.BODY_STATE_TRANSFORM,body.global_transform)
			await _settle()
			_check(_placed_body_clear(peer),"crossbolt full-body fixture starts clear of existing geometry",{"peer":peer,"leading_z":leading_z})
			var selector_before: Transform3D = works.pump_selector.transform
			var bolt_before: Transform3D = works.interlock_bolt.transform
			var nodes_before: Dictionary = works.snapshot().runtime.simulation.nodes
			var result: Dictionary = _step(0.25)
			_check(result.ok and works.status().selector_blocked and works.status().pump_fraction==0.0 and works.pump_selector.transform==selector_before and works.interlock_bolt.transform==bolt_before,"occupied high crossbolt middle/endpoint blocks both actuators atomically",{"peer":peer,"leading_z":leading_z,"result":result})
			_check(works.snapshot().runtime.simulation.nodes==nodes_before and _placed_body_clear(peer),"blocked crossbolt neither injects water nor penetrates real drone",{"peer":peer,"leading_z":leading_z})
			await _park()
			var cleared: Dictionary = _step(0.25)
			_check(cleared.ok and not works.status().selector_blocked and works.status().pump_fraction>0.0,"clearing actual crossbolt body obstruction permits both mechanisms",cleared)
	for z in [-4.3,-5.25]:
		_fixture()
		_enable_selector_fixture()
		var blocker := StaticBody3D.new()
		var collision := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size=Vector3(0.12,0.12,0.12)
		collision.shape=box
		blocker.add_child(collision)
		blocker.position=Vector3(-7.48,7.1,float(z))
		blocker.collision_layer=32
		world.add_child(blocker)
		await _settle()
		var bolt_before: Transform3D = works.interlock_bolt.transform
		var result: Dictionary = _step(0.25)
		_check(result.ok and works.status().selector_blocked and works.status().pump_fraction==0.0 and works.interlock_bolt.transform==bolt_before,"middle/endpoint prop in layer32 blocks high bolt, despite clear low selector",{"z":z,"result":result})
		blocker.queue_free()
		await _settle()
		_check(_step(0.25).ok and not works.status().selector_blocked and works.status().pump_fraction>0.0,"removed crossbolt prop leaves a genuinely clear physical engagement path")

func _test_locked_valve_impulse() -> void:
	await _park()
	# Exact reported former false rejection: 8 mm travel is still inside the
	# physical 10 mm gap. It must not be confused with the opening threshold.
	_fixture(0.008/1.2,0.5,true)
	_check(_step(0.1).ok and int(works.snapshot().runtime.facts.gravity_open_permille)==0,"8mm physical closed-stop clearance remains updateable and cannot feed gravity")
	var invalid: Dictionary = works.snapshot()
	invalid.gravity_fraction=0.016/1.2
	invalid.axis.position_m=0.016
	var before: Dictionary = works.snapshot()
	_check(not works.apply_snapshot(invalid).ok and works.snapshot()==before,"interlocked travel beyond physical gap minus sweep margin is atomically rejected")
	for pump in [0.5,1.0]:
		_fixture(0.0,float(pump),true)
		await _place(1,Vector3(-10,7,-2.5))
		var result := _resolve("push_pull",Works.GRAVITY_ID)
		_check(result.ok,"real push rule can attempt to move a partially/fully pump-locked valve",{"pump":pump,"result":result})
		if not result.ok: continue
		for request in result.physics_requests:
			_check(_impulse(request.impulse).ok,"authorized production impulse enters guided axis")
		var accepted := true
		var max_travel := 0.0
		var first_failure: Dictionary = {}
		var water_before := int(works.status().clinic_volume_ml)
		for unused in range(60):
			await physics_frame
			var moved: Dictionary = _step(1.0/60.0)
			if not moved.ok and first_failure.is_empty(): first_failure=moved
			accepted=accepted and bool(moved.ok)
			max_travel=maxf(max_travel,float(works.gravity_valve.position.x)+8.0)
		_check(accepted and max_travel>=0.0 and max_travel<=0.015 and works.status().pump_fraction==pump,"real crossbolt contact after push stays inside bounded clearance without poisoning water updates",{"pump":pump,"max_travel_m":max_travel,"first_failure":first_failure})
		_check(int(works.snapshot().runtime.facts.gravity_open_permille)==0,"closed crossbolt clearance never reaches true gravity-flow detent",{"pump":pump})
		var expected_flow: bool = int(works.status().clinic_volume_ml)>water_before if pump==1.0 else int(works.status().clinic_volume_ml)==water_before
		_check(expected_flow,"full pump keeps supplying after actual crossbolt impact; incomplete pump remains shut",{"pump":pump,"volume_ml":works.status().clinic_volume_ml})
		await _park()

func _test_lift_sweep_and_volume() -> void:
	await _park()
	for peer in players:
		_fixture(1.0,0,false,1000000)
		var height := float(players[peer].stats.height_m)
		await _place(peer,Vector3(0,4.502+height*0.5,-4))
		var clear := _body_sweep(peer,players[peer].global_position,players[peer].global_position)
		_check(clear.ok,"pinch fixture begins outside current deck, not already penetrating: "+str(peer),clear)
		var before: Dictionary = works.snapshot()
		var deck_before: Transform3D = works.deck.transform
		var blocked: Dictionary = _step(0.25)
		var after_status: Dictionary = works.status()
		# Actual Vector3 position stores float32; adding double half-thickness
		# does not produce an exact 4.5 scalar. Require bit-identical pose before/
		# after, exact integer water, plus a 1 micrometre absolute top error bound.
		_check(blocked.ok and after_status.platform_blocked and int(after_status.clinic_volume_ml)==1000000 and works.deck.transform==deck_before and absf(float(after_status.deck_top_y)-4.5)<=0.000001,"full drone envelope stops both speculative fill and real platform: "+str(peer),{"result":blocked,"volume_ml":after_status.clinic_volume_ml,"deck_top_y":after_status.deck_top_y,"top_error_m":float(after_status.deck_top_y)-4.5,"transform_unchanged":works.deck.transform==deck_before})
		_check(works.snapshot().runtime.simulation.nodes==before.runtime.simulation.nodes and float(works.status().elapsed_seconds)>float(before.runtime.simulation.tick)*0.1,"blocked interval advances only explicit time, conserving all water")
		var after_clear := _body_sweep(peer,players[peer].global_position,players[peer].global_position)
		_check(after_clear.ok,"stopped platform never penetrates occupying body: "+str(peer),after_clear)
		await _park()
		_check(_step(0.1).ok and int(works.status().clinic_volume_ml)>1000000,"clearing obstruction permits ordinary bounded supply again")
	_fixture(1.0,0,false,1000000)
	await _place(2,Vector3(0,6.402+float(players[2].stats.height_m)*0.5,-7.6))
	_check(_step(0.25).ok and works.status().platform_blocked and int(works.status().clinic_volume_ml)==1000000,"northern linkage alone can block supply even with empty deck volume")
	await _park()
	_fixture(1.0,0,false,1999000)
	_check(_step(0.1).ok and int(works.status().clinic_volume_ml)==2000000,"remaining 1000 ml reaches exact cutoff through physical sweep adapter")
	_check(is_equal_approx(float(works.status().deck_top_y),5.0) and is_equal_approx(float(works.water_level(Runtime.CLINIC)),4.5) and is_equal_approx(float(works.water_surfaces[Runtime.CLINIC].position.y),4.5),"actual platform, visible surface and authoritative fluid level share one accepted state")
	var water_ray := _ray(Vector3(0.9,4.7,-8),Vector3(0.9,4.3,-8))
	_check(water_ray.is_empty() and works.contains_water(Vector3(0.9,4.4,-8)) and not works.contains_water(Vector3(1.01,4.4,-8)),"filled tank water stays non-colliding and classification respects actual inner walls")
	for peer in players:
		var crossing := _body_sweep(peer,Vector3(-3.4,5.8,-3.5),Vector3(3.4,5.8,-3.5))
		_check(crossing.ok,"TR/HX full envelope crosses actual aligned landing/deck/landing: "+str(peer),crossing)
	var stable: Dictionary = works.snapshot().runtime.simulation.nodes
	for unused in range(12): _step(0.25)
	_check(works.snapshot().runtime.simulation.nodes==stable and works.status().inlet_closed,"continued updates after 2000 L do not move water or lift higher")

func _test_client_first_frame() -> void:
	var saved: Dictionary = works.snapshot()
	var data: Dictionary = works.layout()
	works.queue_free()
	await _settle()
	var guest := Works.new()
	var decoded: Dictionary = JSON.parse_string(JSON.stringify(saved,"",true,true))
	_check(guest.load_layout(decoded,false).ok,"guest validates hydraulic and actuator snapshot plus authored collision before tree insertion")
	_check(is_equal_approx(guest.deck.position.y+0.175,5.0) and guest.gravity_valve is StaticBody3D,"guest restored geometry uses non-integrating collider before first tree frame")
	world.add_child(guest)
	works=guest
	await _settle()
	var hit := _ray(Vector3(0,5.3,-4),Vector3(0,4.8,-4))
	_check(not hit.is_empty() and absf(float(hit.position.y)-5.0)<0.002,"first guest PhysicsServer state contains the saved raised deck")
	var before: Dictionary = guest.snapshot()
	_check(not guest.can_accept_impulse(Works.GRAVITY_ID,Vector3.RIGHT,1,9999).ok and not guest.apply_authorized_impulse(Works.GRAVITY_ID,Vector3.RIGHT,1,9999).ok and guest.snapshot()==before,"client rejects both impulse approval and execution without state change")
	_check(not guest.fixed_update(0.25,_default_entities(),players,true).ok and guest.snapshot()==before,"client cannot independently advance even when caller supplies true authority flag")
	decoded.runtime.simulation.nodes.clear()
	_check(guest.snapshot()==before,"guest restore does not alias caller-owned nested water state")
	_check(guest.apply_snapshot(before).ok and not guest.apply_snapshot(before).changed,"duplicate reliable guest state has no replayed actuator motion")
	# A received moving pose is a UI/replication fixture; guest cannot integrate
	# or locally rewrite its authoritative velocity when opening a pause menu.
	var moving: Dictionary = before.duplicate(true)
	moving.gravity_speed=1.0
	moving.axis.velocity_mps=1.0
	_check(guest.apply_snapshot(moving).ok,"guest accepts valid authoritative velocity display")
	var received: Dictionary = guest.snapshot()
	guest.set_simulation_paused(true)
	_check(guest.snapshot()==received,"client local pause does not mutate authoritative motion snapshot")
	_check(not guest.reset_impulse_peer(1).ok and guest.snapshot()==received,"client cannot reset actor anti-replay lifecycle")

func _finish() -> void:
	finished=true
	if is_instance_valid(world): world.queue_free()
	await process_frame
	await process_frame
	print("V3_CLINIC_WATERWORKS_TESTS "+JSON.stringify({"checks":checks,"failures":failures,"engine_errors":error_logger.errors,"measurements":measurements,
		"scope":"independent real PhysicsServer / production flight envelopes; explicit placement and saved-level fixtures; no Session, save, LAN, GPU, performance or human-play claim"}))
	var failed: bool = not failures.is_empty() or not error_logger.errors.is_empty()
	OS.remove_logger(error_logger)
	quit(1 if failed else 0)
