class_name TwinDistributionCabinet
extends Node3D
## Independent authority-owned graybox; no Story, saves, rewards or water.
## Every translated box checks its entire swept volume before changing pose.
const Axis = preload("res://scripts/v3/environment/twin_guided_axis.gd")
const FlightBody = preload("res://scripts/v2/flight_body.gd")
const PATH := "res://data/v3/terrain/i2_distribution_layout.json"
const COVER_ID := "I2:distribution_cover"
const RELAY_ID := "I2:distribution_relay"
const LOCK_ID := "I2:distribution_lock"
const GATE_ID := "I2:distribution_gate"
const PANEL_IDS := ["I2:distribution_outlet_a", "I2:distribution_outlet_b"]
const SAVE_KEYS := ["version", "layout_sha256", "serial", "axis", "door_fraction", "electric_latched", "cover_blocked", "door_blocked"]
const LAYOUT_KEYS := ["version", "id", "stage", "origin", "bounds", "fixed_solids", "cover", "door", "targets", "panels", "observation"]
const MAX_SERIAL := 9007199254740000
const MASK := 0xFFFFFFFF
const MARGIN := 0.001
var configured := false
var authority := true
var cover: StaticBody3D
var door: StaticBody3D
var fixed_bodies: Dictionary = {}
var target_bodies: Dictionary = {}
var panel_bodies: Dictionary = {}
var _layout: Dictionary = {}
var _state: Dictionary = {}
var _axis = Axis.new()
var _paused := false
var _pinned := false

func load_layout(saved: Dictionary = {}, is_authority: bool = true) -> Dictionary:
	if not FileAccess.file_exists(PATH): return _r(false, "layout_missing")
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(PATH))
	if not data is Dictionary: return _r(false, "layout_json")
	return configure(data, saved, is_authority)

func configure(data: Dictionary, saved: Dictionary = {}, is_authority: bool = true) -> Dictionary:
	if configured or is_inside_tree(): return _r(false, "configure_before_tree_once")
	var checked := _validate_layout(data)
	if not checked.ok: return checked
	var trial = Axis.new()
	checked = trial.configure(_axis_config(data))
	if not checked.ok: return checked
	var digest := JSON.stringify(data, "", true, true).sha256_text()
	var next := {"version":1, "layout_sha256":digest, "serial":0, "axis":trial.snapshot(),
		"door_fraction":0.0, "electric_latched":false, "cover_blocked":false, "door_blocked":false}
	if not saved.is_empty():
		checked = _check_snapshot(saved, digest, trial)
		if not checked.ok: return checked
		trial.restore(saved.axis, is_authority)
		next = _normalized(saved)
		next.axis = trial.snapshot()
	_layout = data.duplicate(true)
	_state = next
	_axis = trial
	authority = is_authority
	position = _v(data.origin)
	_build_geometry()
	configured = true
	set_process(false)
	set_physics_process(false)
	set_meta("stage", "independent_replaceable_graybox_not_registered")
	_sync_poses()
	return _r(true, "configured", true)

func _ready() -> void:
	if configured: _sync_poses()

func layout() -> Dictionary:
	return _layout.duplicate(true)

func snapshot() -> Dictionary:
	return _state.duplicate(true)

func validate_snapshot(raw: Variant) -> Dictionary:
	if not configured: return _r(false, "not_configured")
	return _check_snapshot(raw, str(_state.layout_sha256), _axis)

func apply_snapshot(raw: Variant) -> Dictionary:
	var checked := validate_snapshot(raw)
	if not checked.ok: return checked
	var trial = _axis.copy_for_trial()
	trial.restore(raw.axis, authority)
	var next := _normalized(raw)
	next.axis = trial.snapshot()
	var changed: bool = next != _state
	_axis = trial
	_state = next
	_pinned = false # Host must resample committed entities before accepting input.
	_sync_poses()
	return _r(true, "snapshot_applied" if changed else "unchanged", changed)

