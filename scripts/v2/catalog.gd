class_name CatalogV2
extends RefCounted

const CONTENT_PATH: String = "res://data/v2/world_content.json"
const SLOT_ORDER: Array[String] = ["weapon", "tool", "drive", "battery", "utility"]
static var _content: Dictionary = {}
static var _frames: Dictionary = {}
static var _modules: Dictionary = {}


static func content() -> Dictionary:
	_load()
	return _content.duplicate(true)


static func airframes() -> Dictionary:
	_load()
	return _frames.duplicate(true)


static func modules() -> Dictionary:
	_load()
	return _modules.duplicate(true)


static func default_build(frame_id: String = "tr01") -> Dictionary:
	_load()
	return {
		"schema_version": 2,
		"build_id": frame_id + "_default",
		"airframe_id": frame_id,
		"slots": {"weapon": "pulse_base", "tool": "scan_base", "drive": "stock", "battery": "stock", "utility": "guard_base"},
		"cosmetic_id": "ivory_teal"
	}


static func resolve_build(build: Dictionary, cargo_kg: float = 0.0, owned_frames: Array = [], owned_modules: Array = [], loaner: bool = false) -> Dictionary:
	_load()
	var errors: Array[Dictionary] = []
	var warnings: Array[Dictionary] = []
	var result: Dictionary = {"valid": false, "errors": errors, "warnings": warnings, "derived": {}, "build": build.duplicate(true)}
	if _content.is_empty():
		_error(errors, "CONTENT_INVALID", "", CONTENT_PATH, "valid schema 2 content", "Restore the generated content file.")
		return result
	if build.get("schema_version", 2) != 2:
		_error(errors, "BUILD_SCHEMA", "", build.get("schema_version"), 2, "Use a version 2 build.")
	var frame_value: Variant = build.get("airframe_id", "")
	if not frame_value is String or not _frames.has(frame_value):
		_error(errors, "BUILD_UNKNOWN_FRAME", "", frame_value, _frames.keys(), "Select a known airframe.")
		return result
	var frame_id: String = str(frame_value)
	var frame: Dictionary = _frames[frame_id]
	if not loaner and not owned_frames.is_empty() and frame_id not in owned_frames:
		_error(errors, "BUILD_FRAME_NOT_OWNED", "", frame_id, owned_frames, "Craft this airframe or select an owned one.")
	if not is_finite(cargo_kg) or cargo_kg < 0.0:
		_error(errors, "BUILD_INVALID_CARGO", "cargo", cargo_kg, "finite and >= 0", "Use a nonnegative finite cargo mass.")
		return result
	var slots_value: Variant = build.get("slots", {})
	if not slots_value is Dictionary:
		_error(errors, "BUILD_INVALID_SLOTS", "", slots_value, SLOT_ORDER, "Restore the last legal build.")
		return result
	var slots: Dictionary = slots_value
	var catalog: Dictionary = _content["catalog"]
	var effects: Dictionary = catalog["effect_defaults"].duplicate(true)
	# A replacement utility does not retain the factory shield.
	effects["guard_enabled"] = false
	_merge_modifiers(effects, frame.get("modifiers", {}), catalog)
	var limits: Dictionary = frame["motion_limits"]
	var mass: float = float(frame["dry_mass_kg"]) + cargo_kg
	var power: float = float(frame["base_flight_pu"])
	var capacity: float = float(frame["capacity_pu"])
	var assembled: Dictionary = {}
	var canonical_slots: Dictionary = {}
	for key: Variant in slots:
		if key not in SLOT_ORDER:
			_error(errors, "BUILD_UNKNOWN_SLOT", str(key), key, SLOT_ORDER, "Remove the unknown slot.")
	for slot: String in SLOT_ORDER:
		if not slots.has(slot):
			_error(errors, "BUILD_MISSING_SLOT", slot, null, "one module", "Choose one module for this slot.")
			continue
		var raw_id: Variant = slots[slot]
		if not raw_id is String:
			_error(errors, "BUILD_INVALID_MODULE_ID", slot, raw_id, "module ID string", "Choose a module from the catalog.")
			continue
		var module_id: String = str(raw_id)
		if module_id == "stock" and slot in ["drive", "battery"]:
			module_id = str(catalog["stock_slot_ids"][slot])
		if not _modules.has(module_id):
			_error(errors, "BUILD_UNKNOWN_MODULE", slot, module_id, "known module", "Choose a module from the catalog.")
			continue
		var module: Dictionary = _modules[module_id]
		canonical_slots[slot] = module_id
		if str(module["slot"]) != slot:
			_error(errors, "BUILD_SLOT_MISMATCH", slot, module["slot"], slot, "Install the module in its matching slot.")
			continue
		if not loaner and not owned_modules.is_empty() and module_id not in owned_modules and module_id not in ["stock_drive", "stock_battery"]:
			_error(errors, "BUILD_MODULE_NOT_OWNED", slot, module_id, owned_modules, "Unlock this module or choose an owned one.")
		var mount_type: String = str(module["mount_type"])
		if mount_type not in frame["mount_types"]:
			_error(errors, "BUILD_MOUNT_CONFLICT", slot, mount_type, frame["mount_types"], "Choose a compatible mount.")
		mass += float(module.get("mass_delta_kg", module.get("mass_kg", 0.0)))
		power += float(module["power_pu"])
		capacity += float(module["capacity_delta_pu"])
		_merge_modifiers(effects, module["modifiers"], catalog)
		assembled[slot] = module
	var cargo_rating: float = float(frame["cargo_rating_kg"])
	var thrust: float = float(frame["max_thrust_n"])
	var ratio: float = thrust / (mass * float(catalog["gravity_mps2"]))
	if cargo_kg > cargo_rating:
		_error(errors, "BUILD_OVER_CARGO", "cargo", cargo_kg, cargo_rating, "Split the cargo into smaller trips.")
	if mass > float(frame["max_takeoff_mass_kg"]):
		_error(errors, "BUILD_OVER_MASS", "", mass, frame["max_takeoff_mass_kg"], "Remove cargo or use lighter modules.")
	if power > capacity:
		_error(errors, "BUILD_OVER_POWER", "", power, capacity, "Use a larger battery or lower power modules.")
	if ratio < float(catalog["minimum_thrust_ratio"]):
		_error(errors, "BUILD_LOW_THRUST_RATIO", "", ratio, catalog["minimum_thrust_ratio"], "Reduce takeoff mass.")
	var mounts: Dictionary = _content["mount_layout"].duplicate(true)
	var rotors: Array[Dictionary] = _rotor_sweeps(frame)
	_validate_geometry(assembled, mounts, rotors, errors)
	var cargo_factor: float = 1.0 - float(catalog["cargo_accel_penalty"]) * clampf(cargo_kg / cargo_rating, 0.0, 1.0)
	var padding: float = float(effects.get("envelope_padding_each_side_m", 0.0)) * 2.0
	var fingerprint: Dictionary = {"content_version": _content.get("content_version", "2"), "source_sha256": _content.get("_source_sha256", ""), "airframe_id": frame_id, "slots": canonical_slots, "cosmetic_id": build.get("cosmetic_id", "ivory_teal")}
	var normalized: Dictionary = build.duplicate(true)
	normalized.erase("derived")
	normalized["schema_version"] = 2
	normalized["slots"] = slots.duplicate(true)
	result["build"] = normalized
	result["derived"] = {
		"mass_kg": mass, "cargo_kg": cargo_kg, "cargo_rating_kg": cargo_rating,
		"capacity_pu": capacity, "power_pu": power, "power_margin_pu": capacity - power,
		"thrust_n": thrust, "thrust_ratio": ratio,
		"speed_mps": float(limits["speed_mps"]) * float(effects.get("speed_multiplier", 1.0)),
		"accel_mps2": float(limits["accel_mps2"]) * float(effects.get("accel_multiplier", 1.0)) * cargo_factor,
		"brake_mps2": float(limits["brake_mps2"]) * cargo_factor,
		"tilt_deg": float(limits["tilt_deg"]), "yaw_deg_s": float(limits["yaw_deg_s"]),
		"rise_mps": float(limits["rise_mps"]), "fall_mps": float(limits["fall_mps"]),
		"health": float(frame["health"]), "heat_capacity": float(frame["heat_capacity"]),
		"width_m": float(frame["width_m"]) + padding, "length_m": float(frame["length_m"]) + padding,
		"height_m": float(frame["height_m"]), "build_hash": JSON.stringify(fingerprint, "", true).sha256_text(),
		"modifiers": effects, "mounts": mounts, "rotor_sweeps": rotors,
		"innate_ability": frame["innate_ability"], "tool_ability": assembled.get("tool", {}).get("ability", ""),
		"weapon_ability": assembled.get("weapon", {}).get("ability", ""), "rotor_count": frame["rotor_count"]
	}
	var horizontal_limit: float = float(catalog["gravity_mps2"]) * tan(deg_to_rad(float(limits["tilt_deg"])))
	if float(result["derived"]["accel_mps2"]) > horizontal_limit:
		warnings.append({"code": "BUILD_TILT_LIMIT", "actual": result["derived"]["accel_mps2"], "limit": horizontal_limit, "remedy": "The flight controller must respect available tilt and thrust."})
	result["valid"] = errors.is_empty()
	return result


