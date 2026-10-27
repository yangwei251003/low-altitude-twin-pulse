class_name TwinTempleGate
extends Node3D
## F-B ring redirects energy; its central flight hole stays open at every angle.

const MODEL_PATH = "res://assets/v3/fantasy/temple_gate.glb"
var rotor_body: AnimatableBody3D
var rotor_visual: Node3D
var rotor_rest = Basis.IDENTITY
var imported = false
var angle = -PI / 3.0
var beam_visual: MeshInstance3D
var output_point = Vector3.ZERO

func _ready() -> void:
	var model = load(MODEL_PATH) as PackedScene
	if model:
		var visual = model.instantiate()
		add_child(visual)
		rotor_visual = visual.find_child("Rotor", true, false)
		if rotor_visual: rotor_rest = rotor_visual.basis
		imported = rotor_visual != null
	if not imported: push_error("F-B import requires an independent Rotor pivot")
	var fixed = StaticBody3D.new()
	fixed.name = "RootStoneFrame"
	fixed.collision_layer = 1
	fixed.set_meta("entity_id", "F1:mirror")
	add_child(fixed)
	for x in [-3.45, 3.45]:
		_shape(fixed, Vector3(x, 4.65, 0), Vector3(1.25, 7.7, 1.8))
	_shape(fixed, Vector3(0, 9.0, 0), Vector3(8.0, 1.2, 1.8))
	for i in range(3):
		_shape(fixed, Vector3(0, 0.15 + i * 0.3, 0), Vector3(8.8 - i * 0.5, 0.3, 4.0 - i * 0.5))
	rotor_body = AnimatableBody3D.new()
	rotor_body.name = "RotorCollision"
	rotor_body.sync_to_physics = false
	rotor_body.collision_layer = 1
	rotor_body.set_meta("entity_id", "F1:mirror")
	add_child(rotor_body)
	rotor_body.position = Vector3(0, 5.2, 0)
	# Sixteen convex pieces, never one convex hull spanning the central opening.
	for i in range(16):
		var a = TAU * i / 16.0
		var shape = _shape(rotor_body, Vector3(cos(a), sin(a), 0) * 2.55, Vector3(0.71, 1.01, 0.7))
		shape.rotation.z = a
	var emitter = MeshInstance3D.new()
	emitter.name = "OpticalPointer"
	var prism = PrismMesh.new()
	prism.size = Vector3(0.6, 0.85, 0.5)
	emitter.mesh = prism
	var material = StandardMaterial3D.new()
	material.albedo_color = Color("4fae9b")
	material.emission_enabled = true
	material.emission = Color("184b43")
	emitter.material_override = material
	rotor_body.add_child(emitter)
	emitter.position = Vector3(2.92, 0, 1.35)
	emitter.rotation.z = -PI * 0.5
	beam_visual = MeshInstance3D.new()
	beam_visual.name = "RedirectedLight"
	var cylinder = CylinderMesh.new()
	cylinder.top_radius = 0.045
	cylinder.bottom_radius = 0.045
	cylinder.radial_segments = 6
	cylinder.height = 1.0
	beam_visual.mesh = cylinder
	var light_material = StandardMaterial3D.new()
	light_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	light_material.albedo_color = Color("b6df9e")
	beam_visual.material_override = light_material
	add_child(beam_visual)
	beam_visual.visible = false
	set_angle(angle)

func set_angle(value: float) -> void:
	angle = value
	rotor_body.rotation.z = angle
	if rotor_visual: rotor_visual.basis = Basis(Vector3.FORWARD, -angle) * rotor_rest

func light_origin() -> Vector3:
	return to_global(Vector3(0, 5.2, 1.35) + Vector3(cos(angle), sin(angle), 0) * 3.2)

func light_endpoint() -> Vector3:
	return to_global(Vector3(0, 5.2, 1.35) + Vector3(cos(angle), sin(angle), 0) * 9.0)

func show_light(enabled: bool, endpoint: Vector3) -> void:
	beam_visual.visible = enabled
	if not enabled: return
	var start = light_origin()
	output_point = endpoint
	var offset = endpoint - start
	beam_visual.global_position = (start + endpoint) * 0.5
	beam_visual.quaternion = Quaternion(Vector3.UP, global_basis.inverse() * offset.normalized())
	beam_visual.scale = Vector3(1, offset.length(), 1)

func _shape(body: PhysicsBody3D, at: Vector3, size: Vector3) -> CollisionShape3D:
	var collision = CollisionShape3D.new()
	var box = BoxShape3D.new()
	box.size = size
	collision.shape = box
	body.add_child(collision)
	collision.position = at
	return collision
