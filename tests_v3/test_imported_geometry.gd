extends SceneTree
## Pure imported-geometry integrity checks. No runtime scene, GPU, network,
## raw GLB mutation, import setting mutation, save or production JSON writes.
const Geometry = preload("res://scripts/v3/world/twin_imported_geometry.gd")
var checks := 0
var failures: Array[String] = []
var imported: Dictionary = {}

func _init() -> void:
	_test_memory_geometry()
	_test_rejections_and_ownership()
	_test_imported_scenes()
	print("V3_IMPORTED_GEOMETRY_TEST "+JSON.stringify({"checks":checks,"failures":failures,
		"algorithm":Geometry.ALGORITHM,"signatures":imported,
		"scope":"Off-tree resources and in-memory geometry only; exported-PCK behavior requires separate root export test."}))
	quit(0 if failures.is_empty() else 1)

func _check(ok: bool,label: String) -> void:
	checks+=1
	if not ok:
		failures.append(label)
		push_error("IMPORTED_GEOMETRY "+label)

func _faces() -> PackedVector3Array:
	return PackedVector3Array([Vector3(0,0,0),Vector3(0,0,2),Vector3(2,0,0),
		Vector3(0,1,0),Vector3(2,1,0),Vector3(0,1,2)])

func _mesh(faces: PackedVector3Array) -> ArrayMesh:
	var arrays: Array=[]
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX]=faces
	var mesh:=ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
	return mesh

func _fixture() -> Node3D:
	var root:=Node3D.new()
	root.name="Root"
	root.transform=Transform3D(Basis(Vector3.UP,.3),Vector3(2,3,4))
	var pivot:=Node3D.new()
	pivot.name="Pivot"
	pivot.transform=Transform3D(Basis(Vector3.RIGHT,.2).scaled(Vector3(1.2,.8,1.0)),Vector3(.3,.5,.7))
	root.add_child(pivot)
	var shape:=MeshInstance3D.new()
	shape.name="Body"
	shape.mesh=_mesh(_faces())
	pivot.add_child(shape)
	return root

func _test_memory_geometry() -> void:
	var root:=_fixture()
	var shape: MeshInstance3D=root.get_node("Pivot/Body")
	var original_transform:=root.transform
	var pivot_transform: Transform3D=root.get_node("Pivot").transform
	var original_bytes:=shape.mesh.get_faces().to_byte_array()
	var original_mesh_id:=shape.mesh.get_instance_id()
	var result: Dictionary=Geometry.signature_node(root)
	var sha: String=result.sha256
	_check(result.ok and sha.length()==64 and result.mesh_count==1 and result.triangle_count==2 and result.node_count==3,"counts and SHA from actual triangles")
	_check(not root.is_inside_tree() and root.transform==original_transform and root.get_node("Pivot").transform==pivot_transform and shape.mesh.get_instance_id()==original_mesh_id and shape.mesh.get_faces().to_byte_array()==original_bytes,"hashing does not enter tree, edit transforms, replace mesh or change source vertices")
	_check(Geometry.signature_node(root)==result,"reentry repeats exact digest and counts")
	result.sha256="caller edit"
	_check(Geometry.signature_node(root).sha256==sha,"returned dictionary cannot poison a cached result")
	root.position.x+=.125
	_check(Geometry.signature_node(root).sha256!=sha,"nonidentity root transform participates")
	root.transform=original_transform
	root.get_node("Pivot").position.z+=.01
	_check(Geometry.signature_node(root).sha256!=sha,"parent transform moves actual descendant geometry in signature")
	root.get_node("Pivot").transform=pivot_transform
	shape.position.y=.001
	_check(Geometry.signature_node(root).sha256!=sha,"mesh-local transform participates")
	shape.position=Vector3.ZERO
	root.get_node("Pivot").name="RenamedPivot"
	_check(Geometry.signature_node(root).sha256!=sha,"stable hierarchy names participate")
	root.get_node("RenamedPivot").name="Pivot"
	_check(Geometry.signature_node(root).sha256==sha,"reverting changes restores original signature without stale cache")

	var clone: Node3D=root.duplicate()
	var copied_shape: MeshInstance3D=clone.get_node("Pivot/Body")
	var moved_faces:=_faces()
	moved_faces[0].x+=.001
	copied_shape.mesh=_mesh(moved_faces)
	_check(Geometry.signature_node(clone).sha256!=sha,"real vertex position change is detected")
	_check(Geometry.signature_node(root).sha256==sha and shape.mesh.get_faces().to_byte_array()==original_bytes,"modified copy does not mutate original resource")
	var reordered:=_faces()
	reordered=PackedVector3Array([reordered[3],reordered[4],reordered[5],reordered[0],reordered[1],reordered[2]])
	copied_shape.mesh=_mesh(reordered)
	_check(Geometry.signature_node(clone).sha256!=sha,"triangle byte order remains evidence; faces are not sorted")
	clone.free()

	var material:=StandardMaterial3D.new()
	material.albedo_color=Color(0.7,0.1,0.2)
	material.albedo_texture=GradientTexture2D.new()
	shape.material_override=material
	shape.mesh.surface_set_material(0,material)
	shape.set_meta("irrelevant_note","not geometry")
	_check(Geometry.signature_node(root).sha256==sha,"material, texture and metadata changes are excluded")
	var sibling:=MeshInstance3D.new()
	sibling.name="Second"
	sibling.mesh=shape.mesh
	root.add_child(sibling)
	var two: Dictionary=Geometry.signature_node(root)
	root.move_child(sibling,0)
	_check(Geometry.signature_node(root).sha256==two.sha256,"sibling insertion order does not destabilize named hierarchy")
	_check(two.mesh_count==2 and two.triangle_count==4,"shared mesh resource at two nodes counts both real instances")
	var pivot: Node3D=root.get_node("Pivot")
	pivot.top_level=true
	_check(Geometry.signature_node(root).sha256!=two.sha256,"top-level inheritance boundary is encoded")
	root.free()

