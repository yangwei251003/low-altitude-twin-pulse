class_name TwinCampaignSetDressing
extends RefCounted
## One low-cost use/readability pass. Existing collision/targets never change.
## Relief stays on supported surfaces; tall scenery is beyond playable Z=40.
const NODE_NAME := "CampaignUseDressing"
const MAX_COMPONENTS := 50

static func install(world: Node3D) -> Dictionary:
	if not is_instance_valid(world): return {"ok":false,"code":"world_missing"}
	var region: String = str(world.region_id)
	if region not in ["F2","I3","F3","I4","F4"]: return {"ok":true,"code":"no_dressing_for_region","components":0}
	var existing: Node = world.get_node_or_null(NODE_NAME)
	if is_instance_valid(existing): return {"ok":true,"code":"already_installed","root":existing,"components":int(existing.get_meta("components",0))}
	var entries: Array = []
	match region:
		"F2": _mirror_garden(entries)
		"I3": _heat_factory(entries)
		"F3": _fungus_corridor(entries)
		"I4": _offshore_array(entries)
		"F4": _shared_vein(entries)
	if entries.size() > MAX_COMPONENTS: return {"ok":false,"code":"visual_component_budget_exceeded","components":entries.size()}
	var root := Node3D.new()
	root.name = NODE_NAME
	root.set_meta("visual_only",true)
	root.set_meta("components",entries.size())
	world.add_child(root)
	var palette: Dictionary = _palette(region)
	var materials: Dictionary = {}
	var meshes: Dictionary = {}
	var groups: Dictionary = {}
	for item: Dictionary in entries:
		var key: String = str(item.shape)+":"+str(item.tone)
		if not groups.has(key): groups[key] = []
		groups[key].append(item)
		if not meshes.has(str(item.shape)): meshes[str(item.shape)] = _mesh(str(item.shape))
		if not materials.has(str(item.tone)):
			var material := StandardMaterial3D.new()
			material.albedo_color = Color(str(palette.get(str(item.tone),"82958a")))
			material.roughness = .88
			material.metallic = .32 if item.tone in ["metal","mirror"] else 0.0
			if item.tone == "glow":
				material.emission_enabled = true
				material.emission = material.albedo_color
				material.emission_energy_multiplier = .16
			materials[str(item.tone)] = material
	var batch_count := 0
	for key: String in groups:
		var first: Dictionary = groups[key][0]
		var multimesh := MultiMesh.new()
		multimesh.transform_format = MultiMesh.TRANSFORM_3D
		multimesh.mesh = meshes[str(first.shape)]
		multimesh.instance_count = groups[key].size()
		for index in range(groups[key].size()):
			var item: Dictionary = groups[key][index]
			var basis: Basis = item.basis if item.has("basis") else Basis.from_euler(item.rotation)
			multimesh.set_instance_transform(index,Transform3D(basis*Basis.from_scale(item.size),item.position))
		var batch := MultiMeshInstance3D.new()
		batch.name = key.replace(":","_")
		batch.multimesh = multimesh
		batch.material_override = materials[str(first.tone)]
		batch.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(batch)
		batch_count += 1
	var surfaces: int = _surface_treatment(world,region)
	return {"ok":true,"code":"use_dressing_installed","root":root,"region":region,
		"components":entries.size(),"batches":batch_count,"shared_materials":materials.size()+2,
		"treated_existing_surfaces":surfaces,"collision_nodes_added":0,"live_lights_added":0}

static func _add(items: Array, shape: String, tone: String, at: Vector3, size: Vector3, rotation := Vector3.ZERO) -> void:
	items.append({"shape":shape,"tone":tone,"position":at,"size":size,"rotation":rotation})

static func _pipe(items: Array, tone: String, from: Vector3, to: Vector3, diameter: float) -> void:
	var delta: Vector3 = to-from
	if delta.length() < .001: return
	items.append({"shape":"cylinder","tone":tone,"position":(from+to)*.5,
		"size":Vector3(diameter,delta.length(),diameter),"basis":Basis(Quaternion(Vector3.UP,delta.normalized()))})

