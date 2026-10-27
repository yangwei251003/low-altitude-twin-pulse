extends SceneTree
## Isolated geometry planning fixture only. No Session, Story, Store or pilot.
## Explicit display poses identify candidate sight lines, never combat evidence.
const World = preload("res://scripts/v3/twin_test_world.gd")
const Catalog = preload("res://scripts/v2/catalog.gd")
var world: Node3D
var output := ""

func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--output="): output=arg.trim_prefix("--output=")
	_run.call_deferred()

func _run() -> void:
	world=World.new()
	root.add_child(world)
	world.build("I1")
	if not world.whale_ready():
		push_error("Real whale import required")
		quit(1)
		return
	var points: Array[Vector3]=[]
	var stats: Dictionary=Catalog.resolve_build(Catalog.default_build("tr01")).derived
	var hull:=BoxShape3D.new()
	hull.size=Vector3(stats.width_m,stats.height_m,stats.length_m)+Vector3.ONE*.38
	for x in range(0,29):
		for y in [9.0,10.0,11.0,12.0,13.0,14.0,15.0,16.0]:
			for z in range(-37,-24): points.append(Vector3(x,y,z))
	var rows: Array=[]
	var states: Array=[
		{"name":"open_sides","view":{"phase":"shielded","nodes_open":true,"nodes":{"port":{"powered":false},"starboard":{"powered":true}}}},
		{"name":"core_exposed","view":{"phase":"exposed","nodes_open":false,"nodes":{"port":{"powered":false},"starboard":{"powered":false}}}}
	]
	for fixture: Dictionary in states:
		world.set_boss_state(fixture.view)
		await physics_frame
		await physics_frame
		await process_frame
		var native: Dictionary={}
		for body: PhysicsBody3D in world.art_whale.collision_bodies():
			native[str(body.name)]=PhysicsServer3D.body_get_state(body.get_rid(),PhysicsServer3D.BODY_STATE_TRANSFORM).is_equal_approx(body.global_transform)
		for point: Vector3 in points:
			var shape_query:=PhysicsShapeQueryParameters3D.new()
			shape_query.shape=hull
			shape_query.transform=Transform3D(Basis.IDENTITY,point)
			shape_query.collision_mask=1|8
			var clear: bool=world.get_world_3d().direct_space_state.intersect_shape(shape_query,1).is_empty()
			var hits: Dictionary={}
			var ranges: Dictionary={}
			for part: String in ["port","starboard","core"]:
				var target: Vector3=world.boss_parts[part].global_position
				var query:=PhysicsRayQueryParameters3D.create(point,target,1|8)
				var hit: Dictionary=world.get_world_3d().direct_space_state.intersect_ray(query)
				hits[part]=str(hit.collider.get_meta("entity_id","")) if not hit.is_empty() else ""
				ranges[part]=point.distance_to(target)
			rows.append({"fixture":fixture.name,"point":[point.x,point.y,point.z],"hull_clear":clear,"hits":hits,"ranges":ranges})
		for value in native.values():
			if not value:
				push_error("Fixture native hatch has not settled")
				quit(1)
				return
	var matches: Array=[]
	for index in points.size():
		var sides: Dictionary=rows[index]
		var core: Dictionary=rows[index+points.size()]
		if sides.hull_clear and core.hull_clear and sides.hits.port=="boss:port" and sides.hits.starboard=="boss:starboard" and sides.ranges.port<=10.001 and sides.ranges.starboard<=10.001 and core.hits.core=="boss:core":
			matches.append({"point":sides.point,"ranges":sides.ranges})
	var side_core: Dictionary={"port":[],"starboard":[]}
	for index in points.size():
		var sides: Dictionary=rows[index]
		var core: Dictionary=rows[index+points.size()]
		for side: String in ["port","starboard"]:
			if sides.hull_clear and core.hull_clear and sides.hits[side]=="boss:"+side and sides.ranges[side]<=10.001 and core.hits.core=="boss:core":
				side_core[side].append({"point":sides.point,"ranges":sides.ranges})
	var report: Dictionary={"matches":matches,"side_core_candidates":side_core,"rows":rows,"sampled_points":points.size(),"scope":"Isolated real original I1 world/imported armor, explicit two view-state fixtures, virtual ray origins and static default-build hull queries. No aircraft movement, Encounter, Story, Store, progression or playable-combat proof; candidate planning only. A real normal Pilot run must still reach and use any chosen point."}
	if not output.is_empty():
		var file=FileAccess.open(output,FileAccess.WRITE)
		if file!=null: file.store_string(JSON.stringify(report))
	print("WHALE_VANTAGE_CANDIDATES "+JSON.stringify({"count":matches.size(),"port_core":side_core.port.size(),"starboard_core":side_core.starboard.size(),"points":points.size()}))
	world.queue_free()
	await process_frame
	quit(0)
