class_name TwinWaterNetwork
extends RefCounted
## Bounded, host-owned reservoir study. No Nodes, clocks, rewards or save writes.
## clean_ml / dirty_ml are equal-density fluid components, not chemical purity.

const DEFAULT_PATH := "res://data/v3/environment/i2_water_network_study.json"
const SCHEMA := 1
const ALGORITHM := "bounded-mix-v1"
const STEP_USEC := 100000
const MAX_DELTA := 5.0
const MAX_COUNTER := 2147483647
const MAX_CAPACITY := 5000000
const MAX_RATE := 50000
const NODE_KEYS := ["id", "capacity_ml", "clean_ml", "dirty_ml", "base_mm", "area_cm2"]
const EDGE_KEYS := ["id", "from", "to", "kind", "max_rate_ml_s", "conductance_ml_s_per_mm", "pump_head_mm", "initial_open_permille", "initial_powered", "bidirectional"]
const EDGE_STATE_KEYS := ["open_permille", "powered", "flow_carry", "last_direction", "last_transfer_ml"]

var _definition: Dictionary = {}
var _nodes: Dictionary = {}
var _edges: Dictionary = {}
var _state: Dictionary = {}
var _digest := ""
var _initial_clean := 0
var _initial_dirty := 0

func load_definition(path: String = DEFAULT_PATH) -> Dictionary:
	if not FileAccess.file_exists(path): return _result(false, "definition_missing")
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null: return _result(false, "definition_unreadable")
	if file.get_length() > 65536:
		file.close()
		return _result(false, "definition_too_large")
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	if not parsed is Dictionary: return _result(false, "invalid_definition_json")
	return configure(parsed)

func configure(definition: Dictionary) -> Dictionary:
	var checked := _validate_definition(definition)
	if not checked.ok: return checked
	_definition = checked.definition
	_nodes = checked.nodes
	_edges = checked.edges
	_digest = JSON.stringify(_definition, "", true, true).sha256_text()
	_initial_clean = 0
	_initial_dirty = 0
	_state = {"schema_version":SCHEMA, "algorithm":ALGORITHM,
		"definition_id":_definition.id, "definition_version":_definition.version,
		"definition_digest":_digest, "tick":0, "pending_usec":0, "nodes":{}, "edges":{}}
	for id in _sorted(_nodes):
		var node: Dictionary = _nodes[id]
		_initial_clean += int(node.clean_ml)
		_initial_dirty += int(node.dirty_ml)
		_state.nodes[id] = {"clean_ml":int(node.clean_ml), "dirty_ml":int(node.dirty_ml)}
	for id in _sorted(_edges):
		var edge: Dictionary = _edges[id]
		_state.edges[id] = {"open_permille":int(edge.initial_open_permille), "powered":edge.initial_powered,
			"flow_carry":0, "last_direction":0, "last_transfer_ml":0}
	return _result(true, "configured")

func definitions() -> Dictionary:
	return _definition.duplicate(true)

func snapshot() -> Dictionary:
	return _state.duplicate(true)

## A private simulation candidate; authored definitions were normalized at
## configure. Copy every dictionary so rejected trials cannot mutate the source.
## Callers still use the original restore/validate_snapshot before adoption.
func copy_for_trial():
	var result = get_script().new()
	result._definition = _definition.duplicate(true)
	result._nodes = _nodes.duplicate(true)
	result._edges = _edges.duplicate(true)
	result._state = _state.duplicate(true)
	result._digest = _digest
	result._initial_clean = _initial_clean
	result._initial_dirty = _initial_dirty
	return result

func elapsed_seconds() -> float:
	return float(_state.get("tick", 0)) * 0.1 + float(_state.get("pending_usec", 0)) / 1000000.0

func get_node(id: String) -> Dictionary:
	if not _nodes.has(id): return {}
	var out: Dictionary = _nodes[id].duplicate(true)
	out.merge(_state.nodes[id], true)
	out["volume_ml"] = _volume(id)
	out["level_m"] = _head_mm(id) / 1000.0
	out["clean_fraction"] = float(out.clean_ml) / float(out.volume_ml) if out.volume_ml > 0 else 0.0
	return out

func get_edge(id: String) -> Dictionary:
	if not _edges.has(id): return {}
	var out: Dictionary = _edges[id].duplicate(true)
	out.merge(_state.edges[id], true)
	out["last_flow_l_s"] = float(out.last_transfer_ml) / 100.0
	out["eligibility"] = _desired_direction(_edges[id], _state.edges[id]).code
	return out

