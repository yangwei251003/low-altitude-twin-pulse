extends SceneTree
## Real MAIN / Session / Store / PhysicsServer integration. No sockets or GPU.
## The previous 27 objectives and pilot starting placements are explicit QA
## fixtures, not a playthrough. Cabinet success is never assigned: abilities go
## through Session and G reads the actual two physical plates. Network ordering
## below injects packets into real consumers; it is not an ENet transport test.
const MAIN = preload("res://scenes/v3/main.tscn")
const Store = preload("res://scripts/v3/core/twin_world_store.gd")
const Director = preload("res://scripts/v3/gameplay/actions/twin_action_director.gd")
const ActionData = preload("res://tests_v3/test_clinic_action.gd") # Constants only.
const Cabinet = preload("res://scripts/v3/world/twin_distribution_cabinet.gd")
const Progress = preload("res://scripts/v3/gameplay/actions/twin_distribution_progress.gd")
const Works = preload("res://scripts/v3/world/twin_clinic_waterworks.gd")
const Contract = preload("res://scripts/v3/network/twin_facility_contract.gd")
const Codec = preload("res://scripts/v3/network/twin_snapshot_codec.gd")
const DT := 0.1
var session
var profile := ""
var base := ""
var phase := "setup"
var checks: Array = []
var failures: Array = []
var samples: Array = []
var same_epoch_followup: Dictionary = {}
var trial_only_followup: Dictionary = {}
var bridge_only_followup: Dictionary = {}
var history_fixture: Dictionary = {}
var original_personal: Dictionary = {}
var first_manual_history: Dictionary = {}
var done := false
var expecting_observation_write_failure := false

class TestLogger extends Logger:
	var errors: Array = []
	var guard := Mutex.new()
	func _log_error(function: String, file: String, line: int, code: String, rationale: String, _editor_notify: bool, error_type: int, _script_backtraces: Array[ScriptBacktrace]) -> void:
		guard.lock()
		errors.append({"function":function,"file":file,"line":line,"code":code,"rationale":rationale,"type":error_type})
		guard.unlock()
var error_logger := TestLogger.new()

func _initialize() -> void:
	OS.add_logger(error_logger)
	_run.call_deferred()

func check(ok: bool, label: String, detail: Variant = null) -> void:
	checks.append({"phase":phase,"label":label,"passed":ok,"detail":detail})
	if not ok: failures.append(label)

func _run() -> void:
	var profiles := 0
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--qa-profile="):
			profile = arg.trim_prefix("--qa-profile=")
			profiles += 1
		elif arg.begins_with("--qa-network") or arg.begins_with("--qa-capture") or arg.begins_with("--qa-suite"):
			check(false,"refuse automatic networking, capture and suite drivers")
			_finish(2)
			return
	if profiles != 1 or not profile.begins_with("qa_distribution_") or profile != profile.validate_filename():
		check(false,"require one fresh --qa-profile=qa_distribution_<unique>")
		_finish(2)
		return
	base = "user://qa_v3_distribution_session/" + profile
	if DirAccess.dir_exists_absolute(base) or DirAccess.dir_exists_absolute("user://profiles_v3/" + profile):
		check(false,"refuse an existing QA profile or evidence directory")
		_finish(2)
		return
	create_timer(120.0).timeout.connect(func():
		if not done:
			check(false,"bounded Session test timed out")
			_finish(2))
	session = MAIN.instantiate()
	if not _main_usable():
		check(false,"MAIN must retain its Session script before entering tree")
		_finish(1)
		return
	root.add_child(session)
	if not _disable_callbacks():
		_finish(1)
		return
	check(session.profile_ready and session.start_flight("solo"),"real MAIN starts solo with the fresh QA profile")
	if not session.active or not _seed_history():
		_finish(1)
		return
	await _first_entry()
	if _healthy(): await _manual_pending()
	if _healthy(): await _electric_branch_and_leave()
	if _healthy(): await _return_main()
	if _healthy(): await _guest_ordering()
	_finish(0 if failures.is_empty() else 1)

func _has_property(name: String) -> bool:
	if not is_instance_valid(session): return false
	for item in session.get_property_list():
		if str(item.name) == name: return true
	return false

func _main_usable() -> bool:
	if not is_instance_valid(session) or session.get_script() == null or not session.has_method("start_flight"): return false
	for name in ["active","network","inputs","players","profile_ready","store","clinic","distribution","trial","world","story"]:
		if not _has_property(name): return false
	return true

func _healthy() -> bool:
	if not error_logger.errors.is_empty() and failures.is_empty(): check(false,"engine errors stop this integration fixture",error_logger.errors.duplicate(true))
	return not done and failures.is_empty() and error_logger.errors.is_empty()

func _disable_callbacks() -> bool:
	if not _main_usable() or not _healthy():
		check(false,"usable MAIN and error-free initialization are required before member access")
		return false
	if not is_instance_valid(session.inputs) or not session.players is Dictionary:
		check(false,"Session must initialize inputs and its real player registry")
		return false
	# Do not set PROCESS_MODE_DISABLED: Jolt bodies must stay in the real space.
	session.set_process(false)
	session.set_physics_process(false)
	session.inputs.set_process(false)
	session.inputs.set_physics_process(false)
	_freeze_bodies()
	return true

func _freeze_bodies() -> void:
	for body in session.players.values():
		body.freeze = true
		body.set_process(false)
		body.set_physics_process(false)
		body.linear_velocity = Vector3.ZERO
		body.angular_velocity = Vector3.ZERO

func _seed_history() -> bool:
	var old = Director.new()
	var loaded: Dictionary = old.load_definitions(Director.DEFAULT_PATH,ActionData.OLD_EXTENSIONS)
	check(loaded.ok,"historical fixture loads the real seven-action definitions")
	if not loaded.ok: return false
	var state: Dictionary = old.default_state()
	for row in ActionData.OLD_EVENTS:
		var result: Dictionary = old.apply_event(state,{"id":"qa-distribution-old:"+str(row[0]),"type":row[1],"target_id":row[2],"option":row[3]}, {"is_authority":true,"validated":true,"region_id":str(row[0]).get_slice(":",0)})
		if not result.get("changed",false):
			check(false,"fixed historical event must be accepted",{"goal":row[0],"code":result.get("code")})
			return false
		state = result.state
	check(state.completed.size()==27 and state.completed_actions.size()==7 and session.story.director.validate_state(state).ok,"old 27-objective state remains valid; new distribution action stays uncompleted by the old27 fixture")
	var saved: Dictionary = session.store.commit({"id":"qa-distribution-history","set":{"world.actions.opening":state,"world.flags":state.flags,"world.completed_objectives":state.completed},"append":{"personal.discoveries":state.discoveries}})
	check(saved.ok,"explicit predecessor history is committed once in the isolated real Store")
	if not saved.ok: return false
	session.world_cache = session.store.snapshot()
	check(session._load_region("I1"),"production reload accepts predecessor history before I2 exists")
	session.consensus.configure([1],int(session.world_cache.world_revision))
	_freeze_bodies()
	history_fixture = state.duplicate(true)
	original_personal = session.store.snapshot().personal.duplicate(true)
	return _healthy()