func set_simulation_paused(value: bool) -> Dictionary:
	if not configured: return _r(false, "not_configured")
	if authority and int(_state.serial) >= MAX_SERIAL: return _r(false, "serial_limit")
	_paused = value
	if not value or not authority: return _r(true, "paused" if value else "resumed")
	var stopped: Dictionary = _axis.stop()
	_publish_axis()
	return {"ok":true, "code":"paused", "cancelled":stopped.cancelled}

func synchronize_impulse_roster(players: Dictionary) -> Dictionary:
	var checked := _host_guard()
	if not checked.ok: return checked
	checked = _validate_players(players)
	if not checked.ok: return checked
	var result: Dictionary = _axis.set_active_peers(_active_peers(players))
	_publish_axis()
	return result

func reset_impulse_peer(peer: int) -> Dictionary:
	var checked := _host_guard()
	if not checked.ok: return checked
	var result: Dictionary = _axis.reset_peer(peer)
	if result.ok: _publish_axis()
	return result

func can_accept_impulse(id: String, impulse: Vector3, peer: int, action_serial: int) -> Dictionary:
	var checked := _host_guard()
	if not checked.ok: return checked
	if id != COVER_ID: return _r(false, "unknown_impulse_target")
	if _paused or _pinned: return _r(false, "mechanism_stopped")
	if not _poses_match(): return _r(false, "unauthorized_pose")
	return _axis.can_accept(impulse, peer, action_serial)

func apply_authorized_impulse(id: String, impulse: Vector3, peer: int, action_serial: int) -> Dictionary:
	var checked := can_accept_impulse(id, impulse, peer, action_serial)
	if not checked.ok: return checked
	var result: Dictionary = _axis.apply_impulse(impulse, peer, action_serial)
	_publish_axis()
	return result

func fixed_update(delta: float, entities: Dictionary, players: Dictionary, is_authority: bool = true) -> Dictionary:
	var checked := _host_guard()
	if not checked.ok: return checked
	if not is_authority: return _r(false, "not_authority")
	if not _number(delta, 0.0, 0.25): return _r(false, "delta_range")
	if delta == 0.0 or _paused: return _r(true, "paused")
	if not _poses_match(): return _r(false, "unauthorized_pose")
	checked = _inputs(entities, players)
	if not checked.ok: return checked
	var trial = _axis.copy_for_trial()
	var roster: Dictionary = trial.set_active_peers(_active_peers(players))
	var cancelled: Array = roster.cancelled.duplicate(true)
	if checked.pinned:
		var stopped: Dictionary = trial.stop()
		cancelled.append_array(stopped.cancelled)
	var proposed: Dictionary = trial.preview(delta)
	var start_cover := _cover_position(float(_state.axis.position_m))
	var finish_cover := _cover_position(float(proposed.position_m))
	var fraction := float(_state.door_fraction)
	if not _state.electric_latched and checked.motor_active:
		fraction = move_toward(fraction, 1.0, minf(delta, float(checked.remaining)) / float(_layout.door.stroke_seconds))
	var start_door := _door_position(float(_state.door_fraction))
	var finish_door := _door_position(fraction)
	var cover_moves: bool = start_cover != finish_cover
	var door_moves: bool = start_door != finish_door
	var cover_blocked: bool = cover_moves and not _sweep_clear(_v(_layout.cover.size), start_cover, finish_cover, [cover.get_rid()])
	var door_blocked: bool = door_moves and not _sweep_clear(_v(_layout.door.size), start_door, finish_door, [door.get_rid()])
	# Also compare both proposed swept boxes; scene queries see the old poses.
	if (cover_moves or door_moves) and _swept_box(_v(_layout.cover.size), start_cover, finish_cover).grow(MARGIN).intersects(_swept_box(_v(_layout.door.size), start_door, finish_door)):
		cover_blocked = cover_moves
		door_blocked = door_moves
	trial.advance(delta, cover_blocked)
	var next := _state.duplicate(true)
	next.axis = trial.snapshot()
	next.cover_blocked = cover_blocked
	next.door_blocked = door_blocked
	if not door_blocked: next.door_fraction = fraction
	next.electric_latched = float(next.door_fraction) == 1.0
	checked = _check_snapshot(next, str(_state.layout_sha256), trial)
	if not checked.ok: return checked
	_pinned = bool(entities[COVER_ID].pinned) and float(entities[COVER_ID].field_remaining) > 0.0
	_axis = trial
	var changed := _adopt_changed(next)
	_sync_poses()
	return {"ok":true, "code":"blocked" if cover_blocked or door_blocked else "advanced", "changed":changed,
		"cover_blocked":cover_blocked, "door_blocked":door_blocked, "cancelled":cancelled}

