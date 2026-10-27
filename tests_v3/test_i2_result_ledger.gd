extends SceneTree
## Pure production Director + result ledger. Trusted historical fact fixtures
## are NOT physical observations, a playthrough, Store writes or reward delivery.
const Ledger = preload("res://scripts/v3/gameplay/twin_i2_result_ledger.gd")
const Director = preload("res://scripts/v3/gameplay/actions/twin_action_director.gd")
const ClinicData = preload("res://tests_v3/test_clinic_action.gd")
const ClinicProgress = preload("res://scripts/v3/gameplay/actions/twin_clinic_progress.gd")
const DistributionProgress = preload("res://scripts/v3/gameplay/actions/twin_distribution_progress.gd")
const EXPOSE := "I2:distribution_audit:expose"
const TRACE := "I2:distribution_audit:trace"
const SHARE := "I2:distribution_audit:share_access"
const EXTRA_EVENTS := [
	[EXPOSE, "fact", "I2:distribution_back_exposed", "manual"],
	[TRACE, "fact", "I2:distribution_route_verified", "mixed_trial"],
	[SHARE, "fact", "I2:distribution_access_committed", "public_span"]
]
var checks := 0
var failures: Array[String] = []
var director = Director.new()
var history: Dictionary = {}
var full: Dictionary = {}

func _initialize() -> void:
	var paths: Array = ClinicData.OLD_EXTENSIONS.duplicate()
	paths.append(Ledger.CLINIC_PATH)
	paths.append(Ledger.DISTRIBUTION_PATH)
	var loaded: Dictionary = director.load_definitions(Director.DEFAULT_PATH, paths)
	check(loaded.get("ok", false), "actual nine-action Director definitions load")
	if loaded.get("ok", false):
		_data_parity()
		_replay()
		if not full.is_empty():
			_routes_and_projection()
			_negative_boundaries()
			_branch_and_early_knowledge()
	print("I2_RESULT_LEDGER checks=%d failures=%d" % [checks, failures.size()])
	print("I2_RESULT_LEDGER_RESULT " + JSON.stringify({"passed":failures.is_empty(), "checks":checks, "failures":failures,
		"scope":"pure_actual_director_results_and_domain_projections",
		"limits":["Trusted event fixtures only; no G/LOS, mechanism, physics, consensus or gameplay completion proof.",
		"No Store commits, receipts/ENet delivery, GUI, performance or human-duration measurement.",
		"Director still validates its complete receipt replay; each facility still validates its physical history."]}))
	quit(0 if failures.is_empty() else 1)

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)
		push_error(label)

func _data_parity() -> void:
	var declared: Dictionary = Ledger.contract()
	var actual: Dictionary = {}
	var domain_by_goal := {EXPOSE:"distribution", TRACE:"trial", SHARE:"shared_access"}
	for path in [Ledger.CLINIC_PATH, Ledger.DISTRIBUTION_PATH]:
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
		if not parsed is Dictionary:
			check(false, "actual authored extension is readable: " + path)
			return
		for action in parsed.actions:
			for objective in action.objectives:
				var flags: Array = []
				var findings: Array = []
				for effect in objective.effects:
					if effect.type == "flag": flags.append(effect)
					if effect.type == "discovery": findings.append(effect.discovery_id)
				var dependencies: Array = objective.after.duplicate()
				# The first audit objective also depends on the entire clinic action.
				if objective.id == EXPOSE:
					check(action.prerequisites == ["I2:clinic_supply"], "cross-domain prerequisite remains the actual clinic action")
					dependencies = ["I2:clinic_supply:confirm"]
				check(objective.events.size() == 1 and flags.size() <= 1 and findings.size() <= 1 and (flags.is_empty() or flags[0].value == true), "result shape remains supported: " + str(objective.id))
				actual[objective.id] = {"domain":domain_by_goal.get(objective.id, "clinic"), "options":objective.events[0].options,
					"after":dependencies, "flag":"" if flags.is_empty() else flags[0].key, "discovery":"" if findings.is_empty() else findings[0]}
	check(declared == actual and actual.size() == 7, "exact seven IDs, options, flags and discoveries match actual clinic/distribution JSON; no I2 wildcard")
	declared[TRACE].options.append("forged")
	check("forged" not in Ledger.contract()[TRACE].options, "public contract is isolated from caller mutation")

func _apply(state: Dictionary, row: Array) -> Dictionary:
	var event := {"id":"qa_i2_ledger:" + str(row[0]), "type":row[1], "target_id":row[2], "option":row[3]}
	var result: Dictionary = director.apply_event(state, event, {"is_authority":true, "validated":true, "region_id":str(row[0]).get_slice(":", 0)})
	if not result.get("changed", false):
		check(false, "trusted authored event applies: " + str(row[0]) + " / " + str(result.get("code")))
		return {}
	return result.state

func _world(state: Dictionary) -> Dictionary:
	return {"actions":{"opening":state.duplicate(true)}, "completed_objectives":state.completed.duplicate(),
		"flags":state.flags.duplicate(true), "environment":{}, "choices":{}}

