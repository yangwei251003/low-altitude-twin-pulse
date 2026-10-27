extends Node3D
## Additive visual content for all eight regions; developed, not playtested.
## No _process/_physics_process, TIME, timer, RNG, physics, save or story writes.
## Root supplies the existing world clock/weather/wind and applied ecology view.
## MultiMesh is partitioned; every batch has custom_aabb and shadows disabled.
## References: docs.godotengine.org/en/stable/tutorials/performance/using_multimesh.html
## and docs.godotengine.org/en/stable/tutorials/shaders/shader_reference/spatial_shader.html
const PATH := "res://data/v3/content/final_world/weather_life.json"
const VolumeShader = preload("res://scripts/v3/content/final_world/weather_volume.gdshader")
const ClothShader = preload("res://scripts/v3/content/final_world/wind_cloth.gdshader")
const LeavesShader = preload("res://scripts/v3/content/final_world/wind_leaves.gdshader")
const ROOT_NAME := "FinalWeatherLifePresentation"
const MAX_RAIN_PER_TILE := 48
const MAX_DUST_PER_TILE := 20
const MAX_TILES := 9
const MAX_FLAGS := 6
const MAX_ACTOR_SIGNALS := 3
static var _definitions: Dictionary = {}
var region_id := ""
var _spec: Dictionary = {}
var _tiles: Array = []
var _flags: Array[Node3D] = []
var _leaf_batches: Array[MultiMeshInstance3D] = []
var _rain_material: ShaderMaterial
var _dust_material: ShaderMaterial
var _cloth_material: ShaderMaterial
var _leaves_material: ShaderMaterial
var _materials: Dictionary = {}
var _actor_signals: Dictionary = {}
var _counter_lamps: Dictionary = {}
var _counter_labels: Dictionary = {}
var _last_counter_keys: Dictionary = {}
var _last_ecology: Dictionary = {}
var _work_arm: Node3D
var _initialized := false
var _clock := 0.0
var _weather := "clear"
var _wind := Vector3.ZERO

static func build(world: Node3D) -> Node3D:
	if not is_instance_valid(world): return null
	var spec: Dictionary = definition(str(world.get("region_id")))
	if spec.is_empty(): return null
	var content = new()
	content.name = ROOT_NAME
	content._build(spec)
	# Detached result: Root mounts it once as a child of the prepared region.
	return content

static func definition(region: String) -> Dictionary:
	if _definitions.is_empty():
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(PATH))
		if parsed is Dictionary:
			for row: Dictionary in parsed.get("regions", []): _definitions[str(row.id)] = row
	return _definitions.get(region, {}).duplicate(true)

static func ecology_view(ecology, authority: bool) -> Dictionary:
	if ecology == null: return {}
	if authority: return ecology.view_packet()
	# pending is the existing reliable mailbox. A future, unconsumed packet may
	# never light a maintenance lamp or replace already applied Guest work facts.
	var pending: Variant = ecology.pending
	if not pending is Dictionary or pending.is_empty() or not pending.get("state") is Dictionary: return {}
	if int(pending.get("serial", -2)) != int(ecology.applied_serial) or int(pending.get("epoch", -2)) != int(ecology.expected_epoch): return {}
	if ecology.session == null or str(pending.get("session_id", "")) != str(ecology.session.received_session) or str(pending.get("region", "")) != str(ecology.session.region_id): return {}
	return pending.state.duplicate(true)

static func apply_state(root: Node3D, weather_context: Dictionary, ecology_snapshot: Dictionary, paused: bool, local_position: Vector3) -> void:
	if not is_instance_valid(root) or not root.has_method("_apply"): return
	root._apply(weather_context, ecology_snapshot, paused, local_position)

func _ready() -> void:
	set_process(false)
	set_physics_process(false)

func _build(spec: Dictionary) -> void:
	_spec = spec.duplicate(true)
	region_id = str(spec.id)
	set_meta("visual_only", true)
	set_meta("authority_phase_required", true)
	set_meta("status", "developed_not_playtested")
	_create_materials()
	_create_volumes()
	_create_flags()
	_create_leaves()
	_create_actor_signals()
	_create_counters()
	if region_id == "F1": _create_grove_workstation()

