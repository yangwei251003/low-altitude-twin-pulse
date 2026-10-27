extends SceneTree
## Headless geometry/data regression only. No production world, physical flight,
## shader images, GPU/performance, human play or final artwork acceptance.
const Layout = preload("res://scripts/v3/world/twin_shore_layout.gd")
const Catalog = preload("res://scripts/v2/catalog.gd")
var checks := 0
var failures: Array[String] = []
var layout = Layout.new()
var triangle_count := 0
var actual_bottom_samples := 0
var imported_boundary_error_m := 0.0
var quantized_boundary_samples := 0
const IMPORT_BOUNDARY_LIMIT_M := 0.00025

func _init() -> void:
	var loaded: Dictionary = layout.load_layout()
	_check(loaded.ok, "authored profile and current actual GLB hashes load: " + str(loaded))
	if loaded.ok:
		_test_profile()
		_test_meshes()
		_test_fixed_objects_and_routes()
		_test_actual_bases()
		_test_validation()
	print("V3_SHORE_LAYOUT_CONTRACT " + JSON.stringify({"checks":checks, "failures":failures, "triangles":triangle_count,
		"actual_bottom_vertex_samples":actual_bottom_samples, "imported_boundary_error_m":imported_boundary_error_m,
		"quantized_boundary_samples":quantized_boundary_samples, "import_boundary_limit_m":IMPORT_BOUNDARY_LIMIT_M,
		"scope":"Headless data, imported mesh geometry and exact same-face resource checks only; no integrated physics, rendering, performance or final terrain artwork acceptance."}))
	quit(0 if failures.is_empty() else 1)

func _check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)
		push_error(label)

func _test_profile() -> void:
	var data: Dictionary = layout.definition()
	_check(data.profile.size() <= 32, "shared shader control points bounded to 32")
	var shader: Dictionary = layout.shader_data()
	_check(shader.count == data.profile.size() and shader.water_points is PackedVector4Array, "shader receives exact packed water-edge rows")
	var smallest := INF
	var mismatch := 0
	var mirrored := true
	for index in range(2001):
		var z := -50.0 + index * 0.05
		var edge: Dictionary = layout.bank_edges(z)
		smallest = minf(smallest, float(edge.right_water) - float(edge.left_water))
		mirrored = mirrored and is_equal_approx(-float(edge.left_top), float(edge.right_top))
		var rows: PackedVector4Array = shader.water_points
		for i in range(1, rows.size()):
			if z > rows[i].x: continue
			var mix_amount := (z - rows[i - 1].x) / (rows[i].x - rows[i - 1].x)
			var mixed: Vector4 = rows[i - 1].lerp(rows[i], mix_amount)
			if absf(mixed.y - float(edge.left_water)) > 0.00001 or absf(mixed.z - float(edge.right_water)) > 0.00001: mismatch += 1
			break
	_check(smallest >= 12, "whole linear main shore opening is at least 12m, excluding existing pillars")
	_check(mismatch == 0, "shader interpolation and CPU bank queries agree over 2001 positions")
	_check(not mirrored, "independent banks are not mirrored")
	var lift: Dictionary = layout.bank_edges(12)
	_check(float(lift.right_water) - float(lift.left_water) >= 16, "lift section retains at least 16m of main water opening")
	_check(layout.bank_edges(NAN).is_empty() and layout.bank_edges(50.1).is_empty(), "out-of-domain Z does not invent a clamped bank")
	_check(is_nan(layout.surface_height(53, 0)) and layout.classify_point(Vector3.INF).kind == "outside", "outside/nonfinite queries rejected")
	var edge: Dictionary = layout.bank_edges(12)
	var x := (float(edge.left_water) + float(edge.right_water)) * 0.5
	_check(layout.classify_point(Vector3(x, -2.7, 12)).kind == "water", "fluid exists between actual bed and water level")
	_check(layout.classify_point(Vector3(x, -3.2, 12)).kind == "solid", "bed is the solid lower boundary")
	_check(layout.classify_point(Vector3(x, -4, 12)).kind == "below_bed", "below-bed position is not water")
	_check(layout.classify_point(Vector3(x, 3, 12)).water and layout.classify_point(Vector3(x, 3, 12)).kind == "air", "water column flag is distinct from immersed point")
	_check(is_equal_approx(layout.surface_height(-45, 0), 0) and is_equal_approx(layout.surface_height(45, 0), 2.4), "unchanged west/east elevation contracts")
	_check(is_equal_approx(layout.bank_height(float(edge.left_water), 12), -2.2), "analytic height agrees with exact left slope toe")
	_check(layout.make_shape("water") == null and not shader.foundation_foam_implemented, "water has no glass collider; local foundation foam explicitly unimplemented")