func _replay() -> void:
	history = director.default_state()
	for row in ClinicData.OLD_EVENTS:
		history = _apply(history, row)
		if history.is_empty(): return
	check(history.completed.size() == 27 and Ledger.validate_world(_world(history), history.discoveries).ok, "actual old seven-action save remains valid")
	var current: Dictionary = history.duplicate(true)
	var rows: Array = ClinicData.EVENTS.duplicate(true)
	rows.append_array(EXTRA_EVENTS)
	for row in rows:
		current = _apply(current, row)
		if current.is_empty(): return
		var restored: Variant = JSON.parse_string(JSON.stringify(_world(current), "", true, true))
		check(Ledger.validate_world(restored, current.discoveries).ok, "each actual I2 prefix survives JSON readback: " + str(row[0]))
	full = _world(current)
	check(current.completed.size() == 34 and director.validate_state(current).ok, "full fixture is actual valid nine-action34-objective Director state")

func _routes_and_projection() -> void:
	var valid_routes := true
	for feed in ["gravity", "pump"]:
		for cover in ["manual", "service_lock"]:
			for sample in ["manual_trial", "pulse_trial", "mixed_trial"]:
				for access in ["public_span", "service_span"]:
					var state: Dictionary = history.duplicate(true)
					var rows: Array = ClinicData.EVENTS.duplicate(true)
					rows[1][3] = feed
					var tail: Array = EXTRA_EVENTS.duplicate(true)
					for i in range(3): tail[i][3] = [cover, sample, access][i]
					rows.append_array(tail)
					for row in rows:
						state = _apply(state, row)
						if state.is_empty(): return
					var result: Dictionary = Ledger.validate_world(_world(state), state.discoveries)
					valid_routes = valid_routes and result.ok and result.projected.shared_access.choices.get(SHARE) == access
	check(valid_routes, "all24 authored feed/cover/sample/access combinations pass actual Director then ledger")
	var before: PackedByteArray = var_to_bytes(full)
	var accepted: Dictionary = Ledger.validate_world(full, full.actions.opening.discoveries)
	var projection: Dictionary = accepted.projected
	check(projection.clinic.completed == [ClinicProgress.DIAGNOSE, ClinicProgress.CONNECT, ClinicProgress.STABILIZE, ClinicProgress.CONFIRM] and projection.distribution.completed == [EXPOSE] and projection.trial.completed == [TRACE] and projection.shared_access.completed == [SHARE], "precise owned projections never give TRACE or bridge results to old clinic/cabinet validators")
	check(ClinicProgress._story_state(projection.clinic.completed, projection.clinic.flags).ok and DistributionProgress._story_state(projection.distribution.completed, projection.distribution.flags, projection.distribution.discoveries).ok, "real old domain result validators accept their projections")
	check(projection.shared_access.flags["I2:distribution_access_shared"] is bool and projection.shared_access.choices[SHARE] == "public_span", "mode is an authored choice; stable shared result flag remains boolean")
	projection.clinic.completed.clear()
	projection.shared_access.choices[SHARE] = "service_span"
	projection.trial.discoveries.clear()
	check(var_to_bytes(full) == before and Ledger.validate_world(full, full.actions.opening.discoveries).projected.shared_access.choices[SHARE] == "public_span", "projection changes do not mutate input or the next validation")
	var reordered: Dictionary = full.duplicate(true)
	reordered.completed_objectives.reverse()
	reordered.completed_objectives.append("I1:unrelated_non_action_record")
	check(Ledger.validate_world(reordered, full.actions.opening.discoveries).ok, "two I2 ledgers compare sets; unrelated non-I2 records are not reinterpreted")
	var string_name: Dictionary = full.duplicate(true)
	string_name.flags.erase("I2:clinic_ready")
	string_name.flags[StringName("I2:clinic_ready")] = true
	check(Ledger.validate_world(string_name, full.actions.opening.discoveries).ok, "real StringName flag keys remain compatible without coercing their values")

func _reject(world: Variant, label: String, discoveries: Variant = null) -> void:
	var personal: Variant = full.actions.opening.discoveries.duplicate() if discoveries == null else discoveries
	var before: PackedByteArray = var_to_bytes([world, personal])
	var result: Dictionary = Ledger.validate_world(world, personal)
	check(not result.ok and not str(result.error).is_empty() and result.projected.is_empty() and before == var_to_bytes([world, personal]), label + "; rejection is atomic and has no partial projection")

