class_name TwinShoreLayout
extends RefCounted
## Replaceable F1 graybox only. No scene wiring, shader mutation, saves or assets.
## Godot world metres. Geometry and queries share one piecewise-linear profile.
const DEFAULT_PATH := "res://data/v3/terrain/f1_shore_layout.json"
const ImportedGeometry = preload("res://scripts/v3/world/twin_imported_geometry.gd")
const MAX_ROWS := 32
const MAX_TRIANGLES := 16000
## Float32 world-space vertices/shader rows can differ by a few micrometres
## from JSON doubles. This is classification tolerance, not expanded geometry.
const SURFACE_EPSILON := 0.00001
var _data: Dictionary = {}
var _geometry: Dictionary = {}
var _footprints: Array = []

func load_layout(path: String = DEFAULT_PATH, verify_sources: bool = true) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null: return {"ok":false, "code":"layout_unreadable"}
	var parsed = JSON.parse_string(file.get_as_text())
	if not parsed is Dictionary: return {"ok":false, "code":"invalid_json"}
	return configure(parsed, verify_sources)

func configure(data: Dictionary, verify_sources: bool = true) -> Dictionary:
	var checked := _validate(data, verify_sources)
	if not checked.ok: return checked
	_data = data.duplicate(true)
	_geometry.clear()
	_build()
	return {"ok":true, "code":"graybox_ready", "parts":part_ids(),
		"source_verified":verify_sources and OS.has_feature("editor"), "imported_geometry_verified":verify_sources}

func definition() -> Dictionary:
	return _data.duplicate(true)

func part_ids() -> Array:
	return _geometry.keys()

func geometry(part: String) -> Dictionary:
	return _geometry.get(part, {}).duplicate(true)

func make_mesh(part: String) -> ArrayMesh:
	if not _geometry.has(part): return null
	var item: Dictionary = _geometry[part]
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = item.faces.duplicate()
	arrays[Mesh.ARRAY_NORMAL] = item.normals.duplicate()
	arrays[Mesh.ARRAY_TEX_UV] = item.uv.duplicate()
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh.resource_name = "F1 replaceable graybox / " + part
	return mesh

func make_shape(part: String) -> ConcavePolygonShape3D:
	# Water has no physical surface; the bed and banks provide solid contact.
	if part == "water" or not _geometry.has(part): return null
	var shape := ConcavePolygonShape3D.new()
	shape.set_faces(_geometry[part].faces.duplicate())
	shape.backface_collision = true
	return shape

func bank_edges(z: float) -> Dictionary:
	if _data.is_empty() or not is_finite(z) or z < -50.0 or z > 50.0: return {}
	var rows: Array = _data.profile
	for i in range(1, rows.size()):
		if z > float(rows[i][0]): continue
		var a: Array = rows[i - 1]
		var b: Array = rows[i]
		var t := (z - float(a[0])) / (float(b[0]) - float(a[0]))
		var left := lerpf(float(a[1]), float(b[1]), t)
		var right := lerpf(float(a[2]), float(b[2]), t)
		return {"left_top":left, "right_top":right, "left_water":left + float(_data.slope_width[0]),
			"right_water":right - float(_data.slope_width[1]), "water_y":float(_data.water_y),
			"west_top_y":float(_data.top_y[0]), "east_top_y":float(_data.top_y[1])}
	return {}

func bank_height(x: float, z: float) -> float:
	var edge := bank_edges(z)
	if edge.is_empty() or not is_finite(x) or absf(x) > 52.0: return NAN
	if x <= float(edge.left_top): return float(_data.top_y[0])
	if x <= float(edge.left_water):
		return lerpf(float(_data.top_y[0]), float(_data.water_y), (x - float(edge.left_top)) / float(_data.slope_width[0]))
	if x >= float(edge.right_top): return float(_data.top_y[1])
	if x >= float(edge.right_water):
		return lerpf(float(_data.top_y[1]), float(_data.water_y), (float(edge.right_top) - x) / float(_data.slope_width[1]))
	return float(_data.bottom_y)

func foundation_at(x: float, z: float) -> String:
	if not is_finite(x) or not is_finite(z): return ""
	var p := Vector2(x, z)
	for polygon in _footprints:
		if not polygon.bounds.grow(SURFACE_EPSILON).has_point(p): continue
		if _on_boundary(p, polygon.outer): return str(polygon.id)
		if not Geometry2D.is_point_in_polygon(p, polygon.outer): continue
		var in_hole := false
		for hole in polygon.holes:
			if _on_boundary(p, hole): return str(polygon.id)
			if Geometry2D.is_point_in_polygon(p, hole): in_hole = true; break
		if not in_hole: return str(polygon.id)
	return ""

