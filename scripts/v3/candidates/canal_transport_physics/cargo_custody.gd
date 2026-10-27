extends RefCounted
## Host-only physical custody candidate. No pose/velocity writes and no Store.
## All participating carriers must be registered; direct attach/release bypasses
## this exclusive boundary and is detected, not silently repaired.
const Flight = preload("res://scripts/v2/flight_body.gd")
const VERSION := 1
const MASK := 1 | 2 | 4 | 8 | 32
const STABLE_USEC := 350000
const MAX_SERIAL := 9007199254740991
const LOAD_OFFSET := Vector3(0,-1.1,0)
const GRIP_OFFSET := Vector3(0,-.65,0)
var revision: int = 0
var last_serial: int = 0
var _authority: bool = false
var _configured: bool = false
var _paused: bool = false
var _cargos: Dictionary = {}
var _berths: Dictionary = {}
var _carriers: Dictionary = {}
var _states: Dictionary = {}
var _berth_contracts: Dictionary = {}
var _cargo_filters: Dictionary = {}
var _grip_records: Dictionary = {}
var _last_physics_frame: int = -1
var _restore_pending: Dictionary = {}
var _restore_first_frame := -1
var _restore_last_frame := -1
var _restored := false

## A settled checkpoint preserves replay counters, but never restores contacts.
func docked_snapshot() -> Dictionary:
	var saved: Dictionary = {"version":1,"revision":revision,"last_serial":last_serial,"cargos":_states.duplicate(true)}
	return saved if validate_docked_snapshot(saved).ok else {}

static func validate_docked_snapshot(saved: Variant) -> Dictionary:
	if not _save_keys(saved,["version","revision","last_serial","cargos"]): return {"ok":false,"code":"custody_keys"}
	if not _save_int(saved.version,1,1) or not _save_int(saved.revision,1,MAX_SERIAL) or not _save_int(saved.last_serial,1,MAX_SERIAL): return {"ok":false,"code":"custody_counters"}
	if not saved.cargos is Dictionary or saved.cargos.is_empty() or saved.cargos.size()>2: return {"ok":false,"code":"custody_registry"}
	var occupied: Array = []
	for id: Variant in saved.cargos:
		if not id is String or id.is_empty(): return {"ok":false,"code":"custody_id"}
		var row: Variant = saved.cargos[id]
		if not _save_keys(row,["phase","carrier","berth","serial","completed_serial","stable_usec","fault"]): return {"ok":false,"code":"custody_row"}
		if row.phase != "docked" or row.carrier != "" or row.fault != "" or not row.berth is String or row.berth.is_empty() or row.berth in occupied: return {"ok":false,"code":"custody_occupancy"}
		if not _save_int(row.serial,1,int(saved.last_serial)) or not _save_int(row.completed_serial,int(row.serial),int(row.serial)) or not _save_int(row.stable_usec,STABLE_USEC,STABLE_USEC): return {"ok":false,"code":"custody_row_counters"}
		occupied.append(row.berth)
	return {"ok":true,"code":"valid_docked_history"}

## Call once per actual physics frame on a NEW configured registry. Repeated
## calls observe 350ms real support; the old stable credit is never imported.
## All public ownership/counters stay fresh until the final atomic assignment.
func restore_docked_fresh(saved: Variant, authority: bool = true, paused: bool = false) -> Dictionary:
	if not _configured or not _authority or not authority: return _bad("not_authority")
	if _restored or revision != 0 or last_serial != 0 or _last_physics_frame != -1: return _bad("fresh_custody_required")
	var valid: Dictionary = validate_docked_snapshot(saved)
	if not valid.ok: return valid
	if saved.cargos.size() != _states.size(): return _bad("restore_registry_mismatch")
	if paused or _paused:
		_restore_first_frame = -1
		_restore_last_frame = -1
		return _bad("restore_paused")
	var encoded: String = JSON.stringify(saved,"",true,true)
	if not _restore_pending.is_empty() and JSON.stringify(_restore_pending,"",true,true) != encoded: return _bad("restore_candidate_changed")
	for id: String in _states:
		if not saved.cargos.has(id) or not _berths.has(saved.cargos[id].berth): return _bad("restore_registry_mismatch")
		var cargo: RigidBody3D = _lookup(_cargos,id)
		var berth: StaticBody3D = _lookup(_berths,str(saved.cargos[id].berth))
		if not _integrity(id).is_empty() or cargo.freeze or not _drop_proof(cargo,berth,null).ok or not support_info(id,str(saved.cargos[id].berth)).get("supported",false):
			_restore_first_frame = -1
			_restore_last_frame = -1
			return _bad("restore_support_pending")
		for hit: Node in cargo.get_colliding_bodies():
			if hit != berth: return _bad("restore_other_contact")
	_restore_pending = saved.duplicate(true)
	var frame: int = Engine.get_physics_frames()
	if _restore_first_frame < 0 or (_restore_last_frame >= 0 and frame != _restore_last_frame and frame != _restore_last_frame+1): _restore_first_frame = frame
	_restore_last_frame = frame
	var observed: int = roundi(float(frame-_restore_first_frame)*1000000.0/float(Engine.physics_ticks_per_second))
	if observed < STABLE_USEC: return {"ok":false,"code":"restore_stability_pending","observed_usec":observed}
	var next: Dictionary = saved.cargos.duplicate(true)
	for row: Dictionary in next.values():
		for key: String in ["serial","completed_serial","stable_usec"]: row[key] = int(row[key])
	_states = next
	revision = int(saved.revision)
	last_serial = int(saved.last_serial)
	_last_physics_frame = frame
	_restored = true
	_restore_pending.clear()
	return {"ok":true,"code":"restored_docked_no_events","observed_usec":observed,"changes":[]}

static func _save_keys(value: Variant, keys: Array) -> bool:
	if not value is Dictionary or value.size() != keys.size(): return false
	for key: Variant in value:
		if not key is String or key not in keys: return false
	return true

static func _save_int(value: Variant, low: int, high: int) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and float(value) == floor(float(value)) and float(value)>=low and float(value)<=high

