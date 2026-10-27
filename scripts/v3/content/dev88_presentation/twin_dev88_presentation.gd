extends RefCounted
## Reusable visual production layer. No physics, AI, inputs, saves or transport.
const Props = preload("res://scripts/v3/content/presentation_next/twin_content_prop_factory.gd")
const SOURCE := "res://data/v3/content/dev88_presentation/presentation.json"
static var _book: Dictionary = {}
static var _materials: Dictionary = {}
static var _unit_meshes: Dictionary = {}

static func build(region: String, markers: Array = []) -> Node3D:
	var root := Node3D.new()
	root.name = "Dev88Presentation"
	root.set_meta("region", region)
	root.set_meta("visual_only", true)
	root.set_meta("editable_source", "res://scripts/v3/content/dev88_presentation/twin_dev88_presentation.gd")
	var spec: Dictionary = _data().get("regions", {}).get(region, {})
	for row: Dictionary in spec.get("props", []):
		var prop: Node3D = Props.make(str(row.kind), region, int(row.get("variant", 0)))
		root.add_child(prop)
		prop.position = _point(row.position)
		prop.rotation.y = deg_to_rad(float(row.get("yaw", 0)))
		prop.scale = Vector3.ONE * float(row.get("scale", 1.0))
	if not spec.is_empty():
		_relief(root, region)
		_backdrop(root, region, str(spec.get("backdrop", "")))
		_choice_tableau(root, region)
	_decorate_contacts(root, region, markers)
	return root

static func make_character(role: String, region: String, variant: int = 0) -> Node3D:
	var specs: Dictionary = _data().get("characters", {})
	var key := role
	if not specs.has(key):
		for id: String in specs:
			var candidate: Dictionary = specs[id]
			if role.contains(str(candidate.name)) or role == str(candidate.role) or role == id.trim_prefix("npc:"): key = id; break
	var spec: Dictionary = specs.get(key, {"name":"联络员", "role":"地区联络", "model":"worker", "accent":"90b8ac", "accessory":"folio"})
	var root := Node3D.new()
	root.name = "ContactProjection_" + key.replace(":", "_")
	root.set_meta("character_id", key)
	root.set_meta("projection_only", true)
	var models: Dictionary = _data().get("character_models", {})
	var path := str(models.get(str(spec.model), ""))
	var scene: PackedScene
	if not path.is_empty(): scene = load(path) as PackedScene
	if scene != null:
		var model: Node3D = scene.instantiate() as Node3D
		model.name = "ReusedEditableCharacterGLB"
		model.process_mode = Node.PROCESS_MODE_DISABLED
		root.add_child(model)
		model.scale = Vector3.ONE * 1.12
		model.rotation.y = deg_to_rad(12.0 * float(posmod(variant, 3) - 1))
	var accent := str(spec.accent)
	var dark := "596c5a" if region.begins_with("F") else "455d68"
	_part(root, "cylinder", Vector3(0, .035, 0), Vector3(.9, .07, .9), dark)
	_part(root, "ring", Vector3(0, .085, 0), Vector3(1.05, .04, 1.05), "81d3c4", true)
	# A visible emitter and light bars make this a radio image, not a newly
	# simulated resident whose location contradicts the original story.
	for side in [-1.0, 1.0]:
		_part(root, "box", Vector3(side * .36, .17, 0), Vector3(.1, .15, .34), accent)
	_accessory(root, str(spec.accessory), accent, dark)
	var plate := _label(root, str(spec.name) + "\n" + str(spec.role) + " · 联络影像", Vector3(0, 2.6, 0))
	plate.set_meta("contact_label", true)
	return root

## Pass the original committed Story state directly. This changes visibility
## and indicator materials only; unchosen alternatives remain hidden.
static func apply_state(root: Node3D, packet: Dictionary) -> void:
	if not is_instance_valid(root): return
	var choices: Dictionary = packet.get("choices", {})
	for group in root.find_children("ChoiceView_*", "Node3D", true, false):
		var objective := str(group.get_meta("choice_objective", ""))
		group.visible = str(choices.get(objective, "")) == str(group.get_meta("choice_option", ""))
	var flags: Dictionary = packet.get("flags", {})
	var region := str(root.get_meta("region", ""))
	var cleared := bool(flags.get(region + ":boss_stopped", false))
	for sign in root.find_children("VictorySignal_*", "Node3D", true, false):
		Props.set_signal(sign, cleared)

