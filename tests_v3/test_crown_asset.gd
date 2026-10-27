extends SceneTree
## Actual GLB/PhysicsServer suite. Candidate/final identity is explicit in LOCK_STAGE.
## Does not start the main session, profiles, saves or ENet.
const VIEW = preload("res://scenes/v3/assets/parasitic_crown.tscn")
const MODEL_PATH := "res://assets/v3/crown/parasitic_crown.glb"
const LOCK_STAGE := "p6 runtime review lock; game-camera visual acceptance separate"
const LOCKED_SHA256 := "3b87381e7769132367f76ef96e1ee549a3937ad526bd2df1d306a44164c40cde"
const LOCKED_BYTE_COUNT := 16341508
const LOCKED_MATERIAL_MESH_COUNTS: Dictionary = {
	"Crown_ChestnutBark":60, "Crown_WarmStone":13, "Crown_AmberCore":1, "Crown_LeafMembrane":2}
const LOCKED_PLATE_ROTATIONS: Dictionary = {
	"CrownPlatePivot_L":{"axis":Vector3.UP, "degrees":-60.0},
	"CrownPlatePivot_R":{"axis":Vector3.UP, "degrees":72.0},
	"CrownPlatePivot_C":{"axis":Vector3.RIGHT, "degrees":-58.0}}
const LOCKED_ANCHORS: Dictionary = {
	"Core":Vector3(0, -0.5, 1.090000033),
	"CrownPlatePivot_L":Vector3(-1.340000033, 0.5, 0.6200000048),
	"CrownPlatePivot_R":Vector3(1.340000033, 0.4600000083, 0.6200000048),
	"CrownPlatePivot_C":Vector3(0, 0.6000000238, 1.100000024),
	"ClawShoulder_FL":Vector3(-1.330000043, -0.2800000012, 0.4199999869),
	"ClawWrist_FL":Vector3(-2.730000019, -1.520000011, 1.380000025),
	"ClawContact_FL":Vector3(-2.539999962, -3.00000003, 2.170000106),
	"ClawShoulder_FR":Vector3(1.350000024, -0.3600000143, 0.4799999893),
	"ClawWrist_FR":Vector3(2.789999962, -1.679999948, 1.450000018),
	"ClawContact_FR":Vector3(2.50999999, -3, 2.219999999),
	"ClawShoulder_BL":Vector3(-1.210000038, -0.4300000072, -0.9100000262),
	"ClawWrist_BL":Vector3(-2.650000095, -1.98999995, -2.009999931),
	"ClawContact_BL":Vector3(-2.279999971, -2.99999994, -2.49999994),
	"ClawShoulder_BR":Vector3(1.220000029, -0.400000006, -0.9200000167),
	"ClawWrist_BR":Vector3(2.700000048, -1.960000068, -1.979999959),
	"ClawContact_BR":Vector3(2.309999943, -3.00000003, -2.479999959),
	"LeafPivot_L":Vector3(-0.9499999881, 0.6499999762, -1.149999976),
	"LeafPivot_R":Vector3(0.9499999881, 0.6499999762, -1.149999976)}
const LOCKED_BOUNDS: Dictionary = {
	"closed":{"minimum":Vector3(-3.537611246, -3.00000003, -2.711497962), "maximum":Vector3(3.33371973, 2.910000086, 2.433778256)},
	"open":{"minimum":Vector3(-3.537611246, -3.00000003, -2.711497962), "maximum":Vector3(3.33371973, 2.719683170, 2.433778256)}}
const LOCKED_MESH_COUNT := 76
const PLATES := ["CrownPlatePivot_L", "CrownPlatePivot_R", "CrownPlatePivot_C"]

