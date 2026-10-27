extends SceneTree
## Real passage/fader, production FlightBody envelopes and fixed Camera controller.
## Scripted poses, not a Session route, GPU readability or human-play acceptance.
const Passage = preload("res://scripts/v3/world/twin_underdeck_passage.gd")
const Visibility = preload("res://scripts/v3/art/twin_terrain_visibility.gd")
const FlightBody = preload("res://scripts/v2/flight_body.gd")
const FlightCamera = preload("res://scripts/v2/flight_camera.gd")
const Catalog = preload("res://scripts/v2/catalog.gd")
var stage: Node3D
var passage: Node3D
var camera: Camera3D
var camera_control = FlightCamera.new()
var helper = Visibility.new()
var checks := 0
var failures: Array = []
var done := false

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	create_timer(40).timeout.connect(func():
		if not done: quit(2))
	stage = Node3D.new()
	root.add_child(stage)
	passage = Passage.new()
	var loaded: Dictionary = passage.load_layout()
	_check(loaded.ok,"actual passage configures",loaded)
	if not loaded.ok:
		passage.free()
		await _finish()
		return
	stage.add_child(passage)
	camera = Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	stage.add_child(camera)
	camera_control.configure(camera)
	camera_control.target_size = 26.0
	var cover: MeshInstance3D = passage.shell.get_node("OccludingCover/Surface")
	var original_cover := _materials(cover)
	var detail_rows: Array = []
	for part in ["CoverDetails", "RoofSupports"]:
		var mesh: MeshInstance3D = passage.shell.get_node("OccludingCover/" + part)
		detail_rows.append({"mesh":mesh,"materials":_materials(mesh)})
	var protected_rows: Array = []
	for branch in [passage.shell.get_node("PermanentNavigation"),passage.get_node("GrayboxMaintenanceMarkings"),passage.gates.front,passage.gates.rear,passage.get_node("InnerLatch")]:
		for mesh in branch.find_children("*","MeshInstance3D",true,false): protected_rows.append({"mesh":mesh,"materials":_materials(mesh)})
	var collision: CollisionShape3D = passage.shell.get_node("ExactSurfaceCollision")
	var shape_id: int = collision.shape.get_instance_id()
	var faces: PackedVector3Array = collision.shape.get_faces()
	var state: Dictionary = passage.snapshot()
	var front_pose: Transform3D = passage.gates.front.transform
	var rear_pose: Transform3D = passage.gates.rear.transform
	_test_navigation_surfaces()
	for frame in ["tr01","hx02"]:
		var pilot := FlightBody.new()
		pilot.configure(Catalog.resolve_build(Catalog.default_build(frame)))
		pilot.freeze = true
		pilot.position = Vector3(-35,2.05,-16.7)
		stage.add_child(pilot)
		pilot.set_process(false)
		pilot.set_physics_process(false)
		await _settle()
		for row in [
			["south approach",Vector3(-35,2.05,-16.7),false],
			["south inside",Vector3(-35,2.05,-20),true],
			["east window outside",Vector3(-25,3.55,-23.5),false],
			["east window inside",Vector3(-29,3.55,-23.5),true],
			["inner latch corridor",Vector3(-35,2.05,-25),true],
			["north inside",Vector3(-35,2.05,-33.5),true],
			["north outside still behind shell",Vector3(-35,2.05,-37.2),true]]:
			helper.clear()
			pilot.global_transform = Transform3D(Basis.IDENTITY,row[1])
			PhysicsServer3D.body_set_state(pilot.get_rid(),PhysicsServer3D.BODY_STATE_TRANSFORM,pilot.global_transform)
			camera_control.snap(pilot.global_position)
			await _settle()
			helper.setup(camera,pilot,[passage.shell])
			for i in range(4): helper.update(0.1)
			var expected: bool = row[2]
			_check(helper.occluded==expected,frame+" fixed-camera actual ray detection: "+str(row[0]),{"expected":expected,"occluded":helper.occluded})
			var cover_correct := true
			for surface in range(cover.mesh.get_surface_count()):
				var material: BaseMaterial3D = cover.get_active_material(surface)
				cover_correct = cover_correct and (material!=original_cover[surface] and is_equal_approx(material.albedo_color.a,Visibility.FADED_ALPHA) if expected else material==original_cover[surface])
				if expected: cover_correct = cover_correct and material.cull_mode == BaseMaterial3D.CULL_BACK
			_check(cover_correct,frame+" only cover has expected cloned alpha: "+str(row[0]))
			var details_correct := true
			for saved in detail_rows:
				var materials := _materials(saved.mesh)
				for index in range(materials.size()):
					details_correct = details_correct and (materials[index]!=saved.materials[index] and is_zero_approx(materials[index].albedo_color.a) if expected else materials[index]==saved.materials[index])
			_check(details_correct,frame+" dense closed details fully withdraw only while blocked: "+str(row[0]))
			var preserved := true
			for saved in protected_rows:
				preserved = preserved and _materials(saved.mesh)==saved.materials
				for material in saved.materials: preserved = preserved and is_equal_approx(material.albedo_color.a,1.0)
			_check(preserved,frame+" floors/landings/wall feet/gates/lock/markings keep original opaque materials: "+str(row[0]))
			_check(collision.shape.get_instance_id()==shape_id and collision.shape.get_faces()==faces and passage.shell.collision_layer==1 and passage.shell.collision_mask==0 and passage.snapshot()==state and passage.gates.front.transform==front_pose and passage.gates.rear.transform==rear_pose,frame+" fade leaves exact collision/state/gate poses untouched: "+str(row[0]))
			var closed_hit := _ray(Vector3(-35,2.05,-16.7),Vector3(-35,2.05,-20))
			_check(closed_hit.get("collider")==passage.gates.front,frame+" opaque closed grille remains real blocker: "+str(row[0]))
		# Restore through the normal release/hold path, not merely helper.clear().
		pilot.global_position = Vector3(-23,6,-15)
		PhysicsServer3D.body_set_state(pilot.get_rid(),PhysicsServer3D.BODY_STATE_TRANSFORM,pilot.global_transform)
		camera_control.snap(pilot.global_position)
		await _settle()
		for i in range(20): helper.update(0.1)
		_check(not helper.occluded and _materials(cover)==original_cover,frame+" clear view restores cover bindings after release hold")
		for saved in detail_rows: _check(_materials(saved.mesh)==saved.materials,frame+" clear view restores exact authored detail bindings: "+str(saved.mesh.name))
		helper.clear()
		pilot.queue_free()
		await _settle()
	await _finish()

