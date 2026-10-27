extends RefCounted
## Committed work history and the ORIGINAL live departure controller.
## No begin/go_to/receipt/service replay, and no imported current contact credit.
const State=preload("res://scripts/v3/gameplay/canal/canal_checkpoint/flight_state.gd")
const History=preload("res://scripts/v3/gameplay/canal/canal_checkpoint/history_state.gd")
const Parts=preload("res://scripts/v3/gameplay/canal/canal_checkpoint/canal_progress_state.gd")
const Departure=preload("res://scripts/v3/gameplay/canal/canal_workbench/beneficiary_departure.gd")
const Rules=Parts.Rules
const KEYS=["version","phase","code","charge","charge_serial","beneficiary","support_observed_seconds","stage","action","bound_pose","health_baseline","collision_baseline","scan_distance_m","tool","tools","history","departure","terminal_pilot"]
const DEPARTURE_KEYS=["version","phase","code","index","leg_started","serial","stable_seconds","support_pose","support_position","support_size","health","collisions","pilot"]
const COMMIT_KEYS=["version","phase","charge","charge_serial","beneficiary","support_observed_seconds","source_frame","action","stage","tool","tools","scan_distance_m","bound_pose","health_baseline","collision_baseline","measurements"]

static func snapshot(bench: Node3D) -> Dictionary:
    var result: Dictionary=inspect(bench)
    return result.snapshot if result.ok else {}

static func inspect(bench: Node3D) -> Dictionary:
    if not bench._configured or bench._closed or not bench._authority or not bench._live() or not bench._committed or bench._receipt_count!=1 or not bench._tools_synchronized(): return _bad("committed_live_identity_or_tools")
    var history: Dictionary=_history(bench)
    if history.is_empty(): return _bad("committed_actual_history")
    var tools: Array=[]
    for part: AnimatableBody3D in bench._moving:
        tools.append({"pose":State.pose(part.global_transform),"size":State.xyz((part.get_child(0).shape as BoxShape3D).size)})
    var row: Dictionary={"version":3,"phase":bench._phase,"code":bench._code,"charge":bench._charge,"charge_serial":bench._charge_serial,"beneficiary":State.capture_progress(bench.beneficiary,History.BENEFICIARY_ID),"support_observed_seconds":bench._support_stable,"stage":bench._stage,"action":bench._action.duplicate(true),"bound_pose":State.pose(bench._bound_pose),"health_baseline":bench._health,"collision_baseline":bench._collision_count,"scan_distance_m":bench._scan_distance,"tool":State.xyz(bench.head.global_position),"tools":tools,"history":history,"departure":departure_snapshot(bench._departure),"terminal_pilot":Parts.pilot_snapshot(bench._terminal_pilot,{})}
    var checked: Dictionary=validate(row,bench._rules.snapshot(),bench.get_script())
    return {"ok":true,"snapshot":row} if checked.ok else {"ok":false,"code":checked.code,"candidate":row}

static func validate(row: Variant, rules: Dictionary, bench_script: Script) -> Dictionary:
    if row is Dictionary and row.get("version")==4: return validate_commit(row,rules,bench_script)
    if not State.exact(row,KEYS) or row.version!=3 or row.phase not in ["departing","departed","restored_settling"] or not row.code is String or not State.number(row.charge,0,100) or not State.integer(row.charge_serial,1,2147483647) or not State.number(row.support_observed_seconds,0,1e9): return _bad("progress_committed_workbench_schema")
    if not State.validate_progress(row.beneficiary,History.BENEFICIARY_ID) or not State.number(row.health_baseline,.00001,100) or not State.integer(row.collision_baseline,0,2147483647) or row.beneficiary.health!=row.health_baseline or row.beneficiary.wait.collision_count!=row.collision_baseline: return _bad("progress_committed_beneficiary")
    if int(rules.get("jobs_completed",-1))!=1 or not History.validate(row.history,rules,bench_script.POINT_A,bench_script.POINT_B,bench_script.TOOL_SIZE,Departure.ROUTE[-1]).ok: return _bad("progress_committed_history")
    if not State.pose_valid(row.bound_pose) or not State.number(row.scan_distance_m,1.39999,1.40001) or not State.vector_valid(row.tool,1000) or State.vec(row.tool)!=bench_script.PARK: return _bad("progress_committed_tool_endpoint")
    if not row.departure is Dictionary or not row.terminal_pilot is Dictionary or not row.action is Dictionary: return _bad("progress_committed_controller_types")
    if not row.terminal_pilot.is_empty():
        if not row.departure.is_empty() or not row.action.is_empty() or not State.integer(row.stage,0,0) or not Parts.validate_pilot(row.terminal_pilot) or State.vec(row.terminal_pilot.target)!=Departure.ROUTE[-1]: return _bad("progress_completed_terminal_controller")
    else:
        if not State.integer(row.stage,4,4) or not State.exact(row.action,Rules.ACTION_KEYS) or not row.action.blocked is bool: return _bad("progress_committed_action")
        for key: String in History.MATCH_KEYS:
            if row.action[key]!=row.history.first_work.action[key]: return _bad("progress_committed_action_identity")
        if not row.departure.is_empty() and (not validate_departure(row.departure) or row.departure.health!=row.health_baseline or row.departure.collisions!=row.collision_baseline): return _bad("progress_committed_departure")
    var boxes: Array[AABB]=bench_script._tool_boxes(bench_script.PARK)
    if not row.tools is Array or row.tools.size()!=4: return _bad("progress_committed_tool_registry")
    for i in 4:
        var tool: Variant=row.tools[i]
        if not State.exact(tool,["pose","size"]) or not State.pose_valid(tool.pose) or not State.vector_valid(tool.size,10) or State.transform(tool.pose)!=Transform3D(Basis.IDENTITY,boxes[i].get_center()) or State.vec(tool.size)!=boxes[i].size: return _bad("progress_committed_tool_pose")
    return {"ok":true,"code":"valid_committed_history_original_departure"}

