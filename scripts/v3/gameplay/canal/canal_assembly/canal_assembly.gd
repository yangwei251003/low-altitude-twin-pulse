extends Node3D
## Host-owned fresh or saved-safe-point canal site inside an existing I2 World3D.
## No World/player/camera/input/UI/repository, RPC, reward or save ownership.
const Bootstrap = preload("res://scripts/v3/gameplay/canal/canal_transport_executor/canal_transport_bootstrap.gd")
const Executor = preload("res://scripts/v3/gameplay/canal/canal_transport_executor/canal_transport_executor.gd")
const Station = preload("res://scripts/v3/gameplay/canal/canal_cooling_station/cooling_station.gd")
const Workbench = preload("res://scripts/v3/gameplay/canal/canal_workbench/workbench.gd")
const RackArt = preload("res://scripts/v3/gameplay/canal/canal_calibration_art/calibration_rack_art.gd")
const CheckpointRestore = preload("res://scripts/v3/gameplay/canal/canal_checkpoint/canal_checkpoint_restore.gd")
const Checkpoint = CheckpointRestore.Checkpoint
const WaitCheckpoint = preload("res://scripts/v3/gameplay/canal/canal_checkpoint/canal_wait_checkpoint.gd")
const ScanCheckpoint = preload("res://scripts/v3/gameplay/canal/canal_checkpoint/canal_scan_checkpoint.gd")
const ScanRestore = preload("res://scripts/v3/gameplay/canal/canal_checkpoint/canal_scan_restore.gd")
const WaitRestore = preload("res://scripts/v3/gameplay/canal/canal_checkpoint/canal_wait_restore.gd")
const ProgressCheckpoint = preload("res://scripts/v3/gameplay/canal/canal_checkpoint/canal_progress_checkpoint.gd")
const ProgressRestore = preload("res://scripts/v3/gameplay/canal/canal_checkpoint/canal_progress_restore.gd")
const StartupCheckpoint = preload("res://scripts/v3/gameplay/canal/canal_checkpoint/canal_startup_checkpoint.gd")
const Runtime = Executor.Rules
const RELAY_ID := "I2:canal_cooling_relay"
const VALVE_ID := "I2:canal_cooling_valve"
const CARRIER_ID := "I2:canal_carrier"

var bootstrap = Bootstrap.new()
var executor = Executor.new()
var cooling: Station
var workbench: Workbench
var rack_art: Dictionary = {}
var _world: WeakRef
var _query: Callable
var _context: Dictionary = {}
var _waiting = Executor.Pilot.new()
var _waiting_report: Dictionary = {}
var _configured := false
var _authority := false
var _ready_for_order := false
var _ordered := false
var _paused := false
var _stopped := false
var _closed := false
var _in_advance := false
var _last_frame := -1
var _fault := ""
var _code := "unconfigured"
var _rule_seconds := 0.0
var _rule_usec := 0
var _device_serial := 0
var _handoff_count := 0
var _handoff: Dictionary = {}
var _cargo_views: Dictionary = {}
var _restorer: RefCounted
var _restore_pending := false
var _restored_mode := false
var _restore_report: Dictionary = {}
var _prepared_device_serial := 0
var _progress_adopted_frame := -1
var _bootstrap_restored := false

func configure(world: Node3D, environment_query: Callable, authority: bool = true) -> Dictionary:
    if not authority: return _reply(false,"not_authority")
    if _configured or _closed: return _reply(false,"already_configured_or_closed")
    var issue: String=_parent_issue(world,environment_query)
    if not issue.is_empty(): return _reply(false,issue)
    # The existing factory only needs a live physical host. Giving it this
    # identity child keeps ALL new bodies under this Assembly, in the same space,
    # without reparenting a live PinJoint or owning the caller's World.
    if _site_present(world): return _reply(false,"site_already_present")
    var created: Dictionary = bootstrap.create(self,environment_query,true)
    if not created.ok: return created
    _world=weakref(world)
    _query=environment_query
    _context=bootstrap.context()
    _authority=true
    _configured=true
    _add_views()
    _code="physical_bootstrap_started"
    return _reply(true,_code)

