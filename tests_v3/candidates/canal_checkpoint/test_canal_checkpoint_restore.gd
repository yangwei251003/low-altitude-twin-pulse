extends "res://tests_v3/candidates/canal_checkpoint/test_canal_checkpoint.gd"
## One real exchange/work/departure capture, then isolated fresh reconstruction.
## No substituted work receipts, cargo teleport during play, Store or reward.
const Restore = preload("res://scripts/v3/candidates/canal_checkpoint/canal_checkpoint_restore.gd")
const FlightState = preload("res://scripts/v3/candidates/canal_checkpoint/flight_state.gd")
var reconstruction_evidence: Dictionary = {}
var restore_view: SubViewport
var restore_world: Node3D

func _collect_inputs() -> void:
	super._collect_inputs()
	for path: String in ["res://scripts/v3/candidates/canal_checkpoint/canal_checkpoint_restore.gd","res://scripts/v3/candidates/canal_checkpoint/flight_state.gd","res://scripts/v3/candidates/canal_checkpoint/history_state.gd","res://tests_v3/candidates/canal_checkpoint/test_canal_checkpoint_restore.gd"]:
		inputs[path] = FileAccess.get_sha256(path)

func _result() -> Dictionary:
	var result: Dictionary = super._result()
	result.reconstruction = reconstruction_evidence.duplicate(true)
	result.checkpoint_scope = "v3 real safe-point capture and isolated fresh entity reconstruction; no Store or service consumption"
	return result

