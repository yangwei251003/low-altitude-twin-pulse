extends SceneTree
## Actual Terrain + installed production west GLBs + candidate east GLBs.
## The detached Ground host is built from the production JSON box, not MAIN.
## No flight, GPU, network, complete quay or artistic acceptance is claimed.
const Terrain = preload("res://scripts/v3/world/twin_i2_waterfront_terrain.gd")
const WestArt = preload("res://scripts/v3/art/twin_i2_revetment_art.gd")
const East = preload("res://scripts/v3/art/twin_i2_east_revetment_art.gd")
var checks := 0
var failures: Array = []
var measurements: Dictionary = {}
var host: Node3D
var started := 0
var finished := false

class ErrorLogger extends Logger:
	var errors: Array = []
	func _log_error(function: String, file: String, line: int, code: String, rationale: String, _notify: bool, error_type: int, _backtraces: Array[ScriptBacktrace]) -> void:
		errors.append({"function":function,"file":file,"line":line,"code":code,"rationale":rationale,"type":error_type})

var logger := ErrorLogger.new()

func _init() -> void:
	OS.add_logger(logger)
	_run.call_deferred()

func _run() -> void:
	started = Time.get_ticks_msec()
	create_timer(20.0).timeout.connect(func() -> void:
		_check(false, "bounded candidate test timeout")
		_finish())
	var terrain := Terrain.new()
	if not _check(terrain.configure().get("ok", false), "actual production Terrain configures"):
		_finish()
		return
	var installed: Dictionary = _host_fixture(terrain)
	if not _check(installed.get("ok",false), "actual Terrain.install uses the unchanged production Ground box contract", installed):
		_finish()
		return
	var raw_before: Dictionary = _scene_record(installed)
	var no_west: Dictionary = East.install(terrain, installed)
	_check(not no_west.ok and _scene_record(installed) == raw_before, "east refuses a terrain with no installed west and changes nothing", no_west)
	var west: Dictionary = WestArt.install(terrain, installed)
	if not _check(west.get("ok",false), "real west-bank installer loads its four existing GLBs", {"code":west.get("code")}):
		_finish()
		return
	var baseline: Dictionary = _scene_record(installed)
	var source_bytes: Dictionary = _source_record(terrain)
	var current: Dictionary = {}
	for part: String in ["bank", "dry_surface"]: current[part] = _geometry(installed.meshes[part].mesh)
	var pre_install_shape: ConcavePolygonShape3D = installed.shape_node.shape
	var shape_rid: RID = pre_install_shape.get_rid()
	var west_before: Dictionary = _node_record(west.wrapper)
	_check(_coverage(current.dry_surface.faces, Vector3(12.4,0,6)) == false and _coverage(current.dry_surface.faces,Vector3(17.1,0,6)), "fixture really has a west hole and still has the east top, before candidate")
	var original_top: ArrayMesh = installed.meshes.dry_surface.mesh
	installed.meshes.dry_surface.mesh = terrain.make_mesh("dry_surface")
	_reject_unchanged(terrain, installed, "rejects resurrected original top instead of resetting the west cut")
	installed.meshes.dry_surface.mesh = original_top
	var tangent_arrays: Array = original_top.surface_get_arrays(0)
	var changed_tangents: PackedFloat32Array = tangent_arrays[Mesh.ARRAY_TANGENT]
	for at in 3: changed_tangents[at*4+3] *= -1.0
	tangent_arrays[Mesh.ARRAY_TANGENT] = changed_tangents
	var altered_tangent := ArrayMesh.new()
	altered_tangent.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,tangent_arrays)
	installed.meshes.dry_surface.mesh = altered_tangent
	_reject_unchanged(terrain,installed,"rejects changed real tangent handedness instead of discarding it")
	installed.meshes.dry_surface.mesh = original_top
	var color_arrays: Array = original_top.surface_get_arrays(0)
	var colors := PackedColorArray()
	colors.resize(current.dry_surface.faces.size())
	colors.fill(Color(.25,.5,.75,1))
	color_arrays[Mesh.ARRAY_COLOR] = colors
	var colored := ArrayMesh.new()
	colored.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,color_arrays)
	installed.meshes.dry_surface.mesh = colored
	_reject_unchanged(terrain,installed,"rejects genuine nonempty unsupported color data without dropping it")
	installed.meshes.dry_surface.mesh = original_top
	var changed_arrays: Array = original_top.surface_get_arrays(0)
	var changed_uv: PackedVector2Array = changed_arrays[Mesh.ARRAY_TEX_UV]
	changed_uv[0] += Vector2(.125,0)
	changed_arrays[Mesh.ARRAY_TEX_UV] = changed_uv
	var altered := ArrayMesh.new()
	altered.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,changed_arrays)
	installed.meshes.dry_surface.mesh = altered
	_reject_unchanged(terrain, installed, "rejects an altered current UV attribute without touching either part")
	installed.meshes.dry_surface.mesh = original_top
	installed.meshes.bank.position.x = .01
	_reject_unchanged(terrain, installed, "rejects transformed current render part atomically")
	installed.meshes.bank.position.x = 0
	var changed_shape := ConcavePolygonShape3D.new()
	var changed_faces: PackedVector3Array = pre_install_shape.get_faces()
	changed_faces[0].x += .01
	changed_shape.set_faces(changed_faces)
	installed.shape_node.shape = changed_shape
	_reject_unchanged(terrain, installed, "rejects an already changed physical Ground instead of blessing it")
	installed.shape_node.shape = pre_install_shape
	root.add_child(host)
	_reject_unchanged(terrain, installed, "live scene input rejects before replacing render resources")
	root.remove_child(host)
	_check(_scene_record(installed) == baseline, "restored negative fixtures leave the exact valid starting scene")
	var installed_east: Dictionary = East.install(terrain, installed)
	if not _check(installed_east.get("ok",false), "candidate installs from actual current west remainder after all resources validate", {"code":installed_east.get("code")}):
		_finish()
		return
	measurements = installed_east.report.duplicate(true)
	var definition: Dictionary = terrain.definition()
	var profile: Array = definition.profile
	var begin: Vector3 = profile[0]
	var end: Vector3 = profile[1]
	var span: float = end.x - begin.x
	var height: float = float(definition.top_y)-float(definition.bed_y)
	_check(absf(_area(installed_east.removed_geometry.bank.faces)-span*height)<.0002,
		"actual east removed bank area follows the configured PROFILE and depth")
	_check(absf(_area(installed_east.removed_geometry.dry_surface.faces)-span*.35)<.0002,
		"actual east removed top area follows the configured PROFILE and imported 350mm thickness")
	for part: String in ["bank","dry_surface"]:
		_audit_partition(part,current[part],installed_east.geometry[part],installed_east.removed_geometry[part])
		var actual: Dictionary = _geometry(installed.meshes[part].mesh)
		_check(actual.faces.to_byte_array() == installed_east.geometry[part].faces.to_byte_array() and actual.uv == installed_east.geometry[part].uv,
			part + " actual assigned ArrayMesh has the measured positions and metric UV")
		var stored_tangents_ok: bool = actual.tangents.size() == installed_east.geometry[part].tangents.size()
		var max_tangent_error := 0.0
		if stored_tangents_ok:
			for at in actual.tangents.size():
				max_tangent_error = maxf(max_tangent_error,absf(actual.tangents[at]-installed_east.geometry[part].tangents[at]))
				if at%4==3: stored_tangents_ok = stored_tangents_ok and actual.tangents[at]==installed_east.geometry[part].tangents[at]
		_check(stored_tangents_ok and max_tangent_error<.0001,part+" actual ArrayMesh preserves tangent frames through engine packing, with exact handedness",{"max_component_error":max_tangent_error})
		_check(absf(float(measurements.parts[part].source_area_m2)-_area(current[part].faces))<.000001,
			part + " report starts at visible west remainder, not original uncut terrain")
	var top: PackedVector3Array = installed_east.geometry.dry_surface.faces
	var coverage_ok := true
	for x: float in [12.249,12.4,12.601,16.899,16.901,17.1,17.249,17.251]:
		for z: float in [2.299,2.301,6.3,10.3,14.3,15.599,15.601]:
			var at := Vector3(x,0,z)
			var in_east: bool = x>16.9 and x<17.25 and z>2.3 and z<15.6
			coverage_ok = coverage_ok and _coverage(top,at) == (_coverage(current.dry_surface.faces,at) and not in_east)
	_check(coverage_ok,"56 edge-adjacent top probes keep west absent, remove only east interior and retain surrounding ground")
	_check(_node_record(west.wrapper) == west_before,"every west node, local pose, imported mesh and material remains unchanged")
	var after: Dictionary = _scene_record(installed)
	var other_parts_unchanged := true
	for part: String in installed.meshes:
		if part in ["bank","dry_surface"]: continue
		other_parts_unchanged = other_parts_unchanged and baseline.parts[part] == after.parts[part]
	_check(other_parts_unchanged,"water, bed, outer boundary and underside keep exact resources, attributes and materials")
	_check(installed.shape_node.shape == pre_install_shape and pre_install_shape.get_rid() == shape_rid and baseline.ground == after.ground,
		"original Ground/body RID, collider/shape RID, poses/layers and collision bytes are identical")
	_check(_source_record(terrain) == source_bytes,"all seven immutable Terrain geometries and original collision data remain identical")
	_check(installed_east.parts.size()==4 and installed_east.triangles==16628 and installed_east.material_count==2,
		"three real 5152-triangle long imports plus one 1172-triangle short import, with two static source materials")
	var widths: Array = []
	var previous_end := 2.3
	var all_models_ok := true
	for record: Dictionary in installed_east.parts:
		var model: Node3D = record.model
		var mesh: MeshInstance3D = record.mesh
		var bounds: AABB = model.transform * mesh.get_aabb()
		var material := mesh.get_active_material(0) as BaseMaterial3D
		all_models_ok = all_models_ok and model.scene_file_path == str(record.path) and model.basis.is_equal_approx(Basis(Vector3.UP,-PI*.5))
		all_models_ok = all_models_ok and absf(bounds.position.x-16.9)<.00001 and absf(bounds.end.x-17.25)<.00001 and absf(bounds.position.y+2.8)<.00001 and absf(bounds.end.y)<.00001
		all_models_ok = all_models_ok and absf(bounds.position.z-previous_end)<.00001 and material != null and material.transparency==BaseMaterial3D.TRANSPARENCY_DISABLED
		if material != null: all_models_ok = all_models_ok and material.albedo_texture!=null and material.normal_texture!=null and material.roughness_texture!=null and material.metallic_texture!=null
		previous_end = bounds.end.z
		widths.append(bounds.size.z)
	_check(all_models_ok and absf(previous_end-15.6)<.00001,"actual rigidly rotated imports form one landward 13.3m span with no nominal gap/overlap and opaque imported PBR",{"widths":widths})
	_check(installed_east.wrapper.find_children("*","CollisionObject3D",true,false).is_empty(),"east appearance adds no physical obstacle or replacement collider")
	var committed: Dictionary = _scene_record(installed)
	var duplicate: Dictionary = East.install(terrain, installed)
	_check(not duplicate.ok and duplicate.code=="already_installed" and _scene_record(installed)==committed,"re-entry rejects without extra nodes, cuts or resource replacement",duplicate)
	installed_east.report.parts.bank.removed_area_m2=-1
	_check(absf(float(measurements.parts.bank.removed_area_m2)-_area(installed_east.removed_geometry.bank.faces))<.000001,
		"captured measurement is detached from caller report mutation and retains actual bank area")
	_finish()

