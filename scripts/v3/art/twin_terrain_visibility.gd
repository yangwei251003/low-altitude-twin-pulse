class_name TwinTerrainVisibility
extends RefCounted
## Local-camera assistance only. Never writes collision, gameplay or replicated state.
const FADED_ALPHA := 0.20
const SCAN_INTERVAL := 0.10
const RELEASE_HOLD := 0.18
const MAX_RAY_LAYERS := 16
const PROTECTED_CLASSES := ["TwinParasiticCrown", "TwinSiphonWhale", "TwinCrownWarning", "TwinBossWarning", "FlightBodyV2"]

var occluded := false
var _camera: Camera3D
var _pilot: Node3D
var _entries: Dictionary = {}
var _scan_elapsed := SCAN_INTERVAL

func setup(camera: Camera3D, pilot: Node3D, candidates: Array) -> void:
	clear()
	_camera = camera
	_pilot = pilot
	for candidate in candidates:
		if not candidate is Node3D or not is_instance_valid(candidate) or candidate.is_queued_for_deletion() or _protected(candidate): continue
		var id: int = candidate.get_instance_id()
		if _entries.has(id): continue
		# Keep candidate ownership disjoint even if a caller supplies both a
		# wrapper and its visual child. One mesh must never have two restorers.
		var has_parent := false
		for existing in _entries.values():
			if existing.root.is_ancestor_of(candidate): has_parent = true
		if has_parent: continue
		for existing_id in _entries.keys():
			if candidate.is_ancestor_of(_entries[existing_id].root): _entries.erase(existing_id)
		var meshes: Array[MeshInstance3D] = []
		_collect(candidate, meshes)
		if meshes.is_empty(): continue
		_entries[id] = {"root":candidate, "meshes":meshes, "blocked":false, "hold":0.0, "alpha":1.0, "rows":[], "installed":false}
	_scan_elapsed = SCAN_INTERVAL

func update(delta: float) -> bool:
	if not is_instance_valid(_camera) or not is_instance_valid(_pilot) or _camera.is_queued_for_deletion() or _pilot.is_queued_for_deletion():
		clear()
		return false
	var elapsed := clampf(delta, 0.0, 0.25) if is_finite(delta) else 0.0
	_scan_elapsed += elapsed
	if _scan_elapsed >= SCAN_INTERVAL:
		_scan_elapsed = 0.0
		_scan()
	occluded = false
	for id in _entries.keys():
		var entry: Dictionary = _entries[id]
		if not is_instance_valid(entry.root) or entry.root.is_queued_for_deletion():
			_restore(entry)
			_entries.erase(id)
			continue
		entry.hold = RELEASE_HOLD if entry.blocked else maxf(0.0, float(entry.hold) - elapsed)
		var fading: bool = entry.blocked or float(entry.hold) > 0.0
		entry.alpha = move_toward(float(entry.alpha), FADED_ALPHA if fading else 1.0, elapsed * (5.2 if fading else 2.7))
		if float(entry.alpha) < 1.0:
			if not entry.installed: _install(entry)
			_set_alpha(entry, float(entry.alpha))
			occluded = true
		elif entry.installed:
			_restore(entry)
	return occluded

func clear() -> void:
	for entry in _entries.values(): _restore(entry)
	_entries.clear()
	_camera = null
	_pilot = null
	_scan_elapsed = SCAN_INTERVAL
	occluded = false

func _protected(node: Node) -> bool:
	if node == _pilot or bool(node.get_meta("terrain_visibility_keep", false)): return true
	var key := str(node.name)
	if key.contains("SapKnot") or key == "HostTarget" or key in ["ParasiticCrown", "SiphonWhale"]: return true
	var script = node.get_script()
	if script is GDScript and str(script.get_global_name()) in PROTECTED_CLASSES: return true
	var entity := str(node.get_meta("entity_id", ""))
	if entity.begins_with("boss:") or entity.begins_with("player:") or entity.begins_with("F1:crown_host_"): return true
	if node is CollisionObject3D and (node.collision_layer & 2) != 0: return true
	return false

func _collect(node: Node, meshes: Array[MeshInstance3D]) -> void:
	if _protected(node): return
	if node is MeshInstance3D and node.mesh != null and node.material_overlay == null:
		var supported := false
		for surface in node.mesh.get_surface_count():
			if node.get_active_material(surface) is BaseMaterial3D: supported = true
		if supported: meshes.append(node)
	for child in node.get_children(): _collect(child, meshes)

