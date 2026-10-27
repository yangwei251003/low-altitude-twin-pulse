extends SceneTree
## Read the current post-yard mesh; no scene, collision or save writes.
const World=preload("res://scripts/v3/twin_test_world.gd")
const Reader=preload("res://scripts/v3/art/twin_i2_east_revetment_art.gd")
const Capture=preload("res://scripts_tools/v3/capture_hud_visibility.gd")
var logger=Capture.CaptureLogger.new()

func _initialize() -> void:
	OS.add_logger(logger)
	_run.call_deferred()

func _run() -> void:
	var output:=""
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--output="): output=arg.trim_prefix("--output=")
	if DisplayServer.get_name()!="headless" or not output.begins_with("res://artifacts/v3/central-ground-") or ".." in output or DirAccess.dir_exists_absolute(output): quit(2); return
	var viewport:=SubViewport.new()
	viewport.world_3d=World3D.new()
	viewport.render_target_update_mode=SubViewport.UPDATE_DISABLED
	root.add_child(viewport)
	var world:=World.new()
	viewport.add_child(world)
	world.build("I2",{},true)
	if not world.build_errors.is_empty() or not world.yard_connector_art.get("ok",false):
		print("CENTRAL_GROUND_BUILD_FAILED ",world.build_errors); viewport.free(); quit(1); return
	var dry: MeshInstance3D=world.waterfront_install.meshes.dry_surface
	var read: Dictionary=Reader._read_mesh(dry.mesh)
	if not read.ok or not dry.global_transform.is_equal_approx(Transform3D.IDENTITY): viewport.free(); quit(1); return
	var data: Dictionary=read.geometry
	# Godot re-encodes normal/tangent arrays on ArrayMesh construction. Preserve
	# the actual current values; positions/UV must still equal the stored cut.
	var expected: Dictionary=world.yard_connector_art.remaining_visual
	if data.faces.to_byte_array()!=expected.faces.to_byte_array() or data.uv.to_byte_array()!=expected.uv.to_byte_array(): viewport.free(); quit(1); return
	var ground: StaticBody3D=world.waterfront_install.ground
	var shape: ConcavePolygonShape3D=world.waterfront_install.shape_node.shape
	var collision:=shape.get_faces().to_byte_array()
	var rid:=ground.get_rid()
	DirAccess.make_dir_recursive_absolute(output)
	var files: Dictionary={}
	for key: String in ["faces","normals","uv","tangents"]:
		var bytes: PackedByteArray=data[key].to_byte_array()
		var filename:="remainder."+key+".f32le"
		var stream:=FileAccess.open(output.path_join(filename),FileAccess.WRITE)
		if stream==null: viewport.free(); quit(1); return
		stream.store_buffer(bytes);stream.close()
		files[key]={"file":filename,"bytes":bytes.size(),"sha256":FileAccess.get_sha256(output.path_join(filename))}
	var ids: Array=[]
	for id in int(data.faces.size()/3): ids.append(id)
	var unchanged: bool=ground.get_rid()==rid and world.waterfront_install.shape_node.shape==shape and shape.get_faces().to_byte_array()==collision and Reader._attributes_sha(Reader._read_mesh(dry.mesh).geometry)==Reader._attributes_sha(data)
	var result:={"ok":unchanged and logger.errors.is_empty(),"kind":"current_world_post_yard_raw_arrays","engine":Engine.get_version_info(),"groups":{"remainder":{"vertex_count":data.faces.size(),"triangle_count":data.faces.size()/3,"source_final_triangle_ids":ids,"files":files}},
		"raw_attributes_sha256":Reader._attributes_sha(data),"ground_collision_sha256":Reader.Split._sha(collision),"read_only_unchanged":unchanged,"engine_errors":logger.errors,
		"scope":"Current live World I2 build; raw surface arrays, no Mesh.get_faces visual quantization. Triangle IDs index this current final remainder. Not a MAIN gameplay/graphics test."}
	FileAccess.open(output.path_join("geometry.json"),FileAccess.WRITE).store_string(JSON.stringify(result,"  ",true,true))
	print("CENTRAL_GROUND_EXPORT ",JSON.stringify({"ok":result.ok,"output":output,"triangles":ids.size(),"sha256":FileAccess.get_sha256(output.path_join("geometry.json"))}))
	viewport.free()
	quit(0 if result.ok else 1)