func _create_materials() -> void:
	_rain_material = ShaderMaterial.new()
	_rain_material.shader = VolumeShader
	_rain_material.set_shader_parameter("tone", Color(str(_spec.palette.rain)))
	_rain_material.set_shader_parameter("dust_mode", 0.0)
	_rain_material.set_shader_parameter("volume_height", 26.0)
	_dust_material = ShaderMaterial.new()
	_dust_material.shader = VolumeShader
	_dust_material.set_shader_parameter("tone", Color(str(_spec.palette.dust)))
	_dust_material.set_shader_parameter("dust_mode", 1.0)
	_dust_material.set_shader_parameter("volume_height", 26.0)
	_cloth_material = ShaderMaterial.new()
	_cloth_material.shader = ClothShader
	_cloth_material.set_shader_parameter("tone", Color(str(_spec.palette.flag)))
	_cloth_material.set_shader_parameter("edge_tone", Color(str(_spec.palette.edge)))
	_cloth_material.set_shader_parameter("industrial", 1.0 if region_id.begins_with("I") else 0.0)
	_leaves_material = ShaderMaterial.new()
	_leaves_material.shader = LeavesShader
	_leaves_material.set_shader_parameter("tone", Color(str(_spec.palette.leaf)))
	_leaves_material.set_shader_parameter("tip_tone", Color(str(_spec.palette.edge)))

func _create_volumes() -> void:
	var side: float = float(_spec.get("tile_side", 32.0))
	var rain_mesh := BoxMesh.new()
	rain_mesh.size = Vector3(.022, .62, .022)
	var dust_mesh := SphereMesh.new()
	dust_mesh.radius = .035
	dust_mesh.height = .07
	dust_mesh.radial_segments = 6
	dust_mesh.rings = 2
	for tile: Array in _spec.get("tiles", []).slice(0, MAX_TILES):
		var centre := Vector3(float(tile[0]), 13.0, float(tile[1]))
		var rain: MultiMeshInstance3D = _volume_batch("RainTile", centre, side, rain_mesh, MAX_RAIN_PER_TILE, _rain_material, 7)
		var dust: MultiMeshInstance3D = _volume_batch("AirborneTile", centre, side, dust_mesh, MAX_DUST_PER_TILE, _dust_material, 19)
		_tiles.append({"centre":centre, "rain":rain, "dust":dust})

func _volume_batch(label: String, at: Vector3, side: float, mesh: Mesh, count: int, material: ShaderMaterial, salt: int) -> MultiMeshInstance3D:
	var multi := MultiMesh.new()
	multi.transform_format = MultiMesh.TRANSFORM_3D
	multi.use_custom_data = true
	multi.mesh = mesh
	multi.instance_count = count
	multi.visible_instance_count = 0
	# Rain bends by at most 2.0m in the supplied bounded wind; the conservative
	# local AABB encloses that displacement, the drop length and the full column.
	multi.custom_aabb = AABB(Vector3(-side*.5-3.0, -14.0, -side*.5-3.0), Vector3(side+6.0, 28.0, side+6.0))
	for index in range(count):
		var x: float = (_fraction(index, salt) - .5) * side
		var z: float = (_fraction(index, salt + 11) - .5) * side
		multi.set_instance_transform(index, Transform3D(Basis.IDENTITY, Vector3(x, 0, z)))
		multi.set_instance_custom_data(index, Color(_fraction(index, salt+3), _fraction(index, salt+5), _fraction(index, salt+9), 1.0))
	var batch := MultiMeshInstance3D.new()
	batch.name = label + str(_tiles.size())
	batch.position = at
	batch.multimesh = multi
	batch.material_override = material
	batch.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	batch.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	add_child(batch)
	return batch

func _create_flags() -> void:
	var cloth: ArrayMesh = _cloth_mesh(region_id.begins_with("F"))
	for row: Dictionary in _spec.get("flags", []).slice(0, MAX_FLAGS):
		var stand := Node3D.new()
		stand.name = str(row.id)
		stand.position = _v(row.position)
		add_child(stand)
		var height: float = float(row.get("height", 2.0))
		_box(stand, "WindMast", Vector3(0, height*.5, 0), Vector3(.065, height, .065), _material("support", Color(str(_spec.palette.support))))
		var vane := Node3D.new()
		vane.name = "WindDirection"
		vane.position.y = height
		stand.add_child(vane)
		var flag := MeshInstance3D.new()
		flag.name = "LeafRibbon" if region_id.begins_with("F") else "CanvasWindsock"
		flag.mesh = cloth
		flag.material_override = _cloth_material
		flag.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		flag.extra_cull_margin = .3
		vane.add_child(flag)
		_flags.append(vane)

