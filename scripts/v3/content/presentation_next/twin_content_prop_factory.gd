extends RefCounted
## Editable low-detail set dressing in the selected I-B / F-B visual language.
## Local presentation only. Callers supply all navigation, collision and authority.
## The four imported kit kinds reuse the project's existing explicit GLB wrappers.

const PropKit = preload("res://scripts/v3/art/twin_prop_kit.gd")
const KINDS := ["route_beacon", "archive_stela", "refuge_shelter", "maintenance_niche", "coolant_stack", "resonance_pylon", "fungus_garden", "root_canopy", "memorial_lantern", "signal_gate", "freight_buoy", "wind_vane", "relay_cabinet", "root_cluster", "work_terrace", "root_terrace"]
const IMPORTED := {"relay_cabinet":"power_relay_cabinet", "root_cluster":"photosensitive_roots", "work_terrace":"coastal_work_terrace", "root_terrace":"rootstone_terrace"}
const INDUSTRIAL := {"body":"b8c3bd", "dark":"455d68", "trim":"719095", "accent":"d2ad69", "signal":"78d4c0", "soft":"9aab9e", "warm":"a77151"}
const FANTASY := {"body":"b3b69b", "dark":"596c5a", "trim":"829173", "accent":"d2c48c", "signal":"8edcc6", "soft":"a18fba", "warm":"af876b"}
static var _materials: Dictionary = {}
static var _meshes: Dictionary = {}

static func supported_kinds() -> Array:
	return KINDS.duplicate()

static func make(kind: String, region: String, variant: int = 0) -> Node3D:
	var root := Node3D.new()
	root.name = "ContentProp_" + kind
	root.set_meta("content_kind", kind)
	root.set_meta("content_region", region)
	root.set_meta("editable_source", "res://scripts/v3/content/presentation_next/twin_content_prop_factory.gd")
	root.set_meta("presentation_only", true)
	var fantasy := region.begins_with("F")
	root.set_meta("fantasy_palette", fantasy)
	var palette: Dictionary = FANTASY if fantasy else INDUSTRIAL
	if IMPORTED.has(kind):
		var existing := PropKit.new()
		existing.asset_kind = str(IMPORTED[kind])
		existing.create_collision = false
		root.add_child(existing)
		return root
	match kind:
		"route_beacon": _route_beacon(root, palette, fantasy, variant)
		"archive_stela": _archive_stela(root, palette, fantasy)
		"refuge_shelter": _refuge_shelter(root, palette, fantasy)
		"maintenance_niche": _maintenance_niche(root, palette)
		"coolant_stack": _coolant_stack(root, palette, variant)
		"resonance_pylon": _resonance_pylon(root, palette, fantasy, variant)
		"fungus_garden": _fungus_garden(root, palette, variant)
		"root_canopy": _root_canopy(root, palette, variant)
		"memorial_lantern": _memorial_lantern(root, palette, fantasy)
		"signal_gate": _signal_gate(root, palette, fantasy)
		"freight_buoy": _freight_buoy(root, palette, fantasy)
		"wind_vane": _wind_vane(root, palette, fantasy)
		_: _route_beacon(root, palette, fantasy, variant)
	return root

## Change only marked visual indicators after a committed content state changes.
## No persistent record or gameplay effect is created here.
static func set_signal(root: Node3D, enabled: bool) -> void:
	if not is_instance_valid(root): return
	var palette: Dictionary = FANTASY if bool(root.get_meta("fantasy_palette", false)) else INDUSTRIAL
	for node in root.find_children("*", "MeshInstance3D", true, false):
		if bool(node.get_meta("content_signal", false)):
			node.material_override = _material(str(palette.signal) if enabled else str(palette.dark), enabled)