func _test_meshes() -> void:
	var plane := PlaneMesh.new()
	var standard: Array = plane.surface_get_arrays(0)
	var pv: PackedVector3Array = standard[Mesh.ARRAY_VERTEX]
	var pi: PackedInt32Array = standard[Mesh.ARRAY_INDEX]
	var native_clockwise := (pv[pi[1]]-pv[pi[0]]).cross(pv[pi[2]]-pv[pi[0]]).dot(standard[Mesh.ARRAY_NORMAL][pi[0]]) < 0
	_check(native_clockwise, "actual Godot PlaneMesh confirms front-facing clockwise convention")
	var data: Dictionary = layout.definition()
	var water_area := 0.0
	var mask_matches := true
	var faces_finite := true
	var front_faces_match := true
	for part in layout.part_ids():
		var geometry: Dictionary = layout.geometry(part)
		var faces: PackedVector3Array = geometry.faces
		triangle_count += int(geometry.triangle_count)
		var mesh: ArrayMesh = layout.make_mesh(part)
		_check(mesh != null and mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX] == faces, str(part) + " ArrayMesh surface vertices use precisely the authored face list")
		if part != "water":
			var collision: ConcavePolygonShape3D = layout.make_shape(part)
			_check(collision != null and collision.get_faces() == faces, str(part) + " triangle collision matches visible geometry; no convex fill")
		for i in range(0, faces.size(), 3):
			var a := faces[i]
			var b := faces[i + 1]
			var c := faces[i + 2]
			front_faces_match = front_faces_match and (b-a).cross(c-a).dot(geometry.normals[i]) < 0
			faces_finite = faces_finite and a.is_finite() and b.is_finite() and c.is_finite()
			if part == "water":
				water_area += (b - a).cross(c - a).length() * 0.5
				var center := (a + b + c) / 3.0
				mask_matches = mask_matches and layout.is_water_xz(center.x, center.z)
				faces_finite = faces_finite and absf(center.y + 2.2) < 0.00001
		var copy: Dictionary = layout.geometry(part)
		copy.faces.clear()
		_check(not layout.geometry(part).faces.is_empty(), str(part) + " callers cannot mutate shared geometry")
	_check(faces_finite, "all mesh vertices finite and water level unchanged")
	_check(front_faces_match, "every terrain face uses Godot-native clockwise winding and an outward lighting normal")
	_check(mask_matches, "every rendered water triangle centroid agrees with same-footprint water query")
	_check(absf(water_area - float(data.water_area_m2)) < 0.005, "clipped water mesh area matches actual polygon difference")
	var foundation_top_area := 0.0
	for foundation in data.foundations:
		for tri in foundation.top_triangles_xz:
			var a := Vector2(tri[0][0], tri[0][1])
			var b := Vector2(tri[1][0], tri[1][1])
			var c := Vector2(tri[2][0], tri[2][1])
			foundation_top_area += absf((b - a).cross(c - a)) * 0.5
			var p := (a + b + c) / 3.0
			mask_matches = mask_matches and not layout.is_water_xz(p.x, p.y) and layout.surface_height(p.x, p.y) >= -0.00001
	_check(mask_matches and foundation_top_area > 0, "only real derived foundations exclude fluid and support their tops")
	_check(triangle_count < 16000, "bounded replaceable graybox geometry")

