class_name TwinClinicWaterworks
extends Node3D
## Independent replaceable graybox. No Session/Story/Store/network authority.
## Authority-integrated swept valve, selector and deck; water has no collider.
const GuidedAxis = preload("res://scripts/v3/environment/twin_guided_axis.gd")
const Runtime = preload("res://scripts/v3/environment/twin_clinic_water_runtime.gd")
const FlightBody = preload("res://scripts/v2/flight_body.gd")
const GravityArt = preload("res://scripts/v3/art/twin_clinic_gravity_art.gd")
const ReceptionArt = preload("res://scripts/v3/art/twin_clinic_reception_art.gd")
const GroundArt = preload("res://scripts/v3/art/twin_clinic_ground_art.gd")
const PumpArt = preload("res://scripts/v3/art/twin_clinic_pump_art.gd")
const WestServiceRoomArt = preload("res://scripts/v3/art/twin_west_service_room_art.gd")
const WestOffsetRoomArt = preload("res://scripts/v3/art/twin_west_offset_room_art.gd")
const WestLandingPlatformArt = preload("res://scripts/v3/art/twin_west_landing_platform_art.gd")
const LiftDeckArt = preload("res://scripts/v3/art/twin_clinic_lift_deck_art.gd")
const PATH := "res://data/v3/terrain/i2_clinic_layout.json"
const GRAVITY_ID := "I2:clinic_gravity_valve"
const PUMP_ID := "I2:clinic_pump"
const RELAY_ID := "I2:clinic_relay"
const MAX_DELTA := 0.25
const MAX_SERIAL := 9007199254740000
const SWEEP_MARGIN_M := 0.001
const SAVE_KEYS := ["schema_version", "layout_sha256", "runtime", "gravity_fraction", "gravity_speed", "pump_fraction", "pump_latched", "powered", "platform_blocked", "selector_blocked", "interlock_waiting", "gravity_pinned", "gravity_blocked", "axis", "serial"]
const LAYOUT_KEYS := ["schema_version", "id", "stage", "bounds", "fixed_solids", "tanks", "moving_parts", "gravity_valve", "pump_selector", "interlock_bolt", "anchors"]

var configured := false
var authority := true
var gravity_valve: StaticBody3D
var pump_selector: StaticBody3D
var interlock_bolt: StaticBody3D
var deck: StaticBody3D
var fixed_bodies: Dictionary = {}
var moving_bodies: Dictionary = {}
var water_surfaces: Dictionary = {}
var water_volumes: Dictionary = {}
var gravity_art: Dictionary = {}
var reception_art: Dictionary = {}
var ground_art: Dictionary = {}
var pump_art: Dictionary = {}
var west_service_room_art: Dictionary = {}
var west_offset_room_art: Dictionary = {}
var west_landing_platform_art: Dictionary = {}
var lift_deck_art: Dictionary = {}
var target_bodies: Dictionary = {}
var _layout: Dictionary = {}
var _state: Dictionary = {}
var _water = Runtime.new()
var _water_definition: Dictionary = {}
var _paused := false
var _lamps: Dictionary = {}
var _axis = GuidedAxis.new()

func load_layout(saved: Dictionary = {}, is_authority: bool = true) -> Dictionary:
	if not FileAccess.file_exists(PATH): return _result(false, "layout_missing")
	var raw: Variant = JSON.parse_string(FileAccess.get_file_as_string(PATH))
	if not raw is Dictionary: return _result(false, "layout_json")
	var checked := configure(raw, saved, is_authority)
	if not checked.ok: return checked
	gravity_art = GravityArt.install(self)
	if not gravity_art.ok: return _result(false, str(gravity_art.code))
	reception_art = ReceptionArt.install(self)
	if not reception_art.ok: return _result(false, str(reception_art.code))
	ground_art = GroundArt.install(self)
	if not ground_art.ok: return _result(false, str(ground_art.code))
	pump_art = PumpArt.install(self)
	if not pump_art.ok: return _result(false, str(pump_art.code))
	west_service_room_art = WestServiceRoomArt.install(self)
	if not west_service_room_art.ok: return _result(false, str(west_service_room_art.code))
	west_offset_room_art = WestOffsetRoomArt.install(self)
	if not west_offset_room_art.ok: return _result(false, str(west_offset_room_art.code))
	west_landing_platform_art = WestLandingPlatformArt.install(self)
	if not west_landing_platform_art.ok: return _result(false, str(west_landing_platform_art.code))
	lift_deck_art = LiftDeckArt.install(self)
	if not lift_deck_art.ok: return _result(false, str(lift_deck_art.code))
	set_service_available(false)
	set_meta("terrain_stage", "authored_gravity_reception_pump_with_remaining_graybox")
	return _result(true, "clinic_layout_and_art_ready", true)

func set_service_available(available: bool) -> void:
	# Presentation follows validated, committed history. Water depth alone is
	# insufficient: access and the reception confirmation must also be complete.
	ReceptionArt.set_service_available(reception_art, available)