static func _route_beacon(root: Node3D, p: Dictionary, fantasy: bool, variant: int) -> void:
	_cylinder(root, Vector3(0, 0.15, 0), 0.65, 0.3, str(p.dark), 6)
	_cylinder(root, Vector3(0, 1.65, 0), 0.18 if fantasy else 0.11, 3.0, str(p.trim), 6)
	if fantasy:
		for side in [-1.0, 1.0]:
			var petal := _cone(root, Vector3(side * 0.45, 2.6, 0), 0.38, 1.2, str(p.body), 5)
			petal.rotation.z = side * 0.65
	else:
		_box(root, Vector3(0, 2.75, 0), Vector3(1.55, 0.52, 0.22), str(p.body))
		_box(root, Vector3(0, 3.12, 0), Vector3(0.88, 0.12, 0.32), str(p.accent))
	var number := posmod(variant, 3) + 1
	for index in range(number):
		_signal(root, Vector3(-0.22 * float(number - 1) + float(index) * 0.44, 2.75, 0.16), Vector3(0.15, 0.25, 0.08), str(p.signal))
	_box(root, Vector3(0, 0.4, 0), Vector3(0.42, 0.12, 0.48), str(p.accent))

static func _archive_stela(root: Node3D, p: Dictionary, fantasy: bool) -> void:
	_cylinder(root, Vector3(0, 0.13, 0), 1.0, 0.26, str(p.dark), 6)
	var slab := _box(root, Vector3(0, 1.55, 0), Vector3(1.45, 2.65, 0.42), str(p.body))
	slab.rotation.z = -0.045 if fantasy else 0.0
	_box(root, Vector3(0, 1.7, 0.24), Vector3(1.12, 1.95, 0.08), str(p.dark))
	for index in range(5):
		_box(root, Vector3(-0.06, 1.0 + float(index) * 0.32, 0.3), Vector3(0.72 if index % 2 == 0 else 0.9, 0.07, 0.035), str(p.trim))
	_signal(root, Vector3(0, 2.65, 0.31), Vector3(0.65, 0.12, 0.07), str(p.signal))
	if fantasy:
		_cone(root, Vector3(-0.9, 0.35, 0.12), 0.23, 0.8, str(p.trim), 5)
		_cone(root, Vector3(0.83, 0.28, -0.12), 0.2, 0.62, str(p.soft), 5)
	else:
		_box(root, Vector3(0, 0.48, 0.42), Vector3(0.95, 0.12, 0.28), str(p.accent))

static func _refuge_shelter(root: Node3D, p: Dictionary, fantasy: bool) -> void:
	_box(root, Vector3(0, 0.16, 0), Vector3(4.2, 0.32, 3.0), str(p.dark))
	for side in [-1.0, 1.0]:
		var post := _box(root, Vector3(side * 1.8, 1.7, -0.8), Vector3(0.24, 3.1, 0.24), str(p.trim))
		post.rotation.z = side * (0.12 if fantasy else 0.0)
		_box(root, Vector3(side * 1.35, 0.68, -0.8), Vector3(1.0, 0.26, 0.75), str(p.body))
		_box(root, Vector3(side * 1.35, 0.45, -0.8), Vector3(0.16, 0.6, 0.6), str(p.trim))
	if fantasy:
		for side in [-1.0, 1.0]:
			var leaf := _box(root, Vector3(side * 1.0, 3.25, -0.35), Vector3(2.3, 0.2, 3.3), str(p.body))
			leaf.rotation.z = side * 0.16
	else:
		_box(root, Vector3(0, 3.2, -0.35), Vector3(4.5, 0.24, 3.3), str(p.body))
		_box(root, Vector3(0, 3.35, -0.3), Vector3(4.5, 0.11, 0.25), str(p.accent))
	_box(root, Vector3(0, 1.1, -1.15), Vector3(1.2, 1.7, 0.2), str(p.trim))
	_signal(root, Vector3(0, 2.66, -0.65), Vector3(0.5, 0.18, 0.16), str(p.signal))