## Existing completed-safe v3 or strict un-ordered WAIT v1 site envelope.
## The external host owns the Store transaction, not this physical restorer.
## This accepts a site envelope, NOT a player/Store save
## format or a player/Store envelope. The external host retains its old World
## until a candidate in a separate caller-created World3D is physically ready.
func prepare_saved(world: Node3D, environment_query: Callable, saved: Dictionary, device_serial: Variant, authority: bool = true) -> Dictionary:
    if not authority: return _reply(false,"not_authority")
    if _configured or _closed or _restorer!=null: return _reply(false,"fresh_restore_owner_required")
    var is_wait: bool=saved.get("kind")==WaitCheckpoint.KIND
    var is_scan: bool=saved.get("kind")==ScanCheckpoint.KIND
    var is_progress: bool=saved.get("kind")==ProgressCheckpoint.KIND
    var is_startup: bool=saved.get("kind")==StartupCheckpoint.KIND
    var transient: bool=is_wait or is_scan or is_progress or is_startup
    var checked: Dictionary=StartupCheckpoint.validate(saved) if is_startup else (ProgressCheckpoint.validate(saved) if is_progress else (ScanCheckpoint.validate(saved) if is_scan else (WaitCheckpoint.validate(saved) if is_wait else Checkpoint.validate(saved))))
    if not checked.ok: return _reply(false,"saved:"+str(checked.code))
    var minimum: int=int(saved.device_serial) if transient else maxi(int(saved.checkpoint.cooling.charge_serial),int(saved.checkpoint.workbench_charge_serial))
    if not transient: minimum=maxi(minimum,int(saved.checkpoint.cooling.axis.last_serial["1"]))
    if transient and device_serial!=saved.device_serial: return _reply(false,"wait_device_serial_mismatch")
    if not Checkpoint.FlightState.integer(device_serial,minimum,2147483647): return _reply(false,"device_serial_would_replay")
    var issue: String=_parent_issue(world,environment_query)
    if not issue.is_empty(): return _reply(false,issue)
    # Never remove, freeze or replace an already present site to make room.
    if _site_present(world): return _reply(false,"site_already_present")
    var candidate: RefCounted=ProgressRestore.new() if is_progress or is_startup else (ScanRestore.new() if is_scan else (WaitRestore.new() if is_wait else CheckpointRestore.new()))
    var prepared: Dictionary=candidate.prepare(self,saved,environment_query,true)
    _restore_report=prepared.duplicate(true)
    if not prepared.ok:
        candidate.discard()
        return _reply(false,"restore_prepare:"+str(prepared.code))
    _restorer=candidate
    _world=weakref(world)
    _query=environment_query
    _authority=true
    _configured=true
    _restored_mode=true
    _restore_pending=true
    _prepared_device_serial=int(device_serial)
    _code="restore_prepared_not_adopted"
    return _reply(true,_code)

## Must be called in the exact ready physics frame; the original restorer
## re-captures actual support/anchor state before adopting. No stale ready flag.
func adopt_saved(authority: bool = true) -> Dictionary:
    if not authority or not _authority: return _reply(false,"not_authority")
    if not _restore_pending or _restorer==null or _closed or _in_advance or _paused or _stopped or not _fault.is_empty(): return _reply(false,"restore_not_available")
    if not _live_owner(): return _restore_failed("restore_owner_lost")
    _in_advance=true
    var result: Dictionary=_adopt_saved()
    _in_advance=false
    return result