func configure(data: Dictionary, saved: Dictionary = {}, is_authority: bool = true) -> Dictionary:
	if configured or is_inside_tree(): return _result(false, "configure_before_tree_once")
	var checked := _validate_layout(data)
	if not checked.ok: return checked
	var candidate = Runtime.new()
	checked = candidate.load_definition()
	if not checked.ok: return checked
	var digest := JSON.stringify(data, "", true, true).sha256_text()
	var axis = GuidedAxis.new()
	checked = axis.configure(_axis_config(data))
	if not checked.ok: return checked
	var next := {"schema_version":2, "layout_sha256":digest, "runtime":candidate.snapshot(),
		"gravity_fraction":0.0, "gravity_speed":0.0, "pump_fraction":0.0, "pump_latched":false,
		"powered":false, "platform_blocked":false, "selector_blocked":false,
		"interlock_waiting":false, "gravity_pinned":false, "gravity_blocked":false, "axis":axis.snapshot(), "serial":0}
	if not saved.is_empty():
		checked = _check_saved(saved, candidate, digest, float(data.gravity_valve.open_epsilon), _interlock_closed_fraction(data), axis)
		if not checked.ok: return checked
		checked = candidate.restore(saved.runtime)
		if not checked.ok: return checked
		next = _normalize(saved)
		next.runtime = candidate.snapshot()
		axis.restore(saved.axis, is_authority)
		next.axis = axis.snapshot()
		next.gravity_speed = float(next.axis.velocity_mps)
	_axis = axis
	_layout = data.duplicate(true)
	_state = next
	_water = candidate
	_water_definition = candidate.definitions()
	authority = is_authority
	_build_geometry()
	configured = true
	set_meta("terrain_stage", "independent_replaceable_graybox")
	set_process(false)
	set_physics_process(false)
	_sync_poses(true)
	return _result(true, "independent_graybox_ready", true)

func _ready() -> void:
	if configured: _sync_poses(true)

static func _axis_config(data: Dictionary) -> Dictionary:
	return {"travel_m":float(data.gravity_valve.travel[0]), "mass_kg":float(data.gravity_valve.mass_kg),
		"damping_per_second":float(data.gravity_valve.damping_per_second),
		"max_speed_mps":float(data.gravity_valve.max_speed_mps), "max_impulse_ns":9.0}

func layout() -> Dictionary:
	return _layout.duplicate(true)

func snapshot() -> Dictionary:
	return _state.duplicate(true)

func apply_snapshot(raw: Variant) -> Dictionary:
	if not configured: return _result(false, "not_configured")
	var checked := _check_saved(raw, _water, str(_state.layout_sha256), float(_layout.gravity_valve.open_epsilon), _interlock_closed_fraction(_layout), _axis)
	if not checked.ok: return checked
	if raw == _state and (not authority or float(_state.gravity_speed) == 0.0):
		_axis.restore(raw.axis, authority)
		return _result(true, "unchanged")
	checked = _water.restore(raw.runtime)
	if not checked.ok: return checked
	_state = _normalize(raw)
	_state.runtime = _water.snapshot()
	_axis.restore(raw.axis, authority)
	_state.axis = _axis.snapshot()
	_state.gravity_speed = float(_state.axis.velocity_mps)
	_sync_poses(true)
	return _result(true, "snapshot_applied", true)

# Explicit stop cancels accepted momentum; no queued force is released later.
# Returned identities are feedback only; Session owns energy/transaction policy.
func set_simulation_paused(value: bool) -> Dictionary:
	if not configured: return _result(false, "not_configured")
	_paused = value
	var result := {"ok":true, "code":"resumed", "cancelled":[]}
	if value and authority:
		result = _axis.stop()
		_state.axis = _axis.snapshot()
		_state.gravity_speed = 0.0
	return result

func reset_impulse_peer(peer_id: int) -> Dictionary:
	if not configured or not authority: return _result(false, "not_authority")
	var result: Dictionary = _axis.reset_peer(peer_id)
	if not result.ok: return result
	_state.axis = _axis.snapshot()
	_state.gravity_speed = float(_state.axis.velocity_mps)
	return result

func synchronize_impulse_roster(players: Dictionary) -> Dictionary:
	if not configured or not is_inside_tree(): return _result(false, "world_required")
	if not authority: return _result(false, "not_authority")
	var checked := _validate_players(players)
	if not checked.ok: return checked
	var peers: Array = []
	for peer in players:
		if players[peer].enabled: peers.append(peer)
	var result: Dictionary = _axis.set_active_peers(peers)
	_state.axis = _axis.snapshot()
	_state.gravity_speed = float(_state.axis.velocity_mps)
	return result

func can_accept_impulse(entity_id: String, impulse: Vector3, peer_id: int, action_serial: int) -> Dictionary:
	if not configured or not is_inside_tree(): return _result(false, "world_required")
	if not authority: return _result(false, "not_authority")
	if entity_id != GRAVITY_ID: return _result(false, "unknown_impulse_target")
	if _paused or bool(_state.gravity_pinned): return _result(false, "mechanism_stopped")
	if not global_transform.is_equal_approx(Transform3D.IDENTITY): return _result(false, "world_aligned_module_required")
	return _axis.can_accept(impulse, peer_id, action_serial)

func apply_authorized_impulse(entity_id: String, impulse: Vector3, peer_id: int, action_serial: int) -> Dictionary:
	var checked := can_accept_impulse(entity_id, impulse, peer_id, action_serial)
	if not checked.ok: return checked
	var result: Dictionary = _axis.apply_impulse(impulse, peer_id, action_serial)
	_state.gravity_blocked = false
	_state.axis = _axis.snapshot()
	_state.gravity_speed = float(_state.axis.velocity_mps)
	return result

