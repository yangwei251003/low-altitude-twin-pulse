extends RefCounted
## Bounded QA-only route search with native full-hull collision queries.
## Only returns waypoints. Never moves a body or advances simulation/progress.
const LEVELS := [1.4,1.8,2.2,2.8,4.0,5.5,7.0,10.0,14.0,18.0,23.0,25.0]
const STEP := 1.5
var driver: Node
var goal := Vector3.ZERO
var shape: BoxShape3D
var cache: Dictionary = {}
var edges: Dictionary = {}
var bounds: Array = []
var opened: Array = []
var score: Dictionary = {}
var came: Dictionary = {}
var expanded := 0
var levels: Array = LEVELS.duplicate()

func find(owner_driver: Node, target: Vector3, region_bounds: Array) -> Array:
	driver=owner_driver;goal=target;bounds=region_bounds
	shape=BoxShape3D.new()
	var stats: Dictionary=driver._body().stats
	shape.size=Vector3(float(stats.width_m),float(stats.height_m),float(stats.length_m))+Vector3.ONE*.38
	var start: Vector3=driver._body().global_position
	for height: float in [start.y,goal.y]:
		var close:=false
		for level: float in levels:
			if absf(height-level)<.25:close=true;break
		if not close:levels.append(height)
	levels.sort()
	var centre:=Vector3i(roundi(start.x/STEP),0,roundi(start.z/STEP))
	for x in range(centre.x-1,centre.x+2):
		for z in range(centre.z-1,centre.z+2):
			for y in range(levels.size()):
				var cell:=Vector3i(x,y,z)
				var at:=_point(cell)
				if at.distance_to(start)>6 or not _clear(cell) or not _segment(start,at):continue
				score[cell]=start.distance_to(at)
				_push({"cell":cell,"cost":score[cell],"rank":score[cell]+at.distance_to(goal)})
	var reached:=false
	var finish:=Vector3i.ZERO
	var visited: Dictionary={}
	while not opened.is_empty() and expanded<5000 and driver._healthy():
		var item: Dictionary=_pop()
		var cell: Vector3i=item.cell
		if visited.has(cell):continue
		visited[cell]=true
		expanded+=1
		var at:=_point(cell)
		if at.distance_to(goal)<6 and _segment(at,goal):reached=true;finish=cell;break
		for delta: Vector3i in [Vector3i(1,0,0),Vector3i(-1,0,0),Vector3i(0,0,1),Vector3i(0,0,-1),Vector3i(0,1,0),Vector3i(0,-1,0),Vector3i(1,0,1),Vector3i(1,0,-1),Vector3i(-1,0,1),Vector3i(-1,0,-1)]:
			var next:=cell+delta
			if visited.has(next) or next.y<0 or next.y>=levels.size() or not _clear(next):continue
			var there:=_point(next)
			var distance: float=float(score[cell])+at.distance_to(there)
			if distance>=float(score.get(next,INF)) or not _segment(at,there):continue
			score[next]=distance;came[next]=cell
			_push({"cell":next,"cost":distance,"rank":distance+there.distance_to(goal)})
		if expanded%160==0:await driver._next()
	if not reached:
		driver._event("native_route_search_no_candidate",{"expanded":expanded,"goal":goal,"scope":"bounded grid only, not proof that all player routes are impossible"})
		return []
	var raw: Array=[goal,_point(finish)]
	var cursor:=finish
	while came.has(cursor):cursor=came[cursor];raw.append(_point(cursor))
	raw.append(start);raw.reverse()
	var path: Array=[]
	var at_index:=0
	while at_index<raw.size()-1:
		var next:=at_index+1
		for index in range(raw.size()-1,at_index,-1):
			if _segment(raw[at_index],raw[index]):next=index;break
		path.append(raw[next]);at_index=next
	driver._event("native_route_search",{"expanded":expanded,"waypoints":path,"goal":goal})
	return path

func _point(cell: Vector3i) -> Vector3:
	return Vector3(float(cell.x)*STEP,float(levels[cell.y]),float(cell.z)*STEP)

func _clear(cell: Vector3i) -> bool:
	if cache.has(cell):return cache[cell]
	var at:=_point(cell)
	var ok: bool=at.x>float(bounds[0])+1.7 and at.x<float(bounds[3])-1.7 and at.z>float(bounds[2])+1.7 and at.z<float(bounds[5])-1.7
	if ok:
		var query:=PhysicsShapeQueryParameters3D.new()
		query.shape=shape;query.transform=Transform3D(Basis.IDENTITY,at);query.collision_mask=1|2|4|8|32;query.exclude=[driver._body().get_rid()]
		ok=driver.session.world.get_world_3d().direct_space_state.intersect_shape(query,1).is_empty()
	cache[cell]=ok;return ok

func _segment(from: Vector3,to: Vector3) -> bool:
	var key: Array=[from,to]
	if edges.has(key):return edges[key]
	var query:=PhysicsShapeQueryParameters3D.new()
	query.shape=shape;query.transform=Transform3D(Basis.IDENTITY,from);query.motion=to-from
	query.collision_mask=1|2|4|8|32;query.exclude=[driver._body().get_rid()]
	var space: PhysicsDirectSpaceState3D=driver.session.world.get_world_3d().direct_space_state
	var occupied:=not space.intersect_shape(query,1).is_empty()
	var result: PackedFloat32Array=space.cast_motion(query)
	var ok:=not occupied and result.size()==2 and result[0]>=.999
	edges[key]=ok;return ok

func _push(item: Dictionary) -> void:
	opened.append(item)
	var index:=opened.size()-1
	while index>0:
		var parent: int=(index-1)/2
		if float(opened[parent].rank)<=float(item.rank):break
		opened[index]=opened[parent];index=parent
	opened[index]=item

func _pop() -> Dictionary:
	var result: Dictionary=opened[0]
	var last: Dictionary=opened.pop_back()
	if opened.is_empty():return result
	var index:=0
	while index*2+1<opened.size():
		var child:=index*2+1
		if child+1<opened.size() and float(opened[child+1].rank)<float(opened[child].rank):child+=1
		if float(last.rank)<=float(opened[child].rank):break
		opened[index]=opened[child];index=child
	opened[index]=last;return result
