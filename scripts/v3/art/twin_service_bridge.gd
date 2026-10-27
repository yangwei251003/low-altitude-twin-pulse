class_name TwinServiceBridge
extends Node3D
## I-B visual import is replaceable; physics and interaction remain in this wrapper.

const MODEL_PATH = "res://assets/v3/industrial/service_bridge.glb"
const TRAVEL = 2.8
var shutter_body: AnimatableBody3D
var shutter_shape: CollisionShape3D
var shutter_visual: Node3D
var slats: Array[Node3D] = []
var slat_origins: Array[Vector3] = []
var lift = 0.0
var imported = false

func _ready() -> void:
	var model = load(MODEL_PATH) as PackedScene
	if model:
		var visual = model.instantiate()
		add_child(visual)
		shutter_visual = visual.find_child("Shutter", true, false)
		if shutter_visual:
			for child in shutter_visual.get_children():
				if child is Node3D and str(child.name).begins_with("Slat_"):
					slats.append(child)
					slat_origins.append(child.position)
		imported = shutter_visual != null and slats.size() == 16
	if not imported: push_error("I-B import requires Shutter and sixteen Slat_XX nodes")
	var fixed = StaticBody3D.new()
	fixed.name = "BridgeStructure"
	fixed.collision_layer = 1
	add_child(fixed)
	_shape(fixed, Vector3(0, 4.55, 0), Vector3(12, 0.5, 4))
	for x in [-5.0, 5.0]:
		_shape(fixed, Vector3(x, 0.3, 0), Vector3(2.4, 0.6, 4.1))
		_shape(fixed, Vector3(x, 2.35, 0), Vector3(1.55, 3.5, 3.3))
		_shape(fixed, Vector3(x, 4.05, 0), Vector3(2.1, 0.5, 3.8))
	for z in [-1.9, 1.9]:
		for x in [-4.15, 4.15]:
			_shape(fixed, Vector3(x, 5.3, z), Vector3(3.6, 1.0, 0.12))
	for x in [-2.42, 2.42]:
		_shape(fixed, Vector3(x, 6.2, -1.75), Vector3(0.24, 2.8, 0.3))
	_shape(fixed, Vector3(0, 7.85, -1.75), Vector3(5.1, 0.5, 0.65))
	shutter_body = AnimatableBody3D.new()
	shutter_body.name = "ShutterCollision"
	shutter_body.sync_to_physics = false # Pose is set once per authoritative physics tick.
	shutter_body.collision_layer = 1
	add_child(shutter_body)
	shutter_shape = _shape(shutter_body, Vector3.ZERO, Vector3(4.4, TRAVEL, 0.18))
	_marker("PassStart", Vector3(0, 6.15, 3.1))
	_marker("PassEnd", Vector3(0, 6.15, -3.1))
	_marker("UnderStart", Vector3(0, 2, 3.8))
	_marker("UnderEnd", Vector3(0, 2, -3.8))
	_marker("DeckProbe", Vector3(3, 7, 0))
	set_lift(0.0)

func set_lift(value: float) -> void:
	lift = clampf(value, 0.0, TRAVEL)
	var remaining = TRAVEL - lift
	shutter_body.position = Vector3(0, 4.8 + lift + remaining * 0.5, -1.75)
	(shutter_shape.shape as BoxShape3D).size.y = maxf(0.01, remaining)
	shutter_body.collision_layer = 1 if remaining > 0.015 else 0
	# Each leaf slides into the roll housing. No stretching of ribs or UVs.
	for i in slats.size():
		slats[i].position = slat_origins[i] + Vector3.UP * lift
		slats[i].visible = slat_origins[i].y + lift < TRAVEL - 0.015

func marker_position(key: String) -> Vector3:
	return (get_node(key) as Node3D).global_position

func _shape(body: PhysicsBody3D, at: Vector3, size: Vector3) -> CollisionShape3D:
	var collision = CollisionShape3D.new()
	var box = BoxShape3D.new()
	box.size = size
	collision.shape = box
	body.add_child(collision)
	collision.position = at
	return collision

func _marker(key: String, at: Vector3) -> void:
	var marker = Marker3D.new()
	marker.name = key
	add_child(marker)
	marker.position = at
