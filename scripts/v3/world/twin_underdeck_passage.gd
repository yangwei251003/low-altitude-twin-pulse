class_name TwinUnderdeckPassage
extends Node3D
## Authored passage shell and sliding gates. No story, store or reward authority.
## Configure before adding to a World, supplying committed flags for first-frame pose.
## All layout numbers are world-aligned coordinates relative to the configured origin.
const PATH := "res://data/v3/terrain/i1_underdeck_layout.json"
const GateArt = preload("res://scripts/v3/art/twin_underdeck_gate_art.gd")
const ShellArt = preload("res://scripts/v3/art/twin_underdeck_shell_art.gd")
const FLAG := "opening:underdeck_latched"
const SNAPSHOT_VERSION := 1
const MAX_DELTA := 0.25
const MAX_SERIAL := 9007199254740000
const FRONT_ID := "I1:underdeck_grille"
const LATCH_ID := "I1:underdeck_latch"
const STATE_KEYS := ["schema_version", "layout_sha256", "phase_usec", "front_fraction", "rear_fraction", "latched", "front_obstructed", "rear_obstructed", "front_pinned", "serial"]

var configured := false
var authority := true
var shell: StaticBody3D
var gates: Dictionary = {}
var _layout: Dictionary = {}
var _state: Dictionary = {}
var _faces := PackedVector3Array()
var _lamps: Dictionary = {}
var _origin := Vector3.ZERO
var shell_art: Dictionary = {}

func load_layout(is_authority: bool = true, committed_flags: Dictionary = {}) -> Dictionary:
	if not FileAccess.file_exists(PATH): return _result(false, "layout_missing")
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(PATH))
	if not parsed is Dictionary: return _result(false, "layout_json")
	return configure(parsed, is_authority, committed_flags)

func configure(data: Dictionary, is_authority: bool = true, committed_flags: Dictionary = {}) -> Dictionary:
	if configured or is_inside_tree(): return _result(false, "configure_before_tree_once")
	var checked := _validate_layout(data)
	if not checked.ok: return checked
	if not committed_flags.get(FLAG, false) is bool: return _result(false, "flag_type")
	_layout = data.duplicate(true)
	_origin = _v(data.origin)
	position = _origin
	authority = is_authority
	var latched: bool = committed_flags.get(FLAG, false)
	_state = {"schema_version":SNAPSHOT_VERSION, "layout_sha256":JSON.stringify(_layout, "", true, true).sha256_text(),
		"phase_usec":0, "front_fraction":1.0 if latched else 0.0, "rear_fraction":1.0 if latched else 0.0,
		"latched":latched, "front_obstructed":false, "rear_obstructed":false, "front_pinned":false, "serial":0}
	_build_shell()
	shell_art = ShellArt.install(shell)
	if not shell_art.ok: return _result(false, str(shell_art.code))
	for id in ["front", "rear"]: _build_gate(id)
	_build_surface_details()
	configured = true
	set_meta("terrain_stage", "authored_shell_with_physical_passage")
	set_process(false)
	set_physics_process(false)
	_sync_pose()
	return _result(true, "independent_graybox_ready", true)

func layout() -> Dictionary:
	return _layout.duplicate(true)

func geometry_faces() -> PackedVector3Array:
	return _faces.duplicate()

func anchor_position(id: String) -> Variant:
	if not configured or not _layout.anchors.has(id): return null
	var local := _v(_layout.anchors[id]) - _origin
	return to_global(local) if is_inside_tree() else transform * local

func target_definitions() -> Array:
	if not configured: return []
	# Registration defaults only. Subsequent updates should read entity_position,
	# otherwise replacing these dictionaries would erase externally owned timers.
	return [{"id":FRONT_ID, "name":"检修廊故障滑门", "position":entity_position(FRONT_ID),
		"tags":["fieldable"], "pinned":false, "pinned_by":"", "field_remaining":0.0, "revision":0},
		{"id":LATCH_ID, "name":"检修廊安全锁", "position":anchor_position("inner_latch"),
		"tags":["echo_operable", "mechanical", "hackable"], "owner":"", "revision":0}]

