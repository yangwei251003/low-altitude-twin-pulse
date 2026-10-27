class_name TwinGroundSurface
extends RefCounted
## Development surface material, not approved final terrain artwork.
## Patterns use world meters and the world's shared shoreline control points.

const GROUND_SHADER = preload("res://assets/v3/materials/twin_ground_study.gdshader")
const FOREST_BASECOLOR = preload("res://assets/v3/materials/forest_floor_surface_v1.png")
const WATER_SHADER = preload("res://assets/v3/materials/twin_water_study.gdshader")
static var _ground_materials: Dictionary = {}
static var _water_materials: Dictionary = {}
static var _shore_profiles: Dictionary = {}

## shore_side: -1 = west/left bank, +1 = east/right bank, 0 = derive from world X.
## Returns a shared material. Duplicate it before making instance-specific edits.
static func material_for(region: String, shore_side: int) -> Material:
	var fantasy = region.begins_with("F")
	var side = clampi(shore_side, -1, 1)
	var key = region + ":" + str(side)
	if not _ground_materials.has(key):
		var material = ShaderMaterial.new()
		material.shader = GROUND_SHADER
		material.resource_name = "Ground study / " + key
		material.set_shader_parameter("fantasy_world", fantasy)
		material.set_shader_parameter("shore_side", float(side))
		_apply_shore(material, region)
		if fantasy:
			material.set_shader_parameter("forest_basecolor", FOREST_BASECOLOR)
			material.set_meta("status", "forest_floor_p2_development_not_final_approved_terrain")
			material.set_meta("source", "single_imagegen_surface_reference_forest_floor_surface_v1")
		else:
			material.set_meta("status", "procedural_ground_study_not_final_approved_terrain")
			material.set_meta("source", "authored_in_project_no_external_images")
		_ground_materials[key] = material
	return _ground_materials[key]

## Opaque water for the current channel floor's top face at y=-2.2.
## No screen sampling, transparency, depth texture, or vertex displacement.
static func water_material(region: String = "I1") -> ShaderMaterial:
	if not _water_materials.has(region):
		var water = ShaderMaterial.new()
		water.shader = WATER_SHADER
		water.resource_name = "Opaque water study / " + region
		water.set_shader_parameter("wind_phase", 0.0)
		water.set_meta("status", "procedural_water_study_not_final_approved_terrain")
		_apply_shore(water, region)
		_water_materials[region] = water
	return _water_materials[region]

static func configure_shore(region: String, data: Dictionary) -> bool:
	var count := int(data.get("count", 0))
	var points = data.get("water_points", PackedVector4Array())
	if count < 2 or count > 32 or not points is PackedVector4Array or points.size() != count: return false
	for index in count:
		var point: Vector4 = points[index]
		if not point.is_finite() or point.y >= point.z: return false
		if index > 0 and point.x <= points[index - 1].x: return false
	_shore_profiles[region] = {"count":count, "water_points":points.duplicate()}
	var key_prefix = region + ":"
	for key in _ground_materials:
		if str(key).begins_with(key_prefix): _apply_shore(_ground_materials[key], region)
	if _water_materials.has(region): _apply_shore(_water_materials[region], region)
	return true

static func _apply_shore(material: ShaderMaterial, region: String) -> void:
	var data: Dictionary = _shore_profiles.get(region, {})
	material.set_shader_parameter("shore_profile_count", int(data.get("count", 0)))
	if data.is_empty(): return
	var points: PackedVector4Array = data.water_points.duplicate()
	points.resize(32)
	material.set_shader_parameter("shore_profile", points)

## Feed the world's existing clock_seconds, including its pause policy.
## Never uses shader TIME, so the caller owns the phase and pause behavior.
static func set_wind_phase(phase_seconds: float, strength: float = 1.0, region: String = "I1") -> void:
	if not is_finite(phase_seconds): return
	var water = water_material(region)
	water.set_shader_parameter("wind_phase", phase_seconds)
	water.set_shader_parameter("ripple_strength", clampf(strength * 0.13, 0.08, 0.3))
