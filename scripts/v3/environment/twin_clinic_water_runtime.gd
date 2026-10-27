class_name TwinClinicWaterRuntime
extends RefCounted
## Independent host rules only. No scene, collision, task, reward, save or clock IO.
## Facts must come from a future authoritative physical actuator adapter.

const Water = preload("res://scripts/v3/gameplay/environment/twin_water_network.gd")
const DEFAULT_PATH := "res://data/v3/environment/i2_clinic_water_network.json"
const SCHEMA := 1
const ALGORITHM := "clinic-float-cutoff-v1"
const TARGET_ML := 2000000
const SOURCE := "I2:clean_cistern"
const CLINIC := "I2:clinic_tank"
const GRAVITY := "I2:clean_to_clinic"
const PUMP := "I2:clean_pump_to_clinic"
const FACT_KEYS := ["gravity_open_permille", "pump_open_permille", "pump_powered", "platform_blocked"]
const SAVE_KEYS := ["schema_version", "algorithm", "pending_usec", "fractional_usec", "facts", "simulation"]
# Capacity / base / area / initial clean / initial dirty. This bounded adapter
# deliberately rejects the earlier study topology and its smaller clinic tank.
const NODE_CONTRACT := {
	SOURCE:[4800000, 6000, 16000, 3200000, 0],
	CLINIC:[4000000, 3500, 20000, 0, 0],
	"I2:rain_tank":[800000, 2000, 4000, 60000, 240000],
	"I2:waste_sump":[1200000, -2000, 6000, 10000, 190000]
}

var _network = Water.new()
var _definition: Dictionary = {}
var _pending_usec := 0
var _fractional_usec := 0.0
var _facts: Dictionary = _closed_facts()

func load_definition(path: String = DEFAULT_PATH) -> Dictionary:
	if not FileAccess.file_exists(path): return _result(false, "definition_missing")
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null: return _result(false, "definition_unreadable")
	if file.get_length() > 65536:
		file.close()
		return _result(false, "definition_too_large")
	var raw: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	if not raw is Dictionary: return _result(false, "invalid_definition_json")
	return configure(raw)

func configure(definition: Dictionary) -> Dictionary:
	var candidate = Water.new()
	var checked: Dictionary = candidate.configure(definition)
	if not checked.ok: return checked
	var normalized: Dictionary = candidate.definitions()
	if not _clinic_contract(normalized): return _result(false, "clinic_definition_contract")
	_network = candidate
	_definition = normalized
	_pending_usec = 0
	_fractional_usec = 0.0
	_facts = _closed_facts()
	return _result(true, "configured")

# The complete current physical sample, not a partial command patch. Both
# positive valve positions are a fault even if the pump has no power.
func step(delta: float, facts: Variant, is_authority: bool = true, paused: bool = false) -> Dictionary:
	if _definition.is_empty(): return _result(false, "not_configured")
	if not is_authority: return _result(false, "authority_required")
	if not is_finite(delta) or delta < 0.0 or delta > Water.MAX_DELTA: return _result(false, "invalid_delta")
	var fact_check := _validate_facts(facts)
	if not fact_check.ok: return fact_check
	if paused or delta == 0.0: return _result(true, "paused")
	# Carry the sub-microsecond rounding error instead of rounding each frame
	# independently. Only bounded remainders use floats; reservoir values are ints.
	var precise_usec := delta * 1000000.0 + _fractional_usec
	var whole_usec := int(floor(precise_usec + 0.5))
	var next_fraction := precise_usec - float(whole_usec)
	var budget := _pending_usec + whole_usec
	@warning_ignore("integer_division")
	var ticks: int = budget / Water.STEP_USEC
	var current: Dictionary = _network.snapshot()
	if int(current.tick) > Water.MAX_COUNTER - ticks: return _result(false, "counter_limit")
	# Every trial tick and cutoff is validated on an isolated instance. A later
	# rejection cannot leave an earlier tick, new controls or clock committed.
	var candidate = Water.new()
	var configured: Dictionary = candidate.configure(_definition)
	if not configured.ok: return _result(false, "candidate_definition")
	var loaded: Dictionary = candidate.restore(current)
	if not loaded.ok: return _result(false, "candidate_restore")
	var normalized: Dictionary = fact_check.facts
	var installed := _install_effective_controls(candidate, normalized)
	if not installed.ok: return installed
	var result := _result(true, "advanced")
	for unused in range(ticks):
		var advanced := _one_tick(candidate, normalized)
		if not advanced.ok: return advanced
		result.ticks += 1
		result.moved_ml += int(advanced.moved_ml)
		result.cutoff_clamped_ml += int(advanced.cutoff_clamped_ml)
	var next_state := {
		"schema_version":SCHEMA, "algorithm":ALGORITHM,
		"pending_usec":budget % Water.STEP_USEC, "fractional_usec":next_fraction,
		"facts":normalized, "simulation":candidate.snapshot()
	}
	var validated := validate_snapshot(next_state)
	if not validated.ok: return validated
	_network = candidate
	_pending_usec = int(next_state.pending_usec)
	_fractional_usec = next_fraction
	_facts = normalized.duplicate(true)
	result["reason"] = status().reason
	return result

