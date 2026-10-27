class_name TwinI2WaterfrontTerrain
extends RefCounted
## Static, replaceable I2 graybox A. No simulation, saves, authority or rewards.
## All geometry uses clinic-local metres (currently identical to world metres).
## install() changes the existing detached Ground's shape, never its identity.
const VERSION := 1
const ID := "I2:south_waterfront_a"
const EXTENT := Rect2(-28, -28, 56, 56)
const TOP_Y := 0.0
const WATER_Y := -1.2
const BED_Y := -2.8
const BOTTOM_Y := -3.0
const CUT_AREA_M2 := 212.6
const EPSILON := 0.00001
const MAX_TRIANGLES := 2048
const PROFILE := [Vector3(2.3,12.6,16.9),Vector3(15.6,12.6,16.9),Vector3(19,9.5,22.5),Vector3(28,9.5,24.5)]
const DEFAULT_AUTHORED := [Rect2(-22,12,18,12),Rect2(-4,12,12,6),Rect2(14.5,-14,10,16)]
const PARTS := ["dry_surface","authored_support","bank","bed","outer","underside","water"]
var _geometry: Dictionary = {}
var _authored: Array[Rect2] = []
var _report: Dictionary = {}

func configure(authored_regions: Array = DEFAULT_AUTHORED) -> Dictionary:
	# Validate and build on a temporary instance: a rejection keeps this instance.
	if authored_regions.size() > 32: return _failure("authored_limit")
	var regions: Array[Rect2] = []
	for value: Variant in authored_regions:
		if not value is Rect2: return _failure("authored_rect_type")
		var rect: Rect2 = value
		if not rect.position.is_finite() or not rect.size.is_finite() or rect.size.x <= 0 or rect.size.y <= 0 or not EXTENT.encloses(rect): return _failure("authored_rect_bounds")
		for prior: Rect2 in regions:
			if prior.intersects(rect): return _failure("authored_overlap")
		for polygon: PackedVector2Array in _channel_polygons():
			if _area(_intersect_rect(polygon,rect)) > EPSILON: return _failure("authored_intersects_cut")
		regions.append(rect)
	var candidate := TwinI2WaterfrontTerrain.new()
	candidate._authored = regions
	candidate._build()
	var checked: Dictionary = candidate._validate_geometry()
	if not checked.ok: return checked
	_geometry = candidate._geometry.duplicate(true)
	_authored = regions.duplicate()
	_report = checked.duplicate(true)
	return summary()

func summary() -> Dictionary:
	return _report.duplicate(true) if not _report.is_empty() else _failure("not_configured")

func definition() -> Dictionary:
	return {"version":VERSION,"id":ID,"extent":EXTENT,"profile":PROFILE.duplicate(),
		"top_y":TOP_Y,"water_y":WATER_Y,"bed_y":BED_Y,"bottom_y":BOTTOM_Y,
		"authored_regions":_authored.duplicate(),"cut_area_m2":CUT_AREA_M2}

func part_ids() -> Array:
	return _geometry.keys()

func geometry(part: String) -> Dictionary:
	return _geometry.get(part,{}).duplicate(true)

func make_mesh(part: String) -> ArrayMesh:
	if not _geometry.has(part) or _geometry[part].faces.is_empty(): return null
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = _geometry[part].faces.duplicate()
	arrays[Mesh.ARRAY_NORMAL] = _geometry[part].normals.duplicate()
	arrays[Mesh.ARRAY_TEX_UV] = _geometry[part].uv.duplicate()
	var result := ArrayMesh.new()
	result.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
	result.resource_name = "I2 replaceable waterfront / " + part
	return result

func collision_faces(origin: Vector3 = Vector3.ZERO) -> PackedVector3Array:
	var result := PackedVector3Array()
	if not origin.is_finite(): return result
	for part: String in PARTS:
		if part == "water" or not _geometry.has(part): continue
		for point: Vector3 in _geometry[part].faces: result.append(point-origin)
	return result

func make_shape(origin: Vector3 = Vector3.ZERO) -> ConcavePolygonShape3D:
	var faces := collision_faces(origin)
	if faces.is_empty(): return null
	var shape := ConcavePolygonShape3D.new()
	shape.set_faces(faces)
	shape.backface_collision = true
	return shape

func bank_edges(z: float) -> Dictionary:
	if not is_finite(z) or z < PROFILE[0].x or z > PROFILE.back().x: return {}
	for index in range(1,PROFILE.size()):
		var a: Vector3 = PROFILE[index-1]
		var b: Vector3 = PROFILE[index]
		if z > b.x: continue
		var t := (z-a.x)/(b.x-a.x)
		return {"left":lerpf(a.y,b.y,t),"right":lerpf(a.z,b.z,t)}
	return {}

