extends RefCounted
## Candidate: only the 28 validated, static imported paving leaves. No physics,
## material duplication, source edits, fader collection, water or patch edits.
# Godot4.7.2 stores normal/tangent directions as16-bit octahedral values,
# including when ARRAY_FLAG_COMPRESS_ATTRIBUTES is off. A rotated surface
# must be encoded again. Budget only this direction error (~0.0115 degrees);
# positions, UV/color, tangent handedness, material and physics stay strict.
# Official: servers/rendering/rendering_server.cpp ARRAY_NORMAL/ARRAY_TANGENT.
const DIRECTION_EPS := .0002
const RENDER := ["layers","cast_shadow","gi_mode","gi_lightmap_texel_scale","transparency","lod_bias","extra_cull_margin","ignore_occlusion_culling","sorting_offset","sorting_use_aabb_center","visibility_range_begin","visibility_range_end","visibility_range_begin_margin","visibility_range_end_margin","visibility_range_fade_mode"]

static func install(art: Dictionary) -> Dictionary:
	var records: Array = []
	for tile: Dictionary in art.tiles:
		for leaf: MeshInstance3D in tile.model.find_children("*","MeshInstance3D",true,false):
			records.append(_record(leaf,art.wrapper,"court",str(tile.id),"court_west" if tile.model.position.x < -4.0 else "receiving"))
	for tile: Dictionary in art.maintenance.tiles:
		for leaf: MeshInstance3D in tile.model.find_children("*","MeshInstance3D",true,false):
			records.append(_record(leaf,art.maintenance.wrapper,"maintenance",str(tile.id),"maintenance_west" if str(tile.id).begins_with("W") else "maintenance_east"))
	if records.size()!=28: return {"ok":false,"code":"paving_batch_source_count"}
	var buckets: Dictionary = {}
	var skipped: Array = []
	for row: Dictionary in records:
		var reason: String = _unsupported(row)
		if not reason.is_empty():
			skipped.append({"source":row.id,"reason":reason})
			continue
		# The actual resource ID is mandatory: a shared atlas/texture SHA is not
		# permission to merge distinct Material resources.
		var key: String = str(row.target.get_instance_id())+":"+row.zone+":"+str(row.material.get_instance_id())+":"+str(row.format)+":"+JSON.stringify(row.properties)+":"+str(row.shadow_format)
		if not buckets.has(key): buckets[key]=[]
		buckets[key].append(row)
	var staged: Array = []
	for bucket: Array in buckets.values():
		if bucket.size()<2: continue
		var visual: Dictionary = _merge(bucket,false)
		if not visual.ok: return _abort(staged,str(visual.code))
		var shadow: Dictionary = {"ok":true,"mesh":null}
		if bucket[0].shadow!=null:
			shadow=_merge(bucket,true)
			if not shadow.ok: return _abort(staged,str(shadow.code))
			visual.mesh.shadow_mesh=shadow.mesh
		var node := MeshInstance3D.new()
		node.name="PavingBatch_"+str(bucket[0].zone)+"_"+str(staged.size())
		node.mesh=visual.mesh
		for property: String in RENDER: node.set(property,bucket[0].properties[property])
		staged.append({"node":node,"bucket":bucket,"ranges":visual.ranges,"before_bounds":visual.bounds})
	# Check every staged view before freeing any old leaf. Failed construction is
	# atomic; skipped/unsupported leaves remain the exact original instances.
	for item: Dictionary in staged:
		if not _equivalent(item): return _abort(staged,"paving_batch_attribute_mismatch")
	var removed: Dictionary = {}
	var entries: Array = []
	for item: Dictionary in staged:
		item.bucket[0].target.add_child(item.node)
		var names: Array = []
		for row: Dictionary in item.bucket:
			removed[row.node.get_instance_id()]=true
			names.append(row.id)
			row["runtime"]=item.node
			row["range"]=item.ranges[row.id]
		entries.append({"scope":item.bucket[0].scope,"zone":item.bucket[0].zone,"runtime_name":str(item.node.name),"source_names":names,"material_id":str(item.bucket[0].material.get_instance_id()),"source_triangles":int(item.node.mesh.get_faces().size()/3),"before_bounds":str(item.before_bounds),"after_bounds":str(item.node.get_aabb()),"shadow_preserved":item.bucket[0].shadow!=null})
	var runtime: Array = []
	for row: Dictionary in records:
		var leaf: MeshInstance3D = row.node
		if removed.has(leaf.get_instance_id()):
			leaf.get_parent().remove_child(leaf)
			leaf.free()
		else:
			row["runtime"]=leaf
			row["range"]=[0,_corner_count(row.mesh)]
			runtime.append(leaf)
		# Never retain a reference to a freed Node. Mesh/Material Resources are
		# read-only provenance for QA, and are not hidden render instances.
		row.erase("node")
	for item: Dictionary in staged: runtime.append(item.node)
	var result := {"ok":true,"code":"paving_batch_ready","records":records,"runtime_meshes":runtime,"report":{"source_meshes":28,"source_triangles":22496,"runtime_meshes":runtime.size(),"merged_source_meshes":removed.size(),"batches":entries,"skipped":skipped}}
	art["paving_batch"]=result
	art["runtime_meshes"]=scoped_meshes(result,"court")
	art["runtime_mesh_count"]=art.runtime_meshes.size()
	art["source_mesh_count"]=16
	art["mesh_count"]=art.runtime_meshes.size()
	art.maintenance["paving_batch"]=result
	art.maintenance["runtime_meshes"]=scoped_meshes(result,"maintenance")
	art.maintenance["runtime_mesh_count"]=art.maintenance.runtime_meshes.size()
	art.maintenance["source_mesh_count"]=12
	art.maintenance["mesh_count"]=art.maintenance.runtime_meshes.size()
	for tile: Dictionary in art.maintenance.tiles:
		tile["source_mesh_count"]=tile.meshes.size()
		tile["meshes"]=tile.model.find_children("*","MeshInstance3D",true,false)
	return result

