class_name TwinParasiticCrown
extends Node3D
## Imported view only. Host arena owns position, decisions, motion approval and damage.
## Runtime GLB identity is locked by the actual asset suite; no missing-model graybox fallback.

const MODEL_PATH := "res://assets/v3/crown/parasitic_crown.glb"
const PLATES := {
	"CrownPlatePivot_L":{"axis":Vector3.UP, "degrees":-60.0},
	"CrownPlatePivot_R":{"axis":Vector3.UP, "degrees":72.0},
	"CrownPlatePivot_C":{"axis":Vector3.RIGHT, "degrees":-58.0}}
const LIMBS := ["FL", "FR", "BL", "BR"]
const ENVELOPE_PADDING := 0.002
const CORE_EMISSION_CLOSED := 0.06
const CORE_EMISSION_OPEN := 0.25

var imported := false
var import_errors: Array[String] = []
var visual: Node3D
var _nodes: Dictionary = {}
var _rest: Dictionary = {}
var _axes: Dictionary = {}
var _bodies: Array[PhysicsBody3D] = []
var _mesh_records: Array[Dictionary] = []
var _movement_shapes: Array[Dictionary] = []
var _core_materials: Array[Dictionary] = []
var _pending_state: Dictionary = {}
var _pending_defeated := false
var _last_pose: Array = []
var _last_transform := Transform3D.IDENTITY

func _ready() -> void:
	if not ResourceLoader.exists(MODEL_PATH):
		_fail("Final imported GLB is unavailable")
		return
	var packed := load(MODEL_PATH) as PackedScene
	if packed == null:
		_fail("GLB must import as PackedScene")
		return
	visual = packed.instantiate() as Node3D
	if visual == null:
		_fail("GLB root must be Node3D")
		return
	add_child(visual)
	var required: Array = ["Core", "CoreSeed", "LeafPivot_L", "LeafPivot_R"]
	required.append_array(PLATES.keys())
	for limb in LIMBS:
		for role in ["ClawShoulder_", "ClawWrist_", "ClawContact_"]: required.append(role + limb)
	for key in required:
		var found := visual.find_children(str(key), "Node3D", true, false)
		if found.size() != 1:
			_fail("Expected exactly one " + str(key) + ", found " + str(found.size()))
		else:
			_nodes[key] = found[0]
	if not import_errors.is_empty(): return
	if not _nodes.CoreSeed is MeshInstance3D or (_nodes.CoreSeed as MeshInstance3D).mesh == null:
		_fail("CoreSeed must remain an independent actual mesh")
		return
	for key in PLATES:
		var pivot: Node3D = _nodes[key]
		_rest[key] = pivot.transform
		var relative_basis: Basis = global_basis.inverse() * pivot.global_basis
		if not relative_basis.is_equal_approx(relative_basis.orthonormalized()) or relative_basis.determinant() < 0.99:
			_fail("Plate chain must use rigid unscaled transforms for conservative rotation bounds: " + str(key))
			continue
		# Axis is authored in asset-root space; convert through the imported rest basis.
		var local_axis: Vector3 = pivot.global_basis.inverse() * visual.global_basis * PLATES[key].axis
		if not local_axis.is_finite() or local_axis.length_squared() < 0.001:
			_fail("Invalid hinge basis " + str(key))
		else:
			_axes[key] = local_axis.normalized()
	if not import_errors.is_empty(): return
	var meshes: Array[MeshInstance3D] = []
	_collect_meshes(visual, meshes)
	if meshes.is_empty():
		_fail("GLB has no real geometry")
		return
	for mesh in meshes:
		var source: Node3D = _collision_group(mesh)
		var plate: String = _plate_parent(mesh)
		_mesh_records.append({"mesh":mesh, "source":source, "plate":plate})
	_build_collisions()
	_build_movement_shapes()
	_prepare_core_materials()
	if not import_errors.is_empty():
		for body in _bodies: body.collision_layer = 0
		return
	imported = true
	set_state(_pending_state, _pending_defeated)
	_pending_state.clear()

func core_position() -> Vector3:
	return (_nodes.Core as Node3D).global_position if imported else Vector3(INF, INF, INF)

func collision_bodies() -> Array:
	return _bodies.duplicate()

