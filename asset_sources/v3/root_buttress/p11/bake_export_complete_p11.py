"""Explicit actual-mesh PBR atlas bake and separate H10 candidate GLB only."""
import bpy,hashlib,json,struct,sys,shutil
from pathlib import Path
HERE=Path(__file__).resolve().parent;ROOT=HERE.parents[3];sys.path.insert(0,str(HERE))
from bake_pbr_atlas import bake_pbr
OUT=ROOT/'assets/v3/candidates/root_buttress_h10_p11';TEX=HERE/'textures';TEX.mkdir(exist_ok=True)
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
report=json.loads((HERE/'p11_source_report.json').read_text(encoding='utf-8'));source=HERE/'root_buttress_h10_complete_p11.blend'
assert report['all_pass'] and sha(source)==report['source_sha256']
runtime=report['runtime_P2_sha256'];ready=HERE/'root_buttress_h10_p11_export_ready.blend'
bpy.ops.wm.open_mainfile(filepath=str(ready if '--export-only' in sys.argv else source));scene=bpy.context.scene;root=bpy.data.objects['RootButtress']
parts=[o for o in root.children_recursive if o.type=='MESH'];anchors=[bpy.data.objects[n] for n in ['GroundOrigin','BodyPerch','HostTarget','LowerShelf']]
def geom_digest(ob):
 h=hashlib.sha256();h.update(struct.pack('<16d',*(v for row in ob.matrix_world for v in row)))
 for v in ob.data.vertices:h.update(struct.pack('<3d',*v.co))
 for f in ob.data.polygons:h.update(struct.pack('<'+str(len(f.vertices))+'I',*f.vertices))
 return h.hexdigest()
before={o.name:geom_digest(o) for o in parts}
body=bpy.data.objects['RockMasses'];roots=[o for o in parts if o.name.startswith('Root_')];sap=bpy.data.objects['SapKnot']
scene.render.threads_mode='FIXED';scene.render.threads=2;scene.cycles.device='CPU'
if '--export-only' in sys.argv:
 prior=json.loads((HERE/'p11_bake_report.json').read_text(encoding='utf-8'));assert sha(ready)==prior['ready_source_sha256'];maps=prior['atlas_maps']
else:baked,maps=bake_pbr(scene,[body,*roots],{'stone':body.data.materials[0],'bark':roots[0].data.materials[0]},TEX,'p11')
assert before=={o.name:geom_digest(o) for o in parts},'Baking changed geometry'
# Preserve Sap original geometry/UV/material. Its existing explicit PBR images
# are copied byte-identically into this source bundle and packed for export.
sap_maps=[]
for node in sap.data.materials[0].node_tree.nodes:
 if node.type=='TEX_IMAGE' and node.image:
  origin=HERE.parent/'p3/textures'/Path(node.image.filepath).name
  if origin.exists():
   target=TEX/origin.name;shutil.copyfile(origin,target);assert sha(origin)==sha(target);node.image.filepath=str(target);node.image.pack();sap_maps.append({'file':str(target.relative_to(ROOT)).replace('\\','/'),'sha256':sha(target),'method':'byte-identical prior Sap PBR map'})
if '--export-only' not in sys.argv:
 scene.cycles.samples=8;bpy.ops.wm.save_as_mainfile(filepath=str(ready))
 bake_report={'source_sha256':sha(source),'ready_source_sha256':sha(ready),'atlas_maps':maps,'sap_maps':sap_maps,'source_geometry_unchanged':True,'runtime_P2_sha256':runtime}
 (HERE/'p11_bake_report.json').write_text(json.dumps(bake_report,ensure_ascii=False,indent=2),encoding='utf-8')
if '--bake-only' in sys.argv:
 assert all(sha(ROOT/f'assets/v3/root_buttress/root_buttress_h{h}.glb')==v for h,v in runtime.items());print('P11_BAKE_ONLY_DONE_NO_RUNTIME_WRITE',flush=True);sys.exit(0)
OUT.mkdir(parents=True,exist_ok=True)
export_col=bpy.data.collections.new('P11_RuntimeExportCopies');scene.collection.children.link(export_col);export_root=bpy.data.objects.new('RootButtressH10',None);export_col.objects.link(export_root);exported=[export_root];stats=[]
for name,originals in [('RockMasses',[body]),('LivingRoots',roots),('SapKnot',[sap])]:
 bpy.ops.object.select_all(action='DESELECT');copies=[]
 for ob in originals:
  cp=ob.copy();cp.data=ob.data.copy();cp.parent=None;cp.matrix_world=ob.matrix_world.copy();export_col.objects.link(cp);cp.select_set(True);copies.append(cp)
 bpy.context.view_layer.objects.active=copies[0]
 if len(copies)>1:bpy.ops.object.join()
 merged=bpy.context.object
 if name in bpy.data.objects and bpy.data.objects[name]!=merged:bpy.data.objects[name].name='Source_'+name
 merged.name=name;merged.parent=export_root;bpy.ops.object.transform_apply(location=True,rotation=True,scale=True)
 for uv in list(merged.data.uv_layers):
  if uv!=merged.data.uv_layers.active:merged.data.uv_layers.remove(uv)
 merged.data.uv_layers.active.name='SurfaceUV';merged.data.uv_layers.active.active_render=True
 merged['collision_role']='target_only' if name=='SapKnot' else 'static_concave'
 merged.data.calc_loop_triangles();stats.append({'name':name,'triangles':len(merged.data.loop_triangles),'vertices':len(merged.data.vertices),'materials':len(merged.data.materials),'source_parts':len(originals)});exported.append(merged)
for ob in anchors:
 name=ob.name;ob.name='Source_'+name;cp=bpy.data.objects.new(name,None);export_col.objects.link(cp);cp.parent=export_root;cp.matrix_world=ob.matrix_world.copy();exported.append(cp)
bpy.ops.object.select_all(action='DESELECT')
for ob in exported:ob.select_set(True)
bpy.context.view_layer.objects.active=export_root
glb=OUT/'root_buttress_h10_p11.glb'
bpy.ops.export_scene.gltf(filepath=str(glb),export_format='GLB',use_selection=True,export_apply=True,export_yup=True,export_extras=True,export_texcoords=True,export_normals=True,export_materials='EXPORT',export_cameras=False,export_lights=False,export_animations=False)
assert all(sha(ROOT/f'assets/v3/root_buttress/root_buttress_h{h}.glb')==v for h,v in runtime.items())
result={'stage':'P11 standalone H10 candidate, pending same-byte reimport and real game camera','source_sha256':sha(source),'ready_source_sha256':sha(ready),'ready_source':str(ready.relative_to(ROOT)).replace('\\','/'),'glb':str(glb.relative_to(ROOT)).replace('\\','/'),'glb_sha256':sha(glb),'bytes':glb.stat().st_size,'runtime_meshes':stats,'atlas_maps':maps,'sap_maps':sap_maps,'source_geometry_unchanged_through_bake':True,'runtime_P2_sha256':runtime,'limits':['single height only','candidate not final artistic acceptance','no performance or full Crown sweep']}
(HERE/'p11_export_report.json').write_text(json.dumps(result,ensure_ascii=False,indent=2),encoding='utf-8');print('P11_EXPORT '+json.dumps(result,ensure_ascii=False),flush=True)