func _checkpoint_cases() -> void:
	await super._checkpoint_cases()
	if not failures.is_empty(): return
	var saved: Dictionary = checkpoint_evidence.envelope.duplicate(true)
	var parsed: Dictionary = JSON.parse_string(JSON.stringify(saved,"",true,true))
	var expected_rules = Rules.new()
	expected_rules.configure()
	expected_rules.restore(parsed.rules)
	var saved_rules: Dictionary = expected_rules.snapshot()
	var original_rules: Dictionary = context.rules.snapshot()
	var original_children: int = world.get_child_count()
	var script: Script = Restore
	if not _check(script.can_instantiate(),"fresh reconstruction script instantiates before tests"): return
	# Pure invalid states cannot allocate a node or touch the running old world.
	var bad: Dictionary = parsed.duplicate(true)
	bad.version = 2
	var rejected = Restore.new()
	_check(not rejected.prepare(world,bad,world.sample_environment,true).ok and world.get_child_count() == original_children and context.rules.snapshot() == original_rules,"old version rejects before construction without changing old scene")
	bad = parsed.duplicate(true)
	bad.checkpoint.cargos[Rules.CASSETTES[0]].holder = bad.checkpoint.cargos[Rules.CASSETTES[1]].holder
	_check(not Checkpoint.validate(bad).ok,"duplicate holder is rejected by v3 restoration validation")
	bad = parsed.duplicate(true)
	bad.checkpoint.carrier.state.damage.components.rotor_left.maximum = 999
	_check(not Checkpoint.validate(bad).ok,"component capacity cannot be enlarged by saved state")
	bad = parsed.duplicate(true)
	bad.checkpoint.carrier.state.battery = INF
	_check(not Checkpoint.validate(bad).ok,"non-finite saved power rejected")
	var low_epoch: Dictionary = parsed.duplicate(true)
	low_epoch.physics.frame = 1
	_check(Checkpoint.validate(low_epoch).ok,"historical source frames survive a new engine frame epoch without relabeling measurements")
	# Explicit missing-ground negative fixture, never used as playable geometry.
	await _new_restore_world(false)
	var absent = Restore.new()
	var no_support: Dictionary = absent.prepare(restore_world,parsed,world.sample_environment,true)
	_check(not no_support.ok and no_support.code == "restore_berth_geometry" and restore_world.get_child_count() == 0,"missing actual ground refuses fresh berth reconstruction",no_support)
	_free_restore_world()
	# Full production world with a physical obstruction at the saved cargo pose.
	await _new_restore_world(true)
	var obstruction := StaticBody3D.new()
	obstruction.name = "ExplicitRestoreOnlyObstacle"
	obstruction.collision_layer = 1
	obstruction.collision_mask = 0
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(.5,.5,.5)
	collision.shape = shape
	obstruction.add_child(collision)
	restore_world.add_child(obstruction)
	obstruction.global_position = FlightState.transform(parsed.checkpoint.cargos[Rules.CASSETTES[0]].pose).origin
	await physics_frame
	var obstructed = Restore.new()
	var blocked: Dictionary = obstructed.prepare(restore_world,parsed,restore_world.sample_environment,true)
	_check(not blocked.ok and not restore_world.has_node("CanalRestoredCandidateSite") and context.rules.snapshot() == original_rules,"actual new-scene obstacle rejects candidate without deleting or writing old scene",blocked)
	_free_restore_world()
	# This obstruction is beyond all berth preflights. It forces failure AFTER
	# carrier/cargo creation and actual support sampling, testing owned cleanup.
	await _new_restore_world(true)
	var terminal_block := StaticBody3D.new()
	terminal_block.collision_layer = 1
	terminal_block.collision_mask = 0
	terminal_block.add_child(Bootstrap._box(Vector3(.8,.8,.8)))
	restore_world.add_child(terminal_block)
	terminal_block.global_position = Departure.ROUTE[-1]
	await physics_frame
	var partial = Restore.new()
	var began: Dictionary = partial.prepare(restore_world,parsed,restore_world.sample_environment,true)
	_check(began.ok and restore_world.has_node("CanalRestoredCandidateSite"),"late-obstruction fixture actually creates fresh pending candidate",began)
	var failed_late: Dictionary = {}
	if began.ok:
		for i in 120:
			await physics_frame
			var step: Dictionary = partial.tick(DT,true,false)
			if not step.ok:
				failed_late = step
				break
	_check(failed_late.get("code","") == "workbench:beneficiary_initial_obstructed" and not restore_world.has_node("CanalRestoredCandidateSite") and context.rules.snapshot() == original_rules,"late real terminal obstruction frees entire partial candidate and leaves old ledger intact",failed_late)
	reconstruction_evidence.late_failure = failed_late
	partial.discard()
	_free_restore_world()
	await _new_restore_world(true)
	var restorer = Restore.new()
	var denied: Dictionary = restorer.prepare(restore_world,parsed,restore_world.sample_environment,false)
	_check(not denied.ok and not restore_world.has_node("CanalRestoredCandidateSite"),"nonhost cannot construct restored entities")
	var prepared: Dictionary = restorer.prepare(restore_world,parsed,restore_world.sample_environment,true)
	if not _check(prepared.ok and not prepared.ready,"valid real capture creates pending isolated entities, never ready from saved support",prepared):
		_free_restore_world(); return
	var initial: Dictionary = FlightState.capture(restorer._context.carrier,Rules.CARRIER)
	_check(_numeric_equal(initial,parsed.checkpoint.carrier),"fresh carrier retains exact saved pose, velocity, damage, battery, heat and timers before first tick",{"saved":parsed.checkpoint.carrier,"actual":initial})
	var before: Dictionary = restorer._context.carrier.command.duplicate(true)
	var no_host: Dictionary = restorer.tick(DT,false,false)
	_check(not no_host.ok and restorer._context.carrier.command == before,"nonhost tick cannot write the fresh flight command")
	var trace: Array = []
	var ready: Dictionary = {}
	var saw_zero_credit := false
	for i in 900:
		await physics_frame
		restore_world.clock_seconds += DT
		# A short, explicitly paused preparation resets observation; no time skip.
		var pause: bool = i in [4,5,6]
		var state: Dictionary = restorer.tick(DT,true,pause)
		if i < 10 or i % 60 == 0 or state.ready or not state.ok:
			trace.append({"tick":i,"phase":state.phase,"code":state.code,"ready":state.ready,"detail_code":state.detail.get("code","")})
		if pause and restorer._context.custody.docked_snapshot().is_empty(): saw_zero_credit = true
		if not state.ok:
			_check(false,"fresh candidate prepares without module fault",state)
			break
		if state.ready:
			ready = state
			break
	reconstruction_evidence.trace = trace
	_check(saw_zero_credit,"pause did not import old 350ms support credit")
	if not _check(not ready.is_empty(),"actual fresh supports, anchors, PARK tools and device reach same-frame ready",{"trace":trace}):
		restorer.discard(); _free_restore_world(); return
	var candidate: Dictionary = restorer._context
	_check(candidate.rules.snapshot() == saved_rules and candidate.custody.docked_snapshot() == saved.checkpoint.custody,"original captured Rules balance and Custody replay counters preserved exactly")
	_check(restorer._executor.report().receipt_count == 0 and restorer._bench.report().receipt.is_empty() and restorer._bench.report().measurements.is_empty() and _numeric_equal(restorer._bench.report().restored_history,saved.history),"restoration never replays ten transport receipts or fabricates new work measurements")
	_check(candidate.carrier.cargo_items.is_empty() and restorer._bench.beneficiary.cargo_items.is_empty() and candidate.rules.snapshot().pending_action.is_empty(),"restored safe point has no attachment or pending action")
	for id: String in Rules.CASSETTES:
		var holder: String = str(parsed.checkpoint.cargos[id].holder)
		var proof: Dictionary = candidate.custody.support_info(id,holder)
		_check(proof.supported and candidate.custody.report().cargos[id].stable_usec == 350000,"reconstructed cargo has new real 350ms support",proof)
	var preserved: Dictionary = candidate.custody.docked_snapshot()
	var replay: Dictionary = candidate.custody.pickup(Rules.CASSETTES[0],Rules.CARRIER,int(preserved.last_serial),int(preserved.revision))
	_check(not replay.ok and replay.code == "stale_serial" and candidate.custody.docked_snapshot() == preserved,"old physical custody serial remains rejected after reconstruction")
	var final: Dictionary = restorer.adopt(true)
	if not _check(final.ok,"only current physically ready candidate can be adopted",{"code":final.get("code","")}):
		restorer.discard(); _free_restore_world(); return
	_check(not restorer.adopt(true).ok,"duplicate adoption cannot return a second live candidate")
	var site: Node3D = final.site
	restorer.discard()
	_check(is_instance_valid(site),"discard after adoption cannot destroy transferred scene")
	_check(final.context.rules.snapshot().jobs_completed == 1 and final.context.rules.snapshot().services_consumed == saved.rules.services_consumed and final.context.rules.snapshot().service_credit == saved.rules.service_credit and final.context.rules.snapshot().service_serial == saved.rules.service_serial,"one existing result and original service consumption remain unchanged")
	reconstruction_evidence.restored = {"history":final.envelope.history,"rules":final.context.rules.snapshot(),"custody":final.context.custody.docked_snapshot(),"carrier":FlightState.capture(final.context.carrier,Rules.CARRIER),"beneficiary":FlightState.capture(final.workbench.beneficiary,Checkpoint.BENEFICIARY_ID),"cooling":final.cooling.snapshot(),"no_store":true}
	checkpoint_evidence.restore_implemented = true
	checkpoint_evidence.cooling_device_restore_only = false
	_check(context.rules.snapshot() == original_rules and world.get_child_count() == original_children,"entire reconstruction and adoption leave old scene ledger and ownership untouched")
	_free_restore_world()