func entity_position(id: String) -> Variant:
	if not configured: return null
	if id == LATCH_ID: return anchor_position("inner_latch")
	if id == FRONT_ID: return gates.front.global_position if is_inside_tree() else transform * gates.front.position
	return null

func snapshot() -> Dictionary:
	return _state.duplicate(true)

func apply_snapshot(raw: Variant) -> Dictionary:
	if not configured: return _result(false, "not_configured")
	var checked := _validate_snapshot(raw)
	if not checked.ok: return checked
	var next: Dictionary = raw.duplicate(true)
	for key in ["schema_version", "phase_usec", "serial"]: next[key] = int(next[key])
	for key in ["front_fraction", "rear_fraction"]: next[key] = float(next[key])
	if next == _state: return _result(true, "unchanged")
	# Session/epoch/sequence rejection belongs to the transport adapter, not this view.
	_state = next
	_sync_pose()
	return _result(true, "snapshot_applied", true)

func apply_committed(flags: Dictionary) -> Dictionary:
	if not configured: return _result(false, "not_configured")
	if not authority: return _result(false, "not_authority")
	if not flags.get(FLAG, false) is bool: return _result(false, "flag_type")
	var value: bool = flags.get(FLAG, false)
	if value == bool(_state.latched): return _result(true, "unchanged")
	if int(_state.serial) >= MAX_SERIAL: return _result(false, "serial_limit")
	_state.latched = value
	_state.phase_usec = 0
	_state.serial = int(_state.serial) + 1
	# Before tree insertion no actors exist: restore the committed pose immediately.
	# During play, fixed_update opens both panels through the same anti-pinch sweep.
	if not is_inside_tree():
		_state.front_fraction = 1.0 if value else 0.0
		_state.rear_fraction = 1.0 if value else 0.0
	_sync_pose()
	return _result(true, "committed_target_applied", true)

func fixed_update(delta: float, authorized_entities: Dictionary, players: Dictionary, is_authority: bool = true) -> Dictionary:
	if not configured or not is_inside_tree(): return _result(false, "world_required")
	if not authority or not is_authority: return _result(false, "not_authority")
	if not is_finite(delta) or delta < 0.0 or delta > MAX_DELTA: return _result(false, "delta_range")
	if delta == 0.0: return _result(true, "paused")
	if int(_state.serial) >= MAX_SERIAL: return _result(false, "serial_limit")
	if players.size() > 2: return _result(false, "player_limit")
	for body in players.values():
		if not body is PhysicsBody3D or not is_instance_valid(body) or not body.is_inside_tree() or body.get_world_3d() != get_world_3d():
			return _result(false, "player_body_required")
		if (int(body.collision_layer) & (2 | 8)) == 0 or body.get_shape_owners().is_empty():
			return _result(false, "player_physics_required")
	var entity: Variant = authorized_entities.get(FRONT_ID, {})
	if not entity is Dictionary or not entity.get("pinned", false) is bool: return _result(false, "pin_state")
	if not _finite(entity.get("field_remaining", 0.0)) or float(entity.get("field_remaining", 0.0)) < 0.0 or float(entity.get("field_remaining", 0.0)) > 4.000001:
		return _result(false, "pin_timer")
	var pinned: bool = entity.get("pinned", false) and float(entity.get("field_remaining", 0.0)) > 0.0
	var usec := int(round(delta * 1000000.0))
	if usec == 0: return _result(true, "sub_microsecond")
	var next: Dictionary = _state.duplicate(true)
	var old_phase: String = status().phase
	next.front_pinned = pinned
	if not pinned and not bool(next.latched): next.phase_usec = (int(next.phase_usec) + usec) % int(_layout.cycle_usec.period)
	var front_goal := 1.0 if bool(next.latched) else _cycle_fraction(int(next.phase_usec))
	var speed := 1000000.0 / float(int(_layout.cycle_usec.open_start) - int(_layout.cycle_usec.opening_start))
	var front_next := float(next.front_fraction) if pinned else move_toward(float(next.front_fraction), front_goal, delta * speed)
	var rear_next := move_toward(float(next.rear_fraction), 1.0 if bool(next.latched) else 0.0, delta * speed)
	# For a translating rectangular solid this expanded box is the exact continuous
	# swept volume. PhysicsServer tests the *actual* player/prop shapes against it.
	next.front_obstructed = not is_equal_approx(front_next, float(next.front_fraction)) and not _sweep_clear("front", float(next.front_fraction), front_next)
	next.rear_obstructed = not is_equal_approx(rear_next, float(next.rear_fraction)) and not _sweep_clear("rear", float(next.rear_fraction), rear_next)
	if not next.front_obstructed: next.front_fraction = front_next
	elif not bool(next.latched): next.phase_usec = _state.phase_usec
	if not next.rear_obstructed: next.rear_fraction = rear_next
	next.serial = int(next.serial) + 1
	var events: Array = []
	for side in ["front", "rear"]:
		if bool(next[side + "_obstructed"]) and not bool(_state[side + "_obstructed"]):
			events.append({"kind":"gate_obstructed", "gate":side, "serial":next.serial, "event_id":"underdeck:%d:%s" % [next.serial, side]})
	_state = next
	_sync_pose()
	if old_phase != str(status().phase): events.append({"kind":"gate_phase", "phase":status().phase, "serial":next.serial, "event_id":"underdeck:%d:phase" % next.serial})
	return {"ok":true, "code":"advanced", "changed":true, "events":events}