func configure(cargo_nodes: Dictionary, berth_nodes: Dictionary, carrier_nodes: Dictionary, authority: bool = true) -> Dictionary:
	if _configured: return _bad("already_configured")
	if cargo_nodes.is_empty() or cargo_nodes.size() > 2 or berth_nodes.is_empty() or berth_nodes.size() > 4 or carrier_nodes.is_empty() or carrier_nodes.size() > 3:
		return _bad("registry_bounds")
	var seen: Dictionary = {}
	var space := RID()
	for group: Dictionary in [cargo_nodes,berth_nodes,carrier_nodes]:
		for key: Variant in group:
			if not key is String or key.is_empty() or key.length() > 80: return _bad("invalid_id")
			var value: Variant = group[key]
			if not value is PhysicsBody3D or not is_instance_valid(value) or not value.is_inside_tree(): return _bad("invalid_body")
			if seen.has(value.get_instance_id()): return _bad("duplicate_body")
			seen[value.get_instance_id()] = true
			if not space.is_valid(): space = value.get_world_3d().space
			if space != value.get_world_3d().space or _box_info(value).is_empty(): return _bad("space_or_envelope")
	for value: Variant in cargo_nodes.values():
		if not value is RigidBody3D or value is Flight or absf(value.mass-2.0) > .00001 or not value.contact_monitor or value.max_contacts_reported < 4 or value.collision_layer != 8 or (value.collision_mask & MASK) != MASK:
			return _bad("cargo_contract")
	for value: Variant in berth_nodes.values():
		if not value is StaticBody3D or not _berth_valid(value): return _bad("berth_contract")
	for value: Variant in carrier_nodes.values():
		if not value is Flight or value.stats.is_empty() or not value.cargo_items.is_empty(): return _bad("carrier_contract")
	for key: String in cargo_nodes:
		_cargos[key] = weakref(cargo_nodes[key])
		_cargo_filters[key] = {"layer":cargo_nodes[key].collision_layer,"mask":cargo_nodes[key].collision_mask}
		_states[key] = {"phase":"free","carrier":"","berth":"","serial":0,"completed_serial":0,"stable_usec":0,"fault":""}
	for key: String in berth_nodes:
		_berths[key] = weakref(berth_nodes[key])
		var box: Dictionary = _box_info(berth_nodes[key])
		_berth_contracts[key] = {"rid":berth_nodes[key].get_rid(),"transform":box.transform,"size":box.shape.size}
	for key: String in carrier_nodes: _carriers[key] = weakref(carrier_nodes[key])
	_authority = authority
	_configured = true
	return _ok()

func set_paused(value: bool, host_authority: bool = true) -> Dictionary:
	if not _configured or not _authority or not host_authority: return _bad("not_authority")
	if _paused != value:
		_paused = value
		revision += 1
	return _ok()

func seat(cargo_id: String, berth_id: String, serial: int, expected_revision: int) -> Dictionary:
	var check: Dictionary = _request(cargo_id,serial,expected_revision)
	if not check.ok: return check
	var state: Dictionary = _states[cargo_id]
	if state.phase != "free": return _bad("not_free")
	if not _berths.has(berth_id): return _bad("unknown_berth")
	if not _same_berth(berth_id): return _bad("berth_lost_or_changed")
	if _occupied(berth_id,cargo_id): return _bad("berth_occupied")
	var cargo: RigidBody3D = _lookup(_cargos,cargo_id)
	var berth: StaticBody3D = _lookup(_berths,berth_id)
	var proof: Dictionary = _drop_proof(cargo,berth,null)
	if not proof.ok: return proof
	state.phase = "settling"
	state.berth = berth_id
	state.serial = serial
	_accept(serial)
	return _ok()

func pickup(cargo_id: String, carrier_id: String, serial: int, expected_revision: int) -> Dictionary:
	var check: Dictionary = _request(cargo_id,serial,expected_revision)
	if not check.ok: return check
	var state: Dictionary = _states[cargo_id]
	if state.phase != "docked": return _bad("not_docked")
	var cargo: RigidBody3D = _lookup(_cargos,cargo_id)
	var carrier: Flight = _lookup(_carriers,carrier_id)
	if not _live(carrier) or not carrier.enabled: return _bad("carrier_unavailable")
	if not carrier.cargo_items.is_empty() or _carrier_reserved(carrier_id): return _bad("carrier_occupied")
	var support: Dictionary = support_info(cargo_id,str(state.berth))
	if not support.get("supported",false): return _bad("support_lost")
	if not _slow(cargo,carrier): return _bad("moving_too_fast")
	if cargo.global_position.distance_to(carrier.global_position+LOAD_OFFSET) > .18: return _bad("grip_too_far")
	var exclude: Array[RID] = [cargo.get_rid(),carrier.get_rid()]
	var ray := PhysicsRayQueryParameters3D.create(carrier.global_position+GRIP_OFFSET,cargo.global_position,MASK,exclude)
	if not cargo.get_world_3d().direct_space_state.intersect_ray(ray).is_empty(): return _bad("grip_obstructed")
	# Existing FlightBody creates the actual PinJoint at the current physical pose.
	# It does not move cargo, but also does not enforce these custody preconditions.
	if not carrier.attach_cargo(cargo,cargo_id,2.0): return _bad("flight_attach_rejected")
	var joint: PinJoint3D = carrier.cargo_items[cargo_id].joint
	# Capture the true local anchors at joint creation. The Joint3D node itself
	# does not follow the two moving bodies, so reading its later world position
	# would not prove the load's physical attachment point.
	_grip_records[cargo_id] = {"carrier_id":carrier_id,"serial":serial,
		"carrier_local":carrier.to_local(joint.global_position),"cargo_local":cargo.to_local(joint.global_position),
		"pickup_offset":cargo.global_position-(carrier.global_position+LOAD_OFFSET),
		"pickup_cargo_basis":cargo.global_basis,"pickup_up_dot":cargo.global_basis.y.dot(Vector3.UP)}
	# Flight.attach narrows the load mask to terrain. Keep the registered physical
	# filter so OTHER players/loads still collide; the PinJoint excludes its own
	# attached carrier pair. No additional collision exception is installed.
	cargo.collision_layer = int(_cargo_filters[cargo_id].layer)
	cargo.collision_mask = int(_cargo_filters[cargo_id].mask)
	state.phase = "carried"
	state.carrier = carrier_id
	state.berth = ""
	state.stable_usec = 0
	state.serial = serial
	_accept(serial)
	var result: Dictionary = _ok()
	result.grip = grip_info(cargo_id)
	return result

func release_to(cargo_id: String, berth_id: String, serial: int, expected_revision: int) -> Dictionary:
	var check: Dictionary = _request(cargo_id,serial,expected_revision)
	if not check.ok: return check
	var state: Dictionary = _states[cargo_id]
	if state.phase != "carried": return _bad("not_carried")
	if not _berths.has(berth_id): return _bad("unknown_berth")
	if not _same_berth(berth_id): return _bad("berth_lost_or_changed")
	if _occupied(berth_id,cargo_id): return _bad("berth_occupied")
	var cargo: RigidBody3D = _lookup(_cargos,cargo_id)
	var carrier: Flight = _lookup(_carriers,str(state.carrier))
	if not is_instance_valid(carrier) or not carrier.enabled: return _bad("carrier_unavailable")
	var proof: Dictionary = _drop_proof(cargo,_lookup(_berths,berth_id),carrier)
	if not proof.ok: return proof
	var item: Dictionary = carrier.cargo_items[cargo_id]
	var joint: PinJoint3D = item.joint
	# release_cargo only queue_frees. Destroy the verified joint synchronously,
	# then let the unchanged FlightBody clear its mass/list exactly once. No
	# physics callback/await or alternate attachment can intervene in this call.
	joint.free()
	var released: RigidBody3D = carrier.release_cargo(cargo_id)
	state.phase = "dropping"
	state.carrier = ""
	state.berth = berth_id # reservation, NOT ownership by the berth yet
	state.stable_usec = 0
	state.serial = serial
	_accept(serial)
	if released != cargo:
		_fault(state,"release_contract_broken")
		return _bad("release_contract_broken")
	return _ok()