static func _mirror_garden(items: Array) -> void:
	# Flat reflective mosaic on the real south landing; never a new bridge.
	for row in range(2):
		for column in range(4):
			_add(items,"box","mirror",Vector3(-28.2+column*2.7,2.025,28.4+row*5.1),Vector3(1.35,.025,1.35),Vector3(0,PI/4.0,0))
	for column in range(3):
		_add(items,"box","edge",Vector3(-27.4+column*3.4,1.05,35.985),Vector3(2.8,1.55,.035))
	# A mirror-court remnant and lake strip are wholly beyond playable Z=40.
	for x in [-29.0,-23.0]:
		_add(items,"column","stone",Vector3(x,3.5,43),Vector3(.8,7,.8))
	_add(items,"box","edge",Vector3(-26,7.1,43),Vector3(6.6,.5,.8))
	for x in [-27.8,-24.2]:
		_add(items,"box","mirror",Vector3(x,4.3,43),Vector3(1.5,3.6,.08),Vector3(0,0,.12 if x < -26 else -.12))
	_add(items,"ring","edge",Vector3(-26,4.4,43.15),Vector3(5.0,.13,5.0),Vector3(PI/2.0,0,0))
	for index in range(8):
		_add(items,"box","mirror",Vector3(-33.8,2.52,-14.0+index*4.6),Vector3(.5,.025,1.6))
	for x in [-24.0,-20.0]:
		for z in [18.0,22.0]:
			_add(items,"box","edge",Vector3(x,7.225,z),Vector3(1.2,.025,.25),Vector3(0,PI/4.0,0))
	for x in [-32.0,-20.0]:
		_add(items,"box","water",Vector3(x,.02,44),Vector3(10,.025,3.5))
	for x in [-28.0,-26.0,-24.0]:
		_add(items,"cone","stone",Vector3(x,.55,43),Vector3(1.5,1.1,1.4))

static func _heat_factory(items: Array) -> void:
	for index in range(7):
		_add(items,"box","metal",Vector3(-28.4+index*1.45,2.025,31),Vector3(.14,.025,7.6))
	for z in [27.1,34.9]:
		_pipe(items,"copper",Vector3(-29.0,2.015,z),Vector3(-19.0,2.015,z),.1)
	for x in [-33.5,-32.0,-30.5]:
		_pipe(items,"metal",Vector3(x,2.485,-15),Vector3(x,2.485,20),.085)
	# Heat exchangers/headers make an industrial silhouette behind the boundary.
	for x in [-29.0,-23.0]:
		_add(items,"cylinder","metal",Vector3(x,3.5,43),Vector3(2.6,7,2.6))
		_add(items,"cone","copper",Vector3(x,7.45,43),Vector3(2.65,.9,2.65))
		for y in [1.0,6.4]:
			_add(items,"ring","edge",Vector3(x,y,43),Vector3(2.9,.18,2.9))
		_add(items,"cylinder","edge",Vector3(x,.35,43),Vector3(3.0,.7,3.0))
	for y in [1.8,3.2,4.6]:
		_pipe(items,"copper",Vector3(-29,y,43),Vector3(-23,y,43),.32)
	for x in [-29.0,-23.0]:
		_add(items,"box","warning",Vector3(x,4.8,41.62),Vector3(.8,.45,.04))
	for x in [-24.0,-20.0]:
		for z in [18.0,22.0]:
			_add(items,"box","metal",Vector3(x,3.225,z),Vector3(1.4,.025,.18))
	for index in range(5):
		_add(items,"box","warning",Vector3(-28.5+index*2.1,1.0,35.99),Vector3(.75,1.2,.03),Vector3(0,0,-.3))

static func _fungus_corridor(items: Array) -> void:
	# Lichen stains and nutrient channels are flush with already solid surfaces.
	for index in range(6):
		_add(items,"cap","moss",Vector3(-28.3+index*1.7,2.03,34.6),Vector3(.95,.045,1.15))
	for index in range(3):
		var x: float = -30.0+index*4.0
		var height: float = 3.5+float(index%2)*1.7
		_add(items,"cylinder","root",Vector3(x,height*.5,43),Vector3(.65,height,.65))
		_add(items,"cap","moss",Vector3(x,height+.45,43),Vector3(3.2,.9,2.8))
		_add(items,"ring","glow",Vector3(x,height+.08,43),Vector3(2.6,.08,2.3))
	for index in range(4):
		_pipe(items,"root",Vector3(-28+index*2.4,2.015,27),Vector3(-26+index*1.6,2.015,34.6),.07)
	for index in range(6):
		_add(items,"box","glow",Vector3(-32.0,2.515,-14+index*6.0),Vector3(.12,.025,3.1),Vector3(0,.16 if index%2 else -.16,0))
	for index in range(6):
		_add(items,"box","root",Vector3(-26.5+index,3.8,22.99),Vector3(.12,.55,.035),Vector3(0,0,.3 if index%2 else -.3))
	for index in range(6):
		_add(items,"cap","moss",Vector3(-31.5+index*2.2,.22,43.6),Vector3(1.3,.45,1.1))