func surface_height(x: float, z: float) -> float:
	var height := bank_height(x, z)
	if not is_finite(height): return height
	var id := foundation_at(x, z)
	for foundation in _data.get("foundations", []):
		if foundation.id == id: height = maxf(height, float(foundation.top_y))
	return height

func is_water_xz(x: float, z: float) -> bool:
	var edge := bank_edges(z)
	return not edge.is_empty() and is_finite(x) and x > float(edge.left_water) and x < float(edge.right_water) and foundation_at(x, z).is_empty()

func classify_point(point: Vector3) -> Dictionary:
	if not point.is_finite(): return {"kind":"outside", "water":false}
	var height := surface_height(point.x, point.z)
	if not is_finite(height): return {"kind":"outside", "water":false}
	var water := is_water_xz(point.x, point.z)
	var kind := "air"
	if point.y < float(_data.bottom_y) - SURFACE_EPSILON: kind = "below_bed"
	elif point.y <= height + SURFACE_EPSILON: kind = "solid"
	elif water and point.y <= float(_data.water_y): kind = "water"
	return {"kind":kind, "water":water, "surface_y":height, "water_y":float(_data.water_y), "foundation":foundation_at(point.x, point.z)}

func shader_data() -> Dictionary:
	var tops := PackedVector4Array()
	var water := PackedVector4Array()
	for row in _data.get("profile", []):
		var edge := bank_edges(float(row[0]))
		tops.append(Vector4(float(row[0]), edge.left_top, edge.right_top, 0))
		water.append(Vector4(float(row[0]), edge.left_water, edge.right_water, 0))
	var footprints: Array = []
	for foundation in _data.get("foundations", []):
		footprints.append({"id":foundation.id, "polygons":foundation.polygons.duplicate(true)})
	return {"count":tops.size(), "bank_points":tops, "water_points":water, "water_y":_data.get("water_y", -2.2),
		"foundation_polygons":footprints, "water_mesh_already_clipped":true, "foundation_foam_implemented":false,
		"interpolation":"Find z interval and linear-mix y/z components of the same two vec4 rows; no sinusoid or +/-8 fallback."}

## Exact maximum of the piecewise planar bank surface over an axis-aligned XZ
## rectangle, plus intersections with actual foundation top triangles.
## It proves only this new graybox's clearance, never the assembled scene.
func max_surface_in_rect(rect: Rect2) -> float:
	if _data.is_empty() or rect.size.x < 0 or rect.size.y < 0 or rect.position.x < -52 or rect.end.x > 52 or rect.position.y < -50 or rect.end.y > 50: return INF
	var zs: Array[float] = [rect.position.y, rect.end.y]
	for row in _data.profile:
		if float(row[0]) > rect.position.y and float(row[0]) < rect.end.y: zs.append(float(row[0]))
	var highest := float(_data.bottom_y)
	for z in zs:
		highest = maxf(highest, maxf(bank_height(rect.position.x, z), bank_height(rect.end.x, z)))
	var quad := PackedVector2Array([rect.position, Vector2(rect.end.x, rect.position.y), rect.end, Vector2(rect.position.x, rect.end.y)])
	for foundation in _data.foundations:
		if float(foundation.top_y) <= highest: continue
		for triangle in foundation.top_triangles_xz:
			if not Geometry2D.intersect_polygons(quad, _points(triangle)).is_empty():
				highest = float(foundation.top_y)
				break
	return highest

func clears_aabb(box: AABB, margin: float = 0.0) -> bool:
	return box.position.y > max_surface_in_rect(Rect2(Vector2(box.position.x, box.position.z), Vector2(box.size.x, box.size.z))) + margin

static func _points(values: Array) -> PackedVector2Array:
	var result := PackedVector2Array()
	for p in values: result.append(Vector2(float(p[0]), float(p[1])))
	return result

static func _inside_polygon(point: Vector2, polygon: Dictionary) -> bool:
	if not Geometry2D.is_point_in_polygon(point, _points(polygon.outer)): return false
	for hole in polygon.holes:
		if Geometry2D.is_point_in_polygon(point, _points(hole)): return false
	return true

static func _on_boundary(point: Vector2, ring: PackedVector2Array) -> bool:
	for i in ring.size():
		if point.distance_squared_to(Geometry2D.get_closest_point_to_segment(point, ring[i], ring[(i+1)%ring.size()])) <= SURFACE_EPSILON * SURFACE_EPSILON: return true
	return false

