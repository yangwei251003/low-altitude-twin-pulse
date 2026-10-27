"""One deterministic read-only replay of the frozen failing P6 script.
Only diagnostic.json/log are written. No render, source save, or parameter edit.
"""
from pathlib import Path
import hashlib
HERE=Path(__file__).resolve().parent
original=HERE/'build_side_study.py'
text=original.read_text(encoding='utf-8')
original_sha=hashlib.sha256(original.read_bytes()).hexdigest()
text=text.replace("HERE/'side_report.json'","HERE/'diagnostic.json'")
needle="bmesh.ops.delete(bm,geom=chosen,context='FACES_ONLY')"
before='''
pre_edges=[]
for i,v in enumerate(loop):
 w=loop[(i+1)%N];es=[e for e in v.link_edges if e.other_vert(v)==w]
 pre_edges.append({'index':i,'coords_local_godot':[list(gp(v.co)),list(gp(w.co))],'coords_blender':[list(v.co),list(w.co)],'length_m':float((w.co-v.co).length),'input_edge_count':len(es),'before_old_faces':sum(f not in cs for e in es for f in e.link_faces),'before_removed_faces':sum(f in cs for e in es for f in e.link_faces)})
'''
assert text.count(needle)==1;text=text.replace(needle,before+needle)
needle="require('all_boundary_edges_shared_old_and_new_faces',all(shared),{'edges':N,'failed':[i for i,q in enumerate(shared) if not q]})"
replacement='''
used_pairs={tuple(sorted((f[j],f[(j+1)%len(f)]))) for f in outf for j in range(len(f))}
cdt_pairs={tuple(sorted(e)) for e in oute}
def diagnostic_line_distance(p,a,b):
 ab=b-a
 if ab.length_squared<1e-20:return float((p-a).length),0.0
 t=float((p-a).dot(ab)/ab.length_squared)
 return float((p-(a+ab*t)).length),t
rows=[]
for i,pre in enumerate(pre_edges):
 v=loop[i];w=loop[(i+1)%N];es=[e for e in v.link_edges if e.other_vert(v)==w]
 oi,oj=boundary_map[i],boundary_map[(i+1)%N];pair=tuple(sorted((oi,oj)))
 face_ids=[fi for fi,f in enumerate(outf) if pair in {tuple(sorted((f[j],f[(j+1)%len(f)]))) for j in range(len(f))}]
 row=dict(pre);row.update({'after_edge_count':len(es),'after_old_faces':sum(f not in newset for e in es for f in e.link_faces),'after_new_faces':sum(f in newset for e in es for f in e.link_faces),'after_total_faces':sum(len(e.link_faces) for e in es),'passes_original_gate':shared[i],'CDT_output_vertex_ids':[oi,oj],'CDT_orig_vertex_ids':[origv[oi],origv[oj]],'CDT_has_direct_edge':pair in cdt_pairs,'CDT_direct_edge_output_face_ids':face_ids,'CDT_direct_edge_output_face_count':len(face_ids),'CDT_output_2d':[list(outv[oi]),list(outv[oj])],'input_2d':[list(uv[i]),list(uv[(i+1)%N])]})
 spans=[]
 for a,b in used_pairs:
  if (a,b)==pair:continue
  da,ta=diagnostic_line_distance(outv[oi],outv[a],outv[b]);db,tb=diagnostic_line_distance(outv[oj],outv[a],outv[b])
  if max(da,db)<1e-5 and min(ta,tb)>-1e-5 and max(ta,tb)<1+1e-5:
   spans.append({'output_edge':[a,b],'orig_vertex_ids':[origv[a],origv[b]],'endpoint_line_distances_2d_m':[da,db],'line_parameters':[ta,tb],'output_face_ids':[fi for fi,f in enumerate(outf) if a in f and b in f]})
 row['output_face_long_edges_covering_segment_2d']=spans
 rows.append(row)
failed=[r for r in rows if not r['passes_original_gate']]
report['diagnostic_all_edges']=rows
report['diagnostic_failed_edges']=failed
report['original_recorded_failed_indices']=json.loads((HERE/'side_report.json').read_text(encoding='utf-8'))['checks'][-1]['detail']['failed']
report['diagnostic_failed_indices']=[r['index'] for r in failed]
report['reproduces_original_failed_indices']=report['diagnostic_failed_indices']==report['original_recorded_failed_indices']
report['frozen_failure_script_sha256']=sha(HERE/'build_side_study.py')
report['diagnostic_scope']='One in-memory replay. No render/source save/geometry parameter change. The frozen failure script and inputs remain unchanged.'
write_report()
print('DIAGNOSTIC_FAILED',len(failed),'reproduces',report['reproduces_original_failed_indices'],flush=True)
for r in failed:print(json.dumps(r,ensure_ascii=False),flush=True)
assert all(sha(Path(p))==h for p,h in frozen.items())
raise SystemExit(0)
'''
assert text.count(needle)==1;text=text.replace(needle,replacement)
compile(text,str(original),'exec')
exec(compile(text,str(original),'exec'),{'__file__':str(original),'__name__':'__main__'})