## Add readable operating faces to the additive Dev87/Dev88 ability props.
## Existing core art, collisions and combat targets are deliberately untouched.
## Call after all additive content has registered its world.objects entries.
static func decorate_devices(world: Node3D) -> int:
	var count := 0
	var objects: Dictionary = world.objects
	var definitions: Dictionary = world.definitions
	for id: String in objects:
		if not id.contains(":job88:") and not id.contains(":job88_") and not id.contains(":next_"): continue
		var body: Node3D = objects[id]
		if body.has_node("Dev88OperatingFace"): continue
		var state: Dictionary = definitions.get(id, {})
		var tags: Array = state.get("tags", [])
		var surface := Vector3(1, 1, 1)
		var original: MeshInstance3D = body.get_node_or_null("Shape") as MeshInstance3D
		if original != null and original.mesh is BoxMesh: surface = (original.mesh as BoxMesh).size
		var skin := Node3D.new()
		skin.name = "Dev88OperatingFace"
		skin.set_meta("entity_id", id)
		body.add_child(skin)
		var front := surface.z * .5 + .025
		var width := minf(surface.x * .78, 1.15)
		var height := minf(surface.y * .78, 1.15)
		_part(skin, "box", Vector3(0, 0, front), Vector3(width, height, .025), "455d68" if not str(world.region_id).begins_with("F") else "596c5a")
		if "conductive" in tags:
			for index in range(3): _part(skin, "box", Vector3(-width * .28 + index * width * .28, height * .1, front + .025), Vector3(width * .12, height * .5, .025), "d2b478")
		if "thermal" in tags:
			_part(skin, "box", Vector3(-width * .35, 0, front + .04), Vector3(.075, height * .75, .03), "bf8665")
			var lamp := _part(skin, "box", Vector3(-width * .35, -height * .25, front + .055), Vector3(.09, .09, .035), "d2b478", true)
			lamp.set_meta("device_field", "temperature")
		if "photosensitive" in tags:
			var lens := _part(skin, "ring", Vector3(width * .22, height * .08, front + .06), Vector3(height * .55, .04, height * .55), "a7c9c1")
			lens.rotation.x = PI / 2.0
		if "growable" in tags:
			for side in [-1.0, 1.0]:
				var leaf := _part(skin, "cone", Vector3(side * width * .3, height * .3, front + .04), Vector3(.11, height * .45, .07), "94b789")
				leaf.rotation.z = side * .6
		if "echo_operable" in tags:
			for side in [-1.0, 1.0]:
				var echo := _part(skin, "ring", Vector3(side * width * .23, -height * .15, front + .06), Vector3(height * .24, .025, height * .24), "b4a2c4")
				echo.rotation.x = PI / 2.0
		if "hackable" in tags:
			for index in range(3): _part(skin, "box", Vector3(-width * .2 + index * width * .2, -height * .28, front + .06), Vector3(.06, .06, .025), "84c1c7")
		count += 1
	return count

static func _decorate_contacts(root: Node3D, region: String, markers: Array) -> void:
	var occupied: Array[Vector3] = []
	var characters: Dictionary = _data().get("characters", {})
	for row: Dictionary in markers:
		if str(row.get("region", "")) != region or str(row.get("kind", "")) != "npc": continue
		var at: Vector3 = _point(row.get("position", [0, 0, 0]))
		var overlap := false
		for old: Vector3 in occupied:
			if at.distance_to(old) < 1.2: overlap = true; break
		if overlap: continue
		occupied.append(at)
		var role := str(row.get("character_id", row.get("id", "")))
		if not characters.has(role):
			var label := str(row.get("label", ""))
			for id: String in characters:
				if label.contains(str(characters[id].name)): role = id; break
		var figure: Node3D = make_character(role, region, occupied.size())
		root.add_child(figure)
		figure.position = at + Vector3(-1.1, -.92, -.55)
		figure.rotation.y = -.25