static func _maintenance_niche(root: Node3D, p: Dictionary) -> void:
	_box(root, Vector3(0, 0.14, 0), Vector3(3.6, 0.28, 2.2), str(p.dark))
	_box(root, Vector3(0, 1.1, -0.45), Vector3(2.7, 0.22, 1.1), str(p.body))
	for side in [-1.0, 1.0]:
		_box(root, Vector3(side * 1.1, 0.65, -0.45), Vector3(0.25, 1.0, 0.8), str(p.trim))
	_box(root, Vector3(0, 1.9, -0.85), Vector3(2.8, 1.25, 0.18), str(p.dark))
	for index in range(4):
		_box(root, Vector3(-0.9 + float(index) * 0.6, 1.95, -0.7), Vector3(0.14, 0.62 if index % 2 == 0 else 0.42, 0.08), str(p.accent))
	_cylinder(root, Vector3(-0.75, 1.42, -0.3), 0.25, 0.44, str(p.trim), 8)
	_box(root, Vector3(0.5, 1.38, -0.3), Vector3(0.8, 0.34, 0.45), str(p.warm))
	_signal(root, Vector3(1.2, 2.45, -0.7), Vector3(0.18, 0.18, 0.08), str(p.signal))

static func _coolant_stack(root: Node3D, p: Dictionary, variant: int) -> void:
	_box(root, Vector3(0, 0.14, 0), Vector3(3.2, 0.28, 2.5), str(p.dark))
	for index in range(3):
		var at := Vector3(-0.92 + float(index) * 0.92, 0.95, -0.15 if index % 2 == 0 else 0.25)
		_cylinder(root, at, 0.38, 1.45, str(p.body), 8)
		_cylinder(root, at + Vector3(0, 0.57, 0), 0.39, 0.17, str(p.accent), 8)
		_box(root, at + Vector3(0, 0.12, 0.37), Vector3(0.18, 0.52, 0.08), str(p.trim))
	_box(root, Vector3(0, 1.8, -0.72), Vector3(2.3, 0.16, 0.14), str(p.trim))
	var valve := _cylinder(root, Vector3(1.28, 1.65, -0.72), 0.28, 0.08, str(p.warm), 8)
	valve.rotation.z = PI / 2.0
	_signal(root, Vector3(1.35, 0.65 + float(posmod(variant, 2)) * 0.18, 0.65), Vector3(0.12, 0.24, 0.08), str(p.signal))

static func _resonance_pylon(root: Node3D, p: Dictionary, fantasy: bool, variant: int) -> void:
	_cylinder(root, Vector3(0, 0.2, 0), 1.05, 0.4, str(p.dark), 6)
	_cylinder(root, Vector3(0, 2.05, 0), 0.4, 3.4, str(p.trim), 6)
	for index in range(3):
		var band := _cylinder(root, Vector3(0, 2.4 + float(index) * 0.55, 0), 0.72 - float(index) * 0.1, 0.13, str(p.body), 8)
		band.rotation.z = (0.2 if fantasy else 0.0) * float(index - 1)
	var crown := _cone(root, Vector3(0, 4.25, 0), 0.6, 1.0, str(p.accent), 6)
	crown.rotation.y = float(posmod(variant, 4)) * PI / 4.0
	_signal(root, Vector3(0, 3.6, 0.43), Vector3(0.23, 0.65, 0.12), str(p.signal))
	for side in [-1.0, 1.0]:
		var arm := _box(root, Vector3(side * 0.75, 1.35, 0), Vector3(1.25, 0.18, 0.22), str(p.body))
		arm.rotation.z = side * 0.7