func _host_fixture(terrain: Terrain) -> Dictionary:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/v3/terrain/i2_clinic_layout.json"))
	if not parsed is Dictionary: return {"ok":false,"code":"source_layout"}
	var spec: Dictionary = {}
	for item: Dictionary in parsed.fixed_solids:
		if item.id=="Ground": spec=item
	if spec.is_empty(): return {"ok":false,"code":"source_ground"}
	var lo := Vector3(float(spec.min[0]),float(spec.min[1]),float(spec.min[2]))
	var hi := Vector3(float(spec.max[0]),float(spec.max[1]),float(spec.max[2]))
	host=Node3D.new()
	var ground := StaticBody3D.new()
	ground.name="Ground"
	ground.collision_layer=1
	ground.collision_mask=0
	ground.position=(lo+hi)*.5
	host.add_child(ground)
	var visual := MeshInstance3D.new()
	visual.name="Visual"
	var box := BoxMesh.new()
	box.size=hi-lo
	visual.mesh=box
	var material := StandardMaterial3D.new()
	material.albedo_color=Color(str(spec.color))
	visual.material_override=material
	ground.add_child(visual)
	var collision := CollisionShape3D.new()
	collision.name="ExactBoxCollision"
	var shape := BoxShape3D.new()
	shape.size=hi-lo
	collision.shape=shape
	ground.add_child(collision)
	return terrain.install(ground)