func target_definitions() -> Array:
	if not configured: return []
	return [
		{"id":COVER_ID,"name":"配流箱检修滑盖","position":entity_position(COVER_ID),"tags":["movable","fieldable","mechanical"],"pinned":false,"pinned_by":"","field_remaining":0.0,"revision":0},
		{"id":RELAY_ID,"name":"配流箱门供能器","position":entity_position(RELAY_ID),"tags":["conductive","electrical"],"charge":0.0,"charge_capacity":100.0,"power_threshold":20.0,"powered":false,"revision":0},
		{"id":LOCK_ID,"name":"配流箱检修门电锁","position":entity_position(LOCK_ID),"tags":["mechanical","hackable"],"controlled":false,"owner":"","takeover_remaining":0.0,"revision":0}]

func entity_position(id: String) -> Variant:
	if not configured or not target_bodies.has(id): return null
	var body: Node3D = target_bodies[id]
	return body.global_position if is_inside_tree() else transform * body.position

func observe_back(peer: int, body: Variant) -> Dictionary:
	# Caller only supplies trusted roster identity/body, never hit counts/position.
	var guarded := _host_guard()
	if not guarded.ok: return guarded
	if not _poses_match(): return _r(false, "unauthorized_pose")
	if not _validate_players({peer:body}).ok or not body.enabled or float(body.health) <= 0.0: return _r(false, "body_invalid")
	var info := _body_geometry(body)
	if not info.ok: return info
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = info.shape
	query.transform = info.transform
	query.collision_mask = MASK
	query.exclude = [body.get_rid()]
	query.margin = 0.0
	if not get_world_3d().direct_space_state.intersect_shape(query, 1).is_empty(): return _r(false, "body_occupied")
	var sensor: Vector3 = body.global_transform * _v(_layout.observation.sensor_offset)
	var local_sensor := to_local(sensor)
	var interior := _bounds_box(_layout.observation.interior)
	var local_body: AABB = (global_transform.affine_inverse() * info.transform) * AABB(-info.shape.size * 0.5, info.shape.size)
	var inside: bool = interior.encloses(local_body)
	var hits := {"manual":[0,0], "service_lock":[0,0]}
	var centers := {"manual":[false,false], "service_lock":[false,false]}
	var any_near := false
	for panel_index in range(2):
		var spec: Dictionary = _layout.panels[panel_index]
		var panel: StaticBody3D = panel_bodies[spec.id]
		var size := _v(spec.size)
		var front := _v(spec.center) + Vector3.BACK * size.z * 0.5
		var offsets := [Vector2.ZERO, Vector2(-0.25,-0.25), Vector2(0.25,-0.25), Vector2(-0.25,0.25), Vector2(0.25,0.25)]
		for sample_index in range(5):
			var offset: Vector2 = offsets[sample_index]
			var point := front + Vector3(offset.x * size.x, offset.y * size.y, 0)
			var endpoint := to_global(point)
			var sight := sensor - endpoint
			if sight.length() > float(_layout.observation.max_distance_m) or sight.length() < 0.0001: continue
			any_near = true
			if sight.normalized().dot(global_basis * Vector3.BACK) < float(_layout.observation.min_facing_dot): continue
			# Extend 2 mm into the physical panel; endpoint-on-surface rays are not robust.
			var ray := PhysicsRayQueryParameters3D.create(sensor, endpoint - sight.normalized()*0.002, MASK, [body.get_rid()])
			var hit := get_world_3d().direct_space_state.intersect_ray(ray)
			if hit.is_empty() or hit.get("rid") != panel.get_rid(): continue
			var method := _ray_method(local_sensor, point, inside)
			if method.is_empty(): continue
			hits[method][panel_index] += 1
			if sample_index == 0: centers[method][panel_index] = true
	for method in ["manual", "service_lock"]:
		if centers[method][0] and centers[method][1] and hits[method][0] >= int(_layout.observation.min_hits) and hits[method][1] >= int(_layout.observation.min_hits):
			return {"ok":true,"code":"back_observed","mechanism_serial":int(_state.serial),"method":method,
				"observer":[sensor.x,sensor.y,sensor.z],"cover_position_m":float(_state.axis.position_m),
				"door_fraction":float(_state.door_fraction),"electric_latched":bool(_state.electric_latched),
				"panel_hits":hits[method].duplicate(),"center_hits":centers[method].duplicate()}
	return {"ok":false,"code":"too_far" if not any_near else "back_covered" if float(_state.axis.position_m)==0.0 and float(_state.door_fraction)==0.0 else "observation_blocked", "panel_hits":hits, "center_hits":centers}

