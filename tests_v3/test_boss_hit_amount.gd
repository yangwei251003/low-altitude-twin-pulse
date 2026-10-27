extends SceneTree
## Staged, post-patch observer. MAIN and all three Encounters are production objects.
const MAIN = preload("res://scenes/v3/main.tscn")
const Regions = preload("res://scripts/v3/world/twin_region_catalog.gd")
const Layout = preload("res://scripts/v3/campaign/twin_campaign_layout.gd")
const PLAN := "F2:mirrorwing_warden:plan"
const WEST := "F1:crown_host_west"
const SCOPE := "Fresh isolated MAIN; explicit full-hull-clear PLAYER observation poses and one temporary opaque QA obstacle. Whale/Crown use original development encounter start, not earned Story engagement. F2 loads empty QA World before an ordered Director-only prefix through its plan; earlier objectives were not naturally played and this profile is not a full Registry-reopen fixture. Ordinary MAIN physics owns all encounter clocks, armor, abilities, attacks and cooldowns. No direct Boss HP, environment, actor health, machinery pose or Encounter-state authoring; damage is passed only to the intended Host-internal APIs. This checks the amount/accepted bridge, not WeaponCycle scheduling, victory/rewards, natural flight, human comfort, graphics, audio listening or LAN."

class ErrorLogger extends Logger:
	var guard := Mutex.new()
	var errors: Array = []
	func _log_error(function: String, file: String, line: int, code: String, rationale: String, _notify: bool, kind: int, _trace: Array[ScriptBacktrace]) -> void:
		if kind == Logger.ERROR_TYPE_WARNING: return
		guard.lock()
		errors.append({"function":function,"file":file,"line":line,"code":code,"rationale":rationale})
		guard.unlock()

var session: Node
var logger := ErrorLogger.new()
var boss := ""
var region := ""
var profile := ""
var output := ""
var finished := false
var began := 0
var checks: Array = []
var shots: Array = []
var poses: Array = []
var fixtures: Array = []

func _initialize() -> void:
	OS.add_logger(logger)
	_run.call_deferred()

func _run() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--boss="): boss = arg.trim_prefix("--boss=")
		if arg.begins_with("--qa-profile="): profile = arg.trim_prefix("--qa-profile=")
		if arg.begins_with("--output="): output = arg.trim_prefix("--output=")
	if boss not in ["whale","crown","campaign"] or not profile.begins_with("qa_boss_hit_amount_") or profile != profile.validate_filename() or DirAccess.dir_exists_absolute("user://profiles_v3/"+profile) or not output.begins_with("res://artifacts/v3/boss-hit-amount-") or ".." in output or DirAccess.dir_exists_absolute(output):
		print("BOSS_HIT_AMOUNT_ARGUMENTS_REJECTED")
		quit(2)
		return
	if DirAccess.make_dir_recursive_absolute(output) != OK: quit(2); return
	region = {"whale":"I1","crown":"F1","campaign":"F2"}[boss]
	began = Time.get_ticks_msec()
	create_timer(45.0).timeout.connect(func():
		if not finished:
			_check(false,"45 second actual MAIN per-Boss wall bound",_diagnostics())
			_finish())
	session = MAIN.instantiate()
	root.add_child(session)
	if not _check(session.profile_ready and session.store.root_path == "user://profiles_v3/"+profile and session.start_flight("solo"),"actual MAIN starts only the named fresh private QA Store"): _finish(); return
	for unused in 3:
		if not await _frame(): return
	if region != "I1" and not _check(session._load_region(region),"ordinary factory loads the empty QA region before any rule fixture",_diagnostics()): _finish(); return
	session.inputs.test_enabled = true
	session.inputs.test_frame = {"axes":{},"held":["brake"],"edges":[]}
	if not _check(session.network.is_authority() and session.world.build_errors.is_empty() and _bridge(session,"_fire"),"post-patch Host Session exposes two-argument bool fire without replacing MAIN",_diagnostics()): _finish(); return
	if boss == "crown" and not _check(session.crown.ready() and _bridge(session.crown,"fire"),"real imported Crown plus patched adapter are available"): _finish(); return
	if boss == "campaign" and not _check(session.campaign.supported() and _bridge(session.campaign,"fire"),"real F2 Campaign plus patched adapter are available"): _finish(); return
	var ok := false
	match boss:
		"whale": ok = await _whale()
		"crown": ok = await _crown()
		"campaign": ok = await _campaign()
	if finished: return
	_check(ok,"selected real Boss completes amount/accepted regression")
	_finish()

