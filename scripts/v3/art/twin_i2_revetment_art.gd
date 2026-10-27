class_name TwinI2RevetmentArt
extends RefCounted
## Authored west-bank presentation. Ground identity and physical faces stay intact.
const Partition = preload("res://scripts/v3/art/twin_i2_revetment_partition.gd")
const SOURCE_MODELS := {
	"long":"res://assets/v3/i2_canal_revetment/i2_canal_revetment_4m.glb",
	"short":"res://assets/v3/i2_canal_revetment/i2_canal_revetment_1p3.glb"}
const MODELS := {
	"long":"res://assets/v3/environment/i2_visual_lod/20261021_021300_adedde/revetment_4m_lod.glb",
	"short":"res://assets/v3/environment/i2_visual_lod/20261021_021300_adedde/revetment_1p3_lod.glb"}
const TRIANGLES := {"long":1804,"short":411}

static func visual_bounds(kind: String) -> AABB:
	var width := 4.0 if kind == "long" else 1.3
	# Exact delivered visual extent; original Ground/partition remains unchanged.
	var edge := 0.0008031860925257206 if kind == "long" else 0.0
	return AABB(Vector3(-width*.5,-2.8,-.35),Vector3(width,2.8,.35+edge))
const PLACEMENTS := [
	["WestBankA","long",Vector3(12.6,0,4.3)],
	["WestBankB","long",Vector3(12.6,0,8.3)],
	["WestBankC","long",Vector3(12.6,0,12.3)],
	["WestBankD","short",Vector3(12.6,0,14.95)]]

static func install(terrain: RefCounted, installed: Dictionary) -> Dictionary:
	if terrain == null or not installed.get("ok",false): return _failure("terrain_required")
	var parent: Node3D = installed.get("wrapper")
	var ground: StaticBody3D = installed.get("ground")
	var collider: CollisionShape3D = installed.get("shape_node")
	if not is_instance_valid(parent) or parent.is_inside_tree() or parent.has_node("AuthoredWestBank"):
		return _failure("detached_terrain_once")
	if not is_instance_valid(ground) or not is_instance_valid(collider) or not collider.shape is ConcavePolygonShape3D:
		return _failure("existing_ground_required")
	var partition := Partition.new()
	var result: Dictionary = partition.configure(terrain)
	if not result.ok: return _failure("partition:"+str(result.code))
	for part: String in Partition.PARTS:
		var old: MeshInstance3D = installed.meshes.get(part)
		if old == null or old.mesh == null or old.get_parent() != parent or not old.transform.is_equal_approx(Transform3D.IDENTITY):
			return _failure("original_visual:"+part)
	var wrapper := Node3D.new()
	wrapper.name = "AuthoredWestBank"
	var packed: Dictionary = {}
	for id: String in MODELS:
		packed[id] = load(MODELS[id]) as PackedScene
		if packed[id] == null: return _reject(wrapper,"missing_glb:"+id)
	var records: Array = []
	var triangles := 0
	var material_ids: Dictionary = {}
	for spec: Array in PLACEMENTS:
		var model := packed[spec[1]].instantiate() as Node3D
		if model == null: return _reject(wrapper,"model_root")
		wrapper.add_child(model)
		var meshes := model.find_children("*","MeshInstance3D",true,false)
		if meshes.size() != 1: return _reject(wrapper,"one_mesh_required")
		for kind: String in ["CollisionObject3D","Camera3D","Light3D","AnimationPlayer"]:
			if not model.find_children("*",kind,true,false).is_empty(): return _reject(wrapper,"unexpected_node:"+kind)
		var mesh: MeshInstance3D = meshes[0]
		if str(mesh.name) != "RevetmentSurface" or mesh.mesh == null or mesh.mesh.get_surface_count() != 1:
			return _reject(wrapper,"surface_contract")
		var ancestor: Node = mesh
		while ancestor != wrapper:
			if ancestor is Node3D and not ancestor.transform.is_equal_approx(Transform3D.IDENTITY): return _reject(wrapper,"authored_identity")
			ancestor = ancestor.get_parent()
		var width := 4.0 if spec[1] == "long" else 1.3
		var expected := visual_bounds(str(spec[1]))
		var bounds: AABB = mesh.mesh.get_aabb()
		if not bounds.position.is_equal_approx(expected.position) or not bounds.size.is_equal_approx(expected.size):
			return _reject(wrapper,"model_dimensions:"+str(spec[1]))
		var faces := mesh.mesh.get_faces()
		if faces.size() != int(TRIANGLES[spec[1]])*3: return _reject(wrapper,"model_geometry")
		for point: Vector3 in faces:
			if not point.is_finite() or not expected.grow(.00001).has_point(point): return _reject(wrapper,"model_envelope")
		var material := mesh.get_active_material(0) as BaseMaterial3D
		if material == null or material.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED or material.albedo_texture == null or material.roughness_texture == null or material.metallic_texture == null or material.normal_texture == null:
			return _reject(wrapper,"opaque_pbr_required")
		material_ids[material.get_instance_id()] = true
		model.name = spec[0]
		model.transform = Transform3D(Basis(Vector3.UP,PI*.5),spec[2])
		mesh.set_meta("terrain_visibility_single_sided",true)
		triangles += int(faces.size()/3)
		records.append({"id":spec[0],"path":MODELS[spec[1]],"model":model,"mesh":mesh,"width":width,"triangles":faces.size()/3})
	# All resources validated. Swap the two visible remainders atomically, keeping
	# their material/identity and every original physical object and shape.
	for part: String in Partition.PARTS: installed.meshes[part].mesh = result.meshes[part]
	parent.add_child(wrapper)
	parent.set_meta("terrain_stage","authored_west_bank_remaining_graybox")
	return {"ok":true,"code":"west_bank_installed","wrapper":wrapper,"parts":records,
		"partition":partition,"summary":partition.summary(),"triangles":triangles,
		"material_count":material_ids.size(),"ground":ground,"shape":collider.shape,
		"paths":MODELS.values(),"collision_policy":"original Ground RID and exact concave faces unchanged"}

static func _failure(code: String) -> Dictionary:
	return {"ok":false,"code":code}

static func _reject(node: Node, code: String) -> Dictionary:
	node.free()
	return _failure(code)
