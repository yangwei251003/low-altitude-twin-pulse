extends RefCounted
## Host-internal, capture-only checkpoint. Never ticks dependencies, issues a
## command, moves a body, restores entities, consumes credit or writes a Store.
const Flight = preload("res://scripts/v2/flight_body.gd")
const Catalog = preload("res://scripts/v2/catalog.gd")
const Rules = preload("res://scripts/v3/candidates/canal_service_loop/canal_service_runtime.gd")
const Custody = preload("res://scripts/v3/candidates/canal_transport_physics/cargo_custody.gd")
const Pilot = preload("res://scripts/v3/candidates/canal_transport_physics/transport_pilot.gd")
const Executor = preload("res://scripts/v3/candidates/canal_transport_executor/canal_transport_executor.gd")
const Bench = preload("res://scripts/v3/candidates/canal_workbench/workbench.gd")
const Departure = preload("res://scripts/v3/candidates/canal_workbench/beneficiary_departure.gd")
const Cooling = preload("res://scripts/v3/candidates/canal_cooling_station/cooling_station.gd")
const FlightState = preload("res://scripts/v3/candidates/canal_checkpoint/flight_state.gd")
const History = preload("res://scripts/v3/candidates/canal_checkpoint/history_state.gd")
const VERSION := 3
const KIND := "canal_safe_checkpoint_v3"
const LAYOUT_ID := "I2:canal_workbench_site_v1"
const BENEFICIARY_ID := "I2:canal_beneficiary_0"
const TOOL_IDS := ["ProbeHead","ProbeNeck","ProbeArm","ProbeCarriage"]
const STABLE_USEC := 350000
const RATE_HZ := 60
const MAX_COUNTER := 9007199254740991
const TOP_KEYS := ["version","kind","layout","physics","rules","history","checkpoint"]
const FLIGHT_KEYS := ["id","pose","velocity","angular_velocity","health","maximum_health","state"]
const CARGO_KEYS := ["holder","pose","velocity","angular_velocity","stable_usec","support_gap_m"]
var _last_frame := -1
var _first_frame := -1
var _binding: Array = []

## Repeated calls in one frame cannot accrue stability. A missed frame or any
## failed live gate resets this observer only; physical state remains untouched.
func capture(context: Dictionary, executor: RefCounted, workbench: Node3D, cooling: Node3D,
        authority: bool = true, paused: bool = false) -> Dictionary:
    if not authority: return _failed("authority_required")
    if paused: return _failed("paused")
    if Engine.physics_ticks_per_second != RATE_HZ: return _failed("physics_rate")
    var frame: int = Engine.get_physics_frames()
    var sampled: Dictionary = _sample(context,executor,workbench,cooling,frame)
    if not sampled.ok: return _failed(str(sampled.code),sampled.get("details",{}))
    var identity: Array = sampled.binding
    if identity != _binding or (_last_frame >= 0 and frame != _last_frame and frame != _last_frame+1):
        _first_frame = frame
        _binding = identity.duplicate()
    if _first_frame < 0: _first_frame = frame
    _last_frame = frame
    # Intervals between observations, not the number of calls.
    var observed_usec: int = mini(STABLE_USEC,roundi(float(frame-_first_frame)*1000000.0/RATE_HZ))
    if observed_usec < STABLE_USEC:
        return {"ok":false,"code":"stability_pending","observed_usec":observed_usec}
    var envelope: Dictionary = sampled.envelope
    envelope.physics.observed_usec = observed_usec
    var checked: Dictionary = validate(envelope)
    if not checked.ok: return _failed("capture_schema:"+str(checked.code))
    return {"ok":true,"code":"captured_only","envelope":envelope.duplicate(true)}

func reset_observation() -> void:
    _last_frame = -1
    _first_frame = -1
    _binding.clear()

func _failed(code: String, details: Dictionary = {}) -> Dictionary:
    reset_observation()
    return {"ok":false,"code":code,"details":details.duplicate(true)}

