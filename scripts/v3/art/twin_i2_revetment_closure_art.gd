class_name TwinI2RevetmentClosureArt
extends RefCounted
## Visual-only closure on the current two-bank/floor remainder. Detached hosts
## are supported; original Ground and all facility collision are never edited.
const Reader = preload("res://scripts/v3/art/twin_i2_east_revetment_art.gd")
const Split = preload("res://scripts/v3/art/twin_i2_revetment_partition.gd")
const Terrain = preload("res://scripts/v3/world/twin_i2_waterfront_terrain.gd")
const PLAN := "res://data/v3/terrain/i2_revetment_closure_layout.json"
const MODEL := "res://assets/v3/environment/i2_revetment_closure/revetment_closure.glb"
const DELIVERY := "res://data/v3/terrain/i2_revetment_closure_delivery.json"
const ROOT_NAME := "AuthoredRevetmentClosure"
# Original GLB hash is build provenance, not an assertion about PCK bytes.
const SOURCE_GLB_SHA256 := "9e3bce1d8871cb3c6778868cc9209d8042a7ecb8eac852d2f99b58e4ca02c67c"
const PLAN_SHA256 := "90246f5528d31d73633a4b22fc69ff0cd61330489ede112e33d908d8097fff7b"
const DELIVERY_SHA256 := "06caba2e11f88856e054c5b05e44559c47e9d7603db07e6ff15655820846c0e2"
const AREA_EPS := .0005 # m²; accumulated Float32 clipping, not a shifted cut plane.

static func prepare_geometry(terrain: Terrain, installed: Dictionary) -> Dictionary:
	# JSON is explicitly included as raw data by the existing export preset.
	if FileAccess.get_sha256(PLAN) != PLAN_SHA256: return _fail("layout_contract_fingerprint")
	if terrain == null or not terrain.summary().get("ok",false): return _fail("configured_terrain_required")
	if installed.get("ok") != true or not installed.get("wrapper") is Node3D or not installed.get("ground") is StaticBody3D or not installed.get("shape_node") is CollisionShape3D:
		return _fail("installed_terrain_required")
	var parent: Node3D = installed.wrapper
	if not is_instance_valid(parent): return _fail("freed_host")
	if parent.has_node(ROOT_NAME) or parent.has_node("RevetmentClosureCandidate"): return _fail("already_installed")
	var shape_node: CollisionShape3D = installed.shape_node
	var ground: StaticBody3D = installed.ground
	if not shape_node.shape is ConcavePolygonShape3D or ground.collision_layer != 1 or ground.collision_mask != 0 or not ground.position.is_equal_approx(Vector3(0,-.2,0)):
		return _fail("ground_contract")
	var shape := shape_node.shape as ConcavePolygonShape3D
	if shape.get_faces().to_byte_array() != terrain.collision_faces(ground.position).to_byte_array(): return _fail("ground_collision_changed")
	if not parent.has_node("AuthoredWestBank") or not parent.has_node("AuthoredEastBankCandidate") or not parent.has_node("EastMaintenanceExtension"):
		return _fail("current_two_banks_and_extension_required")
	var ancestor: Node = parent
	while ancestor != null:
		if ancestor is Node3D and not ancestor.transform.is_equal_approx(Transform3D.IDENTITY): return _fail("identity_host_required")
		ancestor = ancestor.get_parent()
	var raw: Variant = JSON.parse_string(FileAccess.get_file_as_string(PLAN))
	if not raw is Dictionary: return _fail("layout_plan_missing")
	var plan: Dictionary = raw
	if plan.get("version") != 1 or plan.get("pieces",[]).size() != 12 or plan.get("water_segments",[]).size() != 5 or plan.get("height") != 2.8: return _fail("plan_contract")
	var prepared: Dictionary = {}
	var report: Dictionary = {}
	for part: String in ["bank","dry_surface"]:
		if not installed.get("meshes",{}).get(part) is MeshInstance3D: return _fail("visible_part:"+part)
		var visual: MeshInstance3D = installed.meshes[part]
		if visual.get_parent() != parent or not visual.visible or not visual.transform.is_equal_approx(Transform3D.IDENTITY): return _fail("visible_pose:"+part)
		var read: Dictionary = Reader._read_mesh(visual.mesh)
		if not read.ok: return _fail("visible_"+part+":"+str(read.code))
		var partition: Dictionary = _partition(read.geometry,part,plan)
		if not partition.ok: return partition
		prepared[part] = partition
		report[part] = partition.report
	return {"ok":true,"code":"closure_geometry_prepared","plan":plan,"parts":prepared,"report":report,
		"parent":parent,"ground":ground,"shape":shape,"collision_bytes":shape.get_faces().to_byte_array()}

