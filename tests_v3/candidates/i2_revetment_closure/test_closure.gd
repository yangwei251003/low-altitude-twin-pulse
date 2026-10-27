extends SceneTree
## Real installed World geometry. Explicit fixture, not a playthrough.
const World = preload("res://scripts/v3/twin_test_world.gd")
const Candidate = preload("res://scripts/v3/candidates/i2_revetment_closure/revetment_closure.gd")
const Reader = preload("res://scripts/v3/art/twin_i2_east_revetment_art.gd")
const Split = preload("res://scripts/v3/art/twin_i2_revetment_partition.gd")
const FlightCamera = preload("res://scripts/v2/flight_camera.gd")
const OWN := "res://tests_v3/candidates/i2_revetment_closure/"
const MODEL_SHA := "9e3bce1d8871cb3c6778868cc9209d8042a7ecb8eac852d2f99b58e4ca02c67c"
const SIZE := Vector2i(1280,720)
var checks: Array = []
var world: World
var finishing := false
var capture := false
var geometry_only := false
var output := ""
var shots: Array = []
var measurements: Dictionary = {}
var camera: Camera3D
var flight_camera := FlightCamera.new()
var started_usec := 0

class CaptureLogger extends Logger:
	var errors: Array = []
	func _log_error(function: String, file: String, line: int, code: String, rationale: String, _notify: bool, type: int, _backtraces: Array[ScriptBacktrace]) -> void:
		errors.append({"function":function,"file":file,"line":line,"code":code,"rationale":rationale,"type":type})

var logger := CaptureLogger.new()

func _initialize() -> void:
	OS.add_logger(logger)
	_run.call_deferred()

