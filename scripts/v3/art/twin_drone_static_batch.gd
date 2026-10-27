extends RefCounted
## One-time V3 visual batching AFTER Fleet palette / FlightBody
## _ready. Original Nodes, rotor ordering, attachments and physics are untouched.
## EXPLICIT full-geometry variant: opt-in replaces automatic per-source LODs
## for merged sources with the original reference surface + reference shadows.
## This is NOT per-LOD equivalence. Default remains conservative/no LOD removal.
## No per-frame cache. No source Resource mutation. Call original silhouette
## rebuild after install. Analyze is a pure count/read path (no ArrayMesh build).
## Array fix: all visual/shadow reads are explicit {ok,code,arrays}. Only the
## exact pinned4.7.2 compressed position-only shadow API omission is compensated.
const PINNED_POSITION_ONLY_SHADOW_FORMAT := 0x820001001
const META := "v3_drone_static_batch_installed"
# Same Godot octahedral normal/tangent re-encoding budget as the audited paving
# batch. Vertex positions/UV/color/handedness/material identity stay strict.
const DIRECTION_EPS := .0002
const RENDER := ["layers","cast_shadow","gi_mode","gi_lightmap_texel_scale","transparency","lod_bias","extra_cull_margin","ignore_occlusion_culling","sorting_offset","sorting_use_aabb_center","visibility_range_begin","visibility_range_end","visibility_range_begin_margin","visibility_range_end_margin","visibility_range_fade_mode"]

static func analyze(model: Node3D, allow_full_geometry_no_lod: bool = false) -> Dictionary:
	if not is_instance_valid(model): return {"ok":false,"code":"drone_model_missing"}
	return _plan(model,allow_full_geometry_no_lod).report

static func install(model: Node3D, allow_full_geometry_no_lod: bool = false) -> Dictionary:
	if not is_instance_valid(model): return {"ok":false,"code":"drone_model_missing"}
	if model.has_meta(META): return {"ok":false,"code":"drone_batch_already_installed"}
	var plan: Dictionary = _plan(model,allow_full_geometry_no_lod)
	var staged: Array = []
	for bucket: Array in plan.buckets.values():
		if bucket.size()<2: continue
		var visual: Dictionary = _merge(bucket,false)
		if not visual.get("ok",false): return _abort(staged,str(visual.code))
		if bucket[0].shadow!=null:
			var shadow: Dictionary = _merge(bucket,true)
			if not shadow.get("ok",false): return _abort(staged,str(shadow.code))
			visual.mesh.shadow_mesh=shadow.mesh
		var node := MeshInstance3D.new()
		node.name="DroneStaticBatch_"+str(staged.size())
		node.mesh=visual.mesh
		for property: String in RENDER: node.set(property,bucket[0].properties[property])
		staged.append({"node":node,"bucket":bucket,"ranges":visual.ranges,"before_bounds":visual.bounds})
	# Validate ALL new vertex/material/shadow data before clearing any source.
	for item: Dictionary in staged:
		if not _equivalent(item): return _abort(staged,"drone_batch_attribute_mismatch")
	var removed: Dictionary = {}
	var groups: Array = []
	var replaced_lod_sources := 0
	var merged_compensated_shadows := 0
	for item: Dictionary in staged:
		item.bucket[0].target.add_child(item.node)
		var names: Array = []
		for row: Dictionary in item.bucket:
			removed[row.node.get_instance_id()]=true
			if row.has_lods: replaced_lod_sources+=1
			if row.shadow_read.get("compensated",false): merged_compensated_shadows+=1
			names.append(row.id)
			row["runtime"]=item.node
			row["range"]=item.ranges[row.id]
			# Preserve Node/children/parent/transform AND original Rotor* references.
			# Hiding the source instead would leave duplicate silhouette ghosts.
			row.node.mesh=null
		groups.append({"anchor":str(model.get_path_to(item.bucket[0].target)),"sources":names,"material_id":str(item.bucket[0].material.get_instance_id()),"runtime":str(item.node.name),"compensated_shadow_sources":item.bucket.filter(func(row: Dictionary): return row.shadow_read.get("compensated",false)).size()})
	for row: Dictionary in plan.records:
		if not removed.has(row.node.get_instance_id()):
			row["runtime"]=row.node
			row["range"]=[0,_corner_count(row.mesh)] if row.mesh!=null and row.mesh.get_surface_count()==1 else []
	var live: Array = []
	_collect_live(model,live)
	model.set_meta(META,true)
	var report: Dictionary = plan.report.duplicate(true)
	report["runtime_meshes"]=live.size()
	report["merged_source_meshes"]=removed.size()
	report["batch_meshes"]=staged.size()
	report["replaced_lod_source_meshes"]=replaced_lod_sources
	report["merged_compensated_shadow_count"]=merged_compensated_shadows
	report["original_lod_source_meshes_preserved"]=int(report.actual_lod_meshes)-replaced_lod_sources
	report["groups"]=groups
	return {"ok":true,"code":"drone_batch_ready","records":plan.records,"runtime_meshes":live,"report":report}

