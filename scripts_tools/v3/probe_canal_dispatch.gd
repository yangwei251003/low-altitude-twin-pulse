extends SceneTree
## Native query only, fresh private QA. No actor/device placements or actions.
const MAIN = preload("res://scenes/v3/main.tscn")
func _initialize() -> void: _run.call_deferred()
func _run() -> void:
	var profile := ""
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--qa-profile="): profile=arg.trim_prefix("--qa-profile=")
	if not profile.begins_with("qa_dispatch_view_") or profile!=profile.validate_filename() or DirAccess.dir_exists_absolute("user://profiles_v3/"+profile): quit(2); return
	var session: Node=MAIN.instantiate()
	root.add_child(session)
	if not session.start_flight("solo") or not session._load_region("I2"): quit(1); return
	await physics_frame
	await process_frame
	var body: FlightBodyV2=session.players[1]
	var shape:=BoxShape3D.new()
	shape.size=Vector3(float(body.stats.width_m),float(body.stats.height_m),float(body.stats.length_m))+Vector3.ONE*.38
	var rows: Array=[]
	for point: Vector3 in [Vector3(13,3,4),Vector3(12.8,3.2,3.9),Vector3(13,3,6),Vector3(13,3,8),Vector3(14,3,4.2),Vector3(11.3,3,6),Vector3(14.5,3,6),Vector3(13,3.7,4.1)]:
		var query:=PhysicsShapeQueryParameters3D.new()
		query.shape=shape
		query.transform=Transform3D(Basis.IDENTITY,point)
		query.collision_mask=1|2|4|8|32
		query.exclude=[body.get_rid()]
		var hits: Array=session.world.get_world_3d().direct_space_state.intersect_shape(query,4)
		var names: Array=[]
		for hit: Dictionary in hits: names.append(str(hit.collider.get_path()))
		query.transform.origin=Vector3(point.x,3,2.5)
		query.motion=point-query.transform.origin
		var sweep: PackedFloat32Array=session.world.get_world_3d().direct_space_state.cast_motion(query)
		rows.append({"point":str(point),"hull_hits":names,"sweep_z2p5":str(sweep),"fresh_nearest_diagnostic":session.story.nearest(point)})
	print("DISPATCH_NATIVE_QUERY "+JSON.stringify(rows))
	var good:=true
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