func _adopt_saved() -> Dictionary:
    var adopted: Dictionary=_restorer.adopt(true)
    _restore_report=_restorer.report().duplicate(true)
    if not adopted.ok:
        if _restore_report.phase=="fault": return _restore_failed("restore_adopt:"+str(adopted.code))
        return _reply(false,"restore_adopt:"+str(adopted.code))
    _context=adopted.context
    executor=adopted.executor
    workbench=adopted.workbench
    cooling=adopted.cooling
    _device_serial=_prepared_device_serial
    _ready_for_order=bool(adopted.get("ready_for_order",true))
    _ordered=bool(adopted.get("ordered",true))
    if adopted.get("bootstrap")!=null:
        bootstrap=adopted.bootstrap
        _bootstrap_restored=true
    if not _ordered and _ready_for_order:
        _waiting=adopted.waiting
        _waiting_report=_waiting.report()
    _restore_pending=false
    if _restorer.get_script()==ProgressRestore: _progress_adopted_frame=Engine.get_physics_frames()
    # Preserve the kernel's original water/thermal clock and fractional credit.
    _rule_usec=int(_context.rules.status().elapsed_usec) if _context.get("rules")!=null else 0
    _rule_seconds=float(adopted.get("rule_seconds",float(_rule_usec)/1000000.0))
    _add_views()
    if is_instance_valid(workbench):
        rack_art=RackArt.install(workbench.rack)
        if not rack_art.ok: return _fail("restored_rack_art:"+str(rack_art.code))
    _sync_views()
    _code="saved_site_adopted_no_new_receipt"
    return _reply(true,_code)

## Cancel an unadopted candidate only. A running site requires live close/free;
## this method cannot accidentally discard an already adopted old station.
func discard_saved(authority: bool = true) -> Dictionary:
    if not authority or not _authority: return _reply(false,"not_authority")
    if _in_advance or _closed or not _restore_pending or _restorer==null: return _reply(false,"pending_restore_required")
    _in_advance=true
    _restorer.discard()
    _restore_report=_restorer.report().duplicate(true)
    _restore_pending=false
    _closed=true
    _code="restore_candidate_discarded"
    _in_advance=false
    return _reply(true,_code)

func advance(delta: float, authority: bool = true, suspended: bool = false) -> Dictionary:
    if not _authority or not authority: return _reply(false,"not_authority")
    if not _configured or _closed: return _reply(false,"unconfigured_or_closed")
    if _in_advance: return _reply(false,"reentrant_advance")
    if not is_finite(delta) or delta<0 or delta>minf(.1,1.0/float(Engine.physics_ticks_per_second)+.000001): return _reply(false,"invalid_physics_delta")
    if not _fault.is_empty(): return _reply(false,_fault)
    if _restore_pending: return _advance_restore(delta,suspended)
    if not _live_host(): return _fail("host_or_owned_node_lost")
    var stopped: bool = _paused or suspended or delta==0
    var transition: Dictionary = _set_controls_stopped(stopped)
    if not transition.ok: return _fail("pause_transition:"+str(transition.code))
    if stopped:
        _brake_controllers()
        return _reply(true,"paused_rules_and_commands_not_physics_freeze")
    if _last_frame==Engine.get_physics_frames(): return _reply(false,"same_physics_frame")
    _last_frame=Engine.get_physics_frames()
    _in_advance=true
    var result: Dictionary = _advance(delta)
    _in_advance=false
    return result

func _advance_restore(delta: float, suspended: bool) -> Dictionary:
    if not _live_owner(): return _restore_failed("restore_owner_lost")
    var stopped: bool=_paused or suspended or delta==0
    if not stopped and _last_frame==Engine.get_physics_frames(): return _reply(false,"same_physics_frame")
    if not stopped: _last_frame=Engine.get_physics_frames()
    _stopped=stopped
    _in_advance=true
    var result: Dictionary=_restorer.tick(delta,true,stopped)
    _in_advance=false
    _restore_report=result.duplicate(true)
    if not result.ok: return _restore_failed("restore_tick:"+str(result.code))
    _code="restore_paused_no_ready_credit" if stopped else ("restore_ready_not_adopted" if result.ready else "restore_preparing:"+str(result.code))
    return _reply(true,_code)

func _restore_failed(code: String) -> Dictionary:
    if _restorer!=null: _restorer.discard()
    _restore_pending=false
    _fault=code
    _code=code
    return _reply(false,code)

