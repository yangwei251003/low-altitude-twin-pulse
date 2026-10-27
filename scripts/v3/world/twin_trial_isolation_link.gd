class_name TwinTrialIsolationLink
extends Node3D
## Independent low service fitting, not a water solver or a connected trial.
## NORMAL opens the two high-side shutters and closes the low crosslink.
## The single cam axis closes the source route BEFORE opening its alternative.
## Install only with i2_distribution_trial_layout.json's two physical holes.
## Six moving parts are independent; high branches are geometric states only.
const Axis = preload("res://scripts/v3/environment/twin_guided_axis.gd")
const FlightBody = preload("res://scripts/v2/flight_body.gd")
const HANDLE := "I2:trial_isolation_handle"
const ORIGIN := Vector3(18,0,-10)
const TRAVEL := 0.8
const HIGH_CLOSED_AT := 0.35
const LOW_STARTS_AT := 0.45
const PIPE_WIDTH := 0.07
const BORE_WIDTH := 0.04
const MARGIN := 0.001
const SAVE_KEYS := ["version","geometry_sha256","serial","axis","blocked"]
const AXIS_CONFIG := {"travel_m":TRAVEL,"mass_kg":2.0,"damping_per_second":0.8,"max_speed_mps":2.0,"max_impulse_ns":9.0}
var configured := false
var authority := true
var fixed_bodies: Dictionary = {}
var moving_bodies: Dictionary = {}
var target_bodies: Dictionary = {}
var _geometry: Dictionary = {}
var _state: Dictionary = {}
var _axis = Axis.new()
var _paused := false
var _pinned := false

func configure(saved: Dictionary={},is_authority: bool=true) -> Dictionary:
	if configured or is_inside_tree(): return _r(false,"configure_before_tree_once")
	var axis=Axis.new()
	var checked: Dictionary=axis.configure(AXIS_CONFIG)
	if not checked.ok: return checked
	var geometry:=_definition()
	var digest:=JSON.stringify(geometry,"",true,true).sha256_text()
	var next: Dictionary={"version":1,"geometry_sha256":digest,"serial":0,"axis":axis.snapshot(),"blocked":false}
	if not saved.is_empty():
		checked=_check_snapshot(saved,digest,axis)
		if not checked.ok: return checked
		axis.restore(saved.axis,is_authority)
		if is_authority: axis.set_active_peers([])
		next=_normalized(saved)
		next.axis=axis.snapshot()
	_geometry=geometry
	_state=next
	_axis=axis
	authority=is_authority
	position=ORIGIN
	for spec in _geometry.fixed: fixed_bodies[spec.id]=_solid(spec,_v(spec.center),false)
	for spec in _geometry.moving: moving_bodies[spec.id]=_solid(spec,_part_position(spec,float(_state.axis.position_m)),true)
	target_bodies[HANDLE]=moving_bodies.HandleGrip
	moving_bodies.HandleGrip.set_meta("entity_id",HANDLE)
	configured=true
	set_meta("stage","independent_isolation_link_not_connected_to_station")
	set_process(false)
	set_physics_process(false)
	_sync_poses()
	return _r(true,"configured")

func _ready() -> void:
	if configured: _sync_poses()

func layout() -> Dictionary:
	return _geometry.duplicate(true)

func snapshot() -> Dictionary:
	return _state.duplicate(true)

func status() -> Dictionary:
	if not configured: return {}
	return _status_from_verified_pose(_poses_match())

## Internal same-call projection only. Public status() always rechecks poses;
## Station may supply its immediately preceding complete actual geometry check.
## This stores no proof and reads the current axis/velocity/blocked values now.
func _status_from_verified_pose(pose_valid: bool) -> Dictionary:
	if not configured: return {}
	var position_m:=float(_state.axis.position_m)
	var high:=_high_open(position_m)
	var low:=_low_open(position_m)
	var stopped: bool=absf(float(_state.axis.velocity_mps))<0.000001
	return {"axis_position_m":position_m,"axis_velocity_mps":float(_state.axis.velocity_mps),
		"phase":"normal" if position_m<=0.005 and stopped else "trial" if position_m>=TRAVEL-0.005 and stopped else "high_transition" if position_m<HIGH_CLOSED_AT else "both_closed" if position_m<=LOW_STARTS_AT else "low_transition",
		"pose_valid":pose_valid,"high_open_fraction":high,"high_closed":high==0.0 and pose_valid,"low_open_fraction":low,
		"low_open":low>=0.995 and pose_valid,"trial_ready":low>=0.995 and high==0.0 and stopped and pose_valid,
		"blocked":bool(_state.blocked),"station_connected":false,"clinic_water_affected":false}