func _steps(count: int, delta: float = DT) -> void:
	for unused in range(count):
		if not _healthy(): return
		await physics_frame
		session._physics_process(delta)
		for name in ["clinic","distribution","trial"]:
			var adapter = session.get(name)
			if not str(adapter.error).is_empty():
				if name=="distribution" and expecting_observation_write_failure and str(adapter.error)=="distribution_observation_save_failed" and session.distribution.has_pending_observation(): continue
				check(false,"production "+name+" advance rejected",{"error":adapter.error})
				return

func _place(at: Vector3, peer: int = 1) -> void:
	# Explicit starting placement, not a route or a completed objective.
	var body = session.players[peer]
	body.global_transform = Transform3D(Basis.IDENTITY,at)
	body.linear_velocity = Vector3.ZERO
	body.angular_velocity = Vector3.ZERO
	body.force_update_transform()
	PhysicsServer3D.body_set_state(body.get_rid(),PhysicsServer3D.BODY_STATE_TRANSFORM,body.global_transform)
	session.entities[session._actor_id(peer)].position = at
	await physics_frame
	await physics_frame

func _body_clear(peer: int = 1) -> bool:
	var body = session.players[peer]
	var shape := BoxShape3D.new()
	shape.size = Vector3(float(body.stats.width_m),float(body.stats.height_m),float(body.stats.length_m))
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = shape
	query.transform = body.global_transform
	query.collision_mask = 0xFFFFFFFF
	query.exclude = [body.get_rid()]
	query.margin = 0.0
	return body.get_world_3d().direct_space_state.intersect_shape(query,1).is_empty()

func _move(to: Vector3, label: String) -> bool:
	var body = session.players[1]
	check(_body_clear(),label+": actual complete hull starts clear")
	if not _healthy(): return false
	var collision: KinematicCollision3D
	var count := 0
	while body.global_position.distance_to(to)>0.002 and count<100:
		var motion: Vector3 = (to-body.global_position).limit_length(0.2)
		collision = body.move_and_collide(motion)
		await _steps(1,1.0/60.0)
		count += 1
		if collision != null or not _healthy(): break
	var ok: bool = collision==null and body.global_position.distance_to(to)<0.005 and _body_clear()
	check(ok,label,{"actual":str(body.global_position),"target":str(to),"collider":str(collision.get_collider().get_path()) if collision!=null else ""})
	return ok

func _ability(ability: String, target: String, mode: String = "") -> bool:
	for unused in range(20):
		if float(session.cooldowns.get(1,0.0))<=0.0: break
		await _steps(1)
	if not _healthy(): return false
	var before: int = int(session.stats.abilities)
	session._action_received(1,"ability",{"ability":ability,"target_id":target,"mode":mode})
	var accepted: bool = int(session.stats.abilities)==before+1
	check(accepted,"actual Session accepts "+ability+"/"+mode+" on "+target,{"message":session.interface.message.text})
	return accepted

func _g() -> void:
	session.interface.clear_dialogue()
	session.interface.menu.hide()
	var event := InputEventKey.new()
	event.pressed = true
	event.keycode = KEY_G
	event.physical_keycode = KEY_G
	session._unhandled_input(event)

func _disk(value: Variant) -> Variant:
	# Store uses full-precision JSON. Exact comparisons use that same representable
	# form, not a tolerance for fractional seconds or integer state changes.
	return JSON.parse_string(JSON.stringify(value,"",true,true))

func _same(a: Variant, b: Variant) -> bool: return _disk(a)==_disk(b)

func _unchanged_story(label: String) -> void:
	var saved: Dictionary = session.store.snapshot()
	check(_same(session.story.state,history_fixture) and _same(saved.world.actions.opening,history_fixture) and saved.world.completed_objectives==history_fixture.completed,label+": early knowledge does not complete any action")
	check(not saved.world.flags.has(Progress.OBSERVED_FLAG) and Progress.EXPOSE not in saved.world.completed_objectives,label+": no premature expose flag/objective")

func _fork(id: String) -> void:
	check(session._save_environment(),"save current physical state before branch "+id)
	if not _healthy(): return
	check(session.store.fork_branch(id,"Distribution QA "+id,false).ok,"real Store forks independent branch "+id)
	session.world_cache = session.store.snapshot()
	session.consensus.set_world_revision(int(session.world_cache.world_revision))

func _travel(id: String) -> void:
	var proposal: Dictionary = session.consensus.current_proposal()
	if proposal.get("state")=="ready" and proposal.get("kind")=="region_change" and proposal.get("payload",{}).get("region_id")==id:
		session._action_received(1,"confirm",{"proposal_id":proposal.proposal_id,"world_revision":proposal.world_revision})
	else:
		session._ui_action("travel_to",{"region_id":id})
	check(session.region_id==id and session.consensus.current_proposal().is_empty(),"real one-player travel commits/adopts "+id,{"actual":session.region_id,"message":session.interface.message.text})
	_freeze_bodies()
	await physics_frame

func _switch(id: String) -> void:
	session._ui_action("branch",{"id":id})
	check(session.store.snapshot().world.branch_id==id and session.active,"real branch transition adopts "+id,{"message":session.interface.message.text})
	_freeze_bodies()
	await physics_frame

func _check_pose(label: String) -> void:
	var module = session.distribution.module
	var correct := true
	for body in [module.cover,module.door]:
		var actual: Transform3D = PhysicsServer3D.body_get_state(body.get_rid(),PhysicsServer3D.BODY_STATE_TRANSFORM)
		correct = correct and actual.is_equal_approx(body.global_transform)
	check(correct,label+": cover and door immediately match PhysicsServer")
	var target_ok := true
	for id in [Cabinet.COVER_ID,Cabinet.RELAY_ID,Cabinet.LOCK_ID]:
		var actual: Variant = session.entities.get(id,{}).get("position")
		target_ok = target_ok and actual is Vector3 and actual.is_equal_approx(module.entity_position(id))
	check(target_ok,label+": all three real targets keep their own positions, never clinic null")
	var ray := PhysicsRayQueryParameters3D.create(Vector3(18,2.3,-7.7),Vector3(18,2.3,-10.6),1|8)
	var hit: Dictionary = module.get_world_3d().direct_space_state.intersect_ray(ray)
	var fraction: float = float(module.snapshot().door_fraction)
	if fraction==0.0: check(not hit.is_empty() and hit.collider==module.door,label+": closed physical door is the first ray hit")
	elif fraction==1.0: check(hit.is_empty(),label+": fully raised door leaves the real low approach clear",{"hit":str(hit.get("collider"))})