func _sample(context: Dictionary, executor: RefCounted, bench: Node3D, cooling: Node3D, frame: int) -> Dictionary:
    if not is_instance_valid(executor) or executor.get_script() != Executor or not is_instance_valid(bench) or bench.get_script() != Bench:
        return _bad("actual_modules_required")
    var carrier: Variant = context.get("carrier")
    var custody: Variant = context.get("custody")
    var rules: Variant = context.get("rules")
    var cargos: Variant = context.get("cargos")
    var berths: Variant = context.get("berths")
    if not carrier is Flight or not _live(carrier) or not _live(bench): return _bad("live_world_required")
    if not custody is RefCounted or custody.get_script() != Custody or not rules is RefCounted or rules.get_script() != Rules:
        return _bad("actual_rules_custody_required")
    if not _exact(cargos,Rules.CASSETTES) or not _exact(berths,Rules.BERTHS): return _bad("registry_ids")
    if not executor._authority or not bench._authority or executor._rules != rules or executor._custody != custody or bench._rules != rules or bench._custody != custody:
        return _bad("module_binding")
    if executor._in_tick or bench._in_tick: return _bad("incomplete_host_step")
    if executor._body == null or executor._body.get_ref() != carrier or bench._carrier == null or bench._carrier.get_ref() != carrier:
        return _bad("carrier_binding")
    if executor._last_frame != frame or bench._last_frame != frame or custody._last_physics_frame != frame:
        return _bad("current_host_physics_sample_required")
    if not executor._live_registry() or not bench._live(): return _bad("live_geometry_changed")
    var space: RID = carrier.get_world_3d().space
    if bench.get_world_3d().space != space or not _live(bench.beneficiary) or bench.beneficiary.get_world_3d().space != space:
        return _bad("same_world_required")
    if not _live(cooling) or cooling.get_script() != Cooling or cooling.get_world_3d().space != space or not cooling.bound_to(cargos,berths,custody):
        return _bad("actual_cooling_binding_required")
    var device: Dictionary = cooling.capture_state(frame)
    if not device.ok: return _bad("cooling:"+str(device.code))
    var state: Dictionary = rules.snapshot()
    var state_check: Dictionary = rules.validate_snapshot(state)
    if not state_check.ok: return _bad("rules:"+str(state_check.code))
    if state.jobs_completed != 1 or not state.pending_action.is_empty(): return _bad("completed_first_work_no_pending_required")
    var actual: Dictionary = custody.report()
    if not actual.authority or actual.paused: return _bad("active_host_custody_required")
    var flight: Dictionary = executor.report()
    var work: Dictionary = bench.report()
    if not flight.ok or flight.phase != "idle" or not flight.action.is_empty() or not flight.departure.is_empty(): return _bad("executor_not_quiescent")
    if not work.ok or not work.committed or work.phase != "departed" or work.receipt_count != 1:
        return _bad("completed_work_and_departure_required")
    if not work.departure.get("arrived",false) or int(work.departure.get("route_index",-1)) != Departure.ROUTE.size():
        return _bad("departure_incomplete")
    if bench.head.global_position.distance_to(Bench.PARK) > .000001: return _bad("tool_not_parked")
    var tracked: Array[PhysicsBody3D] = [carrier,bench.beneficiary]
    var identity: Array = [executor.get_instance_id(),bench.get_instance_id(),rules.get_instance_id(),custody.get_instance_id(),carrier.get_instance_id(),bench.beneficiary.get_instance_id(),cooling.get_instance_id()]
    for id: String in Rules.BERTHS:
        var berth: Variant = berths[id]
        if not berth is StaticBody3D or not _live(berth) or berth.get_world_3d().space != space: return _bad("berth_world")
        if executor._berths[id].get_ref() != berth or bench._berths[id].get_ref() != berth: return _bad("berth_binding")
        var box: Dictionary = custody._box_info(berth)
        if box.is_empty() or not box.transform.is_equal_approx(Transform3D(Basis.IDENTITY,Executor.BERTH_POINTS[id])) or not box.shape.size.is_equal_approx(Vector3(2,.5,2)):
            return _bad("berth_layout")
        identity.append(berth.get_instance_id())
    var cargo_rows: Dictionary = {}
    var occupied: Array = []
    for id: String in Rules.CASSETTES:
        var cargo: Variant = cargos[id]
        if not cargo is RigidBody3D or not _live(cargo) or cargo.get_world_3d().space != space: return _bad("cargo_world")
        if executor._cargos[id].get_ref() != cargo or bench._cargos[id].get_ref() != cargo: return _bad("cargo_binding")
        if not custody._integrity(id).is_empty(): return _bad("cargo_integrity")
        var holder: String = str(state.cassettes[id].holder)
        var physical: Dictionary = actual.cargos[id]
        if holder not in Rules.BERTHS or holder in occupied or physical.phase != "docked" or physical.berth != holder or not str(physical.carrier).is_empty() or int(physical.stable_usec) != Custody.STABLE_USEC:
            return _bad("stable_unique_docked_cargo_required")
        occupied.append(holder)
        var support: Dictionary = custody.support_info(id,holder)
        if not support.get("supported",false): return _bad("actual_support_required",{"cargo":id,"support":support})
        var cargo_box: Dictionary = custody._box_info(cargo)
        if cargo_box.is_empty() or not _single_box(cargo,Vector3(.4,.4,.4)):
            return _bad("cargo_geometry")
        for hit: Node in cargo.get_colliding_bodies():
            if hit != berths[holder]: return _bad("unexpected_cargo_contact")
        if cargo.freeze: return _bad("frozen_cargo")
        cargo_rows[id] = {"holder":holder,"pose":_pose(cargo.global_transform),"velocity":_xyz(cargo.linear_velocity),"angular_velocity":_xyz(cargo.angular_velocity),"stable_usec":Custody.STABLE_USEC,"support_gap_m":support.bottom_gap_m}
        tracked.append(cargo)
        identity.append(cargo.get_instance_id())
        identity.append(holder)
    for body: Flight in [carrier,bench.beneficiary]:
        var expected_mask: int = 47 if body == bench.beneficiary else 45
        if not _flight_live(body,expected_mask): return _bad("flight_unstable_or_changed",{"body":str(body.name)})
        var checker = Pilot.new()
        if not checker.bind(body): return _bad("query_binding")
        var clear: Dictionary = checker.probe(Vector3.ZERO)
        if not clear.clear: return _bad("flight_envelope_obstructed",{"body":str(body.name),"probe":clear})
    # Include joints outside this candidate's own subtree. Physical node identity
    # is used only during capture, never serialized as a stable entity ID.
    for node: Node in bench.get_tree().root.find_children("*","Joint3D",true,false):
        var joint: Joint3D = node as Joint3D
        if joint.get_node_or_null(joint.node_a) in tracked or joint.get_node_or_null(joint.node_b) in tracked:
            return _bad("attachment_present")
    var anchor: String = str(state.carrier_anchor)
    var target: Vector3 = _anchor(anchor)
    var hold: Dictionary = flight.hold
    var control: Dictionary = flight.controller
    if hold.get("anchor","") != anchor or hold.get("target") != target or not hold.get("action",{}).is_empty() or control.get("target") != target or not control.get("arrived",false) or float(control.get("settled_seconds",0)) < .35:
        return _bad("actual_anchor_hold_required")
    if carrier.global_position.distance_to(target) >= .18: return _bad("carrier_anchor_error")
    if bench.beneficiary.global_position.distance_to(Departure.ROUTE[-1]) >= .18: return _bad("beneficiary_left_terminal")
    var history: Dictionary = _history(work,bench.beneficiary,frame)
    if history.is_empty(): return _bad("first_result_evidence")
    identity.append(history.first_work.action.serial)
    identity.append(anchor)
    var tools: Dictionary = {}
    for part: AnimatableBody3D in bench._moving: tools[str(part.name)] = _pose(part.global_transform)
    var envelope: Dictionary = {"version":VERSION,"kind":KIND,
        "layout":{"id":LAYOUT_ID,"schema":3,"sha256":layout_fingerprint()},
        "physics":{"frame":frame,"rate_hz":RATE_HZ,"observed_usec":0},
        "rules":state.duplicate(true),"history":history,
        "checkpoint":{"carrier":_flight_row(carrier,Rules.CARRIER),"carrier_anchor":anchor,
            "beneficiary":_flight_row(bench.beneficiary,BENEFICIARY_ID),"cargos":cargo_rows,"tools":tools,
            "workbench_charge":work.charge,"workbench_charge_serial":work.charge_serial,"cooling":device.state.duplicate(true),"custody":custody.docked_snapshot()}}
    # All queries above are synchronous. Reject accidental nested advancement or
    # re-entry rather than combining observations from different world states.
    if frame != Engine.get_physics_frames() or rules.snapshot() != state or custody.report() != actual or executor.report() != flight or bench.report() != work or cooling.snapshot() != device.state:
        return _bad("capture_changed_during_read")
    return {"ok":true,"code":"sampled","binding":identity,"envelope":envelope}

