extends SceneTree
## Actual PhysicsServer devices/support/air gap plus original water solver.
## Fixed device poses and accelerated bounded rule intervals are declared test
## fixtures, not a played Boss, normal MAIN integration, GPU or LAN acceptance.
const Rig = preload("res://scripts/v3/gameplay/twin_pump_guardian_mechanisms.gd")
var checks := 0
var failures := 0

class FixtureWorld:
	extends Node3D
	var region_id := "I2"
	var objects: Dictionary = {}
	var definitions: Dictionary = {}
	var initial_transforms: Dictionary = {}
	func _entity(key: String,title: String,at: Vector3,size: Vector3,tags: Array,properties: Dictionary,_tint: Color,_dynamic = false) -> void:
		var id := "I2:"+key
		var body := StaticBody3D.new()
		body.name = key
		body.position = at
		body.collision_layer = 8
		body.collision_mask = 1|2|8
		body.set_meta("entity_id",id)
		var shape := BoxShape3D.new()
		shape.size = size
		var collider := CollisionShape3D.new()
		collider.shape = shape
		body.add_child(collider)
		add_child(body)
		objects[id] = body
		initial_transforms[id] = body.transform
		var state := {"id":id,"name":title,"position":at,"tags":tags,"owner":"neutral","revision":0}
		state.merge(properties,true)
		definitions[id] = state

func _initialize() -> void:
	call_deferred("_run")

