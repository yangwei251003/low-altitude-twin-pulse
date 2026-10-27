"""Reopen source, then import actual GLB and probe unobstructed flight paths."""
import bpy,json,hashlib,sys,time
from pathlib import Path
from mathutils import Vector
from mathutils.bvhtree import BVHTree
ROOT=Path(__file__).resolve().parents[3];SRC=ROOT/'asset_sources/v3/overpass';OUT=ROOT/'assets/v3/overpass';EVID=ROOT/'artifacts/v3/art/overpass'
def pos(p):return Vector((p[0],-p[2],p[1]))
def gp(p):return [p.x,p.z,-p.y]
bpy.ops.wm.open_mainfile(filepath=str(SRC/'maintenance_overpass.blend'))
source=[o for o in bpy.data.collections['Editable_Overpass'].objects if o.type=='MESH'];images=[im for im in bpy.data.images if im.source=='FILE' and im.name.startswith('Overpass_')]
checks={'source_editable_parts':len(source)>200,'all_source_uv':all(o.data.uv_layers for o in source),'sixteen_source_maps':len(images)==16,'all_source_maps_resolve':all(Path(bpy.path.abspath(im.filepath)).is_file() for im in images)}
checks['unique_authored_render_uv']=all(len(o.data.uv_layers)==1 and o.data.uv_layers[0].name=='SurfaceUV' and o.data.uv_layers[0].active_render and o.data.uv_layers.active_index==0 for o in source)
source_count=len(source);studio=set(bpy.data.collections['Studio_NotExported'].objects)
for o in list(bpy.data.objects):
 if o not in studio:bpy.data.objects.remove(o,do_unlink=True)
bpy.ops.import_scene.gltf(filepath=str(OUT/'maintenance_overpass.glb'));bpy.context.view_layer.update()
meshes=[o for o in bpy.context.scene.objects if o.type=='MESH' and o not in studio];trees={}
for o in meshes:
 o.data.calc_loop_triangles();trees[o.name]=BVHTree.FromPolygons([o.matrix_world@v.co for v in o.data.vertices],[tuple(t.vertices) for t in o.data.loop_triangles],all_triangles=True)
def hit(a,b):
 start=pos(a);delta=pos(b)-start;length=delta.length;delta.normalize();best=None
 for name,tree in trees.items():
  p,n,index,dist=tree.ray_cast(start,delta,length)
  if p is not None and (best is None or dist<best['distance']):best={'node':name,'position_godot':gp(p),'distance':dist}
 return best
probes=[]
for x in [-9,-5,0,5,9]:
 for y in [-6.5,-4,-1.2]:
  a=[x,y,-6];b=[x,y,6];result=hit(a,b);probes.append({'kind':'central_cross_flight','from':a,'to':b,'hit':result});checks[f'under_cross_{x}_{y}']=result is None
for z in [-4,-2,0,2,4]:
 for y in [-6.5,-4,-1.2]:
  a=[-10,y,z];b=[10,y,z];result=hit(a,b);probes.append({'kind':'central_length_flight','from':a,'to':b,'hit':result});checks[f'under_length_{z}_{y}']=result is None
for x in [-16,-8,0,8,16]:
 for z in [-2,-1,1,2]:
  a=[x,4,z];b=[x,0,z];result=hit(a,b);probes.append({'kind':'work_deck_support','from':a,'to':b,'hit':result});checks[f'deck_support_{x}_{z}']=result is not None and result['node']=='DeckPanels' and abs(result['position_godot'][1]-.4)<.004
for z in [-2,0,2]:
 a=[-17.45,1.2,z];b=[17.45,1.2,z];result=hit(a,b);probes.append({'kind':'above_deck_traverse','from':a,'to':b,'hit':result});checks[f'deck_length_clear_{z}']=result is None
for name,p in {'DeckLanding':[0,1.4,0],'UnderpassEntry':[0,-3.5,6],'UnderpassExit':[0,-3.5,-6]}.items():checks[name+'_position']=(bpy.data.objects[name].matrix_world.translation-pos(p)).length<1e-4
r={'glb_sha256':hashlib.sha256((OUT/'maintenance_overpass.glb').read_bytes()).hexdigest(),'editable_source_meshes':source_count,'source_images':len(images),'checks':checks,'all_checks_pass':all(checks.values()),'probes':probes,'scope':'actual GLB Blender triangle sampling, not a finite-size drone sweep or Godot physics test'}
(EVID/'source_and_clearance.json').write_text(json.dumps(r,ensure_ascii=False,indent=2),encoding='utf-8');print('OVERPASS_CHECKS '+json.dumps({'count':len(checks),'all_pass':r['all_checks_pass'],'failed':[k for k,v in checks.items() if not v]}),flush=True)
if '--no-render' not in sys.argv:
 scene=bpy.context.scene;scene.render.threads_mode='FIXED';scene.render.threads=2;scene.cycles.device='CPU';scene.cycles.samples=20
 views=sys.argv[sys.argv.index('--views')+1].split(',') if '--views' in sys.argv else ['front']
 setups={'front':((33,23,40),(0,-2,0)),'back':((-32,20,-40),(0,-2,0)),'under':((0,-2.5,36),(0,-2.5,0))};renders=[]
 for name in views:
  at,target=setups[name];scene.camera.location=pos(at);scene.camera.rotation_euler=(pos(target)-scene.camera.location).to_track_quat('-Z','Y').to_euler()
  path=EVID/('overpass_glb_preview.png' if name=='front' else f'overpass_glb_{name}.png');scene.render.filepath=str(path)
  start=time.perf_counter();bpy.ops.render.render(write_still=True)
  renders.append({'view':name,'path':str(path.relative_to(ROOT)).replace('\\','/'),'sha256':hashlib.sha256(path.read_bytes()).hexdigest(),'seconds':time.perf_counter()-start,'camera_godot':at,'target_godot':target})
 (EVID/'glb_renders_v4.json').write_text(json.dumps({'glb_sha256':r['glb_sha256'],'source_sha256':hashlib.sha256((SRC/'maintenance_overpass.blend').read_bytes()).hexdigest(),'cpu_threads':2,'samples':20,'resolution':[scene.render.resolution_x,scene.render.resolution_y],'views':renders,'scope':'Actual frozen GLB reimport into Blender; not Godot screenshots or performance evidence'},ensure_ascii=False,indent=2),encoding='utf-8')
if not r['all_checks_pass']:raise RuntimeError('Overpass source/clearance check failed; do not relax thresholds')