func status() -> Dictionary:
	if not configured: return {}
	var phase := "closed"
	var t: int = _state.phase_usec
	var c: Dictionary = _layout.cycle_usec
	if _state.latched: phase = "released" if float(_state.front_fraction) > 0.999 and float(_state.rear_fraction) > 0.999 else "releasing"
	elif _state.front_pinned: phase = "field_hold"
	elif _state.front_obstructed: phase = "obstructed"
	elif t >= int(c.closing_start) and t < int(c.closed_again): phase = "closing"
	elif t >= int(c.closing_warning_start) and t < int(c.closing_start): phase = "closing_warning"
	elif t >= int(c.open_start) and t < int(c.closing_warning_start): phase = "open"
	elif t >= int(c.opening_start) and t < int(c.open_start): phase = "opening"
	elif t >= int(c.opening_start) - 1000000 and t < int(c.opening_start): phase = "opening_warning"
	return {"phase":phase, "front_fraction":float(_state.front_fraction), "rear_fraction":float(_state.rear_fraction),
		"latched":bool(_state.latched), "front_obstructed":bool(_state.front_obstructed), "rear_obstructed":bool(_state.rear_obstructed)}

func entrance_status_text() -> String:
	match str(status().get("phase", "closed")):
		"opening_warning": return "南门即将开启"
		"opening": return "南门正在开启"
		"open": return "南门已打开"
		"closing_warning": return "南门即将关闭"
		"closing": return "南门正在关闭"
		"field_hold": return "南门已固定 · 仍需观察门缝"
		"obstructed": return "门边受阻 · 请让开滑轨"
		"releasing": return "互锁已解除 · 门片正在收起"
		"released": return "检修通路已开放"
	return "南门关闭 · 东侧高窗常开"

func _sweep_clear(id: String, from_fraction: float, to_fraction: float) -> bool:
	var spec: Dictionary = _layout.gates[id]
	var start := _v(spec.center) - _origin + _v(spec.travel) * from_fraction
	var finish := _v(spec.center) - _origin + _v(spec.travel) * to_fraction
	var shape := BoxShape3D.new()
	shape.size = _v(spec.size) + Vector3(absf(finish.x - start.x), 0, 0)
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = shape
	query.transform = global_transform * Transform3D(Basis.IDENTITY, (start + finish) * 0.5)
	query.collision_mask = 2 | 8
	query.margin = 0.012
	return get_world_3d().direct_space_state.intersect_shape(query, 1).is_empty()