func _history(work: Dictionary, beneficiary: Flight, frame: int) -> Dictionary:
    if not work.get("restored_history",{}).is_empty():
        return work.restored_history.duplicate(true)
    var evidence: Dictionary = work.receipt
    var receipt: Dictionary = evidence.get("receipt",{})
    if not _exact(receipt,Rules.RECEIPT_KEYS) or work.measurements != evidence.get("measurements") or int(evidence.get("physics_frame",0)) > frame: return {}
    for key: String in ["path_clear","endpoint_valid","custody_verified","completed"]:
        if receipt.get(key) != true: return {}
    var action: Dictionary = {}
    for key: String in Executor.MATCH_KEYS: action[key] = receipt[key]
    var samples: Array = []
    for measured: Dictionary in work.measurements:
        if not measured.get("ok",false) or measured.get("body_id") != beneficiary.get_instance_id(): return {}
        var bounds: AABB = measured.bounds
        samples.append({"stage":measured.stage,"frame":measured.physics_frame,"tool":_xyz(measured.tool),"hit":_xyz(measured.hit_position),"gap_m":measured.gap_m,"bounds_position":_xyz(bounds.position),"bounds_size":_xyz(bounds.size)})
    return {"source_frame":frame,"first_work":{"action":action,"beneficiary_id":BENEFICIARY_ID,"frame":evidence.physics_frame,
        "scan_distance_m":work.scan_distance_m,"measurements":samples,"beneficiary_pose":_pose(evidence.beneficiary_pose)},
        "first_departure":{"beneficiary_id":BENEFICIARY_ID,"work_serial":action.serial,"route_end":_xyz(Departure.ROUTE[-1])}}

