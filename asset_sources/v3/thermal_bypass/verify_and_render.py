"""Reopen editable source, delete its model, import exact final GLB and render it.
No runtime write, no Godot. Preserve CPU2 studio and prove geometric coincidence.
"""
from pathlib import Path
import bpy,json,hashlib,math
from mathutils import Vector
from mathutils.kdtree import KDTree
ROOT=Path(__file__).resolve().parents[3];SRC=Path(__file__).resolve().parent;EVID=SRC/'evidence'
glb=ROOT/'assets/v3/thermal_bypass/thermal_bypass.glb';frozen_sha=hashlib.sha256(glb.read_bytes()).hexdigest()
bpy.ops.wm.open_mainfile(filepath=str(SRC/'thermal_bypass.blend'))
source=bpy.data.collections['Editable_ThermalBypass'];objects=list(source.objects);meshes=[o for o in objects if o.type=='MESH']
checks=[]
def check(n,ok,d=None):checks.append({'name':n,'passed':bool(ok),'detail':d})
check('five_editable_blades',sum(o.name.startswith('FanBlade_') for o in meshes)==5)
check('eight_front_coarse_ribs',sum(o.name.startswith('RadiatorRibFront_') for o in meshes)==8)
check('four_static_guard_spokes',sum(o.name.startswith('FixedGuardSpoke') for o in meshes)==4)
check('two_copper_returns',sum(o.name.startswith('CopperReturn_') for o in meshes)==2)
check('one_explicit_uv_per_source_mesh',all(len(o.data.uv_layers)==1 and o.data.uv_layers.active.name=='SurfaceUV' and o.data.uv_layers.active.active_render for o in meshes))
images=[i for i in bpy.data.images if i.source=='FILE'];check('source_external_textures_present',len(images)==24 and all(Path(bpy.path.abspath(i.filepath)).exists() for i in images),len(images))
points=[];source_triangles=0;deps=bpy.context.evaluated_depsgraph_get()
for o in meshes:
    evaluated=o.evaluated_get(deps);me=evaluated.to_mesh();me.calc_loop_triangles();source_triangles+=len(me.loop_triangles)
    points.extend((o.matrix_world@v.co).copy() for v in me.vertices);evaluated.to_mesh_clear()
tree=KDTree(len(points))
for i,p in enumerate(points):tree.insert(p,i)
tree.balance()
source_bounds=[[min(p[k] for p in points) for k in range(3)],[max(p[k] for p in points) for k in range(3)]]
check('source_tri_budget',source_triangles<=12000,source_triangles)
for o in objects:bpy.data.objects.remove(o,do_unlink=True)
before=set(bpy.data.objects.keys());bpy.ops.import_scene.gltf(filepath=str(glb));imported=[o for o in bpy.data.objects if o.name not in before];ims=[o for o in imported if o.type=='MESH']
actual=[];actual_tri=0;max_distance=0
for o in ims:
    o.data.calc_loop_triangles();actual_tri+=len(o.data.loop_triangles)
    for v in o.data.vertices:
        p=o.matrix_world@v.co;actual.append(p);max_distance=max(max_distance,tree.find(p)[2])
actual_bounds=[[min(p[k] for p in actual) for k in range(3)],[max(p[k] for p in actual) for k in range(3)]]
check('reimport_six_meshes',len(ims)==6)
check('source_reimport_triangle_count',actual_tri==source_triangles,{'source':source_triangles,'reimport':actual_tri})
check('reimport_vertices_on_source',max_distance<.000003,{'max_distance_metres':max_distance,'tolerance':.000003})
check('source_reimport_bounds',max(abs(a-b) for aa,bb in zip(source_bounds,actual_bounds) for a,b in zip(aa,bb))<.000003)
check('glb_sha_before_render',hashlib.sha256(glb.read_bytes()).hexdigest()==frozen_sha)
report={'input_glb':str(glb),'input_sha256':frozen_sha,'source_meshes':len(meshes),'source_triangles':source_triangles,'reimport_triangles':actual_tri,'imported_meshes':[o.name for o in ims],'checks':checks,'passed':sum(c['passed'] for c in checks),'failed':sum(not c['passed'] for c in checks),'scope':'Actual GLB reimport with source geometry distance checks. CPU offline, not Godot/collision/performance.'}
(EVID/'reimport_report.json').write_text(json.dumps(report,ensure_ascii=False,indent=2),encoding='utf-8')
assert report['failed']==0,[c for c in checks if not c['passed']]
scene=bpy.context.scene;scene.render.threads_mode='FIXED';scene.render.threads=2;scene.cycles.device='CPU';scene.cycles.samples=24
scene.render.filepath=str(EVID/'thermal_bypass_glb_front.png');bpy.ops.render.render(write_still=True)
cam=scene.camera;cam.location=(-4,6,3.6);cam.rotation_euler=(Vector((0,0,1))-cam.location).to_track_quat('-Z','Y').to_euler();scene.render.filepath=str(EVID/'thermal_bypass_glb_rear.png');bpy.ops.render.render(write_still=True)
assert hashlib.sha256(glb.read_bytes()).hexdigest()==frozen_sha
report['render_complete']=True;report['rendered_files']=['thermal_bypass_glb_front.png','thermal_bypass_glb_rear.png'];report['sha_unchanged_after_render']=True
(EVID/'reimport_report.json').write_text(json.dumps(report,ensure_ascii=False,indent=2),encoding='utf-8')
print('THERMAL_REIMPORT',json.dumps(report,ensure_ascii=False))
