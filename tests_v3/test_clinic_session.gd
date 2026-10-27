extends SceneTree
## Actual MAIN/Session/Store/PhysicsServer integration, without UDP or GPU.
## The previous27 objectives and starting positions are explicit QA fixtures.
## Water uses production fixed updates at0.1s per actual physics frame: this is
## accelerated simulated time, not a human playthrough or duration measurement.
const MAIN = preload("res://scenes/v3/main.tscn")
const Store = preload("res://scripts/v3/core/twin_world_store.gd")
const Director = preload("res://scripts/v3/gameplay/actions/twin_action_director.gd")
const ActionData = preload("res://tests_v3/test_clinic_action.gd") # Constants only; never instantiate its SceneTree.
const Contract = preload("res://scripts/v3/network/twin_facility_contract.gd")
const Codec = preload("res://scripts/v3/network/twin_snapshot_codec.gd")
const Works = preload("res://scripts/v3/world/twin_clinic_waterworks.gd")
const DT := 0.1
const DIAGNOSE := "I2:clinic_supply:diagnose"
const CONNECT := "I2:clinic_supply:connect"
const STABILIZE := "I2:clinic_supply:stabilize"
const CONFIRM := "I2:clinic_supply:confirm"
const FLAG := "I2:clinic_ready"
const DISCOVERY := "I2:clinic_priority_misroute"
const TARGET_ML := 2000000
var session
var guest_store
var profile := ""
var base := ""
var phase := "setup"
var checks: Array = []
var failures: Array = []
var samples: Array = []
var facility_fixture: Dictionary = {}
var main_ecology: Dictionary = {}
var gravity_mid: Dictionary = {}
var done := false

func _initialize() -> void: _run.call_deferred()

func check(ok: bool, label: String, detail: Dictionary = {}) -> void:
	checks.append({"phase":phase,"label":label,"passed":ok,"detail":detail})
	if not ok:
		failures.append(label)
		push_error("CLINIC_SESSION " + label + " " + JSON.stringify(detail))

func _run() -> void:
	var profiles := 0
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--qa-profile="):
			profile = arg.trim_prefix("--qa-profile=")
			profiles += 1
		if arg.begins_with("--qa-network") or arg.begins_with("--qa-capture"):
			push_error("Clinic session test refuses automatic network/capture drivers")
			quit(2)
			return
	if profiles != 1 or not profile.begins_with("qa_clinic_") or profile != profile.validate_filename():
		push_error("One fresh --qa-profile=qa_clinic_<unique> is required")
		quit(2)
		return
	base = "user://qa_v3_clinic/" + profile
	if DirAccess.dir_exists_absolute(base) or DirAccess.dir_exists_absolute("user://profiles_v3/" + profile):
		push_error("Refusing an existing QA profile")
		quit(2)
		return
	create_timer(180.0).timeout.connect(func():
		if not done:
			check(false,"bounded test timed out")
			_finish(2))
	session = MAIN.instantiate()
	root.add_child(session)
	_disable_callbacks()
	check(session.profile_ready and session.start_flight("solo"),"real MAIN opens new QA profile and starts solo")
	if not session.active or not _seed_previous_actions():
		_finish(1)
		return
	await _travel("I2")
	if session.region_id != "I2" or not session.clinic.ready:
		check(false,"I2 production module must be integrated and ready")
		_finish(1)
		return
	check(session.world.clinic == session.clinic.module and session.clinic.background == null,"visited clinic uses the visible world's actual module")
	check(_volume() == 0 and not _completed(DIAGNOSE),"old27-goal save initializes empty clinic without completing eighth action")
	check(_same(_hydraulic(session.store.snapshot().world.environment.I2_water),_hydraulic(session.clinic.persistent_state())),"first I2 entry persists initial water/history before play")
	_check_poses("initial I2")
	_fork("before-water")
	await _gravity_before_diagnosis()
	if failures.is_empty(): await _diagnosis_and_confirmation("gravity",true)
	if failures.is_empty(): await _pump_branch()
	if failures.is_empty(): await _branch_restoration()
	if failures.is_empty(): await _guest_ordering()
	_finish(0 if failures.is_empty() else 1)

func _disable_callbacks() -> void:
	# Disabling process_mode would remove Jolt bodies from their space. Keep all
	# nodes in the real world, manually invoke Session's production callback.
	session.set_process(false)
	session.set_physics_process(false)
	if is_instance_valid(session.inputs):
		session.inputs.set_process(false)
		session.inputs.set_physics_process(false)
	_freeze_bodies()

func _freeze_bodies() -> void:
	for body in session.players.values():
		body.freeze = true
		body.set_process(false)
		body.set_physics_process(false)
		body.linear_velocity = Vector3.ZERO
		body.angular_velocity = Vector3.ZERO

