extends "res://scripts/v3/candidates/canal_playable/probe_playable.gd"
## Scripted real player inputs. Local thermal shortcut plus the actual beneficiary;
## no fake transport/work receipts, no world-state restoration or player healing.

func _run() -> void:
	create_timer(_work_probe_timeout()).timeout.connect(func():
		if not finished:
			_check(false,"bounded interactive work probe timeout")
			_finish())
	play=Scene.instantiate()
	_configure_playable()
	root.add_child(play)
	play.inputs.test_enabled=true
	for i in 2700:
		if not await _frame(): return
		if play.boot_ready: break
	if not _check(play.boot_ready and play.workbench!=null,"real bootstrap and separate occupied workbench exist",play.bootstrap.report()):
		_finish(); return
	_check(play.rack_art.get("ok",false) and play.rack_art.get("triangles",0)==4740 and play.rack_art.get("materials",0)==2,"baked calibration model replaces the original rack visual without a new collider")
	var structure_before: Dictionary=_physical_structure()
	var initial_work: RigidBody3D=play.context.cargos[Runtime.CASSETTES[1]]
	var initial_position: Vector3=initial_work.global_position
	if not await _fly_to(Vector3(2.5,3,8.5)): return
	if not await _select_target(play.Workbench.POWER_ID): return
	await _key(KEY_6)
	await _key(KEY_F)
	if not _check(play.last_action.get("ok",false) and play.workbench.report().powered,"real nearby capability supplies the workbench",play.last_action):
		_finish(); return
	for i in 30:
		if not await _frame(): return
	if not await _select_target(Runtime.CASSETTES[1]): return
	await _key(KEY_5)
	var energy_before: float=play.entities[play.PLAYER_ID].energy
	await _key(KEY_X)
	if not _check(play.last_action.get("ok",false) and play.context.rules.status().temperatures_c[Runtime.CASSETTES[1]]<=45.0,"real player heat ability cools original WORK in place",play.last_action):
		_finish(); return
	_check(float(play.entities[play.PLAYER_ID].energy)<energy_before,"successful thermal capability pays energy")
	_check(play.context.rules.snapshot().thermal_ledger.ability_removed==25000000,"thermal ability removal recorded in conserved millijoules")
	_check(initial_work.global_position.distance_to(initial_position)<.02 and play.context.custody.report().cargos[Runtime.CASSETTES[1]].berth==Runtime.WORK,"original supported cartridge remains at the actual workbench")
	await _capture("01-player-cooled-original-work.png")
	await _rack_capture("04-rack-occupied-close.png")
	# Give the player an unhurried inspection window. The waiting carrier must
	# actively hold its location against real wind without starting logistics.
	var max_wait_distance:=0.0
	for i in 900:
		if not await _frame(): return
		max_wait_distance=maxf(max_wait_distance,play.context.carrier.global_position.distance_to(play.Executor.WAIT_POINT))
	_check(max_wait_distance<.18 and play.context.rules.snapshot().pending_action.is_empty(),"carrier remains at real WAIT while player examines the workbench",{"maximum_distance_m":max_wait_distance,"last_controller":play.waiting_report})
	# Return through the open west approach to make the normal, range-limited
	# takeover request. Never teleport the player to a convenient interaction.
	if not await _fly_to(Vector3(8.8,3.2,18)): return
	if not await _select_target(play.CARRIER_ID): return
	await _key(KEY_0)
	await _key(KEY_F)
	if not _check(play.last_action.get("ok",false) and play.executor_ready,"player leaves one real work order after preparing local shortcut",play.last_action):
		_finish(); return
	if not await _fly_to(Vector3(2.5,3,8.5)): return
	if not await _select_target(play.Workbench.POWER_ID): return
	for i in 24:
		if not await _frame(): return
	var work_view: Dictionary=play.observation.report()
	_check(work_view.occluded and not work_view.faded.is_empty(),"real camera rays reveal the nearby work operation",work_view)
	await _capture("02-physical-calibration-underway.png")
	for i in 4800:
		if not await _frame(): return
		if play.workbench.report().phase=="departed": break
	var work: Dictionary=play.workbench.report()
	var state: Dictionary=play.context.rules.snapshot()
	_check(work.phase=="departed" and work.departure.arrived,"actual beneficiary leaves rack and reaches the short canal route",work)
	_check(work.receipt_count==1 and work.receipt.receipt.serial==1 and work.receipt.receipt.cassette_id==Runtime.CASSETTES[1],"in-place solution completed work first using original hot cartridge",work.receipt)
	_check(state.jobs_completed==1 and state.service_credit==1 and state.services_consumed==0,"one retained service credit; no simulated player repair")
	_check(state.thermal_ledger.work_added==Runtime.WORK_HEAT_MJ,"only actual completed work adds its thermal cost",state.thermal_ledger)
	_check(play.workbench.beneficiary.health==100 and play.workbench.beneficiary.collision_count==0 and play.player.health==100,"player and beneficiary remain healthy without damage masking")
	_check(play.beneficiary_label.text=="巡检恢复","world label changes after actual departure")
	_check(play.cooling_transfer_delay_count>0,"stable physical drop waits for its original place receipt before cooling connection",play.cooling_transfer_delay_count)
	_check(_physical_structure()==structure_before,"camera cutaway preserves structural bodies, shapes, layers and masks")
	await _capture("03-beneficiary-departed.png")
	await _rack_capture("05-rack-empty-close.png")
	evidence={"scope":"scripted actual player movement and Godot key events; local thermal shortcut, real work and real beneficiary flight; no physical keyboard/human/MAIN/Store/LAN/service-consumption validation", "workbench":work,"executor":play.executor.report(),"rules":state,"player_position":_vec(play.player.global_position),"beneficiary_position":_vec(play.workbench.beneficiary.global_position),"maximum_wait_distance_m":max_wait_distance,"cooling_transfer_delay_frames":play.cooling_transfer_delay_count,"work_view":work_view}
	_finish()

func _work_probe_timeout() -> float:
	return 170.0

func _rack_capture(filename: String) -> void:
	# Explicit QA camera only. Real occupied/empty rack, lighting, physics and
	# beneficiary are untouched; no new playable camera or flight is claimed.
	if output.is_empty(): return
	play.set_process(false)
	var old: Transform3D=play.camera.global_transform
	var size: float=play.camera.size
	var focus: Vector3=play.workbench.rack.global_position+Vector3(0,.7,0)
	play.camera.size=7.0
	play.camera.global_position=focus+Vector3(32,39,32)
	play.camera.look_at(focus,Vector3.UP)
	await _capture(filename)
	play.camera.global_transform=old
	play.camera.size=size
	play.set_process(true)

func _physical_structure() -> Dictionary:
	var result: Dictionary={}
	for structure in play.world.find_children("*","CollisionObject3D",true,false):
		if not structure is StaticBody3D and not structure is AnimatableBody3D: continue
		var shapes: Array=[]
		for owner in structure.get_shape_owners():
			for i in structure.shape_owner_get_shape_count(owner):
				shapes.append([structure.shape_owner_get_shape(owner,i).get_rid(),structure.is_shape_owner_disabled(owner)])
		result[structure.get_instance_id()]=[structure.get_rid(),structure.collision_layer,structure.collision_mask,shapes]
	return result
