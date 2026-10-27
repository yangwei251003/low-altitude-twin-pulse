"""Independent double-precision segment/triangle check of saved mesh evidence."""
import json
from pathlib import Path
OUT=Path(__file__).resolve().parent
source=json.loads((OUT/'boolean_crossing_diagnosis.json').read_text())
def sub(a,b):return [x-y for x,y in zip(a,b)]
def dot(a,b):return sum(x*y for x,y in zip(a,b))
def cross(a,b):return [a[1]*b[2]-a[2]*b[1],a[2]*b[0]-a[0]*b[2],a[0]*b[1]-a[1]*b[0]]
result={}
for key,value in source.items():
    rows=[]
    for pair in value['strict_crossings']:
        a,b=[g['godot_points'] for g in pair['geometry']];hits=[]
        for tri,other in [(a,b),(b,a)]:
            for p,q in zip(tri,tri[1:]+tri[:1]):
                d=sub(q,p);e1=sub(other[1],other[0]);e2=sub(other[2],other[0]);h=cross(d,e2);det=dot(e1,h)
                if abs(det)<1e-14:continue
                s=sub(p,other[0]);u=dot(s,h)/det;qq=cross(s,e1);v=dot(d,qq)/det;t=dot(e2,qq)/det
                if 0<u<1 and 0<v<1 and u+v<1 and 0<t<1:hits.append({'u':u,'v':v,'segment_t':t})
        rows.append({'triangles':pair['triangles'],'strict_interior_hits':hits})
    result[key]={'checked_pairs':len(rows),'confirmed_pairs':sum(bool(r['strict_interior_hits']) for r in rows),'rows':rows}
(OUT/'boolean_crossing_double_precision.json').write_text(json.dumps(result,indent=2),encoding='utf-8')
print({key:(r['confirmed_pairs'],r['checked_pairs']) for key,r in result.items()})