func _seed_previous_actions() -> bool:
	var legacy = Director.new()
	var loaded: Dictionary = legacy.load_definitions(Director.DEFAULT_PATH,ActionData.OLD_EXTENSIONS)
	check(loaded.ok,"seven-action historical fixture loads existing production definitions")
	if not loaded.ok: return false
	var state: Dictionary = legacy.default_state()
	for row in ActionData.OLD_EVENTS:
		var event := {"id":"qa-clinic-history:"+str(row[0]),"type":row[1],"target_id":row[2],"option":row[3]}
		var result: Dictionary = legacy.apply_event(state,event,{"is_authority":true,"validated":true,"region_id":str(row[0]).get_slice(":",0)})
		if not result.get("changed",false):
			check(false,"historical event fixture rejected",{"goal":row[0],"code":result.get("code")})
			return false
		state = result.state
	check(state.completed.size()==27 and state.completed_actions.size()==7 and session.story.director.validate_state(state).ok,"fixed old27 objectives validate unchanged in current nine-action Director")
	var eco: Dictionary = session.ecology.persistent_state()
	eco.facilities = {"coolant":2,"maintenance":{"I1:thermal":1,"I1:relay":2},"deliveries":7}
	facility_fixture = eco.facilities.duplicate(true)
	var saved: Dictionary = session.store.commit({"id":"qa-clinic-old27","set":{"world.actions.opening":state,"world.flags":state.flags,"world.completed_objectives":state.completed,"world.ecology":eco},"append":{"personal.discoveries":state.discoveries}})
	check(saved.ok,"old goals and nonzero ecology inventory commit as one explicit fixture")
	if not saved.ok: return false
	session.world_cache = session.store.snapshot()
	check(session.ecology.restore_world(session.world_cache.world) and session._load_region("I1"),"real reload restores predecessor branch")
	session.consensus.configure([1],int(session.world_cache.world_revision))
	_freeze_bodies()
	return true

func _steps(count: int, delta: float = DT) -> void:
	for unused in range(count):
		await physics_frame
		session._physics_process(delta)
		if not session.clinic.error.is_empty():
			check(false,"production clinic advance rejected",{"error":session.clinic.error})
			return

func _place(at: Vector3, peer: int = 1) -> void:
	# Starting-position fixture only. Route passage below uses move_and_collide.
	var body = session.players[peer]
	body.global_transform = Transform3D(Basis.IDENTITY,at)
	body.linear_velocity = Vector3.ZERO
	PhysicsServer3D.body_set_state(body.get_rid(),PhysicsServer3D.BODY_STATE_TRANSFORM,body.global_transform)
	session.entities[session._actor_id(peer)].position = at
	await physics_frame
	await physics_frame

func _move(to: Vector3, label: String) -> bool:
	var body = session.players[1]
	var collision: KinematicCollision3D
	var count := 0
	while body.global_position.distance_to(to)>0.002 and count<160:
		var motion: Vector3 = (to-body.global_position).limit_length(0.2)
		collision = body.move_and_collide(motion)
		await _steps(1,1.0/60.0)
		count += 1
		if collision != null: break
	var ok: bool = collision==null and body.global_position.distance_to(to)<0.005
	check(ok,label,{"position":str(body.global_position),"target":str(to),"collider":str(collision.get_collider().get_path()) if collision!=null else ""})
	return ok

func _ability(ability: String, target: String) -> bool:
	while float(session.cooldowns.get(1,0.0))>0.0: await _steps(1)
	var count: int = int(session.stats.abilities)
	session._action_received(1,"ability",{"ability":ability,"target_id":target})
	var accepted: bool = int(session.stats.abilities)==count+1
	check(accepted,"real Session accepts "+ability+" on "+target,{"notice":session.interface.message.text})
	return accepted

func _g() -> void:
	session.interface.clear_dialogue()
	session.interface.menu.hide()
	var key := InputEventKey.new()
	key.pressed = true
	key.keycode = KEY_G
	key.physical_keycode = KEY_G
	session._unhandled_input(key)

func _volume() -> int: return int(session.clinic.module.status().clinic_volume_ml)
func _completed(id: String) -> bool: return id in session.story.state.get("completed",[])
func _same(a: Variant,b: Variant) -> bool: return JSON.parse_string(JSON.stringify(a))==JSON.parse_string(JSON.stringify(b))

func _hydraulic(envelope: Dictionary) -> Dictionary:
	# Actor revisions are intentionally recreated across region/branch/revive.
	# Compare every hydraulic/history field while excluding only that input ledger.
	var state: Dictionary = envelope.duplicate(true)
	state.mechanism.axis.erase("last_serial")
	return state

