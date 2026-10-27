extends Node
## Orthographic sight-line fading. Registration happens once per streamed object.
## Materials are copied lazily; shared imported resources and collision never change.

const FADED_ALPHA = 0.20
const SCAN_INTERVAL = 0.065
const RELEASE_HOLD = 0.18
const SAMPLE_OFFSETS = [Vector2.ZERO, Vector2(-0.8, 0), Vector2(0.8, 0), Vector2(0, -0.45), Vector2(0, 0.45)]

var camera: Camera3D
var target: Node3D
var entries: Dictionary = {}
var outline_entries: Dictionary = {}
var scan_elapsed = SCAN_INTERVAL
var occluded = false

func configure(view: Camera3D, subject: Node3D) -> void:
	camera = view
	target = subject

func register_occluder(root: Node3D) -> void:
	if not is_instance_valid(root) or entries.has(root.get_instance_id()): return
	if root.has_meta("v2_outline_only_bounds"):
		register_outline_occluder(root, root.get_meta("v2_outline_only_bounds"))
		return
	var meshes: Array[MeshInstance3D] = []
	_collect_meshes(root, meshes)
	if meshes.is_empty(): return
	var bounds: AABB
	var first = true
	for mesh in meshes:
		var local_box: AABB = root.global_transform.affine_inverse() * mesh.global_transform * mesh.get_aabb()
		bounds = local_box if first else bounds.merge(local_box)
		first = false
	entries[root.get_instance_id()] = {"root":root, "meshes":meshes, "bounds":bounds, "alpha":1.0, "blocked":false, "hold":0.0, "materials":[], "installed":false}

func register_outline_occluder(root: Node3D, bounds: AABB) -> void:
	if not is_instance_valid(root) or outline_entries.has(root.get_instance_id()): return
	if bounds.size.x <= 0.0 or bounds.size.y <= 0.0 or bounds.size.z <= 0.0: return
	# A small per-object proxy survives MultiMesh batching. Its envelope only
	# requests the drone silhouette; no batched material or collision is touched.
	outline_entries[root.get_instance_id()] = {"root":root, "bounds":bounds, "blocked":false, "hold":0.0}

func _collect_meshes(node: Node, result: Array[MeshInstance3D]) -> void:
	if node is MeshInstance3D and node.mesh != null: result.append(node)
	for child in node.get_children(): _collect_meshes(child, result)

func update_visibility(delta: float) -> void:
	if not is_instance_valid(camera) or not is_instance_valid(target): return
	scan_elapsed += delta
	if scan_elapsed >= SCAN_INTERVAL:
		scan_elapsed = 0.0
		_scan()
	occluded = false
	for id in entries.keys():
		var entry: Dictionary = entries[id]
		if not is_instance_valid(entry.root) or entry.root.is_queued_for_deletion():
			entries.erase(id)
			continue
		entry.hold = RELEASE_HOLD if entry.blocked else maxf(0.0, float(entry.hold) - delta)
		var fading = entry.blocked or entry.hold > 0.0
		var wanted = FADED_ALPHA if fading else 1.0
		entry.alpha = move_toward(float(entry.alpha), wanted, delta * (5.2 if fading else 2.7))
		if entry.alpha < 1.0:
			_install_materials(entry)
			_set_alpha(entry, float(entry.alpha))
			occluded = true
		elif entry.installed:
			_restore_materials(entry)
	for id in outline_entries.keys():
		var entry: Dictionary = outline_entries[id]
		if not is_instance_valid(entry.root) or entry.root.is_queued_for_deletion():
			outline_entries.erase(id)
			continue
		entry.hold = RELEASE_HOLD if entry.blocked else maxf(0.0, float(entry.hold) - delta)
		if entry.blocked or entry.hold > 0.0: occluded = true
	if target.has_method("set_occlusion_hint"): target.set_occlusion_hint(occluded, delta)

