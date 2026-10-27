"""Measure the 12 reported pairs by independent double-precision clipping."""
from pathlib import Path
import json,numpy as np
OUT=Path(__file__).resolve().parent
raw=np.load(OUT/'upper_cut_mesh_arrays.npz');v=raw['vertices'];tris=raw['triangles']
audit=json.loads((OUT/'upper_coplanar_audit.json').read_text())
def orient(a,b,c):return (b[0]-a[0])*(c[1]-a[1])-(b[1]-a[1])*(c[0]-a[0])
def intersection(subject,clip):
    polygon=list(subject);sign=1 if orient(*clip)>0 else -1
    for a,b in zip(clip,clip[1:]+clip[:1]):
        result=[]
        for p,q in zip(polygon,polygon[1:]+polygon[:1]):
            dp=orient(a,b,p)*sign;dq=orient(a,b,q)*sign
            if dp>=0:result.append(p)
            if (dp<0<dq) or (dq<0<dp):
                t=dp/(dp-dq);result.append((p[0]+(q[0]-p[0])*t,p[1]+(q[1]-p[1])*t))
        polygon=result
        if not polygon:break
    return polygon
rows=[]
for pair in audit['overlaps']:
    points=[v[tris[i]] for i in pair['triangles']]
    n=np.cross(points[0][1]-points[0][0],points[0][2]-points[0][0]);n/=np.linalg.norm(n)
    drop=int(np.argmax(np.abs(n)));axes=[i for i in range(3) if i!=drop]
    aa,bb=[[tuple(float(p[i]) for i in axes) for p in tri] for tri in points]
    polygon=intersection(aa,bb)
    area=abs(sum(a[0]*b[1]-a[1]*b[0] for a,b in zip(polygon,polygon[1:]+polygon[:1])))*.5/abs(n[drop])
    rows.append({'triangles':pair['triangles'],'clipped_area_m2':area,
        'points_godot':[[[float(p[0]),float(p[2]),float(-p[1])] for p in tri] for tri in points],
        'triangle_areas_m2':[float(np.linalg.norm(np.cross(p[1]-p[0],p[2]-p[0]))*.5) for p in points]})
result={'pairs':rows,'sum_pair_overlap_area_m2':sum(r['clipped_area_m2'] for r in rows),
    'max_pair_overlap_area_m2':max(r['clipped_area_m2'] for r in rows),'raw_source_audit_pass':audit['all_pass'],
    'note':'Pair areas are summed, not union area. No automatic geometry change or tolerance waiver.'}
(OUT/'coplanar_overlap_measurement.json').write_text(json.dumps(result,indent=2),encoding='utf-8')
print(json.dumps({k:v for k,v in result.items() if k!='pairs'}));print([(r['triangles'],r['clipped_area_m2']) for r in rows])
