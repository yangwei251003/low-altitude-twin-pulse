class_name TwinSharedAccessBridge
extends Node3D
## Physical mechanism: Story/Session own save transactions and rewards.
## Public socket is carried by the east track pier's upper cantilever: a ground
## post here would block the adjacent Trial controller's established sight line.
## The bridge translates along world +Z; the separate lock pin extends downward.
const Axis = preload("res://scripts/v3/environment/twin_guided_axis.gd")
const FlightBody = preload("res://scripts/v2/flight_body.gd")
const PATH := "res://data/v3/terrain/i2_shared_access_layout.json"
const HANDLE := "I2:shared_bridge_handle"
const PIN := "I2:shared_bridge_lock"
const RELAY := "I2:shared_bridge_relay"
const PUBLIC_CONTROL := "I2:shared_bridge_public_control"
const SERVICE_CONTROL := "I2:shared_bridge_service_control"
const MODES := ["public_span","service_span"]
const SAVE_KEYS := ["version","layout_sha256","serial","axis","pin","blocked"]
const MARGIN := 0.001
var configured := false
var authority := true
var fixed_bodies: Dictionary = {}
var moving_bodies: Dictionary = {}
var pin_bodies: Dictionary = {}
var target_bodies: Dictionary = {}
var deck_art: Dictionary = {}
var landing_art: Dictionary = {}
var _layout: Dictionary = {}
var _state: Dictionary = {}
var _axis = Axis.new()
var _pin = Axis.new()
var _paused := false
var _pinned := false
var _motor_active := false
var _require_control_release := false
var _manual_input := false

func load_layout(saved: Dictionary={},is_authority: bool=true) -> Dictionary:
	var data: Variant=JSON.parse_string(FileAccess.get_file_as_string(PATH))
	if not data is Dictionary: return _r(false,"layout_json")
	return configure(data,saved,is_authority)

func configure(data: Dictionary,saved: Dictionary={},is_authority: bool=true) -> Dictionary:
	if configured or is_inside_tree(): return _r(false,"configure_before_tree_once")
	var checked:=_check_layout(data)
	if not checked.ok: return checked
	var axis=Axis.new()
	var pin=Axis.new()
	checked=axis.configure(data.axis)
	if not checked.ok: return checked
	checked=pin.configure(data.pin_axis)
	if not checked.ok: return checked
	var pin_initial: Dictionary=pin.snapshot()
	pin_initial.position_m=.3
	pin.restore(pin_initial)
	var digest:=JSON.stringify(data,"",true,true).sha256_text()
	var next: Dictionary={"version":1,"layout_sha256":digest,"serial":0,"axis":axis.snapshot(),"pin":pin.snapshot(),"blocked":false}
	if not saved.is_empty():
		checked=_check_snapshot(saved,digest,axis,pin)
		if not checked.ok: return checked
		axis.restore(saved.axis,is_authority)
		pin.restore(saved.pin,is_authority)
		if is_authority:
			axis.set_active_peers([])
			pin.set_active_peers([])
		next=saved.duplicate(true)
		next.serial=int(saved.serial)
		next.axis=axis.snapshot()
		next.pin=pin.snapshot()
	_layout=data.duplicate(true)
	_state=next
	_axis=axis
	_pin=pin
	authority=is_authority
	_require_control_release=is_authority and not saved.is_empty()
	for spec in _layout.fixed: fixed_bodies[spec.id]=_solid(spec,_v(spec.center),false)
	for spec in _layout.moving: moving_bodies[spec.id]=_solid(spec,_point(spec,float(next.axis.position_m),0.0),true)
	for spec in _layout.pin_parts: pin_bodies[spec.id]=_solid(spec,_point(spec,float(next.axis.position_m),float(next.pin.position_m)),true)
	target_bodies={HANDLE:moving_bodies.BridgeHandle,PIN:pin_bodies.LockGrip,RELAY:fixed_bodies.Relay,PUBLIC_CONTROL:fixed_bodies.PublicController,SERVICE_CONTROL:fixed_bodies.ServiceController}
	for id in target_bodies: target_bodies[id].set_meta("entity_id",id)
	for row in _layout.labels:
		var label:=Label3D.new()
		label.text=str(row.text)
		label.position=_v(row.position)+Vector3.UP*.8
		label.font_size=26
		label.pixel_size=.014
		label.modulate=Color(str(row.color))
		label.billboard=BaseMaterial3D.BILLBOARD_ENABLED
		add_child(label)
	configured=true
	set_meta("stage","independent_shared_access_graybox_no_resident_ai")
	set_process(false)
	set_physics_process(false)
	_sync_poses()
	return _r(true,"configured")