func definitions() -> Dictionary:
	return _definition.duplicate(true)

func get_node(id: String) -> Dictionary:
	return _network.get_node(id)

func get_edge(id: String) -> Dictionary:
	return _network.get_edge(id)

func elapsed_seconds() -> float:
	return _network.elapsed_seconds() + (float(_pending_usec) + _fractional_usec) / 1000000.0

# desired_deck_top_m is a hydraulic setpoint, NOT a physical body position.
# This API deliberately has no task-complete / commissioned / traversable flag.
func status() -> Dictionary:
	if _definition.is_empty(): return {}
	var clinic: Dictionary = _network.get_node(CLINIC)
	var gravity: Dictionary = _network.get_edge(GRAVITY)
	var pump: Dictionary = _network.get_edge(PUMP)
	var cutoff: bool = int(clinic.volume_ml) == TARGET_ML
	var route := "none"
	if int(_facts.gravity_open_permille) > 0: route = "gravity"
	elif int(_facts.pump_open_permille) > 0: route = "pump"
	var reason := "closed"
	if cutoff: reason = "target_reached"
	elif bool(_facts.platform_blocked): reason = "platform_blocked"
	elif route == "gravity": reason = str(gravity.eligibility)
	elif route == "pump": reason = str(pump.eligibility)
	return {
		"clinic_volume_ml":int(clinic.volume_ml), "target_volume_ml":TARGET_ML,
		"clinic_level_m":float(clinic.level_m), "clean_fraction":float(clinic.clean_fraction),
		"desired_deck_top_m":float(clinic.level_m) + 0.5,
		"automatic_cutoff":cutoff, "platform_blocked":bool(_facts.platform_blocked),
		"selected_route":route, "reason":reason,
		"effective_controls":_controls_for(_facts, int(clinic.volume_ml)),
		"inlet_closed":int(gravity.open_permille) == 0 and int(pump.open_permille) == 0,
		"last_tick_transfer_ml":int(gravity.last_transfer_ml) + int(pump.last_transfer_ml),
		"elapsed_seconds":elapsed_seconds()
	}

func snapshot() -> Dictionary:
	if _definition.is_empty(): return {}
	return {"schema_version":SCHEMA, "algorithm":ALGORITHM, "pending_usec":_pending_usec,
		"fractional_usec":_fractional_usec, "facts":_facts.duplicate(true), "simulation":_network.snapshot()}