var crown
var stage: Node3D
var checks: Array[Dictionary] = []
var failures: Array[String] = []
var materials: Array[Dictionary] = []

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	_check(not LOCKED_SHA256.is_empty() and LOCKED_ANCHORS.size() >= 18 and LOCKED_BOUNDS.has("closed") and LOCKED_BOUNDS.has("open") and LOCKED_MESH_COUNT > 0, "explicit GLB byte and geometry lock exists before physical asset execution")
	if not failures.is_empty():
		_finish()
		return
	_check(FileAccess.file_exists(MODEL_PATH) and FileAccess.get_sha256(MODEL_PATH) == LOCKED_SHA256, "actual GLB bytes match explicitly identified artist export")
	if not failures.is_empty():
		_finish()
		return
	var model_file := FileAccess.open(MODEL_PATH, FileAccess.READ)
	_check(model_file != null and model_file.get_length() == LOCKED_BYTE_COUNT, "actual GLB byte length matches the p6 binary report")
	if model_file != null: model_file.close()
	stage = Node3D.new()
	root.add_child(stage)
	crown = VIEW.instantiate()
	crown.position = Vector3(10, 13, -22)
	crown.rotation.y = 0.31
	stage.add_child(crown)
	await _settle()
	_check(crown.imported and crown.import_errors.is_empty(), "real GLB imports and satisfies required-node contract", {"errors":crown.import_errors})
	if not crown.imported:
		_finish()
		return
	_test_nodes_and_materials()
	_test_core_rays()
	_test_pause_and_same_frame_poses()
	_test_pending_snapshot()
	_test_movement_envelopes()
	_test_envelope_tightness()
	await _test_instance_isolation()
	_finish()

func _settle() -> void:
	await physics_frame
	await process_frame
	await physics_frame

func _check(ok: bool, label: String, details: Dictionary = {}) -> void:
	checks.append({"ok":ok, "label":label, "details":details})
	if not ok:
		failures.append(label)
		push_error(label)

func _node(key: String) -> Node3D:
	return crown.visual.find_child(key, true, false) as Node3D

func _meshes(node: Node, found: Array[MeshInstance3D]) -> void:
	if node is MeshInstance3D and node.mesh != null: found.append(node)
	for child in node.get_children():
		if not child is CollisionObject3D: _meshes(child, found)

func _state(opened: bool) -> Dictionary:
	return {"type":"parasitic_crown", "mode":"bound" if opened else "attached", "core_open":opened,
		"phase":1, "tick":0, "movement":{}, "anchors":{}, "core_health":160.0}

func _test_nodes_and_materials() -> void:
	var exact := true
	for name in LOCKED_ANCHORS:
		var nodes: Array = crown.visual.find_children(str(name), "Node3D", true, false)
		exact = exact and nodes.size() == 1
		if nodes.size() == 1:
			var actual: Vector3 = crown.visual.to_local((nodes[0] as Node3D).global_position)
			exact = exact and actual.distance_to(LOCKED_ANCHORS[name]) < 0.001
	_check(exact, "actual unique core pivots joints and contacts match locked imported coordinates")
	_check(crown.core_position().distance_to(crown.visual.to_global(LOCKED_ANCHORS.Core)) < 0.001, "public core position follows actual rotated and translated wrapper")
	var parent_chain := true
	for suffix in ["FL", "FR", "BL", "BR"]:
		parent_chain = parent_chain and _node("ClawWrist_" + suffix).get_parent() == _node("ClawShoulder_" + suffix)
		parent_chain = parent_chain and _node("ClawContact_" + suffix).get_parent() == _node("ClawWrist_" + suffix)
	_check(parent_chain, "four shoulder wrist contact parent chains survive real import")
	var meshes: Array[MeshInstance3D] = []
	_meshes(crown.visual, meshes)
	_check(meshes.size() == LOCKED_MESH_COUNT, "actual mesh count matches identified export")
	var correct_layers := true
	var core_bodies := 0
	var triangle_shapes := 0
	for body in crown.collision_bodies():
		var id: String = str(body.get_meta("entity_id", ""))
		correct_layers = correct_layers and body.collision_layer == (0 if id == "boss:crown_core" else 8) and body.collision_mask == 0
		correct_layers = correct_layers and id in ["boss:crown_core", "boss:crown_armor"]
		if id == "boss:crown_core": core_bodies += 1
		for child in body.get_children():
			if child is CollisionShape3D:
				triangle_shapes += 1
				correct_layers = correct_layers and child.shape is ConcavePolygonShape3D
	_check(correct_layers and core_bodies == 1 and triangle_shapes == meshes.size(), "every actual mesh has one triangle collider; closed armor layer8 and independent core disabled")
	var material_mesh_counts: Dictionary = {}
	var named_surfaces := true
	for mesh in meshes:
		named_surfaces = named_surfaces and mesh.mesh.get_surface_count() == 1
		for surface in mesh.mesh.get_surface_count():
			var imported_material := mesh.get_active_material(surface) as BaseMaterial3D
			if imported_material == null:
				named_surfaces = false
				continue
			var material_name := imported_material.resource_name
			material_mesh_counts[material_name] = int(material_mesh_counts.get(material_name, 0)) + 1
	_check(named_surfaces and material_mesh_counts == LOCKED_MATERIAL_MESH_COUNTS, "actual imported material names and per-mesh groups match p6 export", {"groups":material_mesh_counts})
	var valid_materials := true
	for mesh in meshes:
		if str(mesh.name) == "CoreSeed": continue
		for surface in mesh.mesh.get_surface_count():
			var material := mesh.get_active_material(surface) as BaseMaterial3D
			valid_materials = valid_materials and material != null
			if material != null:
				materials.append({"mesh":mesh, "surface":surface, "material":material,
					"albedo":material.albedo_color, "texture":material.albedo_texture,
					"energy":material.emission_energy_multiplier, "emission_enabled":material.emission_enabled})
	_check(valid_materials, "all non-core surfaces retain imported PBR materials")
	var bounds: AABB = _actual_bounds()
	var expected: Dictionary = LOCKED_BOUNDS.closed
	_check(bounds.position.distance_to(expected.minimum) < 0.005 and bounds.end.distance_to(expected.maximum) < 0.005, "closed actual geometry bounds match locked GLB inspection")