func _first_entry() -> void:
	phase = "first_entry_prepare_atomicity"
	check(session._save_environment(),"settle old-region persistence before isolating the first I2 initialization failure")
	if not _healthy(): return
	var before: Dictionary = session.store.snapshot()
	var old_world = session.world
	session.store.failure_point = "before_publish"
	session._ui_action("travel_to",{"region_id":"I2"})
	check(session.region_id=="I1" and session.world==old_world and session.store.snapshot()==before,"first I2 initialization write failure does not adopt candidate or modify old save")
	check(not session.store.snapshot().world.get("environment",{}).has("I2_distribution"),"failed first-entry transaction cannot leave a partial cabinet envelope")
	session.store.failure_point = ""
	await _travel("I2")
	if not _healthy(): return
	check(session.distribution.ready and session.clinic.ready and is_instance_valid(session.distribution.module),"both real I2 adapters are ready after successful initialization")
	if not _healthy(): return
	check(session.distribution.module.get_world_3d()==session.world.get_world_3d(),"cabinet lives in the visible I2 physics space")
	var saved: Dictionary = session.store.snapshot()
	var envelope: Dictionary = saved.world.environment.get("I2_distribution",{})
	check(envelope.has("mechanism") and envelope.has("history") and not envelope.history.back_observed and envelope.mechanism.door_fraction==0.0 and envelope.mechanism.axis.position_m==0.0,"first entry persists closed mechanism and empty history before play")
	_unchanged_story("first entry")
	_check_pose("first entry")
	_fork("closed-before-observation")
	await _place(Vector3(18,5.75,-10.6))
	check(_body_clear(),"closed high-well observation fixture starts outside real geometry")
	check(session.story.nearest(session.players[1].global_position)==Progress.FACT_TARGET,"G exposes the independent inspection before clinic diagnosis is complete")
	before = session.store.snapshot()
	_g()
	check(not session.distribution.progress.snapshot().back_observed and not session.distribution.has_pending_observation() and session.store.snapshot()==before,"closed cabinet G does not create knowledge or a transaction")
	session._action_received(1,"explore",{"target_id":Progress.FACT_TARGET,"method":"manual","panel_hits":[5,5],"center_hits":[true,true],"validated":true})
	check(not session.distribution.progress.snapshot().back_observed and session.store.snapshot()==before,"client-authored hit counts and method cannot bypass actual closed geometry")

func _manual_pending() -> void:
	phase = "manual_observation_failed_save"
	await _place(Vector3(17.6,5.75,-10.6))
	for unused in range(4):
		if float(session.distribution.module.snapshot().axis.position_m)>=1.2: break
		if not await _ability("push_pull",Cabinet.COVER_ID): return
		await _steps(7,0.05)
	await _steps(8)
	check(float(session.distribution.module.snapshot().axis.position_m)>1.0,"real impulses open the physical inspection well")
	await _place(Vector3(18,5.75,-10.6))
	var proof: Dictionary = session.distribution.module.observe_back(1,session.players[1])
	check(proof.ok and proof.method=="manual","host physics sees both real plates through the open high well",proof)
	if not _healthy(): return
	var disk_before: Dictionary = session.store.snapshot()
	expecting_observation_write_failure = true
	session.store.failure_point = "before_publish"
	_g()
	check(session.distribution.has_pending_observation() and not session.distribution.progress.snapshot().back_observed and session.store.snapshot()==disk_before,"failed real G write retains pending proof but no committed knowledge or save changes")
	var observed: Dictionary = session.distribution.module.snapshot()
	# The fully retracted cover sits below the right upper deck. Approach its
	# real service cavity from the east; do not aim through that solid deck.
	await _place(Vector3(22,4.6,-11.45))
	check(_body_clear(),"east service-cavity approach keeps the real hull clear")
	if not await _ability("push_pull",Cabinet.COVER_ID): return
	await _steps(5)
	var latest: Dictionary = session.distribution.module.snapshot()
	check(float(latest.axis.position_m)<float(observed.axis.position_m) and int(latest.serial)>int(observed.serial),"mechanism continues moving after failed observation save",{"observed":observed,"latest":latest})
	check(session.distribution.has_pending_observation() and session.store.snapshot()==disk_before and not session.distribution.progress.snapshot().back_observed,"automatic retries under write failure preserve first proof without adopting it")
	var old_world = session.world
	session._ui_action("travel_to",{"region_id":"I1"})
	check(session.region_id=="I2" and session.world==old_world and session.distribution.has_pending_observation() and session.store.snapshot()==disk_before,"pending evidence plus failed storage cannot be discarded by travel")
	# A failed travel may leave a ready proposal. Cancel only that proposal using
	# the real action, then retry the existing proof without another G or ray.
	var proposal: Dictionary = session.consensus.current_proposal()
	if not proposal.is_empty(): session._action_received(1,"cancel",{"proposal_id":proposal.proposal_id})
	session.store.failure_point = ""
	latest = session.distribution.module.snapshot()
	check(session.distribution.retry_pending(),"explicit retry succeeds when storage recovers without repeating G")
	expecting_observation_write_failure = false
	var saved: Dictionary = session.store.snapshot()
	check(not session.distribution.has_pending_observation() and session.distribution.progress.snapshot().back_observed,"successful write precedes committed Progress adoption")
	check(_same(saved.world.environment.I2_distribution.mechanism,latest) and _same(session.distribution.module.snapshot(),latest),"retry writes the latest physical mechanism and never restores the old observation pose")
	first_manual_history = session.distribution.progress.snapshot()
	check(first_manual_history.method=="manual" and int(first_manual_history.evidence.mechanism_serial)==int(observed.serial),"retry retains the first observation's original serial and manual route")
	_unchanged_story("manual knowledge")
	check(_same(saved.personal,original_personal),"early observation adds no discovery, collection or reward receipt")
	var reread = Store.new(session.store.root_path)
	check(reread.load_profile().ok and _same(reread.snapshot(),saved),"independent Store reads the exact committed early-knowledge envelope")
	# Settle naturally at the left stop; no gate/axis success assignment.
	await _steps(20)
	check(session._save_environment(),"normal environment save also includes the current distribution mechanism")
	_check_pose("manual saved")
	await _capture_pair("manual-history-closed-door")
	# This is explicitly a prior-other-branch personal receipt fixture. There is
	# no distribution objective defined, so never fabricate its Story result.
	var appended: Dictionary = session.store.commit({"id":"qa-other-branch-discovery","append":{"personal.discoveries":[Progress.DISCOVERY]}})
	check(appended.ok,"explicit independent personal discovery fixture records branch-persistent knowledge")
	session.world_cache = session.store.snapshot()
	session.consensus.set_world_revision(int(session.world_cache.world_revision))

