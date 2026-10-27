extends SceneTree
## One actual MAIN boss vertical slice. QA actor observation poses are authored;
## Boss HP, player HP, encounter clocks and environment truth are never authored.
const MAIN = preload("res://scenes/v3/main.tscn")
const Regions = preload("res://scripts/v3/world/twin_region_catalog.gd")
const Layout = preload("res://scripts/v3/campaign/twin_campaign_layout.gd")
const Store = preload("res://scripts/v3/core/twin_world_store.gd")
const BOSS := "mirrorwing_warden"
const PLAN := "F2:mirrorwing_warden:plan"
const REWARD := "boss:F2:mirrorwing_warden"
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
var region := "F2"
var finished := false
var checks: Array = []
var trace: Array = []
var damage_receipts: Array = []
var fixture_receipts := 0
var disabled_signals := 0
var crashes := 0
var trace_key := ""
var store_failure: Dictionary = {}
var victory: Dictionary = {}

func _initialize() -> void:
	OS.add_logger(logger)
	_run.call_deferred()

func _run() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--qa-profile="): profile = arg.trim_prefix("--qa-profile=")
		if arg.begins_with("--output="): output = arg.trim_prefix("--output=")
		if arg.begins_with("--region="): region = arg.trim_prefix("--region=")
	if region!="F2" or not profile.begins_with("qa_campaign_main_combat_") or profile!=profile.validate_filename() or not output.begins_with("res://artifacts/v3/campaign-main-combat-") or ".." in output or DirAccess.dir_exists_absolute(output) or DirAccess.dir_exists_absolute("user://profiles_v3/"+profile):
		quit(2)
		return
	DirAccess.make_dir_recursive_absolute(output)
	create_timer(100).timeout.connect(func():
		if not finished:
			_check(false,"100 second F2 actual MAIN combat bound",_diagnostics())
			_finish())
	Regions._entries = Regions.entries()
	var layout: Dictionary = Layout.definition(region)
	for entry: Dictionary in Regions._entries:
		if entry.id==region:
			entry.playable = true
			entry.spawn = layout.spawn.duplicate()
			entry.bounds = layout.bounds.duplicate()
	session = MAIN.instantiate()
	root.add_child(session)
	if not _check(session.profile_ready and session.start_flight("solo"),"actual MAIN starts a fresh empty QA solo",_diagnostics()):
		_finish()
		return
	if not _check(session._load_region(region) and session.region_id==region and session.world.build_errors.is_empty() and session.campaign.supported(),"normal factory loads the real F2 scene BEFORE any prior-story rule fixture",_diagnostics()):
		_finish()
		return
	session.inputs.test_enabled = true
	session.inputs.test_frame = {"axes":{},"held":["brake"],"edges":[]}
	if not _fixture_through_plan():
		_finish()
		return
	session.story.load_world()
	var actor: FlightBodyV2 = session.players[1]
	actor.damage_resolved.connect(func(receipt: Dictionary):
		var record: Dictionary = receipt.duplicate(true)
		var state: Dictionary = session.campaign.encounter.get_state()
		record["attack_token"] = state.get("attack",{}).get("token","")
		record["attempt"] = state.get("attempt",0)
		damage_receipts.append(record))
	actor.crash_started.connect(func(): crashes += 1)
	actor.disabled.connect(func(): disabled_signals += 1)
	var position: Vector3 = session.world.campaign_arena.centre()+Vector3(0,0,6)
	if not await _place(position):
		_finish()
		return
	for unused in 60:
		if session.campaign.active(): break
		await _frame()
		if finished: return
	if not _check(session.campaign.active() and session.boss_active and session.boss_campaign and int(_state().attempt)==1,"actual nearby MAIN actor starts the authored Boss through the plan gate",_diagnostics()):
		_finish()
		return
	var first_target: String = session.world.campaign_arena.target_id("true_left_wing")
	if not await _weapon_obstruction(first_target):
		_finish()
		return
	var before_abilities: int = session.stats.abilities
	var source: Node3D = session.world.objects["F2:reveal_source"]
	var ability_los: bool = session._line_clear(actor.global_position,source.global_position,actor.get_rid(),"F2:reveal_source")
	session._action_received(1,"ability",{"ability":"light","target_id":"F2:reveal_source","mode":"on"})
	await _frame()
	if finished: return
	var sample: Dictionary = session.campaign.mechanisms.boss_environment(region)
	if not _check(ability_los and actor.global_position.distance_to(source.global_position)<=16.0 and session.stats.abilities==before_abilities+1 and session.entities["F2:reveal_source"].light_level==1.0 and sample.get("true_body_revealed",false) and sample.get("shadow_verified",false) and _state().environment==sample,"original light ability powers the actual emitter and the host ray hits the real true body before its receiver",{"sample":sample,"beam":_reveal_ray(),"diagnostics":_diagnostics()}):
		_finish()
		return
	var before_generation: int = session.store.snapshot().generation
	var before_attempt: int = int(_state().attempt)
	# Hold an explicit QA observation pose inside the authored warning shapes.
	# Actual Session ticks/LOS and original Flight Damage must disable this pilot.
	for unused in 2700:
		await _frame()
		if finished: return
		if int(_state().get("attempt",0))>before_attempt: break
	var original_damage: bool = not damage_receipts.is_empty()
	var attack_counts: Dictionary = {}
	for receipt: Dictionary in damage_receipts:
		original_damage = original_damage and receipt.get("source")==BOSS and receipt.get("weapon_type")=="pulse" and float(receipt.get("damage",0))>0.0 and float(receipt.get("health",100))<float(receipt.get("health_before",100))
		var token: String = str(receipt.get("attack_token",""))
		attack_counts[token] = int(attack_counts.get(token,0))+1
	for count: int in attack_counts.values(): original_damage = original_damage and count==1
	var retried: bool = original_damage and crashes==1 and disabled_signals==1 and int(_state().attempt)==before_attempt+1 and actor.enabled and actor.health==actor.maximum_health and int(_state().core_hp_milli)==int(session.campaign.definition.core_hp_milli)
	if not _check(retried,"authored warning/active attacks cause original Damage, actual disabled signal and automatic full-attempt retry",{"damage":damage_receipts,"per_attack":attack_counts,"crashes":crashes,"disabled_signals":disabled_signals,"generation_before":before_generation,"diagnostics":_diagnostics()}):
		_finish()
		return
	if not _check(session.entities["F2:reveal_source"].light_level==1.0 and session.campaign.mechanisms.boss_environment(region).get("shadow_verified",false),"retry retains the real persistent reveal mechanism without inventing progress"):
		_finish()
		return
	# Elevated QA observation poses isolate weapon/phase/Store checks from the
	# Damage test above. New locked lanes get an explicit alternate QA pose;
	# these fixture placements are not evidence of a player flown dodge.
	if not await _place(session.world.campaign_arena.centre()+Vector3(6,6,9)):
		_finish()
		return
	if not await _fight_to_save_boundary():
		_finish()
		return
	_finish()