func _run() -> void:
	started_usec = Time.get_ticks_usec()
	if not _arguments_valid():
		print("REVETMENT_CLOSURE_ARGUMENTS_REJECTED")
		OS.remove_logger(logger)
		quit(2)
		return
	if not output.is_empty() and DirAccess.make_dir_recursive_absolute(output) != OK:
		quit(2)
		return
	create_timer(65 if capture else 20,true,false,true).timeout.connect(func() -> void:
		_check(false,"bounded internal watchdog")
		_finish())
	root.size = SIZE
	world = World.new()
	world.include_revetment_closure = false # Explicit pre-install comparison.
	world.include_inspection_pit = false
	root.add_child(world)
	world.build("I2")
	if not _check(world.build_errors.is_empty(),"actual I2 World builds existing banks, floor and four facilities",world.build_errors):
		_finish()
		return
	await physics_frame
	await physics_frame
	if finishing: return
	var baseline: Dictionary = _record()
	var physics_before: Dictionary = _physics_record()
	var facilities_before: Dictionary = _facilities_record()
	measurements.original_physics_count = physics_before.size()
	measurements.facilities = facilities_before
	var prepared: Dictionary = Candidate.prepare_geometry(world.waterfront,world.waterfront_install)
	if not _check(prepared.get("ok",false),"remaining actual visible geometry prepares without resetting prior cuts",prepared.get("report",prepared)):
		_finish()
		return
	_check(_record()==baseline,"pure prepare preserves original scene IDs/attributes and Ground bytes")
	var area: float = (sqrt(3.1*3.1+3.4*3.4)+sqrt(5.6*5.6+3.4*3.4)+9+sqrt(85)+4.3)*2.8
	_check(absf(float(prepared.report.bank.removed_area_m2)-area)<.0005,"all five actual remaining bank lengths replace exact original wall area",prepared.report.bank)
	_check(prepared.parts.bank.kept.faces.is_empty(),"no coplanar original bank triangles remain")
	var repeated: Dictionary = Candidate.prepare_geometry(world.waterfront,world.waterfront_install)
	_check(repeated.get("ok",false) and repeated.report==prepared.report and _record()==baseline,"repeated preparation is deterministic and nonmutating")
	var dry: Dictionary = prepared.parts.dry_surface.kept
	_check(not _covers(dry,Vector2(12.4,6)) and not _covers(dry,Vector2(17.1,6)) and not _covers(dry,Vector2(23,8)),"prior straight-bank/floor cutouts stay cut")
	_check(not _covers(dry,Vector2(14.5,2.15)) and _covers(dry,Vector2(11,10)),"new north top is removed while unrelated west land remains")
	var bad: Dictionary = world.waterfront_install.duplicate()
	bad.ok = false
	_check(not Candidate.prepare_geometry(world.waterfront,bad).ok and _record()==baseline,"invalid host rejects without partial install")
	measurements.partition = prepared.report.duplicate(true)
	if not geometry_only:
		if not _check(FileAccess.get_sha256(Candidate.MODEL)==MODEL_SHA,"candidate matches the approved exact GLB bytes",FileAccess.get_sha256(Candidate.MODEL)):
			_finish()
			return
		var installed: Dictionary = Candidate.install(world.waterfront,world.waterfront_install)
		if _check(installed.get("ok",false),"actual candidate GLB imports and installs",installed.get("code")):
			var after: Dictionary = _record()
			_check(after.ground==baseline.ground and after.shape==baseline.shape and after.faces==baseline.faces,"Ground/shape identity and exact collision byte array unchanged")
			_check(after.other==baseline.other,"all water/bed/outer/underside geometry unchanged")
			_check(after.existing==baseline.existing,"both old banks and approved extension retain actual model IDs/poses")
			_check(_physics_record()==physics_before,"all original physics bodies, RIDs, shape data and server poses unchanged")
			_check(_facilities_record()==facilities_before,"all four actual facilities and ability targets unchanged")
			measurements.imported = _model_record(installed)
			_check(measurements.imported.mesh_count==12 and measurements.imported.surface_count==14 and measurements.imported.triangles==32122 and measurements.imported.material_count==2,
				"actual Godot import is 12 meshes / 14 surfaces / 32122 triangles / 2 PBR materials",measurements.imported)
			_check(not Candidate.install(world.waterfront,world.waterfront_install).ok and _record()==after,"second install rejects without partial mutation")
			if capture:
				camera = Camera3D.new()
				camera.projection = Camera3D.PROJECTION_ORTHOGONAL
				root.add_child(camera)
				camera.make_current()
				flight_camera.configure(camera)
				measurements.lighting = _lighting_record()
				await _capture("01-default-26m",Vector3(16.5,1.8,15),0,[],"Production World lighting and fixed production camera; explicit camera fixture, no MAIN/flight/HUD claim.")
				if finishing: return
				var south_points: Array[Vector3] = []
				for x: float in [9.15,9.5,24.5,24.86]:
					for y: float in [-2.8,0.0]: south_points.append(Vector3(x,y,28))
				await _capture("02-south-both-ends",Vector3(17,1.2,25),0,south_points,"Both real south mouths and their full wall heights must be in the image; open water at Z28 remains open.")
				if finishing: return
				await _capture("03-north-paving-joint",Vector3(14.75,1.2,3),3,[Vector3(12.25,0,2),Vector3(17.25,0,2),Vector3(12.6,-2.8,2.3),Vector3(16.9,-2.8,2.3)],"Three ordinary zoom steps; north cap joins existing paving at Z2 and existing straight banks at Z2.3.")
				if finishing: return
				_check(_record()==after and _physics_record()==physics_before and _facilities_record()==facilities_before,
					"rendering the three views does not change terrain, colliders, prior art or facility state")
	_finish()

func _arguments_valid() -> bool:
	var count := 0
	for argument: String in OS.get_cmdline_user_args():
		if argument=="--capture" and not capture: capture=true
		elif argument=="--geometry-only" and not geometry_only: geometry_only=true
		elif argument.begins_with("--output="):
			count+=1
			output=ProjectSettings.globalize_path(argument.trim_prefix("--output=")).replace("\\","/").simplify_path()
		else: return false
	if count>1 or (capture and (geometry_only or count!=1)): return false
	if not output.is_empty():
		var allowed: String=ProjectSettings.globalize_path(OWN+"evidence").replace("\\","/").simplify_path()
		if output.get_base_dir().to_lower()!=allowed.to_lower() or not output.get_file().begins_with("capture-" if capture else "test-"): return false
		if FileAccess.file_exists(output) or DirAccess.dir_exists_absolute(output): return false
	if capture:
		return DisplayServer.get_name()!="headless" and RenderingServer.get_current_rendering_method()=="gl_compatibility" and RenderingServer.is_render_loop_enabled()
	return true

func _digest(value: Variant) -> String:
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	context.update(var_to_bytes(value))
	return context.finish().hex_encode()

