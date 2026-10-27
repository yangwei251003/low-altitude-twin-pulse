"""Reopen editable source, independently import GLB, test real triangles and render.
No Godot invocation; does not change the exported asset or editable source.
"""
import bpy,json,math,hashlib
from pathlib import Path
from mathutils import Vector,Matrix
from mathutils.bvhtree import BVHTree
ROOT=Path(__file__).resolve().parents[3]
SRC=ROOT/'asset_sources/v3/whale';OUT=ROOT/'assets/v3/whale';EVID=ROOT/'artifacts/v3/art/whale'
def pos(p):return Vector((p[0],-p[2],p[1]))
def godot(p):return [float(p.x),float(p.z),float(-p.y)]
def near(a,b):return (Vector(a)-Vector(b)).length<1e-4
bpy.ops.wm.open_mainfile(filepath=str(SRC/'siphon_whale.blend'))
source_meshes=[o for o in bpy.data.collections['Editable_Whale'].objects if o.type=='MESH']
source_images=[i for i in bpy.data.images if i.source=='FILE' and i.name.startswith('Whale_')]
source={'editable_mesh_count':len(source_meshes),'all_meshes_have_uv':all(len(o.data.uv_layers)>0 for o in source_meshes),'texture_count':len(source_images),'missing_textures':[i.filepath for i in source_images if not Path(bpy.path.abspath(i.filepath)).exists()],'source_sha256':hashlib.sha256((SRC/'siphon_whale.blend').read_bytes()).hexdigest()}
source['closed_pivots']=all(bpy.data.objects[n].rotation_euler.to_matrix().is_identity for n in ['PortHatchPivot','StarboardHatchPivot'])
studio=bpy.data.collections['Studio_NotExported'];studio_objects=set(studio.objects)
for o in list(bpy.data.objects):
 if o not in studio_objects:bpy.data.objects.remove(o,do_unlink=True)
bpy.ops.import_scene.gltf(filepath=str(OUT/'siphon_whale.glb'))
asset_objects=[o for o in bpy.context.scene.objects if o not in studio_objects]
meshes=[o for o in asset_objects if o.type=='MESH']
non_glow=[o for o in meshes if not o.name.endswith('Glow')]
markers=['CoreWeakpoint','PortWeakpoint','StarboardWeakpoint','AttackOrigin','RetryEntry','RawCommandRecordAnchor']
expected={'CoreWeakpoint':[0,2.02,3.1],'PortWeakpoint':[-7,.65,0],'StarboardWeakpoint':[7,.65,0],'AttackOrigin':[0,-.2,6.9],'RetryEntry':[-28,-.8,14],'RawCommandRecordAnchor':[0,3.05,3.1]}
checks={'source_has_editable_parts':source['editable_mesh_count']>100,'source_uv_complete':source['all_meshes_have_uv'],'source_24_maps_readable':source['texture_count']==24 and not source['missing_textures'],'source_saved_closed':source['closed_pivots']}
bpy.context.view_layer.update()
for n in markers:checks[n+'_imported_position']=near(bpy.data.objects[n].matrix_world.translation,pos(expected[n]))

def trees(objects):
 deps=bpy.context.evaluated_depsgraph_get();result={}
 for o in objects:
  e=o.evaluated_get(deps);me=e.to_mesh();me.calc_loop_triangles()
  result[o.name]=BVHTree.FromPolygons([e.matrix_world@v.co for v in me.vertices],[tuple(t.vertices) for t in me.loop_triangles],all_triangles=True)
  e.to_mesh_clear()
 return result
def hit(start,end,ts):
 s=pos(start);d=pos(end)-s;distance=d.length;d.normalize();best=None
 for name,t in ts.items():
  p,n,index,dist=t.ray_cast(s,d,distance)
  if p is not None and (best is None or dist<best['distance']):best={'mesh':name,'distance':float(dist),'point_godot':godot(p)}
 return best
probes={}
for n in ['CoreWeakpoint','PortWeakpoint','StarboardWeakpoint']:
 p=expected[n];probes[n+'_vertical']={'from':[p[0],p[1]+5,p[2]],'to':p}