# Dictionary form: {edge_id:{open_permille:..., powered:...}}.
# Array form: [{edge_id:..., open_permille:..., powered:...}] rejects repeated IDs.
# An adapter decoding raw JSON must reject duplicate object keys before constructing a Dictionary.
func step(delta: float, controls: Variant = {}, is_authority: bool = true, paused: bool = false) -> Dictionary:
	if _state.is_empty(): return _result(false, "not_configured")
	if not is_authority: return _result(false, "authority_required")
	if not is_finite(delta) or delta < 0.0 or delta > MAX_DELTA: return _result(false, "invalid_delta")
	var checked := _validate_controls(controls)
	if not checked.ok: return checked
	if paused or delta == 0.0: return _result(true, "paused")
	var added_usec := int(round(delta * 1000000.0))
	@warning_ignore("integer_division")
	var needed: int = (int(_state.pending_usec) + added_usec) / STEP_USEC
	if int(_state.tick) > MAX_COUNTER - needed: return _result(false, "counter_limit")
	# All rejection paths precede mutations, including partial command batches.
	for id in checked.controls:
		for key in checked.controls[id]: _state.edges[id][key] = checked.controls[id][key]
	_state.pending_usec += added_usec
	var result := _result(true, "advanced")
	while int(_state.pending_usec) >= STEP_USEC:
		_state.pending_usec -= STEP_USEC
		_state.tick += 1
		result.ticks += 1
		result.moved_ml += _tick()
	return result

func validate_snapshot(saved: Dictionary) -> Dictionary:
	if _state.is_empty(): return _result(false, "not_configured")
	if not _exact_keys(saved, ["schema_version", "algorithm", "definition_id", "definition_version", "definition_digest", "tick", "pending_usec", "nodes", "edges"]): return _result(false, "snapshot_keys")
	if not _integer(saved.schema_version, SCHEMA, SCHEMA) or saved.algorithm != ALGORITHM: return _result(false, "snapshot_schema")
	if saved.definition_id != _definition.id or not _integer(saved.definition_version, int(_definition.version), int(_definition.version)) or saved.definition_digest != _digest: return _result(false, "definition_mismatch")
	if not _integer(saved.tick, 0, MAX_COUNTER) or not _integer(saved.pending_usec, 0, STEP_USEC - 1): return _result(false, "snapshot_clock")
	if not saved.nodes is Dictionary or not saved.edges is Dictionary: return _result(false, "snapshot_types")
	if not _exact_keys(saved.nodes, _nodes.keys()) or not _exact_keys(saved.edges, _edges.keys()): return _result(false, "snapshot_ids")
	var clean_total := 0
	var dirty_total := 0
	for id in _sorted(_nodes):
		var value: Variant = saved.nodes[id]
		if not value is Dictionary or not _exact_keys(value, ["clean_ml", "dirty_ml"]): return _result(false, "snapshot_node")
		var capacity: int = _nodes[id].capacity_ml
		if not _integer(value.clean_ml, 0, capacity) or not _integer(value.dirty_ml, 0, capacity): return _result(false, "snapshot_quantity")
		if int(value.clean_ml) + int(value.dirty_ml) > capacity: return _result(false, "snapshot_capacity")
		clean_total += int(value.clean_ml)
		dirty_total += int(value.dirty_ml)
	if clean_total != _initial_clean or dirty_total != _initial_dirty: return _result(false, "snapshot_conservation")
	for id in _sorted(_edges):
		var value: Variant = saved.edges[id]
		var edge: Dictionary = _edges[id]
		if not value is Dictionary or not _exact_keys(value, EDGE_STATE_KEYS): return _result(false, "snapshot_edge")
		if not _integer(value.open_permille, 0, 1000) or not value.powered is bool: return _result(false, "snapshot_control")
		if edge.kind == "gravity" and value.powered: return _result(false, "gravity_has_no_power_control")
		if not _integer(value.flow_carry, 0, 9999) or not _integer(value.last_direction, -1, 1): return _result(false, "snapshot_flow_phase")
		var cap := int(ceil(float(edge.max_rate_ml_s) / 10.0))
		if not _integer(value.last_transfer_ml, -cap, cap): return _result(false, "snapshot_rate")
		if int(value.last_direction) < 0 and (edge.kind != "gravity" or not edge.bidirectional): return _result(false, "snapshot_reverse")
		if int(value.last_transfer_ml) != 0 and signi(int(value.last_transfer_ml)) != int(value.last_direction): return _result(false, "snapshot_direction")
		if int(value.last_direction) == 0 and int(value.flow_carry) != 0: return _result(false, "snapshot_flow_phase")
		if int(saved.tick) == 0 and (int(value.last_direction) != 0 or int(value.last_transfer_ml) != 0 or int(value.flow_carry) != 0): return _result(false, "snapshot_initial_flow")
	return _result(true, "valid")