func target_definitions() -> Array:
	if not configured: return []
	return [
		{"id":GRAVITY_ID, "name":"高位清水旁路滑阀", "position":entity_position(GRAVITY_ID),
			"tags":["movable", "fieldable", "mechanical"], "pinned":false, "pinned_by":"", "field_remaining":0.0, "revision":0},
		{"id":PUMP_ID, "name":"病房供水选择阀", "position":entity_position(PUMP_ID),
			"tags":["mechanical", "hackable"], "controlled":false, "owner":"", "takeover_remaining":0.0, "revision":0},
		{"id":RELAY_ID, "name":"病房泵继电器", "position":entity_position(RELAY_ID),
			"tags":["conductive", "electrical"], "charge":0.0, "charge_capacity":100.0, "power_threshold":20.0, "powered":false, "revision":0}
	]

func entity_position(id: String) -> Variant:
	if not configured or not target_bodies.has(id): return null
	var body: Node3D = target_bodies[id]
	return body.global_position if body.is_inside_tree() else body.position

func anchor_position(id: String) -> Variant:
	if not configured or not _layout.anchors.has(id): return null
	return to_global(_v(_layout.anchors[id])) if is_inside_tree() else transform * _v(_layout.anchors[id])

func water_level(id: String) -> Variant:
	if not configured or not _layout.tanks.has(id): return null
	return float(_water.get_node(id).level_m)

func contains_water(world_point: Vector3) -> bool:
	if not configured or not world_point.is_finite(): return false
	var point := to_local(world_point) if is_inside_tree() else transform.affine_inverse() * world_point
	for id in _layout.tanks:
		var tank: Dictionary = _layout.tanks[id]
		var node: Dictionary = _water.get_node(id)
		if int(node.volume_ml) == 0: continue
		var half := _v(tank.inner_size) * 0.5
		if absf(point.x-float(tank.center_xz[0])) < half.x and absf(point.z-float(tank.center_xz[1])) < half.z and point.y >= float(tank.base_y) and point.y < float(node.level_m): return true
	return false

func status() -> Dictionary:
	if not configured: return {}
	var result: Dictionary = _water.status()
	result["deck_top_y"] = deck.position.y + float(_layout.moving_parts[0].size[1]) * 0.5
	for key in ["gravity_fraction", "pump_fraction", "pump_latched", "powered", "platform_blocked", "selector_blocked", "interlock_waiting", "gravity_pinned", "gravity_blocked", "gravity_speed", "serial"]:
		result[key] = _state[key]
	return result

func fixed_update(delta: float, entities: Dictionary, players: Dictionary, is_authority: bool = true) -> Dictionary:
	if not configured or not is_inside_tree(): return _result(false, "world_required")
	if not authority or not is_authority: return _result(false, "not_authority")
	if not is_finite(delta) or delta < 0.0 or delta > MAX_DELTA: return _result(false, "delta_range")
	if delta == 0.0:
		set_simulation_paused(true)
		return _result(true, "paused")
	if not global_transform.is_equal_approx(Transform3D.IDENTITY): return _result(false, "world_aligned_module_required")
	if int(_state.serial) >= MAX_SERIAL: return _result(false, "serial_limit")
	var checked := _read_inputs(entities, players)
	if not checked.ok: return checked
	var sample := _sample_gravity()
	if not sample.ok: return sample
	var next: Dictionary = _state.duplicate(true)
	var axis = _axis.copy_for_trial()
	var peers: Array = []
	for peer in players:
		if players[peer].enabled: peers.append(peer)
	axis.set_active_peers(peers)
	if checked.pinned: axis.stop()
	var proposal: Dictionary = axis.preview(delta)
	if not proposal.ok: return proposal
	var start := gravity_valve.position
	var finish := _v(_layout.gravity_valve.center) + Vector3.RIGHT * float(proposal.position_m)
	var gravity_blocked := start != finish and not _box_sweep_clear(_v(_layout.gravity_valve.size), start, finish, [gravity_valve.get_rid()])
	axis.advance(delta, gravity_blocked)
	next.axis = axis.snapshot()
	next.gravity_fraction = float(next.axis.position_m) / float(_layout.gravity_valve.travel[0])
	next.gravity_speed = float(next.axis.velocity_mps)
	next.gravity_blocked = gravity_blocked
	next.gravity_pinned = bool(checked.pinned)
	next.powered = bool(checked.powered)
	next.selector_blocked = false
	next.interlock_waiting = false
	var epsilon := float(_layout.gravity_valve.open_epsilon)
	var closed_fraction := _interlock_closed_fraction(_layout)
	if float(next.pump_fraction) > 0.0 and float(next.gravity_fraction) > closed_fraction: return _result(false, "mechanical_interlock_violation")
	if not next.pump_latched and checked.motor_active:
		if float(next.gravity_fraction) > closed_fraction:
			next.interlock_waiting = true
		else:
			var motor_delta := minf(delta, float(checked.signal_remaining))
			var goal := move_toward(float(next.pump_fraction), 1.0, motor_delta / float(_layout.pump_selector.stroke_seconds))
			var selector_start := pump_selector.position
			var selector_finish := _v(_layout.pump_selector.center) + _v(_layout.pump_selector.travel) * goal
			# Both actuators commit together. The high crossbolt travels 1.4 m on
			# first engagement; checking only the low selector would teleport it
			# through players/props. Include the bolt's complete path and endpoint.
			var bolt_finish := _bolt_position(goal)
			var bolt_clear := interlock_bolt.position.is_equal_approx(bolt_finish) or _box_sweep_clear(_v(_layout.interlock_bolt.size), interlock_bolt.position, bolt_finish, [interlock_bolt.get_rid()])
			var bolt_swept := AABB((interlock_bolt.position+bolt_finish)*0.5-(_v(_layout.interlock_bolt.size)+(bolt_finish-interlock_bolt.position).abs())*0.5, _v(_layout.interlock_bolt.size)+(bolt_finish-interlock_bolt.position).abs())
			var valve_proposed := AABB(finish-_v(_layout.gravity_valve.size)*0.5, _v(_layout.gravity_valve.size))
			if gravity_blocked: valve_proposed.position = start-_v(_layout.gravity_valve.size)*0.5
			bolt_clear = bolt_clear and not bolt_swept.grow(0.001).intersects(valve_proposed)
			if bolt_clear and _box_sweep_clear(_v(_layout.pump_selector.size), selector_start, selector_finish, [pump_selector.get_rid()]):
				next.pump_fraction = goal
				next.pump_latched = goal == 1.0
			else: next.selector_blocked = true
	var facts := _facts_for(next, false)
	var candidate = _clone_water()
	if candidate == null: return _result(false, "candidate_water")
	var advanced: Dictionary = candidate.step(delta, facts)
	if not advanced.ok: return advanced
	var start_top := float(_water.status().desired_deck_top_m)
	var end_top := float(candidate.status().desired_deck_top_m)
	var blocked := not is_equal_approx(start_top, end_top) and not _lift_sweep_clear(start_top, end_top)
	if blocked:
		# Discard ALL speculative water and clocks. Replay from the original with
		# the safety inlet closed, so an obstructed board never lags a higher tank.
		candidate = _clone_water()
		if candidate == null: return _result(false, "candidate_water")
		advanced = candidate.step(delta, _facts_for(next, true))
		if not advanced.ok: return advanced
	next.platform_blocked = blocked
	next.runtime = candidate.snapshot()
	next.serial = int(next.serial) + 1
	checked = _check_saved(next, _water, str(_state.layout_sha256), epsilon, closed_fraction, axis)
	if not checked.ok: return checked
	_state = next
	_water = candidate
	_axis = axis
	_paused = false
	_sync_poses(true)
	return {"ok":true, "code":"platform_blocked" if blocked else "advanced", "changed":true,
		"moved_ml":int(advanced.moved_ml), "gravity_blocked":gravity_blocked, "selector_blocked":bool(next.selector_blocked), "interlock_waiting":bool(next.interlock_waiting)}

