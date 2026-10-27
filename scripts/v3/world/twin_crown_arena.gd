class_name TwinCrownArena
extends Node3D
## F1 world-space mapping and actual authored collision. Rules remain in the host.
const ORIGIN = Vector3(10, 0, -22)
# The full rendered body AND its colliders sit 25 mm above the support pose.
# This is physical contact clearance, never an offset applied only to queries.
const BODY_CLEARANCE = 0.025
const WarningView = preload("res://scripts/v3/art/twin_crown_warning.gd")
const MODEL_SCRIPT = "res://scripts/v3/art/twin_parasitic_crown.gd"
const HEIGHTS = [10, 17, 12]
var definition: Dictionary = {}
var model: Node3D
var hosts: Dictionary = {}
var host_targets: Dictionary = {}
var ground_modules: Array[Node3D] = []
var warnings: Dictionary = {}
var imported = false
var missing: Array[String] = []
var last_view: Dictionary = {}
var defeated = false
var _glows: Dictionary = {}

func build() -> void:
	position = ORIGIN
	definition = JSON.parse_string(FileAccess.get_file_as_string("res://data/v3/bosses/crown_parasite.json"))
	for index in range(definition.anchors.size()):
		var spec: Dictionary = definition.anchors[index]
		var body = vector(spec.body_position)
		var host = _module(HEIGHTS[index], Vector3(body.x, 0, body.z), str(spec.id))
		if host != null:
			hosts[str(spec.id)] = host
			var anchor = host.find_child("HostTarget", true, false)
			if anchor is Node3D:
				host_targets[str(spec.id)] = anchor
				if to_local(anchor.global_position).distance_to(vector(spec.target_position)) > 0.05:
					missing.append("host_target_mismatch:" + str(spec.id))
			else: missing.append("host_target_missing:" + str(spec.id))
		var fall = vector(spec.fall_position)
		var landing = _module(3, Vector3(fall.x, 0, fall.z), "")
		if landing != null: ground_modules.append(landing)
	if ResourceLoader.exists(MODEL_SCRIPT):
		model = load(MODEL_SCRIPT).new()
		add_child(model)
		model.position = body_position(definition.anchors[0].body_position)
	else: missing.append("crown_wrapper_missing")
	imported = missing.is_empty() and hosts.size() == 3 and ground_modules.size() == 3 and is_instance_valid(model) and model.imported
	_force_transforms(self)

func _module(height: int, at: Vector3, entity_id: String) -> Node3D:
	var path = "res://assets/v3/root_buttress/root_buttress_h%d.glb" % height
	if not ResourceLoader.exists(path):
		missing.append(path)
		return null
	var module = (load(path) as PackedScene).instantiate()
	add_child(module)
	module.position = at
	for mesh in module.find_children("*", "MeshInstance3D", true, false):
		if mesh.mesh == null or str(mesh.name).contains("Foliage") or str(mesh.name).contains("Moss") or str(mesh.name).contains("BarkPlates"): continue
		var body = StaticBody3D.new()
		body.collision_layer = 1
		body.collision_mask = 0
		body.set_meta("entity_id", entity_id if str(mesh.name).contains("SapKnot") else "crown:terrain")
		mesh.add_child(body)
		var collision = CollisionShape3D.new()
		collision.shape = mesh.mesh.create_trimesh_shape()
		collision.shape.backface_collision = true
		body.add_child(collision)
		if str(mesh.name).contains("SapKnot") and not entity_id.is_empty():
			var material = mesh.get_active_material(0)
			if material is BaseMaterial3D:
				var copy = material.duplicate()
				mesh.set_surface_override_material(0, copy)
				_glows[entity_id] = copy
	return module

func host_position(id: String) -> Vector3:
	return host_targets[id].global_position if host_targets.has(id) else Vector3.INF

func core_position() -> Vector3:
	return model.core_position() if imported else Vector3.INF

func retry_position(slot: int) -> Vector3:
	# Above the actual root-arch crown, separate from the active north arena.
	return Vector3(-2.4 if slot == 0 else 2.4, 12.2, -3.0)

func in_combat_space(point: Vector3) -> bool:
	# Includes the clear approach in front of the east host's actual target.
	return point.x >= -22 and point.x <= 43 and point.z >= -47 and point.z <= -9 and point.y >= 0 and point.y <= 27

func engagement(point: Vector3) -> bool:
	return in_combat_space(point) and point.distance_to(to_global(vector(definition.anchors[0].body_position))) <= 18