func _validate(data: Dictionary, verify_sources: bool) -> Dictionary:
	if data.get("schema_version") != 1 or data.get("id") != "f1_shore_layout_v1": return {"ok":false, "code":"schema"}
	for key in ["profile", "top_y", "slope_width", "foundations", "supports", "water_triangles_xz", "extents"]:
		if not data.get(key) is Array: return {"ok":false, "code":"array:" + key}
	if not _same_numbers(data.extents, [-52.0, -50.0, 52.0, 50.0]) or not _same_numbers(data.top_y, [0.0, 2.4]) or not _same_numbers([data.get("water_y"), data.get("bottom_y")], [-2.2, -3.2]): return {"ok":false, "code":"fixed_elevations_or_extents"}
	if data.slope_width.size() != 2: return {"ok":false, "code":"slopes"}
	for value in data.slope_width:
		if not _finite(value) or float(value) < 1.5 or float(value) > 2.0: return {"ok":false, "code":"slopes"}
	if data.profile.size() < 2 or data.profile.size() > MAX_ROWS: return {"ok":false, "code":"profile_count"}
	var last_z := -INF
	for row in data.profile:
		if not row is Array or row.size() != 3: return {"ok":false, "code":"profile_row"}
		for value in row:
			if not _finite(value): return {"ok":false, "code":"profile_number"}
		if float(row[0]) <= last_z or float(row[1]) <= -52 or float(row[2]) >= 52: return {"ok":false, "code":"profile_order_or_bounds"}
		if float(row[2]) - float(row[1]) - float(data.slope_width[0]) - float(data.slope_width[1]) < 12.0: return {"ok":false, "code":"channel_too_narrow"}
		last_z = float(row[0])
	if float(data.profile[0][0]) != -50 or float(data.profile.back()[0]) != 50: return {"ok":false, "code":"profile_endpoints"}
	if not data.get("generated_from") is Dictionary: return {"ok":false, "code":"generated_metadata"}
	var generated: Dictionary = data.generated_from
	for key in ["profile", "top_y", "slope_width", "water_y", "bottom_y"]:
		if generated.get(key) != data[key]: return {"ok":false, "code":"stale_derived_geometry:" + key}
	var signature_parts := PackedStringArray()
	for row in data.profile:
		for value in row: signature_parts.append("%.9f" % float(value))
	for value in data.slope_width + data.top_y + [data.water_y,data.bottom_y]: signature_parts.append("%.9f" % float(value))
	if "|".join(signature_parts).sha256_text() != generated.get("profile_sha256", ""): return {"ok":false, "code":"stale_derived_geometry:profile_sha256"}
	var crossing: Dictionary = generated.get("growth_crossing", {})
	if crossing.get("path", "") != "res://data/v3/terrain/f1_growth_crossing.json" or str(crossing.get("sha256", "")).length()!=64:
		return {"ok":false, "code":"crossing_source"}
	if verify_sources and FileAccess.get_sha256(crossing.path) != crossing.sha256:
		return {"ok":false, "code":"stale_crossing_foundation"}
	if data.foundations.size() > 7 or data.supports.size() != 6: return {"ok":false, "code":"support_count"}
	# Include both foundation caps and all side walls, not only top triangles.
	var triangles: int = data.water_triangles_xz.size() + (data.profile.size()-1)*22 + 16
	var ids: Dictionary = {}
	for foundation in data.foundations:
		if not foundation is Dictionary or not foundation.get("polygons") is Array or not foundation.get("top_triangles_xz") is Array: return {"ok":false, "code":"foundation"}
		var top_y := 2.9 if foundation.get("id", "") == "south_gate" else 0.0
		if not _same_numbers([foundation.get("top_y"), foundation.get("bottom_y")], [top_y, -3.2]): return {"ok":false, "code":"foundation"}
		if not foundation.get("id") is String or foundation.id.is_empty() or ids.has(foundation.id): return {"ok":false, "code":"foundation_id"}
		ids[foundation.id] = true
		triangles += foundation.top_triangles_xz.size()*2
		for polygon in foundation.polygons:
			if not polygon is Dictionary or not polygon.get("outer") is Array or not polygon.get("holes") is Array: return {"ok":false, "code":"footprint"}
			for ring in [polygon.outer] + polygon.holes:
				if not _valid_points(ring, 3, 2048): return {"ok":false, "code":"footprint_points"}
				triangles += ring.size()*2
		for triangle in foundation.top_triangles_xz:
			if not _valid_points(triangle, 3, 3): return {"ok":false, "code":"foundation_triangle"}
	if not ids.has("south_gate"): return {"ok":false, "code":"missing_gate_foundation"}
	if triangles > MAX_TRIANGLES: return {"ok":false, "code":"triangle_budget"}
	for triangle in data.water_triangles_xz:
		if not _valid_points(triangle, 3, 3): return {"ok":false, "code":"water_triangle"}
	var checked: Dictionary = {}
	for support in data.supports:
		if not support is Dictionary or not support.get("source") is Dictionary: return {"ok":false, "code":"source"}
		var source: Dictionary = support.source
		var path := str(source.get("path", ""))
		if not path.begins_with("res://assets/v3/root_buttress/") or not path.ends_with(".glb") or str(source.get("sha256", "")).length() != 64: return {"ok":false, "code":"source_path"}
		var imported: Dictionary = source.get("imported_geometry", {})
		if imported.get("algorithm", "") != ImportedGeometry.ALGORITHM or str(imported.get("sha256", "")).length() != 64:
			return {"ok":false, "code":"missing_imported_geometry_signature", "path":path}
		if verify_sources and not checked.has(path):
			# Export templates contain remapped scenes, not the original GLB bytes.
			# Both modes still verify actual imported vertices + transforms. Source
			# execution additionally checks GLB bytes; absence never bypasses it.
			if OS.has_feature("editor") and FileAccess.get_sha256(path) != source.sha256:
				return {"ok":false, "code":"stale_source_footprint", "path":path}
			var actual := ImportedGeometry.signature(path)
			if not actual.ok or actual.sha256 != imported.sha256:
				return {"ok":false, "code":"stale_imported_geometry", "path":path, "detail":actual.get("code", "")}
			checked[path] = {"raw":source.sha256, "imported":imported.sha256}
		elif verify_sources and checked[path] != {"raw":source.sha256, "imported":imported.sha256}:
			return {"ok":false, "code":"inconsistent_source_signature", "path":path}
	return {"ok":true}

