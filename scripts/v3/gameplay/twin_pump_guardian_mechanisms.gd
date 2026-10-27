extends RefCounted
## I2 combat-only hydraulic rig over the original conservative water solver.
## Does not touch Clinic/Distribution/Trial/Shared/Canal or civilian save state.
const Water = preload("res://scripts/v3/gameplay/environment/twin_water_network.gd")
const RELAY := "I2:guardian_power_relay"
const VALVE := "I2:guardian_direction_valve"
const PLUG := "I2:guardian_isolation_plug"
const DEVICES := [RELAY,VALVE,PLUG]
const BASIN := "I2:guardian_basin"
const RETURN := "I2:guardian_return"
const CIVILIAN := "I2:guardian_civilian_reserve"
const DRAIN := "I2:guardian_drain"
const FILL := "I2:guardian_fill"
const RIG := "PumpGuardianRig"
const PLUG_CLOSED := Vector3(-10,4.72,-25)
const PLUG_OPEN := Vector3(-8.4,4.72,-25)
const METHODS := ["manual","charge","push_pull","takeover","echo","force_field"]
var world: Node3D
var bodies: Dictionary = {}
var region := "I2"
var authority := false
var network = Water.new()
var _entities: Dictionary = {}
var _players: Dictionary = {}
var _state: Dictionary = {}
var _view: Dictionary = {}

static func device_specifications() -> Array:
	return [
		{"id":RELAY,"name":"守卫泵组供电 · ≥20","position":[-10,4.72,-21],"size":[1,1,1],"tags":["conductive","electrical"],"properties":{"charge":0.0,"charge_capacity":100.0,"power_threshold":20.0,"powered":false},"color":Color("e7c361")},
		{"id":VALVE,"name":"方向阀 · 0°排 / 90°灌","position":[10,4.72,-21],"size":[1,1,1],"tags":["mechanical","movable","hackable","echo_operable"],"properties":{"angle":0.0},"color":Color("72b6c3")},
		{"id":PLUG,"name":"居民支路隔离塞 · 向东拔出","position":[-10,4.72,-25],"size":[.6,1,1.8],"tags":["mechanical","movable","hackable","echo_operable"],"properties":{"angle":0.0},"color":Color("e2a45c")}]

## Called once by Root's I2 builder before it copies World.definitions into the
## original entities. Only three interactive targets enter those registries.
static func install(owner_world: Node3D) -> Dictionary:
	if not is_instance_valid(owner_world) or not owner_world.is_inside_tree() or owner_world.get("region_id") != "I2" or not owner_world.has_method("_entity"): return {"ok":false,"code":"live_i2_factory_required"}
	if owner_world.has_node(RIG):
		for id in DEVICES:
			if not owner_world.objects.has(id): return {"ok":false,"code":"partial_existing_guardian_rig"}
		return {"ok":true,"code":"already_installed","device_ids":DEVICES.duplicate()}
	for id in DEVICES:
		if owner_world.objects.has(id) or owner_world.definitions.has(id): return {"ok":false,"code":"guardian_target_conflict"}
	var rig := Node3D.new()
	rig.name = RIG
	owner_world.add_child(rig)
	var material := StandardMaterial3D.new()
	material.albedo_color = Color("437f9c")
	material.roughness = .35
	var fixed_material := StandardMaterial3D.new()
	fixed_material.albedo_color = Color("5c7880")
	fixed_material.roughness = .8
	for spec in fixed_specifications(): _solid(rig,spec.id,_vector(spec.position),_vector(spec.size),fixed_material)
	for spec in tank_specifications():
		var surface := MeshInstance3D.new()
		surface.name = str(spec.id)+"Water"
		var mesh := BoxMesh.new()
		mesh.size = Vector3(float(spec.width),.03,float(spec.depth))
		surface.mesh = mesh
		surface.material_override = material
		surface.position = Vector3(float(spec.x),float(spec.initial_level)-.015,float(spec.z))
		rig.add_child(surface)
	for spec in device_specifications():
		owner_world._entity(str(spec.id).trim_prefix("I2:"),spec.name,_vector(spec.position),_vector(spec.size),spec.tags.duplicate(),spec.properties.duplicate(true),spec.color)
	return {"ok":true,"code":"guardian_rig_installed","device_ids":DEVICES.duplicate(),"combat_water_only":true}