func _advance(delta: float) -> Dictionary:
    if not _ready_for_order:
        var boot: Dictionary=bootstrap.tick(delta,true,false)
        if not boot.ok: return _fail("bootstrap:"+str(boot.code))
        _context=bootstrap.context()
        if boot.ready:
            if not _waiting.bind(_context.carrier) or not _waiting.go_to(Executor.WAIT_POINT,1): return _fail("wait_controller_bind")
            workbench=Workbench.new()
            workbench.name="CanalWorkbench"
            add_child(workbench)
            var made: Dictionary=workbench.configure(_context,true)
            if not made.ok: return _fail("workbench:"+str(made.code))
            rack_art=RackArt.install(workbench.rack)
            if not rack_art.ok: return _fail("rack_art:"+str(rack_art.code))
            _ready_for_order=true
    elif _ordered:
        # Executor is the ONLY Custody step owner after order acceptance.
        var moved: Dictionary=executor.tick(delta,true,false)
        if not moved.ok: return _fail("executor:"+str(moved.code))
    else:
        var custody_step: Dictionary=_context.custody.step(delta,true,false)
        if not custody_step.ok: return _fail("custody:"+str(custody_step.code))
        _context.carrier.environment_sample=_query.call(_context.carrier.global_position)
        _waiting_report=_waiting.tick(delta,true,false)
        if _waiting_report.state not in ["traveling","arrived","blocked"]: return _fail("waiting_controller:"+str(_waiting_report.state))
    if cooling==null and _context.get("custody")!=null:
        cooling=Station.new()
        cooling.name="CanalCoolingStation"
        add_child(cooling)
        var installed: Dictionary=cooling.configure(_context.cargos,_context.berths,_context.custody,true)
        if not installed.ok: return _fail("cooling_configure:"+str(installed.code))
    if is_instance_valid(cooling):
        var cooled: Dictionary=cooling.advance(delta,true)
        if not cooled.ok: return _fail("cooling:"+str(cooled.code))
    if _ready_for_order:
        # Round the accumulated active seconds once, not every 1/60s sample.
        # No wall clock, pause accrual, catch-up or independent World clock here.
        var next_seconds: float=_rule_seconds+delta
        var next_usec: int=roundi(next_seconds*1000000.0)
        var thermal: Dictionary=_context.rules.step(next_usec-_rule_usec,_cooling_facts(),true,false)
        if not thermal.ok: return _fail("rules:"+str(thermal.code))
        _rule_seconds=next_seconds
        _rule_usec=next_usec
    if is_instance_valid(workbench):
        var worked: Dictionary=workbench.advance(delta,true,false)
        if not worked.ok: return _fail("workbench:"+str(worked.code))
    _sync_views()
    _code="advanced"
    return _reply(true,_code)