func _test_navigation_surfaces() -> void:
	var navigation: MeshInstance3D = passage.shell.get_node("PermanentNavigation/Surface")
	var cover: MeshInstance3D = passage.shell.get_node("OccludingCover/Surface")
	for row in [
		["main floor",Vector3(-35,0.7,-30),Vector3(-35,0.2,-30)],
		["raised side landing",Vector3(-28,2.5,-23.5),Vector3(-28,2.1,-23.5)],
		["turning floor",Vector3(-32,0.7,-23.5),Vector3(-32,0.2,-23.5)],
		["main low wall",Vector3(-35,0.6,-30),Vector3(-37,0.6,-30)],
		["side low wall",Vector3(-28,2.45,-24.8),Vector3(-28,2.45,-25.3)],
		["raised landing riser",Vector3(-30.8,1.7,-23.5),Vector3(-30.2,1.7,-23.5)]]:
		_check(_mesh_hit(navigation,row[1],row[2]) and not _mesh_hit(cover,row[1],row[2]),"navigation owns real surface: "+str(row[0]))
	for row in [
		["main ceiling",Vector3(-35,3.4,-30),Vector3(-35,3.9,-30)],
		["side ceiling",Vector3(-28,4.6,-23.5),Vector3(-28,5,-23.5)],
		["upper corridor wall",Vector3(-35,2,-30),Vector3(-37,2,-30)],
		["north upper header",Vector3(-35,4,-36),Vector3(-35,4,-35)]]:
		_check(_mesh_hit(cover,row[1],row[2]) and not _mesh_hit(navigation,row[1],row[2]),"fade cover owns actual blocker: "+str(row[0]))

func _mesh_hit(mesh: MeshInstance3D, from: Vector3, to: Vector3) -> bool:
	var local_from := mesh.to_local(from)
	var local_to := mesh.to_local(to)
	var vertices: PackedVector3Array = mesh.mesh.get_faces()
	for i in range(0,vertices.size(),3):
		if Geometry3D.segment_intersects_triangle(local_from,local_to,vertices[i],vertices[i+1],vertices[i+2])!=null: return true
	return false

func _materials(mesh: MeshInstance3D) -> Array:
	var result: Array = []
	for surface in range(mesh.mesh.get_surface_count()): result.append(mesh.get_active_material(surface))
	return result

func _ray(from: Vector3, to: Vector3) -> Dictionary:
	var query := PhysicsRayQueryParameters3D.create(from,to,1|8)
	query.hit_back_faces = true
	return stage.get_world_3d().direct_space_state.intersect_ray(query)

func _settle() -> void:
	await physics_frame
	await physics_frame
	await process_frame

func _check(ok: bool, label: String, details: Dictionary = {}) -> void:
	checks += 1
	if not ok:
		failures.append({"check":label,"details":details})
		push_error("UNDERDECK_VISIBILITY "+label+" "+JSON.stringify(details))

func _finish() -> void:
	helper.clear()
	if is_instance_valid(stage): stage.queue_free()
	await process_frame
	done = true
	print("UNDERDECK_VISIBILITY_RESULT "+JSON.stringify({"checks":checks,"failures":failures,"scope":"actual PhysicsServer/fader/FlightBody/fixed camera scripted fixtures; no GPU, human-play, Session, LAN or performance claim"}))
	quit(0 if failures.is_empty() else 1)