func _ray_method(start: Vector3, finish: Vector3, inside: bool) -> String:
	var well := _bounds_box(_layout.observation.well)
	if float(_state.axis.position_m)>0.0 and start.y>well.end.y and finish.y<well.position.y:
		if _crosses_y(start,finish,well.position.y,well) and _crosses_y(start,finish,well.end.y,well): return "manual"
	if float(_state.door_fraction)>0.0:
		if inside: return "service_lock"
		var opening := _bounds_box(_layout.observation.door_opening)
		var plane: float = float(_layout.door.center[2])
		if start.z>plane and finish.z<plane:
			var hit := start.lerp(finish,(start.z-plane)/(start.z-finish.z))
			if hit.x>opening.position.x and hit.x<opening.end.x and hit.y>opening.position.y and hit.y<opening.end.y: return "service_lock"
	return ""

static func _crosses_y(start: Vector3, finish: Vector3, y: float, opening: AABB) -> bool:
	var point := start.lerp(finish,(start.y-y)/(start.y-finish.y))
	return point.x>opening.position.x and point.x<opening.end.x and point.z>opening.position.z and point.z<opening.end.z

func _body_geometry(body: PhysicsBody3D) -> Dictionary:
	var shapes: Array = []
	for owner in body.get_shape_owners():
		if body.is_shape_owner_disabled(owner): continue
		for index in range(body.shape_owner_get_shape_count(owner)):
			shapes.append({"shape":body.shape_owner_get_shape(owner,index),"transform":body.global_transform*body.shape_owner_get_transform(owner)})
	if shapes.size()!=1 or not shapes[0].shape is BoxShape3D: return _r(false,"body_envelope_required")
	if not shapes[0].transform.is_finite(): return _r(false,"body_invalid")
	return {"ok":true,"shape":shapes[0].shape,"transform":shapes[0].transform}

func _inputs(entities: Dictionary, players: Dictionary) -> Dictionary:
	var checked := _validate_players(players)
	if not checked.ok: return checked
	for id in [COVER_ID,RELAY_ID,LOCK_ID]:
		if not entities.get(id) is Dictionary: return _r(false,"mechanism_entities_required")
	var mechanical: Dictionary = entities[COVER_ID]
	var relay: Dictionary = entities[RELAY_ID]
	var control: Dictionary = entities[LOCK_ID]
	if not mechanical.get("pinned") is bool or not _number(mechanical.get("field_remaining"),0,4): return _r(false,"pin_state")
	if not relay.get("powered") is bool: return _r(false,"power_state")
	if not control.get("controlled") is bool or not control.get("owner") is String or not _number(control.get("takeover_remaining"),0,8): return _r(false,"control_state")
	var source_ok := false
	for peer in players:
		if str(peer)==control.owner and players[peer].enabled and float(players[peer].health)>0.0: source_ok=true
	return {"ok":true,"code":"valid","pinned":bool(mechanical.pinned) and float(mechanical.field_remaining)>0.0,
		"motor_active":bool(relay.powered) and bool(control.controlled) and float(control.takeover_remaining)>0.0 and source_ok,"remaining":float(control.takeover_remaining)}

