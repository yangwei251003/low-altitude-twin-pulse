extends Node3D
## Graybox host adapter for the separate closed 8 L cartridge cooling loop.
## The real slider, charge relay and supported cartridge decide the facts.
## Caller alone advances Runtime.step; no timers award cooling, work or service.
const Runtime = preload("res://scripts/v3/gameplay/canal/canal_service_loop/canal_service_runtime.gd")
const Axis = preload("res://scripts/v3/environment/twin_guided_axis.gd")
const MASK := 1 | 2 | 4 | 8 | 32
const VALVE_TRAVEL := 0.28
const VALVE_CLOSED := Vector3(5.8,1.18,22.5)
const RELAY_AT := Vector3(5.8,1.15,23.3)
const OPEN_POSITION := 0.25
const MAX_SERIAL := 2147483647
const SNAPSHOT_VERSION := 1
const DEVICE_ID := "I2:canal_cooling_station_0"
const SAVE_KEYS := ["version","id","layout_sha256","revision","charge","charge_serial","axis","paused","contact_observation"]
var valve: StaticBody3D
var relay: StaticBody3D
var configured := false
var revision := 0
var _axis = Axis.new()
var _custody: RefCounted
var _cargos: Dictionary = {}
var _berths: Dictionary = {}
var _authority := false
var _charge := 0.0
var _charge_serial := 0
var _last_frame := -1
var _blocked := false
var _paused := false
var _fault := ""
var _shape: BoxShape3D
var _lamp: MeshInstance3D
var _fixed: Dictionary = {}
var _used := false
var _last_contacts: Dictionary = {Runtime.SOUTH_0:"",Runtime.SOUTH_1:""}

func configure(cargos: Dictionary, berths: Dictionary, custody: RefCounted, authority: bool = true) -> Dictionary:
	if configured: return _result(false,"already_configured")
	if not is_inside_tree() or not global_transform.is_equal_approx(Transform3D.IDENTITY): return _result(false,"identity_root_required")
	if custody==null or not custody.has_method("support_info") or not custody.has_method("report"): return _result(false,"custody_required")
	if cargos.size()!=2: return _result(false,"two_cassettes_required")
	for id: String in Runtime.CASSETTES:
		var node: Variant=cargos.get(id)
		if not node is RigidBody3D or not is_instance_valid(node) or not node.is_inside_tree() or node.get_world_3d()!=get_world_3d(): return _result(false,"cargo_registry")
	for id: String in [Runtime.SOUTH_0,Runtime.SOUTH_1]:
		var node: Variant=berths.get(id)
		if not node is StaticBody3D or not is_instance_valid(node) or not node.is_inside_tree() or node.get_world_3d()!=get_world_3d(): return _result(false,"berth_registry")
	# Exact original ground/fixture space is checked before creating any solids.
	for box: Array in [[Vector3(5.8,.46,22.5),Vector3(1.2,.9,1.2)],[VALVE_CLOSED,Vector3(.4,.14,.76)],[RELAY_AT,Vector3(.4,.5,.24)]]:
		if not _placement_clear(box[0],box[1]): return _result(false,"station_space_occupied")
	var ready: Dictionary=_axis.configure(axis_config())
	if not ready.ok: return ready
	_axis.set_active_peers([1])
	_authority=authority
	_custody=custody
	for id: String in Runtime.CASSETTES: _cargos[id]=weakref(cargos[id])
	for id: String in [Runtime.SOUTH_0,Runtime.SOUTH_1]: _berths[id]=weakref(berths[id])
	var base: StaticBody3D=_solid("ClosedCoolingLoop",Vector3(5.8,.46,22.5),Vector3(1.2,.9,1.2),Color("476866"))
	valve=_solid("PhysicalBypassSlider",VALVE_CLOSED,Vector3(.4,.14,.2),Color("d7b165"))
	relay=_solid("CoolingRelay",RELAY_AT,Vector3(.4,.5,.24),Color("537a7a"))
	_shape=(valve.get_child(0) as CollisionShape3D).shape
	_lamp=_mesh("PowerLamp",Vector3(5.8,1.43,23.32),Vector3(.16,.04,.08),Color("66564c"))
	# Shallow visible rails express the actual linear axis; they are within the
	# cabinet footprint and do not add a second collider to the movable slider.
	_mesh("ValveRail",Vector3(5.8,1.08,22.64),Vector3(.12,.04,.48),Color("303e40"))
	_mesh("Closed8LCase",Vector3(5.8,.98,22.1),Vector3(.8,.12,.24),Color("8ba5a1"))
	_fixed={"base":weakref(base),"relay":weakref(relay),"base_transform":base.global_transform,"relay_transform":relay.global_transform}
	configured=true
	return _result(true,"configured_graybox")

