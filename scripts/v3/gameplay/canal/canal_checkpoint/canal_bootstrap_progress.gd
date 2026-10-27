extends RefCounted
## Bootstrap's own controller state. Does not invent absent Rules or equipment.
const Parts=preload("res://scripts/v3/gameplay/canal/canal_checkpoint/canal_progress_state.gd")
const State=Parts.State
const Bootstrap=preload("res://scripts/v3/gameplay/canal/canal_transport_executor/canal_transport_bootstrap.gd")
const PHASES=["initial_contacts","seating","align","lift_wait","lift","travel","verify_wait"]
const FIELDS=["_serial","_ticks","_custody_started","_alignment_seconds","_leg","_leg_started"]

static func capture(bootstrap: RefCounted) -> Dictionary:
    if bootstrap==null or not bootstrap._authority or bootstrap._closed or bootstrap._in_tick or bootstrap.phase not in PHASES: return {}
    var row: Dictionary={"version":1,"phase":str(bootstrap.phase),"code":str(bootstrap.code),"fields":{},"path":[],"pilot":{},"dock":{}}
    for field: String in FIELDS: row.fields[field]=bootstrap.get(field)
    for point: Vector3 in bootstrap._path: row.path.append(State.xyz(point))
    if bootstrap._pilot!=null: row.pilot=Parts.pilot_snapshot(bootstrap._pilot,bootstrap.cargos)
    if bootstrap.phase=="lift" and bootstrap._dock!=null:
        var dock=bootstrap._dock
        row.dock={"version":1,"berth":Bootstrap.Rules.SOUTH_0,"mode":str(dock.mode),"state":str(dock.state),"reason":str(dock.reason),"target":State.xyz(dock.target),"serial":dock.serial,"stable_seconds":dock.stable_seconds}
    return row if validate(row) else {}

static func validate(row: Variant) -> bool:
    if not State.exact(row,["version","phase","code","fields","path","pilot","dock"]) or row.version!=1 or row.phase not in PHASES or not row.code is String or not State.exact(row.fields,FIELDS) or not row.pilot is Dictionary or not row.dock is Dictionary: return false
    var fields: Dictionary=row.fields
    if not State.integer(fields._serial,0,2147483647) or not State.integer(fields._ticks,0,9007199254740991) or not fields._custody_started is bool or not fields._leg_started is bool or not State.number(fields._alignment_seconds,0,10) or not State.integer(fields._leg,0,2): return false
    if not row.path is Array or row.path.size()!=2 or not Parts.same(row.path,[State.xyz(Vector3(14.75,2.2,21)),State.xyz(Bootstrap.Executor.WAIT_POINT)]): return false
    if row.phase=="initial_contacts":
        if fields._custody_started or int(fields._ticks)>=75 or not row.pilot.is_empty() or not row.dock.is_empty() or int(fields._serial)!=0: return false
    elif not fields._custody_started: return false
    if row.phase in ["align","lift_wait","lift","travel","verify_wait"]:
        if not Parts.validate_pilot(row.pilot): return false
    elif not row.pilot.is_empty(): return false
    if row.phase=="travel" and int(fields._leg)>=2: return false
    if row.phase=="verify_wait" and int(fields._leg)!=2: return false
    if row.phase=="lift":
        var dock: Dictionary=row.dock
        if not State.exact(dock,["version","berth","mode","state","reason","target","serial","stable_seconds"]) or dock.version!=1 or dock.berth!=Bootstrap.Rules.SOUTH_0 or dock.mode!="departure" or dock.state not in ["lifting","clear","blocked"] or not dock.reason is String or not State.vector_valid(dock.target,1000) or not State.integer(dock.serial,1,int(fields._serial)) or not State.number(dock.stable_seconds,0,1e9): return false
    elif not row.dock.is_empty(): return false
    return true

static func restore(context: Dictionary, owner: Node3D, row: Dictionary) -> RefCounted:
    if not validate(row) or not is_instance_valid(owner) or not owner.is_inside_tree() or not context.carrier.freeze: return null
    var bootstrap=Bootstrap.new()
    bootstrap.carrier=context.carrier
    bootstrap.cargos=context.cargos.duplicate()
    bootstrap.berths=context.berths.duplicate()
    bootstrap.custody=context.get("custody")
    bootstrap.rules=context.get("rules")
    bootstrap._world=weakref(owner)
    bootstrap._query=context.environment_query
    bootstrap._authority=true
    bootstrap._progress_restore_contacts=true
    bootstrap.phase=str(row.phase)
    bootstrap.code=str(row.code)
    for field: String in FIELDS: bootstrap.set(field,row.fields[field])
    for field: String in ["_serial","_ticks","_leg"]: bootstrap.set(field,int(row.fields[field]))
    bootstrap._path.clear()
    for point: Array in row.path: bootstrap._path.append(State.vec(point))
    for body: Variant in context.berths.values()+[context.carrier]+context.cargos.values(): bootstrap._initial_nodes.append(weakref(body))
    if not row.pilot.is_empty():
        bootstrap._pilot=Parts.restore_pilot(context.carrier,row.pilot,context.cargos)
        if bootstrap._pilot==null: return null
    if not row.dock.is_empty():
        if context.carrier.cargo_items.size()!=1: return null
        var data: Dictionary=row.dock
        var item: Dictionary=context.carrier.cargo_items.values()[0]
        var dock=Bootstrap.Dock.new()
        dock.body=context.carrier
        dock.cargo=item.body
        dock.joint=item.joint
        dock.support=context.berths[str(data.berth)]
        var shape: Dictionary=Bootstrap.Dock._support(dock.support)
        if not shape.ok: return null
        dock.support_box=shape.bounds
        dock.target=State.vec(data.target)
        dock.serial=int(data.serial)
        dock.mode=str(data.mode)
        dock.state=str(data.state)
        dock.reason=str(data.reason)
        dock.stable_seconds=0.0
        dock.ordinary=Bootstrap.Pilot.new()
        if not dock.ordinary.bind(context.carrier): return null
        bootstrap._dock=dock
    return bootstrap
