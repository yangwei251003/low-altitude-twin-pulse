class_name TwinCampaignLayout
extends RefCounted
## Low-cost authored boxes and supported routes; Root owns World3D and lifetime.
const PATH := "res://data/v3/campaign/layouts.json"

static func definition(region_id: String) -> Dictionary:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(PATH))
	if not parsed is Dictionary: return {}
	for region in parsed.get("regions", []):
		if region.get("id") == region_id: return region.duplicate(true)
	return {}

static func build_geometry(parent: Node3D, region_id: String) -> Dictionary:
	var spec: Dictionary = definition(region_id)
	if spec.is_empty(): return {"ok":false, "code":"campaign_layout_missing"}
	var root := Node3D.new()
	root.name = "CampaignLayout" + region_id
	parent.add_child(root)
	var bodies: Dictionary = {}
	var materials: Dictionary = {}
	for item in spec.get("solids", []):
		if not _point(item.get("position")) or not _point(item.get("size")):
			root.queue_free()
			return {"ok":false, "code":"campaign_layout_invalid"}
		var size: Vector3 = _vector(item.size)
		if minf(size.x, minf(size.y, size.z)) <= 0.0:
			root.queue_free()
			return {"ok":false, "code":"campaign_layout_invalid_size"}
		var body := StaticBody3D.new()
		body.name = str(item.id)
		body.position = _vector(item.position)
		body.collision_layer = 1
		body.collision_mask = 0
		body.set_meta("campaign_purpose", str(item.get("purpose", "")))
		root.add_child(body)
		var collider := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = size
		collider.shape = shape
		body.add_child(collider)
		var mesh := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = size
		mesh.mesh = box
		var tone: String = str(item.get("tone", "ground"))
		if not materials.has(tone):
			var material := StandardMaterial3D.new()
			material.albedo_color = Color(str(spec.palette.get(tone, "66736c")))
			material.roughness = 0.9
			materials[tone] = material
		mesh.material_override = materials[tone]
		body.add_child(mesh)
		bodies[str(item.id)] = body
	return {"ok":true, "code":"campaign_geometry_built", "root":root, "bodies":bodies, "definition":spec}

static func _point(value) -> bool:
	if not value is Array or value.size() != 3: return false
	for number in value:
		if not (number is int or number is float) or not is_finite(float(number)): return false
	return true

static func _vector(value: Array) -> Vector3:
	return Vector3(float(value[0]), float(value[1]), float(value[2]))