func _fork(id: String) -> void:
	check(session._save_environment(),"save current environment before QA branch "+id)
	check(session.store.fork_branch(id,"QA "+id,false).ok,"fork independent branch "+id)
	session.world_cache = session.store.snapshot()
	session.consensus.set_world_revision(int(session.world_cache.world_revision))

func _travel(destination: String) -> void:
	session._ui_action("travel_to",{"region_id":destination})
	check(session.region_id==destination and session.consensus.current_proposal().is_empty(),"production one-player travel commits and adopts "+destination,{"region":session.region_id,"notice":session.interface.message.text})
	_freeze_bodies()
	await physics_frame

func _switch(id: String) -> void:
	session._ui_action("branch",{"id":id})
	check(session.store.snapshot().world.branch_id==id and session.active,"production branch switch adopts "+id,{"notice":session.interface.message.text})
	_freeze_bodies()
	await physics_frame

func _check_poses(label: String) -> void:
	var module = session.clinic.module
	var correct := true
	var bodies: Array = module.moving_bodies.values()
	bodies.append(module.gravity_valve)
	bodies.append(module.pump_selector)
	for body in bodies:
		var actual: Transform3D = PhysicsServer3D.body_get_state(body.get_rid(),PhysicsServer3D.BODY_STATE_TRANSFORM)
		correct = correct and actual.is_equal_approx(body.global_transform)
	check(correct,label+": all moving parts and control bodies publish real PhysicsServer transforms")
	var top: float = float(module.status().deck_top_y)
	var ray := PhysicsRayQueryParameters3D.create(Vector3(0,top+0.5,-4),Vector3(0,top-0.5,-4),1|8)
	var hit: Dictionary = module.get_world_3d().direct_space_state.intersect_ray(ray)
	check(not hit.is_empty() and hit.collider==module.deck and absf(float(hit.position.y)-top)<0.002,label+": actual ray hits deck at restored water-driven height",{"reported_top":top,"hit":str(hit.get("position"))})

func _gravity_before_diagnosis() -> void:
	phase = "gravity_before_diagnosis"
	await _place(Vector3(-10,7,-2.5))
	var before: Dictionary = session.store.snapshot()
	session._action_received(1,"explore",{"target_id":"I2:clinic_feed","type":"fact","option":"gravity","validated":true})
	check(session.store.snapshot()==before and not _completed(CONNECT),"client-authored feed fact cannot bypass actual water or diagnosis")
	if not await _ability("push_pull",Works.GRAVITY_ID): return
	for unused in range(60):
		if _volume()>0: break
		await _steps(1)
	check(_volume()>0 and float(session.clinic.module.status().gravity_fraction)>=0.995,"real impulse moves valve on its axis and transfers positive clean water",session.clinic.module.status())
	check(session.clinic.progress.snapshot().route_method=="gravity" and not _completed(DIAGNOSE) and not _completed(CONNECT),"early gravity transfer is retained as history without auto-diagnosing")
	await _place(Vector3(23,13,23))
	_fork("gravity-mid")
	gravity_mid = session.store.snapshot().branches["gravity-mid"].world.environment.I2_water.duplicate(true)
	await _steps(7)
	var current: Dictionary = session.clinic.persistent_state()
	var disk: Dictionary = session.store.snapshot()
	session._ui_action("branch",{"id":str(disk.world.branch_id)})
	check(session.clinic.persistent_state()==current and session.store.snapshot()==disk,"selecting active branch is a no-op and cannot restore stale water")
	var module_before = session.clinic.module
	var world_before = session.world
	session.store.failure_point = "before_publish"
	session._ui_action("travel_to",{"region_id":"I1"})
	check(session.region_id=="I2" and session.world==world_before and session.clinic.module==module_before and session.store.snapshot()==disk,"failed travel save leaves current world/module/disk unchanged")
	session.store.failure_point = ""
	await _travel("I1")
	var volume_before := _volume()
	check(is_instance_valid(session.clinic.background) and session.clinic.module.get_world_3d()!=session.world.get_world_3d(),"unvisited clinic is hosted in a separate real physics world")
	await _steps(25)
	check(_volume()>volume_before and session.clinic.progress.snapshot().route_method=="gravity","online background clinic continues existing gravity flow without changing its route")
	var background_volume := _volume()
	await _travel("I2")
	check(_volume()==background_volume and session.clinic.background==null,"returning adopts current background water without resetting or double-advancing")
	_check_poses("first return frame")
	var restored: Dictionary = session.clinic.persistent_state()
	session._restore_player(1,session.world.spawn_position)
	_freeze_bodies()
	check(_same(_hydraulic(session.clinic.persistent_state()),_hydraulic(restored)) and session.clinic.module.snapshot().axis.last_serial.get("1")==-1,"real player restore resets pilot input ledger and preserves water/history")
	check(_same(session.ecology.persistent_state().facilities,facility_fixture),"cross-region water persistence preserves previous ecology inventory")