## Internal consistency only: this does NOT authenticate a hostile edited save,
## recreate physics, prove current contact, or replace capture's host checks.
static func validate(envelope: Variant) -> Dictionary:
    if not _json_safe(envelope) or not _exact(envelope,TOP_KEYS): return _bad("envelope_keys_or_json_types")
    if not _integer(envelope.version,VERSION,VERSION) or envelope.kind != KIND: return _bad("version")
    if not _exact(envelope.layout,["id","schema","sha256"]) or envelope.layout.id != LAYOUT_ID or not _integer(envelope.layout.schema,3,3) or envelope.layout.sha256 != layout_fingerprint(): return _bad("layout")
    if not _exact(envelope.physics,["frame","rate_hz","observed_usec"]) or not _integer(envelope.physics.frame,1,MAX_COUNTER) or not _integer(envelope.physics.rate_hz,RATE_HZ,RATE_HZ) or not _integer(envelope.physics.observed_usec,STABLE_USEC,STABLE_USEC): return _bad("physics_sample")
    if not envelope.rules is Dictionary: return _bad("rules_type")
    var validator = Rules.new()
    if not validator.configure().ok: return _bad("rules_configuration")
    var valid_rules: Dictionary = validator.validate_snapshot(envelope.rules)
    if not valid_rules.ok: return _bad("rules:"+str(valid_rules.code))
    var state: Dictionary = envelope.rules
    if int(state.jobs_completed) != 1 or not state.pending_action.is_empty(): return _bad("first_completed_no_pending")
    var cp: Variant = envelope.checkpoint
    if not _exact(cp,["carrier","carrier_anchor","beneficiary","cargos","tools","workbench_charge","workbench_charge_serial","cooling","custody"]): return _bad("checkpoint_keys")
    var valid_custody: Dictionary = Custody.validate_docked_snapshot(cp.custody)
    if not valid_custody.ok or not _exact(cp.custody.cargos,Rules.CASSETTES): return _bad("custody_history")
    for id: String in Rules.CASSETTES:
        if cp.custody.cargos[id].berth != state.cassettes[id].holder: return _bad("custody_rules_holder")
    var valid_cooling: Dictionary = Cooling.validate_snapshot(cp.cooling)
    if not valid_cooling.ok or cp.cooling.paused: return _bad("cooling_state")
    if cp.carrier_anchor != state.carrier_anchor or not _flight_record(cp.carrier,Rules.CARRIER) or not _flight_record(cp.beneficiary,BENEFICIARY_ID): return _bad("flight_record")
    if _origin(cp.carrier.pose).distance_to(_anchor(str(cp.carrier_anchor))) >= .18 or _origin(cp.beneficiary.pose).distance_to(Departure.ROUTE[-1]) >= .18: return _bad("terminal_pose")
    if not _exact(cp.cargos,Rules.CASSETTES): return _bad("cargo_ids")
    var occupied: Array = []
    for id: String in Rules.CASSETTES:
        var cargo: Variant = cp.cargos[id]
        if not _exact(cargo,CARGO_KEYS) or cargo.holder not in Rules.BERTHS or cargo.holder in occupied or cargo.holder != state.cassettes[id].holder: return _bad("cargo_occupancy")
        occupied.append(cargo.holder)
        if not _pose_valid(cargo.pose) or not _vector(cargo.velocity,.12) or not _vector(cargo.angular_velocity,.15) or not _integer(cargo.stable_usec,Custody.STABLE_USEC,Custody.STABLE_USEC) or not _number(cargo.support_gap_m,-.025,.025): return _bad("cargo_stability")
        var pose: Transform3D = _transform(cargo.pose)
        var bounds: AABB = pose*AABB(Vector3(-.2,-.2,-.2),Vector3(.4,.4,.4))
        var support: AABB = AABB(Executor.BERTH_POINTS[str(cargo.holder)]-Vector3(1,.25,1),Vector3(2,.5,2))
        var gap: float = bounds.position.y-support.end.y
        if pose.basis.y.dot(Vector3.UP) < .985 or absf(gap) > .025 or absf(gap-float(cargo.support_gap_m)) > .00001 or bounds.position.x < support.position.x+.03 or bounds.end.x > support.end.x-.03 or bounds.position.z < support.position.z+.03 or bounds.end.z > support.end.z-.03:
            return _bad("cargo_support_geometry")
    for berth: String in [Rules.SOUTH_0,Rules.SOUTH_1]:
        var expected_contact := ""
        for id: String in Rules.CASSETTES:
            if cp.cargos[id].holder == berth: expected_contact = id
        if cp.cooling.contact_observation[berth] != expected_contact: return _bad("cooling_custody_observation")
    if not _exact(cp.tools,TOOL_IDS): return _bad("tool_ids")
    var boxes: Array[AABB] = Bench._tool_boxes(Bench.PARK)
    for i in TOOL_IDS.size():
        var pose: Variant = cp.tools[TOOL_IDS[i]]
        if not _pose_valid(pose) or not _transform(pose).is_equal_approx(Transform3D(Basis.IDENTITY,boxes[i].get_center())): return _bad("tool_park")
    if not _number(cp.workbench_charge,0,100) or not _integer(cp.workbench_charge_serial,1,2147483647): return _bad("workbench_power")
    return History.validate(envelope.history,state,Bench.POINT_A,Bench.POINT_B,Bench.TOOL_SIZE,Departure.ROUTE[-1])