func _bridge(owner_object: Object, method: String) -> bool:
	for entry: Dictionary in owner_object.get_method_list():
		if entry.name == method: return entry.args.size() == 2 and int(entry.get("return",{}).get("type",TYPE_NIL)) == TYPE_BOOL
	return false

func _whale() -> bool:
	if not _check(session.world.whale_ready(),"real imported Whale hit bodies are ready"): return false
	if not await _place_near(session.world.boss_parts.port.global_position,"boss:port",false): return false
	session._start_boss(false) # Real production encounter; explicitly not a Story victory fixture.
	if not _check(session.boss_active and not session.boss_campaign and not _state().is_empty(),"original Whale development start creates the real encounter"): return false
	fixtures.append({"kind":"development_start","boss":"harbor_whale"})
	if not await _closed_rejection("boss:port"): return false
	return await _common("boss:port")

func _crown() -> bool:
	if not await _place_near(session.world.crown_arena.host_position(WEST),WEST,true,3.0): return false
	session._start_boss(false)
	if not _check(session.crown.active() and not session.boss_campaign,"original Crown development start enrolls the actual actor inside combat space"): return false
	fixtures.append({"kind":"development_start","boss":"parasitic_crown"})
	if not await _closed_rejection("boss:crown_core"): return false
	if not await _place_near(session.world.crown_arena.host_position(WEST),WEST,true,3.0): return false
	if not await _ability("light",WEST,"on"): return false
	if not await _ability("growth",WEST,""): return false
	if not _check(bool(_state().get("core_open",false)),"original light and growth transactions open real Crown plates",_state()): return false
	return await _common("boss:crown_core")

func _campaign() -> bool:
	if not _plan_fixture(): return false
	var centre: Vector3 = session.world.campaign_arena.centre()
	var entered := false
	for offset: Vector3 in [Vector3(6,6,-9),Vector3(-6,6,-9),Vector3(0,5,0),Vector3(6,6,6),Vector3(-6,6,6)]:
		var at := centre+offset
		if at.z <= float(Layout.definition(region).boss_arena.entry_z) and at.distance_to(centre) <= 16.0 and _clear_pose(at):
			entered = await _place(at)
			break
	if not _check(entered,"explicit QA pose crosses the real authored F2 engagement boundary"): return false
	for unused in 120:
		if session.campaign.active(): break
		if not await _frame(): return false
	if not _check(session.campaign.active(),"ordinary MAIN starts the actual F2 encounter through its original plan and geometry gates",_diagnostics()): return false
	var target: String = session.world.campaign_arena.target_id("true_left_wing")
	if not await _closed_rejection(target): return false
	if not await _place_near(session.world.objects["F2:reveal_source"].global_position,"F2:reveal_source",true,4.0): return false
	if not await _ability("light","F2:reveal_source","on"): return false
	for unused in 120:
		var environment: Dictionary = session.campaign.mechanisms.boss_environment(region)
		if environment.get("true_body_revealed",false) and environment.get("shadow_verified",false): break
		if not await _frame(): return false
	var actual: Dictionary = session.campaign.mechanisms.boss_environment(region)
	if not _check(actual.get("true_body_revealed",false) and actual.get("shadow_verified",false),"original light ability produces the actual emitter/true-body shadow environment",actual): return false
	return await _common(target)