func restore(saved: Dictionary) -> Dictionary:
	var checked := validate_snapshot(saved)
	if not checked.ok: return checked
	_state = saved.duplicate(true)
	for key in ["schema_version", "definition_version", "tick", "pending_usec"]: _state[key] = int(_state[key])
	for id in _state.nodes:
		for key in ["clean_ml", "dirty_ml"]: _state.nodes[id][key] = int(_state.nodes[id][key])
	for id in _state.edges:
		for key in ["open_permille", "flow_carry", "last_direction", "last_transfer_ml"]: _state.edges[id][key] = int(_state.edges[id][key])
	return _result(true, "restored")

@warning_ignore("integer_division")
func _tick() -> int:
	var flows: Dictionary = {}
	for id in _sorted(_edges):
		var edge: Dictionary = _edges[id]
		var state: Dictionary = _state.edges[id]
		state.last_transfer_ml = 0
		var direction := _desired_direction(edge, state)
		if direction.sign == 0:
			state.last_direction = 0
			state.flow_carry = 0
			continue
		if state.last_direction != direction.sign: state.flow_carry = 0
		state.last_direction = direction.sign
		var numerator: int = int(direction.rate) * int(state.open_permille) + int(state.flow_carry)
		var wanted: int = numerator / 10000
		state.flow_carry = numerator % 10000
		if edge.kind == "gravity":
			# A single link cannot transfer past equal head within this tick.
			var equalization := absf(_head_mm(direction.source) - _head_mm(direction.target)) / (10.0 / float(_nodes[direction.source].area_cm2) + 10.0 / float(_nodes[direction.target].area_cm2))
			wanted = mini(wanted, int(floor(equalization)))
		else:
			# Clamp the volume too: checking only the starting head would let a
			# fast pump exceed its rated lift during this very tick.
			var head_room := _head_mm(direction.source) + float(edge.pump_head_mm) - _head_mm(direction.target)
			var lift_limited_volume := head_room / (10.0 / float(_nodes[direction.source].area_cm2) + 10.0 / float(_nodes[direction.target].area_cm2))
			wanted = mini(wanted, maxi(0, int(floor(lift_limited_volume))))
		flows[id] = {"source":direction.source, "target":direction.target, "amount":wanted, "sign":int(direction.sign)}
	# Proportional limiting uses the same starting quantities for all edges.
	for node_id in _sorted(_nodes):
		var weights: Dictionary = {}
		for id in _sorted(flows):
			if flows[id].source == node_id: weights[id] = flows[id].amount
		var limited := _allocate(weights, _volume(node_id))
		for id in limited: flows[id].amount = limited[id]
	for node_id in _sorted(_nodes):
		var weights: Dictionary = {}
		for id in _sorted(flows):
			if flows[id].target == node_id: weights[id] = flows[id].amount
		var limited := _allocate(weights, int(_nodes[node_id].capacity_ml) - _volume(node_id))
		for id in limited: flows[id].amount = limited[id]
	var deltas: Dictionary = {}
	for id in _nodes: deltas[id] = {"clean_ml":0, "dirty_ml":0}
	var moved := 0
	for source in _sorted(_nodes):
		var weights: Dictionary = {}
		var outgoing := 0
		for id in _sorted(flows):
			if flows[id].source == source:
				weights[id] = int(flows[id].amount)
				outgoing += int(flows[id].amount)
		if outgoing == 0: continue
		var clean_out: int = int(_state.nodes[source].clean_ml) * outgoing / _volume(source)
		var clean_parts := _allocate(weights, clean_out)
		for id in _sorted(weights):
			var amount: int = weights[id]
			var clean: int = clean_parts[id]
			var dirty := amount - clean
			var target: String = flows[id].target
			deltas[source].clean_ml -= clean
			deltas[source].dirty_ml -= dirty
			deltas[target].clean_ml += clean
			deltas[target].dirty_ml += dirty
			_state.edges[id].last_transfer_ml = int(flows[id].sign) * amount
			moved += amount
	for id in _nodes:
		_state.nodes[id].clean_ml += int(deltas[id].clean_ml)
		_state.nodes[id].dirty_ml += int(deltas[id].dirty_ml)
	return moved

