extends Node3D
## Five additive route modules. No input, gameplay clock, AI, save mutation,
## completion event, client simulation, original collider edit or Boss edit.
## install(world) registers ability bodies through the original World._entity.
## Optional apply_view(entities) displays the same authoritative entity values.
const Catalog = preload("res://scripts/v3/content/world_content_next/twin_world_content_catalog.gd")
const Props = preload("res://scripts/v3/content/presentation_next/twin_content_prop_factory.gd")
const ROOT_NAME := "WorldContentNext"
var region_id := ""
var _spec: Dictionary = {}
var _feedback: Dictionary = {}
var _feedback_keys: Dictionary = {}
var _materials: Dictionary = {}
var _world: Node3D

static func install(world: Node3D) -> Dictionary:
	if not is_instance_valid(world): return {"ok":false, "code":"content_world_missing"}
	var region: String = str(world.region_id)
	var spec: Dictionary = Catalog.definition(region)
	if spec.is_empty(): return {"ok":true, "code":"original_region_kept", "region":region}
	var existing: Node3D = world.get_node_or_null(ROOT_NAME)
	if is_instance_valid(existing): return {"ok":true, "code":"content_already_installed", "root":existing, "region":region}
	var content = new()
	content.name = ROOT_NAME
	world.add_child(content)
	return content._build(world, spec)

func _build(world: Node3D, spec: Dictionary) -> Dictionary:
	_world = world
	_spec = spec.duplicate(true)
	region_id = str(spec.id)
	set_meta("status", "developed_not_playtested")
	set_meta("content_id", "world_content_next_20261022")
	for pad: Dictionary in spec.get("pads", []):
		_solid(str(pad.id), Catalog.vector(pad.position), Catalog.vector(pad.size), str(pad.get("tone", "stone")))
	for post: Dictionary in spec.get("supports", []):
		_solid(str(post.id), Catalog.vector(post.position), Catalog.vector(post.size), "support")
	for landmark: Dictionary in spec.get("landmarks", []):
		var prop: Node3D = Props.make(str(landmark.kind), region_id, int(landmark.get("variant", 0)))
		if not is_instance_valid(prop): continue
		prop.name = str(landmark.id)
		add_child(prop)
		prop.position = Catalog.vector(landmark.position)
		prop.rotation.y = deg_to_rad(float(landmark.get("yaw_degrees", 0.0)))
		if landmark.has("scale"): prop.scale = Vector3.ONE * float(landmark.scale)
	for route: Dictionary in spec.get("routes", []): _route(route)
	for sign: Dictionary in spec.get("signs", []):
		_label(str(sign.id), str(sign.text), Catalog.vector(sign.position), 19, Color("cbd8bd"))
	var ids: Array = []
	for entity: Dictionary in spec.get("entities", []):
		var id: String = str(entity.id)
		# An additive content module never replaces an existing body's identity.
		if world.objects.has(id): continue
		world._entity(id.trim_prefix(region_id + ":"), str(entity.name), Catalog.vector(entity.position),
			Catalog.vector(entity.size), entity.tags.duplicate(), entity.properties.duplicate(true),
			Color(str(spec.palette.work)), false)
		var body: Node3D = world.objects[id]
		body.set_meta("content_next", true)
		body.set_meta("practice_only", true)
		body.set_meta("original_route_unchanged", true)
		ids.append(id)
		var panel := Node3D.new()
		panel.name = "PracticeReadout"
		body.add_child(panel)
		var lamp := MeshInstance3D.new()
		lamp.name = "StateLamp"
		var sphere := SphereMesh.new()
		sphere.radius = .16
		sphere.height = .32
		sphere.radial_segments = 8
		sphere.rings = 4
		lamp.mesh = sphere
		lamp.position = Vector3(0, .65, -.95)
		lamp.material_override = _material("pending", Color("b89964"))
		lamp.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		panel.add_child(lamp)
		var readout: Label3D = _label(id + "_readout", str(entity.hint), Catalog.vector(entity.position) + Vector3(0, 2.1, 0), 17, Color("decfa6"))
		_feedback[id] = {"lamp":lamp, "readout":readout, "entity":entity, "requirements":_requirements(id)}
		# A foot-level repeated marker gives the operating face and approach side
		# a visible cue while leaving 3+ metres of flight clearance around it.
		var cue: Node3D = Props.make("route_beacon", region_id, 1)
		if is_instance_valid(cue):
			add_child(cue)
			cue.position = Catalog.vector(entity.position) + Vector3(-2.4, -1.0, 1.5)
			cue.scale = Vector3.ONE * .45
	var note_ids: Array = []
	for note: Dictionary in spec.get("notes", []): note_ids.append(str(note.id))
	var route_ids: Array = []
	for route: Dictionary in spec.get("routes", []): route_ids.append(str(route.id))
	return {"ok":true, "code":"world_content_developed_not_playtested", "root":self, "region":region_id,
		"entity_ids":ids, "note_ids":note_ids, "route_ids":route_ids}