func _sample_points() -> Array[Vector3]:
	var centre: Vector3 = _pilot.global_position
	var width := 0.35
	var height := 0.18
	var envelope := _pilot.get_node_or_null("Envelope") as CollisionShape3D
	if envelope != null and envelope.shape is BoxShape3D:
		centre = envelope.global_position
		var half: Vector3 = envelope.shape.size * 0.5
		var projected: Basis = _camera.global_basis.inverse() * envelope.global_basis
		width = (absf(projected.x.x) * half.x + absf(projected.y.x) * half.y + absf(projected.z.x) * half.z) * 0.7
		height = (absf(projected.x.y) * half.x + absf(projected.y.y) * half.y + absf(projected.z.y) * half.z) * 0.7
	return [centre, centre + _camera.global_basis.x * width, centre - _camera.global_basis.x * width,
		centre + _camera.global_basis.y * height, centre - _camera.global_basis.y * height]

func _scan() -> void:
	for entry in _entries.values(): entry.blocked = false
	if not _pilot.is_visible_in_tree() or _camera.is_position_behind(_pilot.global_position): return
	var space := _camera.get_world_3d().direct_space_state
	for point in _sample_points():
		var direction: Vector3 = _camera.global_basis.z.normalized()
		if _camera.projection != Camera3D.PROJECTION_ORTHOGONAL: direction = (_camera.global_position - point).normalized()
		var depth: float = (_camera.global_position - point).dot(direction) - _camera.near
		if depth <= 0.02: continue
		var query := PhysicsRayQueryParameters3D.create(point + direction * depth, point, 1 | 8)
		query.hit_back_faces = true
		var excluded: Array[RID] = []
		if _pilot is CollisionObject3D: excluded.append(_pilot.get_rid())
		for layer in range(MAX_RAY_LAYERS):
			query.exclude = excluded
			var hit: Dictionary = space.intersect_ray(query)
			if hit.is_empty(): break
			var id := _entry_for(hit.collider)
			if id != 0: _entries[id].blocked = true
			# Continue through independently colliding terrain layers, including a
			# protected sap knot. Never alter the collided body's mask or layer.
			var rid: RID = hit.rid
			if rid in excluded: break
			excluded.append(rid)

func _entry_for(collider: Object) -> int:
	var node := collider as Node
	while node != null:
		if _protected(node): return 0
		var id := node.get_instance_id()
		if _entries.has(id):
			return id if node is Node3D and node.is_visible_in_tree() else 0
		node = node.get_parent()
	return 0

func _install(entry: Dictionary) -> void:
	# Capture current per-instance state on each fade cycle, not an obsolete
	# setup-time material. Shared GLB resources remain untouched.
	entry.rows = []
	for mesh in entry.meshes:
		if not is_instance_valid(mesh) or mesh.is_queued_for_deletion(): continue
		var row := {"mesh":mesh, "override":mesh.material_override, "surfaces":[], "copies":[]}
		var has_copy := false
		for surface in mesh.mesh.get_surface_count():
			row.surfaces.append(mesh.get_surface_override_material(surface))
			var original = mesh.get_active_material(surface)
			if original is BaseMaterial3D:
				var copy: BaseMaterial3D = original.duplicate()
				copy.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
				copy.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
				if mesh.get_meta("terrain_visibility_single_sided", false): copy.cull_mode = BaseMaterial3D.CULL_BACK
				row.copies.append({"material":copy, "alpha":original.albedo_color.a})
				has_copy = true
			else: row.copies.append({})
		if not has_copy: continue
		mesh.material_override = null
		for surface in row.copies.size():
			if not row.copies[surface].is_empty(): mesh.set_surface_override_material(surface, row.copies[surface].material)
		entry.rows.append(row)
	entry.installed = true

func _set_alpha(entry: Dictionary, alpha: float) -> void:
	for row in entry.rows:
		# Dense closed details contribute many translucent layers. For authored
		# cutaway meshes, remove those layers at full fade while retaining the
		# simple enclosure silhouette and all separately protected navigation.
		var opacity := alpha
		if row.mesh.get_meta("terrain_visibility_cutaway_detail", false):
			opacity = clampf((alpha - FADED_ALPHA) / (1.0 - FADED_ALPHA), 0.0, 1.0)
		for copy in row.copies:
			if copy.is_empty(): continue
			var material: BaseMaterial3D = copy.material
			var color := material.albedo_color
			color.a = float(copy.alpha) * opacity
			material.albedo_color = color

func _restore(entry: Dictionary) -> void:
	if not entry.installed: return
	for row in entry.rows:
		if not is_instance_valid(row.mesh): continue
		row.mesh.material_override = row.override
		for surface in row.surfaces.size(): row.mesh.set_surface_override_material(surface, row.surfaces[surface])
	entry.rows = []
	entry.installed = false
