extends RefCounted
## Pure cross-facility result boundary; no scene, persistence, receipt replay or
## mechanism evidence. Exact IDs/options are parity-tested against both JSONs.

const CLINIC_PATH := "res://data/v3/actions/clinic_action.json"
const DISTRIBUTION_PATH := "res://data/v3/actions/distribution_action.json"
const Canal = preload("res://scripts/v3/gameplay/twin_canal_session.gd")
const Pump = preload("res://scripts/v3/gameplay/twin_pump_guardian_mechanisms.gd")
const Encounter = preload("res://scripts/v3/campaign/twin_campaign_encounter.gd")
const PreparationProof = preload("res://scripts/v3/gameplay/twin_canal_preparation_proof.gd")
const DOMAINS := ["clinic", "distribution", "trial", "shared_access", "canal", "guardian"]
const RESULTS := {
	"I2:clinic_supply:diagnose": {"domain":"clinic", "options":["identified"], "after":[], "flag":"", "discovery":""},
	"I2:clinic_supply:connect": {"domain":"clinic", "options":["gravity", "pump"], "after":["I2:clinic_supply:diagnose"], "flag":"", "discovery":""},
	"I2:clinic_supply:stabilize": {"domain":"clinic", "options":["verified"], "after":["I2:clinic_supply:connect"], "flag":"", "discovery":""},
	"I2:clinic_supply:confirm": {"domain":"clinic", "options":["commissioned"], "after":["I2:clinic_supply:stabilize"], "flag":"I2:clinic_ready", "discovery":"I2:clinic_priority_misroute"},
	"I2:distribution_audit:expose": {"domain":"distribution", "options":["manual", "service_lock"], "after":["I2:clinic_supply:confirm"], "flag":"I2:distribution_back_observed", "discovery":"I2:distribution_back_route"},
	"I2:distribution_audit:trace": {"domain":"trial", "options":["manual_trial", "pulse_trial", "mixed_trial"], "after":["I2:distribution_audit:expose"], "flag":"I2:distribution_trace_verified", "discovery":"I2:label_flow_disagreement"},
	"I2:distribution_audit:share_access": {"domain":"shared_access", "options":["public_span", "service_span"], "after":["I2:distribution_audit:trace"], "flag":"I2:distribution_access_shared", "discovery":"I2:shared_access_plan"}
}
const CAMPAIGN_RESULTS := {
	"I2:canal_service:brief":{"domain":"canal","options":["brief"],"after":["I2:distribution_audit:share_access"],"flag":"","discovery":""},
	"I2:canal_service:exchange":{"domain":"canal","options":["high_route","low_route","mixed_route","local_cooling"],"after":["I2:canal_service:brief"],"flag":"","discovery":""},
	"I2:canal_service:service":{"domain":"canal","options":["repaired"],"after":["I2:canal_service:exchange"],"flag":"I2:canal_service_ready","discovery":"I2:canal_calibration"},
	"I2:canal_service:order":{"domain":"canal","options":["record"],"after":["I2:canal_service:service"],"flag":"","discovery":"I2:pump_priority_order"},
	"I2:twin_pump_guardian:plan":{"domain":"guardian","options":["plan"],"after":["I2:canal_service:order"],"flag":"","discovery":""},
	"I2:twin_pump_guardian:engage":{"domain":"guardian","options":["observed"],"after":["I2:twin_pump_guardian:plan"],"flag":"I2:boss_pattern_observed","discovery":""},
	"I2:twin_pump_guardian:stop":{"domain":"guardian","options":["committed"],"after":["I2:twin_pump_guardian:engage"],"flag":"I2:boss_stopped","discovery":""},
	"I2:twin_pump_guardian:decision":{"domain":"guardian","options":["clinic_reserve","balanced_service"],"after":["I2:twin_pump_guardian:stop"],"flag":"I2:chapter_decision_saved","discovery":"I2:operation_record"}}

static func contract() -> Dictionary:
	return RESULTS.duplicate(true)

static func campaign_contract() -> Dictionary:
	return CAMPAIGN_RESULTS.duplicate(true)

