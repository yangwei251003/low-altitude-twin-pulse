class_name StreetDressingV2
extends RefCounted

const V = preload("res://scripts/visuals.gd")
static var surface_cache: Dictionary = {}
static var model_cache: Dictionary = {}
static var color_materials: Dictionary = {}

static func surface(kind: int, color: Color) -> ShaderMaterial:
	var key = str(kind)+str(color)
	if not surface_cache.has(key):
		var material = ShaderMaterial.new()
		material.shader = preload("res://assets/v2/ground.gdshader")
		material.set_shader_parameter("surface_kind",kind)
		material.set_shader_parameter("base_color",color.srgb_to_linear())
		surface_cache[key] = material
	return surface_cache[key]

static func slab(root: Node3D, pos: Vector3, size: Vector3, kind: int, color: Color) -> MeshInstance3D:
	# River-aware street dressing: keep plazas and sidewalks out of the canal.
	if bool(root.get_meta("canal_clip",false)) and absf(fposmod(pos.z+25.0,50.0)-25.0)>5.5 and pos.x-size.x/2<190 and pos.x+size.x/2>182:
		var left_edge=pos.x-size.x/2
		var right_edge=pos.x+size.x/2
		var last: MeshInstance3D
		for span in [Vector2(left_edge,minf(right_edge,182)),Vector2(maxf(left_edge,190),right_edge)]:
			if span.y<=span.x:continue
			last=V.box(root,Vector3((span.x+span.y)/2,pos.y,pos.z),Vector3(span.y-span.x,size.y,size.z),color)
			last.material_override=surface(kind,color)
			last.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		return last
	var mesh = V.box(root,pos,size,color)
	mesh.material_override = surface(kind,color)
	mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mesh

static func prop(root: Node3D, id: String, pos: Vector3, yaw = 0.0, scale_m = 1.0) -> Node3D:
	var path = "res://assets/v2/streets/"+id+".glb"
	if not ResourceLoader.exists(path): return null
	if not model_cache.has(id): model_cache[id] = load(path)
	var model: Node3D = model_cache[id].instantiate()
	_enable_vertex_colors(model)
	root.add_child(model)
	model.position = pos
	model.rotation.y = yaw
	model.scale = Vector3.ONE*scale_m
	return model

static func _enable_vertex_colors(node: Node) -> void:
	if node is MeshInstance3D:
		for index in node.mesh.get_surface_count():
			var arrays = node.mesh.surface_get_arrays(index)
			var material = node.get_active_material(index)
			if arrays[Mesh.ARRAY_COLOR] != null and not arrays[Mesh.ARRAY_COLOR].is_empty() and material is BaseMaterial3D and not material.vertex_color_use_as_albedo:
				var key = material.get_instance_id()
				if not color_materials.has(key):
					var colored = material.duplicate()
					colored.vertex_color_use_as_albedo = true
					colored.vertex_color_is_srgb = false
					color_materials[key] = colored
				node.set_surface_override_material(index,color_materials[key])
	for child in node.get_children(): _enable_vertex_colors(child)

static func lines(root: Node3D, pos: Vector3, size: Vector3, color = Color("e9e6ce")) -> void:
	V.box(root,pos,size,color).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

