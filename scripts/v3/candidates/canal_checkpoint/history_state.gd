extends RefCounted
## Stable historical evidence. Never fabricates a current measurement/body ID.
const State = preload("res://scripts/v3/candidates/canal_checkpoint/flight_state.gd")
const BENEFICIARY_ID := "I2:canal_beneficiary_0"
const MATCH_KEYS := ["serial","kind","actor","cassette_id","source","destination","route","job"]

static func validate(history: Variant, state: Dictionary, point_a: Vector3, point_b: Vector3, tool_size: Vector3, route_end: Vector3) -> Dictionary:
    if not State.exact(history,["source_frame","first_work","first_departure"]): return _bad("history_keys")
    if not State.integer(history.source_frame,1,9007199254740991): return _bad("history_source_frame")
    var capture_frame: int = int(history.source_frame)
    var work: Variant = history.first_work
    if not State.exact(work,["action","beneficiary_id","frame","scan_distance_m","measurements","beneficiary_pose"]) or work.beneficiary_id != BENEFICIARY_ID or not State.pose_valid(work.beneficiary_pose): return _bad("work_evidence")
    var action: Variant = work.action
    if not State.exact(action,MATCH_KEYS) or not State.integer(action.serial,1,int(state.action_serial)) or action.kind != "work" or action.actor != "workbench" or action.cassette_id not in state.cassettes.keys() or action.source != "north_work" or action.destination != "north_work" or action.route != "stationary" or not State.integer(action.job,1,1): return _bad("work_identity")
    if not State.integer(work.frame,1,capture_frame) or not State.number(work.scan_distance_m,1.39999,1.40001) or not work.measurements is Array or work.measurements.size() != 3: return _bad("work_measurements")
    var prior: int = 0
    var initial: Transform3D = State.transform(work.beneficiary_pose)
    var original_bounds: AABB = initial*AABB(Vector3(-.7,-.24,-.7),Vector3(1.4,.48,1.4))
    if initial.origin.distance_to(Vector3(6.6,.56,6)) > .08 or initial.basis.y.dot(Vector3.UP) < .985: return _bad("work_original_support")
    for i in 3:
        var measured: Variant = work.measurements[i]
        if not State.exact(measured,["stage","frame","tool","hit","gap_m","bounds_position","bounds_size"]) or not State.integer(measured.stage,i,i) or not State.integer(measured.frame,prior+1,int(work.frame)) or not State.vector_valid(measured.tool,1000) or not State.vector_valid(measured.hit,1000) or not State.number(measured.gap_m,.04,.18) or not State.vector_valid(measured.bounds_position,1000) or not State.vector_valid(measured.bounds_size,3): return _bad("measurement_order_or_values")
        var tool: Vector3 = State.vec(measured.tool)
        var hit: Vector3 = State.vec(measured.hit)
        var expected: Vector3 = point_b if i == 1 else point_a
        var bounds: AABB = AABB(State.vec(measured.bounds_position),State.vec(measured.bounds_size))
        if bounds.size.x <= 0 or bounds.size.y <= 0 or bounds.size.z <= 0 or bounds.get_center().distance_to(original_bounds.get_center()) > .16: return _bad("measurement_body_bounds")
        # Preserve EACH historical collider bound. The support allows tiny
        # physical movement during scanning; final pose is not every old pose.
        if tool.distance_to(expected) > .00001 or Vector2(hit.x-tool.x,hit.z-tool.z).length() > .00001 or hit.x < bounds.position.x or hit.x > bounds.end.x or hit.z < bounds.position.z or hit.z > bounds.end.z or absf(hit.y-bounds.end.y) > .00001 or absf((tool.y-tool_size.y*.5)-hit.y-float(measured.gap_m)) > .00001: return _bad("measurement_geometry")
        prior = int(measured.frame)
    var departure: Variant = history.first_departure
    if not State.exact(departure,["beneficiary_id","work_serial","route_end"]) or departure.beneficiary_id != BENEFICIARY_ID or not State.integer(departure.work_serial,int(action.serial),int(action.serial)) or not State.vector_valid(departure.route_end,1000) or State.vec(departure.route_end).distance_to(route_end) > .000001: return _bad("departure_history")
    return {"ok":true,"code":"valid_historical_work"}

static func _bad(code: String) -> Dictionary:
    return {"ok":false,"code":code}
