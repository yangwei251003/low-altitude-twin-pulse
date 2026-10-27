extends SceneTree

const Visibility = preload("res://scripts/v2/visibility_controller.gd")
const Body = preload("res://scripts/v2/flight_body.gd")
const Catalog = preload("res://scripts/v2/catalog.gd")
const PilotInput = preload("res://scripts/v2/pilot_input.gd")
const Streets = preload("res://scripts/v2/street_dressing.gd")

class ProxyWorld:
	extends Node3D
	var controller: Node
	func _register_occluder(proxy: Node3D) -> void: controller.register_occluder(proxy)

class CameraSession:
	extends "res://scripts/v2/session.gd"
	func _ready() -> void: pass
	func _process(_delta: float) -> void: pass
	func _physics_process(_delta: float) -> void: pass
	func _notification(_what: int) -> void: pass

var failures: Array[String] = []
var checks = 0

func _initialize() -> void:
	call_deferred("run")

func check(value: bool, description: String) -> void:
	checks += 1
	print("VISIBILITY_V2_", "PASS " if value else "FAIL ", description)
	if not value: failures.append(description)

func building(parent: Node3D, position: Vector3, material: Material) -> Node3D:
	var node = Node3D.new()
	parent.add_child(node)
	node.position = position
	var mesh = MeshInstance3D.new()
	mesh.name = "Wall"
	mesh.mesh = BoxMesh.new()
	mesh.mesh.size = Vector3(3, 5, 3)
	mesh.material_override = material
	node.add_child(mesh)
	var physics = StaticBody3D.new()
	physics.name = "SolidWall"
	physics.collision_layer = 1
	physics.collision_mask = 2
	var collider = CollisionShape3D.new()
	collider.shape = BoxShape3D.new()
	collider.shape.size = Vector3(3, 5, 3)
	physics.add_child(collider)
	node.add_child(physics)
	return node

func advance(controller: Node, seconds: float) -> void:
	for step in range(ceili(seconds * 60.0)): controller.update_visibility(1.0 / 60.0)

func run() -> void:
	var arena = Node3D.new()
	root.add_child(arena)
	var camera = Camera3D.new()
	arena.add_child(camera)
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.position = Vector3(32, 39, 32)
	camera.look_at(Vector3.ZERO)
	var subject = Node3D.new()
	arena.add_child(subject)
	# Off-centre subject catches the perspective-ray implementation error.
	subject.position = camera.basis.x * 8.0
	var shared = StandardMaterial3D.new()
	shared.albedo_color = Color("bda788")
	var toward_camera = camera.basis.z
	var near_building = building(arena, subject.position + toward_camera * 9.0, shared)
	var far_building = building(arena, subject.position + toward_camera * 19.0, shared)
	var clear_building = building(arena, subject.position - toward_camera * 12.0, shared)
	var controller = Visibility.new()
	arena.add_child(controller)
	controller.configure(camera, subject)
	for node in [near_building, far_building, clear_building]: controller.register_occluder(node)
	controller.register_occluder(near_building)
	check(controller.entries.size() == 3, "stream registration is idempotent")
	advance(controller, 0.4)
	check(controller.entries[near_building.get_instance_id()].alpha < 0.21, "first foreground building fades at off-centre subject")
	check(controller.entries[far_building.get_instance_id()].alpha < 0.21, "second foreground building fades simultaneously")
	check(is_equal_approx(controller.entries[clear_building.get_instance_id()].alpha, 1.0), "building behind the drone stays opaque")
	var near_mesh: MeshInstance3D = near_building.get_node("Wall")
	var far_mesh: MeshInstance3D = far_building.get_node("Wall")
	check(near_mesh.get_active_material(0) != shared and near_mesh.get_active_material(0) != far_mesh.get_active_material(0), "faded surfaces have independent material resources")
	check(shared.albedo_color.a == 1.0 and shared.transparency == BaseMaterial3D.TRANSPARENCY_DISABLED, "shared source material remains unchanged")
	check(near_mesh.get_active_material(0).transparency == BaseMaterial3D.TRANSPARENCY_ALPHA and near_mesh.transparency == 0.0, "Compatibility uses alpha materials, never unsupported geometry transparency")
	var collider: StaticBody3D = near_building.get_node("SolidWall")
	check(collider.collision_layer == 1 and collider.collision_mask == 2 and not collider.get_child(0).disabled, "faded building keeps its physical collision")
	var new_building = building(arena, subject.position + toward_camera * 29.0, shared)
	controller.register_occluder(new_building)
	advance(controller, 0.4)
	check(controller.entries[new_building.get_instance_id()].alpha < 0.21, "new streamed building joins visibility fading")
	subject.position += camera.basis.x * 20.0
	advance(controller, 0.1)
	check(controller.entries[near_building.get_instance_id()].alpha < 0.4, "brief exit uses release hysteresis instead of flashing")
	advance(controller, 0.7)
	check(near_mesh.material_override == shared and near_mesh.get_surface_override_material(0) == null, "leaving obstruction restores exact authored material bindings")
	check(not controller.occluded, "visibility state recovers after leaving all buildings")
	new_building.free()
	advance(controller, 0.1)
	check(controller.entries.size() == 3, "unloaded streamed roots are pruned safely")
	test_batched_tree(arena, controller, camera, subject, shared)
	await test_camera(arena)
	arena.queue_free()
	await process_frame
	print("VISIBILITY_V2_SUMMARY ", JSON.stringify({"checks":checks, "failures":failures, "ok":failures.is_empty(), "scope":"Headless visibility math, material isolation, fixed camera direction, screen-relative input and collision preservation only. Actual GL appearance and human comfort require GUI review."}))
	quit(0 if failures.is_empty() else 1)

