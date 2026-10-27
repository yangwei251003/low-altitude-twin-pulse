extends SceneTree
## Headless resource/API check only. Dummy rendering is not a GPU shader compile
## or visual/performance test; the root integrator performs Compatibility capture.

const Surface = preload("res://scripts/v3/art/twin_ground_surface.gd")
var failures: Array[String] = []
var checks = 0

func _initialize() -> void:
	for region in ["I1", "F1"]:
		for side in [-1, 0, 1]:
			var material = Surface.material_for(region, side)
			_check(material is ShaderMaterial, region + ": material type")
			_check(material.shader != null and not material.shader.code.is_empty(), region + ": shader source loads")
			_check(material.get_shader_parameter("fantasy_world") == region.begins_with("F"), region + ": correct region")
			_check(is_equal_approx(float(material.get_shader_parameter("shore_side")), float(side)), region + ": side")
			_check(material == Surface.material_for(region, side), region + ": cached sharing is stable")
	var water = Surface.water_material()
	_check(water is ShaderMaterial and water.shader != null, "water source loads")
	Surface.set_wind_phase(42.5)
	_check(is_equal_approx(float(water.get_shader_parameter("wind_phase")), 42.5), "world phase passed to water")
	Surface.set_wind_phase(NAN)
	_check(is_equal_approx(float(water.get_shader_parameter("wind_phase")), 42.5), "nonfinite phase does not corrupt shader")
	_check(water == Surface.water_material(), "water shared instance")
	for shader in [Surface.GROUND_SHADER, Surface.WATER_SHADER]:
		_check(not shader.code.contains("ALPHA =") and not shader.code.contains("hint_screen_texture") and not shader.code.contains("hint_depth_texture"), "opaque shader without screen/depth sampling")
	print("GROUND_SURFACE_RESOURCE_CHECK checks=%d failures=%d renderer=%s" % [checks, failures.size(), RenderingServer.get_current_rendering_method()])
	print("LIMIT: headless resource/API validation only; no GPU compile, image, or performance acceptance")
	for failure in failures: print("FAIL: " + failure)
	quit(0 if failures.is_empty() else 1)

func _check(condition: bool, label: String) -> void:
	checks += 1
	if not condition: failures.append(label)