static func _plan(model: Node3D, allow_full_geometry_no_lod: bool) -> Dictionary:
	var records: Array = []
	_collect_records(model,model,records,_has_animation(model))
	var buckets: Dictionary = {}
	var skipped: Array = []
	var supported := 0
	var triangles := 0
	var actual_lods := 0
	var compensated_shadows := 0
	var unreadable_visuals := 0
	var skip_counts: Dictionary = {}
	for row: Dictionary in records:
		triangles+=int(row.triangles)
		if row.shadow_read.get("compensated",false): compensated_shadows+=1
		if not row.visual_read.ok: unreadable_visuals+=1
		if row.has_lods: actual_lods+=1
		var eligible: Variant = _unsupported(row,model,allow_full_geometry_no_lod)
		var accepted: bool = eligible is Dictionary and eligible.get("ok")==true
		var reason := "eligibility_invalid_return"
		if eligible is Dictionary: reason="" if accepted else str(eligible.get("code","eligibility_incomplete"))
		if not accepted and reason.is_empty(): reason="eligibility_incomplete"
		row["skip"]=reason
		if not reason.is_empty():
			skip_counts[reason]=int(skip_counts.get(reason,0))+1
			skipped.append({"source":row.id,"reason":reason,"has_lods":row.has_lods})
			continue
		supported+=1
		var key: String = str(row.target.get_instance_id())+":"+str(row.material.get_instance_id())+":"+str(row.format)+":"+str(row.shadow_format)+":"+JSON.stringify(row.properties)
		if not buckets.has(key): buckets[key]=[]
		buckets[key].append(row)
	var merges := 0
	var consumed := 0
	for bucket: Array in buckets.values():
		if bucket.size()>1:
			merges+=1
			consumed+=bucket.size()
	return {"records":records,"buckets":buckets,"report":{"ok":true,"source_mesh_count":records.size(),"source_triangles":triangles,"supported_meshes":supported,"actual_lod_meshes":actual_lods,"compensated_shadow_count":compensated_shadows,"unreadable_visual_count":unreadable_visuals,"skip_reason_counts":skip_counts,"skipped":skipped,"candidate_batches":merges,"candidate_merged_sources":consumed,"predicted_runtime_meshes":records.size()-consumed+merges,"allow_full_geometry_no_lod":allow_full_geometry_no_lod,"lod_policy":"explicit_full_reference_geometry_for_batched_sources" if allow_full_geometry_no_lod else "preserve_actual_lod_sources_unbatched","reference_triangles":triangles,"per_lod_equivalence_claimed":false}}

static func _has_animation(node: Node) -> bool:
	if str(node.name).begins_with("Attachment_"): return false
	if node is AnimationMixer or node is Skeleton3D: return true
	for child: Node in node.get_children():
		if _has_animation(child): return true
	return false