func validate_snapshot(raw: Variant) -> Dictionary:
	if not configured: return _r(false,"not_configured")
	return _check_snapshot(raw,str(_state.geometry_sha256),_axis)

func apply_snapshot(raw: Variant) -> Dictionary:
	var checked:=validate_snapshot(raw)
	if not checked.ok: return checked
	var axis=_axis.copy_for_trial()
	axis.restore(raw.axis,authority)
	if authority: axis.set_active_peers([])
	var next:=_normalized(raw)
	next.axis=axis.snapshot()
	_axis=axis
	_state=next
	_pinned=false
	_sync_poses()
	return _r(true,"snapshot_applied")

func set_simulation_paused(value: bool) -> Dictionary:
	if not configured: return _r(false,"not_configured")
	if authority and int(_state.serial)>=Axis.MAX_SERIAL: return _r(false,"serial_limit")
	_paused=value
	if value and authority:
		var stopped: Dictionary=_axis.stop()
		_publish_axis()
		return {"ok":true,"code":"paused","cancelled":stopped.cancelled}
	return _r(true,"paused" if value else "resumed")

func synchronize_impulse_roster(players: Dictionary) -> Dictionary:
	var checked:=_host_guard()
	if not checked.ok: return checked
	checked=_validate_players(players)
	if not checked.ok: return checked
	var result: Dictionary=_axis.set_active_peers(_active_peers(players))
	_publish_axis()
	return result

func reset_impulse_peer(peer: int) -> Dictionary:
	var checked:=_host_guard()
	if not checked.ok: return checked
	var result: Dictionary=_axis.reset_peer(peer)
	if result.ok: _publish_axis()
	return result

func can_accept_impulse(id: String,impulse: Vector3,peer: int,action_serial: int) -> Dictionary:
	var checked:=_host_guard()
	if not checked.ok: return checked
	if id!=HANDLE: return _r(false,"unknown_impulse_target")
	if _paused or _pinned: return _r(false,"mechanism_stopped")
	if not _poses_match(): return _r(false,"unauthorized_pose")
	return _axis.can_accept(impulse,peer,action_serial)

func apply_authorized_impulse(id: String,impulse: Vector3,peer: int,action_serial: int) -> Dictionary:
	var checked:=can_accept_impulse(id,impulse,peer,action_serial)
	if not checked.ok: return checked
	var result: Dictionary=_axis.apply_impulse(impulse,peer,action_serial)
	_publish_axis()
	return result

func fixed_update(delta: float,entities: Dictionary,players: Dictionary,is_authority: bool=true) -> Dictionary:
	var checked:=_host_guard()
	if not checked.ok: return checked
	if not is_authority: return _r(false,"not_authority")
	if not _number(delta,0.0,0.25): return _r(false,"delta_range")
	if _paused or delta==0.0: return _r(true,"paused")
	if not _poses_match(): return _r(false,"unauthorized_pose")
	checked=_validate_players(players)
	if not checked.ok: return checked
	if not entities.get(HANDLE) is Dictionary: return _r(false,"missing_entity")
	var handle: Dictionary=entities[HANDLE]
	if not handle.get("pinned") is bool or not _number(handle.get("field_remaining"),0,4): return _r(false,"pin_state")
	var pinned: bool=handle.pinned and float(handle.field_remaining)>0.0
	var axis=_axis.copy_for_trial()
	var roster: Dictionary=axis.set_active_peers(_active_peers(players))
	var cancelled: Array=roster.cancelled.duplicate(true)
	if pinned: cancelled.append_array(axis.stop().cancelled)
	var proposed: Dictionary=axis.preview(delta)
	if not proposed.ok: return proposed
	var start:=float(_state.axis.position_m)
	var finish:=float(proposed.position_m)
	var blocked: bool=finish!=start and not _motion_clear(start,finish)
	axis.advance(delta,blocked)
	var next:=snapshot()
	next.axis=axis.snapshot()
	next.blocked=blocked
	checked=_check_snapshot(next,str(_state.geometry_sha256),axis)
	if not checked.ok: return checked
	_axis=axis
	_pinned=pinned
	_adopt(next)
	_sync_poses()
	return {"ok":true,"code":"blocked" if blocked else "advanced","blocked":blocked,"cancelled":cancelled,"trial_ready":status().trial_ready}

