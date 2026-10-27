extends SceneTree
## Actual configured Terrain -> visual partition. No World/GLB/physics stepping.
## Geometry2D intersections and barycentric source attribution are independent
## checks of the candidate's clipping, rather than its own helper as an oracle.
const Terrain = preload("res://scripts/v3/world/twin_i2_waterfront_terrain.gd")
const Partition = preload("res://scripts/v3/art/twin_i2_revetment_partition.gd")
var checks := 0
var failures: Array = []
var measurements: Dictionary = {}

class ErrorLogger extends Logger:
	var errors: Array = []
	func _log_error(function: String, file: String, line: int, code: String, rationale: String, _notify: bool, error_type: int, _backtraces: Array[ScriptBacktrace]) -> void:
		errors.append({"function":function, "file":file, "line":line, "code":code, "rationale":rationale, "type":error_type})

class BadAttributeTerrain extends Terrain:
	# A declared malformed-copy fixture; the original production geometry stays real.
	var fault := "uv_length"
	func geometry(part: String) -> Dictionary:
		var copied: Dictionary = super.geometry(part)
		if part == "dry_surface":
			if fault == "uv_length": copied.uv.resize(copied.uv.size() - 1)
			elif fault == "nonfinite": copied.faces[0] = Vector3(NAN, 0, 0)
			elif fault == "degenerate": copied.faces[1] = copied.faces[0]
			elif fault == "winding":
				var value: Vector3 = copied.faces[0]
				copied.faces[0] = copied.faces[1]
				copied.faces[1] = value
		return copied

var logger := ErrorLogger.new()

func _init() -> void:
	OS.add_logger(logger)
	_run.call_deferred()

func _run() -> void:
	var started: int = Time.get_ticks_msec()
	var source := Terrain.new()
	var source_ready: Dictionary = source.configure()
	_check(source_ready.ok, "actual production Terrain configures", source_ready)
	if not source_ready.ok:
		_finish(started)
		return
	var original: Dictionary = _source_bytes(source)
	var collision_bytes: PackedByteArray = source.collision_faces().to_byte_array()
	var original_shape: ConcavePolygonShape3D = source.make_shape(Vector3(0, -0.2, 0))
	var shape_bytes: PackedByteArray = original_shape.get_faces().to_byte_array()
	var candidate := Partition.new()
	_check(not candidate.result().ok and candidate.make_mesh("bank") == null, "unconfigured candidate returns no usable mesh")
	var built: Dictionary = candidate.configure(source)
	_check(built.ok, "candidate consumes actual configured source", {"code":built.get("code")})
	if not built.ok:
		_finish(started)
		return
	measurements = built.report.duplicate(true)
	_check(built.meshes.size() == 2 and built.geometry.size() == 2 and built.meshes.has("bank") and built.meshes.has("dry_surface"), "only two replacement render parts are returned")
	var definition: Dictionary = source.definition()
	var profile: Array = definition.profile
	var first: Vector3 = profile[0]
	var second: Vector3 = profile[1]
	var length_m: float = second.x - first.x
	var height_m: float = float(definition.top_y) - float(definition.bed_y)
	_check(absf(_area(built.removed_geometry.bank.faces) - length_m * height_m) < 0.0002, "removed bank area derives from actual first PROFILE edge and depth")
	_check(absf(_area(built.removed_geometry.dry_surface.faces) - length_m * 0.35) < 0.0002, "removed top area derives from actual PROFILE length and 350mm asset thickness")
	for part: String in ["bank", "dry_surface"]:
		_audit_part(source.geometry(part), built.geometry[part], built.removed_geometry[part], built.meshes[part], source.make_mesh(part), part)
	_probe_top(source.geometry("dry_surface"), built.geometry.dry_surface, built.removed_geometry.dry_surface)
	_check(_source_bytes(source) == original and source.collision_faces().to_byte_array() == collision_bytes, "every original geometry/UV/normal and collision byte remains unchanged")
	_check(original_shape.get_faces().to_byte_array() == shape_bytes, "pre-existing actual ConcavePolygonShape data remains unchanged")
	_check(source.water_at(Vector3(14.75, -0.5, 6)).water and not source.water_at(Vector3(12.4, -0.5, 6)).water, "source water footprint still distinguishes channel from removed visual top strip")
	var stable: PackedByteArray = _candidate_bytes(candidate)
	var second_result: Dictionary = candidate.configure(source)
	_check(second_result.ok and _candidate_bytes(candidate) == stable, "repeat successful configure is deterministic and does not accumulate cuts")
	# Returned meshes/arrays/reports are disposable, never handles into the source.
	built.geometry.bank.faces[0] = Vector3(999, 999, 999)
	built.removed_geometry.bank.uv.clear()
	built.report.parts.bank.removed_area_m2 = -1
	built.meshes.bank.clear_surfaces()
	_check(_candidate_bytes(candidate) == stable and _source_bytes(source) == original and candidate.make_mesh("bank").get_surface_count() == 1, "caller mutations of results do not corrupt either successful candidate or source")
	for rejected_source: Terrain in [null, Terrain.new()]:
		var rejection: Dictionary = candidate.configure(rejected_source)
		_check(not rejection.ok and _candidate_bytes(candidate) == stable, "missing/unconfigured source leaves last successful candidate intact", rejection)
	var bad := BadAttributeTerrain.new()
	_check(bad.configure().ok, "negative attribute fixture starts from actual configured Terrain")
	for fault: String in ["uv_length", "nonfinite", "degenerate", "winding"]:
		bad.fault = fault
		var rejected: Dictionary = candidate.configure(bad)
		_check(not rejected.ok and _candidate_bytes(candidate) == stable, "bad " + fault + " rejects before replacing either visible part", rejected)
	var paved_strip := Terrain.new()
	_check(paved_strip.configure([Rect2(12.3, 5, 0.2, 1)]).ok, "negative ownership fixture is a valid actual Terrain with authored paving in replacement strip")
	var paved_before: Dictionary = _source_bytes(paved_strip)
	var incomplete: Dictionary = candidate.configure(paved_strip)
	_check(not incomplete.ok and str(incomplete.code).begins_with("incomplete_replacement_surface") and _candidate_bytes(candidate) == stable and _source_bytes(paved_strip) == paved_before, "refuses to silently remove or assume ownership of an already authored top patch", incomplete)
	var no_paving := Terrain.new()
	_check(no_paving.configure([]).ok, "second real source has different authored partition")
	var alternate: Dictionary = candidate.configure(no_paving)
	_check(alternate.ok and absf(_area(alternate.geometry.dry_surface.faces) - _area(second_result.geometry.dry_surface.faces) - float(source.summary().authored_area_m2)) < 0.001, "reconfigure derives geometry from new real source rather than cached default triangles")
	_check(candidate.configure(source).ok and _candidate_bytes(candidate) == stable, "original source may be reconfigured after valid alternate and rejected inputs")
	_check(_source_bytes(source) == original and source.collision_faces().to_byte_array() == collision_bytes, "all successful/rejected repeats preserve original collision and all seven source parts")
	_check(measurements == candidate.summary() and absf(float(measurements.parts.bank.removed_area_m2) - _area(candidate.removed_geometry("bank").faces)) < 0.000001, "final captured report remains detached from tampered result and matches actual removed bank area", {"reported_removed_bank_m2":measurements.parts.bank.removed_area_m2, "actual_removed_bank_m2":_area(candidate.removed_geometry("bank").faces)})
	_finish(started)

