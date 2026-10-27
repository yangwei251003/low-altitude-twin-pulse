extends Node2D
## Thin screen-space corners keep the pilot readable over light-colored armor.
var radius = 16.0
func _draw() -> void:
	for x in [-1.0, 1.0]:
		for y in [-1.0, 1.0]:
			var corner = Vector2(x, y) * radius
			var points = PackedVector2Array([corner - Vector2(x * 5, 0), corner, corner - Vector2(0, y * 5)])
			draw_polyline(points, Color("102a2c"), 4.0, true)
			draw_polyline(points, Color("b4eed9"), 1.5, true)
