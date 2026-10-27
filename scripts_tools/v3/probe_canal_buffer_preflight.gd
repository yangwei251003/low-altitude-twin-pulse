extends SceneTree
## Native query only, fresh private QA. No actor/device placements or actions.
const MAIN = preload("res://scenes/v3/main.tscn")
func _initialize() -> void: _run.call_deferred()
func _run() -> void:
	var profile := ""
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--qa-profile="): profile=arg.trim_prefix("--qa-profile=")
	if not profile.begins_with("qa_buffer_diag_") or profile!=profile.validate_filename() or DirAccess.dir_exists_absolute("user://profiles_v3/"+profile): quit(2); return
	var session: Node=MAIN.instantiate()
	root.add_child(session)
	session.canal_runtime_enabled=false
	if not session.start_flight("solo") or not session._load_region("I2"): quit(1); return
	await physics_frame
	await process_frame
	var body: FlightBodyV2=session.players[1]
	var boot=preload("res://scripts/v3/gameplay/canal/canal_transport_executor/canal_transport_bootstrap.gd")
	var executor=preload("res://scripts/v3/gameplay/canal/canal_transport_executor/canal_transport_executor.gd")
	var rows: Array=[]
	for id: String in executor.BERTH_POINTS: rows.append(boot._site_preflight(session.world,id,executor.BERTH_POINTS[id]))
	print("BUFFER_NATIVE_PREFLIGHT_DIAG "+JSON.stringify({"rows":rows,"access":session.shared_access.module.access_report(),"support_node":str(session.world.get_node("CanalBufferSideBay").global_transform),"scope":"fresh query fixture disables Canal installer only so its failed preflight can be inspected after a real native step; not normal factory acceptance"}))
	var good: bool=rows.all(func(row: Dictionary): return row.ok)
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
