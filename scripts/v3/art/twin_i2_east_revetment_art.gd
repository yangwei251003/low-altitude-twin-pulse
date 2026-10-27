class_name TwinI2EastRevetmentArt
extends RefCounted
## Detached, visual-only east-bank presentation. It clips the CURRENT west-bank remainder;
## the original Terrain is used only to validate its provenance and collision.
const Terrain = preload("res://scripts/v3/world/twin_i2_waterfront_terrain.gd")
const Split = preload("res://scripts/v3/art/twin_i2_revetment_partition.gd")
const WestArt = preload("res://scripts/v3/art/twin_i2_revetment_art.gd")
const PARTS := ["bank", "dry_surface"]
const CUT_MIN := Vector3(16.9, -2.8, 2.3)
const CUT_MAX := Vector3(17.25, 0, 15.6)
const AREA_EPS := 0.0002
const PLACEMENTS := [
	["EastBankA", "long", Vector3(16.9, 0, 4.3)],
	["EastBankB", "long", Vector3(16.9, 0, 8.3)],
	["EastBankC", "long", Vector3(16.9, 0, 12.3)],
	["EastBankD", "short", Vector3(16.9, 0, 14.95)]
]
const TRIANGLES := WestArt.TRIANGLES

static func install(terrain: Terrain, installed: Dictionary) -> Dictionary:
	var host: Dictionary = _validate_host(terrain, installed)
	if not host.ok: return host
	# This remains a narrow known-input installer. The expected west partition is
	# ONLY a validation oracle; clipping below reads actual visible ArrayMeshes.
	var expected_west := Split.new()
	var expected: Dictionary = expected_west.configure(terrain)
	if not expected.ok: return _fail("west_source:" + str(expected.code))
	var prepared_meshes: Dictionary = {}
	var kept: Dictionary = {}
	var removed: Dictionary = {}
	var reports: Dictionary = {}
	for part: String in PARTS:
		var visual: MeshInstance3D = installed.meshes[part]
		var read: Dictionary = _read_mesh(visual.mesh)
		if not read.ok: return _fail("visible_" + part + ":" + str(read.code))
		var expected_read: Dictionary = _read_mesh(expected.meshes[part])
		if not expected_read.ok or _attributes_sha(read.geometry) != _attributes_sha(expected_read.geometry):
			return _fail("current_west_remainder_required:" + part)
		var cut: Dictionary = _cut(read.geometry, part)
		if not cut.ok: return cut
		var mesh: ArrayMesh = _make_mesh(cut.kept, part)
		mesh.surface_set_material(0, visual.mesh.surface_get_material(0))
		prepared_meshes[part] = mesh
		kept[part] = cut.kept
		removed[part] = cut.removed
		reports[part] = cut.report
	var wrapper := Node3D.new()
	wrapper.name = "AuthoredEastBankCandidate"
	wrapper.set_meta("stage", "two_straight_banks_only_candidate")
	var models: Dictionary = {}
	for kind: String in WestArt.MODELS:
		var path: String = WestArt.MODELS[kind]
		var packed := load(path) as PackedScene
		if packed == null or packed.resource_path != path: return _reject(wrapper, "model_path:" + kind)
		models[kind] = packed
	var records: Array = []
	var material_ids: Dictionary = {}
	var triangle_count := 0
	for spec: Array in PLACEMENTS:
		var model := (models[spec[1]] as PackedScene).instantiate() as Node3D
		if model == null: return _reject(wrapper, "model_root")
		wrapper.add_child(model)
		var checked: Dictionary = _validate_model(model, str(spec[1]), wrapper)
		if not checked.ok: return _reject(wrapper, str(checked.code))
		var mesh: MeshInstance3D = checked.mesh
		model.name = str(spec[0])
		model.transform = Transform3D(Basis(Vector3.UP, -PI * 0.5), spec[2])
		var world_bounds: AABB = model.transform * mesh.get_aabb()
		var width: float = checked.width
		var desired: AABB = Transform3D(Basis(Vector3.UP,-PI*.5),spec[2]) * WestArt.visual_bounds(str(spec[1]))
		if not world_bounds.position.is_equal_approx(desired.position) or not world_bounds.size.is_equal_approx(desired.size):
			return _reject(wrapper, "rotated_envelope:" + str(spec[0]))
		mesh.set_meta("terrain_visibility_single_sided", true)
		material_ids[mesh.get_active_material(0).get_instance_id()] = true
		triangle_count += int(checked.triangles)
		records.append({"id":spec[0], "path":WestArt.MODELS[spec[1]], "model":model,
			"mesh":mesh, "bounds":world_bounds, "width":width, "triangles":checked.triangles})
	# No await, scene callbacks or external mutations intervene in this detached
	# transaction. All rejection paths above have left existing nodes/resources alone.
	for part: String in PARTS: installed.meshes[part].mesh = prepared_meshes[part]
	var parent: Node3D = host.parent
	parent.add_child(wrapper)
	return {"ok":true, "code":"east_straight_bank_installed", "wrapper":wrapper, "parts":records,
		"geometry":kept.duplicate(true), "removed_geometry":removed.duplicate(true),
		"report":{"parts":reports.duplicate(true), "scope":"two_straight_banks_only_not_complete_quay",
			"collision_changed":false, "source":"current_visible_west_remainder",
			"collision_sha256":Split._sha(host.collider.shape.get_faces().to_byte_array())},
		"triangles":triangle_count, "material_count":material_ids.size(),
		"ground":host.ground, "shape":host.collider.shape, "paths":WestArt.MODELS.values()}

