extends SceneTree

const Catalog = preload("res://scripts/v2/catalog.gd")
var failures: Array[String] = []
var checks: int = 0


func _initialize() -> void:
	var data: Dictionary = Catalog.content()
	_expect(data.get("regions", []).size() == 4, "four regions")
	_expect(data.get("missions", []).size() == 16, "sixteen missions")
	_expect(data.get("airframe_challenges", []).size() == 18, "eighteen challenges")
	_expect(data.get("mode_configs", []).size() == 12, "twelve regional modes")
	var frames: Dictionary = Catalog.airframes()
	_expect(frames.size() == 6, "six airframes")
	var free_tools: Array[String] = ["scan_base", "hook_base", "delivery_base", "clearance_base"]
	for frame_id: String in frames:
		for tool_id: String in free_tools:
			var factory: Dictionary = Catalog.default_build(frame_id)
			factory["slots"]["tool"] = tool_id
			var empty: Dictionary = Catalog.resolve_build(factory)
			var full: Dictionary = Catalog.resolve_build(factory, float(frames[frame_id]["cargo_rating_kg"]))
			_expect(empty["valid"], frame_id + " legal " + tool_id + " unloaded: " + str(empty["errors"]))
			_expect(full["valid"], frame_id + " legal " + tool_id + " full cargo: " + str(full["errors"]))
			_expect(is_equal_approx(float(full["derived"]["brake_mps2"]), float(empty["derived"]["brake_mps2"]) * 0.7), "single cargo penalty")
	var example: Dictionary = Catalog.default_build()
	example["slots"]["tool"] = "cargo_winch"
	example["slots"]["utility"] = "precision_gimbal"
	var resolved: Dictionary = Catalog.resolve_build(example, 2.0)
	_expect(resolved["valid"], "document example is legal")
	_expect(is_equal_approx(float(resolved["derived"]["mass_kg"]), 5.95), "document example mass 5.95")
	_expect(is_equal_approx(float(resolved["derived"]["power_pu"]), 72.0), "document example power 72")
	_expect(resolved["derived"]["modifiers"]["guard_enabled"] == false, "replaced shield is absent")
	var racing: Dictionary = Catalog.default_build("ag03")
	racing["slots"]["drive"] = "racing_drive"
	var race_result: Dictionary = Catalog.resolve_build(racing)
	_expect(is_equal_approx(float(race_result["derived"]["speed_mps"]), 22.4), "racing drive speed benefit")
	_expect(is_equal_approx(float(race_result["derived"]["brake_mps2"]), 8.0), "racing drive does not secretly upgrade brakes")
	var costly: Dictionary = Catalog.default_build("ag03")
	costly["slots"]["weapon"] = "burst_capacitor"
	costly["slots"]["tool"] = "clearance_base"
	costly["slots"]["drive"] = "racing_drive"
	costly["slots"]["utility"] = "night_sensor"
	_expect(_has_error(Catalog.resolve_build(costly), "BUILD_OVER_POWER"), "power overloaded assembly rejected")
	costly["slots"]["battery"] = "long_range_battery"
	_expect(Catalog.resolve_build(costly)["valid"], "larger battery restores legal power unloaded")
	_expect(_has_error(Catalog.resolve_build(costly, 1.0), "BUILD_OVER_MASS"), "battery mass can make full cargo illegal")
	var heavy: Dictionary = Catalog.default_build("hx02")
	heavy["slots"]["tool"] = "cargo_winch"
	_expect(is_equal_approx(float(Catalog.resolve_build(heavy)["derived"]["modifiers"]["cargo_damping_multiplier"]), 1.6), "cargo damping capped at 1.6")
	var night: Dictionary = Catalog.default_build("nx04")
	night["slots"]["utility"] = "night_sensor"
	_expect(is_equal_approx(float(Catalog.resolve_build(night)["derived"]["modifiers"]["night_scan_time_multiplier"]), 0.65), "night scan bonuses do not multiply")
	var guard: Dictionary = Catalog.default_build()
	guard["slots"]["utility"] = "reinforced_guard"
	var guarded: Dictionary = Catalog.resolve_build(guard)["derived"]
	_expect(float(guarded["width_m"]) > 1.4 and float(guarded["length_m"]) > 1.4, "guard expands collision envelope")
	_expect(float(guarded["modifiers"]["frontal_damage_multiplier"]) == 1.0, "guard does not protect frontal high speed collisions")
	_expect(_has_error(Catalog.resolve_build(Catalog.default_build(), -1.0), "BUILD_INVALID_CARGO"), "negative cargo rejected")
	_expect(_has_error(Catalog.resolve_build(Catalog.default_build(), NAN), "BUILD_INVALID_CARGO"), "NaN cargo rejected")
	_expect(_has_error(Catalog.resolve_build(Catalog.default_build(), INF), "BUILD_INVALID_CARGO"), "infinite cargo rejected")
	var over: Dictionary = Catalog.resolve_build(Catalog.default_build(), 100.0)
	_expect(_has_error(over, "BUILD_OVER_CARGO") and _has_error(over, "BUILD_OVER_MASS") and _has_error(over, "BUILD_LOW_THRUST_RATIO"), "all overload reasons returned together")
	var broken: Dictionary = Catalog.default_build()
	broken["slots"]["tool"] = "nonexistent"
	broken["slots"]["utility"] = "burst_capacitor"
	broken["slots"].erase("battery")
	var invalid: Dictionary = Catalog.resolve_build(broken)
	_expect(_has_error(invalid, "BUILD_UNKNOWN_MODULE") and _has_error(invalid, "BUILD_SLOT_MISMATCH") and _has_error(invalid, "BUILD_MISSING_SLOT"), "multiple invalid slot reasons reported")
	var denied: Dictionary = Catalog.resolve_build(Catalog.default_build("hx02"), 0.0, ["tr01"], ["pulse_base"])
	_expect(_has_error(denied, "BUILD_FRAME_NOT_OWNED") and _has_error(denied, "BUILD_MODULE_NOT_OWNED"), "ownership enforced when supplied")
	_expect(Catalog.resolve_build(Catalog.default_build("hx02"), 0.0, ["tr01"], ["pulse_base"], true)["valid"], "local challenge loan bypasses ownership only")
	var one: Dictionary = Catalog.default_build()
	var two: Dictionary = Catalog.default_build()
	two["slots"] = {"utility": "guard_base", "battery": "stock", "drive": "stock", "tool": "scan_base", "weapon": "pulse_base"}
	_expect(Catalog.resolve_build(one)["derived"]["build_hash"] == Catalog.resolve_build(two)["derived"]["build_hash"], "hash independent of dictionary insertion order")
	two["slots"]["tool"] = "hook_base"
	_expect(Catalog.resolve_build(one)["derived"]["build_hash"] != Catalog.resolve_build(two)["derived"]["build_hash"], "different assembly has different hash")
	var copy_check: Dictionary = Catalog.airframes()
	copy_check["tr01"]["dry_mass_kg"] = 9999.0
	_expect(Catalog.resolve_build(Catalog.default_build())["valid"], "returned catalog cannot mutate authority")
	print(JSON.stringify({"suite": "CatalogV2", "checks": checks, "failed": failures.size(), "failures": failures}))
	quit(0 if failures.is_empty() else 1)


func _expect(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures.append(label)


func _has_error(result: Dictionary, code: String) -> bool:
	for error: Dictionary in result["errors"]:
		if error["code"] == code:
			return true
	return false
