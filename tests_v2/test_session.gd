extends SceneTree

const Session = preload("res://scripts/v2/session.gd")
const Repository = preload("res://scripts/v2/save_repository.gd")
const Catalog = preload("res://scripts/v2/catalog.gd")
var game: GameSessionV2
var checks = 0
var failures: Array = []
var base_path = ""
var fixture_index = 0
var fixture_actions: Array = []
var qa_case = ""
var summary_output = ""
var predicate_stage_ids: Array[String] = []
var observed_cargo_instances: Dictionary = {}

func _initialize() -> void:
	var isolated = false
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--v2-qa=session_") and argument.length()>16:
			qa_case = argument.trim_prefix("--v2-qa=").validate_filename()
			isolated = true
		if argument.begins_with("--session-summary-output="): summary_output = argument.trim_prefix("--session-summary-output=").replace("\\","/").simplify_path()
	if not isolated:
		printerr("Session regression requires a fresh --v2-qa=session_<unique_case> argument; refusing default profile access.")
		quit(2)
		return
	if DirAccess.dir_exists_absolute("user://qa_v2/session_"+qa_case):
		printerr("QA case already exists; use a fresh unique session identifier.")
		quit(2)
		return
	if not summary_output.is_empty():
		var evidence_root = ProjectSettings.globalize_path("res://artifacts/v2/").replace("\\","/").simplify_path().trim_suffix("/")+"/"
		if not summary_output.is_absolute_path() or not summary_output.begins_with(evidence_root) or not summary_output.ends_with(".json"):
			printerr("Session summary copy must be an absolute JSON path inside this project's artifacts/v2 directory.")
			quit(2)
			return
	call_deferred("run")

func check(condition: bool, description: String) -> void:
	checks += 1
	print("SESSION_V2_", "PASS " if condition else "FAIL ",description)
	if not condition: failures.append(description)

func step(count:int)->void:
	for i in range(count): await process_frame

func fresh(label:String)->void:
	paused = false
	game.show_hangar()
	await step(2)
	fixture_index += 1
	game.repository = Repository.new(base_path+"/case_"+str(fixture_index))
	check(game.repository.load_profile(),label+" isolated repository loads")
	game.active_build = game.selected_build()
	game.selected_frame = str(game.active_build.airframe_id)
	game.restored_run_state = {}
	game.pending_transaction.clear()
	game.pending_next = Callable()
	game.input.take_control("keyboard")
	game.phone._state = "Stopped"
	game.phone.set_process(false)
	game.phone.set_physics_process(false)
	game.night = false

func fixture_commit(tx:Dictionary)->void:
	var result = game.repository.commit(tx)
	check(result.ok,"explicit QA fixture setup commits")
	fixture_actions.append(str(tx.id))

func launch(id:String,resume:bool=false)->void:
	game.launch_job(id,resume)
	if is_instance_valid(game.pilot): game.pilot.freeze = true
	if is_instance_valid(game.runner): game.runner.set_physics_process(false)
	if is_instance_valid(game.combat): game.combat.set_physics_process(false)
	await step(2)

func run()->void:
	game = Session.new()
	root.add_child(game)
	game.set_physics_process(false)
	await step(3)
	if not game.qa_mode or not game.repository.root_path.begins_with("user://qa_v2/"):
		printerr("Session did not honor isolated QA profile")
		quit(2)
		return
	base_path = game.repository.root_path
	await test_free_grants()
	await test_purchase()
	await test_invalid_requests()
	await test_reward_idempotence()
	await test_loaner()
	await test_checkpoint()
	await test_stage_transition_resume()
	await test_cargo_checkpoint_resume()
	await test_run_conditions_checkpoint()
	await test_run_conditions_suspend()
	await test_outpost_unlocks()
	await test_service_stage_unlocks()
	await test_service_active_unlock()
	await test_controller_recovery()
	await test_pause()
	paused = false
	var copied: FileAccess
	if not summary_output.is_empty():
		var error = DirAccess.make_dir_recursive_absolute(summary_output.get_base_dir())
		if error == OK: copied = FileAccess.open(summary_output,FileAccess.WRITE)
		check(copied != null,"session summary copy can be written to this run's evidence directory")
	var report = {"suite":"session_v2","engine":Engine.get_version_info().string,"checks":checks,"failures":failures,"ok":failures.is_empty(),"qa_case":qa_case,"qa_root":base_path,"fixture_transactions":fixture_actions,"predicate_completed_stages":predicate_stage_ids,"evidence_scope":"Headless real GameSessionV2/UI/world construction. M01-S1 and M07-S1 use actual TaskRunner action predicates and stage-ready transaction signals with synthetic positions, commands, grounded flags, tool changes and enemy damage. Conditions, outpost, service-unlock, idempotence and fault tests directly invoke stage completion callbacks to verify Session transactions, settings, persisted checkpoints and RegionWorld gates; they are not mission playthroughs. Controller-loss and phone states are injected; QA-only progression is seeded. NOT human playthrough, actual landing/flight-route traversal, graphics/performance, service usability, physical controller or real phone connection evidence."}
	var file = FileAccess.open(base_path+"/session_summary.json",FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(report,"\t",true,true))
		file.close()
	if copied:
		copied.store_string(JSON.stringify(report,"\t",true,true))
		copied.close()
	print("SESSION_V2_SUMMARY ",JSON.stringify(report))
	game.queue_free()
	await step(3)
	# Allow the audio mixing thread to release stopped playback references.
	await create_timer(0.2).timeout
	quit(0 if failures.is_empty() else 1)