func is_water_xz(x: float,z: float) -> bool:
	if not is_finite(x) or not is_finite(z) or z <= PROFILE[0].x+EPSILON or z > 28.0: return false
	var edge := bank_edges(z)
	return not edge.is_empty() and x > float(edge.left)+EPSILON and x < float(edge.right)-EPSILON

func water_at(at: Vector3) -> Dictionary:
	# A flight environment sample classifies the column above the river surface;
	# FlightBody applies its own contact-height threshold. Solid bed is never water.
	return {"water":at.is_finite() and at.y>BED_Y+EPSILON and is_water_xz(at.x,at.z),"water_height":WATER_Y}

func surface_height(x: float,z: float) -> float:
	if not is_finite(x) or not is_finite(z) or x < -28 or x > 28 or z < -28 or z > 28: return NAN
	return BED_Y if is_water_xz(x,z) else TOP_Y

func install(ground: StaticBody3D, legacy_surface_patches: Array = [], water_material: Material = null) -> Dictionary:
	if _report.is_empty(): return _failure("not_configured")
	if not is_instance_valid(ground) or ground.is_inside_tree(): return _failure("install_detached_ground_required")
	var parent := ground.get_parent() as Node3D
	var old := ground.get_node_or_null("Visual") as MeshInstance3D
	var collision := ground.get_node_or_null("ExactBoxCollision") as CollisionShape3D
	if parent == null or parent.is_inside_tree() or old == null or collision == null or not collision.shape is BoxShape3D: return _failure("original_ground_required")
	if str(ground.name) != "Ground" or ground.collision_layer != 1 or ground.collision_mask != 0: return _failure("ground_identity_contract")
	if not ground.transform.is_equal_approx(Transform3D(Basis.IDENTITY,Vector3(0,-.2,0))) or not collision.transform.is_equal_approx(Transform3D.IDENTITY) or not old.transform.is_equal_approx(Transform3D.IDENTITY): return _failure("ground_pose_contract")
	var original_box := collision.shape as BoxShape3D
	if not original_box.size.is_equal_approx(Vector3(56,.4,56)): return _failure("ground_extent_contract")
	var ancestor: Node = parent
	while ancestor != null:
		if ancestor is Node3D and not ancestor.transform.is_equal_approx(Transform3D.IDENTITY): return _failure("clinic_parent_transform")
		ancestor = ancestor.get_parent()
	if parent.has_node("I2WaterfrontTerrainA"): return _failure("already_installed")
	if not old.visible and legacy_surface_patches.is_empty(): return _failure("hidden_ground_requires_render_patches")
	var seen: Dictionary = {}
	for patch: Variant in legacy_surface_patches:
		if not patch is MeshInstance3D or not is_instance_valid(patch) or not parent.is_ancestor_of(patch) or not str(patch.name).begins_with("RemainingSurface") or seen.has(patch.get_instance_id()): return _failure("invalid_legacy_surface_patch")
		seen[patch.get_instance_id()] = true
	# Material/mesh resources are all prepared before mutating the old Ground.
	var wrapper := Node3D.new()
	wrapper.name = "I2WaterfrontTerrainA"
	wrapper.set_meta("terrain_stage","replaceable_graybox_not_final_art")
	var meshes: Dictionary = {}
	var soil: Material = old.get_active_material(0)
	if soil == null: soil = _material(Color("53696c"),.9)
	var bank := _material(Color("4c6267"),.93)
	var bed := _material(Color("344b50"),.97)
	var water: Material = water_material if water_material != null else _material(Color("315f6a"),.55)
	for part: String in PARTS:
		if part == "authored_support": continue # Existing GLBs are the visible top.
		var mesh := make_mesh(part)
		if mesh == null:
			wrapper.free()
			return _failure("prepared_mesh_missing:"+part)
		var visual := MeshInstance3D.new()
		visual.name = part
		visual.mesh = mesh
		visual.material_override = water if part == "water" else (bank if part == "bank" else (bed if part in ["bed","underside"] else soil))
		if part == "water": visual.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		wrapper.add_child(visual)
		meshes[part] = visual
	var replacement := make_shape(ground.position)
	if replacement == null:
		wrapper.free()
		return _failure("prepared_collision_missing")
	parent.add_child(wrapper)
	collision.shape = replacement
	old.hide()
	for patch: MeshInstance3D in legacy_surface_patches: patch.hide()
	return {"ok":true,"code":"detached_ground_replaced","ground":ground,"shape_node":collision,
		"wrapper":wrapper,"meshes":meshes,"summary":summary(),"collision_policy":"same Ground RID; real cut, banks and bed; no water collider"}

