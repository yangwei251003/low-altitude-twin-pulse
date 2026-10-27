extends RefCounted
## Unloaded real FlightBody departure from one verified horizontal support.
## A query-only support exclusion never disables the actual collision shape.
const Flight = preload("res://scripts/v2/flight_body.gd")
const Pilot = preload("res://scripts/v3/gameplay/canal/canal_transport_physics/transport_pilot.gd")
const Dock = preload("res://scripts/v3/gameplay/canal/canal_transport_physics/dock_lift.gd")
const MASK := 1 | 2 | 4 | 8 | 32
# The through lane remains X14.75/Y2.2. Finish in its western inspection
# pocket; do not park a real aircraft on the carrier's north/south return leg.
# Z11.1 retains the measured clearance south of WestTrackPier2.
const ROUTE: Array[Vector3] = [Vector3(6.6,1.8,6),Vector3(6.6,1.8,11.1),Vector3(12.2,1.8,11.1),Vector3(12.2,1.8,14)]
var _body: WeakRef
var _support: WeakRef
var _support_pose := Transform3D.IDENTITY
var _support_box := AABB()
var _space := RID()
var _pilot: RefCounted
var _phase := "idle"
var _code := "idle"
var _index := 0
var _leg_started := false
var _serial := 0
var _stable := 0.0
var _last_frame := -1
var _last: Dictionary = {}
var _health := 0.0
var _collisions := 0

func begin(body: Flight, support: StaticBody3D, authority: bool = true) -> Dictionary:
    if not authority: return {"ok":false,"code":"not_authority"}
    if _phase != "idle": return {"ok":false,"code":"already_started"}
    var proof: Dictionary = support_proof(body,support)
    if not proof.get("supported",false): return {"ok":false,"code":"actual_support_required","proof":proof}
    if not body.cargo_items.is_empty(): return {"ok":false,"code":"unloaded_only"}
    _body = weakref(body)
    _support = weakref(support)
    _support_pose = support.global_transform
    _support_box = proof.support_bounds
    _space = body.get_world_3d().space
    _health = body.health
    _collisions = body.collision_count
    _pilot = Pilot.new()
    if not _pilot.bind(body): return {"ok":false,"code":"pilot_bind_failed"}
    _phase = "lift"
    _code = "started"
    return report()