func _test_fixed_objects_and_routes() -> void:
	# Areas are retained footprints, not new world placements or final asset approval.
	var pads := [
		["west_contact", Rect2(-32,28,6,6),0.0], ["west_nursery",Rect2(-20.5,29,4,4),0.0],
		["east_nursery",Rect2(12,31,2,2),2.4], ["junction",Rect2(28,31,2,2),2.4],
		["relay",Rect2(-15,16,2,2),0.0], ["thermal",Rect2(-30.5,7,3,2),0.0],
		["crate",Rect2(-18,4,2,2),0.0], ["switch",Rect2(14,22,2,2),2.4],
		["west_cave",Rect2(-41.1,-16.0,12.1,8.3),0.0], ["east_cave",Rect2(28.9,-17.0,12.1,8.3),2.4],
		["receiver_terrace",Rect2(-20.1,23.4,9.1,6.2),0.0], ["temple",Rect2(-28.7,21.2,9.4,7.6),0.0]
	]
	for pad in pads:
		var r: Rect2 = pad[1]
		var supported := true
		for z in [r.position.y, r.get_center().y, r.end.y]:
			for x in [r.position.x, r.get_center().x, r.end.x]:
				supported = supported and absf(layout.surface_height(x,z) - float(pad[2])) < 0.00001
		_check(supported, str(pad[0]) + " retained support plane")
	_check(layout.clears_aabb(AABB(Vector3(-7,0.25,-16),Vector3(14,6.25,20))), "whole authored central bridge-under volume not filled by new base")
	_check(layout.clears_aabb(AABB(Vector3(-3,1.7,9),Vector3(6,6.1,6))), "entire moving-platform sweep clear of new base")
	# The new dedicated foundation intentionally contacts the actual shutter
	# bottom at Y2.9. The old anti-crush query padding extends into the base,
	# but only queries dynamic bodies, not terrain. Test the physical solid.
	_check(is_equal_approx(layout.surface_height(6,26),2.9), "dedicated gate base meets actual closed shutter bottom")
	_check(layout.clears_aabb(AABB(Vector3(5.5,2.901,22.5),Vector3(1.0,10.999,7.0))), "actual moving shutter interior remains clear above supporting base")
	_check(layout.clears_aabb(AABB(Vector3(-11,4.75,23.5),Vector3(22,0.5,3))), "growth-bridge solid volume left to its existing state machine")
	_check(layout.clears_aabb(AABB(Vector3(-20.8,5.19,26.34),Vector3(5.8,0.02,0.02))), "actual temple-to-receiver light segment clear of new terrain")
	for id in ["tr01","hx02"]:
		var build: Dictionary = Catalog.resolve_build(Catalog.default_build(id))
		_check(build.valid, id + " actual build dimensions resolve")
		var half := Vector3(build.derived.width_m, build.derived.height_m, build.derived.length_m) * 0.5
		for path in [[Vector3(0,3.25,-16),Vector3(0,3.25,4)], [Vector3(-24,5.2,21.2),Vector3(-24,5.2,28.8)], [Vector3(-35,1.4,-18),Vector3(-35,1.4,-6)], [Vector3(35,3.8,-19),Vector3(35,3.8,-7)]]:
			var start: Vector3 = path[0]
			var end: Vector3 = path[1]
			var swept := AABB(start.min(end) - half, start.max(end) - start.min(end) + half * 2.0)
			_check(layout.clears_aabb(swept), id + " entire upright envelope corridor remains clear of new terrain " + str(start))
		_check(layout.clears_aabb(AABB(Vector3(-18,2.5,32)-half,half*2)), id+" spawn retained")
	# Existing imported high structures remain an independent collision obligation.
	# All new geometry <=2.4, while p6 full model's conservative lowest point at
	# the lowest existing fall pose is 6 + .025 - 3.002 = 3.023.
	_check(layout.max_surface_in_rect(Rect2(-22,-47,65,38)) <= 2.4 and 6.0 + 0.025 - 3.002 > 2.4, "new base cannot intersect any six migration/three fall envelope; existing structures still need physics retest")
	var ecology = JSON.parse_string(FileAccess.get_file_as_string("res://data/v3/ecology/routes.json"))
	var clear_edges := true
	for region in ecology.regions:
		if region.id != "F1": continue
		var nodes: Dictionary = {}
		for node in region.nodes: nodes[node.id] = Vector3(node.position[0],node.position[1],node.position[2])
		for node in region.nodes:
			for next in node.neighbors:
				var a: Vector3 = nodes[node.id]
				var b: Vector3 = nodes[next]
				clear_edges = clear_edges and layout.clears_aabb(AABB(a.min(b)-Vector3.ONE, a.max(b)-a.min(b)+Vector3.ONE*2))
	_check(clear_edges, "all actual ecology adjacency corridors retain terrain clearance with 1m conservative margin")
	for filename in ["opening_actions.json","crown_action.json"]:
		var actions = JSON.parse_string(FileAccess.get_file_as_string("res://data/v3/actions/"+filename))
		for marker in actions.markers:
			if marker.region != "F1": continue
			var p := Vector3(marker.position[0],marker.position[1],marker.position[2])
			_check(layout.surface_height(p.x,p.z) < p.y, str(marker.id)+" actual objective point not buried")

