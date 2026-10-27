extends RefCounted
## Candidate site factory + bounded physical S0-to-WAIT bootstrap. World belongs
## to caller. create() is the sole initial placement boundary; tick never snaps.
const Executor = preload("res://scripts/v3/candidates/canal_transport_executor/canal_transport_executor.gd")
const Flight = preload("res://scripts/v2/flight_body.gd")
const Catalog = preload("res://scripts/v2/catalog.gd")
const Pilot = preload("res://scripts/v3/candidates/canal_transport_physics/transport_pilot.gd")
const Dock = preload("res://scripts/v3/candidates/canal_transport_physics/dock_lift.gd")
const Custody = preload("res://scripts/v3/candidates/canal_transport_physics/cargo_custody.gd")
const Rules = preload("res://scripts/v3/candidates/canal_service_loop/canal_service_runtime.gd")
const MASK := 1|2|4|8|32
var carrier: Flight
var cargos: Dictionary = {}
var berths: Dictionary = {}
var custody: RefCounted
var rules: RefCounted
var preflight: Array = []
var phase := "unconfigured"
var code := "unconfigured"
var controller: Dictionary = {}
var _world: WeakRef
var _query: Callable
var _authority := false
var _closed := false
var _in_tick := false
var _last_frame := -1
var _serial := 0
var _ticks := 0
var _pilot: RefCounted
var _dock: RefCounted
var _custody_started := false
var _alignment_seconds := 0.0
var _path: Array[Vector3] = [Vector3(14.75,2.2,21),Executor.WAIT_POINT]
var _leg := 0
var _leg_started := false
var _initial_nodes: Array[WeakRef] = []
var _progress_restore_contacts := false
var _progress_restore_frame := -1

func create(world: Node3D, environment_query: Callable, authority: bool = true) -> Dictionary:
    if phase != "unconfigured" or _closed: return {"ok":false,"code":"already_created_or_closed"}
    if not authority: return {"ok":false,"code":"not_authority"}
    if not is_instance_valid(world) or not world.is_inside_tree() or not environment_query.is_valid(): return {"ok":false,"code":"live_world_required"}
    if world.has_node("CanalTransportCandidateSite"): return {"ok":false,"code":"candidate_site_already_exists"}
    preflight.clear()
    for id: String in Executor.BERTH_POINTS:
        var checked: Dictionary = _site_preflight(world,id,Executor.BERTH_POINTS[id])
        preflight.append(checked)
        if not checked.ok: return {"ok":false,"code":"candidate_berth_obstructed","preflight":preflight.duplicate(true)}
    _world = weakref(world)
    _query = environment_query
    _authority = true
    var site := Node3D.new()
    site.name = "CanalTransportCandidateSite"
    world.add_child(site)
    # Coordinates are world coordinates even if a future caller nests its World.
    for id: String in Executor.BERTH_POINTS:
        var berth := StaticBody3D.new()
        berth.name = "CandidateBerth_"+id
        berth.collision_layer = 1
        berth.collision_mask = 0
        berth.add_child(_box(Vector3(2,.5,2)))
        site.add_child(berth)
        berth.global_position = Executor.BERTH_POINTS[id]
        berths[id] = berth
        _initial_nodes.append(weakref(berth))
    carrier = Flight.new()
    carrier.name = "CandidateCarrier"
    carrier.configure(Catalog.resolve_build(Catalog.default_build("tr01")))
    carrier.freeze = true
    carrier.max_altitude = 18.0
    site.add_child(carrier)
    carrier.global_position = Executor.BERTH_POINTS[Rules.SOUTH_0]+Vector3.UP*1.55
    carrier.hold_height = carrier.global_position.y
    carrier.safe_position = carrier.global_position
    carrier.environment_hazards_authoritative = true
    carrier.environment_query = environment_query
    carrier.environment_sample = environment_query.call(carrier.global_position)
    _initial_nodes.append(weakref(carrier))
    for pair: Array in [[Rules.CASSETTES[0],Rules.SOUTH_0],[Rules.CASSETTES[1],Rules.WORK]]:
        var cargo := RigidBody3D.new()
        cargo.name = str(pair[0]).replace(":","_")
        cargo.mass = 2.0
        cargo.can_sleep = false
        cargo.continuous_cd = true
        cargo.contact_monitor = true
        cargo.max_contacts_reported = 16
        cargo.collision_layer = 8
        cargo.collision_mask = MASK
        var material := PhysicsMaterial.new()
        material.friction = .55
        material.bounce = 0.0
        cargo.physics_material_override = material
        cargo.add_child(_box(Vector3(.4,.4,.4)))
        site.add_child(cargo)
        cargo.global_position = Executor.BERTH_POINTS[str(pair[1])]+Vector3.UP*.46
        cargos[str(pair[0])] = cargo
        _initial_nodes.append(weakref(cargo))
    _brake()
    phase = "initial_contacts"
    code = "created_physical_fixture_not_ready"
    return {"ok":true,"code":code,"preflight":preflight.duplicate(true)}