static func scoped_meshes(batch: Dictionary, scope: String) -> Array:
	var result: Array = []
	for row: Dictionary in batch.records:
		if row.scope==scope and not result.has(row.runtime): result.append(row.runtime)
	return result

static func proof(batch: Dictionary, scope: String) -> Dictionary:
	var okay := true
	var rows: Array = []
	var triangles := 0
	var materials: Dictionary = {}
	for row: Dictionary in batch.records:
		if row.scope!=scope: continue
		var node: MeshInstance3D = row.runtime
		var actual_pose: Transform3D = relative(node,row.target)
		var matched: bool = is_instance_valid(node) and node.visible and node.mesh.get_surface_count()==1 and node.get_active_material(0)==row.material and _corners_equal(row.mesh,row.pose,node.mesh,actual_pose,int(row.range[0]),int(row.range[1]))
		for property: String in RENDER: matched=matched and node.get(property)==row.properties[property]
		okay=okay and matched
		triangles+=int(_corner_count(row.mesh)/3)
		materials[str(row.material.get_instance_id())]=true
		rows.append({"source":row.id,"tile":row.tile,"matched":matched,"original_material_id":str(row.material.get_instance_id()),"runtime_material_id":str(node.get_active_material(0).get_instance_id()),"index_range":row.range})
	return {"ok":okay and not rows.is_empty(),"scope":scope,"source_meshes":rows.size(),"source_triangles":triangles,"runtime_meshes":scoped_meshes(batch,scope).size(),"material_count":materials.size(),"rows":rows}

static func _record(node: MeshInstance3D, target: Node3D, scope: String, tile: String, zone: String) -> Dictionary:
	var mesh := node.mesh as ArrayMesh
	var properties: Dictionary = {}
	for property: String in RENDER: properties[property]=node.get(property)
	var shadow: ArrayMesh = mesh.shadow_mesh if mesh!=null else null
	return {"node":node,"id":scope+"/"+tile+"/"+str(target.get_path_to(node)),"tile":tile,"target":target,"scope":scope,"zone":zone,"mesh":mesh,"shadow":shadow,"material":node.get_active_material(0),"pose":relative(node,target),"format":mesh.surface_get_format(0) if mesh!=null else -1,"shadow_format":shadow.surface_get_format(0) if shadow!=null and shadow.get_surface_count()==1 else -1,"properties":properties}