func _plan_fixture(plan_id: String = PLAN) -> bool:
	var director = session.story.director
	var state: Dictionary = director.default_state()
	var found := false
	var count := 0
	for action: Dictionary in director.definitions().actions:
		for objective: Dictionary in action.objectives:
			var matcher: Dictionary = objective.events[0]
			var applied: Dictionary = director.apply_event(state,{"id":"qa-hit-amount:"+str(objective.id),"type":matcher.type,"target_id":matcher.target_id,"option":matcher.options[0]},{"is_authority":true,"validated":true,"region_id":action.region_id})
			if not applied.get("ok",false) or not applied.get("changed",false): return _check(false,"ordered Director-only fixture remains rule-valid",{"objective":objective.id,"result":applied})
			state = applied.state
			count += 1
			if objective.id == plan_id: found = true; break
		if found: break
	if not _check(found and director.validate_state(state).get("ok",false),"Director-only fixture stops at the requested plan; previous history was not flown",{"count":count,"stop":plan_id}): return false
	var committed: Dictionary = session.store.commit({"id":"qa-hit-amount-rule-prefix","set":{"world.actions.opening":state}})
	if not _check(committed.get("ok",false),"rule prefix is saved only after actual empty F2 factory load",committed): return false
	session.world_cache = session.store.snapshot()
	session.consensus.set_world_revision(int(session.world_cache.world_revision))
	session.story.load_world()
	fixtures.append({"kind":"Director_rules_only_not_natural_progression","stop":plan_id,"count":count})
	return true

func _closed_rejection(target: String) -> bool:
	if not await _wait_weapon(): return false
	if not await _place_near(_point(target),target,boss == "campaign"): return false
	if not _check(not _open(target),"original read-only armor gate is closed before preparation",{"target":target,"state":_state()}): return false
	return _attempt(target,28.0,false,0.0,"closed physical/rules armor",false)

func _common(target: String) -> bool:
	# Use a real, lockable non-weapon entity. Do not mutate the lock dictionary.
	var wrong := ""
	for id: String in session.entities:
		if id != "player:1" and not id.begins_with("boss:") and not id.begins_with("campaign:") and session.world.objects.has(id) and session.players[1].global_position.distance_to(session.entities[id].position) <= 55.0: wrong = id; break
	if not _check(not wrong.is_empty(),"an original nearby non-Boss entity exists for the wrong-target gate"): return false
	if not await _wait_weapon(): return false
	if not _attempt(wrong,28.0,false,0.0,"actual non-weapon target",false): return false
	if not await _ready_open(target): return false
	if not _attempt(target,9.0,true,9.0,"omitted argument retains pulse9",true): return false
	var hp: Dictionary = _hp()
	var immediate: Variant = session.call("_fire",1,28.0)
	if not _check(immediate is bool and immediate == false and _hp() == hp,"original immediate attempt cooldown returns false without HP change",{"returned":immediate,"cooldown":session.weapon_cooldowns.get(1),"hp":_hp()}): return false
	if boss == "campaign":
		var wrong_part: String = session.world.campaign_arena.target_id("true_right_wing")
		if not await _wait_weapon(): return false
		if not await _place_near(_point(wrong_part),wrong_part,true): return false
		if not _check(not _open(wrong_part) and session.campaign.encounter.current_part() == "true_left_wing","real next F2 part remains closed after pulse9 on its original first part"): return false
		if not _attempt(wrong_part,28.0,false,0.0,"real non-current Boss part",false): return false
		# Each authored F2 wing has only 30HP. Finish the actual remaining 21HP
		# through a real shot, then measure full28 on its fresh original second wing.
		if not await _ready_open(target): return false
		if not _check(is_equal_approx(_target_hp(target),21.0),"actual first F2 wing retains exactly 21HP after default pulse"): return false
		if not _attempt(target,21.0,true,21.0,"real shot disables remaining first-wing21 without changing authored HP",false): return false
		target = wrong_part
	if not await _ready_open(target): return false
	if not _attempt(target,28.0,true,28.0,"Host internal real28 reaches original Encounter",false): return false
	if not await _ready_open(target): return false
	# This rejection reaches the real hit implementation after valid geometry.
	# Campaign's public adapter uses milli units; Session rejects invalid real input earlier.
	if not _attempt(target,0.0,false,0.0,"original Encounter rejects zero amount even with open armor and clear LOS",false,boss == "campaign"): return false
	if not await _ready_open(target): return false
	var actor: FlightBodyV2 = session.players[1]
	var wall := StaticBody3D.new()
	wall.name = "ExplicitQAWeaponLOSBlocker"
	wall.collision_layer = 1
	wall.collision_mask = 0
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3.ONE*0.8
	collision.shape = shape
	wall.add_child(collision)
	session.world.add_child(wall)
	wall.global_position = actor.global_position.lerp(_point(target),0.5)
	for unused in 2:
		if not await _frame(): wall.queue_free(); return false
	var blocked: bool = not session._line_clear(actor.global_position,_point(target),actor.get_rid(),target)
	var armor_was_open: bool = _open(target)
	var ok: bool = _check(blocked and armor_was_open,"temporary actual opaque body blocks LOS while original armor is open",{"target":target,"open":armor_was_open,"ray":_ray(target)})
	if ok: ok = _attempt(target,28.0,false,0.0,"actual opaque LOS obstacle",false)
	wall.queue_free()
	if not await _frame(): return false
	return ok

