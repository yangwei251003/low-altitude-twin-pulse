from pathlib import Path
import bpy,bmesh,json
HERE=Path(__file__).resolve().parent
bpy.ops.wm.open_mainfile(filepath=str(HERE/'rising_seal_source_p2.blend'))
out=[]
for name in ['StoneMass_03']:
 o=bpy.data.objects[name];bm=bmesh.new();bm.from_mesh(o.data);edges=[e for e in bm.edges if e.is_boundary];verts=list({v for e in edges for v in e.verts})
 area=(verts[1].co-verts[0].co).cross(verts[2].co-verts[0].co).length*.5 if len(verts)==3 else None
 out.append({'name':name,'boundary_edge_count':len(edges),'vertices_blender':[list(v.co) for v in verts],'triangle_area_m2':area,'edge_lengths':[e.calc_length() for e in edges]});bm.free()
(HERE/'boolean_boundary_diagnostic.json').write_text(json.dumps(out,indent=2)+'\n',encoding='utf-8');print('BOUNDARY_DIAGNOSTIC',json.dumps(out),flush=True)
