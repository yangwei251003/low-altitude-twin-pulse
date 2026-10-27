extends "res://scripts/v3/candidates/canal_playable/probe_workbench_playable.gd"
## Fresh real capability/work path, retained-space candidate. No MAIN travel,
## viewport compositing, seeded receipts, service consumption or scene reload.
const Owner = preload("res://scripts/v3/candidates/canal_retained_site/retained_site.gd")
const Measured = preload("res://scripts/v3/candidates/canal_retained_site/measured_playable.gd")
const Repository = preload("res://scripts/v3/candidates/canal_checkpoint/checkpoint_repository.gd")
const INNER_SECONDS := 240.0
var site: Owner
var other: SubViewport
var other_body: RigidBody3D
var snapshots: Array[Dictionary] = []
var identities: Dictionary = {}
var qa_profile := ""
var started_usec := 0
var work_background_done := false
var carry_background_done := false
var waiting_frames := 0
var serial4_checked := false

func _run() -> void:
	started_usec = Time.get_ticks_usec()
	create_timer(INNER_SECONDS).timeout.connect(func():
		if not finished:
			_check(false,"bounded retained-site wall timeout",INNER_SECONDS)
			_finish())
	qa_profile = "user://qa_v3/canal_retained_"+str(Time.get_ticks_usec())
	if not _check(not DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(qa_profile)),"fresh isolated QA profile"): _finish(); return
	play = Measured.new()
	play.name = "OriginalCanalPlayableMeasured"
	play.persistence_enabled = true
	play.profile_path = qa_profile
	site = Owner.new()
	root.add_child(site)
	var mounted: Dictionary = site.mount(play)
	if not _check(mounted.ok,"candidate is born inside its permanent World3D",mounted): _finish(); return
	play.inputs.test_enabled = true
	play.inputs.test_frame = {"axes":{},"held":["brake"]}
	_make_other_space()
	for i in 2700:
		if not await _frame(): return
		if play.boot_ready: break
	if not _check(play.boot_ready and is_instance_valid(play.workbench),"fresh physical bootstrap reaches WAIT with original workbench",play.bootstrap.report()): _finish(); return
	identities = site.identity().bodies.duplicate(true)
	_record("fresh_wait")
	if not await _fly_to(Vector3(2.5,3,8.5)): return
	if not await _select_target(play.Workbench.POWER_ID): return
	await _key(KEY_6)
	await _key(KEY_F)
	if not _check(play.last_action.get("ok",false) and play.workbench.report().powered,"actual player capability powers original workbench",play.last_action): _finish(); return
	for i in 30:
		if not await _frame(): return
	if not await _select_target(Runtime.CASSETTES[1]): return
	await _key(KEY_5)
	await _key(KEY_X)
	if not _check(play.last_action.get("ok",false) and play.context.rules.status().temperatures_c[Runtime.CASSETTES[1]]<=45.0,"actual thermal ability prepares the original WORK cartridge",play.last_action): _finish(); return
	if not await _fly_to(Vector3(8.8,3.2,18)): return
	if not await _select_target(play.CARRIER_ID): return
	await _key(KEY_0)
	await _key(KEY_F)
	if not _check(play.last_action.get("ok",false) and play.executor_ready,"one real takeover leaves one work order",play.last_action): _finish(); return
	play.inputs.test_frame = {"axes":{},"held":["brake"]}
	play.measurement_phase = "visible_active"
	# No scheduled outcome writes: choose transition times from actual motion.
	for i in 10800:
		if not await _frame(): return
		var work: Dictionary = play.workbench.report()
		var transport: Dictionary = play.executor.report()
		if not serial4_checked and play.serial4_handoff.get("travel_started",false): _check_serial4_handoff()
		if not work_background_done and work.phase=="scan_out" and float(work.scan_distance_m)>.01:
			if not await _background_interval("scan",120): return
			work_background_done = true
		if not carry_background_done and transport.phase=="travel" and not play.context.carrier.cargo_items.is_empty():
			if not await _background_interval("carried_travel",300): return
			carry_background_done = true
		var state: Dictionary = play.context.rules.snapshot()
		if work.phase=="departed" and transport.phase=="idle" and state.pending_action.is_empty(): waiting_frames+=1
		else: waiting_frames=0
		if work_background_done and carry_background_done and waiting_frames>=30: break
	if not _check(work_background_done and carry_background_done and waiting_frames>=30,"both live phases and actual post-work safe idle reached",{"scan":work_background_done,"carry":carry_background_done,"idle_frames":waiting_frames,"executor":play.executor.report(),"workbench":play.workbench.report()}): _finish(); return
	if not serial4_checked: _check_serial4_handoff()
	var result: Dictionary = play.context.rules.snapshot()
	_check(play.context.rules.validate_snapshot(result).ok,"original complete conservation validator accepts final state")
	_check(result.jobs_completed==1 and result.service_credit==1 and result.services_consumed==0 and play.workbench.report().receipt_count==1,"exactly one original physical work and one unspent credit")
	_check(result.thermal_ledger.ability_removed==25000000 and result.thermal_ledger.work_added==Runtime.WORK_HEAT_MJ,"thermal action and real work cost occur exactly once",result.thermal_ledger)
	_check(site.identity().bodies==identities,"all original physical actors retain instance, RID and space through both returns")
	_check(play.player.health==100 and play.context.carrier.health==100 and play.workbench.beneficiary.health==100,"no hidden damage masking",{"player":play.player.health,"carrier":play.context.carrier.health,"beneficiary":play.workbench.beneficiary.health})
	# Preserve normal full-rate hover; measure post-completion rather than
	# pretending an airborne vehicle can be frozen or integrated at 1 Hz.
	play.measurement_phase = "background_postwork_hover"
	var switched: Dictionary = site.set_foreground(false)
	_check(switched.ok,"post-work background preserves all identities",switched)
	for i in 300:
		if not await _frame(): return
	_check(site.set_foreground(true).ok,"post-work return does not rebuild the scene")
	play.measurement_phase = "visible_postwork_hover"
	for i in 180:
		if not await _frame(): return
	# A single genuine save, no F9/service replay. Relocate by the same real
	# flight helper so the player is away from active transport support.
	if not await _fly_to(Vector3(2.5,3,8.5)): return
	var request: Dictionary = play.request_save_checkpoint()
	if not _check(request.ok,"original candidate requests completed safe-point save",request): _finish(); return
	for i in 1250:
		if not await _frame(): return
		if play.save_generation==1 or not play._save_requested: break
	var disk: Dictionary = Repository.new(qa_profile).read()
	_check(play.save_generation==1 and disk.get("ok",false) and not disk.get("empty",true),"actual original Repository publishes one safe-point generation",{"save":play.last_save_result,"generation":disk.get("generation")})
	if disk.get("ok",false) and not disk.get("empty",true):
		_check(disk.envelope.site.rules.jobs_completed==1 and disk.envelope.site.rules.service_credit==1 and disk.envelope.site.rules.services_consumed==0,"saved background result preserves sole unspent credit")
	_record("final_saved")
	_finish()

