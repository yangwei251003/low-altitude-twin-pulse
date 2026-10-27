class_name TwinSiphonWhale
extends Node3D
## Replaceable GLB view. Encounter decisions and weakpoint hurtboxes belong to the host.

const MODEL_PATH := "res://assets/v3/whale/siphon_whale.glb"
const HATCH_DEGREES := 68.0
const SHIELD_OPEN_OFFSET := Vector3(0, 0.30, -3.2)
# Actual camera review: preserve cylinder shading instead of saturating cyan.
const EMISSION_SCALE := 0.225
const EMISSION_MULTIPLIER_CAP := 0.315
const ANCHORS := {"core":"CoreWeakpoint", "port":"PortWeakpoint", "starboard":"StarboardWeakpoint"}

var imported := false
var visual: Node3D
var import_errors: Array[String] = []
var _nodes: Dictionary = {}
var _rest: Dictionary = {}
var _axes: Dictionary = {}
var _glows: Dictionary = {}
var _bodies: Array[PhysicsBody3D] = []
var _shield_delta := Vector3.ZERO
var _last_state: Array = []
var _pending_state: Dictionary = {}
var _pending_defeated := false

func _ready() -> void:
	var packed := load(MODEL_PATH) as PackedScene
	if packed == null:
		_fail("GLB must be imported before the whale view can initialize")
		return
	visual = packed.instantiate() as Node3D
	if visual == null:
		_fail("GLB scene root must be Node3D")
		return
	add_child(visual)
	for key in ["StaticHull", "PortHatchPivot", "StarboardHatchPivot", "CoreShield", "CoreGlow", "PortGlow", "StarboardGlow", "CoreWeakpoint", "PortWeakpoint", "StarboardWeakpoint", "AttackOrigin", "RetryEntry", "RawCommandRecordAnchor"]:
		var found := visual.find_children(str(key), "Node3D", true, false)
		if found.size() != 1:
			_fail("Expected exactly one " + str(key) + ", found " + str(found.size()))
		else:
			_nodes[key] = found[0]
	if not import_errors.is_empty(): return
	for key in ["PortHatchPivot", "StarboardHatchPivot"]:
		var pivot: Node3D = _nodes[key]
		_rest[key] = pivot.transform
		# Convert the authored asset-root +Z hinge direction into the actual imported
		# pivot basis. No assumption that Blender Euler axes survived GLB unchanged.
		var local_axis: Vector3 = pivot.global_basis.inverse() * visual.global_basis.z
		if not local_axis.is_finite() or local_axis.length_squared() < 0.001:
			_fail("Invalid imported hinge basis: " + str(key))
		else:
			_axes[key] = local_axis.normalized()
	var shield: Node3D = _nodes.CoreShield
	_rest.CoreShield = shield.transform
	_shield_delta = (shield.get_parent() as Node3D).global_basis.inverse() * visual.global_basis * SHIELD_OPEN_OFFSET
	for key in ["CoreGlow", "PortGlow", "StarboardGlow"]: _prepare_glow(str(key))
	if not import_errors.is_empty(): return
	_add_collision("StaticHull", "HullCollision", "boss:hull")
	_add_collision("PortHatchPivot", "PortArmorCollision", "boss:armor")
	_add_collision("StarboardHatchPivot", "StarboardArmorCollision", "boss:armor")
	_add_collision("CoreShield", "CoreArmorCollision", "boss:armor")
	if not import_errors.is_empty():
		for body in _bodies: body.collision_layer = 0
		return
	imported = true
	set_state(_pending_state, _pending_defeated)
	_pending_state.clear()

func weakpoint_position(part: String) -> Vector3:
	if not imported or not ANCHORS.has(part): return Vector3(INF, INF, INF)
	return (_nodes[ANCHORS[part]] as Node3D).global_position

func attack_origin() -> Vector3:
	return (_nodes.AttackOrigin as Node3D).global_position if imported else Vector3(INF, INF, INF)

func retry_entry() -> Vector3:
	return (_nodes.RetryEntry as Node3D).global_position if imported else Vector3(INF, INF, INF)

func raw_record_position() -> Vector3:
	return (_nodes.RawCommandRecordAnchor as Node3D).global_position if imported else Vector3(INF, INF, INF)

func collision_bodies() -> Array[PhysicsBody3D]:
	return _bodies.duplicate()