func _reject_unchanged(terrain: Terrain, installed: Dictionary, label: String) -> void:
	var before: Dictionary = _scene_record(installed)
	var response: Dictionary = East.install(terrain,installed)
	_check(not response.ok and _scene_record(installed)==before,label,response)

func _audit_partition(part: String, before: Dictionary, kept: Dictionary, removed: Dictionary) -> void:
	var attributes := true
	var untouched := true
	var winding := true
	var tangent_frames := true
	var retained_in_cut := 0.0
	var removed_outside := 0.0
	var balances: Dictionary = {}
	var fragments: Dictionary = {}
	for category: String in ["kept","removed"]:
		var data: Dictionary = kept if category=="kept" else removed
		var faces: PackedVector3Array = data.faces
		for first in range(0,faces.size(),3):
			var original: int = int(data.source_triangles[first/3]) * 3
			var a: Vector3=before.faces[original]
			var b: Vector3=before.faces[original+1]
			var c: Vector3=before.faces[original+2]
			var normal: Vector3=before.normals[original]
			# Surface normals are octahedrally packed by Godot. Coplanarity is a
			# geometric property, so derive its plane from real source positions.
			var plane_normal: Vector3=(b-a).cross(c-a).normalized()
			var triangle := PackedVector3Array([faces[first],faces[first+1],faces[first+2]])
			var cross: Vector3=(triangle[1]-triangle[0]).cross(triangle[2]-triangle[0])
			winding=winding and cross.length_squared()>1e-14 and cross.dot(normal)<0
			for offset in 3:
				var index: int=first+offset
				var weights: Vector3=_barycentric(faces[index],a,b,c)
				var uv: Vector2=before.uv[original]*weights.x+before.uv[original+1]*weights.y+before.uv[original+2]*weights.z
				attributes=attributes and weights.x>=-.00001 and weights.y>=-.00001 and weights.z>=-.00001 and absf((faces[index]-a).dot(plane_normal))<.00001
				attributes=attributes and data.normals[index]==normal and data.uv[index].distance_to(uv)<.00001
				for component in 4: tangent_frames = tangent_frames and data.tangents[index*4+component]==before.tangents[original*4+component]
			var triangle_area: float=_area(triangle)
			balances[original]=float(balances.get(original,0.0))+triangle_area
			if not fragments.has(original): fragments[original]=[]
			fragments[original].append(triangle)
			var overlap: float=_east_overlap(triangle,part)
			if category=="kept": retained_in_cut+=overlap
			else: removed_outside+=maxf(triangle_area-overlap,0.0)
	var balanced := true
	var pair_overlap := 0.0
	for first in range(0,before.faces.size(),3):
		var original := PackedVector3Array([before.faces[first],before.faces[first+1],before.faces[first+2]])
		balanced=balanced and absf(float(balances.get(first,0.0))-_area(original))<.0002
		var pieces: Array=fragments.get(first,[])
		if _east_overlap(original,part)<1e-9:
			untouched=untouched and pieces.size()==1 and pieces[0].to_byte_array()==original.to_byte_array()
		for left in pieces.size():
			for right in range(left+1,pieces.size()): pair_overlap=maxf(pair_overlap,_overlap(pieces[left],pieces[right],before.normals[first]))
	_check(attributes and winding,part+" vertices preserve source-triangle metric UV/normals, finite geometry and Godot clockwise winding")
	_check(tangent_frames,part+" every retained and removed corner preserves its real source triangle tangent exactly")
	_check(balanced and pair_overlap<.00005 and absf(_area(before.faces)-_area(kept.faces)-_area(removed.faces))<.0002,
		part+" independent per-triangle conservation rejects lost/overlapping fragments",{"maximum_overlap_m2":pair_overlap})
	_check(untouched,part+" every triangle outside positive east intersection remains byte-identical, including west cut edges and corners")
	_check(retained_in_cut<.00005 and removed_outside<.00005,part+" independent polygon intersections find no kept east interior or removal beyond east footprint",
		{"kept_inside_m2":retained_in_cut,"removed_outside_m2":removed_outside})