func _physics_record() -> Dictionary:
	var rows: Dictionary = {}
	for node: CollisionObject3D in world.find_children("*","CollisionObject3D",true,false):
		var entry: Dictionary = {"id":node.get_instance_id(),"rid":node.get_rid().get_id(),"local":node.transform,"world":node.global_transform,"layer":node.collision_layer,"mask":node.collision_mask,"shapes":[]}
		if node is PhysicsBody3D: entry.server=PhysicsServer3D.body_get_state(node.get_rid(),PhysicsServer3D.BODY_STATE_TRANSFORM)
		for child: CollisionShape3D in node.find_children("*","CollisionShape3D",true,false):
			if child.shape==null: continue
			entry.shapes.append({"node":child.get_instance_id(),"shape":child.shape.get_instance_id(),"rid":child.shape.get_rid().get_id(),"disabled":child.disabled,"local":child.transform,"world":child.global_transform,"bytes":_digest(PhysicsServer3D.shape_get_data(child.shape.get_rid()))})
		rows[str(node.get_path())]=entry
	return rows

func _facilities_record() -> Dictionary:
	var rows: Dictionary = {}
	for id: String in ["clinic","distribution","trial","shared_access"]:
		var module: Node3D=world.get(id)
		rows[id]={"id":module.get_instance_id(),"snapshot_sha256":_digest(module.snapshot()),"target_definitions_sha256":_digest(module.target_definitions())}
	var targets: Dictionary={}
	for id: String in world.objects:
		var body: Node3D=world.objects[id]
		targets[id]={"id":body.get_instance_id(),"pose":body.global_transform}
	rows.targets_sha256=_digest(targets)
	return rows

func _model_record(installed: Dictionary) -> Dictionary:
	var pieces: Dictionary={}
	var materials: Dictionary={}
	var surfaces := 0
	var triangles := 0
	for view: MeshInstance3D in installed.meshes:
		var count := 0
		for index in view.mesh.get_surface_count():
			var arrays: Array=view.mesh.surface_get_arrays(index)
			var indices: Variant=arrays[Mesh.ARRAY_INDEX]
			count+=int(arrays[Mesh.ARRAY_VERTEX].size()/3) if indices==null or indices.is_empty() else int(indices.size()/3)
			var material := view.get_active_material(index) as BaseMaterial3D
			materials[str(material.get_instance_id())]={"name":material.resource_name,"opaque":material.transparency==BaseMaterial3D.TRANSPARENCY_DISABLED,"normal_enabled":material.normal_enabled,"base_size":material.albedo_texture.get_size(),"normal_size":material.normal_texture.get_size(),"rough_size":material.roughness_texture.get_size(),"metal_size":material.metallic_texture.get_size()}
			surfaces+=1
		triangles+=count
		pieces[str(view.name)]={"triangles":count,"surfaces":view.mesh.get_surface_count(),"local":view.transform,"world":view.global_transform,"bounds":view.mesh.get_aabb()}
	return {"path":Candidate.MODEL,"sha256":FileAccess.get_sha256(Candidate.MODEL),"mesh_count":pieces.size(),"surface_count":surfaces,"triangles":triangles,"material_count":materials.size(),"pieces":pieces,"materials":materials}

func _lighting_record() -> Dictionary:
	var result: Dictionary={"environments":[],"lights":[]}
	for node: WorldEnvironment in world.find_children("*","WorldEnvironment",true,false):
		result.environments.append({"name":node.name,"background":node.environment.background_color,"ambient_energy":node.environment.ambient_light_energy,"reflections":node.environment.reflected_light_source})
	for light: Light3D in world.find_children("*","Light3D",true,false):
		result.lights.append({"name":str(light.get_path()),"transform":light.global_transform,"color":light.light_color,"energy":light.light_energy,"visible":light.is_visible_in_tree()})
	return result