func _audit_part(original: Dictionary, kept: Dictionary, removed: Dictionary, mesh: ArrayMesh, original_mesh: ArrayMesh, part: String) -> void:
	var source_faces: PackedVector3Array = original.faces
	var grouped: Dictionary = {}
	var attributes_ok := true
	var winding_ok := true
	var duplicates: Dictionary = {}
	var duplicate_count := 0
	var kept_cut_area := 0.0
	var removed_outside := 0.0
	for bucket: Dictionary in [kept, removed]:
		var is_removed: bool = bucket == removed
		var faces: PackedVector3Array = bucket.faces
		for at in range(0, faces.size(), 3):
			var source_id: int = bucket.source_triangles[at / 3]
			var origin: int = source_id * 3
			var a: Vector3 = source_faces[origin]
			var b: Vector3 = source_faces[origin + 1]
			var c: Vector3 = source_faces[origin + 2]
			var normal: Vector3 = original.normals[origin]
			var cross: Vector3 = (faces[at + 1] - faces[at]).cross(faces[at + 2] - faces[at])
			winding_ok = winding_ok and cross.length_squared() > 1e-14 and cross.dot(normal) < 0
			var ids: Array[String] = []
			for offset in 3:
				var index: int = at + offset
				var point: Vector3 = faces[index]
				var weights: Vector3 = _barycentric(point, a, b, c)
				var expected_uv: Vector2 = original.uv[origin] * weights.x + original.uv[origin + 1] * weights.y + original.uv[origin + 2] * weights.z
				attributes_ok = attributes_ok and point.is_finite() and absf((point - a).dot(normal)) < 0.00001 and weights.x >= -0.00001 and weights.y >= -0.00001 and weights.z >= -0.00001
				attributes_ok = attributes_ok and bucket.normals[index].is_equal_approx(normal) and bucket.uv[index].distance_to(expected_uv) < 0.00001
				ids.append("%.9f,%.9f,%.9f" % [point.x, point.y, point.z])
			ids.sort()
			var key: String = "|".join(ids)
			if duplicates.has(key): duplicate_count += 1
			duplicates[key] = true
			var tri: PackedVector3Array = PackedVector3Array([faces[at], faces[at + 1], faces[at + 2]])
			if not grouped.has(source_id): grouped[source_id] = []
			grouped[source_id].append(tri)
			var cut_area: float = _cut_overlap(tri, part)
			if is_removed: removed_outside += maxf(_area(tri) - cut_area, 0.0)
			else: kept_cut_area += cut_area
	_check(attributes_ok and winding_ok and duplicate_count == 0, part + " every output vertex belongs to its source triangle with original metric UV/normal and valid clockwise winding", {"attributes":attributes_ok, "winding":winding_ok, "duplicates":duplicate_count})
	_check(kept_cut_area < 0.00005 and removed_outside < 0.00005, part + " independent polygon intersection finds no retained interior or removal outside footprint", {"retained_inside_m2":kept_cut_area, "removed_outside_m2":removed_outside})
	var source_balance := true
	var untouched_exact := true
	var maximum_overlap := 0.0
	for origin in range(0, source_faces.size(), 3):
		var source_id: int = origin / 3
		var source_tri := PackedVector3Array([source_faces[origin], source_faces[origin + 1], source_faces[origin + 2]])
		var fragments: Array = grouped.get(source_id, [])
		var sum_area := 0.0
		for fragment: PackedVector3Array in fragments: sum_area += _area(fragment)
		source_balance = source_balance and absf(sum_area - _area(source_tri)) < 0.0002
		if _cut_overlap(source_tri, part) < 1e-9:
			untouched_exact = untouched_exact and fragments.size() == 1 and fragments[0].to_byte_array() == source_tri.to_byte_array()
		for left in fragments.size():
			for right in range(left + 1, fragments.size()):
				maximum_overlap = maxf(maximum_overlap, _projected_overlap(fragments[left], fragments[right], original.normals[origin]))
	_check(source_balance and maximum_overlap < 0.00005, part + " each actual source triangle is conserved with no fragment overlap", {"maximum_overlap_m2":maximum_overlap})
	_check(untouched_exact, part + " triangles with no positive-area cut remain byte-identical, including neighbouring corner banks")
	_check(absf(_area(source_faces) - _area(kept.faces) - _area(removed.faces)) < 0.0002, part + " independently measured total area is conserved")
	var arrays: Array = mesh.surface_get_arrays(0)
	var source_arrays: Array = original_mesh.surface_get_arrays(0)
	var stored_normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var source_stored_normals: PackedVector3Array = source_arrays[Mesh.ARRAY_NORMAL]
	var normals_same: bool = stored_normals.size() == kept.normals.size()
	# Compare both normal arrays through the actual same ArrayMesh storage path;
	# exact input attributes/provenance were checked separately above.
	if normals_same:
		for index in stored_normals.size():
			var source_id: int = kept.source_triangles[index / 3]
			normals_same = normals_same and stored_normals[index] == source_stored_normals[source_id * 3]
	_check(mesh.get_surface_count() == 1 and mesh.surface_get_primitive_type(0) == Mesh.PRIMITIVE_TRIANGLES and arrays[Mesh.ARRAY_VERTEX].to_byte_array() == kept.faces.to_byte_array() and normals_same and arrays[Mesh.ARRAY_TEX_UV] == kept.uv, part + " actual ArrayMesh retains exact positions/UV and the source normal storage result")

