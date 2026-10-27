"""Read actual frozen P3 lower vertices, no Blender or geometry mutation."""
from pathlib import Path
import json,struct,hashlib
HERE=Path(__file__).resolve().parent;ROOT=HERE.parents[3]
p=ROOT/'assets/v3/candidates/rising_seal_p3/rising_seal_p3.glb';blob=p.read_bytes();sha=hashlib.sha256(blob).hexdigest()
assert sha=='e3103cb59810b3703b298450f9047e32bd85fa4e7940cd0188c0660703e8989b'
n=struct.unpack_from('<I',blob,12)[0];g=json.loads(blob[20:20+n]);binary=blob[28+n:]
def positions(i):
 a=g['accessors'][i];v=g['bufferViews'][a['bufferView']];assert a['type']=='VEC3' and a['componentType']==5126;off=v.get('byteOffset',0)+a.get('byteOffset',0);stride=v.get('byteStride',12)
 return [struct.unpack_from('<3f',binary,off+j*stride) for j in range(a['count'])]
out=[]
parents={c:i for i,n in enumerate(g['nodes']) for c in n.get('children',[])}
for i,node in enumerate(g['nodes']):
 if 'mesh' not in node:continue
 ancestry=[];j=i
 while True:
  ancestry.append(g['nodes'][j])
  if j not in parents:break
  j=parents[j]
 # Current exporter applied all mesh transforms; refuse to guess a changed contract.
 for x in ancestry:
  assert x.get('translation',[0,0,0])==[0,0,0] and x.get('scale',[1,1,1])==[1,1,1] and x.get('rotation',[0,0,0,1])==[0,0,0,1] and 'matrix' not in x
 points=[v for pr in g['meshes'][node['mesh']]['primitives'] for v in positions(pr['attributes']['POSITION'])]
 bottom=sorted(set(v for v in points if abs(v[1]+2.5)<1e-6))
 if bottom:out.append({'mesh':node['name'],'local_gate_vertices':[list(v) for v in bottom]})
allp=[p for it in out for p in it['local_gate_vertices']]
assert allp and all(abs(p[0])<=.5+1e-6 and abs(p[2])<=3.5+1e-6 for p in allp)
report={'source':p.relative_to(ROOT).as_posix(),'sha256':sha,'local_gate_bottom_y':-2.5,'gate_closed_world_y':5.4,'world_contact_y':2.9,'inside_nominal_1x7_footprint':True,'vertex_count':len(allp),'groups':out,'note':'Actual lower source vertices, not a complete dynamic contact certificate. Foundation ray checks use these plus full conservative nominal footprint.'}
(HERE/'door_bottom_contact.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n',encoding='utf-8');print(len(allp),'actual lower vertices recorded')
