extends SceneTree
## Isolated actual MAIN mechanism slices. Prior Director receipts are rules
## fixtures introduced only AFTER loading the blank physical development area.
const MAIN = preload("res://scenes/v3/main.tscn")
const Regions = preload("res://scripts/v3/world/twin_region_catalog.gd")
const Layout = preload("res://scripts/v3/campaign/twin_campaign_layout.gd")
const Store = preload("res://scripts/v3/core/twin_world_store.gd")
const Proofs = preload("res://scripts/v3/campaign/twin_campaign_runtime_proofs.gd")
const STARTS := {"F2":"F2:mirror_evidence:records","I3":"I3:cooling_route:brief","I4":"I4:array_witness:brief","F4":"F4:vein_reunion:council"}
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
var region := "F2"
var profile := ""
var output := ""
var finished := false
var complete := false
var checks: Array = []
var phases: Array = []
var fixture_receipts := 0
var expected_facts: Array = []
var expected_goals: Array = []
var expected_readings: Array = []
var payload_prepared: Dictionary = {}
var final_disk: Dictionary = {}

func _initialize() -> void:
	OS.add_logger(logger)
	_run.call_deferred()

func _run() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--region="): region = arg.trim_prefix("--region=")
		if arg.begins_with("--qa-profile="): profile = arg.trim_prefix("--qa-profile=")
		if arg.begins_with("--output="): output = arg.trim_prefix("--output=")
	if not STARTS.has(region) or not profile.begins_with("qa_campaign_remaining_mechanisms_") or profile!=profile.validate_filename() or not output.begins_with("res://artifacts/v3/campaign-remaining-mechanisms-") or ".." in output or DirAccess.dir_exists_absolute(output) or DirAccess.dir_exists_absolute("user://profiles_v3/"+profile):
		quit(2)
		return
	DirAccess.make_dir_recursive_absolute(output)
	create_timer(34).timeout.connect(func():
		if not finished:
			_check(false,"34 second single-region actual MAIN bound",_diagnostics())
			_finish())
	Regions._entries = Regions.entries()
	var layout: Dictionary = Layout.definition(region)
	for item: Dictionary in Regions._entries:
		if item.id==region:
			item.playable = true
			item.spawn = layout.spawn.duplicate()
			item.bounds = layout.bounds.duplicate()
	session = MAIN.instantiate()
	root.add_child(session)
	if not _check(session.profile_ready and session.start_flight("solo") and session._load_region(region) and session.region_id==region and session.campaign.supported(),"actual blank QA MAIN loads the physical area before the rules fixture",_diagnostics()): _finish(); return
	session.inputs.test_enabled = true
	session.inputs.test_frame = {"axes":{},"held":["brake"],"edges":[]}
	if not _seed_prefix(): _finish(); return
	session.story.load_world()
	_phase("actual_area_loaded_prior_rules_fixture_only")
	var passed := false
	match region:
		"F2": passed = await _f2()
		"I3": passed = await _i3()
		"I4": passed = await _i4()
		"F4": passed = await _f4()
	if finished: return
	if passed: complete = _verify_disk()
	_finish()