static func _east_overlap(triangle: PackedVector3Array, part: String) -> float:
	if part=="bank":
		for point: Vector3 in triangle:
			if absf(point.x-16.9)>.00001: return 0.0
	var polygon := PackedVector2Array()
	for point: Vector3 in triangle: polygon.append(Vector2(point.y,point.z) if part=="bank" else Vector2(point.x,point.z))
	var lo: float=-2.8 if part=="bank" else 16.9
	var hi: float=0 if part=="bank" else 17.25
	var clip := PackedVector2Array([Vector2(lo,2.3),Vector2(hi,2.3),Vector2(hi,15.6),Vector2(lo,15.6)])
	var area := 0.0
	for region: PackedVector2Array in Geometry2D.intersect_polygons(polygon,clip): area+=_area2(region)
	return area

static func _overlap(a: PackedVector3Array,b: PackedVector3Array,normal: Vector3) -> float:
	var axis: int=normal.abs().max_axis_index()
	var pa := PackedVector2Array()
	var pb := PackedVector2Array()
	for p: Vector3 in a: pa.append(_project(p,axis))
	for p: Vector3 in b: pb.append(_project(p,axis))
	var area := 0.0
	for region: PackedVector2Array in Geometry2D.intersect_polygons(pa,pb): area+=_area2(region)
	return area/absf(normal[axis])

