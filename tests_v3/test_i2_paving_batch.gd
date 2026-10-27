extends SceneTree
## Candidate, after the supplied production patch is integrated. Real imported
## geometry + native collision; direct Works fixture, not MAIN/flight/FPS proof.
const Works = preload("res://scripts/v3/world/twin_clinic_waterworks.gd")
const Ground = preload("res://scripts/v3/art/twin_clinic_ground_art.gd")
const Batch = preload("res://scripts/v3/art/twin_i2_paving_batch.gd")
const Catalog = preload("res://scripts/v2/catalog.gd")
var stage: Node3D
var works: Node3D
var checks: Array = []
var output := ""
var finished := false
class Errors extends Logger:
	var entries: Array = []
	func _log_error(function: String,file: String,line: int,code: String,rationale: String,_notify: bool,kind: int,_traces: Array[ScriptBacktrace]) -> void:
		if kind!=Logger.ERROR_TYPE_WARNING: entries.append({"function":function,"file":file,"line":line,"code":code,"rationale":rationale})
var logger := Errors.new()

func _initialize() -> void:
	OS.add_logger(logger)
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--output="): output=arg.trim_prefix("--output=")
	_run.call_deferred()

func _check(okay: bool, name: String, actual: Variant = null) -> bool:
	checks.append({"passed":okay,"name":name,"actual":actual})
	return okay

