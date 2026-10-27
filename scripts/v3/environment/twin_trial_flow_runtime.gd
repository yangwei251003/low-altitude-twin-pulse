class_name TwinTrialFlowRuntime
extends RefCounted
## Independent host rules. No Nodes, observations, tasks, rewards or persistence IO.
## The physical adapter supplies the complete interval's verified mechanism facts.

const Water = preload("res://scripts/v3/gameplay/environment/twin_water_network.gd")
const DEFAULT_PATH := "res://data/v3/environment/i2_trial_flow_network.json"
const SCHEMA := 1
const ALGORITHM := "trial-flow-samples-v1"
const SOURCE := "I2:trial_source"
const RECEIVER_A := "I2:trial_receiver_a"
const RECEIVER_B := "I2:trial_receiver_b"
const TO_A := "I2:trial_to_a"
const TO_B := "I2:trial_to_b"
const RETURN_A := "I2:trial_return_a"
const RETURN_B := "I2:trial_return_b"
const EDGES := [TO_A, TO_B, RETURN_A, RETURN_B]
const SAMPLE_ML := 20000
const DETENT_EPS := 0.005
const FACT_KEYS := ["selector_position", "sweep_clear", "powered", "takeover_remaining", "pulse_requested", "return_requested"]
const SAVE_KEYS := ["schema_version", "algorithm", "pending_usec", "fractional_usec", "facts", "phase", "credit_edge", "credit_method", "credit_usec", "samples", "ledger", "simulation"]
const SAMPLE_KEYS := ["clean_ml", "dirty_ml", "manual_ml", "pulse_ml", "first_tick", "last_tick"]
const PHASES := ["idle", "a", "neutral", "b", "reset", "done", "return"]
const INITIAL := {SOURCE:[160000,40000], RECEIVER_A:[0,0], RECEIVER_B:[0,0]}
const ENDPOINTS := {TO_A:[SOURCE,RECEIVER_A], TO_B:[SOURCE,RECEIVER_B], RETURN_A:[RECEIVER_A,SOURCE], RETURN_B:[RECEIVER_B,SOURCE]}

var _network = Water.new()
var _definition: Dictionary = {}
var _state: Dictionary = {}

func load_definition(path: String = DEFAULT_PATH) -> Dictionary:
	var candidate = Water.new()
	var loaded: Dictionary = candidate.load_definition(path)
	if not loaded.ok: return loaded
	return configure(candidate.definitions())

func configure(definition: Dictionary) -> Dictionary:
	var candidate = Water.new()
	var checked: Dictionary = candidate.configure(definition)
	if not checked.ok: return checked
	var normalized: Dictionary = candidate.definitions()
	if not _contract(normalized): return _result(false, "trial_definition_contract")
	_definition = normalized
	_network = candidate
	var ledger := {}
	for id in EDGES: ledger[id] = {"clean_ml":0, "dirty_ml":0}
	_state = {"schema_version":SCHEMA, "algorithm":ALGORITHM, "pending_usec":0,
		"fractional_usec":0.0, "facts":_closed_facts(), "phase":"idle",
		"credit_edge":"", "credit_method":"none", "credit_usec":0, "samples":{"A":_empty_sample(),"B":_empty_sample()},
		"ledger":ledger, "simulation":candidate.snapshot()}
	return _result(true, "configured")