func _clone_water():
	var candidate = Runtime.new()
	if not candidate.configure(_water_definition).ok or not candidate.restore(_water.snapshot()).ok: return null
	return candidate

func _facts_for(state: Dictionary, blocked: bool) -> Dictionary:
	var epsilon := float(_layout.gravity_valve.open_epsilon)
	return {"gravity_open_permille":1000 if float(state.gravity_fraction) >= 1.0-epsilon else 0,
		"pump_open_permille":1000 if state.pump_latched else 0,
		"pump_powered":bool(state.powered), "platform_blocked":blocked}

func _validate_players(players: Dictionary) -> Dictionary:
	if players.size() > 2: return _result(false, "player_limit")
	for peer in players:
		var body: Variant = players[peer]
		if not peer is int or peer <= 0 or peer > 2147483647 or not body is FlightBody or not is_instance_valid(body) or not body.is_inside_tree() or body.get_world_3d() != get_world_3d(): return _result(false, "real_player_required")
		if body.get_shape_owners().is_empty() or (int(body.collision_layer) & 2) == 0: return _result(false, "player_shape_required")
	return _result(true, "valid")

func _read_inputs(entities: Dictionary, players: Dictionary) -> Dictionary:
	var checked := _validate_players(players)
	if not checked.ok: return checked
	for id in [GRAVITY_ID, PUMP_ID, RELAY_ID]:
		if not entities.get(id) is Dictionary: return _result(false, "mechanism_entities_required")
	var mechanical: Dictionary = entities[GRAVITY_ID]
	var control: Dictionary = entities[PUMP_ID]
	var relay: Dictionary = entities[RELAY_ID]
	if not mechanical.get("pinned") is bool or not _number(mechanical.get("field_remaining"), 0.0, 4.0): return _result(false, "pin_state")
	if not control.get("controlled") is bool or not control.get("owner") is String or not _number(control.get("takeover_remaining"), 0.0, 8.0): return _result(false, "control_state")
	if not relay.get("powered") is bool: return _result(false, "power_state")
	var source_ok := false
	for peer in players:
		if str(peer) == str(control.owner) and players[peer].enabled: source_ok = true
	return {"ok":true, "code":"valid", "pinned":bool(mechanical.pinned) and float(mechanical.field_remaining)>0.0,
		"powered":bool(relay.powered), "signal_remaining":float(control.takeover_remaining),
		"motor_active":bool(control.controlled) and float(control.takeover_remaining)>0.0 and source_ok and bool(relay.powered)}