func _create_leaves() -> void:
	var mesh: ArrayMesh = _leaf_mesh()
	for row: Dictionary in _spec.get("leaf_clusters", []):
		var multi := MultiMesh.new()
		multi.transform_format = MultiMesh.TRANSFORM_3D
		multi.mesh = mesh
		multi.instance_count = 12
		multi.custom_aabb = AABB(Vector3(-2.6, -.1, -2.6), Vector3(5.2, 2.9, 5.2))
		for index in range(12):
			var at := Vector3((_fraction(index, 41)-.5)*3.0, 0, (_fraction(index, 53)-.5)*2.5)
			var scale_y: float = .6 + _fraction(index, 67)*.65
			var basis := Basis(Vector3.UP, _fraction(index, 31)*TAU) * Basis.from_scale(Vector3(.6, scale_y, .6))
			multi.set_instance_transform(index, Transform3D(basis, at))
		var batch := MultiMeshInstance3D.new()
		batch.name = str(row.id)
		batch.position = _v(row.position)
		batch.multimesh = multi
		batch.material_override = _leaves_material
		batch.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(batch)
		_leaf_batches.append(batch)

func _create_actor_signals() -> void:
	for id: String in _spec.get("actors", []).slice(0, MAX_ACTOR_SIGNALS):
		var tool := Node3D.new()
		tool.name = id.replace(":", "_") + "_WorkReadout"
		add_child(tool)
		var fork := Node3D.new()
		fork.name = "WorkingTool"
		tool.add_child(fork)
		var support: Material = _material("support", Color(str(_spec.palette.support)))
		for side: float in [-1.0, 1.0]:
			_box(fork, "ToolArm", Vector3(side*.37, -.28, 0), Vector3(.07, .5, .07), support)
			_box(fork, "ToolTip", Vector3(side*.26, -.5, 0), Vector3(.29, .055, .18), _material("work_ready", Color("a4d0a4"), true))
		var cargo := Node3D.new()
		cargo.name = "ExistingCargoReadout"
		cargo.position.y = -.62
		tool.add_child(cargo)
		_box(cargo, "CargoCase", Vector3.ZERO, Vector3(.45, .28, .34), _material("cargo", Color(str(_spec.palette.edge))))
		fork.hide()
		cargo.hide()
		_actor_signals[id] = {"root":tool, "fork":fork, "cargo":cargo}

func _create_counters() -> void:
	for row: Dictionary in _spec.get("maintenance_boards", []):
		var board := Node3D.new()
		board.name = str(row.id)
		board.position = _v(row.position)
		add_child(board)
		_box(board, "CounterBack", Vector3.ZERO, Vector3(1.55, .45, .16), _material("support", Color(str(_spec.palette.support))))
		var lamps: Array[MeshInstance3D] = []
		for index in range(3):
			lamps.append(_box(board, "MaintenanceLamp" + str(index+1), Vector3(-.46+index*.46, .02, .13), Vector3(.25, .25, .10), _material("lamp_off", Color("566b60"))))
		_counter_lamps[str(row.target_id)] = lamps
		var label := Label3D.new()
		label.name = "CounterText"
		label.font = load("res://assets/fonts/NotoSansSC-Medium.ttf")
		label.font_size = 18
		label.pixel_size = .02
		label.outline_size = 3
		label.position.y = .8
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		label.text = str(row.label) + " · 等待已应用维护记录"
		label.hide()
		board.add_child(label)
		_counter_labels[str(row.target_id)] = {"label":label, "name":str(row.label), "board":board}

func _create_grove_workstation() -> void:
	var station := Node3D.new()
	station.name = "F1ExistingGroveCareWorkstation"
	station.set_meta("ecology_target_id", "F1:grove_care")
	station.set_meta("ecology_actor_id", "F1:forest_01")
	add_child(station)
	var root: Material = _material("support", Color(str(_spec.palette.support)))
	var edge: Material = _material("grove_edge", Color(str(_spec.palette.edge)))
	# The existing forest drone works at (5,14,31). A side stem carries its
	# small service cradle; the thin visual never creates a hidden landing deck.
	_box(station, "LivingSupportStem", Vector3(8.4, 6.5, 32.6), Vector3(.38, 13.0, .38), root)
	_box(station, "ServiceArm", Vector3(6.9, 13.15, 32.6), Vector3(3.1, .15, .22), root)
	_box(station, "WorkCradle", Vector3(5.4, 13.15, 31.7), Vector3(1.3, .13, 1.8), edge)
	for index in range(3):
		_box(station, "RootGauge" + str(index), Vector3(8.4+sin(index*2.0)*.13, 12.4+index*.35, 32.6), Vector3(.7, .075, .65), edge)
	_work_arm = Node3D.new()
	_work_arm.name = "ExistingWorkPhaseClamp"
	_work_arm.position = Vector3(5.4, 13.45, 31.7)
	station.add_child(_work_arm)
	for side: float in [-1.0, 1.0]:
		_box(_work_arm, "Clamp", Vector3(side*.55, 0, 0), Vector3(.10, .40, 1.1), root)
	var leaf: MeshInstance3D = _box(station, "CareLeafSample", Vector3(5.4, 13.3, 31.7), Vector3(.28, .12, .9), _material("grove_leaf", Color(str(_spec.palette.leaf))))
	leaf.rotation.y = .4