func step(delta: float, facts: Dictionary, is_authority: bool = true, paused: bool = false) -> Dictionary:
	if _state.is_empty(): return _result(false, "not_configured")
	if not is_authority: return _result(false, "authority_required")
	if not _number(delta, 0.0, Water.MAX_DELTA): return _result(false, "invalid_delta")
	var checked := _validate_facts(facts)
	if not checked.ok: return checked
	if paused or delta == 0.0: return _view_result(_result(true, "paused"))
	var next: Dictionary = _state.duplicate(true)
	var current: Dictionary = checked.facts
	var precise := delta * 1000000.0 + float(next.fractional_usec)
	var remaining := int(floor(precise + 0.5))
	next.fractional_usec = precise - float(remaining)
	@warning_ignore("integer_division")
	var ticks: int = (int(next.pending_usec) + remaining) / Water.STEP_USEC
	if int(next.simulation.tick) > Water.MAX_COUNTER - ticks: return _result(false,"counter_limit")
	var candidate = _network.copy_for_trial()
	if not candidate.restore(next.simulation).ok: return _result(false,"candidate_invalid")
	var result := _result(true, "advanced")
	var control_usec := int(round(float(current.takeover_remaining) * 1000000.0))
	while remaining > 0:
		var portion := mini(remaining, Water.STEP_USEC - int(next.pending_usec))
		current.takeover_remaining = float(control_usec) / 1000000.0
		_sync_phase(next, current)
		var edge := _active_edge(next, current, candidate)
		var eligible := portion if not edge.is_empty() else 0
		if next.phase in ["a", "b"]: eligible = mini(eligible, control_usec)
		var method := "return" if edge in [RETURN_A,RETURN_B] else "pulse" if next.phase in ["a","b"] else "manual"
		# First authorized route/method owns this hydraulic tick. Other routes
		# wait for the next tick; previously earned microseconds are never lost.
		if eligible>0:
			if str(next.credit_edge)=="":
				next.credit_edge=edge
				next.credit_method=method
			if next.credit_edge==edge and next.credit_method==method:
				next.credit_usec+=eligible
		next.pending_usec += portion
		remaining -= portion
		control_usec = maxi(0, control_usec - portion)
		if int(next.pending_usec) == Water.STEP_USEC:
			var advanced := _tick(candidate, next)
			if not advanced.ok: return advanced
			result.ticks += 1
			result.moved_ml += int(advanced.moved_ml)
			result.new_samples.append_array(advanced.new_samples)
			next.pending_usec = 0
			next.credit_edge=""
			next.credit_method="none"
			next.credit_usec=0
	current.takeover_remaining = float(control_usec) / 1000000.0
	_sync_phase(next, current)
	next.facts = current.duplicate(true)
	next.simulation = candidate.snapshot()
	checked = validate_snapshot(next)
	if not checked.ok: return checked
	_network = candidate
	_state = next
	return _view_result(result)

func snapshot() -> Dictionary:
	return _state.duplicate(true)

## Current-instance scalar reads for the already-configured physics step.
## No cache, normalization, validation or hydraulic timing changes.
func desired_selector_for_step() -> Variant:
	return _desired(_state.phase)

func pending_usec_for_step() -> Variant:
	return _state.pending_usec

func return_complete_for_step() -> bool:
	return _volume(_network,RECEIVER_A)==0 and _volume(_network,RECEIVER_B)==0

func definitions() -> Dictionary:
	return _definition.duplicate(true)

func copy_for_trial():
	if not validate_snapshot(_state).ok: return null
	var result = get_script().new()
	result._definition = _definition.duplicate(true)
	result._network = _network.copy_for_trial()
	# Restore keeps the complete water validation and numeric normalization.
	if not result._network.restore(_state.simulation).ok: return null
	result._state = _state.duplicate(true)
	return result

func get_node(id: String) -> Dictionary:
	return _network.get_node(id)

func get_edge(id: String) -> Dictionary:
	return _network.get_edge(id)

func elapsed_seconds() -> float:
	if _state.is_empty(): return 0.0
	return _network.elapsed_seconds() + (float(_state.pending_usec) + float(_state.fractional_usec)) / 1000000.0

func status() -> Dictionary:
	if _state.is_empty(): return {}
	var samples: Dictionary = _state.samples.duplicate(true)
	for label in ["A", "B"]:
		samples[label]["moved_ml"] = _sample_volume(samples[label])
		samples[label]["complete"] = _sample_volume(samples[label]) == SAMPLE_ML
		samples[label]["source"] = SOURCE
		samples[label]["destination"] = RECEIVER_B if label == "A" else RECEIVER_A
	return {"phase":str(_state.phase), "desired_selector":_desired(_state.phase),
		"reason":_reason(), "samples":samples,
		"return_complete":_volume(_network,RECEIVER_A)==0 and _volume(_network,RECEIVER_B)==0,
		"both_samples_recorded":_complete(_state,"A") and _complete(_state,"B"),
		"elapsed_seconds":elapsed_seconds()}