func _background_interval(label: String, frames: int) -> bool:
	var before: Dictionary = _record(label+"_before")
	var joint: PinJoint3D
	var joint_id := 0
	var joint_rid := 0
	if label=="carried_travel":
		var items: Dictionary = play.context.carrier.cargo_items
		var item: Dictionary = items[items.keys()[0]]
		joint = item.joint
		joint_id = joint.get_instance_id()
		joint_rid = joint.get_rid().get_id()
		_check(play.context.rules.snapshot().pending_action.get("kind")=="move" and joint.get_node_or_null(joint.node_a)==play.context.carrier and joint.get_node_or_null(joint.node_b)==item.body,"background starts with actual carrying move and bound PinJoint")
	var alternate_start: Vector3 = other_body.global_position
	var moved: Dictionary = site.set_foreground(false)
	other.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	play.measurement_phase = "background_"+label
	if not _check(moved.ok,"visibility-only transition keeps body and joint identities: "+label,moved): _finish(); return false
	if label=="carried_travel":
		_check(is_instance_valid(joint) and joint.get_instance_id()==joint_id and joint.get_rid().get_id()==joint_rid,"carrying joint unchanged synchronously across background entry")
	for i in frames:
		if not await _frame(): return false
		if i==0 and label=="carried_travel":
			_check(is_instance_valid(joint) and joint.get_instance_id()==joint_id and joint.get_rid().get_id()==joint_rid,"same live carrying joint survives the first background physics tick")
	var after: Dictionary = _record(label+"_background_end")
	_check(other_body.global_position.distance_to(alternate_start)>.05,"independent other World3D really integrates while I2 is not rendered")
	_check(after.world_clock>before.world_clock and after.host_ticks>before.host_ticks,"normal host chain continues in background: "+label)
	_check(after.bodies==before.bodies,"background does not recreate any registered physical actor: "+label)
	_check(play.context.rules.validate_snapshot(after.rules).ok,"real background state retains original conservation validation: "+label)
	if label=="scan":
		_check(float(after.workbench.scan_distance_m)>float(before.workbench.scan_distance_m) or int(after.workbench.receipt_count)>int(before.workbench.receipt_count),"actual scan advances without visibility",{"before":before.workbench,"after":after.workbench})
	else:
		_check(Vector3(after.carrier_position[0],after.carrier_position[1],after.carrier_position[2]).distance_to(Vector3(before.carrier_position[0],before.carrier_position[1],before.carrier_position[2]))>.2,"actual carried flight moves in background")
	var returned: Dictionary = site.set_foreground(true)
	other.render_target_update_mode = SubViewport.UPDATE_DISABLED
	play.measurement_phase = "visible_active"
	_check(returned.ok,"return preserves current scene instead of restoring an older checkpoint: "+label,returned)
	return true

