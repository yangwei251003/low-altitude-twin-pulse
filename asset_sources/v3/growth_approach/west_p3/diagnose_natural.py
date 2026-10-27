import bpy,bmesh,sys,json
from pathlib import Path
from mathutils import Vector
B=Path(__file__).resolve().parent;sys.path.insert(0,str(B))
from geometry_checks import strict_self_intersections
def bl(p):return Vector((p[0],-p[2],p[1]))
bpy.ops.wm.open_mainfile(filepath=str(B.parent/'west_p2/growth_approach_west_p2.blend'))
source=bpy.data.objects['OriginalNaturalFork_SourceCoordinates']
reports=[strict_self_intersections(source)]
ob=source.copy();ob.data=source.data.copy();bpy.context.scene.collection.objects.link(ob);ob.name='Pruned_Original_No_Deformation'
bm=bmesh.new();bm.from_mesh(ob.data)
for point,normal in [((-.6,0,0),(-1,0,0)),((.4,0,0),(1,0,0))]:
 cut=bmesh.ops.bisect_plane(bm,geom=list(bm.verts)+list(bm.edges)+list(bm.faces),plane_co=bl(point),plane_no=bl(normal),dist=1e-6,clear_outer=True)
 edges=[e for e in cut['geom_cut'] if isinstance(e,bmesh.types.BMEdge) and e.is_boundary]
 if edges:bmesh.ops.holes_fill(bm,edges=edges,sides=0)
bmesh.ops.recalc_face_normals(bm,faces=list(bm.faces));bm.to_mesh(ob.data);bm.free()
reports.append(strict_self_intersections(ob))
for report,obj in zip(reports,[source,ob]):
 obj.data.calc_loop_triangles()
 for example in report['examples']:
  example['vertices_godot_source']=[[[float(obj.data.vertices[i].co.x),float(obj.data.vertices[i].co.z),float(-obj.data.vertices[i].co.y)] for i in obj.data.loop_triangles[t].vertices] for t in example['triangles']]
(B/'natural_source_intersection_diagnosis.json').write_text(json.dumps(reports,indent=2),encoding='utf8')
print(json.dumps([{k:v for k,v in q.items() if k!='examples'} for q in reports]))
