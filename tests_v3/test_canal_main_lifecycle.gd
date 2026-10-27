extends SceneTree
## Actual MAIN factory/save/pause/region ownership check over a fresh QA Store.
## Direct QA region loads are lifecycle fixtures, not unlock or flight evidence.
const MAIN = preload("res://scenes/v3/main.tscn")
const Store = preload("res://scripts/v3/core/twin_world_store.gd")
const Canal = preload("res://scripts/v3/gameplay/twin_canal_session.gd")
const Wait = Canal.WaitCheckpoint
class ErrorLogger extends Logger:
	var guard := Mutex.new()
	var errors: Array = []
	func _log_error(function: String,file: String,line: int,code: String,rationale: String,_notify: bool,kind: int,_trace: Array[ScriptBacktrace]) -> void:
		if kind==Logger.ERROR_TYPE_WARNING: return
		guard.lock()
		errors.append({"function":function,"file":file,"line":line,"code":code,"rationale":rationale})
		guard.unlock()
class RestoreSupportObserver extends Node:
	var sample: Callable
	var previous_frame := -1
	var samples := 0
	var streak := 0
	var max_streak := 0
	var frame_delta_histogram: Dictionary = {}
	var first_resets: Array = []
	var best: Dictionary = {}
	var last: Dictionary = {}
	func _physics_process(_delta: float) -> void:
		if not sample.is_valid() or samples>=120: return
		var row: Dictionary = sample.call()
		var frame: int = Engine.get_physics_frames()
		var gap: int = frame-previous_frame if previous_frame>=0 else 1
		frame_delta_histogram[str(gap)] = int(frame_delta_histogram.get(str(gap),0))+1
		var supported: bool = row.hot.get("supported",false) and row.beneficiary.get("supported",false) and row.joint_integrity
		streak = streak+1 if supported and gap==1 else 0
		row["physics_frame"] = frame
		row["frame_delta"] = gap
		row["observed_consecutive_usec"] = int(round(float(streak)*1000000.0/float(Engine.physics_ticks_per_second)))
		if streak>max_streak:
			max_streak = streak
			best = row.duplicate(true)
		if (not supported or gap!=1) and first_resets.size()<8: first_resets.append(row.duplicate(true))
		last = row
		previous_frame = frame
		samples += 1
var logger := ErrorLogger.new()
var restore_observer: RestoreSupportObserver
var session: Node
var profile := ""
var output := ""
var finished := false
var checks: Array = []
var phases: Dictionary = {}
var save_callbacks: Array = []
var saved_envelope: Dictionary = {}
var prepared_error := ""

func _initialize() -> void:
	OS.add_logger(logger)
	_run.call_deferred()