func test_free_grants()->void:
	await fresh("free tools")
	check("hook_base" not in game.repository.data.owned_modules,"new profile does not own gated task hook")
	check(not game.purchase("hook_base"),"task hook cannot be obtained before its briefing unlock")
	fixture_commit({"id":"qa:unlock:M02","append":{"campaign.completed_missions":["M01"]}})
	var parts:int = game.repository.data.wallet.parts
	await launch("M02")
	check(game.flight_active and "hook_base" in game.repository.data.owned_modules,"accepting unlocked M02 permanently grants required free hook")
	check(game.repository.data.wallet.parts==parts,"free tool grant does not spend parts")
	game.show_hangar()
	await step(2)
	check("hook_base" in game.repository.data.owned_modules,"leaving task does not revoke free tool")
	await launch("M02")
	check(game.repository.data.owned_modules.count("hook_base")==1,"accepting briefing again cannot duplicate owned module")

func test_purchase()->void:
	await fresh("purchases")
	fixture_commit({"id":"qa:purchase_funds","parts_delta":300})
	var before:int = game.repository.data.wallet.parts
	check(game.purchase("cargo_winch") and game.repository.data.wallet.parts==before-90,"purchase atomically charges catalog price and grants module")
	check(game.purchase("cargo_winch") and game.repository.data.wallet.parts==before-90,"already owned purchase never charges twice")
	game.repository.failure_point = "before_write"
	check(not game.purchase("precision_gimbal"),"injected write failure blocks purchase success")
	check(game.repository.data.wallet.parts==before-90 and "precision_gimbal" not in game.repository.data.owned_modules,"failed purchase changes neither wallet nor ownership")
	game.repository.failure_point = ""
	check(game.purchase("precision_gimbal") and game.repository.data.wallet.parts==before-210,"retry commits one purchase after storage recovers")
	check(not game.purchase("hx02",true),"locked airframe cannot be purchased just by having currency")

func test_invalid_requests()->void:
	await fresh("invalid requests")
	fixture_commit({"id":"qa:invalid_request_funds","parts_delta":500})
	var before = game.repository.data.duplicate(true)
	check(not game.region_unlocked("R99"),"unknown region is not unlocked")
	game.launch_exploration("R99")
	check(not game.flight_active and game.repository.data==before,"unknown exploration region cannot launch or change wallet")
	game.launch_job("M00_missing")
	check(not game.flight_active and game.repository.data==before,"unknown job cannot launch or change wallet")
	game.launch_job("M16")
	check(not game.flight_active and game.repository.data==before,"locked job cannot launch or change wallet")
	check(not game.purchase("missing_module") and game.repository.data==before,"unknown module purchase has no transaction or charge")
	check(not game.purchase("missing_frame",true) and game.repository.data==before,"unknown airframe purchase has no transaction or charge")

func test_reward_idempotence()->void:
	await fresh("challenge completion")
	await launch("C-TR01-01")
	check(game.flight_active and is_instance_valid(game.runner),"challenge creates actual runner scene")
	var parts:int = game.repository.data.wallet.parts
	game._complete_side_job()
	var rewarded:int = game.repository.data.wallet.parts
	check(rewarded==parts+60,"first challenge completion callback grants first reward")
	game._complete_side_job()
	check(game.repository.data.wallet.parts==rewarded,"duplicate completion callback cannot claim repeat reward within same run")
	await fresh("stage completion")
	await launch("M01")
	var stage:Dictionary = game.current_job.stages[0]
	game._stage_complete(stage)
	check(game.stage_index==1,"successful first stage callback advances exactly one stage")
	parts = game.repository.data.wallet.parts
	game._stage_complete(stage)
	check(game.stage_index==1 and game.repository.data.wallet.parts==parts,"duplicate stale stage callback cannot skip next stage or grant currency")
	await fresh("save retry")
	await launch("M01")
	stage = game.current_job.stages[0]
	parts = game.repository.data.wallet.parts
	game.repository.failure_point = "before_write"
	game._stage_complete(stage)
	check(game.stage_index==0 and game.repository.data.wallet.parts==parts and game.pause_reasons.has("save_error"),"failed stage transaction freezes advancement and reward")
	game.repository.failure_point = ""
	game.retry_save()
	check(game.stage_index==1 and game.repository.data.wallet.parts==parts+int(stage.first_reward_parts),"save retry applies exactly one reward and one transition")