func _apply(context: Dictionary, ecology: Dictionary, paused: bool, focus: Vector3) -> void:
	if paused and _initialized: return
	var phase: Variant = context.get("clock")
	var wind: Variant = context.get("wind_velocity")
	var weather: String = str(context.get("weather", ""))
	if not (phase is int or phase is float) or not is_finite(float(phase)) or float(phase) < 0.0 or not wind is Vector3 or not wind.is_finite() or weather not in ["clear", "rain", "storm"]: return
	_clock = float(phase)
	_wind = wind.limit_length(6.5)
	_weather = weather
	_initialized = true
	if _ecology_shape(ecology): _last_ecology = ecology.duplicate(true)
	var phase_value: float = fposmod(_clock, 16384.0)
	_rain_material.set_shader_parameter("phase_seconds", phase_value)
	_dust_material.set_shader_parameter("phase_seconds", phase_value)
	_cloth_material.set_shader_parameter("phase_seconds", phase_value)
	_leaves_material.set_shader_parameter("phase_seconds", phase_value)
	for material: ShaderMaterial in [_rain_material, _dust_material, _leaves_material]: material.set_shader_parameter("wind_velocity", _wind)
	_cloth_material.set_shader_parameter("wind_strength", clampf(_wind.length()/6.5, 0.0, 1.0))
	var rain_weight: float = 1.0 if _weather == "storm" else .68 if _weather == "rain" else 0.0
	var dust_weight: float = float(_spec.get("dust_weight", .4)) * (.35 if _weather == "storm" else .6 if _weather == "rain" else 1.0)
	_rain_material.set_shader_parameter("weather_weight", rain_weight)
	_dust_material.set_shader_parameter("weather_weight", dust_weight)
	var local_focus: Vector3 = to_local(focus) if is_inside_tree() and focus.is_finite() else Vector3.ZERO
	for tile: Dictionary in _tiles:
		var delta: Vector3 = tile.centre-local_focus
		var near: bool = Vector2(delta.x, delta.z).length() <= 46.0
		tile.rain.visible = near and rain_weight > 0.0
		tile.dust.visible = near and dust_weight > 0.0
		tile.rain.multimesh.visible_instance_count = MAX_RAIN_PER_TILE if _weather == "storm" else 28 if _weather == "rain" else 0
		tile.dust.multimesh.visible_instance_count = MAX_DUST_PER_TILE if dust_weight > 0.0 else 0
	if Vector2(_wind.x, _wind.z).length_squared() > .001:
		var bearing: float = atan2(-_wind.z, _wind.x)
		for flag: Node3D in _flags: flag.rotation.y = bearing
	for batch: MultiMeshInstance3D in _leaf_batches:
		batch.visible = batch.position.distance_to(local_focus) < 55.0
	_apply_ecology(local_focus)