static func build(root: Node3D, cell: Vector2i, world: Node3D) -> void:
	var origin = Vector3(cell.x*100,0,cell.y*100)
	var region_id = str(world.region.id)
	root.set_meta("canal_clip",region_id in ["R1","R3"] and cell.x==1)
	var pavement = Color("b0b6aa") if region_id!="R4" else Color("929c98")
	for a in range(2):
		var x = origin.x+a*50
		var z = origin.z+a*50
		slab(root,Vector3(x,0.015,origin.z+50),Vector3(11,0.03,100),0,Color("36474b"))
		slab(root,Vector3(origin.x+50,0.017,z),Vector3(100,0.034,11),0,Color("36474b"))
		for segment in range(2):
			var offset = segment*50.0+25.0
			for side in [-1,1]:
				slab(root,Vector3(x+side*7.1,0.10,origin.z+offset),Vector3(3,0.20,38.7),1,pavement)
				slab(root,Vector3(origin.x+offset,0.10,z+side*7.1),Vector3(38.7,0.20,3),1,pavement)
				lines(root,Vector3(x+side*5.55,0.13,origin.z+offset),Vector3(0.2,0.26,38.7),Color("d5d6c8"))
				lines(root,Vector3(origin.x+offset,0.13,z+side*5.55),Vector3(38.7,0.26,0.2),Color("d5d6c8"))
				lines(root,Vector3(x+side*4.8,0.045,origin.z+offset),Vector3(0.11,0.02,37),Color("c3c8bc"))
				lines(root,Vector3(origin.x+offset,0.045,z+side*4.8),Vector3(37,0.02,0.11),Color("c3c8bc"))
			for dash in range(5):
				lines(root,Vector3(x,0.048,origin.z+segment*50+14+dash*6),Vector3(0.13,0.02,3),Color("d9bd72"))
				lines(root,Vector3(origin.x+segment*50+14+dash*6,0.048,z),Vector3(3,0.02,0.13),Color("d9bd72"))
			# Crosswalks stop before the curved corner; all four approaches are visible.
			for bar in range(7):
				for edge in [-1,1]:
					lines(root,Vector3(x-4.2+bar*1.4,0.052,origin.z+segment*50+edge*8.0),Vector3(0.7,0.025,3.2))
					lines(root,Vector3(origin.x+segment*50+edge*8.0,0.054,z-4.2+bar*1.4),Vector3(3.2,0.025,0.7))
			for side in [-1,1]:
				prop(root,"street_lamp",Vector3(x+side*7.5,0.2,origin.z+segment*50+15),0 if side==1 else PI)
				prop(root,"traffic_light",Vector3(x+side*7.2,0.2,origin.z+segment*50+side*7.2),0 if side==1 else PI)
				# Parked vehicles sit outside the through lanes.
				var parking = Vector3(x+side*11.5,0.05,origin.z+segment*50+30)
				if world.decoration_clear(parking,3.6):
					slab(root,parking,Vector3(4.2,0.05,10),0,Color("596569"))
					for mark in [-1,0,1]: lines(root,parking+Vector3(0,0.04,mark*4.6),Vector3(4.1,0.02,0.10))
					var vehicle = prop(root,["car_sedan","car_suv","car_delivery"][(cell.x+cell.y+segment+a)%3],parking+Vector3(0,0.02,0),0 if side>0 else PI)
					if vehicle != null: V.collider(root,parking+Vector3.UP*0.65,Vector3(1.8,1.3,4.1))
			# Utilities and shelter are placed away from the working pad.
			var stop = Vector3(x+10,0.2,origin.z+segment*50+17)
			if world.decoration_clear(stop,4.0):
				var shelter = Node3D.new()
				root.get_parent().add_child(shelter)
				shelter.position = stop
				prop(shelter,"bus_stop",Vector3.ZERO,PI/2)
				world._register_occluder(shelter)
				prop(root,"recycling_bins",stop+Vector3(0,0,4.5))
				prop(root,"wayfinding_sign",stop+Vector3(-2.5,0,-3.5))
			for b in range(2):
				var garden = origin+Vector3(a*50+13+b*24,0,segment*50+39)
				if world.decoration_clear(garden,3.5):
					prop(root,"planter",garden)
					var tree = prop(root,["street_tree","street_tree_round","street_tree_slender"][(cell.x+cell.y+a+b)%3],garden+Vector3.UP*0.45,0,0.95)
					if tree != null:
						world._set_lod(tree,140)
						register_tree_outline(root,tree,world)
					V.collider(root,garden+Vector3.UP*1.1,Vector3(0.35,2.2,0.35))
			var seat = origin+Vector3(a*50+17,0.02,segment*50+12)
			if world.decoration_clear(seat,2):
				prop(root,"bench",seat)
				prop(root,"bicycle_rack",seat+Vector3(5,0,0))
				prop(root,"utility_cabinet",seat+Vector3(-4,0,0))
	# Flower beds and tiled walkways give the spaces between roads a readable purpose.
	for a in range(2):
		for b in range(2):
			var plaza = origin+Vector3(25+a*50,0.025,25+b*50)
			slab(root,plaza,Vector3(25,0.05,23),1,pavement.darkened(0.05))
			for offset in [Vector3(11,0,10),Vector3(-11,0,-10)]:
				var p = plaza+offset
				if not world.decoration_clear(p,2): continue
				prop(root,"planter",p)
				V.asset(root,"garden_hedge",p+Vector3.UP*0.2,0.7)
	batch(root)