func validate_snapshot(saved: Dictionary) -> Dictionary:
	if _definition.is_empty(): return _result(false, "not_configured")
	if not _exact_keys(saved, SAVE_KEYS): return _result(false, "snapshot_keys")
	if not _integer(saved.schema_version, SCHEMA, SCHEMA) or saved.algorithm != ALGORITHM: return _result(false, "snapshot_schema")
	if not _integer(saved.pending_usec, 0, Water.STEP_USEC - 1): return _result(false, "snapshot_clock")
	if not _number(saved.fractional_usec) or float(saved.fractional_usec) < -0.5 or float(saved.fractional_usec) >= 0.5: return _result(false, "snapshot_fraction")
	var checked := _validate_facts(saved.facts)
	if not checked.ok: return checked
	if not saved.simulation is Dictionary: return _result(false, "snapshot_simulation")
	checked = _network.validate_snapshot(saved.simulation)
	if not checked.ok: return checked
	if int(saved.simulation.pending_usec) != 0: return _result(false, "nested_clock_remainder")
	if int(saved.simulation.tick) == 0 and int(saved.pending_usec) == 0 and float(saved.fractional_usec) < 0.0: return _result(false, "negative_elapsed")
	var volume := _saved_volume(saved.simulation, CLINIC)
	if volume > TARGET_ML: return _result(false, "snapshot_above_cutoff")
	var expected := _controls_for(saved.facts, volume)
	for id in [GRAVITY, PUMP]:
		var edge: Dictionary = saved.simulation.edges[id]
		if int(edge.open_permille) != int(expected[id].open_permille) or edge.powered != expected[id].powered: return _result(false, "snapshot_effective_controls")
		if int(edge.open_permille) == 0 or (id == PUMP and not edge.powered):
			if int(edge.flow_carry) != 0: return _result(false, "snapshot_blocked_budget")
	return _result(true, "valid")

func restore(saved: Dictionary) -> Dictionary:
	var checked := validate_snapshot(saved)
	if not checked.ok: return checked
	# Core restore is also validate-before-write. All outer state changes follow it.
	checked = _network.restore(saved.simulation)
	if not checked.ok: return checked
	_pending_usec = int(saved.pending_usec)
	_fractional_usec = float(saved.fractional_usec)
	_facts = _validate_facts(saved.facts).facts
	return _result(true, "restored")

@warning_ignore("integer_division")
func _one_tick(candidate, facts: Dictionary) -> Dictionary:
	var before: Dictionary = candidate.snapshot()
	var remaining := TARGET_ML - _saved_volume(before, CLINIC)
	# Effective edge STATE was installed before the first tick and again after
	# every prior tick. It contains gravity powered:false for snapshot integrity;
	# that field is intentionally illegal in the core's gravity COMMAND schema.
	# Advance the already validated state without reinterpreting it as commands.
	var advanced: Dictionary = candidate.step(0.1)
	if not advanced.ok: return advanced
	var after: Dictionary = candidate.snapshot()
	var moved := _saved_volume(after, CLINIC) - _saved_volume(before, CLINIC)
	var clamped := 0
	if moved > remaining:
		# One mutually exclusive inlet only. Model an ideal float valve closing
		# within this final tick; do not falsify the tank's physical 4000 L capacity.
		var source_volume := _saved_volume(before, SOURCE)
		if source_volume <= 0 or remaining < 0: return _result(false, "cutoff_source")
		var clean: int = int(before.nodes[SOURCE].clean_ml) * remaining / source_volume
		var dirty := remaining - clean
		after.nodes[SOURCE] = {"clean_ml":int(before.nodes[SOURCE].clean_ml) - clean, "dirty_ml":int(before.nodes[SOURCE].dirty_ml) - dirty}
		after.nodes[CLINIC] = {"clean_ml":int(before.nodes[CLINIC].clean_ml) + clean, "dirty_ml":int(before.nodes[CLINIC].dirty_ml) + dirty}
		var active: String = GRAVITY if int(after.edges[GRAVITY].last_transfer_ml) > 0 else PUMP
		var inactive: String = PUMP if active == GRAVITY else GRAVITY
		if int(after.edges[inactive].last_transfer_ml) != 0: return _result(false, "cutoff_interlock")
		after.edges[active].last_transfer_ml = remaining
		after.edges[active].last_direction = 1 if remaining > 0 else 0
		after.edges[active].flow_carry = 0
		clamped = moved - remaining
		moved = remaining
		var restored: Dictionary = candidate.restore(after)
		if not restored.ok: return restored
	var controls := _install_effective_controls(candidate, facts)
	if not controls.ok: return controls
	var result := _result(true, "tick")
	result.moved_ml = moved
	result.cutoff_clamped_ml = clamped
	return result