func _run() -> void:
	if not output.begins_with("res://artifacts/v3/i2-paving-batch-") or ".." in output or FileAccess.file_exists(output):
		quit(2); return
	create_timer(12.0).timeout.connect(func() -> void:
		if not finished:
			_check(false,"bounded native paving check timeout")
			_finish())
	works=Works.new()
	var configured: Dictionary = works.configure(JSON.parse_string(FileAccess.get_file_as_string(Works.PATH)),{},false)
	if not _check(configured.get("ok",false),"original bare Works configures",configured):
		await _finish(); return
	# Explicit test-only false builds the actual validated original 28 leaves;
	# normal MAIN continues to use the default true install path.
	var art: Dictionary = Ground.install(works,false)
	if not _check(art.get("ok",false),"actual original import contracts pass before candidate",art.get("code")):
		await _finish(); return
	works.ground_art=art
	var source_nodes: Array = []
	for tile: Dictionary in art.tiles: source_nodes.append_array(tile.model.find_children("*","MeshInstance3D",true,false))
	for tile: Dictionary in art.maintenance.tiles: source_nodes.append_array(tile.model.find_children("*","MeshInstance3D",true,false))
	var source_ids: Array = []
	var source_resources: Array = []
	var source_faces := 0
	var source_bounds := AABB()
	var first := true
	for mesh: MeshInstance3D in source_nodes:
		source_ids.append(mesh.get_instance_id())
		var pose: Transform3D = Batch.relative(mesh,works)
		var faces: PackedVector3Array = mesh.mesh.get_faces()
		source_faces+=faces.size()
		for vertex: Vector3 in faces:
			var point: Vector3 = pose*vertex
			source_bounds=AABB(point,Vector3.ZERO) if first else source_bounds.expand(point)
			first=false
		source_resources.append({"mesh":mesh.mesh,"arrays":var_to_bytes(mesh.mesh.surface_get_arrays(0)),"material":mesh.get_active_material(0),"pose":pose})
	_check(source_nodes.size()==28 and source_faces==22496*3,"real originals are exactly28 leaves/22496 triangles",{"meshes":source_nodes.size(),"triangles":source_faces/3})
	stage=Node3D.new()
	root.add_child(stage)
	stage.add_child(works)
	await physics_frame
	await physics_frame
	await process_frame
	var physical: Dictionary = _physics()
	var untouched: Dictionary = _other_visuals(source_ids)
	var queries: Array = _aircraft_queries()
	var mechanism: Dictionary = works.snapshot()
	var original_roots: Array = []
	for tile: Dictionary in art.tiles+art.maintenance.tiles: original_roots.append({"model":tile.model,"id":tile.model.get_instance_id(),"name":tile.model.name,"pose":tile.model.transform})
	var batch: Dictionary = Batch.install(art)
	if not _check(batch.get("ok",false),"atomic candidate visual install",batch.get("code")):
		await _finish(); return
	_check(batch.runtime_meshes.size()<28,"actual compatible render leaves decrease; unsupported leaves are reported rather than forced",batch.report)
	await physics_frame
	await physics_frame
	await process_frame
	_check(_physics()==physical and works.snapshot()==mechanism,"every native body/shape RID, exact shape data, pose, space/filter, joints and mechanism remain identical")
	_check(_other_visuals([])==untouched,"all noncandidate Ground/remaining-patch/backing/door/water visuals are identical")
	_check(_aircraft_queries()==queries,"same real tr01 envelope sweep and full-envelope nine-ray results",queries)
	var roots_match := true
	for row: Dictionary in original_roots:
		roots_match=roots_match and is_instance_valid(row.model) and row.model.get_instance_id()==row.id and row.model.name==row.name and row.model.transform==row.pose
	_check(roots_match,"original tile/variant roots, names and transforms are retained")
	var source_intact := true
	for row: Dictionary in source_resources: source_intact=source_intact and var_to_bytes(row.mesh.surface_get_arrays(0))==row.arrays
	_check(source_intact,"all source ArrayMesh resources remain byte-identical")
	var runtime_triangles := 0
	var runtime_bounds := AABB()
	first=true
	for mesh: MeshInstance3D in batch.runtime_meshes:
		var pose: Transform3D = Batch.relative(mesh,works)
		for vertex: Vector3 in mesh.mesh.get_faces():
			var point: Vector3 = pose*vertex
			runtime_bounds=AABB(point,Vector3.ZERO) if first else runtime_bounds.expand(point)
			first=false
		runtime_triangles+=int(mesh.mesh.get_faces().size()/3)
	_check(runtime_triangles==22496 and runtime_bounds.position.distance_to(source_bounds.position)<.00005 and runtime_bounds.end.distance_to(source_bounds.end)<.00005,"independent world-space triangle count and geometric bounds remain equal",{"source_bounds":str(source_bounds),"runtime_bounds":str(runtime_bounds),"triangles":runtime_triangles})
	for scope: String in ["court","maintenance"]:
		var proof: Dictionary = Batch.proof(batch,scope)
		_check(proof.ok and proof.source_meshes==(16 if scope=="court" else 12) and proof.source_triangles==(8216 if scope=="court" else 14280),scope+" every original corner/material identity/normal/tangent/UV/color is present once",proof)
	var current_ids: Array = []
	for mesh: MeshInstance3D in works.find_children("*","MeshInstance3D",true,false): current_ids.append(mesh.get_instance_id())
	var removed := 0
	for id: int in source_ids:
		if not current_ids.has(id): removed+=1
	_check(removed==int(batch.report.merged_source_meshes),"merged leaves are freed, never hidden original duplicates",{"removed":removed,"recorded":batch.report.merged_source_meshes})
	await _finish()

func _physics() -> Dictionary:
	var result: Dictionary = {}
	for body: CollisionObject3D in works.find_children("*","CollisionObject3D",true,false):
		var rid: RID = body.get_rid()
		var shapes: Array = []
		for index: int in PhysicsServer3D.body_get_shape_count(rid):
			var shape: RID = PhysicsServer3D.body_get_shape(rid,index)
			shapes.append({"rid":shape,"type":PhysicsServer3D.shape_get_type(shape),"data":var_to_bytes(PhysicsServer3D.shape_get_data(shape)),"pose":PhysicsServer3D.body_get_shape_transform(rid,index)})
		var shape_nodes: Array = []
		for shape_node: CollisionShape3D in body.find_children("*","CollisionShape3D",true,false): shape_nodes.append({"id":shape_node.get_instance_id(),"rid":shape_node.shape.get_rid(),"pose":shape_node.transform,"disabled":shape_node.disabled})
		result[str(body.get_instance_id())]={"rid":rid,"node_pose":body.global_transform,"native_pose":PhysicsServer3D.body_get_state(rid,PhysicsServer3D.BODY_STATE_TRANSFORM),"space":PhysicsServer3D.body_get_space(rid),"layer":PhysicsServer3D.body_get_collision_layer(rid),"mask":PhysicsServer3D.body_get_collision_mask(rid),"shapes":shapes,"shape_nodes":shape_nodes}
	for joint: Joint3D in works.find_children("*","Joint3D",true,false): result["joint/"+str(joint.get_instance_id())]={"pose":joint.transform,"a":joint.node_a,"b":joint.node_b}
	return result

