extends RefCounted
## Read-only test diagnostics. No normalization/mutation of production state.

static func inspect(saved: Dictionary, parsed: Dictionary, restored: Dictionary, node_position: Vector3, physics_position: Vector3, expected: Vector3) -> Dictionary:
	var node_error: float = node_position.distance_to(expected)
	var physics_error: float = physics_position.distance_to(expected)
	var fields: Array = []
	_leaves(saved,parsed,restored,"",fields)
	return {"node_lt_1um":node_error < .000001,"physics_lt_1um":physics_error < .000001,
		"native_dictionary_equal":restored == saved,"node_error_m":scalar(node_error),"physics_error_m":scalar(physics_error),
		"node_position":vector(node_position),"physics_position":vector(physics_position),"expected_position":vector(expected),"fields":fields}

static func scalar(value: Variant) -> Dictionary:
	var result: Dictionary = {"type":type_string(typeof(value)),"value":value}
	if value is int or value is float:
		var bytes := PackedByteArray()
		bytes.resize(8)
		bytes.encode_double(0,float(value))
		result.decimal17 = "%.17f" % float(value)
		result.double_hex = bytes.hex_encode()
	return result

static func vector(value: Vector3) -> Array:
	return [scalar(value.x),scalar(value.y),scalar(value.z)]

## Saved schema values, not Variant container identity. IDs, booleans, versions,
## revisions and replay serials remain exact; only axis double serialization and
## real float32 world positions have the explicit pre-agreed numeric budgets.
static func semantic(saved: Dictionary, restored: Dictionary, node_position: Vector3, physics_position: Vector3, expected: Vector3) -> Dictionary:
	var fields: Array = []
	var values_equal: bool = _semantic_fields(saved,restored,"",fields)
	var node_valid: bool = node_position.is_finite() and expected.is_finite() and node_position.distance_to(expected) <= .00001
	var physics_valid: bool = physics_position.is_finite() and expected.is_finite() and physics_position.distance_to(expected) <= .00001
	return {"ok":values_equal and node_valid and physics_valid,"values_match":values_equal,"node_pose_matches":node_valid,"physics_pose_matches":physics_valid,
		"position_tolerance_m":.00001,"axis_double_tolerance":.000000000001,"fields":fields}

static func _semantic_fields(saved: Dictionary, restored: Dictionary, prefix: String, out: Array) -> bool:
	if saved.size() != restored.size():
		out.append({"path":prefix,"matches":false,"reason":"key_count"})
		return false
	var valid := true
	for key: String in saved:
		var path: String = key if prefix.is_empty() else prefix+"."+key
		if not restored.has(key):
			out.append({"path":path,"matches":false,"reason":"missing_key"})
			valid = false
			continue
		var a: Variant = saved[key]
		var b: Variant = restored[key]
		if a is Dictionary and b is Dictionary:
			if not _semantic_fields(a,b,path,out): valid = false
			continue
		var tolerance: float = .000000000001 if path in ["axis.position_m","axis.velocity_mps"] else 0.0
		var matches: bool = typeof(a) == typeof(b) and a == b
		if (a is int or a is float) and (b is int or b is float):
			matches = is_finite(float(a)) and is_finite(float(b)) and absf(float(a)-float(b)) <= tolerance
		out.append({"path":path,"matches":matches,"tolerance":tolerance,"saved":scalar(a),"restored":scalar(b)})
		if not matches: valid = false
	return valid

static func _leaves(saved: Dictionary, parsed: Dictionary, restored: Dictionary, prefix: String, out: Array) -> void:
	for key: String in saved:
		var path: String = key if prefix.is_empty() else prefix+"."+key
		if saved[key] is Dictionary:
			_leaves(saved[key],parsed.get(key,{}),restored.get(key,{}),path,out)
		else:
			var a: Variant = saved[key]
			var b: Variant = parsed.get(key)
			var c: Variant = restored.get(key)
			var row: Dictionary = {"path":path,"saved":scalar(a),"parsed":scalar(b),"restored":scalar(c),"saved_equal_restored":a == c,"parsed_equal_restored":b == c}
			if (a is int or a is float) and (c is int or c is float):
				row.restored_minus_saved = scalar(float(c)-float(a))
			out.append(row)