func step(delta: float, host_authority: bool = true, paused: bool = false) -> Dictionary:
	if not _configured or not _authority or not host_authority: return _bad("not_authority")
	if not _restore_pending.is_empty(): return _bad("restore_in_progress")
	if not is_finite(delta) or delta < 0.0 or delta > .1: return _bad("invalid_delta")
	if paused or _paused or delta == 0.0: return _ok()
	var physics_frame: int = Engine.get_physics_frames()
	if physics_frame == _last_physics_frame: return _bad("same_physics_frame")
	var missed_sample: bool = _last_physics_frame >= 0 and physics_frame > _last_physics_frame+1
	_last_physics_frame = physics_frame
	# One current contact observation proves at most one real physics interval.
	# Missed frames and large caller deltas cannot create unobserved stability.
	var increment: int = mini(roundi(delta*1000000.0),roundi(1000000.0/float(Engine.physics_ticks_per_second)))
	var changes: Array = []
	for cargo_id: String in _states:
		var state: Dictionary = _states[cargo_id]
		if state.phase == "fault": continue
		var fault: String = _integrity(cargo_id)
		if not fault.is_empty():
			_fault(state,fault)
			changes.append({"cargo_id":cargo_id,"phase":"fault","code":fault})
			continue
		if state.phase in ["settling","dropping","docked"]:
			var proof: Dictionary = support_info(cargo_id,str(state.berth))
			var previous: int = int(state.stable_usec)
			var observed: int = 0 if missed_sample and state.phase != "docked" else previous
			state.stable_usec = mini(STABLE_USEC,observed+increment) if proof.get("supported",false) else 0
			if state.phase == "docked" and not proof.get("supported",false):
				state.phase = "settling" # keep reservation; never manufacture support
				revision += 1
				changes.append({"cargo_id":cargo_id,"phase":"settling","code":"support_lost"})
			elif state.phase != "docked" and int(state.stable_usec) >= STABLE_USEC:
				state.phase = "docked"
				revision += 1
				if state.completed_serial != state.serial:
					state.completed_serial = state.serial
					changes.append({"cargo_id":cargo_id,"phase":"docked","serial":state.serial})
			if previous != int(state.stable_usec): revision += 1
	return {"ok":true,"code":"ok","revision":revision,"changes":changes}

func support_info(cargo_id: String, berth_id: String) -> Dictionary:
	var cargo: RigidBody3D = _lookup(_cargos,cargo_id)
	var berth: StaticBody3D = _lookup(_berths,berth_id)
	if not _live(cargo) or not _same_berth(berth_id): return {"supported":false,"code":"missing_body"}
	var c: Dictionary = _box_info(cargo)
	var b: Dictionary = _box_info(berth)
	if c.is_empty() or b.is_empty(): return {"supported":false,"code":"invalid_envelope"}
	var cb: AABB = c.bounds
	var bb: AABB = b.bounds
	var gap: float = cb.position.y-bb.end.y
	var touches: bool = cargo.get_colliding_bodies().has(berth)
	var coverage: bool = _footprint(cb,bb) and _support_rays(cargo,berth,cb)
	var supported: bool = touches and coverage and absf(gap) <= .025 and _slow(cargo,null) and cargo.global_basis.y.dot(Vector3.UP) >= .985
	return {"supported":supported,"code":"supported" if supported else "not_supported",
		"support_rid":berth.get_rid(),"cargo_rid":cargo.get_rid(),"support_bounds":bb,"cargo_bounds":cb,
		"bottom_gap_m":gap,"actual_contact":touches,"five_rays_on_support":coverage,
		"cargo_velocity":cargo.linear_velocity,"cargo_angular_velocity":cargo.angular_velocity}

func report() -> Dictionary:
	# JSON-safe logical evidence only. Deliberately not called a restorable physics
	# snapshot: a save cannot recreate a valid PinJoint or contact by setting flags.
	return {"version":VERSION,"revision":revision,"last_serial":last_serial,"authority":_authority,"paused":_paused,
		"cargos":_states.duplicate(true),"physics_restore_required":true}

func release_info(cargo_id: String, berth_id: String) -> Dictionary:
	# Read-only preflight, never a reservation or permission token. release_to
	# rechecks the same real geometry plus serial/revision before destroying joint.
	if not _configured or not _states.has(cargo_id): return _bad("unknown_cargo")
	if not _berths.has(berth_id) or not _same_berth(berth_id): return _bad("berth_lost_or_changed")
	var state: Dictionary = _states[cargo_id]
	if state.phase != "carried": return _bad("not_carried")
	if _occupied(berth_id,cargo_id): return _bad("berth_occupied")
	var integrity: String = _integrity(cargo_id)
	if not integrity.is_empty(): return _bad(integrity)
	return _drop_proof(_lookup(_cargos,cargo_id),_lookup(_berths,berth_id),_lookup(_carriers,str(state.carrier)))

func grip_info(cargo_id: String) -> Dictionary:
	if not _grip_records.has(cargo_id): return {}
	var stored: Dictionary = _grip_records[cargo_id]
	var result := {"serial":stored.serial,"carrier_local":_xyz(stored.carrier_local),"cargo_local":_xyz(stored.cargo_local),
		"pickup_offset":_xyz(stored.pickup_offset),"pickup_cargo_basis":_basis_array(stored.pickup_cargo_basis),"pickup_up_dot":stored.pickup_up_dot}
	var cargo: RigidBody3D = _lookup(_cargos,cargo_id)
	var carrier: Flight = _lookup(_carriers,str(stored.carrier_id))
	if _live(cargo) and _live(carrier) and _states[cargo_id].phase == "carried":
		var cargo_anchor: Vector3 = cargo.to_global(stored.cargo_local)
		var carrier_anchor: Vector3 = carrier.to_global(stored.carrier_local)
		result.merge({"cargo_anchor_world":_xyz(cargo_anchor),"carrier_anchor_world":_xyz(carrier_anchor),
			"anchor_error_m":cargo_anchor.distance_to(carrier_anchor),"cargo_up_dot":cargo.global_basis.y.dot(Vector3.UP)})
	return result

func _request(cargo_id: String, serial: int, expected_revision: int) -> Dictionary:
	if not _configured or not _authority: return _bad("not_authority")
	if not _restore_pending.is_empty(): return _bad("restore_in_progress")
	if _paused: return _bad("paused")
	if expected_revision != revision: return _bad("stale_revision")
	if serial <= last_serial or serial > MAX_SERIAL: return _bad("stale_serial")
	if not _states.has(cargo_id): return _bad("unknown_cargo")
	if _states[cargo_id].phase == "fault": return _bad("custody_fault")
	var fault: String = _integrity(cargo_id)
	if not fault.is_empty(): return _bad(fault)
	return _ok()