func _ready() -> void:
	if configured: _sync_poses()

func layout() -> Dictionary:
	return _layout.duplicate(true)

func snapshot() -> Dictionary:
	return _state.duplicate(true)

func status() -> Dictionary:
	if not configured: return {}
	var position_m:=float(_state.axis.position_m)
	var endpoint:=_endpoint(position_m)
	var locked: bool=endpoint!="" and float(_state.pin.position_m)>=.299 and absf(float(_state.axis.velocity_mps))<.000001 and absf(float(_state.pin.velocity_mps))<.000001 and _poses_match()
	return {"position_m":position_m,"pin_extension_m":float(_state.pin.position_m),"locked":locked,
		"mode":endpoint if locked else "unlocked","endpoint":endpoint,"blocked":bool(_state.blocked),"motor_active":_motor_active,
		"paused":_paused,"pose_valid":_poses_match(),"resident_ai":false,"world_choice_committed":false}

func validate_snapshot(raw: Variant) -> Dictionary:
	if not configured: return _r(false,"not_configured")
	return _check_snapshot(raw,str(_state.layout_sha256),_axis,_pin)

func apply_snapshot(raw: Variant) -> Dictionary:
	var checked:=validate_snapshot(raw)
	if not checked.ok: return checked
	var axis=_axis.copy_for_trial()
	var pin=_pin.copy_for_trial()
	axis.restore(raw.axis,authority)
	pin.restore(raw.pin,authority)
	if authority:
		axis.set_active_peers([])
		pin.set_active_peers([])
	var next: Dictionary=raw.duplicate(true)
	next.serial=int(raw.serial)
	next.axis=axis.snapshot()
	next.pin=pin.snapshot()
	_axis=axis
	_pin=pin
	_state=next
	_pinned=false
	_motor_active=false
	_manual_input=false
	_require_control_release=authority
	_sync_poses()
	return _r(true,"snapshot_applied")

func set_simulation_paused(value: bool) -> Dictionary:
	if not configured: return _r(false,"not_configured")
	if authority and int(_state.serial)>=Axis.MAX_SERIAL: return _r(false,"serial_limit")
	_paused=value
	if value and authority:
		var cancelled: Array=_axis.stop().cancelled
		cancelled.append_array(_pin.stop().cancelled)
		_manual_input=false
		_motor_active=false
		_publish_axes()
		return {"ok":true,"code":"paused","cancelled":cancelled}
	return _r(true,"paused" if value else "resumed")

func synchronize_impulse_roster(players: Dictionary) -> Dictionary:
	var checked:=_host_guard()
	if not checked.ok: return checked
	checked=_validate_players(players)
	if not checked.ok: return checked
	var peers:=_active_peers(players)
	var result: Dictionary=_axis.set_active_peers(peers)
	result.cancelled.append_array(_pin.set_active_peers(peers).cancelled)
	_publish_axes()
	return result

func reset_impulse_peer(peer: int) -> Dictionary:
	var checked:=_host_guard()
	if not checked.ok: return checked
	var result: Dictionary=_axis.reset_peer(peer)
	if not result.ok: return result
	result.cancelled.append_array(_pin.reset_peer(peer).cancelled)
	_publish_axes()
	return result

func can_accept_impulse(id: String,impulse: Vector3,peer: int,action_serial: int) -> Dictionary:
	var checked:=_host_guard()
	if not checked.ok: return checked
	if id not in [HANDLE,PIN]: return _r(false,"unknown_impulse_target")
	if _paused or _pinned: return _r(false,"mechanism_stopped")
	if _motor_active: return _r(false,"motor_owns_axis")
	if not _poses_match(): return _r(false,"unauthorized_pose")
	if id==HANDLE and float(_state.pin.position_m)>.000001: return _r(false,"withdraw_lock_pin")
	if id==PIN and impulse.y<0.0 and (_endpoint(float(_state.axis.position_m))=="" or absf(float(_state.axis.velocity_mps))>.000001): return _r(false,"pin_not_aligned")
	return _axis.can_accept(_project(impulse,false),peer,action_serial) if id==HANDLE else _pin.can_accept(_project(impulse,true),peer,action_serial)