func movement_shapes() -> Array:
	# Shape resources are read-only to callers; duplicate each descriptor so transforms cannot be overwritten.
	var result: Array = []
	if not imported: return result
	for entry in _movement_shapes: result.append(entry.duplicate())
	return result

func set_state(presentation: Dictionary, defeated: bool = false) -> void:
	if not presentation.is_empty() and str(presentation.get("type", "parasitic_crown")) != "parasitic_crown": return
	if not imported:
		_pending_state = presentation.duplicate(true)
		_pending_defeated = defeated
		return
	var dead := defeated or str(presentation.get("mode", "")) == "defeated"
	var exposed := dead or bool(presentation.get("core_open", false))
	var pose_key: Array = [exposed, dead]
	if pose_key == _last_pose and global_transform == _last_transform: return
	if pose_key != _last_pose:
		for key in PLATES: _pose_plate(str(key), 1.0 if exposed else 0.0)
		# The authored seed slightly intersects the closed shell. Closed armor
		# must never expose a selectable core surface at a side seam. Keep the
		# complete seed in motion bounds; only its combat collider is gated.
		for body in _bodies:
			if str(body.get_meta("entity_id", "")) == "boss:crown_core":
				body.collision_layer = 8 if exposed else 0
		_set_core_glow(0.0 if dead else (CORE_EMISSION_OPEN if exposed else CORE_EMISSION_CLOSED))
		_last_pose = pose_key
	# The arena sets this wrapper's transform. Even an unchanged armor pose must
	# commit a changed root transform before same-frame ray/shape queries.
	_commit_physics_transforms()
	_last_transform = global_transform

func _pose_plate(key: String, fraction: float) -> void:
	var pose: Transform3D = _rest[key]
	pose.basis = pose.basis * Basis(_axes[key], deg_to_rad(float(PLATES[key].degrees) * clampf(fraction, 0.0, 1.0)))
	(_nodes[key] as Node3D).transform = pose

func _collision_group(mesh: MeshInstance3D) -> Node3D:
	if mesh == _nodes.CoreSeed: return mesh
	var cursor: Node = mesh
	while cursor != visual and cursor != null:
		var key := str(cursor.name)
		if PLATES.has(key) or key.begins_with("ClawShoulder_") or key.begins_with("ClawWrist_") or key in ["LeafPivot_L", "LeafPivot_R"]:
			return cursor as Node3D
		cursor = cursor.get_parent()
	return visual

func _plate_parent(mesh: MeshInstance3D) -> String:
	var cursor: Node = mesh
	while cursor != visual and cursor != null:
		if PLATES.has(str(cursor.name)): return str(cursor.name)
		cursor = cursor.get_parent()
	return ""

func _build_collisions() -> void:
	var groups: Dictionary = {}
	for record in _mesh_records:
		var source: Node3D = record.source
		var key := source.get_instance_id()
		var body: StaticBody3D
		if groups.has(key):
			body = groups[key]
		else:
			body = StaticBody3D.new()
			body.name = "AuthoredTriangleCollision"
			body.collision_layer = 8
			body.collision_mask = 0
			body.set_meta("entity_id", "boss:crown_core" if source == _nodes.CoreSeed else "boss:crown_armor")
			body.set_meta("asset_source", str(source.name) if source != visual else "StaticGeometry")
			source.add_child(body)
			groups[key] = body
			_bodies.append(body)
		var mesh: MeshInstance3D = record.mesh
		var shape := mesh.mesh.create_trimesh_shape()
		if shape == null:
			_fail("Cannot create triangle collision for " + str(mesh.name))
			continue
		shape.backface_collision = true
		var collision := CollisionShape3D.new()
		collision.name = str(mesh.name) + "Faces"
		collision.shape = shape
		body.add_child(collision)
		collision.transform = body.global_transform.affine_inverse() * mesh.global_transform