func _integrity(cargo_id: String) -> String:
	var cargo: RigidBody3D = _lookup(_cargos,cargo_id)
	var state: Dictionary = _states[cargo_id]
	if not _live(cargo): return "cargo_lost"
	if _box_info(cargo).is_empty() or absf(cargo.mass-2.0) > .00001: return "cargo_changed"
	if cargo.collision_layer != _cargo_filters[cargo_id].layer or cargo.collision_mask != _cargo_filters[cargo_id].mask: return "cargo_filter_changed"
	if not str(state.berth).is_empty() and not _same_berth(str(state.berth)): return "berth_lost_or_changed"
	var owners: Array = []
	for carrier_id: String in _carriers:
		var body: Flight = _lookup(_carriers,carrier_id)
		if not _live(body): continue
		for key: Variant in body.cargo_items:
			var item: Dictionary = body.cargo_items[key]
			if item.get("body") == cargo: owners.append({"id":carrier_id,"key":key,"joint":item.get("joint")})
	if state.phase != "carried": return "external_attachment" if not owners.is_empty() else ""
	var carrier: Flight = _lookup(_carriers,str(state.carrier))
	if not _live(carrier) or not carrier.enabled: return "carrier_lost_or_disabled"
	if owners.size() != 1 or owners[0].id != state.carrier or owners[0].key != cargo_id: return "ownership_mismatch"
	var joint: Variant = owners[0].joint
	if typeof(joint) != TYPE_OBJECT or not is_instance_valid(joint) or not joint is PinJoint3D or not joint.is_inside_tree() or joint.is_queued_for_deletion(): return "joint_lost"
	if joint.get_node_or_null(joint.node_a) != carrier or joint.get_node_or_null(joint.node_b) != cargo: return "joint_endpoints_changed"
	if carrier.get_world_3d().space != cargo.get_world_3d().space: return "space_changed"
	return ""

func _drop_proof(cargo: RigidBody3D, berth: StaticBody3D, carrier: Flight) -> Dictionary:
	if not _live(cargo) or not _berth_valid(berth): return _bad("missing_body")
	var c: Dictionary = _box_info(cargo)
	var b: Dictionary = _box_info(berth)
	if c.is_empty() or b.is_empty() or cargo.get_world_3d().space != berth.get_world_3d().space: return _bad("space_or_envelope")
	var cb: AABB = c.bounds
	var bb: AABB = b.bounds
	var gap: float = cb.position.y-bb.end.y
	var footprint: bool = _footprint(cb,bb)
	var up_dot: float = cargo.global_basis.y.dot(Vector3.UP)
	var rejected: Array[String] = []
	if not footprint: rejected.append("footprint")
	if gap < -.025: rejected.append("below_support")
	if gap > .35: rejected.append("above_release_height")
	if up_dot < .985: rejected.append("tilt")
	var diagnostic := {"bottom_gap_m":gap,"gap_min_m":-.025,"gap_max_m":.35,"footprint_inside":footprint,
		"footprint_margin_m":.03,"up_dot":up_dot,"up_dot_min":.985,"pose_rejections":rejected,
		"cargo_bounds_origin":_xyz(cb.position),"cargo_bounds_size":_xyz(cb.size),
		"support_bounds_origin":_xyz(bb.position),"support_bounds_size":_xyz(bb.size),
		"cargo_basis":_basis_array(cargo.global_basis),"cargo_velocity":_xyz(cargo.linear_velocity),
		"cargo_angular_velocity":_xyz(cargo.angular_velocity)}
	if not _slow(cargo,carrier): return _drop_result(false,"moving_too_fast",diagnostic)
	if not rejected.is_empty(): return _drop_result(false,"drop_pose_mismatch",diagnostic)
	var excluded: Array[RID] = [cargo.get_rid(),berth.get_rid()]
	if _live(carrier): excluded.append(carrier.get_rid())
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = c.shape
	query.transform = c.transform
	query.collision_mask = MASK
	query.exclude = excluded
	var space: PhysicsDirectSpaceState3D = cargo.get_world_3d().direct_space_state
	if not space.intersect_shape(query,1).is_empty(): return _drop_result(false,"drop_obstructed",diagnostic)
	query.motion = Vector3.DOWN*(maxf(0.0,gap)+.025)
	var motion: PackedFloat32Array = space.cast_motion(query)
	if motion.size() != 2 or motion[0] < 1.0: return _drop_result(false,"drop_obstructed",diagnostic)
	return _drop_result(true,"ok",diagnostic)

func _drop_result(ok: bool, code: String, diagnostic: Dictionary) -> Dictionary:
	return {"ok":ok,"code":code,"revision":revision,"diagnostic":diagnostic}

static func _xyz(v: Vector3) -> Array:
	return [v.x,v.y,v.z]

static func _basis_array(value: Basis) -> Array:
	return [_xyz(value.x),_xyz(value.y),_xyz(value.z)]

func _support_rays(cargo: RigidBody3D, berth: StaticBody3D, bounds: AABB) -> bool:
	var center: Vector3 = bounds.get_center()
	var offsets: Array[Vector2] = [Vector2.ZERO,Vector2(-.4,-.4),Vector2(.4,-.4),Vector2(-.4,.4),Vector2(.4,.4)]
	var excluded: Array[RID] = [cargo.get_rid()]
	for offset: Vector2 in offsets:
		var at := Vector3(center.x+offset.x*bounds.size.x,bounds.position.y,center.z+offset.y*bounds.size.z)
		var ray := PhysicsRayQueryParameters3D.create(at+Vector3.UP*.045,at+Vector3.DOWN*.06,MASK,excluded)
		var hit: Dictionary = cargo.get_world_3d().direct_space_state.intersect_ray(ray)
		if hit.is_empty() or hit.collider != berth: return false
	return true

func _box_info(body: PhysicsBody3D) -> Dictionary:
	if not _live(body): return {}
	var result: Dictionary = {}
	for owner: int in body.get_shape_owners():
		if body.is_shape_owner_disabled(owner): continue
		var pose: Transform3D = body.global_transform*body.shape_owner_get_transform(owner)
		for i in body.shape_owner_get_shape_count(owner):
			var shape: Shape3D = body.shape_owner_get_shape(owner,i)
			if not result.is_empty() or not shape is BoxShape3D: return {}
			var size: Vector3 = shape.size
			if not size.is_finite() or size.x <= 0 or size.y <= 0 or size.z <= 0: return {}
			if not pose.origin.is_finite() or not pose.basis.is_finite() or not pose.basis.get_scale().is_equal_approx(Vector3.ONE): return {}
			result = {"shape":shape,"transform":pose,"bounds":pose*AABB(-size*.5,size)}
	return result

