extends RefCounted
## Initial-construction candidate. Real empty pit; no water, rewards or Store.
## Render and Ground collider share these exact metres. Art remains unapproved.
const Reader=preload("res://scripts/v3/art/twin_i2_east_revetment_art.gd")
const Split=preload("res://scripts/v3/art/twin_i2_revetment_partition.gd")
const RectCut=preload("res://scripts/v3/art/twin_i2_east_maintenance_art.gd")
const REGION:=Rect2(-22,1,8.75,9.5)
const INTERIOR:=Rect2(-21.7,1.3,8.15,8.9)
const RAMP:=Rect2(-20.5,4,3,6.5)
const BOTTOM:=-2.4
const PARTS:=["floor","walls","coping","ramp"]
var parts: Dictionary={}

func build_geometry() -> Dictionary:
	parts.clear()
	for part: String in PARTS: parts[part]=Split._empty_geometry()
	# The ramp occupies a solid wedge; leave its footprint out of the visible floor.
	_flat("floor",Rect2(-21.7,1.3,8.15,2.7),BOTTOM)
	_flat("floor",Rect2(-21.7,4,1.2,6.2),BOTTOM)
	_flat("floor",Rect2(-17.5,4,3.95,6.2),BOTTOM)
	# Copings lie within the excavated rectangle and are flush with the yard.
	_flat("coping",Rect2(-22,1,.3,9.5),0)
	_flat("coping",Rect2(-13.55,1,.3,9.5),0)
	_flat("coping",Rect2(-21.7,1,8.15,.3),0)
	_flat("coping",Rect2(-21.7,10.2,1.2,.3),0)
	_flat("coping",Rect2(-17.5,10.2,3.95,.3),0)
	_wall(Vector2(-21.7,1.3),Vector2(-21.7,10.2),Vector3.RIGHT)
	_wall(Vector2(-13.55,1.3),Vector2(-13.55,10.2),Vector3.LEFT)
	_wall(Vector2(-21.7,1.3),Vector2(-13.55,1.3),Vector3.BACK)
	_wall(Vector2(-21.7,10.2),Vector2(-20.5,10.2),Vector3.FORWARD)
	_wall(Vector2(-17.5,10.2),Vector2(-13.55,10.2),Vector3.FORWARD)
	# Slope is high at south/yard (z10.5), low at north/bottom (z4).
	_quad("ramp",Vector3(-20.5,BOTTOM,4),Vector3(-17.5,BOTTOM,4),Vector3(-17.5,0,10.5),Vector3(-20.5,0,10.5),Vector3.UP)
	_tri("ramp",Vector3(-20.5,BOTTOM,4),Vector3(-20.5,BOTTOM,10.5),Vector3(-20.5,0,10.5),Vector3.LEFT)
	_tri("ramp",Vector3(-17.5,BOTTOM,4),Vector3(-17.5,BOTTOM,10.5),Vector3(-17.5,0,10.5),Vector3.RIGHT)
	for part: String in PARTS:
		var validated: Dictionary=Split._validate(parts[part])
		if not validated.ok: return {"ok":false,"code":"pit_geometry:"+part+":"+str(validated.code)}
	return {"ok":true,"code":"pit_geometry_ready","parts":parts,"area_m2":REGION.get_area()}

func surface_height(x: float,z: float) -> float:
	if not is_finite(x) or not is_finite(z) or not REGION.has_point(Vector2(x,z)): return NAN
	if x>=RAMP.position.x and x<=RAMP.end.x and z>=4 and z<=10.5: return BOTTOM+(z-4)*2.4/6.5
	return BOTTOM if INTERIOR.has_point(Vector2(x,z)) else 0.0