static func validate_world(world_data: Variant, discoveries: Variant = []) -> Dictionary:
	if not world_data is Dictionary: return _failure("world_shape")
	for field in ["actions", "environment", "flags"]:
		if not world_data.get(field, {}) is Dictionary: return _failure("world_" + field + "_shape")
	var opening: Variant = world_data.get("actions", {}).get("opening", {})
	if not opening is Dictionary: return _failure("opening_shape")
	var completed: Dictionary = _ids(opening.get("completed", []), 256)
	if not completed.ok: return _failure("opening_completed_" + str(completed.error))
	var recorded: Dictionary = _ids(world_data.get("completed_objectives", []), 256)
	if not recorded.ok: return _failure("world_completed_" + str(recorded.error))
	var results: Dictionary = _ids(opening.get("discoveries", []), 512)
	if not results.ok: return _failure("opening_discoveries_" + str(results.error))
	var personal: Dictionary = _ids(discoveries, 512)
	if not personal.ok: return _failure("personal_discoveries_" + str(personal.error))
	var opening_ids: Array = []
	var recorded_ids: Array = []
	var all_results: Dictionary = RESULTS.duplicate(true)
	all_results.merge(CAMPAIGN_RESULTS)
	for source in [completed.ids, recorded.ids]:
		for id in source:
			if id.begins_with("I2:") and not all_results.has(id): return _failure("unknown_i2_objective")
	for id in completed.ids:
		if id.begins_with("I2:"): opening_ids.append(id)
	for id in recorded.ids:
		if id.begins_with("I2:"): recorded_ids.append(id)
	opening_ids.sort()
	recorded_ids.sort()
	if opening_ids != recorded_ids: return _failure("i2_completed_mismatch")

	var known_flags: Dictionary = {}
	var known_findings: Dictionary = {}
	for id in all_results:
		var rule: Dictionary = all_results[id]
		if not str(rule.flag).is_empty(): known_flags[rule.flag] = id
		if not str(rule.discovery).is_empty(): known_findings[rule.discovery] = id
	known_flags["I2:region_route_open"] = "I2:twin_pump_guardian:decision"
	var world_flags: Dictionary = _flags(world_data.get("flags", {}), known_flags)
	if not world_flags.ok: return _failure("world_flags_" + str(world_flags.error))
	var action_flags: Dictionary = _flags(opening.get("flags", {}), known_flags)
	if not action_flags.ok: return _failure("opening_flags_" + str(action_flags.error))
	var choices: Variant = opening.get("choices", {})
	if not choices is Dictionary or choices.size() > 512: return _failure("choices_shape")
	for key in choices:
		if not _key(key): return _failure("choice_key")
		var id: String = str(key)
		if not id.begins_with("I2:"): continue # Director owns non-I2 receipts.
		if not all_results.has(id): return _failure("unknown_i2_choice")
		if not choices[key] is String or choices[key] not in all_results[id].options: return _failure("choice_option")
		if not completed.ids.has(id): return _failure("choice_without_completion")
	for id in results.ids:
		if id.begins_with("I2:") and not known_findings.has(id): return _failure("unknown_i2_result_discovery")

	var projected: Dictionary = {}
	for domain in DOMAINS:
		projected[domain] = {"completed":[], "flags":{}, "choices":{}, "discoveries":[], "result_discoveries":[]}
	for id in all_results:
		var rule: Dictionary = all_results[id]
		var done: bool = completed.ids.has(id)
		var domain: Dictionary = projected[rule.domain]
		if done:
			if not choices.has(id): return _failure("completed_choice_missing")
			for previous in rule.after:
				if not completed.ids.has(previous): return _failure("i2_result_order")
			domain.completed.append(id)
			domain.choices[id] = choices[id]
		var flag: String = rule.flag
		if not flag.is_empty():
			if world_flags.selected.get(flag, false) != done or action_flags.selected.get(flag, false) != done:
				return _failure("result_flag_mismatch")
			if world_flags.selected.has(flag): domain.flags[flag] = world_flags.selected[flag]
		var finding: String = rule.discovery
		if not finding.is_empty():
			if results.ids.has(finding) != done: return _failure("result_discovery_mismatch")
			if results.ids.has(finding): domain.result_discoveries.append(finding)
			# Personal knowledge can precede this branch or lag a guest's world
			# until reliable reward delivery. Never fabricate or erase it here.
			if personal.ids.has(finding): domain.discoveries.append(finding)
	var decision_done: bool = completed.ids.has("I2:twin_pump_guardian:decision")
	if world_flags.selected.get("I2:region_route_open",false) != decision_done or action_flags.selected.get("I2:region_route_open",false) != decision_done: return _failure("campaign_route_flag_mismatch")
	var evidence: Dictionary = _campaign_evidence(world_data,completed.ids,choices)
	if not evidence.ok: return evidence
	return {"ok":true, "error":"", "i2_completed":opening_ids, "projected":projected}

