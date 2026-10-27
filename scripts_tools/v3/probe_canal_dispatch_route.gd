extends SceneTree
## Native query only, fresh private QA. No actor/device placements or actions.
const MAIN = preload("res://scenes/v3/main.tscn")
func _initialize() -> void: _run.call_deferred()
func _run() -> void:
	var profile := ""
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--qa-profile="): profile=arg.trim_prefix("--qa-profile=")
	if not profile.begins_with("qa_dispatch_route_") or profile!=profile.validate_filename() or DirAccess.dir_exists_absolute("user://profiles_v3/"+profile): quit(2); return
	var session: Node=MAIN.instantiate()
	root.add_child(session)
	if not session.start_flight("solo") or not session._load_region("I2"): quit(1); return
	await physics_frame
	await process_frame
	var body: FlightBodyV2=session.players[1]
	var points: Array[Vector3]=[Vector3(3.5,2.8,5.4),Vector3(3.5,3,1.9),Vector3(14.5,3,1.9),Vector3(14.5,3,6)]
	var rows: Array=[]
	var good := true
	var space: PhysicsDirectSpaceState3D=session.world.get_world_3d().direct_space_state
	# Native query positions only. An extra .22 arrival uncertainty plus .36
	# minimum braking envelope conservatively expands the original full hull.
	for extra: float in [0.0,.58]:
		var shape:=BoxShape3D.new()
		shape.size=Vector3(float(body.stats.width_m),float(body.stats.height_m),float(body.stats.length_m))+Vector3.ONE*(.38+extra*2.0)
		for index: int in range(points.size()-1):
			var q:=PhysicsShapeQueryParameters3D.new()
			q.shape=shape
			q.transform=Transform3D(Basis.IDENTITY,points[index])
			q.collision_mask=1|2|4|8|32
			q.exclude=[body.get_rid()]
			var occupied: Array=space.intersect_shape(q,1)
			q.motion=points[index+1]-points[index]
			var sweep: PackedFloat32Array=space.cast_motion(q)
			var ok: bool=occupied.is_empty() and sweep[0]==1.0 and sweep[1]==1.0
			good=good and ok
			rows.append({"hop":index+1,"extra_half_m":extra,"start":str(points[index]),"end":str(points[index+1]),"start_clear":occupied.is_empty(),"sweep":str(sweep),"ok":ok,"occupied":str(occupied[0].collider.get_path()) if not occupied.is_empty() else ""})
	var from: Vector3=points[-1]
	var to:=Vector3(13,3,6)
	var ray:=PhysicsRayQueryParameters3D.create(from,to,0xFFFFFFFF)
	ray.exclude=[body.get_rid()]
	var hit: Dictionary=space.intersect_ray(ray)
	good=good and hit.is_empty() and from.distance_to(to)<3.0
	print("DISPATCH_NATIVE_ROUTE_QUERY "+JSON.stringify({"good":good,"segments":rows,"marker_LOS_clear":hit.is_empty(),"marker_distance":from.distance_to(to),"scope":"geometry only; current actual37 nearest G remains an ordinary runtime check"}))
	session.active=false
	session.environment_save_gate.cancel("qa_geometry_query_teardown")
	session.audio.shutdown()
	session.network.close()
	var deadline: int=Time.get_ticks_usec()+1000000
	while not session.audio.shutdown_status().ready and Time.get_ticks_usec()<deadline: await process_frame
	good=good and session.audio.shutdown_status().ready
	if session.canal!=null: session.canal.clear()
	session.thermal_cargo.clear()
	session.free()
	await process_frame
	quit(0 if good else 1)
