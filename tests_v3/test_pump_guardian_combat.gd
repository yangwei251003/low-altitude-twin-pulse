extends SceneTree
## I2 combat-only vertical slice. Prior Director receipts and collision-checked
## actor observation poses are explicit QA fixtures, not played progression.
const MAIN = preload("res://scenes/v3/main.tscn")
const Pump = preload("res://scripts/v3/gameplay/twin_pump_guardian_mechanisms.gd")
const Store = preload("res://scripts/v3/core/twin_world_store.gd")
const PLAN := "I2:twin_pump_guardian:plan"
const REWARD := "boss:I2:twin_pump_guardian"
class ErrorLogger extends Logger:
	var guard := Mutex.new()
	var errors: Array = []
	func _log_error(function: String,file: String,line: int,code: String,rationale: String,_notify: bool,kind: int,_trace: Array[ScriptBacktrace]) -> void:
		if kind==Logger.ERROR_TYPE_WARNING: return
		guard.lock()
		errors.append({"function":function,"file":file,"line":line,"code":code,"rationale":rationale})
		guard.unlock()
var logger := ErrorLogger.new()
var session: Node
var profile := ""
var output := ""
var finished := false
var checks: Array = []
var phases: Array = []
var water_runs: Array = []
var fixture_receipts := 0
var successful_shots := 0
var phase_two := false
var warning_token := ""
var part_key := ""
var started_frame := 0
var victory: Dictionary = {}
var fixture_expected_tx: Dictionary = {}

func _initialize() -> void:
	OS.add_logger(logger)
	_run.call_deferred()

func _run() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--qa-profile="): profile = arg.trim_prefix("--qa-profile=")
		if arg.begins_with("--output="): output = arg.trim_prefix("--output=")
	if not profile.begins_with("qa_pump_guardian_combat_") or profile!=profile.validate_filename() or not output.begins_with("res://artifacts/v3/pump-guardian-combat-") or ".." in output or DirAccess.dir_exists_absolute(output) or DirAccess.dir_exists_absolute("user://profiles_v3/"+profile):
		quit(2)
		return
	DirAccess.make_dir_recursive_absolute(output)
	started_frame = Engine.get_physics_frames()
	create_timer(60).timeout.connect(func():
		if not finished:
			_check(false,"60 second I2 actual MAIN combat simulation bound",_diagnostics())
			_finish())
	session = MAIN.instantiate()
	root.add_child(session)
	if not _check(session.profile_ready and session.start_flight("solo") and not session.canal_runtime_enabled,"actual empty QA MAIN starts solo with Canal at its ordinary false default",_diagnostics()):
		_finish()
		return
	_phase("main_ready")
	if not _check(session._load_region("I2") and session.region_id=="I2" and session.canal==null and session.campaign.supported(),"normal factory loads actual I2 rig and Arena BEFORE the Director rule prefix",_diagnostics()):
		_finish()
		return
	session.inputs.test_enabled = true
	session.inputs.test_frame = {"axes":{},"held":["brake"],"edges":[]}
	if not _seed_plan():
		_finish()
		return
	session.story.load_world()
	_phase("actual_i2_and_legal_plan_fixture")
	if not await _operate(Pump.PLUG) or not await _battle_pose():
		_finish()
		return
	for unused in 60:
		await _step()
		if finished: return
		if session.campaign.active(): break
	if not _check(session.campaign.active() and int(_state().attempt)==1 and session.campaign.mechanisms.boss_environment("I2").get("civilian_supply_isolated",false),"actual plan/arena entry starts one Boss with the physically withdrawn isolation plug",_diagnostics()):
		_finish()
		return
	_phase("battle_started_actual_isolation")
	if not await _fight():
		_finish()
		return
	_finish()

func _seed_plan() -> bool:
	var director = session.story.director
	var state: Dictionary = director.default_state()
	var found := false
	for action: Dictionary in director.definitions().actions:
		for objective: Dictionary in action.objectives:
			var matcher: Dictionary = objective.events[0]
			var applied: Dictionary = director.apply_event(state,{"id":"qa-pump-combat-rule:"+str(objective.id),"type":matcher.type,"target_id":matcher.target_id,"option":matcher.options[0]},
				{"is_authority":true,"validated":true,"region_id":action.region_id})
			if not applied.get("ok",false) or not applied.get("changed",false): return _check(false,"ordered Director prior-rule fixture is valid",{"objective":objective.id,"result":applied.get("code")})
			state = applied.state
			fixture_receipts += 1
			if objective.id==PLAN:
				found = true
				break
		if found: break
	if not _check(found and PLAN in state.completed and director.validate_state(state).ok,"Director-valid rule fixture stops at the I2 Boss plan; earlier services and campaign were not played",{"receipts":fixture_receipts}): return false
	fixture_expected_tx = {"fixture":"ordered_legal_Director_prefix_in_already_loaded_I2","transaction_id":"qa-pump-combat-plan-rules-fixture","set_path":"world.actions.opening","writes_no_physical_water_or_boss_state":true}
	var stored: Dictionary = session.store.commit({"id":"qa-pump-combat-plan-rules-fixture","set":{"world.actions.opening":state}})
	if not _check(stored.get("ok",false),"rule fixture commits only in already-loaded I2 QA Store",stored): return false
	session.world_cache = session.store.snapshot()
	session.consensus.set_world_revision(int(session.world_cache.world_revision))
	return true

