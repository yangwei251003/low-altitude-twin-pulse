extends "res://tests_v3/test_canal_main_lifecycle.gd"
## Read-only diagnostics over a private COPY of one explicitly named QA profile.
## The added Node only observes after ordinary MAIN ticks; it advances nothing.
const SOURCE_PROFILE := "qa_canal_main_lifecycle_20261020_224952_95d86b"
class SupportObserver extends Node:
	var sample: Callable
	var previous_frame := -1
	var streak := 0
	var max_streak := 0
	var frame_delta_histogram: Dictionary = {}
	var first_samples: Array = []
	var resets: Array = []
	var last: Dictionary = {}
	func _physics_process(_delta: float) -> void:
		if not sample.is_valid(): return
		var row: Dictionary = sample.call()
		var frame: int = Engine.get_physics_frames()
		var gap: int = frame-previous_frame if previous_frame>=0 else 1
		frame_delta_histogram[str(gap)] = int(frame_delta_histogram.get(str(gap),0))+1
		var reasons: Array = []
		if gap!=1: reasons.append("physics_observer_gap:"+str(gap))
		if not row.get("hot",{}).get("supported",false): reasons.append("hot:"+str(row.get("hot",{}).get("code","missing")))
		if not row.get("beneficiary",{}).get("supported",false): reasons.append("beneficiary:"+str(row.get("beneficiary",{}).get("code","missing")))
		if not row.get("joint_integrity",false): reasons.append("joint_integrity")
		row["physics_frame"] = frame
		row["frame_delta"] = gap
		row["reset_reasons"] = reasons
		if reasons.is_empty(): streak += 1
		else:
			if resets.size()<8: resets.append(row.duplicate(true))
			streak = 0
		max_streak = maxi(max_streak,streak)
		row["consecutive_usec"] = int(round(float(streak)*1000000.0/float(Engine.physics_ticks_per_second)))
		if first_samples.size()<8: first_samples.append(row.duplicate(true))
		last = row
		previous_frame = frame
var observer: SupportObserver
var process_histogram: Dictionary = {}
var process_samples: Array = []

func _run() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--qa-profile="): profile = arg.trim_prefix("--qa-profile=")
		if arg.begins_with("--output="): output = arg.trim_prefix("--output=")
	var origin_path: String = "user://profiles_v3/"+profile+"/qa_inspect_origin.json"
	var origin: Variant = JSON.parse_string(FileAccess.get_file_as_string(origin_path)) if FileAccess.file_exists(origin_path) else null
	if not profile.begins_with("qa_canal_restore_inspect_") or profile!=profile.validate_filename() or not origin is Dictionary or origin.get("source_profile")!=SOURCE_PROFILE or not output.begins_with("res://artifacts/v3/canal-restore-inspect-") or ".." in output or DirAccess.dir_exists_absolute(output):
		quit(2)
		return
	DirAccess.make_dir_recursive_absolute(output)
	session = MAIN.instantiate()
	root.add_child(session)
	if not _check(session.profile_ready,"actual MAIN opens only the private copy of the named QA profile"):
		_finish()
		return
	# QA-copy-only location fixture: preserve every original source file and all
	# state envelopes, but avoid constructing an unrelated I1 before this probe.
	var positioned: Dictionary = session.store.commit({"id":"qa-restore-inspect-location-fixture","set":{"world.region_id":"I2"}})
	if not _check(positioned.get("ok",false),"original Store locates the private QA copy in I2 without task/unlock changes",positioned):
		_finish()
		return
	session.world_cache = session.store.snapshot()
	session.canal_runtime_enabled = true
	if not _check(session.start_flight("solo") and session.region_id=="I2" and session.canal!=null,"ordinary start_flight factory builds saved I2 directly from the QA-copy location fixture",_diagnostics()):
		_finish()
		return
	# Five seconds measures actual post-construction restoration/observation,
	# while the runner separately owns a 25-second hard process/cleanup limit.
	create_timer(5).timeout.connect(func():
		if not finished:
			_check(false,"five second standalone saved-site observer bound",_diagnostics())
			_finish())
	saved_envelope = session.world_cache.world.get("environment",{}).get("I2_canal",{}).duplicate(true)
	if not await _wait_ready(120,"ordinary actual MAIN adopts the copied saved physical site"):
		_finish()
		return
	observer = SupportObserver.new()
	observer.sample = _sample_support
	root.add_child(observer) # After MAIN in normal tree order; no simulation calls.
	var previous := -1
	for unused in 30:
		await physics_frame
		await process_frame # Deliberately retain the OLD cadence for its histogram.
		if finished: return
		var frame: int = Engine.get_physics_frames()
		if previous>=0:
			var delta: int = frame-previous
			process_histogram[str(delta)] = int(process_histogram.get(str(delta),0))+1
		process_samples.append(frame)
		previous = frame
		if observer.max_streak>=21 and process_samples.size()>=4: break
	var observed_usec: int = int(round(float(observer.max_streak)*1000000.0/float(Engine.physics_ticks_per_second)))
	_check(not observer.frame_delta_histogram.is_empty() and observer.frame_delta_histogram.keys()==["1"],"read-only ordinary physics Node observes every consecutive simulation frame",observer.frame_delta_histogram)
	_check(observed_usec>=350000,"actual hot/beneficiary contacts and original physical joint have at least 350ms consecutively observed support",{"max_consecutive_usec":observed_usec,"last":observer.last})
	_check(int(session.canal.context().rules.snapshot().jobs_completed)==0 and int(session.canal.context().rules.snapshot().service_credit)==0,"diagnostic observer grants no job or service credit")
	_finish()