func _f2() -> bool:
	var patrol = session.ambient_patrol
	var scout = patrol.scout
	if not _check(patrol.enabled and is_instance_valid(scout) and scout.is_inside_tree() and scout.get_world_3d().space==session.world.get_world_3d().space and scout.hp>0 and patrol.error.is_empty(),"ordinary F2 default binds a live patrol in the actual region without test enabling",{"default_enabled":patrol.enabled,"error":patrol.error,"scout_hp":scout.hp if is_instance_valid(scout) else -1,"epoch":patrol.epoch}): return false
	expected_readings = ["F2:record_low","F2:record_high"]
	expected_facts = ["F2:paired_records","F2:clock_light_path"]
	expected_goals = ["F2:mirror_evidence:records","F2:mirror_evidence:archive","F2:mirror_evidence:light"]
	if not await _read_g("F2:record_low",true) or not await _read_g("F2:record_high",true): return false
	if not await _wait_goal(expected_goals[0],90): return false
	if not await _read_story("npc:shuyao",expected_goals[1]): return false
	var mirror: PhysicsBody3D = session.world.objects["F2:clock_mirror"]
	if not _check(absf(mirror.rotation.y-deg_to_rad(15))<.001,"authored F2 mirror starts physically unaligned at 15 degrees",_beam_diagnostics()): return false
	if not await _ability("F2:clock_mirror","light","on"): return false
	if not await _wait_fact("F2:clock_light_path",120): return false
	if not _check(absf(mirror.rotation.y-deg_to_rad(45))<.001 and session.campaign.mechanisms.view_state().get("beam_valid",false),"original light rotates the actual mirror to 45 degrees and both real ray segments hit the receiver front",_beam_diagnostics()): return false
	if not await _wait_goal(expected_goals[2],90): return false
	_phase("F2_actual_two_readings_and_reflection_saved")
	return true

func _i3() -> bool:
	expected_facts = ["I3:thermal_transfer_verified"]
	expected_goals = ["I3:cooling_route:brief","I3:cooling_route:ledger","I3:cooling_route:exchange"]
	for unused in 120:
		if session.thermal_cargo.supported() and session.thermal_cargo.module.ready: break
		await _frame()
		if finished: return false
	if not _check(session.thermal_cargo.supported() and session.thermal_cargo.module.ready,"ordinary I3 cargo observer reaches its actual initial support before G actions request the original capture boundary",session.thermal_cargo.module.status() if session.thermal_cargo.module!=null else {"participant_error":session.thermal_cargo.error}): return false
	if not await _read_story("npc:qiaoshu",expected_goals[0]) or not await _read_story("I3:cooling_ledger",expected_goals[1]): return false
	var before: Dictionary = session.campaign.mechanisms.persistent_state()
	if not _check(int(before.thermal.transfers)==0 and absf(session.world.objects["I3:cooling_valve"].rotation.y-PI*.5)<.001,"closed actual 90 degree valve has transferred no source heat",_diagnostics()): return false
	if not await _operate("I3:cooling_valve",Vector3(12,8,8),0.0): return false
	if not await _wait_fact("I3:thermal_transfer_verified",720): return false
	var heat: Dictionary = session.campaign.mechanisms.persistent_state().thermal
	if not _check(int(heat.source_loss_j)>=10000 and int(heat.source_loss_j)==int(heat.sink_gain_j)+int(heat.dissipated_j) and not heat.first_record.is_empty() and float(session.entities["I3:hot_cassette"].temperature)<=35 and float(session.entities["I3:cooling_sink"].temperature)>20,"original connected isolated solver removes source heat into the real sink with conserved joule history",{"thermal":heat,"diagnostics":_diagnostics()}): return false
	if not await _wait_goal(expected_goals[2],90): return false
	_phase("I3_actual_valve_and_conserved_heat_Story_saved")
	return true