func _probe_top(before: Dictionary, after: Dictionary, removed: Dictionary) -> void:
	var ok := true
	var samples := 0
	# Edge-adjacent samples exercise all four boundaries without relying on a
	# centroid decision. Points include just outside the 350mm landward strip.
	for x: float in [12.249, 12.251, 12.4, 12.599, 12.601]:
		for z: float in [2.299, 2.301, 6.3, 10.3, 14.3, 15.599, 15.601]:
			var point := Vector3(x, 0, z)
			var existed: bool = _contains(before.faces, point)
			var cut: bool = x > 12.25 and x < 12.6 and z > 2.3 and z < 15.6
			ok = ok and _contains(after.faces, point) == (existed and not cut) and _contains(removed.faces, point) == (existed and cut)
			samples += 1
	_check(ok, "35 independent edge-adjacent coverage probes preserve outside top and remove the whole interior", {"samples":samples})

static func _cut_overlap(triangle: PackedVector3Array, part: String) -> float:
	if part == "bank":
		for point: Vector3 in triangle:
			if absf(point.x - 12.6) > 0.00001: return 0.0
	var polygon := PackedVector2Array()
	for point: Vector3 in triangle: polygon.append(Vector2(point.y, point.z) if part == "bank" else Vector2(point.x, point.z))
	var min_x: float = -2.8 if part == "bank" else 12.25
	var max_x: float = 0.0 if part == "bank" else 12.6
	var rectangle := PackedVector2Array([Vector2(min_x, 2.3), Vector2(max_x, 2.3), Vector2(max_x, 15.6), Vector2(min_x, 15.6)])
	var area := 0.0
	for overlap: PackedVector2Array in Geometry2D.intersect_polygons(polygon, rectangle): area += _area2(overlap)
	return area

