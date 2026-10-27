class_name RegionLayoutWorldUI
extends RefCounted
## Single source for physical land, navigation chart and regional infrastructure.
static var cache: Dictionary = {}

static func get_layout(id: String) -> Dictionary:
	if not cache.has(id):
		var path="res://data/worldui/"+id+".json"
		cache[id]=JSON.parse_string(FileAccess.get_file_as_string(path)) if FileAccess.file_exists(path) else {}
	return cache[id]

static func polygon(values: Array) -> PackedVector2Array:
	var result=PackedVector2Array()
	for p in values: result.append(Vector2(float(p[0]),float(p[1])))
	return result

static func terrain(data: Dictionary, point: Vector3) -> float:
	var result=-3.0
	for land in data.get("land",[]):
		if Geometry2D.is_point_in_polygon(Vector2(point.x,point.z),polygon(land.points)):result=maxf(result,float(land.height))
	return result

static func surface(data: Dictionary, point: Vector3, highest: bool=false) -> Dictionary:
	var height=terrain(data,point)
	var water=height<-.6
	var material="water" if water else "concrete"
	for road in data.get("roads",[]):
		if not bool(road.get("bridge",false)):continue
		var ps: Array=road.points
		for i in range(ps.size()-1):
			var a=Vector2(ps[i][0],ps[i][1]);var b=Vector2(ps[i+1][0],ps[i+1][1])
			var p=Vector2(point.x,point.z)
			var along=(p-a).dot(b-a)/maxf(.001,(b-a).length_squared())
			if along<0 or along>1:continue
			var near=Geometry2D.get_closest_point_to_segment(p,a,b)
			var h=lerpf(float(ps[i][2]),float(ps[i+1][2]),a.distance_to(near)/maxf(.01,a.distance_to(b)))
			if p.distance_to(near)<=float(road.width)*.5 and (highest or h<=point.y+.2) and h>height:
				height=h;water=false;material="bridge"
	return {"valid":true,"height":height,"normal":Vector3.UP,"material":material,"water":water,"water_height":float(data.get("water_level",-.6)),"surface_velocity":Vector3.ZERO}

static func water_at(data: Dictionary, point: Vector3) -> Dictionary:
	var s=surface(data,point)
	return {"over_water":bool(s.water),"height":float(data.get("water_level",-.6)),"bed":-3.0}

static func nearest_route(data: Dictionary, point: Vector3) -> Vector3:
	var best=point;var distance=INF
	for road in data.get("roads",[]):
		for i in range(road.points.size()-1):
			var a=road.points[i];var b=road.points[i+1]
			var p=Geometry2D.get_closest_point_to_segment(Vector2(point.x,point.z),Vector2(a[0],a[1]),Vector2(b[0],b[1]))
			var d=p.distance_to(Vector2(point.x,point.z))
			if d<distance:distance=d;best=Vector3(p.x,point.y,p.y)
	return best
