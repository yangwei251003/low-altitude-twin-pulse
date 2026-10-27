extends "res://scripts_tools/v3/capture_clinic_integrated.gd"
## Reuses only capture/input/fixture utilities; this is the actual MAIN world.
## Same fresh qa_visual_clinic_ and clinic-integrated- output namespace as base.
## Four production views; actual number/Tab/F/G actions, frozen camera placements.
const Cabinet = preload("res://scripts/v3/world/twin_distribution_cabinet.gd")
const DistributionProgress = preload("res://scripts/v3/gameplay/actions/twin_distribution_progress.gd")

func _run() -> void:
	started_usec = Time.get_ticks_usec()
	if not _arguments_valid():
		OS.remove_logger(capture_logger)
		quit(2)
		return
	if DirAccess.make_dir_recursive_absolute(output) != OK:
		OS.remove_logger(capture_logger)
		quit(2)
		return
	create_timer(180.0, true, false, true).timeout.connect(_timeout)
	root.size = SIZE
	session = MAIN.instantiate()
	root.add_child(session)
	if not _check(session.profile_ready and session.start_flight("solo"), "isolated production MAIN starts"):
		await _finish()
		return
	_hold()
	if not _seed_history():
		await _finish()
		return
	_hold()
	session._ui_action("travel_to", {"region_id":"I2"})
	_hold()
	await physics_frame
	if not _check(session.region_id == "I2" and session._facilities_ready() and session.world.distribution == session.distribution.module,
		"real travel adopts both physical I2 facilities"):
		await _finish()
		return
	body = session.players[1]
	inventories.I2 = _scene_inventory(session.world)
	input_paths.assign(INPUTS)
	input_paths.append("res://scripts_tools/v3/capture_distribution_integrated.gd")
	for directory in ["res://scripts/v3", "res://data/v3", "res://scenes/v3"]: _collect_inputs(directory)
	for path in inventories.I2.imported_sources + inventories.I2.material_sources:
		if path not in input_paths: input_paths.append(path)
	_add_import_hashes()
	hashes_before = _input_hashes()
	var before_personal: Dictionary = session.store.snapshot().personal.duplicate(true)
	await _place(Vector3(17.8,2.7,-7.85), "outside closed distribution service door")
	await _capture("01-I2-distribution-closed", "Default production view of the new replaceable graybox cabinet; neither route is open.")
	if finishing: return
	await _place(Vector3(17.6,5.75,-10.6), "legal high-well approach for real push ability")
	if not _select(KEY_2, Cabinet.COVER_ID):
		await _finish()
		return
	for unused in range(4):
		if float(session.distribution.module.snapshot().axis.position_m) >= 1.2: break
		if not await _cast(KEY_2, Cabinet.COVER_ID):
			await _finish()
			return
		await _ticks(30)
	await _ticks(30)
	await _place(Vector3(18,5.75,-10.6), "legal full-hull position reading both plates through high well")
	var manual: Dictionary = session.distribution.module.observe_back(1, body)
	_check(manual.ok and manual.get("method") == "manual", "actual host rays read both plates by the manual route")
	_g("record early distribution knowledge")
	_check(session.distribution.progress.snapshot().back_observed and session.distribution.progress.snapshot().method == "manual",
		"real nearby G commits early knowledge through Store")
	await _capture("02-I2-distribution-high-well", "Real pushed cover and committed G observation; frozen legal camera placement, not a flown route.")
	if finishing: return
	await _place(Vector3(17.8,2.7,-7.85), "door-side approach for real electrical route")
	if not await _cast(KEY_6, Cabinet.RELAY_ID) or not await _cast(KEY_0, Cabinet.LOCK_ID):
		await _finish()
		return
	await _ticks(125)
	_check(session.distribution.module.snapshot().electric_latched, "real charge and takeover complete the door stroke")
	await _capture("03-I2-distribution-open-door", "Default camera and production HUD after actual charge, takeover and full physical door movement.")
	if finishing: return
	await _place(Vector3(18,2.7,-10.8), "clear interior view behind the actual open service door")
	var electric: Dictionary = session.distribution.module.observe_back(1, body)
	_check(electric.ok and electric.get("method") == "service_lock", "actual interior rays independently read the service route")
	_g("repeat knowledge by another physical route")
	_check(session.distribution.progress.snapshot().method == "manual" and _same(before_personal, session.store.snapshot().personal)
		and session.story.state.completed.size() == 27, "alternate observation preserves first route without extra objective or reward")
	physical_probes.distribution = {"manual":manual, "service":electric, "state":session.distribution.module.snapshot()}
	await _capture("04-I2-distribution-interior", "Three legal zoom steps inspect actual interior and two observed plates; graybox appearance is not art acceptance.", 3)
	await _finish()

