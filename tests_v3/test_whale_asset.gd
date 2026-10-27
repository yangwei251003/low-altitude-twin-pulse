extends SceneTree
## Real imported GLB + PhysicsServer; no main session, profile, save or ENet.
const VIEW = preload("res://scenes/v3/assets/siphon_whale.tscn")
const MODEL_PATH := "res://assets/v3/whale/siphon_whale.glb"
# Filled from the artist's final exported-byte inspection, never a silhouette draft.
const LOCKED_SHA256 := "3c9b81c57e602cee7ed0edc5d16917770682d94e2bbbb1a8ae4c46cb1ae244ae"
const LOCKED_MIN := Vector3(-8.4348735809, -2.2049999237, -9.8375930786)
const LOCKED_MAX := Vector3(8.4348735809, 2.5950000286, 6.8299999237)
const LOCKED_ANCHORS: Dictionary = {
	"core":Vector3(0, 2.02, 3.1), "port":Vector3(-7, 0.65, 0),
	"starboard":Vector3(7, 0.65, 0), "attack":Vector3(0, -0.2, 6.9),
	"retry":Vector3(-28, -0.8, 14), "raw_record":Vector3(0, 3.05, 3.1)}
const OBLIQUE_ORIGINS := {"core":Vector3(0, 4.5, 9), "port":Vector3(-10, 3, 5), "starboard":Vector3(10, 3, 5)}

var whale
var stage: Node3D
var checks: Array[Dictionary] = []
var failures: Array[String] = []
var baseline_materials: Dictionary = {}

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	_check(not LOCKED_SHA256.is_empty() and LOCKED_ANCHORS.size() == 6, "final asset lock recorded before execution")
	if LOCKED_SHA256.is_empty() or LOCKED_ANCHORS.size() != 6:
		_finish()
		return
	_check(FileAccess.file_exists(MODEL_PATH) and FileAccess.get_sha256(MODEL_PATH) == LOCKED_SHA256, "actual GLB bytes match final artist lock")
	if not failures.is_empty():
		_finish()
		return
	stage = Node3D.new()
	root.add_child(stage)
	whale = VIEW.instantiate()
	whale.position = Vector3(14, 6, -32)
	whale.rotation.y = 0.31
	stage.add_child(whale)
	await _settle()
	_check(whale.imported, "wrapper accepts complete imported node and material contract", {"errors":whale.import_errors})
	if not whale.imported:
		_finish()
		return
	_test_structure()
	_test_anchors()
	_capture_materials()
	await _test_opening_and_collision()
	_test_immediate_restore()
	await _test_paused_restore()
	await _test_material_isolation()
	_finish()

func _check(ok: bool, label: String, detail: Dictionary = {}) -> void:
	checks.append({"name":label, "passed":ok, "detail":detail})
	if not ok: failures.append(label)

func _settle() -> void:
	await physics_frame
	await physics_frame
	await process_frame

func _meshes(node: Node) -> Array[MeshInstance3D]:
	var result: Array[MeshInstance3D] = []
	if node is MeshInstance3D and node.mesh != null: result.append(node)
	for child in node.get_children():
		if not child is CollisionObject3D: result.append_array(_meshes(child))
	return result

func _node(key: String) -> Node3D:
	return whale.visual.find_child(key, true, false) as Node3D

func _bounds() -> AABB:
	var result := AABB()
	var first := true
	for mesh in _meshes(whale.visual):
		var relative: Transform3D = whale.visual.global_transform.affine_inverse() * mesh.global_transform
		var box: AABB = relative * mesh.get_aabb()
		result = box if first else result.merge(box)
		first = false
	return result

func _test_structure() -> void:
	var bounds := _bounds()
	_check(bounds.position.distance_to(LOCKED_MIN) < 0.025 and bounds.end.distance_to(LOCKED_MAX) < 0.025, "closed GLB dimensions match final independently measured bounds", {"min":_vec(bounds.position), "max":_vec(bounds.end), "size":_vec(bounds.size)})
	_check(whale.visual.find_children("*", "Camera3D", true, false).is_empty() and whale.visual.find_children("*", "Light3D", true, false).is_empty(), "production GLB excludes studio camera and lights")
	var bodies: Array[PhysicsBody3D] = whale.collision_bodies()
	var valid := bodies.size() == 4
	for body in bodies:
		valid = valid and body.collision_layer == 8 and body.collision_mask == 0
		valid = valid and str(body.get_meta("entity_id", "")) in ["boss:hull", "boss:armor"]
		var shapes := 0
		for child in body.get_children():
			if child is CollisionShape3D:
				shapes += 1
				valid = valid and child.shape is ConcavePolygonShape3D and child.shape.get_faces().size() > 0
				valid = valid and child.shape.backface_collision
		valid = valid and shapes > 0
	_check(valid, "four authored triangle collision groups use armor layer; no whole-hull convex box")
	bodies.clear()
	_check(whale.collision_bodies().size() == 4, "collision list cannot be cleared by a caller")