func _apply_ecology(focus: Vector3) -> void:
	var actors: Dictionary = {}
	for row: Dictionary in _last_ecology.get("actors", []): actors[str(row.id)] = row
	for id: String in _actor_signals:
		var readout: Dictionary = _actor_signals[id]
		var row: Dictionary = actors.get(id, {})
		var point: Variant = row.get("p")
		var valid_point: bool = point is Vector3 and point.is_finite()
		readout.root.visible = valid_point
		if not valid_point: continue
		readout.root.position = point
		readout.fork.visible = row.get("phase") == "working"
		readout.cargo.visible = bool(row.get("cargo", false))
		if readout.fork.visible: readout.fork.rotation.y = sin(_clock*1.5)*.16
	var maintenance: Dictionary = _last_ecology.get("maintenance", {})
	for id: String in _counter_lamps:
		var count: int = clampi(int(maintenance.get(id, 0)), 0, 3)
		var known: bool = not _last_ecology.is_empty()
		var key: String = str(count) + str(known)
		var counter_data: Dictionary = _counter_labels[id]
		if str(_last_counter_keys.get(id, "")) != key:
			_last_counter_keys[id] = key
			var lamps: Array = _counter_lamps[id]
			for index in range(lamps.size()): lamps[index].material_override = _material("lamp_ready", Color("a6d19f"), true) if known and index < count else _material("lamp_off", Color("566b60"))
			counter_data.label.text = str(counter_data.name) + (" · 维护记录 %d/3" % count if known else " · 等待已应用维护记录")
		counter_data.label.visible = counter_data.board.position.distance_to(focus) < 11.0
	if is_instance_valid(_work_arm):
		var forest: Dictionary = actors.get("F1:forest_01", {})
		var working: bool = forest.get("phase") == "working" and forest.get("p") is Vector3 and Vector3(forest.p).distance_to(Vector3(5,14,31)) < 3.0
		_work_arm.scale.x = 1.0 + sin(_clock*2.3)*.12 if working else 1.0

func _ecology_shape(value: Dictionary) -> bool:
	if value.is_empty() or not value.get("actors") is Array or not value.get("maintenance") is Dictionary: return false
	if value.actors.size() > 12 or value.maintenance.size() > 8: return false
	for row: Variant in value.actors:
		if not row is Dictionary or not row.get("id") is String or not row.get("p") is Vector3 or not row.p.is_finite(): return false
	for id: Variant in value.maintenance:
		var number: Variant = value.maintenance[id]
		if not (number is int or number is float) or not is_finite(float(number)) or floorf(float(number)) != float(number) or float(number) < 0.0 or float(number) > 3.0: return false
	return true

func _material(key: String, color: Color, unshaded: bool = false) -> StandardMaterial3D:
	if not _materials.has(key):
		var material := StandardMaterial3D.new()
		material.albedo_color = color
		material.roughness = .95
		if unshaded: material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_materials[key] = material
	return _materials[key]

func _box(parent: Node3D, label: String, at: Vector3, size: Vector3, material: Material) -> MeshInstance3D:
	var visual := MeshInstance3D.new()
	visual.name = label
	var mesh := BoxMesh.new()
	mesh.size = size
	visual.mesh = mesh
	visual.position = at
	visual.material_override = material
	visual.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(visual)
	return visual

static func _fraction(index: int, salt: int) -> float:
	return float(posmod((index+1)*7919+salt*104729, 65521))/65521.0

static func _v(point: Array) -> Vector3:
	return Vector3(float(point[0]), float(point[1]), float(point[2]))

static func _cloth_mesh(leaf: bool) -> ArrayMesh:
	var vertices := PackedVector3Array()
	var uvs := PackedVector2Array()
	var normals := PackedVector3Array()
	var width: float = 1.45 if leaf else 1.6
	for segment in range(6):
		var a: float = float(segment)/6.0
		var b: float = float(segment+1)/6.0
		var ha: float = (.22 + sin(a*PI)*.10) if leaf else .22
		var hb: float = (.22 + sin(b*PI)*.10) if leaf else .22
		var points: Array = [Vector3(a*width, -ha, 0), Vector3(b*width, -hb, 0), Vector3(b*width, hb, 0), Vector3(a*width, -ha, 0), Vector3(b*width, hb, 0), Vector3(a*width, ha, 0)]
		var tex: Array = [Vector2(a,0),Vector2(b,0),Vector2(b,1),Vector2(a,0),Vector2(b,1),Vector2(a,1)]
		for index in range(points.size()): vertices.append(points[index]); uvs.append(tex[index]); normals.append(Vector3.FORWARD)
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_NORMAL] = normals
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh

static func _leaf_mesh() -> ArrayMesh:
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = PackedVector3Array([Vector3(-.12,0,0),Vector3(.16,.7,.03),Vector3(0,1.5,0),Vector3(-.12,0,0),Vector3(0,1.5,0),Vector3(-.2,.75,.02)])
	arrays[Mesh.ARRAY_TEX_UV] = PackedVector2Array([Vector2(0,0),Vector2(1,.5),Vector2(.5,1),Vector2(0,0),Vector2(.5,1),Vector2(0,.5)])
	arrays[Mesh.ARRAY_NORMAL] = PackedVector3Array([Vector3.FORWARD,Vector3.FORWARD,Vector3.FORWARD,Vector3.FORWARD,Vector3.FORWARD,Vector3.FORWARD])
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh
