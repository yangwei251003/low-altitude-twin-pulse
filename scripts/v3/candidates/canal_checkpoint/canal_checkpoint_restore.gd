extends RefCounted
## Bounded fresh candidate reconstruction. Caller owns the isolated World3D.
## No Store, elapsed-time catch-up, reward, work confirmation or existing-body
## mutation. discard() destroys only the subtree created by this instance.
const Checkpoint = preload("res://scripts/v3/candidates/canal_checkpoint/canal_checkpoint.gd")
const State = preload("res://scripts/v3/candidates/canal_checkpoint/flight_state.gd")
const Bootstrap = preload("res://scripts/v3/candidates/canal_transport_executor/canal_transport_bootstrap.gd")
const Executor = preload("res://scripts/v3/candidates/canal_transport_executor/canal_transport_executor.gd")
const Custody = preload("res://scripts/v3/candidates/canal_transport_physics/cargo_custody.gd")
const Rules = preload("res://scripts/v3/candidates/canal_service_loop/canal_service_runtime.gd")
const Bench = preload("res://scripts/v3/candidates/canal_workbench/workbench.gd")
const Cooling = preload("res://scripts/v3/candidates/canal_cooling_station/cooling_station.gd")
const Pilot = preload("res://scripts/v3/candidates/canal_transport_physics/transport_pilot.gd")
var _site: Node3D
var _world: WeakRef
var _saved: Dictionary = {}
var _context: Dictionary = {}
var _rules_baseline: Dictionary = {}
var _executor: RefCounted
var _bench: Node3D
var _cooling: Node3D
var _staging_pilot: RefCounted
var _observer: RefCounted
var _phase := "fresh"
var _code := "fresh"
var _last_frame := -1
var _authority := false
var _in_tick := false
var _last: Dictionary = {}
var _ready_frame := -1
var _observed: Dictionary = {}

func prepare(world: Node3D, saved: Dictionary, environment: Callable, authority: bool = true) -> Dictionary:
	if _phase != "fresh": return _reply(false,"fresh_restore_owner_required")
	if not authority: return _reply(false,"authority_required")
	var valid: Dictionary = Checkpoint.validate(saved)
	if not valid.ok: return _reply(false,"envelope:"+str(valid.code))
	if not is_instance_valid(world) or not world.is_inside_tree() or not environment.is_valid() or not world.global_transform.is_equal_approx(Transform3D.IDENTITY): return _reply(false,"isolated_identity_world_required")
	if world.has_node("CanalTransportCandidateSite") or world.has_node("CanalRestoredCandidateSite"): return _reply(false,"existing_candidate_site")
	var preflight: Array = []
	for id: String in Executor.BERTH_POINTS:
		var proof: Dictionary = Bootstrap._site_preflight(world,id,Executor.BERTH_POINTS[id])
		preflight.append(proof)
		if not proof.ok:
			_last = {"berths":preflight}
			return _reply(false,"restore_berth_geometry")
	_saved = saved.duplicate(true)
	_world = weakref(world)
	_authority = true
	_site = Node3D.new()
	_site.name = "CanalRestoredCandidateSite"
	world.add_child(_site)
	var berths: Dictionary = {}
	for id: String in Rules.BERTHS:
		var berth := StaticBody3D.new()
		berth.name = "CandidateBerth_"+id
		berth.collision_layer = 1
		berth.collision_mask = 0
		berth.add_child(Bootstrap._box(Vector3(2,.5,2)))
		_site.add_child(berth)
		berth.global_position = Executor.BERTH_POINTS[id]
		berths[id] = berth
	var cargos: Dictionary = {}
	for id: String in Rules.CASSETTES:
		var row: Dictionary = _saved.checkpoint.cargos[id]
		var shape := BoxShape3D.new()
		shape.size = Vector3(.4,.4,.4)
		var query := PhysicsShapeQueryParameters3D.new()
		query.shape = shape
		query.transform = State.transform(row.pose)
		query.collision_mask = Custody.MASK
		# The named support still collides physically. Exclusion is only the
		# initial overlap query; pure validation already proved its below/footprint.
		var excluded: Array[RID] = [berths[row.holder].get_rid()]
		query.exclude = excluded
		var hits: Array[Dictionary] = world.get_world_3d().direct_space_state.intersect_shape(query,8)
		if not hits.is_empty(): return _fail("restored_cargo_obstructed",{"cargo":id,"hits":_hit_paths(hits)})
		var cargo := RigidBody3D.new()
		cargo.name = id.replace(":","_")
		cargo.mass = 2.0
		cargo.can_sleep = false
		cargo.continuous_cd = true
		cargo.contact_monitor = true
		cargo.max_contacts_reported = 16
		cargo.collision_layer = 8
		cargo.collision_mask = Custody.MASK
		var material := PhysicsMaterial.new()
		material.friction = .55
		material.bounce = 0.0
		cargo.physics_material_override = material
		cargo.add_child(Bootstrap._box(Vector3(.4,.4,.4)))
		_site.add_child(cargo)
		cargo.global_transform = State.transform(row.pose)
		cargo.linear_velocity = State.vec(row.velocity)
		cargo.angular_velocity = State.vec(row.angular_velocity)
		cargos[id] = cargo
	var made: Dictionary = State.create(_site,_saved.checkpoint.carrier,Rules.CARRIER,45,environment)
	if not made.ok: return _fail(str(made.code))
	var rules = Rules.new()
	if not rules.configure().ok or not rules.restore(_saved.rules).ok: return _fail("rules_restore")
	_rules_baseline = rules.snapshot()
	var custody = Custody.new()
	var registry: Dictionary = custody.configure(cargos,berths,{Rules.CARRIER:made.body},true)
	if not registry.ok: return _fail("custody_configure",registry)
	_context = {"carrier":made.body,"cargos":cargos,"berths":berths,"custody":custody,"rules":rules,"environment_query":environment}
	_staging_pilot = Pilot.new()
	if not _staging_pilot.bind(made.body) or not _staging_pilot.probe(Vector3.ZERO).clear or not _staging_pilot.go_to(Checkpoint._anchor(str(_saved.checkpoint.carrier_anchor)),1): return _fail("carrier_initial_clearance")
	_observer = Checkpoint.new()
	_phase = "reacquire_support"
	_code = "fresh_candidate_created_not_ready"
	return report()

