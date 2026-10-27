extends Node3D
## Small additive authoring nodes. Original Rules/physics own all interactions.
const Catalog = preload("res://scripts/v3/content/dev88_story/twin_side_story_catalog.gd")
const NAME := "SideStoryContent88"
var _world: Node3D
var _devices: Dictionary = {}
var _labels: Array = []
var _materials: Dictionary = {}

static func install(world: Node3D) -> Dictionary:
	if not is_instance_valid(world): return {"ok":false,"code":"story_world_missing"}
	var previous: Node = world.get_node_or_null(NAME)
	if is_instance_valid(previous): return {"ok":true,"root":previous}
	var root = new()
	root.name = NAME
	world.add_child(root)
	root._build(world)
	return {"ok":true,"root":root,"code":"developed_not_playtested"}

func _build(world: Node3D) -> void:
	_world = world
	var region: String = str(world.region_id)
	var fantasy: bool = region.begins_with("F")
	var tone := Color("779b89") if fantasy else Color("7e979e")
	for job: Dictionary in Catalog.definitions(region):
		for pad: Dictionary in job.get("pads",[]): _pad(Catalog.vector(pad.position),Catalog.vector(pad.size),tone.darkened(.25))
		var contact_at: Vector3 = Catalog.vector(job.contact.position)
		_pad(contact_at-Vector3(0,2.2,0),Vector3(2.8,.35,2.8),tone.darkened(.3))
		# Characters/radio stations are supplied once by Root's shared NPC
		# presentation for Catalog.markers(); do not put duplicate people here.
		for spec: Dictionary in job.get("entities",[]):
			var id: String = str(spec.id)
			if world.objects.has(id): continue
			world._entity(id.trim_prefix(region+":"),str(spec.name),Catalog.vector(spec.position),Catalog.vector(spec.size),
				spec.tags.duplicate(),spec.properties.duplicate(true),tone,bool(spec.get("dynamic",false)))
			var body: Node3D = world.objects[id]
			body.set_meta("side_story88",true)
			if body is RigidBody3D:
				body.mass = float(spec.get("mass",1.4))
				body.lock_rotation = true
				body.linear_damp = 1.4
				body.continuous_cd = true
			var cap := MeshInstance3D.new()
			cap.name = "StoryStatus88"
			var sphere := SphereMesh.new()
			sphere.radius = .18
			sphere.height = .36
			sphere.radial_segments = 10
			sphere.rings = 5
			cap.mesh = sphere
			cap.position.y = .7
			cap.material_override = _material("pending",Color("bca56d"),true)
			body.add_child(cap)
			var foliage: MeshInstance3D
			if "growable" in spec.tags:
				foliage = MeshInstance3D.new()
				var leaves := PrismMesh.new()
				leaves.size = Vector3(1.4,1.8,1.4)
				foliage.mesh = leaves
				foliage.position.y = 1.0
				foliage.material_override = _material("leaves",Color("75a888"))
				body.add_child(foliage)
			var readout: Label3D = _label(str(spec.name),Catalog.vector(spec.position)+Vector3(0,1.7,0),18)
			_devices[id] = {"cap":cap,"leaves":foliage,"readout":readout,"name":str(spec.name)}
		var ring_index := 0
		for stage: Dictionary in job.stages:
			if stage.type == "route":
				for index: int in stage.points.size():
					ring_index += 1
					_ring(Catalog.vector(stage.points[index]),float(stage.radius),tone.lightened(.12))
					_label(str(job.title)+" · 航点"+str(index+1),Catalog.vector(stage.points[index])+Vector3(0,2.8,0),15)
			elif stage.type == "dock":
				_ring(Catalog.vector(stage.position),float(stage.radius),Color("bdc49a"),-.4)
				_label("实体接收圈 · 低速归位",Catalog.vector(stage.position)+Vector3(0,2.6,0),17)

func apply_view(entities: Dictionary) -> void:
	for id: String in _devices:
		if not entities.has(id): continue
		var state: Dictionary = entities[id]
		var view: Dictionary = _devices[id]
		var pieces := PackedStringArray()
		var tags: Array = state.get("tags",[])
		if "thermal" in tags: pieces.append("温度 %.0f°" % float(state.get("temperature",20)))
		if "conductive" in tags: pieces.append("电荷 %.0f" % float(state.get("charge",0)))
		if "photosensitive" in tags: pieces.append("灯面已亮" if float(state.get("light_level",0)) >= .5 else "灯面待照")
		if "growable" in tags: pieces.append("生长 %.0f%%" % (float(state.get("growth",0))*100))
		if "echo_operable" in tags: pieces.append("回声保持" if bool(state.get("operated",false)) else "回声未保持")
		if "hackable" in tags: pieces.append("本轮已接管" if bool(state.get("controlled",false)) else "等待接管")
		var active: bool = bool(state.get("operated",false)) or bool(state.get("controlled",false)) or float(state.get("charge",0)) >= 70 or float(state.get("light_level",0)) >= .5 or float(state.get("growth",0)) >= .7
		view.cap.material_override = _material("ready",Color("83c4b2"),true) if active else _material("pending",Color("bca56d"),true)
		view.readout.text = str(view.name)+"\n"+" · ".join(pieces)
		if is_instance_valid(view.leaves): view.leaves.scale = Vector3.ONE * (.2+float(state.get("growth",0))*.8)
		var body: Variant = _world.objects.get(id)
		if is_instance_valid(body): view.readout.global_position = body.global_position+Vector3(0,1.7,0)

func set_focus(at: Vector3) -> void:
	for label: Label3D in _labels: label.visible = label.global_position.distance_to(at) < 18.0

func _pad(at: Vector3, size: Vector3, tone: Color) -> void:
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	body.position = at
	body.set_meta("side_story88",true)
	add_child(body)
	var collision := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	collision.shape = box
	body.add_child(collision)
	var view := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	view.mesh = mesh
	view.material_override = _material(tone.to_html(),tone)
	body.add_child(view)

func _ring(at: Vector3, radius: float, tone: Color, marker_y := -.8) -> void:
	var root := Node3D.new()
	root.position = at
	root.set_meta("navigation_only",true)
	add_child(root)
	# Flight and receiving rings are visible, non-colliding guidance only.
	for index: int in 12:
		var angle: float = TAU*float(index)/12.0
		var marker := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(.16,.10,.52)
		marker.mesh = box
		marker.position = Vector3(cos(angle)*radius,marker_y,sin(angle)*radius)
		marker.rotation.y = -angle
		marker.material_override = _material("route_"+tone.to_html(),tone,true)
		marker.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(marker)

func _label(text: String, at: Vector3, font_size: int) -> Label3D:
	var label := Label3D.new()
	label.text = text
	label.font = load("res://assets/fonts/NotoSansSC-Medium.ttf")
	label.font_size = font_size
	label.pixel_size = .017
	label.outline_size = 4
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.modulate = Color("cce0d5")
	label.position = at
	label.visible = false
	add_child(label)
	_labels.append(label)
	return label

func _material(id: String, tone: Color, unshaded := false) -> StandardMaterial3D:
	if not _materials.has(id):
		var material := StandardMaterial3D.new()
		material.albedo_color = tone
		material.roughness = .82
		if unshaded: material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_materials[id] = material
	return _materials[id]