func _electric_branch_and_leave() -> void:
	phase = "branch_before_observation"
	await _switch("closed-before-observation")
	if not _healthy(): return
	check(not session.distribution.progress.snapshot().back_observed and session.distribution.module.snapshot().door_fraction==0.0 and session.distribution.module.snapshot().axis.position_m==0.0,"earlier branch restores its own unobserved closed cabinet")
	check(session.store.snapshot().personal.discoveries.count(Progress.DISCOVERY)==1,"other-branch personal discovery does not invalidate or complete this world branch")
	_unchanged_story("earlier branch")
	_check_pose("earlier branch first frame")
	# Actual gravity operation starts independent clinic flow, still without G
	# diagnosis; later background change must be real water transfer.
	await _place(Vector3(-10,7,-2.5))
	if not await _ability("push_pull",Works.GRAVITY_ID): return
	for unused in range(60):
		if int(session.clinic.module.status().clinic_volume_ml)>0: break
		await _steps(1)
	check(int(session.clinic.module.status().clinic_volume_ml)>0,"real clinic gravity route can run beside the independent cabinet")
	await _place(Vector3(17.8,2.7,-7.85))
	check(_body_clear(),"electric control approach is clear in the actual integrated I2 space")
	if not await _ability("charge",Cabinet.RELAY_ID): return
	await _steps(3)
	check(session.distribution.module.snapshot().door_fraction==0.0,"real relay charge alone does not fabricate door control")
	if not await _ability("takeover",Cabinet.LOCK_ID): return
	await _steps(5)
	var partial: Dictionary = session.distribution.module.snapshot()
	check(float(partial.door_fraction)>0.0 and float(partial.door_fraction)<1.0 and not partial.electric_latched,"authorized charge plus takeover creates a genuine unfinished door stroke",partial)
	await _travel("I1")
	if not _healthy(): return
	var parked: Dictionary = session.distribution.persistent_state()
	var stored: Dictionary = session.store.snapshot().world.environment.I2_distribution
	check(_same(parked,stored) and float(parked.mechanism.door_fraction)==float(partial.door_fraction),"leaving I2 atomically preserves the exact partial door and history")
	check(not is_instance_valid(session.distribution.module),"unvisited cabinet has no background physical module")
	var water_before: int = int(session.clinic.module.status().clinic_volume_ml)
	await _steps(30)
	check(_same(session.distribution.persistent_state(),parked),"three simulated seconds outside I2 do not advance cabinet door, axis or history")
	check(int(session.clinic.module.status().clinic_volume_ml)>water_before,"existing clinic background supply continues independently while cabinet is stopped")
	await _travel("I2")
	if not _healthy(): return
	check(float(session.distribution.module.snapshot().door_fraction)==float(partial.door_fraction) and not session.distribution.progress.snapshot().back_observed,"first returning frame restores the partial door without phantom observation")
	check(float(session.distribution.module.snapshot().axis.velocity_mps)==0.0 and not session.entities[Cabinet.LOCK_ID].controlled and session.entities[Cabinet.LOCK_ID].owner=="","return clears transient takeover and follows host-restored zero axis velocity")
	var restored: Dictionary = session.distribution.module.snapshot()
	await _steps(4)
	check(session.distribution.module.snapshot().door_fraction==restored.door_fraction,"unowned partial door cannot resume just because saved relay remains powered")
	await _place(Vector3(17.8,2.7,-7.85))
	if not await _ability("takeover",Cabinet.LOCK_ID): return
	for unused in range(30):
		if session.distribution.module.snapshot().electric_latched: break
		await _steps(1)
	check(session.distribution.module.snapshot().electric_latched and session.distribution.module.snapshot().door_fraction==1.0,"actual renewed takeover completes and latches the electrical route")
	await _place(Vector3(18,2.3,-7.7))
	if not await _move(Vector3(18,2.3,-10.8),"real TR01 moves through the opened door into the cabinet"): return
	await _place(Vector3(18,2.7,-10.8))
	var proof: Dictionary = session.distribution.module.observe_back(1,session.players[1])
	check(proof.ok and proof.method=="service_lock","interior observation uses real plate first-hit rays",proof)
	_g()
	check(session.distribution.progress.snapshot().back_observed and session.distribution.progress.snapshot().method=="service_lock","real G commits the alternative method independently in the earlier branch")
	_unchanged_story("electric knowledge")
	check(session.store.snapshot().personal.discoveries.count(Progress.DISCOVERY)==1,"alternative route does not repeat the explicit personal receipt fixture")
	_check_pose("electric branch")
	await _capture_pair("electric-history-open-door")

func _return_main() -> void:
	phase = "main_history_and_reload"
	await _switch("main")
	if not _healthy(): return
	check(_same(session.distribution.progress.snapshot(),first_manual_history) and session.distribution.module.snapshot().door_fraction==0.0,"return to main restores original manual history and its independent closed door")
	check(session.store.snapshot().personal.discoveries.count(Progress.DISCOVERY)==1,"branch return preserves exactly one personal receipt")
	_check_pose("main return first frame")
	var history_before: Dictionary = session.distribution.progress.snapshot()
	var mechanism_before: Dictionary = session.distribution.module.snapshot()
	check(session._save_environment() and session._load_region("I2"),"real same-region reload restores both modules from persistent state")
	_freeze_bodies()
	check(_same(session.distribution.progress.snapshot(),history_before) and session.distribution.module.snapshot().door_fraction==mechanism_before.door_fraction and session.distribution.module.snapshot().axis.position_m==mechanism_before.axis.position_m and session.distribution.module.snapshot().axis.velocity_mps==0.0,"reload preserves knowledge/door/cover position with explicit host stop rule")
	_check_pose("main reload first frame")
	_unchanged_story("main reload")
	await _capture_pair("main-new-epoch")
	# Real host publication in this same epoch, after two production time steps.
	# Keep the original three branch samples/indexes unchanged.
	await _steps(2)
	if not _healthy(): return
	await _capture_pair("main-same-epoch-new-reference")
	if not _healthy(): return
	same_epoch_followup = samples.pop_back()
	var previous: Dictionary = samples[2]
	check(same_epoch_followup.clinic.epoch==previous.clinic.epoch and int(same_epoch_followup.clinic.serial)>int(previous.clinic.serial) and int(same_epoch_followup.packet.sequence)>int(previous.packet.sequence),"same-epoch regression uses a newer real host publication, not an invented hydraulic envelope")
	# A second genuine publication isolates the new third-stream gate without
	# weakening the existing cases where only clinic state is missing.
	await _steps(2)
	if not _healthy(): return
	await _capture_pair("main-same-epoch-trial-late-reference")
	if not _healthy(): return
	trial_only_followup=samples.pop_back()
	check(trial_only_followup.trial.epoch==same_epoch_followup.trial.epoch and int(trial_only_followup.trial.serial)>int(same_epoch_followup.trial.serial) and int(trial_only_followup.packet.sequence)>int(same_epoch_followup.packet.sequence),"third-stream late-reference fixture is a newer actual host publication in the same epoch")
	await _steps(2)
	if not _healthy(): return
	await _capture_pair("main-same-epoch-bridge-late-reference")
	if not _healthy(): return
	bridge_only_followup=samples.pop_back()
	check(bridge_only_followup.shared_access.epoch==trial_only_followup.shared_access.epoch and int(bridge_only_followup.shared_access.serial)>int(trial_only_followup.shared_access.serial) and int(bridge_only_followup.packet.sequence)>int(trial_only_followup.packet.sequence),"fourth-stream late-reference fixture is another actual host publication")

