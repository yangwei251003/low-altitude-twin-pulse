"""Native Blender color baking + explicit single candidate GLB.
Only the p3 source directory and the authorized candidate runtime directory.
Frozen p2 runtime and source are never written.
"""
from pathlib import Path
import bpy,json,hashlib,struct,shutil,sys

HERE=Path(__file__).resolve().parent;ROOT=HERE.parents[3]
OUT=ROOT/'assets/v3/candidates/root_buttress_h10_p3'
TEX=HERE/'textures';TEX.mkdir(exist_ok=True);OUT.mkdir(parents=True,exist_ok=True)
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
report=json.loads((HERE/'p3_source_report.json').read_text(encoding='utf-8'))
runtime=report['runtime_p2_before_after_sha256']
def frozen():return {h:sha(ROOT/f'assets/v3/root_buttress/root_buttress_h{h}.glb') for h in runtime}
assert frozen()==runtime
source=HERE/'root_buttress_h10_material_p3.blend'
assert sha(source)==report['source_output_sha256']
bpy.ops.wm.open_mainfile(filepath=str(source));scene=bpy.context.scene
scene.render.engine='CYCLES';scene.cycles.device='CPU';scene.cycles.samples=1
scene.render.threads_mode='FIXED';scene.render.threads=2
asset=bpy.data.objects['RootButtress']
parts=sorted([o for o in asset.children_recursive if o.type=='MESH'],key=lambda o:o.name)
markers=sorted([o for o in asset.children_recursive if o.type=='EMPTY'],key=lambda o:o.name)
def geometry_digest():
 h=hashlib.sha256()
 for o in parts:
  h.update(o.name.encode());h.update(struct.pack('<16d',*(v for row in o.matrix_world for v in row)))
  for v in o.data.vertices:h.update(struct.pack('<3d',*v.co))
  for p in o.data.polygons:h.update(struct.pack('<'+str(len(p.vertices))+'I',*p.vertices))
  for layer in o.data.uv_layers:
   h.update(layer.name.encode())
   for loop in layer.data:h.update(struct.pack('<2d',*loop.uv))
 for o in markers:h.update(o.name.encode());h.update(struct.pack('<16d',*(v for row in o.matrix_world for v in row)))
 return h.hexdigest()
before=geometry_digest();assert before==report['geometry_uv_anchor_fingerprint_before']

baked=[]
for kind in ['Stone','Bark']:
 mat=bpy.data.materials['RB_'+kind]
 bake_mat=mat.copy();bake_mat.name='BakeOnly_'+kind
 nodes=bake_mat.node_tree.nodes;links=bake_mat.node_tree.links
 principled=next(n for n in nodes if n.type=='BSDF_PRINCIPLED')
 emission=nodes.new('ShaderNodeEmission')
 links.new(principled.inputs['Base Color'].links[0].from_socket,emission.inputs['Color'])
 links.new(emission.outputs[0],next(n for n in nodes if n.type=='OUTPUT_MATERIAL').inputs['Surface'])
 bpy.ops.object.select_all(action='DESELECT')
 bpy.ops.mesh.primitive_plane_add(size=2,location=(0,0,-50))
 plane=bpy.context.object;plane.name='BakeOnly_UVPlane';plane.data.materials.append(bake_mat)
 plane.data.uv_layers.active.name='SurfaceUV';plane.data.uv_layers.active.active_render=True
 target=bpy.data.images.new('RB_'+kind+'_BaseColor_P3_Baked',width=1536,height=1536,alpha=False,float_buffer=False)
 target.colorspace_settings.name='sRGB'
 dst=nodes.new('ShaderNodeTexImage');dst.image=target
 for n in nodes:n.select=False
 dst.select=True;nodes.active=dst
 scene.render.bake.use_selected_to_active=False;scene.render.bake.margin=0;scene.render.bake.use_clear=True
 bpy.ops.object.bake(type='EMIT')
 filepath=TEX/f'RB_{kind}_BaseColor_P3.png'
 target.filepath_raw=str(filepath);target.file_format='PNG';target.save();target.pack()
 bpy.data.objects.remove(plane,do_unlink=True);bpy.data.materials.remove(bake_mat)
 # Production material now uses explicit UV -> image -> Principled; native mix
 # recipe remains in the unbaked p3 source, not required at runtime.
 nodes=mat.node_tree.nodes;links=mat.node_tree.links
 p=nodes['Principled BSDF'];tex=nodes.new('ShaderNodeTexImage');tex.name='P3_Baked_BaseColor';tex.image=target;tex.extension='REPEAT'
 uv=next(n for n in nodes if n.type=='UVMAP');links.new(uv.outputs['UV'],tex.inputs['Vector']);links.new(tex.outputs['Color'],p.inputs['Base Color'])
 baked.append({'material':mat.name,'file':str(filepath.relative_to(ROOT)).replace('\\','/'),'sha256':sha(filepath),'resolution':[1536,1536],'operation':'Blender Cycles EMIT bake of native base-color graph, sRGB PNG, CPU2; not composited screenshot'})