## Trusted synchronous host boundary only. Caller must first resolve actual
## ownership/range/LOS/energy and stage generic Ability.commit in a private copy.
## Accept here BEFORE adopting that generic copy. This is never a client RPC.
## No actor energy/revision, cooldown, ownership lease or Store writes occur here.
func apply_authorized_ability(target_id: String, ability_id: String, mode: String = "", physics_requests: Array = [], authority: bool = true) -> Dictionary:
    if not authority or not _authority: return _reply(false,"not_authority")
    if not _configured or _closed or _restore_pending or _paused or _stopped or _in_advance or not _fault.is_empty(): return _reply(false,"not_available")
    if not _live_host(): return _fail("host_or_owned_node_lost")
    if ability_id!="push_pull" and not physics_requests.is_empty(): return _reply(false,"unexpected_physics_request")
    var result: Dictionary={"ok":false,"code":"unsupported_target_or_ability"}
    if ability_id=="heat" and target_id in Runtime.CASSETTES:
        if mode not in ["","cool"]: return _reply(false,"invalid_mode")
        if not _ready_for_order: return _reply(false,"boot_required")
        var state: Dictionary=_context.rules.snapshot()
        result=_context.rules.apply_command({"serial":int(state.command_serial)+1,"expected_revision":state.revision,"kind":"thermal","cassette_id":target_id,"delta_mc":-25000 if mode=="cool" else 25000},true,false)
    elif ability_id=="charge" and target_id in [RELAY_ID,Workbench.POWER_ID]:
        if mode not in ["","drain"]: return _reply(false,"invalid_mode")
        var amount: float=-35.0 if mode=="drain" else 35.0
        if target_id==RELAY_ID and is_instance_valid(cooling): result=cooling.apply_charge(amount,_device_serial+1,true)
        elif target_id==Workbench.POWER_ID and is_instance_valid(workbench): result=workbench.apply_charge(amount,_device_serial+1,true,false)
        if result.ok: _device_serial+=1
    elif ability_id=="push_pull" and target_id==VALVE_ID:
        if mode not in ["","pull"] or physics_requests.size()!=1 or not physics_requests[0] is Dictionary: return _reply(false,"one_resolved_impulse_required")
        var request: Dictionary=physics_requests[0]
        if request.get("type")!="impulse" or request.get("entity_id")!=VALVE_ID or not request.get("impulse") is Vector3 or not request.impulse.is_finite() or request.get("require_collision")!=true: return _reply(false,"resolved_impulse_contract")
        if is_instance_valid(cooling):
            result=cooling.apply_impulse(request.impulse,_device_serial+1,true)
            if result.ok: _device_serial+=1
    elif ability_id=="takeover" and target_id==CARRIER_ID:
        if mode!="": return _reply(false,"invalid_mode")
        if not _ready_for_order: return _reply(false,"boot_required")
        if _ordered: return _reply(false,"work_order_exists")
        result=executor.configure(_context.carrier,_context.cargos,_context.berths,_context.custody,_context.rules,_query,true)
        if result.ok: _ordered=true
    if result.ok: _sync_views()
    return result.duplicate(true)

## Static tags plus fresh physical fields. Caller initializes neutral ownership
## only once and maintains its own revisions/leases; do not reset them every tick.
func target_definitions() -> Array[Dictionary]:
    var rows: Array[Dictionary]=[]
    if not _configured or _closed or _restore_pending or not _fault.is_empty() or not _live_host(): return rows
    for id: String in Runtime.CASSETTES:
        var temperature: float=float(_context.rules.status().temperatures_c[id]) if _ready_for_order else (20.0 if id==Runtime.CASSETTES[0] else 70.0)
        rows.append(_target(id,_context.cargos[id],["thermal"],["heat"],{"temperature":temperature}))
    rows.append(_target(CARRIER_ID,_context.carrier,["mechanical","hackable"],["takeover"],{}))
    if is_instance_valid(cooling):
        rows.append(_target(RELAY_ID,cooling.relay,["conductive","electrical"],["charge"],{"charge":float(cooling.report().charge),"charge_capacity":100.0,"power_threshold":20.0}))
        rows.append(_target(VALVE_ID,cooling.valve,["movable"],["push_pull"],{}))
    if is_instance_valid(workbench):
        rows.append(_target(Workbench.POWER_ID,workbench.power_target,["conductive","electrical"],["charge"],{"charge":float(workbench.report().charge),"charge_capacity":100.0,"power_threshold":20.0}))
    return rows

func context() -> Dictionary:
    if _restore_pending: return {} # Do not hand unadopted live modules to callers.
    var result: Dictionary=_context.duplicate()
    if result.has("cargos"): result.cargos=result.cargos.duplicate()
    if result.has("berths"): result.berths=result.berths.duplicate()
    result.merge({"executor":executor,"cooling":cooling,"workbench":workbench},true)
    return result # Trusted live references, not a serializable save/network state.