static func _coverage(faces: PackedVector3Array,point: Vector3) -> bool:
	for first in range(0,faces.size(),3):
		var weights: Vector3=_barycentric(point,faces[first],faces[first+1],faces[first+2])
		if weights.x>=-.0000001 and weights.y>=-.0000001 and weights.z>=-.0000001: return true
	return false

static func _barycentric(point: Vector3,a: Vector3,b: Vector3,c: Vector3) -> Vector3:
	var axis: int=(b-a).cross(c-a).abs().max_axis_index()
	var pa: Vector2=_project(a,axis)
	var pb: Vector2=_project(b,axis)
	var pc: Vector2=_project(c,axis)
	var pp: Vector2=_project(point,axis)
	var denominator: float=(pb.x-pa.x)*(pc.y-pa.y)-(pc.x-pa.x)*(pb.y-pa.y)
	var v: float=((pp.x-pa.x)*(pc.y-pa.y)-(pc.x-pa.x)*(pp.y-pa.y))/denominator
	var w: float=((pb.x-pa.x)*(pp.y-pa.y)-(pp.x-pa.x)*(pb.y-pa.y))/denominator
	return Vector3(1-v-w,v,w)

static func _project(point: Vector3,axis: int) -> Vector2:
	if axis==0: return Vector2(point.y,point.z)
	if axis==1: return Vector2(point.x,point.z)
	return Vector2(point.x,point.y)