static func _finite(value) -> bool:
	return (value is float or value is int) and is_finite(float(value))

static func _same_numbers(values: Array, expected: Array) -> bool:
	if values.size() != expected.size(): return false
	for i in values.size():
		if not _finite(values[i]) or absf(float(values[i]) - float(expected[i])) > 0.000001: return false
	return true

static func _valid_points(values, low: int, high: int) -> bool:
	if not values is Array or values.size() < low or values.size() > high: return false
	for point in values:
		if not point is Array or point.size() != 2 or not _finite(point[0]) or not _finite(point[1]) or absf(float(point[0])) > 52 or absf(float(point[1])) > 50: return false
	return true

func _new_part(id: String) -> void:
	_geometry[id] = {"faces":PackedVector3Array(), "normals":PackedVector3Array(), "uv":PackedVector2Array(),
		"status":"replaceable_graybox_not_final_art", "collision":id != "water"}

func _tri(id: String, a: Vector3, b: Vector3, c: Vector3, toward: Vector3) -> void:
	var normal := (b - a).cross(c - a)
	if normal.length_squared() < 1e-20: return
	# Godot renders clockwise triangles as front-facing. Its native PlaneMesh
	# therefore has a cross product opposite the outward lighting normal.
	if normal.dot(toward) > 0:
		var swap := b
		b = c
		c = swap
		normal = -normal
	normal = -normal.normalized()
	for p in [a, b, c]:
		_geometry[id].faces.append(p)
		_geometry[id].normals.append(normal)
		_geometry[id].uv.append(Vector2(p.x, p.z) * 0.25)

func _quad(id: String, a: Vector3, b: Vector3, c: Vector3, d: Vector3, toward: Vector3) -> void:
	_tri(id, a, b, c, toward)
	_tri(id, a, c, d, toward)