func _fixture_through_plan() -> bool:
	var director = session.story.director
	var state: Dictionary = director.default_state()
	var found := false
	for action: Dictionary in director.definitions().actions:
		for objective: Dictionary in action.objectives:
			var matcher: Dictionary = objective.events[0]
			var applied: Dictionary = director.apply_event(state,{"id":"qa-combat-rules:"+str(objective.id),"type":matcher.type,"target_id":matcher.target_id,"option":matcher.options[0]},
				{"is_authority":true,"validated":true,"region_id":action.region_id})
			if not applied.get("ok",false) or not applied.get("changed",false): return _check(false,"ordered Director rule fixture accepts a valid prior receipt",{"objective":objective.id,"result":applied.get("code")})
			state = applied.state
			fixture_receipts += 1
			if objective.id==PLAN:
				found = true
				break
		if found: break
	if not _check(found and PLAN in state.completed and director.validate_state(state).ok,"legal Director rules fixture stops at this Boss plan; earlier campaign was not played",{"receipts":fixture_receipts,"last_objective":PLAN}): return false
	var committed: Dictionary = session.store.commit({"id":"qa-campaign-combat-plan-fixture","set":{"world.actions.opening":state}})
	if not _check(committed.get("ok",false),"rule-only prefix commits only inside the already-loaded F2 QA Store",committed): return false
	session.world_cache = session.store.snapshot()
	session.consensus.set_world_revision(int(session.world_cache.world_revision))
	return true