func _sample_gravity() -> Dictionary:
	# Detect external body edits rather than silently correcting an escaped body.
	var expected := _v(_layout.gravity_valve.center)+Vector3.RIGHT*float(_state.axis.position_m)
	var relative := gravity_valve.position-_v(_layout.gravity_valve.center)
	var travel := float(_layout.gravity_valve.travel[0])
	if not gravity_valve.position.is_finite() or relative.x < -0.005 or relative.x > travel+0.005 or absf(relative.y)>0.005 or absf(relative.z)>0.005: return _result(false, "valve_off_rail")
	if gravity_valve.position.distance_to(expected)>0.000002: return _result(false, "valve_pose_changed_externally")
	return _result(true, "valid")

func _lift_sweep_clear(from_top: float, to_top: float) -> bool:
	var excluded: Array[RID] = []
	for body in moving_bodies.values(): excluded.append(body.get_rid())
	# These two precisely adjacent bearing slabs share the x=+-2 side plane.
	# Their authored extents are locked below; touching those bearings is allowed.
	# All other static terrain, players and props remain in the sweep mask.
	excluded.append(fixed_bodies.WestLanding.get_rid())
	excluded.append(fixed_bodies.EastLanding.get_rid())
	for part in _layout.moving_parts:
		var offset := _v(part.offset)
		if not _box_sweep_clear(_v(part.size), offset+Vector3.UP*from_top, offset+Vector3.UP*to_top, excluded): return false
	return true

func _box_sweep_clear(size: Vector3, start: Vector3, finish: Vector3, excluded: Array[RID]) -> bool:
	# Every actuator in this contract translates along exactly one axis; the
	# expanded box is its continuous swept solid, including start and endpoint.
	var shape := BoxShape3D.new()
	shape.size = size + (finish-start).abs()
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = shape
	query.transform = global_transform * Transform3D(Basis.IDENTITY, (start+finish)*0.5)
	query.collision_mask = 1 | 2 | 8 | 32
	query.exclude = excluded
	query.margin = SWEEP_MARGIN_M
	return get_world_3d().direct_space_state.intersect_shape(query, 1).is_empty()

func _sync_poses(include_gravity: bool) -> void:
	var top := float(_water.status().desired_deck_top_m)
	for part in _layout.moving_parts:
		_position_body(moving_bodies[part.id], _v(part.offset)+Vector3.UP*top)
	_position_body(pump_selector, _v(_layout.pump_selector.center)+_v(_layout.pump_selector.travel)*float(_state.pump_fraction))
	_position_body(interlock_bolt, _bolt_position(float(_state.pump_fraction)))
	if include_gravity:
		_position_body(gravity_valve, _v(_layout.gravity_valve.center)+_v(_layout.gravity_valve.travel)*float(_state.gravity_fraction))
	for id in water_surfaces:
		var node: Dictionary = _water.get_node(id)
		water_surfaces[id].position.y = float(node.level_m)
		water_surfaces[id].visible = int(node.volume_ml)>0
		var depth := maxf(0.0, float(node.level_m) - float(_layout.tanks[id].base_y))
		var volume: MeshInstance3D = water_volumes[id]
		# The surface is 2 mm above the opaque volume's top: no coplanar faces,
		# no stacked transparency, and no collision or extra simulated capacity.
		volume.position.y = float(_layout.tanks[id].base_y) + depth * 0.5
		volume.scale.y = maxf(0.0001, depth - 0.004)
		volume.visible = depth > 0.004
	_lamps.gravity.material_override.albedo_color = Color("6cd5ac") if float(_state.gravity_fraction)>=0.995 else Color("c2a66b")
	_lamps.pump.material_override.albedo_color = Color("6cd5ac") if _state.pump_latched and _state.powered else Color("d89b5b") if _state.selector_blocked or _state.interlock_waiting else Color("698287")
	_lamps.deck.material_override.albedo_color = Color("d58753") if _state.platform_blocked else Color("67bcae")

func _bolt_position(pump_fraction: float) -> Vector3:
	var at := _v(_layout.interlock_bolt.center)
	if pump_fraction == 0.0: at += _v(_layout.interlock_bolt.park_offset)
	return at

static func _interlock_closed_fraction(data: Dictionary) -> float:
	# Actual 10 mm closed gap minus the same 1 mm sweep margin. Controlled
	# motion needs no solver overshoot budget. This is NOT the 99.5% flow detent.
	var valve_right: float = float(data.gravity_valve.center[0]) + float(data.gravity_valve.size[0]) * 0.5
	var bolt_left: float = float(data.interlock_bolt.center[0]) - float(data.interlock_bolt.size[0]) * 0.5
	return (bolt_left-valve_right-SWEEP_MARGIN_M) / float(data.gravity_valve.travel[0])

func _position_body(body: PhysicsBody3D, at: Vector3) -> void:
	body.position = at
	if body.is_inside_tree():
		body.force_update_transform()
		PhysicsServer3D.body_set_state(body.get_rid(), PhysicsServer3D.BODY_STATE_TRANSFORM, body.global_transform)