func test_loaner()->void:
	await fresh("loaner isolation")
	var selected = Catalog.default_build("tr01")
	selected.build_id = "tr01_qa_custom"
	selected.slots.utility = "cooling_duct"
	fixture_commit({"id":"qa:owned_loaner_restriction_fixture","append":{"owned_modules":["cargo_winch","cooling_duct","racing_drive"]},"set":{"builds":[selected],"selected_build_id":selected.build_id}})
	var owned: Array = game.repository.data.owned_modules.duplicate()
	var build = game.selected_build()
	var selection_id = str(game.repository.data.selected_build_id)
	await launch("C-HX02-01")
	check(game.pilot.build.airframe_id=="hx02" and "hx02" not in game.repository.data.owned_airframes,"challenge lends unowned frame without granting ownership")
	check(game.repository.data.owned_modules==owned,"loaner hook does not become an owned free tool")
	place_pilot(game.world.poi_position("R1-P01")+Vector3.UP*0.24,true)
	var tool = str(game.pilot.build.slots.tool)
	game.switch_service("tool","cargo_winch")
	check(game.pilot.build.slots.tool==tool,"loaner service rejects an owned but unlisted paid tool")
	game.switch_service("tool","scan_base")
	check(game.pilot.build.slots.tool==tool,"loaner service rejects an owned free tool outside fixed challenge sequence")
	game.switch_service("utility","cooling_duct")
	check(game.pilot.build.slots.utility=="guard_base","loaner service rejects an owned utility outside the fixed loaner build")
	game.switch_service("drive","racing_drive")
	check(game.pilot.build.slots.drive=="stock","loaner service cannot replace fixed drive")
	check(game.repository.data.selected_build_id==selection_id and game.selected_build()==build,"loaner changes never persist over the selected owned build")
	game.show_hangar()
	await step(3)
	check(game.selected_build()==build and game.repository.data.owned_modules==owned,"exiting loaner preserves owned selection and inventory")
	check(game.active_build==build and game.selected_frame==build.airframe_id,"hangar clears transient loaner selection")
	check(game.repository.data.selected_build_id==selection_id,"loaner exit restores the exact nondefault selected build identifier")

func test_checkpoint()->void:
	await fresh("checkpoint resume")
	var checkpoint = {"job_id":"M02","stage_index":1,"run_id":"qa_night_resume","seconds":42.0,"repeat":false,"night":true,"run_state":{}}
	fixture_commit({"id":"qa:resume_fixture","set":{"campaign.active_checkpoint":checkpoint},"append":{"campaign.completed_stages":["M02-S1"],"campaign.completed_missions":["M01"]}})
	await launch("M02",true)
	check(game.stage_index==1 and game.run_id=="qa_night_resume" and game.run_seconds==42.0,"resume restores stage run identity and elapsed time")
	check(game.night,"resume restores checkpoint time variant")

func place_pilot(position_m:Vector3, grounded:bool=false)->void:
	game.pilot.freeze = true
	game.pilot.global_position = position_m
	game.pilot.linear_velocity = Vector3.ZERO
	game.pilot.angular_velocity = Vector3.ZERO
	game.pilot.ground_distance = 0.24 if grounded else position_m.y
	game.pilot.grounded = grounded

func fixture_tick(delta:float=0.1)->void:
	game.pilot.command = {"active":true,"interact":true}
	game.pilot.linear_velocity = Vector3.ZERO
	for item in game.pilot.cargo_items.values():
		var body:RigidBody3D = item.body
		body.freeze = true
		body.global_position = game.pilot.global_position+Vector3.DOWN*1.3
	game.run_seconds += delta
	game.combat._update_objective(delta)
	game.runner._physics_process(delta)
	for enemy in game.combat.enemies:
		if is_instance_valid(enemy): enemy.set_physics_process(false)
	for id in game.runner.cargo:
		var body:RigidBody3D = game.runner.cargo[id]
		if is_instance_valid(body):
			body.freeze = true
			if not observed_cargo_instances.has(id): observed_cargo_instances[id] = body.get_instance_id()

func equip_fixture_tool(tool:String)->void:
	if tool.is_empty() or game.pilot.build.slots.tool==tool: return
	var build = game.pilot.build.duplicate(true)
	build.slots.tool = tool
	var resolved = Catalog.resolve_build(build,game.pilot.cargo_kg,game.repository.data.owned_airframes,game.repository.data.owned_modules)
	check(resolved.valid,"predicate fixture uses a legal owned tool: "+tool)
	if resolved.valid: game.pilot.configure(resolved)