func target_definitions() -> Array:
	if not configured: return []
	return [{"id":HANDLE,"name":"配流试验隔离联锁柄","position":entity_position(HANDLE),"tags":["movable","fieldable","mechanical"],"pinned":false,"pinned_by":"","field_remaining":0.0,"revision":0}]

func entity_position(id: String) -> Variant:
	if not configured or not target_bodies.has(id): return null
	var body: Node3D=target_bodies[id]
	return body.global_position if is_inside_tree() else transform*body.position

func _host_guard() -> Dictionary:
	if not configured or not is_inside_tree(): return _r(false,"world_required")
	if not authority: return _r(false,"not_authority")
	if not global_basis.is_equal_approx(Basis.IDENTITY) or not global_position.is_equal_approx(ORIGIN): return _r(false,"world_aligned_module_required")
	if int(_state.serial)>=Axis.MAX_SERIAL: return _r(false,"serial_limit")
	return _r(true,"valid")

func _validate_players(players: Dictionary) -> Dictionary:
	if players.size()>2: return _r(false,"player_limit")
	for peer in players:
		var body: Variant=players[peer]
		if not peer is int or peer<=0 or peer>2147483647 or not body is FlightBody or not is_instance_valid(body): return _r(false,"real_player_required")
		if not body.is_inside_tree() or body.get_world_3d()!=get_world_3d() or (body.collision_layer&2)==0 or not is_finite(float(body.health)): return _r(false,"player_world_or_health")
		var shapes:=0
		for owner in body.get_shape_owners():
			if not body.is_shape_owner_disabled(owner): shapes+=body.shape_owner_get_shape_count(owner)
		if shapes==0: return _r(false,"player_shape_required")
	return _r(true,"valid")

func _active_peers(players: Dictionary) -> Array:
	var peers: Array=[]
	for peer in players:
		if players[peer].enabled and float(players[peer].health)>0: peers.append(peer)
	peers.sort()
	return peers

func _motion_clear(start: float,finish: float) -> bool:
	var excluded: Array[RID]=[]
	for body in moving_bodies.values(): excluded.append(body.get_rid())
	# Each cam follower is monotone on the whole axis range, so its swept AABB
	# includes the entire path even when this tick crosses both cam breakpoints.
	for spec in _geometry.moving:
		var a:=_part_position(spec,start)
		var b:=_part_position(spec,finish)
		if a==b: continue
		var shape:=BoxShape3D.new()
		shape.size=_v(spec.size)+(b-a).abs()
		var query:=PhysicsShapeQueryParameters3D.new()
		query.shape=shape
		query.transform=global_transform*Transform3D(Basis.IDENTITY,(a+b)*0.5)
		query.collision_mask=0xFFFFFFFF
		query.exclude=excluded
		query.margin=MARGIN
		if not get_world_3d().direct_space_state.intersect_shape(query,1).is_empty(): return false
	return true

func _poses_match() -> bool:
	for spec in _geometry.fixed:
		if not fixed_bodies[spec.id].transform.is_equal_approx(Transform3D(Basis.IDENTITY,_v(spec.center))): return false
	for spec in _geometry.moving:
		if not moving_bodies[spec.id].transform.is_equal_approx(Transform3D(Basis.IDENTITY,_part_position(spec,float(_state.axis.position_m)))): return false
	return true