func _i4() -> bool:
	expected_facts = ["I4:evidence_delivery_verified","I4:defence_isolated"]
	expected_goals = ["I4:array_witness:brief","I4:array_witness:archive","I4:array_witness:witness"]
	if not await _read_story("npc:wenxu",expected_goals[0]) or not await _read_story("I4:protocol_archive",expected_goals[1]): return false
	payload_prepared = Proofs.prepare_payload(session.story.director,session.world_cache.world)
	if not _check(payload_prepared.get("ok",false) and payload_prepared.get("sources",{}).size()==3,"original payload derives three exact branch-scoped Director receipt hashes from the explicit prior rules fixture",payload_prepared): return false
	if not await _ability("I4:witness_source","light","on"): return false
	if not await _wait_fact("I4:evidence_delivery_verified",120): return false
	var state: Dictionary = session.campaign.mechanisms.persistent_state()
	if not _check(session.campaign.mechanisms.view_state().get("witness_lit",false) and session.entities["I4:witness_receiver"].get("received_hashes",{})==payload_prepared.payload_hashes and state.histories.get("I4:evidence_chain",{})==payload_prepared.payload_hashes,"actual source-to-receiver ray delivers all three unchanged original receipt hashes",_beam_diagnostics()): return false
	if not await _wait_goal(expected_goals[2],90): return false
	# Route traversal is deliberately outside this slice. No waypoint teleports,
	# synthetic route receipt or pose sequence is used to unlock its Story goal.
	if not await _ability("I4:civilian_feed","charge","add"): return false
	if not await _ability("I4:defence_platform","force_field","pin"): return false
	if not await _operate("I4:defence_breaker",Vector3(14,5.2,-.5),0.0): return false
	if not await _wait_fact("I4:defence_isolated",120): return false
	state = session.campaign.mechanisms.persistent_state()
	var civilian: Dictionary = session.entities["I4:civilian_feed"]
	if not _check(state.facts.get("I4:defence_isolated")=="field_lock" and state.histories.has("I4:defence_record") and civilian.powered and float(civilian.charge)>=35 and not state.facts.has("I4:storm_route_verified") and "I4:array_witness:shelter" not in session.story.state.completed,"actual supported stationary field lock isolates defence while charged civilian supply stays live; no unflown route is credited",_diagnostics()): return false
	if not _check(session._save_environment(),"original Session saves physically verified I4 isolation history despite the intentionally unplayed route",_diagnostics()): return false
	_phase("I4_actual_optical_receipts_and_separate_defence_saved_route_not_tested")
	return true

func _f4() -> bool:
	expected_facts = ["F4:industrial_link_verified","F4:living_link_verified","F4:dual_load_verified","F4:plans_reviewed"]
	expected_goals = ["F4:vein_reunion:council","F4:vein_reunion:industry","F4:vein_reunion:living","F4:vein_reunion:test","F4:vein_reunion:plan"]
	expected_readings = ["F4:industrial_gauge","F4:living_gauge","F4:choice_terminal"]
	if not await _read_story("npc:guanzhi",expected_goals[0]): return false
	if not await _operate("F4:limited_bus",Vector3(-12,9,8),0.0) or not await _operate("F4:limited_bus",Vector3(-12,9,6),0.0): return false
	if not await _ability("F4:limited_bus","charge","add"): return false
	if not await _wait_goal(expected_goals[1],120): return false
	if not await _ability("F4:living_emitter","light","on"): return false
	for unused in 3:
		if not await _ability("F4:living_support","growth",""): return false
	if not await _wait_goal(expected_goals[2],120): return false
	if not _check(session.entities["F4:living_support"].growth==1.0 and session.campaign.mechanisms.view_state().get("living_connected",false),"original directed sustained emitter and three growth intents create the full supported living collision path",_beam_diagnostics()): return false
	if not await _operate("F4:test_hold",Vector3(10,16,-5),PI*.5): return false
	if not await _wait_view("dual_load_valid",120): return false
	var serial: int = session.campaign.mechanisms.persistent_state().histories.get("F4:load_test",{}).get("test_serial",-1)
	if not await _read_g("F4:industrial_gauge",true) or not await _read_g("F4:living_gauge",true): return false
	var measured: Dictionary = session.campaign.mechanisms.persistent_state().histories.get("F4:dual_load_record",{})
	if not _check(measured.get("method")=="latched_test" and measured.get("test_serial")==serial and measured.get("readings",{}).size()==2 and measured.readings.industrial.test_serial==serial and measured.readings.living.test_serial==serial and int(measured.readings.industrial.load_w)==120 and int(measured.readings.living.load_w)==90,"two actual G gauge readings measure distinct live loads in the same original latched test",measured): return false
	if not await _wait_goal(expected_goals[3],90): return false
	if not await _read_g("F4:choice_terminal",false): return false
	if not _check(session.interface.chapter_choice.visible and session.chapter_choices._read_options(1,"F4:plans_reviewed").is_empty() and not session.campaign.mechanisms.persistent_state().facts.has("F4:plans_reviewed"),"nearby G only opens the three-plan panel; none is automatically read or selected",_diagnostics()): return false
	for option: String in ["shared_stewardship","industrial_lifeline","living_vein"]:
		if not _check(session.chapter_choices.read_option(1,"F4:plans_reviewed",option),"explicit original benefit/cost plan acknowledgement: "+option,_diagnostics()): return false
		await _frame()
		if finished: return false
	if not await _wait_goal(expected_goals[4],90): return false
	var plans: Dictionary = session.campaign.mechanisms.persistent_state().histories.get("F4:plans_read",{})
	if not _check(plans.size()==3 and session.chapter_choices.has_read_all(1,"F4:plans_reviewed") and not session.story.state.choices.has("F4:chapter_choice"),"all three explicit plan readings persist without making the final chapter choice",plans): return false
	_phase("F4_both_actual_lifelines_same_test_gauges_three_explicit_plans_saved")
	return true