func apply_authorized_impulse(id: String,impulse: Vector3,peer: int,action_serial: int) -> Dictionary:
	var checked:=can_accept_impulse(id,impulse,peer,action_serial)
	if not checked.ok: return checked
	var result: Dictionary=_axis.apply_impulse(_project(impulse,false),peer,action_serial) if id==HANDLE else _pin.apply_impulse(_project(impulse,true),peer,action_serial)
	_manual_input=true
	_publish_axes()
	return result

func fixed_update(delta: float,entities: Dictionary,players: Dictionary,is_authority: bool=true) -> Dictionary:
	var checked:=_host_guard()
	if not checked.ok: return checked
	if not is_authority: return _r(false,"not_authority")
	if not _number(delta,0.0,.25): return _r(false,"delta_range")
	if _paused or delta==0.0: return _r(true,"paused")
	if not _poses_match(): return _r(false,"unauthorized_pose")
	checked=_inputs(entities,players)
	if not checked.ok: return checked
	var axis=_axis.copy_for_trial()
	var pin=_pin.copy_for_trial()
	var peers:=_active_peers(players)
	var cancelled: Array=axis.set_active_peers(peers).cancelled
	cancelled.append_array(pin.set_active_peers(peers).cancelled)
	var controls_live: bool=bool(checked.controls_live)
	if not controls_live: _require_control_release=false
	var motor: bool=checked.goal!="" and checked.powered and not checked.pinned and not _require_control_release and not _manual_input
	var start:=float(_state.axis.position_m)
	var pin_start:=float(_state.pin.position_m)
	var finish:=start
	var pin_finish:=pin_start
	var code: String="advanced"
	if checked.pinned:
		cancelled.append_array(axis.stop().cancelled)
		cancelled.append_array(pin.stop().cancelled)
		code="pinned"
	elif motor:
		axis.stop()
		pin.stop()
		var effective:=minf(delta,float(checked.remaining))
		var goal: float=0.0 if checked.goal==MODES[0] else 8.0
		# A nearly arrived carriage is not aligned with the physical socket.
		# Let move_toward consume the last residual step; an epsilon early-exit
		# leaves 60 Hz motion at 7.999999999999969 and the pin correctly refuses.
		if start != goal:
			if pin_start>0.0: pin_finish=move_toward(pin_start,0.0,float(_layout.pin_speed_mps)*effective)
			else: finish=move_toward(start,goal,float(_layout.motor_speed_mps)*effective)
		else: pin_finish=move_toward(pin_start,.3,float(_layout.pin_speed_mps)*effective)
		var axis_next: Dictionary=axis.snapshot()
		axis_next.position_m=finish
		axis.restore(axis_next,false)
		var pin_next: Dictionary=pin.snapshot()
		pin_next.position_m=pin_finish
		pin.restore(pin_next,false)
		code="motor"
	else:
		# Lost authority/power does not coast a previous motor command. Manual
		# accepted velocity remains physical and is consumed by the same tick.
		if _motor_active and not _manual_input:
			axis.stop()
			pin.stop()
		axis.advance(delta)
		pin.advance(delta)
		finish=float(axis.snapshot().position_m)
		pin_finish=float(pin.snapshot().position_m)
	var interlocked: bool=(finish!=start and (pin_start>0.0 or pin_finish>0.0)) or (pin_finish>0.0 and _endpoint(finish)=="")
	var moving: bool=finish!=start or pin_finish!=pin_start
	var blocked: bool=interlocked or (moving and not _motion_clear(start,finish,pin_start,pin_finish))
	if blocked:
		axis=_axis.copy_for_trial()
		pin=_pin.copy_for_trial()
		cancelled.append_array(axis.stop().cancelled)
		cancelled.append_array(pin.stop().cancelled)
		code="interlocked" if interlocked else "blocked"
	var next:=snapshot()
	next.axis=axis.snapshot()
	next.pin=pin.snapshot()
	next.blocked=blocked
	var valid:=_check_snapshot(next,str(_state.layout_sha256),axis,pin)
	if not valid.ok: return valid
	_axis=axis
	_pin=pin
	_pinned=checked.pinned
	_motor_active=motor and not blocked
	_manual_input=false
	_adopt(next)
	_sync_poses()
	return {"ok":true,"code":code,"blocked":blocked,"cancelled":cancelled,"mode":status().mode}