static func _accessory(root: Node3D, kind: String, accent: String, dark: String) -> void:
	match kind:
		"rescue":
			_part(root, "box", Vector3(0, 1.2, .17), Vector3(.5, .58, .12), accent)
			for side in [-1.0, 1.0]: _part(root, "box", Vector3(side * .16, 1.2, .245), Vector3(.055, .5, .025), "e0dcb7")
			_part(root, "box", Vector3(.28, 1.38, -.25), Vector3(.16, .42, .25), dark)
			_part(root, "cylinder", Vector3(.28, 1.92, -.25), Vector3(.025, .7, .025), dark)
		"toolpack":
			_part(root, "box", Vector3(0, 1.16, -.25), Vector3(.53, .63, .2), accent)
			for index in range(3): _part(root, "box", Vector3(-.16 + index * .16, 1.27, -.37), Vector3(.055, .38, .04), dark)
			_part(root, "box", Vector3(.36, .8, .1), Vector3(.22, .37, .26), accent)
		"folio":
			var folio := _part(root, "box", Vector3(.37, 1.1, .25), Vector3(.43, .5, .08), accent)
			folio.rotation.z = -.2
			for index in range(3): _part(root, "box", Vector3(.37, .97 + index * .11, .3), Vector3(.28, .025, .02), "e1dfc6")
		"leaves", "crown":
			for side in [-1.0, 1.0]:
				var leaf := _part(root, "cone", Vector3(side * .3, 1.48, -.03), Vector3(.25, .72, .19), accent)
				leaf.rotation.z = side * .8
			if kind == "crown":
				for index in range(3): _part(root, "cone", Vector3(-.18 + index * .18, 2.14, 0), Vector3(.14, .4, .14), accent)
		"fungi":
			for side in [-1.0, 1.0]:
				_part(root, "cylinder", Vector3(side * .25, 1.54, -.1), Vector3(.06, .45, .06), "c9c5a2")
				_part(root, "cone", Vector3(side * .25, 1.8, -.1), Vector3(.35, .2, .35), accent)
		"seedbasket":
			_part(root, "box", Vector3(0, 1.02, -.35), Vector3(.58, .54, .3), dark)
			for index in range(4): _part(root, "cone", Vector3(-.2 + index * .13, 1.48, -.35), Vector3(.12, .65, .12), accent)
		"aerial":
			_part(root, "box", Vector3(0, 1.1, -.3), Vector3(.43, .5, .22), dark)
			_part(root, "cylinder", Vector3(-.17, 1.85, -.3), Vector3(.035, 1.1, .035), accent)
			_part(root, "box", Vector3(-.17, 2.34, -.3), Vector3(.47, .08, .08), accent)
		"lantern":
			_part(root, "box", Vector3(.42, .87, .12), Vector3(.25, .38, .25), dark)
			_part(root, "box", Vector3(.42, .88, .26), Vector3(.17, .23, .04), accent, true)
			_part(root, "cone", Vector3(.42, 1.1, .12), Vector3(.35, .15, .35), accent)

static func _relief(root: Node3D, region: String) -> void:
	var fantasy := region.begins_with("F")
	var color := "8ab29a" if fantasy else "c0ad7c"
	var transforms: Array[Transform3D] = []
	for index in range(10):
		var x := -29.0 + float(index) * 1.1
		var at := Vector3(x, 2.045, 32.0 + (sin(float(index) * .8) * .6 if fantasy else 0.0))
		var rotation := Basis(Vector3.UP, .35 if index % 2 == 0 else -.35)
		transforms.append(Transform3D(rotation * Basis.from_scale(Vector3(.16, .02, 1.35)), at))
	_batch(root, "SouthWorkSurfaceInlays", "box", transforms, color)
	# Two visibly distinct uninterrupted lines represent industrial and living
	# lifelines without adding a bridge or suggesting an unchosen final plan.
	if region == "F4":
		for side in [-1.0, 1.0]:
			var line: Array[Transform3D] = []
			for index in range(7): line.append(Transform3D(Basis.from_scale(Vector3(.09, .018, .8)), Vector3(-24.0 + side * .6, 2.055, 27.7 + index * 1.05)))
			_batch(root, "LivingLine" if side < 0 else "IndustrialLine", "box", line, "8abfa3" if side < 0 else "d0b779")

static func _backdrop(root: Node3D, region: String, kind: String) -> void:
	var fantasy := region.begins_with("F")
	var tone := "819574" if fantasy else "768b93"
	var accent := "c7c79d" if fantasy else "c6a47b"
	var items: Array[Transform3D] = []
	# Beyond the lateral play boundary: no collision or opaque scenery is
	# placed through the original mirror rays, Boss core or combat corridors.
	for index in range(5):
		var x := -44.0
		var z := -28.0 + float(index) * 12.0
		var height := 3.0 + float(index % 3) * 1.7
		items.append(Transform3D(Basis.from_scale(Vector3(1.0, height, 1.0)), Vector3(x, height * .5 - .2, z)))
	_batch(root, "OuterWorkColumns", "cylinder", items, tone)
	var clusters: Array[Transform3D] = []
	for index in range(5):
		var height := 3.0 + float(index % 3) * 1.7
		clusters.append(Transform3D(Basis.from_scale(Vector3(2.4, .3 if not fantasy else .7, 2.4)), Vector3(-44, height + .1, -28.0 + index * 12.0)))
	_batch(root, "OuterWorkCaps_" + kind, "cone" if fantasy else "cylinder", clusters, accent)
	for index in range(3):
		var sign: Node3D = Props.make("memorial_lantern" if fantasy else "route_beacon", region, index)
		sign.name = "VictorySignal_" + str(index)
		root.add_child(sign)
		sign.position = Vector3(-42.5, 1.2, -23.0 + index * 16.0)
		sign.scale = Vector3.ONE * .8
		Props.set_signal(sign, false)

