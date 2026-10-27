class_name TwinCrownWarning
extends Node3D
## Uses the exact millimetre volumes sent by the host; never resolves damage.
var caption: Label3D
var surfaces: Array[StandardMaterial3D] = []
var _kind = ""

func configure(shape: Dictionary, kind: String) -> void:
	_kind = kind
	var centre: Array = shape.centre_xz_mm
	position = Vector3(float(centre[0]) / 1000.0, 0, float(centre[1]) / 1000.0)
	var low = float(shape.y_min_mm) / 1000.0
	var high = float(shape.y_max_mm) / 1000.0
	var outer = float(shape.outer_mm) / 1000.0
	var inner = float(shape.inner_mm) / 1000.0
	for radius in [outer, inner]:
		if radius <= 0: continue
		for y in [low, high]:
			var mesh = TorusMesh.new()
			mesh.inner_radius = maxf(0.01, radius - 0.10)
			mesh.outer_radius = radius
			mesh.rings = 40
			mesh.ring_segments = 5
			_add_mesh(mesh, Vector3(0, y, 0))
	for index in range(4):
		var angle = float(index) * TAU / 4
		var mesh = BoxMesh.new()
		mesh.size = Vector3(0.055, high - low, 0.055)
		_add_mesh(mesh, Vector3(cos(angle) * outer, (low + high) * 0.5, sin(angle) * outer))
	caption = Label3D.new()
	caption.font = load("res://assets/fonts/NotoSansSC-Medium.ttf")
	caption.font_size = 24
	caption.outline_size = 4
	caption.pixel_size = 0.025
	caption.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	caption.position = Vector3(0, high + 0.8, 0)
	add_child(caption)

func update_time(seconds: float, active: bool) -> void:
	var tint = Color("db7856") if active else Color("e4ba70")
	for material in surfaces: material.albedo_color = tint
	var title = "灼孢" if _kind == "burning_spores" else "根浪 / 孢柱"
	caption.modulate = tint.lightened(0.15)
	caption.text = "%s · %s %.1fs" % [title, "生效" if active else "预警", maxf(0, seconds)]

func _add_mesh(mesh: Mesh, at: Vector3) -> void:
	var visual = MeshInstance3D.new()
	visual.mesh = mesh
	var material = StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	visual.material_override = material
	surfaces.append(material)
	visual.position = at
	add_child(visual)
