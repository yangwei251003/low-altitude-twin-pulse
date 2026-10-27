extends SceneTree
## Pure observer/import-fingerprint contract only. No GPU, flight, FPS or long-run acceptance.
const Profile = preload("res://scripts_tools/v3/profile_crown_flight.gd")
const Encounter = preload("res://scripts/v3/gameplay/twin_crown_encounter.gd")
var checks := 0
var failures: Array[String] = []
const ROSTER: Array[String] = ["player:1"]
const EMPTY_ROSTER: Array[String] = []

func _init() -> void:
	_test_production_observation()
	_test_coverage_rejects_idle_and_warnings()
	_test_reset_and_clock()
	_test_guard_changes()
	_test_fingerprints_and_write_failure()
	print("V3_CROWN_PROFILE_CONTRACT " + JSON.stringify({"checks":checks, "failures":failures,
		"scope":"Pure profiler contract, real encounter rules with movement approval fixture and read-only import hashes. No rendered performance, physical flight or five-minute acceptance."}))
	quit(0 if failures.is_empty() else 1)

func _check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)
		push_error(label)

func _encounter():
	var encounter = Encounter.new()
	var result: Dictionary = encounter.start({"player:1":{"owner":"1", "position":Vector3(-10, 13, -3), "health":100.0, "max_health":100.0, "downed":false}})
	_check(result.ok, "real production encounter starts for observer fixture")
	return encounter

func _advance(encounter) -> void:
	# Pure fixture approves authored routes, not proof of physical clearance.
	var result: Dictionary = encounter.advance(0.1)
	for event in result.events:
		if str(event.kind) == "movement_requested":
			encounter.approve_migration(str(encounter.get_state().movement.token), true)

func _test_production_observation() -> void:
	_check(Profile.CrownCoverage.ENCOUNTER_STEP_USEC == Encounter.STEP_USEC, "observer clock uses actual production step")
	var encounter = _encounter()
	var observer = Profile.CrownCoverage.new()
	observer.observe(encounter.get_state(), true, ROSTER, 0.0, 0.0, 0)
	var actual_fired: Dictionary = {}
	for i in range(1, 3001):
		_advance(encounter)
		var state: Dictionary = encounter.get_state()
		var before: Dictionary = encounter.snapshot()
		observer.observe(state, true, ROSTER, 0.1, i * 0.1, 0)
		if not state.attack.is_empty() and state.attack.fired: actual_fired[state.attack.token] = true
		if i == 35: _check(observer.fired_attacks.is_empty(), "real pending warning is not counted as a fired attack")
		if i == 50: _check(observer.fired_attacks.size() == 1, "real fired attack is observed")
		if i == 55: _check(observer.fired_attacks.size() == 1, "same active attack is counted only once")
		if i == 100: _check(encounter.snapshot() == before, "observer does not mutate authoritative encounter")
	_check(observer.validity_issues(300.0, 300.0).is_empty(), "normal five-minute pure cycle meets declared workload limits, not performance acceptance")
	_check(observer.fired_attacks.size() == actual_fired.size(), "observed fired receipts match all sampled real production attacks")
	_check(is_equal_approx(observer.encounter_seconds, 300.0), "exact encounter clock progress accumulated")
	_check(is_equal_approx(observer.roster_wall_seconds, 300.0), "effective live roster wall coverage accumulated")
	var report: Dictionary = observer.report()
	report.fired_attacks.clear()
	_check(not observer.fired_attacks.is_empty(), "coverage report returns independent receipt data")

func _test_coverage_rejects_idle_and_warnings() -> void:
	var encounter = _encounter()
	var observer = Profile.CrownCoverage.new()
	observer.observe(encounter.get_state(), true, ROSTER, 0.0, 0.0, 0)
	for i in range(1, 301):
		_advance(encounter)
		observer.observe(encounter.get_state(), true, ROSTER, 0.1, i * 0.1, 0)
	var issues: Array = observer.validity_issues(300.0, 300.0)
	_check(issues.has("insufficient_crown_effective_roster_time"), "early activity cannot qualify idle remainder roster coverage")
	_check(issues.has("insufficient_crown_clock_progress"), "early activity cannot qualify idle remainder encounter clock")
	_check(issues.has("insufficient_fired_attacks_in_minute:4"), "per-minute threshold catches unexercised end of long run")
	_check(observer.validity_issues(30.0, 30.0).is_empty(), "thirty-second pure cycle qualifies smoke coverage only")
	var state: Dictionary = encounter.get_state()
	state.tick = 500
	state.attack = {"token":"fixture:warning", "kind":"fixture", "fire_tick":100, "end_tick":700, "fired":false}
	state.hazards = [{"token":"fixture:hazard", "kind":"burning_spores", "fire_tick":490, "end_tick":520, "fired":true}]
	var count: int = observer.fired_attacks.size()
	observer.observe(state, true, EMPTY_ROSTER, 1.0, 31.0, 0)
	_check(observer.fired_attacks.size() == count, "attack without effective roster cannot qualify combat coverage")
	observer.observe(state, true, ROSTER, 1.0, 32.0, 0)
	_check(observer.fired_attacks.has("fixture:hazard") and not observer.fired_attacks.has("fixture:warning"), "active hazard counted while overdue-but-unfired warning remains excluded")
	_check(observer.roster_transitions.size() == 3 and observer.roster_transitions[1].effective_players.is_empty(), "subsecond roster transition history is retained independently of one-second samples")
	state.hazards[0].token = "fixture:expired"
	state.hazards[0].end_tick = 500
	observer.observe(state, true, ROSTER, 1.0, 33.0, 0)
	_check(not observer.fired_attacks.has("fixture:expired"), "expired attack cannot be credited")
	var frozen = Profile.CrownCoverage.new()
	var fresh: Dictionary = _encounter().get_state()
	frozen.observe(fresh, true, ROSTER, 0.0, 0.0, 0)
	frozen.observe(fresh, true, ROSTER, 300.0, 300.0, 0)
	_check(frozen.validity_issues(300, 300).has("insufficient_crown_clock_progress"), "nonempty but frozen roster cannot imply encounter progress")

