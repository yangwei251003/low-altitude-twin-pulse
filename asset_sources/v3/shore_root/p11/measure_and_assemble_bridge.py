"""Read-only assembly of P10 and the frozen real root-arch GLB.

Measures the actual X=4.5 face, not its AABB. All writes stay in p11. With
--render, makes one image using the unchanged P10 camera and studio.
"""
import bpy
import hashlib
import json
import math
import sys
from pathlib import Path
from mathutils import Vector
from mathutils.bvhtree import BVHTree
import numpy as np

OUT = Path(__file__).resolve().parent
PROJECT = OUT.parents[3]
P10 = OUT.parent/'p10/root_shoulder_contact_p10.blend'
GLB = PROJECT/'assets/v3/root_arch/f1_root_arch.glb'
EXPECTED_GLB_SHA = 'a14fd39f649ddd00cf2316126349b841376334879022e6c9256b6ed323ddd581'
sha = lambda p: hashlib.sha256(p.read_bytes()).hexdigest()
before = {'p10_blend':sha(P10),'root_arch_glb':sha(GLB)}
assert before['root_arch_glb']==EXPECTED_GLB_SHA
bpy.ops.wm.open_mainfile(filepath=str(P10))
scene = bpy.context.scene
camera_matrix = scene.camera.matrix_world.copy()
camera_size = scene.camera.data.ortho_scale
high = bpy.data.objects['P10_HighShoulder_ContinuousThickCliff']
candidate_meshes = [o for o in bpy.data.objects if o.type=='MESH'
                    and o.name.startswith('P10_') and not o.hide_render
                    and any(c.name=='P10_RootAndStone_ContactCandidate' for c in o.users_collection)]


def bp(p):
    return Vector((p[0],-p[2],p[1]))


def gp(p):
    return Vector((p.x,p.z,-p.y))


def tree(objects):
    points=[]
    faces=[]
    for ob in objects:
        ob.data.calc_loop_triangles()
        off=len(points)
        points.extend(ob.matrix_world@v.co for v in ob.data.vertices)
        faces.extend(tuple(off+i for i in t.vertices) for t in ob.data.loop_triangles)
    return BVHTree.FromPolygons(points,faces,all_triangles=True)


def bounds(objects):
    ps=[gp(ob.matrix_world@v.co) for ob in objects for v in ob.data.vertices]
    return {'min':[min(p[i] for p in ps) for i in range(3)],
            'max':[max(p[i] for p in ps) for i in range(3)]}


high.data.calc_loop_triangles()
plane_triangles=[]
area=0.0
normal_sum=Vector((0,0,0))
for t in high.data.loop_triangles:
    vs=[gp(high.matrix_world@high.data.vertices[i].co) for i in t.vertices]
    cross=(vs[1]-vs[0]).cross(vs[2]-vs[0])
    if all(abs(v.x-4.5)<2e-5 for v in vs) and cross.length>1e-10 and cross.normalized().x>.98:
        plane_triangles.append(vs)
        area+=cross.length*.5
        normal_sum+=cross
assert plane_triangles, 'No actual outward X=4.5 face found'
plane_points=[p for t in plane_triangles for p in t]
plane_bounds={'min':[min(p[i] for p in plane_points) for i in range(3)],
              'max':[max(p[i] for p in plane_points) for i in range(3)]}

