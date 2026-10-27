class_name TwinRisingSeal
extends AnimatableBody3D
## The moving slab owns its visible geometry and matching triangle collision.
## The world owns travel, authority and the conservative anti-crush sweep.
const MODEL_PATH = "res://assets/v3/rising_seal/rising_seal.glb"
const EXPECTED_MESHES = ["StoneMasses", "LivingRoots", "BronzeFittings", "SealEnergyGlass"]
const ANCHORS = {"Centre":Vector3.ZERO, "BottomContact":Vector3(0,-2.5,0), "StateInlay":Vector3(0.49,-0.1,0)}
var imported = false
var import_errors: Array[String] = []
var visual: Node3D
var core_materials: Array[StandardMaterial3D] = []
var triangles = 0
var collision_parts = 0

func _ready() -> void:
	collision_layer = 1
	collision_mask = 0
	sync_to_physics = false
	if visual == null:
		var model = load(MODEL_PATH) as PackedScene
		if model: install_model(model.instantiate())
	if not imported: push_error("Rising seal import: " + str(import_errors))
	set_gate_state(0.0, false)

func install_model(model: Node3D) -> void:
	# Also accepts the byte-checked raw GLB in an isolated review process.
	assert(visual == null)
	visual = model
	add_child(visual)
	if not model.transform.is_equal_approx(Transform3D.IDENTITY): import_errors.append("root_transform")
	var meshes = visual.find_children("*", "MeshInstance3D", true, false)
	var names: Array[String] = []
	for mesh: MeshInstance3D in meshes:
		names.append(str(mesh.name))
		if mesh.mesh == null: continue
		var collider = CollisionShape3D.new()
		collider.name = "Collision_" + mesh.name
		collider.shape = mesh.mesh.create_trimesh_shape()
		collider.shape.backface_collision = true
		var relative = Transform3D.IDENTITY
		var ancestor: Node = mesh
		while ancestor != self:
			if ancestor is Node3D: relative = ancestor.transform * relative
			ancestor = ancestor.get_parent()
		collider.transform = relative
		add_child(collider)
		triangles += mesh.mesh.get_faces().size() / 3
		collision_parts += 1
		if mesh.name == "SealEnergyGlass":
			for surface in range(mesh.mesh.get_surface_count()):
				var original = mesh.get_active_material(surface)
				if original is StandardMaterial3D:
					var local = original.duplicate() as StandardMaterial3D
					mesh.set_surface_override_material(surface, local)
					core_materials.append(local)
	if collision_parts != 4 or triangles != 18528: import_errors.append("source_geometry")
	for expected in EXPECTED_MESHES:
		if names.count(expected) != 1: import_errors.append("mesh:" + expected)
	if core_materials.is_empty(): import_errors.append("core_material")
	for anchor in ANCHORS:
		var marker = visual.find_child(anchor, true, false) as Node3D
		if marker == null or not marker.position.is_equal_approx(ANCHORS[anchor]):
			import_errors.append("anchor:" + anchor)
	imported = import_errors.is_empty()

func set_gate_state(fraction: float, supplied: bool) -> void:
	# No authority or geometry changes here; brightness follows the same state
	# that raises the slab, including restored and replicated world snapshots.
	var intensity = lerpf(0.12, 1.65, clampf(fraction, 0.0, 1.0))
	if supplied: intensity = maxf(intensity, 0.65)
	for material in core_materials:
		material.emission_enabled = true
		# The authored emissive texture already carries the turquoise colour.
		# Multiplying it by a second dark tint made powered/open states unreadable.
		material.emission = Color.WHITE
		material.emission_energy_multiplier = intensity
