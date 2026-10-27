extends SceneTree
## Actual imported-source vs batched visual equivalence and original native
## collision. Direct Works fixture; no Session, Story, LAN, GPU/FPS or playtest.
const Works = preload("res://scripts/v3/world/twin_clinic_waterworks.gd")
const Art = preload("res://scripts/v3/art/twin_clinic_reception_art.gd")
const Visibility = preload("res://scripts/v3/art/twin_terrain_visibility.gd")
const CameraControl = preload("res://scripts/v2/flight_camera.gd")
var checks: Array = []
var failures: Array = []
var source: Node3D
var works: Node3D
var stage: Node3D
var originals: Dictionary = {}
var helper = Visibility.new()
var output := ""
class ErrorLogger extends Logger:
	var errors: Array = []
	var guard := Mutex.new()
	func _log_error(function: String,file: String,line: int,code: String,rationale: String,_notify: bool,kind: int,_trace: Array[ScriptBacktrace]) -> void:
		if kind==Logger.ERROR_TYPE_WARNING: return
		guard.lock()
		errors.append({"function":function,"file":file,"line":line,"code":code,"rationale":rationale})
		guard.unlock()
var logger := ErrorLogger.new()

func _initialize() -> void:
	OS.add_logger(logger)
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--output="): output=arg.trim_prefix("--output=")
	_run.call_deferred()

func _check(passed: bool, label: String, detail: Variant = null) -> void:
	checks.append({"name":label,"passed":passed,"detail":detail})
	if not passed: failures.append(label)

func _run() -> void:
	source=(load(Art.MODEL_PATH) as PackedScene).instantiate()
	var source_materials: Dictionary = {}
	var triangles := 0
	for mesh: MeshInstance3D in source.find_children("*","MeshInstance3D",true,false):
		var pose: Transform3D=Transform3D(Basis.IDENTITY,Art.ORIGIN)*Art._relative(mesh,source)
		originals[str(mesh.name)]={"mesh":mesh.mesh,"pose":pose,"material":mesh.get_active_material(0)}
		source_materials[mesh.get_active_material(0).get_instance_id()]=true
		triangles+=int(mesh.mesh.get_faces().size()/3)
	_check(originals.size()==186 and triangles==15951 and source_materials.size()==19,"independent actual source retains186/15951/19")
	works=Works.new()
	var configured: Dictionary=works.configure(JSON.parse_string(FileAccess.get_file_as_string(Works.PATH)),{},false)
	_check(configured.ok,"bare original Works configures",configured)
	if not configured.ok:
		await _finish()
		return
	var mechanism: Dictionary=works.snapshot()
	var before: Dictionary = {}
	for name in works.fixed_bodies:
		var body: StaticBody3D=works.fixed_bodies[name]
		var shape: CollisionShape3D=body.get_node("ExactBoxCollision")
		before[name]={"body":body,"rid":body.get_rid(),"shape":shape.shape,"shape_rid":shape.shape.get_rid(),"pose":body.transform,"size":shape.shape.size,"layer":body.collision_layer,"mask":body.collision_mask}
	var art: Dictionary=Art.install(works)
	_check(art.get("ok",false),"normal reception installation and visual batch succeeds",art.get("code",""))
	if not art.get("ok",false):
		await _finish()
		return
	works.reception_art=art
	_check(art.source_mesh_count==186 and art.source_triangles==15951 and art.source_material_count==19,"source accounting remains distinct from active runtime meshes")
	_check(art.model_meshes==art.runtime_meshes and art.runtime_meshes.size()<186 and art.runtime_meshes.size()==art.mesh_count,"runtime arrays expose real reduced geometry without a hardcoded candidate count",art.runtime_meshes.size())
	_check(art.occluders.size()==13 and art.detail_bodies.size()==11 and works.fixed_bodies.size()==65,"original cover and collision body accounting unchanged")
	stage=Node3D.new()
	root.add_child(stage)
	stage.add_child(works)
	await physics_frame
	await physics_frame
	await process_frame
	var intact := true
	for name in before:
		var old: Dictionary=before[name]
		var body: StaticBody3D=works.fixed_bodies[name]
		var shape: CollisionShape3D=body.get_node("ExactBoxCollision")
		intact=intact and body==old.body and body.get_rid()==old.rid and shape.shape==old.shape and shape.shape.get_rid()==old.shape_rid and shape.shape.size==old.size and Art._relative(body,works)==old.pose and body.collision_layer==old.layer and body.collision_mask==old.mask
		intact=intact and PhysicsServer3D.body_get_space(body.get_rid())==stage.get_world_3d().space and PhysicsServer3D.body_get_shape(body.get_rid(),0)==old.shape_rid and PhysicsServer3D.body_get_state(body.get_rid(),PhysicsServer3D.BODY_STATE_TRANSFORM).is_equal_approx(body.global_transform)
	_check(intact and works.snapshot()==mechanism,"same65 original physical bodies/shape RIDs/poses/filter/native space and mechanism state survive installation")
	_test_geometry(art)
	_test_details(art)
	await _test_fade(art)
	await _finish()