func _weapon_obstruction(id: String) -> bool:
	var actor: FlightBodyV2 = session.players[1]
	var target: Node3D = session.world.campaign_arena.targets[id]
	if not _check(session._line_clear(actor.global_position,target.global_position,actor.get_rid(),id),"real weapon ray initially reaches the closed physical wing",{"actor":actor.global_position,"target":target.global_position}): return false
	await _wait_weapon()
	if finished: return false
	var hp: int = int(_state().parts.true_left_wing)
	var shots: int = session.stats.shots
	session._action_received(1,"lock",{"target_id":id})
	session._fire(1)
	_check(int(_state().parts.true_left_wing)==hp and session.stats.shots==shots+1,"closed original armor rejects damage from a real unobstructed host shot",_diagnostics())
	var wall := StaticBody3D.new()
	wall.name = "QA_WeaponLOSObstacle"
	wall.collision_layer = 1
	wall.collision_mask = 0
	var collision := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(1,1,1)
	collision.shape = box
	wall.add_child(collision)
	session.world.add_child(wall)
	wall.global_position = actor.global_position.lerp(target.global_position,.5)
	wall.force_update_transform()
	await _frame()
	await _wait_weapon()
	if finished: return false
	var blocked: bool = not session._line_clear(actor.global_position,target.global_position,actor.get_rid(),id)
	shots = session.stats.shots
	session._fire(1)
	var rejected: bool = blocked and session.stats.shots==shots and int(_state().parts.true_left_wing)==hp
	_check(rejected,"actual opaque collider blocks the original host weapon with no shot or Boss damage",{"blocked":blocked,"obstacle":wall.global_position,"diagnostics":_diagnostics()})
	wall.free()
	await _frame()
	return rejected

func _fight_to_save_boundary() -> bool:
	var actor: FlightBodyV2 = session.players[1]
	var phase_two := false
	var successful_shots := 0
	var positioned_for_token := ""
	for unused in 3000:
		await _frame()
		if finished: return false
		var state: Dictionary = _state()
		phase_two = phase_two or int(state.phase)==2
		if not actor.enabled or int(state.attempt)!=2: return _check(false,"safe weapon observation phase does not silently add another retry",_diagnostics())
		var token: String = str(state.get("attack",{}).get("token",""))
		if state.attack_stage=="warning" and token!=positioned_for_token:
			positioned_for_token = token
			var side: float = -6.0 if actor.global_position.x>0.0 else 6.0
			if not await _place(session.world.campaign_arena.centre()+Vector3(side,6,9)): return false
			continue
		var part: String = session.campaign.encounter.current_part()
		if not session.campaign.encounter.part_open(part) or float(session.weapon_cooldowns.get(1,0))>0: continue
		var id: String = session.world.campaign_arena.target_id(part)
		var target: Node3D = session.world.campaign_arena.targets[id]
		if not session._line_clear(actor.global_position,target.global_position,actor.get_rid(),id):
			return _check(false,"authored open part remains reachable by actual weapon LOS",{"part":part,"actor":actor.global_position,"target":target.global_position,"diagnostics":_diagnostics()})
		var hp_before: int = int(state.core_hp_milli) if part=="core" else int(state.parts[part])
		var final_shot: bool = part=="core" and int(state.phase)==2 and hp_before<=9000
		if final_shot:
			store_failure = {"before":session.store.snapshot(),"actor_health":actor.health,"encounter":state}
			session.store.read_only = true # Original Store publication failure boundary.
		session._action_received(1,"lock",{"target_id":id})
		session._fire(1) # Original weapon cooldown, range, LOS and encounter hit rules.
		var after: Dictionary = _state()
		var hp_after: int = int(after.core_hp_milli) if part=="core" else int(after.parts[part])
		if hp_after<hp_before: successful_shots += 1
		if final_shot:
			var failed_snapshot: Dictionary = session.store.snapshot()
			store_failure["after"] = failed_snapshot
			store_failure["diagnostics"] = _diagnostics()
			var no_publish: bool = after.completed and session.pending_completion and session.boss_active and not session.campaign.victory_committed() and failed_snapshot==store_failure.before and failed_snapshot.personal.discoveries.count(REWARD)==0
			_check(no_publish,"actual final weapon hit completes encounter but failed original Store publishes no victory or reward",store_failure)
			session.store.read_only = false
			if not no_publish: return false
			var attempt: int = int(after.attempt)
			session._action_received(1,"retry",{}) # Actual pending-save retry path.
			var published: Dictionary = session.store.snapshot()
			var saved: bool = session.campaign.victory_committed() and not session.pending_completion and not session.boss_active and _state().completed and int(_state().attempt)==attempt and published.personal.discoveries.count(REWARD)==1 and int(published.generation)>int(failed_snapshot.generation)
			_check(saved and phase_two and successful_shots>0,"original pending retry publishes real two-phase victory and exactly one reward without restarting combat",{"phase_two":phase_two,"successful_shots":successful_shots,"snapshot":published,"diagnostics":_diagnostics()})
			if not saved: return false
			var generation: int = int(published.generation)
			for repeat in 3: session._finish_boss()
			var duplicate: Dictionary = session.store.snapshot()
			_check(int(duplicate.generation)==generation and duplicate.personal.discoveries.count(REWARD)==1,"repeated normal finish processing adds no Store generation or duplicate reward")
			var reader = Store.new(session.store.root_path)
			var opened: Dictionary = reader.load_profile()
			var disk: Dictionary = reader.snapshot()
			var envelope: Dictionary = disk.world.get("environment",{}).get("campaign_F2",{})
			var valid: Dictionary = session.campaign.encounter.validate_snapshot(envelope.get("encounter",{}))
			var disk_ok: bool = opened.get("ok",false) and bool(disk.world.flags.get("campaign_boss:F2",false)) and disk.personal.discoveries.count(REWARD)==1 and valid.get("ok",false) and bool(envelope.get("encounter",{}).get("state",{}).get("completed",false))
			_check(disk_ok,"independent original Store reader verifies the published victory flag, reward and valid completed encounter",{"opened":opened,"envelope":envelope,"validation":valid})
			victory = {"generation":generation,"reward_count":disk.personal.discoveries.count(REWARD),"phase_two":phase_two,"successful_shots":successful_shots,"disk_valid":disk_ok}
			return disk_ok
	return _check(false,"real weapon/physical-mechanism victory reaches the bounded final-save boundary",_diagnostics())

func _place(at: Vector3) -> bool:
	var actor: FlightBodyV2 = session.players[1]
	var shape := actor.get_node("Envelope") as CollisionShape3D
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = shape.shape
	query.transform = Transform3D(Basis.IDENTITY,at)*shape.transform
	query.collision_mask = 1|2|8|32
	query.exclude = [actor.get_rid()]
	var hits: Array[Dictionary] = session.world.get_world_3d().direct_space_state.intersect_shape(query,4)
	if not _check(hits.is_empty() and Regions.contains(region,at),"explicit QA observation pose has actual aircraft clearance",{"at":at,"hits":hits.map(func(hit: Dictionary): return str(hit.collider.get_path()))}): return false
	actor.freeze = true
	actor.global_transform = Transform3D(Basis.IDENTITY,at)
	actor.force_update_transform()
	PhysicsServer3D.body_set_state(actor.get_rid(),PhysicsServer3D.BODY_STATE_TRANSFORM,actor.global_transform)
	actor.linear_velocity = Vector3.ZERO
	actor.angular_velocity = Vector3.ZERO
	actor.hold_height = at.y
	await _frame()
	await _frame()
	return not finished

func _wait_weapon() -> void:
	for unused in 30:
		if float(session.weapon_cooldowns.get(1,0))<=0: return
		await _frame()
		if finished: return

func _frame() -> void:
	await physics_frame
	await process_frame # Original MAIN owns simulation; no synthetic time advance.
	if finished or not is_instance_valid(session) or not session.campaign.supported(): return
	var state: Dictionary = _state()
	var key: String = str(state.get("attempt",0))+":"+str(state.get("attack",{}).get("token",""))+":"+str(state.get("attack_stage",""))+":"+str(state.get("phase",0))
	if key!=trace_key:
		trace_key = key
		trace.append({"physics_frame":Engine.get_physics_frames(),"state":state,"actor_health":session.players[1].health,"actor_enabled":session.players[1].enabled})

func _reveal_ray() -> Dictionary:
	var from: PhysicsBody3D = session.world.objects["F2:reveal_source"]
	var to: Node3D = session.world.objects["F2:shadow_receiver"]
	var query := PhysicsRayQueryParameters3D.create(from.global_position,to.global_position,1|8)
	query.exclude = [from.get_rid()]
	var hit: Dictionary = session.world.get_world_3d().direct_space_state.intersect_ray(query)
	return {"from":from.global_position,"to":to.global_position,"collider":str(hit.collider.get_path()) if hit.has("collider") else "none","entity_id":str(hit.collider.get_meta("entity_id","")) if hit.has("collider") else ""}

func _state() -> Dictionary:
	return session.campaign.encounter.get_state()

func _diagnostics() -> Dictionary:
	if not is_instance_valid(session): return {"session":"not_installed"}
	return {"active":session.active,"region":session.region_id,"interface.message":session.interface.message.text,"campaign.error":session.campaign.error,"campaign.state":session.campaign.presentation(),"mechanism.environment":session.campaign.mechanisms.boss_environment(region) if session.campaign.mechanisms!=null else {},"mechanism.view":session.campaign.mechanisms.view_state() if session.campaign.mechanisms!=null else {},"operation_blockers":session.campaign.last_operation_blockers,"world.build_errors":session.world.build_errors if is_instance_valid(session.world) else [],"pending_completion":session.pending_completion,"store_read_only":session.store.read_only,"generation":session.store.snapshot().generation}

func _check(ok: bool,label: String,actual: Variant=null) -> bool:
	checks.append({"passed":ok,"label":label,"actual":actual})
	return ok

func _finish() -> void:
	if finished: return
	finished = true
	var failures: Array = checks.filter(func(row: Dictionary): return not row.passed)
	var report := {"region":region,"boss":BOSS,"checks":checks,"failures":failures,"engine_errors":logger.errors,"fixture_receipts":fixture_receipts,"trace":trace,"damage_receipts":damage_receipts,"crashes":crashes,"disabled_signals":disabled_signals,"store_failure":store_failure,"victory":victory,"final_diagnostics":_diagnostics(),"scope":"F2 only, actual MAIN scene loaded from an empty isolated QA Store BEFORE an ordered Director-valid rules fixture through the current Boss plan. The prefix is not played progression and lacks prior I2 physical Result envelopes; this QA profile is not used for cross-region/fresh-MAIN progression restore. Explicit full-hull-clearance frozen actor observation poses, original lock/fire cooldown/host LOS, real opaque collider rejection, original light ability and actual true-body shadow ray, original per-frame attack Damage/disabled signal/automatic whole-attempt retry, real two-phase HP loss solely by normal weapon shots, original Store.read_only final-victory failure and normal pending retry, duplicate finish and independent disk reader. No direct HP/environment/encounter/clock mutation. Headless combat integration evidence, not a flown dodge, human fun/difficulty, graphics, performance, LAN, all-six-Boss or full-campaign completion."}
	FileAccess.open(output+"/result.json",FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
	print("CAMPAIGN_MAIN_COMBAT_RESULT "+JSON.stringify({"region":region,"checks":checks.size(),"failures":failures,"engine_errors":logger.errors,"victory":victory,"diagnostics":report.final_diagnostics}))
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
