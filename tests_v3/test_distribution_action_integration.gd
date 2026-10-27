extends "res://tests_v3/test_trial_integration.gd"
## Actual MAIN + abilities + native G + physical routes + real Store. The old
## 27-goal history, starting pilot placements and second local participant are
## explicit QA fixtures. This does not claim sockets, human pacing or visuals.
const Shared = preload("res://scripts/v3/gameplay/twin_shared_access_session.gd")
const Bridge = Shared.Bridge
const DIAGNOSE := "I2:clinic_supply:diagnose"
const CONFIRM := "I2:clinic_supply:confirm"

func _run() -> void:
	var count := 0
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--qa-profile="):
			profile = arg.trim_prefix("--qa-profile=")
			count += 1
		elif arg.begins_with("--qa-network") or arg.begins_with("--qa-capture") or arg.begins_with("--qa-suite"):
			check(false,"refuse unrelated automatic drivers")
	if count != 1 or not profile.begins_with("qa_distribution_action_") or profile != profile.validate_filename():
		check(false,"require one fresh qa_distribution_action_ profile")
	base = "user://qa_v3_distribution_action/" + profile
	if DirAccess.dir_exists_absolute(base) or DirAccess.dir_exists_absolute("user://profiles_v3/" + profile):
		check(false,"refuse existing test/profile paths")
	if not failures.is_empty():
		_finish(2)
		return
	create_timer(150).timeout.connect(func():
		if not done:
			check(false,"bounded whole-action integration timeout")
			_finish(2))
	session = MAIN.instantiate()
	if not _main_usable():
		check(false,"MAIN retains its complete Session implementation")
		_finish(1)
		return
	root.add_child(session)
	if not _disable_callbacks():
		_finish(1)
		return
	check(session.start_flight("solo"),"fresh actual MAIN starts solo")
	if _healthy() and _seed_history():
		await _travel("I2")
		if _healthy(): await _early_bridge_view()
		if _healthy(): await _sample_via_session()
		if _healthy(): await _pending_read_and_return()
		if _healthy(): await _early_cabinet()
		if _healthy(): await _restore_clinic()
		if _healthy(): await _physical_consensus()
		if _healthy(): await _historical_choice_and_branch()
	_finish(0 if failures.is_empty() else 1)

func _early_bridge_view() -> void:
	phase = "early_bridge_inspection_without_false_confirmation"
	await _place(session.shared_access.inspection_position("public_span"))
	session._refresh_interface()
	check(_body_clear() and session.story.nearest(session.players[1].global_position)==Bridge.PUBLIC_CONTROL,"early bridge inspection uses the real unobstructed console approach")
	check(session.story.interaction_label(Bridge.PUBLIC_CONTROL)=="查看当前桥位" and "查看当前桥位" in session.interface.explore_button.text,"predecessor stage offers inspection without promising a final arrangement")
	var before: Dictionary = session.store.snapshot()
	_g()
	var note: String = session.interface.message.text
	check("当前桥位：住区短接" in note and "完成双窗试流调查" in note,"early native G explains the real current bridge and the outstanding investigation",{"message":note})
	check(session.consensus.current_proposal().is_empty() and session.store.snapshot()==before,"early inspection neither proposes a decision nor changes progress or rewards")

func _early_cabinet() -> void:
	phase = "early_real_cabinet_knowledge"
	await _place(Vector3(17.8,2.7,-7.85))
	check(_body_clear(),"electric cabinet approach clears production geometry")
	if not await _ability("charge",Cabinet.RELAY_ID): return
	if not await _ability("takeover",Cabinet.LOCK_ID): return
	for unused in range(60):
		await _steps(1)
		if not _healthy(): return
		if float(session.distribution.module.snapshot().door_fraction) == 1.0: break
	check(float(session.distribution.module.snapshot().door_fraction)==1.0,"real takeover raises the complete low door")
	await _place(Vector3(18,2.3,-7.7))
	if not await _move(Vector3(18,2.3,-10.8),"actual TR01 crosses the open low service door"): return
	await _place(Vector3(18,2.7,-10.8))
	var proof: Dictionary = session.distribution.module.observe_back(1,session.players[1])
	check(proof.ok and proof.method=="service_lock","both actual plates are visible from inside the low route",proof)
	check(session.story.nearest(session.players[1].global_position)==Progress.FACT_TARGET,"native G selects real cabinet inspection")
	if not _healthy(): return
	_g()
	check(session.distribution.progress.snapshot().back_observed and session.distribution.progress.snapshot().method=="service_lock","early G durably retains actual electrical observation")
	check(_same(session.story.state,history_fixture) and session.store.snapshot().personal==original_personal,"early cabinet and sample knowledge do not skip the clinic predecessor or award the new action")