func _sample_support() -> Dictionary:
	var context: Dictionary = session.canal.context()
	var hot: Dictionary = context.custody.support_info(Wait.Rules.CASSETTES[1],Wait.Rules.WORK)
	var beneficiary: Dictionary = Wait.Bench.Departure.support_proof(context.workbench.beneficiary,context.workbench.rack)
	var intact: bool = context.custody._integrity(Wait.Rules.CASSETTES[0]).is_empty() and context.custody._integrity(Wait.Rules.CASSETTES[1]).is_empty() and context.carrier.cargo_items.size()==1 and _joints().size()==1
	return {"hot":hot,"beneficiary":beneficiary,"joint_integrity":intact,"bodies_and_native":_bodies(),"joints":_joints(),"water":{"carrier_contact":context.carrier.water_contact,"beneficiary_contact":context.workbench.beneficiary.water_contact,"carrier_environment":session.world.sample_environment(context.carrier.global_position)},"rules":context.rules.snapshot()}

func _finish() -> void:
	if finished: return
	finished = true
	var failures: Array = checks.filter(func(row: Dictionary): return not row.passed)
	var evidence: Dictionary = {"physics_histogram":observer.frame_delta_histogram,"max_consecutive_frames":observer.max_streak,"first_samples":observer.first_samples,"first_resets":observer.resets,"last":observer.last} if is_instance_valid(observer) else {}
	var report := {"checks":checks,"failures":failures,"engine_errors":logger.errors,"process_frame_delta_histogram":process_histogram,"process_observation_frames":process_samples,"ordinary_physics_observer":evidence,"saved_kind":saved_envelope.get("kind"),"diagnostics":_diagnostics(),"scope":"Standalone five-second post-I2-construction observer, 25-second hard process bound, over a new private copy of exactly qa_canal_main_lifecycle_20261020_224952_95d86b. Source is not opened by Godot. Only this private copy receives one original Store world.region_id=I2 location fixture; Canal is explicitly enabled before normal start_flight to avoid an unrelated I1 build. Envelopes, task facts and unlocks are untouched. Actual MAIN factory restoration; original normal Session/Flight/Water/Rules ticks continue. Additional ordinary Node._physics_process reads actual contacts/rays/velocities/native body states/joint anchors once per physics frame and grants no credit. Side-by-side old physics+process cadence records skipped observation frames; no comparator/physical support thresholds are changed. Not full lifecycle replay or normal progression evidence."}
	FileAccess.open(output+"/result.json",FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
	print("CANAL_RESTORE_INSPECT_RESULT "+JSON.stringify({"checks":checks.size(),"failures":failures,"engine_errors":logger.errors,"process_histogram":process_histogram,"physics_histogram":evidence.get("physics_histogram",{}),"max_consecutive_frames":evidence.get("max_consecutive_frames",0)}))
	if is_instance_valid(observer): observer.free()
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