func _capture_pair(label: String) -> void:
	if not session.players.has(2):
		# Real second body, but no network join. The consensus fixture stays solo.
		session._spawn_player(2,"qa-distribution-second-body",Vector3(24,12,22),"hx02")
		_freeze_bodies()
	session._action_received(1,"propose",{"kind":"pause","payload":{}})
	check(session.simulation_paused,"production pause precedes captured pair "+label)
	if not _healthy(): return
	session.clinic.publish()
	session.distribution.publish()
	session.trial.publish()
	session.shared_access.publish()
	var clinic_event := {"kind":"clinic_state","session_id":session.network.session_id,"region":session.region_id,"epoch":session.clinic.epoch,"serial":session.clinic.serial,"state":session.clinic.persistent_state()}
	var distribution_event := {"kind":"distribution_state","session_id":session.network.session_id,"region":session.region_id,"epoch":session.distribution.epoch,"serial":session.distribution.serial,"state":session.distribution.persistent_state()}
	var trial_event := {"kind":"trial_state","session_id":session.network.session_id,"region":session.region_id,"epoch":session.trial.epoch,"serial":session.trial.serial,"state":session.trial.persistent_state()}
	var bridge_event := {"kind":"shared_access_state","session_id":session.network.session_id,"region":session.region_id,"epoch":session.shared_access.epoch,"serial":session.shared_access.serial,"state":session.shared_access.persistent_state()}
	# Nonzero velocity is a serialization stress fixture on paused actual bodies,
	# not a claim that this captured pose is a naturally flown route.
	session.players[1].linear_velocity = Vector3(0.37,-0.21,0.83)
	session.players[2].linear_velocity = Vector3(-0.49,0.12,-0.31)
	var packet: Dictionary = session._snapshot()
	var references_match: bool=Contract.valid_refs(packet.get("facility_refs"))
	for pair in [[1,clinic_event],[2,distribution_event],[3,trial_event],[4,bridge_event]]:
		var reference: Dictionary=Contract.ref_for_slot(packet.get("facility_refs"),int(pair[0]))
		var event: Dictionary=pair[1]
		references_match=references_match and not event.state.is_empty() and event.session_id==packet.session_id and reference.get("epoch")==event.epoch and reference.get("serial")==event.serial
	check(session._facilities_ready() and references_match,"all four envelopes use actual published host identity/epoch/serial and match motion references",{"label":label,"facility_refs":packet.get("facility_refs")})
	var encoded: Dictionary = Codec.encode(packet)
	check(not encoded.is_empty(),"production codec recognizes all four independent module references",{"label":label})
	if not _healthy(): return
	var raw: PackedByteArray = var_to_bytes(encoded)
	var packed: PackedByteArray = raw.compress(FileAccess.COMPRESSION_ZSTD)
	var decoded: Dictionary = Codec.decode(bytes_to_var(packed.decompress(raw.size(),FileAccess.COMPRESSION_ZSTD)))
	check(decoded==packet,"two real-body four-module motion packet roundtrips without loss",{"label":label,"zstd_bytes":packed.size()})
	check(packed.size()<=1150,"four-module motion fixture stays within 1150B",{"label":label,"zstd_bytes":packed.size(),"clinic_reliable_bytes":var_to_bytes(clinic_event).size(),"distribution_reliable_bytes":var_to_bytes(distribution_event).size(),"trial_reliable_bytes":var_to_bytes(trial_event).size(),"bridge_reliable_bytes":var_to_bytes(bridge_event).size()})
	samples.append({"label":label,"packet":packet.duplicate(true),"clinic":clinic_event.duplicate(true),"distribution":distribution_event.duplicate(true),"trial":trial_event.duplicate(true),"shared_access":bridge_event.duplicate(true)})
	session._action_received(1,"propose",{"kind":"pause","payload":{}})
	_freeze_bodies()

func _guest_ordering() -> void:
	phase = "four_reliable_first_frame"
	check(samples.size()==3,"three actual host states exist for ordering checks")
	if not _healthy(): return
	check(session._save_environment(),"save protected host before replacing test presentation peer")
	var protected_host: Dictionary = session.store.snapshot()
	var host_path: String = session.store.root_path
	var guest_store = Store.new(base.path_join("guest"))
	check(guest_store.load_profile().ok and guest_store.commit({"id":"qa-distribution-guest"}).ok,"fresh independent guest Store owns only its own profile")
	var guest_before: Dictionary = guest_store.snapshot()
	session.active = false
	session.network.close()
	session.free()
	session = MAIN.instantiate()
	if not _main_usable():
		check(false,"guest MAIN must keep a usable Session script")
		return
	root.add_child(session)
	if not _disable_callbacks(): return
	session.store = guest_store
	session.world_cache = guest_before.duplicate(true)
	session.profile_ready = true
	session.network.mode = "guest" # Offline peer retained: no RPC/socket exercise.
	session.active = true
	session.owns_world = false
	session.story.reset_connection()
	session.clinic.reset_connection()
	session.distribution.reset_connection()
	session.trial.reset_connection()
	session.shared_access.reset_connection()
	session.received_session = ""
	session.received_sequence = -1
	var first: Dictionary = samples[0]
	session._queue_snapshot(first.packet)
	session._process(0.0)
	check(not session.clinic.ready and not session.distribution.ready and not session.trial.ready and not session.shared_access.ready and session.received_sequence==-1,"motion-first I2 waits for all four independent reliable states")
	session._network_event(first.shared_access)
	session._process(0.0)
	session._network_event(first.clinic)
	session._process(0.0)
	check(session.clinic.ready and not session.distribution.ready and session.received_sequence==-1 and not session.pending_packet.is_empty(),"valid water state alone cannot release missing cabinet first-frame collision")
	var bad: Dictionary = first.distribution.duplicate(true)
	bad.state.history.method = "forged_client_method"
	session._network_event(bad)
	session._process(0.0)
	check(not session.distribution.ready and session.received_sequence==-1,"invalid cabinet history cannot consume the pending motion sequence")
	session._network_event(first.distribution)
	session._process(0.0)
	check(session.clinic.ready and session.distribution.ready and session.shared_access.ready and not session.trial.ready and not session._facilities_ready() and session.received_sequence==-1 and not session.pending_packet.is_empty(),"valid clinic and late cabinet states cannot release first motion while real trial state is missing")
	session._network_event(first.trial)
	session._process(0.0)
	check(session.clinic.ready and session.distribution.ready and session.trial.ready and session.shared_access.ready and session.received_sequence==first.packet.sequence and session.simulation_paused,"matching late trial state releases the same paused first motion packet")
	if not _healthy(): return
	_check_four_modules(first,"guest paused first frame")
	_freeze_bodies()
	_check_pose("guest paused first frame")
	var frozen_cabinet: Dictionary = session.distribution.module.snapshot()
	var frozen_water: Dictionary = session.clinic.module.snapshot()
	var frozen_trial: Dictionary = session.trial.module.snapshot()
	var frozen_bridge: Dictionary = session.shared_access.module.snapshot()
	for unused in range(3):
		await physics_frame
		session.world.synchronize(session.entities,DT)
		session.distribution.advance(DT)
		session.clinic.advance(DT)
		session.trial.advance(DT)
		session.shared_access.advance(DT)
	check(session.distribution.module.snapshot()==frozen_cabinet and session.clinic.module.snapshot()==frozen_water and session.trial.module.snapshot()==frozen_trial and session.shared_access.module.snapshot()==frozen_bridge,"guest callbacks never integrate any of the four authoritative mechanisms")
	var early: Dictionary = samples[1]
	session._network_event(early.distribution)
	session._network_event(early.clinic)
	session._network_event(early.trial)
	session._network_event(early.shared_access)
	check(session.distribution.module.snapshot()==frozen_cabinet and session.clinic.module.snapshot()==frozen_water and session.trial.module.snapshot()==frozen_trial and session.shared_access.module.snapshot()==frozen_bridge,"future reliable epochs cannot replace current mechanisms before motion references them")
	session._queue_snapshot(early.packet)
	session._process(0.0)
	check(session.received_sequence==early.packet.sequence and session.distribution.ready and session.clinic.ready and session.trial.ready and session.shared_access.ready and _same(session.distribution.module.snapshot(),early.distribution.state.mechanism),"four reliable-first states reconstruct the alternate branch together")
	_check_four_modules(early,"guest reliable-first branch")
	_check_pose("guest electric branch")
	var newest: Dictionary = samples[2]
	session._queue_snapshot(newest.packet)
	session._process(0.0)
	check(not session.distribution.ready and not session.clinic.ready and not session.trial.ready and not session.shared_access.ready and session.received_sequence==early.packet.sequence and session.players[1].freeze,"same-region new epoch freezes the existing pilot until all four modules restore")
	# Keep the old water-only gate isolated: trial is already genuinely ready.
	session._network_event(newest.trial)
	session._network_event(newest.shared_access)
	session._process(0.0)
	check(session.trial.ready and not session.clinic.ready and not session.distribution.ready and session.received_sequence==early.packet.sequence,"trial-first arrival cannot bypass either old reliable stream")
	session._network_event(newest.distribution)
	session._process(0.0)
	check(session.distribution.ready and not session.clinic.ready and session.received_sequence==early.packet.sequence and session.players[1].freeze,"cabinet-first arrival cannot release missing water state")
	await _waiting_inputs_blocked()
	if not _healthy(): return
	session._network_event(newest.clinic)
	session._process(0.0)
	check(session.received_sequence==newest.packet.sequence and session.distribution.ready and session.clinic.ready and session.trial.ready and session.shared_access.ready,"matching water arrival completes the four-module barrier")
	_check_four_modules(newest,"guest restored main")
	_check_pose("guest restored main")
	var last_cabinet: Dictionary = session.distribution.module.snapshot()
	var last_water: Dictionary = session.clinic.module.snapshot()
	var last_trial: Dictionary = session.trial.module.snapshot()
	var last_bridge: Dictionary = session.shared_access.module.snapshot()
	session._network_event(first.distribution)
	session._network_event(first.clinic)
	session._network_event(first.trial)
	session._network_event(first.shared_access)
	session._queue_snapshot(first.packet)
	session._process(0.0)
	check(session.received_sequence==newest.packet.sequence and session.distribution.module.snapshot()==last_cabinet and session.clinic.module.snapshot()==last_water and session.trial.module.snapshot()==last_trial and session.shared_access.module.snapshot()==last_bridge,"old motion and old independent epochs cannot roll any module back")
	var foreign: Dictionary = newest.distribution.duplicate(true)
	foreign.session_id = "not-this-host-session"
	foreign.serial = int(foreign.serial)+100
	session._network_event(foreign)
	check(session.distribution.module.snapshot()==last_cabinet,"foreign session cannot change cabinet collision")
	var swapped: Dictionary = newest.distribution.duplicate(true)
	swapped.kind = "clinic_state"
	swapped.epoch = newest.clinic.epoch
	swapped.serial = int(newest.clinic.serial)+1
	session._network_event(swapped)
	check(session.clinic.module.snapshot()==last_water and session.distribution.module.snapshot()==last_cabinet,"wrong module kind cannot adopt the other module's envelope")
	await _clinic_reference_regressions(newest)
	if not _healthy(): return
	await _trial_reference_regression(same_epoch_followup)
	if not _healthy(): return
	await _bridge_reference_regression(trial_only_followup)
	if not _healthy(): return
	check(guest_store.snapshot()==guest_before,"guest state reconstruction never writes remote world into its personal Store")
	var host_reread = Store.new(host_path)
	check(host_reread.load_profile().ok and _same(host_reread.snapshot(),protected_host),"guest lifecycle leaves protected host disk byte-value state unchanged")

func _waiting_inputs_blocked(missing: String="clinic") -> void:
	var peer: int = session.network.local_id()
	var exactly_one_missing: bool=session.distribution.ready and ((missing=="clinic" and not session.clinic.ready and session.trial.ready and session.shared_access.ready) or (missing=="trial" and session.clinic.ready and not session.trial.ready and session.shared_access.ready) or (missing=="shared_access" and session.clinic.ready and session.trial.ready and not session.shared_access.ready))
	check(session.players.has(peer) and exactly_one_missing and not session._facilities_ready(),"input-gate probe has an existing local pilot and exactly one missing facility: "+missing)
	if not _healthy(): return
	# Explicit input-routing placement at an already tested high-well pose. It
	# ensures G has a real nearby marker and Tab has actual nearby entities;
	# absence of an eligible target must not make this negative check pass.
	var before_position: Vector3 = session.players[peer].global_position
	await _place(Vector3(18,5.75,-10.6),peer)
	check(session.story.nearest(session.players[peer].global_position)==Progress.FACT_TARGET and session.entities.has(Cabinet.COVER_ID),"blocked-input fixture still has a genuine nearby investigation and ability target")
	var sequence_before: int = session.network._sequence
	var locks_before: Dictionary = session.locks.duplicate(true)
	session.interface.menu.hide()
	session.interface.clear_dialogue()
	session._send_ability(false)
	check(session.network._sequence==sequence_before and session.locks==locks_before,"direct ability request cannot transmit while one facility is missing")
	session._cycle_target()
	check(session.network._sequence==sequence_before and session.locks==locks_before,"target cycling cannot transmit or change locks while one facility is missing")
	session.story.request_nearby()
	check(session.network._sequence==sequence_before and session.locks==locks_before,"nearby story request cannot transmit while one facility is missing")
	for key in [KEY_G,KEY_F]:
		var event := InputEventKey.new()
		event.pressed = true
		event.keycode = key
		event.physical_keycode = key
		session._unhandled_input(event)
		check(session.network._sequence==sequence_before and session.locks==locks_before,"real "+OS.get_keycode_string(key)+" key cannot transmit or change locks while waiting for "+missing+" state")
	await _place(before_position,peer)
	check(session.players[peer].freeze and session.distribution.ready and not session.get(missing).ready and not session._facilities_ready(),"blocked gameplay inputs do not release the frozen pilot or the "+missing+" barrier")

