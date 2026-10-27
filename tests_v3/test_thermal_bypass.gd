extends SceneTree
## Real imported asset/view test. No Session, authority, profile or ENet.
## Missing final GLB lock is pending integration (exit2), never an asset pass.
const View = preload("res://scenes/v3/assets/thermal_bypass.tscn")
const MODEL_PATH := "res://assets/v3/thermal_bypass/thermal_bypass.glb"
# Filled only after the artist's actual exported-byte/transform inspection.
const LOCKED_SHA256 := "c9ae203562a36038b807dccea4e410f26356273c9130251e9d972e80491ab7f9"
const LOCKED_BOUNDS := AABB(Vector3(-1.4800000190734863, 0.0, -0.9299999475479126), Vector3(2.9600001573562622, 1.9739999771118164, 1.8599998950958252))
const LOCKED_FAN_PIVOT := Vector3(-0.699999988079071, 1.0, 0.6800000071525574)
const LOCKED_TRIANGLES := 11868
const LOCKED_MESHES := 6
var stage: Node3D
var first
var second
var raw: Node3D
var checks: Array = []
var failures: Array = []

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool, label: String, detail: Dictionary = {}) -> void:
	checks.append({"name":label,"passed":ok,"detail":detail})
	if not ok:
		failures.append(label)
		push_error("THERMAL BYPASS: " + label + " " + JSON.stringify(detail))