func _berth_valid(body: Variant) -> bool:
	if not _live(body) or not body is StaticBody3D or (body.collision_layer & MASK) == 0: return false
	if not body.constant_linear_velocity.is_zero_approx() or not body.constant_angular_velocity.is_zero_approx(): return false
	var box: Dictionary = _box_info(body)
	return not box.is_empty() and _axis_aligned(box.transform.basis)

func _same_berth(berth_id: String) -> bool:
	var body: StaticBody3D = _lookup(_berths,berth_id)
	if not _berth_valid(body) or not _berth_contracts.has(berth_id): return false
	var box: Dictionary = _box_info(body)
	var expected: Dictionary = _berth_contracts[berth_id]
	return body.get_rid() == expected.rid and box.transform == expected.transform and box.shape.size == expected.size

func _footprint(cargo: AABB, berth: AABB) -> bool:
	return cargo.position.x >= berth.position.x+.03 and cargo.end.x <= berth.end.x-.03 and cargo.position.z >= berth.position.z+.03 and cargo.end.z <= berth.end.z-.03

func _slow(cargo: RigidBody3D, carrier: Flight) -> bool:
	if not cargo.linear_velocity.is_finite() or not cargo.angular_velocity.is_finite() or cargo.linear_velocity.length() > .12 or cargo.angular_velocity.length() > .15: return false
	return not _live(carrier) or (carrier.linear_velocity.is_finite() and carrier.angular_velocity.is_finite() and carrier.linear_velocity.length() <= .18 and carrier.angular_velocity.length() <= .15 and (carrier.linear_velocity-cargo.linear_velocity).length() <= .2)

func _occupied(berth_id: String, except_cargo: String) -> bool:
	for key: String in _states:
		if key != except_cargo and _states[key].berth == berth_id: return true
	return false

func _carrier_reserved(carrier_id: String) -> bool:
	for state: Dictionary in _states.values():
		if state.carrier == carrier_id: return true
	return false

func _lookup(registry: Dictionary, key: String) -> Variant:
	return registry[key].get_ref() if registry.has(key) else null

func _live(value: Variant) -> bool:
	return typeof(value) == TYPE_OBJECT and is_instance_valid(value) and value is PhysicsBody3D and value.is_inside_tree() and not value.is_queued_for_deletion()

func _axis_aligned(basis: Basis) -> bool:
	return basis.is_equal_approx(Basis.IDENTITY)

func _accept(serial: int) -> void:
	last_serial = serial
	revision += 1

func _fault(state: Dictionary, code: String) -> void:
	state.phase = "fault"
	state.fault = code
	state.stable_usec = 0
	revision += 1

func _ok() -> Dictionary:
	return {"ok":true,"code":"ok","revision":revision}

func _bad(code: String) -> Dictionary:
	return {"ok":false,"code":code,"revision":revision}

## One carried + one supported cassette. This is separate from docked v1.
## PhysicsServer anchors are authoritative; the Joint node's world position is
## its creation marker and does not follow its moving endpoints.
func snapshot_wait(carried_id: String, carrier_id: String, docked_id: String, berth_id: String) -> Dictionary:
	var captured: Dictionary = inspect_wait_snapshot(carried_id,carrier_id,docked_id,berth_id)
	return captured.snapshot if captured.ok else {}

## Read-only diagnostic of the same strict snapshot path; no extra sampling.
func inspect_wait_snapshot(carried_id: String, carrier_id: String, docked_id: String, berth_id: String) -> Dictionary:
	if not _configured or not _authority or _paused or not _states.has(carried_id) or not _states.has(docked_id): return {"ok":false,"code":"wait_custody_not_available"}
	for id: String in [carried_id,docked_id]:
		var issue: String = _integrity(id)
		if not issue.is_empty(): return {"ok":false,"code":"wait_custody_integrity:"+id+":"+issue}
	if not support_info(docked_id,berth_id).get("supported",false): return {"ok":false,"code":"wait_custody_actual_support"}
	var carrier: Flight=_lookup(_carriers,carrier_id)
	if not _live(carrier) or carrier.cargo_items.size()!=1 or not carrier.cargo_items.has(carried_id): return {"ok":false,"code":"wait_custody_carrier_load"}
	var cargo: RigidBody3D=_lookup(_cargos,carried_id)
	var joint: PinJoint3D=carrier.cargo_items[carried_id].joint
	if not joint.get_rid().is_valid() or not _grip_records.has(carried_id): return {"ok":false,"code":"wait_custody_joint_or_grip"}
	var grip: Dictionary=grip_info(carried_id)
	for key: String in ["cargo_anchor_world","carrier_anchor_world","anchor_error_m","cargo_up_dot"]: grip.erase(key)
	var saved: Dictionary={"version":2,"revision":revision,"last_serial":last_serial,"cargos":_states.duplicate(true),
		"joint":{"cargo_id":carried_id,"carrier_id":carrier_id,"weight":carrier.cargo_items[carried_id].weight,
		"node_pose":_save_pose(joint.global_transform),"local_a":_xyz(PhysicsServer3D.pin_joint_get_local_a(joint.get_rid())),"local_b":_xyz(PhysicsServer3D.pin_joint_get_local_b(joint.get_rid())),
		"bias":joint.get_param(PinJoint3D.PARAM_BIAS),"damping":joint.get_param(PinJoint3D.PARAM_DAMPING),"impulse_clamp":joint.get_param(PinJoint3D.PARAM_IMPULSE_CLAMP),
		"exclude_pair":joint.exclude_nodes_from_collision,"solver_priority":joint.solver_priority,"grip":grip,
		"carrier_exceptions":_save_exceptions(carrier,cargo,carried_id),"cargo_exceptions":_save_exceptions(cargo,carrier,carrier_id)}}
	var checked: Dictionary=validate_wait_snapshot(saved,carried_id,carrier_id,docked_id,berth_id)
	if not checked.ok: return {"ok":false,"code":checked.code,"candidate":saved}
	return {"ok":true,"code":"captured_wait_custody","snapshot":saved}