func _build_geometry() -> void:
	for spec in _layout.fixed_solids:
		var box := AABB(_v(spec.min), _v(spec.max)-_v(spec.min))
		fixed_bodies[spec.id] = _solid(spec.id, box.get_center(), box.size, Color(spec.color))
	for id in _layout.tanks: _build_tank(id, _layout.tanks[id])
	for part in _layout.moving_parts:
		moving_bodies[part.id] = _solid(part.id, Vector3.ZERO, _v(part.size), Color(part.color))
	deck = moving_bodies.Deck
	gravity_valve = _solid("GravityValve", Vector3.ZERO, _v(_layout.gravity_valve.size), Color("bda16a"), 8)
	gravity_valve.set_meta("entity_id", GRAVITY_ID)
	pump_selector = _solid("PumpSelector", Vector3.ZERO, _v(_layout.pump_selector.size), Color("d1b47a"), 8)
	pump_selector.set_meta("entity_id", PUMP_ID)
	interlock_bolt = _solid("InterlockBolt", Vector3.ZERO, _v(_layout.interlock_bolt.size), Color("e1b15c"))
	var relay := _solid("PumpRelay", _v(_layout.anchors.pump_relay), Vector3(0.4,0.7,0.35), Color("4c9f9c"), 8)
	relay.set_meta("entity_id", RELAY_ID)
	target_bodies = {GRAVITY_ID:gravity_valve, PUMP_ID:pump_selector, RELAY_ID:relay}
	_build_markings()

func _build_tank(id: String, spec: Dictionary) -> void:
	var size := _v(spec.inner_size)
	var center := Vector3(float(spec.center_xz[0]),float(spec.base_y),float(spec.center_xz[1]))
	var t := float(spec.wall)
	var label := "Cistern" if id == Runtime.SOURCE else "ClinicTank"
	_solid(label+"Floor",center-Vector3.UP*t*0.5,Vector3(size.x+2*t,t,size.z+2*t),Color("658181"))
	for side in [-1.0,1.0]:
		_solid(label+("Left" if side<0 else "Right"),center+Vector3(side*(size.x+t)*0.5,size.y*0.5,0),Vector3(t,size.y,size.z+2*t),Color("6e8988"))
		var wall := _solid(label+("Back" if side<0 else "Window"),center+Vector3(0,size.y*0.5,side*(size.z+t)*0.5),Vector3(size.x,size.y,t),Color("85b0b1"))
		if side > 0:
			var glass := wall.get_node("Visual").material_override as StandardMaterial3D
			glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			glass.albedo_color.a = 0.28
	# Clinic support legs/cap beams are explicit layout solids. Their 2.52 m
	# inner width leaves the unchanged HX02 envelope a real northward exit.
	var surface := MeshInstance3D.new()
	surface.name = label+"WaterSurface"
	var mesh := PlaneMesh.new()
	mesh.size = Vector2(size.x,size.z)
	surface.mesh = mesh
	surface.position = center
	var material := _material(Color("389baf"))
	material.roughness = 0.35
	surface.material_override = material
	add_child(surface)
	water_surfaces[id] = surface
	var volume := MeshInstance3D.new()
	volume.name = label + "WaterVolume"
	var volume_mesh := BoxMesh.new()
	volume_mesh.size = Vector3(size.x-0.004, 1.0, size.z-0.004)
	volume.mesh = volume_mesh
	volume.position = center
	volume.material_override = material
	add_child(volume)
	water_volumes[id] = volume

func _build_markings() -> void:
	var marks := Node3D.new()
	marks.name = "GrayboxNavigation"
	marks.set_meta("terrain_visibility_keep", true)
	add_child(marks)
	for x in [-8.55,-5.45]: _paint(marks,"PumpEntryLine",Vector3(x,0.404,10.1),Vector3(0.07,0.005,3.8),Color("b9be95"))
	for z in [-5.75,-2.25]:
		_paint(marks,"WestBearingLine",Vector3(-3,5.004,z),Vector3(1.8,0.005,0.07),Color("c9c6a0"))
		_paint(marks,"EastBearingLine",Vector3(3,5.004,z),Vector3(1.8,0.005,0.07),Color("c9c6a0"))
	for y in [3.5,4.0,4.5,5.0]: _paint(marks,"WaterLevelScale",Vector3(0,y,-7.372),Vector3(1.7,0.025,0.005),Color("d3d0b1"))
	for row in [[Vector3(-10.5,0.405,9),Vector3(0.9,0.006,0.5)],[Vector3(-3.3,0.405,5.2),Vector3(0.6,0.006,0.85)]]:
		_paint(marks,"DryWaterStain",row[0],row[1],Color("354f59"))
	_lamps.gravity = _paint(marks,"GravityDetentLamp",Vector3(-6.1,7.15,-5),Vector3(0.15,0.12,0.16),Color("b59d66"))
	_lamps.pump = _paint(marks,"PumpStateLamp",Vector3(-5.75,1.65,7),Vector3(0.15,0.12,0.12),Color("769a94"))
	_lamps.deck = _paint(marks,"LiftSafetyLamp",Vector3(1.78,7.18,-7.2),Vector3(0.18,0.12,0.18),Color("769a94"))

func _solid(label: String, at: Vector3, size: Vector3, color: Color, layer: int = 1) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = label
	body.position = at
	body.collision_layer = layer
	body.collision_mask = 0
	add_child(body)
	_add_box_shape_and_mesh(body,size,color)
	return body

func _add_box_shape_and_mesh(body: PhysicsBody3D, size: Vector3, color: Color) -> void:
	_paint(body,"Visual",Vector3.ZERO,size,color)
	var shape := BoxShape3D.new()
	shape.size = size
	var collider := CollisionShape3D.new()
	collider.name = "ExactBoxCollision"
	collider.shape = shape
	body.add_child(collider)

