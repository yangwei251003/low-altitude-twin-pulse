extends SceneTree
## Native query only, fresh private QA. No actor/device placements or actions.
const MAIN = preload("res://scenes/v3/main.tscn")
func _initialize() -> void: _run.call_deferred()
func _run() -> void:
	var profile := ""
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--qa-profile="): profile=arg.trim_prefix("--qa-profile=")
	if not profile.begins_with("qa_gauge_view_") or profile!=profile.validate_filename() or DirAccess.dir_exists_absolute("user://profiles_v3/"+profile): quit(2); return
	var session: Node=MAIN.instantiate()
	root.add_child(session)
	if not session.start_flight("solo") or not session._load_region("I2"): quit(1); return
	await physics_frame
	await process_frame
	var body: FlightBodyV2=session.players[1]
	var points: Array[Vector3]=[Vector3(14.8,2.8,-5),Vector3(14.8,2.8,1.2),Vector3(18,2.8,1.2),Vector3(18,2.6,1.2),Vector3(16.1,2.6,1.2),Vector3(16.1,1.7,1.2),Vector3(19.9,1.7,1.2),Vector3(14.8,1.7,1.2),Vector3(14.8,2.8,1.2),Vector3(14.8,2.8,-5)]
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
	var station: Node=session.trial.module.station
	var gauges: Array=[]
	for pair: Array in [["A",Vector3(16.1,1.7,1.2),"I2:trial_receiver_a","I2:trial_gauge_a"],["B",Vector3(19.9,1.7,1.2),"I2:trial_receiver_b","I2:trial_gauge_b"]]:
		var spec: Dictionary=station._tank(pair[2])
		var front: Vector3=station._window_center(spec)+Vector3.BACK*float(spec.wall_m)*.5
		var hits:=0
		var central:=false
		var rays: Array=[]
		for offset: Vector2 in [Vector2.ZERO,Vector2(-.09,-.15),Vector2(.09,-.15),Vector2(-.09,.15),Vector2(.09,.15)]:
			var point: Vector3=station.to_global(front+Vector3(offset.x,offset.y,0))
			var sight: Vector3=pair[1]-point
			var ray:=PhysicsRayQueryParameters3D.create(pair[1],point-sight.normalized()*.002,1|2|4|8|32)
			ray.exclude=[body.get_rid()]
			var hit: Dictionary=space.intersect_ray(ray)
			var ok: bool=sight.length()<=4.5 and sight.normalized().dot(Vector3.BACK)>=.35 and hit.get("rid")==station.window_bodies[pair[2]].get_rid()
			if ok: hits+=1
			if offset==Vector2.ZERO: central=ok
			rays.append({"offset":str(offset),"distance":sight.length(),"ok":ok,"first":str(hit.collider.get_path()) if hit.has("collider") else ""})
		var nearest: String=session.story.nearest(pair[1])
		# Fresh QA has no natural stage32, so nearest may be gated by story;
		# retain it as diagnostic. The real resumed observer rechecks it before G.
		good=good and central and hits>=3
		gauges.append({"label":pair[0],"central":central,"hits":hits,"nearest_fresh_QA_diagnostic":nearest,"rays":rays})
	print("GAUGE_NATIVE_ROUTE_QUERY "+JSON.stringify({"good":good,"segments":rows,"gauges":gauges,"scope":"native geometry only; no poses/actions/progress and no natural-flight claim"}))
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