func _seed_prefix() -> bool:
	var director = session.story.director
	var state: Dictionary = director.default_state()
	var found := false
	for action: Dictionary in director.definitions().actions:
		for objective: Dictionary in action.objectives:
			if objective.id==STARTS[region]: found = true; break
			var matcher: Dictionary = objective.events[0]
			var applied: Dictionary = director.apply_event(state,{"id":"qa-remaining-prefix:"+str(objective.id),"type":matcher.type,"target_id":matcher.target_id,"option":matcher.options[0]},{"is_authority":true,"validated":true,"region_id":action.region_id})
			if not applied.get("ok",false) or not applied.get("changed",false): return _check(false,"ordered prior Director rules fixture validates",{"objective":objective.id,"result":applied.get("code")})
			state = applied.state
			fixture_receipts += 1
		if found: break
	if not _check(found and director.validate_state(state).get("ok",false) and STARTS[region] not in state.completed,"prior rules fixture stops before every current-region objective",{"prior_receipts":fixture_receipts}): return false
	var changes := {"world.actions.opening":state,"world.region_id":region}
	if region=="I4": changes["world.completed_objectives"] = state.completed.duplicate() # Original three-source payload's consistent receipt index; fixture, not played history.
	var stored: Dictionary = session.store.commit({"id":"qa-remaining-prefix-and-loaded-region:"+region,"set":changes})
	if not _check(stored.get("ok",false),"already-loaded private QA records only prior legal rules and its current-region location",stored): return false
	session.world_cache = session.store.snapshot()
	session.consensus.set_world_revision(int(session.world_cache.world_revision))
	return true

func _read_story(id: String,goal: String) -> bool:
	if not await _read_g(id,false): return false
	return await _wait_goal(goal,90)

func _read_g(id: String,manual: bool) -> bool:
	if not _check(session.story.markers.has(id),"ordinary Story G has the authored marker registered: "+id,_diagnostics()): return false
	var marker: Dictionary = session.story.markers[id]
	var point: Vector3 = session.story._point(marker)
	if not await _place(point+Vector3.UP*1.4,"G observation "+id): return false
	var actor: FlightBodyV2 = session.players[1]
	if not _check(actor.global_position.distance_to(point)<=float(marker.radius) and session._line_clear(actor.global_position,point,actor.get_rid(),id),"actual G source is within radius and visible: "+id): return false
	# Lock the actual gauge when it is an entity, so the earlier hold lock cannot
	# redirect G. Story-only sources are outside the preceding device's range.
	if session.entities.has(id): session._action_received(1,"lock",{"target_id":id})
	_press_g()
	await _frame()
	if finished: return false
	if manual: return _check(session.campaign.mechanisms.persistent_state().readings.has(id),"original nearby G saves the actual manual reading: "+id,_diagnostics())
	return true