func _run() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--qa-profile="): profile = arg.trim_prefix("--qa-profile=")
		if arg.begins_with("--output="): output = arg.trim_prefix("--output=")
	if not profile.begins_with("qa_canal_main_lifecycle_") or profile!=profile.validate_filename() or not output.begins_with("res://artifacts/v3/canal-main-lifecycle-") or ".." in output or DirAccess.dir_exists_absolute(output) or DirAccess.dir_exists_absolute("user://profiles_v3/"+profile):
		quit(2)
		return
	DirAccess.make_dir_recursive_absolute(output)
	create_timer(85).timeout.connect(func():
		if not finished:
			_check(false,"85 second actual MAIN lifecycle bound",_diagnostics())
			_finish())
	if not _new_main():
		_finish()
		return
	_check(session.canal_runtime_enabled and session.canal==null and session.region_id=="I1","ordinary MAIN defaults to Canal enabled while I1 owns no adapter")
	var first_player: int = session.players[1].get_instance_id()
	if not _load("I2","original factory prepares/adopts first live I2"):
		_finish()
		return
	phases.initial = _diagnostics()
	if not _check(session.canal!=null and is_instance_valid(session.canal.module) and session.canal.module.get_parent()==session.world,"Session factory owns one actual current-world Assembly",_diagnostics()):
		_finish()
		return
	var original_adapter: RefCounted = session.canal
	var original_adapter_id: int = original_adapter.get_instance_id()
	var original_module: WeakRef = weakref(original_adapter.module)
	await _frame()
	await _frame()
	if finished: return
	var early: Dictionary = original_adapter.context()
	if not _check(not early.is_empty() and early.carrier.freeze and not original_adapter.ready,"actual bootstrap starts with its own intentionally frozen carrier",_diagnostics()):
		_finish()
		return
	if not await _pause_cycle("bootstrap",8):
		_finish()
		return
	if not await _wait_ready(2700,"first physical bootstrap reaches actual ready WAIT"):
		_finish()
		return
	if not _targets("first I2") or not await _pause_cycle("ready_wait",66):
		_finish()
		return
	var context: Dictionary = session.canal.context()
	_check(_bodies().size()==4 and _joints().size()==1 and context.carrier.cargo_items.size()==1,"ready site has four original rigid bodies and the actual loaded PinJoint",{"bodies":_bodies(),"joints":_joints()})
	phases.ready = _diagnostics()
	# Autosave remains enabled. Wait for its existing gate rather than replacing
	# the Session clock, save operation, adapter tick, authority or Store.
	for unused in 20:
		if not session.environment_save_gate.pending(): break
		await _frame()
		if finished: return
	var generation_before: int = session.store.snapshot().generation
	var requested: Dictionary = session.request_environment_save(func(result: Dictionary): save_callbacks.append(result.duplicate(true)))
	if not _check(requested.get("ok",false) and not requested.get("completed",true) and save_callbacks.is_empty(),"real Session save accepts asynchronously, before its completion callback",requested):
		_finish()
		return
	for unused in 20:
		await _frame()
		if finished: return
		if not save_callbacks.is_empty(): break
	var saved: bool = save_callbacks.size()==1 and save_callbacks[0].get("ok",false) and save_callbacks[0].get("completed",false) and save_callbacks[0].get("code")=="saved" and not session.environment_save_gate.pending()
	if not _check(saved,"original SaveGate reports exactly one actual successful save callback",{"callbacks":save_callbacks,"gate":session.environment_save_gate.last_result,"diagnostics":_diagnostics()}):
		_finish()
		return
	var disk: Dictionary = _disk()
	saved_envelope = disk.get("world",{}).get("environment",{}).get("I2_canal",{}).duplicate(true)
	var valid: Dictionary = _validate_saved(saved_envelope)
	if not _check(not disk.is_empty() and int(disk.generation)>=generation_before and int(disk.generation)==int(session.store.snapshot().generation) and valid.get("ok",false) and session.world_cache.world.environment.I2_canal==saved_envelope,"new original Store reader sees the exact published physical envelope validated by its actual kind",{"generation_before":generation_before,"disk_generation":disk.get("generation"),"Store_generation":session.store.snapshot().get("generation"),"validation":valid,"readback_comparison":_readback_comparison(session.world_cache.world.environment.I2_canal,saved_envelope)}):
		_finish()
		return
	var old_world: Node3D = session.world
	if not _load("I1","I1 loads only after the original SaveGate completes"):
		_finish()
		return
	var cleared: bool = session.canal==null and original_adapter.module==null and not original_adapter.ready and original_module.get_ref()==null
	var removed: Dictionary = {}
	for id: String in Canal.IDS:
		removed[id] = not old_world.objects.has(id) and not old_world.definitions.has(id) and not old_world.initial_transforms.has(id) and not session.world.objects.has(id) and not session.entities.has(id)
		cleared = cleared and removed[id]
	_check(cleared and session.players[1].get_instance_id()==first_player and session.active and session.owns_world,"normal region adoption clears the old adapter, module and all six owned registries while retaining the player",{"removed":removed,"old_adapter":original_adapter.status(),"diagnostics":_diagnostics()})
	await _frame()
	if finished: return
	var after_leave: Dictionary = _disk()
	_check(after_leave.get("world",{}).get("environment",{}).get("I2_canal",{})==saved_envelope,"leaving I2 retains the saved envelope in the same original Store",_readback_comparison(after_leave.get("world",{}).get("environment",{}).get("I2_canal",{}),saved_envelope))
	phases.left_i2 = _diagnostics()
	# New MAIN reads the same QA directory from disk. Its ordinary startup region
	# remains I1; no forged world.region_id or task/unlock transaction is needed.
	session.network.close()
	session.free()
	session = null
	await process_frame
	await physics_frame
	await process_frame
	if finished: return
	if not _new_main():
		_finish()
		return
	if not _check(session.canal_runtime_enabled and session.canal==null and session.region_id=="I1" and session.world_cache.world.environment.I2_canal==saved_envelope,"fresh MAIN reads that same disk envelope with Canal enabled and no I1 adapter",{"runtime_enabled":session.canal_runtime_enabled,"I1_adapter_null":session.canal==null,"region":session.region_id,"readback_comparison":_readback_comparison(session.world_cache.world.environment.I2_canal,saved_envelope)}):
		_finish()
		return
	if not _load("I2","fresh MAIN factory prepares saved I2 without a hand-created adapter"):
		_finish()
		return
	phases.restore_prepared = _diagnostics()
	if not _check(session.canal!=null and session.canal.get_instance_id()!=original_adapter_id and session.canal.status().assembly.restored_mode and session.canal.status().assembly.restore_pending,"factory creates a new owner and requires actual saved-site restore readiness",_diagnostics()):
		_finish()
		return
	if not await _wait_ready(900,"saved I2 reaches current physical support and actual ready adoption"):
		_finish()
		return
	_targets("restored I2")
	var detail: Dictionary = session.canal.module.status(true)
	var wait_kind: bool = saved_envelope.get("kind")==Wait.KIND
	var original_restore: bool = int(detail.restore.get("support_observed_usec",0))>=350000 if wait_kind else int(detail.restore.get("new_contact_credit",-1))==0
	_check(detail.restored_mode and not detail.restore_pending and detail.restore.get("phase")=="adopted" and original_restore and detail.bootstrap.get("phase")=="not_started_saved_path","actual saved-kind restorer adopts the original physical joint without a new bootstrap or synthetic contact credit",{"kind":saved_envelope.get("kind"),"actual":detail})
	if not await _restored_support():
		_finish()
		return
	detail = session.canal.module.status(true)
	var restored_context: Dictionary = session.canal.context()
	var rules: Dictionary = restored_context.rules.snapshot()
	_check(int(detail.device_serial)==int(saved_envelope.device_serial) and int(detail.rule_usec)>=int(saved_envelope.rule_usec) and not detail.ordered and restored_context.carrier.cargo_items.size()==1 and _bodies().size()==4 and _joints().size()==1,"saved device sequence, rule time and actual four-body/one-joint graph survive reentry",{"saved_rule_usec":saved_envelope.rule_usec,"actual":detail,"bodies":_bodies(),"joints":_joints()})
	_check(int(rules.jobs_completed)==0 and int(rules.service_credit)==0 and int(rules.services_consumed)==0 and session.story.state.get("completed",[]).is_empty() and session.store.snapshot().personal.discoveries.is_empty(),"lifecycle fixture creates no work, service, task completion or discovery",rules)
	phases.restored = _diagnostics()
	_finish()

