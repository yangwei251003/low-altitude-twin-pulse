extends SceneTree
## Verify real imported Texture2D dimensions in original GLB materials; no
## rendering/FPS claim and no mutation of original PNG/GLB/geometry/Store.
const MANIFEST := "res://scripts_tools/v3/manifests/i2_texture_import.json"
const NORMAL_MANIFEST := "res://scripts_tools/v3/manifests/constant_normal_import.json"
func _initialize() -> void: _run.call_deferred()
func _run() -> void:
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(MANIFEST))
	var normal_data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(NORMAL_MANIFEST))
	var failed: Array = []
	var textures: Dictionary = {}
	var parents: Array = []
	var normal_paths: Dictionary = {}
	for row: Dictionary in normal_data.square_textures:
		normal_paths["res://"+str(row.texture)] = row
	for row: Dictionary in data.selected_texture_imports:
		var path: String = "res://"+str(row.texture)
		var texture: Texture2D = load(path)
		var actual := [texture.get_width(),texture.get_height()] if texture!=null else []
		var expected: Array = [1,1] if normal_paths.has(path) else [1024,1024]
		textures[path] = {"size":actual,"expected":expected,"used_in_original_material":false}
		if actual!=expected: failed.append("imported_texture_dimensions:"+path)
		if FileAccess.get_sha256(path)!=row.texture_sha256: failed.append("source_PNG_changed:"+path)
		if path.get_base_dir() not in parents: parents.append(path.get_base_dir())
	for path: String in normal_paths:
		var row: Dictionary = normal_paths[path]
		var texture: Texture2D = load(path)
		var actual := [texture.get_width(),texture.get_height()] if texture!=null else []
		textures[path] = {"size":actual,"expected":[1,1],"used_in_original_material":false}
		if actual!=[1,1]: failed.append("constant_normal_dimensions:"+path); continue
		var pixels: Image = texture.get_image()
		var pixel := pixels.get_pixel(0,0) if pixels!=null else Color.TRANSPARENT
		var rgb := [pixel.r8,pixel.g8,pixel.b8]
		textures[path]["rgb"] = rgb
		if rgb!=[128,128,255]: failed.append("constant_normal_pixel_changed:"+path)
		if FileAccess.get_sha256(path)!=row.source_sha256_at_prior_verified_scan: failed.append("source_normal_PNG_changed:"+path)
		if path.get_base_dir() not in parents: parents.append(path.get_base_dir())
	var checked_glbs: Array = []
	for row: Dictionary in data.glb_inventory:
		var path: String = "res://"+str(row.glb)
		if FileAccess.get_sha256(path)!=row.glb_sha256: failed.append("source_GLB_changed:"+path)
		if path.get_base_dir() not in parents: continue
		var packed: PackedScene = load(path)
		if packed==null: failed.append("missing_original_scene:"+path); continue
		var scene: Node = packed.instantiate()
		_inspect(scene,textures,failed)
		scene.free()
		checked_glbs.append(path)
	for path: String in textures:
		if not textures[path].used_in_original_material: failed.append("not_found_in_original_GLB_material:"+path)
	var report := {"pass":failed.is_empty(),"failures":failed,"textures":textures,"checked_glbs":checked_glbs,"original_GLB_hashes":data.glb_inventory.size(),"scope":"Original source hashes and actual imported Texture2D material dimensions only; no graphics, memory or FPS conclusion."}
	var output := "res://artifacts/v3/i2-texture-import-"+str(Time.get_unix_time_from_system())+".json"
	var file := FileAccess.open(output,FileAccess.WRITE)
	if file: file.store_string(JSON.stringify(report,"\t")); file.close()
	print("I2_TEXTURE_IMPORT_RESULT "+JSON.stringify(report))
	quit(0 if failed.is_empty() else 1)
func _inspect(node: Node,textures: Dictionary,failed: Array) -> void:
	if node is MeshInstance3D and node.mesh!=null:
		for surface: int in node.mesh.get_surface_count():
			var material: Material = node.get_active_material(surface)
			if not material is BaseMaterial3D: continue
			for slot: int in BaseMaterial3D.TEXTURE_MAX:
				var texture: Texture2D = material.get_texture(slot)
				if texture==null or not textures.has(texture.resource_path): continue
				textures[texture.resource_path].used_in_original_material = true
				if [texture.get_width(),texture.get_height()]!=textures[texture.resource_path].expected: failed.append("material_texture_dimensions:"+texture.resource_path)
	for child: Node in node.get_children(): _inspect(child,textures,failed)