static func _load() -> void:
	if not _content.is_empty():
		return
	var file: FileAccess = FileAccess.open(CONTENT_PATH, FileAccess.READ)
	if file == null:
		push_error("CatalogV2: missing " + CONTENT_PATH)
		return
	var parser: JSON = JSON.new()
	var parse_error: Error = parser.parse(file.get_as_text())
	if parse_error != OK or not parser.data is Dictionary:
		push_error("CatalogV2: invalid content JSON")
		return
	var parsed: Dictionary = parser.data
	if parsed.get("schema_version") != 2 or not parsed.get("catalog") is Dictionary or not parsed.get("airframes") is Array or not parsed.get("modules") is Array:
		push_error("CatalogV2: incompatible content schema")
		return
	for collection_name: String in ["airframes", "modules"]:
		var seen: Dictionary = {}
		for entry: Variant in parsed[collection_name]:
			if not entry is Dictionary or not entry.get("id") is String or seen.has(entry["id"]):
				push_error("CatalogV2: duplicate or malformed " + collection_name)
				return
			seen[entry["id"]] = entry
		if collection_name == "airframes":
			_frames = seen
		else:
			_modules = seen
	_content = parsed


static func _error(errors: Array[Dictionary], code: String, slot: String, actual: Variant, limit: Variant, remedy: String) -> void:
	errors.append({"code": code, "slot": slot, "actual": actual, "limit": limit, "remedy": remedy})