func _diagnosis_and_confirmation(route: String, failure_cases: bool) -> void:
	phase = route+"_manual_diagnosis"
	await _place(Vector3(7,5.8,-1))
	if failure_cases:
		var disk: Dictionary = session.store.snapshot()
		session.store.failure_point = "before_publish"
		_g()
		check(not _completed(DIAGNOSE) and session.store.snapshot()==disk,"failed nearby G diagnosis does not publish objective or mutate durable save")
		session.store.failure_point = ""
	_g()
	check(_completed(DIAGNOSE),"actual nearby G with LOS commits diagnosis")
	await _steps(4)
	check(_completed(CONNECT) and session.story.state.choices.get(CONNECT)==route,"production observer recognizes the earlier "+route+" transfer after diagnosis")
	phase = route+"_water_stability"
	for unused in range(850):
		if _volume()==TARGET_ML or not session.clinic.error.is_empty(): break
		await _steps(1)
	check(_volume()==TARGET_ML,"actual conserved water reaches two-million-ml cutoff",session.clinic.module.status())
	if _volume()!=TARGET_ML: return
	if failure_cases:
		await _place(Vector3(0,5.8,-4))
		await _steps(24)
		check(not session.clinic.access_clear() and int(session.clinic.progress.snapshot().stable_usec)==0 and not _completed(STABILIZE),"real pilot blocking three-metre access prevents stability objective")
		await _place(Vector3(-4.5,5.8,-4))
		if not await _move(Vector3(4.5,5.8,-4),"actual TR01 crosses raised deck between both landings"): return
	await _place(Vector3(7,5.8,-1))
	await _steps(25)
	check(session.clinic.access_clear() and _completed(STABILIZE) and not _completed(CONFIRM),"clear actual deck remains stable for two seconds; confirmation remains manual")
	_check_poses("stable full clinic")
	phase = route+"_atomic_confirmation"
	if failure_cases:
		var disk: Dictionary = session.store.snapshot()
		var story_before: Dictionary = session.story.state.duplicate(true)
		var history_before: Dictionary = session.clinic.progress.snapshot()
		session.store.failure_point = "before_publish"
		_g()
		check(session.store.snapshot()==disk and session.story.state==story_before and session.clinic.progress.snapshot()==history_before,"confirmation disk failure leaves action, flag, discovery and commissioned history uncommitted")
		check(not session.world_cache.world.flags.get(FLAG,false) and not _completed(CONFIRM),"failed confirmation cannot announce clinic commissioned")
		session.store.failure_point = ""
	_g()
	var saved: Dictionary = session.store.snapshot()
	check(_completed(CONFIRM) and saved.world.flags.get(FLAG,false) and saved.world.environment.I2_water.history.commissioned and session.clinic.progress.snapshot().commissioned,"actual G commits final objective, flag and hydraulic history together")
	check(saved.personal.discoveries.count(DISCOVERY)==1 and saved.world.actions.opening.characters["npc:ruanheng"].memories.has("I2:clinic_restored_patient_access"),"final inspection records one discovery and Ruanheng's actual memory")
	_g()
	check(session.store.snapshot()==saved,"repeated G cannot issue another reward or another confirmation transaction")
	var reread = Store.new(session.store.root_path)
	check(reread.load_profile().ok and _same(reread.snapshot(),saved),"separate real Store rereads committed clinic state")
	if not session.players.has(2):
		# Roster-only physical fixture, not a network join or transport test.
		session._spawn_player(2,"qa-clinic-physical-peer",Vector3(23,13,22),"hx02")
		_freeze_bodies()
	_capture_pair(route+"-full")