func _fight() -> bool:
	for unused in 3300:
		await _step()
		if finished: return false
		if not await _avoid_warning(): return false
		var state: Dictionary = _state()
		if state.get("completed",false): return _published_victory()
		if not session.players[1].enabled or int(state.attempt)!=1: return _check(false,"scripted weapon observation fixture does not silently consume another attempt",_diagnostics())
		phase_two = phase_two or int(state.phase)==2
		var part: String = session.campaign.encounter.current_part()
		var key: String = str(state.phase)+":"+part
		if key!=part_key:
			part_key = key
			_phase("current_part_"+key)
		if part in ["low_pump","high_pump"]:
			var environment: Dictionary = session.campaign.mechanisms.boss_environment("I2")
			if not environment.get("civilian_supply_isolated",false): return _check(false,"actual civilian isolation remains intact during combat",_diagnostics())
			var needs_water: bool = int(environment.get("water_level_mm",-1))>2000 if part=="low_pump" else int(environment.get("water_level_mm",-1))<3000
			if needs_water:
				if not await _drive_water(part=="high_pump"): return false
				continue
		if not session.campaign.encounter.part_open(part) or float(session.weapon_cooldowns.get(1,0))>0: continue
		var actor: FlightBodyV2 = session.players[1]
		var id: String = session.world.campaign_arena.target_id(part)
		var target: Node3D = session.world.campaign_arena.targets[id]
		if not session._line_clear(actor.global_position,target.global_position,actor.get_rid(),id): return _check(false,"authored open pump/core has actual weapon LOS",{"part":part,"actor":actor.global_position,"target":target.global_position,"diagnostics":_diagnostics()})
		var hp: int = int(state.core_hp_milli) if part=="core" else int(state.parts[part])
		session._action_received(1,"lock",{"target_id":id})
		session._fire(1) # Original cooldown, range, physical LOS and part gate.
		var after: Dictionary = _state()
		var actual_hp: int = int(after.core_hp_milli) if part=="core" else int(after.parts[part])
		if actual_hp<hp: successful_shots += 1
		if after.get("completed",false): return _published_victory()
	return _check(false,"normal weapons and physical water gates complete within the bounded slice",_diagnostics())

func _drive_water(fill: bool) -> bool:
	var mechanisms: RefCounted = session.campaign.mechanisms
	var before: Dictionary = mechanisms.persistent_state()
	_phase("water_"+("fill" if fill else "drain")+"_preparing")
	var direction: String = str(mechanisms.view_state().get("direction","neutral"))
	if direction!=("fill" if fill else "drain"):
		if not await _operate(Pump.VALVE): return false
	if not await _charge("add") or not await _battle_pose(): return false
	_phase("water_"+("fill" if fill else "drain")+"_actual_pump_running")
	var reached := false
	for unused in 660:
		await _step()
		if finished: return false
		if not await _avoid_warning(): return false
		var environment: Dictionary = mechanisms.boss_environment("I2")
		var level: int = int(environment.get("water_level_mm",-1))
		if environment.get("civilian_supply_isolated",false) and (level>=3000 if fill else level>=0 and level<=2000):
			reached = true
			break
	if not _check(reached,"original charged pump reaches the real "+("high" if fill else "low")+"-water part condition",_diagnostics()): return false
	if not await _charge("drain") or not await _battle_pose(): return false
	var after: Dictionary = mechanisms.persistent_state()
	var valid: Dictionary = mechanisms.validate_state(after)
	var conserved: bool = valid.get("ok",false) and int(after.simulation.nodes[Pump.CIVILIAN].clean_ml)==300000 and int(after.simulation.nodes[Pump.CIVILIAN].dirty_ml)==0
	water_runs.append({"fill":fill,"before":before,"after":after,"validation":valid,"environment":mechanisms.boss_environment("I2")})
	_phase("water_"+("high" if fill else "low")+"_reached_and_power_removed")
	return _check(conserved and session.entities[Pump.RELAY].charge==0.0,"original charge drain stops actual flow; conservative ledger and civilian reserve remain valid",water_runs.back())