func target_definitions() -> Array:
	if not configured: return []
	var rows: Array=[]
	for id in [HANDLE,PIN]: rows.append({"id":id,"name":"公共桥牵引柄" if id==HANDLE else "公共桥锁销（上提解锁）","position":entity_position(id),"tags":["movable","fieldable","mechanical"],"pinned":false,"pinned_by":"","field_remaining":0.0,"revision":0})
	rows.append({"id":RELAY,"name":"公共桥供能","position":entity_position(RELAY),"tags":["conductive","electrical"],"charge":0.0,"charge_capacity":100.0,"power_threshold":20.0,"powered":false,"revision":0})
	for id in [PUBLIC_CONTROL,SERVICE_CONTROL]: rows.append({"id":id,"name":"居民短接控制" if id==PUBLIC_CONTROL else "巡检短接控制","position":entity_position(id),"tags":["mechanical","hackable"],"controlled":false,"owner":"","takeover_remaining":0.0,"revision":0})
	return rows

func entity_position(id: String) -> Variant:
	if not configured or not target_bodies.has(id): return null
	var body: Node3D=target_bodies[id]
	return body.global_position if is_inside_tree() else transform*body.position

func access_report() -> Dictionary:
	if not configured or not is_inside_tree(): return _r(false,"world_required")
	var pose:=status()
	var reports: Dictionary={}
	for id in _layout.routes: reports[id]=_route_clear(_layout.routes[id])
	var public_key: String="public_short" if pose.mode==MODES[0] else "public_bypass"
	var service_key: String="service_short" if pose.mode==MODES[1] else "service_bypass"
	return {"ok":true,"mode":pose.mode,"locked":pose.locked,"routes":reports,"public_route":public_key,"service_route":service_key,
		"public_access":reports[public_key].ok,"service_access":reports[service_key].ok,"choice_ready":pose.locked and reports[public_key].ok and reports[service_key].ok,"width_m":3.0,"height_m":2.8,"resident_ai":false}

func _inputs(entities: Dictionary,players: Dictionary) -> Dictionary:
	var checked:=_validate_players(players)
	if not checked.ok: return checked
	for id in [HANDLE,PIN,RELAY,PUBLIC_CONTROL,SERVICE_CONTROL]:
		if not entities.get(id) is Dictionary: return _r(false,"missing_entity")
	var pinned:=false
	for id in [HANDLE,PIN]:
		if not entities[id].get("pinned") is bool or not _number(entities[id].get("field_remaining"),0,4): return _r(false,"pin_state")
		pinned=pinned or (entities[id].pinned and float(entities[id].field_remaining)>0.0)
	if not entities[RELAY].get("powered") is bool: return _r(false,"power_state")
	var controls: Array=[]
	var controls_live:=false
	for id in [PUBLIC_CONTROL,SERVICE_CONTROL]:
		var control: Dictionary=entities[id]
		if not control.get("controlled") is bool or not control.get("owner") is String or not _number(control.get("takeover_remaining"),0,8): return _r(false,"control_state")
		controls_live=controls_live or (control.controlled and float(control.takeover_remaining)>0.0)
		for peer in _active_peers(players):
			if control.controlled and str(peer)==control.owner and float(control.takeover_remaining)>0.0: controls.append(id)
	var goal: String=""
	var remaining:=0.0
	if controls.size()==1:
		goal=MODES[0] if controls[0]==PUBLIC_CONTROL else MODES[1]
		remaining=float(entities[controls[0]].takeover_remaining)
	return {"ok":true,"code":"valid","pinned":pinned,"powered":entities[RELAY].powered,"controls_live":controls_live,"goal":goal,"remaining":remaining}