func _clinic_reference_regressions(previous: Dictionary) -> void:
	phase = "clinic_same_epoch_reference_gate"
	check(not same_epoch_followup.is_empty(),"same-epoch hydraulic publication was captured from the actual host")
	if not _healthy(): return
	var before_water: Dictionary = session.clinic.module.snapshot()
	var next: Dictionary = same_epoch_followup
	session._queue_snapshot(next.packet)
	session._process(0.0)
	check(not session.clinic.ready and session.received_sequence==previous.packet.sequence and session.players[1].freeze and not session.pending_packet.is_empty(),"new serial in the same clinic epoch closes old readiness before accepting motion")
	check(session.clinic.module.snapshot()==before_water,"waiting for a same-epoch hydraulic reference leaves the last validated collision intact")
	session._network_event(next.trial)
	session._network_event(next.shared_access)
	session._process(0.0)
	check(session.trial.ready and not session.clinic.ready and session.received_sequence==previous.packet.sequence,"genuine trial state cannot bypass the same-epoch hydraulic reference")
	session._network_event(next.distribution)
	session._process(0.0)
	check(session.distribution.ready and session.trial.ready and not session.clinic.ready and session.received_sequence==previous.packet.sequence and session.players[1].freeze,"ready cabinet and trial cannot bypass missing same-epoch hydraulic state")
	session._network_event(next.clinic)
	session._process(0.0)
	check(session.clinic.ready and session.distribution.ready and session.trial.ready and session.shared_access.ready and session.received_sequence==next.packet.sequence and _same(session.clinic.module.snapshot(),next.clinic.state.mechanism),"matching same-epoch reliable state releases only its pending motion and exact water state")
	_check_four_modules(next,"same epoch matched reference")
	_check_pose("same epoch matched reference")
	if not _healthy(): return
	# Explicit reliable-transport order fixtures. Only the foreign identity and
	# counter are altered; every accepted envelope is a real host capture.
	for genuine_before_motion in [true,false]:
		phase = "clinic_prebind_foreign_counter_"+("early" if genuine_before_motion else "late")
		session._network_event({"kind":"host_left"})
		await process_frame
		session.story.reset_connection()
		session.network.mode = "guest"
		session.active = true
		session.owns_world = false
		check(session.received_session.is_empty() and session.received_sequence==-1 and not session.clinic.ready and not is_instance_valid(session.world),"real disconnect clears host binding and live hydraulic world before this fresh connection")
		var foreign_early: Dictionary = next.clinic.duplicate(true)
		foreign_early.session_id = "qa-unbound-other-host"
		foreign_early.serial = int(next.clinic.serial)+1000
		session._network_event(foreign_early)
		check(not session.clinic.pending.is_empty() and session.clinic.pending.session_id==foreign_early.session_id and session.received_session.is_empty() and not session.clinic.ready,"pre-motion foreign reliable packet is buffered without choosing the host or enabling input")
		if genuine_before_motion:
			session._network_event(next.clinic)
			check(session.clinic.pending.get("session_id")==next.clinic.session_id and session.clinic.pending.get("serial")==next.clinic.serial and session.received_session.is_empty(),"unbound foreign high serial cannot suppress a different host's genuine lower serial")
		session._network_event(next.distribution)
		session._network_event(next.trial)
		session._network_event(next.shared_access)
		session._queue_snapshot(next.packet)
		session._process(0.0)
		if not genuine_before_motion:
			check(session.received_session==next.packet.session_id and session.received_sequence==-1 and not session.clinic.ready and session.clinic.pending.is_empty() and not session.pending_packet.is_empty(),"motion binds the real host and removes only the foreign pending clinic packet without accepting motion")
			session._network_event(next.clinic)
			session._process(0.0)
		check(session.received_session==next.packet.session_id and session.received_sequence==next.packet.sequence and session.clinic.ready and session.distribution.ready and session.trial.ready and session.shared_access.ready and session.simulation_paused,"genuine lower-serial hydraulic packet completes the paused four-stream first-frame barrier in this arrival order")
		if not _healthy(): return
		check(_same(session.clinic.module.snapshot(),next.clinic.state.mechanism) and _same(session.distribution.module.snapshot(),next.distribution.state.mechanism),"new host binding restores both captured mechanisms without inheriting the foreign counter")
		_check_four_modules(next,"prebind recovery "+str(genuine_before_motion))
		_freeze_bodies()
		_check_pose("prebind recovery "+str(genuine_before_motion))

func _trial_reference_regression(previous: Dictionary) -> void:
	phase="trial_same_epoch_reference_gate"
	check(not trial_only_followup.is_empty(),"late trial reference uses a captured host publication")
	if not _healthy(): return
	var next: Dictionary=trial_only_followup
	var before_trial: Dictionary=session.trial.module.snapshot()
	session._queue_snapshot(next.packet)
	session._process(0.0)
	check(not session.trial.ready and session.received_sequence==previous.packet.sequence and session.players[1].freeze and not session.pending_packet.is_empty(),"new trial serial closes readiness without consuming its pending motion")
	session._network_event(next.clinic)
	session._network_event(next.distribution)
	session._network_event(next.shared_access)
	session._process(0.0)
	check(session.clinic.ready and session.distribution.ready and session.shared_access.ready and not session.trial.ready and not session._facilities_ready() and session.received_sequence==previous.packet.sequence and session.players[1].freeze,"both original streams ready cannot release an existing pilot while only trial state is missing")
	check(session.trial.module.snapshot()==before_trial,"missing trial reference preserves the last validated link, valve leaves and float collision")
	await _waiting_inputs_blocked("trial")
	if not _healthy(): return
	var foreign: Dictionary=next.trial.duplicate(true)
	foreign.session_id="qa-other-trial-host"
	session._network_event(foreign)
	session._process(0.0)
	check(not session.trial.ready and session.received_sequence==previous.packet.sequence and session.trial.module.snapshot()==before_trial,"foreign-host trial envelope cannot release the third-stream barrier")
	session._network_event(next.trial)
	session._network_event(next.shared_access)
	session._process(0.0)
	check(session.clinic.ready and session.distribution.ready and session.trial.ready and session._facilities_ready() and session.received_sequence==next.packet.sequence and session.simulation_paused,"matching real trial publication completes the same paused motion packet")
	if not _healthy(): return
	_check_four_modules(next,"late third stream restored")
	_check_pose("late third stream restored")
	var latest: Dictionary=session.trial.module.snapshot()
	session._network_event(previous.trial)
	session._process(0.0)
	check(session.trial.ready and session.received_sequence==next.packet.sequence and session.trial.module.snapshot()==latest,"older same-epoch trial state cannot undo accepted current collision")