func tick(delta: float, authority: bool = true, paused: bool = false) -> Dictionary:
    if not authority: return _reply(false,"not_authority")
    if not is_finite(delta) or delta < 0 or delta > minf(.1,1.0/Engine.physics_ticks_per_second+.000001): return _reply(false,"invalid_delta")
    if _phase == "idle": return _reply(false,"not_started")
    if not _live():
        _phase = "fault"
        _code = "registered_body_or_support_changed"
        _stable = 0.0
        brake()
        return report()
    if paused or delta == 0:
        brake()
        _stable = 0.0
        _pilot.settled_seconds = 0.0
        _pilot.clear_seconds = 0.0
        if _phase == "arrived": _phase = "terminal_hold"
        return _reply(true,"paused_not_physics_frozen")
    if _last_frame == Engine.get_physics_frames(): return _reply(false,"same_physics_frame")
    if _last_frame >= 0 and Engine.get_physics_frames() > _last_frame+1:
        _stable = 0.0
        _pilot.settled_seconds = 0.0
        _pilot.clear_seconds = 0.0
    _last_frame = Engine.get_physics_frames()
    if _phase == "fault":
        brake()
        return report()
    var body: Flight = _body.get_ref()
    if _phase in ["arrived","terminal_hold"]:
        # Braking alone still drifts in wind. Keep the original final waypoint
        # and serial under the full swept Pilot, with fresh arrival evidence.
        # Blocking loses current readiness, never the already committed work.
        _last = _pilot.tick(delta,true,false)
        var arrived: bool = _last.get("arrived",false) and body.global_position.distance_to(ROUTE[-1]) < .18 and body.linear_velocity.length() < .18
        _stable = float(_last.get("settled_seconds",0.0))
        _phase = "arrived" if arrived else "terminal_hold"
        _code = "actual_terminal_held" if arrived else "terminal_blocked" if _last.get("state","") == "blocked" else "terminal_settling"
        return report()
    if _phase == "lift":
        var bounds: Dictionary = Dock._bounds(body)
        if not bounds.ok: return _fault("unsupported_collider")
        var box: AABB = bounds.bounds
        if not Dock._above(box,_support_box) or box.position.y < _support_box.end.y-.025: return _fault("left_original_support_column")
        var inflated: AABB = box.grow(Pilot.CLEARANCE)
        var query := PhysicsShapeQueryParameters3D.new()
        var shape := BoxShape3D.new()
        shape.size = inflated.size
        query.shape = shape
        query.transform = Transform3D(Basis.IDENTITY,inflated.get_center())
        query.collision_mask = MASK
        # Only while this unchanged sole Box remains wholly below this hull.
        query.exclude = [body.get_rid(),(_support.get_ref() as StaticBody3D).get_rid()]
        var space: PhysicsDirectSpaceState3D = body.get_world_3d().direct_space_state
        var overlap: Array[Dictionary] = space.intersect_shape(query,1)
        if not overlap.is_empty(): return _blocked("lift_initial_overlap",_hit(overlap[0]))
        var offset: Vector3 = ROUTE[0]-body.global_position
        var horizontal: Vector3 = Vector3(offset.x,0,offset.z).limit_length(.20)
        var climb: float = clampf(offset.y*1.2,0,.35)
        for velocity: Vector3 in [body.linear_velocity,Vector3(horizontal.x,climb,horizontal.z)]:
            if velocity.length() < .01: continue
            query.motion = velocity.normalized()*(velocity.length()+velocity.length_squared()/4.0+.2)
            var fraction: PackedFloat32Array = space.cast_motion(query)
            if fraction.size() != 2 or fraction[0] < .999:
                return _blocked("lift_stopping_sweep",{"fraction":fraction,"motion":query.motion})
        var normal: Dictionary = _pilot.probe(Vector3.ZERO)
        if normal.clear and offset.length() < .08 and body.linear_velocity.length() < .12:
            _stable += delta
        else: _stable = 0.0
        # Match Flight's normalized vertical <= .02 fallback (height error * 2)
        # to the SAME climb velocity already swept above, as ordinary Pilot does.
        body.hold_height = body.global_position.y+climb*.5
        body.command = {"active":true,"mode":"assisted","body_relative":false,"planar":horizontal/float(body.stats.speed_mps),"vertical":climb/float(body.stats.rise_mps),"yaw":0.0,"brake":false,"fire":false}
        _last = {"ordinary_probe":normal,"body_bounds":box,"support_bounds":_support_box,"support_query_excluded":true,"swept_climb_mps":climb,"command_vertical":body.command.vertical,"command_body_y":body.global_position.y,"command_hold_height":body.hold_height}
        _code = "lifting"
        if _stable >= .35:
            _phase = "route"
            _index = 1
            brake()
    else:
        if not _leg_started:
            _serial += 1
            if not _pilot.go_to(ROUTE[_index],_serial): return _fault("route_rejected")
            _leg_started = true
        _last = _pilot.tick(delta,true,false)
        _code = "route_blocked" if _last.get("state","") == "blocked" else "flying"
        if _last.get("arrived",false):
            if body.global_position.distance_to(ROUTE[_index]) >= .18 or body.linear_velocity.length() >= .18: return _fault("arrival_evidence_changed")
            _index += 1
            _leg_started = false
            if _index == ROUTE.size():
                _phase = "arrived"
                _code = "actual_short_route_complete"
                _stable = float(_last.get("settled_seconds",0.0))
    return report()

func report() -> Dictionary:
    return {"ok":_phase not in ["idle","fault"],"phase":_phase,"code":_code,"route_index":_index,"arrived":_phase == "arrived","stable_seconds":_stable,"controller":_last.duplicate(true)}

