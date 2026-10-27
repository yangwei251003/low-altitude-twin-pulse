extends RefCounted
## Explicit controller schema, never an object graph/another persistence store.
const State=preload("res://scripts/v3/gameplay/canal/canal_checkpoint/flight_state.gd")
const Pilot=preload("res://scripts/v3/gameplay/canal/canal_transport_physics/transport_pilot.gd")
const Dock=preload("res://scripts/v3/gameplay/canal/canal_transport_physics/dock_lift.gd")
const Executor=preload("res://scripts/v3/gameplay/canal/canal_transport_executor/canal_transport_executor.gd")
const Rules=Executor.Rules
const EXECUTOR_FIELDS=["_phase","_code","_serial","_action","_departure","_path_index","_leg_started","_path_complete","_release_y","_released","_alignment_seconds","_blocked_seconds","_active_ticks","_receipt_count","_initial_health","_initial_collisions","_restored_hold_only","_waiting_for_beneficiary"]

static func same(a: Variant, b: Variant) -> bool:
    if a is int or a is float:
        return (b is int or b is float) and is_finite(float(a)) and is_finite(float(b)) and float(a)==float(b)
    if a is Dictionary and b is Dictionary:
        if a.size()!=b.size(): return false
        for key: Variant in a:
            if not b.has(key) or not same(a[key],b[key]): return false
        return true
    if a is Array and b is Array:
        if a.size()!=b.size(): return false
        for index in a.size():
            if not same(a[index],b[index]): return false
        return true
    return typeof(a)==typeof(b) and a==b

static func pilot_snapshot(pilot: RefCounted, cargos: Dictionary) -> Dictionary:
    if pilot==null: return {}
    var alignment: String=""
    if pilot.alignment_cargo!=null:
        for id: String in cargos:
            if is_same(pilot.alignment_cargo.get_ref(),cargos[id]): alignment=id
        if alignment.is_empty(): return {}
    return {"version":1,"state":str(pilot.state),"mode":str(pilot.mode),"serial":pilot.serial,"target":State.xyz(pilot.target),"settled_seconds":pilot.settled_seconds,"clear_seconds":pilot.clear_seconds,"alignment_cargo":alignment,"alignment_origin":State.xyz(pilot.alignment_origin)}

static func validate_pilot(row: Variant) -> bool:
    return State.exact(row,["version","state","mode","serial","target","settled_seconds","clear_seconds","alignment_cargo","alignment_origin"]) and row.version==1 and row.state in ["idle","traveling","arrived","blocked"] and row.mode in ["route","pickup_alignment"] and State.integer(row.serial,0,9007199254740991) and State.vector_valid(row.target,1000) and State.vector_valid(row.alignment_origin,1000) and State.number(row.settled_seconds,0,1e9) and State.number(row.clear_seconds,0,1e9) and row.alignment_cargo in ["",Rules.CASSETTES[0],Rules.CASSETTES[1]] and (row.mode!="pickup_alignment" or not row.alignment_cargo.is_empty())

static func restore_pilot(body: State.Flight, row: Dictionary, cargos: Dictionary) -> RefCounted:
    if not validate_pilot(row) or not body.freeze: return null
    var pilot=Pilot.new()
    if not pilot.bind(body): return null
    pilot.target=State.vec(row.target)
    pilot.serial=int(row.serial)
    pilot.state=str(row.state)
    pilot.mode=str(row.mode)
    # Source timers are serialized above. Fresh actual-space arrival/clearance
    # credit starts at zero and is earned by the original tick, never imported.
    pilot.settled_seconds=0.0
    pilot.clear_seconds=0.0
    pilot.alignment_origin=State.vec(row.alignment_origin)
    if not row.alignment_cargo.is_empty(): pilot.alignment_cargo=weakref(cargos[row.alignment_cargo])
    return pilot

