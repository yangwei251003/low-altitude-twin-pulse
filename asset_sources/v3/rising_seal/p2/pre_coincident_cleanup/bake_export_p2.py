"""Actual source-mesh PBR bake; explicit standalone candidate, no Godot import."""
from pathlib import Path
import bpy,math,json,hashlib,struct,sys
HERE=Path(__file__).resolve().parent;ROOT=HERE.parents[3]
OUT=ROOT/'assets/v3/candidates/rising_seal_p2';TEX=HERE/'textures';TEX.mkdir(exist_ok=True)
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
source=HERE/'rising_seal_source_p2.blend';ready=HERE/'rising_seal_p2_export_ready.blend'
report=json.loads((HERE/'source_report.json').read_text(encoding='utf-8'))
assert report['all_pass'] and sha(source)==report['source_sha256']
bpy.ops.wm.open_mainfile(filepath=str(ready if '--export-only' in sys.argv else source));scene=bpy.context.scene;root=bpy.data.objects['RisingSeal']
parts=[o for o in root.children if o.type=='MESH'];anchors=[bpy.data.objects[n] for n in ['Centre','BottomContact','StateInlay']]
def geom(o):
 h=hashlib.sha256();h.update(struct.pack('<16d',*(x for row in o.matrix_world for x in row)))
 for v in o.data.vertices:h.update(struct.pack('<3d',*v.co))
 for f in o.data.polygons:h.update(struct.pack('<'+str(len(f.vertices))+'I',*f.vertices))
 return h.hexdigest()