static func _readback_comparison(actual: Dictionary, expected: Dictionary) -> Dictionary:
	# Both operands already crossed the original Store's actual JSON readback.
	# Compare those exact values; another serialization would be a new boundary.
	var fields: Dictionary = {}
	var keys: Array = actual.keys()
	for key in expected:
		if key not in keys: keys.append(key)
	for key in keys:
		fields[str(key)] = {"actual_present":actual.has(key),"expected_present":expected.has(key),"equal":actual.has(key) and expected.has(key) and actual[key]==expected[key]}
	return {"exact_equal":actual==expected,"fields":fields,"actual":actual,"expected":expected}

static func _validate_saved(envelope: Dictionary) -> Dictionary:
	match str(envelope.get("kind","")):
		Canal.StartupCheckpoint.KIND: return Canal.StartupCheckpoint.validate(envelope)
		Canal.ProgressCheckpoint.KIND: return Canal.ProgressCheckpoint.validate(envelope)
		Canal.ScanCheckpoint.KIND: return Canal.ScanCheckpoint.validate(envelope)
		Wait.KIND: return Wait.validate(envelope)
	return {"ok":false,"code":"unknown_actual_checkpoint_kind"}

func _restored_support() -> bool:
	# A startup/progress rebuild grants zero new contact credit. Independently
	# observe ordinary post-adoption contacts for 350ms; never inject that credit
	# into the restorer, pilot, custody or original service ledger.
	# Micro225930 proved the former physics+process observer skipped 8 actual
	# ticks per render. This ordinary Node observes every original physics tick;
	# it never advances simulation or credits unobserved frames.
	restore_observer = RestoreSupportObserver.new()
	restore_observer.sample = _sample_restored_support
	root.add_child(restore_observer)
	for unused in 120:
		await process_frame
		if finished: return false
		if restore_observer.max_streak>=21 or restore_observer.samples>=120: break
	var proof: Dictionary = {"best":restore_observer.best,"last":restore_observer.last,"frame_delta_histogram":restore_observer.frame_delta_histogram,"max_consecutive_usec":int(round(float(restore_observer.max_streak)*1000000.0/float(Engine.physics_ticks_per_second))),"first_resets":restore_observer.first_resets,"samples":restore_observer.samples}
	var supported: bool = int(proof.max_consecutive_usec)>=350000 and restore_observer.frame_delta_histogram.keys()==["1"]
	restore_observer.free()
	restore_observer = null
	return _check(supported,"fresh MAIN actual contacts and original joint remain supported for 350ms without new service credit",proof)

func _sample_restored_support() -> Dictionary:
	var context: Dictionary = session.canal.context()
	var hot: Dictionary = context.custody.support_info(Wait.Rules.CASSETTES[1],Wait.Rules.WORK)
	var beneficiary: Dictionary = Wait.Bench.Departure.support_proof(context.workbench.beneficiary,context.workbench.rack)
	var intact: bool = context.custody._integrity(Wait.Rules.CASSETTES[0]).is_empty() and context.custody._integrity(Wait.Rules.CASSETTES[1]).is_empty() and context.carrier.cargo_items.size()==1 and _joints().size()==1
	return {"hot":hot,"beneficiary":beneficiary,"joint_integrity":intact,"bodies_and_native":_bodies(),"joints":_joints(),"water":{"carrier":context.carrier.water_contact,"beneficiary":context.workbench.beneficiary.water_contact},"saved_kind":saved_envelope.get("kind")}

func _new_main() -> bool:
	session = MAIN.instantiate()
	root.add_child(session)
	var started: bool = session.profile_ready and session.start_flight("solo")
	if started:
		session.inputs.test_enabled = true
		session.inputs.test_frame = {"axes":{},"held":["brake"],"edges":[]}
	return _check(started,"actual MAIN starts solo through the original QA Store",_diagnostics())

func _load(region: String,label: String) -> bool:
	var loaded: bool = session._load_region(region)
	if not loaded:
		# The failed prepare is normally consumed by _load_region. Reproduce only
		# its read-only preparation for a precise code, and discard any candidate.
		var diagnostic: Dictionary = session._prepare_region(region)
		prepared_error = str(diagnostic.get("error","prepare_now_succeeded"))
		if diagnostic.get("ok",false): session._discard_prepared_region(diagnostic)
	return _check(loaded and session.region_id==region,label,_diagnostics())

func _wait_ready(maximum_frames: int,label: String) -> bool:
	var began: int = Engine.get_physics_frames()
	for unused in maximum_frames:
		await _frame()
		if finished: return false
		var state: Dictionary = session.canal.status()
		if not state.error.is_empty() or not str(state.assembly.get("fatal","")).is_empty() or not session.active: break
		if state.ready:
			return _check(true,label,{"physics_frames":Engine.get_physics_frames()-began,"diagnostics":_diagnostics()})
	return _check(false,label,{"physics_frames":Engine.get_physics_frames()-began,"diagnostics":_diagnostics()})

func _pause_cycle(label: String,frames: int) -> bool:
	var before_status: Dictionary = session.canal.status()
	var requested_frame: int = Engine.get_physics_frames()
	session._request_pause() # Original single-participant Consensus; physical application is asynchronous.
	var proposal: Dictionary = session.consensus.current_proposal()
	var pending: Dictionary = session.canal.pause_request_status()
	if not _check(not session.simulation_paused and proposal.get("kind")=="pause" and proposal.get("state")=="ready" and pending.get("ok",false) and pending.get("pending",false),"original Consensus retains ready proposal until the actual physics pause boundary: "+label,{"proposal":proposal,"request":pending,"diagnostics":_diagnostics()}): return false
	for unused in 75:
		await _frame()
		if finished: return false
		if session.simulation_paused or not session.canal.pause_request_status().get("ok",false): break
	var boundary: Dictionary = session.canal.pause_boundary_snapshot()
	var before: Dictionary = boundary.get("bodies",{})
	var modules: Dictionary = boundary.get("modules",{})
	var clock: float = float(boundary.get("carrier_clock",-1.0))
	var paused: Dictionary = session.canal.status()
	var context: Dictionary = session.canal.context()
	var joints: Dictionary = _joints()
	var paused_modules_start: Dictionary = _phase_modules()
	if not _check(boundary.get("ok",false) and not before.is_empty() and int(boundary.get("physics_frame",-1))>=requested_frame and session.simulation_paused and session.consensus.current_proposal().is_empty() and paused.physics_paused and paused.pause_fault.is_empty() and int(paused.paused_body_count)==before.size() and session.players[1].freeze,"Session completes the original Consensus at a recorded actual native pause boundary: "+label,{"boundary":boundary,"modules_at_pause":paused_modules_start,"status":paused,"last_pause_result":session.last_pause_result,"interface.message":session.interface.message.text}): return false
	for unused in frames:
		await _frame()
		if finished: return false
	var still: Dictionary = _bodies()
	var stable: bool = still.keys()==before.keys() and _joints()==joints
	for id: int in before:
		if not still.has(id):
			stable = false
			continue
		var row: Dictionary = still[id]
		stable = stable and row.freeze and row.linear==Vector3.ZERO and row.angular==Vector3.ZERO and row.native_linear==Vector3.ZERO and row.native_angular==Vector3.ZERO and not row.process and not row.physics_process and row.rid==before[id].rid and row.pose==before[id].pose and row.physical==before[id].physical
	var paused_modules: Dictionary = _phase_modules()
	# Existing Custody legitimately toggles paused/revision at the transition.
	# During stopped ticks every field remains exact; absent modules stay absent.
	stable = stable and paused_modules==paused_modules_start and paused_modules.rules==modules.rules and (paused_modules.custody==null)==(modules.custody==null) and context.carrier.flight_seconds==clock and session.canal.status().pause_fault.is_empty()
	_check(stable,"actual paused ticks preserve poses, joints and phase-present rule/custody/Flight clocks: "+label,{"frames":frames,"before":before,"paused":still,"modules_before":modules,"modules_paused":paused_modules,"status":session.canal.status()})
	session._request_pause() # Original Consensus resumes; sample before any subsequent physics tick.
	var resumed: Dictionary = _bodies()
	var restored: bool = resumed.keys()==before.keys() and _joints()==joints and not session.simulation_paused and session.consensus.current_proposal().is_empty() and not session.canal.status().physics_paused
	for id: int in before:
		if not resumed.has(id):
			restored = false
			continue
		for key: String in ["rid","freeze","freeze_mode","sleeping","linear","angular","process","physics_process"]:
			restored = restored and resumed[id][key]==before[id][key]
		restored = restored and resumed[id].native_linear==before[id].linear and resumed[id].native_angular==before[id].angular and resumed[id].native_sleeping==before[id].sleeping and resumed[id].physical==before[id].physical and resumed[id].pose==before[id].pose
	var restored_once: int = int(session.canal.status().pause_restores)
	restored = restored and restored_once==int(before_status.pause_restores)+1
	_check(restored,"original Consensus resumes exact recorded native momentum, modes and same RID/pose once: "+label,{"boundary":boundary,"after":resumed,"status":session.canal.status(),"diagnostics":_diagnostics()})
	session._apply_pause_state()
	_check(_bodies()==resumed and int(session.canal.status().pause_restores)==restored_once,"repeated Session resume cannot reapply old momentum: "+label)
	return stable and restored

func _phase_modules() -> Dictionary:
	# Bootstrap deliberately has no Rules/Custody yet. Observe that absence;
	# never configure substitutes merely to make a pre-WAIT assertion run.
	var context: Dictionary = session.canal.context()
	var rules: Variant = context.get("rules")
	var custody: Variant = context.get("custody")
	return {"rules":rules.snapshot().duplicate(true) if rules!=null else null,"custody":custody.report().duplicate(true) if custody!=null else null}

func _targets(label: String) -> bool:
	var valid: bool = session.canal.status().target_count==6
	var rows: Dictionary = {}
	for id: String in Canal.IDS:
		var body: Variant = session.world.objects.get(id)
		var found: bool = body is PhysicsBody3D and is_instance_valid(body) and body.is_inside_tree() and body.get_world_3d().space==session.world.get_world_3d().space and body.get_meta("entity_id","")==id and session.world.definitions.has(id) and session.world.initial_transforms.has(id) and session.entities.has(id)
		if found: found = session.entities[id].position.is_equal_approx(body.global_position)
		rows[id] = {"valid":found,"body_id":body.get_instance_id() if is_instance_valid(body) else 0}
		valid = valid and found
	return _check(valid,"six live same-world targets are factory-registered exactly once: "+label,rows)

func _bodies() -> Dictionary:
	var result: Dictionary = {}
	for node: Node in session.canal.module.find_children("*","RigidBody3D",true,false):
		var body := node as RigidBody3D
		result[body.get_instance_id()] = {"name":str(body.name),"rid":str(body.get_rid()),"pose":body.global_transform,"physical":PhysicsServer3D.body_get_state(body.get_rid(),PhysicsServer3D.BODY_STATE_TRANSFORM),"freeze":body.freeze,"freeze_mode":body.freeze_mode,"sleeping":body.sleeping,"linear":body.linear_velocity,"angular":body.angular_velocity,"native_linear":PhysicsServer3D.body_get_state(body.get_rid(),PhysicsServer3D.BODY_STATE_LINEAR_VELOCITY),"native_angular":PhysicsServer3D.body_get_state(body.get_rid(),PhysicsServer3D.BODY_STATE_ANGULAR_VELOCITY),"native_sleeping":PhysicsServer3D.body_get_state(body.get_rid(),PhysicsServer3D.BODY_STATE_SLEEPING),"process":body.is_processing(),"physics_process":body.is_physics_processing()}
	return result

