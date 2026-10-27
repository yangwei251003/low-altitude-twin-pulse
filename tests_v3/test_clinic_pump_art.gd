extends SceneTree
## Real imported mesh / physics / camera-helper check; no screenshot or FPS claim.
const Works = preload("res://scripts/v3/world/twin_clinic_waterworks.gd")
const Art = preload("res://scripts/v3/art/twin_clinic_pump_art.gd")
const Flight = preload("res://scripts/v2/flight_body.gd")
const Catalog = preload("res://scripts/v2/catalog.gd")
const FlightCamera = preload("res://scripts/v2/flight_camera.gd")
const Visibility = preload("res://scripts/v3/art/twin_terrain_visibility.gd")
var stage: Node3D
var works: Node3D
var checks := 0
var failures: Array = []
var done := false
class ErrorLog extends Logger:
	var errors: Array = []
	func _log_error(fn: String,file: String,line: int,code: String,rationale: String,_notify: bool,kind: int,_traces: Array[ScriptBacktrace]) -> void:
		errors.append({"function":fn,"file":file,"line":line,"code":code,"rationale":rationale,"kind":kind})
var logger := ErrorLog.new()

func _init() -> void:
	OS.add_logger(logger)
	_run.call_deferred()

func _run() -> void:
	create_timer(90).timeout.connect(func():
		if not done:
			print("PUMP_ART_TIMEOUT "+JSON.stringify({"checks":checks,"failures":failures,"errors":logger.errors}))
			quit(2))
	stage=Node3D.new()
	root.add_child(stage)
	works=Works.new()
	var layout: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(Works.PATH))
	var configured: Dictionary = works.configure(layout)
	_check(configured.ok,"unchanged real clinic layout configures")
	if not configured.ok:
		works.free()
		await _finish()
		return
	var before: Dictionary = works.snapshot()
	var boxes := _boxes()
	var child_count: int = works.fixed_bodies.size()
	var installed: Dictionary = Art.install(works)
	_check(installed.ok,"actual GLB validates and installs: "+str(installed.get("code")))
	if not installed.ok:
		works.free()
		await _finish()
		return
	_check(works.snapshot()==before and _boxes()==boxes and works.fixed_bodies.size()==child_count,"presentation preserves authority state and every original collider/RID/transform")
	_check(installed.triangles==13600 and installed.mesh_count==6,"complete exported 13600 triangles in six independent visual groups")
	var hidden := true
	for id in Art.BOXES: hidden=hidden and not works.fixed_bodies[id].get_node("Visual").visible
	_check(hidden,"all seven original gray render boxes are hidden")
	var mesh_poses := true
	for mesh: MeshInstance3D in installed.model_meshes:
		mesh_poses=mesh_poses and _relative(mesh,works).is_equal_approx(Transform3D(Basis.IDENTITY,Art.ORIGIN))
	_check(mesh_poses,"all imported local vertices resolve at the real pump origin")
	stage.add_child(works)
	await _settle()
	for frame in ["tr01","hx02"]:
		var body := Flight.new()
		body.configure(Catalog.resolve_build(Catalog.default_build(frame)))
		body.freeze=true
		stage.add_child(body)
		body.set_process(false)
		body.set_physics_process(false)
		await _place(body,Vector3(-7,1.8,14.5))
		var clear := _body_clear(body)
		var hit: KinematicCollision3D
		for unused in range(50):
			hit=body.move_and_collide(Vector3(0,0,-.1),false,.001)
			if hit!=null: break
			await physics_frame
		_check(clear and hit==null and absf(body.global_position.z-9.5)<.001 and _body_clear(body),frame+" physically traverses preserved 3.4m opening")
		await _cutaway(body,installed,frame)
		body.queue_free()
		await _settle()
	var roof: Dictionary = stage.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(-7,4,9.5),Vector3(-7,2.8,9.5)))
	_check(roof.get("collider")==works.fixed_bodies.PumpRoof,"original solid roof remains the authoritative hit")
	_check(_boxes()==boxes and works.snapshot()==before,"flight and fade checks cannot mutate world simulation or collision")
	await _finish()

