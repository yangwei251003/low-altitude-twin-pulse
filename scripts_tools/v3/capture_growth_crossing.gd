extends "res://scripts_tools/v3/capture_assets.gd"
## Real viewport / real host ability intents. Static poses, not human play.
const ShoreCapture = preload("res://scripts_tools/v3/capture_shore.gd")

func _run() -> void:
	var safe := false
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--qa-profile=qa_visual_"): safe=true
		if arg.begins_with("--capture-output="): output=arg.trim_prefix("--capture-output=")
	if not safe or DisplayServer.get_name()=="headless" or output.is_empty(): quit(2); return
	if DirAccess.make_dir_recursive_absolute(output)!=OK: quit(2); return
	var before:=_inputs()
	session=load("res://scenes/v3/main.tscn").instantiate()
	root.add_child(session)
	if not session.start_flight("solo") or not session._load_region("F1"): quit(1); return
	session.set_process(false)
	session.set_physics_process(false)
	session.inputs.set_process(false)
	session.inputs.set_physics_process(false)
	await _pose(Vector3(0,5,25),35)
	await _capture("01-before-growth-open-gap")
	await _place(Vector3(-24,5.2,29))
	for i in range(2): _ability("light","F1:mirror")
	for i in range(100):
		session.world.synchronize(session.entities,1.0/60.0)
		await physics_frame
	await _place(Vector3(-18,6.4,29))
	for i in range(2): _ability("growth","F1:growth")
	session.world.synchronize(session.entities,0.0)
	await _pose(Vector3(0,5,25),35)
	await _capture("02-grown-bearing-surface")
	await _place(Vector3(-14,2.5,20))
	_ability("charge","F1:relay")
	for i in range(100):
		session.world.synchronize(session.entities,1.0/60.0)
		await physics_frame
	await _pose(Vector3(0,5,25),35)
	await _capture("03-grown-open-gate")
	await _pose(Vector3(-14,5,25),18)
	await _capture("04-west-actual-terrace-join")
	await _pose(Vector3(13,4,26),18)
	await _capture("05-east-curved-descent")
	var valid: bool=before==_inputs() and session.stats.abilities==5 and session.stats.rejected_abilities==0 and session.world.growth_bridge.collision_layer==1 and session.world.gate_fraction>0.99
	var file:=FileAccess.open(output.path_join("capture.json"),FileAccess.WRITE)
	if file==null: quit(1); return
	file.store_string(JSON.stringify({"purpose":"Actual Compatibility viewport; five real host abilities; scripted static poses, no human play/performance acceptance.",
		"status":"replaceable graybox; final Blender approaches not yet integrated","valid":valid,"input_sha256":before,"inputs_unchanged":before==_inputs(),
		"shots":shots,"abilities":session.stats.abilities,"rejected":session.stats.rejected_abilities,
		"mechanisms":session.world.mechanism_snapshot(),"growth":session.entities["F1:growth"],
		"adapter":RenderingServer.get_video_adapter_name()},"\t"))
	file.close()
	print("GROWTH_CROSSING_CAPTURE ",JSON.stringify({"valid":valid,"shots":shots.size(),"output":output}))
	session.network.close()
	session.queue_free()
	await process_frame
	quit(0 if valid else 1)

func _ability(id: String,target: String) -> void:
	session.cooldowns[1]=0.0
	session._action_received(1,"ability",{"ability":id,"target_id":target})

func _inputs() -> Dictionary:
	var result: Dictionary={}
	for path in ShoreCapture.INPUTS + [
		"res://data/v3/terrain/f1_growth_crossing.json",
		"res://scripts/v3/world/twin_growth_crossing.gd",
		"res://assets/v3/fantasy_kit/rootstone_terrace.glb",
		"res://scripts_tools/v3/capture_growth_crossing.gd"
	]: result[path]=FileAccess.get_sha256(path)
	return result