func _operate(id: String,expected_position: Vector3,expected_yaw: float) -> bool:
	if not await _near(id): return false
	var generation: int = session.store.snapshot().generation
	session._action_received(1,"lock",{"target_id":id})
	_press_g()
	var body: PhysicsBody3D = session.world.objects[id]
	var basis := Basis(Vector3.UP,expected_yaw)
	# I3's ordinary action first captures its owned thermal cargo at the normal
	# SaveGate physics boundary; do not mistake that legitimate async phase for
	# a rejected G or bypass the original action routing.
	for unused in 90:
		await _frame()
		if finished: return false
		if body.global_position.distance_to(expected_position)<.002 and body.global_basis.is_equal_approx(basis) and int(session.store.snapshot().generation)>generation: break
	var actual: Transform3D = PhysicsServer3D.body_get_state(body.get_rid(),PhysicsServer3D.BODY_STATE_TRANSFORM)
	return _check(body.global_position.distance_to(expected_position)<.002 and body.global_basis.is_equal_approx(basis) and actual.origin.distance_to(expected_position)<.002 and actual.basis.is_equal_approx(basis) and int(session.store.snapshot().generation)>generation and session.campaign.last_operation_blockers.is_empty(),"original G completes real device travel and its Store commit: "+id,{"actual":actual,"expected_position":expected_position,"expected_yaw":expected_yaw,"diagnostics":_diagnostics()})

func _ability(id: String,ability: String,mode: String) -> bool:
	if not await _near(id): return false
	for unused in 40:
		if float(session.cooldowns.get(1,0))<=0: break
		await _frame()
		if finished: return false
	var count: int = session.stats.abilities
	session._action_received(1,"ability",{"ability":ability,"target_id":id,"mode":mode})
	await _frame()
	if finished: return false
	return _check(session.stats.abilities==count+1,"original range/LOS/energy/cooldown rules accept "+ability+" on "+id,_diagnostics())

func _near(id: String) -> bool:
	if id=="I4:defence_platform":
		# The real breaker stands above the platform centre. Observe from the
		# east edge, so the ray reaches the platform top before that breaker.
		var point: Vector3 = session.world.objects[id].global_position
		if not await _place(point+Vector3(2.8,1.0,0),"side view of "+id): return false
		var actor: FlightBodyV2 = session.players[1]
		return _check(session._line_clear(actor.global_position,point,actor.get_rid(),id),"QA side observation has actual unobstructed LOS to the platform",{"observer":actor.global_position,"target":point})
	return await _place(session.world.objects[id].global_position+Vector3.UP*3.4,"near "+id)

func _place(at: Vector3,label: String) -> bool:
	var actor: FlightBodyV2 = session.players[1]
	var shape := actor.get_node("Envelope") as CollisionShape3D
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = shape.shape
	query.transform = Transform3D(Basis.IDENTITY,at)*shape.transform
	query.collision_mask = 1|2|8|32
	query.exclude = [actor.get_rid()]
	var hits: Array[Dictionary] = session.world.get_world_3d().direct_space_state.intersect_shape(query,8)
	if not _check(hits.is_empty() and Regions.contains(region,at),"QA observation pose has real full-aircraft clearance: "+label,{"at":at,"hits":hits.map(func(hit: Dictionary): return str(hit.collider.get_path()))}): return false
	actor.freeze = true
	actor.global_transform = Transform3D(Basis.IDENTITY,at)
	actor.force_update_transform()
	PhysicsServer3D.body_set_state(actor.get_rid(),PhysicsServer3D.BODY_STATE_TRANSFORM,actor.global_transform)
	actor.linear_velocity = Vector3.ZERO
	actor.angular_velocity = Vector3.ZERO
	actor.hold_height = at.y
	await _frame()
	return not finished