func can_charge(delta: float, serial: int, authority: bool = true) -> Dictionary:
	var gate: Dictionary=_gate(authority)
	if not gate.ok: return gate
	if revision>=MAX_SERIAL: return _result(false,"revision_exhausted")
	if not is_finite(delta) or absf(delta)>35.0 or is_zero_approx(delta): return _result(false,"charge_range")
	if serial<=_charge_serial or serial>MAX_SERIAL: return _result(false,"charge_replay")
	return _result(true,"charge_allowed")

## Host capability adapter must validate player ownership/range/LOS/energy first.
func apply_charge(delta: float, serial: int, authority: bool = true) -> Dictionary:
	var gate: Dictionary=can_charge(delta,serial,authority)
	if not gate.ok: return gate
	_charge=clampf(_charge+delta,0.0,100.0)
	_charge_serial=serial
	_used=true
	revision+=1
	_sync_lamp()
	return _result(true,"charge_applied")

func can_impulse(impulse: Vector3, serial: int, authority: bool = true) -> Dictionary:
	var gate: Dictionary=_gate(authority)
	if not gate.ok: return gate
	if revision>=MAX_SERIAL: return _result(false,"revision_exhausted")
	if not impulse.is_finite() or impulse.length()>9.00001: return _result(false,"impulse_range")
	return _axis.can_accept(Vector3(impulse.z,0,0),1,serial)

func apply_impulse(impulse: Vector3, serial: int, authority: bool = true) -> Dictionary:
	var gate: Dictionary=can_impulse(impulse,serial,authority)
	if not gate.ok: return gate
	var result: Dictionary=_axis.apply_impulse(Vector3(impulse.z,0,0),1,serial)
	if result.ok:
		_used=true
		revision+=1
	return result

func set_paused(value: bool, authority: bool = true) -> Dictionary:
	if not configured or not _authority or not authority: return _result(false,"authority_required")
	if value!=_paused:
		if revision>=MAX_SERIAL: return _result(false,"revision_exhausted")
		_axis.stop()
		_paused=value
		_used=true
		revision+=1
	return _result(true,"paused" if value else "resumed")

func advance(delta: float, authority: bool = true) -> Dictionary:
	var gate: Dictionary=_gate(authority)
	if not gate.ok: return gate
	if not is_finite(delta) or delta<0.0 or delta>.1: return _result(false,"invalid_delta")
	if delta==0.0: return _result(true,"zero_delta")
	if revision>=MAX_SERIAL: return _result(false,"revision_exhausted")
	var frame: int=Engine.get_physics_frames()
	if frame==_last_frame: return _result(false,"same_physics_frame")
	_last_frame=frame
	var prior_axis: Dictionary=_axis.snapshot()
	var current: float=float(prior_axis.position_m)
	var expected: Vector3=VALVE_CLOSED+Vector3(0,0,current)
	if not valve.global_transform.is_equal_approx(Transform3D(Basis.IDENTITY,expected)):
		_fault="valve_pose_changed"
		return _result(false,_fault)
	var proposal: Dictionary=_axis.preview(delta)
	if not proposal.ok: return proposal
	var finish: Vector3=VALVE_CLOSED+Vector3(0,0,float(proposal.position_m))
	_blocked=not _sweep_clear(expected,finish)
	var result: Dictionary=_axis.advance(delta,_blocked)
	if not result.ok: return result
	_used=true
	if not _blocked:
		# Only this bounded, collision-approved mechanism is positioned. No cargo
		# or aircraft transform/velocity is written by the station.
		# The axis keeps integrating below is_equal_approx's 10um scalar floor.
		# Skipping those updates lets the real body drift behind the saved axis
		# until our unchanged integrity check correctly rejects the mismatch.
		# Quantize the committed axis to Vector3 every time; never widen the guard.
		valve.global_position=VALVE_CLOSED+Vector3(0,0,float(result.position_m))
		PhysicsServer3D.body_set_state(valve.get_rid(),PhysicsServer3D.BODY_STATE_TRANSFORM,valve.global_transform)
	var contacts: Dictionary=_read_contacts()
	if prior_axis!=_axis.snapshot() or contacts!=_last_contacts: revision+=1
	_last_contacts=contacts
	return _result(true,"blocked" if _blocked else "advanced")