for n,start in [('CoreWeakpoint',[0,4.5,9]),('PortWeakpoint',[-10,3,5]),('StarboardWeakpoint',[10,3,5])]:probes[n+'_oblique']={'from':start,'to':expected[n]}
closed_trees=trees(non_glow)
closed={n:hit(p['from'],p['to'],closed_trees) for n,p in probes.items()}
target_mesh={'CoreWeakpoint':'CoreShield','PortWeakpoint':'PortHatch','StarboardWeakpoint':'StarboardHatch'}
clearance={}
for n,m in target_mesh.items():
 p=pos(expected[n]);q,normal,index,dist=closed_trees[m].find_nearest(p)
 up=hit(expected[n],[expected[n][0],expected[n][1]+4,expected[n][2]],{m:closed_trees[m]})
 clearance[n]={'closed_cover_mesh':m,'nearest_cover_distance_m':float(dist),'nearest_cover_point_godot':godot(q),'vertical_cover_distance_m':up['distance'] if up else None,'suggested_max_sphere_radius_with_20pct_margin':float(dist)*.8}
 for kind in ['vertical','oblique']:
  h=closed[n+'_'+kind];checks[n+'_'+kind+'_closed_hits_cover']=h is not None and h['mesh']==m
def bounds(o):
 ps=[o.matrix_world@v.co for v in o.data.vertices];gs=[godot(p) for p in ps]
 return {'min':[min(p[k] for p in gs) for k in range(3)],'max':[max(p[k] for p in gs) for k in range(3)]}
closed_bounds={o.name:bounds(o) for o in meshes}
closed_transforms={n:[list(row) for row in bpy.data.objects[n].matrix_world] for n in ['SiphonWhale','PortHatchPivot','StarboardHatchPivot','CoreShield']}
for n,deg in [('PortHatchPivot',-68),('StarboardHatchPivot',68)]:
 o=bpy.data.objects[n];pivot=o.matrix_world.translation.copy();o.matrix_world=Matrix.Translation(pivot)@Matrix.Rotation(math.radians(deg),4,pos((0,0,1)))@Matrix.Translation(-pivot)@o.matrix_world
bpy.data.objects['CoreShield'].matrix_world.translation+=pos((0,.30,-3.2))
bpy.context.view_layer.update()
opened_trees=trees(non_glow);opened={n:hit(p['from'],p['to'],opened_trees) for n,p in probes.items()}
for n in probes:checks[n+'_open_no_metal_occluder']=opened[n] is None
opened_bounds={o.name:bounds(o) for o in meshes}
for n in ['PortHatch','StarboardHatch']:checks[n+'_actually_raised']=opened_bounds[n]['max'][1]>closed_bounds[n]['max'][1]+1
checks['static_hull_unchanged']=closed_bounds['StaticHull']==opened_bounds['StaticHull']
report={'glb_sha256':hashlib.sha256((OUT/'siphon_whale.glb').read_bytes()).hexdigest(),'blender':bpy.app.version_string,'source':source,'markers_godot':expected,'closed_imported_world_matrices_blender_z_up':closed_transforms,'probes_godot':probes,'closed_ray_hits':closed,'opened_ray_hits':opened,'closed_cover_clearance':clearance,'closed_mesh_bounds_godot':closed_bounds,'open_mesh_bounds_godot':opened_bounds,'checks':checks,'all_checks_pass':all(checks.values()),'scope':'Actual GLB reimport and triangle rays in Blender. Not Godot collision, human play, or game performance.'}
(EVID/'glb_motion_verification.json').write_text(json.dumps(report,ensure_ascii=False,indent=2),encoding='utf-8')
print('GLB_STATE_CHECK '+json.dumps({'checks':checks,'clearance':clearance,'all_pass':report['all_checks_pass']}))
# Render the actual reimport, so source-only geometry cannot hide export problems.
scene=bpy.context.scene;scene.render.threads_mode='FIXED';scene.render.threads=2
scene.cycles.device='CPU';scene.cycles.samples=20
scene.render.filepath=str(EVID/'siphon_whale_glb_open.png');bpy.ops.render.render(write_still=True)
for n,m in closed_transforms.items():bpy.data.objects[n].matrix_world=Matrix(m)
bpy.context.view_layer.update();scene.render.filepath=str(EVID/'siphon_whale_glb_closed.png');bpy.ops.render.render(write_still=True)
print('ACTUAL_GLB_VERIFICATION_COMPLETE')
if not report['all_checks_pass']:raise RuntimeError('Actual GLB verification failed; inspect report, do not relax thresholds.')