func _run() -> void:
	if LOCKED_SHA256.is_empty() or not LOCKED_BOUNDS.has_volume() or not LOCKED_FAN_PIVOT.is_finite():
		print("THERMAL_BYPASS_PENDING: final GLB SHA/bounds are not locked; no placeholder asset tested")
		finish(2)
		return
	check(FileAccess.file_exists(MODEL_PATH) and FileAccess.get_sha256(MODEL_PATH) == LOCKED_SHA256, "actual source GLB matches artist's final byte lock")
	if not failures.is_empty():
		finish(1)
		return
	stage = Node3D.new()
	root.add_child(stage)
	first = View.instantiate()
	first.position = Vector3(-29, 0, 8) # Bottom origin below the entity centre Y1.
	stage.add_child(first)
	second = View.instantiate()
	second.position = Vector3(10, 0, 0)
	second.rotation.y = 0.43
	second.set_state({"temperature":70.0,"powered":true}) # Supported before _ready.
	stage.add_child(second)
	raw = (load(MODEL_PATH) as PackedScene).instantiate() as Node3D
	stage.add_child(raw)
	await settle()
	check(first.imported and second.imported, "two real wrappers import the actual node/material contract", {"first":first.import_errors,"second":second.import_errors})
	if not first.imported or not second.imported:
		finish(1)
		return
	first.set_process(false)
	second.set_process(false)
	var original_materials = material_snapshot(raw)
	var original_static = material_snapshot(first.visual, true)
	var triangles := 0
	var material_names: Dictionary = {}
	var pbr_textures_present := true
	for mesh in meshes(raw):
		for surface in range(mesh.mesh.get_surface_count()):
			var arrays = mesh.mesh.surface_get_arrays(surface)
			var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
			triangles += (indices.size() if not indices.is_empty() else arrays[Mesh.ARRAY_VERTEX].size()) / 3
			var material = mesh.get_active_material(surface) as BaseMaterial3D
			if material == null:
				pbr_textures_present = false
				continue
			material_names[material.resource_name] = true
			pbr_textures_present = pbr_textures_present and material.albedo_texture != null and material.normal_texture != null and material.normal_enabled and material.roughness_texture != null
	check(meshes(raw).size() == LOCKED_MESHES and triangles == LOCKED_TRIANGLES and material_names.size() == 6, "actual imported content retains six meshes six materials and 11868 triangles", {"meshes":meshes(raw).size(),"triangles":triangles,"materials":material_names.keys()})
	check(pbr_textures_present, "every actual imported material has authored basecolor normal and roughness textures")
	var bounds = bounds_of(first.visual)
	check(bounds.position.distance_to(LOCKED_BOUNDS.position) < 0.005 and bounds.end.distance_to(LOCKED_BOUNDS.end) < 0.005, "actual imported vertices match final independent bounds", {"min":str(bounds.position),"max":str(bounds.end)})
	check(bounds.position.x >= -1.505 and bounds.end.x <= 1.505 and bounds.position.y >= -0.005 and bounds.end.y <= 2.005 and bounds.position.z >= -1.005 and bounds.end.z <= 1.005, "bottom-origin asset fits reserved 3x2x2 metre envelope")
	check(first.visual.transform.is_equal_approx(Transform3D.IDENTITY), "authored asset root has unit rest transform")
	check(first.find_children("*", "CollisionObject3D", true, false).is_empty() and first.visual.find_children("*", "Camera3D", true, false).is_empty() and first.visual.find_children("*", "Light3D", true, false).is_empty(), "view owns no collision or imported studio lights/cameras")
	var fan: Node3D = first.visual.find_child("FanRotor", true, false)
	check(fan.basis.is_equal_approx(Basis.IDENTITY), "actual imported fan pivot rest basis matches +Z-axis contract")
	check(first.visual.to_local(fan.global_position).distance_to(LOCKED_FAN_PIVOT) < 0.005, "real fan pivot matches artist's independently measured asset coordinate")
	var private_materials = true
	var preserved_textures = true
	var dedicated_material_names = true
	for key in ["HeatPipes", "StatusLens"]:
		var a = group_materials(first.visual, key)
		var b = group_materials(second.visual, key)
		var source = group_materials(raw, key)
		var expected_name: String = "TB_CopperHeat" if key == "HeatPipes" else "TB_StatusLens"
		dedicated_material_names = dedicated_material_names and source.size() == 1 and source[0].resource_name == expected_name
		private_materials = private_materials and not a.is_empty() and a.size() == b.size() and a.size() == source.size()
		if a.size() != b.size() or a.size() != source.size(): continue
		for i in range(a.size()):
			private_materials = private_materials and a[i] != b[i] and a[i] != source[i] and b[i] != source[i]
			preserved_textures = preserved_textures and a[i].albedo_texture == source[i].albedo_texture and a[i].normal_texture == source[i].normal_texture and a[i].roughness_texture == source[i].roughness_texture
	check(private_materials, "only dedicated heat/lens faces receive per-instance material copies")
	check(dedicated_material_names, "actual dedicated groups contain only their agreed copper and temperature-window materials")
	check(preserved_textures, "material copies preserve authored basecolor normal and roughness textures")
	var second_before = material_snapshot(second.visual)
	var cool = {"temperature":20.0,"powered":false,"unrelated":{"charge":19,"revision":8}}
	var warm = {"temperature":45.0,"powered":false,"unrelated":{"charge":19,"revision":8}}
	var hot = {"temperature":70.0,"powered":true,"unrelated":{"charge":19,"revision":8}}
	var inputs = [cool.duplicate(true), warm.duplicate(true), hot.duplicate(true)]
	first.set_state(cool)
	var e20 = glow(first.visual, "HeatPipes")
	var c20: Color = group_materials(first.visual, "HeatPipes")[0].albedo_color
	var lens20: Color = group_materials(first.visual, "StatusLens")[0].emission
	check(glow(first.visual, "StatusLens") > 0.0 and lens20.b > lens20.r, "unpowered20 still shows a cool cyan temperature window")
	first.set_state(warm)
	var e45 = glow(first.visual, "HeatPipes")
	var lens45: Color = group_materials(first.visual, "StatusLens")[0].emission
	first.set_state(hot)
	var e70 = glow(first.visual, "HeatPipes")
	var lens70: Color = group_materials(first.visual, "StatusLens")[0].emission
	var lens_hot_energy = glow(first.visual, "StatusLens")
	check(e20 == 0.0 and e45 > e20 and e70 > e45 and e70 <= 0.16, "20 45 70 produce ordered restrained heat feedback", {"emission20":e20,"emission45":e45,"emission70":e70})
	check(lens20.b > 0.8 and lens20.r < 0.4 and lens45.r > 0.95 and lens45.g > 0.6 and lens45.g < 0.85 and lens45.b < 0.4 and lens70.r > 0.95 and lens70.g < 0.5 and lens70.b < 0.3, "temperature window keeps distinct saturated cyan amber and orange-red at three reference temperatures", {"cold":str(lens20),"warm":str(lens45),"hot":str(lens70)})
	check(group_materials(first.visual, "HeatPipes")[0].albedo_color != c20 and lens_hot_energy > 0.0 and lens_hot_energy <= 0.8, "hot state warms dedicated pipes and keeps temperature-window emission within reviewed limit")
	check(glow(second.visual, "HeatPipes") == e70 and group_materials(second.visual, "StatusLens")[0].emission == lens70, "state supplied before entering the tree restores hot temperature appearance")
	check([cool, warm, hot] == inputs, "set_state never writes temperature power or nested entity data")
	check(material_snapshot(second.visual) == second_before and material_snapshot(raw) == original_materials, "state changes do not leak into another view or imported material resources")
	check(material_snapshot(first.visual, true) == original_static, "housing hardware and fan materials retain authored properties")
	var before_repeat = material_snapshot(first.visual)
	first.set_state(hot)
	check(material_snapshot(first.visual) == before_repeat, "same state reuses material instances without changing their properties")
	first.set_state({"temperature":NAN,"powered":false})
	check(material_snapshot(first.visual) == before_repeat, "nonfinite temperature cannot corrupt or replace valid visual state")
	# Deterministic visual delta probes; these are not natural combat timing.
	var fan_origin = fan.position
	first.set_state({"temperature":45.0,"powered":true})
	var old_basis = fan.basis
	first._process(0.1)
	var step45 = (old_basis.inverse() * fan.basis).get_rotation_quaternion().get_angle()
	first.set_state(hot)
	old_basis = fan.basis
	first._process(0.1)
	var step70 = (old_basis.inverse() * fan.basis).get_rotation_quaternion().get_angle()
	check(step45 > 0.0 and step70 > step45 and fan.position == fan_origin, "powered fan visibly accelerates with heat around its real pivot", {"step45":step45,"step70":step70})
	var axis = (first.visual.global_basis.inverse() * fan.global_basis.z).normalized()
	check(axis.distance_to(Vector3(0, 0, 1)) < 0.001, "fan rotation preserves declared imported asset +Z axle")
	first.set_state({"temperature":70.0,"powered":false})
	var stopped: Transform3D = fan.transform
	first._process(0.1)
	check(fan.transform == stopped and glow(first.visual, "HeatPipes") == e70 and glow(first.visual, "StatusLens") == lens_hot_energy and group_materials(first.visual, "StatusLens")[0].emission == lens70, "power off stops rotor without erasing hot pipes or the temperature window")
	first.set_state(hot)
	first.set_animation_paused(true)
	stopped = fan.transform
	first._process(0.1)
	check(fan.transform == stopped and group_materials(first.visual, "StatusLens")[0].emission == lens70, "simulation animation pause retains static temperature color")
	first.set_state({"temperature":45.0,"powered":true})
	first._process(0.1)
	check(fan.transform == stopped and glow(first.visual, "HeatPipes") == e45 and group_materials(first.visual, "StatusLens")[0].emission == lens45, "authoritative temperature window restores while rotor animation stays paused")
	first.set_animation_paused(false)
	first._process(0.1)
	check(not fan.transform.is_equal_approx(stopped), "animation resumes from retained phase")
	# Actual SceneTree pause must also stop an automatically processed rotor.
	first.set_process(true)
	paused = true
	stopped = fan.transform
	first.set_state(hot)
	await create_timer(0.06, true).timeout
	check(paused and fan.transform == stopped and glow(first.visual, "HeatPipes") == e70 and group_materials(first.visual, "StatusLens")[0].emission == lens70, "real SceneTree pause stops motion but allows immediate hot-temperature restoration")
	paused = false
	await create_timer(0.06).timeout
	check(not fan.transform.is_equal_approx(stopped), "real process frames resume fan after SceneTree unpauses")
	check(material_snapshot(raw) == original_materials and FileAccess.get_sha256(MODEL_PATH) == LOCKED_SHA256, "imported shared materials and source GLB remain unchanged after all states")
	finish(0 if failures.is_empty() else 1)