func restore(saved: Dictionary) -> Dictionary:
	var checked := validate_snapshot(saved)
	if not checked.ok: return checked
	var candidate = _network.copy_for_trial()
	if not candidate.restore(saved.simulation).ok: return _result(false,"restore_network")
	_network = candidate
	_state = saved.duplicate(true)
	_state.schema_version=SCHEMA
	_state.facts = _validate_facts(saved.facts).facts
	_state.simulation = candidate.snapshot()
	_state.pending_usec=int(saved.pending_usec)
	_state.fractional_usec=float(saved.fractional_usec)
	_state.credit_usec=int(saved.credit_usec)
	for sample in _state.samples.values():
		for key in SAMPLE_KEYS: sample[key]=int(sample[key])
	for row in _state.ledger.values():
		row.clean_ml=int(row.clean_ml)
		row.dirty_ml=int(row.dirty_ml)
	return _view_result(_result(true,"restored"))

func validate_snapshot(saved: Dictionary) -> Dictionary:
	if _definition.is_empty(): return _result(false,"not_configured")
	if not _exact(saved,SAVE_KEYS): return _result(false,"snapshot_keys")
	if not _integer(saved.schema_version,SCHEMA,SCHEMA) or saved.algorithm != ALGORITHM: return _result(false,"snapshot_version")
	if not _integer(saved.pending_usec,0,Water.STEP_USEC-1) or not _number(saved.fractional_usec,-0.5,0.5) or float(saved.fractional_usec)>=0.5: return _result(false,"snapshot_clock")
	if not saved.facts is Dictionary or not _validate_facts(saved.facts).ok: return _result(false,"snapshot_facts")
	if not saved.phase is String or saved.phase not in PHASES: return _result(false,"snapshot_phase")
	if not saved.simulation is Dictionary: return _result(false,"snapshot_simulation")
	var checked: Dictionary = _network.validate_snapshot(saved.simulation)
	if not checked.ok: return checked
	var tick := int(saved.simulation.tick)
	if int(saved.simulation.pending_usec)!=0 or (tick==0 and int(saved.pending_usec)==0 and float(saved.fractional_usec)<0.0): return _result(false,"snapshot_nested_clock")
	if not saved.credit_edge is String or (saved.credit_edge!="" and saved.credit_edge not in EDGES) or not _integer(saved.credit_usec,0,int(saved.pending_usec)): return _result(false,"snapshot_credit")
	if saved.credit_edge=="":
		if saved.credit_method!="none" or int(saved.credit_usec)!=0: return _result(false,"snapshot_credit_empty")
	elif int(saved.credit_usec)==0 or (saved.credit_edge in [TO_A,TO_B] and saved.credit_method not in ["manual","pulse"]) or (saved.credit_edge in [RETURN_A,RETURN_B] and saved.credit_method!="return"): return _result(false,"snapshot_credit_method")
	if not saved.ledger is Dictionary or not _exact(saved.ledger,EDGES) or not saved.samples is Dictionary or not _exact(saved.samples,["A","B"]): return _result(false,"snapshot_evidence_keys")
	var balance := INITIAL.duplicate(true)
	var total_transferred := 0
	var last_transferred := 0
	for id in EDGES:
		var row: Variant = saved.ledger[id]
		if not row is Dictionary or not _exact(row,["clean_ml","dirty_ml"]): return _result(false,"ledger_keys")
		for component in [0,1]:
			var key: String = "clean_ml" if component==0 else "dirty_ml"
			if not _integer(row[key],0,tick*1000): return _result(false,"ledger_range")
			balance[ENDPOINTS[id][0]][component] -= int(row[key])
			balance[ENDPOINTS[id][1]][component] += int(row[key])
			total_transferred += int(row[key])
		var edge: Dictionary = saved.simulation.edges[id]
		if int(edge.open_permille)!=0 or edge.powered or int(edge.flow_carry)!=0: return _result(false,"snapshot_internal_controls")
		if int(edge.last_transfer_ml)>1000 or int(edge.last_direction) not in [0,1]: return _result(false,"snapshot_last_transfer")
		if (int(edge.last_transfer_ml)==0) != (int(edge.last_direction)==0): return _result(false,"snapshot_last_direction")
		last_transferred += int(edge.last_transfer_ml)
	if total_transferred>tick*1000 or last_transferred>1000: return _result(false,"ledger_rate")
	for id in INITIAL:
		if int(saved.simulation.nodes[id].clean_ml)!=int(balance[id][0]) or int(saved.simulation.nodes[id].dirty_ml)!=int(balance[id][1]): return _result(false,"ledger_balance")
	for label in ["A","B"]:
		var sample: Variant = saved.samples[label]
		if not sample is Dictionary or not _exact(sample,SAMPLE_KEYS): return _result(false,"sample_keys")
		for key in ["clean_ml","dirty_ml","manual_ml","pulse_ml"]:
			if not _integer(sample[key],0,SAMPLE_ML): return _result(false,"sample_range")
		var edge: String = TO_B if label=="A" else TO_A
		var total: int = int(saved.ledger[edge].clean_ml)+int(saved.ledger[edge].dirty_ml)
		var amount := _sample_volume(sample)
		if amount!=mini(total,SAMPLE_ML) or int(sample.manual_ml)+int(sample.pulse_ml)!=amount: return _result(false,"sample_total")
		if int(sample.clean_ml)>int(saved.ledger[edge].clean_ml) or int(sample.dirty_ml)>int(saved.ledger[edge].dirty_ml): return _result(false,"sample_components")
		if not _integer(sample.first_tick,0,tick) or not _integer(sample.last_tick,0,tick): return _result(false,"sample_time")
		if amount==0:
			if sample.first_tick!=0 or sample.last_tick!=0: return _result(false,"sample_empty_time")
		elif not _integer(sample.first_tick,1,tick) or not _integer(sample.last_tick,int(sample.first_tick),tick): return _result(false,"sample_time")
	# The live network above already performs the complete snapshot check.
	# Keep definition consistency without building/restoring another unused
	# network; no state from that former temporary object entered validation.
	if _definition != _network.definitions(): return _result(false,"validation_network")
	var projected: Dictionary = saved.duplicate(true)
	_sync_phase(projected,saved.facts)
	if projected.phase!=saved.phase: return _result(false,"snapshot_phase_facts")
	return _result(true,"valid")