func _ticks(count: int) -> void:
	paused = false
	session.world.set_effects_paused(false)
	for unused in range(count):
		await physics_frame
		if finishing: return
		session._physics_process(DT)
		simulated_ticks += 1
		if not session.distribution.error.is_empty() or not session.clinic.error.is_empty() or session.simulation_paused:
			_check(false, "production facilities stopped: " + session.distribution.error + "/" + session.clinic.error)
			break
	_hold()

func _cast(key: Key, target: String) -> bool:
	while float(session.cooldowns.get(1, 0.0)) > 0.0:
		await _ticks(1)
		if finishing: return false
	if not _select(key, target): return false
	var before: Dictionary = _state()
	var accepted: int = int(session.stats.abilities)
	_key(KEY_F)
	actions.append({"input":"number/Tab/F", "target":target, "before":before, "after":_state()})
	return _check(int(session.stats.abilities) == accepted + 1, "real ability input accepts " + target)

func _state() -> Dictionary:
	var result: Dictionary = super._state()
	if session.distribution.ready: result.distribution = session.distribution.persistent_state()
	return result

func _finish() -> void:
	if finishing: return
	finishing = true
	var final_state: Dictionary = _state() if is_instance_valid(session) and session.players.has(1) else {}
	if is_instance_valid(session):
		session.active = false
		session.network.close()
		session.free()
	await process_frame
	await process_frame
	var after := _input_hashes()
	_check(not hashes_before.is_empty() and hashes_before == after, "captured production inputs stayed unchanged")
	_check(shots.size() == 4, "four requested production views saved")
	var logged: Dictionary = capture_logger.snapshot()
	_check(int(logged.error_count) == 0, "no engine/script/shader error including cleanup")
	var passed := true
	for item in checks: passed = passed and bool(item.passed)
	var report := {"passed":passed, "profile":profile, "checks":checks, "shots":shots, "actions":actions,
		"fixture":fixture, "QA_placements":placements, "physical_probes":physical_probes, "final_state":final_state,
		"simulated_ticks":simulated_ticks, "input_sha256_before":hashes_before, "input_sha256_after":after,
		"scene_inventory":inventories, "engine_log":logged, "renderer":RenderingServer.get_current_rendering_method(),
		"wall_seconds":float(Time.get_ticks_usec()-started_usec)/1000000.0,
		"limits":["Historical27 is a trusted fixture. Starting poses are frozen, not flown; cached AGL is unverified.",
			"New physical operations use real number/Tab/F/G input and actual Session fixed ticks, not assigned success.",
			"Replaceable cabinet graybox; no art, performance, human enjoyment or LAN acceptance. No new complete action."]}
	var file := FileAccess.open(output.path_join("state_checks.json"), FileAccess.WRITE)
	if file == null: passed = false
	else:
		file.store_string(JSON.stringify(report, "\t", true, true))
		file.flush()
		passed = passed and file.get_error() == OK
		file.close()
	print("DISTRIBUTION_CAPTURE ", JSON.stringify({"passed":passed, "shots":shots.size(), "checks":checks.size(), "output":output}))
	OS.remove_logger(capture_logger)
	quit(0 if passed else 1)