func _validate_players(players: Dictionary) -> Dictionary:
	if players.size()>2: return _r(false,"player_limit")
	for peer in players:
		var body: Variant = players[peer]
		if not peer is int or peer<=0 or peer>2147483647 or not body is FlightBody or not is_instance_valid(body): return _r(false,"real_player_required")
		if not body.is_inside_tree() or body.get_world_3d()!=get_world_3d() or (int(body.collision_layer)&2)==0 or not _body_geometry(body).ok: return _r(false,"player_world_or_shape")
		if not is_finite(float(body.health)): return _r(false,"player_health")
	return _r(true,"valid")

func _active_peers(players: Dictionary) -> Array:
	var peers: Array = []
	for peer in players:
		if players[peer].enabled and float(players[peer].health)>0.0: peers.append(peer)
	peers.sort()
	return peers

func _host_guard() -> Dictionary:
	if not configured or not is_inside_tree(): return _r(false,"world_required")
	if not authority: return _r(false,"not_authority")
	if not global_basis.is_equal_approx(Basis.IDENTITY) or not global_position.is_equal_approx(_v(_layout.origin)): return _r(false,"world_aligned_module_required")
	if int(_state.serial)>=MAX_SERIAL: return _r(false,"serial_limit")
	return _r(true,"valid")

func _poses_match() -> bool:
	return cover.transform.is_equal_approx(Transform3D(Basis.IDENTITY,_cover_position(float(_state.axis.position_m)))) and door.transform.is_equal_approx(Transform3D(Basis.IDENTITY,_door_position(float(_state.door_fraction))))

func _publish_axis() -> void:
	var next := _state.duplicate(true)
	next.axis = _axis.snapshot()
	_adopt_changed(next)

func _adopt_changed(next: Dictionary) -> bool:
	if next==_state: return false
	next.serial = int(_state.serial)+1
	_state = next
	return true

func _cover_position(distance: float) -> Vector3:
	return _v(_layout.cover.center)+Vector3.RIGHT*distance

func _door_position(fraction: float) -> Vector3:
	return _v(_layout.door.center)+Vector3.UP*float(_layout.door.travel_m)*fraction

static func _swept_box(size: Vector3, start: Vector3, finish: Vector3) -> AABB:
	var extent := size+(finish-start).abs()
	return AABB((start+finish)*0.5-extent*0.5,extent)

func _sweep_clear(size: Vector3, start: Vector3, finish: Vector3, excluded: Array[RID]) -> bool:
	var swept := _swept_box(size,start,finish)
	var shape := BoxShape3D.new()
	shape.size = swept.size
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = shape
	query.transform = global_transform*Transform3D(Basis.IDENTITY,swept.get_center())
	query.collision_mask = MASK
	query.exclude = excluded
	query.margin = MARGIN
	return get_world_3d().direct_space_state.intersect_shape(query,1).is_empty()

func _sync_poses() -> void:
	for pair in [[cover,_cover_position(float(_state.axis.position_m))],[door,_door_position(float(_state.door_fraction))]]:
		var body: StaticBody3D = pair[0]
		body.position = pair[1]
		if is_inside_tree():
			body.force_update_transform()
			PhysicsServer3D.body_set_state(body.get_rid(),PhysicsServer3D.BODY_STATE_TRANSFORM,body.global_transform)

func _build_geometry() -> void:
	for spec in _layout.fixed_solids:
		var box := _bounds_box(spec)
		fixed_bodies[spec.id] = _solid(spec.id,box.get_center(),box.size,Color(spec.color))
	cover = _solid("ManualCover",_cover_position(0),_v(_layout.cover.size),Color("ba9759"),8)
	cover.set_meta("entity_id",COVER_ID)
	door = _solid("ServiceGate",_door_position(0),_v(_layout.door.size),Color("4d9f9e"),8)
	door.set_meta("mechanism_id",GATE_ID)
	target_bodies[COVER_ID] = cover
	for spec in _layout.targets:
		var target := _solid(str(spec.id).replace(":","_"),_v(spec.center),_v(spec.size),Color(spec.color),8)
		target.set_meta("entity_id",spec.id)
		target_bodies[spec.id] = target
	for spec in _layout.panels:
		var target := _solid(str(spec.id).replace(":","_"),_v(spec.center),_v(spec.size),Color(spec.color),8)
		target.set_meta("observation_panel",spec.id)
		panel_bodies[spec.id] = target