func status(include_details: bool = false) -> Dictionary:
    var result: Dictionary=_reply(_configured and not _closed and _fault.is_empty(),_fault if not _fault.is_empty() else _code)
    result.merge({"last_physics_frame":_last_frame,"rule_usec":_rule_usec,"device_serial":_device_serial,"cooling_transfer_delay_count":_handoff_count,"cooling_transfer_wait":_handoff.duplicate(true),"rack_art_ok":rack_art.get("ok",false),"scope":"host_site_no_main_store_network_or_service_transaction"})
    if include_details and not is_inside_tree():
        result.details_unavailable="owner_not_in_tree"
    elif include_details:
        result.bootstrap=bootstrap.report() if not _restored_mode or _bootstrap_restored else {"phase":"not_started_saved_path"}
        result.restore=_restore_report.duplicate(true)
        result.waiting_controller=_waiting_report.duplicate(true)
        result.executor=executor.report() if _ordered else {}
        result.cooling=cooling.report() if is_instance_valid(cooling) else {}
        result.workbench=workbench.report() if is_instance_valid(workbench) else {}
        result.rules=_context.rules.snapshot() if _ready_for_order else {}
    return result

func set_paused(value: bool, authority: bool = true) -> Dictionary:
    if not _authority or not authority: return _reply(false,"not_authority")
    if not _configured or _closed or _in_advance: return _reply(false,"not_available")
    _paused=value
    if _restore_pending:
        if value: return _advance_restore(0,true)
        _stopped=false
        return _reply(true,"restore_resumed_requires_fresh_tick")
    var result: Dictionary=_set_controls_stopped(value)
    if result.ok and value: _brake_controllers()
    return result

func close(authority: bool = true) -> Dictionary:
    if not _authority or not authority: return _reply(false,"not_authority")
    if _in_advance: return _reply(false,"reentrant_close")
    if _closed: return _reply(true,"already_closed")
    if not is_inside_tree(): return _reply(false,"live_owner_required")
    if _restore_pending: return discard_saved(true)
    _set_controls_stopped(true)
    _brake_controllers()
    if _ordered: executor.close(true)
    if not _restored_mode or _bootstrap_restored: bootstrap.close(true)
    if is_instance_valid(workbench): workbench.close(true)
    _closed=true
    return _reply(true,"closed_owned_site_pending_preserved")

func _cooling_facts() -> Dictionary:
    var facts: Dictionary=cooling.facts() if is_instance_valid(cooling) else {"powered":false,"valve_open":false,"sweep_clear":false,"contacts":{Runtime.SOUTH_0:"",Runtime.SOUTH_1:""}}
    _handoff={}
    if not _ordered: return facts
    var state: Dictionary=_context.rules.snapshot()
    var physical: Dictionary=executor.report()
    var pending: Dictionary=state.pending_action
    if pending.get("kind","")!="place" or physical.phase not in ["fall","commit"] or not physical.released or not _context.carrier.cargo_items.is_empty(): return facts
    for key: String in Executor.MATCH_KEYS:
        if not physical.action.has(key) or physical.action[key]!=pending[key]: return facts
    var id: String=str(pending.cassette_id)
    var berth: String=str(pending.destination)
    if berth not in [Runtime.SOUTH_0,Runtime.SOUTH_1] or facts.contacts[berth]!=id: return facts
    if state.cassettes[id].holder!=Runtime.CARRIER or not _context.custody.support_info(id,berth).get("supported",false): return facts
    facts.contacts[berth]=""
    _handoff_count+=1
    _handoff={"cassette_id":id,"berth":berth,"pending_serial":pending.serial,"executor_phase":physical.phase,"code":"stable_contact_waiting_for_place_commit"}
    return facts

func _set_controls_stopped(value: bool) -> Dictionary:
    if _stopped==value: return _reply(true,"pause_state_unchanged")
    if is_instance_valid(cooling):
        var changed: Dictionary=cooling.set_paused(value,true)
        if not changed.ok: return changed
    if _context.get("custody")!=null:
        var changed: Dictionary=_context.custody.set_paused(value,true)
        if not changed.ok: return changed
    _stopped=value
    return _reply(true,"controls_stopped" if value else "controls_resumed")