static func _merge_modifiers(effects: Dictionary, added: Dictionary, catalog: Dictionary) -> void:
	for key: Variant in added:
		if key == "cargo_damping_multiplier":
			effects[key] = minf(float(effects.get(key, 1.0)) * float(added[key]), float(catalog["stack_rules"]["cargo_damping_max"]))
		elif key in ["night_scan_time_multiplier", "shield_damage_multiplier"]:
			effects[key] = minf(float(effects.get(key, 1.0)), float(added[key]))
		elif key == "shield_duration_s":
			effects[key] = maxf(float(effects.get(key, 0.0)), float(added[key]))
		elif key == "shield_cooldown_s":
			effects[key] = maxf(float(effects.get(key, 0.0)), float(added[key]))
		else:
			effects[key] = added[key]


static func _rotor_sweeps(frame: Dictionary) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var rotor_count: int = int(frame["rotor_count"])
	var positions: int = 4 if rotor_count == 8 else rotor_count
	for index: int in range(rotor_count):
		var angle: float = TAU * float(index % positions) / float(positions) + PI / 4.0
		var height: float = 0.13 + (0.13 if rotor_count == 8 and index >= 4 else 0.0)
		result.append({"position_m": [sin(angle) * float(frame["width_m"]) * 0.34, height, cos(angle) * float(frame["length_m"]) * 0.34], "radius_m": minf(float(frame["width_m"]), float(frame["length_m"])) * 0.15, "thickness_m": 0.04})
	return result


static func _validate_geometry(assembled: Dictionary, mounts: Dictionary, rotors: Array[Dictionary], errors: Array[Dictionary]) -> void:
	var boxes: Dictionary = {}
	for slot: String in assembled:
		var module: Dictionary = assembled[slot]
		var mount: Dictionary = mounts[slot]
		if module["mount_type"] != mount["mount_type"]:
			_error(errors, "BUILD_MOUNT_CONFLICT", slot, module["mount_type"], mount["mount_type"], "Use the matching attachment mount.")
		var position: Vector3 = _vector(mount["position_m"])
		var size: Vector3 = _vector(module.get("envelope_size_m", mount["size_m"]))
		var box: AABB = AABB(position - size * 0.5, size)
		for previous_slot: String in boxes:
			if box.intersects(boxes[previous_slot]):
				_error(errors, "BUILD_MOUNT_CONFLICT", slot, previous_slot, "non-overlapping envelopes", "Use compatible attachment envelopes.")
		boxes[slot] = box
		for rotor: Dictionary in rotors:
			var center: Vector3 = _vector(rotor["position_m"])
			var half_height: float = float(rotor["thickness_m"]) * 0.5
			if box.position.y >= center.y + half_height or box.end.y <= center.y - half_height:
				continue
			var closest: Vector2 = Vector2(clampf(center.x, box.position.x, box.end.x), clampf(center.z, box.position.z, box.end.z))
			if closest.distance_to(Vector2(center.x, center.z)) < float(rotor["radius_m"]):
				_error(errors, "BUILD_ROTOR_INTERSECTION", slot, module["id"], "outside rotor sweep", "Choose an attachment clear of the rotors.")


static func _vector(values: Array) -> Vector3:
	return Vector3(float(values[0]), float(values[1]), float(values[2]))