static func tank_specifications() -> Array:
	# Physical footprint exactly matches the solver's area_cm2. Volumes are not
	# scaled up to imply that this little control cistern floods the whole arena.
	return [{"id":"Basin","x":0.0,"z":-25.0,"base":0.0,"width":.8,"depth":.5,"height":4.5,"initial_level":2.0},
		{"id":"Return","x":7.0,"z":-25.0,"base":0.0,"width":1.0,"depth":1.0,"height":2.3,"initial_level":1.4},
		{"id":"Civilian","x":-15.0,"z":-25.0,"base":5.0,"width":.6,"depth":.5,"height":1.2,"initial_level":6.0}]

static func fixed_specifications() -> Array:
	var result: Array = [
		{"id":"WestControlPad","position":[-11.5,2.1,-23],"size":[9,4.2,8]},
		{"id":"EastControlPad","position":[10,2.1,-21],"size":[4,4.2,4]},
		{"id":"CivilianTankStand","position":[-15,4.5,-25],"size":[1,.6,1]},
		{"id":"CivilianCheckBypass","position":[-12.25,4.72,-23.5],"size":[3.9,1,.35]},
		{"id":"BattlePipeEnd","position":[-10,4.72,-26.5],"size":[.6,1,1]},
		{"id":"CivilianPipeEnd","position":[-10,4.72,-23.5],"size":[.6,1,1]}]
	for tank in tank_specifications():
		var x: float = tank.x
		var z: float = tank.z
		var y: float = tank.base
		var width: float = tank.width
		var depth: float = tank.depth
		var height: float = tank.height
		result.append({"id":str(tank.id)+"Floor","position":[x,y-.1,z],"size":[width+.24,.2,depth+.24]})
		for side in [-1,1]:
			result.append({"id":str(tank.id)+("West" if side < 0 else "East"),"position":[x+float(side)*(width*.5+.06),y+height*.5,z],"size":[.12,height,depth+.24]})
			result.append({"id":str(tank.id)+("South" if side < 0 else "North"),"position":[x,y+height*.5,z+float(side)*(depth*.5+.06)],"size":[width,height,.12]})
	return result

static func definition() -> Dictionary:
	var edges: Array = []
	for row in [[DRAIN,BASIN,RETURN],[FILL,RETURN,BASIN]]:
		edges.append({"id":row[0],"from":row[1],"to":row[2],"kind":"pump","max_rate_ml_s":50000,"conductance_ml_s_per_mm":0,"pump_head_mm":10000,"initial_open_permille":0,"initial_powered":false,"bidirectional":false})
	return {"schema_version":1,"id":"I2:guardian_combat_water","version":1,"nodes":[
		{"id":BASIN,"capacity_ml":1600000,"clean_ml":800000,"dirty_ml":0,"base_mm":0,"area_cm2":4000},
		{"id":RETURN,"capacity_ml":2000000,"clean_ml":1400000,"dirty_ml":0,"base_mm":0,"area_cm2":10000},
		{"id":CIVILIAN,"capacity_ml":300000,"clean_ml":300000,"dirty_ml":0,"base_mm":5000,"area_cm2":3000}],"edges":edges}

func configure(owner_world: Node3D, real_bodies: Dictionary = {}, is_authority: bool = true) -> Dictionary:
	if not _state.is_empty() or not is_instance_valid(owner_world) or not owner_world.is_inside_tree() or owner_world.get("region_id") != "I2": return _no("live_i2_required")
	var configured: Dictionary = network.configure(definition())
	if not configured.ok: return configured
	world = owner_world
	bodies = (real_bodies if not real_bodies.is_empty() else world.objects).duplicate()
	var rig: Node = world.get_node_or_null(RIG)
	if is_instance_valid(rig):
		for child in rig.get_children():
			if child is PhysicsBody3D: bodies[str(child.name)] = child
	authority = is_authority
	_state = {"schema_version":1,"region_id":"I2","serial":0,"simulation":network.snapshot(),"readings":{},"methods":{}}
	_refresh_view()
	return _yes("configured")