static func layout_fingerprint() -> String:
    var berths: Dictionary = {}
    for id: String in Rules.BERTHS: berths[id] = [_xyz(Executor.BERTH_POINTS[id]),[2.0,.5,2.0]]
    var fixed: Array = []
    for row: Dictionary in Bench.fixed_definition(): fixed.append([row.id,_xyz(row.center),_xyz(row.size)])
    var tools: Array = []
    for box: AABB in Bench._tool_boxes(Bench.PARK): tools.append([_xyz(box.position),_xyz(box.size)])
    var route: Array = []
    for point: Vector3 in Departure.ROUTE: route.append(_xyz(point))
    return JSON.stringify({"id":LAYOUT_ID,"schema":3,"berths":berths,"wait":_xyz(Executor.WAIT_POINT),"workbench":fixed,"park_tools":tools,"departure_route":route,"flight":"tr01_default_v2","cargo":[.4,.4,.4,2.0],"cooling":Cooling.layout_fingerprint()},"",true,true).sha256_text()

static func _flight_live(body: Flight, expected_mask: int) -> bool:
    var resolved: Dictionary = Catalog.resolve_build(Catalog.default_build("tr01"))
    if body.build != resolved.build or not body.enabled or body.freeze or body.water_contact or not body.cargo_items.is_empty() or body.health <= 0 or body.collision_count != 0 or not body.get_colliding_bodies().is_empty(): return false
    if not body.global_transform.is_finite() or not body.linear_velocity.is_finite() or not body.angular_velocity.is_finite() or body.linear_velocity.length() >= .18 or body.angular_velocity.length() > .15: return false
    if body.collision_layer != 2 or body.collision_mask != expected_mask or not is_zero_approx(body.cargo_kg) or not is_equal_approx(body.mass,float(resolved.derived.mass_kg)): return false
    return _single_box(body,Vector3(1.4,.48,1.4)) and _pose_valid(_pose(body.global_transform)) and FlightState.safe_live(body) and FlightState.validate(FlightState.capture(body,"checked"),"checked")