static func _collect_records(node: Node, model: Node3D, out: Array, animated: bool) -> void:
	if node is MeshInstance3D and node.mesh!=null:
		var target: Node3D = model
		var cursor: Node = node
		while cursor!=model:
			if cursor is Node3D and str(cursor.name).begins_with("Rotor"):
				target=cursor
				break
			cursor=cursor.get_parent()
		var mesh := node.mesh as ArrayMesh
		var shadow: ArrayMesh = mesh.shadow_mesh if mesh!=null else null
		var visual_read: Dictionary = _read_arrays(mesh,false)
		var shadow_read: Dictionary = _read_arrays(shadow,true) if shadow!=null else {"ok":true,"compensated":false}
		var properties: Dictionary = {}
		for property: String in RENDER: properties[property]=node.get(property)
		var lods := false
		for resource: ArrayMesh in [mesh,shadow]:
			if resource==null: continue
			for surface: int in resource.get_surface_count():
				if not RenderingServer.mesh_get_surface(resource.get_rid(),surface).get("lods",[]).is_empty(): lods=true
		out.append({"node":node,"id":str(model.get_path_to(node)),"target":target,"source_mesh":node.mesh,"mesh":mesh,"shadow":shadow,"material":node.get_active_material(0) if node.mesh.get_surface_count()>0 else null,"pose":relative(node,target),"format":mesh.surface_get_format(0) if mesh!=null and mesh.get_surface_count()>0 else -1,"shadow_format":shadow.surface_get_format(0) if shadow!=null and shadow.get_surface_count()==1 else -1,"properties":properties,"animated":animated,"has_lods":lods,"visual_read":visual_read,"shadow_read":shadow_read,"triangles":int(visual_read.get("corner_count",0)/3)})
	for child: Node in node.get_children(): _collect_records(child,model,out,animated)

static func _unsupported(row: Dictionary, model: Node3D, allow_full_geometry_no_lod: bool) -> Dictionary:
	var node: MeshInstance3D = row.node
	var mesh := row.mesh as ArrayMesh
	var material := row.material as BaseMaterial3D
	if row.animated: return {"ok":false,"code":"animation_or_skeleton_present"}
	var cursor: Node = node
	while cursor!=model:
		if str(cursor.name).begins_with("Attachment_"): return {"ok":false,"code":"attachment_branch"}
		# These currently static sensor controls are cheap to leave independent.
		if str(cursor.name).begins_with("SensorPivot") or str(cursor.name).begins_with("OpticalLens"): return {"ok":false,"code":"independent_sensor_branch"}
		if not cursor is Node3D or cursor.get_script()!=null: return {"ok":false,"code":"unknown_script_or_node"}
		if cursor.is_set_as_top_level() or not cursor.visible or not cursor.visibility_parent.is_empty(): return {"ok":false,"code":"independent_transform_or_visibility"}
		if not cursor.transform.is_finite() or cursor.basis.determinant()<=0.0 or not cursor.basis.is_equal_approx(cursor.basis.orthonormalized()): return {"ok":false,"code":"nonrigid_local_transform"}
		for flag: String in ["terrain_visibility_keep","terrain_visibility_cutaway_detail","terrain_visibility_single_sided"]:
			if cursor.has_meta(flag): return {"ok":false,"code":"independent_visibility_metadata"}
		cursor=cursor.get_parent()
	if mesh==null or mesh.get_surface_count()!=1 or mesh.get_blend_shape_count()!=0: return {"ok":false,"code":"unsupported_mesh"}
	if material==null or material.transparency!=BaseMaterial3D.TRANSPARENCY_DISABLED or material.next_pass!=null: return {"ok":false,"code":"nonopaque_or_multipass_material"}
	if material.uv1_triplanar or material.uv2_triplanar or material.billboard_mode!=BaseMaterial3D.BILLBOARD_DISABLED or material.grow or material.fixed_size or material.use_point_size: return {"ok":false,"code":"local_space_material_effect"}
	if node.skin!=null or node.get_node_or_null(node.skeleton) is Skeleton3D or node.material_overlay!=null: return {"ok":false,"code":"skin_skeleton_or_overlay"}
	if node.custom_aabb!=AABB(): return {"ok":false,"code":"custom_instance_culling_bounds"}
	if node.transparency!=0.0 or node.visibility_range_begin!=0.0 or node.visibility_range_end!=0.0: return {"ok":false,"code":"per_leaf_visibility_range"}
	if not row.pose.is_finite() or row.pose.basis.determinant()<=0.0 or not row.pose.basis.is_equal_approx(row.pose.basis.orthonormalized()): return {"ok":false,"code":"nonrigid_relative_transform"}
	if row.has_lods and not allow_full_geometry_no_lod: return {"ok":false,"code":"actual_imported_lods"}
	for resource: ArrayMesh in [mesh,row.shadow]:
		if resource==null: continue
		if resource.get_surface_count()!=1 or resource.surface_get_primitive_type(0)!=Mesh.PRIMITIVE_TRIANGLES or resource.get_blend_shape_count()!=0: return {"ok":false,"code":"unsupported_visual_or_shadow"}
		if resource.custom_aabb!=AABB(): return {"ok":false,"code":"custom_mesh_culling_bounds"}
	var visual: Dictionary = row.visual_read
	if not visual.get("ok",false): return {"ok":false,"code":"visual_"+str(visual.get("code","arrays_unavailable"))}
	var shadow: Dictionary = row.shadow_read
	if not shadow.get("ok",false): return {"ok":false,"code":"shadow_"+str(shadow.get("code","arrays_unavailable"))}
	return {"ok":true,"code":"supported"}