# Triangles, not a rectangular AABB, decide which surface samples exist.
step=.04
ys=np.arange(plane_bounds['min'][1]+step*.5,plane_bounds['max'][1],step)
zs=np.arange(plane_bounds['min'][2]+step*.5,plane_bounds['max'][2],step)
mask=np.zeros((len(ys),len(zs)),dtype=bool)
for tri in plane_triangles:
    a,b,c=[np.array([v.y,v.z],dtype=float) for v in tri]
    lo=np.minimum(np.minimum(a,b),c); hi=np.maximum(np.maximum(a,b),c)
    y0=max(0,int(np.searchsorted(ys,lo[0]))-1);y1=min(len(ys),int(np.searchsorted(ys,hi[0]))+1)
    z0=max(0,int(np.searchsorted(zs,lo[1]))-1);z1=min(len(zs),int(np.searchsorted(zs,hi[1]))+1)
    yy,zz=np.meshgrid(ys[y0:y1],zs[z0:z1],indexing='ij')
    den=(b[1]-c[1])*(a[0]-c[0])+(c[0]-b[0])*(a[1]-c[1])
    if abs(den)<1e-12:
        continue
    u=((b[1]-c[1])*(yy-c[0])+(c[0]-b[0])*(zz-c[1]))/den
    v=((c[1]-a[1])*(yy-c[0])+(a[0]-c[0])*(zz-c[1]))/den
    mask[y0:y1,z0:z1] |= (u>=-1e-7)&(v>=-1e-7)&(u+v<=1+1e-7)

existing=set(bpy.data.objects)
bpy.ops.import_scene.gltf(filepath=str(GLB))
imported=[o for o in bpy.data.objects if o not in existing]
roots=[o for o in imported if o.parent not in imported]
assert len(roots)==1 and roots[0].name=='F1RootArch', [o.name for o in roots]
# Shore at world(-24.5,0,-6), bridge at world(0,0,-6). Keeping the shore
# local frame makes the actual bridge root (+24.5,0,0), no rotation/scale.
roots[0].location += bp((24.5,0,0))
bpy.context.view_layer.update()
west=next(o for o in imported if o.name=='EntryWest')
assert (gp(west.matrix_world.translation)-Vector((4.5,4.5,0))).length<1e-5
solid_meshes=[o for o in imported if o.type=='MESH' and o.name in ('WalkableRoot','StoneRemnants')]
assert len(solid_meshes)==2
all_bridge_meshes=[o for o in imported if o.type=='MESH']
solid_tree=tree(solid_meshes)
candidate_tree=tree(candidate_meshes)
camera_direction=scene.camera.matrix_world.to_quaternion()@Vector((0,0,1))
camera_direction.normalize()
samples=[]
for yi,zi in zip(*np.where(mask)):
    y,z=float(ys[yi]),float(zs[zi])
    if y<0:
        continue
    point=bp((4.5,y,z))
    # The original camera is orthographic: all view rays are parallel.
    own_hit=candidate_tree.ray_cast(point+camera_direction*.004,camera_direction,100)
    baseline_visible=own_hit[0] is None
    outward=solid_tree.ray_cast(point-bp((.004,0,0)),bp((1,0,0)),40.1)
    forward_distance=outward[3]-.004 if outward[0] is not None else None
    view_hit=solid_tree.ray_cast(point+camera_direction*.004,camera_direction,100)
    samples.append({'y':y,'z':z,'baseline_visible':baseline_visible,
                    'nearest_bridge_plus_x_m':forward_distance,
                    'bridge_blocks_original_camera':view_hit[0] is not None})
assert samples
visible=[p for p in samples if p['baseline_visible']]
assert visible
counts={}
for distance in [.02,.25,1.0,3.0,40.0]:
    n=sum(p['nearest_bridge_plus_x_m'] is not None and p['nearest_bridge_plus_x_m']<=distance for p in samples)
    counts[str(distance)]={'samples':n,'fraction':n/len(samples),'approx_area_m2':n*step*step}
blocked=sum(p['bridge_blocks_original_camera'] for p in visible)
uncovered=[p for p in visible if not p['bridge_blocks_original_camera']]
bands=[]
for y0,y1 in [(0,1),(1,2),(2,3),(3,4),(4,4.5)]:
    band=[p for p in visible if y0<=p['y']<y1]
    n=sum(p['bridge_blocks_original_camera'] for p in band)
    bands.append({'y_range':[y0,y1],'baseline_visible_samples':len(band),
                  'bridge_occluded_samples':n,'fraction_occluded':n/len(band) if band else None})


def mat(name,colour):
    m=bpy.data.materials.new(name)
    m.use_nodes=True
    node=m.node_tree.nodes.get('Principled BSDF')
    node.inputs['Base Color'].default_value=(*colour,1)
    node.inputs['Roughness'].default_value=.87
    node.inputs['Specular IOR Level'].default_value=.16
    return m