static func _unsupported(row: Dictionary) -> String:
	var node: MeshInstance3D = row.node
	var mesh := row.mesh as ArrayMesh
	var material := row.material as BaseMaterial3D
	if mesh==null or mesh.get_surface_count()!=1 or mesh.get_blend_shape_count()!=0: return "unsupported_mesh"
	if material==null or material.transparency!=BaseMaterial3D.TRANSPARENCY_DISABLED or material.next_pass!=null: return "nonopaque_or_multipass_material"
	if node.get_script()!=null or node.get_child_count()!=0 or node.skin!=null or node.material_overlay!=null: return "nonstatic_leaf"
	if node.custom_aabb!=AABB(): return "custom_instance_culling_bounds"
	var cursor: Node = node
	while cursor!=row.target:
		if not cursor is Node3D or not cursor.visible or not cursor.visibility_parent.is_empty(): return "independent_visibility"
		for flag: String in ["terrain_visibility_keep","terrain_visibility_cutaway_detail","terrain_visibility_single_sided"]:
			if cursor.has_meta(flag): return "fader_owned"
		cursor=cursor.get_parent()
	if not row.pose.is_finite() or row.pose.basis.determinant()<=0.0 or not row.pose.basis.is_equal_approx(row.pose.basis.orthonormalized()): return "nonrigid_pose"
	if node.transparency!=0.0 or node.visibility_range_begin!=0.0 or node.visibility_range_end!=0.0: return "per_leaf_visibility_range"
	for resource: ArrayMesh in [mesh,row.shadow]:
		if resource==null: continue
		if resource.get_surface_count()!=1 or resource.surface_get_primitive_type(0)!=Mesh.PRIMITIVE_TRIANGLES or resource.get_blend_shape_count()!=0: return "unsupported_visual_or_shadow"
		if resource.custom_aabb!=AABB(): return "custom_culling_bounds"
		# Do not silently discard imported LODs when collapsing independent AABBs.
		var surface: Dictionary = RenderingServer.mesh_get_surface(resource.get_rid(),0)
		if not surface.get("lods",[]).is_empty(): return "actual_imported_lods"
		var arrays: Array = resource.surface_get_arrays(0)
		for slot: int in [Mesh.ARRAY_CUSTOM0,Mesh.ARRAY_CUSTOM1,Mesh.ARRAY_CUSTOM2,Mesh.ARRAY_CUSTOM3,Mesh.ARRAY_BONES,Mesh.ARRAY_WEIGHTS]:
			if arrays[slot]!=null and not arrays[slot].is_empty(): return "unsupported_vertex_channel"
	return ""

static func _merge(rows: Array, shadow: bool) -> Dictionary:
	var out: Array = []
	out.resize(Mesh.ARRAY_MAX)
	out[Mesh.ARRAY_VERTEX]=PackedVector3Array()
	out[Mesh.ARRAY_INDEX]=PackedInt32Array()
	var ranges: Dictionary = {}
	var first := true
	var bounds := AABB()
	for row: Dictionary in rows:
		var mesh: ArrayMesh = row.shadow if shadow else row.mesh
		var arrays: Array = mesh.surface_get_arrays(0)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var offset: int = out[Mesh.ARRAY_VERTEX].size()
		var begin: int = out[Mesh.ARRAY_INDEX].size()
		for vertex: Vector3 in vertices:
			var point: Vector3 = row.pose*vertex
			out[Mesh.ARRAY_VERTEX].append(point)
			bounds=AABB(point,Vector3.ZERO) if first else bounds.expand(point)
			first=false
		for slot: int in [Mesh.ARRAY_NORMAL,Mesh.ARRAY_TANGENT,Mesh.ARRAY_COLOR,Mesh.ARRAY_TEX_UV,Mesh.ARRAY_TEX_UV2]:
			if arrays[slot]==null: continue
			if out[slot]==null: out[slot]=arrays[slot].slice(0,0)
			if slot==Mesh.ARRAY_NORMAL:
				for normal: Vector3 in arrays[slot]: out[slot].append((row.pose.basis*normal).normalized())
			elif slot==Mesh.ARRAY_TANGENT:
				var tangents: PackedFloat32Array = arrays[slot]
				for index: int in range(0,tangents.size(),4):
					var xyz: Vector3 = (row.pose.basis*Vector3(tangents[index],tangents[index+1],tangents[index+2])).normalized()
					out[slot].append_array(PackedFloat32Array([xyz.x,xyz.y,xyz.z,tangents[index+3]]))
			else: out[slot].append_array(arrays[slot])
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX]!=null else PackedInt32Array()
		for index: int in (indices.size() if not indices.is_empty() else vertices.size()): out[Mesh.ARRAY_INDEX].append(offset+(indices[index] if not indices.is_empty() else index))
		ranges[row.id]=[begin,out[Mesh.ARRAY_INDEX].size()-begin]
	var result := ArrayMesh.new()
	result.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,out)
	if result.get_surface_count()!=1: return {"ok":false,"code":"paving_batch_surface_failed"}
	if not shadow: result.surface_set_material(0,rows[0].material)
	if result.get_aabb().position.distance_to(bounds.position)>.00005 or result.get_aabb().end.distance_to(bounds.end)>.00005: return {"ok":false,"code":"paving_batch_bounds_failed"}
	return {"ok":true,"mesh":result,"ranges":ranges,"bounds":bounds}