func tick(delta: float, authority: bool = true, paused: bool = false) -> Dictionary:
	if not _authority or not authority: return _reply(false,"authority_required")
	if _in_tick or _phase in ["fresh","fault","discarded","adopted"]: return _reply(false,"inactive_or_reentrant")
	if not is_finite(delta) or delta < 0 or delta > 1.0/60.0+.000001: return _reply(false,"physics_delta")
	if not is_instance_valid(_site) or not _site.is_inside_tree() or _world == null or not is_instance_valid(_world.get_ref()): return _fail("candidate_lost")
	if _context.rules.snapshot() != _rules_baseline: return _fail("rules_changed_during_prepare")
	if paused or delta == 0:
		_ready_frame = -1
		_observer.reset_observation()
		if _executor != null: _executor.tick(0,true,true)
		else:
			_staging_pilot.tick(1.0/60.0,true,true)
			_context.custody.restore_docked_fresh(_saved.checkpoint.custody,true,true)
		if is_instance_valid(_bench): _bench.advance(0,true,true)
		return _reply(true,"paused_no_restore_credit")
	if _last_frame == Engine.get_physics_frames(): return _reply(false,"same_physics_frame")
	_last_frame = Engine.get_physics_frames()
	_in_tick = true
	_step(delta)
	_in_tick = false
	return report()