colours={'WalkableRoot':(.285,.225,.165),'StoneRemnants':(.28,.285,.27),
         'Moss':(.17,.23,.14),'Foliage':(.21,.27,.16)}
for ob in all_bridge_meshes:
    m=mat('P11_ReadOnlyBridge_Basic_'+ob.name,colours.get(ob.name,(.3,.3,.3)))
    for i in range(len(ob.data.materials)):
        ob.data.materials[i]=m
    if not ob.data.materials:
        ob.data.materials.append(m)
assert scene.camera.matrix_world==camera_matrix and scene.camera.data.ortho_scale==camera_size
scene.render.filepath=str(OUT/'p10-with-frozen-root-arch.png')
scene.render.engine='CYCLES'
scene.cycles.device='CPU'
scene.cycles.samples=12
scene.render.threads_mode='FIXED'
scene.render.threads=2
scene.render.resolution_x,scene.render.resolution_y=1400,1050
report={
    'scope':'read-only P10 plus actual frozen GLB assembly; no geometry edits, no runtime changes',
    'input_sha256':before,
    'placement':{'shore_world':[-24.5,0,-6],'bridge_world':[0,0,-6],
                 'bridge_in_shore_frame':[24.5,0,0],'actual_entry_west_in_shore_frame':list(gp(west.matrix_world.translation))},
    'large_plane':{'actual_coordinate_x':4.5,'triangle_count':len(plane_triangles),
                   'exact_triangle_area_m2':area,'outward_normal':list(normal_sum.normalized()),'bounds':plane_bounds},
    'collision_meshes_used':['WalkableRoot','StoneRemnants'],
    'actual_bridge_solid_bounds_in_shore_frame':bounds(solid_meshes),
    'sampling':{'spacing_m':step,'above_ground_actual_face_samples':len(samples),
                'sampled_above_ground_area_m2':len(samples)*step*step,
                'baseline_original_camera_visible_samples':len(visible),
                'definition':'sample must lie inside actual face triangle, not only face AABB'},
    'plus_x_geometry_coverage_by_max_distance_m':counts,
    'same_camera_structural_occlusion':{'blocked_samples':blocked,'fraction':blocked/len(visible),
                                       'remaining_exposed_samples':len(uncovered),
                                       'approx_remaining_exposed_area_m2':len(uncovered)*step*step,
                                       'height_bands':bands},
    'camera_unchanged_from_p10':{'matrix_blender':list(map(list,camera_matrix)),
                                'orthographic_size':camera_size,'ray_direction_godot':list(gp(camera_direction))},
    'limits':['Finite 4cm area sampling; not exact analytic union area.',
              'Contact coverage means first actual bridge triangle within stated +X distance, not engine collision.',
              'Camera occlusion uses solid structural meshes only; foliage/moss do not claim physical cover.',
              'Offline static assembly only, no Godot import or moving-body validation.',
              'Original P10 camera retained; full bridge extends outside this local interface study frame.'],
}
output=OUT/'bridge_face_coverage.json'
output.write_text(json.dumps(report,ensure_ascii=False,indent=2),encoding='utf-8')
(OUT/'bridge_face_samples.json').write_text(json.dumps(samples,separators=(',',':')),encoding='utf-8')
scene['P11_Assembly_Coverage']=json.dumps(report,ensure_ascii=False)
bpy.ops.wm.save_as_mainfile(filepath=str(OUT/'p10_bridge_readonly_assembly.blend'))
print('P11_MEASURED '+json.dumps({
    'plane_area':area,'face_bounds':plane_bounds,'plus_x':counts,
    'same_camera_hidden_fraction':blocked/len(visible),'remaining_exposed_area':len(uncovered)*step*step,
    'height_bands':bands}),flush=True)
if '--render' in sys.argv:
    bpy.ops.render.render(write_still=True)
assert before=={'p10_blend':sha(P10),'root_arch_glb':sha(GLB)}
print('P11_SOURCE_UNCHANGED',flush=True)