static func apply(bench: Node3D, row: Dictionary) -> bool:
    if row.version==4: return apply_commit(bench,row)
    bench._phase=str(row.phase)
    bench._code="committed_progress_fresh_observation_pending"
    bench._stage=int(row.stage)
    bench._action=row.action.duplicate(true)
    for key: String in ["serial","job"]:
        if bench._action.has(key): bench._action[key]=int(bench._action[key])
    bench._bound_pose=State.transform(row.bound_pose)
    bench._pose_bound=not row.action.is_empty()
    bench._health=float(row.health_baseline)
    bench._collision_count=int(row.collision_baseline)
    bench._scan_distance=float(row.scan_distance_m)
    bench._committed=true
    bench._receipt_count=1 # Historical count; no receipt has been emitted here.
    bench._progress_history=row.history.duplicate(true)
    bench._support_stable=0.0
    bench._wait_support_history=float(row.support_observed_seconds)
    if not row.terminal_pilot.is_empty():
        bench._restored_history=row.history.duplicate(true)
        bench._terminal_pilot=Parts.restore_pilot(bench.beneficiary,row.terminal_pilot,{})
        if bench._terminal_pilot==null: return false
        bench._phase="restored_settling"
    elif not row.departure.is_empty():
        bench._departure=restore_departure(bench.beneficiary,bench.rack,row.departure)
        if bench._departure==null: return false
        bench._phase="departing"
    bench._departure_report={"ok":true,"arrived":false,"phase":"fresh_observation_pending","source_phase":row.phase,"route_index":int(row.departure.index) if not row.departure.is_empty() else 0,"stable_seconds":0.0}
    return true

static func departure_snapshot(controller: RefCounted) -> Dictionary:
    if controller==null: return {}
    return {"version":1,"phase":controller._phase,"code":controller._code,"index":controller._index,"leg_started":controller._leg_started,"serial":controller._serial,"stable_seconds":controller._stable,"support_pose":State.pose(controller._support_pose),"support_position":State.xyz(controller._support_box.position),"support_size":State.xyz(controller._support_box.size),"health":controller._health,"collisions":controller._collisions,"pilot":Parts.pilot_snapshot(controller._pilot,{})}

static func validate_departure(row: Variant) -> bool:
    if not State.exact(row,DEPARTURE_KEYS) or row.version!=1 or row.phase not in ["lift","route","arrived","terminal_hold"] or not row.code is String or not State.integer(row.index,0,4) or not row.leg_started is bool or not State.integer(row.serial,0,9007199254740991) or not State.number(row.stable_seconds,0,1e9) or not State.pose_valid(row.support_pose) or not State.vector_valid(row.support_position,1000) or not State.vector_valid(row.support_size,10) or not State.number(row.health,.00001,100) or not State.integer(row.collisions,0,2147483647) or not Parts.validate_pilot(row.pilot): return false
    # A transformed AABB computes size by subtracting rounded endpoints. Keep
    # the same bounds tolerance as Dock._support, while refs/shape remain exact.
    if State.transform(row.support_pose)!=Transform3D(Basis.IDENTITY,Vector3(6.6,.16,6)) or not State.vec(row.support_position).is_equal_approx(Vector3(5.4,0,4.8)) or not State.vec(row.support_size).is_equal_approx(Vector3(2.4,.32,2.4)): return false
    if int(row.pilot.serial)>int(row.serial) or row.pilot.mode!="route" or not row.pilot.alignment_cargo.is_empty(): return false
    if row.phase=="lift" and (int(row.index)!=0 or int(row.serial)!=0 or row.leg_started): return false
    if row.phase=="route" and (int(row.index)<1 or int(row.index)>3): return false
    if row.phase in ["arrived","terminal_hold"] and (int(row.index)!=4 or row.leg_started or State.vec(row.pilot.target)!=Departure.ROUTE[-1]): return false
    if row.phase=="route" and row.leg_started and State.vec(row.pilot.target)!=Departure.ROUTE[int(row.index)]: return false
    return true