static func _read_arrays(mesh: ArrayMesh, shadow: bool = false) -> Dictionary:
	if mesh==null or mesh.get_surface_count()!=1 or mesh.surface_get_primitive_type(0)!=Mesh.PRIMITIVE_TRIANGLES or mesh.get_blend_shape_count()!=0:
		return {"ok":false,"code":"surface_schema"}
	var arrays: Array = mesh.surface_get_arrays(0)
	if arrays.size()!=Mesh.ARRAY_MAX: return {"ok":false,"code":"array_slot_count"}
	var compensated := false
	if arrays[Mesh.ARRAY_VERTEX]==null and shadow:
		var recovered: Dictionary = _decode_pinned_position_only_shadow(mesh,arrays)
		if not recovered.get("ok",false): return recovered
		arrays=recovered.arrays
		compensated=true
	var valid: Dictionary = _validate_arrays(arrays,mesh.surface_get_format(0),mesh.surface_get_array_len(0))
	if not valid.get("ok",false): return valid
	return {"ok":true,"code":"pinned_shadow_vertex_return_compensated" if compensated else "original_arrays","arrays":arrays,"corner_count":valid.corner_count,"compensated":compensated}

static func _validate_arrays(arrays: Array, format: int, native_vertex_count: int) -> Dictionary:
	if arrays.size()!=Mesh.ARRAY_MAX: return {"ok":false,"code":"array_slot_count"}
	if typeof(arrays[Mesh.ARRAY_VERTEX])!=TYPE_PACKED_VECTOR3_ARRAY: return {"ok":false,"code":"vertex_array_missing_or_type"}
	var count: int = arrays[Mesh.ARRAY_VERTEX].size()
	if count<=0 or count!=native_vertex_count: return {"ok":false,"code":"vertex_array_count"}
	var types: Dictionary = {Mesh.ARRAY_VERTEX:TYPE_PACKED_VECTOR3_ARRAY,Mesh.ARRAY_NORMAL:TYPE_PACKED_VECTOR3_ARRAY,Mesh.ARRAY_TANGENT:TYPE_PACKED_FLOAT32_ARRAY,Mesh.ARRAY_COLOR:TYPE_PACKED_COLOR_ARRAY,Mesh.ARRAY_TEX_UV:TYPE_PACKED_VECTOR2_ARRAY,Mesh.ARRAY_TEX_UV2:TYPE_PACKED_VECTOR2_ARRAY,Mesh.ARRAY_INDEX:TYPE_PACKED_INT32_ARRAY}
	for slot: int in Mesh.ARRAY_MAX:
		if arrays[slot]==null:
			if (format & (1<<slot))!=0: return {"ok":false,"code":"format_channel_missing_"+str(slot)}
			continue
		if not types.has(slot) or typeof(arrays[slot])!=int(types[slot]): return {"ok":false,"code":"unsupported_channel_type_"+str(slot)}
		if slot!=Mesh.ARRAY_INDEX and arrays[slot].size()!=count*(4 if slot==Mesh.ARRAY_TANGENT else 1): return {"ok":false,"code":"channel_count_"+str(slot)}
	for slot: int in [Mesh.ARRAY_VERTEX,Mesh.ARRAY_NORMAL,Mesh.ARRAY_TEX_UV,Mesh.ARRAY_TEX_UV2]:
		if arrays[slot]==null: continue
		for value: Variant in arrays[slot]:
			if not value.is_finite(): return {"ok":false,"code":"nonfinite_channel_"+str(slot)}
	if arrays[Mesh.ARRAY_TANGENT]!=null:
		for value: float in arrays[Mesh.ARRAY_TANGENT]:
			if not is_finite(value): return {"ok":false,"code":"nonfinite_tangent"}
	var corners := count
	if arrays[Mesh.ARRAY_INDEX]!=null:
		corners=arrays[Mesh.ARRAY_INDEX].size()
		for index: int in arrays[Mesh.ARRAY_INDEX]:
			if index<0 or index>=count: return {"ok":false,"code":"index_out_of_range"}
	if corners<=0 or corners%3!=0: return {"ok":false,"code":"triangle_corner_count"}
	return {"ok":true,"corner_count":corners}