static func _area(faces: PackedVector3Array) -> float:
	var area := 0.0
	for first in range(0,faces.size(),3): area+=(faces[first+1]-faces[first]).cross(faces[first+2]-faces[first]).length()*.5
	return area

static func _area2(points: PackedVector2Array) -> float:
	var area := 0.0
	for at in points.size(): area+=points[at].cross(points[(at+1)%points.size()])
	return absf(area)*.5

static func _geometry(mesh: Mesh) -> Dictionary:
	var arrays: Array=mesh.surface_get_arrays(0)
	return {"faces":arrays[Mesh.ARRAY_VERTEX],"normals":arrays[Mesh.ARRAY_NORMAL],"tangents":arrays[Mesh.ARRAY_TANGENT],"uv":arrays[Mesh.ARRAY_TEX_UV]}

static func _source_record(terrain: Terrain) -> Dictionary:
	var data: Dictionary={"collision":terrain.collision_faces().to_byte_array(),"definition":var_to_bytes(terrain.definition())}
	for part: String in terrain.part_ids(): data[part]=var_to_bytes(terrain.geometry(part))
	return data

static func _scene_record(installed: Dictionary) -> Dictionary:
	var parent: Node3D=installed.wrapper
	var ground: StaticBody3D=installed.ground
	var collider: CollisionShape3D=installed.shape_node
	var physical_shape := collider.shape as ConcavePolygonShape3D
	var ids: Array=[]
	for child: Node in parent.get_children(): ids.append(child.get_instance_id())
	var parts: Dictionary={}
	for id: String in installed.meshes:
		var mesh: MeshInstance3D=installed.meshes[id]
		parts[id]={"id":mesh.get_instance_id(),"mesh":mesh.mesh.get_instance_id(),"pose":mesh.transform,
			"arrays":var_to_bytes(mesh.mesh.surface_get_arrays(0)),"material":mesh.get_active_material(0).get_instance_id(),"visible":mesh.visible}
	return {"children":ids,"parts":parts,"ground":{"id":ground.get_instance_id(),"rid":ground.get_rid(),"pose":ground.transform,"layer":ground.collision_layer,"mask":ground.collision_mask,
		"collider":collider.get_instance_id(),"collision_pose":collider.transform,"shape":physical_shape.get_instance_id(),"shape_rid":physical_shape.get_rid(),"faces":physical_shape.get_faces().to_byte_array()}}

static func _node_record(node: Node) -> Dictionary:
	var data: Dictionary={"id":node.get_instance_id(),"children":[]}
	if node is Node3D: data.pose=node.transform
	if node is MeshInstance3D:
		var mat: BaseMaterial3D=node.get_active_material(0)
		data.mesh=node.mesh.get_instance_id()
		data.faces=node.mesh.get_faces().to_byte_array()
		data.material={"id":mat.get_instance_id(),"color":mat.albedo_color,"roughness":mat.roughness,"metallic":mat.metallic,"transparency":mat.transparency}
	for child: Node in node.get_children(): data.children.append(_node_record(child))
	return data

func _check(ok: bool,label: String,details: Dictionary={}) -> bool:
	checks+=1
	if not ok:
		failures.append({"check":label,"details":details})
		print("EAST_STRAIGHT_BANK_FAIL "+label+" "+JSON.stringify(details))
	return ok

func _finish() -> void:
	if finished: return
	finished=true
	if is_instance_valid(host): host.free()
	print("V3_EAST_STRAIGHT_BANK_TESTS "+JSON.stringify({"checks":checks,"failures":failures,"engine_errors":logger.errors,"elapsed_ms":Time.get_ticks_msec()-started,
		"geometry":measurements,"scope":"detached actual Terrain/west/east imports; immutable collision bytes; no MAIN/GPU/flight/network/art proof"}))
	OS.remove_logger(logger)
	quit(0 if failures.is_empty() and logger.errors.is_empty() else 1)