func _other_visuals(exclude: Array) -> Dictionary:
	var result: Dictionary = {}
	for mesh: MeshInstance3D in works.find_children("*","MeshInstance3D",true,false):
		if exclude.has(mesh.get_instance_id()) or str(mesh.name).begins_with("PavingBatch_"): continue
		# Retained unsupported source leaves are still candidates, not outsiders.
		var cursor: Node = mesh
		var candidate := false
		while cursor!=works:
			if cursor.name=="MaintenanceAuthoredPaving" or str(cursor.name) in ["DrainEdge","ServiceWest","ServiceEast","ArrivalWest","ArrivalMiddle","ArrivalEast","ReceivingApproachWest","ReceivingApproachEast"]: candidate=true
			cursor=cursor.get_parent()
		if candidate: continue
		result[str(mesh.get_instance_id())]={"mesh_rid":mesh.mesh.get_rid(),"pose":mesh.global_transform,"material":mesh.get_active_material(0),"visible":mesh.visible}
	return result

func _aircraft_queries() -> Array:
	var resolved: Dictionary = Catalog.resolve_build(Catalog.default_build("tr01"))
	var size := Vector3(float(resolved.derived.width_m),float(resolved.derived.height_m),float(resolved.derived.length_m))
	var hull := BoxShape3D.new()
	hull.size=size
	var result: Array = []
	var space: PhysicsDirectSpaceState3D = works.get_world_3d().direct_space_state
	for at: Vector3 in [Vector3(-19,2,15),Vector3(-13,2,21),Vector3(5,2,15),Vector3(17,2,-12),Vector3(22,2,0)]:
		var query := PhysicsShapeQueryParameters3D.new()
		query.shape=hull
		query.transform=Transform3D(Basis.IDENTITY,at)
		query.motion=Vector3(0,-3,0)
		query.collision_mask=1|4|8|32
		var rays: Array = []
		for x: float in [-size.x*.5,0.0,size.x*.5]:
			for z: float in [-size.z*.5,0.0,size.z*.5]:
				var from: Vector3 = at+Vector3(x,size.y*.5,z)
				var hit: Dictionary = space.intersect_ray(PhysicsRayQueryParameters3D.create(from,from+Vector3(0,-3,0),1|4|8|32))
				rays.append({"rid":hit.get("rid"),"position":hit.get("position"),"normal":hit.get("normal"),"shape":hit.get("shape")})
		result.append({"at":at,"hull":size,"sweep":space.cast_motion(query),"rays":rays})
	return result

func _finish() -> void:
	if finished: return
	finished=true
	if is_instance_valid(stage): stage.queue_free()
	elif is_instance_valid(works): works.free()
	await process_frame
	var passed := logger.entries.is_empty()
	for row: Dictionary in checks: passed=passed and row.passed
	var report := {"passed":passed,"checks":checks,"engine_errors":logger.entries,"scope":"direct Works/imported geometry/native same-body fixture, not MAIN/fixed-camera/GPU/performance or human play evidence"}
	if not output.is_empty():
		DirAccess.make_dir_recursive_absolute(output.get_base_dir())
		var file := FileAccess.open(output,FileAccess.WRITE)
		if file!=null: file.store_string(JSON.stringify(report,"\t"))
	print("I2_PAVING_BATCH ",JSON.stringify(report))
	OS.remove_logger(logger)
	quit(0 if passed else 1)