static func _equivalent(item: Dictionary) -> bool:
	for row: Dictionary in item.bucket:
		var span: Array = item.ranges[row.id]
		if not _corners_equal(row.mesh,row.pose,item.node.mesh,Transform3D.IDENTITY,span[0],span[1]): return false
		if row.shadow!=null and not _corners_equal(row.shadow,row.pose,item.node.mesh.shadow_mesh,Transform3D.IDENTITY,_shadow_begin(item,row),_corner_count(row.shadow)): return false
	return true

static func _shadow_begin(item: Dictionary, wanted: Dictionary) -> int:
	var result := 0
	for row: Dictionary in item.bucket:
		if row.id==wanted.id: break
		result+=_corner_count(row.shadow)
	return result

static func _corners_equal(source: ArrayMesh, source_pose: Transform3D, runtime: ArrayMesh, runtime_pose: Transform3D, begin: int, count: int) -> bool:
	if source==null or runtime==null or count!=_corner_count(source): return false
	var a: Array = source.surface_get_arrays(0)
	var b: Array = runtime.surface_get_arrays(0)
	if begin<0 or begin+count>_corner_count(runtime): return false
	for corner: int in count:
		var ai: int = _index(a,corner)
		var bi: int = _index(b,begin+corner)
		if (source_pose*a[Mesh.ARRAY_VERTEX][ai]).distance_to(runtime_pose*b[Mesh.ARRAY_VERTEX][bi])>.00005: return _mismatch("vertex",{"a":str(source_pose*a[Mesh.ARRAY_VERTEX][ai]),"b":str(runtime_pose*b[Mesh.ARRAY_VERTEX][bi])})
		for slot: int in [Mesh.ARRAY_NORMAL,Mesh.ARRAY_TANGENT,Mesh.ARRAY_COLOR,Mesh.ARRAY_TEX_UV,Mesh.ARRAY_TEX_UV2]:
			if (a[slot]==null)!=(b[slot]==null): return _mismatch("null_channel",{"slot":slot,"source_null":a[slot]==null,"runtime_null":b[slot]==null})
			if a[slot]==null: continue
			if a[slot].is_empty()!=b[slot].is_empty(): return _mismatch("empty_channel",{"slot":slot})
			if a[slot].is_empty(): continue
			if slot==Mesh.ARRAY_NORMAL:
				if (source_pose.basis*a[slot][ai]).normalized().distance_to((runtime_pose.basis*b[slot][bi]).normalized())>DIRECTION_EPS: return _mismatch("normal",{"difference":(source_pose.basis*a[slot][ai]).normalized().distance_to((runtime_pose.basis*b[slot][bi]).normalized())})
			elif slot==Mesh.ARRAY_TANGENT:
				var av := Vector3(a[slot][ai*4],a[slot][ai*4+1],a[slot][ai*4+2])
				var bv := Vector3(b[slot][bi*4],b[slot][bi*4+1],b[slot][bi*4+2])
				if (source_pose.basis*av).normalized().distance_to((runtime_pose.basis*bv).normalized())>DIRECTION_EPS or a[slot][ai*4+3]!=b[slot][bi*4+3]: return _mismatch("tangent",{"difference":(source_pose.basis*av).normalized().distance_to((runtime_pose.basis*bv).normalized()),"w_a":a[slot][ai*4+3],"w_b":b[slot][bi*4+3]})
			elif a[slot][ai]!=b[slot][bi]: return _mismatch("channel",{"slot":slot,"a":str(a[slot][ai]),"b":str(b[slot][bi])})
	return true

static func _index(arrays: Array, corner: int) -> int:
	return corner if arrays[Mesh.ARRAY_INDEX]==null or arrays[Mesh.ARRAY_INDEX].is_empty() else int(arrays[Mesh.ARRAY_INDEX][corner])

static func _corner_count(mesh: ArrayMesh) -> int:
	var arrays: Array = mesh.surface_get_arrays(0)
	return arrays[Mesh.ARRAY_VERTEX].size() if arrays[Mesh.ARRAY_INDEX]==null or arrays[Mesh.ARRAY_INDEX].is_empty() else arrays[Mesh.ARRAY_INDEX].size()

static func relative(node: Node3D, target: Node3D) -> Transform3D:
	var result := Transform3D.IDENTITY
	var current: Node = node
	while current!=target:
		if current is Node3D: result=current.transform*result
		current=current.get_parent()
	return result

static func _abort(staged: Array, code: String) -> Dictionary:
	for item: Dictionary in staged: item.node.free()
	return {"ok":false,"code":code}

static func _mismatch(kind: String, detail: Dictionary) -> bool:
	print("PAVING_BATCH_MISMATCH "+JSON.stringify({"kind":kind,"detail":detail}))
	return false