static func install(terrain: Terrain, installed: Dictionary) -> Dictionary:
	var prepared: Dictionary = prepare_geometry(terrain,installed)
	if not prepared.ok: return prepared
	if FileAccess.get_sha256(DELIVERY) != DELIVERY_SHA256: return _fail("delivery_contract_fingerprint")
	var raw: Variant = JSON.parse_string(FileAccess.get_file_as_string(DELIVERY))
	if not raw is Dictionary: return _fail("delivery_not_ready")
	var contract: Dictionary = raw
	if contract.get("status") != "EXPORTED_VERIFIED" or contract.get("plan_sha256") != PLAN_SHA256 or contract.get("glb_sha256") != SOURCE_GLB_SHA256:
		return _fail("delivery_fingerprint")
	# ResourceLoader follows the exported GLB -> PackedScene remap. Original
	# GLB files need not exist inside the PCK; validate the actual loaded model.
	var packed := load(MODEL) as PackedScene
	if packed == null: return _fail("imported_model_missing")
	var instance: Node = packed.instantiate()
	if not instance is Node3D:
		if is_instance_valid(instance): instance.free()
		return _fail("imported_root")
	var model := instance as Node3D
	var checked: Dictionary = _validate_model(model,contract)
	if not checked.ok:
		model.free()
		return checked
	var dry: MeshInstance3D = installed.meshes.dry_surface
	var dry_mesh: ArrayMesh = Reader._make_mesh(prepared.parts.dry_surface.kept,"remaining original banks closure")
	dry_mesh.surface_set_material(0,dry.mesh.surface_get_material(0))
	var wrapper := Node3D.new()
	wrapper.name = ROOT_NAME
	wrapper.set_meta("stage","production_closure_not_final_area_art")
	wrapper.add_child(model)
	# All resource, geometry and host checks finish before the single commit.
	dry.mesh = dry_mesh
	installed.meshes.bank.visible = false # Its actual remaining 94.2815m² is wholly replaced.
	prepared.parent.add_child(wrapper)
	return {"ok":true,"code":"closure_installed","wrapper":wrapper,"model":model,"meshes":checked.meshes,
		"triangles":checked.triangles,"surface_count":checked.surface_count,"material_count":checked.material_count,"report":prepared.report,
		"model_path":MODEL,"paths":[MODEL],"plan_path":PLAN,"delivery_path":DELIVERY,
		"source_glb_sha256":SOURCE_GLB_SHA256,"source_glb_bytes_checked_at_runtime":false,
		"runtime_validation":"imported_geometry_material_contract",
		"ground":prepared.ground,"shape":prepared.shape,"collision_unchanged":prepared.shape.get_faces().to_byte_array()==prepared.collision_bytes,
		"scope":"original_A_channel_boundary_only; no south cross-water wall"}