func test_batched_tree(arena: Node3D, controller: Node, camera: Camera3D, subject: Node3D, material: Material) -> void:
	var fixture = ProxyWorld.new()
	fixture.controller = controller
	arena.add_child(fixture)
	var chunk = Node3D.new()
	arena.add_child(chunk)
	var dressing = Node3D.new()
	chunk.add_child(dressing)
	var tree = Node3D.new()
	dressing.add_child(tree)
	tree.position = subject.position + camera.basis.z * 10.0
	tree.rotation.y = 0.35
	tree.scale = Vector3.ONE * 0.9
	var mesh = MeshInstance3D.new()
	mesh.mesh = BoxMesh.new()
	mesh.mesh.size = Vector3(3,5,3)
	mesh.material_override = material
	tree.add_child(mesh)
	var physics = StaticBody3D.new()
	dressing.add_child(physics)
	physics.collision_layer = 1
	var shape = CollisionShape3D.new()
	shape.shape = BoxShape3D.new()
	physics.add_child(shape)
	var collider_rid = physics.get_rid()
	var proxy = Streets.register_tree_outline(dressing,tree,fixture)
	controller.register_occluder(proxy)
	check(controller.outline_entries.size() == 1 and controller.entries.size() == 3, "tree proxy is idempotent and separate from material-fade entries")
	var bounds: AABB = proxy.get_meta("v2_outline_only_bounds")
	check(bounds.size.is_equal_approx(Vector3(3,5,3)), "outline envelope is the individual tree, never a street or ground-cell envelope")
	Streets.batch(dressing)
	var batch_instance: MultiMeshInstance3D
	for child in dressing.get_children():
		if child is MultiMeshInstance3D: batch_instance = child; break
	check(is_instance_valid(batch_instance) and not is_instance_valid(mesh), "tree visual stays GPU-instanced after its source mesh is released")
	check(is_instance_valid(proxy) and proxy.get_parent() == chunk, "lightweight outline proxy survives sibling street batching")
	advance(controller,0.3)
	check(controller.occluded and controller.outline_entries[proxy.get_instance_id()].blocked, "batched tree envelope requests drone silhouette when it blocks the view")
	check(batch_instance.material_override == material and material.albedo_color.a == 1.0, "outline-only tree detection never fades a shared MultiMesh material")
	check(is_instance_valid(physics) and physics.get_rid() == collider_rid and physics.collision_layer == 1, "batch and silhouette detection preserve tree collision")
	subject.position += camera.basis.x * 20.0
	advance(controller,0.4)
	check(not controller.occluded, "tree-only silhouette clears after leaving its envelope")
	chunk.free()
	advance(controller,0.1)
	check(controller.outline_entries.is_empty(), "streamed chunk retirement removes its outline proxies safely")
	fixture.free()

func test_camera(parent: Node3D) -> void:
	var game = CameraSession.new()
	parent.add_child(game)
	game.camera = Camera3D.new()
	game.camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	game.add_child(game.camera)
	game.pilot = Body.new()
	game.pilot.configure(Catalog.resolve_build(Catalog.default_build()))
	game.pilot.freeze = true
	game.add_child(game.pilot)
	game.pilot.position = Vector3(50, 2, 70)
	game._snap_camera()
	var original_basis = game.camera.global_basis
	game.pilot.linear_velocity = Vector3(11, 0, -8)
	for index in range(90):
		game.pilot.position += Vector3(0.1, 0.01, -0.08)
		game._update_flight_camera(1.0 / 60.0)
	check(game.camera.global_basis.is_equal_approx(original_basis), "camera azimuth and pitch stay fixed while tracking and leading")
	check(game.camera.projection == Camera3D.PROJECTION_ORTHOGONAL and game.camera_lead.length() <= 1.401, "camera remains orthographic with bounded forward view")
	var input = PilotInput.new()
	parent.add_child(input)
	input.active = true
	input.test_enabled = true
	input.test_frame = {"axes":{"right_x":1.0,"right_y":0.0}}
	var right_command = input.command(game.camera.global_basis).planar
	input.test_frame = {"axes":{"right_x":0.0,"right_y":1.0}}
	var up_command = input.command(game.camera.global_basis).planar
	check(right_command.dot(game.camera.global_basis.x) > 0.999 and absf(right_command.dot(game.camera.global_basis.y)) < 0.001, "right input moves horizontally right on screen")
	check(up_command.dot(game.camera.global_basis.y) > 0.5 and absf(up_command.dot(game.camera.global_basis.x)) < 0.001, "forward input moves vertically up on screen")
	var original_layer=game.pilot.collision_layer
	var original_mask=game.pilot.collision_mask
	game.pilot.set_occlusion_hint(true, 0.5)
	await process_frame
	check(game.pilot.visibility_silhouette.visible and game.pilot.silhouette_material.no_depth_test and game.pilot.silhouette_parts.size() > 0, "occluded drone gets an actual mesh silhouette that ignores depth")
	check(game.pilot.collision_layer == original_layer and game.pilot.collision_mask == original_mask and (original_mask & 32)!=0, "silhouette preserves terrain, cargo and moving-platform collision")
	game.pilot.set_occlusion_hint(false, 0.5)
	check(not game.pilot.visibility_silhouette.visible, "silhouette disappears when normal visibility returns")