func advance(delta: float, entities: Dictionary, players: Dictionary, paused: bool = false) -> Dictionary:
	if not authority: return _no("authority_required")
	if _state.is_empty() or not is_instance_valid(world): return _no("not_configured")
	if not is_finite(delta) or delta < 0.0 or delta > 1.0: return _no("invalid_delta")
	_entities = entities
	_players = players
	if paused or delta == 0.0: return _yes("paused")
	var powered: bool = _power_available()
	var direction: String = _direction()
	var controls := {DRAIN:{"open_permille":0,"powered":false},FILL:{"open_permille":0,"powered":false}}
	if powered and direction in ["drain","fill"]:
		controls[DRAIN if direction == "drain" else FILL] = {"open_permille":1000,"powered":true}
	var advanced: Dictionary = network.step(delta,controls,true)
	if not advanced.ok: return advanced
	var changes: Dictionary = {}
	if int(advanced.moved_ml) > 0:
		# One charge unit per actual second of rated flow, not for a stalled pump.
		# Root persists this ORIGINAL entity with the conservative network state.
		var relay: Dictionary = _entities[RELAY]
		relay.charge = maxf(0.0,float(relay.charge)-float(advanced.moved_ml)/50000.0)
		relay.powered = float(relay.charge) >= 20.0
		relay.revision = int(relay.get("revision",0))+1
		changes[RELAY] = {"charge":relay.charge,"powered":relay.powered,"revision":relay.revision}
	_state.simulation = network.snapshot()
	_refresh_view()
	_sync_water()
	return {"ok":true,"code":"water_advanced","events":[],"entity_changes":changes,"facts_changed":false,"moved_ml":int(advanced.moved_ml),"ticks":int(advanced.ticks)}

func fact(_target: String) -> String:
	# Existing I2 action IDs are Canal exchange/service, boss observed/victory,
	# and explicit chapter consensus. Root's original participants own all five.
	# Water manipulation cannot forge any of those receipts.
	return ""

func boss_environment(requested_region: String = "") -> Dictionary:
	if requested_region not in ["","I2"] or _state.is_empty() or not _scene_complete(): return {}
	return {"water_level_mm":int(round(float(network.get_node(BASIN).level_m)*1000.0)),"civilian_supply_isolated":_civilian_isolated()}

func view_state() -> Dictionary:
	return _view.duplicate(true)

func persistent_state() -> Dictionary:
	return _state.duplicate(true)

func validate_state(saved: Dictionary) -> Dictionary:
	if not _keys(saved,["schema_version","region_id","serial","simulation","readings","methods"]) or saved.schema_version != 1 or saved.region_id != "I2" or not _integer(saved.serial,0,2147483647): return _no("guardian_state_identity")
	if not saved.simulation is Dictionary: return _no("guardian_simulation_type")
	var valid: Dictionary = network.validate_snapshot(saved.simulation)
	if not valid.ok: return _no("guardian_water:"+str(valid.code))
	# The resident reserve has no graph edge. Conserved aggregate totals alone
	# must not allow a forged restore to move its water into the combat loop.
	var reserve: Dictionary = saved.simulation.nodes[CIVILIAN]
	if int(reserve.clean_ml) != 300000 or int(reserve.dirty_ml) != 0: return _no("guardian_civilian_reserve_changed")
	if not saved.readings is Dictionary or not saved.methods is Dictionary or saved.readings.size() > 3 or saved.methods.size() > 3: return _no("guardian_history_type")
	for id in saved.methods:
		if id not in DEVICES or saved.methods[id] not in METHODS: return _no("guardian_method")
	for id in saved.readings:
		var reading: Variant = saved.readings[id]
		if id not in DEVICES or not _keys(reading,["peer","serial","tick","level_mm"]) or not reading.peer is String or reading.peer.length() > 160 or not _integer(reading.serial,1,int(saved.serial)) or not _integer(reading.tick,0,int(saved.simulation.tick)) or not _integer(reading.level_mm,0,4000): return _no("guardian_reading")
	return _yes("guardian_state_valid")