func _attempt(target: String, amount: float, accepted: bool, delta: float, label: String, omitted: bool, direct_campaign: bool = false) -> bool:
	session._action_received(1,"lock",{"target_id":target})
	if not _check(str(session.locks.get(1,"")) == target,"original lock action selects "+label,target): return false
	var before: Dictionary = _hp()
	var before_value: float = _target_hp(target)
	var before_state: Dictionary = _state()
	var before_shots: int = session.stats.shots
	var ray: Dictionary = _ray(target)
	var original_open: bool = _open(target)
	var result: Variant
	if direct_campaign: result = session.campaign.call("fire",1,0)
	elif omitted: result = session.call("_fire",1)
	else: result = session.call("_fire",1,amount)
	var after: Dictionary = _hp()
	var receipt := {"label":label,"api":"Campaign.fire(milli)" if direct_campaign else "Session._fire(real)","omitted":omitted,"amount":0 if direct_campaign else amount,"target":target,"returned":result,"return_type":typeof(result),"expected_accepted":accepted,"hp_before":before,"hp_after":after,"target_hp_before":before_value,"target_hp_after":_target_hp(target),"expected_delta":delta,"original_open":original_open,"ray":ray,"shots_before":before_shots,"shots_after":session.stats.shots,"physics_frame":Engine.get_physics_frames(),"encounter_before":before_state,"encounter_after":_state(),"weapon_cooldown_after":session.weapon_cooldowns.get(1,0)}
	shots.append(receipt)
	var valid: bool = result is bool and result == accepted
	if accepted: valid = valid and is_equal_approx(before_value-_target_hp(target),delta) and original_open and ray.get("clear",false)
	else: valid = valid and before == after
	if boss == "campaign" and label in ["closed physical/rules armor","real non-current Boss part"]:
		# Target + native ray passed the adapter: this is the original part_shielded
		# result, not an early geometry rejection mislabeled as an Encounter test.
		valid = valid and ray.get("clear",false) and session.stats.shots == before_shots+1 and int(_state().last_sequences.get("1",0)) > int(before_state.last_sequences.get("1",0))
	if label == "original Encounter rejects zero amount even with open armor and clear LOS":
		valid = valid and original_open and ray.get("clear",false) and session.stats.shots == before_shots+(0 if boss == "crown" else 1)
	return _check(valid,label+": exact bool and original HP",receipt)

func _ready_open(target: String) -> bool:
	var deadline := Time.get_ticks_msec()+10000
	while not finished and Time.get_ticks_msec() < deadline:
		if float(session.weapon_cooldowns.get(1,0)) <= 0.0 and _open(target):
			if not await _place_near(_point(target),target,true): return false
			if _open(target) and _ray(target).get("clear",false): return true
		if not await _frame(): return false
	return _check(false,"ordinary physics exposes the original target within ten seconds",_diagnostics())