func _desired_direction(edge: Dictionary, state: Dictionary) -> Dictionary:
	var out := {"sign":0, "source":str(edge.from), "target":str(edge.to), "rate":0, "code":"closed"}
	if int(state.open_permille) == 0: return out
	var difference := _head_mm(edge.from) - _head_mm(edge.to)
	if edge.kind == "pump":
		if not state.powered:
			out.code = "unpowered"
			return out
		if -difference >= float(edge.pump_head_mm):
			out.code = "head_limit"
			return out
		out.sign = 1
		out.rate = int(edge.max_rate_ml_s)
	else:
		if is_zero_approx(difference) or (difference < 0.0 and not edge.bidirectional):
			out.code = "no_downhill_head"
			return out
		out.sign = 1 if difference > 0.0 else -1
		if out.sign < 0:
			out.source = str(edge.to)
			out.target = str(edge.from)
		out.rate = mini(int(edge.max_rate_ml_s), int(floor(absf(difference) * float(edge.conductance_ml_s_per_mm))))
	if _volume(out.source) == 0: out.code = "source_empty"
	elif _volume(out.target) >= int(_nodes[out.target].capacity_ml): out.code = "target_full"
	else: out.code = "eligible"
	# No blocked link stores a budget to release as a later burst.
	if out.code != "eligible": out.sign = 0
	return out

@warning_ignore("integer_division")
func _allocate(weights: Dictionary, limit: int) -> Dictionary:
	var result: Dictionary = {}
	var total := 0
	for id in weights: total += int(weights[id])
	var budget := mini(total, limit)
	var used := 0
	var remainders: Dictionary = {}
	for id in _sorted(weights):
		var product: int = int(weights[id]) * budget
		result[id] = product / total if total > 0 else 0
		remainders[id] = product % total if total > 0 else 0
		used += int(result[id])
	# Fewer than the edge count of extra ml; stable IDs break equal remainders.
	for unused in range(budget - used):
		var best := ""
		var remainder := -1
		for id in _sorted(weights):
			if int(remainders[id]) > remainder:
				best = str(id)
				remainder = int(remainders[id])
		result[best] += 1
		remainders[best] = -1
	return result

func _validate_controls(input: Variant) -> Dictionary:
	var commands: Dictionary = {}
	if input is Array:
		if input.size() > _edges.size(): return _result(false, "control_limit")
		for command in input:
			if not command is Dictionary or not command.get("edge_id") is String: return _result(false, "invalid_control")
			var id: String = command.edge_id
			if commands.has(id): return _result(false, "duplicate_control")
			var fields: Dictionary = command.duplicate(true)
			fields.erase("edge_id")
			commands[id] = fields
	elif input is Dictionary:
		if input.size() > _edges.size(): return _result(false, "control_limit")
		commands = input.duplicate(true)
	else: return _result(false, "invalid_control")
	for id in commands:
		if not id is String or not _edges.has(id): return _result(false, "unknown_edge")
		var fields: Variant = commands[id]
		if not fields is Dictionary or fields.is_empty() or fields.size() > 2: return _result(false, "invalid_control")
		for key in fields:
			if key == "open_permille":
				if not _integer(fields[key], 0, 1000): return _result(false, "invalid_valve")
				fields[key] = int(fields[key])
			elif key == "powered":
				if not fields[key] is bool: return _result(false, "invalid_power")
				if _edges[id].kind != "pump": return _result(false, "gravity_has_no_power_control")
			else: return _result(false, "unknown_control")
	return {"ok":true, "code":"valid", "controls":commands}