func _cutaway(body: PhysicsBody3D, art: Dictionary, frame: String) -> void:
	var camera := Camera3D.new()
	camera.projection=Camera3D.PROJECTION_ORTHOGONAL
	stage.add_child(camera)
	var rig = FlightCamera.new()
	rig.configure(camera)
	rig.target_size=26.0
	rig.snap(body.global_position)
	await _settle()
	var helper = Visibility.new()
	helper.setup(camera,body,art.occluders)
	var materials: Dictionary = {}
	for mesh: MeshInstance3D in art.model_meshes: materials[mesh.name]=mesh.get_active_material(0)
	for unused in range(6): helper.update(.1)
	var entry: Dictionary = helper._entries.get(works.fixed_bodies.PumpRoof.get_instance_id(),{})
	_check(helper.occluded and entry.get("installed",false) and float(entry.get("alpha",1.0))<.999,frame+" fixed camera selects original roof body and fades imported roof")
	for mesh: MeshInstance3D in art.model_meshes:
		if mesh.name in ["FloorSurface","WallFeetAndJambs"]:
			_check(mesh.get_active_material(0)==materials[mesh.name],frame+" permanent navigation surface keeps its original material: "+str(mesh.name))
	await _place(body,Vector3(22,9,22))
	rig.snap(body.global_position)
	await _settle()
	for unused in range(20): helper.update(.1)
	var restored: bool = not helper.occluded
	for mesh: MeshInstance3D in art.model_meshes: restored=restored and mesh.get_active_material(0)==materials[mesh.name]
	_check(restored,frame+" unobstructed view restores original imported materials")
	helper.clear()
	camera.queue_free()
	await _settle()

func _boxes() -> Dictionary:
	var rows := {}
	for id in works.fixed_bodies:
		var body: StaticBody3D = works.fixed_bodies[id]
		var collision: CollisionShape3D = body.get_node("ExactBoxCollision")
		rows[id]=[body.get_rid(),body.transform,body.collision_layer,body.collision_mask,collision.transform,collision.shape.get_rid(),collision.shape.size]
	return rows

func _body_clear(body: PhysicsBody3D) -> bool:
	for owner in body.get_shape_owners():
		if body.is_shape_owner_disabled(owner): continue
		for index in range(body.shape_owner_get_shape_count(owner)):
			var q := PhysicsShapeQueryParameters3D.new()
			q.shape=body.shape_owner_get_shape(owner,index)
			q.transform=body.global_transform*body.shape_owner_get_transform(owner)
			q.exclude=[body.get_rid()]
			if not stage.get_world_3d().direct_space_state.intersect_shape(q,1).is_empty(): return false
	return true

func _place(body: PhysicsBody3D, point: Vector3) -> void:
	body.global_transform=Transform3D(Basis.IDENTITY,point)
	body.force_update_transform()
	PhysicsServer3D.body_set_state(body.get_rid(),PhysicsServer3D.BODY_STATE_TRANSFORM,body.global_transform)
	await _settle()

func _settle() -> void:
	await physics_frame
	await physics_frame
	await process_frame

func _check(ok: bool, label: String) -> void:
	checks+=1
	if not ok: failures.append(label)

func _relative(node: Node3D, ancestor: Node3D) -> Transform3D:
	var transform := Transform3D.IDENTITY
	var current: Node = node
	while current!=ancestor:
		if current is Node3D: transform=current.transform*transform
		current=current.get_parent()
	return transform

func _finish() -> void:
	if done: return
	done=true
	if is_instance_valid(stage): stage.queue_free()
	await _settle()
	print("PUMP_ART_TESTS "+JSON.stringify({"checks":checks,"failures":failures,"errors":logger.errors,"scope":"real imported presentation and physics fixtures; no GPU, FPS or human acceptance"}))
	var success := failures.is_empty() and logger.errors.is_empty()
	OS.remove_logger(logger)
	quit(0 if success else 1)
