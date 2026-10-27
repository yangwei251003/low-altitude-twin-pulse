extends SceneTree

const Streets = preload("res://scripts/v2/street_dressing.gd")
var result: Dictionary = {"phase":"readonly imported GLB versus StreetDressingV2.batch", "models":[]}

func _initialize() -> void:
	call_deferred("run_probe")

func color_array_summary(colors: Variant) -> Dictionary:
	if colors == null or colors.is_empty(): return {"count":0}
	var unique: Dictionary = {}
	var lo = Color(100,100,100,100)
	var hi = Color(-100,-100,-100,-100)
	for c in colors:
		var key = "%.4f,%.4f,%.4f,%.4f" % [c.r,c.g,c.b,c.a]
		unique[key] = int(unique.get(key,0))+1
		lo = Color(minf(lo.r,c.r),minf(lo.g,c.g),minf(lo.b,c.b),minf(lo.a,c.a))
		hi = Color(maxf(hi.r,c.r),maxf(hi.g,c.g),maxf(hi.b,c.b),maxf(hi.a,c.a))
	return {"count":colors.size(),"unique":unique,"min":[lo.r,lo.g,lo.b,lo.a],"max":[hi.r,hi.g,hi.b,hi.a]}

func snapshot(node: Node, visible_only: bool = false) -> Array:
	var entries: Array = []
	for child in node.get_children():
		if child is MeshInstance3D and (not visible_only or child.visible):
			for idx in child.mesh.get_surface_count():
				var arrays = child.mesh.surface_get_arrays(idx)
				var m = child.get_active_material(idx)
				var info = {"mesh":str(child.name),"surface":idx,"vertices":arrays[Mesh.ARRAY_VERTEX].size(),
					"format":child.mesh.surface_get_format(idx),"colors":color_array_summary(arrays[Mesh.ARRAY_COLOR]),
					"material_class":m.get_class() if m else "null","material_name":m.resource_name if m else "null"}
				if m is BaseMaterial3D:
					info["vertex_color_use_as_albedo"] = m.vertex_color_use_as_albedo
					info["vertex_color_is_srgb"] = m.vertex_color_is_srgb
					info["albedo"] = [m.albedo_color.r,m.albedo_color.g,m.albedo_color.b,m.albedo_color.a]
					info["roughness"] = m.roughness
					info["metallic"] = m.metallic
					info["shading_mode"] = m.shading_mode
					info["transparency"] = m.transparency
					info["albedo_texture"] = str(m.albedo_texture.resource_path) if m.albedo_texture else ""
				entries.append(info)
		entries.append_array(snapshot(child,visible_only))
	return entries

func run_probe() -> void:
	var manifest = JSON.parse_string(FileAccess.get_file_as_string("res://assets/v2/streets/manifest.json"))
	for model in manifest.models:
		var holder = Node3D.new()
		root.add_child(holder)
		var scene = load(model.path).instantiate()
		holder.add_child(scene)
		var before = snapshot(holder)
		Streets.batch(holder)
		var after = snapshot(holder,true)
		result.models.append({"id":model.id,"before":before,"after":after})
		holder.free()
	var file = FileAccess.open("res://artifacts/v2/material_probe.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(result,"\t"))
	print("MATERIAL_PROBE_COMPLETE models=",result.models.size())
	quit()