static func executor_snapshot(executor: RefCounted, cargos: Dictionary) -> Dictionary:
    if executor==null or not executor._configured or executor._in_tick or executor._closed or executor._phase in ["fault","unconfigured","closed"]: return {}
    var row: Dictionary={"version":1,"fields":{},"path":[],"hold":{},"pilot":pilot_snapshot(executor._pilot,cargos),"dock":{},"pickup_supported_history":bool(executor._pickup_support.get("supported",false))}
    for field: String in EXECUTOR_FIELDS: row.fields[field]=executor.get(field).duplicate(true) if executor.get(field) is Dictionary else executor.get(field)
    for point: Vector3 in executor._path: row.path.append(State.xyz(point))
    if not executor._hold.is_empty():
        row.hold=executor._hold.duplicate(true)
        row.hold.target=State.xyz(executor._hold.target)
    if executor._dock!=null and executor._phase in ["approach","departure"]:
        var dock=executor._dock
        var berth_id: String=""
        for id: String in executor._berths:
            if is_same(executor._berths[id].get_ref(),dock.support): berth_id=id
        row.dock={"version":1,"berth":berth_id,"mode":str(dock.mode),"state":str(dock.state),"reason":str(dock.reason),"target":State.xyz(dock.target),"serial":dock.serial,"stable_seconds":dock.stable_seconds}
    return row

static func validate_executor(row: Variant, rules: Dictionary) -> bool:
    if not State.exact(row,["version","fields","path","hold","pilot","dock","pickup_supported_history"]) or row.version!=1 or not State.exact(row.fields,EXECUTOR_FIELDS) or not validate_pilot(row.pilot) or not row.pickup_supported_history is bool: return false
    var fields: Dictionary=row.fields
    if fields._phase not in ["idle","awaiting_external","travel","pickup_prepare","align","approach_wait","approach","release_wait","fall","commit","departure_wait","departure"] or not fields._code is String: return false
    for key: String in ["_serial","_active_ticks","_receipt_count","_initial_collisions"]:
        if not State.integer(fields[key],0,9007199254740991): return false
    for key: String in ["_leg_started","_path_complete","_released","_restored_hold_only","_waiting_for_beneficiary"]:
        if not fields[key] is bool: return false
    if not State.number(fields._alignment_seconds,0,1e9) or not State.number(fields._blocked_seconds,0,1e9) or not State.number(fields._initial_health,.00001,100) or not State.number(fields._release_y,-1000,1000): return false
    if not row.path is Array or row.path.size()>16 or not State.integer(fields._path_index,0,row.path.size()): return false
    for point: Variant in row.path:
        if not State.vector_valid(point,1000): return false
    if fields._phase=="travel" and (row.path.is_empty() or int(fields._path_index)>=row.path.size()): return false
    if not fields._action is Dictionary or not fields._departure is Dictionary or not row.hold is Dictionary or not row.dock is Dictionary: return false
    if not fields._action.is_empty():
        if not State.exact(fields._action,Rules.ACTION_KEYS): return false
        # Bench confirms after Executor's same-frame external hold. The stale
        # work identity survives until the next ORIGINAL _request tick.
        var committed_work: bool=fields._phase=="awaiting_external" and fields._action.kind=="work" and int(rules.jobs_completed)==1 and rules.pending_action.is_empty()
        if not Rules._same(fields._action,rules.pending_action) and not committed_work: return false
    if fields._phase in ["travel","pickup_prepare","align","approach_wait","approach","release_wait","fall","commit"] and fields._action.is_empty(): return false
    if fields._phase=="pickup_prepare" and (fields._action.kind!="pick" or row.pilot.mode!="route" or State.vec(row.pilot.target)!=Executor.BERTH_POINTS[str(fields._action.source)]+Vector3.UP*1.55): return false
    if not fields._departure.is_empty():
        if not State.exact(fields._departure,Rules.ACTION_KEYS) or fields._departure.kind!="pick" or fields._departure.cassette_id not in Rules.CASSETTES or fields._departure.source not in Rules.BERTHS or rules.cassettes[str(fields._departure.cassette_id)].holder!=Rules.CARRIER: return false
    if fields._phase in ["departure_wait","departure"] and fields._departure.is_empty(): return false
    if not row.hold.is_empty():
        if not State.exact(row.hold,["anchor","target","action","controller_serial"]) or not State.vector_valid(row.hold.target,1000) or row.hold.anchor!=rules.carrier_anchor or not row.hold.action is Dictionary or not State.integer(row.hold.controller_serial,1,int(fields._serial)): return false
    if not row.dock.is_empty():
        if not State.exact(row.dock,["version","berth","mode","state","reason","target","serial","stable_seconds"]) or row.dock.version!=1 or row.dock.berth not in Rules.BERTHS or row.dock.mode not in ["approach","departure"] or row.dock.state not in ["lifting","clear","approaching","ready","blocked"] or not row.dock.reason is String or not State.vector_valid(row.dock.target,1000) or not State.integer(row.dock.serial,1,int(fields._serial)) or not State.number(row.dock.stable_seconds,0,1e9): return false
    if fields._phase in ["approach","departure"] and row.dock.is_empty(): return false
    return int(row.pilot.serial)<=int(fields._serial)