func complete_stage_predicates(stage_id:String)->bool:
	var current_index = -1
	for tick in range(2000):
		if str(game.runner.stage.get("id",""))!=stage_id:
			predicate_stage_ids.append(stage_id)
			return true
		if paused or game.runner.pending: return false
		var action = game.runner.current_action()
		if action.is_empty(): return false
		if current_index!=game.runner.action_index:
			current_index = game.runner.action_index
			equip_fixture_tool(str(action.get("tool_id","")))
			await step(1)
		var target = game.runner.target_position()
		match str(action.type):
			"gate":
				place_pilot(target-game.runner.gate_normal*4)
				fixture_tick()
				if bool(action.get("warning_observed_required",false)): game.combat.warning_seen.emit()
				place_pilot(target+game.runner.gate_normal*4)
			"return": place_pilot(Vector3(target.x,0.24,target.z),true)
			_: place_pilot(target)
		fixture_tick()
		for enemy in game.combat.enemies:
			if is_instance_valid(enemy) and not enemy.is_queued_for_deletion():
				enemy.exposure_left = 4.0
				enemy.take_damage(1000.0)
	return false

func reload_repository()->void:
	var path = game.repository.root_path
	var restored = Repository.new(path)
	check(restored.load_profile(),"checkpoint is readable from its actual saved generation")
	game.repository = restored

func count_cargo_instances(node:Node,id:String)->int:
	var count = int(node is RigidBody3D and str(node.get_meta("cargo_id",""))==id)
	for child in node.get_children(): count += count_cargo_instances(child,id)
	return count

func test_stage_transition_resume()->void:
	await fresh("real first-stage transition resume")
	await launch("M01")
	var dimensions:Vector3 = game.pilot.damage_state.dimensions
	var damage_receipt:Dictionary = game.pilot.apply_combat_hit(7,game.pilot.global_basis.x,game.pilot.to_global(Vector3(-dimensions.x*.45,0,0)),"kinetic")
	check(float(damage_receipt.get("component_damage",0))>0,"checkpoint fixture has actual resolved component damage")
	var reward_id = str(game.current_job.stages[0].reward_id)
	var reward = int(game.current_job.stages[0].first_reward_parts)
	var before = int(game.repository.data.wallet.parts)
	check(await complete_stage_predicates("M01-S1"),"M01-S1 passes actual gate and landing predicates into Session transaction")
	if game.stage_index!=1: return
	check(game.repository.data.ledger.receipts.count(reward_id)==1 and game.repository.data.wallet.parts==before+reward,"real stage-ready signal commits reward exactly once")
	var checkpoint:Dictionary = game.repository.data.campaign.active_checkpoint
	check(int(checkpoint.stage_index)==1 and str(checkpoint.run_state.stage_id)=="M01-S2","stage checkpoint identifies the next stage rather than the completed stage")
	check(int(checkpoint.run_state.action_index)==0,"next-stage checkpoint resets action index")
	var saved_damage:Dictionary = checkpoint.get("damage_state",{})
	check(same_saved_values(saved_damage,game.pilot.damage_snapshot()),"stage transaction saves current hull armor and component damage together")
	check(checkpoint.has("environment_state") and game.repository.data.world.get("combat_regions",{}).has("R1"),"stage transaction preserves environment and regional encounter state")
	var saved_run = str(checkpoint.run_id)
	game.show_hangar()
	await step(3)
	reload_repository()
	await launch("M01",true)
	check(game.flight_active and game.stage_index==1 and game.run_id==saved_run,"hangar exit and disk reload resume the same next-stage run")
	check(str(game.runner.stage.get("id",""))=="M01-S2" and not game.runner.actions.is_empty() and game.runner.action_index==0,"resumed runner has a valid next stage, nonempty actions and zero index")
	check(not game.runner.pending and not paused,"resumed next stage is playable instead of prematurely completed")
	check(game.repository.data.wallet.parts==before+reward and game.repository.data.ledger.receipts.count(reward_id)==1,"resuming next stage does not repay prior stage")
	check(is_equal_approx(game.pilot.health,float(saved_damage.health)) and is_equal_approx(float(game.pilot.damage_state.components.rotor_left.health),float(saved_damage.components.rotor_left.health)),"disk resume restores actual hull and damaged rotor instead of healing them")
	check(game.repository.data.campaign.active_checkpoint.has("damage_state") and game.repository.data.campaign.active_checkpoint.has("environment_state"),"launch transaction retains damage and environment for another interruption")

