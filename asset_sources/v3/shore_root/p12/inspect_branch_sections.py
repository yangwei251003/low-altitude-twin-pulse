"""Read-only source cross sections to select local branch bases, not global cuts."""
import os
os.environ['OPENBLAS_NUM_THREADS']='1'
os.environ['OMP_NUM_THREADS']='1'
import json, struct
from pathlib import Path
import numpy as np
OUT=Path(__file__).resolve().parent
PROJECT=OUT.parents[3]
PATH=PROJECT/'asset_sources/third_party/island_tree_01/island_tree_01_1k.gltf'
data=json.loads(PATH.read_text())
blob=(PATH.parent/data['buffers'][0]['uri']).read_bytes()
def acc(i):
    a=data['accessors'][i];v=data['bufferViews'][a['bufferView']]
    n={'SCALAR':1,'VEC3':3}[a['type']]
    s=struct.Struct('<'+{5126:'f',5125:'I',5123:'H'}[a['componentType']]*n)
    start=v.get('byteOffset',0)+a.get('byteOffset',0);stride=v.get('byteStride',s.size)
    return np.array([s.unpack_from(blob,start+j*stride) for j in range(a['count'])])
pos=acc(0);faces=acc(3).reshape(-1,3)
pose=json.loads((OUT.parent/'p9/candidate_tip_sections.json').read_text())['pose']
R=np.array(pose['rotation_gltf_to_godot_rows']);pivot=np.array(pose['source_pivot_gltf']);translation=np.array(pose['translated_base_pivot_godot'])
records=[]
for y in [.45,.6,.75,.85,1.0,1.1,1.2,1.3,1.4,1.5,1.65,1.8,2.0]:
    pts=[];links=[];lookup={}
    for face in faces:
        tri=pos[face];cut=[]
        for a,b in zip(tri,np.roll(tri,-1,axis=0)):
            if (a[1]<y)<(b[1]<y) or (a[1]<y)>(b[1]<y):
                p=a+(b-a)*(y-a[1])/(b[1]-a[1]);key=tuple(np.round(p,6))
                if key not in lookup:lookup[key]=len(pts);pts.append(p)
                cut.append(lookup[key])
        if len(cut)==2:links.append(cut)
    adj=[set() for p in pts]
    for a,b in links:adj[a].add(b);adj[b].add(a)
    unseen=set(range(len(pts)));components=[]
    while unseen:
        stack=[unseen.pop()];comp=[]
        while stack:
            i=stack.pop();comp.append(i)
            for j in adj[i]:
                if j in unseen:unseen.remove(j);stack.append(j)
        p=np.array([pts[i] for i in comp]);world=(p-pivot)@R.T*3+translation
        components.append({'n':len(comp),'source_min':p.min(0).tolist(),'source_max':p.max(0).tolist(),
                           'source_mean':p.mean(0).tolist(),'world_mean':world.mean(0).tolist()})
    components.sort(key=lambda c:c['source_mean'][0])
    records.append({'source_y':y,'components':components})
(OUT/'branch_sections.json').write_text(json.dumps(records,indent=2))
for record in records:
    print(record['source_y'],[(c['n'],[round(v,2) for v in c['source_mean']],[round(v,2) for v in c['world_mean']]) for c in record['components']])