func _restore_clinic() -> void:
	phase = "actual_clinic_predecessor_unlocks_retained_evidence"
	await _place(Vector3(-10,7,-2.5))
	if not await _ability("push_pull",Works.GRAVITY_ID): return
	for unused in range(60):
		await _steps(1)
		if not _healthy(): return
		if int(session.clinic.module.status().clinic_volume_ml)>0: break
	check(int(session.clinic.module.status().clinic_volume_ml)>0,"physical gravity route transfers actual clinic water")
	await _place(Vector3(7,5.8,-1))
	check(session.story.nearest(session.players[1].global_position)=="I2:clinic_demand","native G selects the actual diagnosis")
	_g()
	check(DIAGNOSE in session.story.state.completed,"real nearby G commits clinic diagnosis")
	await _steps(4)
	for unused in range(850):
		if int(session.clinic.module.status().clinic_volume_ml)==2000000: break
		await _steps(1)
		if not _healthy(): return
	check(int(session.clinic.module.status().clinic_volume_ml)==2000000,"conserved actual water reaches the clinic cutoff")
	await _steps(25)
	check(session.clinic.access_clear() and session.story.nearest(session.players[1].global_position)=="I2:clinic_water_check","clear stable deck leaves final confirmation explicitly available")
	_g()
	check(CONFIRM in session.story.state.completed and session.clinic.progress.snapshot().commissioned,"native G commits water, commissioning and predecessor objective")
	await _steps(8)
	var state: Dictionary = session.story.state
	check(state.completed.size()==33 and state.completed_actions.size()==8 and state.choices.get(Progress.EXPOSE)=="service_lock" and state.choices.get(Trial.TRACE_OBJECTIVE)=="pulse_trial","production observer consumes both retained physical facts after unlock without repeating experiments",state.choices)
	check(session.story.shared_choice_available() and Shared.OBJECTIVE not in state.completed,"ninth action still requires explicit real bridge arrangement")
	await _fork("before_access")

func _confirm(peer: int) -> void:
	var proposal: Dictionary = session.consensus.current_proposal()
	session._action_received(peer,"confirm",{"proposal_id":proposal.get("proposal_id","missing"),"world_revision":proposal.get("world_revision",-1)})

func _route_obstacle() -> StaticBody3D:
	var prop := StaticBody3D.new()
	prop.name = "QAActualRouteObstruction"
	prop.position = Vector3(15,6,0)
	prop.collision_layer = 1
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(.2,.2,.2)
	collision.shape = shape
	prop.add_child(collision)
	session.world.add_child(prop)
	return prop

func _inspection_anchor(mode: String) -> Vector3:
	var module = session.shared_access.module
	var point: Vector3 = session.shared_access.inspection_position(mode)
	var id: String = Bridge.PUBLIC_CONTROL if mode=="public_span" else Bridge.SERVICE_CONTROL
	var controller: Vector3 = module.entity_position(id)
	var landing: StaticBody3D = module.fixed_bodies.EastLanding
	var displayed: Dictionary = session.story.target_anchor(Shared.FACT)
	check(point.is_finite() and is_equal_approx(point.x,landing.global_position.x) and is_equal_approx(point.z,controller.z),"inspection destination follows the real landing centre and selected controller",{"mode":mode,"point":str(point),"landing":str(landing.global_position),"controller":str(controller)})
	check(displayed.get("position") is Vector3 and displayed.position.is_equal_approx(point),"active bridge objective uses the real above-route inspection destination",displayed)
	var taller: Vector3 = session.shared_access.inspection_position(mode,.54)
	check(is_equal_approx(taller.y-point.y,.20) and taller.x==point.x and taller.z==point.z,"larger observer clearance raises the inspection destination without moving the physical controller")
	return point