func apply_view(entities: Dictionary) -> void:
	# Presentation only: never turns a threshold into a reward or saves a fact.
	for id: String in _feedback:
		var item: Dictionary = _feedback[id]
		var state: Dictionary = entities.get(id, {})
		if state.is_empty(): continue
		var complete := true
		for clause: Dictionary in item.requirements:
			var actual: Variant = state.get(str(clause.get("field", "")))
			if actual == null: complete = false; break
			match str(clause.get("op", "")):
				"gte": complete = complete and float(actual) >= float(clause.value)
				"lte": complete = complete and float(actual) <= float(clause.value)
				"eq": complete = complete and actual == clause.value
				_: complete = false
		var detail: String = _state_text(state)
		var key := str(complete) + detail
		if str(_feedback_keys.get(id, "")) == key: continue
		_feedback_keys[id] = key
		item.lamp.material_override = _material("ready", Color("9bc4a9")) if complete else _material("pending", Color("b89964"))
		item.readout.text = ("条件已成立 · 靠近实体 G 读取\n" if complete else str(item.entity.hint) + "\n") + detail

func _requirements(id: String) -> Array:
	for note: Dictionary in _spec.get("notes", []):
		if str(note.id) == id: return note.get("requires", []).duplicate(true)
	return []

func _state_text(state: Dictionary) -> String:
	var pieces := PackedStringArray()
	var tags: Array = state.get("tags", [])
	if "thermal" in tags: pieces.append("温度 %.0f°" % float(state.get("temperature", 20.0)))
	if "conductive" in tags: pieces.append("电荷 %.0f" % float(state.get("charge", 0.0)))
	if "photosensitive" in tags: pieces.append("光已亮" if float(state.get("light_level", 0.0)) >= .5 else "光未亮")
	if "growable" in tags: pieces.append("生长 %.0f%%" % (100.0 * float(state.get("growth", 0.0))))
	if "echo_operable" in tags: pieces.append("回声保持中" if bool(state.get("operated", false)) else "回声未保持")
	if "hackable" in tags: pieces.append("已接管" if bool(state.get("controlled", false)) else "待接管")
	return " · ".join(pieces)

func _solid(id: String, at: Vector3, size: Vector3, tone: String) -> void:
	var body := StaticBody3D.new()
	body.name = id
	body.position = at
	body.collision_layer = 1
	body.collision_mask = 0
	body.set_meta("content_next", true)
	add_child(body)
	var collision := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	collision.shape = box
	body.add_child(collision)
	var visual := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	visual.mesh = mesh
	visual.material_override = _material(tone, Color(str(_spec.palette.get(tone, "667c75"))))
	body.add_child(visual)
	# Small end caps announce a landing without railings across its return path.
	if tone == "stone":
		for side in [-1.0, 1.0]:
			var cap := MeshInstance3D.new()
			var cap_mesh := BoxMesh.new()
			cap_mesh.size = Vector3(.18, .035, maxf(.3, size.z - .3))
			cap.mesh = cap_mesh
			cap.position = Vector3(side * (size.x * .5 - .14), size.y * .5 + .025, 0)
			cap.material_override = _material("route", Color(str(_spec.palette.route)))
			cap.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			body.add_child(cap)

func _route(row: Dictionary) -> void:
	var points: Array = row.get("points", [])
	if points.size() < 2: return
	var route_root := Node3D.new()
	route_root.name = str(row.id)
	route_root.set_meta("navigation_only", true)
	add_child(route_root)
	# Thin hovering dashes sit below the authored flight height. They never
	# behave as a platform or block a mirror ray. Loops retain a visible return.
	var transforms: Array[Transform3D] = []
	for index in range(points.size() - 1):
		var from: Vector3 = Catalog.vector(points[index])
		var to: Vector3 = Catalog.vector(points[index + 1])
		var span: Vector3 = to - from
		var steps: int = maxi(1, int(ceil(span.length() / 4.0)))
		for step in range(steps):
			var at: Vector3 = from.lerp(to, float(step) / float(steps)) - Vector3.UP * 1.25
			var facing := Basis.IDENTITY
			var planar := Vector3(span.x, 0, span.z)
			if planar.length_squared() > .001: facing = Basis(Vector3.UP, atan2(planar.x, planar.z))
			transforms.append(Transform3D(facing, at))
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	var dash := BoxMesh.new()
	dash.size = Vector3(.13, .035, .75)
	multimesh.mesh = dash
	multimesh.instance_count = transforms.size()
	for index in range(transforms.size()): multimesh.set_instance_transform(index, transforms[index])
	var batch := MultiMeshInstance3D.new()
	batch.name = "FlightRouteDashes"
	batch.multimesh = multimesh
	batch.material_override = _material("route", Color(str(_spec.palette.route)))
	batch.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	route_root.add_child(batch)

func _material(key: String, tone: Color) -> StandardMaterial3D:
	if not _materials.has(key):
		var material := StandardMaterial3D.new()
		material.albedo_color = tone
		material.roughness = .9
		if key in ["route", "ready", "pending"]:
			material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_materials[key] = material
	return _materials[key]

func _label(id: String, value: String, at: Vector3, font_size: int, color: Color) -> Label3D:
	var label := Label3D.new()
	label.name = id.replace(":", "_")
	label.text = value
	label.font = load("res://assets/fonts/NotoSansSC-Medium.ttf")
	label.position = at
	label.font_size = font_size
	label.pixel_size = .019
	label.outline_size = 3
	label.modulate = color
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = false
	add_child(label)
	return label
