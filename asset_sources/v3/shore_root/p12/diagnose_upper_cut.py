"""Diagnose the few new upper-air Boolean defects without rendering/export."""
from pathlib import Path
HERE=Path(__file__).resolve().parent
code=(HERE/'build_shore_root_p12.py').read_text(encoding='utf-8')
code=code[:code.index("assert report['all_pass'],'Do not render or export failed geometry'")]
needle="bm=bmesh.new();bm.from_mesh(high.data);bmesh.ops.remove_doubles"
code=code.replace(needle,"before_cleanup_topology=topology(high)\nbefore_cleanup_crossings=strict_self_intersections(high)\nbpy.ops.wm.save_as_mainfile(filepath=str(OUT/'upper_cut_before_cleanup.blend'))\n"+needle)
exec(compile(code,str(HERE/'build_shore_root_p12.py'),'exec'))
high.data.calc_loop_triangles()
bad_triangles=sorted({i for pair in crossings['strict_crossings'] for i in pair['triangles']})
tri_rows=[]
for i in bad_triangles:
    t=high.data.loop_triangles[i]
    p=[high.matrix_world@high.data.vertices[j].co for j in t.vertices]
    tri_rows.append({'triangle':i,'vertices':list(t.vertices),'points_godot':[list(gp(v)) for v in p],
        'edge_lengths_m':[(p[k]-p[(k+1)%3]).length for k in range(3)],
        'area_m2':(p[1]-p[0]).cross(p[2]-p[0]).length*.5})
bm=bmesh.new();bm.from_mesh(high.data);bm.verts.ensure_lookup_table();bm.faces.ensure_lookup_table()
bad_edges=[{'vertices':[v.index for v in e.verts],
    'points_godot':[list(gp(high.matrix_world@v.co)) for v in e.verts],
    'length_m':e.calc_length(),'face_count':len(e.link_faces)} for e in bm.edges if not e.is_manifold]
bm.free()
diagnosis={'before_cleanup_topology':before_cleanup_topology,'before_cleanup_crossings':before_cleanup_crossings,
    'after_cleanup_topology':topology(high),'after_cleanup_crossings':crossings,
    'bad_edges':bad_edges,'bad_triangles':tri_rows,'stage':'diagnostic only, no accepted source or image'}
(OUT/'upper_cut_diagnosis.json').write_text(json.dumps(diagnosis,indent=2),encoding='utf-8')
bpy.ops.wm.save_as_mainfile(filepath=str(OUT/'upper_cut_diagnostic.blend'))
print('UPPER_CUT_DIAGNOSIS',json.dumps(diagnosis),flush=True)