# Keep all runtime-used external PBR maps inside this source candidate.
maps=[]
for kind in ['Stone','Bark','Moss','Sap']:
 mat=bpy.data.materials['RB_'+kind]
 for n in mat.node_tree.nodes:
  if n.type!='TEX_IMAGE' or n.image is None:continue
  im=n.image
  # Original unconnected BaseColor references remain editable, packed in source.
  if n.name=='P3_Baked_BaseColor':continue
  if kind in ('Stone','Bark') and im.colorspace_settings.name=='sRGB':continue
  original=HERE.parent/'textures'/Path(im.filepath).name
  if not original.exists():continue
  target=TEX/original.name;shutil.copyfile(original,target)
  assert sha(original)==sha(target)
  im.filepath=str(target)
  maps.append({'file':str(target.relative_to(ROOT)).replace('\\','/'),'sha256':sha(target),'operation':'byte-identical p2 support map copy'})

assert geometry_digest()==before
ready=HERE/'root_buttress_h10_p3_export_ready.blend'
scene.cycles.samples=12
bpy.ops.wm.save_as_mainfile(filepath=str(ready))

groups={n:[] for n in ['RockMasses','LivingRoots','BarkPlates','MossDetails','SapKnot']}
for ob in parts:
 name=ob.name
 if name.startswith('Rock_'):group='RockMasses'
 elif name.startswith('Root_') or name.startswith('RootBranch_'):group='LivingRoots'
 elif name.startswith('BarkPlate_'):group='BarkPlates'
 elif name.startswith('Moss_'):group='MossDetails'
 elif name=='SapKnot':group='SapKnot'
 else:raise AssertionError('Unclassified editable part '+name)
 groups[group].append(ob)
assert all(groups.values())
export_col=bpy.data.collections.new('RuntimeP3_ExportCopies');scene.collection.children.link(export_col)
root=bpy.data.objects.new('RootButtressH10',None);export_col.objects.link(root)
exported=[root];stats=[]
for name,originals in groups.items():
 bpy.ops.object.select_all(action='DESELECT');copies=[]
 for original in originals:
  cp=original.copy();cp.data=original.data.copy();cp.parent=None;cp.matrix_world=original.matrix_world.copy()
  export_col.objects.link(cp);cp.select_set(True);copies.append(cp)
 bpy.context.view_layer.objects.active=copies[0];bpy.ops.object.join();merged=bpy.context.object
 if name in bpy.data.objects and bpy.data.objects[name]!=merged:bpy.data.objects[name].name='Source_'+name
 merged.name=name;merged.parent=root;bpy.ops.object.transform_apply(location=True,rotation=True,scale=True)
 merged['collision_role']='static_concave' if name in ('RockMasses','LivingRoots') else ('target_only' if name=='SapKnot' else 'decoration_no_collision')
 merged.data.calc_loop_triangles();stats.append({'name':name,'triangles':len(merged.data.loop_triangles),'materials':len(merged.data.materials),'source_parts':len(originals)})
 exported.append(merged)
for original in markers:
 name=original.name;original.name='Source_'+name
 marker=bpy.data.objects.new(name,None);export_col.objects.link(marker);marker.parent=root;marker.matrix_world=original.matrix_world.copy();exported.append(marker)
bpy.ops.object.select_all(action='DESELECT')
for ob in exported:ob.select_set(True)
bpy.context.view_layer.objects.active=root
glb=OUT/'root_buttress_h10_p3.glb'
bpy.ops.export_scene.gltf(filepath=str(glb),export_format='GLB',use_selection=True,export_apply=True,export_yup=True,export_extras=True,export_texcoords=True,export_normals=True,export_materials='EXPORT',export_cameras=False,export_lights=False,export_animations=False)
assert frozen()==runtime
out_report={
 'stage':'single H10 p3 candidate; awaiting same-byte GLB reimport and actual Godot camera; not final art',
 'source_input_sha256':sha(source),'source_export_ready':str(ready.relative_to(ROOT)).replace('\\','/'),
 'source_export_ready_sha256':sha(ready),'editable_meshes':len(parts),'geometry_uv_anchors_unchanged':before==report['geometry_uv_anchor_fingerprint_before'],
 'geometry_uv_anchor_fingerprint':before,'baked_base_colors':baked,'support_maps':maps,
 'glb_path':str(glb.relative_to(ROOT)).replace('\\','/'),'glb_sha256':sha(glb),'bytes':glb.stat().st_size,'meshes':stats,
 'runtime_p2_unchanged':frozen()==runtime,'runtime_p2_sha256':runtime,
 'limits':['not final art','not game screenshot','single height only','major regular tabletop and wide front root geometry unchanged','baked base color is generated/painted reference shading, not measured albedo']}
(HERE/'p3_export_report.json').write_text(json.dumps(out_report,ensure_ascii=False,indent=2),encoding='utf-8')
print('P3_EXPORT '+json.dumps(out_report,ensure_ascii=False),flush=True)