func _paint(parent: Node3D, label: String, at: Vector3, size: Vector3, color: Color) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	var visual := MeshInstance3D.new()
	visual.name = label
	visual.position = at
	visual.mesh = mesh
	visual.material_override = _material(color)
	parent.add_child(visual)
	return visual

static func _material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.8
	return material

func _check_saved(raw: Variant, water, digest: String, epsilon: float, closed_fraction: float, axis) -> Dictionary:
	if not raw is Dictionary or not _exact(raw,SAVE_KEYS): return _result(false,"snapshot_keys")
	if not _integer(raw.schema_version,2,2) or raw.layout_sha256 != digest or not _integer(raw.serial,0,MAX_SERIAL): return _result(false,"snapshot_version")
	if not _number(raw.gravity_fraction,0,1) or not _number(raw.pump_fraction,0,1) or not _number(raw.gravity_speed,-6,6): return _result(false,"snapshot_pose")
	for key in ["pump_latched","powered","platform_blocked","selector_blocked","interlock_waiting","gravity_pinned","gravity_blocked"]:
		if not raw[key] is bool: return _result(false,"snapshot_flag")
	if raw.pump_latched != (float(raw.pump_fraction)==1.0): return _result(false,"snapshot_detent")
	if float(raw.pump_fraction)>0.0 and float(raw.gravity_fraction)>closed_fraction: return _result(false,"snapshot_interlock")
	if (raw.gravity_pinned or raw.gravity_blocked) and float(raw.gravity_speed)!=0.0: return _result(false,"snapshot_pinned_velocity")
	var axis_checked: Dictionary = axis.validate_snapshot(raw.axis)
	if not axis_checked.ok: return axis_checked
	if absf(float(raw.axis.position_m)-float(raw.gravity_fraction)*1.2)>0.000000001 or float(raw.axis.velocity_mps)!=float(raw.gravity_speed): return _result(false,"snapshot_axis_mismatch")
	if not raw.runtime is Dictionary: return _result(false,"snapshot_water")
	var checked: Dictionary = water.validate_snapshot(raw.runtime)
	if not checked.ok: return checked
	var facts: Dictionary = raw.runtime.facts
	if int(facts.gravity_open_permille)!=(1000 if float(raw.gravity_fraction)>=1.0-epsilon else 0) or int(facts.pump_open_permille)!=(1000 if raw.pump_latched else 0) or facts.pump_powered!=raw.powered or facts.platform_blocked!=raw.platform_blocked: return _result(false,"snapshot_actuator_water_mismatch")
	return _result(true,"valid")

func _normalize(raw: Dictionary) -> Dictionary:
	var out: Dictionary = raw.duplicate(true)
	out.schema_version = int(out.schema_version)
	out.serial = int(out.serial)
	for key in ["gravity_fraction","gravity_speed","pump_fraction"]: out[key]=float(out[key])
	return out