func settle() -> void:
	await process_frame
	await process_frame

func meshes(node: Node) -> Array[MeshInstance3D]:
	var result: Array[MeshInstance3D] = []
	if node is MeshInstance3D and node.mesh != null: result.append(node)
	for child in node.get_children(): result.append_array(meshes(child))
	return result

func group_materials(owner: Node3D, key: String) -> Array[BaseMaterial3D]:
	var result: Array[BaseMaterial3D] = []
	var group = owner.find_child(key, true, false)
	if group == null: return result
	for mesh in meshes(group):
		for surface in range(mesh.mesh.get_surface_count()): result.append(mesh.get_active_material(surface) as BaseMaterial3D)
	return result

func glow(owner: Node3D, key: String) -> float:
	var value = 0.0
	for material in group_materials(owner, key):
		if material.emission_enabled: value = maxf(value, material.emission_energy_multiplier)
	return value

func material_snapshot(owner: Node3D, static_only: bool = false) -> Dictionary:
	var result: Dictionary = {}
	var excluded: Array = []
	if static_only:
		for key in ["HeatPipes", "StatusLens"]: excluded.append_array(meshes(owner.find_child(key, true, false)))
	for mesh in meshes(owner):
		if mesh in excluded: continue
		for surface in range(mesh.mesh.get_surface_count()):
			var material = mesh.get_active_material(surface) as BaseMaterial3D
			result[str(owner.get_path_to(mesh)) + ":" + str(surface)] = {"id":material.get_instance_id(),"albedo":material.albedo_color,"emission":material.emission,"enabled":material.emission_enabled,"energy":material.emission_energy_multiplier,"roughness":material.roughness,"metallic":material.metallic,"normal_enabled":material.normal_enabled,"normal_scale":material.normal_scale}
	return result

