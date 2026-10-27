"""Distinguish strict penetration from a Boolean face-boundary contact."""
import bpy,json,sys
from pathlib import Path
from mathutils.bvhtree import BVHTree
OUT=Path(__file__).resolve().parent;sys.path.insert(0,str(OUT))
from geometry_checks import strict_self_intersections
checks=[]
def check(name,ok,detail):checks.append({'name':name,'pass':bool(ok),'detail':detail})
def fixture(name,points,expected):
    mesh=bpy.data.meshes.new(name);mesh.from_pydata(points,[],[(0,1,2),(3,4,5)]);mesh.update()
    ob=bpy.data.objects.new(name,mesh);bpy.context.scene.collection.objects.link(ob)
    result=strict_self_intersections(ob)
    check(name,bool(result['strict_crossings'])==expected,result)
    bpy.data.objects.remove(ob,do_unlink=True);bpy.data.meshes.remove(mesh)
fixture('real_two_sided_penetration',[(0,0,0),(2,0,0),(0,2,0),(.5,.5,-1),(.5,.5,1),(1.5,.5,0)],True)
fixture('one_sided_edge_T_contact',[(0,0,0),(2,0,0),(0,2,0),(.5,0,0),(1,0,0),(.5,.5,1)],False)
fixture('coplanar_area_overlap',[(0,0,0),(2,0,0),(0,2,0),(.25,.25,0),(1.25,.25,0),(.25,1.25,0)],True)
fixture('disjoint_triangles',[(0,0,0),(2,0,0),(0,2,0),(3,0,0),(4,0,0),(3,1,0)],False)
source=OUT.parent/'p10/root_shoulder_contact_p10.blend'
bpy.ops.wm.open_mainfile(filepath=str(source));ob=bpy.data.objects['P10_HighShoulder_ContinuousThickCliff']
original=strict_self_intersections(ob,limit=10000,include_coplanar=False)
ids=sorted({i for pair in original['strict_crossings'] for i in pair['triangles']})
check('original_real_defects_still_detected',bool(ids) and not original['truncated_at_limit'],len(original['strict_crossings']))
ob.data.calc_loop_triangles();points=[ob.matrix_world@v.co for v in ob.data.vertices]
tree=BVHTree.FromPolygons(points,[tuple(ob.data.loop_triangles[i].vertices) for i in ids],all_triangles=True)
repair=json.loads((OUT/'measured_surface_repair.json').read_text());exceptions=[]
for row in repair['authorized_bad_source_exceptions']:
    distance=tree.find_nearest(points[row['source_vertex']])[3]
    exceptions.append({'source_vertex':row['source_vertex'],'distance_to_verified_strict_crossing_m':distance,'repair_error_m':row['error_m']})
check('all_12_exceptions_remain_in_real_old_defects',len(exceptions)==12 and all(e['distance_to_verified_strict_crossing_m']<=.02 and e['repair_error_m']<=.06 for e in exceptions),exceptions)
bpy.ops.wm.open_mainfile(filepath=str(OUT/'upper_cut_before_cleanup.blend'))
ob=bpy.data.objects['P10_HighShoulder_ContinuousThickCliff'];result=strict_self_intersections(ob)
check('uncleaned_Exact_output_no_strict_crossing',not result['strict_crossings'],result)
diagnosis=json.loads((OUT/'upper_cut_diagnosis.json').read_text());adjacency=[]
ob.data.calc_loop_triangles()
for pair in diagnosis['before_cleanup_crossings']['strict_crossings']:
    first,second=[ob.data.loop_triangles[i] for i in pair['triangles']]
    a,b=[ob.data.polygons[t.polygon_index] for t in [first,second]]
    adjacency.append({'triangles':pair['triangles'],'polygon_indices':[first.polygon_index,second.polygon_index],
        'shared_polygon_vertices':sorted(set(a.vertices)&set(b.vertices)),
        'shared_polygon_edges':[list(e) for e in set(a.edge_keys)&set(b.edge_keys)]})
report={'checks':checks,'all_pass':all(c['pass'] for c in checks),'old_strict_crossing_pairs':len(original['strict_crossings']),
    'actual_boolean_face_adjacency':adjacency,'scope':'strict penetration vs one-sided boundary contact, not general proof of all self-contact freedom'}
(OUT/'boundary_classification_verification.json').write_text(json.dumps(report,indent=2),encoding='utf-8')
print('BOUNDARY_CLASSIFICATION_VERIFICATION',json.dumps(report),flush=True)
assert report['all_pass'],'Do not accept adjusted classification without its regressions'