func _cycle_fraction(t: int) -> float:
	var c: Dictionary = _layout.cycle_usec
	if t < int(c.opening_start) or t >= int(c.closed_again): return 0.0
	if t < int(c.open_start): return float(t - int(c.opening_start)) / float(int(c.open_start) - int(c.opening_start))
	if t < int(c.closing_start): return 1.0
	return 1.0 - float(t - int(c.closing_start)) / float(int(c.closed_again) - int(c.closing_start))

func _sync_pose() -> void:
	for id in ["front", "rear"]:
		var body: StaticBody3D = gates[id]
		var spec: Dictionary = _layout.gates[id]
		body.position = _v(spec.center) - _origin + _v(spec.travel) * float(_state[id + "_fraction"])
		if body.is_inside_tree():
			body.force_update_transform()
			PhysicsServer3D.body_set_state(body.get_rid(), PhysicsServer3D.BODY_STATE_TRANSFORM, body.global_transform)
	var phase: String = status().get("phase", "closed")
	var pulse := int(_state.phase_usec / 250000) % 2 == 0
	var front_color := Color("638599")
	if phase == "opening_warning": front_color = Color("82f1d0") if pulse else Color("19483c")
	elif phase == "closing_warning": front_color = Color("ffbf70") if pulse else Color("51321d")
	elif phase in ["closing", "obstructed"]: front_color = Color("dc8048")
	elif phase == "field_hold": front_color = Color("65b4dc")
	elif float(_state.front_fraction) >= 0.999: front_color = Color("50bfa0")
	elif float(_state.front_fraction) > 0.0: front_color = Color("e5a257")
	_lamps.front.material_override.albedo_color = front_color
	# The north exit stays closed until the saved latch releases it. It must never
	# inherit a green signal merely because the unrelated south panel is open.
	_lamps.rear.material_override.albedo_color = Color("dc8048") if _state.rear_obstructed else Color("50bfa0") if float(_state.rear_fraction) >= 0.999 else Color("e5a257") if float(_state.rear_fraction) > 0.0 else Color("638599")