func _ray_at(x: float, y: float) -> Dictionary:
	return _ray_for(crown, x, y)

func _ray_for(view, x: float, y: float) -> Dictionary:
	var from: Vector3 = view.visual.to_global(Vector3(x, y, 6))
	var to: Vector3 = view.visual.to_global(Vector3(x, y, 1.09))
	var query := PhysicsRayQueryParameters3D.create(from, to, 8)
	query.hit_back_faces = true
	return stage.get_world_3d().direct_space_state.intersect_ray(query)

func _hit_id(hit: Dictionary) -> String:
	return str(hit.collider.get_meta("entity_id", "")) if not hit.is_empty() else ""

func _nine_hits(expected: String) -> bool:
	return _nine_hits_for(crown, expected)

func _nine_hits_for(view, expected: String) -> bool:
	for x in [-0.25, 0.0, 0.25]:
		for y in [-0.85, -0.5, -0.15]:
			if _hit_id(_ray_for(view, x, y)) != expected: return false
	return true

func _test_core_rays() -> void:
	crown.set_state(_state(false))
	_check(_core_layer() == 0, "closed shell disables the actual intersecting seed collider instead of relying on frontal samples alone")
	var closed_poses: Dictionary = {}
	for key in PLATES: closed_poses[key] = _node(key).transform
	for x in [-0.25, 0.0, 0.25]:
		for y in [-0.85, -0.5, -0.15]:
			var hit := _ray_at(x, y)
			_check(_hit_id(hit) == "boss:crown_armor", "closed armor blocks actual core-grid probe", {"x":x, "y":y, "hit":_hit_id(hit)})
	var closed_energy := _core_energy(crown)
	crown.set_state(_state(true))
	_check(_core_layer() == 8, "open shell enables only the actual core triangle collider")
	for x in [-0.25, 0.0, 0.25]:
		for y in [-0.85, -0.5, -0.15]:
			var hit := _ray_at(x, y)
			_check(_hit_id(hit) == "boss:crown_core", "open armor lets actual core-grid probe reach seed geometry", {"x":x, "y":y, "hit":_hit_id(hit)})
	var moved := true
	for key in PLATES: moved = moved and not _node(key).transform.is_equal_approx(closed_poses[key])
	_check(moved, "all three imported pivots use their authored axes and open")
	var exact_open_angles := true
	for key in PLATES:
		var expected_pose: Transform3D = closed_poses[key]
		var author_rotation: Dictionary = LOCKED_PLATE_ROTATIONS[key]
		expected_pose.basis = expected_pose.basis * Basis(author_rotation.axis, deg_to_rad(float(author_rotation.degrees)))
		exact_open_angles = exact_open_angles and _node(key).transform.is_equal_approx(expected_pose)
	_check(exact_open_angles, "three imported local pivot rotations match explicit p6 author angles")
	_check(_core_energy(crown) > closed_energy and _core_energy(crown) <= 0.2501, "open seed glow is readable and conservatively capped")
	var bounds: AABB = _actual_bounds()
	var expected: Dictionary = LOCKED_BOUNDS.open
	_check(bounds.position.distance_to(expected.minimum) < 0.005 and bounds.end.distance_to(expected.maximum) < 0.005, "open actual geometry bounds match locked imported pose")
	crown.set_state(_state(false))
	var exact_closed := true
	for key in PLATES: exact_closed = exact_closed and _node(key).transform.is_equal_approx(closed_poses[key])
	_check(exact_closed and _core_layer() == 0 and _nine_hits("boss:crown_armor"), "same-frame reclose restores exact rest, disables seed and blocks next shot")