func _test_reset_and_clock() -> void:
	var observer = Profile.CrownCoverage.new()
	var encounter = _encounter()
	observer.observe(encounter.get_state(), true, ROSTER, 0.0, 0.0, 0)
	encounter.advance(0.35)
	observer.observe(encounter.get_state(), true, ROSTER, 0.35, 0.35, 0)
	_check(is_equal_approx(observer.encounter_seconds, 0.35), "pending microseconds count along with integer ticks")
	encounter.reset()
	observer.observe(encounter.get_state(), true, ROSTER, 0.1, 0.45, 1)
	_check(is_equal_approx(observer.encounter_seconds, 0.35) and observer.errors.is_empty(), "legitimate reset does not subtract or invent clock time")
	encounter.advance(0.2)
	observer.observe(encounter.get_state(), true, ROSTER, 0.2, 0.65, 1)
	_check(is_equal_approx(observer.encounter_seconds, 0.55), "clock progress resumes in next real attempt")
	_check(observer.report().natural_resets == 1 and observer.attempts.size() == 2, "reset serial gives separate attempts")
	var movement: Dictionary = Profile.flight_step(Vector3.ZERO, Vector3(2, 0, 0), 0, 1, 34.9)
	_check(movement.reset and movement.distance == 0.0 and movement.route_wait == 0.0, "short production retry teleport excluded and old leg timeout cleared")
	movement = Profile.flight_step(Vector3.ZERO, Vector3(12, 0, 0), 1, 1, 4.0)
	_check(not movement.reset and movement.unexpected_jump and movement.distance == 12.0 and movement.route_wait == 4.0, "large motion without reset is flagged rather than falsely treated as a retry")
	var bad: Dictionary = encounter.get_state()
	bad.tick = 0
	bad.pending_usec = 0
	observer.observe(bad, true, ROSTER, 0.1, 0.75, 1)
	_check(observer.errors.has("crown_clock_regressed_without_reset"), "unexplained encounter clock regression invalidates observer")
	observer.observe(bad, true, ROSTER, 0.1, 0.85, 0)
	_check(observer.errors.has("crown_reset_serial_regressed"), "reset serial regression is not silently accepted")

func _test_guard_changes() -> void:
	var baseline := {"focused":true, "window_mode":DisplayServer.WINDOW_MODE_WINDOWED, "window_size":Vector2i(1280,720), "viewport_size":Vector2i(1280,720), "vsync":1, "max_fps":0, "time_scale":1.0, "simulation_paused":false, "tree_paused":false, "render_loop":true, "camera_size":32.0, "msaa":0, "scaling":1.0}
	_check(Profile.guard_issues(baseline, baseline).is_empty(), "stable foreground settings accepted")
	for fixture in [["focused",false,"window_focus_lost"], ["simulation_paused",true,"timing_or_pause_changed"], ["tree_paused",true,"timing_or_pause_changed"], ["max_fps",30,"timing_or_pause_changed"], ["time_scale",0.5,"timing_or_pause_changed"], ["render_loop",false,"render_loop_disabled"], ["camera_size",40.0,"camera_zoom_changed"], ["window_size",Vector2i(800,600),"window_or_viewport_changed"], ["viewport_size",Vector2i(800,600),"window_or_viewport_changed"], ["vsync",0,"vsync_changed"], ["msaa",1,"render_quality_changed"], ["scaling",0.5,"render_quality_changed"], ["window_mode",DisplayServer.WINDOW_MODE_MINIMIZED,"window_minimized"]]:
		var changed: Dictionary = baseline.duplicate()
		changed[fixture[0]] = fixture[1]
		_check(Profile.guard_issues(changed, baseline).has(fixture[2]), "frame guard rejects " + str(fixture[0]))

func _test_fingerprints_and_write_failure() -> void:
	var paths: Array[String] = ["res://assets/v3/crown/parasitic_crown.glb", "res://assets/fonts/NotoSansSC-Medium.ttf"]
	var manifest: Dictionary = Profile.fingerprint_paths(paths)
	_check(manifest.errors.is_empty(), "actual crown and font import configs and cache files are readable")
	for path in paths:
		_check(manifest.sha256.has(path) and manifest.sha256.has(path + ".import"), "source and actual import settings locked: " + path)
		_check(not manifest.imports.get(path + ".import", []).is_empty(), "actual remap target discovered: " + path)
		for cache in manifest.imports.get(path + ".import", []):
			_check(manifest.sha256.get(cache, "").length() == 64, "actual remapped runtime cache hash locked: " + cache)
	var missing: Array[String] = ["res://__nonexistent_crown_profile_contract__"]
	_check(not Profile.fingerprint_paths(missing).errors.is_empty(), "missing fingerprint cannot silently certify inputs")
	# A guaranteed nonexistent parent fails without creating any files.
	var absent := "user://missing_crown_profile_contract_%d/report.json" % Time.get_ticks_usec()
	_check(not Profile.store_evidence_json(absent, {"status":"fixture"}), "JSON write failure is propagated to caller")