func _build() -> void:
	for part: String in PARTS:
		_geometry[part] = {"faces":PackedVector3Array(),"normals":PackedVector3Array(),"uv":PackedVector2Array(),"collision":part!="water","render":part!="authored_support"}
	var tops: Array[PackedVector2Array] = []
	tops.append(_rect_polygon(Rect2(-28,-28,56,30.3)))
	for index in range(1,PROFILE.size()):
		var a: Vector3 = PROFILE[index-1]
		var b: Vector3 = PROFILE[index]
		tops.append(PackedVector2Array([Vector2(-28,a.x),Vector2(a.y,a.x),Vector2(b.y,b.x),Vector2(-28,b.x)]))
		tops.append(PackedVector2Array([Vector2(a.z,a.x),Vector2(28,a.x),Vector2(28,b.x),Vector2(b.z,b.x)]))
		var channel := PackedVector2Array([Vector2(a.y,a.x),Vector2(a.z,a.x),Vector2(b.z,b.x),Vector2(b.y,b.x)])
		_flat("bed",channel,BED_Y)
		_flat("water",channel,WATER_Y)
		_wall("bank",Vector2(a.y,a.x),Vector2(b.y,b.x),TOP_Y,BED_Y,Vector3(b.x-a.x,0,a.y-b.y))
		_wall("bank",Vector2(a.z,a.x),Vector2(b.z,b.x),TOP_Y,BED_Y,Vector3(a.x-b.x,0,b.z-a.z))
	_wall("bank",Vector2(12.6,2.3),Vector2(16.9,2.3),TOP_Y,BED_Y,Vector3.BACK)
	for polygon: PackedVector2Array in tops:
		var remainder: Array[PackedVector2Array] = [polygon]
		for rect: Rect2 in _authored:
			_flat("authored_support",_intersect_rect(polygon,rect),TOP_Y)
			var next: Array[PackedVector2Array] = []
			for item: PackedVector2Array in remainder: next.append_array(_subtract_rect(item,rect))
			remainder = next
		for item: PackedVector2Array in remainder: _flat("dry_surface",item,TOP_Y)
	_wall("outer",Vector2(-28,-28),Vector2(28,-28),TOP_Y,BOTTOM_Y,Vector3.FORWARD)
	_wall("outer",Vector2(-28,-28),Vector2(-28,28),TOP_Y,BOTTOM_Y,Vector3.LEFT)
	_wall("outer",Vector2(28,-28),Vector2(28,28),TOP_Y,BOTTOM_Y,Vector3.RIGHT)
	_wall("outer",Vector2(-28,28),Vector2(9.5,28),TOP_Y,BOTTOM_Y,Vector3.BACK)
	_wall("outer",Vector2(24.5,28),Vector2(28,28),TOP_Y,BOTTOM_Y,Vector3.BACK)
	# Only the 20cm bed thickness is capped at the south boundary, never its air/water opening.
	_wall("outer",Vector2(9.5,28),Vector2(24.5,28),BED_Y,BOTTOM_Y,Vector3.BACK)
	_flat("underside",_rect_polygon(EXTENT),BOTTOM_Y,Vector3.DOWN)

func _validate_geometry() -> Dictionary:
	var triangles := 0
	var areas: Dictionary = {}
	for part: String in PARTS:
		var faces: PackedVector3Array = _geometry[part].faces
		var normals: PackedVector3Array = _geometry[part].normals
		if faces.size()%3 != 0 or faces.size()!=normals.size(): return _failure("geometry_arrays")
		var area := 0.0
		for i in range(0,faces.size(),3):
			var cross := (faces[i+1]-faces[i]).cross(faces[i+2]-faces[i])
			if not faces[i].is_finite() or not faces[i+1].is_finite() or not faces[i+2].is_finite() or cross.length_squared()<1e-14 or cross.dot(normals[i])>=0: return _failure("geometry_invalid_triangle")
			area += cross.length()*.5
		areas[part] = area
		triangles += faces.size()/3
		_geometry[part].triangle_count = faces.size()/3
	var authored_area := 0.0
	for rect: Rect2 in _authored: authored_area += rect.get_area()
	# Float32 mesh coordinates introduce micrometre differences; not geometry expansion.
	if absf(float(areas.water)-CUT_AREA_M2)>.001 or absf(float(areas.bed)-CUT_AREA_M2)>.001 or absf(float(areas.authored_support)-authored_area)>.001 or absf(float(areas.dry_surface)+authored_area+CUT_AREA_M2-3136)>.002: return _failure("geometry_area_partition")
	if triangles>MAX_TRIANGLES: return _failure("geometry_budget")
	return {"ok":true,"code":"static_geometry_ready","cut_area_m2":CUT_AREA_M2,"dry_area_m2":3136-CUT_AREA_M2,"authored_area_m2":authored_area,"visible_dry_area_m2":3136-CUT_AREA_M2-authored_area,"areas":areas,"triangles":triangles,"water_collision":false,"backface_collision":true,"bounds":AABB(Vector3(-28,-3,-28),Vector3(56,3,56))}