func test_cargo_checkpoint_resume()->void:
	await fresh("cross-stage cargo checkpoint")
	observed_cargo_instances.clear()
	fixture_commit({"id":"qa:M07_prior_progress","append":{"campaign.completed_missions":["M01","M02","M03","M04","M05","M06"],"owned_modules":["hook_base","clearance_base"]}})
	await launch("M07")
	check(await complete_stage_predicates("M07-S1"),"M07-S1 actual finite combat, clear, pickup and staged delivery predicates commit")
	if game.stage_index!=1: return
	var id = "M07:instrument:1"
	check(game.runner.cargo.has(id) and game.runner.cargo_records[id].state=="staged","next stage retains staged cargo")
	check(game.runner.cargo[id].get_instance_id()==observed_cargo_instances.get(id,-1),"in-memory stage transition retains the same physical cargo instance")
	var checkpoint:Dictionary = game.repository.data.campaign.active_checkpoint
	var saved_records:Dictionary = checkpoint.run_state.cargo_records
	check(str(checkpoint.run_state.stage_id)=="M07-S2" and int(checkpoint.run_state.action_index)==0,"cargo checkpoint points to fresh M07-S2 actions")
	check(saved_records.size()==1 and saved_records.has(id) and saved_records[id].state=="staged","checkpoint contains exactly one stable cargo identity")
	check(is_equal_approx(float(saved_records[id].mass_kg),2.5) and bool(checkpoint.run_state.preparation_flags.get("tether_cut",false)),"checkpoint preserves cargo mass and preparation flag")
	var saved_home:Array = saved_records[id].home.duplicate()
	var parts:int = game.repository.data.wallet.parts
	var old_physical_id:int = game.runner.cargo[id].get_instance_id()
	game.show_hangar()
	await step(3)
	reload_repository()
	await launch("M07",false)
	check(game.stage_index==1 and game.runner.stage.get("id","")=="M07-S2","ordinary mission launch automatically resumes the existing unfinished checkpoint")
	check(game.runner.cargo.has(id) and game.runner.cargo_records.get(id,{}).get("state","")=="staged" and count_cargo_instances(game.play_root,id)==1,"ordinary launch preserves the staged instrument without duplication")
	var ordinary_checkpoint:Dictionary = game.repository.data.campaign.active_checkpoint
	check(ordinary_checkpoint.get("run_state",{}).get("cargo_records",{}).has(id) and ordinary_checkpoint.get("run_state",{}).get("stage_id","")=="M07-S2","ordinary launch does not overwrite retained checkpoint run_state")
	game.show_hangar()
	await step(3)
	reload_repository()
	await launch("M07",true)
	check(game.runner.action_index==0 and game.runner.current_action().get("cargo_id","")==id,"resumed M07-S2 starts at the same cargo pickup")
	check(game.runner.cargo.size()==1 and game.runner.cargo_records.size()==1 and count_cargo_instances(game.play_root,id)==1,"disk resume reconstructs exactly one cargo body without duplication")
	check(game.runner.cargo[id].get_instance_id()!=old_physical_id and game.runner.cargo_records[id].state=="staged","old scene is released and logical staged identity is rebuilt")
	check(game.runner.cargo_records[id].home==saved_home and is_equal_approx(float(game.runner.cargo[id].mass),2.5),"resumed body keeps the recorded seat and mass")
	check(game.pilot.cargo_items.is_empty() and is_zero_approx(game.pilot.cargo_kg),"staged cargo is not silently attached or double-counted")
	equip_fixture_tool("hook_base")
	var physical_id:int = game.runner.cargo[id].get_instance_id()
	place_pilot(game.runner.target_position())
	for tick in range(20):
		if game.runner.action_index!=0: break
		fixture_tick()
	check(game.runner.action_index==1 and game.pilot.cargo_items.size()==1 and game.pilot.cargo_items.has(id),"resumed pickup predicate attaches exactly one cargo")
	check(game.runner.cargo[id].get_instance_id()==physical_id and is_instance_valid(game.pilot.cargo_items[id].joint),"pickup reuses reconstructed body with a real PinJoint")
	check(is_equal_approx(game.pilot.cargo_kg,2.5) and count_cargo_instances(game.play_root,id)==1,"resumed payload mass is counted once")
	check(game.repository.data.wallet.parts==parts,"cargo restoration and pickup never create extra stage reward")
	game.show_hangar()
	await step(3)
	await launch("M01",false)
	check(game.repository.data.campaign.active_checkpoint.job_id=="M01","launching another mission replaces the active checkpoint")
	game.show_hangar()
	await step(3)
	await launch("M07",false)
	check(game.stage_index==0 and game.runner.stage.get("id","")=="M07-S1" and game.runner.action_index==0,"missing matching checkpoint safely restarts M07 preparation at stage one")
	check(not game.runner.pending and not paused and not game.runner.actions.is_empty(),"restarted M07 is actionable rather than stuck waiting for missing cargo")
	var reward_id = str(game.current_job.stages[0].reward_id)
	check(await complete_stage_predicates("M07-S1"),"restarting preparation reconstructs cargo by completing its real predicates")
	check(game.repository.data.wallet.parts==parts and game.repository.data.ledger.receipts.count(reward_id)==1,"replayed preparation never pays the already claimed stage reward twice")
	check(game.stage_index==1 and game.runner.cargo.has(id) and count_cargo_instances(game.play_root,id)==1,"replayed preparation produces one valid staged cargo for M07-S2")