func facts() -> Dictionary:
	var result: Dictionary={"powered":false,"valve_open":false,"sweep_clear":false,"contacts":{Runtime.SOUTH_0:"",Runtime.SOUTH_1:""}}
	if not configured or not _integrity().is_empty() or _paused or not _fault.is_empty(): return result
	result.powered=_charge>=20.0
	result.valve_open=float(_axis.snapshot().position_m)>=OPEN_POSITION
	result.sweep_clear=not _blocked and _sweep_clear(valve.global_position,valve.global_position)
	result.contacts=_read_contacts()
	return result

func _read_contacts() -> Dictionary:
	var contacts: Dictionary={Runtime.SOUTH_0:"",Runtime.SOUTH_1:""}
	var cargo_states: Dictionary=_custody.report().get("cargos",{})
	for id: String in Runtime.CASSETTES:
		var state: Dictionary=cargo_states.get(id,{})
		var berth: String=str(state.get("berth",""))
		if state.get("phase","")!="docked" or berth not in [Runtime.SOUTH_0,Runtime.SOUTH_1]: continue
		# Registry occupancy alone is insufficient: re-check actual contact now.
		if _custody.support_info(id,berth).get("supported",false): contacts[berth]=id
	return contacts

## The contact map is the previous real observation, never restored authority.
## facts() always queries current Custody + support; no saved ray hit is reused.
func snapshot() -> Dictionary:
	if not configured: return {}
	return {"version":SNAPSHOT_VERSION,"id":DEVICE_ID,"layout_sha256":layout_fingerprint(),
		"revision":revision,"charge":_charge,"charge_serial":_charge_serial,
		"axis":_axis.snapshot(),"paused":_paused,"contact_observation":_last_contacts.duplicate(true)}

static func axis_config() -> Dictionary:
	return {"travel_m":VALVE_TRAVEL,"mass_kg":2.0,"damping_per_second":2.0,"max_speed_mps":.6,"max_impulse_ns":9.0}

static func layout_fingerprint() -> String:
	return JSON.stringify({"id":DEVICE_ID,"schema":1,"base":[5.8,.46,22.5,1.2,.9,1.2],
		"valve":[5.8,1.18,22.5,.4,.14,.2],"relay":[5.8,1.15,23.3,.4,.5,.24],
		"axis":axis_config(),"open_position":OPEN_POSITION,"mask":MASK},"",true,true).sha256_text()

static func validate_snapshot(raw: Variant) -> Dictionary:
	if not _exact(raw,SAVE_KEYS): return _result(false,"snapshot_keys")
	if not _integer(raw.version,SNAPSHOT_VERSION,SNAPSHOT_VERSION) or raw.id!=DEVICE_ID or raw.layout_sha256!=layout_fingerprint(): return _result(false,"snapshot_version_layout")
	if not _integer(raw.revision,0,MAX_SERIAL) or not _number(raw.charge,0,100) or not _integer(raw.charge_serial,0,MAX_SERIAL) or not raw.paused is bool: return _result(false,"snapshot_power_revision")
	if int(raw.charge_serial)==0 and float(raw.charge)!=0.0: return _result(false,"snapshot_charge_without_serial")
	var candidate=Axis.new()
	if not candidate.configure(axis_config()).ok: return _result(false,"axis_configuration")
	var valid: Dictionary=candidate.validate_snapshot(raw.axis)
	if not valid.ok: return _result(false,"axis:"+str(valid.code))
	if not _exact(raw.axis.last_serial,["1"]): return _result(false,"snapshot_axis_actor")
	if int(raw.axis.last_serial["1"])==-1 and (float(raw.axis.position_m)!=0.0 or float(raw.axis.velocity_mps)!=0.0): return _result(false,"motion_without_input_serial")
	var minimum_revision: int=(1 if int(raw.charge_serial)>0 else 0)+(1 if int(raw.axis.last_serial["1"])>=0 else 0)
	if int(raw.revision)<minimum_revision: return _result(false,"revision_input_history")
	if raw.paused and float(raw.axis.velocity_mps)!=0.0: return _result(false,"paused_velocity")
	if not _exact(raw.contact_observation,[Runtime.SOUTH_0,Runtime.SOUTH_1]): return _result(false,"contact_observation_keys")
	var seen: Array=[]
	for id: String in [Runtime.SOUTH_0,Runtime.SOUTH_1]:
		var cargo: Variant=raw.contact_observation[id]
		if not cargo is String or (cargo!="" and (cargo not in Runtime.CASSETTES or cargo in seen)): return _result(false,"contact_observation_id")
		if cargo!="": seen.append(cargo)
	if int(raw.revision)==0 and (int(raw.charge_serial)!=0 or float(raw.axis.position_m)!=0.0 or float(raw.axis.velocity_mps)!=0.0 or int(raw.axis.last_serial["1"])!=-1 or raw.paused or not seen.is_empty()): return _result(false,"initial_revision_state")
	return _result(true,"valid_device_state")