func _build_movement_shapes() -> void:
	# Per-mesh boxes are conservative motion-query envelopes, never the armor colliders.
	# For the three plate hinges, solve each vertex's coordinate extrema over the
	# entire rotation interval. Endpoint-only/five-pose samples can miss an arc bulge.
	var inverse := global_transform.affine_inverse()
	for record in _mesh_records:
		var mesh: MeshInstance3D = record.mesh
		var transform_to_wrapper := inverse * mesh.global_transform
		var plate: String = record.plate
		var pivot_origin := Vector3.ZERO
		var axis := Vector3.UP
		var end_angle := 0.0
		if not plate.is_empty():
			pivot_origin = inverse * (_nodes[plate] as Node3D).global_position
			axis = (inverse.basis * visual.global_basis * PLATES[plate].axis).normalized()
			end_angle = deg_to_rad(float(PLATES[plate].degrees))
		var minimum := Vector3(INF, INF, INF)
		var maximum := Vector3(-INF, -INF, -INF)
		var vertex_count := 0
		for surface in mesh.mesh.get_surface_count():
			var arrays: Array = mesh.mesh.surface_get_arrays(surface)
			if arrays.is_empty() or not arrays[Mesh.ARRAY_VERTEX] is PackedVector3Array: continue
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			for vertex in vertices:
				var point: Vector3 = transform_to_wrapper * vertex
				if not point.is_finite():
					_fail("Nonfinite movement geometry: " + str(mesh.name))
					return
				vertex_count += 1
				if plate.is_empty():
					minimum = minimum.min(point)
					maximum = maximum.max(point)
				else:
					var bounds: Array[Vector3] = _rotation_bounds(point, pivot_origin, axis, end_angle)
					minimum = minimum.min(bounds[0])
					maximum = maximum.max(bounds[1])
		if vertex_count == 0:
			_fail("No vertices available for movement query: " + str(mesh.name))
			continue
		var shape := BoxShape3D.new()
		shape.size = maximum - minimum + Vector3.ONE * ENVELOPE_PADDING * 2.0
		_movement_shapes.append({"shape":shape, "transform":Transform3D(Basis.IDENTITY, (minimum + maximum) * 0.5), "mesh_name":str(mesh.name)})

static func _rotation_bounds(point: Vector3, origin: Vector3, axis: Vector3, end_angle: float) -> Array[Vector3]:
	var offset := point - origin
	var parallel := axis * axis.dot(offset)
	var cosine := offset - parallel
	var sine := axis.cross(offset)
	var base := origin + parallel
	var low := minf(0.0, end_angle)
	var high := maxf(0.0, end_angle)
	var minimum := Vector3.ZERO
	var maximum := Vector3.ZERO
	for component in range(3):
		var a: float = cosine[component]
		var b: float = sine[component]
		var start_value: float = base[component] + a
		var end_value: float = base[component] + a * cos(end_angle) + b * sin(end_angle)
		minimum[component] = minf(start_value, end_value)
		maximum[component] = maxf(start_value, end_value)
		var turning := atan2(b, a)
		for turn in range(-2, 3):
			var candidate: float = turning + float(turn) * PI
			if candidate < low or candidate > high: continue
			var value: float = base[component] + a * cos(candidate) + b * sin(candidate)
			minimum[component] = minf(minimum[component], value)
			maximum[component] = maxf(maximum[component], value)
	return [minimum, maximum]

func _prepare_core_materials() -> void:
	var mesh: MeshInstance3D = _nodes.CoreSeed
	for surface in mesh.mesh.get_surface_count():
		var original := mesh.get_active_material(surface) as BaseMaterial3D
		if original == null:
			_fail("CoreSeed requires imported PBR material")
			continue
		var material := original.duplicate() as BaseMaterial3D
		mesh.set_surface_override_material(surface, material)
		_core_materials.append({"material":material, "emission":original.emission})

func _set_core_glow(energy: float) -> void:
	for entry in _core_materials:
		var material: BaseMaterial3D = entry.material
		material.emission_enabled = energy > 0.0
		material.emission = entry.emission
		material.emission_energy_multiplier = energy

func _collect_meshes(node: Node, result: Array[MeshInstance3D]) -> void:
	if node is MeshInstance3D and node.mesh != null: result.append(node)
	for child in node.get_children():
		if not child is CollisionObject3D: _collect_meshes(child, result)

func _commit_physics_transforms() -> void:
	_flush(self)
	for body in _bodies:
		PhysicsServer3D.body_set_state(body.get_rid(), PhysicsServer3D.BODY_STATE_TRANSFORM, body.global_transform)

func _flush(node: Node) -> void:
	if node is Node3D: node.force_update_transform()
	for child in node.get_children(): _flush(child)

func _fail(message: String) -> void:
	import_errors.append(message)
	push_error("ParasiticCrown import contract: " + message)