func _test_actual_bases() -> void:
	var data: Dictionary = layout.definition()
	for support in data.supports:
		var scene = load(support.source.path).instantiate()
		var faces := _actual_faces(scene, Transform3D.IDENTITY)
		scene.free()
		var origin := Vector3(support.position[0],support.position[1],support.position[2])
		var supported := true
		var missing_samples: Array = []
		var area := 0.0
		var bottom_triangles: Array[PackedVector2Array] = []
		for i in range(0,faces.size(),3):
			if maxf(absf(faces[i].y),maxf(absf(faces[i+1].y),absf(faces[i+2].y))) > 0.00001: continue
			var tri := PackedVector2Array()
			for j in range(3):
				var p := faces[i+j]+origin
				tri.append(Vector2(p.x,p.z))
				actual_bottom_samples += 1
				# This imported scene has position compression enabled. Keep the raw
				# GLB footprint geometry exact; measure the importer boundary loss
				# explicitly instead of enlarging the collider or water exclusion.
				if layout.surface_height(p.x,p.z) < -0.002:
					var deviation := _bottom_boundary_distance(Vector2(p.x,p.z),support.bottom_footprint)
					imported_boundary_error_m = maxf(imported_boundary_error_m,deviation)
					quantized_boundary_samples += 1
					supported = supported and deviation <= IMPORT_BOUNDARY_LIMIT_M
					if deviation > IMPORT_BOUNDARY_LIMIT_M and missing_samples.size() < 3: missing_samples.append([p,layout.surface_height(p.x,p.z),deviation])
			if absf((tri[1]-tri[0]).cross(tri[2]-tri[0])) > 0.000000001:
				bottom_triangles.append(tri)
				var center := (tri[0]+tri[1]+tri[2])/3
				supported = supported and layout.surface_height(center.x,center.y) >= -0.002
				area += absf((tri[1]-tri[0]).cross(tri[2]-tri[0]))*.5
		_check(not bottom_triangles.is_empty() and area > 1, str(support.id)+" actual imported bottom faces are present")
		_check(supported, str(support.id)+" imported bottom remains supported within measured source-import boundary precision, at most 0.25mm")
		if not supported: print("SHORE_SUPPORT_DIAGNOSTIC ",support.id," ",missing_samples)
		var only_actual_bottom := true
		for foundation in data.foundations:
			if foundation.id != support.id: continue
			for triangle in foundation.top_triangles_xz:
				var center := (Vector2(triangle[0][0],triangle[0][1])+Vector2(triangle[1][0],triangle[1][1])+Vector2(triangle[2][0],triangle[2][1]))/3
				var found := false
				for tri in bottom_triangles:
					if Geometry2D.is_point_in_polygon(center,tri): found = true; break
				only_actual_bottom = only_actual_bottom and found
		_check(only_actual_bottom, str(support.id)+" no convex-hull or box foundation outside actual bottom triangles")
		# Inspect gaps inside the actual imported support's broad footprint.
		# No artificial hull/box may fill empty areas between separate roots.
		var all_points := PackedVector2Array()
		for tri in bottom_triangles: all_points.append_array(tri)
		var hull := Geometry2D.convex_hull(all_points)
		var gap_count := 0
		var gaps_open := true
		for gx in range(-12,13):
			for gz in range(-12,13):
				var p := Vector2(origin.x+gx*.5,origin.z+gz*.5)
				if layout.bank_height(p.x,p.y) >= -0.01 or not Geometry2D.is_point_in_polygon(p,hull): continue
				var in_bottom := false
				for tri in bottom_triangles:
					if Geometry2D.is_point_in_polygon(p,tri): in_bottom = true; break
				if in_bottom or _bottom_boundary_distance(p,support.bottom_footprint)<0.001: continue
				gap_count += 1
				# Nearby placed pillars may legitimately cover part of this hull.
				# Their own source-face containment is checked independently above.
				gaps_open = gaps_open and layout.foundation_at(p.x,p.y) != str(support.id)
		if float(support.exposed_area_m2)>0:
			_check(gap_count>0 and gaps_open,str(support.id)+" own foundation leaves actual inter-root gaps unfilled; neighboring real supports remain independent")
	_check(imported_boundary_error_m <= IMPORT_BOUNDARY_LIMIT_M,"source-import boundary error independently bounded; no geometry/query inflation")