func _install_effective_controls(candidate, facts: Dictionary) -> Dictionary:
	var saved: Dictionary = candidate.snapshot()
	var controls := _controls_for(facts, _saved_volume(saved, CLINIC))
	for id in [GRAVITY, PUMP]:
		saved.edges[id].open_permille = int(controls[id].open_permille)
		saved.edges[id].powered = bool(controls[id].powered)
		if int(controls[id].open_permille) == 0 or (id == PUMP and not controls[id].powered):
			saved.edges[id].flow_carry = 0
	return candidate.restore(saved)

func _controls_for(facts: Dictionary, clinic_volume: int) -> Dictionary:
	var stop: bool = bool(facts.platform_blocked) or clinic_volume >= TARGET_ML
	return {
		GRAVITY:{"open_permille":0 if stop else int(facts.gravity_open_permille), "powered":false},
		PUMP:{"open_permille":0 if stop else int(facts.pump_open_permille), "powered":bool(facts.pump_powered)}
	}

func _validate_facts(value: Variant) -> Dictionary:
	if not value is Dictionary or not _exact_keys(value, FACT_KEYS): return _result(false, "fact_keys")
	if not _integer(value.gravity_open_permille, 0, 1000) or not _integer(value.pump_open_permille, 0, 1000): return _result(false, "invalid_valve")
	if not value.pump_powered is bool or not value.platform_blocked is bool: return _result(false, "invalid_fact_type")
	if int(value.gravity_open_permille) > 0 and int(value.pump_open_permille) > 0: return _result(false, "interlock_conflict")
	return {"ok":true, "code":"valid", "facts":{
		"gravity_open_permille":int(value.gravity_open_permille), "pump_open_permille":int(value.pump_open_permille),
		"pump_powered":bool(value.pump_powered), "platform_blocked":bool(value.platform_blocked)}}

func _clinic_contract(definition: Dictionary) -> bool:
	if definition.id != "I2:clinic_network_v1" or definition.nodes.size() != 4 or definition.edges.size() != 2: return false
	for node in definition.nodes:
		if not NODE_CONTRACT.has(node.id): return false
		var actual := [node.capacity_ml, node.base_mm, node.area_cm2, node.clean_ml, node.dirty_ml]
		if actual != NODE_CONTRACT[node.id]: return false
	for edge in definition.edges:
		if edge.id not in [GRAVITY, PUMP] or edge.from != SOURCE or edge.to != CLINIC: return false
		if edge.bidirectional or edge.initial_powered or int(edge.initial_open_permille) != 0: return false
		if edge.id == GRAVITY and (edge.kind != "gravity" or int(edge.max_rate_ml_s) != 50000 or int(edge.conductance_ml_s_per_mm) != 20): return false
		if edge.id == PUMP and (edge.kind != "pump" or int(edge.max_rate_ml_s) != 30000 or int(edge.pump_head_mm) != 4500): return false
	return true

static func _closed_facts() -> Dictionary:
	return {"gravity_open_permille":0, "pump_open_permille":0, "pump_powered":false, "platform_blocked":false}

func _saved_volume(saved: Dictionary, id: String) -> int:
	return int(saved.nodes[id].clean_ml) + int(saved.nodes[id].dirty_ml)

func _exact_keys(value: Dictionary, keys: Array) -> bool:
	if value.size() != keys.size(): return false
	for key in value:
		if not key is String or not keys.has(key): return false
	return true

func _number(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value))

func _integer(value: Variant, minimum: int, maximum: int) -> bool:
	return _number(value) and float(value) >= float(minimum) and float(value) <= float(maximum) and floor(float(value)) == float(value)

func _result(ok: bool, code: String) -> Dictionary:
	return {"ok":ok, "code":code, "ticks":0, "moved_ml":0, "cutoff_clamped_ml":0}