static func _decode_pinned_position_only_shadow(mesh: ArrayMesh, original: Array) -> Dictionary:
	# Official ed1daf0bf rendering_server.cpp1333-1341 continues before1378,
	# omitting ret[VERTEX] for this exact compressed/no-normal branch.
	# Recover ONLY local returned arrays from original raw shadow bytes.
	var version: Dictionary = Engine.get_version_info()
	if int(version.get("major",0))!=4 or int(version.get("minor",0))!=7 or int(version.get("patch",0))!=2 or not str(version.get("hash","")).begins_with("ed1daf0bf"):
		return {"ok":false,"code":"shadow_compensation_engine_mismatch"}
	if OS.get_name()!="Windows": return {"ok":false,"code":"shadow_compensation_platform_unverified"}
	if mesh.surface_get_format(0)!=PINNED_POSITION_ONLY_SHADOW_FORMAT: return {"ok":false,"code":"shadow_compensation_format_mismatch"}
	if original.size()!=Mesh.ARRAY_MAX or original[Mesh.ARRAY_VERTEX]!=null or typeof(original[Mesh.ARRAY_INDEX])!=TYPE_PACKED_INT32_ARRAY:
		return {"ok":false,"code":"shadow_compensation_array_schema"}
	for slot: int in range(1,Mesh.ARRAY_INDEX):
		if original[slot]!=null: return {"ok":false,"code":"shadow_compensation_extra_channel"}
	var data: Dictionary = RenderingServer.mesh_get_surface(mesh.get_rid(),0)
	if data.get("format")!=PINNED_POSITION_ONLY_SHADOW_FORMAT or data.get("primitive")!=Mesh.PRIMITIVE_TRIANGLES:
		return {"ok":false,"code":"shadow_compensation_native_schema"}
	var count: int = int(data.get("vertex_count",0))
	var index_count: int = int(data.get("index_count",0))
	if count<=0 or count>65536 or count!=mesh.surface_get_array_len(0) or index_count<=0 or index_count%3!=0 or index_count!=mesh.surface_get_array_index_len(0):
		return {"ok":false,"code":"shadow_compensation_native_count"}
	if typeof(data.get("aabb"))!=TYPE_AABB or typeof(data.get("vertex_data"))!=TYPE_PACKED_BYTE_ARRAY or typeof(data.get("index_data"))!=TYPE_PACKED_BYTE_ARRAY:
		return {"ok":false,"code":"shadow_compensation_native_types"}
	var bounds: AABB = data.aabb
	if not bounds.position.is_finite() or not bounds.size.is_finite() or bounds.size.x<0 or bounds.size.y<0 or bounds.size.z<0:
		return {"ok":false,"code":"shadow_compensation_native_bounds"}
	var bytes: PackedByteArray = data.vertex_data
	var index_bytes: PackedByteArray = data.index_data
	if bytes.size()!=count*8 or index_bytes.size()!=index_count*2 or original[Mesh.ARRAY_INDEX].size()!=index_count:
		return {"ok":false,"code":"shadow_compensation_byte_lengths"}
	for channel: String in ["attribute_data","skin_data","blend_shape_data"]:
		var raw: Variant = data.get(channel,PackedByteArray())
		if typeof(raw)!=TYPE_PACKED_BYTE_ARRAY or not raw.is_empty(): return {"ok":false,"code":"shadow_compensation_extra_bytes"}
	var vertices := PackedVector3Array()
	vertices.resize(count)
	for index: int in count:
		var offset: int = index*8
		if bytes.decode_u16(offset+6)!=0: return {"ok":false,"code":"shadow_compensation_nonzero_padding"}
		# Windows little endian; exact official uint16 normalization, then the
		# native float32 Vector3 multiply/add (no visual-mesh substitution).
		vertices[index]=Vector3(bytes.decode_u16(offset)/65535.0,bytes.decode_u16(offset+2)/65535.0,bytes.decode_u16(offset+4)/65535.0)*bounds.size+bounds.position
		if not vertices[index].is_finite(): return {"ok":false,"code":"shadow_compensation_nonfinite_vertex"}
	for index: int in index_count:
		var decoded: int = index_bytes.decode_u16(index*2)
		if decoded>=count or decoded!=int(original[Mesh.ARRAY_INDEX][index]): return {"ok":false,"code":"shadow_compensation_index_mismatch"}
	var arrays: Array = original.duplicate()
	arrays[Mesh.ARRAY_VERTEX]=vertices
	return {"ok":true,"arrays":arrays}