func _corners(mesh: Mesh, pose: Transform3D) -> Array:
	var arrays: Array=mesh.surface_get_arrays(0)
	var vertices: PackedVector3Array=arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array=arrays[Mesh.ARRAY_NORMAL]
	var uvs: PackedVector2Array=arrays[Mesh.ARRAY_TEX_UV]
	var indices: PackedInt32Array=arrays[Mesh.ARRAY_INDEX]
	var result: Array = []
	for corner in (indices.size() if not indices.is_empty() else vertices.size()):
		var index: int=indices[corner] if not indices.is_empty() else corner
		result.append([pose*vertices[index],(pose.basis*normals[index]).normalized(),uvs[index]])
	return result

func _equal_corners(expected: Array, actual: Array) -> bool:
	if expected.size()!=actual.size(): return false
	for index in expected.size():
		if expected[index][0].distance_to(actual[index][0])>0.0001 or expected[index][1].distance_to(actual[index][1])>0.0001 or expected[index][2].distance_to(actual[index][2])>0.000001: return false
	return true

func _test_geometry(art: Dictionary) -> void:
	var runtime: Dictionary = {}
	var live := true
	var source_bounds := AABB()
	var runtime_bounds := AABB()
	var first_source := true
	var first_runtime := true
	for row: Dictionary in originals.values():
		for vertex in row.mesh.get_faces():
			var point: Vector3=row.pose*vertex
			source_bounds=AABB(point,Vector3.ZERO) if first_source else source_bounds.expand(point)
			first_source=false
	for mesh: MeshInstance3D in art.runtime_meshes:
		live=live and is_instance_valid(mesh) and mesh.is_inside_tree() and mesh.visible
		runtime[str(mesh.name)]=mesh
		for vertex in mesh.mesh.get_faces():
			var point: Vector3=Art._relative(mesh,works)*vertex
			runtime_bounds=AABB(point,Vector3.ZERO) if first_runtime else runtime_bounds.expand(point)
			first_runtime=false
	_check(source_bounds.position.distance_to(runtime_bounds.position)<=0.0001 and source_bounds.end.distance_to(runtime_bounds.end)<=0.0001,"independent source/runtime world-space geometric AABB remains equal",{"source":str(source_bounds),"runtime":str(runtime_bounds)})
	var accounted: Dictionary = {}
	var equivalent := true
	var runtime_triangles := 0
	for entry: Dictionary in art.batch_report.entries:
		var target: MeshInstance3D=runtime.get(entry.runtime_name)
		if target==null:
			equivalent=false
			continue
		var expected: Array = []
		for name in entry.source_names:
			if accounted.has(name) or not originals.has(name): equivalent=false; continue
			accounted[name]=true
			var row: Dictionary=originals[name]
			expected.append_array(_corners(row.mesh,row.pose))
			equivalent=equivalent and target.get_active_material(0)==row.material
		var actual: Array=_corners(target.mesh,Art._relative(target,works))
		equivalent=equivalent and _equal_corners(expected,actual) and target.get_meta("terrain_visibility_cutaway_detail",false)==entry.detail
	for mesh: MeshInstance3D in art.runtime_meshes:
		runtime_triangles+=int(mesh.mesh.get_faces().size()/3)
		var name := str(mesh.name)
		if not originals.has(name): continue
		if accounted.has(name): equivalent=false
		accounted[name]=true
		var row: Dictionary=originals[name]
		equivalent=equivalent and mesh.mesh==row.mesh and _equal_corners(_corners(row.mesh,row.pose),_corners(mesh.mesh,Art._relative(mesh,works)))
		if mesh!=art.status_mesh: equivalent=equivalent and mesh.get_active_material(0)==row.material
	_check(live and accounted.size()==186 and runtime_triangles==15951 and equivalent,"every actual source triangle/UV0/normal/material/world position is accounted exactly once in active runtime",{"runtime":runtime.size(),"accounted_sources":accounted.size(),"triangles":runtime_triangles})
	var hidden_sources := 0
	for mesh in works.find_children("*","MeshInstance3D",true,false):
		if originals.has(str(mesh.name)) and not mesh.visible: hidden_sources+=1
	_check(hidden_sources==0,"merged original186 are freed rather than hidden from drawing but left in fader traversal",hidden_sources)
	var doors := 0
	var glass := 0
	for mesh: MeshInstance3D in art.runtime_meshes:
		var cursor: Node=mesh
		while cursor!=works:
			if str(cursor.name)=="Doors": doors+=1; break
			cursor=cursor.get_parent()
		if mesh.get_active_material(0).transparency!=BaseMaterial3D.TRANSPARENCY_DISABLED: glass+=1
	_check(doors==10 and glass==5,"both original door pivots/leaves and five glass panels remain independent",{"door_meshes":doors,"glass_meshes":glass})
	var original_status: BaseMaterial3D=originals.ReceptionLight.material
	var before_color: Color=art.status_material.albedo_color
	Art.set_service_available(art,true)
	_check(art.status_mesh.get_active_material(0)==art.status_material and art.status_material!=original_status and art.status_material.albedo_color!=before_color and original_status.albedo_color==before_color,"service status remains an independent mutable material")
	Art.set_service_available(art,false)