func _test_anchors() -> void:
	for part in ["core", "port", "starboard"]:
		var local: Vector3 = whale.visual.to_local(whale.weakpoint_position(part))
		_check(local.distance_to(LOCKED_ANCHORS[part]) < 0.005, part + " weakpoint uses exported anchor under translated/rotated wrapper", {"local":_vec(local)})
	_check(whale.visual.to_local(whale.attack_origin()).distance_to(LOCKED_ANCHORS.attack) < 0.005, "attack origin uses actual imported mouth anchor")
	_check(whale.visual.to_local(whale.retry_entry()).distance_to(LOCKED_ANCHORS.retry) < 0.005, "retry entry uses actual imported entrance anchor")
	_check(whale.visual.to_local(whale.raw_record_position()).distance_to(LOCKED_ANCHORS.raw_record) < 0.005, "post-battle record uses its unique exported inspection anchor")
	_check(not whale.weakpoint_position("missing").is_finite(), "unknown weakpoint cannot silently target world origin")

func _capture_materials() -> void:
	for mesh in _meshes(whale.visual):
		if str(mesh.name) in ["CoreGlow", "PortGlow", "StarboardGlow"]: continue
		for surface in range(mesh.mesh.get_surface_count()):
			var material := mesh.get_active_material(surface) as BaseMaterial3D
			baseline_materials[str(whale.visual.get_path_to(mesh)) + ":" + str(surface)] = {
				"mesh":mesh, "surface":surface, "material":material, "albedo":material.albedo_color,
				"emission_enabled":material.emission_enabled, "emission":material.emission,
				"energy":material.emission_energy_multiplier, "texture":material.albedo_texture}

func _ray(part: String, oblique := false) -> Dictionary:
	var target: Vector3 = whale.weakpoint_position(part)
	var up: Vector3 = whale.visual.global_basis.y.normalized()
	var origin: Vector3 = whale.visual.to_global(OBLIQUE_ORIGINS[part]) if oblique else target + up * 5.0
	var query := PhysicsRayQueryParameters3D.create(origin, target, 8)
	query.hit_back_faces = true
	return stage.get_world_3d().direct_space_state.intersect_ray(query)

func _source(hit: Dictionary) -> String:
	return str(hit.collider.get_meta("asset_source", "")) if not hit.is_empty() else ""

func _hatch_center(key: String) -> Vector3:
	var mesh := _meshes(_node(key))[0]
	return whale.visual.to_local(mesh.to_global(mesh.get_aabb().get_center()))

func _glow_energy(key: String, view = null) -> float:
	var owner_view = whale if view == null else view
	var mesh := owner_view.visual.find_child(key, true, false) as MeshInstance3D
	var material := mesh.get_active_material(0) as BaseMaterial3D
	return material.emission_energy_multiplier if material.emission_enabled else 0.0

func _state(open_window: bool, exposed: bool, port_powered := true, starboard_powered := true) -> Dictionary:
	return {"phase":"exposed" if exposed else "shielded", "nodes_open":open_window,
		"nodes":{"port":{"powered":port_powered}, "starboard":{"powered":starboard_powered}}}

func _test_opening_and_collision() -> void:
	whale.set_state(_state(false, false))
	await _settle()
	var port_closed := _hatch_center("PortHatchPivot")
	var starboard_closed := _hatch_center("StarboardHatchPivot")
	var shield_closed: Transform3D = _node("CoreShield").transform
	for part in ["core", "port", "starboard"]:
		var hit := _ray(part)
		var expected: String = {"core":"CoreShield", "port":"PortHatchPivot", "starboard":"StarboardHatchPivot"}[part]
		_check(_source(hit) == expected, part + " closed armor physically blocks its top approach", {"source":_source(hit)})
		_check(_source(_ray(part, true)) == expected, part + " closed armor blocks the final asset's oblique approach")
	whale.set_state(_state(true, false))
	await _settle()
	_check(_hatch_center("PortHatchPivot").y > port_closed.y + 0.4 and _hatch_center("StarboardHatchPivot").y > starboard_closed.y + 0.4, "actual imported left/right hinge axes raise both covers")
	_check(_ray("port").is_empty() and _ray("starboard").is_empty(), "open side covers leave both real weakpoint approaches clear")
	_check(_ray("port", true).is_empty() and _ray("starboard", true).is_empty(), "open side covers clear the final oblique probes")
	_check(_source(_ray("core")) == "CoreShield", "node window does not accidentally expose core")
	var powered_energy := _glow_energy("PortGlow")
	whale.set_state(_state(false, false, false, true))
	await _settle()
	_check(_ray("port").is_empty() and _source(_ray("starboard")) == "StarboardHatchPivot", "disabled port remains inspectable while rearmed starboard closes independently")
	_check(_glow_energy("PortGlow") == 0 and _glow_energy("StarboardGlow") > 0 and powered_energy > 0, "each independently powered side cell has its own emissive state")
	var shielded_energy := _glow_energy("CoreGlow")
	whale.set_state(_state(false, true, false, false))
	await _settle()
	_check(_ray("core").is_empty(), "open core shield reveals the real recessed hole instead of a whole-hull collider")
	_check(_ray("core", true).is_empty(), "retracted core shield clears the final oblique probe")
	_check(_glow_energy("CoreGlow") > shielded_energy, "exposure illuminates only the independent core surface")
	_check(_glow_energy("CoreGlow") <= 0.3151 and _glow_energy("CoreGlow") > 0, "exposed emission stays capped so the imported cylinder shading remains available")
	var open_pose: Transform3D = _node("CoreShield").transform
	_check(not open_pose.is_equal_approx(shield_closed), "core collision parent follows actual retracting shield")
	whale.set_state(_state(false, false))
	await _settle()
	_check(_node("CoreShield").transform.is_equal_approx(shield_closed) and _source(_ray("core")) == "CoreShield", "rearm restores exact closed shield pose and collision")