func _test_pause_and_same_frame_poses() -> void:
	paused = true
	crown.set_state(_state(true))
	_check(_nine_hits("boss:crown_core"), "paused snapshot immediately opens real collision without physics or animation time")
	var pose: Transform3D = _node("CrownPlatePivot_L").transform
	crown.set_state(_state(true))
	_check(_node("CrownPlatePivot_L").transform.is_equal_approx(pose) and _nine_hits("boss:crown_core"), "repeated paused snapshot is idempotent")
	crown.set_state(_state(false))
	_check(_core_layer() == 0 and _nine_hits("boss:crown_armor"), "paused rearm immediately disables seed and closes every tested core approach")
	var old_position: Vector3 = crown.position
	crown.position += Vector3(7, 2, -4)
	crown.set_state(_state(false))
	_check(_nine_hits("boss:crown_armor") and crown.core_position().distance_to(crown.visual.to_global(LOCKED_ANCHORS.Core)) < 0.001, "same armor state still submits changed root transform while paused")
	crown.position = old_position
	crown.set_state(_state(false))
	paused = false
	crown.set_state(_state(true))
	_check(_nine_hits("boss:crown_core"), "running-tree session pause also gets immediate opened collision")
	crown.set_state(_state(false))
	_check(_nine_hits("boss:crown_armor"), "running-tree same-frame closed state blocks core")

func _test_pending_snapshot() -> void:
	# Reconstruct a fresh view from received state. This is the wrapper portion
	# of reconnect, not a claim about ENet delivery or session authority.
	paused = true
	for opened in [false, true]:
		var restored = VIEW.instantiate()
		restored.position = Vector3(-100 if opened else -200, 13, 0)
		restored.set_state(_state(opened))
		stage.add_child(restored)
		_check(restored.imported, "paused fresh view accepts cached snapshot before ready: " + str(opened))
		if restored.imported:
			var expected := "boss:crown_core" if opened else "boss:crown_armor"
			_check(_core_layer_for(restored) == (8 if opened else 0) and _nine_hits_for(restored, expected), "first paused restored snapshot immediately sets layer and all nine rays: " + str(opened))
			restored.set_state(_state(not opened))
			expected = "boss:crown_armor" if opened else "boss:crown_core"
			_check(_core_layer_for(restored) == (0 if opened else 8) and _nine_hits_for(restored, expected), "next restored snapshot toggles collision without an intervening physics frame: " + str(opened))
		stage.remove_child(restored)
		restored.free()
	paused = false

func _actual_bounds() -> AABB:
	var minimum := Vector3(INF, INF, INF)
	var maximum := Vector3(-INF, -INF, -INF)
	var meshes: Array[MeshInstance3D] = []
	_meshes(crown.visual, meshes)
	for mesh in meshes:
		for surface in mesh.mesh.get_surface_count():
			var vertices: PackedVector3Array = mesh.mesh.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX]
			for vertex in vertices:
				var point: Vector3 = crown.visual.to_local(mesh.to_global(vertex))
				minimum = minimum.min(point)
				maximum = maximum.max(point)
	return AABB(minimum, maximum - minimum)