func _build() -> void:
	_footprints.clear()
	for foundation in _data.foundations:
		for polygon in foundation.polygons:
			var outer := _points(polygon.outer)
			var bounds := Rect2(outer[0], Vector2.ZERO)
			for p in outer: bounds = bounds.expand(p)
			var holes: Array[PackedVector2Array] = []
			for hole in polygon.holes: holes.append(_points(hole))
			_footprints.append({"id":foundation.id, "outer":outer, "holes":holes, "bounds":bounds})
	for id in ["west", "east", "bed", "water"]: _new_part(id)
	var floor_y := float(_data.bottom_y)
	var water_y := float(_data.water_y)
	for i in range(1, _data.profile.size()):
		var za := float(_data.profile[i - 1][0])
		var zb := float(_data.profile[i][0])
		var a := bank_edges(za)
		var b := bank_edges(zb)
		for side in [-1, 1]:
			var id := "west" if side < 0 else "east"
			var top_y := float(_data.top_y[0 if side < 0 else 1])
			var xa := float(a.left_top if side < 0 else a.right_top)
			var xb := float(b.left_top if side < 0 else b.right_top)
			var wa := float(a.left_water if side < 0 else a.right_water)
			var wb := float(b.left_water if side < 0 else b.right_water)
			var outside := float(side) * 52.0
			var outer_normal := Vector3(float(side), 0, 0)
			_quad(id, Vector3(outside, top_y, za), Vector3(xa, top_y, za), Vector3(xb, top_y, zb), Vector3(outside, top_y, zb), Vector3.UP)
			_quad(id, Vector3(xa, top_y, za), Vector3(wa, water_y, za), Vector3(wb, water_y, zb), Vector3(xb, top_y, zb), Vector3.UP)
			_quad(id, Vector3(wa, water_y, za), Vector3(wa, floor_y, za), Vector3(wb, floor_y, zb), Vector3(wb, water_y, zb), -outer_normal)
			_quad(id, Vector3(outside, floor_y, za), Vector3(outside, top_y, za), Vector3(outside, top_y, zb), Vector3(outside, floor_y, zb), outer_normal)
			_quad(id, Vector3(outside, floor_y, za), Vector3(wa, floor_y, za), Vector3(wb, floor_y, zb), Vector3(outside, floor_y, zb), Vector3.DOWN)
			for end in [0, 1]:
				if (end == 0 and i != 1) or (end == 1 and i != _data.profile.size() - 1): continue
				var z := za if end == 0 else zb
				var x := xa if end == 0 else xb
				var w := wa if end == 0 else wb
				var normal := Vector3(0, 0, -1 if end == 0 else 1)
				_quad(id, Vector3(outside, floor_y, z), Vector3(outside, top_y, z), Vector3(x, top_y, z), Vector3(x, floor_y, z), normal)
				_quad(id, Vector3(x, floor_y, z), Vector3(x, top_y, z), Vector3(w, water_y, z), Vector3(w, floor_y, z), normal)
		_quad("bed", Vector3(a.left_water, floor_y, za), Vector3(a.right_water, floor_y, za), Vector3(b.right_water, floor_y, zb), Vector3(b.left_water, floor_y, zb), Vector3.UP)
	for triangle in _data.water_triangles_xz: _flat_triangle("water", triangle, water_y, Vector3.UP)
	for foundation in _data.foundations:
		var id := "foundation:" + str(foundation.id)
		var top_y := float(foundation.top_y)
		_new_part(id)
		for triangle in foundation.top_triangles_xz:
			_flat_triangle(id, triangle, top_y, Vector3.UP)
			_flat_triangle(id, triangle, floor_y, Vector3.DOWN)
		for polygon in foundation.polygons:
			# Shapely output orientation may vary. Normalize each ring so its solid
			# lies to the left in XZ; outward lies to the right (including holes).
			for ring_index in range(1 + polygon.holes.size()):
				var ring := _points(polygon.outer if ring_index == 0 else polygon.holes[ring_index - 1])
				var signed_area := 0.0
				for j in ring.size(): signed_area += ring[j].cross(ring[(j + 1) % ring.size()])
				if (signed_area > 0) != (ring_index == 0): ring.reverse()
				for j in ring.size():
					var p := ring[j]
					var q := ring[(j + 1) % ring.size()]
					var outward := Vector3(q.y - p.y, 0, p.x - q.x)
					_quad(id, Vector3(p.x, top_y, p.y), Vector3(q.x, top_y, q.y), Vector3(q.x, floor_y, q.y), Vector3(p.x, floor_y, p.y), outward)
	for id in _geometry:
		_geometry[id].triangle_count = _geometry[id].faces.size() / 3

func _flat_triangle(id: String, triangle: Array, height: float, normal: Vector3) -> void:
	_tri(id, Vector3(float(triangle[0][0]), height, float(triangle[0][1])), Vector3(float(triangle[1][0]), height, float(triangle[1][1])), Vector3(float(triangle[2][0]), height, float(triangle[2][1])), normal)