func _build_shell() -> void:
	# Orthogonal partition, union of authored voids, emit only solid/air boundaries.
	# No concave hull or single box can accidentally span an opening.
	var outer := _box(_layout.outer)
	var axes: Array = [[], [], []]
	for axis in range(3):
		axes[axis].append(outer.position[axis])
		axes[axis].append(outer.end[axis])
		for hole in _layout.voids:
			for point in [hole.min, hole.max]:
				var value := float(point[axis])
				if value > outer.position[axis] and value < outer.end[axis] and not axes[axis].has(value): axes[axis].append(value)
		axes[axis].sort()
	var filled: Dictionary = {}
	for x in range(axes[0].size() - 1):
		for y in range(axes[1].size() - 1):
			for z in range(axes[2].size() - 1):
				var midpoint := Vector3((axes[0][x]+axes[0][x+1])*0.5, (axes[1][y]+axes[1][y+1])*0.5, (axes[2][z]+axes[2][z+1])*0.5)
				var solid := true
				for hole in _layout.voids:
					if _box(hole).has_point(midpoint): solid = false; break
				if solid: filled[Vector3i(x,y,z)] = true
	var groups: Array = [PackedVector3Array(), PackedVector3Array(), PackedVector3Array()]
	# Keep the collision partition/order exactly as authored. Visual-only splits
	# below share the original planes; they do not add caps or invisible blockers.
	var navigation: Array = [PackedVector3Array(), PackedVector3Array(), PackedVector3Array()]
	var cover: Array = [PackedVector3Array(), PackedVector3Array(), PackedVector3Array()]
	var directions: Array[Vector3i] = [Vector3i(-1,0,0),Vector3i(1,0,0),Vector3i(0,-1,0),Vector3i(0,1,0),Vector3i(0,0,-1),Vector3i(0,0,1)]
	for cell: Vector3i in filled:
		var low := Vector3(axes[0][cell.x], axes[1][cell.y], axes[2][cell.z]) - _origin
		var high := Vector3(axes[0][cell.x+1], axes[1][cell.y+1], axes[2][cell.z+1]) - _origin
		for dir in directions:
			if filled.has(cell + dir): continue
			var face := _face(low, high, Vector3(dir))
			var group := 1 if dir.y > 0 else 2 if dir.y < 0 else 0
			groups[group].append_array(face)
			if dir.y != 0:
				# Interior floors/landings stay opaque; the outer roof and all
				# ceilings belong to the camera-faded cover, not the floor group.
				if dir.y > 0 and high.y < outer.end.y - _origin.y:
					navigation[group].append_array(face)
				else:
					cover[group].append_array(face)
				continue
			# Preserve the real raised landing riser as well as its top surface.
			if not filled.has(cell + Vector3i.UP) and high.y < outer.end.y - _origin.y:
				navigation[group].append_array(face)
				continue
			# Find the floor of the air volume next to this wall. A 32 cm wall
			# foot conveys the corridor edge without leaving a 1.85 m wall
			# opaque merely because that is the original collision cell height.
			var air_point := (low + high) * 0.5 + _origin
			if dir.x != 0: air_point.x = (low.x if dir.x < 0 else high.x) + _origin.x + dir.x * 0.001
			else: air_point.z = (low.z if dir.z < 0 else high.z) + _origin.z + dir.z * 0.001
			var floor_y := outer.position.y
			var found_floor := false
			for hole in _layout.voids:
				var air := _box(hole)
				if air_point.x > air.position.x and air_point.x < air.end.x and air_point.z > air.position.z and air_point.z < air.end.z:
					floor_y = minf(floor_y, air.position.y) if found_floor else air.position.y
					found_floor = true
			var cut_y := clampf(floor_y + 0.32 - _origin.y, low.y, high.y)
			if cut_y >= high.y:
				navigation[group].append_array(face)
			elif cut_y <= low.y:
				cover[group].append_array(face)
			else:
				var foot_high := high
				foot_high.y = cut_y
				var wall_low := low
				wall_low.y = cut_y
				navigation[group].append_array(_face(low, foot_high, Vector3(dir)))
				cover[group].append_array(_face(wall_low, high, Vector3(dir)))
	for i in range(groups.size()):
		_faces.append_array(groups[i])
	shell = StaticBody3D.new()
	shell.name = "WarehouseShell"
	shell.collision_layer = 1
	shell.collision_mask = 0
	add_child(shell)
	for part in range(2):
		var parent := Node3D.new()
		parent.name = "PermanentNavigation" if part == 0 else "OccludingCover"
		if part == 0: parent.set_meta("terrain_visibility_keep", true)
		shell.add_child(parent)
		var mesh := ArrayMesh.new()
		var visual_groups: Array = navigation if part == 0 else cover
		for i in range(visual_groups.size()):
			if visual_groups[i].is_empty(): continue
			_append_surface(mesh, visual_groups[i])
			mesh.surface_set_material(mesh.get_surface_count() - 1, _material([Color("5c6e75"),Color("4c595b"),Color("3f515b")][i]))
		var visual := MeshInstance3D.new()
		visual.name = "Surface"
		visual.mesh = mesh
		parent.add_child(visual)
	var shape := ConcavePolygonShape3D.new()
	shape.set_faces(_faces)
	shape.backface_collision = true
	var collider := CollisionShape3D.new()
	collider.name = "ExactSurfaceCollision"
	collider.shape = shape
	shell.add_child(collider)