func bounds_of(owner: Node3D) -> AABB:
	var result := AABB()
	var first_vertex := true
	for mesh in meshes(owner):
		var relative: Transform3D = owner.global_transform.affine_inverse() * mesh.global_transform
		for surface in range(mesh.mesh.get_surface_count()):
			var arrays = mesh.mesh.surface_get_arrays(surface)
			for vertex: Vector3 in arrays[Mesh.ARRAY_VERTEX]:
				var at: Vector3 = relative * vertex
				if first_vertex:
					result = AABB(at, Vector3.ZERO)
					first_vertex = false
				else: result = result.expand(at)
	return result

func finish(code: int) -> void:
	print("THERMAL_BYPASS checks=%d failures=%d pending=%s" % [checks.size(),failures.size(),code == 2])
	print("THERMAL_BYPASS_RESULT " + JSON.stringify({"passed":code == 0,"pending_asset":code == 2,"checks":checks,"failures":failures,"locked_sha256":LOCKED_SHA256,"limits":["Real source GLB/view only; no placeholder model accepted.","No authority/world collision, real F action, gate-opening, save, network, GPU art or performance acceptance.","Manual visual deltas plus real SceneTree pause/resume; no gameplay timing inference."]}))
	paused = false
	if is_instance_valid(stage): stage.free()
	quit(code)