func _capture_pair(label: String) -> void:
	# Production pause consensus; the extra body is not a voting peer in this
	# roster-only fixture. Snapshot serialization nevertheless contains both.
	session._action_received(1,"propose",{"kind":"pause","payload":{}})
	check(session.simulation_paused,"production pause applied before "+label+" snapshot")
	session.clinic.publish()
	var event := {"kind":"clinic_state","session_id":session.network.session_id,"region":session.region_id,"epoch":session.clinic.epoch,"serial":session.clinic.serial,"state":session.clinic.persistent_state()}
	# Each independent reliable stream must be published before capturing motion.
	# These are real production envelopes, not empty substitutes for readiness.
	session.distribution.publish()
	var distribution_event := {"kind":"distribution_state","session_id":session.network.session_id,"region":session.region_id,"epoch":session.distribution.epoch,"serial":session.distribution.serial,"state":session.distribution.persistent_state()}
	session.trial.publish()
	var trial_event := {"kind":"trial_state","session_id":session.network.session_id,"region":session.region_id,"epoch":session.trial.epoch,"serial":session.trial.serial,"state":session.trial.persistent_state()}
	session.shared_access.publish()
	var bridge_event := {"kind":"shared_access_state","session_id":session.network.session_id,"region":session.region_id,"epoch":session.shared_access.epoch,"serial":session.shared_access.serial,"state":session.shared_access.persistent_state()}
	var packet: Dictionary = session._snapshot()
	var references_match: bool = Contract.valid_refs(packet.get("facility_refs"))
	for pair in [[1,event],[2,distribution_event],[3,trial_event],[4,bridge_event]]:
		var reference: Dictionary = Contract.ref_for_slot(packet.get("facility_refs"),int(pair[0]))
		var reliable: Dictionary = pair[1]
		references_match = references_match and not reliable.state.is_empty() and reliable.session_id==packet.session_id and reference.get("epoch")==reliable.epoch and reference.get("serial")==reliable.serial
	check(session._facilities_ready() and references_match,"captured motion references all four genuine host publications",{"label":label,"facility_refs":packet.get("facility_refs")})
	var encoded: Dictionary = Codec.encode(packet)
	var raw: PackedByteArray = var_to_bytes(encoded)
	var zipped: PackedByteArray = raw.compress(FileAccess.COMPRESSION_ZSTD)
	var decoded: Dictionary = Codec.decode(bytes_to_var(zipped.decompress(raw.size(),FileAccess.COMPRESSION_ZSTD)))
	check(not encoded.is_empty() and decoded==packet,"two-body clinic motion packet roundtrips without loss",{"label":label,"raw_bytes":raw.size(),"zstd_bytes":zipped.size()})
	check(zipped.size()<=1150,"two-body clinic motion packet fits1150B",{"label":label,"zstd_bytes":zipped.size(),"reliable_clinic_bytes":var_to_bytes(event).size(),"reliable_distribution_bytes":var_to_bytes(distribution_event).size(),"reliable_trial_bytes":var_to_bytes(trial_event).size(),"reliable_bridge_bytes":var_to_bytes(bridge_event).size()})
	var poses: Dictionary = {}
	var bodies: Dictionary = _auxiliary_bodies()
	for id in bodies:
		var body: PhysicsBody3D = bodies[id]
		poses[id] = body.global_transform
	samples.append({"label":label,"packet":packet.duplicate(true),"event":event.duplicate(true),"distribution_event":distribution_event.duplicate(true),"trial_event":trial_event.duplicate(true),"bridge_event":bridge_event.duplicate(true),"auxiliary_poses":poses})
	session._action_received(1,"propose",{"kind":"pause","payload":{}})
	_freeze_bodies()

func _auxiliary_bodies() -> Dictionary:
	var cabinet = session.distribution.module
	var trial = session.trial.module
	var bodies: Dictionary = {"distribution/cover":cabinet.cover,"distribution/door":cabinet.door}
	for id in trial.link.moving_bodies: bodies["trial/link/"+str(id)] = trial.link.moving_bodies[id]
	for id in trial.station.selector_bodies: bodies["trial/selector/"+str(id)] = trial.station.selector_bodies[id]
	for id in trial.station.valve_bodies: bodies["trial/valve/"+str(id)] = trial.station.valve_bodies[id]
	for id in trial.station.float_bodies: bodies["trial/float/"+str(id)] = trial.station.float_bodies[id]
	for id in session.shared_access.module.moving_bodies: bodies["shared_access/moving/"+str(id)] = session.shared_access.module.moving_bodies[id]
	for id in session.shared_access.module.pin_bodies: bodies["shared_access/pin/"+str(id)] = session.shared_access.module.pin_bodies[id]
	return bodies

func _check_auxiliary_restore(sample: Dictionary, label: String) -> void:
	var available: bool = session._facilities_ready() and is_instance_valid(session.distribution.module) and is_instance_valid(session.trial.module) and is_instance_valid(session.shared_access.module)
	check(available,label+": all four facilities are ready before restored collision is usable")
	if not available: return
	var trial_expected: Dictionary = {"link":sample.trial_event.state.link,"station":sample.trial_event.state.station}
	check(_same(session.distribution.module.snapshot(),sample.distribution_event.state.mechanism) and _same(session.trial.module.snapshot(),trial_expected) and _same(session.shared_access.module.snapshot(),sample.bridge_event.state.mechanism),label+": cabinet, complete trial pair and bridge match genuine host states")
	var bodies: Dictionary = _auxiliary_bodies()
	var mismatch: Array = []
	for id in bodies:
		var body: PhysicsBody3D = bodies[id]
		var actual: Transform3D = PhysicsServer3D.body_get_state(body.get_rid(),PhysicsServer3D.BODY_STATE_TRANSFORM)
		if not sample.auxiliary_poses.has(id) or not actual.is_equal_approx(body.global_transform) or not actual.is_equal_approx(sample.auxiliary_poses.get(id,Transform3D.IDENTITY)):
			mismatch.append(id)
	check(bodies.size()>2 and bodies.size()==sample.auxiliary_poses.size() and mismatch.is_empty(),label+": actual cabinet doors, trial leaves/selector/floats and bridge moving/pin parts restore host PhysicsServer poses immediately",{"bodies":bodies.size(),"mismatch":mismatch})