func _charge(mode: String) -> bool:
	if not await _near(Pump.RELAY): return false
	for unused in 30:
		if float(session.cooldowns.get(1,0))<=0: break
		await _step()
		if finished: return false
	var count: int = session.stats.abilities
	session._action_received(1,"ability",{"ability":"charge","target_id":Pump.RELAY,"mode":mode})
	return _check(session.stats.abilities==count+1 and (session.entities[Pump.RELAY].charge>=35.0 if mode=="add" else session.entities[Pump.RELAY].charge==0.0),"original nearby charge "+mode+" controls actual pump power",_diagnostics())

func _operate(id: String) -> bool:
	if not await _near(id): return false
	var body: PhysicsBody3D = session.world.objects[id]
	var old: Transform3D = body.global_transform
	var expected: Transform3D = old
	if id==Pump.PLUG: expected.origin = Pump.PLUG_OPEN
	else: expected.basis = Basis(Vector3.UP,0.0 if absf(wrapf(body.rotation.y,-PI,PI))>.4 else PI*.5)
	var generation: int = session.store.snapshot().generation
	var receipt: String = "campaign-operation:"+id
	fixture_expected_tx = {"fixture":"QA_actor_observation_then_original_Session_G","target_id":id,"receipt":receipt,"transaction_id":"%s:%s:%d" % [receipt,str(session.world_cache.world.branch_id),int(session.world_cache.generation)],"generation_before":generation,"world_cache_generation":session.world_cache.generation,"expected_pose":expected,"direct_test_Store_write":false}
	session._action_received(1,"lock",{"target_id":id})
	session.interface.clear_dialogue()
	var event := InputEventKey.new()
	event.physical_keycode = KEY_G
	event.keycode = KEY_G
	event.pressed = true
	session._unhandled_input(event)
	await _step()
	if finished: return false
	var physical: Transform3D = PhysicsServer3D.body_get_state(body.get_rid(),PhysicsServer3D.BODY_STATE_TRANSFORM)
	return _check(body.global_transform.origin.distance_to(expected.origin)<.002 and body.global_basis.is_equal_approx(expected.basis) and physical.origin.distance_to(expected.origin)<.002 and physical.basis.is_equal_approx(expected.basis) and int(session.store.snapshot().generation)>generation and session.campaign.last_operation_blockers.is_empty(),"original G completes actual rig travel/Store: "+id,{"old":old,"expected":expected,"node":body.global_transform,"physics":physical,"diagnostics":_diagnostics()})

func _avoid_warning() -> bool:
	var state: Dictionary = _state()
	var token: String = str(state.get("attack",{}).get("token",""))
	if state.get("attack_stage")=="warning" and token!=warning_token:
		warning_token = token
		return await _battle_pose()
	return true

func _battle_pose() -> bool:
	var side: float = -6.0 if session.players[1].global_position.x>=0.0 else 6.0
	return await _place(Vector3(side,12,-16),"battle observation (not flown evasion)")

func _near(id: String) -> bool:
	var body: PhysicsBody3D = session.world.objects[id]
	if not await _place(body.global_position+Vector3.UP*3.4,"near "+id): return false
	var actor: FlightBodyV2 = session.players[1]
	return _check(actor.global_position.distance_to(body.global_position)<=4.5 and session._line_clear(actor.global_position,body.global_position,actor.get_rid(),id),"actual rig actor proximity and LOS: "+id,_diagnostics())

func _place(at: Vector3,label: String) -> bool:
	var actor: FlightBodyV2 = session.players[1]
	var shape := actor.get_node("Envelope") as CollisionShape3D
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = shape.shape
	query.transform = Transform3D(Basis.IDENTITY,at)*shape.transform
	query.collision_mask = 1|2|8|32
	query.exclude = [actor.get_rid()]
	var hits: Array[Dictionary] = session.world.get_world_3d().direct_space_state.intersect_shape(query,8)
	if not _check(hits.is_empty(),"explicit QA pose has actual aircraft clearance: "+label,{"at":at,"hits":hits.map(func(hit: Dictionary): return str(hit.collider.get_path()))}): return false
	actor.freeze = true
	actor.global_transform = Transform3D(Basis.IDENTITY,at)
	actor.force_update_transform()
	PhysicsServer3D.body_set_state(actor.get_rid(),PhysicsServer3D.BODY_STATE_TRANSFORM,actor.global_transform)
	actor.linear_velocity = Vector3.ZERO
	actor.angular_velocity = Vector3.ZERO
	actor.hold_height = at.y
	await _step()
	return not finished