func _validate_layout(data: Dictionary) -> Dictionary:
	if not _exact(data,LAYOUT_KEYS) or data.schema_version!=1 or data.id!="i2_clinic_waterworks_v1": return _result(false,"layout_schema")
	if not data.stage is String or not _bounds(data.bounds): return _result(false,"layout_bounds")
	var outer := AABB(_v(data.bounds.min),_v(data.bounds.max)-_v(data.bounds.min))
	if not outer.position.is_equal_approx(Vector3(-28,-3,-28)) or not outer.end.is_equal_approx(Vector3(28,18,28)): return _result(false,"local_scope_contract")
	if not data.fixed_solids is Array or data.fixed_solids.size()>96 or data.fixed_solids.size()<10: return _result(false,"solid_limit")
	var solids: Dictionary = {}
	for spec in data.fixed_solids:
		if not spec is Dictionary or not _exact(spec,["id","min","max","color"]) or not spec.id is String or spec.id.is_empty() or solids.has(spec.id) or not _bounds(spec) or not _color_valid(spec.color): return _result(false,"solid_shape")
		var box := AABB(_v(spec.min),_v(spec.max)-_v(spec.min))
		if not outer.encloses(box): return _result(false,"solid_outside_scope")
		solids[spec.id]=box
	for row in [["WestLanding",Vector3(-10,4.6,-6),Vector3(-2,5,-2)],["EastLanding",Vector3(2,4.6,-6),Vector3(12,5,-2)],["UnderDeckFloor",Vector3(-2,0,-6),Vector3(2,1,-2)],["PumpFloor",Vector3(-12,0,4),Vector3(-2,0.4,12)]]:
		if not solids.has(row[0]) or not solids[row[0]].position.is_equal_approx(row[1]) or not solids[row[0]].end.is_equal_approx(row[2]): return _result(false,"bearing_floor_contract")
	if not data.tanks is Dictionary or not _exact(data.tanks,[Runtime.SOURCE,Runtime.CLINIC]): return _result(false,"tank_ids")
	for id in data.tanks:
		var tank: Variant = data.tanks[id]
		if not tank is Dictionary or not _exact(tank,["center_xz","inner_size","base_y","wall"]) or not tank.center_xz is Array or tank.center_xz.size()!=2 or not _vector(tank.inner_size): return _result(false,"tank_shape")
		if not _number(tank.center_xz[0],-20,20) or not _number(tank.center_xz[1],-20,20) or not _number(tank.wall,0.1,0.2): return _result(false,"tank_position")
		var expected := Vector3(1.6,3,1) if id==Runtime.SOURCE else Vector3(2,2,1)
		var expected_base: float = 6.0 if id==Runtime.SOURCE else 3.5
		var expected_x: float = -9.0 if id==Runtime.SOURCE else 0.0
		var expected_z: float = -7.0 if id==Runtime.SOURCE else -8.0
		# JSON numbers are floats; Array equality also compares element Variant types.
		# Normalize each validated number, keeping exact coordinates (no tolerance).
		if not _v(tank.inner_size).is_equal_approx(expected) or not _number(tank.base_y,expected_base,expected_base) or float(tank.center_xz[0])!=expected_x or float(tank.center_xz[1])!=expected_z: return _result(false,"tank_volume_geometry_contract")
	if not data.moving_parts is Array or data.moving_parts.size()!=9: return _result(false,"moving_parts")
	var ids: Array = []
	for part in data.moving_parts:
		if not part is Dictionary or not _exact(part,["id","offset","size","color"]) or not part.id is String or ids.has(part.id) or not _vector(part.offset) or not _vector(part.size) or not _color_valid(part.color): return _result(false,"moving_part_shape")
		ids.append(part.id)
		var size := _v(part.size)
		if size.x<=0 or size.y<=0 or size.z<=0 or size.length()>7: return _result(false,"moving_part_size")
		for y in [4.0,5.0]:
			if not outer.encloses(AABB(_v(part.offset)+Vector3.UP*y-size*0.5,size)): return _result(false,"moving_outside_scope")
	if not ids.has("Deck") or data.moving_parts[0].id!="Deck" or not _v(data.moving_parts[0].size).is_equal_approx(Vector3(4,0.35,4)) or not _v(data.moving_parts[0].offset).is_equal_approx(Vector3(0,-0.175,-4)): return _result(false,"deck_contract")
	for key in ["gravity_valve","pump_selector","interlock_bolt"]:
		if not data[key] is Dictionary or not _vector(data[key].get("center")) or not _vector(data[key].get("size")): return _result(false,"actuator_shape")
	if not _exact(data.gravity_valve,["center","size","travel","mass_kg","open_epsilon","damping_per_second","max_speed_mps"]) or not _vector(data.gravity_valve.travel) or not _v(data.gravity_valve.center).is_equal_approx(Vector3(-8,7,-5)) or not _v(data.gravity_valve.travel).is_equal_approx(Vector3(1.2,0,0)) or not _v(data.gravity_valve.size).is_equal_approx(Vector3(0.8,0.35,0.7)) or data.gravity_valve.mass_kg!=2 or data.gravity_valve.open_epsilon!=0.005 or not _number(data.gravity_valve.damping_per_second,0.8,0.8) or not _number(data.gravity_valve.max_speed_mps,6.0,6.0): return _result(false,"gravity_actuator_contract")
	if not _exact(data.pump_selector,["center","size","travel","stroke_seconds"]) or not _vector(data.pump_selector.travel) or not _v(data.pump_selector.center).is_equal_approx(Vector3(-7,1.6,7)) or not _v(data.pump_selector.travel).is_equal_approx(Vector3(0.8,0,0)) or not _v(data.pump_selector.size).is_equal_approx(Vector3(0.8,0.5,0.35)) or data.pump_selector.stroke_seconds!=2: return _result(false,"pump_actuator_contract")
	if not _exact(data.interlock_bolt,["center","size","park_offset"]) or not _vector(data.interlock_bolt.park_offset): return _result(false,"interlock_shape")
	if not _v(data.interlock_bolt.center).is_equal_approx(Vector3(-7.48,7,-5)) or not _v(data.interlock_bolt.size).is_equal_approx(Vector3(0.22,0.40,0.9)) or not _v(data.interlock_bolt.park_offset).is_equal_approx(Vector3(0,0,1.4)): return _result(false,"interlock_contract")
	if not data.anchors is Dictionary or not _exact(data.anchors,["entry","pump_control","pump_relay","gravity_control","water_check","underpass"]): return _result(false,"anchors")
	for point in data.anchors.values():
		if not _vector(point) or not outer.has_point(_v(point)): return _result(false,"anchor_position")
	return _result(true,"valid")

static func _v(value: Array) -> Vector3:
	return Vector3(float(value[0]),float(value[1]),float(value[2]))

static func _number(value: Variant, minimum: float, maximum: float) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and float(value)>=minimum and float(value)<=maximum

static func _integer(value: Variant, minimum: int, maximum: int) -> bool:
	return _number(value,float(minimum),float(maximum)) and floor(float(value))==float(value)

static func _vector(value: Variant) -> bool:
	return value is Array and value.size()==3 and _number(value[0],-100,100) and _number(value[1],-100,100) and _number(value[2],-100,100)

static func _bounds(value: Variant) -> bool:
	if not value is Dictionary or not _vector(value.get("min")) or not _vector(value.get("max")): return false
	var size := _v(value.max)-_v(value.min)
	return size.x>0 and size.y>0 and size.z>0

static func _exact(value: Dictionary, keys: Array) -> bool:
	if value.size()!=keys.size(): return false
	for key in value:
		if not key is String or key not in keys: return false
	return true

static func _color_valid(value: Variant) -> bool:
	if not value is String or value.length()!=6: return false
	for character in value:
		if character not in "0123456789abcdefABCDEF": return false
	return true

static func _result(ok: bool, code: String, changed: bool = false) -> Dictionary:
	return {"ok":ok,"code":code,"changed":changed}