static func _projected_overlap(a: PackedVector3Array, b: PackedVector3Array, normal: Vector3) -> float:
	var axis: int = normal.abs().max_axis_index()
	var pa := PackedVector2Array()
	var pb := PackedVector2Array()
	for point: Vector3 in a: pa.append(_project(point, axis))
	for point: Vector3 in b: pb.append(_project(point, axis))
	var area := 0.0
	for polygon: PackedVector2Array in Geometry2D.intersect_polygons(pa, pb): area += _area2(polygon)
	return area / absf(normal[axis])

static func _project(point: Vector3, dropped_axis: int) -> Vector2:
	if dropped_axis == 0: return Vector2(point.y, point.z)
	if dropped_axis == 1: return Vector2(point.x, point.z)
	return Vector2(point.x, point.y)

static func _contains(faces: PackedVector3Array, point: Vector3) -> bool:
	for index in range(0, faces.size(), 3):
		var w: Vector3 = _barycentric(point, faces[index], faces[index + 1], faces[index + 2])
		if w.x >= -0.0000001 and w.y >= -0.0000001 and w.z >= -0.0000001: return true
	return false

static func _barycentric(point: Vector3, a: Vector3, b: Vector3, c: Vector3) -> Vector3:
	var axis: int = (b - a).cross(c - a).abs().max_axis_index()
	var pa: Vector2 = _project(a, axis)
	var pb: Vector2 = _project(b, axis)
	var pc: Vector2 = _project(c, axis)
	var pp: Vector2 = _project(point, axis)
	# Scalar arithmetic avoids subtracting near-equal squared Float32 dot products
	# for the narrow retained fragments next to a long source triangle.
	var denominator: float = (pb.x - pa.x) * (pc.y - pa.y) - (pc.x - pa.x) * (pb.y - pa.y)
	var v: float = ((pp.x - pa.x) * (pc.y - pa.y) - (pc.x - pa.x) * (pp.y - pa.y)) / denominator
	var w: float = ((pb.x - pa.x) * (pp.y - pa.y) - (pp.x - pa.x) * (pb.y - pa.y)) / denominator
	return Vector3(1.0 - v - w, v, w)

static func _area(faces: PackedVector3Array) -> float:
	var total := 0.0
	for index in range(0, faces.size(), 3): total += (faces[index + 1] - faces[index]).cross(faces[index + 2] - faces[index]).length() * 0.5
	return total

static func _area2(polygon: PackedVector2Array) -> float:
	var sum := 0.0
	for index in polygon.size(): sum += polygon[index].cross(polygon[(index + 1) % polygon.size()])
	return absf(sum) * 0.5

static func _source_bytes(source: Terrain) -> Dictionary:
	var result: Dictionary = {"definition":var_to_bytes(source.definition()), "summary":var_to_bytes(source.summary()), "collision":source.collision_faces().to_byte_array()}
	for part: String in source.part_ids(): result[part] = var_to_bytes(source.geometry(part))
	return result

static func _candidate_bytes(candidate: Partition) -> PackedByteArray:
	return var_to_bytes({"bank":candidate.geometry("bank"), "dry_surface":candidate.geometry("dry_surface"), "removed_bank":candidate.removed_geometry("bank"), "removed_top":candidate.removed_geometry("dry_surface"), "report":candidate.summary()})

func _check(ok: bool, label: String, details: Dictionary = {}) -> void:
	checks += 1
	if not ok:
		failures.append({"check":label, "details":details})
		print("REVETMENT_PARTITION_FAIL " + label + " " + JSON.stringify(details))

func _finish(started: int) -> void:
	print("V3_REVETMENT_PARTITION_TESTS " + JSON.stringify({"checks":checks, "failures":failures, "engine_errors":logger.errors, "elapsed_ms":Time.get_ticks_msec() - started, "geometry":measurements, "scope":"actual Terrain and ArrayMesh geometry only; no installed scene/GLB/GPU/flight/network proof"}))
	OS.remove_logger(logger)
	quit(0 if failures.is_empty() and logger.errors.is_empty() else 1)
