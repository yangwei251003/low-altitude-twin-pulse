class_name FlightNavigation
extends RefCounted

var grid=AStarGrid2D.new()
var world_bounds: Rect2
const CELL=2.0
var search_count=0

func configure(bounds: Rect2, obstacles: Array[Rect2]) -> void:
	world_bounds=bounds
	grid.region=Rect2i(Vector2i.ZERO,Vector2i(ceil(bounds.size.x/CELL),ceil(bounds.size.y/CELL)))
	grid.cell_size=Vector2.ONE*CELL
	grid.offset=bounds.position+Vector2.ONE*CELL*.5
	grid.diagonal_mode=AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	grid.default_compute_heuristic=AStarGrid2D.HEURISTIC_OCTILE
	grid.default_estimate_heuristic=AStarGrid2D.HEURISTIC_OCTILE
	grid.update()
	for x in range(grid.region.size.x):
		for y in range(grid.region.size.y):
			var id=Vector2i(x,y);var pos=grid.get_point_position(id)
			for obstacle in obstacles:
				if obstacle.has_point(pos):grid.set_point_solid(id);break

func cell(pos: Vector3) -> Vector2i:
	var local=(Vector2(pos.x,pos.z)-world_bounds.position)/CELL
	return Vector2i(clampi(int(local.x),0,grid.region.size.x-1),clampi(int(local.y),0,grid.region.size.y-1))

func nearest_free(id: Vector2i) -> Vector2i:
	if not grid.is_point_solid(id):return id
	for radius in range(1,8):
		for x in range(-radius,radius+1):
			for y in range(-radius,radius+1):
				var p=id+Vector2i(x,y)
				if grid.is_in_boundsv(p) and not grid.is_point_solid(p):return p
	return id

func path(from: Vector3,to: Vector3) -> PackedVector2Array:
	search_count+=1
	var a=nearest_free(cell(from));var b=nearest_free(cell(to))
	if grid.is_point_solid(a) or grid.is_point_solid(b):return PackedVector2Array()
	return grid.get_point_path(a,b)