func _make_other_space() -> void:
	other = SubViewport.new()
	other.size = Vector2i(2,2)
	other.world_3d = World3D.new()
	other.render_target_update_mode = SubViewport.UPDATE_DISABLED
	root.add_child(other)
	other_body = RigidBody3D.new()
	other_body.name = "OtherRegionPhysicsFixture"
	other_body.gravity_scale = 0
	other_body.linear_damp_mode = RigidBody3D.DAMP_MODE_REPLACE
	other_body.linear_damp = 0
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3.ONE
	shape.shape = box
	other_body.add_child(shape)
	other_body.position = Vector3(14.75,2.2,23)
	other.add_child(other_body)
	other_body.linear_velocity = Vector3(.25,0,0)
	_check(other.world_3d.space!=site.space_rid(),"the other active region fixture is in a distinct real physics space")

func _record(label: String) -> Dictionary:
	var identity: Dictionary = site.identity()
	var row: Dictionary = {"label":label,"frame":Engine.get_physics_frames(),"host_ticks":play.measured_ticks,
		"world_clock":play.world.clock_seconds,"space":identity.space,"bodies":identity.bodies,
		"joints":identity.joints,"rules":play.context.rules.snapshot(),"custody":play.context.custody.report(),
		"workbench":play.workbench.report(),"executor":play.executor.report(),
		"carrier_position":_vec(play.context.carrier.global_position),"player_position":_vec(play.player.global_position)}
	snapshots.append(row)
	return row

func _key(code: int) -> void:
	# Invoke the unchanged scene input handler with an actual event. This tests
	# its abilities, not OS keyboard delivery or SubViewport input forwarding.
	if not _check(site.foreground,"test input is only issued in foreground"): _finish(); return
	var event := InputEventKey.new()
	event.physical_keycode = code
	event.pressed = true
	play._unhandled_input(event)
	await process_frame