func same_saved_values(left:Dictionary, right:Dictionary)->bool:
	# JSON numbers reload as floats; compare persisted values, not Variant numeric types.
	return JSON.parse_string(JSON.stringify(left))==JSON.parse_string(JSON.stringify(right))

func test_run_conditions_checkpoint()->void:
	await fresh("run conditions stage checkpoint")
	game.update_setting("difficulty",2)
	game.update_setting("auto_fire",true)
	game.update_setting("control_mode","advanced")
	await launch("M01")
	var initial_hash = str(game.run_conditions.control_profile_hash)
	check(game.combat.difficulty==2 and game.run_conditions.difficulty==2,"run conditions capture launch difficulty")
	check(game.run_conditions.control_modes_used==["manual_throttle"] and bool(game.run_conditions.auto_fire_used),"run conditions capture initial control mode and assistance")
	game.update_setting("control_mode","assisted")
	check(game.input.mode=="manual_throttle","airborne flight mode change is rejected")
	# This transaction test explicitly supplies a landed predicate; flight tests
	# separately verify ground contact. Modes may now change only after landing.
	game.pilot.grounded=true
	game.pilot.linear_velocity=Vector3.ZERO
	game.update_setting("control_mode","assisted")
	game.update_setting("auto_fire",false)
	game.update_setting("control_mode","advanced")
	game.update_setting("difficulty",0)
	check(game.combat.difficulty==2 and game.repository.data.settings.difficulty==2,"flight cannot change the recorded difficulty")
	check(not game.combat.auto_fire and bool(game.run_conditions.auto_fire_used),"disabling assistance cannot erase its earlier use")
	check(game.run_conditions.control_modes_used.count("manual_throttle")==1 and game.run_conditions.control_modes_used.count("assisted")==1,"control mode history accumulates without duplicate entries")
	game._stage_complete(game.current_job.stages[0])
	var checkpoint:Dictionary = game.repository.data.campaign.active_checkpoint
	var conditions:Dictionary = checkpoint.get("conditions",{})
	check(game.stage_index==1 and same_saved_values(conditions,game.run_conditions),"atomic next-stage checkpoint includes full run conditions")
	check(conditions.get("difficulty",-1)==2 and bool(conditions.get("auto_fire_used",false)),"stage checkpoint retains difficulty and any assistance used")
	var saved_run = str(game.run_id)
	game.show_hangar()
	await step(3)
	game.update_setting("difficulty",0)
	game.update_setting("auto_fire",false)
	game.update_setting("control_mode","assisted")
	reload_repository()
	await launch("M01",true)
	check(game.run_id==saved_run and game.stage_index==1 and game.combat.difficulty==2,"resume keeps the original run difficulty despite changed hangar defaults")
	check(bool(game.run_conditions.get("auto_fire_used",false)) and not game.combat.auto_fire,"resume retains historical assistance while respecting its current disabled setting")
	check(game.run_conditions.get("control_modes_used",[]).size()==2 and str(game.run_conditions.get("control_profile_hash",""))==initial_hash,"resume preserves the original input profile and deduplicated mode history")
	var record:Dictionary = game._record("qa_conditions_record")
	check(record.difficulty==2 and record.conditions==game.run_conditions,"result record carries the same preserved run conditions")

func test_run_conditions_suspend()->void:
	await fresh("run conditions suspended before first stage")
	game.update_setting("difficulty",2)
	game.update_setting("auto_fire",false)
	game.update_setting("control_mode","advanced")
	await launch("M01")
	var saved_run = str(game.run_id)
	var launch_checkpoint:Dictionary = game.repository.data.campaign.active_checkpoint.duplicate(true)
	check(same_saved_values(launch_checkpoint.get("conditions",{}),game.run_conditions),"initial launch checkpoint includes conditions before any stage completion")
	game.update_setting("auto_fire",true)
	game.update_setting("auto_fire",false)
	game.update_setting("control_mode","assisted")
	game.update_setting("control_mode","advanced")
	game.run_seconds = 12.25
	var expected:Dictionary = game.run_conditions.duplicate(true)
	game.pause_game("manual")
	var before:Dictionary = game.repository.data.duplicate(true)
	var pilot_id = game.pilot.get_instance_id()
	game.repository.failure_point = "before_write"
	game.show_hangar()
	check(game.flight_active and game.pilot.get_instance_id()==pilot_id and game.repository.data==before,"failed suspension save keeps the flight scene and prior checkpoint unchanged")
	check(game.pause_reasons.has("save_error") and not game.pending_transaction.is_empty(),"failed suspension exposes a retryable save-error state")
	game.repository.failure_point = ""
	game.retry_save()
	await step(3)
	var checkpoint:Dictionary = game.repository.data.campaign.active_checkpoint
	check(same_saved_values(checkpoint.get("conditions",{}),expected),"returning to hangar before any stage commit preserves updated run conditions")
	check(int(checkpoint.get("stage_index",-1))==0 and checkpoint.get("run_state",{})==launch_checkpoint.get("run_state",{}) and is_equal_approx(float(checkpoint.get("seconds",0)),12.25),"suspension preserves the safe stage boundary and fractional run time without inventing mid-action state")
	game.update_setting("difficulty",0)
	game.update_setting("auto_fire",false)
	game.update_setting("control_mode","advanced")
	reload_repository()
	await launch("M01",true)
	check(game.run_id==saved_run and game.stage_index==0 and game.runner.stage.id=="M01-S1" and game.runner.action_index==0,"first-stage suspension resumes the same run at its safe first-stage boundary")
	check(game.combat.difficulty==2 and same_saved_values(game.run_conditions,expected),"disk resume preserves difficulty, assistance history and all control modes after suspension")

