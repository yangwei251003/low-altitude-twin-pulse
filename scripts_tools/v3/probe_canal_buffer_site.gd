extends SceneTree
## Native query only, fresh private QA. No actor/device placements or actions.
const MAIN = preload("res://scenes/v3/main.tscn")
func _initialize() -> void: _run.call_deferred()
func _run() -> void:
	var profile := ""
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--qa-profile="): profile=arg.trim_prefix("--qa-profile=")
	if not profile.begins_with("qa_buffer_view_") or profile!=profile.validate_filename() or DirAccess.dir_exists_absolute("user://profiles_v3/"+profile): quit(2); return
	var session: Node=MAIN.instantiate()
	root.add_child(session)
	if not session.start_flight("solo") or not session._load_region("I2"):
		print("BUFFER_LOAD_REJECTED "+JSON.stringify({"last_commit":session.last_commit_result,"message":session.interface.message.text,"world_errors":session.world.build_errors if is_instance_valid(session.world) else [],"canal_preflight":session.canal.module.bootstrap.preflight if session.canal!=null and is_instance_valid(session.canal.module) else []}))
		quit(1); return
	await physics_frame
	await process_frame
	var body: FlightBodyV2=session.players[1]
	var context: Dictionary=session.canal.module.context()
	var buffer: StaticBody3D=context.berths.north_buffer
	var native: Transform3D=PhysicsServer3D.body_get_state(buffer.get_rid(),PhysicsServer3D.BODY_STATE_TRANSFORM)
	var support: StaticBody3D=session.world.get_node("CanalBufferSideBay")
	var support_native: Transform3D=PhysicsServer3D.body_get_state(support.get_rid(),PhysicsServer3D.BODY_STATE_TRANSFORM)
	var actual: bool=support_native.origin.distance_to(Vector3(7,4.9,8))<.00001 and buffer.global_position.distance_to(Vector3(6,5,8))<.00001 and native.origin.distance_to(Vector3(6,5,8))<.00001
	var shape:=BoxShape3D.new()
	shape.size=Vector3(2,.5,2)
	var rows: Array=[]
	var good:=actual
	for point: Vector3 in [Vector3(6,5,8)]:
		var query:=PhysicsShapeQueryParameters3D.new()
		query.shape=shape
		query.transform=Transform3D(Basis.IDENTITY,point)
		query.exclude=[buffer.get_rid(),support.get_rid()]
		query.collision_mask=0xFFFFFFFF
		query.margin=.05
		var hits: Array=session.world.get_world_3d().direct_space_state.intersect_shape(query,8)
		var names: Array=[]
		for hit: Dictionary in hits: names.append(str(hit.collider.get_path()))
		good=good and hits.is_empty()
		rows.append({"candidate":str(point),"size":str(shape.size),"margin":.05,"hits":names})
	var access: Dictionary=session.shared_access.module.access_report()
	good=good and access.choice_ready and access.public_access and access.service_access
	print("BUFFER_NATIVE_SITE_QUERY "+JSON.stringify({"good":good,"rows":rows,"current_access":session.shared_access.module.access_report(),"scope":"fresh QA native query only; no static/rigid pose or game progress change"}))
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