func _test_paused_restore() -> void:
	paused = true
	whale.set_state(_state(false, true, false, false))
	var port_pose: Transform3D = _node("PortHatchPivot").transform
	var core_pose: Transform3D = _node("CoreShield").transform
	var core_hit := _ray("core")
	var port_hit := _ray("port")
	var starboard_hit := _ray("starboard")
	_check(core_hit.is_empty() and port_hit.is_empty() and starboard_hit.is_empty(), "paused state application updates physics without animation time", {"core":_source(core_hit), "port":_source(port_hit), "starboard":_source(starboard_hit)})
	whale.set_state(_state(false, true, false, false))
	_check(_node("PortHatchPivot").transform.is_equal_approx(port_pose) and _node("CoreShield").transform.is_equal_approx(core_pose), "repeated paused snapshot is pose-idempotent")
	whale.set_state(_state(false, false))
	_check(_source(_ray("core")) == "CoreShield" and _source(_ray("port")) == "PortHatchPivot" and _source(_ray("starboard")) == "StarboardHatchPivot", "paused rearm immediately closes corresponding collisions")
	paused = false
	await _settle()
	_check(_source(_ray("core")) == "CoreShield" and _source(_ray("port")) == "PortHatchPivot", "resume does not replay a stale queued open pose")

func _test_immediate_restore() -> void:
	# Session pause leaves SceneTree running. Both forms must be valid before
	# another physics step; no await is allowed between apply and query here.
	whale.set_state(_state(false, true, false, false))
	_check(_ray("core").is_empty() and _ray("port").is_empty() and _ray("starboard").is_empty(), "running-tree restore commits all opened armor before another physics step")
	whale.set_state(_state(false, false))
	_check(_source(_ray("core")) == "CoreShield" and _source(_ray("port")) == "PortHatchPivot" and _source(_ray("starboard")) == "StarboardHatchPivot", "same-frame rearm blocks the next attack without a physics wait")

func _test_material_isolation() -> void:
	var second = VIEW.instantiate()
	second.position = Vector3(100, 10, 100)
	stage.add_child(second)
	await _settle()
	_check(second.imported, "second imported instance initializes independently")
	var other_energy := _glow_energy("PortGlow", second)
	whale.set_state({}, true)
	await _settle()
	_check(_glow_energy("CoreGlow") == 0 and _glow_energy("PortGlow") == 0 and _glow_energy("StarboardGlow") == 0, "persistent defeated state leaves every energy cell dark")
	_check(_glow_energy("PortGlow", second) == other_energy and other_energy > 0, "defeated instance does not mutate another instance's emissive materials")
	var unchanged := true
	for entry in baseline_materials.values():
		var material := entry.mesh.get_active_material(entry.surface) as BaseMaterial3D
		unchanged = unchanged and material == entry.material and material.albedo_color == entry.albedo
		unchanged = unchanged and material.emission_enabled == entry.emission_enabled and material.emission == entry.emission
		unchanged = unchanged and material.emission_energy_multiplier == entry.energy and material.albedo_texture == entry.texture
		unchanged = unchanged and entry.mesh.material_override == null and entry.mesh.get_surface_override_material(entry.surface) == null
	_check(unchanged, "hull/armor imported PBR materials and textures remain untouched through every state")
	_check(_ray("core").is_empty() and _ray("port").is_empty() and _ray("starboard").is_empty(), "defeated pose is deterministically open for inspection")
	second.queue_free()

func _vec(value: Vector3) -> Array:
	return [value.x, value.y, value.z]

func _finish() -> void:
	paused = false
	print("V3_WHALE_ASSET_TESTS " + JSON.stringify({"checks":checks, "check_count":checks.size(), "failures":failures,
		"passed":failures.is_empty(), "locked_sha256":LOCKED_SHA256, "engine":Engine.get_version_info(),
		"limits":["Actual imported GLB, authored triangle collision and immediate state poses only.", "No main session, saved profile, ENet, rendering-performance or human visual acceptance."]}))
	if is_instance_valid(stage): stage.queue_free()
	quit(0 if failures.is_empty() else 1)