func _pump_branch() -> void:
	phase = "pump_route_branch"
	check(session._save_environment(),"persist exact main ecology before independent pump branch")
	main_ecology = session.store.snapshot().world.ecology.duplicate(true)
	# The old inventory is nonzero, but online maintenance legitimately advances
	# while I2 supplies water. Account for completed authored jobs, not >= counters.
	var expected: Dictionary = facility_fixture.duplicate(true)
	var serial_sum := 0
	var route_defs: Dictionary = session.ecology.simulation.definitions()
	for actor in route_defs.actors:
		var steps: int = int(main_ecology.simulation.actors[actor.id].steps_completed)
		serial_sum += steps
		for index in range(steps):
			var job: Dictionary = actor.jobs[index % actor.jobs.size()]
			if job.kind == "deliver" and job.target_id == "I1:maintenance_cooling":
				expected.coolant = mini(3,int(expected.coolant)+1)
				expected.deliveries = int(expected.deliveries)+1
			elif job.kind == "repair":
				expected.maintenance[job.target_id] = mini(3,int(expected.maintenance.get(job.target_id,0))+1)
	check(serial_sum>0 and main_ecology.last_event_serial==serial_sum and _same(main_ecology.facilities,expected),"online background jobs explain exact inventory changes without an unexplained reset",{"steps":serial_sum,"expected":expected,"actual":main_ecology.facilities})
	await _switch("before-water")
	check(_volume()==0 and session.clinic.progress.snapshot().route_method=="" and not _completed(DIAGNOSE),"independent pre-water branch restores empty mechanism and story together")
	check(session.store.snapshot().personal.discoveries.count(DISCOVERY)==1,"personal discovery survives world-branch rewind")
	await _place(Vector3(-7,1.6,14))
	if not await _move(Vector3(-7,1.6,10),"real flight body enters low pump room through actual doorway"): return
	if not await _ability("charge",Works.RELAY_ID): return
	if not await _ability("takeover",Works.PUMP_ID): return
	for unused in range(50):
		if _volume()>0: break
		await _steps(1)
	check(_volume()>0 and session.clinic.module.status().pump_latched and session.clinic.module.status().powered and session.clinic.progress.snapshot().route_method=="pump","real charge and takeover move selector/interlock and start pump transfer")
	check(not _completed(DIAGNOSE),"pump-first route also does not fabricate diagnosis")
	await _travel("I1")
	var old_volume := _volume()
	await _steps(85)
	check(_volume()>old_volume and float(session.clinic.background_entities[Works.RELAY_ID].charge)>=20.0 and session.clinic.module.status().pump_latched,"saved relay and mechanical detent continue background flow beyond takeover duration")
	await _travel("I2")
	await _diagnosis_and_confirmation("pump",false)
	check(session.store.snapshot().personal.discoveries.count(DISCOVERY)==1,"both real routes on separate branches still yield only one personal discovery")

func _branch_restoration() -> void:
	phase = "branch_and_reload"
	await _switch("gravity-mid")
	check(_same(_hydraulic(session.clinic.persistent_state()),_hydraulic(gravity_mid)) and not _completed(DIAGNOSE),"first frame of saved partial branch restores exact water/history with no phantom objective")
	_check_poses("partial branch first frame")
	var volume_before := _volume()
	await _steps(3)
	check(_volume()>volume_before,"restored partial branch continues its already-open gravity route")
	var before: Dictionary = session.clinic.persistent_state()
	check(session._save_environment() and session._load_region("I2"),"real region reload accepts saved partial water state")
	_freeze_bodies()
	check(_same(_hydraulic(session.clinic.persistent_state()),_hydraulic(before)),"reload has no reset, duplicate transfer or offline catch-up")
	_capture_pair("gravity-partial-new-epoch")
	await _switch("main")
	check(_completed(CONFIRM) and _volume()==TARGET_ML and session.clinic.progress.snapshot().commissioned,"switching back restores completed gravity branch independently")
	check(_same(session.store.snapshot().world.ecology,main_ecology) and _same(session.ecology.persistent_state(),main_ecology),"return to main restores its exact saved ecology including legitimate online work")
	_capture_pair("completed-main-new-epoch")

func _guest_ordering() -> void:
	phase = "guest_first_frame_fixture"
	var protected_host: Dictionary = session.store.snapshot()
	var host_path: String = session.store.root_path
	guest_store = Store.new(base.path_join("guest"))
	check(guest_store.load_profile().ok and guest_store.commit({"id":"qa-clinic-guest-bootstrap"}).ok,"isolated guest profile persists its own identity")
	var guest_before: Dictionary = guest_store.snapshot()
	session.active = false
	session.network.close()
	session.free()
	session = MAIN.instantiate()
	root.add_child(session)
	_disable_callbacks()
	session.store = guest_store
	session.world_cache = guest_before.duplicate(true)
	session.profile_ready = true
	session.network.mode = "guest" # Offline peer retained: no socket or RPC transport.
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
	check(not session.clinic.ready and session.received_sequence==-1 and not session.pending_packet.is_empty(),"motion-first I2 packet waits for reliable hydraulic state instead of enabling an empty world")
	# Supply Trial independently so the existing invalid-clinic and missing-
	# distribution tests remain specific to those original streams.
	session._network_event(first.trial_event)
	session._network_event(first.bridge_event)
	var bad: Dictionary = first.event.duplicate(true)
	bad.state.history.observed_serial = int(bad.state.history.observed_serial)+1
	session._network_event(bad)
	session._process(0.0)
	check(not session.clinic.ready and session.received_sequence==-1,"inconsistent reliable history cannot enable guest input or consume motion sequence")
	session._network_event(first.event)
	session._process(0.0)
	check(session.clinic.ready and session.trial.ready and session.shared_access.ready and not session.distribution.ready and not session._facilities_ready() and session.received_sequence==-1,"valid hydraulic and trial states still wait for the independent cabinet stream")
	session._network_event(first.distribution_event)
	session._process(0.0)
	check(session.clinic.ready and session.distribution.ready and session.trial.ready and session.shared_access.ready and session.received_sequence==first.packet.sequence and session.simulation_paused,"valid late reliable state reconstructs paused first packet")
	check(_same(session.clinic.module.snapshot(),first.event.state.mechanism),"guest receives exact mechanism, axis, water and clock state")
	check(_same(session.clinic.persistent_state(),first.event.state),"guest first accepted state includes the complete matching observation history, not only the mechanism")
	_freeze_bodies()
	_check_poses("late reliable paused first frame")
	_check_auxiliary_restore(first,"late reliable paused first frame")
	var frozen: Dictionary = session.clinic.module.snapshot()
	var frozen_trial: Dictionary = session.trial.module.snapshot()
	var frozen_bridge: Dictionary = session.shared_access.module.snapshot()
	for unused in range(6):
		await physics_frame
		session.world.synchronize(session.entities,DT)
		session.clinic.advance(DT)
		session.trial.advance(DT)
		session.shared_access.advance(DT)
	check(session.clinic.module.snapshot()==frozen,"guest updates do not advance received water or guided mechanism")
	check(session.trial.module.snapshot()==frozen_trial,"guest updates do not advance received trial water, credit or guided mechanism")
	check(session.shared_access.module.snapshot()==frozen_bridge,"guest updates never advance authoritative bridge or pin")
	# Isolate the new fourth barrier using the genuine pump-branch publication.
	var bridge_sample: Dictionary = samples[1]
	var bridge_before: Dictionary = session.shared_access.module.snapshot()
	session._queue_snapshot(bridge_sample.packet)
	session._process(0.0)
	for event in [bridge_sample.event,bridge_sample.distribution_event,bridge_sample.trial_event]: session._network_event(event)
	session._process(0.0)
	check(session.clinic.ready and session.distribution.ready and session.trial.ready and not session.shared_access.ready and not session._facilities_ready() and session.received_sequence==first.packet.sequence and session.players[1].freeze and not session.pending_packet.is_empty(),"three genuine streams cannot release paused motion while bridge state is missing")
	check(session.shared_access.module.snapshot()==bridge_before,"missing bridge publication leaves its last validated physical pose unchanged")
	var foreign_bridge: Dictionary = bridge_sample.bridge_event.duplicate(true)
	foreign_bridge.session_id = "foreign-bridge-host"
	session._network_event(foreign_bridge)
	session._process(0.0)
	check(not session.shared_access.ready and session.received_sequence==first.packet.sequence and session.shared_access.module.snapshot()==bridge_before,"foreign bridge event cannot release the fourth barrier")
	session._network_event(bridge_sample.bridge_event)
	session._process(0.0)
	check(session._facilities_ready() and session.received_sequence==bridge_sample.packet.sequence and session.simulation_paused,"matching real bridge event releases exactly the pending paused pump branch")
	_check_poses("late fourth stream")
	_check_auxiliary_restore(bridge_sample,"late fourth stream")
	var bridge_current: Dictionary = session.shared_access.module.snapshot()
	session._network_event(first.bridge_event)
	session._process(0.0)
	check(session.shared_access.module.snapshot()==bridge_current and session.received_sequence==bridge_sample.packet.sequence,"old bridge epoch cannot overwrite newly restored bridge")
	frozen = session.clinic.module.snapshot()
	frozen_trial = session.trial.module.snapshot()
	frozen_bridge = session.shared_access.module.snapshot()
	# samples[2] is the later partial gravity branch.
	var early: Dictionary = samples[2]
	session._network_event(early.event)
	session._network_event(early.distribution_event)
	session._network_event(early.trial_event)
	session._network_event(early.bridge_event)
	check(session.clinic.module.snapshot()==frozen,"future-epoch reliable state alone cannot replace current collision")
	check(session.trial.module.snapshot()==frozen_trial,"future-epoch trial publication alone cannot move current link or station collision")
	check(session.shared_access.module.snapshot()==frozen_bridge,"future-epoch bridge publication alone cannot move current deck or pin")
	session._queue_snapshot(early.packet)
	session._process(0.0)
	check(session.received_sequence==early.packet.sequence and session.clinic.ready and session.distribution.ready and session.trial.ready and session.shared_access.ready and _same(session.clinic.module.snapshot(),early.event.state.mechanism),"reliable-first new-epoch motion adopts its exact partial branch state")
	_check_poses("early reliable new epoch")
	_check_auxiliary_restore(early,"early reliable new epoch")
	var newest: Dictionary = samples[3]
	var previous_trial: Dictionary = session.trial.module.snapshot()
	session._queue_snapshot(newest.packet)
	session._process(0.0)
	check(not session.clinic.ready and session.received_sequence==early.packet.sequence and session.players[1].freeze,"new-epoch motion freezes local body until matching reliable state")
	session._network_event(newest.event)
	session._network_event(newest.distribution_event)
	session._network_event(newest.bridge_event)
	session._process(0.0)
	check(session.clinic.ready and session.distribution.ready and session.shared_access.ready and not session.trial.ready and not session._facilities_ready() and session.received_sequence==early.packet.sequence and session.players[1].freeze and not session.pending_packet.is_empty(),"matching original two streams cannot release pending motion while new-epoch Trial is missing")
	check(session.trial.module.snapshot()==previous_trial,"missing Trial leaves the last validated physical link and station unchanged")
	session._network_event(newest.trial_event)
	session._process(0.0)
	check(session.clinic.ready and session.distribution.ready and session.trial.ready and session.shared_access.ready and session.received_sequence==newest.packet.sequence and session.simulation_paused,"matching late event releases only the pending newer motion")
	_check_poses("latest restored full branch")
	_check_auxiliary_restore(newest,"latest restored full branch")
	var last: Dictionary = session.clinic.module.snapshot()
	var last_trial: Dictionary = session.trial.module.snapshot()
	session._network_event(first.event)
	session._network_event(first.distribution_event)
	session._network_event(first.trial_event)
	session._network_event(first.bridge_event)
	session._queue_snapshot(first.packet)
	session._process(0.0)
	check(session.received_sequence==newest.packet.sequence and session.clinic.module.snapshot()==last,"old epoch and old motion cannot overwrite newer branch state")
	check(session.trial.module.snapshot()==last_trial,"old trial epoch cannot overwrite the accepted newer physical pair")
	var foreign: Dictionary = newest.event.duplicate(true)
	foreign.session_id = "other-world-session"
	foreign.serial = int(foreign.serial)+100
	session._network_event(foreign)
	check(session.clinic.module.snapshot()==last,"foreign-session hydraulic state is rejected")
	check(guest_store.snapshot()==guest_before,"guest first-frame restore never saves remote world into personal profile")
	var host_reread = Store.new(host_path)
	check(host_reread.load_profile().ok and _same(host_reread.snapshot(),protected_host),"guest lifecycle cannot overwrite protected host save")

func _finish(code: int) -> void:
	if done: return
	done = true
	print("CLINIC_SESSION checks=%d failures=%d profile=%s" % [checks.size(),failures.size(),profile])
	print("CLINIC_SESSION_RESULT "+JSON.stringify({"passed":code==0,"profile":profile,"checks":checks,"failures":failures,"limits":["Previous27 goals are fixed trusted historical events committed once; not a seven-action playthrough.","Water is accelerated with production0.1s fixed steps per actual physics frame, not a duration or performance measurement.","Body starting placements and the second physical roster entry are explicit fixtures. Doorway/deck crossings use actual move_and_collide.","Reliable and motion packets are injected into actual production consumers. No ENet, two-PC, GPU, guest reward ACK transport or human acceptance."]}))
	if is_instance_valid(session):
		session.active = false
		session.network.close()
		session.free()
	quit(code)