func _new_restore_world(production: bool) -> void:
	restore_view = SubViewport.new()
	restore_view.own_world_3d = true
	restore_view.world_3d = World3D.new()
	restore_view.render_target_update_mode = SubViewport.UPDATE_DISABLED
	root.add_child(restore_view)
	restore_world = World.new() if production else Node3D.new()
	restore_view.add_child(restore_world)
	if production:
		restore_world.build("I2",{},true)
		_check(restore_world.build_errors.is_empty(),"fresh actual production I2 builds for reconstruction",{"errors":restore_world.build_errors})
		for i in 3: await physics_frame

func _free_restore_world() -> void:
	if is_instance_valid(restore_view): restore_view.free()

func _numeric_equal(a: Variant, b: Variant) -> bool:
	if (a is int or a is float) and (b is int or b is float): return is_finite(float(a)) and is_finite(float(b)) and absf(float(a)-float(b)) <= .000000000001
	if a is Dictionary and b is Dictionary:
		if a.size() != b.size(): return false
		for key: Variant in a:
			if not b.has(key) or not _numeric_equal(a[key],b[key]): return false
		return true
	if a is Array and b is Array:
		if a.size() != b.size(): return false
		for i in a.size():
			if not _numeric_equal(a[i],b[i]): return false
		return true
	return typeof(a) == typeof(b) and a == b
