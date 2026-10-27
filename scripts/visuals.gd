class_name GameVisuals
extends RefCounted

static var mats: Dictionary = {}
static var models: Dictionary = {}
static var surfaces: Dictionary = {}
static var primitives: Dictionary = {}

static func surface(kind: String) -> StandardMaterial3D:
	if surfaces.has(kind): return surfaces[kind]
	var mat=StandardMaterial3D.new()
	if kind in ["paving","lawn"]:
		mat.albedo_color=Color("b9bcad") if kind=="paving" else Color("63754b");mat.roughness=.88
		surfaces[kind]=mat
		return mat
	var asset="aerial_grass_rock" if kind=="grass" else ("rock_boulder_dry" if kind=="rock" else "sandstone_blocks_04")
	var folder="res://assets/textures/"+asset+"/"
	# Imported textures are remapped inside the executable. Directory enumeration
	# does not preserve the source JPG names in a release PCK; use explicit paths.
	mat.albedo_texture=load(folder+asset+"_diff_1k.jpg")
	mat.normal_enabled=true
	mat.normal_texture=load(folder+asset+"_nor_gl_1k.jpg")
	mat.normal_scale=.65
	mat.roughness_texture=load(folder+asset+"_rough_1k.jpg")
	mat.uv1_triplanar=true
	mat.uv1_world_triplanar=true
	mat.uv1_scale=Vector3.ONE*(.22 if kind=="stone" else .32)
	mat.albedo_color=Color("b8c7a2") if kind=="grass" else (Color("a3b9ce") if kind=="stone" else Color("c9c7b9"))
	mat.roughness=.86
	surfaces[kind]=mat
	return mat

static func decorate_materials(node: Node) -> void:
	if node is MeshInstance3D:
		for i in range(node.mesh.get_surface_count()):
			var mat=node.get_active_material(i)
			if mat and ("Limestone face" in mat.resource_name or "Warm limestone" in mat.resource_name):
				node.set_surface_override_material(i,surface("stone"))
	for child in node.get_children():decorate_materials(child)

static func material(color: Color, glow: float = 0.0) -> StandardMaterial3D:
	var key = str(color) + str(glow)
	if mats.has(key): return mats[key]
	var mat = StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 0.6
	if color.a < 1.0:
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	if glow > 0:
		mat.emission_enabled = true
		mat.emission = color
		mat.emission_energy_multiplier = glow
	mats[key] = mat
	return mat

static func box(parent: Node3D, position: Vector3, size: Vector3, color: Color) -> MeshInstance3D:
	var obj = MeshInstance3D.new()
	var key=str(size)
	if not primitives.has(key):
		var created=BoxMesh.new();created.size=size;primitives[key]=created
	var mesh=primitives[key]
	obj.mesh = mesh
	obj.material_override = material(color)
	parent.add_child(obj)
	obj.position = position
	return obj

static func sphere(parent: Node3D, position: Vector3, radius: float, color: Color) -> MeshInstance3D:
	var obj = MeshInstance3D.new()
	var mesh = SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius * 2
	mesh.radial_segments = 16
	mesh.rings = 8
	obj.mesh = mesh
	obj.material_override = material(color, 0.2)
	parent.add_child(obj)
	obj.position = position
	return obj

static func cylinder(parent: Node3D, position: Vector3, radius: float, height: float, color: Color) -> MeshInstance3D:
	var obj = MeshInstance3D.new()
	var mesh = CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = height
	mesh.radial_segments = 32
	obj.mesh = mesh
	obj.material_override = material(color)
	parent.add_child(obj)
	obj.position = position
	return obj

static func ring(parent: Node3D, position: Vector3, radius: float, color: Color, width: float = 0.055) -> MeshInstance3D:
	var obj = MeshInstance3D.new()
	var mesh = TorusMesh.new()
	mesh.inner_radius = radius - width
	mesh.outer_radius = radius + width
	mesh.rings = 48
	mesh.ring_segments = 6
	obj.mesh = mesh
	obj.material_override = material(color, 0.5)
	obj.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(obj)
	obj.position = position
	return obj