func restore(saved: Dictionary) -> Dictionary:
	var valid: Dictionary = validate_state(saved)
	if not valid.ok: return valid
	var restored: Dictionary = network.restore(saved.simulation)
	if not restored.ok: return restored
	_state = saved.duplicate(true)
	_state.serial = int(_state.serial)
	_state.simulation = network.snapshot()
	_refresh_view()
	_sync_water()
	return _yes("guardian_state_restored")

func observe_interaction(peer, id: String, _method: String = "") -> Dictionary:
	if not authority or id not in DEVICES or not _actor_near(peer,id): return _no("guardian_reading_not_near")
	_state.serial = int(_state.serial)+1
	_state.readings[id] = {"peer":str(peer),"serial":int(_state.serial),"tick":int(network.snapshot().tick),"level_mm":int(round(float(network.get_node(BASIN).level_m)*1000.0))}
	return _yes("manual_reading_recorded")

func observe_ability(peer, id: String, ability: String) -> Dictionary:
	if not authority or id not in DEVICES or ability not in METHODS or not _actor_near(peer,id): return _no("guardian_ability_not_observed")
	_state.methods[id] = ability
	return _yes("method_recorded_no_fact")

func _refresh_view() -> void:
	_view = {"water_level_mm":int(round(float(network.get_node(BASIN).get("level_m",0.0))*1000.0)),"civilian_supply_isolated":_civilian_isolated(),"powered":_power_available(),"direction":_direction(),"civilian_reserve_ml":300000,"combat_water_only":true}

func _sync_water() -> void:
	if not is_instance_valid(world): return
	var rig: Node = world.get_node_or_null(RIG)
	if not is_instance_valid(rig): return
	for pair in [["Basin",BASIN],["Return",RETURN],["Civilian",CIVILIAN]]:
		var surface: Node3D = rig.get_node_or_null(str(pair[0])+"Water")
		if is_instance_valid(surface): surface.position.y = float(network.get_node(pair[1]).level_m)-.015

func _power_available() -> bool:
	var relay: Variant = _entities.get(RELAY)
	return _device_at(RELAY,Vector3(-10,4.72,-21),Vector3.ONE) and _supported(RELAY) and relay is Dictionary and _number(relay.get("charge"),20.0,100.0)

func _direction() -> String:
	if not _device_at(VALVE,Vector3(10,4.72,-21),Vector3.ONE) or not _supported(VALVE): return "neutral"
	var axis: Vector3 = _body(VALVE).global_basis.x.normalized()
	if axis.dot(Vector3.RIGHT) > .98: return "drain"
	if axis.dot(Vector3.FORWARD) > .98: return "fill"
	return "neutral"

func _civilian_isolated() -> bool:
	if _state.is_empty() or not _scene_complete(): return false
	var reserve: Dictionary = network.get_node(CIVILIAN)
	if int(reserve.clean_ml) != 300000 or int(reserve.dirty_ml) != 0: return false
	for edge in network.definitions().edges:
		if edge.from == CIVILIAN or edge.to == CIVILIAN: return false
	if not _device_at(PLUG,PLUG_OPEN,Vector3(.6,1,1.8)) or not _supported(PLUG): return false
	# Actual open air between two immutable pipe mouths, plus an intact physical
	# independent check bypass. A controlled/powered flag cannot satisfy either.
	if not _ray(Vector3(-10,4.72,-25.9),Vector3(-10,4.72,-24.1)).is_empty(): return false
	var hit: Dictionary = _ray(Vector3(-14.4,4.72,-23.5),Vector3(-10.2,4.72,-23.5))
	return hit.get("collider") == _body("CivilianCheckBypass")

func _scene_complete() -> bool:
	if not is_instance_valid(world) or not world.is_inside_tree(): return false
	for spec in fixed_specifications():
		if not _device_at(spec.id,_vector(spec.position),_vector(spec.size),true): return false
	for id in DEVICES:
		if not is_instance_valid(_body(id)): return false
	return true