static func _validate_host(terrain: Terrain, installed: Dictionary) -> Dictionary:
	if terrain == null or not bool(terrain.summary().get("ok", false)): return _fail("configured_terrain_required")
	if installed.get("ok") != true or not installed.get("wrapper") is Node3D or not installed.get("ground") is StaticBody3D or not installed.get("shape_node") is CollisionShape3D or not installed.get("meshes") is Dictionary:
		return _fail("installed_terrain_required")
	var parent: Node3D = installed.wrapper
	var ground: StaticBody3D = installed.ground
	var collider: CollisionShape3D = installed.shape_node
	if not is_instance_valid(parent) or not is_instance_valid(ground) or not is_instance_valid(collider): return _fail("freed_host")
	if parent.is_inside_tree() or ground.is_inside_tree(): return _fail("detached_install_required")
	if parent.has_node("AuthoredEastBankCandidate"): return _fail("already_installed")
	var ancestor: Node = parent
	while ancestor != null:
		if ancestor is Node3D and not ancestor.transform.is_equal_approx(Transform3D.IDENTITY): return _fail("host_transform")
		ancestor = ancestor.get_parent()
	if ground.get_parent() != parent.get_parent() or str(ground.name) != "Ground" or ground.collision_layer != 1 or ground.collision_mask != 0 or ground.get_node_or_null("ExactBoxCollision") != collider:
		return _fail("ground_identity")
	if not ground.transform.is_equal_approx(Transform3D(Basis.IDENTITY, Vector3(0,-.2,0))) or not collider.transform.is_equal_approx(Transform3D.IDENTITY) or not collider.shape is ConcavePolygonShape3D:
		return _fail("ground_pose_or_shape")
	var physical_shape := collider.shape as ConcavePolygonShape3D
	if physical_shape.get_faces().to_byte_array() != terrain.collision_faces(ground.position).to_byte_array(): return _fail("ground_collision_changed")
	var west := parent.get_node_or_null("AuthoredWestBank") as Node3D
	if west == null or not west.transform.is_equal_approx(Transform3D.IDENTITY) or west.get_child_count() != 4: return _fail("installed_west_required")
	for spec: Array in WestArt.PLACEMENTS:
		var model := west.get_node_or_null(NodePath(str(spec[0]))) as Node3D
		if model == null or model.scene_file_path != str(WestArt.MODELS[spec[1]]) or not model.transform.is_equal_approx(Transform3D(Basis(Vector3.UP, PI*.5), spec[2])):
			return _fail("installed_west_pose_or_path")
	for part: String in PARTS:
		if not installed.meshes.get(part) is MeshInstance3D: return _fail("visible_part:" + part)
		var visual: MeshInstance3D = installed.meshes[part]
		if not is_instance_valid(visual) or visual.get_parent() != parent or not visual.transform.is_equal_approx(Transform3D.IDENTITY) or not visual.visible: return _fail("visible_part_pose:" + part)
	return {"ok":true, "parent":parent, "ground":ground, "collider":collider}