static func _split_plane(poly: Array[Dictionary], normal: Vector2, distance: float) -> Dictionary:
	var inside: Array[Dictionary] = []
	var outside: Array[Dictionary] = []
	for i in poly.size():
		var a: Dictionary = poly[i]
		var b: Dictionary = poly[(i+1)%poly.size()]
		var pa: Vector3 = a.p
		var pb: Vector3 = b.p
		var da: float = normal.dot(Vector2(pa.x,pa.z))-distance
		var db: float = normal.dot(Vector2(pb.x,pb.z))-distance
		if da >= 0: inside.append(a)
		else: outside.append(a)
		if (da >= 0) != (db >= 0):
			var t: float = da/(da-db)
			var point: Vector3 = pa.lerp(pb,t)
			var correction: float = (distance-normal.dot(Vector2(point.x,point.z)))/normal.length_squared()
			point.x += normal.x*correction
			point.z += normal.y*correction
			var normal_a: Vector3 = a.n
			var normal_b: Vector3 = b.n
			var uv_a: Vector2 = a.uv
			var uv_b: Vector2 = b.uv
			var vertex: Dictionary = {"p":point,"n":normal_a if normal_a==normal_b else normal_a.lerp(normal_b,t).normalized(),"uv":uv_a.lerp(uv_b,t)}
			inside.append(vertex)
			outside.append(vertex)
	return {"inside":Split._clean(inside),"outside":Split._clean(outside)}

static func _footprint(poly: Array[Dictionary], points: Array) -> Dictionary:
	var center := Vector2.ZERO
	for p: Array in points: center += Vector2(float(p[0]),float(p[1]))/points.size()
	var middle: Array[Dictionary] = poly
	var outside: Array = []
	for i in points.size():
		var a := Vector2(float(points[i][0]),float(points[i][1]))
		var b := Vector2(float(points[(i+1)%points.size()][0]),float(points[(i+1)%points.size()][1]))
		var delta: Vector2 = b-a
		var normal := Vector2(-delta.y,delta.x).normalized()
		var d: float = normal.dot(a)
		if normal.dot(center)<d:
			normal = -normal
			d = -d
		var split: Dictionary = _split_plane(middle,normal,d)
		if Split._polygon_area(split.outside)>1e-12: outside.append(split.outside)
		middle = split.inside
	return {"inside":middle,"outside":outside}

static func _bank_match(poly: Array[Dictionary], segments: Array) -> bool:
	for segment: Dictionary in segments:
		var a := Vector2(float(segment.a[0]),float(segment.a[1]))
		var b := Vector2(float(segment.b[0]),float(segment.b[1]))
		var tangent: Vector2 = (b-a).normalized()
		var water := Vector3(float(segment.water[0]),0,float(segment.water[1]))
		var matched := true
		for corner: Dictionary in poly:
			var point: Vector3 = corner.p
			var delta := Vector2(point.x,point.z)-a
			if absf(delta.cross(tangent))>.000003 or delta.dot(tangent)<-.000003 or delta.dot(tangent)>a.distance_to(b)+.000003 or point.y < -2.800003 or point.y > .000003 or corner.n.dot(water)<.99999:
				matched = false
		if matched: return true
	return false

static func _partition(source: Dictionary, part: String, plan: Dictionary) -> Dictionary:
	var kept: Dictionary = Split._empty_geometry()
	var removed: Dictionary = Split._empty_geometry()
	for first in range(0,source.faces.size(),3):
		var polygon: Array[Dictionary] = []
		for j in 3: polygon.append({"p":source.faces[first+j],"n":source.normals[first+j],"uv":source.uv[first+j]})
		if part=="bank":
			Split._emit(removed if _bank_match(polygon,plan.water_segments) else kept,polygon,first/3)
			continue
		var remaining: Array = [polygon]
		for segment: Dictionary in plan.segments:
			var next: Array = []
			for piece: Array[Dictionary] in remaining:
				var cut: Dictionary = _footprint(piece,segment.footprint)
				# Zero-area contact must not unnecessarily retriangulate old regions.
				if Split._polygon_area(cut.inside)<=1e-12: next.append(piece)
				else:
					Split._emit(removed,cut.inside,first/3)
					next.append_array(cut.outside)
			remaining = next
		for piece: Array[Dictionary] in remaining: Split._emit(kept,piece,first/3)
	for output: Dictionary in [kept,removed]:
		var tangents := PackedFloat32Array()
		for source_triangle: int in output.source_triangles:
			for corner in 3:
				for component in 4: tangents.append(source.tangents[source_triangle*12+component])
		output.tangents = tangents
		if not output.faces.is_empty() and not Split._validate(output).ok: return _fail("partition_attributes:"+part)
	var before: float = Split._area(source)
	var retained: float = Split._area(kept)
	var cut_area: float = Split._area(removed)
	var expected: float = float(plan.removed_bank_area_m2 if part=="bank" else plan.top_footprint_area_m2)
	if absf(cut_area-expected)>AREA_EPS or absf(before-retained-cut_area)>AREA_EPS or (part=="bank" and not kept.faces.is_empty()):
		return {"ok":false,"code":"partition_area:"+part,"actual":{"source":before,"retained":retained,"removed":cut_area,"expected":expected}}
	return {"ok":true,"kept":kept,"removed":removed,"report":{"source_area_m2":before,"retained_area_m2":retained,"removed_area_m2":cut_area,
		"source_attributes_sha256":Reader._attributes_sha(source),"removed_triangles":removed.faces.size()/3}}