func set_state(boss: Dictionary, defeated: bool = false) -> void:
	if not imported:
		_pending_state = boss.duplicate(true)
		_pending_defeated = defeated
		return
	var dead := defeated or bool(boss.get("completed", false)) or str(boss.get("phase", "")) == "defeated"
	var exposed := not dead and str(boss.get("phase", "")) == "exposed"
	var open_window := bool(boss.get("nodes_open", false))
	var nodes: Dictionary = boss.get("nodes", {})
	var port_powered := bool(nodes.get("port", {}).get("powered", true)) and not dead
	var starboard_powered := bool(nodes.get("starboard", {}).get("powered", true)) and not dead
	var port_open := dead or open_window or not port_powered
	var starboard_open := dead or open_window or not starboard_powered
	var key := [dead, exposed, port_open, starboard_open, port_powered, starboard_powered]
	if key == _last_state: return
	_last_state = key
	_pose_hatch("PortHatchPivot", -HATCH_DEGREES if port_open else 0.0)
	_pose_hatch("StarboardHatchPivot", HATCH_DEGREES if starboard_open else 0.0)
	var shield_pose: Transform3D = _rest.CoreShield
	if exposed or dead: shield_pose.origin += _shield_delta
	(_nodes.CoreShield as Node3D).transform = shield_pose
	_glow("PortGlow", (1.0 if port_open else 0.45) if port_powered else 0.0)
	_glow("StarboardGlow", (1.0 if starboard_open else 0.45) if starboard_powered else 0.0)
	_glow("CoreGlow", 0.0 if dead else (1.4 if exposed else 0.15))
	# Immediate pose is intentional: paused restores must not wait for animation.
	_flush(visual)
	for body in _bodies:
		PhysicsServer3D.body_set_state(body.get_rid(), PhysicsServer3D.BODY_STATE_TRANSFORM, body.global_transform)

func _pose_hatch(key: String, degrees: float) -> void:
	var pose: Transform3D = _rest[key]
	pose.basis = pose.basis * Basis(_axes[key], deg_to_rad(degrees))
	(_nodes[key] as Node3D).transform = pose

func _add_collision(source_key: String, body_name: String, entity_id: String) -> void:
	var source: Node3D = _nodes[source_key]
	var meshes: Array[MeshInstance3D] = []
	_collect_meshes(source, meshes)
	if meshes.is_empty():
		_fail("Collision source has no real mesh: " + source_key)
		return
	# These are discrete authored poses, not a simulated motion trajectory.
	# Jolt queues kinematic transforms until the next step, even when an
	# AnimatableBody3D has sync_to_physics=false. Static bodies commit a teleport
	# immediately, including during SceneTree pause and same-frame ray queries.
	var body := StaticBody3D.new()
	body.name = body_name
	body.collision_layer = 8
	body.collision_mask = 0
	body.set_meta("entity_id", entity_id)
	body.set_meta("asset_source", source_key)
	source.add_child(body)
	_bodies.append(body)
	for mesh in meshes:
		var shape := mesh.mesh.create_trimesh_shape()
		if shape == null:
			_fail("Cannot build authored triangle collision: " + str(mesh.name))
			continue
		shape.backface_collision = true
		var collision := CollisionShape3D.new()
		collision.name = str(mesh.name) + "Faces"
		collision.shape = shape
		body.add_child(collision)
		collision.transform = body.global_transform.affine_inverse() * mesh.global_transform

func _prepare_glow(key: String) -> void:
	var meshes: Array[MeshInstance3D] = []
	_collect_meshes(_nodes[key], meshes)
	if meshes.is_empty():
		_fail("Independent emissive surface is missing: " + key)
		return
	_glows[key] = []
	for mesh in meshes:
		for surface in range(mesh.mesh.get_surface_count()):
			var original := mesh.get_active_material(surface) as BaseMaterial3D
			if original == null:
				_fail("Glow must use an imported PBR material: " + key)
				continue
			var material := original.duplicate() as BaseMaterial3D
			mesh.set_surface_override_material(surface, material)
			_glows[key].append({"material":material, "albedo":original.albedo_color,
				"emission":original.emission, "energy":maxf(original.emission_energy_multiplier, 1.0)})

func _glow(key: String, power: float) -> void:
	for item in _glows[key]:
		var material: BaseMaterial3D = item.material
		var color: Color = item.albedo
		material.albedo_color = color if power > 0 else Color(color.r * 0.22, color.g * 0.22, color.b * 0.22, color.a)
		material.emission_enabled = power > 0
		material.emission = item.emission
		material.emission_energy_multiplier = minf(float(item.energy) * power * EMISSION_SCALE, EMISSION_MULTIPLIER_CAP)

func _collect_meshes(node: Node, found: Array[MeshInstance3D]) -> void:
	if node is MeshInstance3D and node.mesh != null: found.append(node)
	for child in node.get_children():
		if not child is CollisionObject3D: _collect_meshes(child, found)

func _flush(node: Node) -> void:
	if node is Node3D: node.force_update_transform()
	for child in node.get_children(): _flush(child)

func _fail(message: String) -> void:
	import_errors.append(message)
	push_error("SiphonWhale import contract: " + message)