before={o.name:geom(o) for o in parts}
groups={'stone':[o for o in parts if o.name.startswith(('StoneMass_','SeamClosure','SealRecess'))],'wood':[o for o in parts if o.name.startswith('RootWrap_')],'bronze':[o for o in parts if o.name.startswith(('BronzeChannel_','PanelClamp_','SealBronzeBoss','SealOuterRing','SealPatinaRing'))],'core':[bpy.data.objects['SealEnergyGlass']]}
assert {o for group in groups.values() for o in group}==set(parts)
scene.render.engine='CYCLES';scene.cycles.device='CPU';scene.cycles.samples=1;scene.render.threads_mode='FIXED';scene.render.threads=2
scene.render.bake.use_selected_to_active=False;scene.render.bake.use_clear=True;scene.render.bake.margin=12;scene.render.bake.margin_type='EXTEND';scene.render.bake.normal_space='TANGENT'
maps=[]
if '--export-only' not in sys.argv:
 visibility={o:o.hide_render for o in scene.objects if o.type=='MESH'}
 for o in visibility:o.hide_render=True
 for kind,group in groups.items():
  verts=[];faces=[];mapping=[];smooth=[];mats=[];mi=[]
  for ob in group:
   offset=len(verts);verts.extend(tuple(ob.matrix_world@v.co) for v in ob.data.vertices)
   for material in ob.data.materials:
    if material not in mats:mats.append(material)
   for poly in ob.data.polygons:
    faces.append(tuple(offset+i for i in poly.vertices));mapping.append((ob,poly.index));smooth.append(poly.use_smooth);mi.append(mats.index(ob.data.materials[poly.material_index]))
  data=bpy.data.meshes.new('_SealBake_'+kind);data.from_pydata(verts,[],faces);data.update();temp=bpy.data.objects.new('_SealBake_'+kind,data);scene.collection.objects.link(temp)
  for m in mats:data.materials.append(m)
  detail=data.uv_layers.new(name='DetailUV');target=data.uv_layers.new(name='SurfaceUV')
  for poly,(ob,pi),sm,material_index in zip(data.polygons,mapping,smooth,mi):
   poly.use_smooth=sm;poly.material_index=material_index
   old=ob.data.uv_layers.active
   for li,old_li in zip(poly.loop_indices,ob.data.polygons[pi].loop_indices):
    detail.data[li].uv=old.data[old_li].uv if old else (verts[data.loops[li].vertex_index][1]*.15,verts[data.loops[li].vertex_index][2]*.15)
  data.uv_layers.active=target;target.active_render=True
  # Explicit source UV, separate from packed target UV; prevent wrong UV sampling.
  for m in mats:
   for n in list(m.node_tree.nodes):
    if n.type=='TEX_COORD':
     for link in list(n.outputs['UV'].links):
      uv=m.node_tree.nodes.new('ShaderNodeUVMap');uv.uv_map='DetailUV';m.node_tree.links.new(uv.outputs[0],link.to_socket)
    elif n.type=='UVMAP':n.uv_map='DetailUV'
  bpy.ops.object.select_all(action='DESELECT');temp.select_set(True);bpy.context.view_layer.objects.active=temp
  bpy.ops.object.mode_set(mode='EDIT');bpy.ops.mesh.select_all(action='SELECT');bpy.ops.uv.smart_project(angle_limit=math.radians(66),island_margin=.012,area_weight=.6,correct_aspect=True,scale_to_bounds=True);bpy.ops.object.mode_set(mode='OBJECT')
  setup=[]
  for m in mats:
   m.use_fake_user=True;ns=m.node_tree.nodes;ls=m.node_tree.links
   p=next(n for n in ns if n.type=='BSDF_PRINCIPLED');out=next(n for n in ns if n.type=='OUTPUT_MATERIAL');em=ns.new('ShaderNodeEmission');em.inputs['Strength'].default_value=1;tn=ns.new('ShaderNodeTexImage');tn.name='ACTIVE_BAKE_TARGET';setup.append((m,p,out,em,tn))
  size={'stone':1536,'wood':1536,'bronze':1024,'core':512}[kind];images={}
  for channel in ['basecolor','roughness','normal']:
   image=bpy.data.images.new('seal_'+kind+'_'+channel+'_p2',width=size,height=size,alpha=False,float_buffer=False);image.colorspace_settings.name='Non-Color' if channel in ['roughness','normal'] else 'sRGB'
   for m,p,out,em,tn in setup:
    ns=m.node_tree.nodes;ls=m.node_tree.links;tn.image=image
    for n in ns:n.select=False
    tn.select=True;ns.active=tn
    if channel=='normal':ls.new(p.outputs[0],out.inputs['Surface'])
    else:
     s=p.inputs['Base Color' if channel=='basecolor' else 'Roughness']
     for link in list(em.inputs['Color'].links):ls.remove(link)
     if s.is_linked:ls.new(s.links[0].from_socket,em.inputs['Color'])
     else:
      value=s.default_value;em.inputs['Color'].default_value=(value,value,value,1) if isinstance(value,float) else value
     ls.new(em.outputs[0],out.inputs['Surface'])
   print('SEAL_BAKE_START',kind,channel,size,flush=True);bpy.ops.object.bake(type='NORMAL' if channel=='normal' else 'EMIT')
   path=TEX/(image.name+'.png');image.filepath_raw=str(path);image.file_format='PNG';image.save();image.pack();images[channel]=image
   maps.append({'path':path.relative_to(ROOT).as_posix(),'sha256':sha(path),'bytes':path.stat().st_size,'kind':kind,'channel':channel,'width':size,'height':size});print('SEAL_BAKE_END',kind,channel,flush=True)
  for m,p,out,em,tn in setup:m.node_tree.links.new(p.outputs[0],out.inputs['Surface']);m.node_tree.nodes.remove(em);m.node_tree.nodes.remove(tn)
  result=bpy.data.materials.new('SealP2_'+kind);result.use_nodes=True;ns=result.node_tree.nodes;ns.clear();ls=result.node_tree.links;out=ns.new('ShaderNodeOutputMaterial');p=ns.new('ShaderNodeBsdfPrincipled');ls.new(p.outputs[0],out.inputs['Surface'])
  p.inputs['Metallic'].default_value={'stone':0,'wood':0,'bronze':.5,'core':.10}[kind];p.inputs['Specular IOR Level'].default_value=.23
  uv=ns.new('ShaderNodeUVMap');uv.uv_map='SurfaceUV'
  for channel,image in images.items():
   tex=ns.new('ShaderNodeTexImage');tex.image=image;tex.extension='EXTEND';ls.new(uv.outputs[0],tex.inputs['Vector'])
   if channel=='normal':
    normal=ns.new('ShaderNodeNormalMap');normal.uv_map='SurfaceUV';ls.new(tex.outputs['Color'],normal.inputs['Color']);ls.new(normal.outputs[0],p.inputs['Normal'])
   else:
    ls.new(tex.outputs['Color'],p.inputs['Base Color' if channel=='basecolor' else 'Roughness'])
    if channel=='basecolor' and kind=='core':ls.new(tex.outputs['Color'],p.inputs['Emission Color']);p.inputs['Emission Strength'].default_value=.12
  # Reacquire after edit-mode smart-project/baking. Do not keep RNA UV-layer
  # pointers across mode changes; snapshot plain coordinates before mutations.
  packed_uv=[tuple(loop.uv) for loop in temp.data.uv_layers['SurfaceUV'].data]
  for ob in group:
   if ob.data.uv_layers.active:ob.data.uv_layers.active.name='DetailUV'
   target_layer=ob.data.uv_layers.get('SurfaceUV') or ob.data.uv_layers.new(name='SurfaceUV');ob.data.uv_layers.active=target_layer;target_layer.active_render=True
  for poly,(ob,pi) in zip(data.polygons,mapping):
   for li,old_li in zip(poly.loop_indices,ob.data.polygons[pi].loop_indices):ob.data.uv_layers['SurfaceUV'].data[old_li].uv=packed_uv[li]
  for ob in group:
   ob.data.materials.clear();ob.data.materials.append(result)
   for poly in ob.data.polygons:poly.material_index=0
  bpy.data.objects.remove(temp,do_unlink=True);bpy.data.meshes.remove(data)
 for ob,value in visibility.items():ob.hide_render=value
 assert before=={o.name:geom(o) for o in parts},'Bake changed source geometry'
 scene.cycles.samples=12;bpy.ops.wm.save_as_mainfile(filepath=str(ready))
 (HERE/'bake_report.json').write_text(json.dumps({'source_sha256':sha(source),'ready_sha256':sha(ready),'maps':maps,'geometry_unchanged':True,'lighting_baked':False,'source_detail_uv_separate_from_target':'SurfaceUV'},ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
else:
 old=json.loads((HERE/'bake_report.json').read_text(encoding='utf-8'));assert sha(ready)==old['ready_sha256'];maps=old['maps']
if '--bake-only' in sys.argv:print('SEAL_BAKE_ONLY_DONE',flush=True);sys.exit(0)
OUT.mkdir(parents=True,exist_ok=True);export_col=bpy.data.collections.new('SealP2_ExportCopies');scene.collection.children.link(export_col);er=bpy.data.objects.new('RisingSealP2',None);export_col.objects.link(er);exported=[er];stats=[]
names={'stone':'StoneMasses','wood':'LivingRoots','bronze':'BronzeFittings','core':'SealEnergyGlass'}
for kind,group in groups.items():
 bpy.ops.object.select_all(action='DESELECT');copies=[]
 for ob in group:
  # Freeze the actual author triangulation before joining: joining n-gons may
  # choose a different diagonal. Preserve corner UVs and author split normals.
  old=ob.data;old.calc_loop_triangles();tris=list(old.loop_triangles)
  data=bpy.data.meshes.new(ob.name+'_ExplicitSourceTriangles');data.from_pydata([tuple(v.co) for v in old.vertices],[],[tuple(t.vertices) for t in tris]);data.update()
  for m in old.materials:data.materials.append(m)
  uv=data.uv_layers.new(name='SurfaceUV');uv.active_render=True;normal_values=[]
  for poly,tri in zip(data.polygons,tris):
   poly.material_index=old.polygons[tri.polygon_index].material_index;poly.use_smooth=old.polygons[tri.polygon_index].use_smooth
   for li,oi in zip(poly.loop_indices,tri.loops):uv.data[li].uv=old.uv_layers['SurfaceUV'].data[oi].uv;normal_values.append(tuple(old.corner_normals[oi].vector))
  data.normals_split_custom_set(normal_values)
  cp=ob.copy();cp.data=data;cp.parent=None;cp.matrix_world=ob.matrix_world.copy();export_col.objects.link(cp);cp.select_set(True);copies.append(cp)
 bpy.context.view_layer.objects.active=copies[0]
 if len(copies)>1:bpy.ops.object.join()
 ob=bpy.context.object;name=names[kind]
 if name in bpy.data.objects and bpy.data.objects[name]!=ob:bpy.data.objects[name].name='Author_'+name
 ob.name=name;ob.parent=er;bpy.ops.object.transform_apply(location=True,rotation=True,scale=True)
 ob.data.uv_layers.active=ob.data.uv_layers['SurfaceUV']
 for layer in list(ob.data.uv_layers):
  if layer.name!='SurfaceUV':ob.data.uv_layers.remove(layer)
 ob.data.uv_layers.active.active_render=True;ob.data.calc_loop_triangles();stats.append({'name':name,'kind':kind,'triangles':len(ob.data.loop_triangles),'materials':len(ob.data.materials),'source_parts':len(group)});exported.append(ob)
for ob in anchors:
 name=ob.name;ob.name='Author_'+name;cp=bpy.data.objects.new(name,None);export_col.objects.link(cp);cp.parent=er;cp.matrix_world=ob.matrix_world.copy();exported.append(cp)
bpy.ops.object.select_all(action='DESELECT')
for ob in exported:ob.select_set(True)
bpy.context.view_layer.objects.active=er;glb=OUT/'rising_seal_p2.glb'
bpy.ops.export_scene.gltf(filepath=str(glb),export_format='GLB',use_selection=True,export_apply=True,export_yup=True,export_extras=True,export_texcoords=True,export_normals=True,export_materials='EXPORT',export_cameras=False,export_lights=False,export_animations=False)
assert all(sha(ROOT/p)==value for p,value in report['input_hashes'].items())
result={'stage':'standalone candidate pending same-byte GLB readback and game review','glb':glb.relative_to(ROOT).as_posix(),'glb_sha256':sha(glb),'bytes':glb.stat().st_size,'source_sha256':sha(source),'ready_source':ready.relative_to(ROOT).as_posix(),'ready_sha256':sha(ready),'meshes':stats,'maps':maps,'readonly_inputs':report['input_hashes'],'anchors_godot':{'Centre':[0,0,0],'BottomContact':[0,-2.5,0],'StateInlay':[.49,-.1,0]},'core_emission_strength':.12}
(HERE/'export_report.json').write_text(json.dumps(result,ensure_ascii=False,indent=2)+'\n',encoding='utf-8');print('SEAL_EXPORT_DONE',sha(glb),glb.stat().st_size,flush=True)
