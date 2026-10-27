class_name TwinBossWarning
extends Node3D
## Presentation only. Radius/height use the same definition as host hit testing.
const Attacks = preload("res://scripts/v3/gameplay/twin_boss_attacks.gd")
var attack := ""
var target := Vector3.ZERO
var radius := 0.0
var limits := Vector2.ZERO
var ticks: Array[MeshInstance3D] = []
var caption: Label3D
var _hint := ""

func configure(kind: String, point: Vector3) -> void:
	attack = kind
	target = point
	var rule: Dictionary = Attacks.definition(kind)
	if rule.is_empty(): return
	radius = float(rule.radius)
	position = Vector3(point.x, 0, point.z)
	var tint: Color = rule.color
	var y = point.y
	match str(rule.height_mode):
		"below_world":
			limits = Vector2(-1.0, float(rule.height_limit))
			y = clampf(y, limits.x, limits.y)
			_hint = "升至 %.0f m / 移出圈" % limits.y
		"around_target":
			limits = Vector2(point.y - float(rule.height_limit), point.y + float(rule.height_limit))
			_hint = "升降 %.1f m / 移出圈" % float(rule.height_limit)
		_:
			limits = Vector2(y, y)
			_hint = "保持制动 / 移出圈"
	_ring(y, 0.14, tint)
	if limits.y > limits.x:
		# Explicit vertical bounds; unlike a flat floor decal these show safe altitude.
		_ring(limits.y, 0.075, tint)
		_ring(limits.x, 0.075, tint)
		for i in range(4):
			var angle = i * TAU / 4.0
			var at = Vector3(cos(angle) * (radius - 0.055), (limits.x + limits.y) * 0.5, sin(angle) * (radius - 0.055))
			_box(at, Vector3(0.07, limits.y - limits.x, 0.07), tint.darkened(0.25))
	for i in range(12):
		var angle = -PI * 0.5 + i * TAU / 12.0
		var tick = _box(Vector3(cos(angle) * (radius - 0.4), y + 0.04, sin(angle) * (radius - 0.4)), Vector3(0.12, 0.06, 0.3), tint)
		tick.rotation.y = -angle + PI * 0.5
		ticks.append(tick)
	caption = Label3D.new()
	caption.font_size = 26
	caption.outline_size = 6
	caption.pixel_size = 0.022
	caption.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	caption.modulate = tint.lightened(0.25)
	caption.position = Vector3(0, maxf(y, limits.y) + 1.4, 0)
	add_child(caption)
	set_remaining(2.0)

func set_remaining(seconds: float) -> void:
	if not is_instance_valid(caption): return
	var rule: Dictionary = Attacks.definition(attack)
	caption.text = "%s · %.1f s\n%s" % [rule.get("name", ""), maxf(seconds, 0), _hint]
	var remaining_ticks = ceili(clampf(seconds / 2.0, 0, 1) * 12)
	for i in range(ticks.size()): ticks[i].visible = i < remaining_ticks

func _ring(y: float, width: float, tint: Color) -> void:
	var visual = MeshInstance3D.new()
	var ring = TorusMesh.new()
	ring.inner_radius = radius - width
	ring.outer_radius = radius
	ring.rings = 48
	ring.ring_segments = 6
	visual.mesh = ring
	visual.material_override = _material(tint)
	visual.position.y = y
	visual.set_meta("warning_radius", radius)
	add_child(visual)

func _box(at: Vector3, size: Vector3, tint: Color) -> MeshInstance3D:
	var visual = MeshInstance3D.new()
	var mesh = BoxMesh.new()
	mesh.size = size
	visual.mesh = mesh
	visual.material_override = _material(tint)
	visual.position = at
	add_child(visual)
	return visual

func _material(tint: Color) -> StandardMaterial3D:
	var result = StandardMaterial3D.new()
	result.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	result.albedo_color = tint
	return result