func _build_gate(id: String) -> void:
	var spec: Dictionary = _layout.gates[id]
	# The module sweeps every authority step before publishing the new solid pose.
	# A StaticBody commits the validated pose immediately; Jolt kinematic bodies
	# defer it until the next step, leaving paused/reconnected collision stale.
	var body := StaticBody3D.new()
	body.name = spec.node
	body.collision_layer = 1
	body.collision_mask = 2 | 8
	body.set_meta("entity_id", spec.entity_id)
	add_child(body)
	var size := _v(spec.size)
	var faces := _cube_faces(-size*0.5, size*0.5)
	var mesh := ArrayMesh.new()
	_append_surface(mesh, faces)
	var visual := GateArt.panel(id == "rear")
	body.add_child(visual)
	var collider := CollisionShape3D.new()
	collider.name = "ExactConvexPanel"
	var shape := ConvexPolygonShape3D.new()
	# Preserve the established physical hull bytes. This construction mesh is NOT
	# rendered; the imported continuous solid fills the same 3.8 x 3.2 x .30 box.
	# Upper hanging wheels live in the unreachable wall zone above the lintel.
	shape.points = mesh.get_faces()
	collider.shape = shape
	body.add_child(collider)
	gates[id] = body

func _build_surface_details() -> void:
	var details := Node3D.new()
	details.name = "GrayboxMaintenanceMarkings"
	add_child(details)
	# Floor lanes and repair-zone outline are thin painted surfaces, no collision.
	for x in [-36.35, -33.65]:
		_decal_box(details, Vector3(x,0.454,-27)-_origin, Vector3(0.075,0.004,15.6), Color("c5be89"), "InspectionLane")
	for z in [-24.8,-22.2]:
		_decal_box(details, Vector3(-28.5,2.304,z)-_origin, Vector3(3.6,0.004,0.07), Color("6faeb1"), "SideDuctLane")
	# Painted perimeter stays outside the actual clear opening; it identifies the
	# raised alternate entrance even on the warehouse's shaded east face.
	for z in [-25.16, -21.84]:
		var edge := _decal_box(details, Vector3(-26.48,3.55,z)-_origin, Vector3(0.025,2.62,0.10), Color("86aaa5"), "SideWindowJambPaint")
		edge.material_override.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	for y in [2.24, 4.86]:
		var edge := _decal_box(details, Vector3(-26.48,y,-23.5)-_origin, Vector3(0.025,0.10,3.42), Color("86aaa5"), "SideWindowSillPaint")
		edge.material_override.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	for at in [Vector3(-35.8,0.456,-20.4), Vector3(-34.4,0.456,-31.7),Vector3(-32.3,0.456,-24.1)]:
		var stain := MeshInstance3D.new()
		stain.name = "DryWaterMark"
		var disc := CylinderMesh.new()
		disc.top_radius = 0.4
		disc.bottom_radius = 0.4
		disc.height = 0.003
		disc.radial_segments = 9
		stain.mesh = disc
		stain.position = at - _origin
		stain.scale = Vector3(1.7,1,0.55)
		stain.rotation.y = at.z * 0.4
		stain.material_override = _material(Color("314c50"))
		details.add_child(stain)
	for id in ["front","rear"]:
		var center := _v(_layout.gates[id].center) - _origin
		var rail := GateArt.rail(id == "rear")
		rail.name = "FrontFixedRail" if id == "front" else "RearFixedRail"
		rail.position = center
		details.add_child(rail)
		_lamps[id] = GateArt.lamp(rail)
	var panel := StaticBody3D.new()
	panel.name = "InnerLatch"
	panel.collision_layer = 8
	panel.collision_mask = 0
	panel.position = _v(_layout.anchors.inner_latch) - _origin
	panel.set_meta("entity_id", LATCH_ID)
	add_child(panel)
	var size := Vector3(0.2,0.65,0.6)
	_decal_box(panel, Vector3.ZERO, size, Color("659b91"), "LatchSurface")
	var collider := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	collider.shape = shape
	panel.add_child(collider)