func _capture(id: String, at: Vector3, zoom_steps: int, must_show: Array[Vector3], note: String) -> void:
	flight_camera.target_size=26.0
	if zoom_steps: flight_camera.zoom(zoom_steps)
	flight_camera.snap(at)
	for unused in 12:
		await RenderingServer.frame_post_draw
		if finishing: return
	var points: Array=[]
	var inside := true
	for point: Vector3 in must_show:
		var screen: Vector2=camera.unproject_position(point)
		var visible: bool=not camera.is_position_behind(point) and Rect2(Vector2(24,24),Vector2(SIZE)-Vector2(48,48)).has_point(screen)
		inside=inside and visible
		points.append({"world":point,"screen":screen,"inside_frame":visible})
	_check(inside,"required real joint/end coordinates lie inside the captured frame: "+id,points)
	var picture: Image=root.get_texture().get_image()
	if not _check(picture!=null and not picture.is_empty() and picture.get_size()==SIZE and root.size==SIZE and is_equal_approx(camera.size,flight_camera.target_size),"actual 720p orthographic viewport: "+id): return
	var path: String=output.path_join(id+".png")
	if not _check(not FileAccess.file_exists(path) and picture.save_png(path)==OK,"save fresh actual World PNG: "+id): return
	shots.append({"id":id,"path":path,"sha256":FileAccess.get_sha256(path),"size":[SIZE.x,SIZE.y],"note":note,"camera":{"fixture_target":at,"position":camera.global_position,"basis":camera.global_basis,"orthographic_size":camera.size,"zoom_steps":zoom_steps},"projected_required_points":points})

func _record() -> Dictionary:
	var source: Dictionary = world.waterfront_install
	var other: Dictionary = {}
	for part: String in source.meshes:
		if part in ["bank","dry_surface"]: continue
		var view: MeshInstance3D = source.meshes[part]
		other[part] = {"id":view.get_instance_id(),"mesh":view.mesh.get_instance_id(),"arrays_sha256":_digest(view.mesh.surface_get_arrays(0)),"visible":view.visible,"transform":view.transform}
	var existing: Dictionary = {}
	for name: String in ["AuthoredWestBank","AuthoredEastBankCandidate","EastMaintenanceExtension"]:
		var node: Node3D = source.wrapper.get_node(name)
		var nodes: Array = [node]
		nodes.append_array(node.find_children("*","Node3D",true,false))
		var rows: Array = []
		for item: Node3D in nodes: rows.append([item.get_instance_id(),item.transform,item.visible])
		existing[name] = rows
	return {"ground":source.ground.get_instance_id(),"shape":source.shape_node.shape.get_instance_id(),
		"faces":source.shape_node.shape.get_faces().to_byte_array(),"other":other,"existing":existing,
		"bank_visible":source.meshes.bank.visible,"dry_mesh":source.meshes.dry_surface.mesh.get_instance_id(),
		"bank_mesh":source.meshes.bank.mesh.get_instance_id(),"child_count":source.wrapper.get_child_count()}

func _covers(geometry: Dictionary, point: Vector2) -> bool:
	for first in range(0,geometry.faces.size(),3):
		var a: Vector3 = geometry.faces[first]
		var b: Vector3 = geometry.faces[first+1]
		var c: Vector3 = geometry.faces[first+2]
		if Geometry2D.is_point_in_polygon(point,PackedVector2Array([Vector2(a.x,a.z),Vector2(b.x,b.z),Vector2(c.x,c.z)])): return true
	return false

func _check(ok: bool, label: String, details: Variant = null) -> bool:
	checks.append({"passed":ok,"name":label,"details":details})
	print("PASS " if ok else "FAIL ",label," ",JSON.stringify(details))
	return ok

func _finish() -> void:
	if finishing: return
	finishing = true
	if is_instance_valid(camera): camera.free()
	if is_instance_valid(world): world.free()
	await process_frame
	_check(logger.errors.is_empty(),"zero engine errors including cleanup",logger.errors)
	var passed := true
	for row: Dictionary in checks: passed = passed and bool(row.passed)
	if capture: passed=passed and shots.size()==3
	var report: Dictionary={"passed":passed,"checks":checks,"shots":shots,"measurements":measurements,"engine_errors":logger.errors,"elapsed_seconds":(Time.get_ticks_usec()-started_usec)/1000000.0,"scope":"production World/lighting/FlightCamera fixture with manually installed closure candidate; no MAIN/Session/HUD/playthrough/performance/network/human/final-art acceptance"}
	if not output.is_empty():
		var file:=FileAccess.open(output.path_join("result.json"),FileAccess.WRITE)
		if file==null:
			passed=false
			print("REVETMENT_CLOSURE_REPORT_WRITE_FAILED ",FileAccess.get_open_error())
		else:
			file.store_string(JSON.stringify(report,"\t",true,true)+"\n")
			file.close()
	print("REVETMENT_CLOSURE_RESULT ",JSON.stringify(report))
	OS.remove_logger(logger)
	quit(0 if passed else 1)