# Exactly one call to Water.step(.1) per real hydraulic tick. Permille is
# the fraction of this tick actually authorized at the selected physical route.
func _tick(network, state: Dictionary) -> Dictionary:
	var edge := str(state.credit_edge)
	@warning_ignore("integer_division")
	var permille: int = int(state.credit_usec)/100
	if edge!="" and state.credit_method=="pulse":
		var label: String = "A" if edge==TO_B else "B"
		permille=mini(permille,SAMPLE_ML-_sample_volume(state.samples[label]))
	var commands := {}
	for id in EDGES:
		commands[id]={"open_permille":0}
		if id in [RETURN_A,RETURN_B]: commands[id]["powered"]=false
	if edge!="" and permille>0:
		commands[edge].open_permille=permille
		if edge in [RETURN_A,RETURN_B]: commands[edge].powered=true
	var before: Dictionary = network.snapshot()
	var advanced: Dictionary = network.step(0.1,commands)
	if not advanced.ok: return advanced
	var after: Dictionary = network.snapshot()
	var result := _result(true,"tick")
	if edge!="" and permille>0:
		var source: String = ENDPOINTS[edge][0]
		var destination: String = ENDPOINTS[edge][1]
		var clean := int(before.nodes[source].clean_ml)-int(after.nodes[source].clean_ml)
		var dirty := int(before.nodes[source].dirty_ml)-int(after.nodes[source].dirty_ml)
		if clean<0 or dirty<0 or clean+dirty>permille or int(after.nodes[destination].clean_ml)-int(before.nodes[destination].clean_ml)!=clean or int(after.nodes[destination].dirty_ml)-int(before.nodes[destination].dirty_ml)!=dirty: return _result(false,"tick_difference")
		state.ledger[edge].clean_ml+=clean
		state.ledger[edge].dirty_ml+=dirty
		result.moved_ml=clean+dirty
		if edge in [TO_A,TO_B] and clean+dirty>0:
			var label: String = "A" if edge==TO_B else "B"
			var sample: Dictionary = state.samples[label]
			var room := SAMPLE_ML-_sample_volume(sample)
			var accepted := mini(room,clean+dirty)
			if accepted>0:
				@warning_ignore("integer_division")
				var credited_clean: int = clean*accepted/(clean+dirty)
				sample.clean_ml+=credited_clean
				sample.dirty_ml+=accepted-credited_clean
				sample["pulse_ml" if state.credit_method=="pulse" else "manual_ml"]+=accepted
				if int(sample.first_tick)==0: sample.first_tick=int(after.tick)
				sample.last_tick=int(after.tick)
				if accepted==room: result.new_samples.append(label)
	for id in EDGES:
		after.edges[id].open_permille=0
		after.edges[id].powered=false
		after.edges[id].flow_carry=0
	var closed: Dictionary = network.restore(after)
	if not closed.ok: return closed
	return result