func _test_movement_envelopes() -> void:
	var arc: Array = crown._rotation_bounds(Vector3(1, 0, 0), Vector3.ZERO, Vector3.UP, deg_to_rad(135.0))
	_check(absf(arc[0].z + 1.0) < 0.00001 and absf(arc[1].x - 1.0) < 0.00001, "continuous rotation envelope includes90degree bulge missing from0/135degree endpoints")
	var envelopes: Array = crown.movement_shapes()
	var by_name: Dictionary = {}
	for entry in envelopes: by_name[entry.mesh_name] = entry
	_check(envelopes.size() == LOCKED_MESH_COUNT, "all actual meshes contribute conservative motion geometry")
	var meshes: Array[MeshInstance3D] = []
	_meshes(crown.visual, meshes)
	for fraction in [0.0, 0.1, 0.25, 0.333, 0.5, 0.731, 0.9, 1.0]:
		for key in PLATES: crown._pose_plate(key, fraction)
		crown._commit_physics_transforms()
		var contained := true
		for mesh in meshes:
			if not by_name.has(str(mesh.name)):
				contained = false
				continue
			var envelope: Dictionary = by_name[str(mesh.name)]
			var inverse: Transform3D = envelope.transform.affine_inverse()
			var half: Vector3 = (envelope.shape as BoxShape3D).size * 0.5
			for surface in mesh.mesh.get_surface_count():
				var vertices: PackedVector3Array = mesh.mesh.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX]
				for vertex in vertices:
					var point: Vector3 = inverse * crown.to_local(mesh.to_global(vertex))
					contained = contained and absf(point.x) <= half.x and absf(point.y) <= half.y and absf(point.z) <= half.z
		_check(contained, "every actual vertex lies inside returned motion envelope at pose " + str(fraction))
	# Change presentation key so the public method restores the diagnostic intermediate pose.
	crown.set_state(_state(true))
	crown.set_state(_state(false))
	var transformed: Array = crown.movement_shapes()
	transformed[0].transform = Transform3D.IDENTITY
	_check(crown.movement_shapes()[0].transform == envelopes[0].transform, "caller descriptor edits cannot overwrite stored envelope transform")

func _core_energy(view) -> float:
	var mesh := view.visual.find_child("CoreSeed", true, false) as MeshInstance3D
	var material := mesh.get_active_material(0) as BaseMaterial3D
	return material.emission_energy_multiplier if material.emission_enabled else 0.0

func _core_layer() -> int:
	return _core_layer_for(crown)

func _core_layer_for(view) -> int:
	for body in view.collision_bodies():
		if str(body.get_meta("entity_id", "")) == "boss:crown_core": return int(body.collision_layer)
	return -1