static func _fungus_garden(root: Node3D, p: Dictionary, variant: int) -> void:
	_cylinder(root, Vector3(0, 0.12, 0), 1.75, 0.24, str(p.dark), 7)
	for index in range(5):
		var angle := float(index) * TAU / 5.0 + float(posmod(variant, 3)) * 0.3
		var distance := 0.45 if index == 0 else 1.15
		var height := 0.85 + float(posmod(index + variant, 3)) * 0.48
		var at := Vector3(cos(angle) * distance, height * 0.5 + 0.18, sin(angle) * distance)
		var stem := _cylinder(root, at, 0.11, height, str(p.body), 5)
		stem.rotation.z = cos(angle) * 0.12
		var cap := _cone(root, Vector3(at.x, height + 0.2, at.z), 0.54, 0.4, str(p.soft if index % 2 == 0 else p.trim), 7)
		cap.rotation.x = PI
		if index % 2 == 0:
			_signal(root, Vector3(at.x, height + 0.05, at.z + 0.3), Vector3(0.18, 0.12, 0.12), str(p.signal))

static func _root_canopy(root: Node3D, p: Dictionary, variant: int) -> void:
	for side in [-1.0, 1.0]:
		var trunk := _cylinder(root, Vector3(side * 1.6, 1.75, 0), 0.32, 3.6, str(p.dark), 6)
		trunk.rotation.z = side * 0.22
		for index in range(2):
			var branch := _box(root, Vector3(side * (1.1 - float(index) * 0.3), 3.1 + float(index) * 0.34, 0), Vector3(2.2, 0.25, 0.42), str(p.trim))
			branch.rotation.z = side * (0.28 - float(index) * 0.3)
	for index in range(3):
		var leaf := _cone(root, Vector3(-1.2 + float(index) * 1.2, 3.8, 0), 1.35, 0.75, str(p.body if index != posmod(variant, 3) else p.soft), 6)
		leaf.scale.z = 0.65
	_cylinder(root, Vector3(-1.62, 0.14, 0), 0.75, 0.28, str(p.trim), 6)
	_cylinder(root, Vector3(1.62, 0.14, 0), 0.75, 0.28, str(p.trim), 6)

static func _memorial_lantern(root: Node3D, p: Dictionary, fantasy: bool) -> void:
	_cylinder(root, Vector3(0, 0.15, 0), 0.6, 0.3, str(p.dark), 6)
	_cylinder(root, Vector3(0, 0.95, 0), 0.12, 1.4, str(p.trim), 6)
	_box(root, Vector3(0, 1.8, 0), Vector3(0.8, 0.18, 0.8), str(p.body))
	for x in [-0.31, 0.31]:
		for z in [-0.31, 0.31]:
			_box(root, Vector3(x, 2.2, z), Vector3(0.08, 0.75, 0.08), str(p.trim))
	_signal(root, Vector3(0, 2.2, 0), Vector3(0.43, 0.55, 0.43), str(p.signal))
	_cone(root, Vector3(0, 2.7, 0), 0.6, 0.35, str(p.accent), 6 if fantasy else 4)
	_box(root, Vector3(0, 0.42, 0.5), Vector3(0.52, 0.14, 0.25), str(p.body))

static func _signal_gate(root: Node3D, p: Dictionary, fantasy: bool) -> void:
	for side in [-1.0, 1.0]:
		_box(root, Vector3(side * 3.7, 0.15, 0), Vector3(1.3, 0.3, 1.6), str(p.dark))
		var column := _box(root, Vector3(side * 3.7, 2.6, 0), Vector3(0.55, 4.9, 0.65), str(p.trim))
		column.rotation.z = side * (0.065 if fantasy else 0.0)
		_signal(root, Vector3(side * 3.7, 3.65, 0.4), Vector3(0.2, 1.1, 0.12), str(p.signal))
	_box(root, Vector3(0, 5.25, 0), Vector3(8.1, 0.4, 0.75), str(p.body))
	_box(root, Vector3(0, 5.52, 0), Vector3(4.2, 0.14, 0.8), str(p.accent))
	for index in range(3):
		_box(root, Vector3(-0.75 + float(index) * 0.75, 5.25, 0.43), Vector3(0.2, 0.18, 0.08), str(p.dark))