func _sync_poses() -> void:
	for spec in _geometry.moving:
		var body: StaticBody3D=moving_bodies[spec.id]
		var point:=_part_position(spec,float(_state.axis.position_m))
		if is_inside_tree() and body.position==point and PhysicsServer3D.body_get_state(body.get_rid(),PhysicsServer3D.BODY_STATE_TRANSFORM)==body.global_transform: continue
		body.position=point
		if is_inside_tree():
			body.force_update_transform()
			PhysicsServer3D.body_set_state(body.get_rid(),PhysicsServer3D.BODY_STATE_TRANSFORM,body.global_transform)

func _publish_axis() -> void:
	var next:=snapshot()
	next.axis=_axis.snapshot()
	_adopt(next)

func _adopt(next: Dictionary) -> void:
	if next==_state: return
	next.serial=int(_state.serial)+1
	_state=next

func _solid(spec: Dictionary,center: Vector3,moving: bool) -> StaticBody3D:
	var body:=StaticBody3D.new()
	body.name=spec.id
	body.position=center
	body.collision_layer=8 if moving else 1
	body.collision_mask=0
	var collision:=CollisionShape3D.new()
	var shape:=BoxShape3D.new()
	shape.size=_v(spec.size)
	collision.shape=shape
	body.add_child(collision)
	var visual:=MeshInstance3D.new()
	visual.name="Visual"
	var mesh:=BoxMesh.new()
	mesh.size=shape.size
	visual.mesh=mesh
	var material:=StandardMaterial3D.new()
	material.albedo_color=Color(str(spec.color))
	material.roughness=0.7
	visual.material_override=material
	body.add_child(visual)
	add_child(body)
	return body

static func _definition() -> Dictionary:
	var fixed: Array=[]
	var moving: Array=[]
	for side in [-1,1]:
		var label: String="A" if side<0 else "B"
		var x:=float(side)*1.55
		_tube(fixed,label+"_OuterLow",Vector3(side*2.45,.15,-2.44),Vector3(x+side*.035,.15,-2.44),0)
		_joint(fixed,label+"_FootElbow",Vector3(x,.15,-2.44),[Vector3.RIGHT*side,Vector3.UP])
		_tube(fixed,label+"_Riser",Vector3(x,.185,-2.44),Vector3(x,1.245,-2.44),1)
		_joint(fixed,label+"_LowTee",Vector3(x,1.28,-2.44),[Vector3.LEFT*side,Vector3.UP,Vector3.DOWN])
		_tube(fixed,label+"_HighLower",Vector3(x,1.315,-2.44),Vector3(x,1.586,-2.44),1)
		var height:=2.82 if side<0 else 1.75
		_tube(fixed,label+"_HighUpper",Vector3(x,1.614,-2.44),Vector3(x,height-.035,-2.44),1)
		_joint(fixed,label+"_HighElbow",Vector3(x,height,-2.44),[Vector3.LEFT*side,Vector3.DOWN])
		_tube(fixed,label+"_OldBranchJoin",Vector3(x-side*.035,height,-2.44),Vector3(side*1.3,height,-2.44),0)
		_add(moving,"HighShutter"+label,Vector3(x,1.6,-2.44),Vector3(.08,.012,.08),"bd9a59","high")
	_tube(fixed,"LowCrossA",Vector3(-1.515,1.28,-2.44),Vector3(-.014,1.28,-2.44),0)
	_tube(fixed,"LowCrossB",Vector3(.014,1.28,-2.44),Vector3(1.515,1.28,-2.44),0)
	_add(moving,"LowShutter",Vector3(0,1.28,-2.44),Vector3(.012,.08,.08),"65c5dd","low")
	_add(moving,"HandleGrip",Vector3(-.4,.65,3.15),Vector3(.2,.16,.14),"c9a96b","handle")
	_add(moving,"HandleStem",Vector3(-.4,.49,3.15),Vector3(.05,.16,.07),"b4b7ad","handle")
	_add(moving,"CamDriveRod",Vector3(-.4,.39,.355),Vector3(.04,.04,5.59),"8caaa8","handle")
	_add(fixed,"HandleRail",Vector3(0,.65,3.04),Vector3(1.3,.12,.06),"547f83")
	for side in [-1,1]: _add(fixed,"HandleStop"+str(side),Vector3(side*.54,.65,3.15),Vector3(.05,.18,.18),"547f83")
	return {"version":1,"origin":[18,0,-10],"pipe_width_m":PIPE_WIDTH,"bore_width_m":BORE_WIDTH,
		"axis":AXIS_CONFIG.duplicate(true),"high_closed_at_m":HIGH_CLOSED_AT,"low_starts_at_m":LOW_STARTS_AT,
		"fixed":fixed,"moving":moving,"scope":"link_geometry_only_no_station_or_clinic_water"}

