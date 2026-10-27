class_name TwinClinicPumpArt
extends RefCounted
## Imported presentation only. Seven existing authority colliders keep their
## transforms, shapes and ownership; camera fading still targets those bodies.
const MODEL_PATH := "res://assets/v3/clinic_pump_shell/clinic_pump_shell.glb"
const ORIGIN := Vector3(-7,0,8)
const PARTS := {
	"FloorSurface":"PumpFloor",
	"WallFeetAndJambs":"",
	"WestCover":"PumpWestWall",
	"EastCover":"PumpEastWall",
	"NorthCover":"PumpNorthWall",
	"RoofCover":"PumpRoof",
}
const BOXES := {
	"PumpFloor":[Vector3(-12,0,4),Vector3(-2,.4,12)],
	"PumpWestWall":[Vector3(-12.25,.4,4),Vector3(-12,3.2,12)],
	"PumpEastWall":[Vector3(-2,.4,4),Vector3(-1.75,3.2,12)],
	"PumpNorthWall":[Vector3(-12,.4,3.75),Vector3(-2,3.2,4)],
	"PumpSouthWestJamb":[Vector3(-12,.4,12),Vector3(-8.7,3.2,12.25)],
	"PumpSouthEastJamb":[Vector3(-5.3,.4,12),Vector3(-2,3.2,12.25)],
	"PumpRoof":[Vector3(-12.25,3.2,3.75),Vector3(-1.75,3.5,12.25)],
}

static func install(works: Node3D) -> Dictionary:
	if works.is_inside_tree() or works.has_meta("authored_pump_shell"):
		return {"ok":false,"code":"pump_art_install_before_tree_once"}
	# Validate everything before hiding any existing visible graybox.
	for id in BOXES:
		var body: Variant = works.fixed_bodies.get(id)
		if not body is StaticBody3D or body.get_node_or_null("Visual")==null:
			return {"ok":false,"code":"pump_art_body_missing:"+id}
		var shape := body.get_node_or_null("ExactBoxCollision") as CollisionShape3D
		if shape==null or not shape.shape is BoxShape3D or not shape.transform.is_equal_approx(Transform3D.IDENTITY):
			return {"ok":false,"code":"pump_art_box_required:"+id}
		var expected := Transform3D(Basis.IDENTITY,(BOXES[id][0]+BOXES[id][1])*.5)
		if not body.transform.is_equal_approx(expected) or not shape.shape.size.is_equal_approx(BOXES[id][1]-BOXES[id][0]):
			return {"ok":false,"code":"pump_art_box_changed:"+id}
	var packed := load(MODEL_PATH) as PackedScene
	if packed==null: return {"ok":false,"code":"pump_art_glb_missing"}
	var model := packed.instantiate() as Node3D
	if model==null: return {"ok":false,"code":"pump_art_root_type"}
	if model.get_node_or_null("ClinicPumpShell")==null:
		return _reject(model,"pump_art_design_root")
	var meshes := model.find_children("*","MeshInstance3D",true,false)
	if meshes.size()!=PARTS.size() or not model.find_children("*","CollisionObject3D",true,false).is_empty() or not model.find_children("*","Camera3D",true,false).is_empty() or not model.find_children("*","Light3D",true,false).is_empty():
		return _reject(model,"pump_art_export_contract")
	var selected := {}
	var materials := {}
	var triangles := 0
	for mesh: MeshInstance3D in meshes:
		var id := str(mesh.name)
		if not PARTS.has(id) or selected.has(id) or mesh.mesh==null or mesh.mesh.get_surface_count()!=1:
			return _reject(model,"pump_art_mesh_contract:"+id)
		var ancestor: Node = mesh
		while ancestor!=null:
			if ancestor is Node3D and not ancestor.transform.is_equal_approx(Transform3D.IDENTITY):
				return _reject(model,"pump_art_transform:"+id)
			ancestor=ancestor.get_parent()
		var material := mesh.get_active_material(0) as BaseMaterial3D
		if material==null or material.albedo_texture==null or material.normal_texture==null or material.roughness_texture==null or material.metallic_texture==null:
			return _reject(model,"pump_art_pbr:"+id)
		materials[material.get_instance_id()]=true
		var faces := mesh.mesh.get_faces()
		triangles+=int(faces.size()/3)
		for vertex in faces:
			if not _inside_original_solids(ORIGIN+vertex):
				return _reject(model,"pump_art_outside_existing_collision:"+id)
		selected[id]=mesh
	if triangles!=13600 or materials.size()!=1:
		return _reject(model,"pump_art_geometry_material_count")
	var permanent := Node3D.new()
	permanent.name="PumpPermanentNavigation"
	permanent.position=ORIGIN
	permanent.set_meta("terrain_visibility_keep",true)
	works.add_child(permanent)
	var covers: Array = []
	for id in PARTS:
		var mesh: MeshInstance3D = selected[id]
		mesh.owner=null
		mesh.get_parent().remove_child(mesh)
		if PARTS[id]=="":
			permanent.add_child(mesh)
		else:
			var body: StaticBody3D = works.fixed_bodies[PARTS[id]]
			body.add_child(mesh)
			mesh.transform=body.transform.affine_inverse()*Transform3D(Basis.IDENTITY,ORIGIN)
			if id!="FloorSurface":
				mesh.set_meta("terrain_visibility_single_sided",true)
				covers.append(body)
	for id in BOXES: works.fixed_bodies[id].get_node("Visual").hide()
	model.free()
	works.set_meta("authored_pump_shell",true)
	return {"ok":true,"code":"pump_art_installed","path":MODEL_PATH,"triangles":triangles,
		"mesh_count":meshes.size(),"model_meshes":meshes,"occluders":covers,
		"permanent":permanent,"collision_policy":"seven original bodies and shapes unchanged"}

static func _inside_original_solids(point: Vector3) -> bool:
	for pair in BOXES.values():
		if AABB(pair[0],pair[1]-pair[0]).grow(.0005).has_point(point): return true
	return false

static func _reject(model: Node, code: String) -> Dictionary:
	model.free()
	return {"ok":false,"code":code}