func _decal_box(parent: Node3D, at: Vector3, size: Vector3, color: Color, label: String) -> MeshInstance3D:
	var visual := MeshInstance3D.new()
	visual.name = label
	var mesh := BoxMesh.new()
	mesh.size = size
	visual.mesh = mesh
	visual.position = at
	visual.material_override = _material(color)
	parent.add_child(visual)
	return visual

static func _material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.85
	return material

static func _append_surface(mesh: ArrayMesh, faces: PackedVector3Array) -> void:
	var normals := PackedVector3Array()
	for i in range(0,faces.size(),3):
		var normal := -(faces[i+1]-faces[i]).cross(faces[i+2]-faces[i]).normalized()
		for j in range(3): normals.append(normal)
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = faces
	arrays[Mesh.ARRAY_NORMAL] = normals
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)

static func _cube_faces(low: Vector3, high: Vector3) -> PackedVector3Array:
	var faces := PackedVector3Array()
	for dir in [Vector3.LEFT,Vector3.RIGHT,Vector3.DOWN,Vector3.UP,Vector3.FORWARD,Vector3.BACK]: faces.append_array(_face(low,high,dir))
	return faces

static func _face(low: Vector3, high: Vector3, dir: Vector3) -> PackedVector3Array:
	var points: Array[Vector3] = []
	if dir.x != 0:
		var x := low.x if dir.x < 0 else high.x
		points = [Vector3(x,low.y,low.z),Vector3(x,high.y,low.z),Vector3(x,high.y,high.z),Vector3(x,low.y,high.z)]
	elif dir.y != 0:
		var y := low.y if dir.y < 0 else high.y
		points = [Vector3(low.x,y,low.z),Vector3(high.x,y,low.z),Vector3(high.x,y,high.z),Vector3(low.x,y,high.z)]
	else:
		var z := low.z if dir.z < 0 else high.z
		points = [Vector3(low.x,low.y,z),Vector3(high.x,low.y,z),Vector3(high.x,high.y,z),Vector3(low.x,high.y,z)]
	if (points[1]-points[0]).cross(points[2]-points[0]).dot(dir) > 0: points.reverse()
	return PackedVector3Array([points[0],points[1],points[2],points[0],points[2],points[3]])

func _validate_snapshot(raw: Variant) -> Dictionary:
	if not raw is Dictionary or raw.size() != STATE_KEYS.size(): return _result(false, "snapshot_keys")
	for key in STATE_KEYS:
		if not raw.has(key): return _result(false, "snapshot_keys")
	if not _integer(raw.schema_version, SNAPSHOT_VERSION, SNAPSHOT_VERSION) or raw.layout_sha256 != _state.layout_sha256: return _result(false, "snapshot_version")
	if not _integer(raw.phase_usec, 0, int(_layout.cycle_usec.period)-1) or not _integer(raw.serial, 0, MAX_SERIAL): return _result(false, "snapshot_integer")
	for key in ["front_fraction", "rear_fraction"]:
		if not _finite(raw[key]) or float(raw[key]) < 0.0 or float(raw[key]) > 1.0: return _result(false, "snapshot_fraction")
	for key in ["latched", "front_obstructed", "rear_obstructed", "front_pinned"]:
		if not raw[key] is bool: return _result(false, "snapshot_boolean")
	return _result(true, "valid")