static func asset(parent: Node3D, id: String, pos: Vector3 = Vector3.ZERO, scale_factor: float = 1.0) -> Node3D:
	var path = "res://assets/models/" + id + ".glb"
	var obj: Node3D
	if ResourceLoader.exists(path):
		if not models.has(id): models[id] = load(path)
		obj = models[id].instantiate()
		decorate_materials(obj)
		if id=="rock_large":override_all(obj,surface("rock"))
	else:
		obj = Node3D.new()
		box(obj, Vector3.ZERO, Vector3.ONE, Color("aaaaaa"))
	parent.add_child(obj)
	obj.position = pos
	obj.scale = Vector3.ONE * scale_factor
	return obj

static func override_all(node: Node,mat: Material) -> void:
	if node is MeshInstance3D:node.material_override=mat
	for child in node.get_children():override_all(child,mat)

static func batch_static(root: Node3D) -> void:
	var groups={}
	_collect_static(root,groups)
	for key in groups:
		var items: Array=groups[key]
		if items.size()<3:continue
		var first: MeshInstance3D=items[0]
		var multi=MultiMesh.new()
		multi.transform_format=MultiMesh.TRANSFORM_3D
		multi.mesh=first.mesh
		multi.instance_count=items.size()
		var instance=MultiMeshInstance3D.new()
		instance.multimesh=multi
		instance.material_override=first.material_override
		instance.cast_shadow=first.cast_shadow
		root.add_child(instance)
		for i in range(items.size()):
			multi.set_instance_transform(i,root.global_transform.affine_inverse()*items[i].global_transform)
			items[i].visible=false
	# Merge the remaining small pieces by material and sector. This preserves
	# camera culling while avoiding a draw call for every unique wall or railing.
	var residual={}
	_collect_residual(root,residual)
	for key in residual:
		var items: Array=residual[key]
		if items.size()<2:continue
		var first: MeshInstance3D=items[0]
		var surface=SurfaceTool.new()
		surface.begin(Mesh.PRIMITIVE_TRIANGLES)
		for item in items:
			surface.append_from(item.mesh,0,root.global_transform.affine_inverse()*item.global_transform)
		var merged=MeshInstance3D.new()
		merged.mesh=surface.commit()
		merged.material_override=first.material_override
		merged.cast_shadow=first.cast_shadow
		root.add_child(merged)
		for item in items:item.visible=false

static func _collect_residual(node: Node,groups: Dictionary) -> void:
	if node is MeshInstance3D and node.visible and node.mesh and node.mesh.get_surface_count()==1:
		var mat=node.get_active_material(0)
		if mat is ShaderMaterial or (mat is StandardMaterial3D and mat.transparency!=BaseMaterial3D.TRANSPARENCY_DISABLED):return
		var arrays=node.mesh.surface_get_arrays(0)
		var layout=""
		for arr in arrays:layout+="0" if arr==null or arr.is_empty() else "1"
		var tile=Vector2i(floor(node.global_position.x/24),floor(node.global_position.z/24))
		var key=str(mat.get_rid() if mat else 0)+str(tile)+str(node.cast_shadow)+layout
		if not groups.has(key):groups[key]=[]
		groups[key].append(node)
	for child in node.get_children():_collect_residual(child,groups)

static func _collect_static(node: Node,groups: Dictionary) -> void:
	if node is MeshInstance3D and node.mesh and node.mesh.get_surface_count()==1:
		var material=node.get_active_material(0)
		# Retain per-surface remapping by baking into the instance material override.
		node.material_override=material
		var tile=Vector2i(floor(node.global_position.x/24),floor(node.global_position.z/24))
		var key=str(node.mesh.get_rid())+str(material.get_rid() if material else 0)+str(tile)+str(node.cast_shadow)
		if not groups.has(key):groups[key]=[]
		groups[key].append(node)
	for child in node.get_children():_collect_static(child,groups)

static func collider(parent: Node3D, pos: Vector3, size: Vector3, layer: int = 1) -> StaticBody3D:
	var body = StaticBody3D.new()
	body.collision_layer = layer
	body.collision_mask = 0
	var col = CollisionShape3D.new()
	var shape = BoxShape3D.new()
	shape.size = size
	col.shape = shape
	body.add_child(col)
	parent.add_child(body)
	body.position = pos
	return body

static func rotors(node: Node, delta: float) -> void:
	for child in node.get_children():
		if child is Node3D and child.name.to_lower().begins_with("rotor"):
			child.rotate_y(delta * 32.0)
		rotors(child, delta)