func _solid(label: String, center: Vector3, size: Vector3, color: Color, layer: int = 1) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = label
	body.position = center
	body.collision_layer = layer
	body.collision_mask = 0
	var shape := BoxShape3D.new()
	shape.size = size
	var collision := CollisionShape3D.new()
	collision.shape = shape
	body.add_child(collision)
	var visual := MeshInstance3D.new()
	visual.name = "Visual"
	var mesh := BoxMesh.new()
	mesh.size = size
	visual.mesh = mesh
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.78
	visual.material_override = material
	body.add_child(visual)
	add_child(body)
	return body

static func _axis_config(data: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	for key in Axis.CONFIG_KEYS: result[key]=float(data.cover[key])
	return result

static func _check_snapshot(raw: Variant, digest: String, axis) -> Dictionary:
	if not raw is Dictionary or not _exact(raw,SAVE_KEYS): return _r(false,"snapshot_keys")
	if not _integer(raw.version,1,1) or not raw.layout_sha256 is String or raw.layout_sha256!=digest: return _r(false,"snapshot_version")
	if not _integer(raw.serial,0,MAX_SERIAL): return _r(false,"snapshot_serial")
	if not _number(raw.door_fraction,0,1): return _r(false,"snapshot_door")
	for key in ["electric_latched","cover_blocked","door_blocked"]:
		if not raw[key] is bool: return _r(false,"snapshot_flags")
	if raw.electric_latched != (float(raw.door_fraction)==1.0): return _r(false,"snapshot_latch")
	return axis.validate_snapshot(raw.axis)

static func _normalized(raw: Dictionary) -> Dictionary:
	var next := raw.duplicate(true)
	next.version=1
	next.serial=int(next.serial)
	next.door_fraction=float(next.door_fraction)
	return next

static func _validate_layout(data: Dictionary) -> Dictionary:
	if not _exact(data,LAYOUT_KEYS) or not _integer(data.version,1,1) or data.id!="i2_distribution_cabinet_v1" or not data.stage is String: return _r(false,"layout_schema")
	if not _vector(data.origin) or _v(data.origin)!=Vector3(18,0,-10) or not _bounds(data.bounds): return _r(false,"layout_origin")
	var outer := _bounds_box(data.bounds)
	if outer.position!=Vector3(-3,0,-3) or outer.end!=Vector3(3,7.2,3): return _r(false,"layout_scope")
	if not data.fixed_solids is Array or data.fixed_solids.size()<10 or data.fixed_solids.size()>48: return _r(false,"solid_limit")
	var ids: Dictionary = {}
	for spec in data.fixed_solids:
		if not spec is Dictionary or not _exact(spec,["id","min","max","color"]) or not spec.id is String or spec.id.is_empty() or ids.has(spec.id) or not _bounds(spec) or not _color(spec.color): return _r(false,"solid_shape")
		# Compare authored min/max directly. A float32 AABB min + (max-min)
		# can round an exactly shared boundary outward by one ULP.
		if not _within_bounds(spec,data.bounds): return _r(false,"solid_bounds")
		ids[spec.id]=true
	for id in ["ServiceFloor","LeftWall","RightWall","BackWall","DoorJambLeft","DoorJambRight","DoorTopStop","RoofLeft","RoofRight","RoofBack","RoofFront","UpperDeckLeft","UpperDeckRight","UpperDeckBack","UpperDeckFront"]:
		if not ids.has(id): return _r(false,"required_solid")
	if not data.cover is Dictionary or not _exact(data.cover,["center","size","travel_m","mass_kg","damping_per_second","max_speed_mps","max_impulse_ns"]): return _r(false,"cover_schema")
	if not _vector(data.cover.center) or not _vector(data.cover.size) or not _v(data.cover.center).is_equal_approx(Vector3(0,4.08,-1.45)) or not _v(data.cover.size).is_equal_approx(Vector3(1.2,0.16,1.9)): return _r(false,"cover_geometry")
	for pair in [["travel_m",1.2],["mass_kg",2.0],["damping_per_second",0.8],["max_speed_mps",2.0],["max_impulse_ns",9.0]]:
		if not _number(data.cover[pair[0]],pair[1],pair[1]): return _r(false,"cover_axis_contract")
	if not data.door is Dictionary or not _exact(data.door,["center","size","travel_m","stroke_seconds"]) or not _vector(data.door.center) or not _vector(data.door.size): return _r(false,"door_schema")
	if not _v(data.door.center).is_equal_approx(Vector3(0,2.605,1)) or not _v(data.door.size).is_equal_approx(Vector3(3.4,2.8,0.2)) or not _number(data.door.travel_m,3,3) or not _number(data.door.stroke_seconds,2,2): return _r(false,"door_contract")
	for key in ["targets","panels"]:
		if not data[key] is Array or data[key].size()!=2: return _r(false,"target_count")
		for index in range(2):
			var spec: Variant = data[key][index]
			var expected: String = PANEL_IDS[index] if key=="panels" else [RELAY_ID,LOCK_ID][index]
			if not spec is Dictionary or not _exact(spec,["id","center","size","color"]) or spec.id!=expected or not _vector(spec.center) or not _vector(spec.size) or not _color(spec.color): return _r(false,"target_schema")
			var size := _v(spec.size)
			if size.x<=0 or size.y<=0 or size.z<=0 or not outer.encloses(AABB(_v(spec.center)-size*0.5,size)): return _r(false,"target_bounds")
	var obs: Variant = data.observation
	if not obs is Dictionary or not _exact(obs,["sensor_offset","max_distance_m","min_facing_dot","min_hits","well","door_opening","interior"]): return _r(false,"observation_schema")
	if not _vector(obs.sensor_offset) or _v(obs.sensor_offset)!=Vector3.ZERO or not _number(obs.max_distance_m,4.5,4.5) or not _number(obs.min_facing_dot,0.35,0.35) or not _integer(obs.min_hits,3,3): return _r(false,"observation_contract")
	for key in ["well","door_opening","interior"]:
		if not _bounds(obs[key]) or not outer.encloses(_bounds_box(obs[key])): return _r(false,"observation_bounds")
	return _r(true,"valid")

static func _v(value: Array) -> Vector3:
	return Vector3(float(value[0]),float(value[1]),float(value[2]))

static func _number(value: Variant, low: float, high: float) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and float(value)>=low and float(value)<=high

static func _integer(value: Variant, low: int, high: int) -> bool:
	return _number(value,low,high) and floor(float(value))==float(value)

static func _vector(value: Variant) -> bool:
	return value is Array and value.size()==3 and _number(value[0],-100,100) and _number(value[1],-100,100) and _number(value[2],-100,100)

static func _bounds(value: Variant) -> bool:
	if not value is Dictionary or not _vector(value.get("min")) or not _vector(value.get("max")): return false
	var size := _v(value.max)-_v(value.min)
	return size.x>0 and size.y>0 and size.z>0

static func _bounds_box(value: Dictionary) -> AABB:
	return AABB(_v(value.min),_v(value.max)-_v(value.min))

static func _within_bounds(inner: Dictionary, outer: Dictionary) -> bool:
	for axis in range(3):
		if float(inner.min[axis])<float(outer.min[axis]) or float(inner.max[axis])>float(outer.max[axis]): return false
	return true

static func _exact(value: Dictionary, keys: Array) -> bool:
	if value.size()!=keys.size(): return false
	for key in value:
		if not key is String or key not in keys: return false
	return true

static func _color(value: Variant) -> bool:
	if not value is String or value.length()!=6: return false
	for character in value:
		if character not in "0123456789abcdefABCDEF": return false
	return true

static func _r(ok: bool, code: String, changed: bool = false) -> Dictionary:
	return {"ok":ok,"code":code,"changed":changed}