func _bottom_boundary_distance(point: Vector2, polygons: Array) -> float:
	var nearest := INF
	for polygon in polygons:
		for ring in [polygon.outer] + polygon.holes:
			for i in ring.size():
				var a := Vector2(ring[i][0],ring[i][1])
				var b := Vector2(ring[(i+1)%ring.size()][0],ring[(i+1)%ring.size()][1])
				nearest = minf(nearest,point.distance_to(Geometry2D.get_closest_point_to_segment(point,a,b)))
	return nearest

func _actual_faces(node: Node, parent: Transform3D) -> PackedVector3Array:
	var at := parent
	if node is Node3D: at = parent * node.transform
	var result := PackedVector3Array()
	if node is MeshInstance3D and node.mesh != null and not ("Foliage" in str(node.name) or "Moss" in str(node.name) or "BarkPlates" in str(node.name)):
		# get_faces() passes through TriangleMesh welding; inspect the actual
		# imported render vertices/indices instead of that separately quantized copy.
		for surface in node.mesh.get_surface_count():
			var arrays: Array = node.mesh.surface_get_arrays(surface)
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var indices = arrays[Mesh.ARRAY_INDEX]
			if indices != null and not indices.is_empty():
				for index in indices: result.append(at * vertices[index])
			else:
				for v in vertices: result.append(at * v)
	for child in node.get_children(): result.append_array(_actual_faces(child, at))
	return result

func _test_validation() -> void:
	var original: Dictionary = layout.definition()
	var mutation: Dictionary = layout.definition()
	mutation.profile[1][0] = mutation.profile[0][0]
	_check(not layout.configure(mutation,false).ok and layout.definition() == original, "invalid row order rejected atomically")
	mutation = original.duplicate(true)
	mutation.profile[0][2] = mutation.profile[0][1]+5
	_check(layout.configure(mutation,false).code == "channel_too_narrow", "narrow main channel rejected")
	mutation = original.duplicate(true)
	mutation.profile[0][1] -= 1
	_check(str(layout.configure(mutation,false).code).begins_with("stale_derived_geometry"), "profile edit requires same-footprint water/foundation regeneration")
	mutation = original.duplicate(true)
	mutation.generated_from.profile_sha256 = "0".repeat(64)
	_check(layout.configure(mutation,false).code == "stale_derived_geometry:profile_sha256", "canonical profile hash checked at load")
	mutation = original.duplicate(true)
	mutation.supports[0].source.sha256 = "0".repeat(64)
	_check(layout.configure(mutation,true).code == "stale_source_footprint", "new H10 bytes cannot silently reuse old foundation")
	mutation = original.duplicate(true)
	mutation.supports[0].source.imported_geometry.sha256 = "0".repeat(64)
	_check(layout.configure(mutation,true).code == "stale_imported_geometry", "changed imported positions/transforms cannot reuse source footprint")
	mutation = original.duplicate(true)
	mutation.supports[0].source.imported_geometry.erase("algorithm")
	_check(layout.configure(mutation,true).code == "missing_imported_geometry_signature", "export-safe signature is mandatory")
	_check(layout.definition() == original and layout.make_mesh("absent") == null, "failed inputs leave prior usable layout intact")