func _brake_controllers() -> void:
    if _ordered: executor.tick(0,true,true)
    elif _ready_for_order: _waiting.tick(1.0/float(Engine.physics_ticks_per_second),true,true)
    elif _configured: bootstrap.tick(0,true,true)
    if is_instance_valid(workbench): workbench.advance(0,true,true)

func _live_owner() -> bool:
    var original: Variant=_world.get_ref() if _world!=null else null
    if not original is Node3D or not is_instance_valid(original) or not original.is_inside_tree() or original.is_queued_for_deletion() or get_parent()!=original or not global_transform.is_equal_approx(Transform3D.IDENTITY): return false
    if not _query.is_valid() or _query.get_object()!=original or original.get_world_3d().space!=get_world_3d().space: return false
    return true

func _live_host() -> bool:
    if not _live_owner(): return false
    for value: Variant in _context.get("cargos",{}).values()+_context.get("berths",{}).values()+[_context.get("carrier")]:
        if not value is PhysicsBody3D or not is_instance_valid(value) or not value.is_inside_tree() or value.is_queued_for_deletion() or not is_ancestor_of(value) or value.get_world_3d().space!=get_world_3d().space: return false
    if _ready_for_order and (not is_instance_valid(workbench) or not workbench.is_inside_tree() or not is_ancestor_of(workbench) or workbench.get_world_3d().space!=get_world_3d().space): return false
    return true

func _parent_issue(world: Node3D, environment_query: Callable) -> String:
    if not is_inside_tree() or not global_transform.is_equal_approx(Transform3D.IDENTITY): return "live_identity_assembly_required"
    if not is_instance_valid(world) or not world.is_inside_tree() or get_parent()!=world or world.get("region_id")!="I2" or not world.get("build_errors").is_empty(): return "built_i2_parent_required"
    if get_world_3d().space!=world.get_world_3d().space or not environment_query.is_valid() or environment_query.get_object()!=world: return "same_world_environment_required"
    for id: String in ["clinic","distribution","trial","shared_access"]:
        var facility: Variant=world.get(id)
        if not facility is Node3D or not is_instance_valid(facility) or not facility.is_inside_tree() or facility.get_world_3d().space!=get_world_3d().space: return "production_facility_missing:"+id
    return ""

static func _site_present(world: Node3D) -> bool:
    return not world.find_children("CanalTransportCandidateSite","Node3D",true,false).is_empty() or not world.find_children("CanalRestoredCandidateSite","Node3D",true,false).is_empty()

func _add_views() -> void:
    for berth: StaticBody3D in _context.berths.values(): _box_view(berth,"BerthSurface",Vector3(2,.5,2),Color("748888"))
    for index in 2:
        var id: String=Runtime.CASSETTES[index]
        _cargo_views[id]=_box_view(_context.cargos[id],"ThermalCartridge",Vector3(.4,.4,.4),Color("689baf") if index==0 else Color("c88450"))
        var stripe: MeshInstance3D=_box_view(_context.cargos[id],"FixedIdentityStripe",Vector3(.30,.015,.12),Color("4694ce") if index==0 else Color("e3a04c"))
        stripe.position.y=.205

func _sync_views() -> void:
    if not _ready_for_order: return
    var temperatures: Dictionary=_context.rules.status().temperatures_c
    for id: String in _cargo_views:
        var material: StandardMaterial3D=_cargo_views[id].material_override
        material.albedo_color=Color("689baf").lerp(Color("c88450"),clampf((float(temperatures[id])-20.0)/50.0,0.0,1.0))

static func _box_view(parent: Node3D, label: String, size: Vector3, color: Color) -> MeshInstance3D:
    var view:=MeshInstance3D.new()
    view.name=label
    var box:=BoxMesh.new()
    box.size=size
    view.mesh=box
    var material:=StandardMaterial3D.new()
    material.albedo_color=color
    material.roughness=.7
    view.material_override=material
    parent.add_child(view)
    return view