## Initialization only: never teleport a valve in an already running world.
## Even initialization keeps the closed-to-saved full sweep and endpoint clear.
## A failed call leaves the newly configured device and anti-replay state intact.
func restore_fresh(raw: Variant, authority: bool = true) -> Dictionary:
	if not configured or not _authority or not authority: return _result(false,"authority_required")
	if _used or _last_frame!=-1 or revision!=0: return _result(false,"fresh_device_required")
	var valid: Dictionary=validate_snapshot(raw)
	if not valid.ok: return valid
	var issue: String=_integrity()
	if not issue.is_empty(): return _result(false,issue)
	var candidate=Axis.new()
	if not candidate.configure(axis_config()).ok: return _result(false,"axis_configuration")
	# false is essential: GuidedAxis defaults to clearing velocity on restore.
	var restored: Dictionary=candidate.restore(raw.axis,false)
	if not restored.ok: return restored
	var target: Vector3=VALVE_CLOSED+Vector3(0,0,float(raw.axis.position_m))
	if not _sweep_clear(valve.global_position,target): return _result(false,"restore_space_obstructed")
	_axis=candidate
	_charge=float(raw.charge)
	_charge_serial=int(raw.charge_serial)
	revision=int(raw.revision)
	_paused=raw.paused
	_last_contacts=raw.contact_observation.duplicate(true)
	_blocked=false
	_fault=""
	_last_frame=-1
	_used=true
	valve.global_position=target
	PhysicsServer3D.body_set_state(valve.get_rid(),PhysicsServer3D.BODY_STATE_TRANSFORM,valve.global_transform)
	_sync_lamp()
	return _result(true,"restored_fresh_device_only")

## Same-frame stable binding; bounded nonzero axis velocity is serializable.
## No contact or device clock is advanced by this read-only capture method.
func capture_state(frame: int) -> Dictionary:
	if not configured or not _authority or _paused or not _fault.is_empty(): return _result(false,"active_host_device_required")
	if frame!=Engine.get_physics_frames() or _last_frame!=frame: return _result(false,"current_device_sample_required")
	var issue: String=_integrity()
	if not issue.is_empty(): return _result(false,issue)
	if _blocked or not _sweep_clear(valve.global_position,valve.global_position): return _result(false,"device_obstructed")
	if _last_contacts!=_read_contacts(): return _result(false,"contact_changed_after_sample")
	var state: Dictionary=snapshot()
	var valid: Dictionary=validate_snapshot(state)
	if not valid.ok: return valid
	return {"ok":true,"code":"current_device_sample","state":state}

func bound_to(cargos: Dictionary, berths: Dictionary, custody: RefCounted) -> bool:
	if not configured or _custody!=custody: return false
	for id: String in Runtime.CASSETTES:
		if not _cargos.has(id) or _cargos[id].get_ref()!=cargos.get(id): return false
	for id: String in [Runtime.SOUTH_0,Runtime.SOUTH_1]:
		if not _berths.has(id) or _berths[id].get_ref()!=berths.get(id): return false
	return true

func _sync_lamp() -> void:
	var material: StandardMaterial3D=_lamp.material_override
	material.albedo_color=Color("78c8b4") if _charge>=20.0 else Color("66564c")

static func _exact(value: Variant, keys: Array) -> bool:
	if not value is Dictionary or value.size()!=keys.size(): return false
	for key: Variant in value:
		if not key is String or key not in keys: return false
	return true

static func _number(value: Variant, low: float, high: float) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and float(value)>=low and float(value)<=high

static func _integer(value: Variant, low: int, high: int) -> bool:
	return _number(value,low,high) and floor(float(value))==float(value)

func report() -> Dictionary:
	return {"configured":configured,"revision":revision,"charge":_charge,"charge_serial":_charge_serial,"axis":_axis.snapshot(),"paused":_paused,"blocked":_blocked,"fault":_fault,"facts":facts()}

func _gate(authority: bool) -> Dictionary:
	if not configured: return _result(false,"not_configured")
	if not authority or not _authority: return _result(false,"authority_required")
	if _paused: return _result(false,"paused")
	if not _fault.is_empty(): return _result(false,_fault)
	var issue: String=_integrity()
	if not issue.is_empty():
		_fault=issue
		return _result(false,issue)
	return _result(true,"allowed")

