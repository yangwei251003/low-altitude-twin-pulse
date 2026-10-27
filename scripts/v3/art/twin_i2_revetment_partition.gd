class_name TwinRevetmentPartition
extends RefCounted
## Visual-only geometry partition. Never installs nodes or mutates its source.
const Terrain = preload("res://scripts/v3/world/twin_i2_waterfront_terrain.gd")
const PARTS := ["bank", "dry_surface"]
const CUT_MIN := Vector3(12.25, -2.8, 2.3)
const CUT_MAX := Vector3(12.6, 0, 15.6)
const AREA_TOLERANCE_M2 := 0.0002 # Float32 source positions; not an expanded cut.
const MIN_CROSS_SQUARED := 1e-14
var _kept: Dictionary = {}
var _removed: Dictionary = {}
var _report: Dictionary = {}

func configure(source: Terrain) -> Dictionary:
	if source == null or not bool(source.summary().get("ok", false)):
		return _failure("configured_terrain_required")
	var staged_kept: Dictionary = {}
	var staged_removed: Dictionary = {}
	var measurements: Dictionary = {}
	for part: String in PARTS:
		var original: Dictionary = source.geometry(part)
		var valid: Dictionary = _validate(original)
		if not valid.ok: return _failure("source_" + part + ":" + str(valid.code))
		if part == "dry_surface":
			for point: Vector3 in original.faces:
				if point.y != CUT_MAX.y: return _failure("source_top_plane")
		var kept: Dictionary = _empty_geometry()
		var removed: Dictionary = _empty_geometry()
		var faces: PackedVector3Array = original.faces
		for first in range(0, faces.size(), 3):
			var polygon: Array[Dictionary] = []
			for offset in 3:
				var index: int = first + offset
				polygon.append({"p":faces[index], "n":original.normals[index], "uv":original.uv[index]})
			# Other bank orientations/planes are kept byte-for-byte. Boundary-only
			# contact with the rectangle is not permission to subdivide a triangle.
			var eligible: bool = part == "dry_surface" or _west_bank(polygon)
			var planes: Array = _planes(part)
			var intersection: Array[Dictionary] = polygon
			if eligible:
				for plane: Array in planes:
					intersection = _split(intersection, int(plane[0]), float(plane[1]), float(plane[2])).inside
			if not eligible or _polygon_area(intersection) <= 1e-12:
				_emit(kept, polygon, first / 3)
				continue
			var middle: Array[Dictionary] = polygon
			for plane: Array in planes:
				var pieces: Dictionary = _split(middle, int(plane[0]), float(plane[1]), float(plane[2]))
				_emit(kept, pieces.outside, first / 3)
				middle = pieces.inside
			_emit(removed, middle, first / 3)
		var kept_valid: Dictionary = _validate(kept)
		var removed_valid: Dictionary = _validate(removed)
		if not kept_valid.ok or not removed_valid.ok:
			return _failure("partition_invalid:" + part)
		var source_area: float = _area(original)
		var kept_area: float = _area(kept)
		var removed_area: float = _area(removed)
		var expected: float = (CUT_MAX.z - CUT_MIN.z) * ((CUT_MAX.y - CUT_MIN.y) if part == "bank" else (CUT_MAX.x - CUT_MIN.x))
		if absf(removed_area - expected) > AREA_TOLERANCE_M2:
			return _failure("incomplete_replacement_surface:" + part)
		if absf(source_area - kept_area - removed_area) > AREA_TOLERANCE_M2:
			return _failure("area_conservation:" + part)
		staged_kept[part] = kept
		staged_removed[part] = removed
		measurements[part] = {"source_area_m2":source_area, "retained_area_m2":kept_area,
			"removed_area_m2":removed_area, "source_triangles":faces.size() / 3,
			"retained_triangles":kept.faces.size() / 3, "removed_triangles":removed.faces.size() / 3,
			"source_attributes_sha256":_attributes_sha(original)}
	# The only state write occurs after both real input partitions validate.
	_kept = staged_kept
	_removed = staged_removed
	_report = {"ok":true, "code":"visual_partition_ready", "scope":"visual_geometry_only_no_collision_mutation",
		"cut_min":CUT_MIN, "cut_max":CUT_MAX, "parts":measurements,
		"untouched_parts":source.part_ids().filter(func(part: Variant) -> bool: return not part in PARTS),
		"source_collision_sha256":_sha(source.collision_faces().to_byte_array()),
		"area_tolerance_m2":AREA_TOLERANCE_M2, "collision_changed":false}
	return result()

func result() -> Dictionary:
	if _report.is_empty(): return _failure("not_configured")
	return {"ok":true, "code":"visual_partition_ready",
		"meshes":{"bank":make_mesh("bank"), "dry_surface":make_mesh("dry_surface")},
		"geometry":_kept.duplicate(true), "removed_geometry":_removed.duplicate(true), "report":summary()}

func summary() -> Dictionary:
	return _report.duplicate(true) if not _report.is_empty() else _failure("not_configured")

func geometry(part: String) -> Dictionary:
	return _kept.get(part, {}).duplicate(true)

func removed_geometry(part: String) -> Dictionary:
	return _removed.get(part, {}).duplicate(true)

func make_mesh(part: String) -> ArrayMesh:
	if not _kept.has(part): return null
	var data: Dictionary = _kept[part]
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = data.faces.duplicate()
	arrays[Mesh.ARRAY_NORMAL] = data.normals.duplicate()
	arrays[Mesh.ARRAY_TEX_UV] = data.uv.duplicate()
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh.resource_name = "I2 west revetment visible remainder / " + part
	return mesh

