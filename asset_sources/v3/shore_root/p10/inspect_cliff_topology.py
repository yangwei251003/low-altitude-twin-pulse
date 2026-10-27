"""Read-only source defect classification before a bounded mesh cleanup."""
import json
import math
import struct
from collections import defaultdict
from pathlib import Path

OUT = Path(__file__).resolve().parent
PROJECT = OUT.parents[3]
path = PROJECT/'asset_sources/v3/root_buttress/p8/vendor/rock_face_01/rock_face_01_1k.gltf'
g = json.loads(path.read_text())
blob = (path.parent/g['buffers'][0]['uri']).read_bytes()


def acc(index):
    a = g['accessors'][index]
    v = g['bufferViews'][a['bufferView']]
    n = {'SCALAR':1,'VEC3':3}[a['type']]
    code = {5126:'f',5123:'H',5125:'I'}[a['componentType']]
    fmt = struct.Struct('<'+code*n)
    off = v.get('byteOffset',0)+a.get('byteOffset',0)
    stride = v.get('byteStride',fmt.size)
    return [fmt.unpack_from(blob,off+i*stride) for i in range(a['count'])]


p = g['meshes'][0]['primitives'][0]
points = acc(p['attributes']['POSITION'])
indices = [v[0] for v in acc(p['indices'])]
faces = [indices[i:i+3] for i in range(0,len(indices),3)]
unique = {}
weld = [unique.setdefault(tuple(round(v,6) for v in p),len(unique)) for p in points]
edges = defaultdict(list)
for f_id,f in enumerate(faces):
    for a,b in zip(f,f[1:]+f[:1]):
        edges[tuple(sorted([weld[a],weld[b]]))].append(f_id)
out = []
for e,fs in edges.items():
    if len(fs)<=2:
        continue
    records=[]
    for fi in fs:
        v=[points[i] for i in faces[fi]]
        a=[v[1][i]-v[0][i] for i in range(3)]
        b=[v[2][i]-v[0][i] for i in range(3)]
        c=[a[1]*b[2]-a[2]*b[1],a[2]*b[0]-a[0]*b[2],a[0]*b[1]-a[1]*b[0]]
        length=math.sqrt(sum(n*n for n in c))
        records.append({'face_id':fi,'points':v,'area_m2':length/2,'normal':[n/length for n in c] if length else []})
    out.append({'welded_edge':e,'faces':records})
report={'source_original_not_edited':str(path),'nonmanifold_edges':out,'weld_round_decimal_places':6}
(OUT/'cliff_source_topology.json').write_text(json.dumps(report,indent=2),encoding='utf-8')
print(json.dumps(report,indent=2))
