extends SceneTree
## One production Waterfront -> banks -> maintenance -> closure -> physical pit pipeline.
## Detached construction fixture, then native readback. No MAIN/flight/camera/FPS claim.
## Canonical GLBs are read-only hierarchy/material references, never collision inputs.
const Terrain = preload("res://scripts/v3/world/twin_i2_waterfront_terrain.gd")
const West = preload("res://scripts/v3/art/twin_i2_revetment_art.gd")
const East = preload("res://scripts/v3/art/twin_i2_east_revetment_art.gd")
const Maintenance = preload("res://scripts/v3/art/twin_i2_east_maintenance_art.gd")
const Closure = preload("res://scripts/v3/art/twin_i2_revetment_closure_art.gd")
const Pit = preload("res://scripts/v3/world/twin_i2_inspection_pit.gd")
const PitArt = preload("res://scripts/v3/art/twin_i2_inspection_pit_art.gd")
const PREFIX := "res://assets/v3/environment/i2_visual_lod/20261021_021300_adedde/"
const EXPECTED_TRIANGLES := {
	"revetment_4m_lod.glb":{"RevetmentSurface":1804},
	"revetment_1p3_lod.glb":{"RevetmentSurface":411},
	"east_maintenance_lod.glb":{"FloorSurface":1431,"InspectionBand":2620},
	"inspection_pit_lod.glb":{"FloorAndRamp":1860,"Hardware":3054,"WallConcrete":2460}}
var checks: Array = []
var host: Node3D
var output := ""
var finished := false

class ErrorLogger extends Logger:
	var errors: Array = []
	func _log_error(function: String, file: String, line: int, code: String, rationale: String, _notify: bool, kind: int, _traces: Array[ScriptBacktrace]) -> void:
		errors.append({"function":function,"file":file,"line":line,"code":code,"rationale":rationale,"type":kind})

var logger := ErrorLogger.new()

func _initialize() -> void:
	OS.add_logger(logger)
	_run.call_deferred()

func _run() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--output="): output = arg.trim_prefix("--output=")
	if not output.begins_with("res://artifacts/v3/i2-visual-lod-") or ".." in output or DirAccess.dir_exists_absolute(output):
		quit(2)
		return
	DirAccess.make_dir_recursive_absolute(output)
	create_timer(12.0).timeout.connect(func() -> void:
		if not finished:
			_check(false,"bounded combination check timeout")
			_finish())
	var terrain := Terrain.new()
	if not _check(terrain.configure().get("ok",false),"actual Waterfront configures from current production definition"):
		_finish(); return
	var installed: Dictionary = _host_fixture(terrain)
	if not _check(installed.get("ok",false),"production Terrain.install on canonical JSON Ground",installed.get("code")):
		_finish(); return
	var baseline: Dictionary = _ground_record(installed)
	var west: Dictionary = West.install(terrain,installed)
	if not _check(west.get("ok",false),"production west LOD installer",west.get("code")):
		_finish(); return
	_preserved(installed,baseline,"west LOD preserves original Ground and exact collision")
	var east: Dictionary = East.install(terrain,installed)
	if not _check(east.get("ok",false),"production east LOD installer",east.get("code")):
		_finish(); return
	_preserved(installed,baseline,"east LOD preserves original Ground and exact collision")
	var maintenance: Dictionary = Maintenance.install(installed)
	if not _check(maintenance.get("ok",false),"production maintenance LOD installer",maintenance.get("code")):
		_finish(); return
	_preserved(installed,baseline,"maintenance LOD preserves original Ground and exact collision")
	var closure: Dictionary = Closure.install(terrain,installed)
	if not _check(closure.get("ok",false),"cancelled closure keeps original production GLB",closure.get("code")):
		_finish(); return
	_check(closure.model.scene_file_path == "res://assets/v3/environment/i2_revetment_closure/revetment_closure.glb",
		"cancelled closure resolves the exact unchanged canonical path")
	_preserved(installed,baseline,"unchanged closure view preserves original Ground and exact collision")
	var pit_builder := Pit.new()
	var pit: Dictionary = pit_builder.install(installed)
	if not _check(pit.get("ok",false),"original physical pit construction runs before pit view",pit.get("code")):
		_finish(); return
	# Excavation intentionally replaces the original shape once. This is the
	# production physical operation, not a collision created from any new GLB.
	var excavated: Dictionary = _ground_record(installed)
	_check(excavated.body_rid == baseline.body_rid and excavated.body_transform == baseline.body_transform and excavated.layer == baseline.layer and excavated.mask == baseline.mask,
		"original excavation retains Ground body identity/transform/masks")
	var pit_art: Dictionary = PitArt.install(pit)
	if not _check(pit_art.get("ok",false),"production pit LOD installer",pit_art.get("code")):
		_finish(); return
	_preserved(installed,excavated,"pit LOD preserves the original excavated shape RID and all collision bytes")
	_check(_sha(excavated.faces) == "d665779e1312e2783a2992ab30538164394a3d7d31e76fa8221ba242d9e709fc",
		"excavated original Ground matches existing canonical I2 collision hash",_sha(excavated.faces))
	_check(West.MODELS.long == PREFIX+"revetment_4m_lod.glb" and West.MODELS.short == PREFIX+"revetment_1p3_lod.glb" and Maintenance.MODEL == PREFIX+"east_maintenance_lod.glb" and PitArt.MODEL == PREFIX+"inspection_pit_lod.glb",
		"all four production visual paths are the exact accepted tag")
	for pair: Array in [[West.SOURCE_MODELS.long,"revetment_4m_lod.glb"],[West.SOURCE_MODELS.short,"revetment_1p3_lod.glb"],[Maintenance.SOURCE_MODEL,"east_maintenance_lod.glb"],[PitArt.SOURCE_MODEL,"inspection_pit_lod.glb"]]:
		_asset_contract(str(pair[0]),str(pair[1]))
	for bank: Dictionary in [west,east]:
		for row: Dictionary in bank.parts:
			var kind: String = "long" if str(row.id).ends_with("D") == false else "short"
			var model: Node3D = row.model
			var visual: MeshInstance3D = row.mesh
			var angle: float = PI*.5 if str(row.id).begins_with("West") else -PI*.5
			var actual: AABB = model.transform * visual.mesh.get_aabb()
			var expected: AABB = Transform3D(Basis(Vector3.UP,angle),model.position) * _expected_box(kind)
			_check(model.scene_file_path == str(West.MODELS[kind]) and model.basis.is_equal_approx(Basis(Vector3.UP,angle)) and _same_box(actual,expected),
				str(row.id)+" real installed path/rotation/exact delivered visual extent",{"actual":actual,"expected":expected})
	_check(maintenance.model.scene_file_path == Maintenance.MODEL and maintenance.model.position == Maintenance.ORIGIN and pit_art.model.scene_file_path == PitArt.MODEL and pit_art.model.position == PitArt.ANCHOR,
		"maintenance/pit views retain original placement")
	root.add_child(host)
	await physics_frame
	await physics_frame
	var ground: StaticBody3D = installed.ground
	var collider: CollisionShape3D = installed.shape_node
	_check(PhysicsServer3D.body_get_shape_count(ground.get_rid()) == 1 and PhysicsServer3D.body_get_shape(ground.get_rid(),0) == collider.shape.get_rid() and PhysicsServer3D.body_get_collision_layer(ground.get_rid()) == ground.collision_layer and PhysicsServer3D.body_get_collision_mask(ground.get_rid()) == ground.collision_mask,
		"native server binds the same original excavated shape and masks")
	for at: Vector3 in [Vector3(-19,-2.4,2.7),Vector3(14.75,-2.8,10),Vector3(-20,0,18)]:
		var hit: Dictionary = host.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(at.x,2,at.z),Vector3(at.x,-3,at.z),1))
		_check(hit.get("collider") == ground and hit.get("position",Vector3.INF).distance_to(at) < .00003,
			"native pit/riverbed/neighbouring support remain original",{"expected":at,"actual":hit.get("position")})
	_preserved(installed,excavated,"native scene entry leaves exact original collision unchanged")
	_finish()

