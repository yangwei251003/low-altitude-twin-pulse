class_name TwinImportedGeometry
extends RefCounted
## Imported geometry evidence, available in exported PCKs through remapped scenes.
## No raw source-file reads, tree insertion, resource edits or static result cache.
## Node records are sorted by relative name path; face order is NEVER canonicalized.
## Algorithm v1 is Godot's float32 position representation on this target platform.
const ALGORITHM := "godot-imported-node-transform-mesh-faces-sha256-v1"
const MAX_NODES := 4096
const MAX_DEPTH := 128
const MAX_FACE_VERTICES := 6000000

static func signature(path: String) -> Dictionary:
	if path.is_empty() or not ResourceLoader.exists(path,"PackedScene"):
		return _failure("resource_missing")
	# Re-read the remapped scene and its dependencies; do not reuse a mutable
	# cached scene or keep our own digest after a reimport/replacement.
	var resource = ResourceLoader.load(path,"PackedScene",ResourceLoader.CACHE_MODE_IGNORE_DEEP)
	if not resource is PackedScene: return _failure("not_packed_scene")
	return _signature_packed_scene(resource)

static func _signature_packed_scene(scene: PackedScene) -> Dictionary:
	if scene==null or not scene.can_instantiate(): return _failure("scene_unavailable")
	var instance: Node = scene.instantiate()
	if instance==null: return _failure("instantiate_failed")
	# All paths, including malformed/empty meshes, pass through immediate free.
	var result := signature_node(instance)
	instance.free()
	return result

## Read-only caller-owned root. The caller remains responsible for freeing it.
## Its own local transform IS included, as are all descendant ancestors.
static func signature_node(root: Node) -> Dictionary:
	if not is_instance_valid(root): return _failure("root_missing")
	if root.is_inside_tree(): return _failure("root_must_be_off_tree")
	var context := HashingContext.new()
	if context.start(HashingContext.HASH_SHA256)!=OK: return _failure("hash_start_failed")
	_text(context,ALGORITHM)
	var state := {"mesh_count":0,"triangle_count":0,"node_count":0,"path":""}
	var error := _walk(root,Transform3D.IDENTITY,"",0,context,state)
	if not error.is_empty(): return _failure(error,state)
	if int(state.mesh_count)==0 or int(state.triangle_count)==0: return _failure("empty_geometry",state)
	_count(context,int(state.node_count))
	_count(context,int(state.mesh_count))
	_count(context,int(state.triangle_count))
	return {"ok":true,"code":"ok","algorithm":ALGORITHM,"sha256":context.finish().hex_encode(),
		"mesh_count":int(state.mesh_count),"triangle_count":int(state.triangle_count),"node_count":int(state.node_count)}

static func _walk(node: Node, parent: Transform3D, parent_path: String, depth: int, context: HashingContext, state: Dictionary) -> String:
	state.node_count=int(state.node_count)+1
	if depth>MAX_DEPTH or int(state.node_count)>MAX_NODES: return "node_budget"
	var path := parent_path+"/"+str(node.name)
	state.path=path
	var at := parent
	var top_level := false
	if node is Node3D:
		top_level=node.top_level
		at=node.transform if top_level else parent*node.transform
	if not at.is_finite(): return "nonfinite_transform"
	# Names and node class prevent ambiguous hierarchy boundaries. Length-prefixed
	# UTF-8 records do not rely on delimiter escaping or instance IDs.
	_text(context,path)
	_text(context,node.get_class())
	_count(context,1 if top_level else 0)
	var transform_bytes := PackedFloat32Array([
		at.basis.x.x,at.basis.x.y,at.basis.x.z,
		at.basis.y.x,at.basis.y.y,at.basis.y.z,
		at.basis.z.x,at.basis.z.y,at.basis.z.z,
		at.origin.x,at.origin.y,at.origin.z]).to_byte_array()
	context.update(transform_bytes)
	if node is MeshInstance3D:
		if node.mesh==null: return "missing_mesh"
		if node.mesh.get_surface_count()==0: return "empty_mesh"
		var faces: PackedVector3Array=node.mesh.get_faces()
		if faces.is_empty() or faces.size()%3!=0: return "empty_or_invalid_faces"
		if int(state.triangle_count)*3+faces.size()>MAX_FACE_VERTICES: return "geometry_budget"
		for position in faces:
			if not position.is_finite(): return "nonfinite_faces"
		_count(context,faces.size())
		# Keep the actual Mesh.get_faces() position bytes and triangle order.
		# Local vertices plus the accumulated transform encode placement without
		# a second transform/rounding pass over every vertex.
		context.update(faces.to_byte_array())
		state.mesh_count=int(state.mesh_count)+1
		state.triangle_count=int(state.triangle_count)+faces.size()/3
	else:
		_count(context,0)
	var children: Array[Node]=node.get_children(true)
	children.sort_custom(func(a: Node,b: Node)->bool:return str(a.name)<str(b.name))
	_count(context,children.size())
	for child in children:
		var error := _walk(child,at,path,depth+1,context,state)
		if not error.is_empty(): return error
	return ""

static func _text(context: HashingContext, value: String) -> void:
	var bytes := value.to_utf8_buffer()
	_count(context,bytes.size())
	context.update(bytes)

static func _count(context: HashingContext, value: int) -> void:
	var bytes := PackedByteArray()
	bytes.resize(8)
	bytes.encode_u64(0,value)
	context.update(bytes)

static func _failure(code: String, state: Dictionary = {}) -> Dictionary:
	return {"ok":false,"code":code,"algorithm":ALGORITHM,"sha256":"",
		"mesh_count":int(state.get("mesh_count",0)),"triangle_count":int(state.get("triangle_count",0)),
		"node_count":int(state.get("node_count",0)),"path":str(state.get("path",""))}