static func validate_wait_snapshot(saved: Variant, carried_id: String, carrier_id: String, docked_id: String, berth_id: String) -> Dictionary:
	if not _save_keys(saved,["version","revision","last_serial","cargos","joint"]) or saved.version!=2 or not _save_int(saved.revision,1,MAX_SERIAL) or not _save_int(saved.last_serial,1,MAX_SERIAL): return {"ok":false,"code":"wait_custody_keys"}
	if not _save_keys(saved.cargos,[carried_id,docked_id]): return {"ok":false,"code":"wait_custody_registry"}
	for id: String in [carried_id,docked_id]:
		var row: Variant=saved.cargos[id]
		if not _save_keys(row,["phase","carrier","berth","serial","completed_serial","stable_usec","fault"]) or row.fault!="" or not _save_int(row.serial,1,int(saved.last_serial)) or not _save_int(row.completed_serial,0,int(row.serial)): return {"ok":false,"code":"wait_custody_row"}
		if id==carried_id:
			if row.phase!="carried" or row.carrier!=carrier_id or row.berth!="" or row.stable_usec!=0 or row.completed_serial>=row.serial: return {"ok":false,"code":"wait_carried_occupancy"}
		elif row.phase!="docked" or row.carrier!="" or row.berth!=berth_id or row.stable_usec!=STABLE_USEC or row.completed_serial!=row.serial: return {"ok":false,"code":"wait_docked_occupancy"}
	var joint: Variant=saved.joint
	if not _save_keys(joint,["cargo_id","carrier_id","weight","node_pose","local_a","local_b","bias","damping","impulse_clamp","exclude_pair","solver_priority","grip","carrier_exceptions","cargo_exceptions"]): return {"ok":false,"code":"wait_joint_keys"}
	if joint.cargo_id!=carried_id or joint.carrier_id!=carrier_id or joint.weight!=2.0 or not joint.exclude_pair is bool or not _save_int(joint.solver_priority,1,8): return {"ok":false,"code":"wait_joint_identity"}
	if not _wait_vector(joint.local_a,2) or not _wait_vector(joint.local_b,2) or not _wait_pose(joint.node_pose): return {"ok":false,"code":"wait_joint_anchors"}
	for key: String in ["bias","damping","impulse_clamp"]:
		if not _wait_number(joint[key],0,1 if key=="bias" else 100): return {"ok":false,"code":"wait_joint_parameter"}
	for pair: Array in [["carrier_exceptions",carried_id],["cargo_exceptions",carrier_id]]:
		var list: Variant=joint[pair[0]]
		if not list is Array or list.size()>1 or (list.size()==1 and list[0]!=pair[1]): return {"ok":false,"code":"wait_external_collision_exception"}
	var grip: Variant=joint.grip
	if not _save_keys(grip,["serial","carrier_local","cargo_local","pickup_offset","pickup_cargo_basis","pickup_up_dot"]) or grip.serial!=saved.cargos[carried_id].serial or not _wait_vector(grip.carrier_local,2) or not _wait_vector(grip.cargo_local,2) or not _wait_vector(grip.pickup_offset,.18) or not _wait_number(grip.pickup_up_dot,.985,1.00001): return {"ok":false,"code":"wait_grip_history"}
	if not grip.pickup_cargo_basis is Array or grip.pickup_cargo_basis.size()!=3: return {"ok":false,"code":"wait_grip_basis"}
	for axis: Variant in grip.pickup_cargo_basis:
		if not _wait_vector(axis,1.00001): return {"ok":false,"code":"wait_grip_basis"}
	return {"ok":true,"code":"valid_wait_custody"}

## NEW frozen registry only. No pickup API, new serial or completion event.
## All saved bodies must already be constructed in the same real space.
func restore_wait_fresh(saved: Dictionary, carried_id: String, carrier_id: String, docked_id: String, berth_id: String, authority: bool = true) -> Dictionary:
	if not _configured or not _authority or not authority or _restored or revision!=0 or last_serial!=0 or _last_physics_frame!=-1: return _bad("fresh_wait_custody_required")
	var valid: Dictionary=validate_wait_snapshot(saved,carried_id,carrier_id,docked_id,berth_id)
	if not valid.ok: return valid
	if _cargos.size()!=2 or _carriers.size()!=1 or not _cargos.has(carried_id) or not _cargos.has(docked_id) or not _carriers.has(carrier_id) or not _same_berth(berth_id): return _bad("wait_registry_mismatch")
	var carrier: Flight=_lookup(_carriers,carrier_id)
	var cargo: RigidBody3D=_lookup(_cargos,carried_id)
	if not carrier.freeze or not carrier.cargo_items.is_empty() or carrier.cargo_kg!=0 or not cargo.freeze or not (_lookup(_cargos,docked_id) as RigidBody3D).freeze: return _bad("frozen_unowned_bodies_required")
	if not carrier.get_collision_exceptions().is_empty() or not cargo.get_collision_exceptions().is_empty(): return _bad("fresh_collision_filters_required")
	var data: Dictionary=saved.joint
	var local_a:=Vector3(data.local_a[0],data.local_a[1],data.local_a[2])
	var local_b:=Vector3(data.local_b[0],data.local_b[1],data.local_b[2])
	if carrier.to_global(local_a).distance_to(cargo.to_global(local_b))>.08: return _bad("saved_joint_endpoints_separated")
	var joint:=PinJoint3D.new()
	joint.name="RestoredOriginalCargoJoint"
	carrier.get_parent().add_child(joint)
	joint.global_transform=_wait_transform(data.node_pose)
	joint.node_a=joint.get_path_to(carrier)
	joint.node_b=joint.get_path_to(cargo)
	joint.exclude_nodes_from_collision=data.exclude_pair
	joint.solver_priority=int(data.solver_priority)
	joint.set_param(PinJoint3D.PARAM_BIAS,float(data.bias))
	joint.set_param(PinJoint3D.PARAM_DAMPING,float(data.damping))
	joint.set_param(PinJoint3D.PARAM_IMPULSE_CLAMP,float(data.impulse_clamp))
	joint.force_update_transform()
	# Explicit anchors overwrite the temporary node-derived initial values.
	PhysicsServer3D.pin_joint_set_local_a(joint.get_rid(),local_a)
	PhysicsServer3D.pin_joint_set_local_b(joint.get_rid(),local_b)
	if PhysicsServer3D.pin_joint_get_local_a(joint.get_rid())!=local_a or PhysicsServer3D.pin_joint_get_local_b(joint.get_rid())!=local_b:
		joint.free()
		return _bad("joint_anchor_readback")
	# Joint exclusion already restores this pair in Jolt. Adding the same pair
	# explicitly would outlive joint destruction and leave docked cargo unable
	# to collide with the carrier after a real exchange. Restore only a missing
	# pair; never discard an unrelated external exception.
	if not data.carrier_exceptions.is_empty() and not carrier.get_collision_exceptions().has(cargo): carrier.add_collision_exception_with(cargo)
	if not data.cargo_exceptions.is_empty() and not cargo.get_collision_exceptions().has(carrier): cargo.add_collision_exception_with(carrier)
	carrier.cargo_items[carried_id]={"body":cargo,"joint":joint,"weight":2.0}
	carrier.cargo_body=cargo
	carrier.cargo_joint=joint
	carrier.cargo_id=carried_id
	carrier.cargo_kg=2.0
	var g: Dictionary=data.grip
	_grip_records[carried_id]={"carrier_id":carrier_id,"serial":int(g.serial),"carrier_local":Vector3(g.carrier_local[0],g.carrier_local[1],g.carrier_local[2]),"cargo_local":Vector3(g.cargo_local[0],g.cargo_local[1],g.cargo_local[2]),"pickup_offset":Vector3(g.pickup_offset[0],g.pickup_offset[1],g.pickup_offset[2]),"pickup_cargo_basis":Basis(Vector3(g.pickup_cargo_basis[0][0],g.pickup_cargo_basis[0][1],g.pickup_cargo_basis[0][2]),Vector3(g.pickup_cargo_basis[1][0],g.pickup_cargo_basis[1][1],g.pickup_cargo_basis[1][2]),Vector3(g.pickup_cargo_basis[2][0],g.pickup_cargo_basis[2][1],g.pickup_cargo_basis[2][2])),"pickup_up_dot":float(g.pickup_up_dot)}
	_states=saved.cargos.duplicate(true)
	for row: Dictionary in _states.values():
		for key: String in ["serial","completed_serial","stable_usec"]: row[key]=int(row[key])
	revision=int(saved.revision)
	last_serial=int(saved.last_serial)
	_restored=true
	return {"ok":true,"code":"restored_wait_no_pickup_event","changes":[]}