func _joints() -> Dictionary:
	var result: Dictionary = {}
	for node: Node in session.canal.module.find_children("*","Joint3D",true,false):
		var joint := node as Joint3D
		result[joint.get_instance_id()] = {"rid":str(joint.get_rid()),"a":str(joint.node_a),"b":str(joint.node_b)}
		if joint is PinJoint3D:
			result[joint.get_instance_id()].merge({"local_a":PhysicsServer3D.pin_joint_get_local_a(joint.get_rid()),"local_b":PhysicsServer3D.pin_joint_get_local_b(joint.get_rid()),"bias":joint.get_param(PinJoint3D.PARAM_BIAS),"damping":joint.get_param(PinJoint3D.PARAM_DAMPING),"clamp":joint.get_param(PinJoint3D.PARAM_IMPULSE_CLAMP),"exclude_pair":joint.exclude_nodes_from_collision})
	return result

func _frame() -> void:
	await physics_frame
	await process_frame # Observe the original Session's tick; never tick it twice.

func _disk() -> Dictionary:
	var reader = Store.new(session.store.root_path)
	var loaded: Dictionary = reader.load_profile()
	if not _check(loaded.get("ok",false),"independent original Store reader opens the QA generation",loaded): return {}
	return reader.snapshot()

func _diagnostics() -> Dictionary:
	if not is_instance_valid(session): return {"prepared.error":prepared_error,"session":"not_installed"}
	return {"adapter.status":session.canal.status() if session.canal!=null else {},"interface.message":session.interface.message.text if is_instance_valid(session.interface) else "","last_pause_result":session.last_pause_result,"prepared.error":prepared_error,"active":session.active,"region":session.region_id,"world.build_errors":session.world.build_errors if is_instance_valid(session.world) else [],"save_gate":session.environment_save_gate.last_result.duplicate(true)}

func _check(ok: bool,label: String,actual: Variant=null) -> bool:
	checks.append({"passed":ok,"label":label,"actual":actual})
	return ok

func _finish() -> void:
	if finished: return
	finished = true
	var failures: Array = checks.filter(func(row: Dictionary): return not row.passed)
	var report := {"checks":checks,"failures":failures,"engine_errors":logger.errors,"phases":phases,"save_callbacks":save_callbacks,"saved_envelope":saved_envelope,"final_diagnostics":_diagnostics(),"scope":"Actual MAIN fresh isolated QA solo, default-enabled ordinary Session factory with no adapter in I1, original per-frame bootstrap/restore ticks, original Consensus asynchronous pause and resume; body/RID/pose/native momentum baseline comes from Adapter.pause_boundary_snapshot at the actual synchronized physics freeze boundary, never a stale UI/request frame. Exact native paused pose/zero momentum and original native resume once, real joint/RID/anchors unchanged, real asynchronous SaveGate callback and independent original Store disk readers, I2→I1 six-target teardown, fresh MAIN same-QA-Store I1→I2 saved physical support/joint adoption. Only direct QA region loads are fixtures; no runtime opt-in, adapter allocation/assignment, manual simulation tick, direct simulation_paused write, task fact, unlock or world.region_id commit. Headless lifecycle evidence only: not normal unlocked flight, a completed Canal service loop, graphics, performance, LAN or full-game acceptance."}
	FileAccess.open(output+"/result.json",FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
	print("CANAL_MAIN_LIFECYCLE_RESULT "+JSON.stringify({"checks":checks.size(),"failures":failures,"engine_errors":logger.errors,"diagnostics":report.final_diagnostics}))
	if is_instance_valid(restore_observer):
		restore_observer.free()
		restore_observer = null
	if is_instance_valid(session):
		session.environment_save_gate.cancel("qa_teardown")
		if session.canal!=null: session.canal.clear()
		session.network.close()
		session.free()
		session = null
	await process_frame
	await physics_frame
	await process_frame
	quit(0 if failures.is_empty() and logger.errors.is_empty() else 1)