static func _choice_tableau(root: Node3D, region: String) -> void:
	var objective := ""
	var options: Array = []
	match region:
		"F2": objective = "F2:mirror_evidence:decision"; options = ["publish_raw", "publish_context"]
		"I4": objective = "I4:prism_array:decision"; options = ["public_caps", "regional_cosign"]
		"F4": objective = "F4:twin_vein_core:decision"; options = ["shared_stewardship", "industrial_lifeline", "living_vein"]
		_: return
	for index in range(options.size()):
		var group := Node3D.new()
		group.name = "ChoiceView_" + str(options[index])
		group.set_meta("choice_objective", objective)
		group.set_meta("choice_option", str(options[index]))
		group.visible = false
		root.add_child(group)
		group.position = Vector3(-42, 2, 27)
		var kind := "archive_stela" if region == "F2" else "resonance_pylon"
		if region == "F4": kind = ["memorial_lantern", "coolant_stack", "fungus_garden"][index]
		var prop: Node3D = Props.make(kind, region, index)
		group.add_child(prop)
		if str(options[index]) in ["publish_context", "regional_cosign", "shared_stewardship"]:
			for side in [-1.0, 1.0]:
				var lamp: Node3D = Props.make("memorial_lantern", region, 0)
				group.add_child(lamp)
				lamp.position = Vector3(side * 1.8, 0, 0)
				lamp.scale = Vector3.ONE * .6

static func _part(parent: Node3D, shape: String, at: Vector3, size: Vector3, color: String, glow: bool = false) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.mesh = _mesh(shape)
	node.material_override = _material(color, glow)
	node.position = at
	node.scale = size
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(node)
	return node

static func _batch(parent: Node3D, id: String, shape: String, transforms: Array[Transform3D], color: String) -> void:
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.mesh = _mesh(shape)
	multimesh.instance_count = transforms.size()
	for index in range(transforms.size()): multimesh.set_instance_transform(index, transforms[index])
	var node := MultiMeshInstance3D.new()
	node.name = id
	node.multimesh = multimesh
	node.material_override = _material(color)
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(node)

static func _mesh(shape: String) -> Mesh:
	if not _unit_meshes.has(shape):
		var mesh: PrimitiveMesh
		match shape:
			"cylinder", "cone":
				var cylinder := CylinderMesh.new()
				cylinder.radial_segments = 6
				cylinder.rings = 1
				cylinder.height = 1.0
				cylinder.top_radius = .04 if shape == "cone" else .5
				cylinder.bottom_radius = .5
				mesh = cylinder
			"ring":
				var ring := TorusMesh.new()
				ring.inner_radius = .4
				ring.outer_radius = .5
				ring.rings = 12
				ring.ring_segments = 4
				mesh = ring
			_:
				var box := BoxMesh.new()
				box.size = Vector3.ONE
				mesh = box
		_unit_meshes[shape] = mesh
	return _unit_meshes[shape] as Mesh

static func _material(color: String, glow: bool = false) -> StandardMaterial3D:
	var key := color + (":glow" if glow else "")
	if not _materials.has(key):
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(color)
		mat.roughness = .9
		mat.emission_enabled = glow
		if glow: mat.emission = Color(color); mat.emission_energy_multiplier = .22
		_materials[key] = mat
	return _materials[key] as StandardMaterial3D

static func _label(parent: Node3D, text: String, at: Vector3) -> Label3D:
	var label := Label3D.new()
	label.text = text
	label.position = at
	label.font = load("res://assets/fonts/NotoSansSC-Medium.ttf")
	label.font_size = 20
	label.pixel_size = .012
	label.outline_size = 3
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.modulate = Color("c9d9c3")
	parent.add_child(label)
	return label

static func _point(value: Variant) -> Vector3:
	if value is Vector3: return value
	if value is Array and value.size() == 3: return Vector3(float(value[0]), float(value[1]), float(value[2]))
	return Vector3.ZERO

static func _data() -> Dictionary:
	if _book.is_empty():
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(SOURCE))
		if parsed is Dictionary: _book = parsed
	return _book