func _host_fixture(terrain: Terrain) -> Dictionary:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/v3/terrain/i2_clinic_layout.json"))
	if not parsed is Dictionary: return {"ok":false,"code":"source_layout"}
	var spec: Dictionary = {}
	for row: Dictionary in parsed.fixed_solids:
		if row.id == "Ground": spec = row
	if spec.is_empty(): return {"ok":false,"code":"source_ground"}
	var lo := Vector3(float(spec.min[0]),float(spec.min[1]),float(spec.min[2]))
	var hi := Vector3(float(spec.max[0]),float(spec.max[1]),float(spec.max[2]))
	host = Node3D.new()
	var ground := StaticBody3D.new()
	ground.name = "Ground"
	ground.collision_layer = 1
	ground.collision_mask = 0
	ground.position = (lo+hi)*.5
	host.add_child(ground)
	var visual := MeshInstance3D.new()
	visual.name = "Visual"
	var box := BoxMesh.new()
	box.size = hi-lo
	visual.mesh = box
	visual.material_override = StandardMaterial3D.new()
	ground.add_child(visual)
	var collision := CollisionShape3D.new()
	collision.name = "ExactBoxCollision"
	var shape := BoxShape3D.new()
	shape.size = hi-lo
	collision.shape = shape
	ground.add_child(collision)
	return terrain.install(ground)

func _ground_record(installed: Dictionary) -> Dictionary:
	var body: StaticBody3D = installed.ground
	var collider: CollisionShape3D = installed.shape_node
	var shape: ConcavePolygonShape3D = collider.shape
	return {"body_id":body.get_instance_id(),"body_rid":body.get_rid().get_id(),
		"shape_node_id":collider.get_instance_id(),"shape_id":shape.get_instance_id(),"shape_rid":shape.get_rid().get_id(),
		"body_transform":body.transform,"shape_transform":collider.transform,"host_transform":host.transform,
		"layer":body.collision_layer,"mask":body.collision_mask,"disabled":collider.disabled,
		"backface":shape.backface_collision,"margin":shape.margin,"faces":shape.get_faces().to_byte_array(),
		"collision_objects":host.find_children("*","CollisionObject3D",true,false).size()}