func install(installed: Dictionary) -> Dictionary:
	if not installed.get("ok",false): return {"ok":false,"code":"waterfront_required"}
	var parent: Node3D=installed.get("wrapper")
	var ground: StaticBody3D=installed.get("ground")
	var shape_node: CollisionShape3D=installed.get("shape_node")
	var dry: MeshInstance3D=installed.get("meshes",{}).get("dry_surface")
	if not is_instance_valid(parent) or not is_instance_valid(ground) or not is_instance_valid(shape_node) or not is_instance_valid(dry): return {"ok":false,"code":"host_required"}
	if parent.has_node("InspectionPitCandidate"): return {"ok":false,"code":"already_installed"}
	if not shape_node.shape is ConcavePolygonShape3D or not shape_node.transform.is_equal_approx(Transform3D.IDENTITY) or not dry.transform.is_equal_approx(Transform3D.IDENTITY) or not ground.transform.is_equal_approx(Transform3D(Basis.IDENTITY,Vector3(0,-.2,0))): return {"ok":false,"code":"host_pose"}
	var read: Dictionary=Reader._read_mesh(dry.mesh)
	if not read.ok: return read
	var visual_cut: Dictionary=_cut_top(read.geometry)
	if not visual_cut.ok: return visual_cut
	var physical: Dictionary=Split._empty_geometry()
	var original_faces: PackedVector3Array=shape_node.shape.get_faces()
	for first in range(0,original_faces.size(),3):
		var a: Vector3=original_faces[first]+ground.position
		var b: Vector3=original_faces[first+1]+ground.position
		var c: Vector3=original_faces[first+2]+ground.position
		var n: Vector3=-(b-a).cross(c-a).normalized()
		for p: Vector3 in [a,b,c]:
			physical.faces.append(p); physical.normals.append(n); physical.uv.append(Vector2(p.x,p.z)*.25)
	var physical_cut: Dictionary=_cut_top(physical)
	if not physical_cut.ok: return physical_cut
	var built: Dictionary=build_geometry()
	if not built.ok: return built
	var wrapper:=Node3D.new()
	wrapper.name="InspectionPitCandidate"
	wrapper.set_meta("stage","geometry_graybox_not_final_art")
	var face_list: PackedVector3Array=physical_cut.kept.faces.duplicate()
	var visuals: Dictionary={}
	for part: String in PARTS:
		face_list.append_array(parts[part].faces)
		var view:=MeshInstance3D.new()
		view.name=part
		view.mesh=_mesh(parts[part])
		var material:=StandardMaterial3D.new()
		material.albedo_color=Color("77776b") if part=="walls" else (Color("aa9f88") if part=="coping" else Color("64645d"))
		material.roughness=.92
		view.material_override=material
		wrapper.add_child(view)
		visuals[part]=view
	var replacement:=ConcavePolygonShape3D.new()
	for index in face_list.size(): face_list[index]-=ground.position
	replacement.set_faces(face_list)
	replacement.backface_collision=true
	var dry_mesh: ArrayMesh=Reader._make_mesh(visual_cut.kept,"dry surface / actual inspection cut")
	dry_mesh.surface_set_material(0,dry.mesh.surface_get_material(0))
	# All construction and area checks succeeded; mutate the same Ground only now.
	parent.add_child(wrapper)
	dry.mesh=dry_mesh
	shape_node.shape=replacement
	return {"ok":true,"code":"real_inspection_pit_installed","wrapper":wrapper,"visuals":visuals,"cut_m2":physical_cut.removed_area,"visible_cut_m2":visual_cut.removed_area,"triangles":face_list.size()/3,"ground":ground,"shape":replacement,"geometry":parts}

static func _cut_top(source: Dictionary) -> Dictionary:
	var kept: Dictionary=Split._empty_geometry()
	var removed: Dictionary=Split._empty_geometry()
	for first in range(0,source.faces.size(),3):
		var polygon: Array[Dictionary]=[]
		var eligible:=true
		for corner in 3:
			var index: int=first+corner
			var p: Vector3=source.faces[index]
			eligible=eligible and absf(p.y)<.00001 and source.normals[index].y>.999
			polygon.append({"p":p,"n":source.normals[index],"uv":source.uv[index]})
		if not eligible:
			Split._emit(kept,polygon,first/3); continue
		var row: Dictionary=RectCut._partition(polygon,REGION)
		for piece: Array[Dictionary] in row.outside: Split._emit(kept,piece,first/3)
		Split._emit(removed,row.inside,first/3)
	if source.has("tangents"):
		var tangents:=PackedFloat32Array()
		for triangle: int in kept.source_triangles:
			for corner in 3:
				for component in 4: tangents.append(source.tangents[triangle*12+corner*4+component])
		kept.tangents=tangents
	for row: Dictionary in [kept,removed]:
		var valid: Dictionary=Split._validate(row)
		if not valid.ok: return valid
	var area: float=Split._area(removed)
	if absf(area-REGION.get_area())>.0002 or absf(Split._area(source)-Split._area(kept)-area)>.0002: return {"ok":false,"code":"cut_area","actual":area}
	return {"ok":true,"kept":kept,"removed_area":area}

func _flat(part: String,rect: Rect2,y: float) -> void:
	_quad(part,Vector3(rect.position.x,y,rect.position.y),Vector3(rect.end.x,y,rect.position.y),Vector3(rect.end.x,y,rect.end.y),Vector3(rect.position.x,y,rect.end.y),Vector3.UP)

static func _mesh(data: Dictionary) -> ArrayMesh:
	var arrays: Array=[]
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX]=data.faces
	arrays[Mesh.ARRAY_NORMAL]=data.normals
	arrays[Mesh.ARRAY_TEX_UV]=data.uv
	var mesh:=ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
	return mesh

func _wall(p: Vector2,q: Vector2,normal: Vector3) -> void:
	_quad("walls",Vector3(p.x,0,p.y),Vector3(q.x,0,q.y),Vector3(q.x,BOTTOM,q.y),Vector3(p.x,BOTTOM,p.y),normal)

func _quad(part: String,a: Vector3,b: Vector3,c: Vector3,d: Vector3,toward: Vector3) -> void:
	_tri(part,a,b,c,toward); _tri(part,a,c,d,toward)

func _tri(part: String,a: Vector3,b: Vector3,c: Vector3,toward: Vector3) -> void:
	var cross: Vector3=(b-a).cross(c-a)
	if cross.dot(toward)>0:
		var swap:=b; b=c; c=swap; cross=-cross
	var n: Vector3=-cross.normalized()
	for p: Vector3 in [a,b,c]:
		parts[part].faces.append(p); parts[part].normals.append(n)
		parts[part].uv.append(Vector2(p.x,p.z) if absf(n.y)>.5 else Vector2(p.x+p.z,p.y))
