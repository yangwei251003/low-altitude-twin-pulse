extends SceneTree

var failures: Array[String] = []
var reports: Array[Dictionary] = []
var checks = 0

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var content = CatalogV2.content()
	var widest = Vector3.ZERO
	var widest_id = ""
	for id in CatalogV2.airframes():
		var build = CatalogV2.default_build(str(id))
		build.slots.utility = "reinforced_guard"
		var resolved = CatalogV2.resolve_build(build)
		if resolved.valid and float(resolved.derived.width_m)>widest.x:
			widest = Vector3(resolved.derived.width_m,resolved.derived.height_m,resolved.derived.length_m)
			widest_id = str(id)
	var shape = BoxShape3D.new()
	shape.size = widest
	var query = PhysicsShapeQueryParameters3D.new()
	query.shape = shape
	query.collision_mask = 1|32
	for region in content.regions:
		var world = RegionWorldV2.new()
		world.configure(region,false,{})
		_expect(world.wind_strength_mps2 == float(CatalogV2.content().catalog.wind_strength_mps2.get(str(region.id),0.0)),str(region.id)+" cached wind matches authoritative catalog")
		var sample = world.wind_acceleration(Vector3(120,4,130),17.25)
		_expect(sample == world.wind_acceleration(Vector3(120,4,130),17.25),str(region.id)+" wind replay is deterministic")
		world.night = true
		_expect(sample == world.wind_acceleration(Vector3(120,4,130),17.25),str(region.id)+" night does not secretly increase wind")
		world.night = false
		_expect(world.wind_acceleration(Vector3(120,0.24,130),17.25,0.24).is_zero_approx(),str(region.id)+" grounded service zone is sheltered")
		world.wind_enabled = false
		_expect(world.wind_acceleration(Vector3(120,4,130),17.25).is_zero_approx(),str(region.id)+" first-flight wind can be disabled")
		world.wind_enabled = true
		root.add_child(world)
		for x in range(6):
			for z in range(5):
				if not world.chunks.has(Vector2i(x,z)): world._load_chunk(Vector2i(x,z))
		await physics_frame
		await physics_frame
		var space = world.get_world_3d().direct_space_state
		var targets: Array[Dictionary] = []
		for poi in region.pois: targets.append({"id":str(poi.id),"p":world.poi_position(str(poi.id))+Vector3.UP*2.8})
		for job in content.missions+content.airframe_challenges+content.mode_configs:
			if job.region_id!=region.id: continue
			for stage in job.get("stages",[job]):
				for action in stage.get("actions",[])+stage.get("optional_actions",[]):
					var offset: Array = action.get("offset_xz_m",[0,0])
					var p = world.poi_position(str(action.poi_id))+Vector3(offset[0],0,offset[1])
					p.y=world.surface_height(p)+float(action.get("target_height_m",2.8))
					targets.append({"id":str(stage.id)+":"+str(action.type)+":"+str(action.poi_id),"p":p})
		reports.append(_check_routes(world,space,query,targets))
		world.update_stream(Vector3(50,3,50),true)
		world.update_stream(Vector3(150,3,50))
		_expect(world.chunks.has(Vector2i(1,0)) and world.chunks.has(Vector2i(2,0)),str(region.id)+" current and next approach collision remain ready while corners load")
		_expect(not world.pending_chunks.is_empty(),str(region.id)+" outer buffer construction is staggered")
		for tick in range(25): world.update_stream(Vector3(150,3,50))
		_expect(world.pending_chunks.is_empty() and world.retained_chunks.all(func(cell): return world.chunks.has(cell)),str(region.id)+" queued collision completes long before a 100m approach")
		world.pin_pois([str(region.pois[-1].id)])
		world.update_stream(Vector3(150,3,50))
		_expect(world.pinned.all(func(cell): return world.chunks.has(cell)),str(region.id)+" pinned mission chunks bypass the background queue")
		world.queue_free()
		await process_frame
		await process_frame
	var report = {"suite":"world_scene_physics_fixture","engine":Engine.get_version_info().string,"source_sha256":content.get("_source_sha256",""),"evidence":"Actual region colliders, terrain-relative clearance, and swept maximum-airframe graph paths from spawn to every task target; static geometry proof only, not human play or graphics evidence","widest_frame":widest_id,"envelope_m":[widest.x,widest.y,widest.z],"checks":checks,"failed":failures.size(),"failures":failures,"regions":reports}
	var file = FileAccess.open("res://artifacts/v2/world_geometry.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(report,"  "))
	print(JSON.stringify(report))
	quit(0 if failures.is_empty() else 1)

func _expect(value: bool, label: String) -> void:
	checks += 1
	if not value: failures.append(label)

# A 3D two-layer graph preserves cliffs, decks and cranes. Empty endpoints alone
# are insufficient: every accepted edge is swept with the actual largest frame.
func _shape_clear(space: PhysicsDirectSpaceState3D, query: PhysicsShapeQueryParameters3D, point: Vector3) -> bool:
	query.transform=Transform3D(Basis.IDENTITY,point);query.motion=Vector3.ZERO
	return space.intersect_shape(query,1).is_empty()

func _sweep_clear(space: PhysicsDirectSpaceState3D, query: PhysicsShapeQueryParameters3D, a: Vector3, b: Vector3) -> bool:
	query.transform=Transform3D(Basis.IDENTITY,a);query.motion=b-a
	var fractions=space.cast_motion(query)
	query.motion=Vector3.ZERO
	return fractions.size()==2 and float(fractions[0])>=.99999

func _near_nodes(point: Vector3) -> Array[Vector3i]:
	var nodes: Array[Vector3i]=[]
	var x=floori(point.x/5);var z=floori(point.z/5)
	for dx in range(-1,2):
		for dz in range(-1,2):
			for layer in 2:nodes.append(Vector3i(x+dx,z+dz,layer))
	return nodes

func _check_routes(world: RegionWorldV2,space: PhysicsDirectSpaceState3D,query: PhysicsShapeQueryParameters3D,targets: Array[Dictionary]) -> Dictionary:
	var region_id=str(world.region.id)
	var highest_land=0.0
	for land in world.layout.get("land",[]):highest_land=maxf(highest_land,float(land.height))
	var frame=FlightBodyV2.new()
	var ceiling=float(frame.max_altitude);frame.free()
	var cruise_height=minf(ceiling-2.0,maxf(16.0,highest_land+6.0))
	_expect(cruise_height>highest_land+float(query.shape.size.y)*.5,region_id+" cruise route lies above terrain and below aircraft ceiling")
	var nodes: Dictionary={}
	var low_count=0;var high_count=0
	for x in range(120):
		for z in range(100):
			var low=Vector3(x*5+2.5,0,z*5+2.5)
			low.y=world.surface_height(low)+2.8
			if low.y<=ceiling and _shape_clear(space,query,low):nodes[Vector3i(x,z,0)]=low;low_count+=1
			var high=Vector3(low.x,cruise_height,low.z)
			if _shape_clear(space,query,high):nodes[Vector3i(x,z,1)]=high;high_count+=1
	var spawn=world.poi_position(str(world.region.spawn_poi))+Vector3.UP*1.2
	var spawn_clear=_shape_clear(space,query,spawn)
	_expect(spawn_clear,region_id+" largest frame can occupy the real launch point")
	var queue: Array[Vector3i]=[]
	var visited: Dictionary={}
	if spawn_clear:
		for node in _near_nodes(spawn):
			if nodes.has(node) and _sweep_clear(space,query,spawn,nodes[node]):visited[node]=true;queue.append(node)
	_expect(not queue.is_empty(),region_id+" real launch point has a swept connection to the flight graph")
	var head=0
	var steps=[Vector3i(-1,0,0),Vector3i(1,0,0),Vector3i(0,-1,0),Vector3i(0,1,0)]
	while head<queue.size():
		var node=queue[head];head+=1
		var neighbors: Array[Vector3i]=[Vector3i(node.x,node.y,1-node.z)]
		for step in steps:neighbors.append(node+step)
		for next in neighbors:
			if nodes.has(next) and not visited.has(next) and _sweep_clear(space,query,nodes[node],nodes[next]):
				visited[next]=true;queue.append(next)
	var low_reached=0;var high_reached=0
	for node in visited:
		if node.z==0:low_reached+=1
		else:high_reached+=1
	var low_ratio=float(low_reached)/maxi(1,low_count)
	var high_ratio=float(high_reached)/maxi(1,high_count)
	_expect(low_count>=8400,region_id+" at least 70 percent of terrain-relative low flight cells are physically clear")
	_expect(float(low_reached)/12000.0>=.70,region_id+" at least 70 percent of all low flight cells have a swept route from launch")
	_expect(high_ratio>=.95,region_id+" at least 95 percent of legal cruise cells have a swept route from launch")
	var blocked: Array[String]=[];var disconnected: Array[String]=[]
	for target in targets:
		var clear=_shape_clear(space,query,target.p)
		_expect(clear,"target clear: "+target.id)
		if not clear:blocked.append(target.id)
		var connected=false
		if clear:
			for node in _near_nodes(target.p):
				if visited.has(node) and _sweep_clear(space,query,nodes[node],target.p):connected=true;break
		_expect(connected,"target has a swept route from launch: "+target.id)
		if not connected:disconnected.append(target.id)
	return {"region_id":region_id,"grid_m":5,"cells":12000,"low_height_above_surface_m":2.8,"low_clear_cells":low_count,"connected_low_cells":low_reached,"low_connectivity":low_ratio,"connected_map_fraction":float(low_reached)/12000.0,"cruise_height_m":cruise_height,"cruise_clear_cells":high_count,"connected_cruise_cells":high_reached,"cruise_connectivity":high_ratio,"targets":targets.size(),"blocked_targets":blocked,"disconnected_targets":disconnected,"streamed_chunks":world.chunks.size()}