## New results remain tied to the ORIGINAL saved physical participants. The
## four earlier facility projections/validators continue to validate their own
## real histories; recognizing these exact IDs cannot legitimize a fake prefix.
static func _campaign_evidence(world_data: Dictionary, completed: Dictionary, choices: Dictionary) -> Dictionary:
	var has_canal := false
	var has_guardian := false
	for id in completed:
		if str(id).begins_with("I2:canal_service:"): has_canal = true
		if str(id).begins_with("I2:twin_pump_guardian:"): has_guardian = true
	if not has_canal and not has_guardian: return {"ok":true}
	var environment: Dictionary = world_data.get("environment",{})
	var envelope: Variant = environment.get("I2_canal")
	if not envelope is Dictionary: return _failure("canal_physical_envelope_required")
	var checker = Canal.WaitCheckpoint
	if envelope.get("kind") == Canal.StartupCheckpoint.KIND: checker = Canal.StartupCheckpoint
	elif envelope.get("kind") == Canal.ScanCheckpoint.KIND: checker = Canal.ScanCheckpoint
	elif envelope.get("kind") == Canal.ProgressCheckpoint.KIND: checker = Canal.ProgressCheckpoint
	var valid: Dictionary = checker.validate(envelope)
	if not valid.get("ok",false): return _failure("canal_physical:"+str(valid.get("code","invalid")))
	if completed.has("I2:canal_service:exchange"):
		var rules: Dictionary = envelope.get("rules",{})
		if rules.is_empty(): return _failure("canal_exchange_rules_missing")
		var option: String = str(choices.get("I2:canal_service:exchange",""))
		if option == "local_cooling":
			var preparation: Variant = environment.get("I2_canal_preparation")
			if preparation != null:
				# A completed preparation is historical knowledge. Later legitimate
				# reheating does not erase the actual earlier cold checkpoint.
				var sealed: Dictionary = PreparationProof.validate(preparation)
				if not sealed.get("ok",false) or not _local_cooling_history(sealed.get("envelope",{}),sealed.get("envelope",{}).get("rules",{})): return _failure("canal_local_preparation_seal_invalid")
			elif not _local_cooling_history(envelope,rules): return _failure("canal_local_cooling_history_missing")
		else:
			var executor: Dictionary = envelope.get("executor",{})
			var receipt_count: int = int(executor.get("fields",executor).get("_receipt_count",executor.get("receipt_count",0)))
			# Current sealed checkpoint format retains the original automatic LOW
			# count/first-work history, not a manual HIGH/mixed receipt trace.
			if option != "low_route" or int(rules.get("action_serial",0))<11 or receipt_count<10 or rules.get("policy")!="staggered" or rules.get("buffer_enabled")!=false: return _failure("canal_transport_history_missing")
			for pilot: Dictionary in rules.get("pilots",{}).values():
				if pilot.get("enabled")!=false or pilot.get("peer_id")!=0: return _failure("canal_transport_pilot_history")
			if int(rules.get("jobs_completed",0))==0:
				if not _work_identity(rules.get("pending_action",{}),11,Canal.Assembly.Runtime.CASSETTES[0]): return _failure("canal_transport_work_history")
			elif not _work_identity(envelope.get("workbench",{}).get("history",{}).get("first_work",{}).get("action",{}),11,Canal.Assembly.Runtime.CASSETTES[0]): return _failure("canal_transport_work_history")
	if completed.has("I2:canal_service:service"):
		var rules: Dictionary = envelope.get("rules",{})
		if envelope.get("kind") != Canal.ProgressCheckpoint.KIND or int(rules.get("jobs_completed",0))!=1 or int(rules.get("services_consumed",0))!=1 or int(rules.get("service_credit",-1))!=0 or int(rules.get("service_serial",0))!=1 or not envelope.get("executor",{}).get("fields",{}).get("_waiting_for_beneficiary",false): return _failure("canal_claim_history_missing")
	if not has_guardian: return {"ok":true}
	var combat: Variant = environment.get("campaign_I2")
	if not combat is Dictionary or combat.get("version")!=1 or not combat.get("mechanisms") is Dictionary or not combat.get("encounter") is Dictionary or not combat.get("observed") is bool: return _failure("guardian_physical_envelope_required")
	var pump = Pump.new()
	var configured: Dictionary = pump.network.configure(Pump.definition())
	if not configured.get("ok",false) or not pump.validate_state(combat.mechanisms).get("ok",false): return _failure("guardian_water_history_invalid")
	var encounter = Encounter.new()
	if not encounter.configure("twin_pump_guardian").get("ok",false): return _failure("guardian_definition")
	if not combat.encounter.is_empty() and not encounter.validate_snapshot(combat.encounter).get("ok",false): return _failure("guardian_encounter_invalid")
	if completed.has("I2:twin_pump_guardian:engage") and (not combat.observed or combat.encounter.is_empty()): return _failure("guardian_observation_missing")
	if completed.has("I2:twin_pump_guardian:stop") and (not world_data.get("flags",{}).get("campaign_boss:I2",false) or not combat.encounter.get("state",{}).get("completed",false)): return _failure("guardian_victory_missing")
	return {"ok":true}