func _negative_boundaries() -> void:
	_reject([], "non-world input rejected")
	for field in ["actions", "environment", "flags", "completed_objectives"]:
		var wrong: Dictionary = full.duplicate(true)
		wrong[field] = null
		_reject(wrong, "explicit null world field rejected: " + field)
	for field in ["completed", "flags", "choices", "discoveries"]:
		var wrong: Dictionary = full.duplicate(true)
		wrong.actions.opening[field] = null
		_reject(wrong, "explicit null opening field rejected: " + field)
	for mutation in ["unknown_objective", "duplicate_outside_i2", "wrong_id_type", "ledgers_disagree", "unknown_flag", "numeric_flag", "wrong_shared_flag", "world_flag_missing", "director_flag_missing", "unknown_choice", "wrong_option", "nonstring_choice", "missing_choice", "choice_ahead", "unknown_result_discovery", "missing_result_discovery", "duplicate_result_discovery", "orphan_trace"]:
		var bad: Dictionary = full.duplicate(true)
		match mutation:
			"unknown_objective":
				bad.actions.opening.completed.append("I2:unregistered:result")
				bad.completed_objectives.append("I2:unregistered:result")
			"duplicate_outside_i2": bad.completed_objectives.append(bad.completed_objectives[0])
			"wrong_id_type": bad.actions.opening.completed.append(17)
			"ledgers_disagree": bad.completed_objectives.erase(TRACE)
			"unknown_flag": bad.flags["I2:unregistered:flag"] = false
			"numeric_flag": bad.flags["I2:clinic_ready"] = 1
			"wrong_shared_flag": bad.flags["I2:distribution_access_shared"] = "public_span"
			"world_flag_missing": bad.flags.erase("I2:distribution_trace_verified")
			"director_flag_missing": bad.actions.opening.flags.erase("I2:distribution_trace_verified")
			"unknown_choice": bad.actions.opening.choices["I2:unregistered:result"] = "manual"
			"wrong_option": bad.actions.opening.choices[SHARE] = "manual"
			"nonstring_choice": bad.actions.opening.choices[SHARE] = true
			"missing_choice": bad.actions.opening.choices.erase(TRACE)
			"choice_ahead":
				bad = _world(history)
				bad.actions.opening.choices[TRACE] = "mixed_trial"
			"unknown_result_discovery": bad.actions.opening.discoveries.append("I2:unregistered:world_result")
			"missing_result_discovery": bad.actions.opening.discoveries.erase("I2:label_flow_disagreement")
			"duplicate_result_discovery": bad.actions.opening.discoveries.append("I2:label_flow_disagreement")
			"orphan_trace":
				bad.actions.opening.completed.erase(EXPOSE)
				bad.completed_objectives.erase(EXPOSE)
				bad.actions.opening.choices.erase(EXPOSE)
				bad.actions.opening.discoveries.erase("I2:distribution_back_route")
				bad.actions.opening.flags.erase("I2:distribution_back_observed")
				bad.flags.erase("I2:distribution_back_observed")
		_reject(bad, mutation)
	_reject(full, "wrong personal discovery list type", {})
	_reject(full, "duplicate personal finding", ["I2:shared_access_plan", "I2:shared_access_plan"])
	_reject(full, "wrong personal finding item type", [false])
	var oversized: Dictionary = full.duplicate(true)
	oversized.completed_objectives.resize(257)
	_reject(oversized, "bounded completed array")

func _branch_and_early_knowledge() -> void:
	var earlier: Dictionary = _world(history)
	# Explicit opaque domain envelopes: ledger does not inspect or bless these
	# evidence bodies; the actual adapters must separately reject malformed ones.
	earlier.environment = {"I2_distribution":{"history":{"back_observed":true}}, "I2_trial_flow":{"observed_gauges":{"A":{"volume_ml":20000}, "B":{"volume_ml":20000}}}}
	var unchanged: PackedByteArray = var_to_bytes(earlier)
	var early: Dictionary = Ledger.validate_world(earlier)
	check(early.ok and early.i2_completed.is_empty() and early.projected.distribution.flags.is_empty() and early.projected.trial.result_discoveries.is_empty() and var_to_bytes(earlier) == unchanged, "early mechanism exploration produces no objective, world flag or reward in the common ledger")
	var personal: Array = full.actions.opening.discoveries.duplicate()
	personal.append("I2:other_optional_personal_knowledge")
	var branch: Dictionary = Ledger.validate_world(earlier, personal)
	check(branch.ok and branch.projected.shared_access.completed.is_empty() and branch.projected.shared_access.discoveries == ["I2:shared_access_plan"] and branch.projected.shared_access.result_discoveries.is_empty(), "personal discoveries from a later branch survive an earlier world without fabricating completion")
	check(DistributionProgress._story_state(branch.projected.distribution.completed, branch.projected.distribution.flags, branch.projected.distribution.discoveries).ok, "actual cabinet validator accepts projected earlier branch plus prior personal discovery")
	var delayed: Dictionary = Ledger.validate_world(full, [])
	check(delayed.ok and delayed.projected.distribution.discoveries.is_empty() and delayed.projected.distribution.result_discoveries == ["I2:distribution_back_route"], "guest world results do not require already-delivered personal rewards")
	check(Ledger.validate_world({}, personal).ok, "missing old I2 actions remain empty; prior personal findings are not missing world-history proof")
	var repeated: Dictionary = Ledger.validate_world(full, full.actions.opening.discoveries)
	check(repeated == Ledger.validate_world(full, full.actions.opening.discoveries) and not repeated.has("effects") and not repeated.has("receipts"), "repeated validation is deterministic and emits no reward or receipt")