static func _offshore_array(items: Array) -> void:
	for index in range(6):
		_add(items,"box","metal",Vector3(-28.3+index*1.7,2.025,31),Vector3(.08,.025,7.4))
	for x in [-28.7,-24.0,-19.3]:
		_add(items,"box","edge",Vector3(x,2.028,28.0),Vector3(1.1,.025,1.4))
	for z in [27.0,35.0]:
		_add(items,"box","warning",Vector3(-24,2.03,z),Vector3(8.5,.025,.14))
	for index in range(2):
		var x: float = -29.0+index*6.0
		_add(items,"column","metal",Vector3(x,3.0,43),Vector3(.45,6,.45))
		_pipe(items,"edge",Vector3(x,3.4,43),Vector3(x-1.0,5.8,43),.18)
		_pipe(items,"edge",Vector3(x,3.4,43),Vector3(x+1.0,5.8,43),.18)
		_add(items,"ring","metal",Vector3(x,6.0,43),Vector3(3.2,.16,3.2),Vector3(PI/2.0,.12,0))
		_pipe(items,"copper",Vector3(x,6.0,42.85),Vector3(x,6.0,41.7),.12)
		_add(items,"cone","warning",Vector3(x,7.9,43),Vector3(.4,.5,.4))
	for index in range(6):
		_add(items,"cylinder","ceramic",Vector3(-28.3+index*1.7,2.04,34.9),Vector3(.45,.06,.45))
	for x in [-33.5,-32.5,-31.5,-30.5]:
		_add(items,"box","metal",Vector3(x,2.515,2),Vector3(.11,.025,37))
	for x in [-26.0,-22.0]:
		for z in [18.0,22.0]:
			_add(items,"box","warning",Vector3(x,5.225,z),Vector3(1.0,.025,.12))
	for index in range(3):
		_add(items,"box","glow",Vector3(-28.0+index*2.5,1.1,41.55),Vector3(.12,.35,.08))

static func _shared_vein(items: Array) -> void:
	for index in range(4):
		_add(items,"box","metal",Vector3(-28.4+index*1.2,2.025,31),Vector3(.12,.025,7.5))
		_pipe(items,"root",Vector3(-23.5+index*1.2,2.02,27.3),Vector3(-22.0+index*.8,2.02,34.7),.07)
	_add(items,"ring","edge",Vector3(-24,2.028,31),Vector3(4.3,.035,4.3))
	# Industrial and living service monuments share a visible junction, all
	# outside the map. The thin connection is a cable, not a walkable bridge.
	_add(items,"box","metal",Vector3(-29,3.3,43),Vector3(1.5,6.6,1.2))
	_add(items,"box","ceramic",Vector3(-29,6.7,43),Vector3(1.7,.5,1.4))
	for y in [1.2,3.2,5.2]:
		_add(items,"ring","edge",Vector3(-29,y,43),Vector3(1.8,.13,1.5))
	_add(items,"column","root",Vector3(-22.5,3.1,43),Vector3(1.0,6.2,1.0))
	for index in range(3):
		_pipe(items,"root",Vector3(-22.5,2.5+index,43),Vector3(-24.0+index*1.5,5.0+index*.4,43),.28)
	_add(items,"cone","moss",Vector3(-22.5,6.7,43),Vector3(3.3,1.2,1.3))
	_add(items,"ring","glow",Vector3(-22.5,5.8,43),Vector3(1.6,.1,1.4))
	for y in [3.3,4.1]:
		_pipe(items,"glow",Vector3(-28.2,y,43),Vector3(-23.2,y,43),.09)
	for index in range(6):
		_add(items,"box","edge",Vector3(-28.5+index*1.8,1.0,35.99),Vector3(1.1,1.45,.035))
	for index in range(6):
		_add(items,"box","metal" if index%2 else "root",Vector3(-32.0,2.518,-14+index*6.0),Vector3(.15,.025,3.9),Vector3(0,.2 if index%2 else -.2,0))
	for z in [-16.0,19.0]:
		_add(items,"ring","edge",Vector3(-32.0,2.52,z),Vector3(1.4,.035,1.4))
	for x in [-26.0,-22.0]:
		for z in [18.0,22.0]:
			_add(items,"box","metal" if x < -24 else "root",Vector3(x,7.225,z),Vector3(1.2,.025,.16),Vector3(0,PI/4.0,0))
	for x in [-28.0,-24.0]:
		_add(items,"box","glow",Vector3(x,.15,42.0),Vector3(.9,.1,.35))