static func _freight_buoy(root: Node3D, p: Dictionary, fantasy: bool) -> void:
	_cylinder(root, Vector3(0, 0.3, 0), 1.2, 0.6, str(p.dark), 8)
	_cylinder(root, Vector3(0, 0.63, 0), 0.95, 0.14, str(p.accent), 8)
	_box(root, Vector3(0, 1.12, 0), Vector3(1.1, 0.85, 1.1), str(p.body))
	for side in [-1.0, 1.0]:
		_box(root, Vector3(side * 0.56, 1.12, 0), Vector3(0.08, 0.85, 1.16), str(p.trim))
	_cylinder(root, Vector3(0, 2.0, 0), 0.08, 1.0, str(p.trim), 6)
	_signal(root, Vector3(0, 2.55, 0), Vector3(0.32, 0.32, 0.32), str(p.signal))
	if fantasy: _cone(root, Vector3(0, 1.65, 0), 0.5, 0.3, str(p.soft), 6)

static func _wind_vane(root: Node3D, p: Dictionary, fantasy: bool) -> void:
	_cylinder(root, Vector3(0, 0.15, 0), 0.6, 0.3, str(p.dark), 6)
	_cylinder(root, Vector3(0, 2.0, 0), 0.1, 3.7, str(p.trim), 6)
	_box(root, Vector3(0, 3.75, 0), Vector3(2.25, 0.11, 0.16), str(p.body))
	var flag := _box(root, Vector3(0.72, 3.43, 0), Vector3(0.85, 0.55, 0.08), str(p.soft if fantasy else p.accent))
	flag.rotation.z = -0.15
	_signal(root, Vector3(-0.95, 3.75, 0), Vector3(0.18, 0.18, 0.18), str(p.signal))

static func _box(parent: Node3D, at: Vector3, size: Vector3, color: String, glowing: bool = false) -> MeshInstance3D:
	var key := "box:" + str(size)
	if not _meshes.has(key):
		var box := BoxMesh.new()
		box.size = size
		_meshes[key] = box
	return _instance(parent, at, _meshes[key] as Mesh, color, glowing)

static func _cylinder(parent: Node3D, at: Vector3, radius: float, height: float, color: String, sides: int) -> MeshInstance3D:
	var key := "cylinder:%s:%s:%s" % [radius, height, sides]
	if not _meshes.has(key):
		var cylinder := CylinderMesh.new()
		cylinder.top_radius = radius
		cylinder.bottom_radius = radius
		cylinder.height = height
		cylinder.radial_segments = sides
		cylinder.rings = 1
		_meshes[key] = cylinder
	return _instance(parent, at, _meshes[key] as Mesh, color)

static func _cone(parent: Node3D, at: Vector3, radius: float, height: float, color: String, sides: int) -> MeshInstance3D:
	var key := "cone:%s:%s:%s" % [radius, height, sides]
	if not _meshes.has(key):
		var cone := CylinderMesh.new()
		cone.top_radius = 0.06
		cone.bottom_radius = radius
		cone.height = height
		cone.radial_segments = sides
		cone.rings = 1
		_meshes[key] = cone
	return _instance(parent, at, _meshes[key] as Mesh, color)

static func _signal(parent: Node3D, at: Vector3, size: Vector3, color: String) -> MeshInstance3D:
	var node := _box(parent, at, size, color, true)
	node.set_meta("content_signal", true)
	return node

static func _instance(parent: Node3D, at: Vector3, mesh: Mesh, color: String, glowing: bool = false) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.mesh = mesh
	node.material_override = _material(color, glowing)
	node.position = at
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF if glowing else GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	parent.add_child(node)
	return node

static func _material(color: String, glowing: bool = false) -> StandardMaterial3D:
	var key := color + (":signal" if glowing else ":surface")
	if not _materials.has(key):
		var material := StandardMaterial3D.new()
		material.resource_name = "TwinPulseContent_" + key
		material.albedo_color = Color(color)
		material.roughness = 0.9
		material.emission_enabled = glowing
		if glowing:
			material.emission = Color(color)
			material.emission_energy_multiplier = 0.42
		_materials[key] = material
	return _materials[key] as StandardMaterial3D