func brake() -> void:
    var body: Variant = _body.get_ref() if _body != null else null
    if not body is Flight or not is_instance_valid(body) or not body.is_inside_tree(): return
    body.hold_height = body.global_position.y
    body.command = {"active":true,"mode":"assisted","body_relative":false,"planar":Vector3.ZERO,"vertical":0.0,"yaw":0.0,"brake":true,"fire":false}

static func support_proof(body: Flight, support: StaticBody3D) -> Dictionary:
    if not is_instance_valid(body) or not body.is_inside_tree() or not is_instance_valid(support) or not support.is_inside_tree(): return {"supported":false,"code":"missing_body"}
    if body.get_world_3d().space != support.get_world_3d().space: return {"supported":false,"code":"different_space"}
    var source: Dictionary = Dock._support(support)
    var hull: Dictionary = Dock._bounds(body)
    if not source.ok or not hull.ok: return {"supported":false,"code":"unsupported_collider"}
    var bounds: AABB = hull.bounds
    var slab: AABB = source.bounds
    var contact: bool = body.get_colliding_bodies().has(support)
    var rays := true
    var hits: Array = []
    var excluded: Array[RID] = [body.get_rid()]
    for ratio: Vector2 in [Vector2.ZERO,Vector2(-.35,-.35),Vector2(-.35,.35),Vector2(.35,-.35),Vector2(.35,.35)]:
        var origin := Vector3(bounds.get_center().x+ratio.x*bounds.size.x,bounds.position.y+.03,bounds.get_center().z+ratio.y*bounds.size.z)
        var query := PhysicsRayQueryParameters3D.create(origin,origin+Vector3.DOWN*.10,MASK,excluded)
        var hit: Dictionary = body.get_world_3d().direct_space_state.intersect_ray(query)
        rays = rays and hit.get("collider") == support
        hits.append(str(hit.get("collider","")))
    var gap: float = bounds.position.y-slab.end.y
    var supported: bool = body.enabled and not body.freeze and body.cargo_items.is_empty() and contact and rays and Dock._above(bounds,slab) and absf(gap) <= .025 and body.linear_velocity.length() <= .10 and body.angular_velocity.length() <= .12 and body.global_basis.y.dot(Vector3.UP) >= .985
    return {"supported":supported,"code":"supported" if supported else "not_supported","contact":contact,"rays":rays,"hits":hits,"gap":gap,"body_bounds":bounds,"support_bounds":slab,"support_rid":support.get_rid()}

func _live() -> bool:
    var body: Variant = _body.get_ref() if _body != null else null
    var support: Variant = _support.get_ref() if _support != null else null
    if not body is Flight or not is_instance_valid(body) or not body.is_inside_tree() or body.is_queued_for_deletion(): return false
    if not support is StaticBody3D or not is_instance_valid(support) or not support.is_inside_tree() or support.is_queued_for_deletion(): return false
    var checked: Dictionary = Dock._support(support)
    return body.get_world_3d().space == _space and support.get_world_3d().space == _space and support.global_transform == _support_pose and checked.ok and checked.bounds.is_equal_approx(_support_box) and body.enabled and not body.freeze and body.health == _health and body.collision_count == _collisions and not body.water_contact and body.cargo_items.is_empty()

func _blocked(code: String, details: Dictionary) -> Dictionary:
    _code = code
    _last = details
    _stable = 0
    _pilot.settled_seconds = 0.0
    _pilot.clear_seconds = 0.0
    brake()
    return report()

func _fault(code: String) -> Dictionary:
    _phase = "fault"
    _code = code
    _stable = 0.0
    brake()
    return report()

func _reply(ok: bool, code: String) -> Dictionary:
    var result: Dictionary = report()
    result.ok = ok
    result.code = code
    return result

static func _hit(hit: Dictionary) -> Dictionary:
    var collider: Variant = hit.get("collider")
    return {"collider":str(collider.get_path()) if collider is Node and is_instance_valid(collider) else str(collider)}