func _press_g() -> void:
	session.interface.clear_dialogue()
	var event := InputEventKey.new()
	event.physical_keycode = KEY_G
	event.keycode = KEY_G
	event.pressed = true
	session._unhandled_input(event)

func _wait_goal(id: String,frames: int) -> bool:
	for unused in frames:
		if id in session.story.state.get("completed",[]): return _check(true,"original Story commits current objective: "+id)
		await _frame()
		if finished: return false
	return _check(false,"original Story commits current objective: "+id,_diagnostics())

func _wait_fact(id: String,frames: int) -> bool:
	for unused in frames:
		if not session.campaign.fact(id).is_empty(): return _check(true,"original physical observer yields fact: "+id,_diagnostics())
		await _frame()
		if finished: return false
	return _check(false,"original physical observer yields fact: "+id,_beam_diagnostics())

func _wait_view(key: String,frames: int) -> bool:
	for unused in frames:
		if bool(session.campaign.mechanisms.view_state().get(key,false)): return _check(true,"original live mechanism sample: "+key,_diagnostics())
		await _frame()
		if finished: return false
	return _check(false,"original live mechanism sample: "+key,_beam_diagnostics())

func _verify_disk() -> bool:
	var reader = Store.new(session.store.root_path)
	var opened: Dictionary = reader.load_profile()
	final_disk = reader.snapshot()
	var saved: Dictionary = final_disk.world.get("environment",{}).get("campaign_"+region,{}).get("mechanisms",{})
	var mechanism_ok: Dictionary = session.campaign.mechanisms.validate_state(saved)
	var action_ok: Dictionary = session.story.director.validate_state(final_disk.world.get("actions",{}).get("opening",{}))
	var verified: bool = opened.get("ok",false) and mechanism_ok.get("ok",false) and action_ok.get("ok",false)
	for id: String in expected_facts: verified = verified and saved.get("facts",{}).has(id)
	for id: String in expected_goals: verified = verified and id in final_disk.world.actions.opening.completed
	for id: String in expected_readings: verified = verified and saved.get("readings",{}).has(id)
	if not _check(verified,"independent original Store reader validates all actual facts, required goals and explicit readings",{"opened":opened,"mechanism_validation":mechanism_ok,"Story_validation":action_ok,"saved_mechanisms":saved}): return false
	return _check(not session.campaign.active() and not session.boss_active,"mechanism slice creates no Boss encounter or victory")

func _beam_diagnostics() -> Dictionary:
	var result: Dictionary = _diagnostics()
	var traces: Array = []
	var pairs: Array = [["F2:clock_source","F2:clock_mirror"],["F2:clock_mirror","F2:clock_receiver"]] if region=="F2" else ([["I4:witness_source","I4:witness_receiver"]] if region=="I4" else [["F4:living_emitter","F4:living_support"]])
	for pair: Array in pairs:
		if not session.world.objects.has(pair[0]) or not session.world.objects.has(pair[1]): continue
		var first: PhysicsBody3D = session.world.objects[pair[0]]
		var second: PhysicsBody3D = session.world.objects[pair[1]]
		var ray := PhysicsRayQueryParameters3D.create(first.global_position,second.global_position,1|8,[first.get_rid()])
		var hit: Dictionary = session.world.get_world_3d().direct_space_state.intersect_ray(ray)
		traces.append({"from":pair[0],"to":pair[1],"from_pose":first.global_transform,"to_pose":second.global_transform,"direct_line_collider":str(hit.collider.get_path()) if not hit.is_empty() else "","hit_position":hit.get("position")})
	result["read_only_direct_ray_diagnostics"] = traces
	result["growth_blockers"] = session.world.campaign_growth_blockers.duplicate(true)
	return result

func _frame() -> void:
	await physics_frame
	await process_frame