func _preserved(installed: Dictionary, before: Dictionary, label: String) -> void:
	var after: Dictionary = _ground_record(installed)
	var display: Dictionary = after.duplicate()
	display.faces_sha256 = _sha(after.faces)
	display.face_bytes = after.faces.size()
	display.erase("faces")
	_check(after == before,label,display)

func _asset_contract(source_path: String, filename: String) -> void:
	var source_scene := load(source_path) as PackedScene
	var lod_scene := load(PREFIX+filename) as PackedScene
	if not _check(source_scene != null and lod_scene != null,filename+" canonical and LOD imports exist"): return
	var source := source_scene.instantiate() as Node3D
	var lod := lod_scene.instantiate() as Node3D
	var old: Dictionary = _hierarchy(source)
	var current: Dictionary = _hierarchy(lod)
	_check(old == current,filename+" retains canonical hierarchy and all local transforms",current)
	var names: Dictionary = EXPECTED_TRIANGLES[filename]
	var meshes: Array = lod.find_children("*","MeshInstance3D",true,false)
	_check(meshes.size() == names.size(),filename+" exact mesh/surface/material contract count",meshes.size())
	for view: MeshInstance3D in meshes:
		var canonical: MeshInstance3D = source.get_node_or_null(lod.get_path_to(view))
		var name: String = str(view.name)
		var valid: bool = names.has(name) and view.mesh != null and canonical != null and canonical.mesh != null and view.mesh.get_surface_count() == 1
		if valid:
			var material := view.get_active_material(0) as BaseMaterial3D
			var original := canonical.get_active_material(0) as BaseMaterial3D
			valid = view.mesh.get_faces().size() == int(names[name])*3 and material != null and original != null
			if material != null and original != null:
				valid = valid and material.resource_name == original.resource_name and material.transparency == BaseMaterial3D.TRANSPARENCY_DISABLED and material.albedo_texture != null and material.normal_texture != null and material.roughness_texture != null and material.metallic_texture != null
		var expected: AABB = canonical.mesh.get_aabb() if canonical != null and canonical.mesh != null else AABB()
		if filename == "revetment_4m_lod.glb": expected = _expected_box("long")
		if filename == "inspection_pit_lod.glb" and name == "Hardware":
			expected = AABB(Vector3(-4.075999736785889,-2.484999895095825,-4.452000141143799),Vector3(8.151999473571777,2.4859998950269073,9.170999526977539))
		_check(valid and _same_box(view.mesh.get_aabb(),expected),filename+"/"+name+" exact new tri/opaque PBR/explicit bounds",{"triangles":view.mesh.get_faces().size()/3 if view.mesh != null else -1,"actual":view.mesh.get_aabb() if view.mesh != null else AABB(),"expected":expected})
	_check(lod.find_children("*","CollisionObject3D",true,false).is_empty(),filename+" contains no imported collision")
	source.free()
	lod.free()

func _hierarchy(model: Node3D) -> Dictionary:
	var result: Dictionary = {".":{"type":model.get_class(),"transform":model.transform}}
	for node: Node3D in model.find_children("*","Node3D",true,false):
		result[str(model.get_path_to(node))] = {"type":node.get_class(),"transform":node.transform}
	return result

func _expected_box(kind: String) -> AABB:
	var width: float = 4.0 if kind == "long" else 1.3
	var edge: float = .0008031860925257206 if kind == "long" else 0.0
	return AABB(Vector3(-width*.5,-2.8,-.35),Vector3(width,2.8,.35+edge))

func _same_box(actual: AABB, expected: AABB) -> bool:
	# Same engine float comparison as the production binders; no added tolerance.
	return actual.position.is_equal_approx(expected.position) and actual.size.is_equal_approx(expected.size)

func _sha(bytes: PackedByteArray) -> String:
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	context.update(bytes)
	return context.finish().hex_encode()

func _check(ok: bool, label: String, actual: Variant = null) -> bool:
	checks.append({"passed":ok,"label":label,"actual":actual})
	return ok

func _finish() -> void:
	if finished: return
	finished = true
	if is_instance_valid(host): host.free()
	await process_frame
	var failures: Array = checks.filter(func(row: Dictionary) -> bool: return not row.passed)
	var result: Dictionary = {"checks":checks,"failed":failures.size(),"engine_errors":logger.errors,
		"scope":"One production Waterfront/pit construction fixture. Original collision exact before/after every view, real imported LOD contracts, native readback. No MAIN, flight, actual camera, LAN or performance claim."}
	FileAccess.open(output+"/result.json",FileAccess.WRITE).store_string(JSON.stringify(result,"\t"))
	print("I2_VISUAL_LOD_RESULT "+JSON.stringify({"checks":checks.size(),"failed":failures.size(),"failures":failures,"engine_errors":logger.errors}))
	quit(0 if failures.is_empty() and logger.errors.is_empty() else 1)
