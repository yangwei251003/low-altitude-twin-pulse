extends SceneTree

var failures: Array[String] = []
var reports: Array[Dictionary] = []
var checks = 0
var world: RegionWorldV2
var pilot: FlightBodyV2
var combat: CombatV2
var runner: TaskRunnerV2
var stage_success = false
var stage_failure = ""
var scene: Node3D
var ticks = 0

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var content = CatalogV2.content()
	await _setup(content.regions[0],"tr01")
	await _negative_predicates()
	await _dispose()
	for region in content.regions:
		for job in content.missions+content.airframe_challenges+content.mode_configs:
			if job.region_id!=region.id: continue
			await _setup(region,"hx02" if str(job.id).begins_with("salvage:") else str(job.get("airframe_id","tr01")))
			for stage in job.get("stages",[job]):
				stage_success = false
				stage_failure = ""
				runner.start_stage(stage)
				var completed = await _drive_stage()
				_expect(completed,str(stage.id)+" predicates complete: "+stage_failure)
				reports.append({"id":stage.id,"completed":completed,"actions":stage.actions.size(),"action_index":runner.action_index,"failure":stage_failure,"metrics":runner.record_metrics()})
				if not completed: break
				if not stage.get("optional_actions",[]).is_empty():
					stage_success = false
					stage_failure = ""
					runner.start_stage(stage,true)
					var optional_completed = await _drive_stage()
					_expect(optional_completed,str(stage.id)+" optional predicates complete")
					reports.append({"id":str(stage.id)+":optional","completed":optional_completed,"actions":stage.optional_actions.size(),"failure":stage_failure,"metrics":runner.record_metrics()})
			await _dispose()
	var report = {"suite":"task_scene_action_predicates","engine":Engine.get_version_info().string,"source_sha256":content.get("_source_sha256",""),"evidence":"Automated scene fixture: sets body positions and commands, equips legal tools, removes enemies through damage. Does not call _complete_action or claim manual gameplay, flight-route traversal, service UI, timing feasibility, or graphics quality.","checks":checks,"failed":failures.size(),"failures":failures,"fixture_ticks":ticks,"jobs":reports}
	var file = FileAccess.open("res://artifacts/v2/tasks_predicates.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(report,"  "))
	print(JSON.stringify({"suite":report.suite,"checks":checks,"failed":failures.size(),"failures":failures,"jobs":reports.size(),"fixture_ticks":ticks}))
	quit(0 if failures.is_empty() else 1)

func _setup(region: Dictionary, frame_id: String) -> void:
	scene = Node3D.new()
	root.add_child(scene)
	world = RegionWorldV2.new()
	world.configure(region,false,{})
	scene.add_child(world)
	pilot = FlightBodyV2.new()
	pilot.configure(CatalogV2.resolve_build(CatalogV2.default_build(frame_id)))
	pilot.freeze = true
	pilot.practice = true
	scene.add_child(pilot)
	pilot.global_position = world.poi_position(str(region.spawn_poi))+Vector3.UP*2.8
	combat = CombatV2.new()
	combat.pilot = pilot
	scene.add_child(combat)
	combat.set_physics_process(false)
	runner = TaskRunnerV2.new()
	runner.world = world
	runner.pilot = pilot
	runner.combat = combat
	scene.add_child(runner)
	runner.set_physics_process(false)
	runner.stage_ready.connect(func(_stage): stage_success = true)
	runner.failed.connect(func(reason): stage_failure = reason)
	await physics_frame

func _dispose() -> void:
	scene.queue_free()
	await process_frame
	await process_frame

func _equip(tool: String) -> void:
	var build = pilot.build.duplicate(true)
	if not tool.is_empty(): build.slots.tool = tool
	if "basic_light" in runner.stage.get("equipment_plan",{}).get("utility_required",[]): build.slots.utility = "searchlight_base"
	if runner.stage.has("loaner_utility"): build.slots.utility = runner.stage.loaner_utility
	var checked = CatalogV2.resolve_build(build,pilot.cargo_kg)
	_expect(checked.valid,"fixture tool load legal "+tool)
	pilot.configure(checked)

func _tick(delta = 0.25) -> void:
	ticks += 1
	pilot.linear_velocity = Vector3.ZERO
	pilot.angular_velocity = Vector3.ZERO
	for id in pilot.cargo_items:
		var body: RigidBody3D = pilot.cargo_items[id].body
		body.freeze = true
		body.global_position = pilot.global_position+Vector3.DOWN*1.3
	combat._update_objective(delta)
	runner._physics_process(delta)
	for enemy in combat.enemies:
		if is_instance_valid(enemy): enemy.set_physics_process(false)
	for body in runner.cargo.values():
		if is_instance_valid(body): body.freeze = true

func _drive_stage() -> bool:
	var last_action = -1
	var action_ticks = 0
	var scan_side = false
	for iteration in range(30000):
		if runner.pending: return stage_success and stage_failure.is_empty()
		var action = runner.current_action()
		if action.is_empty(): return stage_success
		if last_action!=runner.action_index:
			last_action = runner.action_index
			action_ticks = 0
			_equip(str(action.get("tool_id","")))
			await process_frame
			runner.progress_s = 0
		action_ticks += 1
		if action_ticks>5000: stage_failure = "fixture action timeout: "+str(action); return false
		var target = runner.target_position()
		pilot.command = {"active":true,"interact":true}
		pilot.ground_distance = 2.8
		pilot.grounded = false
		match str(action.type):
			"gate":
				if action_ticks==1:
					pilot.global_position = target-runner.gate_normal*4.0
					_tick()
					if bool(action.get("warning_observed_required",false)): combat.warning_seen.emit()
					pilot.global_position = target+runner.gate_normal*4.0
			"scan":
				if action.has("scan_facing_deg"):
					var angle = deg_to_rad(float(action.scan_facing_deg))
					pilot.global_position = target+Vector3(sin(angle)*2.2,0,cos(angle)*2.2)
				elif action.has("scan_path_m"):
					scan_side = not scan_side
					pilot.global_position = target+Vector3(1.0 if scan_side else -1.0,0,0)
				else: pilot.global_position = target
			"escort":
				pilot.global_position = runner.facility.global_position+Vector3.UP*2.0
			"return":
				# Predicate fixture only; actual contact is tested by test_flight.
				pilot.global_position = Vector3(target.x,0.24,target.z)
				pilot.ground_distance = 0.24
				pilot.grounded = true
			_: pilot.global_position = target
		_tick()
		for enemy in combat.enemies:
			if is_instance_valid(enemy) and not enemy.is_queued_for_deletion():
				enemy.exposure_left = 4.0
				enemy.take_damage(1000.0)
		for node in combat.target_nodes:
			if is_instance_valid(node) and not node.is_queued_for_deletion(): node.take_damage(1000.0)
	return false

func _negative_predicates() -> void:
	runner.start_stage({"id":"FIXTURE:landing","actions":[{"type":"return","poi_id":"R1-P01","duration_s":1.0}]})
	pilot.global_position = Vector3(runner.target_position().x,0.5,runner.target_position().z)
	pilot.ground_distance = 0.5
	pilot.grounded = false
	for i in range(8): _tick()
	_expect(not runner.pending,"hovering near the floor is not a landing")
	pilot.grounded = true
	for i in range(4): _tick()
	_expect(runner.pending,"stable contact telemetry permits landing dwell")
	runner.start_stage({"id":"FIXTURE:gate","actions":[{"type":"gate","poi_id":"R1-P01","duration_s":0.05}]})
	var target = runner.target_position()
	pilot.global_position = target-runner.gate_normal*4
	pilot.command = {"interact":false}
	_tick()
	pilot.global_position = target
	for i in range(10): _tick()
	_expect(not runner.pending,"standing in gate does not complete")
	pilot.global_position = target+runner.gate_normal*4
	_tick()
	_expect(runner.pending,"actual plane crossing completes gate")
	runner.start_stage({"id":"FIXTURE:tool","actions":[{"type":"clear","poi_id":"R1-P01","tool_id":"clearance_base","duration_s":1.0}]})
	pilot.global_position = runner.target_position()
	pilot.command = {"interact":true}
	for i in range(8): _tick()
	_expect(not runner.pending,"wrong tool cannot clear")
	_equip("clearance_base")
	pilot.command.interact = false
	for i in range(8): _tick()
	_expect(not runner.pending,"correct tool requires held input")
	pilot.command.interact = true
	for i in range(4): _tick()
	_expect(runner.pending,"correct tool and dwell complete")
	runner.start_stage({"id":"FIXTURE:window","actions":[{"type":"interact","poi_id":"R1-P01","duration_s":1.0,"safe_window_s":4.0}]})
	pilot.global_position = runner.target_position()
	runner.action_elapsed_s = 4.1
	for i in range(4): _tick()
	_expect(not runner.pending,"closed safety window cannot complete")
	runner.action_elapsed_s = 0
	for i in range(4): _tick()
	_expect(runner.pending,"open safety window accepts work")
	runner.start_stage({"id":"FIXTURE:staging","actions":[{"type":"pickup","poi_id":"R1-P01","tool_id":"hook_base","cargo_id":"fixture:seat","cargo_kg":1.0},{"type":"deliver","poi_id":"R1-P02","tool_id":"hook_base","cargo_id":"fixture:seat","cargo_disposition":"staged"}]})
	_expect(await _drive_stage(),"staged cargo first stage")
	var instance_id = runner.cargo["fixture:seat"].get_instance_id()
	runner.start_stage({"id":"FIXTURE:reuse","actions":[{"type":"pickup","poi_id":"R1-P02","tool_id":"hook_base","cargo_id":"fixture:seat","cargo_kg":1.0,"reuse_staged_instance":true},{"type":"deliver","poi_id":"R1-P03","tool_id":"hook_base","cargo_id":"fixture:seat"}]})
	_expect(runner.cargo["fixture:seat"].get_instance_id()==instance_id,"same cargo instance survives stage change")
	_expect(await _drive_stage(),"same cargo is picked and delivered")
	_expect(str(runner.cargo_records["fixture:seat"].state)=="delivered","cargo consumed exactly once")
	var recovery_stage = {"id":"FIXTURE:recovery","actions":[{"type":"pickup","poi_id":"R1-P01","tool_id":"delivery_base","cargo_id":"fixture:recover","cargo_kg":0.2},{"type":"deliver","poi_id":"R1-P03","tool_id":"delivery_base","cargo_id":"fixture:recover","recovery_poi_id":"R1-P02"}]}
	runner.start_stage(recovery_stage)
	_equip("delivery_base")
	pilot.command = {"interact":true}
	pilot.global_position = runner.target_position()+Vector3.RIGHT*2.0
	for i in range(8): _tick()
	_expect(runner.action_index==0 and pilot.cargo_items.is_empty(),"sideways pickup cannot create a long angled cargo joint")
	pilot.global_position = runner.target_position()+Vector3.UP
	for i in range(8): _tick()
	_expect(runner.action_index==0 and pilot.cargo_items.is_empty(),"high pickup cannot create an excessively long cargo joint")
	pilot.global_position = runner.target_position()
	for i in range(6): _tick()
	_expect(pilot.cargo_items.has("fixture:recover"),"pickup creates physical cargo joint")
	_expect(is_instance_valid(pilot.cargo_items["fixture:recover"].joint),"real joint is present")
	var recovered_id = runner.cargo["fixture:recover"].get_instance_id()
	_expect(runner.recover_cargo(),"cargo recovery available")
	_expect(runner.cargo["fixture:recover"].get_instance_id()==recovered_id,"recovery retains exact physical instance")
	_expect(runner.cargo["fixture:recover"].global_position.distance_to(world.poi_position("R1-P02")+Vector3.UP*0.7)<0.01,"recovery returns to specified seat")
	pilot.global_position = world.poi_position("R1-P02")+Vector3(2,2.8,0)
	_tick()
	_expect(not pilot.cargo_items.has("fixture:recover"),"recovery pickup uses the same alignment rule")
	pilot.global_position = world.poi_position("R1-P02")+Vector3.UP*2.8
	_tick()
	_expect(pilot.cargo_items.has("fixture:recover"),"delivery step permits pickup at recovery seat")
	var saved = runner.snapshot_run_state()
	_expect(runner.resume_stage(recovery_stage,saved),"atomic resume restores active stage")
	_expect(runner.action_index==1 and pilot.cargo_items.has("fixture:recover"),"resume retains action index and attached cargo")
	_expect(await _drive_stage(),"resumed delivery completes through predicate")
	var salvage = {"id":"FIXTURE:extract","actions":[{"type":"pickup","poi_id":"R1-P01","tool_id":"hook_base","cargo_id":"fixture:value","cargo_kg":0.7,"cargo_value":20,"optional":true},{"type":"pickup","poi_id":"R1-P02","tool_id":"hook_base","cargo_id":"fixture:skip","cargo_kg":2.0,"cargo_value":40,"optional":true},{"type":"return","poi_id":"R1-P01","duration_s":1.0,"extract_carried_cargo":true}]}
	runner.start_stage(salvage)
	_equip("hook_base")
	pilot.global_position = runner.target_position()
	for i in range(6): _tick()
	_expect(runner.action_index==1,"salvage first pickup complete")
	_expect(runner.begin_extract(),"early extraction skips remaining risk")
	_expect(await _drive_stage(),"early extraction requires actual landing predicate")
	_expect(runner.delivered_reward_parts==20 and runner.extraction_manifest.size()==1,"salvage rewards only physically returned cargo")
	runner.start_stage({"id":"FIXTURE:skip","actions":[{"type":"pickup","poi_id":"R1-P01","tool_id":"hook_base","cargo_id":"fixture:optional","cargo_kg":1.0,"optional":true},{"type":"return","poi_id":"R1-P01","duration_s":1.0,"extract_carried_cargo":true}]})
	_expect(runner.skip_optional(),"optional cargo may be skipped")
	_expect(not runner.skip_optional(),"required action may not be skipped")
	_expect(await _drive_stage(),"zero-cargo extraction can finish")
	_expect(runner.delivered_reward_parts==0,"skipped cargo never pays")
	runner.start_stage({"id":"FIXTURE:nodes","actions":[{"type":"defend","poi_id":"R1-P01","enemy_roles":[],"waves":1,"target_nodes":3,"boss_phase":1}]})
	pilot.global_position = runner.target_position()
	for i in range(8): _tick()
	_expect(not runner.pending and combat.target_nodes.size()==3,"empty enemy list cannot bypass power nodes")
	for node in combat.target_nodes: node.take_damage(1000)
	_tick()
	_expect(runner.pending,"destroying real nodes permits phase completion")
	runner.start_stage({"id":"FIXTURE:metric","completion_metrics":{"collision_count_max":0},"actions":[{"type":"return","poi_id":"R1-P01","duration_s":1.0}]})
	pilot.collision_event.emit({"kind":"frontal"})
	pilot.global_position = runner.target_position()
	pilot.ground_distance = 0.24
	pilot.grounded = true
	for i in range(4): _tick()
	_expect(runner.pending and not stage_failure.is_empty(),"challenge collision constraint rejects completion")
	stage_failure = ""
	var late_stage = {"id":"FIXTURE:late_resume","actions":[{"type":"pickup","poi_id":"R1-P01","tool_id":"hook_base","cargo_id":"fixture:late","cargo_kg":1.0},{"type":"deliver","poi_id":"R1-P02","tool_id":"hook_base","cargo_id":"fixture:late"},{"type":"interact","poi_id":"R1-P03","duration_s":1.0}]}
	runner.start_stage(late_stage)
	_equip("hook_base")
	pilot.global_position = runner.target_position()
	for i in range(6): _tick()
	pilot.global_position = runner.target_position()
	for i in range(6): _tick()
	_expect(runner.action_index==2,"fixture reaches post-delivery checkpoint")
	var late_saved = runner.snapshot_run_state()
	_expect(runner.resume_stage(late_stage,late_saved) and stage_failure.is_empty(),"late resume does not rerun an already consumed pickup")
	_expect(runner.action_index==2 and not runner.cargo.has("fixture:late"),"late resume preserves consumed cargo")
	_expect(await _drive_stage(),"late resume finishes normally")

func _expect(value: bool, label: String) -> void:
	checks += 1
	if not value: failures.append(label)