func _frame() -> bool:
	await physics_frame
	if finished: return false
	if not play.fatal.is_empty() or not logger.errors.is_empty():
		if play.boot_ready and is_instance_valid(play.workbench): _record("fatal_observed_by_probe")
		_check(false,"unchanged playable remains healthy",{"fatal":play.fatal,"errors":logger.errors})
		_finish(); return false
	return true

func _capture(_filename: String) -> void:
	pass # Headless: no frame_post_draw await and no screenshot claim.

func _check_serial4_handoff() -> void:
	serial4_checked = true
	var handoff: Dictionary = play.diagnostics().serial4_handoff
	if not _check(not handoff.is_empty(),"serial4 post-place handoff was actually observed",handoff): return
	var action: Dictionary = handoff.action
	_check(action.get("kind")=="move" and action.get("serial")==4 and action.get("source")=="south_0" and action.get("destination")=="north_work" and action.get("cassette_id","")=="","serial4 is the real empty-carrier route after S0 placement",action)
	_check(handoff.observed_live_hold and handoff.travel_started and int(handoff.travel_frame)>int(handoff.first_frame),"real source hold precedes serial4 route travel",handoff)
	_check(handoff.same_action_and_pending and handoff.same_receipts and int(handoff.initial_receipts)==2,"source recovery keeps the same pending identity and emits no extra receipt",handoff)
	_check(handoff.same_ownership and handoff.ownership[Runtime.CASSETTES[0]]=={"phase":"docked","berth":"south_0","carrier":""} and handoff.ownership[Runtime.CASSETTES[1]]=={"phase":"docked","berth":"north_work","carrier":""},"source recovery preserves both real docked cargo owners",handoff.ownership)
	# This is a continuity bound for the recorded 60 Hz recovery, not a relaxed
	# physical permission. No requirement that the changed wind phase repeats
	# the first failed run's initial >0.20 m error, and no forced displacement.
	_check(handoff.consecutive_frames and int(handoff.samples)>1 and float(handoff.max_step_m)<.10,"recorded handoff is continuous normal-frame physical movement",handoff)
	_check(handoff.travel_started and float(handoff.get("final_distance_m",INF))<.18 and float(handoff.get("final_speed_mps",INF))<.18,"serial4 starts only after original Pilot position and speed settling bounds",handoff)

func _finish() -> void:
	if finished: return
	finished = true
	_check(logger.errors.is_empty(),"zero engine errors",logger.errors)
	var result: Dictionary = {"checks":checks,"failures":failures,"engine_errors":logger.errors,
		"elapsed_seconds":float(Time.get_ticks_usec()-started_usec)/1000000.0,"inner_timeout_seconds":INNER_SECONDS,
		"profile":qa_profile,"snapshots":snapshots,"transitions":site.transitions if is_instance_valid(site) else [],
		"measurements":play.measurements() if is_instance_valid(play) else {},
		"transport_diagnostics":play.diagnostics() if is_instance_valid(play) else {},
		"scope":"Fresh candidate in permanent SubViewport/World3D; real original host chain and injected original input-handler events. Player stays in I2 under scripted brake; other space is a minimal real rigid-body fixture, not I1/MAIN travel. No rendering/FPS/LAN/full service UI or arbitrary-flight save evidence."}
	if not output.is_empty():
		DirAccess.make_dir_recursive_absolute(output)
		var file := FileAccess.open(output.path_join("result.json"),FileAccess.WRITE)
		if file!=null: file.store_string(JSON.stringify(result,"  ",true,true))
	print("V3_CANAL_RETAINED_SITE "+JSON.stringify({"checks":checks,"failures":failures,"engine_errors":logger.errors,"elapsed_seconds":result.elapsed_seconds,"snapshot_count":snapshots.size()}))
	if is_instance_valid(site):
		site.close()
		site.free()
	if is_instance_valid(other): other.free()
	quit(0 if failures.is_empty() else 1)
