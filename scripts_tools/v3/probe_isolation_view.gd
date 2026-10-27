extends SceneTree
## Native query only, fresh private QA. No actor/device placements or actions.
const MAIN = preload("res://scenes/v3/main.tscn")
func _initialize() -> void: _run.call_deferred()
func _run() -> void:
	var profile := ""
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--qa-profile="): profile=arg.trim_prefix("--qa-profile=")
	if not profile.begins_with("qa_isolation_view_") or profile!=profile.validate_filename() or DirAccess.dir_exists_absolute("user://profiles_v3/"+profile): quit(2); return
	var session: Node=MAIN.instantiate()
	root.add_child(session)
	if not session.start_flight("solo") or not session._load_region("I2"): quit(1); return
	await physics_frame
	await process_frame
	var body: FlightBodyV2=session.players[1]
	var target: Vector3=session.trial.module.entity_position("I2:trial_isolation_handle")
	var shape := BoxShape3D.new()
	shape.size=Vector3(float(body.stats.width_m),float(body.stats.height_m),float(body.stats.length_m))+Vector3.ONE*.38
	var rows: Array=[]
	# A western raised ray still crosses the stop's TOP near its inner X face.
	# Approach from southwest instead: at that face, z must exceed its south
	# face -6.76. For dx2.8 and inner gap .115, dz>2.2 clears the whole stop.
	for offset: Vector3 in [Vector3(-2.8,1.25,1.05),Vector3(-2.8,1.25,2.7),Vector3(-2.8,1.4,3.1),Vector3(-3.2,1.25,3.1)]:
		var point:=target+offset
		var ray:=PhysicsRayQueryParameters3D.create(point,target,0xFFFFFFFF)
		ray.exclude=[body.get_rid()]
		var hit: Dictionary=session.world.get_world_3d().direct_space_state.intersect_ray(ray)
		var hull:=PhysicsShapeQueryParameters3D.new()
		hull.shape=shape
		hull.transform=Transform3D(Basis.IDENTITY,point)
		hull.collision_mask=1|2|4|8|32
		hull.exclude=[body.get_rid()]
		var clear: bool=session.world.get_world_3d().direct_space_state.intersect_shape(hull,1).is_empty()
		var start:=Vector3(14.8,2.8,-5)
		hull.transform=Transform3D(Basis.IDENTITY,start)
		hull.motion=point-start
		var sweep: PackedFloat32Array=session.world.get_world_3d().direct_space_state.cast_motion(hull)
		rows.append({"offset":str(offset),"hull_clear":clear,"sweep_fraction":str(sweep),"first_id":str(hit.collider.get_meta("entity_id","")) if hit.has("collider") else "","first_path":str(hit.collider.get_path()) if hit.has("collider") else "","first_point":str(hit.get("position")),"actual_handle":str(target)})
	print("ISOLATION_NATIVE_VIEW_QUERY "+JSON.stringify(rows))
	var good: bool=rows.slice(1).all(func(row: Dictionary): return row.hull_clear and row.first_id=="I2:trial_isolation_handle" and row.sweep_fraction=="[1.0, 1.0]")
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
