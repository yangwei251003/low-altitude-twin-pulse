"""Plain volume reconstruction only; no interface cut, Boolean, render/export."""
import bpy,bmesh,json,sys,hashlib
from pathlib import Path
from mathutils.bvhtree import BVHTree
OUT=Path(__file__).resolve().parent;sys.path.insert(0,str(OUT))
from geometry_checks import strict_self_intersections
SOURCE=OUT.parent/'p10/root_shoulder_contact_p10.blend'
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
before_sha=sha(SOURCE)
bpy.ops.wm.open_mainfile(filepath=str(SOURCE))
ob=bpy.data.objects['P10_HighShoulder_ContinuousThickCliff'];ob.data=ob.data.copy()
def tree():
    ob.data.calc_loop_triangles()
    return BVHTree.FromPolygons([ob.matrix_world@v.co for v in ob.data.vertices],
        [tuple(t.vertices) for t in ob.data.loop_triangles],all_triangles=True)
old=tree();old_points=[ob.matrix_world@v.co for v in ob.data.vertices]
source_bm=bmesh.new();source_bm.from_mesh(ob.data);source_pending=set(source_bm.verts);source_component_count=0
while source_pending:
    source_component_count+=1;stack=[source_pending.pop()]
    while stack:
        v=stack.pop()
        for e in v.link_edges:
            q=e.other_vert(v)
            if q in source_pending:source_pending.remove(q);stack.append(q)
source_bm.free()
root=bpy.data.objects['P10_NaturalMainRoot_TrueCrossSectionCuts']
root_cap=[root.matrix_world@v.co for v in root.data.vertices if abs(v.co.z-.1)<1e-5]
old_triangles=[tuple(t.vertices) for t in ob.data.loop_triangles]
old_crossings=strict_self_intersections(ob,limit=100000)
bad_triangle_ids=sorted({i for row in old_crossings['strict_crossings'] for i in row['triangles']})
bad_vertices={i for ti in bad_triangle_ids for i in old_triangles[ti]}
bad_tree=BVHTree.FromPolygons(old_points,[old_triangles[i] for i in bad_triangle_ids],all_triangles=True) if bad_triangle_ids else None
bpy.ops.object.select_all(action='DESELECT');ob.select_set(True);bpy.context.view_layer.objects.active=ob
ob.data.remesh_voxel_size=.02;ob.data.remesh_voxel_adaptivity=0
ob.data.use_remesh_preserve_volume=False
ob.data.use_remesh_fix_poles=False
bpy.ops.object.voxel_remesh()
bm=bmesh.new();bm.from_mesh(ob.data)
topology={'boundary':sum(e.is_boundary for e in bm.edges),'nonmanifold':sum(not e.is_manifold for e in bm.edges),
          'signed_volume':bm.calc_volume(signed=True)}
pending=set(bm.verts);components=[];component_records=[]
while pending:
    stack=[pending.pop()];n=0;members=[]
    while stack:
        v=stack.pop();n+=1;members.append(v)
        for edge in v.link_edges:
            q=edge.other_vert(v)
            if q in pending:pending.remove(q);stack.append(q)
    components.append(n)
    if n<1000:
        pts=[ob.matrix_world@v.co for v in members];faces={f for v in members for f in v.link_faces}
        gp=lambda p:(p.x,p.z,-p.y)
        distances=[bad_tree.find_nearest(p)[3] for p in pts] if bad_tree else []
        cap_distance=min((p-q).length for p in pts for q in root_cap)
        near_join=any(3.35<=p.x<=4.65 and -.15<=p.z<=4.65 and abs(p.y)<=2.9 for p in pts)
        component_records.append({'vertices':sorted(v.index for v in members),'vertex_count':n,
            'bounds_godot':{'min':[min(gp(p)[i] for p in pts) for i in range(3)],'max':[max(gp(p)[i] for p in pts) for i in range(3)]},
            'surface_area_m2':sum(f.calc_area() for f in faces),
            'nearest_old_self_intersection_min_m':min(distances) if distances else None,
            'nearest_old_self_intersection_max_m':max(distances) if distances else None,
            'distance_to_root_cap_min_m':cap_distance,'intersects_protected_join_zone':near_join,
            'source_component_count':source_component_count})
topology['components']=sorted(components,reverse=True);bm.free()
new=tree();forward=[new.find_nearest(p)[3] for p in old_points]
worst=max(range(len(forward)),key=lambda i:forward[i])
reverse=max(old.find_nearest(ob.matrix_world@v.co)[3] for v in ob.data.vertices)
crossings=strict_self_intersections(ob)
exceptions=[];unrelated=[]
for i,distance in enumerate(forward):
    if distance<=.04:continue
    p=old_points[i];near_bad=bad_tree.find_nearest(p)[3] if bad_tree else None
    row={'source_vertex':i,'point_godot':[p.x,p.z,-p.y],'error_m':distance,
         'on_old_crossing_triangle':i in bad_vertices,'distance_to_old_crossing_triangle_m':near_bad}
    exceptions.append(row)
    if near_bad is None or near_bad>.02 or distance>.06:unrelated.append(row)
p=old_points[worst];q=new.find_nearest(p)[0]
result={'method':'2cm plain voxel; Preserve Volume=false and Fix Poles=false; no Boolean or geometric projection',
        'topology':topology,'triangles':len(ob.data.loop_triangles),'crossings':crossings,
        'old_self_intersection_pairs':len(old_crossings['strict_crossings']),
        'old_self_intersecting_triangle_ids':bad_triangle_ids,
        'small_components':component_records,'source_points_over_4cm':exceptions,
        'points_exceeding_authorized_local_repair_rule':unrelated,
        'source_to_new_sampled_max_m':forward[worst],'new_to_source_sampled_max_m':reverse,
        'worst_source_vertex':worst,'worst_source_point_godot':[p.x,p.z,-p.y],
        'nearest_new_point_godot':[q.x,q.z,-q.y],
        'source_unchanged':sha(SOURCE)==before_sha,'source_sha256':before_sha,
        'not_analytic_hausdorff_bound':True}
result['bounded_source_repair_rule_pass']=not unrelated and reverse<.04
result['all_pass']=topology['boundary']==0 and topology['nonmanifold']==0 and len(components)==1 and not crossings['strict_crossings'] and result['bounded_source_repair_rule_pass']
(OUT/'plain_voxel_diagnosis.json').write_text(json.dumps(result,indent=2),encoding='utf-8')
# Preserve actual unfiltered bytes before any future tiny-shell removal.
bpy.ops.wm.save_as_mainfile(filepath=str(OUT/'plain_voxel_unfiltered.blend'))
result['unfiltered_blend_sha256']=sha(OUT/'plain_voxel_unfiltered.blend')
(OUT/'plain_voxel_diagnosis.json').write_text(json.dumps(result,indent=2),encoding='utf-8')
print('PLAIN_VOXEL',json.dumps({k:v for k,v in result.items() if k not in ['source_points_over_4cm','points_exceeding_authorized_local_repair_rule','old_self_intersecting_triangle_ids']}),flush=True)