func _motion_clear(start: float,finish: float,pin_start: float,pin_finish: float) -> bool:
	var excluded: Array[RID]=[]
	for body in fixed_bodies.values()+moving_bodies.values()+pin_bodies.values(): excluded.append(body.get_rid())
	# Own supports may meet moving bearing faces at zero-volume contact. Exact
	# boxes below reject every positive-volume intrusion; foreign colliders use
	# full PhysicsServer sweeps with a positive margin and are never excluded.
	for spec in _layout.moving+_layout.pin_parts:
		var is_pin: bool=spec in _layout.pin_parts
		var a:=_point(spec,start,pin_start if is_pin else 0.0)
		var b:=_point(spec,finish,pin_finish if is_pin else 0.0)
		if a==b: continue
		var size:=_v(spec.size)+(b-a).abs()
		var swept:=AABB((a+b)*.5-size*.5,size)
		for fixed in _layout.fixed:
			var fs:=_v(fixed.size)
			if _positive_overlap(swept,AABB(_v(fixed.center)-fs*.5,fs)): return false
		var shape:=BoxShape3D.new()
		shape.size=size
		var query:=PhysicsShapeQueryParameters3D.new()
		query.shape=shape
		query.transform=global_transform*Transform3D(Basis.IDENTITY,(a+b)*.5)
		query.exclude=excluded
		query.collision_mask=0xFFFFFFFF
		query.margin=MARGIN
		if not get_world_3d().direct_space_state.intersect_shape(query,1).is_empty(): return false
	return true

func _route_clear(points: Array) -> Dictionary:
	var floor_tiles:=_floor_tiles()
	var length:=0.0
	for i in range(points.size()-1):
		var a:=Vector2(float(points[i][0]),float(points[i][1]))
		var b:=Vector2(float(points[i+1][0]),float(points[i+1][1]))
		var low:=a.min(b)-Vector2.ONE*1.5
		var size: Vector2=(b-a).abs()+Vector2.ONE*3.0
		var rect:=Rect2(low,size)
		if not _covered(rect,floor_tiles): return {"ok":false,"code":"floor_gap","segment":i}
		var shape:=BoxShape3D.new()
		shape.size=Vector3(size.x,2.8,size.y)
		var query:=PhysicsShapeQueryParameters3D.new()
		query.shape=shape
		query.transform=Transform3D(Basis.IDENTITY,Vector3(rect.get_center().x,6.41,rect.get_center().y))
		query.collision_mask=0xFFFFFFFF
		query.margin=MARGIN
		var hits: Array[Dictionary]=get_world_3d().direct_space_state.intersect_shape(query,8)
		if not hits.is_empty():
			var colliders: Array[String]=[]
			for hit in hits: colliders.append(str(hit.collider.get_path()))
			return {"ok":false,"code":"route_obstructed","segment":i,"colliders":colliders}
		length+=a.distance_to(b)
	return {"ok":true,"code":"clear","length_m":length}

func _floor_tiles() -> Array:
	var tiles: Array=[]
	for node in get_parent().find_children("*","CollisionShape3D",true,false):
		if node.disabled or not node.shape is BoxShape3D or not node.get_parent() is CollisionObject3D or node.get_parent().collision_layer==0: continue
		if not node.global_basis.is_equal_approx(Basis.IDENTITY): continue
		var half: Vector3=node.shape.size*.5
		if absf(node.global_position.y+half.y-5.0)>.00001: continue
		tiles.append(Rect2(Vector2(node.global_position.x-half.x,node.global_position.z-half.z),Vector2(half.x*2,half.z*2)))
	return tiles

static func _covered(rect: Rect2,tiles: Array) -> bool:
	var pending: Array=[rect]
	for tile: Rect2 in tiles:
		var next: Array=[]
		for part: Rect2 in pending:
			var cut:=part.intersection(tile)
			if not cut.has_area(): next.append(part); continue
			for remainder in [Rect2(part.position,Vector2(cut.position.x-part.position.x,part.size.y)),Rect2(Vector2(cut.end.x,part.position.y),Vector2(part.end.x-cut.end.x,part.size.y)),Rect2(Vector2(cut.position.x,part.position.y),Vector2(cut.size.x,cut.position.y-part.position.y)),Rect2(Vector2(cut.position.x,cut.end.y),Vector2(cut.size.x,part.end.y-cut.end.y))]:
				if remainder.size.x>.00001 and remainder.size.y>.00001: next.append(remainder)
		pending=next
		if pending.is_empty(): return true
		if pending.size()>128: return false
	return pending.is_empty()