static func _validate_model(model: Node3D, kind: String, wrapper: Node3D) -> Dictionary:
	if model.scene_file_path != str(WestArt.MODELS[kind]): return _fail("instance_source_path")
	for type_name: String in ["CollisionObject3D", "Camera3D", "Light3D", "AnimationPlayer"]:
		if not model.find_children("*", type_name, true, false).is_empty(): return _fail("unexpected_import_node:" + type_name)
	var meshes := model.find_children("*", "MeshInstance3D", true, false)
	if meshes.size() != 1: return _fail("one_import_mesh_required")
	var mesh: MeshInstance3D = meshes[0]
	var ancestor: Node = mesh
	while ancestor != wrapper:
		if ancestor is Node3D and not ancestor.transform.is_equal_approx(Transform3D.IDENTITY): return _fail("authored_identity")
		ancestor = ancestor.get_parent()
	if str(mesh.name) != "RevetmentSurface" or mesh.mesh == null or mesh.mesh.get_surface_count() != 1 or mesh.mesh.surface_get_primitive_type(0) != Mesh.PRIMITIVE_TRIANGLES: return _fail("import_surface_contract")
	var width: float = 4.0 if kind == "long" else 1.3
	var expected := WestArt.visual_bounds(kind)
	var bounds: AABB = mesh.mesh.get_aabb()
	if not bounds.position.is_equal_approx(expected.position) or not bounds.size.is_equal_approx(expected.size): return _fail("import_bounds")
	var faces: PackedVector3Array = mesh.mesh.get_faces()
	if faces.size() != int(TRIANGLES[kind]) * 3: return _fail("import_triangles")
	for point: Vector3 in faces:
		if not point.is_finite() or not expected.grow(.00001).has_point(point): return _fail("import_finite_envelope")
	var material := mesh.get_active_material(0) as BaseMaterial3D
	if material == null or material.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED or material.albedo_texture == null or material.roughness_texture == null or material.metallic_texture == null or material.normal_texture == null: return _fail("import_opaque_pbr")
	return {"ok":true, "mesh":mesh, "width":width, "triangles":faces.size()/3}

static func _read_mesh(mesh: Mesh) -> Dictionary:
	if not mesh is ArrayMesh: return _fail("array_mesh_required")
	var array_mesh := mesh as ArrayMesh
	if array_mesh.get_surface_count() != 1 or array_mesh.get_blend_shape_count() != 0 or array_mesh.surface_get_primitive_type(0) != Mesh.PRIMITIVE_TRIANGLES: return _fail("array_mesh_required")
	var arrays: Array = array_mesh.surface_get_arrays(0)
	for index in Mesh.ARRAY_MAX:
		if index in [Mesh.ARRAY_VERTEX, Mesh.ARRAY_NORMAL, Mesh.ARRAY_TANGENT, Mesh.ARRAY_TEX_UV]: continue
		if arrays[index] != null and arrays[index].size() != 0: return _fail("unsupported_attribute")
	var geometry: Dictionary = {"faces":arrays[Mesh.ARRAY_VERTEX], "normals":arrays[Mesh.ARRAY_NORMAL], "uv":arrays[Mesh.ARRAY_TEX_UV]}
	var checked: Dictionary = Split._validate(geometry)
	if not checked.ok: return checked
	# Godot supplies a real tangent array even when the source mesh submitted only
	# position/normal/UV. This known planar source has one frame per triangle.
	# Keep those frames explicitly; never discard a nonempty generated attribute.
	if not arrays[Mesh.ARRAY_TANGENT] is PackedFloat32Array: return _fail("tangents_required")
	var tangents: PackedFloat32Array = arrays[Mesh.ARRAY_TANGENT]
	if tangents.size() != geometry.faces.size() * 4: return _fail("tangent_count")
	for first in range(0, tangents.size(), 12):
		for component in 4:
			var value: float = tangents[first + component]
			if not is_finite(value) or tangents[first+4+component] != value or tangents[first+8+component] != value:
				return _fail("triangle_tangent_frame")
		if absf(absf(tangents[first+3])-1.0) > .00001: return _fail("tangent_handedness")
		if absf(Vector3(tangents[first],tangents[first+1],tangents[first+2]).length_squared()-1.0) > .00002:
			return _fail("tangent_unit")
	geometry.tangents = tangents.duplicate()
	return {"ok":true, "geometry":geometry}