func _cancel_vote_button() -> void:
	session._refresh_interface()
	var cancel_button: Button
	for item in session.interface.vote.find_children("*","Button",true,false):
		if item.text=="暂缓，继续探索": cancel_button=item
	check(is_instance_valid(cancel_button) and session.interface.vote.visible,"ready proposal exposes the actual cancel-and-explore UI button")
	if not is_instance_valid(cancel_button): return
	# Exercise the existing button binding through UI -> NetworkPort -> Session.
	# This is a native control activation, not a synthetic consensus.resolve call.
	cancel_button.pressed.emit()
	session._refresh_interface()
	await _steps(1)
	check(session.consensus.current_proposal().is_empty() and not session.interface.vote.visible and session.inputs.active,"UI cancel releases the ready decision and restores normal flight input")

func _move_blocking_peer_above_route() -> void:
	var peer := 2
	var body = session.players[peer]
	var destination: Vector3 = body.global_position+Vector3.UP*2.2
	check(_body_clear(peer),"blocking HX occupies the walking clearance but starts outside solid geometry")
	var collision: KinematicCollision3D
	var moves := 0
	# A collision-respecting motion fixture after the real UI releases inputs;
	# no position assignment, removal or fake route-clear result clears the hull.
	while body.global_position.distance_to(destination)>.002 and moves<20:
		collision=body.move_and_collide((destination-body.global_position).limit_length(.2))
		await _steps(1,1.0/60.0)
		moves+=1
		if collision!=null or not _healthy(): break
	check(collision==null and body.global_position.distance_to(destination)<.005 and _body_clear(peer),"actual HX hull moves clear through the production space after cancellation",{"position":str(body.global_position),"destination":str(destination),"moves":moves,"collider":"" if collision==null else str(collision.get_collider().get_path())})