static func _single_box(body: PhysicsBody3D, size: Vector3) -> bool:
    var shapes: int = 0
    for owner: int in body.get_shape_owners():
        if body.is_shape_owner_disabled(owner) or not body.shape_owner_get_transform(owner).is_equal_approx(Transform3D.IDENTITY): return false
        for index in body.shape_owner_get_shape_count(owner):
            var shape: Shape3D = body.shape_owner_get_shape(owner,index)
            if not shape is BoxShape3D or not shape.size.is_equal_approx(size): return false
            shapes += 1
    return shapes == 1

static func _flight_row(body: Flight, id: String) -> Dictionary:
    return FlightState.capture(body,id)

static func _flight_record(value: Variant, id: String) -> bool:
    return FlightState.validate(value,id)

static func _anchor(id: String) -> Vector3:
    return Executor.WAIT_POINT if id == Rules.WAIT else Vector3(Executor.BERTH_POINTS.get(id,Vector3.ZERO))+Vector3.UP*2.2

static func _live(value: Variant) -> bool:
    return value is Node3D and is_instance_valid(value) and value.is_inside_tree() and not value.is_queued_for_deletion()

static func _xyz(value: Vector3) -> Array:
    return [value.x,value.y,value.z]

static func _pose(value: Transform3D) -> Array:
    return _xyz(value.basis.x)+_xyz(value.basis.y)+_xyz(value.basis.z)+_xyz(value.origin)

static func _vec(value: Array) -> Vector3:
    return Vector3(float(value[0]),float(value[1]),float(value[2]))

static func _origin(value: Array) -> Vector3:
    return Vector3(float(value[9]),float(value[10]),float(value[11]))

static func _transform(value: Array) -> Transform3D:
    return Transform3D(Basis(_vec(value.slice(0,3)),_vec(value.slice(3,6)),_vec(value.slice(6,9))),_origin(value))

static func _pose_valid(value: Variant) -> bool:
    if not value is Array or value.size() != 12: return false
    for n: Variant in value:
        if not _number(n,-1000,1000): return false
    var basis: Basis = _transform(value).basis
    return absf(basis.determinant()-1.0) <= .00001 and basis.is_equal_approx(basis.orthonormalized())

static func _vector(value: Variant, maximum: float) -> bool:
    if not value is Array or value.size() != 3: return false
    for n: Variant in value:
        if not _number(n,-maximum,maximum): return false
    return _vec(value).length() <= maximum

static func _number(value: Variant, minimum: float, maximum: float) -> bool:
    return (value is int or value is float) and is_finite(float(value)) and float(value) >= minimum and float(value) <= maximum

static func _integer(value: Variant, minimum: int, maximum: int) -> bool:
    return _number(value,minimum,maximum) and float(value) == floor(float(value))

static func _exact(value: Variant, keys: Array) -> bool:
    if not value is Dictionary or value.size() != keys.size(): return false
    for key: Variant in value:
        if not key is String or key not in keys: return false
    return true

static func _json_safe(value: Variant, depth: int = 0) -> bool:
    if depth > 12: return false
    if value is Dictionary:
        if value.size() > 64: return false
        for key: Variant in value:
            if not key is String or key.length() > 128 or not _json_safe(value[key],depth+1): return false
        return true
    if value is Array:
        if value.size() > 64: return false
        for part: Variant in value:
            if not _json_safe(part,depth+1): return false
        return true
    if value is String: return value.length() <= 256
    if value is bool: return true
    return _number(value,-MAX_COUNTER,MAX_COUNTER)

static func _bad(code: String, details: Dictionary = {}) -> Dictionary:
    return {"ok":false,"code":code,"details":details}
