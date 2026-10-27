class_name TwinUnderdeckShellArt
extends RefCounted
## Explicit GLB presentation; the passage retains its exact physical shell.
const MODEL_PATH := "res://assets/v3/underdeck_shell/underdeck_shell.glb"
const PARTS := ["NavigationSurface", "CoverSurface", "CoverDetails", "RoofSupports"]

static func install(shell: Node3D) -> Dictionary:
	var packed := load(MODEL_PATH) as PackedScene
	if packed == null: return {"ok":false, "code":"shell_glb_missing"}
	var model := packed.instantiate() as Node3D
	if model == null: return {"ok":false, "code":"shell_root_type"}
	var selected: Dictionary = {}
	var triangles := 0
	var surfaces := 0
	for name in PARTS:
		var found := model.find_children(name, "MeshInstance3D", true, false)
		if found.size() != 1:
			model.free()
			return {"ok":false, "code":"shell_part:" + name}
		var mesh: MeshInstance3D = found[0]
		var node: Node = mesh
		while node != null:
			if node is Node3D and not node.transform.is_equal_approx(Transform3D.IDENTITY):
				model.free()
				return {"ok":false, "code":"shell_nonidentity:" + name}
			node = node.get_parent()
		if mesh.mesh == null:
			model.free()
			return {"ok":false, "code":"shell_empty_mesh:" + name}
		triangles += mesh.mesh.get_faces().size() / 3
		surfaces += mesh.mesh.get_surface_count()
		for index in mesh.mesh.get_surface_count():
			var material := mesh.get_active_material(index) as BaseMaterial3D
			if material == null or material.albedo_texture == null or material.normal_texture == null:
				model.free()
				return {"ok":false, "code":"shell_pbr_material:" + name}
		selected[name] = mesh
	if triangles > 22000 or model.find_children("*", "MeshInstance3D", true, false).size() != PARTS.size() or not model.find_children("*", "CollisionObject3D", true, false).is_empty() or not model.find_children("*", "Camera3D", true, false).is_empty() or not model.find_children("*", "Light3D", true, false).is_empty():
		model.free()
		return {"ok":false, "code":"shell_export_contract"}
	# Preserve established public paths. These now contain the imported render
	# surfaces, so camera/coverage checks exercise the actual authored asset.
	for pair in [["NavigationSurface", "PermanentNavigation"], ["CoverSurface", "OccludingCover"]]:
		var parent: Node3D = shell.get_node(pair[1])
		var previous: Node = parent.get_node("Surface")
		parent.remove_child(previous)
		previous.free()
		var mesh: MeshInstance3D = selected[pair[0]]
		mesh.owner = null
		mesh.get_parent().remove_child(mesh)
		mesh.name = "Surface"
		if pair[0] == "CoverSurface": mesh.set_meta("terrain_visibility_single_sided", true)
		parent.add_child(mesh)
	for name in ["CoverDetails", "RoofSupports"]:
		var mesh: MeshInstance3D = selected[name]
		mesh.owner = null
		mesh.set_meta("terrain_visibility_cutaway_detail", true)
		mesh.get_parent().remove_child(mesh)
		shell.get_node("OccludingCover").add_child(mesh)
	model.free()
	shell.set_meta("authored_shell", true)
	return {"ok":true, "code":"authored_shell_installed", "triangles":triangles, "surfaces":surfaces, "path":MODEL_PATH}