static func register_tree_outline(dressing: Node3D, tree: Node3D, world: Node3D) -> Node3D:
	var boxes: Array[AABB] = []
	_collect_outline_bounds(tree,tree.transform.affine_inverse(),boxes)
	if boxes.is_empty(): return null
	var bounds = boxes[0]
	for box in boxes: bounds = bounds.merge(box)
	var proxy = Node3D.new()
	proxy.name = "TreeVisibilityProxy"
	# Keep the proxy beside StreetDressing: batch() frees source mesh nodes,
	# while chunk retirement owns and frees both dressing and its tree proxies.
	dressing.get_parent().add_child(proxy)
	proxy.global_transform = tree.global_transform
	proxy.set_meta("v2_outline_only_bounds",bounds)
	world._register_occluder(proxy)
	return proxy

static func _collect_outline_bounds(node: Node, transform: Transform3D, boxes: Array[AABB]) -> void:
	var local = transform * node.transform if node is Node3D else transform
	if node is MeshInstance3D and node.mesh != null: boxes.append(local * node.get_aabb())
	for child in node.get_children(): _collect_outline_bounds(child,local,boxes)

static var instanced_meshes: Dictionary = {}
static var unit_cube: BoxMesh

static func batch(root: Node3D) -> void:
	# Retain imported mesh LODs and cull in 25 m cells instead of unpacking
	# hundreds of copies into one 100 m mesh during flight streaming.
	var groups: Dictionary = {}
	var sources: Array[MeshInstance3D] = []
	_collect_instances(root,Transform3D.IDENTITY,groups,sources)
	for key in groups:
		var group: Dictionary = groups[key]
		var origin: Vector3 = group.transforms[0].origin
		var multi = MultiMesh.new()
		multi.transform_format=MultiMesh.TRANSFORM_3D
		multi.mesh=group.mesh
		multi.instance_count=group.transforms.size()
		for i in group.transforms.size():
			var transform: Transform3D=group.transforms[i]
			transform.origin-=origin
			multi.set_instance_transform(i,transform)
		var instance=MultiMeshInstance3D.new()
		instance.multimesh=multi
		instance.material_override=group.override
		instance.cast_shadow=group.shadow
		instance.visibility_range_end=group.distance
		instance.position=origin
		root.add_child(instance)
		instance.name="StreetInstances"
	# All transforms and resources are now retained by MultiMesh. Keep physical
	# bodies but release source visual nodes instead of accumulating hidden copies.
	for source in sources: source.free()

static func _collect_instances(node: Node, transform: Transform3D, groups: Dictionary, sources: Array[MeshInstance3D]) -> void:
	for child in node.get_children():
		var local = transform*child.transform if child is Node3D else transform
		if child is MeshInstance3D and child.visible:
			var mesh: Mesh = child.mesh
			var material: Material = child.material_override
			if mesh is BoxMesh:
				if unit_cube == null:
					unit_cube=BoxMesh.new(); unit_cube.size=Vector3.ONE
				local.basis=local.basis.scaled_local(mesh.size)
				mesh=unit_cube
			elif mesh is ArrayMesh and material==null:
				var bake_key=str(mesh.get_rid())
				for index in mesh.get_surface_count():
					var active=child.get_active_material(index)
					bake_key+=str(active.get_rid() if active else 0)
				if not instanced_meshes.has(bake_key):
					var baked: ArrayMesh=mesh.duplicate()
					for index in mesh.get_surface_count(): baked.surface_set_material(index,child.get_active_material(index))
					instanced_meshes[bake_key]=baked
				mesh=instanced_meshes[bake_key]
			var cell=Vector2i(floori(local.origin.x/25),floori(local.origin.z/25))
			var key=str(mesh.get_rid())+str(material.get_rid() if material else 0)+str(child.cast_shadow)+str(cell)+str(child.visibility_range_end)
			if not groups.has(key): groups[key]={"mesh":mesh,"override":material,"shadow":child.cast_shadow,"distance":child.visibility_range_end,"transforms":[]}
			groups[key].transforms.append(local)
			sources.append(child)
		_collect_instances(child,local,groups,sources)