func _physical_consensus() -> void:
	phase = "two_local_participants_and_commit_time_revalidation"
	# This is deliberately NOT a network guest: real second hull and consensus,
	# but no ENet identity registration or socket claim.
	session._spawn_player(2,"qa-second-physical",Vector3(25,10,18),"hx02")
	_freeze_bodies()
	session.consensus.configure([1,2],int(session.world_cache.world_revision))
	var public_inspection: Vector3 = _inspection_anchor("public_span")
	await _place(Vector3(public_inspection.x,public_inspection.y,session.shared_access.module.entity_position(Bridge.SERVICE_CONTROL).z))
	check(session.story.nearest(session.players[1].global_position)==Bridge.PUBLIC_CONTROL,"locked public bridge remains the G choice even when pilot is closer to the service controller")
	await _place(public_inspection)
	check(_body_clear() and session.shared_access.choice_confirmation(1,"public_span").ok,"actual public controller can be inspected above the pedestrian clearance")
	check(session.story.nearest(session.players[1].global_position)==Bridge.PUBLIC_CONTROL,"native G selects the live public controller")
	var before_radio: Dictionary = session.store.snapshot()
	for unused in range(32):
		if not session.interface.radio.visible: break
		session.interface.explore_button.pressed.emit()
	check(not session.interface.radio.visible and session.store.snapshot()==before_radio and session.consensus.current_proposal().is_empty(),"actual continue-dialogue button finishes clinic radio without confirming a bridge arrangement")
	session._refresh_interface()
	check("确认住区通路安排" in session.interface.explore_button.text,"completed investigation now exposes the actual arrangement confirmation")
	_g()
	var proposal: Dictionary = session.consensus.current_proposal()
	check(proposal.get("state")=="pending" and proposal.get("kind")=="facility_choice" and Shared.OBJECTIVE not in session.story.state.completed,"one of two real participants cannot finalize the arrangement alone",proposal)
	if not _healthy(): return
	session._action_received(2,"cancel",{"proposal_id":proposal.proposal_id})
	check(session.consensus.current_proposal().is_empty() and Shared.OBJECTIVE not in session.story.state.completed,"disagreement cancels the proposed result with no reward")
	_g()
	proposal = session.consensus.current_proposal()
	check(proposal.get("state")=="pending","native G can propose again after cancellation")
	if not _healthy(): return
	var before_body_obstruction: Dictionary = session.store.snapshot()
	await _place(Vector3(15,6.4,0),2)
	check(_body_clear(2),"second real hull blocks the public route without intersecting the bridge deck or guards")
	_confirm(2)
	session._refresh_interface()
	await _steps(1)
	check(session.consensus.current_proposal().get("state")=="ready" and session.store.snapshot()==before_body_obstruction and not session.inputs.active,"unanimous but physically occupied route remains uncommitted while the vote UI captures input")
	if not _healthy(): return
	await _cancel_vote_button()
	if not _healthy(): return
	await _move_blocking_peer_above_route()
	if not _healthy(): return
	check(session.shared_access.choice_confirmation(1,"public_span").ok and Shared.OBJECTIVE not in session.story.state.completed,"moving the real blocking hull restores confirmability without granting the objective")
	_g()
	proposal=session.consensus.current_proposal()
	check(proposal.get("state")=="pending" and proposal.get("participants",[]).size()==2,"native G reproposes the current real configuration to both participants after physical remediation")
	if not _healthy(): return
	var before: Dictionary = session.store.snapshot()
	var blocker := _route_obstacle()
	await physics_frame
	await physics_frame
	_confirm(2)
	check(session.consensus.current_proposal().get("state")=="ready" and session.store.snapshot()==before and Shared.OBJECTIVE not in session.story.state.completed,"both votes cannot commit after the actual route becomes obstructed")
	check("挡住了通路" in session.interface.message.text and "保存未成功" not in session.interface.message.text,"blocked-route feedback identifies the physical problem and how to resume instead of blaming storage")
	blocker.free()
	await physics_frame
	await physics_frame
	check(session.shared_access.choice_confirmation(1,"public_span").ok,"removing the actual obstacle restores both routes without changing the chosen mode")
	session.store.failure_point="before_publish"
	_confirm(2)
	check(session.store.snapshot()==before and session.consensus.current_proposal().get("state")=="ready" and Shared.OBJECTIVE not in session.story.state.completed,"failed Store publication keeps a retryable unanimous proposal and awards nothing")
	session.store.failure_point=""
	_confirm(2)
	var saved: Dictionary = session.store.snapshot()
	check(session.consensus.current_proposal().is_empty() and session.story.state.completed.size()==34 and session.story.state.completed_actions.size()==9,"successful explicit retry completes exactly nine actions and thirty-four objectives")
	check(saved.world.flags.get(Shared.FLAG,false) and saved.world.actions.opening.choices.get(Shared.OBJECTIVE)=="public_span" and session.store.matches_persisted_value(session.shared_access.persistent_state(),saved.world.environment.I2_shared_access),"same durable transaction includes exact current bridge, world flag and chosen public arrangement")
	check(saved.personal.discoveries.count(Shared.DISCOVERY)==1,"public arrangement awards the stable personal discovery once")
	session._action_received(2,"confirm",{"proposal_id":proposal.proposal_id,"world_revision":proposal.world_revision})
	_g()
	check(session.store.snapshot()==saved,"duplicate confirmation and repeat G cannot issue another result or transaction")
	session._guest_left(2)
	await physics_frame