static func _target(id: String, body: PhysicsBody3D, tags: Array, abilities: Array, state: Dictionary) -> Dictionary:
    var physical: Dictionary=state.duplicate(true)
    physical.position=body.global_position
    return {"id":id,"body":body,"tags":tags.duplicate(),"abilities":abilities.duplicate(),"state":physical}

func _reply(ok: bool, code: String) -> Dictionary:
    var restore_ready: bool=not _closed and _authority and _restore_pending and _restorer!=null and bool(_restorer.report().ready)
    return {"ok":ok,"code":code,"configured":_configured,"ready":_ready_for_order,"ordered":_ordered,"paused":_paused or _stopped,"closed":_closed,"fatal":_fault,"restored_mode":_restored_mode,"restore_pending":_restore_pending,"restore_ready":restore_ready}

func _fail(code: String) -> Dictionary:
    _fault=code
    _brake_controllers()
    return _reply(false,code)

func _exit_tree() -> void:
    # Children have already left the tree here. Their reports may query global
    # transforms, so NEVER run close/tick/report or a physics query in this path.
    # The host calls close while the owner is live for controlled shutdown.
    # Abrupt owner removal merely revokes this facade; Godot removes its owned
    # bodies, and re-entering the same facade cannot resume stale commands.
    if not _closed: _code="owner_left_tree_without_close"
    _closed=true
    _authority=false
    _paused=true
    _stopped=true
    _in_advance=false
    _query=Callable()
    _world=null

## Called in the same host physics frame before pausing or a Store transaction.
## No stabilization credit, device step or command is produced by capture.
func capture_wait() -> Dictionary:
    if not _authority or not _configured or _closed or _restore_pending or _ordered or not _ready_for_order or _paused or _stopped or _in_advance or not _fault.is_empty() or not _live_host(): return {"ok":false,"code":"unordered_live_wait_required"}
    if _last_frame!=Engine.get_physics_frames(): return {"ok":false,"code":"current_wait_frame_required"}
    return WaitCheckpoint.capture(_context,_waiting,workbench,cooling,_device_serial,_rule_seconds,_rule_usec)


## Host requests this BEFORE asynchronous save settling. capture itself stays
## pure. WAIT retains its original synchronous boundary and needs no handshake.
func prepare_scan_capture() -> Dictionary:
    if not _authority or not _configured or _closed or _restore_pending or _paused or _stopped or _in_advance or not _fault.is_empty() or not _live_host(): return {"ok":false,"code":"live_scan_capture_host_required","ready":false}
    if not _ordered or (is_instance_valid(workbench) and workbench._phase not in Workbench.STAGES): return {"ok":true,"code":"scan_capture_not_required","ready":true,"required":false}
    return workbench.prepare_scan_capture(true)

func release_scan_capture() -> Dictionary:
    if not _authority or _in_advance: return {"ok":false,"code":"not_authority_or_reentrant"}
    if not is_instance_valid(workbench): return {"ok":true,"code":"scan_capture_already_released"}
    return workbench.release_scan_capture(true)

func capture_scan() -> Dictionary:
    if not _authority or not _configured or _closed or _restore_pending or not _ordered or not _ready_for_order or _paused or _stopped or _in_advance or not _fault.is_empty() or not _live_host(): return {"ok":false,"code":"ordered_live_scan_required"}
    if _last_frame!=Engine.get_physics_frames(): return {"ok":false,"code":"current_scan_frame_required"}
    return ScanCheckpoint.capture(_context,executor,workbench,cooling,_device_serial,_rule_seconds,_rule_usec)

func capture_active_checkpoint() -> Dictionary:
    if not _ordered:
        var wait: Dictionary=capture_wait()
        return wait if wait.ok else StartupCheckpoint.capture(self)
    if is_instance_valid(workbench) and workbench._phase in Workbench.STAGES: return capture_scan()
    return ProgressCheckpoint.capture(_context,executor,workbench,cooling,_device_serial,_rule_seconds,_rule_usec,_progress_adopted_frame==Engine.get_physics_frames())