func tick(delta: float, authority: bool = true, suspended: bool = false) -> Dictionary:
    if not _authority or not authority: return _reply("not_authority",false)
    if _closed: return _reply("closed",false)
    if _in_tick: return _reply("reentrant_tick",false)
    if not is_finite(delta) or delta < 0 or delta > minf(.1,1.0/float(Engine.physics_ticks_per_second)+.000001): return _reply("invalid_physics_delta",false)
    if suspended or delta == 0:
        _reset_stability()
        _brake()
        return _reply("suspended",true)
    if _last_frame == Engine.get_physics_frames(): return _reply("same_physics_frame",false)
    if _last_frame >= 0 and Engine.get_physics_frames() > _last_frame+1: _reset_stability()
    _last_frame = Engine.get_physics_frames()
    _in_tick = true
    _advance(delta)
    _in_tick = false
    return report()

func context() -> Dictionary:
    # Live references for the owning host; deliberately not a save/network blob.
    return {"carrier":carrier,"cargos":cargos.duplicate(),"berths":berths.duplicate(),"custody":custody,"rules":rules,"environment_query":_query}

func report() -> Dictionary:
    return {"ok":phase != "fault" and not _closed,"phase":phase,"code":code,"ready":phase == "ready",
        "ticks":_ticks,"controller":controller.duplicate(true),"custody_started":_custody_started,
        "custody":custody.report() if _custody_started else {},"preflight":preflight.duplicate(true)}

func close(authority: bool = true) -> Dictionary:
    if not authority or not _authority: return _reply("not_authority",false)
    if _in_tick: return _reply("reentrant_close",false)
    _brake()
    _closed = true
    return report()