static func restore_departure(body: State.Flight, rack: StaticBody3D, row: Dictionary) -> RefCounted:
    if not body.freeze or not validate_departure(row): return null
    var proof: Dictionary=Departure.Dock._support(rack)
    if not proof.ok or rack.global_transform!=State.transform(row.support_pose) or not proof.bounds.is_equal_approx(AABB(State.vec(row.support_position),State.vec(row.support_size))): return null
    var controller=Departure.new()
    controller._body=weakref(body)
    controller._support=weakref(rack)
    controller._support_pose=rack.global_transform
    controller._support_box=proof.bounds
    controller._space=body.get_world_3d().space
    controller._pilot=Parts.restore_pilot(body,row.pilot,{})
    if controller._pilot==null: return null
    controller._phase="terminal_hold" if row.phase=="arrived" else str(row.phase)
    controller._code="original_departure_fresh_observation_pending"
    controller._index=int(row.index)
    controller._leg_started=bool(row.leg_started)
    controller._serial=int(row.serial)
    controller._stable=0.0
    controller._health=float(row.health)
    controller._collisions=int(row.collisions)
    return controller

static func inspect_commit(bench: Node3D) -> Dictionary:
    if not bench._configured or bench._closed or not bench._authority or not bench._live() or bench._committed or bench._receipt_count!=0 or bench._phase!="commit" or bench._stage!=4 or not bench._pose_bound or not bench._tools_synchronized(): return _bad("commit_live_identity_or_tools")
    var samples: Array=[]
    var frame: int=Engine.get_physics_frames()
    if bench._scan_restore_pending:
        # In-progress NEW rays are incomplete current observations. A second
        # save retains the whole original historical prefix, never relabels it.
        samples=bench._scan_sources.duplicate(true)
    else:
        for index in bench._measurements.size():
            var sample: Dictionary=bench._scan_measurement(bench._measurements[index])
            if sample.is_empty(): return _bad("commit_actual_measurement")
            sample["source_observation"]={}
            if index<bench._scan_sources.size():
                var previous: Dictionary=bench._scan_sources[index]
                sample.source_observation=previous.get("source_observation",{}).duplicate(true)
                if sample.source_observation.is_empty():
                    sample.source_observation=previous.duplicate(true)
                    sample.source_observation.erase("source_observation")
            samples.append(sample)
    for sample: Dictionary in samples: frame=maxi(frame,int(sample.frame))
    var tools: Array=[]
    for part: AnimatableBody3D in bench._moving:
        tools.append({"pose":State.pose(part.global_transform),"size":State.xyz((part.get_child(0).shape as BoxShape3D).size)})
    var row: Dictionary={"version":4,"phase":"commit","charge":bench._charge,"charge_serial":bench._charge_serial,"beneficiary":State.capture_progress(bench.beneficiary,History.BENEFICIARY_ID),"support_observed_seconds":bench._support_stable,"source_frame":frame,"action":bench._action.duplicate(true),"stage":4,"tool":State.xyz(bench.head.global_position),"tools":tools,"scan_distance_m":bench._scan_distance,"bound_pose":State.pose(bench._bound_pose),"health_baseline":bench._health,"collision_baseline":bench._collision_count,"measurements":samples}
    var checked: Dictionary=validate_commit(row,bench._rules.snapshot(),bench.get_script())
    return {"ok":true,"snapshot":row} if checked.ok else {"ok":false,"code":checked.code,"candidate":row}