func _wait_weapon() -> bool:
	for unused in 180:
		if float(session.weapon_cooldowns.get(1,0)) <= 0.0: return true
		if not await _frame(): return false
	return _check(false,"original attempt cooldown elapses by ordinary MAIN ticks")

func _ability(ability: String, target: String, mode: String) -> bool:
	for unused in 180:
		if float(session.cooldowns.get(1,0)) <= 0.0: break
		if not await _frame(): return false
	var before: int = session.stats.abilities
	session._action_received(1,"ability",{"ability":ability,"target_id":target,"mode":mode})
	if not await _frame(): return false
	return _check(session.stats.abilities == before+1,"original ability accepts "+ability+" at "+target,{"state":_state(),"message":session.interface.message.text})

func _place_near(point: Vector3, target: String, require_los: bool, radius: float = 7.0) -> bool:
	# Whale's real hatch has an overhead aperture; do not assume a horizontal
	# ring provides LOS through it even during the original open window.
	for offset: Vector3 in [Vector3(0,radius,0),Vector3(0,-radius,0)]:
		var at := point+offset
		if _clear_pose(at) and (not require_los or session._line_clear(at,point,session.players[1].get_rid(),target)):
			return await _place(at)
	for height: float in [0.0,3.0,5.0,-1.0]:
		for index in 16:
			var angle := TAU*float(index)/16.0
			var at := point+Vector3(cos(angle)*radius,height,sin(angle)*radius)
			if _clear_pose(at) and (not require_los or session._line_clear(at,point,session.players[1].get_rid(),target)):
				return await _place(at)
	return _check(false,"actual hull/LOS permits bounded QA observation pose",{"target":target,"point":point,"require_los":require_los,"diagnostics":_diagnostics()})

func _clear_pose(at: Vector3) -> bool:
	if not Regions.contains(region,at): return false
	if boss == "crown" and not session.world.crown_arena.in_combat_space(at): return false
	var actor: FlightBodyV2 = session.players[1]
	var envelope := actor.get_node("Envelope") as CollisionShape3D
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = envelope.shape
	query.transform = Transform3D(Basis.IDENTITY,at)*envelope.transform
	query.collision_mask = 1|2|8|32
	query.exclude = [actor.get_rid()]
	return session.world.get_world_3d().direct_space_state.intersect_shape(query,1).is_empty()

func _place(at: Vector3) -> bool:
	var actor: FlightBodyV2 = session.players[1]
	actor.freeze = true
	actor.global_transform = Transform3D(Basis.IDENTITY,at)
	actor.force_update_transform()
	PhysicsServer3D.body_set_state(actor.get_rid(),PhysicsServer3D.BODY_STATE_TRANSFORM,actor.global_transform)
	actor.linear_velocity = Vector3.ZERO
	actor.angular_velocity = Vector3.ZERO
	actor.hold_height = at.y
	poses.append({"physics_frame":Engine.get_physics_frames(),"at":at,"kind":"explicit_QA_player_only_not_flown"})
	for unused in 2:
		if not await _frame(): return false
	return true

func _point(target: String) -> Vector3:
	if boss == "crown" and target == "boss:crown_core": return session.world.crown_arena.core_position()
	if boss == "campaign" and session.world.campaign_arena.targets.has(target): return session.world.campaign_arena.targets[target].global_position
	return session.entities.get(target,{}).get("position",Vector3.INF)

func _ray(target: String) -> Dictionary:
	var actor: FlightBodyV2 = session.players[1]
	var point := _point(target)
	if not point.is_finite(): return {"clear":false,"code":"target_point_missing"}
	var query := PhysicsRayQueryParameters3D.create(actor.global_position,point,1|8)
	query.exclude = [actor.get_rid()]
	var hit: Dictionary = session.get_world_3d().direct_space_state.intersect_ray(query)
	return {"clear":session._line_clear(actor.global_position,point,actor.get_rid(),target),"distance":actor.global_position.distance_to(point),"first_entity":str(hit.collider.get_meta("entity_id","")) if hit.has("collider") else "","first_path":str(hit.collider.get_path()) if hit.has("collider") else "","from":actor.global_position,"to":point}