static func _tube(parts: Array,label: String,a: Vector3,b: Vector3,axis: int) -> void:
	var center: Vector3=(a+b)*.5
	var length:=absf(b[axis]-a[axis])
	var others: Array=[]
	for i in range(3):
		if i!=axis: others.append(i)
	# Four explicit walls leave an actual .04m bore; no solid pipe collider.
	for index in range(2):
		var normal: int=others[index]
		var across: int=others[1-index]
		for sign_value in [-1,1]:
			var size:=Vector3.ZERO
			size[axis]=length
			size[normal]=(PIPE_WIDTH-BORE_WIDTH)*.5
			size[across]=PIPE_WIDTH if index==0 else BORE_WIDTH
			var point:=center
			point[normal]+=sign_value*(PIPE_WIDTH+BORE_WIDTH)*.25
			_add(parts,label+"_Wall"+str(index)+"_"+str(sign_value),point,size,"738e91")

static func _joint(parts: Array,label: String,center: Vector3,open_faces: Array) -> void:
	for axis in range(3):
		for sign_value in [-1,1]:
			var direction:=Vector3.ZERO
			direction[axis]=sign_value
			if direction in open_faces: continue
			var size:=Vector3.ONE*PIPE_WIDTH
			size[axis]=(PIPE_WIDTH-BORE_WIDTH)*.5
			_add(parts,label+"_Face"+str(axis)+"_"+str(sign_value),center+direction*(PIPE_WIDTH+BORE_WIDTH)*.25,size,"738e91")

static func _add(parts: Array,id: String,center: Vector3,size: Vector3,color: String,motion: String="") -> void:
	var row: Dictionary={"id":id,"center":[center.x,center.y,center.z],"size":[size.x,size.y,size.z],"color":color}
	if motion!="": row.motion=motion
	parts.append(row)

static func _part_position(spec: Dictionary,distance: float) -> Vector3:
	var point:=_v(spec.center)
	if spec.motion=="handle": return point+Vector3.RIGHT*distance
	return point+Vector3.BACK*.14*(_high_open(distance) if spec.motion=="high" else _low_open(distance))

static func _high_open(distance: float) -> float:
	return 1.0-clampf(distance/HIGH_CLOSED_AT,0.0,1.0)

static func _low_open(distance: float) -> float:
	return clampf((distance-LOW_STARTS_AT)/(TRAVEL-LOW_STARTS_AT),0.0,1.0)

static func _check_snapshot(raw: Variant,digest: String,axis) -> Dictionary:
	if not raw is Dictionary or not _exact(raw,SAVE_KEYS): return _r(false,"snapshot_keys")
	if not _integer(raw.version,1,1) or not raw.geometry_sha256 is String or raw.geometry_sha256!=digest: return _r(false,"snapshot_geometry")
	if not _integer(raw.serial,0,Axis.MAX_SERIAL) or not raw.blocked is bool: return _r(false,"snapshot_state")
	return axis.validate_snapshot(raw.axis)

static func _normalized(raw: Dictionary) -> Dictionary:
	var next:=raw.duplicate(true)
	next.version=1
	next.serial=int(raw.serial)
	return next

static func _v(value: Array) -> Vector3:
	return Vector3(float(value[0]),float(value[1]),float(value[2]))

static func _number(value: Variant,low: float,high: float) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and float(value)>=low and float(value)<=high

static func _integer(value: Variant,low: int,high: int) -> bool:
	return _number(value,float(low),float(high)) and float(value)==floor(float(value))

static func _exact(value: Dictionary,keys: Array) -> bool:
	if value.size()!=keys.size(): return false
	for key in value:
		if not key is String or key not in keys: return false
	return true

static func _r(ok: bool,code: String) -> Dictionary:
	return {"ok":ok,"code":code}