func _sync_phase(state: Dictionary, facts: Dictionary) -> void:
	var neutral: bool = _at(facts,0.0) and facts.sweep_clear
	var authorized: bool = facts.powered and float(facts.takeover_remaining)>0.0
	if facts.return_requested:
		state.phase="return"
		return
	if state.phase=="return": state.phase="reset"
	if not facts.pulse_requested:
		if state.phase!="idle": state.phase="idle" if neutral else "reset"
		return
	if not authorized:
		state.phase="reset"
		return
	if state.phase=="idle" or (state.phase=="reset" and neutral):
		state.phase="a" if not _complete(state,"A") else "b" if not _complete(state,"B") else "done"
	if state.phase=="a" and _complete(state,"A"): state.phase="neutral"
	if state.phase=="neutral" and neutral: state.phase="b" if not _complete(state,"B") else "done"
	if state.phase=="b" and _complete(state,"B"): state.phase="done" if neutral else "reset"

func _active_edge(state: Dictionary, facts: Dictionary, network) -> String:
	if not facts.sweep_clear: return ""
	if state.phase=="return":
		if not facts.powered or not _at(facts,0.0): return ""
		if _volume(network,RECEIVER_A)>0: return RETURN_A
		if _volume(network,RECEIVER_B)>0: return RETURN_B
		return ""
	if state.phase=="idle" and not facts.pulse_requested:
		if _at(facts,-1.0): return TO_B
		if _at(facts,1.0): return TO_A
	if facts.powered and float(facts.takeover_remaining)>0.0:
		if state.phase=="a" and _at(facts,-1.0): return TO_B
		if state.phase=="b" and _at(facts,1.0): return TO_A
	return ""

func _reason() -> String:
	var facts: Dictionary = _state.facts
	if not facts.sweep_clear: return "mechanism_blocked"
	var edge := _active_edge(_state,facts,_network)
	var method := "return" if edge in [RETURN_A,RETURN_B] else "pulse" if _state.phase in ["a","b"] else "manual"
	if edge!="" and str(_state.credit_edge)!="" and (edge!=str(_state.credit_edge) or method!=str(_state.credit_method)): return "switching_settle"
	if _state.phase=="done": return "pulse_complete"
	if _state.phase=="reset":
		if facts.pulse_requested and not facts.powered: return "unpowered"
		if facts.pulse_requested and float(facts.takeover_remaining)<=0.0: return "takeover_expired"
		return "reset_to_neutral"
	if _state.phase=="return":
		if not facts.powered: return "unpowered"
		if not _at(facts,0.0): return "waiting_for_neutral"
		return "return_complete" if _volume(_network,RECEIVER_A)+_volume(_network,RECEIVER_B)==0 else "returning"
	if edge.is_empty(): return "waiting_for_detent" if _state.phase!="idle" else "neutral"
	return "source_empty" if _volume(_network,SOURCE)==0 else "flowing"