static func _collect_live(node: Node, out: Array) -> void:
	if node is MeshInstance3D and node.mesh!=null: out.append(node)
	for child: Node in node.get_children(): _collect_live(child,out)

static func proof(batch: Dictionary) -> Dictionary:
	var rows: Array = []
	var okay := bool(batch.get("ok",false))
	for row: Dictionary in batch.get("records",[]):
		var matched := true
		if row.skip.is_empty():
			var node: MeshInstance3D = row.runtime
			matched=is_instance_valid(node) and node.mesh!=null and node.get_active_material(0)==row.material and _corners_equal(row.mesh,row.pose,node.mesh,relative(node,row.target),int(row.range[0]),int(row.range[1]))
			for property: String in RENDER: matched=matched and node.get(property)==row.properties[property]
			if row.shadow!=null:
				# Shadow corner spans follow the same source ordering, but can have
				# a different vertex/index count than the visual surface.
				var begin := 0
				for earlier: Dictionary in batch.records:
					if earlier==row: break
					if earlier.get("runtime")==node and earlier.shadow!=null: begin+=_corner_count(earlier.shadow,true)
				matched=matched and _corners_equal(row.shadow,row.pose,node.mesh.shadow_mesh,relative(node,row.target),begin,_corner_count(row.shadow,true),true)
		else:
			matched=is_instance_valid(row.node) and row.node.mesh==row.source_mesh
		okay=okay and matched
		rows.append({"source":row.id,"matched":matched,"skip":row.skip})
	return {"ok":okay and not rows.is_empty(),"rows":rows}

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
		var read: Dictionary = _read_arrays(mesh,shadow)
		if not read.get("ok",false): return {"ok":false,"code":"drone_batch_arrays_"+str(read.get("code","unavailable"))}
		var arrays: Array = read.arrays
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
	if result.get_surface_count()!=1: return {"ok":false,"code":"drone_batch_surface_failed"}
	if not shadow: result.surface_set_material(0,rows[0].material)
	if result.get_aabb().position.distance_to(bounds.position)>.00005 or result.get_aabb().end.distance_to(bounds.end)>.00005: return {"ok":false,"code":"drone_batch_bounds_failed"}
	return {"ok":true,"mesh":result,"ranges":ranges,"bounds":bounds}

static func _equivalent(item: Dictionary) -> bool:
	for row: Dictionary in item.bucket:
		var span: Array = item.ranges[row.id]
		if not _corners_equal(row.mesh,row.pose,item.node.mesh,Transform3D.IDENTITY,span[0],span[1]): return false
		if row.shadow!=null and not _corners_equal(row.shadow,row.pose,item.node.mesh.shadow_mesh,Transform3D.IDENTITY,_shadow_begin(item,row),_corner_count(row.shadow,true),true): return false
	return true

static func _shadow_begin(item: Dictionary, wanted: Dictionary) -> int:
	var result := 0
	for row: Dictionary in item.bucket:
		if row.id==wanted.id: break
		result+=_corner_count(row.shadow,true)
	return result

static func _corners_equal(source: ArrayMesh, source_pose: Transform3D, runtime: ArrayMesh, runtime_pose: Transform3D, begin: int, count: int, shadow: bool = false) -> bool:
	if source==null or runtime==null: return false
	var original: Dictionary = _read_arrays(source,shadow)
	var actual: Dictionary = _read_arrays(runtime,shadow)
	if not original.get("ok",false) or not actual.get("ok",false) or count!=original.corner_count: return false
	var a: Array = original.arrays
	var b: Array = actual.arrays
	if begin<0 or begin+count>actual.corner_count: return false
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

static func _corner_count(mesh: ArrayMesh, shadow: bool = false) -> int:
	var read: Dictionary = _read_arrays(mesh,shadow)
	return int(read.get("corner_count",0)) if read.get("ok",false) else 0

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
	print("DRONE_BATCH_MISMATCH "+JSON.stringify({"kind":kind,"detail":detail}))
	return false