static func _cut(source: Dictionary, part: String) -> Dictionary:
	var kept: Dictionary = Split._empty_geometry()
	var removed: Dictionary = Split._empty_geometry()
	var faces: PackedVector3Array = source.faces
	var planes: Array = [[1,-2.8,1.0],[1,0.0,-1.0],[2,2.3,1.0],[2,15.6,-1.0]] if part == "bank" else [[0,16.9,1.0],[0,17.25,-1.0],[2,2.3,1.0],[2,15.6,-1.0]]
	for first in range(0, faces.size(), 3):
		var polygon: Array[Dictionary] = []
		var eligible: bool = true
		for offset in 3:
			var at: int = first + offset
			polygon.append({"p":faces[at], "n":source.normals[at], "uv":source.uv[at]})
			if part == "bank" and (faces[at].x != CUT_MIN.x or source.normals[at].dot(Vector3.LEFT) < .99999): eligible = false
		var intersection: Array[Dictionary] = polygon
		if eligible:
			for plane: Array in planes: intersection = Split._split(intersection, int(plane[0]), float(plane[1]), float(plane[2])).inside
		if not eligible or Split._polygon_area(intersection) <= 1e-12:
			Split._emit(kept, polygon, first/3)
			continue
		var middle: Array[Dictionary] = polygon
		for plane: Array in planes:
			var pieces: Dictionary = Split._split(middle, int(plane[0]), float(plane[1]), float(plane[2]))
			Split._emit(kept, pieces.outside, first/3)
			middle = pieces.inside
		Split._emit(removed, middle, first/3)
	if not Split._validate(kept).ok or not Split._validate(removed).ok: return _fail("cut_invalid:" + part)
	# Clipping adds corners within the same planar source triangle. Its checked
	# constant tangent frame belongs to every retained/removed corner unchanged.
	for output: Dictionary in [kept, removed]:
		var tangents := PackedFloat32Array()
		for source_triangle: int in output.source_triangles:
			for corner in 3:
				for component in 4: tangents.append(source.tangents[source_triangle*12+component])
		output.tangents = tangents
	var area_before: float = Split._area(source)
	var area_after: float = Split._area(kept)
	var area_removed: float = Split._area(removed)
	var expected_area: float = 13.3 * (2.8 if part == "bank" else .35)
	if absf(area_removed-expected_area) > AREA_EPS or absf(area_before-area_after-area_removed) > AREA_EPS: return _fail("cut_area:" + part)
	return {"ok":true, "kept":kept, "removed":removed, "report":{"source_attributes_sha256":_attributes_sha(source), "source_area_m2":area_before,
		"retained_area_m2":area_after, "removed_area_m2":area_removed, "source_triangles":faces.size()/3,
		"retained_triangles":kept.faces.size()/3, "removed_triangles":removed.faces.size()/3}}

static func _make_mesh(geometry: Dictionary, part: String) -> ArrayMesh:
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = geometry.faces.duplicate()
	arrays[Mesh.ARRAY_NORMAL] = geometry.normals.duplicate()
	arrays[Mesh.ARRAY_TANGENT] = geometry.tangents.duplicate()
	arrays[Mesh.ARRAY_TEX_UV] = geometry.uv.duplicate()
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh.resource_name = "I2 east candidate over west remainder / " + part
	return mesh

static func _attributes_sha(geometry: Dictionary) -> String:
	var bytes: PackedByteArray = geometry.faces.to_byte_array()
	bytes.append_array(geometry.normals.to_byte_array())
	bytes.append_array(geometry.uv.to_byte_array())
	bytes.append_array(geometry.tangents.to_byte_array())
	return Split._sha(bytes)

static func _fail(code: String) -> Dictionary:
	return {"ok":false, "code":code}

static func _reject(wrapper: Node, code: String) -> Dictionary:
	wrapper.free()
	return _fail(code)