func seed_prior_missions(id:String, receipt:String)->void:
	var previous:Array = []
	for mission in game.content.missions:
		if str(mission.id)==id: break
		previous.append(str(mission.id))
	fixture_commit({"id":receipt,"append":{"campaign.completed_missions":previous,"owned_modules":["hook_base","clearance_base","searchlight_base"]}})

func outpost_available(region_id:String, poi_id:String)->bool:
	for poi in game.available_outposts(region_id):
		if str(poi.id)==poi_id: return true
	return false

func test_outpost_unlocks()->void:
	var unlocks:Dictionary = game.content.catalog.outpost_unlocks
	check(unlocks.size()==4,"catalog defines four mission-unlocked outposts")
	for mission_id in unlocks:
		var poi_id = str(unlocks[mission_id])
		await fresh("outpost "+poi_id)
		seed_prior_missions(str(mission_id),"qa:outpost_previous:"+str(mission_id))
		await launch(str(mission_id))
		var region_id = str(game.current_job.region_id)
		check(poi_id not in game.repository.data.world.outposts and not outpost_available(region_id,poi_id),poi_id+" is unavailable before its mission completion")
		while game.stage_index < game.current_job.stages.size()-1:
			game._stage_complete(game.current_job.stages[game.stage_index])
			check(poi_id not in game.repository.data.world.outposts,poi_id+" intermediate stage does not unlock the outpost early")
		var stage:Dictionary = game.current_job.stages[game.stage_index]
		var before:Dictionary = game.repository.data.duplicate(true)
		game.repository.failure_point = "before_write"
		game._stage_complete(stage)
		check(game.repository.data==before and game.pause_reasons.has("save_error"),poi_id+" failed final transaction changes neither progression, currency nor outposts")
		check(poi_id not in game.repository.data.world.outposts and str(mission_id) not in game.world.completed_missions,poi_id+" failed save cannot expose the outpost or completed-mission service gate")
		game.repository.failure_point = ""
		game.retry_save()
		check(str(mission_id) in game.repository.data.campaign.completed_missions and poi_id in game.repository.data.world.outposts,poi_id+" successful retry atomically commits mission and outpost")
		check(game.repository.data.ledger.receipts.count(str(stage.reward_id))==1 and game.repository.data.world.outposts.count(poi_id)==1,poi_id+" completion grants one receipt and one outpost ID")
		check(game.repository.data.wallet.parts==before.wallet.parts+int(stage.first_reward_parts),poi_id+" successful final transaction pays exactly its stage reward")
		check(outpost_available(region_id,poi_id),poi_id+" becomes an available departure point")
		if game.content.catalog.service_unlocks.has(poi_id):
			check(game.world.service_unlocked(poi_id),poi_id+" live world sees the newly committed mission service unlock")
		var after:Dictionary = game.repository.data.duplicate(true)
		game._stage_complete(stage)
		check(game.repository.data==after,poi_id+" duplicate completion callback cannot repeat reward or unlock")
		game.show_hangar()
		await step(3)
		reload_repository()
		check(poi_id in game.repository.data.world.outposts and str(mission_id) in game.repository.data.campaign.completed_missions,poi_id+" mission and outpost survive actual disk reload together")