func _validate_players(players: Dictionary) -> Dictionary:
	if players.size()>2: return _r(false,"player_limit")
	for peer in players:
		var body: Variant=players[peer]
		if not peer is int or peer<=0 or peer>2147483647 or not is_instance_valid(body) or not body is FlightBody: return _r(false,"real_player_required")
		if not body.is_inside_tree() or body.get_world_3d()!=get_world_3d() or (body.collision_layer&2)==0 or not is_finite(float(body.health)): return _r(false,"player_world_or_health")
		var count:=0
		for owner in body.get_shape_owners():
			if not body.is_shape_owner_disabled(owner): count+=body.shape_owner_get_shape_count(owner)
		if count==0: return _r(false,"player_shape_required")
	return _r(true,"valid")

func _active_peers(players: Dictionary) -> Array:
	var result: Array=[]
	for peer in players:
		if players[peer].enabled and float(players[peer].health)>0.0: result.append(peer)
	result.sort()
	return result

func _host_guard() -> Dictionary:
	if not configured or not is_inside_tree(): return _r(false,"world_required")
	if not authority: return _r(false,"not_authority")
	if not global_transform.is_equal_approx(Transform3D.IDENTITY): return _r(false,"world_aligned_module_required")
	if int(_state.serial)>=Axis.MAX_SERIAL: return _r(false,"serial_limit")
	return _r(true,"valid")

func _poses_match() -> bool:
	if not configured: return false
	for spec in _layout.fixed:
		if not _body_matches(fixed_bodies[spec.id],_v(spec.center),_v(spec.size)): return false
	for spec in _layout.moving:
		if not _body_matches(moving_bodies[spec.id],_point(spec,float(_state.axis.position_m),0),_v(spec.size)): return false
	for spec in _layout.pin_parts:
		if not _body_matches(pin_bodies[spec.id],_point(spec,float(_state.axis.position_m),float(_state.pin.position_m)),_v(spec.size)): return false
	return true

func _sync_poses() -> void:
	for spec in _layout.moving+_layout.pin_parts:
		var is_pin: bool=spec in _layout.pin_parts
		var body: StaticBody3D=pin_bodies[spec.id] if is_pin else moving_bodies[spec.id]
		body.position=_point(spec,float(_state.axis.position_m),float(_state.pin.position_m) if is_pin else 0.0)
		if is_inside_tree():
			body.force_update_transform()
			PhysicsServer3D.body_set_state(body.get_rid(),PhysicsServer3D.BODY_STATE_TRANSFORM,body.global_transform)

func _solid(spec: Dictionary,at: Vector3,moving: bool) -> StaticBody3D:
	var body:=StaticBody3D.new()
	body.name=spec.id
	body.position=at
	body.collision_layer=8 if moving else 1
	body.collision_mask=0
	var collision:=CollisionShape3D.new()
	var shape:=BoxShape3D.new()
	shape.size=_v(spec.size)
	collision.shape=shape
	body.add_child(collision)
	var mesh:=BoxMesh.new()
	mesh.size=shape.size
	var visual:=MeshInstance3D.new()
	visual.name="Visual"
	visual.mesh=mesh
	var material:=StandardMaterial3D.new()
	material.albedo_color=Color(str(spec.color))
	material.roughness=.72
	visual.material_override=material
	body.add_child(visual)
	# The panel may fade for a pilot underneath; its actual top boundary must
	# remain legible. These narrow caps are local visual cues, never collision.
	if str(spec.id) in ["NorthGuard", "SouthGuard", "WestOuterRail", "EastOuterRail", "SouthOuterRail"]:
		var cap_size := Vector3(shape.size.x, .025, shape.size.z)
		_edge_cue(body, cap_size, Vector3(0, shape.size.y*.5, 0), "Top", Color("b0c3bd"))
	elif str(spec.id) == "BridgeDeck":
		for side in [-1.0, 1.0]:
			_edge_cue(body, Vector3(.04,.012,shape.size.z), Vector3(side*(shape.size.x*.5-.02),shape.size.y*.5,0), "East" if side>0 else "West", Color("c9a45a"))
	add_child(body)
	return body