static func _save_exceptions(body: PhysicsBody3D, other: PhysicsBody3D, id: String) -> Array:
	var result: Array=[]
	for exception: PhysicsBody3D in body.get_collision_exceptions():
		# Jolt may list the same body through both joint exclusion and an
		# explicit exception after restore. Persist identities, not backend
		# multiplicity; any different body remains an unsupported exception.
		var identity: String=id if exception==other else "unsupported_external_body"
		if not result.has(identity): result.append(identity)
	return result

static func _wait_number(value: Variant, low: float, high: float) -> bool:
	return (value is float or value is int) and is_finite(float(value)) and float(value)>=low and float(value)<=high

static func _wait_vector(value: Variant, bound: float) -> bool:
	if not value is Array or value.size()!=3: return false
	for number: Variant in value:
		if not _wait_number(number,-bound,bound): return false
	return true

static func _save_pose(t: Transform3D) -> Array:
	return [t.basis.x.x,t.basis.x.y,t.basis.x.z,t.basis.y.x,t.basis.y.y,t.basis.y.z,t.basis.z.x,t.basis.z.y,t.basis.z.z,t.origin.x,t.origin.y,t.origin.z]

static func _wait_transform(a: Array) -> Transform3D:
	return Transform3D(Basis(Vector3(a[0],a[1],a[2]),Vector3(a[3],a[4],a[5]),Vector3(a[6],a[7],a[8])),Vector3(a[9],a[10],a[11]))

static func _wait_pose(a: Variant) -> bool:
	if not a is Array or a.size()!=12: return false
	for n: Variant in a:
		if not _wait_number(n,-1000,1000): return false
	var pose: Transform3D=_wait_transform(a)
	return absf(pose.basis.determinant()-1)<.0001 and pose.basis.is_equal_approx(pose.basis.orthonormalized())

## Separate ongoing-state schema. The optional joint is read from the real
## PinJoint, and its original grip/replay identity is preserved without pickup.
func snapshot_progress() -> Dictionary:
	if not _configured or not _authority or _paused: return {}
	var joint: Dictionary={}
	for id: String in _states:
		if not _integrity(id).is_empty(): return {}
		if _states[id].phase=="carried":
			joint=_progress_joint_snapshot(id,str(_states[id].carrier))
			if joint.is_empty(): return {}
	var row: Dictionary={"version":3,"revision":revision,"last_serial":last_serial,"cargos":_states.duplicate(true),"joint":joint}
	return row if validate_progress_snapshot(row).ok else {}

static func validate_progress_snapshot(saved: Variant) -> Dictionary:
	if not _save_keys(saved,["version","revision","last_serial","cargos","joint"]) or saved.version!=3 or not _save_int(saved.revision,0,MAX_SERIAL) or not _save_int(saved.last_serial,0,MAX_SERIAL) or not saved.cargos is Dictionary or saved.cargos.size()!=2 or not saved.joint is Dictionary: return {"ok":false,"code":"progress_custody_keys"}
	var occupied: Array=[]
	var carried: Array=[]
	for id: Variant in saved.cargos:
		if not id is String or id.is_empty(): return {"ok":false,"code":"progress_custody_id"}
		var row: Variant=saved.cargos[id]
		if not _save_keys(row,["phase","carrier","berth","serial","completed_serial","stable_usec","fault"]) or row.phase not in ["free","settling","dropping","docked","carried"] or row.fault!="" or not _save_int(row.serial,0,int(saved.last_serial)) or not _save_int(row.completed_serial,0,int(row.serial)) or not _save_int(row.stable_usec,0,STABLE_USEC): return {"ok":false,"code":"progress_custody_row"}
		if row.phase=="carried":
			if row.carrier!="carrier" or row.berth!="" or row.stable_usec!=0: return {"ok":false,"code":"progress_carried_identity"}
			carried.append(id)
		elif row.phase=="free":
			if row.carrier!="" or row.berth!="" or row.stable_usec!=0: return {"ok":false,"code":"progress_free_identity"}
		else:
			if row.carrier!="" or row.berth not in ["south_0","south_1","north_work","north_buffer"] or row.berth in occupied: return {"ok":false,"code":"progress_berth_occupancy"}
			occupied.append(row.berth)
	if carried.size()>1 or (carried.is_empty()!=saved.joint.is_empty()): return {"ok":false,"code":"progress_joint_registry"}
	if not carried.is_empty():
		var id: String=carried[0]
		if not _validate_progress_joint(saved.joint,id,int(saved.cargos[id].serial)): return {"ok":false,"code":"progress_joint_or_grip"}
	return {"ok":true,"code":"valid_progress_custody_no_current_contacts"}

func restore_progress_fresh(saved: Dictionary, authority: bool=true) -> Dictionary:
	if not authority or not _configured or not _authority or _restored or revision!=0 or last_serial!=0 or _last_physics_frame!=-1: return _bad("fresh_progress_custody_required")
	var checked: Dictionary=validate_progress_snapshot(saved)
	if not checked.ok: return checked
	if saved.cargos.keys().size()!=_states.size(): return _bad("progress_custody_registry")
	for id: String in _states:
		if not saved.cargos.has(id) or not (_lookup(_cargos,id) as RigidBody3D).freeze: return _bad("progress_frozen_registry_required")
	if not saved.joint.is_empty():
		var attached: Dictionary=_restore_progress_joint_fresh(saved.joint)
		if not attached.ok: return attached
	_states=saved.cargos.duplicate(true)
	revision=int(saved.revision)
	last_serial=int(saved.last_serial)
	_restored=true
	for row: Dictionary in _states.values():
		for key: String in ["serial","completed_serial"]: row[key]=int(row[key])
		row.stable_usec=0
		if row.phase=="docked": row.phase="settling"
	return {"ok":true,"code":"restored_progress_no_receipt_no_contact_credit","changes":[]}