static func validate_commit(row: Variant, rules: Dictionary, bench_script: Script) -> Dictionary:
    if not State.exact(row,COMMIT_KEYS) or row.version!=4 or row.phase!="commit" or not State.integer(row.stage,4,4) or not State.number(row.charge,0,100) or not State.integer(row.charge_serial,1,2147483647) or not State.number(row.support_observed_seconds,0,1e9) or not State.integer(row.source_frame,1,9007199254740991): return _bad("progress_commit_schema")
    if not State.validate_progress(row.beneficiary,History.BENEFICIARY_ID) or not State.pose_valid(row.bound_pose) or row.beneficiary.health!=row.health_baseline or row.beneficiary.wait.collision_count!=row.collision_baseline or not State.number(row.health_baseline,.00001,100) or not State.integer(row.collision_baseline,0,2147483647): return _bad("progress_commit_flight")
    if int(rules.get("jobs_completed",-1))!=0 or int(rules.get("service_credit",-1))!=0 or not State.exact(row.action,Rules.ACTION_KEYS) or not Rules._same(row.action,rules.pending_action) or row.action.kind!="work": return _bad("progress_commit_original_pending")
    if not State.number(row.scan_distance_m,1.39999,1.40001) or not State.vector_valid(row.tool,1000) or State.vec(row.tool)!=bench_script.PARK: return _bad("progress_commit_endpoint_distance")
    var bound: Transform3D=State.transform(row.bound_pose)
    var actual: Transform3D=State.transform(row.beneficiary.pose)
    if bound.origin.distance_to(Vector3(6.6,.56,6))>.08 or bound.basis.y.dot(Vector3.UP)<.985 or actual.origin.distance_to(bound.origin)>.08 or actual.basis.y.dot(bound.basis.y)<.985: return _bad("progress_commit_original_support_pose")
    if not row.measurements is Array or row.measurements.size()!=3: return _bad("progress_commit_three_endpoints")
    var previous: int=0
    for index in 3:
        var sample: Variant=row.measurements[index]
        if not State.exact(sample,["stage","frame","tool","hit","gap_m","bounds_position","bounds_size","source_observation"]) or not sample.source_observation is Dictionary: return _bad("progress_commit_measurement_keys")
        var current: Dictionary=sample.duplicate(true)
        current.erase("source_observation")
        if not bench_script._valid_scan_measurement(current,index,bound,int(row.source_frame)) or int(sample.frame)<=previous: return _bad("progress_commit_endpoint_history")
        if not sample.source_observation.is_empty() and not bench_script._valid_scan_measurement(sample.source_observation,index,bound,9007199254740991): return _bad("progress_commit_endpoint_source")
        previous=int(sample.frame)
    var boxes: Array[AABB]=bench_script._tool_boxes(bench_script.PARK)
    if not row.tools is Array or row.tools.size()!=4: return _bad("progress_commit_tool_registry")
    for index in 4:
        var tool: Variant=row.tools[index]
        if not State.exact(tool,["pose","size"]) or not State.pose_valid(tool.pose) or not State.vector_valid(tool.size,10) or State.transform(tool.pose)!=Transform3D(Basis.IDENTITY,boxes[index].get_center()) or State.vec(tool.size)!=boxes[index].size: return _bad("progress_commit_tool_pose")
    return {"ok":true,"code":"valid_pre_receipt_commit_original_three_endpoints"}

static func apply_commit(bench: Node3D, row: Dictionary) -> bool:
    bench._phase="commit"
    bench._code="original_commit_fresh_rays_pending"
    bench._stage=4
    bench._action=row.action.duplicate(true)
    for key: String in ["serial","job"]: bench._action[key]=int(bench._action[key])
    bench._work_cargo=bench._cargos[str(row.action.cassette_id)]
    bench._bound_pose=State.transform(row.bound_pose)
    bench._pose_bound=true
    bench._health=float(row.health_baseline)
    bench._collision_count=int(row.collision_baseline)
    bench._scan_distance=float(row.scan_distance_m)
    bench._scan_sources=row.measurements.duplicate(true)
    bench._support_stable=0.0
    bench._scan_restore_pending=true
    return true

static func _history(bench: Node3D) -> Dictionary:
    if not bench._progress_history.is_empty(): return bench._progress_history.duplicate(true)
    if not bench._restored_history.is_empty(): return bench._restored_history.duplicate(true)
    var evidence: Dictionary=bench._receipt
    var receipt: Dictionary=evidence.get("receipt",{})
    if not State.exact(receipt,Rules.RECEIPT_KEYS) or bench._measurements!=evidence.get("measurements"): return {}
    for key: String in ["path_clear","endpoint_valid","custody_verified","completed"]:
        if receipt[key]!=true: return {}
    var action: Dictionary={}
    for key: String in History.MATCH_KEYS: action[key]=receipt[key]
    var measurements: Array=[]
    for measured: Dictionary in bench._measurements:
        if not measured.get("ok",false) or measured.get("body_id")!=bench.beneficiary.get_instance_id(): return {}
        measurements.append(bench._scan_measurement(measured))
    return {"source_frame":Engine.get_physics_frames(),"first_work":{"action":action,"beneficiary_id":History.BENEFICIARY_ID,"frame":evidence.physics_frame,"scan_distance_m":bench._scan_distance,"measurements":measurements,"beneficiary_pose":State.pose(evidence.beneficiary_pose)},"first_departure":{"beneficiary_id":History.BENEFICIARY_ID,"work_serial":action.serial,"route_end":State.xyz(Departure.ROUTE[-1])}}

static func _bad(code: String) -> Dictionary:
    return {"ok":false,"code":code}