func apply_view(view: Dictionary, stopped: bool = false) -> void:
	last_view = view.duplicate(true)
	defeated = stopped
	if is_instance_valid(model) and model.imported:
		model.position = body_position(definition.anchors[0].body_position if view.is_empty() else view.position)
		model.set_state(view, stopped)
		_force_transforms(model)
		for body in model.collision_bodies(): PhysicsServer3D.body_set_state(body.get_rid(), PhysicsServer3D.BODY_STATE_TRANSFORM, body.global_transform)
	for id in _glows:
		var state: Dictionary = view.get("anchors", {}).get(id, {})
		var material: BaseMaterial3D = _glows[id]
		material.emission_enabled = not stopped and (bool(state.get("lit", false)) or bool(state.get("burning", false)))
		material.emission = Color("dd6d35") if state.get("burning", false) else Color("9bb576")
		material.emission_energy_multiplier = 0.3
	var wanted: Dictionary = {}
	for attack in view.get("attacks", []):
		for index in range(attack.shapes.size()):
			var key = str(attack.token) + ":" + str(index)
			wanted[key] = true
			if not warnings.has(key):
				var warning = WarningView.new()
				add_child(warning)
				warning.configure(attack.shapes[index], str(attack.kind))
				warnings[key] = warning
			warnings[key].update_time(float(attack.remaining), bool(attack.active))
	for key in warnings.keys():
		if not wanted.has(key):
			remove_child(warnings[key])
			warnings[key].queue_free()
			warnings.erase(key)

func motion_clear(points_mm: Array, include_players: bool = true) -> bool:
	return bool(motion_result(points_mm, include_players).get("clear", false))

func motion_result(points_mm: Array, include_players: bool = true) -> Dictionary:
	if not imported or points_mm.size() < 2: return {"clear":false, "reason":"not_ready"}
	var excluded: Array[RID] = []
	for body in model.collision_bodies(): excluded.append(body.get_rid())
	var space = get_world_3d().direct_space_state
	var parts: Array = model.movement_shapes()
	if parts.is_empty(): return {"clear":false, "reason":"no_geometry"}
	for index in range(points_mm.size() - 1):
		var from = to_global(body_position(vector(points_mm[index]) / 1000.0))
		var to = to_global(body_position(vector(points_mm[index + 1]) / 1000.0))
		if from.y < 3 or to.y < 3 or from.y > 24 or to.y > 24: return {"clear":false, "reason":"height", "segment":index}
		for part_index in range(parts.size()):
			var part: Dictionary = parts[part_index]
			var query = PhysicsShapeQueryParameters3D.new()
			query.shape = part.shape
			query.transform = Transform3D(Basis.IDENTITY, from) * part.transform
			query.motion = to - from
			query.margin = 0.001
			query.collision_mask = 1 | 8 | (2 if include_players else 0)
			query.exclude = excluded
			var overlaps = space.intersect_shape(query, 1)
			if not overlaps.is_empty(): return {"clear":false, "reason":"initial_overlap", "segment":index, "part":part_index, "mesh":str(part.get("mesh_name", "")), "collider":str(overlaps[0].collider.get_path())}
			var travel = space.cast_motion(query)
			if travel.size() < 2 or travel[0] < 0.999: return {"clear":false, "reason":"sweep", "segment":index, "part":part_index, "mesh":str(part.get("mesh_name", "")), "travel":Array(travel)}
			query.transform.origin += query.motion
			query.motion = Vector3.ZERO
			overlaps = space.intersect_shape(query, 1)
			if not overlaps.is_empty(): return {"clear":false, "reason":"destination_overlap", "segment":index, "part":part_index, "mesh":str(part.get("mesh_name", "")), "collider":str(overlaps[0].collider.get_path())}
	return {"clear":true, "parts":parts.size(), "segments":points_mm.size() - 1}

func attack_origin(attack: Dictionary) -> Vector3:
	if not imported: return Vector3.INF
	if attack.get("kind", "") == "burning_spores":
		var target = host_position(str(attack.get("anchor_id", "")))
		# The exposed front of the burning sap knot, independent of crown migration.
		return target + Vector3(0, 0, 0.85) if target.is_finite() else Vector3.INF
	return model.global_position + Vector3(0, 0, 4.3)

func attack_line_clear(attack: Dictionary, point: Vector3, player_rid: RID) -> bool:
	if not imported: return false
	var origin = attack_origin(attack)
	if not origin.is_finite(): return false
	var query = PhysicsRayQueryParameters3D.create(origin, point, 1 | 8)
	var exclusions: Array[RID] = [player_rid]
	for body in model.collision_bodies(): exclusions.append(body.get_rid())
	query.exclude = exclusions
	return get_world_3d().direct_space_state.intersect_ray(query).is_empty()

static func body_position(support_pose) -> Vector3:
	return vector(support_pose) + Vector3.UP * BODY_CLEARANCE

static func vector(value) -> Vector3:
	return value if value is Vector3 else Vector3(float(value[0]), float(value[1]), float(value[2]))

func _force_transforms(node: Node) -> void:
	if node is Node3D: node.force_update_transform()
	for child in node.get_children(): _force_transforms(child)
