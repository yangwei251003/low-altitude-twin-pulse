"""Bake explicit UV/PBR maps and export only the standalone P12 candidate."""
import bpy,hashlib,json,struct,sys
from pathlib import Path
HERE=Path(__file__).resolve().parent;PROJECT=HERE.parents[3];sys.path.insert(0,str(HERE))
from bake_pbr_atlas import bake_pbr
OUT=PROJECT/'assets/v3/candidates/shore_root_t03a_p12';TEX=HERE/'textures'
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
prior=json.loads((HERE/'p12_retopology_report.json').read_text());source=HERE/'shore_root_t03a_p12_pbr_author.blend'
assert prior['all_pass'] and sha(source)==prior['author_sha256']
ready=HERE/'shore_root_t03a_p12_export_ready.blend'
bpy.ops.wm.open_mainfile(filepath=str(ready if '--export-only' in sys.argv else source))
scene=bpy.context.scene;root=bpy.data.objects['ShoreRootT03A'];parts=[o for o in root.children if o.type=='MESH']
def digest(ob):
 h=hashlib.sha256();h.update(struct.pack('<16d',*(v for row in ob.matrix_world for v in row)))
 for v in ob.data.vertices:h.update(struct.pack('<3d',*v.co))
 for f in ob.data.polygons:h.update(struct.pack('<'+str(len(f.vertices))+'I',*f.vertices))
 return h.hexdigest()
before={o.name:digest(o) for o in parts}
scene.render.threads_mode='FIXED';scene.render.threads=2;scene.cycles.device='CPU'
if '--export-only' in sys.argv:
 baked_report=json.loads((HERE/'p12_bake_report.json').read_text());assert sha(ready)==baked_report['ready_sha256'];maps=baked_report['maps']
else:
 materials={'stone':bpy.data.objects['Rock_HighShoulder'].data.materials[0],'bark':bpy.data.objects['Root_MainFork'].data.materials[0]}
 _,maps=bake_pbr(scene,parts,materials,TEX,'t03a_p12')
 assert before=={o.name:digest(o) for o in parts}
 scene.cycles.samples=12;bpy.ops.wm.save_as_mainfile(filepath=str(ready))
 baked_report={'source_sha256':sha(source),'ready_sha256':sha(ready),'maps':maps,'geometry_unchanged':True,'material_count':2}
 (HERE/'p12_bake_report.json').write_text(json.dumps(baked_report,ensure_ascii=False,indent=2),encoding='utf-8')
if '--bake-only' in sys.argv:print('P12_BAKE_ONLY_COMPLETE',flush=True);sys.exit(0)
OUT.mkdir(parents=True,exist_ok=True)
col=bpy.data.collections.new('P12_EXPLICIT_EXPORT_COPIES');scene.collection.children.link(col)
root.name='Source_ShoreRootT03A';export_root=bpy.data.objects.new('ShoreRootT03A',None);col.objects.link(export_root)
export_root['asset_version']='T03A-shore-root-p12-candidate';export_root['coordinate_system']='Godot metres, source Z up converted explicitly'
exported=[export_root];stats=[]
for name,group in [('RockMasses',[o for o in parts if o.name.startswith('Rock_')]),('LivingRoots',[bpy.data.objects['Root_MainFork']])]:
 bpy.ops.object.select_all(action='DESELECT');copies=[]
 for ob in group:
  cp=ob.copy();cp.data=ob.data.copy();cp.parent=None;cp.matrix_world=ob.matrix_world.copy();col.objects.link(cp);cp.select_set(True);copies.append(cp)
 bpy.context.view_layer.objects.active=copies[0]
 if len(copies)>1:bpy.ops.object.join()
 merged=bpy.context.object;merged.name=name;merged.parent=export_root;bpy.ops.object.transform_apply(location=True,rotation=True,scale=True)
 active=merged.data.uv_layers.active
 for uv in list(merged.data.uv_layers):
  if uv!=active:merged.data.uv_layers.remove(uv)
 active.name='SurfaceUV';active.active_render=True
 merged['collision_role']='static_concave_actual_mesh';merged.data.calc_loop_triangles()
 stats.append({'name':name,'triangles':len(merged.data.loop_triangles),'vertices':len(merged.data.vertices),'materials':len(merged.data.materials),'editable_source_parts':len(group)})
 exported.append(merged)
anchors={}
for name in ['GroundOrigin','BridgeJoin','WestBlend']:
 ob=bpy.data.objects[name];ob.name='Source_'+name;cp=bpy.data.objects.new(name,None);col.objects.link(cp);cp.parent=export_root;cp.matrix_world=ob.matrix_world.copy();exported.append(cp)
 p=cp.matrix_world.translation;anchors[name]=[p.x,p.z,-p.y]
bpy.ops.object.select_all(action='DESELECT')
for ob in exported:ob.select_set(True)
bpy.context.view_layer.objects.active=export_root
glb=OUT/'shore_root_t03a.glb'
bpy.ops.export_scene.gltf(filepath=str(glb),export_format='GLB',use_selection=True,export_apply=True,export_yup=True,export_extras=True,export_texcoords=True,export_normals=True,export_materials='EXPORT',export_cameras=False,export_lights=False,export_animations=False)
assert sha(source)==prior['author_sha256']
result={'stage':'standalone candidate pending real-byte reimport and root game-camera review','glb':str(glb),'sha256':sha(glb),'bytes':glb.stat().st_size,'ready_source_sha256':sha(ready),'source_sha256':sha(source),'mesh_stats':stats,'anchors_godot':anchors,'atlas_maps':maps,'bake_geometry_unchanged':True}
(HERE/'p12_export_report.json').write_text(json.dumps(result,ensure_ascii=False,indent=2),encoding='utf-8')
print('P12_CANDIDATE_EXPORTED '+json.dumps(result,ensure_ascii=False),flush=True)