func _state() -> Dictionary:
	if not is_instance_valid(session): return {}
	if boss == "crown": return session.crown.encounter.get_state()
	if boss == "campaign": return session.campaign.encounter.get_state() if session.campaign.encounter != null else {}
	return session.encounter.get_state()

func _hp() -> Dictionary:
	var state := _state()
	if state.is_empty(): return {}
	if boss == "whale": return {"port":state.nodes.port.health,"starboard":state.nodes.starboard.health,"core":state.core_health}
	if boss == "crown": return {"core_hp_milli":state.core_hp_milli}
	return {"parts":state.parts.duplicate(true),"core_hp_milli":state.core_hp_milli}

func _target_hp(target: String) -> float:
	var state := _state()
	if boss == "whale": return float(state.nodes.get(target.trim_prefix("boss:"),{}).get("health",state.core_health))
	if boss == "crown": return float(state.core_hp_milli)/1000.0
	return float(state.parts.get(session.world.campaign_arena.part_id(target),state.core_hp_milli))/1000.0

func _open(target: String) -> bool:
	var state := _state()
	if state.is_empty() or state.get("completed",false): return false
	if boss == "crown": return target == "boss:crown_core" and bool(state.core_open)
	if boss == "campaign": return session.campaign.owns_target(target) and session.campaign.encounter.part_open(session.world.campaign_arena.part_id(target))
	var part := target.trim_prefix("boss:")
	return float(state.exposed_remaining) > 0.0 if part == "core" else bool(state.nodes_open) and bool(state.nodes.get(part,{}).get("powered",false))

func _frame() -> bool:
	await physics_frame
	await process_frame # No test clock advance; ordinary MAIN owns simulation.
	return not finished

func _diagnostics() -> Dictionary:
	if not is_instance_valid(session): return {"session":"not_installed"}
	return {"region":session.region_id,"active":session.active,"boss_active":session.boss_active,"boss_campaign":session.boss_campaign,"state":_state(),"message":session.interface.message.text,"generation":session.store.snapshot().generation,"world_errors":session.world.build_errors if is_instance_valid(session.world) else [],"weapon_cooldown":session.weapon_cooldowns.get(1,0),"actor_enabled":session.players[1].enabled if session.players.has(1) else false}

func _check(ok: bool, label: String, actual: Variant = null) -> bool:
	checks.append({"passed":ok,"label":label,"actual":actual})
	return ok

func _scope() -> String:
	return SCOPE

func _finish() -> void:
	if finished: return
	finished = true
	var diagnostics := _diagnostics()
	var drain: Dictionary = {}
	if is_instance_valid(session):
		session.active = false # QA terminal teardown only; not a gameplay pause/save claim.
		session.environment_save_gate.cancel("qa_hit_amount_teardown")
		session.network.close()
		session.audio.shutdown()
		var deadline := Time.get_ticks_msec()+1000
		while Time.get_ticks_msec() < deadline:
			drain = session.audio.shutdown_status()
			if drain.get("ready",false): break
			await process_frame
		_check(drain.get("ready",false),"original audio shutdown drains in bounded QA terminal cleanup",drain)
		if session.canal != null: session.canal.clear()
		session.thermal_cargo.clear()
		session.free()
	session = null
	await process_frame
	await physics_frame
	await process_frame
	var failures: Array = checks.filter(func(row: Dictionary): return not row.passed)
	var report := {"boss":boss,"region":region,"profile":profile,"checks":checks,"failures":failures,"engine_errors":logger.errors,"shots":shots,"poses":poses,"fixtures":fixtures,"final_diagnostics":diagnostics,"audio_drain":drain,"wall_seconds":float(Time.get_ticks_msec()-began)/1000.0,"scope":_scope()}
	FileAccess.open(output+"/result.json",FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
	print("BOSS_HIT_AMOUNT_RESULT "+JSON.stringify({"boss":boss,"checks":checks.size(),"failures":failures,"engine_errors":logger.errors,"wall_seconds":report.wall_seconds}))
	quit(0 if failures.is_empty() and logger.errors.is_empty() else 1)