func test_service_stage_unlocks()->void:
	var rules:Dictionary = game.content.catalog.service_unlocks
	var exercised = 0
	for poi_id in rules:
		var rule:Dictionary = rules[poi_id]
		if not rule.has("stage"): continue
		exercised += 1
		var required = str(rule.stage)
		var mission_id = required.split("-")[0]
		await fresh("service stage gate "+str(poi_id))
		seed_prior_missions(mission_id,"qa:service_previous:"+str(poi_id))
		await launch(mission_id)
		check(not game.world.service_unlocked(str(poi_id)),str(poi_id)+" matching active mission cannot bypass its stage prerequisite")
		place_pilot(game.world.poi_position(str(poi_id))+Vector3.UP*0.24,true)
		check(str(game.world.nearest_service(game.pilot.global_position).get("id",""))!=str(poi_id),str(poi_id)+" locked service is excluded from actual nearest-service lookup")
		var original_tool = str(game.pilot.build.slots.tool)
		game.switch_service("tool","hook_base")
		check(game.pilot.build.slots.tool==original_tool,str(poi_id)+" a landed fixture cannot use the locked service")
		while str(game.current_job.stages[game.stage_index].id)!=required:
			game._stage_complete(game.current_job.stages[game.stage_index])
			check(not game.world.service_unlocked(str(poi_id)),str(poi_id)+" earlier stage completion is insufficient")
		var stage:Dictionary = game.current_job.stages[game.stage_index]
		game.repository.failure_point = "before_write"
		game._stage_complete(stage)
		check(not game.world.service_unlocked(str(poi_id)) and required not in game.repository.data.campaign.completed_stages,str(poi_id)+" failed stage write does not open service")
		game.repository.failure_point = ""
		game.retry_save()
		check(required in game.repository.data.campaign.completed_stages and game.world.service_unlocked(str(poi_id)),str(poi_id)+" successful stage commit immediately opens its service")
		place_pilot(game.world.poi_position(str(poi_id))+Vector3.UP*0.24,true)
		check(str(game.world.nearest_service(game.pilot.global_position).get("id",""))==str(poi_id),str(poi_id)+" unlocked service is returned at its real location")
		game.show_hangar()
		await step(3)
		reload_repository()
		await launch(mission_id,true)
		check(game.world.service_unlocked(str(poi_id)),str(poi_id)+" service prerequisite persists after scene and repository reload")
	check(exercised==6,"all six stage-gated services were exercised")

func test_service_active_unlock()->void:
	await fresh("active-mission service exception")
	seed_prior_missions("M11","qa:service_M11_previous")
	game.launch_exploration("R3")
	game.pilot.freeze = true
	game.combat.set_physics_process(false)
	await step(2)
	check(not game.world.service_unlocked("R3-P19"),"M11 service remains closed during unrelated exploration before mission completion")
	game.show_hangar()
	await step(3)
	await launch("M11")
	check(game.world.service_unlocked("R3-P19") and "M11" not in game.repository.data.campaign.completed_missions,"M11 service opens only for its explicitly permitted active mission")
	for index in range(game.current_job.stages.size()): game._stage_complete(game.current_job.stages[game.stage_index])
	game.show_hangar()
	await step(3)
	reload_repository()
	game.launch_exploration("R3")
	game.pilot.freeze = true
	game.combat.set_physics_process(false)
	await step(2)
	check(game.world.service_unlocked("R3-P19"),"M11 service remains available in exploration after committed mission completion")

func test_controller_recovery()->void:
	await fresh("synthetic controller loss")
	await launch("M01")
	game.input.pause_requested.emit("controller_lost")
	check(paused and game.pause_reasons.has("controller_lost") and not game.input.active,"synthetic controller loss suspends command output")
	game.resume_game()
	check(not paused and not game.pause_reasons.has("controller_lost") and game.input.active,"explicit resume clears the recovered controller-loss pause")
	game.input.pause_requested.emit("controller_lost")
	game.desktop_control()
	check(not game.pause_reasons.has("controller_lost") and game.pause_reasons.has("manual") and paused,"desktop takeover clears controller-loss but preserves deliberate manual pause")
	game.resume_game()
	check(not paused and game.input.active and game.input.source=="keyboard","explicit resume after desktop takeover returns usable keyboard control")

func test_pause()->void:
	await fresh("phone state pause")
	await launch("M01")
	game.input.take_control("phone")
	game.phone._state = "Active"
	game.phone._neutral = false
	game.phone._approved = true
	game.pause_game("manual")
	check(paused and not game.input.active,"manual pause immediately disables command output")
	check(not bool(game.phone.get_status().active),"manual phone pause invalidates active lease instead of leaving it active")
	game.resume_game()
	check(paused and not game.input.active,"off-center phone cannot bypass resume neutral requirement")
	game.pause_reasons["save_error"] = true
	game.pause_reasons["phone:disconnect"] = true
	game.phone._state = "Active"
	game._phone_changed()
	check(paused and game.pause_reasons.has("save_error"),"phone reactivation cannot clear save-error pause")
	game.pause_reasons.erase("save_error")
	game.pause_reasons["result"] = true
	game._phone_changed()
	check(paused and game.pause_reasons.has("result"),"phone reactivation cannot escape result screen")