func _integrity() -> String:
	if not configured: return "not_configured"
	if not is_instance_valid(valve) or not is_instance_valid(relay) or not valve.is_inside_tree() or not relay.is_inside_tree() or valve.is_queued_for_deletion() or relay.is_queued_for_deletion(): return "mechanism_lost"
	if not _solid_geometry(valve,Vector3(.4,.14,.2)) or _shape.size!=Vector3(.4,.14,.2): return "valve_collision_changed"
	if not global_transform.is_equal_approx(Transform3D.IDENTITY): return "root_moved"
	for pair: Array in [["base","base_transform"],["relay","relay_transform"]]:
		var node: Variant=_fixed[pair[0]].get_ref()
		if not is_instance_valid(node) or not node.global_transform.is_equal_approx(_fixed[pair[1]]): return "fixed_mount_changed"
		var size: Vector3=Vector3(1.2,.9,1.2) if pair[0]=="base" else Vector3(.4,.5,.24)
		if not _solid_geometry(node,size): return "fixed_collision_changed"
	for group: Dictionary in [_cargos,_berths]:
		for entry: WeakRef in group.values():
			var node: Variant=entry.get_ref()
			if not is_instance_valid(node) or not node.is_inside_tree() or node.get_world_3d()!=get_world_3d(): return "registered_body_lost"
	var expected: Vector3=VALVE_CLOSED+Vector3(0,0,float(_axis.snapshot().position_m))
	if not valve.global_transform.is_equal_approx(Transform3D(Basis.IDENTITY,expected)): return "valve_pose_changed"
	return ""

static func _solid_geometry(body: StaticBody3D, size: Vector3) -> bool:
	if body.collision_layer!=1 or body.collision_mask!=0: return false
	var count := 0
	for owner: int in body.get_shape_owners():
		if body.is_shape_owner_disabled(owner) or not body.shape_owner_get_transform(owner).is_equal_approx(Transform3D.IDENTITY): return false
		for index in body.shape_owner_get_shape_count(owner):
			var shape: Shape3D=body.shape_owner_get_shape(owner,index)
			if not shape is BoxShape3D or not shape.size.is_equal_approx(size): return false
			count+=1
	return count==1

func _placement_clear(at: Vector3, size: Vector3) -> bool:
	var shape:=BoxShape3D.new()
	shape.size=size
	var query:=PhysicsShapeQueryParameters3D.new()
	query.shape=shape
	query.transform=Transform3D(Basis.IDENTITY,at)
	query.collision_mask=MASK
	query.margin=.001
	return get_world_3d().direct_space_state.intersect_shape(query,8).is_empty()

func _sweep_clear(start: Vector3, finish: Vector3) -> bool:
	var query:=PhysicsShapeQueryParameters3D.new()
	query.shape=_shape
	query.transform=Transform3D(Basis.IDENTITY,start)
	query.motion=Vector3.ZERO
	query.collision_mask=MASK
	query.exclude=[valve.get_rid()]
	query.margin=.001
	var space: PhysicsDirectSpaceState3D=get_world_3d().direct_space_state
	if not space.intersect_shape(query,8).is_empty(): return false
	query.motion=finish-start
	if query.motion.length_squared()>0.000000001:
		var fraction: PackedFloat32Array=space.cast_motion(query)
		if fraction.size()!=2 or fraction[0]<.99999: return false
	query.transform.origin=finish
	query.motion=Vector3.ZERO
	return space.intersect_shape(query,8).is_empty()

func _solid(label: String, at: Vector3, size: Vector3, color: Color) -> StaticBody3D:
	var body:=StaticBody3D.new()
	body.name=label
	body.position=at
	body.collision_layer=1
	body.collision_mask=0
	var collider:=CollisionShape3D.new()
	var shape:=BoxShape3D.new()
	shape.size=size
	collider.shape=shape
	body.add_child(collider)
	add_child(body)
	var view: MeshInstance3D=_mesh(label+"Shape",Vector3.ZERO,size,color,body)
	view.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	return body

func _mesh(label: String, at: Vector3, size: Vector3, color: Color, parent: Node3D = null) -> MeshInstance3D:
	var node:=MeshInstance3D.new()
	node.name=label
	node.position=at
	var shape:=BoxMesh.new()
	shape.size=size
	var material:=StandardMaterial3D.new()
	material.albedo_color=color
	material.roughness=.75
	node.mesh=shape
	node.material_override=material
	(parent if parent!=null else self).add_child(node)
	return node

static func _result(ok: bool, code: String) -> Dictionary:
	return {"ok":ok,"code":code}