static func _validate_model(model: Node3D, contract: Dictionary) -> Dictionary:
	for type_name: String in ["CollisionObject3D","Camera3D","Light3D","AnimationPlayer"]:
		if not model.find_children("*",type_name,true,false).is_empty(): return _fail("unexpected_import:"+type_name)
	var meshes: Array = model.find_children("*","MeshInstance3D",true,false)
	if meshes.size()!=12 or not contract.get("pieces") is Dictionary: return _fail("twelve_surface_contract")
	var triangles := 0
	var surface_count := 0
	var materials: Dictionary = {}
	var seen: Dictionary = {}
	for view: MeshInstance3D in meshes:
		var key: String = str(view.name)
		if seen.has(key) or not contract.pieces.has(key) or view.mesh==null: return _fail("import_piece:"+key)
		seen[key] = true
		var node: Node = view
		while node!=null:
			if node is Node3D and not node.transform.is_equal_approx(Transform3D.IDENTITY): return _fail("world_authored_identity")
			node = node.get_parent()
		var expected: Dictionary = contract.pieces[key]
		if view.mesh.get_surface_count()!=int(expected.surfaces): return _fail("actual_surfaces:"+key)
		var count := 0
		for surface in view.mesh.get_surface_count():
			if view.mesh.surface_get_primitive_type(surface)!=Mesh.PRIMITIVE_TRIANGLES: return _fail("triangle_surface")
			surface_count += 1
			var arrays: Array = view.mesh.surface_get_arrays(surface)
			var indices: Variant = arrays[Mesh.ARRAY_INDEX]
			count += int(arrays[Mesh.ARRAY_VERTEX].size()/3) if indices==null or indices.is_empty() else int(indices.size()/3)
			var material := view.get_active_material(surface) as BaseMaterial3D
			if material==null or material.transparency!=BaseMaterial3D.TRANSPARENCY_DISABLED or material.albedo_texture==null or material.normal_texture==null or material.roughness_texture==null or material.metallic_texture==null:
				return _fail("opaque_pbr_required:"+key)
			materials[material.get_instance_id()] = true
		if count!=int(expected.triangles): return _fail("actual_triangles:"+key)
		var bounds: AABB = view.mesh.get_aabb()
		var lo: Array = expected.bounds.min
		var hi: Array = expected.bounds.max
		if not bounds.position.is_equal_approx(Vector3(lo[0],lo[1],lo[2])) or not bounds.end.is_equal_approx(Vector3(hi[0],hi[1],hi[2])): return _fail("actual_bounds:"+key)
		triangles += count
	if triangles!=32122 or surface_count!=14 or materials.size()!=2: return _fail("import_total_contract")
	return {"ok":true,"meshes":meshes,"triangles":triangles,"surface_count":surface_count,"material_count":materials.size()}

static func _fail(code: String) -> Dictionary:
	return {"ok":false,"code":code}