func _scan() -> void:
	# For an orthographic camera every pixel ray is parallel, including while
	# the subject is away from screen centre during follow-camera smoothing.
	var direction = camera.global_basis.z.normalized()
	var depth = maxf(0.0, (camera.global_position - target.global_position).dot(direction) - camera.near)
	var centre = target.global_position + Vector3.UP * 0.10
	var sample_points: Array[Vector3] = []
	for offset in SAMPLE_OFFSETS:
		sample_points.append(centre + camera.global_basis.x * offset.x + camera.global_basis.y * offset.y + direction * 0.18)
	for entry in entries.values():
		entry.blocked = false
		if not is_instance_valid(entry.root) or not entry.root.is_visible_in_tree(): continue
		var box: AABB = entry.root.global_transform * entry.bounds
		var broad_hit = false
		for point in sample_points:
			if box.intersects_segment(point, point + direction * depth) != null:
				broad_hit = true
				break
		if not broad_hit: continue
		for mesh in entry.meshes:
			if not is_instance_valid(mesh) or not mesh.is_visible_in_tree(): continue
			var to_local: Transform3D = mesh.global_transform.affine_inverse()
			var mesh_box: AABB = mesh.get_aabb()
			for point in sample_points:
				if mesh_box.intersects_segment(to_local * point, to_local * (point + direction * depth)) != null:
					entry.blocked = true
					break
			if entry.blocked: break
	for entry in outline_entries.values():
		entry.blocked = false
		if not is_instance_valid(entry.root) or not entry.root.is_visible_in_tree(): continue
		var to_local: Transform3D = entry.root.global_transform.affine_inverse()
		var bounds: AABB = entry.bounds
		for point in sample_points:
			if bounds.intersects_segment(to_local * point, to_local * (point + direction * depth)) != null:
				entry.blocked = true
				break

func _install_materials(entry: Dictionary) -> void:
	if entry.installed: return
	if entry.materials.is_empty():
		for mesh in entry.meshes:
			if not is_instance_valid(mesh): continue
			var row = {"mesh":mesh, "override":mesh.material_override, "surface_overrides":[], "faded":[], "base_alpha":[]}
			for surface in range(mesh.mesh.get_surface_count()):
				row.surface_overrides.append(mesh.get_surface_override_material(surface))
				var original = mesh.get_active_material(surface)
				var faded: BaseMaterial3D
				if original is BaseMaterial3D:
					faded = original.duplicate()
				elif original == null:
					faded = StandardMaterial3D.new()
				else:
					# Custom shader surfaces retain their authored appearance. The
					# always-visible drone silhouette remains the fallback for them.
					row.faded.append(null)
					row.base_alpha.append(1.0)
					continue
				faded.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
				faded.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
				row.faded.append(faded)
				row.base_alpha.append(faded.albedo_color.a)
			entry.materials.append(row)
	for row in entry.materials:
		if not is_instance_valid(row.mesh): continue
		# A whole-object override would mask the surface alpha overrides.
		row.mesh.material_override = null
		for surface in range(row.faded.size()):
			if row.faded[surface] != null: row.mesh.set_surface_override_material(surface, row.faded[surface])
			elif row.override != null: row.mesh.set_surface_override_material(surface, row.override)
	entry.installed = true

func _set_alpha(entry: Dictionary, alpha: float) -> void:
	for row in entry.materials:
		for surface in range(row.faded.size()):
			var material: BaseMaterial3D = row.faded[surface]
			if material == null: continue
			var color = material.albedo_color
			color.a = float(row.base_alpha[surface]) * alpha
			material.albedo_color = color

func _restore_materials(entry: Dictionary) -> void:
	for row in entry.materials:
		if not is_instance_valid(row.mesh): continue
		row.mesh.material_override = row.override
		for surface in range(row.surface_overrides.size()): row.mesh.set_surface_override_material(surface, row.surface_overrides[surface])
	entry.installed = false

func reset() -> void:
	for entry in entries.values():
		if entry.installed: _restore_materials(entry)
	entries.clear()
	outline_entries.clear()
	occluded = false
	if is_instance_valid(target) and target.has_method("set_occlusion_hint"): target.set_occlusion_hint(false, 1.0)

func _exit_tree() -> void:
	reset()