func _bridge_reference_regression(previous: Dictionary) -> void:
	phase="bridge_same_epoch_reference_gate"
	check(not bridge_only_followup.is_empty(),"late bridge reference uses a captured real host publication")
	if not _healthy(): return
	var next: Dictionary=bridge_only_followup
	var before_bridge: Dictionary=session.shared_access.module.snapshot()
	session._queue_snapshot(next.packet)
	session._process(0.0)
	check(not session.shared_access.ready and session.received_sequence==previous.packet.sequence and session.players[1].freeze and not session.pending_packet.is_empty(),"new bridge serial closes readiness without consuming its pending motion")
	for event in [next.clinic,next.distribution,next.trial]: session._network_event(event)
	session._process(0.0)
	check(session.clinic.ready and session.distribution.ready and session.trial.ready and not session.shared_access.ready and not session._facilities_ready() and session.received_sequence==previous.packet.sequence and session.players[1].freeze,"three existing streams cannot release motion while only the bridge stream is missing")
	check(session.shared_access.module.snapshot()==before_bridge,"waiting for bridge preserves last validated deck and pin collision")
	await _waiting_inputs_blocked("shared_access")
	if not _healthy(): return
	var foreign: Dictionary=next.shared_access.duplicate(true)
	foreign.session_id="qa-other-bridge-host"
	session._network_event(foreign)
	session._process(0.0)
	check(not session.shared_access.ready and session.received_sequence==previous.packet.sequence and session.shared_access.module.snapshot()==before_bridge,"foreign bridge state cannot release the fourth barrier")
	session._network_event(next.shared_access)
	session._process(0.0)
	check(session._facilities_ready() and session.received_sequence==next.packet.sequence and session.simulation_paused,"matching real bridge state completes the paused four-facility frame")
	if not _healthy(): return
	_check_four_modules(next,"late fourth stream restored")
	_check_pose("late fourth stream restored")
	var latest: Dictionary=session.shared_access.module.snapshot()
	session._network_event(previous.shared_access)
	session._process(0.0)
	check(session.shared_access.ready and session.received_sequence==next.packet.sequence and session.shared_access.module.snapshot()==latest,"older same-epoch bridge cannot undo accepted deck and pin collision")

func _check_four_modules(sample: Dictionary, label: String) -> void:
	var available: bool=session.clinic.ready and session.distribution.ready and session.trial.ready and is_instance_valid(session.clinic.module) and is_instance_valid(session.distribution.module) and session.shared_access.ready and is_instance_valid(session.trial.module) and is_instance_valid(session.shared_access.module)
	check(available,label+": all four restored modules exist before physical inspection")
	if not available: return
	var clinic = session.clinic.module
	var cabinet = session.distribution.module
	var trial = session.trial.module
	var trial_expected: Dictionary={"link":sample.trial.state.link,"station":sample.trial.state.station}
	check(_same(clinic.snapshot(),sample.clinic.state.mechanism) and _same(cabinet.snapshot(),sample.distribution.state.mechanism) and _same(trial.snapshot(),trial_expected) and _same(session.shared_access.module.snapshot(),sample.shared_access.state.mechanism),label+": all four mechanisms equal their genuine host envelopes")
	var clinic_bodies: Array=clinic.moving_bodies.values()
	clinic_bodies.append_array([clinic.gravity_valve,clinic.pump_selector,clinic.interlock_bolt])
	var trial_bodies: Array=trial.link.moving_bodies.values()
	trial_bodies.append_array(trial.station.selector_bodies.values())
	trial_bodies.append_array(trial.station.valve_bodies.values())
	trial_bodies.append_array(trial.station.float_bodies.values())
	var groups: Dictionary={"clinic":clinic_bodies,"distribution":[cabinet.cover,cabinet.door],"trial":trial_bodies,"shared_access":session.shared_access.module.moving_bodies.values()+session.shared_access.module.pin_bodies.values()}
	for id in groups:
		var mismatches: Array=[]
		for body in groups[id]:
			var actual: Transform3D=PhysicsServer3D.body_get_state(body.get_rid(),PhysicsServer3D.BODY_STATE_TRANSFORM)
			if not actual.is_equal_approx(body.global_transform): mismatches.append(str(body.name))
		check(not groups[id].is_empty() and mismatches.is_empty(),label+": "+str(id)+" moving collision immediately matches the restored scene",{"body_count":groups[id].size(),"mismatches":mismatches})
	var connected: Dictionary=trial.connection_status()
	check(trial.link._poses_match() and trial.station._poses_match() and session.shared_access.module._poses_match() and connected.ok,label+": real same-world trial binding and every leaf/float pose match restored mechanisms",connected)

func _finish(code: int) -> void:
	if done: return
	done = true
	if is_instance_valid(session):
		if _has_property("active"): session.set("active",false)
		var transport: Node = session.get_node_or_null("Network")
		if is_instance_valid(transport) and transport.has_method("close"): transport.call("close")
		session.free()
	if code==0 and not error_logger.errors.is_empty(): code=1
	print("DISTRIBUTION_SESSION checks=%d failures=%d profile=%s" % [checks.size(),failures.size(),profile])
	print("DISTRIBUTION_SESSION_RESULT "+JSON.stringify({"passed":code==0,"profile":profile,"checks":checks,"failures":failures,"engine_errors":error_logger.errors,"limits":["Previous27 objectives are declared historical Director events, not a playthrough; the new distribution action is not completed by this fixture.","Pilot starting placements, the second real body, and nonzero paused snapshot velocities are explicit QA fixtures; actual door traversal uses move_and_collide.","One personal discovery is explicitly seeded as prior-other-branch history after verifying early observation awards nothing; this does not test actual distribution reward delivery.","All four reliable event streams and motion packets are real host captures injected into real guest consumers. No ENet, two PCs, reconnect transport or receipt ACK validation.","Production physics uses controlled bounded steps; no human duration, graphical or performance acceptance."]}))
	OS.remove_logger(error_logger)
	quit(code)