func _published_victory() -> bool:
	_phase("original_weapon_victory_publication")
	var snapshot: Dictionary = session.store.snapshot()
	var complete: bool = phase_two and successful_shots>0 and _state().completed and int(_state().core_hp_milli)==0 and session.campaign.victory_committed() and not session.pending_completion and not session.boss_active and snapshot.personal.discoveries.count(REWARD)==1 and water_runs.size()==2
	_check(complete,"real low/high water gates and original weapons complete both phases and publish exactly one Boss reward",{"successful_shots":successful_shots,"phase_two":phase_two,"water_runs":water_runs.size(),"diagnostics":_diagnostics()})
	var reader = Store.new(session.store.root_path)
	var opened: Dictionary = reader.load_profile()
	var disk: Dictionary = reader.snapshot()
	var envelope: Dictionary = disk.world.get("environment",{}).get("campaign_I2",{})
	var valid_encounter: Dictionary = session.campaign.encounter.validate_snapshot(envelope.get("encounter",{}))
	var valid_water: Dictionary = session.campaign.mechanisms.validate_state(envelope.get("mechanisms",{}))
	var disk_ok: bool = opened.get("ok",false) and valid_encounter.get("ok",false) and valid_water.get("ok",false) and bool(disk.world.flags.get("campaign_boss:I2",false)) and disk.personal.discoveries.count(REWARD)==1 and bool(envelope.get("encounter",{}).get("state",{}).get("completed",false))
	_check(disk_ok,"independent original Store reader verifies real completed Boss and conservative combat-water state",{"opened":opened,"encounter_validation":valid_encounter,"water_validation":valid_water,"envelope":envelope})
	victory = {"generation":snapshot.generation,"successful_shots":successful_shots,"phase_two":phase_two,"reward_count":disk.personal.discoveries.count(REWARD),"disk_valid":disk_ok,"water_runs":water_runs.size()}
	return complete and disk_ok

func _step() -> void:
	await physics_frame
	await process_frame

func _state() -> Dictionary:
	return session.campaign.encounter.get_state()

func _phase(label: String) -> void:
	var row := {"phase":label,"simulation_seconds":float(Engine.get_physics_frames()-started_frame)/float(Engine.physics_ticks_per_second),"diagnostics":_diagnostics()}
	phases.append(row)
	print("PUMP_COMBAT_PROGRESS "+JSON.stringify(row))

func _diagnostics() -> Dictionary:
	if not is_instance_valid(session): return {"session":"not_installed"}
	return {"region":session.region_id,"message":session.interface.message.text,"world_errors":session.world.build_errors if is_instance_valid(session.world) else [],"campaign_error":session.campaign.error,"encounter":session.campaign.presentation(),"environment":session.campaign.mechanisms.boss_environment("I2") if session.campaign.mechanisms!=null else {},"view":session.campaign.mechanisms.view_state() if session.campaign.mechanisms!=null else {},"blockers":session.campaign.last_operation_blockers,"generation":session.store.snapshot().generation,"last_commit_result":session.last_commit_result.duplicate(true),"fixture_expected_tx":fixture_expected_tx.duplicate(true)}

func _check(ok: bool,label: String,actual: Variant=null) -> bool:
	checks.append({"passed":ok,"label":label,"actual":actual})
	return ok

func _finish() -> void:
	if finished: return
	finished = true
	var failures: Array = checks.filter(func(row: Dictionary): return not row.passed)
	var report := {"checks":checks,"failures":failures,"engine_errors":logger.errors,"phases":phases,"fixture_receipts":fixture_receipts,"water_runs":water_runs,"victory":victory,"diagnostics":_diagnostics(),"scope":"I2 actual MAIN empty QA first loads ordinary scene/three rig devices/Arena, then commits an ordered Director-valid rule prefix through twin_pump_guardian plan in that already-loaded area. Prefix is rules-only, lacks earlier facility physical Result envelopes and is never used for fresh-MAIN/cross-region progression restore. Canal remains default false. Original G/Story/Transport/operate withdraws physical civilian isolation plug and turns actual valve; original charge intents supply/remove power; ordinary Session/WaterNetwork ticks physically raise/lower battle water through part gates with 300000ml resident reserve retained. Collision-checked frozen actor observation placements and warning-time alternation isolate original weapon/LOS two-phase fight; these are not flown dodges. Boss/player HP, water quantities, encounter/environment/clock are never directly set or advanced. Original final Store victory and new independent disk reader only; F2 failure/retry suite is not repeated. No full Canal service, normal unlocked progression, graphics, performance, LAN, human difficulty/fun or whole-campaign acceptance."}
	FileAccess.open(output+"/result.json",FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
	print("PUMP_GUARDIAN_COMBAT_RESULT "+JSON.stringify({"checks":checks.size(),"failures":failures,"engine_errors":logger.errors,"victory":victory,"diagnostics":report.diagnostics}))
	if is_instance_valid(session):
		session.store.read_only = false
		session.environment_save_gate.cancel("qa_teardown")
		if session.canal!=null: session.canal.clear()
		session.network.close()
		session.free()
		session = null
	await process_frame
	await physics_frame
	await process_frame
	quit(0 if failures.is_empty() and logger.errors.is_empty() and not victory.is_empty() else 1)