func _to_service() -> void:
	await _place(Vector3(19.7,7.1,3.5))
	if not await _ability("charge",Bridge.RELAY): return
	if not await _ability("takeover",Bridge.SERVICE_CONTROL): return
	for unused in range(160):
		await _steps(1,.05)
		if not _healthy(): return
		if session.shared_access.module.status().mode=="service_span": break
	check(session.shared_access.module.status().locked and session.shared_access.module.status().mode=="service_span","real motor retracts the pin, moves eight metres and relocks service end")
	var service_inspection: Vector3 = _inspection_anchor("service_span")
	await _place(Vector3(service_inspection.x,service_inspection.y,session.shared_access.module.entity_position(Bridge.PUBLIC_CONTROL).z))
	check(session.story.nearest(session.players[1].global_position)==Bridge.SERVICE_CONTROL,"locked service bridge remains the G choice even when pilot is closer to the public controller")
	await _place(service_inspection)
	check(session.shared_access.choice_confirmation(1,"service_span").ok,"new service route is genuinely inspectable with both bypasses clear")

func _historical_choice_and_branch() -> void:
	phase = "current_bridge_vs_historical_agreement_and_branch_dedup"
	await _to_service()
	if not _healthy(): return
	check(session._save_environment(),"later physical bridge movement is durably saved")
	check(session.story.state.choices.get(Shared.OBJECTIVE)=="public_span","later operational movement does not rewrite the historical first arrangement")
	var before_record: Dictionary = session.store.snapshot()
	session._refresh_interface()
	check(session.story.interaction_label(Bridge.SERVICE_CONTROL)=="查看通路记录" and "查看通路记录" in session.interface.explore_button.text,"completed bridge uses a record-view interaction instead of inviting another final choice")
	_g()
	var record_text: String = session.interface.message.text
	check("首次" in record_text and "住区" in record_text and "当前" in record_text and "巡检" in record_text and session.store.snapshot()==before_record,"actual repeated G distinguishes historical public agreement from current service position without writing or awarding",{"message":record_text})
	await _switch("before_access")
	check(Shared.OBJECTIVE not in session.story.state.completed and session.shared_access.module.status().mode=="public_span" and session.store.snapshot().personal.discoveries.count(Shared.DISCOVERY)==1,"prior branch restores its real initial bridge and unfinished agreement while retaining personal collection")
	await _to_service()
	if not _healthy(): return
	check(session.story.nearest(session.players[1].global_position)==Bridge.SERVICE_CONTROL,"native G selects the other live controller in the prior branch")
	_g()
	check(session.consensus.current_proposal().is_empty() and session.story.state.choices.get(Shared.OBJECTIVE)=="service_span" and session.story.state.completed.size()==34,"single player can explicitly finish a different physical arrangement on its own branch")
	check(session.store.snapshot().personal.discoveries.count(Shared.DISCOVERY)==1,"second branch cannot duplicate the same personal discovery")
	await _switch("main")
	check(session.story.state.choices.get(Shared.OBJECTIVE)=="public_span" and session.shared_access.module.status().mode=="service_span","main restores its own historical public agreement and separately saved current service position")
	var disk = Store.new(session.store.root_path)
	check(disk.load_profile().ok and _same(disk.snapshot(),session.store.snapshot()),"independent Store reread restores the exact final world, branch and personal results")

func _finish(code: int) -> void:
	if done: return
	done=true
	if is_instance_valid(session):
		session.active=false
		session.network.close()
		session.free()
	if not error_logger.errors.is_empty(): code=1
	print("DISTRIBUTION_ACTION_INTEGRATION checks=%d failures=%d profile=%s" % [checks.size(),failures.size(),profile])
	print("DISTRIBUTION_ACTION_INTEGRATION_RESULT "+JSON.stringify({"passed":code==0,"checks":checks,"failures":failures,"engine_errors":error_logger.errors,"limits":["Previous 27 goals and starting pilot placements are declared fixtures; not an entire campaign playthrough.","Two local physical participants exercise real consensus, not ENet or two-PC cooperation.","Actual MAIN, Store and physical mechanisms; no graphics, human pacing, fun or performance acceptance."]}))
	OS.remove_logger(error_logger)
	quit(code)