func _test_envelope_tightness() -> void:
	# Containment alone cannot detect an unnecessarily huge query volume. Check
	# the static meshes exactly, and compare hinge envelopes with dense actual
	# imported poses (not the wrapper's analytic bounds function).
	var envelopes: Dictionary = {}
	for entry in crown.movement_shapes(): envelopes[str(entry.mesh_name)] = entry
	var meshes: Array[MeshInstance3D] = []
	_meshes(crown.visual, meshes)
	var sampled: Dictionary = {}
	var moving: Array[MeshInstance3D] = []
	for mesh in meshes:
		var ancestor: Node = mesh.get_parent()
		var hinged := false
		while ancestor != null and ancestor != crown.visual:
			if str(ancestor.name) in PLATES: hinged = true
			ancestor = ancestor.get_parent()
		if hinged: moving.append(mesh)
		else: sampled[str(mesh.name)] = _mesh_bounds_in_wrapper(mesh)
	for step in range(129):
		for key in PLATES: crown._pose_plate(key, float(step) / 128.0)
		for mesh in moving:
			var bounds: AABB = _mesh_bounds_in_wrapper(mesh)
			var key := str(mesh.name)
			if sampled.has(key):
				var previous: AABB = sampled[key]
				sampled[key] = previous.merge(bounds)
			else:
				sampled[key] = bounds
	var static_error := 0.0
	var hinge_error := 0.0
	var worst_static := ""
	var worst_hinge := ""
	var lowest_actual := INF
	var lowest_envelope := INF
	for mesh in meshes:
		var key := str(mesh.name)
		var entry: Dictionary = envelopes[key]
		var half: Vector3 = (entry.shape as BoxShape3D).size * 0.5
		var query_min: Vector3 = entry.transform.origin - half
		var query_max: Vector3 = entry.transform.origin + half
		var actual: AABB = sampled[key]
		var error := maxf((query_min + Vector3.ONE * 0.002).distance_to(actual.position), (query_max - Vector3.ONE * 0.002).distance_to(actual.end))
		lowest_actual = minf(lowest_actual, actual.position.y)
		lowest_envelope = minf(lowest_envelope, query_min.y)
		if mesh in moving:
			if error > hinge_error:
				hinge_error = error
				worst_hinge = key
		elif error > static_error:
			static_error = error
			worst_static = key
	_check(static_error < 0.0001, "rest limbs and feet retain exact per-mesh bounds plus2mm, with no crown-angle inflation", {"maximum_error_m":static_error, "mesh":worst_static})
	_check(hinge_error < 0.0005, "continuous crown envelopes stay within0.5mm of129 actual imported poses", {"maximum_error_m":hinge_error, "mesh":worst_hinge, "hinged_mesh_count":moving.size()})
	_check(absf(lowest_envelope + 0.002 - lowest_actual) < 0.0005, "movement query lower limit follows actual lowest geometry plus2mm only", {"actual_min_y":lowest_actual, "query_min_y":lowest_envelope})
	crown.set_state(_state(true))
	crown.set_state(_state(false))

func _mesh_bounds_in_wrapper(mesh: MeshInstance3D) -> AABB:
	var minimum := Vector3(INF, INF, INF)
	var maximum := Vector3(-INF, -INF, -INF)
	for surface in mesh.mesh.get_surface_count():
		var vertices: PackedVector3Array = mesh.mesh.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX]
		for vertex in vertices:
			var point: Vector3 = crown.to_local(mesh.to_global(vertex))
			minimum = minimum.min(point)
			maximum = maximum.max(point)
	return AABB(minimum, maximum - minimum)

func _test_instance_isolation() -> void:
	var second = VIEW.instantiate()
	second.position = Vector3(100, 0, 0)
	stage.add_child(second)
	await _settle()
	_check(second.imported, "second GLB instance initializes independently")
	if not second.imported:
		second.queue_free()
		return
	var other_energy := _core_energy(second)
	crown.set_state(_state(false), true)
	_check(_core_energy(crown) == 0 and _core_energy(second) == other_energy and other_energy > 0, "defeated core turns off without mutating another instance")
	_check(_nine_hits("boss:crown_core"), "defeated pose remains open for inspection")
	var untouched := true
	for entry in materials:
		var material := entry.mesh.get_active_material(entry.surface) as BaseMaterial3D
		untouched = untouched and material == entry.material and material.albedo_color == entry.albedo and material.albedo_texture == entry.texture
		untouched = untouched and material.emission_energy_multiplier == entry.energy and material.emission_enabled == entry.emission_enabled
		untouched = untouched and entry.mesh.material_override == null and entry.mesh.get_surface_override_material(entry.surface) == null
	_check(untouched, "all imported non-core PBR materials and textures remain untouched through poses")
	second.queue_free()

func _finish() -> void:
	paused = false
	print("V3_CROWN_ASSET_TESTS " + JSON.stringify({"checks":checks, "check_count":checks.size(), "failures":failures,
		"passed":failures.is_empty(), "lock_stage":LOCK_STAGE, "locked_sha256":LOCKED_SHA256, "engine":Engine.get_version_info(),
		"limits":["Only the explicitly identified GLB bytes and immediate authored triangle collision.", "No session, profile, durable save, LAN, GPU appearance, performance or human combat evidence."]}))
	if is_instance_valid(stage): stage.queue_free()
	quit(0 if failures.is_empty() else 1)
