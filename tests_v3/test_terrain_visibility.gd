extends SceneTree
## Synthetic real PhysicsServer geometry; no main scene, profile, network or GPU.
const Visibility = preload("res://scripts/v3/art/twin_terrain_visibility.gd")
var stage: Node3D
var camera: Camera3D
var pilot: Node3D
var helper = Visibility.new()
var checks: Array[Dictionary] = []
var failures: Array[String] = []

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	stage = Node3D.new()
	root.add_child(stage)
	camera = Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 18.0
	stage.add_child(camera)
	camera.position = Vector3(0, 0, 10)
	pilot = Node3D.new()
	pilot.name = "LocalPilot"
	stage.add_child(pilot)
	var envelope := CollisionShape3D.new()
	envelope.name = "Envelope"
	var pilot_shape := BoxShape3D.new()
	pilot_shape.size = Vector3(1.0, 0.5, 1.0)
	envelope.shape = pilot_shape
	pilot.add_child(envelope)
	var shared := StandardMaterial3D.new()
	shared.albedo_color = Color(0.6, 0.4, 0.2, 0.8)
	var rock := _rock("Rock", Vector3(0, 0, 5), Vector3(2, 2, 1), shared)
	var other := _rock("OffAxis", Vector3(5, 0, 5), Vector3(2, 2, 1), shared)
	await _settle()
	helper.setup(camera, pilot, [rock, other])
	_check(helper.update(0.1), "actual intersecting terrain begins fade")
	var faded: Material = rock.get_node("Surface").get_active_material(0)
	_check(faded != shared and faded.albedo_color.a < shared.albedo_color.a, "only per-instance material copy loses alpha")
	_check(other.get_node("Surface").get_active_material(0) == shared and is_equal_approx(shared.albedo_color.a, 0.8), "off-axis instance and shared source material remain exact")
	_check(_ray(Vector3(0, 0, 9), Vector3.ZERO).get("collider") == rock.get_node("Surface/Body"), "faded rock still physically blocks the same ray")
	_check(rock.get_node("Surface/Body").collision_layer == 1 and rock.get_node("Surface/Body/Shape").shape.size == Vector3(2, 2, 1), "layers and physical shape are untouched")
	for i in 4: helper.update(0.01)
	_check(rock.get_node("Surface").get_active_material(0) == faded, "frame transitions reuse the same cloned material")
	rock.position.x = 5
	await _settle()
	helper.update(0.1)
	_check(rock.get_node("Surface").get_active_material(0) != shared, "short release hold prevents one-frame flicker")
	for i in 12: helper.update(0.05)
	_check(rock.get_node("Surface").get_active_material(0) == shared and rock.get_node("Surface").get_surface_override_material(0) == null, "clear view restores original surface binding")
	helper.clear()
	rock.queue_free()
	other.queue_free()
	await _settle()

	# A root's aggregate AABB covers the pilot, but its true aperture does not.
	var arch := Node3D.new()
	stage.add_child(arch)
	var left := _rock("Left", Vector3(-1.2, 0, 5), Vector3(0.3, 2, 1), shared, arch)
	var right := _rock("Right", Vector3(1.2, 0, 5), Vector3(0.3, 2, 1), shared, arch)
	await _settle()
	helper.setup(camera, pilot, [arch])
	_check(not helper.update(0.1), "real aperture does not fade merely because root bounds overlap")
	_check(left.get_node("Surface").get_active_material(0) == shared and right.get_node("Surface").get_active_material(0) == shared, "both aperture banks retain their materials")
	helper.clear()
	arch.queue_free()
	await _settle()

	var front := _rock("Front", Vector3(0, 0, 7), Vector3(2, 2, 0.5), shared)
	var rear := _rock("Rear", Vector3(0, 0, 4), Vector3(2, 2, 0.5), shared)
	var knot := _rock("SapKnot", Vector3(0, 0, 2), Vector3(1, 1, 0.4), shared, rear)
	knot.get_node("Surface/Body").set_meta("entity_id", "F1:crown_host_west")
	var override_mat := StandardMaterial3D.new()
	var surface_mat := StandardMaterial3D.new()
	var front_mesh: MeshInstance3D = front.get_node("Surface")
	front_mesh.material_override = override_mat
	front_mesh.set_surface_override_material(0, surface_mat)
	await _settle()
	helper.setup(camera, pilot, [front, rear, rear.get_node("Surface"), front])
	helper.update(0.1)
	_check(front_mesh.get_active_material(0) != override_mat and rear.get_node("Surface").get_active_material(0) != shared, "all actual layered terrain blockers fade")
	_check(knot.get_node("Surface").get_active_material(0) == shared, "SapKnot target and glow material are entirely excluded")
	_check(helper._entries.size() == 2, "duplicate and nested candidates have a single material owner")
	helper.clear()
	_check(front_mesh.material_override == override_mat and front_mesh.get_surface_override_material(0) == surface_mat, "clear restores both whole override and hidden surface override exactly")
	helper.clear()
	_check(not helper.occluded and front_mesh.material_override == override_mat, "clear is idempotent")
	helper.setup(camera, pilot, [rear.get_node("Surface"), rear])
	helper.update(0.1)
	_check(helper._entries.size() == 1, "parent supplied after child replaces nested ownership safely")
	helper.setup(camera, pilot, [])
	_check(rear.get_node("Surface").get_active_material(0) == shared, "new setup restores the previous candidate set")
	front.queue_free()
	rear.queue_free()
	await _settle()

	# Protected objects are deliberately supplied to catch an unsafe caller.
	var boss := _rock("ParasiticCrown", Vector3(0, 0, 6), Vector3(2, 2, 1), shared)
	boss.set_meta("entity_id", "boss:crown_armor")
	var warning := _rock("Warning", Vector3(0, 0, 4), Vector3(2, 2, 1), shared)
	warning.set_meta("terrain_visibility_keep", true)
	var player_surface := MeshInstance3D.new()
	player_surface.mesh = BoxMesh.new()
	player_surface.material_override = shared
	pilot.add_child(player_surface)
	await _settle()
	helper.setup(camera, pilot, [boss, warning, pilot])
	_check(not helper.update(0.1) and boss.get_node("Surface").get_active_material(0) == shared and warning.get_node("Surface").get_active_material(0) == shared and player_surface.material_override == shared, "boss, warning and local player never fade")
	helper.clear()
	boss.queue_free()
	warning.queue_free()
	await _settle()

	var shader := Shader.new()
	shader.code = "shader_type spatial; void fragment(){ ALBEDO=vec3(0.3); }"
	var custom := ShaderMaterial.new()
	custom.shader = shader
	var shader_rock := _rock("CustomShader", Vector3(0, 0, 5), Vector3(2, 2, 1), custom)
	await _settle()
	helper.setup(camera, pilot, [shader_rock])
	_check(not helper.update(0.1) and shader_rock.get_node("Surface").get_active_material(0) == custom, "unknown shader semantics are not replaced or corrupted")
	helper.clear()
	shader_rock.queue_free()
	await _settle()

	# Orthographic rays are parallel, rather than converging at camera origin.
	pilot.position.x = 4
	var lateral := _rock("ParallelOnly", Vector3(4, 0, 5), Vector3(0.8, 2, 1), shared)
	await _settle()
	helper.setup(camera, pilot, [lateral])
	_check(helper.update(0.1), "orthographic off-center pilot selects its actual screen occluder")
	pilot.queue_free()
	_check(not helper.update(0.1) and lateral.get_node("Surface").get_active_material(0) == shared, "queued local target safely clears and restores terrain")
	await _settle()
	helper.clear()
	stage.queue_free()
	await process_frame
	print(JSON.stringify({"suite":"terrain_visibility", "checks":checks.size(), "failed":failures.size(), "failures":failures, "scope":"headless actual PhysicsServer; visual/GPU acceptance separate"}))
	quit(0 if failures.is_empty() else 1)

func _rock(label: String, at: Vector3, size: Vector3, material: Material, parent: Node3D = null) -> Node3D:
	var result := Node3D.new()
	result.name = label
	(parent if parent != null else stage).add_child(result)
	result.position = at
	var mesh := MeshInstance3D.new()
	mesh.name = "Surface"
	var box := BoxMesh.new()
	box.size = size
	box.material = material
	mesh.mesh = box
	result.add_child(mesh)
	var body := StaticBody3D.new()
	body.name = "Body"
	body.collision_layer = 1
	body.collision_mask = 0
	mesh.add_child(body)
	var shape := CollisionShape3D.new()
	shape.name = "Shape"
	var box_shape := BoxShape3D.new()
	box_shape.size = size
	shape.shape = box_shape
	body.add_child(shape)
	return result

func _ray(from: Vector3, to: Vector3) -> Dictionary:
	return stage.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(from, to, 1 | 8))

func _settle() -> void:
	await physics_frame
	await process_frame
	await physics_frame
	await process_frame

func _check(condition: bool, label: String) -> void:
	checks.append({"name":label, "passed":condition})
	if not condition:
		failures.append(label)
		push_error(label)