static func _surface_treatment(world: Node3D, region: String) -> int:
	var root: Node3D = world.get_node_or_null("CampaignLayout"+region)
	if not is_instance_valid(root): return 0
	var palette: Dictionary = _palette(region)
	var ground := StandardMaterial3D.new()
	ground.albedo_color = Color(str(palette.ground))
	ground.roughness = .98
	var floor := StandardMaterial3D.new()
	floor.albedo_texture = _surface_texture(region,palette)
	floor.roughness = .9
	floor.uv1_scale = Vector3(5,5,5)
	floor.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	var changed := 0
	for body: Node in root.get_children():
		for child: Node in body.get_children():
			if child is MeshInstance3D:
				child.material_override = ground if str(body.name) == "Ground" else floor
				changed += 1
	return changed

static func _surface_texture(region: String, palette: Dictionary) -> ImageTexture:
	var canvas := Image.create(32,32,false,Image.FORMAT_RGB8)
	var base := Color(str(palette.stone))
	var seam := Color(str(palette.ground))
	var detail := Color(str(palette.edge))
	for y in range(32):
		for x in range(32):
			var color: Color = base
			match region:
				"F2":
					if x%16 == 0 or y%16 == 0: color = seam
					if absi(x-16)+absi(y-16) in [12,13]: color = detail
				"I3":
					if x%8 in [0,1] or y%16 == 0: color = seam
					if y > 27 and (x+y)%8 < 4: color = detail
				"F3":
					if (x*7+y*11)%23 < 3: color = seam
					if (x-y+32)%16 in [0,1]: color = detail
				"I4":
					if y%16 in [0,1] or (x+(16 if y < 16 else 0))%32 < 2: color = seam
					if x > 27 and (x+y)%10 < 3: color = detail
				"F4":
					color = base if x < 16 else Color(str(palette.moss))
					if x in [15,16] or y%16 == 0: color = detail
			canvas.set_pixel(x,y,color)
	return ImageTexture.create_from_image(canvas)

static func _mesh(shape: String) -> Mesh:
	if shape == "box":
		var box := BoxMesh.new()
		box.size = Vector3.ONE
		return box
	if shape == "ring":
		var ring := TorusMesh.new()
		ring.inner_radius = .41
		ring.outer_radius = .5
		ring.rings = 12
		ring.ring_segments = 4
		return ring
	var cylinder := CylinderMesh.new()
	cylinder.height = 1.0
	cylinder.radial_segments = 8
	cylinder.rings = 0
	cylinder.top_radius = .08 if shape == "cone" else (.5 if shape == "cap" else .5)
	cylinder.bottom_radius = .16 if shape == "cap" else (.35 if shape == "column" else .5)
	return cylinder

static func _palette(region: String) -> Dictionary:
	var themes := {
		"F2":{"ground":"28464c","stone":"748a83","edge":"b0b18c","metal":"778b92","mirror":"b7d0ca","water":"275769","moss":"4c7464","root":"77764f","glow":"86a795","copper":"a09367","warning":"aeaa7d","ceramic":"a6bbb1"},
		"I3":{"ground":"303e42","stone":"667273","edge":"7e8e91","metal":"465b63","mirror":"97aeb0","water":"2e535b","moss":"617168","root":"81704c","glow":"9bb3a7","copper":"986e46","warning":"b6a36b","ceramic":"bcc4bd"},
		"F3":{"ground":"283d35","stone":"607353","edge":"82936b","metal":"61756d","mirror":"a4bfa3","water":"31564d","moss":"7a8961","root":"756344","glow":"89bba2","copper":"958464","warning":"a8a071","ceramic":"a8bba1"},
		"I4":{"ground":"293c47","stone":"647d85","edge":"95a9a7","metal":"435b6a","mirror":"a6c2c6","water":"244b5c","moss":"5f766e","root":"7e7861","glow":"7aa9ae","copper":"a18b5b","warning":"c0b383","ceramic":"c1c7b5"},
		"F4":{"ground":"30443c","stone":"758a8b","edge":"a99b72","metal":"5b7b83","mirror":"bdd0bd","water":"315d63","moss":"6b8053","root":"7a6d4a","glow":"9ebca2","copper":"9b865a","warning":"b8ac7c","ceramic":"b8c8bb"}
	}
	return themes[region].duplicate(true)