func _check(condition: bool,label: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("PUMP GUARDIAN: "+label)

func _totals(mechanism) -> Array:
	var clean := 0
	var dirty := 0
	for node in mechanism.network.snapshot().nodes.values():
		clean += int(node.clean_ml)
		dirty += int(node.dirty_ml)
	return [clean,dirty]

func _operation_clear(body: PhysicsBody3D,finish: Transform3D) -> bool:
	var collider: CollisionShape3D
	for child in body.get_children():
		if child is CollisionShape3D: collider = child; break
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = collider.shape
	query.collision_mask = 1|2|8
	query.exclude = [body.get_rid()]
	query.margin = .001
	for step in range(1,9):
		query.transform = body.global_transform.interpolate_with(finish,float(step)/8.0)*collider.transform
		if not body.get_world_3d().direct_space_state.intersect_shape(query,4).is_empty(): return false
	return true

func _run() -> void:
	var world := FixtureWorld.new()
	root.add_child(world)
	_check(Rig.install(world).ok,"three actual devices and supported low-cost tank geometry installed")
	var count: int = world.get_child_count()
	_check(Rig.install(world).ok and world.get_child_count() == count,"install is idempotent")
	_check(world.objects.size() == 3 and world.definitions.size() == 3,"fixed tank walls do not clutter interactive target registries")
	await physics_frame
	await physics_frame
	var mechanism = Rig.new()
	_check(mechanism.configure(world,world.objects,true).ok,"original conservative WaterNetwork configured")
	var entities: Dictionary = world.definitions.duplicate(true)
	_check(_totals(mechanism) == [2500000,0],"three actual reservoirs begin with exactly 2500L clean")
	_check(mechanism.boss_environment().water_level_mm == 2000 and not mechanism.boss_environment().civilian_supply_isolated,"initial 2m water is real volume/area, civilian plug still closed")
	var volume_before: int = int(mechanism.network.get_node(Rig.BASIN).volume_ml)
	for _step in range(3): _check(mechanism.advance(1.0,entities,{}).ok,"unpowered physical observation advances safe time")
	_check(int(mechanism.network.get_node(Rig.BASIN).volume_ml) == volume_before,"unpowered pump moves no water")
	var valve: PhysicsBody3D = world.objects[Rig.VALVE]
	var plug: PhysicsBody3D = world.objects[Rig.PLUG]
	var open_pose: Transform3D = plug.global_transform
	open_pose.origin = Rig.PLUG_OPEN
	var fill_pose: Transform3D = valve.global_transform
	fill_pose.basis = Basis(Vector3.UP,PI/2.0)
	_check(_operation_clear(plug,open_pose),"normal G-size sweep can really extract isolation plug")
	_check(_operation_clear(valve,fill_pose),"normal G-size sweep can really rotate direction valve")
	plug.global_transform = open_pose
	await physics_frame
	await physics_frame
	mechanism.advance(.1,entities,{})
	_check(mechanism.boss_environment().civilian_supply_isolated,"actual clear pipe gap plus intact check bypass and reserve prove isolation")
	_check(mechanism.boss_environment().water_level_mm == 2000,"plug movement alone does not set a water-level gate")
	entities[Rig.RELAY].charge = 100.0
	valve.global_transform = fill_pose
	await physics_frame
	await physics_frame
	_check(mechanism.boss_environment().water_level_mm == 2000,"direction change alone never teleports water")
	for _step in range(8):
		var pumped: Dictionary = mechanism.advance(1.0,entities,{})
		_check(pumped.ok and pumped.moved_ml == 50000,"actual high pump rate remains bounded at 50L/s")
		_check(_totals(mechanism) == [2500000,0] and mechanism.network.validate_snapshot(mechanism.network.snapshot()).ok,"each original network interval conserves both fluid components")
	_check(mechanism.boss_environment().water_level_mm == 3000,"eight actual 50L/s rule intervals raise 0.4m2 cistern by 1m")
	_check(is_equal_approx(float(entities[Rig.RELAY].charge),92.0),"flow spends only original relay charge")
	_check(int(mechanism.network.get_node(Rig.CIVILIAN).clean_ml) == 300000,"resident independent reserve is not drawn by combat pumps")
	valve.rotation.y = 0.0
	await physics_frame
	await physics_frame
	for _step in range(8): mechanism.advance(1.0,entities,{})
	_check(mechanism.boss_environment().water_level_mm == 2000 and _totals(mechanism) == [2500000,0],"reverse pump returns to actual low window without creating water")
	var actor := {"active":true,"position":valve.global_position+Vector3.UP*2.0}
	mechanism.advance(0.0,entities,{1:actor})
	_check(mechanism.observe_interaction(1,Rig.VALVE).ok,"near real unobstructed device can record an informational reading")
	for target in ["I2:canal_exchange_verified","I2:canal_service_verified","I2:boss_observed","I2:boss_defeated","I2:chapter_choice"]:
		_check(mechanism.fact(target).is_empty(),"G/running water cannot forge original Story receipt: "+target)
	var saved: Dictionary = mechanism.persistent_state()
	var decoded: Dictionary = JSON.parse_string(JSON.stringify(saved,"",true,true))
	_check(mechanism.validate_state(decoded).ok and mechanism.restore(decoded).ok,"original water + bounded history survive JSON and restore")
	var stable := JSON.stringify(mechanism.persistent_state(),"",true,true)
	_check(mechanism.advance(1.0,entities,{},true).ok and JSON.stringify(mechanism.persistent_state(),"",true,true) == stable,"pause consumes no simulation or charge")
	var invalid: Dictionary = decoded.duplicate(true)
	invalid.simulation.nodes[Rig.CIVILIAN].clean_ml -= 1
	invalid.simulation.nodes[Rig.BASIN].clean_ml += 1
	_check(not mechanism.restore(invalid).ok,"aggregate-conserved theft from independent resident reserve refused")
	invalid = decoded.duplicate(true)
	invalid.simulation.nodes[Rig.BASIN].clean_ml += 1
	_check(not mechanism.restore(invalid).ok,"original solver rejects created water")
	entities[Rig.RELAY].charge = 19.0
	volume_before = int(mechanism.network.get_node(Rig.BASIN).volume_ml)
	mechanism.advance(1.0,entities,{})
	_check(int(mechanism.network.get_node(Rig.BASIN).volume_ml) == volume_before,"stored powered flag cannot substitute for actual sufficient charge")
	plug.global_position = Rig.PLUG_CLOSED
	await physics_frame
	await physics_frame
	mechanism.advance(.1,entities,{})
	_check(not mechanism.boss_environment().civilian_supply_isolated,"actually reinserted isolation plug closes Boss safety window")
	plug.global_position = Rig.PLUG_OPEN
	var check_body: PhysicsBody3D = mechanism.bodies.CivilianCheckBypass
	check_body.get_child(0).disabled = true
	await physics_frame
	await physics_frame
	_check(mechanism.boss_environment().is_empty(),"missing real check bypass cannot default to safe isolation")
	check_body.get_child(0).disabled = false
	await physics_frame
	await physics_frame
	var guest = Rig.new()
	_check(guest.configure(world,world.objects,false).ok,"guest may construct a presentation-only mechanism binding")
	var guest_before := JSON.stringify(guest.persistent_state(),"",true,true)
	_check(not guest.advance(.1,entities,{}).ok and JSON.stringify(guest.persistent_state(),"",true,true) == guest_before,"guest cannot run another water simulation")
	world.queue_free()
	await physics_frame
	print("Pump guardian mechanisms: %d checks, %d failures; real device collision + original conservative solver; no played Boss/MAIN/LAN claim." % [checks,failures])
	quit(0 if failures == 0 else 1)