func _device_at(id: String, position: Vector3, size: Vector3, fixed: bool = false) -> bool:
	var body: PhysicsBody3D = _body(id)
	if not is_instance_valid(body) or body.global_position.distance_to(position) > .15 or body.global_basis.y.normalized().dot(Vector3.UP) < .99 or not body.global_basis.get_scale().is_equal_approx(Vector3.ONE): return false
	if fixed and not body.global_basis.is_equal_approx(Basis.IDENTITY): return false
	var shapes := 0
	for child in body.get_children():
		if not child is CollisionShape3D: continue
		if child.disabled or not child.shape is BoxShape3D or not child.transform.is_equal_approx(Transform3D.IDENTITY) or not child.shape.size.is_equal_approx(size): return false
		shapes += 1
	return shapes == 1

func _supported(id: String) -> bool:
	var body: PhysicsBody3D = _body(id)
	if not is_instance_valid(body): return false
	var at: Vector3 = body.global_position
	var hit: Dictionary = _ray(at,at-Vector3.UP*.65,[body.get_rid()])
	return not hit.is_empty() and Vector3(hit.normal).dot(Vector3.UP) > .98 and absf(float(hit.position.y)-4.2) < .025 and absf(at.y-.5-float(hit.position.y)) <= .025

func _actor_near(peer, id: String) -> bool:
	if not _players.has(peer) or not is_instance_valid(_body(id)): return false
	var actor: Variant = _players[peer]
	var at := Vector3.INF
	var excluded: Array = []
	if actor is Node3D and is_instance_valid(actor):
		if not bool(actor.get("enabled")): return false
		at = actor.global_position
		if actor is CollisionObject3D: excluded.append(actor.get_rid())
	elif actor is Dictionary and actor.get("active",false) and actor.get("position") is Vector3: at = actor.position
	if at.distance_to(_body(id).global_position) > 4.5: return false
	var hit: Dictionary = _ray(at,_body(id).global_position,excluded)
	return hit.is_empty() or hit.get("collider") == _body(id)

func _body(id: String) -> PhysicsBody3D:
	var body: Variant = bodies.get(id)
	return body if body is PhysicsBody3D and is_instance_valid(body) and body.is_inside_tree() and is_instance_valid(world) and body.get_world_3d().space == world.get_world_3d().space else null

func _ray(from: Vector3, to: Vector3, excluded: Array = []) -> Dictionary:
	if not is_instance_valid(world) or not world.is_inside_tree(): return {}
	var query := PhysicsRayQueryParameters3D.create(from,to,1|8)
	var rids: Array[RID] = []
	for rid in excluded:
		if rid is RID and rid.is_valid(): rids.append(rid)
	query.exclude = rids
	return world.get_world_3d().direct_space_state.intersect_ray(query)

static func _solid(parent: Node3D, id: String, at: Vector3, size: Vector3, material: StandardMaterial3D) -> void:
	var body := StaticBody3D.new()
	body.name = id
	body.position = at
	body.collision_layer = 1
	body.collision_mask = 1|2|8
	var shape := BoxShape3D.new()
	shape.size = size
	var collider := CollisionShape3D.new()
	collider.shape = shape
	body.add_child(collider)
	var mesh := BoxMesh.new()
	mesh.size = size
	var view := MeshInstance3D.new()
	view.mesh = mesh
	view.material_override = material
	body.add_child(view)
	parent.add_child(body)

static func _vector(value: Array) -> Vector3:
	return Vector3(float(value[0]),float(value[1]),float(value[2]))

static func _keys(value, keys: Array) -> bool:
	if not value is Dictionary or value.size() != keys.size(): return false
	for key in keys:
		if not value.has(key): return false
	return true

static func _number(value, low: float, high: float) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and float(value) >= low and float(value) <= high

static func _integer(value, low: int, high: int) -> bool:
	return _number(value,float(low),float(high)) and float(value) == floor(float(value))

static func _yes(code: String) -> Dictionary:
	return {"ok":true,"code":code,"events":[],"entity_changes":{},"facts_changed":false}

static func _no(code: String) -> Dictionary:
	return {"ok":false,"code":code,"events":[],"entity_changes":{},"facts_changed":false}