func _test_rejections_and_ownership() -> void:
	_check(Geometry.signature("res://assets/v3/root_buttress/not_present.glb").code=="resource_missing","missing remapped resource rejected")
	_check(Geometry.signature_node(null).code=="root_missing","missing root rejected")
	var empty:=Node3D.new()
	empty.name="Empty"
	_check(Geometry.signature_node(empty).code=="empty_geometry" and is_instance_valid(empty),"empty caller-owned scene rejected without freeing caller")
	empty.free()
	var missing:=MeshInstance3D.new()
	missing.name="MissingMesh"
	_check(Geometry.signature_node(missing).code=="missing_mesh" and is_instance_valid(missing),"missing mesh rejected without silently skipping")
	missing.mesh=ArrayMesh.new()
	_check(Geometry.signature_node(missing).code=="empty_mesh","mesh without surfaces rejected")
	missing.mesh=_mesh(_faces())
	missing.position.x=INF
	_check(Geometry.signature_node(missing).code=="nonfinite_transform","nonfinite transform rejected")
	missing.position=Vector3.ZERO
	missing.mesh=null
	var scene:=PackedScene.new()
	_check(scene.pack(missing)==OK,"invalid-mesh off-tree packed fixture constructed")
	missing.free()
	var orphan_before:=int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT))
	var all_rejected:=true
	for i in 8:
		var failure: Dictionary=Geometry._signature_packed_scene(scene)
		all_rejected=all_rejected and not failure.ok and failure.code=="missing_mesh" and failure.sha256.is_empty()
	_check(all_rejected,"all instantiated missing-mesh paths return explicit failure")
	_check(int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT))==orphan_before,"failure exits immediately free their instantiated nodes")
	_check(Geometry._signature_packed_scene(PackedScene.new()).code=="scene_unavailable","uninstantiable scene rejected")

func _test_imported_scenes() -> void:
	for height in [3,10,12,17]:
		var path:="res://assets/v3/root_buttress/root_buttress_h%d.glb"%height
		var orphan_before:=int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT))
		var first: Dictionary=Geometry.signature(path)
		var second: Dictionary=Geometry.signature(path)
		imported[path]=first
		_check(first.ok and first.mesh_count>0 and first.triangle_count>0,"real imported height "+str(height)+" has actual geometry")
		_check(first==second,"real imported height "+str(height)+" repeats without instance-ID instability")
		_check(int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT))==orphan_before,"real imported height "+str(height)+" leaves no orphan instances")
		var packed: PackedScene=ResourceLoader.load(path,"PackedScene",ResourceLoader.CACHE_MODE_IGNORE_DEEP)
		var root: Node=packed.instantiate()
		var transform_before: Transform3D=root.transform
		var direct: Dictionary=Geometry.signature_node(root)
		_check(direct==first and not root.is_inside_tree() and root.transform==transform_before,"caller-owned real imported height "+str(height)+" matches remapped scene signature unchanged")
		root.position.y+=.01
		_check(Geometry.signature_node(root).sha256!=first.sha256,"real imported root transform change detected for height "+str(height))
		root.free()
		_check(Geometry.signature(path)==first,"temporary edited instance cannot mutate reloaded height "+str(height))