static func restore_executor(context: Dictionary, row: Dictionary) -> RefCounted:
    if not validate_executor(row,context.rules.snapshot()) or not context.carrier.freeze: return null
    var executor=Executor.new()
    executor._body=weakref(context.carrier)
    executor._space=context.carrier.get_world_3d().space
    executor._custody=context.custody
    executor._rules=context.rules
    executor._environment=context.environment_query
    for id: String in context.cargos: executor._cargos[id]=weakref(context.cargos[id])
    for id: String in context.berths:
        executor._berths[id]=weakref(context.berths[id])
        executor._berth_poses[id]=context.berths[id].global_transform
    executor._pilot=restore_pilot(context.carrier,row.pilot,context.cargos)
    if executor._pilot==null: return null
    for field: String in EXECUTOR_FIELDS:
        var value: Variant=row.fields[field]
        executor.set(field,value.duplicate(true) if value is Dictionary else value)
    for field: String in ["_serial","_path_index","_active_ticks","_receipt_count","_initial_collisions"]: executor.set(field,int(row.fields[field]))
    for point: Array in row.path: executor._path.append(State.vec(point))
    executor._hold=row.hold.duplicate(true)
    if not row.hold.is_empty(): executor._hold.target=State.vec(row.hold.target)
    executor._pickup_support={"supported":row.pickup_supported_history,"source_observation_only":true}
    if not row.dock.is_empty():
        if context.carrier.cargo_items.size()!=1: return null
        var data: Dictionary=row.dock
        var item: Dictionary=context.carrier.cargo_items.values()[0]
        var dock=Dock.new()
        dock.body=context.carrier
        dock.cargo=item.body
        dock.joint=item.joint
        dock.support=context.berths[str(data.berth)]
        var shape: Dictionary=Dock._support(dock.support)
        if not shape.ok: return null
        dock.support_box=shape.bounds
        dock.target=State.vec(data.target)
        dock.serial=int(data.serial)
        dock.mode=str(data.mode)
        dock.state=str(data.state)
        dock.reason=str(data.reason)
        dock.stable_seconds=0.0
        dock.ordinary=Pilot.new()
        if not dock.ordinary.bind(context.carrier): return null
        executor._dock=dock
    executor._authority=true
    executor._configured=true
    var state: Dictionary=context.rules.snapshot()
    var physical: Dictionary=context.custody.report().cargos
    for id: String in Rules.CASSETTES:
        if physical[id].phase in ["settling","docked"] and state.cassettes[id].holder in Rules.BERTHS and physical[id].berth==state.cassettes[id].holder:
            executor._progress_contact_history[id]=str(state.cassettes[id].holder)
    return executor