static func _planes(part: String) -> Array:
	if part == "bank": return [[1, CUT_MIN.y, 1.0], [1, CUT_MAX.y, -1.0], [2, CUT_MIN.z, 1.0], [2, CUT_MAX.z, -1.0]]
	return [[0, CUT_MIN.x, 1.0], [0, CUT_MAX.x, -1.0], [2, CUT_MIN.z, 1.0], [2, CUT_MAX.z, -1.0]]

static func _west_bank(polygon: Array[Dictionary]) -> bool:
	for vertex: Dictionary in polygon:
		if vertex.p.x != CUT_MAX.x or vertex.n.dot(Vector3.RIGHT) < 0.99999: return false
	return true

static func _split(polygon: Array[Dictionary], axis: int, edge: float, sign_value: float) -> Dictionary:
	var inside: Array[Dictionary] = []
	var outside: Array[Dictionary] = []
	for index in polygon.size():
		var a: Dictionary = polygon[index]
		var b: Dictionary = polygon[(index + 1) % polygon.size()]
		var pa: Vector3 = a.p
		var pb: Vector3 = b.p
		var da: float = (pa[axis] - edge) * sign_value
		var db: float = (pb[axis] - edge) * sign_value
		var a_inside: bool = da >= 0.0
		var b_inside: bool = db >= 0.0
		if a_inside: inside.append(a)
		else: outside.append(a)
		if a_inside != b_inside:
			var t: float = da / (da - db)
			var position: Vector3 = pa.lerp(pb, t)
			position[axis] = edge # Exact authored plane; no epsilon expansion.
			var normal_a: Vector3 = a.n
			var normal_b: Vector3 = b.n
			var uv_a: Vector2 = a.uv
			var uv_b: Vector2 = b.uv
			var vertex: Dictionary = {"p":position, "n":normal_a if normal_a == normal_b else normal_a.lerp(normal_b, t).normalized(), "uv":uv_a.lerp(uv_b, t)}
			inside.append(vertex)
			outside.append(vertex)
	return {"inside":_clean(inside), "outside":_clean(outside)}

static func _clean(polygon: Array[Dictionary]) -> Array[Dictionary]:
	var result_polygon: Array[Dictionary] = []
	for vertex: Dictionary in polygon:
		if result_polygon.is_empty() or result_polygon.back().p != vertex.p: result_polygon.append(vertex)
	if result_polygon.size() > 1 and result_polygon.front().p == result_polygon.back().p: result_polygon.pop_back()
	return result_polygon

static func _emit(destination: Dictionary, polygon: Array[Dictionary], source_triangle: int) -> void:
	for index in range(1, polygon.size() - 1):
		var a: Vector3 = polygon[0].p
		var b: Vector3 = polygon[index].p
		var c: Vector3 = polygon[index + 1].p
		if (b - a).cross(c - a).length_squared() <= MIN_CROSS_SQUARED: continue
		for vertex: Dictionary in [polygon[0], polygon[index], polygon[index + 1]]:
			destination.faces.append(vertex.p)
			destination.normals.append(vertex.n)
			destination.uv.append(vertex.uv)
		destination.source_triangles.append(source_triangle)

static func _validate(data: Dictionary) -> Dictionary:
	if not data.get("faces") is PackedVector3Array or not data.get("normals") is PackedVector3Array or not data.get("uv") is PackedVector2Array:
		return _failure("attribute_types")
	var faces: PackedVector3Array = data.faces
	var normals: PackedVector3Array = data.normals
	var uv: PackedVector2Array = data.uv
	if faces.is_empty() or faces.size() % 3 != 0 or normals.size() != faces.size() or uv.size() != faces.size(): return _failure("attribute_lengths")
	for index in range(0, faces.size(), 3):
		var cross: Vector3 = (faces[index + 1] - faces[index]).cross(faces[index + 2] - faces[index])
		if not cross.is_finite() or cross.length_squared() <= MIN_CROSS_SQUARED: return _failure("degenerate_triangle")
		for offset in 3:
			var at: int = index + offset
			if not faces[at].is_finite() or not normals[at].is_finite() or not uv[at].is_finite(): return _failure("nonfinite_attribute")
			if absf(normals[at].length_squared() - 1.0) > 0.00002 or cross.dot(normals[at]) >= 0: return _failure("normal_or_winding")
	return {"ok":true, "code":"valid"}

static func _empty_geometry() -> Dictionary:
	return {"faces":PackedVector3Array(), "normals":PackedVector3Array(), "uv":PackedVector2Array(), "source_triangles":PackedInt32Array()}

static func _polygon_area(polygon: Array[Dictionary]) -> float:
	var area := 0.0
	for index in range(1, polygon.size() - 1):
		var a: Vector3 = polygon[0].p
		var b: Vector3 = polygon[index].p
		var c: Vector3 = polygon[index + 1].p
		area += (b - a).cross(c - a).length() * 0.5
	return area

static func _area(data: Dictionary) -> float:
	var area := 0.0
	var faces: PackedVector3Array = data.faces
	for index in range(0, faces.size(), 3): area += (faces[index + 1] - faces[index]).cross(faces[index + 2] - faces[index]).length() * 0.5
	return area

static func _attributes_sha(data: Dictionary) -> String:
	var bytes: PackedByteArray = data.faces.to_byte_array()
	bytes.append_array(data.normals.to_byte_array())
	bytes.append_array(data.uv.to_byte_array())
	return _sha(bytes)

static func _sha(bytes: PackedByteArray) -> String:
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	context.update(bytes)
	return context.finish().hex_encode()

static func _failure(code: String) -> Dictionary:
	return {"ok":false, "code":code}