func _phase(label: String) -> void:
	var row := {"phase":label,"diagnostics":_diagnostics()}
	phases.append(row)
	print("CAMPAIGN_REMAINING_PROGRESS "+JSON.stringify(row))

func _diagnostics() -> Dictionary:
	if not is_instance_valid(session): return {"session":"not_installed"}
	return {"region":session.region_id,"stored_region":session.world_cache.world.get("region_id"),"message":session.interface.message.text,"world_errors":session.world.build_errors if is_instance_valid(session.world) else [],"last_commit_result":session.last_commit_result.duplicate(true),"campaign_error":session.campaign.error,"blockers":session.campaign.last_operation_blockers,"mechanism":session.campaign.mechanisms.persistent_state() if session.campaign.mechanisms!=null else {},"view":session.campaign.mechanisms.view_state() if session.campaign.mechanisms!=null else {},"current_targets":session.story.current_targets()}

func _check(ok: bool,label: String,actual: Variant=null) -> bool:
	checks.append({"passed":ok,"label":label,"actual":actual})
	return ok

func _finish() -> void:
	if finished: return
	finished = true
	if is_instance_valid(session):
		session.environment_save_gate.cancel("qa_teardown")
		session.active = false
		session.network.close()
		session.audio.shutdown()
		var deadline: int = Time.get_ticks_usec()+1000000
		var audio_status: Dictionary = session.audio.shutdown_status()
		while not audio_status.ready and Time.get_ticks_usec()<deadline:
			await process_frame
			audio_status=session.audio.shutdown_status()
		_check(audio_status.ready,"original terminal audio shutdown drains within original 1s",audio_status)
	var failures: Array = checks.filter(func(row: Dictionary): return not row.passed)
	var report := {"region":region,"complete":complete,"checks":checks,"failures":failures,"engine_errors":logger.errors,"phases":phases,"fixture_receipts":fixture_receipts,"payload_prepared":payload_prepared,"saved_environment":final_disk.get("world",{}).get("environment",{}).get("campaign_"+region,{}),"diagnostics":_diagnostics(),"scope":"One actual MAIN blank private QA loads its in-memory-playable authored physical area, then receives an ordered Director-valid prior rules fixture stopping before every current-region objective. Only matching already-loaded world.region_id is set; I4 also indexes those prior rule receipts in original completed_objectives for the original three-source payload validator. This is not prior physical completion or played campaign evidence. Explicit full-hull-clear QA actor observation poses are allowed and disclosed. Actual G and original ability/range/LOS/energy rules operate authored bodies; normal physics samples and original Story/Store perform all current facts. F2: two G manual readings and actual two-segment reflection; I3: G valve and conserved real heat exchange, no loaded-route claim; I4: original three-receipt payload, light ray/receiver and separate real defence/civilian condition, deliberately no storm-route fixture or credit; F4: actual bounded industrial supply/living light+growth support, G latch/two explicit same-test load readings, three explicit plan benefit/cost acknowledgements, no final choice. Independent original Store reader validates outputs. No injected physical fact/environment/event, changed HP, moved device fixture, fabricated nutrition, Store success, synthetic goal, played route, Boss fight, graphics/performance/LAN/human fun or full campaign acceptance."}
	FileAccess.open(output+"/result.json",FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
	print("CAMPAIGN_REMAINING_MAIN_RESULT "+JSON.stringify({"region":region,"complete":complete,"checks":checks.size(),"failures":failures,"engine_errors":logger.errors,"diagnostics":report.diagnostics}))
	if is_instance_valid(session):
		session.environment_save_gate.cancel("qa_teardown")
		if session.canal!=null: session.canal.clear()
		session.thermal_cargo.clear()
		session.network.close()
		session.free()
		session = null
	await process_frame
	await physics_frame
	await process_frame
	quit(0 if complete and failures.is_empty() and logger.errors.is_empty() else 1)