func _test_details(art: Dictionary) -> void:
	var design: Node3D=source.get_node("ClinicReception")
	var exact := true
	for name in Art.GROUPS:
		if name.ends_with("Floor") or name=="ReceptionServiceStatus": continue
		var expected := PackedVector3Array()
		for path in Art.GROUPS[name].paths:
			var branch: Node3D=design.get_node(NodePath(path))
			for mesh: MeshInstance3D in branch.find_children("*","MeshInstance3D",true,false):
				var row: Dictionary=originals[str(mesh.name)]
				for vertex in mesh.mesh.get_faces(): expected.append(row.pose*vertex)
		var body: StaticBody3D=art.detail_bodies[name]
		var shape: ConcavePolygonShape3D=body.get_child(0).shape
		var actual: PackedVector3Array=shape.get_faces()
		exact=exact and actual.size()==expected.size() and shape.backface_collision and body.collision_layer==1 and body.collision_mask==0
		for index in mini(expected.size(),actual.size()): exact=exact and expected[index].distance_to(actual[index])<=0.00001
		exact=exact and PhysicsServer3D.body_get_shape(body.get_rid(),0)==shape.get_rid()
	_check(exact,"all ten original architectural/furniture concave colliders retain independently imported faces and native shape binding")
	_check(art.support.model_meshes.size()==2 and art.support.triangles==4520 and art.detail_bodies.ReceptionSupport==art.support.detail_body,"separate existing support geometry/collision is retained")

func _test_fade(art: Dictionary) -> void:
	var camera := Camera3D.new()
	camera.projection=Camera3D.PROJECTION_ORTHOGONAL
	stage.add_child(camera)
	var pilot := Node3D.new()
	stage.add_child(pilot)
	var control=CameraControl.new()
	control.configure(camera)
	control.target_size=26.0
	for row in [["ReceptionRearRoofLeft",Vector3(4.3,6.4,-8)],["ReceptionRearRoofRight",Vector3(9.7,6.4,-8)],["ReceptionCanopyLeft",Vector3(3.5,6.4,-3.8)],["ReceptionCanopyRight",Vector3(10.5,6.4,-3.8)]]:
		helper.clear()
		pilot.global_position=row[1]
		control.snap(pilot.global_position)
		var cover: Node3D=works.get_node(NodePath(row[0]))
		var saved: Array = []
		for mesh: MeshInstance3D in cover.get_node("AuthoredVisual").find_children("*","MeshInstance3D",true,false): saved.append({"mesh":mesh,"material":mesh.get_active_material(0)})
		helper.setup(camera,pilot,art.occluders)
		for unused in 6: helper.update(.1)
		var valid: bool=helper._entries.get(cover.get_instance_id(),{}).get("blocked",false)
		var shell := false
		var detail := false
		for record: Dictionary in saved:
			var material: BaseMaterial3D=record.mesh.get_active_material(0)
			var cutaway: bool=record.mesh.get_meta("terrain_visibility_cutaway_detail",false)
			if cutaway: detail=true
			else: shell=true
			valid=valid and material!=record.material and is_equal_approx(material.albedo_color.a,record.material.albedo_color.a*(0.0 if cutaway else .2))
		_check(valid and shell and detail,"real fixed-camera fade preserves shell20percent/detail0 independently: "+str(row[0]))
		helper.clear()
		for record: Dictionary in saved: valid=valid and record.mesh.get_active_material(0)==record.material
		_check(valid,"fade releases restore original material identity: "+str(row[0]))

func _finish() -> void:
	helper.clear()
	if is_instance_valid(source): source.free()
	if is_instance_valid(stage): stage.queue_free()
	elif is_instance_valid(works): works.free()
	await process_frame
	var report := {"passed":failures.is_empty() and logger.errors.is_empty(),"checks":checks,"failures":failures,"engine_errors":logger.errors,"scope":"actual imported visual attributes/materials and native original collision; direct Works and parked camera fixtures; no FPS, GPU, story or playthrough claim"}
	if not output.is_empty():
		var file=FileAccess.open(output,FileAccess.WRITE)
		if file!=null: file.store_string(JSON.stringify(report))
	print("CLINIC_RECEPTION_BATCH ",JSON.stringify(report))
	OS.remove_logger(logger)
	quit(0 if report.passed else 1)