func _validate_facts(value: Dictionary) -> Dictionary:
	if not _exact(value,FACT_KEYS): return _result(false,"fact_keys")
	if not _number(value.selector_position,-1.0,1.0) or not _number(value.takeover_remaining,0.0,8.0): return _result(false,"fact_range")
	for key in ["sweep_clear","powered","pulse_requested","return_requested"]:
		if not value[key] is bool: return _result(false,"fact_type")
	if value.pulse_requested and value.return_requested: return _result(false,"request_interlock")
	var normalized: Dictionary = value.duplicate(true)
	normalized.selector_position=float(value.selector_position)
	normalized.takeover_remaining=float(round(float(value.takeover_remaining)*1000000.0))/1000000.0
	return {"ok":true,"code":"valid","facts":normalized}

func _contract(definition: Dictionary) -> bool:
	if definition.id!="I2:trial_flow_v1" or int(definition.version)!=1 or definition.nodes.size()!=3 or definition.edges.size()!=4: return false
	for node in definition.nodes:
		if not INITIAL.has(node.id) or int(node.capacity_ml)!=200000 or int(node.clean_ml)!=int(INITIAL[node.id][0]) or int(node.dirty_ml)!=int(INITIAL[node.id][1]): return false
		if int(node.base_mm)!=(1400 if node.id==SOURCE else 250) or int(node.area_cm2)!=(4000 if node.id==SOURCE else 2000): return false
	for edge in definition.edges:
		if edge.id not in EDGES or edge.from!=ENDPOINTS[edge.id][0] or edge.to!=ENDPOINTS[edge.id][1] or edge.bidirectional or edge.initial_powered or int(edge.initial_open_permille)!=0 or int(edge.max_rate_ml_s)!=10000: return false
		var gravity: bool = edge.id in [TO_A,TO_B]
		if edge.kind!=("gravity" if gravity else "pump") or int(edge.conductance_ml_s_per_mm)!=(100 if gravity else 0) or int(edge.pump_head_mm)!=(0 if gravity else 2000): return false
	return true

func _view_result(result: Dictionary) -> Dictionary:
	var view := status()
	result["desired_selector"]=view.get("desired_selector")
	result["reason"]=view.get("reason","")
	return result

static func _closed_facts() -> Dictionary:
	return {"selector_position":0.0,"sweep_clear":true,"powered":false,"takeover_remaining":0.0,"pulse_requested":false,"return_requested":false}

static func _empty_sample() -> Dictionary:
	return {"clean_ml":0,"dirty_ml":0,"manual_ml":0,"pulse_ml":0,"first_tick":0,"last_tick":0}

static func _sample_volume(sample: Dictionary) -> int:
	return int(sample.clean_ml)+int(sample.dirty_ml)

static func _complete(state: Dictionary, label: String) -> bool:
	return _sample_volume(state.samples[label])==SAMPLE_ML

static func _desired(phase: String) -> Variant:
	if phase=="idle": return null
	return -1.0 if phase=="a" else 1.0 if phase=="b" else 0.0

static func _volume(network, id: String) -> int:
	return int(network.get_node(id).volume_ml)

static func _at(facts: Dictionary, target: float) -> bool:
	return absf(float(facts.selector_position)-target)<=DETENT_EPS

static func _exact(value: Dictionary, keys: Array) -> bool:
	if value.size()!=keys.size(): return false
	for key in value:
		if not key is String or key not in keys: return false
	return true

static func _number(value: Variant, low: float, high: float) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and float(value)>=low and float(value)<=high

static func _integer(value: Variant, low: int, high: int) -> bool:
	return _number(value,float(low),float(high)) and float(value)==floor(float(value))

static func _result(ok: bool, code: String) -> Dictionary:
	return {"ok":ok,"code":code,"ticks":0,"moved_ml":0,"new_samples":[]}
