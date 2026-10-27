extends RefCounted
## Visual-only candidate on the actual two-bank remainder. Never replaces a
## collision shape: the five support feet retain their original ground below.
const Reader=preload("res://scripts/v3/art/twin_i2_east_revetment_art.gd")
const Split=preload("res://scripts/v3/art/twin_i2_revetment_partition.gd")
const MODEL:="res://assets/v3/candidates/i2_east_maintenance_extension/east_maintenance_extension.glb"
const ORIGIN:=Vector3(20.7,0,8.8)
const AREA:=97.545
const REGION:=Rect2(16.9,2,7.6,13.6)
const HOLES:=[Rect2(20.56,5.66,.68,.68),Rect2(20.56,13.36,.68,.68),Rect2(17.69,3.86,.28,.28),Rect2(17.69,9.66,.28,.28),Rect2(17.26,5.96,.28,.28)]

static func install(installed: Dictionary) -> Dictionary:
	if not installed.get("ok",false) or not installed.get("meshes",{}).get("dry_surface") is MeshInstance3D:
		return {"ok":false,"code":"waterfront_required"}
	var old: MeshInstance3D=installed.meshes.dry_surface
	var parent: Node3D=old.get_parent()
	if parent.has_node("EastMaintenanceExtensionCandidate"):
		return {"ok":false,"code":"already_installed"}
	if not old.visible or not old.transform.is_equal_approx(Transform3D.IDENTITY):
		return {"ok":false,"code":"original_dry_surface_required"}
	var read: Dictionary=Reader._read_mesh(old.mesh)
	if not read.ok: return read
	var cut: Dictionary=_cut(read.geometry)
	if not cut.ok: return cut
	var packed:=load(MODEL) as PackedScene
	if packed==null: return {"ok":false,"code":"import_missing"}
	var model:=packed.instantiate() as Node3D
	if model==null: return {"ok":false,"code":"import_root"}
	var checked: Dictionary=_validate_model(model)
	if not checked.ok:
		model.free()
		return checked
	var mesh: ArrayMesh=Reader._make_mesh(cut.kept,"east maintenance")
	mesh.surface_set_material(0,old.mesh.surface_get_material(0))
	# All validation completes before the visible scene is changed.
	model.name="EastMaintenanceExtensionCandidate"
	model.position=ORIGIN
	parent.add_child(model)
	old.mesh=mesh
	return {"ok":true,"code":"east_maintenance_installed","model":model,"meshes":checked.meshes,"triangles":checked.triangles,"removed_area_m2":cut.removed_area,"remaining_area_m2":cut.remaining_area,"model_path":MODEL,"collision_unchanged":true}

static func _validate_model(model: Node3D) -> Dictionary:
	for kind: String in ["CollisionObject3D","Camera3D","Light3D","AnimationPlayer"]:
		if not model.find_children("*",kind,true,false).is_empty(): return {"ok":false,"code":"unexpected_import:"+kind}
	var meshes: Array=model.find_children("*","MeshInstance3D",true,false)
	if meshes.size()!=2: return {"ok":false,"code":"two_meshes_required"}
	var names: Dictionary={"FloorSurface":9240,"InspectionBand":7484}
	var materials: Dictionary={}
	var bounds:=AABB()
	var first:=true
	var triangles:=0
	for view: MeshInstance3D in meshes:
		if str(view.name) not in names or view.mesh==null or view.mesh.get_surface_count()!=1:
			return {"ok":false,"code":"mesh_contract"}
		var node: Node=view
		while node!=null:
			if node is Node3D and not node.transform.is_equal_approx(Transform3D.IDENTITY): return {"ok":false,"code":"identity_required"}
			node=node.get_parent()
		var count:=int(view.mesh.get_faces().size()/3)
		if count!=names[str(view.name)]: return {"ok":false,"code":"triangle_contract"}
		triangles+=count
		bounds=view.get_aabb() if first else bounds.merge(view.get_aabb())
		first=false
		var material:=view.get_active_material(0) as BaseMaterial3D
		if material==null or material.transparency!=BaseMaterial3D.TRANSPARENCY_DISABLED or material.albedo_texture==null or material.normal_texture==null or material.metallic_texture==null or material.roughness_texture==null:
			return {"ok":false,"code":"opaque_pbr_required"}
		materials[material.get_instance_id()]=true
	if materials.size()!=2 or not bounds.position.is_equal_approx(Vector3(-3.8,-.18,-6.8)) or not bounds.size.is_equal_approx(Vector3(7.6,.18,13.6)):
		return {"ok":false,"code":"material_or_bounds"}
	return {"ok":true,"meshes":meshes,"triangles":triangles}

static func _partition(polygon: Array[Dictionary], rect: Rect2) -> Dictionary:
	var inside: Array[Dictionary]=polygon
	var outside: Array=[]
	for plane: Array in [[0,rect.position.x,1.0],[0,rect.end.x,-1.0],[2,rect.position.y,1.0],[2,rect.end.y,-1.0]]:
		var row: Dictionary=Split._split(inside,int(plane[0]),float(plane[1]),float(plane[2]))
		if Split._polygon_area(row.outside)>1e-12: outside.append(row.outside)
		inside=row.inside
	return {"inside":inside,"outside":outside}

static func _cut(source: Dictionary) -> Dictionary:
	var kept: Dictionary=Split._empty_geometry()
	var removed: Dictionary=Split._empty_geometry()
	for first in range(0,source.faces.size(),3):
		var polygon: Array[Dictionary]=[]
		for corner in 3:
			var index: int=first+corner
			polygon.append({"p":source.faces[index],"n":source.normals[index],"uv":source.uv[index]})
		var outer: Dictionary=_partition(polygon,REGION)
		for piece: Array[Dictionary] in outer.outside: Split._emit(kept,piece,first/3)
		var pending: Array=[outer.inside] if Split._polygon_area(outer.inside)>1e-12 else []
		for hole: Rect2 in HOLES:
			var next: Array=[]
			for piece: Array[Dictionary] in pending:
				var row: Dictionary=_partition(piece,hole)
				Split._emit(kept,row.inside,first/3)
				next.append_array(row.outside)
			pending=next
		for piece: Array[Dictionary] in pending: Split._emit(removed,piece,first/3)
	for output: Dictionary in [kept,removed]:
		var tangents:=PackedFloat32Array()
		for triangle: int in output.source_triangles:
			for corner in 3:
				for component in 4: tangents.append(source.tangents[triangle*12+component])
		output.tangents=tangents
		var validated: Dictionary=Split._validate(output)
		if not validated.ok: return validated
	var area_before: float=Split._area(source)
	var area_kept: float=Split._area(kept)
	var area_removed: float=Split._area(removed)
	if absf(area_removed-AREA)>.0002 or absf(area_before-area_kept-area_removed)>.0002:
		return {"ok":false,"code":"exact_extension_area","removed":area_removed,"expected":AREA}
	return {"ok":true,"kept":kept,"removed_area":area_removed,"remaining_area":area_kept}