func _validate_definition(value: Dictionary) -> Dictionary:
	if not _exact_keys(value, ["schema_version", "id", "version", "nodes", "edges"]): return _result(false, "definition_keys")
	if not _integer(value.schema_version, SCHEMA, SCHEMA) or not _integer(value.version, 1, 1000000) or not _id(value.id): return _result(false, "definition_schema")
	if not value.nodes is Array or value.nodes.size() < 3 or value.nodes.size() > 5: return _result(false, "node_limit")
	if not value.edges is Array or value.edges.is_empty() or value.edges.size() > 8: return _result(false, "edge_limit")
	var nodes: Dictionary = {}
	var edges: Dictionary = {}
	for node in value.nodes:
		if not node is Dictionary or not _exact_keys(node, NODE_KEYS) or not _id(node.id): return _result(false, "invalid_node")
		if nodes.has(node.id): return _result(false, "duplicate_node")
		if not _integer(node.capacity_ml, 1, MAX_CAPACITY) or not _integer(node.clean_ml, 0, MAX_CAPACITY) or not _integer(node.dirty_ml, 0, MAX_CAPACITY): return _result(false, "invalid_quantity")
		if int(node.clean_ml) + int(node.dirty_ml) > int(node.capacity_ml): return _result(false, "initial_capacity")
		if not _integer(node.base_mm, -50000, 50000) or not _integer(node.area_cm2, 1, 1000000): return _result(false, "invalid_geometry")
		var normalized: Dictionary = node.duplicate(true)
		for key in NODE_KEYS:
			if key != "id": normalized[key] = int(normalized[key])
		nodes[node.id] = normalized
	for edge in value.edges:
		if not edge is Dictionary or not _exact_keys(edge, EDGE_KEYS) or not _id(edge.id): return _result(false, "invalid_edge")
		if edges.has(edge.id): return _result(false, "duplicate_edge")
		if not edge.from is String or not edge.to is String or not nodes.has(edge.from) or not nodes.has(edge.to) or edge.from == edge.to: return _result(false, "invalid_endpoint")
		if edge.kind not in ["gravity", "pump"] or not edge.initial_powered is bool or not edge.bidirectional is bool: return _result(false, "invalid_edge_kind")
		if not _integer(edge.max_rate_ml_s, 1, MAX_RATE) or not _integer(edge.initial_open_permille, 0, 1000): return _result(false, "invalid_rate")
		if not _integer(edge.conductance_ml_s_per_mm, 0, 5000) or not _integer(edge.pump_head_mm, 0, 100000): return _result(false, "invalid_pressure")
		if edge.kind == "gravity" and (edge.initial_powered or int(edge.conductance_ml_s_per_mm) == 0 or int(edge.pump_head_mm) != 0): return _result(false, "invalid_gravity")
		if edge.kind == "pump" and (edge.bidirectional or int(edge.conductance_ml_s_per_mm) != 0 or int(edge.pump_head_mm) == 0): return _result(false, "invalid_pump")
		var normalized: Dictionary = edge.duplicate(true)
		for key in ["max_rate_ml_s", "conductance_ml_s_per_mm", "pump_head_mm", "initial_open_permille"]: normalized[key] = int(normalized[key])
		edges[edge.id] = normalized
	var definition := {"schema_version":SCHEMA, "id":str(value.id), "version":int(value.version), "nodes":[], "edges":[]}
	for id in _sorted(nodes): definition.nodes.append(nodes[id].duplicate(true))
	for id in _sorted(edges): definition.edges.append(edges[id].duplicate(true))
	return {"ok":true, "code":"valid", "definition":definition, "nodes":nodes, "edges":edges}

func _volume(id: String) -> int:
	return int(_state.nodes[id].clean_ml) + int(_state.nodes[id].dirty_ml)

func _head_mm(id: String) -> float:
	return float(_nodes[id].base_mm) + float(_volume(id)) * 10.0 / float(_nodes[id].area_cm2)

func _integer(value: Variant, minimum: int, maximum: int) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and float(value) >= float(minimum) and float(value) <= float(maximum) and floor(float(value)) == float(value)

func _id(value: Variant) -> bool:
	if not value is String or value.is_empty() or value.length() > 64: return false
	for index in value.length():
		var c: int = value.unicode_at(index)
		if not ((c >= 48 and c <= 57) or (c >= 65 and c <= 90) or (c >= 97 and c <= 122) or c in [45, 58, 95]): return false
	return true

func _sorted(value: Dictionary) -> Array:
	var keys: Array = value.keys()
	keys.sort()
	return keys

func _exact_keys(value: Dictionary, expected: Array) -> bool:
	if value.size() != expected.size(): return false
	for key in expected:
		if not value.has(key): return false
	return true

func _result(ok: bool, code: String) -> Dictionary:
	return {"ok":ok, "code":code, "ticks":0, "moved_ml":0}