func _tri(part: String,a: Vector3,b: Vector3,c: Vector3,toward: Vector3) -> void:
	var cross := (b-a).cross(c-a)
	if cross.length_squared()<1e-14: return
	if cross.dot(toward)>0:
		var swap := b
		b=c
		c=swap
		cross=-cross
	var normal := -cross.normalized() # Godot front faces are clockwise.
	for point: Vector3 in [a,b,c]:
		_geometry[part].faces.append(point)
		_geometry[part].normals.append(normal)
		_geometry[part].uv.append(Vector2(point.x,point.z)*.25 if absf(normal.y)>.5 else Vector2(point.x+point.z,point.y)*.25)

func _flat(part: String,polygon: PackedVector2Array,y: float,normal: Vector3=Vector3.UP) -> void:
	for i in range(1,polygon.size()-1):
		_tri(part,Vector3(polygon[0].x,y,polygon[0].y),Vector3(polygon[i].x,y,polygon[i].y),Vector3(polygon[i+1].x,y,polygon[i+1].y),normal)

func _wall(part: String,p: Vector2,q: Vector2,top: float,bottom: float,normal: Vector3) -> void:
	var a:=Vector3(p.x,top,p.y)
	var b:=Vector3(q.x,top,q.y)
	var c:=Vector3(q.x,bottom,q.y)
	var d:=Vector3(p.x,bottom,p.y)
	_tri(part,a,b,c,normal)
	_tri(part,a,c,d,normal)

static func _channel_polygons() -> Array[PackedVector2Array]:
	var result: Array[PackedVector2Array] = []
	for index in range(1,PROFILE.size()):
		var a: Vector3=PROFILE[index-1]
		var b: Vector3=PROFILE[index]
		result.append(PackedVector2Array([Vector2(a.y,a.x),Vector2(a.z,a.x),Vector2(b.z,b.x),Vector2(b.y,b.x)]))
	return result

static func _rect_polygon(rect: Rect2) -> PackedVector2Array:
	return PackedVector2Array([rect.position,Vector2(rect.end.x,rect.position.y),rect.end,Vector2(rect.position.x,rect.end.y)])

static func _clip(polygon: PackedVector2Array,axis: int,edge: float,sign_value: float) -> PackedVector2Array:
	var result:=PackedVector2Array()
	for i in polygon.size():
		var a:=polygon[i]
		var b:=polygon[(i+1)%polygon.size()]
		var inside_a: bool=(a[axis]-edge)*sign_value>=0
		var inside_b: bool=(b[axis]-edge)*sign_value>=0
		if inside_a: result.append(a)
		if inside_a!=inside_b: result.append(a.lerp(b,(edge-a[axis])/(b[axis]-a[axis])))
	return result

static func _intersect_rect(polygon: PackedVector2Array,rect: Rect2) -> PackedVector2Array:
	var result:=_clip(polygon,0,rect.position.x,1)
	result=_clip(result,0,rect.end.x,-1)
	result=_clip(result,1,rect.position.y,1)
	return _clip(result,1,rect.end.y,-1)

static func _subtract_rect(polygon: PackedVector2Array,rect: Rect2) -> Array[PackedVector2Array]:
	var result: Array[PackedVector2Array]=[]
	var middle:=_clip(_clip(polygon,0,rect.position.x,1),0,rect.end.x,-1)
	for item: PackedVector2Array in [_clip(polygon,0,rect.position.x,-1),_clip(polygon,0,rect.end.x,1),_clip(middle,1,rect.position.y,-1),_clip(middle,1,rect.end.y,1)]:
		if _area(item)>1e-10: result.append(item)
	return result

static func _area(polygon: PackedVector2Array) -> float:
	var result:=0.0
	for i in polygon.size(): result+=polygon[i].cross(polygon[(i+1)%polygon.size()])
	return absf(result)*.5

static func _material(color: Color,roughness: float) -> StandardMaterial3D:
	var result:=StandardMaterial3D.new()
	result.albedo_color=color
	result.roughness=roughness
	return result

static func _failure(code: String) -> Dictionary:
	return {"ok":false,"code":code}