func _advance(delta: float) -> void:
    if phase in ["fault","ready"]: return
    var original_world: Variant = _world.get_ref() if _world != null else null
    if not original_world is Node3D or not is_instance_valid(original_world) or not original_world.is_inside_tree():
        _fault("initial_world_lost")
        return
    for reference: WeakRef in _initial_nodes:
        var value: Variant = reference.get_ref()
        if not value is PhysicsBody3D or not is_instance_valid(value) or not value.is_inside_tree() or value.is_queued_for_deletion() or value.get_world_3d().space != original_world.get_world_3d().space:
            _fault("initial_node_lost")
            return
    if not _query.is_valid() or not carrier.enabled or carrier.health != carrier.maximum_health or carrier.collision_count != 0 or carrier.water_contact:
        _fault("carrier_or_environment_fault")
        return
    carrier.environment_sample = _query.call(carrier.global_position)
    if _custody_started:
        var updated: Dictionary = custody.step(delta,true,false)
        if not updated.ok:
            _fault("custody:"+str(updated.code))
            return
    if not _safe_contacts():
        _fault("unexpected_physical_contact")
        return
    _ticks += 1
    match phase:
        "initial_contacts":
            if _ticks >= 75:
                custody = Custody.new()
                var configured: Dictionary = custody.configure(cargos,berths,{Rules.CARRIER:carrier},true)
                if not configured.ok:
                    _fault("custody_configure:"+str(configured.code))
                    return
                _custody_started = true
                for pair: Array in [[Rules.CASSETTES[0],Rules.SOUTH_0],[Rules.CASSETTES[1],Rules.WORK]]:
                    var seated: Dictionary = custody.seat(str(pair[0]),str(pair[1]),_next_serial(),custody.revision)
                    if not seated.ok:
                        _fault("initial_seat:"+str(seated.code))
                        return
                phase = "seating"
        "seating":
            if _docked(Rules.CASSETTES[0],Rules.SOUTH_0) and _docked(Rules.CASSETTES[1],Rules.WORK):
                carrier.freeze = false
                _pilot = Pilot.new()
                if not _pilot.bind(carrier) or not _pilot.go_to_pickup_alignment(cargos[Rules.CASSETTES[0]],_next_serial()):
                    _fault("initial_alignment_rejected")
                    return
                phase = "align"
        "align":
            controller = _pilot.tick(delta,true,false)
            if controller.state == "blocked":
                code = "alignment_blocked"
                return
            _alignment_seconds += delta
            if _alignment_seconds > 10:
                _fault("initial_alignment_deadline")
                return
            if controller.arrived and _slow():
                var offset: Vector3 = cargos[Rules.CASSETTES[0]].global_position-(carrier.global_position+Custody.LOAD_OFFSET)
                if offset.length() > Pilot.PICKUP_TOLERANCE:
                    _fault("initial_alignment_evidence")
                    return
                var picked: Dictionary = custody.pickup(Rules.CASSETTES[0],Rules.CARRIER,_next_serial(),custody.revision)
                if not picked.ok:
                    _fault("initial_pickup:"+str(picked.code))
                    return
                _brake()
                phase = "lift_wait"
        "lift_wait":
            _brake()
            if _slow():
                _dock = Dock.new()
                var started: Dictionary = _dock.begin(carrier,berths[Rules.SOUTH_0],_next_serial(),true)
                if not started.ok:
                    code = "departure_wait:"+str(started.code)
                    return
                phase = "lift"
        "lift":
            controller = _dock.tick(delta,true,false)
            if controller.get("clear",false): phase = "travel"
        "travel":
            if not _leg_started:
                if not _pilot.go_to(_path[_leg],_next_serial()):
                    _fault("initial_waypoint_rejected")
                    return
                _leg_started = true
            controller = _pilot.tick(delta,true,false)
            if controller.arrived:
                if carrier.global_position.distance_to(_path[_leg]) >= .18 or carrier.linear_velocity.length() >= .18:
                    _fault("initial_arrival_evidence")
                    return
                _leg += 1
                _leg_started = false
                if _leg == _path.size():
                    _brake()
                    phase = "verify_wait"
        "verify_wait":
            _brake()
            if _progress_restore_contacts and not _docked(Rules.CASSETTES[1],Rules.WORK):
                if _progress_restore_frame<0: _progress_restore_frame=Engine.get_physics_frames()
                var actual: Dictionary=custody.report().cargos[Rules.CASSETTES[1]]
                if actual.phase in ["settling","docked"] and actual.berth==Rules.WORK and Engine.get_physics_frames()-_progress_restore_frame<=90:
                    code="restored_original_work_support_pending"
                    return
            _progress_restore_contacts=false
            if carrier.global_position.distance_to(Executor.WAIT_POINT) >= .18 or not _joint() or not _docked(Rules.CASSETTES[1],Rules.WORK):
                _fault("initial_wait_custody_evidence")
                return
            rules = Rules.new()
            var configured: Dictionary = rules.configure()
            if not configured.ok:
                _fault("rules_configure:"+str(configured.code))
                return
            phase = "ready"
            code = "actual_wait_ready"

func _safe_contacts() -> bool:
    if not carrier.get_colliding_bodies().is_empty(): return false
    for id: String in cargos:
        var allowed: StaticBody3D = berths[Rules.WORK] if id == Rules.CASSETTES[1] else berths[Rules.SOUTH_0]
        if id == Rules.CASSETTES[0] and phase in ["travel","verify_wait"]: allowed = null
        for hit: Node in cargos[id].get_colliding_bodies():
            if hit != allowed: return false
    if _custody_started:
        for state: Dictionary in custody.report().cargos.values():
            if state.phase == "fault": return false
    return true

func _docked(id: String, berth: String) -> bool:
    var state: Dictionary = custody.report().cargos[id]
    return state.phase == "docked" and state.berth == berth and custody.support_info(id,berth).get("supported",false)

func _joint() -> bool:
    if carrier.cargo_items.size() != 1 or not carrier.cargo_items.has(Rules.CASSETTES[0]): return false
    var item: Dictionary = carrier.cargo_items[Rules.CASSETTES[0]]
    return is_instance_valid(item.joint) and item.joint is PinJoint3D and item.body == cargos[Rules.CASSETTES[0]] and item.joint.get_node_or_null(item.joint.node_a) == carrier and item.joint.get_node_or_null(item.joint.node_b) == item.body