static func _local_cooling_history(envelope: Dictionary, rules: Dictionary) -> bool:
	var runtime = Canal.Assembly.Runtime
	if rules.get("policy")!="staggered" or rules.get("buffer_enabled")!=false or int(rules.get("command_serial",0))<1: return false
	for pilot: Dictionary in rules.get("pilots",{}).values():
		if pilot.get("enabled")!=false or pilot.get("peer_id")!=0: return false
	var thermal: Dictionary = rules.get("thermal_ledger",{})
	var removed: int = int(thermal.get("ability_removed",0))
	var cassettes: Dictionary = rules.get("cassettes",{})
	if int(rules.get("jobs_completed",0))==0:
		var cassette: Dictionary = cassettes.get(runtime.CASSETTES[1],{})
		var energy: int = int(cassette.get("energy_mj",runtime.INITIAL_HEAT_MJ))
		if cassette.get("holder")!=runtime.WORK or cassettes.get(runtime.CASSETTES[0],{}).get("holder")!=runtime.CARRIER or energy>25000000 or removed<runtime.INITIAL_HEAT_MJ-energy or int(thermal.get("work_added",0))!=0 or int(rules.get("action_serial",0))>1: return false
		var pending: Dictionary = rules.get("pending_action",{})
		return pending.is_empty() or _work_identity(pending,1,runtime.CASSETTES[1])
	if int(rules.get("jobs_completed",0))!=1 or int(thermal.get("work_added",0))!=runtime.WORK_HEAT_MJ or removed<25000000: return false
	return _work_identity(envelope.get("workbench",{}).get("history",{}).get("first_work",{}).get("action",{}),1,runtime.CASSETTES[1])

static func _work_identity(action: Dictionary, serial: int, cassette: String) -> bool:
	return action.get("kind")=="work" and action.get("actor")=="workbench" and action.get("serial")==serial and action.get("cassette_id")==cassette and action.get("source")==Canal.Assembly.Runtime.WORK and action.get("destination")==Canal.Assembly.Runtime.WORK and action.get("route")=="stationary" and action.get("job")==1

static func _ids(value: Variant, limit: int) -> Dictionary:
	if not value is Array or value.size() > limit: return {"ok":false, "error":"shape"}
	var seen: Dictionary = {}
	for id in value:
		if not id is String or id.is_empty() or id.length() > 128: return {"ok":false, "error":"id"}
		if seen.has(id): return {"ok":false, "error":"duplicate"}
		seen[id] = true
	return {"ok":true, "ids":seen}

static func _flags(value: Variant, known: Dictionary) -> Dictionary:
	if not value is Dictionary or value.size() > 512: return {"ok":false, "error":"shape"}
	var selected: Dictionary = {}
	for key in value:
		if not _key(key): return {"ok":false, "error":"key"}
		var id: String = str(key)
		if not id.begins_with("I2:"): continue
		if not known.has(id): return {"ok":false, "error":"unknown_i2"}
		if not value[key] is bool: return {"ok":false, "error":"type"}
		selected[id] = value[key]
	return {"ok":true, "selected":selected}

static func _key(value: Variant) -> bool:
	return (value is String or value is StringName) and not str(value).is_empty() and str(value).length() <= 128

static func _failure(error: String) -> Dictionary:
	return {"ok":false, "error":error, "projected":{}}