static func _validate_layout(data: Dictionary) -> Dictionary:
	if data.get("schema_version") != 1 or data.get("id") != "i1_underdeck_layout_v1": return _result(false, "layout_schema")
	if not _vector(data.get("origin")) or not _bounds(data.get("outer")): return _result(false, "layout_outer")
	var outer := _box(data.outer)
	if not outer.position.is_equal_approx(Vector3(-43.5,0,-35.5)) or not outer.size.is_equal_approx(Vector3(17,6,17)): return _result(false, "warehouse_contract")
	if not data.get("voids") is Array or data.voids.size() < 3 or data.voids.size() > 8: return _result(false, "void_count")
	var ids: Array = []
	for hole in data.voids:
		if not _bounds(hole) or not hole.get("id") is String or hole.id in ids: return _result(false, "void_bounds")
		ids.append(hole.id)
		var box := _box(hole)
		# Vector3 uses float32; this tolerance is <0.01 mm, not extra playable space.
		if not outer.encloses(box) or box.position.y <= 0.0 or box.end.y > 4.80001: return _result(false, "void_support_contract")
	if not data.get("gates") is Dictionary or data.gates.size() != 2: return _result(false, "gates")
	for id in ["front","rear"]:
		var spec: Variant = data.gates.get(id)
		if not spec is Dictionary or not _vector(spec.get("center")) or not _vector(spec.get("size")) or not _vector(spec.get("travel")): return _result(false, "gate_vectors")
		var center := Vector3(-35,2.05,-18.5 if id=="front" else -35.5)
		if not _v(spec.center).is_equal_approx(center) or not _v(spec.size).is_equal_approx(Vector3(3.8,3.2,0.3)) or not _v(spec.travel).is_equal_approx(Vector3(4.2 if id=="front" else -4.2,0,0)): return _result(false, "gate_contract")
		if spec.get("node") != ("FrontGrille" if id=="front" else "RearGrille") or spec.get("entity_id") != (FRONT_ID if id=="front" else "I1:underdeck_rear_grille"): return _result(false, "gate_id")
	if not data.get("cycle_usec") is Dictionary or data.cycle_usec.size() != 6: return _result(false, "cycle")
	var last := 0
	for key in ["opening_start","open_start","closing_warning_start","closing_start","closed_again","period"]:
		if not _integer(data.cycle_usec.get(key), last+1, 8000000): return _result(false, "cycle_order")
		last = int(data.cycle_usec[key])
	if last != 8000000: return _result(false, "cycle_period")
	if int(data.cycle_usec.open_start)-int(data.cycle_usec.opening_start) != 1200000 or int(data.cycle_usec.closed_again)-int(data.cycle_usec.closing_start) != 1200000 or int(data.cycle_usec.closing_start)-int(data.cycle_usec.closing_warning_start) < 1000000: return _result(false, "cycle_warning_speed")
	if not data.get("anchors") is Dictionary or data.anchors.size() != 5: return _result(false, "anchors")
	for key in ["entry","side_entry","exit","inner_latch","inspection_log"]:
		if not _vector(data.anchors.get(key)): return _result(false, "anchor_vector")
	if not data.get("roof_supports") is Array or data.roof_supports.size() != 3: return _result(false, "roof_supports")
	for i in range(3):
		var support: Variant = data.roof_supports[i]
		if not support is Dictionary or not _vector(support.get("center")) or support.get("footprint") != [3.0,3.0]: return _result(false, "roof_support_contract")
		if not _v(support.center).is_equal_approx(Vector3([-42.0,-35.0,-28.0][i],6,-26)): return _result(false, "roof_support_contract")
	return _result(true, "layout_valid")

static func _bounds(raw: Variant) -> bool:
	if not raw is Dictionary or not _vector(raw.get("min")) or not _vector(raw.get("max")): return false
	var size := _v(raw.max)-_v(raw.min)
	return size.x > 0.0 and size.y > 0.0 and size.z > 0.0

static func _box(raw: Dictionary) -> AABB:
	return AABB(_v(raw.min), _v(raw.max)-_v(raw.min))

static func _v(raw: Array) -> Vector3:
	return Vector3(float(raw[0]),float(raw[1]),float(raw[2]))

static func _vector(raw: Variant) -> bool:
	if not raw is Array or raw.size() != 3: return false
	for value in raw:
		if not _finite(value) or absf(float(value)) > 100.0: return false
	return true

static func _finite(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value))

static func _integer(value: Variant, low: int, high: int) -> bool:
	return _finite(value) and float(value) == floor(float(value)) and float(value) >= low and float(value) <= high

static func _result(ok: bool, code: String, changed: bool = false) -> Dictionary:
	return {"ok":ok, "code":code, "changed":changed}