func _slow() -> bool:
    if carrier.linear_velocity.length() > .12 or carrier.angular_velocity.length() > .12: return false
    for item: Dictionary in carrier.cargo_items.values():
        if item.body.linear_velocity.length() > .10 or item.body.angular_velocity.length() > .12 or (item.body.linear_velocity-carrier.linear_velocity).length() > .18: return false
    return true

func _next_serial() -> int:
    _serial = maxi(_serial,int(custody.last_serial))+1
    return _serial

func _reset_stability() -> void:
    if _pilot != null:
        _pilot.settled_seconds = 0.0
        _pilot.clear_seconds = 0.0
    if _dock != null: _dock.stable_seconds = 0.0

func _brake() -> void:
    if not is_instance_valid(carrier) or not carrier.is_inside_tree(): return
    carrier.hold_height = carrier.global_position.y
    carrier.command = {"active":true,"mode":"assisted","body_relative":false,"planar":Vector3.ZERO,"vertical":0.0,"brake":true,"fire":false}

func _fault(reason: String) -> void:
    _brake()
    code = reason
    phase = "fault"

func _reply(reason: String, ok: bool) -> Dictionary:
    var result: Dictionary = report()
    result.code = reason
    result.ok = ok
    return result

static func _box(size: Vector3) -> CollisionShape3D:
    var node := CollisionShape3D.new()
    var shape := BoxShape3D.new()
    shape.size = size
    node.shape = shape
    return node

static func _site_preflight(world: Node3D, id: String, at: Vector3) -> Dictionary:
    var space: PhysicsDirectSpaceState3D = world.get_world_3d().direct_space_state
    var query := PhysicsShapeQueryParameters3D.new()
    var shape := BoxShape3D.new()
    shape.size = Vector3(2,.5,2)
    query.shape = shape
    query.transform = Transform3D(Basis.IDENTITY,at)
    query.collision_mask = MASK
    var intrusions: Array = []
    for hit: Dictionary in space.intersect_shape(query,32):
        var value: Variant = hit.get("collider")
        var bounds: Dictionary = _fixed_bounds(value)
        if not bounds.ok or bounds.bounds.end.y > at.y+.005: intrusions.append(str(value.get_path()) if value is Node else str(value))
    var supports: Array = []
    var supported := true
    for offset: Vector3 in [Vector3.ZERO,Vector3(-.8,0,-.8),Vector3(.8,0,-.8),Vector3(-.8,0,.8),Vector3(.8,0,.8)]:
        var ray := PhysicsRayQueryParameters3D.create(at+offset+Vector3.UP*.02,at+offset+Vector3.DOWN*.3,MASK)
        var hit: Dictionary = space.intersect_ray(ray)
        var valid: bool = not hit.is_empty() and absf(hit.position.y-at.y) < .01
        supported = supported and valid
        supports.append({"valid":valid,"position":hit.get("position",Vector3.ZERO)})
    shape = BoxShape3D.new()
    shape.size = Vector3(2,2.35,2)
    query.shape = shape
    query.transform.origin = at+Vector3.UP*1.455
    var air: Array = []
    for hit: Dictionary in space.intersect_shape(query,32): air.append(str(hit.collider.get_path()))
    return {"ok":intrusions.is_empty() and air.is_empty() and supported,"id":id,"intrusions":intrusions,"overhead":air,"supports":supports}

static func _fixed_bounds(value: Variant) -> Dictionary:
    if not value is CollisionObject3D: return {"ok":false}
    var initialized := false
    var bounds := AABB()
    for owner: int in value.get_shape_owners():
        if value.is_shape_owner_disabled(owner): continue
        var pose: Transform3D = value.global_transform*value.shape_owner_get_transform(owner)
        for i in value.shape_owner_get_shape_count(owner):
            var shape: Shape3D = value.shape_owner_get_shape(owner,i)
            var part := AABB()
            if shape is BoxShape3D: part = pose*AABB(-shape.size*.5,shape.size)
            elif shape is ConcavePolygonShape3D:
                var vertices: PackedVector3Array = shape.get_faces()
                if vertices.is_empty(): return {"ok":false}
                part = AABB(pose*vertices[0],Vector3.ZERO)
                for vertex: Vector3 in vertices: part = part.expand(pose*vertex)
            else: return {"ok":false}
            bounds = bounds.merge(part) if initialized else part
            initialized = true
    return {"ok":initialized,"bounds":bounds}