func _edge_cue(body: StaticBody3D, size: Vector3, offset: Vector3, suffix: String, color: Color) -> void:
	var edge := MeshInstance3D.new()
	edge.name = "CutawayEdge" + suffix
	edge.position = offset
	edge.set_meta("terrain_visibility_keep", true)
	var mesh := BoxMesh.new()
	mesh.size = size
	edge.mesh = mesh
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = .72
	edge.material_override = material
	body.add_child(edge)

func _publish_axes() -> void:
	var next:=snapshot()
	next.axis=_axis.snapshot()
	next.pin=_pin.snapshot()
	_adopt(next)

func _adopt(next: Dictionary) -> void:
	if next==_state: return
	next.serial=int(_state.serial)+1
	_state=next

static func _point(spec: Dictionary,position_m: float,pin_m: float) -> Vector3:
	return _v(spec.center)+Vector3(0,-pin_m,position_m)

static func _endpoint(position_m: float) -> String:
	return MODES[0] if position_m==0.0 else MODES[1] if position_m==8.0 else ""

static func _project(impulse: Vector3,pin: bool) -> Vector3:
	return Vector3(-impulse.y,impulse.x,impulse.z) if pin else Vector3(impulse.z,impulse.y,impulse.x)

static func _positive_overlap(a: AABB,b: AABB) -> bool:
	var size: Vector3=a.end.min(b.end)-a.position.max(b.position)
	return size.x>.000001 and size.y>.000001 and size.z>.000001

static func _body_matches(body: Variant,at: Vector3,size: Vector3) -> bool:
	return is_instance_valid(body) and body.collision_layer!=0 and not body.get_child(0).disabled and body.transform.is_equal_approx(Transform3D(Basis.IDENTITY,at)) and body.get_child(0).shape is BoxShape3D and body.get_child(0).shape.size.is_equal_approx(size) and body.get_node("Visual").mesh.size.is_equal_approx(size)

static func _check_snapshot(raw: Variant,digest: String,axis,pin) -> Dictionary:
	if not raw is Dictionary or not _exact(raw,SAVE_KEYS): return _r(false,"snapshot_keys")
	if not _number(raw.version,1,1) or not raw.layout_sha256 is String or raw.layout_sha256!=digest: return _r(false,"snapshot_version")
	if not _number(raw.serial,0,Axis.MAX_SERIAL) or floor(float(raw.serial))!=float(raw.serial) or not raw.blocked is bool: return _r(false,"snapshot_state")
	var checked: Dictionary=axis.validate_snapshot(raw.axis)
	if not checked.ok: return checked
	checked=pin.validate_snapshot(raw.pin)
	if not checked.ok: return checked
	if raw.axis.last_serial.size()!=raw.pin.last_serial.size(): return _r(false,"snapshot_roster_mismatch")
	for peer in raw.axis.last_serial:
		if not raw.pin.last_serial.has(peer): return _r(false,"snapshot_roster_mismatch")
	if float(raw.pin.position_m)>0.0 and (_endpoint(float(raw.axis.position_m))=="" or absf(float(raw.axis.velocity_mps))>.000001): return _r(false,"snapshot_pin_alignment")
	return _r(true,"valid")

