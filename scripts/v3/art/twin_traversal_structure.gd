class_name TwinTraversalStructure
extends Node3D
## Reimport-safe static geometry. Traversable holes use authored triangles.
const MODELS = {"overpass":"res://assets/v3/overpass/maintenance_overpass.glb", "root_arch":"res://assets/v3/root_arch/f1_root_arch.glb"}
const COLLISION_MESHES = {"overpass":["DeckPanels", "SteelStructure", "RailingsHardware"], "root_arch":["WalkableRoot", "StoneRemnants"]}
const ANCHORS = {"overpass":["DeckLanding", "UnderpassEntry", "UnderpassExit"], "root_arch":["EntryWest", "Crown", "EntryEast", "Underpass"]}
@export_enum("overpass", "root_arch") var asset_kind = "overpass"
var imported = false
var visual: Node3D
var collision_body: StaticBody3D
var anchors: Dictionary = {}
var collision_mesh_count = 0
static var _shape_cache: Dictionary = {}

func _ready() -> void:
	var packed = load(MODELS[asset_kind]) as PackedScene
	if packed == null:
		push_error("Missing traversal asset: " + asset_kind)
		return
	visual = packed.instantiate()
	add_child(visual)
	collision_body = StaticBody3D.new()
	collision_body.name = "AuthoredTraversalCollision"
	collision_body.collision_layer = 1
	add_child(collision_body)
	for mesh_name in COLLISION_MESHES[asset_kind]:
		var mesh = visual.find_child(mesh_name, true, false) as MeshInstance3D
		if mesh == null or mesh.mesh == null:
			push_error("Traversal mesh missing: " + str(mesh_name))
			return
		var key = str(MODELS[asset_kind]) + ":" + str(mesh_name)
		if not _shape_cache.has(key): _shape_cache[key] = mesh.mesh.create_trimesh_shape()
		var shape = CollisionShape3D.new()
		shape.name = mesh_name
		shape.shape = _shape_cache[key]
		collision_body.add_child(shape)
		shape.transform = collision_body.global_transform.affine_inverse() * mesh.global_transform
		collision_mesh_count += 1
	for anchor in ANCHORS[asset_kind]:
		var marker = visual.find_child(anchor, true, false) as Node3D
		if marker == null:
			push_error("Traversal anchor missing: " + str(anchor))
			return
		anchors[anchor] = marker
	imported = true

func marker_position(id: String) -> Vector3:
	return anchors[id].global_position if imported and anchors.has(id) else Vector3.INF