func _step(delta: float) -> void:
	if _phase == "reacquire_support":
		var environment: Variant = _context.environment_query.call(_context.carrier.global_position)
		if not environment is Dictionary:
			_fail("staging_environment")
			return
		_context.carrier.environment_sample = environment
		var held: Dictionary = _staging_pilot.tick(delta,true,false)
		if held.get("state","") == "blocked":
			_fail("carrier_staging_blocked",held)
			return
		var supported: Dictionary = _context.custody.restore_docked_fresh(_saved.checkpoint.custody,true,false)
		_last = supported
		if not supported.ok:
			if supported.code not in ["restore_support_pending","restore_stability_pending"]: _fail("custody:"+str(supported.code),supported)
			return
		_executor = Executor.new()
		var controller: Dictionary = _executor.configure_restored(_context,true)
		if not controller.ok:
			_fail("executor:"+str(controller.code),controller)
			return
		_bench = Bench.new()
		_site.add_child(_bench)
		var work: Dictionary = _bench.configure_completed(_context,_saved,true)
		if not work.ok:
			_fail("workbench:"+str(work.code),work)
			return
		_cooling = Cooling.new()
		_site.add_child(_cooling)
		var configured: Dictionary = _cooling.configure(_context.cargos,_context.berths,_context.custody,true)
		if not configured.ok:
			_fail("cooling_configure",configured)
			return
		var restored: Dictionary = _cooling.restore_fresh(_saved.checkpoint.cooling,true)
		if not restored.ok:
			_fail("cooling_restore",restored)
			return
		_phase = "settle"
		_code = "all_entities_created_not_ready"
		return
	var flown: Dictionary = _executor.tick(delta,true,false)
	var work: Dictionary = _bench.advance(delta,true,false)
	var cooled: Dictionary = _cooling.advance(delta,true)
	if not flown.ok or not work.ok or not cooled.ok:
		_fail("reconstructed_module_fault",{"executor":flown,"workbench":work,"cooling":cooled})
		return
	var captured: Dictionary = _observer.capture(_context,_executor,_bench,_cooling,true,false)
	_last = captured.duplicate(true)
	if captured.ok:
		_observed = captured.envelope.duplicate(true)
		_ready_frame = Engine.get_physics_frames()
		_phase = "ready"
		_code = "fresh_entities_physically_ready"
	else:
		_ready_frame = -1
		_phase = "settle"
		_code = "settling:"+str(captured.code)
		if captured.code not in ["stability_pending","completed_work_and_departure_required","actual_anchor_hold_required","flight_unstable_or_changed","beneficiary_left_terminal"]:
			_fail("recapture:"+str(captured.code),captured)

## External host adopts only a currently verified candidate. This transfers
## ownership, not a Store transaction or service consumption. tick then stops.
func adopt(authority: bool = true) -> Dictionary:
	if not authority or not _authority or _in_tick or _phase != "ready" or _ready_frame != Engine.get_physics_frames(): return _reply(false,"current_ready_required")
	var checked: Dictionary = _observer.capture(_context,_executor,_bench,_cooling,true,false)
	if not checked.ok: return _reply(false,"adopt_recheck:"+str(checked.code))
	var resumed: Dictionary = _executor.resume_restored(true)
	if not resumed.ok: return resumed
	# Consumption is derived from the existing ledger, not a new saved flag. The
	# one completed beneficiary cannot produce a second service after loading.
	if int(_context.rules.snapshot().services_consumed) == 1:
		var waiting: Dictionary = _executor.wait_for_next_beneficiary(true)
		if not waiting.ok: return _fail("consumed_restore_hold:"+str(waiting.code))
	_phase = "adopted"
	return {"ok":true,"code":"adopted_no_service_or_store","site":_site,"context":_context.duplicate(),"executor":_executor,"workbench":_bench,"cooling":_cooling,"envelope":checked.envelope.duplicate(true)}

func discard() -> void:
	if _phase == "adopted": return
	if is_instance_valid(_site): _site.free()
	_context.clear()
	_executor = null
	_bench = null
	_cooling = null
	_staging_pilot = null
	_phase = "discarded"

func report() -> Dictionary:
	return {"ok":_phase not in ["fresh","fault","discarded"],"phase":_phase,"code":_code,"ready":_phase == "ready" and _ready_frame == Engine.get_physics_frames(),"detail":_last.duplicate(true),"rules_unchanged":not _context.is_empty() and _context.rules.snapshot() == _rules_baseline,"envelope":_observed.duplicate(true)}

func _reply(ok: bool, code: String) -> Dictionary:
	var result: Dictionary = report()
	result.ok = ok
	result.code = code
	return result

func _fail(code: String, detail: Dictionary = {}) -> Dictionary:
	_last = detail.duplicate(true)
	_code = code
	discard()
	_phase = "fault"
	return report()

static func _hit_paths(hits: Array[Dictionary]) -> Array:
	var result: Array = []
	for hit: Dictionary in hits:
		var body: Variant = hit.get("collider")
		result.append(str(body.get_path()) if body is Node and is_instance_valid(body) else str(body))
	return result