func _progress_joint_snapshot(id: String, carrier_id: String) -> Dictionary:
	var carrier: Flight=_lookup(_carriers,carrier_id)
	var cargo: RigidBody3D=_lookup(_cargos,id)
	if not _live(carrier) or carrier.cargo_items.size()!=1 or not carrier.cargo_items.has(id) or not _grip_records.has(id): return {}
	var joint: Variant=carrier.cargo_items[id].joint
	if not joint is PinJoint3D or not is_instance_valid(joint) or not joint.get_rid().is_valid(): return {}
	var grip: Dictionary=grip_info(id)
	for key: String in ["cargo_anchor_world","carrier_anchor_world","anchor_error_m","cargo_up_dot"]: grip.erase(key)
	return {"cargo_id":id,"carrier_id":carrier_id,"weight":carrier.cargo_items[id].weight,"node_pose":_save_pose(joint.global_transform),"local_a":_xyz(PhysicsServer3D.pin_joint_get_local_a(joint.get_rid())),"local_b":_xyz(PhysicsServer3D.pin_joint_get_local_b(joint.get_rid())),"bias":joint.get_param(PinJoint3D.PARAM_BIAS),"damping":joint.get_param(PinJoint3D.PARAM_DAMPING),"impulse_clamp":joint.get_param(PinJoint3D.PARAM_IMPULSE_CLAMP),"exclude_pair":joint.exclude_nodes_from_collision,"solver_priority":joint.solver_priority,"grip":grip,"carrier_exceptions":_save_exceptions(carrier,cargo,id),"cargo_exceptions":_save_exceptions(cargo,carrier,carrier_id)}

static func _validate_progress_joint(joint: Variant, id: String, serial: int) -> bool:
	if not _save_keys(joint,["cargo_id","carrier_id","weight","node_pose","local_a","local_b","bias","damping","impulse_clamp","exclude_pair","solver_priority","grip","carrier_exceptions","cargo_exceptions"]): return false
	if joint.cargo_id!=id or joint.carrier_id!="carrier" or joint.weight!=2.0 or not joint.exclude_pair is bool or not _save_int(joint.solver_priority,1,8) or not _wait_vector(joint.local_a,2) or not _wait_vector(joint.local_b,2) or not _wait_pose(joint.node_pose): return false
	for key: String in ["bias","damping","impulse_clamp"]:
		if not _wait_number(joint[key],0,1 if key=="bias" else 100): return false
	for pair: Array in [["carrier_exceptions",id],["cargo_exceptions","carrier"]]:
		if not joint[pair[0]] is Array or joint[pair[0]].size()>1 or (joint[pair[0]].size()==1 and joint[pair[0]][0]!=pair[1]): return false
	var grip: Variant=joint.grip
	if not _save_keys(grip,["serial","carrier_local","cargo_local","pickup_offset","pickup_cargo_basis","pickup_up_dot"]) or not _save_int(grip.serial,serial,serial) or not _wait_vector(grip.carrier_local,2) or not _wait_vector(grip.cargo_local,2) or not _wait_vector(grip.pickup_offset,.18) or not _wait_number(grip.pickup_up_dot,.985,1.00001) or not grip.pickup_cargo_basis is Array or grip.pickup_cargo_basis.size()!=3: return false
	for axis: Variant in grip.pickup_cargo_basis:
		if not _wait_vector(axis,1.00001): return false
	return true

func _restore_progress_joint_fresh(data: Dictionary) -> Dictionary:
	var id: String=str(data.cargo_id)
	var carrier: Flight=_lookup(_carriers,str(data.carrier_id))
	var cargo: RigidBody3D=_lookup(_cargos,id)
	if not _live(carrier) or not _live(cargo) or not carrier.freeze or not cargo.freeze or not carrier.cargo_items.is_empty() or carrier.cargo_kg!=0 or not carrier.get_collision_exceptions().is_empty() or not cargo.get_collision_exceptions().is_empty(): return _bad("fresh_frozen_progress_joint_required")
	var local_a:=Vector3(data.local_a[0],data.local_a[1],data.local_a[2])
	var local_b:=Vector3(data.local_b[0],data.local_b[1],data.local_b[2])
	if carrier.to_global(local_a).distance_to(cargo.to_global(local_b))>.08: return _bad("progress_joint_endpoints_separated")
	var joint:=PinJoint3D.new()
	joint.name="RestoredOriginalCargoJoint"
	carrier.get_parent().add_child(joint)
	joint.global_transform=_wait_transform(data.node_pose)
	joint.node_a=joint.get_path_to(carrier)
	joint.node_b=joint.get_path_to(cargo)
	joint.exclude_nodes_from_collision=data.exclude_pair
	joint.solver_priority=int(data.solver_priority)
	joint.set_param(PinJoint3D.PARAM_BIAS,float(data.bias))
	joint.set_param(PinJoint3D.PARAM_DAMPING,float(data.damping))
	joint.set_param(PinJoint3D.PARAM_IMPULSE_CLAMP,float(data.impulse_clamp))
	joint.force_update_transform()
	PhysicsServer3D.pin_joint_set_local_a(joint.get_rid(),local_a)
	PhysicsServer3D.pin_joint_set_local_b(joint.get_rid(),local_b)
	if PhysicsServer3D.pin_joint_get_local_a(joint.get_rid())!=local_a or PhysicsServer3D.pin_joint_get_local_b(joint.get_rid())!=local_b:
		joint.free()
		return _bad("progress_joint_anchor_readback")
	if not data.carrier_exceptions.is_empty() and not carrier.get_collision_exceptions().has(cargo): carrier.add_collision_exception_with(cargo)
	if not data.cargo_exceptions.is_empty() and not cargo.get_collision_exceptions().has(carrier): cargo.add_collision_exception_with(carrier)
	carrier.cargo_items[id]={"body":cargo,"joint":joint,"weight":2.0}
	carrier.cargo_body=cargo
	carrier.cargo_joint=joint
	carrier.cargo_id=id
	carrier.cargo_kg=2.0
	var g: Dictionary=data.grip
	_grip_records[id]={"carrier_id":str(data.carrier_id),"serial":int(g.serial),"carrier_local":Vector3(g.carrier_local[0],g.carrier_local[1],g.carrier_local[2]),"cargo_local":Vector3(g.cargo_local[0],g.cargo_local[1],g.cargo_local[2]),"pickup_offset":Vector3(g.pickup_offset[0],g.pickup_offset[1],g.pickup_offset[2]),"pickup_cargo_basis":Basis(Vector3(g.pickup_cargo_basis[0][0],g.pickup_cargo_basis[0][1],g.pickup_cargo_basis[0][2]),Vector3(g.pickup_cargo_basis[1][0],g.pickup_cargo_basis[1][1],g.pickup_cargo_basis[1][2]),Vector3(g.pickup_cargo_basis[2][0],g.pickup_cargo_basis[2][1],g.pickup_cargo_basis[2][2])),"pickup_up_dot":float(g.pickup_up_dot)}
	return {"ok":true,"code":"progress_joint_rebuilt_no_pickup"}