static func _check_layout(data: Dictionary) -> Dictionary:
	var keys: Array=["version","id","stage","origin","bounds","axis","pin_axis","motor_speed_mps","pin_speed_mps","deck_top_y","route_width_m","route_height_m","fixed","moving","pin_parts","routes","labels"]
	if not _exact(data,keys) or not _number(data.version,1,1) or data.id!="i2_shared_access_bridge_v1" or data.stage!="independent_replaceable_graybox": return _r(false,"layout_schema")
	if not _vec(data.origin) or _v(data.origin)!=Vector3.ZERO or not _number(data.deck_top_y,5,5) or not _number(data.route_width_m,3,3) or not _number(data.route_height_m,2.8,2.8): return _r(false,"layout_contract")
	if not data.axis is Dictionary or not data.pin_axis is Dictionary or not _number(data.axis.get("travel_m"),8,8) or not _number(data.pin_axis.get("travel_m"),.3,.3): return _r(false,"layout_axis")
	if not _number(data.axis.get("max_impulse_ns"),9,9) or not _number(data.pin_axis.get("max_impulse_ns"),9,9): return _r(false,"layout_impulse_cap")
	if not _number(data.motor_speed_mps,.1,2) or not _number(data.pin_speed_mps,.1,1): return _r(false,"layout_motor")
	if not data.bounds is Dictionary or not _exact(data.bounds,["min","max"]) or not _vec(data.bounds.min) or not _vec(data.bounds.max): return _r(false,"layout_bounds")
	if not _v(data.bounds.min).is_equal_approx(Vector3(8.4,0,-2.1)) or not _v(data.bounds.max).is_equal_approx(Vector3(21.4,6.25,14.8)): return _r(false,"layout_extent")
	var ids: Dictionary={}
	for group in ["fixed","moving","pin_parts"]:
		if not data[group] is Array or data[group].is_empty() or data[group].size()>64: return _r(false,"layout_parts")
		for spec in data[group]:
			if not spec is Dictionary or not _exact(spec,["id","center","size","color","role"]) or not spec.id is String or spec.id.is_empty() or ids.has(spec.id) or not _vec(spec.center) or not _vec(spec.size) or not spec.color is String or not spec.role is String: return _r(false,"layout_part")
			if _v(spec.size).x<=0 or _v(spec.size).y<=0 or _v(spec.size).z<=0: return _r(false,"layout_size")
			for offset in [Vector3.ZERO,Vector3(0,-.3 if group=="pin_parts" else 0,8 if group!="fixed" else 0)]:
				var low: Vector3=_v(spec.center)+offset-_v(spec.size)*.5
				var high: Vector3=_v(spec.center)+offset+_v(spec.size)*.5
				for dimension in range(3):
					if low[dimension]<float(data.bounds.min[dimension])-.00001 or high[dimension]>float(data.bounds.max[dimension])+.00001: return _r(false,"layout_part_bounds")
			ids[spec.id]=group
	for id in {"BridgeDeck":"moving","BridgeHandle":"moving","LockRod":"pin_parts","LockGrip":"pin_parts","Relay":"fixed","PublicController":"fixed","ServiceController":"fixed","PublicSocketCantilever":"fixed","EastTrackPier0":"fixed"}:
		var expected: String="moving" if id in ["BridgeDeck","BridgeHandle"] else "pin_parts" if id in ["LockRod","LockGrip"] else "fixed"
		if ids.get(id)!=expected: return _r(false,"layout_required_part")
	if not data.routes is Dictionary or not _exact(data.routes,["public_short","service_short","public_bypass","service_bypass"]): return _r(false,"layout_routes")
	for route in data.routes.values():
		if not route is Array or route.size()<2 or route.size()>8: return _r(false,"route_points")
		for i in range(route.size()):
			if not route[i] is Array or route[i].size()!=2 or not _number(route[i][0],8,22) or not _number(route[i][1],-6,15): return _r(false,"route_point")
			if i>0 and route[i][0]!=route[i-1][0] and route[i][1]!=route[i-1][1]: return _r(false,"route_axis")
	if not data.labels is Array or data.labels.size()>4: return _r(false,"layout_labels")
	for row in data.labels:
		if not row is Dictionary or not _exact(row,["text","position","color"]) or not row.text is String or not row.color is String or not _vec(row.position): return _r(false,"layout_label")
	return _r(true,"valid")

static func _exact(value: Dictionary,keys: Array) -> bool:
	if value.size()!=keys.size(): return false
	for key in value:
		if not key is String or key not in keys: return false
	return true

static func _vec(value: Variant) -> bool:
	if not value is Array or value.size()!=3: return false
	for number in value:
		if not _number(number,-100,100): return false
	return true

static func _v(value: Array) -> Vector3:
	return Vector3(float(value[0]),float(value[1]),float(value[2]))

static func _number(value: Variant,low: float,high: float) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and float(value)>=low and float(value)<=high

static func _r(ok: bool,code: String) -> Dictionary:
	return {"ok":ok,"code":code}
